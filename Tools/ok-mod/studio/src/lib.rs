//! `ok-mod-studio`: what an OK Studio mod uses on top of `ok-mod-sdk` (Docs/OK_MOD_S8_STUDIO_API.md).
//!
//! OK Studio talks to a mod through hooks (`Event::Hook`, JSON payload in, `Reply::Json` out), one mod at a time:
//!
//! - `studio.panel_ui`: asked when the studio opens. The mod answers what it adds: commands in the studio's command
//!   table, tool row buttons, context menu entries, rows of the 狀態 / 畫面設定 pages, timeline values, keys, timers.
//!   Build the answer with [`Ui`].
//! - `studio.command`: one of those commands was run (`name`, `arg`).
//! - scene events: `studio.scene_load`, `studio.scene_save`, `studio.objects_copied`, `studio.object_deleted`,
//!   `studio.objects_selected`, `studio.timeline_event`, `studio.panel_control`; and `key.<id>`, `timer.<id>` for the
//!   mod's keys and timers. The payload's `event` says which (`scene_load`, …, `objects_deleted`, `timeline_pass`,
//!   `control`, `key`, `drag`, `timer`).
//!
//! Subscribe with [`subscribe`] in `register`; read a call with [`Call::from_event`]. The answer is an [`Effect`]: new
//! scene data for the mod, a status line, a selection, studio commands to run, the playhead, a nudge of the selected
//! objects, a scene copy to write.
//!
//! The mod's data lives in the scene (`.okscene` "mods", one undo step with the change that made it): the context
//! carries it as `data`, the effect sets it. A mod keeps nothing about the scene anywhere else, so undo, redo, load and
//! save are right without the mod doing anything.

use ok_mod_sdk::{Event, Registrar, Reply};
pub use serde_json::{json, Map, Value};

/// Protocol version this crate speaks.
pub const PROTOCOL: u64 = 1;
/// The hook asking what the mod adds to the studio.
pub const PANEL_UI: &str = "studio.panel_ui";
/// The hook running one of the mod's studio commands.
pub const COMMAND: &str = "studio.command";

/// The hook a scene event comes through (`objects_deleted` → `studio.object_deleted`, …).
pub fn event_hook(event: &str) -> String {
    match event {
        "objects_deleted" => "studio.object_deleted".into(),
        "timeline_pass" => "studio.timeline_event".into(),
        "control" => "studio.panel_control".into(),
        other => format!("studio.{other}"),
    }
}

/// Subscribes to the studio's hooks: `studio.panel_ui`, `studio.command`, the scene `events` (names as in the payload's
/// `event`: `scene_load`, `scene_save`, `objects_copied`, `objects_deleted`, `objects_selected`, `timeline_pass`,
/// `control`), `key.<id>` for each key id and `timer.<id>` for each timer id the mod's [`Ui`] declares.
pub fn subscribe(reg: &mut Registrar, events: &[&str], keys: &[&str], timers: &[&str]) {
    reg.subscribe(PANEL_UI).subscribe(COMMAND);
    for e in events {
        reg.subscribe(&event_hook(e));
    }
    for k in keys {
        reg.subscribe(&format!("key.{k}"));
    }
    for t in timers {
        reg.subscribe(&format!("timer.{t}"));
    }
}

/// One object of the scene, when the mod asked for the list (`Ui::objects(true)`).
#[derive(Debug, Clone, PartialEq)]
pub struct Object {
    pub id: i64,
    pub kind: String,
    pub name: String,
    pub parent: i64,
    pub visible: bool,
}

/// The context of one call from the studio.
#[derive(Debug, Clone)]
pub struct Call {
    /// The hook it came through.
    pub hook: String,
    pub raw: Map<String, Value>,
}

impl Call {
    /// A studio hook's call (`studio.*`, `key.*`, `timer.*` with the studio's context); `None` for any other event.
    pub fn from_event(event: &Event) -> Option<Call> {
        let Event::Hook { name, payload } = event else { return None };
        let hook = name.as_str();
        if !(hook.starts_with("studio.") || hook.starts_with("key.") || hook.starts_with("timer.")) {
            return None;
        }
        Call::parse(hook, payload.as_str())
    }
    /// The studio's context (a JSON object with `"studio"`) of a call through `hook`.
    pub fn parse(hook: &str, payload: &str) -> Option<Call> {
        match serde_json::from_str::<Value>(payload) {
            Ok(Value::Object(raw)) if raw.contains_key("studio") => Some(Call { hook: hook.into(), raw }),
            _ => None,
        }
    }
    /// `studio.panel_ui`: answer with [`Ui`].
    pub fn is_ui(&self) -> bool {
        self.hook == PANEL_UI
    }
    /// `studio.command`: the command's name.
    pub fn command(&self) -> Option<&str> {
        if self.hook == COMMAND { self.raw.get("name").and_then(Value::as_str) } else { None }
    }
    pub fn get(&self, key: &str) -> Option<&Value> {
        self.raw.get(key)
    }
    /// The argument the button, menu entry or command gave.
    pub fn arg(&self) -> &str {
        self.raw.get("arg").and_then(Value::as_str).unwrap_or("")
    }
    /// Which event (`scene_load`, `key`, `drag`, `timer`, …; `command` for a command).
    pub fn event(&self) -> &str {
        self.raw.get("event").and_then(Value::as_str).unwrap_or("")
    }
    /// The mod's scene data (null when the scene has none).
    pub fn data(&self) -> &Value {
        self.raw.get("data").unwrap_or(&Value::Null)
    }
    pub fn data_version(&self) -> u64 {
        self.raw.get("data_version").and_then(Value::as_u64).unwrap_or(0)
    }
    pub fn selection(&self) -> Vec<i64> {
        ids(self.raw.get("selection"))
    }
    pub fn primary(&self) -> Option<i64> {
        self.raw.get("primary").and_then(Value::as_i64).filter(|i| *i >= 0)
    }
    /// Playhead, timeline length (seconds) and whether it plays.
    pub fn time(&self) -> f64 {
        self.raw.get("time").and_then(Value::as_f64).unwrap_or(0.0)
    }
    pub fn duration(&self) -> f64 {
        self.raw.get("duration").and_then(Value::as_f64).unwrap_or(0.0)
    }
    pub fn playing(&self) -> bool {
        self.raw.get("playing").and_then(Value::as_bool).unwrap_or(false)
    }
    pub fn scene_file(&self) -> &str {
        self.raw.get("scene_file").and_then(Value::as_str).unwrap_or("")
    }
    pub fn objects(&self) -> Vec<Object> {
        self.raw
            .get("objects")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|o| {
                        Some(Object {
                            id: o.get("id")?.as_i64()?,
                            kind: o.get("kind").and_then(Value::as_str).unwrap_or("").to_string(),
                            name: o.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
                            parent: o.get("parent").and_then(Value::as_i64).unwrap_or(-1),
                            visible: o.get("visible").and_then(Value::as_bool).unwrap_or(true),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default()
    }
    /// `objects_deleted`: the ids gone; `objects_selected`: the ids now selected.
    pub fn ids(&self) -> Vec<i64> {
        ids(self.raw.get("ids"))
    }
    /// `objects_copied`, `scene_load` (import): old id -> new id.
    pub fn id_map(&self) -> Vec<(i64, i64)> {
        self.raw
            .get("map")
            .and_then(Value::as_object)
            .map(|m| m.iter().filter_map(|(k, v)| Some((k.parse().ok()?, v.as_i64()?))).collect())
            .unwrap_or_default()
    }
    /// `scene_load`: `load`, `import` or `clear`.
    pub fn load_kind(&self) -> &str {
        self.raw.get("kind").and_then(Value::as_str).unwrap_or("")
    }
    /// `scene_load` import: this mod's data in the scene that was added.
    pub fn imported_data(&self) -> &Value {
        self.raw.get("imported_data").unwrap_or(&Value::Null)
    }
    /// `key` / `drag` / `timer` / `control`: the id the mod gave it.
    pub fn id(&self) -> &str {
        self.raw.get("id").and_then(Value::as_str).unwrap_or("")
    }
    /// `key`: pressed (true) or released.
    pub fn down(&self) -> bool {
        self.raw.get("down").and_then(Value::as_bool).unwrap_or(false)
    }
    /// `drag`: mouse movement in pixels since the last one (x right, y down).
    pub fn delta(&self) -> (f64, f64) {
        let f = |k| self.raw.get(k).and_then(Value::as_f64).unwrap_or(0.0);
        (f("dx"), f("dy"))
    }
    /// `drag` / `key`: modifier keys held.
    pub fn shift(&self) -> bool {
        self.raw.get("shift").and_then(Value::as_bool).unwrap_or(false)
    }
    /// `timeline_pass`: the marks the playhead went over (their index in the mod's mark list).
    pub fn marks(&self) -> Vec<usize> {
        self.raw
            .get("marks")
            .and_then(Value::as_array)
            .map(|a| a.iter().filter_map(|v| v.as_u64().map(|u| u as usize)).collect())
            .unwrap_or_default()
    }
}

fn ids(v: Option<&Value>) -> Vec<i64> {
    v.and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_i64).collect()).unwrap_or_default()
}

/// What a call from the studio does. Everything is optional; an empty effect does nothing.
#[derive(Debug, Clone, Default)]
pub struct Effect {
    map: Map<String, Value>,
}

impl Effect {
    pub fn new() -> Self {
        Self::default()
    }
    /// The mod's new scene data (any JSON value; an object for rows bound to it), with its format version.
    pub fn data(mut self, data: Value, version: u64) -> Self {
        self.map.insert("data".into(), data);
        self.map.insert("data_version".into(), version.into());
        self
    }
    /// Removes the mod's data from the scene.
    pub fn clear_data(mut self) -> Self {
        self.map.insert("clear_data".into(), true.into());
        self
    }
    pub fn status(mut self, text: impl Into<String>) -> Self {
        self.map.insert("status".into(), Value::String(text.into()));
        self
    }
    pub fn select(mut self, ids: &[i64]) -> Self {
        self.map.insert("select".into(), json!(ids));
        self
    }
    /// Runs a studio command (`studio_state` ui.commands lists them), after this answer.
    pub fn run(mut self, command: &str, arg: &str) -> Self {
        let list = self.map.entry("run").or_insert_with(|| Value::Array(Vec::new()));
        if let Value::Array(a) = list {
            a.push(json!({"command": command, "arg": arg}));
        }
        self
    }
    /// Moves the playhead and / or starts or stops playback.
    pub fn timeline(mut self, time: Option<f64>, playing: Option<bool>) -> Self {
        let mut t = Map::new();
        if let Some(time) = time {
            t.insert("time".into(), time.into());
        }
        if let Some(p) = playing {
            t.insert("playing".into(), p.into());
        }
        self.map.insert("timeline".into(), Value::Object(t));
        self
    }
    /// Moves the selected objects: `right` / `up` in cm as the view sees them (`forward` along the view).
    pub fn nudge_view(mut self, right: f64, up: f64, forward: f64) -> Self {
        self.nudge().insert("move_view".into(), json!([right, up, forward]));
        self
    }
    /// Turns the selected objects (degrees: pitch, yaw, roll).
    pub fn nudge_rotate(mut self, pitch: f64, yaw: f64, roll: f64) -> Self {
        self.nudge().insert("rotate".into(), json!([pitch, yaw, roll]));
        self
    }
    /// Scales the selected objects by `factor`.
    pub fn nudge_scale(mut self, factor: f64) -> Self {
        self.nudge().insert("scale".into(), factor.into());
        self
    }
    fn nudge(&mut self) -> &mut Map<String, Value> {
        let n = self.map.entry("nudge").or_insert_with(|| Value::Object(Map::new()));
        n.as_object_mut().expect("nudge is an object")
    }
    /// Writes the scene as `<name>.okscene` in the studio's folder for this mod, keeping the newest `keep` there.
    pub fn export(mut self, name: &str, keep: u32) -> Self {
        self.map.insert("export".into(), json!({"name": name, "keep": keep}));
        self
    }
    pub fn into_reply(self) -> Reply {
        Reply::Json(Value::Object(self.map).to_string().into())
    }
}

/// The answer to `studio.panel_ui`. Labels are text ids (`mod.<id>.…`, from the mod's `locale/`), or plain text.
#[derive(Debug, Clone, Default)]
pub struct Ui {
    map: Map<String, Value>,
}

impl Ui {
    pub fn new() -> Self {
        let mut map = Map::new();
        map.insert("protocol".into(), PROTOCOL.into());
        Ui { map }
    }
    fn push(&mut self, list: &str, item: Value) -> &mut Self {
        let l = self.map.entry(list).or_insert_with(|| Value::Array(Vec::new()));
        if let Value::Array(a) = l {
            a.push(item);
        }
        self
    }
    /// One of the mod's declared commands in the studio's command table, as `mod.<id>.<name>` (one undo step).
    pub fn command(&mut self, name: &str, label: &str) -> &mut Self {
        self.push("commands", json!({"name": name, "label": label}))
    }
    /// A tool row button running `command` (a full studio command id, e.g. `mod.<id>.<name>`).
    pub fn toolbar(&mut self, id: &str, label: &str, tooltip: &str, command: &str, arg: &str) -> &mut Self {
        self.push("toolbar", json!({"id": id, "label": label, "tooltip": tooltip, "command": command, "arg": arg}))
    }
    /// A context menu entry; `kinds` limits it to selections whose primary object is of one of these kinds
    /// (`character`, `item`, `light`, `camera`, `folder`, `effect`, `model`; empty: any).
    pub fn menu(&mut self, id: &str, label: &str, command: &str, arg: &str, kinds: &[&str]) -> &mut Self {
        self.push("menu", json!({"id": id, "label": label, "command": command, "arg": arg, "kinds": kinds}))
    }
    /// A row bound to a value in the mod's data. `panel`: `state` (the selected character's 狀態 page; `{object}` in
    /// `bind` is its id) or `scene` (畫面設定). `kind`: toggle, slider, dropdown, color, text, button.
    /// `bind` is a path in the data object, keys separated by `.`.
    pub fn control(&mut self, control: Value) -> &mut Self {
        self.push("controls", control)
    }
    /// A value the timeline can key, bound like a row (a number or an array of numbers in the data).
    pub fn interpolable(&mut self, id: &str, label: &str, bind: &str, per_object: bool) -> &mut Self {
        self.push("interpolables", json!({"id": id, "label": label, "bind": bind, "per_object": per_object}))
    }
    /// A key chord (`V`, `Ctrl+Shift+K`) sending `key` events; `drag`: while held, mouse moves send `drag` events.
    pub fn key(&mut self, id: &str, chord: &str, drag: bool) -> &mut Self {
        self.push("keys", json!({"id": id, "key": chord, "drag": drag}))
    }
    /// A `timer` event every `ms` milliseconds (at least 50).
    pub fn timer(&mut self, id: &str, ms: u64) -> &mut Self {
        self.push("timers", json!({"id": id, "ms": ms}))
    }
    /// A path in the data to a list of marks (`{"time": s}` objects or numbers): `timeline_pass` when played over.
    pub fn timeline_marks(&mut self, path: &str) -> &mut Self {
        self.map.insert("timeline_marks".into(), path.into());
        self
    }
    /// Send the scene's object list with every call.
    pub fn objects(&mut self, on: bool) -> &mut Self {
        self.map.insert("objects".into(), on.into());
        self
    }
    pub fn into_reply(&mut self) -> Reply {
        Reply::Json(Value::Object(std::mem::take(&mut self.map)).to_string().into())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn call_reads_the_context() {
        let c = Call::parse("studio.command", r#"{"studio":1,"name":"go","arg":"x","data":{"a":1},"selection":[3,4],"primary":4,"map":{"3":7}}"#).unwrap();
        assert_eq!(c.arg(), "x");
        assert_eq!(c.data()["a"], 1);
        assert_eq!(c.selection(), vec![3, 4]);
        assert_eq!(c.primary(), Some(4));
        assert_eq!(c.id_map(), vec![(3, 7)]);
        assert_eq!(c.command(), Some("go"));
        assert!(!c.is_ui());
        assert!(Call::parse("studio.command", "plain text").is_none());
        assert!(Call::parse("studio.command", r#"{"a":1}"#).is_none());
    }

    #[test]
    fn effect_writes_json() {
        let Reply::Json(j) = Effect::new().data(json!({"n": 1}), 2).status("ok").run("scene.save", "").into_reply() else { panic!() };
        let v: Value = serde_json::from_str(j.as_str()).unwrap();
        assert_eq!(v["data"]["n"], 1);
        assert_eq!(v["data_version"], 2);
        assert_eq!(v["run"][0]["command"], "scene.save");
    }
}
