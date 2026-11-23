//! Street hooks added in wave 4 and the `cards` reply (Docs/OK_MOD_HOOKS.md §10; sent by
//! `Source/OpenKoikatsu/OKStreetSocialMods.inl` and its callers). Every street payload also carries the day: `day`,
//! `date` (YYYY-MM-DD), `minute` (of the day) and `lang` (`Day`, flattened into each payload here).
//!
//! Rules only record (plan §6.6): these hooks say what happened; what she makes of it stays with the AI.
//!
//! ```ignore
//! Event::Hook { name, payload } if name.as_str() == hooks::street::LOAD => {
//!     let load: hooks::street::Load = hooks::parse(payload)?;
//!     for h in &load.heroines { if let Some(s) = &h.section { self.notes.insert(h.id.clone(), s.data(1, |_, v| Ok(v))?); } }
//!     Ok(Reply::None)
//! }
//! Event::Hook { name, .. } if name.as_str() == hooks::street::DAY_CHANGE => {
//!     // Write back rarely (a day's end, a turn in the relationship): each write remakes her clinic card.
//!     let writes = self.notes.iter().map(|(id, n)| hooks::street::CardWrite::write(id, 1, n)).collect::<ModResult<Vec<_>>>()?;
//!     hooks::street::cards(&writes)
//! }
//! ```

use serde::{Deserialize, Serialize};
use serde_json::Value;

use super::ExtSection;
use crate::{ModResult, Reply};

/// A save was loaded (or a new game started: `new_game`); each heroine carries this mod's section of her card.
pub const LOAD: &str = "street.load";
pub const DAY_CHANGE: &str = "street.day_change";
/// The part of the day turned: morning 5-11, day 11-17, evening 17-20, night 20-5.
pub const PERIOD_CHANGE: &str = "street.period_change";
/// He touched her and the touch was settled.
pub const TOUCH: &str = "street.touch";
/// An interaction with her ended: done, only recorded, or refused.
pub const ACTION: &str = "street.action";
/// He came into another place (the first place of a session is not told).
pub const ARRIVE: &str = "street.arrive";
/// A call between them, either way (`from`: "him" / "her").
pub const PHONE: &str = "street.phone";

/// The day every street payload carries.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Day {
    #[serde(default)]
    pub day: i64,
    #[serde(default)]
    pub date: String,
    #[serde(default)]
    pub minute: i64,
    #[serde(default)]
    pub lang: String,
}

/// One heroine as the mods see her.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Heroine {
    /// Stable across saves and card edits: key a mod's data by it.
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    /// MM-DD, when her profile has one.
    #[serde(default)]
    pub birthday: Option<String>,
    /// `street.load` only: this mod's section of her card (None when it has none).
    #[serde(default)]
    pub section: Option<ExtSection>,
}

/// `street.load`.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Load {
    #[serde(flatten)]
    pub day: Day,
    #[serde(default)]
    pub heroines: Vec<Heroine>,
    /// The save had no calendar yet: a new game.
    #[serde(default)]
    pub new_game: bool,
    /// What this mod kept in the save (`ext.mods.<id>`), null when nothing.
    #[serde(default)]
    pub state: Value,
}

/// `street.period_change`: `period` and the one before (`morning`, `day`, `evening`, `night`).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct PeriodChange {
    #[serde(flatten)]
    pub day: Day,
    #[serde(default)]
    pub period: String,
    #[serde(default)]
    pub previous: String,
}

/// `street.touch`: where he touched her (`head`, `cheek`, `hand_l`, `hand_r`, `chest_l`, `chest_r`), whether she saw it
/// coming (`look`) and how many times in a row (`repeat`).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Touch {
    #[serde(flatten)]
    pub day: Day,
    #[serde(default)]
    pub heroine: Heroine,
    #[serde(default)]
    pub part: String,
    #[serde(default)]
    pub look: bool,
    #[serde(default)]
    pub repeat: i64,
}

/// `street.action`: interaction `act` with her (`hers`: she started it), done, only recorded or refused (`why`).
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Action {
    #[serde(flatten)]
    pub day: Day,
    #[serde(default)]
    pub heroine: Heroine,
    #[serde(default)]
    pub act: String,
    #[serde(default)]
    pub hers: bool,
    #[serde(default)]
    pub record_only: bool,
    #[serde(default)]
    pub done: bool,
    #[serde(default)]
    pub refused: bool,
    #[serde(default)]
    pub why: Option<String>,
    #[serde(default)]
    pub reaction: f64,
    #[serde(default)]
    pub place: String,
}

/// `street.arrive`: he (`who`: "him") came from `from` into `place`; `heroine` when he is on a date or talking with her.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Arrive {
    #[serde(flatten)]
    pub day: Day,
    #[serde(default)]
    pub who: String,
    #[serde(default)]
    pub place: String,
    #[serde(default)]
    pub place_name: Option<String>,
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub heroine: Option<Heroine>,
}

/// `street.phone`: a call (`kind`: "call") from him or from her; answered, declined (she called, he hung up) or missed.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
pub struct Phone {
    #[serde(flatten)]
    pub day: Day,
    #[serde(default)]
    pub heroine: Heroine,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub answered: bool,
    #[serde(default)]
    pub declined: bool,
}

/// One entry of a `cards` reply: this mod's section of a heroine's card written, or removed.
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct CardWrite {
    pub heroine: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub version: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub data_b64: Option<String>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub remove: bool,
}

/// Most bytes one section written to her card may have.
pub const CARD_SECTION_MAX: usize = 1 << 20;

impl CardWrite {
    /// `value` as JSON at `version` in heroine `heroine`'s card (her own card; at most `CARD_SECTION_MAX` bytes).
    pub fn write<T: Serialize>(heroine: &str, version: u32, value: &T) -> ModResult<CardWrite> {
        let bytes = serde_json::to_vec(value).map_err(|e| e.to_string())?;
        if bytes.len() > CARD_SECTION_MAX {
            return Err(format!("{} bytes for {heroine}'s card: at most {CARD_SECTION_MAX}", bytes.len()));
        }
        let s = super::section(version, value)?;
        Ok(CardWrite { heroine: heroine.into(), version: Some(version), data_b64: s["data_b64"].as_str().map(String::from), remove: false })
    }
    /// This mod's section removed from her card.
    pub fn remove(heroine: &str) -> CardWrite {
        CardWrite { heroine: heroine.into(), version: None, data_b64: None, remove: true }
    }
}

/// Reply writing (or removing) this mod's data in the heroines' cards: `{"cards": [...]}`; any street hook may answer
/// it. A write changes her card file (its size and time), so the clinic's remade card is built again: write at a day's
/// end or a turn in the relationship, not on every event.
pub fn cards(writes: &[CardWrite]) -> ModResult<Reply> {
    super::json(&with_cards(Value::Object(Default::default()), writes)?)
}

/// `reply` (a JSON object: `rules`, `facts`, ...) with `"cards"` added.
pub fn with_cards(mut reply: Value, writes: &[CardWrite]) -> ModResult<Value> {
    let Some(obj) = reply.as_object_mut() else { return Err("a reply with cards is a JSON object".into()) };
    obj.insert("cards".into(), serde_json::to_value(writes).map_err(|e| e.to_string())?);
    Ok(reply)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payloads_parse_as_the_street_sends_them() {
        let l: Load = serde_json::from_str(r#"{"day":3,"date":"2026-04-03","minute":480,"lang":"zh-TW","new_game":true,"state":null,
            "heroines":[{"id":"h1","name":"A","birthday":"04-05","section":{"version":1,"data_b64":"IngiIA=="}},{"id":"h2","name":"B","section":null}]}"#).unwrap();
        assert!(l.new_game && l.day.minute == 480 && l.heroines[1].section.is_none());
        assert_eq!(l.heroines[0].section.as_ref().unwrap().data::<String>(1, |_, v| Ok(v)).unwrap(), "x");
        let p: Phone = serde_json::from_str(r#"{"day":1,"heroine":{"id":"h1","name":"A"},"kind":"call","from":"her","answered":false,"declined":true}"#).unwrap();
        assert!(p.declined && p.from == "her");
        let a: Arrive = serde_json::from_str(r#"{"who":"him","place":"cafe","from":"park"}"#).unwrap();
        assert!(a.heroine.is_none() && a.place_name.is_none());
        let a: Action = serde_json::from_str(r#"{"heroine":{"id":"h"},"act":"hug","hers":false,"record_only":false,"done":false,"refused":true,"why":"tired","reaction":-0.5,"place":"cafe"}"#).unwrap();
        assert_eq!(a.why.as_deref(), Some("tired"));
    }

    #[test]
    fn cards_reply() {
        let Reply::Json(j) = cards(&[CardWrite::write("h1", 2, &"note").unwrap(), CardWrite::remove("h2")]).unwrap() else { panic!() };
        let v: Value = serde_json::from_str(j.as_str()).unwrap();
        assert_eq!(v["cards"][0]["version"], 2);
        assert!(v["cards"][0].get("remove").is_none());
        assert_eq!(v["cards"][1], serde_json::json!({"heroine": "h2", "remove": true}));
        assert!(CardWrite::write("h", 1, &"x".repeat(CARD_SECTION_MAX + 1)).is_err());
    }
}
