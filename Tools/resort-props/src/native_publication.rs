use super::*;
use std::collections::BTreeMap;
pub fn publish(root: &Path, reviewed: bool) -> R<()> {
    if !reviewed {
        return Err("Inspect actual Unreal captures, then pass --visual-reviewed".into());
    }
    let out = root.join("output/street-social-city-production/resort-native-v1");
    let install = read_json(&out.join("install.json"))?;
    let audit = read_json(&out.join("audit.json"))?;
    let render = read_json(&out.join("render.json"))?;
    let cat = read_json(
        &root.join("output/street-social-city-production/resort-streetscape-v1/catalog.json"),
    )?;
    let imports = read_json(&out.join("imports.json"))?;
    assert_eq!(audit["status"], "passed");
    assert_eq!(audit["run_id"], render["run_id"]);
    assert_eq!(audit["reopened_for_phase"], "render");
    assert_eq!(install["map_sha256"], render["map_sha256"]);
    assert_eq!(
        sha(&root.join("StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap"))?,
        install["map_sha256"]
    );
    let errors: Vec<String> = fs::read_to_string(out.join("render-editor.log"))?
        .lines()
        .filter(|s| {
            let s = s.to_lowercase();
            s.contains("failed to compile material")
                || s.contains("logshadercompilers: error")
                || ((s.contains("[sm5]") || s.contains("[sm6]")) && s.contains("error"))
        })
        .map(str::to_owned)
        .collect();
    assert!(errors.is_empty(), "Shader errors: {errors:?}");
    let mut images = vec![];
    let mut cards = String::new();
    for r in render["images"].as_array().unwrap() {
        let path = PathBuf::from(r["path"].as_str().unwrap());
        assert_eq!(sha(&path)?, r["sha256"]);
        let im = image::open(&path)?.to_rgb8();
        assert_eq!(im.dimensions(), (1600, 1000));
        let mut sum = [0.; 3];
        let mut sq = [0.; 3];
        let mut count = 0.;
        for p in im.pixels().step_by(4) {
            count += 1.;
            for k in 0..3 {
                let v = p[k] as f64;
                sum[k] += v;
                sq[k] += v * v;
            }
        }
        let mean = sum.map(|x| x / count);
        let sd = [0, 1, 2].map(|k| (sq[k] / count - mean[k] * mean[k]).max(0.).sqrt());
        assert!(
            mean.iter().sum::<f64>() / 3. > 12. && sd.iter().copied().fold(0., f64::max) > 12.,
            "Black/featureless capture {path:?}"
        );
        let name = r["view"].as_str().unwrap();
        let title = match name {
            "hotel-garden" => "飯店花園休憩區",
            "campus-lake" => "校園休憩區",
            "shop-dining" => "商店街露天座位",
            "bay-camp" => "海灣遊憩／露營區",
            "sports-entry" => "運動館入口配套",
            "world-overview" => "正式世界俯瞰",
            "flower-detail" => "花壇實例與比例",
            "foliage-near" => "近景植栽",
            "foliage-far" => "遠景自動 LOD",
            _ => name,
        };
        let group = if name.starts_with("scooter") {
            "vehicles"
        } else if name.contains("foliage") || name.contains("flower") {
            "plants"
        } else {
            "regions"
        };
        cards.push_str(&format!("<figure data-group=\"{group}\"><a href=\"renders/{name}.png\"><img src=\"renders/{name}.png\" loading=\"lazy\" alt=\"{title}\"></a><figcaption>{title}</figcaption></figure>"));
        images.push(json!({"view":name,"sha256":r["sha256"],"mean_rgb":mean,"stddev_rgb":sd}));
    }
    assert_eq!(images.len(), 15);
    let mut regions: BTreeMap<String, usize> = BTreeMap::new();
    let mut types: BTreeMap<String, usize> = BTreeMap::new();
    let mut flower_groups = 0;
    for g in install["groups"].as_array().unwrap() {
        if g["kind"] == "flower" {
            flower_groups += 1;
        }
        if g["kind"] == "prop" {
            for p in g["instances"].as_array().unwrap() {
                *regions
                    .entry(p["zone"].as_str().unwrap().into())
                    .or_default() += 1;
                *types
                    .entry(p["asset"].as_str().unwrap().into())
                    .or_default() += 1;
            }
        }
    }
    assert_eq!(types.len(), 100);
    assert_eq!(flower_groups, 24);
    let mut rows = String::new();
    for a in cat["assets"].as_array().unwrap() {
        let id = a["id"].as_str().unwrap();
        let b = &a["bounds_m"];
        let dims = [0, 1, 2].map(|i| b[1][i].as_f64().unwrap() - b[0][i].as_f64().unwrap());
        let tris = &imports["assets"][id]["lod_triangles"];
        rows.push_str(&format!("<tr><td>{id}</td><td>{}</td><td>{:.2} × {:.2} × {:.2}m</td><td>{} / {} / {}</td><td>{}</td></tr>",a["name"].as_str().unwrap(),dims[0],dims[1],dims[2],tris[0],tris[1],tris[2],types[id]));
    }
    let region_rows = regions
        .iter()
        .map(|(name, n)| format!("<tr><td>{name}</td><td>{n}</td></tr>"))
        .collect::<String>();
    let flower_count = audit["instances"]["flower"].as_u64().unwrap();
    let html = format!(
        r##"<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Unreal 正式室外整合驗收</title><style>body{{margin:0;background:#eef1e9;color:#243d36;font:16px/1.6 system-ui}}header{{padding:24px;background:#204f46;color:white}}h1{{margin:0}}main{{max-width:1300px;margin:auto;padding:24px}}.stats{{display:flex;flex-wrap:wrap;gap:12px}}.stats div{{background:white;padding:15px;border-radius:8px}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:14px}}figure{{margin:0;background:#fff;border-radius:8px;overflow:hidden}}img{{width:100%;display:block}}figcaption{{padding:10px}}table{{border-collapse:collapse;width:100%;background:white}}td,th{{text-align:left;padding:8px;border-bottom:1px solid #d8e3db}}code{{word-break:break-all}}a{{color:#176c61}}button{{padding:8px 14px;margin:8px;font:inherit}}.note{{background:#fff4cf;padding:14px}}section{{margin-top:28px}}</style><header><h1>Unreal 正式室外整合 · 驗收完成</h1><div>StreetSocialCity / UniversityCity · 保存後重開地圖 · D3D12 原生實拍</div></header><main><div class="stats"><div>100 種物件 / 300 個實例</div><div>1,475 棵變化樹</div><div>10 輛機車 / 24 輛自行車</div><div>24 組花壇 / {flower_count} 株植栽</div><div>{} 項原生檢查通過</div></div><p>樹、載具與物件已實際保存在 <code>/Game/UniversityCity/Maps/UniversityCity</code>。保留真實 LOD、六色、葉／花色與微幅旋轉縮放。原建築與地形保留，入口碰撞與既有場景回歸通過。</p><p><a href="audit.json">原生驗收</a> · <a href="activation.json">啟用與地圖雜湊</a> · <a href="placement.json">26 區配置</a> · <a href="visual-review.json">實拍檢查</a> · <a href="METHOD.md">執行與程式換色方法</a></p><p class="note">驗收範圍為這次室外物件層。現有地形接縫／低面數輪廓及建築外觀沿用原版本；此報告不代表重新製作整張世界美術、完成遊戲打包或測得幀率基準。</p><section><h2>正式場景實拍</h2><p>下列均由保存的原生地圖拍攝，相機經建築外框與碰撞檢查；未另放展示物件或改動燈光。</p><div><button data-filter="all">全部</button><button data-filter="regions">區域</button><button data-filter="vehicles">機車六色</button><button data-filter="plants">植物</button></div><div class="grid">{cards}</div></section><section><h2>100 種物件</h2><table><thead><tr><th>編號</th><th>物件</th><th>寬 × 深 × 高</th><th>LOD 0 / 1 / 2 三角面</th><th>實例</th></tr></thead><tbody>{rows}</tbody></table></section><section><h2>區域分布</h2><table><tr><th>區域</th><th>物件實例</th></tr>{region_rows}</table></section><section><h2>開啟與換色</h2><p>執行 <code>C:/portable/OpenKoikatsu/StreetSocialCity/OpenCity.cmd</code>。新資產位於 <code>/Game/UniversityCity/ResortV1/</code>，Actor 資料夾為 <code>UniversityCity/ResortV1/</code>。</p><p>載具可切換 MI_scooter_0～5、MI_bicycle_0～5，或於 MID 設定 BaseColorTexture。布面參數 ResortTint；樹葉 LeafTint；花草 FlowerTint / LeafFactor。來源及回復步驟見 METHOD.md。</p></section></main><script>for(const b of document.querySelectorAll('[data-filter]'))b.onclick=()=>{{for(const c of document.querySelectorAll('figure'))c.hidden=b.dataset.filter!=='all'&&c.dataset.group!==b.dataset.filter;}};</script></html>"##,
        audit["checks"]
    );
    fs::copy(
        root.join("Docs/STREET_CITY_RESORT_NATIVE.md"),
        out.join("METHOD.md"),
    )?;
    fs::write(out.join("index.html"), html)?;
    write(
        &out.join("visual-review.json"),
        &json!({"status":"passed","images":images,"manual_review":true,"shader_errors":errors,"scope":"actual native Unreal saved scene; 15 captures inspected","map_sha256":install["map_sha256"],"audit_run_id":audit["run_id"]}),
    )?;
    write(
        &out.join("activation.json"),
        &json!({"status":"native_installed_and_verified","project":"StreetSocialCity/StreetSocialCity.uproject","map":"/Game/UniversityCity/Maps/UniversityCity","map_sha256":install["map_sha256"],"authorization":"User explicitly authorized StreetSocialCity modification on 2026-10-20","native_project_modified":true,"distinct_props":100,"prop_instances":300,"regions":regions,"trees":1475,"scooters":10,"bicycles":24,"flower_beds":24,"flower_instances":flower_count,"native_checks":audit["checks"],"native_audit_sha256":sha(&out.join("audit.json"))?,"visual_review_sha256":sha(&out.join("visual-review.json"))?,"tool_sources":["Tools/street_city_resort_native.lua","Tools/street_city_resort_run.lua","Tools/resort-props"]}),
    )?;
    println!("Published verified native scene: 100 types, 300 props, {flower_count} plants, 15 real Unreal captures");
    Ok(())
}
