//! `boop`: a poke makes hair, chest and skirt bounce (Docs/OK_MOD_FRAMEWORK_PLAN.md §14, Docs/OK_MOD_S11_FRAME.md).
//! What it shows is the right way to use the per-frame call:
//! - the frame function (`ok_mod_frame!`) runs on worker threads for several characters at once, so it shares only
//!   `static` state with the mod (settings as atomics, pokes behind a lock it only holds to copy them);
//! - it stays far under the budget: a handful of anchor bones per character, found once and cached;
//! - it only answers physics forces (`Frame::push`), never touches bones.
//!
//! Pokes come from the hook `input.pointer` (a ray and a velocity, world space; the game sends it when the mouse sweeps
//! over a character) or from the console: `mod.org.openkoikatsu.boop.poke [head|chest|skirt|all]`.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::Instant;

use ok_mod_sdk::frame::{Force, Frame};
use ok_mod_sdk::prelude::*;
use serde::Deserialize;

// ---------------------------------------------------------------- shared with the frame function

static STRENGTH: AtomicU32 = AtomicU32::new(0);
static DECAY: AtomicU32 = AtomicU32::new(0);
static FREQUENCY: AtomicU32 = AtomicU32::new(0);

fn get(a: &AtomicU32) -> f32 {
    f32::from_bits(a.load(Ordering::Relaxed))
}
fn set(a: &AtomicU32, v: f64) {
    a.store((v as f32).to_bits(), Ordering::Relaxed)
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Target {
    /// Anchors near a ray (origin, direction).
    Ray([f32; 3], [f32; 3]),
    /// One region of every character: 0 head, 1 chest, 2 skirt.
    Region(usize),
}

#[derive(Clone, Copy, Debug)]
struct Poke {
    target: Target,
    /// Push direction (unit) and how hard relative to the strength setting.
    dir: [f32; 3],
    gain: f32,
    start: Instant,
}

static POKES: Mutex<Vec<Poke>> = Mutex::new(Vec::new());

/// Anchor bones per region, and the character's size (head to waist), cached per character and skeleton layout.
#[derive(Clone)]
struct Anchors {
    bones: [Vec<usize>; 3],
}
static ANCHORS: Mutex<Option<HashMap<(u64, usize), Anchors>>> = Mutex::new(None);

const REGIONS: [&[&str]; 3] = [
    &["cf_j_head"],
    &["cf_j_bust01_L", "cf_j_bust01_R"],
    &["cf_j_waist02", "cf_d_sk_top"],
];

fn anchors(f: &Frame) -> Anchors {
    let key = (f.character(), f.len());
    let mut g = ANCHORS.lock().unwrap_or_else(|e| e.into_inner());
    let map = g.get_or_insert_with(HashMap::new);
    if let Some(a) = map.get(&key) {
        return a.clone();
    }
    let bones = REGIONS.map(|names| names.iter().filter_map(|n| f.find(n)).collect::<Vec<_>>());
    let a = Anchors { bones };
    if map.len() > 64 {
        map.clear();
    }
    map.insert(key, a.clone());
    a
}

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn len(a: [f32; 3]) -> f32 {
    dot(a, a).sqrt()
}
fn unit(a: [f32; 3]) -> [f32; 3] {
    let l = len(a);
    if l > 1e-6 { [a[0] / l, a[1] / l, a[2] / l] } else { [1.0, 0.0, 0.0] }
}

/// Distance from `p` to the ray (origin, unit dir), behind the origin counting as the origin.
fn ray_distance(p: [f32; 3], origin: [f32; 3], dir: [f32; 3]) -> f32 {
    let v = sub(p, origin);
    let t = dot(v, dir).max(0.0);
    len(sub(v, [dir[0] * t, dir[1] * t, dir[2] * t]))
}

/// The frame: each live poke pushes the anchors it hits, a damped wobble over `decay` seconds.
fn frame(f: &mut Frame) -> bool {
    let pokes: Vec<Poke> = {
        let mut g = POKES.lock().unwrap_or_else(|e| e.into_inner());
        if g.is_empty() {
            return false;
        }
        let decay = get(&DECAY);
        g.retain(|p| p.start.elapsed().as_secs_f32() < decay);
        g.clone()
    };
    if pokes.is_empty() {
        return false;
    }
    let a = anchors(f);
    // The character's size sets the reach: head to waist.
    let size = match (a.bones[0].first(), a.bones[2].first()) {
        (Some(&h), Some(&w)) => len(sub(f.world_pos(h), f.world_pos(w))).max(1e-3),
        _ => return false,
    };
    let (strength, decay, frequency) = (get(&STRENGTH), get(&DECAY).max(1e-3), get(&FREQUENCY));
    for p in &pokes {
        let age = p.start.elapsed().as_secs_f32();
        let wobble = (std::f32::consts::TAU * frequency * age).cos() * (1.0 - age / decay);
        let k = strength * p.gain * wobble;
        for (region, bones) in a.bones.iter().enumerate() {
            for &b in bones {
                let at = f.world_pos(b);
                let hit = match p.target {
                    Target::Region(r) => r == region,
                    Target::Ray(origin, dir) => ray_distance(at, origin, dir) < size * 0.35,
                };
                if hit {
                    f.push(Force { center: at, radius: size * 0.6, force: [p.dir[0] * k, p.dir[1] * k, p.dir[2] * k], reserved: 0.0 });
                }
            }
        }
    }
    false
}
ok_mod_sdk::ok_mod_frame!(frame);

// ---------------------------------------------------------------- the mod

#[derive(Deserialize)]
struct Pointer {
    origin: [f32; 3],
    dir: [f32; 3],
    /// How the pointer moved, world units per second; the push follows it.
    velocity: [f32; 3],
}

struct Boop {
    host: Host,
    pokes: u64,
}

impl Boop {
    fn settings(&self) {
        set(&STRENGTH, self.host.config_float("strength").unwrap_or(0.02));
        set(&DECAY, self.host.config_float("decay").unwrap_or(0.8));
        set(&FREQUENCY, self.host.config_float("frequency").unwrap_or(3.0));
    }
    fn poke(&mut self, target: Target, dir: [f32; 3], gain: f32) {
        let mut g = POKES.lock().unwrap_or_else(|e| e.into_inner());
        if g.len() >= 16 {
            g.remove(0);
        }
        g.push(Poke { target, dir: unit(dir), gain, start: Instant::now() });
        self.pokes += 1;
    }
}

impl Mod for Boop {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Boop { host, pokes: 0 })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_float("strength", 0.02, 0.0, 0.5, "mod.org.openkoikatsu.boop.config.strength")
            .config_float("decay", 0.8, 0.1, 5.0, "mod.org.openkoikatsu.boop.config.decay")
            .config_float("frequency", 3.0, 0.5, 10.0, "mod.org.openkoikatsu.boop.config.frequency")
            .command("poke", "mod.org.openkoikatsu.boop.cmd.poke")
            .subscribe("input.pointer")
            .subscribe("config_changed");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Enabled | Event::ConfigChanged { .. } => self.settings(),
            Event::Hook { name, payload } if name.as_str() == "input.pointer" => {
                let p: Pointer = serde_json::from_str(payload.as_str()).map_err(|e| e.to_string())?;
                let speed = len(p.velocity);
                if speed > 1e-4 {
                    self.poke(Target::Ray(p.origin, unit(p.dir)), p.velocity, speed.clamp(0.2, 3.0));
                }
            }
            Event::Command { name, args } if name.as_str() == "poke" => {
                let regions: &[usize] = match args.as_str().trim() {
                    "" | "all" => &[0, 1, 2],
                    "head" => &[0],
                    "chest" => &[1],
                    "skirt" => &[2],
                    other => return Err(format!("poke [head|chest|skirt|all], not {other}")),
                };
                for &r in regions {
                    self.poke(Target::Region(r), [1.0, 0.0, 0.3], 1.0);
                }
                return Ok(Reply::Text(format!("boop ({} poke(s) so far)", self.pokes).into()));
            }
            Event::Command { name, .. } => return Err(format!("unknown command {name}")),
            _ => {}
        }
        Ok(Reply::None)
    }
}

ok_mod!(Boop);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ray_distance_measures_from_the_ray() {
        assert!((ray_distance([0.0, 1.0, 5.0], [0.0; 3], [0.0, 0.0, 1.0]) - 1.0).abs() < 1e-6);
        assert!((ray_distance([0.0, 0.0, -3.0], [0.0; 3], [0.0, 0.0, 1.0]) - 3.0).abs() < 1e-6, "behind: from the origin");
    }
}
