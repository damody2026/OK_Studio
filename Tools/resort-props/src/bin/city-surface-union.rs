//! Remove same-material opaque coplanar overlaps without changing their union.
//! Native importer interpolates the original triangle's UV/normal/color attributes.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
};
type V = [f64; 3];
type P = [f64; 2];
fn sub(a: V, b: V) -> V {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}
fn dot(a: V, b: V) -> f64 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
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
fn area(poly: &[P]) -> f64 {
    if poly.len() < 3 {
        return 0.;
    }
    let mut s = 0.;
    for i in 1..poly.len()-1 {
        s += side(poly[0],poly[i],poly[i+1]);
    }
    s * 0.5
}
fn half(poly: &[P], a: P, b: P, sign: f64, inside: bool) -> Vec<P> {
    if poly.is_empty() {
        return vec![];
    }
    let sign = sign * if inside { 1. } else { -1. };
    let mut out = vec![];
    let mut prev = *poly.last().unwrap();
    let mut d0 = side(a, b, prev) * sign;
    for &cur in poly {
        let d1 = side(a, b, cur) * sign;
        // Complementary half-planes must not both retain an epsilon-wide
        // strip: repeated subtraction would duplicate those slivers.
        let i0 = d0 >= 0.;
        let i1 = d1 >= 0.;
        if i0 != i1 {
            let t = d0 / (d0 - d1);
            out.push([
                prev[0] + (cur[0] - prev[0]) * t,
                prev[1] + (cur[1] - prev[1]) * t,
            ]);
        }
        if i1 {
            out.push(cur)
        }
        prev = cur;
        d0 = d1;
    }
    out.dedup_by(|a, b| (a[0] - b[0]).abs() + (a[1] - b[1]).abs() < 1e-7);
    out
}
fn subtract(poly: &[P], cover: &[P; 3]) -> Vec<Vec<P>> {
    let sign = area(cover).signum();
    let mut intersection = poly.to_vec();
    for k in 0..3 {
        intersection = half(&intersection, cover[k], cover[(k + 1) % 3], sign, true);
    }
    if area(&intersection).abs() < 1e-5 {
        return vec![poly.to_vec()];
    }
    let mut inside = poly.to_vec();
    let mut pieces = vec![];
    for k in 0..3 {
        let outside = half(&inside, cover[k], cover[(k + 1) % 3], sign, false);
        if area(&outside).abs() > 1e-6 {
            pieces.push(outside)
        }
        inside = half(&inside, cover[k], cover[(k + 1) % 3], sign, true);
        if inside.len() < 3 {
            break;
        }
    }
    pieces
}
#[derive(Clone)]
struct Tri {
    p: [V; 3],
    q: [P; 3],
    n: V,
    d: f64,
    drop: usize,
    slot: u32,
    id: i32,
    area: f64,
}
impl Tri {
    fn new(p: [V; 3], slot: u32, id: i32) -> Option<Self> {
        let n = cross(sub(p[1], p[0]), sub(p[2], p[0]));
        let size = dot(n, n).sqrt();
        if size < 1e-7 {
            return None;
        }
        let n = n.map(|x| x / size);
        let drop = (0..3)
            .max_by(|&i, &j| n[i].abs().total_cmp(&n[j].abs()))
            .unwrap();
        let axes: Vec<_> = (0..3).filter(|&i| i != drop).collect();
        let q = p.map(|p| [p[axes[0]], p[axes[1]]]);
        Some(Self {
            p,
            q,
            n,
            d: dot(n, p[0]),
            drop,
            slot,
            id,
            area: size * 0.5,
        })
    }
    fn lift(&self, p: P) -> V {
        let den = side(self.q[0], self.q[1], self.q[2]);
        let a = side(self.q[1], self.q[2], p) / den;
        let b = side(self.q[2], self.q[0], p) / den;
        let c = 1. - a - b;
        std::array::from_fn(|k| self.p[0][k] * a + self.p[1][k] * b + self.p[2][k] * c)
    }

}
fn u32at(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes(b[i..i + 4].try_into().unwrap())
}
fn read(path: &Path, allowed: &HashSet<u32>) -> Vec<Tri> {
    let b = fs::read(path).unwrap();
    assert_eq!(u32at(&b, 0), 0x43445932);
    let nv = u32at(&b, 4) as usize;
    let nt = u32at(&b, 8) as usize;
    let start = 12 + nv * 12;
    let mut out = vec![];
    for i in 0..nt {
        let slot = u32at(&b, start + nt * 16 + i * 4);
        if !allowed.contains(&slot) {
            continue;
        }
        let p = std::array::from_fn(|k| {
            let id = u32at(&b, start + i * 12 + k * 4) as usize;
            std::array::from_fn(|j| f32::from_bits(u32at(&b, 12 + id * 12 + j * 4)) as f64)
        });
        if let Some(t) = Tri::new(p, slot, u32at(&b, start + nt * 12 + i * 4) as i32) {
            out.push(t)
        }
    }
    out
}
fn process(ts: &[Tri], two_sided: &HashSet<u32>, cross_slot: bool) -> (Vec<Value>, f64) {
    // World-origin plane intercepts are not a conservative broadphase for
    // nearby tilted faces. Use padded 3D AABBs; exact geometry still qualifies
    // every candidate below. Oversized faces compare against all prior faces.
    let mut groups: HashMap<(i32, i32, i32), Vec<usize>> = HashMap::new();
    let mut large: Vec<usize> = vec![];
    let mut patches = vec![];
    let mut removed = 0.;
    for (i, t) in ts.iter().enumerate() {
        let lo: [i32;3] = std::array::from_fn(|k| ((t.p.iter().map(|p|p[k]).fold(f64::INFINITY,f64::min)-0.201)/100.).floor() as i32);
        let hi: [i32;3] = std::array::from_fn(|k| ((t.p.iter().map(|p|p[k]).fold(f64::NEG_INFINITY,f64::max)+0.201)/100.).floor() as i32);
        let cells=(0..3).map(|k|hi[k] as i64-lo[k] as i64+1).product::<i64>();
        let mut candidates=large.clone();
        if cells<=4096 {
            for x in lo[0]..=hi[0] {for y in lo[1]..=hi[1] {for z in lo[2]..=hi[2] {
                if let Some(v)=groups.get(&(x,y,z)){candidates.extend(v);}
            }}}
        }else{candidates.extend(0..i);}
        candidates.sort_unstable();candidates.dedup();
        let mut parts = vec![t.q.to_vec()];
        for j in candidates {
            let b = &ts[j];
            if (!cross_slot && b.slot != t.slot)
                || (if two_sided.contains(&t.slot) && two_sided.contains(&b.slot) {
                    dot(t.n, b.n).abs()
                } else {
                    dot(t.n, b.n)
                }) < if cross_slot {0.999999} else {0.99999999}
                || t.p.iter().any(|p| (dot(b.n, *p) - b.d).abs() > if cross_slot {0.2} else {0.002})
                || b.p.iter().any(|p| (dot(t.n, *p) - t.d).abs() > if cross_slot {0.2} else {0.002})

            {
                continue;
            }
            let axes: Vec<usize>=(0..3).filter(|&k|k!=t.drop).collect();
            let cover=b.p.map(|p|[p[axes[0]],p[axes[1]]]);
            let mut next = vec![];
            for p in parts {
                next.extend(subtract(&p, &cover))
            }
            parts = next;
            if parts.is_empty() {
                break;
            }
            assert!(
                parts.len() < if cross_slot && t.area > 1000000. {20000} else {1000},
                "Unexpected polygon fragmentation; id={} slot={} area={} pieces={} source={:?}",t.id,t.slot,t.area,parts.len(),t.p
            );
        }
        let retained = parts
            .iter()
            .map(|p| area(p).abs() / t.n[t.drop].abs())
            .sum::<f64>();
        assert!(retained <= t.area + 1e-3, "Area increased: id={} slot={} original={} retained={} points={:?} pieces={:?}",t.id,t.slot,t.area,retained,t.p,parts);
        if t.area - retained > 1e-4 {
            let mut replacements = vec![];
            for p in parts {
                for k in 1..p.len().saturating_sub(1) {
                    let q = [t.lift(p[0]), t.lift(p[k]), t.lift(p[k + 1])];
                    if dot(cross(sub(q[1], q[0]), sub(q[2], q[0])), t.n) > 1e-6 {
                        replacements.push(q)
                    }
                }
            }
            removed += t.area - retained;
            patches.push(json!({"triangle":t.id,"triangles":replacements,"original_area_cm2":t.area,"retained_area_cm2":retained}));
        }
        if cells <= 4096 {
            for x in lo[0]..=hi[0] {for y in lo[1]..=hi[1] {for z in lo[2]..=hi[2] {
                groups.entry((x,y,z)).or_default().push(i);
            }}}
        }else{large.push(i);}
    }
    (patches, removed)
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let folder = PathBuf::from(args.get(1).expect("CDY2 export folder"));
    let output = PathBuf::from(args.get(2).expect("union plan JSON"));
    let cross_slot=args.iter().any(|a|a=="--all-opaque-slots");
    let bytes = fs::read(folder.join("scene.json")).unwrap();
    let scene: Value = serde_json::from_slice(&bytes).unwrap();
    let instances = scene["instances"].as_array().unwrap();
    let mut plans = vec![];
    let mut count = 0;
    let mut removed = 0.;
    for (mid, m) in scene["meshes"].as_array().unwrap().iter().enumerate() {
        let refs: Vec<_> = instances
            .iter()
            .filter(|i| i["mesh"].as_u64() == Some(mid as u64))
            .collect();
        if refs.is_empty() {
            continue;
        }
        let nslots = refs
            .iter()
            .map(|i| i["blend_modes"].as_array().unwrap().len())
            .min()
            .unwrap();
        let allowed: HashSet<u32> = (0..nslots)
            .filter(|&s| refs.iter().all(|i| i["blend_modes"][s].as_i64() == Some(0)))
            .map(|s| s as u32)
            .collect();
        let two_sided: HashSet<u32> = (0..nslots)
            .filter(|&s| {
                refs.iter()
                    .all(|i| i["two_sided_by_slot"][s].as_bool() == Some(true))
            })
            .map(|s| s as u32)
            .collect();
        let mut lods = vec![];
        for l in m["lods"].as_array().unwrap() {
            let file = l["file"].as_str().unwrap();
            let mut ts = read(&folder.join(file), &allowed);
            // Small details take precedence over broad backing surfaces.
            // Their original material and barycentric UVs remain untouched;
            // only hidden near-coplanar overlap is cut out of the backing.
            if cross_slot { ts.sort_by(|a,b|a.area.total_cmp(&b.area).then(a.id.cmp(&b.id))); }
            let (patches, area) = process(&ts, &two_sided, cross_slot);
            if !patches.is_empty() {
                count += patches.len();
                removed += area;
                lods.push(json!({"lod":l["lod"],"source_sha256":format!("{:x}",Sha256::digest(fs::read(folder.join(file)).unwrap())),"patches":patches}));
            }
        }
        if !lods.is_empty() {
            let mut keys: Vec<_> = refs.iter().map(|i| i["key"].as_str().unwrap()).collect();
            keys.sort();
            keys.dedup();
            plans.push(json!({"source_asset":m["asset"],"component_keys":keys,"lods":lods}));
        }
        if mid % 25 == 0 {
            eprintln!(
                "mesh {} plans {} patched triangles {}",
                mid,
                plans.len(),
                count
            );
        }
    }
    let result = json!({"status":"prepared_requires_native_apply_and_area_validation","cross_slot":cross_slot,"distance_tolerance_cm":if cross_slot{0.2}else{0.002},"method":"Opaque coplanar polygon subtraction; cross-slot mode preserves smaller original details over backing; opposite winding merged only for uniformly two-sided slots; preserves union and barycentric attributes","scene_sha256":format!("{:x}",Sha256::digest(bytes)),"modified_source_triangles":count,"redundant_area_cm2":removed,"meshes":plans});
    fs::write(output, serde_json::to_vec(&result).unwrap()).unwrap();
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fine_material_detail_wins_over_near_coplanar_backing() {
        let detail=Tri::new([[10.,10.,0.1],[20.,10.,0.1],[10.,20.,0.1]],1,9).unwrap();
        let backing=Tri::new([[0.,0.,0.],[100.,0.,0.],[0.,100.,0.]],0,10).unwrap();
        let (patches,removed)=process(&[detail,backing],&HashSet::new(),true);
        assert_eq!(patches.len(),1);assert_eq!(patches[0]["triangle"],10);assert!((removed-50.).abs()<1e-6);
    }
    #[test]
    fn complementary_half_planes_do_not_duplicate_thin_slivers() {
        let poly=[[49.99999237060547,520.],[-90.,380.],[49.99995422363281,380.]];
        let cover=[[49.999954223641126,380.0000305175781],[-89.99996948242355,380.0000305175781],[-90.,380.]];
        let pieces=subtract(&poly,&cover);let kept:f64=pieces.iter().map(|p|area(p).abs()).sum();
        assert!(kept<=area(&poly).abs()+1e-8);
    }
    #[test]
    fn overlapping_triangles_preserve_union_area() {
        let a = [[0., 0.], [100., 0.], [0., 100.]];
        let b = [[25., 25.], [125., 25.], [25., 125.]];
        let parts = subtract(&b, &a);
        let remaining: f64 = parts.iter().map(|p| area(p).abs()).sum();
        assert!((remaining - 3750.).abs() < 1e-6);
        assert!(subtract(&a, &a).is_empty());
    }
    #[test]
    fn shared_edges_keep_both_surfaces() {
        let a = [[0., 0.], [100., 0.], [0., 100.]];
        let b = [[100., 100.], [0., 100.], [100., 0.]];
        assert!((subtract(&b, &a).iter().map(|p| area(p).abs()).sum::<f64>() - 5000.).abs() < 1e-6);
    }
    #[test]
    fn barycentric_lift_keeps_source_plane() {
        let t = Tri::new([[1., 0., 0.], [1., 100., 0.], [1., 0., 100.]], 0, 0).unwrap();
        assert_eq!(t.lift([25., 25.]), [1., 25., 25.]);
    }
    #[test]
    fn multiple_covers_preserve_the_remaining_corner() {
        let sources = [
            [[0., 0.], [100., 0.], [0., 100.]],
            [[100., 100.], [0., 100.], [100., 0.]],
        ];
        let covers = [
            [[0., 0.], [60., 0.], [0., 100.]],
            [[60., 100.], [0., 100.], [60., 0.]],
            [[40., 0.], [100., 0.], [40., 40.]],
            [[100., 40.], [40., 40.], [100., 0.]],
        ];
        let mut total = 0.;
        for t in sources {
            let mut pieces = vec![t.to_vec()];
            for c in covers {
                pieces = pieces.iter().flat_map(|p| subtract(p, &c)).collect();
            }
            total += pieces.iter().map(|p| area(p).abs()).sum::<f64>();
        }
        assert!((total - 2400.).abs() < 1e-6);
    }
    #[test]
    fn different_slots_and_opposite_winding_are_preserved() {
        let a = Tri::new([[0., 0., 0.], [100., 0., 0.], [0., 100., 0.]], 0, 0).unwrap();
        let mut b = a.clone();
        b.slot = 1;
        b.id = 1;
        assert!(process(&[a.clone(), b], &HashSet::new(), false).0.is_empty());
        let b = Tri::new([a.p[0], a.p[2], a.p[1]], 0, 1).unwrap();
        assert!(process(&[a.clone(), b.clone()], &HashSet::new(), false)
            .0
            .is_empty());
        let result = process(&[a, b], &HashSet::from([0]), false);
        assert_eq!(result.0.len(), 1);
        assert!((result.1 - 5000.).abs() < 1e-6);
    }
    #[test]
    fn far_origin_tilted_overlap_is_not_lost_to_plane_buckets() {
        let a=Tri::new([[100000.,100000.,0.],[100000.,100100.,0.],[100000.,100000.,100.]],0,0).unwrap();
        let b=Tri::new([[100000.,100020.,10.],[100000.001,100080.,10.],[100000.,100020.,70.]],0,1).unwrap();
        assert!(dot(a.n,b.n)>0.99999999);
        let result=process(&[a,b],&HashSet::new(),true);
        assert_eq!(result.0.len(),1);assert!(result.1>1700.);
    }

    #[test]
    fn near_parallel_submillimeter_street_surfaces_share_the_scan_tolerance() {
        let a=Tri::new([[100000.,100000.,0.],[100000.,100100.,0.],[100000.,100000.,100.]],0,0).unwrap();
        let b=Tri::new([[100000.,100020.,10.],[100000.01,100080.,10.],[100000.,100020.,70.]],0,1).unwrap();
        let nd=dot(a.n,b.n);assert!(nd<0.99999999&&nd>0.999999);
        assert_eq!(process(&[a.clone(),b.clone()],&HashSet::new(),false).0.len(),0);
        let result=process(&[a,b],&HashSet::new(),true);
        assert_eq!(result.0.len(),1);assert!(result.1>1700.);
    }

}
