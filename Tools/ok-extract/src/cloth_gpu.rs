//! Her garments with their own rig drawn on the GPU while her clothes are pushed out over her skin (belly_bulge cover)
//! and follow her thighs' jiggle (thigh_jiggle::follow_own) (user, 2026-11-14: all of Lan's clothes on the GPU, 120 FPS).
//!
//! Without this, a garment either of them moves is drawn from its CPU vertices: the whole mesh skinned, pushed and uploaded
//! every frame. With it on (`ok_cloth_gpu_set`), Unreal keeps such a garment on its GPU route (palette skinning) and adds
//! each vertex's move: the solve skins the garment as the CPU route would (`render_solved`, no physics step), pushes and
//! follows it exactly as there, and keeps only what moved (vertex, move in the session's Unity space, metres). The GPU adds
//! it after the placement correction, where the CPU route's positions are, so the drawn vertices are the same; normals are
//! the skinned ones on both routes (neither push nor jiggle turns them).
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

static ON: AtomicBool = AtomicBool::new(false);
/// ok.ClothGpu 2: the push and the jiggle worked out on the GPU too (ClothCover.usf); 1 only the moves added there.
static GPU: AtomicBool = AtomicBool::new(false);
/// Per session: the garments the cover and the jiggle would draw from CPU vertices ([cover, jiggle]).
static WANTED: Mutex<Option<HashMap<usize, [Vec<usize>; 2]>>> = Mutex::new(None);
/// Per (session, part): this pose's moves.
static MOVES: Mutex<Option<HashMap<(usize, usize), Vec<(u32, [f32; 3])>>>> = Mutex::new(None);

pub fn set_on(on: bool) { ON.store(on, Ordering::Relaxed); }
pub fn set_mode(mode: i32) { ON.store(mode >= 1, Ordering::Relaxed);GPU.store(mode >= 2, Ordering::Relaxed); }
pub fn on_gpu() -> bool { on() && GPU.load(Ordering::Relaxed) }
pub fn on() -> bool { ON.load(Ordering::Relaxed) }

/// The parts one of them (0 cover, 1 jiggle) would put on the CPU route now.
pub fn note(session: usize, kind: usize, parts: &[usize]) {
    let mut w = WANTED.lock().unwrap();
    let e = w.get_or_insert_with(HashMap::new).entry(session).or_default();
    if e[kind] != parts { e[kind] = parts.to_vec(); }
}
pub fn wants(session: usize, part: usize) -> bool {
    on() && WANTED.lock().unwrap().as_ref().and_then(|w| w.get(&session)).is_some_and(|e| e[0].contains(&part) || e[1].contains(&part))
}
pub fn put(session: usize, part: usize, moves: Vec<(u32, [f32; 3])>) {
    MOVES.lock().unwrap().get_or_insert_with(HashMap::new).insert((session, part), moves);
    put_cpu(session, part);
}
/// This pose's moves of a part (empty: none, or not wanted).
pub fn moves(session: usize, part: usize) -> Vec<(u32, [f32; 3])> {
    if !wants(session, part) { return Vec::new(); }
    MOVES.lock().unwrap().as_ref().and_then(|m| m.get(&(session, part)).cloned()).unwrap_or_default()
}
pub fn forget(session: usize) {
    if let Some(f) = FIELD.lock().unwrap().as_mut() { f.remove(&session); }
    if let Some(j) = JOBS.lock().unwrap().as_mut() { j.retain(|(s, _), _| *s != session); }
    if let Some(w) = WANTED.lock().unwrap().as_mut() { w.remove(&session); }
    if let Some(m) = MOVES.lock().unwrap().as_mut() { m.retain(|(s, _), _| *s != session); }
}
/// The moves from `before` to `after` (every vertex that moved at all: the GPU adds exactly these).
pub fn diff(before: &[[f32; 3]], after: &[[f32; 3]]) -> Vec<(u32, [f32; 3])> {
    before.iter().zip(after).enumerate().filter_map(|(j, (a, b))| {
        let d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
        (d[0] != 0. || d[1] != 0. || d[2] != 0.).then_some((j as u32, d))
    }).collect()
}

// ---- ok.ClothGpu 2
/// Per session: this frame's field (outer header 16 words: [0] the cover field's start or ~0, [1] jiggle slots, [2] their
/// start (xyz, 0 each), [4..13) the cover constants; then the cover field, then the jiggle moves).
static FIELD: Mutex<Option<HashMap<usize, std::sync::Arc<Vec<u32>>>>> = Mutex::new(None);
/// Per (session, part): done on the GPU this frame (its data's revision: 1 + which maps it has).
static JOBS: Mutex<Option<HashMap<(usize, usize), u32>>> = Mutex::new(None);

pub fn build_field(session: usize, cover: Option<&crate::belly_bulge::CoverField>) {
    let mut out = vec![0u32; 16];
    for (i, c) in crate::belly_bulge::GPU_CONSTS.iter().enumerate() { out[4 + i] = c.to_bits(); }
    match cover { Some(c) => { out[0] = out.len() as u32;c.gpu_field(&mut out); } None => out[0] = u32::MAX }
    if let Some(m) = crate::thigh_jiggle::gpu_moves(session) {
        out[1] = m.len() as u32;out[2] = out.len() as u32;
        for v in m { out.extend([v[0].to_bits(), v[1].to_bits(), v[2].to_bits(), 0]); }
    }
    FIELD.lock().unwrap().get_or_insert_with(HashMap::new).insert(session, std::sync::Arc::new(out));
}
pub fn field(session: usize) -> Option<std::sync::Arc<Vec<u32>>> { FIELD.lock().unwrap().as_ref()?.get(&session).cloned() }

/// Whether a garment can be done on the GPU this frame: the maps the field needs are found (else the CPU route this once,
/// which finds them). Some(revision) when it can.
pub fn gpu_ready(session: usize, index: usize, part: &crate::session::SessionPart, follows_any: bool) -> Option<u32> {
    let cover_map = crate::belly_bulge::gpu_has_follow_map(part);
    let mut probe = Vec::new();
    let jiggle_map = crate::thigh_jiggle::gpu_map(session, index, part.rest_positions.len(), &mut probe);
    if follows_any && !cover_map { return None; }
    if crate::thigh_jiggle::gpu_any(session) && !jiggle_map { return None; }
    Some(1 + cover_map as u32 + 2 * jiggle_map as u32)
}
pub fn put_gpu(session: usize, part: usize, revision: u32) {
    JOBS.lock().unwrap().get_or_insert_with(HashMap::new).insert((session, part), revision);
    if let Some(m) = MOVES.lock().unwrap().as_mut() { m.remove(&(session, part)); }
}
pub fn put_cpu(session: usize, part: usize) { if let Some(j) = JOBS.lock().unwrap().as_mut() { j.remove(&(session, part)); } }
/// -1 not wanted, 0 its moves (`moves`), >0 done on the GPU (the revision of its data: `garment`).
pub fn job(session: usize, part: usize) -> i32 {
    if !wants(session, part) { return -1; }
    JOBS.lock().unwrap().as_ref().and_then(|j| j.get(&(session, part)).copied()).map_or(0, |r| r as i32)
}
/// A garment's still data (cover.rs gpu_garment, then the jiggle map: header words 8, 9).
pub fn garment(session: usize, index: usize, part: &crate::session::SessionPart) -> Vec<u32> {
    let mut out = Vec::new();
    if !crate::belly_bulge::gpu_garment(part, &mut out) { return out; }
    let at = out.len() as u32;
    if crate::thigh_jiggle::gpu_map(session, index, part.rest_positions.len(), &mut out) { out[8] = 1;out[9] = at; }
    out
}