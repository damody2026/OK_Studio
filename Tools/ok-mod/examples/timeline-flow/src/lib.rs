//! `timeline-flow` (TimelineFlowControl; Docs/OK_MOD_FRAMEWORK_PLAN.md §14.2): marks on the timeline that the core's
//! whole-timeline loop cannot do: loop a stretch (A … B), jump to a time, stop and wait (play goes on with the play
//! button). The marks are scene data; the studio tells the mod when playback passes one (no per-frame tick).
//!
//! Scene data (version 1): `{"marks": [{"time": s, "kind": "loop_start" | "loop_end" | "jump" | "stop", "to": s}]}`.

use ok_mod_sdk::prelude::*;
use ok_mod_studio::{json, Call, Effect, Ui, Value};

const ID: &str = "org.openkoikatsu.timeline_flow";
const P: &str = "mod.org.openkoikatsu.timeline_flow";
const VERSION: u64 = 1;

struct Flow;

fn marks(data: &Value) -> Vec<Value> {
    data.get("marks").and_then(Value::as_array).cloned().unwrap_or_default()
}

fn time_of(m: &Value) -> f64 {
    m.get("time").and_then(Value::as_f64).unwrap_or(0.0)
}

fn kind_of(m: &Value) -> &str {
    m.get("kind").and_then(Value::as_str).unwrap_or("")
}

fn label(kind: &str) -> &'static str {
    match kind {
        "loop_start" => "迴圈起點 A",
        "loop_end" => "迴圈終點 B",
        "jump" => "跳轉",
        "stop" => "停住",
        _ => "標記",
    }
}

fn store(mut list: Vec<Value>) -> Effect {
    list.sort_by(|a, b| time_of(a).total_cmp(&time_of(b)));
    if list.is_empty() {
        Effect::new().clear_data()
    } else {
        Effect::new().data(json!({ "marks": list }), VERSION)
    }
}

impl Flow {
    fn ui(&self) -> Reply {
        let cmd = |n: &str| format!("mod.{ID}.{n}");
        Ui::new()
            .command("loop_start", &format!("{P}.cmd.loop_start"))
            .command("loop_end", &format!("{P}.cmd.loop_end"))
            .command("jump", &format!("{P}.cmd.jump"))
            .command("stop", &format!("{P}.cmd.stop"))
            .command("clear", &format!("{P}.cmd.clear"))
            .toolbar("loop_start", "A", &format!("{P}.tool.loop_start"), &cmd("loop_start"), "")
            .toolbar("loop_end", "B", &format!("{P}.tool.loop_end"), &cmd("loop_end"), "")
            .toolbar("stop", "停", &format!("{P}.tool.stop"), &cmd("stop"), "")
            .toolbar("jump", "跳", &format!("{P}.tool.jump"), &cmd("jump"), "0")
            .toolbar("clear", "清", &format!("{P}.tool.clear"), &cmd("clear"), "")
            .timeline_marks("marks")
            .into_reply()
    }

    /// A mark at the playhead (one of a kind at the same time replaces the other).
    fn mark(&self, call: &Call, kind: &str) -> Reply {
        let t = call.time();
        let mut list = marks(call.data());
        list.retain(|m| !((time_of(m) - t).abs() < 1e-3 && kind_of(m) == kind));
        let mut m = json!({"time": t, "kind": kind});
        if kind == "jump" {
            let to: f64 = call.arg().trim().parse().unwrap_or(0.0);
            m["to"] = to.into();
        }
        list.push(m);
        store(list).status(format!("{} 於 {t:.2} 秒", label(kind))).into_reply()
    }

    fn passed(&self, call: &Call) -> Reply {
        let list = marks(call.data());
        // The first mark passed that changes the flow wins (several in one frame: the earliest).
        for i in call.marks() {
            let Some(m) = list.get(i) else { continue };
            match kind_of(m) {
                "loop_end" => {
                    let end = time_of(m);
                    let start = list.iter().filter(|x| kind_of(x) == "loop_start" && time_of(x) < end).map(time_of).fold(None, |a: Option<f64>, t| Some(a.map_or(t, |a| a.max(t))));
                    if let Some(start) = start {
                        return Effect::new().timeline(Some(start), Some(true)).into_reply();
                    }
                }
                "jump" => {
                    let to = m.get("to").and_then(Value::as_f64).unwrap_or(0.0);
                    return Effect::new().timeline(Some(to), Some(true)).status(format!("跳到 {to:.2} 秒")).into_reply();
                }
                "stop" => {
                    return Effect::new().timeline(Some(time_of(m)), Some(false)).status("停住：按播放繼續").into_reply();
                }
                _ => {}
            }
        }
        Effect::new().into_reply()
    }
}

impl Mod for Flow {
    fn create(_host: Host) -> ModResult<Self> {
        Ok(Flow)
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        ok_mod_studio::subscribe(reg, &["timeline_pass"], &[], &[]);
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Some(call) = Call::from_event(event) else { return Ok(Reply::None) };
        Ok(match call.command() {
            _ if call.is_ui() => self.ui(),
            Some("clear") => store(Vec::new()).status("已清除時間軸標記").into_reply(),
            Some(kind @ ("loop_start" | "loop_end" | "jump" | "stop")) => self.mark(&call, kind),
            Some(other) => return Err(format!("unknown command {other}")),
            None if call.event() == "timeline_pass" => self.passed(&call),
            None => Effect::new().into_reply(),
        })
    }
}

ok_mod!(Flow);
