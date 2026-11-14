//! hairdeck.models.setdit.SetDiT with the context encoders of its subclasses (image DiT, chain DiT, colour model's
//! inner DiT) and the Euler / CFG flow sampler (hairdeck.sampling.flow.fm_sample, euler, shift 1).
use crate::nn::{chunks, e, heads, ln_plain, merge, modulate, sdpa, timestep_embedding, Weights, R};
use candle_core::{Device, Tensor, D};

pub struct SetDiT {
    pub w: Weights,
    /// key prefix ("" or "dit.")
    pre: String,
    pub depth: usize,
    pub heads: usize,
    dev: Device,
}

impl SetDiT {
    pub fn new(w: Weights, pre: &str, depth: usize, heads: usize, dev: &Device) -> SetDiT {
        SetDiT { w, pre: pre.into(), depth, heads, dev: dev.clone() }
    }
    fn k(&self, s: &str) -> String { format!("{}{s}", self.pre) }
    fn lin(&self, x: &Tensor, s: &str) -> R<Tensor> { self.w.linear(x, &self.k(s)) }

    /// ImgSetDiT.encode_cond: cond_proj(cond_norm(tokens)) + ctx_pos
    pub fn encode_image(&self, tokens: &Tensor) -> R<Tensor> {
        let c = self.w.ln(tokens, &self.k("cond_norm"), 1e-5)?;
        self.lin(&c, "cond_proj")?.broadcast_add(self.w.p(&self.k("ctx_pos"))?).map_err(e)
    }
    /// ChainDiT.encode_cond: card_proj(card_norm(cards)) + card_pos
    pub fn encode_cards(&self, cards: &Tensor) -> R<Tensor> {
        let c = self.w.ln(cards, &self.k("card_norm"), 1e-5)?;
        self.lin(&c, "card_proj")?.broadcast_add(self.w.p(&self.k("card_pos"))?).map_err(e)
    }

    fn attn(&self, x: &Tensor, ctx: &Tensor, name: &str) -> R<Tensor> {
        let q = heads(&self.lin(x, &format!("{name}.q"))?, self.heads)?;
        let kv = chunks(&self.lin(ctx, &format!("{name}.kv"))?, 2)?;
        let k = heads(&kv[0], self.heads)?;
        let v = heads(&kv[1], self.heads)?;
        let q = self.w.rms(&q, &self.k(&format!("{name}.qn")))?;
        let k = self.w.rms(&k, &self.k(&format!("{name}.kn")))?;
        self.lin(&merge(&sdpa(&q, &k, &v, None)?)?, &format!("{name}.o"))
    }

    /// The conditioning vector c and the hidden states after all blocks.
    pub fn trunk(&self, x: &Tensor, t: &[f32], ctx: &Tensor) -> R<(Tensor, Tensor)> {
        let temb = timestep_embedding(t, 256, &self.dev)?;
        let tc = self.lin(&self.lin(&temb, "t_mlp.0")?.silu().map_err(e)?, "t_mlp.2")?;
        let pool = ctx.mean(1).map_err(e)?;
        let pc = self.lin(&self.lin(&pool, "pool_mlp.0")?.silu().map_err(e)?, "pool_mlp.2")?;
        let c = (tc + pc).map_err(e)?;
        let sc = c.silu().map_err(e)?;
        let mut h = self.lin(x, "inp")?;
        for i in 0..self.depth {
            let b = format!("blocks.{i}");
            let m = chunks(&self.lin(&sc, &format!("{b}.ada"))?, 9)?;
            let y = modulate(&ln_plain(&h, 1e-6)?, &m[0], &m[1])?;
            let a = self.attn(&y, &y, &format!("{b}.attn"))?;
            h = (h + a.broadcast_mul(&m[2].unsqueeze(1).map_err(e)?).map_err(e)?).map_err(e)?;
            let a = self.attn(&modulate(&ln_plain(&h, 1e-6)?, &m[3], &m[4])?, ctx, &format!("{b}.xattn"))?;
            h = (h + a.broadcast_mul(&m[5].unsqueeze(1).map_err(e)?).map_err(e)?).map_err(e)?;
            let y = modulate(&ln_plain(&h, 1e-6)?, &m[6], &m[7])?;
            let y = self.lin(&self.lin(&y, &format!("{b}.mlp.0"))?.gelu().map_err(e)?, &format!("{b}.mlp.2"))?;
            h = (h + y.broadcast_mul(&m[8].unsqueeze(1).map_err(e)?).map_err(e)?).map_err(e)?;
        }
        Ok((c, h))
    }

    /// SetDiT.forward: velocity for tokens x (B, N, D) at times t with the encoded context ctx (B, M, dim).
    pub fn forward(&self, x: &Tensor, t: &[f32], ctx: &Tensor) -> R<Tensor> {
        let (c, h) = self.trunk(x, t, ctx)?;
        let f = chunks(&self.lin(&c.silu().map_err(e)?, "f_ada")?, 2)?;
        self.lin(&modulate(&ln_plain(&h, 1e-6)?, &f[0], &f[1])?, "out")
    }

    /// Euler integration from t = 1 (noise x) to 0 in `steps` uniform steps, CFG with the learned null context.
    pub fn sample(&self, ctx: &Tensor, x: Tensor, steps: usize, cfg: f32) -> R<Tensor> {
        let (b, m, d) = ctx.dims3().map_err(e)?;
        let null = self.w.p(&self.k("null_ctx"))?.reshape((1, m, d)).and_then(|t| t.broadcast_as((b, m, d))).and_then(|t| t.contiguous()).map_err(e)?;
        let both_ctx = Tensor::cat(&[ctx, &null], 0).map_err(e)?;
        let mut x = x;
        for i in 0..steps {
            let t = 1.0 - i as f32 / steps as f32;
            let tn = 1.0 - (i + 1) as f32 / steps as f32;
            let v = if cfg == 1.0 { self.forward(&x, &vec![t; b], ctx)? } else {
                let both = self.forward(&Tensor::cat(&[&x, &x], 0).map_err(e)?, &vec![t; 2 * b], &both_ctx)?;
                let vc = both.narrow(0, 0, b).map_err(e)?;
                let vu = both.narrow(0, b, b).map_err(e)?;
                (&vu + ((vc - &vu).map_err(e)? * cfg as f64).map_err(e)?).map_err(e)?
            };
            x = (x + (v * (tn - t) as f64).map_err(e)?).map_err(e)?;
        }
        Ok(x)
    }
}

/// Last-dimension slice helper.
pub fn cols(x: &Tensor, start: usize, len: usize) -> R<Tensor> { x.narrow(D::Minus1, start, len).map_err(e) }
