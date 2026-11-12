//! MHR body model (Meta Momentum Human Rig, `assets/mhr_model.pt` of SAM 3D Body) and SAM 3D
//! Body's `MHRHead`, reduced to what the decoder needs: the first 70 keypoints. Only the 468
//! vertices and 50 joints those keypoints read are skinned, so the pose correctives (a
//! 55317×3000 linear layer) shrink to 1404 rows. Line for line with the TorchScript code in
//! mhr_model.pt (pymomentum character.py / skel_state.py / quaternion.py / mhr.py) and
//! sam_3d_body/models/heads/mhr_head.py + modules/mhr_utils.py.
//!
//! Skeleton states are [tx, ty, tz, qx, qy, qz, qw, s] like pymomentum.

use candle_core::{DType, Device, Tensor};
use std::collections::HashMap;
use std::path::Path;

type R<T> = Result<T, String>;
fn e<E: std::fmt::Display>(x: E) -> String { x.to_string() }

pub const NJ: usize = 127;
const NV: usize = 18439;
pub const NKP: usize = 70;
const NPOSE: usize = 519;
const BODY_CONT: usize = 260;
const POSE_FEAT: usize = 750; // joints 2..127 × 6 (`joint_parameters.reshape(B,-1,7)[:, 2:, 3:6]`)
const HIDDEN: usize = 3000;

type V3 = [f64; 3];
type Qt = [f64; 4]; // x y z w

// ---------------------------------------------------------------- quaternions (pymomentum)

fn qnorm(q: Qt) -> Qt {
    let n = (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]).sqrt().max(1e-12);
    [q[0] / n, q[1] / n, q[2] / n, q[3] / n]
}
fn qmul(a: Qt, b: Qt) -> Qt {
    let [x1, y1, z1, w1] = a;
    let [x2, y2, z2, w2] = b;
    [
        w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2,
        w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
        w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2,
        w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2,
    ]
}
fn cross(a: V3, b: V3) -> V3 { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
/// rotate_vector_assume_normalized
fn qrot(q: Qt, v: V3) -> V3 {
    let axis = [q[0], q[1], q[2]];
    let av = cross(axis, v);
    let aav = cross(axis, av);
    [v[0] + 2. * (av[0] * q[3] + aav[0]), v[1] + 2. * (av[1] * q[3] + aav[1]), v[2] + 2. * (av[2] * q[3] + aav[2])]
}
fn euler_xyz_q(r: V3) -> Qt {
    let (roll, pitch, yaw) = (r[0], r[1], r[2]);
    let (cy, sy) = ((yaw * 0.5).cos(), (yaw * 0.5).sin());
    let (cp, sp) = ((pitch * 0.5).cos(), (pitch * 0.5).sin());
    let (cr, sr) = ((roll * 0.5).cos(), (roll * 0.5).sin());
    [sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy, cr * cp * sy - sr * sp * cy, cr * cp * cy + sr * sp * sy]
}

#[derive(Clone, Copy)]
struct Skel {
    t: V3,
    q: Qt,
    s: f64,
}
impl Skel {
    /// skel_state.multiply (both rotations normalized first)
    fn mul(&self, o: &Skel) -> Skel {
        let q1 = qnorm(self.q);
        let r = qrot(q1, o.t);
        Skel { t: [self.t[0] + self.s * r[0], self.t[1] + self.s * r[1], self.t[2] + self.s * r[2]], q: qmul(q1, qnorm(o.q)), s: self.s * o.s }
    }
    /// skel_state.transform_points
    fn apply(&self, p: V3) -> V3 {
        let r = qrot(qnorm(self.q), [p[0] * self.s, p[1] * self.s, p[2] * self.s]);
        [self.t[0] + r[0], self.t[1] + r[1], self.t[2] + r[2]]
    }
}

// ---------------------------------------------------------------- rotations (mhr_utils / roma)

type M3 = [[f64; 3]; 3];
fn normalize(a: V3) -> V3 {
    let n = (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt().max(1e-12);
    [a[0] / n, a[1] / n, a[2] / n]
}
/// batchXYZfrom6D: columns x, y, z of the matrix, then XYZ euler angles.
fn xyz_from_6d(p: &[f64]) -> V3 {
    let x = normalize([p[0], p[1], p[2]]);
    let z = normalize(cross(x, [p[3], p[4], p[5]]));
    let y = cross(z, x);
    // matrix[r][c] = column c, row r
    let sy = (x[0] * x[0] + x[1] * x[1]).sqrt();
    if sy < 1e-6 {
        [(-z[1]).atan2(y[1]), (-x[2]).atan2(sy), 0.]
    } else {
        [y[2].atan2(z[2]), (-x[2]).atan2(sy), x[1].atan2(x[0])]
    }
}
/// batch6DFromXYZ: first two columns of Rz·Ry·Rx (per the explicit formula in mhr_utils).
fn six_d_from_xyz(r: V3) -> [f64; 6] {
    let (cx, cy, cz) = (r[0].cos(), r[1].cos(), r[2].cos());
    let (sx, sy, sz) = (r[0].sin(), r[1].sin(), r[2].sin());
    [cy * cz, cy * sz, -sy, -cx * sz + sx * sy * cz, cx * cz + sx * sy * sz, sx * cy]
}
/// geometry_utils.rot6d_to_rotmat: Gram-Schmidt on (x0,x1,x2) and (x3,x4,x5) as columns.
fn rot6d_to_rotmat(x: &[f64]) -> M3 {
    let a1 = [x[0], x[1], x[2]];
    let a2 = [x[3], x[4], x[5]];
    let b1 = normalize(a1);
    let d = b1[0] * a2[0] + b1[1] * a2[1] + b1[2] * a2[2];
    let b2 = normalize([a2[0] - d * b1[0], a2[1] - d * b1[1], a2[2] - d * b1[2]]);
    let b3 = cross(b1, b2);
    [[b1[0], b2[0], b3[0]], [b1[1], b2[1], b3[1]], [b1[2], b2[2], b3[2]]]
}
/// R = Rz(c)·Ry(b)·Rx(a) → (a, b, c). roma's "xyz" returns [a, b, c], "ZYX" returns [c, b, a].
fn zyx_angles(m: &M3) -> V3 {
    let b = (-m[2][0]).clamp(-1., 1.).asin();
    [m[2][1].atan2(m[2][2]), b, m[1][0].atan2(m[0][0])]
}
fn rz_ry_rx(a: f64, b: f64, c: f64) -> M3 {
    let (ca, sa, cb, sb, cc, sc) = (a.cos(), a.sin(), b.cos(), b.sin(), c.cos(), c.sin());
    [
        [cc * cb, cc * sb * sa - sc * ca, cc * sb * ca + sc * sa],
        [sc * cb, sc * sb * sa + cc * ca, sc * sb * ca - cc * sa],
        [-sb, cb * sa, cb * ca],
    ]
}
fn mm(a: &M3, b: &M3) -> M3 {
    let mut r = [[0.; 3]; 3];
    for i in 0..3 {
        for j in 0..3 {
            r[i][j] = (0..3).map(|k| a[i][k] * b[k][j]).sum();
        }
    }
    r
}
fn mv(a: &M3, v: V3) -> V3 { [0, 1, 2].map(|i| a[i][0] * v[0] + a[i][1] * v[1] + a[i][2] * v[2]) }

// fmt tables from mhr_utils.compact_cont_to_model_params_body
const BODY_3DOF: [[usize; 3]; 23] = [
    [0, 2, 4], [6, 8, 10], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23], [24, 25, 26], [27, 28, 29], [34, 35, 36], [37, 38, 39],
    [44, 45, 46], [53, 54, 55], [64, 65, 66], [85, 69, 73], [86, 70, 79], [87, 71, 82], [88, 72, 76], [91, 92, 93], [112, 96, 100],
    [113, 97, 106], [114, 98, 109], [115, 99, 103], [130, 131, 132],
];
const BODY_1DOF: [usize; 58] = [
    1, 3, 5, 7, 9, 11, 30, 31, 32, 33, 40, 41, 42, 43, 47, 48, 49, 50, 51, 52, 56, 57, 58, 59, 60, 61, 62, 63, 67, 68, 74, 75, 77, 78, 80, 81, 83,
    84, 89, 90, 94, 95, 101, 102, 104, 105, 107, 108, 110, 111, 116, 117, 118, 119, 120, 121, 122, 123,
];
const BODY_TRANS: [usize; 6] = [124, 125, 126, 127, 128, 129];
const HAND_PARAM_IDXS: std::ops::RangeInclusive<usize> = 62..=115;
const HAND_DOFS: [usize; 16] = [3, 1, 1, 3, 1, 1, 3, 1, 1, 3, 1, 1, 2, 3, 1, 1];

fn body_params(cont: &[f64]) -> [f64; 133] {
    let mut p = [0.; 133];
    for (g, idx) in BODY_3DOF.iter().enumerate() {
        let a = xyz_from_6d(&cont[g * 6..g * 6 + 6]);
        for k in 0..3 {
            p[idx[k]] = a[k];
        }
    }
    let o = 23 * 6;
    for (i, &idx) in BODY_1DOF.iter().enumerate() {
        p[idx] = cont[o + 2 * i].atan2(cont[o + 2 * i + 1]);
    }
    let o = o + 58 * 2;
    for (i, &idx) in BODY_TRANS.iter().enumerate() {
        p[idx] = cont[o + i];
    }
    p
}
fn hand_params(cont: &[f64]) -> [f64; 27] {
    let mut p = [0.; 27];
    let (mut c, mut q) = (0, 0);
    for &k in &HAND_DOFS {
        if k == 3 {
            let a = xyz_from_6d(&cont[c..c + 6]);
            p[q..q + 3].copy_from_slice(&a);
        } else {
            for i in 0..k {
                p[q + i] = cont[c + 2 * i].atan2(cont[c + 2 * i + 1]);
            }
        }
        c += 2 * k;
        q += k;
    }
    p
}

// ---------------------------------------------------------------- loading

fn st_f64(st: &safetensors::SafeTensors, name: &str) -> R<(Vec<f64>, Vec<usize>)> {
    let t = st.tensor(name).map_err(|x| format!("MHR 權重缺少 {name}：{x}"))?;
    let d = t.data();
    let v: Vec<f64> = match t.dtype() {
        safetensors::Dtype::F32 => d.chunks_exact(4).map(|c| f32::from_le_bytes(c.try_into().unwrap()) as f64).collect(),
        safetensors::Dtype::F64 => d.chunks_exact(8).map(|c| f64::from_le_bytes(c.try_into().unwrap())).collect(),
        safetensors::Dtype::BF16 => d.chunks_exact(2).map(|c| half::bf16::from_le_bytes([c[0], c[1]]).to_f64()).collect(),
        safetensors::Dtype::I64 => d.chunks_exact(8).map(|c| i64::from_le_bytes(c.try_into().unwrap()) as f64).collect(),
        safetensors::Dtype::I32 => d.chunks_exact(4).map(|c| i32::from_le_bytes(c.try_into().unwrap()) as f64).collect(),
        safetensors::Dtype::U8 => d.iter().map(|&c| c as f64).collect(),
        x => return Err(format!("MHR 權重 {name} 的型別 {x:?} 不支援")),
    };
    Ok((v, t.shape().to_vec()))
}

/// The MHR rig, restricted to the keypoint subset.
pub struct Rig {
    verts: Vec<usize>,
    joints: Vec<usize>,
    base: Vec<V3>,
    /// shape_vectors[n][needed vertex]
    shape_vec: Vec<Vec<V3>>,
    pt: Vec<f64>, // 889 × 249
    t_off: Vec<V3>,
    prerot: Vec<Qt>,
    pmi: Vec<(usize, usize)>, // (source, target=parent)
    inv_bind: Vec<Skel>,
    /// per needed vertex: (joint, weight)
    skin: Vec<Vec<(usize, f64)>>,
    sp: Vec<(usize, usize, f64)>, // (row, col, w) of the 3000×756 sparse layer
    corr_w: Tensor,               // (3·nv, 3000) on the device
    dev: Device,
}

/// SAM's `MHRHead` buffers (head_pose.* or head_pose_hand.*).
pub struct Head {
    hand_model: bool,
    scale_mean: Vec<f64>,
    scale_comps: Vec<f64>, // 28 × 68
    hand_pose_mean: Vec<f64>,
    hand_pose_comps: Vec<f64>, // 54 × 54
    hand_idx_l: Vec<usize>,
    hand_idx_r: Vec<usize>,
    /// keypoint_mapping[:70] restricted to [needed verts; needed joints]
    km: Vec<Vec<f64>>,
    right_wrist: V3,
    root: V3,
    local_to_world_wrist: M3,
    nonhand: Vec<usize>,
}

impl Rig {
    /// `mhr`: converted mhr_model.pt; `keypoint_mapping`: head_pose.keypoint_mapping (308 × (18439+127)).
    pub fn load(mhr: &Path, keypoint_mapping: &[f64], dev: &Device) -> R<Rig> {
        let bytes = std::fs::read(mhr).map_err(|x| format!("{}：{x}", mhr.display()))?;
        let st = safetensors::SafeTensors::deserialize(&bytes).map_err(|x| format!("{}：{x}", mhr.display()))?;
        let cols = NV + NJ;
        let mut verts = Vec::new();
        let mut joints = Vec::new();
        for c in 0..cols {
            if (0..NKP).any(|r| keypoint_mapping[r * cols + c] != 0.) {
                if c < NV { verts.push(c) } else { joints.push(c - NV) }
            }
        }
        let (base_all, _) = st_f64(&st, "character_torch.blend_shape.base_shape")?;
        let (sv_all, sv_shape) = st_f64(&st, "character_torch.blend_shape.shape_vectors")?;
        let nshape = sv_shape[0];
        let base: Vec<V3> = verts.iter().map(|&v| [base_all[v * 3], base_all[v * 3 + 1], base_all[v * 3 + 2]]).collect();
        let shape_vec: Vec<Vec<V3>> = (0..nshape)
            .map(|n| verts.iter().map(|&v| { let o = (n * NV + v) * 3; [sv_all[o], sv_all[o + 1], sv_all[o + 2]] }).collect())
            .collect();
        let (pt, pt_shape) = st_f64(&st, "character_torch.parameter_transform.parameter_transform")?;
        if pt_shape != [NJ * 7, 249] {
            return Err(format!("MHR parameter_transform 形狀 {pt_shape:?}"));
        }
        let (to, _) = st_f64(&st, "character_torch.skeleton.joint_translation_offsets")?;
        let (pr, _) = st_f64(&st, "character_torch.skeleton.joint_prerotations")?;
        let (pmi, pmi_shape) = st_f64(&st, "character_torch.skeleton.pmi")?;
        let np = pmi_shape[1];
        let (ib, _) = st_f64(&st, "character_torch.linear_blend_skinning.inverse_bind_pose")?;
        let (si, _) = st_f64(&st, "character_torch.linear_blend_skinning.skin_indices_flattened")?;
        let (sw, _) = st_f64(&st, "character_torch.linear_blend_skinning.skin_weights_flattened")?;
        let (vi, _) = st_f64(&st, "character_torch.linear_blend_skinning.vert_indices_flattened")?;
        let slot: HashMap<usize, usize> = verts.iter().enumerate().map(|(i, &v)| (v, i)).collect();
        let mut skin = vec![Vec::new(); verts.len()];
        for k in 0..vi.len() {
            if let Some(&i) = slot.get(&(vi[k] as usize)) {
                skin[i].push((si[k] as usize, sw[k]));
            }
        }
        let (spi, _) = st_f64(&st, "pose_correctives_model.pose_dirs_predictor.0.sparse_indices")?;
        let (spw, _) = st_f64(&st, "pose_correctives_model.pose_dirs_predictor.0.sparse_weight")?;
        let nnz = spw.len();
        let sp: Vec<(usize, usize, f64)> = (0..nnz).map(|k| (spi[k] as usize, spi[nnz + k] as usize, spw[k])).collect();
        if sp.iter().any(|&(r, c, _)| r >= HIDDEN || c >= POSE_FEAT) {
            return Err("MHR pose correctives 稀疏層的索引超出 3000×750".into());
        }
        // Dense rows of the second layer for the needed vertices only.
        let w2 = st.tensor("pose_correctives_model.pose_dirs_predictor.2.weight").map_err(e)?;
        if w2.shape() != [NV * 3, HIDDEN] || w2.dtype() != safetensors::Dtype::F32 {
            return Err(format!("MHR pose correctives 形狀 {:?}", w2.shape()));
        }
        let d = w2.data();
        let mut rows = Vec::with_capacity(verts.len() * 3 * HIDDEN);
        for &v in &verts {
            for c in 0..3 {
                let o = (v * 3 + c) * HIDDEN * 4;
                rows.extend(d[o..o + HIDDEN * 4].chunks_exact(4).map(|b| f32::from_le_bytes(b.try_into().unwrap())));
            }
        }
        let corr_w = Tensor::from_vec(rows, (verts.len() * 3, HIDDEN), dev).map_err(e)?;
        Ok(Rig {
            base,
            shape_vec,
            pt,
            t_off: (0..NJ).map(|j| [to[j * 3], to[j * 3 + 1], to[j * 3 + 2]]).collect(),
            prerot: (0..NJ).map(|j| [pr[j * 4], pr[j * 4 + 1], pr[j * 4 + 2], pr[j * 4 + 3]]).collect(),
            pmi: (0..np).map(|k| (pmi[k] as usize, pmi[np + k] as usize)).collect(),
            inv_bind: (0..NJ).map(|j| { let b = &ib[j * 8..j * 8 + 8]; Skel { t: [b[0], b[1], b[2]], q: [b[3], b[4], b[5], b[6]], s: b[7] } }).collect(),
            skin,
            sp,
            corr_w,
            verts,
            joints,
            dev: dev.clone(),
        })
    }

    /// Joint parameters (889) and global skeleton states for model parameters (204).
    fn skeleton(&self, model_params: &[f64]) -> (Vec<f64>, Vec<Skel>) {
        let mut jp = vec![0.; NJ * 7];
        for (d, out) in jp.iter_mut().enumerate() {
            let row = &self.pt[d * 249..d * 249 + model_params.len()];
            *out = row.iter().zip(model_params).map(|(a, b)| a * b).sum();
        }
        let mut g: Vec<Skel> = (0..NJ)
            .map(|j| {
                let p = &jp[j * 7..j * 7 + 7];
                Skel {
                    t: [p[0] + self.t_off[j][0], p[1] + self.t_off[j][1], p[2] + self.t_off[j][2]],
                    q: qmul(self.prerot[j], euler_xyz_q([p[3], p[4], p[5]])),
                    s: (p[6] * std::f64::consts::LN_2).exp(),
                }
            })
            .collect();
        for &(src, tgt) in &self.pmi {
            g[src] = g[tgt].mul(&g[src]);
        }
        (jp, g)
    }

    /// Pose-corrective MLP input: 6D of the euler angles of joints 2.., minus the identity's 1s.
    fn pose_features(jp: &[f64]) -> Vec<f32> {
        let mut f = Vec::with_capacity(POSE_FEAT);
        for j in 2..NJ {
            let mut s = six_d_from_xyz([jp[j * 7 + 3], jp[j * 7 + 4], jp[j * 7 + 5]]);
            s[0] -= 1.;
            s[4] -= 1.;
            f.extend(s.iter().map(|v| *v as f32));
        }
        f
    }

    /// Batched MHR forward → (needed vertices, needed joints) in metres (before the y/z flip).
    /// `shape`: 45 identity coefficients; `model`: 204 model parameters.
    fn forward(&self, batch: &[(Vec<f64>, Vec<f64>)]) -> R<Vec<(Vec<V3>, Vec<V3>)>> {
        let n = batch.len();
        let skels: Vec<(Vec<f64>, Vec<Skel>)> = batch.iter().map(|(_, m)| self.skeleton(m)).collect();
        // Sparse layer + ReLU on the CPU, dense layer for the needed rows on the device.
        let mut h = vec![0f32; n * HIDDEN];
        for (b, (jp, _)) in skels.iter().enumerate() {
            let f = Self::pose_features(jp);
            let hb = &mut h[b * HIDDEN..(b + 1) * HIDDEN];
            for &(r, c, w) in &self.sp {
                hb[r] += (w * f[c] as f64) as f32;
            }
            for v in hb.iter_mut() {
                *v = v.max(0.);
            }
        }
        let ht = Tensor::from_vec(h, (n, HIDDEN), &self.dev).map_err(e)?;
        let corr = ht.matmul(&self.corr_w.t().map_err(e)?).and_then(|t| t.to_dtype(DType::F32)).and_then(|t| t.to_vec2::<f32>()).map_err(e)?;
        let mut out = Vec::with_capacity(n);
        for (b, ((shape, _), (_, g))) in batch.iter().zip(&skels).enumerate() {
            let js: Vec<Skel> = (0..NJ).map(|j| g[j].mul(&self.inv_bind[j])).collect();
            let mut vs = Vec::with_capacity(self.verts.len());
            for i in 0..self.verts.len() {
                let mut p = self.base[i];
                for (k, c) in shape.iter().enumerate() {
                    let s = self.shape_vec[k][i];
                    p = [p[0] + s[0] * c, p[1] + s[1] * c, p[2] + s[2] * c];
                }
                let cr = &corr[b][i * 3..i * 3 + 3];
                p = [p[0] + cr[0] as f64, p[1] + cr[1] as f64, p[2] + cr[2] as f64];
                let mut acc = [0.; 3];
                for &(j, w) in &self.skin[i] {
                    let q = js[j].apply(p);
                    acc = [acc[0] + w * q[0], acc[1] + w * q[1], acc[2] + w * q[2]];
                }
                vs.push([acc[0] / 100., acc[1] / 100., acc[2] / 100.]);
            }
            let jc = self.joints.iter().map(|&j| [g[j].t[0] / 100., g[j].t[1] / 100., g[j].t[2] / 100.]).collect();
            out.push((vs, jc));
        }
        Ok(out)
    }
}

impl Head {
    /// `w(name)` reads `prefix.name` from the SAM 3D Body weights.
    pub fn load(w: &dyn Fn(&str) -> R<Vec<f64>>, rig: &Rig, hand_model: bool) -> R<Head> {
        let km_all = w("keypoint_mapping")?;
        let cols = NV + NJ;
        let km = (0..NKP)
            .map(|r| rig.verts.iter().map(|&v| km_all[r * cols + v]).chain(rig.joints.iter().map(|&j| km_all[r * cols + NV + j])).collect())
            .collect();
        let v3 = |x: Vec<f64>| [x[0], x[1], x[2]];
        let l = w("local_to_world_wrist")?;
        Ok(Head {
            hand_model,
            scale_mean: w("scale_mean")?,
            scale_comps: w("scale_comps")?,
            hand_pose_mean: w("hand_pose_mean")?,
            hand_pose_comps: w("hand_pose_comps")?,
            hand_idx_l: w("hand_joint_idxs_left")?.iter().map(|v| *v as usize).collect(),
            hand_idx_r: w("hand_joint_idxs_right")?.iter().map(|v| *v as usize).collect(),
            km,
            right_wrist: v3(w("right_wrist_coords")?),
            root: v3(w("root_coords")?),
            local_to_world_wrist: [[l[0], l[1], l[2]], [l[3], l[4], l[5]], [l[6], l[7], l[8]]],
            nonhand: w("nonhand_param_idxs")?.iter().map(|v| *v as usize).collect(),
        })
    }

    fn hand_cont_to_params(&self, h: &[f64]) -> [f64; 27] {
        let mut c = self.hand_pose_mean.clone();
        for b in 0..54 {
            for a in 0..54 {
                c[b] += h[a] * self.hand_pose_comps[a * 54 + b];
            }
        }
        hand_params(&c)
    }

    /// MHRHead.forward for a batch of `pred` (= proj(token) + init_pose, 519 each):
    /// the first 70 keypoints in the camera system (y and z flipped), metres.
    pub fn keypoints(&self, rig: &Rig, preds: &[Vec<f64>]) -> R<Vec<Vec<V3>>> { Ok(self.keypoints_params(rig, preds)?.0) }

    /// `keypoints` plus the 204 MHR model parameters of each item (for parity checks).
    pub fn keypoints_params(&self, rig: &Rig, preds: &[Vec<f64>]) -> R<(Vec<Vec<V3>>, Vec<Vec<f64>>)> {
        let mut batch = Vec::with_capacity(preds.len());
        for pred in preds {
            if pred.len() != NPOSE {
                return Err(format!("MHR head 輸入長度 {}（應為 {NPOSE}）", pred.len()));
            }
            let r = rot6d_to_rotmat(&pred[0..6]);
            let a = zyx_angles(&r);
            let mut global_rot = [a[2], a[1], a[0]]; // roma "ZYX" order
            let mut global_trans = [0.; 3];
            let mut body = body_params(&pred[6..6 + BODY_CONT]);
            for i in HAND_PARAM_IDXS {
                body[i] = 0.;
            }
            body[130] = 0.;
            body[131] = 0.;
            body[132] = 0.;
            let o = 6 + BODY_CONT;
            let shape = pred[o..o + 45].to_vec();
            let scale = &pred[o + 45..o + 73];
            let hand = &pred[o + 73..o + 181];
            if self.hand_model {
                // Wrist-centric prediction moved onto the body (roma "xyz": R = Rz(g2)Ry(g1)Rx(g0)).
                let r0 = rz_ry_rx(global_rot[0], global_rot[1], global_rot[2]);
                let r1 = mm(&r0, &self.local_to_world_wrist);
                global_rot = zyx_angles(&r1);
                let r2 = rz_ry_rx(global_rot[0], global_rot[1], global_rot[2]);
                let d = mv(&r2, [self.right_wrist[0] - self.root[0], self.right_wrist[1] - self.root[1], self.right_wrist[2] - self.root[2]]);
                global_trans = [-(d[0] + self.root[0]), -(d[1] + self.root[1]), -(d[2] + self.root[2])];
            }
            let mut model = Vec::with_capacity(204);
            model.extend(global_trans.iter().map(|v| v * 10.));
            model.extend_from_slice(&global_rot);
            model.extend_from_slice(&body[..130]);
            let lh = self.hand_cont_to_params(&hand[..54]);
            let rh = self.hand_cont_to_params(&hand[54..]);
            for i in 0..27 {
                model[self.hand_idx_l[i]] = lh[i];
                model[self.hand_idx_r[i]] = rh[i];
            }
            for k in 0..68 {
                let mut s = self.scale_mean[k];
                for c in 0..28 {
                    s += scale[c] * self.scale_comps[c * 68 + k];
                }
                model.push(s);
            }
            if self.hand_model {
                for &i in &self.nonhand {
                    model[i] = 0.;
                }
            }
            batch.push((shape, model));
        }
        let posed = rig.forward(&batch)?;
        let params = batch.iter().map(|(_, m)| m.clone()).collect();
        let kps = posed
            .iter()
            .map(|(vs, js)| {
                (0..NKP)
                    .map(|k| {
                        if self.hand_model && !(21..42).contains(&k) {
                            return [0., 0., 0.];
                        }
                        let row = &self.km[k];
                        let mut p = [0.; 3];
                        for (w, q) in row.iter().zip(vs.iter().chain(js.iter())) {
                            if *w != 0. {
                                p = [p[0] + w * q[0], p[1] + w * q[1], p[2] + w * q[2]];
                            }
                        }
                        [p[0], -p[1], -p[2]]
                    })
                    .collect()
            })
            .collect();
        Ok((kps, params))
    }
}
