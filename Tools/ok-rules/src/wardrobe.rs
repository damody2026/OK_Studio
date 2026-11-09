//! Her clothes (user 2026-11-04): what he bought her at the clothes and shoe shops and what of it she has on. Kept in
//! ext.wardrobe.<id> = {owned: [piece], worn: [item ids]}, a piece being what catalog.json says of the item: {item, name,
//! parts: [[card part, list id], ...], outfit (-1: the one she goes out in, 3 her swimsuit, 6 her pyjamas), color}.
//! Unreal sells them (category "clothes") and writes `dress` into a copy of her card (ok-extract restyle).
use crate::effects::Effects;
use serde_json::{json, Value};

fn s<'a>(r: &'a Value, k: &str) -> &'a str {
    r.get(k).and_then(Value::as_str).unwrap_or_default()
}

fn wardrobe(ext: &Value, girl: &str) -> Value {
    let w = ext.get("wardrobe").and_then(|a| a.get(girl)).cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    json!({"owned": w.get("owned").cloned().unwrap_or_else(|| json!([])), "worn": w.get("worn").cloned().unwrap_or_else(|| json!([]))})
}

fn with_wardrobe(ext: &Value, girl: &str, w: Value) -> Value {
    let mut ext = ext.clone();
    if !ext.is_object() {
        ext = json!({});
    }
    if !ext.get("wardrobe").is_some_and(Value::is_object) {
        ext["wardrobe"] = json!({});
    }
    ext["wardrobe"][girl] = w;
    ext
}

fn list(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or_default()
}

fn find<'a>(w: &'a Value, item: &str) -> Option<&'a Value> {
    list(&w["owned"]).iter().find(|p| s(p, "item") == item)
}

fn parts_of(p: &Value) -> Vec<i64> {
    list(&p["parts"]).iter().filter_map(|x| x.get(0).and_then(Value::as_i64)).collect()
}

fn outfit_of(p: &Value) -> i64 {
    p.get("outfit").and_then(Value::as_i64).unwrap_or(-1)
}

/// Put `item` on: what she had on the same parts of the same outfit comes off.
fn put_on(w: &mut Value, item: &str) {
    let Some(piece) = find(w, item).cloned() else { return };
    let (outfit, parts) = (outfit_of(&piece), parts_of(&piece));
    let keep: Vec<Value> = list(&w["worn"])
        .iter()
        .filter(|id| {
            let other = find(w, id.as_str().unwrap_or_default());
            other.is_some_and(|o| s(o, "item") != item && (outfit_of(o) != outfit || !parts_of(o).iter().any(|p| parts.contains(p))))
        })
        .cloned()
        .collect();
    w["worn"] = Value::Array(keep);
    w["worn"].as_array_mut().unwrap().push(json!(item));
}

/// The parts to write into her card, oldest first: [{outfit, part, id, color}].
fn dress(w: &Value, trying: Option<&Value>) -> Value {
    let worn = list(&w["worn"]).iter().filter_map(|id| find(w, id.as_str().unwrap_or_default()));
    let mut out = Vec::new();
    for piece in worn.chain(trying) {
        for part in list(&piece["parts"]) {
            out.push(json!({"outfit": outfit_of(piece), "part": part[0], "id": part[1], "color": s(piece, "color")}));
        }
    }
    Value::Array(out)
}

fn refused(reason: &str, ext: &Value) -> Value {
    let key = format!("wardrobe.refused_{reason}");
    json!({"ok": false, "reason": reason, "fact": crate::tr::lookup(&key, ""), "ext": ext})
}

/// He buys her a piece and she puts it on. Request: girl, ext, day, place, piece. Answer: ok, ext, effects, fact, reason.
fn buy(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).filter(|g| !g.is_empty()).ok_or("missing_field: girl")?;
    let piece = r.get("piece").filter(|p| !s(p, "item").is_empty()).ok_or("missing_field: piece")?;
    let ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut w = wardrobe(&ext, girl);
    if find(&w, s(piece, "item")).is_some() {
        return Ok(refused("already_owned", &ext));
    }
    let mut owned = piece.clone();
    owned["day"] = r.get("day").cloned().unwrap_or(json!(-1));
    w["owned"].as_array_mut().ok_or("wardrobe: owned")?.push(owned);
    put_on(&mut w, s(piece, "item"));
    let args = [("item", crate::tr::a(s(piece, "name")))];
    let mut fx = Effects::default();
    fx.note_at(girl, "new_clothes", &crate::tr::m("wardrobe.bought_note", &args), s(r, "place"), 0.7);
    Ok(json!({"ok": true, "ext": with_wardrobe(&ext, girl, w), "effects": fx.into_value(), "fact": crate::tr::m("wardrobe.bought_fact", &args)}))
}

/// She changes. Request: girl, ext, item (one she owns, "" for all her own clothes again), on (false takes it off).
fn change(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).filter(|g| !g.is_empty()).ok_or("missing_field: girl")?;
    let ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut w = wardrobe(&ext, girl);
    let item = s(r, "item");
    if item.is_empty() {
        w["worn"] = json!([]);
    } else if find(&w, item).is_none() {
        return Ok(refused("not_owned", &ext));
    } else if r.get("on").and_then(Value::as_bool).unwrap_or(true) {
        put_on(&mut w, item);
    } else {
        let keep: Vec<Value> = list(&w["worn"]).iter().filter(|id| id.as_str() != Some(item)).cloned().collect();
        w["worn"] = Value::Array(keep);
    }
    Ok(json!({"ok": true, "ext": with_wardrobe(&ext, girl, w)}))
}

/// What she has. Request: girl, ext, trying (a piece she tries on over them, optional). Answer: owned (each with worn),
/// dress (see above).
fn wardrobe_of(r: &Value) -> Value {
    let w = wardrobe(r.get("ext").unwrap_or(&Value::Null), s(r, "girl"));
    let worn = list(&w["worn"]);
    let owned: Vec<Value> = list(&w["owned"])
        .iter()
        .map(|p| json!({"item": s(p, "item"), "name": s(p, "name"), "worn": worn.iter().any(|id| id.as_str() == Some(s(p, "item")))}))
        .collect();
    json!({"owned": owned, "dress": dress(&w, r.get("trying").filter(|t| t.is_object()))})
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    Some(match kind {
        "clothes_buy" => buy(r),
        "clothes_change" => change(r),
        "wardrobe_of" => Ok(wardrobe_of(r)),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn piece(item: &str, parts: Value, outfit: i64) -> Value {
        json!({"item": item, "name": item, "parts": parts, "outfit": outfit, "color": ""})
    }

    fn buy_ok(ext: Value, p: Value) -> Value {
        let v = buy(&json!({"girl": "g", "ext": ext, "day": 3, "place": "department", "piece": p})).unwrap();
        assert_eq!(v["ok"], true);
        v["ext"].clone()
    }

    #[test]
    fn a_new_piece_replaces_what_she_had_on_those_parts_only() {
        let ext = buy_ok(json!({}), piece("skirt", json!([[1, 8]]), -1));
        let ext = buy_ok(ext, piece("shoes", json!([[7, 11], [8, 11]]), -1));
        let ext = buy_ok(ext, piece("dress", json!([[0, 56], [1, 0]]), -1));
        let v = wardrobe_of(&json!({"girl": "g", "ext": ext}));
        let on: Vec<_> = v["owned"].as_array().unwrap().iter().filter(|p| p["worn"] == true).map(|p| p["item"].as_str().unwrap()).collect();
        assert_eq!(on, ["shoes", "dress"], "the dress takes the skirt's place, the shoes stay");
        assert_eq!(v["dress"].as_array().unwrap().len(), 4);
    }

    #[test]
    fn her_swimsuit_stays_in_her_swimming_outfit() {
        let ext = buy_ok(json!({}), piece("bra", json!([[2, 3]]), -1));
        let ext = buy_ok(ext, piece("bikini", json!([[2, 8], [3, 7]]), 3));
        let v = wardrobe_of(&json!({"girl": "g", "ext": ext}));
        assert_eq!(v["owned"].as_array().unwrap().iter().filter(|p| p["worn"] == true).count(), 2);
    }

    #[test]
    fn she_keeps_what_he_bought_and_can_change_back() {
        let p = piece("dress", json!([[0, 56]]), -1);
        let ext = buy_ok(json!({}), p.clone());
        let again = buy(&json!({"girl": "g", "ext": ext, "piece": p})).unwrap();
        assert_eq!(again["reason"], "already_owned");
        let off = change(&json!({"girl": "g", "ext": ext, "item": ""})).unwrap();
        let v = wardrobe_of(&json!({"girl": "g", "ext": off["ext"]}));
        assert_eq!(v["dress"], json!([]));
        assert_eq!(v["owned"].as_array().unwrap().len(), 1, "taken off, not gone");
        let on = change(&json!({"girl": "g", "ext": off["ext"], "item": "dress", "on": true})).unwrap();
        assert_eq!(wardrobe_of(&json!({"girl": "g", "ext": on["ext"]}))["dress"].as_array().unwrap().len(), 1);
        assert_eq!(change(&json!({"girl": "g", "ext": {}, "item": "dress"})).unwrap()["reason"], "not_owned");
    }

    #[test]
    fn trying_on_changes_nothing_she_owns() {
        let ext = buy_ok(json!({}), piece("skirt", json!([[1, 8]]), -1));
        let v = wardrobe_of(&json!({"girl": "g", "ext": ext, "trying": piece("dress", json!([[0, 56]]), -1)}));
        assert_eq!(v["dress"].as_array().unwrap().len(), 2);
        assert_eq!(v["owned"].as_array().unwrap().len(), 1);
    }
}
