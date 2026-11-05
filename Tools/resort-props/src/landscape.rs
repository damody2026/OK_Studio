use super::*;
pub fn textures(out: &Path) -> R<()> {
    fs::create_dir_all(out.join("textures"))?;
    for name in ["teak", "linen", "stone"] {
        let mut im = image::RgbImage::new(1024, 1024);
        for (y, row) in im.rows_mut().enumerate() {
            for (x, p) in row.enumerate() {
                let (x, y) = (x as f64, y as f64);
                let noise = (((x as u32).wrapping_mul(73856093)
                    ^ (y as u32).wrapping_mul(19349663))
                    % 101) as f64
                    / 100.;
                let (base, n) = match name {
                    "teak" => (
                        [163., 119., 74.],
                        (x * 0.31 + (y * 0.024).sin() * 3. + (y * 0.071).sin()).sin() * 9.
                            + (x * 0.051 + (y * 0.016).sin() * 2.).sin() * 13.
                            + noise * 6.,
                    ),
                    "linen" => (
                        [238., 234., 222.],
                        (x * std::f64::consts::PI / 2.).sin() * 4.
                            + (y * std::f64::consts::PI / 2.).sin() * 4.
                            + noise * 3.,
                    ),
                    _ => (
                        [185., 188., 177.],
                        noise * 15. + (x * 0.04 + y * 0.03).sin() * 4.,
                    ),
                };
                *p = image::Rgb(base.map(|c| (c + n).clamp(0., 255.) as u8));
            }
        }
        im.save(out.join("textures").join(format!("{name}.png")))?;
    }
    Ok(())
}
pub fn build(root: &Path, out: &Path, placements: &Value) -> R<()> {
    let base = root.join("output/street-social-city-production");
    let old = read_json(&base.join("streetscape-variations-v1/variation-manifest.json"))?;
    let trees: Vec<Value> = old["instances"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| {
            ["camphor", "cherry"].contains(&p["asset"].as_str().unwrap_or(""))
                && p["after"]["position_m"][1].as_f64().unwrap_or(999.) < 550.
        })
        .cloned()
        .collect();
    for name in ["camphor", "cherry"] {
        for lod in 0..3 {
            let filename = format!("{name}-LOD{lod}.glb");
            let row = old["models"]
                .as_array()
                .unwrap()
                .iter()
                .find(|p| p["id"] == name && p["level"] == lod)
                .ok_or("missing tree LOD proof")?;
            assert_eq!(
                row["sha256"],
                sha(&base
                    .join("streetscape-variations-v1/models")
                    .join(&filename))?
            );
            fs::copy(
                base.join("streetscape-variations-v1/models")
                    .join(&filename),
                out.join("models").join(filename),
            )?;
        }
    }
    copy_dir(
        &base.join("streetscape-variations-v1/textures"),
        &out.join("textures"),
    )?;
    let registry = read_json(&base.join("streetscape-v1/active-asset-registry.json"))?;
    let asset = registry["assets"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["id"] == "bed-flowers")
        .ok_or("missing remeshed flowers")?;
    let flower = PathBuf::from(asset["lods"][0]["path"].as_str().unwrap());
    assert_eq!(asset["lods"][0]["sha256"], sha(&flower)?);
    fs::copy(&flower, out.join("models/bed-flowers.glb"))?;
    let mut flowers = vec![];
    for p in placements["instances"].as_array().unwrap() {
        let i = p["asset_index"].as_u64().unwrap() as usize;
        let fit = match i {
            40 => Some(([0., 0., 0.45], [1.7, 0.27, 0.3])),
            41 => Some(([0., 0., 0.64], [0.85, 0.85, 0.35])),
            43 => Some(([0., 0., 1.2], [1.8, 0.55, 0.28])),
            44 => Some(([0., 0.25, 1.15], [1.8, 0.2, 0.3])),
            45 => Some(([0., 0., 0.18], [2.2, 0.8, 0.35])),
            46 => Some(([0., 0., 0.5], [2.8, 0.8, 0.35])),
            47 => Some(([0., 0., 1.45], [1.8, 0.5, 0.35])),
            59 => Some(([0.65, 0., 2.37], [0.45, 0.45, 0.3])),
            _ => None,
        };
        if let Some((offset, size)) = fit {
            let j = flowers.len();
            let yaw = ((j * 37 % 241) as f64 / 10. - 12.).clamp(-12., 12.);
            let xy = 0.94 + (j * 17 % 61) as f64 / 1000.;
            let zz = 0.96 + (j * 13 % 81) as f64 / 1000.;
            let parent_yaw = p["yaw_deg"].as_f64().unwrap().to_radians();
            let position = [
                p["position_m"][0].as_f64().unwrap() + offset[0] * parent_yaw.cos()
                    - offset[1] * parent_yaw.sin(),
                p["position_m"][1].as_f64().unwrap()
                    + offset[0] * parent_yaw.sin()
                    + offset[1] * parent_yaw.cos(),
                p["position_m"][2].as_f64().unwrap() + offset[2],
            ];
            flowers.push(json!({"parent":p["id"],"model":"models/bed-flowers.glb","offset_m":offset,"fit_size_m":size,"position_m":position,"world_yaw_deg":p["yaw_deg"].as_f64().unwrap()+yaw,"yaw_delta_deg":yaw,"scale_xy":xy,"scale_z":zz,"palette":j%4,"leaf_factor":0.90+(j*7%17)as f64/100.,"render_rule":"hue-classified petal tint; preserve green leaves and original texture shading"}));
        }
    }
    write(
        &out.join("plantings.json"),
        &json!({"schema":1,"flowers":flowers,"existing_tree_variants":trees,"trees_are_existing_context_not_additional_object_types":true,"source_flower":asset,"source_variation_sha256":sha(&base.join("streetscape-variations-v1/variation-manifest.json"))?,"new_tripo_generations":0,"method":"reuse certified remeshed flower geometry and trees; no new organic mesh required"}),
    )?;
    Ok(())
}
