//! HairDeck (github.com/hyz317/HairDeck, Apache-2.0) output -> an authored hair part of the session.
//!
//! HairDeck writes, per generated hairstyle, `cards_seed<s>.json` (a list of `{shape, seq, colors}`: `seq` rows are
//! `[x, y, z, width, thickness, vx, vy, vz]` control points of one hair card, `colors` the sRGB colours at the centres
//! of equal parts along it) and `chains_seed<s>.json` (spring-bone chains `{joints, n_joints, stiffness}`), both in
//! its head frame: y up, the face toward +z, metres, right-handed, with the canonical skull ellipsoid of
//! `hairdeck.vis.head_proxy` (radii 0.405 W, 0.5 W, 0.5 W around FACE_TOP - (0, 0.447 W, 0.2 W)).
//!
//! The card mesh is HairDeck's `hairdeck.infer.glb.cards_vf` (5-point stencil tangents, Bishop transport of the root
//! direction, four vertices per ring, the same faces). The skull ellipsoid is fitted to the upper part of the
//! character's own head mesh, the frame mirrored on x into Unity's left-handed one (winding swapped). Card colours go
//! to an atlas (one cell per card, the colours along v), the chains become the private soft hair rig of
//! `portable_hair_soft` (root = the head; card roots stay on it).
use super::*;
use crate::pose::Mat4;

/// The canonical head frame of HairDeck's released models (`data/head_frame_train.npz`: face width W, face-top
/// anchor O), filled in from that file; `hairdeck_frame` in the opts overrides it.
pub(super) const CANON_W: f32 = 0.127_598_24;
pub(super) const CANON_O: [f32; 3] = [0.0, 0.479_054_95, 0.025_801_453];

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HairDeckOpts {
    /// Native hair shader of the character's own hair (ramps, gloss) instead of the plain item shader.
    #[serde(default = "yes")] pub native: bool,
    /// Extra uniform scale on top of the fit, and an offset in head-local metres.
    #[serde(default = "one")] pub scale: f32,
    #[serde(default)] pub offset: [f32; 3],
    /// The head frame (W, O) when it is not the released one.
    #[serde(default)] pub frame_w: Option<f32>,
    #[serde(default)] pub frame_o: Option<[f32; 3]>,
    /// Without chains (or with `rigid`) the hair follows the head rigidly.
    #[serde(default)] pub rigid: bool,
    /// One colour for all cards (sRGB 0..1) when the cards file has none.
    #[serde(default)] pub hair_color: Option<[f32; 3]>,
}
fn yes() -> bool { true }
fn one() -> f32 { 1.0 }
impl Default for HairDeckOpts {
    fn default() -> Self { Self { native: true, scale: 1.0, offset: [0.0; 3], frame_w: None, frame_o: None, rigid: false, hair_color: None } }
}

#[derive(Deserialize)]
struct Card { #[serde(default)] shape: String, seq: Vec<Vec<f64>>, #[serde(default)] colors: Vec<[f64; 3]> }
#[derive(Deserialize)]
struct DeckChain { joints: Vec<[f64; 3]>, #[serde(default)] stiffness: f64 }

type V3 = [f64; 3];
fn sub(a: V3, b: V3) -> V3 { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn add(a: V3, b: V3) -> V3 { [a[0] + b[0], a[1] + b[1], a[2] + b[2]] }
fn mul(a: V3, s: f64) -> V3 { [a[0] * s, a[1] * s, a[2] * s] }
fn dot(a: V3, b: V3) -> f64 { a[0] * b[0] + a[1] * b[1] + a[2] * b[2] }
fn cross(a: V3, b: V3) -> V3 { [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]] }
fn norm(a: V3) -> f64 { dot(a, a).sqrt() }
fn unit(a: V3) -> V3 { mul(a, 1.0 / (norm(a) + 1e-12)) }

/// One card's ring vertices (4 per control point) and faces, as `cards_vf` (None below 3 points).
fn card_vf(rows: &[[f64; 8]], triangle: bool) -> Option<(Vec<V3>, Vec<[u32; 3]>)> {
    let n = rows.len();
    if n < 3 { return None; }
    let p: Vec<V3> = rows.iter().map(|r| [r[0], r[1], r[2]]).collect();
    const ST: [f64; 5] = [-1.0 / 12.0, 2.0 / 3.0, 0.0, -2.0 / 3.0, 1.0 / 12.0];
    let t: Vec<V3> = if n < 5 { vec![unit(sub(p[n - 1], p[0])); n] } else {
        (0..n).map(|i| {
            let lo = (i as i64 - 2).clamp(0, n as i64 - 5) as usize;
            unit((0..5).fold([0.0; 3], |acc, k| add(acc, mul(p[lo + k], ST[k]))))
        }).collect()
    };
    let mut nv = vec![[0.0; 3]; n];
    let v0 = [rows[0][5], rows[0][6], rows[0][7]];
    nv[0] = unit(sub(v0, mul(t[0], dot(v0, t[0]))));
    for i in 1..n {
        let (a, b) = (t[i - 1], t[i]);
        let ax = cross(a, b);
        let s = norm(ax);
        let c = dot(a, b).clamp(-1.0, 1.0);
        let mut m = nv[i - 1];
        if s > 1e-9 {
            let k = mul(ax, 1.0 / s);
            m = add(add(mul(m, c), mul(cross(k, m), s)), mul(k, dot(k, m) * (1.0 - c)));
        }
        nv[i] = unit(sub(m, mul(b, dot(m, b))));
    }
    let (up, down) = if triangle { (3.0, 6.0) } else { (2.0, 2.0) };
    let mut v = Vec::with_capacity(4 * n);
    for i in 0..n {
        let nn = unit(nv[i]);
        let tg = unit(sub(t[i], mul(nn, dot(t[i], nn))));
        let t2 = cross(nn, tg);
        let (w, th) = (rows[i][3], rows[i][4]);
        v.push(add(p[i], mul(nn, w / 2.0)));
        v.push(add(p[i], mul(t2, th / up)));
        v.push(sub(p[i], mul(nn, w / 2.0)));
        v.push(sub(p[i], mul(t2, th / down)));
    }
    let mut f: Vec<[u32; 3]> = vec![[0, 2, 1], [0, 3, 2]];
    for i in 1..n as u32 {
        let l = 4 * i;
        f.extend([[l, l - 4, l + 1], [l + 1, l - 3, l + 2], [l + 2, l - 2, l + 3], [l + 3, l - 1, l], [l - 3, l + 1, l - 4],
            [l - 4, l, l - 1], [l - 1, l + 3, l - 2], [l - 2, l + 2, l - 3], [l, l + 1, l + 2], [l, l + 2, l + 3]]);
    }
    Some((v, f))
}

/// Arc-length position (0..1) of every control point of a card (`card_uv`'s v).
fn card_v(rows: &[[f64; 8]]) -> Vec<f64> {
    let mut s = vec![0.0];
    for w in rows.windows(2) { s.push(s.last().unwrap() + norm(sub([w[1][0], w[1][1], w[1][2]], [w[0][0], w[0][1], w[0][2]]))); }
    let last = *s.last().unwrap();
    if last > 0.0 { s.iter().map(|x| x / last).collect() } else { (0..rows.len()).map(|i| i as f64 / (rows.len() - 1) as f64).collect() }
}

/// Fewer control points (arc-length resampling of all 8 channels) so the whole style fits the triangle budget.
fn resample(rows: &[[f64; 8]], m: usize) -> Vec<[f64; 8]> {
    if rows.len() <= m { return rows.to_vec(); }
    let v = card_v(rows);
    (0..m).map(|j| {
        let x = j as f64 / (m - 1) as f64;
        let k = v.partition_point(|y| *y <= x).clamp(1, rows.len() - 1);
        let span = (v[k] - v[k - 1]).max(1e-12);
        let a = ((x - v[k - 1]) / span).clamp(0.0, 1.0);
        std::array::from_fn(|c| rows[k - 1][c] * (1.0 - a) + rows[k][c] * a)
    }).collect()
}

fn lerp_colors(colors: &[[f64; 3]], v: f64) -> [f64; 3] {
    let b = colors.len();
    let x = v * b as f64 - 0.5;
    if x <= 0.0 { return colors[0]; }
    if x >= (b - 1) as f64 { return colors[b - 1]; }
    let i = x.floor() as usize;
    let a = x - i as f64;
    std::array::from_fn(|c| colors[i][c] * (1.0 - a) + colors[i + 1][c] * a)
}

/// Head-local placement of the HairDeck head frame: the skull ellipsoid onto the upper part of the head mesh.
struct Fit { scale: f64, from: V3, to: V3 }
impl Fit {
    /// HairDeck head frame -> head-local Unity (x mirrored).
    fn apply(&self, p: V3) -> V3 {
        let q = mul(sub(p, self.from), self.scale);
        add([-q[0], q[1], q[2]], self.to)
    }
}
fn fit(s: &OkSession, head_world: &Mat4, opts: &HairDeckOpts) -> Result<(Fit, serde_json::Value), String> {
    let w = opts.frame_w.unwrap_or(CANON_W) as f64;
    let o = opts.frame_o.unwrap_or(CANON_O).map(|x| x as f64);
    // hairdeck.vis.head_proxy: face centre O - 0.547 W, ellipsoid centre 0.1 W above and 0.2 W behind it.
    let centre = [o[0], o[1] - 0.547 * w + 0.10 * w, o[2] - 0.2 * w];
    let radii = [0.405 * w, 0.5 * w, 0.5 * w];
    let inv = crate::pose::mat_inv_pub(head_world);
    let head = s.parts.iter().find(|p| p.role == "head" && !p.positions.is_empty()).ok_or("the character has no head mesh")?;
    let local: Vec<V3> = head.positions.iter().map(|p| { let q = crate::pose::mat_vec(&inv, *p); [q[0] as f64, q[1] as f64, q[2] as f64] }).collect();
    let (ymin, ymax) = local.iter().fold((f64::MAX, f64::MIN), |(a, b), p| (a.min(p[1]), b.max(p[1])));
    // The cranium: the top 45% of the head mesh (above the eyes, no jaw, nose or ear lobes).
    let cut = ymax - 0.45 * (ymax - ymin);
    let upper: Vec<&V3> = local.iter().filter(|p| p[1] >= cut).collect();
    if upper.len() < 16 { return Err("head mesh too small to fit the hair".into()); }
    let ext = |k: usize| upper.iter().fold((f64::MAX, f64::MIN), |(a, b), p| (a.min(p[k]), b.max(p[k])));
    let (x0, x1) = ext(0);
    let (z0, z1) = ext(2);
    let half_x = (x1 - x0) / 2.0;
    let half_z = (z1 - z0) / 2.0;
    let k = 0.5 * (half_x / radii[0] + half_z / radii[2]) * opts.scale as f64;
    // Skull top onto the head's top; centred on x, the cranium's middle on z.
    let target_centre = [(x0 + x1) / 2.0, ymax - radii[1] * k, (z0 + z1) / 2.0];
    let to = add(target_centre, opts.offset.map(|x| x as f64));
    let report = serde_json::json!({"frame_w": w, "frame_o": o, "scale": k, "head_top": ymax, "cranium_half_x": half_x, "cranium_half_z": half_z, "centre": to});
    Ok((Fit { scale: k, from: centre, to }, report))
}

/// The authored hair mesh and its colour atlas for a HairDeck result.
pub(super) fn build(s: &OkSession, cards_json: &[u8], chains_json: Option<&[u8]>, opts: &HairDeckOpts) -> Result<(HairMesh, Vec<u8>, serde_json::Value), String> {
    let cards: Vec<Card> = serde_json::from_slice(cards_json).map_err(|e| format!("cards json: {e}"))?;
    let sk = s.body_skel.as_ref().ok_or("missing body skeleton")?;
    let head_world = sk.worlds[head(sk)?];
    let (fit, fit_report) = fit(s, &head_world, opts)?;
    let mut rows: Vec<(Vec<[f64; 8]>, bool, Vec<[f64; 3]>)> = Vec::new();
    for c in &cards {
        let r: Vec<[f64; 8]> = c.seq.iter().filter(|r| r.len() >= 8).map(|r| std::array::from_fn(|i| r[i])).collect();
        if r.len() < 3 || r.iter().flatten().any(|x| !x.is_finite()) { continue; }
        let colors = if c.colors.is_empty() { vec![opts.hair_color.map(|c| c.map(|x| x as f64)).unwrap_or([0.4, 0.3, 0.25])] } else { c.colors.clone() };
        rows.push((r, c.shape == "triangle", colors));
    }
    if rows.is_empty() { return Err("the cards file has no card with 3 or more points".into()); }
    // Triangle budget of the authored hair (portable_hair::validate): 2 + 10 (n - 1) per card.
    let tris = |rows: &[(Vec<[f64; 8]>, bool, Vec<[f64; 3]>)]| rows.iter().map(|r| 2 + 10 * (r.0.len() - 1)).sum::<usize>();
    let mut cap = rows.iter().map(|r| r.0.len()).max().unwrap();
    while tris(&rows) > 49_000 && cap > 3 {
        cap -= 1;
        for r in &mut rows { r.0 = resample(&r.0, cap); }
    }
    if tris(&rows) > 50_000 { return Err(format!("{} cards are too many for the 50000 triangle budget", rows.len())); }
    // Colour atlas: cells of 4 x 32 pixels, 64 per row.
    const CW: usize = 4; const CH: usize = 32; const PER_ROW: usize = 64;
    let width = CW * PER_ROW;
    let height = CH * rows.len().div_ceil(PER_ROW);
    let mut atlas = image::RgbaImage::new(width as u32, height as u32);
    let (mut positions, mut uvs, mut gloss_uvs, mut indices, mut card_of, mut ring_of) = (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
    let mut lines: Vec<Vec<V3>> = Vec::new();
    for (ci, (r, tri, colors)) in rows.iter().enumerate() {
        let Some((v, f)) = card_vf(r, *tri) else { continue };
        let brightness = 0.86 + 0.14 * (((ci as u64).wrapping_mul(0x9E3779B97F4A7C15) >> 40) as f64 / (1u64 << 24) as f64);
        let (cx, cy) = ((ci % PER_ROW) * CW, (ci / PER_ROW) * CH);
        for y in 0..CH {
            let c = lerp_colors(colors, (y as f64 + 0.5) / CH as f64);
            let px = image::Rgba([0, 1, 2].map(|k| ((c[k] * brightness).clamp(0.0, 1.0) * 255.0 + 0.5) as u8).into_iter().chain([255]).collect::<Vec<_>>().try_into().unwrap());
            for x in 0..CW { atlas.put_pixel((cx + x) as u32, (cy + y) as u32, px); }
        }
        let vv = card_v(r);
        let base = positions.len() as u32;
        for (k, p) in v.iter().enumerate() {
            let (ring, corner) = (k / 4, k % 4);
            let q = fit.apply(*p);
            positions.push([q[0] as f32, q[1] as f32, q[2] as f32]);
            let along = vv[ring];
            let u = [0.0, 0.5, 1.0, 0.5][corner];
            // Unity v runs up the texture; PNG rows run down.
            let y = cy as f64 + 0.5 + along * (CH as f64 - 1.0);
            uvs.push([((cx as f64 + 0.5 + u * (CW as f64 - 1.0)) / width as f64) as f32, (1.0 - y / height as f64) as f32]);
            gloss_uvs.push([u as f32, along as f32]);
            card_of.push(lines.len());
            ring_of.push(ring);
        }
        for t in f {
            let [a, b, c] = t.map(|i| base + i);
            let (pa, pb, pc) = (positions[a as usize], positions[b as usize], positions[c as usize]);
            let e1 = [pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2]];
            let e2 = [pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2]];
            let cr = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
            if (cr[0] * cr[0] + cr[1] * cr[1] + cr[2] * cr[2]).sqrt() <= 1e-12 { continue; }
            // Mirrored frame: the second and third index swap.
            indices.extend([a, c, b]);
        }
        lines.push(r.iter().map(|x| fit.apply([x[0], x[1], x[2]])).collect());
    }
    // Smooth normals within each card (its vertices are its own), tangents across the card (u).
    let n = positions.len();
    let mut normals = vec![[0f64; 3]; n];
    for t in indices.chunks(3) {
        let p = |i: u32| { let q = positions[i as usize]; [q[0] as f64, q[1] as f64, q[2] as f64] };
        let fnrm = cross(sub(p(t[1]), p(t[0])), sub(p(t[2]), p(t[0])));
        for &i in t { normals[i as usize] = add(normals[i as usize], fnrm); }
    }
    let mut tangents = Vec::with_capacity(n);
    let mut out_normals = Vec::with_capacity(n);
    for i in 0..n {
        let nn = unit(normals[i]);
        let ring_base = i - i % 4;
        let pos = |k: usize| { let q = positions[k]; [q[0] as f64, q[1] as f64, q[2] as f64] };
        let across = sub(pos(ring_base + 2), pos(ring_base));
        let mut t = sub(across, mul(nn, dot(across, nn)));
        if norm(t) < 1e-9 { t = if nn[0].abs() < 0.9 { cross(nn, [1.0, 0.0, 0.0]) } else { cross(nn, [0.0, 1.0, 0.0]) }; }
        let t = unit(t);
        let line = &lines[card_of[i]];
        let r = ring_of[i].min(line.len() - 1);
        let along = sub(line[(r + 1).min(line.len() - 1)], line[r.saturating_sub(1)]);
        let w = if dot(cross(nn, t), along) >= 0.0 { 1.0 } else { -1.0 };
        out_normals.push([nn[0] as f32, nn[1] as f32, nn[2] as f32]);
        tangents.push([t[0] as f32, t[1] as f32, t[2] as f32, w]);
    }
    let chains: Vec<DeckChain> = match chains_json { Some(b) if !opts.rigid => serde_json::from_slice(b).map_err(|e| format!("chains json: {e}"))?, _ => Vec::new() };
    let soft_rig = if chains.is_empty() { None } else { Some(rig(&chains, &fit, &positions, &card_of, &ring_of, &lines)?) };
    let mut png = Vec::new();
    atlas.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png).map_err(|e| e.to_string())?;
    let report = serde_json::json!({"cards": lines.len(), "vertices": n, "triangles": indices.len() / 3, "control_points_cap": cap,
        "atlas": [width, height], "chains_in": chains.len(), "chains_used": soft_rig.as_ref().map_or(0, |r| r.chains.len()), "fit": fit_report});
    let mesh = HairMesh { positions, normals: out_normals, tangents, uvs, indices, texture: String::new(), normal: None, roughness: None, metallic: None,
        native_material_card: None, native_gloss_asset: None, gloss_uvs: if opts.native { gloss_uvs } else { Vec::new() },
        soft_rig, hide_source_accessory: true, layer: None, native_self: opts.native };
    Ok((mesh, png, report))
}

/// HairDeck's chains as the private soft rig: at most 32 chains, 3..12 joints each, 256 bones with the root; every
/// card follows the chain nearest to its centreline (its root ring stays on the head).
fn rig(chains: &[DeckChain], fit: &Fit, positions: &[[f32; 3]], card_of: &[usize], ring_of: &[usize], lines: &[Vec<V3>]) -> Result<soft::SoftRig, String> {
    let mut cs: Vec<(Vec<V3>, f64)> = chains.iter().filter(|c| c.joints.len() >= 2)
        .map(|c| (c.joints.iter().map(|j| fit.apply(*j)).collect::<Vec<_>>(), c.stiffness.clamp(0.0, 1.0))).collect();
    let len = |p: &[V3]| p.windows(2).map(|w| norm(sub(w[1], w[0]))).sum::<f64>();
    cs.retain(|c| len(&c.0) > 1e-3);
    cs.sort_by(|a, b| len(&b.0).total_cmp(&len(&a.0)));
    cs.truncate(32);
    if cs.is_empty() { return Err("no usable spring chain".into()); }
    let per = (255 / cs.len()).clamp(3, 12);
    let mut out = Vec::new();
    for (i, (p, stiff)) in cs.iter().enumerate() {
        let rows: Vec<[f64; 8]> = p.iter().map(|q| [q[0], q[1], q[2], 0., 0., 0., 0., 0.]).collect();
        let m = p.len().clamp(3, per);
        let pts = if p.len() >= m { resample(&rows, m) } else {
            // Too few joints: insert points along the polyline.
            let v = card_v(&rows);
            (0..m).map(|j| { let x = j as f64 / (m - 1) as f64; let k = v.partition_point(|y| *y <= x).clamp(1, rows.len() - 1);
                let a = ((x - v[k - 1]) / (v[k] - v[k - 1]).max(1e-12)).clamp(0.0, 1.0); std::array::from_fn(|c| rows[k - 1][c] * (1.0 - a) + rows[k][c] * a) }).collect()
        };
        out.push(soft::Chain { name: format!("deck{i}"), points: pts.iter().map(|r| [r[0] as f32, r[1] as f32, r[2] as f32]).collect(),
            damping: 0.2, elasticity: (0.04 + 0.12 * stiff) as f32, stiffness: (0.15 + 0.6 * stiff) as f32, radius: 0.02 });
    }
    // Nearest chain per card (mean distance of its centreline), then per vertex the segment it projects onto.
    let seg = |a: V3, b: V3, p: V3| { let ab = sub(b, a); let t = (dot(sub(p, a), ab) / dot(ab, ab).max(1e-18)).clamp(0.0, 1.0); (norm(sub(p, add(a, mul(ab, t)))), t) };
    let chain_pts: Vec<Vec<V3>> = out.iter().map(|c| c.points.iter().map(|q| [q[0] as f64, q[1] as f64, q[2] as f64]).collect()).collect();
    let nearest = |p: V3, c: &[V3]| c.windows(2).enumerate().map(|(k, w)| { let (d, t) = seg(w[0], w[1], p); (d, k, t) }).min_by(|a, b| a.0.total_cmp(&b.0)).unwrap();
    let card_chain: Vec<usize> = lines.iter().map(|l| (0..chain_pts.len()).min_by(|&a, &b| {
        let d = |c: usize| l.iter().map(|p| nearest(*p, &chain_pts[c]).0).sum::<f64>();
        d(a).total_cmp(&d(b))
    }).unwrap()).collect();
    let offsets: Vec<usize> = out.iter().scan(1usize, |acc, c| { let o = *acc; *acc += c.points.len(); Some(o) }).collect();
    let mut weights = Vec::with_capacity(positions.len());
    let mut bone_idx = Vec::with_capacity(positions.len());
    for (i, p) in positions.iter().enumerate() {
        let p = [p[0] as f64, p[1] as f64, p[2] as f64];
        let c = card_chain[card_of[i]];
        let (d, k, t) = nearest(p, &chain_pts[c]);
        if ring_of[i] == 0 || d > 0.08 {
            weights.push([1.0, 0.0, 0.0, 0.0]); bone_idx.push([0, 0, 0, 0]); continue;
        }
        let (a, b) = ((offsets[c] + k) as u16, (offsets[c] + k + 1) as u16);
        // The second ring blends from the head into the chain, so card roots do not tear.
        let root = if ring_of[i] == 1 { 0.5 } else { 0.0 };
        let wa = ((1.0 - t) * (1.0 - root)) as f32;
        let wb = (t * (1.0 - root)) as f32;
        weights.push([(1.0 - wa - wb).max(0.0), wa, wb, 0.0]);
        bone_idx.push([0, a, b, 0]);
    }
    Ok(soft::SoftRig { chains: out, weights, bone_idx })
}

/// Replaces the character's hair in a live session with a HairDeck result (the reader's and OK Studio's path).
pub fn apply(s: &mut OkSession, cards_json: &[u8], chains_json: Option<&[u8]>, opts: &HairDeckOpts) -> Result<serde_json::Value, String> {
    let (mesh, png, mut report) = build(s, cards_json, chains_json, opts)?;
    validate(&mesh)?;
    install(s, &mesh, &png, None)?;
    report["part"] = serde_json::json!(part_name(&mesh));
    Ok(report)
}
/// `apply` from files: `cards_seed<s>.json`, and `chains_seed<s>.json` beside it when it exists.
pub fn apply_files(s: &mut OkSession, cards: &Path, opts: &HairDeckOpts) -> Result<serde_json::Value, String> {
    let c = crate::gamefs::read(cards).map_err(|e| format!("{}: {e}", cards.display()))?;
    let name = cards.file_name().and_then(|n| n.to_str()).unwrap_or("");
    let chains = cards.with_file_name(name.replacen("cards_", "chains_", 1));
    let ch = if name.starts_with("cards_") && chains.ok_is_file() { Some(crate::gamefs::read(&chains).map_err(|e| e.to_string())?) } else { None };
    let mut r = apply(s, &c, ch.as_deref(), opts)?;
    r["chains_file"] = serde_json::json!(ch.as_ref().map(|_| chains));
    Ok(r)
}
