//! `light-rig` (OK mod wave 4, Docs/OK_MOD_E_WAVE4.md): a Studio mod that edits the scene itself instead of only its own
//! data (KKAPI: a plugin moving and adding objects through Studio's own classes). Everything goes through the studio's
//! ops (`Effect::op`), so each command is one undo step with what it did to the objects and to the mod's data:
//!
//! - the tool button (light icon, pressed while the light is there) adds a point light over the selected object and
//!   remembers it; pressed again it deletes the light (`spawn`, then the new id from `studio.ops_result`; `delete`);
//! - 補光移到這裡 moves the light over the selection; with nothing selected over the object it was aimed at last, read
//!   with an `inspect` op (`transform`);
//! - the eye button shows only the selection (hides the other top-level objects, `patch` `bVisible`), again shows them;
//! - numbered names (`rename`), a smile and the top half off for the selected characters (`expression`, `clothes`);
//! - FK, IK and a studio animation for the selected character (`fk`, `ik`, `anim`; the argument names the bone, the
//!   effector or the animation key);
//! - the light's height is a row of the Mod page (系統 → Mod), in the mod's data;
//! - a character's new card, outfit, clothes or animation shows in the status line (`studio.character_changed`).
//!
//! Scene data (version 1): `{"rig": <light id>, "target": <object id>, "height": <cm>, "solo": [<hidden ids>]}`.

use ok_mod_sdk::prelude::*;
use ok_mod_studio::{json, op, Call, Effect, Map, Ui, Value};

const ID: &str = "org.openkoikatsu.light_rig";
const P: &str = "mod.org.openkoikatsu.light_rig";
const VERSION: u64 = 1;
const HEIGHT: f64 = 150.0;

struct Rig;

fn data(call: &Call) -> Map<String, Value> {
    call.data().as_object().cloned().unwrap_or_default()
}

fn save(d: Map<String, Value>) -> Effect {
    if d.is_empty() { Effect::new().clear_data() } else { Effect::new().data(Value::Object(d), VERSION) }
}

fn height(d: &Map<String, Value>) -> f64 {
    d.get("height").and_then(Value::as_f64).unwrap_or(HEIGHT)
}

/// The location of an object as the studio's inspect gives it (`transform.translation`, relative to its parent).
pub fn location(object: &Value) -> Option<[f64; 3]> {
    let t = object.get("transform")?.get("translation")?;
    Some([t.get("x")?.as_f64()?, t.get("y")?.as_f64()?, t.get("z")?.as_f64()?])
}

/// Top-level objects to hide so only the selection shows: roots that are not selected and hold nothing selected.
pub fn solo_hide(objects: &[ok_mod_studio::Object], selection: &[i64]) -> Vec<i64> {
    let parent = |id: i64| objects.iter().find(|o| o.id == id).map(|o| o.parent).unwrap_or(-1);
    let mut keep = std::collections::HashSet::new();
    for &s in selection {
        let mut at = s;
        while at >= 0 && keep.insert(at) {
            at = parent(at);
        }
    }
    objects.iter().filter(|o| o.parent < 0 && o.visible && !keep.contains(&o.id)).map(|o| o.id).collect()
}

impl Rig {
    fn ui(&self) -> Reply {
        Ui::new()
            .command("toggle", &format!("{P}.cmd.toggle"))
            .command("aim", &format!("{P}.cmd.aim"))
            .command("solo", &format!("{P}.cmd.solo"))
            .command("rename", &format!("{P}.cmd.rename"))
            .command("smile", &format!("{P}.cmd.smile"))
            .command("tilt", &format!("{P}.cmd.tilt"))
            .command("reach", &format!("{P}.cmd.reach"))
            .command("anim", &format!("{P}.cmd.anim"))
            .toolbar_icon("toggle", "light", &format!("{P}.tool.toggle"), &format!("mod.{ID}.toggle"), "", "rig")
            .toolbar_icon("solo", "eye", &format!("{P}.tool.solo"), &format!("mod.{ID}.solo"), "", "solo")
            .menu("aim", &format!("{P}.menu.aim"), &format!("mod.{ID}.aim"), "", &[])
            .menu("smile", &format!("{P}.menu.smile"), &format!("mod.{ID}.smile"), "", &["character"])
            .control(json!({"id": "height", "label": format!("{P}.row.height"), "panel": "mods", "kind": "slider", "min": 20, "max": 400, "step": 5, "bind": "height"}))
            .objects(true)
            .details(true)
            .into_reply()
    }

    fn toggle(&self, call: &Call) -> Reply {
        let mut d = data(call);
        if let Some(rig) = d.get("rig").and_then(Value::as_i64) {
            d.remove("rig");
            d.remove("target");
            return save(d).op(op::delete(&[rig])).status("補光已拿掉").into_reply();
        }
        let Some(target) = call.primary() else { return Effect::new().status("先選一個物件，補光會加在它上方").into_reply() };
        let Some([x, y, z]) = call.details(target).and_then(location) else { return Effect::new().status("讀不到所選物件的位置").into_reply() };
        let name = call.details(target).and_then(|o| o.get("name")).and_then(Value::as_str).unwrap_or("").to_string();
        Effect::new()
            .op(op::spawn("light", json!({"light_type": "point", "name": format!("補光 → {name}"), "location": [x, y, z + height(&d)]})))
            .tag(&format!("added:{target}"))
            .into_reply()
    }

    fn aim(&self, call: &Call) -> Reply {
        let d = data(call);
        let Some(rig) = d.get("rig").and_then(Value::as_i64) else { return Effect::new().status("還沒有補光（工具列的燈泡）").into_reply() };
        let target = call.primary().filter(|p| *p != rig).or_else(|| d.get("target").and_then(Value::as_i64));
        let Some(target) = target else { return Effect::new().status("先選一個物件").into_reply() };
        // Read where it is with a get op (studio.get): the answer comes back in studio.ops_result (works with nothing selected).
        Effect::new().op(op::get(Some(target))).tag(&format!("aim:{target}")).into_reply()
    }

    fn solo(&self, call: &Call) -> Reply {
        let mut d = data(call);
        if let Some(hidden) = d.remove("solo").and_then(|v| v.as_array().cloned()) {
            let mut e = save(d).status(format!("全部顯示（{} 個）", hidden.len()));
            for id in hidden.iter().filter_map(Value::as_i64) {
                e = e.op(op::show(id, true));
            }
            return e.into_reply();
        }
        let selection = call.selection();
        if selection.is_empty() {
            return Effect::new().status("先選要單獨顯示的物件").into_reply();
        }
        let hide = solo_hide(&call.objects(), &selection);
        if hide.is_empty() {
            return Effect::new().status("沒有別的物件可藏").into_reply();
        }
        d.insert("solo".into(), json!(hide));
        let mut e = save(d).status(format!("單獨顯示：藏起 {} 個物件", hide.len()));
        for id in &hide {
            e = e.op(op::show(*id, false));
        }
        e.into_reply()
    }

    fn rename(&self, call: &Call) -> Reply {
        let selection = call.selection();
        let objects = call.objects();
        let Some(first) = selection.first().and_then(|id| objects.iter().find(|o| o.id == *id)) else { return Effect::new().status("先選物件").into_reply() };
        // "名稱 3" → "名稱": the base without a number the mod gave before.
        let base = match first.name.rsplit_once(' ') {
            Some((b, n)) if n.chars().all(|c| c.is_ascii_digit()) => b.to_string(),
            _ => first.name.clone(),
        };
        let mut e = Effect::new().status(format!("{} 個物件改名為「{base} 1…」", selection.len()));
        for (i, id) in selection.iter().enumerate() {
            e = e.op(op::rename(*id, &format!("{base} {}", i + 1)));
        }
        e.into_reply()
    }

    fn smile(&self, call: &Call) -> Reply {
        let objects = call.objects();
        let chars: Vec<i64> = call.selection().into_iter().filter(|id| objects.iter().any(|o| o.id == *id && o.kind == "character")).collect();
        if chars.is_empty() {
            return Effect::new().status("先選角色").into_reply();
        }
        let mut e = Effect::new().status(format!("{} 個角色微笑", chars.len()));
        for id in chars {
            e = e.op(op::expression(id, Some(0), Some(1), Some(1), Some(0.3))).op(op::clothes(id, 0, 1));
        }
        e.into_reply()
    }

    /// The primary character (FK / IK / animation work on one).
    fn character(&self, call: &Call) -> Option<i64> {
        let objects = call.objects();
        call.primary().filter(|id| objects.iter().any(|o| o.id == *id && o.kind == "character"))
    }

    /// FK: the bone named by the argument (default the neck) tilted 20 degrees.
    fn tilt(&self, call: &Call) -> Reply {
        let Some(id) = self.character(call) else { return Effect::new().status("先選一個角色").into_reply() };
        let bone = if call.arg().is_empty() { "cf_j_neck" } else { call.arg() };
        Effect::new().op(op::fk(id, &[(bone, [0.0, 0.0, 20.0])])).tag("tilt").status(format!("#{id} 的 {bone} 轉 20°")).into_reply()
    }

    /// IK: the effector named by the argument (default 3) moved to (30, -20, 140) cm, full weight.
    fn reach(&self, call: &Call) -> Reply {
        let Some(id) = self.character(call) else { return Effect::new().status("先選一個角色").into_reply() };
        let effector: u8 = call.arg().parse().unwrap_or(3);
        Effect::new().op(op::ik(id, &[(effector, [30.0, -20.0, 140.0], 1.0)])).tag("reach").status(format!("#{id} 的 IK {effector} 移動")).into_reply()
    }

    /// A studio animation by its key (`kind/group/category/no`, the argument).
    fn anim(&self, call: &Call) -> Reply {
        let Some(id) = self.character(call) else { return Effect::new().status("先選一個角色").into_reply() };
        if call.arg().is_empty() {
            return Effect::new().status("要給動作的 kind/group/category/no").into_reply();
        }
        Effect::new().op(op::anim(id, call.arg())).tag("anim").into_reply()
    }

    /// What the ops answered: a new light's id to remember, a position to move the light to.
    fn results(&self, call: &Call) -> Reply {
        let results = call.results();
        let first = results.first().cloned().unwrap_or(Value::Null);
        let ok = first.get("ok").and_then(Value::as_bool).unwrap_or(false);
        let mut d = data(call);
        if let Some(target) = call.tag().strip_prefix("added:").and_then(|t| t.parse::<i64>().ok()) {
            let Some(rig) = first.get("id").and_then(Value::as_i64).filter(|_| ok) else {
                return Effect::new().status(format!("補光沒加上：{}", first.get("error").and_then(Value::as_str).unwrap_or("?"))).into_reply();
            };
            let h = height(&d);
            d.insert("rig".into(), rig.into());
            d.insert("target".into(), target.into());
            // The light stays selected as the spawn op left it; the status says where it went.
            return save(d).status(format!("補光 #{rig} 加在 #{target} 上方 {h:.0} cm")).into_reply();
        }
        if matches!(call.tag(), "tilt" | "reach" | "anim") {
            return Effect::new()
                .status(if ok { format!("{}：完成", call.tag()) } else { format!("{} 沒做成：{}", call.tag(), first.get("error").and_then(Value::as_str).unwrap_or("?")) })
                .into_reply();
        }
        if let Some(target) = call.tag().strip_prefix("aim:").and_then(|t| t.parse::<i64>().ok()) {
            let (Some(rig), Some([x, y, z])) = (d.get("rig").and_then(Value::as_i64), first.get("object").and_then(location)) else {
                return Effect::new().status("讀不到那個物件的位置").into_reply();
            };
            let h = height(&d);
            d.insert("target".into(), target.into());
            return save(d).op(op::transform(rig, Some([x, y, z + h]), None, None)).tag("aimed").status(format!("補光移到 #{target} 上方 {h:.0} cm")).into_reply();
        }
        Effect::new().into_reply()
    }

    fn event(&self, call: &Call) -> Reply {
        match call.event() {
            "ops_result" => self.results(call),
            // Someone deleted the light (or its target): forget it.
            "objects_deleted" => {
                let mut d = data(call);
                let gone = call.ids();
                let rig = d.get("rig").and_then(Value::as_i64);
                if rig.is_some_and(|r| gone.contains(&r)) {
                    d.remove("rig");
                    d.remove("target");
                    return save(d).into_reply();
                }
                if d.get("target").and_then(Value::as_i64).is_some_and(|t| gone.contains(&t)) {
                    d.remove("target");
                    return save(d).into_reply();
                }
                Effect::new().into_reply()
            }
            "character_changed" => {
                let what = call.changes().join("、");
                Effect::new().status(format!("角色 #{}：{what}", call.object().unwrap_or(-1))).into_reply()
            }
            _ => Effect::new().into_reply(),
        }
    }
}

impl Mod for Rig {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(Rig)
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        ok_mod_studio::subscribe(reg, &["objects_deleted", "ops_result", "character_changed"], &[], &[]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        Ok(match call.command() {
            _ if call.is_ui() => self.ui(),
            Some("toggle") => self.toggle(&call),
            Some("aim") => self.aim(&call),
            Some("solo") => self.solo(&call),
            Some("rename") => self.rename(&call),
            Some("smile") => self.smile(&call),
            Some("tilt") => self.tilt(&call),
            Some("reach") => self.reach(&call),
            Some("anim") => self.anim(&call),
            Some(other) => return Err(format!("unknown command {other}")),
            None => self.event(&call),
        })
    }
}

ok_mod!(Rig);

#[cfg(test)]
mod tests {
    use super::*;
    use ok_mod_studio::Object;

    fn obj(id: i64, parent: i64) -> Object {
        Object { id, kind: "item".into(), name: format!("o{id}"), parent, visible: true, frame: None }
    }

    #[test]
    fn solo_keeps_the_selection_and_its_parents() {
        let objects = vec![obj(1, -1), obj(2, 1), obj(3, -1), obj(4, -1)];
        assert_eq!(solo_hide(&objects, &[2]), vec![3, 4]);
        assert_eq!(solo_hide(&objects, &[3, 4]), vec![1]);
    }

    #[test]
    fn location_reads_the_inspected_transform() {
        let o = json!({"transform": {"translation": {"x": 1.0, "y": 2.0, "z": 3.0}}});
        assert_eq!(location(&o), Some([1.0, 2.0, 3.0]));
        assert_eq!(location(&json!({})), None);
    }
}
