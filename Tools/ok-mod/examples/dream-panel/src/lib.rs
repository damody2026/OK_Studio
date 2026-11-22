//! `dream-panel`: a mod's own DreamGUI panel on the card reader's mod page (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.13 D2).
//!
//! The panel is `Plugins/org_openkoikatsu_dream_panel/DUI/Panel.dui`, compiled and cooked by the ModKit
//! (`Tools/modkit_cook.lua --mod org_openkoikatsu_dream_panel`) into `content/*.pak`, shipped with its source as
//! `ui/Panel.dui`. The page places it with `{"kind": "dui", "widget": "Panel"}`.
//!
//! Code stays here, in Rust: the panel's buttons raise `ui.org.openkoikatsu.dream-panel.<event>` hooks (`Mod.Emit`), and
//! its text lines read this mod's values (`Mod.Text("greeting")` is `mod.org.openkoikatsu.dream-panel.greeting` from
//! `reader.values`). Nothing goes into the card.

use ok_mod_sdk::prelude::*;
use serde_json::{json, Value};

const UI: &str = "ui.org.openkoikatsu.dream-panel.";

#[derive(Default)]
struct DreamPanel {
    hellos: u32,
}

impl DreamPanel {
    fn values(&self) -> Value {
        let greeting = if self.hellos == 0 { "還沒打招呼".to_string() } else { format!("你好！（第 {} 次）", self.hellos) };
        json!({"greeting": greeting, "count_text": format!("按了 {} 次「打招呼」", self.hellos), "count": self.hellos})
    }

    /// A panel event: `hello` counts one, `reset` goes back to none.
    fn event(&mut self, name: &str) -> Result<Value, String> {
        match name {
            "hello" => {
                self.hellos += 1;
                Ok(json!({}))
            }
            "reset" => {
                self.hellos = 0;
                Ok(json!({"notice": "打招呼次數歸零"}))
            }
            other => Err(format!("unknown panel event {other}")),
        }
    }
}

fn page() -> Value {
    json!({"pages": [{
        "name": "DreamGUI 面板",
        "items": [
            {"kind": "label", "text": "下面是 mod 自帶的 .dui 面板：按鈕回到 mod 的 Rust 程式，文字綁定 mod 的值。", "style": "Caption"},
            {"kind": "dui", "widget": "Panel", "height": 170},
            {"kind": "label", "key": "count_text", "style": "AccentText"},
        ],
    }]})
}

impl Mod for DreamPanel {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(DreamPanel::default())
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        for hook in ["reader.ui", "reader.values"] {
            reg.subscribe(hook);
        }
        for event in ["hello", "reset"] {
            reg.subscribe(&format!("{UI}{event}"));
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Hook { name, .. } => match name.as_str() {
                "reader.ui" => hooks::json(&page()),
                "reader.values" => hooks::json(&self.values()),
                other => match other.strip_prefix(UI) {
                    Some(e) => hooks::json(&self.event(e)?),
                    None => Ok(Reply::None),
                },
            },
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(DreamPanel);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn panel_events_change_the_values() {
        let mut m = DreamPanel::default();
        assert_eq!(m.values()["count"], 0);
        m.event("hello").unwrap();
        m.event("hello").unwrap();
        assert_eq!(m.values()["count"], 2);
        assert!(m.values()["greeting"].as_str().unwrap().contains('2'));
        assert!(m.event("reset").unwrap()["notice"].is_string());
        assert_eq!(m.values()["count"], 0);
        assert!(m.event("explode").is_err());
    }

    #[test]
    fn the_page_places_the_panel() {
        let text = page().to_string();
        assert!(text.contains(r#""kind":"dui""#) && text.contains(r#""widget":"Panel""#));
    }
}
