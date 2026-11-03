//! Edge cases of her H experience and pregnancy seen in play (Docs/ONEONE_PERFECTION_CHECKLIST.md), through the
//! modules' public calls only: a stranger, one who hates him, a lover, desire past what one scene allows, and many
//! finishes inside on a fertile day.
#[cfg(test)]
mod tests {
    use crate::relation::Relation;
    use serde_json::{json, Value};

    fn rel(stage: &str, f: impl FnOnce(&mut Relation)) -> Value {
        let mut r = Relation { id: "g".into(), stage: stage.into(), ..Relation::default() };
        f(&mut r);
        serde_json::to_value(r).unwrap()
    }

    fn experience(relation: Value, ext: Value) -> Value {
        crate::hexp::eval("h_experience", &json!({"girl": "g", "relation": relation, "ext": ext})).unwrap().unwrap()
    }

    #[test]
    fn a_stranger_never_touched_is_a_virgin_who_wants_a_condom_and_no_kiss() {
        let e = experience(rel("stranger", |r| r.chastity = 60.0), json!({}));
        assert_eq!(e["virgin"], true);
        assert_eq!(e["level"], 0);
        assert_eq!(e["raw_ok"], false);
        assert_eq!(e["kiss_ok"], false);
        assert_eq!(e["used"], false);
        assert_eq!(e["had_enough"], false);
        assert!(e["anal_chance"].as_f64().unwrap() < 0.1, "{}", e["anal_chance"]);
    }

    #[test]
    fn only_one_who_hates_him_is_not_hooked_and_serves_him_once() {
        let ext = json!({"hexp": {"g": {"count": 3, "virgin": false}}});
        let sore = experience(rel("friend", |r| r.resentment = 60.0), ext.clone());
        assert_eq!(sore["resentful"], true);
        assert_eq!(sore["service_rounds"], 1);
        assert_eq!(sore["climax_limit"], 1);
        assert_eq!(sore["addicted"], true, "below 90 she is still hooked (user, 2026-11-01)");
        let hates = experience(rel("friend", |r| r.resentment = 90.0), ext);
        assert_eq!(hates["addicted"], false);
    }

    #[test]
    fn his_lover_kisses_him_however_chaste_she_is() {
        let ext = json!({"hexp": {"g": {"count": 1, "virgin": false}}});
        let friend = experience(rel("friend", |r| r.chastity = 90.0), ext.clone());
        let lover = experience(rel("lover", |r| r.chastity = 90.0), ext);
        assert_eq!(friend["kiss_ok"], false);
        assert_eq!(lover["kiss_ok"], true);
        assert!(lover["climax_limit"].as_i64().unwrap() > friend["climax_limit"].as_i64().unwrap());
    }

    #[test]
    fn desire_past_one_hundred_wants_more_than_one_scene_allows() {
        // 胡桃 at desire 126 (2026-11-03 play): she wants thirteen, a scene stops counting at ten.
        let e = experience(rel("stranger", |r| r.sex_desire = 126.0), json!({}));
        assert_eq!(e["climax_wanted"], 13);
        assert_eq!(e["climax_limit"], 10);
    }

    #[test]
    fn each_finish_inside_on_a_fertile_day_is_its_own_chance() {
        let fertile = (0..28).find(|&d| crate::pregnancy::chance("g", d) >= 0.5).expect("a fertile day in the cycle");
        let barren = (0..28).find(|&d| crate::pregnancy::chance("g", d) == 0.0).expect("a day she cannot conceive");
        let conceived = |day: i64, inside: i64| (0..200).filter(|&seed| crate::pregnancy::after_scene(&mut crate::pregnancy::Preg::default(), "g", day, inside, seed)).count();
        assert_eq!(conceived(fertile, 0), 0, "no finish inside, no pregnancy");
        assert_eq!(conceived(barren, 10), 0, "outside her window nothing takes");
        let once = conceived(fertile, 1);
        let thrice = conceived(fertile, 3);
        assert!((70..=130).contains(&once), "one finish at one in two: {once}/200");
        assert!(thrice > once && thrice >= 160, "three finishes: {thrice}/200 against {once}");
    }
}
