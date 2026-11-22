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
    hair: bool,
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
        // Hair colour is not a registry key but the original editor's composite action (a base colour and the gradient,
        // outline and gloss it sets on every hair part): asked for as an op, applied the way the detailed editor applies
        // one (Docs/OK_MOD_HOOKS.md §5, `ops`).
        let mut ops = Vec::new();
        if self.hair {
            ops.push(json!({"op": "hair_base_color", "rgba": self.hair_colour()}));
        }
        let mut said = Vec::new();
        if !edits.is_empty() { said.push(format!("隨機調整了 {} 個滑桿", edits.len())); }
        if !ops.is_empty() { said.push("換了髮色".to_owned()); }
        let notice = if said.is_empty() { "身形、臉型、髮色都沒勾，沒有變更".to_owned() } else { said.join("，") };
        let mut reply = json!({"set": edits, "notice": notice});
        if !ops.is_empty() { reply["ops"] = json!(ops); }
        reply
    }
    /// A hair colour (0..1 RGB): any hue, saturation and value kept to what hair looks like; the spread widens them.
    fn hair_colour(&mut self) -> [f64; 3] {
        let reach = self.reach();
        let h = self.next();
        let s = (0.45 + (self.next() * 2.0 - 1.0) * reach).clamp(0.05, 0.95);
        let v = (0.6 + (self.next() * 2.0 - 1.0) * reach).clamp(0.15, 0.98);
        let rgb = hsv(h, s, v);
        rgb.map(|c| (c * 1000.0).round() / 1000.0)
    }
}

/// HSV (each 0..1) to RGB.
fn hsv(h: f64, s: f64, v: f64) -> [f64; 3] {
    let i = (h * 6.0).floor();
    let f = h * 6.0 - i;
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - f * s), v * (1.0 - (1.0 - f) * s));
    match i as i64 % 6 { 0 => [v, t, p], 1 => [q, v, p], 2 => [p, v, t], 3 => [p, q, v], 4 => [t, p, v], _ => [v, p, q] }
}

impl Mod for RandomChara {
    fn create(_host: Host) -> ModResult<Self> {
        let seed = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(1) | 1;
        Ok(RandomChara { body: true, face: true, hair: false, spread: "medium".into(), seed })
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
                        {"kind": "bool", "key": "hair", "label": "髮色"},
                        {"kind": "radio", "key": "spread", "label": "幅度", "options": [
                            {"value": "small", "label": "小"}, {"value": "medium", "label": "中"}, {"value": "wide", "label": "大"}]},
                        {"kind": "button", "action": "roll", "label": "隨機"},
                    ],
                }]})),
                "reader.values" => hooks::json(&json!({"body": self.body, "face": self.face, "hair": self.hair, "spread": self.spread})),
                "reader.control" => {
                    let set: hooks::ReaderSet = hooks::parse(payload)?;
                    match set.key.as_str() {
                        "body" => self.body = set.value.as_bool().ok_or("body is true/false")?,
                        "face" => self.face = set.value.as_bool().ok_or("face is true/false")?,
                        "hair" => self.hair = set.value.as_bool().ok_or("hair is true/false")?,
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
        let mut m = RandomChara { body: true, face: false, hair: false, spread: "wide".into(), seed: 7 };
        let r = m.roll();
        let edits = r["set"].as_array().unwrap();
        assert_eq!(edits.len(), BODY);
        assert!(edits.iter().all(|e| (0.0..=1.0).contains(&e["value"].as_f64().unwrap())));
        assert!(edits.iter().all(|e| e["key"].as_str().unwrap().starts_with("shape.body.")));
        assert!(r.get("ops").is_none(), "no hair op unless asked");
    }

    #[test]
    fn hair_is_an_op() {
        let mut m = RandomChara { body: false, face: false, hair: true, spread: "medium".into(), seed: 11 };
        let r = m.roll();
        assert!(r["set"].as_array().unwrap().is_empty());
        let op = &r["ops"][0];
        assert_eq!(op["op"], "hair_base_color");
        let rgba = op["rgba"].as_array().unwrap();
        assert_eq!(rgba.len(), 3);
        assert!(rgba.iter().all(|c| (0.0..=1.0).contains(&c.as_f64().unwrap())));
        assert_eq!(r["notice"], "換了髮色");
        assert_eq!(hsv(0.0, 1.0, 1.0), [1.0, 0.0, 0.0]);
    }
}
