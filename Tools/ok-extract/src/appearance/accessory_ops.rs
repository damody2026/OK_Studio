//! The original editor's accessory copy and transfer (`ChaCustom/CvsAccessoryCopy.cs`, `CvsAccessoryChange.cs`):
//!
//! - `{"op":"accessory_transfer","from":a,"to":b}`: slot `a` of the shown outfit copied onto slot `b` of the same outfit
//!   (the "轉移" window; the original keeps the source slot too).
//! - `{"op":"accessory_copy","from_outfit":o,"slots":[..]}`: those slots of outfit `o` copied onto the same slots of the
//!   shown outfit (the "複製" window between outfits).
//!
//! What moves is the slot's `ChaFileAccessory.PartsInfo` (kind, item, parent, the three move sets, colours, hide
//! category, no-shake) and the sideloader resolve row that says which zipmod item the id is
//! (`outfit<o>.accessory<s>.ChaFileAccessory.PartsInfo.id`): without that row a mod accessory copied by id alone would
//! open as whatever another mod numbers the same. Other plugins' per-slot data (Material Editor, ...) is theirs, as in
//! the original, where each plugin copies its own on the copy/transfer event; a mod gets the same event as
//! `reader.accessory_copy` / `reader.accessory_transfer` (Docs/OK_MOD_HOOKS.md). Only the card's 20 slots: the extra
//! slots of MoreAccessories live in its KKEx XML and are refused rather than half-copied.
use super::*;
use serde_json::Value as J;

pub(super) const NAMES: &[&str] = &["accessory_transfer", "accessory_copy"];

/// (source outfit, source slot, destination slot) for every op, the destination outfit being `outfit`.
fn moves(outfit: usize, ops: &[J]) -> Result<Vec<(usize, usize, usize)>, String> {
    let slot = |v: &J, what: &str| v.as_u64().map(|n| n as usize).filter(|n| *n < 20).ok_or_else(|| format!("{what} 只能是 0..19 的飾品欄"));
    let mut out = Vec::new();
    for op in ops {
        match op["op"].as_str().unwrap_or("") {
            "accessory_transfer" => {
                let (from, to) = (slot(&op["from"], "from")?, slot(&op["to"], "to")?);
                if from == to { return Err("來源和目的是同一個飾品欄".into()); }
                out.push((outfit, from, to));
            }
            "accessory_copy" => {
                let from_outfit = op["from_outfit"].as_u64().map(|n| n as usize).ok_or("缺少 from_outfit")?;
                if from_outfit == outfit { return Err("來源和目的是同一套服裝".into()); }
                let slots = op["slots"].as_array().filter(|a| !a.is_empty()).ok_or("缺少要複製的飾品欄")?;
                for s in slots { let s = slot(s, "slots")?; out.push((from_outfit, s, s)); }
            }
            other => return Err(format!("不支援的動作：{other}")),
        }
    }
    if out.is_empty() || out.len() > 64 { return Err("動作清單數量錯誤".into()); }
    Ok(out)
}

/// The accessory parts of `outfit` (a clone; `sections` walks a copy of the blocks).
fn parts_of(blocks: &BTreeMap<String, Vec<u8>>, outfit: usize) -> Result<Vec<Value>, String> {
    let mut copy = blocks.clone();
    let mut parts = None;
    properties::sections(&mut copy, outfit, |name, v| {
        if name == "accessory" { parts = Some(at(v, "parts")?.as_array().cloned().ok_or("飾品資料格式錯誤")?); }
        Ok(())
    })?;
    parts.ok_or_else(|| "這套服裝沒有飾品資料".into())
}

fn resolve_property(outfit: usize, slot: usize) -> String { format!("outfit{outfit}.accessory{slot}.ChaFileAccessory.PartsInfo.id") }

/// The resolver rows' list in a KKEx map (either key spelling), created when absent.
fn resolver_rows(kkex: &mut Value) -> Result<&mut Vec<Value>, String> {
    const NEW: &str = "com.bepis.sideloader.universalautoresolver";
    const OLD: &str = "EC.Core.Sideloader.UniversalAutoResolver";
    let has = |v: &Value, k: &str| v.as_map().is_some_and(|m| m.iter().any(|(x, _)| x.as_str() == Some(k)));
    let key = if !has(kkex, NEW) && has(kkex, OLD) { OLD } else { NEW };
    if !has(kkex, key) { set(kkex, key, Value::Array(vec![1.into(), Value::Map(vec![("info".into(), Value::Array(Vec::new()))])]))?; }
    let Value::Map(map) = kkex else { return Err("模組資料格式不支援".into()) };
    let plugin = map.iter_mut().find(|(k, _)| k.as_str() == Some(key)).map(|(_, v)| v).ok_or("解析器資料不足")?;
    let data = match plugin {
        Value::Array(a) => a.get_mut(1).ok_or("解析器資料不足")?,
        v => v,
    };
    match at(data, "info")? { Value::Array(list) => Ok(list), _ => Err("解析器清單格式不支援".into()) }
}

fn row_property(row: &Value) -> Option<String> {
    let mut v = match row { Value::Binary(b) => decode(b).ok()?, v => v.clone() };
    at(&mut v, "Property").ok()?.as_str().map(str::to_owned)
}

/// `{"op":"accessory_transfer"|"accessory_copy", ...}` applied to `original`'s outfit `outfit`, as one write.
pub(super) fn apply(original: &[u8], outfit: usize, ops: &[J]) -> Result<Vec<u8>, String> {
    let moves = moves(outfit, ops)?;
    let mut blocks = blocks_from_card(original)?;
    // Sources read before anything is written: a transfer list may chain (0->1, 1->2 copies the old slot 1).
    let mut sources = BTreeMap::new();
    for &(o, s, _) in &moves {
        if !sources.contains_key(&(o, s)) {
            let parts = parts_of(&blocks, o)?;
            sources.insert((o, s), parts.get(s).cloned().ok_or("飾品欄超出範圍")?);
        }
    }
    properties::sections(&mut blocks, outfit, |name, v| {
        if name != "accessory" { return Ok(()); }
        let Value::Array(parts) = at(v, "parts")? else { return Err("飾品資料格式錯誤".into()) };
        for &(o, s, to) in &moves { *parts.get_mut(to).ok_or("飾品欄超出範圍")? = sources[&(o, s)].clone(); }
        Ok(())
    })?;
    if let Some(raw) = blocks.get("KKEx").cloned() {
        let mut kkex = decode(&raw)?;
        let rows = resolver_rows(&mut kkex)?;
        let old: Vec<(Option<String>, Value)> = rows.iter().map(|r| (row_property(r), r.clone())).collect();
        for &(o, s, to) in &moves {
            let (src, dst) = (resolve_property(o, s), resolve_property(outfit, to));
            let row = old.iter().find(|(p, _)| p.as_deref() == Some(src.as_str())).map(|(_, r)| r.clone());
            rows.retain(|r| row_property(r).as_deref() != Some(dst.as_str()));
            if let Some(row) = row {
                let mut v = match &row { Value::Binary(b) => decode(b)?, v => v.clone() };
                set(&mut v, "Property", dst.as_str().into())?;
                rows.push(match row { Value::Binary(_) => Value::Binary(encode(&v)?), _ => v });
            }
        }
        blocks.insert("KKEx".into(), encode(&kkex)?);
    }
    write_blocks(original, blocks)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn moves_are_checked_before_anything_is_written() {
        assert_eq!(moves(1, &[json!({"op": "accessory_transfer", "from": 2, "to": 5})]).unwrap(), vec![(1, 2, 5)]);
        assert_eq!(moves(1, &[json!({"op": "accessory_copy", "from_outfit": 0, "slots": [3, 4]})]).unwrap(), vec![(0, 3, 3), (0, 4, 4)]);
        assert!(moves(1, &[json!({"op": "accessory_transfer", "from": 2, "to": 2})]).is_err());
        assert!(moves(1, &[json!({"op": "accessory_transfer", "from": 2, "to": 20})]).is_err(), "extra slots are refused");
        assert!(moves(1, &[json!({"op": "accessory_copy", "from_outfit": 1, "slots": [0]})]).is_err());
        assert!(moves(1, &[json!({"op": "accessory_copy", "from_outfit": 0, "slots": []})]).is_err());
    }

    #[test]
    fn a_resolve_row_follows_its_accessory() {
        let row = |p: &str, m: &str| Value::Binary(encode(&Value::Map(vec![("ModID".into(), m.into()), ("Property".into(), p.into())])).unwrap());
        let mut kkex = Value::Map(vec![("com.bepis.sideloader.universalautoresolver".into(), Value::Array(vec![1.into(), Value::Map(vec![("info".into(), Value::Array(vec![
            row(&resolve_property(0, 3), "mod.a"), row(&resolve_property(1, 3), "mod.old"), row("other", "mod.c")]))])]))]);
        let rows = resolver_rows(&mut kkex).unwrap();
        assert_eq!(rows.len(), 3);
        assert_eq!(row_property(&rows[1]).as_deref(), Some(resolve_property(1, 3).as_str()));
    }

    #[test]
    #[ignore = "needs Content/CharacterCards/CrowdAPNG/C000.png"]
    fn transfer_and_copy_on_a_real_card() {
        let card = std::fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/../../Content/CharacterCards/CrowdAPNG/C000.png")).unwrap();
        let blocks = blocks_from_card(&card).unwrap();
        let before = parts_of(&blocks, 0).unwrap();
        let used = before.iter().position(|p| p.as_map().is_some_and(|m| m.iter().any(|(k, v)| k.as_str() == Some("type") && v.as_i64() != Some(120)))).expect("a worn accessory");
        let empty = before.iter().position(|p| p.as_map().is_some_and(|m| m.iter().any(|(k, v)| k.as_str() == Some("type") && v.as_i64() == Some(120)))).expect("an empty slot");
        let out = apply(&card, 0, &[json!({"op": "accessory_transfer", "from": used, "to": empty})]).unwrap();
        let after = parts_of(&blocks_from_card(&out).unwrap(), 0).unwrap();
        assert_eq!(after[empty], before[used]);
        assert_eq!(after[used], before[used], "the source slot stays");
        let out = apply(&card, 1, &[json!({"op": "accessory_copy", "from_outfit": 0, "slots": [used]})]).unwrap();
        assert_eq!(parts_of(&blocks_from_card(&out).unwrap(), 1).unwrap()[used], before[used]);
    }
}
