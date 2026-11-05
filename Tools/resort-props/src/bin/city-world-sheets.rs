#[allow(dead_code)]
#[path = "city-asymmetric-sheets.rs"]
mod sheets;

use std::{env, fs, path::PathBuf};

fn main() {
    let args: Vec<_> = env::args().collect();
    let folder = PathBuf::from(args.get(1).expect("source folder"));
    let inventory = PathBuf::from(args.get(2).expect("inventory-baseline.json"));
    let ledger = PathBuf::from(args.get(3).expect("facing-install.json"));
    let conflicts = PathBuf::from(args.get(4).expect("scan.conflicts.jsonl"));
    let output = PathBuf::from(args.get(5).expect("output plan json"));
    let plan = sheets::build_world_plan(&folder, &inventory, &ledger, &conflicts)
        .unwrap_or_else(|e| panic!("{e}"));
    fs::write(&output, serde_json::to_vec(&plan).unwrap())
        .unwrap_or_else(|e| panic!("write {}: {e}", output.display()));
    eprintln!(
        "modified {} blocked {} covers {}",
        plan["modified_source_triangles"],
        plan["blocked"].as_array().map(|v| v.len()).unwrap_or(0),
        plan["covers"].as_array().map(|v| v.len()).unwrap_or(0)
    );
}
