//! DINOv3 ViT-L/16 (facebook/dinov3-vitl16-pretrain-lvd1689m, transformers layout) as HairDeck's image encoder
//! (hairdeck.models.imgmodel.DinoEncoder): uint8 crop (res x res) -> CLS, 4 storage tokens and the patch tokens, all
//! after the final norm. Like hub_state_dict: no k bias, RoPE base 100 with the periods rounded to bfloat16.
use crate::nn::{e, heads, merge, sdpa, Weights, R};
use candle_core::{Device, Tensor};
use std::path::Path;

const DIM: usize = 1024;
const DEPTH: usize = 24;
const HEADS: usize = 16;
const PATCH: usize = 16;
const PREFIX: usize = 5;
const MEAN: [f32; 3] = [0.485, 0.456, 0.406];
const STD: [f32; 3] = [0.229, 0.224, 0.225];

pub struct Dino {
    w: Weights,
    res: usize,
    sin: Tensor,
    cos: Tensor,
    dev: Device,
}

fn bf16_round(x: f32) -> f32 {
    // round to nearest even on the upper 16 bits
    let b = x.to_bits();
    let r = b.wrapping_add(0x7FFF + ((b >> 16) & 1)) & 0xFFFF_0000;
    f32::from_bits(r)
}

impl Dino {
    pub fn load(path: &Path, res: usize, dev: &Device) -> R<Dino> {
        let w = Weights::load(path, dev, "DINOv3")?;
        w.p("layer.23.mlp.down_proj.weight")?;
        let grid = res / PATCH;
        let hd = DIM / HEADS;
        let periods: Vec<f32> = (0..hd / 4).map(|k| bf16_round(100f32.powf(2.0 * k as f32 / (hd / 2) as f32))).collect();
        let (mut sin, mut cos) = (Vec::with_capacity(grid * grid * hd), Vec::with_capacity(grid * grid * hd));
        for i in 0..grid {
            for j in 0..grid {
                let c = [2.0 * ((i as f32 + 0.5) / grid as f32) - 1.0, 2.0 * ((j as f32 + 0.5) / grid as f32) - 1.0];
                let ang: Vec<f32> = (0..2).flat_map(|a| periods.iter().map(move |p| 2.0 * std::f32::consts::PI * c[a] / p)).collect();
                for _ in 0..2 {
                    sin.extend(ang.iter().map(|v| v.sin()));
                    cos.extend(ang.iter().map(|v| v.cos()));
                }
            }
        }
        let sin = Tensor::from_vec(sin, (grid * grid, hd), dev).map_err(e)?;
        let cos = Tensor::from_vec(cos, (grid * grid, hd), dev).map_err(e)?;
        Ok(Dino { w, res, sin, cos, dev: dev.clone() })
    }
    pub fn n_tokens(&self) -> usize { PREFIX + (self.res / PATCH).pow(2) }

    fn rope(&self, t: &Tensor) -> R<Tensor> {
        let n = t.dim(2).map_err(e)?;
        let d = t.dim(3).map_err(e)?;
        let prefix = t.narrow(2, 0, PREFIX).map_err(e)?;
        let x = t.narrow(2, PREFIX, n - PREFIX).map_err(e)?;
        let x1 = x.narrow(3, 0, d / 2).map_err(e)?;
        let x2 = x.narrow(3, d / 2, d / 2).map_err(e)?;
        let rot = Tensor::cat(&[&x2.neg().map_err(e)?, &x1], 3).map_err(e)?;
        let y = (x.broadcast_mul(&self.cos).map_err(e)? + rot.broadcast_mul(&self.sin).map_err(e)?).map_err(e)?;
        Tensor::cat(&[&prefix, &y], 2).and_then(|t| t.contiguous()).map_err(e)
    }

    /// crop: RGB bytes res x res -> (1, n_tokens, 1024)
    pub fn forward(&self, crop: &[u8]) -> R<Tensor> {
        let res = self.res;
        if crop.len() != res * res * 3 { return Err("DINOv3 輸入大小不對".into()); }
        let mut v = vec![0f32; 3 * res * res];
        for y in 0..res {
            for x in 0..res {
                for c in 0..3 {
                    v[c * res * res + y * res + x] = (crop[(y * res + x) * 3 + c] as f32 / 255.0 - MEAN[c]) / STD[c];
                }
            }
        }
        let w = &self.w;
        let img = Tensor::from_vec(v, (1, 3, res, res), &self.dev).map_err(e)?;
        let x = img.conv2d(w.p("embeddings.patch_embeddings.weight")?, 0, PATCH, 1, 1)
            .and_then(|t| t.broadcast_add(&w.w["embeddings.patch_embeddings.bias"].reshape((1, DIM, 1, 1))?))
            .and_then(|t| t.flatten_from(2)).and_then(|t| t.transpose(1, 2)).map_err(e)?;
        let cls = w.p("embeddings.cls_token")?.reshape((1, 1, DIM)).map_err(e)?;
        let reg = w.p("embeddings.register_tokens")?.reshape((1, 4, DIM)).map_err(e)?;
        let mut x = Tensor::cat(&[&cls, &reg, &x], 1).and_then(|t| t.contiguous()).map_err(e)?;
        for i in 0..DEPTH {
            let p = format!("layer.{i}");
            let h = w.ln(&x, &format!("{p}.norm1"), 1e-5)?;
            let q = self.rope(&heads(&w.linear(&h, &format!("{p}.attention.q_proj"))?, HEADS)?)?;
            // the transformers file has no k bias; the original checkpoint masks it out (mask_k_bias)
            let k = h.broadcast_matmul(&w.p(&format!("{p}.attention.k_proj.weight"))?.t().map_err(e)?).map_err(e)?;
            let k = self.rope(&heads(&k, HEADS)?)?;
            let v = heads(&w.linear(&h, &format!("{p}.attention.v_proj"))?, HEADS)?;
            let a = w.linear(&merge(&sdpa(&q, &k, &v, None)?)?, &format!("{p}.attention.o_proj"))?;
            x = (x + a.broadcast_mul(w.p(&format!("{p}.layer_scale1.lambda1"))?).map_err(e)?).map_err(e)?;
            let h = w.ln(&x, &format!("{p}.norm2"), 1e-5)?;
            let m = w.linear(&w.linear(&h, &format!("{p}.mlp.up_proj"))?.gelu_erf().map_err(e)?, &format!("{p}.mlp.down_proj"))?;
            x = (x + m.broadcast_mul(w.p(&format!("{p}.layer_scale2.lambda1"))?).map_err(e)?).map_err(e)?;
        }
        w.ln(&x, "norm", 1e-5)
    }
}
