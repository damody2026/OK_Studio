//! Face blendshapes of the open: mouth pattern pairs, runtime mouth channels and the neutral/default FBS weights.
use super::*;

/// `FBSCtrlMouth` `PtnSet` for the mouth target meshes, transcribed from the
/// vanilla head prefab (`bo_head_00.unity3d`, see dump `face_blendshape.json`).
/// For each pattern the pair is `(close, open)` blendshape indices; the mouth
/// blends between them with `FBSCtrlMouth.CalcBlend(openRate)`
/// (`FBSBase.CalculateBlendShape`: close = 100 - open*100, open = open*100).
pub(crate) fn mouth_ptn_pair(mesh_name: &str, ptn: usize) -> Option<(i32, i32)> {
    let n = mesh_name.to_ascii_lowercase();
    let (close, open): (&[i32], &[i32]) = if n.contains("cf_o_face") {
        (&[28, 31, 32, 31, 31], &[29, 30, 33, 34, 35])
    } else if n.contains("cf_o_noseline") {
        (&[25, 28, 29, 28, 28], &[26, 27, 30, 31, 32])
    } else if n.contains("cf_o_tooth") {
        (&[0, 0, 4, 0, 0], &[1, 2, 5, 6, 7])
    } else if n.contains("cf_o_canine") {
        (&[0, 0, 4, 0, 0], &[1, 2, 5, 6, 7])
    } else if n.contains("o_tang") {
        (&[0, 3, 4, 3, 3], &[1, 2, 5, 6, 7])
    } else {
        return None;
    };
    match (close.get(ptn), open.get(ptn)) {
        (Some(&c), Some(&o)) => Some((c, o)),
        _ => None,
    }
}

/// Live CPU mouth baseline is the loaded controller's pattern-0 closed pair;
/// GPU mouth morphs start raw. Channels outside this controller stay unowned.
pub(crate) fn runtime_mouth_channel_weights(channel_count: usize, patterns: &[(i32,i32)], raw_gpu: bool) -> Vec<Option<f32>> {
    let mut weights=vec![None;channel_count];
    for &(close,open) in patterns {
        for index in [close,open] { if index>=0 { if let Some(w)=weights.get_mut(index as usize) { *w=Some(0.0); } } }
    }
    if !raw_gpu {
        if let Some(&(close,_))=patterns.first() {
            if close>=0 { if let Some(w)=weights.get_mut(close as usize) { *w=Some(100.0); } }
        }
    }
    weights
}

#[cfg(test)]
#[test]
pub(crate) fn live_mouth_baseline_uses_authored_controller_indices() {
    // Unknown channel names are immaterial: the controller defines the set.
    // Include reordered channels, a shared close/open and a missing close.
    let patterns=[(3,1),(5,2),(7,7),(-1,0)];
    assert_eq!(runtime_mouth_channel_weights(8,&patterns,false),
        vec![Some(0.),Some(0.),Some(0.),Some(100.),None,Some(0.),None,Some(0.)]);
    assert_eq!(runtime_mouth_channel_weights(8,&patterns,true),
        vec![Some(0.),Some(0.),Some(0.),Some(0.),None,Some(0.),None,Some(0.)]);
    assert_eq!(runtime_mouth_channel_weights(4,&[(2,2)],false),
        vec![None,None,Some(100.),None]);
    assert_eq!(runtime_mouth_channel_weights(3,&[(-1,1),(8,-1)],false),
        vec![None,Some(0.),None]);
    assert_eq!(runtime_mouth_channel_weights(0,&patterns,false),Vec::<Option<f32>>::new());
}

pub(crate) struct HeadFbsInput<'a> {
    pub(crate) mouth: Option<&'a [(i32,i32)]>,
    pub(crate) eyes: Option<&'a [(i32,i32)]>,
    pub(crate) eyebrow: Option<&'a [(i32,i32)]>,
}

/// FBSBase.CalculateBlendShape clears every referenced channel then accumulates
/// the selected pair, including shared Close/Open indices and the -1 sentinel.
pub(crate) fn controller_neutral_weights(channel_count: usize, patterns: &[(i32,i32)], open: f32) -> Vec<Option<f32>> {
    let mut weights = runtime_mouth_channel_weights(channel_count, patterns, true);
    let percent = fbs_integer_open_percent(open);
    if let Some(&(close, opened)) = patterns.first() {
        for (index, value) in [(close, 100-percent), (opened, percent)] {
            if index >= 0 {
                if let Some(Some(weight)) = weights.get_mut(index as usize) {
                    *weight += value as f32;
                }
            }
        }
    }
    weights
}

pub(crate) fn head_neutral_weights(channel_count: usize, input: &HeadFbsInput<'_>, eyes_open: f32, eyebrow_open: f32) -> Vec<Option<f32>> {
    let mut weights = vec![None; channel_count];
    // FaceBlendShape.LateUpdate evaluates Eyebrow before Eyes; a shared channel
    // is overwritten by the later controller, not added across controllers.
    for (patterns, open) in [
        (input.eyebrow, eyebrow_open),
        (input.eyes, eyes_open),
    ] {
        if let Some(patterns) = patterns {
            for (destination, source) in weights.iter_mut().zip(controller_neutral_weights(channel_count, patterns, open)) {
                if source.is_some() { *destination = source; }
            }
        }
    }
    weights
}

#[cfg(test)]
#[test]
pub(crate) fn neutral_controller_indices_support_custom_mod_channels() {
    assert_eq!(controller_neutral_weights(8,&[(3,1),(5,2),(7,7),(-1,0)],0.61337),
        vec![Some(0.),Some(61.),Some(0.),Some(39.),None,Some(0.),None,Some(0.)]);
    assert_eq!(controller_neutral_weights(4,&[(2,2)],0.92),vec![None,None,Some(100.),None]);
    assert_eq!(controller_neutral_weights(3,&[(-1,1)],0.92),vec![None,Some(92.),None]);
    assert_eq!(controller_neutral_weights(3,&[(1,-1)],0.92),vec![None,Some(8.),None]);
    // Geometric effect uses indices, not the renamed channel labels. Channel 1
    // would have been missed entirely by the former _def_op name heuristic.
    let weights = controller_neutral_weights(2,&[(0,1)],0.92);
    let deltas = [[1.,0.,0.],[0.,1.,0.]];
    let mut position=[0.;3];
    for (delta, weight) in deltas.iter().zip(weights) {
        for axis in 0..3 { position[axis] += delta[axis]*weight.unwrap_or(0.)/100.; }
    }
    assert_eq!(position,[0.08,0.92,0.]);
    let input=HeadFbsInput { mouth:None, eyes:Some(&[(0,1)]), eyebrow:Some(&[(1,2)]) };
    assert_eq!(head_neutral_weights(3,&input,0.92,0.61337),vec![Some(8.),Some(92.),Some(61.)]);
}

/// The weight (percent) apply_default_fbs bakes into each channel of a head
/// mesh; 0 where it bakes nothing. The live face subtracts exactly these as its
/// baseline, so a mouth baked open here is not opened a second time.
pub(crate) fn default_fbs_weights(mesh_name: &str, channels: &[&str], authored_fbs: Option<&HeadFbsInput<'_>>) -> Vec<f32> {
    let mut weights = vec![0.0f32; channels.len()];
    if std::env::var("OK_NOFBS").is_ok() || channels.is_empty() {
        return weights;
    }
    // Live GPU path still bakes eye/brow neutral into the bind mesh, but leaves
    // kuti_* for SetBlendShapeWeight. Dump + OK_SKELMESH without OK_GPU_SKIN
    // keeps the old skip.
    let gpu_skin = crate::profile::var("OK_GPU_SKIN").ok().as_deref() == Some("1");
    if crate::profile::var("OK_SKELMESH").ok().as_deref() == Some("1") && !gpu_skin {
        return weights;
    }
    // Head stays CPU-baked unless OK_HEAD_GPUSKIN. Skipping kuti then leaves
    // the mouth at the closed bind pose, because the editor morph path only
    // runs for skel_kind 1/2/3.
    let mouth_on_gpu = gpu_skin && crate::profile::var("OK_HEAD_GPUSKIN").is_ok();
    let authored_mouth = authored_fbs.and_then(|input| input.mouth);
    // Legacy OBJ preview mouth override. Live mouth baselines and head eye/brow
    // baselines below use authored controller indices, including custom names.
    let mouth = mouth_ptn_override().and_then(|ptn| mouth_ptn_pair(mesh_name, ptn));
    let mouth_open = mouth_open_percent();
    // Live mouth setters subtract the authored pattern-0 closed delta from
    // CPU vertices, then add the selected pair. GPU morph meshes stay raw.
    // Use the loaded controller's target indices, including mod channel names.
    let fallback = mouth_ptn_pair(mesh_name,0).map(|pair| vec![pair]);
    let live_weights = if gpu_skin {
        authored_mouth.or(fallback.as_deref()).map(|patterns|
            runtime_mouth_channel_weights(channels.len(),patterns,mouth_on_gpu))
    } else { None };
    let neutral_weights = authored_fbs.map(|input| head_neutral_weights(channels.len(),input,
        f32::from_bits(EYES_OPEN_MAX_BITS.load(std::sync::atomic::Ordering::Relaxed)),
        f32::from_bits(EYEBROW_OPEN_MAX_BITS.load(std::sync::atomic::Ordering::Relaxed))));
    for (i, name) in channels.iter().enumerate() {
        let weight = if let Some(weight) = live_weights.as_ref().and_then(|weights| weights[i]) {
            weight
        } else if let Some(weight) = neutral_weights.as_ref().and_then(|weights| weights[i]) {
            weight
        } else if mouth_on_gpu && name.to_ascii_lowercase().contains("kuti") {
            0.0
        } else if let Some((close, open)) = mouth {
            if name.to_ascii_lowercase().contains("kuti") {
                let idx = i as i32;
                if close == open && idx == close {
                    // close/open share a channel: the two weights sum.
                    100.0
                } else if idx == close {
                    100.0 - mouth_open
                } else if idx == open {
                    mouth_open
                } else {
                    0.0
                }
            } else {
                if authored_fbs.is_some() { 0.0 } else { neutral_fbs_weight(name) }
            }
        } else {
            if authored_fbs.is_some() { 0.0 } else { neutral_fbs_weight(name) }
        };
        weights[i] = weight.max(0.0);
    }
    weights
}

pub(crate) fn apply_default_fbs(mesh: &mut ExtractedMesh, authored_fbs: Option<&HeadFbsInput<'_>>) {
    if std::env::var("OK_FBS_DIAG").is_ok() {
        let sample: Vec<_> = mesh
            .blend_shapes
            .iter()
            .filter(|(n, _)| n.contains("kuti") || mesh.name.eq_ignore_ascii_case("cf_Ohitomi_L"))
            .map(|(n, d)| format!("{n}:{}", d.len()))
            .collect();
        eprintln!(
            "ok-extract: FBS {} channels={} sample={:?}",
            mesh.name,
            mesh.blend_shapes.len(),
            sample
        );
    }
    let names: Vec<&str> = mesh.blend_shapes.iter().map(|(name, _)| name.as_str()).collect();
    let weights = default_fbs_weights(&mesh.name, &names, authored_fbs);
    let n = mesh.positions.len();
    let mut touched = 0usize;
    let mut maxd = 0.0f32;
    for ((_, deltas), &w) in mesh.blend_shapes.iter().zip(&weights) {
        if w <= 0.0 {
            continue;
        }
        let f = w / 100.0;
        for (idx, d) in deltas {
            let i = *idx as usize;
            if i < n {
                mesh.positions[i][0] += d[0] * f;
                mesh.positions[i][1] += d[1] * f;
                mesh.positions[i][2] += d[2] * f;
                touched += 1;
                maxd = maxd.max((d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt() * f);
            }
        }
    }
    if std::env::var("OK_FBS_DIAG").is_ok() {
        eprintln!("ok-extract: FBS APPLY {} touched={touched} maxd={maxd:.4}", mesh.name);
    }
}

/// Exact controller OpenMax bits, after ChaControl's separate status/controller
/// clamps. Set before meshes are emitted; names do not determine source channels.
pub(crate) static EYES_OPEN_MAX_BITS: std::sync::atomic::AtomicU32 =
    std::sync::atomic::AtomicU32::new(0.92f32.to_bits());
pub(crate) static EYEBROW_OPEN_MAX_BITS: std::sync::atomic::AtomicU32 =
    std::sync::atomic::AtomicU32::new(1.0f32.to_bits());

/// ChaControl.ChangeEyesOpenMax keeps status in [0,1], but the actual FBS
/// controller's OpenMax is clamped separately to [0,.92]. Do not change the
/// stored card value or confuse this with the blink/gaze correction stage.
pub(crate) fn eye_controller_open_max(status: f32) -> f32 {
    status.clamp(0.0,0.92)
}

pub(crate) fn neutral_fbs_weight(name: &str) -> f32 {
    // FaceBlendShape pattern 0 blends each control between its `_def_cl` and
    // `_def_op` targets; the weights sum to 100. The dump at rest shows:
    //   mouth  (`kuti_*`)      `_cl`=100 `_op`=0   (closed)
    //   eyes   (`siro*`, line) source-clamped OpenMax (default .92)
    //   brows  (`mayuge*`)     `_cl`=0   `_op`=100 (always fully "open")
    let n = name.to_ascii_lowercase();
    let is_mouth = n.contains("kuti");
    let is_brow = n.contains("mayuge") || n.contains("mayu");
    let open = if is_mouth {
        0.0
    } else if is_brow {
        f32::from_bits(EYEBROW_OPEN_MAX_BITS.load(std::sync::atomic::Ordering::Relaxed))
    } else {
        f32::from_bits(EYES_OPEN_MAX_BITS.load(std::sync::atomic::Ordering::Relaxed))
    };
    if let Ok(v) = std::env::var("OK_FBS_DEFCL") {
        if n.ends_with("_def_cl") && !is_mouth {
            if let Ok(f) = v.parse::<f32>() {
                return f;
            }
        }
    }
    let percent = fbs_integer_open_percent(open);
    if n.ends_with("_def_cl") {
        (100 - percent) as f32
    } else if n.ends_with("_def_op") {
        percent as f32
    } else {
        0.0
    }
}

pub(crate) fn fbs_integer_open_percent(open: f32) -> i32 {
    (open.clamp(0.0,1.0)*100.0) as i32
}

#[cfg(test)]
#[test]
pub(crate) fn neutral_fbs_integer_percent_matches_native() {
    assert_eq!(fbs_integer_open_percent(0.926),92);
    assert_eq!(fbs_integer_open_percent(0.61337),61);
    assert_eq!(fbs_integer_open_percent(0.00999),0);
    assert_eq!(fbs_integer_open_percent(0.91999),91);
    assert_eq!(fbs_integer_open_percent(1.0),100);
    assert_eq!(fbs_integer_open_percent(-1.0),0);
    assert_eq!(fbs_integer_open_percent(2.0),100);
    // ChangeEyesOpenMax clamps the controller before FBSBase quantization.
    assert_eq!(eye_controller_open_max(1.0),0.92);
    assert_eq!(eye_controller_open_max(2.0),0.92);
    assert_eq!(eye_controller_open_max(-1.0),0.0);
    assert_eq!(eye_controller_open_max(0.61337),0.61337);
    assert_eq!(fbs_integer_open_percent(eye_controller_open_max(1.0)),92);
    assert_eq!(fbs_integer_open_percent(eye_controller_open_max(0.91999)),91);
}

/// Her tears (Docs/H_DEVELOPMENT_EXPERIENCE_PLAN.md P2): from `from` (her skeleton space, Unity metres) a path down her
/// face as she is posed now, each step `step` metres along `down` laid flat on her skin there and kept `lift` metres
/// off it. The points and her skin's normal at each; it ends where her face does (no face vertex within 1.5 cm).
pub fn tear_path(session: &crate::session::OkSession, from: [f32; 3], down: [f32; 3], step: f32, lift: f32, count: usize) -> Vec<([f32; 3], [f32; 3])> {
    // Her face is skinned on her head's skeleton, which sits on her body's head bone (crate::head_onto_body).
    let Some(part) = session.parts.iter().find(|p| p.name.eq_ignore_ascii_case("cf_O_face")) else { return Vec::new() };
    let body = session.body_skel.as_ref();
    let skel = match part.skel_kind { 2 => session.head_full_posed.as_ref().or(session.head_skel.as_ref()), _ => body };
    let Some(skel) = skel else { return Vec::new() };
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return Vec::new(); }
    let onto = if part.skel_kind == 2 { crate::head_onto_body(body, Some(skel)) } else { crate::pose::ident() };
    let pal: Vec<crate::pose::Mat4> = worlds.iter().zip(&binds).map(|(w, b)| crate::pose::mat_mul_pub(&onto, &crate::pose::mat_mul_pub(w, b))).collect();
    let apply = |m: &crate::pose::Mat4, p: [f32; 3], w: f32| -> [f32; 3] { std::array::from_fn(|i| m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] * w) };
    let len = |v: [f32; 3]| (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    // Her face as posed: each vertex and its normal skinned by its bones.
    let face: Vec<([f32; 3], [f32; 3])> = (0..part.rest_positions.len()).filter_map(|j| {
        let (b, w) = (part.bone_idx.get(j)?, part.weights.get(j)?);
        let (mut p, mut n) = ([0f32; 3], [0f32; 3]);
        for (b, w) in b.iter().zip(w) {
            let Some(m) = pal.get(*b as usize) else { continue };
            if *w <= 0. { continue; }
            let (q, r) = (apply(m, part.rest_positions[j], 1.), apply(m, *part.rest_normals.get(j)?, 0.));
            for c in 0..3 { p[c] += q[c] * w;n[c] += r[c] * w; }
        }
        let l = len(n);if l < 1e-6 { return None; }
        Some((p, [n[0] / l, n[1] / l, n[2] / l]))
    }).collect();
    // Where a point lies on her face: the nearest four vertices, nearer counting more.
    let near = |a: [f32; 3]| -> Option<([f32; 3], [f32; 3])> {
        let mut best = [(f32::MAX, 0usize); 4];
        for (i, (p, _)) in face.iter().enumerate() {
            let d = (0..3).map(|c| (a[c] - p[c]) * (a[c] - p[c])).sum::<f32>();
            if d < best[3].0 { let mut k = 3;while k > 0 && best[k - 1].0 > d { best[k] = best[k - 1];k -= 1; }best[k] = (d, i); }
        }
        if best[0].0 > 0.015 * 0.015 { return None; }
        let (mut p, mut n, mut sum) = ([0f32; 3], [0f32; 3], 0f32);
        for &(d, i) in best.iter().filter(|(d, _)| *d < f32::MAX) {
            let w = 1. / (d.sqrt() + 0.001);sum += w;
            for c in 0..3 { p[c] += face[i].0[c] * w;n[c] += face[i].1[c] * w; }
        }
        let l = len(n);if l < 1e-6 { return None; }
        Some(([p[0] / sum, p[1] / sum, p[2] / sum], [n[0] / l, n[1] / l, n[2] / l]))
    };
    let mut out = Vec::with_capacity(count);
    let mut at = from;
    for _ in 0..count {
        let Some((p, n)) = near(at) else { break };
        out.push(([p[0] + n[0] * lift, p[1] + n[1] * lift, p[2] + n[2] * lift], n));
        // Down her skin: the way down with the part into her skin taken out.
        let dn = down[0] * n[0] + down[1] * n[1] + down[2] * n[2];
        let t = [down[0] - n[0] * dn, down[1] - n[1] * dn, down[2] - n[2] * dn];
        let l = len(t);if l < 0.2 { break; } // her skin faces up or down there: the tear stops
        at = [p[0] + t[0] / l * step, p[1] + t[1] / l * step, p[2] + t[2] / l * step];
    }
    out
}
