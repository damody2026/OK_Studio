//! `idle-breath`: posed characters in OK Studio breathe (Docs/OK_MOD_FRAMEWORK_PLAN.md §14.2; KKABMX / KKPE-like
//! per-frame bone post-processing). The chest rises and falls, the shoulders follow a little.
//!
//! - **Per frame** (`ok_mod_frame!`, feature `frame`): after the pose, the spine and shoulder bones get a small rotation
//!   on a sine. It runs on the game's worker threads for several characters at once, so it reads only `static`
//!   settings (a lock held just to copy one character's numbers).
//! - **Per character**: the strength is scene data under the object's id (`chars.<id>.strength`, a 狀態 row and a
//!   per-object timeline value), so copies, deletes, imports, undo and save carry it like any scene data. The studio
//!   says which object a frame belongs to (`Object::frame`); the mod refreshes that map on every call it gets and on a
//!   half-second timer (a rebuilt character gets a new frame id).
//!
//! Scene data (version 1): `{"enabled": bool, "speed": breaths per minute, "chars": {"<object id>": {"strength": 0..3}}}`.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Instant;

use ok_mod_sdk::frame::Frame;
use ok_mod_sdk::prelude::*;
use ok_mod_studio::{json, Call, Effect, Map, Ui, Value};

const P: &str = "mod.org.openkoikatsu.idle-breath";
const VERSION: u64 = 1;
const DEFAULT_SPEED: f64 = 16.0;
const DEFAULT_STRENGTH: f64 = 1.0;

/// What the frame function reads: copied from the scene data whenever the mod is called.
struct Settings {
    enabled: bool,
    /// Breaths per second.
    rate: f32,
    /// Strength by frame id (`Frame::character`); a character not listed breathes at `DEFAULT_STRENGTH`.
    strength: HashMap<u64, f32>,
}

static SETTINGS: Mutex<Option<Settings>> = Mutex::new(None);
static START: Mutex<Option<Instant>> = Mutex::new(None);

/// The bones a breath moves: name, axis (local), degrees at full strength.
const BONES: [(&str, usize, f32); 4] = [
    ("cf_j_spine02", 0, 1.4),
    ("cf_j_spine03", 0, 0.9),
    ("cf_j_shoulder_L", 2, 0.8),
    ("cf_j_shoulder_R", 2, -0.8),
];

/// `rot * q(axis, degrees)`, Unity quaternions `[x, y, z, w]`.
fn turn(rot: [f32; 4], axis: usize, degrees: f32) -> [f32; 4] {
    let half = degrees.to_radians() * 0.5;
    let mut q = [0.0f32, 0.0, 0.0, half.cos()];
    q[axis] = half.sin();
    let [ax, ay, az, aw] = rot;
    let [bx, by, bz, bw] = q;
    [
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ]
}

/// How far into a breath (-1..1) at `seconds`: a slow in-breath, a quicker out-breath, each character a little off the
/// others (its id picks a phase) so a crowd does not breathe in step.
fn breath(seconds: f32, rate: f32, character: u64) -> f32 {
    let offset = (character.wrapping_mul(0x9E37_79B9_7F4A_7C15) >> 40) as f32 / (1u64 << 24) as f32;
    let phase = (seconds * rate + offset).fract();
    let s = (phase * std::f32::consts::TAU).sin();
    if s > 0.0 { s } else { s * 0.8 }
}

fn frame(f: &mut Frame) -> bool {
    let (rate, strength) = {
        let Ok(guard) = SETTINGS.lock() else { return false };
        let Some(s) = guard.as_ref() else { return false };
        if !s.enabled {
            return false;
        }
        (s.rate, s.strength.get(&f.character()).copied().unwrap_or(DEFAULT_STRENGTH as f32))
    };
    if strength <= 0.0 || f.kind() != 0 {
        return false; // nothing to do, or a 1-on-1 pair frame (the pair's own motion breathes)
    }
    let seconds = START.lock().ok().and_then(|g| g.map(|t| t.elapsed().as_secs_f32())).unwrap_or(0.0);
    let b = breath(seconds, rate, f.character()) * strength;
    let mut changed = false;
    for (name, axis, degrees) in BONES {
        if let Some(i) = f.find(name) {
            let bones = f.bones_mut();
            bones[i].rot = turn(bones[i].rot, axis, degrees * b);
            changed = true;
        }
    }
    changed
}

ok_mod_sdk::ok_mod_frame!(frame);

/// The scene data with its defaults filled in.
fn completed(data: &Value) -> Value {
    let mut out = json!({"enabled": true, "speed": DEFAULT_SPEED, "chars": {}});
    if let (Some(o), Some(d)) = (out.as_object_mut(), data.as_object()) {
        for (k, v) in d {
            o.insert(k.clone(), v.clone());
        }
    }
    out
}

/// The frame function's settings from a call's scene data and objects.
fn settings_of(data: &Value, objects: &[ok_mod_studio::Object]) -> Settings {
    let data = completed(data);
    let chars = data.get("chars").and_then(Value::as_object).cloned().unwrap_or_default();
    let mut strength = HashMap::new();
    for o in objects {
        let Some(frame) = o.frame else { continue };
        let s = chars.get(&o.id.to_string()).and_then(|c| c.get("strength")).and_then(Value::as_f64).unwrap_or(DEFAULT_STRENGTH);
        strength.insert(frame, s.clamp(0.0, 3.0) as f32);
    }
    Settings {
        enabled: data.get("enabled").and_then(Value::as_bool).unwrap_or(true),
        rate: (data.get("speed").and_then(Value::as_f64).unwrap_or(DEFAULT_SPEED).clamp(4.0, 40.0) / 60.0) as f32,
        strength,
    }
}

/// Per-object entries moved with their objects (copied, deleted, imported).
fn remap(data: &Value, call: &Call) -> Option<Value> {
    let mut d = completed(data);
    let chars = d.get_mut("chars")?.as_object_mut()?;
    let before: Map<String, Value> = chars.clone();
    match call.event() {
        "objects_copied" => {
            for (old, new) in call.id_map() {
                if let Some(v) = before.get(&old.to_string()) {
                    chars.insert(new.to_string(), v.clone());
                }
            }
        }
        "objects_deleted" => {
            for id in call.ids() {
                chars.remove(&id.to_string());
            }
        }
        "scene_load" if call.load_kind() == "import" => {
            let imported = completed(call.imported_data());
            let theirs = imported.get("chars").and_then(Value::as_object).cloned().unwrap_or_default();
            let map = call.id_map();
            for (old, v) in theirs {
                let Ok(old) = old.parse::<i64>() else { continue };
                if let Some((_, new)) = map.iter().find(|(o, _)| *o == old) {
                    chars.insert(new.to_string(), v);
                }
            }
        }
        _ => return None,
    }
    (*chars != before).then_some(d)
}

struct Breath;

impl Breath {
    fn ui(&self) -> Reply {
        Ui::new()
            .command("reset", &format!("{P}.cmd.reset"))
            .control(json!({"id": "enabled", "label": format!("{P}.row.enabled"), "panel": "scene", "kind": "toggle", "bind": "enabled"}))
            .control(json!({"id": "speed", "label": format!("{P}.row.speed"), "panel": "scene", "kind": "slider", "min": 4, "max": 40, "step": 1, "bind": "speed"}))
            .control(json!({"id": "strength", "label": format!("{P}.row.strength"), "panel": "state", "kind": "slider", "min": 0, "max": 3, "step": 0.1, "bind": "chars.{object}.strength"}))
            .interpolable("strength", &format!("{P}.row.strength"), "chars.{object}.strength", true)
            .timer("sync", 500)
            .objects(true)
            .into_reply()
    }
}

impl Mod for Breath {
    fn create(_host: Host) -> ModResult<Self> {
        if let Ok(mut s) = START.lock() {
            s.get_or_insert_with(Instant::now);
        }
        Ok(Breath)
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        ok_mod_studio::subscribe(reg, &["scene_load", "objects_copied", "objects_deleted", "objects_selected", "control"], &[], &["sync"]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        // Every call carries the scene data and the objects: the frame function follows them.
        if let Ok(mut s) = SETTINGS.lock() {
            *s = Some(settings_of(call.data(), &call.objects()));
        }
        Ok(match call.command() {
            _ if call.is_ui() => self.ui(),
            Some("reset") => {
                let mut d = completed(call.data());
                d["enabled"] = true.into();
                d["speed"] = DEFAULT_SPEED.into();
                d["chars"] = json!({});
                Effect::new().data(d, VERSION).status("呼吸：回到預設").into_reply()
            }
            Some(other) => return Err(format!("unknown command {other}")),
            None => match remap(call.data(), &call) {
                Some(d) => Effect::new().data(d, VERSION).into_reply(),
                None => Effect::new().into_reply(),
            },
        })
    }
}

ok_mod!(Breath);

#[cfg(test)]
mod tests {
    use super::*;

    fn obj(id: i64, frame: Option<u64>) -> ok_mod_studio::Object {
        ok_mod_studio::Object { id, kind: "character".into(), name: String::new(), parent: -1, visible: true, frame }
    }

    #[test]
    fn strength_follows_the_object_to_its_frame() {
        let data = json!({"speed": 30, "chars": {"7": {"strength": 2.5}}});
        let s = settings_of(&data, &[obj(7, Some(1000)), obj(8, Some(2000)), obj(9, None)]);
        assert_eq!(s.strength[&1000], 2.5);
        assert_eq!(s.strength[&2000], DEFAULT_STRENGTH as f32);
        assert_eq!(s.strength.len(), 2);
        assert!((s.rate - 0.5).abs() < 1e-6);
        assert!(s.enabled);
    }

    #[test]
    fn a_turn_keeps_the_quaternion_unit() {
        let q = turn([0.0, 0.0, 0.0, 1.0], 0, 90.0);
        let n: f32 = q.iter().map(|v| v * v).sum();
        assert!((n - 1.0).abs() < 1e-5);
        assert!((q[0] - (45f32).to_radians().sin()).abs() < 1e-5);
    }

    #[test]
    fn breaths_stay_in_range_and_differ_between_characters() {
        for i in 0..100 {
            let b = breath(i as f32 * 0.37, 0.25, 42);
            assert!((-0.8..=1.0).contains(&b));
        }
        assert_ne!(breath(1.0, 0.25, 1), breath(1.0, 0.25, 2));
    }
}
