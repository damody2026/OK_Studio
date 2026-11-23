//! Card reader hooks added in wave 4 (Docs/OK_MOD_HOOKS.md §10; sent by `Source/OpenKoikatsu/OKReaderMods.cpp` and the
//! host's `clothes_store` / `clothes_load`). Every reader payload also carries `card`, the shown character's card path.
//!
//! ```ignore
//! reg.subscribe(hooks::reader::PROPERTY_CHANGE).subscribe(hooks::reader::GET_RESULT);
//! // ...
//! Event::Hook { name, payload } if name.as_str() == hooks::reader::PROPERTY_CHANGE => {
//!     let p: hooks::reader::PropertyChange = hooks::parse(payload)?;
//!     if p.keys.iter().any(|k| k.starts_with("shape.body.")) { return hooks::reader::get(&["body.height", "shape.face.*"]); }
//!     Ok(Reply::None)
//! }
//! Event::Hook { name, payload } if name.as_str() == hooks::reader::GET_RESULT => {
//!     let r: hooks::reader::GetResult = hooks::parse(payload)?;
//!     self.height = r.values.get("body.height").and_then(|v| v.as_f64());
//!     Ok(Reply::None)
//! }
//! ```

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use super::ExtSection;
use crate::{ModResult, Reply};

/// An accessory was put in a slot by the appearance page (or a slot was added: no `slot`, `added`).
pub const ACCESSORY_CHANGE: &str = "reader.accessory_change";
/// The `accessory_transfer` op moved slot `from` of the shown outfit to `to`.
pub const ACCESSORY_TRANSFER: &str = "reader.accessory_transfer";
/// The `accessory_copy` op copied slots of another outfit into the shown one.
pub const ACCESSORY_COPY: &str = "reader.accessory_copy";
/// An outfit card (.okclothes) was exported; answer `CoordinateSave` to store this mod's data in it.
pub const COORDINATE_SAVE: &str = "reader.coordinate_save";
/// An outfit card was put on; its sections of this mod come along.
pub const COORDINATE_LOAD: &str = "reader.coordinate_load";
/// The clothes state buttons changed what she wears.
pub const CLOTHES_STATE: &str = "reader.clothes_state";
/// Sliders, the detailed editor or registry writes changed values (one hook per 0.25 s of changes; not `mod.*`, and
/// not the changes this mod's own reply made).
pub const PROPERTY_CHANGE: &str = "reader.property_change";
/// The answer to a reply's `"get"` (`get`), sent to that mod only.
pub const GET_RESULT: &str = "reader.get_result";

/// `reader.accessory_change`.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct AccessoryChange {
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    /// None when a slot was added (`added`).
    #[serde(default)]
    pub slot: Option<i64>,
    /// The catalogue item put in.
    #[serde(default)]
    pub item: String,
    #[serde(default)]
    pub added: bool,
}

/// `reader.accessory_transfer`: slot `from` of `outfit` moved to slot `to`.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct AccessoryTransfer {
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    #[serde(default)]
    pub from: i64,
    #[serde(default)]
    pub to: i64,
}

/// `reader.accessory_copy`: `slots` of outfit `from_outfit` copied into `to_outfit` (the shown one).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct AccessoryCopy {
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub from_outfit: i64,
    #[serde(default)]
    pub to_outfit: i64,
    #[serde(default)]
    pub slots: Vec<i64>,
}

/// One accessory-scoped section of this mod (`<mod>/acc/<outfit>/<slot>`; in an outfit card no `outfit`).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct AccessorySection {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub outfit: Option<i64>,
    pub slot: i64,
    pub version: u32,
    pub data_b64: String,
}
impl AccessorySection {
    /// The data as `T` (see `ExtSection::data`).
    pub fn data<T: serde::de::DeserializeOwned>(&self, version: u32, upgrade: impl FnOnce(u32, Value) -> ModResult<Value>) -> ModResult<T> {
        ExtSection { version: self.version, requires: None, data_b64: self.data_b64.clone(), resources: Default::default() }.data(version, upgrade)
    }
    /// A section to put in a reply's `"accessories"`: `value` as JSON at `version`. `outfit` None for an outfit card.
    pub fn new<T: Serialize>(outfit: Option<i64>, slot: i64, version: u32, value: &T) -> ModResult<AccessorySection> {
        let s = super::section(version, value)?;
        Ok(AccessorySection { outfit, slot, version, data_b64: s["data_b64"].as_str().unwrap_or_default().to_string() })
    }
}

/// `reader.coordinate_save`: outfit `outfit` of `card` was exported as the outfit card `clothes`.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct CoordinateSave {
    #[serde(default)]
    pub clothes: String,
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
}

/// Reply to `reader.coordinate_save`: this mod's section of the outfit card (`value` at `version`) and its accessory
/// sections (slots only: an outfit card is one outfit).
pub fn coordinate_save<T: Serialize>(version: u32, value: &T, accessories: &[AccessorySection]) -> ModResult<Reply> {
    let mut v = super::section(version, value)?;
    if !accessories.is_empty() {
        if accessories.iter().any(|a| a.outfit.is_some()) {
            return Err("an outfit card's accessory sections have no outfit".into());
        }
        v["accessories"] = serde_json::to_value(accessories).map_err(|e| e.to_string())?;
    }
    super::json(&v)
}

/// `reader.coordinate_load`: the outfit card `clothes` was put on as outfit `outfit` of `card`; `section` and
/// `accessories` are this mod's data in it.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct CoordinateLoad {
    #[serde(default)]
    pub clothes: String,
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    #[serde(default)]
    pub section: Option<ExtSection>,
    #[serde(default)]
    pub accessories: Vec<AccessorySection>,
}

/// `reader.clothes_state`: what she wears of outfit `outfit` after a clothes button (`kind`: the part pressed;
/// `states`: the nine parts' states, as the reader keeps them).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct ClothesState {
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    #[serde(default)]
    pub kind: i64,
    #[serde(default)]
    pub states: Vec<i64>,
}

/// `reader.property_change`: registry keys changed and their values now.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct PropertyChange {
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    #[serde(default)]
    pub keys: Vec<String>,
    #[serde(default)]
    pub values: Map<String, Value>,
}

/// `reader.get_result`: the values a `"get"` asked for, by key (prefix requests expanded).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct GetResult {
    #[serde(default)]
    pub card: String,
    #[serde(default)]
    pub outfit: i64,
    #[serde(default)]
    pub values: Map<String, Value>,
}

/// Most keys one `"get"` may ask for.
pub const GET_MAX: usize = 256;

/// Reply asking the reader for registry values (keys, or prefixes ending in `*`; at most `GET_MAX`; `mod.*` is not
/// given): they come back to this mod alone as `reader.get_result`. Its answer is followed like any reply, but may not
/// ask again. To ask along with other reply fields, put `"get"` in your own JSON (`with_get`).
pub fn get(keys: &[&str]) -> ModResult<Reply> {
    super::json(&with_get(Value::Object(Map::new()), keys)?)
}

/// `reply` (a JSON object: `set`, `notice`, ...) with `"get": keys` added.
pub fn with_get(mut reply: Value, keys: &[&str]) -> ModResult<Value> {
    if keys.is_empty() || keys.len() > GET_MAX {
        return Err(format!("get asks for 1..{GET_MAX} keys, not {}", keys.len()));
    }
    let Some(obj) = reply.as_object_mut() else { return Err("a reply with get is a JSON object".into()) };
    obj.insert("get".into(), keys.iter().map(|k| Value::String((*k).into())).collect());
    Ok(reply)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payloads_parse_as_the_reader_sends_them() {
        let a: AccessoryChange = serde_json::from_str(r#"{"card":"c.png","outfit":1,"item":"ao_hair_01","added":true}"#).unwrap();
        assert_eq!((a.slot, a.added), (None, true));
        let c: AccessoryCopy = serde_json::from_str(r#"{"card":"c","from_outfit":2,"to_outfit":0,"slots":[1,3]}"#).unwrap();
        assert_eq!(c.slots, vec![1, 3]);
        let p: PropertyChange = serde_json::from_str(r#"{"card":"c","outfit":0,"keys":["shape.body.height"],"values":{"shape.body.height":0.6}}"#).unwrap();
        assert_eq!(p.values["shape.body.height"], 0.6);
        let l: CoordinateLoad = serde_json::from_str(r#"{"clothes":"x.okclothes","card":"c","outfit":0,"section":null,"accessories":[{"slot":2,"version":1,"data_b64":"IjEi"}]}"#).unwrap();
        assert_eq!(l.accessories[0].data::<String>(1, |_, v| Ok(v)).unwrap(), "1");
    }

    #[test]
    fn get_and_coordinate_replies() {
        let Reply::Json(j) = get(&["body.height", "shape.face.*"]).unwrap() else { panic!() };
        assert_eq!(j.as_str(), r#"{"get":["body.height","shape.face.*"]}"#);
        assert!(get(&[]).is_err());
        let v = with_get(serde_json::json!({"notice": "hi"}), &["a"]).unwrap();
        assert_eq!(v["notice"], "hi");
        let acc = AccessorySection::new(None, 3, 1, &"x").unwrap();
        let Reply::Json(j) = coordinate_save(2, &5, &[acc]).unwrap() else { panic!() };
        let v: Value = serde_json::from_str(j.as_str()).unwrap();
        assert_eq!((v["version"].as_u64(), v["accessories"][0]["slot"].as_i64()), (Some(2), Some(3)));
        assert!(v["accessories"][0].get("outfit").is_none());
        assert!(coordinate_save(1, &0, &[AccessorySection::new(Some(0), 1, 1, &0).unwrap()]).is_err());
    }
}
