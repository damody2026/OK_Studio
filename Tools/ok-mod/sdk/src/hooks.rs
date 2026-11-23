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
    /// The card's resources (okMr) this section's data names, by sha256 hex, as base64 (character_load only).
    #[serde(default, skip_serializing_if = "std::collections::BTreeMap::is_empty")]
    pub resources: std::collections::BTreeMap<String, String>,
}

impl ExtSection {
    /// Resource `hash` (named in this section's data) as the card stores it.
    pub fn resource(&self, hash: &str) -> Option<Vec<u8>> { self.resources.get(hash).and_then(|b| b64().decode(b).ok()) }
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
    /// `section` was made from the original card's KKEx (`extract.kkex`), not read from the card's okMx: the card does
    /// not have it yet, so the mod should write it on the next save.
    #[serde(default)]
    pub imported: bool,
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

/// The name a resource is stored under in the card (okMr): its sha256, lowercase hex. Write it into your data to keep
/// the resource; the host drops resources no section names (plan §6.12).
pub fn resource_hash(bytes: &[u8]) -> String {
    use sha2::Digest;
    sha2::Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

/// Reply to `reader.character_save`: store `value` as this mod's section, with `resources` (pictures, masks...) put in
/// the card once each. `value` must name each one by `resource_hash`; together they may weigh at most 100 MiB per card.
pub fn save_with_resources<T: Serialize>(version: u32, value: &T, resources: &[&[u8]]) -> ModResult<Reply> {
    let mut v = section(version, value)?;
    v["resources_b64"] = resources.iter().map(|r| Value::String(b64().encode(r))).collect();
    json(&v)
}

/// A card file's section of one mod and the resources it names, read straight from the file (feature `card-file`), for
/// hooks that only get the card's path, such as `material.post_texture`.
#[cfg(feature = "card-file")]
pub struct CardMod {
    pub section: ExtSection,
}
#[cfg(feature = "card-file")]
impl CardMod {
    /// Mod `id`'s section of the card at `path` (None: the card has none).
    pub fn read(path: &str, id: &str) -> ModResult<Option<CardMod>> {
        let bytes = std::fs::read(path).map_err(|e| format!("{path}: {e}"))?;
        let data = ok_card_mods::read_data(&bytes)?;
        let Some(section) = data.get(id) else { return Ok(None) };
        let section = section?;
        let res = ok_card_mods::read_resources(&bytes)?;
        let resources = res.by_hash.iter()
            .filter(|(h, _)| section.data.windows(h.len()).any(|w| w == h.as_bytes()))
            .map(|(h, b)| (h.clone(), b64().encode(b))).collect();
        Ok(Some(CardMod { section: ExtSection { version: section.version, requires: None, data_b64: b64().encode(&section.data), resources } }))
    }
}

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

/// The hotkey a `key.<id>.<entry>` hook is for (declared with `Registrar::hotkey`): `Some(entry)`, else `None`.
///
/// ```ignore
/// Event::Hook { name, payload } => match hooks::hotkey(name) {
///     Some("toggle") => { let k: hooks::KeyPress = hooks::parse(payload)?; self.toggle(&k.mode); Ok(Reply::None) }
///     _ => Ok(Reply::None),
/// },
/// ```
pub fn hotkey(hook: &str) -> Option<&str> {
    let rest = hook.strip_prefix("key.")?;
    rest.rsplit_once('.').map(|(_, entry)| entry)
}

/// The payload of a hotkey hook: the mode it was pressed in (reader, studio, pair, street) and the chord as bound.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct KeyPress {
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub chord: String,
}

/// Development-mode hot reload (`Registrar::keep_state`): the old copy answers this hook with its state (`hooks::json`;
/// `Reply::None` keeps nothing). Payload `{"version"}`, the version being replaced.
pub const SAVE_STATE: &str = "dev.save_state";
/// The new copy gets the state the old one saved: payload `RestoreState`.
pub const RESTORE_STATE: &str = "dev.restore_state";

/// The payload of `dev.restore_state`. `state` is what the old copy answered (a text answer arrives as a JSON string);
/// a mod whose state layout changed checks `from_version`, and an `Err` reply fails the reload (the new copy keeps
/// running from scratch).
///
/// ```ignore
/// Event::Hook { name, .. } if name == hooks::SAVE_STATE => hooks::json(&self.counts),
/// Event::Hook { name, payload } if name == hooks::RESTORE_STATE => {
///     let r: hooks::RestoreState<Counts> = hooks::parse(payload)?;
///     self.counts = r.state;
///     Ok(Reply::None)
/// }
/// ```
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct RestoreState<T> {
    #[serde(default)]
    pub from_version: String,
    #[serde(default)]
    pub to_version: String,
    pub state: T,
}
