//! The one-on-one's lasting marks on her, after the original H scene (Heroine.HExperience, HSceneProc.EndProc and
//! CalcParameter, HSceneResult.OnClickEnd): how many times, her first kiss, her virginity front and back, and the five
//! area experiences (chest, crotch, anal, butt, nipples; index 0 is kissing) that make her 初めて, 不慣れ, 慣れ or 淫乱.
//! Kept per heroine in ext.hexp.<id>. Unreal counts what happened in the scene and asks; the level gates poses, raw
//! insertion and anal, and picks her voice bank.
use crate::effects::Effects;
use crate::relation::Relation;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

/// Area indices, as the original hAreaExps.
pub const KISS: usize = 0;
pub const CHEST: usize = 1;
pub const CROTCH: usize = 2;
pub const ANAL: usize = 3;
pub const BUTT: usize = 4;
pub const NIPPLE: usize = 5;
/// Climaxes in a day after which each one raises her libido (hexp libido_gain).
const LIBIDO_AFTER: i32 = 10;
const AREA_KEYS: [&str; 6] = ["kiss", "chest", "crotch", "anal", "butt", "nipple"];
/// The rest of her he touches and kisses (H_SCENE_ADDITIONS_PLAN 3, user 2026-11-03: each grows of its own), with what
/// her relation must be at least for a touch and for a kiss there (stage_index; developed past 30 one less).
pub const BODY_KEYS: [&str; 5] = ["head", "hand", "thigh", "calf", "foot"];
const BODY_NEED: [(i32, i32); 5] = [(0, 0), (0, 0), (1, 1), (0, 1), (1, 2)];
/// How deep (AlignDeep, 0..100) counts as all the way in: her top is 90 once that place is developed to 100.
const DEEPEST: f64 = 85.0;

/// What she has been through (Heroine's H fields).
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct HExp {
    pub count: i32,
    pub kissed: bool,
    pub areas: [f32; 6],
    /// The original's countKokanH and countAnalH: added to the crotch and anal areas only when judging her experience
    /// level (level()), never to her development (coordinator 2026-11-03, option A).
    pub crotch_h: f32,
    pub anal_h: f32,
    pub service: f32,
    pub service_count: i32,
    /// Her mouth's development, 0..100 (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md): ten points each time he comes in her mouth.
    pub oral: f32,
    pub raw_count: i32,
    pub virgin: bool,
    pub anal_virgin: bool,
    /// Her hymen was rebuilt at the clinic (clinic.rs hymen_restore, user 2026-11-03): she is not a virgin, but the next
    /// time he enters her she bleeds and it hurts as the first time; then it is broken again.
    pub hymen_restored: bool,
    /// The game day the today_* fields are for (-1 none): what she has had today carries from one scene to the next, so
    /// leaving the room and coming back does not undo "that is enough for today".
    pub today_day: i64,
    pub today_orgasms: i32,
    pub today_service: i32,
    pub today_anal_refused: bool,
    /// Libido she gained (one point for each climax past the tenth in a day, user 2026-11-01): added to her profile's
    /// traits.libido (the street passes it as profile.libido_gain).
    pub libido_gain: i32,
    /// Game minute until which his semen (white) and her blood (red) run out of her after a scene (-1 none; discharge).
    pub white_until: i64,
    pub red_until: i64,
    /// He has gone all the way into her vagina / anus once (counts.crotch.deepest past DEEPEST): a memory the first time.
    pub crotch_deep: bool,
    pub anal_deep: bool,
    /// The poses played with her (their shown names; H_SCENE_ADDITIONS_PLAN 5): the rest are marked New.
    pub poses: Vec<String>,
    /// Her head, hands, thighs, calves and feet, 0..100 (BODY_KEYS): half a point a second touched or kissed.
    pub body: std::collections::BTreeMap<String, f32>,
    /// How many times she has come in all, and where (user 2026-11-03): AREA_KEYS and BODY_KEYS, a climax from his touch
    /// or kiss there, crotch and anal with him in her too.
    pub orgasms: i32,
    pub climaxes: std::collections::BTreeMap<String, i32>,
    /// How many times they have had sex (a scene he was in her: vaginal, anal, either).
    pub sex_count: i32,
    pub vaginal_count: i32,
    pub anal_count: i32,
}

impl Default for HExp {
    fn default() -> Self {
        HExp { count: 0, kissed: false, areas: [0.0; 6], crotch_h: 0.0, anal_h: 0.0, service: 0.0, service_count: 0, oral: 0.0, raw_count: 0, virgin: true, anal_virgin: true, hymen_restored: false, today_day: -1, today_orgasms: 0, today_service: 0, today_anal_refused: false, libido_gain: 0, white_until: -1, red_until: -1, crotch_deep: false, anal_deep: false, poses: Vec::new(), body: Default::default(), orgasms: 0, climaxes: Default::default(), sex_count: 0, vaginal_count: 0, anal_count: 0 }
    }
}

impl HExp {
    /// An area's development, 0..100: ten points each climax there (H_DEVELOPMENT_EXPERIENCE_PLAN), the same number the
    /// scene shows and grows (OKHScene Dev()).
    pub fn area(&self, i: usize) -> f32 {
        self.areas[i].min(100.0)
    }
    /// An area as the original judges her experience level: crotch and anal count their intercourse too.
    fn judged(&self, i: usize) -> f32 {
        let extra = match i {
            CROTCH => self.crotch_h,
            ANAL => self.anal_h,
            _ => 0.0,
        };
        (self.areas[i] + extra).min(100.0)
    }
    /// 0 初めて, 1 不慣れ, 2 慣れ, 3 淫乱 (Heroine.HExperience): lewdness 100 wins only once she has done it.
    pub fn level(&self, lewdness: f32) -> i32 {
        if self.count == 0 {
            0
        } else if lewdness >= 100.0 {
            3
        } else if (CHEST..=NIPPLE).any(|i| self.judged(i) < 100.0) {
            1
        } else {
            2
        }
    }
}

/// The catalog's condom (the convenience store sells them; user 2026-11-03: none put on unless one of them has one).
pub const CONDOM: &str = "cv_condom";

/// How many condoms she has of her own (ext.items.owned, bought herself or given).
fn her_condoms(ext: &Value, girl: &str) -> usize {
    ext.get("items").and_then(|i| i.get("owned")).and_then(|o| o.get(girl)).and_then(Value::as_array).map_or(0, |a| a.iter().filter(|e| e.get("item").and_then(Value::as_str) == Some(CONDOM)).count())
}

pub fn of(ext: &Value, girl: &str) -> HExp {
    ext.get("hexp").and_then(|h| h.get(girl)).and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default()
}

/// Hours his semen (white) and her blood (red) run out of her after a scene with `raw` finishes inside her without a
/// condom and `condom` with one: past four, an hour and an hour more for each after; blood with the semen when she
/// `bleeds` (陰部脆弱 or her first time), and blood alone past four with a condom.
pub fn discharge_hours(raw: i64, condom: i64, bleeds: bool) -> (i64, i64) {
    const FREE: i64 = 4;
    let white = (raw - FREE).max(0);
    let red = (if bleeds { white } else { 0 }).max((condom - FREE).max(0));
    (white, red)
}

/// The original's diminishing ladder for each finish or climax in one scene: 15, 10, 5, then 1.
fn ladder(times: i64) -> f32 {
    (0..times.max(0)).map(|k| match k { 0 => 15.0, 1 => 10.0, 2 => 5.0, _ => 1.0 }).sum()
}

fn level_name(level: i32) -> &'static str {
    match level {
        0 => crate::tr::t("hexp.level_first"),
        1 => crate::tr::t("hexp.level_inexperienced"),
        2 => crate::tr::t("hexp.level_used"),
        _ => crate::tr::t("hexp.level_lewd"),
    }
}

/// How many times she wants to come for her desire for him: one per ten points (100 wants ten, 50 five).
pub fn climax_wanted(sex_desire: f32) -> i32 {
    (sex_desire.clamp(0.0, crate::relation::SEX_DESIRE_MAX) / 10.0).round() as i32
}

fn body_name(k: &str) -> &'static str {
    match k {
        "head" => crate::tr::t("hexp.area_head"),
        "hand" => crate::tr::t("hexp.area_hand"),
        "thigh" => crate::tr::t("hexp.area_thigh"),
        "calf" => crate::tr::t("hexp.area_calf"),
        _ => crate::tr::t("hexp.area_foot"),
    }
}

fn area_name(i: usize) -> &'static str {
    match i {
        KISS => crate::tr::t("hexp.area_kiss"),
        CHEST => crate::tr::t("hexp.area_chest"),
        CROTCH => crate::tr::t("hexp.area_crotch"),
        ANAL => crate::tr::t("hexp.area_anal"),
        BUTT => crate::tr::t("hexp.area_butt"),
        _ => crate::tr::t("hexp.area_nipple"),
    }
}

/// What the scene allows with her now. Request: girl, ext, relation. Answer: level (0..3) and its name, the five areas,
/// raw_ok (NamaInsertCheck without the calendar: 淫乱, or 慣れ with five raw times or as his lover), anal_chance
/// (hAreaExps[3]+countAnalH percent), kiss_ok (lover or already kissed), used (poses marked isExperience need 慣れ).
/// Her character moves each of these (the street has no calendar or H-scene favor of the original): a girl of low
/// chastity who is lewd lets him go raw sooner and is easier about anal, one who is drawn to him kisses before they
/// are lovers, one who resents him does not.
fn experience(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).ok_or("missing_field: girl")?;
    let rel: Option<Relation> = r.get("relation").filter(|v| v.is_object()).map(|v| serde_json::from_value(v.clone())).transpose().map_err(|e| format!("relation: {e}"))?;
    let lewd = rel.as_ref().map_or(0.0, |r| r.lewdness);
    let lover = rel.as_ref().is_some_and(|r| r.stage == "lover");
    let h = of(r.get("ext").unwrap_or(&Value::Null), girl);
    let level = h.level(lewd);
    let t = crate::traits::Traits::from_profile(r.get("profile").unwrap_or(&Value::Null));
    let chaste = rel.as_ref().map_or_else(|| crate::heroine::default_chastity(&t), |r| crate::heroine::chastity(r, &t));
    let attraction = rel.as_ref().map_or(0.0, |r| r.attraction);
    let resentment = rel.as_ref().map_or(0.0, |r| r.resentment);
    let easy = lewd / 100.0 + (50.0 - chaste) / 100.0; // about -0.45 (chaste, innocent) .. 1.45 (lewd, loose)
    let kiss_ok = lover || h.kissed || (resentment < 30.0 && attraction + 30.0 * easy >= 45.0 + 0.3 * chaste);
    let raw_ok = level == 3 || (level == 2 && (h.raw_count >= 5 || lover)) || (level >= 1 && easy >= 0.9) || (lover && level >= 1 && t.worship >= 70);
    let anal_chance = (h.area(ANAL) / 100.0 + 0.25 * easy).clamp(0.0, 1.0);
    // How many times in one scene she serves him to the end (hand, mouth, breasts) before she has had enough: more
    // as she gets used to it, is lewd and loose, or is his lover; once if she resents him.
    let service_rounds = if resentment >= 50.0 { 1 } else { (1 + level + (1.5 * easy).round() as i32 + i32::from(lover)).clamp(1, 6) };
    // How many times she comes in one scene before she has had enough and wants it to stop (no more touching, moving,
    // entering her): the same things move it, a lover lasts longer.
    // Her desire for him (sex_desire, 0..200) is how many times she wants to come: 100 wants ten, 50 five. She does
    // not have enough before that (a lewd girl left wanting stays frustrated and comes looking for him, `initiative`).
    let wanted = climax_wanted(rel.as_ref().map_or(0.0, |r| r.sex_desire));
    let climax_limit = if resentment >= 50.0 { 1 } else { (2 + level + (1.5 * easy).round() as i32 + 2 * i32::from(lover)).max(wanted).clamp(2, 10) };
    // Today so far (the request's game day): she starts this scene where the last one today left her.
    let day = r.get("day").and_then(Value::as_i64).unwrap_or(-1);
    let today = day >= 0 && h.today_day == day;
    let (today_orgasms, today_service, anal_refused_today) = if today { (h.today_orgasms, h.today_service, h.today_anal_refused) } else { (0, 0, false) };
    let preg = crate::pregnancy::on_day(r.get("ext").unwrap_or(&Value::Null), girl, day.max(0));
    let mut areas: serde_json::Map<String, Value> = AREA_KEYS.iter().enumerate().map(|(i, k)| (k.to_string(), json!(h.area(i)))).collect();
    areas.insert("oral".into(), json!(h.oral.min(100.0)));
    // What she lets him touch and kiss of the rest of her (and her lips: as close as a kiss).
    let stage = rel.as_ref().map_or(0, |r| r.stage_index());
    let mut touch_ok = serde_json::Map::new();
    for (i, k) in BODY_KEYS.iter().enumerate() {
        let d = h.body.get(*k).copied().unwrap_or(0.0).min(100.0);
        areas.insert(k.to_string(), json!(d));
        let less = i32::from(d >= 30.0);
        touch_ok.insert(k.to_string(), json!({"touch": stage >= BODY_NEED[i].0 - less, "kiss": stage >= BODY_NEED[i].1 - less}));
    }
    touch_ok.insert("lips".into(), json!({"touch": stage >= 1 - i32::from(h.area(KISS) >= 30.0), "kiss": kiss_ok}));
    Ok(json!({
        "touch_ok": touch_ok,
        // A rebuilt hymen plays as her first time in the scene (the insertion's pain, blood and reaction, OKHScene).
        "level": level, "level_name": level_name(level), "areas": areas, "count": h.count, "virgin": h.virgin || h.hymen_restored, "anal_virgin": h.anal_virgin,
        "hymen_restored": h.hymen_restored,
        "raw_ok": raw_ok,
        // Condoms of hers she can give him for it (his own are his bag's, the street adds them as his_condoms).
        "her_condoms": her_condoms(r.get("ext").unwrap_or(&Value::Null), girl),
        "anal_chance": anal_chance,
        "service_rounds": service_rounds,
        "climax_limit": climax_limit,
        "climax_wanted": wanted,
        // She resents him (resentment 50 or more): no anal whatever her experience (the scene asks nothing more of her).
        "resentful": resentment >= 50.0,
        "today_orgasms": today_orgasms,
        "today_service": today_service,
        "anal_refused_today": anal_refused_today,
        "had_enough": today_orgasms >= climax_limit,
        // Hooked on it (user, 2026-11-01: most heroines who keep coming get addicted to sex instead of wanting to go
        // home when tired): every girl but one who hates him (resentment 90 and up). Past her limit she is
        // worn out but cannot stop and begs for more.
        "addicted": resentment < 90.0,
        "libido_gain": h.libido_gain,
        "white_until": h.white_until,
        "red_until": h.red_until,
        "kiss_ok": kiss_ok,
        "chastity": chaste,
        "used": level >= 2,
        "kissed": h.kissed,
        "poses_played": h.poses,
        "orgasms": h.orgasms,
        "climaxes": h.climaxes,
        "sex_count": h.sex_count,
        "vaginal_count": h.vaginal_count,
        "anal_count": h.anal_count,
        "pregnancy": crate::pregnancy::view(&preg, girl, day.max(0)),
    }))
}

/// One one-on-one ended. Request: girl, ext, relation, place, counts {areas: {chest: seconds touched, ...}, kiss
/// (seconds), service_finishes, service (any service pose played), crotch {inserted, climaxes}, anal {inserted,
/// climaxes}, raw (inserted without a condom), her_orgasms, played (any pose at all)}. Answer: ext (ext.hexp.<girl>),
/// effects (the relation and her memories: the time itself, firsts, an area she got used to, a new level), level_before,
/// level_after, hexp.
fn session_end(r: &Value) -> Result<Value, String> {
    let girl = r.get("girl").and_then(Value::as_str).ok_or("missing_field: girl")?;
    let mut rel: Relation = serde_json::from_value(r.get("relation").cloned().ok_or("missing_field: relation")?).map_err(|e| format!("relation: {e}"))?;
    let place = r.get("place").and_then(Value::as_str).unwrap_or("");
    let mut ext = r.get("ext").cloned().filter(Value::is_object).unwrap_or_else(|| json!({}));
    let c = r.get("counts").cloned().unwrap_or_else(|| json!({}));
    let num = |v: &Value, k: &str| v.get(k).and_then(Value::as_f64).unwrap_or(0.0);
    let flag = |v: &Value, k: &str| v.get(k).and_then(Value::as_bool).unwrap_or(false);
    let before = rel.clone();
    let mut h = of(&ext, girl);
    // Her development as the player set it on the scene's left panel (user 2026-11-04): what this scene adds comes on top.
    if let Some(set) = c.get("dev_set").and_then(Value::as_object) {
        for (k, v) in set {
            let v = v.as_f64().unwrap_or(0.0).clamp(0.0, 100.0) as f32;
            if let Some(i) = AREA_KEYS.iter().position(|a| a == k) {
                h.areas[i] = v;
            } else if k == "oral" {
                h.oral = v;
            } else if BODY_KEYS.contains(&k.as_str()) {
                h.body.insert(k.clone(), v);
            }
        }
    }
    let was = h.clone();
    let level_before = h.level(rel.lewdness);
    let mut fx = Effects::default();
    // Today's tally (whatever was played): a new game day starts it again.
    if let Some(day) = r.get("day").and_then(Value::as_i64).filter(|d| *d >= 0) {
        if h.today_day != day {
            h.today_day = day;
            h.today_orgasms = 0;
            h.today_service = 0;
            h.today_anal_refused = false;
        }
        let before = h.today_orgasms;
        h.today_orgasms += num(&c, "her_orgasms") as i32;
        // Past ten climaxes in a day each one raises her libido a point.
        h.libido_gain = (h.libido_gain + (h.today_orgasms - before.max(LIBIDO_AFTER)).max(0)).min(100);
        h.today_service += num(&c, "service_finishes") as i32;
        h.today_anal_refused |= flag(&c, "anal_refused");
    }

    // What runs out of her afterwards (user, 2026-11-01): past four finishes inside her without a condom his semen, for
    // an hour of game time and an hour more for each one after that; her blood with it when she is 陰部脆弱
    // (traits.vagina_fragile), or it was her first time or her hymen grows back (traits.hymen_regen) unless it is
    // stretched (traits.hymen_stretched, KK_SkinEffects' card settings); past four with a condom only her blood, the
    // same way. Counted from the minute the scene ended; a longer run already going is kept.
    if let Some(now) = r.get("minute").and_then(Value::as_i64).filter(|m| *m >= 0) {
        let t = crate::traits::Traits::from_profile(r.get("profile").unwrap_or(&Value::Null));
        let inserted = flag(c.get("crotch").unwrap_or(&Value::Null), "inserted");
        let first = h.virgin && inserted;
        // A hymen rebuilt at the clinic bleeds whatever her card says about it being stretched.
        let rebuilt = h.hymen_restored && inserted;
        let bleeds = t.vagina_fragile || rebuilt || ((first || t.hymen_regen) && !t.hymen_stretched);
        let (white, red) = discharge_hours(num(&c, "his_inside_raw") as i64, num(&c, "his_condom") as i64, bleeds);
        if white > 0 { h.white_until = h.white_until.max(now + 60 * white); }
        if red > 0 { h.red_until = h.red_until.max(now + 60 * red); }
    }

    // Only what they did leaves a mark: opening the room and leaving at once is no intimate time.
    let played = flag(&c, "played");
    for pose in c.get("poses").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str) {
        if !h.poses.iter().any(|p| p == pose) {
            h.poses.push(pose.to_string());
        }
    }
    if played {
        fx.note_at(&rel.id, "intimacy", crate::tr::t("shop.private_room_time"), place, 0.9);
        rel.add_liking(5.0);
        rel.attraction = (rel.attraction + 5.0).min(100.0);
        rel.dependency = (rel.dependency + 3.0).min(100.0);
        // Touching: selectAreas*0.1 a scene in the original, where one scene caps at 100; here a second of touch is
        // worth half a point, so a long caress of one place is a big step and five scenes of it make her used to it.
        let areas = c.get("areas").cloned().unwrap_or_else(|| json!({}));
        for i in CHEST..=NIPPLE {
            let secs = num(&areas, AREA_KEYS[i]).clamp(0.0, 200.0) as f32;
            h.areas[i] = (h.areas[i] + secs * 0.5).min(100.0);
        }
        for k in BODY_KEYS {
            let secs = num(&areas, k).clamp(0.0, 200.0) as f32;
            if secs > 0.0 {
                let d = h.body.entry(k.to_string()).or_insert(0.0);
                *d = (*d + secs * 0.5).min(100.0);
            }
        }
        let kiss = num(&c, "kiss").max(num(&areas, "kiss")).clamp(0.0, 100.0) as f32;
        if kiss > 0.0 {
            h.areas[KISS] = (h.areas[KISS] + kiss).min(100.0);
            h.kissed = true;
        }
        let finishes = num(&c, "service_finishes") as i64;
        h.service = (h.service + ladder(finishes)).min(1000.0);
        if flag(&c, "service") || finishes > 0 {
            h.service_count = (h.service_count + 1).min(1000);
        }
        // Development (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md, user 2026-11-01): each climax with him in her vagina or
        // anus opens it ten points more; each time he comes in her mouth, her mouth ten.
        for (key, i) in [("crotch", CROTCH), ("anal", ANAL)] {
            let climaxes = num(c.get(key).unwrap_or(&Value::Null), "climaxes").clamp(0.0, 20.0) as f32;
            h.areas[i] = (h.areas[i] + 10.0 * climaxes).min(100.0);
        }
        h.oral = (h.oral + 10.0 * num(&c, "his_mouth").clamp(0.0, 20.0) as f32).min(100.0);
        for (key, slot, virgin) in [("crotch", &mut h.crotch_h, &mut h.virgin), ("anal", &mut h.anal_h, &mut h.anal_virgin)] {
            let part = c.get(key).cloned().unwrap_or_else(|| json!({}));
            if flag(&part, "inserted") {
                *slot = (*slot + 5.0 + ladder(num(&part, "climaxes") as i64)).min(1000.0);
                *virgin = false;
            }
        }
        if flag(c.get("crotch").unwrap_or(&Value::Null), "inserted") {
            h.hymen_restored = false;
        }
        if flag(&c, "raw") {
            h.raw_count = (h.raw_count + 1).min(1000);
        }
        // Her climaxes in all and where (counts.climax_areas: from his touch and kiss; crotch and anal add those with
        // him in her), and the times they had sex.
        h.orgasms = (h.orgasms + num(&c, "her_orgasms").clamp(0.0, 100.0) as i32).min(100_000);
        let by_touch = c.get("climax_areas").cloned().unwrap_or_else(|| json!({}));
        for k in AREA_KEYS.iter().chain(BODY_KEYS.iter()) {
            let inside = if *k == "crotch" || *k == "anal" { num(c.get(*k).unwrap_or(&Value::Null), "climaxes") } else { 0.0 };
            let n = (num(&by_touch, k) + inside).clamp(0.0, 100.0) as i32;
            if n > 0 {
                let e = h.climaxes.entry(k.to_string()).or_insert(0);
                *e = (*e + n).min(100_000);
            }
        }
        let (vaginal, anal) = (flag(c.get("crotch").unwrap_or(&Value::Null), "inserted"), flag(c.get("anal").unwrap_or(&Value::Null), "inserted"));
        h.vaginal_count += i32::from(vaginal);
        h.anal_count += i32::from(anal);
        h.sex_count += i32::from(vaginal || anal);
        h.count = (h.count + 1).min(10000);
        // Lewdness: the original's result table adds a few points a scene, more when she came; anal play adds to it.
        let orgasms = num(&c, "her_orgasms").clamp(0.0, 3.0) as f32;
        let anal = if flag(c.get("anal").unwrap_or(&Value::Null), "inserted") { 2.0 } else { 0.0 };
        rel.lewdness = (rel.lewdness + 2.0 + 3.0 * orgasms + anal).min(crate::talk::LEWDNESS_CAP);
        // Every climax he gave her warms her to him.
        let climaxes = num(&c, "her_orgasms").clamp(0.0, 20.0) as f32;
        if climaxes > 0.0 {
            rel.add_liking(1.5 * climaxes);
        }
        // Each climax satisfies ten points of her desire for him; what is left she still wants (frustrated).
        rel.sex_desire = (rel.sex_desire - 10.0 * climaxes).max(0.0);
        // Found touching herself on the street (her desire at 200, OKStreetSocialOnani.inl) and taken there: each time he
        // came in her without a condom fills her favor for him by her whole stage (user 2026-11-03: 中出好感度 +100%).
        if flag(&c, "street_onani") {
            let inside = num(&c, "his_inside_vagina_raw").clamp(0.0, 20.0) as f32;
            if inside > 0.0 {
                let cap = rel.favor_cap();
                rel.favor = (rel.favor + cap * inside).min(cap);
            }
        }
        // She said no to going without a condom and he did anyway: 1 to 5 favor (user 2026-11-04), by her chastity and her
        // character (a proud girl minds, one who worships him or is already lewd less so).
        if flag(&c, "raw_pressed") {
            let t = crate::traits::Traits::from_profile(r.get("profile").unwrap_or(&Value::Null));
            let chaste = crate::heroine::chastity(&rel, &t);
            let minds = (chaste - 40.0) / 10.0 + (t.self_esteem as f32 - 50.0) / 25.0 - (t.worship as f32 - 50.0) / 25.0 - rel.lewdness / 50.0;
            rel.favor = (rel.favor - (3.0 + minds).round().clamp(1.0, 5.0)).max(0.0);
            fx.note_at(&rel.id, "h_first", crate::tr::t("hexp.raw_pressed_upset"), place, 0.85);
        }
        // The whole time in one memory she can be asked about ("how many times did you come?").
        let int = |k: &str| crate::tr::a(&(num(&c, k) as i64).to_string());
        let poses = r.get("poses").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).collect::<Vec<_>>().join("、")).unwrap_or_default();
        let summary = crate::tr::m("hexp.session_summary", &[("orgasms", int("her_orgasms")), ("finishes", int("his_finishes")), ("inside", int("his_inside")), ("outside", int("his_outside")), ("mouth", int("his_mouth")), ("swallowed", int("swallowed")), ("poses", crate::tr::a(&poses))]);
        fx.note_at(&rel.id, "h_level", &summary, place, 0.9);
    }

    // Her memories of the firsts and of what changed in her.
    let mut first = |fx: &mut Effects, id: &'static str, importance: f32| fx.note_at(&rel.id, "h_first", crate::tr::t(id), place, importance);
    if was.count == 0 && h.count > 0 {
        first(&mut fx, "hexp.first_time", 1.0);
    }
    if was.virgin && !h.virgin {
        first(&mut fx, "hexp.lost_virginity", 1.0);
    }
    if was.hymen_restored && !h.hymen_restored {
        first(&mut fx, "hexp.restored_hymen_broken", 0.9);
    }
    if was.anal_virgin && !h.anal_virgin {
        first(&mut fx, "hexp.first_anal", 0.95);
    }
    if !was.kissed && h.kissed {
        first(&mut fx, "hexp.first_kiss", 0.95);
    }
    // The first time he went all the way in (the scene's deepest, AlignDeep: 90 once she is opened up).
    for (key, deep, id) in [("crotch", &mut h.crotch_deep, "hexp.first_deepest"), ("anal", &mut h.anal_deep, "hexp.first_deepest_anal")] {
        if played && !*deep && num(c.get(key).unwrap_or(&Value::Null), "deepest") >= DEEPEST {
            *deep = true;
            first(&mut fx, id, 0.8);
        }
    }
    // Each place past 30 (she starts to feel it), 60 (sensitive to him) and 100 (used to him), her mouth too
    // (H_DEVELOPMENT_EXPERIENCE_PLAN P3): only the highest crossed this time.
    let steps = [(100.0, "hexp.area_used_to", 0.7), (60.0, "hexp.area_sensitive", 0.6), (30.0, "hexp.area_feels", 0.5)];
    let body = |x: &HExp, k: &str| x.body.get(k).copied().unwrap_or(0.0).min(100.0);
    let places = (CHEST..=NIPPLE).map(|i| (was.area(i), h.area(i), area_name(i))).chain(std::iter::once((was.oral, h.oral, crate::tr::t("hexp.area_mouth"))))
        .chain(BODY_KEYS.iter().map(|k| (body(&was, k), body(&h, k), body_name(k))));
    for (before, after, name) in places {
        if let Some(&(_, id, importance)) = steps.iter().find(|&&(at, _, _)| before < at && after >= at) {
            fx.note_at(&rel.id, "h_area", &crate::tr::m(id, &[("area", crate::tr::a(name))]), place, importance);
        }
    }
    let level_after = h.level(rel.lewdness);
    // The result shown when the scene ends (HSceneResult): each place before and after, in the panel's order, as the scene
    // shows them (area(): development only), and the firsts of this time.
    let rows: Vec<Value> = [(KISS, "kiss"), (CHEST, "chest"), (NIPPLE, "nipple"), (BUTT, "butt"), (CROTCH, "crotch"), (ANAL, "anal")]
        .iter()
        .map(|&(i, key)| json!({"area": key, "name": area_name(i), "before": was.area(i).round(), "after": h.area(i).round()}))
        .chain(std::iter::once(json!({"area": "oral", "name": crate::tr::t("hexp.area_mouth"), "before": was.oral.round(), "after": h.oral.round()})))
        .chain(BODY_KEYS.iter().map(|k| json!({"area": k, "name": body_name(k), "before": body(&was, k).round(), "after": body(&h, k).round()})))
        .collect();
    let firsts: Vec<&str> = [
        (was.count == 0 && h.count > 0, "hexp.first_time"),
        (was.virgin && !h.virgin, "hexp.lost_virginity"),
        (was.hymen_restored && !h.hymen_restored, "hexp.restored_hymen_broken"),
        (was.anal_virgin && !h.anal_virgin, "hexp.first_anal"),
        (!was.kissed && h.kissed, "hexp.first_kiss"),
        (!was.crotch_deep && h.crotch_deep, "hexp.first_deepest"),
        (!was.anal_deep && h.anal_deep, "hexp.first_deepest_anal"),
    ]
    .iter()
    .filter(|(yes, _)| *yes)
    .map(|(_, id)| crate::tr::t(id))
    .collect();
    // Her pregnancy (pregnancy.rs): the days since the last scene first (a birth past term), then his finishes in her
    // vagina without a condom this time.
    let day = r.get("day").and_then(Value::as_i64).unwrap_or(-1);
    let mut preg = crate::pregnancy::on_day(&ext, girl, day.max(0));
    let seed = r.get("seed").and_then(Value::as_i64).unwrap_or(day * 7919 + h.count as i64) as i32;
    let conceived = crate::pregnancy::after_scene(&mut preg, girl, day, num(&c, "his_inside_vagina_raw") as i64, seed);
    if day >= 0 {
        crate::pregnancy::store(&mut ext, girl, &preg);
    }
    let pregnancy = crate::pregnancy::view(&preg, girl, day.max(0));
    // Her totals after this time (the result screen's line).
    let totals = json!({"orgasms": h.orgasms, "climaxes": h.climaxes, "sex_count": h.sex_count, "vaginal_count": h.vaginal_count, "anal_count": h.anal_count, "count": h.count});
    let result = json!({"areas": rows, "firsts": firsts, "level_before_name": level_name(level_before), "played": played, "pregnancy": pregnancy, "conceived": conceived, "totals": totals});
    if level_after != level_before && level_after > 0 {
        fx.note_at(&rel.id, "h_level", &crate::tr::m("hexp.level_changed", &[("level", crate::tr::a(level_name(level_after)))]), place, 0.85);
    }
    fx.relation(&rel, &before);
    if !ext.get("hexp").is_some_and(Value::is_object) {
        ext["hexp"] = json!({});
    }
    ext["hexp"][girl] = serde_json::to_value(&h).map_err(|e| e.to_string())?;
    // The condoms put on in the scene are used up: his from his bag (his_remove), hers from what she owns.
    let his_used = num(&c, "condoms_his").clamp(0.0, 50.0) as usize;
    let mut her_used = num(&c, "condoms_her").clamp(0.0, 50.0) as usize;
    if let Some(owned) = ext.get_mut("items").and_then(|i| i.get_mut("owned")).and_then(|o| o.get_mut(girl)).and_then(Value::as_array_mut) {
        owned.retain(|e| {
            let used = her_used > 0 && e.get("item").and_then(Value::as_str) == Some(CONDOM);
            her_used -= usize::from(used);
            !used
        });
    }
    Ok(json!({"ext": ext, "effects": fx.into_value(), "level_before": level_before, "level_after": level_after, "level_name": level_name(level_after), "hexp": h, "result": result, "his_remove": vec![CONDOM; his_used]}))
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    Some(match kind {
        "h_experience" => experience(r),
        "h_session_end" => session_end(r),
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rel(lewd: f32) -> Value {
        let mut r = Relation { id: "g".into(), ..Relation::default() };
        r.lewdness = lewd;
        r.stage = "friend".into();
        serde_json::to_value(r).unwrap()
    }

    #[test]
    fn first_session_takes_her_virginity_and_makes_her_inexperienced() {
        let out = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": {}, "counts": {"played": true, "crotch": {"inserted": true, "climaxes": 1}, "kiss": 12, "her_orgasms": 1}})).unwrap();
        assert_eq!(out["level_before"], 0);
        assert_eq!(out["level_after"], 1);
        let h = &out["ext"]["hexp"]["g"];
        assert_eq!(h["virgin"], false);
        assert_eq!(h["anal_virgin"], true);
        assert_eq!(h["crotch_h"], 20.0);
        assert_eq!(h["kissed"], true);
        let notes: Vec<&str> = out["effects"].as_array().unwrap().iter().filter_map(|e| e.get("act").and_then(Value::as_str)).collect();
        assert!(notes.iter().filter(|a| **a == "h_first").count() >= 3, "first time, virginity, kiss: {notes:?}");
    }

    #[test]
    fn her_climaxes_by_place_and_the_times_they_had_sex_add_up() {
        let ext = json!({"hexp": {"g": {"count": 2, "virgin": false, "orgasms": 3, "climaxes": {"crotch": 2, "chest": 1}, "sex_count": 1, "vaginal_count": 1}}});
        let counts = json!({"played": true, "her_orgasms": 4, "climax_areas": {"chest": 1, "kiss": 1}, "crotch": {"inserted": true, "climaxes": 2}, "anal": {"inserted": true, "climaxes": 0}});
        let out = session_end(&json!({"girl": "g", "relation": rel(10.0), "ext": ext, "counts": counts})).unwrap();
        let h = &out["hexp"];
        assert_eq!(h["orgasms"], 7);
        assert_eq!(h["climaxes"], json!({"chest": 2, "crotch": 4, "kiss": 1}));
        assert_eq!((h["sex_count"].as_i64(), h["vaginal_count"].as_i64(), h["anal_count"].as_i64()), (Some(2), Some(2), Some(1)));
        assert_eq!(out["result"]["totals"]["sex_count"], 2);
        let e = experience(&json!({"girl": "g", "relation": rel(10.0), "ext": out["ext"]})).unwrap();
        assert_eq!((e["orgasms"].as_i64(), e["climaxes"]["crotch"].as_i64(), e["sex_count"].as_i64()), (Some(7), Some(4), Some(2)));
        // Only caressed: she came, but they did not have sex.
        let out = session_end(&json!({"girl": "g", "relation": rel(10.0), "ext": out["ext"], "counts": {"played": true, "her_orgasms": 1, "climax_areas": {"nipple": 1}}})).unwrap();
        assert_eq!((out["hexp"]["sex_count"].as_i64(), out["hexp"]["climaxes"]["nipple"].as_i64()), (Some(2), Some(1)));
    }

    #[test]
    fn development_set_on_the_panel_is_kept_with_what_the_scene_adds() {
        let ext = json!({"hexp": {"g": {"count": 1, "areas": [0, 0, 30, 0, 0, 0]}}});
        let out = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": ext, "counts": {"played": false,
            "dev_set": {"crotch": 80, "oral": 55, "foot": 40, "nothing": 9, "chest": 300}}})).unwrap();
        let h: HExp = serde_json::from_value(out["ext"]["hexp"]["g"].clone()).unwrap();
        assert_eq!((h.areas[CROTCH], h.areas[1], h.oral, h.body["foot"]), (80.0, 100.0, 55.0, 40.0));
    }

    #[test]
    fn climaxes_in_her_and_his_mouth_develop_her() {
        let ext = json!({"hexp": {"g": {"count": 1, "areas": [0, 0, 30, 95, 0, 0], "oral": 40}}});
        let out = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": ext, "counts": {"played": true,
            "crotch": {"inserted": true, "climaxes": 2}, "anal": {"inserted": true, "climaxes": 1}, "his_mouth": 3}})).unwrap();
        let h: HExp = serde_json::from_value(out["ext"]["hexp"]["g"].clone()).unwrap();
        assert_eq!(h.areas[CROTCH], 50.0);
        assert_eq!(h.areas[ANAL], 100.0);
        assert_eq!(h.oral, 70.0);
        // Her anal past 100 and her mouth past 60 are remembered; her crotch (30 -> 50, its intercourse not counted) crosses none.
        let areas = out["effects"].as_array().unwrap().iter().filter(|e| e.get("act").and_then(Value::as_str) == Some("h_area")).count();
        assert_eq!(areas, 2);
        let e = experience(&json!({"girl": "g", "relation": rel(0.0), "ext": out["ext"]})).unwrap();
        assert_eq!(e["areas"]["oral"], json!(70.0));
    }

    #[test]
    fn the_result_shows_each_place_as_the_scene_does() {
        let ext = json!({"hexp": {"g": {"count": 1, "virgin": false, "areas": [0, 0, 20, 0, 0, 0], "crotch_h": 30}}});
        let out = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": ext, "counts": {"played": true}})).unwrap();
        let crotch = out["result"]["areas"].as_array().unwrap().iter().find(|a| a["area"] == "crotch").unwrap().clone();
        assert_eq!(crotch["before"], json!(20.0), "development only, as the scene's panel and experience() show (not the 30 intercourse)");
        let e = experience(&json!({"girl": "g", "relation": rel(0.0), "ext": ext})).unwrap();
        assert_eq!(e["areas"]["crotch"], json!(20.0));
    }

    #[test]
    fn the_first_time_all_the_way_in_is_remembered_once() {
        let deep = |ext: Value, d: f64| session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": ext, "counts": {"played": true,
            "crotch": {"inserted": true, "deepest": d}}})).unwrap();
        let firsts = |out: &Value| out["result"]["firsts"].as_array().unwrap().len();
        let shallow = deep(json!({"hexp": {"g": {"count": 1, "virgin": false}}}), 70.0);
        assert_eq!(firsts(&shallow), 0);
        let all_in = deep(shallow["ext"].clone(), 90.0);
        assert_eq!(firsts(&all_in), 1);
        assert!(all_in["ext"]["hexp"]["g"]["crotch_deep"].as_bool().unwrap());
        assert_eq!(firsts(&deep(all_in["ext"].clone(), 90.0)), 0, "only the first time");
    }

    #[test]
    fn all_five_areas_at_100_make_her_used_to_it_and_lewdness_100_lewd() {
        let ext = json!({"hexp": {"g": {"count": 3, "areas": [50, 99, 100, 100, 100, 100], "kissed": true}}});
        let secs = json!({"chest": 10});
        let out = session_end(&json!({"girl": "g", "relation": rel(10.0), "ext": ext, "counts": {"played": true, "areas": secs}})).unwrap();
        assert_eq!(out["level_before"], 1);
        assert_eq!(out["level_after"], 2);
        let h: HExp = serde_json::from_value(out["ext"]["hexp"]["g"].clone()).unwrap();
        assert_eq!(h.level(100.0), 3);
        assert_eq!(HExp::default().level(100.0), 0, "never done it: 初めて whatever her lewdness");
    }

    #[test]
    fn climaxes_warm_her_and_a_chaste_girl_minds_being_pressed_raw() {
        let base = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": {}, "counts": {"played": true}})).unwrap();
        let warm = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": {}, "counts": {"played": true, "her_orgasms": 3}})).unwrap();
        let favor = |o: &Value| o["effects"].as_array().unwrap().iter().find(|e| e["op"] == "relation").map(|e| e["set"]["favor"].as_f64().unwrap_or(0.0)).unwrap_or(0.0);
        assert!(favor(&warm) > favor(&base), "three climaxes: {} vs {}", favor(&warm), favor(&base));
        let mut chaste: Relation = serde_json::from_value(rel(0.0)).unwrap();
        chaste.chastity = 90.0;
        chaste.favor = 50.0;
        let pressed = session_end(&json!({"girl": "g", "relation": chaste, "ext": {}, "counts": {"played": true, "raw_pressed": true}})).unwrap();
        let mut easy: Relation = serde_json::from_value(rel(0.0)).unwrap();
        easy.chastity = 10.0;
        easy.favor = 50.0;
        let fine = session_end(&json!({"girl": "g", "relation": easy, "ext": {}, "counts": {"played": true, "raw_pressed": true}})).unwrap();
        assert!(favor(&pressed) < favor(&fine), "chaste {} vs easy {}", favor(&pressed), favor(&fine));
        let unpressed: Relation = { let mut r: Relation = serde_json::from_value(rel(0.0)).unwrap(); r.chastity = 90.0; r.favor = 50.0; r };
        let plain = favor(&session_end(&json!({"girl": "g", "relation": unpressed, "ext": {}, "counts": {"played": true}})).unwrap());
        assert_eq!(plain - favor(&pressed), 5.0, "a chaste girl minds the most");
        let mut lewd: Relation = serde_json::from_value(rel(0.0)).unwrap();
        lewd.chastity = 0.0;
        lewd.lewdness = 400.0;
        lewd.favor = 50.0;
        let cost = favor(&session_end(&json!({"girl": "g", "relation": lewd.clone(), "ext": {}, "counts": {"played": true}})).unwrap()) - favor(&session_end(&json!({"girl": "g", "relation": lewd, "ext": {}, "counts": {"played": true, "raw_pressed": true}})).unwrap());
        assert_eq!(cost, 1.0, "it always costs her something");
    }

    #[test]
    fn her_character_moves_kiss_raw_and_anal() {
        let mut shy: Relation = serde_json::from_value(rel(0.0)).unwrap();
        shy.chastity = 85.0;
        shy.attraction = 50.0;
        let mut loose: Relation = serde_json::from_value(rel(60.0)).unwrap();
        loose.chastity = 15.0;
        loose.attraction = 50.0;
        let ext = json!({"hexp": {"g": {"count": 1, "virgin": false}}});
        let a = experience(&json!({"girl": "g", "relation": shy, "ext": ext})).unwrap();
        let b = experience(&json!({"girl": "g", "relation": loose, "ext": ext})).unwrap();
        assert_eq!(a["kiss_ok"], false);
        assert_eq!(b["kiss_ok"], true);
        assert_eq!(a["raw_ok"], false);
        assert_eq!(b["raw_ok"], true);
        assert!(b["anal_chance"].as_f64().unwrap() > a["anal_chance"].as_f64().unwrap());
        assert!(b["service_rounds"].as_i64().unwrap() > a["service_rounds"].as_i64().unwrap());
        assert!(a["service_rounds"].as_i64().unwrap() >= 1);
        assert!(b["climax_limit"].as_i64().unwrap() > a["climax_limit"].as_i64().unwrap());
        assert!(a["climax_limit"].as_i64().unwrap() >= 2);
        let mut sore = loose.clone();
        sore.resentment = 60.0;
        let c = experience(&json!({"girl": "g", "relation": sore, "ext": ext})).unwrap();
        assert_eq!(c["resentful"], true);
        assert_eq!(c["climax_limit"], 1);
        assert_eq!(b["resentful"], false);
    }

    #[test]
    fn her_desire_is_how_many_times_she_wants_to_come() {
        let mut keen: Relation = serde_json::from_value(rel(0.0)).unwrap();
        keen.sex_desire = 100.0;
        let mut half = keen.clone();
        half.sex_desire = 50.0;
        let ext = json!({"hexp": {"g": {"count": 1, "virgin": false}}});
        let a = experience(&json!({"girl": "g", "relation": keen, "ext": ext})).unwrap();
        let b = experience(&json!({"girl": "g", "relation": half, "ext": ext})).unwrap();
        assert_eq!(a["climax_wanted"], 10);
        assert_eq!(a["climax_limit"], 10);
        assert_eq!(b["climax_wanted"], 5);
        assert!(b["climax_limit"].as_i64().unwrap() >= 5);
        // Three climaxes satisfy thirty points: twenty are left (two more she wants).
        let out = session_end(&json!({"girl": "g", "relation": half, "ext": {}, "counts": {"played": true, "her_orgasms": 3}})).unwrap();
        let desire = out["effects"].as_array().unwrap().iter().find(|e| e["op"] == "relation").map(|e| e["set"]["sex_desire"].as_f64().unwrap_or(-1.0)).unwrap_or(-1.0);
        assert!((desire - 20.0).abs() < 0.01, "desire left {desire}");
    }

    #[test]
    fn what_she_had_today_carries_to_the_next_scene_that_day() {
        let r = rel(0.0);
        let first = session_end(&json!({"girl": "g", "relation": r, "ext": {}, "day": 3, "counts": {"played": true, "her_orgasms": 3, "service_finishes": 1, "anal_refused": true}})).unwrap();
        let e = experience(&json!({"girl": "g", "relation": r, "ext": first["ext"], "day": 3})).unwrap();
        assert_eq!(e["today_orgasms"], 3);
        assert_eq!(e["today_service"], 1);
        assert_eq!(e["anal_refused_today"], true);
        assert_eq!(e["had_enough"], e["climax_limit"].as_i64().unwrap() <= 3);
        let again = session_end(&json!({"girl": "g", "relation": r, "ext": first["ext"], "day": 3, "counts": {"played": true, "her_orgasms": 2}})).unwrap();
        assert_eq!(experience(&json!({"girl": "g", "relation": r, "ext": again["ext"], "day": 3})).unwrap()["today_orgasms"], 5);
        let tomorrow = experience(&json!({"girl": "g", "relation": r, "ext": again["ext"], "day": 4})).unwrap();
        assert_eq!(tomorrow["today_orgasms"], 0);
        assert_eq!(tomorrow["anal_refused_today"], false);
    }

    #[test]
    fn past_four_finishes_she_runs_white_or_red_for_hours() {
        assert_eq!(discharge_hours(4, 0, true), (0, 0), "four is not past four");
        assert_eq!(discharge_hours(5, 0, false), (1, 0));
        assert_eq!(discharge_hours(7, 0, false), (3, 0), "an hour more for each after");
        assert_eq!(discharge_hours(6, 0, true), (2, 2), "fragile or her first time: blood with it");
        assert_eq!(discharge_hours(0, 6, false), (0, 2), "with a condom only blood");
        let r = rel(0.0);
        let out = session_end(&json!({"girl": "g", "relation": r, "ext": {}, "day": 3, "minute": 600,
            "profile": {"traits": {"vagina_fragile": true}}, "counts": {"played": true, "his_inside_raw": 6}})).unwrap();
        assert_eq!(out["ext"]["hexp"]["g"]["white_until"], 720);
        assert_eq!(out["ext"]["hexp"]["g"]["red_until"], 720);
        let after = session_end(&json!({"girl": "g", "relation": r, "ext": out["ext"], "day": 3, "minute": 650, "counts": {"played": true, "his_inside_raw": 5}})).unwrap();
        assert_eq!(after["ext"]["hexp"]["g"]["white_until"], 720, "a longer run already going is kept");
    }

    #[test]
    fn climaxes_past_ten_a_day_raise_her_libido() {
        let r = rel(0.0);
        let first = session_end(&json!({"girl": "g", "relation": r, "ext": {}, "day": 3, "counts": {"played": true, "her_orgasms": 8}})).unwrap();
        assert_eq!(first["ext"]["hexp"]["g"]["libido_gain"], 0);
        let again = session_end(&json!({"girl": "g", "relation": r, "ext": first["ext"], "day": 3, "counts": {"played": true, "her_orgasms": 5}})).unwrap();
        assert_eq!(again["ext"]["hexp"]["g"]["libido_gain"], 3, "the 11th, 12th and 13th of the day");
        let next_day = session_end(&json!({"girl": "g", "relation": r, "ext": again["ext"], "day": 4, "counts": {"played": true, "her_orgasms": 4}})).unwrap();
        assert_eq!(next_day["ext"]["hexp"]["g"]["libido_gain"], 3, "kept; a new day counts from zero");
        assert_eq!(experience(&json!({"girl": "g", "relation": r, "ext": next_day["ext"], "day": 4})).unwrap()["libido_gain"], 3);
    }

    #[test]
    fn condoms_put_on_are_used_up_his_and_hers() {
        let ext = json!({"items": {"owned": {"g": [{"item": "cv_condom", "from": "own", "day": 1}, {"item": "cv_tea", "from": "own", "day": 1}, {"item": "cv_condom", "from": "own", "day": 2}]}}});
        let e = experience(&json!({"girl": "g", "relation": rel(0.0), "ext": ext})).unwrap();
        assert_eq!(e["her_condoms"], 2);
        let out = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": ext, "counts": {"played": true, "condoms_his": 2, "condoms_her": 1}})).unwrap();
        assert_eq!(out["his_remove"], json!(["cv_condom", "cv_condom"]));
        let left: Vec<&str> = out["ext"]["items"]["owned"]["g"].as_array().unwrap().iter().filter_map(|e| e["item"].as_str()).collect();
        assert_eq!(left, ["cv_tea", "cv_condom"]);
        assert_eq!(experience(&json!({"girl": "g", "relation": rel(0.0), "ext": out["ext"]})).unwrap()["her_condoms"], 1);
    }

    #[test]
    fn nothing_played_changes_no_experience() {
        let out = session_end(&json!({"girl": "g", "relation": rel(0.0), "ext": {}, "counts": {}})).unwrap();
        assert_eq!(out["ext"]["hexp"]["g"]["count"], 0);
        assert_eq!(out["level_after"], 0);
    }

    #[test]
    fn raw_and_anal_follow_experience() {
        let e = experience(&json!({"girl": "g", "relation": rel(0.0), "ext": {"hexp": {"g": {"count": 1, "anal_h": 30, "areas": [0, 0, 0, 50, 0, 0]}}}})).unwrap();
        assert_eq!(e["raw_ok"], false);
        assert!((e["anal_chance"].as_f64().unwrap() - 0.5).abs() < 1e-6, "her anal development 50; its intercourse (anal_h) only judges her level");
        assert_eq!(e["kiss_ok"], false);
        assert_eq!(ladder(5), 32.0);
    }
}
