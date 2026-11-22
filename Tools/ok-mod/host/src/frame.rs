//! Per-frame mod calls (feature `frame`, work item 11, Docs/OK_MOD_S11_FRAME.md). Not through abi_stable: a mod that
//! takes frames exports the plain C function `ok_mod_frame` (`ok_mod_sdk::ok_mod_frame!`), found next to its root module.
//! The game hands `okm_frame` to ok-extract (`ok_set_mod_frame`), which calls it once per character per frame from its
//! worker threads with an `OkModFrame` (Tools/ok-extract/src/mod_frame.rs); this passes it to every enabled mod's
//! function in load order.
//!
//! Budget (plan section 6.8): each call of each mod is timed. Over budget (default 0.5 ms, `okm_frame_budget`) the
//! log warns (first time, then every 100th); `OVERRUN_LIMIT` frames over budget in a row, or a panic, and the mod's
//! frame function is not called again this session (its other hooks keep working).

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, RwLock};

use ok_mod_api::LogLevel;

use crate::LogSink;

/// What the mod exports: returns bit 0 when it changed bones, `PANICKED` when it panicked (the SDK's wrapper).
pub type ModFrameFn = unsafe extern "C" fn(frame: *mut c_void) -> u32;
pub const SYMBOL: &[u8] = b"ok_mod_frame\0";
pub const PANICKED: u32 = 0x8000_0000;
pub const OVERRUN_LIMIT: u32 = 30;
/// `OkModFrame` starts with `struct_size: u32, version: u32` (Tools/ok-extract/src/mod_frame.rs). The host knows
/// version 1, which is at least `FRAME_V1_SIZE` bytes; any other frame is passed to nobody.
pub const FRAME_VERSION: u32 = 1;
pub const FRAME_V1_SIZE: u32 = 80;
static BAD_FRAME: AtomicBool = AtomicBool::new(false);

pub(crate) struct FrameMod {
    pub(crate) id: String,
    f: ModFrameFn,
    overruns: AtomicU32,
    over_total: AtomicU64,
    calls: AtomicU64,
    worst_us: AtomicU64,
    off: AtomicBool,
}

static MODS: RwLock<Vec<Arc<FrameMod>>> = RwLock::new(Vec::new());
static BUDGET_US: AtomicU64 = AtomicU64::new(500);
static LOG: RwLock<Option<LogSink>> = RwLock::new(None);

fn log(level: LogLevel, id: &str, text: &str) {
    if let Ok(g) = LOG.read() {
        if let Some(l) = g.as_ref() {
            l(level, id, text);
        }
    }
}

/// The mod DLL's `ok_mod_frame`, if it exports one. The library stays loaded (the host never unloads mods).
pub(crate) fn find(dll: &std::path::Path) -> Option<ModFrameFn> {
    // SAFETY: the DLL was already loaded and checked by open_dll; loading it again only adds a reference.
    unsafe {
        let lib = ok_mod_api::abi_stable::library::RawLibrary::load_at(dll).ok()?;
        let f = lib.get::<ModFrameFn>(SYMBOL).ok().map(|s| *s);
        std::mem::forget(lib);
        f
    }
}

/// Replaces the list of mods taking frames (enabled ones, load order). Their counters start over.
pub(crate) fn publish(list: Vec<(String, ModFrameFn)>, sink: &LogSink) {
    if let Ok(mut g) = LOG.write() {
        *g = Some(sink.clone());
    }
    let old: Vec<Arc<FrameMod>> = MODS.read().map(|g| g.clone()).unwrap_or_default();
    let mods = list
        .into_iter()
        .map(|(id, f)| {
            // A mod still loaded keeps its record (and whether it was stopped for overrunning).
            old.iter()
                .find(|m| m.id == id && m.f as usize == f as usize)
                .cloned()
                .unwrap_or_else(|| Arc::new(FrameMod { id, f, overruns: AtomicU32::new(0), over_total: AtomicU64::new(0), calls: AtomicU64::new(0), worst_us: AtomicU64::new(0), off: AtomicBool::new(false) }))
        })
        .collect();
    if let Ok(mut g) = MODS.write() {
        *g = mods;
    }
}

pub(crate) fn clear() {
    if let Ok(mut g) = MODS.write() {
        g.clear();
    }
}

/// Mods taking frames and their counters, for `{"op":"frame_stats"}`.
pub(crate) fn stats() -> serde_json::Value {
    let mods = MODS.read().map(|g| g.clone()).unwrap_or_default();
    serde_json::json!({
        "budget_us": BUDGET_US.load(Ordering::Relaxed),
        "mods": mods.iter().map(|m| serde_json::json!({
            "id": m.id, "calls": m.calls.load(Ordering::Relaxed), "over_budget": m.over_total.load(Ordering::Relaxed),
            "worst_us": m.worst_us.load(Ordering::Relaxed), "stopped": m.off.load(Ordering::Relaxed),
        })).collect::<Vec<_>>(),
    })
}

/// Sets the per-mod per-call budget in microseconds (0 = the default 500).
#[no_mangle]
pub extern "C" fn okm_frame_budget(us: u64) {
    BUDGET_US.store(if us == 0 { 500 } else { us }, Ordering::Relaxed);
}

/// One character's frame (ok-extract's `OkModFrameFn`): every enabled mod's `ok_mod_frame` in load order. Returns bit 0
/// when any changed the bones. With a null frame, the number of mods taking frames. Any thread, several characters at
/// once.
///
/// # Safety
/// `frame` points at a valid `OkModFrame` for the call (Tools/ok-extract/src/mod_frame.rs).
#[no_mangle]
pub unsafe extern "C" fn okm_frame(frame: *mut c_void) -> u32 {
    let Ok(mods) = MODS.read() else { return 0 };
    // Null asks how many mods take frames (ok-extract skips building a frame nobody reads).
    if frame.is_null() {
        return mods.iter().filter(|m| !m.off.load(Ordering::Relaxed)).count() as u32;
    }
    if mods.is_empty() {
        return 0;
    }
    let (size, version) = { let head = frame as *const u32; (*head, *head.add(1)) };
    if version != FRAME_VERSION || size < FRAME_V1_SIZE {
        if !BAD_FRAME.swap(true, Ordering::Relaxed) {
            log(LogLevel::Error, "host", &format!("frame version {version} size {size}: this host reads version {FRAME_VERSION} (at least {FRAME_V1_SIZE} bytes); frames are not passed on"));
        }
        return 0;
    }
    let budget = BUDGET_US.load(Ordering::Relaxed);
    let mut changed = 0u32;
    for m in mods.iter() {
        if m.off.load(Ordering::Relaxed) {
            continue;
        }
        let start = std::time::Instant::now();
        let r = (m.f)(frame);
        let us = start.elapsed().as_micros() as u64;
        m.calls.fetch_add(1, Ordering::Relaxed);
        m.worst_us.fetch_max(us, Ordering::Relaxed);
        if r & PANICKED != 0 {
            m.off.store(true, Ordering::Relaxed);
            log(LogLevel::Error, &m.id, "frame function panicked: not called again this session");
            continue;
        }
        changed |= r & 1;
        if us > budget {
            let total = m.over_total.fetch_add(1, Ordering::Relaxed) + 1;
            let run = m.overruns.fetch_add(1, Ordering::Relaxed) + 1;
            if total == 1 || total % 100 == 0 {
                log(LogLevel::Warn, &m.id, &format!("frame took {us} us, budget {budget} us ({total} time(s) over)"));
            }
            if run >= OVERRUN_LIMIT {
                m.off.store(true, Ordering::Relaxed);
                log(LogLevel::Error, &m.id, &format!("frame over budget {run} times in a row: not called again this session"));
            }
        } else {
            m.overruns.store(0, Ordering::Relaxed);
        }
    }
    changed
}

/// A mod that panicked elsewhere: its frame function is not called again either.
pub(crate) fn clear_one(id: &str) {
    if let Ok(g) = MODS.read() {
        for m in g.iter().filter(|m| m.id == id) {
            m.off.store(true, Ordering::Relaxed);
        }
    }
}

/// `stats()` for tests and tools.
pub fn stats_json() -> serde_json::Value {
    stats()
}
