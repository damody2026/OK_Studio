//! Bookmarks (Docs/H_SCENE_ADDITIONS_PLAN.md 13): he marks a moment with her (in the H scene, the time after it, or
//! talking on the street). Each keeps when and where, her state then (relation, mood, pregnancy week), the last 50 lines
//! between them and a thumbnail's file name (the PNG is Unreal's, beside the save). They are part of the save's `ext`
//! (ext.bookmarks.<girl>, at most 100 each, the oldest dropped), and she remembers them: each is a memory, her words
//! carry the last five, and asked about one she reads its lines.
use serde_json::{json, Value};

const MOST: usize = 100;
const LINES: usize = 50;
const TOLD: usize = 5;

fn s<'a>(r: &'a Value, k: &str) -> &'a str {
    r.get(k).and_then(Value::as_str).unwrap_or_default()
}

fn n(r: &Value, k: &str) -> i64 {
    r.get(k).and_then(Value::as_i64).unwrap_or(0)
}

fn list(r: &Value, girl: &str) -> Vec<Value> {
    r.get("ext").and_then(|e| e.get("bookmarks")).and_then(|b| b.get(girl)).and_then(Value::as_array).cloned().unwrap_or_default()
}

fn with_list(r: &Value, girl: &str, marks: Vec<Value>) -> Value {
    let mut ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    if !ext.get("bookmarks").is_some_and(Value::is_object) {
        ext["bookmarks"] = json!({});
    }
    ext["bookmarks"][girl] = Value::Array(marks);
    ext
}

/// "11/3 21:05 溫泉SPA飯店": its date and time, then the place.
fn title(day: i64, minute: i64, place: &str) -> String {
    let d = crate::calendar::date(day as i32, (minute as f64) / 60.0);
    let place = if place.is_empty() { crate::tr::t("bookmarks.street") } else { place };
    crate::tr::m("bookmarks.title", &[("month", crate::tr::a(&d.month.to_string())), ("day", crate::tr::a(&d.day.to_string())), ("time", crate::tr::a(&format!("{}:{:02}", minute / 60, minute % 60))), ("place", crate::tr::a(place))])
}

/// One line for her: the last thing she said then (else the last line at all), cut short.
fn summary(lines: &[Value]) -> String {
    let pick = lines.iter().rev().find(|l| s(l, "who") == "her" && !s(l, "text").is_empty()).or_else(|| lines.iter().rev().find(|l| !s(l, "text").is_empty()));
    let text = pick.map(|l| s(l, "text")).unwrap_or_default();
    let cut: String = text.chars().take(40).collect();
    if cut.chars().count() < text.chars().count() { cut + "…" } else { cut }
}

/// Her state then, in words: relation, mood, and the week when she is pregnant.
fn state(r: &Value, girl: &str, day: i64) -> String {
    let rel = r.get("relation").cloned().unwrap_or(Value::Null);
    let stage = match s(&rel, "stage") {
        "lover" => crate::tr::t("bookmarks.stage_lover"),
        "friend" => crate::tr::t("bookmarks.stage_friend"),
        _ => crate::tr::t("bookmarks.stage_stranger"),
    };
    let level = rel.get("mood_level").and_then(Value::as_f64).unwrap_or(0.0);
    let mood = if level >= 0.3 { crate::tr::t("bookmarks.mood_good") } else if level <= -0.3 { crate::tr::t("bookmarks.mood_bad") } else { crate::tr::t("bookmarks.mood_calm") };
    let p = crate::pregnancy::on_day(r.get("ext").unwrap_or(&Value::Null), girl, day);
    let week = crate::pregnancy::view(&p, girl, day).get("week").and_then(Value::as_i64).unwrap_or(0);
    let pregnant = crate::pregnancy::view(&p, girl, day).get("pregnant").and_then(Value::as_bool).unwrap_or(false);
    let mut out = crate::tr::m("bookmarks.state", &[("stage", crate::tr::a(stage)), ("mood", crate::tr::a(mood))]);
    if pregnant {
        out += &crate::tr::m("bookmarks.state_pregnant", &[("week", crate::tr::a(&week.to_string()))]);
    }
    out
}

/// He marked this moment. Request: ext, girl, relation, day, minute (of the day), place (its name as shown, "" for the
/// street), lines [{who: him|her, text}] (oldest first; the last 50 are kept), thumb (file name). Answer: ext, id, title,
/// summary, memory (her memory of it, for MindObserve).
fn add(r: &Value) -> Result<Value, String> {
    let girl = s(r, "girl");
    if girl.is_empty() {
        return Err("missing_field: girl".into());
    }
    let (day, minute) = (n(r, "day"), n(r, "minute").rem_euclid(1440));
    let all: Vec<Value> = r.get("lines").and_then(Value::as_array).cloned().unwrap_or_default();
    let lines: Vec<Value> = all[all.len().saturating_sub(LINES)..].iter().map(|l| json!({"who": s(l, "who"), "text": s(l, "text")})).collect();
    let mut marks = list(r, girl);
    let id = marks.iter().filter_map(|m| m.get("id").and_then(Value::as_i64)).max().unwrap_or(0) + 1;
    let title = title(day, minute, s(r, "place"));
    let summary = summary(&lines);
    let state = state(r, girl, day);
    marks.push(json!({"id": id, "day": day, "minute": minute, "place": s(r, "place"), "title": title, "summary": summary, "state": state, "lines": lines, "thumb": s(r, "thumb")}));
    if marks.len() > MOST {
        marks.drain(..marks.len() - MOST);
    }
    let memory = crate::tr::m("bookmarks.memory", &[("title", crate::tr::a(&title)), ("summary", crate::tr::a(&summary))]);
    Ok(json!({"ext": with_list(r, girl, marks), "id": id, "title": title, "summary": summary, "memory": memory}))
}

/// Her bookmarks for the phone, newest first. Request: ext, girl. Answer: bookmarks [{id, title, summary, state, thumb,
/// lines}].
fn view(r: &Value) -> Value {
    let rows: Vec<Value> = list(r, s(r, "girl")).into_iter().rev().collect();
    json!({"bookmarks": rows})
}

/// For her words: the last five (title and one line), and the lines of one when he asks about it (his words name the
/// bookmark word, its date or its place; else the newest). Request: ext, girl, said. Answer: text.
fn facts(r: &Value) -> Value {
    let marks = list(r, s(r, "girl"));
    if marks.is_empty() {
        return json!({"text": ""});
    }
    let told: Vec<String> = marks.iter().rev().take(TOLD).map(|m| crate::tr::m("bookmarks.fact_item", &[("title", crate::tr::a(s(m, "title"))), ("summary", crate::tr::a(s(m, "summary")))])).collect();
    let mut text = crate::tr::m("bookmarks.fact_recent", &[("items", crate::tr::a(&told.join(crate::tr::t("items.separator"))))]);
    let said = s(r, "said");
    if !said.is_empty() && said.contains(crate::tr::t("bookmarks.word")) {
        let named = marks.iter().rev().find(|m| {
            let place = s(m, "place");
            let d = crate::calendar::date(n(m, "day") as i32, 0.0);
            (!place.is_empty() && said.contains(place)) || said.contains(&format!("{}/{}", d.month, d.day))
        });
        let m = named.unwrap_or_else(|| marks.last().unwrap());
        let lines: Vec<String> = m
            .get("lines")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .map(|l| crate::tr::m(if s(l, "who") == "him" { "bookmarks.line_him" } else { "bookmarks.line_her" }, &[("text", crate::tr::a(s(l, "text")))]))
            .collect();
        text += crate::tr::t("items.fact_separator");
        text += &crate::tr::m("bookmarks.fact_lines", &[("title", crate::tr::a(s(m, "title"))), ("state", crate::tr::a(s(m, "state"))), ("lines", crate::tr::a(&lines.join(" / ")))]);
    }
    json!({"text": text})
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    Some(match kind {
        "bookmark_add" => add(r),
        "bookmarks_view" => Ok(view(r)),
        "bookmarks_facts" => Ok(facts(r)),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(k: usize) -> Value {
        Value::Array((0..k).map(|i| json!({"who": if i % 2 == 0 { "him" } else { "her" }, "text": format!("line {i}")})).collect())
    }

    #[test]
    fn a_bookmark_keeps_the_last_fifty_lines_and_her_state() {
        let out = add(&json!({"girl": "g", "ext": {}, "relation": {"stage": "lover", "mood_level": 0.5}, "day": 3, "minute": 21 * 60 + 5, "place": "飯店", "lines": lines(70), "thumb": "b.png"})).unwrap();
        let m = &out["ext"]["bookmarks"]["g"][0];
        assert_eq!(m["lines"].as_array().unwrap().len(), 50);
        assert_eq!(m["lines"][0]["text"], "line 20");
        assert_eq!(m["summary"], "line 69");
        assert_eq!(m["thumb"], "b.png");
        assert!(!m["state"].as_str().unwrap().is_empty());
        assert!(out["memory"].as_str().unwrap().contains(m["title"].as_str().unwrap()));
    }

    #[test]
    fn past_a_hundred_the_oldest_goes() {
        let mut ext = json!({});
        for _ in 0..105 {
            ext = add(&json!({"girl": "g", "ext": ext, "day": 1, "minute": 600, "lines": lines(2)})).unwrap()["ext"].clone();
        }
        let marks = ext["bookmarks"]["g"].as_array().unwrap();
        assert_eq!(marks.len(), 100);
        assert_eq!(marks[0]["id"], 6);
        assert_eq!(marks[99]["id"], 105);
    }

    #[test]
    fn she_is_told_the_last_five_and_reads_one_when_asked() {
        let mut ext = json!({});
        for k in 0..7 {
            ext = add(&json!({"girl": "g", "ext": ext, "day": 1, "minute": 600 + k, "place": if k == 2 { "民宿" } else { "飯店" }, "lines": lines(3)})).unwrap()["ext"].clone();
        }
        let plain = facts(&json!({"girl": "g", "ext": ext, "said": "你好"}))["text"].as_str().unwrap().to_string();
        assert_eq!(plain.matches("line 1").count(), 5, "five bookmarks, each with its one line: {plain}");
        let word = crate::tr::t("bookmarks.word");
        let asked = facts(&json!({"girl": "g", "ext": ext, "said": format!("還記得民宿那個{word}嗎")}))["text"].as_str().unwrap().to_string();
        assert!(asked.contains("line 0") && asked.contains("民宿"), "{asked}");
        assert_eq!(facts(&json!({"girl": "other", "ext": ext}))["text"], "");
    }
}
