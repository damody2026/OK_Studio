//! Her clothes kept over her skin (user, 2026-11-02: her nipples and swollen bust came through her shirt, and so did her
//! belly lifted over his penis). The original binds her clothes to her body's bones (AssignedAnotherWeights), so they follow
//! her shape sliders; what moves her skin alone (the belly `wrap_deltas` lifts, her nipples) they do not. Each frame the
//! skin that pokes out (her breasts, and the skin lifted over him) pushes the cloth over it out along its normal to `margin`
//! past it, fading over `REACH_M` across the skin: a garment on her body skeleton as a morph (`cover_deltas`), one with
//! its own rig as it is skinned on the CPU (`CoverField::cover`, while the scene has it on: `set_cover`; the private GPU
//! route skins its own copy of the rest mesh, so the scene draws those from their CPU vertices then).
use super::*;
use crate::pose::Skeleton;

/// Cloth this near her skin moves with it as it swells (`CoverField::follows`), all of it within `HUG_M`.
const FOLLOW_M: f32 = 0.03;
/// Each garment's cloth vertices and the skin they follow (by its neighbour table), found the first time it is pushed.
static FOLLOW_MAP: std::sync::LazyLock<std::sync::Mutex<HashMap<usize, std::sync::Arc<Vec<([(u32, f32); 4], f32)>>>>> = std::sync::LazyLock::new(Default::default);
/// How far across the skin one place pushes the cloth (its push fades to nothing there), and the cells it is looked up in.
const REACH_M: f32 = 0.025;
/// Her breasts' push fades over this (they lift the cloth a little; the width lifted skin needs tented a shirt).
const BUST_REACH_M: f32 = 0.015;
/// The farthest cloth her unmoved skin pushes: `BUST_REACH_M` across it, `UNDER_M` behind it or the margin before it.
const NEAR_M: f32 = 0.022;
/// Over skin lifted this near (across the way it went) the cloth rises all the way: wider than a triangle of cloth, or the
/// ridge of the hill comes up between its corners.
const FULL_M: f32 = 0.012;
/// Where the cloth stops rising, across the way the skin went; the cells of `Lift`.
const LIFT_REACH_M: f32 = 0.03;
/// Cloth this far under her belly as it was is on her back (she is thicker than this, cloth on her front lies nearer).
const FAR_M: f32 = 0.06;
/// Cloth further under the skin as it was (not lifted) is on her far side, or under another garment's skin: left alone.
const UNDER_M: f32 = 0.015;
/// Her skin is thinned to one place in each cube this wide (the nearest a garment vertex looks is `REACH_M`).
const THIN_M: f32 = 0.006;
/// Her breasts away from her nipples, still, are thinned to this (a smooth surface: the chord sags 0.2 mm over it): each cloth
/// vertex there looks through a quarter as much skin (6 mm cost 10 ms of the frame for one shirt, every frame).
const BUST_THIN_M: f32 = 0.012;
/// How far moved skin must have swelled out along its normal to push the cloth.
const OUT_M: f32 = 0.003;
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
    // Kept on as it already is, with no skin moved (every character's own cover, before each pose: AKKPreviewActor::
    // KeepClothCoverCpu): nothing to work out again, and no garments newly reached.
    if on && body_moves.is_empty() {
        let key = session as *const OkSession as usize;
        if COVER.lock().unwrap().iter().any(|(k, m)| *k == key && m.is_empty()) { return Vec::new(); }
    }
    let field = if on { session.body_skel.as_ref().and_then(|skel| CoverField::new(&session.parts, skel, &body_moves)) } else { None };
    keep_cover(session, on, body_moves, field.as_ref())
}

/// `set_cover` with her pushing skin already worked out (the wrap worker's).
pub fn keep_cover(session: &OkSession, on: bool, body_moves: Vec<(u32, [f32; 6])>, field: Option<&CoverField>) -> Vec<usize> {
    let _trace = crate::native_profile::Scope::new(54);
    let key = session as *const OkSession as usize;
    let mut all = COVER.lock().unwrap();all.retain(|(k, _)| *k != key);
    if !on { return Vec::new(); }
    // Only the garments that reach her pushing skin (every eighth vertex as its renderer draws it, against the cells it
    // lists); while none does they all stay on the GPU route.
    all.push((key, body_moves));drop(all);
    let Some(field) = field else { return Vec::new(); };
    let head = session.head_full_posed.as_ref().or(session.head_skel.as_ref());
    let clothes = session.clothes_dynamic_runtime.as_ref().map(|(_, state)| &state.skel);
    // Each garment's palette on its own worker: one after another they took 0.56 ms of the game thread each frame
    // (BellyWrapTake, trace EGalPerf19 after he came). The order of the list stays the parts' order.
    use rayon::prelude::*;
    let own: Vec<usize> = session.parts.iter().enumerate().filter(|(_, p)| p.render_visible && covers(&p.role) && p.runtime_accessory.is_some()).map(|(i, _)| i).collect();
    // Once one reaches, the same garments are kept on the CPU for REACH_HOLD frames before they are looked at again: the
    // test (a palette per garment) was most of BellyWrapTake's 0.31 ms a frame (2026-11-13). Not reaching is still looked at
    // every frame, so a garment goes to the CPU the frame her skin reaches it; one left there a few frames longer has no
    // push to draw and looks the same.
    {
        let mut held = REACH_HELD.lock().unwrap();
        if let Some(e) = held.iter_mut().find(|e| e.0 == key) {
            if e.1 > 0 && e.2 == own { e.1 -= 1; return e.3.clone(); }
        }
    }
    let reached: Vec<usize> = crate::session::native_parallel_work(|| own.par_iter().filter_map(|&i| {
        let runtime = session.parts[i].runtime_accessory.as_ref()?;
        let (mesh, palette) = runtime.export_skin_palette(runtime.skin_body(session.body_skel.as_ref(), clothes), head)?;
        let reaches = (0..mesh.rest_positions.len()).step_by(8).any(|j| {
            let (Some(b), Some(w)) = (mesh.bone_idx.get(j), mesh.weights.get(j)) else { return false; };
            let mut c = [0f32; 3];
            for (b, w) in b.iter().zip(w) { if let Some(m) = palette.get(*b as usize).filter(|_| *w > 0.) { let q = point(m, mesh.rest_positions[j]);for a in 0..3 { c[a] += q[a] * w; } } }
            field.at(c).is_some()
        });
        reaches.then_some(i)
    }).collect());
    // One reaching: all of them on the CPU. Garments laid on one another (fishnet over tights, the same tights in two
    // slots) drawn one from the CPU and one from the GPU fought for depth all down her legs (user, 2026-11-11).
    let mut held = REACH_HELD.lock().unwrap();held.retain(|e| e.0 != key);
    if reached.is_empty() { return reached; }
    // COVER_SPLIT (ok.HScene.ClothCoverSplit, off by default): only the garments that reach go to the CPU, the rest stay
    // on the GPU route (a fully dressed heroine's 32 garments skinned on the CPU and streamed every frame held her at
    // 80 FPS, 2026-11-13); the layered-garment fight above is what it must be checked against.
    let out = if COVER_SPLIT.load(std::sync::atomic::Ordering::Relaxed) { reached } else { own.clone() };
    if held.len() >= 16 { held.remove(0); }
    held.push((key, REACH_HOLD, own, out.clone()));
    out
}
/// Only the garments that reach her pushing skin drawn from the CPU (`keep_cover`); set by `ok_cover_split`.
static COVER_SPLIT: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
pub(crate) fn set_cover_split(on: bool) { COVER_SPLIT.store(on, std::sync::atomic::Ordering::Relaxed); }
/// Frames a reaching garment set is kept before the test again (`keep_cover`).
const REACH_HOLD: u32 = 8;
/// Per session: the frames left before the test again, her garments looked at, and those kept on the CPU.
static REACH_HELD: std::sync::Mutex<Vec<(usize, u32, Vec<usize>, Vec<usize>)>> = std::sync::Mutex::new(Vec::new());

/// Per garment (its neighbour table): the frame count, the vertices `push_at` moved last frame, its vertex count.
static WARM: std::sync::LazyLock<std::sync::Mutex<HashMap<usize, (u32, Vec<u32>, usize)>>> = std::sync::LazyLock::new(Default::default);
/// OK_COVER_WARM=<n>: each frame `push_at` looks at last frame's pushed cloth, two rings round it and one in n of the rest
/// (0 or 1, the default: every vertex every frame; the approximation pushed cloth late, the user turned it back, 2026-11-10).
fn warm_stride() -> usize { std::env::var("OK_COVER_WARM").ok().and_then(|v| v.parse().ok()).unwrap_or(0) }

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
/// CoverField::prepare's reading of her skeleton.
pub(crate) struct CoverPrep { still: std::sync::Arc<CoverStill>, worlds: Vec<Mat4>, binds: Vec<Mat4>, moves: Vec<(u32, [f32; 6])> }

/// `lifted`: for each of `skin`, whether `Lift` raises the cloth over it (moved along its one way, on her front); the rest
/// of the moved skin pushes the cloth out along its own normal (`push_at`).
/// `follow`: her skin that swelled out this frame (body vertex, how far it went, her skeleton space): the cloth hugging it
/// moves as far (`follows`). `still`, `skins`: to pose all her skin once, for a garment seen the first time.
pub struct CoverField { skin: Vec<([f32; 3], [f32; 3], [f32; 3])>, lifted: Vec<bool>, grid: Vec<Vec<u32>>, lo: [i64; 3], hi: [i64; 3], lift: Option<Lift>,
    follow: Vec<Option<[f32; 3]>>, follows_any: bool, still: std::sync::Arc<CoverStill>, skins: Vec<Mat4>, posed: std::sync::OnceLock<Vec<[f32; 3]>> }

/// Her skin that was lifted, seen along the way it went (`way`): where across it (in `side`) and how high along it now, one
/// for each `THIN_M` square, the highest; in squares `LIFT_REACH_M` wide, each listing what is in it and round it. `belly`:
/// the plane her skin lay in (height along `way` = a * across + b * across + c): the skin slides across as it lifts, so what
/// it was where it came from says nothing of what lies under the cloth it now reaches. Cloth rises along that one way only, so seen from there no triangle of it turns over however tall the hill:
/// pushed along the skin's normals a hill of 12 cm turned them over, and what stops that left the hill through the kimono
/// (user, 2026-11-07).
struct Lift { way: [f32; 3], side: [[f32; 3]; 2], skin: Vec<([f32; 2], f32, f32)>, belly: [f32; 3], grid: Vec<Vec<u32>>, lo: [i64; 2], hi: [i64; 2] }

impl CoverField {
    /// Her pushing skin posed on `skel` (her body skeleton now), lifted by `body_moves`.
    fn new(parts: &[SessionPart], skel: &Skeleton, body_moves: &[(u32, [f32; 6])]) -> Option<CoverField> {
        let still = cover_still(parts, skel)?;
        let (worlds, binds) = crate::skel_export::palettes(skel, &parts[still.body]);
        if worlds.is_empty() { return None; }
        CoverField::from_still(&still, &worlds, &binds, body_moves)
    }

    /// As `new`, reading nothing of the session.
    fn from_still(still: &std::sync::Arc<CoverStill>, worlds: &[Mat4], binds: &[Mat4], body_moves: &[(u32, [f32; 6])]) -> Option<CoverField> {
        let skins: Vec<Mat4> = worlds.iter().zip(binds).map(|(w, b)| mat_mul_pub(w, b)).collect();
        let unit = |v: [f32; 3]| { let l = dot(v, v).sqrt();(l > 1e-6).then(|| [v[0] / l, v[1] / l, v[2] / l]) };
        let moved: HashMap<u32, [f32; 6]> = body_moves.iter().copied().collect();
        let mut skin = Vec::new();let mut taken: std::collections::HashSet<([i64; 3], bool)> = std::collections::HashSet::new();
        let mut lifted: Vec<([f32; 3], [f32; 3])> = Vec::new();
        // By her body vertex (a hash map of them was looked up four times for every cloth vertex hugging her: follows).
        let mut follow: Vec<Option<[f32; 3]>> = vec![None; still.rest.len()];let mut follows_any = false;
        for j in 0..still.rest.len() {
            let delta = moved.get(&(j as u32));
            let on_bust = still.on_bust[j];
            if delta.is_none() && !on_bust { continue; }
            let (Some(bones), Some(weights)) = (still.bones.get(j), still.weights.get(j)) else { continue; };
            let mut m = [[0f32; 4]; 4];
            for (b, w) in bones.iter().zip(weights) {
                let Some(s) = skins.get(*b as usize) else { continue; };if *w <= 0. { continue; }
                for r in 0..4 { for c in 0..4 { m[r][c] += s[r][c] * w; } }
            }
            let r = still.rest[j];let Some(rn) = still.normals.get(j) else { continue; };
            let d = delta.copied().unwrap_or([0.; 6]);
            let p0 = point(&m, r);let p = point(&m, [r[0] + d[0], r[1] + d[1], r[2] + d[2]]);
            let o = point(&m, [0.; 3]);let q = point(&m, [rn[0] + d[3], rn[1] + d[4], rn[2] + d[5]]);
            let Some(n) = unit(sub(q, o)) else { continue; };
            // Moved skin only where it swells out (his bulge under her belly): round him at her crotch it is drawn aside
            // and in, and cloth pushed off that tore into black folds.
            // Against her normal as it was: on the flank of the hill the normal now lies across the move.
            let Some(n0) = unit(sub(point(&m, *rn), o)) else { continue; };
            if dot(sub(p, p0), n0) >= OUT_M { lifted.push((p0, p)); }
            if delta.is_some() && dot(sub(p, p0), n0) > 0. { follow[j] = Some(sub(p, p0));follows_any = true; }
            // Moved skin is followed (`follows`) and lifted over (`Lift`), not pushed off along its normal.
            if p != p0 { continue; }
            if !on_bust && dot(sub(p, p0), n) < OUT_M { continue; }
            let fine = delta.is_some() || still.on_nip[j];let thin = if fine { THIN_M } else { BUST_THIN_M };
            if !taken.insert((p.map(|v| (v / thin).floor() as i64), fine)) { continue; }
            skin.push((p0, p, n));
        }
        if skin.is_empty() && !follows_any { return None; }
        let lift = Lift::new(&lifted);
        let lifted = vec![false; skin.len()];
        // In every cell from where the skin was to where it is: the cloth over it lies back where it was. The cells, a box
        // of them round all the skin (a dense grid: a hash map of them cost milliseconds a frame).
        let path = |s: ([f32; 3], [f32; 3], [f32; 3])| {
            let way = sub(s.1, s.0);let steps = (dot(way, way).sqrt() / (REACH_M * 0.5)).ceil() as usize;
            (0..=steps).map(move |k| { let f = k as f32 / steps.max(1) as f32;cell([s.0[0] + way[0] * f, s.0[1] + way[1] * f, s.0[2] + way[2] * f]) })
        };
        let (mut lo, mut hi) = ([i64::MAX; 3], [i64::MIN; 3]);
        for s in &skin { for c in path(*s) { for a in 0..3 { lo[a] = lo[a].min(c[a] - 1);hi[a] = hi[a].max(c[a] + 1); } } }
        if skin.is_empty() { (lo, hi) = ([0; 3], [0; 3]); }
        let size: Vec<usize> = (0..3).map(|a| (hi[a] - lo[a] + 1) as usize).collect();
        if size.iter().product::<usize>() > 1 << 20 { return None; }
        let mut grid: Vec<Vec<u32>> = vec![Vec::new(); size.iter().product()];
        let mut cells: Vec<usize> = Vec::new();
        for (i, s) in skin.iter().enumerate() {
            cells.clear();
            // Skin that did not move pushes only cloth within `BUST_REACH_M` across it and `UNDER_M` / the margin along it
            // (push_at): only the cells that near it, at most eight. Listed in all 27 round it, each cloth vertex at her
            // breasts went through some 150 of them: 2.4 ms a frame for one shirt, every character, every frame.
            if s.0 == s.1 {
                let c = cell(s.1);
                for a in -1..=1 { for b in -1..=1 { for e in -1..=1 {
                    let k = [c[0] + a, c[1] + b, c[2] + e];
                    let gap: f32 = (0..3).map(|x| { let (l, h) = (k[x] as f32 * REACH_M, (k[x] + 1) as f32 * REACH_M);let d = (l - s.1[x]).max(s.1[x] - h).max(0.);d * d }).sum();
                    if gap <= NEAR_M * NEAR_M { cells.push((((k[0] - lo[0]) as usize * size[1]) + (k[1] - lo[1]) as usize) * size[2] + (k[2] - lo[2]) as usize); }
                } } }
                for &c in &cells { grid[c].push(i as u32); }
                continue;
            }
            for c in path(*s) {
                for a in -1..=1 { for b in -1..=1 { for e in -1..=1 {
                    cells.push((((c[0] + a - lo[0]) as usize * size[1]) + (c[1] + b - lo[1]) as usize) * size[2] + (c[2] + e - lo[2]) as usize);
                } } }
            }
            cells.sort_unstable();cells.dedup();
            for &c in &cells { grid[c].push(i as u32); }
        }
        Some(CoverField { skin, lifted, grid, lo, hi, lift, follow, follows_any, still: still.clone(), skins, posed: std::sync::OnceLock::new() })
    }

    /// What `build` needs, read off her skeleton before her clothes chains move (they write their own bones into it):
    /// the field is then built while they run (OkSession::finish_paired_dynamics_filtered). Her skin is not led by
    /// those bones. None as `for_frame` gives None.
    pub(crate) fn prepare(session: usize, parts: &[SessionPart], skel: Option<&Skeleton>) -> Option<CoverPrep> {
        let moves = COVER.lock().ok()?.iter().find(|(k, _)| *k == session)?.1.clone();
        let skel = skel?;let still = cover_still(parts, skel)?;
        let (worlds, binds) = crate::skel_export::palettes(skel, &parts[still.body]);
        if worlds.is_empty() { return None; }
        Some(CoverPrep { still, worlds, binds, moves })
    }

    /// The field from what `prepare` read (any thread).
    pub(crate) fn build(prep: CoverPrep) -> Option<CoverField> {
        let _trace = crate::native_profile::Scope::new(47);
        CoverField::from_still(&prep.still, &prep.worlds, &prep.binds, &prep.moves)
    }

    /// For a session whose clothes are kept over her skin now (`set_cover`), her pushing skin on `skel`; None otherwise.
    pub(crate) fn for_frame(session: usize, parts: &[SessionPart], skel: Option<&Skeleton>) -> Option<CoverField> {
        let moves = COVER.lock().ok()?.iter().find(|(k, _)| *k == session)?.1.clone();
        CoverField::new(parts, skel?, &moves)
    }

    /// A garment with its own rig, just skinned on the CPU (`positions`, her skeleton space): moved out over her skin.
    pub(crate) fn cover(&self, _index: usize, part: &SessionPart, positions: &mut [[f32; 3]]) {
        if !covers(&part.role) || part.runtime_accessory.is_none() || positions.len() != part.rest_positions.len() { return; }
        let _trace = crate::native_profile::Scope::new(48);let _time = Timed(std::time::Instant::now(), 27);
        let nbr = { let _t = Timed(std::time::Instant::now(), 28);neighbours(&part.indices, &part.rest_positions) };
        // Keyed by the garment's own neighbour table (one per mesh of each session).
        let warm = std::sync::Arc::as_ptr(&nbr) as usize;
        let Some(push) = self.pushes(margin(&part.role), positions, &nbr, &part.indices, Some(warm)) else { return; };
        for (p, v) in positions.iter_mut().zip(push) { for a in 0..3 { p[a] += v[a]; } }
    }

    /// How far each of `positions` (a garment posed) moves with the skin under it that swelled out, and whether it hugs
    /// her skin at all. Every layer of cloth over one place moves as far, so they stay in their order: each pushed to one
    /// height over the skin, her fishnets and tights lay on one surface and fought for depth (user, 2026-11-11).
    fn follows(&self, positions: &[[f32; 3]], key: usize) -> Option<(Vec<[f32; 3]>, Vec<bool>)> {
        if !self.follows_any { return None; }
        let found = FOLLOW_MAP.lock().unwrap().get(&key).filter(|m| m.len() == positions.len()).cloned();
        let map = match found { Some(m) => m, None => {
            let m = std::sync::Arc::new(self.map_to_skin(positions));
            let mut all = FOLLOW_MAP.lock().unwrap();if all.len() > 256 { all.clear(); }
            all.insert(key, m.clone());m
        } };
        let _time = Timed(std::time::Instant::now(), 37);
        // Each cloth vertex on its own, on the pool.
        use rayon::prelude::*;
        let each: Vec<([f32; 3], bool)> = map.par_iter().map(|(near, gap)| {
            if near[0].1 <= 0. { return ([0.; 3], false); }
            let hug = (1. - (gap - HUG_M).max(0.) / (FOLLOW_M - HUG_M)).clamp(0., 1.);
            let mut v = [0f32; 3];
            for &(i, w) in near { if w <= 0. { break; } if let Some(Some(d)) = self.follow.get(i as usize) { for a in 0..3 { v[a] += d[a] * w * hug; } } }
            (v, true)
        }).collect();
        let any = each.iter().any(|(v, _)| dot(*v, *v) > 0.);
        let (moves, hugs): (Vec<[f32; 3]>, Vec<bool>) = each.into_iter().unzip();
        any.then_some((moves, hugs))
    }

    /// For each cloth vertex at `positions`: her four nearest skin vertices within `FOLLOW_M` (weighed, nearer more) and how
    /// far the nearest is. Her skin posed this frame.
    fn map_to_skin(&self, positions: &[[f32; 3]]) -> Vec<([(u32, f32); 4], f32)> {
        use rayon::prelude::*;
        let still = &self.still;let skins = &self.skins;
        let posed = self.posed.get_or_init(|| {
            (0..still.rest.len()).into_par_iter().map(|j| {
                let (Some(b), Some(w)) = (still.bones.get(j), still.weights.get(j)) else { return [f32::MAX; 3]; };
                let mut c = [0f32; 3];let r = still.rest[j];
                for (b, w) in b.iter().zip(w) { if *w <= 0. { continue; } if let Some(s) = skins.get(*b as usize) { let q = point(s, r);for a in 0..3 { c[a] += q[a] * w; } } }
                c
            }).collect()
        });
        let key = |p: [f32; 3]| p.map(|v| (v / FOLLOW_M).floor() as i64);
        let mut grid: HashMap<[i64; 3], Vec<u32>> = HashMap::new();
        for (j, p) in posed.iter().enumerate() { if p[0].abs() < 1e6 { grid.entry(key(*p)).or_default().push(j as u32); } }
        positions.par_iter().map(|&c| {
            let mut best: [(u32, f32); 4] = [(0, f32::MAX); 4];
            if c[0].abs() < 1e6 {
                let k = key(c);
                for a in -1..=1 { for b in -1..=1 { for e in -1..=1 {
                    let Some(list) = grid.get(&[k[0] + a, k[1] + b, k[2] + e]) else { continue; };
                    for &i in list {
                        let d = sub(c, posed[i as usize]);let d = dot(d, d);
                        if d >= FOLLOW_M * FOLLOW_M || d >= best[3].1 { continue; }
                        let mut s = 3;while s > 0 && best[s - 1].1 > d { best[s] = best[s - 1];s -= 1; }
                        best[s] = (i, d);
                    }
                } } }
            }
            if best[0].1 == f32::MAX { return ([(0, 0.); 4], f32::MAX); }
            let gap = best[0].1.sqrt();
            let mut out = [(0u32, 0f32); 4];let mut total = 0.;
            for (o, &(i, d)) in out.iter_mut().zip(&best) { if d == f32::MAX { break; } let w = 1. / (d.sqrt() + 0.002);*o = (i, w);total += w; }
            for o in &mut out { o.1 /= total; }
            (out, gap)
        }).collect()
    }

    /// The skin listed for the cell `c` is in (None outside the box).
    fn at(&self, c: [f32; 3]) -> Option<&Vec<u32>> {
        let k = cell(c);
        if (0..3).any(|a| k[a] < self.lo[a] || k[a] > self.hi[a]) { return None; }
        let (h, w) = ((self.hi[1] - self.lo[1] + 1) as usize, (self.hi[2] - self.lo[2] + 1) as usize);
        self.grid.get((((k[0] - self.lo[0]) as usize * h) + (k[1] - self.lo[1]) as usize) * w + (k[2] - self.lo[2]) as usize).filter(|l| !l.is_empty())
    }

    /// How far each of `positions` (a garment posed, her skeleton space) moves: up over the skin lifted under it, then out
    /// over her breasts.
    fn pushes(&self, keep: f32, positions: &[[f32; 3]], nbr: &[Vec<u32>], indices: &[u32], warm: Option<usize>) -> Option<Vec<[f32; 3]>> {
        // The cloth hugging her skin moves with it; what hangs loose is lifted over it.
        let (follow, hugs) = self.follows(positions, nbr.as_ptr() as usize).unzip();
        let at: std::borrow::Cow<[[f32; 3]]> = match &follow { Some(f) => positions.iter().zip(f).map(|(p, v)| [p[0] + v[0], p[1] + v[1], p[2] + v[2]]).collect::<Vec<_>>().into(), None => positions.into() };
        let lifted = { let _trace = crate::native_profile::Scope::new(49); self.lift.as_ref().and_then(|l| l.moves(keep, &at, nbr, indices, hugs.as_deref())) };
        let lifted = match (follow, lifted) { (Some(mut f), Some(l)) => { for (t, v) in f.iter_mut().zip(l) { for a in 0..3 { t[a] += v[a]; } } Some(f) }, (f, l) => f.or(l) };
        let Some(mut total) = lifted else { return self.pushes_from(keep, positions, nbr, indices, warm); };
        let moved: Vec<[f32; 3]> = positions.iter().zip(&total).map(|(p, v)| [p[0] + v[0], p[1] + v[1], p[2] + v[2]]).collect();
        if let Some(push) = self.pushes_from(keep, &moved, nbr, indices, warm) { for (t, v) in total.iter_mut().zip(push) { for a in 0..3 { t[a] += v[a]; } } }
        Some(total)
    }

    /// How far each of `positions` moves to stay `keep` past her breasts, evened over the cloth round it (so a nipple lifts
    /// a little tent of cloth and not one vertex).
    fn pushes_from(&self, keep: f32, positions: &[[f32; 3]], nbr: &[Vec<u32>], indices: &[u32], warm: Option<usize>) -> Option<Vec<[f32; 3]>> {
        let _trace = crate::native_profile::Scope::new(50);
        // Each vertex on its own, on the pool: one garment was 1 ms on the frame's longest path (trace 2026-11-08).
        use rayon::prelude::*;
        let at_trace = crate::native_profile::Scope::new(60);let t_at = Timed(std::time::Instant::now(), 29);
        // From last frame's (WARM): the vertices it pushed, two rings round them and every `stride`-th of the rest in
        // turn. Cloth the skin newly reaches elsewhere is pushed up to `stride` frames late (user accepted, 2026-11-10).
        let stride = warm_stride();
        let n = positions.len();
        let last = warm.filter(|_| stride > 1).and_then(|k| WARM.lock().unwrap().get(&k).filter(|e| e.2 == n).map(|e| (e.0, e.1.clone())));
        let frame = last.as_ref().map_or(0, |l| l.0.wrapping_add(1));
        let mut push: Vec<[f32; 3]> = match last {
            None => positions.par_iter().map(|&c| self.push_at(keep, c)).collect(),
            Some((_, hot)) => {
                let mut want = vec![false; n];let mut list: Vec<u32> = Vec::with_capacity(hot.len() * 4 + n / stride + 1);
                for &j in &hot { if !want[j as usize] { want[j as usize] = true;list.push(j); } }
                let mut from = 0;
                for _ in 0..2 {
                    let to = list.len();
                    for i in from..to { for &k in nbr.get(list[i] as usize).into_iter().flatten() { if let Some(w) = want.get_mut(k as usize).filter(|w| !**w) { *w = true;list.push(k); } } }
                    from = to;
                }
                for j in (frame as usize % stride..n).step_by(stride) { if !want[j] { want[j] = true;list.push(j as u32); } }
                let found: Vec<[f32; 3]> = list.par_iter().map(|&j| self.push_at(keep, positions[j as usize])).collect();
                let mut push = vec![[0f32; 3]; n];
                for (&j, v) in list.iter().zip(found) { push[j as usize] = v; }
                push
            }
        };
        if let Some(k) = warm {
            let hot: Vec<u32> = (0..n as u32).filter(|&j| dot(push[j as usize], push[j as usize]) > 0.).collect();
            let mut all = WARM.lock().unwrap();if all.len() > 256 { all.clear(); }
            all.insert(k, (frame, hot, n));
        }
        drop(t_at);drop(at_trace);let rings_trace = crate::native_profile::Scope::new(61);let t_rings = Timed(std::time::Instant::now(), 30);
        if !push.iter().any(|v| dot(*v, *v) > 0.) { return None; }
        // Only the cloth round what moved: six rings out from it (the push reaches only `REACH_M` across the skin itself).
        // Where each ring vertex is in the ring: a dense index (a hash map of them each ring was most of this).
        let mut near: Vec<u32> = (0..push.len() as u32).filter(|&j| dot(push[j as usize], push[j as usize]) > 0.).collect();
        let mut slot: Vec<u32> = vec![u32::MAX; push.len()];
        // Which vertices are in the ring already: grown by marking (sorting each ring with its neighbours, ten times its
        // size, was most of a garment's cover: 2026-11-10, every character, every frame).
        let mut taken = vec![false; push.len()];
        for &j in &near { taken[j as usize] = true; }
        for _ in 0..6 {
            for i in 0..near.len() {
                let j = near[i] as usize;
                for &k in nbr.get(j).into_iter().flatten() { if let Some(t) = taken.get_mut(k as usize).filter(|t| !**t) { *t = true;near.push(k); } }
            }
            let was: Vec<[f32; 3]> = near.iter().map(|&j| push[j as usize]).collect();
            for (i, &j) in near.iter().enumerate() { if let Some(s) = slot.get_mut(j as usize) { *s = i as u32; } }
            for (i, &j) in near.iter().enumerate() {
                let Some(list) = nbr.get(j as usize).filter(|l| !l.is_empty()) else { continue; };
                let mut s = [0f32; 3];
                for &k in list { let v = match slot.get(k as usize) { Some(&q) if q != u32::MAX => was[q as usize], _ => push[k as usize] };for a in 0..3 { s[a] += v[a]; } }
                let f = 0.6 / list.len() as f32;let avg = [s[0] * f, s[1] * f, s[2] * f];
                if dot(avg, avg) > dot(was[i], was[i]) { push[j as usize] = avg; }
            }
            for &j in &near { if let Some(s) = slot.get_mut(j as usize) { *s = u32::MAX; } }
        }
        drop(t_rings);drop(rings_trace);let _flip_trace = crate::native_profile::Scope::new(62);let _flip = Timed(std::time::Instant::now(), 31);
        // A triangle of cloth the pushes turn over (her crotch, where the skin round him moves apart) showed its black inside:
        // its corners are pushed half as far, until none turns over. Halving never pushes a vertex that was not: the
        // triangles that can turn are found once.
        let cross = |u: [f32; 3], v: [f32; 3]| [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
        let moved = |push: &[[f32; 3]], k: usize| { let (p, v) = (positions[k], push[k]);[p[0] + v[0], p[1] + v[1], p[2] + v[2]] };
        // Each with its normal as posed and that normal's length, worked out once (the same numbers every round).
        let pushed: Vec<([usize; 3], [f32; 3], f32)> = indices.chunks_exact(3).map(|t| [t[0] as usize, t[1] as usize, t[2] as usize])
            .filter(|t| t.iter().all(|&k| k < push.len()) && !t.iter().all(|&k| dot(push[k], push[k]) == 0.))
            // A triangle with no area (a seam's sliver) never counts as upright: it halved its corners all six times.
            .filter_map(|[a, b, c]| { let w = cross(sub(positions[b], positions[a]), sub(positions[c], positions[a]));(dot(w, w) > 1e-16).then(|| ([a, b, c], w, dot(w, w).sqrt())) }).collect();
        // After the first round only a triangle with a corner halved in the round before can turn over (the others' corners
        // are where they were): 1.7 ms a frame of a fully dressed heroine went through every triangle six times (2026-11-13).
        let mut changed = vec![false; push.len()];let mut last: Vec<usize> = Vec::new();
        for round in 0..6 {
            let mut halve: Vec<usize> = Vec::new();
            for &([a, b, c], was, was_len) in &pushed {
                if round > 0 && !(changed[a] || changed[b] || changed[c]) { continue; }
                if [a, b, c].iter().all(|&k| dot(push[k], push[k]) == 0.) { continue; }
                let now = cross(sub(moved(&push, b), moved(&push, a)), sub(moved(&push, c), moved(&push, a)));
                if dot(was, now) <= 0.2 * was_len * dot(now, now).sqrt() { halve.extend([a, b, c]); }
            }
            if halve.is_empty() { break; }
            for &k in &last { changed[k] = false; }
            for &k in &halve { changed[k] = true;push[k] = push[k].map(|v| v * 0.5); }
            last = halve;
        }
        Some(push)
    }

    /// How far the cloth vertex at `c` moves to stay `keep` past her skin listed round it (pushes_from's first pass).
    fn push_at(&self, keep: f32, c: [f32; 3]) -> [f32; 3] {
        {
            let Some(list) = self.at(c) else { return [0.; 3]; };
            // As far as the skin that needs it most, along the normals of all that does weighed by how much: the way taken
            // from the one skin alone jumped between neighbouring cloth vertices and folded the cloth between them, black.
            let mut best = 0f32;let mut way = [0f32; 3];
            for &i in list {
                let (p0, p, n) = self.skin[i as usize];
                // Skin lifted is `Lift`'s.
                if self.lifted[i as usize] { continue; }
                // Cloth behind the skin: her far side, or under it.
                if dot(sub(c, p0), n) < -UNDER_M { continue; }
                let g = sub(c, p);let h = dot(g, n);let across = dot(g, g) - h * h;
                if across >= BUST_REACH_M * BUST_REACH_M { continue; }
                let t = 1. - across.sqrt() / BUST_REACH_M;let w = t * t * (3. - 2. * t);
                let need = push_by(keep, dot(sub(c, p0), n), dot(sub(p, p0), n)) * w;
                if need <= 0. { continue; }
                best = best.max(need);for a in 0..3 { way[a] += n[a] * need; }
            }
            let l = dot(way, way).sqrt();
            if best > 0. && l > 1e-9 { [way[0] / l * best, way[1] / l * best, way[2] / l * best] } else { [0.; 3] }
        }
    }

}

/// The plane through `points` (height the third): height = a * first + b * second + c.
fn plane(points: impl Iterator<Item = [f32; 3]>) -> [f32; 3] {
    let (mut n, mut m, mut r) = (0f64, [[0f64; 3]; 3], [0f64; 3]);
    let all: Vec<[f64; 3]> = points.map(|p| p.map(|v| v as f64)).collect();
    if all.is_empty() { return [0.; 3]; }
    let mid = all.iter().fold([0f64; 3], |s, p| [s[0] + p[0], s[1] + p[1], s[2] + p[2]]).map(|v| v / all.len() as f64);
    for p in &all { let (x, y, z) = (p[0] - mid[0], p[1] - mid[1], p[2] - mid[2]);m[0][0] += x * x;m[0][1] += x * y;m[1][1] += y * y;r[0] += x * z;r[1] += y * z;n += 1.; }
    let d = m[0][0] * m[1][1] - m[0][1] * m[0][1];
    if d.abs() < 1e-12 * n { return [0., 0., mid[2] as f32]; }
    let (a, b) = ((r[0] * m[1][1] - r[1] * m[0][1]) / d, (r[1] * m[0][0] - r[0] * m[0][1]) / d);
    [a as f32, b as f32, (mid[2] - a * mid[0] - b * mid[1]) as f32]
}

/// How far over the moved skin cloth `g` over it as it was ends up: as far as it was (it moves with the skin), and cloth
/// nearer than `keep` (or under it) out to a little under `keep`, in the same order. Every garment pushed to `keep` lay
/// on one surface: her fishnets and tights fought for depth wherever the skin swelled (user, 2026-11-11).
fn over(keep: f32, g: f32) -> f32 { if g >= keep { g } else { keep * ((g - keep) / keep).exp() } }
/// Cloth this near the skin as it was hugs it (moves all the way with it); looser cloth moves less, the order kept.
const HUG_M: f32 = 0.01;
/// How far out cloth `g` over the skin as it was moves when that skin swells out `lift`: with the skin as it hugs it, less
/// the looser it hangs (none once the skin no longer reaches it), never past cloth that lay over it.
fn push_by(keep: f32, g: f32, lift: f32) -> f32 {
    let lift = lift.max(0.);let hug = (1. - (g - HUG_M).max(0.) / (lift + HUG_M)).max(0.);
    lift * hug + over(keep, g) - g
}

fn cell(p: [f32; 3]) -> [i64; 3] { p.map(|v| (v / REACH_M).floor() as i64) }

impl Lift {
    /// `lifted`: each place of her skin as it was and as it is. None when it went no one way.
    fn new(lifted: &[([f32; 3], [f32; 3])]) -> Option<Lift> {
        let mut sum = [0f32; 3];
        for (p0, p) in lifted { let d = sub(*p, *p0);for a in 0..3 { sum[a] += d[a]; } }
        let l = dot(sum, sum).sqrt();if l < 1e-6 { return None; }
        let way = sum.map(|v| v / l);
        let cross = |u: [f32; 3], v: [f32; 3]| [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
        let other = if way[0].abs() < 0.7 { [1., 0., 0.] } else { [0., 1., 0.] };
        let a = cross(way, other);let l = dot(a, a).sqrt();let a = a.map(|v| v / l);
        let side = [a, cross(way, a)];
        // Only the skin that went its way (the swelling of her buttocks behind would set the plane between them).
        let belly = plane(lifted.iter().filter(|(p0, p)| dot(sub(*p, *p0), way) > 0.).map(|(p0, _)| [dot(*p0, side[0]), dot(*p0, side[1]), dot(*p0, way)]));
        let mut thin: HashMap<[i64; 2], ([f32; 2], f32, f32)> = HashMap::new();
        for (p0, p) in lifted {
            let h = dot(*p, way);
            if h <= dot(*p0, way) { continue; }
            let q = [dot(*p, side[0]), dot(*p, side[1])];
            let base = dot(*p0, way);
            let e = thin.entry(q.map(|v| (v / THIN_M).floor() as i64)).or_insert((q, h, base));
            if h > e.1 { *e = (q, h, base); }
        }
        let skin: Vec<([f32; 2], f32, f32)> = thin.into_values().collect();
        if skin.is_empty() { return None; }
        let (mut lo, mut hi) = ([i64::MAX; 2], [i64::MIN; 2]);
        for s in &skin { let c = s.0.map(|v| (v / LIFT_REACH_M).floor() as i64);for a in 0..2 { lo[a] = lo[a].min(c[a] - 1);hi[a] = hi[a].max(c[a] + 1); } }
        let (w, h) = ((hi[0] - lo[0] + 1) as usize, (hi[1] - lo[1] + 1) as usize);
        if w * h > 1 << 20 { return None; }
        let mut grid: Vec<Vec<u32>> = vec![Vec::new(); w * h];
        for (i, s) in skin.iter().enumerate() {
            let c = s.0.map(|v| (v / LIFT_REACH_M).floor() as i64);
            for a in -1..=1 { for b in -1..=1 { grid[(c[0] + a - lo[0]) as usize * h + (c[1] + b - lo[1]) as usize].push(i as u32); } }
        }
        Some(Lift { way, side, skin, belly, grid, lo, hi })
    }

    /// Whether what is at `q` across, `up` along `way`, is on her back.
    fn far(&self, q: [f32; 2], up: f32) -> bool { up < self.belly[0] * q[0] + self.belly[1] * q[1] + self.belly[2] - FAR_M }

    /// Raises the corners of each triangle of cloth the skin still comes through: where the cloth is coarse (her obi) the
    /// hill stood up in the middle of a triangle, with no corner near enough to rise.
    fn clear(&self, keep: f32, positions: &[[f32; 3]], rise: &mut [f32], indices: &[u32]) {
        let (lo, hi) = (self.lo.map(|v| v as f32 * LIFT_REACH_M), self.hi.map(|v| (v + 1) as f32 * LIFT_REACH_M));
        let seen: Vec<Option<[f32; 3]>> = positions.iter().map(|&c| {
            if c[0].abs() > 1e6 { return None; }
            let (q, up) = ([dot(c, self.side[0]), dot(c, self.side[1])], dot(c, self.way));
            (!self.far(q, up)).then_some([q[0], q[1], up])
        }).collect();
        let h = (self.hi[1] - self.lo[1] + 1) as usize;
        for t in indices.chunks_exact(3) {
            let k = [t[0] as usize, t[1] as usize, t[2] as usize];
            let (Some(Some(a)), Some(Some(b)), Some(Some(c))) = (seen.get(k[0]), seen.get(k[1]), seen.get(k[2])) else { continue; };
            let (a, b, c) = (*a, *b, *c);
            let (x0, x1) = (a[0].min(b[0]).min(c[0]), a[0].max(b[0]).max(c[0]));
            let (y0, y1) = (a[1].min(b[1]).min(c[1]), a[1].max(b[1]).max(c[1]));
            if x1 < lo[0] || x0 > hi[0] || y1 < lo[1] || y0 > hi[1] { continue; }
            let d = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]);
            if d.abs() < 1e-10 { continue; }
            // The cells it lies over (each lists the skin round it too: a skin found twice is met already the second time).
            let cell = |v: f32, a: usize| ((v / LIFT_REACH_M).floor() as i64).clamp(self.lo[a], self.hi[a]);
            for i in cell(x0, 0)..=cell(x1, 0) { for j in cell(y0, 1)..=cell(y1, 1) {
                for &n in &self.grid[(i - self.lo[0]) as usize * h + (j - self.lo[1]) as usize] {
                    let (s, top, base) = self.skin[n as usize];
                    if s[0] < x0 || s[0] > x1 || s[1] < y0 || s[1] > y1 { continue; }
                    let u = ((s[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (s[1] - a[1])) / d;
                    let v = ((b[0] - a[0]) * (s[1] - a[1]) - (s[0] - a[0]) * (b[1] - a[1])) / d;
                    if u < 0. || v < 0. || u + v > 1. { continue; }
                    let w = [1. - u - v, u, v];
                    let z = (a[2] + rise[k[0]]) * w[0] + (b[2] + rise[k[1]]) * w[1] + (c[2] + rise[k[2]]) * w[2];
                    let z0 = a[2] * w[0] + b[2] * w[1] + c[2] * w[2];
                    let short = z0 + push_by(keep, z0 - base, top - base) - z;
                    if short > 0. { for m in k { rise[m] += short; } }
                }
            } }
        }
    }

    /// How far along `way` `c` must rise to stay `keep` over the skin.
    fn rise(&self, keep: f32, c: [f32; 3]) -> f32 {
        // A vertex no bone holds lies at f32::MAX.
        if c[0].abs() > 1e6 { return 0.; }
        let q = [dot(c, self.side[0]), dot(c, self.side[1])];
        let k = q.map(|v| (v / LIFT_REACH_M).floor() as i64);
        if (0..2).any(|a| k[a] < self.lo[a] || k[a] > self.hi[a]) { return 0.; }
        let h = (self.hi[1] - self.lo[1] + 1) as usize;
        let up = dot(c, self.way);let mut best = 0f32;
        if self.far(q, up) { return 0.; }
        for &i in &self.grid[(k[0] - self.lo[0]) as usize * h + (k[1] - self.lo[1]) as usize] {
            let (s, top, base) = self.skin[i as usize];
            // Its most is `room` (the falloff is at most 1): none that cannot pass the best so far, and none out of reach,
            // is weighed (the same best; most of the list is either).
            let room = push_by(keep, up - base, top - base);if room <= best { continue; }
            let (x, y) = (q[0] - s[0], q[1] - s[1]);let d2 = x * x + y * y;
            if d2 >= LIFT_REACH_M * LIFT_REACH_M { continue; }let across = d2.sqrt();
            let t = ((LIFT_REACH_M - across) / (LIFT_REACH_M - FULL_M)).min(1.);
            best = best.max(room * t * t * (3. - 2. * t));
        }
        best
    }

    /// How each of `positions` moves, evened over the cloth round it (a tent, not a spike). None when none does.
    /// `fixed`: cloth that moves with her skin already (`follows`): left where it is.
    fn moves(&self, keep: f32, positions: &[[f32; 3]], nbr: &[Vec<u32>], indices: &[u32], fixed: Option<&[bool]>) -> Option<Vec<[f32; 3]>> {
        let held = |j: usize| fixed.is_some_and(|f| f.get(j) == Some(&true));
        // Each vertex on its own, on the pool; the rings grown by marking, as pushes_from's (sorting each ring with its
        // neighbours was most of the lift: 1 ms of a garment on the pair solve's longest path, trace 2026-11-10).
        use rayon::prelude::*;
        let mut rise: Vec<f32> = { let _trace = crate::native_profile::Scope::new(57);let _time = Timed(std::time::Instant::now(), 38); positions.par_iter().enumerate().map(|(j, &c)| if held(j) { 0. } else { self.rise(keep, c) }).collect() };
        { let _trace = crate::native_profile::Scope::new(58);let _time = Timed(std::time::Instant::now(), 39); self.clear(keep, positions, &mut rise, indices); }
        for j in 0..rise.len() { if held(j) { rise[j] = 0.; } }
        let _rings_trace = crate::native_profile::Scope::new(59);let _rings_time = Timed(std::time::Instant::now(), 40);
        let mut near: Vec<u32> = (0..rise.len() as u32).filter(|&j| rise[j as usize] > 0.).collect();
        if near.is_empty() { return None; }
        let mut taken = vec![false; rise.len()];
        for &j in &near { taken[j as usize] = true; }
        let mut was = rise.clone();
        for _ in 0..6 {
            for i in 0..near.len() {
                let j = near[i] as usize;
                for &k in nbr.get(j).into_iter().flatten() { if let Some(t) = taken.get_mut(k as usize).filter(|t| !**t) { *t = true;near.push(k); } }
            }
            was.copy_from_slice(&rise);
            for &j in &near {
                let Some(list) = nbr.get(j as usize).filter(|l| !l.is_empty()) else { continue; };
                let avg = list.iter().map(|&k| was[k as usize]).sum::<f32>() * 0.8 / list.len() as f32;
                if avg > rise[j as usize] && !held(j as usize) { rise[j as usize] = avg; }
            }
        }
        Some(rise.into_iter().map(|r| self.way.map(|v| v * r)).collect())
    }
}

/// What of her body and her garments on her body skeleton stays while she is posed, once for each set of parts.
pub(super) struct CoverStill {
    body: usize, rest: Vec<[f32; 3]>, normals: Vec<[f32; 3]>, bones: Vec<[u16; 4]>, weights: Vec<[f32; 4]>, on_bust: Vec<bool>, on_nip: Vec<bool>,
    cloth: Vec<ClothMesh>,
}
/// `near`: its vertices led by a bone that leads her breast skin too (the only ones her breasts can reach while no skin is
/// lifted; a skirt has none): only those are posed then.
struct ClothMesh { part: usize, keep: f32, rest: Vec<[f32; 3]>, bones: Vec<[u16; 4]>, weights: Vec<[f32; 4]>, indices: Vec<u32>, nbr: std::sync::Arc<Vec<Vec<u32>>>, near: Vec<u32> }
static COVER_STILL: std::sync::Mutex<Vec<(usize, usize, usize, std::sync::Arc<CoverStill>)>> = std::sync::Mutex::new(Vec::new());

/// Her clothes changed on the same model (wardrobe.rs): what was read from the old ones goes.
pub(crate) fn clothes_changed() {
    COVER_STILL.lock().unwrap().clear();
    WARM.lock().unwrap().clear();
    FOLLOW_MAP.lock().unwrap().clear();
    COVER.lock().unwrap().clear();
    REACH_HELD.lock().unwrap().clear();
}

fn cover_still(parts: &[SessionPart], skel: &Skeleton) -> Option<std::sync::Arc<CoverStill>> {
    let key = (parts.as_ptr() as usize, parts.len(), parts.iter().map(|p| p.rest_positions.len()).sum::<usize>());
    if let Some(e) = COVER_STILL.lock().unwrap().iter().find(|e| (e.0, e.1, e.2) == key) { return Some(e.3.clone()); }
    let (body, part) = parts.iter().enumerate().filter(|(_, p)| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none())
        .max_by_key(|(_, p)| (p.blend_shapes.iter().any(|(n, _)| is_bulge(n)), p.rest_positions.len()))?;
    let pushing: Vec<bool> = skel.names.iter().map(|n| { let n = n.to_ascii_lowercase();PUSHING.iter().any(|s| n.contains(s)) }).collect();
    let on_bust: Vec<bool> = (0..part.rest_positions.len()).map(|j| part.bone_idx.get(j).zip(part.weights.get(j)).is_some_and(|(b, w)| b.iter().zip(w).any(|(b, w)| *w > 0.3 && pushing.get(*b as usize) == Some(&true)))).collect();
    // Her nipples and areolae (led by a `bnip` bone): thinned finely.
    let nip: Vec<bool> = skel.names.iter().map(|n| n.to_ascii_lowercase().contains("bnip")).collect();
    let on_nip: Vec<bool> = (0..part.rest_positions.len()).map(|j| part.bone_idx.get(j).zip(part.weights.get(j)).is_some_and(|(b, w)| b.iter().zip(w).any(|(b, w)| *w > 0.05 && nip.get(*b as usize) == Some(&true)))).collect();
    // The bones leading her breast skin at all (her body and her clothes on it share the skeleton's bone indices).
    let mut region = vec![false; skel.names.len()];
    for j in (0..on_bust.len()).filter(|&j| on_bust[j]) {
        if let (Some(b), Some(w)) = (part.bone_idx.get(j), part.weights.get(j)) { for (b, w) in b.iter().zip(w) { if *w > 0. { if let Some(r) = region.get_mut(*b as usize) { *r = true; } } } }
    }
    let near = |p: &SessionPart| (0..p.rest_positions.len() as u32)
        .filter(|&j| p.bone_idx[j as usize].iter().zip(&p.weights[j as usize]).any(|(b, w)| *w > 0. && region.get(*b as usize) == Some(&true))).collect::<Vec<u32>>();
    let cloth = parts.iter().enumerate().filter(|(_, p)| covers(&p.role) && p.runtime_accessory.is_none() && p.skel_kind == 1
        && p.weights.len() == p.rest_positions.len() && p.bone_idx.len() == p.rest_positions.len())
        .map(|(i, p)| ClothMesh { part: i, keep: margin(&p.role), rest: p.rest_positions.clone(), bones: p.bone_idx.clone(), weights: p.weights.clone(), indices: p.indices.clone(), nbr: neighbours(&p.indices, &p.rest_positions), near: near(p) }).collect();
    let still = std::sync::Arc::new(CoverStill { body, rest: part.rest_positions.clone(), normals: part.rest_normals.clone(), bones: part.bone_idx.clone(), weights: part.weights.clone(), on_bust, on_nip, cloth });
    let mut all = COVER_STILL.lock().unwrap();all.insert(0, (key.0, key.1, key.2, still.clone()));all.truncate(4);
    Some(still)
}

/// Her skin and clothes tables built before his first stroke (the opening's thread).
pub(super) fn warm(session: &OkSession) {
    if let Some(rest) = crate::skel_export::bind_body(session) { let _ = cover_still(&session.parts, &rest); }
}

/// One frame of her clothes cover: the bones now, for her body and each garment she has on.
pub(super) struct CoverFrame { still: std::sync::Arc<CoverStill>, worlds: Vec<Mat4>, binds: Vec<Mat4>, cloth: Vec<(usize, Vec<Mat4>)> }

pub(super) fn frame(session: &OkSession) -> Option<CoverFrame> {
    let skel = session.body_skel.as_ref()?;
    let still = cover_still(&session.parts, skel)?;
    let (worlds, binds) = crate::skel_export::palettes(skel, &session.parts[still.body]);
    if worlds.is_empty() { return None; }
    let cloth = still.cloth.iter().enumerate().filter(|(_, c)| session.parts[c.part].render_visible).filter_map(|(i, c)| {
        let (w, b) = crate::skel_export::palettes(skel, &session.parts[c.part]);
        let palette: Vec<Mat4> = w.iter().zip(&b).map(|(w, b)| mat_mul_pub(w, b)).collect();
        (!palette.is_empty()).then_some((i, palette))
    }).collect();
    Some(CoverFrame { still, worlds, binds, cloth })
}

/// Her pushing skin and her garments' moves for `body_moves`: the moves as `cover_deltas` gives them.
pub(super) fn solve(frame: &CoverFrame, body_moves: &[(u32, [f32; 6])]) -> (Vec<(usize, Vec<(u32, [f32; 3])>)>, Option<std::sync::Arc<CoverField>>) {
    let Some(field) = CoverField::from_still(&frame.still, &frame.worlds, &frame.binds, body_moves) else { return (Vec::new(), None); };
    let mut out = Vec::new();
    for (i, palette) in &frame.cloth {
        let mesh = &frame.still.cloth[*i];
        let (rest, weights, bones) = (&mesh.rest, &mesh.weights, &mesh.bones);
        // No skin lifted (every character's own cover, each pose): only what her breasts can reach is posed.
        if body_moves.is_empty() && frame.still.cloth[*i].near.is_empty() { continue; }
        let mut wanted = vec![!body_moves.is_empty(); rest.len()];
        if body_moves.is_empty() { for &j in &mesh.near { wanted[j as usize] = true; } }
        let mats: Vec<Option<Mat4>> = (0..rest.len()).map(|j| {
            if !wanted[j] { return None; }
            let mut m = [[0f32; 4]; 4];let mut total = 0.;
            for (b, w) in bones[j].iter().zip(&weights[j]) {
                let Some(p) = palette.get(*b as usize).filter(|_| *w > 0.) else { continue; };
                for r in 0..4 { for c in 0..4 { m[r][c] += p[r][c] * w; } }total += w;
            }
            (total > 0.5).then_some(m)
        }).collect();
        let posed: Vec<[f32; 3]> = mats.iter().zip(rest).map(|(m, r)| m.map_or([f32::MAX; 3], |m| point(&m, *r))).collect();
        let Some(push) = field.pushes(mesh.keep, &posed, &mesh.nbr, &mesh.indices, None) else { continue; };
        let mut moves = Vec::new();
        for (j, v) in push.into_iter().enumerate() {
            let Some(m) = mats[j] else { continue; };
            if dot(v, v) < 0.0001 * 0.0001 { continue; }
            // Back into the mesh's space (the posed skin's inverse, as the morph is skinned).
            let inv = mat_inv_pub(&m);let o = point(&inv, [0.; 3]);let a = point(&inv, v);
            moves.push((j as u32, [a[0] - o[0], a[1] - o[1], a[2] - o[2]]));
        }
        if !moves.is_empty() { out.push((mesh.part, moves)); }
    }
    (out, Some(std::sync::Arc::new(field)))
}

/// The moves of her garments on her body skeleton this frame (a morph each): for each (session part index), its vertex
/// index and move in the mesh's own space (Unity metres). `body_moves` are her body's skin moves now (`wrap_deltas`).
pub fn cover_deltas(session: &OkSession, body_moves: &[(u32, [f32; 6])]) -> Vec<(usize, Vec<(u32, [f32; 3])>)> {
    let Some(f) = frame(session) else { return Vec::new(); };
    if f.cloth.is_empty() { return Vec::new(); }
    solve(&f, body_moves).0
}

#[cfg(test)]
mod lift_tests {
    use super::*;

    // One triangle of cloth far wider than the ridge, its corners out of the ridge's reach.
    #[test]
    fn a_coarse_triangle_clears_the_ridge() {
        let lifted: Vec<_> = (0..40).map(|i| { let x = i as f32 * 0.005 - 0.1;([x, 0., 0.], [x, 0., 0.1]) }).collect();
        let lift = Lift::new(&lifted).unwrap();
        let cloth = [[-0.3, -0.3, 0.02], [0.3, -0.3, 0.02], [0., 0.3, 0.02]];
        let nbr = vec![vec![1, 2], vec![0, 2], vec![0, 1]];
        let moves = lift.moves(0.005, &cloth, &nbr, &[0, 1, 2], None).unwrap();
        // At the ridge, a third of the way from each corner in height.
        assert!(moves.iter().map(|v| cloth[0][2] + v[2]).sum::<f32>() / 3. >= 0.09, "{moves:?}");
    }

    // Her belly tilted to the way the skin went: the skin slides across as it lifts, onto cloth far from where it came from.
    #[test]
    fn cloth_the_skin_slid_under_rises_too() {
        let mut lifted = Vec::new();
        for i in 0..60 { for j in -7..=7 {
            let (x, y) = (i as f32 * 0.005, j as f32 * 0.002);
            let p0 = [x, y, 0.6 * x];
            lifted.push((p0, [p0[0] + 0.08, y, p0[2] + 0.1]));
        } }
        let lift = Lift::new(&lifted).unwrap();
        // Cloth 1 cm over her belly near the low end of the skin, where it slid to from far up it.
        let c = [0.2, 0., 0.13];
        assert!(lift.rise(0.005, c) > 0.05, "{}", lift.rise(0.005, c));
        // Cloth on her back there stays.
        assert_eq!(lift.rise(0.005, [c[0] + 0.1, 0., c[2] - 0.17]), 0.);
    }

    // A ridge 10 cm tall and 3 cm wide lifted out of flat skin, cloth 2 cm over it in 1 cm squares and more behind her.
    #[test]
    fn cloth_rises_over_a_tall_ridge() {
        let mut lifted = Vec::new();
        for i in 0..60 { for j in -7..=7 {
            let (x, y) = (i as f32 * 0.005, j as f32 * 0.002);
            let t = 1. - (y / 0.015).abs();
            lifted.push(([x, y, 0.], [x, y, 0.1 * t + 0.001]));
        } }
        let lift = Lift::new(&lifted).unwrap();
        assert!(lift.way[2] > 0.99);
        let (w, h) = (31usize, 21usize);
        let at = |i: usize, j: usize| [i as f32 * 0.01, (j as f32 - 10.) * 0.01, 0.02];
        let mut cloth: Vec<[f32; 3]> = (0..w * h).map(|k| at(k / h, k % h)).collect();
        cloth.push([0.1, 0., -0.1]);
        let mut nbr = vec![Vec::new(); cloth.len()];
        for k in 0..w * h { let (i, j) = (k / h, k % h);
            if i + 1 < w { nbr[k].push((k + h) as u32);nbr[k + h].push(k as u32); }
            if j + 1 < h { nbr[k].push((k + 1) as u32);nbr[k + 1].push(k as u32); }
        }
        let moves = lift.moves(0.005, &cloth, &nbr, &[], None).unwrap();
        // Along the ridge it clears the top.
        for i in 0..w - 1 { let k = i * h + 10;assert!(cloth[k][2] + moves[k][2] >= 0.1, "{i}: {}", cloth[k][2] + moves[k][2]); }
        // Only up: seen from there the cloth stays where it was, so no triangle of it turns over.
        for v in &moves { assert!(v[0].abs() < 0.005 && v[1].abs() < 0.005 && v[2] >= 0.); }
        // Her far side, and cloth far across the ridge, stay.
        assert_eq!(moves[w * h], [0.; 3]);
        // (loose cloth near the low edge of the ridge moves a hair with it: well under a tenth of a millimetre here)
        assert!(dot(moves[10 * h], moves[10 * h]) < 1e-5 * 1e-5, "{:?}", moves[10 * h]);
    }
}

/// A garment's cover time, added to OKAnim.Profile's `cover.garments` when it ends.
struct Timed(std::time::Instant, usize);
impl Drop for Timed { fn drop(&mut self) { crate::okanim::prof::add(self.1, self.0); } }
