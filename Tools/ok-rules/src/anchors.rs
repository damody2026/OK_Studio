//! Where people stand, sit and lie in the city (StreetSocialData/city_anchors.json, written by
//! Tools/build_street_city_places.lua) and which acts use which kinds of anchor (rules/anchor_kinds.toml). The table is
//! read once with the tuning and indexed by id, place, kind and a 10 m grid, so a query neither reads files nor walks the
//! whole table. Which anchors are taken is the game's to know: it passes them as `exclude`.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap, HashSet};

const CELL_CM: f32 = 1000.0;

#[derive(Deserialize, Serialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Slot {
    pub pos: [f32; 3],
    /// The hips on the seat; `pos` stays the foot point on the floor.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seat_pos: Option<[f32; 3]>,
    pub yaw: f32,
}

#[derive(Deserialize, Serialize, Debug, Clone, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Anchor {
    pub id: String,
    pub name: String,
    pub place: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub building: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub room: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub floor: Option<i32>,
    /// The foot point on the floor: what the character walks to.
    pub pos: [f32; 3],
    /// Where the hips go on a seat (seat surface, middle of the seat).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub seat_pos: Option<[f32; 3]>,
    pub yaw: f32,
    pub kinds: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub slots: Vec<Slot>,
    pub privacy: i32,
    pub outdoor: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
}

impl Anchor {
    fn capacity(&self) -> usize {
        self.slots.len().max(1)
    }
}

#[derive(Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct KindInfo {
    pub name: String,
    pub people: u32,
}

#[derive(Deserialize, Debug, Clone)]
#[serde(deny_unknown_fields)]
pub struct AnchorKinds {
    pub kinds: BTreeMap<String, KindInfo>,
    /// acts.toml id -> the kinds it can use.
    pub acts: BTreeMap<String, Vec<String>>,
    /// H category number (h_poses.json) -> the kinds it can use.
    pub h: BTreeMap<String, Vec<String>>,
}

#[derive(Deserialize)]
struct AnchorFile {
    anchors: Vec<Anchor>,
}

pub struct AnchorIndex {
    pub rows: Vec<Anchor>,
    pub table: AnchorKinds,
    by_id: HashMap<String, u32>,
    by_place: HashMap<String, Vec<u32>>,
    by_kind: HashMap<String, Vec<u32>>,
    grid: HashMap<(i32, i32), Vec<u32>>,
}

fn cell(v: f32) -> i32 {
    (v / CELL_CM).floor() as i32
}

fn dist2(p: [f32; 3], n: [f32; 3]) -> f32 {
    (p[0] - n[0]).powi(2) + (p[1] - n[1]).powi(2) + (p[2] - n[2]).powi(2)
}

impl AnchorIndex {
    pub fn new(data: Value, table: AnchorKinds) -> Result<AnchorIndex, String> {
        let rows = serde_json::from_value::<AnchorFile>(data).map_err(|e| format!("city_anchors: {e}"))?.anchors;
        let (mut by_id, mut by_place, mut by_kind, mut grid) = (HashMap::new(), HashMap::<String, Vec<u32>>::new(), HashMap::<String, Vec<u32>>::new(), HashMap::<(i32, i32), Vec<u32>>::new());
        for (i, a) in rows.iter().enumerate() {
            let i = i as u32;
            if by_id.insert(a.id.clone(), i).is_some() {
                return Err(format!("city_anchors: {} twice", a.id));
            }
            by_place.entry(a.place.clone()).or_default().push(i);
            for k in &a.kinds {
                by_kind.entry(k.clone()).or_default().push(i);
            }
            grid.entry((cell(a.pos[0]), cell(a.pos[1]))).or_default().push(i);
        }
        Ok(AnchorIndex { rows, table, by_id, by_place, by_kind, grid })
    }

    fn near_ids(&self, near: [f32; 3], radius: f32) -> Vec<u32> {
        let (x0, x1, y0, y1) = (cell(near[0] - radius), cell(near[0] + radius), cell(near[1] - radius), cell(near[1] + radius));
        let mut out = Vec::new();
        for x in x0..=x1 {
            for y in y0..=y1 {
                if let Some(ids) = self.grid.get(&(x, y)) {
                    out.extend_from_slice(ids);
                }
            }
        }
        out
    }

    /// The anchors a request allows, nearest first (table order without `near`). The narrowest index starts the search.
    pub fn find(&self, kinds: &[String], r: &Value) -> Vec<&Anchor> {
        let place = r.get("place").and_then(Value::as_str).filter(|s| !s.is_empty());
        let near = r.get("near").and_then(|v| serde_json::from_value::<[f32; 3]>(v.clone()).ok());
        let radius = r.get("radius").and_then(Value::as_f64).map(|v| v as f32);
        let floor = r.get("floor").and_then(Value::as_i64).map(|v| v as i32);
        let pmin = r.get("privacy_min").and_then(Value::as_i64).unwrap_or(0) as i32;
        let pmax = r.get("privacy_max").and_then(Value::as_i64).unwrap_or(2) as i32;
        let outdoor = r.get("outdoor").and_then(Value::as_bool);
        let capacity = r.get("capacity").and_then(Value::as_u64).unwrap_or(1) as usize;
        let limit = r.get("limit").and_then(Value::as_u64).unwrap_or(20) as usize;
        let tags: Vec<&str> = r.get("tags").and_then(Value::as_array).map(|t| t.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
        let exclude: HashSet<&str> = r.get("exclude").and_then(Value::as_array).map(|t| t.iter().filter_map(Value::as_str).collect()).unwrap_or_default();
        let wanted: HashSet<&str> = kinds.iter().map(String::as_str).collect();
        let keep = |a: &Anchor| {
            (wanted.is_empty() || a.kinds.iter().any(|k| wanted.contains(k.as_str())))
                && floor.map_or(true, |f| a.floor == Some(f))
                && a.privacy >= pmin
                && a.privacy <= pmax
                && outdoor.map_or(true, |o| a.outdoor == o)
                && a.capacity() >= capacity
                && tags.iter().all(|t| a.tags.iter().any(|x| x == t))
                && !exclude.contains(a.id.as_str())
        };
        // nearest few with no radius: widen the grid search until the answer cannot change, the whole table only as a last step
        if let (Some(n), None, None, true) = (near, radius, place, limit > 0) {
            let mut rad = 3000.0_f32;
            while rad < 100000.0 {
                let mut rows: Vec<(f32, u32)> = self.near_ids(n, rad).into_iter().filter(|&i| keep(&self.rows[i as usize])).map(|i| (dist2(self.rows[i as usize].pos, n), i)).filter(|q| q.0 <= rad * rad).collect();
                if rows.len() >= limit {
                    return self.nearest(&mut rows, limit);
                }
                rad *= 3.0;
            }
        }

        let mut ids: Vec<u32> = if let Some(p) = place {
            self.by_place.get(p).cloned().unwrap_or_default()
        } else if let (Some(n), Some(rad)) = (near, radius) {
            self.near_ids(n, rad)
        } else if !kinds.is_empty() {
            let mut v: Vec<u32> = kinds.iter().filter_map(|k| self.by_kind.get(k)).flatten().copied().collect();
            v.sort_unstable();
            v.dedup();
            v
        } else {
            (0..self.rows.len() as u32).collect()
        };
        ids.retain(|&i| keep(&self.rows[i as usize]));
        match near {
            Some(n) => {
                let mut rows: Vec<(f32, u32)> = ids.into_iter().map(|i| (dist2(self.rows[i as usize].pos, n), i)).collect();
                if let Some(rad) = radius {
                    rows.retain(|q| q.0 <= rad * rad);
                }
                self.nearest(&mut rows, limit)
            }
            None => ids.into_iter().take(if limit > 0 { limit } else { usize::MAX }).map(|i| &self.rows[i as usize]).collect(),
        }
    }

    fn nearest(&self, rows: &mut Vec<(f32, u32)>, limit: usize) -> Vec<&Anchor> {
        if limit > 0 && rows.len() > limit {
            rows.select_nth_unstable_by(limit - 1, |a, b| a.0.total_cmp(&b.0));
            rows.truncate(limit);
        }
        rows.sort_unstable_by(|a, b| a.0.total_cmp(&b.0));
        rows.iter().map(|q| &self.rows[q.1 as usize]).collect()
    }

    /// The kinds an act can use: an acts.toml id, or an H category number (as a number or as text).
    pub fn kinds_of_act(&self, act: &Value) -> Option<&Vec<String>> {
        let key = act.as_i64().map(|n| n.to_string()).or_else(|| act.as_str().map(str::to_string))?;
        self.table.acts.get(&key).or_else(|| self.table.h.get(&key))
    }

    pub fn get(&self, id: &str) -> Option<&Anchor> {
        self.by_id.get(id).map(|&i| &self.rows[i as usize])
    }

    pub fn of_place(&self, place: &str) -> Vec<&Anchor> {
        self.by_place.get(place).map(|ids| ids.iter().map(|&i| &self.rows[i as usize]).collect()).unwrap_or_default()
    }

    pub fn count(&self, kind: &str) -> usize {
        self.by_kind.get(kind).map_or(0, Vec::len)
    }
}

fn strings(v: Option<&Value>) -> Vec<String> {
    match v {
        Some(Value::String(s)) => vec![s.clone()],
        Some(Value::Array(a)) => a.iter().filter_map(Value::as_str).map(str::to_string).collect(),
        _ => Vec::new(),
    }
}

pub fn eval(t: &AnchorIndex, kind: &str, r: &Value) -> Option<Result<Value, String>> {
    Some(Ok(match kind {
        "anchor_find" => json!({"anchors": t.find(&strings(r.get("kinds")), r)}),
        "anchors_of_place" => {
            let place = r.get("place").and_then(Value::as_str).unwrap_or_default();
            let kinds = strings(r.get("kinds"));
            let rows: Vec<&Anchor> = t.of_place(place).into_iter().filter(|a| kinds.is_empty() || a.kinds.iter().any(|k| kinds.contains(k))).collect();
            json!({"anchors": rows})
        }
        "anchor_get" => json!({"anchor": t.get(r.get("id").and_then(Value::as_str).unwrap_or_default())}),
        "anchor_for_act" => {
            let Some(kinds) = r.get("act").and_then(|a| t.kinds_of_act(a)) else {
                return Some(Err(format!("anchor_for_act: unknown act {}", r.get("act").unwrap_or(&Value::Null))));
            };
            json!({"kinds": kinds, "anchors": t.find(kinds, r)})
        }
        "anchor_kinds" => {
            let rows: Vec<Value> = t.table.kinds.iter().map(|(k, v)| json!({"kind": k, "name": v.name, "people": v.people, "count": t.count(k)})).collect();
            json!({"kinds": rows, "total": t.rows.len()})
        }
        _ => return None,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tuning::Tuning;

    fn data(name: &str) -> String {
        std::fs::read_to_string(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Content/IndependentResources/StreetSocialData").join(name)).unwrap()
    }

    fn sample() -> AnchorIndex {
        let table: AnchorKinds = toml::from_str("[kinds]\nseat = {name='a',people=1}\nseat_pair={name='b',people=2}\n[acts]\nhug=['seat_pair']\n[h]\n12=['seat']\n").unwrap();
        let row = |id: &str, place: &str, x: f32, kinds: &[&str], privacy: i32, slots: usize| {
            json!({"id": id, "name": id, "place": place, "pos": [x, 0.0, 0.0], "yaw": 0.0, "kinds": kinds, "privacy": privacy, "outdoor": false,
                   "slots": (0..slots).map(|_| json!({"pos": [x, 0.0, 0.0], "yaw": 0.0})).collect::<Vec<_>>()})
        };
        AnchorIndex::new(json!({"anchors": [row("p.a", "p", 100.0, &["seat"], 0, 0), row("p.b", "p", 300.0, &["seat_pair"], 1, 2), row("q.a", "q", 5000.0, &["seat"], 2, 0)]}), table).unwrap()
    }

    #[test]
    fn find_filters_sorts_and_limits() {
        let t = sample();
        let ids = |r: Value, k: &[&str]| t.find(&k.iter().map(|s| s.to_string()).collect::<Vec<_>>(), &r).iter().map(|a| a.id.clone()).collect::<Vec<_>>();
        assert_eq!(ids(json!({"near": [0.0, 0.0, 0.0], "radius": 10000.0}), &["seat", "seat_pair"]), ["p.a", "p.b", "q.a"]);
        assert_eq!(ids(json!({"near": [0.0, 0.0, 0.0], "radius": 200.0}), &["seat"]), ["p.a"]);
        assert_eq!(ids(json!({"near": [6000.0, 0.0, 0.0], "limit": 1}), &["seat"]), ["q.a"]);
        assert_eq!(ids(json!({"capacity": 2}), &["seat", "seat_pair"]), ["p.b"]);
        assert_eq!(ids(json!({"privacy_min": 2}), &["seat"]), ["q.a"]);
        assert_eq!(ids(json!({"exclude": ["p.a"], "place": "p"}), &["seat"]), Vec::<String>::new());
    }

    #[test]
    fn answers_through_eval() {
        let t = sample();
        assert_eq!(eval(&t, "anchor_get", &json!({"id": "p.b"})).unwrap().unwrap()["anchor"]["place"], "p");
        assert_eq!(eval(&t, "anchors_of_place", &json!({"place": "p", "kinds": "seat"})).unwrap().unwrap()["anchors"].as_array().unwrap().len(), 1);
        assert_eq!(eval(&t, "anchor_for_act", &json!({"act": "hug"})).unwrap().unwrap()["anchors"][0]["id"], "p.b");
        assert_eq!(eval(&t, "anchor_for_act", &json!({"act": 12})).unwrap().unwrap()["kinds"][0], "seat");
        assert!(eval(&t, "anchor_for_act", &json!({"act": "nope"})).unwrap().is_err());
        assert_eq!(eval(&t, "anchor_kinds", &json!({})).unwrap().unwrap()["total"], 3);
        assert!(eval(&t, "other", &json!({})).is_none());
    }

    #[test]
    fn every_activity_anchor_and_station_is_found() {
        let tuning = Tuning::load(None).unwrap();
        let t = &tuning.anchors;
        let mut missing = Vec::new();
        for a in &tuning.activities.activity {
            if a.place.is_empty() || a.anchor.is_empty() {
                continue;
            }
            if !a.anchor.split('|').any(|n| t.get(&format!("{}.{n}", a.place)).is_some()) {
                missing.push(format!("{}: {}.{}", a.id, a.place, a.anchor));
            }
        }
        let catalog: Value = serde_json::from_str(&data("catalog.json")).unwrap();
        for j in catalog["jobs"].as_array().unwrap() {
            let place = j["place"].as_str().unwrap_or_default();
            for s in j["stations"].as_array().into_iter().flatten().filter_map(Value::as_str) {
                if !place.is_empty() && t.get(&format!("{place}.{s}")).is_none() {
                    missing.push(format!("job {}: {place}.{s}", j["id"]));
                }
            }
        }
        assert!(missing.is_empty(), "{}", missing.join("\n"));
    }

    #[test]
    fn every_kind_has_anchors_and_every_h_category_a_kind() {
        let tuning = Tuning::load(None).unwrap();
        let t = &tuning.anchors;
        let empty: Vec<&String> = t.table.kinds.keys().filter(|k| t.count(k) == 0).collect();
        assert!(empty.is_empty(), "no anchors: {empty:?}");
        let poses: Value = serde_json::from_str(&data("h_poses.json")).unwrap();
        for p in poses.as_array().unwrap() {
            for c in p["categories"].as_array().unwrap() {
                assert!(t.kinds_of_act(c).is_some(), "H category {c}");
            }
        }
        for ks in t.table.acts.values().chain(t.table.h.values()) {
            for k in ks {
                assert!(t.table.kinds.contains_key(k), "{k}");
            }
        }
    }

    #[test]
    fn rows_are_consistent() {
        let tuning = Tuning::load(None).unwrap();
        let t = &tuning.anchors;
        for a in &t.rows {
            assert_eq!(a.id, format!("{}.{}", a.place, a.name));
            for k in &a.kinds {
                let info = t.table.kinds.get(k).unwrap_or_else(|| panic!("{}: kind {k}", a.id));
                if info.people == 2 && !k.starts_with("h_") {
                    assert!(a.slots.is_empty() || a.slots.len() >= 2, "{}: {k}", a.id);
                }
            }
            assert!((0..=2).contains(&a.privacy), "{}", a.id);
            // a floor is 3 to 10 m (the sports hall's are the tallest), with the ground at z 1200
            if let (Some(f), false) = (a.floor, a.outdoor) {
                assert!(a.pos[2] > 900.0 + (f - 1) as f32 * 250.0 && a.pos[2] < 1900.0 + (f - 1) as f32 * 1000.0, "{} floor {f} z {}", a.id, a.pos[2]);
            }
        }
    }

    #[test]
    fn a_query_over_the_whole_table_is_fast() {
        let tuning = Tuning::load(None).unwrap();
        let t = &tuning.anchors;
        let kinds = vec!["seat".to_string(), "seat_pair".to_string()];
        let r = json!({"near": [50000.0, 50000.0, 1200.0], "limit": 10});
        let n = 2000;
        let start = std::time::Instant::now();
        for _ in 0..n {
            assert!(!t.find(&kinds, &r).is_empty());
        }
        let each = start.elapsed().as_secs_f64() / n as f64;
        assert!(each < 0.0001, "{each}");
    }
}
