//! Belly bulge morphs for the H scene: where his penis presses out through her belly (or her back) the game swells
//! the skin there instead of letting it come through. Made once on opening a female body: a grid of round swells
//! "belly.bulge.<side><height><across>", on her front, back, left and right (f b l r), at six heights on her belly, from just over her
//! crotch to her upper spine and three places across that side (front and back: her
//! middle and her groins 5.5 cm to each side; left and right: 5 cm before and behind her middle), each `BULGE_M` out
//! along the skin at weight 100. The scene asks `past` where his glans is against her skin now and drives
//! the one swell that moves that skin most (UOKHScenePanel::BulgeBelly). Skin on her breasts, arms, head and lower legs
//! stays, and so does skin on her thighs.
use crate::pose::{mat_inv_pub, mat_mul_pub, Mat4};
use crate::session::{OkSession, SessionPart};
use std::collections::HashMap;
mod bones;
pub use bones::bone_deltas;
mod clip;
pub use clip::{back_exit, clip_deltas};
mod cover;
pub use cover::{cover_deltas, keep_cover, set_cover, CoverField};
pub(crate) use cover::clothes_changed;

/// Where the swells are along her crotch-to-upper-spine line (fractions of it): her belly only, from just over her
/// crotch up (user 2026-11-01: the swells under it, on her upper thighs and by her entrance, moved her thighs).
const HEIGHTS: [f32; 6] = [0.05, 0.15, 0.25, 0.35, 0.46, 0.58];
/// Where across her front and back (metres from her middle), and across her sides (metres before her middle).
const ACROSS: [f32; 3] = [-0.055, 0.0, 0.055];
const ALONG_SIDE: [f32; 3] = [-0.05, 0.0, 0.05];
/// Her sides: front, back, left, right, with the way each faces (she faces +z, her left is +x).
const SIDES: [(char, [f32; 2]); 4] = [('f', [0., 1.]), ('b', [0., -1.]), ('l', [1., 0.]), ('r', [-1., 0.])];
/// How far the skin moves at weight 100 (Unity metres), and how wide a swell is (one standard deviation): a glans 8 cm
/// out of a thin girl's belly made a 4 cm wide one a pillar.
pub const BULGE_M: f32 = 0.14;
const ROUND_M: f32 = 0.055;
/// How near her entrance (cf_j_kokan, bind pose) the skin never swells, and over how much further it comes in.
const NEAR_ENTRANCE_M: f32 = 0.05;
const ENTRANCE_FADE_M: f32 = 0.05;
/// How far around a place its normal is averaged for the way it moves (a navel is about 1 cm across).
const SMOOTH_M: f32 = 0.03;
/// Bones whose skin never swells (part of a name): a straight clip leaves her low, at the groin, where the skin is on
/// her waist and thigh bones, so those are not limited. Her own hidden penis mesh (dan bones) is not her skin.
const STILL: [&str; 12] = ["bust", "arm", "hand", "head", "neck", "shoulder", "leg02", "leg03", "foot", "toe", "knee", "dan"];
/// Her thighs (part of a name): their skin never swells. A swell made with her legs straight moved her thighs with it
/// once they were drawn up over her belly or spread by her entrance (大張腿, 抬腿朝天; user 2026-11-01, plain from the
/// front), even at her groin.
const THIGH: [&str; 2] = ["thigh", "leg01"];
/// Her opening around him (user 2026-11-01: it opens and closes with him): the morph `OPEN` parts the skin at her
/// entrance to either side, `OPEN_M` at its middle at weight 100, fading over `OPEN_ROUND_M` around it. The scene drives it
/// with his stroke (UOKHScenePanel::BulgeBelly), on bodies without an opening of their own (`OWN_OPEN`; the BP bodies open
/// with their cf_J_Vagina bones instead).
pub const OPEN: &str = "kokan.open";
/// The opening some bodies carry themselves (the SAC uncensor bodies), used instead of `OPEN`.
pub const OWN_OPEN: &str = "vagina.open";
const OPEN_M: f32 = 0.011;
const OPEN_ROUND_M: f32 = 0.016;

fn point(m: &Mat4, p: [f32; 3]) -> [f32; 3] { std::array::from_fn(|i| m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3]) }
fn translation(m: &Mat4) -> [f32; 3] { [m[0][3], m[1][3], m[2][3]] }
fn is_bulge(n: &std::ffi::CString) -> bool { n.to_bytes().starts_with(b"belly.bulge.") }

/// The morph name on `side` (f b l r) at height `k` (0 lowest), place `across` (0..2 across that side).
pub fn name(side: char, k: usize, across: usize) -> String { format!("belly.bulge.{side}{k}{across}") }

/// The skin matrix of vertex `j` (palette blended by its weights) and how much of it is on bones that swell.
fn skin_of(part: &SessionPart, j: usize, worlds: &[Mat4], binds: &[Mat4], still: &[bool], thigh: &[bool]) -> Option<(Mat4, f32, f32)> {
    let (indices, weights) = (part.bone_idx.get(j)?, part.weights.get(j)?);
    let mut free = 1.0f32;let mut on_thigh = 0.0f32;
    let mut skin = [[0.0f32; 4]; 4];
    for (b, w) in indices.iter().zip(weights) {
        let b = *b as usize;if *w <= 0. || b >= worlds.len() { continue; }
        if still.get(b) == Some(&true) { free -= *w; }
        if thigh.get(b) == Some(&true) { on_thigh += *w; }
        let m = mat_mul_pub(&worlds[b], &binds[b]);
        for r in 0..4 { for c in 0..4 { skin[r][c] += m[r][c] * w; } }
    }
    Some((skin, free, on_thigh))
}

/// Adds the targets to her body part once; true when added (the skeleton export is then rebuilt with them).
pub fn add(session: &mut OkSession) -> bool {
    // Hers only (ChaFileParameter.sex 1): his body has the same cf_ bones, cf_j_kokan too. His penis gets the morph it is
    // folded into her with (clip.rs).
    if session.sex != 1 { return session.sex == 0 && clip::add_clip_morph(session); }
    let Some(rest) = crate::skel_export::bind_body(session) else { return false; };
    let at = |n: &str| rest.world_tf(n).map(|m| translation(&m));
    // Her crotch to her upper spine in the bind pose (she faces +z): the heights the swells are at.
    let (Some(kokan), Some(top)) = (at("cf_j_kokan").or_else(|| at("cf_J_Kokan")), at("cf_j_spine02")) else { return false; };
    let still: Vec<bool> = rest.names.iter().map(|n| { let n = n.to_ascii_lowercase(); STILL.iter().any(|s| n.contains(s)) }).collect();
    let thigh: Vec<bool> = rest.names.iter().map(|n| { let n = n.to_ascii_lowercase(); THIGH.iter().any(|s| n.contains(s)) }).collect();
    let mut added = false;
    for part in session.parts.iter_mut() {
        if part.role != "body" || part.skel_kind != 1 || part.runtime_accessory.is_some() { continue; }
        if part.blend_shapes.iter().any(|(n, _)| is_bulge(n)) { continue; }
        let (worlds, binds) = crate::skel_export::palettes(&rest, part);
        if worlds.is_empty() { continue; }
        // Each vertex in the bind pose with its skin matrix (to bring the moved point back into the mesh) and how free it is.
        struct Vert { j: usize, p: [f32; 3], n: [f32; 3], inv: Mat4, free: f32 }
        let mut verts = Vec::new();
        for j in 0..part.rest_positions.len() {
            let Some((skin, free, on_thigh)) = skin_of(part, j, &worlds, &binds, &still, &thigh) else { continue; };
            let p = point(&skin, part.rest_positions[j]);
            let free = free - on_thigh;
            if free <= 0.01 { continue; }
            let o = point(&skin, [0.; 3]);
            let n = part.rest_normals.get(j).map(|v| { let v = point(&skin, *v); [v[0] - o[0], v[1] - o[1], v[2] - o[2]] }).unwrap_or([0., 0., 1.]);
            verts.push(Vert { j, p, n, inv: mat_inv_pub(&skin), free });
        }
        // Vertices split along UV / normal seams share one place: one normal and one freedom for all of them, or the swell
        // tears open along the seams.
        let key = |p: [f32; 3]| p.map(|v| (v * 5000.).round() as i64);
        let mut weld: HashMap<[i64; 3], ([f32; 3], f32, f32)> = HashMap::new();
        for v in &verts {
            let len = (v.n[0] * v.n[0] + v.n[1] * v.n[1] + v.n[2] * v.n[2]).sqrt();if len < 1e-6 { continue; }
            let e = weld.entry(key(v.p)).or_insert(([0.; 3], 0., 0.));
            for i in 0..3 { e.0[i] += v.n[i] / len; }
            e.1 += v.free;e.2 += 1.;
        }
        // The way each place moves: its normal averaged over SMOOTH_M around it. A small hollow (her navel) then moves as
        // one with the skin around it; along their own normals its walls spread apart and opened it into a black hole.
        let places: Vec<([i64; 3], [f32; 3], [f32; 3])> = verts.iter().filter_map(|v| weld.get(&key(v.p)).map(|e| (key(v.p), v.p, e.0))).collect();
        let cell = |p: [f32; 3]| p.map(|v| (v / SMOOTH_M).floor() as i64);
        let mut grid: HashMap<[i64; 3], Vec<usize>> = HashMap::new();
        for (i, (_, p, _)) in places.iter().enumerate() { grid.entry(cell(*p)).or_default().push(i); }
        let mut smooth: HashMap<[i64; 3], [f32; 3]> = HashMap::new();
        for (k, p, _) in &places {
            if smooth.contains_key(k) { continue; }
            let c = cell(*p);let mut sum = [0f32; 3];
            for dx in -1..=1 { for dy in -1..=1 { for dz in -1..=1 {
                for &i in grid.get(&[c[0] + dx, c[1] + dy, c[2] + dz]).into_iter().flatten() {
                    let (_, q, n) = places[i];let d2 = (0..3).map(|a| (q[a] - p[a]) * (q[a] - p[a])).sum::<f32>();
                    if d2 > SMOOTH_M * SMOOTH_M { continue; }
                    let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if len < 1e-6 { continue; }
                    for a in 0..3 { sum[a] += n[a] / len; }
                }
            }}}
            smooth.insert(*k, sum);
        }
        let mut targets: Vec<(String, Vec<(u32, [f32; 3])>)> = Vec::new();
        for (side, way) in SIDES {
            for (k, h) in HEIGHTS.iter().enumerate() {
                for a in 0..3 {
                    // Front and back swells sit across her (x), side ones before and behind her middle (z, along the line up her).
                    let y = kokan[1] + (top[1] - kokan[1]) * h;
                    let (x, z) = (kokan[0] + ACROSS[a], kokan[2] + (top[2] - kokan[2]) * h + ALONG_SIDE[a]);
                    let mut deltas = Vec::new();
                    for v in &verts {
                        let (Some((_, free, count)), Some(sum)) = (weld.get(&key(v.p)), smooth.get(&key(v.p))) else { continue; };
                        let len = (sum[0] * sum[0] + sum[1] * sum[1] + sum[2] * sum[2]).sqrt();if len < 1e-6 { continue; }
                        let n = [sum[0] / len, sum[1] / len, sum[2] / len];let free = (free / count).min(1.);
                        // Facing out on that side; round across her (x) and along her (y).
                        let facing = n[0] * way[0] + n[2] * way[1];if facing < 0.15 { continue; }
                        let dx = (if way[0] == 0. { v.p[0] - x } else { v.p[2] - z }) / ROUND_M;let dy = (v.p[1] - y) / ROUND_M;
                        // Nothing by her entrance: the lowest swells reached her labia and groin and, at his deepest
                        // stroke, pulled that skin apart into a black hole (user, 2026-11-02, 後背位): none within
                        // NEAR_ENTRANCE_M of it, growing to full over the next ENTRANCE_FADE_M.
                        let e = ((0..3).map(|i| (v.p[i] - kokan[i]) * (v.p[i] - kokan[i])).sum::<f32>().sqrt() - NEAR_ENTRANCE_M) / ENTRANCE_FADE_M;
                        let clear = { let t = e.clamp(0., 1.); t * t * (3. - 2. * t) };
                        // That skin is still in the target, unmoved, outside NEAR_ENTRANCE_M: `past` then sees his
                        // penis come out of her lower belly there (user, 2026-11-02, 騎乘位) with nothing to swell, and
                        // the scene draws him back or turns him instead.
                        let reach = (-0.5 * (dx * dx + dy * dy)).exp() * facing.min(1.) * free;
                        if reach < 0.01 || e <= 0. { continue; }
                        let fall = reach * clear;
                        let moved = [v.p[0] + n[0] * BULGE_M * fall, v.p[1] + n[1] * BULGE_M * fall, v.p[2] + n[2] * BULGE_M * fall];
                        let local = point(&v.inv, moved);let base = part.rest_positions[v.j];
                        deltas.push((v.j as u32, [local[0] - base[0], local[1] - base[1], local[2] - base[2]]));
                    }
                    if !deltas.is_empty() { targets.push((name(side, k, a), deltas)); }
                }
            }
        }
        // Her entrance parted: each side of her middle (x) away from it, most at her entrance, nothing at her middle line.
        let mut open = Vec::new();
        for v in &verts {
            let d = [v.p[0] - kokan[0], v.p[1] - kokan[1], v.p[2] - kokan[2]];
            let r2 = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) / (OPEN_ROUND_M * OPEN_ROUND_M);if r2 > 9. { continue; }
            let side = (d[0] / 0.004).clamp(-1., 1.);
            let push = OPEN_M * (-0.5 * r2).exp() * side * v.free.min(1.);if push.abs() < 1e-5 { continue; }
            let local = point(&v.inv, [v.p[0] + push, v.p[1], v.p[2]]);let base = part.rest_positions[v.j];
            open.push((v.j as u32, [local[0] - base[0], local[1] - base[1], local[2] - base[2]]));
        }
        // A body with its own opening (SAC bodies: vagina.open) opens with that one, not this.
        let own = part.blend_shapes.iter().any(|(n, _)| n.to_bytes() == OWN_OPEN.as_bytes());
        if !own && !open.is_empty() { targets.push((OPEN.to_string(), open)); }
        for (target, deltas) in targets {
            part.morph_idx.push(deltas.iter().map(|(i, _)| *i).collect());
            part.morph_dxyz.push(deltas.iter().flat_map(|(_, d)| *d).collect());
            part.blend_shapes.push((std::ffi::CString::new(target).unwrap(), deltas));
        }
        added = true;
    }
    if added { session.skel_export = None; }
    added
}

/// How far from her entrance her skin is made finer (`refine`): as far as his glans lifts it, with room for the skirt.
const REFINE_REACH_M: f32 = 0.30;
/// Her lips and the skin just round them keep their triangles (her opening is shaped by morphs of its own).
const REFINE_LIPS_M: f32 = 0.02;
/// Skin facing further back than this (the z of its normal, she faces +z) stays as it is: he lifts her front.
const REFINE_FACING: f32 = -0.2;

/// Every triangle with all three corners in `marked` cut in four at its edge middles; a neighbour sharing a cut edge is cut
/// along it too, so no crack opens at the edge of the marked skin. The new triangle list, and for each new vertex (numbered
/// from `marked.len()`) the two vertices it lies between. Winding is kept.
fn split_triangles(indices: &[u32], marked: &[bool]) -> (Vec<u32>, Vec<(u32, u32)>) {
    let is_marked = |v: u32| marked.get(v as usize).copied().unwrap_or(false);
    let edge = |a: u32, b: u32| if a < b { (a, b) } else { (b, a) };
    let mut mids: HashMap<(u32, u32), u32> = HashMap::new();
    let mut made: Vec<(u32, u32)> = Vec::new();
    for t in indices.chunks_exact(3) {
        if !t.iter().all(|v| is_marked(*v)) { continue; }
        for (a, b) in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] {
            let e = edge(a, b);
            if !mids.contains_key(&e) { mids.insert(e, (marked.len() + made.len()) as u32);made.push(e); }
        }
    }
    let mut out = Vec::with_capacity(indices.len() + made.len() * 9);
    for t in indices.chunks_exact(3) {
        let m = [mids.get(&edge(t[0], t[1])).copied(), mids.get(&edge(t[1], t[2])).copied(), mids.get(&edge(t[2], t[0])).copied()];
        match m.iter().filter(|x| x.is_some()).count() {
            0 => out.extend_from_slice(t),
            3 => {
                let (ab, bc, ca) = (m[0].unwrap(), m[1].unwrap(), m[2].unwrap());
                out.extend_from_slice(&[t[0], ab, ca, ab, t[1], bc, ca, bc, t[2], ab, bc, ca]);
            }
            1 => {
                // Turned so the cut edge is a-b.
                let k = m.iter().position(|x| x.is_some()).unwrap();
                let (a, b, c, x) = (t[k], t[(k + 1) % 3], t[(k + 2) % 3], m[k].unwrap());
                out.extend_from_slice(&[a, x, c, x, b, c]);
            }
            _ => {
                // Turned so the whole edge is c-a: a-b and b-c are cut.
                let k = m.iter().position(|x| x.is_none()).unwrap();
                let (c, a, b) = (t[k], t[(k + 1) % 3], t[(k + 2) % 3]);
                let (x, y) = (m[(k + 1) % 3].unwrap(), m[(k + 2) % 3].unwrap());
                out.extend_from_slice(&[x, b, y, a, x, y, a, y, c]);
            }
        }
    }
    (out, made)
}

/// The middle of two skinned vertices: their weights averaged, the four largest kept.
fn mid_weights(ba: &[u16; 4], wa: &[f32; 4], bb: &[u16; 4], wb: &[f32; 4]) -> ([u16; 4], [f32; 4]) {
    let mut all: Vec<(u16, f32)> = Vec::with_capacity(8);
    for (bones, weights) in [(ba, wa), (bb, wb)] {
        for (b, w) in bones.iter().zip(weights) {
            if *w <= 0. { continue; }
            match all.iter_mut().find(|e| e.0 == *b) { Some(e) => e.1 += *w * 0.5, None => all.push((*b, *w * 0.5)) }
        }
    }
    all.sort_by(|x, y| y.1.total_cmp(&x.1));all.truncate(4);
    let sum: f32 = all.iter().map(|e| e.1).sum();
    let (mut bones, mut weights) = ([0u16; 4], [0f32; 4]);
    for (i, (b, w)) in all.iter().enumerate() { bones[i] = *b;weights[i] = if sum > 0. { *w / sum } else { 0. }; }
    (bones, weights)
}

/// Her skin where he lifts it cut finer, twice as many edges across it (user, 2026-11-06: the lifted skin looked faceted),
/// for the one-on-one scene only: every other mode keeps the card's mesh. New vertices lie on the old edges, so she looks
/// the same at rest; old vertices keep their numbers. Once per session, after `add`, before the mesh is built. Returns
/// the vertices added.
pub fn refine(session: &mut OkSession) -> usize {
    if session.sex != 1 { return 0; }
    let Some(rest) = crate::skel_export::bind_body(session) else { return 0; };
    let at = |n: &str| rest.world_tf(n).map(|m| translation(&m));
    let (Some(kokan), Some(top)) = (at("cf_j_kokan").or_else(|| at("cf_J_Kokan")), at("cf_j_spine02")) else { return 0; };
    let still: Vec<bool> = rest.names.iter().map(|n| { let n = n.to_ascii_lowercase(); STILL.iter().any(|s| n.contains(s)) }).collect();
    let thigh: Vec<bool> = rest.names.iter().map(|n| { let n = n.to_ascii_lowercase(); THIGH.iter().any(|s| n.contains(s)) }).collect();
    let mut total = 0;
    for part in session.parts.iter_mut() {
        if part.role != "body" || part.skel_kind != 1 || part.runtime_accessory.is_some() || !part.blend_shapes.iter().any(|(n, _)| is_bulge(n)) { continue; }
        let (worlds, binds) = crate::skel_export::palettes(&rest, part);
        if worlds.is_empty() { continue; }
        let n = part.rest_positions.len();
        let marked: Vec<bool> = (0..n).map(|j| {
            let Some((skin, free, on_thigh)) = skin_of(part, j, &worlds, &binds, &still, &thigh) else { return false; };
            if free - on_thigh <= 0.01 { return false; }
            let p = point(&skin, part.rest_positions[j]);
            let d = (0..3).map(|i| (p[i] - kokan[i]) * (p[i] - kokan[i])).sum::<f32>().sqrt();
            if d < REFINE_LIPS_M || d > REFINE_REACH_M || p[1] > top[1] { return false; }
            let o = point(&skin, [0.; 3]);
            part.rest_normals.get(j).is_some_and(|v| { let v = point(&skin, *v);let w = [v[0] - o[0], v[1] - o[1], v[2] - o[2]];
                let len = (w[0] * w[0] + w[1] * w[1] + w[2] * w[2]).sqrt();len > 1e-6 && w[2] / len >= REFINE_FACING })
        }).collect();
        let (indices, made) = split_triangles(&part.indices, &marked);
        if made.is_empty() { continue; }
        fn mid2(v: &mut Vec<[f32; 2]>, n: usize, made: &[(u32, u32)]) {
            if v.len() != n { return; }
            for (a, b) in made { let (p, q) = (v[*a as usize], v[*b as usize]);v.push([(p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5]); }
        }
        fn mid3(v: &mut Vec<[f32; 3]>, n: usize, made: &[(u32, u32)], unit: bool) {
            if v.len() != n { return; }
            for (a, b) in made {
                let (p, q) = (v[*a as usize], v[*b as usize]);let mut m = [(p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5, (p[2] + q[2]) * 0.5];
                let len = (m[0] * m[0] + m[1] * m[1] + m[2] * m[2]).sqrt();
                if unit { if len > 1e-6 { for x in &mut m { *x /= len; } } else { m = p; } }
                v.push(m);
            }
        }
        mid3(&mut part.rest_positions, n, &made, false);mid3(&mut part.positions, n, &made, false);
        mid3(&mut part.rest_normals, n, &made, true);mid3(&mut part.normals, n, &made, true);
        mid2(&mut part.uvs, n, &made);mid2(&mut part.uv2, n, &made);mid2(&mut part.uv3, n, &made);mid2(&mut part.uv4, n, &made);
        if part.rest_tangents.len() == n {
            for (a, b) in &made {
                let (p, q) = (part.rest_tangents[*a as usize], part.rest_tangents[*b as usize]);
                let mut m = [p[0] + q[0], p[1] + q[1], p[2] + q[2]];
                let len = (m[0] * m[0] + m[1] * m[1] + m[2] * m[2]).sqrt();
                if len > 1e-6 { for x in &mut m { *x /= len; } } else { m = [p[0], p[1], p[2]]; }
                part.rest_tangents.push([m[0], m[1], m[2], p[3]]);
            }
        }
        if part.vertex_colors.len() == n {
            for (a, b) in &made {
                let (p, q) = (part.vertex_colors[*a as usize], part.vertex_colors[*b as usize]);
                part.vertex_colors.push(std::array::from_fn(|i| ((p[i] as u16 + q[i] as u16) / 2) as u8));
            }
        }
        if part.bone_idx.len() == n && part.weights.len() == n {
            for (a, b) in &made {
                let (a, b) = (*a as usize, *b as usize);
                let (bones, weights) = mid_weights(&part.bone_idx[a], &part.weights[a], &part.bone_idx[b], &part.weights[b]);
                part.bone_idx.push(bones);part.weights.push(weights);
            }
        }
        // Each morph moves the new vertices half way between what it does to the two ends.
        let middles = |of: &HashMap<u32, [f32; 3]>| -> Vec<(u32, [f32; 3])> {
            made.iter().enumerate().filter_map(|(i, (a, b))| {
                let (p, q) = (of.get(a), of.get(b));if p.is_none() && q.is_none() { return None; }
                let (p, q) = (p.copied().unwrap_or([0.; 3]), q.copied().unwrap_or([0.; 3]));
                Some(((n + i) as u32, [(p[0] + q[0]) * 0.5, (p[1] + q[1]) * 0.5, (p[2] + q[2]) * 0.5]))
            }).collect()
        };
        for (_, deltas) in part.blend_shapes.iter_mut() {
            let of: HashMap<u32, [f32; 3]> = deltas.iter().copied().collect();
            deltas.extend(middles(&of));
        }
        for (idx, dxyz) in part.morph_idx.iter_mut().zip(part.morph_dxyz.iter_mut()) {
            if dxyz.len() != idx.len() * 3 { continue; }
            let of: HashMap<u32, [f32; 3]> = idx.iter().enumerate().map(|(i, v)| (*v, [dxyz[i * 3], dxyz[i * 3 + 1], dxyz[i * 3 + 2]])).collect();
            for (v, d) in middles(&of) { idx.push(v);dxyz.extend_from_slice(&d); }
        }
        part.indices = indices;total += made.len();
    }
    if total > 0 { session.skel_export = None; }
    // Her index of this skin now, on the opening's thread: left to his first stroke it stopped the game for 1.6 s.
    if let Some(part) = session.parts.iter().find(|p| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none() && p.blend_shapes.iter().any(|(n, _)| is_bulge(n))) { let _ = wrap_verts(session, part); }
    cover::warm(session);
    total
}

/// His penis root (cm_J_dan100_00) turned so his penis points along `dir` (his skeleton space, Unity, any length): lying
/// face down (躺姿後入) the clip points it almost straight down, through her lower belly and about 10 cm into the floor,
/// where no swell of hers has room to cover it (user, 2026-11-01: turning it is fine there). The scene gives the line into
/// her (her entrance to her lower spine). Written as his FK on that bone (user_fk, applied after the pair contacts), from
/// the pose as it is now. Returns the degrees turned now; None without his penis.
pub fn aim_penis(session: &mut OkSession, dir: [f32; 3]) -> Option<f32> {
    const ROOT: &str = "cm_J_dan100_00";
    let tip = penis_tip(session)?;
    let skel = session.body_skel.as_ref()?;
    let world = skel.world_tf(ROOT)?;
    let root = translation(&world);
    let norm = |v: [f32; 3]| { let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt(); if l < 1e-6 { None } else { Some([v[0] / l, v[1] / l, v[2] / l]) } };
    let v = norm([tip[0] - root[0], tip[1] - root[1], tip[2] - root[2]])?;
    let d = norm(dir)?;
    let dot = (v[0] * d[0] + v[1] * d[1] + v[2] * d[2]).clamp(-1.0, 1.0);
    let angle = dot.acos();
    if angle < 0.002 { return Some(0.0); }
    let axis = [v[1] * d[2] - v[2] * d[1], v[2] * d[0] - v[0] * d[2], v[0] * d[1] - v[1] * d[0]];
    let mut turn = crate::pose::quat_axis_angle(axis, angle);
    // Whichever handedness the axis came out in: the turned penis must point along `dir`.
    let r = rotate(turn, v);
    if r[0] * d[0] + r[1] * d[1] + r[2] * d[2] < dot { turn = crate::pose::quat_axis_angle(axis, -angle); }
    // To the bone's own frame: local' = local * (world^-1 * turn * world).
    let w = rotation_of(&world);
    let local_turn = crate::pose::quat_mul(conj(w), crate::pose::quat_mul(turn, w));
    let id = skel.tfs.iter().find(|(_, t)| t.name == ROOT).map(|(id, _)| *id)?;
    let local = crate::pose::quat_mul(skel.tfs.get(&id)?.rot, local_turn);
    let euler = crate::pose::quat_to_unity_euler(local);
    if !euler.iter().all(|e| e.is_finite()) { return None; }
    session.user_fk.retain(|(n, _)| n != ROOT);
    session.user_fk.push((ROOT.to_string(), euler));
    Some(angle.to_degrees())
}

fn conj(q: [f32; 4]) -> [f32; 4] { [-q[0], -q[1], -q[2], q[3]] }
fn rotate(q: [f32; 4], v: [f32; 3]) -> [f32; 3] {
    let p = crate::pose::quat_mul(crate::pose::quat_mul(q, [v[0], v[1], v[2], 0.0]), conj(q));
    [p[0], p[1], p[2]]
}
/// The rotation of a world matrix (scale taken out of its columns).
fn rotation_of(m: &Mat4) -> [f32; 4] {
    let col = |c: usize| { let v = [m[0][c], m[1][c], m[2][c]]; let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt().max(1e-6); [v[0] / l, v[1] / l, v[2] / l] };
    let (x, y, z) = (col(0), col(1), col(2));
    let (m00, m11, m22) = (x[0], y[1], z[2]);
    let trace = m00 + m11 + m22;
    let q = if trace > 0.0 {
        let s = (trace + 1.0).sqrt() * 2.0;
        [(y[2] - z[1]) / s, (z[0] - x[2]) / s, (x[1] - y[0]) / s, 0.25 * s]
    } else if m00 > m11 && m00 > m22 {
        let s = (1.0 + m00 - m11 - m22).sqrt() * 2.0;
        [0.25 * s, (y[0] + x[1]) / s, (z[0] + x[2]) / s, (y[2] - z[1]) / s]
    } else if m11 > m22 {
        let s = (1.0 + m11 - m00 - m22).sqrt() * 2.0;
        [(y[0] + x[1]) / s, 0.25 * s, (z[1] + y[2]) / s, (z[0] - x[2]) / s]
    } else {
        let s = (1.0 + m22 - m00 - m11).sqrt() * 2.0;
        [(z[0] + x[2]) / s, (z[1] + y[2]) / s, 0.25 * s, (x[1] - y[0]) / s]
    };
    let l = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).sqrt().max(1e-6);
    [q[0] / l, q[1] / l, q[2] / l, q[3] / l]
}

/// The end of his penis now: the vertex of his penis mesh farthest from its root (his skeleton space, Unity metres).
/// Not J_dan109: the dan bones draw in as he goes in (17.8 cm at her entrance, 5 to 9 in a loop) while his penis is drawn
/// whole (19.6 cm), so that bone is mid-shaft then.
pub fn penis_tip(session: &OkSession) -> Option<[f32; 3]> {
    let skel = session.body_skel.as_ref()?;
    let part = session.parts.iter().find(|p| crate::head_body::is_penis_mesh(&p.name))?;
    let root = translation(&skel.world_tf("cm_J_dan100_00")?);
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return None; }
    let mut best: Option<(f32, [f32; 3])> = None;
    for j in 0..part.rest_positions.len() {
        let Some((skin, _, _)) = skin_of(part, j, &worlds, &binds, &[], &[]) else { continue; };
        let p = point(&skin, part.rest_positions[j]);
        let d = (p[0] - root[0]).powi(2) + (p[1] - root[1]).powi(2) + (p[2] - root[2]).powi(2);
        if best.map_or(true, |(b, _)| d > b) { best = Some((d, p)); }
    }
    best.map(|(_, p)| p)
}

/// How near his glans a skin vertex counts as where it comes through.
const NEAR_M: f32 = 0.06;
/// How far `tip` (her skeleton space, Unity metres) is outside her skin now (negative: inside): of the skin vertices any
/// swell moves within `NEAR_M` of it, in her current pose without the swell, the one it is farthest out of along its normal
/// (none that near: the nearest); how far that vertex is; the swell that moves it most and how far it does at weight 100
/// (metres). Not simply the nearest: a glans 6 cm out of her belly is often nearest a vertex below where it came through,
/// and the swell picked there bulged under it.
/// His penis made longer or bigger in the scene (user, 2026-11-02: set live): `length` times the way along his dan
/// bones (cm_J_dan100_00's children), `scale` his penis root's scale (the whole penis, girth and length). 0 is 1.
#[derive(Debug, Default, Clone)]
pub struct PenisSize { pub length: f32, pub scale: f32, kept: HashMap<i64, ([f32; 3], [f32; 3])> }

/// Applied after each frame's pose (and once more after the pair contacts): the bones' own local positions times
/// `length`. A bone not set again since (the same position as written) keeps the one it had, so it is never lengthened
/// twice. True when his bones changed (the worlds need rebuilding).
pub fn apply_penis_size(sk: &mut crate::pose::Skeleton, size: &mut PenisSize) -> bool {
    let one = |v: f32| if v > 0. && v.is_finite() { v } else { 1. };
    let (l, s) = (one(size.length), one(size.scale));
    if l == 1. && s == 1. && size.kept.is_empty() { return false; }
    let Some(root) = sk.tfs.iter().find(|(_, t)| t.name == "cm_J_dan100_00").map(|(id, _)| *id) else { return false; };
    if let Some(t) = sk.tfs.get_mut(&root) { t.scale = [s; 3]; }
    for id in crate::pose::subtree_ids_pub(root, &sk.tfs) {
        if id == root { continue; }
        let Some(t) = sk.tfs.get_mut(&id) else { continue; };
        if !t.name.starts_with("cm_J_dan") { continue; }
        let raw = match size.kept.get(&id) { Some((w, r)) if *w == t.pos => *r, _ => t.pos };
        let p = [raw[0] * l, raw[1] * l, raw[2] * l];
        t.pos = p;size.kept.insert(id, (p, raw));
    }
    if l == 1. && s == 1. { size.kept.clear(); }
    true
}

/// Her skin round her entrance that `skin_check` reads (bind pose, metres from cf_j_kokan): her belly, groin, bottom and the
/// tops of her thighs.
const PROBE_M: f32 = 0.25;
/// Her opening itself is left out: his penis passes through it, and its rim read as him out of her skin (1 to 1.6 cm
/// all the time, 桌上躺位), drawing him almost out of her. Only the opening: at 6 cm her perineum and the start of the
/// cleft of her bottom were left out too, and his penis lay in them unseen (user, 2026-11-02, 桌上躺位 from the front).
const PROBE_INNER_M: f32 = 0.03;
/// Farther than this from all of it a point counts as deep in her.
const NEAR_SKIN_M: f32 = 0.10;

/// How many of her nearest skin vertices one depth reading averages (skin_check): one alone read his penis between two
/// folds that face each other (her vulva, her perineum, the cleft of her bottom) as out of one of them whichever way
/// he went, and its normal said only "sideways".
const NEAREST: usize = 6;
/// Step of the depth's slope (skin_check), metres.
const SLOPE_M: f32 = 0.01;

/// Her skin round her entrance as it is now: position, outward normal, and the vertex's distance from her entrance at
/// rest (metres).
struct SkinNow { p: [f32; 3], n: [f32; 3], rest: f32 }

fn skin_now(session: &OkSession) -> Option<Vec<SkinNow>> {
    let skel = session.body_skel.as_ref()?;
    let part = session.parts.iter().find(|p| p.blend_shapes.iter().any(|(n, _)| is_bulge(n)))?;
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return None; }
    let probe = session.skin_probe.get_or_init(|| {
        let Some(rest) = crate::skel_export::bind_body(session) else { return Vec::new(); };
        let Some(k) = rest.world_tf("cf_j_kokan").or_else(|| rest.world_tf("cf_J_Kokan")).map(|m| translation(&m)) else { return Vec::new(); };
        let (rw, rb) = crate::skel_export::palettes(&rest, part);
        // Nor the folds of her vulva (skin led by cf_j_kokan): his penis goes through them.
        let fold: Vec<bool> = rest.names.iter().map(|n| n.to_ascii_lowercase().contains("kokan")).collect();
        let led_by_fold = |j: usize| { let (b, w) = (part.bone_idx[j], part.weights[j]);let mut top = 0;for t in 1..4 { if w[t] > w[top] { top = t; } }
            fold.get(b[top] as usize) == Some(&true) };
        (0..part.rest_positions.len()).filter(|&j| !led_by_fold(j)).filter_map(|j| {
            let (s, _, _) = skin_of(part, j, &rw, &rb, &[], &[])?;
            let p = point(&s, part.rest_positions[j]);let d = (0..3).map(|i| (p[i] - k[i]) * (p[i] - k[i])).sum::<f32>().sqrt();
            (d < PROBE_M && d > PROBE_INNER_M).then_some((j as u32, d))
        }).collect()
    });
    Some(probe.iter().filter_map(|&(j, rest)| {
        let j = j as usize;
        let (skin, _, _) = skin_of(part, j, &worlds, &binds, &[], &[])?;
        let p = point(&skin, part.rest_positions[j]);let o = point(&skin, [0.; 3]);
        let n = point(&skin, *part.rest_normals.get(j)?);let n = [n[0] - o[0], n[1] - o[1], n[2] - o[2]];
        let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if len < 1e-6 { return None; }
        Some(SkinNow { p, n: [n[0] / len, n[1] / len, n[2] / len], rest })
    }).collect())
}

/// Her skin round her entrance in cells of `SKIN_CELL_M`, for `depth`'s nearest vertices without reading all of it.
struct SkinGrid { lo: [i64; 3], size: [i64; 3], start: Vec<u32>, items: Vec<u32> }
const SKIN_CELL_M: f32 = 0.02;
impl SkinGrid {
    fn cell(p: [f32; 3]) -> [i64; 3] { p.map(|v| (v / SKIN_CELL_M).floor() as i64) }
    fn new(skin: &[SkinNow]) -> SkinGrid {
        let (mut lo, mut hi) = ([i64::MAX; 3], [i64::MIN; 3]);
        for s in skin { let c = Self::cell(s.p); for a in 0..3 { lo[a] = lo[a].min(c[a]);hi[a] = hi[a].max(c[a]); } }
        if skin.is_empty() { return SkinGrid { lo: [0; 3], size: [0; 3], start: vec![0], items: Vec::new() }; }
        let size = [hi[0] - lo[0] + 1, hi[1] - lo[1] + 1, hi[2] - lo[2] + 1];
        let n = (size[0] * size[1] * size[2]) as usize;
        let index = |c: [i64; 3]| (((c[0] - lo[0]) * size[1] + (c[1] - lo[1])) * size[2] + (c[2] - lo[2])) as usize;
        let mut count = vec![0u32; n + 1];
        for s in skin { count[index(Self::cell(s.p)) + 1] += 1; }
        for k in 1..=n { count[k] += count[k - 1]; }
        let mut fill = count.clone();let mut items = vec![0u32; skin.len()];
        for (i, s) in skin.iter().enumerate() { let k = index(Self::cell(s.p));items[fill[k] as usize] = i as u32;fill[k] += 1; }
        SkinGrid { lo, size, start: count, items }
    }
    /// As `depth`, reading the cells out from `at` ring by ring until no nearer vertex can be left.
    fn depth(&self, skin: &[SkinNow], at: [f32; 3]) -> Option<(f32, f32)> {
        if self.items.is_empty() { return None; }
        let mut near: [(f32, usize); NEAREST] = [(f32::MAX, 0); NEAREST];
        let c = Self::cell(at);
        // Rings beyond the box hold nothing: as far as the farthest corner of it.
        let reach = (0..3).map(|a| (c[a] - self.lo[a]).abs().max((c[a] - (self.lo[a] + self.size[a] - 1)).abs())).max().unwrap_or(0);
        for r in 0..=reach {
            for x in c[0] - r..=c[0] + r { for y in c[1] - r..=c[1] + r { for z in c[2] - r..=c[2] + r {
                if (x - c[0]).abs() != r && (y - c[1]).abs() != r && (z - c[2]).abs() != r { continue; }
                let k = [x - self.lo[0], y - self.lo[1], z - self.lo[2]];
                if (0..3).any(|a| k[a] < 0 || k[a] >= self.size[a]) { continue; }
                let cell = ((k[0] * self.size[1] + k[1]) * self.size[2] + k[2]) as usize;
                for &i in &self.items[self.start[cell] as usize..self.start[cell + 1] as usize] {
                    let s = &skin[i as usize];let i = i as usize;
                    let d = (0..3).map(|q| (at[q] - s.p[q]) * (at[q] - s.p[q])).sum::<f32>();
                    // As the scan in index order: an equal distance goes after the ones already kept.
                    if d < near[NEAREST - 1].0 || (d == near[NEAREST - 1].0 && i < near[NEAREST - 1].1) {
                        let mut k = NEAREST - 1;while k > 0 && (near[k - 1].0 > d || (near[k - 1].0 == d && near[k - 1].1 > i)) { near[k] = near[k - 1];k -= 1; }near[k] = (d, i);
                    }
                }
            } } }
            // Every cell not read yet is at least r cells away.
            let bound = r as f32 * SKIN_CELL_M;
            if near[NEAREST - 1].0 < f32::MAX && near[NEAREST - 1].0 <= bound * bound { break; }
            if bound > NEAR_SKIN_M && near[0].0 > NEAR_SKIN_M * NEAR_SKIN_M { return None; }
        }
        if near[0].0 > NEAR_SKIN_M * NEAR_SKIN_M { return None; }
        let (mut sum, mut weight) = (0f32, 0f32);
        for &(d, i) in near.iter().filter(|(d, _)| *d < f32::MAX) {
            let s = &skin[i];let w = 1. / (d.sqrt() + 0.005);
            sum += w * ((at[0] - s.p[0]) * s.n[0] + (at[1] - s.p[1]) * s.n[1] + (at[2] - s.p[2]) * s.n[2]);weight += w;
        }
        Some((sum / weight, skin[near[0].1].rest))
    }
}

/// Out of her skin at `at`: the signed distances to her NEAREST skin vertices along their normals, the nearer counting
/// more; below 0 inside her. And the rest distance of the nearest. None with no skin within NEAR_SKIN_M.
fn depth(skin: &[SkinNow], at: [f32; 3]) -> Option<(f32, f32)> {
    let mut near: [(f32, usize); NEAREST] = [(f32::MAX, 0); NEAREST];
    for (i, s) in skin.iter().enumerate() {
        let d = (0..3).map(|c| (at[c] - s.p[c]) * (at[c] - s.p[c])).sum::<f32>();
        if d < near[NEAREST - 1].0 { let mut k = NEAREST - 1;while k > 0 && near[k - 1].0 > d { near[k] = near[k - 1];k -= 1; }near[k] = (d, i); }
    }
    if near[0].0 > NEAR_SKIN_M * NEAR_SKIN_M { return None; }
    let (mut sum, mut weight) = (0f32, 0f32);
    for &(d, i) in near.iter().filter(|(d, _)| *d < f32::MAX) {
        let s = &skin[i];let w = 1. / (d.sqrt() + 0.005);
        sum += w * ((at[0] - s.p[0]) * s.n[0] + (at[1] - s.p[1]) * s.n[1] + (at[2] - s.p[2]) * s.n[2]);weight += w;
    }
    Some((sum / weight, skin[near[0].1].rest))
}

/// For each point (her skeleton space, Unity metres): how far it is out of her skin round her entrance (metres, below 0
/// inside her; any skin, not only the swells': user, 2026-11-02, 桌上躺位, his glans out of her bottom), the way that
/// distance grows (unit, her skeleton space: the way out of her there), and the rest distance from her entrance of the
/// nearest skin. None where no skin is within NEAR_SKIN_M. Her skin is placed once for all of them.
pub fn skin_check(session: &OkSession, at: &[[f32; 3]]) -> Vec<Option<(f32, [f32; 3], f32)>> {
    let Some(skin) = skin_now(session) else { return vec![None; at.len()]; };
    // Seven readings a point, each over all of her skin round her entrance: in a grid of it instead (the same nearest
    // vertices, SkinGrid::depth).
    let grid = SkinGrid::new(&skin);
    at.iter().map(|&a| {
        let (d, rest) = grid.depth(&skin, a)?;
        let mut g = [0f32; 3];
        for c in 0..3 {
            let (mut hi, mut lo) = (a, a);hi[c] += SLOPE_M;lo[c] -= SLOPE_M;
            g[c] = match (grid.depth(&skin, hi), grid.depth(&skin, lo)) { (Some(h), Some(l)) => h.0 - l.0, _ => 0. };
        }
        let len = (g[0] * g[0] + g[1] * g[1] + g[2] * g[2]).sqrt();
        Some((d, if len > 1e-6 { [g[0] / len, g[1] / len, g[2] / len] } else { [0.; 3] }, rest))
    }).collect()
}


/// The vertices her bulge shapes move, each once, in the order the shapes list them (`past`).
fn bulge_verts(part: &SessionPart) -> std::sync::Arc<Vec<u32>> {
    static KEPT: std::sync::Mutex<Vec<(usize, usize, usize, std::sync::Arc<Vec<u32>>)>> = std::sync::Mutex::new(Vec::new());
    let key = (part as *const SessionPart as usize, part.blend_shapes.len(), part.rest_positions.len());
    if let Some(e) = KEPT.lock().unwrap().iter().find(|e| (e.0, e.1, e.2) == key) { return e.3.clone(); }
    let mut seen = std::collections::HashSet::new();let mut verts = Vec::new();
    for (_, deltas) in part.blend_shapes.iter().filter(|(n, _)| is_bulge(n)) { for (j, _) in deltas { if seen.insert(*j) { verts.push(*j); } } }
    let verts = std::sync::Arc::new(verts);
    let mut kept = KEPT.lock().unwrap();kept.insert(0, (key.0, key.1, key.2, verts.clone()));kept.truncate(4);
    verts
}

pub fn past(session: &OkSession, tip: [f32; 3]) -> Option<(f32, f32, String, f32)> {
    let skel = session.body_skel.as_ref()?;
    let part = session.parts.iter().find(|p| p.blend_shapes.iter().any(|(n, _)| is_bulge(n)))?;
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return None; }
    // Her bulge's vertices once each, in the order the shapes list them (kept per body part: the set of them was built
    // every frame), skinned on the pool, then taken in that order as before (the first of equals wins).
    let verts = bulge_verts(part);
    use rayon::prelude::*;
    let read: Vec<Option<(f32, f32, usize)>> = verts.par_iter().map(|&j| {
        let j = j as usize;
        let (skin, _, _) = skin_of(part, j, &worlds, &binds, &[], &[])?;
        let p = point(&skin, part.rest_positions[j]);
        let d = [tip[0] - p[0], tip[1] - p[1], tip[2] - p[2]];
        let dist = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
        let o = point(&skin, [0.; 3]);
        let n = part.rest_normals.get(j).map(|v| { let v = point(&skin, *v); [v[0] - o[0], v[1] - o[1], v[2] - o[2]] })?;
        let len = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if len < 1e-6 { return None; }
        Some((dist, (d[0] * n[0] + d[1] * n[1] + d[2] * n[2]) / len, j))
    }).collect();
    let (mut nearest, mut most_out): (Option<(f32, f32, usize)>, Option<(f32, f32, usize)>) = (None, None);
    for (dist, out, j) in read.into_iter().flatten() {
        if nearest.map_or(true, |(b, _, _)| dist < b) { nearest = Some((dist, out, j)); }
        if dist <= NEAR_M * NEAR_M && most_out.map_or(true, |(_, b, _)| out > b) { most_out = Some((dist, out, j)); }
    }
    let (dist, out, j) = most_out.or(nearest)?;
    let mut most: Option<(&std::ffi::CString, f32)> = None;
    for (n, deltas) in part.blend_shapes.iter().filter(|(n, _)| is_bulge(n)) {
        let Some((_, d)) = deltas.iter().find(|(i, _)| *i as usize == j) else { continue; };
        let moves = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt();
        if most.map_or(true, |(_, m)| moves > m) { most = Some((n, moves)); }
    }
    let (n, moves) = most?;
    Some((out, dist.sqrt(), n.to_string_lossy().into_owned(), moves))
}

/// Her skin round her entrance that her belly wraps him with (`wrap_deltas`): each vertex of her body part within
/// WRAP_REACH_M of her entrance at rest, its rest distance from her entrance, and its normal averaged over WRAP_SMOOTH_M
/// round it (her navel and creases would turn their walls apart). Built once per body.
/// `place`: the copies of one place of her skin (split at her mesh's UV seams) share it, from where they lie at rest.
struct WrapVert { j: usize, from_entrance: f32, n: [f32; 3], nbr: Vec<u32>, tri: Vec<[u32; 2]>, free: f32, inner: bool, place: u32, rest: [f32; 3], bones: [u16; 4], weights: [f32; 4] }
/// Her buttocks (part of a name): with her thighs and the STILL bones, skin on them never rises (user 2026-11-02: the
/// lift is her belly's, her thighs and bottom stay where they are).
const BUTTOCK: [&str; 1] = ["siri"];
/// Rounds of evening the lift over her mesh (each skin towards its neighbours', never below what him under it asks):
/// the skirt alone left a wall each side of the lifted skin, drawn black at her lips (GalV1103j).
const WRAP_EVEN_ROUNDS: usize = 4;
const WRAP_REACH_M: f32 = 0.30;
const WRAP_SMOOTH_M: f32 = 0.02;
/// Her lips (within WRAP_LIPS_M of her entrance at rest) never move; the skin comes in fully over WRAP_LIPS_FADE_M more.
/// (0.5 cm and 1 cm more tore her lips open: GalV1103i.)
const WRAP_LIPS_M: f32 = 0.015;
const WRAP_LIPS_FADE_M: f32 = 0.02;
/// Skin that looks into her own skin within WRAP_INNER_M at rest (the walls of her vagina, her creases) never moves: its
/// normal meets him from the inside, and pushed past him it came out through her mons (GalV1103h, a dark hole).
const WRAP_INNER_M: f32 = 0.05;
/// Her skin round her entrance, within this at rest, is what is looked into for that.
const WRAP_INNER_REACH_M: f32 = 0.20;
/// The most a skin is lifted (0.12 left his glans through her mons at 正常位's deepest, user 2026-11-02), and how wide
/// the skirt round the lifted skin is (its height times WRAP_SKIRT, plus WRAP_SKIRT_M).
/// 0.40 then 1.0: her belly must take him 40 cm and more out of where it was (user, 2026-11-02, to prove it right).
const WRAP_MOST_M: f32 = 1.0;
/// The way up is her skin's normal within WRAP_UP_NEAR_M of him, WRAP_UP_PAST_M from her entrance at rest or more.
const WRAP_UP_NEAR_M: f32 = 0.05;
const WRAP_UP_PAST_M: f32 = 0.05;
/// Skin facing up rises fully from WRAP_FACE_FULL (cosine) and not at all below WRAP_FACE_FROM.
const WRAP_FACE_FROM: f32 = 0.0;
const WRAP_FACE_FULL: f32 = 0.5;
/// The tent round him falls WRAP_SLOPE metres for each metre along her skin.
const WRAP_SLOPE: f32 = 1.5;
const WRAP_HELD_NEAR_M: f32 = 0.03;
/// Columns up the way the skin rises, this wide, and how much higher other skin in one is for the lower to be covered.
const WRAP_LAYER_CELL_M: f32 = 0.015;
const WRAP_LAYER_GAP_M: f32 = 0.02;
const WRAP_HELD_FAR_M: f32 = 0.10;
/// The last few bodies (her, the second heroine, an outfit changing); each took 1.6 s to build.
static WRAP_VERTS: std::sync::Mutex<Vec<(usize, usize, std::sync::Arc<Vec<WrapVert>>)>> = std::sync::Mutex::new(Vec::new());

fn wrap_verts(session: &OkSession, part: &SessionPart) -> Option<std::sync::Arc<Vec<WrapVert>>> {
    let key = (part as *const SessionPart as usize, part.rest_positions.len());
    if let Some((_, _, v)) = WRAP_VERTS.lock().unwrap().iter().find(|e| (e.0, e.1) == key) { return Some(v.clone()); }
    let rest = crate::skel_export::bind_body(session)?;
    let kokan = rest.world_tf("cf_j_kokan").or_else(|| rest.world_tf("cf_J_Kokan")).map(|m| translation(&m))?;
    let (worlds, binds) = crate::skel_export::palettes(&rest, part);
    if worlds.is_empty() { return None; }
    let named = |list: &[&str]| -> Vec<bool> { rest.names.iter().map(|n| { let n = n.to_ascii_lowercase(); list.iter().any(|s| n.contains(s)) }).collect() };
    let (still, mut held) = (named(&STILL), named(&THIGH));
    for (h, b) in held.iter_mut().zip(named(&BUTTOCK)) { *h |= b; }
    // Bind pose position and normal of each vertex near her entrance.
    let mut near: Vec<(usize, [f32; 3], [f32; 3], f32)> = Vec::new();
    let mut at_rest: Vec<Option<[f32; 3]>> = vec![None; part.rest_positions.len()];
    for j in 0..part.rest_positions.len() {
        let Some((m, _, _)) = skin_of(part, j, &worlds, &binds, &[], &[]) else { continue; };
        let p = point(&m, part.rest_positions[j]);
        let d = ((0..3).map(|i| (p[i] - kokan[i]) * (p[i] - kokan[i])).sum::<f32>()).sqrt();
        if d <= WRAP_INNER_REACH_M + WRAP_INNER_M { at_rest[j] = Some(p); }
        if d > WRAP_REACH_M { continue; }
        let o = point(&m, [0.; 3]);
        let n = part.rest_normals.get(j).map(|v| { let v = point(&m, *v); [v[0] - o[0], v[1] - o[1], v[2] - o[2]] }).unwrap_or([0., 0., 1.]);
        near.push((j, p, n, d));
    }
    let cell = |p: [f32; 3]| p.map(|v| (v / WRAP_SMOOTH_M).floor() as i64);
    let mut grid: HashMap<[i64; 3], Vec<usize>> = HashMap::new();
    for (i, (_, p, _, _)) in near.iter().enumerate() { grid.entry(cell(*p)).or_default().push(i); }
    // Her skin round her entrance at rest, in cells WRAP_INNER_M wide, to look into.
    let tris: Vec<[usize; 3]> = part.indices.chunks_exact(3).map(|t| [t[0] as usize, t[1] as usize, t[2] as usize])
        .filter(|t| t.iter().all(|&v| at_rest.get(v).is_some_and(|p| p.is_some()))).collect();
    let tcell = |p: [f32; 3]| p.map(|v| (v / WRAP_INNER_M).floor() as i64);
    let mut tgrid: HashMap<[i64; 3], Vec<usize>> = HashMap::new();
    for (t, tri) in tris.iter().enumerate() {
        let mut cs: Vec<[i64; 3]> = tri.iter().map(|&v| tcell(at_rest[v].unwrap())).collect();cs.sort();cs.dedup();
        for c in cs { tgrid.entry(c).or_default().push(t); }
    }
    let looks_in = |j: usize, p: [f32; 3], n: [f32; 3]| -> bool {
        let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if l < 1e-6 { return false; }
        let n = [n[0] / l, n[1] / l, n[2] / l];
        let c = tcell(p);let mut seen = std::collections::HashSet::new();
        for dx in -1..=1 { for dy in -1..=1 { for dz in -1..=1 {
            for &t in tgrid.get(&[c[0] + dx, c[1] + dy, c[2] + dz]).into_iter().flatten() {
                if !seen.insert(t) || tris[t].contains(&j) { continue; }
                let [a, b, cc] = tris[t].map(|v| at_rest[v].unwrap());
                // Möller–Trumbore.
                let e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];let e2 = [cc[0] - a[0], cc[1] - a[1], cc[2] - a[2]];
                let h = [n[1] * e2[2] - n[2] * e2[1], n[2] * e2[0] - n[0] * e2[2], n[0] * e2[1] - n[1] * e2[0]];
                let det = e1[0] * h[0] + e1[1] * h[1] + e1[2] * h[2];if det.abs() < 1e-12 { continue; }
                let s = [p[0] - a[0], p[1] - a[1], p[2] - a[2]];let u = (s[0] * h[0] + s[1] * h[1] + s[2] * h[2]) / det;
                if !(0. ..=1.).contains(&u) { continue; }
                let q = [s[1] * e1[2] - s[2] * e1[1], s[2] * e1[0] - s[0] * e1[2], s[0] * e1[1] - s[1] * e1[0]];
                let v = (n[0] * q[0] + n[1] * q[1] + n[2] * q[2]) / det;if v < 0. || u + v > 1. { continue; }
                let t = (e2[0] * q[0] + e2[1] * q[1] + e2[2] * q[2]) / det;
                if t > 0.002 && t < WRAP_INNER_M { return true; }
            }
        }}}
        false
    };
    let mut out = Vec::with_capacity(near.len());
    let mut places: HashMap<[i64; 3], u32> = HashMap::new();
    for (j, p, n0, d) in &near {
        let inner = *d <= WRAP_INNER_REACH_M && looks_in(*j, *p, *n0);
        let free = skin_of(part, *j, &worlds, &binds, &still, &held).map_or(0., |(_, f, on)| (f - on).clamp(0., 1.));
        let c = cell(*p);let mut sum = [0f32; 3];
        for dx in -1..=1 { for dy in -1..=1 { for dz in -1..=1 {
            for &i in grid.get(&[c[0] + dx, c[1] + dy, c[2] + dz]).into_iter().flatten() {
                let (_, q, n, _) = near[i];
                if (0..3).map(|a| (q[a] - p[a]) * (q[a] - p[a])).sum::<f32>() > WRAP_SMOOTH_M * WRAP_SMOOTH_M { continue; }
                let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if l < 1e-6 { continue; }
                for a in 0..3 { sum[a] += n[a] / l; }
            }
        }}}
        // Back into the mesh's own space (the bind skin's inverse), where the posed skin turns it each frame.
        let Some((m, _, _)) = skin_of(part, *j, &worlds, &binds, &[], &[]) else { continue; };
        let inv = mat_inv_pub(&m);let o = point(&inv, [0.; 3]);let q = point(&inv, sum);
        let n = [q[0] - o[0], q[1] - o[1], q[2] - o[2]];let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();
        if l < 1e-6 { continue; }
        let next = places.len() as u32;let place = *places.entry(p.map(|v| (v * 5000.).round() as i64)).or_insert(next);
        out.push(WrapVert { j: *j, from_entrance: *d, n: [n[0] / l, n[1] / l, n[2] / l], nbr: Vec::new(), tri: Vec::new(), free, inner, place, rest: part.rest_positions[*j], bones: part.bone_idx[*j], weights: part.weights[*j] });
    }
    // Each one's neighbours along her mesh.
    let at: HashMap<usize, u32> = out.iter().enumerate().map(|(i, v)| (v.j, i as u32)).collect();
    for t in part.indices.chunks_exact(3) {
        let ids: Vec<Option<u32>> = t.iter().map(|&v| at.get(&(v as usize)).copied()).collect();
        for a in 0..3 { for b in 0..3 {
            if a == b { continue; }
            if let (Some(x), Some(y)) = (ids[a], ids[b]) { if !out[x as usize].nbr.contains(&y) { out[x as usize].nbr.push(y); } }
        }}
        // Its triangles, the other two corners in winding order (for its normal after the move).
        if let [Some(x), Some(y), Some(z)] = ids[..] { out[x as usize].tri.push([y, z]);out[y as usize].tri.push([z, x]);out[z as usize].tri.push([x, y]); }
    }
    let out = std::sync::Arc::new(out);
    { let mut cache = WRAP_VERTS.lock().unwrap();cache.retain(|e| (e.0, e.1) != key);cache.insert(0, (key.0, key.1, out.clone()));cache.truncate(4); }
    Some(out)
}

/// How her body's skin moves this frame to wrap his penis in her (user, 2026-11-02: project him onto her belly for a
/// height line and pull her belly up over him, any depth, no tearing): the straight tube from `from` (her entrance) to
/// `to` (his glans), her skeleton space, metres, `radius` round. Skin whose normal, looking out, meets the tube rises
/// along that normal past its far side; the skin round it facing much the same way rises with it, less with distance,
/// over a skirt as wide as that height. Her lips stay. Each move is given in the mesh's own space (as morph deltas),
/// with the vertex index of her body part.
pub fn wrap_deltas(session: &OkSession, from: [f32; 3], to: [f32; 3], up: [f32; 3], radius: f32) -> Vec<(u32, [f32; 6])> {
    let Some((verts, worlds, binds)) = wrap_input(session) else { return Vec::new(); };
    wrap_solve(&verts, &worlds, &binds, from, to, up, radius)
}

/// What `wrap_solve` needs of her this frame: nothing of the session is read after this, so it can run while the pair
/// solves on.
fn wrap_input(session: &OkSession) -> Option<(std::sync::Arc<Vec<WrapVert>>, Vec<Mat4>, Vec<Mat4>)> {
    let skel = session.body_skel.as_ref()?;
    let part = session.parts.iter().find(|p| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none() && p.blend_shapes.iter().any(|(n, _)| is_bulge(n)))?;
    let verts = wrap_verts(session, part)?;
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return None; }
    Some((verts, worlds, binds))
}

/// One frame's wrap and clothes, off the game thread (the wrap took 5 to 9 ms of it, 2026-11-06). Body and clothes come
/// from the same frame's skin, so the scene shows them together: a frame apart his bulge came through her clothes.
struct WrapJob { key: usize, wrap: Option<(std::sync::Arc<Vec<WrapVert>>, Vec<Mat4>, Vec<Mat4>, [[f32; 3]; 3], f32)>, cover: Option<cover::CoverFrame> }
/// What came of a job: her body's moves, the moves of her garments on her body skeleton, her pushing skin.
pub struct WrapDone { pub body: Vec<(u32, [f32; 6])>, pub cloth: Vec<(usize, Vec<(u32, [f32; 3])>)>, pub field: Option<std::sync::Arc<CoverField>> }
/// Each session's job: None while it runs.
static WRAP_DONE: std::sync::Mutex<Vec<(usize, Option<WrapDone>)>> = std::sync::Mutex::new(Vec::new());
static WRAP_WORKER: std::sync::OnceLock<std::sync::Mutex<std::sync::mpsc::Sender<WrapJob>>> = std::sync::OnceLock::new();

fn wrap_worker() -> &'static std::sync::Mutex<std::sync::mpsc::Sender<WrapJob>> {
    WRAP_WORKER.get_or_init(|| {
        let (send, receive) = std::sync::mpsc::channel::<WrapJob>();
        let _ = std::thread::Builder::new().name("ok-wrap".into()).spawn(move || {
            for job in receive {
                let body = job.wrap.map_or_else(Vec::new, |(verts, worlds, binds, at, radius)| wrap_solve(&verts, &worlds, &binds, at[0], at[1], at[2], radius));
                let (cloth, field) = job.cover.map_or((Vec::new(), None), |frame| cover::solve(&frame, &body));
                let mut done = WRAP_DONE.lock().unwrap();
                if let Some(e) = done.iter_mut().find(|e| e.0 == job.key) { e.1 = Some(WrapDone { body, cloth, field }); }
            }
        });
        std::sync::Mutex::new(send)
    })
}

/// Starts this frame's job for `session` (its sessions idle): her skin wrapped round him when `wrap`, her clothes kept
/// over her skin when `cover`. False while the last one still runs.
pub fn wrap_start(session: &OkSession, wrap: bool, from: [f32; 3], to: [f32; 3], up: [f32; 3], radius: f32, cover: bool) -> bool {
    let key = session as *const OkSession as usize;
    {
        let mut done = WRAP_DONE.lock().unwrap();
        match done.iter_mut().find(|e| e.0 == key) { Some(e) => { if e.1.is_none() { return false; } e.1 = None; } None => done.push((key, None)) }
    }
    let wrap = if wrap { wrap_input(session).map(|(v, w, b)| (v, w, b, [from, to, up], radius)) } else { None };
    let cover = if cover { cover::frame(session) } else { None };
    wrap_worker().lock().unwrap().send(WrapJob { key, wrap, cover }).is_ok()
}

/// The finished job of `session`, once. Started and taken a frame apart, so what the scene shows is a frame old.
pub fn wrap_take(session: &OkSession) -> Option<WrapDone> {
    let key = session as *const OkSession as usize;
    let mut done = WRAP_DONE.lock().unwrap();
    let i = done.iter().position(|e| e.0 == key && e.1.is_some())?;
    done.swap_remove(i).1
}

/// `wrap_deltas`, reading nothing but what it is given.
fn wrap_solve(verts: &[WrapVert], worlds: &[Mat4], binds: &[Mat4], from: [f32; 3], to: [f32; 3], up: [f32; 3], radius: f32) -> Vec<(u32, [f32; 6])> {
    let sub = |a: [f32; 3], b: [f32; 3]| [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let axis = sub(to, from);let axis_len2 = dot(axis, axis).max(1e-8);
    let along = |k: f32| [from[0] + axis[0] * k, from[1] + axis[1] * k, from[2] + axis[2] * k];
    let posed = posed_verts(verts, worlds, binds);
    // Her skin over him, lifted all one way (user, 2026-11-02: project him onto her belly for a height line and pull her
    // belly up): each skin moved along its own normal fanned out into a slab when he stood 60 cm out of her, and went
    // only half way along him when it looked along him.
    let lips = |d: f32| { let t = ((d - WRAP_LIPS_M) / WRAP_LIPS_FADE_M).clamp(0., 1.); t * t * (3. - 2. * t) };
    let off = |x: [f32; 3]| { let k = (dot(sub(x, from), axis) / axis_len2).clamp(0., 1.);let g = sub(x, along(k));dot(g, g).sqrt() };
    // The way up: the way her belly faces (from her chest, as the scene reads it). Without that, her skin's normal where
    // he comes near it or out through it, past her entrance (the skin round her entrance faces every way), weighed by
    // how near; that took the skin he passes alongside too, and lay along him (GalV1103t).
    let given = dot(up, up) > 1e-6;
    let mut up = if given { up } else { [0f32; 3] };
    for q in posed.iter().filter(|_| !given) {
        if verts[q.i].from_entrance < WRAP_UP_PAST_M { continue; }
        let o = off(q.p);if o > radius + WRAP_UP_NEAR_M { continue; }
        let w = 1. - (o - radius).max(0.) / WRAP_UP_NEAR_M;
        for a in 0..3 { up[a] += q.n[a] * w; }
    }
    let ul = dot(up, up).sqrt();if ul < 1e-6 { return Vec::new(); }
    let up = [up[0] / ul, up[1] / ul, up[2] / ul];
    // Under him: how high his far side stands over each skin facing that way, along it, where he passes within his
    // radius of the line up from it (his height line on her).
    let samples = ((axis_len2.sqrt() / (radius * 0.5)).ceil() as usize).max(1);
    let line: Vec<[f32; 3]> = (0..=samples).map(|s| along(s as f32 / samples as f32)).collect();
    let mut src = vec![0f32; verts.len()];let mut face = vec![0f32; verts.len()];
    let mut pos: Vec<Option<[f32; 3]>> = vec![None; verts.len()];
    // Skin with more of her skin over it, up the way it would rise (her belly under her drawn-up thighs, the far side of
    // a crease), stays: lifted through the skin over it, its back showed black (GalV1104h).
    let side = if up[0].abs() < 0.9 { [1., 0., 0.] } else { [0., 1., 0.] };
    let e1 = { let h = dot(side, up);let v = [side[0] - up[0] * h, side[1] - up[1] * h, side[2] - up[2] * h];let l = dot(v, v).sqrt();[v[0] / l, v[1] / l, v[2] / l] };
    let e2 = [up[1] * e1[2] - up[2] * e1[1], up[2] * e1[0] - up[0] * e1[2], up[0] * e1[1] - up[1] * e1[0]];
    let column = |p: [f32; 3]| [(dot(p, e1) / WRAP_LAYER_CELL_M).floor() as i64, (dot(p, e2) / WRAP_LAYER_CELL_M).floor() as i64];
    let cols: Vec<[i64; 2]> = posed.iter().map(|q| column(q.p)).collect();
    let (lo, hi) = cols.iter().fold(([i64::MAX; 2], [i64::MIN; 2]), |(l, h), c| ([l[0].min(c[0]), l[1].min(c[1])], [h[0].max(c[0]), h[1].max(c[1])]));
    // One cell of room all round, for the look at the cells beside each.
    let (w, rows) = ((hi[0] - lo[0] + 3).max(0) as usize, (hi[1] - lo[1] + 3).max(0) as usize);
    let cell_at = |c: [i64; 2]| (c[1] - lo[1] + 1) as usize * w + (c[0] - lo[0] + 1) as usize;
    let mut top = vec![f32::MIN; w * rows];
    for (q, c) in posed.iter().zip(&cols) { let h = dot(q.p, up);let e = &mut top[cell_at(*c)];if h > *e { *e = h; } }
    let covered: Vec<bool> = {
        let mut c = vec![false; verts.len()];
        for (q, k) in posed.iter().zip(&cols) {
            let h = dot(q.p, up);let at = cell_at(*k);
            c[q.i] = [at - w - 1, at - w, at - w + 1, at - 1, at, at + 1, at + w - 1, at + w, at + w + 1].iter().any(|&i| top[i] - h > WRAP_LAYER_GAP_M);
        }
        c
    };
    for q in &posed {
        pos[q.i] = Some(q.p);
        let f = ((dot(q.n, up) - WRAP_FACE_FROM) / (WRAP_FACE_FULL - WRAP_FACE_FROM)).clamp(0., 1.);
        let v = &verts[q.i];let free = v.free * v.free * (3. - 2. * v.free);
        // The walls of her vagina never push (pushed past him they came out through her mons, GalV1103h), but they follow
        // the skin round them: left behind they tore a black hole by him at her mons (GalV1104d).
        // How much each skin rises with the tent: her lips stay, skin on her thighs and bottom stays. Which way it faces
        // only decides whether it is pushed by him: the skin by his way out through her mons faces aside, and lifted
        // less than its neighbours it folded over them, black (GalV1104e).
        // Skin held by her thighs and bottom still rises right by him (WRAP_HELD_NEAR_M): his way out through her mons is
        // at her groin, and the skin there left behind opened the side of the skin round him, black (GalV1104f).
        face[q.i] = lips(v.from_entrance) * free;
        let lips_here = lips(v.from_entrance);
        if lips_here <= 0. || v.inner || f <= 0. { continue; }
        let mut h = 0f32;
        for at in &line {
            let rel = sub(*at, q.p);
            let hu = dot(rel, up);let lat = [rel[0] - up[0] * hu, rel[1] - up[1] * hu, rel[2] - up[2] * hu];
            let l2 = dot(lat, lat);if l2 >= radius * radius { continue; }
            h = h.max(hu + (radius * radius - l2).sqrt());
        }
        src[q.i] = h.min(WRAP_MOST_M);
    }
    // How far along her skin each skin is from the skin he pushes: held skin rises fully within WRAP_HELD_NEAR_M of it,
    // and as held as it is from WRAP_HELD_FAR_M.
    let mut apart: Vec<f32> = src.iter().map(|&h| if h > 0. { 0. } else { f32::MAX }).collect();
    // The tent round it (down WRAP_SLOPE for each metre along her skin) needs nothing of that: at the same time.
    let mut lift = src.clone();
    std::thread::scope(|s| {
        s.spawn(|| spread_near(&verts, &pos, &mut apart, WRAP_HELD_FAR_M));
        spread_tent(&verts, &pos, &mut lift, WRAP_SLOPE);
    });
    for (i, v) in verts.iter().enumerate() {
        let t = ((apart[i] - WRAP_HELD_NEAR_M) / (WRAP_HELD_FAR_M - WRAP_HELD_NEAR_M)).clamp(0., 1.);
        let near = 1. - t * t * (3. - 2. * t);
        let free = v.free * v.free * (3. - 2. * v.free);
        // Her lips follow the skin round him too (never push): held, they left the side of the skin by her entrance open,
        // black inside (GalV1104g).
        face[i] = if covered[i] { near } else { free.max(near) };
    }
    // The tent evened.
    for _ in 0..WRAP_EVEN_ROUNDS {
        let was = lift.clone();
        for (i, v) in verts.iter().enumerate() {
            if v.nbr.is_empty() { continue; }
            let avg = v.nbr.iter().map(|&k| was[k as usize]).sum::<f32>() / v.nbr.len() as f32;
            lift[i] = src[i].max((was[i] + avg) * 0.5);
        }
    }
    // Held skin rises less; the skin under him all the way.
    for i in 0..lift.len() { lift[i] = if src[i] > 0. && face[i] > 0. { src[i].max(lift[i] * face[i]) } else { lift[i] * face[i] }; }
    // The copies of one place of her skin (split at her mesh's UV seams; no edge joins them) rise together, the highest of
    // them: each worked out on its own, they rose apart and her belly split open along the seams, black (椅子對面 with
    // the root pad up, user 2026-11-02; the belly bones had the same, GalBones7).
    let places = verts.iter().map(|v| v.place as usize + 1).max().unwrap_or(0);
    {
        let mut most = vec![f32::MIN; places];
        for (i, p) in pos.iter().enumerate() { if p.is_some() { let e = &mut most[verts[i].place as usize];if lift[i] > *e { *e = lift[i]; } } }
        for (i, p) in pos.iter().enumerate() { if p.is_some() { lift[i] = most[verts[i].place as usize]; } }
    }
    // Where each skin goes, and its normal there (its triangles' after the move against before, welded over UV seams):
    // left as it was, the outline shell swelled out of the stretched skin along the old normals, black teeth (GalV1104j).
    let moved: Vec<Option<[f32; 3]>> = (0..verts.len()).map(|i| pos[i].map(|p| [p[0] + up[0] * lift[i], p[1] + up[1] * lift[i], p[2] + up[2] * lift[i]])).collect();
    mesh_moves(&verts, &posed, &pos, &moved, places)
}

/// A skin on the heap of `spread_near` and `spread_tent`: its value, its index. Largest first.
#[derive(Clone, Copy, PartialEq)]
struct Reach(f32, u32);
impl Eq for Reach {}
impl PartialOrd for Reach { fn partial_cmp(&self, o: &Self) -> Option<std::cmp::Ordering> { Some(self.cmp(o)) } }
impl Ord for Reach { fn cmp(&self, o: &Self) -> std::cmp::Ordering { self.0.total_cmp(&o.0).then(self.1.cmp(&o.1)) } }

fn edge_len(a: [f32; 3], b: [f32; 3]) -> f32 { let d = [a[0] - b[0], a[1] - b[1], a[2] - b[2]];(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt() }

/// How far along her skin each skin is from the nearest with `apart` 0 (the others come in as f32::MAX and stay so past
/// `reach`: nothing further on uses them). One pass by nearest first; sweeping the whole mesh until nothing changed took
/// up to 200 rounds, most of the wrap once her belly was refined.
fn spread_near(verts: &[WrapVert], pos: &[Option<[f32; 3]>], apart: &mut [f32], reach: f32) {
    let mut heap = std::collections::BinaryHeap::with_capacity(verts.len());
    for (i, a) in apart.iter().enumerate() { if *a == 0. && pos[i].is_some() { heap.push(Reach(-0., i as u32)); } }
    while let Some(Reach(d, i)) = heap.pop() {
        let (d, i) = (-d, i as usize);
        if d > apart[i] { continue; }
        let Some(p) = pos[i] else { continue; };
        for &k in &verts[i].nbr {
            let k = k as usize;let Some(q) = pos[k] else { continue; };
            let cand = d + edge_len(p, q);
            if cand < apart[k] && cand <= reach { apart[k] = cand;heap.push(Reach(-cand, k as u32)); }
        }
    }
}

/// The tent over her skin: each skin as high as the highest of `lift`, down `slope` for each metre along her skin from it.
fn spread_tent(verts: &[WrapVert], pos: &[Option<[f32; 3]>], lift: &mut [f32], slope: f32) {
    let mut heap = std::collections::BinaryHeap::with_capacity(verts.len());
    for (i, h) in lift.iter().enumerate() { if *h > 0. && pos[i].is_some() { heap.push(Reach(*h, i as u32)); } }
    while let Some(Reach(h, i)) = heap.pop() {
        let i = i as usize;
        if h < lift[i] { continue; }
        let Some(p) = pos[i] else { continue; };
        for &k in &verts[i].nbr {
            let k = k as usize;let Some(q) = pos[k] else { continue; };
            let cand = h - slope * edge_len(p, q);
            if cand > lift[k] { lift[k] = cand;heap.push(Reach(cand, k as u32)); }
        }
    }
}

/// Each vertex of `verts` posed this frame: position, normal (its averaged one), skin matrix.
struct Posed { i: usize, p: [f32; 3], n: [f32; 3], m: Mat4 }
fn posed_verts(verts: &[WrapVert], worlds: &[Mat4], binds: &[Mat4]) -> Vec<Posed> {
    let mut posed = Vec::with_capacity(verts.len());
    let skins: Vec<Mat4> = worlds.iter().zip(binds).map(|(w, b)| mat_mul_pub(w, b)).collect();
    for (i, v) in verts.iter().enumerate() {
        let mut m = [[0.0f32; 4]; 4];
        for (b, w) in v.bones.iter().zip(&v.weights) {
            let Some(s) = skins.get(*b as usize) else { continue; };if *w <= 0. { continue; }
            for r in 0..4 { for c in 0..4 { m[r][c] += s[r][c] * w; } }
        }
        let p = point(&m, v.rest);
        let o = point(&m, [0.; 3]);let q = point(&m, v.n);let n = [q[0] - o[0], q[1] - o[1], q[2] - o[2]];
        let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt();if l < 1e-6 { continue; }
        posed.push(Posed { i, p, n: [n[0] / l, n[1] / l, n[2] / l], m });
    }
    posed
}

/// The moves of the skin (`pos` posed, `moved` where it goes this frame) as morph deltas: body vertex index, the move in
/// the mesh's own space (the posed skin's inverse, as the morph is skinned), then the turn of its normal there.
fn mesh_moves(verts: &[WrapVert], posed: &[Posed], pos: &[Option<[f32; 3]>], moved: &[Option<[f32; 3]>], places: usize) -> Vec<(u32, [f32; 6])> {
    let sub = |a: [f32; 3], b: [f32; 3]| [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    // Only places on a triangle that moved turn: most of her skin in reach stays where it is.
    let mut live = vec![false; places];
    for (i, v) in verts.iter().enumerate() {
        if pos[i] == moved[i] { continue; }
        live[v.place as usize] = true;
        for t in &v.tri { live[verts[t[0] as usize].place as usize] = true;live[verts[t[1] as usize].place as usize] = true; }
    }
    let mut sums = vec![([0f32; 3], [0f32; 3]); places];
    for (i, v) in verts.iter().enumerate() {
        if !live[v.place as usize] { continue; }
        let (Some(p), Some(m)) = (pos[i], moved[i]) else { continue; };
        let e = &mut sums[v.place as usize];
        for t in &v.tri {
            let (Some(b), Some(c), Some(mb), Some(mc)) = (pos[t[0] as usize], pos[t[1] as usize], moved[t[0] as usize], moved[t[1] as usize]) else { continue; };
            let cross = |a: [f32; 3], b: [f32; 3], c: [f32; 3]| { let (u, w) = (sub(b, a), sub(c, a));[u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]] };
            let (n0, n1) = (cross(p, b, c), cross(m, mb, mc));
            for a in 0..3 { e.0[a] += n0[a];e.1[a] += n1[a]; }
        }
    }
    let unit = |v: [f32; 3]| { let l = dot(v, v).sqrt();if l < 1e-12 { None } else { Some([v[0] / l, v[1] / l, v[2] / l]) } };
    let mut out = Vec::new();
    for q in posed {
        let need = moved[q.i].map_or(0., |m| dot(sub(m, q.p), sub(m, q.p)).sqrt());
        // The normal's turn, as a change of her mesh's own normal (the morph's TangentZ delta).
        let (a, b) = sums[verts[q.i].place as usize];
        let dn = unit(a).zip(unit(b)).map_or([0.; 3], |(a, b)| sub(b, a));
        if need < 0.0005 && dot(dn, dn) < 1e-4 { continue; }
        // Up, back into the mesh's space (the posed skin's inverse, as the morph is skinned).
        let inv = mat_inv_pub(&q.m);
        let a = point(&inv, moved[q.i].unwrap_or(q.p));let b = point(&inv, q.p);
        // Her normal and its turn back in the mesh's space (vectors: the skin matrix's inverse without its move).
        let o = point(&inv, [0.; 3]);let back = |v: [f32; 3]| sub(point(&inv, v), o);
        let turned = unit(back(q.n)).map_or([0.; 3], |n0| { let w = back(dn);sub(unit([n0[0] + w[0], n0[1] + w[1], n0[2] + w[2]]).unwrap_or(n0), n0) });
        out.push((verts[q.i].j as u32, [a[0] - b[0], a[1] - b[1], a[2] - b[2], turned[0], turned[1], turned[2]]));
    }
    out
}

#[cfg(test)]
mod spread_tests {
    use super::{spread_near, spread_tent, WrapVert};
    /// A bumpy sheet of skin, each vertex joined to its grid neighbours, one corner hole left unposed.
    fn sheet(n: usize) -> (Vec<WrapVert>, Vec<Option<[f32; 3]>>) {
        let id = |x: usize, y: usize| (y * n + x) as u32;
        let mut verts = Vec::new();let mut pos = Vec::new();
        for y in 0..n { for x in 0..n {
            let mut nbr = Vec::new();
            if x > 0 { nbr.push(id(x - 1, y)); } if x + 1 < n { nbr.push(id(x + 1, y)); }
            if y > 0 { nbr.push(id(x, y - 1)); } if y + 1 < n { nbr.push(id(x, y + 1)); }
            if x + 1 < n && y + 1 < n { nbr.push(id(x + 1, y + 1)); } if x > 0 && y > 0 { nbr.push(id(x - 1, y - 1)); }
            verts.push(WrapVert { j: 0, from_entrance: 0., n: [0.; 3], nbr, tri: Vec::new(), free: 1., inner: false, place: 0, rest: [0.; 3], bones: [0; 4], weights: [0.; 4] });
            let (fx, fy) = (x as f32, y as f32);
            pos.push(if x == 3 && y == 4 { None } else { Some([fx * 0.01, fy * 0.012, ((fx * 0.7).sin() + (fy * 0.4).cos()) * 0.004]) });
        } }
        (verts, pos)
    }
    fn len(a: [f32; 3], b: [f32; 3]) -> f32 { ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2)).sqrt() }
    #[test]
    fn nearest_first_finds_what_the_sweeps_found() {
        let (verts, pos) = sheet(24);
        let mut start = vec![f32::MAX; verts.len()];start[5 * 24 + 7] = 0.;start[17 * 24 + 15] = 0.;
        // As the sweeps were, until nothing changed.
        let mut want = start.clone();
        loop { let mut changed = false;
            for (i, v) in verts.iter().enumerate() { let Some(p) = pos[i] else { continue; };
                for &k in &v.nbr { let Some(q) = pos[k as usize] else { continue; };if want[k as usize] == f32::MAX { continue; }
                    let c = want[k as usize] + len(p, q);if c < want[i] - 1e-5 { want[i] = c;changed = true; } } }
            if !changed { break; } }
        let reach = 0.10;let mut got = start.clone();spread_near(&verts, &pos, &mut got, reach);
        for i in 0..got.len() {
            if pos[i].is_none() { continue; }
            if want[i] <= reach - 1e-3 { assert!((got[i] - want[i]).abs() < 1e-3, "{i}: {} {}", got[i], want[i]); }
            if want[i] > reach + 1e-3 { assert_eq!(got[i], f32::MAX, "{i}"); }
        }
    }
    #[test]
    fn the_tent_is_what_the_sweeps_made() {
        let (verts, pos) = sheet(24);
        let mut start = vec![0f32; verts.len()];start[5 * 24 + 7] = 0.06;start[6 * 24 + 8] = 0.05;start[17 * 24 + 15] = 0.03;
        let mut want = start.clone();
        loop { let mut changed = false;
            for (i, v) in verts.iter().enumerate() { let Some(p) = pos[i] else { continue; };
                for &k in &v.nbr { let Some(q) = pos[k as usize] else { continue; };
                    let c = want[k as usize] - 1.5 * len(p, q);if c > want[i] + 1e-5 { want[i] = c;changed = true; } } }
            if !changed { break; } }
        let mut got = start.clone();spread_tent(&verts, &pos, &mut got, 1.5);
        for i in 0..got.len() { assert!((got[i] - want[i]).abs() < 1e-3, "{i}: {} {}", got[i], want[i]); }
    }
}

#[cfg(test)]
mod refine_tests {
    use super::{mid_weights, split_triangles};
    fn area2(p: &[[f32; 2]], t: &[u32]) -> f32 {
        t.chunks_exact(3).map(|c| { let (a, b, d) = (p[c[0] as usize], p[c[1] as usize], p[c[2] as usize]);(b[0] - a[0]) * (d[1] - a[1]) - (b[1] - a[1]) * (d[0] - a[0]) }).sum()
    }
    fn with_mids(mut p: Vec<[f32; 2]>, made: &[(u32, u32)]) -> Vec<[f32; 2]> {
        for (a, b) in made { let (x, y) = (p[*a as usize], p[*b as usize]);p.push([(x[0] + y[0]) * 0.5, (x[1] + y[1]) * 0.5]); }
        p
    }
    #[test]
    fn a_marked_triangle_is_cut_in_four_and_its_neighbour_keeps_no_crack() {
        // Two triangles sharing edge 1-2; only the first has all three corners marked.
        let p = vec![[0., 0.], [1., 0.], [0., 1.], [1., 1.]];
        let t = [0, 1, 2, 2, 1, 3];
        let (out, made) = split_triangles(&t, &[true, true, true, false]);
        assert_eq!(made.len(), 3);
        assert_eq!(out.len() / 3, 4 + 2);
        let q = with_mids(p.clone(), &made);
        assert!((area2(&q, &out) - area2(&p, &t)).abs() < 1e-6, "area and winding kept");
        // Every edge used once each way but the outline: no T junction left.
        let mut open = std::collections::HashMap::new();
        for c in out.chunks_exact(3) { for (a, b) in [(c[0], c[1]), (c[1], c[2]), (c[2], c[0])] { *open.entry((a, b)).or_insert(0) += 1; } }
        let outline = open.keys().filter(|(a, b)| !open.contains_key(&(*b, *a))).count();
        assert_eq!(outline, 6, "the square's four sides, two of them halved");
    }
    #[test]
    fn a_triangle_with_two_cut_edges_stays_whole() {
        // Marked fan round vertex 0 leaves triangle 1-2-3 with two cut edges (1-2 and 2-3 belong to marked triangles).
        let p = vec![[0., 0.], [2., 0.], [2., 2.], [0., 2.], [3., 1.], [1., 3.]];
        let t = [0, 1, 2, 0, 2, 3, 1, 4, 2, 2, 5, 3];
        let (out, made) = split_triangles(&t, &[true, true, true, true, false, false]);
        assert!((area2(&with_mids(p.clone(), &made), &out) - area2(&p, &t)).abs() < 1e-6);
        let (only, none) = split_triangles(&t, &[false; 6]);
        assert_eq!(only, t);assert!(none.is_empty());
    }
    #[test]
    fn middle_weights_stay_four_and_sum_to_one() {
        let (b, w) = mid_weights(&[1, 2, 3, 4], &[0.4, 0.3, 0.2, 0.1], &[1, 5, 6, 7], &[0.7, 0.1, 0.1, 0.1]);
        assert_eq!(b[0], 1);assert!((w.iter().sum::<f32>() - 1.).abs() < 1e-5);
    }
}

#[cfg(test)]
mod skin_grid_tests {
    use super::*;
    #[test]
    fn grid_depth_is_the_scan_depth() {
        // A rough sheet of skin with repeated points (equal distances) and queries in it, beside it and far off.
        let mut seed = 12345u64;let mut rnd = || { seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);((seed >> 33) as f32) / (1u64 << 31) as f32 };
        let mut skin = Vec::new();
        for _ in 0..3000 { let p = [rnd() * 0.4 - 0.2, rnd() * 0.4 - 0.2, rnd() * 0.05];skin.push(SkinNow { p, n: [0., 0., 1.], rest: rnd() }); }
        for k in 0..50 { let p = skin[k].p;skin.push(SkinNow { p, n: [0., 1., 0.], rest: 0.5 }); }
        let grid = SkinGrid::new(&skin);
        for _ in 0..2000 {
            let at = [rnd() * 0.8 - 0.4, rnd() * 0.8 - 0.4, rnd() * 0.4 - 0.2];
            assert_eq!(grid.depth(&skin, at), depth(&skin, at), "at {at:?}");
        }
        for k in 0..60 { let at = skin[k].p;assert_eq!(grid.depth(&skin, at), depth(&skin, at)); }
    }
}
