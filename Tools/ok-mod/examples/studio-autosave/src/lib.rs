//! `studio-autosave` (Autosave; Docs/OK_MOD_FRAMEWORK_PLAN.md §14.2): every few minutes, while the scene has unsaved
//! changes, a copy of it as `.okscene` in the mod's backup folder (Saved/OKStudio/ModExports/<mod id>), the newest few
//! kept. A tool button saves one now. The studio's own backup (Saved/OKStudio/Backup) is separate: this one is named,
//! kept as long as the player wants and shows how a mod uses a timer instead of polling every frame.

use std::time::{SystemTime, UNIX_EPOCH};

use ok_mod_sdk::prelude::*;
use ok_mod_studio::{Call, Effect, Ui};

const ID: &str = "org.openkoikatsu.studio_autosave";
const P: &str = "mod.org.openkoikatsu.studio_autosave";

struct Autosave {
    host: Host,
    /// Minutes since the last copy (the timer ticks once a minute).
    minutes: i64,
}

fn stamp() -> String {
    let secs = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    // UTC date and time from the Unix time (civil-from-days, Howard Hinnant), so names sort by time.
    let days = (secs / 86400) as i64;
    let (h, m, s) = ((secs / 3600) % 24, (secs / 60) % 60, secs % 60);
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(mo <= 2);
    format!("{y:04}{mo:02}{d:02}-{h:02}{m:02}{s:02}")
}

impl Autosave {
    fn keep(&self) -> u32 {
        self.host.config_int("keep").unwrap_or(5).clamp(1, 50) as u32
    }
    fn every(&self) -> i64 {
        self.host.config_int("minutes").unwrap_or(5).max(1)
    }
    fn save(&mut self, why: &str) -> Reply {
        self.minutes = 0;
        let name = format!("autosave-{}", stamp());
        self.host.info(format!("{why}: {name}"));
        Effect::new().export(&name, self.keep()).status(format!("已自動備份 {name}（保留最新 {} 份）", self.keep())).into_reply()
    }

    fn ui(&self) -> Reply {
        Ui::new()
            .command("save_now", &format!("{P}.cmd.save_now"))
            .toolbar("save_now", "備", &format!("{P}.tool.save_now"), &format!("mod.{ID}.save_now"), "")
            .timer("minute", 60_000)
            .into_reply()
    }
}

impl Mod for Autosave {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Autosave { host, minutes: 0 })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_bool("enabled", true, &format!("{P}.config.enabled"))
            .config_int("minutes", 5, 1, 120, &format!("{P}.config.minutes"))
            .config_int("keep", 5, 1, 50, &format!("{P}.config.keep"));
        ok_mod_studio::subscribe(reg, &[], &[], &["minute"]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        Ok(match call.command() {
            _ if call.is_ui() => self.ui(),
            Some("save_now") => self.save("saved on request"),
            Some(other) => return Err(format!("unknown command {other}")),
            None if call.event() == "timer" => {
                self.minutes += 1;
                let dirty = call.get("dirty").and_then(|v| v.as_bool()).unwrap_or(false);
                if self.host.config_bool("enabled").unwrap_or(true) && dirty && self.minutes >= self.every() {
                    self.save("autosave")
                } else {
                    Effect::new().into_reply()
                }
            }
            None => Effect::new().into_reply(),
        })
    }
}

ok_mod!(Autosave);

#[cfg(test)]
mod tests {
    #[test]
    fn stamp_looks_like_a_date() {
        let s = super::stamp();
        assert_eq!(s.len(), 15);
        assert!(s.starts_with("20"));
    }
}
