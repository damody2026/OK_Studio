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

/// Enabled mods subscribed to `hook` (none without a host). Ask before building a payload: a hook nobody subscribed
/// to must not slow card opening down (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.7).
pub fn subscribers(hook: &str) -> Vec<String> {
    if !available() {
        return Vec::new();
    }
    let request = serde_json::json!({"op": "subscribers", "hook": hook}).to_string();
    let Some(answer) = dispatch(&request) else { return Vec::new() };
    let value: serde_json::Value = serde_json::from_str(&answer).unwrap_or_default();
    value["mods"].as_array().map(|a| a.iter().filter_map(|v| v.as_str().map(str::to_string)).collect()).unwrap_or_default()
}

/// `material.post_texture`: a part's main texture after all the core's own work (composites, KSOX/KCOX overlays,
/// emblems, Material Editor), for every card kind, before it reaches the session. Payload:
/// `{"slot":"<part role: body, head, hair, clothes_top, accessory...>","part":"<mesh name>","outfit","width","height",
/// "rgba":<address>,"len"}`
/// where `rgba` is the address of `len` bytes of 8-bit RGBA (rows top to bottom), writable in place by the mod for the
/// duration of the call only. Reply `{"changed":true}` when it wrote, so the texture is encoded again.
pub const POST_TEXTURE: &str = "material.post_texture";

/// Runs `material.post_texture` over `png` (PNG or the raw container, crate::teximg) when some mod subscribed;
/// otherwise does nothing. A changed texture is written back in the open path's encoding.
pub fn post_texture(slot: &str, part: &str, outfit: i32, png: &mut Option<Vec<u8>>) {
    let Some(bytes) = png.as_deref() else { return };
    if subscribers(POST_TEXTURE).is_empty() {
        return;
    }
    let image = match crate::teximg::load_from_memory(bytes) {
        Ok(image) => image,
        Err(e) => {
            eprintln!("ok-extract: {POST_TEXTURE} {slot}/{part}: texture not decoded: {e}");
            return;
        }
    };
    let mut rgba = image.to_rgba8();
    let (width, height) = rgba.dimensions();
    let len = rgba.len();
    let payload = serde_json::json!({
        "slot": slot, "part": part, "outfit": outfit, "width": width, "height": height,
        "rgba": rgba.as_mut_ptr() as usize, "len": len,
    });
    let request = serde_json::json!({"op": "hook", "hook": POST_TEXTURE, "payload": payload}).to_string();
    let Some(answer) = dispatch(&request) else { return };
    let value: serde_json::Value = serde_json::from_str(&answer).unwrap_or_default();
    let mut changed = false;
    for reply in value["replies"].as_array().into_iter().flatten() {
        if reply["ok"].as_bool() == Some(true) {
            changed |= reply["json"]["changed"].as_bool() == Some(true);
        } else {
            eprintln!("ok-extract: {POST_TEXTURE} {slot}/{part}: {} failed: {}", reply["mod"], reply["error"]);
        }
    }
    if changed {
        if let Some(encoded) = crate::teximg::encode_rgba(&rgba) {
            *png = Some(encoded);
        }
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

        // material.post_texture (same test: the dispatcher is global). Nobody subscribed: the PNG is left as it is.
        let red = image::RgbaImage::from_pixel(2, 2, image::Rgba([255, 0, 0, 255]));
        let original = crate::texture_bake::encode_png(&red).unwrap();
        let mut png = Some(original.clone());
        unsafe { ok_set_mod_dispatch(Some(nobody), Some(release)) };
        post_texture("body", "o_body_a", 0, &mut png);
        assert_eq!(png.as_deref(), Some(original.as_slice()));
        // A subscriber that turns every pixel green in place.
        unsafe { ok_set_mod_dispatch(Some(painter), Some(release)) };
        post_texture("body", "o_body_a", 0, &mut png);
        let out = image::load_from_memory(png.as_deref().unwrap()).unwrap().to_rgba8();
        assert!(out.pixels().all(|p| p.0 == [0, 255, 0, 255]));

        unsafe { ok_set_mod_dispatch(None, None) };
        assert!(!available());
    }

    unsafe extern "C" fn nobody(req: *const c_char) -> *const c_char {
        let req: serde_json::Value = serde_json::from_str(&CStr::from_ptr(req).to_string_lossy()).unwrap();
        assert_eq!(req["op"], "subscribers", "a hook nobody subscribed to is never sent");
        CString::new(r#"{"mods":[]}"#).unwrap().into_raw()
    }

    unsafe extern "C" fn painter(req: *const c_char) -> *const c_char {
        let req: serde_json::Value = serde_json::from_str(&CStr::from_ptr(req).to_string_lossy()).unwrap();
        let answer = match req["op"].as_str().unwrap() {
            "subscribers" => r#"{"mods":["painter"]}"#.to_string(),
            "hook" => {
                let p = &req["payload"];
                assert_eq!((p["slot"].as_str(), p["width"].as_u64(), p["len"].as_u64()), (Some("body"), Some(2), Some(16)));
                let rgba = std::slice::from_raw_parts_mut(p["rgba"].as_u64().unwrap() as usize as *mut u8, 16);
                for px in rgba.chunks_mut(4) { px.copy_from_slice(&[0, 255, 0, 255]); }
                r#"{"replies":[{"mod":"painter","ok":true,"json":{"changed":true}}]}"#.to_string()
            }
            other => panic!("unexpected op {other}"),
        };
        CString::new(answer).unwrap().into_raw()
    }
}
