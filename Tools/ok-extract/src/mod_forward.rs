//! ok-extract inside the game talks to the game's one OK mod host instead of loading its own
//! (Docs/OK_MOD_HOOK_INVENTORY.md §5.2): Unreal hands over a dispatch function with
//! `ok_set_mod_dispatch`, and hooks that run here (card conversion, texture post-processing) send
//! their requests through it. Without it (the ok-extract CLI, tests) there is no host and hooks are
//! skipped.
//!
//! A separate setter rather than a new `OkUnrealBindings` field: several Unreal modules call
//! `ok_register_bindings` with their own bindings, and the last one would wipe the dispatcher.

use std::ffi::{c_char, CStr, CString};
use std::sync::Mutex;

/// One mod host request (`okm_dispatch` JSON, Tools/ok-mod/host/include/ok_mod_host.h); returns the
/// answer as UTF-8 owned by the host (released with the matching free function), or null.
pub type OkModDispatchFn = unsafe extern "C" fn(request_json: *const c_char) -> *const c_char;
pub type OkModFreeFn = unsafe extern "C" fn(text: *const c_char);

#[derive(Clone, Copy)]
struct Forward {
    dispatch: OkModDispatchFn,
    free: OkModFreeFn,
}

static FORWARD: Mutex<Option<Forward>> = Mutex::new(None);

/// Sets (or, with a null function, clears) the game's mod host dispatcher.
///
/// # Safety
/// Both functions must stay callable from any thread until cleared.
#[no_mangle]
pub unsafe extern "C" fn ok_set_mod_dispatch(dispatch: Option<OkModDispatchFn>, free: Option<OkModFreeFn>) {
    let value = match (dispatch, free) {
        (Some(dispatch), Some(free)) => Some(Forward { dispatch, free }),
        _ => None,
    };
    if let Ok(mut g) = FORWARD.lock() {
        *g = value;
    }
}

/// Whether a mod host is reachable from here.
pub fn available() -> bool {
    FORWARD.lock().map(|g| g.is_some()).unwrap_or(false)
}

/// Sends one request to the game's mod host; `None` when there is none or it refused.
pub fn dispatch(request_json: &str) -> Option<String> {
    let forward = (*FORWARD.lock().ok()?)?;
    let request = CString::new(request_json).ok()?;
    unsafe {
        let answer = (forward.dispatch)(request.as_ptr());
        if answer.is_null() {
            return None;
        }
        let text = CStr::from_ptr(answer).to_string_lossy().into_owned();
        (forward.free)(answer);
        Some(text)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe extern "C" fn echo(req: *const c_char) -> *const c_char {
        let text = CStr::from_ptr(req).to_string_lossy();
        CString::new(format!("{{\"echo\":{text}}}")).unwrap().into_raw()
    }
    unsafe extern "C" fn release(text: *const c_char) {
        drop(CString::from_raw(text as *mut c_char));
    }

    #[test]
    fn forwards_and_clears() {
        unsafe { ok_set_mod_dispatch(None, None) };
        assert!(!available());
        assert_eq!(dispatch("{}"), None);
        unsafe { ok_set_mod_dispatch(Some(echo), Some(release)) };
        assert!(available());
        assert_eq!(dispatch(r#"{"op":"list"}"#).as_deref(), Some(r#"{"echo":{"op":"list"}}"#));
        unsafe { ok_set_mod_dispatch(None, None) };
        assert!(!available());
    }
}
