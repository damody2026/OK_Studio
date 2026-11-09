//! FlowHMR inference (https://github.com/flowhmr/flowhmr, `flowhmr_latest`): the
//! `HunyuanMotionMMDiT` flow-matching denoiser on the GPU, Euler sampling, and the
//! 491-dim latent decode, line for line with flowhmr/network/hymotion_mmdit_for_v2m.py,
//! token_refiner.py, mmdit/*.py and pipeline/pipeline_v2m.py (`generate`, `_decode_latent_to_motion`).
//! The SMPL-H result is handed on as the SMPL-X body (joints 0–21 are the same skeleton) in the
//! same `gvhmr::Output` the rest of the pipeline already reads.

use crate::geom::*;
use crate::gvhmr::{Output, Skeleton, SmplParams};
use candle_core::{DType, Device, Tensor};
use std::collections::HashMap;
use std::path::Path;

type R<T> = Result<T, String>;
fn e<E: std::fmt::Display>(x: E) -> String { x.to_string() }

pub const LATENT: usize = 491;
pub const FEATURE: usize = 3072;
const DIM: usize = 1024;
const HEADS: usize = 16;
const HEAD_DIM: usize = 64;
const MLP: usize = 4096;
const DOUBLE: usize = 6;
const SINGLE: usize = 12;
const REFINER: usize = 2;
/// narrowband_length 2.0 s, narrowband_v2m_length 3 frames (tt follows v2m), tm disabled.
const MM_WINDOW: usize = 60;
const MC_WINDOW: usize = 3;
const CC_WINDOW: usize = 3;
pub const STEPS: usize = 20;
pub const FPS: f64 = 30.;
/// Latent layout: root vel xz, root y, 52×3 local joint positions, 52×6 local rot6d, 16 shapes, 4 contacts.
const SPLIT: [usize; 6] = [2, 1, 156, 312, 16, 4];

// ---------------------------------------------------------------- network

pub struct Network {
    w: HashMap<String, Tensor>,
    /// Normalisation buffers stored next to the network in the checkpoint (pipeline_v2m.load_mean_std).
    stats: HashMap<String, Vec<f32>>,
    dev: Device,
}

impl Network {
    pub fn load(path: &Path, dev: &Device) -> R<Self> {
        let raw = candle_core::safetensors::load(path, dev).map_err(|x| format!("{}：{x}", path.display()))?;
        let mut w = HashMap::new();
        let mut stats = HashMap::new();
        for (k, v) in raw {
            let v = v.to_dtype(DType::F32).map_err(e)?;
            if let Some(s) = k.strip_prefix("motion_transformer.") {
                w.insert(s.to_string(), v);
            } else if k.ends_with("_mean") || k.ends_with("_std") {
                stats.insert(k, v.flatten_all().and_then(|t| t.to_vec1::<f32>()).map_err(e)?);
            }
        }
        if !w.contains_key("single_blocks.11.linear2.weight") || !stats.contains_key("local_rot_data_std") {
            return Err(format!("{} 不是 FlowHMR 權重（缺 motion_transformer.single_blocks.11 或正規化統計）", path.display()));
        }
        Ok(Network { w, stats, dev: dev.clone() })
    }
    fn p(&self, k: &str) -> R<&Tensor> { self.w.get(k).ok_or_else(|| format!("FlowHMR 權重缺少 {k}")) }
    fn linear(&self, x: &Tensor, name: &str) -> R<Tensor> {
        let w = self.p(&format!("{name}.weight"))?;
        let y = x.broadcast_matmul(&w.t().map_err(e)?).map_err(e)?;
        match self.w.get(&format!("{name}.bias")) {
            Some(b) => y.broadcast_add(b).map_err(e),
            None => Ok(y),
        }
    }
    fn stat(&self, k: &str) -> R<&[f32]> { self.stats.get(k).map(|v| v.as_slice()).ok_or_else(|| format!("FlowHMR 權重缺少 {k}")) }

    /// LayerNorm without affine (`elementwise_affine=False`).
    fn norm(x: &Tensor, eps: f64) -> R<Tensor> {
        let mean = x.mean_keepdim(candle_core::D::Minus1).map_err(e)?;
        let xc = x.broadcast_sub(&mean).map_err(e)?;
        let var = xc.sqr().and_then(|t| t.mean_keepdim(candle_core::D::Minus1)).map_err(e)?;
        xc.broadcast_div(&(var + eps).and_then(|t| t.sqrt()).map_err(e)?).map_err(e)
    }
    fn layer_norm(&self, x: &Tensor, name: &str, eps: f64) -> R<Tensor> {
        candle_nn::ops::layer_norm(x, self.p(&format!("{name}.weight"))?, self.p(&format!("{name}.bias"))?, eps as f32).map_err(e)
    }
    fn rms_norm(&self, x: &Tensor, name: &str) -> R<Tensor> {
        candle_nn::ops::rms_norm(x, self.p(&format!("{name}.weight"))?, 1e-6).map_err(e)
    }
    /// `ModulateDiT`: linear(silu(adapter)) split into `n` chunks, each (1, DIM).
    fn modulation(&self, adapter: &Tensor, name: &str, n: usize) -> R<Vec<Tensor>> {
        let m = self.linear(&adapter.silu().map_err(e)?, &format!("{name}.linear"))?;
        (0..n).map(|i| m.narrow(1, i * DIM, DIM).map_err(e)).collect()
    }
    fn modulate(x: &Tensor, shift: &Tensor, scale: &Tensor) -> R<Tensor> {
        x.broadcast_mul(&(scale + 1.).map_err(e)?).and_then(|t| t.broadcast_add(shift)).map_err(e)
    }
    /// `TimestepEmbeddingEncoder`: sinusoidal [cos, sin] embedding, Linear, SiLU, Linear.
    fn timestep(&self, t: f64, factor: f64, name: &str) -> R<Tensor> {
        let half = DIM / 2;
        let mut emb = vec![0f32; DIM];
        for i in 0..half {
            let f = (-(10000f32.ln()) * i as f32 / half as f32).exp();
            let a = (t as f32 * factor as f32) * f;
            emb[i] = a.cos();
            emb[half + i] = a.sin();
        }
        let x = Tensor::from_vec(emb, (1, DIM), &self.dev).map_err(e)?;
        let h = self.linear(&x, &format!("{name}.blocks.0"))?.silu().map_err(e)?;
        self.linear(&h, &format!("{name}.blocks.2"))
    }
    fn mlp_encoder(&self, x: &Tensor, name: &str) -> R<Tensor> {
        let h = self.linear(x, &format!("{name}.linears.0"))?.silu().map_err(e)?;
        self.linear(&h, &format!("{name}.linears.2"))
    }

    /// (L, DIM) → (HEADS, L, HEAD_DIM)
    fn heads(x: &Tensor, l: usize) -> R<Tensor> {
        x.reshape((l, HEADS, HEAD_DIM)).and_then(|t| t.transpose(0, 1)).and_then(|t| t.contiguous()).map_err(e)
    }
    /// Scaled dot-product attention over (HEADS, Lq, D) with an additive (Lq, Lk) mask, in query chunks.
    fn attention(q: &Tensor, k: &Tensor, v: &Tensor, mask: Option<&Tensor>) -> R<Tensor> {
        let lq = q.dim(1).map_err(e)?;
        let kt = k.t().map_err(e)?.contiguous().map_err(e)?;
        let chunk = 1024;
        let mut outs = Vec::new();
        let mut s0 = 0;
        while s0 < lq {
            let n = chunk.min(lq - s0);
            let qc = q.narrow(1, s0, n).map_err(e)?;
            let mut s = (qc.matmul(&kt).map_err(e)? / (HEAD_DIM as f64).sqrt()).map_err(e)?;
            if let Some(m) = mask {
                s = s.broadcast_add(&m.narrow(0, s0, n).map_err(e)?).map_err(e)?;
            }
            outs.push(candle_nn::ops::softmax_last_dim(&s).map_err(e)?.matmul(v).map_err(e)?);
            s0 += n;
        }
        let a = Tensor::cat(&outs, 1).map_err(e)?; // (HEADS, Lq, D)
        a.transpose(0, 1).and_then(|t| t.reshape((lq, DIM))).map_err(e)
    }

    /// `HunyuanMotionMMDiT.forward` for one sequence: x (T,491) noisy latent, feature (T,3072),
    /// camera_R (T,9), timestep t in [0,1]. Returns the predicted clean latent x1 (T,491).
    fn forward(&self, x: &Tensor, ctxt: &Tensor, t: f64, rope: &(Tensor, Tensor), mask: &Tensor) -> R<Tensor> {
        let l = x.dim(0).map_err(e)?;
        let mut m = self.linear(x, "input_encoder")?;
        // adapter = timestep(t·1000) + vtxt_encoder(zeros(768))
        let zeros = Tensor::zeros((1, 768), DType::F32, &self.dev).map_err(e)?;
        let adapter = (self.timestep(t, 1000., "timestep_encoder")? + self.mlp_encoder(&zeros, "vtxt_encoder")?).map_err(e)?;

        // SingleTokenRefiner: c = timestep(t) + MLP(mean of the raw context), then 2 refiner blocks.
        let c = (self.timestep(t, 1., "text_refiner.timestep_encoder")?
            + self.mlp_encoder(&ctxt.mean_keepdim(0).map_err(e)?, "text_refiner.context_encoder")?)
        .map_err(e)?;
        let mut c_feat = self.linear(ctxt, "text_refiner.input_embedder")?;
        for b in 0..REFINER {
            let n = format!("text_refiner.individual_token_refiner.blocks.{b}");
            let g = self.modulation(&c, &format!("{n}.adaLN_modulation"), 2)?;
            let qkv = self.linear(&self.layer_norm(&c_feat, &format!("{n}.norm1"), 1e-5)?, &format!("{n}.self_attn_qkv"))?;
            let q = self.layer_norm(&qkv.narrow(1, 0, DIM).map_err(e)?.reshape((l, HEADS, HEAD_DIM)).map_err(e)?, &format!("{n}.self_attn_q_norm"), 1e-5)?;
            let k = self.layer_norm(&qkv.narrow(1, DIM, DIM).map_err(e)?.reshape((l, HEADS, HEAD_DIM)).map_err(e)?, &format!("{n}.self_attn_k_norm"), 1e-5)?;
            let v = qkv.narrow(1, 2 * DIM, DIM).map_err(e)?;
            let to_h = |t: Tensor| t.transpose(0, 1).and_then(|t| t.contiguous()).map_err(e);
            let a = Self::attention(&to_h(q)?, &to_h(k)?, &Self::heads(&v, l)?, None)?;
            c_feat = (c_feat + self.linear(&a, &format!("{n}.self_attn_proj"))?.broadcast_mul(&g[0]).map_err(e)?).map_err(e)?;
            let h = self.layer_norm(&c_feat, &format!("{n}.norm2"), 1e-5)?;
            let h = self.linear(&self.linear(&h, &format!("{n}.mlp.fc1"))?.silu().map_err(e)?, &format!("{n}.mlp.fc2"))?;
            c_feat = (c_feat + h.broadcast_mul(&g[1]).map_err(e)?).map_err(e)?;
        }

        let (cos, sin) = rope;
        let qk = |qkv: &Tensor, prefix: &str| -> R<(Tensor, Tensor, Tensor)> {
            let q = self.rms_norm(&qkv.narrow(1, 0, DIM).map_err(e)?.reshape((l, HEADS, HEAD_DIM)).map_err(e)?, &format!("{prefix}q_norm"))?;
            let k = self.rms_norm(&qkv.narrow(1, DIM, DIM).map_err(e)?.reshape((l, HEADS, HEAD_DIM)).map_err(e)?, &format!("{prefix}k_norm"))?;
            let to_h = |t: Tensor| t.transpose(0, 1).and_then(|t| t.contiguous()).map_err(e);
            let q = candle_nn::rotary_emb::rope_i(&to_h(q)?.unsqueeze(0).map_err(e)?, cos, sin).map_err(e)?.squeeze(0).map_err(e)?;
            let k = candle_nn::rotary_emb::rope_i(&to_h(k)?.unsqueeze(0).map_err(e)?, cos, sin).map_err(e)?.squeeze(0).map_err(e)?;
            Ok((q, k, Self::heads(&qkv.narrow(1, 2 * DIM, DIM).map_err(e)?, l)?))
        };
        let gelu_mlp = |x: &Tensor, n: &str| -> R<Tensor> { self.linear(&self.linear(x, &format!("{n}.fc1"))?.gelu().map_err(e)?, &format!("{n}.fc2")) };

        // double-stream blocks: separate weights, joint attention over [motion; context]
        for b in 0..DOUBLE {
            let n = format!("double_blocks.{b}");
            let mm = self.modulation(&adapter, &format!("{n}.motion_mod"), 6)?;
            let tm = self.modulation(&adapter, &format!("{n}.text_mod"), 6)?;
            let (mq, mk, mv) = qk(&self.linear(&Self::modulate(&Self::norm(&m, 1e-6)?, &mm[0], &mm[1])?, &format!("{n}.motion_qkv"))?, &format!("{n}.motion_"))?;
            let (tq, tk, tv) = qk(&self.linear(&Self::modulate(&Self::norm(&c_feat, 1e-6)?, &tm[0], &tm[1])?, &format!("{n}.text_qkv"))?, &format!("{n}.text_"))?;
            let cat = |a: &Tensor, b: &Tensor| Tensor::cat(&[a, b], 1).map_err(e);
            let a = Self::attention(&cat(&mq, &tq)?, &cat(&mk, &tk)?, &cat(&mv, &tv)?, Some(mask))?;
            let (ma, ta) = (a.narrow(0, 0, l).map_err(e)?, a.narrow(0, l, l).map_err(e)?);
            m = (m + self.linear(&ma, &format!("{n}.motion_out_proj"))?.broadcast_mul(&mm[2]).map_err(e)?).map_err(e)?;
            let h = gelu_mlp(&Self::modulate(&Self::norm(&m, 1e-6)?, &mm[3], &mm[4])?, &format!("{n}.motion_mlp"))?;
            m = (m + h.broadcast_mul(&mm[5]).map_err(e)?).map_err(e)?;
            c_feat = (c_feat + self.linear(&ta, &format!("{n}.text_out_proj"))?.broadcast_mul(&tm[2]).map_err(e)?).map_err(e)?;
            let h = gelu_mlp(&Self::modulate(&Self::norm(&c_feat, 1e-6)?, &tm[3], &tm[4])?, &format!("{n}.text_mlp"))?;
            c_feat = (c_feat + h.broadcast_mul(&tm[5]).map_err(e)?).map_err(e)?;
        }

        // single-stream blocks over the concatenation; RoPE restarts at 0 for each half
        let mut h = Tensor::cat(&[&m, &c_feat], 0).map_err(e)?;
        for b in 0..SINGLE {
            let n = format!("single_blocks.{b}");
            let g = self.modulation(&adapter, &format!("{n}.modulation"), 3)?;
            let y = self.linear(&Self::modulate(&Self::norm(&h, 1e-6)?, &g[0], &g[1])?, &format!("{n}.linear1"))?;
            let qkv = y.narrow(1, 0, 3 * DIM).map_err(e)?;
            let hidden = y.narrow(1, 3 * DIM, MLP).map_err(e)?;
            let (q1, k1, v1) = qk(&qkv.narrow(0, 0, l).map_err(e)?, &format!("{n}."))?;
            let (q2, k2, v2) = qk(&qkv.narrow(0, l, l).map_err(e)?, &format!("{n}."))?;
            let cat = |a: &Tensor, b: &Tensor| Tensor::cat(&[a, b], 1).map_err(e);
            let a = Self::attention(&cat(&q1, &q2)?, &cat(&k1, &k2)?, &cat(&v1, &v2)?, Some(mask))?;
            let o = self.linear(&Tensor::cat(&[&a, &hidden.gelu().map_err(e)?], 1).map_err(e)?, &format!("{n}.linear2"))?;
            h = (h + o.broadcast_mul(&g[2]).map_err(e)?).map_err(e)?;
        }

        // FinalLayer on the motion half
        let g = self.modulation(&adapter, "final_layer.adaLN_modulation", 2)?;
        let x = Self::modulate(&Self::norm(&h.narrow(0, 0, l).map_err(e)?, 1e-5)?, &g[0], &g[1])?;
        self.linear(&x, "final_layer.linear")
    }

    /// Additive narrowband_v2m mask over [motion; context] (2T × 2T).
    fn mask(&self, l: usize) -> R<Tensor> {
        let n = 2 * l;
        let mut m = vec![f32::NEG_INFINITY; n * n];
        for i in 0..l {
            for j in 0..l {
                let d = i.abs_diff(j);
                if d <= MM_WINDOW {
                    m[i * n + j] = 0.; // motion → motion
                }
                if d <= MC_WINDOW {
                    m[i * n + l + j] = 0.; // motion → context
                }
                if d <= CC_WINDOW {
                    m[(l + i) * n + l + j] = 0.; // context → context (context → motion stays masked)
                }
            }
        }
        Tensor::from_vec(m, (n, n), &self.dev).map_err(e)
    }

    /// RoPE tables (interleaved pairs, base 10000, head dim 64) for positions 0..l.
    fn rope(&self, l: usize) -> R<(Tensor, Tensor)> {
        let mut cos = vec![0f32; l * 32];
        let mut sin = vec![0f32; l * 32];
        for t in 0..l {
            for k in 0..32 {
                let f = 1. / 10000f32.powf(2. * k as f32 / HEAD_DIM as f32);
                let a = t as f32 * f;
                cos[t * 32 + k] = a.cos();
                sin[t * 32 + k] = a.sin();
            }
        }
        Ok((Tensor::from_vec(cos, (l, 32), &self.dev).map_err(e)?, Tensor::from_vec(sin, (l, 32), &self.dev).map_err(e)?))
    }

    /// `V2MPipeline.generate` with cfg 1.0: Euler over linspace(0,1,steps+1) from noise `y0`,
    /// the network predicting x1 and the velocity being (x1 − x)/max(1 − t, 1/steps).
    /// `progress(step)` is called after each step.
    pub fn sample(&self, feature: &[f32], camera_r: &[f32], y0: &[f32], steps: usize, progress: &dyn Fn(usize)) -> R<Vec<f32>> {
        let l = y0.len() / LATENT;
        if feature.len() != l * FEATURE || camera_r.len() != l * 9 {
            return Err(format!("FlowHMR 輸入長度不一致：雜訊 {l} 幀、特徵 {}、相機 {}", feature.len() / FEATURE, camera_r.len() / 9));
        }
        let d = &self.dev;
        let ctxt = (self.linear(&Tensor::from_slice(feature, (l, FEATURE), d).map_err(e)?, "ctxt_encoder.feature")?
            + self.linear(&Tensor::from_slice(camera_r, (l, 9), d).map_err(e)?, "ctxt_encoder.camera_R")?)
        .map_err(e)?;
        let rope = self.rope(l)?;
        let mask = self.mask(l)?;
        let mut y = Tensor::from_slice(y0, (l, LATENT), d).map_err(e)?;
        for s in 0..steps {
            let (t0, t1) = (s as f64 / steps as f64, (s + 1) as f64 / steps as f64);
            let x1 = self.forward(&y, &ctxt, t0, &rope, &mask)?;
            let v = ((x1 - &y).map_err(e)? / (1. - t0).max(1. / steps as f64)).map_err(e)?;
            y = (y + (v * (t1 - t0)).map_err(e)?).map_err(e)?;
            progress(s + 1);
        }
        y.flatten_all().and_then(|t| t.to_vec1::<f32>()).map_err(e)
    }
}

// ---------------------------------------------------------------- noise

/// `torch.randn(shape, generator=torch.Generator().manual_seed(seed))` on the CPU (float32):
/// mt19937 uniforms, Box–Muller in blocks of 16 (aten normal_fill), so a seed gives the same
/// noise as the reference implementation.
pub fn torch_randn(n: usize, seed: u64) -> Vec<f32> {
    let mut mt = Mt19937::new(seed as u32);
    let mut uniform = || ((mt.next() & ((1 << 24) - 1)) as f32) * (1. / (1u32 << 24) as f32);
    let mut d: Vec<f32> = (0..n).map(|_| uniform()).collect();
    let fill16 = |d: &mut [f32]| {
        for j in 0..8 {
            let u1 = 1. - d[j];
            let u2 = d[j + 8];
            let r = (-2. * u1.ln()).sqrt();
            let th = 2. * std::f32::consts::PI * u2;
            d[j] = r * th.cos();
            d[j + 8] = r * th.sin();
        }
    };
    if n < 16 {
        // aten falls back to scalar Box–Muller below 16 values; FlowHMR never asks for that few.
        return d;
    }
    let mut i = 0;
    while i + 16 <= n {
        fill16(&mut d[i..i + 16]);
        i += 16;
    }
    if n % 16 != 0 {
        let tail = n - 16;
        for k in 0..16 {
            d[tail + k] = uniform();
        }
        fill16(&mut d[tail..]);
    }
    d
}

struct Mt19937 {
    s: [u32; 624],
    i: usize,
}
impl Mt19937 {
    fn new(seed: u32) -> Self {
        let mut s = [0u32; 624];
        s[0] = seed;
        for i in 1..624 {
            s[i] = 1812433253u32.wrapping_mul(s[i - 1] ^ (s[i - 1] >> 30)).wrapping_add(i as u32);
        }
        Mt19937 { s, i: 624 }
    }
    fn next(&mut self) -> u32 {
        if self.i >= 624 {
            for k in 0..624 {
                let y = (self.s[k] & 0x8000_0000) | (self.s[(k + 1) % 624] & 0x7fff_ffff);
                let mut v = self.s[(k + 397) % 624] ^ (y >> 1);
                if y & 1 != 0 {
                    v ^= 0x9908_b0df;
                }
                self.s[k] = v;
            }
            self.i = 0;
        }
        let mut y = self.s[self.i];
        self.i += 1;
        y ^= y >> 11;
        y ^= (y << 7) & 0x9d2c_5680;
        y ^= (y << 15) & 0xefc6_0000;
        y ^ (y >> 18)
    }
}

// ---------------------------------------------------------------- decode

/// FlowHMR's rot6d: two columns stored interleaved (`view(3,2)`), Gram–Schmidt, columns b1 b2 b3.
fn rot6d_cols(d: &[f64]) -> M3 {
    let a1 = [d[0], d[2], d[4]];
    let a2 = [d[1], d[3], d[5]];
    let b1 = normalize(a1);
    let b2 = normalize(sub(a2, scale(b1, dot(b1, a2))));
    let b3 = cross(b1, b2);
    [[b1[0], b2[0], b3[0]], [b1[1], b2[1], b3[1]], [b1[2], b2[2], b3[2]]]
}

pub struct Decoded {
    /// Root orientation in FlowHMR's y-up world (axis-angle).
    pub global_orient: Vec<V3>,
    pub body_pose: Vec<[V3; 21]>,
    /// Pelvis position in the world (m).
    pub pelvis: Vec<V3>,
    pub foot_contacts: Vec<[f64; 4]>,
}

/// `_decode_latent_to_motion` (motion_style basic) for the 22 body joints.
pub fn decode(net: &Network, latent: &[f32]) -> R<Decoded> {
    let l = latent.len() / LATENT;
    let off: Vec<usize> = SPLIT.iter().scan(0, |a, s| { let o = *a; *a += s; Some(o) }).collect();
    let (vel_m, vel_s) = (net.stat("smooth_root_vel_mean")?, net.stat("smooth_root_vel_std")?);
    let (ljp_m, ljp_s) = (net.stat("local_joints_positions_mean")?, net.stat("local_joints_positions_std")?);
    let (rot_m, rot_s) = (net.stat("local_rot_data_mean")?, net.stat("local_rot_data_std")?);
    let (fc_m, fc_s) = (net.stat("rep_foot_contacts_mean")?, net.stat("rep_foot_contacts_std")?);
    let clamp = |s: f32| s.max(1e-5) as f64;
    let mut out = Decoded { global_orient: Vec::with_capacity(l), body_pose: Vec::with_capacity(l), pelvis: Vec::with_capacity(l), foot_contacts: Vec::with_capacity(l) };
    let (mut rx, mut rz) = (0f64, 0f64);
    for t in 0..l {
        let x = &latent[t * LATENT..(t + 1) * LATENT];
        let vx = x[off[0]] as f64 * clamp(vel_s[0]) + vel_m[0] as f64;
        let vz = x[off[0] + 1] as f64 * clamp(vel_s[2]) + vel_m[2] as f64;
        if t > 0 {
            rx += vx / FPS;
            rz += vz / FPS;
        }
        // pelvis = its local joint position, x/z moved by the integrated root; y is already absolute
        // (the separate root height channel is not used for it).
        let p: V3 = std::array::from_fn(|k| x[off[2] + k] as f64 * clamp(ljp_s[k]) + ljp_m[k] as f64);
        out.pelvis.push([p[0] + rx, p[1], p[2] + rz]);
        let rot = |j: usize| -> M3 {
            let d: Vec<f64> = (0..6).map(|k| x[off[3] + j * 6 + k] as f64 * clamp(rot_s[j * 6 + k]) + rot_m[j * 6 + k] as f64).collect();
            rot6d_cols(&d)
        };
        out.global_orient.push(matrix_to_aa(&rot(0)));
        out.body_pose.push(std::array::from_fn(|j| matrix_to_aa(&rot(j + 1))));
        out.foot_contacts.push(std::array::from_fn(|k| x[off[5] + k] as f64 * clamp(fc_s[k]) + fc_m[k] as f64));
    }
    Ok(out)
}

// ---------------------------------------------------------------- pipeline

pub struct Inputs {
    /// SAM 3D Body pose tokens per frame: body, left hand, right hand (T × 3072).
    pub feature: Vec<f32>,
    /// World→camera rotation of each frame relative to the first, OpenCV axes (`R_t·R_0ᵀ`).
    pub cam_r: Vec<M3>,
    pub seed: u64,
    pub steps: usize,
}

/// Samples, decodes and returns the motion as SMPL-X body parameters (betas 0; the pelvis of the
/// neutral SMPL-X rest pose is placed on FlowHMR's pelvis). The world is y-up like GVHMR's.
pub fn predict(net: &Network, skel: &Skeleton, inp: &Inputs, progress: &dyn Fn(usize)) -> R<Output> {
    let l = inp.cam_r.len();
    if l < 2 || inp.feature.len() != l * FEATURE {
        return Err(format!("FlowHMR 輸入長度不一致：相機 {l} 幀、特徵 {} 幀", inp.feature.len() / FEATURE));
    }
    let cam: Vec<f32> = inp.cam_r.iter().flat_map(|m| m.iter().flat_map(|r| r.iter().map(|v| *v as f32))).collect();
    let y0 = torch_randn(l * LATENT, inp.seed);
    let latent = net.sample(&inp.feature, &cam, &y0, inp.steps, progress)?;
    let d = decode(net, &latent)?;
    let betas = [0f64; 10];
    let j0 = skel.joints(&betas)[0];
    let global = SmplParams { global_orient: d.global_orient.clone(), body_pose: d.body_pose.clone(), transl: d.pelvis.iter().map(|p| sub(*p, j0)).collect(), betas };
    // Camera-frame copy (rotation only: FlowHMR has no camera translation). Single-person import does
    // not read it; pair alignment needs real camera placement and stays on GVHMR.
    let flip: M3 = [[1., 0., 0.], [0., -1., 0.], [0., 0., -1.]];
    let incam_orient = (0..l).map(|t| matrix_to_aa(&mul(&mul(&inp.cam_r[t], &flip), &aa_to_matrix(d.global_orient[t])))).collect();
    let incam_transl = (0..l).map(|t| mv(&mul(&inp.cam_r[t], &flip), global.transl[t])).collect();
    let incam = SmplParams { global_orient: incam_orient, body_pose: d.body_pose, transl: incam_transl, betas };
    // GVHMR's static-joint logits are only used inside gvhmr::predict; FlowHMR has its own contacts.
    Ok(Output { global, incam, static_conf_logits: Vec::new() })
}

#[cfg(test)]
mod tests {
    #[test]
    fn randn_matches_torch() {
        // torch.randn((1,3,6), generator=torch.Generator().manual_seed(42)) — torch 2.12 CPU
        let want = [1.926915, 1.487284, -0.497398, 0.439589, -0.758131, 1.078318, 0.800801, 1.680621, 0.35586, -0.686623, 0.610466, 1.334738, -0.231624, 0.041759, -0.251575, 0.859859, -0.309727, -0.39571];
        let got = super::torch_randn(18, 42);
        for (a, b) in got.iter().zip(want) {
            assert!((*a as f64 - b).abs() < 1e-5, "{got:?}");
        }
        // long sequences, with and without the redrawn tail block (torch.randn((n,), seed 42))
        let cases: [(usize, [(usize, f64); 7]); 2] = [
            (23568, [(0, 1.926915), (15, 0.762445), (16, 1.642317), (9000, 1.288897), (23551, -0.139587), (23552, 0.404841), (23567, 0.479944)]),
            (23077, [(0, 1.926915), (15, 0.762445), (16, 1.642317), (9000, 1.288897), (23060, -1.233407), (23061, -0.274345), (23076, 0.757633)]),
        ];
        for (n, want) in cases {
            let got = super::torch_randn(n, 42);
            for (i, v) in want {
                assert!((got[i] as f64 - v).abs() < 1e-5, "n={n} i={i}: {} vs {v}", got[i]);
            }
        }
    }
}
