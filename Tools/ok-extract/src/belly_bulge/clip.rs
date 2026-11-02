//! His penis out through her back not drawn (user, 2026-11-02: "背部要直接把超出的部分不顯示"; her belly bones only lift
//! her belly, and in 後背位 and 椅子後入 his glans came out of her lower back). `back_exit` finds where the line from her
//! entrance to his glans last leaves her body through skin facing away from her belly; `clip_deltas` folds what of his
//! penis lies past that skin back onto a plane `CLIP_IN_M` under it, as the morph `CLIP` of his penis, so it is hidden in her.
use super::*;

/// The empty morph his penis carries so the scene can move it each frame (its renderer gets a morph slot only with one).
pub const CLIP: &str = "penis.clip";
/// How far under her skin his penis is folded, and how near her entrance a crossing is still her opening.
const CLIP_IN_M: f32 = 0.01;
const EXIT_FROM_M: f32 = 0.04;
/// How far before the crossing (along him) his penis may be folded: only the part past it, never his shaft at her entrance.
const CLIP_BEFORE_M: f32 = 0.04;
/// Her skin facing her belly's way more than this (cosine) is her belly, lifted by her belly bones instead; less is her back,
/// her sides and the cleft of her bottom (its walls face sideways: his glans out of the top of her bottom, 後背位).
const BELLY_COS: f32 = 0.4;

/// Her body's skin, posed now: position and outward normal of each vertex (None where it has no skin).
fn posed_body(part: &SessionPart, worlds: &[Mat4], binds: &[Mat4]) -> Vec<Option<([f32; 3], [f32; 3])>> {
    (0..part.rest_positions.len()).map(|j| {
        let (m, _, _) = skin_of(part, j, worlds, binds, &[], &[])?;
        let p = point(&m, part.rest_positions[j]);let o = point(&m, [0.; 3]);
        let q = point(&m, *part.rest_normals.get(j)?);let n = [q[0] - o[0], q[1] - o[1], q[2] - o[2]];
        let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if l < 1e-6 { return None; }
        Some((p, [n[0] / l, n[1] / l, n[2] / l]))
    }).collect()
}

/// Where the line from `from` (her entrance) to `to` (his glans) last leaves her body (her skeleton space, Unity metres)
/// past `EXIT_FROM_M`, if that skin is not her belly (faces `up`, the way her belly faces, less than `BELLY_COS`): the place and her skin's outward normal
/// there. None when he stays in her or comes out on her belly side.
pub fn back_exit(session: &OkSession, from: [f32; 3], to: [f32; 3], up: [f32; 3]) -> Option<([f32; 3], [f32; 3])> {
    let skel = session.body_skel.as_ref()?;
    let part = session.parts.iter().find(|p| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none() && p.blend_shapes.iter().any(|(n, _)| is_bulge(n)))?;
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return None; }
    let sub = |a: [f32; 3], b: [f32; 3]| [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let cross = |a: [f32; 3], b: [f32; 3]| [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
    let line = sub(to, from);let len = dot(line, line).sqrt();
    if len <= EXIT_FROM_M || dot(up, up) < 1e-12 { return None; }
    let dir = [line[0] / len, line[1] / len, line[2] / len];
    let skin = posed_body(part, &worlds, &binds);
    let mut best: Option<(f32, [f32; 3])> = None;
    for t in part.indices.chunks_exact(3) {
        let (Some((a, na)), Some((b, nb)), Some((c, nc))) = (skin[t[0] as usize], skin[t[1] as usize], skin[t[2] as usize]) else { continue; };
        // Möller–Trumbore, the line both ways.
        let (e1, e2) = (sub(b, a), sub(c, a));let h = cross(dir, e2);let det = dot(e1, h);
        if det.abs() < 1e-12 { continue; }
        let s = sub(from, a);let u = dot(s, h) / det;if !(0. ..=1.).contains(&u) { continue; }
        let q = cross(s, e1);let v = dot(dir, q) / det;if v < 0. || u + v > 1. { continue; }
        let d = dot(e2, q) / det;
        if d < EXIT_FROM_M || d > len || best.is_some_and(|(b, _)| b >= d) { continue; }
        let w = 1. - u - v;let n = [na[0] * w + nb[0] * u + nc[0] * v, na[1] * w + nb[1] * u + nc[1] * v, na[2] * w + nb[2] * u + nc[2] * v];
        best = Some((d, n));
    }
    // The last of her skin before his glans: where it is left out of her (her skin facing the way he goes), he is out
    // there; going back in, his glans is in her. Not the first crossing: inside, the folds of her bottom's cleft and her
    // own inner skin faced her belly, and his glans out of the top of her bottom was missed (後背位, root pad (0,3)).
    let (d, n) = best?;
    if dot(n, dir) <= 0. { return None; }
    let l = dot(n, n).sqrt();let n = [n[0] / l, n[1] / l, n[2] / l];
    (dot(n, up) < BELLY_COS).then(|| ([from[0] + dir[0] * d, from[1] + dir[1] * d, from[2] + dir[2] * d], n))
}

/// His penis past her skin folded under it (his skeleton space, Unity metres): `at` where he comes out of her, `normal`
/// her skin's outward normal there, `axis` the way his penis points. Each vertex of his penis past the plane `CLIP_IN_M`
/// under her skin (and past `CLIP_BEFORE_M` before `at` along him) goes back along him onto that plane, as morph deltas
/// of his penis part (vertex index, move in the mesh's own space, then no turn of its normal). `inset` metres more under her
/// skin: the morph is drawn a frame or two after his pose is read, and a fast thrust carries him that much further out.
pub fn clip_deltas(session: &OkSession, at: [f32; 3], normal: [f32; 3], axis: [f32; 3], inset: f32) -> Vec<(u32, [f32; 6])> {
    let Some(skel) = session.body_skel.as_ref() else { return Vec::new(); };
    let Some(part) = session.parts.iter().find(|p| crate::head_body::is_penis_mesh(&p.name)) else { return Vec::new(); };
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return Vec::new(); }
    let sub = |a: [f32; 3], b: [f32; 3]| [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let unit = |v: [f32; 3]| { let l = dot(v, v).sqrt();if l < 1e-6 { None } else { Some([v[0] / l, v[1] / l, v[2] / l]) } };
    let (Some(n), Some(a)) = (unit(normal), unit(axis)) else { return Vec::new(); };
    let inset = CLIP_IN_M + inset.max(0.);
    let plane = [at[0] - n[0] * inset, at[1] - n[1] * inset, at[2] - n[2] * inset];
    // Back along him onto the plane; where he lies almost along her skin, the rest straight down onto it.
    let along = dot(a, n).max(0.3);
    let mut out = Vec::new();
    for j in 0..part.rest_positions.len() {
        let Some((m, _, _)) = skin_of(part, j, &worlds, &binds, &[], &[]) else { continue; };
        let p = point(&m, part.rest_positions[j]);
        let past = dot(sub(p, plane), n);
        if past <= 0. || dot(sub(p, at), a) < -(CLIP_BEFORE_M + inset) { continue; }
        let s = past / along;let mut q = [p[0] - a[0] * s, p[1] - a[1] * s, p[2] - a[2] * s];
        let rest = dot(sub(q, plane), n);if rest > 0. { q = [q[0] - n[0] * rest, q[1] - n[1] * rest, q[2] - n[2] * rest]; }
        let inv = mat_inv_pub(&m);let (x, y) = (point(&inv, q), point(&inv, p));
        out.push((j as u32, [x[0] - y[0], x[1] - y[1], x[2] - y[2], 0., 0., 0.]));
    }
    out
}

/// His penis given the empty morph `CLIP` (his body only), so it can be folded each frame. True when added.
pub fn add_clip_morph(session: &mut OkSession) -> bool {
    let Some(part) = session.parts.iter_mut().find(|p| crate::head_body::is_penis_mesh(&p.name)) else { return false; };
    if part.rest_positions.is_empty() || part.blend_shapes.iter().any(|(n, _)| n.to_bytes() == CLIP.as_bytes()) { return false; }
    // One vertex moved a hair: a morph with no moves may be dropped on the way to the renderer.
    let deltas = vec![(0u32, [0f32, 0., 1e-6])];
    part.morph_idx.push(deltas.iter().map(|(i, _)| *i).collect());
    part.morph_dxyz.push(deltas.iter().flat_map(|(_, d)| *d).collect());
    part.blend_shapes.push((std::ffi::CString::new(CLIP).unwrap(), deltas));
    session.skel_export = None;
    true
}
