//! `object-hotkeys` (StudioObjectMoveHotkeys; Docs/OK_MOD_FRAMEWORK_PLAN.md §14.2): hold a key and move the mouse to
//! move (V), turn (B) or scale (N) the selected objects in OK Studio. Shift while moving: along the view instead of up.
//! Keeps no data: a pure QoL mod. The whole drag is one undo step (the studio joins edits made in a row).

use ok_mod_sdk::prelude::*;
use ok_mod_studio::{Call, Effect, Ui};

const P: &str = "mod.org.openkoikatsu.object_hotkeys";

struct Hotkeys {
    host: Host,
}

impl Hotkeys {
    fn chord(&self, key: &str, default: &str) -> String {
        self.host.config_text(key).filter(|k| !k.is_empty()).unwrap_or_else(|| default.into())
    }
    fn speed(&self) -> f64 {
        self.host.config_float("speed").unwrap_or(0.5)
    }

    fn ui(&self) -> Reply {
        Ui::new()
            .key("move", &self.chord("hotkey_move", "V"), true)
            .key("rotate", &self.chord("hotkey_rotate", "B"), true)
            .key("scale", &self.chord("hotkey_scale", "N"), true)
            .into_reply()
    }

    fn event(&self, call: &Call) -> Reply {
        match call.event() {
            "drag" => {
                let (dx, dy) = call.delta();
                let s = self.speed();
                let effect = match call.id() {
                    // Right and up as seen; with Shift the mouse's up and down moves along the view.
                    "move" if call.shift() => Effect::new().nudge_view(dx * s, 0.0, -dy * s),
                    "move" => Effect::new().nudge_view(dx * s, -dy * s, 0.0),
                    "rotate" => Effect::new().nudge_rotate(-dy * s, dx * s, 0.0),
                    "scale" => Effect::new().nudge_scale((1.0 + dx * 0.004 * s).clamp(0.5, 2.0)),
                    _ => Effect::new(),
                };
                effect.into_reply()
            }
            "key" if call.down() => {
                let what = match call.id() {
                    "move" => "移動",
                    "rotate" => "旋轉",
                    "scale" => "縮放",
                    _ => return Effect::new().into_reply(),
                };
                if call.selection().is_empty() {
                    Effect::new().status("先選取物件").into_reply()
                } else {
                    Effect::new().status(format!("{what}：移動滑鼠（放開鍵結束）")).into_reply()
                }
            }
            _ => Effect::new().into_reply(),
        }
    }
}

impl Mod for Hotkeys {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Hotkeys { host })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_hotkey("hotkey_move", "V", &format!("{P}.config.hotkey_move"))
            .config_hotkey("hotkey_rotate", "B", &format!("{P}.config.hotkey_rotate"))
            .config_hotkey("hotkey_scale", "N", &format!("{P}.config.hotkey_scale"))
            .config_float("speed", 0.5, 0.05, 5.0, &format!("{P}.config.speed"));
        ok_mod_studio::subscribe(reg, &[], &["move", "rotate", "scale"], &[]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        Ok(if call.is_ui() { self.ui() } else { self.event(&call) })
    }
}

ok_mod!(Hotkeys);
