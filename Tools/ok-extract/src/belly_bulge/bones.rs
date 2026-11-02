//! Her belly's own bones (ok.HScene.Wrap 3, user 2026-11-02: BetterPenetration's way, "add belly bones yourself"): BP
//! swells a belly with a DynamicBone on `cf_J_Belly` bones his penis colliders push away, but the KKS BP bodies
//! (Profundis, SAC Innie) carry no such bones. So her body gets them here: bones on her skin round her entrance, one each
//! `BONE_CELL_M`, each riding on the skin it sits on (its vertex's own skinning, so it turns with her as the skin does;
//! the swells made beforehand turned with her thighs, GalV1103a~c), the skin round each bound to it by weights made
//! once at rest. Each frame each bone is pushed by his penis, the tube from her entrance to his glans: out the way her
//! belly faces, past his far side, as BP's colliders push its particles (the bone's own radius `BONE_RADIUS_M`), and
//! follows that like a spring, rising faster than it settles. Her skin moves with its bones by their weights, drawn as
//! the same morph as `wrap_deltas`.
use super::*;

/// One bone each this far apart on her skin at rest, and how far its weight reaches (one standard deviation; nothing
/// past `BONE_REACH`) and over how many bones at most each skin is shared.
/// (3.5 cm apart, 3 cm reach: the weights evened the tent's top under his glans, which stood out of it, GalBones1.)
const BONE_CELL_M: f32 = 0.02;
const BONE_SIGMA_M: f32 = 0.015;
const BONE_REACH: f32 = 2.5;
const BONE_MOST: usize = 6;
/// Each bone's own radius against his (BP's DynamicBone m_Radius).
const BONE_RADIUS_M: f32 = 0.01;
/// Of the way to where he pushes it, how much each bone goes each frame rising and settling.
/// (0.6 left the tent a frame behind his thrust, his glans out of its top, GalBones1.)
const BONE_RISE: f32 = 0.9;
const BONE_SETTLE: f32 = 0.3;

struct BellyBones { key: (usize, usize), anchor: Vec<usize>, weights: Vec<Vec<(u32, f32)>>, lift: Vec<f32> }
static BONES: std::sync::Mutex<Option<BellyBones>> = std::sync::Mutex::new(None);

/// Her bones and their weights, made from her skin at rest (bind pose): `wrap_verts`' skin, a bone on the skin nearest
/// the middle of each cell that pushes (her lips, the walls of her vagina and the skin on her thighs and bottom carry
/// none, as with `wrap_deltas`).
fn make(session: &OkSession, part: &SessionPart, verts: &[WrapVert]) -> Option<BellyBones> {
    let rest = crate::skel_export::bind_body(session)?;
    let (worlds, binds) = crate::skel_export::palettes(&rest, part);
    if worlds.is_empty() { return None; }
    let at: Vec<Option<[f32; 3]>> = verts.iter().map(|v| skin_of(part, v.j, &worlds, &binds, &[], &[]).map(|(m, _, _)| point(&m, part.rest_positions[v.j]))).collect();
    let lips = |d: f32| ((d - WRAP_LIPS_M) / WRAP_LIPS_FADE_M).clamp(0., 1.);
    let cell = |p: [f32; 3]| p.map(|v| (v / BONE_CELL_M).floor() as i64);
    let mut best: HashMap<[i64; 3], (f32, usize)> = HashMap::new();
    for (i, v) in verts.iter().enumerate() {
        let Some(p) = at[i] else { continue; };
        if v.inner || v.free < 0.5 || lips(v.from_entrance) < 1. { continue; }
        let c = cell(p);
        let middle = c.map(|k| (k as f32 + 0.5) * BONE_CELL_M);
        let d = (0..3).map(|a| (p[a] - middle[a]) * (p[a] - middle[a])).sum::<f32>();
        let e = best.entry(c).or_insert((f32::MAX, i));
        if d < e.0 { *e = (d, i); }
    }
    let mut anchor: Vec<usize> = best.values().map(|(_, i)| *i).collect();anchor.sort();
    let reach = BONE_SIGMA_M * BONE_REACH;
    let mut grid: HashMap<[i64; 3], Vec<u32>> = HashMap::new();
    let rcell = |p: [f32; 3]| p.map(|v| (v / reach).floor() as i64);
    for (b, &i) in anchor.iter().enumerate() { grid.entry(rcell(at[i].unwrap())).or_default().push(b as u32); }
    let weights = at.iter().map(|p| {
        let Some(p) = p else { return Vec::new(); };
        let c = rcell(*p);let mut w: Vec<(u32, f32)> = Vec::new();
        for dx in -1..=1 { for dy in -1..=1 { for dz in -1..=1 {
            for &b in grid.get(&[c[0] + dx, c[1] + dy, c[2] + dz]).into_iter().flatten() {
                let q = at[anchor[b as usize]].unwrap();
                let d2 = (0..3).map(|a| (p[a] - q[a]) * (p[a] - q[a])).sum::<f32>();
                if d2 < reach * reach { w.push((b, (-d2 / (2. * BONE_SIGMA_M * BONE_SIGMA_M)).exp())); }
            }
        }}}
        w.sort_by(|a, b| b.1.total_cmp(&a.1));w.truncate(BONE_MOST);
        // Full weight where bones are all round; fading to none past the outermost (sum under one).
        let sum = w.iter().map(|x| x.1).sum::<f32>().max(1.);
        for x in &mut w { x.1 /= sum; }
        w
    }).collect();
    let n = anchor.len();
    Some(BellyBones { key: (0, 0), anchor, weights, lift: vec![0.; n] })
}

/// How her body's skin moves this frame with her belly bones pushed by his penis, the tube from `from` (her entrance) to
/// `to` (his glans), `radius` round, `up` the way her belly faces (her skeleton space, metres); as `wrap_deltas` gives it.
/// No `up`: none (and her bones settle back).
pub fn bone_deltas(session: &OkSession, from: [f32; 3], to: [f32; 3], up: [f32; 3], radius: f32) -> Vec<(u32, [f32; 6])> {
    let Some(skel) = session.body_skel.as_ref() else { return Vec::new(); };
    let Some(part) = session.parts.iter().find(|p| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none() && p.blend_shapes.iter().any(|(n, _)| is_bulge(n))) else { return Vec::new(); };
    let Some(verts) = wrap_verts(session, part) else { return Vec::new(); };
    let key = (part as *const SessionPart as usize, part.rest_positions.len());
    let mut cache = BONES.lock().unwrap();
    if cache.as_ref().map_or(true, |b| b.key != key) {
        let Some(mut made) = make(session, part, &verts) else { return Vec::new(); };
        made.key = key;
        crate::ffi::ffi_log(1, &format!("belly bones: {} bones over {} skin vertices", made.anchor.len(), verts.len()));
        *cache = Some(made);
    }
    let bones = cache.as_mut().unwrap();
    let (worlds, binds) = crate::skel_export::palettes(skel, part);
    if worlds.is_empty() { return Vec::new(); }
    let sub = |a: [f32; 3], b: [f32; 3]| [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
    let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let posed = posed_verts(part, &verts, &worlds, &binds);
    let mut pos: Vec<Option<[f32; 3]>> = vec![None; verts.len()];let mut normal = vec![[0f32; 3]; verts.len()];
    for q in &posed { pos[q.i] = Some(q.p);normal[q.i] = q.n; }
    let ul = dot(up, up).sqrt();
    let up = if ul > 1e-6 { [up[0] / ul, up[1] / ul, up[2] / ul] } else { [0.; 3] };
    // Where his penis pushes each bone: past his far side the way her belly faces, if he passes within his radius and
    // the bone's of the line up from it (BP: the collider pushes the particle out of it).
    let axis = sub(to, from);let reach = radius + BONE_RADIUS_M;
    let samples = ((dot(axis, axis).sqrt() / (reach * 0.5)).ceil() as usize).max(1);
    for (b, &i) in bones.anchor.iter().enumerate() {
        let mut want = 0f32;
        if let (Some(p), true) = (pos[i], ul > 1e-6) {
            let face = ((dot(normal[i], up) - WRAP_FACE_FROM) / (WRAP_FACE_FULL - WRAP_FACE_FROM)).clamp(0., 1.);
            if face > 0. {
                for s in 0..=samples {
                    let k = s as f32 / samples as f32;
                    let rel = sub([from[0] + axis[0] * k, from[1] + axis[1] * k, from[2] + axis[2] * k], p);
                    let hu = dot(rel, up);let lat = sub(rel, [up[0] * hu, up[1] * hu, up[2] * hu]);
                    let l2 = dot(lat, lat);if l2 >= reach * reach { continue; }
                    want = want.max(hu + (reach * reach - l2).sqrt());
                }
                want = want.min(WRAP_MOST_M) * face;
            }
        }
        let h = &mut bones.lift[b];
        *h += (want - *h) * if want > *h { BONE_RISE } else { BONE_SETTLE };
        if *h < 1e-4 { *h = 0.; }
    }
    if bones.lift.iter().all(|h| *h == 0.) { return Vec::new(); }
    // Her skin with its bones (her lips less, as in `wrap_deltas`). Skin on her thighs and bottom carries no bone but
    // goes with the lifted bones it is bound to: left down beside them it stood as a black wall (GalBones1).
    let lips = |d: f32| { let t = ((d - WRAP_LIPS_M) / WRAP_LIPS_FADE_M).clamp(0., 1.); t * t * (3. - 2. * t) };
    let moved: Vec<Option<[f32; 3]>> = (0..verts.len()).map(|i| pos[i].map(|p| {
        let v = &verts[i];let free = v.free * v.free * (3. - 2. * v.free);
        let w = &bones.weights[i];
        let lifted = w.iter().filter(|(b, _)| bones.lift[*b as usize] > 0.005).map(|(_, w)| *w).sum::<f32>().min(1.);
        let lift = w.iter().map(|(b, w)| bones.lift[*b as usize] * w).sum::<f32>() * lips(v.from_entrance) * free.max(lifted);
        [p[0] + up[0] * lift, p[1] + up[1] * lift, p[2] + up[2] * lift]
    })).collect();
    mesh_moves(&verts, &posed, &pos, &moved)
}
