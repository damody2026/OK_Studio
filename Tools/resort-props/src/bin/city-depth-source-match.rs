//! Revalidate the inputs of a prior triangle scan, without claiming its candidates passed.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{collections::{BTreeMap, BTreeSet}, env, fs, path::{Path, PathBuf}};

fn hash(path: &Path) -> String { format!("{:x}", Sha256::digest(fs::read(path).unwrap())) }
fn read(path: &Path) -> Value { serde_json::from_slice(&fs::read(path).unwrap()).unwrap() }
fn celestial(r: &Value) -> bool {
    matches!(r["actor"].as_str(), Some("ResortNightSky" | "ResortMoonDisc" | "ResortMoonHalo"))
}
fn instance_key(r: &Value) -> String { format!("{}#{}", r["key"].as_str().unwrap(), r["instance"]) }
fn canonical(r: &Value, scene: &Value) -> Value {
    json!({"actor":r["actor"],"component":r["component"],"instance":r["instance"],
        "asset":scene["meshes"][r["mesh"].as_u64().unwrap() as usize]["asset"],
        "matrix":r["matrix"],"materials":r["materials"],"blend_modes":r["blend_modes"],
        "two_sided":r["two_sided"],"two_sided_by_slot":r["two_sided_by_slot"]})
}
fn main() {
    let args: Vec<_> = env::args().collect();
    let previous = PathBuf::from(args.get(1).expect("previous scene folder"));
    let scan_path = PathBuf::from(args.get(2).expect("previous scan JSON"));
    let export_path = PathBuf::from(args.get(3).expect("fresh native depth_export.json"));
    let output = PathBuf::from(args.get(4).expect("output proof JSON"));
    let scan = read(&scan_path); let export = read(&export_path);
    assert_eq!(scan["truncated"], false, "A complete prior scan is required");
    assert_eq!(export["status"], "passed", "A successful fresh native export is required");
    assert_eq!(scan["metadata_sha256"].as_str().unwrap(), hash(&previous.join("scene.json")));
    let current = PathBuf::from(export["folder"].as_str().unwrap());
    let old = read(&previous.join("scene.json")); let new = read(&current.join("scene.json"));
    let old_rows: BTreeMap<_,_> = old["instances"].as_array().unwrap().iter().filter(|r| !celestial(r)).map(|r| (instance_key(r),r)).collect();
    let new_rows: BTreeMap<_,_> = new["instances"].as_array().unwrap().iter().filter(|r| !celestial(r)).map(|r| (instance_key(r),r)).collect();
    assert_eq!(old_rows.len(),old["instances"].as_array().unwrap().iter().filter(|r| !celestial(r)).count(),"Duplicate old instance key");
    assert_eq!(new_rows.len(),new["instances"].as_array().unwrap().iter().filter(|r| !celestial(r)).count(),"Duplicate new instance key");
    let mut differences=vec![];
    for key in old_rows.keys().chain(new_rows.keys()).collect::<BTreeSet<_>>() {
        match (old_rows.get(key),new_rows.get(key)) {
            (Some(a),Some(b)) if canonical(a,&old)==canonical(b,&new) => (),
            _ => differences.push(json!({"kind":"instance_or_binding_changed","key":key})),
        }
    }
    let new_meshes: BTreeMap<_,_> = new["meshes"].as_array().unwrap().iter().map(|m|(m["asset"].as_str().unwrap(),m)).collect();
    let recorded: BTreeMap<_,_> = scan["mesh_source_sha256"].as_array().unwrap().iter().map(|r|(r["file"].as_str().unwrap(),r["sha256"].as_str().unwrap())).collect();
    let needed: BTreeSet<_> = old_rows.values().map(|r|r["mesh"].as_u64().unwrap() as usize).collect();
    let mut hashes=BTreeMap::new(); let mut checked=0;let mut higher_lods=vec![];
    for index in needed {
        let mesh=&old["meshes"][index]; let asset=mesh["asset"].as_str().unwrap();
        let Some(fresh)=new_meshes.get(asset) else {differences.push(json!({"kind":"mesh_missing","asset":asset}));continue};
        let fresh_lods: BTreeMap<_,_> = fresh["lods"].as_array().unwrap().iter().map(|l|(l["lod"].as_u64().unwrap(),l)).collect();
        if mesh["lods"].as_array().unwrap().len()!=fresh_lods.len() {differences.push(json!({"kind":"lod_count_changed","asset":asset}));}
        for lod in mesh["lods"].as_array().unwrap() {
            let level=lod["lod"].as_u64().unwrap();
            let Some(fresh_lod)=fresh_lods.get(&level) else {differences.push(json!({"kind":"lod_missing","asset":asset,"lod":level}));continue};
            let source=lod["file"].as_str().unwrap();
            let expected=if let Some(value)=recorded.get(source) {(*value).to_owned()} else {
                assert!(level>2,"Prior scan did not hash an LOD within its declared 0-2 coverage");
                // These files are compared with the preserved export snapshot,
                // but must never be described as covered by the prior scan.
                let value=hash(&previous.join(source));higher_lods.push(json!({"asset":asset,"lod":level,"snapshot_sha256":value,"part_of_previous_triangle_scan":false}));value
            };
            let file=fresh_lod["file"].as_str().unwrap();
            let actual=hashes.entry(file.to_owned()).or_insert_with(||hash(&current.join(file)));
            checked+=1;
            if actual.as_str()!=expected || lod["vertices"]!=fresh_lod["vertices"] || lod["triangles"]!=fresh_lod["triangles"] {
                differences.push(json!({"kind":"lod_geometry_changed","asset":asset,"lod":level}));
            }
        }
    }
    let matched=differences.is_empty();
    let report=json!({"status":if matched{"geometry_and_bindings_match_previous_scan"}else{"requires_fresh_triangle_scan"},
        "current_map_sha256":export["map_sha256"],"fresh_export_sha256":hash(&export_path),
        "fresh_metadata_sha256":hash(&current.join("scene.json")),"previous_scan_sha256":hash(&scan_path),
        "previous_metadata_sha256":scan["metadata_sha256"],"instances_checked":new_rows.len(),"lod_files_checked":checked,
        "differences":differences,"previous_scan_lod_passes":[0,1,2],"additional_unscanned_higher_lod_snapshots":higher_lods,"previous_unconfirmed_candidates":scan["candidate_conflicts"],
        "previous_exact_duplicate_pairs":scan["exact_duplicate_pairs"],"full_city_zero_z_fighting_accepted":false,
        "scope":"Exact matrix, mesh LOD bytes, effective material paths, blend modes and sidedness comparison. Celestial surfaces retain their separate native angular/depth-layer audit. This revalidates scan inputs; it does not accept unresolved candidates or replace rendered motion review."});
    fs::write(output,serde_json::to_vec_pretty(&report).unwrap()).unwrap();
    println!("instances={} lods={} differences={}",new_rows.len(),checked,report["differences"].as_array().unwrap().len());
    if !matched { std::process::exit(2); }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn changing_export_indices_does_not_hide_material_or_transform_changes() {
        let a=json!({"meshes":[{"asset":"/Game/A.A"},{"asset":"/Game/B.B"}]});
        let b=json!({"meshes":[{"asset":"/Game/B.B"},{"asset":"/Game/A.A"}]});
        let r=json!({"actor":"Floor","component":"Mesh","mesh":0,"instance":-1,"matrix":[1,0,0,0],"materials":["M"],"blend_modes":[0],"two_sided":false,"two_sided_by_slot":[false]});
        let mut s=r.clone();s["mesh"]=json!(1);assert_eq!(canonical(&r,&a),canonical(&s,&b));
        s["matrix"][3]=json!(0.01);assert_ne!(canonical(&r,&a),canonical(&s,&b));
        s=r.clone();s["mesh"]=json!(1);s["two_sided_by_slot"]=json!([true]);assert_ne!(canonical(&r,&a),canonical(&s,&b));
        s=r.clone();s["mesh"]=json!(1);s["materials"]=json!(["DifferentMaterial"]);assert_ne!(canonical(&r,&a),canonical(&s,&b));
        s=r.clone();s["mesh"]=json!(1);s["blend_modes"]=json!([1]);assert_ne!(canonical(&r,&a),canonical(&s,&b));
    }
}
