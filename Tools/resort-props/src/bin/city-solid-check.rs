//! Prove which authored material slots contain only outward, closed solid shells.
//! Open sheets, nonmanifold joins, reversed shells and unsupported LODs fail closed.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::PathBuf,
};
fn u32at(b: &[u8], n: usize) -> u32 {
    u32::from_le_bytes(b[n..n + 4].try_into().unwrap())
}
fn root(p: &mut [usize], mut i: usize) -> usize {
    while p[i] != i {
        p[i] = p[p[i]];
        i = p[i];
    }
    i
}
fn volume(a: [f64; 3], b: [f64; 3], c: [f64; 3]) -> f64 {
    (a[0] * (b[1] * c[2] - b[2] * c[1])
        + a[1] * (b[2] * c[0] - b[0] * c[2])
        + a[2] * (b[0] * c[1] - b[1] * c[0]))
        / 6.
}
fn inspect(b: &[u8]) -> (HashSet<usize>, Value) {
    assert_eq!(u32at(b, 0), 0x43445932);
    let nv = u32at(b, 4) as usize;
    let nt = u32at(b, 8) as usize;
    let start = 12 + nv * 12;
    let points: Vec<[f64; 3]> = (0..nv)
        .map(|i| std::array::from_fn(|k| f32::from_bits(u32at(b, 12 + i * 12 + k * 4)) as f64))
        .collect();
    let tris: Vec<[usize; 3]> = (0..nt)
        .map(|i| std::array::from_fn(|k| u32at(b, start + i * 12 + k * 4) as usize))
        .collect();
    let slots: Vec<_> = (0..nt)
        .map(|i| u32at(b, start + nt * 16 + i * 4) as usize)
        .collect();
    let mut vertices = HashMap::new();
    let mut welded = Vec::new();
    for p in &points {
        let key = p.map(|v| (v * 100.).round() as i64);
        let id = vertices.len();
        welded.push(*vertices.entry(key).or_insert(id));
    }
    let mut parent: Vec<_> = (0..nt).collect();
    let mut edges: HashMap<(usize, usize), (usize, u32, i32)> = HashMap::new();
    let mut bad = vec![false; nt];
    for (i, t) in tris.iter().enumerate() {
        let q = t.map(|v| welded[v]);
        for k in 0..3 {
            let (a, c) = (q[k], q[(k + 1) % 3]);
            if a == c {
                bad[i] = true;
                continue;
            }
            let key = (a.min(c), a.max(c));
            let sign = if a < c { 1 } else { -1 };
            if let Some(e) = edges.get_mut(&key) {
                let r = root(&mut parent, i);
                let s = root(&mut parent, e.0);
                parent[r] = s;
                e.1 += 1;
                e.2 += sign;
            } else {
                edges.insert(key, (i, 1, sign));
            }
        }
    }
    for (_, e) in edges {
        if e.1 != 2 || e.2 != 0 {
            let r = root(&mut parent, e.0);
            bad[r] = true;
        }
    }
    let mut shell_volume = vec![0.; nt];
    let mut shell_bad = vec![false; nt];
    let mut lo = vec![[f64::INFINITY; 3]; nt];
    let mut hi = vec![[f64::NEG_INFINITY; 3]; nt];
    for (i, t) in tris.iter().enumerate() {
        let r = root(&mut parent, i);
        shell_bad[r] |= bad[i];
        shell_volume[r] += volume(points[t[0]], points[t[1]], points[t[2]]);
        for v in t {
            for k in 0..3 {
                lo[r][k] = lo[r][k].min(points[*v][k]);
                hi[r][k] = hi[r][k].max(points[*v][k]);
            }
        }
    }
    let mut counts: HashMap<usize, (usize, usize)> = HashMap::new();
    for (i, slot) in slots.iter().enumerate() {
        let r = root(&mut parent, i);
        let thickness = (0..3)
            .map(|k| hi[r][k] - lo[r][k])
            .fold(f64::INFINITY, f64::min);
        let good = !shell_bad[r] && shell_volume[r] < -0.01 && thickness <= 100.;
        let n = counts.entry(*slot).or_insert((0, 0));
        n.0 += 1;
        n.1 += usize::from(good);
    }
    let safe: HashSet<_> = counts
        .iter()
        .filter(|(_, c)| c.0 > 0 && c.0 == c.1)
        .map(|(s, _)| *s)
        .collect();
    let rows:Vec<_>=counts.iter().map(|(s,c)|json!({"slot":s,"triangles":c.0,"proven_closed_outward_triangles":c.1,"safe":safe.contains(s)})).collect();
    (
        safe,
        json!({"vertices":nv,"triangles":nt,"slots":rows,"sha256":format!("{:x}",Sha256::digest(b))}),
    )
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let folder = PathBuf::from(args.get(1).expect("original CDY2 export"));
    let inventory: Value =
        serde_json::from_slice(&fs::read(args.get(2).expect("original inventory")).unwrap())
            .unwrap();
    let output = args.get(3).expect("proof output");
    let raw = fs::read(folder.join("scene.json")).unwrap();
    let scene: Value = serde_json::from_slice(&raw).unwrap();
    let labels: HashSet<_> = inventory["actors"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|a| a["building_floor"] == true)
        .map(|a| a["label"].as_str().unwrap())
        .collect();
    let selected: HashSet<_> = scene["instances"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|i| labels.contains(i["actor"].as_str().unwrap()))
        .map(|i| i["mesh"].as_u64().unwrap())
        .collect();
    let mut meshes = vec![];
    for (mid, m) in scene["meshes"].as_array().unwrap().iter().enumerate() {
        if !selected.contains(&(mid as u64)) {
            continue;
        }
        let mut common: Option<HashSet<usize>> = None;
        let mut lods = vec![];
        for l in m["lods"].as_array().unwrap() {
            let (safe, mut row) =
                inspect(&fs::read(folder.join(l["file"].as_str().unwrap())).unwrap());
            row["lod"] = l["lod"].clone();
            common = Some(match common {
                None => safe,
                Some(old) => old.intersection(&safe).copied().collect(),
            });
            lods.push(row);
        }
        let mut slots: Vec<_> = common.unwrap_or_default().into_iter().collect();
        slots.sort();
        if !slots.is_empty() {
            meshes.push(json!({"source_asset":m["asset"],"safe_slots":slots,"lods":lods}));
        }
        if mid % 25 == 0 {
            eprintln!("mesh {} proven {}", mid, meshes.len());
        }
    }
    let report = json!({"status":"passed","scope":"Original building-floor meshes only; slot safe in every LOD; each welded shell is closed, manifold, consistently wound, negative-volume like native Engine Cube and <=100cm minimum bounding thickness; occupiable closed hulls excluded","position_quantization_cm":0.01,"scene_sha256":format!("{:x}",Sha256::digest(raw)),"meshes":meshes});
    fs::write(output, serde_json::to_vec(&report).unwrap()).unwrap();
}
#[cfg(test)]
mod tests {
    use super::*;
    fn fixture(faces: &[[u32; 3]]) -> Vec<u8> {
        let mut b = vec![];
        for n in [0x43445932, 4, faces.len() as u32] {
            b.extend(n.to_le_bytes());
        }
        for p in [
            [0f32, 0., 0.],
            [100., 0., 0.],
            [0., 100., 0.],
            [0., 0., 100.],
        ] {
            for v in p {
                b.extend(v.to_le_bytes());
            }
        }
        for t in faces {
            for v in t {
                b.extend(v.to_le_bytes());
            }
        }
        for i in 0..faces.len() {
            b.extend((i as u32).to_le_bytes());
        }
        for _ in faces {
            b.extend(0u32.to_le_bytes());
        }
        b
    }
    #[test]
    fn only_closed_outward_shells_authorize_culling() {
        let f = [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]];
        assert!(inspect(&fixture(&f)).0.contains(&0));
        assert!(inspect(&fixture(&f[..3])).0.is_empty());
        let inverted: Vec<_> = f.iter().map(|t| [t[0], t[2], t[1]]).collect();
        assert!(inspect(&fixture(&inverted)).0.is_empty());
        let mut duplicate = f.to_vec();
        duplicate.push(f[0]);
        assert!(inspect(&fixture(&duplicate)).0.is_empty());
    }
}
