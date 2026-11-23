//! The flat C ABI Unreal uses (`include/ok_mod_host.h`), loaded like ok_rules.dll
//! (LoadLibrary + GetProcAddress, `Source/OpenKoikatsu/OKStreetRules.cpp`). Strings are UTF-8 JSON;
//! every returned string is released with `okm_free`; nothing ever unwinds into the caller.

use std::cell::RefCell;
use std::collections::HashSet;
use std::ffi::{c_char, c_void, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use ok_mod_api::{LogLevel, Reply};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{config, lock, HostConfig, LogSink, ModHost, ModReply};

/// Bumped when a function's signature or the meaning of a request changes.
pub const OKM_ABI_VERSION: u32 = 1;

pub type OkmLogFn = Option<unsafe extern "C" fn(user: *mut c_void, level: i32, mod_id: *const c_char, message: *const c_char)>;

pub struct OkmHost {
    host: Mutex<ModHost>,
}

thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = const { RefCell::new(None) };
}

fn set_error(e: String) {
    LAST_ERROR.with(|l| *l.borrow_mut() = Some(e));
}

fn to_c(s: String) -> *const c_char {
    CString::new(s.replace('\0', " ")).map(|c| c.into_raw() as *const c_char).unwrap_or(std::ptr::null())
}

unsafe fn from_c<'a>(p: *const c_char) -> Result<&'a str, String> {
    if p.is_null() {
        return Err("null string".into());
    }
    CStr::from_ptr(p).to_str().map_err(|e| format!("not UTF-8: {e}"))
}

fn guarded<T>(fallback: T, body: impl FnOnce() -> Result<T, String>) -> T {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => {
            set_error(e);
            fallback
        }
        Err(_) => {
            set_error("ok_mod_host: internal panic".into());
            fallback
        }
    }
}

struct UserPtr(*mut c_void);
// The caller promises the log callback may be called from any thread with this pointer.
unsafe impl Send for UserPtr {}
unsafe impl Sync for UserPtr {}

#[derive(Deserialize)]
struct OpenConfig {
    mods_dir: PathBuf,
    #[serde(default)]
    config_dir: Option<PathBuf>,
    target: String,
    #[serde(default)]
    no_mods: bool,
    #[serde(default)]
    disabled: Vec<String>,
    #[serde(default)]
    dev: bool,
}

#[no_mangle]
pub extern "C" fn okm_abi_version() -> u32 {
    OKM_ABI_VERSION
}

/// # Safety
/// `config_json` is a NUL-terminated UTF-8 string; `log` (may be null) is callable with `user` from
/// any thread until `okm_close`.
#[no_mangle]
pub unsafe extern "C" fn okm_open(config_json: *const c_char, log: OkmLogFn, user: *mut c_void) -> *mut OkmHost {
    guarded(std::ptr::null_mut(), || {
        let cfg: OpenConfig = serde_json::from_str(from_c(config_json)?).map_err(|e| format!("okm_open config: {e}"))?;
        let user = Arc::new(UserPtr(user));
        let sink: LogSink = Arc::new(move |level: LogLevel, id: &str, message: &str| {
            let Some(f) = log else { return };
            let (Ok(id), Ok(message)) = (CString::new(id.replace('\0', " ")), CString::new(message.replace('\0', " "))) else { return };
            let user = &user;
            unsafe { f(user.0, level as i32, id.as_ptr(), message.as_ptr()) };
        });
        let host = ModHost::open(
            HostConfig {
                mods_dir: cfg.mods_dir,
                config_dir: cfg.config_dir,
                target: cfg.target,
                no_mods: cfg.no_mods,
                disabled: cfg.disabled.into_iter().collect::<HashSet<_>>(),
                dev: cfg.dev,
            },
            sink,
        );
        Ok(Box::into_raw(Box::new(OkmHost { host: Mutex::new(host) })))
    })
}

fn reply_json(r: &Result<Reply, String>) -> Value {
    match r {
        Ok(Reply::Text(t)) => json!({"ok": true, "text": t.as_str()}),
        Ok(Reply::Json(j)) => json!({"ok": true, "json": serde_json::from_str::<Value>(j.as_str()).unwrap_or(Value::String(j.to_string()))}),
        Ok(_) => json!({"ok": true}),
        Err(e) => json!({"ok": false, "error": e}),
    }
}

fn replies_json(rs: Vec<ModReply>) -> Value {
    Value::Array(
        rs.into_iter()
            .map(|r| {
                let mut v = reply_json(&r.result);
                v["mod"] = r.id.into();
                v
            })
            .collect(),
    )
}

fn str_field<'a>(req: &'a Value, key: &str) -> Result<&'a str, String> {
    req.get(key).and_then(Value::as_str).ok_or_else(|| format!("missing string \"{key}\""))
}

/// Handles one JSON request; see `include/ok_mod_host.h` for the list.
pub fn handle(host: &mut ModHost, req: &Value) -> Result<Value, String> {
    let op = str_field(req, "op")?;
    Ok(match op {
        "list" => json!({
            "host_version": crate::HOST_VERSION,
            "api_version": ok_mod_api::API_VERSION,
            "abi_version": ok_mod_api::ABI_VERSION,
            "target": host.target(),
            "modes": host.modes(),
            "no_mods": host.no_mods(),
            "mods": host.statuses(),
        }),
        "event" => {
            let mode = str_field(req, "mode")?;
            let replies = match str_field(req, "event")? {
                // Also loads the mods for that mode when this process had not run it yet.
                "mode_enter" => host.enter_mode(mode),
                "mode_exit" => host.exit_mode(mode),
                other => return Err(format!("unknown event \"{other}\"")),
            };
            json!({"replies": replies_json(replies)})
        }
        "command" => {
            let args = req.get("args").and_then(Value::as_str).unwrap_or("");
            let (id, name) = match req.get("command").and_then(Value::as_str) {
                Some(full) => ModHost::split_command(full).ok_or_else(|| format!("\"{full}\" is not mod.<id>.<name>"))?,
                None => (str_field(req, "mod")?, str_field(req, "name")?),
            };
            reply_json(&host.command(id, name, args))
        }
        "config" => {
            let entries = host.config(str_field(req, "mod")?)?;
            Value::Array(
                entries
                    .into_iter()
                    .map(|(e, v)| {
                        json!({
                            "key": e.key,
                            "type": config::type_name(&e.default),
                            "value": config::to_json(&v),
                            "default": config::to_json(&e.default),
                            "min": e.min,
                            "max": e.max,
                            "description_id": e.description_id,
                        })
                    })
                    .collect(),
            )
        }
        "config_set" => {
            let value = req.get("value").and_then(config::from_json).ok_or("missing or unsupported \"value\"")?;
            match host.set_config(str_field(req, "mod")?, str_field(req, "key")?, value) {
                Ok(()) => json!({"ok": true}),
                Err(e) => json!({"ok": false, "error": e}),
            }
        }
        "content" => json!({"mods": host.content()}),
        // {"op":"frame_stats"}: mods taking frames, their calls, overruns, worst call and whether they were stopped.
        #[cfg(feature = "frame")]
        "frame_stats" => crate::frame::stats(),
        // {"op":"frame_budget","us"}: the per-mod per-call budget (0 = the default 500 us).
        #[cfg(feature = "frame")]
        "frame_budget" => {
            crate::frame::okm_frame_budget(req.get("us").and_then(Value::as_u64).unwrap_or(0));
            crate::frame::stats()
        }
        "reload" => match host.reload(str_field(req, "mod")?) {
            Ok(text) => json!({"ok": true, "text": text}),
            Err(e) => json!({"ok": false, "error": e}),
        },
        // {"op":"hook","hook","payload","mods"?}: a named hook (Event::Hook) to its subscribers, or to the listed mods.
        // {"op":"subscribers","hook"}: who would get that hook, so callers skip preparing a payload nobody reads.
        "subscribers" => json!({"mods": host.subscribers(str_field(req, "hook")?)}),
        "hook" => {
            let name = str_field(req, "hook")?;
            let payload = req.get("payload").cloned().unwrap_or(Value::Null).to_string();
            let replies = match req.get("mods").and_then(Value::as_array) {
                Some(ids) => ids.iter().filter_map(Value::as_str)
                    .map(|id| ModReply { id: id.into(), result: host.hook_one(id, name, &payload) })
                    .collect(),
                None => host.hook(name, &payload),
            };
            json!({"replies": replies_json(replies)})
        }
        // {"op":"hotkeys"}: the mod hotkeys the game watches (host/src/keys.rs), bound or not.
        "hotkeys" => json!({"keys": host.hotkeys().iter().map(crate::keys::Hotkey::json).collect::<Vec<_>>()}),
        // {"op":"key","chord","mode"}: a chord pressed in a mode; the hook key.<id>.<name> of every hotkey bound to it.
        "key" => {
            let replies = host.key(str_field(req, "chord")?, req.get("mode").and_then(Value::as_str).unwrap_or(""));
            json!({"replies": replies_json(replies)})
        }
        "disable" => match host.disable(str_field(req, "mod")?) {
            Ok(()) => json!({"ok": true}),
            Err(e) => json!({"ok": false, "error": e}),
        },
        // Cards, the reader and conversion (host/src/card.rs, Docs/OK_MOD_HOOKS.md).
        other if crate::card::OPS.contains(&other) => crate::card::handle(host, other, req)?,
        other => return Err(format!("unknown op \"{other}\"")),
    })
}

/// # Safety
/// `h` comes from `okm_open`; `request_json` is a NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn okm_dispatch(h: *mut OkmHost, request_json: *const c_char) -> *const c_char {
    guarded(std::ptr::null(), || {
        let h = h.as_ref().ok_or("null host")?;
        let req: Value = serde_json::from_str(from_c(request_json)?).map_err(|e| format!("request: {e}"))?;
        let answer = handle(&mut lock(&h.host), &req)?;
        Ok(to_c(answer.to_string()))
    })
}

/// # Safety
/// `text` comes from this library (or is null).
#[no_mangle]
pub unsafe extern "C" fn okm_free(text: *const c_char) {
    if !text.is_null() {
        let _ = catch_unwind(|| drop(CString::from_raw(text as *mut c_char)));
    }
}

#[no_mangle]
pub extern "C" fn okm_last_error() -> *const c_char {
    LAST_ERROR.with(|l| l.borrow().clone()).map(to_c).unwrap_or(std::ptr::null())
}

/// # Safety
/// `h` comes from `okm_open` and is not used afterwards.
#[no_mangle]
pub unsafe extern "C" fn okm_close(h: *mut OkmHost) {
    if !h.is_null() {
        let _ = catch_unwind(AssertUnwindSafe(|| {
            let host = Box::from_raw(h);
            lock(&host.host).close();
        }));
    }
}
