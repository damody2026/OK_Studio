//! SAM 3D Body (facebook/sam-3d-body-dinov3) pose tokens for FlowHMR: per frame the body
//! decoder's pose token and the hand decoder's pose token for each hand (3 × 1024), exactly
//! what FlowHMR's lite_sam_infer.extract_tokens captures. Line for line with
//! sam_3d_body/models/meta_arch/sam3d_body.py (forward_pose_branch, forward_decoder[_hand],
//! keypoint token updates, _get_hand_box), decoders/promptable_decoder.py, modules/transformer.py,
//! camera_embed.py, prompt_encoder.py, heads/camera_head.py, data/transforms (crop) and the DINOv3
//! ViT-H+/16 backbone (dinov3/models/vision_transformer.py, layers/*). The MHR body model is in mhr.rs.
//!
//! The backbone runs in bfloat16 like the release (TRAIN.FP16_TYPE bfloat16); everything after it in f32.

use crate::mhr::{Head, Rig, NKP};
use candle_core::{DType, Device, Tensor};
use std::collections::HashMap;
use std::path::Path;

type R<T> = Result<T, String>;
fn e<E: std::fmt::Display>(x: E) -> String { x.to_string() }

const IMG: usize = 512;
const PATCH: usize = 16;
const GRID: usize = IMG / PATCH; // 32
const NPATCH: usize = GRID * GRID;
const BB_DIM: usize = 1280;
const BB_DEPTH: usize = 32;
const BB_HEADS: usize = 20;
const BB_PREFIX: usize = 5; // cls + 4 storage tokens
const DEC: usize = 1024;
const DEC_HEADS: usize = 8;
const DEC_LAYERS: usize = 6;
const NTOK: usize = 145; // pose, prev, prompt, 2 hand boxes, 70 2D keypoints, 70 3D keypoints
const KP2D: usize = 5;
const KP3D: usize = 75;
const MEAN: [f32; 3] = [0.485, 0.456, 0.406];
const STD: [f32; 3] = [0.229, 0.224, 0.225];

/// Intermediate values for parity checks (name → flattened f32).
pub type Trace = HashMap<String, Vec<f32>>;

pub struct Model {
    w: HashMap<String, Tensor>,
    bb_dtype: DType,
    rig: Rig,
    head: Head,
    head_hand: Head,
    rope: (Tensor, Tensor),
    pe_body: Tensor,
    pe_hand: Tensor,
    dev: Device,
}

/// One crop: geometry in the full image and the normalized pixels.
struct Crop {
    center: [f32; 2],
    scale: [f32; 2],
    affine: [[f64; 3]; 2],
    pixels: Vec<f32>, // 3 × 512 × 512, normalized
}

fn tensor_f64(t: &Tensor) -> R<Vec<f64>> {
    Ok(t.to_dtype(DType::F64).and_then(|t| t.flatten_all()).and_then(|t| t.to_vec1::<f64>()).map_err(e)?)
}

// ---------------------------------------------------------------- crops (data/transforms)

/// GetBBoxCenterScale(padding) + TopdownAffine(512, use_udp=False): float32 like numpy.
fn crop_geometry(b: [f32; 4], padding: f32) -> ([f32; 2], [f32; 2], [[f64; 3]; 2]) {
    let center = [(b[0] + b[2]) * 0.5, (b[1] + b[3]) * 0.5];
    let mut s = [(b[2] - b[0]) * padding, (b[3] - b[1]) * padding];
    let fix = |s: [f32; 2], ar: f32| if s[0] > s[1] * ar { [s[0], s[0] / ar] } else { [s[1] * ar, s[1]] };
    s = fix(fix(s, 0.75), 1.0);
    // get_warp_matrix: src = center, center + (0, -w/2), third point; dst = (256,256), (256,0), (0,0).
    let src1 = [center[0], (center[1] as f64 + s[0] as f64 * -0.5) as f32];
    let d = [center[0] - src1[0], center[1] - src1[1]];
    let src2 = [src1[0] - d[1], src1[1] + d[0]];
    let src = [[center[0] as f64, center[1] as f64], [src1[0] as f64, src1[1] as f64], [src2[0] as f64, src2[1] as f64]];
    let half = IMG as f64 / 2.;
    let dst = [[half, half], [half, 0.], [0., 0.]];
    (center, s, affine_from_points(&src, &dst))
}

/// cv2.getAffineTransform: solves dst = M·[src,1] exactly for three point pairs.
fn affine_from_points(src: &[[f64; 2]; 3], dst: &[[f64; 2]; 3]) -> [[f64; 3]; 2] {
    let det = src[0][0] * (src[1][1] - src[2][1]) - src[0][1] * (src[1][0] - src[2][0]) + (src[1][0] * src[2][1] - src[2][0] * src[1][1]);
    let mut m = [[0.; 3]; 2];
    for r in 0..2 {
        let (a, b, c) = (dst[0][r], dst[1][r], dst[2][r]);
        m[r][0] = (a * (src[1][1] - src[2][1]) - src[0][1] * (b - c) + (b * src[2][1] - c * src[1][1])) / det;
        m[r][1] = (src[0][0] * (b - c) - a * (src[1][0] - src[2][0]) + (src[1][0] * c - src[2][0] * b)) / det;
        m[r][2] = (src[0][0] * (src[1][1] * c - src[2][1] * b) - src[0][1] * (src[1][0] * c - src[2][0] * b) + a * (src[1][0] * src[2][1] - src[2][0] * src[1][1])) / det;
    }
    m
}

/// cv2.warpAffine(INTER_LINEAR, BORDER_CONSTANT 0) with OpenCV's fixed-point arithmetic
/// (as reproduced by FlowHMR's sam_gpu_preprocess.py), then ToTensor and normalization.
fn warp(img: &[u8], w: usize, h: usize, m: &[[f64; 3]; 2], flip: bool) -> Vec<f32> {
    let d = m[0][0] * m[1][1] - m[0][1] * m[1][0];
    let d = if d != 0. { 1. / d } else { 0. };
    let (a11, a22, a12, a21) = (m[1][1] * d, m[0][0] * d, -m[0][1] * d, -m[1][0] * d);
    let b1 = -a11 * m[0][2] - a12 * m[1][2];
    let b2 = -a21 * m[0][2] - a22 * m[1][2];
    let inv = [[a11, a12, b1], [a21, a22, b2]];
    let n = IMG * IMG;
    let mut out = vec![0f32; 3 * n];
    let hx: Vec<[i64; 2]> = (0..IMG).map(|x| [0, 1].map(|a| (inv[a][0] * x as f64 * 1024.).round_ties_even() as i64)).collect();
    for y in 0..IMG {
        let vy = [0, 1].map(|a| ((inv[a][1] * y as f64 + inv[a][2]) * 1024.).round_ties_even() as i64);
        for x in 0..IMG {
            let sx = (hx[x][0] + vy[0] + 16) >> 5;
            let sy = (hx[x][1] + vy[1] + 16) >> 5;
            let (x0, y0, fx, fy) = (sx >> 5, sy >> 5, sx & 31, sy & 31);
            let mut acc = [0i64; 3];
            for dy in 0..2i64 {
                let yy = y0 + dy;
                let wy = if dy == 1 { fy } else { 32 - fy };
                for dx in 0..2i64 {
                    let xx = x0 + dx;
                    if xx < 0 || xx >= w as i64 || yy < 0 || yy >= h as i64 {
                        continue;
                    }
                    let wgt = wy * if dx == 1 { fx } else { 32 - fx };
                    let col = if flip { w as i64 - 1 - xx } else { xx };
                    let p = (yy as usize * w + col as usize) * 3;
                    for c in 0..3 {
                        acc[c] += img[p + c] as i64 * wgt;
                    }
                }
            }
            for c in 0..3 {
                let v = ((acc[c] + 512) >> 10) as f32 / 255.;
                out[c * n + y * IMG + x] = (v - MEAN[c]) / STD[c];
            }
        }
    }
    out
}

/// Antialiased bilinear downsampling weights (PyTorch `_upsample_bilinear2d_aa`, scale_factor 1/16).
fn aa_weights(input: usize, output: usize) -> Vec<(usize, Vec<f64>)> {
    let scale = input as f64 / output as f64;
    let support = scale; // bilinear: interp_size/2 · scale
    (0..output)
        .map(|i| {
            let center = scale * (i as f64 + 0.5);
            let xmin = ((center - support + 0.5) as i64).max(0) as usize;
            let xmax = ((center + support + 0.5) as i64).min(input as i64) as usize;
            let mut w: Vec<f64> = (xmin..xmax)
                .map(|j| {
                    let x = ((j - xmin) as f64 + xmin as f64 - center + 0.5) / scale;
                    (1. - x.abs()).max(0.)
                })
                .collect();
            let total: f64 = w.iter().sum();
            if total != 0. {
                w.iter_mut().for_each(|v| *v /= total);
            }
            (xmin, w)
        })
        .collect()
}

/// CameraEncoder input: per-pixel rays of the crop, downsampled to the patch grid, Fourier-encoded (99).
fn ray_features(affine: &[[f64; 3]; 2], k: &[f64; 9]) -> Vec<f32> {
    let a = affine.map(|r| r.map(|v| v as f32));
    let ray = |p: usize, axis: usize| -> f64 {
        let v = p as f32 / a[axis][axis] - a[axis][2] / a[axis][axis];
        let (c, f) = if axis == 0 { (k[2] as f32, k[0] as f32) } else { (k[5] as f32, k[4] as f32) };
        ((v - c) / f) as f64
    };
    let ww = aa_weights(IMG, GRID);
    let line = |axis: usize| -> Vec<f64> { ww.iter().map(|(s, w)| w.iter().enumerate().map(|(j, wj)| wj * ray(s + j, axis)).sum()).collect() };
    let (rx, ry) = (line(0), line(1));
    let freqs: Vec<f64> = (0..16).map(|i| 1. + (32. - 1.) * i as f64 / 15.).collect();
    let mut out = Vec::with_capacity(NPATCH * 99);
    for gy in 0..GRID {
        for gx in 0..GRID {
            let pos = [rx[gx] as f32, ry[gy] as f32, 1f32];
            let mut f = [0f32; 48];
            for d in 0..3 {
                for b in 0..16 {
                    f[d * 16 + b] = pos[d] * freqs[b] as f32;
                }
            }
            out.extend_from_slice(&pos);
            out.extend(f.iter().map(|v| (std::f32::consts::PI * v).sin()));
            out.extend(f.iter().map(|v| (std::f32::consts::PI * v).cos()));
        }
    }
    out
}

/// PositionEmbeddingRandom on the patch grid → (1024, 1280).
fn dense_pe(g: &[f64]) -> Vec<f32> {
    let n = g.len() / 2;
    let mut out = Vec::with_capacity(NPATCH * 2 * n);
    for i in 0..GRID {
        for j in 0..GRID {
            let x = 2. * ((j as f32 + 0.5) / GRID as f32) - 1.;
            let y = 2. * ((i as f32 + 0.5) / GRID as f32) - 1.;
            let c: Vec<f32> = (0..n).map(|k| 2. * std::f32::consts::PI * (x * g[k] as f32 + y * g[n + k] as f32)).collect();
            out.extend(c.iter().map(|v| v.sin()));
            out.extend(c.iter().map(|v| v.cos()));
        }
    }
    out
}

impl Model {
    /// `sam3d`: converted model.ckpt; `mhr`: converted assets/mhr_model.pt. `f32_backbone` is for parity tests.
    pub fn load(sam3d: &Path, mhr: &Path, dev: &Device, f32_backbone: bool) -> R<Model> {
        let raw = candle_core::safetensors::load(sam3d, dev).map_err(|x| format!("{}：{x}", sam3d.display()))?;
        if !raw.contains_key("decoder_hand.norm_final.weight") || !raw.contains_key("backbone.encoder.blocks.31.mlp.w3.weight") {
            return Err(format!("{} 不是 SAM 3D Body（dinov3）權重", sam3d.display()));
        }
        let bb_dtype = if f32_backbone { DType::F32 } else { DType::BF16 };
        let mut w = HashMap::new();
        let mut cpu: HashMap<String, Vec<f64>> = HashMap::new();
        for (k, v) in raw {
            if k.starts_with("head_pose.") || k.starts_with("head_pose_hand.") || k.contains("positional_encoding_gaussian_matrix") || k.ends_with("rope_embed.periods") {
                cpu.insert(k.clone(), tensor_f64(&v)?);
            }
            let v = if k.starts_with("backbone.") { v.to_dtype(bb_dtype) } else { v.to_dtype(DType::F32) }.map_err(e)?;
            w.insert(k, v);
        }
        // LinearKMaskedBias: the K third of the qkv bias is masked out.
        for i in 0..BB_DEPTH {
            let b = format!("backbone.encoder.blocks.{i}.attn.qkv.bias");
            let m = format!("backbone.encoder.blocks.{i}.attn.qkv.bias_mask");
            let masked = w[&b].broadcast_mul(&w[&m].nan_to_num_zero()?).map_err(e)?;
            w.insert(b, masked);
        }
        let get = |p: &str| { let p = p.to_string(); let cpu = &cpu; move |n: &str| -> R<Vec<f64>> { cpu.get(&format!("{p}.{n}")).cloned().ok_or_else(|| format!("SAM 3D Body 權重缺少 {p}.{n}")) } };
        let km = cpu.get("head_pose.keypoint_mapping").ok_or("SAM 3D Body 權重缺少 head_pose.keypoint_mapping")?;
        let rig = Rig::load(mhr, km, dev)?;
        let head = Head::load(&get("head_pose"), &rig, false)?;
        let head_hand = Head::load(&get("head_pose_hand"), &rig, true)?;
        // DINOv3 RoPE ("separate" normalization, eval: no shift/jitter/rescale).
        let periods = &cpu["backbone.encoder.rope_embed.periods"];
        let nf = periods.len(); // 16
        let mut sin = Vec::with_capacity(NPATCH * nf * 4);
        let mut cos = Vec::with_capacity(NPATCH * nf * 4);
        for i in 0..GRID {
            for j in 0..GRID {
                let c = [2. * ((i as f32 + 0.5) / GRID as f32) - 1., 2. * ((j as f32 + 0.5) / GRID as f32) - 1.];
                let ang: Vec<f32> = (0..2).flat_map(|a| (0..nf).map(move |k| (a, k))).map(|(a, k)| 2. * std::f32::consts::PI * c[a] / periods[k] as f32).collect();
                for _ in 0..2 {
                    sin.extend(ang.iter().map(|v| v.sin()));
                    cos.extend(ang.iter().map(|v| v.cos()));
                }
            }
        }
        let hd = BB_DIM / BB_HEADS;
        let rope = (Tensor::from_vec(sin, (NPATCH, hd), dev).map_err(e)?, Tensor::from_vec(cos, (NPATCH, hd), dev).map_err(e)?);
        let pe_body = Tensor::from_vec(dense_pe(&cpu["prompt_encoder.pe_layer.positional_encoding_gaussian_matrix"]), (1, NPATCH, BB_DIM), dev).map_err(e)?;
        let pe_hand = Tensor::from_vec(dense_pe(&cpu["hand_pe_layer.positional_encoding_gaussian_matrix"]), (1, NPATCH, BB_DIM), dev).map_err(e)?;
        Ok(Model { w, bb_dtype, rig, head, head_hand, rope, pe_body, pe_hand, dev: dev.clone() })
    }

    fn p(&self, k: &str) -> R<&Tensor> { self.w.get(k).ok_or_else(|| format!("SAM 3D Body 權重缺少 {k}")) }
    fn linear(&self, x: &Tensor, name: &str) -> R<Tensor> {
        let x = &x.contiguous().map_err(e)?;
        let y = x.broadcast_matmul(&self.p(&format!("{name}.weight"))?.t().map_err(e)?).map_err(e)?;
        match self.w.get(&format!("{name}.bias")) {
            Some(b) => y.broadcast_add(b).map_err(e),
            None => Ok(y),
        }
    }
    fn ln(&self, x: &Tensor, name: &str, eps: f32) -> R<Tensor> {
        candle_nn::ops::layer_norm(x, self.p(&format!("{name}.weight"))?, self.p(&format!("{name}.bias"))?, eps).map_err(e)
    }
    /// transformer.FFN with ReLU, no identity: layers.0.0 → relu → layers.1
    fn ffn(&self, x: &Tensor, name: &str) -> R<Tensor> {
        let h = self.linear(x, &format!("{name}.layers.0.0"))?.relu().map_err(e)?;
        self.linear(&h, &format!("{name}.layers.1"))
    }

    // ------------------------------------------------------------ backbone

    /// DINOv3 ViT-H+/16 get_intermediate_layers(n=1, reshape, norm) → (B, 1024, 1280) f32.
    fn backbone(&self, x: &Tensor) -> R<Tensor> {
        let b = x.dim(0).map_err(e)?;
        let pre = "backbone.encoder";
        let x = x.to_dtype(self.bb_dtype).map_err(e)?;
        let x = x
            .conv2d(self.p(&format!("{pre}.patch_embed.proj.weight"))?, 0, PATCH, 1, 1)
            .and_then(|t| t.broadcast_add(&self.w[&format!("{pre}.patch_embed.proj.bias")].reshape((1, BB_DIM, 1, 1))?))
            .and_then(|t| t.flatten_from(2))
            .and_then(|t| t.transpose(1, 2))
            .map_err(e)?;
        let cls = self.p(&format!("{pre}.cls_token"))?.broadcast_as((b, 1, BB_DIM)).map_err(e)?;
        let reg = self.p(&format!("{pre}.storage_tokens"))?.broadcast_as((b, 4, BB_DIM)).map_err(e)?;
        let mut x = Tensor::cat(&[&cls, &reg, &x], 1).and_then(|t| t.contiguous()).map_err(e)?;
        let n = x.dim(1).map_err(e)?;
        let hd = BB_DIM / BB_HEADS;
        for i in 0..BB_DEPTH {
            let bp = format!("{pre}.blocks.{i}");
            let h = self.ln(&x, &format!("{bp}.norm1"), 1e-5)?;
            let qkv = self.linear(&h, &format!("{bp}.attn.qkv"))?.reshape((b, n, 3, BB_HEADS, hd)).map_err(e)?;
            let part = |k: usize| qkv.narrow(2, k, 1).and_then(|t| t.squeeze(2)).and_then(|t| t.transpose(1, 2)).map_err(e);
            let (q, k, v) = (self.rope(&part(0)?)?, self.rope(&part(1)?)?, part(2)?.contiguous().map_err(e)?);
            let s = (q.matmul(&k.t().map_err(e)?).map_err(e)? * (1. / (hd as f64).sqrt())).map_err(e)?;
            let a = candle_nn::ops::softmax_last_dim(&s).and_then(|t| t.matmul(&v)).and_then(|t| t.transpose(1, 2)).and_then(|t| t.reshape((b, n, BB_DIM))).map_err(e)?;
            let a = self.linear(&a, &format!("{bp}.attn.proj"))?;
            x = (x + a.broadcast_mul(self.p(&format!("{bp}.ls1.gamma"))?).map_err(e)?).map_err(e)?;
            let h = self.ln(&x, &format!("{bp}.norm2"), 1e-5)?;
            let g = (self.linear(&h, &format!("{bp}.mlp.w1"))?.silu().map_err(e)? * self.linear(&h, &format!("{bp}.mlp.w2"))?).map_err(e)?;
            let m = self.linear(&g, &format!("{bp}.mlp.w3"))?;
            x = (x + m.broadcast_mul(self.p(&format!("{bp}.ls2.gamma"))?).map_err(e)?).map_err(e)?;
        }
        let x = self.ln(&x, &format!("{pre}.norm"), 1e-5)?;
        x.narrow(1, BB_PREFIX, NPATCH).and_then(|t| t.to_dtype(DType::F32)).map_err(e)
    }

    /// RoPE on the patch tokens (prefix tokens untouched), computed in f32 like the release.
    fn rope(&self, t: &Tensor) -> R<Tensor> {
        let dt = t.dtype();
        let t = t.to_dtype(DType::F32).map_err(e)?;
        let (b, h, n, d) = t.dims4().map_err(e)?;
        let prefix = t.narrow(2, 0, BB_PREFIX).map_err(e)?;
        let x = t.narrow(2, BB_PREFIX, n - BB_PREFIX).map_err(e)?;
        let x1 = x.narrow(3, 0, d / 2).map_err(e)?;
        let x2 = x.narrow(3, d / 2, d / 2).map_err(e)?;
        let rot = Tensor::cat(&[&x2.neg().map_err(e)?, &x1], 3).map_err(e)?;
        let y = (x.broadcast_mul(&self.rope.1).map_err(e)? + rot.broadcast_mul(&self.rope.0).map_err(e)?).map_err(e)?;
        let _ = (b, h);
        Tensor::cat(&[&prefix, &y], 2).and_then(|t| t.to_dtype(dt)).and_then(|t| t.contiguous()).map_err(e)
    }

    // ------------------------------------------------------------ decoder

    /// transformer.Attention (8 heads × 64) without mask.
    fn attention(&self, q: &Tensor, k: &Tensor, v: &Tensor, name: &str) -> R<Tensor> {
        let (b, nq, _) = q.dims3().map_err(e)?;
        let nk = k.dim(1).map_err(e)?;
        let hd = 64;
        let split = |t: Tensor, n: usize| t.reshape((b, n, DEC_HEADS, hd)).and_then(|t| t.transpose(1, 2)).and_then(|t| t.contiguous()).map_err(e);
        let q = split(self.linear(q, &format!("{name}.q_proj"))?, nq)?;
        let k = split(self.linear(k, &format!("{name}.k_proj"))?, nk)?;
        let v = split(self.linear(v, &format!("{name}.v_proj"))?, nk)?;
        let s = (q.matmul(&k.t().map_err(e)?).map_err(e)? * (1. / (hd as f64).sqrt())).map_err(e)?;
        let a = candle_nn::ops::softmax_last_dim(&s).and_then(|t| t.matmul(&v)).and_then(|t| t.transpose(1, 2)).and_then(|t| t.reshape((b, nq, DEC_HEADS * hd))).map_err(e)?;
        self.linear(&a, &format!("{name}.proj"))
    }

    /// TransformerDecoderLayer (repeat_pe, no two-way).
    fn layer(&self, x: &Tensor, ctx: &Tensor, x_pe: &Tensor, ctx_pe: &Tensor, name: &str, first: bool) -> R<Tensor> {
        let x_pe = self.ln(x_pe, &format!("{name}.ln_pe_1"), 1e-6)?;
        let ctx_pe = self.ln(ctx_pe, &format!("{name}.ln_pe_2"), 1e-6)?;
        let h = self.ln(x, &format!("{name}.ln1"), 1e-6)?;
        let qk = if first { h.clone() } else { (&h + &x_pe).map_err(e)? };
        let x = (x + self.attention(&qk, &qk, &h, &format!("{name}.self_attn"))?).map_err(e)?;
        let q = (self.ln(&x, &format!("{name}.ln2_1"), 1e-6)? + &x_pe).map_err(e)?;
        let c = self.ln(ctx, &format!("{name}.ln2_2"), 1e-6)?;
        let k = c.broadcast_add(&ctx_pe).map_err(e)?;
        let x = (&x + self.attention(&q, &k, &c, &format!("{name}.cross_attn"))?).map_err(e)?;
        let h = self.ln(&x, &format!("{name}.ln3"), 1e-6)?;
        let f = self.linear(&h, &format!("{name}.ffn.layers.0.0"))?.gelu_erf().map_err(e)?;
        (&x + self.linear(&f, &format!("{name}.ffn.layers.1"))?).map_err(e)
    }

    /// forward_decoder / forward_decoder_hand for a batch of crops with their image embeddings.
    /// Returns (pose token after norm_final (B,1024), hand-detect tokens (B,2,1024)).
    fn decode(&self, emb: &Tensor, crops: &[Crop], k: &[f64; 9], hand: bool, trace: &mut Option<&mut Trace>) -> R<(Tensor, Tensor)> {
        let b = crops.len();
        let sfx = if hand { "_hand" } else { "" };
        let dec = if hand { "decoder_hand" } else { "decoder" };
        let dev = &self.dev;
        // Mask prompt (none) then CameraEncoder.
        let emb = emb.broadcast_add(self.p("prompt_encoder.no_mask_embed.weight")?).map_err(e)?;
        let rays: Vec<f32> = crops.iter().flat_map(|c| ray_features(&c.affine, k)).collect();
        let rays = Tensor::from_vec(rays, (b, NPATCH, 99), dev).map_err(e)?;
        let z = Tensor::cat(&[&emb, &rays], 2).map_err(e)?;
        let wconv = self.p(&format!("ray_cond_emb{sfx}.conv.weight"))?.reshape((BB_DIM, BB_DIM + 99)).map_err(e)?;
        let img = z.broadcast_matmul(&wconv.t().map_err(e)?).map_err(e)?;
        let img = self.ln(&img, &format!("ray_cond_emb{sfx}.norm"), 1e-6)?;
        if let Some(t) = trace.as_deref_mut() {
            t.insert(format!("ray{sfx}"), img.flatten_all().and_then(|t| t.to_vec1()).map_err(e)?);
        }
        let img_pe = if hand { &self.pe_hand } else { &self.pe_body };

        // Tokens.
        let init_pose = self.p(&format!("init_pose{sfx}.weight"))?; // (1, 519)
        let init_cam = self.p(&format!("init_camera{sfx}.weight"))?; // (1, 3)
        let init_est = Tensor::cat(&[init_pose, init_cam], 1).map_err(e)?;
        let cond: Vec<f32> = crops
            .iter()
            .flat_map(|c| {
                let f = k[0] as f32;
                [(c.center[0] - k[2] as f32) / f, (c.center[1] - k[5] as f32) / f, c.scale[0] / f]
            })
            .collect();
        let cond = Tensor::from_vec(cond, (b, 3), dev).map_err(e)?;
        let init_in = Tensor::cat(&[&cond, &init_est.broadcast_as((b, 522)).map_err(e)?], 1).map_err(e)?;
        let t0 = self.linear(&init_in, &format!("init_to_token_mhr{sfx}"))?.unsqueeze(1).map_err(e)?;
        let t1 = self.linear(&init_est, &format!("prev_to_token_mhr{sfx}"))?.unsqueeze(1).and_then(|t| t.broadcast_as((b, 1, DEC))).map_err(e)?;
        let t2 = self.linear(self.p("prompt_encoder.invalid_point_embed.weight")?, "prompt_to_token")?.unsqueeze(1).and_then(|t| t.broadcast_as((b, 1, DEC))).map_err(e)?;
        let hb = self.p("hand_box_embedding.weight")?.unsqueeze(0).and_then(|t| t.broadcast_as((b, 2, DEC))).map_err(e)?;
        let kp = self.p(&format!("keypoint_embedding{sfx}.weight"))?.unsqueeze(0).and_then(|t| t.broadcast_as((b, NKP, DEC))).map_err(e)?;
        let kp3 = self.p(&format!("keypoint3d_embedding{sfx}.weight"))?.unsqueeze(0).and_then(|t| t.broadcast_as((b, NKP, DEC))).map_err(e)?;
        let mut x = Tensor::cat(&[&t0, &t1, &t2, &hb, &kp, &kp3], 1).and_then(|t| t.contiguous()).map_err(e)?;
        let z1 = Tensor::zeros((b, 1, DEC), DType::F32, dev).map_err(e)?;
        let zrest = Tensor::zeros((b, NTOK - 3, DEC), DType::F32, dev).map_err(e)?;
        let mut aug = Tensor::cat(&[&z1, &t1, &t2, &zrest], 1).and_then(|t| t.contiguous()).map_err(e)?;

        let head = if hand { &self.head_hand } else { &self.head };
        let scale_factor = if hand { 10. } else { 1. };
        for li in 0..DEC_LAYERS {
            x = self.layer(&x, &img, &aug, img_pe, &format!("{dec}.layers.{li}"), li == 0)?;
            if let Some(t) = trace.as_deref_mut() {
                t.insert(format!("{dec}_l{li}"), x.flatten_all().and_then(|t| t.to_vec1()).map_err(e)?);
            }
            if li == DEC_LAYERS - 1 {
                break;
            }
            // token_to_pose_output_fn on norm_final(x), then the 2D / 3D keypoint token updates.
            let tok = self.ln(&x, &format!("{dec}.norm_final"), 1e-6)?.narrow(1, 0, 1).and_then(|t| t.squeeze(1)).map_err(e)?;
            let pred = self.ffn(&tok, &format!("head_pose{sfx}.proj"))?.broadcast_add(init_pose).map_err(e)?;
            let cam = self.ffn(&tok, &format!("head_camera{sfx}.proj"))?.broadcast_add(init_cam).map_err(e)?;
            let pred: Vec<Vec<f64>> = pred.to_dtype(DType::F64).and_then(|t| t.to_vec2()).map_err(e)?;
            let cam: Vec<Vec<f64>> = cam.to_dtype(DType::F64).and_then(|t| t.to_vec2()).map_err(e)?;
            let (kp3d, params) = head.keypoints_params(&self.rig, &pred)?;
            if let Some(t) = trace.as_deref_mut() {
                t.insert(format!("kp3d{sfx}_l{li}"), kp3d.iter().flatten().flatten().map(|v| *v as f32).collect());
                t.insert(format!("params{sfx}_l{li}"), params.iter().flatten().map(|v| *v as f32).collect());
                t.insert(format!("pred{sfx}_l{li}"), pred.iter().flatten().map(|v| *v as f32).collect());
            }
            let mut pe2 = Vec::with_capacity(b * NKP * 2);
            let mut valid = Vec::with_capacity(b * NKP);
            let mut samp = vec![0f32; b * NKP * NPATCH];
            let mut pe3 = Vec::with_capacity(b * NKP * 3);
            for (i, c) in crops.iter().enumerate() {
                // PerspectiveHead.perspective_projection (use_intrin_center)
                let (s, tx, ty) = (-cam[i][0], cam[i][1], -cam[i][2]);
                let bs = c.scale[0] as f64 * s * scale_factor + 1e-8;
                let tz = 2. * k[0] / bs;
                let cx = 2. * (c.center[0] as f64 - k[2]) / bs;
                let cy = 2. * (c.center[1] as f64 - k[5]) / bs;
                let t = [tx + cx, ty + cy, tz];
                let pel = [0, 1, 2].map(|a| (kp3d[i][9][a] + kp3d[i][10][a]) / 2.);
                for (j, p) in kp3d[i].iter().enumerate() {
                    let q = [p[0] + t[0], p[1] + t[1], p[2] + t[2]];
                    let (u, v) = (k[0] * q[0] / q[2] + k[1] * q[1] / q[2] + k[2], k[3] * q[0] / q[2] + k[4] * q[1] / q[2] + k[5]);
                    let a = &c.affine;
                    let cu = (u * a[0][0] + v * a[0][1] + a[0][2]) / IMG as f64 - 0.5;
                    let cv = (u * a[1][0] + v * a[1][1] + a[1][2]) / IMG as f64 - 0.5;
                    let ok = !(cu + 0.5 < 0. || cu + 0.5 > 1. || cv + 0.5 < 0. || cv + 0.5 > 1. || q[2] < 1e-5);
                    pe2.extend([cu as f32, cv as f32]);
                    valid.push(if ok { 1f32 } else { 0. });
                    // grid_sample(bilinear, zeros, align_corners=False) at (2cu, 2cv) on the 32×32 grid.
                    if ok {
                        let ix = ((2. * cu + 1.) * GRID as f64 - 1.) / 2.;
                        let iy = ((2. * cv + 1.) * GRID as f64 - 1.) / 2.;
                        let (x0, y0) = (ix.floor(), iy.floor());
                        let (fx, fy) = (ix - x0, iy - y0);
                        for (dx, dy, wgt) in [(0, 0, (1. - fx) * (1. - fy)), (1, 0, fx * (1. - fy)), (0, 1, (1. - fx) * fy), (1, 1, fx * fy)] {
                            let (xx, yy) = (x0 as i64 + dx, y0 as i64 + dy);
                            if xx >= 0 && yy >= 0 && (xx as usize) < GRID && (yy as usize) < GRID {
                                samp[(i * NKP + j) * NPATCH + yy as usize * GRID + xx as usize] += wgt as f32;
                            }
                        }
                    }
                    pe3.extend([(p[0] - pel[0]) as f32, (p[1] - pel[1]) as f32, (p[2] - pel[2]) as f32]);
                }
            }
            let valid = Tensor::from_vec(valid, (b, NKP, 1), dev).map_err(e)?;
            let pe2 = Tensor::from_vec(pe2, (b, NKP, 2), dev).map_err(e)?;
            let pe3 = Tensor::from_vec(pe3, (b, NKP, 3), dev).map_err(e)?;
            let samp = Tensor::from_vec(samp, (b, NKP, NPATCH), dev).map_err(e)?;
            let aug2 = self.ffn(&pe2, &format!("keypoint_posemb_linear{sfx}"))?.broadcast_mul(&valid).map_err(e)?;
            let feats = samp.matmul(&img).map_err(e)?; // invalid rows are zero already
            let add = self.linear(&feats, &format!("keypoint_feat_linear{sfx}"))?;
            let aug3 = self.ffn(&pe3, &format!("keypoint3d_posemb_linear{sfx}"))?;
            let xk = (x.narrow(1, KP2D, NKP).map_err(e)? + add).map_err(e)?;
            x = Tensor::cat(&[&x.narrow(1, 0, KP2D).map_err(e)?, &xk, &x.narrow(1, KP3D, NKP).map_err(e)?], 1).and_then(|t| t.contiguous()).map_err(e)?;
            aug = Tensor::cat(&[&aug.narrow(1, 0, KP2D).map_err(e)?, &aug2, &aug3], 1).and_then(|t| t.contiguous()).map_err(e)?;
        }
        let out = self.ln(&x, &format!("{dec}.norm_final"), 1e-6)?;
        if let Some(t) = trace.as_deref_mut() {
            t.insert(format!("{dec}_out"), out.flatten_all().and_then(|t| t.to_vec1()).map_err(e)?);
        }
        let tok = out.narrow(1, 0, 1).and_then(|t| t.squeeze(1)).map_err(e)?;
        let handdet = out.narrow(1, 3, 2).map_err(e)?;
        Ok((tok, handdet))
    }

    /// bbox_embed MLP (relu, relu, linear) + sigmoid → (x, y, w, h) in 0..1 of the body crop.
    fn hand_boxes(&self, handdet: &Tensor) -> R<Vec<[[f64; 4]; 2]>> {
        let mut h = handdet.clone();
        for l in 0..3 {
            h = self.linear(&h, &format!("bbox_embed.layers.{l}"))?;
            if l < 2 {
                h = h.relu().map_err(e)?;
            }
        }
        let v: Vec<Vec<Vec<f64>>> = candle_nn::ops::sigmoid(&h).and_then(|t| t.to_dtype(DType::F64)).and_then(|t| t.to_vec3()).map_err(e)?;
        Ok(v.iter().map(|b| [0, 1].map(|s| [b[s][0], b[s][1], b[s][2], b[s][3]])).collect())
    }

    /// Pose tokens (frames × 3072: body, left hand, right hand) for RGB frames with one person box (xyxy) each.
    pub fn tokens(&self, frames: &[&[u8]], w: usize, h: usize, boxes: &[[f32; 4]], k: &[f64; 9], mut trace: Option<&mut Trace>) -> R<Vec<f32>> {
        let n = frames.len();
        let mk = |img: &[u8], b: [f32; 4], pad: f32, flip: bool| {
            let (center, scale, affine) = crop_geometry(b, pad);
            Crop { center, scale, pixels: warp(img, w, h, &affine, flip), affine }
        };
        let body: Vec<Crop> = frames.iter().zip(boxes).map(|(f, b)| mk(f, *b, 1.25, false)).collect();
        let x = Tensor::from_vec(body.iter().flat_map(|c| c.pixels.iter().copied()).collect::<Vec<f32>>(), (n, 3, IMG, IMG), &self.dev).map_err(e)?;
        if let Some(t) = trace.as_deref_mut() {
            t.insert("body_img".into(), body[0].pixels.clone());
        }
        let emb = self.backbone(&x)?;
        if let Some(t) = trace.as_deref_mut() {
            t.insert("backbone".into(), emb.flatten_all().and_then(|t| t.to_vec1()).map_err(e)?);
        }
        let (tok_body, handdet) = self.decode(&emb, &body, k, false, &mut trace)?;
        // _get_hand_box: crop-space boxes → squares in the full image; the left hand runs on the mirrored image.
        let hb = self.hand_boxes(&handdet)?;
        let mut hands = Vec::with_capacity(2 * n);
        for side in 0..2 {
            for (i, c) in body.iter().enumerate() {
                // numpy float32 like the release (hand_box and affine_trans are float32 there)
                let bx = hb[i][side].map(|v| v as f32 * IMG as f32);
                let a = c.affine.map(|r| r.map(|v| v as f32));
                let sc = bx[2].max(bx[3]) / a[0][0];
                let cx = (bx[0] - a[0][2]) / a[0][0];
                let cy = (bx[1] - a[1][2]) / a[0][0];
                let xyxy = [cx - sc * 1. / 2., cy - sc * 1. / 2., cx + sc * 1. / 2., cy + sc * 1. / 2.];
                let flip = side == 0;
                let xyxy = if flip { [w as f32 - xyxy[2] - 1., xyxy[1], w as f32 - xyxy[0] - 1., xyxy[3]] } else { xyxy };
                if let Some(t) = trace.as_deref_mut() {
                    t.insert(format!("hand_xyxy_{side}"), xyxy.to_vec());
                }
                hands.push(mk(frames[i], xyxy, 0.9, flip));
            }
        }
        if let Some(t) = trace.as_deref_mut() {
            t.insert("hand_img_0".into(), hands[0].pixels.clone());
        }
        let x = Tensor::from_vec(hands.iter().flat_map(|c| c.pixels.iter().copied()).collect::<Vec<f32>>(), (2 * n, 3, IMG, IMG), &self.dev).map_err(e)?;
        let emb = self.backbone(&x)?;
        if let Some(t) = trace.as_deref_mut() {
            t.insert("backbone_hand".into(), emb.narrow(0, 0, 1).and_then(|t| t.flatten_all()).and_then(|t| t.to_vec1()).map_err(e)?);
        }
        let (tok_hand, _) = self.decode(&emb, &hands, k, true, &mut trace)?;
        let lh = tok_hand.narrow(0, 0, n).map_err(e)?;
        let rh = tok_hand.narrow(0, n, n).map_err(e)?;
        Tensor::cat(&[&tok_body, &lh, &rh], 1).and_then(|t| t.flatten_all()).and_then(|t| t.to_vec1()).map_err(e)
    }
}

trait NanZero {
    fn nan_to_num_zero(&self) -> R<Tensor>;
}
impl NanZero for Tensor {
    /// bias_mask is 1 for q/v and 0 for k (NaN only before loading).
    fn nan_to_num_zero(&self) -> R<Tensor> {
        let v: Vec<f32> = self.to_dtype(DType::F32).and_then(|t| t.to_vec1()).map_err(e)?;
        Tensor::from_vec(v.iter().map(|x| if x.is_nan() { 0. } else { *x }).collect::<Vec<f32>>(), self.shape(), self.device()).and_then(|t| t.to_dtype(self.dtype())).map_err(e)
    }
}
