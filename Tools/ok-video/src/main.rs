//! ok-video: video to OK motion without Python (Docs/VIDEO_MOTION_NATIVE_PLAN.md).
use candle_core::{DType, Device, Tensor};
use std::path::Path;
use std::time::Instant;

mod crop;
mod flowhmr;
mod geom;
mod gvhmr;
mod npy;
mod models;
mod mhr;
mod pairalign;
mod pickle;
mod pipeline;
mod sam3d;
mod smplx;
mod track;
mod video;
mod vit;
mod vo;
mod yolo;

/// One tensor of a torch.save file as f32 (`name` "" for a bare tensor).
fn read_pt(path: &Path, name: &str) -> Result<(Vec<f32>, Vec<usize>), String> {
    let mut ck = pickle::Checkpoint::open(path)?;
    let t = ck.tensors.iter().find(|t| t.name == name).cloned().ok_or_else(|| format!("{} 沒有 {name:?}", path.display()))?;
    let b = ck.bytes(&t)?;
    let v = match t.dtype {
        pickle::DType::F32 => b.chunks_exact(4).map(|c| f32::from_le_bytes(c.try_into().unwrap())).collect(),
        pickle::DType::F64 => b.chunks_exact(8).map(|c| f64::from_le_bytes(c.try_into().unwrap()) as f32).collect(),
        pickle::DType::F16 => b.chunks_exact(2).map(|c| half::f16::from_le_bytes([c[0], c[1]]).to_f32()).collect(),
        d => return Err(format!("{name}: unsupported dtype {d:?}")),
    };
    Ok((v, t.shape))
}

/// Probe width/height with ffprobe (Tools/ffmpeg).
fn video_size(video: &Path) -> Result<(u32, u32), String> {
    let exe = std::env::var("OK_FFPROBE").unwrap_or_else(|_| "C:/portable/OpenKoikatsu/Tools/ffmpeg/ffprobe.exe".into());
    let out = std::process::Command::new(&exe)
        .args(["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0"])
        .arg(video)
        .output()
        .map_err(|e| format!("無法執行 {exe}：{e}"))?;
    let s = String::from_utf8_lossy(&out.stdout);
    let mut it = s.trim().split(',').map(|v| v.trim().parse::<u32>());
    match (it.next(), it.next()) {
        (Some(Ok(w)), Some(Ok(h))) => Ok((w, h)),
        _ => Err(format!("ffprobe 讀不到 {} 的尺寸：{}", video.display(), String::from_utf8_lossy(&out.stderr))),
    }
}

/// Project root: the nearest ancestor of the executable holding OpenKoikatsu.uproject.
fn project_root() -> std::path::PathBuf {
    if let Ok(me) = std::env::current_exe() {
        for d in me.ancestors().skip(1) {
            if d.join("OpenKoikatsu.uproject").is_file() {
                return d.to_path_buf();
            }
        }
    }
    std::env::current_dir().unwrap_or_default()
}

const IMPORT_USAGE: &str = "ok-video import <影片> [--name 名稱] [--method gvhmr|flowhmr] [--features <SAM 特徵.npy>] [--seed 42] [-s] [--f_mm N] [--pair --left male|female --game <遊戲目錄>] [--arm-reach 1.0] [--collar-scale 0.5] [--smooth 1.0] [--models <checkpoints>] [--out-dir <dir>] [--card <png>] [--ok-extract <exe>] [--skip-gvhmr] [--no-validate]";

fn import(args: &[String]) -> Result<(), String> {
    let root = project_root();
    let mut it = args.iter();
    let mut video = None;
    let mut name = None;
    let mut flag = |k: &str| args.iter().any(|a| a == k);
    let static_cam = flag("-s") || flag("--static_cam");
    let pair = flag("--pair");
    let skip = flag("--skip-gvhmr");
    let no_validate = flag("--no-validate");
    let value = |k: &str| args.iter().position(|a| a == k).and_then(|i| args.get(i + 1)).cloned();
    let num = |k: &str, d: f64| -> Result<f64, String> {
        match value(k) {
            Some(v) => v.parse::<f64>().map_err(|_| format!("{k} 需要數字：{v}")),
            None => Ok(d),
        }
    };
    while let Some(a) = it.next() {
        if a.starts_with('-') {
            if matches!(a.as_str(), "--name" | "--f_mm" | "--left" | "--game" | "--arm-reach" | "--collar-scale" | "--smooth" | "--models" | "--out-dir" | "--card" | "--ok-extract" | "--data" | "--method" | "--seed" | "--features") {
                let v = it.next();
                if a == "--name" {
                    name = v.cloned();
                }
            }
        } else if video.is_none() {
            video = Some(std::path::PathBuf::from(a));
        }
    }
    let video = video.ok_or_else(|| format!("缺少影片路徑。用法：{IMPORT_USAGE}"))?;
    let out_dir = value("--out-dir").map(Into::into).unwrap_or_else(|| root.join("Saved").join("VideoMotions"));
    // Model root: --models, OK_GVHMR_MODELS, local-instance.json "gvhmr_models", then <project>/ref/GVHMR/inputs/checkpoints.
    let local = std::fs::read_to_string(root.join("local-instance.json")).ok().and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok());
    let models_root = value("--models")
        .or_else(|| std::env::var("OK_GVHMR_MODELS").ok())
        .or_else(|| local.as_ref().and_then(|v| v["gvhmr_models"].as_str().map(String::from)))
        .map(Into::into)
        .unwrap_or_else(|| root.join("ref/GVHMR/inputs/checkpoints"));
    let game: Option<std::path::PathBuf> = value("--game").map(Into::into);
    // Validation card: --card; the bundled portable card when it still has a snapshot; else the game's first female card.
    let card = if no_validate {
        None
    } else if let Some(c) = value("--card") {
        Some(c.into())
    } else {
        let bundled = root.join("Content/CharacterCards/CrowdAPNG/C000.png");
        if pipeline::portable_card(&bundled) {
            Some(bundled)
        } else {
            let folder = game.as_ref().map(|g| g.join("UserData/chara/female"));
            let mut cards: Vec<std::path::PathBuf> = folder
                .and_then(|f| std::fs::read_dir(f).ok())
                .map(|d| d.filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.extension().is_some_and(|x| x.eq_ignore_ascii_case("png"))).collect())
                .unwrap_or_default();
            cards.sort();
            Some(cards.into_iter().next().ok_or("找不到驗證用的女性角色卡：請用 --card 指定，或用 --game 指向含 UserData/chara/female/*.png 的遊戲目錄（也可用 --no-validate 略過驗證）")?)
        }
    };
    let left = value("--left").unwrap_or_else(|| "male".into());
    if left != "male" && left != "female" {
        return Err(format!("--left 只能是 male 或 female：{left}"));
    }
    let o = pipeline::Options {
        name: name.unwrap_or_else(|| video.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default()),
        video: std::fs::canonicalize(&video).unwrap_or(video),
        models: models::Paths { root: models_root, cache: out_dir.join("models") },
        out_dir,
        static_cam,
        f_mm: value("--f_mm").and_then(|v| v.parse().ok()).filter(|v: &f64| *v > 0.),
        pair,
        left_male: left == "male",
        game,
        card,
        ok_extract: value("--ok-extract").map(Into::into).unwrap_or_else(|| root.join("Tools/ok-extract/target/release/ok-extract.exe")),
        data: value("--data").map(Into::into).unwrap_or_else(|| root.join("Tools/video_motion/data")),
        arm_reach: num("--arm-reach", 1.)?,
        collar_scale: num("--collar-scale", 0.5)?,
        smooth: num("--smooth", 1.)?,
        skip_gvhmr: skip,
        method: models::Method::parse(&value("--method").unwrap_or_else(|| "gvhmr".into()))?,
        seed: value("--seed").map(|v| v.parse::<u64>().map_err(|_| format!("--seed 需要非負整數：{v}"))).transpose()?.unwrap_or(42),
        features: value("--features").map(Into::into),
    };
    let _ = &mut flag;
    pipeline::run(&o)
}

/// `compare-motion <a.npz> <b.npz> <SMPLX_NEUTRAL.npz>`: per-joint world distance (MPJPE) and angle differences.
fn compare_motion(args: &[String]) -> Result<(), String> {
    let (a, b) = (Path::new(args.first().ok_or("a.npz")?), Path::new(args.get(1).ok_or("b.npz")?));
    let skel = gvhmr::Skeleton::load(Path::new(args.get(2).ok_or("SMPLX_NEUTRAL.npz")?))?;
    let keys = ["global_orient", "body_pose", "transl", "betas"];
    let (ma, mb) = (npy::read_npz(a, &keys)?, npy::read_npz(b, &keys)?);
    let l = ma["transl"].shape[0].min(mb["transl"].shape[0]);
    let joints = |m: &std::collections::HashMap<String, npy::Array>, t: usize| {
        let betas: [f64; 10] = std::array::from_fn(|k| m["betas"].data[t * 10 + k]);
        let pose: [geom::V3; 21] = std::array::from_fn(|j| std::array::from_fn(|k| m["body_pose"].data[t * 63 + j * 3 + k]));
        gvhmr::fk(&skel, std::array::from_fn(|k| m["global_orient"].data[t * 3 + k]), &pose, &betas, std::array::from_fn(|k| m["transl"].data[t * 3 + k])).0
    };
    let mut world = Vec::new();
    let mut local = Vec::new();
    let mut root = Vec::new();
    for t in 0..l {
        let (ja, jb) = (joints(&ma, t), joints(&mb, t));
        root.push(geom::norm(geom::sub(ja[0], jb[0])));
        for j in 0..22 {
            world.push(geom::norm(geom::sub(ja[j], jb[j])));
            local.push(geom::norm(geom::sub(geom::sub(ja[j], ja[0]), geom::sub(jb[j], jb[0]))));
        }
    }
    let stats = |name: &str, mut v: Vec<f64>| {
        v.sort_by(|x, y| x.partial_cmp(y).unwrap());
        println!("{name:>26}: median {:.4} p95 {:.4} max {:.4}", v[v.len() / 2], v[v.len() * 95 / 100], v[v.len() - 1]);
    };
    println!("frames {l}");
    stats("joint world m", world);
    stats("joint root-relative m", local);
    stats("root drift m", root);
    Ok(())
}

/// `vo-test <video> [px per frame]`: synthetic pan (a window sliding over the first frame) —
/// the estimated yaw per 8-frame sample should equal atan(8·px / f).
fn vo_test(args: &[String]) -> Result<(), String> {
    let video_path = Path::new(args.first().ok_or("video")?);
    let px: usize = args.get(1).and_then(|v| v.parse().ok()).unwrap_or(2);
    let info = video::probe(video_path)?;
    let mut reader = video::Reader::open(video_path, &info, 0.5)?;
    let mut frame = Vec::new();
    reader.next(&mut frame)?;
    let (w, h) = (reader.width, reader.height);
    drop(reader);
    let (cw, ch) = (w * 3 / 4, h * 3 / 4);
    let f = ((cw * cw + ch * ch) as f64).sqrt() / (24f64 * 24. + 36. * 36.).sqrt() * 24.;
    let n = ((w - cw) / px).min(64);
    let window = |x0: usize| {
        let mut rgb = vec![0u8; cw * ch * 3];
        for y in 0..ch {
            rgb[y * cw * 3..(y + 1) * cw * 3].copy_from_slice(&frame[(y * w + x0) * 3..(y * w + x0 + cw) * 3]);
        }
        vo::Gray::from_rgb(&rgb, cw, ch)
    };
    for k in (8..n).step_by(8) {
        let (a, b) = (window((k - 8) * px), window(k * px));
        let (p0, p1) = vo::matches(&a, &b);
        let r = vo::relative_rotation(&p0, &p1, f, cw as f64 / 2., ch as f64 / 2., k as u64);
        let expect = ((8 * px) as f64 / f).atan().to_degrees();
        match r {
            Some((r, inl)) => {
                let aa = geom::matrix_to_aa(&r);
                println!("sample {k}: matches {} inliers {inl} rot (deg) [{:.3}, {:.3}, {:.3}] expected |yaw| {expect:.3}", p0.len(), aa[0].to_degrees(), aa[1].to_degrees(), aa[2].to_degrees());
            }
            None => println!("sample {k}: matches {} — not enough", p0.len()),
        }
    }
    Ok(())
}

/// Person detections for every frame of a video (full resolution).
fn detect_all(video_path: &Path, net: &yolo::Yolo, conf: f32) -> Result<(Vec<Vec<yolo::Det>>, video::Info), String> {
    let info = video::probe(video_path)?;
    let mut reader = video::Reader::open(video_path, &info, 1.)?;
    let mut frame = Vec::new();
    let mut out = Vec::new();
    while reader.next(&mut frame)? {
        out.push(net.detect(&frame, reader.width, reader.height, conf)?);
    }
    Ok((out, info))
}

/// `track-golden <video> <models> <preprocess dir> [--pair]`: YOLO + tracking vs the Python boxes.
fn track_golden(args: &[String]) -> Result<(), String> {
    let video_path = Path::new(args.first().ok_or("video")?);
    let models = Path::new(args.get(1).ok_or("models")?);
    let pre = Path::new(args.get(2).ok_or("preprocess dir")?);
    let pair = args.iter().any(|a| a == "--pair");
    let dev = device();
    let net = yolo::Yolo::load(&models.join("yolov8x.safetensors"), &dev)?;
    let t = Instant::now();
    let (dets, info) = detect_all(video_path, &net, if pair { 0.3 } else { 0.5 })?;
    println!("frames {} detect {:.1}s, persons/frame {:.2}", dets.len(), t.elapsed().as_secs_f64(), dets.iter().map(|d| d.len()).sum::<usize>() as f64 / dets.len() as f64);
    let report = |name: &str, mine: &[[f32; 4]], gold: &[f32]| {
        let mut v: Vec<f64> = mine.iter().enumerate().map(|(i, b)| yolo::iou(b, &[gold[i * 4], gold[i * 4 + 1], gold[i * 4 + 2], gold[i * 4 + 3]]) as f64).collect();
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!("{name:>8} IoU vs golden: min {:.3} p5 {:.3} median {:.3}", v[0], v[v.len() / 20], v[v.len() / 2]);
    };
    if pair {
        let p = track::pair(&dets, info.width as usize)?;
        println!("cover left {:.3} right {:.3}", p.cover_left, p.cover_right);
        for (role, boxes) in [("left", &p.left), ("right", &p.right)] {
            if let Ok((g, _)) = read_pt(&pre.join("tracks.pt"), role) {
                report(role, boxes, &g);
            }
        }
    } else {
        let main = track::single(&dets, info.width as usize, info.height as usize)?;
        let (g, _) = read_pt(&pre.join("bbx.pt"), "bbx_xyxy")?;
        report("single", &main, &g);
    }
    Ok(())
}

/// `vit-golden <preprocess dir> <video> <models dir> [frames]`: ViTPose keypoints and HMR2
/// features on the Python pipeline's boxes, compared with its vitpose.pt / vit_features.pt.
fn vit_golden(args: &[String]) -> Result<(), String> {
    let pre = Path::new(args.first().ok_or("preprocess dir")?);
    let video_path = Path::new(args.get(1).ok_or("video")?);
    let models = Path::new(args.get(2).ok_or("models dir")?);
    let limit: usize = args.get(3).and_then(|v| v.parse().ok()).unwrap_or(usize::MAX);
    let (bbx, _) = read_pt(&pre.join("bbx.pt"), "bbx_xys")?;
    let (gkp, _) = read_pt(&pre.join("vitpose.pt"), "")?;
    let (gfeat, _) = read_pt(&pre.join("vit_features.pt"), "")?;
    let dev = device();
    let t0 = Instant::now();
    let pose = vit::Weights::load(&models.join("vitpose.safetensors"), &dev, "ViTPose", &["backbone.", "keypoint_head."])?;
    let hmr = vit::Weights::load(&models.join("hmr2.safetensors"), &dev, "HMR2", &["backbone.", "smpl_head.transformer."])?;
    println!("load {:.1}s", t0.elapsed().as_secs_f64());
    let info = video::probe(video_path)?;
    let mut reader = video::Reader::open(video_path, &info, 0.5)?;
    let mut frame = Vec::new();
    let n = (bbx.len() / 3).min(limit);
    let mut crops: Vec<f32> = Vec::new();
    let mut kps: Vec<[[f32; 3]; 17]> = Vec::new();
    let mut feats: Vec<f32> = Vec::new();
    let t1 = Instant::now();
    let mut flush = |crops: &mut Vec<f32>, first: usize, kps: &mut Vec<[[f32; 3]; 17]>, feats: &mut Vec<f32>| -> Result<(), String> {
        let b = crops.len() / (3 * crop::H * crop::W);
        if b == 0 {
            return Ok(());
        }
        let x = vit::crops_tensor(crops, b, &dev)?;
        let heat = pose.vitpose(&x)?;
        for i in 0..b {
            let t = first + i;
            kps.push(vit::decode(&heat[i * 17 * 64 * 48..(i + 1) * 17 * 64 * 48], [bbx[t * 3] as f64, bbx[t * 3 + 1] as f64, bbx[t * 3 + 2] as f64]));
        }
        feats.extend(hmr.hmr2(&x)?);
        crops.clear();
        Ok(())
    };
    let mut first = 0;
    for t in 0..n {
        if !reader.next(&mut frame)? {
            return Err(format!("影片只有 {t} 幀，少於 {n}"));
        }
        let mut c = vec![0f32; 3 * crop::H * crop::W];
        crop::crop(&frame, reader.width, reader.height, bbx[t * 3] as f64, bbx[t * 3 + 1] as f64, bbx[t * 3 + 2] as f64, &mut c);
        crops.extend(c);
        if (t + 1) % 16 == 0 {
            flush(&mut crops, first, &mut kps, &mut feats)?;
            first = t + 1;
        }
    }
    flush(&mut crops, first, &mut kps, &mut feats)?;
    drop(reader);
    println!("frames {n} vitpose+hmr2 {:.1}s", t1.elapsed().as_secs_f64());
    let stats = |name: &str, mut v: Vec<f64>| {
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!("{name:>18}: median {:.4} p95 {:.4} max {:.4}", v[v.len() / 2], v[v.len() * 95 / 100], v[v.len() - 1]);
    };
    let mut pix = Vec::new();
    let mut conf = Vec::new();
    for t in 0..n {
        for j in 0..17 {
            let g = &gkp[(t * 17 + j) * 3..(t * 17 + j) * 3 + 3];
            pix.push((((kps[t][j][0] - g[0]).powi(2) + (kps[t][j][1] - g[1]).powi(2)) as f64).sqrt());
            conf.push((kps[t][j][2] - g[2]).abs() as f64);
        }
    }
    let mut worst: Vec<(f64, usize, usize)> = (0..n * 17).map(|i| (pix[i], i / 17, i % 17)).collect();
    worst.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
    for (d, t, j) in worst.iter().take(6) {
        let g = &gkp[(t * 17 + j) * 3..(t * 17 + j) * 3 + 3];
        println!("  frame {t} joint {j}: {d:.1}px mine {:?} golden {:?} box {:?}", kps[*t][*j], g, &bbx[t * 3..t * 3 + 3]);
    }
    stats("keypoint px", pix);
    stats("keypoint conf", conf);
    let cos: Vec<f64> = (0..n)
        .map(|t| {
            let a = &feats[t * 1024..(t + 1) * 1024];
            let b = &gfeat[t * 1024..(t + 1) * 1024];
            let d: f64 = a.iter().zip(b).map(|(x, y)| (*x as f64) * (*y as f64)).sum();
            let na: f64 = a.iter().map(|x| (*x as f64).powi(2)).sum::<f64>().sqrt();
            let nb: f64 = b.iter().map(|x| (*x as f64).powi(2)).sum::<f64>().sqrt();
            1. - d / (na * nb)
        })
        .collect();
    stats("feature 1-cos", cos);
    Ok(())
}

/// `gvhmr-golden <dir with preprocess/> <video> <motion.npz> <models dir> <SMPLX_NEUTRAL.npz> [--static]`:
/// runs GVHMR on the Python pipeline's cached inputs and compares with its motion.npz.
fn gvhmr_golden(args: &[String]) -> Result<(), String> {
    let pre = Path::new(args.first().ok_or("preprocess dir")?);
    let video = Path::new(args.get(1).ok_or("video")?);
    let golden = Path::new(args.get(2).ok_or("motion.npz")?);
    let models = Path::new(args.get(3).ok_or("models dir")?);
    let smplx = Path::new(args.get(4).ok_or("SMPLX_NEUTRAL.npz")?);
    let static_cam = args.iter().any(|a| a == "--static");
    let (bbx, _) = read_pt(&pre.join("bbx.pt"), "bbx_xys")?;
    let (kp, kshape) = read_pt(&pre.join("vitpose.pt"), "")?;
    let (feat, _) = read_pt(&pre.join("vit_features.pt"), "")?;
    let l = kshape[0];
    let (w, h) = video_size(video)?;
    let focal = ((w as f64).powi(2) + (h as f64).powi(2)).sqrt();
    let inp = gvhmr::Inputs {
        kp2d: (0..l).map(|t| std::array::from_fn(|j| std::array::from_fn(|c| kp[(t * 17 + j) * 3 + c]))).collect(),
        bbx_xys: (0..l).map(|t| [bbx[t * 3] as f64, bbx[t * 3 + 1] as f64, bbx[t * 3 + 2] as f64]).collect(),
        focal,
        cx: w as f64 / 2.,
        cy: h as f64 / 2.,
        cam_angvel: vec![[1., 0., 0., 0., 1., 0.]; l],
        imgseq: feat,
        static_cam,
    };
    if !static_cam {
        return Err("non-static golden needs slam results (not cached); use --static".into());
    }
    let dev = device();
    let t0 = Instant::now();
    let net = gvhmr::Network::load(&models.join("gvhmr.safetensors"), &dev)?;
    let skel = gvhmr::Skeleton::load(smplx)?;
    let t1 = Instant::now();
    let out = gvhmr::predict(&net, &skel, &inp)?;
    println!("frames {l} load {:.2}s predict {:.2}s", (t1 - t0).as_secs_f64(), t1.elapsed().as_secs_f64());
    let g = npy::read_npz(golden, &["global_orient", "body_pose", "transl", "betas"])?;
    let stats = |name: &str, mut v: Vec<f64>| {
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        println!("{name:>22}: median {:.5} p95 {:.5} max {:.5}", v[v.len() / 2], v[v.len() * 95 / 100], v[v.len() - 1]);
    };
    let ang = |a: geom::V3, b: geom::V3| {
        let m = geom::mul(&geom::aa_to_matrix(a), &geom::tr(&geom::aa_to_matrix(b)));
        geom::norm(geom::matrix_to_aa(&m)).to_degrees()
    };
    stats("global_orient deg", (0..l).map(|t| ang(out.global.global_orient[t], std::array::from_fn(|k| g["global_orient"].data[t * 3 + k]))).collect());
    stats("body_pose deg", (0..l).flat_map(|t| { let o = &out; let g = &g; (0..21).map(move |j| ang(o.global.body_pose[t][j], std::array::from_fn(|k| g["body_pose"].data[t * 63 + j * 3 + k]))) }).collect());
    stats("transl m", (0..l).map(|t| geom::norm(geom::sub(out.global.transl[t], std::array::from_fn(|k| g["transl"].data[t * 3 + k])))).collect());
    stats("betas", (0..10).map(|b| (out.global.betas[b] - g["betas"].data[b]).abs()).collect());
    let gb: [f64; 10] = std::array::from_fn(|b| g["betas"].data[b]);
    let mut jd = Vec::new();
    for t in 0..l {
        let mine = gvhmr::fk(&skel, out.global.global_orient[t], &out.global.body_pose[t], &out.global.betas, out.global.transl[t]).0;
        let pose: [geom::V3; 21] = std::array::from_fn(|j| std::array::from_fn(|k| g["body_pose"].data[t * 63 + j * 3 + k]));
        let theirs = gvhmr::fk(&skel, std::array::from_fn(|k| g["global_orient"].data[t * 3 + k]), &pose, &gb, std::array::from_fn(|k| g["transl"].data[t * 3 + k])).0;
        for j in 0..22 {
            jd.push(geom::norm(geom::sub(mine[j], theirs[j])));
        }
    }
    stats("joints m", jd);
    Ok(())
}

fn st_dtype(d: pickle::DType) -> safetensors::Dtype {
    use pickle::DType::*;
    match d {
        F32 => safetensors::Dtype::F32,
        F16 => safetensors::Dtype::F16,
        BF16 => safetensors::Dtype::BF16,
        F64 => safetensors::Dtype::F64,
        I64 => safetensors::Dtype::I64,
        I32 => safetensors::Dtype::I32,
        I16 => safetensors::Dtype::I16,
        I8 => safetensors::Dtype::I8,
        U8 => safetensors::Dtype::U8,
        Bool => safetensors::Dtype::U8, // candle has no bool; same bytes
    }
}

/// `weights list|convert <checkpoint> [out.safetensors] [--prefix p]`: names keep the
/// checkpoint's layout; `--prefix` keeps only that subtree and strips it.
fn weights(args: &[String]) -> Result<(), String> {
    let mode = args.first().map(String::as_str).unwrap_or("");
    let input = args.get(1).ok_or("缺少權重檔路徑")?;
    let prefix = args.iter().position(|a| a == "--prefix").and_then(|i| args.get(i + 1)).cloned().unwrap_or_default();
    if mode == "check" {
        // Load a converted cache onto the inference device and compare with the checkpoint.
        let dev = device();
        let t = Instant::now();
        let map = candle_core::safetensors::load(Path::new(input), &dev).map_err(|e| format!("{input}：{e}"))?;
        let values: usize = map.values().map(|t| t.elem_count()).sum();
        println!("{input}: {} tensors, {:.1} M values on {:?} in {:.1}s", map.len(), values as f64 / 1e6, dev, t.elapsed().as_secs_f64());
        return Ok(());
    }
    if mode == "describe" {
        print!("{}", pickle::describe(Path::new(input))?);
        return Ok(());
    }
    let mut ck = pickle::Checkpoint::open(Path::new(input))?;
    let keep: Vec<pickle::TensorInfo> = ck
        .tensors
        .iter()
        .filter(|t| prefix.is_empty() || t.name.starts_with(&format!("{prefix}.")))
        .cloned()
        .map(|mut t| {
            if !prefix.is_empty() {
                t.name = t.name[prefix.len() + 1..].to_string();
            }
            t
        })
        .collect();
    let params: usize = keep.iter().map(|t| t.numel()).sum();
    if mode == "list" {
        for t in &keep {
            println!("{} {:?} {:?}", t.name, t.dtype, t.shape);
        }
        println!("# {} tensors, {:.1} M values", keep.len(), params as f64 / 1e6);
        return Ok(());
    }
    let out = args.get(2).filter(|a| !a.starts_with("--")).ok_or("缺少輸出路徑")?;
    let mut data = Vec::with_capacity(keep.len());
    for t in &keep {
        data.push((t.name.clone(), t.dtype, t.shape.clone(), ck.bytes(t)?));
    }
    let views: Vec<(String, safetensors::tensor::TensorView)> = data
        .iter()
        .map(|(n, d, s, b)| (n.clone(), safetensors::tensor::TensorView::new(st_dtype(*d), s.clone(), b).unwrap()))
        .collect();
    safetensors::serialize_to_file(views, None, Path::new(out)).map_err(|e| format!("無法寫入 {out}：{e}"))?;
    println!("wrote {out}: {} tensors, {:.1} M values", keep.len(), params as f64 / 1e6);
    Ok(())
}

/// `flowhmr-golden <flowhmr.safetensors> <inputs.npz> <out.npz> [--steps N]`: runs the FlowHMR sampler
/// on reference inputs (`feature` (T,3072), `camera_R` (T,9), `noise` (T,491)) and writes `latent`
/// (T,491) plus the decoded `global_orient` / `body_pose` (axis-angle) and `pelvis`, for comparison
/// with the PyTorch implementation.
fn flowhmr_golden(args: &[String]) -> Result<(), String> {
    let (ck, inp, out) = match args {
        [a, b, c, ..] => (a, b, c),
        _ => return Err("用法：ok-video flowhmr-golden <flowhmr.safetensors> <inputs.npz> <out.npz> [--steps N]".into()),
    };
    let steps = args.iter().position(|a| a == "--steps").and_then(|i| args.get(i + 1)).and_then(|v| v.parse().ok()).unwrap_or(flowhmr::STEPS);
    let m = npy::read_npz(Path::new(inp), &["feature", "camera_R", "noise"])?;
    let f32s = |k: &str| m[k].data.iter().map(|v| *v as f32).collect::<Vec<f32>>();
    let dev = device();
    let net = flowhmr::Network::load(Path::new(ck), &dev)?;
    let t = Instant::now();
    let latent = net.sample(&f32s("feature"), &f32s("camera_R"), &f32s("noise"), steps, &|_| {})?;
    let l = latent.len() / flowhmr::LATENT;
    println!("sampled {l} frames, {steps} steps in {:.2}s", t.elapsed().as_secs_f64());
    let d = flowhmr::decode(&net, &latent)?;
    let flat3 = |v: &[[f64; 3]]| v.iter().flat_map(|a| a.iter().map(|x| *x as f32)).collect::<Vec<f32>>();
    let go = flat3(&d.global_orient);
    let bp: Vec<f32> = d.body_pose.iter().flat_map(|p| p.iter().flat_map(|a| a.iter().map(|x| *x as f32))).collect();
    let pel = flat3(&d.pelvis);
    npy::write_npz(
        Path::new(out),
        &[
            ("latent", npy::Out::F32(&latent, vec![l, flowhmr::LATENT])),
            ("global_orient", npy::Out::F32(&go, vec![l, 3])),
            ("body_pose", npy::Out::F32(&bp, vec![l, 63])),
            ("pelvis", npy::Out::F32(&pel, vec![l, 3])),
        ],
    )?;
    println!("wrote {out}");
    Ok(())
}

/// `sam3d-golden <sam3d_body.safetensors> <mhr.safetensors> <dump.npz> [--fp32]`: runs SAM 3D Body on
/// the frame / box / K of a reference dump (scratch sam_dump.py) and prints the largest difference of
/// each stage against the PyTorch values. `--fp32` runs the backbone in f32 (dump made with --fp32).
fn sam3d_golden(args: &[String]) -> Result<(), String> {
    let (ck, mhr, dump) = match args {
        [a, b, c, ..] => (a, b, c),
        _ => return Err("用法：ok-video sam3d-golden <sam3d_body.safetensors> <mhr.safetensors> <dump.npz> [--fp32]".into()),
    };
    let fp32 = args.iter().any(|a| a == "--fp32");
    let d = npy::read_npz(Path::new(dump), &[])?;
    let frame = &d["frame"];
    let (h, w) = (frame.shape[0], frame.shape[1]);
    let img: Vec<u8> = frame.data.iter().map(|v| *v as u8).collect();
    let b = &d["box"].data;
    let kd = &d["K"].data;
    let k: [f64; 9] = std::array::from_fn(|i| kd[i] as f32 as f64);
    let dev = device();
    let t = Instant::now();
    let model = sam3d::Model::load(Path::new(ck), Path::new(mhr), &dev, fp32)?;
    println!("loaded in {:.1}s", t.elapsed().as_secs_f64());
    let mut trace = sam3d::Trace::new();
    let t = Instant::now();
    let tok = model.tokens(&[&img], w, h, &[[b[0] as f32, b[1] as f32, b[2] as f32, b[3] as f32]], &k, Some(&mut trace))?;
    println!("tokens in {:.2}s", t.elapsed().as_secs_f64());
    trace.insert("tokens".into(), tok);
    // (mine, reference key, reference is channel-major (C, N) and mine is (N, C))
    let mut checks: Vec<(String, String, bool, usize)> = vec![
        ("body_img".into(), "body_img".into(), false, 0),
        ("backbone".into(), "backbone_out_0".into(), true, 0),
        ("ray".into(), "ray_cond_emb_out".into(), true, 0),
        ("decoder_out".into(), "decoder_out".into(), false, 0),
        ("hand_xyxy_0".into(), "left_xyxy".into(), false, 0),
        ("hand_xyxy_1".into(), "right_xyxy".into(), false, 0),
        ("hand_img_0".into(), "hand_img_0".into(), false, 0),
        ("backbone_hand".into(), "backbone_out_1".into(), true, 0),
        ("ray_hand".into(), "ray_cond_emb_hand_out_0".into(), true, 0),
        ("decoder_hand_out".into(), "decoder_hand_out_0".into(), false, 0),
        ("decoder_hand_out".into(), "decoder_hand_out_1".into(), false, 1),
        ("tokens".into(), "tokens".into(), false, 0),
    ];
    for l in 0..6 {
        checks.insert(3 + l, (format!("decoder_l{l}"), format!("decoder_l{l}"), false, 0));
        if l < 5 {
            checks.push((format!("params_l{l}"), format!("head_pose_params_{l}"), false, 0));
            checks.push((format!("kp3d_l{l}"), format!("head_pose_kp3d_{l}"), false, 0));
            checks.push((format!("kp3d_hand_l{l}"), format!("head_pose_hand_kp3d_{l}"), false, 0));
        }
        checks.push((format!("decoder_hand_l{l}"), format!("decoder_hand_l{l}_0"), false, 0));
    }
    for (mine, theirs, cmajor, item) in checks {
        let (Some(a), Some(r)) = (trace.get(&mine), d.get(&theirs)) else {
            println!("{mine:>18}: (missing {})", if trace.contains_key(&mine) { theirs } else { mine.clone() });
            continue;
        };
        let n = r.data.len();
        let a = &a[(item * n).min(a.len())..];
        let mut max = 0f64;
        let mut at = (0, 0., 0.);
        let mut scale = 0f64;
        let c = if cmajor { r.shape[r.shape.len() - 3] } else { 1 };
        let p = n / c;
        // Reference crops are ToTensor output; mine are normalized.
        let norm = theirs.contains("_img");
        for i in 0..n.min(a.len()) {
            let mut rv = if cmajor { r.data[(i % c) * p + i / c] } else { r.data[i] };
            if norm {
                let ch = i / (n / 3);
                rv = (rv - [0.485, 0.456, 0.406][ch]) / [0.229, 0.224, 0.225][ch];
            }
            if (a[i] as f64 - rv).abs() > max {
                max = (a[i] as f64 - rv).abs();
                at = (i, a[i] as f64, rv);
            }
            scale = scale.max(rv.abs());
        }
        println!("{mine:>18} vs {theirs:<26} max |Δ| {max:.3e} at {} ({:.5} vs {:.5})  (max |ref| {scale:.3e}, n {n})", at.0, at.1, at.2);
    }
    if let Some(out) = args.iter().position(|a| a == "--out").and_then(|i| args.get(i + 1)) {
        let arrays: Vec<(&str, npy::Out)> = trace.iter().map(|(k, v)| (k.as_str(), npy::Out::F32(v, vec![v.len()]))).collect();
        npy::write_npz(Path::new(out), &arrays)?;
        println!("wrote {out}");
    }
    Ok(())
}

fn device() -> Device {
    match Device::new_cuda(0) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("[警告] 找不到可用的 NVIDIA GPU（{e}），改用 CPU，速度約慢 50 倍");
            Device::Cpu
        }
    }
}

fn bench() -> candle_core::Result<()> {
    let dev = device();
    for (dtype, name) in [(DType::F32, "f32"), (DType::F16, "f16")] {
        let n = 4096;
        let a = Tensor::randn(0f32, 1., (n, n), &dev)?.to_dtype(dtype)?;
        let b = Tensor::randn(0f32, 1., (n, n), &dev)?.to_dtype(dtype)?;
        let _ = a.matmul(&b)?.sum_all()?.to_dtype(DType::F32)?.to_scalar::<f32>()?;
        let t = Instant::now();
        let iters = 20;
        let mut c = a.matmul(&b)?;
        for _ in 1..iters {
            c = a.matmul(&b)?;
        }
        let _ = c.sum_all()?.to_dtype(DType::F32)?.to_scalar::<f32>()?;
        let s = t.elapsed().as_secs_f64();
        println!("matmul {name} {n}x{n}: {:.1} TFLOPS on {:?}", 2. * (n as f64).powi(3) * iters as f64 / s / 1e12, dev);
    }
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let code = match args.get(1).map(String::as_str) {
        Some("weights") => weights(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("import") => match import(&args[2..]) {
            Ok(()) => 0,
            Err(e) => {
                // stdout only: the editor reads stdout and stderr through one pipe.
                for line in e.lines() {
                    println!("[錯誤] {line}");
                }
                2
            }
        },
        Some("compare-motion") => compare_motion(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("vo-test") => vo_test(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("track-golden") => track_golden(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("vit-golden") => vit_golden(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("gvhmr-golden") => gvhmr_golden(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("sam3d-golden") => sam3d_golden(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("flowhmr-golden") => flowhmr_golden(&args[2..]).map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        Some("bench") => bench().map(|_| 0).unwrap_or_else(|e| {
            eprintln!("[錯誤] {e}");
            1
        }),
        _ => {
            eprintln!("usage: ok-video bench | weights list|convert <checkpoint> [out.safetensors] [--prefix p]");
            2
        }
    };
    std::process::exit(code);
}
