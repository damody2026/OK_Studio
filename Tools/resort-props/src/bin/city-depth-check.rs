//! Independent world-space triangle audit. UE centimetres; no geometry inferred from AABBs.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    fs,
    io::{BufWriter, Write},
    path::{Path, PathBuf},
};
type V = [f64; 3];
fn sub(a: V, b: V) -> V {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn dot(a: V, b: V) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross(a: V, b: V) -> V {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}
fn unit(a: V) -> V {
    let d = dot(a, a).sqrt();
    [a[0] / d, a[1] / d, a[2] / d]
}
fn transform(p: V, m: &[Value]) -> V {
    let mut q = [0.; 3];
    for j in 0..3 {
        q[j] = p[0] * m[j].as_f64().unwrap()
            + p[1] * m[4 + j].as_f64().unwrap()
            + p[2] * m[8 + j].as_f64().unwrap()
            + m[12 + j].as_f64().unwrap();
    }
    q
}
#[derive(Clone)]
struct Mesh {
    p: Vec<V>,
    tris: Vec<[usize; 3]>,
    ids: Vec<i32>,
    slots: Vec<usize>,
}
fn u32at(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes(b[i..i + 4].try_into().unwrap())
}
fn mesh(path: &Path) -> Mesh {
    let b = fs::read(path).unwrap();
    let version = u32at(&b, 0);
    assert!(version == 0x43445931 || version == 0x43445932);
    let nv = u32at(&b, 4) as usize;
    let nt = u32at(&b, 8) as usize;
    assert_eq!(
        b.len(),
        12 + nv * 12 + nt * if version == 0x43445932 { 20 } else { 16 }
    );
    let mut p = Vec::with_capacity(nv);
    for i in 0..nv {
        let mut v = [0.; 3];
        for k in 0..3 {
            v[k] = f32::from_bits(u32at(&b, 12 + i * 12 + k * 4)) as f64;
        }
        p.push(v);
    }
    let start = 12 + nv * 12;
    let tris = (0..nt)
        .map(|i| {
            [
                u32at(&b, start + i * 12) as usize,
                u32at(&b, start + i * 12 + 4) as usize,
                u32at(&b, start + i * 12 + 8) as usize,
            ]
        })
        .collect();
    let ids = (0..nt)
        .map(|i| u32at(&b, start + nt * 12 + i * 4) as i32)
        .collect();
    let slots = (0..nt)
        .map(|i| {
            if version == 0x43445932 {
                u32at(&b, start + nt * 16 + i * 4) as usize
            } else {
                0
            }
        })
        .collect();
    Mesh {
        p,
        tris,
        ids,
        slots,
    }
}
#[derive(Clone)]
struct Tri {
    p: [V; 3],
    n: V,
    d: f64,
    lo: V,
    hi: V,
    area: f64,
    instance: usize,
    id: i32,
    lod: i64,
    back: bool,
    two_sided: bool,
    depth_writer: bool,
    slot: usize,
}
fn tri(p: [V; 3], instance: usize, id: i32, lod: i64) -> Option<Tri> {
    let a = cross(sub(p[1], p[0]), sub(p[2], p[0]));
    let area = dot(a, a).sqrt() * 0.5;
    if !area.is_finite() || area < 0.02 {
        return None;
    }
    let mut n = unit(a);
    let k = (0..3)
        .max_by(|a, b| n[*a].abs().total_cmp(&n[*b].abs()))
        .unwrap();
    let back = n[k] < 0.;
    if back {
        n = [-n[0], -n[1], -n[2]];
    }
    let mut lo = p[0];
    let mut hi = p[0];
    for v in &p[1..] {
        for k in 0..3 {
            lo[k] = lo[k].min(v[k]);
            hi[k] = hi[k].max(v[k]);
        }
    }
    Some(Tri {
        d: dot(n, p[0]),
        p,
        n,
        lo,
        hi,
        area,
        instance,
        id,
        lod,
        back,
        two_sided: false,
        depth_writer: true,
        slot: 0,
    })
}
fn area2(p: &[[f64; 2]]) -> f64 {
    (0..p.len())
        .map(|i| {
            let j = (i + 1) % p.len();
            p[i][0] * p[j][1] - p[j][0] * p[i][1]
        })
        .sum::<f64>()
        * 0.5
}
fn intersect_polygon(a: &Tri, b: &Tri) -> (Vec<[f64;2]>,usize) {
    let drop = (0..3)
        .max_by(|x, y| a.n[*x].abs().total_cmp(&a.n[*y].abs()))
        .unwrap();
    let ks: Vec<_> = (0..3).filter(|k| *k != drop).collect();
    let cv = |p: V| [p[ks[0]], p[ks[1]]];
    let mut poly: Vec<_> = a.p.iter().map(|p| cv(*p)).collect();
    let mut clip: Vec<_> = b.p.iter().map(|p| cv(*p)).collect();
    if area2(&clip) < 0. {
        clip.reverse();
    }
    for k in 0..3 {
        let v = clip[k];
        let w = clip[(k + 1) % 3];
        let side = |q: [f64; 2]| (w[0] - v[0]) * (q[1] - v[1]) - (w[1] - v[1]) * (q[0] - v[0]);
        let input = poly;
        poly = vec![];
        if input.is_empty() {
            return (vec![],drop);
        }
        let mut previous = *input.last().unwrap();
        let mut sp = side(previous);
        for current in input {
            let sc = side(current);
            if (sc >= 0.) != (sp >= 0.) {
                let t = sp / (sp - sc);
                poly.push([
                    previous[0] + t * (current[0] - previous[0]),
                    previous[1] + t * (current[1] - previous[1]),
                ]);
            }
            if sc >= 0. {
                poly.push(current);
            }
            previous = current;
            sp = sc;
        }
    }
    (poly,drop)
}
fn intersect_area(a: &Tri, b: &Tri) -> f64 {
    let (poly,drop)=intersect_polygon(a,b);
    area2(&poly).abs() / a.n[drop].abs().max(1e-12)
}
fn overlap_center(a:&Tri,b:&Tri)->V {
    let (poly,drop)=intersect_polygon(a,b);assert!(!poly.is_empty());
    let ks:Vec<_>=(0..3).filter(|k|*k!=drop).collect();let mut p=[0.;3];
    for q in &poly { p[ks[0]]+=q[0]/poly.len() as f64;p[ks[1]]+=q[1]/poly.len() as f64; }
    p[drop]=(a.d-a.n[ks[0]]*p[ks[0]]-a.n[ks[1]]*p[ks[1]])/a.n[drop];p
}
fn test(a: &Tri, b: &Tri) -> Option<f64> {
    if !a.depth_writer || !b.depth_writer {
        return None;
    }
    if a.back != b.back && !a.two_sided && !b.two_sided {
        return None;
    }
    if a.instance == b.instance && a.id == b.id {
        return None;
    }
    if dot(a.n, b.n) < 0.999999 {
        return None;
    }
    if a.p.iter().any(|p| (dot(b.n, *p) - b.d).abs() > 0.20)
        || b.p.iter().any(|p| (dot(a.n, *p) - a.d).abs() > 0.20)
    {
        return None;
    }
    if (0..3).any(|k| a.lo[k] > b.hi[k] + 0.2 || b.lo[k] > a.hi[k] + 0.2) {
        return None;
    }
    let ar = intersect_area(a, b);
    if ar > 1.0 && ar > a.area.min(b.area) * 1e-5 {
        Some(ar)
    } else {
        None
    }
}
type Cell = (usize, i64, i32, i32, i32);
// A plane distance measured at world origin is unstable for nearly parallel
// triangles far from origin. Bin its intercept relative to each spatial cell.
// Axis normalization plus a 3-bucket neighborhood conservatively covers the
// angular/distance tolerances; 0.4 cm padded bounds cover cell boundaries.
fn visit_cells(t: &Tri, mut f: impl FnMut(Cell)) -> bool {
    let lo = t.lo.map(|x| ((x - 0.4) / 500.).floor() as i32);
    let hi = t.hi.map(|x| ((x + 0.4) / 500.).floor() as i32);
    let count =
        (hi[0] - lo[0] + 1) as i64 * (hi[1] - lo[1] + 1) as i64 * (hi[2] - lo[2] + 1) as i64;
    if count > 4096 {
        return false;
    }
    for x in lo[0]..=hi[0] {
        for y in lo[1]..=hi[1] {
            for z in lo[2]..=hi[2] {
                let c = [
                    (x as f64 + 0.5) * 500.,
                    (y as f64 + 0.5) * 500.,
                    (z as f64 + 0.5) * 500.,
                ];
                for axis in 0..3 {
                    if t.n[axis].abs() < 0.55 {
                        continue;
                    }
                    let intercept = (t.d - dot(t.n, c)) / t.n[axis];
                    f((axis, (intercept / 2.).round() as i64, x, y, z));
                }
            }
        }
    }
    true
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let folder = PathBuf::from(args.get(1).expect("scene export directory"));
    let output = PathBuf::from(args.get(2).expect("report JSON"));
    let streaming = args.iter().any(|x| x == "--stream");
    let conflict_path = output.with_extension("conflicts.jsonl");
    let mut writer = if streaming {
        Some(BufWriter::new(fs::File::create(&conflict_path).unwrap()))
    } else {
        None
    };
    let scene_bytes = fs::read(folder.join("scene.json")).unwrap();
    let metadata_sha256 = format!("{:x}", Sha256::digest(&scene_bytes));
    let scene: Value = serde_json::from_slice(&scene_bytes).unwrap();
    assert!(
        scene["format"].as_str().unwrap_or("").starts_with("CDY2"),
        "Fresh CDY2 export with per-triangle material slots required"
    );
    let instances = scene["instances"].as_array().unwrap();
    let meshes = scene["meshes"].as_array().unwrap();
    let mut loaded = HashMap::new();
    let mut conflicts = vec![];
    let mut exact_count = 0usize;
    let mut candidate_count = 0usize;
    let mut tests = 0u64;
    let mut examined = 0u64;
    let mut skipped = vec![];
    for level in 0..3 {
        let mut ts: Vec<Tri> = vec![];
        for (ii, inst) in instances.iter().enumerate() {
            let label = inst["actor"].as_str().unwrap();
            if label.starts_with("ResortMoon")
                || label == "ResortNightSky"
                || label.contains("SkySphere")
            {
                if level == 0 {
                    skipped.push(json!({"actor":label,"reason":"curved celestial surface;separate angular/depth-layer audit"}));
                }
                continue;
            }
            let mid = inst["mesh"].as_u64().unwrap() as usize;
            let lods = meshes[mid]["lods"].as_array().unwrap();
            if lods.is_empty() {
                continue;
            }
            let l = lods
                .iter()
                .rev()
                .find(|l| l["lod"].as_i64().unwrap() <= level)
                .unwrap_or(&lods[0]);
            let file = l["file"].as_str().unwrap();
            let m = loaded
                .entry(file.to_string())
                .or_insert_with(|| mesh(&folder.join(file)));
            let mat = inst["matrix"].as_array().unwrap();
            let p: Vec<_> = m.p.iter().map(|p| transform(*p, mat)).collect();
            for (ti, t) in m.tris.iter().enumerate() {
                if let Some(mut t) = tri(
                    [p[t[0]], p[t[1]], p[t[2]]],
                    ii,
                    m.ids[ti],
                    l["lod"].as_i64().unwrap(),
                ) {
                    let slot = m.slots[ti];
                    t.slot = slot;
                    t.two_sided = inst["two_sided_by_slot"][slot]
                        .as_bool()
                        .unwrap_or(inst["two_sided"].as_bool().unwrap_or(true));
                    let blend = inst["blend_modes"][slot].as_i64().unwrap_or(0);
                    t.depth_writer = blend == 0 || blend == 1;
                    let rows: Vec<V> = (0..3)
                        .map(|r| {
                            [
                                mat[r * 4].as_f64().unwrap(),
                                mat[r * 4 + 1].as_f64().unwrap(),
                                mat[r * 4 + 2].as_f64().unwrap(),
                            ]
                        })
                        .collect();
                    if dot(rows[0], cross(rows[1], rows[2])) < 0. {
                        t.back = !t.back;
                    }
                    ts.push(t);
                }
            }
        }
        examined += ts.len() as u64;
        eprintln!("LOD{}: {} world triangles", level, ts.len());
        let mut grid: HashMap<Cell, Vec<usize>> = HashMap::new();
        let mut large: Vec<usize> = vec![];
        let mut exact: HashMap<[[i64; 3]; 3], usize> = HashMap::new();
        for i in 0..ts.len() {
            let a = &ts[i];
            let mut key = a.p.map(|p| p.map(|x| (x * 100.).round() as i64));
            key.sort();
            let exact_match = exact.get(&key).copied();
            if exact_match.is_none() {
                exact.insert(key, i);
            }
            let mut candidates = vec![];
            if let Some(j) = exact_match {
                candidates.push(j);
            }
            candidates.extend(large.iter().copied());
            let small = visit_cells(a, |key| {
                for dp in -3..=3 {
                    let mut key = key;
                    key.1 += dp;
                    if let Some(v) = grid.get(&key) {
                        candidates.extend(v.iter().copied());
                    }
                }
            });
            if !small {
                candidates.extend(0..i);
            }
            candidates.sort_unstable();
            candidates.dedup();
            for j in candidates {
                tests += 1;
                let b = &ts[j];
                if let Some(area) = test(a, b) {
                    candidate_count += 1;
                    let mut b_key = b.p.map(|p| p.map(|x| (x * 100.).round() as i64));
                    b_key.sort();
                    let is_exact = key == b_key;
                    if is_exact {
                        exact_count += 1;
                    }
                    if streaming || conflicts.len() < 2000000 {
                        let value = json!({"pass_lod":level,"a_instance":a.instance,"b_instance":b.instance,"a_actor":instances[a.instance]["actor"],"b_actor":instances[b.instance]["actor"],"a_key":instances[a.instance]["key"],"b_key":instances[b.instance]["key"],"a_triangle":a.id,"b_triangle":b.id,"a_lod":a.lod,"b_lod":b.lod,"normal":a.n,"separation_cm":(a.d-b.d).abs(),"overlap_cm2":area,"a_area_cm2":a.area,"b_area_cm2":b.area,"exact_triangle":is_exact,"center_cm":overlap_center(a,b),"a_two_sided":a.two_sided,"b_two_sided":b.two_sided,"a_front_normal":a.n.map(|v|if a.back{-v}else{v}),"b_front_normal":b.n.map(|v|if b.back{-v}else{v}),"a_material_slot":a.slot,"b_material_slot":b.slot});
                        if let Some(w) = writer.as_mut() {
                            serde_json::to_writer(&mut *w, &value).unwrap();
                            w.write_all(b"\n").unwrap();
                        }
                        if conflicts.len() < if streaming { 5000 } else { 2000000 } {
                            conflicts.push(value);
                        }
                    }
                }
            }
            if small {
                visit_cells(a, |key| {
                    grid.entry(key).or_default().push(i);
                });
            } else {
                large.push(i);
            }
            if i % 1000000 == 0 {
                eprintln!("  {}/{}", i, ts.len());
            }
        }
    }
    let mut source_hashes:Vec<_>=loaded.keys().map(|name|json!({"file":name,"sha256":format!("{:x}",Sha256::digest(fs::read(folder.join(name)).unwrap()))})).collect();
    source_hashes.sort_by_key(|x| x["file"].as_str().unwrap().to_string());
    if let Some(w) = writer.as_mut() {
        w.flush().unwrap();
    }
    let report = json!({"status":"scan_complete_requires_review","units":"UE cm","distance_tolerance_cm":0.2,"broadphase":"cell-relative plane intercepts, shared dominant axes, conservative angular and spatial padding","metadata_sha256":metadata_sha256,"mesh_source_sha256":source_hashes,"material_policy":"Per-triangle slots; Opaque/Masked depth writers; opposite-facing single-sided contacts excluded; translucent sorting requires separate visual audit","passes":"LOD0,LOD1,LOD2 with available fallback;alternative LODs of same instance never compared","world_triangles_examined":examined,"triangle_pairs_tested":tests,"candidate_conflicts":candidate_count,"exact_duplicate_pairs":exact_count,"truncated":!streaming&&candidate_count>conflicts.len(),"all_conflicts_file":if streaming{Some(conflict_path)}else{None},"inline_conflicts_are_examples":streaming,"separate_depth_audit":skipped,"conflicts":conflicts});
    fs::write(output, serde_json::to_vec(&report).unwrap()).unwrap();
    eprintln!("{} candidates;{} exact", candidate_count, exact_count);
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample(p: [V; 3], i: usize) -> Tri {
        tri(p, i, 0, 0).unwrap()
    }
    #[test]
    fn coincident_and_small_separation_are_detected() {
        let a = sample([[0., 0., 0.], [100., 0., 0.], [0., 100., 0.]], 0);
        let b = sample([[0., 0., 0.1], [100., 0., 0.1], [0., 100., 0.1]], 1);
        assert!((test(&a, &b).unwrap() - 5000.).abs() < 1e-6);
        let c = sample([[0., 0., 1.], [100., 0., 1.], [0., 100., 1.]], 2);
        assert!(test(&a, &c).is_none());
    }
    #[test]
    fn shared_edge_is_not_a_surface_conflict() {
        let a = sample([[0., 0., 0.], [100., 0., 0.], [0., 100., 0.]], 0);
        let b = sample([[100., 100., 0.], [0., 100., 0.], [100., 0., 0.]], 1);
        assert!(test(&a, &b).is_none());
    }
    #[test]
    fn back_to_back_single_sided_faces_do_not_fight() {
        let a = sample([[0., 0., 0.], [100., 0., 0.], [0., 100., 0.]], 0);
        let mut b = a.clone();
        b.instance = 1;
        b.back = !a.back;
        assert!(test(&a, &b).is_none());
        b.two_sided = true;
        assert!(test(&a, &b).is_some());
        b.depth_writer = false;
        assert!(test(&a, &b).is_none());
    }
    #[test]
    fn partial_overlap_and_nonparallel_crossing() {
        let a = sample([[0., 0., 0.], [100., 0., 0.], [0., 100., 0.]], 0);
        let b = sample([[25., 25., 0.], [125., 25., 0.], [25., 125., 0.]], 1);
        assert!((test(&a, &b).unwrap() - 1250.).abs() < 1e-6);
        let witness=overlap_center(&a,&b);
        assert!(witness[0]>=25.&&witness[1]>=25.&&witness[0]+witness[1]<=100.+1e-6);
        assert_eq!(witness[2],0.);
        let c = sample([[25., 25., -10.], [125., 25., 10.], [25., 125., 10.]], 2);
        assert!(test(&a, &c).is_none());
    }
    #[test]
    fn ue_matrix_is_row_vector_convention() {
        let m: Vec<Value> = vec![
            2., 0., 0., 0., 0., 3., 0., 0., 0., 0., 4., 0., 10., 20., 30., 1.,
        ]
        .into_iter()
        .map(Value::from)
        .collect();
        assert_eq!(transform([1., 2., 3.], &m), [12., 26., 42.]);
    }
    #[test]
    fn broadphase_covers_far_origin_tilts_and_cell_boundaries() {
        let a = sample(
            [
                [100000., 100000., 500.],
                [100100., 100000., 500.],
                [100000., 100100., 500.],
            ],
            0,
        );
        let b = sample(
            [
                [100000., 100000., 500.1],
                [100100., 100000., 500.101],
                [100000., 100100., 500.1],
            ],
            1,
        );
        assert!(test(&a, &b).is_some());
        let mut keys = std::collections::HashSet::new();
        visit_cells(&a, |k| {
            keys.insert(k);
        });
        let mut found = false;
        visit_cells(&b, |key| {
            for dp in -3..=3 {
                let mut k = key;
                k.1 += dp;
                found |= keys.contains(&k);
            }
        });
        assert!(found);
    }
}
