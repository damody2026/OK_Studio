use super::*;
use image::{GrayImage, Luma, RgbaImage};
use sha2::{Digest, Sha256};
use std::{
    io::{Read, Write},
    net::TcpListener,
};
pub fn sha(path: &Path) -> Result<String> {
    Ok(format!("{:x}", Sha256::digest(fs::read(path)?)))
}
fn folder(root: &Path) -> PathBuf {
    root.join("output/street-social-city-production/streetscape-variations-v1")
}
fn linear(v: f64) -> f64 {
    if v <= 0.04045 {
        v / 12.92
    } else {
        ((v + 0.055) / 1.055).powf(2.4)
    }
}
fn srgb(v: f64) -> u8 {
    let v = v.clamp(0., 1.);
    ((if v <= 0.0031308 {
        12.92 * v
    } else {
        1.055 * v.powf(1. / 2.4) - 0.055
    }) * 255.)
        .round() as u8
}
fn smooth(a: f64, b: f64, v: f64) -> f64 {
    let t = ((v - a) / (b - a)).clamp(0., 1.);
    t * t * (3. - 2. * t)
}
fn hsv(rgb: [u8; 3]) -> (f64, f64, f64) {
    let [r, g, b] = rgb.map(|v| v as f64 / 255.);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let d = max - min;
    let h = if d < 1e-8 {
        0.
    } else if max == r {
        60. * ((g - b) / d).rem_euclid(6.)
    } else if max == g {
        60. * ((b - r) / d + 2.)
    } else {
        60. * ((r - g) / d + 4.)
    };
    (h, if max > 0. { d / max } else { 0. }, max)
}
fn hex(s: &str) -> [f64; 3] {
    let v = u32::from_str_radix(s.trim_start_matches('#'), 16).unwrap();
    [
        ((v >> 16) & 255) as f64 / 255.,
        ((v >> 8) & 255) as f64 / 255.,
        (v & 255) as f64 / 255.,
    ]
}
fn palette(aid: &str) -> Vec<Value> {
    let values = if aid == "cherry" {
        vec![
            ("柔粉", "#fff5fa"),
            ("淡白粉", "#fffdf6"),
            ("冷粉", "#f5e5ff"),
            ("暖粉", "#fff0e6"),
        ]
    } else if aid == "camphor" {
        vec![
            ("新葉綠", "#edffe4"),
            ("深葉綠", "#d9efdf"),
            ("暖葉綠", "#fff6de"),
            ("自然綠", "#f8fff4"),
        ]
    } else {
        vec![
            ("青綠", "#417f80"),
            ("酒紅", "#a83d46"),
            ("奶油白", "#e7dcc5"),
            ("海軍藍", "#3e5e93"),
            ("芥末黃", "#caa039"),
            ("石墨灰", "#59636b"),
        ]
    };
    values.iter().enumerate().map(|(i,(name,color))|json!({"id":i,"name":name,"hex":color,"linear_rgb":hex(color).map(linear)})).collect()
}
fn mask_image(aid: &str, image: &RgbaImage) -> (GrayImage, f64) {
    let mut mask = GrayImage::new(image.width(), image.height());
    let mut values = vec![];
    for (x, y, p) in image.enumerate_pixels() {
        let (h, s, v) = hsv([p[0], p[1], p[2]]);
        let m = if aid == "scooter" {
            smooth(135., 150., h)
                * (1. - smooth(210., 225., h))
                * smooth(0.065, 0.14, s)
                * smooth(0.07, 0.16, v)
        } else {
            smooth(65., 85., h)
                * (1. - smooth(160., 180., h))
                * smooth(0.065, 0.15, s)
                * smooth(0.065, 0.15, v)
        };
        let m = (m * 255.).round() as u8;
        mask.put_pixel(x, y, Luma([m]));
        if m > 240 {
            values.push(linear(v));
        }
    }
    values.sort_by(|a, b| a.total_cmp(b));
    let reference = if values.is_empty() {
        0.15
    } else {
        values[values.len() / 2]
    };
    (mask, reference.max(0.025))
}
fn paint(original: &RgbaImage, mask: &GrayImage, color: [f64; 3], reference: f64) -> RgbaImage {
    let color = color.map(linear);
    let mut image = original.clone();
    for (x, y, p) in image.enumerate_pixels_mut() {
        let weight = mask.get_pixel(x, y)[0] as f64 / 255.;
        if weight == 0. {
            continue;
        }
        let source = [
            linear(p[0] as f64 / 255.),
            linear(p[1] as f64 / 255.),
            linear(p[2] as f64 / 255.),
        ];
        let shade = (source[0].max(source[1]).max(source[2]) / reference).clamp(0.15, 1.8);
        for c in 0..3 {
            p[c] = srgb(source[c] * (1. - weight) + color[c] * shade * weight)
        }
    }
    image
}
fn triangles(glb: &Glb) -> u64 {
    glb.doc["meshes"]
        .as_array()
        .unwrap()
        .iter()
        .flat_map(|m| m["primitives"].as_array().unwrap())
        .map(|p| {
            let a = p["indices"]
                .as_u64()
                .unwrap_or_else(|| p["attributes"]["POSITION"].as_u64().unwrap())
                as usize;
            glb.doc["accessors"][a]["count"].as_u64().unwrap() / 3
        })
        .sum()
}
fn hash_unit(id: &str, lane: u8) -> f64 {
    let d = Sha256::digest(format!("street-variation-v1|20261020|{id}|{lane}").as_bytes());
    u32::from_le_bytes(d[..4].try_into().unwrap()) as f64 / u32::MAX as f64
}
pub fn build(root: &Path) -> Result<()> {
    let out = folder(root);
    let base = root.join("output/street-social-city-production/streetscape-v1");
    let delivery = load(&base.join("delivery.json"))?;
    fs::create_dir_all(out.join("models"))?;
    let mut registry = vec![];
    for asset in delivery["assets"].as_array().unwrap() {
        let aid = asset["id"].as_str().unwrap();
        if !["scooter", "bicycle", "camphor", "cherry"].contains(&aid) {
            continue;
        }
        let palettes = palette(aid);
        let vehicle = ["scooter", "bicycle"].contains(&aid);
        let texture_dir = out.join("textures").join(aid);
        fs::create_dir_all(&texture_dir)?;
        let mut reference = 0.;
        let mut mask_path = Value::Null;
        let mut paint_pixels = 0;
        let mut total_pixels = 0;
        for lod in asset["lods"].as_array().unwrap() {
            let source = PathBuf::from(lod["path"].as_str().unwrap());
            let mut glb = Glb::read(&source)?;
            let source_bin_sha = format!("{:x}", Sha256::digest(&glb.bin));
            let original_materials = glb.doc["materials"].as_array().unwrap().clone();
            let mut mappings = vec![];
            for (mi, material) in original_materials.iter().enumerate() {
                let eligible = vehicle || material["alphaMode"] == "MASK";
                if !eligible {
                    continue;
                }
                let mut palette_indices = vec![];
                if vehicle {
                    let texture = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
                        .as_u64()
                        .ok_or("Vehicle has no base-color texture")?
                        as usize;
                    let image_index =
                        glb.doc["textures"][texture]["source"].as_u64().unwrap() as usize;
                    let original = image::load_from_memory(glb.image(image_index)?)?.to_rgba8();
                    let (mask, refvalue) = mask_image(aid, &original);
                    reference = refvalue;
                    if lod["level"] == 0 {
                        mask.save(texture_dir.join("paint-mask.png"))?;
                        paint_pixels = mask.pixels().filter(|p| p[0] > 0).count();
                        total_pixels = (mask.width() * mask.height()) as usize;
                        assert!(paint_pixels > total_pixels / 100, "Empty paint region");
                        assert!(
                            paint_pixels < total_pixels * 3 / 4,
                            "Mask recolors most hardware"
                        );
                        mask_path = json!(format!("textures/{aid}/paint-mask.png"));
                        for p in &palettes {
                            paint(&original, &mask, hex(p["hex"].as_str().unwrap()), reference)
                                .save(texture_dir.join(format!("paint-{}.png", p["id"])))?;
                        }
                    }
                }
                for p in &palettes {
                    let mut new = material.clone();
                    new["name"] =
                        json!(format!("{aid}-{}-{}", p["id"], p["name"].as_str().unwrap()));
                    if vehicle {
                        let image_index = glb.doc["images"].as_array().unwrap().len();
                        glb.doc["images"]
                            .as_array_mut()
                            .unwrap()
                            .push(json!({"uri":format!("../textures/{aid}/paint-{}.png",p["id"])}));
                        let ti = glb.doc["textures"].as_array().unwrap().len();
                        glb.doc["textures"]
                            .as_array_mut()
                            .unwrap()
                            .push(json!({"source":image_index,"sampler":0}));
                        new["pbrMetallicRoughness"]["baseColorTexture"]["index"] = json!(ti);
                    } else {
                        new["pbrMetallicRoughness"]["baseColorFactor"] = json!([
                            p["linear_rgb"][0],
                            p["linear_rgb"][1],
                            p["linear_rgb"][2],
                            1.
                        ]);
                    }
                    let n = glb.doc["materials"].as_array().unwrap().len();
                    glb.doc["materials"].as_array_mut().unwrap().push(new);
                    palette_indices.push(json!({"material":n,"variants":[p["id"]]}));
                }
                mappings.push((mi, palette_indices));
            }
            for mesh in glb.doc["meshes"].as_array_mut().unwrap() {
                for primitive in mesh["primitives"].as_array_mut().unwrap() {
                    if let Some((_, map)) = mappings
                        .iter()
                        .find(|(mi, _)| primitive["material"].as_u64() == Some(*mi as u64))
                    {
                        primitive["extensions"]["KHR_materials_variants"]["mappings"] = json!(map);
                    }
                }
            }
            glb.doc["extensions"]["KHR_materials_variants"]["variants"] = json!(palettes
                .iter()
                .map(|p| json!({"name":p["name"]}))
                .collect::<Vec<_>>());
            if glb.doc["extensionsUsed"].is_null() {
                glb.doc["extensionsUsed"] = json!([])
            }
            if !glb.doc["extensionsUsed"]
                .as_array()
                .unwrap()
                .iter()
                .any(|x| x == "KHR_materials_variants")
            {
                glb.doc["extensionsUsed"]
                    .as_array_mut()
                    .unwrap()
                    .push(json!("KHR_materials_variants"));
            }
            glb.doc["extras"]["street_variation"] = json!({"asset":aid,"vehicle":vehicle,"mask_uri":if vehicle{json!(format!("../textures/{aid}/paint-mask.png"))}else{Value::Null},"paint_reference_linear_value":reference,"mode":"shared geometry, original texture plus paint mask, linear RGB target"});
            let relative = format!("models/{aid}-LOD{}.glb", lod["level"]);
            glb.save(&out.join(&relative))?;
            registry.push(json!({"id":aid,"level":lod["level"],"path":relative,"source":source,"source_sha256":sha(&source)?,"sha256":sha(&out.join(&relative))?,"binary_sha256":source_bin_sha,"triangles":triangles(&glb),"palettes":palettes,"mask":mask_path,"paint_reference_linear_value":reference,"paint_pixels":paint_pixels,"total_pixels":total_pixels,"source_remesh_certificates":lod.get("certified_sources").cloned().unwrap_or(json!([])),"source_lod_record":lod}));
        }
    }
    let mut deltas = vec![];
    let mut collider_deltas = vec![];
    for group in delivery["groups"].as_array().unwrap() {
        for instance in group["instances"].as_array().unwrap() {
            let aid = group["asset"].as_str().unwrap();
            if !["scooter", "bicycle", "camphor", "cherry"].contains(&aid) {
                continue;
            }
            let id = instance["id"].as_str().unwrap();
            let tree = ["camphor", "cherry"].contains(&aid);
            let mut next = instance.clone();
            let color = ((hash_unit(id, 0) * palette(aid).len() as f64).floor() as usize)
                .min(palette(aid).len() - 1);
            let tint = palette(aid)[color]["linear_rgb"].clone();
            let yaw = if tree {
                (hash_unit(id, 1) * 2. - 1.) * 12.
            } else {
                0.
            };
            let xy = if tree {
                0.94 + hash_unit(id, 2) * 0.06
            } else {
                1.
            };
            let z = if tree {
                0.96 + hash_unit(id, 3) * 0.08
            } else {
                1.
            };
            next["yaw_deg"] = json!(instance["yaw_deg"].as_f64().unwrap() + yaw);
            next["scale"] = json!([
                instance["scale"][0].as_f64().unwrap() * xy,
                instance["scale"][1].as_f64().unwrap() * xy,
                instance["scale"][2].as_f64().unwrap() * z
            ]);
            next["variation"] = json!({"palette":color,"linear_rgb":tint,"yaw_delta_deg":yaw,"horizontal_factor":xy,"height_factor":z,"root_pivot_unchanged":true});
            if tree {
                collider_deltas.push(json!({"id":format!("{id}-trunk"),"tree_id":id,"position_m":next["position_m"],"yaw_deg":next["yaw_deg"],"scale":next["scale"]}));
            }
            deltas.push(json!({"id":id,"asset":aid,"source_group":group["label"],"before":instance,"after":next}));
        }
    }
    write(
        &out.join("variation-manifest.json"),
        &json!({"status":"built_requires_verification","source_delivery":base.join("delivery.json"),"source_delivery_sha256":sha(&base.join("delivery.json"))?,"source_acceptance_sha256":sha(&base.join("acceptance.json"))?,"seed":20261020,"models":registry,"instances":deltas,"trunk_colliders":collider_deltas,"runtime":{"material_instance_per_actor":false,"custom_data_floats":3,"custom_data_semantics":["PaintOrLeafTintLinearR","PaintOrLeafTintLinearG","PaintOrLeafTintLinearB"],"preserve_existing_lod_thresholds":true,"preserve_existing_cull_distances":true,"tree_yaw_delta_max_degrees":12,"tree_horizontal_scale_range":[0.94,1.],"tree_height_scale_range":[0.96,1.04],"root_position_unchanged":true},"unreal_integration":{"status":"not_applied","reason":"Current AGENTS.md prohibits modifying StreetSocialCity/; delivery is portable GLBs, material contract and deterministic instance deltas outside that project."}}),
    )?;
    println!(
        "Built {} model/LOD packages and {} deterministic variations",
        registry.len(),
        deltas.len()
    );
    verify(root)
}
pub fn verify(root: &Path) -> Result<()> {
    let out = folder(root);
    let manifest = load(&out.join("variation-manifest.json"))?;
    let mut checks = 0;
    let source_path = PathBuf::from(manifest["source_delivery"].as_str().unwrap());
    assert_eq!(sha(&source_path)?, manifest["source_delivery_sha256"]);
    let baseline = load(&source_path)?;
    let mut original_instances = std::collections::HashMap::new();
    for group in baseline["groups"].as_array().unwrap() {
        for instance in group["instances"].as_array().unwrap() {
            if ["scooter", "bicycle", "camphor", "cherry"]
                .contains(&group["asset"].as_str().unwrap())
            {
                assert!(original_instances
                    .insert(
                        instance["id"].as_str().unwrap(),
                        (
                            group["asset"].clone(),
                            group["label"].clone(),
                            instance.clone()
                        )
                    )
                    .is_none());
            }
        }
    }
    assert_eq!(
        manifest["instances"].as_array().unwrap().len(),
        original_instances.len()
    );
    checks += 1;
    let mut totals = serde_json::Map::new();
    for row in manifest["models"].as_array().unwrap() {
        let source = PathBuf::from(row["source"].as_str().unwrap());
        assert_eq!(sha(&source)?, row["source_sha256"]);
        let old = Glb::read(&source)?;
        let path = out.join(row["path"].as_str().unwrap());
        assert_eq!(sha(&path)?, row["sha256"]);
        let new = Glb::read(&path)?;
        assert_eq!(
            old.bin, new.bin,
            "Geometry/UV/normal/original texture bytes changed"
        );
        for key in ["accessors", "bufferViews", "nodes", "scenes", "scene"] {
            assert_eq!(
                old.doc[key], new.doc[key],
                "Source structure changed: {key}"
            );
        }
        assert_eq!(triangles(&old), triangles(&new));
        let mut unchanged_meshes = new.doc["meshes"].clone();
        for (mesh_index, mesh) in unchanged_meshes
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .enumerate()
        {
            for (primitive_index, primitive) in mesh["primitives"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .enumerate()
            {
                let original = &old.doc["meshes"][mesh_index]["primitives"][primitive_index];
                if let Some(maps) =
                    primitive["extensions"]["KHR_materials_variants"]["mappings"].as_array()
                {
                    let source_material =
                        &old.doc["materials"][original["material"].as_u64().unwrap() as usize];
                    for mapping in maps {
                        let material =
                            &new.doc["materials"][mapping["material"].as_u64().unwrap() as usize];
                        assert_eq!(source_material["normalTexture"], material["normalTexture"]);
                        assert_eq!(
                            source_material["pbrMetallicRoughness"]["metallicRoughnessTexture"],
                            material["pbrMetallicRoughness"]["metallicRoughnessTexture"]
                        );
                        assert_eq!(
                            source_material["pbrMetallicRoughness"]["roughnessFactor"],
                            material["pbrMetallicRoughness"]["roughnessFactor"]
                        );
                        checks += 3;
                    }
                }
                if let Some(ext) = primitive
                    .get_mut("extensions")
                    .and_then(|v| v.as_object_mut())
                {
                    ext.remove("KHR_materials_variants");
                    if ext.is_empty() && original.get("extensions").is_none() {
                        primitive.as_object_mut().unwrap().remove("extensions");
                    }
                }
            }
        }
        assert_eq!(unchanged_meshes, old.doc["meshes"]);
        for (index, material) in old.doc["materials"].as_array().unwrap().iter().enumerate() {
            assert_eq!(material, &new.doc["materials"][index]);
            checks += 1;
        }
        for img in new.doc["images"].as_array().unwrap() {
            if let Some(uri) = img["uri"].as_str() {
                let texture = path.parent().unwrap().join(uri);
                assert!(texture.is_file());
                let image = image::open(texture)?;
                assert!(image.width() <= 2048 && image.height() <= 2048);
                checks += 2;
            }
        }
        checks += 10;
        if ["scooter", "bicycle"].contains(&row["id"].as_str().unwrap()) {
            for (mi, m) in old.doc["materials"].as_array().unwrap().iter().enumerate() {
                let ti = m["pbrMetallicRoughness"]["baseColorTexture"]["index"]
                    .as_u64()
                    .unwrap() as usize;
                let ii = old.doc["textures"][ti]["source"].as_u64().unwrap() as usize;
                let original = image::load_from_memory(old.image(ii)?)?.to_rgba8();
                let mask = image::open(out.join(row["mask"].as_str().unwrap()))?.into_luma8();
                let mut different = std::collections::HashSet::new();
                for p in row["palettes"].as_array().unwrap() {
                    let painted = image::open(out.join(format!(
                        "textures/{}/paint-{}.png",
                        row["id"].as_str().unwrap(),
                        p["id"]
                    )))?
                    .to_rgba8();
                    assert!(painted.width() <= 2048 && painted.height() <= 2048);
                    assert_eq!(painted.dimensions(), original.dimensions());
                    for (x, y, pixel) in original.enumerate_pixels() {
                        let other = painted.get_pixel(x, y);
                        if mask.get_pixel(x, y)[0] == 0 {
                            assert_eq!(pixel, other, "Unpainted tyre/chrome/light pixels changed");
                        }
                        assert_eq!(pixel[3], other[3]);
                    }
                    different.insert(sha(&out.join(format!(
                        "textures/{}/paint-{}.png",
                        row["id"].as_str().unwrap(),
                        p["id"]
                    )))?);
                    checks += 3;
                }
                assert_eq!(different.len(), row["palettes"].as_array().unwrap().len());
                let _ = mi;
            }
        } else {
            let n = old.doc["materials"].as_array().unwrap().len();
            for material in new.doc["materials"].as_array().unwrap().iter().skip(n) {
                assert_eq!(material["alphaMode"], "MASK");
                assert_eq!(material["doubleSided"], true);
                assert!((material["alphaCutoff"].as_f64().unwrap() - 0.33).abs() < 1e-5);
                checks += 3;
            }
        }
    }
    let colliders = manifest["trunk_colliders"].as_array().unwrap();
    let mut all_ids = std::collections::HashSet::new();
    for row in manifest["instances"].as_array().unwrap() {
        let before = &row["before"];
        let after = &row["after"];
        let (original_asset, original_group, original) = original_instances
            .get(row["id"].as_str().unwrap())
            .ok_or("Variation references unknown source instance")?;
        assert_eq!(original, before);
        assert_eq!(original_asset, &row["asset"]);
        assert_eq!(original_group, &row["source_group"]);
        checks += 3;
        assert!(all_ids.insert(row["id"].as_str().unwrap()));
        assert_eq!(before["position_m"], after["position_m"]);
        let aid = row["asset"].as_str().unwrap();
        let tree = ["camphor", "cherry"].contains(&aid);
        if tree {
            let v = &after["variation"];
            assert!(v["yaw_delta_deg"].as_f64().unwrap().abs() <= 12.);
            let xy = v["horizontal_factor"].as_f64().unwrap();
            let z = v["height_factor"].as_f64().unwrap();
            assert!((0.94..=1.).contains(&xy) && (0.96..=1.04).contains(&z));
            for axis in 0..2 {
                assert!(
                    after["scale"][axis].as_f64().unwrap()
                        <= before["scale"][axis].as_f64().unwrap()
                );
            }
            let collider = colliders
                .iter()
                .find(|c| c["tree_id"] == row["id"])
                .ok_or("Missing matching trunk collision transform")?;
            assert_eq!(collider["position_m"], after["position_m"]);
            assert_eq!(collider["yaw_deg"], after["yaw_deg"]);
            assert_eq!(collider["scale"], after["scale"]);
            checks += 7;
        } else {
            for axis in 0..3 {
                assert_eq!(
                    before["scale"][axis].as_f64(),
                    after["scale"][axis].as_f64()
                );
            }
            assert_eq!(before["yaw_deg"].as_f64(), after["yaw_deg"].as_f64());
            checks += 2;
        }
        let n = totals.entry(aid).or_insert(json!(0));
        *n = json!(n.as_u64().unwrap() + 1);
        checks += 2;
    }
    write(
        &out.join("acceptance.json"),
        &json!({"status":"passed","checks":checks,"models":manifest["models"].as_array().unwrap().len(),"instances":manifest["instances"].as_array().unwrap().len(),"counts":totals,"seed":manifest["seed"],"geometry_bytes_unchanged":true,"triangle_increase":0,"normal_roughness_metalness_unchanged":true,"unmasked_pixels_exactly_unchanged":true,"root_positions_unchanged":true,"crown_conservative_horizontal_envelope_never_enlarged":true,"collider_transforms_match_trees":true,"manifest_sha256":sha(&out.join("variation-manifest.json"))?,"native_unreal_updated":false,"reason":"StreetSocialCity/ protected by current AGENTS.md; native integration not claimed."}),
    )?;
    println!("PASS {checks} checks; geometry +0 triangles, protected hardware pixels unchanged");
    Ok(())
}
pub fn serve(root: &Path, port: u16) -> Result<()> {
    let out = folder(root).canonicalize()?;
    let server = TcpListener::bind(("127.0.0.1", port))?;
    println!("Street variation preview http://127.0.0.1:{port}/index.html");
    for stream in server.incoming() {
        let out = out.clone();
        let mut stream = stream?;
        std::thread::spawn(move || {
            let _ = stream.set_read_timeout(Some(std::time::Duration::from_secs(20)));
            let mut request = Vec::new();
            let header_end = loop {
                let mut part = [0; 8192];
                let n = stream.read(&mut part).unwrap_or(0);
                if n == 0 {
                    return;
                }
                request.extend_from_slice(&part[..n]);
                if let Some(i) = request.windows(4).position(|p| p == b"\r\n\r\n") {
                    break i + 4;
                }
                if request.len() > 16384 {
                    return;
                }
            };
            let line = String::from_utf8_lossy(&request[..header_end]).into_owned();
            let uri = line
                .split_whitespace()
                .nth(1)
                .unwrap_or("/")
                .split('?')
                .next()
                .unwrap_or("/");
            if line.starts_with("POST ") {
                let name = uri.trim_start_matches("/capture/");
                let allowed = ["scooter", "bicycle", "camphor", "cherry"]
                    .iter()
                    .any(|a| (0..3).any(|l| name == format!("{a}-LOD{l}.png")));
                let origin = format!("origin: http://127.0.0.1:{port}");
                let header = line.to_ascii_lowercase();
                let size = header
                    .lines()
                    .find_map(|s| {
                        s.strip_prefix("content-length:")
                            .and_then(|s| s.trim().parse::<usize>().ok())
                    })
                    .unwrap_or(0);
                if !uri.starts_with("/capture/")
                    || !allowed
                    || !header.lines().any(|s| s.trim() == origin)
                    || !header.contains("x-street-preview: 1")
                    || size == 0
                    || size > 12 * 1024 * 1024
                {
                    return;
                }
                while request.len() < header_end + size {
                    let mut part = [0; 16384];
                    let n = stream.read(&mut part).unwrap_or(0);
                    if n == 0 {
                        return;
                    }
                    request.extend_from_slice(&part[..n]);
                }
                let bytes = &request[header_end..header_end + size];
                if !bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
                    return;
                }
                if let Ok(pic) = image::load_from_memory(bytes) {
                    if pic.width() > 3000 || pic.height() > 3000 {
                        return;
                    }
                } else {
                    return;
                }
                let target = out.join("renders").join(name);
                if fs::create_dir_all(target.parent().unwrap()).is_err()
                    || fs::write(&target, bytes).is_err()
                {
                    return;
                }
                let _=stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 18\r\nConnection: close\r\n\r\n{\"status\":\"saved\"}");
                return;
            }
            if !line.starts_with("GET ") {
                return;
            }
            let relative = if uri == "/" {
                "index.html"
            } else {
                uri.trim_start_matches('/')
            };
            let path = out.join(relative);
            let valid = path
                .canonicalize()
                .ok()
                .filter(|p| p.starts_with(&out) && p.is_file());
            if let Some(path) = valid {
                if let Ok(body) = fs::read(&path) {
                    let mime = match path.extension().and_then(|s| s.to_str()).unwrap_or("") {
                        "html" => "text/html; charset=utf-8",
                        "js" | "mjs" => "text/javascript",
                        "json" => "application/json",
                        "png" => "image/png",
                        "glb" => "model/gltf-binary",
                        "css" => "text/css",
                        "md" => "text/plain; charset=utf-8",
                        _ => "application/octet-stream",
                    };
                    let _=write!(stream,"HTTP/1.1 200 OK\r\nContent-Type: {mime}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",body.len());
                    let _ = stream.write_all(&body);
                    return;
                }
            }
            let _ = stream.write_all(
                b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            );
        });
    }
    Ok(())
}
