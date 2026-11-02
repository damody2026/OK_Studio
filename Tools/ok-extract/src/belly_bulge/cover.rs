//! Her clothes kept over her skin (user, 2026-11-02: her nipples and swollen bust came through her shirt, and so did her
//! belly lifted over his penis). The original binds her clothes to her body's bones (AssignedAnotherWeights), so they follow
//! her shape sliders; what moves her skin alone (the belly `wrap_deltas` lifts, her nipples) they do not. Each frame the
//! skin that pokes out (her breasts, and the skin lifted over him) pushes the cloth over it out along its normal to `margin`
//! past it, fading over `REACH_M` across the skin: a garment on her body skeleton as a morph (`cover_deltas`), one with
//! its own rig as it is skinned on the CPU (`CoverField::cover`, while the scene has it on: `set_cover`; the private GPU
//! route skins its own copy of the rest mesh, so the scene draws those from their CPU vertices then).
use super::*;
use crate::pose::Skeleton;

/// How far across the skin one place pushes the cloth (its push fades to nothing there), and the cells it is looked up in.
const REACH_M: f32 = 0.035;
/// Cloth further under the skin as it was (not lifted) is on her far side, or under another garment's skin: left alone.
const UNDER_M: f32 = 0.015;
/// Her skin is thinned to one place in each cube this wide (the nearest a garment vertex looks is `REACH_M`).
const THIN_M: f32 = 0.006;
/// Bones whose skin pushes every frame (part of a name): her breasts and nipples.
const PUSHING: [&str; 2] = ["bust", "bnip"];

/// How far past the skin each garment is kept (its role): underwear nearest, the rest over it.
fn margin(role: &str) -> f32 {
    match role { "clothes_bra" | "clothes_shorts" | "clothes_panst" | "clothes_socks" | "clothes_gloves" => 0.002, _ => 0.005 }
}
/// Garments that cover skin that pokes out (shoes cover none of it).
fn covers(role: &str) -> bool { role.starts_with("clothes") && role != "clothes_shoes" }

/// The sessions whose clothes are kept over their skin now (the H scene turns it on), with her skin's wrap moves.
static COVER: std::sync::Mutex<Vec<(usize, Vec<(u32, [f32; 6])>)>> = std::sync::Mutex::new(Vec::new());
/// Keeps (or stops keeping) the garments with their own rig of `session` over her skin as they are skinned; `body_moves`
/// her body's skin moves now (`wrap_deltas`). The garments it moves (session part indices: to be drawn from their CPU vertices).
pub fn set_cover(session: &OkSession, on: bool, body_moves: Vec<(u32, [f32; 6])>) -> Vec<usize> {
    let key = session as *const OkSession as usize;
    let mut all = COVER.lock().unwrap();all.retain(|(k, _)| *k != key);
    if !on { return Vec::new(); }
    // Only the garments that reach her pushing skin (every eighth vertex as its renderer draws it, against the cells it
    // lists): the others stay on the GPU route.
    let field = session.body_skel.as_ref().and_then(|skel| CoverField::new(&session.parts, skel, &body_moves));
    all.push((key, body_moves));
    let Some(field) = field else { return Vec::new(); };
    let head = session.head_full_posed.as_ref().or(session.head_skel.as_ref());
    let clothes = session.clothes_dynamic_runtime.as_ref().map(|(_, state)| &state.skel);
    session.parts.iter().enumerate().filter(|(_, p)| p.render_visible && covers(&p.role)).filter_map(|(i, p)| {
        let runtime = p.runtime_accessory.as_ref()?;
        let (mesh, palette) = runtime.export_skin_palette(runtime.skin_body(session.body_skel.as_ref(), clothes), head)?;
        let reaches = (0..mesh.rest_positions.len()).step_by(8).any(|j| {
            let (Some(b), Some(w)) = (mesh.bone_idx.get(j), mesh.weights.get(j)) else { return false; };
            let mut c = [0f32; 3];
            for (b, w) in b.iter().zip(w) { if let Some(m) = palette.get(*b as usize).filter(|_| *w > 0.) { let q = point(m, mesh.rest_positions[j]);for a in 0..3 { c[a] += q[a] * w; } } }
            field.at(c).is_some()
        });
        reaches.then_some(i)
    }).collect()
}

static NEIGHBOURS: std::sync::Mutex<Vec<(usize, usize, std::sync::Arc<Vec<Vec<u32>>>)>> = std::sync::Mutex::new(Vec::new());
/// Each vertex's neighbours along a garment's mesh (copies of one place split at UV seams count as one another's).
fn neighbours(indices: &[u32], rest: &[[f32; 3]]) -> std::sync::Arc<Vec<Vec<u32>>> {
    let key = (indices.as_ptr() as usize, rest.len());
    let mut cache = NEIGHBOURS.lock().unwrap();
    if let Some((_, _, n)) = cache.iter().find(|(a, b, _)| (*a, *b) == key) { return n.clone(); }
    let mut nbr: Vec<Vec<u32>> = vec![Vec::new(); rest.len()];
    for t in indices.chunks_exact(3) {
        for (a, b) in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] {
            if (a as usize) < nbr.len() && (b as usize) < nbr.len() { nbr[a as usize].push(b);nbr[b as usize].push(a); }
        }
    }
    let weld = |p: [f32; 3]| p.map(|v| (v * 5000.).round() as i64);
    let mut same: HashMap<[i64; 3], Vec<u32>> = HashMap::new();
    for (j, p) in rest.iter().enumerate() { same.entry(weld(*p)).or_default().push(j as u32); }
    for group in same.values().filter(|g| g.len() > 1) { for &a in group { for &b in group { if a != b { nbr[a as usize].push(b); } } } }
    for n in &mut nbr { n.sort_unstable();n.dedup(); }
    let n = std::sync::Arc::new(nbr);
    if cache.len() > 64 { cache.clear(); }
    cache.push((key.0, key.1, n.clone()));
    n
}

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn dot(a: [f32; 3], b: [f32; 3]) -> f32 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }

/// Her skin that pushes this frame: where it was (not lifted), where it is, its normal; in cells `REACH_M` wide.
/// Each cell lists the skin in it and in the cells round it, so a garment vertex looks in its own cell only; `lo`/`hi`
/// bound the cells that list any.
pub struct CoverField { skin: Vec<([f32; 3], [f32; 3], [f32; 3])>, grid: Vec<Vec<u32>>, lo: [i64; 3], hi: [i64; 3] }

impl CoverField {
    /// Her pushing skin posed on `skel` (her body skeleton now), lifted by `body_moves`.
    fn new(parts: &[SessionPart], skel: &Skeleton, body_moves: &[(u32, [f32; 6])]) -> Option<CoverField> {
        let body = parts.iter().filter(|p| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none())
            .max_by_key(|p| (p.blend_shapes.iter().any(|(n, _)| is_bulge(n)), p.rest_positions.len()))?;
        let (worlds, binds) = crate::skel_export::palettes(skel, body);
        if worlds.is_empty() { return None; }
        let pushing: Vec<bool> = skel.names.iter().map(|n| { let n = n.to_ascii_lowercase();PUSHING.iter().any(|s| n.contains(s)) }).collect();
        let unit = |v: [f32; 3]| { let l = dot(v, v).sqrt();(l > 1e-6).then(|| [v[0] / l, v[1] / l, v[2] / l]) };
        let moved: HashMap<u32, [f32; 6]> = body_moves.iter().copied().collect();
        let mut skin = Vec::new();let mut taken: std::collections::HashSet<[i64; 3]> = std::collections::HashSet::new();
        for j in 0..body.rest_positions.len() {
            let delta = moved.get(&(j as u32));
            let on_bust = body.bone_idx.get(j).zip(body.weights.get(j)).is_some_and(|(b, w)| b.iter().zip(w).any(|(b, w)| *w > 0.3 && pushing.get(*b as usize) == Some(&true)));
            if delta.is_none() && !on_bust { continue; }
            let Some((m, _, _)) = skin_of(body, j, &worlds, &binds, &[], &[]) else { continue; };
            let r = body.rest_positions[j];let Some(rn) = body.rest_normals.get(j) else { continue; };
            let d = delta.copied().unwrap_or([0.; 6]);
            let p0 = point(&m, r);let p = point(&m, [r[0] + d[0], r[1] + d[1], r[2] + d[2]]);
            let o = point(&m, [0.; 3]);let q = point(&m, [rn[0] + d[3], rn[1] + d[4], rn[2] + d[5]]);
            let Some(n) = unit(sub(q, o)) else { continue; };
            if !taken.insert(p.map(|v| (v / THIN_M).floor() as i64)) { continue; }
            skin.push((p0, p, n));
        }
        if skin.is_empty() { return None; }
        // In every cell from where the skin was to where it is: the cloth over it lies back where it was. The cells, a box
        // of them round all the skin (a dense grid: a hash map of them cost milliseconds a frame).
        let path = |s: ([f32; 3], [f32; 3], [f32; 3])| {
            let way = sub(s.1, s.0);let steps = (dot(way, way).sqrt() / (REACH_M * 0.5)).ceil() as usize;
            (0..=steps).map(move |k| { let f = k as f32 / steps.max(1) as f32;cell([s.0[0] + way[0] * f, s.0[1] + way[1] * f, s.0[2] + way[2] * f]) })
        };
        let (mut lo, mut hi) = ([i64::MAX; 3], [i64::MIN; 3]);
        for s in &skin { for c in path(*s) { for a in 0..3 { lo[a] = lo[a].min(c[a] - 1);hi[a] = hi[a].max(c[a] + 1); } } }
        let size: Vec<usize> = (0..3).map(|a| (hi[a] - lo[a] + 1) as usize).collect();
        if size.iter().product::<usize>() > 1 << 20 { return None; }
        let mut grid: Vec<Vec<u32>> = vec![Vec::new(); size.iter().product()];
        let mut cells: Vec<usize> = Vec::new();
        for (i, s) in skin.iter().enumerate() {
            cells.clear();
            for c in path(*s) {
                for a in -1..=1 { for b in -1..=1 { for e in -1..=1 {
                    cells.push((((c[0] + a - lo[0]) as usize * size[1]) + (c[1] + b - lo[1]) as usize) * size[2] + (c[2] + e - lo[2]) as usize);
                } } }
            }
            cells.sort_unstable();cells.dedup();
            for &c in &cells { grid[c].push(i as u32); }
        }
        Some(CoverField { skin, grid, lo, hi })
    }

    /// For a session whose clothes are kept over her skin now (`set_cover`), her pushing skin on `skel`; None otherwise.
    pub(crate) fn for_frame(session: usize, parts: &[SessionPart], skel: Option<&Skeleton>) -> Option<CoverField> {
        let moves = COVER.lock().ok()?.iter().find(|(k, _)| *k == session)?.1.clone();
        CoverField::new(parts, skel?, &moves)
    }

    /// A garment with its own rig, just skinned on the CPU (`positions`, her skeleton space): moved out over her skin.
    pub(crate) fn cover(&self, _index: usize, part: &SessionPart, positions: &mut [[f32; 3]]) {
        if !covers(&part.role) || part.runtime_accessory.is_none() || positions.len() != part.rest_positions.len() { return; }
        let nbr = neighbours(&part.indices, &part.rest_positions);
        let Some(push) = self.pushes(margin(&part.role), positions, &nbr) else { return; };
        for (p, v) in positions.iter_mut().zip(push) { for a in 0..3 { p[a] += v[a]; } }
    }

    /// The skin listed for the cell `c` is in (None outside the box).
    fn at(&self, c: [f32; 3]) -> Option<&Vec<u32>> {
        let k = cell(c);
        if (0..3).any(|a| k[a] < self.lo[a] || k[a] > self.hi[a]) { return None; }
        let (h, w) = ((self.hi[1] - self.lo[1] + 1) as usize, (self.hi[2] - self.lo[2] + 1) as usize);
        self.grid.get((((k[0] - self.lo[0]) as usize * h) + (k[1] - self.lo[1]) as usize) * w + (k[2] - self.lo[2]) as usize).filter(|l| !l.is_empty())
    }

    /// How far each of `positions` (a garment posed, her skeleton space) moves to stay `keep` past her skin, evened over
    /// the cloth round it (so a nipple lifts a little tent of cloth and not one vertex).
    fn pushes(&self, keep: f32, positions: &[[f32; 3]], nbr: &[Vec<u32>]) -> Option<Vec<[f32; 3]>> {
        let mut push: Vec<[f32; 3]> = vec![[0.; 3]; positions.len()];
        let mut any = false;
        for (j, &c) in positions.iter().enumerate() {
            let Some(list) = self.at(c) else { continue; };
            let mut best = 0f32;let mut way = [0f32; 3];
            {
                for &i in list {
                    let (p0, p, n) = self.skin[i as usize];
                    // Cloth behind the skin as it was: her far side, or under it.
                    if dot(sub(c, p0), n) < -UNDER_M { continue; }
                    let g = sub(c, p);let h = dot(g, n);let across = dot(g, g) - h * h;
                    if across >= REACH_M * REACH_M { continue; }
                    let t = 1. - across.sqrt() / REACH_M;let w = t * t * (3. - 2. * t);
                    let need = (keep - h) * w;
                    if need > best { best = need;way = n; }
                }
            }
            if best > 0. { push[j] = [way[0] * best, way[1] * best, way[2] * best];any = true; }
        }
        if !any { return None; }
        // Only the cloth round what moved: four rings out from it.
        let mut near: Vec<u32> = (0..push.len() as u32).filter(|&j| dot(push[j as usize], push[j as usize]) > 0.).collect();
        for _ in 0..4 {
            let mut ring: Vec<u32> = near.iter().flat_map(|&j| nbr.get(j as usize).into_iter().flatten().copied()).chain(near.iter().copied()).collect();
            ring.sort_unstable();ring.dedup();near = ring;
            let was: Vec<[f32; 3]> = near.iter().map(|&j| push[j as usize]).collect();
            let at: HashMap<u32, usize> = near.iter().enumerate().map(|(i, &j)| (j, i)).collect();
            for (i, &j) in near.iter().enumerate() {
                let Some(list) = nbr.get(j as usize).filter(|l| !l.is_empty()) else { continue; };
                let mut s = [0f32; 3];for &k in list { let v = at.get(&k).map_or(push[k as usize], |&q| was[q]);for a in 0..3 { s[a] += v[a]; } }
                let f = 0.6 / list.len() as f32;let avg = [s[0] * f, s[1] * f, s[2] * f];
                if dot(avg, avg) > dot(was[i], was[i]) { push[j as usize] = avg; }
            }
        }
        Some(push)
    }

}

/// A line to the log}

fn cell(p: [f32; 3]) -> [i64; 3] { p.map(|v| (v / REACH_M).floor() as i64) }

/// The moves of her garments on her body skeleton this frame (a morph each): for each (session part index), its vertex
/// index and move in the mesh's own space (Unity metres). `body_moves` are her body's skin moves now (`wrap_deltas`).
pub fn cover_deltas(session: &OkSession, body_moves: &[(u32, [f32; 6])]) -> Vec<(usize, Vec<(u32, [f32; 3])>)> {
    let Some(skel) = session.body_skel.as_ref() else { return Vec::new(); };
    if !session.parts.iter().any(|p| p.render_visible && covers(&p.role) && p.skel_kind == 1 && p.runtime_accessory.is_none()) { return Vec::new(); }
    let Some(field) = CoverField::new(&session.parts, skel, body_moves) else { return Vec::new(); };
    let mut out = Vec::new();
    for (pi, part) in session.parts.iter().enumerate() {
        if !part.render_visible || !covers(&part.role) { continue; }
        // Garments with their own rig are moved as they are skinned (CoverField::cover).
        if part.runtime_accessory.is_some() || part.skel_kind != 1 { continue; }
        let (w, b) = crate::skel_export::palettes(skel, part);
        let palette: Vec<Mat4> = w.iter().zip(&b).map(|(w, b)| mat_mul_pub(w, b)).collect();
        let (rest, weights, bones) = (&part.rest_positions, &part.weights, &part.bone_idx);
        if palette.is_empty() || weights.len() != rest.len() || bones.len() != rest.len() { continue; }
        let mats: Vec<Option<Mat4>> = (0..rest.len()).map(|j| {
            let mut m = [[0f32; 4]; 4];let mut total = 0.;
            for (b, w) in bones[j].iter().zip(&weights[j]) {
                let Some(p) = palette.get(*b as usize).filter(|_| *w > 0.) else { continue; };
                for r in 0..4 { for c in 0..4 { m[r][c] += p[r][c] * w; } }total += w;
            }
            (total > 0.5).then_some(m)
        }).collect();
        let posed: Vec<[f32; 3]> = mats.iter().zip(rest).map(|(m, r)| m.map_or([f32::MAX; 3], |m| point(&m, *r))).collect();
        let nbr = if part.rest_positions.len() == rest.len() { neighbours(&part.indices, &part.rest_positions) } else { std::sync::Arc::new(Vec::new()) };
        let Some(push) = field.pushes(margin(&part.role), &posed, &nbr) else { continue; };
        let mut moves = Vec::new();
        for (j, v) in push.into_iter().enumerate() {
            let Some(m) = mats[j] else { continue; };
            if dot(v, v) < 0.0001 * 0.0001 { continue; }
            // Back into the mesh's space (the posed skin's inverse, as the morph is skinned).
            let inv = mat_inv_pub(&m);let o = point(&inv, [0.; 3]);let a = point(&inv, v);
            moves.push((j as u32, [a[0] - o[0], a[1] - o[1], a[2] - o[2]]));
        }
        if !moves.is_empty() { out.push((pi, moves)); }
    }
    out
}
