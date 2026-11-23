//! Test fixture (Docs/OK_MOD_E_WAVE4.md §7): every `pair.*` payload's `her_gauge`, `his_gauge` and `inserted` go to the
//! log; the first event of a one-on-one that carries the gauges (the H scene is up) is answered with
//! `{"pair": {"her": 77, "his": 33}}`, which the host turns into `UOKHScenePanel::SetGauges`. The hotkey `bump` (F9)
//! answers `{"pair": {"her": 90, "his": 10}, "notice": …}` (OKModeHotkeys.cpp handles it in the one-on-one).

use ok_mod_sdk::prelude::*;
use serde_json::{json, Value};

struct Gauges {
    host: Host,
    set: bool,
}

impl Mod for Gauges {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Gauges { host, set: false })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        for h in ["pair.enter", "pair.ready", "pair.note", "pair.line", "pair.voice", "pair.finish", "pair.exit"] {
            reg.subscribe(h);
        }
        // F9: the gauges to 90 / 10 (Docs/OK_MOD_E_WAVE6.md: a hotkey's reply in the one-on-one).
        reg.hotkey("bump", "F9", "mod.org.openkoikatsu.test.pair_gauges.config.bump");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        let p: Value = serde_json::from_str(payload.as_str()).unwrap_or(Value::Null);
        if hooks::hotkey(name.as_str()) == Some("bump") {
            self.host.log(LogLevel::Info, format!("bump in {}: gauges to 90 / 10", p.get("mode").and_then(Value::as_str).unwrap_or("?")));
            return Ok(Reply::Json(json!({"pair": {"her": 90, "his": 10}, "notice": "量表 90／10"}).to_string().into()));
        }
        if name.as_str() == "pair.enter" || name.as_str() == "pair.exit" {
            self.set = false;
        }
        let Some(her) = p.get("her_gauge").and_then(Value::as_f64) else {
            self.host.log(LogLevel::Info, format!("{name}: no gauges (card {})", p.get("card").and_then(Value::as_str).unwrap_or("")));
            return Ok(Reply::None);
        };
        let his = p.get("his_gauge").and_then(Value::as_f64).unwrap_or(-1.0);
        let inserted = p.get("inserted").and_then(Value::as_bool).unwrap_or(false);
        self.host.log(LogLevel::Info, format!("{name}: her {her:.1} his {his:.1} inserted {inserted}"));
        if self.set || name.as_str() == "pair.exit" {
            return Ok(Reply::None);
        }
        self.set = true;
        self.host.log(LogLevel::Info, "setting the gauges to 77 / 33");
        Ok(Reply::Json(json!({"pair": {"her": 77, "his": 33}}).to_string().into()))
    }
}

ok_mod!(Gauges);
