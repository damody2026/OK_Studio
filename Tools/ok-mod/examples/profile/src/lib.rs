//! `profile`: a character profile text kept in the card (Docs/OK_MOD_HOOKS.md; the reference mod of
//! Docs/OK_MOD_FRAMEWORK_PLAN.md §14.1, KK_Plugins' Profile).
//!
//! - Converting an original card: its `KK_Profile` KKEx section (`ProfileText`) becomes this mod's `okMx` data (`kkex`).
//! - Opening a card: the text is read from the card (`character_load`), shown on the reader's "Profile" page and as the
//!   registry key `mod.org.openkoikatsu.profile.text` (reader_call get/set reach it).
//! - Saving: the text goes back into the card (`character_save`); an empty text removes the section.
//! - When "apply this mod's data on load" is off, or the card's data is newer than this mod, the card's section is kept
//!   as it is on save (never overwritten with an empty text) unless the text was edited.

use ok_mod_sdk::prelude::*;
use serde::{Deserialize, Serialize};

/// Version of the data this mod writes. 1: `{"text": "..."}`.
const DATA_VERSION: u32 = 1;

#[derive(Default, Serialize, Deserialize)]
struct Data {
    text: String,
}

struct Profile {
    host: Host,
    text: String,
    /// The card has a section this mod did not read (apply off, or unreadable): saved back as it is unless edited.
    keep_card: bool,
    edited: bool,
}

/// `ProfileText` anywhere in a KKEx section (ExtendedSave writes `[version, {..}]` or `{version, data: {..}}`).
fn profile_text(v: &rmpv::Value) -> Option<String> {
    match v {
        rmpv::Value::Map(items) => items.iter().find_map(|(k, v)| {
            if k.as_str() == Some("ProfileText") { v.as_str().map(str::to_owned) } else { profile_text(v) }
        }),
        rmpv::Value::Array(items) => items.iter().find_map(profile_text),
        _ => None,
    }
}

impl Mod for Profile {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Profile { host, text: String::new(), keep_card: false, edited: false })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        for hook in ["extract.kkex_keys", "extract.kkex", "reader.character_load", "reader.character_save", "reader.ui", "reader.values", "reader.control"] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        match name.as_str() {
            "extract.kkex_keys" => hooks::json(&serde_json::json!({"keys": ["KK_Profile"]})),
            "extract.kkex" => {
                let kkex: hooks::Kkex = hooks::parse(payload)?;
                let Some(bytes) = kkex.section("KK_Profile") else { return Ok(Reply::None) };
                let value = rmpv::decode::read_value(&mut &bytes[..]).map_err(|e| format!("KK_Profile: {e}"))?;
                match profile_text(&value) {
                    Some(text) if !text.trim().is_empty() => hooks::save(DATA_VERSION, &Data { text }),
                    _ => Ok(Reply::None),
                }
            }
            "reader.character_load" => {
                let load: hooks::CharacterLoad = hooks::parse(payload)?;
                self.edited = false;
                self.keep_card = load.section.is_some();
                self.text.clear();
                if let Some(data) = load.data::<Data>(DATA_VERSION, |_, v| Ok(v)).unwrap_or_else(|e| {
                    self.host.warn(format!("{}: {e}", load.card));
                    None
                }) {
                    self.text = data.text;
                    self.keep_card = false;
                    // From the original card's KK_Profile: the card has no section yet; saving writes it.
                    self.edited = load.imported;
                }
                Ok(Reply::None)
            }
            "reader.character_save" => {
                if self.keep_card && !self.edited { return Ok(Reply::None); }
                if self.text.trim().is_empty() { return hooks::remove(); }
                hooks::save(DATA_VERSION, &Data { text: self.text.clone() })
            }
            // Two tabs (Docs/OK_MOD_HOOKS.md §4): the text in a multi-line field with its length under it, and a note on
            // where the text comes from and goes.
            "reader.ui" => hooks::json(&serde_json::json!({"pages": [{
                "name": "角色簡介",
                "layout": "tabs",
                "items": [
                    {"kind": "group", "label": "簡介", "items": [
                        {"kind": "text", "key": "text", "label": "簡介", "multiline": true, "height": 160, "placeholder": "寫下她的簡介"},
                        {"kind": "label", "key": "length", "style": "Caption"},
                    ]},
                    {"kind": "group", "label": "說明", "items": [
                        {"kind": "label", "text": "簡介存在卡片裡（OK 卡的 mod 資料），另存卡片時寫入；原作卡的 KK_Profile 會在開卡時帶進來。", "style": "Body"},
                    ]},
                ],
            }]})),
            "reader.values" => hooks::json(&serde_json::json!({
                "text": self.text,
                "length": format!("{} / 2000 字", self.text.chars().count()),
            })),
            "reader.control" => {
                let set: hooks::ReaderSet = hooks::parse(payload)?;
                if set.key != "text" { return Err(format!("unknown key {}", set.key)); }
                self.text = set.value.as_str().ok_or("text must be a string")?.chars().take(2000).collect();
                self.edited = true;
                Ok(Reply::None)
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(Profile);

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn finds_profile_text_in_both_shapes() {
        let inner = rmpv::Value::Map(vec![("ProfileText".into(), "她喜歡貓".into())]);
        assert_eq!(profile_text(&rmpv::Value::Array(vec![0.into(), inner.clone()])).as_deref(), Some("她喜歡貓"));
        let outer = rmpv::Value::Map(vec![("version".into(), 0.into()), ("data".into(), inner)]);
        assert_eq!(profile_text(&outer).as_deref(), Some("她喜歡貓"));
    }
}
