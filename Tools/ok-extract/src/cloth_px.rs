//! Skirts and sleeves as PhysX cloth (PxDeformableSurface, GPU FEM) instead of DynamicBone (user, 2026-11-20).
//!
//! Which vertices are cloth is found from the garment itself, never per card:
//! - skirt: vertices weighted to the skirt bones `cf_j_sk_<column>_<level>` (the ones the game's ct_clothesBot
//!   DynamicBones swing). The weighted level along the chain gives each vertex its depth: the waistband (level 0) is
//!   pinned to the skinned garment, the hem hangs free.
//! - sleeve: vertices of a top weighted to the arm bones (upper arm, forearm, elbow, wrist, hand) of one side. Their
//!   position along shoulder -> elbow -> wrist pins the shoulder opening and the cuff; the middle may move.
//! Every free vertex may leave its skinned position by at most its "max distance" (as Unreal's cloth paint): a share of
//! its distance to the nearest pinned vertex, and for a sleeve also how loose it sits around the arm.
//!
//! The garment is skinned as before, giving each vertex its animated target; the host (OKPhysXSecondary, PhysX 5.11)
//! simulates the welded triangle mesh with the pinned vertices on their targets and the body capsules (legs, arms, hips,
//! torso) as kinematic colliders, and returns the vertices. Rust then keeps them within their max distance and out of the
//! capsules (never deeper than the skinned target itself was), and turns the normals with the cloth.
//!
//! One driver per region: a garment whose skirt is cloth is skinned without its DynamicBones (the rigid path,
//! `AccessoryFramePolicy::cloth_rigid`); sleeves are weighted to body bones no chain moves, so a top keeps its chains.
//! `ok.ClothPx 0` (ok_cloth_px_set) gives the DynamicBones back; with no host or no CUDA nothing changes.
use std::collections::HashMap;
use std::sync::atomic::{AtomicI32, AtomicPtr, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use crate::px::OkPxCapsule;

/// `flags` bit 0: the garment has a skirt region (no bending: a walk flipped its pleats into a mirrored rest angle).
pub type CreateFn = unsafe extern "C" fn(key: u64, n: u32, pos: *const f32, inv_mass: *const f32, tri_n: u32, tris: *const u32, flags: u32) -> i32;
/// dt < 0: put every vertex on its target at rest (teleport, first frame). Returns 1 with `out` for these targets, 2 with
/// `out` for the previous call's targets (the host simulates while the frame renders), 0 with nothing.
/// `prev`: what was shown last frame (null: the host's own state); the free vertices start there.
pub type StepFn = unsafe extern "C" fn(key: u64, n: u32, targets: *const f32, prev: *const f32, caps: *const OkPxCapsule, cap_n: u32, dt: f32, out: *mut f32) -> i32;
pub type ReleaseFn = unsafe extern "C" fn(key: u64);

static CREATE: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());
static STEP: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());
static RELEASE: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());
/// 0 off (DynamicBone as before), 1 skirts and sleeves, 2 skirts only, 3 sleeves only.
static MODE: AtomicI32 = AtomicI32::new(0);
static NEXT_KEY: AtomicU64 = AtomicU64::new(1);

#[no_mangle]
pub extern "C" fn ok_set_physx_cloth(create: Option<CreateFn>, step: Option<StepFn>, release: Option<ReleaseFn>) {
    RELEASE.store(release.map_or(std::ptr::null_mut(), |f| f as *mut ()), Ordering::Release);
    STEP.store(step.map_or(std::ptr::null_mut(), |f| f as *mut ()), Ordering::Release);
    CREATE.store(create.map_or(std::ptr::null_mut(), |f| f as *mut ()), Ordering::Release);
}
fn host() -> Option<(CreateFn, StepFn, ReleaseFn)> {
    let (c, s, r) = (CREATE.load(Ordering::Acquire), STEP.load(Ordering::Acquire), RELEASE.load(Ordering::Acquire));
    if c.is_null() || s.is_null() || r.is_null() { return None; }
    // SAFETY: only ok_set_physx_cloth stores here, each with its own function type.
    unsafe { Some((std::mem::transmute::<*mut (), CreateFn>(c), std::mem::transmute::<*mut (), StepFn>(s), std::mem::transmute::<*mut (), ReleaseFn>(r))) }
}
pub fn set_mode(mode: i32) { MODE.store(mode.clamp(0, 3), Ordering::Relaxed); }
pub fn mode() -> i32 { MODE.load(Ordering::Relaxed) }
fn active() -> bool { mode() > 0 && host().is_some() }

// ---- tuning (OK_CLOTH_PX_* environment overrides, read once)
fn env_f(key: &str, default: f32) -> f32 { std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default) }
struct Tune { stretch: f32, pin_t: f32, skirt_reach: f32, skirt_max: f32, sleeve_reach: f32, sleeve_max: f32, shoulder_u: f32, cuff_u: f32, cap_scale: f32, cap_margin: f32, carry: bool, pull: f32, rebuild: f32 }
fn tune() -> &'static Tune {
    static T: std::sync::OnceLock<Tune> = std::sync::OnceLock::new();
    T.get_or_init(|| Tune {
        stretch: env_f("OK_CLOTH_PX_STRETCH", 1.03),
        pin_t: env_f("OK_CLOTH_PX_PIN", 0.12),
        skirt_reach: env_f("OK_CLOTH_PX_SKIRT_REACH", 0.55),
        skirt_max: env_f("OK_CLOTH_PX_SKIRT_MAX", 0.30),
        sleeve_reach: env_f("OK_CLOTH_PX_SLEEVE_REACH", 0.35),
        sleeve_max: env_f("OK_CLOTH_PX_SLEEVE_MAX", 0.08),
        shoulder_u: env_f("OK_CLOTH_PX_SHOULDER", 0.14),
        cuff_u: env_f("OK_CLOTH_PX_CUFF", 0.05),
        cap_scale: env_f("OK_CLOTH_PX_CAPSULE", 1.5),
        cap_margin: env_f("OK_CLOTH_PX_MARGIN", 0.001),
        carry: env_f("OK_CLOTH_PX_CARRY", 1.) > 0.5,
        pull: env_f("OK_CLOTH_PX_PULL", 3.),
        rebuild: env_f("OK_CLOTH_PX_REBUILD", 0.3),
    })
}

// ---- detection from the garment's weights
const KIND_SKIRT: u8 = 1;
const KIND_SLEEVE_L: u8 = 2;
const KIND_SLEEVE_R: u8 = 3;

/// `cf_j_sk_03_04` -> level 4.
fn skirt_level(name: &str) -> Option<u32> {
    let rest = name.strip_prefix("cf_j_sk_")?;
    let mut it = rest.split('_');
    let _column: u32 = it.next()?.parse().ok()?;
    it.next()?.parse().ok()
}
/// Arm bones of one side (0 left, 1 right): what a sleeve is skinned to.
fn arm_side(name: &str) -> Option<usize> {
    let n = name.to_ascii_lowercase();
    if !n.starts_with("cf_") || n.contains("shoulder") { return None; }
    if !["arm", "elbo", "wrist", "hand"].iter().any(|k| n.contains(k)) { return None; }
    if n.ends_with("_l") { Some(0) } else if n.ends_with("_r") { Some(1) } else { None }
}
fn skirt_role(role: &str) -> bool {
    role.starts_with("clothes") && !["clothes_shoes", "clothes_socks", "clothes_panst", "clothes_gloves", "clothes_bra", "clothes_shorts"].iter().any(|r| role.starts_with(r))
}
fn sleeve_role(role: &str) -> bool { role.starts_with("clothes_top") }

/// Per render vertex: the kind (0 none) and, for a skirt vertex, its depth along the chains (0 waist .. 1 hem).
struct Detect { kind: Vec<u8>, depth: Vec<f32>, skirt: bool, sleeves: bool, sig: (usize, usize) }

fn detect(part: &crate::session::SessionPart) -> Option<Detect> {
    let runtime = part.runtime_accessory.as_ref()?;
    let src = runtime.source_mesh();
    let n = src.weights.len();
    if n == 0 || src.bone_idx.len() != n || src.indices.len() < 3 { return None; }
    let (want_skirt, want_sleeve) = (skirt_role(&part.role) && mode() != 3, sleeve_role(&part.role) && mode() != 2);
    if !want_skirt && !want_sleeve { return None; }
    // Each bone's depth along the game's skirt chains cf_j_sk_<column>_<level> (0 waist .. 1 hem). The garment's own
    // DynamicBone chains are rooted on the clothes rig, not in its SMR skeleton (tried 2026-11-20: no bone found on any
    // test card); a mod skirt on other bones (K*/joint*) that no chain moves stays as it was.
    let max_level = src.bone_names.iter().filter_map(|b| skirt_level(b)).max().unwrap_or(0).max(1) as f32;
    let levels: Vec<Option<f32>> = src.bone_names.iter().map(|b| skirt_level(b).map(|l| l as f32 / max_level)).collect();
    let sides: Vec<Option<usize>> = src.bone_names.iter().map(|b| arm_side(b)).collect();
    let mut kind = vec![0u8; n];
    let mut depth = vec![0f32; n];
    let (mut skirt_n, mut sleeve_n) = (0usize, [0usize; 2]);
    for v in 0..n {
        let (mut total, mut sk, mut sk_level, mut arm) = (0f32, 0f32, 0f32, [0f32; 2]);
        for k in 0..4 {
            let w = src.weights[v][k];
            if w <= 0. { continue; }
            total += w;
            let b = src.bone_idx[v][k] as usize;
            if let Some(Some(l)) = levels.get(b) { sk += w; sk_level += w * *l; }
            if let Some(Some(s)) = sides.get(b) { arm[*s] += w; }
        }
        if total <= 1e-5 { continue; }
        if want_skirt && sk / total >= 0.25 {
            kind[v] = KIND_SKIRT;
            depth[v] = (sk_level / total).clamp(0., 1.);
            skirt_n += 1;
        } else if want_sleeve {
            for s in 0..2 { if arm[s] / total >= 0.5 { kind[v] = KIND_SLEEVE_L + s as u8; sleeve_n[s] += 1; } }
        }
    }
    if std::env::var("OK_CLOTH_PX_DEBUG").is_ok_and(|v| v == "1") {
        let mut sums = vec![0f32; src.bone_names.len()];
        for v in 0..n { for k in 0..4 { if let Some(s) = sums.get_mut(src.bone_idx[v][k] as usize) { *s += src.weights[v][k]; } } }
        let mut order: Vec<usize> = (0..sums.len()).collect();
        order.sort_by(|a, b| sums[*b].total_cmp(&sums[*a]));
        let top: Vec<String> = order.iter().take(12).map(|&b| format!("{}={:.0}", src.bone_names[b], sums[b])).collect();
        crate::ffi::ffi_log(1, &format!("OK cloth px detect: role={} verts={n} skirt_verts={skirt_n} sleeve_verts={sleeve_n:?} bones: {}", part.role, top.join(" ")));
    }
    let skirt = skirt_n >= 30;
    let sleeves = sleeve_n.iter().any(|c| *c >= 30);
    if !skirt { for k in kind.iter_mut() { if *k == KIND_SKIRT { *k = 0; } } }
    for s in 0..2 { if sleeve_n[s] < 30 { for k in kind.iter_mut() { if *k == KIND_SLEEVE_L + s as u8 { *k = 0; } } } }
    (skirt || sleeves).then_some(Detect { kind, depth, skirt, sleeves, sig: (n, src.indices.len()) })
}

// ---- per (session, part) state
struct Sim {
    key: u64,
    created: bool,
    /// Render vertex -> particle (u32::MAX: not simulated).
    particle_of: Vec<u32>,
    /// Particle -> one of its render vertices (its target).
    rep: Vec<u32>,
    pinned: Vec<bool>,
    max_dist: Vec<f32>,
    tris: Vec<[u32; 3]>,
    offsets: Vec<[f32; 3]>,
    last_target: Vec<[f32; 3]>,
    free: usize,
    /// When it last stepped: a pose given without a time step (render_solved, the reader's frames) steps by the time
    /// passed since, so the cloth runs in real time whichever path skins it.
    last_step: Option<std::time::Instant>,
    /// One neighbour per particle: with its normal, the particle's local frame. A move kept from an older pose (the
    /// host's result a frame late, the last result on a pose without a step) turns with that frame: carried as a fixed
    /// world vector, a sleeve slid off the turning arm and showed it (Keqing running, 2026-11-20).
    nbr: Vec<u32>,
    /// The targets the host's running job was given (its result is for these).
    launch_target: Vec<[f32; 3]>,
    /// Per particle and body capsule: how close to the capsule's axis it may come (particle * caps + capsule). From the
    /// pose the cloth was built in: min(the capsule grown by OK_CLOTH_PX_CAPSULE, its distance then - margin), a
    /// backstop. A per-frame limit by the skinned target let a stepping thigh through the skirt (the target skirt does
    /// not move with the leg) and a sleeve sag onto the arm (Keqing running, 2026-11-20).
    cap_fit: Vec<f32>,
    cap_n: usize,
    /// Long-range attachment: each free particle's nearest pinned particle and its distance when built. The soft FEM
    /// surface stretched under its weight (a short skirt hung 10 cm longer than the game's, Haruno Chika walking,
    /// 2026-11-20) and a stiffer one crumpled; no free particle may get farther from its pin than OK_CLOTH_PX_STRETCH x that.
    anchor: Vec<u32>,
    anchor_len: Vec<f32>,
    /// Sleeve particles: they never sink more than 2 mm behind their skinned surface, or the shirt under the jacket
    /// showed through the sleeve (Haruno Chika, 2026-11-20).
    sleeve: Vec<bool>,
    /// Straight distance to the anchor when built: how far the garment's shape has moved since (made again past
    /// OK_CLOTH_PX_REBUILD, 30%, at most every half second; a walk's own skirt keys move it 6-13%).
    straight: Vec<f32>,
    built: std::time::Instant,
    /// Made on a pose that was not moving (made again once it moves).
    made_still: bool,
}
struct Entry { detect: Option<Arc<Detect>>, sim: Option<Sim>, failed: bool, pose: PoseWatch }
/// Whether the garment is being animated. PhysX keeps the rest shape a cloth was made in, and the bind pose (the
/// reader's first frames, a still Studio pose) has the skirt higher than a clip's own skirt keys hang it: made then,
/// the cloth held the hem 3-5 cm up for good (2026-11-20). So a cloth is made after 1.5 s of motion (a crossfade out of
/// the bind pose had not ended at 0.5 s), or after two still seconds; one made still is made again once it has moved 1.5 s.
#[derive(Default)]
struct PoseWatch { last: Vec<[f32; 3]>, changed: Option<std::time::Instant>, moving_since: Option<std::time::Instant>, first: Option<std::time::Instant> }
impl PoseWatch {
    /// Updates from this frame's garment; true while it moves (a still frame within 0.25 s of a change still counts).
    fn see(&mut self, positions: &[[f32; 3]]) -> bool {
        let now = std::time::Instant::now();
        self.first.get_or_insert(now);
        let moved = self.last.len() != positions.len()
            || self.last.iter().zip(positions).any(|(a, b)| (a[0] - b[0]).abs() + (a[1] - b[1]).abs() + (a[2] - b[2]).abs() > 5e-4);
        if moved { self.last = positions.to_vec(); self.changed = Some(now); self.moving_since.get_or_insert(now); }
        else if self.changed.is_none_or(|t| now.duration_since(t).as_secs_f32() > 0.25) { self.moving_since = None; }
        self.moving_since.is_some()
    }
    fn moved_for(&self) -> f32 { self.moving_since.map_or(0., |t| t.elapsed().as_secs_f32()) }
    fn still_for(&self) -> f32 { self.changed.or(self.first).map_or(0., |t| t.elapsed().as_secs_f32()) }
}
type Map = HashMap<(usize, usize), Arc<Mutex<Entry>>>;
static STATES: Mutex<Option<Map>> = Mutex::new(None);

fn entry(session: usize, index: usize, part: &crate::session::SessionPart) -> Option<Arc<Mutex<Entry>>> {
    let sig = part.runtime_accessory.as_ref().map(|r| (r.source_mesh().weights.len(), r.source_mesh().indices.len()))?;
    let mut all = STATES.lock().unwrap();
    let map = all.get_or_insert_with(HashMap::new);
    if let Some(e) = map.get(&(session, index)) {
        let fresh = e.lock().unwrap().detect.as_ref().map_or(true, |d| d.sig == sig);
        if fresh { return Some(e.clone()); }
        release_entry(&mut e.lock().unwrap());
    }
    let e = Arc::new(Mutex::new(Entry { detect: detect(part).map(Arc::new), sim: None, failed: false, pose: PoseWatch::default() }));
    map.insert((session, index), e.clone());
    Some(e)
}
fn release_entry(e: &mut Entry) {
    if let (Some(sim), Some((_, _, release))) = (e.sim.take(), host()) { if sim.created { unsafe { release(sim.key) } } }
}

/// The session went away: its cloths released on the host.
pub fn forget(session: usize) {
    let gone: Vec<Arc<Mutex<Entry>>> = {
        let mut all = STATES.lock().unwrap();
        let Some(map) = all.as_mut() else { return };
        let keys: Vec<_> = map.keys().filter(|(s, _)| *s == session).copied().collect();
        keys.into_iter().filter_map(|k| map.remove(&k)).collect()
    };
    for e in gone { release_entry(&mut e.lock().unwrap()); }
}
/// Mode changed: every cloth starts over (released on the host, detection again).
pub fn reset_all() {
    let gone: Vec<Arc<Mutex<Entry>>> = STATES.lock().unwrap().take().map(|m| m.into_values().collect()).unwrap_or_default();
    for e in gone { release_entry(&mut e.lock().unwrap()); }
}

/// Whether this garment is cloth now (it must be drawn from its CPU vertices).
pub fn is_cloth(session: usize, index: usize, part: &crate::session::SessionPart) -> bool {
    if !active() || part.runtime_accessory.is_none() { return false; }
    let Some(e) = entry(session, index, part) else { return false };
    let e = e.lock().unwrap();
    !e.failed && e.detect.is_some()
}
/// Whether its DynamicBones must stay off this frame (its skirt is cloth): one driver per region.
pub fn takes_over_dynamics(session: usize, index: usize, part: &crate::session::SessionPart) -> bool {
    if !active() || part.runtime_accessory.is_none() { return false; }
    let Some(e) = entry(session, index, part) else { return false };
    let e = e.lock().unwrap();
    !e.failed && e.detect.as_ref().is_some_and(|d| d.skirt)
}

// ---- vector helpers
fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn add(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[0] + b[0], a[1] + b[1], a[2] + b[2]] }
fn scale(a: [f32; 3], s: f32) -> [f32; 3] { [a[0] * s, a[1] * s, a[2] * s] }
fn dot(a: [f32; 3], b: [f32; 3]) -> f32 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
fn len(a: [f32; 3]) -> f32 { dot(a, a).sqrt() }
fn smooth(e0: f32, e1: f32, x: f32) -> f32 { let t = ((x - e0) / (e1 - e0)).clamp(0., 1.); t * t * (3. - 2. * t) }
fn bone_pos(skel: &crate::pose::Skeleton, name: &str) -> Option<[f32; 3]> {
    crate::bone_world(Some(skel), None, name).map(|m| [m[0][3], m[1][3], m[2][3]])
}
/// Closest point parameter and distance of p to the segment a-b.
fn seg_closest(p: [f32; 3], a: [f32; 3], b: [f32; 3]) -> (f32, f32) {
    let ab = sub(b, a);
    let l2 = dot(ab, ab);
    let t = if l2 > 1e-12 { (dot(sub(p, a), ab) / l2).clamp(0., 1.) } else { 0. };
    (t, len(sub(p, add(a, scale(ab, t)))))
}

/// Builds the simulation mesh of a garment from its region, at the targets of this frame.
fn build(d: &Detect, indices: &[u32], targets: &[[f32; 3]], skel: &crate::pose::Skeleton) -> Option<Sim> {
    let n = targets.len();
    if d.kind.len() != n { return None; }
    let t = tune();
    // Triangles touching the region, all three vertices simulated (the ones outside it pinned: the border).
    let mut used = vec![false; n];
    let mut raw: Vec<[u32; 3]> = Vec::new();
    for tri in indices.chunks_exact(3) {
        let v = [tri[0] as usize, tri[1] as usize, tri[2] as usize];
        if v.iter().any(|&i| i >= n) { continue; }
        if v.iter().any(|&i| d.kind[i] != 0) { for &i in &v { used[i] = true; } raw.push([tri[0], tri[1], tri[2]]); }
    }
    // Weld vertices at one position (UV seams, the double-sided copies) into one particle: within WELD of each other,
    // found in the neighbouring cells of a 1 mm grid. Exact positions only left the skirt's seams apart, a slit opening
    // down its front (Keqing, 2026-11-20).
    const WELD: f32 = 3.0e-4;
    let cell = |p: [f32; 3]| -> [i64; 3] { std::array::from_fn(|i| (p[i] * 1000.).floor() as i64) };
    let mut grid: HashMap<[i64; 3], Vec<u32>> = HashMap::new();
    let mut particle_of = vec![u32::MAX; n];
    let mut rep: Vec<u32> = Vec::new();
    let mut all_region: Vec<bool> = Vec::new();
    let mut kind_of: Vec<u8> = Vec::new();
    let mut depth_of: Vec<f32> = Vec::new();
    for v in 0..n {
        if !used[v] { continue; }
        let c = cell(targets[v]);
        let mut found = None;
        'search: for dx in -1..=1 { for dy in -1..=1 { for dz in -1..=1 {
            if let Some(list) = grid.get(&[c[0] + dx, c[1] + dy, c[2] + dz]) {
                for &id in list { if len(sub(targets[rep[id as usize] as usize], targets[v])) <= WELD { found = Some(id); break 'search; } }
            }
        } } }
        let id = match found {
            Some(id) => id,
            None => {
                rep.push(v as u32); all_region.push(true); kind_of.push(0); depth_of.push(1.);
                let id = (rep.len() - 1) as u32;
                grid.entry(c).or_default().push(id);
                id
            }
        };
        particle_of[v] = id;
        let p = id as usize;
        if d.kind[v] == 0 { all_region[p] = false; } else { kind_of[p] = d.kind[v]; depth_of[p] = depth_of[p].min(d.depth[v]); }
    }
    let np = rep.len();
    if np < 8 { return None; }
    let mut seen: std::collections::HashSet<[u32; 3]> = std::collections::HashSet::new();
    let mut tris: Vec<[u32; 3]> = Vec::new();
    for tri in &raw {
        let p = [particle_of[tri[0] as usize], particle_of[tri[1] as usize], particle_of[tri[2] as usize]];
        if p[0] == p[1] || p[1] == p[2] || p[0] == p[2] { continue; }
        // Slivers the weld left (a seam or hem folded onto itself): a near-zero area element is infinitely stiff and
        // flung its particles metres away, the max distance then showing them as a lifted skirt (2026-11-20).
        let (a, b, c) = (targets[rep[p[0] as usize] as usize], targets[rep[p[1] as usize] as usize], targets[rep[p[2] as usize] as usize]);
        let (e0, e1, e2) = (len(sub(b, a)), len(sub(c, b)), len(sub(a, c)));
        let area = 0.5 * len(cross(sub(b, a), sub(c, a)));
        let longest = e0.max(e1).max(e2);
        if area < 2.0e-7 || area < 0.02 * longest * longest { continue; }
        let mut s = p; s.sort_unstable();
        if seen.insert(s) { tris.push(p); }
    }
    if tris.len() < 8 { return None; }
    orient(&mut tris);
    let mut nbr = vec![u32::MAX; np];
    for t in &tris { for k in 0..3 { let p = t[k] as usize; if nbr[p] == u32::MAX { nbr[p] = t[(k + 1) % 3]; } } }
    let pos: Vec<[f32; 3]> = rep.iter().map(|&v| targets[v as usize]).collect();
    // Sleeves: where each vertex sits along shoulder -> elbow -> wrist, and how far from that line.
    let arms: [Option<[[f32; 3]; 3]>; 2] = std::array::from_fn(|s| {
        let side = if s == 0 { "L" } else { "R" };
        Some([bone_pos(skel, &format!("cf_j_arm00_{side}"))?, bone_pos(skel, &format!("cf_j_forearm01_{side}"))?, bone_pos(skel, &format!("cf_j_hand_{side}"))?])
    });
    let along = |p: [f32; 3], arm: &[[f32; 3]; 3]| -> (f32, f32) {
        let (l0, l1) = (len(sub(arm[1], arm[0])), len(sub(arm[2], arm[1])));
        let (t0, r0) = seg_closest(p, arm[0], arm[1]);
        let (t1, r1) = seg_closest(p, arm[1], arm[2]);
        if r0 <= r1 { (t0 * l0 / (l0 + l1).max(1e-6), r0) } else { ((l0 + t1 * l1) / (l0 + l1).max(1e-6), r1) }
    };
    let mut u = vec![0f32; np];
    let mut r = vec![0f32; np];
    let mut umax = [0f32; 2];
    for p in 0..np {
        let k = kind_of[p];
        if k == KIND_SLEEVE_L || k == KIND_SLEEVE_R {
            let s = (k - KIND_SLEEVE_L) as usize;
            if let Some(arm) = &arms[s] { let (a, b) = along(pos[p], arm); u[p] = a; r[p] = b; if all_region[p] { umax[s] = umax[s].max(a); } }
        }
    }
    let mut in_tri = vec![false; np];
    for t3 in &tris { for &q in t3 { in_tri[q as usize] = true; } }
    let mut pinned = vec![false; np];
    for p in 0..np {
        let k = kind_of[p];
        // A particle no element holds would only fall: it follows the pose.
        pinned[p] = !all_region[p] || !in_tri[p] || match k {
            KIND_SKIRT => depth_of[p] < t.pin_t,
            KIND_SLEEVE_L | KIND_SLEEVE_R => {
                let s = (k - KIND_SLEEVE_L) as usize;
                arms[s].is_none() || u[p] < t.shoulder_u || u[p] > umax[s] - t.cuff_u
            }
            _ => true,
        };
    }
    let pins: Vec<usize> = (0..np).filter(|&p| pinned[p]).collect();
    if pins.is_empty() { return None; }
    let mut max_dist = vec![0f32; np];
    let mut anchor = vec![u32::MAX; np];
    let mut anchor_len = vec![0f32; np];
    let mut straight = vec![0f32; np];
    let mut free = 0usize;
    // Multi-source Dijkstra from every pin over the welded triangle edges.
    let mut adj: Vec<Vec<(u32, f32)>> = vec![Vec::new(); np];
    for t3 in &tris { for k in 0..3 { let (a, b) = (t3[k] as usize, t3[(k + 1) % 3] as usize); let w = len(sub(pos[a], pos[b])); adj[a].push((b as u32, w)); adj[b].push((a as u32, w)); } }
    let mut geo = vec![f32::MAX; np];
    let mut geo_src = vec![u32::MAX; np];
    let mut heap = std::collections::BinaryHeap::new();
    for &q in &pins { geo[q] = 0.; geo_src[q] = q as u32; heap.push((std::cmp::Reverse(0u32), q as u32)); }
    while let Some((std::cmp::Reverse(dk), a)) = heap.pop() {
        let a = a as usize;
        if f32::from_bits(dk) > geo[a] { continue; }
        for &(b, w) in &adj[a] {
            let nd = geo[a] + w;
            if nd < geo[b as usize] { geo[b as usize] = nd; geo_src[b as usize] = geo_src[a]; heap.push((std::cmp::Reverse(nd.to_bits()), b)); }
        }
    }
    for p in 0..np {
        if pinned[p] { continue; }
        let (near_id, near) = pins.iter().map(|&q| (q, len(sub(pos[p], pos[q])))).fold((0, f32::MAX), |a, b| if b.1 < a.1 { b } else { a });
        // LRA: the rest distance along the cloth to the pin it hangs from, not the straight line --
        // a flared skirt is longer over the hips than the chord from waist to hem.
        anchor[p] = geo_src[p];
        anchor_len[p] = if geo_src[p] == u32::MAX { let _ = near_id; near } else { geo[p] };
        if anchor[p] != u32::MAX { straight[p] = len(sub(pos[p], pos[anchor[p] as usize])); }
        max_dist[p] = match kind_of[p] {
            KIND_SKIRT => (t.skirt_reach * near * smooth(t.pin_t, t.pin_t + 0.25, depth_of[p])).min(t.skirt_max),
            _ => (t.sleeve_reach * near).min(0.012 + 0.6 * (r[p] - 0.05).max(0.)).min(t.sleeve_max),
        };
        if max_dist[p] > 1e-4 { free += 1; } else { pinned[p] = true; }
    }
    if free < 16 { return None; }
    Some(Sim { key: NEXT_KEY.fetch_add(1, Ordering::Relaxed), created: false, particle_of, rep, pinned, max_dist, tris,
        offsets: vec![[0.; 3]; np], launch_target: pos.clone(), last_target: pos, free, last_step: None, nbr, cap_fit: Vec::new(), cap_n: 0, anchor, anchor_len,
        sleeve: kind_of.iter().map(|k| *k == KIND_SLEEVE_L || *k == KIND_SLEEVE_R).collect(), straight, built: std::time::Instant::now(), made_still: false })
}

/// Body capsules for the cloth: limbs, hips and torso of the skeleton (no head, no floor sphere), as the body proxies
/// (the host collides with these; Rust's backstop grows them, cap_fit).
fn capsules(skel: &crate::pose::Skeleton) -> Vec<OkPxCapsule> {
    crate::dbone::body_proxy_capsules(skel).into_iter().filter(|c| c.radius > 0. && c.radius < 1.0).collect()
}

fn particle_normals(pos: &[[f32; 3]], tris: &[[u32; 3]]) -> Vec<[f32; 3]> {
    let mut n = vec![[0f32; 3]; pos.len()];
    for t in tris {
        let (a, b, c) = (pos[t[0] as usize], pos[t[1] as usize], pos[t[2] as usize]);
        let f = cross(sub(b, a), sub(c, a));
        for &i in t { n[i as usize] = add(n[i as usize], f); }
    }
    for v in &mut n { let l = len(*v); if l > 1e-12 { *v = scale(*v, 1. / l); } }
    n
}
/// OK_CLOTH_PX_DEBUG=1: true about once a second per cloth.
fn debug_due(key: u64) -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    if !*ON.get_or_init(|| std::env::var("OK_CLOTH_PX_DEBUG").is_ok_and(|v| v == "1")) { return false; }
    static LAST: Mutex<Option<HashMap<u64, std::time::Instant>>> = Mutex::new(None);
    let mut m = LAST.lock().unwrap();
    let m = m.get_or_insert_with(HashMap::new);
    let now = std::time::Instant::now();
    if m.get(&key).is_some_and(|t| now.duration_since(*t).as_secs_f32() < 1.) { return false; }
    m.insert(key, now);
    true
}
/// One winding for every connected patch. A double-sided garment welds its back faces onto its front ones; the
/// deduplication keeps whichever came first, so neighbours could disagree, and the cloth's rest bending angles then
/// fold the pleats the wrong way (the skirt opened up like an umbrella, 2026-11-20).
fn orient(tris: &mut [[u32; 3]]) {
    let mut by_edge: std::collections::HashMap<(u32, u32), Vec<usize>> = std::collections::HashMap::new();
    for (i, t) in tris.iter().enumerate() {
        for k in 0..3 { let (a, b) = (t[k], t[(k + 1) % 3]); by_edge.entry((a.min(b), a.max(b))).or_default().push(i); }
    }
    let has = |t: &[u32; 3], a: u32, b: u32| (0..3).any(|k| t[k] == a && t[(k + 1) % 3] == b);
    let mut done = vec![false; tris.len()];
    for seed in 0..tris.len() {
        if done[seed] { continue; }
        done[seed] = true;
        let mut stack = vec![seed];
        while let Some(i) = stack.pop() {
            let t = tris[i];
            for k in 0..3 {
                let (a, b) = (t[k], t[(k + 1) % 3]);
                let Some(list) = by_edge.get(&(a.min(b), a.max(b))) else { continue };
                // Only a manifold edge says how its neighbour must wind.
                if list.len() != 2 { continue; }
                for &j in list {
                    if j == i || done[j] { continue; }
                    // Agreeing windings run a shared edge in opposite directions.
                    if has(&tris[j], a, b) { tris[j].swap(1, 2); }
                    done[j] = true;
                    stack.push(j);
                }
            }
        }
    }
}
/// Each particle's local frame (tangent to its neighbour, bitangent, normal) at these positions.
fn frames(pos: &[[f32; 3]], tris: &[[u32; 3]], nbr: &[u32]) -> Vec<[[f32; 3]; 3]> {
    let normals = particle_normals(pos, tris);
    (0..pos.len()).map(|p| {
        let n = normals[p];
        let q = nbr.get(p).copied().filter(|q| *q != u32::MAX).map_or(pos[p], |q| pos[q as usize]);
        let e = sub(q, pos[p]);
        let t = sub(e, scale(n, dot(e, n)));
        let lt = len(t);
        if lt < 1e-9 || len(n) < 0.5 { return [[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]; }
        let t = scale(t, 1. / lt);
        [t, cross(n, t), n]
    }).collect()
}
/// `v` given in frame `from`, the same vector in frame `to`.
fn carry(v: [f32; 3], from: &[[f32; 3]; 3], to: &[[f32; 3]; 3]) -> [f32; 3] {
    if !tune().carry { return v; }
    let c = [dot(v, from[0]), dot(v, from[1]), dot(v, from[2])];
    add(add(scale(to[0], c[0]), scale(to[1], c[1])), scale(to[2], c[2]))
}
/// Turns `v` by the rotation that takes unit `a` onto unit `b`.
fn turn(v: [f32; 3], a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    let c = dot(a, b);
    if c > 0.99999 || c < -0.999 { return v; }
    let k = cross(a, b);
    // Rodrigues with sin = |k|, cos = c.
    let kv = cross(k, v);
    add(add(v, kv), scale(cross(k, kv), 1. / (1. + c)))
}

#[derive(Clone, Copy)]
pub(crate) struct Stats { pub cloths: u32, pub particles: u32, pub free: u32, pub steps: u64, pub step_us: u64, pub max_offset_mm: f32, pub clamped: u64, pub pushed: u64 }
static STATS: Mutex<Stats> = Mutex::new(Stats { cloths: 0, particles: 0, free: 0, steps: 0, step_us: 0, max_offset_mm: 0., clamped: 0, pushed: 0 });
pub(crate) fn take_stats() -> Stats {
    let mut s = STATS.lock().unwrap();
    let out = Stats { ..*s };
    s.steps = 0; s.step_us = 0; s.max_offset_mm = 0.; s.clamped = 0; s.pushed = 0;
    // Live counts.
    let all = STATES.lock().unwrap();
    let (mut c, mut p, mut f) = (0u32, 0u32, 0u32);
    if let Some(map) = all.as_ref() { for e in map.values() { if let Ok(e) = e.try_lock() { if let Some(sim) = &e.sim { if sim.created { c += 1; p += sim.rep.len() as u32; f += sim.free as u32; } } } } }
    Stats { cloths: c, particles: p, free: f, ..out }
}

/// A garment just skinned (`positions`/`normals` in her skeleton space, metres): its cloth stepped by `dt` (0: the last
/// result kept on the new pose) and written over its region.
pub(crate) fn apply(session: usize, index: usize, part: &crate::session::SessionPart, skel: Option<&crate::pose::Skeleton>,
    positions: &mut [[f32; 3]], normals: &mut [[f32; 3]], dt: f32) {
    if !active() { return; }
    let Some(skel) = skel else { return };
    let Some(runtime) = part.runtime_accessory.as_ref() else { return };
    let Some((create, step, _)) = host() else { return };
    let Some(e) = entry(session, index, part) else { return };
    let mut e = e.lock().unwrap();
    if e.failed { return; }
    let Some(d) = e.detect.clone() else { return };
    if positions.len() != d.kind.len() { return; }
    let moving = e.pose.see(positions);
    if e.sim.as_ref().is_some_and(|s| s.made_still) && moving && e.pose.moved_for() >= 1.5 {
        crate::ffi::ffi_log(1, &format!("OK cloth px: part {index} ({}) started moving, made again on the moving pose", part.role));
        release_entry(&mut e);
    }
    if e.sim.is_none() && e.pose.moved_for() < 1.5 && e.pose.still_for() < 2. { return; }
    // The garment's shape moved far from the one the cloth was made in (the reader's first frame is the bind pose,
    // a skirt spread out; the walk then hangs it): PhysX keeps the rest shape it was made with (a later rest upload
    // changed nothing), so the cloth held the skirt 5 cm up (2026-11-20). Made again on this shape.
    if let Some(sim) = e.sim.as_ref().filter(|s| s.created && s.built.elapsed().as_secs_f32() > 0.5) {
        let (mut drift, mut n) = (0f32, 0usize);
        for p in 0..sim.rep.len() {
            let a = sim.anchor[p];
            if a == u32::MAX || sim.anchor_len[p] < 0.02 { continue; }
            let l = len(sub(positions[sim.rep[p] as usize], positions[sim.rep[a as usize] as usize]));
            drift += (l - sim.straight[p]).abs() / sim.straight[p].max(1e-4);
            n += 1;
        }
        if n > 0 && drift / n as f32 > tune().rebuild {
            crate::ffi::ffi_log(1, &format!("OK cloth px: part {index} ({}) changed shape ({:.0}% from its rest), made again", part.role, drift / n as f32 * 100.));
            release_entry(&mut e);
        }
    }
    if e.sim.is_none() {
        match build(&d, &runtime.source_mesh().indices, positions, skel) {
            Some(mut sim) => { sim.made_still = !moving; e.sim = Some(sim) }
            None => { e.failed = true; crate::ffi::ffi_log(1, &format!("OK cloth px: part {index} ({}) has no usable cloth region, DynamicBone kept", part.role)); return; }
        }
    }
    let sim = e.sim.as_mut().unwrap();
    let np = sim.rep.len();
    let targets: Vec<[f32; 3]> = sim.rep.iter().map(|&v| positions[v as usize]).collect();
    if !sim.created {
        let inv: Vec<f32> = sim.pinned.iter().map(|p| if *p { 0. } else { 1. }).collect();
        let ok = unsafe { create(sim.key, np as u32, targets.as_ptr().cast(), inv.as_ptr(), sim.tris.len() as u32, sim.tris.as_ptr().cast(), d.skirt as u32) };
        if ok != 1 {
            e.failed = true; e.sim = None;
            crate::ffi::ffi_log(2, &format!("OK cloth px: host could not create the cloth of part {index} ({}), DynamicBone kept", part.role));
            return;
        }
        sim.created = true;
        sim.last_target = targets.clone();
        let mut out = vec![[0f32; 3]; np];
        unsafe { step(sim.key, np as u32, targets.as_ptr().cast(), std::ptr::null(), std::ptr::null(), 0, -1., out.as_mut_ptr().cast()); }
        crate::ffi::ffi_log(1, &format!("OK cloth px: part {index} ({}) skirt={} sleeves={} particles={np} free={} triangles={}",
            part.role, d.skirt, d.sleeves, sim.free, sim.tris.len()));
    }
    // A jump of the pose (new animation, teleport): start again on the targets.
    let jump = targets.iter().zip(&sim.last_target).map(|(a, b)| len(sub(*a, *b))).fold(0f32, f32::max);
    let caps = capsules(skel);
    if sim.cap_n != caps.len() || sim.cap_fit.len() != np * caps.len() {
        let t = tune();
        sim.cap_n = caps.len();
        sim.cap_fit = (0..np).flat_map(|p| caps.iter().map(move |c| (p, c)).collect::<Vec<_>>())
            .map(|(p, c)| (c.radius * t.cap_scale).min((seg_closest(targets[p], c.a, c.b).1 - t.cap_margin).max(0.))).collect();
    }
    let now = std::time::Instant::now();
    let dt = if dt > 0. { dt } else {
        let passed = sim.last_step.map_or(0., |t| now.duration_since(t).as_secs_f32());
        if passed >= 0.004 { passed.min(0.1) } else { 0. }
    };
    if dt > 0. || sim.last_step.is_none() { sim.last_step = Some(now); }
    // The last result's moves, turned from the last pose's local frames to this pose's.
    let now_frames = frames(&targets, &sim.tris, &sim.nbr);
    let last_frames = frames(&sim.last_target, &sim.tris, &sim.nbr);
    let carried: Vec<[f32; 3]> = (0..np).map(|p| add(targets[p], carry(sim.offsets[p], &last_frames[p], &now_frames[p]))).collect();
    let mut sim_pos: Vec<[f32; 3]>;
    if dt > 0. {
        let t0 = std::time::Instant::now();
        sim_pos = vec![[0f32; 3]; np];
        let reset = jump > 0.35;
        let ok = unsafe { step(sim.key, np as u32, targets.as_ptr().cast(), carried.as_ptr().cast(), caps.as_ptr(), caps.len() as u32, if reset { -1. } else { dt }, sim_pos.as_mut_ptr().cast()) };
        match ok {
            1 => {}
            // The host's result for the targets its job was given (it simulates while frames render): carried onto this pose.
            2 => {
                let launch_frames = frames(&sim.launch_target, &sim.tris, &sim.nbr);
                for p in 0..np { sim_pos[p] = add(targets[p], carry(sub(sim_pos[p], sim.launch_target[p]), &launch_frames[p], &now_frames[p])); }
            }
            _ => sim_pos = carried.clone(),
        }
        // 3: its job still runs (nothing launched); otherwise a job now runs on these targets.
        if ok != 3 { sim.launch_target = targets.clone(); }
        let mut st = STATS.lock().unwrap(); st.steps += 1; st.step_us += t0.elapsed().as_micros() as u64;
    } else {
        sim_pos = carried;
    }
    sim.last_target = targets.clone();
    if debug_due(sim.key) {
        // Raw cloth against the pose: how far down (-) / up (+) and out from the pinned ring's axis the free part sits.
        let pins: Vec<usize> = (0..np).filter(|&p| sim.pinned[p]).collect();
        let c = pins.iter().fold([0f32; 3], |a, &p| add(a, targets[p]));
        let c = scale(c, 1. / pins.len().max(1) as f32);
        let (mut dy, mut dr, mut n, mut far) = (0f64, 0f64, 0usize, 0usize);
        for p in 0..np {
            if sim.pinned[p] { continue; }
            let (a, b) = (sim_pos[p], targets[p]);
            if len(sub(a, b)) > 0.5 { far += 1; continue; }
            dy += (a[1] - b[1]) as f64;
            dr += ((a[0] - c[0]).hypot(a[2] - c[2]) - (b[0] - c[0]).hypot(b[2] - c[2])) as f64;
            n += 1;
        }
        let n = n.max(1) as f64;
        crate::ffi::ffi_log(1, &format!("OK cloth px debug: cloth {} free {} raw mean dy {:.1} mm, mean out {:.1} mm, {far} flung (pin centre y {:.3})", sim.key, n, dy / n * 1000., dr / n * 1000., c[1]));
    }
    // Max distance, then out of the body (never deeper than the target already was).
    let (mut clamped, mut pushed, mut most) = (0u64, 0u64, 0f32);
    let stretch = tune().stretch;
    for p in 0..np {
        if sim.pinned[p] { sim_pos[p] = targets[p]; continue; }
        if !sim_pos[p].iter().all(|x| x.is_finite()) { sim_pos[p] = targets[p]; continue; }
        if let Some(&a) = sim.anchor.get(p).filter(|a| **a != u32::MAX) {
            let pin = targets[a as usize];
            let v = sub(sim_pos[p], pin);
            let d = len(v);
            // Never shorter than the garment as posed now: a clip's own skirt keys stretch it past the lengths of the
            // pose it was built in (the reader's bind pose), and that limit held the hem 4 cm up (2026-11-20).
            let limit = sim.anchor_len[p].max(len(sub(targets[p], pin))) * stretch;
            if d > limit && d > 1e-9 { sim_pos[p] = add(pin, scale(v, limit / d)); }
        }
        let mut off = sub(sim_pos[p], targets[p]);
        if sim.sleeve[p] {
            if let Some(n) = normals.get(sim.rep[p] as usize).copied().filter(|n| len(*n) > 0.5) {
                let d = dot(off, n);
                if d < -0.002 { off = sub(off, scale(n, d + 0.002)); sim_pos[p] = add(targets[p], off); }
            }
        }
        let l = len(off);
        if l > sim.max_dist[p] { sim_pos[p] = add(targets[p], scale(off, sim.max_dist[p] / l)); clamped += 1; }
        for (ci, c) in caps.iter().enumerate() {
            let r = sim.cap_fit[p * sim.cap_n + ci];
            if r <= 0. { continue; }
            let ab = sub(c.b, c.a);
            let l2 = dot(ab, ab);
            let s = if l2 > 1e-12 { (dot(sub(sim_pos[p], c.a), ab) / l2).clamp(0., 1.) } else { 0. };
            let axis = add(c.a, scale(ab, s));
            let v = sub(sim_pos[p], axis);
            let dl = len(v);
            if dl < r && dl > 1e-6 { sim_pos[p] = add(axis, scale(v, r / dl)); pushed += 1; }
        }
        most = most.max(len(sub(sim_pos[p], targets[p])));
    }
    // What the next step starts from eases back toward the garment as skinned (OK_CLOTH_PX_PULL per second): a pleat
    // the walk flipped stayed flipped, its bending holding the skirt 3-5 cm up even standing (2026-11-20).
    let keep = if dt > 0. { (-tune().pull * dt).exp() } else { 1. };
    for p in 0..np { sim.offsets[p] = scale(sub(sim_pos[p], targets[p]), keep); }
    // Normals turned with the cloth, then the region written.
    let nt = particle_normals(&targets, &sim.tris);
    let ns = particle_normals(&sim_pos, &sim.tris);
    for v in 0..positions.len() {
        let p = sim.particle_of[v];
        if p == u32::MAX { continue; }
        let p = p as usize;
        if sim.pinned[p] { continue; }
        positions[v] = sim_pos[p];
        if let Some(n) = normals.get_mut(v) { *n = turn(*n, nt[p], ns[p]); }
    }
    let mut st = STATS.lock().unwrap();
    st.clamped += clamped; st.pushed += pushed; st.max_offset_mm = st.max_offset_mm.max(most * 1000.);
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn orient_flips_disagreeing_neighbour() {
        let mut t = [[0u32, 1, 2], [1, 2, 3]];
        orient(&mut t);
        // Edge 1-2 runs 1->2 in the first, so the second must run 2->1.
        assert!((0..3).any(|k| t[1][k] == 2 && t[1][(k + 1) % 3] == 1));
    }
    #[test]
    fn names() {
        assert_eq!(skirt_level("cf_j_sk_03_04"), Some(4));
        assert_eq!(skirt_level("cf_j_sk_top"), None);
        assert_eq!(arm_side("cf_j_forearm01_L"), Some(0));
        assert_eq!(arm_side("cf_s_wrist_R"), Some(1));
        assert_eq!(arm_side("cf_j_shoulder_L"), None);
        assert_eq!(arm_side("cf_j_index01_L"), None);
        assert!(skirt_role("clothes_bot") && skirt_role("clothes_top") && !skirt_role("clothes_socks"));
    }
    /// OK_CLOTH_CARD=<card.png>[;<card.png>...]: what each garment's detection finds (its chains, its weights).
    #[test]
    #[ignore = "local cards: OK_CLOTH_CARD"]
    fn describe_cards() {
        set_mode(1);
        let cards = std::env::var("OK_CLOTH_CARD").expect("OK_CLOTH_CARD");
        for card in cards.split(';').filter(|c| !c.is_empty()) {
            let game = std::ffi::CString::new("").unwrap();
            let c = std::ffi::CString::new(card).unwrap();
            let mut out = std::ptr::null_mut();
            let mut err = [0i8; 512];
            let r = unsafe { crate::ffi::session_open(game.as_ptr(), c.as_ptr(), 0, &mut out, err.as_mut_ptr(), 512) };
            if r != 0 { eprintln!("CARD {card}: open failed {}", unsafe { std::ffi::CStr::from_ptr(err.as_ptr()) }.to_string_lossy()); continue; }
            let s = unsafe { &mut *out };
            for (i, p) in s.parts.iter().enumerate() {
                if !p.role.starts_with("clothes") { continue; }
                let Some(rt) = p.runtime_accessory.as_ref() else { continue };
                let src = rt.source_mesh();
                let d = detect(p);
                let (sk, sl) = d.as_ref().map_or((0, 0), |d| (d.kind.iter().filter(|k| **k == KIND_SKIRT).count(), d.kind.iter().filter(|k| **k >= KIND_SLEEVE_L).count()));
                // Where her unclaimed bones hang: the ancestry of the most weighted bone.
                let anc = |name: &str| -> String {
                    let Some(sk) = src.smr_skel.as_ref() else { return String::new() };
                    let Some((mut id, _)) = sk.tfs.iter().find(|(_, t)| t.name == name).map(|(id, t)| (*id, t)) else { return "?".into() };
                    let mut path = Vec::new();
                    while let Some(t) = sk.tfs.get(&id) { path.push(t.name.clone()); match t.parent { Some(p) => id = p, None => break } if path.len() > 12 { break; } }
                    path.join("<")
                };
                let mut sums = vec![0f32; src.bone_names.len()];
                for v in 0..src.weights.len() { for k in 0..4 { if let Some(x) = sums.get_mut(src.bone_idx[v][k] as usize) { *x += src.weights[v][k]; } } }
                let top = (0..sums.len()).max_by(|a, b| sums[*a].total_cmp(&sums[*b])).map(|b| src.bone_names[b].clone()).unwrap_or_default();
                eprintln!("CARD {card} part {i} {} verts={} skirt={sk} sleeve={sl} dbones={} top={top} path={}",
                    p.role, src.weights.len(), src.deferred_dbones.is_some(), anc(&top));
            }
        }
    }
    #[test]
    fn turn_keeps_length_and_maps_axis() {
        let a = [0., 1., 0.];
        let b = [1., 0., 0.];
        let r = turn(a, a, b);
        assert!(len(sub(r, b)) < 1e-5);
        let w = turn([0., 0., 2.], a, b);
        assert!((len(w) - 2.).abs() < 1e-5);
    }
}
