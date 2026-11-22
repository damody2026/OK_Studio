//! Requests about cards, the reader and card conversion (Docs/OK_MOD_HOOKS.md). Mods get these as `Event::Hook`s; the
//! host reads and writes the card's `okMx` itself (Tools/ok-card-mods, the same code as ok-extract), so a mod never
//! touches a file and every other mod's section is kept byte for byte.
//!
//! Mod data travels as base64 (`data_b64`): the bytes are the mod's own (the SDK's `ExtData` writes JSON).
//!
//! Resources (`okMr`, plan §6.12): a `reader.character_save` reply may add `"resources_b64": [..]`; each is stored once
//! by its sha256 (lowercase hex), which the mod writes into its own data to reference it. A resource no section's data
//! names any more is dropped when the card is saved, and a mod's referenced resources may weigh at most
//! `resource_limit()` (100 MiB) per card: over it, that mod's section is not written and the log says why.

use base64::Engine;
use ok_card_mods::{ModData, Requires, Resources, Section};
use ok_mod_api::{LogLevel, Reply};
use serde_json::{json, Map, Value};

use crate::ModHost;

pub const OPS: &[&str] = &["card_core", "card_mods", "card_load", "card_store", "extract.kkex", "reader.ui", "reader.values", "reader.control"];

fn b64() -> base64::engine::GeneralPurpose { base64::engine::general_purpose::STANDARD }

fn str_field<'a>(req: &'a Value, key: &str) -> Result<&'a str, String> {
    req.get(key).and_then(Value::as_str).ok_or_else(|| format!("missing string \"{key}\""))
}

/// A mod's reply as JSON (`Reply::Json` parsed; `None`/text as null).
fn reply_value(reply: &Result<Reply, String>) -> Result<Value, String> {
    match reply {
        Ok(Reply::Json(text)) => serde_json::from_str(text.as_str()).map_err(|e| format!("reply is not JSON: {e}")),
        Ok(_) => Ok(Value::Null),
        Err(e) => Err(e.clone()),
    }
}

/// Mods enabled now: id -> version.
fn enabled(host: &ModHost) -> std::collections::HashMap<String, String> {
    host.statuses().into_iter().filter(|s| s.state == "enabled").map(|s| (s.id, s.version)).collect()
}

fn read_card(path: &str) -> Result<(Vec<u8>, ModData), String> {
    let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
    let data = ok_card_mods::read_data(&bytes).map_err(|e| format!("{path}: {e}"))?;
    Ok((bytes, data))
}

/// What one mod's resources may weigh in one card (plan §6.12, 100 MiB). `OK_MOD_RESOURCE_LIMIT` (bytes) lowers it
/// for tests.
pub fn resource_limit() -> usize {
    std::env::var("OK_MOD_RESOURCE_LIMIT").ok().and_then(|v| v.parse().ok()).unwrap_or(100 * 1024 * 1024)
}

/// Whether `data` names resource `hash` (its 64 hex digits appear in the bytes).
fn names(data: &[u8], hash: &str) -> bool {
    data.windows(hash.len()).any(|w| w == hash.as_bytes())
}

/// The card's resources that `data` names, as `{hash: base64}` (for character_load).
fn named_resources(res: &Resources, data: &[u8]) -> Value {
    Value::Object(res.by_hash.iter().filter(|(h, _)| names(data, h)).map(|(h, b)| (h.clone(), b64().encode(b).into())).collect())
}

fn section_json(s: &Section) -> Value {
    json!({
        "version": s.version,
        "requires": s.requires.as_ref().map(|r| json!({"id": r.id, "version": r.version})),
        "data_b64": b64().encode(&s.data),
    })
}

/// A mod's `{version, data_b64}` reply as a section that requires this mod at its installed version.
fn section_from_reply(id: &str, version: &str, v: &Value) -> Result<Section, String> {
    let data_version = v.get("version").and_then(Value::as_u64).and_then(|n| u32::try_from(n).ok()).ok_or("reply needs \"version\" (u32)")?;
    let data = b64().decode(v.get("data_b64").and_then(Value::as_str).ok_or("reply needs \"data_b64\"")?).map_err(|e| format!("data_b64: {e}"))?;
    Ok(Section { version: data_version, requires: Some(Requires { id: id.into(), version: version.into() }), data })
}

/// A character_save reply's `"resources_b64": [..]`, by sha256 hex.
fn resources_from_reply(v: &Value) -> Result<Resources, String> {
    let mut res = Resources::default();
    for item in v.get("resources_b64").and_then(Value::as_array).into_iter().flatten() {
        let text = item.as_str().ok_or("resources_b64 holds base64 strings")?;
        res.add(&b64().decode(text).map_err(|e| format!("resources_b64: {e}"))?);
    }
    Ok(res)
}

fn replies_json(replies: Vec<crate::ModReply>) -> Value {
    Value::Array(replies.into_iter().map(|r| match reply_value(&r.result) {
        Ok(v) => json!({"mod": r.id, "ok": true, "json": v}),
        Err(e) => json!({"mod": r.id, "ok": false, "error": e}),
    }).collect())
}

/// `mod.<id>.<field>` -> (id, field), for an enabled mod id.
fn split_key<'a>(key: &'a str, ids: &std::collections::HashMap<String, String>) -> Option<(&'a str, &'a str)> {
    let rest = key.strip_prefix("mod.")?;
    // Mod ids contain dots: the longest enabled id that prefixes the key.
    ids.keys().filter_map(|id| rest.strip_prefix(id.as_str()).and_then(|f| f.strip_prefix('.')).map(|f| (id.len(), f)))
        .max_by_key(|(n, _)| *n).map(|(n, f)| (&rest[..n], f))
}

/// A reader page's items and every container's under them: keys and actions get the mod's prefix, images become full
/// paths inside the mod's folder (anything else is removed: a mod shows only its own pictures). A `.dui` panel item
/// (`"kind": "dui"`, plan §6.13 D2) gets `"mod"`: its panel, values and hooks are always this mod's.
fn rewrite_items(node: &mut Value, id: &str, dir: Option<&std::path::Path>) {
    for item in node.get_mut("items").and_then(Value::as_array_mut).into_iter().flatten() {
        if let Some(k) = item.get("key").and_then(Value::as_str).map(str::to_owned) { item["key"] = format!("mod.{id}.{k}").into(); }
        if let Some(a) = item.get("action").and_then(Value::as_str).map(str::to_owned) { item["action"] = format!("mod.{id}.{a}").into(); }
        if item.get("kind").and_then(Value::as_str) == Some("dui") { item["mod"] = id.into(); }
        if let Some(image) = item.get("image").and_then(Value::as_str).map(str::to_owned) {
            match dir.and_then(|d| mod_file(d, &image)) {
                Some(full) => item["image"] = full.into(),
                None => { item.as_object_mut().map(|o| o.remove("image")); }
            }
        }
        rewrite_items(item, id, dir);
    }
}

/// `name` inside `dir` (relative, no `..`, an existing file), as a full path with forward slashes.
fn mod_file(dir: &std::path::Path, name: &str) -> Option<String> {
    let rel = std::path::Path::new(name);
    if rel.is_absolute() || rel.components().any(|c| !matches!(c, std::path::Component::Normal(_))) { return None; }
    let full = dir.join(rel);
    full.is_file().then(|| std::path::absolute(&full).unwrap_or(full).to_string_lossy().replace('\\', "/"))
}

pub fn handle(host: &mut ModHost, op: &str, req: &Value) -> Result<Value, String> {
    let payload = |v: Value| v.to_string();
    Ok(match op {
        // {"op":"card_core","card","id":"ok.<name>"} -> {"data_b64"|null}: a section the core itself keeps in okMx (the
        // reader's mod material overrides, "ok.materials"), read; with "data_b64" it is written (null removes it).
        // Only "ok." ids: mods' sections are theirs (card_store).
        "card_core" => {
            let path = str_field(req, "card")?;
            let id = str_field(req, "id")?;
            if !id.starts_with("ok.") { return Err(format!("card_core is for the core's own sections (ok.*), not {id}")); }
            let (bytes, mut data) = read_card(path)?;
            match req.get("data_b64") {
                None => json!({"data_b64": data.get(id).and_then(Result::ok).map(|s| b64().encode(&s.data))}),
                Some(v) => {
                    let changed = match v.as_str() {
                        Some(text) => {
                            let bytes = b64().decode(text).map_err(|e| format!("data_b64: {e}"))?;
                            data.set(id, &Section { version: 1, requires: None, data: bytes });
                            true
                        }
                        None => data.remove(id),
                    };
                    if changed {
                        std::fs::write(path, ok_card_mods::with_data(&bytes, &data)?).map_err(|e| format!("{path}: {e}"))?;
                    }
                    json!({"ok": true, "changed": changed})
                }
            }
        }
        // {"op":"card_mods","card"}: the card's okMx sections and whether their mods are here.
        "card_mods" => {
            let path = str_field(req, "card")?;
            let (bytes, data) = read_card(path)?;
            let mods = enabled(host);
            let sections: Vec<Value> = data.ids().map(|id| {
                let mut v = match data.get(id) { Some(Ok(s)) => section_json(&s), Some(Err(e)) => json!({"error": e}), None => Value::Null };
                v["id"] = id.into();
                v["bytes"] = data.raw(id).map_or(0, <[u8]>::len).into();
                v["enabled"] = mods.contains_key(id).into();
                v["mod_version"] = mods.get(id).cloned().into();
                v.as_object_mut().map(|o| o.remove("data_b64"));
                v
            }).collect();
            json!({"identity": ok_card_mods::card_identity(&bytes), "sections": sections})
        }
        // {"op":"card_load","card","outfit","skip_apply":[ids],"imported":{id: section}?}: reader.character_load to every
        // subscriber, with its section. "imported" are sections made from an original card's KKEx (ok-extract
        // ok_kkex_mod_sections): a mod the card has no section for gets that one, marked "imported": true, and writes
        // it into the card on the next save.
        "card_load" => {
            let path = str_field(req, "card")?;
            let outfit = req.get("outfit").and_then(Value::as_i64).unwrap_or(0);
            let skip: Vec<&str> = req.get("skip_apply").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
            let (bytes, data) = read_card(path)?;
            let identity = ok_card_mods::card_identity(&bytes);
            let mods = enabled(host);
            // okMr only when there is one (zstd of up to every mod's resources).
            let res = if ok_card_mods::chunk(&bytes, ok_card_mods::RESOURCE_CHUNK).is_some() {
                ok_card_mods::read_resources(&bytes).unwrap_or_else(|e| {
                    host.host_log(LogLevel::Warn, &format!("{path}: {e}; mods get no resources"));
                    Resources::default()
                })
            } else {
                Resources::default()
            };
            let mut replies = Vec::new();
            for id in host.subscribers("reader.character_load") {
                let (section, imported) = match data.get(&id) {
                    Some(Ok(s)) => {
                        let mut v = section_json(&s);
                        if !res.by_hash.is_empty() { v["resources"] = named_resources(&res, &s.data); }
                        (v, false)
                    }
                    _ => match req.get("imported").and_then(|i| i.get(&id)) { Some(s) if s.is_object() => (s.clone(), true), _ => (Value::Null, false) },
                };
                let body = payload(json!({"card": path, "outfit": outfit, "identity": identity, "apply": !skip.contains(&id.as_str()), "section": section, "imported": imported}));
                let result = host.hook_one(&id, "reader.character_load", &body);
                replies.push(crate::ModReply { id, result });
            }
            let missing: Vec<Value> = data.ids().filter(|id| !id.starts_with("ok.") && !mods.contains_key(*id)).map(|id| {
                let r = data.get(id).and_then(Result::ok).and_then(|s| s.requires);
                json!({"id": id, "version": r.map(|r| r.version)})
            }).collect();
            json!({"replies": replies_json(replies), "missing": missing})
        }
        // {"op":"card_store","card","outfit"}: character_save to every subscriber; their sections written into the card.
        "card_store" => {
            let path = str_field(req, "card")?;
            let outfit = req.get("outfit").and_then(Value::as_i64).unwrap_or(0);
            let (bytes, mut data) = read_card(path)?;
            let mut res = ok_card_mods::read_resources(&bytes).map_err(|e| format!("{path}: {e}"))?;
            let res_before: Vec<String> = res.by_hash.keys().cloned().collect();
            let limit = resource_limit();
            let mods = enabled(host);
            let (mut written, mut removed, mut errors) = (Vec::new(), Vec::new(), Vec::new());
            for id in host.subscribers("reader.character_save") {
                let body = payload(json!({"card": path, "outfit": outfit}));
                match reply_value(&host.hook_one(&id, "reader.character_save", &body)) {
                    Ok(Value::Null) => {}
                    Ok(v) if v.get("remove").and_then(Value::as_bool) == Some(true) => { if data.remove(&id) { removed.push(id); } }
                    Ok(v) => match section_from_reply(&id, mods.get(&id).map_or("", String::as_str), &v).and_then(|s| {
                        let added = resources_from_reply(&v)?;
                        Ok((s, added))
                    }) {
                        Ok((s, added)) => {
                            // What this section names, from the card or from this reply, counted once.
                            let weight: usize = res.by_hash.iter().chain(added.by_hash.iter().filter(|(h, _)| !res.by_hash.contains_key(*h)))
                                .filter(|(h, _)| names(&s.data, h)).map(|(_, b)| b.len()).sum();
                            if weight > limit {
                                let e = format!("its resources weigh {weight} bytes in this card, over the limit of {limit}: not written");
                                host.host_log(LogLevel::Error, &format!("{id}: {path}: {e}"));
                                errors.push(json!({"mod": id, "error": e}));
                                continue;
                            }
                            for (h, b) in added.by_hash { res.by_hash.entry(h).or_insert(b); }
                            data.set(&id, &s);
                            written.push(id);
                        }
                        Err(e) => errors.push(json!({"mod": id, "error": e})),
                    },
                    Err(e) => errors.push(json!({"mod": id, "error": e})),
                }
            }
            let mut pruned = 0;
            if !written.is_empty() || !removed.is_empty() {
                // Resources no section names any more (a mod replaced or removed its picture) leave the card.
                let raws: Vec<&[u8]> = data.ids().filter_map(|id| data.raw(id)).collect();
                let before = res.by_hash.len();
                res.by_hash.retain(|h, _| raws.iter().any(|r| names(r, h)));
                pruned = before - res.by_hash.len();
                let mut out = ok_card_mods::with_data(&bytes, &data)?;
                if res.by_hash.keys().ne(res_before.iter()) {
                    out = ok_card_mods::with_resources(&out, &res)?;
                }
                std::fs::write(path, out).map_err(|e| format!("{path}: {e}"))?;
            }
            json!({"ok": errors.is_empty(), "written": written, "removed": removed, "errors": errors,
                   "resources": {"count": res.by_hash.len(), "bytes": res.total_bytes(), "pruned": pruned}})
        }
        // {"op":"extract.kkex","sections":{"<KKEx key>": "<msgpack b64>"}}: converting an original card. Returns the okMx
        // sections mods made from them; the caller (ok-extract) writes them into the OK card.
        "extract.kkex" => {
            let sections = req.get("sections").cloned().unwrap_or(Value::Object(Map::new()));
            let mods = enabled(host);
            let mut out = Map::new();
            let mut errors = Vec::new();
            for id in host.subscribers("extract.kkex") {
                let body = payload(json!({"sections": sections}));
                match reply_value(&host.hook_one(&id, "extract.kkex", &body)) {
                    Ok(Value::Null) => {}
                    Ok(v) => match section_from_reply(&id, mods.get(&id).map_or("", String::as_str), &v) {
                        Ok(s) => { out.insert(id, section_json(&s)); }
                        Err(e) => errors.push(json!({"mod": id, "error": e})),
                    },
                    Err(e) => errors.push(json!({"mod": id, "error": e})),
                }
            }
            json!({"sections": out, "errors": errors})
        }
        // {"op":"reader.ui"}: the controls each mod puts in the reader; keys become mod.<id>.<key>.
        // Items nest (group, row, tabs, scroll: Docs/OK_MOD_HOOKS.md §4); every level is rewritten, and an image names a
        // PNG in the mod's own folder, handed on as a full path (one outside the folder is dropped).
        "reader.ui" => {
            let statuses = host.statuses();
            let names: std::collections::HashMap<String, String> = statuses.iter().map(|s| (s.id.clone(), s.name.clone())).collect();
            let dirs: std::collections::HashMap<String, String> = statuses.into_iter().map(|s| (s.id, s.dir)).collect();
            let mut out = Vec::new();
            for r in host.hook("reader.ui", "{}") {
                match reply_value(&r.result) {
                    Ok(mut v) => {
                        let dir = dirs.get(&r.id).map(std::path::PathBuf::from);
                        for page in v.get_mut("pages").and_then(Value::as_array_mut).into_iter().flatten() {
                            rewrite_items(page, &r.id, dir.as_deref());
                        }
                        out.push(json!({"mod": r.id, "name": names.get(&r.id), "pages": v.get("pages").cloned().unwrap_or(json!([]))}));
                    }
                    Err(e) => out.push(json!({"mod": r.id, "error": e})),
                }
            }
            json!({"mods": out})
        }
        // {"op":"reader.values"}: every mod control's value now, by full key.
        "reader.values" => {
            let mut values = Map::new();
            for r in host.hook("reader.values", "{}") {
                if let Ok(Value::Object(o)) = reply_value(&r.result) {
                    for (k, v) in o { values.insert(format!("mod.{}.{k}", r.id), v); }
                }
            }
            Value::Object(values)
        }
        // {"op":"reader.control","key":"mod.<id>.<field>","value"}: one control changed. The mod's reply may ask the
        // reader for more ({"set":[{key,value}]} registry edits, {"notice": text}); it is passed back as "json".
        "reader.control" => {
            let key = str_field(req, "key")?;
            let mods = enabled(host);
            let (id, field) = split_key(key, &mods).ok_or_else(|| format!("{key} is not mod.<enabled mod id>.<field>"))?;
            let (id, field) = (id.to_owned(), field.to_owned());
            let body = payload(json!({"key": field, "value": req.get("value").cloned().unwrap_or(Value::Null)}));
            match reply_value(&host.hook_one(&id, "reader.control", &body)) {
                Ok(v) => json!({"ok": true, "mod": id, "json": v}),
                Err(e) => json!({"ok": false, "mod": id, "error": e}),
            }
        }
        _ => return Err(format!("unknown op \"{op}\"")),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn keys_split_on_the_longest_enabled_id() {
        let ids: std::collections::HashMap<String, String> = [("org.a", "1"), ("org.a.b", "1")].iter().map(|(a, b)| (a.to_string(), b.to_string())).collect();
        assert_eq!(split_key("mod.org.a.b.text", &ids), Some(("org.a.b", "text")));
        assert_eq!(split_key("mod.org.a.text", &ids), Some(("org.a", "text")));
        assert_eq!(split_key("mod.org.c.text", &ids), None);
    }

    #[test]
    fn nested_items_are_rewritten_and_images_stay_in_the_mod_folder() {
        let dir = std::env::temp_dir().join(format!("ok-mod-ui-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("pics")).unwrap();
        std::fs::write(dir.join("pics").join("icon.png"), b"png").unwrap();
        let mut page = json!({"name": "p", "layout": "tabs", "items": [
            {"kind": "group", "label": "a", "items": [
                {"kind": "row", "items": [{"kind": "number", "key": "n"}, {"kind": "button", "action": "go"}]},
                {"kind": "image", "image": "pics/icon.png"},
                {"kind": "image", "image": "../secret.png"},
                {"kind": "image", "image": "missing.png"},
                {"kind": "dui", "widget": "Panel", "mod": "org.other"},
            ]},
        ]});
        rewrite_items(&mut page, "org.x", Some(&dir));
        let g = &page["items"][0]["items"];
        assert_eq!(g[0]["items"][0]["key"], "mod.org.x.n");
        assert_eq!(g[0]["items"][1]["action"], "mod.org.x.go");
        assert!(g[1]["image"].as_str().unwrap().ends_with("pics/icon.png"), "{page}");
        assert!(g[2].get("image").is_none() && g[3].get("image").is_none(), "{page}");
        assert_eq!(g[4]["mod"], "org.x", "a panel is always the page's own mod's");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
