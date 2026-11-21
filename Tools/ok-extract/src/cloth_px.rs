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
/// Bit 1: `prev` of each step holds corrections (the move Rust gave each vertex of the last result shown), not positions.
pub type CreateFn = unsafe extern "C" fn(key: u64, n: u32, pos: *const f32, inv_mass: *const f32, tri_n: u32, tris: *const u32, flags: u32) -> i32;
/// dt < 0: put every vertex on its target at rest (teleport, first frame). Returns 1 with `out` for these targets, 2 with
/// `out` for the previous call's targets (the host simulates while the frame renders), 0 with nothing.
/// `prev`: what was shown last frame (null: the host's own state); the free vertices start there. With create flag bit 1:
/// the corrections to steer the free vertices by instead.
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
/// To Unreal's log (and stderr in tests, which have no Unreal).
fn log(level: i32, msg: &str) {
    crate::ffi::ffi_log(level, msg);
    #[cfg(test)] eprintln!("{msg}");
}

// ---- tuning (OK_CLOTH_PX_* environment overrides, read once)
fn env_f(key: &str, default: f32) -> f32 { std::env::var(key).ok().and_then(|v| v.parse().ok()).unwrap_or(default) }
struct Tune { stretch: f32, pin_t: f32, skirt_reach: f32, skirt_max: f32, chain_max: f32, long_span: f32, long_max: f32, up_max: f32, sleeve_reach: f32, sleeve_max: f32, shoulder_u: f32, cuff_u: f32, cap_scale: f32, cap_margin: f32, carry: bool, pull: f32, rebuild: f32, shin: bool, smooth: u32, edge: f32, keep_out: f32, live_push: bool, blend: bool }
fn tune() -> &'static Tune {
    static T: std::sync::OnceLock<Tune> = std::sync::OnceLock::new();
    T.get_or_init(|| Tune {
        stretch: env_f("OK_CLOTH_PX_STRETCH", 1.03),
        pin_t: env_f("OK_CLOTH_PX_PIN", 0.12),
        skirt_reach: env_f("OK_CLOTH_PX_SKIRT_REACH", 0.55),
        skirt_max: env_f("OK_CLOTH_PX_SKIRT_MAX", 0.30),
        chain_max: env_f("OK_CLOTH_PX_CHAIN_MAX", 0.06),
        // Every skirt (span 0): a cloth made mid-walk keeps that moment's flare as its rest shape (PhysX keeps the rest
        // it was made with), so a free skirt hung 1-4 cm above its pose or 1 cm below by when it was made; softer,
        // thinner, Poisson 0, more iterations, a stronger pull did not change that (2026-11-21).
        long_span: env_f("OK_CLOTH_PX_LONG_SPAN", 0.),
        long_max: env_f("OK_CLOTH_PX_LONG_MAX", 0.05),
        // A skirt is never shown higher than its pose by more than this: hanging cloth does not rise by itself, a leg
        // kicking it up is already in the DynamicBone pose (Megumin's hem showed her underwear 2 cm up).
        up_max: env_f("OK_CLOTH_PX_UP", 0.005),
        sleeve_reach: env_f("OK_CLOTH_PX_SLEEVE_REACH", 0.35),
        sleeve_max: env_f("OK_CLOTH_PX_SLEEVE_MAX", 0.08),
        shoulder_u: env_f("OK_CLOTH_PX_SHOULDER", 0.14),
        cuff_u: env_f("OK_CLOTH_PX_CUFF", 0.05),
        cap_scale: env_f("OK_CLOTH_PX_CAPSULE", 1.5),
        cap_margin: env_f("OK_CLOTH_PX_MARGIN", 0.001),
        carry: env_f("OK_CLOTH_PX_CARRY", 1.) > 0.5,
        pull: env_f("OK_CLOTH_PX_PULL", 3.),
        rebuild: env_f("OK_CLOTH_PX_REBUILD", 0.3),
        shin: env_f("OK_CLOTH_PX_SHIN", 1.) > 0.5,
        // Passes averaging a follow cloth's offsets with its neighbours'.
        smooth: env_f("OK_CLOTH_PX_SMOOTH", 2.).max(0.) as u32,
        // Longest edge of a cloth region's triangles after loading (0: the garment as authored), see cloth_refine.
        edge: env_f("OK_CLOTH_PX_EDGE", 0.025),
        // Out of the body: never nearer a capsule's axis than its pose is now, up to the capsule grown by
        // OK_CLOTH_PX_CAPSULE plus this (OK_CLOTH_PX_LIVE_PUSH=0: the room it had when the cloth was made, as before).
        keep_out: env_f("OK_CLOTH_PX_KEEP_OUT", 0.04),
        live_push: env_f("OK_CLOTH_PX_LIVE_PUSH", 1.) > 0.5,
        blend: env_f("OK_CLOTH_PX_BLEND", 1.) > 0.5,
    })
}

// ---- detection from the garment's weights
const KIND_SKIRT: u8 = 1;
const KIND_SLEEVE_L: u8 = 2;
const KIND_SLEEVE_R: u8 = 3;
/// On a garment's own sleeve chain (its DynamicBones keep posing it): the cloth only sways around that pose
/// (OK_CLOTH_PX_CHAIN_MAX). Left free, a long drape crumpled into a heap at the knee (2026-11-21).
const KIND_CHAIN: u8 = 4;

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
/// Garments whose own sleeve chains may be cloth: tops, and gloves that carry a drape on their own chains (Raiden
/// Shogun's outfit 2: a gauze wrap hung from the arms, grafted onto the body, 2026-11-21). A plain glove has no chain
/// and stays as it is.
fn chain_role(role: &str) -> bool { sleeve_role(role) || role.starts_with("clothes_gloves") }
/// Garments with DynamicBone chains of their own or bones grafted onto the body (the kimono, the gauze wrap) as
/// cloth swaying around their running DynamicBones (OK_CLOTH_PX_CHAINS=0: they stay DynamicBone, as before
/// 2026-11-21). They were left out when a free cloth rose 10 cm off them; following the DynamicBone pose (as every
/// skirt does now) keeps them on it.
fn chains_on() -> bool { std::env::var("OK_CLOTH_PX_CHAINS").map_or(true, |v| v != "0") }

/// Per render vertex: the kind (0 none) and, for a skirt vertex, its depth along the chains (0 waist .. 1 hem).
/// pleats: a pleated skirt (cf_j_sk_*), made without bending.
/// long: a long skirt, cloth around its running DynamicBones (see detect).
/// follow: on a garment whose DynamicBones keep running (own chains or grafted bones): the cloth only sways around them.
struct Detect { kind: Vec<u8>, depth: Vec<f32>, skirt: bool, sleeves: bool, pleats: bool, long: bool, follow: bool, sig: (usize, usize) }

fn detect(part: &crate::session::SessionPart) -> Option<Detect> {
    let runtime = part.runtime_accessory.as_ref()?;
    classify(runtime.source_mesh(), &part.role, runtime.implanted_bones(), mode(), true)
}
/// What of a garment mesh is cloth in this mode (1 all, 2 skirts, 3 sleeves). `implanted`: its bones grafted onto
/// the body (empty before its rig is built: the chains are then found from its own DynamicBone set).
fn classify(src: &crate::unity::ExtractedMesh, role: &str, implanted: &std::collections::HashSet<i64>, mode: i32, debug: bool) -> Option<Detect> {
    let debug = debug && std::env::var("OK_CLOTH_PX_DEBUG").is_ok_and(|v| v == "1");
    let n = src.weights.len();
    if n == 0 || src.bone_idx.len() != n || src.indices.len() < 3 { return None; }
    let (want_skirt, want_sleeve) = (skirt_role(role) && mode != 3, sleeve_role(role) && mode != 2);
    let want_chain = chain_role(role) && mode != 2 && chains_on();
    if !want_skirt && !want_sleeve && !want_chain { return None; }
    // Each bone's depth along the game's skirt chains cf_j_sk_<column>_<level> (0 waist .. 1 hem). The garment's own
    // DynamicBone chains are rooted on the clothes rig, not in its SMR skeleton (tried 2026-11-20: no bone found on any
    // test card); a mod skirt on other bones (K*/joint*) that no chain moves stays as it was.
    let max_level = src.bone_names.iter().filter_map(|b| skirt_level(b)).max().unwrap_or(0).max(1) as f32;
    let mut levels: Vec<Option<f32>> = src.bone_names.iter().map(|b| skirt_level(b).map(|l| l as f32 / max_level)).collect();
    // A mod garment's own DynamicBone chains (Raiden Shogun's kimono: +SleeveB_*, its skirt panels), found by name in
    // the renderer's skeleton: depth = steps below the chain root / the deepest step of that chain (pinned at the root, like cf_j_sk_*)
    // (2026-11-21).
    let chains = chain_levels(src, implanted, debug);
    let mut chain_bone = vec![false; src.bone_names.len()];
    // Sleeves with chains of their own are those chains: the arm-weight sleeve (pinned along the arm) put on top of
    // them collapsed the kimono's sleeves and tore its long drape (2026-11-21). As cloth they follow their running
    // DynamicBones (KIND_CHAIN, OK_CLOTH_PX_CHAIN_MAX).
    let own_sleeves = chains.iter().any(|l| l.is_some());
    let chain_sleeves = want_chain && own_sleeves;
    if chain_sleeves {
        for (b, l) in chains.iter().enumerate() { if let (Some(l), None) = (l, levels[b]) { levels[b] = Some(*l); chain_bone[b] = true; } }
    }
    // With OK_CLOTH_PX_CHAINS=0 such a garment stays DynamicBone whole: a cf_j_sk corner of it as free cloth beside its
    // DynamicBone drape jagged at the seam (the drape moves it 35%).
    if own_sleeves && !chain_sleeves { return None; }
    // So does any garment whose bones were grafted onto the body: its chains keep running in the shared clothes rig,
    // and a free cloth beside them rose 10 cm into the body (the kimono front apron on cf_j_sk, raw dy +100 mm).
    let grafted = !implanted.is_empty();
    if grafted && !chains_on() { return None; }
    let want_sleeve = want_sleeve && !own_sleeves;
    let sides: Vec<Option<usize>> = src.bone_names.iter().map(|b| arm_side(b)).collect();
    let mut kind = vec![0u8; n];
    let mut depth = vec![0f32; n];
    let (mut skirt_n, mut sleeve_n, mut chain_n) = (0usize, [0usize; 2], 0usize);
    for v in 0..n {
        let (mut total, mut sk, mut sk_level, mut arm, mut chain_w) = (0f32, 0f32, 0f32, [0f32; 2], 0f32);
        for k in 0..4 {
            let w = src.weights[v][k];
            if w <= 0. { continue; }
            total += w;
            let b = src.bone_idx[v][k] as usize;
            if let Some(Some(l)) = levels.get(b) { sk += w; sk_level += w * *l; if chain_bone[b] { chain_w += w; } }
            if let Some(Some(s)) = sides.get(b) { arm[*s] += w; }
        }
        if total <= 1e-5 { continue; }
        let on_chain = chain_w * 2. >= sk;
        if sk / total >= 0.25 && (if on_chain { chain_sleeves } else { want_skirt }) {
            kind[v] = if on_chain { KIND_CHAIN } else { KIND_SKIRT };
            depth[v] = (sk_level / total).clamp(0., 1.);
            skirt_n += 1;
            if on_chain { chain_n += 1; }
        } else if want_sleeve {
            for s in 0..2 { if arm[s] / total >= 0.5 { kind[v] = KIND_SLEEVE_L + s as u8; sleeve_n[s] += 1; } }
        }
    }
    if debug {
        let mut sums = vec![0f32; src.bone_names.len()];
        for v in 0..n { for k in 0..4 { if let Some(s) = sums.get_mut(src.bone_idx[v][k] as usize) { *s += src.weights[v][k]; } } }
        let mut order: Vec<usize> = (0..sums.len()).collect();
        order.sort_by(|a, b| sums[*b].total_cmp(&sums[*a]));
        let top: Vec<String> = order.iter().take(12).map(|&b| format!("{}={:.0}", src.bone_names[b], sums[b])).collect();
        log(1, &format!("OK cloth px detect: role={} verts={n} skirt_verts={skirt_n} (own chains {chain_n}) sleeve_verts={sleeve_n:?} chain bones={} grafted={grafted} bones: {}", role, chains.iter().filter(|l| l.is_some()).count(), top.join(" ")));
    }
    let skirt = skirt_n >= 30;
    let sleeves = sleeve_n.iter().any(|c| *c >= 30);
    if !skirt { for k in kind.iter_mut() { if *k == KIND_SKIRT || *k == KIND_CHAIN { *k = 0; } } }
    for s in 0..2 { if sleeve_n[s] < 30 { for k in kind.iter_mut() { if *k == KIND_SLEEVE_L + s as u8 { *k = 0; } } } }
    // Pleated skirts get no bending (their folds flip); a region mostly on the garment's own chains (sleeves, panels)
    // keeps it, or it slumps.
    let pleats = skirt && chain_n * 2 < skirt_n;
    // A long skirt (its region spans more than OK_CLOTH_PX_LONG_SPAN top to hem; 0 by default, so every skirt): its
    // DynamicBones keep running
    // and the cloth only sways around them (OK_CLOTH_PX_LONG_MAX). Free, Raiden's maid skirt panels swung up to mid
    // thigh, and the legs went through the front panel: the body capsules are thinner than legs in thigh-high
    // stockings, while DynamicBone's own colliders keep the panel off them (2026-11-21).
    let (mut lo, mut hi) = (f32::MAX, f32::MIN);
    for (v, k) in kind.iter().enumerate() {
        if *k == KIND_SKIRT { if let Some(p) = src.positions.get(v) { lo = lo.min(p[1]); hi = hi.max(p[1]); } }
    }
    let long = skirt && hi > lo && hi - lo > tune().long_span;
    if debug && skirt {
        log(1, &format!("OK cloth px detect: role={role} skirt span {:.3} long={long}", hi - lo));
    }
    (skirt || sleeves).then_some(Detect { kind, depth, skirt, sleeves, pleats, long, follow: chain_sleeves || grafted, sig: (n, src.indices.len()) })
}
/// A garment mesh whose rig was just built from it (push.rs): more triangles where it will be cloth (cloth_refine),
/// when PhysX cloth can run here (a host registered, or OK_CLOTH_PX_REFINE=1). The region is found on the built rig
/// (a grafted garment's chains are known only there), whose source keeps the mesh's vertex order. Returns the
/// vertices added: the caller builds the rig again from the refined mesh.
pub(crate) fn refine_mesh(mesh: &mut crate::unity::ExtractedMesh, role: &str, rig: &crate::session::AccessoryRuntime) -> usize {
    let t = tune();
    let forced = std::env::var("OK_CLOTH_PX_REFINE").ok();
    if t.edge <= 0. || forced.as_deref() == Some("0") || (host().is_none() && forced.as_deref() != Some("1")) { return 0; }
    let src = rig.source_mesh();
    if src.weights.len() != mesh.weights.len() || src.indices != mesh.indices { return 0; }
    let Some(d) = classify(src, role, rig.implanted_bones(), 1, false) else { return 0 };
    let selected: Vec<bool> = d.kind.iter().map(|k| *k != 0).collect();
    let (n, tris) = (mesh.weights.len(), mesh.indices.len() / 3);
    let added = crate::cloth_refine::refine(mesh, &selected, t.edge, (n * 6).clamp(4000, 40000));
    if added > 0 && std::env::var("OK_CLOTH_PX_DEBUG").is_ok_and(|v| v == "1") {
        log(1, &format!("OK cloth px refine: {role} {} vertices {n} -> {}, triangles {tris} -> {} (edges <= {:.0} mm)",
            mesh.name, mesh.weights.len(), mesh.indices.len() / 3, t.edge * 1000.));
    }
    added
}
// Per renderer bone: its depth (0 root .. 1 deepest) in one of the garment's own DynamicBone chains, by name.
/// Clothes whose bones were grafted onto the body (copy-weights clothes with their own chains: the kimono) have no
/// set of their own any more; their chains start at each grafted bone whose parent is not grafted.
fn chain_levels(src: &crate::unity::ExtractedMesh, implanted: &std::collections::HashSet<i64>, debug: bool) -> Vec<Option<f32>> {
    let mut out = vec![None; src.bone_names.len()];
    let Some(skel) = src.smr_skel.as_ref() else { return out };
    let mut roots = src.deferred_dbones.as_ref().map(|set| set.root_names(skel)).unwrap_or_default();
    if roots.is_empty() {
        roots = implanted.iter().filter_map(|id| skel.tfs.get(id))
            .filter(|t| !t.parent.is_some_and(|p| implanted.contains(&p)))
            .map(|t| (t.name.clone(), Vec::new())).collect();
    }
    let parent_of: HashMap<&str, &str> = skel.tfs.values()
        .filter_map(|t| t.parent.and_then(|p| skel.tfs.get(&p)).map(|p| (t.name.as_str(), p.name.as_str()))).collect();
    // Only sleeve chains (hung from an arm bone). Long panels and trains from the waist crumple and tear as cloth (the
    // kimono's back train, 2026-11-21): they stay DynamicBone.
    let on_arm = |root: &str| {
        let mut cur = root;
        for _ in 0..64 {
            let Some(p) = parent_of.get(cur) else { return false };
            // Body bones reach a grafted garment as "__ok_body_bridge/<bone>".
            if arm_side(p.rsplit('/').next().unwrap_or(p)).is_some() { return true; }
            cur = p;
        }
        false
    };
    if debug {
        for (root, _) in &roots {
            let mut path = vec![root.as_str()]; let mut cur = root.as_str();
            while let Some(p) = parent_of.get(cur) { path.push(p); cur = p; if path.len() > 10 { break; } }
            log(1, &format!("OK cloth px chain root on_arm={} {}", on_arm(root), path.join("<")));
        }
    }
    roots.retain(|(root, _)| on_arm(root));
    if roots.is_empty() { return out; }
    // Each bone: (its root, steps below it), the nearest chain root up its ancestry.
    let mut found: Vec<Option<(usize, u32)>> = vec![None; src.bone_names.len()];
    for (b, name) in src.bone_names.iter().enumerate() {
        let mut cur = name.as_str();
        for step in 0..64u32 {
            if let Some(r) = roots.iter().position(|(root, ex)| root == cur || ex.iter().any(|e| e == cur)) {
                if roots[r].1.iter().any(|e| e == cur) { break; }
                if step > 0 || roots[r].0 == *name { found[b] = Some((r, step)); }
                break;
            }
            let Some(p) = parent_of.get(cur) else { break };
            cur = p;
        }
    }
    let mut deepest = vec![0u32; roots.len()];
    for f in found.iter().flatten() { deepest[f.0] = deepest[f.0].max(f.1); }
    for (b, f) in found.iter().enumerate() {
        if let Some((r, s)) = f { out[b] = Some(*s as f32 / deepest[*r].max(1) as f32); }
    }
    out
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
    /// The capsules' radii on the GPU: none bigger than the free particles' room from it in the shape the cloth was
    /// made in. At full size the hip and thigh capsules sat outside Chika's pleated skirt and pushed it 4.4 cm up
    /// (OKPhysXCloth.Collide 0: -0.2 cm, 2026-11-21).
    gpu_rad: Vec<f32>,
    /// Skirt (or own-chain) particles: never shown above their pose by more than OK_CLOTH_PX_UP.
    skirt: Vec<bool>,
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
    /// Each particle's neighbours along the triangle edges (smoothing a follow cloth's offsets).
    links: Vec<Vec<u32>>,
    /// Diagnostics (OK_CLOTH_PX_DEBUG): the host's last answer and the pose jump it was given.
    last_ok: i32,
    last_jump: f32,
    /// Jitter (OK_CLOTH_PX_DEBUG): each free particle's offset from its pose over the last two frames, raw (the host's
    /// result carried) and shown; the second difference of that is what shakes on screen while the pose moves smoothly.
    jit_hist: Vec<[[f32; 3]; 4]>,
    /// [raw sum mm, shown sum mm, samples, frames, frames with a host result]
    jit: [f64; 5],
    /// Per particle and capsule: kept out by the capsule's whole grown size whatever its pose (a long skirt's shins).
    cap_forced: Vec<bool>,
    /// OK_CLOTH_PX_BLEND: the newest host result and what is shown, as offsets from the pose (carried with it), the time
    /// since that result and the usual time between results.
    goal: Vec<[f32; 3]>,
    shown_raw: Vec<[f32; 3]>,
    since_result: f32,
    interval: f32,
    /// Time passed since the last job was launched (the next one simulates it).
    pending: f32,
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
/// Per (session, part): how far each region (by kind) sits from the body, measured on the moving pose before the
/// cloth is made. Of two garments with the same region only the outer one becomes cloth; the inner one follows the
/// pose under it. Two cloths simulated apart crossed each other (Chika's blouse under her blazer, 2026-11-21).
/// Per region: (mean distance out from the body capsules, reach: how far down a skirt hangs / how far from the
/// shoulder a sleeve goes, 95th percentile).
type Layer = [Option<(f32, f32)>; 5];
/// With the garment mesh it was measured on (path id, name): the submeshes of one garment are not layers of each other.
static LAYERS: Mutex<Option<HashMap<(usize, usize), (Layer, (i64, String))>>> = Mutex::new(None);
/// Only the vertices this part draws: the submeshes of one garment share its whole vertex buffer, and measured over all of
/// it Raiden's kimono parts each found another covering them, none becoming cloth (2026-11-21).
fn layer_measure(d: &Detect, indices: &[u32], positions: &[[f32; 3]], skel: &crate::pose::Skeleton, caps: &[OkPxCapsule]) -> Layer {
    let mut drawn = vec![false; d.kind.len()];
    for &i in indices { if let Some(x) = drawn.get_mut(i as usize) { *x = true; } }
    let shoulder = [bone_pos(skel, "cf_j_arm00_L"), bone_pos(skel, "cf_j_arm00_R")];
    let mut sum = [(0f64, 0usize); 5];
    let mut reach: [Vec<f32>; 5] = Default::default();
    for (v, k) in d.kind.iter().enumerate() {
        let k = *k as usize;
        if k == 0 || k >= 5 || !drawn[v] { continue; }
        let r = caps.iter().map(|c| seg_closest(positions[v], c.a, c.b).1 - c.radius).fold(f32::MAX, f32::min);
        if r.is_finite() && r < 1. { sum[k].0 += r as f64; sum[k].1 += 1; }
        let sleeve = if k == KIND_SLEEVE_L as usize { shoulder[0] } else if k == KIND_SLEEVE_R as usize { shoulder[1] } else { None };
        // Down is -y: a skirt's reach is how low it goes (stored as -y so larger = farther, like a sleeve's).
        reach[k].push(match sleeve { Some(s) => len(sub(positions[v], s)), None => -positions[v][1] });
    }
    let mut out = [None; 5];
    for k in 1..5 {
        if sum[k].1 < 30 { continue; }
        reach[k].sort_by(f32::total_cmp);
        let r95 = reach[k][(reach[k].len() - 1) * 95 / 100];
        out[k] = Some(((sum[k].0 / sum[k].1 as f64) as f32, r95));
    }
    out
}
/// The regions of this part that another part of the session covers (same kind, farther out by more than 3 mm).
fn covered(session: usize, index: usize, own: &Layer, mesh: &(i64, String)) -> [bool; 5] {
    let mut out = [false; 5];
    let all = LAYERS.lock().unwrap();
    let Some(map) = all.as_ref() else { return out };
    for ((s, i), (other, other_mesh)) in map {
        if *s != session || *i == index || other_mesh == mesh { continue; }
        for k in 1..5 {
            // Only the same kind: a chain is a sleeve on its arm now, and its reach (from the shoulder) is no skirt's (how
            // low); merged, Raiden's kimono panel "covered" her own sleeves (2026-11-21).
            let same = |a: usize, b: usize| a == b;
            let Some(mine) = own[k] else { continue };
            // Covered: the other is farther out and reaches as far (within 2 cm); a blazer ending at the hips does
            // not cover the skirt below it.
            if (1..5).any(|j| same(k, j) && other[j].is_some_and(|o| o.0 > mine.0 + 0.003 && o.1 >= mine.1 - 0.02)) { out[k] = true; }
        }
    }
    out
}

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
    if let Some(m) = LAYERS.lock().unwrap().as_mut() { m.retain(|(s, _), _| *s != session); }
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
    *LAYERS.lock().unwrap() = None;
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
    // A garment grafted onto the body (coordinated) shares its chains with the clothes set: they keep running and the
    // cloth overrides only its own vertices, or its other panels would go rigid.
    let grafted = part.runtime_accessory.as_ref().is_some_and(|r| !r.implanted_bones().is_empty());
    !e.failed && !grafted && e.detect.as_ref().is_some_and(|d| d.skirt && !d.long)
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
            KIND_SKIRT | KIND_CHAIN => depth_of[p] < t.pin_t,
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
            KIND_SKIRT => (t.skirt_reach * near * smooth(t.pin_t, t.pin_t + 0.25, depth_of[p])).min(if d.long { t.long_max } else { t.skirt_max }),
            KIND_CHAIN => (t.skirt_reach * near * smooth(t.pin_t, t.pin_t + 0.25, depth_of[p])).min(t.chain_max),
            _ => (t.sleeve_reach * near).min(0.012 + 0.6 * (r[p] - 0.05).max(0.)).min(t.sleeve_max),
        };
        if max_dist[p] > 1e-4 { free += 1; } else { pinned[p] = true; }
    }
    if free < 16 { return None; }
    Some(Sim { key: NEXT_KEY.fetch_add(1, Ordering::Relaxed), created: false, particle_of, rep, pinned, max_dist, tris,
        offsets: vec![[0.; 3]; np], launch_target: pos.clone(), last_target: pos, free, last_step: None, nbr, cap_fit: Vec::new(), cap_n: 0, gpu_rad: Vec::new(),
        skirt: kind_of.iter().map(|k| *k == KIND_SKIRT || *k == KIND_CHAIN).collect(), anchor, anchor_len,
        sleeve: kind_of.iter().map(|k| *k == KIND_SLEEVE_L || *k == KIND_SLEEVE_R).collect(), straight, built: std::time::Instant::now(), made_still: false,
        links: adj.iter().map(|l| { let mut v: Vec<u32> = l.iter().map(|x| x.0).collect(); v.sort_unstable(); v.dedup(); v }).collect(), last_ok: -1, last_jump: 0., jit_hist: Vec::new(), jit: [0.; 5], cap_forced: Vec::new(), goal: Vec::new(), shown_raw: Vec::new(), since_result: 0., interval: 0., pending: 0. })
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
fn debug_on() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var("OK_CLOTH_PX_DEBUG").is_ok_and(|v| v == "1"))
}
fn debug_due(key: u64) -> bool {
    if !debug_on() { return false; }
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
        log(1, &format!("OK cloth px: part {index} ({}) started moving, made again on the moving pose", part.role));
        release_entry(&mut e);
    }
    if e.sim.is_none() {
        let m = layer_measure(&d, &runtime.source_mesh().indices, positions, skel, &capsules(skel));
        LAYERS.lock().unwrap().get_or_insert_with(HashMap::new).insert((session, index), (m, (runtime.source_mesh().path_id, runtime.source_mesh().name.clone())));
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
            log(1, &format!("OK cloth px: part {index} ({}) changed shape ({:.0}% from its rest), made again", part.role, drift / n as f32 * 100.));
            release_entry(&mut e);
        }
    }
    if e.sim.is_none() {
        let (own, mesh) = LAYERS.lock().unwrap().as_ref().and_then(|m| m.get(&(session, index)).cloned()).unwrap_or(([None; 5], (0, String::new())));
        let under = covered(session, index, &own, &mesh);
        if under.iter().any(|u| *u) {
            let mut kind = d.kind.clone();
            for k in kind.iter_mut() { if (*k as usize) < 5 && under[*k as usize] { *k = 0; } }
            let skirt = kind.iter().filter(|k| **k == KIND_SKIRT || **k == KIND_CHAIN).count() >= 30;
            let sleeves = kind.iter().any(|k| *k == KIND_SLEEVE_L || *k == KIND_SLEEVE_R);
            log(1, &format!("OK cloth px: part {index} ({}) is under another garment's cloth (kinds {:?}), those follow the pose", part.role,
                (1..5).filter(|k| under[*k]).collect::<Vec<_>>()));
            let nd = Detect { kind, depth: d.depth.clone(), skirt, sleeves, pleats: d.pleats && skirt, long: d.long && skirt, follow: d.follow, sig: d.sig };
            if !skirt && !sleeves { e.failed = true; e.detect = Some(Arc::new(nd)); return; }
            e.detect = Some(Arc::new(nd));
        }
    }
    let d = e.detect.clone().unwrap();
    if e.sim.is_none() {
        match build(&d, &runtime.source_mesh().indices, positions, skel) {
            Some(mut sim) => { sim.made_still = !moving; e.sim = Some(sim) }
            None => { e.failed = true; log(1, &format!("OK cloth px: part {index} ({}) has no usable cloth region, DynamicBone kept", part.role)); return; }
        }
    }
    let sim = e.sim.as_mut().unwrap();
    let np = sim.rep.len();
    let targets: Vec<[f32; 3]> = sim.rep.iter().map(|&v| positions[v as usize]).collect();
    if !sim.created {
        let inv: Vec<f32> = sim.pinned.iter().map(|p| if *p { 0. } else { 1. }).collect();
        let ok = unsafe { create(sim.key, np as u32, targets.as_ptr().cast(), inv.as_ptr(), sim.tris.len() as u32, sim.tris.as_ptr().cast(), d.pleats as u32 | 2) };
        if ok != 1 {
            e.failed = true; e.sim = None;
            log(2, &format!("OK cloth px: host could not create the cloth of part {index} ({}), DynamicBone kept", part.role));
            return;
        }
        sim.created = true;
        sim.last_target = targets.clone();
        let mut out = vec![[0f32; 3]; np];
        unsafe { step(sim.key, np as u32, targets.as_ptr().cast(), std::ptr::null(), std::ptr::null(), 0, -1., out.as_mut_ptr().cast()); }
        log(1, &format!("OK cloth px: part {index} ({}) skirt={} sleeves={} particles={np} free={} triangles={}",
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
        // A long skirt's hanging part keeps out of the lower legs by their whole size, however close it hung when the
        // cloth was made: made mid-stride, the shin was already in Raiden's kimono panel and kept going through it
        // (outfit 5, 2026-11-21). OK_CLOTH_PX_SHIN=0: as the rest of the body.
        sim.cap_forced = vec![false; np * caps.len()];
        if d.long && t.shin {
            let shins: Vec<usize> = caps.iter().enumerate().filter(|(_, c)| ["L", "R"].iter().any(|s| {
                let near = |a: [f32; 3], bone: &str| bone_pos(skel, &format!("{bone}_{s}")).is_some_and(|b| len(sub(a, b)) < 1e-4);
                near(c.a, "cf_j_leg01") && near(c.b, "cf_j_leg03")
            })).map(|(i, _)| i).collect();
            for p in 0..np {
                if sim.pinned[p] || !sim.skirt[p] { continue; }
                for &ci in &shins { sim.cap_fit[p * sim.cap_n + ci] = caps[ci].radius * t.cap_scale; sim.cap_forced[p * sim.cap_n + ci] = true; }
            }
        }
        sim.gpu_rad = caps.iter().enumerate().map(|(ci, c)| (0..np).filter(|&p| !sim.pinned[p])
            .map(|p| sim.cap_fit[p * sim.cap_n + ci]).fold(c.radius, f32::min)).collect();
    }
    // A skirt gets none on the GPU: the thighs swinging into it there kicked Chika's pleated skirt 3-4 cm up for good
    // (OKPhysXCloth.Collide 0: -0.2 cm; shrunk capsules or no friction did not help, 2026-11-21). Rust still pushes
    // every particle out of the body after each step.
    // That was judged while the host ignored every upload after the first frames (the cloth never followed the body,
    // see OKPhysXCloth Upload); with the cloth simulated for real the legs must push the skirt (a shin went through
    // Raiden's kimono panel, 2026-11-21). OK_CLOTH_PX_SKIRT_CAPS=0: none for skirts, as before.
    static SKIRT_CAPS: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    let skirt_caps = *SKIRT_CAPS.get_or_init(|| std::env::var("OK_CLOTH_PX_SKIRT_CAPS").map_or(true, |v| v != "0"));
    let gpu_caps: Vec<OkPxCapsule> = if d.skirt && !skirt_caps { Vec::new() } else {
        caps.iter().zip(&sim.gpu_rad).map(|(c, r)| OkPxCapsule { radius: *r, ..*c }).collect() };
    let now = std::time::Instant::now();
    let dt = if dt > 0. { dt } else {
        let passed = sim.last_step.map_or(0., |t| now.duration_since(t).as_secs_f32());
        if passed >= 0.004 { passed.min(0.1) } else { 0. }
    };
    if dt > 0. || sim.last_step.is_none() { sim.last_step = Some(now); }
    // The newest result and what is shown, as moves off the pose: turned from the last pose's local frames to this one's.
    let now_frames = frames(&targets, &sim.tris, &sim.nbr);
    let last_frames = frames(&sim.last_target, &sim.tris, &sim.nbr);
    let reset = jump > 0.35;
    if sim.goal.len() != np || reset {
        sim.goal = vec![[0f32; 3]; np]; sim.shown_raw = vec![[0f32; 3]; np]; sim.interval = 0.; sim.since_result = 0.;
    }
    for p in 0..np {
        sim.goal[p] = carry(sim.goal[p], &last_frames[p], &now_frames[p]);
        sim.shown_raw[p] = carry(sim.shown_raw[p], &last_frames[p], &now_frames[p]);
    }
    // Out of the body. Live (OK_CLOTH_PX_LIVE_PUSH): never nearer a capsule's axis than the pose is this frame, up to the
    // capsule grown plus OK_CLOTH_PX_KEEP_OUT. The room a particle had when the cloth was made was wrong once the walk
    // moved it: too little let Raiden's gauze sleeves fall into her hips (outfit 2), too much pushed cloth out past its
    // pose every frame (outfits 3, 5, 2026-11-21).
    let t = tune();
    let live: Vec<f32> = if t.live_push {
        let mut v = vec![0f32; np * caps.len()];
        for p in 0..np {
            if sim.pinned[p] { continue; }
            for (ci, c) in caps.iter().enumerate() {
                let full = c.radius * t.cap_scale;
                let r = (seg_closest(targets[p], c.a, c.b).1 - t.cap_margin).min(full + t.keep_out);
                v[p * caps.len() + ci] = if sim.cap_forced.get(p * sim.cap_n + ci).copied().unwrap_or(false) { r.max(full) } else { r };
            }
        }
        v
    } else { (0..np * caps.len()).map(|i| sim.cap_fit.get(i).copied().unwrap_or(0.)).collect() };
    // Collect the finished GPU job first, work out the corrections on that very result (the GPU holds it), then launch
    // the next job with them. Corrections sent with the launch that collected a result were for the result before: in
    // async mode the host steered every vertex back to the previous result and the skirt shook between the two
    // (Raiden's maid skirt, 19 mm a frame at 60 fps, 2026-11-21).
    let t0 = std::time::Instant::now();
    let mut out = vec![[0f32; 3]; np];
    let mut fresh = false;
    if dt > 0. {
        sim.pending += dt;
        let mut code = if reset { 0 } else { unsafe { step(sim.key, np as u32, targets.as_ptr().cast(), std::ptr::null(), std::ptr::null(), 0, 0., out.as_mut_ptr().cast()) } };
        if code == 2 {
            let launch_frames = frames(&sim.launch_target, &sim.tris, &sim.nbr);
            for p in 0..np { sim.goal[p] = carry(sub(out[p], sim.launch_target[p]), &launch_frames[p], &now_frames[p]); }
            fresh = true;
        }
        if code != 3 {
            // What the clamps and the push do to the result the GPU holds, and the pull back toward the pose over the
            // time this job covers (OK_CLOTH_PX_PULL per second: a pleat the walk flipped stayed flipped, 2026-11-20);
            // turned back onto the pose that result was made on.
            let mut fixed: Vec<[f32; 3]> = (0..np).map(|p| add(targets[p], sim.goal[p])).collect();
            constrain(sim, &d, &targets, normals, &caps, &live, &mut fixed);
            let back = 1. - (-t.pull * sim.pending).exp();
            let launch_frames = frames(&sim.launch_target, &sim.tris, &sim.nbr);
            let delta: Vec<[f32; 3]> = (0..np).map(|p| {
                if sim.pinned[p] { return [0.; 3]; }
                let c = sub(sub(fixed[p], targets[p]), sim.goal[p]);
                let c = sub(c, scale(sub(fixed[p], targets[p]), back));
                carry(c, &now_frames[p], &launch_frames[p])
            }).collect();
            let ok = unsafe { step(sim.key, np as u32, targets.as_ptr().cast(), delta.as_ptr().cast(), gpu_caps.as_ptr(), gpu_caps.len() as u32,
                if reset { -1. } else { sim.pending }, out.as_mut_ptr().cast()) };
            // 1: done at once (OKPhysXCloth.Async 0, or a reset onto the targets).
            if ok == 1 { for p in 0..np { sim.goal[p] = sub(out[p], targets[p]); } fresh = true; code = 1; }
            sim.launch_target = targets.clone();
            sim.pending = 0.;
        }
        sim.last_ok = code; sim.last_jump = jump;
        let mut st = STATS.lock().unwrap(); st.steps += 1; st.step_us += t0.elapsed().as_micros() as u64;
    }
    // Between two results the cloth shown eases toward the newest one (OK_CLOTH_PX_BLEND): the GPU job takes 20 ms with
    // the renderer on the same GPU, a result came every 6 frames at 200 fps and the frames between held the last one.
    sim.since_result += dt;
    if fresh {
        sim.interval = if sim.interval > 0. { sim.interval * 0.7 + sim.since_result * 0.3 } else { sim.since_result };
        sim.since_result = 0.;
    }
    let a = if !t.blend || reset || sim.interval <= 1e-4 { 1. } else { (dt / sim.interval).clamp(0., 1.) };
    for p in 0..np { sim.shown_raw[p] = add(sim.shown_raw[p], scale(sub(sim.goal[p], sim.shown_raw[p]), a)); }
    let mut sim_pos: Vec<[f32; 3]> = (0..np).map(|p| add(targets[p], sim.shown_raw[p])).collect();
    sim.last_target = targets.clone();
    if debug_due(sim.key) {
        let j = sim.jit;
        let s = j[2].max(1.);
        log(1, &format!("OK cloth px jitter: cloth {} raw {:.2} mm, shown {:.2} mm a frame (second difference of the pose (raw) and of the cloth shown, mean of free particles over {} frames, {} with a host result)",
            sim.key, j[0] / s, j[1] / s, j[3], j[4]));
        sim.jit = [0.; 5];
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
        log(1, &format!("OK cloth px debug: cloth {} free {} raw mean dy {:.1} mm, mean out {:.1} mm, {far} flung (pin centre y {:.3}, host {} jump {:.0} mm)", sim.key, n, dy / n * 1000., dr / n * 1000., c[1], sim.last_ok, sim.last_jump * 1000.));
    }
    let (clamped, pushed) = constrain(sim, &d, &targets, normals, &caps, &live, &mut sim_pos);
    let most = (0..np).map(|p| len(sub(sim_pos[p], targets[p]))).fold(0f32, f32::max);
    for p in 0..np { sim.offsets[p] = sub(sim_pos[p], targets[p]); }
    if debug_on() && dt > 0. {
        if sim.jit_hist.len() != np { sim.jit_hist = vec![[[f32::NAN; 3]; 4]; np]; }
        let (mut a, mut b, mut n) = (0f64, 0f64, 0usize);
        for p in 0..np {
            if sim.pinned[p] { continue; }
            // Where the pose and the cloth shown are, in her space: their second differences (the pose's own shake is
            // the floor; an offset measure counted a jittery pose as the cloth's).
            let (tg, fin) = (targets[p], sim_pos[p]);
            let h = &mut sim.jit_hist[p];
            if h[1][0].is_finite() && h[3][0].is_finite() {
                a += len(add(sub(tg, scale(h[0], 2.)), h[1])) as f64;
                b += len(add(sub(fin, scale(h[2], 2.)), h[3])) as f64;
                n += 1;
            }
            *h = [tg, h[0], fin, h[2]];
        }
        if n > 0 { sim.jit[0] += a / n as f64 * 1000.; sim.jit[1] += b / n as f64 * 1000.; sim.jit[2] += 1.; }
        sim.jit[3] += 1.;
        if fresh { sim.jit[4] += 1.; }
    }
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

/// The cloth's positions kept to the garment: max distance from its pin and from the pose, sleeves not sunk behind their
/// surface, skirts not risen, a follow cloth's moves smoothed with its neighbours', then out of the body (`live`: each
/// particle's room from each capsule axis). Returns (clamped, pushed).
fn constrain(sim: &Sim, d: &Detect, targets: &[[f32; 3]], normals: &[[f32; 3]], caps: &[OkPxCapsule], live: &[f32], pos: &mut [[f32; 3]]) -> (u64, u64) {
    let np = pos.len();
    let (mut clamped, mut pushed) = (0u64, 0u64);
    let t = tune();
    for p in 0..np {
        if sim.pinned[p] { pos[p] = targets[p]; continue; }
        if !pos[p].iter().all(|x| x.is_finite()) { pos[p] = targets[p]; continue; }
        if let Some(&a) = sim.anchor.get(p).filter(|a| **a != u32::MAX) {
            let pin = targets[a as usize];
            let v = sub(pos[p], pin);
            let dl = len(v);
            // Never shorter than the garment as posed now: a clip's own skirt keys stretch it past the lengths of the
            // pose it was built in (the reader's bind pose), and that limit held the hem 4 cm up (2026-11-20).
            let limit = sim.anchor_len[p].max(len(sub(targets[p], pin))) * t.stretch;
            if dl > limit && dl > 1e-9 { pos[p] = add(pin, scale(v, limit / dl)); }
        }
        let mut off = sub(pos[p], targets[p]);
        if sim.sleeve[p] {
            if let Some(n) = normals.get(sim.rep[p] as usize).copied().filter(|n| len(*n) > 0.5) {
                let k = dot(off, n);
                if k < -0.002 { off = sub(off, scale(n, k + 0.002)); pos[p] = add(targets[p], off); }
            }
        }
        let l = len(off);
        if l > sim.max_dist[p] { pos[p] = add(targets[p], scale(off, sim.max_dist[p] / l)); clamped += 1; }
        if sim.skirt[p] && pos[p][1] > targets[p][1] + t.up_max { pos[p][1] = targets[p][1] + t.up_max; clamped += 1; }
    }
    // A follow cloth's moves averaged with its neighbours' (pinned ones moving by nothing): each particle clamped on its
    // own around a DynamicBone pose that swings, the drape's edge jagged and tore (Raiden's kimono, 2026-11-21).
    if d.follow && t.smooth > 0 {
        let mut off: Vec<[f32; 3]> = (0..np).map(|p| sub(pos[p], targets[p])).collect();
        for _ in 0..t.smooth {
            let next: Vec<[f32; 3]> = (0..np).map(|p| {
                if sim.pinned[p] || sim.links[p].is_empty() { return off[p]; }
                let sum = sim.links[p].iter().fold([0f32; 3], |a, &q| add(a, off[q as usize]));
                add(scale(off[p], 0.5), scale(sum, 0.5 / sim.links[p].len() as f32))
            }).collect();
            off = next;
        }
        for p in 0..np { if !sim.pinned[p] { pos[p] = add(targets[p], off[p]); } }
    }
    // Two passes for capsules that overlap (hip and thigh).
    for p in 0..np {
        if sim.pinned[p] { continue; }
        for (ci, c) in caps.iter().enumerate().chain(caps.iter().enumerate()) {
            let r = live.get(p * caps.len() + ci).copied().unwrap_or(0.);
            if r <= 0. { continue; }
            let ab = sub(c.b, c.a);
            let l2 = dot(ab, ab);
            let s = if l2 > 1e-12 { (dot(sub(pos[p], c.a), ab) / l2).clamp(0., 1.) } else { 0. };
            let axis = add(c.a, scale(ab, s));
            let v = sub(pos[p], axis);
            let dl = len(v);
            if dl < r && dl > 1e-6 { pos[p] = add(axis, scale(v, r / dl)); pushed += 1; }
        }
    }
    (clamped, pushed)
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
        // OK_CLOTH_OUTFITS=0,1,2 (default 0); OK_CLOTH_ALL=1 also lists the parts that are not clothes (accessories).
        let outfits: Vec<i32> = std::env::var("OK_CLOTH_OUTFITS").ok().map(|v| v.split(',').filter_map(|x| x.trim().parse().ok()).collect()).unwrap_or(vec![0]);
        let all = std::env::var("OK_CLOTH_ALL").is_ok_and(|v| v == "1");
        for card in cards.split(';').filter(|c| !c.is_empty()) { for &outfit in &outfits {
            let game = std::ffi::CString::new("").unwrap();
            let c = std::ffi::CString::new(card).unwrap();
            let mut out = std::ptr::null_mut();
            let mut err = [0i8; 512];
            let r = unsafe { crate::ffi::session_open(game.as_ptr(), c.as_ptr(), outfit, &mut out, err.as_mut_ptr(), 512) };
            if r != 0 { eprintln!("CARD {card}: open failed {}", unsafe { std::ffi::CStr::from_ptr(err.as_ptr()) }.to_string_lossy()); continue; }
            eprintln!("CARD {card} outfit {outfit}");
            let s = unsafe { &mut *out };
            for (i, p) in s.parts.iter().enumerate() {
                if !p.role.starts_with("clothes") && !all { continue; }
                let Some(rt) = p.runtime_accessory.as_ref() else { if all { eprintln!("  part {i} {} (no runtime)", p.role); } continue };
                let src = rt.source_mesh();
                let d = detect(p);
                let (sk, sl) = d.as_ref().map_or((0, 0), |d| (d.kind.iter().filter(|k| **k == KIND_SKIRT || **k == KIND_CHAIN).count(), d.kind.iter().filter(|k| **k == KIND_SLEEVE_L || **k == KIND_SLEEVE_R).count()));
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
                let mut order: Vec<usize> = (0..sums.len()).collect();
                order.sort_by(|a, b| sums[*b].total_cmp(&sums[*a]));
                let top = order.first().map(|b| src.bone_names[*b].clone()).unwrap_or_default();
                let tops: Vec<String> = order.iter().take(6).map(|&b| format!("{}={:.0}", src.bone_names[b], sums[b])).collect();
                // The cloth region's triangle edges (how coarse it is).
                if let Some(d) = d.as_ref() {
                    let pos = if src.rest_positions.len() == src.weights.len() { &src.rest_positions } else { &src.positions };
                    let mut e: Vec<f32> = src.indices.chunks_exact(3).filter(|t| t.iter().any(|&v| d.kind[v as usize] != 0))
                        .flat_map(|t| (0..3).map(move |k| len(sub(pos[t[k] as usize], pos[t[(k + 1) % 3] as usize])))).collect();
                    e.sort_by(f32::total_cmp);
                    if !e.is_empty() { eprintln!("    region edges: n={} median {:.1} mm p90 {:.1} mm max {:.1} mm follow={} long={}", e.len(), e[e.len() / 2] * 1000., e[e.len() * 9 / 10] * 1000., e[e.len() - 1] * 1000., d.follow, d.long); }
                }
                eprintln!("  part {i} {} verts={} tris={} skirt={sk} sleeve={sl} dbones={} implanted={} top: {} path={}",
                    p.role, src.weights.len(), src.indices.len() / 3, src.deferred_dbones.is_some(), rt.implanted_bones().len(), tops.join(" "), anc(&top));
            }
        } }
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
