//! PhysX cloth kept out of her real skin (cloth_px). The body capsules (`dbone::body_proxy_capsules`) are thinner than
//! a stylised body: Raiden's gauze sleeves went through her thighs and her kimono panel through her shins while every
//! particle sat outside its capsule (user, 2026-11-21). Each frame her body mesh, thinned to one vertex in each
//! `THIN_M` cube, is posed with her skeleton's palette and put in a grid; a cloth particle nearer it than the margin (or
//! inside it) is pushed out along the skin's normal, never deeper than its own pose already was.
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use crate::pose::{Mat4, Skeleton};
use crate::session::SessionPart;

/// Her body mesh thinned to one vertex per cube this wide.
const THIN_M: f32 = 0.01;
/// Grid cells; a particle reads its own cell and the 26 round it, so skin up to this far is seen.
const CELL_M: f32 = 0.04;
/// Width of the Gaussian each skin vertex is read with (`SkinField::depth`).
const SIGMA_M: f32 = 0.01;
fn sigma() -> f32 {
    static S: std::sync::OnceLock<f32> = std::sync::OnceLock::new();
    *S.get_or_init(|| std::env::var("OK_CLOTH_PX_SKIN_SIGMA").ok().and_then(|v| v.parse().ok()).unwrap_or(SIGMA_M))
}

/// Her body part and the vertices kept of it (by its mesh and size).
struct Still { body: usize, verts: Vec<u32> }
static STILL: Mutex<Vec<(usize, usize, usize, Arc<Still>)>> = Mutex::new(Vec::new());
/// Per session: her skin posed this frame.
static FIELDS: Mutex<Option<HashMap<usize, Arc<SkinField>>>> = Mutex::new(None);

/// Her skin posed: positions and outward normals in her skeleton space, in cells of `CELL_M` (counting sort).
pub(crate) struct SkinField { p: Vec<[f32; 3]>, n: Vec<[f32; 3]>, lo: [i64; 3], size: [i64; 3], start: Vec<u32>, items: Vec<u32> }

fn point(m: &Mat4, p: [f32; 3]) -> [f32; 3] { std::array::from_fn(|i| m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3]) }
fn vector(m: &Mat4, p: [f32; 3]) -> [f32; 3] { std::array::from_fn(|i| m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2]) }
fn cell(p: [f32; 3]) -> [i64; 3] { p.map(|v| (v / CELL_M).floor() as i64) }

fn still(parts: &[SessionPart]) -> Option<Arc<Still>> {
    let (body, part) = parts.iter().enumerate().filter(|(_, p)| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none())
        .max_by_key(|(_, p)| p.rest_positions.len())?;
    let key = (parts.as_ptr() as usize, body, part.rest_positions.len());
    if let Some(e) = STILL.lock().unwrap().iter().find(|e| (e.0, e.1, e.2) == key) { return Some(e.3.clone()); }
    let mut taken = std::collections::HashSet::new();
    let verts: Vec<u32> = (0..part.rest_positions.len()).filter(|&j| {
        part.rest_normals.get(j).is_some_and(|n| n.iter().any(|v| *v != 0.)) && part.bone_idx.get(j).is_some() && part.weights.get(j).is_some()
            && taken.insert(part.rest_positions[j].map(|v| (v / THIN_M).floor() as i64))
    }).map(|j| j as u32).collect();
    if verts.is_empty() { return None; }
    let s = Arc::new(Still { body, verts });
    let mut kept = STILL.lock().unwrap();
    if kept.len() >= 16 { kept.remove(0); }
    kept.push((key.0, key.1, key.2, s.clone()));
    Some(s)
}

/// Poses her skin for this frame when any of her garments is PhysX cloth (`cloth_px::has_cloth`); before her garments are
/// skinned. `skel`: her body skeleton now.
pub(crate) fn prepare(session: usize, parts: &[SessionPart], skel: Option<&Skeleton>) {
    let field = if crate::cloth_px::has_cloth(session) { skel.and_then(|skel| build(parts, skel)) } else { None };
    let mut all = FIELDS.lock().unwrap();
    let map = all.get_or_insert_with(HashMap::new);
    match field { Some(f) => { map.insert(session, Arc::new(f)); } None => { map.remove(&session); } }
}

fn build(parts: &[SessionPart], skel: &Skeleton) -> Option<SkinField> {
    let still = still(parts)?;
    let part = &parts[still.body];
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return None; }
    let skins: Vec<Mat4> = worlds.iter().zip(&binds).map(|(w, b)| crate::pose::mat_mul_pub(w, b)).collect();
    let (mut p, mut n) = (Vec::with_capacity(still.verts.len()), Vec::with_capacity(still.verts.len()));
    for &j in &still.verts {
        let j = j as usize;
        let (b, w) = (part.bone_idx[j], part.weights[j]);
        let mut m = [[0f32; 4]; 4];
        let mut total = 0.;
        for k in 0..4 {
            let Some(s) = skins.get(b[k] as usize) else { continue };
            if w[k] <= 0. { continue; }
            total += w[k];
            for r in 0..4 { for c in 0..4 { m[r][c] += s[r][c] * w[k]; } }
        }
        if total < 0.5 { continue; }
        let q = vector(&m, part.rest_normals[j]);
        let l = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2]).sqrt();
        if l < 1e-6 { continue; }
        p.push(point(&m, part.rest_positions[j]));
        n.push([q[0] / l, q[1] / l, q[2] / l]);
    }
    if p.is_empty() { return None; }
    let (mut lo, mut hi) = ([i64::MAX; 3], [i64::MIN; 3]);
    for q in &p { let c = cell(*q); for a in 0..3 { lo[a] = lo[a].min(c[a]); hi[a] = hi[a].max(c[a]); } }
    let size = [hi[0] - lo[0] + 1, hi[1] - lo[1] + 1, hi[2] - lo[2] + 1];
    let cells = (size[0] * size[1] * size[2]) as usize;
    if cells > 1 << 22 { return None; }
    let index = |c: [i64; 3]| (((c[0] - lo[0]) * size[1] + (c[1] - lo[1])) * size[2] + (c[2] - lo[2])) as usize;
    let mut start = vec![0u32; cells + 1];
    for q in &p { start[index(cell(*q)) + 1] += 1; }
    for k in 1..=cells { start[k] += start[k - 1]; }
    let mut fill = start.clone();
    let mut items = vec![0u32; p.len()];
    for (i, q) in p.iter().enumerate() { let k = index(cell(*q)); items[fill[k] as usize] = i as u32; fill[k] += 1; }
    Some(SkinField { p, n, lo, size, start, items })
}

/// Her skin posed this frame, if `prepare` made it.
pub(crate) fn field(session: usize) -> Option<Arc<SkinField>> {
    FIELDS.lock().unwrap().as_ref().and_then(|m| m.get(&session).cloned())
}

pub(crate) fn forget(session: usize) {
    if let Some(m) = FIELDS.lock().unwrap().as_mut() { m.remove(&session); }
}

impl SkinField {
    /// How far `at` is out of her skin along it (below 0 inside) and the way out there: every skin vertex within a cell
    /// read, weighted by a Gaussian of its distance (`SIGMA_M`). Continuous as `at` moves: the nearest four alone, by
    /// inverse distance, jumped as one left the four and another came in, and the cloth pushed by it shook (Raiden's
    /// gauze, 1.7 -> 3.6 mm a frame, 2026-11-21). With how much it counts (0..1). None with no skin within a cell.
    pub(crate) fn depth(&self, at: [f32; 3]) -> Option<(f32, [f32; 3], f32)> {
        let c = cell(at);
        let cells = || (-1..=1i64).flat_map(|x| (-1..=1i64).flat_map(move |y| (-1..=1i64).map(move |z| [x, y, z])))
            .filter_map(|o| {
                let k = [c[0] + o[0] - self.lo[0], c[1] + o[1] - self.lo[1], c[2] + o[2] - self.lo[2]];
                if (0..3).any(|a| k[a] < 0 || k[a] >= self.size[a]) { return None; }
                let i = ((k[0] * self.size[1] + k[1]) * self.size[2] + k[2]) as usize;
                Some(&self.items[self.start[i] as usize..self.start[i + 1] as usize])
            });
        let dist2 = |q: [f32; 3]| (at[0] - q[0]).powi(2) + (at[1] - q[1]).powi(2) + (at[2] - q[2]).powi(2);
        // Weighted against the nearest (it counts 1): a point deep in her thigh, 3 cm from all her skin, reads it as
        // surely as one on it. One pass: the sums so far are scaled down whenever a nearer vertex turns up (this runs
        // several times a frame for every particle; two passes cost Raiden 40 fps, 2026-11-21).
        let (mut sum, mut weight, mut way) = (0f32, 0f32, [0f32; 3]);
        let mut nearest = CELL_M * CELL_M;
        let k2 = -0.5 / (sigma() * sigma());
        for items in cells() { for &s in items {
            let (q, n) = (self.p[s as usize], self.n[s as usize]);
            let d = dist2(q);
            if d > CELL_M * CELL_M { continue; }
            if d < nearest {
                let k = ((nearest - d) * k2).exp();
                sum *= k; weight *= k; for a in 0..3 { way[a] *= k; }
                nearest = d;
            }
            let w = ((d - nearest) * k2).exp();
            sum += w * ((at[0] - q[0]) * n[0] + (at[1] - q[1]) * n[1] + (at[2] - q[2]) * n[2]);
            weight += w;
            for a in 0..3 { way[a] += w * n[a]; }
        } }
        if weight <= 0. { return None; }
        let l = (way[0] * way[0] + way[1] * way[1] + way[2] * way[2]).sqrt();
        if l < 1e-6 || weight < 1e-6 { return None; }
        // How much the reading counts (0..1), fading out where the skin read faces both ways (between her thighs: no way
        // out) and as the nearest skin nears the reach; a cut-off there turned the push on and off as the cloth crossed it.
        let ramp = |e0: f32, e1: f32, x: f32| { let t = ((x - e0) / (e1 - e0)).clamp(0., 1.); t * t * (3. - 2. * t) };
        let trust = ramp(0.3, 0.7, l / weight) * (1. - ramp(CELL_M * 0.75, CELL_M, nearest.sqrt()));
        if trust <= 0. { return None; }
        Some((sum / weight, [way[0] / l, way[1] / l, way[2] / l], trust))
    }
}
