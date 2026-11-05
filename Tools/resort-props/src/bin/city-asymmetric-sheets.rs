//! Partition two-sided opaque triangles by opposing one-sided opaque coverage.
//! Overlap becomes front-only; the uncovered remainder stays two-sided.
//! Mesh-local centimetres. The one-sided cover triangle is not edited.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
};

type V = [f64; 3];
type P = [f64; 2];
type Cell = (u8, i64, i64, i64, i64);

const PLANE_TOL: f64 = 0.002;
const NORMAL_DOT_MAX: f64 = -0.999999;
const MIN_OVERLAP_CM2: f64 = 1.0;
const MIN_OVERLAP_FRACTION: f64 = 1e-5;
/// Same cell size as the depth scanner. Padding is wider than the plane
/// tolerance so a triangle sitting on a cell face is inserted on both sides.
const CELL: f64 = 500.0;
const CELL_PAD: f64 = 0.4;
const INTERCEPT_BIN: f64 = 2.0;
/// ±3 bins, matching the scanner, covers a rounding boundary and a small
/// normal tilt. A single origin-centred plane bucket does not.
const INTERCEPT_NEIGHBOR: i64 = 3;
const MAX_CELLS: i64 = 4096;
// Fine binary grid: coarse 2^-20 weights moved large-face cuts outside small
// cover triangles. Keep boundaries deterministic without millimetre snapping.
const BARY_Q: f64 = 1.0 / 17592186044416.0;
const MAX_POLYGONS: usize = 4096;
// A convex polygon needs n-2 triangles; shared-boundary vertices can exceed
// the polygon count. Keep an independent, finite emitted triangle budget.
const MAX_PIECES: usize = 8192;
const MAX_VERTICES: usize = 512;

fn sub(a: V, b: V) -> V {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn dot(a: V, b: V) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}
fn cross(a: V, b: V) -> V {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}
fn side(a: P, b: P, p: P) -> f64 {
    (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
}
fn area2(poly: &[P]) -> f64 {
    if poly.len() < 3 {
        return 0.0;
    }
    let mut s = 0.0;
    for i in 0..poly.len() {
        let j = (i + 1) % poly.len();
        s += poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1];
    }
    s * 0.5
}
fn dist_to_plane(n: V, origin: V, p: V) -> f64 {
    dot(n, sub(p, origin)).abs()
}
fn hex_sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn u32at(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes(b[i..i + 4].try_into().unwrap())
}

fn dedup_poly(poly: &mut Vec<P>) {
    poly.dedup_by(|a, b| (a[0] - b[0]).abs() + (a[1] - b[1]).abs() < 1e-9);
    if poly.len() >= 2 {
        let a = poly[0];
        let b = *poly.last().unwrap();
        if (a[0] - b[0]).abs() + (a[1] - b[1]).abs() < 1e-9 {
            poly.pop();
        }
    }
}

/// Complementary half-planes share the boundary (`s >= 0` and `s <= 0`).
/// An epsilon gap would drop a sliver; an epsilon overlap would duplicate it.
fn split_line(poly: &[P], a: P, b: P, sign: f64) -> (Vec<P>, Vec<P>) {
    if poly.is_empty() {
        return (vec![], vec![]);
    }
    let mut inn = vec![];
    let mut out = vec![];
    let mut prev = *poly.last().unwrap();
    let mut s0 = side(a, b, prev) * sign;
    for &cur in poly {
        let s1 = side(a, b, cur) * sign;
        let in0 = s0 >= 0.0;
        let in1 = s1 >= 0.0;
        if in0 != in1 {
            let denom = s0 - s1;
            let t = if denom == 0.0 { 0.0 } else { s0 / denom };
            let hit = [
                prev[0] + (cur[0] - prev[0]) * t,
                prev[1] + (cur[1] - prev[1]) * t,
            ];
            inn.push(hit);
            out.push(hit);
        }
        if s1 >= 0.0 {
            inn.push(cur);
        }
        if s1 <= 0.0 {
            out.push(cur);
        }
        prev = cur;
        s0 = s1;
    }
    dedup_poly(&mut inn);
    dedup_poly(&mut out);
    (inn, out)
}

fn clip_cover(poly: &[P], cover: &[P; 3]) -> (Vec<P>, Vec<Vec<P>>) {
    let sign = area2(cover).signum();
    if sign == 0.0 {
        return (vec![], vec![poly.to_vec()]);
    }
    let mut inside = poly.to_vec();
    let mut outside = vec![];
    for k in 0..3 {
        let (inn, out) = split_line(&inside, cover[k], cover[(k + 1) % 3], sign);
        if out.len() >= 3 && area2(&out).abs() > 1e-12 {
            outside.push(out);
        }
        inside = inn;
        if inside.len() < 3 || area2(&inside).abs() <= 1e-12 {
            inside.clear();
            break;
        }
    }
    (inside, outside)
}

#[derive(Clone)]
struct Tri {
    p: [V; 3],
    n: V,
    /// Dominant-axis sign flipped so opposite windings share a plane bin.
    n_bin: V,
    origin: V,
    drop: usize,
    axes: [usize; 2],
    local: [P; 3],
    area: f64,
    lo: V,
    hi: V,
}

impl Tri {
    fn new(p: [V; 3]) -> Option<Self> {
        let e1 = sub(p[1], p[0]);
        let e2 = sub(p[2], p[0]);
        let c = cross(e1, e2);
        let size = dot(c, c).sqrt();
        if !size.is_finite() || size < 1e-7 {
            return None;
        }
        let n = c.map(|v| v / size);
        if !n.iter().all(|v| v.is_finite()) {
            return None;
        }
        let drop = (0..3)
            .max_by(|&i, &j| n[i].abs().total_cmp(&n[j].abs()))
            .unwrap();
        let mut n_bin = n;
        if n[drop] < 0.0 {
            n_bin = n.map(|v| -v);
        }
        let axes = {
            let mut a = [0usize; 2];
            let mut naxis = 0;
            for i in 0..3 {
                if i != drop {
                    a[naxis] = i;
                    naxis += 1;
                }
            }
            a
        };
        let project = |v: V| [v[axes[0]] - p[0][axes[0]], v[axes[1]] - p[0][axes[1]]];
        let local = p.map(project);
        if area2(&local).abs() < 1e-12 {
            return None;
        }
        let mut lo = p[0];
        let mut hi = p[0];
        for v in &p[1..] {
            for k in 0..3 {
                lo[k] = lo[k].min(v[k]);
                hi[k] = hi[k].max(v[k]);
            }
        }
        Some(Self {
            p,
            n,
            n_bin,
            origin: p[0],
            drop,
            axes,
            local,
            area: size * 0.5,
            lo,
            hi,
        })
    }

    fn project(&self, p: V) -> P {
        [
            p[self.axes[0]] - self.origin[self.axes[0]],
            p[self.axes[1]] - self.origin[self.axes[1]],
        ]
    }

    fn bary(&self, p: P) -> [f64; 3] {
        let den = side(self.local[0], self.local[1], self.local[2]);
        let a = side(self.local[1], self.local[2], p) / den;
        let b = side(self.local[2], self.local[0], p) / den;
        [a, b, 1.0 - a - b]
    }

    fn area_of(&self, poly: &[P]) -> f64 {
        area2(poly).abs() / self.n[self.drop].abs()
    }
}

fn canon_bary(mut b: [f64; 3]) -> [f64; 3] {
    for v in &mut b {
        if !v.is_finite() {
            *v = 0.0;
        }
        *v = (*v / BARY_Q).round() * BARY_Q;
    }
    let mut k = 0usize;
    for i in 1..3 {
        if b[i].abs() > b[k].abs() {
            k = i;
        }
    }
    let rest = b[(k + 1) % 3] + b[(k + 2) % 3];
    b[k] = 1.0 - rest;
    b
}

fn bary_key(b: [f64; 3]) -> [i64; 3] {
    b.map(|v| (v / BARY_Q).round() as i64)
}

fn weld(b: [f64; 3], verts: &mut Vec<[f64; 3]>) -> [f64; 3] {
    let q = canon_bary(b);
    for v in verts.iter() {
        let d = (0..3).map(|i| (v[i] - q[i]).abs()).fold(0.0, f64::max);
        // Half a quantum collapses only values that round to the same place,
        // including a value and the representative already stored for it.
        if d <= BARY_Q * 0.51 {
            return *v;
        }
    }
    verts.push(q);
    q
}

fn same_bary(a: [f64; 3], b: [f64; 3]) -> bool {
    bary_key(a) == bary_key(b)
}

fn on_segment(a: [f64; 3], b: [f64; 3], v: [f64; 3]) -> Option<f64> {
    let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let len2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
    if len2 < 1e-24 {
        return None;
    }
    let av = [v[0] - a[0], v[1] - a[1], v[2] - a[2]];
    let t = (av[0] * ab[0] + av[1] * ab[1] + av[2] * ab[2]) / len2;
    if t <= 1e-7 || t >= 1.0 - 1e-7 {
        return None;
    }
    let mut d = 0.0f64;
    for i in 0..3 {
        d = d.max((v[i] - (a[i] + ab[i] * t)).abs());
    }
    if d <= BARY_Q * 4.0 {
        Some(t)
    } else {
        None
    }
}

fn split_t_junctions(polys: &mut [Vec<[f64; 3]>]) {
    for _ in 0..8 {
        let verts: Vec<[f64; 3]> = polys.iter().flatten().copied().collect();
        let mut changed = false;
        for poly in polys.iter_mut() {
            if poly.len() < 2 {
                continue;
            }
            let mut next = Vec::with_capacity(poly.len() + 4);
            for i in 0..poly.len() {
                let a = poly[i];
                let b = poly[(i + 1) % poly.len()];
                next.push(a);
                let mut mids = vec![];
                for v in &verts {
                    if same_bary(*v, a) || same_bary(*v, b) {
                        continue;
                    }
                    if poly.iter().any(|p| same_bary(*p, *v)) {
                        continue;
                    }
                    if let Some(t) = on_segment(a, b, *v) {
                        mids.push((t, *v));
                    }
                }
                mids.sort_by(|x, y| x.0.total_cmp(&y.0));
                for (_, v) in mids {
                    if next.last().map(|p| !same_bary(*p, v)).unwrap_or(true) {
                        next.push(v);
                    }
                }
            }
            if next.len() >= 2 && same_bary(next[0], *next.last().unwrap()) {
                next.pop();
            }
            if next.len() != poly.len() {
                changed = true;
                *poly = next;
            }
            if poly.len() > MAX_VERTICES {
                panic!(
                    "fragmentation explosion while welding boundaries: {} vertices",
                    poly.len()
                );
            }
        }
        if !changed {
            return;
        }
    }
    panic!("fragmentation explosion: T-junction weld did not settle");
}

#[derive(Clone, Copy)]
struct RawTri {
    p: [V; 3],
    slot: u32,
    id: i32,
}

struct SlotFlag {
    blend: i64,
    two_sided: bool,
}

struct Piece {
    bary: [[f64; 3]; 3],
    front_only: bool,
}

struct Patch {
    triangle: i32,
    material_slot: u32,
    area_before_cm2: f64,
    area_after_cm2: f64,
    front_only_area_cm2: f64,
    cover_triangles: Vec<i32>,
    pieces: Vec<Piece>,
}

#[derive(Clone)]
struct Prepared {
    tri: Tri,
    slot: u32,
    id: i32,
    two_sided: bool,
}

fn lift(p: &[V; 3], b: [f64; 3]) -> V {
    std::array::from_fn(|k| p[0][k] * b[0] + p[1][k] * b[1] + p[2][k] * b[2])
}

fn piece_area(p: &[V; 3], b: &[[f64; 3]; 3]) -> f64 {
    let q = b.map(|w| lift(p, w));
    let n = cross(sub(q[1], q[0]), sub(q[2], q[0]));
    0.5 * dot(n, n).sqrt()
}

fn area_quantum_tol(tri: &Tri) -> f64 {
    let mut edges = 0.0;
    let mut longest = 0.0f64;
    for i in 0..3 {
        let d = sub(tri.p[i], tri.p[(i + 1) % 3]);
        let len = dot(d, d).sqrt();
        edges += len;
        longest = longest.max(len);
    }
    let pos = 0.5 * BARY_Q * longest;
    (1e-4 + edges * pos).max(1e-4)
}

/// Cell-relative intercept. `visit` returns false when the triangle is too
/// large to bin; callers then test it directly instead of dropping it.
fn visit_cells(t: &Tri, mut f: impl FnMut(Cell)) -> bool {
    let lo = t.lo.map(|x| ((x - CELL_PAD) / CELL).floor() as i64);
    let hi = t.hi.map(|x| ((x + CELL_PAD) / CELL).floor() as i64);
    let count = (hi[0] - lo[0] + 1) * (hi[1] - lo[1] + 1) * (hi[2] - lo[2] + 1);
    if count > MAX_CELLS || count <= 0 {
        return false;
    }
    for x in lo[0]..=hi[0] {
        for y in lo[1]..=hi[1] {
            for z in lo[2]..=hi[2] {
                let c = [
                    (x as f64 + 0.5) * CELL,
                    (y as f64 + 0.5) * CELL,
                    (z as f64 + 0.5) * CELL,
                ];
                let rel = sub(t.origin, c);
                for axis in 0..3 {
                    if t.n_bin[axis].abs() < 0.55 {
                        continue;
                    }
                    let intercept = dot(t.n_bin, rel) / t.n_bin[axis];
                    if !intercept.is_finite() {
                        continue;
                    }
                    f((
                        axis as u8,
                        (intercept / INTERCEPT_BIN).round() as i64,
                        x,
                        y,
                        z,
                    ));
                }
            }
        }
    }
    true
}

#[cfg(test)]
fn bins_overlap(a: &Tri, b: &Tri) -> bool {
    let mut keys = HashSet::new();
    let a_small = visit_cells(a, |key| {
        for dp in -INTERCEPT_NEIGHBOR..=INTERCEPT_NEIGHBOR {
            let mut k = key;
            k.1 += dp;
            keys.insert(k);
        }
    });
    if !a_small {
        return true;
    }
    let mut found = false;
    let b_small = visit_cells(b, |key| found |= keys.contains(&key));
    !b_small || found
}

struct CoverIndex {
    grid: HashMap<Cell, Vec<usize>>,
    large: Vec<usize>,
}

impl CoverIndex {
    fn build(covers: &[Prepared]) -> Self {
        let mut grid: HashMap<Cell, Vec<usize>> = HashMap::new();
        let mut large = vec![];
        for (i, c) in covers.iter().enumerate() {
            let small = visit_cells(&c.tri, |key| {
                grid.entry(key).or_default().push(i);
            });
            if !small {
                large.push(i);
            }
        }
        Self { grid, large }
    }

    fn query(&self, target: &Tri, ncovers: usize) -> Vec<usize> {
        let mut out = self.large.clone();
        let small = visit_cells(target, |key| {
            for dp in -INTERCEPT_NEIGHBOR..=INTERCEPT_NEIGHBOR {
                let mut k = key;
                k.1 += dp;
                if let Some(v) = self.grid.get(&k) {
                    out.extend(v.iter().copied());
                }
            }
        });
        if !small {
            out.extend(0..ncovers);
        }
        out.sort_unstable();
        out.dedup();
        out
    }
}

fn aabb_separated(a: &Tri, b: &Tri) -> bool {
    (0..3).any(|k| a.lo[k] > b.hi[k] + PLANE_TOL || b.lo[k] > a.hi[k] + PLANE_TOL)
}

fn overlap_area(target: &Tri, cover: &Tri) -> f64 {
    let c = cover.p.map(|p| target.project(p));
    let (inter, _) = clip_cover(&target.local, &c);
    if inter.len() < 3 {
        0.0
    } else {
        target.area_of(&inter)
    }
}

fn qualifying_overlap(target: &Tri, cover: &Tri) -> Option<f64> {
    if dot(target.n, cover.n) > NORMAL_DOT_MAX {
        return None;
    }
    if aabb_separated(target, cover) {
        return None;
    }
    if target
        .p
        .iter()
        .any(|p| dist_to_plane(cover.n, cover.origin, *p) > PLANE_TOL)
        || cover
            .p
            .iter()
            .any(|p| dist_to_plane(target.n, target.origin, *p) > PLANE_TOL)
    {
        return None;
    }
    let area = overlap_area(target, cover);
    let smaller = target.area.min(cover.area);
    if area > MIN_OVERLAP_CM2 && area > smaller * MIN_OVERLAP_FRACTION {
        Some(area)
    } else {
        None
    }
}

fn triangulate(poly: &[[f64; 3]], positions: &[V; 3], front_only: bool) -> Vec<Piece> {
    let mut pieces = vec![];
    if poly.len() < 3 {
        return pieces;
    }
    let origin_n = cross(sub(positions[1], positions[0]), sub(positions[2], positions[0]));
    for i in 1..poly.len() - 1 {
        let bary = [poly[0], poly[i], poly[i + 1]];
        if same_bary(bary[0], bary[1]) || same_bary(bary[1], bary[2]) || same_bary(bary[0], bary[2])
        {
            continue;
        }
        let q = bary.map(|w| lift(positions, w));
        let n = cross(sub(q[1], q[0]), sub(q[2], q[0]));
        if dot(n, origin_n) <= 1e-8 {
            continue;
        }
        pieces.push(Piece { bary, front_only });
    }
    pieces
}

fn polygons_from(pending: &[Vec<P>], tri: &Tri, verts: &mut Vec<[f64; 3]>) -> Vec<Vec<[f64; 3]>> {
    let mut polys = vec![];
    for poly in pending {
        let mut out = vec![];
        for p in poly {
            let b = weld(tri.bary(*p), verts);
            if out.last().map(|q| !same_bary(*q, b)).unwrap_or(true) {
                out.push(b);
            }
        }
        if out.len() >= 2 && same_bary(out[0], *out.last().unwrap()) {
            out.pop();
        }
        if out.len() >= 3 {
            polys.push(out);
        }
    }
    polys
}

fn partition_one(
    target: &Prepared,
    covers: &[Prepared],
    index: &CoverIndex,
) -> Result<Option<Patch>, String> {
    let mut accepted: Vec<(i32, f64, [P; 3])> = vec![];
    for i in index.query(&target.tri, covers.len()) {
        let cover = &covers[i];
        if cover.id == target.id && cover.slot == target.slot {
            continue;
        }
        if let Some(area) = qualifying_overlap(&target.tri, &cover.tri) {
            let local = cover.tri.p.map(|p| target.tri.project(p));
            accepted.push((cover.id, area, local));
        }
    }
    if accepted.is_empty() {
        return Ok(None);
    }
    accepted.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.total_cmp(&b.1)));
    accepted.dedup_by(|a, b| a.0 == b.0);
    let overlap_sum: f64 = accepted.iter().map(|c| c.1).sum();
    let max_overlap = accepted.iter().map(|c| c.1).fold(0.0, f64::max);

    let mut pending = vec![target.tri.local.to_vec()];
    let mut front: Vec<Vec<P>> = vec![];
    for (_, _, local) in &accepted {
        let mut next = vec![];
        for poly in &pending {
            let (inside, outside) = clip_cover(poly, local);
            if inside.len() >= 3 && target.tri.area_of(&inside) > 1e-8 {
                front.push(inside);
            }
            next.extend(outside);
        }
        pending = next;
        if pending.len() + front.len() > MAX_POLYGONS {
            return Err(format!(
                "fragmentation explosion on triangle {}: {} polygons",
                target.id,
                pending.len() + front.len()
            ));
        }
    }

    let front_raw: f64 = front.iter().map(|p| target.tri.area_of(p)).sum();
    let back_raw: f64 = pending.iter().map(|p| target.tri.area_of(p)).sum();
    let raw_tol = 1e-3 + target.tri.area * 1e-9;
    if (front_raw + back_raw - target.tri.area).abs() > raw_tol
        || front_raw > overlap_sum + raw_tol
        || front_raw + raw_tol < max_overlap
    {
        return Err(format!(
            "area loss or duplication on triangle {}: before={} front={} back={} overlap_sum={} max_overlap={}",
            target.id, target.tri.area, front_raw, back_raw, overlap_sum, max_overlap
        ));
    }
    if front_raw <= MIN_OVERLAP_CM2 * 0.5 {
        return Err(format!(
            "accepted cover produced no front-only area on triangle {}",
            target.id
        ));
    }

    let mut verts = vec![];
    let mut front_b = polygons_from(&front, &target.tri, &mut verts);
    let mut back_b = polygons_from(&pending, &target.tri, &mut verts);
    let nfront = front_b.len();
    let mut all = front_b;
    all.append(&mut back_b);
    split_t_junctions(&mut all);
    front_b = all[..nfront].to_vec();
    let back_b = all[nfront..].to_vec();

    let mut pieces = vec![];
    for poly in &front_b {
        pieces.extend(triangulate(poly, &target.tri.p, true));
    }
    for poly in &back_b {
        pieces.extend(triangulate(poly, &target.tri.p, false));
    }
    if pieces.len() > MAX_PIECES {
        return Err(format!(
            "fragmentation explosion on triangle {}: {} pieces; source_area={} front={} back={} covers={}",
            target.id,
            pieces.len(), target.tri.area, front_raw, back_raw, accepted.len()
        ));
    }
    let mut front_area = 0.0;
    let mut back_area = 0.0;
    for piece in &pieces {
        let area = piece_area(&target.tri.p, &piece.bary);
        if piece.front_only {
            front_area += area;
        } else {
            back_area += area;
        }
    }
    let qtol = area_quantum_tol(&target.tri);
    if (front_area - front_raw).abs() > qtol
        || (back_area - back_raw).abs() > qtol
        || (front_area + back_area - target.tri.area).abs() > qtol
    {
        return Err(format!(
            "quantized pieces changed area on triangle {}: raw {}/{} emitted {}/{} before {}",
            target.id, front_raw, back_raw, front_area, back_area, target.tri.area
        ));
    }
    let mut ids: Vec<i32> = accepted.iter().map(|c| c.0).collect();
    ids.sort_unstable();
    ids.dedup();
    Ok(Some(Patch {
        triangle: target.id,
        material_slot: target.slot,
        area_before_cm2: target.tri.area,
        area_after_cm2: front_area + back_area,
        front_only_area_cm2: front_area,
        cover_triangles: ids,
        pieces,
    }))
}

fn partition_lod(raw: &[RawTri], slots: &[SlotFlag]) -> Result<Vec<Patch>, String> {
    let mut prepared = vec![];
    for tri in raw {
        let Some(flag) = slots.get(tri.slot as usize) else {
            continue;
        };
        if flag.blend != 0 {
            continue;
        }
        let Some(geom) = Tri::new(tri.p) else {
            continue;
        };
        prepared.push(Prepared {
            tri: geom,
            slot: tri.slot,
            id: tri.id,
            two_sided: flag.two_sided,
        });
    }
    let covers: Vec<Prepared> = prepared.iter().filter(|t| !t.two_sided).cloned().collect();
    let index = CoverIndex::build(&covers);
    let mut patches = vec![];
    for target in prepared.iter().filter(|t| t.two_sided) {
        if let Some(patch) = partition_one(target, &covers, &index)? {
            patches.push(patch);
        }
    }
    Ok(patches)
}

fn read_cdy2(path: &Path) -> Vec<RawTri> {
    let b = fs::read(path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    let magic = u32at(&b, 0);
    assert_eq!(magic, 0x43445932, "CDY2 per-triangle slots required");
    let nv = u32at(&b, 4) as usize;
    let nt = u32at(&b, 8) as usize;
    assert_eq!(b.len(), 12 + nv * 12 + nt * 20, "truncated CDY2 {}", path.display());
    let mut points = Vec::with_capacity(nv);
    for i in 0..nv {
        points.push(std::array::from_fn(|k| {
            f32::from_bits(u32at(&b, 12 + i * 12 + k * 4)) as f64
        }));
    }
    let start = 12 + nv * 12;
    let mut out = Vec::with_capacity(nt);
    for i in 0..nt {
        let idx = std::array::from_fn(|k| u32at(&b, start + i * 12 + k * 4) as usize);
        let id = u32at(&b, start + nt * 12 + i * 4) as i32;
        let slot = u32at(&b, start + nt * 16 + i * 4);
        out.push(RawTri {
            p: idx.map(|v| points[v]),
            slot,
            id,
        });
    }
    out
}

struct InstanceSig {
    key: String,
    blend: Vec<i64>,
    two_sided: Vec<bool>,
}

fn instance_signature(inst: &Value) -> Result<InstanceSig, String> {
    let key = inst["key"]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| "missing component key".to_string())?
        .to_string();
    let blends = inst["blend_modes"]
        .as_array()
        .ok_or_else(|| format!("{key} missing blend_modes"))?;
    let sides = inst["two_sided_by_slot"]
        .as_array()
        .ok_or_else(|| format!("{key} missing two_sided_by_slot"))?;
    if blends.len() != sides.len() {
        return Err(format!(
            "{key} blend_modes and two_sided_by_slot differ in length"
        ));
    }
    let mut blend = Vec::with_capacity(blends.len());
    let mut two_sided = Vec::with_capacity(sides.len());
    for i in 0..blends.len() {
        blend.push(
            blends[i]
                .as_i64()
                .ok_or_else(|| format!("{key} blend_modes[{i}] is not an integer"))?,
        );
        two_sided.push(
            sides[i]
                .as_bool()
                .ok_or_else(|| format!("{key} two_sided_by_slot[{i}] is not a bool"))?,
        );
    }
    Ok(InstanceSig {
        key,
        blend,
        two_sided,
    })
}

fn patch_json(patch: &Patch) -> Value {
    json!({
        "triangle": patch.triangle,
        "material_slot": patch.material_slot,
        "area_before_cm2": patch.area_before_cm2,
        "area_after_cm2": patch.area_after_cm2,
        "front_only_area_cm2": patch.front_only_area_cm2,
        "cover_triangles": patch.cover_triangles,
        "pieces": patch.pieces.iter().map(|p| json!({
            "barycentric": p.bary,
            "front_only": p.front_only
        })).collect::<Vec<_>>()
    })
}

fn build_plan(folder: &Path, inventory_path: &Path) -> Value {
    let inventory: Value = serde_json::from_slice(
        &fs::read(inventory_path)
            .unwrap_or_else(|e| panic!("read {}: {e}", inventory_path.display())),
    )
    .unwrap_or_else(|e| panic!("parse {}: {e}", inventory_path.display()));
    let floor_labels: HashSet<String> = inventory["actors"]
        .as_array()
        .unwrap_or_else(|| panic!("inventory actors array required"))
        .iter()
        .filter(|a| a["building_floor"] == true)
        .map(|a| {
            a["label"]
                .as_str()
                .unwrap_or_else(|| panic!("building_floor actor missing label"))
                .to_string()
        })
        .collect();
    let scene_bytes = fs::read(folder.join("scene.json"))
        .unwrap_or_else(|e| panic!("read scene.json: {e}"));
    let scene_sha256 = hex_sha256(&scene_bytes);
    let scene: Value = serde_json::from_slice(&scene_bytes).expect("scene.json");
    assert!(
        scene["format"].as_str().unwrap_or("").starts_with("CDY2"),
        "Fresh CDY2 export with per-triangle material slots required"
    );
    let instances = scene["instances"]
        .as_array()
        .unwrap_or_else(|| panic!("scene instances array required"));
    let meshes = scene["meshes"]
        .as_array()
        .unwrap_or_else(|| panic!("scene meshes array required"));
    let selected: HashSet<u64> = instances
        .iter()
        .filter(|i| {
            i["actor"]
                .as_str()
                .is_some_and(|label| floor_labels.contains(label))
        })
        .map(|i| i["mesh"].as_u64().expect("instance mesh index"))
        .collect();

    let mut plans = vec![];
    let mut blocked = vec![];
    let mut modified = 0u64;
    let mut converted = 0.0;
    for (mid, mesh) in meshes.iter().enumerate() {
        if !selected.contains(&(mid as u64)) {
            continue;
        }
        let refs: Vec<&Value> = instances
            .iter()
            .filter(|i| i["mesh"].as_u64() == Some(mid as u64))
            .collect();
        let asset = mesh["asset"].as_str().unwrap_or("").to_string();
        let mut signatures = vec![];
        let mut broken = None;
        for inst in &refs {
            match instance_signature(inst) {
                Ok(sig) => signatures.push(sig),
                Err(reason) => {
                    broken = Some(reason);
                    break;
                }
            }
        }
        signatures.sort_by(|a, b| a.key.cmp(&b.key));
        let mut keys: Vec<String> = signatures.iter().map(|s| s.key.clone()).collect();
        keys.dedup();
        let agree = broken.is_none()
            && !signatures.is_empty()
            && signatures.windows(2).all(|w| {
                w[0].blend == w[1].blend && w[0].two_sided == w[1].two_sided
            });
        if !agree {
            let reason = broken.unwrap_or_else(|| {
                if signatures.is_empty() {
                    "mesh has no instances".to_string()
                } else {
                    "instances disagree on per-slot blend_modes or two_sided_by_slot".to_string()
                }
            });
            blocked.push(json!({
                "source_asset": asset,
                "reason": reason,
                "component_keys": keys,
                "signatures": signatures.iter().map(|s| json!({
                    "component_key": s.key,
                    "blend_modes": s.blend,
                    "two_sided_by_slot": s.two_sided
                })).collect::<Vec<_>>()
            }));
            continue;
        }
        let flags: Vec<SlotFlag> = signatures[0]
            .blend
            .iter()
            .zip(&signatures[0].two_sided)
            .map(|(&blend, &two_sided)| SlotFlag { blend, two_sided })
            .collect();
        let mut lods = vec![];
        let Some(lod_list) = mesh["lods"].as_array() else {
            continue;
        };
        for lod in lod_list {
            let file = lod["file"].as_str().expect("lod file");
            let bytes = fs::read(folder.join(file))
                .unwrap_or_else(|e| panic!("read {file}: {e}"));
            let source_sha256 = hex_sha256(&bytes);
            let raw = read_cdy2(&folder.join(file));
            let patches = partition_lod(&raw, &flags).unwrap_or_else(|e| {
                panic!("mesh {asset} lod {}: {e}", lod["lod"])
            });
            if patches.is_empty() {
                continue;
            }
            modified += patches.len() as u64;
            converted += patches.iter().map(|p| p.front_only_area_cm2).sum::<f64>();
            lods.push(json!({
                "lod": lod["lod"],
                "source_sha256": source_sha256,
                "patches": patches.iter().map(patch_json).collect::<Vec<_>>()
            }));
        }
        if !lods.is_empty() {
            plans.push(json!({
                "source_asset": asset,
                "component_keys": keys,
                "blend_modes": signatures[0].blend,
                "two_sided_by_slot": signatures[0].two_sided,
                "lods": lods
            }));
        }
    }
    blocked.sort_by(|a, b| {
        a["source_asset"]
            .as_str()
            .unwrap_or("")
            .cmp(b["source_asset"].as_str().unwrap_or(""))
    });
    plans.sort_by(|a, b| {
        a["source_asset"]
            .as_str()
            .unwrap_or("")
            .cmp(b["source_asset"].as_str().unwrap_or(""))
    });
    json!({
        "status": "prepared_requires_native_validation",
        "method": "asymmetric_front_only_partition",
        "scene_sha256": scene_sha256,
        "distance_tolerance_cm": PLANE_TOL,
        "modified_source_triangles": modified,
        "converted_area_cm2": converted,
        "blocked": blocked,
        "meshes": plans
    })
}

fn main() {
    let args: Vec<_> = std::env::args().collect();
    let folder = PathBuf::from(args.get(1).expect("surface folder"));
    let inventory = PathBuf::from(args.get(2).expect("inventory-baseline.json"));
    let output = PathBuf::from(args.get(3).expect("output plan json"));
    let plan = build_plan(&folder, &inventory);
    fs::write(&output, serde_json::to_vec(&plan).unwrap())
        .unwrap_or_else(|e| panic!("write {}: {e}", output.display()));
    eprintln!(
        "modified {} converted_cm2 {} blocked {}",
        plan["modified_source_triangles"],
        plan["converted_area_cm2"],
        plan["blocked"].as_array().map(|v| v.len()).unwrap_or(0)
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(p: [[f64; 3]; 3], slot: u32, id: i32) -> RawTri {
        RawTri { p, slot, id }
    }
    fn opaque_mixed() -> Vec<SlotFlag> {
        vec![
            SlotFlag {
                blend: 0,
                two_sided: true,
            },
            SlotFlag {
                blend: 0,
                two_sided: false,
            },
        ]
    }
    fn right(scale: f64, z: f64) -> [[f64; 3]; 3] {
        [[0.0, 0.0, z], [scale, 0.0, z], [0.0, scale, z]]
    }
    fn flip(p: [[f64; 3]; 3]) -> [[f64; 3]; 3] {
        [p[0], p[2], p[1]]
    }

    fn assert_bary_valid(positions: &[[f64; 3]; 3], piece: &Piece) {
        let origin = cross(
            sub(positions[1], positions[0]),
            sub(positions[2], positions[0]),
        );
        for b in &piece.bary {
            let s = b[0] + b[1] + b[2];
            assert!((s - 1.0).abs() < 1e-9, "barycentric sum {s:?} from {b:?}");
            for c in b {
                assert!(
                    (-1e-5..=1.0 + 1e-5).contains(c),
                    "barycentric component {c}"
                );
            }
            let pos = lift(positions, *b);
            assert!(
                dist_to_plane(origin, positions[0], pos) / dot(origin, origin).sqrt() < 1e-4,
                "piece left the source plane"
            );
        }
        let q = piece.bary.map(|w| lift(positions, w));
        let n = cross(sub(q[1], q[0]), sub(q[2], q[0]));
        assert!(dot(n, origin) > 0.0, "piece flipped the source winding");
        assert!(piece_area(positions, &piece.bary) > 0.0);
    }

    fn assert_patch(source: &RawTri, patch: &Patch, front_expected: f64) {
        assert_eq!(patch.triangle, source.id);
        assert_eq!(patch.material_slot, source.slot);
        assert_ne!(patch.triangle, 0, "native id must not be confused with a missing id");
        let mut front = 0.0;
        let mut back = 0.0;
        for piece in &patch.pieces {
            assert_bary_valid(&source.p, piece);
            let area = piece_area(&source.p, &piece.bary);
            if piece.front_only {
                front += area;
            } else {
                back += area;
            }
        }
        let total = front + back;
        assert!(
            (total - patch.area_before_cm2).abs() < 0.05,
            "pieces do not cover the source: {total} vs {}",
            patch.area_before_cm2
        );
        assert!((patch.area_after_cm2 - total).abs() < 1e-6);
        assert!((patch.front_only_area_cm2 - front).abs() < 1e-6);
        assert!((front - front_expected).abs() < 0.05, "front {front} expected {front_expected}");
        assert!((back - (patch.area_before_cm2 - front_expected)).abs() < 0.05);
        assert_shared_f32(&patch.pieces);
    }

    fn f32_bits(b: [f64; 3]) -> [u32; 3] {
        b.map(|v| (v as f32).to_bits())
    }

    fn assert_shared_f32(pieces: &[Piece]) {
        let mut verts = vec![];
        for (pi, piece) in pieces.iter().enumerate() {
            for b in piece.bary {
                verts.push((pi, piece.front_only, b));
            }
        }
        for (i, a) in verts.iter().enumerate() {
            for b in verts.iter().skip(i + 1) {
                if a.0 == b.0 {
                    continue;
                }
                let d = (0..3).map(|k| (a.2[k] - b.2[k]).abs()).fold(0.0, f64::max);
                if d < 1e-5 {
                    assert_eq!(
                        f32_bits(a.2),
                        f32_bits(b.2),
                        "shared boundary diverged in f32: {:?} vs {:?}",
                        a.2,
                        b.2
                    );
                }
            }
        }
    }

    #[test]
    fn opposite_mixed_full_coverage_becomes_front_only() {
        let target = raw(right(100.0, 0.0), 0, 100);
        let cover = raw(flip(right(100.0, 0.0)), 1, 200);
        let patches = partition_lod(&[target, cover], &opaque_mixed()).unwrap();
        assert_eq!(patches.len(), 1);
        assert!(patches[0].pieces.iter().all(|p| p.front_only));
        assert!(!patches[0].pieces.iter().any(|p| !p.front_only));
        assert_eq!(patches[0].cover_triangles, vec![200]);
        assert_patch(&raw(right(100.0, 0.0), 0, 100), &patches[0], 5000.0);
        let corners: HashSet<[i64; 3]> = patches[0]
            .pieces
            .iter()
            .flat_map(|p| p.bary)
            .map(bary_key)
            .collect();
        for corner in [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]] {
            assert!(corners.contains(&bary_key(corner)), "missing corner {corner:?}");
        }
    }

    #[test]
    fn partial_coverage_keeps_two_sided_outside() {
        let target_p = right(100.0, 0.0);
        let cover_p = flip([[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 40.0, 0.0]]);
        let target = raw(target_p, 0, 7);
        let patches = partition_lod(
            &[target, raw(cover_p, 1, 8)],
            &opaque_mixed(),
        )
        .unwrap();
        assert_eq!(patches.len(), 1);
        assert!(patches[0].pieces.iter().any(|p| p.front_only));
        assert!(patches[0].pieces.iter().any(|p| !p.front_only));
        assert_patch(&raw(target_p, 0, 7), &patches[0], 800.0);
        assert_eq!(patches[0].triangle, 7);
        assert_ne!(patches[0].cover_triangles, vec![0]);
    }

    #[test]
    fn same_facing_and_both_two_sided_are_excluded() {
        let target = raw(right(100.0, 0.0), 0, 1);
        let same = raw(right(100.0, 0.0), 1, 2);
        assert!(partition_lod(&[target, same], &opaque_mixed())
            .unwrap()
            .is_empty());
        let opposite = raw(flip(right(100.0, 0.0)), 1, 3);
        let both = vec![
            SlotFlag {
                blend: 0,
                two_sided: true,
            },
            SlotFlag {
                blend: 0,
                two_sided: true,
            },
        ];
        assert!(partition_lod(&[raw(right(100.0, 0.0), 0, 1), opposite], &both)
            .unwrap()
            .is_empty());
        let one_sided_only = vec![
            SlotFlag {
                blend: 0,
                two_sided: false,
            },
            SlotFlag {
                blend: 0,
                two_sided: false,
            },
        ];
        assert!(partition_lod(
            &[
                raw(right(100.0, 0.0), 0, 1),
                raw(flip(right(100.0, 0.0)), 1, 2)
            ],
            &one_sided_only
        )
        .unwrap()
        .is_empty());
    }

    #[test]
    fn masked_and_translucent_covers_are_excluded() {
        let target = raw(right(100.0, 0.0), 0, 5);
        let cover = raw(flip(right(100.0, 0.0)), 1, 6);
        for blend in [1, 2, 3] {
            let slots = vec![
                SlotFlag {
                    blend: 0,
                    two_sided: true,
                },
                SlotFlag {
                    blend,
                    two_sided: false,
                },
            ];
            assert!(
                partition_lod(&[target, cover], &slots).unwrap().is_empty(),
                "blend {blend} acted as opaque coverage"
            );
        }
        let masked_target = vec![
            SlotFlag {
                blend: 1,
                two_sided: true,
            },
            SlotFlag {
                blend: 0,
                two_sided: false,
            },
        ];
        assert!(partition_lod(
            &[raw(right(100.0, 0.0), 0, 5), raw(flip(right(100.0, 0.0)), 1, 6)],
            &masked_target
        )
        .unwrap()
        .is_empty());
    }

    #[test]
    fn coverage_area_thresholds() {
        let slots = opaque_mixed();
        let tiny = partition_lod(
            &[
                raw(right(1.0, 0.0), 0, 1),
                raw(flip(right(1.0, 0.0)), 1, 2),
            ],
            &slots,
        )
        .unwrap();
        assert!(tiny.is_empty(), "0.5cm² overlap must not convert");
        let enough = partition_lod(
            &[
                raw(right(2.0, 0.0), 0, 3),
                raw(flip(right(2.0, 0.0)), 1, 4),
            ],
            &slots,
        )
        .unwrap();
        assert_eq!(enough.len(), 1);
        assert!((enough[0].front_only_area_cm2 - 2.0).abs() < 0.05);

        let l = 10000.0;
        let target = [[0.0, 0.0, 0.0], [l, 0.0, 0.0], [0.0, l, 0.0]];
        let cover = flip([
            [l - 2.0, 0.0, 0.0],
            [l - 2.0 + l, 0.0, 0.0],
            [l - 2.0, l, 0.0],
        ]);
        let measured = overlap_area(&Tri::new(target).unwrap(), &Tri::new(cover).unwrap());
        let smaller = Tri::new(target).unwrap().area.min(Tri::new(cover).unwrap().area);
        assert!(
            measured > MIN_OVERLAP_CM2 && measured <= smaller * MIN_OVERLAP_FRACTION,
            "fixture overlap {measured} does not sit between the absolute and relative gates"
        );
        let rejected = partition_lod(&[raw(target, 0, 9), raw(cover, 1, 10)], &slots).unwrap();
        assert!(
            rejected.is_empty(),
            "overlap above 1cm² but below 1e-5 of the smaller triangle was converted"
        );
    }

    #[test]
    fn overlapping_coverers_convert_the_union_once() {
        let target_p = [[0.0, 0.0, 0.0], [200.0, 0.0, 0.0], [0.0, 200.0, 0.0]];
        let a = flip([[0.0, 0.0, 0.0], [100.0, 0.0, 0.0], [0.0, 100.0, 0.0]]);
        let b = flip([[50.0, 0.0, 0.0], [150.0, 0.0, 0.0], [50.0, 100.0, 0.0]]);
        let patches = partition_lod(
            &[
                raw(target_p, 0, 10),
                raw(a, 1, 11),
                raw(b, 1, 12),
            ],
            &opaque_mixed(),
        )
        .unwrap();
        assert_eq!(patches.len(), 1);
        assert_eq!(patches[0].cover_triangles, vec![11, 12]);
        // |A∪B| = 5000+5000-1250. Twice that would be a double conversion.
        assert_patch(&raw(target_p, 0, 10), &patches[0], 8750.0);
        assert!(patches[0].front_only_area_cm2 < 9000.0);
    }

    #[test]
    fn far_origin_tilt_is_not_lost_to_a_global_plane_bucket() {
        let x = 1_000_000.0;
        let y = 1_000_000.0;
        let target_p = [
            [x, y, 1000.0],
            [x + 100.0, y, 1000.0],
            [x, y + 100.0, 1000.0],
        ];
        let cover_p = flip([
            [x, y, 1000.001],
            [x + 100.0, y, 1000.0],
            [x, y + 100.0, 1000.001],
        ]);
        let target = Tri::new(target_p).unwrap();
        let cover = Tri::new(cover_p).unwrap();
        let naive = |t: &Tri| (dot(t.n_bin, t.origin) / INTERCEPT_BIN).round() as i64;
        assert!(
            (naive(&target) - naive(&cover)).abs() > INTERCEPT_NEIGHBOR,
            "fixture no longer separates a single origin plane bucket"
        );
        assert!(
            bins_overlap(&target, &cover),
            "cell-relative bins missed a far tilted pair"
        );
        let decoy = raw(
            [[0.0, 0.0, 0.0], [10.0, 0.0, 0.0], [0.0, 10.0, 0.0]],
            1,
            1,
        );
        let patches = partition_lod(
            &[decoy, raw(target_p, 0, 50), raw(cover_p, 1, 60)],
            &opaque_mixed(),
        )
        .unwrap();
        assert_eq!(patches.len(), 1);
        assert_eq!(patches[0].triangle, 50);
        assert_eq!(patches[0].cover_triangles, vec![60]);
        assert_patch(&raw(target_p, 0, 50), &patches[0], 5000.0);
    }

    #[test]
    fn cell_boundary_pair_is_partitioned() {
        let z0 = 500.0 - 0.0005;
        let z1 = 500.0 + 0.0005;
        assert_ne!((z0 / CELL).floor() as i64, (z1 / CELL).floor() as i64);
        let target_p = right(100.0, z0);
        let cover_p = flip(right(100.0, z1));
        let target = Tri::new(target_p).unwrap();
        let cover = Tri::new(cover_p).unwrap();
        let mut bare = HashSet::new();
        let lo = (z0 / CELL).floor() as i64;
        let hi = (z1 / CELL).floor() as i64;
        bare.insert(lo);
        assert!(!bare.contains(&hi), "unpadded cells already overlap");
        assert!(bins_overlap(&target, &cover));
        let patches = partition_lod(
            &[raw(target_p, 0, 15), raw(cover_p, 1, 16)],
            &opaque_mixed(),
        )
        .unwrap();
        assert_eq!(patches.len(), 1);
        assert_patch(&raw(target_p, 0, 15), &patches[0], 5000.0);
    }

    #[test]
    fn pieces_preserve_area_and_barycentric() {
        let target_p = right(80.0, 0.0);
        let cover_p = flip([[10.0, 5.0, 0.0], [50.0, 5.0, 0.0], [10.0, 45.0, 0.0]]);
        let patches = partition_lod(
            &[raw(target_p, 0, 21), raw(cover_p, 1, 22)],
            &opaque_mixed(),
        )
        .unwrap();
        assert_eq!(patches.len(), 1);
        let cover_area = Tri::new(cover_p).unwrap().area;
        assert_patch(&raw(target_p, 0, 21), &patches[0], cover_area);
        for piece in &patches[0].pieces {
            for b in piece.bary {
                let p = lift(&target_p, b);
                let denom = side(
                    [target_p[0][0], target_p[0][1]],
                    [target_p[1][0], target_p[1][1]],
                    [target_p[2][0], target_p[2][1]],
                );
                let a = side(
                    [target_p[1][0], target_p[1][1]],
                    [target_p[2][0], target_p[2][1]],
                    [p[0], p[1]],
                ) / denom;
                let b0 = side(
                    [target_p[2][0], target_p[2][1]],
                    [target_p[0][0], target_p[0][1]],
                    [p[0], p[1]],
                ) / denom;
                assert!((a - b[0]).abs() < 1e-5);
                assert!((b0 - b[1]).abs() < 1e-5);
                assert!(a >= -1e-4 && b0 >= -1e-4 && 1.0 - a - b0 >= -1e-4);
            }
        }
    }

    fn write_cdy2(tris: &[([ [f32; 3]; 3], u32, u32)]) -> Vec<u8> {
        let nv = tris.len() * 3;
        let nt = tris.len();
        let mut b = Vec::new();
        for n in [0x43445932u32, nv as u32, nt as u32] {
            b.extend(n.to_le_bytes());
        }
        for (p, _, _) in tris {
            for v in p {
                for c in v {
                    b.extend(c.to_le_bytes());
                }
            }
        }
        for i in 0..nt {
            for k in 0..3u32 {
                b.extend(((i as u32) * 3 + k).to_le_bytes());
            }
        }
        for (_, _, id) in tris {
            b.extend(id.to_le_bytes());
        }
        for (_, slot, _) in tris {
            b.extend(slot.to_le_bytes());
        }
        b
    }

    #[test]
    fn synthetic_scene_plan_uses_native_triangle_ids() {
        let dir = std::env::temp_dir().join(format!(
            "ok-asymmetric-sheets-{}-{}",
            std::process::id(),
            17
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let lod0 = write_cdy2(&[
            (
                [
                    [0.0, 0.0, 0.0],
                    [100.0, 0.0, 0.0],
                    [0.0, 100.0, 0.0],
                ],
                0,
                100,
            ),
            (
                [
                    [0.0, 0.0, 0.0],
                    [0.0, 100.0, 0.0],
                    [100.0, 0.0, 0.0],
                ],
                1,
                200,
            ),
        ]);
        let lod1 = write_cdy2(&[
            ([[0.0, 0.0, 0.0], [10.0, 0.0, 0.0], [0.0, 10.0, 0.0]], 0, 300),
            (
                [[1000.0, 0.0, 0.0], [1000.0, 10.0, 0.0], [1010.0, 0.0, 0.0]],
                1,
                400,
            ),
        ]);
        fs::write(dir.join("floor-lod0.cdy2"), &lod0).unwrap();
        fs::write(dir.join("floor-lod1.cdy2"), &lod1).unwrap();
        let scene = json!({
            "format": "CDY2",
            "instances": [
                {"mesh": 0, "actor": "FloorA", "key": "FloorA::StaticMesh", "blend_modes": [0, 0], "two_sided_by_slot": [true, false]},
                {"mesh": 0, "actor": "FloorB", "key": "FloorB::StaticMesh", "blend_modes": [0, 0], "two_sided_by_slot": [true, false]},
                {"mesh": 1, "actor": "BlockA", "key": "BlockA::StaticMesh", "blend_modes": [0], "two_sided_by_slot": [true]},
                {"mesh": 1, "actor": "BlockB", "key": "BlockB::StaticMesh", "blend_modes": [0], "two_sided_by_slot": [false]},
                {"mesh": 2, "actor": "NotFloor", "key": "NotFloor::StaticMesh", "blend_modes": [0, 0], "two_sided_by_slot": [true, false]}
            ],
            "meshes": [
                {"asset": "/Game/FloorAgreed", "lods": [
                    {"lod": 0, "file": "floor-lod0.cdy2"},
                    {"lod": 1, "file": "floor-lod1.cdy2"}
                ]},
                {"asset": "/Game/FloorBlocked", "lods": [{"lod": 0, "file": "missing-blocked.cdy2"}]},
                {"asset": "/Game/NotFloor", "lods": [{"lod": 0, "file": "missing-not-floor.cdy2"}]}
            ]
        });
        let scene_bytes = serde_json::to_vec(&scene).unwrap();
        fs::write(dir.join("scene.json"), &scene_bytes).unwrap();
        let inventory = json!({"actors": [
            {"label": "FloorA", "building_floor": true},
            {"label": "FloorB", "building_floor": true},
            {"label": "BlockA", "building_floor": true},
            {"label": "NotFloor", "building_floor": false}
        ]});
        let inventory_path = dir.join("inventory-baseline.json");
        fs::write(&inventory_path, serde_json::to_vec(&inventory).unwrap()).unwrap();
        let plan = build_plan(&dir, &inventory_path);
        assert_eq!(plan["status"], "prepared_requires_native_validation");
        assert_eq!(plan["method"], "asymmetric_front_only_partition");
        assert_eq!(plan["distance_tolerance_cm"], 0.002);
        assert_eq!(plan["scene_sha256"], hex_sha256(&scene_bytes));
        assert_eq!(plan["modified_source_triangles"], 1);
        assert!((plan["converted_area_cm2"].as_f64().unwrap() - 5000.0).abs() < 0.05);
        assert_eq!(plan["meshes"].as_array().unwrap().len(), 1);
        let mesh = &plan["meshes"][0];
        assert_eq!(mesh["source_asset"], "/Game/FloorAgreed");
        assert_eq!(
            mesh["component_keys"],
            json!(["FloorA::StaticMesh", "FloorB::StaticMesh"])
        );
        assert_eq!(mesh["blend_modes"], json!([0, 0]));
        assert_eq!(mesh["two_sided_by_slot"], json!([true, false]));
        let lods = mesh["lods"].as_array().unwrap();
        assert_eq!(lods.len(), 1, "LOD1 has no overlap and must not copy LOD0");
        assert_eq!(lods[0]["lod"], 0);
        assert_eq!(lods[0]["source_sha256"], hex_sha256(&lod0));
        let patch = &lods[0]["patches"][0];
        assert_eq!(patch["triangle"], 100);
        assert_eq!(patch["material_slot"], 0);
        assert_eq!(patch["cover_triangles"], json!([200]));
        assert_ne!(patch["triangle"], 0);
        let pieces = patch["pieces"].as_array().unwrap();
        assert!(pieces.iter().all(|p| p["front_only"] == true));
        assert!((patch["area_before_cm2"].as_f64().unwrap() - 5000.0).abs() < 1e-6);
        assert!(
            (patch["area_after_cm2"].as_f64().unwrap() - patch["area_before_cm2"].as_f64().unwrap())
                .abs()
                < 0.05
        );
        let blocked = plan["blocked"].as_array().unwrap();
        assert_eq!(blocked.len(), 1);
        assert_eq!(blocked[0]["source_asset"], "/Game/FloorBlocked");
        assert!(blocked[0]["reason"]
            .as_str()
            .unwrap()
            .contains("disagree"));
        let text = serde_json::to_string(&plan).unwrap();
        assert!(!text.contains("missing-blocked"));
        assert!(!text.contains("NotFloor"));
        assert!(!text.contains("\"triangle\":300"));
        assert!(!text.contains("\"triangle\":400"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn tiny_cover_on_large_target_stays_within_native_cover_tolerance() {
        let source = raw(right(10000.0, 0.0), 0, 11);
        let mut cp = flip(right(2.5, 0.0));
        for p in &mut cp { p[0] += 1000.17; p[1] += 2000.37; }
        let cover = raw(cp, 1, 39);
        let patches = partition_lod(&[source.clone(), cover.clone()], &opaque_mixed()).unwrap();
        assert_eq!(patches.len(), 1);
        let cover_geom = Tri::new(cp).unwrap();
        for p in patches[0].pieces.iter().filter(|p| p.front_only) {
            for b in p.bary {
                let point = lift(&source.p, b);
                let w = cover_geom.bary(cover_geom.project(point));
                assert!(w.iter().all(|v| *v >= -0.000002), "native containment failed: {w:?}");
            }
        }
    }

    #[test]
    fn complementary_split_does_not_duplicate_area() {
        let poly = [[0.0, 0.0], [100.0, 0.0], [0.0, 100.0]];
        let cover = [[25.0, 25.0], [125.0, 25.0], [25.0, 125.0]];
        let (inside, outside) = clip_cover(&poly, &cover);
        let kept = area2(&inside).abs()
            + outside.iter().map(|p| area2(p).abs()).sum::<f64>();
        assert!((kept - area2(&poly).abs()).abs() < 1e-6);
        assert!(area2(&inside).abs() > 1.0);
        let thin = [
            [49.99999237060547, 520.0],
            [-90.0, 380.0],
            [49.99995422363281, 380.0],
        ];
        let thin_cover = [
            [49.999954223641126, 380.0000305175781],
            [-89.99996948242355, 380.0000305175781],
            [-90.0, 380.0],
        ];
        let (inn, out) = clip_cover(&thin, &thin_cover);
        let sum = area2(&inn).abs() + out.iter().map(|p| area2(p).abs()).sum::<f64>();
        assert!(sum <= area2(&thin).abs() + 1e-6);
    }
}

// Cross-instance sheets. World centimetres decide coplanarity and overlap.
// Emitted areas are the unscaled source triangle: barycentrics are affine, so
// they are solved on the transformed target and measured on its local corners.
const SAME_DOT: f64 = 0.999999;
const SINGULAR_DET: f64 = 1e-12;
const AREA_QUANTUM: f64 = 1_000_000.0;

fn transform_point(p: V, m: &[f64; 16]) -> V {
    std::array::from_fn(|j| p[0] * m[j] + p[1] * m[4 + j] + p[2] * m[8 + j] + m[12 + j])
}

fn mat_det(m: &[f64; 16]) -> f64 {
    let r0 = [m[0], m[1], m[2]];
    let r1 = [m[4], m[5], m[6]];
    let r2 = [m[8], m[9], m[10]];
    dot(r0, cross(r1, r2))
}

fn quantize_area(area: f64) -> Result<i64, String> {
    let q = (area * AREA_QUANTUM).round();
    if !q.is_finite() || q < 0.0 || q > i64::MAX as f64 {
        return Err(format!("non-finite world area {area}"));
    }
    Ok(q as i64)
}

fn companion_json_path(conflicts: &Path) -> Result<PathBuf, String> {
    let name = conflicts
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| format!("conflicts path {} has no file name", conflicts.display()))?;
    let stem = name.strip_suffix(".conflicts.jsonl").ok_or_else(|| {
        format!("conflicts path must end in .conflicts.jsonl, got {name}")
    })?;
    Ok(conflicts.with_file_name(format!("{stem}.json")))
}

fn json_str<'a>(v: &'a Value, field: &str) -> Result<&'a str, String> {
    v.get(field)
        .and_then(|x| x.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("missing {field}"))
}

fn json_i64(v: &Value, field: &str) -> Result<i64, String> {
    v.get(field)
        .and_then(|x| x.as_i64())
        .ok_or_else(|| format!("missing {field}"))
}

fn json_usize(v: &Value, field: &str) -> Result<usize, String> {
    let n = json_i64(v, field)?;
    usize::try_from(n).map_err(|_| format!("negative {field}"))
}

fn json_bool(v: &Value, field: &str) -> Result<bool, String> {
    v.get(field)
        .and_then(|x| x.as_bool())
        .ok_or_else(|| format!("missing {field}"))
}

fn parse_matrix(value: &Value, ctx: &str) -> Result<[f64; 16], String> {
    let arr = value
        .as_array()
        .ok_or_else(|| format!("{ctx} matrix is not an array"))?;
    if arr.len() != 16 {
        return Err(format!("{ctx} matrix does not have 16 numbers"));
    }
    let mut m = [0.0; 16];
    for (i, v) in arr.iter().enumerate() {
        let n = v
            .as_f64()
            .ok_or_else(|| format!("{ctx} matrix[{i}] is not a number"))?;
        if !n.is_finite() {
            return Err(format!("{ctx} matrix[{i}] is not finite"));
        }
        m[i] = n;
    }
    Ok(m)
}

fn multi_transform(inst: &Value) -> bool {
    if inst
        .get("instance_count")
        .and_then(|v| v.as_u64())
        .unwrap_or(1)
        > 1
    {
        return true;
    }
    for name in [
        "per_instance_transforms",
        "instance_transforms",
        "hism_instances",
        "his_instances",
    ] {
        if inst
            .get(name)
            .and_then(|v| v.as_array())
            .is_some_and(|a| a.len() > 1)
        {
            return true;
        }
    }
    false
}

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd, Hash)]
struct Endpoint {
    instance: usize,
    key: String,
    lod: i64,
    triangle: i32,
}

struct SceneMesh {
    asset: String,
    lods: Vec<(i64, String)>,
}

struct SceneInst {
    actor: String,
    key: String,
    mesh: usize,
    asset: String,
    matrix: [f64; 16],
    blend: Vec<i64>,
    two_sided: Vec<bool>,
    materials: Vec<String>,
    floor: bool,
    unusable: Option<String>,
    shared_mesh: bool,
    front_tolerance_cm: f64,
    ground_top_replace: bool,
    actual_building_floor: bool,
    cover_only: bool,
}

struct Geom {
    world: Tri,
    local: Tri,
    area_q: i64,
    slot: u32,
    asset: String,
    matrix: [f64; 16],
    material: String,
    sha: String,
    two_sided: bool,
}

struct SheetPatch {
    operation: &'static str,
    plane_tolerance_cm: f64,
    triangle: i32,
    material_slot: u32,
    area_before_cm2: f64,
    area_after_cm2: f64,
    front_only_area_cm2: f64,
    removed_area_cm2: f64,
    covers: Vec<Endpoint>,
    pieces: Vec<Piece>,
    removed_pieces: Vec<Piece>,
}

fn world_cover_polygon(target:&Tri,cover:&Tri)->[P;3]{
    let denominator=dot(target.n,cover.n);
    cover.p.map(|p|{let distance=dot(target.n,sub(p,target.origin))/denominator;target.project(std::array::from_fn(|k|p[k]-cover.n[k]*distance))})
}
fn world_overlap_at_tol(target: &Tri, cover: &Tri, opposite: bool, tolerance: f64, either: bool) -> Option<f64> {
    let n=dot(target.n,cover.n);
    // Ground two-sided covers may match or oppose. Every other caller passes
    // either=false and keeps the single-direction dot test.
    let aligned=if either{n<=NORMAL_DOT_MAX||n>=SAME_DOT}else if opposite{n<=NORMAL_DOT_MAX}else{n>=SAME_DOT};
    if !aligned{return None;}
    if (0..3).any(|k|target.p.iter().map(|p|p[k]).fold(f64::INFINITY,f64::min)>cover.p.iter().map(|p|p[k]).fold(f64::NEG_INFINITY,f64::max)+tolerance||cover.p.iter().map(|p|p[k]).fold(f64::INFINITY,f64::min)>target.p.iter().map(|p|p[k]).fold(f64::NEG_INFINITY,f64::max)+tolerance){return None;}
    let projected=world_cover_polygon(target,cover);let (intersection,_)=clip_cover(&target.local,&projected);
    if intersection.len()<3||intersection.iter().any(|p|dist_to_plane(cover.n,cover.origin,lift(&target.p,target.bary(*p)))>tolerance+1.0e-10){return None;}
    let area=target.area_of(&intersection);let smaller=target.area.min(cover.area);
    if area>MIN_OVERLAP_CM2&&area>smaller*MIN_OVERLAP_FRACTION{Some(area)}else{None}
}

fn fan_area(param: &Tri, positions: &[V; 3], poly: &[P]) -> f64 {
    if poly.len() < 3 {
        return 0.0;
    }
    let origin = cross(
        sub(positions[1], positions[0]),
        sub(positions[2], positions[0]),
    );
    let mut area = 0.0;
    let b0 = param.bary(poly[0]);
    for i in 1..poly.len() - 1 {
        let bary = [b0, param.bary(poly[i]), param.bary(poly[i + 1])];
        let q = bary.map(|w| lift(positions, w));
        let n = cross(sub(q[1], q[0]), sub(q[2], q[0]));
        if dot(n, origin) > 1e-8 {
            area += 0.5 * dot(n, n).sqrt();
        }
    }
    area
}

fn priority_tuple<'a>(g: &'a Geom, e: &'a Endpoint) -> (i64, &'a str, i64, i32, usize) {
    (g.area_q, e.key.as_str(), e.lod, e.triangle, e.instance)
}

fn partition_sheet(
    world: &Tri,
    local: &Tri,
    covers: &[(&Tri, f64)],
    front_only: bool,
    triangle: i32,
) -> Result<(f64, f64, f64, f64, Vec<Piece>, Vec<Piece>), String> {
    let overlap_sum: f64 = covers.iter().map(|c| c.1).sum();
    let max_overlap = covers.iter().map(|c| c.1).fold(0.0, f64::max);
    let mut pending = vec![world.local.to_vec()];
    let mut inside_polys: Vec<Vec<P>> = vec![];
    for (cover, _) in covers {
        let local_cover = world_cover_polygon(world,cover);
        let mut next = vec![];
        for poly in &pending {
            let (inside, outside) = clip_cover(poly, &local_cover);
            if inside.len() >= 3 && world.area_of(&inside) > 1e-8 {
                inside_polys.push(inside);
            }
            next.extend(outside);
        }
        pending = next;
        if pending.len() + inside_polys.len() > MAX_POLYGONS {
            return Err(format!(
                "fragmentation explosion on triangle {triangle}: {} polygons",
                pending.len() + inside_polys.len()
            ));
        }
    }
    let covered_raw: f64 = inside_polys.iter().map(|p| world.area_of(p)).sum();
    let kept_raw: f64 = pending.iter().map(|p| world.area_of(p)).sum();
    let raw_tol = 1e-3 + world.area * 1e-9;
    if (covered_raw + kept_raw - world.area).abs() > raw_tol
        || covered_raw > overlap_sum + raw_tol
        || covered_raw + raw_tol < max_overlap
    {
        return Err(format!(
            "area loss or duplication on triangle {triangle}: world before={} covered={} kept={} overlap_sum={} max_overlap={}",
            world.area, covered_raw, kept_raw, overlap_sum, max_overlap
        ));
    }
    if covered_raw <= MIN_OVERLAP_CM2 * 0.5 {
        return Err(format!(
            "accepted cover produced no covered area on triangle {triangle}"
        ));
    }
    let local_covered: f64 = inside_polys.iter().map(|p| fan_area(world, &local.p, p)).sum();
    let local_kept: f64 = pending.iter().map(|p| fan_area(world, &local.p, p)).sum();
    let local_tol = 1e-3 + local.area * 1e-9;
    if (local_covered + local_kept - local.area).abs() > local_tol {
        return Err(format!(
            "local area loss on triangle {triangle}: before={} covered={} kept={}",
            local.area, local_covered, local_kept
        ));
    }

    let mut verts = vec![];
    let mut inside_b = polygons_from(&inside_polys, world, &mut verts);
    let mut outside_b = polygons_from(&pending, world, &mut verts);
    let n_in = inside_b.len();
    let mut all = inside_b;
    all.append(&mut outside_b);
    split_t_junctions(&mut all);
    inside_b = all[..n_in].to_vec();
    outside_b = all[n_in..].to_vec();

    let mut kept = vec![];
    let mut removed = vec![];
    if front_only {
        for poly in &inside_b {
            kept.extend(triangulate(poly, &local.p, true));
        }
        for poly in &outside_b {
            kept.extend(triangulate(poly, &local.p, false));
        }
    } else {
        for poly in &outside_b {
            kept.extend(triangulate(poly, &local.p, false));
        }
        for poly in &inside_b {
            removed.extend(triangulate(poly, &local.p, false));
        }
    }
    if kept.len() + removed.len() > MAX_PIECES {
        return Err(format!(
            "fragmentation explosion on triangle {triangle}: {} pieces",
            kept.len() + removed.len()
        ));
    }
    let mut front_area = 0.0;
    let mut kept_area = 0.0;
    let mut removed_area = 0.0;
    let mut world_pieces = 0.0;
    for piece in kept.iter().chain(&removed) {
        world_pieces += piece_area(&world.p, &piece.bary);
    }
    for piece in &kept {
        let area = piece_area(&local.p, &piece.bary);
        if piece.front_only {
            front_area += area;
        } else {
            kept_area += area;
        }
    }
    for piece in &removed {
        removed_area += piece_area(&local.p, &piece.bary);
    }
    let qtol = area_quantum_tol(local);
    let wtol = area_quantum_tol(world);
    if (world_pieces - (covered_raw + kept_raw)).abs() > wtol {
        return Err(format!(
            "quantized pieces changed world area on triangle {triangle}: raw {} emitted {world_pieces}",
            covered_raw + kept_raw
        ));
    }
    let (expect_front, expect_kept, expect_removed) = if front_only {
        (local_covered, local_kept, 0.0)
    } else {
        (0.0, local_kept, local_covered)
    };
    if (front_area - expect_front).abs() > qtol
        || (kept_area - expect_kept).abs() > qtol
        || (removed_area - expect_removed).abs() > qtol
        || (front_area + kept_area + removed_area - local.area).abs() > qtol
    {
        return Err(format!(
            "quantized pieces changed local area on triangle {triangle}: front {front_area} kept {kept_area} removed {removed_area} before {}",
            local.area
        ));
    }
    let area_after = if front_only {
        front_area + kept_area
    } else {
        kept_area
    };
    Ok((
        local.area,
        area_after,
        if front_only { front_area } else { 0.0 },
        if front_only { 0.0 } else { removed_area },
        kept,
        removed,
    ))
}

fn piece_json(pieces: &[Piece]) -> Vec<Value> {
    pieces
        .iter()
        .map(|p| {
            json!({
                "barycentric": p.bary,
                "front_only": p.front_only
            })
        })
        .collect()
}

fn select_lod<'a>(
    lods: &'a [(i64, String)],
    pass: i64,
    claimed: i64,
    ctx: &str,
) -> Result<&'a (i64, String), String> {
    if lods.is_empty() {
        return Err(format!("stale scan row: {ctx} mesh has no lods"));
    }
    let selected = lods
        .iter()
        .rev()
        .find(|l| l.0 <= pass)
        .unwrap_or(&lods[0]);
    if selected.0 != claimed {
        return Err(format!(
            "stale scan row: {ctx} lod {claimed} does not match pass {pass} source lod {}",
            selected.0
        ));
    }
    Ok(selected)
}

struct LoadedFile {
    sha: String,
    tris: HashMap<i32, RawTri>,
}

fn read_cdy2_needed(path: &Path, needed: &HashSet<i32>) -> Result<LoadedFile, String> {
    let bytes = fs::read(path).map_err(|e| format!("read {}: {e}", path.display()))?;
    let sha = hex_sha256(&bytes);
    if bytes.len() < 12 {
        return Err(format!("truncated CDY2 {}", path.display()));
    }
    let magic = u32at(&bytes, 0);
    if magic != 0x43445932 {
        return Err(format!(
            "CDY2 per-triangle slots required {}",
            path.display()
        ));
    }
    let nv = u32at(&bytes, 4) as usize;
    let nt = u32at(&bytes, 8) as usize;
    let expect = 12 + nv * 12 + nt * 20;
    if bytes.len() != expect {
        return Err(format!("truncated CDY2 {}", path.display()));
    }
    let start = 12 + nv * 12;
    let mut found: HashMap<i32, (usize, u32)> = HashMap::new();
    for i in 0..nt {
        let id = u32at(&bytes, start + nt * 12 + i * 4) as i32;
        if !needed.contains(&id) {
            continue;
        }
        if found.contains_key(&id) {
            return Err(format!(
                "duplicate native triangle id {id} in {}",
                path.display()
            ));
        }
        let slot = u32at(&bytes, start + nt * 16 + i * 4);
        found.insert(id, (i, slot));
    }
    for id in needed {
        if !found.contains_key(id) {
            return Err(format!(
                "stale scan row: triangle {id} missing from {}",
                path.display()
            ));
        }
    }
    let mut tris = HashMap::new();
    for (id, (i, slot)) in found {
        let idx = std::array::from_fn(|k| u32at(&bytes, start + i * 12 + k * 4) as usize);
        if idx.iter().any(|v| *v >= nv) {
            return Err(format!(
                "triangle {id} index out of range in {}",
                path.display()
            ));
        }
        let p = idx.map(|v| {
            std::array::from_fn(|k| f32::from_bits(u32at(&bytes, 12 + v * 12 + k * 4)) as f64)
        });
        tris.insert(id, RawTri { p, slot, id });
    }
    Ok(LoadedFile { sha, tris })
}

struct Cand {
    a: Endpoint,
    b: Endpoint,
    a_slot: usize,
    b_slot: usize,
    a_file: String,
    b_file: String,
}

fn side_endpoint(
    row: &Value,
    side: &str,
    pass: i64,
    instances: &[SceneInst],
    meshes: &[SceneMesh],
) -> Result<(Endpoint, usize, String), String> {
    let index = json_usize(row, &format!("{side}_instance"))
        .map_err(|e| format!("stale scan row: {e}"))?;
    let inst = instances.get(index).ok_or_else(|| {
        format!("stale scan row: {side}_instance {index} is outside the scene")
    })?;
    let actor = json_str(row, &format!("{side}_actor")).map_err(|e| format!("stale scan row: {e}"))?;
    if actor != inst.actor {
        return Err(format!(
            "stale scan row: {side}_actor {actor} != scene instance {index} {}",
            inst.actor
        ));
    }
    let key = json_str(row, &format!("{side}_key")).map_err(|e| format!("stale scan row: {e}"))?;
    if key != inst.key {
        return Err(format!(
            "stale scan row: {side}_key {key} != scene instance {index} {}",
            inst.key
        ));
    }
    let claimed = json_i64(row, &format!("{side}_lod")).map_err(|e| format!("stale scan row: {e}"))?;
    let mesh = meshes.get(inst.mesh).ok_or_else(|| {
        format!("stale scan row: instance {index} mesh {} is outside the scene", inst.mesh)
    })?;
    let lod = select_lod(&mesh.lods, pass, claimed, &format!("{side} instance {index}"))?;
    let tri = json_i64(row, &format!("{side}_triangle"))
        .map_err(|e| format!("stale scan row: {e}"))?;
    let tri = i32::try_from(tri).map_err(|_| {
        format!("stale scan row: {side}_triangle {tri} is outside i32")
    })?;
    let slot = json_usize(row, &format!("{side}_material_slot"))
        .map_err(|e| format!("stale scan row: {e}"))?;
    if slot >= inst.two_sided.len() || slot >= inst.blend.len() || slot >= inst.materials.len() {
        return Err(format!(
            "stale scan row: {side}_material_slot {slot} is outside instance {index}"
        ));
    }
    let two = json_bool(row, &format!("{side}_two_sided"))
        .map_err(|e| format!("stale scan row: {e}"))?;
    if two != inst.two_sided[slot] {
        return Err(format!(
            "stale scan row: {side}_two_sided does not match scene slot {slot} on {}",
            inst.key
        ));
    }
    Ok((
        Endpoint {
            instance: index,
            key: key.to_string(),
            lod: lod.0,
            triangle: tri,
        },
        slot,
        lod.1.clone(),
    ))
}

fn exclusion_name(reason: &str) -> &'static str {
    if reason.contains("component key") {
        "ambiguous_component_key"
    } else {
        "rejected_transform"
    }
}

fn bump(map: &mut BTreeMap<String, u64>, key: &str) {
    *map.entry(key.to_string()).or_insert(0) += 1;
}

fn note_blocked(
    blocked: &mut BTreeMap<(String, String), BTreeSet<String>>,
    inst: &SceneInst,
    reason: &str,
) {
    blocked
        .entry((inst.asset.clone(), reason.to_string()))
        .or_default()
        .insert(inst.key.clone());
}

struct Emitted {
    asset: String,
    key: String,
    matrix: [f64; 16],
    materials: Vec<String>,
    two_sided: Vec<bool>,
    blend: Vec<i64>,
    lod: i64,
    sha: String,
    front_existing: Option<(u32, usize)>,
    patch: SheetPatch,
}

#[derive(Clone, Copy)]
enum SheetKind {
    FrontOnly,
    Remove,
    GroundTopReplace,
    RemoveDuplicateTwoSided,
    RemoveOneSidedDuplicate,
    PairedFrontOnly,
}

fn drop_sheet_endpoints(
    groups: &mut BTreeMap<Endpoint, BTreeSet<Endpoint>>,
    gone: &BTreeSet<Endpoint>,
) {
    groups.retain(|ep, _| !gone.contains(ep));
    for covers in groups.values_mut() {
        covers.retain(|ep| !gone.contains(ep));
    }
    groups.retain(|_, covers| !covers.is_empty());
}

fn selector_flag(doc: &Value, name: &str) -> Result<bool, String> {
    match doc.get(name) {
        None => Ok(false),
        Some(Value::Bool(value)) => Ok(*value),
        Some(_) => Err(format!("{name} must be a bool")),
    }
}

/// GNN, Outdoor_annex_ground, and World_PK_* only. Native rejects any other
/// label before rebind, including a 0.2 cm gap on an ordinary floor.
fn ground_scope_label(label: &str) -> bool {
    let bytes = label.as_bytes();
    (bytes.len() == 3 && bytes[0] == b'G' && bytes[1].is_ascii_digit() && bytes[2].is_ascii_digit())
        || label == "Outdoor_annex_ground"
        || label.starts_with("World_PK_")
}

fn upward_terrain(inst: &SceneInst, geom: &Geom) -> bool {
    inst.ground_top_replace && !inst.cover_only && ground_scope_label(&inst.actor) && geom.world.n[2] < -0.8
}

/// One-sided covers stay same-facing and may be another material on the target.
/// Two-sided covers are explicit: the cover actor must be an actual building
/// floor or cover_only, and either winding is accepted by the caller.
fn ground_cover_choice(target: &Geom, cover: &Geom, cover_inst: &SceneInst, opposite: bool) -> bool {
    if cover.two_sided {
        return cover_inst.actual_building_floor || cover_inst.cover_only;
    }
    !opposite && (target.two_sided || cover_inst.actual_building_floor || cover_inst.cover_only)
}

fn prune_paired_fixed_point(
    paired: &mut BTreeMap<Endpoint, BTreeSet<Endpoint>>,
    exclusions: &mut BTreeMap<String, u64>,
) {
    loop {
        let mut broken = BTreeSet::new();
        for (target, covers) in paired.iter() {
            for cover in covers {
                if !paired.get(cover).is_some_and(|set| set.contains(target)) {
                    broken.insert(target.clone());
                    broken.insert(cover.clone());
                }
            }
        }
        if broken.is_empty() {
            break;
        }
        for _ in &broken {
            bump(exclusions, "deferred_unpaired_two_sided");
        }
        drop_sheet_endpoints(paired, &broken);
    }
}

fn emit_group(
    groups: &BTreeMap<Endpoint, BTreeSet<Endpoint>>,
    geoms: &HashMap<Endpoint, Geom>,
    instances: &[SceneInst],
    front_slots: &HashMap<String, BTreeMap<usize, usize>>,
    kind: SheetKind,
    _exclusions: &mut BTreeMap<String, u64>,
    _blocked: &mut BTreeMap<(String, String), BTreeSet<String>>,
    out: &mut Vec<Emitted>,
) -> Result<(), String> {
    let front_like = matches!(kind, SheetKind::FrontOnly | SheetKind::PairedFrontOnly);
    let operation = match kind {
        SheetKind::FrontOnly => "front_only",
        SheetKind::Remove => "remove",
        SheetKind::GroundTopReplace => "ground_top_replace",
        SheetKind::RemoveDuplicateTwoSided => "remove_duplicate_two_sided",
        SheetKind::RemoveOneSidedDuplicate => "remove_one_sided_duplicate",
        SheetKind::PairedFrontOnly => "paired_front_only",
    };
    for (target_ep, cover_eps) in groups {
        let target = geoms.get(target_ep).ok_or_else(|| {
            format!("missing geometry for triangle {}", target_ep.triangle)
        })?;
        let inst = &instances[target_ep.instance];
        let mut front_existing = None;
        if front_like {
            let slot = target.slot as usize;
            match front_slots.get(&inst.key).and_then(|m| m.get(&slot)).copied() {
                Some(existing) => front_existing = Some((target.slot, existing)),
                // Native creates a checked one-sided child and slot when this
                // component has no earlier front-only partition. Existing slots
                // are still reused and their bindings are validated above.
                None => {}
            }
        }
        // Ground and ordinary front-only keep their opt-in gap. Duplicate,
        // mixed one-sided removal and both-two-sided operations stay on the
        // strict 0.002 cm plane.
        let tolerance = if matches!(kind, SheetKind::FrontOnly | SheetKind::GroundTopReplace) {
            inst.front_tolerance_cm
        } else {
            PLANE_TOL
        };
        if matches!(kind, SheetKind::RemoveOneSidedDuplicate) && target.two_sided {
            return Err(format!(
                "remove_one_sided_duplicate target {} is not one-sided",
                target_ep.triangle
            ));
        }
        if matches!(kind, SheetKind::RemoveOneSidedDuplicate)
            && !cover_eps.iter().any(|ep| geoms.get(ep).is_some_and(|g| g.two_sided))
        {
            return Err(format!(
                "remove_one_sided_duplicate on {} lacks a two-sided cover",
                target_ep.triangle
            ));
        }
        let mut packed: Vec<(&Tri, f64, Endpoint)> = vec![];
        for cover_ep in cover_eps {
            if cover_ep.instance == target_ep.instance
                && cover_ep.lod == target_ep.lod
                && cover_ep.triangle == target_ep.triangle
            {
                return Err(format!(
                    "refusing self-cover of triangle {}",
                    target_ep.triangle
                ));
            }
            let cover = geoms.get(cover_ep).ok_or_else(|| {
                format!("missing cover geometry for triangle {}", cover_ep.triangle)
            })?;
            let either = matches!(kind, SheetKind::GroundTopReplace) && cover.two_sided;
            let area = world_overlap_at_tol(&target.world, &cover.world, front_like, tolerance, either).ok_or_else(|| {
                format!(
                    "accepted cover {} lost overlap on triangle {}",
                    cover_ep.triangle, target_ep.triangle
                )
            })?;
            packed.push((&cover.world, area, cover_ep.clone()));
        }
        let covers_owned: Vec<Endpoint> = packed.iter().map(|(_, _, ep)| ep.clone()).collect();
        let refs: Vec<(&Tri, f64)> = packed.iter().map(|(tri, area, _)| (*tri, *area)).collect();
        let (before, after, front_area, removed_area, pieces, removed_pieces) =
            partition_sheet(&target.world, &target.local, &refs, front_like, target_ep.triangle)?;
        out.push(Emitted {
            asset: target.asset.clone(),
            key: inst.key.clone(),
            matrix: target.matrix,
            materials: inst.materials.clone(),
            two_sided: inst.two_sided.clone(),
            blend: inst.blend.clone(),
            lod: target_ep.lod,
            sha: target.sha.clone(),
            front_existing,
            patch: SheetPatch {
                operation,
                plane_tolerance_cm: tolerance,
                triangle: target_ep.triangle,
                material_slot: target.slot,
                area_before_cm2: before,
                area_after_cm2: after,
                front_only_area_cm2: front_area,
                removed_area_cm2: removed_area,
                covers: covers_owned,
                pieces,
                removed_pieces,
            },
        });
    }
    Ok(())
}

pub fn build_world_plan(
    folder: &Path,
    inventory_path: &Path,
    ledger_path: &Path,
    conflicts_path: &Path,
) -> Result<Value, String> {
    let inventory: Value = serde_json::from_slice(
        &fs::read(inventory_path)
            .map_err(|e| format!("read {}: {e}", inventory_path.display()))?,
    )
    .map_err(|e| format!("parse {}: {e}", inventory_path.display()))?;
    let enable_mixed = selector_flag(&inventory, "enable_mixed_same_facing")?;
    let prefer_same_facing = selector_flag(&inventory, "prefer_same_facing_pass")?;
    let mut floor_labels = HashSet::new();
    let mut front_tolerances:HashMap<String,f64>=HashMap::new();
    let mut ground_replacements=HashSet::new();let mut actual_buildings=HashSet::new();let mut cover_only_labels=HashSet::new();
    for actor in inventory
        .get("actors")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "inventory actors array required".to_string())?
    {
        if actor.get("cover_only")==Some(&Value::Bool(true)){cover_only_labels.insert(json_str(actor,"label")?.to_string());}
        if actor.get("building_floor")==Some(&Value::Bool(true)){actual_buildings.insert(json_str(actor,"label")?.to_string());}
        if actor.get("ground_top_replace")==Some(&Value::Bool(true)){ground_replacements.insert(json_str(actor,"label")?.to_string());}
        // A dedicated selector may opt in non-occupiable ground components;
        // the original building-floor inventory remains the default input.
        if actor.get("repair_eligible").and_then(Value::as_bool)
            .unwrap_or(actor.get("building_floor") == Some(&Value::Bool(true))) {
            let label = actor
                .get("label")
                .and_then(|v| v.as_str())
                .filter(|s| !s.is_empty())
                .ok_or_else(|| "building_floor actor missing label".to_string())?;
            let tolerance=actor.get("front_only_tolerance_cm").and_then(Value::as_f64).unwrap_or(PLANE_TOL);
            if !tolerance.is_finite()||tolerance<PLANE_TOL||tolerance>0.2{return Err(format!("invalid front-only tolerance on {label}"));}
            front_tolerances.insert(label.to_string(),tolerance);
            floor_labels.insert(label.to_string());
        }
    }
    let scene_bytes = fs::read(folder.join("scene.json"))
        .map_err(|e| format!("read scene.json: {e}"))?;
    let scene_sha256 = hex_sha256(&scene_bytes);
    let scene: Value = serde_json::from_slice(&scene_bytes).map_err(|e| format!("parse scene.json: {e}"))?;
    if !scene
        .get("format")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .starts_with("CDY2")
    {
        return Err("Fresh CDY2 export with per-triangle material slots required".to_string());
    }
    let mesh_values = scene
        .get("meshes")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "scene meshes array required".to_string())?;
    let mut meshes = Vec::with_capacity(mesh_values.len());
    for (mid, mesh) in mesh_values.iter().enumerate() {
        let asset = json_str(mesh, "asset")
            .map_err(|e| format!("mesh {mid} {e}"))?;
        let mut lods = vec![];
        for (li, lod) in mesh
            .get("lods")
            .and_then(|v| v.as_array())
            .ok_or_else(|| format!("mesh {mid} lods array required"))?
            .iter()
            .enumerate()
        {
            let level = json_i64(lod, "lod").map_err(|e| format!("mesh {mid} lod {li} {e}"))?;
            let file = json_str(lod, "file").map_err(|e| format!("mesh {mid} lod {li} {e}"))?;
            lods.push((level, file.to_string()));
        }
        meshes.push(SceneMesh {
            asset: asset.to_string(),
            lods,
        });
    }
    let instance_values = scene
        .get("instances")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "scene instances array required".to_string())?;
    let mut key_count: HashMap<String, usize> = HashMap::new();
    let mut mesh_count: HashMap<usize, usize> = HashMap::new();
    let mut parsed = Vec::with_capacity(instance_values.len());
    for (index, inst) in instance_values.iter().enumerate() {
        let actor = json_str(inst, "actor").map_err(|e| format!("instance {index} {e}"))?;
        let key = json_str(inst, "key").map_err(|e| format!("instance {index} {e}"))?;
        let mesh = json_usize(inst, "mesh").map_err(|e| format!("instance {index} {e}"))?;
        if mesh >= meshes.len() {
            return Err(format!("instance {index} mesh {mesh} is outside the scene"));
        }
        let matrix = parse_matrix(
            inst.get("matrix").ok_or_else(|| format!("instance {index} missing matrix"))?,
            &format!("instance {index}"),
        )?;
        let blends = inst
            .get("blend_modes")
            .and_then(|v| v.as_array())
            .ok_or_else(|| format!("instance {index} missing blend_modes"))?;
        let sides = inst
            .get("two_sided_by_slot")
            .and_then(|v| v.as_array())
            .ok_or_else(|| format!("instance {index} missing two_sided_by_slot"))?;
        let materials = inst
            .get("materials")
            .and_then(|v| v.as_array())
            .ok_or_else(|| format!("instance {index} missing materials"))?;
        if blends.len() != sides.len() || blends.len() != materials.len() {
            return Err(format!(
                "instance {index} blend_modes, two_sided_by_slot and materials differ in length"
            ));
        }
        let mut blend = Vec::with_capacity(blends.len());
        let mut two_sided = Vec::with_capacity(sides.len());
        let mut material_names = Vec::with_capacity(materials.len());
        for i in 0..blends.len() {
            blend.push(
                blends[i]
                    .as_i64()
                    .ok_or_else(|| format!("instance {index} blend_modes[{i}] is not an integer"))?,
            );
            two_sided.push(sides[i].as_bool().ok_or_else(|| {
                format!("instance {index} two_sided_by_slot[{i}] is not a bool")
            })?);
            material_names.push(
                materials[i]
                    .as_str()
                    .ok_or_else(|| format!("instance {index} materials[{i}] is not a string"))?
                    .to_string(),
            );
        }
        *key_count.entry(key.to_string()).or_insert(0) += 1;
        *mesh_count.entry(mesh).or_insert(0) += 1;
        parsed.push((
            actor.to_string(),
            key.to_string(),
            mesh,
            matrix,
            blend,
            two_sided,
            material_names,
            multi_transform(inst),
        ));
    }
    let mut instances = Vec::with_capacity(parsed.len());
    for (actor, key, mesh, matrix, blend, two_sided, materials, multi) in parsed {
        let det = mat_det(&matrix);
        let unusable = if key_count[&key] != 1 {
            Some("component key is shared by multiple scene instances".to_string())
        } else if multi {
            Some("component has multiple instance transforms".to_string())
        } else if !det.is_finite() || det.abs() < SINGULAR_DET {
            Some("singular component transform".to_string())
        } else if det < 0.0 {
            Some("negative determinant on component transform".to_string())
        } else {
            None
        };
        let floor = floor_labels.contains(&actor);
        let front_tolerance_cm=front_tolerances.get(&actor).copied().unwrap_or(PLANE_TOL);
        let ground_top_replace=ground_replacements.contains(&actor);let actual_building_floor=actual_buildings.contains(&actor);let cover_only=cover_only_labels.contains(&actor);
        instances.push(SceneInst {
            actor,
            key,
            mesh,
            asset: meshes[mesh].asset.clone(),
            matrix,
            blend,
            two_sided,
            materials,
            floor,
            unusable,
            shared_mesh: mesh_count[&mesh] != 1,
            front_tolerance_cm,
            ground_top_replace,actual_building_floor,cover_only,
        });
    }

    let ledger: Value = serde_json::from_slice(
        &fs::read(ledger_path).map_err(|e| format!("read {}: {e}", ledger_path.display()))?,
    )
    .map_err(|e| format!("parse {}: {e}", ledger_path.display()))?;
    let mut front_slots: HashMap<String, BTreeMap<usize, usize>> = HashMap::new();
    let mut seen_ledger = HashSet::new();
    for (ci, comp) in ledger
        .get("components")
        .and_then(|v| v.as_array())
        .ok_or_else(|| "facing ledger components array required".to_string())?
        .iter()
        .enumerate()
    {
        let actor = json_str(comp, "actor").map_err(|e| format!("ledger component {ci} {e}"))?;
        let component =
            json_str(comp, "component").map_err(|e| format!("ledger component {ci} {e}"))?;
        let key = format!("{actor}::{component}");
        if !seen_ledger.insert(key.clone()) {
            return Err(format!("ledger component {key} is duplicated"));
        }
        let mesh_after =
            json_str(comp, "mesh_after").map_err(|e| format!("ledger component {key} {e}"))?;
        let original = json_usize(comp, "original_slot_count")
            .map_err(|e| format!("ledger component {key} {e}"))?;
        let bound: Vec<&SceneInst> = instances.iter().filter(|i| i.key == key).collect();
        if bound.len() != 1 {
            return Err(format!(
                "ledger component {key} does not bind to exactly one scene instance"
            ));
        }
        let inst = bound[0];
        if inst.asset != mesh_after {
            return Err(format!(
                "ledger component {key} mesh_after {mesh_after} != scene {}",
                inst.asset
            ));
        }
        let added = comp
            .get("added_slots")
            .and_then(|v| v.as_array())
            .ok_or_else(|| format!("ledger component {key} missing added_slots"))?;
        let mut slot_map = BTreeMap::new();
        for (si, slot) in added.iter().enumerate() {
            let ctx = format!("ledger {key} added_slots[{si}]");
            let source = json_usize(slot, "source_slot").map_err(|e| format!("{ctx} {e}"))?;
            let existing = json_usize(slot, "added_slot").map_err(|e| format!("{ctx} {e}"))?;
            let parent = json_str(slot, "parent_before").map_err(|e| format!("{ctx} {e}"))?;
            let after = json_str(slot, "material_after").map_err(|e| format!("{ctx} {e}"))?;
            if source >= original || existing < original || existing >= inst.materials.len() {
                return Err(format!("{ctx} is outside the scene material list"));
            }
            if inst.materials[source] != parent {
                return Err(format!(
                    "{ctx} parent_before does not match scene materials[{source}]"
                ));
            }
            if inst.materials[existing] != after {
                return Err(format!(
                    "{ctx} material_after does not match scene materials[{existing}]"
                ));
            }
            if inst.blend[existing] != 0 || inst.two_sided[existing] {
                return Err(format!(
                    "{ctx} existing slot {existing} is not an opaque one-sided material"
                ));
            }
            if slot_map.insert(source, existing).is_some() {
                return Err(format!("ledger {key} repeats source_slot {source}"));
            }
        }
        front_slots.insert(key, slot_map);
    }

    let report_path = companion_json_path(conflicts_path)?;
    let report_bytes = fs::read(&report_path)
        .map_err(|e| format!("read {}: {e}", report_path.display()))?;
    let report: Value = serde_json::from_slice(&report_bytes)
        .map_err(|e| format!("parse {}: {e}", report_path.display()))?;
    let meta = report
        .get("metadata_sha256")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "scan report missing metadata_sha256".to_string())?;
    if meta != scene_sha256 {
        return Err(format!(
            "scan metadata_sha256 {meta} != scene sha256 {scene_sha256}"
        ));
    }
    match report.get("truncated").and_then(|v| v.as_bool()) {
        Some(false) => {}
        Some(true) => {
            return Err(
                "scan report truncated is true; refusing a partial candidate file".to_string(),
            )
        }
        None => return Err("scan report missing truncated".to_string()),
    }
    let claimed = report
        .get("candidate_conflicts")
        .and_then(|v| v.as_u64())
        .ok_or_else(|| "scan report missing candidate_conflicts".to_string())?;
    let conflict_bytes = fs::read(conflicts_path)
        .map_err(|e| format!("read {}: {e}", conflicts_path.display()))?;
    let candidate_file_sha256 = hex_sha256(&conflict_bytes);
    let text = String::from_utf8(conflict_bytes)
        .map_err(|e| format!("conflicts are not utf-8: {e}"))?;
    let mut rows = Vec::new();
    for (n, line) in text.split('\n').enumerate() {
        let line = line.trim_end_matches('\r');
        if line.is_empty() {
            continue;
        }
        let value: Value = serde_json::from_str(line)
            .map_err(|e| format!("conflicts line {}: {e}", n + 1))?;
        let pass = json_i64(&value, "pass_lod").map_err(|e| format!("stale scan row: {e}"))?;
        let (a, a_slot, a_file) = side_endpoint(&value, "a", pass, &instances, &meshes)?;
        let (b, b_slot, b_file) = side_endpoint(&value, "b", pass, &instances, &meshes)?;
        rows.push(Cand {
            a,
            b,
            a_slot,
            b_slot,
            a_file,
            b_file,
        });
    }
    if rows.len() as u64 != claimed {
        return Err(format!(
            "candidate row count {} != candidate_conflicts {claimed}; not all rows were read",
            rows.len()
        ));
    }

    let mut needed: HashMap<String, HashSet<i32>> = HashMap::new();
    for row in &rows {
        needed.entry(row.a_file.clone()).or_default().insert(row.a.triangle);
        needed.entry(row.b_file.clone()).or_default().insert(row.b.triangle);
    }
    let mut loaded: HashMap<String, LoadedFile> = HashMap::new();
    for (file, ids) in &needed {
        loaded.insert(
            file.clone(),
            read_cdy2_needed(&folder.join(file), ids)?,
        );
    }
    for row in &rows {
        for (file, ep, slot) in [
            (&row.a_file, &row.a, row.a_slot),
            (&row.b_file, &row.b, row.b_slot),
        ] {
            let raw = &loaded[file].tris[&ep.triangle];
            if raw.slot as usize != slot {
                return Err(format!(
                    "stale scan row: triangle {} in {file} slot {} != scan slot {slot}",
                    ep.triangle, raw.slot
                ));
            }
        }
    }

    let mut exclusions: BTreeMap<String, u64> = BTreeMap::new();
    let mut seen_pairs: HashMap<(Endpoint, Endpoint), ()> = HashMap::new();
    let mut unique = Vec::new();
    for row in rows {
        let ordered = if (row.a.instance, row.a.lod, row.a.triangle, row.a.key.as_str())
            <= (row.b.instance, row.b.lod, row.b.triangle, row.b.key.as_str())
        {
            (row.a.clone(), row.b.clone())
        } else {
            (row.b.clone(), row.a.clone())
        };
        if seen_pairs.insert(ordered, ()).is_some() {
            bump(&mut exclusions, "duplicate_fallback_lod");
            continue;
        }
        unique.push(row);
    }

    let mut pending = Vec::new();
    let mut blocked: BTreeMap<(String, String), BTreeSet<String>> = BTreeMap::new();
    for row in unique {
        let ia = &instances[row.a.instance];
        let ib = &instances[row.b.instance];
        if !ia.floor || !ib.floor {
            bump(&mut exclusions, "not_building_floor");
            continue;
        }
        if row.a.instance == row.b.instance && !ia.ground_top_replace {
            // Different triangles on one component may continue for explicit
            // both-two-sided removal, or for opted-in mixed one-sided removal.
            // The exact same lod/triangle never covers itself.
            let both_two = ia.two_sided[row.a_slot] && ib.two_sided[row.b_slot];
            let distinct = row.a.lod != row.b.lod || row.a.triangle != row.b.triangle;
            let mixed = enable_mixed
                && distinct
                && ia.two_sided[row.a_slot] != ib.two_sided[row.b_slot];
            if !(both_two && distinct) && !mixed {
                bump(&mut exclusions, "same_instance");
                continue;
            }
        }
        if ia.unusable.is_some() || ib.unusable.is_some() {
            if let Some(reason) = &ia.unusable {
                bump(&mut exclusions, exclusion_name(reason));
                note_blocked(&mut blocked, ia, reason);
            }
            if let Some(reason) = &ib.unusable {
                if ia.unusable.is_none() {
                    bump(&mut exclusions, exclusion_name(reason));
                }
                note_blocked(&mut blocked, ib, reason);
            }
            continue;
        }
        if ia.blend[row.a_slot] != 0 || ib.blend[row.b_slot] != 0 {
            bump(&mut exclusions, "masked_or_translucent");
            continue;
        }
        pending.push(row);
    }

    let mut geoms: HashMap<Endpoint, Geom> = HashMap::new();
    let mut degenerate = HashSet::new();
    for row in &pending {
        for (ep, file, slot) in [
            (&row.a, &row.a_file, row.a_slot),
            (&row.b, &row.b_file, row.b_slot),
        ] {
            if geoms.contains_key(ep) || degenerate.contains(ep) {
                continue;
            }
            let raw = &loaded[file].tris[&ep.triangle];
            let inst = &instances[ep.instance];
            let (Some(local), Some(world)) = (
                Tri::new(raw.p),
                Tri::new(raw.p.map(|p| transform_point(p, &inst.matrix))),
            ) else {
                degenerate.insert(ep.clone());
                continue;
            };
            let area_q = quantize_area(world.area)?;
            geoms.insert(
                ep.clone(),
                Geom {
                    world,
                    local,
                    area_q,
                    slot: slot as u32,
                    asset: inst.asset.clone(),
                    matrix: inst.matrix,
                    material: inst.materials[slot].clone(),
                    sha: loaded[file].sha.clone(),
                    two_sided: inst.two_sided[slot],
                },
            );
        }
    }

    let mut front_groups: BTreeMap<Endpoint, BTreeSet<Endpoint>> = BTreeMap::new();
    let mut remove_groups: BTreeMap<Endpoint, BTreeSet<Endpoint>> = BTreeMap::new();
    let mut ground_groups:BTreeMap<Endpoint,BTreeSet<Endpoint>>=BTreeMap::new();
    let mut duplicate_groups: BTreeMap<Endpoint, BTreeSet<Endpoint>> = BTreeMap::new();
    let mut mixed_groups: BTreeMap<Endpoint, BTreeSet<Endpoint>> = BTreeMap::new();
    let mut paired_groups: BTreeMap<Endpoint, BTreeSet<Endpoint>> = BTreeMap::new();
    for row in &pending {
        let (Some(ga), Some(gb)) = (geoms.get(&row.a), geoms.get(&row.b)) else {
            bump(&mut exclusions, "geometry_rejected");
            continue;
        };
        let dotn = dot(ga.world.n, gb.world.n);
        let opposite = if dotn <= NORMAL_DOT_MAX {
            true
        } else if dotn >= SAME_DOT {
            false
        } else {
            bump(&mut exclusions, "geometry_rejected");
            continue;
        };
        let ground_a = upward_terrain(&instances[row.a.instance], ga)
            && ground_cover_choice(ga, gb, &instances[row.b.instance], opposite);
        let ground_b = upward_terrain(&instances[row.b.instance], gb)
            && ground_cover_choice(gb, ga, &instances[row.a.instance], opposite);
        if row.a.instance==row.b.instance&&!ground_a&&!ground_b{
            let both_two=ga.two_sided&&gb.two_sided;
            let distinct=row.a.lod!=row.b.lod||row.a.triangle!=row.b.triangle;
            // Non-overlapping same-component rows stay same_instance so a separated
            // fixture is not reclassified as a geometry miss. Proved strict-plane
            // overlap of two different two-sided triangles, or an opted-in mixed
            // pair, is the exception. Mixed stays on the 0.002 cm plane.
            let mixed_plane = enable_mixed
                && ga.two_sided != gb.two_sided
                && distinct
                && world_overlap_at_tol(&ga.world, &gb.world, false, PLANE_TOL, false).is_some();
            if !(both_two && distinct && world_overlap_at_tol(&ga.world,&gb.world,opposite,PLANE_TOL,false).is_some()) && !mixed_plane {
                bump(&mut exclusions,"same_instance");
                continue;
            }
        }
        let tolerance=if ground_a{instances[row.a.instance].front_tolerance_cm}else if ground_b{instances[row.b.instance].front_tolerance_cm}else if opposite&&ga.two_sided&&!gb.two_sided{instances[row.a.instance].front_tolerance_cm}else if opposite&&gb.two_sided&&!ga.two_sided{instances[row.b.instance].front_tolerance_cm}else{PLANE_TOL};
        if world_overlap_at_tol(&ga.world,&gb.world,opposite,tolerance,false).is_none() {
            bump(&mut exclusions, "geometry_rejected");
            continue;
        }
        if ground_a||ground_b{
            let (target,cover)=if ground_a{(&row.a,&row.b)}else{(&row.b,&row.a)};
            if target.instance==cover.instance && target.lod==cover.lod && target.triangle==cover.triangle {
                bump(&mut exclusions,"same_instance");
            } else if instances[target.instance].shared_mesh {
                note_blocked(&mut blocked,&instances[target.instance],"shared ground replacement target");
            } else {
                ground_groups.entry(target.clone()).or_default().insert(cover.clone());
            }
            continue;
        }
        if opposite {
            match (ga.two_sided, gb.two_sided) {
                (true, false) => {
                    if instances[row.a.instance].cover_only{bump(&mut exclusions,"immutable_cover_target");continue;}
                    if instances[row.a.instance].shared_mesh {
                        bump(&mut exclusions, "blocked_target");
                        note_blocked(
                            &mut blocked,
                            &instances[row.a.instance],
                            "shared mesh has multiple scene instances",
                        );
                    } else {
                        front_groups.entry(row.a.clone()).or_default().insert(row.b.clone());
                    }
                }
                (false, true) => {
                    if instances[row.b.instance].cover_only{bump(&mut exclusions,"immutable_cover_target");continue;}
                    if instances[row.b.instance].shared_mesh {
                        bump(&mut exclusions, "blocked_target");
                        note_blocked(
                            &mut blocked,
                            &instances[row.b.instance],
                            "shared mesh has multiple scene instances",
                        );
                    } else {
                        front_groups.entry(row.b.clone()).or_default().insert(row.a.clone());
                    }
                }
                (true, true) => {
                    if instances[row.a.instance].cover_only || instances[row.b.instance].cover_only {
                        bump(&mut exclusions, "immutable_cover_target");
                        continue;
                    }
                    if instances[row.a.instance].shared_mesh || instances[row.b.instance].shared_mesh {
                        bump(&mut exclusions, "blocked_target");
                        if instances[row.a.instance].shared_mesh {
                            note_blocked(&mut blocked, &instances[row.a.instance], "shared mesh has multiple scene instances");
                        }
                        if instances[row.b.instance].shared_mesh {
                            note_blocked(&mut blocked, &instances[row.b.instance], "shared mesh has multiple scene instances");
                        }
                        continue;
                    }
                    paired_groups.entry(row.a.clone()).or_default().insert(row.b.clone());
                    paired_groups.entry(row.b.clone()).or_default().insert(row.a.clone());
                }
                (false, false) => bump(&mut exclusions, "opposite_both_one_sided"),
            }
        } else {
            match (ga.two_sided, gb.two_sided) {
                (false, false) => {
                    let a_first = priority_tuple(ga, &row.a) < priority_tuple(gb, &row.b);
                    let (winner, loser) = if a_first {
                        (&row.a, &row.b)
                    } else {
                        (&row.b, &row.a)
                    };
                    if instances[loser.instance].cover_only{bump(&mut exclusions,"immutable_cover_target");continue;}
                    if instances[loser.instance].shared_mesh {
                        bump(&mut exclusions, "blocked_target");
                        note_blocked(
                            &mut blocked,
                            &instances[loser.instance],
                            "shared mesh has multiple scene instances",
                        );
                    } else {
                        remove_groups
                            .entry(loser.clone())
                            .or_default()
                            .insert(winner.clone());
                    }
                }
                (true, true) => {
                    let a_first = priority_tuple(ga, &row.a) < priority_tuple(gb, &row.b);
                    let (winner, loser) = if a_first { (&row.a, &row.b) } else { (&row.b, &row.a) };
                    if instances[loser.instance].cover_only {
                        bump(&mut exclusions, "immutable_cover_target");
                        continue;
                    }
                    if instances[loser.instance].shared_mesh {
                        bump(&mut exclusions, "blocked_target");
                        note_blocked(&mut blocked, &instances[loser.instance], "shared mesh has multiple scene instances");
                    } else {
                        duplicate_groups.entry(loser.clone()).or_default().insert(winner.clone());
                    }
                }
                (false, true) | (true, false) => {
                    if !enable_mixed {
                        bump(&mut exclusions, "same_facing_mixed");
                    } else {
                        let (target, cover) = if ga.two_sided {
                            (&row.b, &row.a)
                        } else {
                            (&row.a, &row.b)
                        };
                        if target.instance == cover.instance
                            && target.lod == cover.lod
                            && target.triangle == cover.triangle
                        {
                            bump(&mut exclusions, "same_instance");
                        } else if instances[target.instance].cover_only {
                            bump(&mut exclusions, "immutable_cover_target");
                        } else if instances[target.instance].shared_mesh {
                            bump(&mut exclusions, "blocked_target");
                            note_blocked(
                                &mut blocked,
                                &instances[target.instance],
                                "shared mesh has multiple scene instances",
                            );
                        } else {
                            mixed_groups
                                .entry(target.clone())
                                .or_default()
                                .insert(cover.clone());
                        }
                    }
                }
            }
        }
    }

    // A terrain top replaced by an opaque upward-facing floor is removed in
    // this pass. Its remaining area is unchanged; rear-only partitions can be
    // proposed again on a fresh scan, without duplicate patches for one face.
    for target in ground_groups.keys(){
        front_groups.remove(target);
        remove_groups.remove(target);
        mixed_groups.remove(target);
    }
    if enable_mixed {
        let mixed_targets: Vec<Endpoint> = mixed_groups.keys().cloned().collect();
        for target in mixed_targets {
            if let Some(extra) = remove_groups.remove(&target) {
                mixed_groups.entry(target).or_default().extend(extra);
            }
        }
        let missing: Vec<Endpoint> = mixed_groups
            .iter()
            .filter(|(_, covers)| !covers.iter().any(|ep| geoms.get(ep).is_some_and(|g| g.two_sided)))
            .map(|(ep, _)| ep.clone())
            .collect();
        for ep in &missing {
            bump(&mut exclusions, "same_facing_mixed");
            mixed_groups.remove(ep);
        }
    }
    if prefer_same_facing {
        let preferred: BTreeSet<Endpoint> = duplicate_groups
            .keys()
            .filter(|ep| front_groups.contains_key(*ep) || paired_groups.contains_key(*ep))
            .cloned()
            .collect();
        if !preferred.is_empty() {
            for _ in &preferred {
                bump(&mut exclusions, "deferred_same_facing_pass");
            }
            let paired_before: BTreeSet<Endpoint> = paired_groups.keys().cloned().collect();
            drop_sheet_endpoints(&mut front_groups, &preferred);
            drop_sheet_endpoints(&mut paired_groups, &preferred);
            for _ep in paired_before
                .iter()
                .filter(|ep| !preferred.contains(ep) && !paired_groups.contains_key(*ep))
            {
                bump(&mut exclusions, "deferred_unpaired_two_sided");
            }
            // Duplicate cover sets stay. Reciprocal paired edges are pruned
            // until none remain, so this pass never emits half a pair.
            prune_paired_fixed_point(&mut paired_groups, &mut exclusions);
        }
    }
    let mut kinds: BTreeMap<Endpoint, usize> = BTreeMap::new();
    for groups in [&front_groups, &remove_groups, &ground_groups, &duplicate_groups, &mixed_groups, &paired_groups] {
        for ep in groups.keys() {
            *kinds.entry(ep.clone()).or_insert(0) += 1;
        }
    }
    let ambiguous: BTreeSet<Endpoint> = kinds.into_iter().filter(|(_, n)| *n > 1).map(|(ep, _)| ep).collect();
    if !ambiguous.is_empty() {
        for _ in &ambiguous {
            bump(&mut exclusions, "ambiguous_two_sided_combination");
        }
        let mut emptied = BTreeSet::new();
        for (ep, covers) in &paired_groups {
            if ambiguous.contains(ep) {
                continue;
            }
            if covers.iter().all(|c| ambiguous.contains(c)) {
                emptied.insert(ep.clone());
            }
        }
        for _ in &emptied {
            bump(&mut exclusions, "deferred_unpaired_two_sided");
        }
        let mut gone = ambiguous;
        gone.extend(emptied);
        for groups in [&mut front_groups, &mut remove_groups, &mut ground_groups, &mut duplicate_groups, &mut mixed_groups, &mut paired_groups] {
            drop_sheet_endpoints(groups, &gone);
        }
    }
    let mut broken = BTreeSet::new();
    for (target, covers) in &paired_groups {
        for cover in covers {
            if !paired_groups.get(cover).is_some_and(|set| set.contains(target)) {
                broken.insert(target.clone());
                broken.insert(cover.clone());
            }
        }
    }
    if !broken.is_empty() {
        for _ in &broken {
            bump(&mut exclusions, "deferred_unpaired_two_sided");
        }
        for groups in [&mut front_groups, &mut remove_groups, &mut ground_groups, &mut duplicate_groups, &mut mixed_groups, &mut paired_groups] {
            drop_sheet_endpoints(groups, &broken);
        }
    }
    let mut emitted = Vec::new();
    emit_group(&front_groups, &geoms, &instances, &front_slots, SheetKind::FrontOnly, &mut exclusions, &mut blocked, &mut emitted)?;
    emit_group(&remove_groups, &geoms, &instances, &front_slots, SheetKind::Remove, &mut exclusions, &mut blocked, &mut emitted)?;
    emit_group(&mixed_groups, &geoms, &instances, &front_slots, SheetKind::RemoveOneSidedDuplicate, &mut exclusions, &mut blocked, &mut emitted)?;
    emit_group(&ground_groups, &geoms, &instances, &front_slots, SheetKind::GroundTopReplace, &mut exclusions, &mut blocked, &mut emitted)?;
    emit_group(&duplicate_groups, &geoms, &instances, &front_slots, SheetKind::RemoveDuplicateTwoSided, &mut exclusions, &mut blocked, &mut emitted)?;
    emit_group(&paired_groups, &geoms, &instances, &front_slots, SheetKind::PairedFrontOnly, &mut exclusions, &mut blocked, &mut emitted)?;
    let mut seen_patch = HashSet::new();
    for item in &emitted {
        if !seen_patch.insert((item.key.clone(), item.lod, item.patch.triangle)) {
            return Err(format!(
                "duplicate world patch on {} lod {} triangle {}",
                item.key, item.lod, item.patch.triangle
            ));
        }
    }
    let mut cover_ids: BTreeMap<Endpoint, u64> = BTreeMap::new();
    for item in &emitted {
        for ep in &item.patch.covers {
            cover_ids.entry(ep.clone()).or_default();
        }
    }
    for (i, id) in cover_ids.values_mut().enumerate() {
        *id = i as u64;
    }
    let mut covers = Vec::with_capacity(cover_ids.len());
    for (ep, id) in &cover_ids {
        let g = geoms.get(ep).ok_or_else(|| {
            format!("missing cover {} for id {id}", ep.triangle)
        })?;
        let mut record = json!({
            "id": id,
            "component_key": ep.key,
            "source_asset": g.asset,
            "lod": ep.lod,
            "triangle": ep.triangle,
            "material_slot": g.slot,
            "material": g.material,
            "world_matrix": g.matrix.to_vec(),
            "source_sha256": g.sha
        });
        if g.two_sided {
            record.as_object_mut().unwrap().insert("original_two_sided".to_string(), json!(true));
        }
        covers.push(record);
    }

    struct Acc {
        key: String,
        matrix: [f64; 16],
        materials: Vec<String>,
        two_sided: Vec<bool>,
        blend: Vec<i64>,
        front: BTreeMap<u32, usize>,
        lods: BTreeMap<i64, (String, Vec<SheetPatch>)>,
    }
    let mut accs: BTreeMap<String, Acc> = BTreeMap::new();
    let mut sources: BTreeMap<(String, i64), String> = BTreeMap::new();
    for item in emitted {
        let acc = accs.entry(item.asset.clone()).or_insert_with(|| Acc {
            key: item.key.clone(),
            matrix: item.matrix,
            materials: item.materials.clone(),
            two_sided: item.two_sided.clone(),
            blend: item.blend.clone(),
            front: BTreeMap::new(),
            lods: BTreeMap::new(),
        });
        if acc.key != item.key {
            return Err(format!(
                "refusing to emit shared mesh {} for more than one instance",
                item.asset
            ));
        }
        if let Some((slot, existing)) = item.front_existing {
            if let Some(prev) = acc.front.get(&slot) {
                if *prev != existing {
                    return Err(format!(
                        "front-only slot {slot} on {} maps to both {prev} and {existing}",
                        item.asset
                    ));
                }
            }
            acc.front.insert(slot, existing);
        }
        let lod = acc.lods.entry(item.lod).or_insert_with(|| (item.sha.clone(), vec![]));
        if lod.0 != item.sha {
            return Err(format!(
                "lod {} of {} has two source hashes",
                item.lod, item.asset
            ));
        }
        lod.1.push(item.patch);
        sources.insert((item.asset.clone(), item.lod), item.sha.clone());
    }
    for (ep, _) in &cover_ids {
        let g = &geoms[ep];
        if let Some(prev) = sources.insert((g.asset.clone(), ep.lod), g.sha.clone()) {
            if prev != g.sha {
                return Err(format!(
                    "lod {} of {} has two source hashes",
                    ep.lod, g.asset
                ));
            }
        }
    }

    let mut mesh_json = Vec::new();
    let mut modified = 0u64;
    for (asset, acc) in accs {
        let mut lods = Vec::new();
        for (lod, (sha, mut patches)) in acc.lods {
            patches.sort_by(|a, b| {
                a.triangle
                    .cmp(&b.triangle)
                    .then(a.operation.cmp(b.operation))
            });
            modified += patches.len() as u64;
            lods.push(json!({
                "lod": lod,
                "source_sha256": sha,
                "patches": patches.iter().map(|patch| {
                    let mut ids: Vec<u64> = patch.covers.iter().map(|ep| cover_ids[ep]).collect();
                    ids.sort_unstable();
                    ids.dedup();
                    json!({
                        "operation": patch.operation,
                        "plane_tolerance_cm":patch.plane_tolerance_cm,
                        "triangle": patch.triangle,
                        "material_slot": patch.material_slot,
                        "area_before_cm2": patch.area_before_cm2,
                        "area_after_cm2": patch.area_after_cm2,
                        "front_only_area_cm2": patch.front_only_area_cm2,
                        "removed_area_cm2": patch.removed_area_cm2,
                        "cover_ids": ids,
                        "pieces": piece_json(&patch.pieces),
                        "removed_pieces": piece_json(&patch.removed_pieces)
                    })
                }).collect::<Vec<_>>()
            }));
        }
        mesh_json.push(json!({
            "source_asset": asset,
            "component_keys": [acc.key],
            "world_matrix": acc.matrix.to_vec(),
            "materials": acc.materials,
            "two_sided_by_slot": acc.two_sided,
            "blend_modes": acc.blend,
            "front_slot_map": acc.front.iter().map(|(slot, existing)| json!({
                "source_slot": slot,
                "existing_slot": existing
            })).collect::<Vec<_>>(),
            "lods": lods
        }));
    }
    let blocked_json: Vec<Value> = blocked
        .into_iter()
        .map(|((asset, reason), keys)| {
            json!({
                "source_asset": asset,
                "reason": reason,
                "component_keys": keys.into_iter().collect::<Vec<_>>()
            })
        })
        .collect();
    exclusions.retain(|_, n| *n > 0);
    let sources_json: Vec<Value> = sources
        .into_iter()
        .map(|((asset, lod), sha)| {
            json!({
                "source_asset": asset,
                "lod": lod,
                "source_sha256": sha
            })
        })
        .collect();
    Ok(json!({
        "status": "prepared_requires_native_validation",
        "method": "world_opaque_sheet_partition",
        "scene_sha256": scene_sha256,
        "candidate_file_sha256": candidate_file_sha256,
        "distance_tolerance_cm": front_tolerances.values().copied().fold(PLANE_TOL,f64::max),
        "remove_distance_tolerance_cm":PLANE_TOL,
        "blocked": blocked_json,
        "exclusions": exclusions,
        "modified_source_triangles": modified,
        "sources": sources_json,
        "covers": covers,
        "meshes": mesh_json
    }))
}

#[cfg(test)]
mod world_tests {
    use super::*;

    struct Case(PathBuf);
    impl Drop for Case {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    struct WInst {
        actor: String,
        component: String,
        asset: String,
        floor: bool,
        matrix: [f64; 16],
        blend: Vec<i64>,
        two_sided: Vec<bool>,
        materials: Vec<String>,
        tris: Vec<([[f64; 3]; 3], u32, i32)>,
        front: Vec<(usize, usize)>,
        share_of: Option<usize>,
    }

    fn eye() -> [f64; 16] {
        [
            1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
        ]
    }

    fn make(
        actor: &str,
        asset: &str,
        floor: bool,
        matrix: [f64; 16],
        blend: &[i64],
        sided: &[bool],
        materials: &[&str],
        tris: Vec<([[f64; 3]; 3], u32, i32)>,
        front: Vec<(usize, usize)>,
    ) -> WInst {
        WInst {
            actor: actor.into(),
            component: "StaticMesh".into(),
            asset: asset.into(),
            floor,
            matrix,
            blend: blend.to_vec(),
            two_sided: sided.to_vec(),
            materials: materials.iter().map(|s| (*s).to_string()).collect(),
            tris,
            front,
            share_of: None,
        }
    }

    fn right(scale: f64, z: f64) -> [[f64; 3]; 3] {
        [[0.0, 0.0, z], [scale, 0.0, z], [0.0, scale, z]]
    }
    fn flip(p: [[f64; 3]; 3]) -> [[f64; 3]; 3] {
        [p[0], p[2], p[1]]
    }
    fn tri(p: [[f64; 3]; 3], slot: u32, id: i32) -> ( [[f64; 3]; 3], u32, i32) {
        (p, slot, id)
    }

    fn write_cdy2(tris: &[([ [f32; 3]; 3], u32, u32)]) -> Vec<u8> {
        let nv = tris.len() * 3;
        let nt = tris.len();
        let mut b = Vec::new();
        for n in [0x43445932u32, nv as u32, nt as u32] {
            b.extend(n.to_le_bytes());
        }
        for (p, _, _) in tris {
            for v in p {
                for c in v {
                    b.extend(c.to_le_bytes());
                }
            }
        }
        for i in 0..nt {
            for k in 0..3u32 {
                b.extend(((i as u32) * 3 + k).to_le_bytes());
            }
        }
        for (_, _, id) in tris {
            b.extend(id.to_le_bytes());
        }
        for (_, slot, _) in tris {
            b.extend(slot.to_le_bytes());
        }
        b
    }

    fn scan_row(
        insts: &[WInst],
        pass: i64,
        a: usize,
        a_slot: usize,
        a_tri: i32,
        a_two: bool,
        b: usize,
        b_slot: usize,
        b_tri: i32,
        b_two: bool,
        separation: f64,
        overlap: f64,
    ) -> Value {
        let key = |i: usize| format!("{}::{}", insts[i].actor, insts[i].component);
        json!({
            "pass_lod": pass,
            "a_instance": a,
            "b_instance": b,
            "a_actor": insts[a].actor,
            "b_actor": insts[b].actor,
            "a_key": key(a),
            "b_key": key(b),
            "a_triangle": a_tri,
            "b_triangle": b_tri,
            "a_lod": 0,
            "b_lod": 0,
            "a_two_sided": a_two,
            "b_two_sided": b_two,
            "a_material_slot": a_slot,
            "b_material_slot": b_slot,
            "separation_cm": separation,
            "overlap_cm2": overlap,
            "a_area_cm2": 0.0,
            "b_area_cm2": 0.0
        })
    }

    fn prepare(name: &str, insts: &[WInst], rows: &[Value]) -> Case {
        let n = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "ok-world-sheets-{}-{n}-{name}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let mut mesh_of = vec![0usize; insts.len()];
        let mut mesh_json = Vec::new();
        for (i, inst) in insts.iter().enumerate() {
            if let Some(src) = inst.share_of {
                assert!(src < i);
                mesh_of[i] = mesh_of[src];
                continue;
            }
            mesh_of[i] = mesh_json.len();
            let file = format!("mesh-{i}.cdy2");
            let encoded: Vec<([ [f32; 3]; 3], u32, u32)> = inst
                .tris
                .iter()
                .map(|(p, slot, id)| (p.map(|v| v.map(|c| c as f32)), *slot, *id as u32))
                .collect();
            fs::write(dir.join(&file), write_cdy2(&encoded)).unwrap();
            mesh_json.push(json!({
                "asset": inst.asset,
                "lods": [{"lod": 0, "file": file}]
            }));
        }
        let instances: Vec<Value> = insts
            .iter()
            .enumerate()
            .map(|(i, inst)| {
                json!({
                    "mesh": mesh_of[i],
                    "actor": inst.actor,
                    "key": format!("{}::{}", inst.actor, inst.component),
                    "matrix": inst.matrix.to_vec(),
                    "blend_modes": inst.blend,
                    "two_sided_by_slot": inst.two_sided,
                    "materials": inst.materials
                })
            })
            .collect();
        let scene = json!({
            "format": "CDY2",
            "instances": instances,
            "meshes": mesh_json
        });
        let scene_bytes = serde_json::to_vec(&scene).unwrap();
        fs::write(dir.join("scene.json"), &scene_bytes).unwrap();
        let mut labels = BTreeMap::new();
        for inst in insts {
            if let Some(prev) = labels.insert(inst.actor.clone(), inst.floor) {
                assert_eq!(prev, inst.floor, "conflicting floor flag for {}", inst.actor);
            }
        }
        let actors: Vec<Value> = labels
            .iter()
            .map(|(label, floor)| json!({"label": label, "building_floor": floor}))
            .collect();
        fs::write(
            dir.join("inventory-baseline.json"),
            serde_json::to_vec(&json!({"actors": actors})).unwrap(),
        )
        .unwrap();
        let mut components = Vec::new();
        for (i, inst) in insts.iter().enumerate() {
            let original = inst.materials.len() - inst.front.len();
            let asset = insts
                .iter()
                .enumerate()
                .find(|(j, _)| *j == inst.share_of.unwrap_or(i) || (*j == i && inst.share_of.is_none()))
                .map(|(_, owner)| {
                    if inst.share_of.is_some() {
                        insts[inst.share_of.unwrap()].asset.clone()
                    } else {
                        owner.asset.clone()
                    }
                })
                .unwrap();
            let added: Vec<Value> = inst
                .front
                .iter()
                .map(|(source, added)| {
                    assert!(*source < original && *added >= original && *added < inst.materials.len());
                    json!({
                        "source_slot": source,
                        "added_slot": added,
                        "parent_before": inst.materials[*source],
                        "material_after": inst.materials[*added]
                    })
                })
                .collect();
            components.push(json!({
                "actor": inst.actor,
                "component": inst.component,
                "mesh_after": asset,
                "original_slot_count": original,
                "added_slots": added
            }));
        }
        fs::write(
            dir.join("facing-install.json"),
            serde_json::to_vec(&json!({"components": components})).unwrap(),
        )
        .unwrap();
        let mut conflict_bytes = Vec::new();
        for row in rows {
            serde_json::to_writer(&mut conflict_bytes, row).unwrap();
            conflict_bytes.push(b'\n');
        }
        fs::write(dir.join("scan.conflicts.jsonl"), &conflict_bytes).unwrap();
        fs::write(
            dir.join("scan.json"),
            serde_json::to_vec(&json!({
                "metadata_sha256": hex_sha256(&scene_bytes),
                "truncated": false,
                "candidate_conflicts": rows.len()
            }))
            .unwrap(),
        )
        .unwrap();
        Case(dir)
    }

    fn plan(case: &Case) -> Result<Value, String> {
        build_world_plan(
            &case.0,
            &case.0.join("inventory-baseline.json"),
            &case.0.join("facing-install.json"),
            &case.0.join("scan.conflicts.jsonl"),
        )
    }

    fn near(v: &Value, key: &str, expect: f64) {
        let got = v.get(key).and_then(|x| x.as_f64()).unwrap();
        assert!(
            (got - expect).abs() < 0.05,
            "{key}={got} expected {expect} in {v}"
        );
    }

    fn mesh<'a>(plan: &'a Value, asset: &str) -> &'a Value {
        plan["meshes"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["source_asset"] == asset)
            .unwrap_or_else(|| panic!("missing mesh {asset} in {plan}"))
    }

    fn excl(plan: &Value, key: &str) -> u64 {
        plan["exclusions"]
            .get(key)
            .and_then(|v| v.as_u64())
            .unwrap_or(0)
    }

    fn patches<'a>(plan: &'a Value, asset: &str) -> &'a Vec<Value> {
        mesh(plan, asset)["lods"][0]["patches"]
            .as_array()
            .unwrap()
    }

    #[test]
    fn world_opposite_mixed_full_and_partial_cross_actor() {
        let full = right(100.0, 0.0);
        let part = right(100.0, 500.0);
        let part_cover = flip([[0.0, 0.0, 500.0], [40.0, 0.0, 500.0], [0.0, 40.0, 500.0]]);
        let insts = vec![
            make("FullTarget", "/Game/FullTarget.FullTarget", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Front"], vec![tri(full, 0, 100)], vec![(0, 1)]),
            make("FullCover", "/Game/FullCover.FullCover", true, eye(), &[0], &[false], &["MI_CoverFull"], vec![tri(flip(full), 0, 200)], vec![]),
            make("PartTarget", "/Game/PartTarget.PartTarget", true, eye(), &[0, 0], &[true, false], &["parent", "MI_FrontPart"], vec![tri(part, 0, 7)], vec![(0, 1)]),
            make("PartCover", "/Game/PartCover.PartCover", true, eye(), &[0], &[false], &["MI_CoverPart"], vec![tri(part_cover, 0, 8)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 100, true, 1, 0, 200, false, 123456.0, 0.0),
            scan_row(&insts, 0, 2, 0, 7, true, 3, 0, 8, false, 123456.0, 0.0),
        ];
        let case = prepare("full-partial", &insts, &rows);
        let plan = plan(&case).unwrap();
        assert_eq!(plan["method"], "world_opaque_sheet_partition");
        assert_eq!(plan["modified_source_triangles"], 2);
        let full_patch = &patches(&plan, "/Game/FullTarget.FullTarget")[0];
        assert_eq!(full_patch["operation"], "front_only");
        assert_eq!(full_patch["triangle"], 100);
        near(full_patch, "area_before_cm2", 5000.0);
        near(full_patch, "area_after_cm2", 5000.0);
        near(full_patch, "front_only_area_cm2", 5000.0);
        assert_eq!(full_patch["removed_area_cm2"], 0.0);
        assert!(full_patch["removed_pieces"].as_array().unwrap().is_empty());
        assert!(full_patch["pieces"]
            .as_array()
            .unwrap()
            .iter()
            .all(|p| p["front_only"] == true));
        assert_eq!(mesh(&plan, "/Game/FullTarget.FullTarget")["front_slot_map"][0]["existing_slot"], 1);
        let part_patch = &patches(&plan, "/Game/PartTarget.PartTarget")[0];
        near(part_patch, "front_only_area_cm2", 800.0);
        near(part_patch, "area_after_cm2", 5000.0);
        assert_eq!(part_patch["removed_area_cm2"], 0.0);
        assert!(part_patch["pieces"].as_array().unwrap().iter().any(|p| p["front_only"] == true));
        assert!(part_patch["pieces"].as_array().unwrap().iter().any(|p| p["front_only"] == false));
        assert_eq!(plan["covers"].as_array().unwrap().len(), 2);
        assert!(plan["covers"].as_array().unwrap().iter().all(|c| c.get("original_two_sided").is_none()));
    }

    #[test]
    fn world_same_facing_one_sided_union_is_acyclic() {
        let small = right(10.0, 0.0);
        let large = right(20.0, 0.0);
        let insts = vec![
            make("A", "/Game/A.A", true, eye(), &[0], &[false], &["MI_A"], vec![tri(small, 0, 11)], vec![]),
            make("B", "/Game/B.B", true, eye(), &[0], &[false], &["MI_B"], vec![tri(small, 0, 2)], vec![]),
            make("D", "/Game/D.D", true, eye(), &[0], &[false], &["MI_D"], vec![tri(large, 0, 30)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 11, false, 1, 0, 2, false, 99999.0, 0.0),
            scan_row(&insts, 0, 0, 0, 11, false, 2, 0, 30, false, 99999.0, 0.0),
            scan_row(&insts, 0, 1, 0, 2, false, 2, 0, 30, false, 99999.0, 0.0),
        ];
        let case = prepare("union", &insts, &rows);
        let plan = plan(&case).unwrap();
        assert!(plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] != "/Game/A.A"));
        let b = &patches(&plan, "/Game/B.B")[0];
        assert_eq!(b["operation"], "remove");
        assert_eq!(b["front_only_area_cm2"], 0.0);
        near(b, "area_before_cm2", 50.0);
        near(b, "removed_area_cm2", 50.0);
        near(b, "area_after_cm2", 0.0);
        assert!((b["area_after_cm2"].as_f64().unwrap() + b["removed_area_cm2"].as_f64().unwrap() - 50.0).abs() < 0.05);
        assert!(b["removed_pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        let d = &patches(&plan, "/Game/D.D")[0];
        assert_eq!(d["operation"], "remove");
        assert_eq!(d["front_only_area_cm2"], 0.0);
        near(d, "area_before_cm2", 200.0);
        near(d, "removed_area_cm2", 50.0);
        near(d, "area_after_cm2", 150.0);
        assert!(d["removed_area_cm2"].as_f64().unwrap() < 80.0, "union was double counted");
        let b_cover = b["cover_ids"][0].as_u64().unwrap();
        let cover = plan["covers"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["id"].as_u64() == Some(b_cover))
            .unwrap();
        assert_eq!(cover["triangle"], 11);
        assert_ne!(cover["triangle"], 30);
        assert_eq!(d["cover_ids"].as_array().unwrap().len(), 2);
        assert!(d["cover_ids"].as_array().unwrap().iter().any(|id| id.as_u64() == Some(b_cover)));
        let retained = 50.0 + b["area_after_cm2"].as_f64().unwrap() + d["area_after_cm2"].as_f64().unwrap();
        assert!((retained - 200.0).abs() < 0.05, "world union changed: {retained}");
    }

    #[test]
    fn world_masked_cover_is_excluded() {
        let p = right(100.0, 0.0);
        let insts = vec![
            make("Target", "/Game/T.T", true, eye(), &[0], &[true], &["parent"], vec![tri(p, 0, 1)], vec![]),
            make("Masked", "/Game/M.M", true, eye(), &[1], &[false], &["mask"], vec![tri(flip(p), 0, 2)], vec![]),
            make("Translucent", "/Game/R.R", true, eye(), &[3, 0], &[true, false], &["trans", "front"], vec![tri(right(100.0, 50.0), 0, 3)], vec![(0, 1)]),
            make("Opaque", "/Game/O.O", true, eye(), &[0], &[false], &["opaque"], vec![tri(flip(right(100.0, 50.0)), 0, 4)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 2, false, 0.0, 5000.0),
            scan_row(&insts, 0, 2, 0, 3, true, 3, 0, 4, false, 0.0, 5000.0),
        ];
        let plan = plan(&prepare("masked", &insts, &rows)).unwrap();
        assert_eq!(excl(&plan, "masked_or_translucent"), 2);
        assert!(plan["meshes"].as_array().unwrap().is_empty());
        assert_eq!(plan["modified_source_triangles"], 0);
    }

    #[test]
    fn world_same_facing_mixed_and_two_sided_are_excluded() {
        let p = right(100.0, 0.0);
        let q = right(100.0, 400.0);
        let insts = vec![
            make("MixA", "/Game/MixA.MixA", true, eye(), &[0], &[true], &["a"], vec![tri(p, 0, 1)], vec![]),
            make("MixB", "/Game/MixB.MixB", true, eye(), &[0], &[false], &["b"], vec![tri(p, 0, 2)], vec![]),
            make("TwoA", "/Game/TwoA.TwoA", true, eye(), &[0], &[true], &["c"], vec![tri(q, 0, 3)], vec![]),
            make("TwoB", "/Game/TwoB.TwoB", true, eye(), &[0], &[true], &["d"], vec![tri(q, 0, 4)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 2, false, 0.0, 9000.0),
            scan_row(&insts, 0, 2, 0, 3, true, 3, 0, 4, true, 0.0, 9000.0),
        ];
        let plan = plan(&prepare("mixed", &insts, &rows)).unwrap();
        assert_eq!(excl(&plan, "same_facing_mixed"), 1);
        assert_eq!(excl(&plan, "same_facing_two_sided"), 0);
        let dup = &patches(&plan, "/Game/TwoB.TwoB")[0];
        assert_eq!(dup["operation"], "remove_duplicate_two_sided");
        assert_eq!(dup["plane_tolerance_cm"], 0.002);
        near(dup, "removed_area_cm2", 5000.0);
        near(dup, "area_after_cm2", 0.0);
        assert_eq!(dup["front_only_area_cm2"], 0.0);
        assert!(plan["meshes"].as_array().unwrap().iter().all(|m| {
            let asset = m["source_asset"].as_str().unwrap();
            asset != "/Game/TwoA.TwoA" && asset != "/Game/MixA.MixA" && asset != "/Game/MixB.MixB"
        }));
        assert_eq!(plan["covers"][0]["original_two_sided"], true);
        assert_eq!(plan["covers"][0]["component_key"], "TwoA::StaticMesh");
    }

    #[test]
    fn world_duplicate_native_ids_get_global_cover_ids() {
        let target = right(100.0, 0.0);
        let a = flip([[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 40.0, 0.0]]);
        let b = flip([[60.0, 0.0, 0.0], [100.0, 0.0, 0.0], [60.0, 40.0, 0.0]]);
        let insts = vec![
            make("Target", "/Game/Target.Target", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Front"], vec![tri(target, 0, 1)], vec![(0, 1)]),
            make("CoverA", "/Game/CoverA.CoverA", true, eye(), &[0], &[false], &["MI_A"], vec![tri(a, 0, 42)], vec![]),
            make("CoverB", "/Game/CoverB.CoverB", true, eye(), &[0], &[false], &["MI_B"], vec![tri(b, 0, 42)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 42, false, 5000.0, 0.0),
            scan_row(&insts, 0, 0, 0, 1, true, 2, 0, 42, false, 5000.0, 0.0),
        ];
        let plan = plan(&prepare("dup-id", &insts, &rows)).unwrap();
        let covers = plan["covers"].as_array().unwrap();
        assert_eq!(covers.len(), 2);
        assert!(covers.iter().all(|c| c["triangle"] == 42));
        assert_ne!(covers[0]["source_asset"], covers[1]["source_asset"]);
        let mut ids: Vec<i64> = covers.iter().map(|c| c["id"].as_i64().unwrap()).collect();
        ids.sort();
        assert_eq!(ids, vec![0, 1]);
        let patch = &patches(&plan, "/Game/Target.Target")[0];
        assert_eq!(patch["cover_ids"].as_array().unwrap().len(), 2);
        near(patch, "front_only_area_cm2", 1600.0);
        near(patch, "area_before_cm2", 5000.0);
        near(patch, "area_after_cm2", 5000.0);
    }

    #[test]
    fn world_fallback_lod_rows_dedup_by_source_identity() {
        let p = right(40.0, 0.0);
        let insts = vec![
            make("Target", "/Game/Target.Target", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Front"], vec![tri(p, 0, 5)], vec![(0, 1)]),
            make("Cover", "/Game/Cover.Cover", true, eye(), &[0], &[false], &["MI_Cover"], vec![tri(flip(p), 0, 6)], vec![]),
        ];
        let row = scan_row(&insts, 0, 0, 0, 5, true, 1, 0, 6, false, 4000.0, 1.0);
        let mut pass1 = row.clone();
        pass1["pass_lod"] = json!(1);
        let mut pass2 = row.clone();
        pass2["pass_lod"] = json!(2);
        let plan = plan(&prepare("dedup", &insts, &[row, pass1, pass2])).unwrap();
        assert_eq!(excl(&plan, "duplicate_fallback_lod"), 2);
        assert_eq!(plan["modified_source_triangles"], 1);
        near(&patches(&plan, "/Game/Target.Target")[0], "front_only_area_cm2", 800.0);
    }

    #[test]
    fn world_transform_preserves_local_area() {
        // Row-vector M: scale 2, 90° about Z, translate. Local corners do not
        // coincide; the cover is authored at the target's world corners.
        let matrix = [
            0.0, -2.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 0.0, 1_000_000.0, -2_000_000.0,
            300.0, 1.0,
        ];
        let local = right(10.0, 0.0);
        let world = [
            [1_000_000.0, -2_000_000.0, 300.0],
            [1_000_000.0, -2_000_020.0, 300.0],
            [1_000_020.0, -2_000_000.0, 300.0],
        ];
        assert_eq!(transform_point(local[0], &matrix), world[0]);
        assert_eq!(transform_point(local[1], &matrix), world[1]);
        assert_eq!(transform_point(local[2], &matrix), world[2]);
        let insts = vec![
            make("Target", "/Game/Target.Target", true, matrix, &[0, 0], &[true, false], &["parent", "MI_Front"], vec![tri(local, 0, 15)], vec![(0, 1)]),
            make("Cover", "/Game/Cover.Cover", true, eye(), &[0], &[false], &["MI_Cover"], vec![tri(flip(world), 0, 16)], vec![]),
        ];
        let plan = plan(&prepare(
            "xform",
            &insts,
            &[scan_row(&insts, 0, 0, 0, 15, true, 1, 0, 16, false, 0.0, 0.0)],
        ))
        .unwrap();
        let patch = &patches(&plan, "/Game/Target.Target")[0];
        near(patch, "area_before_cm2", 50.0);
        near(patch, "area_after_cm2", 50.0);
        near(patch, "front_only_area_cm2", 50.0);
        assert!((patch["front_only_area_cm2"].as_f64().unwrap() - 200.0).abs() > 10.0);
        assert_eq!(patch["removed_pieces"].as_array().unwrap().len(), 0);
        let stored = mesh(&plan, "/Game/Target.Target")["world_matrix"]
            .as_array()
            .unwrap();
        assert_eq!(stored.len(), 16);
        assert_eq!(stored[12].as_f64().unwrap(), 1_000_000.0);
    }

    #[test]
    fn world_far_origin_tilt_ignores_global_intercept() {
        let x = 1_000_000.0;
        let y = 1_000_000.0;
        let z1 = 1000.001f32 as f64;
        let target_p = [[x, y, 1000.0], [x + 100.0, y, 1000.0], [x, y + 100.0, 1000.0]];
        let cover_p = flip([[x, y, z1], [x + 100.0, y, 1000.0], [x, y + 100.0, z1]]);
        let target = Tri::new(target_p).unwrap();
        let cover = Tri::new(cover_p).unwrap();
        let gap = (dot(target.n_bin, target.origin) - dot(cover.n_bin, cover.origin)).abs();
        assert!(gap > 1.0, "fixture no longer separates global intercepts: {gap}");
        let decoy_a = right(80.0, 0.0);
        let decoy_b = flip(right(80.0, 10.0));
        let insts = vec![
            make("Far", "/Game/Far.Far", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Front"], vec![tri(target_p, 0, 50)], vec![(0, 1)]),
            make("FarCover", "/Game/FarCover.FarCover", true, eye(), &[0], &[false], &["MI_Far"], vec![tri(cover_p, 0, 60)], vec![]),
            make("Near", "/Game/Near.Near", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Near"], vec![tri(decoy_a, 0, 70)], vec![(0, 1)]),
            make("NearCover", "/Game/NearCover.NearCover", true, eye(), &[0], &[false], &["MI_NearCover"], vec![tri(decoy_b, 0, 80)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 50, true, 1, 0, 60, false, 80_000.0, 0.0),
            scan_row(&insts, 0, 2, 0, 70, true, 3, 0, 80, false, 0.0, 1.0e9),
        ];
        let plan = plan(&prepare("far", &insts, &rows)).unwrap();
        assert!(excl(&plan, "geometry_rejected") >= 1);
        assert_eq!(plan["meshes"].as_array().unwrap().len(), 1);
        let patch = &patches(&plan, "/Game/Far.Far")[0];
        assert_eq!(patch["triangle"], 50);
        near(patch, "front_only_area_cm2", 5000.0);
        near(patch, "area_after_cm2", 5000.0);
        assert!(plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] != "/Game/Near.Near"));
    }

    #[test]
    fn world_fixture_parses_cdy2_scene_ledger_and_scan() {
        let mut share_b = make("FloorShareB", "/Game/Shared.Shared", true, eye(), &[0], &[false], &["MI_ShareB"], vec![], vec![]);
        share_b.share_of = Some(2);
        let mirror = [
            -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
        ];
        let insts = vec![
            make("FloorTarget", "/Game/FloorTarget.FloorTarget", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Front"], vec![
                tri(right(100.0, 0.0), 0, 100),
                tri(right(10.0, 0.0).map(|mut v| { v[0] += 8000.0; v }), 0, 301),
                tri(flip(right(10.0, 0.0)).map(|mut v| { v[0] += 8000.0; v }), 0, 302),
                tri(right(10.0, 0.0).map(|mut v| { v[0] += 16000.0; v }), 0, 303),
            ], vec![(0, 1)]),
            make("FloorCover", "/Game/FloorCover.FloorCover", true, eye(), &[0], &[false], &["MI_Cover"], vec![tri(flip(right(100.0, 0.0)), 0, 200)], vec![]),
            make("FloorShareA", "/Game/Shared.Shared", true, eye(), &[0], &[false], &["MI_ShareA"], vec![tri(right(30.0, 0.0), 0, 7)], vec![]),
            share_b,
            make("FloorMirror", "/Game/Mirror.Mirror", true, mirror, &[0, 0], &[true, false], &["parent", "MI_Mirror"], vec![tri(right(20.0, 0.0), 0, 5)], vec![(0, 1)]),
            make("MirrorCover", "/Game/MirrorCover.MirrorCover", true, eye(), &[0], &[false], &["MI_MCover"], vec![tri(flip(right(20.0, 0.0)), 0, 6)], vec![]),
            make("FloorSolo", "/Game/Solo.Solo", true, eye(), &[0, 0], &[true, false], &["parent", "MI_Solo"], vec![tri(right(25.0, 800.0), 0, 8)], vec![(0, 1)]),
            make("NotFloor", "/Game/NotFloor.NotFloor", false, eye(), &[0], &[false], &["MI_Other"], vec![tri(flip(right(25.0, 800.0)), 0, 9)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 100, true, 1, 0, 200, false, 111.0, 0.0),
            scan_row(&insts, 0, 2, 0, 7, false, 3, 0, 7, false, 0.0, 450.0),
            scan_row(&insts, 0, 4, 0, 5, true, 5, 0, 6, false, 0.0, 200.0),
            scan_row(&insts, 0, 0, 0, 301, true, 0, 0, 302, true, 0.0, 50.0),
            scan_row(&insts, 0, 0, 0, 301, true, 0, 0, 303, true, 8000.0, 0.0),
            scan_row(&insts, 0, 6, 0, 8, true, 7, 0, 9, false, 0.0, 300.0),
        ];
        let case = prepare("fixture", &insts, &rows);
        let built = plan(&case).unwrap();
        assert_eq!(built["status"], "prepared_requires_native_validation");
        assert_eq!(built["method"], "world_opaque_sheet_partition");
        assert_eq!(built["distance_tolerance_cm"], 0.002);
        let scene_bytes = fs::read(case.0.join("scene.json")).unwrap();
        assert_eq!(built["scene_sha256"], hex_sha256(&scene_bytes));
        let conflict_bytes = fs::read(case.0.join("scan.conflicts.jsonl")).unwrap();
        assert_eq!(built["candidate_file_sha256"], hex_sha256(&conflict_bytes));
        assert_eq!(built["modified_source_triangles"], 3);
        let target = mesh(&built, "/Game/FloorTarget.FloorTarget");
        assert_eq!(target["component_keys"], json!(["FloorTarget::StaticMesh"]));
        assert_eq!(target["front_slot_map"], json!([{"source_slot": 0, "existing_slot": 1}]));
        assert_eq!(target["materials"][1], "MI_Front");
        let lod_file = fs::read(case.0.join("mesh-0.cdy2")).unwrap();
        assert_eq!(target["lods"][0]["source_sha256"], hex_sha256(&lod_file));
        let face_patches = target["lods"][0]["patches"].as_array().unwrap();
        assert_eq!(face_patches.len(), 3);
        let patch = &face_patches[0];
        assert_eq!(patch["triangle"], 100);
        assert_eq!(patch["operation"], "front_only");
        near(patch, "area_before_cm2", 5000.0);
        assert!(patch["pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == true));
        let paired301 = face_patches.iter().find(|p| p["triangle"] == 301).unwrap();
        let paired302 = face_patches.iter().find(|p| p["triangle"] == 302).unwrap();
        assert_eq!(paired301["operation"], "paired_front_only");
        assert_eq!(paired302["operation"], "paired_front_only");
        assert_eq!(paired301["plane_tolerance_cm"], 0.002);
        near(paired301, "front_only_area_cm2", 50.0);
        near(paired302, "front_only_area_cm2", 50.0);
        assert_eq!(paired301["cover_ids"][0], cover_named(&built, "/Game/FloorTarget.FloorTarget", 302)["id"]);
        assert_eq!(paired302["cover_ids"][0], cover_named(&built, "/Game/FloorTarget.FloorTarget", 301)["id"]);
        assert_eq!(cover_named(&built, "/Game/FloorTarget.FloorTarget", 301)["original_two_sided"], true);
        assert_eq!(cover_named(&built, "/Game/FloorTarget.FloorTarget", 302)["original_two_sided"], true);
        let cover = built["covers"].as_array().unwrap().iter().find(|c| c["triangle"] == 200).unwrap();
        assert!(cover.get("original_two_sided").is_none());
        assert_eq!(cover["triangle"], 200);
        assert_eq!(cover["material"], "MI_Cover");
        assert_eq!(cover["component_key"], "FloorCover::StaticMesh");
        assert_eq!(cover["world_matrix"].as_array().unwrap().len(), 16);
        let cover_bytes = fs::read(case.0.join("mesh-1.cdy2")).unwrap();
        assert_eq!(cover["source_sha256"], hex_sha256(&cover_bytes));
        let assets: Vec<_> = built["meshes"].as_array().unwrap().iter().map(|m| m["source_asset"].as_str().unwrap().to_string()).collect();
        assert_eq!(assets, vec!["/Game/FloorTarget.FloorTarget".to_string()]);
        let blocked = built["blocked"].as_array().unwrap();
        assert!(blocked.iter().any(|b| b["source_asset"] == "/Game/Shared.Shared" && b["reason"].as_str().unwrap().contains("shared mesh")));
        assert!(blocked.iter().any(|b| b["source_asset"] == "/Game/Mirror.Mirror" && b["reason"].as_str().unwrap().contains("negative determinant")));
        assert!(excl(&built, "blocked_target") >= 1);
        assert!(excl(&built, "rejected_transform") >= 1);
        assert!(excl(&built, "same_instance") >= 1);
        assert!(excl(&built, "not_building_floor") >= 1);
        assert!(built["sources"].as_array().unwrap().iter().any(|s| s["source_asset"] == "/Game/FloorTarget.FloorTarget" && s["source_sha256"] == hex_sha256(&lod_file)));
        assert!(built["sources"].as_array().unwrap().iter().any(|s| s["source_asset"] == "/Game/FloorCover.FloorCover"));

        let mut truncated: Value = serde_json::from_slice(&fs::read(case.0.join("scan.json")).unwrap()).unwrap();
        truncated["truncated"] = json!(true);
        fs::write(case.0.join("scan.json"), serde_json::to_vec(&truncated).unwrap()).unwrap();
        let err = plan(&case).unwrap_err();
        assert!(err.contains("truncated"), "{err}");
        truncated["truncated"] = json!(false);
        truncated["metadata_sha256"] = json!("deadbeef");
        fs::write(case.0.join("scan.json"), serde_json::to_vec(&truncated).unwrap()).unwrap();
        let err = plan(&case).unwrap_err();
        assert!(err.contains("metadata_sha256"), "{err}");
        truncated["metadata_sha256"] = json!(hex_sha256(&scene_bytes));
        truncated["candidate_conflicts"] = json!(1);
        fs::write(case.0.join("scan.json"), serde_json::to_vec(&truncated).unwrap()).unwrap();
        let err = plan(&case).unwrap_err();
        assert!(err.contains("not all rows"), "{err}");

        let fresh = prepare(
            "stale",
            &insts[..2],
            &[scan_row(&insts, 0, 0, 0, 100, true, 1, 0, 200, false, 1.0, 1.0)],
        );
        let mut bad_row = scan_row(&insts, 0, 0, 0, 100, true, 1, 0, 200, false, 1.0, 1.0);
        bad_row["a_actor"] = json!("SomeoneElse");
        let mut bytes = Vec::new();
        serde_json::to_writer(&mut bytes, &bad_row).unwrap();
        bytes.push(b'\n');
        fs::write(fresh.0.join("scan.conflicts.jsonl"), &bytes).unwrap();
        let err = plan(&fresh).unwrap_err();
        assert!(err.contains("stale"), "{err}");

        let ledger_case = prepare(
            "ledger",
            &insts[..2],
            &[scan_row(&insts, 0, 0, 0, 100, true, 1, 0, 200, false, 1.0, 1.0)],
        );
        let mut ledger: Value = serde_json::from_slice(&fs::read(ledger_case.0.join("facing-install.json")).unwrap()).unwrap();
        ledger["components"][0]["mesh_after"] = json!("/Game/Nope.Nope");
        fs::write(ledger_case.0.join("facing-install.json"), serde_json::to_vec(&ledger).unwrap()).unwrap();
        let err = plan(&ledger_case).unwrap_err();
        assert!(err.contains("mesh_after"), "{err}");
    }
    #[test]
    fn world_new_component_can_request_a_native_front_slot() {
        let full=right(100.,0.);
        let insts=vec![
            make("Ground","/Game/Ground.Ground",true,eye(),&[0],&[true],&["ground"],vec![tri(full,0,10)],vec![]),
            make("Floor","/Game/Floor.Floor",true,eye(),&[0],&[false],&["floor"],vec![tri(flip(full),0,20)],vec![]),
        ];
        let rows=vec![scan_row(&insts,0,0,0,10,true,1,0,20,false,5000.,0.)];
        let case=prepare("new-ground-front-slot",&insts,&rows);
        fs::write(case.0.join("inventory-baseline.json"),serde_json::to_vec(&json!({"actors":[{"label":"Ground","building_floor":false,"repair_eligible":true},{"label":"Floor","building_floor":true}]})).unwrap()).unwrap();
        fs::write(case.0.join("facing-install.json"),serde_json::to_vec(&json!({"components":[]})).unwrap()).unwrap();
        let p=plan(&case).unwrap();assert!(p["blocked"].as_array().unwrap().is_empty());
        assert_eq!(p["modified_source_triangles"],1);assert!(mesh(&p,"/Game/Ground.Ground")["front_slot_map"].as_array().unwrap().is_empty());
        near(&patches(&p,"/Game/Ground.Ground")[0],"front_only_area_cm2",5000.);
    }

    #[test]
    fn world_ground_gap_front_only_preserves_area_without_relaxing_removal() {
        let full=right(100.,0.);let raised=flip(right(100.,0.1));
        let insts=vec![
            make("G00","/Game/Ground.Ground",true,eye(),&[0],&[true],&["ground"],vec![tri(full,0,10)],vec![]),
            make("Floor","/Game/Floor.Floor",true,eye(),&[0],&[false],&["floor"],vec![tri(raised,0,20)],vec![]),
        ];
        let rows=vec![scan_row(&insts,0,0,0,10,true,1,0,20,false,5000.,0.1)];
        let case=prepare("ground-gap",&insts,&rows);assert_eq!(plan(&case).unwrap()["modified_source_triangles"],0);
        fs::write(case.0.join("inventory-baseline.json"),serde_json::to_vec(&json!({"actors":[{"label":"G00","repair_eligible":true,"front_only_tolerance_cm":0.2},{"label":"Floor","building_floor":true}]})).unwrap()).unwrap();
        let p=plan(&case).unwrap();assert_eq!(p["modified_source_triangles"],1);let patch=&patches(&p,"/Game/Ground.Ground")[0];near(patch,"area_after_cm2",5000.);near(patch,"front_only_area_cm2",5000.);assert_eq!(patch["plane_tolerance_cm"],0.2);assert_eq!(p["remove_distance_tolerance_cm"],0.002);
    }

    #[test]
    fn world_ground_top_replacement_is_opt_in_and_preserves_remaining_area() {
        let full=flip(right(100.,0.));let cover=flip(right(25.,0.1));
        let insts=vec![make("G00","/Game/Ground.Ground",true,eye(),&[0],&[true],&["ground"],vec![tri(full,0,10)],vec![]),make("Floor","/Game/Floor.Floor",true,eye(),&[0],&[false],&["floor"],vec![tri(cover,0,20)],vec![])];
        let rows=vec![scan_row(&insts,0,0,0,10,true,1,0,20,false,312.5,0.1)];let case=prepare("ground-top-replace",&insts,&rows);assert_eq!(plan(&case).unwrap()["modified_source_triangles"],0);
        fs::write(case.0.join("inventory-baseline.json"),serde_json::to_vec(&json!({"actors":[{"label":"G00","repair_eligible":true,"ground_top_replace":true,"front_only_tolerance_cm":0.2},{"label":"Floor","building_floor":true}]})).unwrap()).unwrap();
        let p=plan(&case).unwrap();let x=&patches(&p,"/Game/Ground.Ground")[0];assert_eq!(x["operation"],"ground_top_replace");near(x,"area_before_cm2",5000.);near(x,"area_after_cm2",4687.5);near(x,"removed_area_cm2",312.5);near(x,"front_only_area_cm2",0.);
    }
    #[test]
    fn world_ground_top_can_use_a_different_native_face_in_the_same_component() {
        let insts=vec![make("G00","/Game/Ground.Ground",true,eye(),&[0,0],&[true,false],&["base","grass"],vec![tri(flip(right(100.,0.)),0,10),tri(flip(right(25.,0.1)),1,20)],vec![])];
        let mut row=scan_row(&insts,0,0,0,10,true,0,0,20,false,312.5,0.1);row["b_material_slot"]=json!(1);let rows=vec![row];let case=prepare("ground-local-top",&insts,&rows);
        fs::write(case.0.join("inventory-baseline.json"),serde_json::to_vec(&json!({"actors":[{"label":"G00","repair_eligible":true,"ground_top_replace":true,"front_only_tolerance_cm":0.2}]})).unwrap()).unwrap();
        let p=plan(&case).unwrap();assert_eq!(p["modified_source_triangles"],1);assert_eq!(patches(&p,"/Game/Ground.Ground")[0]["operation"],"ground_top_replace");
    }

    #[test]
    fn world_ground_tolerance_is_checked_on_overlap_not_distant_vertices() {
        let target=flip(right(20000.,0.));let cover=[[200.,200.,0.1],[300.,200.,0.101],[200.,300.,0.1]];
        let insts=vec![make("G00","/Game/Ground.Ground",true,eye(),&[0],&[true],&["ground"],vec![tri(target,0,10)],vec![]),make("Floor","/Game/Floor.Floor",true,eye(),&[0],&[false],&["floor"],vec![tri(cover,0,20)],vec![])];
        let rows=vec![scan_row(&insts,0,0,0,10,true,1,0,20,false,5000.,0.1)];let case=prepare("ground-local-tolerance",&insts,&rows);
        fs::write(case.0.join("inventory-baseline.json"),serde_json::to_vec(&json!({"actors":[{"label":"G00","repair_eligible":true,"front_only_tolerance_cm":0.2},{"label":"Floor","building_floor":true}]})).unwrap()).unwrap();
        let p=plan(&case).unwrap();assert_eq!(p["modified_source_triangles"],1);near(&patches(&p,"/Game/Ground.Ground")[0],"front_only_area_cm2",5000.);
    }

    #[test]
    fn world_immutable_street_covers_never_become_targets() {
        let insts=vec![make("FixedStreet","/Game/Street.Street",true,eye(),&[0],&[false],&["street"],vec![tri(right(100.,0.),0,10)],vec![]),make("Detail","/Game/Detail.Detail",true,eye(),&[0],&[false],&["detail"],vec![tri(right(25.,0.),0,20)],vec![])];
        let rows=vec![scan_row(&insts,0,0,0,10,false,1,0,20,false,312.5,0.)];let case=prepare("immutable-street",&insts,&rows);
        fs::write(case.0.join("inventory-baseline.json"),serde_json::to_vec(&json!({"actors":[{"label":"FixedStreet","repair_eligible":true,"cover_only":true},{"label":"Detail","building_floor":true}]})).unwrap()).unwrap();
        let p=plan(&case).unwrap();assert_eq!(p["modified_source_triangles"],0);assert_eq!(excl(&p,"immutable_cover_target"),1);
    }

    fn cover_named<'a>(plan: &'a Value, asset: &str, triangle: i64) -> &'a Value {
        plan["covers"].as_array().unwrap().iter().find(|c| c["source_asset"] == asset && c["triangle"] == triangle).unwrap()
    }

    #[test]
    fn world_same_facing_two_sided_union_is_acyclic() {
        let small = right(10.0, 0.0);
        let large = right(20.0, 0.0);
        let insts = vec![
            make("A", "/Game/A.A", true, eye(), &[0], &[true], &["MI_A"], vec![tri(small, 0, 11)], vec![]),
            make("B", "/Game/B.B", true, eye(), &[0], &[true], &["MI_B"], vec![tri(small, 0, 2)], vec![]),
            make("D", "/Game/D.D", true, eye(), &[0], &[true], &["MI_D"], vec![tri(large, 0, 30)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 11, true, 1, 0, 2, true, 0.0, 50.0),
            scan_row(&insts, 0, 0, 0, 11, true, 2, 0, 30, true, 0.0, 50.0),
            scan_row(&insts, 0, 1, 0, 2, true, 2, 0, 30, true, 0.0, 50.0),
        ];
        let plan = plan(&prepare("two-union", &insts, &rows)).unwrap();
        assert!(plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] != "/Game/A.A"));
        let b = &patches(&plan, "/Game/B.B")[0];
        assert_eq!(b["operation"], "remove_duplicate_two_sided");
        assert_eq!(b["plane_tolerance_cm"], 0.002);
        near(b, "area_before_cm2", 50.0);
        near(b, "removed_area_cm2", 50.0);
        near(b, "area_after_cm2", 0.0);
        assert_eq!(b["front_only_area_cm2"], 0.0);
        assert!(b["removed_pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        let d = &patches(&plan, "/Game/D.D")[0];
        assert_eq!(d["operation"], "remove_duplicate_two_sided");
        near(d, "area_before_cm2", 200.0);
        near(d, "removed_area_cm2", 50.0);
        near(d, "area_after_cm2", 150.0);
        assert!(d["pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        assert!(d["removed_area_cm2"].as_f64().unwrap() < 80.0, "two-sided union was double counted");
        let winner = cover_named(&plan, "/Game/A.A", 11);
        assert_eq!(winner["original_two_sided"], true);
        assert_eq!(winner["material"], "MI_A");
        assert_eq!(d["cover_ids"].as_array().unwrap().len(), 2);
        let retained = 50.0 + b["area_after_cm2"].as_f64().unwrap() + d["area_after_cm2"].as_f64().unwrap();
        assert!((retained - 200.0).abs() < 0.05, "two-sided world union changed: {retained}");
        assert_eq!(excl(&plan, "same_facing_two_sided"), 0);
        assert_eq!(excl(&plan, "same_facing_mixed"), 0);
    }

    #[test]
    fn world_opposite_two_sided_full_pair_keeps_forward_material() {
        let full = right(100.0, 0.0);
        let insts = vec![
            make("SideA", "/Game/SideA.SideA", true, eye(), &[0, 0], &[true, false], &["MatA", "MI_A"], vec![tri(full, 0, 1)], vec![(0, 1)]),
            make("SideB", "/Game/SideB.SideB", true, eye(), &[0, 0], &[true, false], &["MatB", "MI_B"], vec![tri(flip(full), 0, 2)], vec![(0, 1)]),
        ];
        let plan = plan(&prepare("pair-full", &insts, &[scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 2, true, 0.0, 5000.0)])).unwrap();
        assert_eq!(plan["modified_source_triangles"], 2);
        for (asset, material, child) in [("/Game/SideA.SideA", "MatA", "MI_A"), ("/Game/SideB.SideB", "MatB", "MI_B")] {
            let mesh = mesh(&plan, asset);
            assert_eq!(mesh["materials"][0], material);
            assert_eq!(mesh["materials"][1], child);
            assert_eq!(mesh["front_slot_map"], json!([{"source_slot": 0, "existing_slot": 1}]));
            let patch = &patches(&plan, asset)[0];
            assert_eq!(patch["operation"], "paired_front_only");
            assert_eq!(patch["material_slot"], 0);
            assert_eq!(patch["plane_tolerance_cm"], 0.002);
            near(patch, "area_before_cm2", 5000.0);
            near(patch, "area_after_cm2", 5000.0);
            near(patch, "front_only_area_cm2", 5000.0);
            assert_eq!(patch["removed_area_cm2"], 0.0);
            assert!(patch["pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == true));
            assert!(patch["removed_pieces"].as_array().unwrap().is_empty());
        }
        let a = cover_named(&plan, "/Game/SideA.SideA", 1);
        let b = cover_named(&plan, "/Game/SideB.SideB", 2);
        assert_eq!(a["original_two_sided"], true);
        assert_eq!(b["original_two_sided"], true);
        assert_eq!(a["material"], "MatA");
        assert_eq!(b["material"], "MatB");
        assert_eq!(patches(&plan, "/Game/SideA.SideA")[0]["cover_ids"][0], b["id"]);
        assert_eq!(patches(&plan, "/Game/SideB.SideB")[0]["cover_ids"][0], a["id"]);
    }

    #[test]
    fn world_opposite_two_sided_partial_pair_converts_only_intersection() {
        let full = right(100.0, 0.0);
        let part = flip([[0.0, 0.0, 0.0], [40.0, 0.0, 0.0], [0.0, 40.0, 0.0]]);
        let insts = vec![
            make("Large", "/Game/Large.Large", true, eye(), &[0], &[true], &["LargeMat"], vec![tri(full, 0, 7)], vec![]),
            make("Small", "/Game/Small.Small", true, eye(), &[0], &[true], &["SmallMat"], vec![tri(part, 0, 8)], vec![]),
        ];
        let plan = plan(&prepare("pair-part", &insts, &[scan_row(&insts, 0, 0, 0, 7, true, 1, 0, 8, true, 0.0, 800.0)])).unwrap();
        assert_eq!(plan["modified_source_triangles"], 2);
        let large = &patches(&plan, "/Game/Large.Large")[0];
        let small = &patches(&plan, "/Game/Small.Small")[0];
        assert_eq!(large["operation"], "paired_front_only");
        assert_eq!(small["operation"], "paired_front_only");
        near(large, "front_only_area_cm2", 800.0);
        near(small, "front_only_area_cm2", 800.0);
        near(large, "area_before_cm2", 5000.0);
        near(large, "area_after_cm2", 5000.0);
        near(small, "area_before_cm2", 800.0);
        near(small, "area_after_cm2", 800.0);
        assert_eq!(large["removed_area_cm2"], 0.0);
        assert_eq!(small["removed_area_cm2"], 0.0);
        assert!(large["pieces"].as_array().unwrap().iter().any(|p| p["front_only"] == true));
        assert!(large["pieces"].as_array().unwrap().iter().any(|p| p["front_only"] == false));
        assert!(small["pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == true));
        assert!(mesh(&plan, "/Game/Large.Large")["front_slot_map"].as_array().unwrap().is_empty());
        assert_eq!(mesh(&plan, "/Game/Large.Large")["materials"][0], "LargeMat");
        assert_eq!(mesh(&plan, "/Game/Small.Small")["materials"][0], "SmallMat");
        assert_eq!(large["cover_ids"][0], cover_named(&plan, "/Game/Small.Small", 8)["id"]);
        assert_eq!(small["cover_ids"][0], cover_named(&plan, "/Game/Large.Large", 7)["id"]);
    }

    #[test]
    fn world_same_component_distinct_triangles_are_explicit_targets() {
        let insts = vec![
            make("Same", "/Game/Same.Same", true, eye(), &[0], &[true], &["Sheet"], vec![
                tri(right(10.0, 0.0), 0, 1),
                tri(right(10.0, 0.0), 0, 2),
            ], vec![]),
            make("Pair", "/Game/Pair.Pair", true, eye(), &[0], &[true], &["PairMat"], vec![
                tri(right(20.0, 50.0), 0, 3),
                tri(flip(right(20.0, 50.0)), 0, 4),
            ], vec![]),
        ];
        let mut self_row = scan_row(&insts, 0, 0, 0, 1, true, 0, 0, 1, true, 0.0, 50.0);
        self_row["b_triangle"] = json!(1);
        let rows = vec![
            self_row,
            scan_row(&insts, 0, 0, 0, 1, true, 0, 0, 2, true, 0.0, 50.0),
            scan_row(&insts, 0, 1, 0, 3, true, 1, 0, 4, true, 0.0, 200.0),
        ];
        let plan = plan(&prepare("same-component", &insts, &rows)).unwrap();
        assert!(excl(&plan, "same_instance") >= 1);
        assert_eq!(plan["modified_source_triangles"], 3);
        let removed = &patches(&plan, "/Game/Same.Same")[0];
        assert_eq!(removed["operation"], "remove_duplicate_two_sided");
        assert_eq!(removed["triangle"], 2);
        let same_cover = cover_named(&plan, "/Game/Same.Same", 1);
        assert_eq!(removed["cover_ids"][0], same_cover["id"]);
        assert_eq!(same_cover["component_key"], "Same::StaticMesh");
        assert_eq!(same_cover["original_two_sided"], true);
        assert_ne!(same_cover["triangle"], removed["triangle"]);
        let pair = patches(&plan, "/Game/Pair.Pair");
        assert_eq!(pair.len(), 2);
        assert!(pair.iter().all(|p| p["operation"] == "paired_front_only"));
        let by_tri = |id: i64| pair.iter().find(|p| p["triangle"] == id).unwrap();
        assert_eq!(by_tri(3)["cover_ids"][0], cover_named(&plan, "/Game/Pair.Pair", 4)["id"]);
        assert_eq!(by_tri(4)["cover_ids"][0], cover_named(&plan, "/Game/Pair.Pair", 3)["id"]);
        for patch in pair {
            let cover_id = patch["cover_ids"][0].as_u64().unwrap();
            let cover = plan["covers"].as_array().unwrap().iter().find(|c| c["id"].as_u64() == Some(cover_id)).unwrap();
            assert_eq!(cover["component_key"], "Pair::StaticMesh");
            assert_ne!(cover["triangle"], patch["triangle"]);
        }
    }

    #[test]
    fn world_unpaired_and_ambiguous_two_sided_are_deferred() {
        let insts = vec![
            make("Winner", "/Game/Winner.Winner", true, eye(), &[0], &[true], &["W"], vec![tri(right(20.0, 0.0), 0, 1)], vec![]),
            make("Mixed", "/Game/Mixed.Mixed", true, eye(), &[0], &[true], &["M"], vec![tri(right(100.0, 0.0), 0, 2)], vec![]),
            make("Opposite", "/Game/Opposite.Opposite", true, eye(), &[0], &[true], &["O"], vec![tri(flip([[50.0, 0.0, 0.0], [70.0, 0.0, 0.0], [50.0, 20.0, 0.0]]), 0, 3)], vec![]),
            make("Fixed", "/Game/Fixed.Fixed", true, eye(), &[0], &[true], &["F"], vec![tri(flip(right(30.0, 400.0)), 0, 4)], vec![]),
            make("Loose", "/Game/Loose.Loose", true, eye(), &[0], &[true], &["L"], vec![tri(right(30.0, 400.0), 0, 5)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 2, true, 0.0, 200.0),
            scan_row(&insts, 0, 1, 0, 2, true, 2, 0, 3, true, 0.0, 200.0),
            scan_row(&insts, 0, 3, 0, 4, true, 4, 0, 5, true, 0.0, 450.0),
        ];
        let case = prepare("defer-two-sided", &insts, &rows);
        fs::write(case.0.join("inventory-baseline.json"), serde_json::to_vec(&json!({"actors": [
            {"label": "Winner", "building_floor": true},
            {"label": "Mixed", "building_floor": true},
            {"label": "Opposite", "building_floor": true},
            {"label": "Fixed", "building_floor": true, "cover_only": true},
            {"label": "Loose", "building_floor": true}
        ]})).unwrap()).unwrap();
        let plan = plan(&case).unwrap();
        assert_eq!(plan["modified_source_triangles"], 0);
        assert!(plan["meshes"].as_array().unwrap().is_empty());
        assert!(excl(&plan, "ambiguous_two_sided_combination") >= 1);
        assert!(excl(&plan, "deferred_unpaired_two_sided") >= 1);
        assert!(excl(&plan, "immutable_cover_target") >= 1);
        assert_eq!(excl(&plan, "same_facing_mixed"), 0);
    }

    #[test]
    fn world_masked_two_sided_and_immutable_targets_stay_excluded() {
        let sheet = right(40.0, 0.0);
        let insts = vec![
            make("Opaque", "/Game/Opaque.Opaque", true, eye(), &[0], &[true], &["O"], vec![tri(sheet, 0, 1)], vec![]),
            make("Masked", "/Game/Masked.Masked", true, eye(), &[1], &[true], &["mask"], vec![tri(flip(sheet), 0, 2)], vec![]),
            make("Street", "/Game/Street.Street", true, eye(), &[0], &[true], &["street"], vec![tri(right(100.0, 800.0), 0, 3)], vec![]),
            make("Detail", "/Game/Detail.Detail", true, eye(), &[0], &[true], &["detail"], vec![tri(right(20.0, 800.0), 0, 4)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 2, true, 0.0, 800.0),
            scan_row(&insts, 0, 2, 0, 3, true, 3, 0, 4, true, 0.0, 200.0),
        ];
        let case = prepare("masked-immutable-two", &insts, &rows);
        fs::write(case.0.join("inventory-baseline.json"), serde_json::to_vec(&json!({"actors": [
            {"label": "Opaque", "building_floor": true},
            {"label": "Masked", "building_floor": true},
            {"label": "Street", "building_floor": true, "cover_only": true},
            {"label": "Detail", "building_floor": true}
        ]})).unwrap()).unwrap();
        let plan = plan(&case).unwrap();
        assert_eq!(excl(&plan, "masked_or_translucent"), 1);
        assert_eq!(excl(&plan, "immutable_cover_target"), 1);
        assert_eq!(plan["modified_source_triangles"], 0);
        assert!(plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] != "/Game/Street.Street"));
    }

    #[test]
    fn world_two_sided_exact_plane_does_not_use_ground_gap() {
        let insts = vec![
            make("G00", "/Game/Ground.Ground", true, eye(), &[0], &[true], &["ground"], vec![tri(right(100.0, 0.0), 0, 10)], vec![]),
            make("Floor", "/Game/Floor.Floor", true, eye(), &[0], &[true], &["floor"], vec![tri(flip(right(100.0, 0.1)), 0, 20)], vec![]),
        ];
        let case = prepare("two-sided-gap", &insts, &[scan_row(&insts, 0, 0, 0, 10, true, 1, 0, 20, true, 5000.0, 0.1)]);
        fs::write(case.0.join("inventory-baseline.json"), serde_json::to_vec(&json!({"actors": [
            {"label": "G00", "repair_eligible": true, "front_only_tolerance_cm": 0.2},
            {"label": "Floor", "building_floor": true, "front_only_tolerance_cm": 0.2}
        ]})).unwrap()).unwrap();
        let plan = plan(&case).unwrap();
        assert_eq!(plan["modified_source_triangles"], 0);
        assert!(plan["meshes"].as_array().unwrap().is_empty());
        assert_eq!(plan["remove_distance_tolerance_cm"], 0.002);
    }

    fn set_selector(case: &Case, mixed: bool, prefer: bool) {
        let mut inv: Value =
            serde_json::from_slice(&fs::read(case.0.join("inventory-baseline.json")).unwrap()).unwrap();
        inv["enable_mixed_same_facing"] = json!(mixed);
        inv["prefer_same_facing_pass"] = json!(prefer);
        fs::write(
            case.0.join("inventory-baseline.json"),
            serde_json::to_vec(&inv).unwrap(),
        )
        .unwrap();
    }

    fn operations(plan: &Value) -> Vec<String> {
        let mut out = Vec::new();
        for mesh in plan["meshes"].as_array().unwrap() {
            for lod in mesh["lods"].as_array().unwrap() {
                for patch in lod["patches"].as_array().unwrap() {
                    out.push(patch["operation"].as_str().unwrap().to_string());
                }
            }
        }
        out
    }

    fn write_actors(case: &Case, actors: Value) {
        fs::write(
            case.0.join("inventory-baseline.json"),
            serde_json::to_vec(&json!({"actors": actors})).unwrap(),
        )
        .unwrap();
    }

    #[test]
    fn world_two_sided_terrain_cover_allows_either_normal_at_one_millimetre() {
        let terrain = flip(right(100.0, 0.0));
        let opposite = right(25.0, 0.1);
        let opposite_insts = vec![
            make("World_PK_0109", "/Game/Terrain.Terrain", true, eye(), &[0], &[true], &["ground"], vec![tri(terrain, 0, 10)], vec![]),
            make("ImmutableFloor", "/Game/Floor.Floor", true, eye(), &[0], &[true], &["floor"], vec![tri(opposite, 0, 20)], vec![]),
        ];
        let opposite_case = prepare(
            "terrain-opposite-two",
            &opposite_insts,
            &[scan_row(&opposite_insts, 0, 0, 0, 10, true, 1, 0, 20, true, 0.1, 312.5)],
        );
        write_actors(&opposite_case, json!([
            {"label": "World_PK_0109", "repair_eligible": true, "ground_top_replace": true, "front_only_tolerance_cm": 0.2},
            {"label": "ImmutableFloor", "repair_eligible": true, "cover_only": true}
        ]));
        let opposite_plan = plan(&opposite_case).unwrap();
        assert_eq!(opposite_plan["modified_source_triangles"], 1);
        assert_eq!(opposite_plan["remove_distance_tolerance_cm"], 0.002);
        let opposite_patch = &patches(&opposite_plan, "/Game/Terrain.Terrain")[0];
        assert_eq!(opposite_patch["operation"], "ground_top_replace");
        assert_eq!(opposite_patch["plane_tolerance_cm"], 0.2);
        near(opposite_patch, "area_before_cm2", 5000.0);
        near(opposite_patch, "area_after_cm2", 4687.5);
        near(opposite_patch, "removed_area_cm2", 312.5);
        assert_eq!(opposite_patch["front_only_area_cm2"], 0.0);
        assert!(opposite_patch["pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        assert!(opposite_patch["removed_pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        let opposite_cover = cover_named(&opposite_plan, "/Game/Floor.Floor", 20);
        assert_eq!(opposite_cover["original_two_sided"], true);
        assert_eq!(opposite_patch["cover_ids"][0], opposite_cover["id"]);
        assert!(opposite_plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] == "/Game/Terrain.Terrain"));

        // A terrain actor can be retained as an immutable cover in a later
        // floor/exterior pass. Its old terrain opt-in must not make it mutable.
        write_actors(&opposite_case, json!([
            {"label": "World_PK_0109", "repair_eligible": true, "cover_only": true, "ground_top_replace": true, "front_only_tolerance_cm": 0.2},
            {"label": "ImmutableFloor", "repair_eligible": true, "cover_only": true}
        ]));
        let immutable_plan = plan(&opposite_case).unwrap();
        assert!(immutable_plan["meshes"].as_array().unwrap().is_empty());

        let matching = flip(right(25.0, 0.1));
        let matching_insts = vec![
            make("G00", "/Game/Ground.Ground", true, eye(), &[0], &[true], &["ground"], vec![tri(terrain, 0, 10)], vec![]),
            make("Floor", "/Game/MatchFloor.MatchFloor", true, eye(), &[0], &[true], &["floor"], vec![tri(matching, 0, 21)], vec![]),
        ];
        let matching_case = prepare(
            "terrain-matching-two",
            &matching_insts,
            &[scan_row(&matching_insts, 0, 0, 0, 10, true, 1, 0, 21, true, 0.1, 312.5)],
        );
        write_actors(&matching_case, json!([
            {"label": "G00", "repair_eligible": true, "ground_top_replace": true, "front_only_tolerance_cm": 0.2},
            {"label": "Floor", "building_floor": true}
        ]));
        let matching_plan = plan(&matching_case).unwrap();
        let matching_patch = &patches(&matching_plan, "/Game/Ground.Ground")[0];
        assert_eq!(matching_patch["operation"], "ground_top_replace");
        assert_eq!(matching_patch["plane_tolerance_cm"], 0.2);
        near(matching_patch, "removed_area_cm2", 312.5);
        near(matching_patch, "area_after_cm2", 4687.5);
        assert_eq!(cover_named(&matching_plan, "/Game/MatchFloor.MatchFloor", 21)["original_two_sided"], true);
        assert!(matching_plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] == "/Game/Ground.Ground"));
    }

    #[test]
    fn world_two_sided_terrain_cover_rejects_ordinary_floor_and_non_upward() {
        let raised = right(25.0, 0.1);
        let ordinary = vec![
            make("FloorA", "/Game/FloorA.FloorA", true, eye(), &[0], &[true], &["a"], vec![tri(flip(right(100.0, 0.0)), 0, 1)], vec![]),
            make("FloorB", "/Game/FloorB.FloorB", true, eye(), &[0], &[true], &["b"], vec![tri(raised, 0, 2)], vec![]),
        ];
        let ordinary_case = prepare(
            "ordinary-two-gap",
            &ordinary,
            &[scan_row(&ordinary, 0, 0, 0, 1, true, 1, 0, 2, true, 0.1, 312.5)],
        );
        write_actors(&ordinary_case, json!([
            {"label": "FloorA", "building_floor": true, "front_only_tolerance_cm": 0.2},
            {"label": "FloorB", "building_floor": true, "front_only_tolerance_cm": 0.2}
        ]));
        let ordinary_plan = plan(&ordinary_case).unwrap();
        assert_eq!(ordinary_plan["modified_source_triangles"], 0);
        assert!(!operations(&ordinary_plan).iter().any(|op| op == "ground_top_replace"));

        let non_up = vec![
            make("World_PK_0109", "/Game/Terrain.Terrain", true, eye(), &[0], &[true], &["ground"], vec![tri(right(100.0, 0.0), 0, 3)], vec![]),
            make("Floor", "/Game/Floor.Floor", true, eye(), &[0], &[true], &["floor"], vec![tri(flip(raised), 0, 4)], vec![]),
        ];
        let non_up_case = prepare(
            "non-upward-terrain",
            &non_up,
            &[scan_row(&non_up, 0, 0, 0, 3, true, 1, 0, 4, true, 0.1, 312.5)],
        );
        write_actors(&non_up_case, json!([
            {"label": "World_PK_0109", "repair_eligible": true, "ground_top_replace": true, "front_only_tolerance_cm": 0.2},
            {"label": "Floor", "building_floor": true}
        ]));
        let non_up_plan = plan(&non_up_case).unwrap();
        assert_eq!(non_up_plan["modified_source_triangles"], 0);
        assert!(non_up_plan["meshes"].as_array().unwrap().is_empty());

        let loose = vec![
            make("World_PK_0109", "/Game/Terrain.Terrain", true, eye(), &[0], &[true], &["ground"], vec![tri(flip(right(100.0, 0.0)), 0, 5)], vec![]),
            make("Other", "/Game/Other.Other", true, eye(), &[0], &[true], &["other"], vec![tri(raised, 0, 6)], vec![]),
        ];
        let loose_case = prepare(
            "terrain-cover-not-floor",
            &loose,
            &[scan_row(&loose, 0, 0, 0, 5, true, 1, 0, 6, true, 0.1, 312.5)],
        );
        write_actors(&loose_case, json!([
            {"label": "World_PK_0109", "repair_eligible": true, "ground_top_replace": true, "front_only_tolerance_cm": 0.2},
            {"label": "Other", "repair_eligible": true}
        ]));
        let loose_plan = plan(&loose_case).unwrap();
        assert_eq!(loose_plan["modified_source_triangles"], 0);
        assert!(!operations(&loose_plan).iter().any(|op| op == "ground_top_replace"));
    }

    #[test]
    fn world_mixed_same_facing_removes_one_sided_only_when_enabled() {
        let sheet = right(100.0, 0.0);
        let insts = vec![
            make("Target", "/Game/Target.Target", true, eye(), &[0], &[false], &["one"], vec![tri(sheet, 0, 1)], vec![]),
            make("Cover", "/Game/Cover.Cover", true, eye(), &[0], &[true], &["two"], vec![tri(sheet, 0, 2)], vec![]),
        ];
        let rows = vec![scan_row(&insts, 0, 0, 0, 1, false, 1, 0, 2, true, 0.0, 5000.0)];
        let case = prepare("mixed-full", &insts, &rows);
        let off = plan(&case).unwrap();
        assert_eq!(excl(&off, "same_facing_mixed"), 1);
        assert_eq!(off["modified_source_triangles"], 0);
        assert!(!operations(&off).iter().any(|op| op == "remove_one_sided_duplicate"));

        set_selector(&case, true, false);
        let on = plan(&case).unwrap();
        assert_eq!(excl(&on, "same_facing_mixed"), 0);
        assert_eq!(on["modified_source_triangles"], 1);
        let patch = &patches(&on, "/Game/Target.Target")[0];
        assert_eq!(patch["operation"], "remove_one_sided_duplicate");
        assert_eq!(patch["plane_tolerance_cm"], 0.002);
        near(patch, "area_before_cm2", 5000.0);
        near(patch, "removed_area_cm2", 5000.0);
        near(patch, "area_after_cm2", 0.0);
        assert_eq!(patch["front_only_area_cm2"], 0.0);
        assert!(patch["removed_pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        assert_eq!(cover_named(&on, "/Game/Cover.Cover", 2)["original_two_sided"], true);
        assert!(on["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] == "/Game/Target.Target"));

        let partial_insts = vec![
            make("Target", "/Game/Target.Target", true, eye(), &[0], &[false], &["one"], vec![tri(sheet, 0, 3)], vec![]),
            make("Cover", "/Game/Cover.Cover", true, eye(), &[0], &[true], &["two"], vec![tri(right(25.0, 0.0), 0, 4)], vec![]),
        ];
        let partial = prepare(
            "mixed-partial",
            &partial_insts,
            &[scan_row(&partial_insts, 0, 0, 0, 3, false, 1, 0, 4, true, 0.0, 312.5)],
        );
        write_actors(&partial, json!([
            {"label": "Target", "building_floor": true, "front_only_tolerance_cm": 0.2},
            {"label": "Cover", "building_floor": true, "front_only_tolerance_cm": 0.2}
        ]));
        set_selector(&partial, true, false);
        let partial_plan = plan(&partial).unwrap();
        let partial_patch = &patches(&partial_plan, "/Game/Target.Target")[0];
        assert_eq!(partial_patch["operation"], "remove_one_sided_duplicate");
        assert_eq!(partial_patch["plane_tolerance_cm"], 0.002);
        near(partial_patch, "removed_area_cm2", 312.5);
        near(partial_patch, "area_after_cm2", 4687.5);
        assert!(partial_patch["pieces"].as_array().unwrap().iter().all(|p| p["front_only"] == false));
        assert!(!partial_patch["removed_pieces"].as_array().unwrap().is_empty());

        let gapped = vec![
            make("Target", "/Game/Target.Target", true, eye(), &[0], &[false], &["one"], vec![tri(sheet, 0, 5)], vec![]),
            make("Cover", "/Game/Cover.Cover", true, eye(), &[0], &[true], &["two"], vec![tri(right(25.0, 0.1), 0, 6)], vec![]),
        ];
        let gap_case = prepare(
            "mixed-gap",
            &gapped,
            &[scan_row(&gapped, 0, 0, 0, 5, false, 1, 0, 6, true, 0.1, 312.5)],
        );
        write_actors(&gap_case, json!([
            {"label": "Target", "building_floor": true, "front_only_tolerance_cm": 0.2},
            {"label": "Cover", "building_floor": true}
        ]));
        set_selector(&gap_case, true, false);
        let gap_plan = plan(&gap_case).unwrap();
        assert_eq!(gap_plan["modified_source_triangles"], 0);
        assert!(!operations(&gap_plan).iter().any(|op| op == "remove_one_sided_duplicate"));
    }

    #[test]
    fn world_mixed_same_component_and_combined_one_sided_covers() {
        let insts = vec![make(
            "Sheet",
            "/Game/Sheet.Sheet",
            true,
            eye(),
            &[0, 0],
            &[false, true],
            &["one", "two"],
            vec![tri(right(100.0, 0.0), 0, 10), tri(right(25.0, 0.0), 1, 20)],
            vec![],
        )];
        let rows = vec![scan_row(&insts, 0, 0, 0, 10, false, 0, 1, 20, true, 0.0, 312.5)];
        let case = prepare("mixed-same-component", &insts, &rows);
        set_selector(&case, true, false);
        let same_plan = plan(&case).unwrap();
        assert_eq!(same_plan["modified_source_triangles"], 1);
        let patch = &patches(&same_plan, "/Game/Sheet.Sheet")[0];
        assert_eq!(patch["operation"], "remove_one_sided_duplicate");
        assert_eq!(patch["triangle"], 10);
        assert_eq!(patch["plane_tolerance_cm"], 0.002);
        near(patch, "removed_area_cm2", 312.5);
        let cover = cover_named(&same_plan, "/Game/Sheet.Sheet", 20);
        assert_eq!(patch["cover_ids"][0], cover["id"]);
        assert_eq!(cover["component_key"], "Sheet::StaticMesh");
        assert_ne!(cover["triangle"], patch["triangle"]);
        assert_eq!(cover["original_two_sided"], true);

        let corner = [[75.0, 0.0, 0.0], [100.0, 0.0, 0.0], [75.0, 25.0, 0.0]];
        let union_insts = vec![
            make("Large", "/Game/Large.Large", true, eye(), &[0], &[false], &["large"], vec![tri(right(100.0, 0.0), 0, 1)], vec![]),
            make("SmallOne", "/Game/SmallOne.SmallOne", true, eye(), &[0], &[false], &["one"], vec![tri(right(25.0, 0.0), 0, 2)], vec![]),
            make("SmallTwo", "/Game/SmallTwo.SmallTwo", true, eye(), &[0], &[true], &["two"], vec![tri(corner, 0, 3)], vec![]),
        ];
        let union_rows = vec![
            scan_row(&union_insts, 0, 0, 0, 1, false, 1, 0, 2, false, 0.0, 312.5),
            scan_row(&union_insts, 0, 0, 0, 1, false, 2, 0, 3, true, 0.0, 312.5),
        ];
        let union_case = prepare("mixed-union", &union_insts, &union_rows);
        let union_off = plan(&union_case).unwrap();
        assert_eq!(excl(&union_off, "same_facing_mixed"), 1);
        assert_eq!(operations(&union_off), vec!["remove".to_string()]);
        near(&patches(&union_off, "/Game/Large.Large")[0], "removed_area_cm2", 312.5);
        assert!(cover_named(&union_off, "/Game/SmallOne.SmallOne", 2).get("original_two_sided").is_none());

        set_selector(&union_case, true, false);
        let union_on = plan(&union_case).unwrap();
        assert_eq!(union_on["modified_source_triangles"], 1);
        assert_eq!(operations(&union_on), vec!["remove_one_sided_duplicate".to_string()]);
        let union_patch = &patches(&union_on, "/Game/Large.Large")[0];
        assert_eq!(union_patch["plane_tolerance_cm"], 0.002);
        near(union_patch, "removed_area_cm2", 625.0);
        near(union_patch, "area_after_cm2", 4375.0);
        assert_eq!(union_patch["cover_ids"].as_array().unwrap().len(), 2);
        assert_eq!(cover_named(&union_on, "/Game/SmallTwo.SmallTwo", 3)["original_two_sided"], true);
        assert!(cover_named(&union_on, "/Game/SmallOne.SmallOne", 2).get("original_two_sided").is_none());
        assert!(union_on["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] == "/Game/Large.Large"));
    }

    #[test]
    fn world_mixed_immutable_and_masked_stay_excluded() {
        let far = [[500.0, 0.0, 0.0], [600.0, 0.0, 0.0], [500.0, 100.0, 0.0]];
        let insts = vec![
            make("FixedStreet", "/Game/Street.Street", true, eye(), &[0], &[false], &["street"], vec![tri(right(100.0, 0.0), 0, 1)], vec![]),
            make("StreetCover", "/Game/StreetCover.StreetCover", true, eye(), &[0], &[true], &["cover"], vec![tri(right(100.0, 0.0), 0, 2)], vec![]),
            make("Masked", "/Game/Masked.Masked", true, eye(), &[1], &[false], &["mask"], vec![tri(far, 0, 3)], vec![]),
            make("MaskCover", "/Game/MaskCover.MaskCover", true, eye(), &[0], &[true], &["cover"], vec![tri(far, 0, 4)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, false, 1, 0, 2, true, 0.0, 5000.0),
            scan_row(&insts, 0, 2, 0, 3, false, 3, 0, 4, true, 0.0, 5000.0),
        ];
        let case = prepare("mixed-reject", &insts, &rows);
        write_actors(&case, json!([
            {"label": "FixedStreet", "building_floor": true, "cover_only": true},
            {"label": "StreetCover", "building_floor": true},
            {"label": "Masked", "building_floor": true},
            {"label": "MaskCover", "building_floor": true}
        ]));
        set_selector(&case, true, false);
        let plan = plan(&case).unwrap();
        assert_eq!(excl(&plan, "immutable_cover_target"), 1);
        assert_eq!(excl(&plan, "masked_or_translucent"), 1);
        assert_eq!(plan["modified_source_triangles"], 0);
        assert!(plan["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] != "/Game/Street.Street"));
        assert!(!operations(&plan).iter().any(|op| op == "remove_one_sided_duplicate"));
    }

    #[test]
    fn world_prefer_same_facing_pass_emits_duplicate_without_half_pair() {
        let insts = vec![
            make("DupLarge", "/Game/DupLarge.DupLarge", true, eye(), &[0], &[true], &["L"], vec![tri(right(100.0, 0.0), 0, 1)], vec![]),
            make("DupSmall", "/Game/DupSmall.DupSmall", true, eye(), &[0], &[true], &["S"], vec![tri(right(25.0, 0.0), 0, 2)], vec![]),
            make("Pair", "/Game/Pair.Pair", true, eye(), &[0], &[true], &["P"], vec![tri(flip(right(100.0, 0.0)), 0, 3)], vec![]),
            make("FrontCover", "/Game/FrontCover.FrontCover", true, eye(), &[0], &[false], &["F"], vec![tri(flip(right(40.0, 0.0)), 0, 4)], vec![]),
        ];
        let rows = vec![
            scan_row(&insts, 0, 0, 0, 1, true, 1, 0, 2, true, 0.0, 312.5),
            scan_row(&insts, 0, 0, 0, 1, true, 2, 0, 3, true, 0.0, 5000.0),
            scan_row(&insts, 0, 0, 0, 1, true, 3, 0, 4, false, 0.0, 800.0),
        ];
        let case = prepare("prefer-duplicate", &insts, &rows);
        let conservative = plan(&case).unwrap();
        assert_eq!(conservative["modified_source_triangles"], 0);
        assert!(conservative["meshes"].as_array().unwrap().is_empty());
        assert!(excl(&conservative, "ambiguous_two_sided_combination") >= 1);
        assert!(excl(&conservative, "deferred_unpaired_two_sided") >= 1);
        assert_eq!(excl(&conservative, "deferred_same_facing_pass"), 0);
        assert!(!operations(&conservative).iter().any(|op| op == "remove_duplicate_two_sided" || op == "paired_front_only" || op == "front_only"));

        set_selector(&case, false, true);
        let preferred = plan(&case).unwrap();
        assert_eq!(preferred["modified_source_triangles"], 1);
        assert_eq!(operations(&preferred), vec!["remove_duplicate_two_sided".to_string()]);
        let patch = &patches(&preferred, "/Game/DupLarge.DupLarge")[0];
        assert_eq!(patch["plane_tolerance_cm"], 0.002);
        near(patch, "removed_area_cm2", 312.5);
        near(patch, "area_after_cm2", 4687.5);
        assert_eq!(patch["front_only_area_cm2"], 0.0);
        assert_eq!(patch["cover_ids"].as_array().unwrap().len(), 1);
        assert_eq!(patch["cover_ids"][0], cover_named(&preferred, "/Game/DupSmall.DupSmall", 2)["id"]);
        assert!(preferred["meshes"].as_array().unwrap().iter().all(|m| m["source_asset"] == "/Game/DupLarge.DupLarge"));
        assert!(preferred["covers"].as_array().unwrap().iter().all(|c| {
            c["source_asset"] != "/Game/Pair.Pair" && c["source_asset"] != "/Game/FrontCover.FrontCover"
        }));
        assert!(excl(&preferred, "deferred_same_facing_pass") >= 1);
        assert!(excl(&preferred, "deferred_unpaired_two_sided") >= 1);
        assert_eq!(excl(&preferred, "ambiguous_two_sided_combination"), 0);
    }

}
