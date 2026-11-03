//! UniversityCity prop index: answers "what is around her" for the StreetSocial heroines.
//!
//! The data is `props.json`, written by `Tools/build_street_city_places.lua` (section 5) from the map's assembly
//! reports and actor dump. It lists every usable or talkable object (beds, mirrors, toilets, chairs, vending machines,
//! benches, lanterns ...) with its kind, position and the area it belongs to (a room, an outdoor place or a building).
//! Coordinates are UE cm, +X north, +Y east.
//!
//! The index buckets props and area doors in a 10 m XY grid, so a 10 m or 20 m query touches 9 or 25 cells.
//! Visibility follows the walls the data knows about: inside a room she only sees that room's props; outside a room
//! (corridors, lobbies, outdoors) she sees props that are not inside some other room. `eval` takes the same
//! JSON request / response shape as ok-rules so the module can move there unchanged.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Kind {
    pub zh: String,
    pub category: String,
    #[serde(default)]
    pub uses: Vec<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Area {
    pub id: String,
    /// "room", "place" (outdoor spot) or "building"
    pub kind: String,
    /// room type (dorm, class, motel_suite ...), outdoor place kind (grove, park_bench ...) or building category
    #[serde(rename = "type", default)]
    pub area_type: String,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub building: Option<String>,
    #[serde(default)]
    pub floor: Option<i32>,
    #[serde(default)]
    pub privacy: i32,
    pub door: [f32; 3],
    #[serde(default)]
    pub min: Option<[f32; 3]>,
    #[serde(default)]
    pub max: Option<[f32; 3]>,
    #[serde(default)]
    pub radius_cm: Option<f32>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Prop {
    /// kind id (key of `kinds`)
    pub k: String,
    pub p: [f32; 3],
    /// area index, absent when the prop is outdoors and outside every named place
    #[serde(default)]
    pub a: Option<u32>,
    /// world yaw (degrees) the front of the object looks to, when known
    #[serde(default)]
    pub face: Option<f32>,
    /// specific name (天花板鏡, 吉他 ...) overriding the kind name
    #[serde(default)]
    pub n: Option<String>,
}

#[derive(Debug, Deserialize)]
struct File {
    #[serde(default)]
    map_sha256: String,
    #[serde(default = "default_cell")]
    cell_cm: f32,
    kinds: HashMap<String, Kind>,
    areas: Vec<Area>,
    props: Vec<Prop>,
}

fn default_cell() -> f32 {
    1000.0
}

/// Props within this height of her feet count as on her level (a floor is 3.2 to 4.2 m).
const LEVEL_CM: f32 = 250.0;

pub struct PropIndex {
    pub map_sha256: String,
    pub kinds: HashMap<String, Kind>,
    pub areas: Vec<Area>,
    pub props: Vec<Prop>,
    cell: f32,
    prop_grid: HashMap<(i32, i32), Vec<u32>>,
    area_grid: HashMap<(i32, i32), Vec<u32>>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Query {
    #[serde(default = "default_radius")]
    pub radius_cm: f32,
    /// only these kind ids (empty = all)
    #[serde(default)]
    pub kinds: Vec<String>,
    /// only these categories (furniture, bathroom, mirror, shop, outdoor ...; empty = all)
    #[serde(default)]
    pub categories: Vec<String>,
    /// ignore walls: every prop in the radius on her level
    #[serde(default)]
    pub through_walls: bool,
    /// at most this many props (0 = no limit), nearest first
    #[serde(default)]
    pub limit: usize,
}

fn default_radius() -> f32 {
    1000.0
}

#[derive(Debug, Clone, Serialize)]
pub struct Hit {
    pub index: u32,
    pub dist_cm: f32,
}

fn dist(a: [f32; 3], b: [f32; 3]) -> f32 {
    let (dx, dy, dz) = (a[0] - b[0], a[1] - b[1], a[2] - b[2]);
    (dx * dx + dy * dy + dz * dz).sqrt()
}

/// Eight-point compass direction from `from` to `to` (+X north, +Y east).
pub fn direction_zh(from: [f32; 3], to: [f32; 3]) -> &'static str {
    let (n, e) = (to[0] - from[0], to[1] - from[1]);
    if n * n + e * e < 100.0 * 100.0 {
        return "就在旁邊";
    }
    let deg = e.atan2(n).to_degrees().rem_euclid(360.0);
    const NAMES: [&str; 8] = [
        "北邊",
        "東北邊",
        "東邊",
        "東南邊",
        "南邊",
        "西南邊",
        "西邊",
        "西北邊",
    ];
    NAMES[(((deg + 22.5) / 45.0) as usize) % 8]
}

fn metres(cm: f32) -> String {
    let m = cm / 100.0;
    if m < 10.0 {
        format!("{:.1} 公尺", m)
    } else {
        format!("{:.0} 公尺", m)
    }
}

impl PropIndex {
    pub fn from_json(text: &str) -> Result<PropIndex, String> {
        let f: File = serde_json::from_str(text).map_err(|e| format!("props.json: {e}"))?;
        let mut idx = PropIndex {
            map_sha256: f.map_sha256,
            kinds: f.kinds,
            areas: f.areas,
            props: f.props,
            cell: if f.cell_cm > 0.0 { f.cell_cm } else { 1000.0 },
            prop_grid: HashMap::new(),
            area_grid: HashMap::new(),
        };
        for (i, p) in idx.props.iter().enumerate() {
            let c = idx.cell_of(p.p);
            idx.prop_grid.entry(c).or_default().push(i as u32);
        }
        for (i, a) in idx.areas.iter().enumerate() {
            // a room or building is filed under every cell its box touches, so area_at needs one cell lookup
            let (lo, hi) = match (a.min, a.max) {
                (Some(lo), Some(hi)) => (lo, hi),
                _ => {
                    let r = a.radius_cm.unwrap_or(600.0);
                    (
                        [a.door[0] - r, a.door[1] - r, a.door[2]],
                        [a.door[0] + r, a.door[1] + r, a.door[2]],
                    )
                }
            };
            let (c0, c1) = (idx.cell_of(lo), idx.cell_of(hi));
            for x in c0.0..=c1.0 {
                for y in c0.1..=c1.1 {
                    idx.area_grid.entry((x, y)).or_default().push(i as u32);
                }
            }
        }
        Ok(idx)
    }

    pub fn load(path: &str) -> Result<PropIndex, String> {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
        PropIndex::from_json(&text)
    }

    fn cell_of(&self, p: [f32; 3]) -> (i32, i32) {
        (
            (p[0] / self.cell).floor() as i32,
            (p[1] / self.cell).floor() as i32,
        )
    }

    fn cells_around(&self, p: [f32; 3], r: f32) -> impl Iterator<Item = (i32, i32)> {
        let (c0, c1) = (
            self.cell_of([p[0] - r, p[1] - r, 0.0]),
            self.cell_of([p[0] + r, p[1] + r, 0.0]),
        );
        (c0.0..=c1.0).flat_map(move |x| (c0.1..=c1.1).map(move |y| (x, y)))
    }

    /// The room / outdoor place / building she stands in (smallest room box wins; z within the room height).
    pub fn area_at(&self, p: [f32; 3]) -> Option<u32> {
        let mut best: Option<(u32, f32, u8)> = None; // (index, size, rank: 0 room, 1 building, 2 place)
        for &i in self.area_grid.get(&self.cell_of(p)).into_iter().flatten() {
            let a = &self.areas[i as usize];
            let cand = match (a.min, a.max) {
                (Some(lo), Some(hi)) => {
                    let inside = p[0] >= lo[0]
                        && p[0] <= hi[0]
                        && p[1] >= lo[1]
                        && p[1] <= hi[1]
                        && p[2] >= lo[2] - 60.0
                        && p[2] <= hi[2];
                    inside.then(|| {
                        (
                            i,
                            (hi[0] - lo[0]) * (hi[1] - lo[1]),
                            if a.kind == "room" { 0 } else { 1 },
                        )
                    })
                }
                _ => {
                    let r = a.radius_cm.unwrap_or(600.0);
                    let d = ((p[0] - a.door[0]).powi(2) + (p[1] - a.door[1]).powi(2)).sqrt();
                    (d <= r && (p[2] - a.door[2]).abs() < LEVEL_CM * 2.0).then(|| (i, r * r, 2))
                }
            };
            if let Some(c) = cand {
                if best.map_or(true, |b| (c.2, c.1) < (b.2, b.1)) {
                    best = Some(c);
                }
            }
        }
        best.map(|b| b.0)
    }

    fn is_room(&self, a: Option<u32>) -> bool {
        a.map_or(false, |i| self.areas[i as usize].kind == "room")
    }

    /// Whether a prop is on the level she stands on. Positions are object bases on the floor (mirrors: the glass
    /// centre, up to the ceiling), so the window looks up more than down. Inside her own room the room box already
    /// fixes the floor and a ceiling mirror 3.9 m above her feet still counts; elsewhere the window stays below the
    /// smallest storey height (3.6 m), so the floor above and the floor below never leak in.
    fn same_level(&self, feet: [f32; 3], pr: &Prop, in_her_room: bool) -> bool {
        let dz = pr.p[2] - feet[2];
        let up = match (in_her_room, pr.k == "mirror") {
            (true, true) => 450.0,
            (true, false) => 300.0,
            (false, true) => 320.0,
            (false, false) => LEVEL_CM,
        };
        dz >= -120.0 && dz <= up
    }

    /// Storey she is on: the floor number of her room or, in a corridor, of the room nearest below her feet.
    pub fn floor_at(&self, p: [f32; 3]) -> Option<i32> {
        let here = self.area_at(p)?;
        let a = &self.areas[here as usize];
        if a.floor.is_some() {
            return a.floor;
        }
        if a.kind != "building" {
            return None;
        }
        let mut best: Option<(f32, i32)> = None;
        for &i in self.area_grid.get(&self.cell_of(p)).into_iter().flatten() {
            let r = &self.areas[i as usize];
            if let (Some(f), Some(lo)) = (r.floor, r.min) {
                let dz = p[2] - lo[2];
                if r.building == a.building && dz > -60.0 && best.map_or(true, |b| dz < b.0) {
                    best = Some((dz, f));
                }
            }
        }
        best.map(|b| b.1)
    }

    /// Props near `p`, nearest first.
    pub fn nearby(&self, p: [f32; 3], q: &Query) -> Vec<Hit> {
        let here = self.area_at(p);
        let in_room = self.is_room(here);
        let mut hits = Vec::new();
        for c in self.cells_around(p, q.radius_cm) {
            for &i in self.prop_grid.get(&c).into_iter().flatten() {
                let pr = &self.props[i as usize];
                if !self.same_level(p, pr, in_room && pr.a == here) {
                    continue;
                }
                let d = dist(p, pr.p);
                if d > q.radius_cm {
                    continue;
                }
                if !q.through_walls {
                    let visible = if in_room {
                        pr.a == here
                    } else {
                        !self.is_room(pr.a) || pr.a == here
                    };
                    if !visible {
                        continue;
                    }
                }
                if !q.kinds.is_empty() && !q.kinds.iter().any(|k| k == &pr.k) {
                    continue;
                }
                if !q.categories.is_empty() {
                    let cat = self
                        .kinds
                        .get(&pr.k)
                        .map(|k| k.category.as_str())
                        .unwrap_or("");
                    if !q.categories.iter().any(|c| c == cat) {
                        continue;
                    }
                }
                hits.push(Hit {
                    index: i,
                    dist_cm: d,
                });
            }
        }
        hits.sort_by(|a, b| a.dist_cm.total_cmp(&b.dist_cm));
        if q.limit > 0 {
            hits.truncate(q.limit);
        }
        hits
    }

    /// Rooms, outdoor places and buildings whose door is within `radius_cm` (on any level), nearest first.
    pub fn nearby_areas(&self, p: [f32; 3], radius_cm: f32) -> Vec<Hit> {
        let mut seen = std::collections::HashSet::new();
        let mut hits = Vec::new();
        for c in self.cells_around(p, radius_cm) {
            for &i in self.area_grid.get(&c).into_iter().flatten() {
                if !seen.insert(i) {
                    continue;
                }
                let d = dist(p, self.areas[i as usize].door);
                if d <= radius_cm {
                    hits.push(Hit {
                        index: i,
                        dist_cm: d,
                    });
                }
            }
        }
        hits.sort_by(|a, b| a.dist_cm.total_cmp(&b.dist_cm));
        hits
    }

    pub fn prop_name(&self, pr: &Prop) -> String {
        pr.n.clone().unwrap_or_else(|| {
            self.kinds
                .get(&pr.k)
                .map(|k| k.zh.clone())
                .unwrap_or_else(|| pr.k.clone())
        })
    }

    pub fn area_name(&self, a: &Area) -> String {
        a.name.clone().unwrap_or_else(|| a.id.clone())
    }

    fn area_json(&self, i: u32) -> Value {
        let a = &self.areas[i as usize];
        json!({ "index": i, "id": a.id, "kind": a.kind, "type": a.area_type, "name": self.area_name(a), "building": a.building,
                "floor": a.floor, "privacy": a.privacy, "door": a.door })
    }

    /// Everything around her as JSON, plus a one-paragraph Chinese description for the chat prompt.
    /// Props are grouped by name (鏡子 ×2, nearest first); each group keeps the nearest position so she can walk there.
    pub fn describe(&self, p: [f32; 3], q: &Query, area_radius_cm: f32) -> Value {
        let here = self.area_at(p);
        let hits = self.nearby(p, q);
        let mut groups: BTreeMap<String, (usize, f32, u32)> = BTreeMap::new();
        let mut order = Vec::new();
        for h in &hits {
            let pr = &self.props[h.index as usize];
            let name = self.prop_name(pr);
            let e = groups.entry(name.clone()).or_insert_with(|| {
                order.push(name.clone());
                (0, h.dist_cm, h.index)
            });
            e.0 += 1;
        }
        let props: Vec<Value> = order
            .iter()
            .map(|name| {
                let (n, d, i) = groups[name];
                let pr = &self.props[i as usize];
                let kind = self.kinds.get(&pr.k);
                json!({ "name": name, "kind": pr.k, "category": kind.map(|k| k.category.clone()), "uses": kind.map(|k| k.uses.clone()),
                        "count": n, "nearest_cm": d.round(), "nearest": { "index": i, "pos": pr.p, "face": pr.face }, "direction": direction_zh(p, pr.p) })
            })
            .collect();
        let areas: Vec<Value> = self
            .nearby_areas(p, area_radius_cm)
            .into_iter()
            .filter(|h| Some(h.index) != here)
            .filter(|h| {
                // shops and named places; skip the individual rooms of other buildings (a dorm has hundreds)
                // rooms only on her own storey (the dorm rooms right above her are not "nearby")
                let a = &self.areas[h.index as usize];
                a.kind != "room"
                    || (a.door[2] - p[2]).abs() < LEVEL_CM
                        && here.map_or(false, |i| {
                            self.areas[i as usize].building.is_some()
                                && self.areas[i as usize].building == a.building
                        })
            })
            .take(12)
            .map(|h| {
                let mut v = self.area_json(h.index);
                v["dist_cm"] = json!(h.dist_cm.round());
                let door = self.areas[h.index as usize].door;
                v["direction"] = json!(direction_zh(p, door));
                let dz = door[2] - p[2];
                v["level"] = json!(if dz > LEVEL_CM {
                    "above"
                } else if dz < -LEVEL_CM {
                    "below"
                } else {
                    "same"
                });
                v
            })
            .collect();
        let mut text = String::new();
        if let Some(i) = here {
            let a = &self.areas[i as usize];
            match self.floor_at(p) {
                Some(f) if a.kind != "place" => {
                    text.push_str(&format!("妳在「{}」（{} 樓）。", self.area_name(a), f))
                }
                _ => text.push_str(&format!("妳在「{}」。", self.area_name(a))),
            }
        }
        if !props.is_empty() {
            let parts: Vec<String> = props
                .iter()
                .take(14)
                .map(|v| {
                    let n = v["count"].as_u64().unwrap_or(1);
                    let name = v["name"].as_str().unwrap_or("");
                    let d = metres(v["nearest_cm"].as_f64().unwrap_or(0.0) as f32);
                    if n > 1 {
                        format!("{name}×{n}（最近 {d}）")
                    } else {
                        format!("{name}（{d}）")
                    }
                })
                .collect();
            text.push_str(&format!("附近有：{}。", parts.join("、")));
        }
        if !areas.is_empty() {
            let parts: Vec<String> = areas
                .iter()
                .take(6)
                .map(|v| {
                    let dir = match v["level"].as_str() {
                        Some("above") => format!("樓上，{}", v["direction"].as_str().unwrap_or("")),
                        Some("below") => format!("樓下，{}", v["direction"].as_str().unwrap_or("")),
                        _ => v["direction"].as_str().unwrap_or("").to_string(),
                    };
                    let dir = dir.as_str();
                    let name = v["name"].as_str().unwrap_or("");
                    if dir == "就在旁邊" {
                        format!("{name}（{dir}）")
                    } else {
                        format!(
                            "{name}（{dir} {}）",
                            metres(v["dist_cm"].as_f64().unwrap_or(0.0) as f32)
                        )
                    }
                })
                .collect();
            text.push_str(&format!("附近的地點：{}。", parts.join("、")));
        }
        json!({ "here": here.map(|i| self.area_json(i)), "floor": self.floor_at(p), "props": props, "areas": areas, "text": text })
    }

    /// ok-rules style entry: `kind` names the question, `request` carries `pos` [x,y,z] and the Query fields.
    ///   nearby_props  -> describe(): here, grouped props, nearby areas, text
    ///   prop_list     -> every matching prop (index, kind, name, pos, face, area, dist_cm), nearest first
    ///   area_at       -> the area she stands in
    ///   nearest_prop  -> the nearest prop of `kinds` / `categories` (to walk to and use)
    pub fn eval(&self, kind: &str, request: &Value) -> Option<Value> {
        let pos = request
            .get("pos")
            .and_then(|v| serde_json::from_value::<[f32; 3]>(v.clone()).ok());
        let q: Query = serde_json::from_value(request.clone()).unwrap_or_default();
        let q = Query {
            radius_cm: if q.radius_cm > 0.0 {
                q.radius_cm
            } else {
                default_radius()
            },
            ..q
        };
        match kind {
            "nearby_props" => {
                let p = pos?;
                let ar = request
                    .get("area_radius_cm")
                    .and_then(Value::as_f64)
                    .unwrap_or(q.radius_cm as f64 * 2.0) as f32;
                Some(self.describe(p, &q, ar))
            }
            "prop_list" => {
                let p = pos?;
                let list: Vec<Value> = self
                    .nearby(p, &q)
                    .into_iter()
                    .map(|h| {
                        let pr = &self.props[h.index as usize];
                        json!({ "index": h.index, "kind": pr.k, "name": self.prop_name(pr), "pos": pr.p, "face": pr.face,
                                "area": pr.a.map(|a| self.areas[a as usize].id.clone()), "dist_cm": h.dist_cm.round() })
                    })
                    .collect();
                Some(json!({ "props": list }))
            }
            "area_at" => Some(json!({ "here": self.area_at(pos?).map(|i| self.area_json(i)) })),
            "nearest_prop" => {
                let p = pos?;
                let q = Query { limit: 1, ..q };
                let h = self.nearby(p, &q).into_iter().next();
                Some(json!({ "prop": h.map(|h| {
                    let pr = &self.props[h.index as usize];
                    json!({ "index": h.index, "kind": pr.k, "name": self.prop_name(pr), "pos": pr.p, "face": pr.face, "dist_cm": h.dist_cm.round(),
                            "direction": direction_zh(p, pr.p) })
                }) }))
            }
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = r#"{
      "schema": 1, "cell_cm": 1000,
      "kinds": {
        "mirror": {"zh": "鏡子", "category": "mirror", "uses": ["look_mirror"]},
        "bed": {"zh": "床", "category": "furniture", "uses": ["sleep"]},
        "bench": {"zh": "長椅", "category": "furniture", "uses": ["sit"]},
        "vending": {"zh": "自動販賣機", "category": "shop", "uses": ["buy_drink"]}
      },
      "areas": [
        {"id": "r1-0101", "kind": "room", "type": "apartment", "name": "1樓住家01", "building": "R1", "floor": 1, "privacy": 2,
         "door": [1000, 1000, 0], "min": [1000, 1000, 0], "max": [1600, 1600, 320]},
        {"id": "r1-0102", "kind": "room", "type": "apartment", "name": "1樓住家02", "building": "R1", "floor": 1, "privacy": 2,
         "door": [1700, 1000, 0], "min": [1700, 1000, 0], "max": [2300, 1600, 320]},
        {"id": "building_r1", "kind": "building", "type": "住宅", "name": "住宅一號", "building": "R1", "door": [900, 1300, 0],
         "min": [900, 900, 0], "max": [2400, 1700, 2000]},
        {"id": "grove_00", "kind": "place", "type": "grove", "door": [5000, 5000, 0], "radius_cm": 1500},
        {"id": "r1-0201", "kind": "room", "type": "apartment", "name": "2樓住家01", "building": "R1", "floor": 2, "privacy": 2,
         "door": [1000, 1000, 360], "min": [1000, 1000, 360], "max": [1600, 1600, 680]}
      ],
      "props": [
        {"k": "bed", "p": [1200, 1200, 0], "a": 0, "face": 90},
        {"k": "mirror", "p": [1300, 1000, 130], "a": 0, "n": "床邊大鏡子"},
        {"k": "mirror", "p": [1400, 1000, 130], "a": 0},
        {"k": "bed", "p": [1900, 1200, 0], "a": 1},
        {"k": "vending", "p": [850, 1300, 0]},
        {"k": "bench", "p": [5200, 5000, 0], "a": 3},
        {"k": "bench", "p": [5200, 5000, 900]},
        {"k": "bed", "p": [1200, 1200, 360], "a": 4},
        {"k": "mirror", "p": [1300, 1000, 490], "a": 4},
        {"k": "mirror", "p": [950, 1300, 130]}
      ]
    }"#;

    fn idx() -> PropIndex {
        PropIndex::from_json(SAMPLE).unwrap()
    }

    #[test]
    fn inside_a_room_sees_only_that_room() {
        let i = idx();
        let hits = i.nearby(
            [1250.0, 1250.0, 0.0],
            &Query {
                radius_cm: 2000.0,
                ..Default::default()
            },
        );
        let kinds: Vec<&str> = hits
            .iter()
            .map(|h| i.props[h.index as usize].k.as_str())
            .collect();
        assert_eq!(kinds, vec!["bed", "mirror", "mirror"]);
        assert_eq!(
            i.areas[i.area_at([1250.0, 1250.0, 0.0]).unwrap() as usize].id,
            "r1-0101"
        );
    }

    #[test]
    fn outside_rooms_skips_furniture_behind_walls() {
        let i = idx();
        let hits = i.nearby(
            [900.0, 1250.0, 0.0],
            &Query {
                radius_cm: 2000.0,
                ..Default::default()
            },
        );
        let kinds: Vec<&str> = hits
            .iter()
            .map(|h| i.props[h.index as usize].k.as_str())
            .collect();
        assert_eq!(kinds, vec!["vending", "mirror"]);
        let all = i.nearby(
            [900.0, 1250.0, 0.0],
            &Query {
                radius_cm: 2000.0,
                through_walls: true,
                ..Default::default()
            },
        );
        assert_eq!(
            all.len(),
            6,
            "the corridor mirror counts, the floor above does not"
        );
    }

    #[test]
    fn other_levels_and_filters() {
        let i = idx();
        let hits = i.nearby(
            [5000.0, 5000.0, 0.0],
            &Query {
                radius_cm: 1000.0,
                ..Default::default()
            },
        );
        assert_eq!(hits.len(), 1, "the bench 9 m up is on another level");
        let none = i.nearby(
            [5000.0, 5000.0, 0.0],
            &Query {
                radius_cm: 1000.0,
                categories: vec!["mirror".into()],
                ..Default::default()
            },
        );
        assert!(none.is_empty());
        assert_eq!(
            i.areas[i.area_at([5000.0, 4000.0, 0.0]).unwrap() as usize].id,
            "grove_00"
        );
    }

    #[test]
    fn describe_groups_and_text() {
        let i = idx();
        let v = i
            .eval(
                "nearby_props",
                &json!({ "pos": [1250, 1250, 0], "radius_cm": 1000 }),
            )
            .unwrap();
        assert_eq!(v["here"]["id"], "r1-0101");
        let names: Vec<&str> = v["props"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["床", "床邊大鏡子", "鏡子"]);
        let text = v["text"].as_str().unwrap();
        assert!(
            text.starts_with("妳在「1樓住家01」（1 樓）。附近有：床（0.7 公尺）"),
            "{text}"
        );
        let n = i
            .eval(
                "nearest_prop",
                &json!({ "pos": [950, 1500, 0], "kinds": ["vending"], "radius_cm": 2000 }),
            )
            .unwrap();
        assert_eq!(n["prop"]["kind"], "vending");
        assert_eq!(n["prop"]["direction"], "西南邊");
        assert!(i.eval("unknown", &json!({})).is_none());
    }

    #[test]
    fn storeys_stay_apart() {
        let i = idx();
        // in the 1F room: the 2F room's bed and mirror right above are not hers
        let v = i
            .eval(
                "nearby_props",
                &json!({ "pos": [1250, 1250, 0], "radius_cm": 1000 }),
            )
            .unwrap();
        assert_eq!(v["props"].as_array().unwrap().len(), 3);
        assert!(
            v["areas"]
                .as_array()
                .unwrap()
                .iter()
                .all(|a| a["id"] != "r1-0201"),
            "{}",
            v["areas"]
        );
        // in the 2F room: its own bed and mirror, nothing from 1F; the floor is 2
        let v = i
            .eval(
                "nearby_props",
                &json!({ "pos": [1250, 1250, 360], "radius_cm": 1000 }),
            )
            .unwrap();
        assert_eq!(v["here"]["id"], "r1-0201");
        assert_eq!(v["floor"], 2);
        let names: Vec<&str> = v["props"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p["name"].as_str().unwrap())
            .collect();
        assert_eq!(names, vec!["床", "鏡子"]);
        // the 1F corridor mirror is not seen from the 2F corridor above it
        let up = i.nearby(
            [950.0, 1250.0, 360.0],
            &Query {
                radius_cm: 2000.0,
                ..Default::default()
            },
        );
        assert!(up.is_empty(), "{up:?}");
        assert_eq!(
            i.floor_at([950.0, 1250.0, 0.0]),
            None,
            "corridor at ground: no room below to name the floor"
        );
    }

    #[test]
    fn compass() {
        assert_eq!(direction_zh([0.0, 0.0, 0.0], [1000.0, 0.0, 0.0]), "北邊");
        assert_eq!(direction_zh([0.0, 0.0, 0.0], [0.0, 1000.0, 0.0]), "東邊");
        assert_eq!(
            direction_zh([0.0, 0.0, 0.0], [-1000.0, -1000.0, 0.0]),
            "西南邊"
        );
    }

    /// The real city index, when it has been built on this machine.
    #[test]
    fn real_city_index() {
        let path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../output/street-social-city-production/places-v1/props.json"
        );
        let Ok(i) = PropIndex::load(path) else { return };
        assert!(i.props.len() > 10_000);
        for p in &i.props {
            assert!(i.kinds.contains_key(&p.k), "{}", p.k);
            if let Some(a) = p.a {
                assert!((a as usize) < i.areas.len());
            }
        }
        let t = std::time::Instant::now();
        let mut n = 0;
        for k in 0..2000 {
            let p = &i.props[(k * 7919) % i.props.len()];
            n += i
                .nearby(
                    p.p,
                    &Query {
                        radius_cm: 2000.0,
                        ..Default::default()
                    },
                )
                .len();
        }
        let per = t.elapsed().as_secs_f64() * 1e6 / 2000.0;
        assert!(n > 0);
        eprintln!("2000 queries of 20 m: {per:.1} us each, {n} hits");
    }
}
