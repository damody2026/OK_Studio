//! Zip archives larger than 4 GB with non-ASCII member names (Tools/original_data.lua);
//! the Windows tar cannot read UTF-8 file lists.
use crate::{arg, read_input, Res};
use serde_json::{json, Value};
use std::io::{BufReader, BufWriter, Write};
use std::path::{Component, Path};

/// zip-create <spec.json|-> : {"out": zip, "root": dir, "files": [path relative to root, ...], "store": bool}
/// -> {"files", "bytes"}. Members keep the given relative names (forward slashes, UTF-8); Zip64 throughout.
pub fn create(args: &[String]) -> Res<Value> {
    let spec: Value = serde_json::from_slice(&read_input(arg(args, 0, "spec")?)?).map_err(|e| e.to_string())?;
    let out = spec["out"].as_str().ok_or("spec.out")?;
    let root = Path::new(spec["root"].as_str().ok_or("spec.root")?);
    let method = if spec["store"].as_bool().unwrap_or(false) { zip::CompressionMethod::Stored } else { zip::CompressionMethod::Deflated };
    let options = zip::write::SimpleFileOptions::default().compression_method(method).large_file(true);
    let file = std::fs::File::create(out).map_err(|e| format!("{out}: {e}"))?;
    let mut zip = zip::ZipWriter::new(BufWriter::with_capacity(1 << 20, file));
    let mut count = 0usize;
    for name in spec["files"].as_array().ok_or("spec.files")? {
        let name = name.as_str().ok_or("file name")?;
        let src = root.join(name);
        let mut input = BufReader::with_capacity(1 << 20, std::fs::File::open(&src).map_err(|e| format!("{}: {e}", src.display()))?);
        zip.start_file(name, options).map_err(|e| format!("{name}: {e}"))?;
        std::io::copy(&mut input, &mut zip).map_err(|e| format!("{name}: {e}"))?;
        count += 1;
    }
    let mut inner = zip.finish().map_err(|e| e.to_string())?;
    inner.flush().map_err(|e| e.to_string())?;
    drop(inner);
    Ok(json!({ "files": count, "bytes": std::fs::metadata(out).map_err(|e| e.to_string())?.len() }))
}

/// zip-extract <zip> <dest> [list.txt|-] -> {"files"}: every member, or only the names listed one per line.
pub fn extract(args: &[String]) -> Res<Value> {
    let path = arg(args, 0, "zip")?;
    let dest = Path::new(arg(args, 1, "dest")?);
    let wanted: Option<std::collections::HashSet<String>> = match args.get(2) {
        Some(list) => Some(String::from_utf8_lossy(&read_input(list)?).lines().map(|l| l.trim_end_matches('\r').to_string()).filter(|l| !l.is_empty()).collect()),
        None => None,
    };
    let file = std::fs::File::open(path).map_err(|e| format!("{path}: {e}"))?;
    let mut zip = zip::ZipArchive::new(BufReader::with_capacity(1 << 20, file)).map_err(|e| format!("{path}: {e}"))?;
    let mut count = 0usize;
    for i in 0..zip.len() {
        let mut member = zip.by_index(i).map_err(|e| e.to_string())?;
        let name = member.name().to_string();
        if wanted.as_ref().is_some_and(|w| !w.contains(&name)) || member.is_dir() { continue; }
        let rel = Path::new(&name);
        if rel.components().any(|c| !matches!(c, Component::Normal(_))) { return Err(format!("unsafe member name {name}")); }
        let target = dest.join(rel);
        if let Some(parent) = target.parent() { std::fs::create_dir_all(parent).map_err(|e| format!("{}: {e}", parent.display()))?; }
        let mut output = BufWriter::with_capacity(1 << 20, std::fs::File::create(&target).map_err(|e| format!("{}: {e}", target.display()))?);
        std::io::copy(&mut member, &mut output).map_err(|e| format!("{name}: {e}"))?;
        output.flush().map_err(|e| e.to_string())?;
        count += 1;
    }
    Ok(json!({ "files": count }))
}
