//! Card tokens -> cards (hairdeck.models.tokenizer, hairdeck.cards.tokens, the card VAE decoder of hairdeck.cards.vae)
//! and the chain token decoding (hairdeck.spring.chaindit.decode).
use crate::nn::{chunks, e, heads, ln_plain, merge, sdpa, Weights, R};
use candle_core::{Device, Tensor};
use std::path::Path;

fn json_vec(v: &serde_json::Value, k: &str) -> R<Vec<f32>> {
    v[k].as_array().ok_or_else(|| format!("統計檔缺少 {k}"))?.iter().map(|x| x.as_f64().map(|f| f as f32).ok_or_else(|| format!("{k} 不是數字"))).collect()
}
fn read_json(p: &Path) -> R<serde_json::Value> {
    serde_json::from_slice(&std::fs::read(p).map_err(|x| format!("{}：{x}", p.display()))?).map_err(|x| format!("{}：{x}", p.display()))
}

/// [root (3), latent (zdim), root width direction (3), shape class, existence]
pub struct Tokenizer { pub root_mu: Vec<f32>, pub root_sd: Vec<f32>, pub lmu: Vec<f32>, pub lsd: Vec<f32>, pub zdim: usize, pub dim: usize }
impl Tokenizer {
    pub fn load(stats_head: &Path, latent_stats_head: &Path) -> R<Tokenizer> {
        let s = read_json(stats_head)?;
        let l = read_json(latent_stats_head)?;
        let lmu = json_vec(&l, "mu")?;
        let zdim = lmu.len();
        Ok(Tokenizer { root_mu: json_vec(&s, "root_mu")?, root_sd: json_vec(&s, "root_sd")?, lsd: json_vec(&l, "sd")?, lmu, zdim, dim: 3 + zdim + 5 })
    }
    pub fn exist(&self, t: &[f32]) -> bool { t[self.dim - 1] > 0.0 }
    pub fn root(&self, t: &[f32]) -> [f64; 3] { std::array::from_fn(|k| (t[k] * self.root_sd[k] + self.root_mu[k]) as f64) }
    pub fn z(&self, t: &[f32]) -> Vec<f32> { (0..self.zdim).map(|k| t[3 + k] * self.lsd[k] + self.lmu[k]).collect() }
    pub fn nrm(&self, t: &[f32]) -> [f64; 3] { std::array::from_fn(|k| t[3 + self.zdim + k] as f64) }
    pub fn triangle(&self, t: &[f32]) -> bool { t[3 + self.zdim + 3] > 0.0 }

    /// clean_tokens: empty slots zeroed, existence and class snapped to +-1, root normal unit length.
    pub fn clean(&self, x: &[f32]) -> Vec<f32> {
        let mut y = x.to_vec();
        let (z, d) = (self.zdim, self.dim);
        for s in y.chunks_mut(d) {
            if s[d - 1] > 0.0 {
                let n = (s[3 + z].powi(2) + s[4 + z].powi(2) + s[5 + z].powi(2)).sqrt().max(1e-6);
                for k in 0..3 { s[3 + z + k] /= n; }
                let c = s[6 + z];
                s[6 + z] = if c > 0.0 { 1.0 } else if c < 0.0 { -1.0 } else { 1.0 };
                s[d - 1] = 1.0;
            } else {
                s.iter_mut().for_each(|v| *v = 0.0);
                s[d - 1] = -1.0;
            }
        }
        y
    }
    /// sign_token_normals: each existing card's root normal flipped where it points towards the mean card root.
    pub fn sign_normals(&self, x: &mut [f32]) {
        let d = self.dim;
        let roots: Vec<[f64; 3]> = x.chunks(d).filter(|s| self.exist(s)).map(|s| self.root(s)).collect();
        if roots.is_empty() { return; }
        let c: [f64; 3] = std::array::from_fn(|k| roots.iter().map(|r| r[k]).sum::<f64>() / roots.len() as f64);
        for s in x.chunks_mut(d) {
            if !self.exist(s) { continue; }
            let r = self.root(s);
            let n = self.nrm(s);
            if (0..3).map(|k| (n[k] as f32 as f64) * (r[k] - c[k])).sum::<f64>() < 0.0 {
                for k in 0..3 { s[3 + self.zdim + k] = -s[3 + self.zdim + k]; }
            }
        }
    }
}

pub struct CardVae { w: Weights, mu: Vec<f32>, sd: Vec<f32>, l: usize, nf: usize, depth: usize, dev: Device }
impl CardVae {
    pub fn load(dir: &Path, dev: &Device) -> R<CardVae> {
        let w = Weights::load(&dir.join("model.safetensors"), dev, "card VAE")?;
        let s = read_json(&dir.join("stats.json"))?;
        let l = w.arg_usize("L")?;
        let nf = w.arg_usize("nf").unwrap_or(16);
        let depth = w.arg_usize("depth")?;
        Ok(CardVae { mu: json_vec(&s, "mu")?, sd: json_vec(&s, "sd")?, l, nf, depth, w, dev: dev.clone() })
    }
    fn mlp2(&self, x: &Tensor, name: &str) -> R<Tensor> {
        self.w.linear(&self.w.linear(x, &format!("{name}.0"))?.silu().map_err(e)?, &format!("{name}.2"))
    }
    /// decode_cards: latents (one per card) and roots -> (n, 5) cards in the head frame.
    pub fn decode(&self, zs: &[Vec<f32>], roots: &[[f64; 3]]) -> R<Vec<Vec<[f64; 5]>>> {
        let zdim = zs.first().map_or(0, |z| z.len());
        let mut out = vec![Vec::new(); zs.len()];
        if zs.is_empty() { return Ok(out); }
        let z = Tensor::from_vec(zs.concat(), (zs.len(), zdim), &self.dev).map_err(e)?;
        let logits: Vec<Vec<f32>> = self.mlp2(&z, "n_head")?.to_vec2().map_err(e)?;
        let ns: Vec<usize> = logits.iter().map(|r| (r.iter().enumerate().max_by(|a, b| a.1.total_cmp(b.1)).unwrap().0 + 1).max(3)).collect();
        // cards of one point count decode together (no padding, so no attention mask)
        let mut groups: std::collections::BTreeMap<usize, Vec<usize>> = Default::default();
        for (i, n) in ns.iter().enumerate() { groups.entry(*n).or_default().push(i); }
        for (n, idx) in groups {
            let n = n.min(self.l);
            let zb = Tensor::from_vec(idx.iter().flat_map(|&i| zs[i].clone()).collect::<Vec<_>>(), (idx.len(), zdim), &self.dev).map_err(e)?;
            let c = self.mlp2(&zb, "from_z")?;
            let mut four = Vec::with_capacity(n * (1 + 2 * self.nf));
            for j in 0..n {
                let u = j as f32 / (n - 1).max(1) as f32;
                four.push(u);
                for k in 0..self.nf { four.push((u * 2f32.powi(k as i32) * std::f32::consts::PI).sin()); }
                for k in 0..self.nf { four.push((u * 2f32.powi(k as i32) * std::f32::consts::PI).cos()); }
            }
            let four = Tensor::from_vec(four, (1, n, 1 + 2 * self.nf), &self.dev).map_err(e)?;
            let mut h = self.w.linear(&four, "q_in")?.broadcast_add(&c.unsqueeze(1).map_err(e)?).map_err(e)?;
            let sc = c.silu().map_err(e)?;
            for i in 0..self.depth {
                let b = format!("dec.blocks.{i}");
                let m = chunks(&self.w.linear(&sc, &format!("{b}.ada"))?.unsqueeze(1).map_err(e)?, 6)?;
                let y = (ln_plain(&h, 1e-5)?.broadcast_mul(&(&m[1] + 1.0).map_err(e)?).map_err(e)? .broadcast_add(&m[0])).map_err(e)?;
                let qkv = chunks(&self.w.linear(&y, &format!("{b}.qkv"))?, 3)?;
                let a = sdpa(&heads(&qkv[0], 8)?, &heads(&qkv[1], 8)?, &heads(&qkv[2], 8)?, None)?;
                h = (h + m[2].broadcast_mul(&self.w.linear(&merge(&a)?, &format!("{b}.o"))?).map_err(e)?).map_err(e)?;
                let y = (ln_plain(&h, 1e-5)?.broadcast_mul(&(&m[4] + 1.0).map_err(e)?).map_err(e)?.broadcast_add(&m[3])).map_err(e)?;
                let y = self.w.linear(&self.w.linear(&y, &format!("{b}.mlp.0"))?.gelu_erf().map_err(e)?, &format!("{b}.mlp.2"))?;
                h = (h + m[5].broadcast_mul(&y).map_err(e)?).map_err(e)?;
            }
            let o = self.w.linear(&self.w.ln(&h, "norm", 1e-5)?, "out")?;
            let o: Vec<Vec<Vec<f32>>> = o.to_vec3().map_err(e)?;
            for (q, &i) in idx.iter().enumerate() {
                out[i] = o[q].iter().map(|r| {
                    let f: [f64; 5] = std::array::from_fn(|k| (r[k] * self.sd[k] + self.mu[k]) as f64);
                    [f[0] + roots[i][0], f[1] + roots[i][1], f[2] + roots[i][2], f[3].max(0.0), f[4].max(0.0)]
                }).collect();
            }
        }
        Ok(out)
    }
}

/// tokens_to_cards (root_dir): (seq rows [x, y, z, w, t, nx, ny, nz], triangle) per existing slot, in slot order.
pub fn tokens_to_cards(tok: &Tokenizer, vae: &CardVae, x: &[f32]) -> R<Vec<(Vec<[f64; 8]>, bool)>> {
    let slots: Vec<&[f32]> = x.chunks(tok.dim).filter(|s| tok.exist(s)).collect();
    let zs: Vec<Vec<f32>> = slots.iter().map(|s| tok.z(s)).collect();
    let roots: Vec<[f64; 3]> = slots.iter().map(|s| tok.root(s)).collect();
    let seqs = vae.decode(&zs, &roots)?;
    Ok(slots.iter().zip(seqs).map(|(s, seq)| {
        let n = tok.nrm(s);
        let l = (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]).sqrt() + 1e-12;
        let n = [n[0] / l, n[1] / l, n[2] / l];
        (seq.iter().map(|r| [r[0], r[1], r[2], r[3], r[4], n[0], n[1], n[2]]).collect(), tok.triangle(s))
    }).collect())
}

/// chaindit.decode: chain tokens (48 x 27) -> chains (path of 8 points, joints by arc length, stiffness).
pub fn decode_chains(x: &[f32], dim: usize, stats: &Path) -> R<serde_json::Value> {
    let s = read_json(stats)?;
    let (mu, sd) = (json_vec(&s, "mu")?, json_vec(&s, "sd")?);
    const M: usize = 8;
    let mut out = Vec::new();
    for t in x.chunks(dim) {
        if t[dim - 1] <= 0.0 { continue; }
        let v: Vec<f64> = (0..dim - 1).map(|k| (t[k] * sd[k] + mu[k]) as f64).collect();
        let path: Vec<[f64; 3]> = (0..M).map(|i| [v[3 * i], v[3 * i + 1], v[3 * i + 2]]).collect();
        let nj = (v[M * 3].round() as i64).clamp(2, 20) as usize;
        let mut d = vec![0.0];
        for w in path.windows(2) { d.push(d.last().unwrap() + ((w[1][0] - w[0][0]).powi(2) + (w[1][1] - w[0][1]).powi(2) + (w[1][2] - w[0][2]).powi(2)).sqrt()); }
        let total = *d.last().unwrap();
        let joints: Vec<[f64; 3]> = (0..nj).map(|j| {
            let tt = total * j as f64 / (nj - 1) as f64;
            let k = d.partition_point(|x| *x <= tt).clamp(1, M - 1);
            let a = if d[k] > d[k - 1] { ((tt - d[k - 1]) / (d[k] - d[k - 1])).clamp(0.0, 1.0) } else { 0.0 };
            std::array::from_fn(|c| path[k - 1][c] * (1.0 - a) + path[k][c] * a)
        }).collect();
        out.push(serde_json::json!({"path": path, "joints": joints, "n_joints": nj, "stiffness": v[M * 3 + 1].clamp(0.0, 1.0)}));
    }
    Ok(serde_json::Value::Array(out))
}

/// skimage.color.lab2rgb (D65, 2 degree observer), clipped to 0..1.
pub fn lab_to_srgb(l: f64, a: f64, b: f64) -> [f64; 3] {
    let fy = (l + 16.0) / 116.0;
    let fx = a / 500.0 + fy;
    let fz = (fy - b / 200.0).max(0.0);
    let inv = |f: f64| if f > 0.2068966 { f * f * f } else { (f - 16.0 / 116.0) / 7.787 };
    let (x, y, z) = (inv(fx) * 0.95047, inv(fy), inv(fz) * 1.08883);
    let r = 3.24048134 * x - 1.53715152 * y - 0.49853633 * z;
    let g = -0.96925495 * x + 1.87599 * y + 0.04155593 * z;
    let bb = 0.05564664 * x - 0.20404134 * y + 1.05731107 * z;
    [r, g, bb].map(|c| {
        let c = if c > 0.0031308 { 1.055 * c.powf(1.0 / 2.4) - 0.055 } else { 12.92 * c };
        c.clamp(0.0, 1.0)
    })
}
