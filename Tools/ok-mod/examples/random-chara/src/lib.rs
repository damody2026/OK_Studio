//! `random-chara`: a reader page that randomizes her body and face (RandomCharacterGenerator, plan §14.1).
//!
//! The mod never touches the model: its button runs the command `roll`, whose reply asks the reader for registry edits
//! (`{"set": [{"key": "shape.body.3", "value": 0.42}, ...]}`), the same edits reader_call `set` makes. Which sliders it
//! moves and how far are the page's own controls (`body`, `face`, `spread`).

use ok_mod_sdk::prelude::*;
use serde_json::{json, Value};

/// KKS: 44 body sliders, 52 face sliders (OKCharacterMCPRegistry `shape.body.N` / `shape.face.N`).
const BODY: usize = 44;
const FACE: usize = 52;

struct RandomChara {
    body: bool,
    face: bool,
    /// How far from the middle (0.5) a value may go: "small" 0.15, "medium" 0.3, "wide" 0.5.
    spread: String,
    seed: u64,
}

impl RandomChara {
    fn next(&mut self) -> f64 {
        // xorshift64*: enough for sliders, no dependency.
        self.seed ^= self.seed >> 12;
        self.seed ^= self.seed << 25;
        self.seed ^= self.seed >> 27;
        (self.seed.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 11) as f64 / (1u64 << 53) as f64
    }
    fn reach(&self) -> f64 {
        match self.spread.as_str() { "small" => 0.15, "wide" => 0.5, _ => 0.3 }
    }
    fn roll(&mut self) -> Value {
        let reach = self.reach();
        let mut edits = Vec::new();
        for (on, part, n) in [(self.body, "body", BODY), (self.face, "face", FACE)] {
            if !on { continue; }
            for i in 0..n {
                let v = (0.5 + (self.next() * 2.0 - 1.0) * reach).clamp(0.0, 1.0);
                edits.push(json!({"key": format!("shape.{part}.{i}"), "value": (v * 100.0).round() / 100.0}));
            }
        }
        let notice = if edits.is_empty() { "身形與臉型都沒勾，沒有變更".to_owned() } else { format!("隨機調整了 {} 個滑桿", edits.len()) };
        json!({"set": edits, "notice": notice})
    }
}

impl Mod for RandomChara {
    fn create(_host: Host) -> ModResult<Self> {
        let seed = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1) | 1;
        Ok(RandomChara { body: true, face: true, spread: "medium".into(), seed })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.command("roll", "mod.org.openkoikatsu.random-chara.cmd.roll");
        for hook in ["reader.ui", "reader.values", "reader.control"] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Command { name, .. } if name.as_str() == "roll" => hooks::json(&self.roll()),
            Event::Command { name, .. } => Err(format!("unknown command {name}")),
            Event::Hook { name, payload } => match name.as_str() {
                "reader.ui" => hooks::json(&json!({"pages": [{
                    "name": "隨機角色",
                    "items": [
                        {"kind": "bool", "key": "body", "label": "身形"},
                        {"kind": "bool", "key": "face", "label": "臉型"},
                        {"kind": "choice", "key": "spread", "label": "幅度", "options": [
                            {"value": "small", "label": "小"}, {"value": "medium", "label": "中"}, {"value": "wide", "label": "大"}]},
                        {"kind": "button", "action": "roll", "label": "隨機"},
                    ],
                }]})),
                "reader.values" => hooks::json(&json!({"body": self.body, "face": self.face, "spread": self.spread})),
                "reader.control" => {
                    let set: hooks::ReaderSet = hooks::parse(payload)?;
                    match set.key.as_str() {
                        "body" => self.body = set.value.as_bool().ok_or("body is true/false")?,
                        "face" => self.face = set.value.as_bool().ok_or("face is true/false")?,
                        "spread" => {
                            let s = set.value.as_str().ok_or("spread is a string")?;
                            if !["small", "medium", "wide"].contains(&s) { return Err(format!("spread {s}: small, medium or wide")); }
                            self.spread = s.into();
                        }
                        other => return Err(format!("unknown key {other}")),
                    }
                    Ok(Reply::None)
                }
                _ => Ok(Reply::None),
            },
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(RandomChara);

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rolls_stay_in_range_and_follow_the_switches() {
        let mut m = RandomChara { body: true, face: false, spread: "wide".into(), seed: 7 };
        let r = m.roll();
        let edits = r["set"].as_array().unwrap();
        assert_eq!(edits.len(), BODY);
        assert!(edits.iter().all(|e| (0.0..=1.0).contains(&e["value"].as_f64().unwrap())));
        assert!(edits.iter().all(|e| e["key"].as_str().unwrap().starts_with("shape.body.")));
    }
}
