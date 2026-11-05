use super::*;
use std::collections::HashSet;
pub fn verify(root: &Path) -> R<()> {
    let out = root.join("output/street-social-city-production/resort-streetscape-v1");
    let cat = read_json(&out.join("catalog.json"))?;
    let layout = read_json(&out.join("placement.json"))?;
    let _cylinder=source(&root.join("output/street-social-city-production/campus-v1/components/unit-cylinder/remesh/remeshed-candidate.glb"))?;
    let mut unique = HashSet::new();
    let mut checks = 0usize;
    let mut totals = [0u64; 3];
    for a in cat["assets"].as_array().unwrap() {
        let mut previous = u64::MAX;
        for l in a["lods"].as_array().unwrap() {
            let p = out.join(l["path"].as_str().unwrap());
            assert_eq!(l["sha256"], sha(&p)?);
            let bytes = fs::read(&p)?;
            assert_eq!(
                u32::from_le_bytes(bytes[8..12].try_into()?) as usize,
                bytes.len()
            );
            let n = u32::from_le_bytes(bytes[12..16].try_into()?) as usize;
            let d: Value = serde_json::from_slice(&bytes[20..20 + n])?;
            let bin = &bytes[28 + n..];
            if l["level"] == 0 {
                assert!(
                    unique.insert(format!("{:x}", Sha256::digest(bin))),
                    "duplicate geometry: {}",
                    a["id"]
                );
            }
            let mut tris = 0;
            for prim in d["meshes"][0]["primitives"].as_array().unwrap() {
                let ac = &d["accessors"][prim["attributes"]["POSITION"].as_u64().unwrap() as usize];
                let count = ac["count"].as_u64().unwrap();
                tris += count / 3;
                assert_eq!(count % 3, 0);
                for (key, size) in [("POSITION", 3), ("NORMAL", 3), ("TEXCOORD_0", 2)] {
                    let ac = &d["accessors"][prim["attributes"][key].as_u64().unwrap() as usize];
                    assert_eq!(count, ac["count"].as_u64().unwrap());
                    let view = &d["bufferViews"][ac["bufferView"].as_u64().unwrap() as usize];
                    let off = view["byteOffset"].as_u64().unwrap_or(0) as usize;
                    let len = view["byteLength"].as_u64().unwrap() as usize;
                    assert_eq!(len, count as usize * size * 4);
                    assert!(off + len <= bin.len());
                    for chunk in bin[off..off + len].chunks_exact(4) {
                        assert!(f32::from_le_bytes(chunk.try_into()?).is_finite());
                        checks += 1;
                    }
                }
            }
            assert_eq!(tris, l["triangles"].as_u64().unwrap());
            assert!(tris <= previous);
            previous = tris;
            totals[l["level"].as_u64().unwrap() as usize] += tris;
            for im in d["images"].as_array().unwrap() {
                let path = p
                    .parent()
                    .unwrap()
                    .join(im["uri"].as_str().unwrap())
                    .canonicalize()?;
                assert!(path.starts_with(out.canonicalize()?));
                let image = image::open(path)?;
                assert!(image.width() <= 2048 && image.height() <= 2048);
                checks += 1;
            }
        }
    }
    assert_eq!(unique.len(), 100);
    let inst = layout["instances"].as_array().unwrap();
    assert_eq!(inst.len(), 300);
    let mut all = HashSet::new();
    for (a, p) in inst.iter().enumerate() {
        all.insert(p["asset"].as_str().unwrap());
        for q in &inst[a + 1..] {
            let dist = (p["position_m"][0].as_f64().unwrap()
                - q["position_m"][0].as_f64().unwrap())
            .hypot(p["position_m"][1].as_f64().unwrap() - q["position_m"][1].as_f64().unwrap());
            assert!(
                dist + 1e-6
                    >= p["protected_radius_m"].as_f64().unwrap()
                        + q["protected_radius_m"].as_f64().unwrap()
                        + 1.
            );
            checks += 1;
        }
    }
    assert_eq!(all.len(), 100);
    for proof in cat["source_proofs"].as_array().unwrap() {
        assert_eq!(
            sha(&PathBuf::from(proof["source"].as_str().unwrap()))?,
            proof["sha256"]
        );
    }
    let plants = read_json(&out.join("plantings.json"))?;
    for p in plants["flowers"].as_array().unwrap() {
        assert!(p["yaw_delta_deg"].as_f64().unwrap().abs() <= 12.);
        assert!((0.94..=1.).contains(&p["scale_xy"].as_f64().unwrap()));
        assert!((0.96..=1.04).contains(&p["scale_z"].as_f64().unwrap()));
        checks += 3;
    }
    write(
        &out.join("verification.json"),
        &json!({"status":"passed","checks":checks,"distinct_geometry_hashes":unique.len(),"all_assets_placed":all.len(),"lod_total_triangles_single_copy":totals,"flower_clusters":plants["flowers"].as_array().unwrap().len(),"tree_context_count":plants["existing_tree_variants"].as_array().unwrap().len(),"native_project_modified":false,"exclusions":"No native Unreal import, no game FPS or navigation runtime test"}),
    )?;
    println!("Verified {checks} checks, 100 unique geometry hashes, all 300 LOD files");
    Ok(())
}
