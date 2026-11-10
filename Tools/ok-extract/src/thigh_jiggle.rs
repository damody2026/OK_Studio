//! Her thighs and buttocks jiggle behind her legs (user, 2026-11-10: ref/zzz_thigh_jiggle.md, the Zenless Zone Zero
//! style shown by Layla_3D). Six short helper "bones" a side: the upper and lower buttock, the upper, middle and lower
//! back of the thigh and the back of the calf. Each is a rotation spring of chain length one: its tail, 6 cm behind its
//! head inside the flesh, lags its parent bone and swings back (the head stays; no stretch, no gravity), at its own
//! natural frequency, falling from the calf to the buttock, so one step's jolt reaches the buttock last.
//!
//! The card's body has no such bones (her `cf_s_thigh*` / `cf_s_leg*` carry whole rings of the leg, front and back), so
//! the islands are worked out from her body mesh as it is bound: each a patch of the back of the leg, its weight peaking
//! at 0.6 and fading into its neighbours. Their moves are drawn as one morph of her body (in the mesh's own space, as
//! the vertex is skinned), not as bones: the skeleton, the mesh and the cards stay as they are.
use crate::pose::{mat_inv_pub, mat_mul_pub, Mat4};
use crate::session::{OkSession, SessionPart};

/// One helper: its spring (natural frequency, damping ratio), the most it swings, and where its island lies.
struct Spec { name: &'static str, f0: f32, zeta: f32, max_deg: f32 }
/// The design table of the reference (2 Hz walk: the calf 18 degrees behind, the upper buttock 76).
const SPECS: [Spec; 6] = [
    Spec { name: "calf", f0: 7.32, zeta: 0.55, max_deg: 5. },
    Spec { name: "thigh_lo", f0: 4.09, zeta: 0.45, max_deg: 6. },
    Spec { name: "thigh_mid", f0: 3.08, zeta: 0.40, max_deg: 7. },
    Spec { name: "thigh_up", f0: 2.59, zeta: 0.36, max_deg: 8. },
    Spec { name: "butt_lo", f0: 2.31, zeta: 0.32, max_deg: 10. },
    Spec { name: "butt", f0: 2.22, zeta: 0.42, max_deg: 8. },
];
/// From the head back to the tail (all six alike: the reach is the angle's).
const TAIL_M: f32 = 0.06;
/// The most of a vertex an island takes from its own bones (the reference's green to yellow).
const PEAK: f32 = 0.6;
/// Longest step of the springs (a 30 Hz frame is cut in four).
const STEP_S: f32 = 1. / 120.;

/// One helper of one side, ready: its island, its head and rest tail (mesh space), the bone leading it.
struct Island { spec: usize, bone: usize, head: [f32; 3], tail: [f32; 3], verts: Vec<(u32, f32)> }
/// Its spring now: the tail's place and speed (her skeleton space) and the target tail it followed last.
#[derive(Clone, Copy, Default)]
struct Spring { q: [f32; 3], v: [f32; 3], target: [f32; 3], live: bool }

/// Her helpers and their springs, and the moves last worked out (vertex, move in the mesh's own space).
pub struct ThighJiggle { body: usize, verts: usize, islands: Vec<Island>, springs: Vec<Spring>, pub moves: Vec<(u32, [f32; 3])> }

static ALL: std::sync::Mutex<Vec<(usize, ThighJiggle)>> = std::sync::Mutex::new(Vec::new());

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn add(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[0] + b[0], a[1] + b[1], a[2] + b[2]] }
fn scale(a: [f32; 3], s: f32) -> [f32; 3] { [a[0] * s, a[1] * s, a[2] * s] }
fn dot(a: [f32; 3], b: [f32; 3]) -> f32 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
fn len(a: [f32; 3]) -> f32 { dot(a, a).sqrt() }
fn unit(a: [f32; 3]) -> [f32; 3] { let l = len(a);if l > 1e-9 { scale(a, 1. / l) } else { [0.; 3] } }
fn point(m: &Mat4, p: [f32; 3]) -> [f32; 3] { std::array::from_fn(|i| m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3]) }
fn vector(m: &Mat4, p: [f32; 3]) -> [f32; 3] { std::array::from_fn(|i| m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2]) }
fn smooth(e0: f32, e1: f32, x: f32) -> f32 { let t = ((x - e0) / (e1 - e0)).clamp(0., 1.);t * t * (3. - 2. * t) }
fn gauss(x: f32, sigma: f32) -> f32 { (-0.5 * (x / sigma) * (x / sigma)).exp() }

/// The rotation turning unit `a` onto unit `b` (no twist about either), as a function on vectors.
fn turn(a: [f32; 3], b: [f32; 3]) -> impl Fn([f32; 3]) -> [f32; 3] {
    let k = cross(a, b);let s = len(k);let c = dot(a, b);
    let axis = if s > 1e-9 { scale(k, 1. / s) } else { [0.; 3] };
    move |v: [f32; 3]| {
        if s <= 1e-9 { return v; }
        // Rodrigues.
        add(add(scale(v, c), scale(cross(axis, v), s)), scale(axis, dot(axis, v) * (1. - c)))
    }
}

impl ThighJiggle {
    /// Her helpers from her body as bound; None when the bones it needs are not hers (a male body has no `cf_s_siri`).
    fn new(session: &OkSession) -> Option<ThighJiggle> {
        let skel = session.body_skel.as_ref()?;
        let (body, part) = session.parts.iter().enumerate().filter(|(_, p)| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none())
            .max_by_key(|(_, p)| p.rest_positions.len())?;
        let index = |name: &str| skel.names.iter().position(|n| n.eq_ignore_ascii_case(name)).filter(|&i| i < part.bind_poses.len());
        // A bone's place in the mesh's space, as the mesh is bound.
        let at = |i: usize| { let m = mat_inv_pub(&part.bind_poses[i]);[m[0][3], m[1][3], m[2][3]] };
        let back = [0., 0., -1.];
        let mut islands = Vec::new();
        for side in ["L", "R"] {
            let n = |b: &str| index(&format!("{b}_{side}"));
            let (Some(hip), Some(knee), Some(ankle), Some(butt), Some(pelvis)) = (n("cf_s_thigh01"), n("cf_s_leg01"), n("cf_s_leg03"), n("cf_s_siri"), index("cf_s_waist02")) else { return None; };
            let (h, k, a, b) = (at(hip), at(knee), at(ankle), at(butt));
            let thigh = sub(k, h);let thigh_len = len(thigh);let thigh_dir = unit(thigh);
            let shin = sub(a, k);let shin_len = len(shin);let shin_dir = unit(shin);
            if thigh_len < 0.1 || shin_len < 0.1 { return None; }
            let other = if side == "L" { "R" } else { "L" };
            let other_hip = at(index(&format!("cf_s_thigh01_{other}"))?);
            // This side's vertices: nearer this leg than the other one.
            let mine = |v: [f32; 3]| (v[0] - h[0]).abs() < (v[0] - other_hip[0]).abs();
            let island = |spec: usize, bone: usize, weigh: &dyn Fn([f32; 3], [f32; 3]) -> f32, axis_at: &dyn Fn([f32; 3]) -> [f32; 3]| -> Option<Island> {
                let mut verts = Vec::new();let mut sum = [0.; 3];let mut total = 0.;
                for (j, (v, nrm)) in part.rest_positions.iter().zip(&part.rest_normals).enumerate() {
                    if !mine(*v) { continue; }
                    // The back of her (and its outer side a little): the front and the knee stay on her bones.
                    let w = PEAK * weigh(*v, *nrm) * smooth(0.05, 0.6, dot(unit(*nrm), back));
                    if w < 0.02 { continue; }
                    verts.push((j as u32, w));for i in 0..3 { sum[i] += v[i] * w; }total += w;
                }
                if verts.len() < 8 { return None; }
                // The head inside the flesh: half way from the axis to the island's middle; the tail straight back.
                let mid = scale(sum, 1. / total);let axis = axis_at(mid);
                let head = add(axis, scale(sub(mid, axis), 0.5));
                Some(Island { spec, bone, head, tail: add(head, scale(back, TAIL_M)), verts })
            };
            let on_thigh = |v: [f32; 3]| { let t = dot(sub(v, h), thigh_dir) / thigh_len;(t, add(h, scale(thigh_dir, t.clamp(0., 1.) * thigh_len))) };
            let on_shin = |v: [f32; 3]| { let t = dot(sub(v, k), shin_dir) / shin_len;(t, add(k, scale(shin_dir, t.clamp(0., 1.) * shin_len))) };
            let near_leg = |v: [f32; 3], axis: [f32; 3]| 1. - smooth(0.09, 0.13, len(sub(v, axis)));
            // The back of the calf, its swell (a third of the way down).
            if let Some(i) = island(0, knee, &|v, _| { let (t, p) = on_shin(v);gauss(t - 0.3, 0.14) * near_leg(v, p) }, &|m| on_shin(m).1) { islands.push(i); }
            // The thigh's lower, middle and upper bands (the lowest kept off the back of the knee).
            for (spec, c) in [(1, 0.74), (2, 0.5), (3, 0.27)] {
                if let Some(i) = island(spec, hip, &|v, _| { let (t, p) = on_thigh(v);gauss(t - c, 0.11) * near_leg(v, p) * (1. - smooth(0.86, 0.95, t)) }, &|m| on_thigh(m).1) { islands.push(i); }
            }
            // The buttock above her thigh: its lower crescent at the fold (on her thigh), its upper part on her pelvis.
            let height = |v: [f32; 3]| dot(sub(v, h), scale(thigh_dir, -1.));
            let beside = |v: [f32; 3]| 1. - smooth(0.07, 0.11, (v[0] - b[0]).abs());
            let behind = |v: [f32; 3]| smooth(0.0, 0.03, h[2] - v[2]);
            let axis_up = |m: [f32; 3]| [m[0], m[1], h[2]];
            if let Some(i) = island(4, hip, &|v, _| gauss(height(v) + 0.05, 0.03) * beside(v) * behind(v), &axis_up) { islands.push(i); }
            if let Some(i) = island(5, pelvis, &|v, _| gauss(height(v) - 0.035, 0.04) * beside(v) * behind(v), &axis_up) { islands.push(i); }
        }
        if islands.is_empty() { return None; }
        // Where islands overlap a vertex keeps no more than its peak.
        let mut taken = vec![0f32; part.rest_positions.len()];
        for i in &islands { for (j, w) in &i.verts { taken[*j as usize] += w; } }
        for i in &mut islands { for (j, w) in &mut i.verts { let t = taken[*j as usize];if t > PEAK { *w *= PEAK / t; } } }
        let springs = vec![Spring::default(); islands.len()];
        Some(ThighJiggle { body, verts: part.rest_positions.len(), islands, springs, moves: Vec::new() })
    }

    /// The springs `dt` on (her skeleton as posed now; 0 keeps them), and the moves of her body's vertices.
    fn step(&mut self, part: &SessionPart, worlds: &[Mat4], dt: f32, gain: f32) {
        let skin = |b: usize| worlds.get(b).zip(part.bind_poses.get(b)).map(|(w, bind)| mat_mul_pub(w, bind));
        self.moves.clear();
        let mut by_vertex: std::collections::HashMap<u32, [f32; 3]> = std::collections::HashMap::new();
        for (island, spring) in self.islands.iter().zip(&mut self.springs) {
            let Some(s) = skin(island.bone) else { continue; };
            let spec = &SPECS[island.spec];
            let head = point(&s, island.head);let target = point(&s, island.tail);
            // A first frame, or her skeleton jumped (a new clip placed her elsewhere): the tail starts where it rests.
            if !spring.live || len(sub(target, spring.q)) > 0.3 { *spring = Spring { q: target, v: [0.; 3], target, live: true }; }
            if dt > 0. {
                let w = 2. * std::f32::consts::PI * spec.f0;let zeta = spec.zeta;
                let steps = (dt / STEP_S).ceil().max(1.) as usize;let h = dt / steps as f32;
                let target_v = scale(sub(target, spring.target), 1. / dt);
                for k in 0..steps {
                    // The target moves along with her bone over the frame.
                    let f = (k + 1) as f32 / steps as f32;
                    let t_now = add(spring.target, scale(sub(target, spring.target), f));
                    let a = sub(scale(sub(t_now, spring.q), w * w), scale(sub(spring.v, target_v), 2. * zeta * w));
                    spring.v = add(spring.v, scale(a, h));spring.q = add(spring.q, scale(spring.v, h));
                    // No stretch: the tail stays on its sphere round the head.
                    let d = sub(spring.q, head);let l = len(d);if l > 1e-6 { spring.q = add(head, scale(d, TAIL_M / l)); }
                }
                spring.target = target;
            }
            // The swing, in the mesh's space, held to its limit.
            let inv = mat_inv_pub(&s);
            let rest = unit(sub(island.tail, island.head));
            let mut now = unit(vector(&inv, sub(spring.q, head)));
            let max = (spec.max_deg * gain).to_radians();
            let angle = dot(rest, now).clamp(-1., 1.).acos();
            if angle > max {
                let side = unit(sub(now, scale(rest, dot(now, rest))));
                now = add(scale(rest, max.cos()), scale(side, max.sin()));
                // The tail held there too, so it does not wind up past the limit.
                spring.q = add(head, scale(unit(vector(&s, now)), TAIL_M));
            }
            if angle < 1e-5 { continue; }
            let r = turn(rest, now);
            for (j, wgt) in &island.verts {
                let v = part.rest_positions[*j as usize];
                let moved = add(island.head, r(sub(v, island.head)));
                let d = scale(sub(moved, v), *wgt);
                let e = by_vertex.entry(*j).or_insert([0.; 3]);*e = add(*e, d);
            }
        }
        self.moves = by_vertex.into_iter().filter(|(_, d)| dot(*d, *d) > 1e-10).collect();
        self.moves.sort_unstable_by_key(|(j, _)| *j);
    }
}

/// Her thighs' and buttocks' jiggle `dt` on (0: as it was): the session part of her body and its vertices' moves, or
/// None (no female body, `gain` 0). `gain` scales the swing limits (1: the reference's).
pub fn thigh_jiggle(session: &OkSession, dt: f32, gain: f32) -> Option<(usize, Vec<(u32, [f32; 3])>)> {
    let key = session as *const OkSession as usize;
    let mut all = ALL.lock().unwrap();
    if gain <= 0. { all.retain(|(k, _)| *k != key);return None; }
    let skel = session.body_skel.as_ref()?;
    let fresh = |j: &ThighJiggle| session.parts.get(j.body).is_some_and(|p| p.role == "body" && p.rest_positions.len() == j.verts);
    if !all.iter().any(|(k, j)| *k == key && fresh(j)) {
        all.retain(|(k, _)| *k != key);
        let made = ThighJiggle::new(session)?;
        if all.len() >= 16 { all.remove(0); }
        all.push((key, made));
    }
    let (_, jiggle) = all.iter_mut().find(|(k, _)| *k == key)?;
    jiggle.step(&session.parts[jiggle.body], &skel.worlds, dt.clamp(0., 0.1), gain);
    Some((jiggle.body, jiggle.moves.clone()))
}

#[cfg(test)]
mod tests {
    use super::*;

    // A spring started level, its target swung up and held: the tail follows, overshoots a little and settles.
    #[test]
    fn a_spring_follows_and_settles() {
        let spec = &SPECS[3];let w = 2. * std::f32::consts::PI * spec.f0;
        let mut s = Spring { q: [0., 0., -TAIL_M], v: [0.; 3], target: [0., 0., -TAIL_M], live: true };
        let target = [0., TAIL_M * 0.2, -TAIL_M * 0.98];
        let mut most: f32 = 0.;
        for _ in 0..240 {
            let h = STEP_S;
            let a = sub(scale(sub(target, s.q), w * w), scale(s.v, 2. * spec.zeta * w));
            s.v = add(s.v, scale(a, h));s.q = add(s.q, scale(s.v, h));
            let l = len(s.q);s.q = scale(s.q, TAIL_M / l);most = most.max(s.q[1]);
        }
        assert!((s.q[1] - target[1]).abs() < 1e-3, "{:?}", s.q);
        assert!(most > target[1], "no overshoot: {most}");
    }

    // The turn takes one direction onto the other and leaves the axis between them alone.
    #[test]
    fn turn_takes_a_onto_b() {
        let (a, b) = ([0., 0., -1.], unit([0., 0.2, -1.]));
        let r = turn(a, b);let t = r(a);
        assert!(len(sub(t, b)) < 1e-5, "{t:?}");
        let x = r([1., 0., 0.]);assert!(len(sub(x, [1., 0., 0.])) < 1e-5, "{x:?}");
    }
}

/// Her islands as worked out (a test's look at them).
#[cfg(test)]
pub(crate) fn debug_islands(session: &OkSession) {
    let Some(j) = ThighJiggle::new(session) else { eprintln!("no islands");return; };
    for i in &j.islands {
        let peak = i.verts.iter().map(|(_, w)| *w).fold(0f32, f32::max);
        eprintln!("{:10} bone {:3} verts {:4} peak {:.2} head [{:.3} {:.3} {:.3}]", SPECS[i.spec].name, i.bone, i.verts.len(), peak, i.head[0], i.head[1], i.head[2]);
    }
}
