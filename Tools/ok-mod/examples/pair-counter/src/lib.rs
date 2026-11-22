//! `pair-counter` (HSceneProc / GameAPI StartH-EndH statistics; Docs/OK_MOD_FRAMEWORK_PLAN.md §14.3): every one-on-one
//! with her is counted in her card. When it ends (`pair.exit`) the mod adds one time, the seconds it lasted and how
//! often each came during it (`pair.finish`), and writes that back into the card's `okMx` as its own section; the host
//! hands the section over on `pair.enter` / `pair.exit` and writes the reply (`hooks::save`) into the card file.
//! The street's fitting room (`fitting`) and one-on-ones left before they were ready (`cancelled`) are not counted.
//!
//! Card data (version 1): `{"times", "seconds", "her", "him", "last"}` (`last`: Unix seconds of the last one).
//! The reader shows it through the reader hooks (after sync point B).

use ok_mod_sdk::prelude::*;
use serde::{Deserialize, Serialize};

const VERSION: u32 = 1;

#[derive(Clone, Debug, Default, Deserialize, Serialize, PartialEq)]
pub struct Stats {
    #[serde(default)]
    pub times: u64,
    #[serde(default)]
    pub seconds: f64,
    /// Her finishes (`pair.finish` kinds starting with "org").
    #[serde(default)]
    pub her: u64,
    /// His (the other kinds: "same_*", "*_in", "*_out" …).
    #[serde(default)]
    pub him: u64,
    #[serde(default)]
    pub last: u64,
}

#[derive(Deserialize)]
struct PairEvent {
    #[serde(default)]
    card: String,
    #[serde(default)]
    text: String,
    #[serde(default)]
    cancelled: bool,
    #[serde(default)]
    fitting: bool,
    #[serde(default)]
    seconds: f64,
    #[serde(default)]
    section: Option<hooks::ExtSection>,
}

struct Counter {
    host: Host,
    /// Finishes during the one-on-one going on now, for its card.
    card: String,
    her: u64,
    him: u64,
}

fn now() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// Whose finish a `pair.finish` kind is: "org*" hers, "same*" both, else his.
pub fn finish_of(kind: &str) -> (u64, u64) {
    if kind.starts_with("same") {
        (1, 1)
    } else if kind.starts_with("org") {
        (1, 0)
    } else {
        (0, 1)
    }
}

impl Counter {
    fn stats(&self, e: &PairEvent) -> Stats {
        match &e.section {
            Some(s) => s.data(VERSION, |_old, v| Ok(v)).unwrap_or_else(|err| {
                self.host.log(LogLevel::Warn, format!("{}: keeping the card's data as it is: {err}", e.card));
                Stats::default()
            }),
            None => Stats::default(),
        }
    }
}

impl Mod for Counter {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Counter { host, card: String::new(), her: 0, him: 0 })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.subscribe("pair.enter").subscribe("pair.finish").subscribe("pair.exit");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        let e: PairEvent = hooks::parse(payload)?;
        if e.fitting {
            return Ok(Reply::None);
        }
        match name.as_str() {
            "pair.enter" => {
                self.card = e.card;
                self.her = 0;
                self.him = 0;
                Ok(Reply::None)
            }
            "pair.finish" => {
                let (her, him) = finish_of(&e.text);
                self.her += her;
                self.him += him;
                Ok(Reply::None)
            }
            "pair.exit" => {
                let (her, him) = if e.card == self.card { (self.her, self.him) } else { (0, 0) };
                self.card.clear();
                self.her = 0;
                self.him = 0;
                if e.cancelled || e.card.is_empty() {
                    return Ok(Reply::None);
                }
                // The section the host read from the card just now: one card file, whatever happened since enter.
                if e.section.as_ref().is_some_and(|s| s.version > VERSION) {
                    self.host.log(LogLevel::Warn, format!("{}: card data newer than this mod, not counted", e.card));
                    return Ok(Reply::None);
                }
                let mut s = self.stats(&e);
                s.times += 1;
                s.seconds += e.seconds.max(0.0);
                s.her += her;
                s.him += him;
                s.last = now();
                self.host.log(LogLevel::Info, format!("{}: {} time(s), {:.0} s in all", e.card, s.times, s.seconds));
                hooks::save(VERSION, &s)
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(Counter);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finishes_are_told_apart() {
        assert_eq!(finish_of("org_in"), (1, 0));
        assert_eq!(finish_of("same_out"), (1, 1));
        assert_eq!(finish_of("in"), (0, 1));
    }

    #[test]
    fn stats_round_trip_through_a_section() {
        let s = Stats { times: 2, seconds: 30.5, her: 1, him: 3, last: 9 };
        let section: hooks::ExtSection = serde_json::from_value(hooks::section(VERSION, &s).unwrap()).unwrap();
        assert_eq!(section.data::<Stats>(VERSION, |_, v| Ok(v)).unwrap(), s);
    }
}
