//! Getting about town (R6-203): the city is a kilometre across and two people walk it at 2.75 m a game minute, so the
//! dorm to the convenience store was four hours on foot. The bus (cheap, between its fixed stops) and the taxi (dearer,
//! to the door) take them there; the clock and the walking pace stay as they are. Amounts are written in yuan and come
//! out in the request's region (`region::fixed`: a region has its own fares); the two of them ride together.
use serde_json::{json, Value};

/// The day plans' walk, two together (OKStreetSocialOuting.inl counts the same).
pub const WALK_M_PER_MIN: f64 = 2.75;
/// A town bus between stops, stops and lights counted.
const BUS_M_PER_MIN: f64 = 250.0;
/// Half the time between two buses, on average.
const BUS_WAIT_MIN: f64 = 6.0;
/// A taxi through town.
const TAXI_M_PER_MIN: f64 = 400.0;
/// Hailing one, or the one called coming round.
const TAXI_WAIT_MIN: f64 = 3.0;
/// Roads are not straight lines: a ride's length from the stops' straight distance.
const ROAD_FACTOR: f64 = 1.3;
/// Fares in yuan (2010): a bus ride a person; a taxi's flag fall (its first 3 km) and each kilometre after.
const BUS_FARE: i64 = 1;
const TAXI_FLAG: i64 = 10;
const TAXI_FLAG_KM: f64 = 3.0;
const TAXI_PER_KM: i64 = 2;
/// Under this many minutes on foot no ride is worth it.
const RIDE_FROM_MIN: i64 = 15;

/// The bus stops: by the door of these places, one town line through campus, the shopping streets, the station and
/// the south (the map has shelters only by the station). Unreal places them at the places' doors.
pub const STOPS: [&str; 16] = [
    "boys_dorm", "girls_dorm", "campus_sports", "cafeteria", "campus_ee", "library", "campus_gate", "bookstore",
    "fastfood", "park", "department", "civic", "station", "beach", "zoo", "amusement",
];

fn num(v: &Value, k: &str) -> f64 {
    v.get(k).and_then(Value::as_f64).unwrap_or(0.0)
}

fn point(v: &Value, k: &str) -> Option<(f64, f64)> {
    let a = v.get(k)?.as_array()?;
    Some((a.first()?.as_f64()?, a.get(1)?.as_f64()?))
}

fn dist(a: (f64, f64), b: (f64, f64)) -> f64 {
    ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt()
}

fn minutes(m: f64, per_min: f64) -> i64 {
    (m / per_min).ceil() as i64
}

/// A taxi's fare for a ride of this many metres (yuan in, region money out).
fn taxi_fare(ride_m: f64) -> i64 {
    let flag = crate::region::fixed("taxi_flag", TAXI_FLAG);
    let extra_km = ((ride_m / 1000.0) - TAXI_FLAG_KM).max(0.0).ceil() as i64;
    flag + extra_km * crate::region::fixed("taxi_per_km", TAXI_PER_KM)
}

/// Request: walk_m (the walking route's length, m), from [x,y] and to [x,y] (m), stops [{id, x, y}] (m: the stops'
/// places, as Unreal found them), people (riding together, default 1), cash (his wallet, region money; optional).
/// Answer: walk {minutes}; bus {fare, minutes, board, alight, walk_to_minutes, ride_minutes, walk_from_minutes} or null;
/// taxi {fare, minutes, ride_minutes} or null; suggest ("walk" | "bus" | "taxi"): the quickest of what saves time and
/// what he can pay, the bus when it is not much slower than the taxi.
fn quote(r: &Value) -> Result<Value, String> {
    let walk_m = num(r, "walk_m").max(0.0);
    let walk_min = minutes(walk_m, WALK_M_PER_MIN);
    let people = r.get("people").and_then(Value::as_i64).unwrap_or(1).max(1);
    let cash = r.get("cash").and_then(Value::as_i64);
    let (Some(from), Some(to)) = (point(r, "from"), point(r, "to")) else {
        return Ok(json!({"walk": {"minutes": walk_min}, "bus": null, "taxi": null, "suggest": "walk"}));
    };
    let far = walk_min >= RIDE_FROM_MIN;
    let taxi = far.then(|| {
        // By road, never longer than the walking route itself.
        let ride_m = (dist(from, to) * ROAD_FACTOR).min(walk_m.max(dist(from, to)));
        let ride = minutes(ride_m, TAXI_M_PER_MIN);
        json!({"fare": taxi_fare(ride_m), "minutes": TAXI_WAIT_MIN as i64 + ride, "ride_minutes": ride})
    });
    // The bus: on at the stop nearest him, off at the one nearest where they go (on foot to and from it).
    let stops: Vec<(String, (f64, f64))> = r
        .get("stops")
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(|s| Some((s.get("id")?.as_str()?.to_string(), (s.get("x")?.as_f64()?, s.get("y")?.as_f64()?)))).collect())
        .unwrap_or_default();
    let nearest = |p: (f64, f64)| stops.iter().min_by(|a, b| dist(a.1, p).total_cmp(&dist(b.1, p)));
    let bus = match (far, nearest(from), nearest(to)) {
        (true, Some(on), Some(off)) if on.0 != off.0 => {
            let to_stop = minutes(dist(from, on.1) * ROAD_FACTOR, WALK_M_PER_MIN);
            let from_stop = minutes(dist(off.1, to) * ROAD_FACTOR, WALK_M_PER_MIN);
            let ride = minutes(dist(on.1, off.1) * ROAD_FACTOR, BUS_M_PER_MIN);
            let total = to_stop + BUS_WAIT_MIN as i64 + ride + from_stop;
            // Only when it saves a good part of the walk.
            (total * 10 < walk_min * 8).then(|| {
                json!({"fare": crate::region::fixed("bus_fare", BUS_FARE) * people, "minutes": total, "board": on.0, "alight": off.0,
                       "walk_to_minutes": to_stop, "ride_minutes": ride, "walk_from_minutes": from_stop})
            })
        }
        _ => None,
    };
    let affordable = |o: &Option<Value>| o.as_ref().filter(|v| cash.is_none_or(|c| v["fare"].as_i64().unwrap_or(0) <= c)).cloned();
    let (bus_ok, taxi_ok) = (affordable(&bus), affordable(&taxi));
    let mins = |o: &Option<Value>| o.as_ref().and_then(|v| v["minutes"].as_i64());
    let suggest = match (mins(&bus_ok), mins(&taxi_ok)) {
        (Some(b), Some(t)) => if b <= t + 20 { "bus" } else { "taxi" },
        (Some(_), None) => "bus",
        (None, Some(t)) if t * 2 <= walk_min => "taxi",
        _ => "walk",
    };
    Ok(json!({"walk": {"minutes": walk_min}, "bus": bus, "taxi": taxi, "suggest": suggest}))
}

pub fn eval(kind: &str, r: &Value) -> Option<Result<Value, String>> {
    match kind {
        "transit_stops" => Some(Ok(json!({"stops": STOPS}))),
        "transit_quote" => Some(quote(r)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stops() -> Value {
        json!([{"id": "boys_dorm", "x": 932.0, "y": 561.0}, {"id": "bookstore", "x": 471.0, "y": 287.0}, {"id": "girls_dorm", "x": 932.0, "y": 321.0}])
    }

    #[test]
    fn a_short_walk_needs_no_ride() {
        let q = quote(&json!({"walk_m": 25.0, "from": [930.0, 560.0], "to": [940.0, 540.0], "stops": stops()})).unwrap();
        assert_eq!(q["walk"]["minutes"], 10);
        assert!(q["bus"].is_null() && q["taxi"].is_null());
        assert_eq!(q["suggest"], "walk");
    }

    #[test]
    fn across_town_the_bus_and_the_taxi_save_hours() {
        // The boys' dorm to the convenience store beside the bookstore: about 650 m of road, four hours on foot.
        let q = quote(&json!({"walk_m": 660.0, "from": [931.0, 560.0], "to": [470.0, 274.0], "stops": stops(), "people": 2})).unwrap();
        assert!(q["walk"]["minutes"].as_i64().unwrap() > 200);
        let taxi = &q["taxi"];
        assert!(taxi["minutes"].as_i64().unwrap() < 10, "{q}");
        assert_eq!(taxi["fare"], TAXI_FLAG);
        let bus = &q["bus"];
        assert_eq!(bus["board"], "boys_dorm");
        assert_eq!(bus["alight"], "bookstore");
        assert_eq!(bus["fare"], BUS_FARE * 2, "two of them, a fare each");
        assert!(bus["minutes"].as_i64().unwrap() < 60, "{q}");
        assert_eq!(q["suggest"], "bus");
    }

    #[test]
    fn far_from_any_stop_the_taxi_is_the_way() {
        // From the middle of nowhere: the walk to the nearest stop is most of the walk, no bus.
        let q = quote(&json!({"walk_m": 300.0, "from": [700.0, 1080.0], "to": [717.0, 1144.0], "stops": stops()})).unwrap();
        assert!(q["bus"].is_null(), "{q}");
        assert_eq!(q["suggest"], "taxi");
    }

    #[test]
    fn what_he_cannot_pay_is_not_suggested() {
        let q = quote(&json!({"walk_m": 660.0, "from": [931.0, 560.0], "to": [470.0, 274.0], "stops": stops(), "people": 2, "cash": 0})).unwrap();
        assert_eq!(q["suggest"], "walk");
        assert!(!q["taxi"].is_null(), "still quoted, only not suggested");
    }

    #[test]
    fn fares_are_the_regions_own() {
        let _scope = crate::tr::scope("zh-TW", "TW");
        let q = quote(&json!({"walk_m": 660.0, "from": [931.0, 560.0], "to": [470.0, 274.0], "stops": stops(), "people": 2})).unwrap();
        assert_eq!(q["taxi"]["fare"], 70);
        assert_eq!(q["bus"]["fare"], 30);
        // A long ride pays its kilometres past the flag fall.
        assert_eq!(taxi_fare(4200.0), 70 + 2 * 20);
    }
}
