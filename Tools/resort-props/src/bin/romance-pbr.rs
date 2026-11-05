// Resort romance architectural PBR. One native Grok albedo per set; normal and ORM are derived.
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
    Family { id: "ivory_lime_plaster", roles: &["wall", "facade"], roughness: 0.84, spread: 0.05, gain: 1.5, period_m: 2.0, variations: [
        "warm ivory lime plaster with clearly visible fine wheat and honey mineral pores, irregular cream-on-oatmeal pigment mottling, varied tactile trowel marks, enough fine tonal variation to show real lime texture under flat lighting",
        "richer honey-ivory lime plaster with faint blush sand grains and broader cloudy trowel passes",
        "cool ivory lime plaster dusted with pale sage mineral flecks and a slightly drier open pore",
    ]},
    Family { id: "blush_lime_plaster", roles: &["wall", "facade"], roughness: 0.80, spread: 0.06, gain: 1.6, period_m: 2.0, variations: [
        "coral-blush lime plaster with clearly visible fine cream mineral grains and irregular peach pigment mottling, varied small tactile pores, flat and softly romantic but distinctly textured",
        "deeper dusty-rose lime plaster with warm apricot mottling and sparse cream lime spots",
        "soft peach-blush plaster with a faint lagoon-gray mineral veil and a tighter burnish",
    ]},
    Family { id: "sage_limewash", roles: &["wall", "trim"], roughness: 0.86, spread: 0.05, gain: 1.3, period_m: 2.2, variations: [
        "pale sage limewash with visibly varied olive and ivory mineral pigment, fine contrasting brush drag and distinct small oatmeal flecks across an evenly lit surface",
        "muted olive-sage limewash with sandy cream breaks and a drier matte tooth",
        "gray-sage limewash with a hint of lagoon blue in the mineral dust, a very thin wash",
    ]},
    Family { id: "lagoon_mineral_plaster", roles: &["wall", "facade", "trim"], roughness: 0.78, spread: 0.06, gain: 1.6, period_m: 2.0, variations: [
        "pale lagoon mineral plaster, aqua-gray over warm sand, fine even pores",
        "deeper lagoon plaster with soft teal mineral clouds and cream lime blooms",
        "misty blue-green plaster with sparse coral mineral specks and a smooth trowel",
    ]},
    Family { id: "honed_limestone", roles: &["facade", "floor", "trim", "stairs"], roughness: 0.40, spread: 0.04, gain: 1.2, period_m: 1.6, variations: [
        "pale cream honed limestone, tight grain, faint warm shell flecks, no large veins and no slab joints",
        "warmer honey honed limestone with soft oatmeal grain and tiny fossil specks, still honed and flat",
        "cool gray-cream honed limestone with a faint blush mineral and very low relief",
    ]},
    Family { id: "honed_travertine", roles: &["facade", "floor", "wall"], roughness: 0.46, spread: 0.05, gain: 1.9, period_m: 1.8, variations: [
        "light ivory travertine with small evenly distributed pores, honed rather than polished, no tile grid",
        "warm wheat travertine with slightly larger soft pores and cream bands, honed and planar",
        "pale blush travertine with fine pores and a faint coral mineral tint, honed",
    ]},
    Family { id: "whitewashed_wood", roles: &["trim", "wall", "facade"], roughness: 0.62, spread: 0.06, gain: 2.3, period_m: 1.15, variations: [
        "whitewashed softwood, a thin lime wash letting pale ash grain show, continuous fine fibres, no plank seams, knots or nails",
        "warmer whitewash over honey wood with more grain contrast, still one continuous fibre field without boards",
        "cooler gray-white wash over driftwood-pale grain, softer fibre, no boards and no hardware",
    ]},
    Family { id: "teak_wood", roles: &["floor", "trim", "stairs", "facade"], roughness: 0.54, spread: 0.05, gain: 2.5, period_m: 1.0, variations: [
        "pale honey teak fibre, straight fine grain, warm gold, a continuous field with no planks, knots or nails",
        "deeper amber teak with tighter dark grain lines and a slight oil-rich satin, no boards",
        "weathered honey-gray teak fibre, sun-faded, still a continuous grain field without boards",
    ]},
    Family { id: "handmade_ceramic", roles: &["wall", "floor", "trim"], roughness: 0.34, spread: 0.04, gain: 0.9, period_m: 1.2, variations: [
        "warm cream handmade ceramic glaze with clearly visible tiny oatmeal speckles and gentle peach pigment pooling, irregular fine ceramic orange-peel relief and ivory-to-honey tonal variation, no reflected highlights, no grout and no tile grid",
        "blush handmade ceramic glaze with soft coral pooling in the micro texture, no grout",
        "sage-ivory ceramic glaze with a faint lagoon edge tone, satin, no grout and no objects",
    ]},
    Family { id: "honed_terrazzo", roles: &["floor", "stairs"], roughness: 0.30, spread: 0.04, gain: 1.3, period_m: 1.4, variations: [
        "warm ivory terrazzo with small cream, blush and pale stone chips, honed, no large slabs",
        "sand terrazzo with sage, honey and shell chips, a denser chip mix, honed flat",
        "pale lagoon terrazzo with aqua, cream and coral chips, fine and honed",
    ]},
    Family { id: "terracotta_tile", roles: &["roof", "floor", "facade"], roughness: 0.70, spread: 0.06, gain: 2.0, period_m: 1.1, variations: [
        "pale salmon terracotta clay, fine pores, warm and dry, a continuous surface without a grout grid",
        "deep burnt-sienna terracotta with darker iron flecks and a coarser clay tooth, no tiles drawn as objects",
        "dusty rose terracotta with cream mineral specks and a softer more open clay",
    ]},
    Family { id: "coral_stone", roles: &["facade", "trim", "floor"], roughness: 0.50, spread: 0.05, gain: 1.7, period_m: 1.5, variations: [
        "pale coral honed stone, warm pink-cream grain and fine shell dust, no joints",
        "richer coral stone with apricot mineral and tiny cream fossils, honed",
        "muted coral-gray reef stone, softer pink and a little more granular, honed",
    ]},
    Family { id: "shell_limestone", roles: &["trim", "facade", "wall", "roof"], roughness: 0.44, spread: 0.04, gain: 1.4, period_m: 1.7, variations: [
        "white shell limestone, creamy and very fine, a few pale gold grains, honed",
        "warm ivory shell stone with faint blush shell fragments, honed",
        "cool pearl shell limestone with a hint of lagoon gray and a tight grain",
    ]},
    Family { id: "pale_resort_stucco", roles: &["wall", "facade", "roof"], roughness: 0.82, spread: 0.05, gain: 1.25, period_m: 2.4, variations: [
        "pale warm stucco, fine sand float, ivory with a wheat cast",
        "slightly blush sand stucco with more open sand sparkle, still a flat coat",
        "ivory stucco with clearly varied sage and honey sand grains, irregular chalky mottling and distinct fine float marks in soft flat light",
    ]},
    Family { id: "lagoon_ceramic", roles: &["trim", "wall"], roughness: 0.24, spread: 0.03, gain: 0.7, period_m: 0.9, variations: [
        "satin lagoon ceramic glaze with visibly uneven aqua-to-milky-teal pigment pooling and fine cream speckles, tiny tactile orange-peel pores, no painted highlights and no grout",
        "deeper teal-lagoon satin glaze with soft cream variation, calm and dielectric",
        "misty aqua glaze with a faint blush thinness in the color, satin, no painted highlights",
    ]},
    Family { id: "weathered_teak_deck", roles: &["floor", "stairs", "roof"], roughness: 0.58, spread: 0.06, gain: 2.6, period_m: 1.25, variations: [
        "sun-faded teak fibre, pale silver-honey, fine raised grain, no planks, gaps or nails",
        "warmer weathered teak with more amber left in the fibre and a slightly rougher tooth, no boards",
        "gray-honey weathered teak with a faint salt-silver cast, a continuous fibre field",
    ]},
];

const OUT_REL: &str = "output/street-social-city-production/romance-pbr-v1";
const N: usize = 2048;

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
fn prompt_for(desc: &str) -> String {
    format!(
        "Use image_gen exactly once. No shell, no subagents, no other tools. Return only the absolute generated image path.\n\
Create ONE original seamless square architectural albedo texture. Request native 2048 by 2048 pixels if image_gen can target that size; otherwise return the largest square image the tool produces.\n\
The subject is only the material surface, scanned flat and filling the frame edge to edge: {desc}. \
Orthographic, perfectly planar, full bleed, even diffuse illumination, seamless on both axes, realistic architectural pigment and fine tactile grain.\n\
No cast shadows, no vignette, no highlights, no glare, no perspective, no border, no text, no numbers, no logo, no watermark, no objects, no furniture, no plants, no windows, no room, no normal-map coloring, no roughness chart, no multi-map sheet.\n"
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
            let prompt = prompt_for(f.variations[v]);
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
            }));
        }
    }
    json!({
        "status": "catalogued",
        "version": "romance-pbr-v1",
        "date": "2026-10-22",
        "set_count": sets.len(),
        "families": FAMILIES.len(),
        "output_resolution": N,
        "metallic": "architectural dielectrics, ORM blue channel is 0",
        "normal_convention": "DirectX tangent space. nx = -dH/dx, ny = +dH/dy (green encodes +Y down), nz reconstructed. Wrapped central differences of a periodic high-pass of albedo luminance. Derived estimate, not a measured scan.",
        "orm_convention": "R = cavity AO estimate kept near 1, G = family-calibrated roughness, B = metallic 0. Derived estimate, not a measured scan and not baked lighting.",
        "seam": "Narrow periodic half-offset blend, then exact opposite-edge match so column 0 equals column N-1 and row 0 equals row N-1.",
        "assignment": "Lua plan hashes building id, category and role into this catalogue. A building reuses sets, but the six-slot tuple is unique. Shader seed, tint and period differ per building.",
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
    let (albedo, normal, orm) = derive_maps(&sized, f)?;
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
            "source_native_2048": sw == 2048 && sh == 2048,
            "resampled_to_2048": resampled,
            "resample_filter": if resampled { "Lanczos3" } else { "none" },
            "output_width": N,
            "output_height": N,
            "basecolor_sha256": sha_file(&folder.join("basecolor.png"))?,
            "normal_sha256": sha_file(&folder.join("normal.png"))?,
            "orm_sha256": sha_file(&folder.join("orm.png"))?,
            "attempts": attempts,
            "provenance": "native Grok image_gen albedo; normal and ORM mathematically derived",
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
    let prompt = prompt_for(f.variations[v]);
    fs::write(folder.join("grok-prompt.txt"), &prompt)?;
    let prompt_sha = sha_bytes(prompt.as_bytes());
    let meta_path = folder.join("generation.json");
    if meta_path.exists() {
        let old: Value = serde_json::from_slice(&fs::read(&meta_path)?)?;
        if old["status"] == "generated" && old["prompt_sha256"] == prompt_sha && folder.join("basecolor.png").is_file() && folder.join("normal.png").is_file() && folder.join("orm.png").is_file() {
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

fn selftest() -> R<()> {
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
    let fake = Family { id: "self", roles: &["wall"], roughness: 0.5, spread: 0.05, gain: 1.5, period_m: 1.0, variations: ["", "", ""] };
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
    if FAMILIES.len() != 16 || FAMILIES.iter().map(|_| 3).sum::<usize>() != 48 {
        return Err("catalogue is not 16x3".into());
    }
    let mut ids = std::collections::BTreeSet::new();
    for f in FAMILIES {
        for v in 0..3 {
            if !ids.insert(set_id(f, v)) {
                return Err("duplicate set id".into());
            }
        }
        for role in ["floor", "wall", "roof", "stairs", "facade", "trim"] {
            let _ = role;
        }
    }
    for role in ["floor", "wall", "roof", "stairs", "facade", "trim"] {
        if !FAMILIES.iter().any(|f| f.roles.contains(&role)) {
            return Err(format!("no family covers {role}").into());
        }
    }
    println!("selftest: passed");
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
                let meta: Value = serde_json::from_slice(&fs::read(folder.join("generation.json"))?)?;
                if meta["status"] != "generated" {
                    return Err(format!("status {}", meta["status"]).into());
                }
                if meta["prompt_sha256"] != sha_file(&folder.join("grok-prompt.txt"))? {
                    return Err("prompt hash mismatch".into());
                }
                let bc = image::open(folder.join("basecolor.png"))?.to_rgb8();
                let nm = image::open(folder.join("normal.png"))?.to_rgb8();
                let orm = image::open(folder.join("orm.png"))?.to_rgb8();
                if bc.dimensions() != (N as u32, N as u32) || nm.dimensions() != (N as u32, N as u32) || orm.dimensions() != (N as u32, N as u32) {
                    return Err("output is not 2048".into());
                }
                if edge_diff(&bc) != 0 || edge_diff(&nm) != 0 || edge_diff(&orm) != 0 {
                    return Err("seam diff is not 0".into());
                }
                if sha_file(&folder.join("basecolor.png"))? != meta["basecolor_sha256"] || sha_file(&folder.join("normal.png"))? != meta["normal_sha256"] || sha_file(&folder.join("orm.png"))? != meta["orm_sha256"] {
                    return Err("map hash mismatch".into());
                }
                let sw = meta["source_width"].as_u64().unwrap_or(0);
                let sh = meta["source_height"].as_u64().unwrap_or(0);
                let native = sw == 2048 && sh == 2048;
                if meta["source_native_2048"].as_bool() != Some(native) {
                    return Err("native 2048 flag does not match the source file".into());
                }
                let square_side = (sw as u32).min(sh as u32);
                let expect_resample = square_side != N as u32;
                if meta["resampled_to_2048"].as_bool() != Some(expect_resample) {
                    return Err("resample flag does not match the source dimensions".into());
                }
                let copy = PathBuf::from(meta["grok_source_copy"].as_str().unwrap_or(""));
                if !copy.is_file() || sha_file(&copy)? != meta["grok_source_copy_sha256"] {
                    return Err("missing grok source copy".into());
                }
                let opened = image::open(&copy)?.to_rgb8();
                if opened.dimensions() != (sw as u32, sh as u32) {
                    return Err("recorded source dimensions differ from the copied image".into());
                }
                let log = PathBuf::from(meta["event_log"].as_str().unwrap_or(""));
                if !log.is_file() || sha_file(&log)? != meta["event_sha256"] || meta["tool_call_id"].as_str().unwrap_or("").is_empty() {
                    return Err("missing tool receipt".into());
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
                for y in (0..N as u32).step_by(8) {
                    for x in (0..N as u32).step_by(8) {
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
                    return Err(format!("map stats len_bad={len_bad} metal={metal} rough_bad={rough_bad} ao_min={ao_min}").into());
                }
                let mean = luma_sum / samples;
                let sd = (luma_sq / samples - mean * mean).max(0.0).sqrt();
                if sd < 0.012 {
                    return Err("basecolor is flat".into());
                }
                means.push((f.id.to_owned(), id.clone(), [rgb[0] / samples / 255.0, rgb[1] / samples / 255.0, rgb[2] / samples / 255.0]));
                Ok(json!({"id": id, "source": format!("{sw}x{sh}"), "native_2048": native, "resampled": meta["resampled_to_2048"], "seam": 0}))
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
    let status = if failures.is_empty() && rows.len() == 48 { "passed" } else { "failed" };
    save_json(&dir.join("verification.json"), &json!({"status": status, "passed": rows.len(), "failed": failures.len(), "rows": rows, "failures": failures}))?;
    if status != "passed" {
        return Err(format!("verify failed: {} passed, {} failed", rows.len(), failures.len()).into());
    }
    println!("verify: 48 passed");
    Ok(())
}

fn sheet(root: &Path) -> R<()> {
    let dir = out_dir(root);
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
                let im = image::open(&path)?.resize_exact(thumb, thumb, FilterType::Triangle).to_rgb8();
                image::imageops::replace(&mut grid, &im, ((v * 3 + k) as i64) * thumb as i64, i as i64 * thumb as i64);
            }
            let bc = folder.join("basecolor.png");
            if bc.is_file() {
                let im = image::open(&bc)?.resize_exact(256, 256, FilterType::Triangle).to_rgb8();
                let n = i * 3 + v;
                image::imageops::replace(&mut big, &im, (n % 8) as i64 * 256, (n / 8) as i64 * 256);
            }
            let meta = fs::read_to_string(folder.join("generation.json")).unwrap_or_else(|_| "{}".into());
            let meta: Value = serde_json::from_str(&meta).unwrap_or(json!({}));
            cards.push_str(&format!(
                "<figure><img src=\"sets/{id}/basecolor.png\" alt=\"{id} basecolor\"><img src=\"sets/{id}/normal.png\" alt=\"{id} normal\"><img src=\"sets/{id}/orm.png\" alt=\"{id} orm\"><figcaption><strong>{id}</strong><br>{desc}<br>source {sw}×{sh}, native 2048: {native}, resampled: {resampled}<br>roughness {rough}, metallic 0</figcaption></figure>\n",
                id = id,
                desc = f.variations[v],
                sw = meta["source_width"].as_u64().unwrap_or(0),
                sh = meta["source_height"].as_u64().unwrap_or(0),
                native = meta["source_native_2048"],
                resampled = meta["resampled_to_2048"],
                rough = f.roughness,
            ));
        }
    }
    grid.save(dir.join("contact-maps.png"))?;
    big.save(dir.join("contact-basecolor.png"))?;
    let html = format!(
        "<!doctype html><meta charset=\"utf-8\"><title>Romance PBR v1</title><style>body{{font:16px/1.45 sans-serif;background:#f6f1ea;color:#2b241d;margin:32px}} figure{{display:inline-block;width:320px;margin:8px;background:#fff;padding:8px}} img{{width:100px;height:100px;object-fit:cover}} figcaption{{font-size:13px}}</style><h1>度假大學城建築材質 romance-pbr-v1</h1><p>48 組。每組一張 Grok 原生 albedo，DirectX normal 與 ORM 由週期導數數學派生，不是掃描實測。金屬度為 0。</p><p><a href=\"contact-basecolor.png\">albedo 接觸表</a> · <a href=\"contact-maps.png\">三圖接觸表</a> · <a href=\"verification.json\">驗證</a> · <a href=\"report.md\">方法</a></p>{cards}"
    );
    fs::write(dir.join("index.html"), html)?;
    let report = format!(
        "# Romance PBR v1\n\n\
日期：2026-10-22。\n\n\
## 方法\n\n\
- 16 個建築材質家族 × 3 個獨立提示，共 48 組。每一組只向 Grok `image_gen` 要一張平面 albedo。\n\
- 工具沒有解析度參數。提示要求原生 2048；`generation.json` 的 `source_width` / `source_height` 與 `source_native_2048` 以實際檔案為準。不是 2048 的圖用 Lanczos3 重採樣，並在 `resampled_to_2048` 標明。\n\
- 接縫：窄帶半週期混合，再讓對邊像素完全相同。法線使用包裹式中心差分，DirectX（nx = -dH/dx，ny = +dH/dy）。高度來自 albedo 亮度的週期高通，不是另一張生成圖，也不是舊的 1K 圖上色。\n\
- ORM：R 為接近 1 的凹洞 AO 估計，G 為家族校正粗糙度，B 金屬度恆為 0。這些是物理約束下的估計，不是測量掃描，也不含烘焙光影。\n\
- 建築著色由 `Tools/street_city_romance_pbr.lua` 依城市計畫與目前地圖做元件覆寫。共用 mesh 不改父材質。\n\n\
## 範圍\n\n\
牆、地面、屋頂、樓梯、立面、線腳。招牌、在地化文字、玻璃、燈、植栽、家具與金屬件排除。\n"
    );
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
    let workers = env::var("ROMANCE_PBR_WORKERS").ok().and_then(|s| s.parse().ok()).unwrap_or(4).clamp(1, 4);
    println!("generate: {} workers, grok {}", workers, exe.display());
    let mut failures = Vec::new();
    let indices: Vec<_> = (0..48).collect();
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
    save_json(&dir.join("generate-summary.json"), &json!({"status": if failures.is_empty() {"passed"} else {"failed"}, "failures": failures}))?;
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
