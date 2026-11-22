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
//! character's own head mesh (its width, the forehead and the top: the face mesh has no back of the skull), the frame
//! mirrored on x into Unity's left-handed one (winding swapped). Card colours go
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
    /// A bred child's hair drawn from both parents' faces (mother, father, father_share): a record only.
    #[serde(default, skip_serializing_if = "Option::is_none")] pub mix: Option<serde_json::Value>,
}
fn yes() -> bool { true }
fn one() -> f32 { 1.0 }
impl Default for HairDeckOpts {
    fn default() -> Self { Self { native: true, scale: 1.0, offset: [0.0; 3], frame_w: None, frame_o: None, rigid: false, hair_color: None, mix: None } }
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
    // The game's face mesh has no back of the skull (the hair covers it): the scale comes from the cranium's width,
    // the skull's front from the forehead, its top from the head's top.
    // The game's cranium is boxier than HairDeck's (VRoid-like) skull: at the fitted size the top of the forehead
    // shows through the bangs. 4% larger, 0.13 radius higher and 0.07 radius forward covered it (C041, 2026-11-15).
    let k = half_x / radii[0] * 1.04 * opts.scale as f64;
    let target_centre = [(x0 + x1) / 2.0, ymax - radii[1] * k + 0.13 * radii[1] * k, z1 - radii[2] * k + 0.07 * radii[2] * k];
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
    let (mut positions, mut uvs, mut indices, mut card_of, mut ring_of) = (Vec::new(), Vec::new(), Vec::new(), Vec::new(), Vec::new());
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
        // Native hair: the tangent frame of UV1 (ring_uv), u round the head and the bitangent up the UV1 v, as on the
        // game's hair. The hair program moves the gloss band along v by (_SpeclarHeight - 1) * dot(view, bitangent):
        // with each card's own across / along frame every card moved its band its own way and the ring broke into
        // blocks along the strands (2026-11-22).
        let q = pos(i);
        let (dir, up) = if opts.native {
            let sz = if q[2] < 0.0 { -1.0 } else { 1.0 };
            let gu = if q[0].abs() + q[2].abs() < 1e-9 { [1.0, 0.0, 0.0] } else { [q[2].abs(), 0.0, -q[0] * sz] };
            (gu, [RING_SIDE * q[0].signum(), 1.0, RING_FRONT])
        } else {
            let line = &lines[card_of[i]];
            let r = ring_of[i].min(line.len() - 1);
            (across, sub(line[(r + 1).min(line.len() - 1)], line[r.saturating_sub(1)]))
        };
        let mut t = sub(dir, mul(nn, dot(dir, nn)));
        if norm(t) < 1e-9 { t = if nn[0].abs() < 0.9 { cross(nn, [1.0, 0.0, 0.0]) } else { cross(nn, [0.0, 1.0, 0.0]) }; }
        let t = unit(t);
        let w = if dot(cross(nn, t), up) >= 0.0 { 1.0 } else { -1.0 };
        out_normals.push([nn[0] as f32, nn[1] as f32, nn[2] as f32]);
        tangents.push([t[0] as f32, t[1] as f32, t[2] as f32, w]);
    }
    let chains: Vec<DeckChain> = match chains_json { Some(b) if !opts.rigid => serde_json::from_slice(b).map_err(|e| format!("chains json: {e}"))?, _ => Vec::new() };
    let soft_rig = if chains.is_empty() { None } else { Some(rig(&chains, &fit, &positions, &card_of, &ring_of, &lines)?) };
    let gloss_uvs = if opts.native { ring_uv(&positions) } else { Vec::new() };
    let gloss_mask = if opts.native { Some(gloss_mask()?) } else { None };
    let mut png = Vec::new();
    atlas.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png).map_err(|e| e.to_string())?;
    let report = serde_json::json!({"cards": lines.len(), "vertices": n, "triangles": indices.len() / 3, "control_points_cap": cap,
        "atlas": [width, height], "chains_in": chains.len(), "chains_used": soft_rig.as_ref().map_or(0, |r| r.chains.len()), "fit": fit_report});
    let mesh = HairMesh { positions, normals: out_normals, tangents, uvs, indices, texture: String::new(), normal: None, roughness: None, metallic: None,
        native_material_card: None, native_gloss_asset: None, gloss_uvs,
        soft_rig, hide_source_accessory: false, layer: None, native_self: opts.native, gloss_mask };
    Ok((mesh, png, report))
}

/// UV1 of HairDeck hair laid out like the game's hair (2026-11-22, measured on C001, C002, C020 and Megumin's hair):
/// the native hair program reads `_HairGloss` at UV1 and at UV1 + 0.008 in v and lights their difference, and every
/// game gloss mask is a band of streaks at v = 0.5. On the game's hair v rises with head height (3.3..4.5 per unit
/// on the bangs) and the band (v = 0.5) lies on a tilted ring round the crown, y = a - 0.25..0.4 z - 0.3..0.7 |x| in
/// head space (+Y up, +Z to the face), a 0.19..0.22, about 0.03 under the top of the hair; u runs round the head at
/// 0.35..0.6 per radian. Here u is folded (front and back alike) so no seam runs down the back, and v is clamped
/// inside the black of the mask so long hair does not wrap round into the band again.
const RING_DV_DY: f64 = 3.6;
const RING_DU_DAZ: f64 = 0.45;
/// The ring drops this much per unit forward (+Z) and per unit sideways (|x|).
const RING_FRONT: f64 = 0.33;
const RING_SIDE: f64 = 0.45;
fn ring_uv(positions: &[[f32; 3]]) -> Vec<[f32; 2]> {
    let mut crown: Vec<f64> = positions.iter().filter(|p| p[0] * p[0] + p[2] * p[2] < 0.06 * 0.06).map(|p| p[1] as f64).collect();
    if crown.is_empty() { crown = positions.iter().map(|p| p[1] as f64).collect(); }
    crown.sort_by(|a, b| a.total_cmp(b));
    let top = crown.get(crown.len().saturating_sub(1) * 95 / 100).copied().unwrap_or(0.22);
    let a = (top - 0.03).clamp(0.17, 0.24);
    positions.iter().map(|p| {
        let (x, y, z) = (p[0] as f64, p[1] as f64, p[2] as f64);
        let ring = a - RING_FRONT * z - RING_SIDE * x.abs();
        let v = (0.5 + RING_DV_DY * (y - ring)).clamp(0.01, 0.99);
        let u = 0.5 + RING_DU_DAZ * x.atan2(z.abs());
        [u as f32, v as f32]
    }).collect()
}

/// A gloss mask drawn like the game's (mt_hairgloss): black, with a band of vertical streak groups across v = 0.5,
/// each group pinched like an hourglass (C001's mask), grey about 0.38. Used when none of her hair has a mask of its
/// own (mod hair has none); it tiles in u.
fn gloss_mask() -> Result<Vec<u8>, String> {
    const N: usize = 512;
    let rnd = |k: u64| ((k.wrapping_add(1).wrapping_mul(0x9E3779B97F4A7C15) >> 40) as f64) / (1u64 << 24) as f64;
    let mut img = image::RgbaImage::from_pixel(N as u32, N as u32, image::Rgba([0, 0, 0, 255]));
    let half = 0.13 * N as f64;
    let (mut x0, mut g) = (0usize, 0u64);
    while x0 < N {
        let w = 10 + (rnd(g * 3) * 16.0) as usize;
        let gap = 3 + (rnd(g * 3 + 1) * 6.0) as usize;
        let (level, tall) = (0.38 * (0.8 + 0.4 * rnd(g * 3 + 2)), 0.85 + 0.3 * rnd(g * 7 + 5));
        let c = x0 as f64 + w as f64 / 2.0;
        for x in x0..x0 + w {
            let t = ((x as f64 + 0.5 - c) / (w as f64 / 2.0)).abs().min(1.0);
            let h = half * tall * (0.55 + 0.45 * t * t);
            let side = 1.0 - ((t - 0.8) / 0.2).clamp(0.0, 1.0);
            for y in 0..N {
                let d = (y as f64 + 0.5 - N as f64 / 2.0).abs();
                let k = 1.0 - ((d - 0.45 * h) / (0.55 * h)).clamp(0.0, 1.0);
                let k = k * k * (3.0 - 2.0 * k);
                let val = ((level * k * side).clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
                if val > 0 { img.put_pixel((x % N) as u32, y as u32, image::Rgba([val, val, val, 255])); }
            }
        }
        x0 += w + gap;
        g += 1;
    }
    let mut png = Vec::new();
    img.write_to(&mut std::io::Cursor::new(&mut png), image::ImageFormat::Png).map_err(|e| e.to_string())?;
    Ok(png)
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
    // The same hair already on this session (the reader and OK Studio put it on every session they load): nothing to do.
    let stamp = format!("{:08x}{:08x}{}", crc(cards_json), chains_json.map_or(0, crc), serde_json::to_string(opts).unwrap_or_default());
    if s.parts.iter().any(|p| p.render_visible && p.name.starts_with("Tripo_") && p.source_material.as_ref().is_some_and(|m| m.name == stamp)) {
        return Ok(serde_json::json!({"already": true}));
    }
    let (mesh, png, mut report) = build(s, cards_json, chains_json, opts)?;
    validate(&mesh)?;
    // Her old hair made of accessories goes, whatever its meshes and shaders are called (C031's hair is a main_item
    // named Body.049): every hair-category accessory (121), every slot HairAccessoryCustomizer keeps data for (C071's
    // hair cap 53_mesh) and every accessory on a hair socket (a_n_hair_*). The user, 2026-11-22: with HairDeck hair
    // the original hair accessories are not wanted, they overlap it. Ribbons and pins of those slots go with them:
    // they were placed for the old hair and float or sink in the new one. (Until then only renderers tinted with her
    // hair colour went, and Keqing's twin tails and the like stayed through the new hair.)
    let slots = card_hair_slots(s);
    let mut hidden = Vec::new();
    for p in s.parts.iter_mut().filter(|p| p.role == "accessory" && p.render_visible) {
        let Some(sp) = p.source_property.as_ref() else { continue };
        if !slots.iter().any(|k| sp == k || sp.strip_prefix(k.as_str()).is_some_and(|r| r.starts_with('.'))) { continue; }
        p.render_visible = false;
        hidden.push(p.name.clone());
    }
    report["hidden_hair_accessories"] = serde_json::json!(hidden);
    install(s, &mesh, &png, None)?;
    // A runtime accessory's vertices are drawn where they are (world): the display takes them as they stand until the
    // first solve moves them. Installed head-local, a card opened with this hair showed it at her feet (2026-11-22):
    // placed with the head as it is now.
    let head_world = s.body_skel.as_ref().and_then(|sk| head(sk).ok().map(|h| sk.worlds[h]));
    if let (Some(hw), Some(p)) = (head_world, s.parts.iter_mut().find(|p| p.name == part_name(&mesh) && p.render_visible)) {
        let o = crate::pose::mat_vec(&hw, [0.0; 3]);
        p.positions = p.rest_positions.iter().map(|v| crate::pose::mat_vec(&hw, *v)).collect();
        p.normals = p.rest_normals.iter().map(|n| {
            let w = crate::pose::mat_vec(&hw, *n);
            let d = [w[0] - o[0], w[1] - o[1], w[2] - o[2]];
            let l = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt().max(1e-12);
            [d[0] / l, d[1] / l, d[2] / l]
        }).collect();
    }
    if let Some(p) = s.parts.iter_mut().find(|p| p.name == part_name(&mesh) && p.render_visible) {
        // Without a native hair shader on the character the hair is drawn with the item shader: its colour atlas is
        // sRGB like any colour texture (read raw it came out pale violet), and the item outline traces every card.
        if p.shader_kind == 8 { p.runtime_textures.insert("_MainTex".into(), [1, 0, 0, 1, 1]); p.source_outline_enabled = false; }
        if let Some(m) = p.source_material.as_mut() { m.name = stamp; }
    }
    report["part"] = serde_json::json!(part_name(&mesh));
    Ok(report)
}
/// `outfit<o>.accessory<k>` of the session's card that are her hair: every hair-category (121, 髪) accessory, every
/// accessory on a hair socket (`a_n_hair_*`), and the slots HairAccessoryCustomizer keeps data for that sit on her head
/// (it keeps data for necklaces too). Nothing without the card file.
fn card_hair_slots(s: &OkSession) -> Vec<String> {
    let Some(path) = s.card_path.as_deref() else { return Vec::new() };
    let Ok(first) = crate::card::parse_card_outfit(path, 0) else { return Vec::new() };
    let mut out = Vec::new();
    for o in 0..first.coordinate_count.max(1) as i32 {
        let info = if o == 0 { first.clone() } else { match crate::card::parse_card_outfit(path, o) { Ok(i) => i, Err(_) => continue } };
        for (k, a) in info.accessory.iter().enumerate() {
            let socket = a.parent_key.to_ascii_lowercase();
            let on_hair = socket.starts_with("a_n_hair");
            let on_head = on_hair || socket.starts_with("a_n_head");
            if a.type_id == 121 || on_hair || (on_head && info.hair_acc.contains_key(&(o, k as i32))) { out.push(format!("outfit{o}.accessory{k}")); }
        }
    }
    out
}

/// Session parts that are accessories but not her hair (bunny ears, hats, pins and ribbons): what a picture of her
/// face for HairDeck leaves out, else HairDeck draws them as hair (the user, 2026-11-22). A slot is hair when one of its
/// renderers is (a hair shader, or "hair" / "kami" in its mesh or renderer name), or it is a hair-category (121)
/// accessory; the whole slot then stays (Raiden's hair has a main_item layer under the same mesh). Not by socket: her
/// bunny ears sit on a hair socket and her long hair on the head one. HairDeck hair stays.
pub fn non_hair_accessory_parts(s: &OkSession) -> Vec<usize> {
    let slot = |sp: &str| -> String { match sp.match_indices('.').nth(1) { Some((i, _)) => sp[..i].to_string(), None => sp.to_string() } };
    let hairish = |p: &crate::session::SessionPart| {
        let shader = p.source_material.as_ref().map(|m| m.shader.to_ascii_lowercase()).unwrap_or_default();
        let named = |n: &str| { let n = n.to_ascii_lowercase(); n.contains("hair") || n.contains("kami") };
        shader.contains("main_hair") || named(&p.name) || p.source_renderer_names.iter().any(|r| named(r))
    };
    let mut hair: std::collections::HashSet<String> = card_hair_category_slots(s).into_iter().collect();
    for p in s.parts.iter().filter(|p| p.role == "accessory" && hairish(p)) { if let Some(sp) = &p.source_property { hair.insert(slot(sp)); } }
    s.parts.iter().enumerate().filter(|(_, p)| p.role == "accessory" && !p.name.starts_with("Tripo_")
        && !p.source_property.as_ref().is_some_and(|sp| hair.contains(&slot(sp))))
        .map(|(i, _)| i).collect()
}
/// `outfit<o>.accessory<k>` of the session's card in the hair category (121, 髪).
fn card_hair_category_slots(s: &OkSession) -> Vec<String> {
    let Some(path) = s.card_path.as_deref() else { return Vec::new() };
    let Ok(first) = crate::card::parse_card_outfit(path, 0) else { return Vec::new() };
    let mut out = Vec::new();
    for o in 0..first.coordinate_count.max(1) as i32 {
        let info = if o == 0 { first.clone() } else { match crate::card::parse_card_outfit(path, o) { Ok(i) => i, Err(_) => continue } };
        for (k, a) in info.accessory.iter().enumerate() { if a.type_id == 121 { out.push(format!("outfit{o}.accessory{k}")); } }
    }
    out
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

/// Checks a HairDeck result on a card without the game: opens the card (as the reader does), puts the hair on and
/// writes `out` (.obj, head-local): the head mesh, the hair and the hair bones (lines), plus the report.
pub fn preview_obj(lib: &Path, card: &Path, cards: &Path, opts: &HairDeckOpts, out: &Path) -> Result<serde_json::Value, String> {
    let mut s = match crate::oklib::open_original_card(Path::new(""), card, 0) { Some(r) => r?, None => crate::session::open(lib, Some(card), 0)? };
    s.card_path = Some(card.to_path_buf());
    let before: Vec<serde_json::Value> = s.parts.iter().filter(|p| p.role == "accessory" || p.role.starts_with("hair"))
        .map(|p| serde_json::json!([p.role, p.name, p.source_renderer_names, p.source_material.as_ref().map(|m| m.shader.clone()), p.render_visible, p.source_property])).collect();
    // OK_HAIR_INSPECT=<file.json>: her own native hair (shader 1 / 10) as it is before the new hair goes on — head-space
    // positions, UV0, UV1 and indices — and its _HairGloss beside it (<file>.gloss<i>.png); for studying the game's hair.
    if let Ok(dump) = std::env::var("OK_HAIR_INSPECT") {
        let sk = s.body_skel.as_ref().ok_or("missing body skeleton")?;
        let inv = crate::pose::mat_inv_pub(&sk.worlds[head(sk)?]);
        let dump = Path::new(&dump);
        let mut parts = Vec::new();
        for (i, p) in s.parts.iter().enumerate().filter(|(_, p)| matches!(p.shader_kind, 1 | 10)) {
            if let Some(g) = &p.hair_gloss { std::fs::write(dump.with_extension(format!("gloss{i}.png")), g).map_err(|e| e.to_string())?; }
            parts.push(serde_json::json!({"index": i, "name": p.name, "role": p.role, "visible": p.render_visible, "shader_kind": p.shader_kind,
                "positions": p.positions.iter().map(|q| crate::pose::mat_vec(&inv, *q)).collect::<Vec<_>>(), "uvs": p.uvs, "uv2": p.uv2, "indices": p.indices,
                "gloss": p.hair_gloss.as_ref().map(|g| g.len()), "gloss_st": p.hair_gloss_st}));
        }
        std::fs::write(dump, serde_json::to_vec(&serde_json::json!({"card": card, "parts": parts})).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    }
    let mut report = apply_files(&mut s, cards, opts)?;
    report["hair_parts_before"] = serde_json::json!(before);
    let sk = s.body_skel.as_ref().ok_or("missing body skeleton")?;
    let inv = crate::pose::mat_inv_pub(&sk.worlds[head(sk)?]);
    let mut obj = String::from("# head-local (Unity, metres)\n");
    let mut base = 1usize;
    let mut emit = |name: &str, pos: &[[f32; 3]], idx: &[u32], obj: &mut String| {
        obj.push_str(&format!("o {name}\n"));
        for p in pos { obj.push_str(&format!("v {} {} {}\n", p[0], p[1], p[2])); }
        for t in idx.chunks(3) { obj.push_str(&format!("f {} {} {}\n", base + t[0] as usize, base + t[1] as usize, base + t[2] as usize)); }
        base += pos.len();
    };
    if let Some(h) = s.parts.iter().find(|p| p.role == "head") {
        let pos: Vec<[f32; 3]> = h.positions.iter().map(|p| crate::pose::mat_vec(&inv, *p)).collect();
        emit("head", &pos, &h.indices, &mut obj);
    }
    let name = report["part"].as_str().unwrap_or("").to_string();
    let hair = s.parts.iter().find(|p| p.name == name).ok_or("hair part missing")?;
    emit("hair", &hair.rest_positions, &hair.indices, &mut obj);
    // (the gloss mask beside the OBJ, for a look)
    if let Some(g) = &hair.hair_gloss { std::fs::write(out.with_extension("gloss.png"), g).map_err(|e| e.to_string())?; }
    report["hair_material"] = serde_json::json!({"shader_kind": hair.shader_kind, "shader": hair.source_material.as_ref().map(|m| m.shader.clone()),
        "png": hair.png.as_ref().map(|p| p.len()), "shader_textures": hair.shader_textures.iter().map(|(k, v)| (k.clone(), v.len())).collect::<Vec<_>>(),
        "runtime_textures": hair.runtime_textures, "floats": hair.source_material.as_ref().map(|m| m.floats.clone()), "gloss_st": hair.hair_gloss_st, "blend": hair.blend, "unlit": hair.unlit, "item_draw": hair.item_draw.is_some(),
        "overtex": hair.overtex_png.as_ref().map(|p| p.len()), "renderer_names": hair.source_renderer_names, "skel_kind": hair.skel_kind,
        // the gloss mask and the range of UV1 (ring_uv)
        "gloss_png": hair.hair_gloss.as_ref().map(|g| g.len()), "uv1_range": hair.uv2.iter().fold([f32::MAX, f32::MAX, f32::MIN, f32::MIN], |r, q| [r[0].min(q[0]), r[1].min(q[1]), r[2].max(q[0]), r[3].max(q[1])]),
        "visible_after": s.parts.iter().filter(|p| p.render_visible && (p.role == "accessory" || p.role.starts_with("hair"))).map(|p| serde_json::json!([p.role, p.name, p.source_material.as_ref().map(|m| m.shader.clone())])).collect::<Vec<_>>(),
        "visible_hair": s.parts.iter().filter(|p| p.render_visible && (p.role.starts_with("hair") || p.name.to_ascii_lowercase().contains("hair"))).map(|p| p.name.clone()).collect::<Vec<_>>()});
    std::fs::write(out, obj).map_err(|e| e.to_string())?;
    if let Some(png) = &hair.png { std::fs::write(out.with_extension("png"), png).map_err(|e| e.to_string())?; }
    report["obj"] = serde_json::json!(out);
    Ok(report)
}

// ------------------------------------------------------------------ HairDeck hair kept in the card

/// A card's own HairDeck hair (`okHk`): zstd of a JSON `{"format":"ok-hairdeck","version":1,"cards":[...],
/// "chains":[...]|null,"opts":{...},"hair_color":[r,g,b],"source":"..."}` (`cards`/`chains` as HairDeck writes them,
/// `hair_color` the card's hair colour when the hair was put in). The display puts it on every session of the card
/// (`ok_session_apply_card_hairdeck`, where the reader's own HairDeck hair goes on); a card whose hair colour changed since (a bred child's mixed colour, the salon's dye) gets the
/// cards' colours moved by that difference.
pub const CHUNK: &[u8; 4] = b"okHk";
const FORMAT: &str = "ok-hairdeck";

#[derive(Serialize, Deserialize)]
struct Saved {
    format: String,
    version: u32,
    cards: serde_json::Value,
    #[serde(default)] chains: Option<serde_json::Value>,
    #[serde(default)] opts: HairDeckOpts,
    #[serde(default)] hair_color: Option<[f32; 3]>,
    #[serde(default)] source: Option<String>,
}

fn read_saved(payload: &[u8]) -> Result<Saved, String> {
    let json = zstd::stream::decode_all(payload).map_err(|e| format!("okHk: {e}"))?;
    let s: Saved = serde_json::from_slice(&json).map_err(|e| format!("okHk: {e}"))?;
    if s.format != FORMAT { return Err("okHk: not HairDeck hair".into()); }
    if s.version != 1 { return Err(format!("okHk: version {} (supported 1)", s.version)); }
    Ok(s)
}

/// The card's hair colour (as `card::parse_card_outfit` picks it), from its bytes.
fn card_hair_color(bytes: &[u8]) -> Option<[f32; 3]> {
    let info = crate::card::parse_card_bytes_mode(bytes, 0, false).ok()?;
    Some([info.hair_color[0], info.hair_color[1], info.hair_color[2]])
}

/// The HairDeck hair a card carries: its `okHk` payload (None: the card's own hair).
pub fn card_payload(bytes: &[u8]) -> Option<&[u8]> { crate::oklib::png_chunk(bytes, CHUNK) }

/// `card` (bytes) with this HairDeck hair (`cards_seed<s>.json`, its `chains_seed<s>.json` beside it) kept in it; None
/// takes the card's own hair back.
pub fn with_hair(card: &[u8], cards: Option<&Path>, opts: &HairDeckOpts) -> Result<Vec<u8>, String> {
    // (her identity stays what it was: a card without `okId` is known by its bytes)
    let Some(cards) = cards else {
        if card_payload(card).is_none() { return Ok(card.to_vec()); }
        let id = crate::oklib::card_identity(card);
        let plain = crate::cardbake::strip_kinds(card, &[CHUNK]).into_owned();
        return match id { Some(id) if crate::oklib::png_chunk(card, crate::oklib::IDENTITY_CHUNK).is_none() => crate::oklib::with_card_identity(&plain, &id), _ => Ok(plain) };
    };
    let read_json = |p: &Path| -> Result<serde_json::Value, String> {
        serde_json::from_slice(&crate::gamefs::read(p).map_err(|e| format!("{}: {e}", p.display()))?).map_err(|e| format!("{}: {e}", p.display()))
    };
    let deck = read_json(cards)?;
    if !deck.as_array().is_some_and(|a| !a.is_empty()) { return Err(format!("{}: no hair cards", cards.display())); }
    let name = cards.file_name().and_then(|n| n.to_str()).unwrap_or("");
    let chains_path = cards.with_file_name(name.replacen("cards_", "chains_", 1));
    let chains = if name.starts_with("cards_") && chains_path.ok_is_file() { Some(read_json(&chains_path)?) } else { None };
    // A bred child's hair drawn from her parents' faces (`mix`) has their colours as the model saw them; kept against
    // its own mean colour, it opens moved to her card's hair colour (mixed in HSV by breeding), so it follows her genes.
    let hair_color = if opts.mix.is_some() { deck_mean_color(&deck).or_else(|| card_hair_color(card)) } else { card_hair_color(card) };
    let saved = Saved { format: FORMAT.into(), version: 1, cards: deck, chains, opts: opts.clone(), hair_color,
        source: cards.parent().and_then(|d| d.file_name()).map(|d| format!("{}/{name}", d.to_string_lossy())) };
    let payload = zstd::stream::encode_all(&serde_json::to_vec(&saved).map_err(|e| e.to_string())?[..], 9).map_err(|e| e.to_string())?;
    crate::tree_answers::with_chunk(card, CHUNK, &payload)
}

/// `with_hair` on files: `card` with the hair of `cards` (None: without HairDeck hair), written to `out` (may be `card`).
pub fn put_into_card(card: &Path, cards: Option<&Path>, opts: &HairDeckOpts, out: &Path) -> Result<String, String> {
    let bytes = crate::gamefs::read(card).map_err(|e| format!("{}: {e}", card.display()))?;
    let made = with_hair(&bytes, cards, opts)?;
    std::fs::write(out, &made).map_err(|e| format!("{}: {e}", out.display()))?;
    Ok(match card_payload(&made) {
        Some(p) => format!("HairDeck hair kept in the card ({} bytes)", p.len()),
        None => "the card's own hair".into(),
    })
}

/// The mean of the cards' colours (sRGB 0..1), None without any.
fn deck_mean_color(cards: &serde_json::Value) -> Option<[f32; 3]> {
    let (mut sum, mut n) = ([0f64; 3], 0usize);
    for c in cards.as_array().into_iter().flatten().filter_map(|card| card.get("colors")).filter_map(|c| c.as_array()).flatten() {
        let Some(rgb) = c.as_array() else { continue };
        if rgb.len() < 3 { continue; }
        for i in 0..3 { sum[i] += rgb[i].as_f64().unwrap_or(0.0); }
        n += 1;
    }
    (n > 0).then(|| [0, 1, 2].map(|i| (sum[i] / n as f64) as f32))
}

/// Cards whose colours are moved by `shift` (clamped to 0..1).
fn shifted_cards(cards: &serde_json::Value, shift: [f32; 3]) -> serde_json::Value {
    let mut out = cards.clone();
    for card in out.as_array_mut().into_iter().flatten() {
        for c in card.get_mut("colors").and_then(|c| c.as_array_mut()).into_iter().flatten() {
            if let Some(rgb) = c.as_array_mut() {
                for (i, v) in rgb.iter_mut().take(3).enumerate() {
                    if let Some(x) = v.as_f64() { *v = serde_json::json!((x + shift[i] as f64).clamp(0.0, 1.0)); }
                }
            }
        }
    }
    out
}

/// The HairDeck hair kept in the card `bytes` (`okHk`) put on her session: Ok(None) when the card has none.
pub fn apply_card(s: &mut OkSession, card: &Path, bytes: &[u8]) -> Result<Option<serde_json::Value>, String> {
    let Some(payload) = card_payload(bytes) else { return Ok(None) };
    let saved = read_saved(payload)?;
    let shift = match (saved.hair_color, card_hair_color(bytes)) {
        (Some(was), Some(now)) => [now[0] - was[0], now[1] - was[1], now[2] - was[2]],
        _ => [0.0; 3],
    };
    let moved = shift.iter().any(|d| d.abs() > 0.002);
    let cards = if moved { shifted_cards(&saved.cards, shift) } else { saved.cards };
    let cards = serde_json::to_vec(&cards).map_err(|e| e.to_string())?;
    let chains = saved.chains.as_ref().map(serde_json::to_vec).transpose().map_err(|e| e.to_string())?;
    // (the hair slots and colour of her card: apply reads them by the card's path)
    if s.card_path.is_none() { s.card_path = Some(card.to_path_buf()); }
    let mut report = apply(s, &cards, chains.as_deref(), &saved.opts)?;
    report["from_card"] = serde_json::json!(saved.source);
    if moved { report["colour_shift"] = serde_json::json!(shift); }
    Ok(Some(report))
}

/// For breeding: `child` (bytes) with the HairDeck hair of the parent her hair came from (`hair_parent`), or none.
pub fn inherit(child: &[u8], hair_parent: &[u8]) -> Result<Vec<u8>, String> {
    match card_payload(hair_parent) {
        Some(p) => crate::cardbake::with_chunk(child, CHUNK, p),
        None => Ok(crate::cardbake::strip_kinds(child, &[CHUNK]).into_owned()),
    }
}

#[cfg(test)]
mod card_tests {
    use super::*;
    #[test]
    fn colours_move_with_the_card() {
        let cards = serde_json::json!([{"seq": [[0.0]], "colors": [[0.5, 0.2, 0.9], [0.1, 0.0, 1.0]]}]);
        let out = shifted_cards(&cards, [0.1, -0.1, 0.2]);
        let c = &out[0]["colors"];
        assert!((c[0][0].as_f64().unwrap() - 0.6).abs() < 1e-6 && (c[0][1].as_f64().unwrap() - 0.1).abs() < 1e-6);
        assert_eq!(c[1][1].as_f64().unwrap(), 0.0);
        assert_eq!(c[1][2].as_f64().unwrap(), 1.0);
    }
}
