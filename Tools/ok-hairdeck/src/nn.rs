//! Weights and the few layers the HairDeck networks use, on candle tensors (f32).
use candle_core::{DType, Device, Tensor, D};
use std::collections::HashMap;
use std::path::Path;

pub type R<T> = Result<T, String>;
pub fn e<E: std::fmt::Display>(x: E) -> String { x.to_string() }

pub struct Weights {
    pub w: HashMap<String, Tensor>,
    pub what: String,
    pub meta: serde_json::Value,
}

impl Weights {
    /// A safetensors file as f32 tensors on `dev`, with its `hairdeck` metadata (args) when present.
    pub fn load(path: &Path, dev: &Device, what: &str) -> R<Weights> {
        let bytes = std::fs::read(path).map_err(|x| format!("{}：{x}", path.display()))?;
        let (_, md) = safetensors::SafeTensors::read_metadata(&bytes).map_err(|x| format!("{}：{x}", path.display()))?;
        let meta = md.metadata().as_ref().and_then(|m| m.get("hairdeck")).and_then(|s| serde_json::from_str(s).ok()).unwrap_or(serde_json::Value::Null);
        let raw = candle_core::safetensors::load_buffer(&bytes, dev).map_err(|x| format!("{}：{x}", path.display()))?;
        let mut w = HashMap::new();
        for (k, v) in raw {
            let v = if v.dtype() == DType::I64 || v.dtype() == DType::U8 { v } else { v.to_dtype(DType::F32).map_err(e)? };
            w.insert(k, v);
        }
        Ok(Weights { w, what: what.into(), meta })
    }
    pub fn p(&self, k: &str) -> R<&Tensor> { self.w.get(k).ok_or_else(|| format!("{} 權重缺少 {k}", self.what)) }
    pub fn has(&self, k: &str) -> bool { self.w.contains_key(k) }
    pub fn arg_usize(&self, k: &str) -> R<usize> {
        self.meta["args"][k].as_u64().map(|v| v as usize).ok_or_else(|| format!("{} 的設定缺少 {k}", self.what))
    }
    /// x W^T + b (bias when the file has one).
    pub fn linear(&self, x: &Tensor, name: &str) -> R<Tensor> {
        let x = x.contiguous().map_err(e)?;
        let y = x.broadcast_matmul(&self.p(&format!("{name}.weight"))?.t().map_err(e)?).map_err(e)?;
        match self.w.get(&format!("{name}.bias")) {
            Some(b) => y.broadcast_add(b).map_err(e),
            None => Ok(y),
        }
    }
    pub fn ln(&self, x: &Tensor, name: &str, eps: f64) -> R<Tensor> {
        let y = ln_plain(x, eps)?;
        y.broadcast_mul(self.p(&format!("{name}.weight"))?).and_then(|t| t.broadcast_add(&self.w[&format!("{name}.bias")])).map_err(e)
    }
    /// RMSNorm with weight `name.w` (setdit.RMSNorm), eps 1e-6.
    pub fn rms(&self, x: &Tensor, name: &str) -> R<Tensor> {
        let ms = x.sqr().and_then(|t| t.mean_keepdim(D::Minus1)).map_err(e)?;
        let y = x.broadcast_div(&(ms + 1e-6).and_then(|t| t.sqrt()).map_err(e)?).map_err(e)?;
        y.broadcast_mul(self.p(&format!("{name}.w"))?).map_err(e)
    }
}

/// LayerNorm without affine parameters.
pub fn ln_plain(x: &Tensor, eps: f64) -> R<Tensor> {
    let mu = x.mean_keepdim(D::Minus1).map_err(e)?;
    let xc = x.broadcast_sub(&mu).map_err(e)?;
    let var = xc.sqr().and_then(|t| t.mean_keepdim(D::Minus1)).map_err(e)?;
    xc.broadcast_div(&(var + eps).and_then(|t| t.sqrt()).map_err(e)?).map_err(e)
}

/// softmax(q k^T / sqrt(d)) v for (B, H, N, d) tensors; `mask` (B, 1, 1, M) additive (0 / -inf) when given.
pub fn sdpa(q: &Tensor, k: &Tensor, v: &Tensor, mask: Option<&Tensor>) -> R<Tensor> {
    let d = q.dim(D::Minus1).map_err(e)?;
    let s = (q.contiguous().map_err(e)?.matmul(&k.t().and_then(|t| t.contiguous()).map_err(e)?).map_err(e)? * (1.0 / (d as f64).sqrt())).map_err(e)?;
    let s = match mask { Some(m) => s.broadcast_add(m).map_err(e)?, None => s };
    candle_nn::ops::softmax_last_dim(&s).and_then(|t| t.matmul(&v.contiguous()?)).map_err(e)
}

/// (B, N, H*d) -> (B, H, N, d)
pub fn heads(x: &Tensor, h: usize) -> R<Tensor> {
    let (b, n, c) = x.dims3().map_err(e)?;
    x.reshape((b, n, h, c / h)).and_then(|t| t.transpose(1, 2)).and_then(|t| t.contiguous()).map_err(e)
}
/// (B, H, N, d) -> (B, N, H*d)
pub fn merge(x: &Tensor) -> R<Tensor> {
    let (b, h, n, d) = x.dims4().map_err(e)?;
    x.transpose(1, 2).and_then(|t| t.reshape((b, n, h * d))).map_err(e)
}

/// x * (1 + scale[:, None]) + shift[:, None] for x (B, N, C), shift / scale (B, C).
pub fn modulate(x: &Tensor, shift: &Tensor, scale: &Tensor) -> R<Tensor> {
    let s = (scale.unsqueeze(1).map_err(e)? + 1.0).map_err(e)?;
    x.broadcast_mul(&s).and_then(|t| t.broadcast_add(&shift.unsqueeze(1)?)).map_err(e)
}

/// The `n` equal chunks of the last dimension.
pub fn chunks(x: &Tensor, n: usize) -> R<Vec<Tensor>> {
    let c = x.dim(D::Minus1).map_err(e)? / n;
    (0..n).map(|i| x.narrow(D::Minus1, i * c, c).and_then(|t| t.contiguous()).map_err(e)).collect()
}

/// setdit.timestep_embedding: (B,) -> (B, dim): cos, sin of t * 1000 * exp(-ln(10000) k / half).
pub fn timestep_embedding(t: &[f32], dim: usize, dev: &Device) -> R<Tensor> {
    let half = dim / 2;
    let mut v = Vec::with_capacity(t.len() * dim);
    for &tt in t {
        let args: Vec<f32> = (0..half).map(|k| tt * 1000.0 * (-(10000f32.ln()) * k as f32 / half as f32).exp()).collect();
        v.extend(args.iter().map(|a| a.cos()));
        v.extend(args.iter().map(|a| a.sin()));
    }
    Tensor::from_vec(v, (t.len(), dim), dev).map_err(e)
}

/// Standard normal noise from a seeded xorshift / Box-Muller stream (not torch's generator: use `--noise` files to
/// reproduce a Python run exactly).
pub fn randn(seed: u64, n: usize) -> Vec<f32> {
    let mut s = seed.wrapping_mul(0x9E3779B97F4A7C15) ^ 0xD1B54A32D192ED03;
    let mut next = || { s ^= s << 13; s ^= s >> 7; s ^= s << 17; ((s >> 11) as f64 + 0.5) / (1u64 << 53) as f64 };
    let mut out = Vec::with_capacity(n);
    while out.len() < n {
        let (u1, u2) = (next(), next());
        let r = (-2.0 * u1.ln()).sqrt();
        out.push((r * (std::f64::consts::TAU * u2).cos()) as f32);
        out.push((r * (std::f64::consts::TAU * u2).sin()) as f32);
    }
    out.truncate(n);
    out
}

/// A little-endian f32 .npy file (C order) -> values and shape.
pub fn read_npy(path: &Path) -> R<(Vec<f32>, Vec<usize>)> {
    let b = std::fs::read(path).map_err(|x| format!("{}：{x}", path.display()))?;
    if b.len() < 10 || &b[..6] != b"\x93NUMPY" { return Err(format!("{} 不是 npy", path.display())); }
    let (hl, start) = if b[6] == 1 { (u16::from_le_bytes([b[8], b[9]]) as usize, 10) } else { (u32::from_le_bytes([b[8], b[9], b[10], b[11]]) as usize, 12) };
    let h = String::from_utf8_lossy(&b[start..start + hl]).to_string();
    if !h.contains("'<f4'") || h.contains("'fortran_order': True") { return Err(format!("{}：只支援 C 順序的 <f4", path.display())); }
    let shape: Vec<usize> = h.split("'shape': (").nth(1).and_then(|s| s.split(')').next()).unwrap_or("")
        .split(',').filter_map(|x| x.trim().parse().ok()).collect();
    let data = &b[start + hl..];
    Ok((data.chunks_exact(4).map(|c| f32::from_le_bytes(c.try_into().unwrap())).collect(), shape))
}
