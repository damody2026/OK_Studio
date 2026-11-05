use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    net::TcpListener,
    path::{Path, PathBuf},
};
type R<T> = Result<T, Box<dyn std::error::Error>>;
#[derive(Clone)]
struct Shape {
    p: Vec<[f64; 3]>,
    i: Vec<u32>,
}
#[derive(Clone)]
struct Part {
    shape: usize,
    p: [f64; 3],
    s: [f64; 3],
    rot: f64,
    tilt: f64,
    mat: usize,
}
struct Model {
    parts: Vec<Part>,
}
impl Model {
    fn new() -> Self {
        Self { parts: vec![] }
    }
    fn b(&mut self, p: [f64; 3], s: [f64; 3], mat: usize) {
        self.parts.push(Part {
            shape: 0,
            p,
            s,
            rot: 0.,
            tilt: 0.,
            mat,
        });
    }
    fn c(&mut self, p: [f64; 3], s: [f64; 3], mat: usize) {
        self.parts.push(Part {
            shape: 1,
            p,
            s,
            rot: 0.,
            tilt: 0.,
            mat,
        });
    }
    fn beam(&mut self, a: [f64; 3], b: [f64; 3], r: f64, mat: usize) {
        let d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
        let len = (d.iter().map(|x| x * x).sum::<f64>()).sqrt();
        self.parts.push(Part {
            shape: 1,
            p: a,
            s: [r, r, len],
            rot: d[1].atan2(d[0]),
            tilt: (d[2] / len).acos(),
            mat,
        });
    }
    fn legs(&mut self, w: f64, d: f64, h: f64) {
        for x in [-w / 2., w / 2.] {
            for y in [-d / 2., d / 2.] {
                self.b([x, y, 0.], [0.07, 0.07, h], 1);
            }
        }
    }
    fn slats(&mut self, w: f64, d: f64, z: f64, n: usize) {
        for i in 0..n {
            self.b(
                [-w / 2. + (i as f64 + 0.5) * w / n as f64, 0., z],
                [w / n as f64 * 0.84, d, 0.045],
                0,
            );
        }
    }
    fn ring(&mut self, r: f64, z: f64, n: usize, mat: usize) {
        for k in 0..n {
            let a = k as f64 * std::f64::consts::TAU / n as f64;
            let b = (k + 1) as f64 * std::f64::consts::TAU / n as f64;
            self.beam(
                [r * a.cos(), r * a.sin(), z],
                [r * b.cos(), r * b.sin(), z],
                0.035,
                mat,
            );
        }
    }
}
fn sha(p: &Path) -> R<String> {
    Ok(format!("{:x}", Sha256::digest(fs::read(p)?)))
}
fn read_json(p: &Path) -> R<Value> {
    Ok(serde_json::from_slice(&fs::read(p)?)?)
}
fn write(p: &Path, v: &Value) -> R<()> {
    if let Some(d) = p.parent() {
        fs::create_dir_all(d)?;
    }
    fs::write(p, serde_json::to_vec_pretty(v)?)?;
    Ok(())
}
fn source(p: &Path) -> R<Shape> {
    let b = fs::read(p)?;
    let n = u32::from_le_bytes(b[12..16].try_into()?) as usize;
    let v: Value = serde_json::from_slice(&b[20..20 + n])?;
    let bin = &b[28 + n..];
    let pr = &v["meshes"][0]["primitives"][0];
    let vals = |ai: usize| -> Vec<f64> {
        let a = &v["accessors"][ai];
        let bv = &v["bufferViews"][a["bufferView"].as_u64().unwrap() as usize];
        let off = bv["byteOffset"].as_u64().unwrap_or(0) as usize
            + a["byteOffset"].as_u64().unwrap_or(0) as usize;
        let c = a["count"].as_u64().unwrap() as usize;
        let sz = if a["type"] == "VEC3" { 3 } else { 1 };
        let ct = a["componentType"].as_u64().unwrap();
        let bytes = if ct == 5123 { 2 } else { 4 };
        let stride = bv["byteStride"].as_u64().unwrap_or((bytes * sz) as u64) as usize;
        let mut out = vec![];
        for i in 0..c {
            for j in 0..sz {
                let o = off + i * stride + j * bytes;
                out.push(match ct {
                    5126 => f32::from_le_bytes(bin[o..o + 4].try_into().unwrap()) as f64,
                    5123 => u16::from_le_bytes(bin[o..o + 2].try_into().unwrap()) as f64,
                    5125 => u32::from_le_bytes(bin[o..o + 4].try_into().unwrap()) as f64,
                    _ => panic!("unsupported component"),
                });
            }
        }
        out
    };
    let raw = vals(pr["attributes"]["POSITION"].as_u64().unwrap() as usize);
    let mut ps: Vec<[f64; 3]> = raw.chunks(3).map(|x| [x[0], x[1], x[2]]).collect();
    // Certified GLB primitives are Y-up. Assemble in east/north/up (Z-up).
    // Convert before normalizing: otherwise a cylinder becomes a stretched disc.
    for p in &mut ps {
        *p = [p[0], -p[2], p[1]];
    }
    let mut lo = [f64::MAX; 3];
    let mut hi = [f64::MIN; 3];
    for p in &ps {
        for k in 0..3 {
            lo[k] = lo[k].min(p[k]);
            hi[k] = hi[k].max(p[k]);
        }
    }
    for p in &mut ps {
        for k in 0..3 {
            p[k] = (p[k] - lo[k]) / (hi[k] - lo[k]) - if k == 2 { 0. } else { 0.5 };
        }
    }
    if p.to_string_lossy().contains("unit-cylinder") {
        assert!(
            ps.iter()
                .all(|p| p[2].abs() < 1e-5 || (p[2] - 1.).abs() < 1e-5),
            "Cylinder caps must remain perpendicular to up axis"
        );
    }
    Ok(Shape {
        p: ps,
        i: vals(pr["indices"].as_u64().unwrap() as usize)
            .iter()
            .map(|x| *x as u32)
            .collect(),
    })
}
fn transformed(p: [f64; 3], q: &Part) -> [f64; 3] {
    let x = p[0] * q.s[0];
    let y = p[1] * q.s[1];
    let z = p[2] * q.s[2];
    let xx = x * q.tilt.cos() + z * q.tilt.sin();
    let zz = -x * q.tilt.sin() + z * q.tilt.cos();
    [
        q.p[0] + xx * q.rot.cos() - y * q.rot.sin(),
        q.p[1] + xx * q.rot.sin() + y * q.rot.cos(),
        q.p[2] + zz,
    ]
}
const COLORS: [[f64; 4]; 8] = [
    [0.58, 0.34, 0.16, 1.],
    [0.13, 0.20, 0.21, 1.],
    [0.90, 0.82, 0.62, 1.],
    [0.16, 0.55, 0.57, 1.],
    [0.20, 0.39, 0.20, 1.],
    [0.87, 0.44, 0.36, 1.],
    [0.95, 0.76, 0.27, 1.],
    [0.75, 0.81, 0.80, 1.],
];
fn glb(path: &Path, model: &Model, sh: &[Shape], name: &str) -> R<(usize, [[f64; 3]; 2])> {
    let mut bin = vec![];
    let mut bvs = vec![];
    let mut ac = vec![];
    let mut primitives = vec![];
    let mut lo = [f64::MAX; 3];
    let mut hi = [f64::MIN; 3];
    let mut tris = 0;
    for mat in 0..14 {
        let mut positions = vec![];
        let mut normals = vec![];
        let mut uv = vec![];
        for q in model.parts.iter().filter(|q| q.mat == mat) {
            let s = &sh[q.shape];
            for t in s.i.chunks(3) {
                let ps = [
                    transformed(s.p[t[0] as usize], q),
                    transformed(s.p[t[1] as usize], q),
                    transformed(s.p[t[2] as usize], q),
                ];
                let a = [
                    ps[1][0] - ps[0][0],
                    ps[1][1] - ps[0][1],
                    ps[1][2] - ps[0][2],
                ];
                let b = [
                    ps[2][0] - ps[0][0],
                    ps[2][1] - ps[0][1],
                    ps[2][2] - ps[0][2],
                ];
                let n = [
                    a[1] * b[2] - a[2] * b[1],
                    a[2] * b[0] - a[0] * b[2],
                    a[0] * b[1] - a[1] * b[0],
                ];
                let len = n.iter().map(|x| x * x).sum::<f64>().sqrt().max(1e-12);
                for p in ps {
                    let dominant = if n[2].abs() > n[0].abs().max(n[1].abs()) {
                        2
                    } else if n[0].abs() > n[1].abs() {
                        0
                    } else {
                        1
                    };
                    uv.extend_from_slice(&match dominant {
                        0 => [p[1] as f32, p[2] as f32],
                        1 => [(p[0]+if name=="sign"{0.5}else{0.}) as f32, (if name=="sign"{1.-p[2]}else{p[2]}) as f32],
                        _ => [p[0] as f32, p[1] as f32],
                    });
                    for k in 0..3 {
                        lo[k] = lo[k].min(p[k]);
                        hi[k] = hi[k].max(p[k]);
                        positions.push(p[k] as f32);
                        normals.push((n[k] / len) as f32);
                    }
                }
                tris += 1;
            }
        }
        if positions.is_empty() {
            continue;
        }
        let mut attrs = vec![];
        for data in [&positions, &normals] {
            let start = bin.len();
            for f in data {
                bin.extend(f.to_le_bytes());
            }
            let vi = bvs.len();
            bvs.push(
                json!({"buffer":0,"byteOffset":start,"byteLength":bin.len()-start,"target":34962}),
            );
            let ai = ac.len();
            let mut a =
                json!({"bufferView":vi,"componentType":5126,"count":data.len()/3,"type":"VEC3"});
            if attrs.is_empty() {
                let mut mn = [f32::MAX; 3];
                let mut mx = [f32::MIN; 3];
                for p in positions.chunks(3) {
                    for k in 0..3 {
                        mn[k] = mn[k].min(p[k]);
                        mx[k] = mx[k].max(p[k]);
                    }
                }
                a["min"] = json!(mn);
                a["max"] = json!(mx);
            }
            ac.push(a);
            attrs.push(ai);
        }
        let off = bin.len();
        for f in &uv {
            bin.extend(f.to_le_bytes());
        }
        let vi = bvs.len();
        bvs.push(json!({"buffer":0,"byteOffset":off,"byteLength":bin.len()-off,"target":34962}));
        let ai = ac.len();
        ac.push(json!({"bufferView":vi,"componentType":5126,"count":uv.len()/2,"type":"VEC2"}));
        let mut p = json!({"attributes":{"POSITION":attrs[0],"NORMAL":attrs[1],"TEXCOORD_0":ai},"material":mat});
        if mat == 3 || mat == 5 || mat == 6 || mat >= 8 {
            p["extensions"] = json!({"KHR_materials_variants":{"mappings":(0..6).map(|i|json!({"material":8+i,"variants":[i]})).collect::<Vec<_>>()}});
        }
        primitives.push(p);
    }
    let mut materials=COLORS.iter().enumerate().map(|(i,c)|json!({"name":format!("surface-{i}"),"pbrMetallicRoughness":{"baseColorFactor":c,"metallicFactor":if i==1{0.55}else{0.0},"roughnessFactor":if i==1{0.38}else{0.76}}})).collect::<Vec<_>>();
    let presets = [
        [0.16, 0.55, 0.57, 1.],
        [0.86, 0.43, 0.35, 1.],
        [0.93, 0.75, 0.28, 1.],
        [0.30, 0.42, 0.65, 1.],
        [0.48, 0.60, 0.42, 1.],
        [0.84, 0.78, 0.65, 1.],
    ];
    for c in presets {
        materials.push(json!({"pbrMetallicRoughness":{"baseColorFactor":c,"metallicFactor":0.0,"roughnessFactor":0.7}}));
    }
    for i in [0, 2, 7] {
        materials[i]["pbrMetallicRoughness"]["baseColorTexture"] =
            json!({"index":if i==0{0}else if i==2{1}else{2}});
        materials[i]["pbrMetallicRoughness"]["baseColorFactor"] = json!([1, 1, 1, 1]);
    }
    for i in [3, 5, 6, 8, 9, 10, 11, 12, 13] {
        materials[i]["pbrMetallicRoughness"]["baseColorTexture"] = json!({"index":1});
    }
    let prefix = if path
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|p| p.to_str())
        == Some("models")
    {
        "../textures/"
    } else {
        "textures/"
    };
    let d = json!({"asset":{"version":"2.0","generator":"resort-props certified primitive assembly"},"extensionsUsed":["KHR_materials_variants"],"extensions":{"KHR_materials_variants":{"variants":[{"name":"海灣青綠"},{"name":"珊瑚橘"},{"name":"日光黃"},{"name":"海軍藍"},{"name":"鼠尾草綠"},{"name":"沙灘米"}]}},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":name,"mesh":0,"rotation":[-0.7071067811865476,0,0,0.7071067811865476]}],"meshes":[{"name":name,"primitives":primitives}],"materials":materials,"images":[{"uri":format!("{prefix}teak.png")},{"uri":format!("{prefix}linen.png")},{"uri":format!("{prefix}stone.png")}],"textures":[{"sampler":0,"source":0},{"sampler":0,"source":1},{"sampler":0,"source":2}],"samplers":[{"wrapS":10497,"wrapT":10497,"magFilter":9729,"minFilter":9987}],"accessors":ac,"bufferViews":bvs,"buffers":[{"byteLength":bin.len()}]});
    let mut j = serde_json::to_vec(&d)?;
    while j.len() % 4 != 0 {
        j.push(b' ');
    }
    let mut bytes = b"glTF".to_vec();
    bytes.extend(2u32.to_le_bytes());
    bytes.extend(((28 + j.len() + bin.len()) as u32).to_le_bytes());
    bytes.extend((j.len() as u32).to_le_bytes());
    bytes.extend(b"JSON");
    bytes.extend(j);
    bytes.extend((bin.len() as u32).to_le_bytes());
    bytes.extend(b"BIN\0");
    bytes.extend(bin);
    fs::write(path, bytes)?;
    Ok((tris, [lo, hi]))
}
mod canopy;
mod activities;
mod landscape;
mod native_publication;
mod placement;
mod recipes;
mod verify;
fn build(root: &Path) -> R<()> {
    let out = root.join("output/street-social-city-production/resort-streetscape-v1");
    fs::create_dir_all(out.join("models"))?;
    landscape::textures(&out)?;
    let mut shapes = vec![];
    let mut proofs = vec![];
    for kind in ["unit-panel", "unit-cylinder"] {
        let p=root.join(format!("output/street-social-city-production/campus-v1/components/{kind}/remesh/remeshed-candidate.glb"));
        let report = read_json(&p.with_file_name("remesh-report.json"))?;
        assert_eq!(report["status"], "passed");
        assert_eq!(report["output_sha256"], sha(&p)?);
        shapes.push(source(&p)?);
        proofs.push(json!({"source":p,"sha256":sha(&p)?,"remesh_report":report}));
    }
    let (canopy, proof) = canopy::prepare(&out)?;
    shapes.push(canopy);
    proofs.push(proof);
    let mut rows = vec![];
    let mut all = vec![];
    for i in 0..100 {
        let name = recipes::NAMES[i];
        let mut lods = vec![];
        let mut base_bounds = [[0.; 3]; 2];
        for lod in 0..3 {
            let model = recipes::recipe(i, lod);
            let relative = format!("models/R{:03}-LOD{lod}.glb", i + 1);
            let (tris, bounds) = glb(&out.join(&relative), &model, &shapes, name)?;
            assert!(tris <= 12000);
            if lod == 0 {
                base_bounds = bounds;
                all.push(model);
            }
            lods.push(json!({"level":lod,"path":relative,"triangles":tris,"sha256":sha(&out.join(&relative))?}));
        }
        rows.push(json!({"id":format!("R{:03}",i+1),"name":name,"category":recipes::CATEGORIES[i/10],"bounds_m":base_bounds,"lods":lods,"color_presets":6,"construction":"assembled_from_certified_remeshed_primitives","cull_m":if i%10==0{220}else{100}}));
    }
    let placements = placement::place(root, &rows)?;
    let mut scene = Model::new();
    for p in placements["instances"].as_array().unwrap() {
        let i = p["asset_index"].as_u64().unwrap() as usize;
        let pos = p["position_m"].as_array().unwrap();
        let yaw = p["yaw_deg"].as_f64().unwrap().to_radians();
        for q in &all[i].parts {
            let mut q = q.clone();
            let x = q.p[0];
            let y = q.p[1];
            q.p[0] = pos[0].as_f64().unwrap() + x * yaw.cos() - y * yaw.sin();
            q.p[1] = pos[1].as_f64().unwrap() + x * yaw.sin() + y * yaw.cos();
            q.p[2] += pos[2].as_f64().unwrap();
            q.rot += yaw;
            if [3, 5, 6].contains(&q.mat) {
                q.mat = 8 + p["preset"].as_u64().unwrap() as usize;
            }
            scene.parts.push(q);
        }
    }
    let (scene_tris, _) = glb(
        &out.join("resort-layer.glb"),
        &scene,
        &shapes,
        "Resort world-coordinate layer",
    )?;
    write(&out.join("placement.json"), &placements)?;
    landscape::build(root, &out, &placements)?;
    write(
        &out.join("catalog.json"),
        &json!({"schema":1,"assets":rows,"presets":["#298c91","#db6e59","#edbf47","#4c6ba6","#7a996b","#d6c7a6"],"plant_variation":{"yaw_deg":[-12,12],"scale_xy":[0.94,1.0],"scale_z":[0.96,1.04],"leaf_tint_range":[0.88,1.08],"flower_presets":["ivory","coral","lilac","pink"]},"source_proofs":proofs,"native_project_modified":false}),
    )?;
    write(
        &out.join("acceptance.json"),
        &json!({"status":"geometry_and_placement_passed","distinct_types":100,"lod_files":300,"instances":placements["instances"].as_array().unwrap().len(),"layer_triangles_lod0":scene_tris,"color_variants_counted_as_types":false,"source_certificates_verified":3,"native_project_modified":false,"scope":"portable GLBs and world-coordinate placement; Unreal import not performed","placement_checks":placements["checks"]}),
    )?;
    let vendor = root.join("output/street-social-city-production/streetscape-variations-v1/vendor");
    copy_dir(&vendor, &out.join("vendor"))?;
    for file in ["index.html", "viewer.js"] {
        fs::copy(
            root.join("Tools/resort-props/viewer").join(file),
            out.join(file),
        )?;
    }
    fs::copy(
        root.join("Tools/resort-props/METHOD.md"),
        out.join("METHOD.md"),
    )?;
    let catalog = read_json(&out.join("catalog.json"))?;
    let table = catalog["assets"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| {
            format!(
                "<tr><td>{}</td><td>{}</td><td>{}</td><td>{} / {} / {}</td><td>{}</td></tr>",
                a["id"].as_str().unwrap(),
                a["name"].as_str().unwrap(),
                a["category"].as_str().unwrap(),
                a["lods"][0]["triangles"],
                a["lods"][1]["triangles"],
                a["lods"][2]["triangles"],
                a["lods"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|l| format!(
                        "<a href=\"{}\">LOD{}</a> ",
                        l["path"].as_str().unwrap(),
                        l["level"]
                    ))
                    .collect::<String>()
            )
        })
        .collect::<String>();
    let html = fs::read_to_string(out.join("index.html"))?.replace(
        "<tbody id=\"rows\"></tbody>",
        &format!("<tbody id=\"rows\">{table}</tbody>"),
    );
    fs::write(out.join("index.html"), html)?;
    println!("Built 100 distinct types / 300 LODs / {scene_tris} layer triangles");
    Ok(())
}
fn copy_dir(a: &Path, b: &Path) -> R<()> {
    fs::create_dir_all(b)?;
    for e in fs::read_dir(a)? {
        let e = e?;
        if e.file_type()?.is_dir() {
            copy_dir(&e.path(), &b.join(e.file_name()))?;
        } else {
            fs::copy(e.path(), b.join(e.file_name()))?;
        }
    }
    Ok(())
}
fn serve(root: &Path) -> R<()> {
    let out = root
        .join("output/street-social-city-production/resort-streetscape-v1")
        .canonicalize()?;
    for stream in TcpListener::bind("127.0.0.1:47983")?.incoming() {
        let mut s = stream?;
        s.set_read_timeout(Some(std::time::Duration::from_secs(3)))?;
        let mut b = [0u8; 8192];
        let n = s.read(&mut b)?;
        let req = String::from_utf8_lossy(&b[..n]);
        let path = req
            .split_whitespace()
            .nth(1)
            .unwrap_or("/")
            .split('?')
            .next()
            .unwrap();
        if req.starts_with("POST /capture ") {
            let boundary = b[..n].windows(4).position(|w| w == b"\r\n\r\n");
            let length = req.lines().find_map(|line| {
                line.to_ascii_lowercase()
                    .strip_prefix("content-length:")
                    .and_then(|v| v.trim().parse::<usize>().ok())
            });
            let origin = req
                .lines()
                .any(|line| line.eq_ignore_ascii_case("Origin: http://127.0.0.1:47983"));
            let marker = req
                .lines()
                .any(|line| line.eq_ignore_ascii_case("X-Resort-Preview: 1"));
            if let (Some(start), Some(len)) = (boundary, length) {
                if origin && marker && len < 12_000_000 {
                    let mut png = b[start + 4..n].to_vec();
                    while png.len() < len {
                        let count = s.read(&mut b)?;
                        if count == 0 {
                            break;
                        }
                        png.extend_from_slice(&b[..count]);
                    }
                    let valid = png.len() == len
                        && png.starts_with(b"\x89PNG\r\n\x1a\n")
                        && image::load_from_memory(&png)
                            .map(|p| p.width() <= 3000 && p.height() <= 3000)
                            .unwrap_or(false);
                    if valid {
                        fs::write(out.join("preview.png"), png)?;
                        s.write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK",
                        )?;
                        continue;
                    }
                }
            }
            s.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n")?;
            continue;
        }
        let p = out.join(if path == "/" {
            "index.html"
        } else {
            path.trim_start_matches('/')
        });
        let result = p
            .canonicalize()
            .ok()
            .filter(|p| p.starts_with(&out) && p.is_file())
            .and_then(|p| fs::read(p).ok());
        if let Some(data) = result {
            let mime = if path.ends_with("js") {
                "text/javascript"
            } else if path.ends_with("json") {
                "application/json"
            } else if path.ends_with("glb") {
                "model/gltf-binary"
            } else if path.ends_with("png") {
                "image/png"
            } else {
                "text/html; charset=utf-8"
            };
            let _=write!(s,"HTTP/1.1 200 OK\r\nContent-Type: {mime}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",data.len());
            let _ = s.write_all(&data);
        } else {
            let _ = s.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n");
        }
    }
    Ok(())
}
fn main() -> R<()> {
    let args: Vec<_> = std::env::args().collect();
    let root = PathBuf::from(args.get(2).map(|s| s.as_str()).unwrap_or(".")).canonicalize()?;
    match args.get(1).map(|s| s.as_str()).unwrap_or("build") {
        "build" => build(&root),
        "serve" => serve(&root),
        "verify" => verify::verify(&root),
        "activities-build" => activities::build(&root),
        "native-layout" => placement::native(&root),
        "native-publish" => native_publication::publish(
            &root,
            args.get(3).map(String::as_str) == Some("--visual-reviewed"),
        ),
        _ => Err("unknown command".into()),
    }
}
