//! `hook-probe`: a test mod for the reader and street hooks added in wave 4 (Docs/OK_MOD_C_WAVE4.md §2–§3). A fixture, not an example: not in the full profile.
//!
//! Every hook it hears is written as one JSON line to `OK_HOOK_PROBE_LOG` (default: `<temp>/ok-hook-probe.jsonl`) and
//! to the game log (`probe <hook> ...`). It also answers a few, so the answers' roads are exercised:
//! - reader.property_change: `{"get": ["shape.body.*", "nickname"]}` once per card (answered with reader.get_result);
//! - a page `{"accessory": true}` with one per-slot text control (`note`), its values by `{outfit, slot}`, saved as the
//!   card's accessory sections on reader.character_save and read back on reader.character_load;
//! - reader.coordinate_save: a section `{"from": <card>}` written into the outfit card (seen again on coordinate_load);
//! - street.touch: the first touch with each heroine this run writes `{"touches": n}` into her card (`cards`), which
//!   street.load hands back as her `section` next time.
//!
//! Nothing here is for players.

use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;

use ok_mod_sdk::prelude::*;
use serde_json::{json, Value};

struct Probe {
    host: Host,
    /// Per-slot notes of the card shown: (outfit, slot) -> text.
    notes: BTreeMap<(u64, u64), String>,
    asked_get: bool,
    /// Heroines whose card got its touch count this run.
    written: BTreeSet<String>,
    /// Touch counts read from the cards at street.load.
    touches: BTreeMap<String, u64>,
}

fn log_path() -> std::path::PathBuf {
    std::env::var_os("OK_HOOK_PROBE_LOG").map(Into::into).unwrap_or_else(|| std::env::temp_dir().join("ok-hook-probe.jsonl"))
}

/// What of a payload goes in the log: everything but the base64 data (its length instead).
fn brief(v: &Value) -> Value {
    match v {
        Value::Object(o) => Value::Object(o.iter().map(|(k, v)| (k.clone(), if k == "data_b64" { json!(v.as_str().map_or(0, str::len)) } else { brief(v) })).collect()),
        Value::Array(a) => Value::Array(a.iter().map(brief).collect()),
        v => v.clone(),
    }
}

/// `{version, data_b64}` decoded as JSON.
fn section_json(v: &Value) -> Option<Value> {
    let s: hooks::ExtSection = serde_json::from_value(v.clone()).ok()?;
    s.data(1, |_, v| Ok(v)).ok()
}

/// `{outfit, slot}` of a per-slot control's request.
fn slot_of(v: &Value) -> (u64, u64) {
    (v["accessory"]["outfit"].as_u64().unwrap_or(0), v["accessory"]["slot"].as_u64().unwrap_or(0))
}

/// `payload` read as the SDK's type for hook `name`, where it has one.
fn typed(name: &str, payload: &str) -> ModResult<()> {
    use hooks::{reader as r, street as s};
    match name {
        r::ACCESSORY_CHANGE => { hooks::parse::<r::AccessoryChange>(payload)?; }
        r::ACCESSORY_TRANSFER => { hooks::parse::<r::AccessoryTransfer>(payload)?; }
        r::ACCESSORY_COPY => { hooks::parse::<r::AccessoryCopy>(payload)?; }
        r::COORDINATE_SAVE => { hooks::parse::<r::CoordinateSave>(payload)?; }
        r::COORDINATE_LOAD => { hooks::parse::<r::CoordinateLoad>(payload)?; }
        r::CLOTHES_STATE => { hooks::parse::<r::ClothesState>(payload)?; }
        r::PROPERTY_CHANGE => { hooks::parse::<r::PropertyChange>(payload)?; }
        r::GET_RESULT => { hooks::parse::<r::GetResult>(payload)?; }
        s::LOAD => { hooks::parse::<s::Load>(payload)?; }
        s::PERIOD_CHANGE => { hooks::parse::<s::PeriodChange>(payload)?; }
        s::TOUCH => { hooks::parse::<s::Touch>(payload)?; }
        s::ACTION => { hooks::parse::<s::Action>(payload)?; }
        s::ARRIVE => { hooks::parse::<s::Arrive>(payload)?; }
        s::PHONE => { hooks::parse::<s::Phone>(payload)?; }
        _ => {}
    }
    Ok(())
}

impl Probe {
    fn record(&self, hook: &str, payload: &Value) {
        let line = json!({"hook": hook, "payload": brief(payload)});
        self.host.info(format!("probe {hook} {}", line["payload"]));
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(log_path()) {
            let _ = writeln!(f, "{line}");
        }
    }
}

impl Mod for Probe {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Probe { host, notes: BTreeMap::new(), asked_get: false, written: BTreeSet::new(), touches: BTreeMap::new() })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        // F9: a JSON answer to a hotkey (a notice, and removing this mod's section of a heroine's card, which writes
        // nothing when there is none), the road a hotkey's {"notice", "cards"} takes in the street.
        reg.hotkey("probe_notice", "F9", "mod.org.openkoikatsu.hook_probe.config.probe_notice");
        for hook in [
            "reader.character_load", "reader.character_save", "reader.ui", "reader.values", "reader.control",
            "reader.accessory_change", "reader.accessory_copy", "reader.accessory_transfer",
            "reader.coordinate_load", "reader.coordinate_save", "reader.clothes_state", "reader.property_change", "reader.get_result",
            "street.load", "street.period_change", "street.touch", "street.action", "street.arrive", "street.phone",
        ] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        let name = name.as_str();
        if hooks::hotkey(name) == Some("probe_notice") {
            let key: hooks::KeyPress = hooks::parse(payload)?;
            self.record(name, &json!({"mode": key.mode, "chord": key.chord}));
            let mut reply = json!({"notice": format!("hook-probe: {} in {}", key.chord, key.mode)});
            if let Some(id) = self.touches.keys().next() {
                reply = hooks::street::with_cards(reply, &[hooks::street::CardWrite::remove(id)])?;
            }
            return hooks::json(&reply);
        }
        let p: Value = hooks::parse(payload)?;
        if !matches!(name, "reader.ui" | "reader.values") { self.record(name, &p); }
        // The SDK's payload types (hooks::reader, hooks::street) read what the game sent: a mismatch is logged.
        if let Err(e) = typed(name, payload) { self.host.warn(format!("probe {name}: SDK type does not read it: {e}")); }
        match name {
            "reader.character_load" => {
                self.notes.clear();
                self.asked_get = false;
                for a in p["accessories"].as_array().into_iter().flatten() {
                    if let (Some(o), Some(s), Some(v)) = (a["outfit"].as_u64(), a["slot"].as_u64(), section_json(a)) {
                        self.notes.insert((o, s), v.as_str().unwrap_or_default().to_owned());
                    }
                }
                Ok(Reply::None)
            }
            "reader.character_save" => {
                let mut list = Vec::new();
                for ((o, s), text) in &self.notes {
                    let mut sec = hooks::section(1, text)?;
                    sec["outfit"] = json!(o);
                    sec["slot"] = json!(s);
                    list.push(sec);
                }
                if list.is_empty() { Ok(Reply::None) } else { hooks::json(&json!({"accessories": list})) }
            }
            "reader.ui" => hooks::json(&json!({"pages": [{
                "name": "Hook Probe", "accessory": true,
                "items": [{"kind": "separator", "label": "每格"}, {"kind": "text", "key": "note", "label": "這一格的備註"}]
            }]})),
            "reader.values" => hooks::json(&json!({"note": self.notes.get(&slot_of(&p)).cloned().unwrap_or_default()})),
            "reader.control" => {
                if p["key"] != "note" { return Err(format!("unknown key {}", p["key"])); }
                let k = slot_of(&p);
                self.record("probe.note_set", &json!({"outfit": k.0, "slot": k.1, "value": p["value"]}));
                self.notes.insert(k, p["value"].as_str().unwrap_or_default().chars().take(60).collect());
                Ok(Reply::None)
            }
            "reader.accessory_transfer" => {
                let o = p["outfit"].as_u64().unwrap_or(0);
                if let (Some(f), Some(t)) = (p["from"].as_u64(), p["to"].as_u64()) {
                    if let Some(n) = self.notes.get(&(o, f)).cloned() { self.notes.insert((o, t), n); }
                }
                Ok(Reply::None)
            }
            "reader.accessory_copy" => {
                let (from, to) = (p["from_outfit"].as_u64().unwrap_or(0), p["to_outfit"].as_u64().unwrap_or(0));
                for s in p["slots"].as_array().into_iter().flatten().filter_map(Value::as_u64) {
                    if let Some(n) = self.notes.get(&(from, s)).cloned() { self.notes.insert((to, s), n); }
                }
                Ok(Reply::None)
            }
            "reader.coordinate_save" => hooks::save(1, &json!({"from": p["card"], "outfit": p["outfit"]})),
            "reader.property_change" if !self.asked_get => {
                self.asked_get = true;
                hooks::reader::get(&["shape.body.*", "nickname"])
            }
            "reader.get_result" => {
                let n = p["values"].as_object().map_or(0, |o| o.len());
                self.host.info(format!("probe got {n} registry value(s)"));
                Ok(Reply::None)
            }
            "street.load" => {
                for h in p["heroines"].as_array().into_iter().flatten() {
                    let n = section_json(&h["section"]).and_then(|v| v["touches"].as_u64()).unwrap_or(0);
                    if let Some(id) = h["id"].as_str() { self.touches.insert(id.to_owned(), n); }
                }
                Ok(Reply::None)
            }
            "street.touch" => {
                let Some(id) = p["heroine"]["id"].as_str() else { return Ok(Reply::None) };
                if !self.written.insert(id.to_owned()) { return Ok(Reply::None); }
                let n = self.touches.get(id).copied().unwrap_or(0) + 1;
                self.host.info(format!("probe writes touches={n} into {id}'s card"));
                hooks::street::cards(&[hooks::street::CardWrite::write(id, 1, &json!({"touches": n}))?])
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(Probe);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brief_hides_data_and_sections_round_trip() {
        assert_eq!(brief(&json!({"a": {"data_b64": "QUJD"}, "b": [1]})), json!({"a": {"data_b64": 4}, "b": [1]}));
        let sec = hooks::section(1, &json!({"touches": 2})).unwrap();
        assert_eq!(section_json(&sec).unwrap()["touches"], 2);
        assert_eq!(slot_of(&json!({"accessory": {"outfit": 1, "slot": 3}})), (1, 3));
    }
}
