//! The catalogue (Content/IndependentResources/StreetSocialData/catalog.json): opening hours, what each place sells and
//! the jobs, and the money rules that read it: whether a place is open, her taste for an item, what she orders when
//! she eats out alone, who wants to pay a bill, and how a gift lands.
use crate::rng::RandomStream;
use serde_json::{json, Value};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Default)]
pub struct Place {
    /// Hour ranges; "to" may pass 24 (overnight).
    pub open: Vec<(f64, f64)>,
    pub weekend_open: Vec<(f64, f64)>,
    /// Monday 0.
    pub closed_weekdays: Vec<i32>,
    /// Admission (yuan), and the student price when there is one (0: none).
    pub entry: i64,
    pub entry_student: i64,
}

#[derive(Debug, Clone, Default)]
pub struct Item {
    pub id: String,
    pub place: String,
    pub name: String,
    pub category: String,
    /// size ("" for one size, or M/L/S) -> price
    pub price: BTreeMap<String, i32>,
    pub season: Vec<i32>,
    pub tags: Vec<String>,
    pub options: Vec<String>,
    pub effects: BTreeMap<String, f32>,
    pub giftable: bool,
    pub consumable: bool,
    /// The floor of a building it is sold on (the department store: 9F food court, 10F view restaurant); 0: anywhere there.
    pub floor: i32,
}

impl Item {
    pub fn price_of(&self, size: &str) -> i32 {
        self.price.get(size).copied().unwrap_or_else(|| self.price.values().copied().min().unwrap_or(0))
    }

    /// One size, else M, else the first.
    pub fn default_size(&self) -> String {
        if self.price.contains_key("") {
            String::new()
        } else if self.price.contains_key("M") {
            "M".into()
        } else {
            self.price.keys().next().cloned().unwrap_or_default()
        }
    }
}

/// A weekday in the data: a name ("mon" .. "sun"; which day is plain to whoever writes it) or a number (0 = Monday).
pub fn weekday_of(v: &Value) -> Option<i32> {
    if let Some(n) = v.as_i64() {
        return Some(n as i32);
    }
    ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].iter().position(|d| v.as_str().is_some_and(|s| s.eq_ignore_ascii_case(d))).map(|k| k as i32)
}

#[derive(Debug, Clone, Default)]
pub struct Catalog {
    pub places: BTreeMap<String, Place>,
    pub items: Vec<Item>,
    /// Job id -> (place, wage).
    pub jobs: BTreeMap<String, (String, i32)>,
}

fn ranges(o: &Value, k: &str) -> Vec<(f64, f64)> {
    o.get(k).and_then(Value::as_array).map(|a| a.iter().filter_map(|r| r.as_array().filter(|r| r.len() == 2).map(|r| (r[0].as_f64().unwrap_or(0.0), r[1].as_f64().unwrap_or(0.0)))).collect()).unwrap_or_default()
}

fn strings(o: &Value, k: &str) -> Vec<String> {
    o.get(k).and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_str).map(String::from).collect()).unwrap_or_default()
}

impl Catalog {
    pub fn parse(root: &Value) -> Catalog {
        let mut c = Catalog::default();
        for (id, o) in root.get("places").and_then(Value::as_object).into_iter().flatten() {
            c.places.insert(
                id.clone(),
                Place {
                    open: ranges(o, "open"),
                    weekend_open: ranges(o, "weekend_open"),
                    closed_weekdays: o.get("closed_weekdays").and_then(Value::as_array).map(|a| a.iter().filter_map(weekday_of).collect()).unwrap_or_default(),
                    entry: o.get("entry").and_then(Value::as_i64).unwrap_or(0),
                    entry_student: o.get("entry_student").and_then(Value::as_i64).unwrap_or(0),
                },
            );
        }
        for o in root.get("items").and_then(Value::as_array).into_iter().flatten() {
            let s = |k: &str| o.get(k).and_then(Value::as_str).unwrap_or("").to_string();
            let item = Item {
                id: s("id"),
                place: s("place"),
                name: s("name"),
                category: s("category"),
                price: o.get("price").and_then(Value::as_object).map(|m| m.iter().filter_map(|(k, v)| v.as_f64().map(|p| (k.clone(), p as i32))).collect()).unwrap_or_default(),
                season: o.get("season").and_then(Value::as_array).map(|a| a.iter().filter_map(Value::as_i64).map(|m| m as i32).collect()).unwrap_or_default(),
                tags: strings(o, "tags"),
                options: strings(o, "options"),
                effects: o.get("effects").and_then(Value::as_object).map(|m| m.iter().filter_map(|(k, v)| v.as_f64().map(|e| (k.clone(), e as f32))).collect()).unwrap_or_default(),
                giftable: o.get("giftable").and_then(Value::as_bool).unwrap_or(false),
                consumable: o.get("consumable").and_then(Value::as_bool).unwrap_or(true),
                floor: o.get("floor").and_then(Value::as_i64).unwrap_or(0) as i32,
            };
            if !item.id.is_empty() && !item.price.is_empty() {
                c.items.push(item);
            }
        }
        for o in root.get("jobs").and_then(Value::as_array).into_iter().flatten() {
            let id = o.get("id").and_then(Value::as_str).unwrap_or("").to_string();
            if !id.is_empty() {
                c.jobs.insert(id, (o.get("place").and_then(Value::as_str).unwrap_or("").to_string(), o.get("wage").and_then(Value::as_f64).unwrap_or(95.0) as i32));
            }
        }
        c
    }

    /// Places missing from the catalogue are always open.
    pub fn place_open(&self, place: &str, hours: f64, weekday: i32) -> bool {
        let Some(p) = self.places.get(place) else { return true };
        if p.closed_weekdays.contains(&weekday) {
            return false;
        }
        let r = if weekday >= 5 && !p.weekend_open.is_empty() { &p.weekend_open } else { &p.open };
        r.iter().any(|(from, to)| (hours >= *from && hours < *to) || (*to > 24.0 && hours < to - 24.0)) || r.is_empty()
    }

    /// Why it is closed, in words: the hours of that day (a weekend has its own: the cafeteria opens 11-14 on Saturday,
    /// not 7-19), or a day it does not open at all.
    pub fn closed_why(&self, place: &str, weekday: i32) -> String {
        let Some(p) = self.places.get(place) else { return crate::tr::t("catalog.closed_now").to_string() };
        if p.closed_weekdays.contains(&weekday) {
            // Its day off by name ("closed every Monday"): the job panel says it of tomorrow, where "closed today" was wrong.
            let day = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].get(weekday as usize).copied().unwrap_or("mon");
            return crate::tr::m("catalog.closed_weekday", &[("weekday", crate::tr::a(crate::tr::lookup(&format!("series.{day}"), day)))]);
        }
        let weekend = weekday >= 5 && !p.weekend_open.is_empty();
        let hours = if weekend { &p.weekend_open } else { &p.open };
        match hours.first() {
            Some((from, to)) => crate::tr::m(if weekend { "catalog.closed_now_weekend_hours" } else { "catalog.closed_now_hours" }, &[("from", crate::tr::a(&fmt_g(*from))), ("to", crate::tr::a(&fmt_g(*to)))]),
            None => crate::tr::t("catalog.closed_now").to_string(),
        }
    }

    pub fn items_at(&self, place: &str, month: i32) -> Vec<&Item> {
        self.items.iter().filter(|i| i.place == place && (i.season.is_empty() || i.season.contains(&month))).collect()
    }

    pub fn find(&self, id: &str) -> Option<&Item> {
        self.items.iter().find(|i| i.id == id)
    }
}

/// %g for an hour like 10 or 21.5.
fn fmt_g(v: f64) -> String {
    if v.fract() == 0.0 {
        format!("{}", v as i64)
    } else {
        format!("{v}")
    }
}

/// The five sweetness levels a drink is made at (the shop's own words, zh-TW): 0%, 10%, 30%, 50%, 100%.
pub const SUGAR_LEVELS: [&str; 5] = ["無糖", "微糖", "少糖", "半糖", "全糖"];
/// The ice levels, and warm or hot for a drink whose options list "hot" (teas and milk teas, not juice).
pub const ICE_LEVELS: [&str; 7] = ["無冰", "微冰", "少冰", "半冰", "全冰", "溫", "熱"];

/// A sweetness however it was said ("半糖去冰" from the model, "50%", "half sugar", the old "正常"), as one of
/// SUGAR_LEVELS; "" when none is named.
pub fn sugar_of(said: &str) -> &'static str {
    let s = said.to_lowercase();
    let words: [(&[&str], usize); 5] = [
        (&["無糖", "无糖", "去糖", "不加糖", "no sugar", "sugar-free", "sugar free", "zero sugar"], 0),
        (&["微糖", "一分糖", "light sugar", "slightly sweet"], 1),
        (&["少糖", "三分糖", "less sugar", "low sugar"], 2),
        (&["半糖", "五分糖", "half sugar", "half sweet"], 3),
        (&["全糖", "正常糖", "標準糖", "标准糖", "正常甜", "full sugar", "regular sugar", "normal sugar"], 4),
    ];
    for (keys, level) in words {
        if keys.iter().any(|k| s.contains(k)) {
            return SUGAR_LEVELS[level];
        }
    }
    // Percentages, longest first ("100%" also holds "0%").
    for (p, level) in [("100%", 4), ("50%", 3), ("30%", 2), ("10%", 1), ("0%", 0)] {
        if s.contains(p) {
            return SUGAR_LEVELS[level];
        }
    }
    if s.trim() == "正常" || s.trim() == "標準" || s.trim() == "标准" || s.trim() == "regular" || s.trim() == "normal" { "全糖" } else { "" }
}

/// An ice level however it was said (the old "去冰" and "正常"), as one of ICE_LEVELS; "" when none is named.
pub fn ice_of(said: &str) -> &'static str {
    let s = said.to_lowercase();
    let words: [(&[&str], usize); 7] = [
        (&["溫", "温", "warm"], 5),
        (&["熱", "热", "hot"], 6),
        (&["無冰", "无冰", "去冰", "不加冰", "no ice", "without ice"], 0),
        (&["微冰", "light ice", "a little ice"], 1),
        (&["少冰", "less ice", "low ice"], 2),
        (&["半冰", "half ice"], 3),
        (&["全冰", "正常冰", "標準冰", "标准冰", "多冰", "full ice", "regular ice", "normal ice"], 4),
    ];
    for (keys, level) in words {
        if keys.iter().any(|k| s.contains(k)) {
            return ICE_LEVELS[level];
        }
    }
    if s.trim() == "正常" || s.trim() == "標準" || s.trim() == "标准" || s.trim() == "regular" || s.trim() == "normal" { "全冰" } else { "" }
}

/// How well an item matches her tastes: 2 exact (item and, for drinks, sweetness and ice), 1 liked, 0 neutral, -1
/// disliked or allergic.
pub fn taste_of(profile: &Value, item: &Item, sweetness: &str, ice: &str) -> i32 {
    let Some(tastes) = profile.get("tastes").filter(|t| t.is_object()) else { return 0 };
    let has = |field: &str| strings(tastes, field).iter().any(|s| *s == item.id || item.tags.contains(s) || (!s.is_empty() && item.name.contains(s.as_str())));
    if has("allergies") || has("dislikes") {
        return -1;
    }
    if !has("likes") {
        return 0;
    }
    if item.options.is_empty() {
        return 2;
    }
    let drink = tastes.get("drink").cloned().unwrap_or(Value::Null);
    let want_sweet = drink.get("sweetness").and_then(Value::as_str).unwrap_or("");
    let want_ice = drink.get("ice").and_then(Value::as_str).unwrap_or("");
    // Compared as levels: her "去冰" is the cup made "無冰".
    if (want_sweet.is_empty() || sugar_of(want_sweet) == sugar_of(sweetness)) && (want_ice.is_empty() || ice_of(want_ice) == ice_of(ice)) {
        2
    } else {
        1
    }
}

/// Her choice eating out alone: liked items first, within budget, at this place.
pub fn pick_meal<'a>(c: &'a Catalog, place: &str, month: i32, profile: &Value, budget: i32, rng: &mut RandomStream) -> Option<&'a Item> {
    pick_meal_on(c, place, 0, month, profile, budget, rng)
}

/// pick_meal on one floor of the place (0: any): a meal at the 9F food court was billed as two hot coffees from the 10F
/// view restaurant (R4-5).
pub fn pick_meal_on<'a>(c: &'a Catalog, place: &str, floor: i32, month: i32, profile: &Value, budget: i32, rng: &mut RandomStream) -> Option<&'a Item> {
    let mut options = Vec::new();
    let mut liked = Vec::new();
    for i in c.items_at(place, month) {
        if floor > 0 && i.floor > 0 && i.floor != floor {
            continue;
        }
        if !i.consumable || i.price_of(&i.default_size()) > budget.max(crate::region::amount("goods", 30) as i32) {
            continue;
        }
        let t = taste_of(profile, i, "", "");
        if t < 0 {
            continue;
        }
        options.push(i);
        if t > 0 {
            liked.push(i);
        }
    }
    let from = if liked.is_empty() { &options } else { &liked };
    if from.is_empty() {
        None
    } else {
        Some(from[rng.rand_range(0, from.len() as i32 - 1) as usize])
    }
}

pub fn profile_int(p: &Value, section: &str, field: &str, def: i32) -> i32 {
    p.get(section).and_then(|s| s.get(field)).and_then(Value::as_f64).map(|v| v as i32).unwrap_or(def)
}

/// Who she wants to pay a bill, and how hard she insists. treat_balance > 0: he has paid for her more than she for him.
/// cash < 0: her wallet is not known yet (treated as able to pay).
pub fn checkout_lean(profile: &Value, cash: i64, total: i32, treat_balance: i32, stage: &str) -> (&'static str, f32) {
    let pride = profile_int(profile, "money", "treat_pride", 50);
    let expects = profile_int(profile, "money", "expects_treat", 50);
    let reciprocity = profile_int(profile, "money", "reciprocity", 50);
    let share = (total + 1) / 2;
    if cash >= 0 && cash < share as i64 {
        return ("player_pays", 0.3 + expects as f32 / 250.0);
    }
    if treat_balance >= 2 && reciprocity >= 50 && (cash < 0 || cash >= total as i64) {
        return ("she_pays", (0.4 + reciprocity as f32 / 200.0 + treat_balance as f32 * 0.05).clamp(0.0, 0.95));
    }
    if pride >= 65 {
        return ("split", pride as f32 / 110.0);
    }
    if expects >= 60 || stage == "lover" {
        return ("player_pays", 0.3 + expects as f32 / 200.0);
    }
    ("split", 0.4)
}

/// A gift: taste match x price for the relationship. Above 0.5 she gladly accepts; below 0 she declines.
pub fn gift_score(profile: &Value, item: &Item, price: i32, stage: &str, greed: f32) -> f32 {
    let taste = taste_of(profile, item, "", "");
    let style = profile.get("tastes").and_then(|t| t.get("gift_style")).and_then(Value::as_str).unwrap_or("");
    let mut score = 0.3 + taste as f32 * 0.2;
    if (style == "cute" && item.tags.iter().any(|t| t == "cute")) || (style == "luxury" && item.tags.iter().any(|t| t == "luxury")) || (style == "practical" && item.category == "goods") {
        score += 0.3;
    }
    let comfortable = match stage {
        "lover" => crate::region::amount("cash", 4000) as i32,
        "friend" => crate::region::amount("cash", 600) as i32,
        _ => crate::region::amount("cash", 170) as i32,
    };
    let pride = profile_int(profile, "money", "treat_pride", 50);
    if price > comfortable {
        score -= (price - comfortable) as f32 / comfortable as f32 * (pride as f32 / 100.0) - greed / 200.0;
    }
    (score + greed / 400.0).clamp(-1.0, 1.5)
}

pub fn eval(c: &Catalog, kind: &str, r: &Value) -> Option<Result<Value, String>> {
    let s = |k: &str| r.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    Some(match kind {
        "place_open" => {
            let place = s("place");
            let open = c.place_open(&place, r.get("hours").and_then(Value::as_f64).unwrap_or(12.0), r.get("weekday").and_then(Value::as_i64).unwrap_or(0) as i32);
            let weekday = r.get("weekday").and_then(Value::as_i64).unwrap_or(0) as i32;
            Ok(json!({"open": open, "why": if open { String::new() } else { c.closed_why(&place, weekday) }}))
        }
        // A drink's sweetness and ice as levels, as this item can be made: no ice choice for a smoothie (no "ice" in its
        // options), no warm or hot for juice (no "hot"). The shop's default (全糖, 全冰) for what was not said; what
        // was asked and cannot be made comes back as refused_ice.
        "drink_options" => {
            let item = c.items.iter().find(|i| i.id == s("item"));
            let opts = |o: &str| item.is_some_and(|i| i.options.iter().any(|x| x == o));
            let sugar = if opts("sweetness") { sugar_of(&s("sweetness")) } else { "" };
            let asked = ice_of(&s("ice"));
            let warm = asked == "溫" || asked == "熱";
            let (ice, refused) = if !opts("ice") { ("", asked) } else if warm && !opts("hot") { (ICE_LEVELS[4], asked) } else if asked.is_empty() { (ICE_LEVELS[4], "") } else { (asked, "") };
            Ok(json!({"sweetness": if !opts("sweetness") { "" } else if sugar.is_empty() { SUGAR_LEVELS[4] } else { sugar }, "ice": ice,
                "refused_ice": refused, "named_sweetness": !sugar.is_empty(), "named_ice": !asked.is_empty() && refused.is_empty(),
                "sweetness_choices": if opts("sweetness") { SUGAR_LEVELS.to_vec() } else { vec![] },
                "ice_choices": if !opts("ice") { vec![] } else if opts("hot") { ICE_LEVELS.to_vec() } else { ICE_LEVELS[..5].to_vec() }}))
        }
        _ => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tuning::Tuning;

    #[test]
    fn hours_overnight_and_closed_days() {
        let mut c = Catalog::default();
        c.places.insert("bar".into(), Place { open: vec![(18.0, 26.0)], weekend_open: vec![], closed_weekdays: vec![0], ..Default::default() });
        assert!(c.place_open("bar", 20.0, 2) && c.place_open("bar", 1.5, 2) && !c.place_open("bar", 3.0, 2));
        assert!(!c.place_open("bar", 20.0, 0), "closed on Mondays");
        assert!(c.place_open("nowhere", 3.0, 0));
        assert_eq!(c.closed_why("bar", 2), "那裡現在沒開（營業 18–26 點）", "zh-TW, the default language");
        assert_eq!(c.closed_why("bar", 0), "那裡每週一公休", "closed on Mondays, said of any day");
    }

    #[test]
    fn drink_options_are_five_levels_each() {
        assert_eq!(sugar_of("半糖少冰"), "半糖");
        assert_eq!(ice_of("半糖少冰"), "少冰");
        assert_eq!(sugar_of("100%"), "全糖", "100% holds 0% and 10%");
        assert_eq!(sugar_of("10%"), "微糖");
        assert_eq!(sugar_of("无糖"), "無糖");
        assert_eq!(ice_of("去冰"), "無冰", "the old spelling");
        assert_eq!(ice_of("正常"), "全冰");
        assert_eq!(sugar_of("正常"), "全糖");
        assert_eq!(ice_of("half ice"), "半冰");
        assert_eq!(sugar_of("随便"), "");
        assert_eq!(ice_of("热的"), "熱");
        let c = Tuning::builtin().catalog;
        let ask = |item: &str, sweet: &str, ice: &str| eval(&c, "drink_options", &json!({"item": item, "sweetness": sweet, "ice": ice})).unwrap().unwrap();
        let v = ask("dk_pearl_milk", "微糖", "");
        assert_eq!((v["sweetness"].as_str(), v["ice"].as_str(), v["named_ice"].as_bool()), (Some("微糖"), Some("全冰"), Some(false)));
        assert_eq!(ask("dk_pearl_milk", "半糖", "热").get("ice").and_then(Value::as_str), Some("熱"), "milk tea can be hot");
        let juice = ask("dk_passion_green", "", "溫");
        assert_eq!((juice["ice"].as_str(), juice["refused_ice"].as_str()), (Some("全冰"), Some("溫")), "juice is not made warm");
        let smoothie = ask("dk_mango_smoothie", "少糖", "少冰");
        assert_eq!((smoothie["sweetness"].as_str(), smoothie["ice"].as_str(), smoothie["refused_ice"].as_str()), (Some("少糖"), Some(""), Some("少冰")), "a smoothie's ice is not chosen");
        assert!(smoothie["ice_choices"].as_array().unwrap().is_empty());
        let item = Item { id: "tea".into(), name: "綠茶".into(), options: vec!["sweetness".into()], ..Default::default() };
        let p = json!({"tastes": {"likes": ["tea"], "drink": {"sweetness": "半糖", "ice": "去冰"}}});
        assert_eq!(taste_of(&p, &item, "半糖", "無冰"), 2, "her 去冰 is the cup made 無冰");
    }

    #[test]
    fn tastes_meals_and_bills() {
        let c = Tuning::builtin().catalog;
        assert!(!c.items.is_empty() && !c.places.is_empty(), "catalog.json parsed");
        let item = Item { id: "tea".into(), name: "綠茶".into(), options: vec!["sweetness".into()], ..Default::default() };
        let p = json!({"tastes": {"likes": ["tea"], "drink": {"sweetness": "半糖"}}});
        assert_eq!((taste_of(&p, &item, "半糖", ""), taste_of(&p, &item, "全糖", "")), (2, 1));
        assert_eq!(taste_of(&json!({"tastes": {"dislikes": ["綠"]}}), &item, "", ""), -1);
        assert_eq!(checkout_lean(&json!({}), 10, 100, 0, "friend").0, "player_pays");
        assert_eq!(checkout_lean(&json!({"money": {"reciprocity": 80}}), 500, 100, 3, "friend").0, "she_pays");
        assert_eq!(checkout_lean(&json!({"money": {"treat_pride": 80}}), 500, 100, 0, "friend").0, "split");
        let place = c.items.iter().find(|i| i.consumable).map(|i| i.place.clone()).unwrap();
        let mut rng = RandomStream::new(3);
        assert!(pick_meal(&c, &place, 9, &json!({}), 500, &mut rng).is_some());
        let gift = Item { id: "bag".into(), tags: vec!["luxury".into()], ..Default::default() };
        assert!(gift_score(&json!({"tastes": {"gift_style": "luxury"}}), &gift, 100, "friend", 0.0) > gift_score(&json!({}), &gift, 100, "friend", 0.0));
    }
}
