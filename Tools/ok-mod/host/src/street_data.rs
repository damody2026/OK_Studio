//! Street data tables from mods (plan §6.6 "資料表擴充", Docs/OK_MOD_C_WAVE6.md): `Mods/<id>/street/*.toml`.
//!
//! - `[[items]]`: goods and gifts sold in a street shop, merged into the street catalogue (catalog.json's item shape).
//!   The id is always `<mod id>.<name>` (a bare `name` gets the prefix); prices are written in yuan, the base region,
//!   and converted like the built-in ones (ok-rules region.rs).
//! - `[[topics]]`: material for her talk: sentences the AI may draw on, put in the static part of her prompt (not rules,
//!   not facts about today; what she says is hers).
//!
//! `{"op":"street_data"}` reads every enabled mod's files and answers `{"items", "topics", "problems"}`. A bad row is
//! dropped and named in `problems`; the rest of the file still counts. The street (UE) checks what only it knows: the
//! shop (`place`) has to exist, and an id may not shadow a built-in item.
use serde_json::{json, Map, Value};
use std::path::Path;

use crate::ModHost;

pub const OPS: &[&str] = &["street_data"];

/// At most this many items and topics from one mod.
const MAX_ITEMS: usize = 200;
const MAX_TOPICS: usize = 50;
/// The longest topic text, in characters.
const MAX_TOPIC_CHARS: usize = 300;

pub fn handle(host: &mut ModHost, op: &str, _req: &Value) -> Result<Value, String> {
    match op {
        "street_data" => {
            let mut out = Tables::default();
            for m in host.statuses().into_iter().filter(|m| m.state == "enabled") {
                read_mod(&m.id, Path::new(&m.dir), &mut out);
            }
            Ok(json!({"items": out.items, "topics": out.topics, "problems": out.problems}))
        }
        other => Err(format!("unknown op {other}")),
    }
}

#[derive(Default)]
pub struct Tables {
    pub items: Vec<Value>,
    pub topics: Vec<Value>,
    pub problems: Vec<Value>,
}

/// One mod's `street/*.toml`, in file name order.
pub fn read_mod(id: &str, dir: &Path, out: &mut Tables) {
    let Ok(read) = std::fs::read_dir(dir.join("street")) else { return };
    let mut files: Vec<_> = read.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.is_file() && p.extension().is_some_and(|e| e.eq_ignore_ascii_case("toml"))).collect();
    files.sort();
    let (mut items, mut topics) = (0usize, 0usize);
    for path in files {
        let file = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        let mut problem = |e: String| out_problem(&mut out.problems, id, &file, e);
        let table: toml::Table = match std::fs::read_to_string(&path).map_err(|e| e.to_string()).and_then(|t| toml::from_str(&t).map_err(|e| e.to_string())) {
            Ok(t) => t,
            Err(e) => { problem(e); continue; }
        };
        for (n, row) in table.get("items").and_then(toml::Value::as_array).into_iter().flatten().enumerate() {
            if items >= MAX_ITEMS { problem(format!("more than {MAX_ITEMS} items: the rest dropped")); break; }
            match item(id, row) {
                Ok(v) => { out.items.push(v); items += 1; }
                Err(e) => problem(format!("items[{n}]: {e}")),
            }
        }
        for (n, row) in table.get("topics").and_then(toml::Value::as_array).into_iter().flatten().enumerate() {
            if topics >= MAX_TOPICS { problem(format!("more than {MAX_TOPICS} topics: the rest dropped")); break; }
            match topic(id, row) {
                Ok(v) => { out.topics.push(v); topics += 1; }
                Err(e) => problem(format!("topics[{n}]: {e}")),
            }
        }
        for key in table.keys().filter(|k| !matches!(k.as_str(), "items" | "topics")) {
            problem(format!("unknown table [{key}]"));
        }
    }
}

fn out_problem(problems: &mut Vec<Value>, id: &str, file: &str, error: String) {
    problems.push(json!({"mod": id, "file": file, "error": error}));
}

fn to_json(v: &toml::Value) -> Value { serde_json::to_value(v).unwrap_or(Value::Null) }

fn str_of<'a>(row: &'a toml::Table, key: &str) -> Option<&'a str> { row.get(key).and_then(toml::Value::as_str).map(str::trim).filter(|s| !s.is_empty()) }

/// The full id: `<mod id>.<name>`; the name is `[a-z0-9_]`.
fn full_id(id: &str, given: &str) -> Result<String, String> {
    let name = given.strip_prefix(&format!("{id}.")).unwrap_or(given);
    if name.is_empty() || name.len() > 48 || !name.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_') {
        return Err(format!("id \"{given}\": a name of a-z, 0-9 and _ (at most 48), made <mod id>.<name>"));
    }
    Ok(format!("{id}.{name}"))
}

/// One item row as catalog.json writes it, with `"mod"`.
fn item(id: &str, row: &toml::Value) -> Result<Value, String> {
    let row = row.as_table().ok_or("an item is a table")?;
    let full = full_id(id, str_of(row, "id").ok_or("needs \"id\"")?)?;
    let name = str_of(row, "name").ok_or("needs \"name\"")?;
    let place = str_of(row, "place").ok_or("needs \"place\" (the shop that sells it)")?;
    // price = 68 (one size, yuan) or price = { "" = 68, L = 80 }.
    let mut price = Map::new();
    match row.get("price") {
        Some(toml::Value::Integer(n)) => { price.insert(String::new(), json!(n)); }
        Some(toml::Value::Table(t)) => for (size, n) in t {
            price.insert(size.clone(), json!(n.as_integer().ok_or_else(|| format!("price.{size} is a whole number of yuan"))?));
        },
        _ => return Err("needs \"price\" (whole yuan, or a table size -> yuan)".into()),
    }
    if price.is_empty() || price.values().any(|v| v.as_i64().is_none_or(|n| !(1..=1_000_000).contains(&n))) {
        return Err("price: 1..1000000 yuan".into());
    }
    let category = str_of(row, "category").unwrap_or("gift");
    let mut out = json!({
        "id": full, "mod": id, "name": name, "place": place, "category": category, "price": price,
        "giftable": row.get("giftable").and_then(toml::Value::as_bool).unwrap_or(true),
        "consumable": row.get("consumable").and_then(toml::Value::as_bool).unwrap_or(false),
        "tags": row.get("tags").map(to_json).unwrap_or(json!([])),
        "options": row.get("options").map(to_json).unwrap_or(json!([])),
        "season": row.get("season").map(to_json).unwrap_or(Value::Null),
        "effects": row.get("effects").map(to_json).unwrap_or(json!({})),
    });
    if let Some(prop) = str_of(row, "prop") { out["prop"] = prop.into(); }
    if let Some(floor) = row.get("floor").and_then(toml::Value::as_integer) { out["floor"] = floor.into(); }
    if !out["tags"].as_array().is_some_and(|a| a.iter().all(Value::is_string)) { return Err("tags: a list of strings".into()); }
    if !out["effects"].as_object().is_some_and(|o| o.values().all(Value::is_number)) { return Err("effects: a table of numbers".into()); }
    if let Some(names) = row.get("names").and_then(toml::Value::as_table) {
        // Its name in other languages ({"en" = "Birthday cake"}): the street picks the one of its language.
        out["names"] = to_json(&toml::Value::Table(names.clone()));
    }
    Ok(out)
}

/// One topic row: `{"mod", "text", "lang"?}`.
fn topic(id: &str, row: &toml::Value) -> Result<Value, String> {
    let row = row.as_table().ok_or("a topic is a table")?;
    let text = str_of(row, "text").ok_or("needs \"text\"")?;
    if text.chars().count() > MAX_TOPIC_CHARS { return Err(format!("text: at most {MAX_TOPIC_CHARS} characters")); }
    let mut out = json!({"mod": id, "text": text});
    if let Some(lang) = str_of(row, "lang") { out["lang"] = lang.into(); }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn items_get_the_mod_prefix_and_bad_rows_are_named() {
        let dir = std::env::temp_dir().join(format!("ok-street-data-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("street")).unwrap();
        std::fs::write(dir.join("street/a.toml"), r#"
[[items]]
id = "cake"
name = "小蛋糕"
place = "conveni"
price = 68
tags = ["sweet"]
names = { en = "Small cake" }

[[items]]
id = "Bad Id"
name = "x"
place = "conveni"
price = 1

[[items]]
id = "org.x.box"
name = "盒子"
place = "department"
price = { "" = 120, L = 150 }
consumable = true

[[topics]]
text = "生日那天收到記得自己的人送的小東西，會讓人高興。"
lang = "zh-TW"

[[shops]]
"#).unwrap();
        let mut t = Tables::default();
        read_mod("org.x", &dir, &mut t);
        assert_eq!(t.items.len(), 2);
        assert_eq!(t.items[0]["id"], "org.x.cake");
        assert_eq!(t.items[0]["price"][""], 68);
        assert_eq!(t.items[0]["giftable"], true);
        assert_eq!(t.items[0]["names"]["en"], "Small cake");
        assert_eq!(t.items[1]["id"], "org.x.box", "an id already <mod id>.<name> is kept");
        assert_eq!(t.items[1]["price"]["L"], 150);
        assert_eq!(t.topics.len(), 1);
        assert_eq!(t.topics[0]["lang"], "zh-TW");
        let errors: Vec<&str> = t.problems.iter().map(|p| p["error"].as_str().unwrap()).collect();
        assert_eq!(errors.len(), 2, "{errors:?}");
        assert!(errors[0].starts_with("items[1]: id \"Bad Id\""));
        assert_eq!(errors[1], "unknown table [shops]");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
