//! `scene-notes` (KKAPI StudioContextMenus / ToolbarManager; Docs/OK_MOD_FRAMEWORK_PLAN.md §14.2): notes on objects.
//! Right-click an object → 加備註; a character's note is edited on its 狀態 page; the tool button steps through the
//! noted objects, selecting each and showing its note. Notes follow their objects: a copied object gets a copy, a
//! deleted one loses its note, an imported scene's notes come in under the new ids.
//!
//! Scene data (version 1): `{"notes": {"<object id>": "text"}}`.

use ok_mod_sdk::prelude::*;
use ok_mod_studio::{json, Call, Effect, Map, Ui, Value};

const ID: &str = "org.openkoikatsu.scene_notes";
const P: &str = "mod.org.openkoikatsu.scene_notes";
const VERSION: u64 = 1;

struct Notes {
    /// The note the tool button showed last (its object id); only for stepping, not scene state.
    last: i64,
}

fn notes(data: &Value) -> Map<String, Value> {
    data.get("notes").and_then(Value::as_object).cloned().unwrap_or_default()
}

fn with_notes(notes: Map<String, Value>) -> Effect {
    if notes.is_empty() {
        Effect::new().clear_data()
    } else {
        Effect::new().data(json!({ "notes": notes }), VERSION)
    }
}

impl Notes {
    fn ui(&self) -> Reply {
        Ui::new()
            .command("add", &format!("{P}.cmd.add"))
            .command("remove", &format!("{P}.cmd.remove"))
            .command("next", &format!("{P}.cmd.next"))
            .menu("add", &format!("{P}.menu.add"), &format!("mod.{ID}.add"), "", &[])
            .menu("remove", &format!("{P}.menu.remove"), &format!("mod.{ID}.remove"), "", &[])
            .toolbar("next", "註", &format!("{P}.tool.next"), &format!("mod.{ID}.next"), "")
            .control(json!({"id": "note", "label": format!("{P}.row.note"), "panel": "state", "kind": "text", "bind": "notes.{object}"}))
            .objects(true)
            .into_reply()
    }

    fn name_of(call: &Call, id: i64) -> String {
        call.objects().into_iter().find(|o| o.id == id).map(|o| o.name).unwrap_or_else(|| format!("#{id}"))
    }

    fn add(&self, call: &Call) -> Reply {
        let Some(id) = call.primary() else { return Effect::new().status("先選取物件").into_reply() };
        let mut n = notes(call.data());
        let text = if call.arg().is_empty() { format!("{} 的備註", Self::name_of(call, id)) } else { call.arg().to_string() };
        n.insert(id.to_string(), Value::String(text.clone()));
        with_notes(n).status(format!("已加備註：{text}")).into_reply()
    }

    fn remove(&self, call: &Call) -> Reply {
        let mut n = notes(call.data());
        let gone: Vec<i64> = call.selection().into_iter().filter(|id| n.remove(&id.to_string()).is_some()).collect();
        if gone.is_empty() {
            return Effect::new().status("所選物件沒有備註").into_reply();
        }
        with_notes(n).status(format!("已刪 {} 則備註", gone.len())).into_reply()
    }

    fn next(&mut self, call: &Call) -> Reply {
        let n = notes(call.data());
        let mut ids: Vec<i64> = n.keys().filter_map(|k| k.parse().ok()).collect();
        ids.sort();
        if ids.is_empty() {
            return Effect::new().status("場景裡沒有備註（右鍵物件 → 加備註）").into_reply();
        }
        let id = ids.iter().copied().find(|i| *i > self.last).unwrap_or(ids[0]);
        self.last = id;
        let pos = ids.iter().position(|i| *i == id).unwrap_or(0) + 1;
        let text = n.get(&id.to_string()).and_then(Value::as_str).unwrap_or("");
        Effect::new().select(&[id]).status(format!("備註 {pos}／{}：{}：{text}", ids.len(), Self::name_of(call, id))).into_reply()
    }

    fn event(&self, call: &Call) -> Reply {
        let mut n = notes(call.data());
        match call.event() {
            "objects_copied" => {
                let mut changed = false;
                for (old, new) in call.id_map() {
                    if let Some(text) = n.get(&old.to_string()).cloned() {
                        n.insert(new.to_string(), text);
                        changed = true;
                    }
                }
                if changed { with_notes(n).into_reply() } else { Effect::new().into_reply() }
            }
            "objects_deleted" => {
                let before = n.len();
                for id in call.ids() {
                    n.remove(&id.to_string());
                }
                if n.len() != before { with_notes(n).into_reply() } else { Effect::new().into_reply() }
            }
            // An added scene's notes come in under the ids its objects got here.
            "scene_load" if call.load_kind() == "import" => {
                let map = call.id_map();
                let imported = notes(call.imported_data());
                let mut changed = false;
                for (old, text) in imported {
                    let Ok(old) = old.parse::<i64>() else { continue };
                    if let Some((_, new)) = map.iter().find(|(o, _)| *o == old) {
                        n.insert(new.to_string(), text);
                        changed = true;
                    }
                }
                if changed { with_notes(n).into_reply() } else { Effect::new().into_reply() }
            }
            _ => Effect::new().into_reply(),
        }
    }
}

impl Mod for Notes {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(Notes { last: -1 })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        ok_mod_studio::subscribe(reg, &["objects_copied", "objects_deleted", "scene_load"], &[], &[]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        Ok(match call.command() {
            _ if call.is_ui() => self.ui(),
            Some("add") => self.add(&call),
            Some("remove") => self.remove(&call),
            Some("next") => self.next(&call),
            Some(other) => return Err(format!("unknown command {other}")),
            None => self.event(&call),
        })
    }
}

ok_mod!(Notes);
