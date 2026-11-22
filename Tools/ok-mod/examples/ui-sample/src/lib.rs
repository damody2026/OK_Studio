//! `ui-sample`: one reader page with every kind of control a mod can declare (Docs/OK_MOD_HOOKS.md §4, plan §6.13 D1):
//! tabs, groups, a row, a scrolling box, a number box, a slider, a progress bar, a colour, radio buttons, a drop-down, a
//! list, a switch, a multi-line text field, labels in the theme's text styles, a picture from this mod's folder and a
//! button. The values live in memory only (nothing goes into the card): a page to copy from, and the reader's test.

use std::collections::BTreeMap;

use ok_mod_sdk::prelude::*;
use serde_json::{json, Value};

struct UiSample {
    values: BTreeMap<&'static str, Value>,
}

fn first_values() -> BTreeMap<&'static str, Value> {
    BTreeMap::from([
        ("count", json!(3)),
        ("volume", json!(0.5)),
        ("tint", json!("#7EA6D0")),
        ("size", json!("m")),
        ("mood", json!("calm")),
        ("fruit", json!("apple")),
        ("shy", json!(false)),
        ("note", json!("")),
    ])
}

impl UiSample {
    /// What the page shows: the values, a summary line and the lines of the read-only list.
    fn shown(&self) -> Value {
        let mut out: serde_json::Map<String, Value> = self.values.iter().map(|(k, v)| (k.to_string(), v.clone())).collect();
        let volume = self.values["volume"].as_f64().unwrap_or(0.0) * 100.0;
        out.insert("summary".into(), format!("數量 {}，音量 {volume:.0}%，顏色 {}", self.values["count"], self.values["tint"].as_str().unwrap_or("")).into());
        out.insert("history".into(), json!(self.values.iter().map(|(k, v)| format!("{k} = {v}")).collect::<Vec<_>>()));
        Value::Object(out)
    }

    fn set(&mut self, key: &str, value: Value) -> Result<(), String> {
        let ok = match key {
            "count" => value.as_f64().is_some_and(|n| (0.0..=10.0).contains(&n)),
            "volume" => value.as_f64().is_some_and(|n| (0.0..=1.0).contains(&n)),
            "tint" => value.as_str().is_some_and(|s| s.len() == 7 && s.starts_with('#') && s[1..].chars().all(|c| c.is_ascii_hexdigit())),
            "size" => value.as_str().is_some_and(|s| ["s", "m", "l"].contains(&s)),
            "mood" => value.as_str().is_some_and(|s| ["calm", "happy", "sleepy"].contains(&s)),
            "fruit" => value.as_str().is_some_and(|s| ["apple", "peach", "melon", "grape"].contains(&s)),
            "shy" => value.is_boolean(),
            "note" => value.as_str().is_some_and(|s| s.chars().count() <= 500),
            _ => return Err(format!("unknown key {key}")),
        };
        if !ok {
            return Err(format!("{key}: {value} is not accepted"));
        }
        let slot = *self.values.keys().find(|k| **k == key).ok_or("unknown key")?;
        self.values.insert(slot, value);
        Ok(())
    }
}

fn options(pairs: &[(&str, &str)]) -> Value {
    json!(pairs.iter().map(|(v, l)| json!({"value": v, "label": l})).collect::<Vec<_>>())
}

fn page() -> Value {
    json!({"pages": [{
        "name": "控制項範例",
        "layout": "tabs",
        "items": [
            {"kind": "group", "label": "數值", "items": [
                {"kind": "label", "text": "數字與比例", "style": "Title"},
                {"kind": "number", "key": "count", "label": "數量", "min": 0, "max": 10, "step": 1},
                {"kind": "slider", "key": "volume", "label": "音量", "min": 0, "max": 1, "step": 0.05},
                {"kind": "progress", "key": "volume", "label": "目前"},
                {"kind": "color", "key": "tint", "label": "顏色"},
                {"kind": "label", "key": "summary", "style": "AccentText"},
            ]},
            {"kind": "group", "label": "選擇", "items": [
                {"kind": "radio", "key": "size", "label": "尺寸", "options": options(&[("s", "小"), ("m", "中"), ("l", "大")])},
                {"kind": "choice", "key": "mood", "label": "心情", "options": options(&[("calm", "平靜"), ("happy", "開心"), ("sleepy", "想睡")])},
                {"kind": "list", "key": "fruit", "label": "水果", "height": 150, "options": options(&[("apple", "蘋果"), ("peach", "桃子"), ("melon", "哈密瓜"), ("grape", "葡萄")])},
                {"kind": "bool", "key": "shy", "label": "害羞"},
            ]},
            {"kind": "group", "label": "文字與其他", "items": [
                {"kind": "text", "key": "note", "label": "備註", "multiline": true, "height": 100, "placeholder": "隨便寫點什麼"},
                {"kind": "image", "image": "icon.png", "width": 64},
                {"kind": "group", "label": "目前的值（可摺疊）", "fold": true, "items": [
                    {"kind": "scroll", "height": 120, "items": [{"kind": "list", "key": "history", "height": 110}]},
                ]},
                {"kind": "row", "items": [
                    {"kind": "button", "action": "reset", "label": "恢復初始值"},
                    {"kind": "label", "text": "（按鈕執行 mod 的指令）", "style": "Caption"},
                ]},
            ]},
        ],
    }]})
}

impl Mod for UiSample {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(UiSample { values: first_values() })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.command("reset", "mod.org.openkoikatsu.ui-sample.cmd.reset");
        for hook in ["reader.ui", "reader.values", "reader.control"] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Command { name, .. } if name.as_str() == "reset" => {
                self.values = first_values();
                hooks::json(&json!({"notice": "範例控制項已恢復初始值"}))
            }
            Event::Command { name, .. } => Err(format!("unknown command {name}")),
            Event::Hook { name, payload } => match name.as_str() {
                "reader.ui" => hooks::json(&page()),
                "reader.values" => hooks::json(&self.shown()),
                "reader.control" => {
                    let set: hooks::ReaderSet = hooks::parse(payload)?;
                    self.set(&set.key, set.value)?;
                    Ok(Reply::None)
                }
                _ => Ok(Reply::None),
            },
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(UiSample);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn values_are_checked_and_shown() {
        let mut m = UiSample { values: first_values() };
        m.set("count", json!(7)).unwrap();
        m.set("tint", json!("#112233")).unwrap();
        assert!(m.set("count", json!(11)).is_err());
        assert!(m.set("size", json!("xl")).is_err());
        assert!(m.set("tint", json!("blue")).is_err());
        let shown = m.shown();
        assert_eq!(shown["count"], 7);
        assert!(shown["summary"].as_str().unwrap().contains("#112233"));
        assert!(shown["history"].as_array().unwrap().iter().any(|l| l == "count = 7"));
    }

    #[test]
    fn every_kind_is_on_the_page() {
        let text = page().to_string();
        for kind in ["group", "row", "scroll", "number", "slider", "progress", "color", "radio", "choice", "list", "bool", "text", "image", "button", "label"] {
            assert!(text.contains(&format!("\"kind\":\"{kind}\"")), "{kind}");
        }
    }
}
