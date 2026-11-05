// Street-social ground PBR. One native Grok albedo per set; normal and ORM are derived estimates.
// Final maps are exactly 1024x1024. Albedo content is image_gen; seam conditioning and maps are derived.
use image::{imageops::FilterType, Rgb, RgbImage};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

type R<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;

struct Family {
    id: &'static str,
    roles: &'static [&'static str],
    roughness: f32,
    spread: f32,
    gain: f32,
    period_m: f32,
    variations: [&'static str; 3],
}

const FAMILIES: &[Family] = &[
    Family { id: "lawn_turf", roles: &["turf"], roughness: 0.86, spread: 0.05, gain: 1.8, period_m: 0.90, variations: [
        "maintained lawn turf of short dense blades in rich mid green with slight yellow-green shifts, each blade a few millimetres wide and overlapping its neighbours",
        "healthy maintained olive-green campus lawn, dense short living green blades with less than one percent tiny straw tips; overall clearly leaf green, never tan or brown, no bare patches",
        "lush medium natural leaf-green short resort lawn, fine narrow densely packed freshly cut blades, varied light and dark green chlorophyll; clearly green with no cyan, teal, blue or turquoise tint, no flowers",
    ]},
    Family { id: "meadow_grass", roles: &["turf"], roughness: 0.90, spread: 0.06, gain: 1.2, period_m: 1.10, variations: [
        "unmown meadow sward, mixed blade lengths in living green, dense overlapping blades without a mower stripe",
        "sun-warmed meadow, more yellow-green blades and tiny tan seed tips kept small and evenly scattered, not one repeated hero stalk",
        "damper meadow, deeper green and slightly broader blades, still dense, soft and fully covering",
    ]},
    Family { id: "planting_soil", roles: &["soil"], roughness: 0.94, spread: 0.04, gain: 1.7, period_m: 0.60, variations: [
        "dark chocolate-brown loam broken into irregular moist crumbs a few millimetres across, with tiny pale organic flecks and fine root specks",
        "wetter near-black loam, finer crumbs plus a few larger 10 mm clods and more decomposed leaf crumbs, still real soil",
        "loam mixed with reddish-brown mineral crumbs and charcoal-dark organic crumbs, uneven aggregates rather than one brown tone",
    ]},
    Family { id: "asphalt", roles: &["road"], roughness: 0.78, spread: 0.04, gain: 1.1, period_m: 1.50, variations: [
        "fresh dense-graded asphalt, dark neutral gray binder with fine exposed stones a few millimetres across, dry and even",
        "lightly oxidized asphalt, warmer mid gray, a little more exposed sand and small aggregate, no cracks",
        "cooler blue-gray asphalt with a slightly more open fine texture, still continuous pavement",
    ]},
    Family { id: "pedestrian_pavers", roles: &["walk"], roughness: 0.64, spread: 0.05, gain: 1.5, period_m: 2.40, variations: [
        "warm honey limestone rectangular pavers in stack bond, each module 300 mm by 150 mm including a narrow 4 mm joint, eight by sixteen units filling the tile",
        "warmer sandstone rectangles, each module 400 mm by 200 mm including a narrow joint, six by twelve units, with a little more mineral speckle",
        "pale buff stone rectangles, each module 600 mm by 300 mm including a narrow gray joint, four by eight units, calm and even",
    ]},
    Family { id: "campus_concrete", roles: &["walk"], roughness: 0.74, spread: 0.04, gain: 0.85, period_m: 2.00, variations: [
        "light warm-gray broom-finished campus concrete, fine directional micro-striations, no control joints and no stains",
        "cooler gray concrete with more exposed fine sand, a softer float-broom mix, planar",
        "cream-gray wood-float concrete, low contrast and a slightly more open sand, no formwork lines",
    ]},
    Family { id: "beach_sand", roles: &["sand"], roughness: 0.92, spread: 0.03, gain: 0.7, period_m: 0.80, variations: [
        "dry pale warm beach sand, fine even grains, a light ivory-tan",
        "slightly damp darker tan sand, grains a little more clumped, no footprints",
        "cooler shell-pale sand with tiny crushed-shell dust, still a fine grain field without whole shells",
    ]},
    Family { id: "river_gravel", roles: &["walk"], roughness: 0.82, spread: 0.05, gain: 1.2, period_m: 0.70, variations: [
        "small rounded river pebbles about 8 to 20 mm, mixed gray and tan, tightly packed with a little sand in the gaps",
        "warmer brown-gray river gravel, slightly smaller pebbles, denser and more uniform",
        "cooler slate and cream pebbles, still small and rounded, no single hero stone",
    ]},
    Family { id: "timber_deck", roles: &["deck"], roughness: 0.56, spread: 0.05, gain: 2.2, period_m: 1.00, variations: [
        "outdoor honey teak, fine straight grain, warm gold fibre, a continuous field",
        "deeper amber teak with tighter dark grain lines and a slight satin, still only fibre",
        "sun-faded silver-honey teak fibre, fine raised grain, continuous and weathered",
    ]},
    Family { id: "terracotta_paving", roles: &["walk"], roughness: 0.70, spread: 0.05, gain: 1.6, period_m: 1.20, variations: [
        "pale salmon terracotta clay pavers, module 200 mm by 100 mm including a narrow joint, six by twelve units, fine clay pores",
        "deeper burnt-sienna clay pavers, the same 200 mm by 100 mm module, more iron flecks, narrow even joints",
        "dusty rose terracotta pavers, a slightly more open clay, the same repeating module and narrow cream-gray joints",
    ]},
    Family { id: "rubber_track", roles: &["court"], roughness: 0.88, spread: 0.03, gain: 0.65, period_m: 1.00, variations: [
        "red vulcanized rubber track granules, fine and matte, classic brick red, an even broadcast surface",
        "deeper brick-red rubber granules, slightly coarser, still an even broadcast surface",
        "muted terracotta-red rubber with a few darker granules mixed through, no markings",
    ]},
    Family { id: "acrylic_court", roles: &["court"], roughness: 0.42, spread: 0.03, gain: 0.4, period_m: 2.00, variations: [
        "matte mid-blue acrylic sports coating with fine sand texture, a continuous playing surface",
        "deeper court blue acrylic, the same fine sand tooth, a slightly denser colour",
        "cooler blue-gray acrylic coating, even and matte, with no markings of any kind",
    ]},
    Family { id: "tactile_paving", roles: &["walk"], roughness: 0.76, spread: 0.03, gain: 0.35, period_m: 0.60, variations: [
        "warm yellow-buff concrete micrograin, flat and even, the colour of a safety paving tile without any raised pattern",
        "slightly more ochre yellow concrete, finer pores, still a flat material sample",
        "cooler sandy-yellow concrete micrograin, a little more mineral speckle, no symbols",
    ]},
    Family { id: "limestone_path", roles: &["walk"], roughness: 0.48, spread: 0.04, gain: 1.15, period_m: 1.60, variations: [
        "pale cream honed limestone, tight grain and faint warm shell flecks, a continuous path surface without slab joints",
        "warmer honey honed limestone with soft oatmeal grain and tiny fossil specks, still flat",
        "cool gray-cream honed limestone with a faint blush mineral and very low relief",
    ]},
    Family { id: "interior_porcelain", roles: &["interior"], roughness: 0.22, spread: 0.03, gain: 0.35, period_m: 1.20, variations: [
        "warm greige matte porcelain with clearly visible scattered fine charcoal and oatmeal mineral speckles, irregular cream clay pigment and fine fired-ceramic pores, a continuous floor surface without grout; small natural tonal variation must remain visible under flat diffuse lighting",
        "soft greige matte porcelain, a slightly warmer speckle, still even and dielectric",
        "cool light-gray matte porcelain, tighter speckle and a faint blue-gray cast, no tile grid",
    ]},
    Family { id: "interior_terrazzo", roles: &["interior"], roughness: 0.28, spread: 0.04, gain: 1.05, period_m: 1.40, variations: [
        "warm ivory honed terrazzo with small cream, blush and pale stone chips, no large slabs",
        "sand-coloured honed terrazzo with sage, honey and shell chips in a denser mix",
        "cooler gray-ivory honed terrazzo with charcoal and cream chips, fine and flat",
    ]},
];

const OUT_REL: &str = "output/street-social-city-production/ground-pbr-v1";
const N: usize = 1024;
const SETS: usize = 48;

fn sha_bytes(b: &[u8]) -> String {
    format!("{:x}", Sha256::digest(b))
}
fn sha_file(p: &Path) -> R<String> {
    Ok(sha_bytes(&fs::read(p)?))
}
fn save_json(p: &Path, v: &Value) -> R<()> {
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(p, serde_json::to_vec_pretty(v)?)?;
    Ok(())
}
fn smooth(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}
fn set_id(f: &Family, v: usize) -> String {
    format!("{}_v{}", f.id, v + 1)
}
fn is_grass(id: &str) -> bool {
    matches!(id, "lawn_turf" | "meadow_grass")
}
fn extra_clause(f: &Family) -> &'static str {
    match f.id {
        "lawn_turf" | "meadow_grass" => "Fill the frame with dense small realistic overlapping blades a few millimetres wide. Do not draw flowers, trees, bare soil shapes, or one repeated hero plant.",
        "planting_soil" => "Show real dark brown loam crumbs with tiny organic matter, not painted flat brown.",
        "pedestrian_pavers" => "Warm stone rectangular pavers, narrow subtle joints. The joint module must divide the 2.40 m tile exactly so opposite edges meet. No broken unique stones and no manhole.",
        "asphalt" => "Fine aggregate asphalt across 1.50 m. No painted lines, no manholes, no large cracks.",
        "acrylic_court" => "Uniform acrylic sports surface. No painted lines, keys, logos or court markings.",
        "tactile_paving" => "Surface micrograin only. Do not draw truncated domes, bars, cones or arrows; the physical tactile geometry already exists.",
        "timber_deck" => "Fine outdoor teak grain only, no objects. No planks, nails, furniture or gaps.",
        _ => "Keep the feature scale small and evenly distributed. No obvious large unique repeating objects.",
    }
}
fn prompt_for(f: &Family, v: usize) -> String {
    let scale = format!("{:.2}", f.period_m);
    let grass_range = if is_grass(f.id) {
        " This grass tile represents 0.7 to 1.2 metres of real ground."
    } else {
        ""
    };
    let bans = if is_grass(f.id) {
        "No cast shadows, no baked lighting, no vignette, no highlights, no glare, no perspective, no border, no text, no numbers, no logo, no watermark, no objects, no furniture, no trees, no flowers, no windows, no room, no people, no obvious large unique repeating objects, no normal-map coloring, no roughness chart, no multi-map sheet.\n\
Dense small realistic overlapping blades are the whole subject."
    } else {
        "No cast shadows, no baked lighting, no vignette, no highlights, no glare, no perspective, no border, no text, no numbers, no logo, no watermark, no objects, no furniture, no plants, no windows, no room, no people, no obvious large unique repeating objects, no normal-map coloring, no roughness chart, no multi-map sheet."
    };
    format!(
        "Use image_gen exactly once. No shell, no subagents, no other tools. Return only the absolute generated image path.\n\
Create ONE original seamless square photoreal ground albedo texture. Request native 1024 by 1024 pixels.\n\
The subject is only the material surface, scanned flat and filling the frame edge to edge: {desc}. {extra}\n\
One square tile represents {scale} metres by {scale} metres of the real surface.{grass_range}\n\
Orthographic, perfectly planar, full bleed, even diffuse illumination, seamless on both axes, photoreal material surface and fine tactile grain. No baked light and no perspective.\n\
{bans}\n",
        desc = f.variations[v],
        extra = extra_clause(f),
        scale = scale,
        grass_range = grass_range,
        bans = bans,
    )
}
fn out_dir(root: &Path) -> PathBuf {
    root.join(OUT_REL)
}
fn set_dir(root: &Path, id: &str) -> PathBuf {
    out_dir(root).join("sets").join(id)
}

fn catalog_value() -> Value {
    let mut sets = Vec::new();
    for f in FAMILIES {
        for v in 0..3 {
            let id = set_id(f, v);
            let prompt = prompt_for(f, v);
            sets.push(json!({
                "id": id,
                "family": f.id,
                "variation": v + 1,
                "roles": f.roles,
                "roughness": f.roughness,
                "spread": f.spread,
                "normal_gain": f.gain,
                "period_m": f.period_m,
                "metallic": 0.0,
                "description": f.variations[v],
                "prompt_sha256": sha_bytes(prompt.as_bytes()),
                "basecolor": format!("sets/{id}/basecolor.png"),
                "normal": format!("sets/{id}/normal.png"),
                "orm": format!("sets/{id}/orm.png"),
                "albedo": "native Grok image_gen",
                "normal_orm": "derived estimates",
            }));
        }
    }
    json!({
        "status": "catalogued",
        "version": "ground-pbr-v1",
        "date": "2026-10-23",
        "set_count": sets.len(),
        "families": FAMILIES.len(),
        "output_resolution": N,
        "metallic": "ground dielectrics, ORM blue channel is 0",
        "albedo_provenance": "native Grok image_gen only",
        "normal_orm_provenance": "derived estimates, not measured scans and not a second generated image",
        "normal_convention": "DirectX tangent space. nx = -dH/dx, ny = +dH/dy (green encodes +Y down), nz reconstructed. Wrapped central differences of a periodic high-pass of albedo luminance. Derived estimate, not a measured scan.",
        "orm_convention": "R = cavity AO estimate kept near 1, G = family-calibrated roughness, B = metallic 0. Derived estimate, not a measured scan and not baked lighting.",
        "seam": "Narrow periodic half-offset blend, then exact opposite-edge match so column 0 equals column N-1 and row 0 equals row N-1.",
        "scale_m": "lawn_turf and meadow_grass tiles represent 0.7 to 1.2 m. planting_soil represents 0.6 m. asphalt represents 1.5 m. pedestrian_pavers represents 2.4 m with real-size narrow joints. Other families use their period_m.",
        "assignment": "Street social city ground catalogue. Each set is one independent image_gen albedo plus derived normal and ORM. Instances may reuse a set; they do not bake a second generated map.",
        "sets": sets,
    })
}

fn encode_path(s: &str) -> String {
    s.bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect()
}

fn event_text(v: &Value) -> String {
    if let Some(s) = v.as_str() {
        return s.to_owned();
    }
    if let Some(arr) = v.as_array() {
        return arr.iter().filter_map(|x| x["text"].as_str()).collect::<Vec<_>>().join("\n");
    }
    String::new()
}

fn receipt(folder: &Path, sid: &str) -> R<Option<(PathBuf, PathBuf, String)>> {
    let log = PathBuf::from(env::var("USERPROFILE")?)
        .join(".grok/sessions")
        .join(encode_path(&folder.to_string_lossy().replace('/', "\\")))
        .join(sid)
        .join("chat_history.jsonl");
    if !log.exists() {
        return Ok(None);
    }
    let events: Vec<Value> = fs::read_to_string(&log)?.lines().filter_map(|s| serde_json::from_str(s).ok()).collect();
    let expected = fs::read_to_string(folder.join("grok-prompt.txt"))?;
    let matched = events.iter().filter(|e| e["type"] == "user").any(|e| {
        let c = event_text(&e["content"]);
        let c = c.split("<user_query>\n").nth(1).map(|s| s.rsplit("\n</user_query>").last().unwrap_or(s)).unwrap_or(&c);
        c.replace("\r\n", "\n").trim() == expected.replace("\r\n", "\n").trim()
    });
    if !matched {
        return Ok(None);
    }
    let calls: Vec<String> = events
        .iter()
        .flat_map(|e| e["tool_calls"].as_array().into_iter().flatten())
        .filter(|c| c["name"] == "image_gen")
        .filter_map(|c| c["id"].as_str().map(str::to_owned))
        .collect();
    let session = log.parent().unwrap();
    for e in events.iter().rev() {
        if e["type"] != "tool_result" {
            continue;
        }
        if let Some(id) = e["tool_call_id"].as_str() {
            if !calls.iter().any(|c| c == id) {
                continue;
            }
            let blob = event_text(&e["content"]);
            let candidates = if let Ok(v) = serde_json::from_str::<Value>(&blob) {
                v["path"].as_str().map(|p| vec![p.to_owned()]).unwrap_or_default()
            } else {
                Vec::new()
            };
            for p in candidates {
                let p = PathBuf::from(&p);
                if p.is_file() && p.starts_with(session) {
                    return Ok(Some((p, log.clone(), id.to_owned())));
                }
            }
        }
    }
    Ok(None)
}

fn grok_exe() -> R<PathBuf> {
    if let Ok(p) = env::var("GROK_EXE") {
        let p = PathBuf::from(p);
        if p.is_file() {
            return Ok(p);
        }
    }
    for name in ["grok.exe", "grok"] {
        if let Ok(out) = Command::new("where.exe").arg(name).output() {
            if out.status.success() {
                if let Some(line) = String::from_utf8_lossy(&out.stdout).lines().next() {
                    let p = PathBuf::from(line.trim());
                    if p.is_file() {
                        return Ok(p);
                    }
                }
            }
        }
    }
    Err("grok.exe is not on PATH and GROK_EXE is unset".into())
}

fn new_sid(index: usize, attempt: u32) -> R<String> {
    let tick = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    Ok(format!(
        "{:08x}-{:04x}-4{:03x}-8{:03x}-{:012x}",
        (index as u32).wrapping_add(attempt.wrapping_mul(64)),
        ((tick >> 48) & 65535) as u16,
        ((tick >> 36) & 4095) as u16,
        ((tick >> 24) & 4095) as u16,
        (tick & 0xffffffffffff) as u64
    ))
}

fn luma_at(img: &RgbImage, x: u32, y: u32) -> f32 {
    let p = img.get_pixel(x, y);
    (p[0] as f32 * 0.2126 + p[1] as f32 * 0.7152 + p[2] as f32 * 0.0722) / 255.0
}

fn quality(img: &RgbImage) -> R<()> {
    let (w, h) = img.dimensions();
    if w < 256 || h < 256 {
        return Err(format!("source {w}x{h} is below 256").into());
    }
    let mut sum = 0.0f64;
    let mut sum2 = 0.0f64;
    let mut n = 0.0f64;
    let step = ((w.min(h) / 64).max(1)) as u32;
    for y in (0..h).step_by(step as usize) {
        for x in (0..w).step_by(step as usize) {
            let l = luma_at(img, x, y) as f64;
            sum += l;
            sum2 += l * l;
            n += 1.0;
        }
    }
    let mean = sum / n;
    let var = (sum2 / n - mean * mean).max(0.0);
    if var.sqrt() < 0.012 {
        return Err("source albedo is nearly flat".into());
    }
    let mut border = 0.0f64;
    let mut center = 0.0f64;
    let mut nb = 0.0f64;
    let mut nc = 0.0f64;
    for y in (0..h).step_by(step as usize) {
        for x in (0..w).step_by(step as usize) {
            let l = luma_at(img, x, y) as f64;
            let edge = x * 8 < w || (w - x) * 8 < w || y * 8 < h || (h - y) * 8 < h;
            let mid = x > w / 4 && x < w * 3 / 4 && y > h / 4 && y < h * 3 / 4;
            if edge {
                border += l;
                nb += 1.0;
            }
            if mid {
                center += l;
                nc += 1.0;
            }
        }
    }
    if nc > 0.0 && nb > 0.0 && border / nb < (center / nc) * 0.55 {
        return Err("source looks like a baked vignette or corner shadow".into());
    }
    Ok(())
}

fn to_square(img: &RgbImage) -> (RgbImage, bool) {
    let (w, h) = img.dimensions();
    if w == h {
        return (img.clone(), false);
    }
    let s = w.min(h);
    let x = (w - s) / 2;
    let y = (h - s) / 2;
    (image::imageops::crop_imm(img, x, y, s, s).to_image(), true)
}

fn seam_rgb(src: &RgbImage) -> RgbImage {
    let n = src.width() as usize;
    let band = (n / 16).clamp(8, n / 4);
    let mut a = vec![[0f32; 3]; n * n];
    for y in 0..n {
        for x in 0..n {
            let p = src.get_pixel(x as u32, y as u32);
            a[y * n + x] = [p[0] as f32, p[1] as f32, p[2] as f32];
        }
    }
    let mut b = a.clone();
    for y in 0..n {
        for x in 0..n {
            let dx = (x.min(n - 1 - x) as f32) / band as f32;
            let dy = (y.min(n - 1 - y) as f32) / band as f32;
            let w = smooth(dx).min(1.0) * smooth(dy).min(1.0);
            let sx = (x + n / 2) % n;
            let sy = (y + n / 2) % n;
            let p = a[y * n + x];
            let q = a[sy * n + sx];
            b[y * n + x] = [
                p[0] * w + q[0] * (1.0 - w),
                p[1] * w + q[1] * (1.0 - w),
                p[2] * w + q[2] * (1.0 - w),
            ];
        }
    }
    for i in 0..band {
        let t = 1.0 - smooth(i as f32 / band as f32);
        let end = n - 1 - i;
        if i >= end {
            break;
        }
        for k in 0..n {
            for (horizontal, ia, ib) in [
                (true, k * n + i, k * n + end),
                (false, i * n + k, end * n + k),
            ] {
                let _ = horizontal;
                let pa = b[ia];
                let pb = b[ib];
                let avg = [(pa[0] + pb[0]) * 0.5, (pa[1] + pb[1]) * 0.5, (pa[2] + pb[2]) * 0.5];
                b[ia] = [
                    pa[0] * (1.0 - t) + avg[0] * t,
                    pa[1] * (1.0 - t) + avg[1] * t,
                    pa[2] * (1.0 - t) + avg[2] * t,
                ];
                b[ib] = [
                    pb[0] * (1.0 - t) + avg[0] * t,
                    pb[1] * (1.0 - t) + avg[1] * t,
                    pb[2] * (1.0 - t) + avg[2] * t,
                ];
            }
        }
    }
    for y in 0..n {
        b[y * n + (n - 1)] = b[y * n];
    }
    for x in 0..n {
        b[(n - 1) * n + x] = b[x];
    }
    let mut out = RgbImage::new(n as u32, n as u32);
    for y in 0..n {
        for x in 0..n {
            let p = b[y * n + x];
            out.put_pixel(
                x as u32,
                y as u32,
                Rgb([
                    p[0].round().clamp(0.0, 255.0) as u8,
                    p[1].round().clamp(0.0, 255.0) as u8,
                    p[2].round().clamp(0.0, 255.0) as u8,
                ]),
            );
        }
    }
    out
}

fn height_from(rgb: &RgbImage) -> Vec<f32> {
    let n = rgb.width() as usize;
    let mut l = vec![0f32; n * n];
    for y in 0..n {
        for x in 0..n {
            l[y * n + x] = luma_at(rgb, x as u32, y as u32);
        }
    }
    let r = (n / 64).clamp(2, 48);
    let win = (r * 2 + 1) as f32;
    let mut tmp = vec![0f32; n * n];
    for y in 0..n {
        for x in 0..n {
            let mut s = 0f32;
            for k in 0..=r * 2 {
                let xx = (x + k + n - r) % n;
                s += l[y * n + xx];
            }
            tmp[y * n + x] = s / win;
        }
    }
    let mut blur = vec![0f32; n * n];
    for x in 0..n {
        for y in 0..n {
            let mut s = 0f32;
            for k in 0..=r * 2 {
                let yy = (y + k + n - r) % n;
                s += tmp[yy * n + x];
            }
            blur[y * n + x] = s / win;
        }
    }
    l.iter().zip(blur.iter()).map(|(a, b)| (0.5 + (a - b) * 2.2).clamp(0.0, 1.0)).collect()
}

fn derive_maps(albedo: &RgbImage, f: &Family) -> R<(RgbImage, RgbImage, RgbImage)> {
    let albedo = seam_rgb(albedo);
    let n = albedo.width() as usize;
    let h = height_from(&albedo);
    let mut normal = RgbImage::new(n as u32, n as u32);
    let mut orm = RgbImage::new(n as u32, n as u32);
    let lo = (f.roughness - f.spread).clamp(0.04, 0.98);
    let hi = (f.roughness + f.spread).clamp(0.04, 0.98);
    for y in 0..n {
        for x in 0..n {
            let at = |xx: usize, yy: usize| h[(yy % n) * n + (xx % n)];
            let dx = (at(x + 1, y) - at(x + n - 1, y)) * f.gain;
            let dy = (at(x, y + 1) - at(x, y + n - 1)) * f.gain;
            let nx = -dx;
            let ny = dy;
            let nz = 1.0;
            let len = (nx * nx + ny * ny + nz * nz).sqrt();
            let enc = |a: f32| ((a * 0.5 + 0.5) * 255.0).round().clamp(0.0, 255.0) as u8;
            normal.put_pixel(x as u32, y as u32, Rgb([enc(nx / len), enc(ny / len), enc(nz / len)]));
            let hv = at(x, y);
            let rough = (f.roughness + (hv - 0.5) * f.spread).clamp(lo, hi);
            let avg = (at(x + 1, y) + at(x + n - 1, y) + at(x, y + 1) + at(x, y + n - 1)) * 0.25;
            let cavity = (avg - hv).max(0.0);
            let ao = (1.0 - cavity * 0.35).clamp(0.86, 1.0);
            orm.put_pixel(
                x as u32,
                y as u32,
                Rgb([(ao * 255.0).round() as u8, (rough * 255.0).round() as u8, 0]),
            );
        }
    }
    // Exact bitmap seam after quantization. One-pixel edge copy; derivatives above already wrap.
    for y in 0..n as u32 {
        normal.put_pixel(n as u32 - 1, y, *normal.get_pixel(0, y));
        orm.put_pixel(n as u32 - 1, y, *orm.get_pixel(0, y));
    }
    for x in 0..n as u32 {
        normal.put_pixel(x, n as u32 - 1, *normal.get_pixel(x, 0));
        orm.put_pixel(x, n as u32 - 1, *orm.get_pixel(x, 0));
    }
    Ok((albedo, normal, orm))
}

fn derive_from_source(folder: &Path, source: &Path, f: &Family, cropped: bool) -> R<(u32, u32, bool)> {
    let opened = image::open(source)?.to_rgb8();
    let (sw, sh) = opened.dimensions();
    quality(&opened)?;
    let (square, did_crop) = to_square(&opened);
    let resampled = square.width() != N as u32 || square.height() != N as u32;
    let sized = if resampled {
        image::imageops::resize(&square, N as u32, N as u32, FilterType::Lanczos3)
    } else {
        square
    };
    if sized.dimensions() != (N as u32, N as u32) {
        return Err("sized albedo is not 1024".into());
    }
    let (albedo, normal, orm) = derive_maps(&sized, f)?;
    if albedo.dimensions() != (N as u32, N as u32) || normal.dimensions() != (N as u32, N as u32) || orm.dimensions() != (N as u32, N as u32) {
        return Err("derived maps are not 1024".into());
    }
    quality(&albedo)?;
    albedo.save(folder.join("basecolor.png"))?;
    normal.save(folder.join("normal.png"))?;
    orm.save(folder.join("orm.png"))?;
    let _ = (cropped, did_crop);
    Ok((sw, sh, resampled))
}

fn write_meta(folder: &Path, f: &Family, v: usize, extra: Value) -> R<()> {
    let mut base = json!({
        "id": set_id(f, v),
        "family": f.id,
        "variation": v + 1,
        "roughness": f.roughness,
        "spread": f.spread,
        "normal_gain": f.gain,
        "period_m": f.period_m,
        "metallic": 0.0,
        "output_width": N,
        "output_height": N,
        "albedo_provenance": "native Grok image_gen",
        "normal_orm_provenance": "derived estimates",
        "normal_convention": "DirectX tangent space, wrapped central differences of a high-pass of albedo luminance. Derived estimate, not a measured scan.",
        "orm_convention": "R cavity AO near 1, G calibrated roughness, B metallic 0. Derived estimate, not baked light and not a measured scan.",
        "seam": "narrow periodic blend plus exact opposite-edge match",
    });
    if let (Some(obj), Some(add)) = (base.as_object_mut(), extra.as_object()) {
        for (k, v) in add {
            obj.insert(k.clone(), v.clone());
        }
    }
    save_json(&folder.join("generation.json"), &base)
}

fn finish_from_proof(root: &Path, index: usize, proof: (PathBuf, PathBuf, String), sid: &str, attempts: u32) -> R<()> {
    let (f, v) = (&FAMILIES[index / 3], index % 3);
    let folder = set_dir(root, &set_id(f, v));
    fs::create_dir_all(&folder)?;
    let ext = proof.0.extension().and_then(|e| e.to_str()).unwrap_or("img");
    let copied = folder.join(format!("grok-source.{ext}"));
    fs::copy(&proof.0, &copied)?;
    let (sw, sh, resampled) = derive_from_source(&folder, &copied, f, false)?;
    write_meta(
        &folder,
        f,
        v,
        json!({
            "status": "generated",
            "prompt_sha256": sha_file(&folder.join("grok-prompt.txt"))?,
            "session_id": sid,
            "tool_call_id": proof.2,
            "event_log": proof.1,
            "event_sha256": sha_file(&proof.1)?,
            "grok_original": proof.0,
            "grok_original_sha256": sha_file(&proof.0)?,
            "grok_source_copy": copied,
            "grok_source_copy_sha256": sha_file(&copied)?,
            "source_width": sw,
            "source_height": sh,
            "source_native_1024": sw == 1024 && sh == 1024,
            "resampled_to_1024": resampled,
            "resample_filter": if resampled { "Lanczos3" } else { "none" },
            "output_width": N,
            "output_height": N,
            "basecolor_sha256": sha_file(&folder.join("basecolor.png"))?,
            "normal_sha256": sha_file(&folder.join("normal.png"))?,
            "orm_sha256": sha_file(&folder.join("orm.png"))?,
            "attempts": attempts,
            "provenance": "native Grok image_gen albedo; normal and ORM are derived estimates, not measured scans",
        }),
    )?;
    println!("{}: generated {sw}x{sh} -> {N}x{N}", set_id(f, v));
    Ok(())
}

fn generate_one(root: &Path, index: usize, exe: &Path) -> R<()> {
    let (f, v) = (&FAMILIES[index / 3], index % 3);
    let id = set_id(f, v);
    let folder = set_dir(root, &id);
    fs::create_dir_all(&folder)?;
    let prompt = prompt_for(f, v);
    fs::write(folder.join("grok-prompt.txt"), &prompt)?;
    let prompt_sha = sha_bytes(prompt.as_bytes());
    let meta_path = folder.join("generation.json");
    if meta_path.exists() {
        let old: Value = serde_json::from_slice(&fs::read(&meta_path)?)?;
        if old["status"] == "generated" && old["prompt_sha256"] == prompt_sha && old["normal_gain"].as_f64().map(|g|(g-f.gain as f64).abs()<0.0001).unwrap_or(false) && folder.join("basecolor.png").is_file() && folder.join("normal.png").is_file() && folder.join("orm.png").is_file() {
            println!("{id}: cached");
            return Ok(());
        }
        if let Some(sid) = old["session_id"].as_str() {
            if let Some(proof) = receipt(&folder, sid)? {
                if finish_from_proof(root, index, proof, sid, old["attempts"].as_u64().unwrap_or(1) as u32).is_ok() {
                    return Ok(());
                }
            }
        }
    }
    let mut last = String::from("not started");
    for attempt in 1..=3 {
        let sid = new_sid(index, attempt)?;
        write_meta(&folder, f, v, json!({"status":"running","prompt_sha256":prompt_sha,"session_id":sid,"attempts":attempt}))?;
        let mut cmd = Command::new(exe);
        cmd.args(["--session-id", &sid, "--prompt-file"])
            .arg(folder.join("grok-prompt.txt"))
            .arg("--cwd")
            .arg(&folder)
            .args(["--model", "grok-4.7", "--effort", "medium", "--tools", "image_gen", "--no-subagents", "--disable-web-search", "--always-approve", "--max-turns", "4", "--output-format", "json"])
            .env("GROK_MEMORY", "0")
            .env("GROK_DISABLE_AUTOUPDATER", "1")
            .stdout(Stdio::from(fs::File::create(folder.join(format!("grok-run-{attempt}.json")))?))
            .stderr(Stdio::from(fs::File::create(folder.join(format!("grok-stderr-{attempt}.log")))?));
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x08000000);
        }
        let mut child = cmd.spawn()?;
        let start = Instant::now();
        let proof = loop {
            if let Some(p) = receipt(&folder, &sid)? {
                break Some(p);
            }
            if let Some(status) = child.try_wait()? {
                last = format!("attempt {attempt} exit {status} without an image_gen receipt");
                break None;
            }
            if start.elapsed() > Duration::from_secs(420) {
                let _ = child.kill();
                let _ = child.wait();
                last = format!("attempt {attempt} timed out after 420s");
                break None;
            }
            thread::sleep(Duration::from_secs(2));
        };
        if child.try_wait()?.is_none() {
            thread::sleep(Duration::from_secs(2));
            if child.try_wait()?.is_none() {
                let _ = child.kill();
            }
            let _ = child.wait();
        }
        if let Some(p) = proof {
            match finish_from_proof(root, index, p, &sid, attempt) {
                Ok(()) => return Ok(()),
                Err(e) => last = e.to_string(),
            }
            if attempt < 3 {
                thread::sleep(Duration::from_secs(8));
            }
            continue;
        }
        if attempt < 3 {
            thread::sleep(Duration::from_secs(8));
        }
    }
    write_meta(&folder, f, v, json!({"status":"failed","prompt_sha256":prompt_sha,"error":last}))?;
    Err(format!("{id}: {last}").into())
}

fn edge_diff(img: &RgbImage) -> u8 {
    let n = img.width();
    let mut max = 0u8;
    for i in 0..n {
        let a = img.get_pixel(0, i);
        let b = img.get_pixel(n - 1, i);
        let c = img.get_pixel(i, 0);
        let d = img.get_pixel(i, n - 1);
        for k in 0..3 {
            max = max.max(a[k].abs_diff(b[k])).max(c[k].abs_diff(d[k]));
        }
    }
    max
}

fn near(a: f32, b: f32) -> bool {
    (a - b).abs() < 0.001
}

fn selftest() -> R<()> {
    if N != 1024 || SETS != 48 {
        return Err("output contract is not 1024 and 48 sets".into());
    }
    let n = 64u32;
    let mut img = RgbImage::new(n, n);
    for y in 0..n {
        for x in 0..n {
            let g = if x == 32 && y == 32 { 200 } else { 20 + ((x * 3 + y) % 50) as u8 };
            img.put_pixel(x, y, Rgb([g, g.wrapping_add(10), g.wrapping_add(20)]));
        }
    }
    let seamed = seam_rgb(&img);
    if edge_diff(&seamed) != 0 {
        return Err("selftest seam is not exact".into());
    }
    let center = seamed.get_pixel(32, 32)[0];
    if center < 150 {
        return Err(format!("selftest center was destroyed: {center}").into());
    }
    let fake = Family { id: "self", roles: &["walk"], roughness: 0.5, spread: 0.05, gain: 1.5, period_m: 1.0, variations: ["", "", ""] };
    let (_a, normal, orm) = derive_maps(&image::imageops::resize(&img, 64, 64, FilterType::Triangle), &fake)?;
    if edge_diff(&normal) != 0 || edge_diff(&orm) != 0 {
        return Err("selftest derived maps are not seamed".into());
    }
    let p = normal.get_pixel(8, 8);
    let nx = p[0] as f32 / 255.0 * 2.0 - 1.0;
    let ny = p[1] as f32 / 255.0 * 2.0 - 1.0;
    let nz = p[2] as f32 / 255.0 * 2.0 - 1.0;
    let len = (nx * nx + ny * ny + nz * nz).sqrt();
    if !(0.97..=1.03).contains(&len) || nz < 0.5 || orm.get_pixel(8, 8)[2] != 0 {
        return Err(format!("selftest normal/orm failed len={len}").into());
    }
    if FAMILIES.len() != 16 || FAMILIES.iter().map(|_| 3).sum::<usize>() != SETS {
        return Err("catalogue is not 16x3".into());
    }
    let cat = catalog_value();
    if cat["version"] != "ground-pbr-v1" || cat["set_count"] != SETS || cat["families"] != 16 || cat["output_resolution"] != N {
        return Err("catalog header mismatch".into());
    }
    let mut ids = std::collections::BTreeSet::new();
    let mut prompts = std::collections::BTreeSet::new();
    for f in FAMILIES {
        if f.variations.iter().collect::<std::collections::BTreeSet<_>>().len() != 3 {
            return Err(format!("{} variations are not distinct", f.id).into());
        }
        if f.roles.is_empty() {
            return Err(format!("{} has no role", f.id).into());
        }
        match f.id {
            "lawn_turf" | "meadow_grass" => {
                if !(0.7..=1.2).contains(&f.period_m) {
                    return Err(format!("{} period is outside 0.7 to 1.2 m", f.id).into());
                }
            }
            "planting_soil" if !near(f.period_m, 0.6) => return Err("planting_soil is not 0.6 m".into()),
            "asphalt" if !near(f.period_m, 1.5) => return Err("asphalt is not 1.5 m".into()),
            "pedestrian_pavers" if !near(f.period_m, 2.4) => return Err("pedestrian_pavers is not 2.4 m".into()),
            _ => {}
        }
        for v in 0..3 {
            let id = set_id(f, v);
            if !ids.insert(id) {
                return Err("duplicate set id".into());
            }
            let prompt = prompt_for(f, v);
            if !prompts.insert(sha_bytes(prompt.as_bytes())) {
                return Err(format!("{} prompt is not unique", f.id).into());
            }
            for needle in ["Use image_gen exactly once", "1024 by 1024", "photoreal", "no perspective", "baked light", "seamless"] {
                if !prompt.contains(needle) {
                    return Err(format!("{} prompt missing {needle}", f.id).into());
                }
            }
            if prompt.contains("2048") {
                return Err(format!("{} prompt still says 2048", f.id).into());
            }
            if is_grass(f.id) {
                if prompt.contains("no plants") || !prompt.contains("dense small realistic overlapping blades") || !prompt.contains("0.7 to 1.2") {
                    return Err(format!("{} grass prompt is wrong", f.id).into());
                }
            } else if !prompt.contains("no plants") {
                return Err(format!("{} prompt does not ban plants", f.id).into());
            }
            match f.id {
                "planting_soil" if !prompt.contains("real dark brown loam crumbs with tiny organic matter, not painted flat brown") => {
                    return Err("soil prompt dropped the loam clause".into());
                }
                "pedestrian_pavers" if !prompt.contains("narrow subtle joints") || !prompt.contains("2.40") => {
                    return Err("paver prompt dropped joint scale".into());
                }
                "asphalt" if !prompt.contains("1.50") => return Err("asphalt prompt dropped 1.50 m".into()),
                "acrylic_court" if !prompt.contains("No painted lines") => return Err("court prompt allows lines".into()),
                "tactile_paving" if !prompt.contains("Surface micrograin only") => return Err("tactile prompt draws geometry".into()),
                "timber_deck" if !prompt.contains("Fine outdoor teak grain only, no objects") => return Err("deck prompt allows objects".into()),
                _ => {}
            }
        }
    }
    for role in ["turf", "soil", "road", "walk", "court", "sand", "deck", "interior"] {
        if !FAMILIES.iter().any(|f| f.roles.contains(&role)) {
            return Err(format!("no family covers {role}").into());
        }
    }
    println!("selftest: passed");
    Ok(())
}

fn file_ok(path: &Path) -> R<()> {
    let len = fs::metadata(path)?.len();
    if len < 64 {
        return Err(format!("{} is too small", path.display()).into());
    }
    Ok(())
}

fn verify(root: &Path) -> R<()> {
    selftest()?;
    let dir = out_dir(root);
    let mut rows = Vec::new();
    let mut failures = Vec::new();
    let mut means: Vec<(String, String, [f64; 3])> = Vec::new();
    for f in FAMILIES {
        for v in 0..3 {
            let id = set_id(f, v);
            let folder = set_dir(root, &id);
            let check = (|| -> R<Value> {
                let meta_path = folder.join("generation.json");
                let prompt_path = folder.join("grok-prompt.txt");
                let bc_path = folder.join("basecolor.png");
                let nm_path = folder.join("normal.png");
                let orm_path = folder.join("orm.png");
                for path in [&meta_path, &prompt_path, &bc_path, &nm_path, &orm_path] {
                    if !path.is_file() {
                        return Err(format!("missing {}", path.display()).into());
                    }
                    file_ok(path)?;
                }
                let meta: Value = serde_json::from_slice(&fs::read(&meta_path)?)?;
                if meta["status"] != "generated" {
                    return Err(format!("status {}", meta["status"]).into());
                }
                if meta.get("source_native_2048").is_some() || meta.get("resampled_to_2048").is_some() {
                    return Err("stale 2048 provenance field".into());
                }
                if meta["prompt_sha256"] != sha_file(&prompt_path)? {
                    return Err("prompt hash mismatch".into());
                }
                if meta["output_width"].as_u64() != Some(N as u64) || meta["output_height"].as_u64() != Some(N as u64) {
                    return Err("recorded output size is not 1024".into());
                }
                for path in [&bc_path, &nm_path, &orm_path] {
                    let (w, h) = image::image_dimensions(path)?;
                    if (w, h) != (N as u32, N as u32) {
                        return Err("output header is not 1024".into());
                    }
                }
                if sha_file(&bc_path)? != meta["basecolor_sha256"] || sha_file(&nm_path)? != meta["normal_sha256"] || sha_file(&orm_path)? != meta["orm_sha256"] {
                    return Err("map hash mismatch".into());
                }
                let sw = meta["source_width"].as_u64().unwrap_or(0);
                let sh = meta["source_height"].as_u64().unwrap_or(0);
                let native = sw == 1024 && sh == 1024;
                if meta["source_native_1024"].as_bool() != Some(native) {
                    return Err("native 1024 flag does not match the source file".into());
                }
                let square_side = (sw as u32).min(sh as u32);
                let expect_resample = square_side != N as u32;
                if meta["resampled_to_1024"].as_bool() != Some(expect_resample) {
                    return Err("resample flag does not match the source dimensions".into());
                }
                let copy = PathBuf::from(meta["grok_source_copy"].as_str().unwrap_or(""));
                if !copy.is_file() || sha_file(&copy)? != meta["grok_source_copy_sha256"] {
                    return Err("missing grok source copy".into());
                }
                let (dw, dh) = image::image_dimensions(&copy)?;
                if (dw, dh) != (sw as u32, sh as u32) {
                    return Err("recorded source dimensions differ from the copied image header".into());
                }
                let log = PathBuf::from(meta["event_log"].as_str().unwrap_or(""));
                if !log.is_file() || sha_file(&log)? != meta["event_sha256"] || meta["tool_call_id"].as_str().unwrap_or("").is_empty() {
                    return Err("missing tool receipt".into());
                }
                let bc = image::open(&bc_path)?.to_rgb8();
                let nm = image::open(&nm_path)?.to_rgb8();
                let orm = image::open(&orm_path)?.to_rgb8();
                if edge_diff(&bc) != 0 || edge_diff(&nm) != 0 || edge_diff(&orm) != 0 {
                    return Err("seam diff is not 0".into());
                }
                let mut len_bad = 0u32;
                let mut z_sum = 0.0f64;
                let mut samples = 0.0f64;
                let mut metal = 0u32;
                let mut rough_bad = 0u32;
                let mut ao_min = 255u8;
                let mut luma_sum = 0.0f64;
                let mut luma_sq = 0.0f64;
                let mut rgb = [0.0f64; 3];
                let lo = (f.roughness - f.spread).clamp(0.04, 0.98);
                let hi = (f.roughness + f.spread).clamp(0.04, 0.98);
                for y in (0..N as u32).step_by(16) {
                    for x in (0..N as u32).step_by(16) {
                        let p = nm.get_pixel(x, y);
                        let nx = p[0] as f32 / 255.0 * 2.0 - 1.0;
                        let ny = p[1] as f32 / 255.0 * 2.0 - 1.0;
                        let nz = p[2] as f32 / 255.0 * 2.0 - 1.0;
                        let len = (nx * nx + ny * ny + nz * nz).sqrt();
                        if !(0.96..=1.04).contains(&len) {
                            len_bad += 1;
                        }
                        z_sum += nz as f64;
                        samples += 1.0;
                        let o = orm.get_pixel(x, y);
                        if o[2] != 0 {
                            metal += 1;
                        }
                        let rough = o[1] as f32 / 255.0;
                        if rough < lo - 1.0 / 255.0 || rough > hi + 1.0 / 255.0 {
                            rough_bad += 1;
                        }
                        ao_min = ao_min.min(o[0]);
                        let c = bc.get_pixel(x, y);
                        let l = (c[0] as f64 * 0.2126 + c[1] as f64 * 0.7152 + c[2] as f64 * 0.0722) / 255.0;
                        luma_sum += l;
                        luma_sq += l * l;
                        rgb[0] += c[0] as f64;
                        rgb[1] += c[1] as f64;
                        rgb[2] += c[2] as f64;
                    }
                }
                if len_bad > 0 || metal > 0 || rough_bad > 0 || ao_min < 210 || z_sum / samples < 0.85 {
                    return Err(format!("map stats len_bad={len_bad} metal={metal} rough_bad={rough_bad} ao_min={ao_min} mean_normal_z={}",z_sum/samples).into());
                }
                let mean = luma_sum / samples;
                let sd = (luma_sq / samples - mean * mean).max(0.0).sqrt();
                if sd < 0.012 {
                    return Err("basecolor is flat".into());
                }
                means.push((f.id.to_owned(), id.clone(), [rgb[0] / samples / 255.0, rgb[1] / samples / 255.0, rgb[2] / samples / 255.0]));
                Ok(json!({"id": id, "source": format!("{sw}x{sh}"), "native_1024": native, "resampled": meta["resampled_to_1024"], "seam": 0, "output": "1024x1024"}))
            })();
            match check {
                Ok(row) => rows.push(row),
                Err(e) => failures.push(format!("{id}: {e}")),
            }
        }
    }
    let mut hashes = std::collections::BTreeSet::new();
    for f in FAMILIES {
        for v in 0..3 {
            let p = set_dir(root, &set_id(f, v)).join("basecolor.png");
            if p.is_file() {
                if let Ok(h) = sha_file(&p) {
                    if !hashes.insert(h) {
                        failures.push(format!("{} basecolor hash is not unique", set_id(f, v)));
                    }
                }
            }
        }
    }
    for f in FAMILIES {
        let group: Vec<_> = means.iter().filter(|m| m.0 == f.id).map(|m| m.2).collect();
        if group.len() == 3 {
            let mut min = f64::MAX;
            for a in 0..3 {
                for b in a + 1..3 {
                    let d = (0..3).map(|k| (group[a][k] - group[b][k]).powi(2)).sum::<f64>().sqrt();
                    min = min.min(d);
                }
            }
            if min < 0.02 {
                failures.push(format!("{} variations are too close (mean RGB L2 {min:.4})", f.id));
            }
        }
    }
    let status = if failures.is_empty() && rows.len() == SETS { "passed" } else { "failed" };
    save_json(&dir.join("verification.json"), &json!({"status": status, "passed": rows.len(), "failed": failures.len(), "expected": SETS, "output_resolution": N, "rows": rows, "failures": failures}))?;
    if status != "passed" {
        return Err(format!("verify failed: {} passed, {} failed", rows.len(), failures.len()).into());
    }
    println!("verify: {SETS} passed");
    Ok(())
}

fn sheet(root: &Path) -> R<()> {
    let dir = out_dir(root);
    fs::create_dir_all(&dir)?;
    let thumb = 112u32;
    let mut grid = RgbImage::from_pixel(thumb * 9, thumb * 16, Rgb([16, 16, 16]));
    let mut big = RgbImage::from_pixel(256 * 8, 256 * 6, Rgb([16, 16, 16]));
    let mut cards = String::new();
    for (i, f) in FAMILIES.iter().enumerate() {
        for v in 0..3 {
            let id = set_id(f, v);
            let folder = set_dir(root, &id);
            for (k, kind) in ["basecolor", "normal", "orm"].iter().enumerate() {
                let path = folder.join(format!("{kind}.png"));
                if !path.is_file() {
                    continue;
                }
                let (w, h) = image::image_dimensions(&path).unwrap_or((0, 0));
                if (w, h) != (N as u32, N as u32) {
                    continue;
                }
                let im = image::open(&path)?.resize_exact(thumb, thumb, FilterType::Triangle).to_rgb8();
                image::imageops::replace(&mut grid, &im, ((v * 3 + k) as i64) * thumb as i64, i as i64 * thumb as i64);
            }
            let bc = folder.join("basecolor.png");
            if bc.is_file() {
                let (w, h) = image::image_dimensions(&bc).unwrap_or((0, 0));
                if (w, h) == (N as u32, N as u32) {
                    let im = image::open(&bc)?.resize_exact(256, 256, FilterType::Triangle).to_rgb8();
                    let n = i * 3 + v;
                    image::imageops::replace(&mut big, &im, (n % 8) as i64 * 256, (n / 8) as i64 * 256);
                }
            }
            let meta = fs::read_to_string(folder.join("generation.json")).unwrap_or_else(|_| "{}".into());
            let meta: Value = serde_json::from_str(&meta).unwrap_or(json!({}));
            cards.push_str(&format!(
                "<figure><img src=\"sets/{id}/basecolor.png\" alt=\"{id} basecolor\"><img src=\"sets/{id}/normal.png\" alt=\"{id} normal\"><img src=\"sets/{id}/orm.png\" alt=\"{id} orm\"><figcaption><strong>{id}</strong><br>{desc}<br>tile {period:.2} m<br>source {sw}×{sh}, native 1024: {native}, resampled: {resampled}<br>roughness {rough}, metallic 0<br>albedo image_gen; normal/ORM derived</figcaption></figure>\n",
                id = id,
                desc = f.variations[v],
                period = f.period_m,
                sw = meta["source_width"].as_u64().unwrap_or(0),
                sh = meta["source_height"].as_u64().unwrap_or(0),
                native = meta["source_native_1024"],
                resampled = meta["resampled_to_1024"],
                rough = f.roughness,
            ));
        }
    }
    grid.save(dir.join("contact-maps.png"))?;
    big.save(dir.join("contact-basecolor.png"))?;
    let html = format!(
        "<!doctype html><meta charset=\"utf-8\"><title>Ground PBR v1</title><style>body{{font:16px/1.45 sans-serif;background:#f3f1ec;color:#241f1a;margin:32px}} figure{{display:inline-block;width:340px;margin:8px;background:#fff;padding:8px}} img{{width:100px;height:100px;object-fit:cover}} figcaption{{font-size:13px}}</style><h1>街區地面材質 ground-pbr-v1</h1><p>16 個家族 × 3 個獨立 albedo，共 48 組。每組最終 basecolor、normal、ORM 都是 1024×1024。Albedo 只來自 Grok image_gen；DirectX normal 與 ORM 是派生估計，不是掃描實測。金屬度為 0。</p><p><a href=\"contact-basecolor.png\">albedo 接觸表</a> · <a href=\"contact-maps.png\">三圖接觸表</a> · <a href=\"verification.json\">驗證</a> · <a href=\"report.md\">方法</a></p>{cards}"
    );
    fs::write(dir.join("index.html"), html)?;
    let report = "\
# Ground PBR v1\n\n\
日期：2026-10-23。\n\n\
## 方法\n\n\
- 16 個戶外與室內地面家族 × 3 個獨立提示，共 48 組。每一組只向 Grok `image_gen` 要一張平面 albedo。\n\
- 最終 basecolor、normal、ORM 都是精確 1024×1024（N=1024）。提示要求原生 1024。`generation.json` 的 `source_width` / `source_height` 與 `source_native_1024` 以實際來源檔為準。正方形邊長不是 1024 的圖用 Lanczos3 重採樣，並在 `resampled_to_1024` 標明。\n\
- 接縫：窄帶半週期混合，再讓對邊像素完全相同。法線使用包裹式中心差分，DirectX（nx = -dH/dx，ny = +dH/dy）。高度來自 albedo 亮度的週期高通。這是派生估計，不是另一張生成圖，也不是掃描實測。\n\
- ORM：R 為接近 1 的凹洞 AO 估計，G 為家族校正粗糙度，B 金屬度恆為 0。這些是物理約束下的估計，不是測量掃描，也不含烘焙光影。\n\
- 草皮 `lawn_turf` 與 `meadow_grass` 允許密集、細小、真實、互相重疊的草葉，單磚代表 0.7–1.2 m。其餘家族禁止植物。\n\
- `planting_soil` 代表 0.6 m，要真實深棕壤土碎屑與細小有機質，不是平塗棕色。`asphalt` 代表 1.5 m。`pedestrian_pavers` 代表 2.4 m，暖色石材長方鋪石與窄縫，模數整除 2.4 m。\n\
- `acrylic_court` 不畫球場線。`tactile_paving` 只做表面微粒，觸覺凸點幾何已另有模型。`timber_deck` 只做戶外柚木細紋，不放物件。\n\n\
## 範圍\n\n\
草坪、草甸、植栽土、柏油、人行鋪石、校園混凝土、沙灘、河礫、木甲板、紅陶鋪面、跑道橡膠、壓克力球場、觸覺鋪面微粒、石灰岩小徑、室內瓷、室內水磨石。不產生招牌、玻璃、燈、家具、金屬件或明顯的大型獨特重複物件。\n";
    fs::write(dir.join("report.md"), report)?;
    println!("sheet: index.html");
    Ok(())
}

fn root_from(args: &[String]) -> R<PathBuf> {
    let raw = args.last().filter(|s| !matches!(s.as_str(), "catalog" | "selftest" | "generate" | "verify" | "sheet" | "all")).cloned().unwrap_or_else(|| "C:/portable/OpenKoikatsu".into());
    let root = fs::canonicalize(raw)?;
    Ok(PathBuf::from(root.to_string_lossy().trim_start_matches(r"\\?\")))
}

fn generate(root: &Path) -> R<()> {
    let exe = grok_exe()?;
    let dir = out_dir(root);
    fs::create_dir_all(&dir)?;
    let lock = dir.join("generate.lock");
    if lock.exists() {
        let age = lock.metadata()?.modified()?.elapsed().unwrap_or(Duration::from_secs(0));
        if age < Duration::from_secs(3600) {
            return Err("generate.lock is under an hour old; another generate may be running".into());
        }
    }
    fs::write(&lock, format!("{}", std::process::id()))?;
    let workers = env::var("GROUND_PBR_WORKERS").ok().and_then(|s| s.parse().ok()).unwrap_or(4).clamp(1, 4);
    println!("generate: {} workers, grok {}", workers, exe.display());
    let mut failures = Vec::new();
    let indices: Vec<_> = (0..SETS).collect();
    for chunk in indices.chunks(workers) {
        let mut jobs = Vec::new();
        for &i in chunk {
            let root = root.to_path_buf();
            let exe = exe.clone();
            jobs.push(thread::spawn(move || generate_one(&root, i, &exe)));
        }
        for job in jobs {
            if let Err(e) = job.join().unwrap() {
                eprintln!("{e}");
                failures.push(e.to_string());
            }
        }
    }
    let _ = fs::remove_file(&lock);
    save_json(&dir.join("generate-summary.json"), &json!({"status": if failures.is_empty() {"passed"} else {"failed"}, "expected": SETS, "failures": failures}))?;
    if !failures.is_empty() {
        return Err(format!("{} sets failed", failures.len()).into());
    }
    Ok(())
}

fn main() -> R<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    let cmd = args.first().map(String::as_str).unwrap_or("all");
    let root = root_from(&args)?;
    let dir = out_dir(&root);
    fs::create_dir_all(&dir)?;
    match cmd {
        "catalog" => save_json(&dir.join("catalog.json"), &catalog_value())?,
        "selftest" => selftest()?,
        "generate" => {
            save_json(&dir.join("catalog.json"), &catalog_value())?;
            generate(&root)?;
        }
        "verify" => verify(&root)?,
        "sheet" => sheet(&root)?,
        "all" => {
            save_json(&dir.join("catalog.json"), &catalog_value())?;
            selftest()?;
            generate(&root)?;
            verify(&root)?;
            sheet(&root)?;
        }
        other => return Err(format!("unknown command {other}. Use catalog | selftest | generate | verify | sheet | all").into()),
    }
    Ok(())
}
