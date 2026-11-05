//! Grok's per-building design register -> baked, role-separated exterior GLBs.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};
type R<T> = Result<T, Box<dyn std::error::Error>>;
type P = [f64; 3];
const ROLES: [&str; 6] = ["roof", "trim", "facade", "wood", "sign_panel", "metal"];
#[derive(Default)]
struct Mesh {
    faces: BTreeMap<usize, Vec<[P; 3]>>,
    parts: usize,
}
fn sub(a: P, b: P) -> P {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn add(a: P, b: P) -> P {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}
fn mul(a: P, s: f64) -> P {
    [a[0] * s, a[1] * s, a[2] * s]
}
fn cross(a: P, b: P) -> P {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}
fn len(a: P) -> f64 {
    a.iter().map(|x| x * x).sum::<f64>().sqrt()
}
impl Mesh {
    fn tri(&mut self, a: P, b: P, c: P, m: usize) {
        if len(cross(sub(b, a), sub(c, a))) > 1e-8 {
            self.faces.entry(m).or_default().push([a, b, c]);
        }
    }
    fn quad(&mut self, a: P, b: P, c: P, d: P, m: usize) {
        self.tri(a, b, c, m);
        self.tri(a, c, d, m);
    }
    fn solid(&mut self, p: [P; 8], m: usize) {
        for [a, b, c, d] in [
            [0, 3, 2, 1],
            [4, 5, 6, 7],
            [0, 1, 5, 4],
            [1, 2, 6, 5],
            [2, 3, 7, 6],
            [3, 0, 4, 7],
        ] {
            self.quad(p[a], p[b], p[c], p[d], m);
        }
        self.parts += 1;
    }
    fn b(&mut self, c: P, s: P, m: usize) {
        let [x, y, z] = c;
        let [w, d, h] = s.map(|v| v / 2.);
        self.solid(
            [
                [x - w, y - d, z - h],
                [x + w, y - d, z - h],
                [x + w, y + d, z - h],
                [x - w, y + d, z - h],
                [x - w, y - d, z + h],
                [x + w, y - d, z + h],
                [x + w, y + d, z + h],
                [x - w, y + d, z + h],
            ],
            m,
        );
    }
    fn panel(&mut self, mut p: [P; 4], thick: f64, m: usize) {
        if cross(sub(p[1], p[0]), sub(p[2], p[0]))[2] < 0. {
            p.reverse();
        }
        self.solid(
            [
                sub(p[0], [0., 0., thick]),
                sub(p[1], [0., 0., thick]),
                sub(p[2], [0., 0., thick]),
                sub(p[3], [0., 0., thick]),
                p[0],
                p[1],
                p[2],
                p[3],
            ],
            m,
        );
    }
    fn rooftri(&mut self, a: P, b: P, c: P) {
        if cross(sub(b, a), sub(c, a))[2] < 0. {
            self.tri(a, c, b, 0);
        } else {
            self.tri(a, b, c, 0);
        }
    }
    fn beam(&mut self, a: P, b: P, width: f64, m: usize) {
        let axis = sub(b, a);
        let axis = mul(axis, 1. / len(axis).max(1e-10));
        let u = cross(
            axis,
            if axis[2].abs() < 0.9 {
                [0., 0., 1.]
            } else {
                [0., 1., 0.]
            },
        );
        let u = mul(u, width / 2. / len(u));
        let v = mul(cross(axis, u), 1.);
        self.solid(
            [
                sub(sub(a, u), v),
                add(sub(a, v), u),
                add(add(a, u), v),
                add(sub(a, u), v),
                sub(sub(b, u), v),
                add(sub(b, v), u),
                add(add(b, u), v),
                add(sub(b, u), v),
            ],
            m,
        );
    }
    fn cylinder(&mut self, c: P, r: f64, h: f64, m: usize) {
        let n = 8;
        for k in 0..n {
            let a = k as f64 * std::f64::consts::TAU / n as f64;
            let b = (k + 1) as f64 * std::f64::consts::TAU / n as f64;
            let p = [c[0] + r * a.cos(), c[1] + r * a.sin(), c[2]];
            let q = [c[0] + r * b.cos(), c[1] + r * b.sin(), c[2]];
            let t = add(p, [0., 0., h]);
            let u = add(q, [0., 0., h]);
            self.quad(p, q, u, t, m);
            self.tri([c[0], c[1], c[2] + h], t, u, m);
            self.tri(c, q, p, m);
        }
        self.parts += 1;
    }
}
fn n(v: &Value, k: &str) -> f64 {
    v[k].as_f64().unwrap()
}
fn st<'a>(v: &'a Value, k: &str) -> &'a str {
    v[k].as_str().unwrap()
}
fn read(p: impl AsRef<Path>) -> R<Value> {
    Ok(serde_json::from_slice(&fs::read(p)?)?)
}
fn write(p: impl AsRef<Path>, v: &Value) -> R<()> {
    fs::write(p, serde_json::to_vec_pretty(v)?)?;
    Ok(())
}
fn sha(p: impl AsRef<Path>) -> R<String> {
    Ok(format!("{:x}", Sha256::digest(fs::read(p)?)))
}
fn gltf(p: P) -> P {
    [p[0], p[2], -p[1]]
}
fn glb(path: &Path, mesh: &Mesh, name: &str) -> R<Value> {
    let mut bin: Vec<u8> = vec![];
    let mut views = vec![];
    let mut accessors = vec![];
    let mut primitives = vec![];
    let mut bounds = [[f64::INFINITY; 3], [f64::NEG_INFINITY; 3]];
    let mut tris = 0;
    for (mat, faces) in &mesh.faces {
        let mut pos: Vec<f32> = vec![];
        let mut norms: Vec<f32> = vec![];
        let mut uvs: Vec<f32> = vec![];
        for tri in faces {
            let nn = cross(sub(tri[1], tri[0]), sub(tri[2], tri[0]));
            let norm = gltf(mul(nn, 1. / len(nn)));
            for p in tri {
                for k in 0..3 {
                    bounds[0][k] = bounds[0][k].min(p[k]);
                    bounds[1][k] = bounds[1][k].max(p[k]);
                }
                pos.extend(gltf(*p).map(|x| x as f32));
                norms.extend(norm.map(|x| x as f32));
                let uv = if nn[2].abs() >= nn[0].abs().max(nn[1].abs()) {
                    [p[0], p[1]]
                } else if nn[0].abs() >= nn[1].abs() {
                    [p[1], p[2]]
                } else {
                    [p[0], p[2]]
                };
                uvs.extend(uv.map(|v| v as f32));
            }
            tris += 1;
        }
        let mut attrs = vec![];
        for (data, dim) in [(&pos, 3), (&norms, 3), (&uvs, 2)] {
            let off = bin.len();
            for v in data {
                bin.extend(v.to_le_bytes());
            }
            let vi = views.len();
            views.push(
                json!({"buffer":0,"byteOffset":off,"byteLength":bin.len()-off,"target":34962}),
            );
            let ai = accessors.len();
            let mut a = json!({"bufferView":vi,"componentType":5126,"count":data.len()/dim,"type":if dim==3{"VEC3"}else{"VEC2"}});
            if attrs.is_empty() {
                let mut lo = [f32::INFINITY; 3];
                let mut hi = [f32::NEG_INFINITY; 3];
                for p in data.chunks(3) {
                    for k in 0..3 {
                        lo[k] = lo[k].min(p[k]);
                        hi[k] = hi[k].max(p[k]);
                    }
                }
                a["min"] = json!(lo);
                a["max"] = json!(hi);
            }
            accessors.push(a);
            attrs.push(ai);
        }
        primitives.push(json!({"attributes":{"POSITION":attrs[0],"NORMAL":attrs[1],"TEXCOORD_0":attrs[2]},"material":mat}));
    }
    let colors = [
        [0.52, 0.25, 0.17, 1.],
        [0.88, 0.8, 0.65, 1.],
        [0.95, 0.86, 0.72, 1.],
        [0.42, 0.26, 0.13, 1.],
        [0.12, 0.24, 0.24, 1.],
        [0.48, 0.3, 0.12, 1.],
    ];
    let g = json!({"asset":{"version":"2.0","generator":"OpenKoikatsu Grok design register / Codex architecture mesh"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0,"name":name}],"meshes":[{"name":name,"primitives":primitives}],"materials":ROLES.iter().enumerate().map(|(i,r)|json!({"name":r,"pbrMetallicRoughness":{"baseColorFactor":colors[i],"roughnessFactor":0.7,"metallicFactor":if i==5{0.5}else{0.}}})).collect::<Vec<_>>(),"buffers":[{"byteLength":bin.len()}],"bufferViews":views,"accessors":accessors});
    let mut js = serde_json::to_vec(&g)?;
    while js.len() % 4 != 0 {
        js.push(b' ');
    }
    while bin.len() % 4 != 0 {
        bin.push(0);
    }
    let mut raw = vec![];
    for v in [
        0x46546c67,
        2,
        (12 + 8 + js.len() + 8 + bin.len()) as u32,
        js.len() as u32,
        0x4e4f534a,
    ] {
        raw.extend(v.to_le_bytes());
    }
    raw.extend(js);
    raw.extend((bin.len() as u32).to_le_bytes());
    raw.extend(0x004e4942_u32.to_le_bytes());
    raw.extend(bin);
    fs::write(path, raw)?;
    Ok(json!({"triangles":tris,"bounds_m":bounds,"parts":mesh.parts,"sha256":sha(path)?}))
}
fn subtract_rect(r: [f64; 4], c: [f64; 4]) -> Vec<[f64; 4]> {
    let [x0, y0, x1, y1] = r;
    let a = x0.max(c[0]);
    let b = y0.max(c[1]);
    let d = x1.min(c[2]);
    let e = y1.min(c[3]);
    if a >= d || b >= e {
        return vec![r];
    }
    [
        [x0, y0, a, y1],
        [d, y0, x1, y1],
        [a, y0, d, b],
        [a, e, d, y1],
    ]
    .into_iter()
    .filter(|p| p[2] - p[0] > 0.5 && p[3] - p[1] > 0.5)
    .collect()
}
fn roof(m: &mut Mesh, r: [f64; 4], z: f64, pitch: f64, family: &str, axis: &str, seed: usize) {
    let [x0, y0, x1, y1] = r;
    let w = x1 - x0;
    let d = y1 - y0;
    let cx = (x0 + x1) / 2.;
    let cy = (y0 + y1) / 2.;
    let e = z + 0.28;
    let rise =
        (((if axis == "y" { w } else { d }) / 2.) * pitch.to_radians().tan()).clamp(0.65, 3.6);
    let pt = |u: f64, v: f64, h: f64| {
        if axis == "y" {
            [cx + u * w / 2., cy + v * d / 2., h]
        } else {
            [cx + v * w / 2., cy + u * d / 2., h]
        }
    };
    let gable = |m: &mut Mesh, a: f64, b: f64, base: f64, rr: f64| {
        m.panel(
            [
                pt(a, -1., base),
                pt(b, -1., base + rr),
                pt(b, 1., base + rr),
                pt(a, 1., base),
            ],
            0.15,
            0,
        );
    };
    match family {
        "shed" => {
            m.panel(
                [
                    pt(-1., -1., e),
                    pt(1., -1., e + rise),
                    pt(1., 1., e + rise),
                    pt(-1., 1., e),
                ],
                0.18,
                0,
            );
        }
        "butterfly" => {
            gable(m, -1., 0., e + rise, -rise);
            gable(m, 1., 0., e + rise, -rise);
            m.beam(pt(0., -1., e - 0.02), pt(0., 1., e - 0.02), 0.16, 5);
        }
        "hip" => {
            let rr = rise;
            let q = [
                pt(-1., -1., e),
                pt(1., -1., e),
                pt(1., 1., e),
                pt(-1., 1., e),
            ];
            let a = pt(0., -0.55, e + rr);
            let b = pt(0., 0.55, e + rr);
            for [a, b, c] in [
                [q[0], q[1], a],
                [q[1], q[2], b],
                [q[1], b, a],
                [q[2], q[3], b],
                [q[3], q[0], a],
                [q[3], a, b],
            ] {
                m.rooftri(a, b, c);
            }
            for k in 0..4 {
                m.quad(
                    sub(q[k], [0., 0., 0.17]),
                    sub(q[(k + 1) % 4], [0., 0., 0.17]),
                    q[(k + 1) % 4],
                    q[k],
                    0,
                );
            }
            m.beam(a, b, 0.16, 1);
        }
        "paired_pavilion" => {
            for (a, b) in [(-1., -0.05), (0.05, 1.)] {
                let mid = (a + b) / 2.;
                m.panel(
                    [
                        pt(a, -1., e),
                        pt(mid, -1., e + rise * 0.6),
                        pt(mid, 1., e + rise * 0.6),
                        pt(a, 1., e),
                    ],
                    0.15,
                    0,
                );
                m.panel(
                    [
                        pt(mid, -1., e + rise * 0.6),
                        pt(b, -1., e),
                        pt(b, 1., e),
                        pt(mid, 1., e + rise * 0.6),
                    ],
                    0.15,
                    0,
                );
            }
        }
        "stepped" => {
            gable(m, -1., -0.05, e, rise * 0.6);
            gable(m, 1., 0.05, e + rise * 0.32, rise * 0.6);
            m.beam(
                pt(0., -1., e + rise * 0.65),
                pt(0., 1., e + rise * 0.65),
                0.18,
                3,
            );
        }
        "lantern" => {
            gable(m, -1., -0.22, e, rise * 0.75);
            gable(m, 1., 0.22, e, rise * 0.75);
            let top = e + rise * 0.75 + 0.65;
            let p = [
                pt(-0.26, -0.95, top),
                pt(0.26, -0.95, top),
                pt(0.26, 0.95, top),
                pt(-0.26, 0.95, top),
            ];
            m.panel(p, 0.12, 0);
            for v in [-0.9, 0.9] {
                m.beam(pt(-0.2, v, e + rise * 0.75), pt(-0.2, v, top), 0.12, 3);
                m.beam(pt(0.2, v, e + rise * 0.75), pt(0.2, v, top), 0.12, 3);
            }
        }
        "cross_gable" => {
            gable(m, -1., 0., e, rise);
            gable(m, 1., 0., e, rise);
            let small = [cx - w * 0.24, y0 + 0.15, cx + w * 0.24, cy];
            roof(
                m,
                small,
                e + rise * 0.12,
                pitch,
                "gable",
                if axis == "y" { "x" } else { "y" },
                seed,
            );
        }
        _ => {
            gable(m, -1., 0., e, rise);
            gable(m, 1., 0., e, rise);
        }
    }
    // Discrete roof-edge fascia and timber rafters create a readable silhouette.
    for (a, b) in [
        (pt(-1., -1., e), pt(-1., 1., e)),
        (pt(1., -1., e), pt(1., 1., e)),
    ] {
        m.beam(a, b, 0.18, 1);
    }
    if family == "gable" || family == "cross_gable" {
        for v in [-1., 1.] {
            m.beam(pt(-1., v, e - 0.03), pt(0., v, e + rise - 0.03), 0.13, 3);
            m.beam(pt(0., v, e + rise - 0.03), pt(1., v, e - 0.03), 0.13, 3);
        }
    }
}
fn brow(m: &mut Mesh, side: &str, along: f64, z: f64, width: f64, w: f64, d: f64, detail: &str) {
    let point = |u: f64, h: f64| match side {
        "south" => [along + u, -d / 2. - 0.16, h],
        "north" => [along - u, d / 2. + 0.16, h],
        "east" => [w / 2. + 0.16, along + u, h],
        _ => [-w / 2. - 0.16, along - u, h],
    };
    if detail == "arched_brow" {
        let rr = width / 2. + 0.12;
        for i in 0..6 {
            let a = i as f64 * std::f64::consts::PI / 6.;
            let b = (i + 1) as f64 * std::f64::consts::PI / 6.;
            m.beam(
                point(rr * a.cos(), z + 0.3 * a.sin()),
                point(rr * b.cos(), z + 0.3 * b.sin()),
                0.085,
                1,
            );
        }
    } else {
        m.beam(
            point(-width / 2. - 0.12, z),
            point(width / 2. + 0.12, z),
            0.12,
            if detail == "timber_brackets" { 3 } else { 1 },
        );
    }
}
fn build(spec: &Value, design: &Value, index: usize) -> R<(Mesh, Value)> {
    let w = n(spec, "width_m");
    let d = n(spec, "depth_m");
    let h = n(spec, "height_m");
    let id = st(spec, "id");
    let family = st(design, "roof_family");
    let axis = st(design, "roof_axis");
    let pitch = n(design, "pitch_deg");
    let e = n(design, "eave_m").clamp(0.4, 0.6) - 0.11;
    let detail = st(design, "detail");
    let mut m = Mesh::default();
    let court = spec["courtyard"].as_array().map(|a| {
        let a = a.iter().map(|v| v.as_f64().unwrap()).collect::<Vec<_>>();
        [
            a[0] - a[2] / 2.,
            a[1] - a[3] / 2.,
            a[0] + a[2] / 2.,
            a[1] + a[3] / 2.,
        ]
    });
    let large = w > 18. || d > 26.;
    let nx = if large { (w / 11.).ceil() as usize } else { 1 };
    let ny = if large { (d / 11.).ceil() as usize } else { 1 };
    let mut modules = 0;
    for i in 0..nx {
        for j in 0..ny {
            if detail == "pergola" && large && i == 0 && j == 0 {
                continue;
            }
            // A deliberate central service terrace gives large roofs practical breathing room.
            if nx > 4 && ny > 3 && i > 0 && i + 1 < nx && j > 0 && j + 1 < ny {
                continue;
            }
            let gap = if large { 0.35 } else { 0. };
            let x0 = -w / 2. + i as f64 * w / nx as f64 + if i == 0 { -e } else { gap };
            let x1 = -w / 2. + (i + 1) as f64 * w / nx as f64 + if i + 1 == nx { e } else { -gap };
            let y0 = -d / 2. + j as f64 * d / ny as f64 + if j == 0 { -e } else { gap };
            let y1 = -d / 2. + (j + 1) as f64 * d / ny as f64 + if j + 1 == ny { e } else { -gap };
            let rects = if let Some(c) = court {
                subtract_rect(
                    [x0, y0, x1, y1],
                    [c[0] - 0.22, c[1] - 0.22, c[2] + 0.22, c[3] + 0.22],
                )
            } else {
                vec![[x0, y0, x1, y1]]
            };
            for r in rects {
                if r[2] - r[0] < 1. || r[3] - r[1] < 1. {
                    continue;
                }
                let z = h + if large {
                    ((i + j + index) % 3) as f64 * 0.12
                } else {
                    0.
                };
                roof(&mut m, r, z, pitch, family, axis, index);
                modules += 1;
            }
        }
    }
    // Outside-only floor cornices; no columns or screens in original windows/entries.
    for f in spec["floors"].as_array().unwrap() {
        let z = n(f, "z_m") + n(f, "height_m") - 0.08;
        if z < 3.2 {
            continue;
        }
        for s in [-1., 1.] {
            if let Some(c) = court.filter(|c| s > 0. && c[3] >= d / 2. - 0.1) {
                for (a, b) in [(-w / 2. - 0.2, c[0] - 0.05), (c[2] + 0.05, w / 2. + 0.2)] {
                    m.b(
                        [(a + b) / 2., s * (d / 2. + 0.14), z],
                        [b - a, 0.26, 0.15],
                        1,
                    );
                }
            } else {
                m.b([0., s * (d / 2. + 0.14), z], [w + 0.40, 0.26, 0.15], 1);
            }
            m.b([s * (w / 2. + 0.14), 0., z], [0.26, d + 0.40, 0.15], 1);
        }
    }
    for sx in [-1., 1.] {
        for sy in [-1., 1.] {
            let x = sx * (w / 2. + 0.24);
            let y = sy * (d / 2. + 0.24);
            m.b([x, y, (h + 3.1) / 2.], [0.22, 0.22, h - 3.1], 2);
            m.b([x, y, h - 0.3], [0.42, 0.42, 0.22], 1);
        }
    }
    // Curved window brows are concentrated at the public and top storeys.
    for (k, window) in spec["windows"].as_array().unwrap().iter().enumerate() {
        if k % 2 == 1 {
            continue;
        }
        let floor = window["floor"].as_u64().unwrap();
        if floor != 1 && floor != spec["floors"].as_array().unwrap().len() as u64 && k % 7 != 0 {
            continue;
        }
        let z = (n(window, "z") + n(window, "height_m") + 0.09).max(3.08);
        brow(
            &mut m,
            st(window, "side"),
            n(window, "along"),
            z,
            n(window, "width_m"),
            w,
            d,
            detail,
        );
    }
    // Upper-floor eave brackets on shops add depth without creating false balconies.
    if id.starts_with('S') && id != "SP" {
        for x in [-w * 0.38, 0., w * 0.38] {
            for z in [3.65, 7.45] {
                if z < h - 0.5 {
                    m.beam(
                        [x, -d / 2. - 0.08, z - 0.45],
                        [x, -d / 2. - 0.55, z],
                        0.105,
                        3,
                    );
                    m.b([x, -d / 2. - 0.3, z], [0.14, 0.55, 0.12], 3);
                }
            }
        }
    }
    // Street-facing horizontal fascia, entirely within the ground storey.
    // Prefer the public/street entrance over service exits.
    let entries = spec["entrances"].as_array().unwrap();
    let entry = entries
        .iter()
        .find(|e| e["purpose"] == "street_main" || e["id"].as_str().unwrap_or("").contains("grand"))
        .unwrap_or(&entries[0]);
    let side = entry["facade_side"].as_str().unwrap();
    let side_name = match side {
        "N" => "north",
        "E" => "east",
        "W" => "west",
        _ => "south",
    };
    let wall_length = if side == "E" || side == "W" { d } else { w };
    let mut along = if id.starts_with('S') && id != "SP" {
        0.
    } else {
        entry["position_m"][if side == "E" || side == "W" { 1 } else { 0 }]
            .as_f64()
            .unwrap()
    };
    let nominal = if large {
        (wall_length * 0.42).clamp(10., 18.)
    } else {
        wall_length * (0.68 + (index % 3) as f64 * 0.03)
    };
    let mut sw = nominal.min((wall_length / 2. - along.abs() - 0.3) * 2.);
    let door_top = entries
        .iter()
        .filter(|e| e["facade_side"] == side)
        .map(|e| e["height_m"].as_f64().unwrap_or(2.7))
        .fold(2.4_f64, f64::max);
    let window_top = spec["windows"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|q| q["floor"] == 1 && q["side"] == side_name)
        .map(|q| n(q, "z") + n(q, "height_m"))
        .fold(0_f64, f64::max);
    let mut bottom = 2.75_f64.max(door_top + 0.12).max(window_top + 0.08);
    let mut top =
        (n(&spec["floors"][0], "height_m") - 0.12).min(bottom + if large { 1.05 } else { 1.0 });
    let vertical = top - bottom < 0.4;
    if vertical {
        along = wall_length / 2. - 0.85;
        sw = 1.05;
        bottom = 2.9;
        top = bottom + 4.8;
    }
    let sh = top - bottom;
    assert!(
        sh > 0.3 && sw > 0.9,
        "No clear ground-floor fascia for {id}"
    );
    let sz = (bottom + top) / 2.;
    let (cx, cy, yaw) = match side {
        "N" => (along, d / 2. + 0.35, 180_f64),
        "E" => (w / 2. + 0.35, along, 90_f64),
        "W" => (-w / 2. - 0.35, along, -90_f64),
        _ => (along, -d / 2. - 0.35, 0_f64),
    };
    let mut board_mesh = Mesh::default();
    board_mesh.b([0., 0., 0.], [sw, 0.22, sh], 4);
    for x in [-sw / 2., sw / 2.] {
        board_mesh.b([x, -0.02, 0.], [0.11, 0.28, sh + 0.12], 5);
    }
    for z in [-sh / 2., sh / 2.] {
        board_mesh.b([0., -0.02, z], [sw + 0.14, 0.28, 0.10], 5);
    }
    for x in [-sw * 0.4, sw * 0.4] {
        board_mesh.b([x, 0.15, 0.], [0.12, 0.3, 0.14], 5);
    }
    let angle = yaw.to_radians();
    for (role, faces) in board_mesh.faces {
        for tri in faces {
            let p = tri.map(|p| {
                [
                    cx + p[0] * angle.cos() - p[1] * angle.sin(),
                    cy + p[0] * angle.sin() + p[1] * angle.cos(),
                    sz + p[2],
                ]
            });
            m.tri(p[0], p[1], p[2], role);
        }
    }
    m.parts += board_mesh.parts;
    if detail == "pergola" && large {
        // A small roof pavilion on a solid corner, never above E1's courtyard.
        let cx = -w / 2. + 4.;
        let cy = -d / 2. + 3.5;
        let zz = h + 2.4;
        for x in [cx - 2.5, cx + 2.5] {
            for y in [cy - 2., cy + 2.] {
                m.cylinder([x, y, h + 0.1], 0.09, 2.3, 3);
            }
        }
        for k in 0..10 {
            m.b([cx - 2.8 + k as f64 * 0.62, cy, zz], [0.12, 5., 0.14], 3);
        }
    }
    let window_clearance = if vertical {
        spec["windows"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|q| {
                q["side"] == side_name && n(q, "z") < top && n(q, "z") + n(q, "height_m") > bottom
            })
            .map(|q| (n(q, "along") - along).abs() - n(q, "width_m") / 2. - sw / 2. - 0.07)
            .fold(999_f64, f64::min)
    } else {
        bottom - 0.06 - window_top
    };
    let board = json!({"center_m":[cx,cy,sz],"width_m":sw,"height_m":sh,"face":side_name,"yaw_deg":yaw,"placement":if vertical{"ground_to_upper_vertical"}else{"ground_floor_horizontal"},"bottom_m":bottom,"top_m":top,"entrance":entry["id"],"door_clearance_m":bottom-0.06-door_top,"window_clearance_m":window_clearance,"window_clearance_axis":if vertical{"lateral"}else{"height"}});
    Ok((
        m,
        json!({"id":id,"name":spec["name"],"roof_family":family,"recipe":design,"roof_modules":modules,"sign_board":board,"original_floors":spec["floors"].as_array().unwrap().len(),"note":design["note"]}),
    ))
}
fn main() -> R<()> {
    let out = PathBuf::from("output/street-social-city-production/resort-architecture-v1");
    let input = read(out.join("building-input.json"))?;
    let design = read(out.join("design-register.json"))?;
    let specs = input["buildings"].as_array().ok_or("missing buildings")?;
    let designs = design["buildings"].as_array().ok_or("missing designs")?;
    assert_eq!(specs.len(), 122);
    assert_eq!(designs.len(), 122);
    let by = designs
        .iter()
        .map(|b| (st(b, "id"), b))
        .collect::<BTreeMap<_, _>>();
    assert_eq!(by.len(), 122);
    let mut rows = vec![];
    let mut tris = 0;
    fs::create_dir_all(out.join("models"))?;
    for (i, b) in specs.iter().enumerate() {
        let id = st(b, "id");
        let d = by.get(id).ok_or("missing design id")?;
        let (mesh, mut row) = build(b, d, i)?;
        let rel = format!("models/{id}.glb");
        let result = glb(&out.join(&rel), &mesh, id)?;
        tris += result["triangles"].as_u64().unwrap();
        row["glb"] = json!(rel);
        row["geometry"] = result;
        rows.push(row);
    }
    let floors: usize = specs
        .iter()
        .map(|b| b["floors"].as_array().unwrap().len())
        .sum();
    assert_eq!(floors, 427);
    assert!(tris <= 200000, "triangle budget exceeded: {tris}");
    write(
        out.join("geometry-manifest.json"),
        &json!({"status":"generated","buildings":rows,"building_count":122,"original_floors":floors,"triangles":tris,"coordinates":"baked glTF Y-up [local x,local z,-local y], metres, identity nodes; import at original building transform","design_register_sha256":sha(out.join("design-register.json"))?,"input_sha256":sha(out.join("building-input.json"))?,"generator_sha256":sha("Tools/resort-props/src/bin/resort-architecture.rs")?,"method":"Grok Build per-building roof/design choices; Codex dimensioned non-destructive exterior geometry and native integration"}),
    )?;
    println!("Generated122 buildings /427 preserved floors /{tris} exterior triangles");
    Ok(())
}
