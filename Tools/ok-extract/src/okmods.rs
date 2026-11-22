//! Mod data in an OK card (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.2, §6.12): `okMx` (data) and `okMr` (resources), which the
//! core keeps exactly as they are. The codec and the identity rule live in Tools/ok-card-mods, shared with the OK mod
//! host; this module adds what is ok-extract's own:
//!
//! - A remade OK card carries both chunks over (`carry_over`, called from `oklib::keep_identity`).
//! - The open cache (`oklib::session_cache_key`) also hashes the mods enabled in this process and their versions, so an
//!   open built with a mod's hooks is never served to a process without it, or the other way. The list is what the mod
//!   host set (`set_enabled`), else what the game's host answers through `mod_forward` (inside Unreal); with no mod
//!   enabled the key is what it was before mods existed.
use std::sync::RwLock;

pub use ok_card_mods::{
    carry_over, read_data, read_resources, with_data, with_resources, ModData, Requires, Resources, Section, DATA_CHUNK,
    IDENTITY_EXCLUDED, RESOURCE_CHUNK,
};

static ENABLED: RwLock<Option<Vec<(String, String)>>> = RwLock::new(None);

/// The mods enabled in this process with their versions, set by whoever runs the host here (the ok-extract CLI linking
/// it; empty: no mods). Without a call, the game's host is asked (`enabled`).
pub fn set_enabled(mut mods: Vec<(String, String)>) {
    mods.sort();
    mods.dedup();
    *ENABLED.write().unwrap_or_else(|e| e.into_inner()) = Some(mods);
}

/// Whether a mod with these subscriptions can change what an open makes: it takes a hook that runs inside an open
/// (`extract.*`), other than the conversion-only `extract.kkex` / `extract.kkex_keys`. Only those count in the open-cache
/// key: a street or reader mod (birthday, subtitles, profile) changes nothing an open makes, and counting it made every
/// cached open miss once a mod was installed (street heroines whose in-game cold open fails then never loaded; S10).
pub fn changes_opens<'a>(subscriptions: impl IntoIterator<Item = &'a str>) -> bool {
    subscriptions.into_iter().any(|s| s.starts_with("extract.") && s != "extract.kkex" && s != "extract.kkex_keys")
}

/// The enabled mods that can change an open (`changes_opens`), with their versions, sorted: as set, else the game's
/// host's `list` (`state: enabled`), else none.
pub fn enabled() -> Vec<(String, String)> {
    if let Some(set) = ENABLED.read().unwrap_or_else(|e| e.into_inner()).clone() { return set; }
    let Some(answer) = crate::mod_forward::dispatch(r#"{"op":"list"}"#) else { return Vec::new() };
    let Ok(list) = serde_json::from_str::<serde_json::Value>(&answer) else { return Vec::new() };
    let mut out: Vec<(String, String)> = list["mods"].as_array().into_iter().flatten()
        .filter(|m| m["state"] == "enabled")
        .filter(|m| changes_opens(m["subscriptions"].as_array().into_iter().flatten().filter_map(|s| s.as_str())))
        .filter_map(|m| Some((m["id"].as_str()?.to_owned(), m["version"].as_str().unwrap_or_default().to_owned())))
        .collect();
    out.sort();
    out
}

/// `ok_set_enabled_mods`: the game's mod host tells this copy of ok-extract which mods run (lines `id@version`), so the
/// open-cache key does not ask the host on every open; null clears it (the host is asked again). OKModModes.cpp calls
/// it whenever a mode's mods are loaded, for every module's copy (FOkSession::SetEnabledMods).
///
/// # Safety
/// `lines` is null or a NUL-terminated UTF-8 string.
#[no_mangle]
pub unsafe extern "C" fn ok_set_enabled_mods(lines: *const std::ffi::c_char) {
    if lines.is_null() {
        *ENABLED.write().unwrap_or_else(|e| e.into_inner()) = None;
        return;
    }
    set_enabled(parse_lines(&std::ffi::CStr::from_ptr(lines).to_string_lossy()));
}
fn parse_lines(text: &str) -> Vec<(String, String)> {
    text.lines().map(str::trim).filter(|l| !l.is_empty())
        .map(|l| match l.rsplit_once('@') { Some((id, v)) => (id.to_owned(), v.to_owned()), None => (l.to_owned(), String::new()) })
        .collect()
}

/// What the open-cache key hashes for the enabled mods; None with none (the key is then what it was before mods).
pub fn cache_key_bytes() -> Option<Vec<u8>> { key_bytes(&enabled()) }
fn key_bytes(mods: &[(String, String)]) -> Option<Vec<u8>> {
    if mods.is_empty() { return None; }
    let mut out = Vec::new();
    for (id, version) in mods { out.extend_from_slice(id.as_bytes()); out.push(b'@'); out.extend_from_slice(version.as_bytes()); out.push(b'\n'); }
    Some(out)
}

/// The card's KKEx sections (ExtendedSave data of the original game's plugins), each as its msgpack bytes, by key.
pub fn kkex_sections(card: &[u8]) -> std::collections::BTreeMap<String, Vec<u8>> {
    let mut out = std::collections::BTreeMap::new();
    let Ok(blocks) = crate::appearance::blocks_from_card(card) else { return out };
    let Some(raw) = blocks.get("KKEx") else { return out };
    let Ok(rmpv::Value::Map(items)) = rmpv::decode::read_value(&mut &raw[..]) else { return out };
    for (k, v) in items {
        let Some(k) = k.as_str() else { continue };
        let mut bytes = Vec::new();
        if rmpv::encode::write_value(&mut bytes, &v).is_ok() { out.insert(k.to_owned(), bytes); }
    }
    out
}

/// The okMx sections the mods make from an original card's KKEx (ExtendedSave data of the original game's plugins):
/// `extract.kkex_keys` asks which KKEx keys they read, `extract.kkex` hands those sections over as msgpack
/// (Docs/OK_MOD_HOOKS.md). By mod id: `{version, requires, data_b64}`. Empty without a mod host here (the CLI) or
/// with no such mod.
pub fn kkex_mod_sections(original: &[u8]) -> Result<serde_json::Map<String, serde_json::Value>, String> {
    let none = serde_json::Map::new();
    if !crate::mod_forward::available() { return Ok(none); }
    let Some(answer) = crate::mod_forward::dispatch(r#"{"op":"hook","hook":"extract.kkex_keys","payload":{}}"#) else { return Ok(none) };
    let answer: serde_json::Value = serde_json::from_str(&answer).unwrap_or_default();
    let mut keys: Vec<String> = answer["replies"].as_array().into_iter().flatten()
        .flat_map(|r| r["json"]["keys"].as_array().cloned().unwrap_or_default())
        .filter_map(|k| k.as_str().map(str::to_owned)).collect();
    keys.sort();
    keys.dedup();
    if keys.is_empty() { return Ok(none); }
    let all = kkex_sections(original);
    let sections: serde_json::Map<String, serde_json::Value> = keys.iter().filter_map(|k| all.get(k).map(|b| (k.clone(), ok_card_mods::b64::encode(b).into()))).collect();
    if sections.is_empty() { return Ok(none); }
    let request = serde_json::json!({"op": "extract.kkex", "sections": sections}).to_string();
    let Some(answer) = crate::mod_forward::dispatch(&request) else { return Ok(none) };
    let answer: serde_json::Value = serde_json::from_str(&answer).map_err(|e| format!("kkex answer: {e}"))?;
    for e in answer["errors"].as_array().into_iter().flatten() { eprintln!("ok-extract: kkex: {e}"); }
    Ok(answer["sections"].as_object().cloned().unwrap_or_default())
}

/// Converting an original card into an OK card (`oklib::make_ok_card`): `kkex_mod_sections` written into the new card's
/// okMx. Without a mod host here or with no such mod, `made` comes back unchanged.
pub fn with_kkex_mods(original: &[u8], made: Vec<u8>) -> Result<Vec<u8>, String> {
    let sections = kkex_mod_sections(original)?;
    if sections.is_empty() { return Ok(made); }
    let mut data = read_data(&made)?;
    for (id, s) in &sections {
        let bytes = ok_card_mods::b64::decode(s["data_b64"].as_str().unwrap_or_default()).map_err(|e| format!("kkex {id}: {e}"))?;
        let requires = s["requires"].as_object().map(|r| Requires { id: r.get("id").and_then(|v| v.as_str()).unwrap_or(id).into(), version: r.get("version").and_then(|v| v.as_str()).unwrap_or_default().into() });
        data.set(id, &Section { version: s["version"].as_u64().unwrap_or(1) as u32, requires, data: bytes });
    }
    with_data(&made, &data)
}

/// `ok_kkex_mod_sections`: `kkex_mod_sections` of the card at `card_path` as JSON into `out` (the reader, opening an
/// original card, hands them to the mods as if the card had them). Returns 0, the size needed when `out` is null or
/// too small (+1 for the NUL), or -1 when the card cannot be read.
///
/// # Safety
/// `card_path` is a NUL-terminated UTF-8 path; `out` is null or `cap` writable bytes.
#[no_mangle]
pub unsafe extern "C" fn ok_kkex_mod_sections(card_path: *const std::ffi::c_char, out: *mut std::ffi::c_char, cap: i32) -> i32 {
    if card_path.is_null() { return -1; }
    let path = std::ffi::CStr::from_ptr(card_path).to_string_lossy().into_owned();
    let made = std::panic::catch_unwind(|| -> Result<String, String> {
        let bytes = std::fs::read(&path).map_err(|e| e.to_string())?;
        Ok(serde_json::Value::Object(kkex_mod_sections(&bytes)?).to_string())
    });
    let Ok(Ok(json)) = made else { return -1 };
    if out.is_null() || cap <= 0 || cap as usize <= json.len() { return json.len() as i32 + 1; }
    std::ptr::copy_nonoverlapping(json.as_ptr(), out as *mut u8, json.len());
    *out.add(json.len()) = 0;
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_open_changing_mods_count() {
        assert!(!changes_opens(["street.day_change", "reader.ui", "extract.kkex", "extract.kkex_keys"]));
        assert!(changes_opens(["reader.ui", "extract.post_texture"]));
    }
    #[test]
    fn cache_key_bytes_only_with_mods() {
        // (the process-wide list is left alone: other tests compute open-cache keys meanwhile)
        assert!(key_bytes(&[]).is_none());
        assert!(cache_key_bytes().is_none(), "no mod enabled and no host in tests");
        assert_eq!(key_bytes(&[("a".into(), "2.0.0".into()), ("b".into(), "1.0.0".into())]).unwrap(), b"a@2.0.0\nb@1.0.0\n");
    }

    /// Every card under OK_IDENTITY_DIR keeps the identity the code before mods gave it (only okVo left out).
    /// `OK_IDENTITY_DIR=<folder> cargo test --release --lib okmods::tests::identities_unchanged -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn identities_unchanged() {
        fn before(bytes: &[u8]) -> Option<String> {
            use sha2::Digest;
            if let Some(id) = crate::oklib::png_chunk(bytes, crate::oklib::IDENTITY_CHUNK) {
                return std::str::from_utf8(id).ok().filter(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())).map(str::to_owned);
            }
            if bytes.len() < 8 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" { return None; }
            let mut hash = sha2::Sha256::new();
            hash.update(&bytes[..8]);
            let mut pos = 8usize;
            while pos + 12 <= bytes.len() {
                let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().ok()?) as usize;
                let end = pos.checked_add(12 + len).filter(|e| *e <= bytes.len())?;
                let kind = &bytes[pos + 4..pos + 8];
                if kind != b"okVo" { hash.update(&bytes[pos..end]); }
                pos = end;
                if kind == b"IEND" { break; }
            }
            hash.update(&bytes[pos..]);
            Some(hash.finalize().iter().map(|b| format!("{b:02x}")).collect())
        }
        let dirs = std::env::var("OK_IDENTITY_DIR").expect("OK_IDENTITY_DIR");
        let mut files = Vec::new();
        fn walk(d: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
            let Ok(rd) = std::fs::read_dir(d) else { return };
            for e in rd.flatten() {
                let p = e.path();
                if p.is_dir() { walk(&p, out) } else if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("png")) { out.push(p) }
            }
        }
        for d in std::env::split_paths(&dirs) { walk(&d, &mut files); }
        let (mut same, mut differ) = (0, Vec::new());
        for f in &files {
            let Ok(bytes) = std::fs::read(f) else { continue };
            let (a, b) = (before(&bytes), crate::oklib::card_identity(&bytes));
            if a == b { same += 1 } else { differ.push(f.clone()) }
            if let Some(b) = &b { println!("{b}\t{}", f.display()); }
        }
        eprintln!("identities: {} cards, {same} unchanged, {} changed", files.len(), differ.len());
        assert!(differ.is_empty(), "changed: {differ:?}");
    }
    /// Prints the KKEx sections of OK_KKEX_CARD (for writing a kkex mod).
    #[test]
    #[ignore]
    fn print_kkex_sections() {
        let card = std::fs::read(std::env::var("OK_KKEX_CARD").expect("OK_KKEX_CARD")).unwrap();
        for (k, v) in kkex_sections(&card) {
            let value = rmpv::decode::read_value(&mut &v[..]).unwrap();
            let text = value.to_string();
            println!("{k} ({} bytes): {}", v.len(), &text[..text.len().min(400)]);
        }
    }
}
