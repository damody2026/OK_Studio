//! `outfit-names`: a name for each outfit of a card (Docs/OK_MOD_HOOKS.md; MoreOutfits' names, plan §14.1).
//!
//! Outfit-scoped data in the card's `okMx` (one section, the names by outfit index). The reader's outfit list shows
//! "服裝 1：制服" (the `outfit_names` reply); the "Outfit name" page edits the outfit shown now.
//!
//! Data versions, to show `on_upgrade` (`ExtSection::data`'s upgrade): 1 was a list of names in outfit order, 2 is a
//! map from outfit index to name (an outfit without a name is left out). A card written by version 1 is read and,
//! once saved, written as version 2.

use std::collections::BTreeMap;

use ok_mod_sdk::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::Value;

const DATA_VERSION: u32 = 2;

#[derive(Default, Serialize, Deserialize)]
struct Data {
    names: BTreeMap<String, String>,
}

/// Version 1 (`["制服", "", "泳裝"]`) to 2 (`{"names": {"0": "制服", "2": "泳裝"}}`).
fn upgrade(old: u32, v: Value) -> ModResult<Value> {
    match old {
        1 => {
            let list = v.as_array().ok_or("version 1 data is a list of names")?;
            let names: BTreeMap<String, String> = list.iter().enumerate()
                .filter_map(|(i, n)| n.as_str().filter(|n| !n.is_empty()).map(|n| (i.to_string(), n.to_owned())))
                .collect();
            Ok(serde_json::json!({"names": names}))
        }
        other => Err(format!("unknown data version {other}")),
    }
}

struct OutfitNames {
    host: Host,
    names: BTreeMap<String, String>,
    outfit: i64,
    keep_card: bool,
    edited: bool,
}

impl OutfitNames {
    /// Every name, for the reader's outfit list; a removed name is sent as "" so the list drops it.
    fn names_reply(&self, also_clear: Option<&str>) -> ModResult<Reply> {
        let mut names: serde_json::Map<String, Value> = self.names.iter().map(|(k, v)| (k.clone(), v.clone().into())).collect();
        if let Some(k) = also_clear { names.entry(k.to_owned()).or_insert_with(|| "".into()); }
        hooks::json(&serde_json::json!({"outfit_names": names}))
    }
}

impl Mod for OutfitNames {
    fn create(host: Host) -> ModResult<Self> {
        Ok(OutfitNames { host, names: BTreeMap::new(), outfit: 0, keep_card: false, edited: false })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        for hook in ["reader.character_load", "reader.outfit_change", "reader.character_save", "reader.ui", "reader.values", "reader.control"] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        match name.as_str() {
            "reader.character_load" => {
                let load: hooks::CharacterLoad = hooks::parse(payload)?;
                self.outfit = load.outfit;
                self.names.clear();
                self.edited = false;
                self.keep_card = load.section.is_some();
                match load.data::<Data>(DATA_VERSION, upgrade) {
                    Ok(Some(d)) => { self.names = d.names; self.keep_card = false; }
                    Ok(None) => {}
                    Err(e) => self.host.warn(format!("{}: {e}", load.card)),
                }
                self.names_reply(None)
            }
            "reader.outfit_change" => {
                #[derive(Deserialize)]
                struct Change { outfit: i64 }
                self.outfit = hooks::parse::<Change>(payload)?.outfit;
                Ok(Reply::None)
            }
            "reader.character_save" => {
                if self.keep_card && !self.edited { return Ok(Reply::None); }
                if self.names.is_empty() { return hooks::remove(); }
                hooks::save(DATA_VERSION, &Data { names: self.names.clone() })
            }
            "reader.ui" => hooks::json(&serde_json::json!({"pages": [{
                "name": "服裝名稱",
                "items": [{"kind": "text", "key": "name", "label": "這套服裝的名稱"}],
            }]})),
            "reader.values" => hooks::json(&serde_json::json!({"name": self.names.get(&self.outfit.to_string()).cloned().unwrap_or_default()})),
            "reader.control" => {
                let set: hooks::ReaderSet = hooks::parse(payload)?;
                if set.key != "name" { return Err(format!("unknown key {}", set.key)); }
                let name: String = set.value.as_str().ok_or("name must be a string")?.trim().chars().take(40).collect();
                let key = self.outfit.to_string();
                if name.is_empty() { self.names.remove(&key); } else { self.names.insert(key.clone(), name); }
                self.edited = true;
                self.names_reply(Some(&key))
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(OutfitNames);

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn version_1_lists_upgrade_to_maps() {
        let v = upgrade(1, serde_json::json!(["制服", "", "泳裝"])).unwrap();
        let d: Data = serde_json::from_value(v).unwrap();
        assert_eq!(d.names.get("0").map(String::as_str), Some("制服"));
        assert_eq!(d.names.get("1"), None);
        assert_eq!(d.names.get("2").map(String::as_str), Some("泳裝"));
    }
}
