//! Her pregnancy (user 2026-11-03, after AL_Pregnancy for AmanatsuLocation): his finish inside her vagina without a
//! condom may make her pregnant by the day of her 28-day cycle; each pregnancy runs its own 37 to 42 weeks (as a real
//! one, H_SCENE_ADDITIONS_PLAN 8), her belly growing by stages and her bust up to half again; after the birth she
//! recovers 180 days before she can again, her bust going back over those six months and her belly in a month. She
//! knows from her fifth or sixth week (her period late), is sick weeks 6 to 14 and heavy from 28. The births and the
//! pregnancy also change her body for good (areolae larger, nipples darker), fully after five. Kept per heroine in
//! ext.preg.<id>; everything else is worked out from the game day, so no day has to be visited.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// A pregnancy stored before each had its own term: forty weeks.
pub const GESTATION_DAYS: i64 = 280;
/// Each pregnancy's term: 37 to 42 weeks.
pub const TERM_MIN: i64 = 37 * 7;
pub const TERM_MAX: i64 = 42 * 7;
pub const RECOVERY_DAYS: i64 = 180;
/// Her belly gone this many days after the birth; her bust takes the whole recovery.
pub const BELLY_BACK_DAYS: i64 = 30;
pub const CYCLE_DAYS: i64 = 28;
/// Births (with the pregnancy under way counted as its part of one) at which her body has fully changed.
pub const FULL_CHANGE: f32 = 5.0;
/// Her bust at term: half again (the desire's swell adds to it, OKHScene SwellBust).
pub const BUST_GAIN: f32 = 0.5;
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
    /// This pregnancy's term in days (0: one stored before terms, GESTATION_DAYS).
    pub term: i64,
    /// Game day of the last birth (-1 none).
    pub born_at: i64,
    /// She has been told (by her body) of this pregnancy and it is in her memory; births so far that are.
    pub told: bool,
    pub births_noted: i32,
    /// Made to ovulate (the control channel's game_ovulate): any finish inside takes, whatever the day, until she conceives.
    pub ovulate: bool,
}

impl Default for Preg {
    fn default() -> Self { Preg { since: -1, births: 0, recover_until: -1, term: 0, born_at: -1, told: false, births_noted: 0, ovulate: false } }
}

impl Preg {
    pub fn term_days(&self) -> i64 { if self.term > 0 { self.term } else { GESTATION_DAYS } }
}

fn hash(girl: &str) -> u32 { girl.bytes().fold(2166136261u32, |h, b| (h ^ b as u32).wrapping_mul(16777619)) }

/// Her stored state with what the days since have done: a pregnancy past its term is a birth, its recovery after.
pub fn on_day(ext: &Value, girl: &str, day: i64) -> Preg {
    let mut p: Preg = ext.get("preg").and_then(|m| m.get(girl)).and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
    if p.since >= 0 && day >= p.since + p.term_days() {
        p.births += 1;
        p.born_at = p.since + p.term_days();
        p.recover_until = p.born_at + RECOVERY_DAYS;
        p.since = -1;
        p.term = 0;
        p.told = false;
    }
    p
}

/// The day of her cycle (0..27): each girl's cycle starts on her own day.
fn cycle_day(girl: &str, day: i64) -> i64 {
    let offset = hash(girl) as i64 % CYCLE_DAYS;
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

/// Her chance today with what has been done to her: made to ovulate it is certain.
fn chance_now(p: &Preg, girl: &str, day: i64) -> f32 { if p.ovulate { 1.0 } else { chance(girl, day) } }

fn belly(progress: f32) -> f32 {
    let p = progress.clamp(0.0, 1.0);
    BELLY.windows(2).find(|w| p <= w[1].0).map_or(1.0, |w| w[0].1 + (w[1].1 - w[0].1) * (p - w[0].0) / (w[1].0 - w[0].0))
}

/// The day she knows (her period late): five weeks and her own 0..7 days in.
fn knows_from(girl: &str) -> i64 { 35 + (hash(girl) >> 8) as i64 % 8 }

/// How many times she is sick on `day` (weeks 6 to 14): 1 to 3, her own per day.
fn sick_times(girl: &str, day: i64) -> i64 { 1 + ((hash(girl) as i64 ^ day.wrapping_mul(2654435761)) & 0xffff) % 3 }

/// What the scene and the street show of it on `day`.
pub fn view(p: &Preg, girl: &str, day: i64) -> Value {
    let pregnant = p.since >= 0;
    let days = if pregnant { day - p.since } else { 0 };
    let progress = if pregnant { (days as f32 / p.term_days() as f32).clamp(0.0, 1.0) } else { 0.0 };
    let week = days / 7;
    let after = if p.born_at >= 0 && day >= p.born_at { day - p.born_at } else { -1 };
    let recovering = !pregnant && day < p.recover_until;
    // Her belly and bust going back after the birth: the belly in a month, the bust over the six months.
    let back = |over: i64| if after >= 0 && after < over { 1.0 - after as f32 / over as f32 } else { 0.0 };
    let sick = pregnant && (6..=14).contains(&week);
    json!({
        "pregnant": pregnant,
        "progress": progress,
        "week": week,
        "term_weeks": if pregnant { p.term_days() / 7 } else { 0 },
        "days_left": if pregnant { (p.term_days() - days).max(0) } else { 0 },
        "belly": if pregnant { belly(progress) } else { back(BELLY_BACK_DAYS) },
        "bust": BUST_GAIN * if pregnant { progress } else { back(RECOVERY_DAYS) },
        "body": ((p.births as f32 + progress) / FULL_CHANGE).min(1.0),
        "births": p.births,
        "days_since_birth": after,
        "recovering": recovering,
        "knows": pregnant && days >= knows_from(girl),
        "sick": sick,
        "sick_times": if sick { sick_times(girl, day) } else { 0 },
        "heavy": pregnant && week >= 28,
        // Lying on her front or pressed on her belly: not from week 20 (OKHScene locks those poses).
        "belly_locked": pregnant && week >= 20,
        "cycle_day": cycle_day(girl, day),
        "chance": if pregnant || recovering { 0.0 } else { chance_now(p, girl, day) },
        "ovulate": p.ovulate,
    })
}

/// A scene ended on `day` with `inside` finishes in her vagina without a condom: each may make her pregnant (one roll
/// each, `seed` the scene's). Returns whether she conceived now; the pregnancy's term is drawn with it.
pub fn after_scene(p: &mut Preg, girl: &str, day: i64, inside: i64, seed: i32) -> bool {
    if day < 0 || inside <= 0 || p.since >= 0 || day < p.recover_until {
        return false;
    }
    let mut rng = crate::rng::RandomStream::new(seed);
    let c = chance_now(p, girl, day);
    if p.ovulate || (0..inside.min(10)).any(|_| rng.chance(c)) {
        p.ovulate = false;
        p.since = day;
        p.term = TERM_MIN + rng.rand_range(0, (TERM_MAX - TERM_MIN) as i32) as i64;
        p.told = false;
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

/// A new day for her (the street asks each morning and on load). Request: girl, ext, day, place. Answer: ext, effects
/// (her memory the first time she knows, and of a birth), pregnancy (view), learned / born (now).
fn day(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).ok_or("missing_field: girl")?;
    let day = r.get("day").and_then(Value::as_i64).ok_or("missing_field: day")?;
    let place = r.get("place").and_then(Value::as_str).unwrap_or("");
    let mut ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut p = on_day(&ext, girl, day);
    let v = view(&p, girl, day);
    let mut fx = crate::effects::Effects::default();
    let learned = v["knows"] == true && !p.told;
    if learned {
        p.told = true;
        fx.note_at(girl, "pregnancy", &crate::tr::m("preg.learned", &[("week", crate::tr::a(&v["week"].to_string()))]), place, 0.95);
    }
    let born = p.births > p.births_noted;
    if born {
        p.births_noted = p.births;
        fx.note_at(girl, "pregnancy", crate::tr::t("preg.birth"), place, 0.95);
    }
    if learned || born || ext.get("preg").and_then(|m| m.get(girl)).is_none_or(|s| serde_json::from_value::<Preg>(s.clone()).ok().as_ref() != Some(&p)) {
        store(&mut ext, girl, &p);
    }
    Ok(json!({"ext": ext, "effects": fx.into_value(), "pregnancy": v, "learned": learned, "born": born}))
}

/// Request: girl, ext, day, progress (0..1). Answer: ext with her pregnancy that far along (a test and debug set).
fn set(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).ok_or("missing_field: girl")?;
    let day = r.get("day").and_then(Value::as_i64).ok_or("missing_field: day")?;
    let mut ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut p = on_day(&ext, girl, day);
    match r.get("progress").and_then(Value::as_f64) {
        Some(f) if f > 0.0 => {
            if p.term <= 0 { p.term = GESTATION_DAYS; }
            p.since = day - (f.min(0.999) * p.term_days() as f64).round() as i64;
            p.recover_until = -1;
        }
        _ => p.since = -1,
    }
    if let Some(b) = r.get("births").and_then(Value::as_i64) { p.births = b.clamp(0, 100) as i32; p.births_noted = p.births; }
    // A birth this many days ago (her bust and belly going back).
    if let Some(a) = r.get("born_days_ago").and_then(Value::as_i64) { p.born_at = day - a.max(0); p.recover_until = p.born_at + RECOVERY_DAYS; }
    store(&mut ext, girl, &p);
    Ok(json!({"ext": ext, "pregnancy": view(&p, girl, day)}))
}

/// Request: girl, ext, day, on (omitted: only asks). Answer: ext, pregnancy (a test and debug set: game_ovulate).
fn ovulate(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).ok_or("missing_field: girl")?;
    let day = r.get("day").and_then(Value::as_i64).ok_or("missing_field: day")?;
    let mut ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let mut p = on_day(&ext, girl, day);
    if let Some(on) = r.get("on").and_then(Value::as_bool) {
        p.ovulate = on;
        store(&mut ext, girl, &p);
    }
    Ok(json!({"ext": ext, "pregnancy": view(&p, girl, day)}))
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    match kind {
        "preg_ovulate" => Some(ovulate(r)),
        "preg_set" => Some(set(r)),
        "preg_day" => Some(day(r)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn made_to_ovulate_any_finish_inside_takes_once() {
        // A day she never can on her own.
        let barren = (0..CYCLE_DAYS).find(|&d| chance("a", d) == 0.0).unwrap();
        let on = ovulate(&json!({"girl": "a", "day": barren, "on": true})).unwrap();
        assert_eq!(on["pregnancy"]["ovulate"], true);
        assert_eq!(on["pregnancy"]["chance"], 1.0);
        let mut p = on_day(&on["ext"], "a", barren);
        assert!(!after_scene(&mut p, "a", barren, 0, 1), "no finish inside, nothing takes");
        assert!(p.ovulate);
        assert!(after_scene(&mut p, "a", barren, 1, 1));
        assert_eq!(p.since, barren);
        assert!(!p.ovulate, "spent on the pregnancy");
        // Off again: her own cycle, and only reading changes nothing.
        let off = ovulate(&json!({"girl": "a", "day": barren, "ext": on["ext"], "on": false})).unwrap();
        assert_eq!(off["pregnancy"]["chance"], 0.0);
        let read = ovulate(&json!({"girl": "a", "day": barren, "ext": on["ext"]})).unwrap();
        assert_eq!(read["ext"], on["ext"]);
    }

    #[test]
    fn belly_grows_by_stages_and_body_by_births() {
        assert_eq!(belly(0.0), 0.0);
        assert!((belly(0.2) - 0.05).abs() < 1e-6);
        assert!((belly(0.575) - 0.475).abs() < 1e-4);
        assert_eq!(belly(1.0), 1.0);
        let p = Preg { since: 0, births: 2, ..Preg::default() };
        let v = view(&p, "a", 140);
        assert!((v["progress"].as_f64().unwrap() - 0.5).abs() < 1e-6);
        assert!((v["body"].as_f64().unwrap() - 0.5).abs() < 1e-6);
        assert!((v["bust"].as_f64().unwrap() - 0.25).abs() < 1e-6);
        assert_eq!(v["week"], 20);
        assert_eq!(v["belly_locked"], true);
    }

    #[test]
    fn term_is_a_birth_then_recovery() {
        let ext = json!({"preg": {"a": {"since": 10, "births": 0, "recover_until": -1, "term": 270}}});
        let p = on_day(&ext, "a", 10 + 270);
        assert_eq!((p.since, p.births, p.born_at, p.recover_until), (-1, 1, 280, 280 + RECOVERY_DAYS));
        let v = view(&p, "a", 280 + 5);
        assert_eq!(v["recovering"], true);
        assert_eq!(v["chance"], 0.0);
        let mut q = p.clone();
        assert!(!after_scene(&mut q, "a", 285, 10, 1));
        // Her bust goes back over six months, her belly in one.
        let bust = |d: i64| view(&p, "a", 280 + d)["bust"].as_f64().unwrap();
        let belly = |d: i64| view(&p, "a", 280 + d)["belly"].as_f64().unwrap();
        assert!((bust(0) - 0.5).abs() < 1e-6 && (bust(90) - 0.25).abs() < 1e-6 && bust(180) == 0.0);
        assert!((belly(0) - 1.0).abs() < 1e-6 && belly(30) == 0.0);
        // An old save without a term: forty weeks.
        assert_eq!(on_day(&json!({"preg": {"a": {"since": 0}}}), "a", 279).since, 0);
    }

    #[test]
    fn each_term_is_thirty_seven_to_forty_two_weeks() {
        let fertile = (0..CYCLE_DAYS).find(|&d| cycle_day("a", d) == 14).unwrap();
        let terms: Vec<i64> = (0..60).filter_map(|s| { let mut p = Preg::default(); after_scene(&mut p, "a", fertile, 10, s).then_some(p.term) }).collect();
        assert!(terms.len() > 20);
        assert!(terms.iter().all(|t| (TERM_MIN..=TERM_MAX).contains(t)));
        assert!(terms.iter().min() != terms.iter().max());
    }

    #[test]
    fn she_learns_once_and_is_sick_then_heavy() {
        let ext = json!({"preg": {"a": {"since": 0, "term": 280}}});
        let early = day(&json!({"girl": "a", "ext": ext.clone(), "day": 20})).unwrap();
        assert_eq!(early["learned"], false);
        let told = day(&json!({"girl": "a", "ext": ext, "day": 50})).unwrap();
        assert_eq!(told["learned"], true);
        assert_eq!(told["effects"].as_array().map_or(0, Vec::len), 1);
        let again = day(&json!({"girl": "a", "ext": told["ext"].clone(), "day": 51})).unwrap();
        assert_eq!(again["learned"], false);
        let v = |d: i64| view(&Preg { since: 0, term: 280, ..Preg::default() }, "a", d);
        assert_eq!(v(50)["sick"], true);
        assert!((1..=3).contains(&v(50)["sick_times"].as_i64().unwrap()));
        assert_eq!(v(120)["sick"], false);
        assert_eq!(v(200)["heavy"], true);
        let born = day(&json!({"girl": "a", "ext": again["ext"].clone(), "day": 290})).unwrap();
        assert_eq!(born["born"], true);
        assert_eq!(born["pregnancy"]["pregnant"], false);
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
