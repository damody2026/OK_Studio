//! Extended VNGE studio modules (`vnge_sssadv`, `vnge_sssb`, `vnge_actor`, `vnge_physics`,
//! `vnge_sound` + `vnge_sound_extdata`, `-ministates:`, `-vntext:`, and `PoseSaveState` `.png`/`.txt` library).

use std::path::Path;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::card::map_get;
use crate::studio_scene::{png_len, Object, Scene};
use crate::vnge::{data_png_load, parse_py_or_json, VngeRegistry};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct VngeMinistate {
    pub name: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub group: String,
    pub payload: Value,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct VngeTextEntry {
    pub id: String,
    pub dic_key: i32,
    pub text: String,
    pub color: [f32; 4],
    pub outline_color: [f32; 4],
    pub outline_spread: f32,
    pub visible: bool,
    pub in_front: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub font: String,
    pub size: f32,
    pub anchor: i32,
    pub alignment: i32,
    pub position: [f32; 3],
    pub rotation: [f32; 3],
    pub scale: [f32; 3],
    pub is_3d: bool,
    pub bind_cam: bool,
    pub parent_hide: bool,
    pub word_wrap: bool,
    pub word_wrap_len: i32,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct VngeSoundSource {
    pub id: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub group: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub path: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub extracted_path: String,
    pub volume: f32,
    pub pitch: f32,
    pub loop_play: bool,
    pub auto_play: bool,
    pub is_3d: bool,
    pub bind_key: i32,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub bind_actor: String,
    pub min_dist: f32,
    pub max_dist: f32,
    pub raw: Value,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct VngeSoundData {
    pub version: String,
    pub sources: Vec<VngeSoundSource>,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub spectrum: Value,
    #[serde(default, skip_serializing_if = "Value::is_null")]
    pub general: Value,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct VngePhysicsData {
    pub version: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub colliders: Vec<Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub rigid_bodies: Vec<Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub triggers: Vec<Value>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub actions: Vec<Value>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct VngePosePreset {
    pub category: String,
    pub pose: Value,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    pub raw: Value,
}

fn num_f32(v: Option<&Value>, def: f32) -> f32 {
    let Some(x) = v else { return def };
    x.as_f64()
        .map(|f| f as f32)
        .or_else(|| x.as_i64().map(|n| n as f32))
        .or_else(|| x.as_str().and_then(|s| s.trim().parse::<f32>().ok()))
        .filter(|f| f.is_finite())
        .unwrap_or(def)
}

fn num_i32(v: Option<&Value>, def: i32) -> i32 {
    let Some(x) = v else { return def };
    x.as_i64()
        .map(|n| n as i32)
        .or_else(|| x.as_f64().map(|f| f.round() as i32))
        .or_else(|| x.as_str().and_then(|s| s.trim().parse::<i32>().ok()))
        .unwrap_or(def)
}

fn flag_bool(v: Option<&Value>, def: bool) -> bool {
    let Some(x) = v else { return def };
    x.as_bool()
        .or_else(|| x.as_i64().map(|n| n != 0))
        .or_else(|| {
            x.as_str().map(|s| {
                matches!(
                    s.trim().to_ascii_lowercase().as_str(),
                    "true" | "1" | "yes" | "on"
                )
            })
        })
        .unwrap_or(def)
}

fn arr3(v: Option<&Value>, def: [f32; 3]) -> [f32; 3] {
    let Some(x) = v else { return def };
    if let Some(a) = x.as_array() {
        if a.len() >= 3 {
            return [
                num_f32(a.first(), def[0]),
                num_f32(a.get(1), def[1]),
                num_f32(a.get(2), def[2]),
            ];
        }
    }
    if x.is_object() {
        return [
            num_f32(x.get("x"), def[0]),
            num_f32(x.get("y"), def[1]),
            num_f32(x.get("z"), def[2]),
        ];
    }
    def
}

fn arr4(v: Option<&Value>, def: [f32; 4]) -> [f32; 4] {
    let Some(x) = v else { return def };
    if let Some(a) = x.as_array() {
        if a.len() >= 3 {
            return [
                num_f32(a.first(), def[0]),
                num_f32(a.get(1), def[1]),
                num_f32(a.get(2), def[2]),
                num_f32(a.get(3), def[3]),
            ];
        }
    }
    if x.is_object() {
        return [
            num_f32(x.get("r").or_else(|| x.get("x")), def[0]),
            num_f32(x.get("g").or_else(|| x.get("y")), def[1]),
            num_f32(x.get("b").or_else(|| x.get("z")), def[2]),
            num_f32(x.get("a").or_else(|| x.get("w")), def[3]),
        ];
    }
    def
}

fn decode_base64_lenient(input: &str) -> Option<Vec<u8>> {
    fn val(b: u8) -> Option<u8> {
        match b {
            b'A'..=b'Z' => Some(b - b'A'),
            b'a'..=b'z' => Some(b - b'a' + 26),
            b'0'..=b'9' => Some(b - b'0' + 52),
            b'+' | b'-' => Some(62),
            b'/' | b'_' => Some(63),
            _ => None,
        }
    }
    let clean: Vec<u8> = input
        .bytes()
        .filter(|b| !b.is_ascii_whitespace() && *b != b'=')
        .collect();
    if clean.is_empty() {
        return None;
    }
    let mut out = Vec::with_capacity(clean.len() * 3 / 4);
    for chunk in clean.chunks(4) {
        if chunk.len() < 2 {
            break;
        }
        let c0 = val(chunk[0])?;
        let c1 = val(chunk[1])?;
        out.push((c0 << 2) | (c1 >> 4));
        if chunk.len() >= 3 {
            let c2 = val(chunk[2])?;
            out.push((c1 << 4) | (c2 >> 2));
            if chunk.len() >= 4 {
                let c3 = val(chunk[3])?;
                out.push((c2 << 6) | c3);
            }
        }
    }
    Some(out)
}

fn audio_ext(bytes: &[u8], hint: &str) -> &'static str {
    if bytes.starts_with(b"RIFF") {
        "wav"
    } else if bytes.starts_with(b"OggS") {
        "ogg"
    } else if bytes.starts_with(b"fLaC") {
        "flac"
    } else if bytes.starts_with(b"ID3") || (bytes.len() >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
        "mp3"
    } else {
        let low = hint.to_ascii_lowercase();
        if low.ends_with(".ogg") {
            "ogg"
        } else if low.ends_with(".mp3") {
            "mp3"
        } else {
            "wav"
        }
    }
}

pub fn parse_json_plugin(blocks: Option<&rmpv::Value>, plugin_id: &str) -> Option<Value> {
    let (_, main, _) = blocks.and_then(|b| data_png_load(b, plugin_id))?;
    let v = parse_py_or_json(&main).ok()?;
    match &v {
        Value::Null => None,
        Value::Array(a) if a.is_empty() => None,
        Value::Object(m) if m.is_empty() => None,
        Value::Object(m) if m.len() == 1 && m.get("scene").and_then(Value::as_array).is_some_and(Vec::is_empty) => None,
        _ => Some(v),
    }
}

pub fn parse_ministates(scene: &Scene) -> Vec<VngeMinistate> {
    let mut out = Vec::new();
    fn walk(objs: &[Object], out: &mut Vec<VngeMinistate>) {
        for o in objs {
            match o {
                Object::Folder { name, children, .. } => {
                    if name.trim().starts_with("-ministates:") {
                        for item in children {
                            if let Object::Folder {
                                name: mname,
                                children: mchildren,
                                ..
                            } = item
                            {
                                let raw_str = mchildren
                                    .iter()
                                    .find_map(|c| match c {
                                        Object::Folder { name: inner, .. } => Some(inner.as_str()),
                                        _ => None,
                                    })
                                    .unwrap_or("");
                                let payload = if raw_str.is_empty() {
                                    Value::Null
                                } else {
                                    parse_py_or_json(raw_str).unwrap_or_else(|_| Value::String(raw_str.to_string()))
                                };
                                let trimmed = mname.trim();
                                let (group, clean_name) = if let Some((g, rest)) = trimmed.split_once(':') {
                                    (g.trim().to_string(), rest.trim().to_string())
                                } else {
                                    (String::new(), trimmed.to_string())
                                };
                                out.push(VngeMinistate {
                                    name: clean_name,
                                    group,
                                    payload,
                                });
                            }
                        }
                    } else {
                        walk(children, out);
                    }
                }
                Object::Item { children, .. } | Object::Route { children, .. } => walk(children, out),
                Object::Character { children, .. } => {
                    for (_, c) in children {
                        walk(c, out);
                    }
                }
                _ => {}
            }
        }
    }
    walk(&scene.objects, &mut out);
    out
}

pub fn parse_vntexts(scene: &Scene) -> Vec<VngeTextEntry> {
    let mut out = Vec::new();
    fn walk(objs: &[Object], out: &mut Vec<VngeTextEntry>) {
        for o in objs {
            match o {
                Object::Folder {
                    key,
                    change,
                    visible,
                    name,
                    children,
                } => {
                    if let Some(id) = name.trim().strip_prefix("-vntext:") {
                        let data_str = children.iter().find_map(|c| match c {
                            Object::Folder { name: cn, .. } => cn.trim().strip_prefix("-vntextdata:"),
                            _ => None,
                        });
                        if let Some(raw) = data_str {
                            if let Ok(ss) = parse_py_or_json(raw) {
                                let raw_text = ss
                                    .get("text")
                                    .and_then(Value::as_str)
                                    .unwrap_or("")
                                    .replace("\\n", "\n")
                                    .replace("\\'", "'");
                                let bind_cam = flag_bool(ss.get("bindcam"), false);
                                out.push(VngeTextEntry {
                                    id: id.trim().to_string(),
                                    dic_key: *key,
                                    text: raw_text,
                                    color: arr4(ss.get("color"), [1.0, 1.0, 1.0, 1.0]),
                                    outline_color: [0.0, 0.0, 0.0, 0.8],
                                    outline_spread: 1.0,
                                    visible: flag_bool(ss.get("visible"), *visible),
                                    in_front: flag_bool(ss.get("infront"), true),
                                    font: ss.get("font").and_then(Value::as_str).unwrap_or("").to_string(),
                                    size: num_f32(ss.get("size"), 24.0),
                                    anchor: num_i32(ss.get("anchor"), 4),
                                    alignment: num_i32(ss.get("alignment"), 1),
                                    position: arr3(ss.get("position"), change.pos),
                                    rotation: arr3(ss.get("rotation"), change.rot),
                                    scale: arr3(ss.get("scale"), change.scale),
                                    is_3d: !bind_cam,
                                    bind_cam,
                                    parent_hide: flag_bool(ss.get("parentHide"), false),
                                    word_wrap: flag_bool(ss.get("wwEnable"), false),
                                    word_wrap_len: num_i32(ss.get("wwLength"), 0),
                                });
                            }
                        }
                    }
                    walk(children, out);
                }
                Object::Text {
                    key,
                    change,
                    visible,
                    id,
                    color,
                    outline_color,
                    outline_spread,
                    text,
                    text_color,
                    font_size,
                    direction,
                } => {
                    out.push(VngeTextEntry {
                        id: format!("studio_text_{key}"),
                        dic_key: *key,
                        text: text.clone(),
                        color: [text_color.r, text_color.g, text_color.b, text_color.a],
                        outline_color: [outline_color.r, outline_color.g, outline_color.b, outline_color.a],
                        outline_spread: *outline_spread,
                        visible: *visible,
                        in_front: true,
                        font: format!("preset_{id}_dir_{direction}_bg_{:.2}_{:.2}_{:.2}_{:.2}", color.r, color.g, color.b, color.a),
                        size: if *font_size > 0 { *font_size as f32 } else { 32.0 },
                        anchor: 4,
                        alignment: 1,
                        position: change.pos,
                        rotation: change.rot,
                        scale: change.scale,
                        is_3d: false,
                        bind_cam: true,
                        parent_hide: false,
                        word_wrap: true,
                        word_wrap_len: 0,
                    });
                }
                Object::Item { children, .. } | Object::Route { children, .. } => walk(children, out),
                Object::Character { children, .. } => {
                    for (_, c) in children {
                        walk(c, out);
                    }
                }
                _ => {}
            }
        }
    }
    walk(&scene.objects, &mut out);
    out
}

pub fn parse_vnphysics(blocks: Option<&rmpv::Value>) -> Option<VngePhysicsData> {
    let (_, main, _) = blocks.and_then(|b| data_png_load(b, "vnge_physics"))?;
    let v = parse_py_or_json(&main).ok()?;
    let colliders = v
        .get("colliders")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let rigid_bodies = v
        .get("rigidBodys")
        .or_else(|| v.get("rigidBodies"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let triggers = v
        .get("triggers")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let actions = v
        .get("actions")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if colliders.is_empty() && rigid_bodies.is_empty() && triggers.is_empty() && actions.is_empty() {
        return None;
    }
    Some(VngePhysicsData {
        version: v
            .get("version")
            .and_then(Value::as_str)
            .unwrap_or("1")
            .to_string(),
        colliders,
        rigid_bodies,
        triggers,
        actions,
    })
}

pub fn parse_vnsound(
    blocks: Option<&rmpv::Value>,
    reg: &VngeRegistry,
    out_dir: Option<&Path>,
) -> Option<VngeSoundData> {
    let b = blocks?;
    let (version, main, _) = data_png_load(b, "vnge_sound")?;
    let root = parse_py_or_json(&main).ok()?;
    let sound_map = root.get("Sound").and_then(Value::as_object);
    let spectrum = root.get("Spectrum").cloned().unwrap_or(Value::Null);
    let general = root.get("General").cloned().unwrap_or(Value::Null);

    // Unpack embedded audio blobs from `vnge_sound_extdata` (either a msgpack map of key -> binary/str, or StudioNEO indexed base64).
    let mut ext_blobs: std::collections::HashMap<String, Vec<u8>> = std::collections::HashMap::new();
    if let Some(ext_plugin) = map_get(b, "vnge_sound_extdata") {
        let ext_inner = ext_plugin.as_array().and_then(|a| a.get(1)).unwrap_or(ext_plugin);
        if let Some(main_val) = map_get(ext_inner, "main") {
            if let Some(entries) = main_val.as_map() {
                for (k, v) in entries {
                    let Some(ks) = k.as_str() else { continue };
                    if let Some(bin) = v.as_slice() {
                        ext_blobs.insert(ks.to_string(), bin.to_vec());
                    } else if let Some(s) = v.as_str() {
                        if let Some(bin) = decode_base64_lenient(s) {
                            ext_blobs.insert(ks.to_string(), bin);
                        }
                    }
                }
            } else if let Some(keys_str) = main_val.as_str() {
                if let Ok(Value::Array(keys)) = parse_py_or_json(keys_str) {
                    for (idx, kv) in keys.iter().enumerate() {
                        let Some(ks) = kv.as_str() else { continue };
                        if let Some((_, b64, _)) = data_png_load(b, &format!("vnge_sound_extdata_{idx}")) {
                            if let Some(bin) = decode_base64_lenient(&b64) {
                                ext_blobs.insert(ks.to_string(), bin);
                            }
                        }
                    }
                }
            }
        }
    }

    let mut sources = Vec::new();
    let mut file_idx = 0usize;
    if let Some(sm) = sound_map {
        for (group_or_id, item) in sm {
            let mut push_one = |id: &str, group: &str, cfg: &Value| {
                let path_str = cfg
                    .get("path")
                    .or_else(|| cfg.get("file"))
                    .or_else(|| cfg.get("url"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let ext_key = cfg
                    .get("extKey")
                    .or_else(|| cfg.get("extdata"))
                    .and_then(Value::as_str)
                    .unwrap_or(if !path_str.is_empty() { path_str.as_str() } else { id });
                let mut extracted_path = String::new();
                if let (Some(dir), Some(bytes)) = (out_dir, ext_blobs.get(ext_key).or_else(|| ext_blobs.get(id))) {
                    if !bytes.is_empty() {
                        let ext = audio_ext(bytes, &path_str);
                        let out_file = dir.join(format!("vnsound_{file_idx}.{ext}"));
                        file_idx += 1;
                        if std::fs::write(&out_file, bytes).is_ok() {
                            extracted_path = out_file.display().to_string();
                        }
                    }
                }
                let bind_actor = cfg
                    .get("actor")
                    .or_else(|| cfg.get("target"))
                    .or_else(|| cfg.get("bindActor"))
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .to_string();
                let bind_key = if !bind_actor.is_empty() {
                    reg.resolve_any(&bind_actor).unwrap_or(-1)
                } else {
                    num_i32(cfg.get("targetKey"), -1)
                };
                sources.push(VngeSoundSource {
                    id: id.to_string(),
                    group: group.to_string(),
                    path: path_str,
                    extracted_path,
                    volume: num_f32(cfg.get("volume").or_else(|| cfg.get("vol")), 1.0),
                    pitch: num_f32(cfg.get("pitch"), 1.0),
                    loop_play: flag_bool(cfg.get("loop"), false),
                    auto_play: flag_bool(cfg.get("autoPlay").or_else(|| cfg.get("autoplay")), false),
                    is_3d: flag_bool(cfg.get("is3D").or_else(|| cfg.get("spatial")), bind_key >= 0),
                    bind_key,
                    bind_actor,
                    min_dist: num_f32(cfg.get("minDist").or_else(|| cfg.get("minDistance")), 1.0),
                    max_dist: num_f32(cfg.get("maxDist").or_else(|| cfg.get("maxDistance")), 25.0),
                    raw: cfg.clone(),
                });
            };

            if let Some(sub) = item.as_object() {
                if sub.contains_key("path") || sub.contains_key("file") || sub.contains_key("volume") || sub.contains_key("vol") {
                    push_one(group_or_id, "", item);
                } else {
                    for (sid, scfg) in sub {
                        push_one(sid, group_or_id, scfg);
                    }
                }
            } else if let Some(arr) = item.as_array() {
                for (i, scfg) in arr.iter().enumerate() {
                    let sid = scfg
                        .get("id")
                        .or_else(|| scfg.get("name"))
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                        .unwrap_or_else(|| format!("{group_or_id}_{i}"));
                    push_one(&sid, group_or_id, scfg);
                }
            }
        }
    }

    let has_spectrum = spectrum.as_array().is_some_and(|a| !a.is_empty());
    if sources.is_empty() && !has_spectrum {
        return None;
    }
    Some(VngeSoundData {
        version,
        sources,
        spectrum,
        general,
    })
}

// ============================================================================
// VNGE PoseSaveState (`Console/Lib/sss/*/*.png` & `.txt`) reader / writer
// ============================================================================

fn read_7bit_str<'a>(bytes: &'a [u8], pos: &mut usize) -> Result<&'a str, String> {
    let mut len: usize = 0;
    let mut shift = 0;
    loop {
        let b = *bytes.get(*pos).ok_or("unexpected EOF reading 7-bit length")?;
        *pos += 1;
        len |= ((b & 0x7f) as usize) << shift;
        if b & 0x80 == 0 {
            break;
        }
        shift += 7;
        if shift > 28 {
            return Err("invalid 7-bit string length".into());
        }
    }
    let end = pos.checked_add(len).ok_or("string length overflow")?;
    let slice = bytes.get(*pos..end).ok_or("truncated string payload")?;
    *pos = end;
    std::str::from_utf8(slice).map_err(|e| e.to_string())
}

fn write_7bit_str(out: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    let mut n = bytes.len();
    loop {
        let mut b = (n & 0x7f) as u8;
        n >>= 7;
        if n != 0 {
            b |= 0x80;
        }
        out.push(b);
        if n == 0 {
            break;
        }
    }
    out.extend_from_slice(bytes);
}

/// Reads a VNGE `PoseSaveState` preset from either a `.png` (PNG + `.NET BinaryWriter` tail) or plain `.txt`/`.json`.
pub fn read_vnge_pose_preset(bytes: &[u8]) -> Result<VngePosePreset, String> {
    let plen = png_len(bytes);
    let (category, text) = if plen > 0 && plen < bytes.len() {
        let mut pos = plen;
        let magic = read_7bit_str(bytes, &mut pos)?;
        if magic != "vnge_posesavestate" {
            return Err(format!("unexpected PoseSaveState marker: {magic:?}"));
        }
        let cat = read_7bit_str(bytes, &mut pos)?.to_string();
        let body = read_7bit_str(bytes, &mut pos)?.to_string();
        (cat, body)
    } else {
        let body = std::str::from_utf8(bytes)
            .map_err(|e| format!("invalid UTF-8 pose text: {e}"))?
            .trim_start_matches('\u{feff}')
            .to_string();
        (String::new(), body)
    };
    let raw = parse_py_or_json(&text)?;
    let pose = raw.get("pose").cloned().unwrap_or_else(|| raw.clone());
    let tags = raw
        .get("tags")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(|x| x.as_str().map(str::to_owned))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    Ok(VngePosePreset {
        category,
        pose,
        tags,
        raw,
    })
}

/// Minimal 1x1 transparent PNG fallback when saving a VNGE `PoseSaveState` `.png` without a custom screenshot.
const TINY_PNG_1X1: &[u8] = &[
    0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, b'I', b'H', b'D', b'R',
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89,
    0x00, 0x00, 0x00, 0x0a, b'I', b'D', b'A', b'T',
    0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4,
    0x00, 0x00, 0x00, 0x00, b'I', b'E', b'N', b'D', 0xae, 0x42, 0x60, 0x82,
];

/// Encodes a VNGE `PoseSaveState` `.png` file compatible with `posesavestate.py`.
pub fn write_vnge_pose_preset(category: &str, json_payload: &str, png_thumb: Option<&[u8]>) -> Vec<u8> {
    let thumb = png_thumb
        .filter(|b| png_len(b) > 0)
        .map(|b| &b[..png_len(b)])
        .unwrap_or(TINY_PNG_1X1);
    let mut out = Vec::with_capacity(thumb.len() + json_payload.len() + 64);
    out.extend_from_slice(thumb);
    write_7bit_str(&mut out, "vnge_posesavestate");
    write_7bit_str(&mut out, category);
    write_7bit_str(&mut out, json_payload);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vnge_pose_preset_png_roundtrips_with_7bit_strings() {
        let payload = r#"{"pose": {"eyebrow": 2, "eyes": 4, "eyes_open": 0.663, "mouth": 40, "mouth_open": 0.863}, "tags": ["Sexy", "Smile"]}"#;
        let encoded = write_vnge_pose_preset("sss/ffaces/", payload, None);
        assert!(png_len(&encoded) > 0);
        let decoded = read_vnge_pose_preset(&encoded).expect("preset must parse");
        assert_eq!(decoded.category, "sss/ffaces/");
        assert_eq!(decoded.tags, vec!["Sexy".to_string(), "Smile".to_string()]);
        assert_eq!(decoded.pose["eyebrow"], 2);
        assert_eq!(decoded.pose["mouth"], 40);
    }
}
