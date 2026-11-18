//! hscene: the street's one-on-one H scene (OKHScene.h's panel through /private and /hscene) with named fields, and its
//! state read back. game_call could reach /hscene before, but only as a string the MCP could neither read nor check
//! (2026-11-18). pair_call is a different scene (the Interaction host), not this one.
use crate::game::Game;
use anyhow::{Result, bail};
use serde_json::{Value, json};

pub fn tools() -> Vec<Value> {
    vec![json!({
        "name": "hscene",
        "description": "The one-on-one H scene in the street game (she and he alone; the H panel). Every call answers with the scene's state: \
open, the girl, state (Idle, Loop, ...), mode, pose, pending pose, speed, playback_speed, her/his gauges, orgasms, siru (liquid levels), \
outfit, and the panel's buttons (kind + label: poses 1000-1999, actions such as insert 2009, faster 2001, lock 2017, finishes 2004/2005; \
tabs 20 poses, 30 clothes). No field: only reads. open=<slot 1..10> starts it with her (fails while she is loading or busy); \
close=true ends it. Fields act in this order: speed, pause, pose, button, say, outfit, orbit/face_cam/crotch_cam, spray; \
wait_s waits before reading back (an animation settling). full=true returns the whole raw view.",
        "inputSchema": {"type": "object", "properties": {
            "open": {"type": "integer", "description": "heroine slot 1..10: begin the one-on-one with her"},
            "close": {"type": "boolean", "description": "end the one-on-one"},
            "button": {"type": "integer", "description": "press the panel button with this kind (see buttons in the answer)"},
            "pose": {"type": "string", "description": "pick a pose by its name"},
            "speed": {"type": "number", "description": "motion speed slider (0..3)"},
            "pause": {"type": "boolean", "description": "pause/resume the motion, as the space key"},
            "say": {"type": "string", "description": "a line for him"},
            "outfit": {"type": "integer", "description": "her card's outfit 0..6"},
            "orbit": {"type": "object", "description": "camera round her hips (or bone), turned from where she faces",
                "properties": {"yaw": {"type": "number"}, "pitch": {"type": "number"}, "distance": {"type": "number"}, "bone": {"type": "string"}}},
            "face_cam": {"type": "number", "description": "camera at her face, this far (cm)"},
            "crotch_cam": {"type": "number", "description": "camera at her crotch, this far (cm)"},
            "spray": {"type": "boolean", "description": "the water gun firing at the orbit focus (development builds)"},
            "spray_at": {"type": "array", "items": {"type": "number"}, "description": "[x,y,z] cm from the focus for spray"},
            "wait_s": {"type": "number", "description": "seconds to wait before reading the state back"},
            "full": {"type": "boolean", "description": "return the whole raw view"}
        }}
    })]
}

/// Whether the call changes the scene (no field, or only wait_s/full: a read).
pub fn mutates(a: &Value) -> bool {
    a.as_object().is_some_and(|o| o.keys().any(|k| k != "wait_s" && k != "full"))
}

pub fn run(game: &Game, a: &Value) -> Result<Value> {
    let mut notes = Vec::new();
    if a["close"] == true {
        notes.push(format!("close: {}", game.call("/private", Some(&json!({"off": true})))?));
    }
    if let Some(girl) = a["open"].as_i64() {
        let r = game.call("/private", Some(&json!({"girl": girl})))?;
        if r["ok"] != true {
            bail!("open girl {girl}: {}", r["error"].as_str().unwrap_or("refused"));
        }
        notes.push(format!("opened girl {girl}"));
    }
    let mut body = json!({});
    for k in ["speed", "pause", "pose", "say", "outfit", "face_cam", "crotch_cam", "spray", "spray_at"] {
        if !a[k].is_null() {
            body[k] = a[k].clone();
        }
    }
    if let Some(kind) = a["button"].as_i64() {
        body["kind"] = json!(kind);
    }
    if a["orbit"].is_object() {
        let o = &a["orbit"];
        body["orbit"] = json!([o["yaw"].as_f64().unwrap_or(0.0), o["pitch"].as_f64().unwrap_or(10.0), o["distance"].as_f64().unwrap_or(150.0)]);
        if let Some(bone) = o["bone"].as_str() {
            body["orbit_bone"] = json!(bone);
        }
    }
    let acted = body.as_object().is_some_and(|o| !o.is_empty());
    if acted {
        let r = game.call("/hscene", Some(&body))?;
        if r["ok"] != true {
            bail!("hscene: {}", r["error"].as_str().unwrap_or("refused"));
        }
    }
    if let Some(w) = a["wait_s"].as_f64() {
        std::thread::sleep(std::time::Duration::from_secs_f64(w.clamp(0.0, 120.0)));
    }
    // The read back: an empty body changes nothing and answers the view.
    let r = game.call("/hscene", Some(&json!({})))?;
    let text = if r["ok"] != true {
        format!("open: false ({})", r["error"].as_str().unwrap_or("-"))
    } else if a["full"] == true {
        serde_json::to_string_pretty(&r["h"])?
    } else {
        summary(&r["h"])
    };
    let mut out = notes;
    out.push(text);
    Ok(json!({"content": [{"type": "text", "text": out.join("\n")}], "isError": false}))
}

fn summary(h: &Value) -> String {
    let s = |k: &str| match &h[k] {
        Value::String(t) => t.clone(),
        Value::Null => "-".into(),
        v => v.to_string(),
    };
    let mut lines = vec![
        "open: true".to_string(),
        format!("state {} (wanted {}) mode {} pose {} pending {} tab {}", s("state"), s("wanted"), s("mode"), s("pose"), s("pending"), s("tab")),
        format!("speed {} playback {} her {} his {} orgasms {} siru {} outfit {} condom {}", s("speed"), s("playback_speed"), s("her"), s("his"),
            s("orgasms"), s("siru"), s("outfit"), s("condom")),
    ];
    let title = s("title");
    if !title.is_empty() && title != "-" {
        lines.push(format!("title: {title}  hint: {}", s("hint")));
    }
    // The buttons on the panel: any array of {kind, label} objects in the view.
    if let Some(o) = h.as_object() {
        for (k, v) in o {
            let Some(items) = v.as_array() else { continue };
            let list: Vec<String> = items.iter().filter_map(|b| Some(format!("{} {}", b["kind"].as_i64()?, b["label"].as_str().unwrap_or("")))).collect();
            if !list.is_empty() {
                lines.push(format!("{k}: {}", list.join(" | ")));
            }
        }
    }
    lines.join("\n")
}
