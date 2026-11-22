//! Loads real mod DLLs: `hello`, the panic fixture, the bad-layout fixture, mods built by other rustc
//! versions and a `panic = "abort"` build (Docs/OK_MOD_FRAMEWORK_PLAN.md §15.4 item 1).
//!
//! The fixtures are built by this test with a nested cargo into `target/fixtures-*` (other
//! toolchains through `rustup run <toolchain> cargo`); a toolchain that is not installed is skipped
//! with a message.

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use ok_mod_host::ok_mod_api::{ConfigValue, Event, LogLevel, Reply};
use ok_mod_host::{ffi, HostConfig, LogSink, ModHost, ModStatus};

const HELLO: &str = "org.openkoikatsu.hello";
const PANIC: &str = "org.openkoikatsu.test.panic";
const BAD: &str = "org.openkoikatsu.test.badlayout";

/// Old and new toolchains next to the default one (`rustup toolchain list` on this machine).
const OTHER_TOOLCHAINS: &[&str] = &["1.92.0", "1.98.1"];

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

/// Tests share the panic fixture's environment variable; run them one at a time.
fn serial() -> MutexGuard<'static, ()> {
    static M: Mutex<()> = Mutex::new(());
    M.lock().unwrap_or_else(|e| e.into_inner())
}

enum Build {
    Current,
    Toolchain(&'static str),
    PanicAbort,
}

/// Builds the three fixture crates; returns the folder with their DLLs, or `None` when the
/// toolchain is not installed.
fn build(kind: Build) -> Option<PathBuf> {
    static DONE: OnceLock<Mutex<HashMap<String, Option<PathBuf>>>> = OnceLock::new();
    let key = match kind {
        Build::Current => "current".to_string(),
        Build::Toolchain(t) => t.to_string(),
        Build::PanicAbort => "panic-abort".to_string(),
    };
    let mut done = DONE.get_or_init(Default::default).lock().unwrap();
    if let Some(r) = done.get(&key) {
        return r.clone();
    }
    let target_dir = workspace().join("target").join(format!("fixtures-{key}"));
    let mut cmd = match kind {
        Build::Toolchain(t) => {
            let ok = Command::new("rustup").args(["run", t, "rustc", "--version"]).env_remove("RUSTUP_TOOLCHAIN").output().is_ok_and(|o| o.status.success());
            if !ok {
                eprintln!("toolchain {t} is not installed; skipping it");
                done.insert(key, None);
                return None;
            }
            let mut c = Command::new("rustup");
            c.args(["run", t, "cargo"]);
            c
        }
        _ => Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into())),
    };
    cmd.args(["build", "-j", "8", "-p", "ok-mod-hello", "-p", "ok-mod-fixture-panic", "-p", "ok-mod-fixture-bad-layout", "--target-dir"])
        .arg(&target_dir)
        .current_dir(workspace());
    if let Build::PanicAbort = kind {
        cmd.args(["--config", "profile.dev.panic=\"abort\""]);
    }
    for v in ["RUSTUP_TOOLCHAIN", "RUSTC", "RUSTDOC", "RUSTC_WRAPPER", "RUSTC_WORKSPACE_WRAPPER", "CARGO_TARGET_DIR", "CARGO_BUILD_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
        cmd.env_remove(v);
    }
    let out = cmd.output().expect("run cargo");
    assert!(out.status.success(), "fixture build ({key}) failed:\n{}", String::from_utf8_lossy(&out.stderr));
    let dir = target_dir.join("debug");
    done.insert(key, Some(dir.clone()));
    Some(dir)
}

struct Scratch(PathBuf);

impl Scratch {
    fn new(name: &str) -> Scratch {
        let dir = workspace().join("target").join("test-mods").join(format!("{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("Mods")).unwrap();
        Scratch(dir)
    }
    fn mods(&self) -> PathBuf {
        self.0.join("Mods")
    }
    fn config(&self) -> PathBuf {
        self.0.join("config")
    }
    /// Copies a fixture crate's mod.toml (optionally edited) and its DLL into `Mods/<folder>/`.
    fn install(&self, folder: &str, crate_dir: &str, dll_dir: &Path, dll: &str, edit: impl Fn(String) -> String) {
        let dest = self.mods().join(folder);
        std::fs::create_dir_all(&dest).unwrap();
        let text = std::fs::read_to_string(workspace().join(crate_dir).join("mod.toml")).unwrap();
        std::fs::write(dest.join("mod.toml"), edit(text)).unwrap();
        std::fs::copy(dll_dir.join(dll), dest.join(dll)).unwrap();
    }
    fn hello(&self, dll_dir: &Path) {
        self.install("hello", "examples/hello", dll_dir, "ok_hello.dll", |t| t);
    }
    fn panic(&self, dll_dir: &Path) {
        self.install("panic", "fixtures/panic-mod", dll_dir, "ok_fixture_panic.dll", |t| t);
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        // The DLLs stay loaded (abi_stable never unloads), so their copies cannot be deleted now.
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

type Logs = Arc<Mutex<Vec<(LogLevel, String, String)>>>;

fn open(scratch: &Scratch, target: &str) -> (ModHost, Logs) {
    let logs: Logs = Default::default();
    let sink_logs = logs.clone();
    let sink: LogSink = Arc::new(move |l, id, m| sink_logs.lock().unwrap().push((l, id.to_string(), m.to_string())));
    let mut cfg = HostConfig::new(scratch.mods(), target);
    cfg.config_dir = Some(scratch.config());
    (ModHost::open(cfg, sink), logs)
}

fn status<'a>(all: &'a [ModStatus], id: &str) -> &'a ModStatus {
    all.iter().find(|s| s.id == id).unwrap_or_else(|| panic!("no status for {id}: {all:?}"))
}

fn logged(logs: &Logs, id: &str, needle: &str) -> bool {
    logs.lock().unwrap().iter().any(|(_, i, m)| i == id && m.contains(needle))
}

#[test]
fn hello_loads_answers_and_keeps_config() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("hello");
    s.hello(&dlls);

    let (mut host, logs) = open(&s, "reader");
    let st = host.statuses();
    let hello = status(&st, HELLO);
    assert_eq!(hello.state, "enabled", "{hello:?}");
    assert!(hello.rustc.as_deref().unwrap().starts_with("rustc "), "{hello:?}");
    assert_eq!(hello.commands, vec![format!("mod.{HELLO}.ping")]);
    assert!(logged(&logs, HELLO, "hello from hello"), "{:?}", logs.lock().unwrap());
    assert!(logged(&logs, "", "1 mod(s) enabled: org.openkoikatsu.hello"));

    assert_eq!(host.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 1 (hello)".into()));
    assert_eq!(host.command(HELLO, "ping", "x").unwrap(), Reply::Text("pong 2 (hello) x".into()));
    assert!(host.command(HELLO, "nope", "").is_err());
    assert_eq!(ModHost::split_command("mod.org.openkoikatsu.hello.ping"), Some((HELLO, "ping")));

    let replies = host.dispatch(&Event::ModeEnter { mode: "reader".into() });
    assert_eq!(replies.len(), 1);
    assert!(logged(&logs, HELLO, "entered mode reader"));
    // Not subscribed: nobody is called.
    assert!(host.dispatch(&Event::ConfigChanged { key: "greeting".into() }).is_empty());

    assert!(host.set_config(HELLO, "greeting", ConfigValue::Int(3)).is_err());
    host.set_config(HELLO, "greeting", ConfigValue::Text("hi".into())).unwrap();
    assert_eq!(host.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 3 (hi)".into()));
    host.close();
    assert!(s.config().join(format!("{HELLO}.toml")).is_file());

    // Saved value survives a restart; the mod also runs in another mode.
    let (mut again, logs) = open(&s, "studio");
    assert!(logged(&logs, HELLO, "hi from hello"));
    assert_eq!(again.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 1 (hi)".into()));
    let cfg = again.config(HELLO).unwrap();
    assert_eq!(cfg[0].1, ConfigValue::Text("hi".into()));
}

#[test]
fn no_mods_and_disabled_and_wrong_target() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("nomods");
    s.hello(&dlls);
    s.install("studio-only", "examples/hello", &dlls, "ok_hello.dll", |t| {
        t.replace("org.openkoikatsu.hello", "org.openkoikatsu.studioonly").replace("targets = [\"reader\", \"studio\", \"pair\", \"street\", \"extract\"]", "targets = [\"studio\"]")
    });

    let mut cfg = HostConfig::new(s.mods(), "reader");
    cfg.no_mods = true;
    let host = ModHost::open(cfg, Arc::new(|_, _, _| {}));
    assert!(host.statuses().is_empty());

    let mut cfg = HostConfig::new(s.mods(), "reader");
    cfg.disabled.insert(HELLO.into());
    let host = ModHost::open(cfg, Arc::new(|_, _, _| {}));
    let st = host.statuses();
    assert_eq!(status(&st, HELLO).state, "skipped");
    assert_eq!(status(&st, "org.openkoikatsu.studioonly").state, "skipped");
}

#[test]
fn panic_disables_only_that_mod() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("panic");
    s.hello(&dlls);
    s.panic(&dlls);

    for at in ["command", "create", "register", "enabled", "mode_enter"] {
        std::env::set_var("OK_MOD_TEST_PANIC_AT", at);
        let (mut host, logs) = open(&s, "reader");
        if at == "command" {
            assert_eq!(status(&host.statuses(), PANIC).state, "enabled");
            let err = host.command(PANIC, "boom", "").unwrap_err();
            assert!(err.contains("deliberate panic in command"), "{err}");
            assert!(err.contains("panic-mod"), "panic location expected in: {err}");
        }
        if at == "mode_enter" {
            host.dispatch(&Event::ModeEnter { mode: "reader".into() });
        }
        let st = host.statuses();
        let p = status(&st, PANIC);
        assert_eq!(p.state, "faulted", "panic at {at}: {p:?}");
        assert!(p.reason.as_deref().unwrap().contains(&format!("deliberate panic in {at}")), "{p:?}");
        assert!(logged(&logs, PANIC, "disabled after a panic") || at == "create" || at == "register", "{at}");
        // The other mod is untouched, the faulted one is never called again.
        assert_eq!(status(&st, HELLO).state, "enabled");
        assert!(host.command(HELLO, "ping", "").is_ok());
        assert!(host.command(PANIC, "boom", "").is_err());
        host.dispatch(&Event::ModeEnter { mode: "reader".into() });
    }
    std::env::remove_var("OK_MOD_TEST_PANIC_AT");
}

#[test]
fn incompatible_dlls_are_refused() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("refuse");
    s.hello(&dlls);
    // abi_stable layout check.
    s.install("bad", "fixtures/bad-layout", &dlls, "ok_fixture_bad_layout.dll", |t| t);
    // mod.toml asks for another API version.
    s.install("newapi", "examples/hello", &dlls, "ok_hello.dll", |t| t.replace("org.openkoikatsu.hello", "org.openkoikatsu.newapi").replace("api = \"0.1\"", "api = \"0.2\""));
    // mod.toml and the DLL disagree.
    s.install("mismatch", "examples/hello", &dlls, "ok_hello.dll", |t| t.replace("org.openkoikatsu.hello", "org.openkoikatsu.mismatch"));
    // DLL missing.
    s.install("nodll", "examples/hello", &dlls, "ok_hello.dll", |t| t.replace("org.openkoikatsu.hello", "org.openkoikatsu.nodll").replace("ok_hello.dll", "missing.dll"));

    let (host, _logs) = open(&s, "reader");
    let st = host.statuses();
    let bad = status(&st, BAD);
    assert_eq!(bad.state, "rejected");
    assert!(bad.reason.as_deref().unwrap().contains("not a compatible ok_mod DLL"), "{bad:?}");
    let newapi = status(&st, "org.openkoikatsu.newapi");
    assert!(newapi.state == "rejected" && newapi.reason.as_deref().unwrap().contains("needs ok-mod-api 0.2"), "{newapi:?}");
    let mismatch = status(&st, "org.openkoikatsu.mismatch");
    assert!(mismatch.state == "rejected" && mismatch.reason.as_deref().unwrap().contains("but mod.toml says"), "{mismatch:?}");
    let nodll = status(&st, "org.openkoikatsu.nodll");
    assert!(nodll.state == "rejected" && nodll.reason.as_deref().unwrap().contains("missing"), "{nodll:?}");
    assert_eq!(status(&st, HELLO).state, "enabled");
}

#[test]
fn panic_abort_build_is_refused() {
    let _g = serial();
    let dlls = build(Build::PanicAbort).unwrap();
    let s = Scratch::new("abort");
    s.hello(&dlls);
    let (host, _logs) = open(&s, "reader");
    let st = host.statuses();
    let h = status(&st, HELLO);
    assert!(h.state == "rejected" && h.reason.as_deref().unwrap().contains("panic = \"abort\""), "{h:?}");
}

#[test]
fn mods_from_other_rustc_versions_load() {
    let _g = serial();
    for tc in OTHER_TOOLCHAINS {
        let Some(dlls) = build(Build::Toolchain(tc)) else { continue };
        let s = Scratch::new(&format!("rustc-{tc}"));
        s.hello(&dlls);
        s.panic(&dlls);
        std::env::set_var("OK_MOD_TEST_PANIC_AT", "command");
        let (mut host, _logs) = open(&s, "reader");
        let st = host.statuses();
        let h = status(&st, HELLO);
        assert_eq!(h.state, "enabled", "{tc}: {h:?}");
        assert!(h.rustc.as_deref().unwrap().contains(tc), "built by {tc}? {h:?}");
        assert_eq!(host.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 1 (hello)".into()));
        // Panic isolation also works across compilers.
        assert!(host.command(PANIC, "boom", "").unwrap_err().contains("deliberate panic"));
        assert_eq!(status(&host.statuses(), PANIC).state, "faulted");
        assert!(host.command(HELLO, "ping", "").is_ok());
        std::env::remove_var("OK_MOD_TEST_PANIC_AT");
        eprintln!("{tc}: {}", h.rustc.as_deref().unwrap());
    }
}

// ---------------------------------------------------------------------------------------------
// The C ABI as Unreal uses it
// ---------------------------------------------------------------------------------------------

static C_LOGS: Mutex<Vec<String>> = Mutex::new(Vec::new());

unsafe extern "C" fn c_log(user: *mut c_void, level: i32, id: *const c_char, message: *const c_char) {
    assert_eq!(user as usize, 0x1234);
    let id = CStr::from_ptr(id).to_string_lossy();
    let message = CStr::from_ptr(message).to_string_lossy();
    C_LOGS.lock().unwrap().push(format!("{level} [{id}] {message}"));
}

fn c_call(h: *mut ffi::OkmHost, req: &str) -> serde_json::Value {
    let req = CString::new(req).unwrap();
    unsafe {
        let out = ffi::okm_dispatch(h, req.as_ptr());
        if out.is_null() {
            let e = ffi::okm_last_error();
            let text = CStr::from_ptr(e).to_string_lossy().into_owned();
            ffi::okm_free(e);
            return serde_json::json!({ "c_error": text });
        }
        let v = serde_json::from_str(&CStr::from_ptr(out).to_string_lossy()).unwrap();
        ffi::okm_free(out);
        v
    }
}

#[test]
fn c_abi_round_trip() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("cabi");
    s.hello(&dlls);
    s.panic(&dlls);
    std::env::set_var("OK_MOD_TEST_PANIC_AT", "command");
    assert_eq!(ffi::okm_abi_version(), 1);
    let cfg = serde_json::json!({"mods_dir": s.mods(), "config_dir": s.config(), "target": "reader"}).to_string();
    let cfg = CString::new(cfg).unwrap();
    let h = unsafe { ffi::okm_open(cfg.as_ptr(), Some(c_log), 0x1234 as *mut c_void) };
    assert!(!h.is_null());

    let list = c_call(h, r#"{"op":"list"}"#);
    assert_eq!(list["target"], "reader");
    let mods = list["mods"].as_array().unwrap();
    assert!(mods.iter().any(|m| m["id"] == HELLO && m["state"] == "enabled" && m["commands"][0] == "mod.org.openkoikatsu.hello.ping"), "{list}");

    let r = c_call(h, r#"{"op":"command","command":"mod.org.openkoikatsu.hello.ping","args":"a b"}"#);
    assert_eq!(r, serde_json::json!({"ok": true, "text": "pong 1 (hello) a b"}));
    let r = c_call(h, r#"{"op":"command","mod":"org.openkoikatsu.test.panic","name":"boom"}"#);
    assert_eq!(r["ok"], false);
    let r = c_call(h, r#"{"op":"event","event":"mode_enter","mode":"studio"}"#);
    assert_eq!(r["replies"].as_array().unwrap().len(), 1, "{r}");
    let r = c_call(h, r#"{"op":"config_set","mod":"org.openkoikatsu.hello","key":"greeting","value":"yo"}"#);
    assert_eq!(r["ok"], true);
    let r = c_call(h, r#"{"op":"config","mod":"org.openkoikatsu.hello"}"#);
    assert_eq!(r[0]["value"], "yo");
    assert_eq!(r[0]["type"], "text");
    let r = c_call(h, r#"{"op":"disable","mod":"org.openkoikatsu.hello"}"#);
    assert_eq!(r["ok"], true);
    let r = c_call(h, r#"{"op":"nonsense"}"#);
    assert!(r["c_error"].as_str().unwrap().contains("unknown op"));
    let list = c_call(h, r#"{"op":"list"}"#);
    let states: Vec<(String, String)> = list["mods"].as_array().unwrap().iter().map(|m| (m["id"].as_str().unwrap().into(), m["state"].as_str().unwrap().into())).collect();
    assert!(states.contains(&(HELLO.into(), "disabled".into())) && states.contains(&(PANIC.into(), "faulted".into())), "{states:?}");
    unsafe { ffi::okm_close(h) };
    std::env::remove_var("OK_MOD_TEST_PANIC_AT");

    let logs = C_LOGS.lock().unwrap();
    assert!(logs.iter().any(|l| l.contains("[org.openkoikatsu.hello] hello from hello")), "{logs:?}");
    assert!(logs.iter().any(|l| l.starts_with("1 [org.openkoikatsu.test.panic] disabled after a panic")), "{logs:?}");
}

#[test]
fn entering_another_mode_loads_its_mods() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("modes");
    s.hello(&dlls);
    // The panic fixture (told not to panic) stands in for a studio-only mod.
    std::env::set_var("OK_MOD_TEST_PANIC_AT", "never");
    s.install("studio-only", "fixtures/panic-mod", &dlls, "ok_fixture_panic.dll", |t| {
        t.replace("targets = [\"reader\", \"studio\", \"pair\", \"street\", \"extract\"]", "targets = [\"studio\"]")
    });
    let (mut host, logs) = open(&s, "street");
    assert_eq!(status(&host.statuses(), "org.openkoikatsu.test.panic").state, "skipped");
    let replies = host.enter_mode("street");
    assert_eq!(replies.len(), 1, "hello subscribed to mode_enter");
    // The same process goes on to the studio: its mods load then, and both subscribers hear of it.
    let replies = host.enter_mode("studio");
    assert_eq!(replies.len(), 2, "{replies:?}");
    assert_eq!(status(&host.statuses(), "org.openkoikatsu.test.panic").state, "enabled");
    assert!(logged(&logs, "org.openkoikatsu.test.panic", "loaded Panic test"));
    assert!(logged(&logs, "", "mode street/studio: 2 mod(s) enabled"));
    assert_eq!(host.modes(), ["street".to_string(), "studio".to_string()]);
    // Entering it again loads nothing twice.
    host.enter_mode("studio");
    assert_eq!(host.statuses().iter().filter(|m| m.state == "enabled").count(), 2);
    assert_eq!(host.exit_mode("studio").len(), 1, "only hello subscribed to mode_exit");
    std::env::remove_var("OK_MOD_TEST_PANIC_AT");
}

#[test]
fn dev_mode_reload_swaps_in_a_fresh_copy() {
    let _g = serial();
    let dlls = build(Build::Current).unwrap();
    let s = Scratch::new("reload");
    s.hello(&dlls);
    let (mut host, _logs) = open(&s, "reader");
    assert!(host.reload(HELLO).unwrap_err().contains("development mode"));
    drop(host);

    let logs: Logs = Default::default();
    let sink_logs = logs.clone();
    let mut cfg = HostConfig::new(s.mods(), "reader");
    cfg.dev = true;
    let mut host = ModHost::open(cfg, Arc::new(move |l, id, m| sink_logs.lock().unwrap().push((l, id.to_string(), m.to_string()))));
    assert_eq!(host.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 1 (hello)".into()));
    assert_eq!(host.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 2 (hello)".into()));
    // The DLL on disk is in use; the reload loads a copy under a new name and starts the mod over.
    let text = host.reload(HELLO).unwrap();
    assert!(text.contains(".reload"), "{text}");
    assert_eq!(host.command(HELLO, "ping", "").unwrap(), Reply::Text("pong 1 (hello)".into()));
    assert_eq!(status(&host.statuses(), HELLO).state, "enabled");
    assert_eq!(logs.lock().unwrap().iter().filter(|(_, id, m)| id == HELLO && m.contains("hello from hello")).count(), 2);
    assert!(std::fs::read_dir(s.mods().join("hello/.reload")).unwrap().count() == 1);
}
