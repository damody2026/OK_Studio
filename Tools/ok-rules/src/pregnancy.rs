//! Her pregnancy (user 2026-11-03, after AL_Pregnancy for AmanatsuLocation): his finish inside her vagina without a
//! condom may make her pregnant by the day of her 28-day cycle; the pregnancy runs 280 game days, her belly growing by
//! stages; after the birth she recovers 180 days before she can again. The births and the pregnancy also change her
//! body for good (areolae larger, nipples darker), fully after five. Kept per heroine in ext.preg.<id>; everything
//! else is worked out from the game day, so no day has to be visited.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub const GESTATION_DAYS: i64 = 280;
pub const RECOVERY_DAYS: i64 = 180;
pub const CYCLE_DAYS: i64 = 28;
/// Births (with the pregnancy under way counted as its part of one) at which her body has fully changed.
pub const FULL_CHANGE: f32 = 5.0;
/// Her belly at each part of the way (AL_Pregnancy's stages 0, 20, 45, 70, 100%): fraction of the full belly.
const BELLY: [(f32, f32); 5] = [(0.0, 0.0), (0.2, 0.05), (0.45, 0.3), (0.7, 0.65), (1.0, 1.0)];

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct Preg {
    /// Game day she conceived (-1 not pregnant).
    pub since: i64,
    pub births: i32,
    /// Game day until which she recovers from the last birth (-1 none).
    pub recover_until: i64,
}

impl Default for Preg {
    fn default() -> Self { Preg { since: -1, births: 0, recover_until: -1 } }
}

/// Her stored state with what the days since have done: a pregnancy past its term is a birth, its recovery after.
pub fn on_day(ext: &Value, girl: &str, day: i64) -> Preg {
    let mut p: Preg = ext.get("preg").and_then(|m| m.get(girl)).and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
    if p.since >= 0 && day >= p.since + GESTATION_DAYS {
        p.births += 1;
        p.recover_until = p.since + GESTATION_DAYS + RECOVERY_DAYS;
        p.since = -1;
    }
    p
}

/// The day of her cycle (0..27): each girl's cycle starts on her own day.
fn cycle_day(girl: &str, day: i64) -> i64 {
    let offset = girl.bytes().fold(2166136261u32, |h, b| (h ^ b as u32).wrapping_mul(16777619)) as i64 % CYCLE_DAYS;
    (day.max(0) + offset).rem_euclid(CYCLE_DAYS)
}

/// AL_Pregnancy's SimpleCycle: days 12..16 of the cycle half, 8..19 one in twenty, the rest never.
pub fn chance(girl: &str, day: i64) -> f32 {
    match cycle_day(girl, day) {
        12..=16 => 0.5,
        8..=19 => 0.05,
        _ => 0.0,
    }
}

fn belly(progress: f32) -> f32 {
    let p = progress.clamp(0.0, 1.0);
    BELLY.windows(2).find(|w| p <= w[1].0).map_or(1.0, |w| w[0].1 + (w[1].1 - w[0].1) * (p - w[0].0) / (w[1].0 - w[0].0))
}

/// What the scene and the street show of it on `day`.
pub fn view(p: &Preg, girl: &str, day: i64) -> Value {
    let progress = if p.since >= 0 { ((day - p.since) as f32 / GESTATION_DAYS as f32).clamp(0.0, 1.0) } else { 0.0 };
    let recovering = p.since < 0 && day < p.recover_until;
    json!({
        "pregnant": p.since >= 0,
        "progress": progress,
        "week": if p.since >= 0 { (day - p.since) / 7 } else { 0 },
        "belly": belly(progress),
        "body": ((p.births as f32 + progress) / FULL_CHANGE).min(1.0),
        "births": p.births,
        "recovering": recovering,
        "cycle_day": cycle_day(girl, day),
        "chance": if p.since >= 0 || recovering { 0.0 } else { chance(girl, day) },
    })
}

/// A scene ended on `day` with `inside` finishes in her vagina without a condom: each may make her pregnant (one roll
/// each, `seed` the scene's). Returns whether she conceived now.
pub fn after_scene(p: &mut Preg, girl: &str, day: i64, inside: i64, seed: i32) -> bool {
    if day < 0 || inside <= 0 || p.since >= 0 || day < p.recover_until {
        return false;
    }
    let mut rng = crate::rng::RandomStream::new(seed);
    let c = chance(girl, day);
    if (0..inside.min(10)).any(|_| rng.chance(c)) {
        p.since = day;
        return true;
    }
    false
}

pub fn store(ext: &mut Value, girl: &str, p: &Preg) {
    if !ext.get("preg").is_some_and(Value::is_object) {
        ext["preg"] = json!({});
    }
    ext["preg"][girl] = serde_json::to_value(p).unwrap_or(Value::Null);
}

/// Request: girl, ext, day, progress (0..1). Answer: ext with her pregnancy that far along (a test and debug set).
fn set(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).ok_or("missing_field: girl")?;
    let day = r.get("day").and_then(Value::as_i64).ok_or("missing_field: day")?;
    let mut ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut p = on_day(&ext, girl, day);
    match r.get("progress").and_then(Value::as_f64) {
        Some(f) if f > 0.0 => { p.since = day - (f.min(0.999) * GESTATION_DAYS as f64).round() as i64; p.recover_until = -1; }
        _ => p.since = -1,
    }
    if let Some(b) = r.get("births").and_then(Value::as_i64) { p.births = b.clamp(0, 100) as i32; }
    store(&mut ext, girl, &p);
    Ok(json!({"ext": ext, "pregnancy": view(&p, girl, day)}))
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    match kind {
        "preg_set" => Some(set(r)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn belly_grows_by_stages_and_body_by_births() {
        assert_eq!(belly(0.0), 0.0);
        assert!((belly(0.2) - 0.05).abs() < 1e-6);
        assert!((belly(0.575) - 0.475).abs() < 1e-4);
        assert_eq!(belly(1.0), 1.0);
        let p = Preg { since: 0, births: 2, recover_until: -1 };
        let v = view(&p, "a", 140);
        assert!((v["progress"].as_f64().unwrap() - 0.5).abs() < 1e-6);
        assert!((v["body"].as_f64().unwrap() - 0.5).abs() < 1e-6);
        assert_eq!(v["week"], 20);
    }

    #[test]
    fn term_is_a_birth_then_recovery() {
        let ext = json!({"preg": {"a": {"since": 10, "births": 0, "recover_until": -1}}});
        let p = on_day(&ext, "a", 10 + GESTATION_DAYS);
        assert_eq!((p.since, p.births, p.recover_until), (-1, 1, 10 + GESTATION_DAYS + RECOVERY_DAYS));
        let v = view(&p, "a", 10 + GESTATION_DAYS + 5);
        assert_eq!(v["recovering"], true);
        assert_eq!(v["chance"], 0.0);
        let mut q = p.clone();
        assert!(!after_scene(&mut q, "a", 10 + GESTATION_DAYS + 5, 10, 1));
    }

    #[test]
    fn conception_follows_her_cycle() {
        let fertile = (0..CYCLE_DAYS).find(|&d| cycle_day("a", d) == 14).unwrap();
        let safe = (0..CYCLE_DAYS).find(|&d| cycle_day("a", d) == 2).unwrap();
        assert_eq!(chance("a", fertile), 0.5);
        assert_eq!(chance("a", safe), 0.0);
        let mut p = Preg::default();
        assert!(!after_scene(&mut p, "a", safe, 10, 7));
        let took = (0..20).filter(|&s| { let mut p = Preg::default(); after_scene(&mut p, "a", fertile, 1, s) }).count();
        assert!(took > 3 && took < 17, "{took}");
        let mut p = Preg::default();
        assert!(!after_scene(&mut p, "a", fertile, 0, 7));
    }
}
