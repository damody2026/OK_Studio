//! The clinics and the hair salon (user 2026-11-03): a gynaecology clinic that rebuilds her hymen, a cosmetic clinic
//! that gives her someone else's face, and a salon that dyes her hair. What she had done is kept in ext (her hexp for
//! the hymen, ext.appearance.<id> for her face and hair); Unreal sells the treatment (catalog.json, places clinic_gyn,
//! clinic_beauty, salon), asks here whether it can be done, and shows her new face and hair from appearance_of.
use crate::effects::Effects;
use serde_json::{json, Value};

fn s<'a>(r: &'a Value, k: &str) -> &'a str {
    r.get(k).and_then(Value::as_str).unwrap_or_default()
}

/// Hair colours the salon has, by id: its name's text id and the colour (sRGB hex).
pub const HAIR_COLORS: [(&str, &str); 12] = [
    ("black", "#1b1716"),
    ("dark_brown", "#3b2519"),
    ("chestnut", "#6b3e26"),
    ("ash_brown", "#7a6656"),
    ("honey_blonde", "#c9a063"),
    ("platinum", "#e6dcc8"),
    ("silver", "#b9bcc4"),
    ("wine_red", "#6e1f2d"),
    ("cherry_pink", "#e58fa8"),
    ("lavender", "#a58fc9"),
    ("navy_blue", "#27345e"),
    ("mint_green", "#8fcbb3"),
];

fn hair_name(id: &str) -> String {
    let key = format!("clinic.hair_{id}");
    crate::tr::lookup(&key, "").to_string()
}

fn appearance(ext: &Value, girl: &str) -> Value {
    ext.get("appearance").and_then(|a| a.get(girl)).cloned().filter(Value::is_object).unwrap_or_else(|| json!({}))
}

fn with_appearance(ext: &Value, girl: &str, a: Value) -> Value {
    let mut ext = ext.clone();
    if !ext.is_object() {
        ext = json!({});
    }
    if !ext.get("appearance").is_some_and(Value::is_object) {
        ext["appearance"] = json!({});
    }
    ext["appearance"][girl] = a;
    ext
}

fn refused(reason: &str, ext: &Value) -> Value {
    let key = format!("clinic.refused_{reason}");
    json!({"ok": false, "reason": reason, "fact": crate::tr::lookup(&key, ""), "ext": ext})
}

/// One treatment. Request: kind (hymen_restore | face_swap | face_restore | hair_dye), girl, girl_name, ext, profile,
/// day, place; face_swap: from (whose face: a heroine id), from_name; hair_dye: color (an id of HAIR_COLORS).
/// Answer: ok, ext, effects (her memory of it), fact (for her words), reason when not ok.
fn treat(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).filter(|g| !g.is_empty()).ok_or("missing_field: girl")?;
    let ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let place = s(r, "place");
    let day = r.get("day").and_then(Value::as_i64).unwrap_or(-1);
    let mut fx = Effects::default();
    let (ext, note, fact) = match s(r, "kind") {
        "hymen_restore" => {
            let mut h = crate::hexp::of(&ext, girl);
            let t = crate::traits::Traits::from_profile(r.get("profile").unwrap_or(&Value::Null));
            if h.virgin {
                return Ok(refused("still_virgin", &ext));
            }
            if h.hymen_restored {
                return Ok(refused("already_restored", &ext));
            }
            if t.hymen_regen {
                return Ok(refused("regrows", &ext));
            }
            h.hymen_restored = true;
            let mut ext = ext;
            if !ext.get("hexp").is_some_and(Value::is_object) {
                ext["hexp"] = json!({});
            }
            ext["hexp"][girl] = serde_json::to_value(&h).map_err(|e| e.to_string())?;
            (ext, crate::tr::t("clinic.hymen_note").to_string(), crate::tr::t("clinic.hymen_fact").to_string())
        }
        "face_swap" => {
            let from = s(r, "from");
            if from.is_empty() || from == girl {
                return Ok(refused("no_face", &ext));
            }
            let mut a = appearance(&ext, girl);
            if s(&a, "face_from") == from {
                return Ok(refused("same_face", &ext));
            }
            let name = if s(r, "from_name").is_empty() { from } else { s(r, "from_name") };
            a["face_from"] = json!(from);
            a["face_from_name"] = json!(name);
            a["face_day"] = json!(day);
            let args = [("name", crate::tr::a(name))];
            (with_appearance(&ext, girl, a), crate::tr::m("clinic.face_note", &args), crate::tr::m("clinic.face_fact", &args))
        }
        "face_restore" => {
            let mut a = appearance(&ext, girl);
            if s(&a, "face_from").is_empty() {
                return Ok(refused("own_face", &ext));
            }
            if let Some(o) = a.as_object_mut() {
                o.remove("face_from");
                o.remove("face_from_name");
            }
            a["face_day"] = json!(day);
            (with_appearance(&ext, girl, a), crate::tr::t("clinic.face_restore_note").to_string(), crate::tr::t("clinic.face_restore_fact").to_string())
        }
        "hair_dye" => {
            let id = s(r, "color");
            let Some((_, hex)) = HAIR_COLORS.iter().find(|(c, _)| *c == id) else {
                return Ok(refused("no_color", &ext));
            };
            let mut a = appearance(&ext, girl);
            if s(&a, "hair") == id {
                return Ok(refused("same_color", &ext));
            }
            a["hair"] = json!(id);
            a["hair_rgb"] = json!(hex);
            a["hair_day"] = json!(day);
            let args = [("color", crate::tr::a(&hair_name(id)))];
            (with_appearance(&ext, girl, a), crate::tr::m("clinic.hair_note", &args), crate::tr::m("clinic.hair_fact", &args))
        }
        other => return Err(format!("unknown_kind: {other}")),
    };
    fx.note_at(girl, "body_change", &note, place, 0.85);
    Ok(json!({"ok": true, "ext": ext, "effects": fx.into_value(), "fact": fact}))
}

/// What to show of her now. Request: ext, girl. Answer: face_from (a heroine id, "" her own), hair (colour id, "" her
/// own), hair_rgb.
fn appearance_of(r: &Value) -> Value {
    let a = appearance(r.get("ext").unwrap_or(&Value::Null), s(r, "girl"));
    json!({"face_from": s(&a, "face_from"), "face_from_name": s(&a, "face_from_name"), "hair": s(&a, "hair"), "hair_rgb": s(&a, "hair_rgb")})
}

/// The salon's colour chart: [{id, name, rgb}].
fn hair_colors() -> Value {
    json!({"colors": HAIR_COLORS.iter().map(|(id, hex)| json!({"id": id, "name": hair_name(id), "rgb": hex})).collect::<Vec<_>>()})
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    Some(match kind {
        "clinic_treat" => treat(r),
        "appearance_of" => Ok(appearance_of(r)),
        "hair_colors" => Ok(hair_colors()),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn treat_ok(r: Value) -> Value {
        treat(&r).unwrap()
    }

    #[test]
    fn rebuilt_hymen_bleeds_once_more_and_is_broken_again() {
        let ext = json!({"hexp": {"g": {"count": 3, "virgin": false}}});
        let v = treat_ok(json!({"kind": "hymen_restore", "girl": "g", "ext": ext, "day": 5}));
        assert_eq!(v["ok"], true);
        let ext = v["ext"].clone();
        assert_eq!(ext["hexp"]["g"]["hymen_restored"], true);
        assert_eq!(ext["hexp"]["g"]["count"], 3, "the rest of what she has been through stays");
        // The scene plays it as her first time.
        let rel = json!({"id": "g", "stage": "lover"});
        let e = crate::hexp::eval("h_experience", &json!({"girl": "g", "ext": ext, "relation": rel})).unwrap().unwrap();
        assert_eq!(e["virgin"], true);
        // He enters her: she bleeds, and it is broken again (her memory says so, not that she lost her virginity).
        let counts = json!({"played": true, "crotch": {"inserted": true, "climaxes": 1}, "his_inside_raw": 5});
        let end = crate::hexp::eval("h_session_end", &json!({"girl": "g", "ext": ext, "relation": rel, "counts": counts, "minute": 600, "day": 5})).unwrap().unwrap();
        assert_eq!(end["hexp"]["hymen_restored"], false);
        assert!(end["hexp"]["red_until"].as_i64().unwrap() > 600, "she bleeds: {}", end["hexp"]);
        let firsts = end["result"]["firsts"].as_array().unwrap();
        assert!(firsts.iter().any(|f| f == crate::tr::t("hexp.restored_hymen_broken")));
        assert!(!firsts.iter().any(|f| f == crate::tr::t("hexp.lost_virginity")));
    }

    #[test]
    fn hymen_not_rebuilt_when_there_is_nothing_to_rebuild() {
        assert_eq!(treat_ok(json!({"kind": "hymen_restore", "girl": "g", "ext": {}}))["reason"], "still_virgin");
        let regen = json!({"traits": {"hymen_regen": true}});
        assert_eq!(treat_ok(json!({"kind": "hymen_restore", "girl": "g", "ext": {"hexp": {"g": {"virgin": false}}}, "profile": regen}))["reason"], "regrows");
        let twice = json!({"hexp": {"g": {"virgin": false, "hymen_restored": true}}});
        assert_eq!(treat_ok(json!({"kind": "hymen_restore", "girl": "g", "ext": twice}))["reason"], "already_restored");
    }

    #[test]
    fn her_face_and_hair_are_kept_and_shown() {
        let v = treat_ok(json!({"kind": "face_swap", "girl": "g", "from": "h", "from_name": "惠惠", "ext": {"items": {"x": 1}}, "day": 7}));
        assert_eq!(v["ok"], true);
        assert_eq!(v["ext"]["items"]["x"], 1, "the rest of ext is kept");
        let v = treat_ok(json!({"kind": "hair_dye", "girl": "g", "color": "cherry_pink", "ext": v["ext"], "day": 8}));
        let shown = appearance_of(&json!({"ext": v["ext"], "girl": "g"}));
        assert_eq!(shown["face_from"], "h");
        assert_eq!(shown["hair"], "cherry_pink");
        assert_eq!(shown["hair_rgb"], "#e58fa8");
        assert_eq!(treat_ok(json!({"kind": "face_swap", "girl": "g", "from": "g", "ext": {}}))["reason"], "no_face");
        assert_eq!(treat_ok(json!({"kind": "hair_dye", "girl": "g", "color": "rainbow", "ext": {}}))["reason"], "no_color");
        let back = treat_ok(json!({"kind": "face_restore", "girl": "g", "ext": v["ext"]}));
        let shown = appearance_of(&json!({"ext": back["ext"], "girl": "g"}));
        assert_eq!(shown["face_from"], "");
        assert_eq!(shown["hair"], "cherry_pink", "her hair stays dyed");
    }
}
