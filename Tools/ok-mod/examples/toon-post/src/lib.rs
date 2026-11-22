//! `toon-post`: a comic look for OK Studio (Docs/OK_MOD_FRAMEWORK_PLAN.md §14.2; what StudioSceneSettings and TwoLut-like
//! plugins add to the original). Outlines along depth edges and halftone dots in the shadows, over the whole view.
//!
//! - The look is the mod's own post-process material (`materials/toon.toml`: B layer `M_OKToonPost`, cooked by
//!   Tools/modkit_cook.lua from Plugins/org_openkoikatsu_toon_post into `content/`).
//! - Its settings are scene data (saved in the `.okscene`'s `mods`), edited by rows on the 畫面設定 page; line width,
//!   line strength, dot size and dot strength are timeline interpolables. The studio reads the data every frame
//!   (`post_process` in the panel reply), so nothing here runs per frame and undo / redo cover the settings.
//!
//! Scene data (version 1): `{"enabled": bool, "line_width", "line_strength", "dot_size", "dot_strength": numbers,
//! "line_color": "#RRGGBB"}`.

use ok_mod_sdk::prelude::*;
use ok_mod_studio::{json, Call, Effect, Ui, Value};

const ID: &str = "org.openkoikatsu.toon-post";
const P: &str = "mod.org.openkoikatsu.toon-post";
const VERSION: u64 = 1;

/// The settings a scene starts with when the look is turned on.
pub fn defaults() -> Value {
    json!({"enabled": true, "line_width": 1.5, "line_strength": 1.0, "dot_size": 6.0, "dot_strength": 0.5, "line_color": "#08080C"})
}

/// The data with every missing setting filled in (turning the look on in a scene that never had it).
pub fn completed(data: &Value) -> Value {
    let mut out = defaults();
    if let (Some(o), Some(d)) = (out.as_object_mut(), data.as_object()) {
        for (k, v) in d {
            o.insert(k.clone(), v.clone());
        }
    }
    out
}

struct Toon;

impl Toon {
    fn ui(&self) -> Reply {
        let slider = |id: &str, min: f64, max: f64, step: f64| {
            json!({"id": id, "label": format!("{P}.row.{id}"), "panel": "scene", "kind": "slider", "min": min, "max": max, "step": step, "bind": id})
        };
        Ui::new()
            .command("reset", &format!("{P}.cmd.reset"))
            .control(json!({"id": "enabled", "label": format!("{P}.row.enabled"), "panel": "scene", "kind": "toggle", "bind": "enabled"}))
            .control(slider("line_width", 0.5, 4.0, 0.1))
            .control(slider("line_strength", 0.0, 1.0, 0.05))
            .control(slider("dot_size", 2.0, 20.0, 0.5))
            .control(slider("dot_strength", 0.0, 1.0, 0.05))
            .control(json!({"id": "line_color", "label": format!("{P}.row.line_color"), "panel": "scene", "kind": "color", "bind": "line_color"}))
            .interpolable("line_width", &format!("{P}.row.line_width"), "line_width", false)
            .interpolable("line_strength", &format!("{P}.row.line_strength"), "line_strength", false)
            .interpolable("dot_size", &format!("{P}.row.dot_size"), "dot_size", false)
            .interpolable("dot_strength", &format!("{P}.row.dot_strength"), "dot_strength", false)
            .post_process(
                &format!("{ID}/toon"),
                "enabled",
                &[("LineWidth", "line_width"), ("LineStrength", "line_strength"), ("DotSize", "dot_size"), ("DotStrength", "dot_strength")],
                &[("LineColor", "line_color")],
            )
            .into_reply()
    }
}

impl Mod for Toon {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(Toon)
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        ok_mod_studio::subscribe(reg, &["control"], &[], &[]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        Ok(match call.command() {
            _ if call.is_ui() => self.ui(),
            Some("reset") => Effect::new().data(defaults(), VERSION).status("漫畫風：設定回到預設").into_reply(),
            Some(other) => return Err(format!("unknown command {other}")),
            // A row changed: the first time the look is turned on, the other settings get their defaults (in the same
            // undo step as the toggle).
            None if call.event() == "control" => {
                let data = call.data();
                if data.as_object().is_some_and(|o| o.len() < defaults().as_object().map_or(0, |d| d.len())) {
                    Effect::new().data(completed(data), VERSION).into_reply()
                } else {
                    Effect::new().into_reply()
                }
            }
            None => Effect::new().into_reply(),
        })
    }
}

ok_mod!(Toon);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn turning_on_fills_the_rest() {
        let d = completed(&json!({"enabled": true, "dot_size": 9.0}));
        assert_eq!(d["dot_size"], 9.0, "a set value stays");
        assert_eq!(d["line_width"], 1.5, "a missing one gets its default");
        assert_eq!(d["line_color"], "#08080C");
    }
}
