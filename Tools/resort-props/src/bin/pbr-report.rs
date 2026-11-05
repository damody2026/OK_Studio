use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    path::{Path, PathBuf},
};
type R<T> = Result<T, Box<dyn std::error::Error>>;
fn read(p: &Path) -> R<Value> {
    Ok(serde_json::from_slice(&fs::read(p)?)?)
}
fn sha(p: &Path) -> R<String> {
    Ok(format!("{:x}", Sha256::digest(fs::read(p)?)))
}
fn esc(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}
fn write(p: &Path, v: &Value) -> R<()> {
    fs::write(p, serde_json::to_vec_pretty(v)?)?;
    Ok(())
}
fn main() -> R<()> {
    let root = PathBuf::from(
        std::env::args()
            .nth(1)
            .unwrap_or("C:/portable/OpenKoikatsu".into()),
    );
    let out = root.join("output/street-social-city-production/pbr-grok-v1");
    if std::env::args().any(|s| s == "--contact") {
        let render = read(&out.join("render.json"))?;
        let rows = render["images"].as_array().unwrap();
        let mut sheet = image::RgbImage::new(1600, rows.len().div_ceil(4) as u32 * 250);
        for (i, r) in rows.iter().enumerate() {
            let im = image::open(r["path"].as_str().unwrap())?
                .resize_exact(400, 250, image::imageops::FilterType::Triangle)
                .to_rgb8();
            image::imageops::replace(&mut sheet, &im, (i % 4 * 400) as i64, (i / 4 * 250) as i64);
        }
        sheet.save(out.join("native-contact.png"))?;
        return Ok(());
    }
    let reviewed = std::env::args().any(|s| s == "--visual-reviewed");
    assert!(
        reviewed,
        "Inspect native render captures before publication"
    );
    let inventory = read(&out.join("inventory.json"))?;
    let plan = read(&out.join("plan.json"))?;
    let repair = read(&out.join("repair.json"))?;
    let audit = read(&out.join("audit.json"))?;
    let render = read(&out.join("render.json"))?;
    assert_eq!(repair["status"], "passed");
    assert_eq!(audit["status"], "passed");
    assert_eq!(render["status"], "passed");
    assert_eq!(render["run_id"], audit["run_id"]);
    let map = root.join("StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap");
    assert_eq!(sha(&map)?, render["map_sha256"]);
    let mut native_materials = vec![];
    for row in inventory["parents"].as_array().unwrap() {
        let path = row["path"].as_str().unwrap();
        let relative = path
            .split('.')
            .next()
            .unwrap()
            .strip_prefix("/Game/")
            .ok_or("Material outside native project")?;
        let package = root
            .join("StreetSocialCity/Content")
            .join(format!("{relative}.uasset"));
        native_materials.push(json!({"asset":path,"package_sha256":sha(&package)?}));
    }
    let logs = fs::read_to_string(out.join("render-editor.log"))?
        + &fs::read_to_string(out.join("repair-editor.log"))?;
    let errors: Vec<_> = logs
        .lines()
        .filter(|s| {
            let s = s.to_lowercase();
            s.contains("failed to compile material")
                || s.contains("logshadercompilers: error")
                || ((s.contains("[sm6]") || s.contains("[sm5]")) && s.contains("error"))
        })
        .collect();
    assert!(errors.is_empty(), "Shader errors: {errors:?}");
    let mut gallery = String::new();
    let mut generated = vec![];
    let mut families = BTreeMap::new();
    for row in plan["rows"].as_array().unwrap() {
        if row["action"] == "repair" {
            *families
                .entry(row["family"].as_str().unwrap().to_owned())
                .or_insert(0usize) += 1;
        }
    }
    for d in fs::read_dir(out.join("maps"))? {
        let d = d?;
        if !d.file_type()?.is_dir() {
            continue;
        }
        let folder = d.path();
        let name = d.file_name().to_string_lossy().to_string();
        let receipt = read(&folder.join("generation.json"))?;
        assert_eq!(sha(&folder.join("normal.png"))?, receipt["normal_sha256"]);
        assert_eq!(sha(&folder.join("orm.png"))?, receipt["orm_sha256"]);
        assert_eq!(
            sha(Path::new(receipt["grok_original"].as_str().unwrap()))?,
            receipt["grok_sha256"]
        );
        assert_eq!(
            sha(Path::new(receipt["event_log"].as_str().unwrap()))?,
            receipt["event_sha256"]
        );
        let norm = image::open(folder.join("normal.png"))?.to_rgb8();
        let orm = image::open(folder.join("orm.png"))?.to_rgb8();
        assert_eq!(norm.dimensions(), (1024, 1024));
        assert_eq!(orm.dimensions(), (1024, 1024));
        let mut max_error = 0f32;
        for p in norm.pixels().step_by(7) {
            let n = p.0.map(|b| b as f32 / 255. * 2. - 1.);
            let l = (n.iter().map(|a| a * a).sum::<f32>()).sqrt();
            max_error = max_error.max((l - 1.).abs());
            assert!(n[2] > 0.7);
        }
        assert!(
            max_error < 0.015,
            "Invalid normal length {name}: {max_error}"
        );
        let m = (receipt["metallic"].as_f64().unwrap() * 255.) as u8;
        for p in orm.pixels().step_by(7) {
            assert_eq!(p[0], 255);
            assert_eq!(p[2], m);
        }
        generated.push(json!({"family":name,"normal_sha256":receipt["normal_sha256"],"orm_sha256":receipt["orm_sha256"],"normal_max_length_error":max_error,"used_parents":families.get(&name).copied().unwrap_or(0),"grok_receipt":receipt}));
        gallery+=&format!("<article><h3>{}</h3><p>套用 {} 個母材質</p><div class=trio><figure><img src=\"maps/{}/height.png\"><figcaption>Grok 高度來源</figcaption></figure><figure><img src=\"maps/{}/normal.png\"><figcaption>數值轉換 Normal</figcaption></figure><figure><img src=\"maps/{}/orm.png\"><figcaption>ORM：G粗糙／B金屬</figcaption></figure></div></article>",esc(&name),families.get(&name).copied().unwrap_or(0),name,name,name);
    }
    assert_eq!(generated.len(), 16);
    let mut shots = String::new();
    let mut captures = vec![];
    for row in render["images"].as_array().unwrap() {
        let path = Path::new(row["path"].as_str().unwrap());
        assert_eq!(sha(path)?, row["sha256"]);
        let im = image::open(path)?.to_rgb8();
        assert_eq!(im.dimensions(), (1600, 1000));
        let name = row["view"].as_str().unwrap();
        shots+=&format!("<figure><a href=\"renders/{name}.png\"><img src=\"renders/{name}.png\"></a><figcaption>{name} · Unreal 原生實拍</figcaption></figure>");
        captures.push(row.clone());
    }
    assert_eq!(captures.len(), 17);
    let mut table = String::new();
    for row in plan["rows"].as_array().unwrap() {
        let c = row["channels"]
            .as_array()
            .unwrap()
            .iter()
            .filter_map(Value::as_str)
            .collect::<Vec<_>>()
            .join(", ");
        table += &format!(
            "<tr><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td></tr>",
            esc(row["path"].as_str().unwrap()),
            esc(row["action"].as_str().unwrap()),
            esc(row["family"]
                .as_str()
                .unwrap_or("constant / dedicated shader")),
            esc(&c),
            esc(row["reason"].as_str().unwrap())
        );
    }
    let page = format!(
        r#"<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>全城 Grok PBR 原生驗收</title><style>body{{font:16px system-ui;margin:auto;max-width:1500px;padding:28px;background:#121b25;color:#e4edf2}}h1,h2{{color:#e9c88b}}a{{color:#8edbd5}}img{{width:100%;display:block}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:20px}}.trio{{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}}figure{{margin:0}}article,figure{{background:#1b2935;padding:12px;border-radius:8px}}figcaption{{padding:8px}}table{{border-collapse:collapse;width:100%;font-size:13px}}td,th{{padding:9px;border:1px solid #43515a;overflow-wrap:anywhere}}input{{font:inherit;padding:12px;width:90%;margin:20px 0}}.scroll{{overflow:auto}}p{{line-height:1.7}}</style><h1>全城缺漏 PBR · Grok Build 補製</h1><p>實際盤點 {} 個材質、{} 個母材質；已補 {} 個，保留 {} 個。重新開啟正式 Unreal 地圖，{} 項原生檢查通過。</p><p>Grok 生成 16 類微觀高度原圖；Rust 由高度計算法線與校正 ORM，並非直接拿照片冒充 Normal。所有成品 1K，共享貼圖與 mipmap，未增加模型面數。原有底色、三語文字、透明遮罩、六色、LOD 保留。玻璃、水、鏡子、發光螢幕不新增 N/M/R 圖，保留常數參數與專用材質。</p><p><a href="METHOD.md">完整流程與回復方式</a> · <a href="audit.json">重新開圖檢查</a> · <a href="verification.json">原圖工具證據／數值驗收</a> · <a href="backups.json">原材質備份</a></p><h2>正式 Unreal 場景</h2><p>沿用原本相機、光照及布局，無另擺展示道具。材質微細變化近看較明顯，不會改變原有美術配色。</p><div class=grid>{shots}</div><h2>Grok 原圖與 PBR 成品</h2><div class=grid>{gallery}</div><h2>逐材質盤點與處理</h2><input placeholder="搜尋材質、類別、repair / preserve" oninput="document.querySelectorAll('tbody tr').forEach(r=>r.hidden=!r.textContent.toLowerCase().includes(this.value.toLowerCase()))"><div class=scroll><table><thead><tr><th>原生材質路徑</th><th>處理</th><th>類別</th><th>待補通道</th><th>依據</th></tr></thead><tbody>{table}</tbody></table></div></html>"#,
        inventory["materials"].as_array().unwrap().len(),
        inventory["parents"].as_array().unwrap().len(),
        audit["repaired"],
        audit["preserved"],
        audit["checks"]
    );
    fs::copy(
        root.join("Docs/STREET_CITY_PBR_GROK.md"),
        out.join("METHOD.md"),
    )?;
    fs::write(out.join("index.html"), page)?;
    write(
        &out.join("verification.json"),
        &json!({"status":"passed","native_project_modified":true,"run_id":render["run_id"],"map_sha256":render["map_sha256"],"materials":audit["materials"],"parents":audit["parents"],"repaired":audit["repaired"],"preserved":audit["preserved"],"checks":audit["checks"],"generated":generated,"captures":captures,"native_material_packages":native_materials,"manual_visual_review":true,"shader_errors":errors,"normal_maps_are_derived_from_grok_height":true,"no_geometry_changes":true}),
    )?;
    println!(
        "Published native PBR report: {} repaired, {} preserved, {} checks, {} actual captures",
        audit["repaired"],
        audit["preserved"],
        audit["checks"],
        captures.len()
    );
    Ok(())
}
