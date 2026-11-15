//! ok-hairdeck: HairDeck (github.com/hyz317/HairDeck, Apache-2.0) hair cards, colours and spring chains from one
//! character image, without Python. The networks are those of hairdeck.infer.image.Pipeline; the preprocessing (SAM 3
//! masks, BiRefNet matte) is replaced by a crop box given by the caller and the image's own alpha as the matte.
//!
//!   ok-hairdeck generate --image IMG --out DIR [--box x0,y0,x1,y1] [--seed 0] [--n 1] [--steps 50] [--cfg 2]
//!                        [--weights F:/HairDeckData] [--noise N.npy] [--chain-noise N.npy] [--no-chains] [--no-colors]
//!
//! Writes DIR/model_input.png, DIR/cards_seed<s>.json ([{shape, seq, colors}], HairDeck's format), DIR/chains_seed<s>.json
//! and DIR/info.json. The weights folder is a HairDeck workspace (scripts/setup/download_weights.py).
use candle_core::{Device, Tensor};
use nn::{e, R};
use std::path::{Path, PathBuf};
use std::time::Instant;

mod cards;
mod dino;
mod dit;
mod nn;

struct Args {
    image: PathBuf,
    out: PathBuf,
    boxx: Option<[f32; 4]>,
    seed: u64,
    n: usize,
    steps: usize,
    cfg: f32,
    weights: PathBuf,
    noise: Option<PathBuf>,
    chain_noise: Option<PathBuf>,
    chains: bool,
    colors: bool,
    cpu: bool,
}

fn parse(a: &[String]) -> R<Args> {
    let mut r = Args { image: PathBuf::new(), out: PathBuf::new(), boxx: None, seed: 0, n: 1, steps: 50, cfg: 2.0,
        weights: std::env::var_os("HAIRDECK_ROOT").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("F:/HairDeckData")),
        noise: None, chain_noise: None, chains: true, colors: true, cpu: false };
    let mut i = 0;
    let val = |i: &mut usize| -> R<String> { *i += 1; a.get(*i).cloned().ok_or_else(|| format!("{} 後面少了值", a[*i - 1])) };
    while i < a.len() {
        match a[i].as_str() {
            "--image" => r.image = val(&mut i)?.into(),
            "--out" => r.out = val(&mut i)?.into(),
            "--box" => { let v: Vec<f32> = val(&mut i)?.split(',').filter_map(|x| x.trim().parse().ok()).collect(); if v.len() != 4 { return Err("--box 要 x0,y0,x1,y1".into()); } r.boxx = Some([v[0], v[1], v[2], v[3]]); }
            "--seed" => r.seed = val(&mut i)?.parse().map_err(e)?,
            "--n" => r.n = val(&mut i)?.parse::<usize>().map_err(e)?.clamp(1, 4),
            "--steps" => r.steps = val(&mut i)?.parse().map_err(e)?,
            "--cfg" => r.cfg = val(&mut i)?.parse().map_err(e)?,
            "--weights" => r.weights = val(&mut i)?.into(),
            "--noise" => r.noise = Some(val(&mut i)?.into()),
            "--chain-noise" => r.chain_noise = Some(val(&mut i)?.into()),
            "--no-chains" => r.chains = false,
            "--no-colors" => r.colors = false,
            "--cpu" => r.cpu = true,
            x => return Err(format!("不認得的參數 {x}")),
        }
        i += 1;
    }
    if r.image.as_os_str().is_empty() || r.out.as_os_str().is_empty() { return Err("需要 --image 與 --out".into()); }
    Ok(r)
}

/// The model input (crop_white of the matte composited on white) and the matte cut the same way.
fn prep(img: &image::RgbaImage, b: [f32; 4], res: usize) -> (Vec<u8>, Vec<bool>, image::RgbImage) {
    let [x0, y0, x1, y1] = b.map(|v| v.round() as i64);
    let (w, h) = ((x1 - x0).max(1) as u32, (y1 - y0).max(1) as u32);
    let mut canvas = image::RgbImage::from_pixel(w, h, image::Rgb([255, 255, 255]));
    let mut matte = image::GrayImage::new(w, h);
    for y in 0..h {
        for x in 0..w {
            let (sx, sy) = (x as i64 + x0, y as i64 + y0);
            if sx < 0 || sy < 0 || sx >= img.width() as i64 || sy >= img.height() as i64 { continue; }
            let p = img.get_pixel(sx as u32, sy as u32).0;
            let a = p[3] as f32 / 255.0;
            canvas.put_pixel(x, y, image::Rgb([0, 1, 2].map(|c| (p[c] as f32 * a + 255.0 * (1.0 - a) + 0.5) as u8)));
            matte.put_pixel(x, y, image::Luma([p[3]]));
        }
    }
    let crop = image::imageops::resize(&canvas, res as u32, res as u32, image::imageops::FilterType::CatmullRom);
    let m = image::imageops::resize(&matte, res as u32, res as u32, image::imageops::FilterType::Nearest);
    let mut mv: Vec<bool> = m.pixels().map(|p| p.0[0] > 127).collect();
    if !mv.iter().any(|v| *v) { mv.iter_mut().for_each(|v| *v = true); }
    (crop.as_raw().clone(), mv, crop)
}

/// An opaque image's matte (BiRefNet's in HairDeck): what differs from the corners' colour (a flat background).
fn matte_from_background(img: &mut image::RgbaImage) {
    if img.pixels().any(|p| p.0[3] < 250) { return; }
    let (w, h) = (img.width(), img.height());
    let corners: Vec<[u8; 4]> = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)].iter().map(|&(x, y)| img.get_pixel(x, y).0).collect();
    let bg: [i32; 3] = std::array::from_fn(|c| { let mut v: Vec<i32> = corners.iter().map(|p| p[c] as i32).collect(); v.sort(); (v[1] + v[2]) / 2 });
    let spread: i32 = corners.iter().map(|p| (0..3).map(|c| (p[c] as i32 - bg[c]).abs()).sum::<i32>()).max().unwrap_or(0);
    if spread > 60 { return; } // not a flat background: keep the whole image
    for p in img.pixels_mut() { if (0..3).map(|c| (p.0[c] as i32 - bg[c]).abs()).sum::<i32>() <= 40 { p.0[3] = 0; } }
}

/// Without SAM 3's hair and face masks: the character is the alpha (or what differs from the corners' colour), the
/// head the top of it — a square as wide as the character's top part, a third of its height for a full figure.
fn auto_box(img: &image::RgbaImage) -> [f32; 4] {
    let (w, h) = (img.width() as usize, img.height() as usize);
    let fg = |p: [u8; 4]| p[3] > 127;
    let rows: Vec<Option<(usize, usize)>> = (0..h).map(|y| {
        let xs: Vec<usize> = (0..w).filter(|&x| fg(img.get_pixel(x as u32, y as u32).0)).collect();
        if xs.len() < 2 { None } else { Some((xs[0], *xs.last().unwrap())) }
    }).collect();
    let (Some(top), Some(bottom)) = (rows.iter().position(|r| r.is_some()), rows.iter().rposition(|r| r.is_some())) else {
        let s = w.min(h) as f32; let x = (w as f32 - s) / 2.0; return [x, 0.0, x + s, s];
    };
    let (mut x0, mut x1) = (w, 0);
    for r in rows.iter().flatten() { x0 = x0.min(r.0); x1 = x1.max(r.1); }
    let (bw, bh) = ((x1 - x0 + 1) as f32, (bottom - top + 1) as f32);
    let side = if bh > 1.8 * bw { bh / 3.0 } else { bw.min(bh) };
    // centred on the character's top part
    let span = rows[top..(top + side as usize).min(h)].iter().flatten().fold((w, 0), |a, r| (a.0.min(r.0), a.1.max(r.1)));
    let cx = (span.0 + span.1) as f32 / 2.0;
    let y0 = top as f32 - 0.04 * side;
    [cx - side / 2.0, y0, cx + side / 2.0, y0 + side]
}

fn noise(path: Option<&Path>, seed: u64, shape: (usize, usize)) -> R<Vec<f32>> {
    match path {
        Some(p) => {
            let (v, s) = nn::read_npy(p)?;
            if v.len() != shape.0 * shape.1 { return Err(format!("{} 的形狀 {s:?} 不是 {shape:?}", p.display())); }
            Ok(v)
        }
        None => Ok(nn::randn(seed, shape.0 * shape.1)),
    }
}

fn run(a: Args) -> R<()> {
    let dev = if a.cpu { Device::Cpu } else { Device::new_cuda(0).unwrap_or(Device::Cpu) };
    let root = &a.weights;
    let t0 = Instant::now();
    let img_w = nn::Weights::load(&root.join("ckpt/image_model/model.safetensors"), &dev, "image DiT")?;
    let (dim_, depth, heads, res, nmax) = (img_w.arg_usize("dim")?, img_w.arg_usize("depth")?, img_w.arg_usize("heads")?, img_w.arg_usize("res")?, img_w.arg_usize("nmax")?);
    let _ = dim_;
    let model = dit::SetDiT::new(img_w, "", depth, heads, &dev);
    let enc = dino::Dino::load(&root.join("third_party/weights/dinov3/model.safetensors"), res, &dev)?;
    let tok = cards::Tokenizer::load(&root.join("data/token_stats_head.json"), &root.join("ckpt/card_vae/latent_stats_head.json"))?;
    let vae = cards::CardVae::load(&root.join("ckpt/card_vae"), &dev)?;
    let color = if a.colors {
        let w = nn::Weights::load(&root.join("ckpt/color_model/model.safetensors"), &dev, "colour model")?;
        Some(dit::SetDiT::new(w, "dit.", depth, heads, &dev))
    } else { None };
    let chain = if a.chains {
        let w = nn::Weights::load(&root.join("ckpt/chain_model/model.safetensors"), &dev, "chain DiT")?;
        let (d, h) = (w.arg_usize("depth")?, w.arg_usize("heads")?);
        let cdim = w.meta["dim"].as_u64().ok_or("chain DiT 缺少 dim")? as usize;
        Some((dit::SetDiT::new(w, "", d, h, &dev), cdim))
    } else { None };
    let load_sec = t0.elapsed().as_secs_f64();

    let mut rgba = image::open(&a.image).map_err(|x| format!("{}：{x}", a.image.display()))?.to_rgba8();
    matte_from_background(&mut rgba);
    let b = a.boxx.unwrap_or_else(|| auto_box(&rgba));
    let (crop, matte, crop_img) = prep(&rgba, b, res);
    std::fs::create_dir_all(&a.out).map_err(e)?;
    crop_img.save(a.out.join("model_input.png")).map_err(e)?;

    let t1 = Instant::now();
    let feats = enc.forward(&crop)?;
    let ctx = model.encode_image(&feats)?;
    let color_ctx = match &color {
        Some(c) => {
            let base = c.encode_image(&feats)?;
            // per 16 px patch: mean RGB, matte fraction, mean RGB under the matte
            let g = res / 16;
            let mut st = vec![0f32; g * g * 7];
            for py in 0..g {
                for px in 0..g {
                    let (mut s, mut sm, mut f) = ([0f32; 3], [0f32; 3], 0f32);
                    for y in py * 16..py * 16 + 16 {
                        for x in px * 16..px * 16 + 16 {
                            let m = matte[y * res + x] as u8 as f32;
                            f += m;
                            for c in 0..3 { let v = crop[(y * res + x) * 3 + c] as f32 / 255.0; s[c] += v; sm[c] += v * m; }
                        }
                    }
                    let fr = f / 256.0;
                    let o = &mut st[(py * g + px) * 7..][..7];
                    for c in 0..3 { o[c] = s[c] / 256.0; o[4 + c] = (sm[c] / 256.0) / fr.max(1e-3); }
                    o[3] = fr;
                }
            }
            let st = Tensor::from_vec(st, (1, g * g, 7), &dev).map_err(e)?;
            let add = c.w.linear(&st, "patch")?;
            let head = base.narrow(1, 0, 5).map_err(e)?;
            let rest = (base.narrow(1, 5, g * g).map_err(e)? + add).map_err(e)?;
            Some(Tensor::cat(&[&head, &rest], 1).map_err(e)?)
        }
        None => None,
    };
    let mut samples = Vec::new();
    for k in 0..a.n {
        let seed = a.seed + k as u64;
        let ts = Instant::now();
        let x0 = noise(if k == 0 { a.noise.as_deref() } else { None }, seed, (nmax, tok.dim))?;
        let x0 = Tensor::from_vec(x0, (1, nmax, tok.dim), &dev).map_err(e)?;
        let x = model.sample(&ctx, x0, a.steps, a.cfg)?;
        let xv: Vec<f32> = x.flatten_all().and_then(|t| t.to_vec1()).map_err(e)?;
        let cards = cards::tokens_to_cards(&tok, &vae, &xv)?;
        let mut card_colors: Option<Vec<Vec<[f64; 3]>>> = None;
        if let (Some(c), Some(cctx)) = (&color, &color_ctx) {
            let mut xc = tok.clean(&xv);
            tok.sign_normals(&mut xc);
            let xt = Tensor::from_vec(xc.clone(), (1, nmax, tok.dim), &dev).map_err(e)?;
            let (cc, h) = c.trunk(&xt, &[0.0], cctx)?;
            let f = nn::chunks(&c.w.linear(&cc.silu().map_err(e)?, "col_ada")?, 2)?;
            let y = c.w.linear(&nn::modulate(&nn::ln_plain(&h, 1e-6)?, &f[0], &f[1])?, "col_out")?;
            let y: Vec<Vec<f32>> = y.squeeze(0).and_then(|t| t.to_vec2()).map_err(e)?;
            let mu: Vec<f32> = c.w.p("mu")?.to_vec1().map_err(e)?;
            let sd: Vec<f32> = c.w.p("sd")?.to_vec1().map_err(e)?;
            let mut cols = Vec::new();
            for (slot, s) in xc.chunks(tok.dim).enumerate() {
                if !tok.exist(s) { continue; }
                let r = &y[slot];
                cols.push((0..16).map(|bin| {
                    let lab: [f64; 3] = std::array::from_fn(|q| (r[bin * 3 + q] * sd[q] + mu[q]) as f64);
                    cards::lab_to_srgb(lab[0], lab[1], lab[2]).map(|v| (v * 1e4).round() / 1e4)
                }).collect());
            }
            card_colors = Some(cols);
        }
        let json: Vec<serde_json::Value> = cards.iter().enumerate().map(|(i, (seq, tri))| {
            let mut o = serde_json::json!({"shape": if *tri { "triangle" } else { "square" }, "seq": seq});
            if let Some(c) = &card_colors { o["colors"] = serde_json::json!(c[i]); }
            o
        }).collect();
        std::fs::write(a.out.join(format!("cards_seed{seed}.json")), serde_json::to_vec(&json).map_err(e)?).map_err(e)?;
        let mut n_chains = None;
        if let Some((cm, cdim)) = &chain {
            let xc = tok.clean(&xv);
            let cctx = cm.encode_cards(&Tensor::from_vec(xc, (1, nmax, tok.dim), &dev).map_err(e)?)?;
            let z = noise(if k == 0 { a.chain_noise.as_deref() } else { None }, seed ^ 0xC4A1, (48, *cdim))?;
            let xs = cm.sample(&cctx, Tensor::from_vec(z, (1, 48, *cdim), &dev).map_err(e)?, 50, 2.0)?;
            let xs: Vec<f32> = xs.flatten_all().and_then(|t| t.to_vec1()).map_err(e)?;
            let ch = cards::decode_chains(&xs, *cdim, &root.join("data/spring/chain_stats_head.json"))?;
            n_chains = ch.as_array().map(|v| v.len());
            std::fs::write(a.out.join(format!("chains_seed{seed}.json")), serde_json::to_vec(&ch).map_err(e)?).map_err(e)?;
        }
        println!("seed {seed}: {} cards, {:?} chains, {:.1}s", cards.len(), n_chains, ts.elapsed().as_secs_f64());
        samples.push(serde_json::json!({"seed": seed, "n_cards": cards.len(), "n_chains": n_chains, "colors": card_colors.is_some()}));
    }
    let info = serde_json::json!({"image": a.image, "box": b, "res": res, "steps": a.steps, "cfg": a.cfg, "device": format!("{dev:?}"),
        "load_sec": load_sec, "generate_sec": t1.elapsed().as_secs_f64(), "samples": samples});
    std::fs::write(a.out.join("info.json"), serde_json::to_vec_pretty(&info).map_err(e)?).map_err(e)?;
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let r = match args.first().map(String::as_str) {
        Some("generate") => parse(&args[1..]).and_then(run),
        _ => Err("用法：ok-hairdeck generate --image IMG --out DIR [--box x0,y0,x1,y1] [--seed 0] [--n 1] [--weights F:/HairDeckData]".into()),
    };
    if let Err(x) = r { eprintln!("ok-hairdeck: {x}"); std::process::exit(1); }
}
