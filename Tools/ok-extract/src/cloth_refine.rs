//! More triangles where a garment becomes PhysX cloth (user, 2026-11-21: "衣服面數不夠時需要自己加面").
//!
//! A low-poly skirt or sleeve folds only at its few edges: Raiden Shogun's maid skirt (776 vertices) and kimono
//! panel (953) bent like cardboard. Before the garment's rig is built, every triangle touching its cloth region is
//! cut until no edge is longer than OK_CLOTH_PX_EDGE (longest edge first, so the triangles stay well shaped). The
//! new vertices are midpoints: position, normal, tangent, UVs, colour, skin weights and morph deltas are the
//! average of the edge's two ends, so the garment looks as before until the cloth moves it.
//!
//! An edge is cut by where its ends sit, not by their indices: a UV seam or the back copy of a double-sided panel
//! has its own vertices at the same places, and cutting only one side left a crack along it. Each side gets its
//! own midpoint (its own UV), at the same place; the cloth welds them into one particle.
use std::collections::HashMap;

use crate::unity::ExtractedMesh;
use crate::vertcolor::Bary;

fn sub(a: [f32; 3], b: [f32; 3]) -> [f32; 3] { [a[0] - b[0], a[1] - b[1], a[2] - b[2]] }
fn len(a: [f32; 3]) -> f32 { (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt() }

/// Cuts the triangles with a selected vertex (and their neighbours across a cut edge) until no selected
/// triangle has an edge longer than `max_edge`, adding at most `max_new` vertices. Returns the vertices added.
pub(crate) fn refine(mesh: &mut ExtractedMesh, selected: &[bool], max_edge: f32, max_new: usize) -> usize {
    let n0 = mesh.weights.len().max(mesh.rest_positions.len()).max(mesh.positions.len());
    if selected.len() != n0 || mesh.indices.len() < 3 || max_edge <= 0. { return 0; }
    let mut tri_sel: Vec<bool> = mesh.indices.chunks_exact(3).map(|t| t.iter().any(|&v| selected.get(v as usize) == Some(&true))).collect();
    let mut added = 0usize;
    for _pass in 0..8 {
        let n = mesh.weights.len().max(mesh.rest_positions.len()).max(mesh.positions.len());
        let pos: &[[f32; 3]] = if mesh.rest_positions.len() == n { &mesh.rest_positions } else { &mesh.positions };
        if pos.len() != n || mesh.indices.iter().any(|&v| v as usize >= n) { break; }
        // Where each vertex sits (0.1 mm): seams and double-sided copies share it.
        let mut at: HashMap<[i32; 3], u32> = HashMap::new();
        let place: Vec<u32> = pos.iter().map(|p| {
            let k = [(p[0] * 1e4).round() as i32, (p[1] * 1e4).round() as i32, (p[2] * 1e4).round() as i32];
            let next = at.len() as u32;
            *at.entry(k).or_insert(next)
        }).collect();
        let key = |a: u32, b: u32| { let (x, y) = (place[a as usize], place[b as usize]); if x < y { (x, y) } else { (y, x) } };
        // Each selected triangle cuts its longest edge when that is too long.
        let mut cut: std::collections::HashSet<(u32, u32)> = std::collections::HashSet::new();
        for (t, tri) in mesh.indices.chunks_exact(3).enumerate() {
            if !tri_sel[t] { continue; }
            let e = [(tri[0], tri[1]), (tri[1], tri[2]), (tri[2], tri[0])];
            let l = e.map(|(a, b)| len(sub(pos[a as usize], pos[b as usize])));
            let k = (0..3).max_by(|x, y| l[*x].total_cmp(&l[*y])).unwrap();
            if l[k] > max_edge && key(e[k].0, e[k].1).0 != key(e[k].0, e[k].1).1 { cut.insert(key(e[k].0, e[k].1)); }
        }
        if cut.is_empty() { break; }
        // One midpoint per cut index edge.
        let mut mid: HashMap<(u32, u32), u32> = HashMap::new();
        let mut bary: Vec<Bary> = (0..n as u32).map(|v| Bary { v: [v, v, v], w: [1., 0., 0.] }).collect();
        for tri in mesh.indices.chunks_exact(3) {
            for k in 0..3 {
                let (a, b) = (tri[k], tri[(k + 1) % 3]);
                if !cut.contains(&key(a, b)) { continue; }
                let ik = if a < b { (a, b) } else { (b, a) };
                if !mid.contains_key(&ik) { mid.insert(ik, bary.len() as u32); bary.push(Bary { v: [ik.0, ik.1, ik.0], w: [0.5, 0.5, 0.] }); }
            }
        }
        if added + mid.len() > max_new { break; }
        let m = |a: u32, b: u32| mid.get(&if a < b { (a, b) } else { (b, a) }).copied();
        let mut indices: Vec<u32> = Vec::with_capacity(mesh.indices.len() * 2);
        let mut sel: Vec<bool> = Vec::with_capacity(tri_sel.len() * 2);
        for (t, tri) in mesh.indices.chunks_exact(3).enumerate() {
            let v = [tri[0], tri[1], tri[2]];
            let ms = [m(v[0], v[1]), m(v[1], v[2]), m(v[2], v[0])];
            let mut push = |a: u32, b: u32, c: u32| { indices.extend_from_slice(&[a, b, c]); sel.push(tri_sel[t]); };
            match ms.iter().filter(|x| x.is_some()).count() {
                0 => push(v[0], v[1], v[2]),
                1 => {
                    // Edge k = (v[k], v[k+1]) cut at mk.
                    let k = (0..3).find(|k| ms[*k].is_some()).unwrap();
                    let (a, b, c, mk) = (v[k], v[(k + 1) % 3], v[(k + 2) % 3], ms[k].unwrap());
                    push(a, mk, c); push(mk, b, c);
                }
                2 => {
                    // Turned so the uncut edge is (u2, u0): cuts on (u0, u1) and (u1, u2).
                    let k = (0..3).find(|k| ms[*k].is_none()).unwrap();
                    let r = (k + 1) % 3;
                    let u = [v[r], v[(r + 1) % 3], v[(r + 2) % 3]];
                    let (m0, m1) = (ms[r].unwrap(), ms[(r + 1) % 3].unwrap());
                    push(m0, u[1], m1);
                    // The quad u0 m0 m1 u2 split along its shorter diagonal.
                    let d = |a: u32, b: u32| {
                        let p = |x: u32| { let bb = &bary[x as usize]; let mut o = [0f32; 3]; for j in 0..3 { for c in 0..3 { o[c] += pos[bb.v[j] as usize][c] * bb.w[j]; } } o };
                        len(sub(p(a), p(b)))
                    };
                    if d(u[0], m1) <= d(m0, u[2]) { push(u[0], m0, m1); push(u[0], m1, u[2]); } else { push(u[0], m0, u[2]); push(m0, m1, u[2]); }
                }
                _ => {
                    let (m0, m1, m2) = (ms[0].unwrap(), ms[1].unwrap(), ms[2].unwrap());
                    push(v[0], m0, m2); push(m0, v[1], m1); push(m2, m1, v[2]); push(m0, m1, m2);
                }
            }
        }
        resample(mesh, n, &bary);
        mesh.indices = indices;
        tri_sel = sel;
        added += mid.len();
    }
    added
}

/// Every per-vertex stream of the mesh at the new vertices (an absent or mismatched stream left as it was is dropped).
fn resample(mesh: &mut ExtractedMesh, n: usize, b: &[Bary]) {
    use crate::vertcolor::{lerp, lerp_dirs, lerp_morph, lerp_skin, lerp_tangents};
    fn s<const N: usize>(v: &mut Vec<[f32; N]>, n: usize, b: &[Bary]) { if v.len() == n { *v = lerp(v, b); } else { v.clear(); } }
    s(&mut mesh.positions, n, b);
    s(&mut mesh.rest_positions, n, b);
    if mesh.normals.len() == n { mesh.normals = lerp_dirs(&mesh.normals, b); } else { mesh.normals.clear(); }
    if mesh.rest_normals.len() == n { mesh.rest_normals = lerp_dirs(&mesh.rest_normals, b); } else { mesh.rest_normals.clear(); }
    if mesh.tangents.len() == n { mesh.tangents = lerp_tangents(&mesh.tangents, b); } else { mesh.tangents.clear(); }
    s(&mut mesh.uvs, n, b);
    s(&mut mesh.uv2, n, b);
    s(&mut mesh.uv3, n, b);
    s(&mut mesh.uv4, n, b);
    if mesh.vertex_colors.len() == n {
        let f: Vec<[f32; 4]> = mesh.vertex_colors.iter().map(|c| c.map(|x| x as f32)).collect();
        mesh.vertex_colors = lerp(&f, b).into_iter().map(|c| c.map(|x| x.round().clamp(0., 255.) as u8)).collect();
    } else { mesh.vertex_colors.clear(); }
    if mesh.weights.len() == n && mesh.bone_idx.len() == n {
        (mesh.weights, mesh.bone_idx) = lerp_skin(&mesh.weights, &mesh.bone_idx, b);
    }
    for (_, deltas) in &mut mesh.blend_shapes { *deltas = lerp_morph(deltas, n, b); }
}

#[cfg(test)]
mod tests {
    use super::*;
    /// A quad split along y=0 and a UV seam: cutting keeps both sides on the same places, the weights summed to one.
    #[test]
    fn cuts_long_edges_on_both_sides_of_a_seam() {
        // Two triangles sharing positions (0,0)-(1,0) through different vertices (a seam).
        let positions = vec![[0., 0., 0.], [1., 0., 0.], [0.5, 1., 0.], [0., 0., 0.], [1., 0., 0.], [0.5, -1., 0.]];
        let mut mesh = ExtractedMesh {
            positions: positions.clone(), rest_positions: positions,
            uvs: vec![[0., 0.], [1., 0.], [0.5, 1.], [0., 1.], [1., 1.], [0.5, 0.]],
            weights: vec![[1., 0., 0., 0.], [0., 1., 0., 0.], [1., 0., 0., 0.], [1., 0., 0., 0.], [0., 1., 0., 0.], [1., 0., 0., 0.]],
            bone_idx: vec![[0, 1, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0], [0, 1, 0, 0]],
            indices: vec![0, 1, 2, 4, 3, 5],
            blend_shapes: vec![("m".into(), vec![(1, [0., 0., 1.])])],
            ..Default::default()
        };
        let sel = vec![true, true, true, false, false, false];
        let added = refine(&mut mesh, &sel, 0.6, 1000);
        assert!(added >= 2);
        // No edge of any triangle on the selected side longer than the limit.
        let p = &mesh.rest_positions;
        for t in mesh.indices.chunks_exact(3) {
            if t.iter().all(|&v| p[v as usize][1] >= 0.) {
                for k in 0..3 { assert!(len(sub(p[t[k] as usize], p[t[(k + 1) % 3] as usize])) <= 0.6 + 1e-5); }
            }
        }
        // The seam: every midpoint on y=0 exists on both sides.
        let on_seam: Vec<[f32; 3]> = p.iter().skip(6).filter(|q| q[1].abs() < 1e-6).copied().collect();
        for q in &on_seam { assert_eq!(on_seam.iter().filter(|r| len(sub(**r, *q)) < 1e-6).count(), 2, "{q:?}"); }
        for w in &mesh.weights { assert!((w.iter().sum::<f32>() - 1.).abs() < 1e-5); }
        assert!(mesh.blend_shapes[0].1.len() > 1, "a morph spreads onto the new midpoints");
        assert_eq!(mesh.uvs.len(), p.len());
    }
}
