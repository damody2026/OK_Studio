//! Per-frame mod hooks (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.8, work item 11, Docs/OK_MOD_S11_FRAME.md): a typed
//! call once per character per frame, never JSON.
//!
//! The game hands over the mod host's frame function (`okm_frame`, Tools/ok-mod/host) with `ok_set_mod_frame`. With
//! none set, a frame costs one atomic load here and one in each dynamic-bone force site: playback without mods is
//! what it was.
//!
//! - **Post-pose bones**: after the bone modifiers (ABMX), before Studio IK (`Session::finish_animator_transforms`),
//!   and once per pair frame after the pair's pose. The mod sees the body skeleton's local transforms (Unity space)
//!   and its world matrices, and may write the locals; written locals are published to worlds once.
//! - **Physics forces**: the frame may answer forces (`OkModForce`: a sphere and an acceleration); the dynamic bones of
//!   that character whose chain root is inside a sphere get it added to their `m_Force` in this frame's solve. They
//!   are replaced by the next frame's answer (a mod keeps a push going by answering it again).
//!
//! Runs on worker threads, several characters at once: the host's function must be thread-safe.

use std::collections::HashMap;
use std::ffi::{c_char, CString};
use std::sync::atomic::{AtomicBool, AtomicPtr, Ordering};
use std::sync::{Mutex, RwLock};

use crate::pose::Skeleton;

/// One bone's local transform (Unity space, the parent's frame).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct OkModBone {
    pub pos: [f32; 3],
    pub rot: [f32; 4],
    pub scale: [f32; 3],
}

/// A push for this frame's physics: dynamic-bone chains whose root is within `radius` of `center` (world, Unity space)
/// get `force` added to their `m_Force` (same units: a displacement per update step, like DynamicBone's gravity).
#[repr(C)]
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct OkModForce {
    pub center: [f32; 3],
    pub radius: f32,
    pub force: [f32; 3],
    pub reserved: f32,
}

/// What a frame call sees. `size` is this struct's size (fields are only ever appended).
#[repr(C)]
pub struct OkModFrame {
    pub size: u32,
    /// 0 = a character on its own (card reader, Studio), 1 = a pair frame (1-on-1).
    pub kind: u32,
    /// Stable for the character's lifetime (its session), to key a mod's per-character state.
    pub character: u64,
    /// 0 male, 1 female.
    pub sex: i32,
    /// Seconds since the last frame, and the clip time.
    pub dt: f32,
    pub time: f32,
    pub bone_count: u32,
    /// `bone_count` NUL-terminated names, valid for the call.
    pub names: *const *const c_char,
    /// `bone_count` locals the mod may change in place.
    pub bones: *mut OkModBone,
    /// `bone_count` world matrices (row-major 4x4, Unity space) before the mod's changes.
    pub worlds: *const [f32; 16],
    /// Room for `force_cap` forces; the mod sets `force_count`.
    pub forces: *mut OkModForce,
    pub force_cap: u32,
    pub force_count: u32,
}

/// The host's frame function. Returns bit 0 set when it changed `bones`; called with null, the number of mods taking
/// frames (none: no frame is built).
pub type OkModFrameFn = unsafe extern "C" fn(frame: *mut OkModFrame) -> u32;

static FRAME: AtomicPtr<()> = AtomicPtr::new(std::ptr::null_mut());
/// Some character has forces this frame (the dynamic-bone sites check only this when none has).
static ANY_FORCE: AtomicBool = AtomicBool::new(false);
static FORCES: RwLock<Option<HashMap<u64, Vec<OkModForce>>>> = RwLock::new(None);
/// Bone names per skeleton layout, as C strings (built once per layout, not per frame).
static NAMES: Mutex<Option<HashMap<u64, std::sync::Arc<Names>>>> = Mutex::new(None);

pub const MAX_FORCES: usize = 32;

struct Names {
    _owned: Vec<CString>,
    ptrs: Vec<*const c_char>,
}
// SAFETY: the pointers point into `_owned`, which is never mutated after construction.
unsafe impl Send for Names {}
unsafe impl Sync for Names {}

/// Sets (or clears with null) the mod host's frame function.
///
/// # Safety
/// The function must stay callable from any thread until cleared.
#[no_mangle]
pub unsafe extern "C" fn ok_set_mod_frame(frame: Option<OkModFrameFn>) {
    FRAME.store(frame.map_or(std::ptr::null_mut(), |f| f as *mut ()), Ordering::Release);
    if frame.is_none() {
        if let Ok(mut g) = FORCES.write() {
            *g = None;
        }
        ANY_FORCE.store(false, Ordering::Release);
    }
}

#[inline]
fn frame_fn() -> Option<OkModFrameFn> {
    let p = FRAME.load(Ordering::Acquire);
    // SAFETY: stored from an OkModFrameFn by ok_set_mod_frame.
    (!p.is_null()).then(|| unsafe { std::mem::transmute::<*mut (), OkModFrameFn>(p) })
}

/// Whether a mod host takes frames (one atomic load).
#[inline]
pub fn active() -> bool {
    !FRAME.load(Ordering::Relaxed).is_null()
}

fn names_for(sk: &Skeleton, order: &[i64]) -> std::sync::Arc<Names> {
    // The layout's key: its bone ids in order.
    let mut h = std::collections::hash_map::DefaultHasher::new();
    std::hash::Hash::hash(order, &mut h);
    let key = std::hash::Hasher::finish(&h);
    let mut g = NAMES.lock().unwrap_or_else(|e| e.into_inner());
    let map = g.get_or_insert_with(HashMap::new);
    if let Some(n) = map.get(&key) {
        return n.clone();
    }
    let owned: Vec<CString> = order
        .iter()
        .map(|id| CString::new(sk.tfs.get(id).map(|t| t.name.as_str()).unwrap_or("")).unwrap_or_default())
        .collect();
    let ptrs = owned.iter().map(|c| c.as_ptr()).collect();
    let names = std::sync::Arc::new(Names { _owned: owned, ptrs });
    if map.len() > 256 {
        map.clear();
    }
    map.insert(key, names.clone());
    names
}

/// One character's frame: hands its body skeleton to the host's frame function; publishes changed locals and keeps
/// the forces it answered for this frame's dynamics. Does nothing without a host.
pub fn post_pose(sk: &mut Skeleton, character: u64, sex: i32, kind: u32, dt: f32, time: f32) {
    let Some(frame) = frame_fn() else { return };
    // SAFETY: null asks whether anyone takes frames (OkModFrameFn).
    if unsafe { frame(std::ptr::null_mut()) } == 0 {
        if ANY_FORCE.load(Ordering::Relaxed) {
            set_forces(character, &[]);
        }
        return;
    }
    let mut order: Vec<i64> = sk.tfs.keys().copied().collect();
    order.sort_unstable();
    let names = names_for(sk, &order);
    let mut bones: Vec<OkModBone> = order
        .iter()
        .map(|id| sk.tfs.get(id).map(|t| OkModBone { pos: t.pos, rot: t.rot, scale: t.scale }).unwrap_or_default())
        .collect();
    let mut cache = HashMap::new();
    let worlds: Vec<[f32; 16]> = order
        .iter()
        .map(|id| {
            let m = crate::pose::world_of(*id, &sk.tfs, &mut cache);
            let mut out = [0.0f32; 16];
            for r in 0..4 {
                for c in 0..4 {
                    out[r * 4 + c] = m[r][c];
                }
            }
            out
        })
        .collect();
    let mut forces = [OkModForce::default(); MAX_FORCES];
    let mut view = OkModFrame {
        size: std::mem::size_of::<OkModFrame>() as u32,
        kind,
        character,
        sex,
        dt,
        time,
        bone_count: order.len() as u32,
        names: names.ptrs.as_ptr(),
        bones: bones.as_mut_ptr(),
        worlds: worlds.as_ptr(),
        forces: forces.as_mut_ptr(),
        force_cap: MAX_FORCES as u32,
        force_count: 0,
    };
    // SAFETY: every pointer is valid for the call; the host's function is thread-safe (ok_set_mod_frame).
    let changed = unsafe { frame(&mut view) } & 1 != 0;
    let count = (view.force_count as usize).min(MAX_FORCES);
    set_forces(character, &forces[..count]);
    if changed {
        for (id, b) in order.iter().zip(&bones) {
            if let Some(t) = sk.tfs.get_mut(id) {
                if b.pos.iter().chain(&b.rot).chain(&b.scale).all(|v| v.is_finite()) {
                    t.pos = b.pos;
                    t.rot = b.rot;
                    t.scale = b.scale;
                }
            }
        }
        sk.rebuild_worlds();
    }
}

fn set_forces(character: u64, forces: &[OkModForce]) {
    let Ok(mut g) = FORCES.write() else { return };
    let map = g.get_or_insert_with(HashMap::new);
    if forces.is_empty() {
        map.remove(&character);
    } else {
        map.insert(character, forces.iter().filter(|f| f.radius > 0.0 && f.force.iter().all(|v| v.is_finite())).copied().collect());
    }
    ANY_FORCE.store(!map.is_empty(), Ordering::Release);
}

/// The mod forces on a dynamic-bone chain of the character being solved (`crate::px::current_group`) whose root is at
/// `root` (world, Unity space). Zero (one atomic load) when no mod pushes anything.
#[inline]
pub fn force_at(root: [f32; 3]) -> [f32; 3] {
    if !ANY_FORCE.load(Ordering::Relaxed) {
        return [0.0; 3];
    }
    force_at_slow(crate::px::current_group(), root)
}

#[cold]
fn force_at_slow(character: u64, root: [f32; 3]) -> [f32; 3] {
    let Ok(g) = FORCES.read() else { return [0.0; 3] };
    let Some(list) = g.as_ref().and_then(|m| m.get(&character)) else { return [0.0; 3] };
    let mut sum = [0.0f32; 3];
    for f in list {
        let d = [root[0] - f.center[0], root[1] - f.center[1], root[2] - f.center[2]];
        if d[0] * d[0] + d[1] * d[1] + d[2] * d[2] <= f.radius * f.radius {
            for i in 0..3 {
                sum[i] += f.force[i];
            }
        }
    }
    sum
}

/// `a + mod forces at root`, for the dynamic-bone sites (`m_Force` plus this frame's pushes).
#[inline]
pub fn with_force(force: [f32; 3], root: [f32; 3]) -> [f32; 3] {
    let extra = force_at(root);
    [force[0] + extra[0], force[1] + extra[1], force[2] + extra[2]]
}

#[cfg(test)]
mod tests {
    use super::*;

    unsafe extern "C" fn push_and_bend(frame: *mut OkModFrame) -> u32 {
        if frame.is_null() {
            return 1;
        }
        let f = &mut *frame;
        assert_eq!(f.size as usize, std::mem::size_of::<OkModFrame>());
        let bones = std::slice::from_raw_parts_mut(f.bones, f.bone_count as usize);
        let names = std::slice::from_raw_parts(f.names, f.bone_count as usize);
        for (b, n) in bones.iter_mut().zip(names) {
            if std::ffi::CStr::from_ptr(*n).to_str() == Ok("hair") {
                b.pos[1] += 1.0;
            }
        }
        *f.forces = OkModForce { center: [0.0; 3], radius: 2.0, force: [0.5, 0.0, 0.0], reserved: 0.0 };
        f.force_count = 1;
        1
    }

    #[test]
    fn frame_bends_and_pushes() {
        // One test: the frame function is global.
        unsafe { ok_set_mod_frame(None) };
        assert!(!active());
        assert_eq!(force_at([0.0; 3]), [0.0; 3]);
        let tf = |name: &str, parent| crate::pose::Tf { name: name.into(), parent, sibling_index: None, pos: [0.0; 3], rot: [0.0, 0.0, 0.0, 1.0], scale: [1.0; 3] };
        let mut sk = Skeleton { names: Vec::new(), worlds: Vec::new(), rest: Vec::new(), smr_count: 0,
            tfs: [(1, tf("root", None)), (2, tf("hair", Some(1)))].into(), bone_ids: Vec::new(), source_mesh: 0 };
        post_pose(&mut sk, 7, 1, 0, 0.016, 0.0);
        assert_eq!(sk.tfs.get(&2).unwrap().pos, [0.0; 3], "no host: nothing happens");

        unsafe { ok_set_mod_frame(Some(push_and_bend)) };
        post_pose(&mut sk, 7, 1, 0, 0.016, 0.0);
        assert_eq!(sk.tfs.get(&2).unwrap().pos, [0.0, 1.0, 0.0]);
        assert_eq!(force_at_slow(7, [1.0, 0.0, 0.0]), [0.5, 0.0, 0.0]);
        assert_eq!(force_at_slow(7, [3.0, 0.0, 0.0]), [0.0; 3], "outside the sphere");
        assert_eq!(force_at_slow(8, [0.0; 3]), [0.0; 3], "another character");
        unsafe { ok_set_mod_frame(None) };
        assert_eq!(force_at([0.0; 3]), [0.0; 3]);
    }
}
