//! Universal compatibility corpus auditor (`ok-extract <game_root> --compat-audit <path>... [--json <out.json>]`).
//! Scans character cards and CharaStudio scenes in parallel, filtering out empty/default plugin stubs so
//! active `KKEx` plugin IDs, `Timeline` interpolables, `NodesConstraints`, and `MaterialEditor` shader families
//! are ranked by true empirical usage.

use rayon::prelude::*;
use rmpv::Value;
use serde::Serialize;
use std::collections::BTreeMap;
use std::io::Cursor;
use std::path::{Path, PathBuf};

#[derive(Default, Clone, Serialize)]
pub struct HitStat {
    pub status: &'static str,
    pub total_files: usize,
    pub active_files: usize,
    pub total_entries: usize,
    pub sample: String,
}

#[derive(Default, Serialize)]
pub struct AuditReport {
    pub scanned_pngs: usize,
    pub character_cards: usize,
    pub studio_scenes: usize,
    pub other_pngs: usize,
    pub card_plugins: BTreeMap<String, HitStat>,
    pub scene_plugins: BTreeMap<String, HitStat>,
    pub timeline_interpolables: BTreeMap<String, HitStat>,
    pub material_editor_shaders: BTreeMap<String, HitStat>,
    pub parsed_verification: BTreeMap<String, usize>,
}

#[derive(Default)]
struct LocalAcc {
    scanned_pngs: usize,
    character_cards: usize,
    studio_scenes: usize,
    other_pngs: usize,
    card_plugins: BTreeMap<String, HitStat>,
    scene_plugins: BTreeMap<String, HitStat>,
    timeline_interpolables: BTreeMap<String, HitStat>,
    material_editor_shaders: BTreeMap<String, HitStat>,
    parsed_verification: BTreeMap<String, usize>,
}

impl LocalAcc {
    fn record(
        map: &mut BTreeMap<String, HitStat>,
        key: String,
        status: &'static str,
        active: bool,
        entries: usize,
        sample: &Path,
    ) {
        let stat = map.entry(key).or_insert_with(|| HitStat {
            status,
            ..Default::default()
        });
        stat.status = status;
        stat.total_files += 1;
        if active {
            stat.active_files += 1;
            stat.total_entries += entries.max(1);
            if stat.sample.is_empty() {
                stat.sample = sample.display().to_string();
            }
        }
    }

    fn merge(mut self, other: Self) -> Self {
        self.scanned_pngs += other.scanned_pngs;
        self.character_cards += other.character_cards;
        self.studio_scenes += other.studio_scenes;
        self.other_pngs += other.other_pngs;
        fn merge_map(into: &mut BTreeMap<String, HitStat>, from: BTreeMap<String, HitStat>) {
            for (k, v) in from {
                let e = into.entry(k).or_insert_with(|| HitStat {
                    status: v.status,
                    ..Default::default()
                });
                e.total_files += v.total_files;
                e.active_files += v.active_files;
                e.total_entries += v.total_entries;
                if e.sample.is_empty() && !v.sample.is_empty() {
                    e.sample = v.sample;
                }
            }
        }
        merge_map(&mut self.card_plugins, other.card_plugins);
        merge_map(&mut self.scene_plugins, other.scene_plugins);
        merge_map(&mut self.timeline_interpolables, other.timeline_interpolables);
        merge_map(&mut self.material_editor_shaders, other.material_editor_shaders);
        for (k, v) in other.parsed_verification {
            *self.parsed_verification.entry(k).or_default() += v;
        }
        self
    }
}

fn png_end(bytes: &[u8]) -> Option<usize> {
    const SIG: &[u8; 8] = b"\x89PNG\r\n\x1a\n";
    if bytes.len() < 8 || &bytes[..8] != SIG {
        return None;
    }
    let mut p = 8usize;
    while p + 12 <= bytes.len() {
        let len = u32::from_be_bytes([bytes[p], bytes[p + 1], bytes[p + 2], bytes[p + 3]]) as usize;
        let end = p.checked_add(12)?.checked_add(len)?;
        if end > bytes.len() {
            return None;
        }
        if &bytes[p + 4..p + 8] == b"IEND" {
            return Some(end);
        }
        p = end;
    }
    None
}

fn looks_like_studio_scene(bytes: &[u8], iend: usize) -> bool {
    let Some(&len) = bytes.get(iend) else { return false };
    let len = len as usize;
    if !(3..=16).contains(&len) || iend + 1 + len > bytes.len() {
        return false;
    }
    bytes[iend + 1..iend + 1 + len]
        .iter()
        .all(|&c| c.is_ascii_digit() || c == b'.')
}

pub fn classify_shader_supported(shader: &str) -> &'static str {
    let family = crate::shader_family(shader);
    let s = family.as_str();
    if crate::is_native_hair_shader(s)
        || s.contains("main_item_studio")
        || s.starts_with("koikano/")
        || s.starts_with("unlit/")
        || s.starts_with("cm3d2/")
        || s.contains("particles/additive")
        || matches!(
            s,
            "shader forge/main_skin"
                | "shader forge/main_opaque"
                | "shader forge/main_alpha"
                | "shader forge/main_item"
                | "shader forge/main_item_emission"
                | "shader forge/main_item_ditherd"
                | "shader forge/main_standardmdk_studio"
                | "shader forge/toon_eye_lod0"
                | "shader forge/toon_eyew_lod0"
                | "shader forge/toon_glasses_lod0"
                | "shader forge/toon_nose_lod0"
                | "standard"
                | "kkuss"
                | "kkussitem"
                | "kkussalpha"
                | "kkusshair"
                | "kkuts"
                | "kkuts_tess"
                | "kkutsitem"
                | "kkutsitem_tess"
                | "kkutsalpha"
                | "kkutsalpha_tess"
                | "kkutshair"
                | "kkutshair_tess"
                | "kkutseye"
                | "kkutseyew"
                | "ibl_shader"
                | "ibl_shader_alpha"
                | "goo"
                | "bettermatcap"
                | "da/chara/oil painting"
                | "harvexarc-xray"
                | "harvexarc/xray"
        )
    {
        "supported"
    } else {
        "unsupported"
    }
}

fn classify_card_plugin(id: &str) -> &'static str {
    let low = id.to_ascii_lowercase();
    if low == "com.bepis.sideloader.universalautoresolver"
        || low == "ec.core.sideloader.universalautoresolver"
        || low == "com.deathweasel.bepinex.pushup"
        || low.contains("uncensorselector")
        || low.contains("abmdata")
        || low == "ksox"
        || low == "kcox"
        || low == "kk_pregnancyplus"
        || low == "kk_invisiblebody"
        || low == "com.deathweasel.bepinex.dynamicboneeditor"
        || low == "com.deathweasel.bepinex.colliders"
        || low.contains("materialeditor")
        || low.contains("hairaccessorycustomizer")
        || low.contains("moreaccessories")
        || low == "com.deathweasel.bepinex.eyecontrol"
        || low == "madevil.kk.ass"
        || low == "accessory_states"
        || low == "nakay.kk.clothingblendshape"
        || low == "org.njaecha.plugins.editfangs"
        || low == "kkpe"
        || low == "com.openkoikatsu.provenance"
    {
        "supported"
    } else if low.contains("additionalcardinfo")
        || low.contains("additional_card_info")
        || low.contains("authordata")
        || low == "migrationhelper"
        || low == "pluginlisttool"
        || low == "aaaaaaaaaaaa_data"
        || low.contains("gamedialoghelper")
        || low.contains("autosave")
        || low.contains("charamaker")
        || low.contains("clothingunlocker")
        || low.contains("maker")
        || low.contains("sliders")
        || low.contains("title")
        || low.contains("browser")
        || low.contains("profile")
        || low == "marco.kkapi"
    {
        "ui_or_meta"
    } else {
        "unsupported"
    }
}

fn classify_scene_plugin(id: &str) -> &'static str {
    match id {
        "com.bepis.sideloader.universalautoresolver"
        | "EC.Core.Sideloader.UniversalAutoResolver"
        | "com.deathweasel.bepinex.materialeditor"
        | "KKVMDPlayExtSave"
        | "mmddirectorData"
        | "com.jim60105.kk.studiocharalightlinkedtocamera"
        | "com.jim60105.kks.studiocharalightlinkedtocamera"
        | "timeline"
        | "nodesConstraints"
        | "KK_AnimationController"
        | "kkpe"
        | "org.njaecha.plugins.treenodenaming"
        | "com.rikkibalboa.bepinex.savecameraobjectfov"
        | "orange.spork.moarcamzplugin"
        | "com.deathweasel.bepinex.studioscenesettings"
        | "com.deathweasel.bepinex.studioimageembed"
        | "ShadowSettings"
        | "com.shallty.shadowsettings"
        | "LightSettingsData"
        | "com.rikkibalboa.bepinex.lightsettings"
        | "lightSwitch"
        | "rendererEditor"
        | "vnge_kfa"
        | "vnge_kfa2"
        | "vnge_sss"
        | "vnge_sssadv"
        | "vnge_sssb"
        | "vnge_actor"
        | "vnge_physics"
        | "vnge_sound"
        | "vnge_sound_extdata"
        | "vnge_vnss" => "supported",
        "vnge_rig" => "partial",
        "CharaStudioTweak" | "com.shallty.shalltyutils" | "RSkoi_ComponentUtil" => "ui_or_meta",
        _ => "unsupported",
    }
}

fn classify_timeline_interpolable(owner: &str, id: &str) -> &'static str {
    let norm_owner = if owner == "HSPE" { "KKPE" } else { owner };
    match (norm_owner, id) {
        (
            "Timeline",
            "cameraOPos"
            | "cameraORot"
            | "cameraOZoom"
            | "cameraFOV"
            | "cameraPos"
            | "cameraRot"
            | "cameraData"
            | "timeScale"
            | "objectEnabled"
            | "guideObjectPos"
            | "guideObjectRot"
            | "guideObjectScale"
            | "objectAnimationSpeed"
            | "charAnimation"
            | "charAnimationPattern"
            | "itemAnimationTime"
            | "charAnimationTime"
            | "charClothes"
            | "juice"
            | "tears"
            | "blush"
            | "femaleNipples"
            | "characterNeck"
            | "characterEyes"
            | "characterEyesOpen"
            | "characterEyebrows"
            | "characterEyebrowsOpen"
            | "characterMouth"
            | "characterMouthOpen"
            | "characterLeftHand"
            | "characterRightHand"
            | "itemColor1"
            | "itemColor2"
            | "itemColor3"
            | "itemColor4"
            | "itemPatternColor1"
            | "itemPatternColor2"
            | "itemPatternColor3"
            | "itemPatternUV1"
            | "itemPatternUV2"
            | "itemPatternUV3"
            | "itemPatternRotation1"
            | "itemPatternRotation2"
            | "itemPatternRotation3"
            | "itemPatternClamp1"
            | "itemPatternClamp2"
            | "itemPatternClamp3"
            | "itemShadowColor"
            | "itemAlpha"
            | "itemEmissionColor"
            | "itemEmissionPower"
            | "itemLightCancel"
            | "itemLineColor"
            | "itemLineWidth"
            | "itemPanelColor"
            | "itemPanelPatternUV"
            | "itemPanelPatternRotation"
            | "itemPanelPatternClamp"
            | "lightColor"
            | "lightOnOff"
            | "lightShadows"
            | "lightStrength"
            | "lightRange"
            | "lightSpotAngle",
        )
        | (
            "KKPE",
            "bonePos"
            | "boneRot"
            | "boneScale"
            | "lastBlendShape"
            | "groupBlendShape"
            | "groupBlendShapeLink"
            | "leftBoobEnabled"
            | "rightBoobEnabled"
            | "leftButtEnabled"
            | "rightButtEnabled"
            | "leftBoobGravity"
            | "rightBoobGravity"
            | "leftButtGravity"
            | "rightButtGravity"
            | "leftBoobForce"
            | "rightBoobForce"
            | "leftButtForce"
            | "rightButtForce"
            | "dynamicBoneEnabled"
            | "dynamicBoneForce"
            | "dynamicBoneGravity"
            | "dynamicBoneWeight"
            | "dynamicBoneDamping"
            | "dynamicBoneElasticity"
            | "dynamicBoneStiffness"
            | "dynamicBoneInertia"
            | "dynamicBoneRadius"
            | "dynamicBoneFreezeAxis"
            | "colliderRadius"
            | "colliderHeight"
            | "colliderBaseCenter"
            | "colliderBaseDirection"
            | "colliderBaseBound"
            | "ikPositionWeight",
        )
        | (
            "ShalltyUtils",
            "guideObjectXPos"
            | "guideObjectYPos"
            | "guideObjectZPos"
            | "guideObjectXRot"
            | "guideObjectYRot"
            | "guideObjectZRot"
            | "guideObjectXScale"
            | "guideObjectYScale"
            | "guideObjectZScale"
            | "boneXPos"
            | "boneYPos"
            | "boneZPos"
            | "boneXRot"
            | "boneYRot"
            | "boneZRot"
            | "boneXScale"
            | "boneYScale"
            | "boneZScale",
        )
        | ("NodesConstraints", "constraintEnabled" | "constraintPos" | "constraintRos")
        | ("MaterialEditor", "floatProperty" | "colorProperty" | "textureOffsetProperty" | "textureScaleProperty")
        | ("PregnancyPlus", "0" | "inflation")
        | ("Eye Shaking", "shakingEnabled")
        | ("RendererEditor", "targetEnabled") => "supported",
        ("KKPE", x)
            if x.starts_with("fbbikEffectorPositionWeight")
                || x.starts_with("fbbikEffectorRotationWeight")
                || x.starts_with("fbbikConstraintBendWeight") =>
        {
            "supported"
        }
        ("RendererEditor", x)
            if x.starts_with("Float_")
                || x.starts_with("Color_")
                || x.starts_with("Vector4_")
                || (x.starts_with("Texture_") && (x.ends_with("Offset") || x.ends_with("Scale"))) =>
        {
            "supported"
        }
        _ => "unsupported",
    }
}

fn plugin_inner(plugin: &Value) -> Option<&Value> {
    let data = if let Some(arr) = plugin.as_array() {
        arr.get(1)?
    } else {
        crate::card::map_get(plugin, "1").unwrap_or(plugin)
    };
    if data.is_nil() {
        return None;
    }
    Some(crate::card::map_get(data, "data").unwrap_or(data))
}

fn value_has_payload(v: &Value) -> bool {
    match v {
        Value::Nil => false,
        Value::Boolean(b) => *b,
        Value::String(s) => s.as_str().is_some_and(|t| {
            let t = t.trim();
            !t.is_empty() && t != "[]" && t != "{}" && !t.ends_with("/>")
        }),
        Value::Binary(b) => {
            if b.is_empty() || b == &[0x80] || b == &[0x90] {
                return false;
            }
            if let Ok(decoded) = rmpv::decode::read_value(&mut Cursor::new(b)) {
                return value_has_payload(&decoded);
            }
            true
        }
        Value::Array(a) => a.iter().any(value_has_payload),
        Value::Map(m) => m.iter().any(|(_, val)| value_has_payload(val)),
        _ => true,
    }
}

fn collect_me_shaders(inner: &Value, path: &Path, acc: &mut LocalAcc) {
    let Some(bin) = crate::card::map_get(inner, "MaterialShaderList").and_then(Value::as_slice) else {
        return;
    };
    let Ok(list) = rmpv::decode::read_value(&mut Cursor::new(bin)) else {
        return;
    };
    let Some(arr) = list.as_array() else { return };
    let mut per_file: BTreeMap<String, usize> = BTreeMap::new();
    for item in arr {
        let Some(shader) = crate::card::map_get(item, "ShaderName")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
        else {
            continue;
        };
        *per_file.entry(shader.to_string()).or_default() += 1;
    }
    for (shader, count) in per_file {
        let status = classify_shader_supported(&shader);
        LocalAcc::record(&mut acc.material_editor_shaders, shader, status, true, count, path);
    }
}

fn audit_card(bytes: &[u8], path: &Path, acc: &mut LocalAcc) -> bool {
    let Ok(blocks) = crate::appearance::blocks_from_card(bytes) else {
        return false;
    };
    acc.character_cards += 1;
    if let Ok(info) = crate::card::parse_card_bytes(bytes, 0) {
        *acc.parsed_verification.entry("cards_parsed_ok".into()).or_default() += 1;
        if info.edit_fangs.is_some() {
            *acc.parsed_verification.entry("cards_edit_fangs_parsed".into()).or_default() += 1;
        }
        if !info.clothes_blend_shapes.is_empty() {
            *acc.parsed_verification.entry("cards_clothing_blend_shapes_parsed".into()).or_default() += 1;
        }
        if !info.acc_state_sync.is_empty() {
            *acc.parsed_verification.entry("cards_acc_state_sync_parsed".into()).or_default() += 1;
        }
    }
    let Some(kkex_bytes) = blocks.get("KKEx") else {
        return true;
    };
    let Ok(kkex) = rmpv::decode::read_value(&mut Cursor::new(kkex_bytes)) else {
        return true;
    };
    let Some(map) = kkex.as_map() else {
        return true;
    };
    for (k, v) in map {
        let Some(id) = k.as_str() else { continue };
        let status = classify_card_plugin(id);
        let inner = plugin_inner(v);
        let active = inner.is_some_and(value_has_payload);
        if let Some(inner) = inner {
            if id.to_ascii_lowercase().contains("materialeditor") {
                collect_me_shaders(inner, path, acc);
            }
        }
        LocalAcc::record(&mut acc.card_plugins, id.to_string(), status, active, 1, path);
    }
    true
}

fn xml_text_of<'a>(inner: &'a Value, key: &str) -> Option<std::borrow::Cow<'a, str>> {
    let v = crate::card::map_get(inner, key)?;
    if let Some(s) = v.as_str() {
        Some(std::borrow::Cow::Borrowed(s))
    } else if let Some(b) = v.as_slice() {
        let b = b.strip_prefix(&[0xEF, 0xBB, 0xBF]).unwrap_or(b);
        Some(String::from_utf8_lossy(b))
    } else {
        None
    }
}

fn audit_scene(bytes: &[u8], path: &Path, acc: &mut LocalAcc) {
    acc.studio_scenes += 1;
    let Some(blocks) = crate::studio_scene::scene_plugins(bytes) else {
        return;
    };
    let dummy_keys: Vec<i32> = (0..16384).collect();
    if let Some(tl) = crate::studio_scene_plugins::extract_timeline(Some(&blocks), &dummy_keys) {
        *acc.parsed_verification.entry("scenes_timeline_parsed".into()).or_default() += 1;
        *acc.parsed_verification.entry("scenes_timeline_tracks_parsed".into()).or_default() += tl.tracks.len();
    }
    let cons = crate::studio_scene_plugins::extract_nodes_constraints(Some(&blocks), &dummy_keys);
    if !cons.is_empty() {
        *acc.parsed_verification.entry("scenes_constraints_parsed".into()).or_default() += 1;
        *acc.parsed_verification.entry("scenes_constraint_items_parsed".into()).or_default() += cons.len();
    }
    if crate::studio_scene_plugins::parse_tree_node_naming(&blocks).is_some() {
        *acc.parsed_verification.entry("scenes_treenodenaming_parsed".into()).or_default() += 1;
    }
    if crate::studio_scene_plugins::parse_save_camera_fov(&blocks).is_some() {
        *acc.parsed_verification.entry("scenes_savecameraobjectfov_parsed".into()).or_default() += 1;
    }
    if crate::studio_scene_plugins::parse_moar_camz(&blocks).is_some() {
        *acc.parsed_verification.entry("scenes_moarcamz_parsed".into()).or_default() += 1;
    }
    if crate::studio_scene_plugins::parse_studio_scene_settings(&blocks).is_some() {
        *acc.parsed_verification.entry("scenes_studioscenesettings_parsed".into()).or_default() += 1;
    }
    let Some(map) = blocks.as_map() else { return };
    for (k, v) in map {
        let Some(id) = k.as_str() else { continue };
        let status = classify_scene_plugin(id);
        let Some(inner) = plugin_inner(v) else {
            LocalAcc::record(&mut acc.scene_plugins, id.to_string(), status, false, 0, path);
            continue;
        };
        let (active, entries) = match id {
            "timeline" => {
                if let Some(xml) = xml_text_of(inner, "sceneInfo") {
                    if xml.contains("<interpolable") {
                        let mut count = 0usize;
                        let mut per_interp: BTreeMap<String, (usize, &'static str)> = BTreeMap::new();
                        if let Ok(doc) = roxmltree::Document::parse(&xml) {
                            for node in doc.descendants().filter(|n| n.has_tag_name("interpolable")) {
                                let enabled = node.attribute("enabled").map(|e| e != "false").unwrap_or(true);
                                let kfs = node.children().filter(|c| c.has_tag_name("keyframe")).count();
                                if !enabled || kfs == 0 {
                                    continue;
                                }
                                count += 1;
                                let owner = node.attribute("owner").unwrap_or("?");
                                let iid = node.attribute("id").unwrap_or("?");
                                let key = format!("{owner}::{iid}");
                                let st = classify_timeline_interpolable(owner, iid);
                                let entry = per_interp.entry(key).or_insert((0, st));
                                entry.0 += 1;
                            }
                        }
                        for (interp_key, (n, st)) in per_interp {
                            LocalAcc::record(&mut acc.timeline_interpolables, interp_key, st, true, n, path);
                        }
                        (count > 0, count)
                    } else {
                        (false, 0)
                    }
                } else {
                    (false, 0)
                }
            }
            "nodesConstraints" => {
                if let Some(xml) = xml_text_of(inner, "constraints") {
                    if xml.contains("<constraint") {
                        let n = roxmltree::Document::parse(&xml)
                            .ok()
                            .map(|d| d.descendants().filter(|c| c.has_tag_name("constraint")).count())
                            .unwrap_or(1);
                        (n > 0, n)
                    } else {
                        (false, 0)
                    }
                } else {
                    (false, 0)
                }
            }
            "rendererEditor" => {
                let n = xml_text_of(inner, "xml")
                    .and_then(|xml| {
                        roxmltree::Document::parse(&xml)
                            .ok()
                            .map(|d| d.root_element().children().filter(|c| c.is_element()).count())
                    })
                    .unwrap_or(0);
                (n > 0, n)
            }
            "kkpe" => {
                let active = xml_text_of(inner, "sceneInfo")
                    .and_then(|xml| {
                        let doc = roxmltree::Document::parse(&xml).ok()?;
                        let mut edits = 0usize;
                        for n in doc.descendants().filter(|n| n.is_element()) {
                            let tag = n.tag_name().name();
                            if tag == "charaInfo"
                                || tag == "bone"
                                || tag == "blendShape"
                                || tag == "collider"
                                || tag == "dynamicBone"
                            {
                                edits += 1;
                            } else if tag == "itemInfo" && n.children().any(|c| c.is_element() && c.children().any(|gc| gc.is_element())) {
                                edits += 1;
                            }
                        }
                        Some(edits)
                    })
                    .unwrap_or(0);
                (active > 0, active)
            }
            "com.jim60105.kk.studiocharalightlinkedtocamera"
            | "com.jim60105.kks.studiocharalightlinkedtocamera" => {
                let locked = crate::card::map_get(inner, "locked")
                    .map(|x| x.as_bool() == Some(true) || x.as_str() == Some("true"))
                    .unwrap_or(false);
                (locked, usize::from(locked))
            }
            "com.deathweasel.bepinex.studioscenesettings" => {
                let masking = crate::card::map_get(inner, "MapMasking").and_then(Value::as_bool) == Some(true);
                let near = crate::card::map_get(inner, "NearClipPlane").is_some_and(|x| !x.is_nil());
                let far = crate::card::map_get(inner, "FarClipPlane").is_some_and(|x| !x.is_nil());
                let active = masking || near || far;
                (active, usize::from(active))
            }
            "com.rikkibalboa.bepinex.savecameraobjectfov" => {
                let cams = crate::card::map_get(inner, "cameras").is_some_and(value_has_payload);
                let fov_changed = crate::card::map_get(inner, "mainFov")
                    .and_then(Value::as_f64)
                    .is_some_and(|f| (f - 23.0).abs() > 1e-3);
                let active = cams || fov_changed;
                (active, usize::from(active))
            }
            "orange.spork.moarcamzplugin" => {
                let active = crate::card::map_get(inner, "MoarCamz")
                    .and_then(Value::as_slice)
                    .and_then(|b| rmpv::decode::read_value(&mut Cursor::new(b)).ok())
                    .and_then(|v| {
                        let arr = v.as_array()?;
                        let non_zero = arr
                            .iter()
                            .filter(|slot| {
                                let pos = crate::card::map_get(slot, "Position")
                                    .and_then(Value::as_array)
                                    .is_some_and(|a| a.iter().any(|x| x.as_f64().unwrap_or(0.0).abs() > 1e-4));
                                let rot = crate::card::map_get(slot, "Rotation")
                                    .and_then(Value::as_array)
                                    .is_some_and(|a| a.iter().any(|x| x.as_f64().unwrap_or(0.0).abs() > 1e-4));
                                pos || rot
                            })
                            .count();
                        Some(non_zero)
                    })
                    .unwrap_or(0);
                (active > 0, active)
            }
            "com.deathweasel.bepinex.materialeditor" => {
                collect_me_shaders(inner, path, acc);
                let active = value_has_payload(inner);
                (active, usize::from(active))
            }
            _ => {
                let active = value_has_payload(inner);
                (active, usize::from(active))
            }
        };
        LocalAcc::record(&mut acc.scene_plugins, id.to_string(), status, active, entries, path);
    }
}

fn walk_pngs(p: &Path, out: &mut Vec<PathBuf>) {
    if p.is_file() {
        if p.extension().is_some_and(|e| e.eq_ignore_ascii_case("png")) {
            out.push(p.to_path_buf());
        }
        return;
    }
    let Ok(rd) = std::fs::read_dir(p) else { return };
    let mut entries: Vec<PathBuf> = rd.flatten().map(|e| e.path()).collect();
    entries.sort();
    for child in entries {
        if child.is_dir() {
            walk_pngs(&child, out);
        } else if child.extension().is_some_and(|e| e.eq_ignore_ascii_case("png")) {
            out.push(child);
        }
    }
}

pub fn run_audit(inputs: &[PathBuf]) -> AuditReport {
    let mut pngs = Vec::new();
    for p in inputs {
        walk_pngs(p, &mut pngs);
    }
    let merged = pngs
        .par_iter()
        .fold(LocalAcc::default, |mut acc, path| {
            acc.scanned_pngs += 1;
            let Ok(bytes) = std::fs::read(path) else {
                acc.other_pngs += 1;
                return acc;
            };
            let Some(iend) = png_end(&bytes) else {
                acc.other_pngs += 1;
                return acc;
            };
            if looks_like_studio_scene(&bytes, iend) {
                audit_scene(&bytes, path, &mut acc);
            } else if !audit_card(&bytes, path, &mut acc) {
                acc.other_pngs += 1;
            }
            acc
        })
        .reduce(LocalAcc::default, LocalAcc::merge);

    AuditReport {
        scanned_pngs: merged.scanned_pngs,
        character_cards: merged.character_cards,
        studio_scenes: merged.studio_scenes,
        other_pngs: merged.other_pngs,
        card_plugins: merged.card_plugins,
        scene_plugins: merged.scene_plugins,
        timeline_interpolables: merged.timeline_interpolables,
        material_editor_shaders: merged.material_editor_shaders,
        parsed_verification: merged.parsed_verification,
    }
}

fn print_ranked(title: &str, map: &BTreeMap<String, HitStat>, only_gaps: bool) {
    let mut rows: Vec<(&String, &HitStat)> = map
        .iter()
        .filter(|(_, s)| s.active_files > 0 && (!only_gaps || s.status != "supported"))
        .collect();
    rows.sort_by(|a, b| b.1.active_files.cmp(&a.1.active_files).then_with(|| a.0.cmp(b.0)));
    println!("\n=== {title} ({}) ===", rows.len());
    for (name, stat) in rows.into_iter().take(40) {
        println!(
            "  [{:<11}] active={:<5} total={:<5} entries={:<6} {}",
            stat.status, stat.active_files, stat.total_files, stat.total_entries, name
        );
    }
}

pub fn cli(args: &[String]) -> Result<(), String> {
    let mut inputs = Vec::new();
    let mut json_out: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--json" {
            i += 1;
            json_out = Some(PathBuf::from(args.get(i).ok_or("--json requires output path")?));
        } else {
            inputs.push(PathBuf::from(&args[i]));
        }
        i += 1;
    }
    if inputs.is_empty() {
        return Err("usage: ok-extract <game_root> --compat-audit <dir_or_png>... [--json <out.json>]".into());
    }
    let t0 = std::time::Instant::now();
    let report = run_audit(&inputs);
    println!(
        "Scanned {} PNGs in {:.2}s (cards={}, studio_scenes={}, other={})",
        report.scanned_pngs,
        t0.elapsed().as_secs_f64(),
        report.character_cards,
        report.studio_scenes,
        report.other_pngs
    );
    print_ranked("Card KKEx Plugins (Gaps / Non-Supported)", &report.card_plugins, true);
    print_ranked("Studio Scene KKEx Plugins (Gaps / Non-Supported)", &report.scene_plugins, true);
    print_ranked("Active Timeline Interpolables", &report.timeline_interpolables, false);
    print_ranked("Unsupported MaterialEditor Shaders", &report.material_editor_shaders, true);

    if let Some(out) = json_out {
        if let Some(parent) = out.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let bytes = serde_json::to_vec_pretty(&report).map_err(|e| e.to_string())?;
        std::fs::write(&out, bytes).map_err(|e| e.to_string())?;
        println!("\nWrote full JSON report to {}", out.display());
    }
    Ok(())
}
