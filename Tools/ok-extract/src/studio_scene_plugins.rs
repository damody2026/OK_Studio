//! Universal Studio scene plugin parsers (`KKEx` scene & character blocks):
//! - `timeline` (`Timeline.dll`): keyframe & cubic-Hermite curve tracks for camera, objects, bones, IK, morphs, lights, items, and constraints
//! - `nodesConstraints` (`NodesConstraints.dll`) + `KK_AnimationController` fallback: parent/child object & bone/IK constraints
//! - `kkpe` (`KKPE.dll` / `HSPE`): static bone TRS (`advancedObjects`) and blendshape (`skinnedMeshes`) overrides for characters & items
//! - `org.njaecha.plugins.treenodenaming`: custom Workspace tree node names by `dicKey`
//! - `com.rikkibalboa.bepinex.savecameraobjectfov`: per-camera object FOV & main camera FOV
//! - `orange.spork.moarcamzplugin`: extended Studio camera slots (`MoarCamz`)
//! - `com.deathweasel.bepinex.studioscenesettings`: scene near/far clip plane, shadow distance, map masking
//! - `com.deathweasel.bepinex.studioimageembed`: embedded PNG/JPEG background and frame textures

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::path::Path;

use rmpv::Value;
use serde::Serialize;

use crate::card::map_get;
use crate::studio_scene::{scene_plugins, Object, Scene};

/// Collects every `ObjectCtrlInfo` key in `scene.objects` sorted ascending, matching
/// `new SortedDictionary<int, ObjectCtrlInfo>(Studio.Instance.dicObjectCtrl).ToList()`
/// used by `Timeline` and `NodesConstraints` for `objectIndex` / `parentObjectIndex` / `childObjectIndex`.
pub fn sorted_dic_keys(scene: &Scene) -> Vec<i32> {
    fn walk(objs: &[Object], out: &mut BTreeSet<i32>) {
        for o in objs {
            match o {
                Object::Character { key, children, .. } => {
                    out.insert(*key);
                    for (_, list) in children {
                        walk(list, out);
                    }
                }
                Object::Item { key, children, .. }
                | Object::Folder { key, children, .. }
                | Object::Route { key, children, .. } => {
                    out.insert(*key);
                    walk(children, out);
                }
                Object::Light { key, .. }
                | Object::Camera { key, .. }
                | Object::Text { key, .. } => {
                    out.insert(*key);
                }
            }
        }
    }
    let mut set = BTreeSet::new();
    walk(&scene.objects, &mut set);
    set.into_iter().collect()
}

/// Maps a KK Studio IK target bone/guide-object name (`cf_t_*` / `cm_t_*`) to `OKStudio`'s FinalIK effector index:
/// `0` body, `1..2` L/R shoulder, `3..4` L/R thigh, `5..6` L/R hand, `7..8` L/R foot, `9..10` L/R elbow bend, `11..12` L/R knee bend.
pub fn studio_ik_effector_from_path(path: &str) -> Option<i32> {
    let leaf = path.rsplit('/').next().unwrap_or(path).trim();
    match leaf {
        "cf_t_hips" | "cm_t_hips" => Some(0),
        "cf_t_shoulder_L" | "cm_t_shoulder_L" => Some(1),
        "cf_t_elbo_L" | "cm_t_elbo_L" => Some(9),
        "cf_t_hand_L" | "cm_t_hand_L" => Some(5),
        "cf_t_shoulder_R" | "cm_t_shoulder_R" => Some(2),
        "cf_t_elbo_R" | "cm_t_elbo_R" => Some(10),
        "cf_t_hand_R" | "cm_t_hand_R" => Some(6),
        "cf_t_waist_L" | "cm_t_waist_L" => Some(3),
        "cf_t_knee_L" | "cm_t_knee_L" => Some(11),
        "cf_t_leg_L" | "cm_t_leg_L" => Some(7),
        "cf_t_waist_R" | "cm_t_waist_R" => Some(4),
        "cf_t_knee_R" | "cm_t_knee_R" => Some(12),
        "cf_t_leg_R" | "cm_t_leg_R" => Some(8),
        _ => None,
    }
}

pub fn leaf_bone_name(path: &str) -> String {
    let trimmed = path.trim().trim_matches('/');
    trimmed.rsplit('/').next().unwrap_or(trimmed).to_string()
}

fn plugin_data_map<'a>(blocks: &'a Value, id: &str) -> Option<&'a Value> {
    let p = map_get(blocks, id)?;
    Some(p.as_array().and_then(|a| a.get(1)).unwrap_or(p))
}

fn val_f32(v: &Value) -> Option<f32> {
    v.as_f64()
        .or_else(|| v.as_i64().map(|n| n as f64))
        .or_else(|| v.as_u64().map(|n| n as f64))
        .or_else(|| v.as_str().and_then(|s| s.trim().parse::<f64>().ok()))
        .map(|x| x as f32)
        .filter(|x| x.is_finite())
}

fn val_i32(v: &Value) -> Option<i32> {
    v.as_i64()
        .map(|n| n as i32)
        .or_else(|| v.as_u64().map(|n| n as i32))
        .or_else(|| v.as_str().and_then(|s| s.trim().parse::<i32>().ok()))
}

fn val_bool(v: &Value) -> Option<bool> {
    v.as_bool()
        .or_else(|| v.as_i64().map(|n| n != 0))
        .or_else(|| v.as_u64().map(|n| n != 0))
        .or_else(|| {
            v.as_str().and_then(|s| match s.trim().to_ascii_lowercase().as_str() {
                "true" | "1" => Some(true),
                "false" | "0" => Some(false),
                _ => None,
            })
        })
}

fn val_bytes<'a>(v: &'a Value) -> Option<&'a [u8]> {
    match v {
        Value::Binary(b) => Some(b.as_slice()),
        Value::Ext(_, b) => Some(b.as_slice()),
        _ => None,
    }
}

fn decode_nested_msgpack(v: &Value) -> Option<Value> {
    if let Some(bytes) = val_bytes(v) {
        let mut cur = std::io::Cursor::new(bytes);
        rmpv::decode::read_value(&mut cur).ok()
    } else if v.is_map() || v.is_array() {
        Some(v.clone())
    } else {
        None
    }
}

fn parse_xml_bool(s: &str) -> Option<bool> {
    match s.trim().to_ascii_lowercase().as_str() {
        "true" | "1" => Some(true),
        "false" | "0" => Some(false),
        _ => None,
    }
}

fn attr_f32(n: roxmltree::Node<'_, '_>, key: &str) -> Option<f32> {
    n.attribute(key)?
        .trim()
        .parse::<f32>()
        .ok()
        .filter(|v| v.is_finite())
}

fn attr_i32(n: roxmltree::Node<'_, '_>, key: &str) -> Option<i32> {
    n.attribute(key)?.trim().parse::<i32>().ok()
}

fn attr_bool(n: roxmltree::Node<'_, '_>, key: &str) -> Option<bool> {
    parse_xml_bool(n.attribute(key)?)
}

fn parse_xml_lenient(raw: &str) -> Option<String> {
    let trimmed = raw.trim_matches(|c: char| c == '\u{feff}' || c == '\0' || c.is_whitespace());
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed.to_string())
}

// ============================================================================
// 1. TreeNodeNaming (`org.njaecha.plugins.treenodenaming`)
// ============================================================================

pub fn parse_tree_node_naming(blocks: &Value) -> Option<BTreeMap<String, String>> {
    let data = plugin_data_map(blocks, "org.njaecha.plugins.treenodenaming")?;
    let names_val = decode_nested_msgpack(map_get(data, "names")?)?;
    let entries = names_val.as_map()?;
    let mut out = BTreeMap::new();
    for (k, v) in entries {
        let Some(dic_key) = val_i32(k) else { continue };
        let Some(name) = v.as_str().map(str::trim).filter(|s| !s.is_empty()) else { continue };
        out.insert(dic_key.to_string(), name.to_string());
    }
    (!out.is_empty()).then_some(out)
}

// ============================================================================
// 2. SaveCameraObjectFOV (`com.rikkibalboa.bepinex.savecameraobjectfov`)
// ============================================================================

#[derive(Clone, Debug, Default, Serialize)]
pub struct CameraFovData {
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub cameras: BTreeMap<String, f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub main_fov: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub camera_index: Option<i32>,
}

pub fn parse_save_camera_fov(blocks: &Value) -> Option<CameraFovData> {
    let data = plugin_data_map(blocks, "com.rikkibalboa.bepinex.savecameraobjectfov")?;
    let mut out = CameraFovData::default();
    if let Some(cams_raw) = map_get(data, "cameras").and_then(decode_nested_msgpack) {
        if let Some(entries) = cams_raw.as_map() {
            for (k, v) in entries {
                let (Some(dic_key), Some(fov)) = (val_i32(k), val_f32(v)) else { continue };
                if (1.0..=179.0).contains(&fov) {
                    out.cameras.insert(dic_key.to_string(), fov);
                }
            }
        }
    }
    out.main_fov = map_get(data, "mainFov")
        .and_then(val_f32)
        .filter(|f| (1.0..=179.0).contains(f));
    out.camera_index = map_get(data, "cameraIndex").and_then(val_i32);
    if out.cameras.is_empty() && out.main_fov.is_none() && out.camera_index.is_none() {
        None
    } else {
        Some(out)
    }
}

// ============================================================================
// 3. MoarCamz (`orange.spork.moarcamzplugin`)
// ============================================================================

#[derive(Clone, Debug, Serialize)]
pub struct MoarCamSlot {
    pub slot: i32,
    pub pos: [f32; 3],
    pub rot: [f32; 3],
    pub distance: [f32; 3],
    pub fov: f32,
    pub offset_pos: [f32; 3],
    pub center_target: i32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub center_target_bone: String,
    pub center_target_engaged: bool,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct MoarCamzSceneData {
    pub slots: Vec<MoarCamSlot>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_selection: Option<i32>,
}

fn msgpack_vec3(v: Option<&Value>) -> Option<[f32; 3]> {
    let v = v?;
    if let Some(a) = v.as_array() {
        if a.len() >= 3 {
            return Some([val_f32(&a[0])?, val_f32(&a[1])?, val_f32(&a[2])?]);
        }
    }
    if v.is_map() {
        let x = map_get(v, "x").or_else(|| map_get(v, "X")).and_then(val_f32)?;
        let y = map_get(v, "y").or_else(|| map_get(v, "Y")).and_then(val_f32)?;
        let z = map_get(v, "z").or_else(|| map_get(v, "Z")).and_then(val_f32)?;
        return Some([x, y, z]);
    }
    None
}

pub fn parse_moar_camz(blocks: &Value) -> Option<MoarCamzSceneData> {
    let data = plugin_data_map(blocks, "orange.spork.moarcamzplugin")?;
    let list_val = map_get(data, "MoarCamz").and_then(decode_nested_msgpack)?;
    let arr = list_val.as_array()?;
    let mut slots = Vec::new();
    for item in arr {
        if !item.is_map() {
            continue;
        }
        let slot = map_get(item, "SlotNumber").and_then(val_i32).unwrap_or(slots.len() as i32);
        let pos = msgpack_vec3(map_get(item, "Position")).unwrap_or([0.0; 3]);
        let rot = msgpack_vec3(map_get(item, "Rotation")).unwrap_or([0.0; 3]);
        let distance = msgpack_vec3(map_get(item, "Distance")).unwrap_or([0.0; 3]);
        let fov = map_get(item, "FOV").and_then(val_f32).unwrap_or(23.0);
        let offset_pos = msgpack_vec3(map_get(item, "OffsetPosition")).unwrap_or([0.0; 3]);
        let center_target = map_get(item, "CenterTarget").and_then(val_i32).unwrap_or(-1);
        let center_target_bone = map_get(item, "CenterTargetBone")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        let center_target_engaged = map_get(item, "CenterTargetEngaged")
            .and_then(val_bool)
            .unwrap_or(false);
        // Skip completely unset empty slots (`pos==0 && rot==0 && distance==0 && !engaged`)
        let is_unset = pos == [0.0; 3]
            && rot == [0.0; 3]
            && distance == [0.0; 3]
            && !center_target_engaged;
        if is_unset {
            continue;
        }
        slots.push(MoarCamSlot {
            slot,
            pos,
            rot,
            distance,
            fov: fov.clamp(1.0, 170.0),
            offset_pos,
            center_target,
            center_target_bone,
            center_target_engaged,
        });
    }
    if slots.is_empty() {
        return None;
    }
    let last_selection = map_get(data, "MoarCamzLastSelection").and_then(val_i32);
    Some(MoarCamzSceneData { slots, last_selection })
}

// ============================================================================
// 4. StudioSceneSettings (`com.deathweasel.bepinex.studioscenesettings`)
// ============================================================================

#[derive(Clone, Debug, Default, Serialize)]
pub struct StudioSceneSettingsData {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub near_clip: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub far_clip: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub shadow_distance: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub map_masking: Option<bool>,
}

pub fn parse_studio_scene_settings(blocks: &Value) -> Option<StudioSceneSettingsData> {
    let data = plugin_data_map(blocks, "com.deathweasel.bepinex.studioscenesettings")?;
    let near_clip = map_get(data, "NearClipPlane").and_then(val_f32).filter(|v| *v > 0.0);
    let far_clip = map_get(data, "FarClipPlane").and_then(val_f32).filter(|v| *v > 0.0);
    let shadow_distance = map_get(data, "ShadowDistance").and_then(val_f32).filter(|v| *v > 0.0);
    let map_masking = map_get(data, "MapMasking").and_then(val_bool);
    if near_clip.is_none() && far_clip.is_none() && shadow_distance.is_none() && map_masking.is_none() {
        None
    } else {
        Some(StudioSceneSettingsData {
            near_clip,
            far_clip,
            shadow_distance,
            map_masking,
        })
    }
}

// ============================================================================
// 5. StudioImageEmbed (`com.deathweasel.bepinex.studioimageembed`)
// ============================================================================

fn detect_image_ext(bytes: &[u8]) -> Option<&'static str> {
    if bytes.len() >= 8 && &bytes[0..8] == b"\x89PNG\r\n\x1a\n" {
        Some("png")
    } else if bytes.len() >= 3 && &bytes[0..3] == b"\xff\xd8\xff" {
        Some("jpg")
    } else if bytes.len() >= 2 && &bytes[0..2] == b"BM" {
        Some("bmp")
    } else if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("webp")
    } else {
        None
    }
}

pub fn export_studio_image_embed(
    blocks: &Value,
    out_dir: &Path,
) -> (Option<String>, Option<String>) {
    let Some(data) = plugin_data_map(blocks, "com.deathweasel.bepinex.studioimageembed") else {
        return (None, None);
    };
    let write_one = |key: &str, stem: &str| -> Option<String> {
        let bytes = map_get(data, key).and_then(val_bytes)?;
        let ext = detect_image_ext(bytes)?;
        let file_name = format!("{stem}.{ext}");
        let path = out_dir.join(&file_name);
        std::fs::write(&path, bytes).ok()?;
        Some(file_name)
    };
    (write_one("BGData", "embedded_bg"), write_one("FrameData", "embedded_frame"))
}

// ============================================================================
// 6. KKPE (`kkpe` -> `sceneInfo` & character `characterInfo`)
// ============================================================================

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct KkpeBoneOverride {
    pub path: String,
    pub bone: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pos: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quat: Option<[f32; 4]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub euler: Option<[f32; 3]>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scale: Option<[f32; 3]>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct KkpeMorphOverride {
    pub renderer: String,
    pub index: i32,
    pub weight: f32,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct KkpeElementData {
    pub dic_key: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub eyes_ptn: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub eyes_open: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mouth_ptn: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mouth_open: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub eyebrows_ptn: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub eyebrows_open: Option<f32>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub bones: Vec<KkpeBoneOverride>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub morphs: Vec<KkpeMorphOverride>,
}

impl KkpeElementData {
    pub fn is_empty(&self) -> bool {
        self.eyes_ptn.is_none()
            && self.eyes_open.is_none()
            && self.mouth_ptn.is_none()
            && self.mouth_open.is_none()
            && self.eyebrows_ptn.is_none()
            && self.eyebrows_open.is_none()
            && self.bones.is_empty()
            && self.morphs.is_empty()
    }
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct KkpeSceneData {
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub characters: Vec<KkpeElementData>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub items: Vec<KkpeElementData>,
}

fn parse_kkpe_element_node(
    node: roxmltree::Node<'_, '_>,
    dic_key: i32,
    is_character: bool,
) -> Option<KkpeElementData> {
    // MainWindow.cs: character PoseController defaults `enabled = true`, item PoseController defaults `enabled = false`.
    let default_enabled = is_character;
    let enabled = attr_bool(node, "enabled").unwrap_or(default_enabled);
    if !enabled {
        return None;
    }
    let mut out = KkpeElementData {
        dic_key,
        ..Default::default()
    };
    for child in node.children().filter(|c| c.is_element()) {
        match child.tag_name().name() {
            "advancedObjects" => {
                for obj in child.children().filter(|c| c.is_element() && c.tag_name().name() == "object") {
                    let Some(path) = obj.attribute("name").map(str::trim).filter(|s| !s.is_empty()) else {
                        continue;
                    };
                    let bone = leaf_bone_name(path);
                    if bone.is_empty() {
                        continue;
                    }
                    let pos = match (attr_f32(obj, "posX"), attr_f32(obj, "posY"), attr_f32(obj, "posZ")) {
                        (Some(x), Some(y), Some(z)) => Some([x, y, z]),
                        _ => None,
                    };
                    let (quat, euler) = match (
                        attr_f32(obj, "rotX"),
                        attr_f32(obj, "rotY"),
                        attr_f32(obj, "rotZ"),
                        attr_f32(obj, "rotW"),
                    ) {
                        (Some(x), Some(y), Some(z), Some(w)) => {
                            let q = crate::finalik::qnorm([x, y, z, w]);
                            (Some(q), Some(crate::pose::quat_to_unity_euler(q)))
                        }
                        _ => (None, None),
                    };
                    let scale = match (attr_f32(obj, "scaleX"), attr_f32(obj, "scaleY"), attr_f32(obj, "scaleZ")) {
                        (Some(x), Some(y), Some(z)) => Some([x, y, z]),
                        _ => None,
                    };
                    if pos.is_some() || quat.is_some() || scale.is_some() {
                        out.bones.push(KkpeBoneOverride {
                            path: path.to_string(),
                            bone,
                            pos,
                            quat,
                            euler,
                            scale,
                        });
                    }
                }
            }
            "skinnedMeshes" => {
                if is_character {
                    out.eyes_ptn = attr_i32(child, "eyesPtn");
                    out.eyes_open = attr_f32(child, "eyesOpen");
                    out.mouth_ptn = attr_i32(child, "mouthPtn");
                    out.mouth_open = attr_f32(child, "mouthOpen");
                    out.eyebrows_ptn = attr_i32(child, "eyebrowsPtn");
                    out.eyebrows_open = attr_f32(child, "eyebrowsOpen");
                }
                for smr in child.children().filter(|c| c.is_element() && c.tag_name().name() == "skinnedMesh") {
                    let Some(renderer) = smr.attribute("name").map(str::trim).filter(|s| !s.is_empty()) else {
                        continue;
                    };
                    for bs in smr.children().filter(|c| c.is_element() && c.tag_name().name() == "blendShape") {
                        let (Some(index), Some(weight)) = (attr_i32(bs, "index"), attr_f32(bs, "weight")) else {
                            continue;
                        };
                        if index >= 0 {
                            out.morphs.push(KkpeMorphOverride {
                                renderer: renderer.to_string(),
                                index,
                                weight: weight.clamp(0.0, 100.0),
                            });
                        }
                    }
                }
            }
            _ => {}
        }
    }
    (!out.is_empty()).then_some(out)
}

pub fn parse_kkpe_character_xml(xml: &str, char_key: i32) -> Option<KkpeElementData> {
    let cleaned = parse_xml_lenient(xml)?;
    let doc = roxmltree::Document::parse(&cleaned).ok()?;
    let root = doc.root_element();
    if root.tag_name().name() != "characterInfo" {
        return None;
    }
    parse_kkpe_element_node(root, char_key, true)
}

pub fn parse_kkpe_scene_items_xml(xml: &str) -> Vec<KkpeElementData> {
    let Some(cleaned) = parse_xml_lenient(xml) else { return Vec::new() };
    let Ok(doc) = roxmltree::Document::parse(&cleaned) else { return Vec::new() };
    let root = doc.root_element();
    if root.tag_name().name() != "root" {
        return Vec::new();
    }
    let mut items = Vec::new();
    for item_node in root.children().filter(|c| c.is_element() && c.tag_name().name() == "itemInfo") {
        let Some(dic_key) = attr_i32(item_node, "index") else { continue };
        if let Some(elem) = parse_kkpe_element_node(item_node, dic_key, false) {
            items.push(elem);
        }
    }
    items
}

pub fn extract_kkpe(
    scene_blocks: Option<&Value>,
    char_card_bytes: &HashMap<i32, Vec<u8>>,
) -> Option<KkpeSceneData> {
    let mut out = KkpeSceneData::default();
    if let Some(blocks) = scene_blocks {
        if let Some(data) = plugin_data_map(blocks, "kkpe") {
            if let Some(xml) = map_get(data, "sceneInfo").and_then(|v| v.as_str()) {
                out.items = parse_kkpe_scene_items_xml(xml);
            }
        }
    }
    let mut sorted_chars: Vec<(&i32, &Vec<u8>)> = char_card_bytes.iter().collect();
    sorted_chars.sort_by_key(|(k, _)| **k);
    for (&char_key, card) in sorted_chars {
        let Ok(card_blocks) = crate::appearance::blocks_from_card(card) else { continue };
        let Some(kkex_bytes) = card_blocks.get("KKEx") else { continue };
        let mut cur = std::io::Cursor::new(kkex_bytes.as_slice());
        let Ok(kkex) = rmpv::decode::read_value(&mut cur) else { continue };
        let Some(data) = plugin_data_map(&kkex, "kkpe") else { continue };
        let Some(xml) = map_get(data, "characterInfo").and_then(|v| v.as_str()) else { continue };
        if let Some(elem) = parse_kkpe_character_xml(xml, char_key) {
            out.characters.push(elem);
        }
    }
    if out.characters.is_empty() && out.items.is_empty() {
        None
    } else {
        Some(out)
    }
}

// ============================================================================
// 7. NodesConstraints (`nodesConstraints` + `KK_AnimationController` fallback)
// ============================================================================

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct SceneNodeConstraint {
    pub load_id: i32,
    pub enabled: bool,
    /// `-2` means Studio's main camera; `>= 0` is the parent object's `dicKey`.
    pub parent_key: i32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub parent_path: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub parent_bone: String,
    pub child_key: i32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub child_path: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub child_bone: String,
    /// `>= 0` when the child transform is a character Studio IK effector (`cf_t_*`).
    pub child_ik_effector: i32,
    pub position: bool,
    pub mirror_position: bool,
    pub pos_offset: [f32; 3],
    pub rotation: bool,
    pub mirror_rotation: bool,
    pub look_at: bool,
    pub rot_offset: [f32; 4],
    pub scale: bool,
    pub mirror_scale: bool,
    pub scale_offset: [f32; 3],
    pub orig_parent_pos: [f32; 3],
    pub orig_parent_rot: [f32; 4],
    pub orig_parent_scale: [f32; 3],
    pub pos_factor: f32,
    pub rot_factor: f32,
    pub scale_factor: f32,
    pub pos_locks: [bool; 3],
    pub rot_locks: [bool; 3],
    pub scale_locks: [bool; 3],
    pub fix_dynamic_bone: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub alias: String,
}

pub fn parse_nodes_constraints_xml(xml: &str, sorted_keys: &[i32]) -> Vec<SceneNodeConstraint> {
    let Some(cleaned) = parse_xml_lenient(xml) else { return Vec::new() };
    let Ok(doc) = roxmltree::Document::parse(&cleaned) else { return Vec::new() };
    let root = doc.root_element();
    if root.tag_name().name() != "constraints" {
        return Vec::new();
    }
    let mut out = Vec::new();
    for (seq_idx, c) in root
        .children()
        .filter(|n| n.is_element() && n.tag_name().name() == "constraint")
        .enumerate()
    {
        let Some(p_idx) = attr_i32(c, "parentObjectIndex") else { continue };
        let parent_key = if p_idx == -2 {
            -2
        } else if p_idx >= 0 && (p_idx as usize) < sorted_keys.len() {
            sorted_keys[p_idx as usize]
        } else {
            continue;
        };
        let Some(c_idx) = attr_i32(c, "childObjectIndex") else { continue };
        if c_idx < 0 || (c_idx as usize) >= sorted_keys.len() {
            continue;
        }
        let child_key = sorted_keys[c_idx as usize];
        let parent_path = if parent_key == -2 {
            String::new()
        } else {
            c.attribute("parentPath").unwrap_or("").trim().to_string()
        };
        let child_path = c
            .attribute("childPath")
            .or_else(|| c.attribute("childName"))
            .unwrap_or("")
            .trim()
            .to_string();
        let parent_bone = if parent_path.is_empty() {
            String::new()
        } else {
            leaf_bone_name(&parent_path)
        };
        let child_ik_effector = if child_path.is_empty() {
            -1
        } else {
            studio_ik_effector_from_path(&child_path).unwrap_or(-1)
        };
        let child_bone = if child_path.is_empty() || child_ik_effector >= 0 {
            String::new()
        } else {
            leaf_bone_name(&child_path)
        };
        let load_id = attr_i32(c, "uniqueLoadId").unwrap_or(seq_idx as i32);
        let enabled = attr_bool(c, "enabled").unwrap_or(true);
        let position = attr_bool(c, "position").unwrap_or(false);
        let mirror_position = attr_bool(c, "mirrorPosition").unwrap_or(false);
        let pos_offset = [
            attr_f32(c, "positionOffsetX").unwrap_or(0.0),
            attr_f32(c, "positionOffsetY").unwrap_or(0.0),
            attr_f32(c, "positionOffsetZ").unwrap_or(0.0),
        ];
        let rotation = attr_bool(c, "rotation").unwrap_or(false);
        let mirror_rotation = attr_bool(c, "mirrorRotation").unwrap_or(false);
        let look_at = attr_bool(c, "lookAt").unwrap_or(false);
        let rot_offset = crate::finalik::qnorm([
            attr_f32(c, "rotationOffsetX").unwrap_or(0.0),
            attr_f32(c, "rotationOffsetY").unwrap_or(0.0),
            attr_f32(c, "rotationOffsetZ").unwrap_or(0.0),
            attr_f32(c, "rotationOffsetW").unwrap_or(1.0),
        ]);
        let scale = attr_bool(c, "scale").unwrap_or(false);
        let mirror_scale = attr_bool(c, "mirrorScale").unwrap_or(false);
        let scale_offset = [
            attr_f32(c, "scaleOffsetX").unwrap_or(1.0),
            attr_f32(c, "scaleOffsetY").unwrap_or(1.0),
            attr_f32(c, "scaleOffsetZ").unwrap_or(1.0),
        ];
        if !position && !rotation && !scale {
            continue;
        }
        let orig_parent_pos = [
            attr_f32(c, "originalParentPositionX").unwrap_or(0.0),
            attr_f32(c, "originalParentPositionY").unwrap_or(0.0),
            attr_f32(c, "originalParentPositionZ").unwrap_or(0.0),
        ];
        let orig_parent_rot = crate::finalik::qnorm([
            attr_f32(c, "originalParentRotationX").unwrap_or(0.0),
            attr_f32(c, "originalParentRotationY").unwrap_or(0.0),
            attr_f32(c, "originalParentRotationZ").unwrap_or(0.0),
            attr_f32(c, "originalParentRotationW").unwrap_or(1.0),
        ]);
        let orig_parent_scale = [
            attr_f32(c, "originalParentScaleX").unwrap_or(1.0),
            attr_f32(c, "originalParentScaleY").unwrap_or(1.0),
            attr_f32(c, "originalParentScaleZ").unwrap_or(1.0),
        ];
        let pos_factor = attr_f32(c, "positionChangeFactor").unwrap_or(1.0);
        let rot_factor = attr_f32(c, "rotationChangeFactor").unwrap_or(1.0);
        let scale_factor = attr_f32(c, "scaleChangeFactor").unwrap_or(1.0);
        let pos_locks = [
            attr_bool(c, "positionLocksX").unwrap_or(true),
            attr_bool(c, "positionLocksY").unwrap_or(true),
            attr_bool(c, "positionLocksZ").unwrap_or(true),
        ];
        let rot_locks = [
            attr_bool(c, "rotationLocksX").unwrap_or(true),
            attr_bool(c, "rotationLocksY").unwrap_or(true),
            attr_bool(c, "rotationLocksZ").unwrap_or(true),
        ];
        let scale_locks = [
            attr_bool(c, "scaleLocksX").unwrap_or(true),
            attr_bool(c, "scaleLocksY").unwrap_or(true),
            attr_bool(c, "scaleLocksZ").unwrap_or(true),
        ];
        let fix_dynamic_bone = attr_bool(c, "dynamic").unwrap_or(false);
        let alias = c.attribute("alias").unwrap_or("").to_string();
        out.push(SceneNodeConstraint {
            load_id,
            enabled,
            parent_key,
            parent_path,
            parent_bone,
            child_key,
            child_path,
            child_bone,
            child_ik_effector,
            position,
            mirror_position,
            pos_offset,
            rotation,
            mirror_rotation,
            look_at,
            rot_offset,
            scale,
            mirror_scale,
            scale_offset,
            orig_parent_pos,
            orig_parent_rot,
            orig_parent_scale,
            pos_factor,
            rot_factor,
            scale_factor,
            pos_locks,
            rot_locks,
            scale_locks,
            fix_dynamic_bone,
            alias,
        });
    }
    out
}

pub fn extract_nodes_constraints(
    scene_blocks: Option<&Value>,
    sorted_keys: &[i32],
) -> Vec<SceneNodeConstraint> {
    let Some(blocks) = scene_blocks else { return Vec::new() };
    let mut out = Vec::new();
    if let Some(data) = plugin_data_map(blocks, "nodesConstraints") {
        if let Some(xml) = map_get(data, "constraints").and_then(|v| v.as_str()) {
            out.extend(parse_nodes_constraints_xml(xml, sorted_keys));
        }
    }
    // KK_AnimationController scene fallback (`AnimationInfo` list of `{ CharDicKey, ItemDicKey, IKPart, Version }`).
    if let Some(data) = plugin_data_map(blocks, "KK_AnimationController") {
        if let Some(arr) = map_get(data, "AnimationInfo").and_then(|v| v.as_array()) {
            for raw in arr {
                let Some(info) = decode_nested_msgpack(raw) else { continue };
                let Some(char_key) = map_get(&info, "CharDicKey").and_then(val_i32) else { continue };
                let Some(item_key) = map_get(&info, "ItemDicKey").and_then(val_i32) else { continue };
                let Some(ik_part) = map_get(&info, "IKPart").and_then(|v| v.as_str()) else { continue };
                let Some(effector) = studio_ik_effector_from_path(ik_part) else { continue };
                if !sorted_keys.contains(&char_key) || !sorted_keys.contains(&item_key) {
                    continue;
                }
                let load_id = -1000 - (out.len() as i32);
                out.push(SceneNodeConstraint {
                    load_id,
                    enabled: true,
                    parent_key: item_key,
                    parent_path: String::new(),
                    parent_bone: String::new(),
                    child_key: char_key,
                    child_path: ik_part.to_string(),
                    child_bone: String::new(),
                    child_ik_effector: effector,
                    position: true,
                    mirror_position: false,
                    pos_offset: [0.0; 3],
                    rotation: true,
                    mirror_rotation: false,
                    look_at: false,
                    rot_offset: [0.0, 0.0, 0.0, 1.0],
                    scale: false,
                    mirror_scale: false,
                    scale_offset: [1.0; 3],
                    orig_parent_pos: [0.0; 3],
                    orig_parent_rot: [0.0, 0.0, 0.0, 1.0],
                    orig_parent_scale: [1.0; 3],
                    pos_factor: 1.0,
                    rot_factor: 1.0,
                    scale_factor: 1.0,
                    pos_locks: [true; 3],
                    rot_locks: [true; 3],
                    scale_locks: [true; 3],
                    fix_dynamic_bone: false,
                    alias: String::new(),
                });
            }
        }
    }
    out
}

// ============================================================================
// 8. Timeline (`timeline` -> `sceneInfo` XML)
// ============================================================================

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct TimelineCurvePoint {
    pub t: f32,
    pub v: f32,
    pub in_t: f32,
    pub out_t: f32,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct TimelineKeyframe {
    pub time: f32,
    /// Value components (`[v]` for scalar/bool/int, `[x,y,z]` for Vector3, `[x,y,z,w]` for Quaternion/Color/Vector4, or `N` morph weights).
    pub values: Vec<f32>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub names: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub curve: Vec<TimelineCurvePoint>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct TimelineInterpolableTrack {
    pub owner: String,
    pub id: String,
    /// `-1` for global tracks (`cameraPos`, `cameraRot`, `cameraFOV`, `cameraOPos`, `cameraORot`, `cameraOZoom`, `timeScale`).
    pub dic_key: i32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub target_path: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub target_bone: String,
    /// `>= 0` when `guideObject*` targets a character Studio IK effector (`cf_t_*`).
    pub target_ik_effector: i32,
    pub param_int: i32,
    pub keyframes: Vec<TimelineKeyframe>,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct TimelineSceneData {
    pub duration: f32,
    pub tracks: Vec<TimelineInterpolableTrack>,
}

fn read_curve_points(kf_node: roxmltree::Node<'_, '_>) -> Vec<TimelineCurvePoint> {
    let mut pts = Vec::new();
    for ck in kf_node
        .children()
        .filter(|n| n.is_element() && n.tag_name().name() == "curveKeyframe")
    {
        let (Some(t), Some(v), Some(in_t), Some(out_t)) = (
            attr_f32(ck, "time"),
            attr_f32(ck, "value"),
            attr_f32(ck, "inTangent"),
            attr_f32(ck, "outTangent"),
        ) else {
            continue;
        };
        pts.push(TimelineCurvePoint { t, v, in_t, out_t });
    }
    pts.sort_by(|a, b| a.t.total_cmp(&b.t));
    // Omit default linear curve `[(0, 0, 1, 1), (1, 1, 1, 1)]` to keep JSON compact.
    if pts.len() == 2
        && (pts[0].t - 0.0).abs() < 1e-5
        && (pts[0].v - 0.0).abs() < 1e-5
        && (pts[0].out_t - 1.0).abs() < 1e-4
        && (pts[1].t - 1.0).abs() < 1e-5
        && (pts[1].v - 1.0).abs() < 1e-5
        && (pts[1].in_t - 1.0).abs() < 1e-4
    {
        return Vec::new();
    }
    pts
}

fn parse_timeline_keyframe_value(
    owner: &str,
    id: &str,
    kf_node: roxmltree::Node<'_, '_>,
) -> Option<(Vec<f32>, Vec<String>)> {
    match (owner, id) {
        ("Timeline", "cameraOPos" | "cameraPos" | "guideObjectPos" | "guideObjectScale")
        | ("KKPE", "bonePos" | "boneScale") => {
            let x = attr_f32(kf_node, "valueX")?;
            let y = attr_f32(kf_node, "valueY")?;
            let z = attr_f32(kf_node, "valueZ")?;
            Some((vec![x, y, z], Vec::new()))
        }
        ("Timeline", "cameraORot" | "cameraRot" | "guideObjectRot") | ("KKPE", "boneRot") => {
            let x = attr_f32(kf_node, "valueX")?;
            let y = attr_f32(kf_node, "valueY")?;
            let z = attr_f32(kf_node, "valueZ")?;
            let w = attr_f32(kf_node, "valueW")?;
            let q = crate::finalik::qnorm([x, y, z, w]);
            Some((vec![q[0], q[1], q[2], q[3]], Vec::new()))
        }
        (
            "Timeline",
            "cameraOZoom"
            | "cameraFOV"
            | "timeScale"
            | "objectAnimationSpeed"
            | "charAnimationPattern"
            | "itemAnimationTime"
            | "charAnimationTime"
            | "blush"
            | "femaleNipples"
            | "characterEyesOpen"
            | "characterEyebrowsOpen"
            | "characterMouthOpen"
            | "itemAlpha"
            | "itemEmissionPower"
            | "itemLightCancel"
            | "itemLineWidth"
            | "itemPatternRotation1"
            | "itemPatternRotation2"
            | "itemPatternRotation3"
            | "itemPanelPatternRotation"
            | "lightStrength"
            | "lightRange"
            | "lightSpotAngle",
        )
        | ("KKPE", "lastBlendShape") => {
            let v = attr_f32(kf_node, "value")?;
            Some((vec![v], Vec::new()))
        }
        (
            "Timeline",
            "objectEnabled" | "lightOnOff" | "lightShadows" | "itemPatternClamp1" | "itemPatternClamp2"
            | "itemPatternClamp3" | "itemPanelPatternClamp",
        )
        | ("NodesConstraints", "constraintEnabled") => {
            let b = attr_bool(kf_node, "value").or_else(|| attr_f32(kf_node, "value").map(|v| v != 0.0))?;
            Some((vec![if b { 1.0 } else { 0.0 }], Vec::new()))
        }
        (
            "Timeline",
            "tears"
            | "charClothes"
            | "juice"
            | "characterNeck"
            | "characterEyes"
            | "characterEyebrows"
            | "characterMouth"
            | "characterLeftHand"
            | "characterRightHand",
        ) => {
            let n = attr_i32(kf_node, "value")?;
            Some((vec![n as f32], Vec::new()))
        }
        (
            "Timeline",
            "lightColor"
            | "itemColor1"
            | "itemColor2"
            | "itemColor3"
            | "itemColor4"
            | "itemPatternColor1"
            | "itemPatternColor2"
            | "itemPatternColor3"
            | "itemShadowColor"
            | "itemEmissionColor"
            | "itemLineColor"
            | "itemPanelColor",
        ) => {
            let r = attr_f32(kf_node, "valueR")?;
            let g = attr_f32(kf_node, "valueG")?;
            let b = attr_f32(kf_node, "valueB")?;
            let a = attr_f32(kf_node, "valueA").unwrap_or(1.0);
            Some((vec![r, g, b, a], Vec::new()))
        }
        (
            "Timeline",
            "itemPatternUV1" | "itemPatternUV2" | "itemPatternUV3" | "itemPanelPatternUV",
        ) => {
            let x = attr_f32(kf_node, "valueX")?;
            let y = attr_f32(kf_node, "valueY")?;
            let z = attr_f32(kf_node, "valueZ")?;
            let w = attr_f32(kf_node, "valueW")?;
            Some((vec![x, y, z, w], Vec::new()))
        }
        ("KKPE", "groupBlendShape" | "groupBlendShapeLink") => {
            let count = attr_i32(kf_node, "valueCount")?;
            if !(1..=4096).contains(&count) {
                return None;
            }
            let mut vals = Vec::with_capacity(count as usize);
            let mut names = Vec::with_capacity(count as usize);
            let mut any_name = false;
            for i in 0..count {
                let v = attr_f32(kf_node, &format!("value{i}")).unwrap_or(0.0);
                vals.push(v);
                let nm = kf_node.attribute(format!("name{i}").as_str()).unwrap_or("").to_string();
                if !nm.is_empty() {
                    any_name = true;
                }
                names.push(nm);
            }
            if !any_name {
                names.clear();
            }
            Some((vals, names))
        }
        _ => None,
    }
}

pub fn parse_timeline_xml(xml: &str, sorted_keys: &[i32]) -> Option<TimelineSceneData> {
    let cleaned = parse_xml_lenient(xml)?;
    let doc = roxmltree::Document::parse(&cleaned).ok()?;
    let root = doc.root_element();
    if root.tag_name().name() != "root" {
        return None;
    }
    let mut tracks = Vec::new();
    let mut max_kf_time = 0.0f32;

    fn walk_tree(
        node: roxmltree::Node<'_, '_>,
        sorted_keys: &[i32],
        tracks: &mut Vec<TimelineInterpolableTrack>,
        max_kf_time: &mut f32,
    ) {
        for child in node.children().filter(|c| c.is_element()) {
            match child.tag_name().name() {
                "interpolableGroup" => walk_tree(child, sorted_keys, tracks, max_kf_time),
                "interpolable" => {
                    if !attr_bool(child, "enabled").unwrap_or(true) {
                        continue;
                    }
                    let Some(owner) = child.attribute("owner") else { continue };
                    let Some(id) = child.attribute("id") else { continue };
                    let dic_key = if let Some(obj_idx) = attr_i32(child, "objectIndex") {
                        if obj_idx < 0 || (obj_idx as usize) >= sorted_keys.len() {
                            continue;
                        }
                        sorted_keys[obj_idx as usize]
                    } else {
                        -1
                    };
                    let mut target_path = String::new();
                    let mut target_bone = String::new();
                    let mut target_ik_effector = -1;
                    let mut param_int = -1;

                    match (owner, id) {
                        ("Timeline", "guideObjectPos" | "guideObjectRot" | "guideObjectScale") => {
                            target_path = child.attribute("guideObjectPath").unwrap_or("").trim().to_string();
                            if !target_path.is_empty() {
                                if let Some(eff) = studio_ik_effector_from_path(&target_path) {
                                    target_ik_effector = eff;
                                } else {
                                    target_bone = leaf_bone_name(&target_path);
                                }
                            }
                        }
                        ("Timeline", "charClothes" | "juice") => {
                            let Some(p) = attr_i32(child, "parameter") else { continue };
                            param_int = p;
                        }
                        ("KKPE", "bonePos" | "boneRot" | "boneScale") => {
                            target_path = child.attribute("parameter").unwrap_or("").trim().to_string();
                            target_bone = leaf_bone_name(&target_path);
                            if target_bone.is_empty() {
                                continue;
                            }
                        }
                        ("KKPE", "lastBlendShape") => {
                            target_path = child.attribute("parameter1").unwrap_or("").trim().to_string();
                            let Some(idx) = attr_i32(child, "parameter2") else { continue };
                            if target_path.is_empty() || idx < 0 {
                                continue;
                            }
                            param_int = idx;
                        }
                        ("KKPE", "groupBlendShape" | "groupBlendShapeLink") => {
                            target_path = child.attribute("parameter").unwrap_or("").trim().to_string();
                            if target_path.is_empty() {
                                continue;
                            }
                        }
                        ("NodesConstraints", "constraintEnabled") => {
                            let Some(load_id) = attr_i32(child, "parameter") else { continue };
                            param_int = load_id;
                        }
                        _ => {}
                    }

                    let mut keyframes = Vec::new();
                    for kf_node in child
                        .children()
                        .filter(|k| k.is_element() && k.tag_name().name() == "keyframe")
                    {
                        let Some(time) = attr_f32(kf_node, "time") else { continue };
                        if time < 0.0 {
                            continue;
                        }
                        let Some((values, names)) = parse_timeline_keyframe_value(owner, id, kf_node) else {
                            continue;
                        };
                        if time > *max_kf_time {
                            *max_kf_time = time;
                        }
                        keyframes.push(TimelineKeyframe {
                            time,
                            values,
                            names,
                            curve: read_curve_points(kf_node),
                        });
                    }
                    if keyframes.is_empty() {
                        continue;
                    }
                    keyframes.sort_by(|a, b| a.time.total_cmp(&b.time));
                    // Keep only the first groupBlendShape keyframe's `names` array to avoid repeating identical blendshape names per keyframe.
                    for kf in keyframes.iter_mut().skip(1) {
                        kf.names.clear();
                    }
                    tracks.push(TimelineInterpolableTrack {
                        owner: owner.to_string(),
                        id: id.to_string(),
                        dic_key,
                        target_path,
                        target_bone,
                        target_ik_effector,
                        param_int,
                        keyframes,
                    });
                }
                _ => {}
            }
        }
    }

    walk_tree(root, sorted_keys, &mut tracks, &mut max_kf_time);
    if tracks.is_empty() {
        return None;
    }
    let duration = attr_f32(root, "duration")
        .filter(|d| *d > 0.0)
        .unwrap_or_else(|| if max_kf_time > 1e-4 { max_kf_time } else { 10.0 });
    Some(TimelineSceneData { duration, tracks })
}

pub fn extract_timeline(scene_blocks: Option<&Value>, sorted_keys: &[i32]) -> Option<TimelineSceneData> {
    let blocks = scene_blocks?;
    let data = plugin_data_map(blocks, "timeline")?;
    let xml = map_get(data, "sceneInfo")?.as_str()?;
    parse_timeline_xml(xml, sorted_keys)
}

// ============================================================================
// Top-level scene export hook (`studio_scene::export`)
// ============================================================================

pub fn export_scene_plugins(
    scene_bytes: &[u8],
    scene: &Scene,
    char_card_bytes: &HashMap<i32, Vec<u8>>,
    out_dir: &Path,
    json: &mut serde_json::Value,
) {
    let blocks = scene_plugins(scene_bytes);
    let sorted_keys = sorted_dic_keys(scene);

    if let Some(ref b) = blocks {
        if let Some(names) = parse_tree_node_naming(b) {
            if let Ok(v) = serde_json::to_value(names) {
                json["object_names"] = v;
            }
        }
        if let Some(fovs) = parse_save_camera_fov(b) {
            if let Ok(v) = serde_json::to_value(fovs) {
                json["camera_fovs"] = v;
            }
        }
        if let Some(mc) = parse_moar_camz(b) {
            if let Ok(v) = serde_json::to_value(mc) {
                json["moar_camz"] = v;
            }
        }
        if let Some(settings) = parse_studio_scene_settings(b) {
            if let Ok(v) = serde_json::to_value(settings) {
                json["scene_settings"] = v;
            }
        }
        let (embed_bg, embed_frame) = export_studio_image_embed(b, out_dir);
        if embed_bg.is_some() || embed_frame.is_some() {
            if !json["effects"].is_object() {
                json["effects"] = serde_json::json!({});
            }
            if let Some(bg) = embed_bg {
                json["effects"]["background"] = serde_json::Value::String(bg);
            }
            if let Some(fr) = embed_frame {
                json["effects"]["frame"] = serde_json::Value::String(fr);
            }
        }
    }

    if let Some(kkpe) = extract_kkpe(blocks.as_ref(), char_card_bytes) {
        if let Ok(v) = serde_json::to_value(kkpe) {
            json["kkpe"] = v;
        }
    }

    let constraints = extract_nodes_constraints(blocks.as_ref(), &sorted_keys);
    if !constraints.is_empty() {
        if let Ok(v) = serde_json::to_value(constraints) {
            json["constraints"] = v;
        }
    }

    if let Some(timeline) = extract_timeline(blocks.as_ref(), &sorted_keys) {
        if let Ok(v) = serde_json::to_value(timeline) {
            json["timeline"] = v;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ik_effector_mapping_matches_okstudio_finalik_indices() {
        assert_eq!(studio_ik_effector_from_path("BodyTop/work/cf_t_hips"), Some(0));
        assert_eq!(studio_ik_effector_from_path("cf_t_shoulder_L"), Some(1));
        assert_eq!(studio_ik_effector_from_path("cf_t_elbo_L"), Some(9));
        assert_eq!(studio_ik_effector_from_path("cf_t_hand_L"), Some(5));
        assert_eq!(studio_ik_effector_from_path("cf_t_shoulder_R"), Some(2));
        assert_eq!(studio_ik_effector_from_path("cf_t_elbo_R"), Some(10));
        assert_eq!(studio_ik_effector_from_path("cf_t_hand_R"), Some(6));
        assert_eq!(studio_ik_effector_from_path("cf_t_waist_L"), Some(3));
        assert_eq!(studio_ik_effector_from_path("cf_t_knee_L"), Some(11));
        assert_eq!(studio_ik_effector_from_path("cf_t_leg_L"), Some(7));
        assert_eq!(studio_ik_effector_from_path("cf_t_waist_R"), Some(4));
        assert_eq!(studio_ik_effector_from_path("cf_t_knee_R"), Some(12));
        assert_eq!(studio_ik_effector_from_path("cf_t_leg_R"), Some(8));
        assert_eq!(studio_ik_effector_from_path("BodyTop/p_cf_body_bone/cf_j_arm01_L"), None);
    }

    #[test]
    fn kkpe_parses_character_and_item_enabled_policies_and_bones_morphs() {
        let char_xml = r#"<characterInfo version="2.12.0.24" name="Heroine">
            <advancedObjects>
                <object name="BodyTop/p_cf_body_bone/cf_j_root/cf_j_arm01_L" posX="0.01" posY="-0.02" posZ="0.03" rotW="1" rotX="0" rotY="0" rotZ="0" scaleX="1.1" scaleY="1.0" scaleZ="0.9"/>
            </advancedObjects>
            <skinnedMeshes eyesPtn="3" eyesOpen="0.75" mouthPtn="5" mouthOpen="0.4">
                <skinnedMesh name="BodyTop/p_cf_head_bone/cf_O_face">
                    <blendShape index="12" weight="65.5"/>
                </skinnedMesh>
            </skinnedMeshes>
        </characterInfo>"#;
        let parsed = parse_kkpe_character_xml(char_xml, 42).expect("characterInfo enabled by default");
        assert_eq!(parsed.dic_key, 42);
        assert_eq!(parsed.eyes_ptn, Some(3));
        assert!((parsed.eyes_open.unwrap() - 0.75).abs() < 1e-5);
        assert_eq!(parsed.bones.len(), 1);
        assert_eq!(parsed.bones[0].bone, "cf_j_arm01_L");
        assert_eq!(parsed.bones[0].pos, Some([0.01, -0.02, 0.03]));
        assert_eq!(parsed.bones[0].scale, Some([1.1, 1.0, 0.9]));
        assert_eq!(parsed.morphs.len(), 1);
        assert_eq!(parsed.morphs[0].index, 12);
        assert!((parsed.morphs[0].weight - 65.5).abs() < 1e-4);

        let disabled_char = r#"<characterInfo version="2.12.0" enabled="False"><advancedObjects><object name="a" scaleX="2" scaleY="2" scaleZ="2"/></advancedObjects></characterInfo>"#;
        assert!(parse_kkpe_character_xml(disabled_char, 42).is_none());

        let scene_xml = r#"<root version="2.12.0.24">
            <itemInfo name="DisabledProp" index="100">
                <advancedObjects><object name="root/boneA" scaleX="2" scaleY="2" scaleZ="2"/></advancedObjects>
            </itemInfo>
            <itemInfo name="EnabledProp" index="205" enabled="True">
                <advancedObjects><object name="root/boneB" posX="0.5" posY="0" posZ="-0.25"/></advancedObjects>
            </itemInfo>
        </root>"#;
        let items = parse_kkpe_scene_items_xml(scene_xml);
        assert_eq!(items.len(), 1, "item without enabled=True must be ignored per MainWindow.cs");
        assert_eq!(items[0].dic_key, 205);
        assert_eq!(items[0].bones[0].bone, "boneB");
    }

    #[test]
    fn nodes_constraints_resolves_sorted_dic_keys_and_camera_parent() {
        let sorted = vec![10, 25, 99];
        let xml = r#"<constraints version="1.6.3">
            <constraint enabled="true" parentObjectIndex="-2" parentPath="" childObjectIndex="1" childPath="" uniqueLoadId="0"
                position="true" mirrorPosition="false" positionOffsetX="0" positionOffsetY="0.1" positionOffsetZ="1.5"
                rotation="true" mirrorRotation="false" lookAt="true" rotationOffsetW="1" rotationOffsetX="0" rotationOffsetY="0" rotationOffsetZ="0"
                scale="false"/>
            <constraint enabled="true" parentObjectIndex="2" parentPath="Sword/Grip" childObjectIndex="0" childPath="BodyTop/work/cf_t_hand_R" uniqueLoadId="4"
                position="true" positionOffsetX="0" positionOffsetY="0" positionOffsetZ="0"
                rotation="true" rotationOffsetW="1" rotationOffsetX="0" rotationOffsetY="0" rotationOffsetZ="0"/>
        </constraints>"#;
        let list = parse_nodes_constraints_xml(xml, &sorted);
        assert_eq!(list.len(), 2);
        assert_eq!(list[0].parent_key, -2);
        assert_eq!(list[0].child_key, 25);
        assert!(list[0].look_at);
        assert_eq!(list[1].parent_key, 99);
        assert_eq!(list[1].parent_bone, "Grip");
        assert_eq!(list[1].child_key, 10);
        assert_eq!(list[1].child_ik_effector, 6);
        assert!(list[1].child_bone.is_empty());
        assert_eq!(list[1].load_id, 4);
    }

    #[test]
    fn timeline_parses_nested_groups_camera_kkpe_and_constraint_tracks() {
        let sorted = vec![12, 40];
        let xml = r#"<root duration="8.5" blockLength="10" divisions="10">
            <interpolableGroup name="CamGroup">
                <interpolable enabled="true" owner="Timeline" id="cameraPos">
                    <keyframe time="0" valueX="0" valueY="1.2" valueZ="-2.5">
                        <curveKeyframe time="0" value="0" inTangent="0" outTangent="0"/>
                        <curveKeyframe time="1" value="1" inTangent="0" outTangent="0"/>
                    </keyframe>
                    <keyframe time="8.5" valueX="1.0" valueY="1.4" valueZ="-2.0"/>
                </interpolable>
            </interpolableGroup>
            <interpolable enabled="true" owner="KKPE" id="boneRot" objectIndex="0" parameter="BodyTop/p_cf_body_bone/cf_j_head">
                <keyframe time="0" valueX="0" valueY="0" valueZ="0" valueW="1"/>
                <keyframe time="4" valueX="0" valueY="0.258819" valueZ="0" valueW="0.9659258"/>
            </interpolable>
            <interpolable enabled="true" owner="NodesConstraints" id="constraintEnabled" parameter="4">
                <keyframe time="0" value="true"/>
                <keyframe time="5" value="false"/>
            </interpolable>
        </root>"#;
        let tl = parse_timeline_xml(xml, &sorted).expect("timeline parsed");
        assert!((tl.duration - 8.5).abs() < 1e-5);
        assert_eq!(tl.tracks.len(), 3);
        assert_eq!(tl.tracks[0].id, "cameraPos");
        assert_eq!(tl.tracks[0].dic_key, -1);
        assert_eq!(tl.tracks[0].keyframes[0].curve.len(), 2, "ease-in-out curve preserved");
        assert_eq!(tl.tracks[1].owner, "KKPE");
        assert_eq!(tl.tracks[1].dic_key, 12);
        assert_eq!(tl.tracks[1].target_bone, "cf_j_head");
        assert_eq!(tl.tracks[2].owner, "NodesConstraints");
        assert_eq!(tl.tracks[2].param_int, 4);
        assert_eq!(tl.tracks[2].keyframes[1].values, vec![0.0]);
    }
}
