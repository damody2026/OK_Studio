//! Hooks (`Event::Hook`, Docs/OK_MOD_HOOKS.md): JSON payloads in, JSON replies out, and the mod's own data in a card
//! (`okMx`, ExtendedSave's counterpart) as base64.
//!
//! ```ignore
//! Event::Hook { name, payload } if name == "reader.character_load" => {
//!     let load: hooks::CharacterLoad = hooks::parse(payload)?;
//!     self.text = if load.apply { load.data(1, |_old, v| Ok(v))?.unwrap_or_default() } else { String::new() };
//!     Ok(Reply::None)
//! }
//! Event::Hook { name, .. } if name == "reader.character_save" => hooks::save(1, &self.text),
//! ```

use base64::Engine;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::Value;

use crate::{ModResult, Reply};

fn b64() -> base64::engine::GeneralPurpose { base64::engine::general_purpose::STANDARD }

/// A hook's payload as `T`.
pub fn parse<T: DeserializeOwned>(payload: &str) -> ModResult<T> {
    serde_json::from_str(payload).map_err(|e| format!("hook payload: {e}"))
}

/// A JSON reply.
pub fn json<T: Serialize>(value: &T) -> ModResult<Reply> {
    serde_json::to_string(value).map(|s| Reply::Json(s.into())).map_err(|e| e.to_string())
}

/// This mod's section of a card, as the host hands it over.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct ExtSection {
    pub version: u32,
    #[serde(default)]
    pub requires: Option<Value>,
    pub data_b64: String,
}

impl ExtSection {
    /// The data as `T` (written by `save`/`section`), first brought up to `version` by `upgrade(old version, data)` when
    /// an older version of the mod wrote it (ExtendedSave's `CardBeingImported` counterpart). Newer than `version`:
    /// an error (this mod is older than the card's data), so the caller keeps its defaults and does not save over it.
    pub fn data<T: DeserializeOwned>(&self, version: u32, upgrade: impl FnOnce(u32, Value) -> ModResult<Value>) -> ModResult<T> {
        let bytes = b64().decode(&self.data_b64).map_err(|e| format!("data_b64: {e}"))?;
        let mut value: Value = serde_json::from_slice(&bytes).map_err(|e| format!("section data: {e}"))?;
        if self.version > version {
            return Err(format!("the card's data is version {}, this mod reads up to {version}", self.version));
        }
        if self.version < version { value = upgrade(self.version, value)?; }
        serde_json::from_value(value).map_err(|e| format!("section data: {e}"))
    }
}

/// `reader.character_load`: a card was opened (or the outfit reloaded). `section` is this mod's data in it, if any; `apply`
/// is false when the player turned "apply this mod's data on load" off for this mod.
#[derive(Clone, Debug, Deserialize)]
pub struct CharacterLoad {
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    #[serde(default)]
    pub identity: Option<String>,
    #[serde(default = "yes")]
    pub apply: bool,
    #[serde(default)]
    pub section: Option<ExtSection>,
}
fn yes() -> bool { true }

impl CharacterLoad {
    /// This mod's data (see `ExtSection::data`), None when the card has none or `apply` is off.
    pub fn data<T: DeserializeOwned>(&self, version: u32, upgrade: impl FnOnce(u32, Value) -> ModResult<Value>) -> ModResult<Option<T>> {
        match (&self.section, self.apply) {
            (Some(s), true) => s.data(version, upgrade).map(Some),
            _ => Ok(None),
        }
    }
}

/// The section a `reader.character_save` (or `extract.kkex`) reply carries: `value` as JSON at `version`.
pub fn section<T: Serialize>(version: u32, value: &T) -> ModResult<Value> {
    let bytes = serde_json::to_vec(value).map_err(|e| e.to_string())?;
    Ok(serde_json::json!({"version": version, "data_b64": b64().encode(bytes)}))
}

/// Reply to `reader.character_save` / `extract.kkex`: store `value` as this mod's section.
pub fn save<T: Serialize>(version: u32, value: &T) -> ModResult<Reply> { json(&section(version, value)?) }

/// Reply to `reader.character_save`: remove this mod's section from the card.
pub fn remove() -> ModResult<Reply> { json(&serde_json::json!({"remove": true})) }

/// `extract.kkex`: an original card being converted; each requested KKEx section as msgpack.
#[derive(Clone, Debug, Deserialize)]
pub struct Kkex {
    #[serde(default)]
    pub sections: std::collections::BTreeMap<String, String>,
}
impl Kkex {
    /// The msgpack bytes of KKEx section `key`, if the card has it.
    pub fn section(&self, key: &str) -> Option<Vec<u8>> { self.sections.get(key).and_then(|s| b64().decode(s).ok()) }
}

/// `reader.control`: one of this mod's reader controls changed (`key` without the `mod.<id>.` prefix).
#[derive(Clone, Debug, Deserialize)]
pub struct ReaderSet {
    pub key: String,
    #[serde(default)]
    pub value: Value,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn sections_round_trip_and_upgrade() {
        let v = section(1, &"hello").unwrap();
        let s: ExtSection = serde_json::from_value(v).unwrap();
        assert_eq!(s.data::<String>(1, |_, v| Ok(v)).unwrap(), "hello");
        let upgraded: String = s.data(2, |old, v| Ok(Value::String(format!("{}+v{old}", v.as_str().unwrap())))).unwrap();
        assert_eq!(upgraded, "hello+v1");
        assert!(s.data::<String>(0, |_, v| Ok(v)).is_err(), "data newer than the mod");
    }
}
