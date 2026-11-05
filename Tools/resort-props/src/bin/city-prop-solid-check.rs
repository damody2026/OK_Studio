//! Read-only proposals for closed, outward, non-occupiable component slots.
//! Does not edit geometry, transforms, instances, collisions, bindings, assets, or materials.
//! Does not claim that z-fighting is resolved. Native shader, WPO/PDO, reverse-culling,
//! current-source hash, and component-preservation checks remain for Codex.

use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::Path,
    process::ExitCode,
};

const THICKNESS_CAP_CM: f64 = 100.0;
const CDY2_MAGIC: u32 = 0x43445932;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!(
            "usage: city-prop-solid-check <scene-folder> <selection.json> <output.json>"
        );
        return ExitCode::from(2);
    }
    let selection_bytes = match fs::read(&args[2]) {
        Ok(bytes) => bytes,
        Err(err) => {
            let _ = write_output(
                &args[3],
                &json!({
                    "status": "rejected",
                    "reasons": [format!("failed to read selection: {err}")]
                }),
            );
            eprintln!("failed to read selection: {err}");
            return ExitCode::from(1);
        }
    };
    let selection: Value = match serde_json::from_slice(&selection_bytes) {
        Ok(value) => value,
        Err(err) => {
            let _ = write_output(
                &args[3],
                &json!({
                    "status": "rejected",
                    "reasons": [format!("selection is not JSON: {err}")]
                }),
            );
            eprintln!("selection is not JSON: {err}");
            return ExitCode::from(1);
        }
    };
    match prepare(Path::new(&args[1]), &selection) {
        Ok(report) => {
            if let Err(err) = write_output(&args[3], &report) {
                eprintln!("{err}");
                return ExitCode::from(1);
            }
            let proposed = report["components"].as_array().map(|v| v.len()).unwrap_or(0);
            let rejected = report["rejected"].as_array().map(|v| v.len()).unwrap_or(0);
            eprintln!(
                "city-prop-solid-check: status {} proposed {proposed} rejected {rejected}",
                report["status"].as_str().unwrap_or("")
            );
            ExitCode::SUCCESS
        }
        Err(err) => {
            let _ = write_output(
                &args[3],
                &json!({"status": "rejected", "reasons": [err]}),
            );
            eprintln!("{err}");
            ExitCode::from(1)
        }
    }
}

fn write_output(path: &str, value: &Value) -> Result<(), String> {
    let bytes = serde_json::to_vec(value).map_err(|err| format!("failed to encode report: {err}"))?;
    fs::write(path, bytes).map_err(|err| format!("failed to write {path}: {err}"))
}

fn prepare(folder: &Path, selection: &Value) -> Result<Value, String> {
    let max_cm = selection_thickness(selection)?;
    let keys = selection_keys(selection)?;
    let scene_bytes = fs::read(folder.join("scene.json"))
        .map_err(|err| format!("failed to read scene.json: {err}"))?;
    let scene_sha256 = hex_sha256(&scene_bytes);
    let scene: Value = serde_json::from_slice(&scene_bytes)
        .map_err(|err| format!("scene.json is not JSON: {err}"))?;
    let format = scene.get("format").and_then(Value::as_str).unwrap_or("");
    if !format.starts_with("CDY2") {
        return Err("scene format must be a CDY2 export".to_string());
    }
    let meshes = parse_meshes(scene.get("meshes"))?;
    let instances = scene
        .get("instances")
        .and_then(Value::as_array)
        .ok_or_else(|| "scene instances array required".to_string())?;
    let mut rows_of: HashMap<String, Vec<usize>> = HashMap::new();
    for (index, instance) in instances.iter().enumerate() {
        let key = instance
            .get("key")
            .and_then(Value::as_str)
            .ok_or_else(|| format!("instance {index} is missing key"))?;
        rows_of.entry(key.to_string()).or_default().push(index);
    }

    let mut cache: HashMap<String, Result<Parsed, String>> = HashMap::new();
    let mut proposed = Vec::new();
    let mut rejected = Vec::new();
    for key in keys {
        match classify_component(folder, &meshes, instances, rows_of.get(&key), &key, max_cm, &mut cache)
        {
            ComponentVerdict::Propose(value) => proposed.push(value),
            ComponentVerdict::Reject(value) => rejected.push(value),
        }
    }
    Ok(json!({
        "status": "prepared_requires_native_validation",
        "scene_sha256": scene_sha256,
        "max_solid_thickness_cm": max_cm,
        "position_weld": "exact float32 bits; -0 canonicalized to +0; positions are not quantized",
        "orientation": "negative signed volume relative to a shell-local origin, matching native Engine Cube",
        "thickness": "min(local bbox axis extent * matrix row-norm scale) must be <= max_solid_thickness_cm on every shell and every instance",
        "proposal": "per-component slots only; shared meshes stay shared; original assets and materials are not edited",
        "inventory_modified": false,
        "geometry_transforms_instances_collisions_or_bindings_changed": false,
        "claims": {
            "material_or_map_changes_applied": false,
            "z_fighting_resolved": false,
            "original_assets_or_materials_edited": false
        },
        "remaining_native_checks": [
            "Native shader, world position offset (WPO), and pixel depth offset (PDO)",
            "Reverse culling",
            "Current source hash before apply",
            "Component preservation: override only the selected component; do not edit the original asset or material"
        ],
        "components": proposed,
        "rejected": rejected
    }))
}

fn selection_thickness(selection: &Value) -> Result<f64, String> {
    match selection.get("max_solid_thickness_cm") {
        None => Ok(THICKNESS_CAP_CM),
        Some(value) => {
            let thickness = value.as_f64().ok_or_else(|| {
                "max_solid_thickness_cm must be a number in (0, 100]".to_string()
            })?;
            if thickness.is_finite() && thickness > 0.0 && thickness <= THICKNESS_CAP_CM {
                Ok(thickness)
            } else {
                Err("max_solid_thickness_cm must be in (0, 100]; values above 100 are rejected"
                    .to_string())
            }
        }
    }
}

fn selection_keys(selection: &Value) -> Result<Vec<String>, String> {
    let values = selection
        .get("components")
        .and_then(Value::as_array)
        .ok_or_else(|| "selection components array of actor::component keys required".to_string())?;
    let mut keys = Vec::with_capacity(values.len());
    let mut seen = HashSet::new();
    for value in values {
        let key = value.as_str().ok_or_else(|| {
            "selection components must be exact actor::component strings".to_string()
        })?;
        if !seen.insert(key.to_string()) {
            return Err(format!("duplicate selection component key {key}"));
        }
        keys.push(key.to_string());
    }
    Ok(keys)
}

struct MeshInfo {
    asset: String,
    lods: Vec<LodInfo>,
}

struct LodInfo {
    level: i64,
    file: String,
}

fn parse_meshes(value: Option<&Value>) -> Result<Vec<MeshInfo>, String> {
    let values = value
        .and_then(Value::as_array)
        .ok_or_else(|| "scene meshes array required".to_string())?;
    let mut meshes = Vec::with_capacity(values.len());
    for (index, mesh) in values.iter().enumerate() {
        let asset = mesh
            .get("asset")
            .and_then(Value::as_str)
            .ok_or_else(|| format!("mesh {index} is missing asset"))?
            .to_string();
        let lod_values = mesh
            .get("lods")
            .and_then(Value::as_array)
            .ok_or_else(|| format!("mesh {index} lods array required"))?;
        let mut lods = Vec::with_capacity(lod_values.len());
        for (lod_index, lod) in lod_values.iter().enumerate() {
            let level = lod.get("lod").and_then(Value::as_i64).ok_or_else(|| {
                format!("mesh {index} lod {lod_index} is missing an integer lod")
            })?;
            let file = lod
                .get("file")
                .and_then(Value::as_str)
                .ok_or_else(|| format!("mesh {index} lod {lod_index} is missing file"))?
                .to_string();
            lods.push(LodInfo { level, file });
        }
        meshes.push(MeshInfo { asset, lods });
    }
    Ok(meshes)
}

enum ComponentVerdict {
    Propose(Value),
    Reject(Value),
}

struct Inst {
    actor: String,
    component: String,
    local: i64,
    mesh: usize,
    scales: [f64; 3],
    materials: Vec<String>,
    two_sided: Vec<bool>,
    blend: Vec<i64>,
}

impl Inst {
    fn place(&self) -> String {
        if self.local < 0 {
            "static mesh".to_string()
        } else {
            format!("hism local index {}", self.local)
        }
    }
}

fn classify_component(
    folder: &Path,
    meshes: &[MeshInfo],
    instances: &[Value],
    rows: Option<&Vec<usize>>,
    key: &str,
    max_cm: f64,
    cache: &mut HashMap<String, Result<Parsed, String>>,
) -> ComponentVerdict {
    let Some(rows) = rows else {
        return reject(key, None, None, vec!["component key is absent".to_string()]);
    };
    let mut parsed = Vec::with_capacity(rows.len());
    for &index in rows {
        match parse_instance(&instances[index], index) {
            Ok(instance) => parsed.push(instance),
            Err(reason) => {
                return reject(key, None, None, vec![reason]);
            }
        }
    }
    let actor = parsed[0].actor.clone();
    let component = parsed[0].component.clone();
    let mesh_index = parsed[0].mesh;
    if parsed.iter().any(|inst| inst.actor != actor || inst.component != component) {
        return reject(
            key,
            Some(actor),
            Some(component),
            vec!["ambiguous component key".to_string()],
        );
    }
    if format!("{actor}::{component}") != key {
        return reject(
            key,
            Some(actor),
            Some(component),
            vec!["ambiguous component key".to_string()],
        );
    }
    if parsed.iter().any(|inst| inst.mesh != mesh_index) {
        return reject(
            key,
            Some(actor),
            Some(component),
            vec!["inconsistent mesh".to_string()],
        );
    }
    if let Err(reason) = validate_instance_indexes(&parsed) {
        return reject(key, Some(actor), Some(component), vec![reason]);
    }
    if let Err(reason) = validate_material_arrays(&parsed) {
        return reject(key, Some(actor), Some(component), vec![reason]);
    }
    for inst in &mut parsed {
        match linear_scales_from_instance(instances, rows, inst) {
            Ok(scale) => inst.scales = scale,
            Err(reason) => {
                return reject(
                    key,
                    Some(actor),
                    Some(component),
                    vec![format!("{}: {reason}", inst.place())],
                );
            }
        }
    }
    if mesh_index >= meshes.len() {
        return reject(
            key,
            Some(actor),
            Some(component),
            vec!["mesh index is outside the scene".to_string()],
        );
    }
    let mesh = &meshes[mesh_index];
    if mesh.lods.is_empty() {
        return reject(
            key,
            Some(actor),
            Some(component),
            vec!["mesh has no source LODs".to_string()],
        );
    }
    for lod in &mesh.lods {
        ensure_lod(cache, folder, lod);
    }
    for lod in &mesh.lods {
        if let Some(Err(err)) = cache.get(&lod.file) {
            return reject(
                key,
                Some(actor),
                Some(component),
                vec![format!("LOD {} {}: {err}", lod.level, lod.file)],
            );
        }
    }
    let proofs: Vec<(&LodInfo, &Parsed)> = mesh
        .lods
        .iter()
        .map(|lod| (lod, cache.get(&lod.file).unwrap().as_ref().unwrap()))
        .collect();
    let material_len = parsed[0].materials.len();
    for (lod, proof) in &proofs {
        for triangle in &proof.triangles {
            if triangle.slot >= material_len {
                return reject(
                    key,
                    Some(actor.clone()),
                    Some(component.clone()),
                    vec![format!(
                        "LOD {} triangle slot {} is outside the material array",
                        lod.level, triangle.slot
                    )],
                );
            }
        }
    }

    let mut slots = HashSet::new();
    for (_, proof) in &proofs {
        for triangle in &proof.triangles {
            slots.insert(triangle.slot);
        }
    }
    let mut ordered: Vec<usize> = slots.into_iter().collect();
    ordered.sort_unstable();
    let mut safe = Vec::new();
    let mut diagnostics = Vec::new();
    let mut binding_thickness = 0.0_f64;
    for slot in ordered {
        match slot_failure(slot, &proofs, &parsed, max_cm) {
            None => {
                binding_thickness = binding_thickness.max(slot_binding_thickness(slot, &proofs, &parsed));
                safe.push(slot);
            }
            Some(reason) => diagnostics.push(reason),
        }
    }
    if safe.is_empty() {
        if diagnostics.is_empty() {
            diagnostics.push("no source slot is a proven opaque two-sided solid".to_string());
        }
        return reject(key, Some(actor), Some(component), diagnostics);
    }
    let source_lods: Vec<Value> = proofs
        .iter()
        .map(|(lod, proof)| {
            json!({
                "lod": lod.level,
                "file": lod.file,
                "sha256": proof.sha256,
                "triangles": proof.triangles.len(),
                "native_id_count": proof.native_ids.len(),
                "native_ids_sha256": proof.native_ids_sha256
            })
        })
        .collect();
    let mut local_indexes: Vec<i64> = parsed.iter().map(|inst| inst.local).collect();
    local_indexes.sort_unstable();
    ComponentVerdict::Propose(json!({
        "actor": actor,
        "component": component,
        "component_key": key,
        "source_asset": mesh.asset,
        "instance_count": parsed.len(),
        "local_indexes": local_indexes,
        "safe_slots": safe,
        "min_axis_thickness_cm": binding_thickness,
        "source_lods": source_lods,
        "diagnostics": diagnostics
    }))
}

fn reject(key: &str, actor: Option<String>, component: Option<String>, reasons: Vec<String>) -> ComponentVerdict {
    ComponentVerdict::Reject(json!({
        "component_key": key,
        "actor": actor,
        "component": component,
        "reasons": reasons
    }))
}

fn parse_instance(value: &Value, index: usize) -> Result<Inst, String> {
    let actor = value
        .get("actor")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("instance {index} is missing actor"))?
        .to_string();
    let component = value
        .get("component")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("instance {index} is missing component"))?
        .to_string();
    let mesh = value.get("mesh").and_then(Value::as_u64).ok_or_else(|| {
        format!("instance {index} mesh index is missing or negative")
    })? as usize;
    let local = value.get("instance").and_then(Value::as_i64).ok_or_else(|| {
        format!("instance {index} is missing integer instance (-1 static, or HISM local index)")
    })?;
    if local < -1 {
        return Err(format!("instance {index} has invalid instance index {local}"));
    }
    let (materials, two_sided, blend) = parse_material_arrays(value, index)?;
    Ok(Inst {
        actor,
        component,
        local,
        mesh,
        scales: [1.0, 1.0, 1.0],
        materials,
        two_sided,
        blend,
    })
}

fn parse_material_arrays(
    value: &Value,
    index: usize,
) -> Result<(Vec<String>, Vec<bool>, Vec<i64>), String> {
    let materials = value
        .get("materials")
        .and_then(Value::as_array)
        .ok_or_else(|| format!("instance {index} inconsistent material arrays: materials missing"))?;
    let sides = value.get("two_sided_by_slot").and_then(Value::as_array).ok_or_else(|| {
        format!("instance {index} inconsistent material arrays: two_sided_by_slot missing")
    })?;
    let blends = value.get("blend_modes").and_then(Value::as_array).ok_or_else(|| {
        format!("instance {index} inconsistent material arrays: blend_modes missing")
    })?;
    if materials.len() != sides.len() || materials.len() != blends.len() {
        return Err(format!(
            "instance {index} inconsistent material arrays: materials, two_sided_by_slot, and blend_modes differ in length"
        ));
    }
    let mut material_names = Vec::with_capacity(materials.len());
    let mut two_sided = Vec::with_capacity(sides.len());
    let mut blend = Vec::with_capacity(blends.len());
    for slot in 0..materials.len() {
        let name = materials[slot].as_str().ok_or_else(|| {
            format!("instance {index} inconsistent material arrays: materials[{slot}] is not a string")
        })?;
        let side = sides[slot].as_bool().ok_or_else(|| {
            format!(
                "instance {index} inconsistent material arrays: two_sided_by_slot[{slot}] is not a bool"
            )
        })?;
        let mode = blends[slot].as_i64().ok_or_else(|| {
            format!("instance {index} inconsistent material arrays: blend_modes[{slot}] is not an integer")
        })?;
        material_names.push(name.to_string());
        two_sided.push(side);
        blend.push(mode);
    }
    Ok((material_names, two_sided, blend))
}

fn validate_instance_indexes(rows: &[Inst]) -> Result<(), String> {
    let ordinary = rows.iter().any(|inst| inst.local < 0);
    let instanced = rows.iter().any(|inst| inst.local >= 0);
    if ordinary && instanced {
        return Err("mixed ordinary and instanced rows".to_string());
    }
    if ordinary {
        if rows.len() == 1 && rows[0].local == -1 {
            Ok(())
        } else {
            Err("ordinary component requires exactly one instance -1 row".to_string())
        }
    } else {
        let mut indexes: Vec<i64> = rows.iter().map(|inst| inst.local).collect();
        indexes.sort_unstable();
        if indexes.windows(2).any(|pair| pair[0] == pair[1]) {
            return Err("duplicate hism local index".to_string());
        }
        let expected: Vec<i64> = (0..indexes.len() as i64).collect();
        if indexes != expected {
            Err(format!(
                "incomplete hism local index sequence {indexes:?}; expected {expected:?}"
            ))
        } else {
            Ok(())
        }
    }
}

fn validate_material_arrays(rows: &[Inst]) -> Result<(), String> {
    let materials = &rows[0].materials;
    let sides = &rows[0].two_sided;
    let blend = &rows[0].blend;
    if rows.iter().any(|inst| {
        inst.materials.len() != materials.len()
            || inst.two_sided.len() != sides.len()
            || inst.blend.len() != blend.len()
    }) {
        return Err(
            "inconsistent material arrays: instances disagree on slot-array length".to_string(),
        );
    }
    Ok(())
}

fn linear_scales_from_instance(
    instances: &[Value],
    rows: &[usize],
    inst: &Inst,
) -> Result<[f64; 3], String> {
    let Some(position) = rows.iter().find(|&&index| {
        instances[index].get("instance").and_then(Value::as_i64) == Some(inst.local)
            && instances[index].get("actor").and_then(Value::as_str) == Some(inst.actor.as_str())
    }) else {
        return Err("missing matrix row for instance".to_string());
    };
    let matrix = parse_matrix(&instances[*position], *position)?;
    linear_scales(&matrix)
}

fn parse_matrix(value: &Value, index: usize) -> Result<[f64; 16], String> {
    let numbers = value
        .get("matrix")
        .and_then(Value::as_array)
        .ok_or_else(|| format!("instance {index} matrix is missing"))?;
    if numbers.len() != 16 {
        return Err(format!("instance {index} matrix does not have 16 numbers"));
    }
    let mut matrix = [0.0; 16];
    for (offset, number) in numbers.iter().enumerate() {
        let value = number
            .as_f64()
            .ok_or_else(|| format!("instance {index} matrix[{offset}] is not a number"))?;
        if !value.is_finite() {
            return Err(format!("instance {index} matrix[{offset}] is not finite"));
        }
        matrix[offset] = value;
    }
    Ok(matrix)
}

/// Row-vector UE matrix: the images of the local axes are the first three rows.
/// Their Euclidean norms are the world scales. Reflections have a negative
/// determinant even though those norms are positive, so they are rejected
/// instead of being folded into the thickness measure.
fn linear_scales(matrix: &[f64; 16]) -> Result<[f64; 3], String> {
    if matrix.iter().any(|value| !value.is_finite())
        || !(matrix[3].abs() <= 1e-6
            && matrix[7].abs() <= 1e-6
            && matrix[11].abs() <= 1e-6
            && (matrix[15] - 1.0).abs() <= 1e-6)
    {
        return Err("non-finite or non-affine matrix".to_string());
    }
    let rows = [
        [matrix[0], matrix[1], matrix[2]],
        [matrix[4], matrix[5], matrix[6]],
        [matrix[8], matrix[9], matrix[10]],
    ];
    let norms = [
        length(rows[0]),
        length(rows[1]),
        length(rows[2]),
    ];
    if norms.iter().any(|norm| !norm.is_finite() || *norm <= 1e-8) {
        return Err("singular scale".to_string());
    }
    for i in 0..3 {
        for j in (i + 1)..3 {
            let dot = (rows[i][0] * rows[j][0] + rows[i][1] * rows[j][1] + rows[i][2] * rows[j][2]).abs();
            if dot > 1e-4 * norms[i] * norms[j] {
                return Err("sheared matrix".to_string());
            }
        }
    }
    let det = scalar_triple(rows[0], rows[1], rows[2]);
    let product = norms[0] * norms[1] * norms[2];
    if !(det.is_finite() && det > 1e-6 * product) {
        if det < 0.0 {
            return Err("reflection".to_string());
        }
        return Err("singular scale".to_string());
    }
    Ok(norms)
}

fn length(row: [f64; 3]) -> f64 {
    (row[0] * row[0] + row[1] * row[1] + row[2] * row[2]).sqrt()
}

fn scalar_triple(a: [f64; 3], b: [f64; 3], c: [f64; 3]) -> f64 {
    a[0] * (b[1] * c[2] - b[2] * c[1])
        + a[1] * (b[2] * c[0] - b[0] * c[2])
        + a[2] * (b[0] * c[1] - b[1] * c[0])
}

fn ensure_lod(cache: &mut HashMap<String, Result<Parsed, String>>, folder: &Path, lod: &LodInfo) {
    if cache.contains_key(&lod.file) {
        return;
    }
    let loaded = fs::read(folder.join(&lod.file))
        .map_err(|err| format!("failed to read: {err}"))
        .and_then(|bytes| parse_cdy2(&bytes));
    cache.insert(lod.file.clone(), loaded);
}

fn slot_failure(
    slot: usize,
    proofs: &[(&LodInfo, &Parsed)],
    instances: &[Inst],
    max_cm: f64,
) -> Option<String> {
    if let Some(reason) = material_slot_failure(slot, instances) {
        return Some(format!("slot {slot}: {reason}"));
    }
    for (lod, proof) in proofs {
        let triangles: Vec<&Triangle> = proof
            .triangles
            .iter()
            .filter(|triangle| triangle.slot == slot)
            .collect();
        if triangles.is_empty() {
            return Some(format!(
                "slot {slot}: missing from LOD {}; a dropped LOD is not a success",
                lod.level
            ));
        }
        for triangle in triangles {
            if triangle.degenerate {
                return Some(format!("slot {slot}: LOD {} degenerate triangle", lod.level));
            }
            let Some(shell_index) = triangle.shell else {
                return Some(format!(
                    "slot {slot}: LOD {} triangle is not in a proven shell",
                    lod.level
                ));
            };
            let shell = &proof.shells[shell_index];
            if !shell.geometric {
                return Some(format!("slot {slot}: LOD {} {}", lod.level, shell.reason));
            }
            for inst in instances {
                let thickness = min_axis_thickness(shell.extents, inst.scales);
                if !(thickness.is_finite() && thickness <= max_cm) {
                    return Some(format!(
                        "slot {slot}: LOD {} shell thickness {thickness:.4}cm exceeds {max_cm}cm at {}",
                        lod.level,
                        inst.place()
                    ));
                }
            }
        }
    }
    None
}

fn material_slot_failure(slot: usize, instances: &[Inst]) -> Option<String> {
    let mut names = Vec::with_capacity(instances.len());
    for inst in instances {
        if inst.blend[slot] != 0 {
            return Some(format!(
                "blend mode {} is not opaque on {}",
                inst.blend[slot],
                inst.place()
            ));
        }
        if !inst.two_sided[slot] {
            return Some(format!("not two-sided on {}", inst.place()));
        }
        if inst.materials[slot].is_empty() {
            return Some("empty material".to_string());
        }
        names.push(inst.materials[slot].as_str());
    }
    if names.iter().any(|name| *name != names[0]) {
        return Some("material inconsistency".to_string());
    }
    None
}

fn slot_binding_thickness(slot: usize, proofs: &[(&LodInfo, &Parsed)], instances: &[Inst]) -> f64 {
    let mut binding = 0.0_f64;
    for (_, proof) in proofs {
        for triangle in &proof.triangles {
            if triangle.slot != slot || triangle.degenerate {
                continue;
            }
            let Some(shell_index) = triangle.shell else {
                continue;
            };
            let shell = &proof.shells[shell_index];
            for inst in instances {
                binding = binding.max(min_axis_thickness(shell.extents, inst.scales));
            }
        }
    }
    binding
}

fn min_axis_thickness(extents: [f64; 3], scales: [f64; 3]) -> f64 {
    extents
        .iter()
        .zip(scales)
        .map(|(extent, scale)| extent * scale)
        .fold(f64::INFINITY, f64::min)
}

struct Parsed {
    // Read by the synthetic weld tests; the CLI report does not dump vertex tables.
    #[cfg_attr(not(test), allow(dead_code))]
    unique_vertices: usize,
    triangles: Vec<Triangle>,
    shells: Vec<Shell>,
    sha256: String,
    native_ids: Vec<u32>,
    native_ids_sha256: String,
}

struct Triangle {
    slot: usize,
    degenerate: bool,
    shell: Option<usize>,
}

struct Shell {
    extents: [f64; 3],
    // Read by the far-origin and orientation tests; not copied into the report.
    #[cfg_attr(not(test), allow(dead_code))]
    volume: f64,
    geometric: bool,
    reason: String,
}

fn parse_cdy2(bytes: &[u8]) -> Result<Parsed, String> {
    if bytes.len() < 12 {
        return Err("CDY2 header is truncated".to_string());
    }
    let magic = u32_at(bytes, 0)?;
    if magic != CDY2_MAGIC {
        return Err(format!("CDY2 magic mismatch: {magic:#x}"));
    }
    let nv = u32_at(bytes, 4)? as usize;
    let nt = u32_at(bytes, 8)? as usize;
    let expected = expected_len(nv, nt).ok_or_else(|| "CDY2 declared size overflows".to_string())?;
    if bytes.len() != expected {
        return Err(format!(
            "CDY2 length {} != {expected}; refusing truncated or padded bytes",
            bytes.len()
        ));
    }
    let mut points = Vec::with_capacity(nv);
    for index in 0..nv {
        let mut point = [0.0_f32; 3];
        for axis in 0..3 {
            point[axis] = f32::from_bits(u32_at(bytes, 12 + index * 12 + axis * 4)?);
            if !point[axis].is_finite() {
                return Err(format!("non-finite position at vertex {index}"));
            }
        }
        points.push(point);
    }
    let index_at = 12 + nv * 12;
    let mut corners = Vec::with_capacity(nt);
    for index in 0..nt {
        let mut triangle = [0_usize; 3];
        for corner in 0..3 {
            let vertex = u32_at(bytes, index_at + index * 12 + corner * 4)?;
            if vertex as usize >= nv {
                return Err(format!("triangle {index} index {vertex} is outside 0..{nv}"));
            }
            triangle[corner] = vertex as usize;
        }
        corners.push(triangle);
    }
    let ids_at = index_at + nt * 12;
    let mut native_ids = Vec::with_capacity(nt);
    for index in 0..nt {
        native_ids.push(u32_at(bytes, ids_at + index * 4)?);
    }
    let slots_at = ids_at + nt * 4;
    let mut slots = Vec::with_capacity(nt);
    for index in 0..nt {
        slots.push(u32_at(bytes, slots_at + index * 4)? as usize);
    }
    debug_assert_eq!(slots_at + nt * 4, bytes.len());

    let (welded, unique_positions) = weld_positions(&points);
    let mut triangles = Vec::with_capacity(nt);
    let mut welded_corners = Vec::with_capacity(nt);
    let mut degenerate = Vec::with_capacity(nt);
    for index in 0..nt {
        let ids = [
            welded[corners[index][0]],
            welded[corners[index][1]],
            welded[corners[index][2]],
        ];
        let collapsed = ids[0] == ids[1] || ids[1] == ids[2] || ids[2] == ids[0];
        let flat = !collapsed && cross_length_squared(unique_positions[ids[0]], unique_positions[ids[1]], unique_positions[ids[2]]) <= 1e-20;
        let is_degenerate = collapsed || flat;
        degenerate.push(is_degenerate);
        welded_corners.push(ids);
        triangles.push(Triangle {
            slot: slots[index],
            degenerate: is_degenerate,
            shell: None,
        });
    }
    let shells = build_shells(&welded_corners, &degenerate, &unique_positions, &mut triangles);
    Ok(Parsed {
        unique_vertices: unique_positions.len(),
        triangles,
        shells,
        sha256: hex_sha256(bytes),
        native_ids_sha256: hash_native_ids(&native_ids),
        native_ids,
    })
}

fn expected_len(nv: usize, nt: usize) -> Option<usize> {
    nv.checked_mul(12)?
        .checked_add(nt.checked_mul(20)?)?
        .checked_add(12)
}

fn u32_at(bytes: &[u8], offset: usize) -> Result<u32, String> {
    let slice = bytes
        .get(offset..offset + 4)
        .ok_or_else(|| format!("CDY2 read past end at {offset}"))?;
    Ok(u32::from_le_bytes(slice.try_into().unwrap()))
}

fn canon_bits(value: f32) -> u32 {
    let bits = value.to_bits();
    if bits == 0x8000_0000 { 0 } else { bits }
}

fn weld_positions(points: &[[f32; 3]]) -> (Vec<usize>, Vec<[f64; 3]>) {
    let mut map: HashMap<(u32, u32, u32), usize> = HashMap::new();
    let mut welded = Vec::with_capacity(points.len());
    let mut unique = Vec::new();
    for point in points {
        let key = (canon_bits(point[0]), canon_bits(point[1]), canon_bits(point[2]));
        let id = if let Some(id) = map.get(&key) {
            *id
        } else {
            let id = unique.len();
            unique.push([
                f32::from_bits(key.0) as f64,
                f32::from_bits(key.1) as f64,
                f32::from_bits(key.2) as f64,
            ]);
            map.insert(key, id);
            id
        };
        welded.push(id);
    }
    (welded, unique)
}

fn cross_length_squared(a: [f64; 3], b: [f64; 3], c: [f64; 3]) -> f64 {
    let ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
    let ac = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
    let cross = [
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    ];
    cross[0] * cross[0] + cross[1] * cross[1] + cross[2] * cross[2]
}

fn build_shells(
    corners: &[[usize; 3]],
    degenerate: &[bool],
    positions: &[[f64; 3]],
    triangles: &mut [Triangle],
) -> Vec<Shell> {
    let count = corners.len();
    let mut parent: Vec<usize> = (0..count).collect();
    let mut edges: HashMap<(usize, usize), Vec<(usize, i32)>> = HashMap::new();
    for (index, triangle) in corners.iter().enumerate() {
        if degenerate[index] {
            continue;
        }
        for corner in 0..3 {
            let start = triangle[corner];
            let end = triangle[(corner + 1) % 3];
            let (key, sign) = if start < end {
                ((start, end), 1)
            } else {
                ((end, start), -1)
            };
            edges.entry(key).or_default().push((index, sign));
        }
    }
    for uses in edges.values() {
        if let Some(&(first, _)) = uses.first() {
            for &(other, _) in uses.iter().skip(1) {
                union(&mut parent, first, other);
            }
        }
    }

    let mut shell_of_root: HashMap<usize, usize> = HashMap::new();
    let mut members: Vec<Vec<usize>> = Vec::new();
    for index in 0..count {
        if degenerate[index] {
            continue;
        }
        let root = find(&mut parent, index);
        let shell = *shell_of_root.entry(root).or_insert_with(|| {
            members.push(Vec::new());
            members.len() - 1
        });
        members[shell].push(index);
        triangles[index].shell = Some(shell);
    }

    let mut issue = vec![0_u8; members.len()];
    for uses in edges.values() {
        let kind = if uses.len() > 2 {
            3
        } else if uses.len() != 2 {
            2
        } else if uses[0].1 + uses[1].1 != 0 {
            1
        } else {
            0
        };
        if kind > 0 {
            if let Some(shell) = triangles[uses[0].0].shell {
                issue[shell] = issue[shell].max(kind);
            }
        }
    }

    members
        .iter()
        .enumerate()
        .map(|(index, member)| {
            let (extents, volume) = shell_measure(member, corners, positions);
            let (geometric, reason) = if issue[index] == 3 {
                (false, "nonmanifold edge".to_string())
            } else if issue[index] == 2 {
                (false, "open edge".to_string())
            } else if issue[index] == 1 {
                (false, "inconsistent winding".to_string())
            } else if outward_volume(volume, extents) {
                (true, String::new())
            } else {
                (false, "reversed or zero volume".to_string())
            };
            Shell {
                extents,
                volume,
                geometric,
                reason,
            }
        })
        .collect()
}

fn find(parent: &mut [usize], mut index: usize) -> usize {
    let mut root = index;
    while parent[root] != root {
        root = parent[root];
    }
    while parent[index] != root {
        let next = parent[index];
        parent[index] = root;
        index = next;
    }
    root
}

fn union(parent: &mut [usize], a: usize, b: usize) {
    let a = find(parent, a);
    let b = find(parent, b);
    if a != b {
        parent[a] = b;
    }
}

/// Signed volume from one shell vertex. Using the world origin cancels at city
/// scale (~1e7 cm) and can flip the Engine Cube sign.
fn shell_measure(member: &[usize], corners: &[[usize; 3]], positions: &[[f64; 3]]) -> ([f64; 3], f64) {
    let origin = positions[corners[member[0]][0]];
    let mut low = [f64::INFINITY; 3];
    let mut high = [f64::NEG_INFINITY; 3];
    let mut volume = 0.0;
    for &index in member {
        let triangle = corners[index];
        let mut shifted = [[0.0; 3]; 3];
        for corner in 0..3 {
            let position = positions[triangle[corner]];
            for axis in 0..3 {
                low[axis] = low[axis].min(position[axis]);
                high[axis] = high[axis].max(position[axis]);
                shifted[corner][axis] = position[axis] - origin[axis];
            }
        }
        volume += scalar_triple(shifted[0], shifted[1], shifted[2]);
    }
    let extents = [high[0] - low[0], high[1] - low[1], high[2] - low[2]];
    (extents, volume / 6.0)
}

fn outward_volume(volume: f64, extents: [f64; 3]) -> bool {
    if !volume.is_finite() {
        return false;
    }
    let extent = extents.iter().copied().fold(0.0, f64::max);
    if !(extent > 0.0) {
        return false;
    }
    volume < -1e-9 * extent * extent * extent
}

fn hex_sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn hash_native_ids(ids: &[u32]) -> String {
    let mut hasher = Sha256::new();
    for id in ids {
        hasher.update(id.to_le_bytes());
    }
    format!("{:x}", hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static TEMP_SEQ: AtomicU64 = AtomicU64::new(0);

    struct TempDir(PathBuf);
    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    struct MeshIn {
        asset: &'static str,
        lods: Vec<(i64, Vec<u8>)>,
    }

    struct RowIn {
        actor: String,
        component: String,
        mesh: usize,
        instance: i64,
        matrix: [f64; 16],
        materials: Vec<String>,
        two_sided: Vec<bool>,
        blend: Vec<i64>,
    }

    fn row(
        actor: &str,
        component: &str,
        mesh: usize,
        instance: i64,
        matrix: [f64; 16],
        materials: &[&str],
        two_sided: &[bool],
        blend: &[i64],
    ) -> RowIn {
        RowIn {
            actor: actor.to_string(),
            component: component.to_string(),
            mesh,
            instance,
            matrix,
            materials: materials.iter().map(|value| (*value).to_string()).collect(),
            two_sided: two_sided.to_vec(),
            blend: blend.to_vec(),
        }
    }

    fn identity() -> [f64; 16] {
        [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
    }

    fn scale_matrix(x: f64, y: f64, z: f64) -> [f64; 16] {
        [x, 0.0, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, 0.0, z, 0.0, 0.0, 0.0, 0.0, 1.0]
    }

    fn rotated_scale(x: f64, y: f64, z: f64, degrees: f64) -> [f64; 16] {
        let (sin, cos) = degrees.to_radians().sin_cos();
        [
            x * cos,
            x * sin,
            0.0,
            0.0,
            y * -sin,
            y * cos,
            0.0,
            0.0,
            0.0,
            0.0,
            z,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
        ]
    }

    fn push_u32(bytes: &mut Vec<u8>, value: u32) {
        bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn push_f32(bytes: &mut Vec<u8>, value: f32) {
        bytes.extend_from_slice(&value.to_le_bytes());
    }

    fn encode_cdy2(verts: &[[f32; 3]], tris: &[[u32; 3]], slots: &[u32], ids: &[u32]) -> Vec<u8> {
        assert_eq!(tris.len(), slots.len());
        assert_eq!(tris.len(), ids.len());
        let mut bytes = Vec::new();
        push_u32(&mut bytes, CDY2_MAGIC);
        push_u32(&mut bytes, verts.len() as u32);
        push_u32(&mut bytes, tris.len() as u32);
        for vertex in verts {
            for value in vertex {
                push_f32(&mut bytes, *value);
            }
        }
        for triangle in tris {
            for index in triangle {
                push_u32(&mut bytes, *index);
            }
        }
        for id in ids {
            push_u32(&mut bytes, *id);
        }
        for slot in slots {
            push_u32(&mut bytes, *slot);
        }
        bytes
    }

    fn box_parts(min: [f32; 3], max: [f32; 3]) -> ([[f32; 3]; 8], [[u32; 3]; 12]) {
        let [x0, y0, z0] = min;
        let [x1, y1, z1] = max;
        let vertices = [
            [x0, y0, z0],
            [x1, y0, z0],
            [x0, y1, z0],
            [x1, y1, z0],
            [x0, y0, z1],
            [x1, y0, z1],
            [x0, y1, z1],
            [x1, y1, z1],
        ];
        // Inward mathematical winding. Its signed volume is negative, which is
        // the native Engine Cube orientation used by city-solid-check.
        let triangles = [
            [0, 3, 2],
            [0, 1, 3],
            [4, 7, 5],
            [4, 6, 7],
            [0, 5, 1],
            [0, 4, 5],
            [2, 7, 6],
            [2, 3, 7],
            [0, 6, 4],
            [0, 2, 6],
            [1, 7, 3],
            [1, 5, 7],
        ];
        (vertices, triangles)
    }

    fn box_bytes(min: [f32; 3], max: [f32; 3], slot: u32, id_base: u32) -> Vec<u8> {
        let (vertices, triangles) = box_parts(min, max);
        let slots = [slot; 12];
        let ids: Vec<u32> = (0..12).map(|index| id_base + index).collect();
        encode_cdy2(&vertices, &triangles, &slots, &ids)
    }

    fn reversed_box_bytes(min: [f32; 3], max: [f32; 3]) -> Vec<u8> {
        let (vertices, mut triangles) = box_parts(min, max);
        for triangle in &mut triangles {
            triangle.swap(1, 2);
        }
        encode_cdy2(&vertices, &triangles, &[0; 12], &(0..12).collect::<Vec<_>>())
    }

    fn open_box_bytes(min: [f32; 3], max: [f32; 3], slots: &[u32]) -> Vec<u8> {
        let (vertices, triangles) = box_parts(min, max);
        let keep = 11;
        encode_cdy2(
            &vertices,
            &triangles[..keep],
            &slots[..keep],
            &(0..keep as u32).collect::<Vec<_>>(),
        )
    }

    fn tet_bytes(flip: bool) -> Vec<u8> {
        let vertices = [
            [0.0, 0.0, 0.0],
            [100.0, 0.0, 0.0],
            [0.0, 100.0, 0.0],
            [0.0, 0.0, 100.0],
        ];
        let mut triangles = [[0, 1, 2], [0, 3, 1], [0, 2, 3], [1, 3, 2]];
        if flip {
            for triangle in &mut triangles {
                triangle.swap(1, 2);
            }
        }
        encode_cdy2(&vertices, &triangles, &[0; 4], &[11, 12, 13, 14])
    }

    fn shifted_box(offset: [f32; 3], size: [f32; 3], slot: u32) -> (Vec<[f32; 3]>, Vec<[u32; 3]>, Vec<u32>) {
        let (vertices, triangles) = box_parts(
            offset,
            [
                offset[0] + size[0],
                offset[1] + size[1],
                offset[2] + size[2],
            ],
        );
        (
            vertices.to_vec(),
            triangles.to_vec(),
            vec![slot; triangles.len()],
        )
    }

    fn combine(mut parts: Vec<(Vec<[f32; 3]>, Vec<[u32; 3]>, Vec<u32>)>) -> Vec<u8> {
        let mut vertices = Vec::new();
        let mut triangles = Vec::new();
        let mut slots = Vec::new();
        for (part_vertices, part_triangles, part_slots) in &mut parts {
            let base = vertices.len() as u32;
            vertices.append(part_vertices);
            for triangle in part_triangles.iter() {
                triangles.push([triangle[0] + base, triangle[1] + base, triangle[2] + base]);
            }
            slots.append(part_slots);
        }
        let ids: Vec<u32> = (0..triangles.len() as u32).map(|index| 100 + index).collect();
        encode_cdy2(&vertices, &triangles, &slots, &ids)
    }

    fn evaluate(meshes: &[MeshIn], rows: &[RowIn], keys: &[&str], max_cm: Option<f64>) -> Result<Value, String> {
        let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let seq = TEMP_SEQ.fetch_add(1, Ordering::Relaxed);
        let dir = TempDir(std::env::temp_dir().join(format!(
            "ok-prop-solid-{}-{seq}-{nanos}",
            std::process::id()
        )));
        fs::create_dir_all(&dir.0).unwrap();
        let sentinel = b"{\"actors\":[{\"label\":\"INVENTORY_SENTINEL_DO_NOT_ECHO\",\"building_floor\":true}]}";
        fs::write(dir.0.join("building-floor-inventory.json"), sentinel).unwrap();
        let mut mesh_json = Vec::new();
        for (index, mesh) in meshes.iter().enumerate() {
            let mut lods = Vec::new();
            for (lod_index, (level, bytes)) in mesh.lods.iter().enumerate() {
                let file = format!("mesh-{index}-lod-{lod_index}.cdy2");
                fs::write(dir.0.join(&file), bytes).unwrap();
                lods.push(json!({"lod": level, "file": file, "triangles": 0}));
            }
            mesh_json.push(json!({"asset": mesh.asset, "lods": lods}));
        }
        let instance_json: Vec<Value> = rows
            .iter()
            .map(|row| {
                json!({
                    "actor": row.actor,
                    "component": row.component,
                    "key": format!("{}::{}", row.actor, row.component),
                    "mesh": row.mesh,
                    "instance": row.instance,
                    "matrix": row.matrix.to_vec(),
                    "materials": row.materials,
                    "two_sided_by_slot": row.two_sided,
                    "blend_modes": row.blend
                })
            })
            .collect();
        let scene = json!({
            "format": "CDY2",
            "meshes": mesh_json,
            "instances": instance_json
        });
        fs::write(dir.0.join("scene.json"), serde_json::to_vec(&scene).unwrap()).unwrap();
        let mut selection = json!({"components": keys});
        if let Some(max_cm) = max_cm {
            selection["max_solid_thickness_cm"] = json!(max_cm);
        }
        let result = prepare(&dir.0, &selection);
        assert_eq!(
            fs::read(dir.0.join("building-floor-inventory.json")).unwrap(),
            sentinel,
            "building-floor inventory must stay untouched"
        );
        if let Ok(report) = &result {
            let text = serde_json::to_string(report).unwrap();
            assert!(!text.contains("INVENTORY_SENTINEL_DO_NOT_ECHO"));
            assert!(!text.contains("building_floor"));
            assert_eq!(report["status"], "prepared_requires_native_validation");
            assert_eq!(report["claims"]["material_or_map_changes_applied"], false);
            assert_eq!(report["claims"]["z_fighting_resolved"], false);
            assert_eq!(report["claims"]["original_assets_or_materials_edited"], false);
            assert_eq!(report["inventory_modified"], false);
            assert_eq!(
                report["geometry_transforms_instances_collisions_or_bindings_changed"],
                false
            );
            let checks = report["remaining_native_checks"].as_array().unwrap();
            let joined = checks
                .iter()
                .map(|value| value.as_str().unwrap())
                .collect::<Vec<_>>()
                .join("\n");
            assert!(joined.contains("WPO") && joined.contains("PDO"));
            assert!(joined.to_ascii_lowercase().contains("reverse culling"));
            assert!(joined.to_ascii_lowercase().contains("source hash"));
            assert!(joined.to_ascii_lowercase().contains("component preservation"));
        }
        result
    }

    fn must(meshes: &[MeshIn], rows: &[RowIn], keys: &[&str], max_cm: Option<f64>) -> Value {
        evaluate(meshes, rows, keys, max_cm).unwrap()
    }

    fn proposed<'a>(report: &'a Value, key: &str) -> &'a Value {
        report["components"]
            .as_array()
            .unwrap()
            .iter()
            .find(|value| value["component_key"] == key)
            .unwrap_or_else(|| panic!("missing proposal {key}: {report}"))
    }

    fn parse_error(bytes: &[u8]) -> String {
        match parse_cdy2(bytes) {
            Ok(_) => panic!("expected CDY2 rejection"),
            Err(err) => err,
        }
    }

    fn reasons(report: &Value, key: &str) -> String {
        let entry = report["rejected"]
            .as_array()
            .unwrap()
            .iter()
            .find(|value| value["component_key"] == key)
            .unwrap_or_else(|| panic!("missing rejection {key}: {report}"));
        entry["reasons"]
            .as_array()
            .unwrap()
            .iter()
            .map(|value| value.as_str().unwrap().to_string())
            .collect::<Vec<_>>()
            .join("\n")
    }

    fn absent_from_components(report: &Value, key: &str) {
        assert!(
            report["components"]
                .as_array()
                .unwrap()
                .iter()
                .all(|value| value["component_key"] != key),
            "{key} was proposed: {report}"
        );
    }

    #[test]
    fn closed_outward_box_accepted() {
        let tet = parse_cdy2(&tet_bytes(false)).unwrap();
        assert!(tet.shells[0].geometric);
        assert!(tet.shells[0].volume < 0.0);
        let cube = [0.0, 0.0, 0.0];
        let solid = parse_cdy2(&box_bytes(cube, [100.0, 100.0, 100.0], 0, 1)).unwrap();
        assert_eq!(solid.shells.len(), 1);
        assert!(solid.shells[0].geometric);
        assert!((solid.shells[0].volume + 1_000_000.0).abs() < 1e-3);

        let report = must(
            &[
                MeshIn {
                    asset: "/Game/Tet",
                    lods: vec![(0, tet_bytes(false))],
                },
                MeshIn {
                    asset: "/Game/Cube",
                    lods: vec![(0, box_bytes(cube, [100.0, 100.0, 100.0], 0, 20))],
                },
            ],
            &[
                row("Tet", "SM", 0, -1, identity(), &["MI"], &[true], &[0]),
                row("Cube", "SM", 1, -1, identity(), &["MI"], &[true], &[0]),
            ],
            &["Tet::SM", "Cube::SM"],
            None,
        );
        assert_eq!(proposed(&report, "Tet::SM")["safe_slots"], json!([0]));
        assert_eq!(proposed(&report, "Cube::SM")["safe_slots"], json!([0]));
        assert!((proposed(&report, "Cube::SM")["min_axis_thickness_cm"].as_f64().unwrap() - 100.0).abs() < 1e-6);
        assert_eq!(report["max_solid_thickness_cm"], 100.0);
    }

    #[test]
    fn reversed_box_rejected() {
        let reversed = parse_cdy2(&reversed_box_bytes([0.0, 0.0, 0.0], [100.0, 100.0, 100.0])).unwrap();
        assert!(!reversed.shells[0].geometric);
        assert!(reversed.shells[0].volume > 0.0);
        assert!(reversed.shells[0].reason.contains("reversed"));
        let tet = parse_cdy2(&tet_bytes(true)).unwrap();
        assert!(!tet.shells[0].geometric);

        let report = must(
            &[MeshIn {
                asset: "/Game/Reversed",
                lods: vec![(0, reversed_box_bytes([0.0, 0.0, 0.0], [20.0, 80.0, 80.0]))],
            }],
            &[row("Rev", "SM", 0, -1, identity(), &["MI"], &[true], &[0])],
            &["Rev::SM"],
            None,
        );
        absent_from_components(&report, "Rev::SM");
        assert!(reasons(&report, "Rev::SM").contains("reversed"));
    }

    #[test]
    fn open_face_rejected() {
        let (vertices, triangles) = box_parts([0.0, 0.0, 0.0], [10.0, 40.0, 40.0]);
        let mut slots = [0_u32; 12];
        slots[11] = 1;
        let closed = encode_cdy2(&vertices, &triangles, &slots, &(0..12).collect::<Vec<_>>());
        let closed_proof = parse_cdy2(&closed).unwrap();
        assert!(closed_proof.shells.iter().all(|shell| shell.geometric));
        let open = open_box_bytes([0.0, 0.0, 0.0], [10.0, 40.0, 40.0], &[0; 12]);
        assert!(!parse_cdy2(&open).unwrap().shells[0].geometric);

        let report = must(
            &[
                MeshIn {
                    asset: "/Game/MixedClosed",
                    lods: vec![(0, closed)],
                },
                MeshIn {
                    asset: "/Game/Open",
                    lods: vec![(0, open_box_bytes([0.0, 0.0, 0.0], [10.0, 40.0, 40.0], &{
                        let mut slots = [0_u32; 12];
                        for slot in slots.iter_mut().take(6) {
                            *slot = 0;
                        }
                        for slot in slots.iter_mut().skip(6) {
                            *slot = 1;
                        }
                        slots
                    }))],
                },
            ],
            &[
                row("Mixed", "SM", 0, -1, identity(), &["A", "B"], &[true, true], &[0, 0]),
                row("Open", "SM", 1, -1, identity(), &["A", "B"], &[true, true], &[0, 0]),
            ],
            &["Mixed::SM", "Open::SM"],
            None,
        );
        let mixed = proposed(&report, "Mixed::SM");
        assert_eq!(mixed["safe_slots"], json!([0, 1]));
        absent_from_components(&report, "Open::SM");
        let text = reasons(&report, "Open::SM");
        assert!(text.contains("open edge"), "{text}");
        assert!(text.contains("slot 0"), "{text}");
    }

    #[test]
    fn nonmanifold_edge_rejected() {
        let (vertices, triangles) = box_parts([0.0, 0.0, 0.0], [10.0, 30.0, 30.0]);
        let mut all = triangles.to_vec();
        all.push(triangles[0]);
        let mut slots = vec![0_u32; 12];
        slots.push(1);
        let ids: Vec<u32> = (0..13).collect();
        let bytes = encode_cdy2(&vertices, &all, &slots, &ids);
        let proof = parse_cdy2(&bytes).unwrap();
        assert!(proof.shells.iter().any(|shell| shell.reason.contains("nonmanifold")));
        let report = must(
            &[MeshIn {
                asset: "/Game/Nonmanifold",
                lods: vec![(0, bytes)],
            }],
            &[row(
                "Join",
                "SM",
                0,
                -1,
                identity(),
                &["A", "B"],
                &[true, true],
                &[0, 0],
            )],
            &["Join::SM"],
            None,
        );
        absent_from_components(&report, "Join::SM");
        let text = reasons(&report, "Join::SM");
        assert!(text.contains("nonmanifold"), "{text}");
        assert!(text.contains("slot 0"), "{text}");
    }

    #[test]
    fn degenerate_and_tiny_exact_gap_not_welded() {
        let (vertices, triangles) = box_parts([0.0, 0.0, 0.0], [10.0, 20.0, 20.0]);
        let mut degenerate_vertices = vertices.to_vec();
        degenerate_vertices.push(vertices[0]);
        let mut degenerate_tris = triangles.to_vec();
        degenerate_tris.push([8, 8, 1]);
        let mut slots = vec![0_u32; 12];
        slots.push(1);
        let degenerate = encode_cdy2(
            &degenerate_vertices,
            &degenerate_tris,
            &slots,
            &(0..13).collect::<Vec<_>>(),
        );
        let degenerate_proof = parse_cdy2(&degenerate).unwrap();
        assert!(degenerate_proof.triangles[12].degenerate);
        assert_eq!(degenerate_proof.unique_vertices, 8);

        let mut gap_vertices = vertices.to_vec();
        gap_vertices.push([0.004, 0.0, 0.0]);
        let mut gap_tris = triangles.to_vec();
        // 0.004 cm is inside the old 0.01 cm quantizer bin, but the bits differ.
        gap_tris[0] = [8, triangles[0][1], triangles[0][2]];
        let gap = encode_cdy2(&gap_vertices, &gap_tris, &[0; 12], &(0..12).collect::<Vec<_>>());
        let gap_proof = parse_cdy2(&gap).unwrap();
        assert_eq!(gap_proof.unique_vertices, 9);
        assert!(gap_proof.shells.iter().all(|shell| !shell.geometric));

        let mut welded_vertices = vertices;
        welded_vertices[0] = [-0.0, 0.0, 0.0];
        let mut split_vertices = welded_vertices.to_vec();
        split_vertices.push([-0.0, -0.0, 0.0]);
        let mut split_tris = triangles.to_vec();
        split_tris[0] = [8, triangles[0][1], triangles[0][2]];
        let welded = encode_cdy2(&split_vertices, &split_tris, &[0; 12], &(0..12).collect::<Vec<_>>());
        let welded_proof = parse_cdy2(&welded).unwrap();
        assert_eq!(welded_proof.unique_vertices, 8);
        assert!(welded_proof.shells[0].geometric, "{}", welded_proof.shells[0].reason);
        assert!(welded_proof.shells[0].volume < 0.0);

        let report = must(
            &[
                MeshIn {
                    asset: "/Game/Degenerate",
                    lods: vec![(0, degenerate)],
                },
                MeshIn {
                    asset: "/Game/Gap",
                    lods: vec![(0, gap)],
                },
                MeshIn {
                    asset: "/Game/Weld",
                    lods: vec![(0, welded)],
                },
            ],
            &[
                row("Deg", "SM", 0, -1, identity(), &["A", "B"], &[true, true], &[0, 0]),
                row("Gap", "SM", 1, -1, identity(), &["A"], &[true], &[0]),
                row("Weld", "SM", 2, -1, identity(), &["A"], &[true], &[0]),
            ],
            &["Deg::SM", "Gap::SM", "Weld::SM"],
            None,
        );
        let degenerate_row = proposed(&report, "Deg::SM");
        assert_eq!(degenerate_row["safe_slots"], json!([0]));
        assert!(degenerate_row["diagnostics"]
            .as_array()
            .unwrap()
            .iter()
            .any(|value| value.as_str().unwrap().contains("degenerate")));
        absent_from_components(&report, "Gap::SM");
        assert!(reasons(&report, "Gap::SM").contains("open edge"));
        assert_eq!(proposed(&report, "Weld::SM")["safe_slots"], json!([0]));
    }

    #[test]
    fn opaque_masked_filtering() {
        let solid = combine(vec![
            shifted_box([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0),
            shifted_box([100.0, 0.0, 0.0], [10.0, 20.0, 20.0], 1),
        ]);
        let one = box_bytes([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0, 1);
        let report = must(
            &[
                MeshIn {
                    asset: "/Game/TwoSlots",
                    lods: vec![(0, solid)],
                },
                MeshIn {
                    asset: "/Game/OneSided",
                    lods: vec![(0, one.clone())],
                },
                MeshIn {
                    asset: "/Game/Translucent",
                    lods: vec![(0, one)],
                },
            ],
            &[
                row(
                    "Filter",
                    "SM",
                    0,
                    -1,
                    identity(),
                    &["Opaque", "Masked"],
                    &[true, true],
                    &[0, 1],
                ),
                row("Single", "SM", 1, -1, identity(), &["Opaque"], &[false], &[0]),
                row("Glass", "SM", 2, -1, identity(), &["Glass"], &[true], &[2]),
            ],
            &["Filter::SM", "Single::SM", "Glass::SM"],
            None,
        );
        assert_eq!(proposed(&report, "Filter::SM")["safe_slots"], json!([0]));
        let diagnostics = proposed(&report, "Filter::SM")["diagnostics"].to_string();
        assert!(diagnostics.contains("not opaque"), "{diagnostics}");
        absent_from_components(&report, "Single::SM");
        assert!(reasons(&report, "Single::SM").contains("not two-sided"));
        absent_from_components(&report, "Glass::SM");
        assert!(reasons(&report, "Glass::SM").contains("not opaque"));
    }

    #[test]
    fn unsafe_lod_rejects_slot() {
        let lod0 = combine(vec![
            shifted_box([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0),
            shifted_box([80.0, 0.0, 0.0], [10.0, 20.0, 20.0], 1),
        ]);
        let lod1 = combine(vec![
            shifted_box([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0),
            {
                let (vertices, triangles, _) =
                    shifted_box([80.0, 0.0, 0.0], [10.0, 20.0, 20.0], 1);
                let keep = triangles.len() - 1;
                (vertices, triangles[..keep].to_vec(), vec![1; keep])
            },
        ]);
        let closed = box_bytes([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0, 3);
        let report = must(
            &[
                MeshIn {
                    asset: "/Game/MultiLod",
                    lods: vec![(0, lod0), (1, lod1)],
                },
                MeshIn {
                    asset: "/Game/Dropped",
                    lods: vec![(0, closed), (1, Vec::new())],
                },
            ],
            &[
                row(
                    "Multi",
                    "SM",
                    0,
                    -1,
                    identity(),
                    &["A", "B"],
                    &[true, true],
                    &[0, 0],
                ),
                row("Drop", "SM", 1, -1, identity(), &["A"], &[true], &[0]),
            ],
            &["Multi::SM", "Drop::SM"],
            None,
        );
        // The empty LOD file is still a declared source LOD. Writing it as an
        // empty byte string makes the parser reject it; the component must not
        // succeed on LOD 0 alone. Replace that setup if the empty file is not
        // created: evaluate always writes the provided bytes.
        assert_eq!(proposed(&report, "Multi::SM")["safe_slots"], json!([0]));
        let diagnostics = proposed(&report, "Multi::SM")["diagnostics"].to_string();
        assert!(diagnostics.contains("slot 1"), "{diagnostics}");
        assert!(diagnostics.contains("LOD 1"), "{diagnostics}");
        assert!(diagnostics.contains("open edge"), "{diagnostics}");
        absent_from_components(&report, "Drop::SM");
        let dropped = reasons(&report, "Drop::SM");
        assert!(dropped.contains("LOD 1"), "{dropped}");
        assert!(!dropped.contains("safe_slots"), "{dropped}");
    }

    #[test]
    fn material_inconsistency_rejected() {
        let bytes = box_bytes([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0, 4);
        let high = box_bytes([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 3, 8);
        let report = must(
            &[
                MeshIn {
                    asset: "/Game/Mat",
                    lods: vec![(0, bytes)],
                },
                MeshIn {
                    asset: "/Game/Range",
                    lods: vec![(0, high)],
                },
            ],
            &[
                row("Mat", "H", 0, 0, identity(), &["MI_A"], &[true], &[0]),
                row("Mat", "H", 0, 1, identity(), &["MI_B"], &[true], &[0]),
                row("Len", "H", 0, 0, identity(), &["MI_A"], &[true], &[0]),
                row("Len", "H", 0, 1, identity(), &["MI_A", "Extra"], &[true, true], &[0, 0]),
                row("Range", "SM", 1, -1, identity(), &["Only"], &[true], &[0]),
            ],
            &["Mat::H", "Len::H", "Range::SM"],
            None,
        );
        absent_from_components(&report, "Mat::H");
        assert!(reasons(&report, "Mat::H").contains("material inconsistency"));
        absent_from_components(&report, "Len::H");
        assert!(reasons(&report, "Len::H").contains("inconsistent material arrays"));
        absent_from_components(&report, "Range::SM");
        assert!(reasons(&report, "Range::SM").contains("outside the material array"));
    }

    #[test]
    fn shared_mesh_different_components_supported() {
        let bytes = box_bytes([0.0, 0.0, 0.0], [10.0, 200.0, 200.0], 0, 9);
        let report = must(
            &[MeshIn {
                asset: "/Game/SharedWall",
                lods: vec![(0, bytes)],
            }],
            &[
                row("Wall", "SM", 0, -1, identity(), &["WallMat"], &[true], &[0]),
                row("Room", "SM", 0, -1, scale_matrix(20.0, 1.0, 1.0), &["WallMat"], &[true], &[0]),
                row(
                    "Decoy",
                    "SM",
                    0,
                    -1,
                    scale_matrix(100.0, 100.0, 100.0),
                    &["WallMat"],
                    &[true],
                    &[0],
                ),
            ],
            &["Wall::SM", "Room::SM"],
            None,
        );
        let wall = proposed(&report, "Wall::SM");
        assert_eq!(wall["source_asset"], "/Game/SharedWall");
        assert_eq!(wall["safe_slots"], json!([0]));
        assert_eq!(report["components"].as_array().unwrap().len(), 1);
        absent_from_components(&report, "Room::SM");
        assert!(reasons(&report, "Room::SM").contains("exceeds"));
        let text = serde_json::to_string(&report).unwrap();
        assert!(!text.contains("Decoy"));
        assert!(!text.contains("edit_asset"));
    }

    #[test]
    fn negative_singular_sheared_transform_rejected() {
        let depth_rows = [
            2.0, 0.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 0.0, 4.0, 0.0, 10.0, 20.0, 30.0, 1.0,
        ];
        assert_eq!(linear_scales(&depth_rows).unwrap(), [2.0, 3.0, 4.0]);
        let mirror = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0];
        assert!(linear_scales(&mirror).unwrap_err().contains("reflection"));
        let singular = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0];
        assert!(linear_scales(&singular).unwrap_err().contains("singular"));
        let shear = [1.0, 0.0, 0.0, 0.0, 0.5, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0];
        assert!(linear_scales(&shear).unwrap_err().contains("sheared"));
        let mut nan_matrix = identity();
        nan_matrix[0] = f64::NAN;
        assert!(linear_scales(&nan_matrix).unwrap_err().contains("finite"));

        let bytes = box_bytes([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0, 15);
        let affine = {
            let mut matrix = identity();
            matrix[15] = 0.0;
            matrix
        };
        let report = must(
            &[MeshIn {
                asset: "/Game/Xform",
                lods: vec![(0, bytes)],
            }],
            &[
                row("Bad", "Mirror", 0, -1, mirror, &["M"], &[true], &[0]),
                row("Bad", "Singular", 0, -1, singular, &["M"], &[true], &[0]),
                row("Bad", "Shear", 0, -1, shear, &["M"], &[true], &[0]),
                row("Bad", "Affine", 0, -1, affine, &["M"], &[true], &[0]),
            ],
            &["Bad::Mirror", "Bad::Singular", "Bad::Shear", "Bad::Affine"],
            None,
        );
        assert!(reasons(&report, "Bad::Mirror").contains("reflection"));
        assert!(reasons(&report, "Bad::Singular").contains("singular"));
        assert!(reasons(&report, "Bad::Shear").contains("sheared"));
        assert!(reasons(&report, "Bad::Affine").contains("affine"));
        assert!(report["components"].as_array().unwrap().is_empty());
    }

    #[test]
    fn rotated_nonuniform_thin_box_accepted() {
        let bytes = box_bytes([0.0, 0.0, 0.0], [10.0, 400.0, 400.0], 0, 30);
        let proper = [-1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0];
        assert!(linear_scales(&proper).is_ok());
        let report = must(
            &[MeshIn {
                asset: "/Game/Thin",
                lods: vec![(0, bytes)],
            }],
            &[
                row("Thin", "Axis", 0, -1, scale_matrix(2.0, 1.0, 1.0), &["M"], &[true], &[0]),
                row(
                    "Thin",
                    "Rot",
                    0,
                    -1,
                    rotated_scale(2.0, 1.0, 1.0, 45.0),
                    &["M"],
                    &[true],
                    &[0],
                ),
                row("Thin", "Spin", 0, -1, proper, &["M"], &[true], &[0]),
            ],
            &["Thin::Axis", "Thin::Rot", "Thin::Spin"],
            None,
        );
        let axis = proposed(&report, "Thin::Axis")["min_axis_thickness_cm"].as_f64().unwrap();
        let rotated = proposed(&report, "Thin::Rot")["min_axis_thickness_cm"].as_f64().unwrap();
        assert!((axis - 20.0).abs() < 1e-4, "{axis}");
        assert!((rotated - axis).abs() < 1e-4, "axis {axis} rotated {rotated}");
        assert_eq!(proposed(&report, "Thin::Rot")["safe_slots"], json!([0]));
        assert!((proposed(&report, "Thin::Spin")["min_axis_thickness_cm"].as_f64().unwrap() - 10.0).abs() < 1e-4);
    }

    #[test]
    fn source_cube_scaled_into_room_rejected() {
        let bytes = box_bytes([0.0, 0.0, 0.0], [100.0, 100.0, 100.0], 0, 40);
        let report = must(
            &[MeshIn {
                asset: "/Game/RoomCube",
                lods: vec![(0, bytes)],
            }],
            &[row(
                "Room",
                "SM",
                0,
                -1,
                scale_matrix(5.0, 5.0, 5.0),
                &["M"],
                &[true],
                &[0],
            )],
            &["Room::SM"],
            None,
        );
        absent_from_components(&report, "Room::SM");
        let text = reasons(&report, "Room::SM");
        assert!(text.contains("500"), "{text}");
        assert!(text.contains("exceeds"), "{text}");
        assert!(text.contains("100"), "{text}");
    }

    #[test]
    fn later_hism_instance_large_or_mirrored_rejects() {
        let bytes = box_bytes([0.0, 0.0, 0.0], [100.0, 100.0, 100.0], 0, 50);
        let mirror = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0];
        let report = must(
            &[MeshIn {
                asset: "/Game/HismCube",
                lods: vec![(0, bytes)],
            }],
            &[
                row("Other", "SM", 0, -1, identity(), &["M"], &[true], &[0]),
                row("Late", "Large", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Late", "Large", 0, 1, scale_matrix(5.0, 5.0, 5.0), &["M"], &[true], &[0]),
                row("Late", "Mirror", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Late", "Mirror", 0, 1, mirror, &["M"], &[true], &[0]),
            ],
            &["Late::Large", "Late::Mirror"],
            None,
        );
        absent_from_components(&report, "Late::Large");
        let large = reasons(&report, "Late::Large");
        assert!(large.contains("hism local index 1"), "{large}");
        assert!(large.contains("500"), "{large}");
        absent_from_components(&report, "Late::Mirror");
        let mirrored = reasons(&report, "Late::Mirror");
        assert!(mirrored.contains("hism local index 1"), "{mirrored}");
        assert!(mirrored.contains("reflection"), "{mirrored}");
        assert!(!serde_json::to_string(&report).unwrap().contains("Other"));
    }

    #[test]
    fn translated_far_origin_mesh_volume_robust() {
        let bytes = box_bytes(
            [10_000_000.0, 10_000_000.0, 10_000_000.0],
            [10_000_100.0, 10_000_100.0, 10_000_100.0],
            0,
            70,
        );
        let proof = parse_cdy2(&bytes).unwrap();
        assert_eq!(proof.shells.len(), 1);
        assert!(
            (proof.shells[0].volume + 1_000_000.0).abs() < 1e-3,
            "volume {}",
            proof.shells[0].volume
        );
        assert!(proof.shells[0].geometric);
        let report = must(
            &[MeshIn {
                asset: "/Game/Far",
                lods: vec![(0, bytes)],
            }],
            &[row("Far", "SM", 0, -1, identity(), &["M"], &[true], &[0])],
            &["Far::SM"],
            None,
        );
        assert_eq!(proposed(&report, "Far::SM")["safe_slots"], json!([0]));
        assert!((proposed(&report, "Far::SM")["min_axis_thickness_cm"].as_f64().unwrap() - 100.0).abs() < 1e-3);
    }

    #[test]
    fn fixture_parses_hism_indexes_and_native_ids() {
        let ids: Vec<u32> = (700..712).collect();
        let (vertices, triangles) = box_parts([0.0, 0.0, 0.0], [10.0, 20.0, 20.0]);
        let bytes = encode_cdy2(&vertices, &triangles, &[0; 12], &ids);
        let mut truncated = bytes.clone();
        truncated.pop();
        assert!(parse_error(&truncated).contains("truncated"));
        let mut padded = bytes.clone();
        padded.push(0);
        assert!(parse_error(&padded).contains("padded"));
        let mut bad_magic = bytes.clone();
        bad_magic[0] = 0x31;
        assert!(parse_error(&bad_magic).contains("magic"));
        let mut bad_index = bytes.clone();
        let index_at = 12 + 8 * 12;
        bad_index[index_at..index_at + 4].copy_from_slice(&99_u32.to_le_bytes());
        assert!(parse_error(&bad_index).contains("outside"));
        let mut non_finite = bytes.clone();
        non_finite[12..16].copy_from_slice(&f32::NAN.to_le_bytes());
        assert!(parse_error(&non_finite).contains("non-finite"));
        let parsed = parse_cdy2(&bytes).unwrap();
        assert_eq!(parsed.native_ids, ids);
        assert_eq!(parsed.native_ids_sha256, hash_native_ids(&ids));

        let other = box_bytes([0.0, 0.0, 0.0], [10.0, 20.0, 20.0], 0, 1);
        let report = must(
            &[
                MeshIn {
                    asset: "/Game/Fixture",
                    lods: vec![(0, bytes.clone())],
                },
                MeshIn {
                    asset: "/Game/OtherMesh",
                    lods: vec![(0, other)],
                },
            ],
            &[
                row("Decoy", "SM", 0, -1, identity(), &["M"], &[true], &[0]),
                row("Good", "HISM", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Good", "HISM", 0, 1, identity(), &["M"], &[true], &[0]),
                row("Gap", "Seq", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Gap", "Seq", 0, 2, identity(), &["M"], &[true], &[0]),
                row("Dup", "Idx", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Dup", "Idx", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Mix", "Row", 0, -1, identity(), &["M"], &[true], &[0]),
                row("Mix", "Row", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Two", "Static", 0, -1, identity(), &["M"], &[true], &[0]),
                row("Two", "Static", 0, -1, identity(), &["M"], &[true], &[0]),
                row("One", "Static", 0, -1, identity(), &["M"], &[true], &[0]),
                row("Split", "Mesh", 0, 0, identity(), &["M"], &[true], &[0]),
                row("Split", "Mesh", 1, 1, identity(), &["M"], &[true], &[0]),
            ],
            &[
                "Good::HISM",
                "Gap::Seq",
                "Dup::Idx",
                "Mix::Row",
                "Two::Static",
                "One::Static",
                "Split::Mesh",
                "Missing::Nope",
            ],
            None,
        );
        let good = proposed(&report, "Good::HISM");
        assert_eq!(good["instance_count"], 2);
        assert_eq!(good["local_indexes"], json!([0, 1]));
        assert_eq!(good["safe_slots"], json!([0]));
        assert_eq!(good["source_lods"][0]["sha256"], hex_sha256(&bytes));
        assert_eq!(good["source_lods"][0]["native_id_count"], 12);
        assert_eq!(good["source_lods"][0]["native_ids_sha256"], hash_native_ids(&ids));
        assert_eq!(proposed(&report, "One::Static")["local_indexes"], json!([-1]));
        assert_eq!(proposed(&report, "One::Static")["instance_count"], 1);
        assert!(reasons(&report, "Gap::Seq").contains("incomplete hism"));
        assert!(reasons(&report, "Dup::Idx").contains("duplicate hism"));
        assert!(reasons(&report, "Mix::Row").contains("mixed ordinary"));
        assert!(reasons(&report, "Two::Static").contains("exactly one"));
        assert!(reasons(&report, "Split::Mesh").contains("inconsistent mesh"));
        assert!(reasons(&report, "Missing::Nope").contains("absent"));
        let text = serde_json::to_string(&report).unwrap();
        assert!(!text.contains("Decoy"));
        assert!(!text.contains("scene.json"));
    }

    #[test]
    fn thickness_above_100_is_rejected() {
        let err = prepare(
            Path::new("unused-scene"),
            &json!({"components": ["A::B"], "max_solid_thickness_cm": 101}),
        )
        .unwrap_err();
        assert!(err.contains("100"), "{err}");
        assert!(prepare(
            Path::new("unused-scene"),
            &json!({"components": ["A::B"], "max_solid_thickness_cm": 0}),
        )
        .unwrap_err()
        .contains("100"));
        let duplicate = prepare(
            Path::new("unused-scene"),
            &json!({"components": ["A::B", "A::B"]}),
        )
        .unwrap_err();
        assert!(duplicate.contains("duplicate"), "{duplicate}");
    }
}
