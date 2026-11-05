use image::{imageops::FilterType, Rgb, RgbImage};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
type R<T> = Result<T, Box<dyn std::error::Error + Send + Sync>>;
const SURFACES: &[(&str,&str,f32,f32)]=&[
 ("plaster","fine painted lime plaster, subtle irregular trowelled micro pores, no large cracks",0.8,0.),
 ("concrete","fine cast concrete pores and very faint sand aggregate, no large seams",0.85,0.),
 ("stone","fine honed natural stone mineral granules, subtle veins, no large slabs",0.55,0.),
 ("wood","fine real timber fibres and subtle parallel grain, no plank divisions or nails",0.65,0.),
 ("fabric","fine woven linen threads in a regular tiny warp and weft weave",0.9,0.),
 ("ceramic","very fine glazed ceramic orange peel surface, extremely subtle tiny pores, no grout",0.28,0.),
 ("asphalt","asphalt small mineral aggregate, no road lines, no text, no cracks",0.93,0.),
 ("rubber","fine matte rubber stipple and tiny pores, no tire tread or macro features",0.87,0.),
 ("metal","very fine brushed stainless steel machining scratches, no bolts, no highlights",0.32,1.),
 ("plastic","very fine polymer surface, subtle injection moulded micro stipple, no large features",0.45,0.),
 ("bark","fine tree bark fibres and shallow narrow fissures, no tree silhouette",0.95,0.),
 ("foliage","extremely subtle leaf cuticle microscopic cellular texture, no leaf silhouettes or stems",0.72,0.),
 ("leather","fine leather grain pores, no stitching, no cushion shape",0.65,0.),
 ("paper","fine coated printed paper or sign laminate microscopic fibre, no lettering",0.6,0.),
 ("soil","fine dry soil particles and sand, no stones larger than grains, no plants",0.98,0.),
 ("grass","tiny grass leaf microfibres seen as an even tightly woven natural turf surface, no perspective",0.94,0.)];
fn sha(p: &Path) -> R<String> {
    Ok(format!("{:x}", Sha256::digest(fs::read(p)?)))
}
fn save(p: &Path, v: &Value) -> R<()> {
    fs::write(p, serde_json::to_vec_pretty(v)?)?;
    Ok(())
}
fn encode(s: &str) -> String {
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
fn receipt(folder: &Path, sid: &str) -> R<Option<(PathBuf, PathBuf, String)>> {
    let log = PathBuf::from(std::env::var("USERPROFILE")?)
        .join(".grok/sessions")
        .join(encode(&folder.to_string_lossy().replace('/', "\\")))
        .join(sid)
        .join("chat_history.jsonl");
    if !log.exists() {
        return Ok(None);
    }
    let events: Vec<Value> = fs::read_to_string(&log)?
        .lines()
        .filter_map(|s| serde_json::from_str(s).ok())
        .collect();
    let expected = fs::read_to_string(folder.join("grok-prompt.txt"))?;
    let matched = events.iter().filter(|e| e["type"] == "user").any(|e| {
        let c = if let Some(s) = e["content"].as_str() {
            s.to_owned()
        } else {
            e["content"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|v| v["text"].as_str())
                .collect::<Vec<_>>()
                .join("\n")
        };
        let c = c
            .split("<user_query>\n")
            .nth(1)
            .map(|s| s.rsplit("\n</user_query>").last().unwrap_or(s))
            .unwrap_or(&c);
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
    for e in events.iter().rev() {
        if e["type"] != "tool_result" {
            continue;
        }
        if let Some(id) = e["tool_call_id"].as_str() {
            if !calls.contains(&id.to_owned()) {
                continue;
            }
            if let Some(s) = e["content"].as_str() {
                if let Ok(v) = serde_json::from_str::<Value>(s) {
                    if let Some(p) = v["path"].as_str() {
                        let p = PathBuf::from(p);
                        if p.is_file() && p.starts_with(log.parent().unwrap()) {
                            return Ok(Some((p, log.clone(), id.into())));
                        }
                    }
                }
            }
        }
    }
    Ok(None)
}
fn one(root: &Path, i: usize) -> R<()> {
    let (name, description, rough, metal) = SURFACES[i];
    let folder = root
        .join("output/street-social-city-production/pbr-grok-v1/maps")
        .join(name);
    fs::create_dir_all(&folder)?;
    let prompt=format!("Use image_gen exactly once to generate a single square 1024x1024 seamless grayscale HEIGHT texture for {description}. This is a technical material height map, not a photograph, not a shaded render. Uniform neutral gray baseline; white is microscopic raised relief, dark is microscopic indentation. Very low amplitude, evenly distributed microdetail, orthographic straight-on, flat neutral information with absolutely no light, shadows, vignette, glare, perspective, border, lettering or legend. Tileable edges. Fill entire image. Normal and roughness will be mathematically derived from this generated height. Return the saved image path. Do not run commands, do not edit any code.");
    fs::write(folder.join("grok-prompt.txt"), &prompt)?;
    let prompt_sha = format!("{:x}", Sha256::digest(prompt.as_bytes()));
    let meta = folder.join("generation.json");
    if meta.exists() {
        let v: Value = serde_json::from_slice(&fs::read(&meta)?)?;
        if v["prompt_sha256"] == prompt_sha && folder.join("height.png").exists() {
            println!("{name}: cached");
            return Ok(());
        }
    }
    let previous = fs::read(folder.join("grok-run.json"))
        .ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        .and_then(|v| v["sessionId"].as_str().map(str::to_owned));
    let existing = if let Some(s) = &previous {
        receipt(&folder, s)?
    } else {
        None
    };
    let tick = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let sid = if existing.is_some() {
        previous.unwrap()
    } else {
        format!(
            "{:08x}-{:04x}-4{:03x}-8{:03x}-{:012x}",
            (tick >> 64) as u32,
            ((tick >> 48) & 65535) as u16,
            ((tick >> 36) & 4095) as u16,
            ((tick >> 24) & 4095) as u16,
            (tick & 0xffffffffffff) as u64
        )
    };
    let proof = if let Some(p) = existing {
        p
    } else {
        let mut cmd = Command::new("grok.exe");
        cmd.args(["--session-id", &sid, "--prompt-file"])
            .arg(folder.join("grok-prompt.txt"))
            .arg("--cwd")
            .arg(&folder)
            .args([
                "--model",
                "grok-4.7",
                "--effort",
                "medium",
                "--tools",
                "image_gen",
                "--no-subagents",
                "--disable-web-search",
                "--always-approve",
                "--no-auto-update",
                "--max-turns",
                "3",
                "--output-format",
                "json",
            ])
            .env("GROK_MEMORY", "0")
            .stdout(Stdio::from(fs::File::create(folder.join("grok-run.json"))?))
            .stderr(Stdio::from(fs::File::create(
                folder.join("grok-stderr.log"),
            )?));
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x08000000);
        }
        let mut child = cmd.spawn()?;
        let start = Instant::now();
        let proof;
        loop {
            if let Some(p) = receipt(&folder, &sid)? {
                proof = p;
                break;
            }
            if let Some(status) = child.try_wait()? {
                return Err(format!("{name} no image receipt, exit {status}").into());
            }
            if start.elapsed() > Duration::from_secs(300) {
                let _ = child.kill();
                return Err(format!("{name} timed out").into());
            }
            thread::sleep(Duration::from_secs(2));
        }
        // No model work beyond the completed image is required. The process has a 3-turn cap.
        for _ in 0..10 {
            if child.try_wait()?.is_some() {
                break;
            }
            thread::sleep(Duration::from_secs(1));
        }
        if child.try_wait()?.is_none() {
            child.kill()?;
        }
        let _ = child.wait();
        proof
    };
    let raw = image::open(&proof.0)?.to_luma8();
    let raw = image::imageops::resize(&raw, 1024, 1024, FilterType::Lanczos3);
    // Opposite edge crossfade removes source generation seams; numerical normals use wrapped derivatives.
    let n = 1024usize;
    let mut h = vec![0f32; n * n];
    for y in 0..n {
        for x in 0..n {
            let wx = (std::f32::consts::PI * x as f32 / n as f32).sin().powi(2);
            let wy = (std::f32::consts::PI * y as f32 / n as f32).sin().powi(2);
            let at = |xx: usize, yy: usize| raw.get_pixel(xx as u32, yy as u32).0[0] as f32 / 255.;
            h[y * n + x] = at(x, y) * wx * wy
                + at((x + n / 2) % n, y) * (1. - wx) * wy
                + at(x, (y + n / 2) % n) * wx * (1. - wy)
                + at((x + n / 2) % n, (y + n / 2) % n) * (1. - wx) * (1. - wy);
        }
    }
    let mut height = RgbImage::new(n as u32, n as u32);
    let mut normal = height.clone();
    let mut orm = height.clone();
    for y in 0..n {
        for x in 0..n {
            let at = |xx: usize, yy: usize| h[yy * n + xx];
            let dx = (at((x + 1) % n, y) - at((x + n - 1) % n, y)) * 1.5;
            let dy = (at(x, (y + 1) % n) - at(x, (y + n - 1) % n)) * 1.5;
            let len = (dx * dx + dy * dy + 1.).sqrt();
            let encode = |a: f32| ((a * 0.5 + 0.5) * 255.).round().clamp(0., 255.) as u8;
            normal.put_pixel(
                x as u32,
                y as u32,
                Rgb([encode(-dx / len), encode(dy / len), encode(1. / len)]),
            );
            let value = (h[y * n + x] * 255.).round() as u8;
            height.put_pixel(x as u32, y as u32, Rgb([value; 3]));
            let r = (rough + (h[y * n + x] - 0.5) * 0.12).clamp(0.05, 1.);
            orm.put_pixel(
                x as u32,
                y as u32,
                Rgb([255, (r * 255.).round() as u8, (metal * 255.) as u8]),
            );
        }
    }
    height.save(folder.join("height.png"))?;
    normal.save(folder.join("normal.png"))?;
    orm.save(folder.join("orm.png"))?;
    save(
        &meta,
        &json!({"status":"generated","prompt_sha256":prompt_sha,"session_id":sid,"tool_call_id":proof.2,"event_log":proof.1,"event_sha256":sha(&proof.1)?,"grok_original":proof.0,"grok_sha256":sha(&proof.0)?,"normal_sha256":sha(&folder.join("normal.png"))?,"orm_sha256":sha(&folder.join("orm.png"))?,"roughness":rough,"metallic":metal,"normal_convention":"DirectX tangent space +Y down, numeric wrapped derivatives from Grok height","orm":"R=unoccluded AO 1; G=roughness calibrated to physical family; B=metallic 0 or 1; no baked light"}),
    )?;
    println!("{name}: generated + derived normal / ORM");
    Ok(())
}
fn main() -> R<()> {
    let root = PathBuf::from(
        std::env::args()
            .nth(1)
            .unwrap_or("C:/portable/OpenKoikatsu".into()),
    );
    let root = fs::canonicalize(root)?
        .to_string_lossy()
        .trim_start_matches(r"\\?\")
        .to_owned();
    let root = PathBuf::from(root);
    for chunk in (0..SURFACES.len()).collect::<Vec<_>>().chunks(4) {
        let jobs: Vec<_> = chunk
            .iter()
            .map(|&i| {
                let r = root.clone();
                thread::spawn(move || one(&r, i))
            })
            .collect();
        for j in jobs {
            j.join().unwrap()?;
        }
    }
    let out = root.join("output/street-social-city-production/pbr-grok-v1");
    let mut sheet = RgbImage::new(1536, 1024);
    for (i, (name, _, _, _)) in SURFACES.iter().enumerate() {
        for (k, kind) in ["height", "normal", "orm"].iter().enumerate() {
            let im = image::open(out.join("maps").join(name).join(format!("{kind}.png")))?
                .resize_exact(128, 256, FilterType::Triangle)
                .to_rgb8();
            image::imageops::replace(
                &mut sheet,
                &im,
                ((i % 4) * 384 + k * 128) as i64,
                ((i / 4) * 256) as i64,
            );
        }
    }
    sheet.save(out.join("maps-contact.png"))?;
    Ok(())
}
