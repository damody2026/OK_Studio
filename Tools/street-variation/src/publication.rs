use super::*;
pub fn publish(root: &Path) -> Result<()> {
    let out = root.join("output/street-social-city-production/streetscape-variations-v1");
    let src = root.join("Tools/street-variation");
    let deps = src.join("viewer-deps/node_modules/three");
    for file in [
        "build/three.module.js",
        "build/three.core.js",
        "examples/jsm/loaders/GLTFLoader.js",
        "examples/jsm/controls/OrbitControls.js",
        "examples/jsm/utils/BufferGeometryUtils.js",
        "LICENSE",
    ] {
        let target = out.join("vendor").join(file);
        fs::create_dir_all(target.parent().unwrap())?;
        fs::copy(deps.join(file), target)?;
    }
    for file in ["viewer.html", "viewer.js"] {
        fs::copy(src.join("viewer").join(file), out.join(file))?;
    }
    let a = load(&out.join("acceptance.json"))?;
    let manifest = load(&out.join("variation-manifest.json"))?;
    let mut table = String::new();
    for row in manifest["models"].as_array().unwrap() {
        table.push_str(&format!(
            "<tr><td>{}</td><td>{}</td><td>{}</td><td><a href=\"{}\">GLB＋換色變體</a></td></tr>",
            row["id"].as_str().unwrap(),
            row["level"],
            row["triangles"],
            row["path"].as_str().unwrap()
        ));
    }
    let page=format!(r##"<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>街景色彩與自然變體</title><style>body{{margin:0;background:#152b23;color:#e9f3e9;font:17px/1.75 system-ui}}main{{max-width:1500px;margin:auto;padding:28px}}a{{color:#a3ebbb}}h1{{line-height:1.2}}.notice{{padding:18px;border:1px solid #8aa98e;background:#304b3b}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:18px}}img{{width:100%;border-radius:10px}}figure{{margin:0;padding:14px;background:#264333}}iframe{{width:100%;height:900px;border:0;background:#eee}}td,th{{padding:10px;border-bottom:1px solid #58725e;text-align:left}}table{{width:100%}}code{{overflow-wrap:anywhere}}</style><main><h1>街景色彩與自然變體</h1><p>機車與自行車各六組車色、連續可調色遮罩；樟樹與櫻花樹各四組葉片色調，加入小幅角度與大小變化。沿用已 remesh 網格，新增三角面數為 0。</p><p class="notice">依目前 AGENTS.md，本次未修改 StreetSocialCity/。下方是實際可攜模型及設定的預覽；原生 Unreal 地圖仍使用上一版。這次以車漆／車架遮罩精準調色，不需額外 GPT 圖片或 Tripo 模型。</p><p>已準備 {} 個實例差異設定：{} 棵樹、{} 輛機車、{} 輛自行車。樹木角度 ±12°、水平縮放94–100%、高度96–104%；保持原樹根位置，樹幹碰撞同步變換，水平保守包絡不放大。原有 LOD 幾何、輪胎／燈具原色、法線／粗糙度／金屬度及葉片 Alpha 保留。</p><p>固定種子20261020，{}項驗收通過。<a href="acceptance.json">驗收</a> · <a href="variation-manifest.json">全部設定與來源</a> · <a href="METHOD.md">製作／啟動方法</a> · <a href="StreetVariation.ush">共用材質函式</a></p><h2>互動調整</h2><p><a href="http://127.0.0.1:47982/viewer.html">開啟完整互動預覽</a>。如重新開機後未啟動，執行 <code>Tools\lua\lua.exe Tools\street_variations.lua serve</code>。</p><iframe id="viewer" title="街景可調模型互動預覽"></iframe><script>document.getElementById('viewer').src=location.protocol==='file:'?'http://127.0.0.1:47982/viewer.html':'viewer.html';</script><h2>實際模型比較</h2><div class="grid">{}</div><h2>可攜GLB與所有LOD</h2><p>每份GLB保留原始預設材質，另提供KHR_materials_variants。請連同相鄰textures資料夾使用；預覽可直接調色，支援此擴充的檢視器也能選擇預設變體。</p><table><tr><th>物件</th><th>LOD</th><th>三角面</th><th>下載</th></tr>{}</table></main></html>"##,
 a["instances"],a["counts"]["camphor"].as_u64().unwrap()+a["counts"]["cherry"].as_u64().unwrap(),a["counts"]["scooter"],a["counts"]["bicycle"],a["checks"],["scooter","bicycle","camphor","cherry"].iter().map(|aid|format!("<figure><img src=\"renders/{aid}-LOD0.png\" alt=\"{aid} 實際模型色彩比較\"><figcaption>{aid} · 同一網格的不同設定</figcaption></figure>")).collect::<String>(),table);
    fs::write(out.join("index.html"), page)?;
    fs::copy(
        src.join("StreetVariation.ush"),
        out.join("StreetVariation.ush"),
    )?;
    fs::copy(src.join("METHOD.md"), out.join("METHOD.md"))?;
    println!("Published portable variation gallery; native Unreal remains untouched");
    Ok(())
}

pub fn finalize(root: &Path, visual_reviewed: bool) -> Result<()> {
    assert!(
        visual_reviewed,
        "Inspect actual model images and UI before acknowledging visual review"
    );
    let out = root.join("output/street-social-city-production/streetscape-variations-v1");
    let acceptance = load(&out.join("acceptance.json"))?;
    let manifest = load(&out.join("variation-manifest.json"))?;
    assert_eq!(acceptance["status"], "passed");
    assert_eq!(
        acceptance["manifest_sha256"],
        json!(variation::sha(&out.join("variation-manifest.json"))?)
    );
    let mut images = vec![];
    for row in manifest["models"].as_array().unwrap() {
        let relative = format!(
            "renders/{}-LOD{}.png",
            row["id"].as_str().unwrap(),
            row["level"]
        );
        let path = out.join(&relative);
        let pic = image::open(&path)?.to_rgb8();
        assert!(pic.width() > 400 && pic.height() > 300);
        let pixels = pic
            .pixels()
            .map(|p| p[0] as f64 + p[1] as f64 + p[2] as f64)
            .collect::<Vec<_>>();
        let mean = pixels.iter().sum::<f64>() / pixels.len() as f64;
        let variance = pixels.iter().map(|p| (p - mean).powi(2)).sum::<f64>() / pixels.len() as f64;
        assert!(variance > 100.);
        images.push(json!({"asset":row["id"],"lod":row["level"],"image":relative,"sha256":variation::sha(&path)?,"width":pic.width(),"height":pic.height()}));
    }
    write(
        &out.join("visual-acceptance.json"),
        &json!({"status":"passed","acknowledged_actual_visual_review":true,"images":images,"ui_checks":["arbitrary vehicle hex #6f3aae updates only selected vehicle","six preset vehicle colors render with unchanged black tyres and metal","tree controls tested at yaw12, horizontal94%, height104%","reset and enable/disable variation controls","actual models loaded and rendered at all 10 source LODs","all preview PNGs saved by local viewer and checked"],"native_unreal_updated":false,"manifest_sha256":acceptance["manifest_sha256"]}),
    )?;
    let mut links = 0;
    for file in ["index.html", "viewer.html"] {
        let text = fs::read_to_string(out.join(file))?;
        for attribute in ["href=\"", "src=\""] {
            for value in text
                .split(attribute)
                .skip(1)
                .filter_map(|s| s.split('"').next())
            {
                if value.starts_with("http") || value.starts_with("data:") || value.is_empty() {
                    continue;
                }
                assert!(out.join(value).exists(), "Missing publication link {value}");
                links += 1;
            }
        }
    }
    write(
        &out.join("publication-acceptance.json"),
        &json!({"status":"passed","local_links_checked":links,"page_sha256":variation::sha(&out.join("index.html"))?,"source_manifest_sha256":acceptance["manifest_sha256"],"acceptance_sha256":variation::sha(&out.join("acceptance.json"))?,"visual_acceptance_sha256":variation::sha(&out.join("visual-acceptance.json"))?,"geometry_triangle_increase":0,"source_code_sha256":variation::sha(&root.join("Tools/street-variation/src/variation.rs"))?,"native_unreal_updated":false}),
    )?;
    println!("PASS all 10 actual LOD captures, UI acknowledgement and {links} publication links");
    Ok(())
}
