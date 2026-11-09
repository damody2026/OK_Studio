use super::*;
use std::collections::HashMap;
struct Field {
    w: usize,
    data: Vec<f64>,
}
impl Field {
    fn at(&self, x: f64, y: f64) -> f64 {
        let x = x.clamp(0., 1100.);
        let y = (1100. - y).clamp(0., 1100.);
        let i = x.floor() as usize;
        let j = y.floor() as usize;
        let u = x - i as f64;
        let v = y - j as f64;
        let f = |i: usize, j: usize| self.data[j.min(self.w - 1) * self.w + i.min(self.w - 1)];
        f(i, j) * (1. - u) * (1. - v)
            + f(i + 1, j) * u * (1. - v)
            + f(i, j + 1) * (1. - u) * v
            + f(i + 1, j + 1) * u * v
    }
}
fn npy(archive: &mut zip::ZipArchive<fs::File>, name: &str) -> R<Field> {
    let mut b = vec![];
    archive.by_name(name)?.read_to_end(&mut b)?;
    assert_eq!(&b[..6], b"\x93NUMPY");
    let (h, start) = if b[6] == 1 {
        (u16::from_le_bytes(b[8..10].try_into()?) as usize, 10)
    } else {
        (u32::from_le_bytes(b[8..12].try_into()?) as usize, 12)
    };
    let header = std::str::from_utf8(&b[start..start + h])?;
    assert!(header.contains("False"));
    let raw = &b[start + h..];
    let data: Vec<f64> = if header.contains("f4") {
        raw.chunks_exact(4)
            .map(|v| f32::from_le_bytes(v.try_into().unwrap()) as f64)
            .collect()
    } else if header.contains("f8") {
        raw.chunks_exact(8)
            .map(|v| f64::from_le_bytes(v.try_into().unwrap()))
            .collect()
    } else {
        raw.iter().map(|x| *x as f64).collect()
    };
    let w = (data.len() as f64).sqrt() as usize;
    assert_eq!(w * w, data.len());
    assert_eq!(w, 1101);
    Ok(Field { w, data })
}
fn v(v: &Value, k: usize) -> f64 {
    v[k].as_f64().unwrap()
}
pub fn terrain_height(root: &Path, x: f64, y: f64) -> R<f64> {
    let path=root.join("output/street-social-city-production/world-ground-v1/world-field.npz");
    let mut zip=zip::ZipArchive::new(fs::File::open(path)?)?;
    Ok(npy(&mut zip,"height_map.npy")?.at(x,y))
}
fn dist(x: f64, y: f64, a: [f64; 2], b: [f64; 2]) -> f64 {
    let d = [b[0] - a[0], b[1] - a[1]];
    let t = (((x - a[0]) * d[0] + (y - a[1]) * d[1]) / (d[0] * d[0] + d[1] * d[1]).max(1e-9))
        .clamp(0., 1.);
    (x - a[0] - t * d[0]).hypot(y - a[1] - t * d[1])
}
pub fn place(root: &Path, assets: &[Value]) -> R<Value> {
    place_regions(root, assets, false)
}
pub fn native(root: &Path) -> R<()> {
    let cat = read_json(
        &root.join("output/street-social-city-production/resort-streetscape-v1/catalog.json"),
    )?;
    let layout = place_regions(root, cat["assets"].as_array().unwrap(), true)?;
    write(
        &root.join("output/street-social-city-production/resort-native-v1/placement.json"),
        &layout,
    )?;
    println!(
        "Prepared {} region-aware native placements",
        layout["instances"].as_array().unwrap().len()
    );
    Ok(())
}
fn place_regions(root: &Path, assets: &[Value], regional: bool) -> R<Value> {
    let base = root.join("output/street-social-city-production");
    let mut zip = zip::ZipArchive::new(fs::File::open(
        base.join("world-ground-v1/world-field.npz"),
    )?)?;
    let height = npy(&mut zip, "height_map.npy")?;
    let water = npy(&mut zip, "water_map.npy")?;
    let audit =
        read_json(&root.join("Docs/StreetSocialCity/production/building-floor-audit.json"))?;
    let plan = read_json(&base.join("streetscape-v1/plan.json"))?;
    let ground = read_json(&base.join("world-ground-v1/ground-plan.json"))?;
    let facilities = read_json(&base.join("world-completion-v1/outdoor/assembly-report.json"))?;
    let campus = read_json(&base.join("campus-v1/outdoor/assembly.json"))?;
    let campus_sizes = read_json(&base.join("campus-v1/outdoor/acceptance.json"))?;
    let mut obstacles: HashMap<(i32, i32), Vec<(f64, f64, f64)>> = HashMap::new();
    for p in plan["instances"].as_array().unwrap() {
        let x = v(&p["position_m"], 0);
        let y = v(&p["position_m"], 1);
        let r = p["footprint_radius_m"].as_f64().unwrap_or(1.);
        obstacles
            .entry(((x / 10.) as i32, (y / 10.) as i32))
            .or_default()
            .push((x, y, r));
    }
    let mut roads = vec![];
    for r in ground["roads"].as_array().unwrap() {
        for pair in r["points_map_m"].as_array().unwrap().windows(2) {
            let a = [v(&pair[0], 0), 1100. - v(&pair[0], 1)];
            let b = [v(&pair[1], 0), 1100. - v(&pair[1], 1)];
            roads.push((a, b, r["width_m"].as_f64().unwrap()));
        }
    }
    let mut candidates = vec![];
    for ix in 2..218 {
        for iy in 2..218 {
            let x = ix as f64 * 5.;
            let y = iy as f64 * 5.;
            if water.at(x, y) > 0.001 {
                continue;
            }
            let near = roads
                .iter()
                .map(|(a, b, w)| dist(x, y, *a, *b) - w / 2.)
                .fold(f64::MAX, f64::min);
            if near < 1. || near > 16. {
                continue;
            }
            candidates.push((x, y, near));
        }
    }
    let targets = [
        [760., 270.],
        [780., 220.],
        [610., 260.],
        [800., 315.],
        [590., 200.],
        [960., 320.],
        [600., 160.],
        [980., 180.],
        [730., 210.],
        [950., 430.],
    ];
    let mut selected = vec![];
    let mut occupied: Vec<(f64, f64, f64)> = vec![];
    let mut checks = 0usize;
    for copy in 0..3 {
        for (i, a) in assets.iter().enumerate() {
            let b = &a["bounds_m"];
            let radius = (v(&b[1], 0).abs().max(v(&b[0], 0).abs()))
                .hypot(v(&b[1], 1).abs().max(v(&b[0], 1).abs()))
                + 0.25;
            let region_targets = [
                [[760., 270.], [760., 875.], [990., 180.]],
                [[780., 220.], [600., 700.], [1010., 340.]],
                [[610., 260.], [430., 430.], [100., 180.]],
                [[800., 315.], [405., 780.], [990., 190.]],
                [[590., 200.], [545., 800.], [706., 844.]],
                [[960., 320.], [842., 630.], [760., 875.]],
                [[600., 160.], [420., 620.], [990., 310.]],
                [[980., 180.], [1040., 270.], [1030., 340.]],
                [[730., 210.], [50., 180.], [700., 545.]],
                [[950., 430.], [600., 700.], [620., 200.]],
            ];
            let region_names = [
                ["hotel-garden", "campus-lake", "bay-rest"],
                ["hotel-garden", "campus-garden", "bay-camp"],
                ["hotel-dining", "shop-dining", "transit-dining"],
                ["hotel-wellness", "sports-entry", "bay-service"],
                ["city-garden", "campus-reading", "campus-active"],
                ["bay-walk", "riverside-walk", "campus-lake"],
                ["city-play", "campus-sports", "bay-play"],
                ["bay-beach", "bay-marina", "bay-camp"],
                ["hotel-service", "transit-service", "campus-gate"],
                ["bay-landmark", "campus-garden", "city-stage"],
            ];
            let t = if regional {
                region_targets[i / 10][copy]
            } else {
                targets[i / 10]
            };
            let mut sorted = candidates.clone();
            sorted.sort_by(|a, b| {
                let score = |p: &(f64, f64, f64)| {
                    (p.0 - t[0]).hypot(p.1 - t[1])
                        + p.2 * 4.
                        + copy as f64 * ((p.0 - t[0]).sin() * 6.)
                };
                score(a).total_cmp(&score(b))
            });
            let mut found = None;
            for (x, y, near) in sorted {
                checks += 1;
                if near < radius + 0.8 {
                    continue;
                }
                if plan["entrance_keepouts_m"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|p| (x - v(p, 0)).hypot(y - v(p, 1)) < 4. + radius)
                {
                    continue;
                }
                if audit["buildings"].as_array().unwrap().iter().any(|b| {
                    (x - v(&b["world_position_m"], 0)).abs()
                        < v(&b["footprint_m"], 0) / 2. + radius + 2.
                        && (y - v(&b["world_position_m"], 1)).abs()
                            < v(&b["footprint_m"], 1) / 2. + radius + 2.
                }) {
                    continue;
                }
                if facilities["nodes"].as_array().unwrap().iter().any(|b| {
                    (x - v(&b["origin"], 0)).abs() < v(&b["size"], 0) / 2. + radius + 1.
                        && (y - v(&b["origin"], 1)).abs() < v(&b["size"], 1) / 2. + radius + 1.
                }) {
                    continue;
                }
                if regional
                    && campus["assets"].as_array().unwrap().iter().any(|b| {
                        let size = campus_sizes["assets"]
                            .as_array()
                            .unwrap()
                            .iter()
                            .find(|s| s["id"] == b["id"]);
                        size.map(|s| {
                            (x - v(&b["position_m"], 0)).abs() < v(&s["size"], 0) / 2. + radius + 1.
                                && (y - v(&b["position_m"], 1)).abs()
                                    < v(&s["size"], 1) / 2. + radius + 1.
                        })
                        .unwrap_or(false)
                    })
                {
                    continue;
                }
                if occupied
                    .iter()
                    .any(|(xx, yy, r)| (x - xx).hypot(y - yy) < radius + r + 1.)
                {
                    continue;
                }
                let gx = (x / 10.) as i32;
                let gy = (y / 10.) as i32;
                let mut hit = false;
                for dx in -2..=2 {
                    for dy in -2..=2 {
                        if let Some(obs) = obstacles.get(&(gx + dx, gy + dy)) {
                            if obs
                                .iter()
                                .any(|(xx, yy, r)| (x - xx).hypot(y - yy) < radius + r + 0.5)
                            {
                                hit = true;
                            }
                        }
                    }
                }
                if hit {
                    continue;
                }
                let mut hs = vec![];
                let mut wet = false;
                for dx in [-radius, 0., radius] {
                    for dy in [-radius, 0., radius] {
                        hs.push(height.at(x + dx, y + dy));
                        wet |= water.at(x + dx, y + dy) > 0.001;
                    }
                }
                let min = hs.iter().copied().fold(f64::MAX, f64::min);
                let max = hs.iter().copied().fold(f64::MIN, f64::max);
                if wet || max - min > 0.035 {
                    continue;
                }
                found = Some((x, y, max));
                break;
            }
            let (x, y, z) = found.ok_or(format!("No safe site for {}", a["name"]))?;
            occupied.push((x, y, radius));
            let mut yaw = if copy % 2 == 0 { 0. } else { 180. };
            if regional {
                // The local front of seating and counters is -Y. Face the nearest route.
                if matches!(
                    i,
                    0 | 1 | 3 | 4 | 6 | 8 | 9 | 23 | 24 | 25 | 29 | 32 | 80 | 81 | 82 | 84 | 89
                ) {
                    let (aa, bb, _) = roads
                        .iter()
                        .min_by(|(a, b, _), (c, d, _)| {
                            dist(x, y, *a, *b).total_cmp(&dist(x, y, *c, *d))
                        })
                        .unwrap();
                    let dx = bb[0] - aa[0];
                    let dy = bb[1] - aa[1];
                    let u = (((x - aa[0]) * dx + (y - aa[1]) * dy) / (dx * dx + dy * dy).max(1e-9))
                        .clamp(0., 1.);
                    yaw = (aa[1] + u * dy - y).atan2(aa[0] + u * dx - x).to_degrees() + 90.;
                }
            }
            selected.push(json!({"id":format!("RESORT-{:04}",selected.len()+1),"asset_index":i,"asset":a["id"],"position_m":[x,y,z+0.002],"yaw_deg":yaw,"scale":[1,1,1],"preset":(i+copy)%6,"protected_radius_m":radius,"category":a["category"],"zone":if regional{region_names[i/10][copy]}else{"portable"},"zone_anchor_m":t}));
        }
    }
    Ok(
        json!({"schema":1,"axes":"east,north,up metres; GLBs exported Y-up","instances":selected,"checks":{"candidate_checks":checks,"buildings":true,"all_road_widths_plus_clearance":true,"existing_outdoor_facilities":true,"existing_props":true,"pairwise_clearance_m":1,"max_terrain_delta_m":0.035,"water_footprint_samples":9},"source_hashes":{"height_field":sha(&base.join("world-ground-v1/world-field.npz"))?,"building_audit":sha(&root.join("Docs/StreetSocialCity/production/building-floor-audit.json"))?,"street_layout":sha(&base.join("streetscape-v1/plan.json"))?},"native_project_modified":false}),
    )
}
