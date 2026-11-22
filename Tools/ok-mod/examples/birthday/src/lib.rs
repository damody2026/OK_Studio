//! `birthday`: what happened on her birthdays, remembered (plan §14.3; GameAPI DayChange + a TopicApi-like plugin).
//!
//! The street already knows birthdays (her 【今天】 line says it is her birthday, a gift counts for more). This mod adds
//! what the core does not keep: **each year, whether he came to see her on her birthday and whether she took a gift**,
//! saved in the street save (`ext.mods.org.openkoikatsu.birthday`), and handed to her as facts on her later turns.
//!
//! Rules only record (plan §6.6): the mod never decides what she says or how she feels about it, it only states what
//! happened ("last year on your birthday he came to see you and gave you a gift"). No pressure: nothing is said about a
//! birthday he missed, and nothing counts down. In the morning of a birthday the player gets a small notice.
//!
//! Hooks: street.load, street.day_change, street.talk_begin, street.gift, street.talk_facts, and the namespaced rule
//! `org.openkoikatsu.birthday.upcoming` (street.rule): the next birthdays, for any code that asks.

use std::collections::BTreeMap;

use ok_mod_sdk::prelude::*;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// One heroine as the street hands her over.
#[derive(Clone, Default, Deserialize)]
struct Heroine {
    id: String,
    #[serde(default)]
    name: String,
    /// "MM-DD"
    #[serde(default)]
    birthday: Option<String>,
}

/// What happened on one of her birthdays.
#[derive(Clone, Default, Debug, PartialEq, Serialize, Deserialize)]
struct Year {
    #[serde(default)]
    met: bool,
    #[serde(default)]
    gift: bool,
}

/// The saved state: by heroine id, by year.
#[derive(Clone, Default, Debug, PartialEq, Serialize, Deserialize)]
struct State {
    #[serde(default)]
    years: BTreeMap<String, BTreeMap<i32, Year>>,
}

#[derive(Deserialize)]
struct Common {
    #[serde(default)]
    date: String,
    #[serde(default)]
    lang: String,
    #[serde(default)]
    heroine: Option<Heroine>,
    #[serde(default)]
    heroines: Vec<Heroine>,
}

/// "YYYY-MM-DD" -> (year, month, day).
fn ymd(date: &str) -> Option<(i32, u32, u32)> {
    let mut p = date.split('-');
    Some((p.next()?.parse().ok()?, p.next()?.parse().ok()?, p.next()?.parse().ok()?))
}
/// "MM-DD" -> (month, day).
fn md(birthday: &str) -> Option<(u32, u32)> {
    let (m, d) = birthday.split_once('-')?;
    Some((m.parse().ok()?, d.parse().ok()?))
}
/// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
fn days(y: i32, m: u32, d: u32) -> i64 {
    let y = if m <= 2 { y - 1 } else { y } as i64;
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let mp = (m as i64 + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d as i64 - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}
/// Days from `date` to her next birthday (0 = today). Feb 29 counts on Mar 1 in other years.
fn days_until(date: (i32, u32, u32), birthday: (u32, u32)) -> i64 {
    let (y, m, d) = date;
    let today = days(y, m, d);
    let on = |year: i32| {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
        let (bm, bd) = if birthday == (2, 29) && !leap { (3, 1) } else { birthday };
        days(year, bm, bd)
    };
    let this = on(y);
    if this >= today { this - today } else { on(y + 1) - today }
}

fn words(lang: &str) -> &'static [&'static str; 6] {
    // 0 notice, 1 met+gift, 2 met, 3 today met, 4 today gift, 5 year label
    match lang {
        "en" => &["Today is {name}'s birthday.", "on your birthday in {year} he came to see you and you took a gift from him", "on your birthday in {year} he came to see you", "today, your birthday, he has come to see you", "today, your birthday, you took a gift from him", ""],
        "zh-CN" => &["今天是{name}的生日。", "{year} 年你生日那天，他来见了你，你也收下了他的礼物", "{year} 年你生日那天，他来见了你", "今天是你生日，他来找你了", "今天是你生日，你收下了他的礼物", ""],
        _ => &["今天是{name}的生日。", "{year} 年你生日那天，他來見了你，你也收下了他的禮物", "{year} 年你生日那天，他來見了你", "今天是你生日，他來找你了", "今天是你生日，你收下了他的禮物", ""],
    }
}

struct Birthday {
    state: State,
    heroines: BTreeMap<String, Heroine>,
}

impl Birthday {
    fn remember(&mut self, list: &[Heroine]) {
        for h in list { self.heroines.insert(h.id.clone(), h.clone()); }
    }
    fn is_birthday(h: &Heroine, date: &str) -> Option<i32> {
        let (y, m, d) = ymd(date)?;
        (md(h.birthday.as_deref()?)? == (m, d)).then_some(y)
    }
    /// Marks this year's birthday; Some(state reply) when it changed.
    fn mark(&mut self, h: &Heroine, date: &str, f: impl FnOnce(&mut Year)) -> Option<Value> {
        let year = Self::is_birthday(h, date)?;
        let entry = self.state.years.entry(h.id.clone()).or_default().entry(year).or_default();
        let before = entry.clone();
        f(entry);
        (*entry != before).then(|| json!({"state": self.state}))
    }
    fn facts(&self, h: &Heroine, date: &str, lang: &str) -> Vec<String> {
        let w = words(lang);
        let Some(years) = self.state.years.get(&h.id) else { return Vec::new() };
        let today = Self::is_birthday(h, date);
        let mut out = Vec::new();
        for (year, y) in years.iter().rev() {
            if Some(*year) == today {
                if y.gift { out.push(w[4].to_string()); } else if y.met { out.push(w[3].to_string()); }
            } else if y.met {
                out.push(w[if y.gift { 1 } else { 2 }].replace("{year}", &year.to_string()));
            }
            if out.len() >= 3 { break; }
        }
        out
    }
    fn upcoming(&self, date: &str, within: i64) -> Value {
        let Some(today) = ymd(date) else { return json!({"upcoming": []}) };
        let mut list: Vec<(i64, &Heroine)> = self.heroines.values()
            .filter_map(|h| Some((days_until(today, md(h.birthday.as_deref()?)?), h)))
            .filter(|(n, _)| *n <= within).collect();
        list.sort_by_key(|(n, h)| (*n, h.id.clone()));
        json!({"upcoming": list.iter().map(|(n, h)| json!({"id": h.id, "name": h.name, "birthday": h.birthday, "in_days": n})).collect::<Vec<_>>()})
    }
}

impl Mod for Birthday {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(Birthday { state: State::default(), heroines: BTreeMap::new() })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        for hook in ["street.load", "street.day_change", "street.talk_begin", "street.gift", "street.talk_facts", "street.rule"] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        let name = name.as_str();
        match name {
            "street.load" => {
                #[derive(Deserialize)]
                struct Load { #[serde(default)] state: Value, #[serde(default)] heroines: Vec<Heroine> }
                let load: Load = hooks::parse(payload)?;
                self.state = if load.state.is_null() { State::default() } else { serde_json::from_value(load.state).map_err(|e| format!("saved state: {e}"))? };
                self.heroines.clear();
                self.remember(&load.heroines);
                Ok(Reply::None)
            }
            "street.day_change" => {
                let c: Common = hooks::parse(payload)?;
                self.remember(&c.heroines);
                let names: Vec<&str> = c.heroines.iter().filter(|h| Self::is_birthday(h, &c.date).is_some()).map(|h| h.name.as_str()).collect();
                if names.is_empty() { return Ok(Reply::None); }
                let sep = if c.lang == "en" { ", " } else { "、" };
                hooks::json(&json!({"notice": words(&c.lang)[0].replace("{name}", &names.join(sep))}))
            }
            "street.talk_begin" | "street.gift" => {
                #[derive(Deserialize)]
                struct Ev { #[serde(default)] date: String, heroine: Heroine, #[serde(default)] accepted: bool }
                let e: Ev = hooks::parse(payload)?;
                let gift = name == "street.gift";
                if gift && !e.accepted { return Ok(Reply::None); }
                match self.mark(&e.heroine, &e.date, |y| { y.met = true; if gift { y.gift = true; } }) {
                    Some(v) => hooks::json(&v),
                    None => Ok(Reply::None),
                }
            }
            "street.talk_facts" => {
                let c: Common = hooks::parse(payload)?;
                let Some(h) = c.heroine else { return Ok(Reply::None) };
                let facts = self.facts(&h, &c.date, &c.lang);
                if facts.is_empty() { Ok(Reply::None) } else { hooks::json(&json!({"facts": facts})) }
            }
            "street.rule" => {
                #[derive(Deserialize)]
                struct Rule { rule: String, #[serde(default)] request: Value }
                let r: Rule = hooks::parse(payload)?;
                match r.rule.as_str() {
                    // {"rule":"org.openkoikatsu.birthday.upcoming","date":"YYYY-MM-DD","within":30}
                    "upcoming" => {
                        let date = r.request.get("date").and_then(Value::as_str).map(str::to_owned).unwrap_or_default();
                        let within = r.request.get("within").and_then(Value::as_i64).unwrap_or(30);
                        hooks::json(&self.upcoming(&date, within))
                    }
                    other => Err(format!("unknown rule {other}")),
                }
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(Birthday);

#[cfg(test)]
mod tests {
    use super::*;

    fn her(id: &str, birthday: &str) -> Heroine { Heroine { id: id.into(), name: id.to_uppercase(), birthday: Some(birthday.into()) } }

    #[test]
    fn dates() {
        assert_eq!(days(1970, 1, 1), 0);
        assert_eq!(days_until((2026, 11, 23), (11, 23)), 0);
        assert_eq!(days_until((2026, 11, 23), (11, 25)), 2);
        assert_eq!(days_until((2026, 12, 31), (1, 1)), 1);
        assert_eq!(days_until((2027, 2, 28), (2, 29)), 1, "Feb 29 on Mar 1 in a common year");
    }

    #[test]
    fn records_and_tells_only_what_happened() {
        let mut b = Birthday { state: State::default(), heroines: BTreeMap::new() };
        let a = her("a", "11-23");
        assert!(b.mark(&a, "2026-11-22", |y| y.met = true).is_none(), "not her birthday: nothing recorded");
        assert!(b.mark(&a, "2026-11-23", |y| y.met = true).is_some());
        assert!(b.mark(&a, "2026-11-23", |y| y.met = true).is_none(), "the same again: no change");
        assert!(b.mark(&a, "2026-11-23", |y| y.gift = true).is_some());
        assert_eq!(b.facts(&a, "2026-11-23", "zh-TW"), vec!["今天是你生日，你收下了他的禮物"]);
        let next_year = b.facts(&a, "2027-03-01", "en");
        assert_eq!(next_year, vec!["on your birthday in 2026 he came to see you and you took a gift from him"]);
        // A heroine he never saw on her birthday: nothing said at all.
        assert!(b.facts(&her("c", "01-01"), "2027-03-01", "en").is_empty());
        // The state survives a save as JSON.
        let saved = serde_json::to_value(&b.state).unwrap();
        assert_eq!(serde_json::from_value::<State>(saved).unwrap(), b.state);
    }

    #[test]
    fn upcoming_rule() {
        let mut b = Birthday { state: State::default(), heroines: BTreeMap::new() };
        b.remember(&[her("a", "11-25"), her("b", "01-10"), Heroine { id: "c".into(), ..Default::default() }]);
        let v = b.upcoming("2026-11-23", 60);
        let ids: Vec<&str> = v["upcoming"].as_array().unwrap().iter().map(|h| h["id"].as_str().unwrap()).collect();
        assert_eq!(ids, vec!["a", "b"]);
        assert_eq!(v["upcoming"][0]["in_days"], 2);
    }
}
