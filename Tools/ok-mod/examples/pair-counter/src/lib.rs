//! `pair-counter` (HSceneProc / GameAPI StartH-EndH statistics; Docs/OK_MOD_FRAMEWORK_PLAN.md §14.3): every one-on-one
//! with her is counted in her card. When it ends (`pair.exit`) the mod adds one time, the seconds it lasted and how
//! often each came during it (`pair.finish`), and writes that back into the card's `okMx` as its own section; the host
//! hands the section over on `pair.enter` / `pair.exit` and writes the reply (`hooks::save`) into the card file.
//! The street's fitting room (`fitting`) and one-on-ones left before they were ready (`cancelled`) are not counted.
//!
//! Card data (version 1): `{"times", "seconds", "her", "him", "last"}` (`last`: Unix seconds of the last one).
//! The reader shows it (C, OK mod wave 3): `reader.character_load` reads the section of the card the reader opened, and
//! a "1 對 1 統計" page lists it (`reader.ui` / `reader.values`, read only). The mod does not take `reader.character_save`,
//! so a card saved in the reader keeps its section byte for byte (Docs/OK_MOD_HOOKS.md §3).

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
    /// The reader: the card it shows and what that card holds (None: no card, or a card without this mod's data).
    shown: Option<Stats>,
    shown_card: bool,
}

/// `YYYY-MM-DD` (UTC) of Unix seconds.
pub fn date_of(secs: u64) -> String {
    // Days to civil date (Howard Hinnant's algorithm).
    let z = (secs / 86_400) as i64 + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

/// The reader page's lines for what a card holds.
pub fn reader_values(card: bool, s: Option<&Stats>) -> serde_json::Value {
    let Some(s) = s.filter(|s| s.times > 0) else {
        let none = if card { "這張卡還沒有 1 對 1 的紀錄。" } else { "還沒有開卡。" };
        return serde_json::json!({"summary": none, "times": "", "time": "", "finishes": "", "last": ""});
    };
    let minutes = s.seconds / 60.0;
    serde_json::json!({
        "summary": "",
        "times": format!("{} 次", s.times),
        "time": format!("共 {minutes:.1} 分鐘，平均每次 {:.1} 分鐘", minutes / s.times as f64),
        "finishes": format!("她 {} 次，他 {} 次", s.her, s.him),
        "last": if s.last > 0 { format!("{}（UTC）", date_of(s.last)) } else { String::new() },
    })
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
        Ok(Counter { host, card: String::new(), her: 0, him: 0, shown: None, shown_card: false })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.subscribe("pair.enter").subscribe("pair.finish").subscribe("pair.exit");
        // The reader: read only (no reader.character_save, so a save keeps the card's section as it is).
        reg.subscribe("reader.character_load").subscribe("reader.character_unload").subscribe("reader.ui").subscribe("reader.values");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        match name.as_str() {
            "reader.character_load" => {
                let load: hooks::CharacterLoad = hooks::parse(payload)?;
                self.shown_card = true;
                // Shown whatever "apply on load" says: the page only reads it, nothing is applied to her.
                self.shown = match &load.section {
                    Some(s) => s.data(VERSION, |_old, v| Ok(v)).map_err(|e| self.host.log(LogLevel::Warn, format!("{}: {e}", load.card))).ok(),
                    None => None,
                };
                return Ok(Reply::None);
            }
            "reader.character_unload" => {
                self.shown = None;
                self.shown_card = false;
                return Ok(Reply::None);
            }
            "reader.ui" => {
                let line = |key: &str, label: &str| serde_json::json!({"kind": "label", "key": key, "text": format!("{label}：")});
                return hooks::json(&serde_json::json!({"pages": [{
                    "name": "1 對 1 統計",
                    "items": [
                        {"kind": "label", "text": "1 對 1 統計", "style": "Title"},
                        {"kind": "label", "key": "summary", "style": "Caption"},
                        line("times", "次數"), line("time", "時間"), line("finishes", "高潮"), line("last", "最後一次"),
                        {"kind": "label", "text": "在 1 對 1 結束時由這個 mod 記在她的卡片裡；這一頁只顯示，不會改卡片。", "style": "Caption"},
                    ],
                }]}));
            }
            "reader.values" => return hooks::json(&reader_values(self.shown_card, self.shown.as_ref())),
            _ => {}
        }
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
                // The street opens the one-on-one before her card is known (pair.enter with no card): the first
                // event that has it tells whose one-on-one this is.
                if self.card.is_empty() {
                    self.card = e.card;
                }
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
    fn the_reader_page_reads_the_card() {
        assert_eq!(date_of(0), "1970-01-01");
        assert_eq!(date_of(1_795_379_922), "2026-11-22");
        let v = reader_values(true, Some(&Stats { times: 2, seconds: 300.0, her: 3, him: 1, last: 1_795_379_922 }));
        assert_eq!(v["times"], "2 次");
        assert_eq!(v["time"], "共 5.0 分鐘，平均每次 2.5 分鐘");
        assert_eq!(v["finishes"], "她 3 次，他 1 次");
        assert_eq!(v["last"], "2026-11-22（UTC）");
        assert_eq!(reader_values(true, None)["summary"], "這張卡還沒有 1 對 1 的紀錄。");
        assert_eq!(reader_values(false, None)["summary"], "還沒有開卡。");
    }

    #[test]
    fn stats_round_trip_through_a_section() {
        let s = Stats { times: 2, seconds: 30.5, her: 1, him: 3, last: 9 };
        let section: hooks::ExtSection = serde_json::from_value(hooks::section(VERSION, &s).unwrap()).unwrap();
        assert_eq!(section.data::<Stats>(VERSION, |_, v| Ok(v)).unwrap(), s);
    }
}
