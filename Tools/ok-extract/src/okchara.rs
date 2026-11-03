//! OK character cards made from an authored character (Charakuru-style workflow:
//! illustration -> part images -> Tripo meshes -> rigged -> fitted to the Koikatsu skeleton).
//!
//! The card is an OK card of a base character. Its skeleton (and so every existing
//! animation, pose and pairing) drives the authored parts; the `okCh` chunk carries
//! those parts and hides the base character's own renderers.
//!
//! Positions are stored in the base skeleton's space as it opened when the card was
//! made, together with the world matrix of every bone they use, so the palette at
//! run time is `world_now * inverse(world_at_fit)`.
use crate::pose::{mat_inv_pub, mat_mul_pub, Mat4};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, ffi::CString, fs, io::Write, path::Path};

pub const CHUNK: &[u8; 4] = b"okCh";
const VERSION: u32 = 2;
/// Name prefix of every part an okCh chunk adds.
pub const PART_PREFIX: &str = "OKChara_";

#[derive(Serialize, Deserialize, Clone)]
pub struct CharaBone { pub name: String, pub fit_world: Mat4 }

#[derive(Serialize, Deserialize, Clone)]
pub struct CharaPart {
    pub name: String,
    /// Session role ("clothes_top", "hair_b", ...) and the clothing slot (ChaFileClothes kind 0..8, -1 none)
    /// whose state shows or hides it.
    pub role: String,
    pub slot: i8,
    pub positions: Vec<[f32; 3]>,
    pub normals: Vec<[f32; 3]>,
    pub tangents: Vec<[f32; 4]>,
    pub uvs: Vec<[f32; 2]>,
    pub indices: Vec<u32>,
    /// Indices into `CharaCard::bones`.
    pub bone_idx: Vec<[u16; 4]>,
    pub weights: Vec<[f32; 4]>,
    /// PNG albedo.
    /// Index into `CharaCard::textures` (PNG albedo).
    pub texture: u16,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct CharaCard {
    pub version: u32, pub name: String, pub bones: Vec<CharaBone>, pub parts: Vec<CharaPart>,
    /// Keep the base character's body and head (face, eyes, brows, mouth): the card is a regular character
    /// wearing authored clothes and hair. False: every base renderer is replaced.
    pub native: bool,
    /// Body _AlphaMask (PNG, red channel = under the top) replacing the base clothes' mask while the top is worn.
    pub body_mask: Option<Vec<u8>>,
    /// PNG albedo textures shared by the parts.
    pub textures: Vec<Vec<u8>>,
}

fn open_base(lib: &Path, card: &Path) -> Result<crate::session::OkSession, String> {
    crate::session::open(lib, Some(card), 0)
}

/// Bone names, parents and world matrices of the base card's skeleton as it opens,
/// plus its visible geometry as an OBJ (Unity coordinates), for fitting.
pub fn dump_skeleton(lib: &Path, card: &Path, out_json: &Path, out_obj: &Path) -> Result<serde_json::Value, String> {
    let s = open_base(lib, card)?;
    let sk = s.body_skel.as_ref().ok_or("base card has no body skeleton")?;
    let index: HashMap<i64, usize> = sk.bone_ids.iter().enumerate().map(|(i, id)| (*id, i)).collect();
    let bones: Vec<_> = sk.names.iter().enumerate().map(|(i, n)| {
        let parent = sk.bone_ids.get(i).and_then(|id| sk.tfs.get(id)).and_then(|t| t.parent).and_then(|p| index.get(&p)).map(|p| sk.names[*p].clone());
        serde_json::json!({"name": n, "parent": parent, "world": sk.worlds[i]})
    }).collect();
    let parts: Vec<_> = s.parts.iter().map(|p| serde_json::json!({"role": p.role, "name": p.name, "visible": p.render_visible, "skel_kind": p.skel_kind, "vertices": p.positions.len()})).collect();
    let report = serde_json::json!({"card": card, "bones": bones, "parts": parts});
    fs::write(out_json, serde_json::to_vec_pretty(&report).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    write_obj(out_obj, s.parts.iter().filter(|p| p.render_visible).map(|p| (format!("{}_{}", p.role, p.name), &p.positions, &p.indices)))?;
    Ok(serde_json::json!({"bones": sk.names.len(), "parts": s.parts.len(), "json": out_json, "obj": out_obj}))
}

fn write_obj<'a>(path: &Path, parts: impl Iterator<Item = (String, &'a Vec<[f32; 3]>, &'a Vec<u32>)>) -> Result<(), String> {
    let mut obj = std::io::BufWriter::new(fs::File::create(path).map_err(|e| e.to_string())?);
    let mut base = 1usize;
    for (name, pos, idx) in parts {
        writeln!(obj, "o {}", name.replace(' ', "_")).map_err(|e| e.to_string())?;
        for v in pos { writeln!(obj, "v {} {} {}", v[0], v[1], v[2]).map_err(|e| e.to_string())?; }
        for t in idx.chunks(3) { writeln!(obj, "f {} {} {}", t[0] as usize + base, t[1] as usize + base, t[2] as usize + base).map_err(|e| e.to_string())?; }
        base += pos.len();
    }
    Ok(())
}

// ---------- small vector math ----------
type V3 = [f32; 3];
fn sub(a: V3, b: V3) -> V3 { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn add(a: V3, b: V3) -> V3 { [a[0] + b[0], a[1] + b[1], a[2] + b[2]] }
fn mul(a: V3, s: f32) -> V3 { [a[0] * s, a[1] * s, a[2] * s] }
fn dot(a: V3, b: V3) -> f32 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
fn cross(a: V3, b: V3) -> V3 { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
fn len(a: V3) -> f32 { dot(a, a).sqrt() }
fn norm(a: V3) -> V3 { let l = len(a); if l > 1e-12 { mul(a, 1. / l) } else { [0., 1., 0.] } }
fn mid(a: V3, b: V3) -> V3 { mul(add(a, b), 0.5) }
type M3 = [[f32; 3]; 3];
fn m3_vec(m: &M3, v: V3) -> V3 { [dot(m[0], v), dot(m[1], v), dot(m[2], v)] }
fn m3_mul(a: &M3, b: &M3) -> M3 { let mut r = [[0f32; 3]; 3]; for i in 0..3 { for j in 0..3 { r[i][j] = (0..3).map(|k| a[i][k] * b[k][j]).sum(); } } r }
fn m3_ident() -> M3 { [[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]] }
/// Smallest rotation taking unit vector a onto unit vector b.
fn rot_between(a: V3, b: V3) -> M3 {
    let v = cross(a, b); let c = dot(a, b);
    if c < -0.9999 {
        // Opposite: rotate 180 degrees about any axis perpendicular to a.
        let axis = norm(if a[0].abs() < 0.9 { cross(a, [1., 0., 0.]) } else { cross(a, [0., 1., 0.]) });
        let mut r = [[0f32; 3]; 3];
        for i in 0..3 { for j in 0..3 { r[i][j] = 2. * axis[i] * axis[j] - if i == j { 1. } else { 0. }; } }
        return r;
    }
    let k = 1. / (1. + c);
    let vx: M3 = [[0., -v[2], v[1]], [v[2], 0., -v[0]], [-v[1], v[0], 0.]];
    let vx2 = m3_mul(&vx, &vx);
    let mut r = m3_ident();
    for i in 0..3 { for j in 0..3 { r[i][j] += vx[i][j] + vx2[i][j] * k; } }
    r
}
fn rot_y(theta: f32) -> M3 { let (s, c) = theta.sin_cos(); [[c, 0., s], [0., 1., 0.], [-s, 0., c]] }

/// One joint's fitting transform: x -> dst + R * S * (x - src).
#[derive(Clone, Copy)]
struct Fit { src: V3, dst: V3, rs: M3, normal: M3, rot: M3 }
impl Fit {
    fn apply(&self, x: V3) -> V3 { add(self.dst, m3_vec(&self.rs, sub(x, self.src))) }
    /// Segment src->src_child onto dst->dst_child: stretched along the bone by the
    /// length ratio, scaled across it by `g` (keeps the authored limb thickness).
    fn segment(src: V3, src_child: V3, dst: V3, dst_child: V3, g: f32) -> Fit {
        let a = norm(sub(src_child, src)); let b = norm(sub(dst_child, dst));
        let r = len(sub(dst_child, dst)) / len(sub(src_child, src)).max(1e-6);
        let mut s = [[0f32; 3]; 3];
        for i in 0..3 { for j in 0..3 { s[i][j] = if i == j { g } else { 0. } + (r - g) * a[i] * a[j]; } }
        let mut sn = [[0f32; 3]; 3];
        for i in 0..3 { for j in 0..3 { sn[i][j] = if i == j { 1. / g } else { 0. } + (1. / r - 1. / g) * a[i] * a[j]; } }
        let rot = rot_between(a, b);
        Fit { src, dst, rs: m3_mul(&rot, &s), normal: m3_mul(&rot, &sn), rot }
    }
    fn uniform(src: V3, dst: V3, rot: M3, g: f32) -> Fit {
        let mut rs = rot; for row in rs.iter_mut() { for v in row.iter_mut() { *v *= g; } }
        Fit { src, dst, rs, normal: rot, rot }
    }
    /// The turn alone (no scale): what a joint that keeps its proportions inherits.
    fn rotation(&self) -> M3 { self.rot }
}

// ---------- GLB reading ----------
struct SrcMesh { name: String, positions: Vec<V3>, normals: Vec<V3>, uvs: Vec<[f32; 2]>, indices: Vec<u32>, joints: Vec<[u16; 4]>, weights: Vec<[f32; 4]>, image: Vec<u8> }
struct Src { joint_names: Vec<String>, joint_pos: Vec<V3>, meshes: Vec<SrcMesh>, parent: HashMap<String, String> }
fn bare(n: &str) -> &str { n.trim_start_matches("mixamorig:") }

fn read_glb(path: &Path) -> Result<Src, String> {
    let bytes = fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let g = gltf::Gltf::from_slice(&bytes).map_err(|e| e.to_string())?;
    let blob = g.blob.as_deref().ok_or("GLB has no binary chunk")?;
    let skin = g.skins().next().ok_or("GLB has no skin (rig it first)")?;
    let joint_names: Vec<String> = skin.joints().map(|n| n.name().unwrap_or("").to_string()).collect();
    let ibm: Vec<[[f32; 4]; 4]> = skin.reader(|_| Some(blob)).read_inverse_bind_matrices().ok_or("skin has no inverse bind matrices")?.collect();
    // glTF matrices are column-major: m[col][row]. Joint world = inverse(IBM); take its translation.
    let joint_pos = ibm.iter().map(|m| {
        let rm: Mat4 = std::array::from_fn(|r| std::array::from_fn(|c| m[c][r]));
        let w = mat_inv_pub(&rm);
        [w[0][3], w[1][3], w[2][3]]
    }).collect();
    let mut meshes = Vec::new();
    for node in g.nodes().filter(|n| n.mesh().is_some()) {
        let mesh = node.mesh().unwrap();
        for prim in mesh.primitives() {
            let r = prim.reader(|_| Some(blob));
            let positions: Vec<V3> = r.read_positions().ok_or("primitive without positions")?.collect();
            let n = positions.len();
            let normals: Vec<V3> = r.read_normals().map(|x| x.collect()).unwrap_or_else(|| vec![[0., 1., 0.]; n]);
            let uvs: Vec<[f32; 2]> = r.read_tex_coords(0).map(|x| x.into_f32().collect()).unwrap_or_else(|| vec![[0., 0.]; n]);
            let indices: Vec<u32> = r.read_indices().map(|x| x.into_u32().collect()).unwrap_or_else(|| (0..n as u32).collect());
            let joints: Vec<[u16; 4]> = r.read_joints(0).ok_or("primitive without joints")?.into_u16().collect();
            let weights: Vec<[f32; 4]> = r.read_weights(0).ok_or("primitive without weights")?.into_f32().collect();
            let tex = prim.material().pbr_metallic_roughness().base_color_texture().ok_or("primitive without base colour texture")?;
            let image = match tex.texture().source().source() {
                gltf::image::Source::View { view, .. } => blob[view.offset()..view.offset() + view.length()].to_vec(),
                gltf::image::Source::Uri { uri, .. } => return Err(format!("external texture {uri} not supported")),
            };
            if normals.len() != n || uvs.len() != n || joints.len() != n || weights.len() != n { return Err("primitive channels differ in length".into()); }
            meshes.push(SrcMesh { name: node.name().unwrap_or("mesh").to_string(), positions, normals, uvs, indices, joints, weights, image });
        }
    }
    let mut parent = HashMap::new();
    for n in g.nodes() { for c in n.children() { parent.insert(bare(c.name().unwrap_or("")).to_string(), bare(n.name().unwrap_or("")).to_string()); } }
    let mut src = Src { joint_names, joint_pos, meshes, parent };
    align_joints_to_mesh(&mut src)?;
    Ok(src)
}

/// Tripo's exports keep joint nodes untransformed and the joint frame (from the inverse
/// bind matrices) turned against the vertices when the model was turned on upload.
/// Fit the joints onto the vertices they carry: a rotation about the vertical axis and a
/// translation (2D Procrustes over the weighted vertex centroids), applied when it helps.
fn align_joints_to_mesh(src: &mut Src) -> Result<f32, String> {
    let nj = src.joint_pos.len();
    let (mut sum, mut wsum) = (vec![[0f32; 3]; nj], vec![0f32; nj]);
    for m in &src.meshes {
        for v in 0..m.positions.len() {
            for k in 0..4 {
                let w = m.weights[v][k];
                if w < 0.5 { continue; }
                let j = m.joints[v][k] as usize;
                if j < nj { sum[j] = add(sum[j], mul(m.positions[v], w)); wsum[j] += w; }
            }
        }
    }
    let pairs: Vec<(V3, V3, f32)> = (0..nj).filter(|j| wsum[*j] > 5.).map(|j| (src.joint_pos[j], mul(sum[j], 1. / wsum[j]), wsum[j])).collect();
    if pairs.len() < 4 { return Err("too few weighted joints to check the rig against the mesh".into()); }
    let total: f32 = pairs.iter().map(|p| p.2).sum();
    let mp = pairs.iter().fold([0f32; 3], |a, p| add(a, mul(p.0, p.2 / total)));
    let mc = pairs.iter().fold([0f32; 3], |a, p| add(a, mul(p.1, p.2 / total)));
    let (mut sdot, mut scross) = (0f32, 0f32);
    for (p, c, w) in &pairs {
        let (a, b) = (sub(*p, mp), sub(*c, mc));
        // Rotation about +Y taking a (xz) onto b (xz): x' = x cos + z sin, z' = -x sin + z cos.
        sdot += w * (a[0] * b[0] + a[2] * b[2]);
        scross += w * (a[2] * b[0] - a[0] * b[2]);
    }
    let phi = scross.atan2(sdot);
    // Joints sit off their vertices' centroids (a limb's centroid is mid-bone), so only the
    // turn is taken from the fit; it is applied about the model origin, heights unchanged.
    let residual = |rot: &M3| -> f32 { pairs.iter().map(|(p, c, w)| w * len(sub(m3_vec(rot, *p), *c))).sum::<f32>() / total };
    let rot = rot_y(phi);
    if residual(&rot) < residual(&m3_ident()) * 0.8 {
        for p in src.joint_pos.iter_mut() { *p = m3_vec(&rot, *p); }
    }
    Ok(phi)
}

/// Mixamo joint (without side and prefix) -> Koikatsu bone name stem used for skin weights.
fn kk_skin_bone(mixamo: &str) -> Option<String> {
    let (side, base) = if let Some(b) = mixamo.strip_prefix("Left") { ("_L", b) } else if let Some(b) = mixamo.strip_prefix("Right") { ("_R", b) } else { ("", mixamo) };
    let finger = |stem: &str, rest: &str| -> Option<String> {
        let n: u32 = rest.parse().ok()?; Some(format!("cf_j_{stem}0{}{side}", n.min(3)))
    };
    let s = match base {
        "Hips" => "cf_j_hips".to_string(),
        "Spine" => "cf_s_spine01".into(), "Spine1" => "cf_s_spine02".into(), "Spine2" => "cf_s_spine03".into(),
        "Neck" => "cf_s_neck".into(), "Head" | "HeadTop_End" => "cf_s_head".into(),
        "Shoulder" => format!("cf_j_shoulder{side}"), "Arm" => format!("cf_j_arm00{side}"),
        "ForeArm" => format!("cf_j_forearm01{side}"), "Hand" => format!("cf_j_hand{side}"),
        "UpLeg" => format!("cf_j_thigh00{side}"), "Leg" => format!("cf_j_leg01{side}"),
        "Foot" => format!("cf_j_foot{side}"), "ToeBase" | "Toe_End" => format!("cf_j_toes{side}"),
        b => {
            for (m, k) in [("HandThumb", "thumb"), ("HandIndex", "index"), ("HandMiddle", "middle"), ("HandRing", "ring"), ("HandPinky", "little")] {
                if let Some(rest) = b.strip_prefix(m) { return finger(k, rest); }
            }
            return None;
        }
    };
    Some(s)
}

#[derive(Default, Deserialize)]
pub struct BuildOptions {
    /// Character name written into the card's okCh header.
    #[serde(default)] pub name: String,
    /// Vertices of these source meshes within this distance (m) of the base body take the body's weights.
    #[serde(default)] pub donor_meshes: Vec<String>,
    #[serde(default = "default_donor_distance")] pub donor_distance: f32,
    /// Card face image (PNG) replacing the base card's thumbnail.
    #[serde(default)] pub thumbnail: Option<String>,
    /// Longest texture side; larger albedo textures are downscaled.
    #[serde(default = "default_texture_size")] pub texture_size: u32,
    /// Per source mesh: the only rig joints its vertices may follow (others pass to the nearest allowed ancestor),
    /// e.g. hair must not follow the arms it hangs next to.
    #[serde(default)] pub allowed_joints: HashMap<String, Vec<String>>,
    /// Meshes whose part below the hips that stands off the skin follows the native skirt chains (cf_j_sk_*).
    #[serde(default)] pub skirt_meshes: Vec<String>,
    /// Below the hips, cloth farther than this from the skin is skirt.
    #[serde(default = "default_skirt_gap")] pub skirt_gap: f32,
    #[serde(default = "default_smooth")] pub smooth_iterations: u32,
    /// Cloth within this distance (m) of a shin or foot bone is boot or legging, not skirt.
    #[serde(default = "default_shin_radius")] pub shin_radius: f32,
    /// Per source mesh: an albedo image file replacing the GLB's (e.g. after `project`).
    #[serde(default)] pub texture_overrides: HashMap<String, String>,
    /// Press what lies under the ankles up to the floor when the fitted soles sink below it.
    #[serde(default = "yes")] pub ground: bool,
    /// Scale of the chest's front about the breast bones (1 = as authored), within bust_radius metres.
    #[serde(default = "one")] pub bust_scale: f32,
    #[serde(default = "default_bust_radius")] pub bust_radius: f32,
    /// Base card fields set before it is made an OK card again ([path, value], see `ok-chara fields`):
    /// face shape, pupils, brows, skin, head size... Needs `game` (zipmods of the base card).
    #[serde(default)] pub card_edits: Vec<(String, serde_json::Value)>,
    #[serde(default)] pub game: Option<String>,
    /// Keep the base body and face; source meshes become clothes (`clothes_meshes`) and hair (`hair_meshes`)
    /// with their painted skin removed.
    #[serde(default = "yes")] pub native: bool,
    #[serde(default)] pub clothes_meshes: Vec<String>,
    #[serde(default)] pub hair_meshes: Vec<String>,
    /// Hair placed by the painted eyes onto the base eyes: extra scale, and how far the base pupils sit
    /// behind the painted eye surface (m, +Z is the face's front).
    #[serde(default = "one")] pub hair_scale: f32,
    #[serde(default)] pub hair_eye_depth: f32,
    /// Body mask texture size and how far a skirt may hang off the skin and still hide it.
    #[serde(default = "default_mask_size")] pub mask_size: u32,
    #[serde(default = "default_mask_reach")] pub mask_reach: f32,
}
fn default_skirt_gap() -> f32 { 0.012 }
fn yes() -> bool { true }
fn default_bust_radius() -> f32 { 0.075 }
fn default_mask_size() -> u32 { 1024 }
fn default_mask_reach() -> f32 { 0.25 }
fn default_shin_radius() -> f32 { 0.075 }
fn seg_dist(p: V3, a: V3, b: V3) -> f32 {
    let ab = sub(b, a); let t = (dot(sub(p, a), ab) / dot(ab, ab).max(1e-9)).clamp(0., 1.);
    len(sub(p, add(a, mul(ab, t))))
}
fn default_smooth() -> u32 { 4 }

/// The base skeleton's skirt chains: cf_j_sk_CC_JJ, chains around the hips, joints downwards.
struct SkirtRig { center: V3, chains: Vec<(f32, Vec<(String, V3)>)> }
impl SkirtRig {
    fn from_skeleton(sk: &crate::pose::Skeleton) -> Option<SkirtRig> {
        let pos = |n: &str| sk.names.iter().position(|x| x == n).map(|i| { let w = sk.worlds[i]; [w[0][3], w[1][3], w[2][3]] });
        let center = pos("cf_j_hips")?;
        let mut chains = Vec::new();
        for c in 0..16 {
            let joints: Vec<(String, V3)> = (0..16).map_while(|j| { let n = format!("cf_j_sk_{c:02}_{j:02}"); pos(&n).map(|p| (n, p)) }).collect();
            if joints.len() < 2 { continue; }
            let a = joints[0].1; chains.push(((a[0] - center[0]).atan2(a[2] - center[2]), joints));
        }
        if chains.len() < 3 { return None; }
        chains.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());
        Some(SkirtRig { center, chains })
    }
    /// Two neighbouring chains by angle around the hips, and the two joints bracketing the height.
    fn weights(&self, p: V3) -> Vec<(String, f32)> {
        let ang = (p[0] - self.center[0]).atan2(p[2] - self.center[2]);
        let n = self.chains.len();
        let tau = std::f32::consts::TAU;
        let mut out = Vec::new();
        for i in 0..n {
            let (a0, a1) = (self.chains[i].0, self.chains[(i + 1) % n].0);
            let span = (a1 - a0).rem_euclid(tau).max(1e-4);
            let off = (ang - a0).rem_euclid(tau);
            if off <= span {
                let t = off / span;
                for (chain, cw) in [(&self.chains[i].1, 1. - t), (&self.chains[(i + 1) % n].1, t)] {
                    let mut placed = false;
                    for k in 0..chain.len() - 1 {
                        let (ya, yb) = (chain[k].1[1], chain[k + 1].1[1]);
                        if p[1] <= ya && p[1] >= yb {
                            let s = ((ya - p[1]) / (ya - yb).max(1e-5)).clamp(0., 1.);
                            out.push((chain[k].0.clone(), cw * (1. - s))); out.push((chain[k + 1].0.clone(), cw * s)); placed = true; break;
                        }
                    }
                    if !placed {
                        let j = if p[1] > chain[0].1[1] { 0 } else { chain.len() - 1 };
                        out.push((chain[j].0.clone(), cw));
                    }
                }
                break;
            }
        }
        out
    }
}

/// Average each selected vertex's weights with its neighbours' (vertices at one position count as one).
fn smooth_weights(vw: &mut [Vec<(String, f32)>], pos: &[V3], idx: &[u32], selected: impl Fn(usize) -> bool, iterations: u32) {
    let key = |p: V3| (p[0].to_bits(), p[1].to_bits(), p[2].to_bits());
    let mut weld: HashMap<(u32, u32, u32), usize> = HashMap::new();
    let rep: Vec<usize> = (0..pos.len()).map(|i| *weld.entry(key(pos[i])).or_insert(i)).collect();
    let mut nb: HashMap<usize, Vec<usize>> = HashMap::new();
    for t in idx.chunks(3) {
        for (a, b) in [(t[0], t[1]), (t[1], t[2]), (t[2], t[0])] {
            let (a, b) = (rep[a as usize], rep[b as usize]);
            nb.entry(a).or_default().push(b); nb.entry(b).or_default().push(a);
        }
    }
    for _ in 0..iterations {
        let snapshot: Vec<Vec<(String, f32)>> = vw.to_vec();
        for v in 0..vw.len() {
            if rep[v] != v || !selected(v) { continue; }
            let Some(ns) = nb.get(&v) else { continue };
            let mut acc: Vec<(String, f32)> = Vec::new();
            for &u in std::iter::once(&v).chain(ns.iter()) {
                let total: f32 = snapshot[u].iter().map(|e| e.1).sum::<f32>().max(1e-6);
                for (name, w) in &snapshot[u] { if let Some(e) = acc.iter_mut().find(|e| &e.0 == name) { e.1 += w / total; } else { acc.push((name.clone(), w / total)); } }
            }
            vw[v] = acc;
        }
        for v in 0..vw.len() { if rep[v] != v { vw[v] = vw[rep[v]].clone(); } }
    }
}

fn default_donor_distance() -> f32 { 0.03 }
fn default_texture_size() -> u32 { 4096 }

/// Build an OK character card: base OK card + rigged GLB -> fitted parts in an okCh chunk.
pub fn build(lib: &Path, base_card: &Path, glb: &Path, options: &BuildOptions, out: &Path, preview_obj: Option<&Path>) -> Result<serde_json::Value, String> {
    // The base card with this character's face and body settings, made an OK card again so its model
    // list and pack follow the changed ids.
    let base_path = out.with_extension("base.png");
    let base_bytes = if options.card_edits.is_empty() { fs::read(base_card).map_err(|e| e.to_string())? } else {
        let raw = fs::read(base_card).map_err(|e| e.to_string())?;
        let edited = crate::appearance::patch_paths(&raw, 0, &options.card_edits)?;
        let tmp = out.with_extension("edit.png");
        fs::write(&tmp, &edited).map_err(|e| e.to_string())?;
        let game = Path::new(options.game.as_deref().ok_or("card_edits need the game directory (game) to make the OK card again")?);
        let made = crate::oklib::remake_ok_card(lib, game, &tmp);
        let _ = fs::remove_file(&tmp);
        made?.2
    };
    fs::write(&base_path, &base_bytes).map_err(|e| e.to_string())?;
    let s = open_base(lib, &base_path)?;
    let sk = s.body_skel.as_ref().ok_or("base card has no body skeleton")?;
    let bone_index: HashMap<&str, usize> = sk.names.iter().enumerate().map(|(i, n)| (n.as_str(), i)).collect();
    let kpos = |n: &str| -> Result<V3, String> { let i = *bone_index.get(n).ok_or(format!("base skeleton has no {n}"))?; let w = sk.worlds[i]; Ok([w[0][3], w[1][3], w[2][3]]) };

    let mut src = read_glb(glb)?;
    // glTF (right-handed) -> Unity (left-handed): mirror X.
    let to_unity = |p: V3| [-p[0], p[1], p[2]];
    for p in src.joint_pos.iter_mut() { *p = to_unity(*p); }
    for m in src.meshes.iter_mut() {
        for p in m.positions.iter_mut() { *p = to_unity(*p); }
        for n in m.normals.iter_mut() { *n = to_unity(*n); }
        for t in m.indices.chunks_mut(3) { t.swap(1, 2); }
    }
    let jidx: HashMap<String, usize> = src.joint_names.iter().enumerate().map(|(i, n)| (n.trim_start_matches("mixamorig:").to_string(), i)).collect();
    let jp = |n: &str| -> Result<V3, String> { jidx.get(n).map(|i| src.joint_pos[*i]).ok_or(format!("rig has no joint {n}")) };
    // Face the character down +Z like the Koikatsu skeleton (Tripo may have turned it on upload).
    let fwd = sub(mid(jp("LeftToeBase")?, jp("RightToeBase")?), mid(jp("LeftFoot")?, jp("RightFoot")?));
    let theta = (-fwd[0]).atan2(fwd[2]);
    let yaw = rot_y(theta);
    {
        let check = m3_vec(&yaw, fwd);
        if check[2] <= 0. { return Err(format!("could not orient the rig forward ({check:?})")); }
    }
    for p in src.joint_pos.iter_mut() { *p = m3_vec(&yaw, *p); }
    for m in src.meshes.iter_mut() {
        for p in m.positions.iter_mut() { *p = m3_vec(&yaw, *p); }
        for n in m.normals.iter_mut() { *n = m3_vec(&yaw, *n); }
    }
    let jp = |n: &str| -> Result<V3, String> { jidx.get(n).map(|i| src.joint_pos[*i]).ok_or(format!("rig has no joint {n}")) };
    if jp("LeftArm")?[0] >= 0. { return Err("rig's LeftArm is not on the character's left (-X) after conversion".into()); }

    // Global cross-section scale: the torso ratio.
    let thigh_mid_src = mid(jp("LeftUpLeg")?, jp("RightUpLeg")?);
    let thigh_mid_dst = mid(kpos("cf_j_thigh00_L")?, kpos("cf_j_thigh00_R")?);
    let g = len(sub(kpos("cf_j_neck")?, thigh_mid_dst)) / len(sub(jp("Neck")?, thigh_mid_src)).max(1e-6);

    // Fit transform of every rig joint.
    let mut fits: Vec<Option<Fit>> = vec![None; src.joint_names.len()];
    fn set_fit(fits: &mut [Option<Fit>], jidx: &HashMap<String, usize>, name: &str, f: Fit) { if let Some(i) = jidx.get(name) { fits[*i] = Some(f); } }
    macro_rules! set { ($n:expr, $f:expr) => { set_fit(&mut fits, &jidx, $n, $f) }; }
    set!("Hips", Fit::uniform(thigh_mid_src, thigh_mid_dst, m3_ident(), g));
    let mut segs: Vec<(String, String, String, String)> = vec![
        ("Spine".into(), "Spine1".into(), "cf_j_spine01".into(), "cf_j_spine02".into()),
        ("Spine1".into(), "Spine2".into(), "cf_j_spine02".into(), "cf_j_spine03".into()),
        ("Spine2".into(), "Neck".into(), "cf_j_spine03".into(), "cf_j_neck".into()),
        ("Neck".into(), "Head".into(), "cf_j_neck".into(), "cf_j_head".into()),
    ];
    for (side, s) in [("Left", "_L"), ("Right", "_R")] {
        let f = |m: &str, mc: &str, k: &str, kc: &str| (format!("{side}{m}"), format!("{side}{mc}"), format!("{k}{s}"), format!("{kc}{s}"));
        segs.push(f("Shoulder", "Arm", "cf_j_shoulder", "cf_j_arm00"));
        segs.push(f("Arm", "ForeArm", "cf_j_arm00", "cf_j_forearm01"));
        segs.push(f("ForeArm", "Hand", "cf_j_forearm01", "cf_j_hand"));
        segs.push(f("Hand", "HandMiddle1", "cf_j_hand", "cf_j_middle01"));
        segs.push(f("UpLeg", "Leg", "cf_j_thigh00", "cf_j_leg01"));
        segs.push(f("Leg", "Foot", "cf_j_leg01", "cf_j_leg03"));
        segs.push(f("Foot", "ToeBase", "cf_j_leg03", "cf_j_toes"));
        for (m, k) in [("Thumb", "thumb"), ("Index", "index"), ("Middle", "middle"), ("Ring", "ring"), ("Pinky", "little")] {
            for i in 1..3 { segs.push(f(&format!("Hand{m}{i}"), &format!("Hand{m}{}", i + 1), &format!("cf_j_{k}0{i}"), &format!("cf_j_{k}0{}", i + 1))); }
        }
    }
    let mut fitted_segments = 0;
    for (a, b, ka, kb) in &segs {
        if let (Ok(pa), Ok(pb), Ok(qa), Ok(qb)) = (jp(a), jp(b), kpos(ka), kpos(kb)) { set!(a, Fit::segment(pa, pb, qa, qb, g)); fitted_segments += 1; }
    }
    // Head keeps its authored proportions.
    // Upright like the base head at rest: the authored necks lean differently, the heads both look ahead.
    let neck_rot = m3_ident();
    set!("Head", Fit::uniform(jp("Head")?, kpos("cf_j_head")?, neck_rot, g));
    // Leaves and unmapped joints follow the nearest fitted ancestor (by name chain).
    let g_parent = src.parent.clone();
    for i in 0..fits.len() {
        if fits[i].is_some() { continue; }
        let mut name = src.joint_names[i].trim_start_matches("mixamorig:").to_string();
        let mut found = None;
        while let Some(p) = g_parent.get(&name) {
            if let Some(f) = jidx.get(p).and_then(|j| fits[*j]) { found = Some(f); break; }
            name = p.clone();
        }
        // A leaf follows its parent's transform anchored at the parent's joint.
        fits[i] = Some(found.unwrap_or(Fit::uniform(thigh_mid_src, thigh_mid_dst, m3_ident(), g)));
    }
    let fits: Vec<Fit> = fits.into_iter().map(|f| f.unwrap()).collect();
    if std::env::var_os("OKCHARA_DEBUG").is_some() {
        for n in ["Hips", "Spine2", "Neck", "Head", "LeftArm"] {
            if let Some(i) = jidx.get(n) { let f = fits[*i]; eprintln!("FIT {n} src={:?} dst={:?} rs={:?}", f.src, f.dst, f.rs); }
        }
        for m in &src.meshes {
            let mut hist: HashMap<String, f32> = HashMap::new();
            for v in 0..m.positions.len() { for k in 0..4 { *hist.entry(bare(&src.joint_names[m.joints[v][k] as usize]).to_string()).or_default() += m.weights[v][k]; } }
            let mut h: Vec<_> = hist.into_iter().collect(); h.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
            eprintln!("WEIGHTS {} {:?}", m.name, &h[..h.len().min(8)]);
        }
    }

    // Base body (donor) vertices and weights, in the same space.
    let donor = s.parts.iter().find(|p| p.role == "body" && p.render_visible && p.skel_kind == 1 && !p.weights.is_empty())
        .ok_or("base card has no visible body mesh to transfer weights from")?;

    let mut card = CharaCard { version: VERSION, name: options.name.clone(), bones: Vec::new(), parts: Vec::new(), native: false, body_mask: None, textures: Vec::new() };
    let mut bone_slot: HashMap<String, u16> = HashMap::new();
    let mut slot_of = |name: &str, card: &mut CharaCard| -> Result<u16, String> {
        if let Some(i) = bone_slot.get(name) { return Ok(*i); }
        let bi = *bone_index.get(name).ok_or(format!("base skeleton has no {name}"))?;
        card.bones.push(CharaBone { name: name.to_string(), fit_world: sk.worlds[bi] });
        let i = (card.bones.len() - 1) as u16; bone_slot.insert(name.to_string(), i); Ok(i)
    };
    let skirt = SkirtRig::from_skeleton(sk);
    let mut skirt_preview: Vec<(String, Vec<V3>, Vec<u32>)> = Vec::new();
    let mut shin_segments = Vec::new();
    for side in ["_L", "_R"] {
        let (knee, ankle, toes) = (kpos(&format!("cf_j_leg01{side}"))?, kpos(&format!("cf_j_leg03{side}"))?, kpos(&format!("cf_j_toes{side}"))?);
        shin_segments.push((knee, ankle)); shin_segments.push((ankle, toes));
    }
    let mut report_parts = Vec::new();
    let mut report_hair = serde_json::Value::Null;
    let mut top_cloth: Option<(Vec<V3>, Vec<u32>)> = None;
    let hips_y = kpos("cf_j_hips")?[1];
    for m in &src.meshes {
        let n = m.positions.len();
        let allowed = options.allowed_joints.get(&m.name);
        let follow = |j: usize| -> usize {
            let Some(allowed) = allowed else { return j };
            let mut name = bare(&src.joint_names[j]).to_string();
            loop {
                if allowed.iter().any(|a| a == &name) { return jidx.get(&name).copied().unwrap_or(j); }
                match src.parent.get(&name) { Some(p) if jidx.contains_key(p) => name = p.clone(), _ => return j }
            }
        };
        let mut positions = Vec::with_capacity(n);
        let mut normals = Vec::with_capacity(n);
        for v in 0..n {
            let (mut p, mut nn) = ([0f32; 3], [0f32; 3]);
            let w = m.weights[v]; let sum: f32 = w.iter().sum::<f32>().max(1e-6);
            for k in 0..4 {
                if w[k] <= 0. { continue; }
                let f = &fits[follow(m.joints[v][k] as usize)];
                p = add(p, mul(f.apply(m.positions[v]), w[k] / sum));
                nn = add(nn, mul(m3_vec(&f.normal, m.normals[v]), w[k] / sum));
            }
            positions.push(p); normals.push(norm(nn));
        }
        // Bust size: the front of the chest scaled about each breast's centre bone, fading out over the radius.
        if (options.bust_scale - 1.).abs() > 1e-3 && options.donor_meshes.iter().any(|d| d == &m.name) {
            for side in ["_L", "_R"] {
                let c = kpos(&format!("cf_j_bust02{side}"))?;
                let r = options.bust_radius;
                for p in positions.iter_mut() {
                    let d = len(sub(*p, c));
                    if d >= r || p[2] < c[2] - 0.03 { continue; }
                    let t = 1. - d / r; let w = t * t * (3. - 2. * t);
                    *p = add(c, mul(sub(*p, c), 1. + (options.bust_scale - 1.) * w));
                }
            }
        }
        // Soles below the floor (boots and heels are taller than the base's bare ankle): what lies under
        // the ankle is pressed up to stand on y = 0.
        let mut grounded = 0usize;
        if options.ground {
            let ankle = kpos("cf_j_leg03_L")?[1].min(kpos("cf_j_leg03_R")?[1]);
            let low = positions.iter().map(|p| p[1]).fold(f32::MAX, f32::min);
            if low < 0. && ankle > 0. {
                for p in positions.iter_mut() { if p[1] < ankle { p[1] = ankle * (p[1] - low) / (ankle - low); grounded += 1; } }
            }
        }
        // Weights: the base body's where the surface lies on it, the native skirt chains for a
        // skirt, else the rig's mapped to Koikatsu bones.
        let use_donor = options.donor_meshes.iter().any(|d| d == &m.name);
        let use_skirt = options.skirt_meshes.iter().any(|d| d == &m.name) && skirt.is_some();
        let mut donor_hits = 0usize; let mut skirt_hits = 0usize;
        let mut vw: Vec<Vec<(String, f32)>> = Vec::with_capacity(n);
        // Skirt cloth hangs from the hips; shins, boots and feet (rig: Leg/Foot/Toe) are not skirt.
        let lower_leg = |v: usize| -> bool {
            shin_segments.iter().any(|(a, b)| seg_dist(positions[v], *a, *b) < options.shin_radius)
        };
        let mut is_skirt = vec![false; n];
        for v in 0..n {
            let mut acc: Vec<(String, f32)> = Vec::new();
            let mut push = |name: String, w: f32| { if w <= 0. { return; } if let Some(e) = acc.iter_mut().find(|e| e.0 == name) { e.1 += w; } else { acc.push((name, w)); } };
            let nearest = if use_donor {
                let mut best = (f32::MAX, 0usize);
                for (i, q) in donor.positions.iter().enumerate() { let d = dot(sub(*q, positions[v]), sub(*q, positions[v])); if d < best.0 { best = (d, i); } }
                let lower = positions[v][1] < hips_y;
                let limit = if lower && use_skirt { options.skirt_gap } else { options.donor_distance };
                (best.0.sqrt() <= limit).then_some(best.1)
            } else { None };
            if let Some(i) = nearest {
                donor_hits += 1;
                for k in 0..4 { push(sk.names[donor.bone_idx[i][k] as usize].clone(), donor.weights[i][k]); }
            } else if use_skirt && positions[v][1] < hips_y && !lower_leg(v) {
                is_skirt[v] = true;
                skirt_hits += 1;
                for (name, w) in skirt.as_ref().unwrap().weights(positions[v]) { push(name, w); }
            } else {
                for k in 0..4 {
                    let j = follow(m.joints[v][k] as usize);
                    let name = kk_skin_bone(src.joint_names[j].trim_start_matches("mixamorig:")).ok_or(format!("no Koikatsu bone for {}", src.joint_names[j]))?;
                    push(name, m.weights[v][k]);
                }
            }
            vw.push(acc);
        }
        if use_skirt { smooth_weights(&mut vw, &positions, &m.indices, |v| positions[v][1] < hips_y && !lower_leg(v), options.smooth_iterations); }
        if use_skirt {
            let tris: Vec<u32> = m.indices.chunks(3).filter(|t| t.iter().all(|i| is_skirt[*i as usize])).flatten().copied().collect();
            skirt_preview.push((format!("skirt_{}", m.name), positions.clone(), tris));
        }
        let mut bone_idx = Vec::with_capacity(n); let mut weights = Vec::with_capacity(n);
        for mut acc in vw {
            acc.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
            acc.truncate(4);
            let total: f32 = acc.iter().map(|e| e.1).sum::<f32>().max(1e-6);
            let mut bi = [0u16; 4]; let mut ww = [0f32; 4];
            for (k, (name, w)) in acc.iter().enumerate() { bi[k] = slot_of(name, &mut card)?; ww[k] = w / total; }
            bone_idx.push(bi); weights.push(ww);
        }
        // glTF UVs start at the top of the image, Unity's at the bottom.
        let uvs: Vec<[f32; 2]> = m.uvs.iter().map(|t| [t[0], 1. - t[1]]).collect();
        let tangents = tangents(&positions, &normals, &uvs, &m.indices);
        let texture = match options.texture_overrides.get(&m.name) {
            Some(file) => albedo_png(&fs::read(file).map_err(|e| format!("{file}: {e}"))?, options.texture_size)?,
            None => albedo_png(&m.image, options.texture_size)?,
        };
        let texture_bytes = texture.len();
        card.textures.push(texture);
        let tex_index = (card.textures.len() - 1) as u16;
        let mut positions = positions;
        // Triangle labels: which part each triangle goes to (None: painted skin, dropped).
        let img = image::load_from_memory(&match options.texture_overrides.get(&m.name) { Some(f) => fs::read(f).map_err(|e| e.to_string())?, None => m.image.clone() })
            .map_err(|e| e.to_string())?.to_rgb8();
        let ntri = m.indices.len() / 3;
        let colors: Vec<[u8; 3]> = m.indices.chunks(3).map(|t| tri_color(&img, &m.uvs, t)).collect();
        let tri_centre = |pos: &[V3], t: usize| -> V3 { let i = &m.indices[t * 3..t * 3 + 3]; mul(add(add(pos[i[0] as usize], pos[i[1] as usize]), pos[i[2] as usize]), 1. / 3.) };
        let mut labels: Vec<Option<(&str, i8)>> = vec![Some(("okchara", -1)); ntri];
        let is_clothes = options.native && options.clothes_meshes.iter().any(|c| c == &m.name);
        let is_hair = options.native && options.hair_meshes.iter().any(|c| c == &m.name);
        let mut dropped = 0usize;
        if is_clothes {
            let knee_y = kpos("cf_j_leg01_L")?[1].max(kpos("cf_j_leg01_R")?[1]);
            let thighs: Vec<(V3, V3)> = ["_L", "_R"].iter().map(|sd| Ok((kpos(&format!("cf_j_thigh00{sd}"))?, kpos(&format!("cf_j_leg01{sd}"))?))).collect::<Result<_, String>>()?;
            for t in 0..ntri {
                let c = tri_centre(&positions, t); let col = colors[t];
                let lum = (col[0] as u32 * 3 + col[1] as u32 * 6 + col[2] as u32) / 10;
                labels[t] = if skin_like(col) { None }
                    else if c[1] < knee_y + 0.03 && shin_segments.iter().any(|(a, b)| seg_dist(c, *a, *b) < options.shin_radius + 0.02) { Some(("clothes_shoes_outer", 8)) }
                    else if c[1] < hips_y && lum < 120 && col[0] as i32 > col[2] as i32 + 10 && thighs.iter().any(|(a, b)| seg_dist(c, *a, *b) < 0.1) { Some(("clothes_socks", 6)) }
                    else { Some(("clothes_top", 0)) };
                if labels[t].is_none() { dropped += 1; }
            }
        }
        // Hair: drop the painted face and neck, then the small islands that held the eyes, brows and mouth.
        if is_hair {
            for t in 0..ntri { if skin_like(colors[t]) { labels[t] = None; } }
            let keep: Vec<bool> = labels.iter().map(|l| l.is_some()).collect();
            let kept = keep.iter().filter(|k| **k).count();
            let mut islands = tri_islands(&positions, &m.indices, &keep);
            islands.sort_by_key(|g| std::cmp::Reverse(g.len()));
            let mut removed: Vec<(usize, V3)> = Vec::new();
            if std::env::var_os("OKCHARA_DEBUG").is_some() {
                eprintln!("ISLANDS kept={kept} count={}", islands.len());
                for g in islands.iter().take(40) {
                    let c = g.iter().fold([0f32; 3], |a, t| add(a, tri_centre(&positions, *t)));
                    let col = g.iter().fold([0u32; 3], |a, t| [a[0] + colors[*t][0] as u32, a[1] + colors[*t][1] as u32, a[2] + colors[*t][2] as u32]);
                    let n = g.len() as f32;
                    eprintln!("ISLAND tris={} centre={:?} colour={:?}", g.len(), mul(c, 1. / n), col.map(|v| v / g.len() as u32));
                }
            }
            for g in islands.iter().skip(1) {
                if g.len() * 50 > kept { continue; }
                if g.len() >= 20 {
                    let c = g.iter().fold([0f32; 3], |a, t| add(a, tri_centre(&positions, *t)));
                    removed.push((g.len(), mul(c, 1. / g.len() as f32)));
                }
                for t in g { labels[*t] = None; }
            }
            dropped = labels.iter().filter(|l| l.is_none()).count();
            // The painted eyes: the mirror pair among the removed islands (one each side, level, alike in size).
            let mut best: Option<(f32, V3, V3)> = None;
            for (i, (na, a)) in removed.iter().enumerate() { for (nb, b) in removed.iter().skip(i + 1) {
                if a[0] * b[0] >= 0. { continue; }
                let size = (*na as f32 / *nb as f32).max(*nb as f32 / *na as f32);
                let score = (a[0] + b[0]).abs() + (a[1] - b[1]).abs() + (a[2] - b[2]).abs() * 0.5 + (size - 1.) * 0.02;
                if size < 2.5 && (a[1] - b[1]).abs() < 0.03 && best.map_or(true, |x| score < x.0) { best = Some((score, *a, *b)); }
            } }
            let mut eye_islands: Vec<V3> = best.map(|b| vec![b.1, b.2]).unwrap_or_default();
            // Frame the base face: the painted eyes onto the base eyes (scale by their distance).
            let kk_eye = |name: &str| s.parts.iter().find(|p| p.name == name && !p.positions.is_empty()).map(|p| mul(p.positions.iter().fold([0f32; 3], |a, v| add(a, *v)), 1. / p.positions.len() as f32));
            eye_islands.sort_by(|a, b| a[0].partial_cmp(&b[0]).unwrap());
            if let (2.., Some(l), Some(r)) = (eye_islands.len(), kk_eye("cf_Ohitomi_L"), kk_eye("cf_Ohitomi_R")) {
                let (a, b) = (eye_islands[0], eye_islands[eye_islands.len() - 1]);
                let (ka, kb) = if l[0] < r[0] { (l, r) } else { (r, l) };
                let sc = len(sub(kb, ka)) / len(sub(b, a)).max(1e-4);
                let (from, to) = (mid(a, b), mid(ka, kb));
                // The painted eyes sit on the face surface, the base pupils a little inside it.
                let to = add(to, [0., 0., options.hair_eye_depth]);
                for p in positions.iter_mut() { *p = add(to, mul(sub(*p, from), sc * options.hair_scale)); }
                report_hair = serde_json::json!({"eye_islands": eye_islands.len(), "scale": sc, "from": from, "to": to});
            } else {
                report_hair = serde_json::json!({"eye_islands": eye_islands.len(), "aligned": false});
            }
        }
        report_parts.push(serde_json::json!({"name": m.name, "vertices": n, "triangles": ntri, "dropped_triangles": dropped, "donor_weighted": donor_hits, "skirt_weighted": skirt_hits, "grounded": grounded, "texture_bytes": texture_bytes}));
        let mut groups: Vec<((&str, i8), Vec<usize>)> = Vec::new();
        for t in 0..ntri { if let Some(l) = labels[t] { match groups.iter_mut().find(|g| g.0 == l) { Some(g) => g.1.push(t), None => groups.push((l, vec![t])) } } }
        for ((role, slot), tris) in groups {
            let role = if is_hair { "hair_b" } else { role };
            let (verts, idx) = sub_mesh(&tris, &m.indices);
            let pick = |v: &Vec<V3>| verts.iter().map(|i| v[*i]).collect::<Vec<_>>();
            let name = if role == "okchara" { format!("{PART_PREFIX}{}", m.name) } else { format!("{PART_PREFIX}{}_{role}", m.name) };
            if role == "clothes_top" { top_cloth = Some((pick(&positions), idx.clone())); }
            card.parts.push(CharaPart { name, role: role.into(), slot, positions: pick(&positions), normals: pick(&normals),
                tangents: verts.iter().map(|i| tangents[*i]).collect(), uvs: verts.iter().map(|i| uvs[*i]).collect(), indices: idx,
                bone_idx: verts.iter().map(|i| bone_idx[*i]).collect(), weights: verts.iter().map(|i| weights[*i]).collect(), texture: tex_index });
        }
    }
    card.native = options.native;
    let mut mask_report = serde_json::Value::Null;
    if options.native {
        if let (Some((pos, idx)), Some(body)) = (&top_cloth, s.parts.iter().find(|p| p.role == "body" && p.render_visible && !p.uvs.is_empty())) {
            let (png, covered) = body_mask_png(body, pos, idx, options.mask_size, options.mask_reach)?;
            mask_report = serde_json::json!({"covered_vertices": covered, "body_vertices": body.positions.len(), "png_bytes": png.len()});
            if let Some(obj) = preview_obj { let _ = fs::write(obj.with_extension("mask.png"), &png); }
            card.body_mask = Some(png);
        }
    }
    if let Some(obj) = preview_obj {
        let mut items: Vec<(String, &Vec<[f32; 3]>, &Vec<u32>)> = card.parts.iter().map(|p| (p.name.clone(), &p.positions, &p.indices)).collect();
        items.push(("base_body".into(), &donor.positions, &donor.indices));
        for (name, p, t) in &skirt_preview { items.push((name.clone(), p, t)); }
        write_obj(obj, items.into_iter())?;
    }
    let payload = encode(&card)?;
    let thumb = match &options.thumbnail { Some(t) => Some(fs::read(t).map_err(|e| format!("{t}: {e}"))?), None => None };
    let bytes = card_with_chunk(&base_bytes, &payload, thumb.as_deref())?;
    fs::write(out, &bytes).map_err(|e| e.to_string())?;
    // Read back through the normal open path.
    let check = crate::session::open(lib, Some(out), 0)?;
    let shown: Vec<_> = check.parts.iter().filter(|p| p.render_visible).map(|p| p.name.clone()).collect();
    let ours = shown.iter().filter(|n| n.starts_with(PART_PREFIX)).count();
    if ours != card.parts.len() || (!card.native && ours != shown.len()) { return Err(format!("reopened card shows {shown:?}")); }
    Ok(serde_json::json!({
        "card": out, "bytes": bytes.len(), "okch_bytes": payload.len(), "bones": card.bones.len(), "parts": report_parts,
        "orientation_yaw_degrees": theta.to_degrees(), "cross_section_scale": g, "fitted_segments": fitted_segments,
        "reopened_visible_parts": shown, "hair_alignment": report_hair, "body_mask": mask_report, "base_card": base_path,
    }))
}

/// Painted skin: light, warm, a little red over blue (white cloth and lace are neutral, blonde hair is yellower).
fn skin_like(c: [u8; 3]) -> bool {
    let (r, g, b) = (c[0] as i32, c[1] as i32, c[2] as i32);
    r >= 180 && g >= 150 && r >= g && g >= b - 4 && (r - b) >= 10 && (r - b) <= 60 && (g - b) <= 40
}

/// Mean texel colour of a triangle (its corners and centre), glTF UVs (origin top left).
fn tri_color(img: &image::RgbImage, uvs: &[[f32; 2]], t: &[u32]) -> [u8; 3] {
    let (w, h) = img.dimensions();
    let px = |u: f32, v: f32| { let x = ((u.rem_euclid(1.)) * w as f32) as u32; let y = ((v.rem_euclid(1.)) * h as f32) as u32; img.get_pixel(x.min(w - 1), y.min(h - 1)).0 };
    let c: Vec<[f32; 2]> = t.iter().map(|i| uvs[*i as usize]).collect();
    let centre = [(c[0][0] + c[1][0] + c[2][0]) / 3., (c[0][1] + c[1][1] + c[2][1]) / 3.];
    let mut acc = [0u32; 3];
    for s in [c[0], c[1], c[2], centre, centre] { let p = px(s[0], s[1]); for k in 0..3 { acc[k] += p[k] as u32; } }
    acc.map(|v| (v / 5) as u8)
}

/// Connected groups of triangles (vertices at one position join), each a list of triangle indices.
fn tri_islands(pos: &[V3], idx: &[u32], keep: &[bool]) -> Vec<Vec<usize>> {
    let key = |p: V3| (p[0].to_bits(), p[1].to_bits(), p[2].to_bits());
    let mut weld: HashMap<(u32, u32, u32), usize> = HashMap::new();
    let rep: Vec<usize> = (0..pos.len()).map(|i| *weld.entry(key(pos[i])).or_insert(i)).collect();
    let mut parent: Vec<usize> = (0..pos.len()).collect();
    fn find(p: &mut [usize], x: usize) -> usize { let mut r = x; while p[r] != r { r = p[r]; } let mut y = x; while p[y] != r { let n = p[y]; p[y] = r; y = n; } r }
    for (t, tri) in idx.chunks(3).enumerate() {
        if !keep[t] { continue; }
        let a = find(&mut parent, rep[tri[0] as usize]);
        for k in 1..3 { let b = find(&mut parent, rep[tri[k] as usize]); if a != b { parent[b] = a; } }
    }
    let mut groups: HashMap<usize, Vec<usize>> = HashMap::new();
    for (t, tri) in idx.chunks(3).enumerate() { if keep[t] { let r = find(&mut parent, rep[tri[0] as usize]); groups.entry(r).or_default().push(t); } }
    groups.into_values().collect()
}

/// The triangles of one label as a part of their own (vertices renumbered).
fn sub_mesh(tris: &[usize], idx: &[u32]) -> (Vec<usize>, Vec<u32>) {
    let mut map: HashMap<u32, u32> = HashMap::new(); let mut verts = Vec::new(); let mut out = Vec::new();
    for t in tris { for k in 0..3 { let v = idx[t * 3 + k]; let n = *map.entry(v).or_insert_with(|| { verts.push(v as usize); (verts.len() - 1) as u32 }); out.push(n); } }
    (verts, out)
}

fn ray_tri(o: V3, d: V3, a: V3, b: V3, c: V3) -> Option<f32> {
    let (e1, e2) = (sub(b, a), sub(c, a)); let p = cross(d, e2); let det = dot(e1, p);
    if det.abs() < 1e-12 { return None; }
    let inv = 1. / det; let s = sub(o, a); let u = dot(s, p) * inv; if !(0. ..=1.).contains(&u) { return None; }
    let q = cross(s, e1); let v = dot(d, q) * inv; if v < 0. || u + v > 1. { return None; }
    let t = dot(e2, q) * inv; (t > 0.).then_some(t)
}

/// Body _AlphaMask: red 0 where the top covers the skin. A body vertex is covered when its outward normal
/// meets the cloth within `reach` (a flared skirt hangs far from the thighs) or the cloth passes just inside it.
fn body_mask_png(body: &crate::session::SessionPart, cloth_pos: &[V3], cloth_idx: &[u32], size: u32, reach: f32) -> Result<(Vec<u8>, usize), String> {
    let tris: Vec<[V3; 3]> = cloth_idx.chunks(3).map(|t| [cloth_pos[t[0] as usize], cloth_pos[t[1] as usize], cloth_pos[t[2] as usize]]).collect();
    // Coarse grid over the cloth's triangles for the rays (x/z cells; rays scan the cells they pass).
    let hit = |o: V3, d: V3, max: f32| tris.iter().any(|t| ray_tri(o, d, t[0], t[1], t[2]).is_some_and(|x| x <= max));
    use rayon::prelude::*;
    let covered: Vec<f32> = (0..body.positions.len()).into_par_iter().map(|i| {
        let (p, n) = (body.positions[i], norm(body.normals[i]));
        let out = hit(add(p, mul(n, 0.002)), n, reach);
        let inside = hit(add(p, mul(n, 0.002)), mul(n, -1.), 0.025);
        if out || inside { 1. } else { 0. }
    }).collect();
    let count = covered.iter().filter(|c| **c > 0.5).count();
    let mut img = image::RgbaImage::from_pixel(size, size, image::Rgba([255, 255, 255, 255]));
    for t in body.indices.chunks(3) {
        // Unity UVs (origin bottom left) -> image rows from the top.
        let q: Vec<(f32, f32, f32)> = t.iter().map(|i| { let uv = body.uvs[*i as usize]; (uv[0] * size as f32, (1. - uv[1]) * size as f32, covered[*i as usize]) }).collect();
        raster(&q, size, size, |x, y, b| { let c = b[0] * q[0].2 + b[1] * q[1].2 + b[2] * q[2].2; if c >= 0.5 { img.get_pixel_mut(x, y).0[0] = 0; } });
    }
    // Grow the covered area by two texels so UV seams do not leave skin lines under the cloth.
    for _ in 0..2 {
        let src = img.clone();
        for y in 0..size { for x in 0..size {
            if src.get_pixel(x, y).0[0] == 0 { continue; }
            let near = [(x.wrapping_sub(1), y), (x + 1, y), (x, y.wrapping_sub(1)), (x, y + 1)].iter().any(|(a, b)| *a < size && *b < size && src.get_pixel(*a, *b).0[0] == 0);
            if near { img.get_pixel_mut(x, y).0[0] = 0; }
        } }
    }
    let mut out = Vec::new();
    img.write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png).map_err(|e| e.to_string())?;
    Ok((out, count))
}

fn albedo_png(encoded: &[u8], max_side: u32) -> Result<Vec<u8>, String> {
    let img = image::load_from_memory(encoded).map_err(|e| format!("texture: {e}"))?;
    let img = if img.width().max(img.height()) > max_side { img.resize(max_side, max_side, image::imageops::FilterType::Lanczos3) } else { img };
    let mut out = Vec::new();
    img.to_rgba8().write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png).map_err(|e| e.to_string())?;
    Ok(out)
}

fn tangents(pos: &[V3], nrm: &[V3], uv: &[[f32; 2]], idx: &[u32]) -> Vec<[f32; 4]> {
    let n = pos.len();
    let (mut t, mut b) = (vec![[0f32; 3]; n], vec![[0f32; 3]; n]);
    for tri in idx.chunks(3) {
        let (i0, i1, i2) = (tri[0] as usize, tri[1] as usize, tri[2] as usize);
        let (e1, e2) = (sub(pos[i1], pos[i0]), sub(pos[i2], pos[i0]));
        let (du1, dv1, du2, dv2) = (uv[i1][0] - uv[i0][0], uv[i1][1] - uv[i0][1], uv[i2][0] - uv[i0][0], uv[i2][1] - uv[i0][1]);
        let det = du1 * dv2 - du2 * dv1; if det.abs() < 1e-12 { continue; }
        let r = 1. / det;
        let tt = mul(sub(mul(e1, dv2), mul(e2, dv1)), r); let bb = mul(sub(mul(e2, du1), mul(e1, du2)), r);
        for i in [i0, i1, i2] { t[i] = add(t[i], tt); b[i] = add(b[i], bb); }
    }
    (0..n).map(|i| {
        let tt = norm(sub(t[i], mul(nrm[i], dot(nrm[i], t[i]))));
        let w = if dot(cross(nrm[i], tt), b[i]) < 0. { -1. } else { 1. };
        [tt[0], tt[1], tt[2], w]
    }).collect()
}

fn encode(card: &CharaCard) -> Result<Vec<u8>, String> {
    let raw = bincode::serialize(card).map_err(|e| e.to_string())?;
    let mut out = b"OKCH".to_vec(); out.extend(VERSION.to_le_bytes());
    out.extend(zstd::encode_all(&raw[..], 9).map_err(|e| e.to_string())?);
    Ok(out)
}
pub fn decode(payload: &[u8]) -> Result<CharaCard, String> {
    if payload.len() < 8 || &payload[..4] != b"OKCH" { return Err("not an okCh payload".into()); }
    let v = u32::from_le_bytes(payload[4..8].try_into().unwrap());
    if v != VERSION { return Err(format!("okCh version {v} is not {VERSION}: build the card again")); }
    let raw = zstd::decode_all(&payload[8..]).map_err(|e| e.to_string())?;
    bincode::deserialize(&raw).map_err(|e| e.to_string())
}

fn chunks(png: &[u8]) -> Result<(Vec<(&[u8], &[u8])>, usize), String> {
    if png.len() < 8 || &png[..8] != b"\x89PNG\r\n\x1a\n" { return Err("not a PNG".into()); }
    let mut out = Vec::new(); let mut pos = 8;
    while pos + 12 <= png.len() {
        let l = u32::from_be_bytes(png[pos..pos + 4].try_into().unwrap()) as usize;
        let end = pos.checked_add(12 + l).filter(|e| *e <= png.len()).ok_or("truncated PNG chunk")?;
        let kind = &png[pos + 4..pos + 8];
        if kind == b"IEND" { return Ok((out, pos)); }
        out.push((kind, &png[pos + 8..pos + 8 + l]));
        pos = end;
    }
    Err("PNG without IEND".into())
}
fn put_chunk(out: &mut Vec<u8>, kind: &[u8], data: &[u8]) {
    out.extend((data.len() as u32).to_be_bytes());
    let mut c = kind.to_vec(); c.extend_from_slice(data);
    out.extend(&c); out.extend(crc32fast::hash(&c).to_be_bytes());
}
/// The base card with this okCh chunk (replacing an earlier one), optionally with a new face image.
/// Card data after IEND (the Koikatsu card itself) and the OK chunks stay as they are.
pub fn card_with_chunk(base: &[u8], payload: &[u8], thumbnail: Option<&[u8]>) -> Result<Vec<u8>, String> {
    let (base_chunks, iend) = chunks(base)?;
    let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
    let is_image = |k: &[u8]| matches!(k, b"IHDR" | b"PLTE" | b"IDAT" | b"tRNS" | b"gAMA" | b"cHRM" | b"sRGB" | b"iCCP" | b"sBIT" | b"pHYs" | b"bKGD" | b"acTL" | b"fcTL" | b"fdAT");
    if let Some(t) = thumbnail {
        let (tc, _) = chunks(t)?;
        for (k, d) in tc.iter().filter(|(k, _)| is_image(k)) { put_chunk(&mut out, k, d); }
        for (k, d) in base_chunks.iter().filter(|(k, _)| !is_image(k) && *k != CHUNK) { put_chunk(&mut out, k, d); }
    } else {
        for (k, d) in base_chunks.iter().filter(|(k, _)| *k != CHUNK) { put_chunk(&mut out, k, d); }
    }
    put_chunk(&mut out, CHUNK, payload);
    out.extend_from_slice(&base[iend..]);
    Ok(out)
}

/// Apply a card's okCh chunk to a freshly opened session: hide the base character's
/// renderers and add the authored parts, skinned by the session's body skeleton.
pub fn apply(sess: &mut crate::session::OkSession, card_bytes: &[u8]) -> Result<bool, String> {
    let Some(payload) = crate::oklib::png_chunk(card_bytes, CHUNK) else { return Ok(false) };
    let card = decode(payload)?;
    let sk = sess.body_skel.as_ref().ok_or("okCh card opened without a body skeleton")?;
    let index: HashMap<&str, usize> = sk.names.iter().enumerate().map(|(i, n)| (n.as_str(), i)).collect();
    let mut binds: Vec<Mat4> = vec![identity(); sk.names.len()];
    let mut map = Vec::with_capacity(card.bones.len());
    for b in &card.bones {
        let i = *index.get(b.name.as_str()).ok_or(format!("okCh bone {} missing from the skeleton", b.name))?;
        binds[i] = mat_inv_pub(&b.fit_world); map.push(i as u16);
    }
    let template = sess.parts.iter().find(|p| p.skel_kind == 1 && p.role.starts_with("clothes"))
        .or_else(|| sess.parts.iter().find(|p| p.skel_kind == 1))
        .cloned().ok_or("base session has no body-skinned part to template from")?;
    // Worn state of each clothing slot (0 on, 1/2 half, 3 off) as this session was asked to open.
    let states = crate::unity::requested_clothes_states();
    let worn = |slot: i8| slot < 0 || states.get(slot as usize).map_or(true, |s| *s != 3);
    for p in sess.parts.iter_mut() {
        // A native card keeps the base body and head (face, eyes, brows, mouth, tongue) and drops its hair,
        // accessories and clothes; otherwise every base renderer goes.
        if !(card.native && (p.role == "body" || p.role == "head")) { p.render_visible = false; }
    }
    if card.native {
        let top_on = worn(0);
        for p in sess.parts.iter_mut().filter(|p| p.role == "body" && p.render_visible) {
            match (&card.body_mask, top_on) {
                (Some(mask), true) => {
                    p.alpha_mask = Some(mask.clone()); p.shader_textures.insert("_AlphaMask".into(), mask.clone());
                    p.blend = "masked".into(); p.blend_c = CString::new("masked").unwrap();
                    if let Some(m) = p.source_material.as_mut() { m.floats.insert("_alpha_a".into(), 1.); m.floats.insert("_alpha_b".into(), 1.); }
                }
                _ => { p.alpha_mask = None; p.shader_textures.remove("_AlphaMask"); }
            }
        }
    }
    for cp in &card.parts {
        let mut p = template.clone();
        let n = cp.positions.len();
        p.role = cp.role.clone(); p.role_c = CString::new(p.role.clone()).map_err(|e| e.to_string())?;
        p.name = cp.name.clone(); p.name_c = CString::new(p.name.clone()).map_err(|e| e.to_string())?;
        p.render_visible = worn(cp.slot); p.source_property = None; p.runtime_accessory = None; p.item_draw = None; p.eye_draw = None; p.iris_runtime = None;
        let mut material = crate::unity::MeshMaterial::default();
        material.name = cp.name.clone(); material.shader = "Shader Forge/main_item".into(); material.render_queue = 2000;
        for k in ["_Color", "_Color2", "_Color3"] { material.colors.insert(k.into(), [1.; 4]); }
        material.colors.insert("_ShadowColor".into(), [0.78, 0.74, 0.80, 1.]);
        for (k, v) in [("_MainTex_ST_x", 1.), ("_MainTex_ST_y", 1.), ("_MainTex_ST_z", 0.), ("_MainTex_ST_w", 0.), ("_Glossiness", 0.2)] { material.floats.insert(k.into(), v); }
        p.source_material = Some(material); p.blend = "opaque".into(); p.blend_c = CString::new("opaque").unwrap();
        p.shader_textures.clear(); p.runtime_textures.clear();
        let albedo = card.textures.get(cp.texture as usize).ok_or("okCh part names a missing texture")?;
        p.shader_textures.insert("_MainTex".into(), albedo.clone());
        // The native Forge pass runs in gamma space: feed the encoded albedo without an sRGB decode.
        p.runtime_textures.insert("_MainTex".into(), [1, 0, 0, 0, 1]);
        p.shader_kind = 8; p.unlit = true;
        p.rest_positions = cp.positions.clone(); p.positions = cp.positions.clone();
        p.rest_normals = cp.normals.clone(); p.normals = cp.normals.clone(); p.rest_tangents = cp.tangents.clone();
        p.uvs = cp.uvs.clone(); p.uv2.clear(); p.uv3.clear(); p.uv4.clear(); p.vertex_colors = vec![[255; 4]; n];
        p.indices = cp.indices.clone();
        p.weights = cp.weights.clone();
        p.bone_idx = cp.bone_idx.iter().map(|b| b.map(|k| map[k as usize])).collect();
        p.bind_poses = binds.clone(); p.skel_kind = 1;
        p.parent_bone = None; p.rigid_follow_bone = None; p.parent_c = CString::default(); p.rigid_follow_c = CString::default();
        p.png = Some(albedo.clone()); p.alpha_mask = None; p.hair_gloss = None; p.detail_mask = None; p.line_mask = None;
        p.normal_map = None; p.normal_detail = None; p.normal_mask = None; p.overtex_png = None; p.overtex2_png = None;
        p.overcolor = [1.; 4]; p.overcolor2 = [1.; 4]; p.specular_color = [0.15, 0.15, 0.15, 1.]; p.metallic = 0.; p.smoothness = 0.2;
        p.main_tex_st = [1., 1., 0., 0.]; p.source_outline_enabled = true; p.line_color = [0.25, 0.22, 0.24, 1.];
        p.blend_shapes.clear(); p.morph_idx.clear(); p.morph_dxyz.clear();
        p.mouth_patterns.clear(); p.eye_patterns.clear(); p.eyebrow_patterns.clear(); p.face_baseline_weights.clear();
        sess.parts.push(p);
    }
    sess.skin_all(); sess.skel_export = None;
    Ok(true)
}

/// Open an OK character card, turn a few bones (with their descendants) about their joints and
/// write the skinned authored parts as OBJ: a quick look at how the weights follow motion.
pub fn pose_test(lib: &Path, card: &Path, out_obj: &Path) -> Result<serde_json::Value, String> {
    let mut s = crate::session::open(lib, Some(card), 0)?;
    let turns: [(&str, V3, f32); 5] = [("cf_j_sk_00_00", [1., 0., 0.], -30.), ("cf_j_arm00_L", [0., 0., 1.], 60.), ("cf_j_arm00_R", [0., 0., 1.], -35.), ("cf_j_thigh00_R", [1., 0., 0.], -45.), ("cf_j_head", [0., 1., 0.], 25.)];
    {
        let sk = s.body_skel.as_mut().ok_or("no body skeleton")?;
        let index: HashMap<i64, usize> = sk.bone_ids.iter().enumerate().map(|(i, id)| (*id, i)).collect();
        let parent: Vec<Option<usize>> = (0..sk.names.len()).map(|i| sk.bone_ids.get(i).and_then(|id| sk.tfs.get(id)).and_then(|t| t.parent).and_then(|p| index.get(&p).copied())).collect();
        for (bone, axis, deg) in turns {
            let b = sk.names.iter().position(|n| n == bone).ok_or(format!("no {bone}"))?;
            let w = sk.worlds[b]; let pivot = [w[0][3], w[1][3], w[2][3]];
            let (sn, c) = deg.to_radians().sin_cos(); let a = norm(axis);
            let r: M3 = std::array::from_fn(|i| std::array::from_fn(|j| {
                let k: M3 = [[0., -a[2], a[1]], [a[2], 0., -a[0]], [-a[1], a[0], 0.]];
                (if i == j { 1. } else { 0. }) + sn * k[i][j] + (1. - c) * (0..3).map(|m| k[i][m] * k[m][j]).sum::<f32>()
            }));
            let mut t: Mat4 = identity();
            for i in 0..3 { for j in 0..3 { t[i][j] = r[i][j]; } t[i][3] = pivot[i] - (0..3).map(|j| r[i][j] * pivot[j]).sum::<f32>(); }
            for i in 0..sk.names.len() {
                let mut q = Some(i); let mut under = false;
                while let Some(x) = q { if x == b { under = true; break; } q = parent[x]; }
                if under { sk.worlds[i] = mat_mul_pub(&t, &sk.worlds[i]); }
            }
        }
    }
    s.skin_all();
    write_obj(out_obj, s.parts.iter().filter(|p| p.render_visible).map(|p| (p.name.clone(), &p.positions, &p.indices)))?;
    Ok(serde_json::json!({"obj": out_obj, "turned": turns.iter().map(|t| t.0).collect::<Vec<_>>()}))
}

#[derive(Deserialize)]
pub struct ProjectOptions {
    /// Source mesh (node name) whose albedo is repainted.
    pub mesh: String,
    /// Reference view image (part image on a plain background).
    pub image: String,
    /// "back" or "front" (orthographic, along the glTF Z axis).
    pub view: String,
    /// Only texels at most this bright (luma 0..1) are repainted; 1 repaints all.
    #[serde(default = "one")] pub max_luma: f32,
    /// Blend strength 0..1.
    #[serde(default = "one")] pub strength: f32,
    /// Reference pixels more saturated than this (0..1) are not painted (e.g. hair over a dark veil).
    #[serde(default = "one")] pub max_ref_saturation: f32,
    /// Reference pixels brighter than this are not painted (e.g. white lace above the mesh hem).
    #[serde(default = "one")] pub max_ref_luma: f32,
    pub out: String,
}
fn one() -> f32 { 1. }

/// Paint a reference view onto a mesh's albedo: texels that face the view, are visible in it
/// and pass the brightness filter take the reference colour (tone-matched to the texels they replace).
pub fn project_texture(glb: &Path, o: &ProjectOptions) -> Result<serde_json::Value, String> {
    let src = read_glb(glb)?;
    let m = src.meshes.iter().find(|m| m.name == o.mesh).ok_or(format!("no mesh {}", o.mesh))?;
    let back = match o.view.as_str() { "back" => true, "front" => false, v => return Err(format!("unknown view {v}")) };
    // Image plane: u to the right of the image, v down; depth towards the camera is smaller.
    let proj = |p: V3| -> (f32, f32, f32) { if back { (-p[0], -p[1], p[2]) } else { (p[0], -p[1], -p[2]) } };
    let facing = |n: V3| -> f32 { if back { -n[2] } else { n[2] } };
    let reference = image::open(&o.image).map_err(|e| format!("{}: {e}", o.image))?.to_rgb8();
    let (rw, rh) = reference.dimensions();
    // Foreground box of the reference (pixels away from the corner background colour).
    let bg = reference.get_pixel(2, 2).0;
    let fg = |x: u32, y: u32| { let p = reference.get_pixel(x, y).0; (0..3).map(|i| (p[i] as i32 - bg[i] as i32).abs()).max().unwrap() > 24 };
    let (mut x0, mut y0, mut x1, mut y1) = (rw, rh, 0, 0);
    for y in 0..rh { for x in 0..rw { if fg(x, y) { x0 = x0.min(x); y0 = y0.min(y); x1 = x1.max(x); y1 = y1.max(y); } } }
    if x1 <= x0 || y1 <= y0 { return Err("reference image has no foreground".into()); }
    let pts: Vec<(f32, f32, f32)> = m.positions.iter().map(|p| proj(*p)).collect();
    let (mut u0, mut v0, mut u1, mut v1) = (f32::MAX, f32::MAX, f32::MIN, f32::MIN);
    for (u, v, _) in &pts { u0 = u0.min(*u); v0 = v0.min(*v); u1 = u1.max(*u); v1 = v1.max(*v); }
    // The silhouette boxes are matched in width and height separately: generated views are not exact in proportion.
    let s = (y1 - y0) as f32 / (v1 - v0);
    let sx = (x1 - x0) as f32 / (u1 - u0);
    let to_img = |u: f32, v: f32| -> (f32, f32) { (x0 as f32 + (u - u0) * sx, y0 as f32 + (v - v0) * s) };
    // Depth buffer at reference resolution.
    let mut depth = vec![f32::MAX; (rw * rh) as usize];
    for t in m.indices.chunks(3) {
        let q: Vec<(f32, f32, f32)> = t.iter().map(|i| { let (u, v, d) = pts[*i as usize]; let (x, y) = to_img(u, v); (x, y, d) }).collect();
        raster(&q, rw, rh, |x, y, b| { let d = b[0] * q[0].2 + b[1] * q[1].2 + b[2] * q[2].2; let k = (y * rw + x) as usize; if d < depth[k] { depth[k] = d; } });
    }
    let diag = (((v1 - v0) * (v1 - v0) + (u1 - u0) * (u1 - u0)).sqrt()) * 0.004;
    let mut tex = image::load_from_memory(&m.image).map_err(|e| e.to_string())?.to_rgb8();
    let (tw, th) = tex.dimensions();
    // Pass 1: collect target texels and reference colours.
    let mut hits: Vec<(u32, u32, [f32; 3], f32)> = Vec::new();
    let mut seen = vec![false; (tw * th) as usize];
    for t in m.indices.chunks(3) {
        let i = [t[0] as usize, t[1] as usize, t[2] as usize];
        let q: Vec<(f32, f32, f32)> = i.iter().map(|k| (m.uvs[*k][0] * tw as f32, m.uvs[*k][1] * th as f32, 0.)).collect();
        raster(&q, tw, th, |x, y, b| {
            let k = (y * tw + x) as usize; if seen[k] { return; }
            let p = add(add(mul(m.positions[i[0]], b[0]), mul(m.positions[i[1]], b[1])), mul(m.positions[i[2]], b[2]));
            let n = norm(add(add(mul(m.normals[i[0]], b[0]), mul(m.normals[i[1]], b[1])), mul(m.normals[i[2]], b[2])));
            let f = facing(n); if f < 0.25 { return; }
            let (u, v, d) = proj(p); let (ix, iy) = to_img(u, v);
            if ix < 0. || iy < 0. || ix >= rw as f32 - 1. || iy >= rh as f32 - 1. { return; }
            let (px, py) = (ix as u32, iy as u32);
            if d > depth[(py * rw + px) as usize] + diag || !fg(px, py) { return; }
            let old = tex.get_pixel(x, y).0;
            if (0.299 * old[0] as f32 + 0.587 * old[1] as f32 + 0.114 * old[2] as f32) / 255. > o.max_luma { return; }
            let r = reference.get_pixel(px, py).0;
            let (hi, lo) = (r.iter().max().copied().unwrap() as f32, r.iter().min().copied().unwrap() as f32);
            if hi > 0. && (hi - lo) / hi > o.max_ref_saturation { return; }
            if (0.299 * r[0] as f32 + 0.587 * r[1] as f32 + 0.114 * r[2] as f32) / 255. > o.max_ref_luma { return; }
            seen[k] = true;
            hits.push((x, y, [r[0] as f32, r[1] as f32, r[2] as f32], ((f - 0.25) / 0.35).clamp(0., 1.)));
        });
    }
    if hits.is_empty() { return Err("no texel faces the view".into()); }
    // Tone match: reference colours to the mean/std of the texels they replace.
    let stats = |vals: &mut dyn Iterator<Item = [f32; 3]>| { let (mut s, mut s2, mut n) = ([0f32; 3], [0f32; 3], 0f32); for c in vals { for i in 0..3 { s[i] += c[i]; s2[i] += c[i] * c[i]; } n += 1.; } let m: V3 = std::array::from_fn(|i| s[i] / n); let sd: V3 = std::array::from_fn(|i| (s2[i] / n - m[i] * m[i]).max(1.).sqrt()); (m, sd) };
    let (rm, rs) = stats(&mut hits.iter().map(|h| h.2));
    let (om, os) = stats(&mut hits.iter().map(|h| { let p = tex.get_pixel(h.0, h.1).0; [p[0] as f32, p[1] as f32, p[2] as f32] }));
    for (x, y, r, w) in &hits {
        let old = tex.get_pixel(*x, *y).0;
        let mut c = [0u8; 3];
        for i in 0..3 {
            let toned = om[i] + (r[i] - rm[i]) * (os[i] / rs[i]).clamp(0.5, 2.);
            c[i] = (old[i] as f32 + (toned - old[i] as f32) * w * o.strength).round().clamp(0., 255.) as u8;
        }
        tex.put_pixel(*x, *y, image::Rgb(c));
    }
    tex.save(&o.out).map_err(|e| format!("{}: {e}", o.out))?;
    Ok(serde_json::json!({"out": o.out, "texels": hits.len(), "reference_box": [x0, y0, x1, y1], "scale_px_per_unit": s}))
}

/// Rasterise a triangle given in pixel coordinates; calls f(x, y, barycentric) for covered pixel centres.
fn raster(q: &[(f32, f32, f32)], w: u32, h: u32, mut f: impl FnMut(u32, u32, [f32; 3])) {
    let (ax, ay, bx, by, cx, cy) = (q[0].0, q[0].1, q[1].0, q[1].1, q[2].0, q[2].1);
    let area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
    if area.abs() < 1e-9 { return; }
    let minx = ax.min(bx).min(cx).floor().max(0.) as i64; let maxx = (ax.max(bx).max(cx).ceil() as i64).min(w as i64 - 1);
    let miny = ay.min(by).min(cy).floor().max(0.) as i64; let maxy = (ay.max(by).max(cy).ceil() as i64).min(h as i64 - 1);
    for y in miny..=maxy { for x in minx..=maxx {
        let (px, py) = (x as f32 + 0.5, y as f32 + 0.5);
        let w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area;
        let w1 = ((cx - px) * (ay - py) - (cy - py) * (ax - px)) / area;
        let w2 = 1. - w0 - w1;
        if w0 >= -1e-4 && w1 >= -1e-4 && w2 >= -1e-4 { f(x as u32, y as u32, [w0, w1, w2]); }
    } }
}

fn identity() -> Mat4 { [[1., 0., 0., 0.], [0., 1., 0., 0.], [0., 0., 1., 0.], [0., 0., 0., 1.]] }

#[allow(dead_code)]
fn _unused2(a: &Mat4, b: &Mat4) -> Mat4 { mat_mul_pub(a, b) }

#[cfg(test)]
mod tests {
    use super::*;
    #[test] fn segment_fit_maps_joints_and_keeps_cross_section() {
        let f = Fit::segment([0., 0., 0.], [0., 1., 0.], [1., 0., 0.], [3., 0., 0.], 0.5);
        let e = f.apply([0., 1., 0.]); assert!((e[0] - 3.).abs() < 1e-5 && e[1].abs() < 1e-5);
        // A point 1 unit off the bone axis lands 0.5 off the target axis.
        let side = f.apply([0., 0., 1.]); assert!((len(sub(side, [1., 0., 0.])) - 0.5).abs() < 1e-5);
    }
    #[test] fn skin_bone_names() {
        assert_eq!(kk_skin_bone("LeftForeArm").as_deref(), Some("cf_j_forearm01_L"));
        assert_eq!(kk_skin_bone("RightHandPinky2").as_deref(), Some("cf_j_little02_R"));
        assert_eq!(kk_skin_bone("Spine1").as_deref(), Some("cf_s_spine02"));
        assert_eq!(kk_skin_bone("LeftHandThumb4").as_deref(), Some("cf_j_thumb03_L"));
    }
    #[test] fn chunk_roundtrip_and_replace() {
        let mut png = b"\x89PNG\r\n\x1a\n".to_vec(); put_chunk(&mut png, b"IHDR", &[0; 13]); put_chunk(&mut png, b"IEND", &[]); png.extend(b"KKDATA");
        let card = CharaCard { version: VERSION, name: "t".into(), bones: vec![], parts: vec![], native: true, body_mask: None, textures: vec![] };
        let a = card_with_chunk(&png, &encode(&card).unwrap(), None).unwrap();
        let b = card_with_chunk(&a, &encode(&card).unwrap(), None).unwrap();
        assert_eq!(a, b); assert!(b.ends_with(b"IEND\xaeB`\x82KKDATA"));
        assert_eq!(decode(crate::oklib::png_chunk(&b, CHUNK).unwrap()).unwrap().name, "t");
    }
}

/// The base card's editable fields (path = value), for choosing `card_edits`.
pub fn card_fields(card: &Path) -> Result<serde_json::Value, String> {
    let bytes = fs::read(card).map_err(|e| e.to_string())?;
    let fields = crate::appearance::list_paths(&bytes, 0)?;
    Ok(serde_json::Value::Object(fields.into_iter().map(|(k, v)| (k, serde_json::Value::String(v))).collect()))
}
