//! Universal character card plugin compatibility (`KKEx` extended data):
//! - `com.deathweasel.bepinex.eyecontrol`: `EyeOpenMax` + `DisableBlinking`
//! - `org.njaecha.plugins.editfangs`: 42-vertex `cf_O_canine` procedural fang mesh edit
//! - `nakay.kk.ClothingBlendShape`: `ChaClothesBlendShape` component defaults (`20.0`) + saved `ClothesDataSet`
//! - `madevil.kk.ass` (`AccStateSync`) & `Accessory_States`: clothing-state & custom-group accessory/renderer triggers

use std::collections::{HashMap, HashSet};
use std::io::Cursor;
use rmpv::Value;

use crate::card::CardInfo;
use crate::unity::ExtractedMesh;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct ClothesBlendShapeSlot {
    pub item_name: String,
    pub renderers: Vec<i64>,
    pub shape_index: usize,
}

#[derive(Debug, Clone, Default)]
pub struct AccTriggerProperty {
    pub coordinate: i32,
    pub slot: i32,
    pub ref_kind: i32,
    pub ref_state: i32,
    pub visible: bool,
    pub priority: i32,
    pub render_show: HashSet<String>,
    pub render_hide: HashSet<String>,
}

#[derive(Debug, Clone, Default)]
pub struct AccTriggerGroup {
    pub coordinate: i32,
    pub kind: i32,
    pub state: i32,
    pub startup: i32,
}

#[derive(Debug, Clone, Default)]
pub struct AccStateSyncData {
    pub triggers: Vec<AccTriggerProperty>,
    pub groups: Vec<AccTriggerGroup>,
}

impl AccStateSyncData {
    pub fn is_empty(&self) -> bool {
        self.triggers.is_empty()
    }

    pub fn has_render_show_for(&self, outfit: i32, slot: i32, renderer_name: &str) -> bool {
        self.triggers.iter().any(|t| {
            t.coordinate == outfit
                && t.slot == slot
                && t.render_show.iter().any(|n| n == renderer_name || n.eq_ignore_ascii_case(renderer_name))
        })
    }

    pub fn any_render_show_in_slot(&self, outfit: i32, slot: i32) -> bool {
        self.triggers
            .iter()
            .any(|t| t.coordinate == outfit && t.slot == slot && !t.render_show.is_empty())
    }
}

fn plugin_version(kv: &Value) -> i32 {
    kv.as_array()
        .and_then(|a| a.first())
        .and_then(val_i32)
        .unwrap_or(0)
}

fn plugin_data_map(kv: &Value) -> Option<&[(Value, Value)]> {
    kv.as_array().and_then(|a| a.get(1)).and_then(Value::as_map).map(|v| v.as_slice())
}

fn map_lookup<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a Value> {
    map.iter()
        .find(|(k, _)| k.as_str().is_some_and(|s| s == key || s.eq_ignore_ascii_case(key)))
        .map(|(_, v)| v)
}

fn val_i32(v: &Value) -> Option<i32> {
    v.as_i64()
        .map(|n| n as i32)
        .or_else(|| v.as_u64().map(|n| n as i32))
        .or_else(|| v.as_f64().map(|n| n as i32))
}

fn val_f32(v: &Value) -> Option<f32> {
    v.as_f64()
        .map(|n| n as f32)
        .or_else(|| v.as_i64().map(|n| n as f32))
        .or_else(|| v.as_u64().map(|n| n as f32))
}

fn val_bool(v: &Value) -> Option<bool> {
    v.as_bool().or_else(|| val_i32(v).map(|n| n != 0))
}

fn decode_nested_msgpack(v: &Value) -> Option<Value> {
    if let Some(bytes) = v.as_slice() {
        let mut cur = Cursor::new(bytes);
        rmpv::decode::read_value(&mut cur).ok()
    } else {
        Some(v.clone())
    }
}

/// `com.deathweasel.bepinex.eyecontrol`: `EyeOpenMax` (`0..1`) and `DisableBlinking` (`bool`).
pub fn apply_eyecontrol(plugin_kv: &Value, info: &mut CardInfo) {
    let Some(data) = plugin_data_map(plugin_kv) else {
        return;
    };
    if let Some(open_max) = map_lookup(data, "EyeOpenMax").and_then(val_f32) {
        if open_max.is_finite() {
            info.eyes_open_max = open_max.clamp(0.0, 1.0);
        }
    }
    if let Some(disable_blink) = map_lookup(data, "DisableBlinking").and_then(val_bool) {
        if disable_blink {
            info.eyes_blink = false;
        }
    }
}

/// `org.njaecha.plugins.editfangs`: `fangData` (`[scaleL, scaleR, spacingL, spacingR]`).
pub fn parse_edit_fangs(plugin_kv: &Value) -> Option<[f32; 4]> {
    let data = plugin_data_map(plugin_kv)?;
    let raw = map_lookup(data, "fangData")?;
    let unpacked = decode_nested_msgpack(raw)?;
    let mut vals = if let Some(arr) = unpacked.as_array() {
        if arr.len() < 4 {
            return None;
        }
        [
            val_f32(&arr[0])?,
            val_f32(&arr[1])?,
            val_f32(&arr[2])?,
            val_f32(&arr[3])?,
        ]
    } else if let Some(m) = unpacked.as_map() {
        [
            map_lookup(m, "scaleL").and_then(val_f32).unwrap_or(0.1),
            map_lookup(m, "scaleR").and_then(val_f32).unwrap_or(0.1),
            map_lookup(m, "spacingL").and_then(val_f32).unwrap_or(1.0),
            map_lookup(m, "spacingR").and_then(val_f32).unwrap_or(1.0),
        ]
    } else {
        return None;
    };
    if !vals.iter().all(|x| x.is_finite()) {
        return None;
    }
    // EditFangsController.Start leaves loaded zero values as-is when `loaded = true` in OnReload,
    // so preserve exact deserialized values.
    let _ = &mut vals;
    Some(vals)
}

fn quat_rotate_y_deg(deg: f32, v: [f32; 3]) -> [f32; 3] {
    let half = deg.to_radians() * 0.5;
    let (sy, cy) = half.sin_cos();
    // q = (0, sy, 0, cy): v' = v + 2*cy*(u x v) + 2*(u x (u x v)) where u = (0, sy, 0)
    // u x v = (sy * v.z, 0, -sy * v.x)
    // u x (u x v) = (-sy*sy * v.x, 0, -sy*sy * v.z)
    let tx = 2.0 * sy * v[2];
    let tz = -2.0 * sy * v[0];
    [
        v[0] + cy * tx + sy * tz,
        v[1],
        v[2] + cy * tz - sy * tx,
    ]
}

/// Exact port of `EditFangsController.registerFangs` + `OnReload` (`adjustFang(..., readjust: true)`).
/// Runs on raw unrigged head mesh `cf_O_canine` (`42` vertices) before `rig_mesh`.
pub fn apply_edit_fangs(mesh: &mut ExtractedMesh, fang_data: Option<[f32; 4]>) {
    let Some([scale_l, scale_r, spacing_l, spacing_r]) = fang_data else {
        return;
    };
    if mesh.positions.len() != 42 || mesh.normals.len() != 42 {
        return;
    }
    if !crate::is_double_tooth_reference(mesh) {
        return;
    }
    let base_v = mesh.positions.clone();
    let base_n = mesh.normals.clone();

    let mut min_y = 100.0f32;
    for p in &base_v {
        if p[1] < min_y {
            min_y = p[1];
        }
    }
    let mut tips_list: Vec<usize> = base_v
        .iter()
        .enumerate()
        .filter(|(_, p)| (p[1] - min_y).abs() <= 1e-7)
        .map(|(i, _)| i)
        .collect();
    if tips_list.len() < 2 {
        let tip_l = (0..21)
            .min_by(|&a, &b| base_v[a][1].partial_cmp(&base_v[b][1]).unwrap_or(std::cmp::Ordering::Equal))
            .unwrap_or(0);
        let tip_r = (21..42)
            .min_by(|&a, &b| base_v[a][1].partial_cmp(&base_v[b][1]).unwrap_or(std::cmp::Ordering::Equal))
            .unwrap_or(21);
        tips_list = vec![tip_l, tip_r];
    }
    let tips = [tips_list[0], tips_list[1]];

    let target_l = [-0.007559223f32, 0.01637148f32, 0.08396365f32];
    let target_r = [0.007559223f32, 0.01637148f32, 0.08396365f32];
    let sq_dist = |a: [f32; 3], b: [f32; 3]| {
        let dx = a[0] - b[0];
        let dy = a[1] - b[1];
        let dz = a[2] - b[2];
        dx * dx + dy * dy + dz * dz
    };
    let mut rotp = [0usize, 0usize];
    if let Some((idx, d)) = (0..42).map(|i| (i, sq_dist(base_v[i], target_l))).min_by(|a, b| a.1.partial_cmp(&b.1).unwrap()) {
        if d < 1e-6 {
            rotp[0] = idx;
        }
    }
    if let Some((idx, d)) = (0..42).map(|i| (i, sq_dist(base_v[i], target_r))).min_by(|a, b| a.1.partial_cmp(&b.1).unwrap()) {
        if d < 1e-6 {
            rotp[1] = idx;
        }
    }

    let num = ((spacing_l as f64 * std::f64::consts::PI / 2.0).cos()
        * if spacing_l <= 1.0 { 1.0 } else { 2.3 }) as f32;
    let num2 = ((spacing_r as f64 * std::f64::consts::PI / 2.0).cos()
        * if spacing_r <= 1.0 { 1.0 } else { 2.3 }) as f32;

    let mut cur_v = base_v.clone();
    let mut cur_n = base_n.clone();
    // EditFangsController.OnReload calls `adjustFang(..., readjust: true)`, which executes two passes
    // where pass 2 reads `sharedMesh.vertices[rotp]` updated by pass 1 while resetting vertices from `fangsBaseVertices`.
    for _pass in 0..2 {
        let val = [
            cur_v[rotp[0]][0] * 0.99,
            cur_v[rotp[0]][1] * 0.99,
            cur_v[rotp[0]][2] * 0.99,
        ];
        let val3 = [
            cur_v[rotp[1]][0] * 0.99,
            cur_v[rotp[1]][1] * 0.99,
            cur_v[rotp[1]][2] * 0.99,
        ];
        let mut next_v = [[0.0f32; 3]; 42];
        let mut next_n = [[0.0f32; 3]; 42];
        for i in 0..42 {
            if i >= 21 {
                let mut p = [
                    base_v[i][0] - 0.01 * (1.0 - spacing_r),
                    base_v[i][1] - 0.001 * num2,
                    base_v[i][2] + 0.0014 * num2,
                ];
                let rel = [p[0] - val3[0], p[1] - val3[1], p[2] - val3[2]];
                let rot = quat_rotate_y_deg(num2 * -30.0, rel);
                p = [val3[0] + rot[0], val3[1] + rot[1], val3[2] + rot[2]];
                let n = quat_rotate_y_deg(num2 * -30.0, base_n[i]);
                if i == tips[1] {
                    p[1] += 0.01 * (0.1 - scale_r);
                    p[2] += 0.002 * (0.1 - scale_r);
                }
                next_v[i] = p;
                next_n[i] = n;
            } else {
                let mut p = [
                    base_v[i][0] + 0.01 * (1.0 - spacing_l),
                    base_v[i][1] - 0.001 * num,
                    base_v[i][2] + 0.0014 * num,
                ];
                let rel = [p[0] - val[0], p[1] - val[1], p[2] - val[2]];
                let rot = quat_rotate_y_deg(num * 30.0, rel);
                p = [val[0] + rot[0], val[1] + rot[1], val[2] + rot[2]];
                let n = quat_rotate_y_deg(num * 30.0, base_n[i]);
                if i == tips[0] {
                    p[1] += 0.01 * (0.1 - scale_l);
                    p[2] += 0.002 * (0.1 - scale_l);
                }
                next_v[i] = p;
                next_n[i] = n;
            }
        }
        cur_v.copy_from_slice(&next_v);
        cur_n.copy_from_slice(&next_n);
    }
    mesh.positions = cur_v;
    mesh.normals = cur_n;
    if mesh.rest_positions.len() == 42 {
        mesh.rest_positions = mesh.positions.clone();
    }
    if mesh.rest_normals.len() == 42 {
        mesh.rest_normals = mesh.normals.clone();
    }
}

/// `nakay.kk.ClothingBlendShape`: parses `ClothesDataSet` into `(coordinate, category, shoes_type) -> [f32; 4]`.
pub fn parse_clothing_blend_shapes(
    plugin_kv: &Value,
    coord_override: Option<i32>,
    out: &mut HashMap<(i32, i32, i32), [f32; 4]>,
) {
    let Some(data) = plugin_data_map(plugin_kv) else {
        return;
    };
    let Some(raw) = map_lookup(data, "ClothesDataSet") else {
        return;
    };
    let Some(unpacked) = decode_nested_msgpack(raw) else {
        return;
    };
    let Some(arr) = unpacked.as_array() else {
        return;
    };
    if let Some(c) = coord_override {
        out.retain(|&(coord, _, _), _| coord != c);
    }
    for item in arr {
        let Some(m) = item.as_map() else {
            continue;
        };
        let coord = coord_override
            .or_else(|| map_lookup(m, "Coordinate").and_then(val_i32))
            .unwrap_or(0);
        let Some(cat) = map_lookup(m, "Category").and_then(val_i32) else {
            continue;
        };
        let shoes_type = map_lookup(m, "ShoesType").and_then(val_i32).unwrap_or(0);
        let mut weights = [20.0f32; 4];
        if let Some(w_arr) = map_lookup(m, "ShapeWeight").and_then(Value::as_array) {
            for (idx, v) in w_arr.iter().take(4).enumerate() {
                if let Some(f) = val_f32(v) {
                    if f.is_finite() {
                        weights[idx] = f;
                    }
                }
            }
        }
        out.insert((coord, cat, shoes_type), weights);
    }
}

/// Applies `ChaClothesBlendShape` (`Awake` default `20.0` + `ClothingBlendShapeController.SetMeshWeight`)
/// to unrigged clothing meshes before `push_meshes`.
pub fn apply_clothes_blend_shapes(
    meshes: &mut [ExtractedMesh],
    defs: &[ClothesBlendShapeSlot],
    card: &CardInfo,
    outfit: i32,
    category_no: i32,
    shoes_type: i32,
) {
    if defs.is_empty() || meshes.is_empty() {
        return;
    }
    let saved = if card.clothes_blend_shapes.is_empty() {
        Some([20.0f32; 4])
    } else {
        card.clothes_blend_shapes
            .get(&(outfit, category_no, shoes_type))
            .copied()
    };
    for (slot_idx, slot) in defs.iter().enumerate().take(4) {
        if slot.renderers.is_empty() {
            continue;
        }
        // ChaClothesBlendShape.BlendShapeIndexExists: every referenced renderer must have blendShapeCount > shapeIndex.
        let mut matched_any = false;
        let mut all_valid = true;
        for m in meshes.iter() {
            if m.renderer_ids.iter().any(|id| slot.renderers.contains(id)) {
                matched_any = true;
                if slot.shape_index >= m.blend_shapes.len() {
                    all_valid = false;
                    break;
                }
            }
        }
        if !matched_any || !all_valid {
            continue;
        }
        // ChaClothesBlendShape.Awake() sets 20f first; SetMeshWeight overrides non-empty item names when BlendShapeData exists.
        let mut weight_pct = 20.0f32;
        if !slot.item_name.is_empty() {
            if let Some(w) = saved {
                weight_pct = w[slot_idx];
            }
        }
        let w = weight_pct / 100.0;
        if w.abs() <= 1e-6 {
            continue;
        }
        for m in meshes.iter_mut() {
            if !m.renderer_ids.iter().any(|id| slot.renderers.contains(id)) {
                continue;
            }
            let Some((_, deltas)) = m.blend_shapes.get(slot.shape_index) else {
                continue;
            };
            let deltas_copy = deltas.clone();
            let has_rest = m.rest_positions.len() == m.positions.len();
            for (v_idx, d) in deltas_copy {
                if let Some(p) = m.positions.get_mut(v_idx as usize) {
                    p[0] += d[0] * w;
                    p[1] += d[1] * w;
                    p[2] += d[2] * w;
                }
                if has_rest {
                    if let Some(rp) = m.rest_positions.get_mut(v_idx as usize) {
                        rp[0] += d[0] * w;
                        rp[1] += d[1] * w;
                        rp[2] += d[2] * w;
                    }
                }
            }
        }
    }
}

fn parse_string_set(v: &Value) -> HashSet<String> {
    let mut set = HashSet::new();
    if let Some(arr) = v.as_array() {
        for item in arr {
            if let Some(s) = item.as_str() {
                if !s.is_empty() {
                    set.insert(s.to_string());
                }
            }
        }
    }
    set
}

fn shoe_trigger_fix(triggers: &mut Vec<AccTriggerProperty>) {
    let refs: Vec<AccTriggerProperty> = triggers
        .iter()
        .filter(|x| (x.ref_kind == 7 || x.ref_kind == 8) && x.ref_state == 3)
        .cloned()
        .collect();
    if refs.is_empty() {
        return;
    }
    for r in refs {
        triggers.retain(|x| {
            !(x.coordinate == r.coordinate
                && x.slot == r.slot
                && x.ref_kind == r.ref_kind
                && (x.ref_state == 1 || x.ref_state == 2))
        });
        let mut t1 = r.clone();
        t1.ref_state = 1;
        triggers.push(t1);
        let mut t2 = r;
        t2.ref_state = 2;
        triggers.push(t2);
    }
}

fn parse_legacy_group_kind(group: &str, fallback_kind: i32) -> i32 {
    if fallback_kind >= 0 {
        return fallback_kind;
    }
    let g = group.trim();
    if let Some(num_str) = g.strip_prefix("custom_") {
        if let Ok(n) = num_str.parse::<i32>() {
            return 9 + n;
        }
    }
    match g {
        "top" | "clothesTop" => 0,
        "bot" | "clothesBot" => 1,
        "bra" => 2,
        "shorts" => 3,
        "gloves" => 4,
        "panst" => 5,
        "socks" => 6,
        "shoes_inner" => 7,
        "shoes_outer" => 8,
        _ => -1,
    }
}

fn parse_legacy_outfit_trigger_info(
    coord: i32,
    outfit_val: &Value,
    vgroups_val: Option<&Value>,
    out: &mut AccStateSyncData,
) {
    let Some(m) = outfit_val.as_map() else {
        return;
    };
    let Some(parts_val) = map_lookup(m, "Parts") else {
        return;
    };
    let mut part_entries: Vec<&Value> = Vec::new();
    if let Some(arr) = parts_val.as_array() {
        part_entries.extend(arr.iter());
    } else if let Some(pmap) = parts_val.as_map() {
        part_entries.extend(pmap.iter().map(|(_, v)| v));
    }
    for p in part_entries {
        let Some(pm) = p.as_map() else {
            continue;
        };
        let Some(slot) = map_lookup(pm, "Slot").and_then(val_i32) else {
            continue;
        };
        let raw_kind = map_lookup(pm, "Kind").and_then(val_i32).unwrap_or(-1);
        let group_str = map_lookup(pm, "Group").and_then(Value::as_str).unwrap_or("");
        let ref_kind = parse_legacy_group_kind(group_str, raw_kind);
        if ref_kind < 0 {
            continue;
        }
        let states: Vec<bool> = map_lookup(pm, "State")
            .and_then(Value::as_array)
            .map(|a| a.iter().map(|x| val_bool(x).unwrap_or(false)).collect())
            .unwrap_or_else(|| vec![true, false, false, false]);
        let max_states = if ref_kind >= 9 { 2.min(states.len()) } else { states.len().min(4) };
        for (st_idx, &vis) in states.iter().take(max_states).enumerate() {
            out.triggers.push(AccTriggerProperty {
                coordinate: coord,
                slot,
                ref_kind,
                ref_state: st_idx as i32,
                visible: vis,
                priority: 0,
                render_show: HashSet::new(),
                render_hide: HashSet::new(),
            });
        }
        if ref_kind >= 9 && !out.groups.iter().any(|g| g.coordinate == coord && g.kind == ref_kind) {
            let mut startup = 0;
            if let Some(vg_map) = vgroups_val.and_then(Value::as_map) {
                if let Some(vg) = map_lookup(vg_map, group_str).and_then(Value::as_map) {
                    // VirtualGroupInfo.State == true means State 0 (ON), false means State 1 (OFF).
                    if map_lookup(vg, "State").and_then(val_bool) == Some(false) {
                        startup = 1;
                    }
                }
            }
            out.groups.push(AccTriggerGroup {
                coordinate: coord,
                kind: ref_kind,
                state: startup,
                startup,
            });
        }
    }
}

/// `madevil.kk.ass` (`AccStateSync`): parses both modern (`version >= 6`) and legacy (`version < 6`) schemas.
pub fn parse_acc_state_sync(
    plugin_kv: &Value,
    coord_override: Option<i32>,
    in_studio_scene: bool,
    out: &mut AccStateSyncData,
) {
    let version = plugin_version(plugin_kv);
    if version > 7 {
        return;
    }
    let Some(data) = plugin_data_map(plugin_kv) else {
        return;
    };
    if let Some(c) = coord_override {
        out.triggers.retain(|t| t.coordinate != c);
        out.groups.retain(|g| g.coordinate != c);
    } else {
        out.triggers.clear();
        out.groups.clear();
    }

    if version > 0 && version < 6 {
        if let Some(c) = coord_override {
            if let Some(raw_oti) = map_lookup(data, "OutfitTriggerInfo").and_then(decode_nested_msgpack) {
                let vgi = map_lookup(data, "OutfitVirtualGroupInfo").and_then(decode_nested_msgpack);
                parse_legacy_outfit_trigger_info(c, &raw_oti, vgi.as_ref(), out);
            }
        } else if let Some(raw_cti) = map_lookup(data, "CharaTriggerInfo").and_then(decode_nested_msgpack) {
            let vgi_all = map_lookup(data, "CharaVirtualGroupInfo").and_then(decode_nested_msgpack);
            if let Some(arr) = raw_cti.as_array() {
                for (coord_idx, elem) in arr.iter().enumerate() {
                    parse_legacy_outfit_trigger_info(coord_idx as i32, elem, None, out);
                }
            } else if let Some(cmap) = raw_cti.as_map() {
                for (ck, elem) in cmap {
                    let Some(coord_idx) = val_i32(ck) else {
                        continue;
                    };
                    let vgi_coord = vgi_all.as_ref().and_then(Value::as_map).and_then(|m| {
                        m.iter().find(|(k, _)| val_i32(k) == Some(coord_idx)).map(|(_, v)| v)
                    });
                    parse_legacy_outfit_trigger_info(coord_idx, elem, vgi_coord, out);
                }
            }
        }
        shoe_trigger_fix(&mut out.triggers);
        return;
    }

    let mut added_triggers = Vec::new();
    if let Some(raw_props) = map_lookup(data, "TriggerPropertyList").and_then(decode_nested_msgpack) {
        if let Some(arr) = raw_props.as_array() {
            for item in arr {
                let Some(m) = item.as_map() else {
                    continue;
                };
                let coordinate = coord_override
                    .or_else(|| map_lookup(m, "Coordinate").and_then(val_i32))
                    .unwrap_or(-1);
                let slot = map_lookup(m, "Slot").and_then(val_i32).unwrap_or(-1);
                let ref_kind = map_lookup(m, "RefKind").and_then(val_i32).unwrap_or(-1);
                let ref_state = map_lookup(m, "RefState").and_then(val_i32).unwrap_or(-1);
                if coordinate < 0 || slot < 0 || ref_kind < 0 || ref_state < 0 {
                    continue;
                }
                let visible = map_lookup(m, "Visible").and_then(val_bool).unwrap_or(true);
                let priority = map_lookup(m, "Priority").and_then(val_i32).unwrap_or(0);
                let render_show = map_lookup(m, "RenderShow")
                    .map(parse_string_set)
                    .unwrap_or_default();
                let render_hide = map_lookup(m, "RenderHide")
                    .map(parse_string_set)
                    .unwrap_or_default();
                added_triggers.push(AccTriggerProperty {
                    coordinate,
                    slot,
                    ref_kind,
                    ref_state,
                    visible,
                    priority,
                    render_show,
                    render_hide,
                });
            }
        }
    }
    if added_triggers.is_empty() {
        return;
    }
    shoe_trigger_fix(&mut added_triggers);

    if let Some(raw_groups) = map_lookup(data, "TriggerGroupList").and_then(decode_nested_msgpack) {
        if let Some(arr) = raw_groups.as_array() {
            for item in arr {
                let Some(m) = item.as_map() else {
                    continue;
                };
                let coordinate = coord_override
                    .or_else(|| map_lookup(m, "Coordinate").and_then(val_i32))
                    .unwrap_or(-1);
                let Some(kind) = map_lookup(m, "Kind").and_then(val_i32) else {
                    continue;
                };
                if coordinate < 0 {
                    continue;
                }
                let startup = map_lookup(m, "Startup").and_then(val_i32).unwrap_or(0);
                let saved_state = map_lookup(m, "State").and_then(val_i32).unwrap_or(startup);
                let has_state_1 = map_lookup(m, "States")
                    .and_then(Value::as_map)
                    .is_some_and(|sm| sm.iter().any(|(k, _)| val_i32(k) == Some(1)));
                if !has_state_1 {
                    let clones: Vec<AccTriggerProperty> = added_triggers
                        .iter()
                        .filter(|x| x.coordinate == coordinate && x.ref_kind == kind && x.ref_state == 0)
                        .filter(|x| {
                            !added_triggers.iter().any(|y| {
                                y.coordinate == coordinate
                                    && y.slot == x.slot
                                    && y.ref_kind == kind
                                    && y.ref_state == 1
                            })
                        })
                        .map(|x| {
                            let mut c = x.clone();
                            c.ref_state = 1;
                            c.visible = false;
                            c
                        })
                        .collect();
                    added_triggers.extend(clones);
                }
                let state = if in_studio_scene && coord_override.is_none() {
                    saved_state
                } else {
                    startup
                };
                out.groups.push(AccTriggerGroup {
                    coordinate,
                    kind,
                    state,
                    startup,
                });
            }
        }
    }
    out.triggers.extend(added_triggers);
}

/// `Accessory_States`: converts `CoordinateData` (`_slotinfo`, `_names`, `_clothnotdata`) via
/// `CoordinateData.Accstatesyncconvert` when `madevil.kk.ass` is not present on the card.
pub fn parse_accessory_states(plugin_kv: &Value, out: &mut AccStateSyncData) {
    if !out.triggers.is_empty() {
        // `madevil.kk.ass` takes precedence when both exist on a card.
        return;
    }
    let Some(data) = plugin_data_map(plugin_kv) else {
        return;
    };
    let Some(raw_cd) = map_lookup(data, "CoordinateData").and_then(decode_nested_msgpack) else {
        return;
    };
    let Some(coord_map) = raw_cd.as_map() else {
        return;
    };
    for (ck, cv) in coord_map {
        let Some(outfit_num) = val_i32(ck) else {
            continue;
        };
        let Some(cm) = cv.as_map() else {
            continue;
        };
        let mut cloth_not = [false; 3];
        if let Some(cn_arr) = map_lookup(cm, "_clothnotdata").and_then(Value::as_array) {
            for (i, b) in cn_arr.iter().take(3).enumerate() {
                cloth_not[i] = val_bool(b).unwrap_or(false);
            }
        }
        let Some(slot_map) = map_lookup(cm, "_slotinfo").and_then(Value::as_map) else {
            continue;
        };
        struct ParsedSlot {
            slot: i32,
            binding: i32,
            shoetype: i32,
            ranges: Vec<[i32; 2]>,
        }
        let mut parsed_slots = Vec::new();
        for (sk, sv) in slot_map {
            let Some(slot) = val_i32(sk) else {
                continue;
            };
            let Some(sm) = sv.as_map() else {
                continue;
            };
            let binding = map_lookup(sm, "_binding").and_then(val_i32).unwrap_or(-1);
            if binding < 0 {
                continue;
            }
            let shoetype = map_lookup(sm, "_shoetype").and_then(val_i32).unwrap_or(2);
            let mut ranges = Vec::new();
            if let Some(st_arr) = map_lookup(sm, "_state").and_then(Value::as_array) {
                for r in st_arr {
                    if let Some(ra) = r.as_array() {
                        if ra.len() >= 2 {
                            if let (Some(a), Some(b)) = (val_i32(&ra[0]), val_i32(&ra[1])) {
                                ranges.push([a, b]);
                            }
                        }
                    }
                }
            }
            if ranges.is_empty() {
                ranges.push([0, 3]);
            }
            parsed_slots.push(ParsedSlot {
                slot,
                binding,
                shoetype,
                ranges,
            });
        }
        let max_state = |binding: i32| -> i32 {
            if binding < 9 {
                3
            } else {
                parsed_slots
                    .iter()
                    .filter(|s| s.binding == binding)
                    .flat_map(|s| s.ranges.iter().map(|r| r[1]))
                    .max()
                    .unwrap_or(0)
            }
        };
        let show_state = |st: i32, ranges: &[[i32; 2]]| -> bool {
            ranges.iter().any(|r| r[0] <= st && st <= r[1])
        };
        let push_cloth_not = |out_triggers: &mut Vec<AccTriggerProperty>, slot: i32, ranges: &[[i32; 2]], clothing_kind: i32| {
            for i in 0..4 {
                let edge = i % 3 == 0;
                out_triggers.push(AccTriggerProperty {
                    coordinate: outfit_num,
                    slot,
                    ref_kind: clothing_kind,
                    ref_state: i,
                    visible: edge && show_state(i, ranges),
                    priority: if edge { 2 } else { 0 },
                    render_show: HashSet::new(),
                    render_hide: HashSet::new(),
                });
            }
        };

        for ps in &parsed_slots {
            let num = max_state(ps.binding) + 1;
            for i in 0..num {
                let visible = show_state(i, &ps.ranges);
                let priority = if ps.binding < 4 && i % 3 == 0 { 2 } else { 1 };
                out.triggers.push(AccTriggerProperty {
                    coordinate: outfit_num,
                    slot: ps.slot,
                    ref_kind: ps.binding,
                    ref_state: i,
                    visible,
                    priority,
                    render_show: HashSet::new(),
                    render_hide: HashSet::new(),
                });
            }
            let is_shoe_binding = ps.binding == 7 || ps.binding == 8;
            if ps.shoetype != 2 && !is_shoe_binding {
                let ref_kind = if ps.shoetype == 0 { 8 } else { 7 };
                for j in 0..num {
                    out.triggers.push(AccTriggerProperty {
                        coordinate: outfit_num,
                        slot: ps.slot,
                        ref_kind,
                        ref_state: j,
                        visible: false,
                        priority: 3,
                        render_show: HashSet::new(),
                        render_hide: HashSet::new(),
                    });
                }
            }
            if is_shoe_binding && ps.shoetype == 2 {
                let ref_kind2 = if ps.binding == 7 { 8 } else { 7 };
                for k in 0..num {
                    let visible = show_state(k, &ps.ranges);
                    let priority = if ps.binding < 4 && k % 3 == 0 { 2 } else { 1 };
                    out.triggers.push(AccTriggerProperty {
                        coordinate: outfit_num,
                        slot: ps.slot,
                        ref_kind: ref_kind2,
                        ref_state: k,
                        visible,
                        priority,
                        render_show: HashSet::new(),
                        render_hide: HashSet::new(),
                    });
                }
            }
            match ps.binding {
                0 => {
                    if cloth_not[0] {
                        push_cloth_not(&mut out.triggers, ps.slot, &ps.ranges, 1);
                    }
                    if cloth_not[1] {
                        push_cloth_not(&mut out.triggers, ps.slot, &ps.ranges, 2);
                    }
                }
                1 => {
                    if cloth_not[0] {
                        push_cloth_not(&mut out.triggers, ps.slot, &ps.ranges, 0);
                    }
                }
                2 => {
                    if cloth_not[2] {
                        push_cloth_not(&mut out.triggers, ps.slot, &ps.ranges, 3);
                    }
                    if cloth_not[1] {
                        push_cloth_not(&mut out.triggers, ps.slot, &ps.ranges, 0);
                    }
                }
                3 => {
                    if cloth_not[2] {
                        push_cloth_not(&mut out.triggers, ps.slot, &ps.ranges, 2);
                    }
                }
                _ => {}
            }
            if ps.binding >= 9 && !out.groups.iter().any(|g| g.coordinate == outfit_num && g.kind == ps.binding) {
                out.groups.push(AccTriggerGroup {
                    coordinate: outfit_num,
                    kind: ps.binding,
                    state: 0,
                    startup: 0,
                });
            }
        }
        if let Some(names_map) = map_lookup(cm, "_names").and_then(Value::as_map) {
            for (nk, _) in names_map {
                if let Some(kind) = val_i32(nk) {
                    if !out.groups.iter().any(|g| g.coordinate == outfit_num && g.kind == kind) {
                        out.groups.push(AccTriggerGroup {
                            coordinate: outfit_num,
                            kind,
                            state: 0,
                            startup: 0,
                        });
                    }
                }
            }
        }
    }
    shoe_trigger_fix(&mut out.triggers);
}

/// Evaluates `AccStateSync.SyncAllAccToggle` + `ApplySlotRendererTrigger` against `session_parts`.
#[allow(clippy::too_many_arguments)]
pub fn apply_acc_state_sync_visibility(
    card: &CardInfo,
    outfit: i32,
    clothes_states: [u8; 9],
    clothes_state_present: [bool; 9],
    not_bot: bool,
    not_shorts: bool,
    apply_slot_visibility: bool,
    session_parts: &mut [crate::session::SessionPart],
) {
    if card.acc_state_sync.is_empty() {
        return;
    }
    let shoes_type = card.status_shoes_type as i32;
    let mut states_dict: HashMap<i32, i32> = HashMap::new();
    for i in 0..9usize {
        if clothes_state_present[i] {
            let mut st = clothes_states[i] as i32;
            if i == 0 && not_bot && clothes_states[1] == 3 {
                st = 3;
            }
            if i == 1 && not_bot && clothes_states[0] == 3 {
                st = 3;
            }
            if i == 2 && not_shorts && clothes_states[3] == 3 {
                st = 3;
            }
            if i == 3 && not_shorts && clothes_states[2] == 3 {
                st = 3;
            }
            if i == 7 && shoes_type != 0 {
                st = 3;
            }
            if i == 8 && shoes_type != 1 {
                st = 3;
            }
            states_dict.insert(i as i32, st);
        }
    }
    if shoes_type == 0 && !clothes_state_present[7] {
        states_dict.insert(7, 3);
    }
    if shoes_type == 1 && !clothes_state_present[8] {
        states_dict.insert(8, 3);
    }

    let mut coord_triggers: Vec<&AccTriggerProperty> = card
        .acc_state_sync
        .triggers
        .iter()
        .filter(|t| t.coordinate == outfit)
        .collect();
    if coord_triggers.is_empty() {
        return;
    }
    coord_triggers.sort_by(|a, b| {
        a.slot
            .cmp(&b.slot)
            .then_with(|| b.priority.cmp(&a.priority))
            .then_with(|| a.ref_kind.cmp(&b.ref_kind))
            .then_with(|| a.ref_state.cmp(&b.ref_state))
    });

    let mut winning_by_slot: HashMap<usize, &AccTriggerProperty> = HashMap::new();
    let mut cur_slot = -1i32;
    let mut cur_resolved = false;
    for x in coord_triggers {
        if x.slot != cur_slot {
            cur_slot = x.slot;
            cur_resolved = false;
        }
        if cur_resolved || x.slot < 0 {
            continue;
        }
        let matched = if (0..=8).contains(&x.ref_kind) {
            states_dict.get(&x.ref_kind) == Some(&x.ref_state)
                && (x.ref_kind != 8 || shoes_type != 0 || !clothes_state_present[7])
                && (x.ref_kind != 7 || shoes_type != 1 || !clothes_state_present[8])
        } else if x.ref_kind >= 9 {
            card.acc_state_sync
                .groups
                .iter()
                .find(|g| g.coordinate == outfit && g.kind == x.ref_kind)
                .is_some_and(|g| g.state == x.ref_state)
        } else {
            false
        };
        if matched {
            winning_by_slot.insert(x.slot as usize, x);
            cur_resolved = true;
        }
    }
    if winning_by_slot.is_empty() {
        return;
    }

    for part in session_parts.iter_mut() {
        let Some(prop) = part.source_property.as_deref() else {
            continue;
        };
        let Some(slot) = crate::accessory_slot_from_property(prop) else {
            continue;
        };
        let Some(trigger) = winning_by_slot.get(&slot) else {
            continue;
        };
        if apply_slot_visibility {
            part.render_visible = trigger.visible;
        }
        if !part.render_visible {
            continue;
        }
        // ApplySlotRendererTrigger matches Unity Renderer.name (GameObject name).
        if !trigger.render_show.is_empty() {
            if part
                .source_renderer_names
                .iter()
                .any(|rn| trigger.render_show.contains(rn))
            {
                part.render_visible = true;
            }
        }
        if !trigger.render_hide.is_empty() {
            if part
                .source_renderer_names
                .iter()
                .any(|rn| trigger.render_hide.contains(rn))
            {
                part.render_visible = false;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pack_msgpack(v: &Value) -> Vec<u8> {
        let mut out = Vec::new();
        rmpv::encode::write_value(&mut out, v).unwrap();
        out
    }

    #[test]
    fn eyecontrol_updates_open_max_and_blink() {
        let mut info = CardInfo::default();
        info.eyes_open_max = 1.0;
        info.eyes_blink = true;
        let kv = Value::Array(vec![
            1.into(),
            Value::Map(vec![
                ("EyeOpenMax".into(), Value::F32(0.65)),
                ("DisableBlinking".into(), Value::Boolean(true)),
            ]),
        ]);
        apply_eyecontrol(&kv, &mut info);
        assert!((info.eyes_open_max - 0.65).abs() < 1e-6);
        assert!(!info.eyes_blink);
    }

    #[test]
    fn editfangs_parses_and_deforms_42_vertex_canine() {
        let fang_bin = pack_msgpack(&Value::Array(vec![
            Value::F32(0.45),
            Value::F32(0.45),
            Value::F32(0.8),
            Value::F32(0.8),
        ]));
        let kv = Value::Array(vec![
            1.into(),
            Value::Map(vec![("fangData".into(), Value::Binary(fang_bin))]),
        ]);
        let parsed = parse_edit_fangs(&kv).expect("fangData should parse");
        assert!((parsed[0] - 0.45).abs() < 1e-6);
        assert!((parsed[2] - 0.8).abs() < 1e-6);

        let mut positions = vec![[0.0f32, 0.01, 0.08]; 42];
        positions[3] = [-0.008, -0.005, 0.084]; // left tip (min y)
        positions[24] = [0.008, -0.005, 0.084]; // right tip (min y)
        positions[5] = [-0.007559223, 0.01637148, 0.08396365];
        positions[26] = [0.007559223, 0.01637148, 0.08396365];
        let mut mesh = ExtractedMesh {
            name: "o_tooth_canine".into(),
            renderer_names: vec!["cf_O_canine".into()],
            positions: positions.clone(),
            normals: vec![[0.0, 0.0, 1.0]; 42],
            ..Default::default()
        };
        apply_edit_fangs(&mut mesh, Some(parsed));
        // Larger scaleL (> 0.1) lowers tip Y (`+ 0.01 * (0.1 - scaleL)` < 0).
        assert!(mesh.positions[3][1] < positions[3][1]);
        assert!(mesh.positions[24][1] < positions[24][1]);
        assert!((mesh.positions[3][0] + mesh.positions[24][0]).abs() < 1e-5);
    }

    #[test]
    fn clothing_blend_shape_defaults_to_20_and_applies_saved_weights() {
        let row = Value::Map(vec![
            ("Coordinate".into(), 0.into()),
            ("Category".into(), 105.into()),
            ("ShoesType".into(), 0.into()),
            (
                "ShapeWeight".into(),
                Value::Array(vec![Value::F32(75.0), Value::F32(20.0), Value::F32(0.0), Value::F32(20.0)]),
            ),
        ]);
        let bin = pack_msgpack(&Value::Array(vec![row]));
        let kv = Value::Array(vec![
            1.into(),
            Value::Map(vec![("ClothesDataSet".into(), Value::Binary(bin))]),
        ]);
        let mut card = CardInfo::default();
        parse_clothing_blend_shapes(&kv, None, &mut card.clothes_blend_shapes);
        assert_eq!(card.clothes_blend_shapes.get(&(0, 105, 0)), Some(&[75.0, 20.0, 0.0, 20.0]));

        let defs = vec![ClothesBlendShapeSlot {
            item_name: "Collar Open".into(),
            renderers: vec![42],
            shape_index: 0,
        }];
        let mut mesh = ExtractedMesh {
            name: "top".into(),
            renderer_ids: vec![42],
            positions: vec![[0.0, 0.0, 0.0]],
            blend_shapes: vec![("open".into(), vec![(0, [1.0, 2.0, 0.0])])],
            ..Default::default()
        };
        apply_clothes_blend_shapes(&mut std::slice::from_mut(&mut mesh), &defs, &card, 0, 105, 0);
        assert!((mesh.positions[0][0] - 0.75).abs() < 1e-6);
        assert!((mesh.positions[0][1] - 1.5).abs() < 1e-6);

        // Outfit 1 has no saved entry -> ChaClothesBlendShape.Awake() default 20% applies!
        let mut mesh_default = ExtractedMesh {
            name: "top".into(),
            renderer_ids: vec![42],
            positions: vec![[0.0, 0.0, 0.0]],
            blend_shapes: vec![("open".into(), vec![(0, [1.0, 0.0, 0.0])])],
            ..Default::default()
        };
        apply_clothes_blend_shapes(&mut std::slice::from_mut(&mut mesh_default), &defs, &card, 1, 105, 0);
        assert!((mesh_default.positions[0][0] - 0.20).abs() < 1e-6);
    }

    #[test]
    fn acc_state_sync_and_accessory_states_evaluate_slot_and_renderer_visibility() {
        let props = Value::Array(vec![
            Value::Map(vec![
                ("Coordinate".into(), 0.into()),
                ("Slot".into(), 2.into()),
                ("RefKind".into(), 0.into()),
                ("RefState".into(), 0.into()),
                ("Visible".into(), true.into()),
                ("Priority".into(), 1.into()),
                ("RenderShow".into(), Value::Array(vec![])),
                ("RenderHide".into(), Value::Array(vec!["sheath_closed".into()])),
            ]),
            Value::Map(vec![
                ("Coordinate".into(), 0.into()),
                ("Slot".into(), 2.into()),
                ("RefKind".into(), 0.into()),
                ("RefState".into(), 3.into()),
                ("Visible".into(), false.into()),
                ("Priority".into(), 1.into()),
            ]),
        ]);
        let kv = Value::Array(vec![
            7.into(),
            Value::Map(vec![("TriggerPropertyList".into(), Value::Binary(pack_msgpack(&props)))]),
        ]);
        let mut card = CardInfo::default();
        card.status_shoes_type = 1;
        parse_acc_state_sync(&kv, None, false, &mut card.acc_state_sync);

        let dummy_mesh = ExtractedMesh {
            name: "m".into(),
            positions: vec![[0.0; 3]],
            normals: vec![[0.0, 1.0, 0.0]],
            uvs: vec![[0.0; 2]],
            indices: vec![0, 0, 0],
            ..Default::default()
        };
        let mut p_hilt = crate::session::SessionPart::from_mesh("acc", &dummy_mesh, "opaque", false);
        p_hilt.source_property = Some("outfit0.accessory2".into());
        p_hilt.source_renderer_names = vec!["hilt".into()];
        let mut p_sheath = crate::session::SessionPart::from_mesh("acc", &dummy_mesh, "opaque", false);
        p_sheath.source_property = Some("outfit0.accessory2".into());
        p_sheath.source_renderer_names = vec!["sheath_closed".into()];

        let mut parts = vec![p_hilt, p_sheath];
        apply_acc_state_sync_visibility(
            &card,
            0,
            [0; 9],
            [true; 9],
            false,
            false,
            true,
            &mut parts,
        );
        assert!(parts[0].render_visible);
        assert!(!parts[1].render_visible);

        // Top stripped (state 3) -> whole slot 2 hidden!
        parts[0].render_visible = true;
        parts[1].render_visible = true;
        let mut stripped = [0u8; 9];
        stripped[0] = 3;
        apply_acc_state_sync_visibility(
            &card,
            0,
            stripped,
            [true; 9],
            false,
            false,
            true,
            &mut parts,
        );
        assert!(!parts[0].render_visible);
        assert!(!parts[1].render_visible);
    }
}
