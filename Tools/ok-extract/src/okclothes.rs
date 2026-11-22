//! OK clothes (`.okclothes`): one outfit (clothes + accessories and the
//! plugin data that belongs to them) as an OK file. Made from a game
//! coordinate card (`【KoiKatuClothes】`) or exported from a character card's
//! outfit; worn by writing it into a character card's outfit. Shared
//! resources come from the OK base library; the file only names them.
use std::io::Cursor;
use std::path::Path;

use rmpv::Value;

/// A game coordinate card: thumbnail PNG + coordinate data + ExtendedSave.
pub struct CoordinateFile {
    pub png: Vec<u8>,
    pub product: i32,
    pub marker: String,
    pub version: String,
    pub name: String,
    /// ChaFileCoordinate bytes (same layout as one character Coordinate entry).
    pub data: Vec<u8>,
    /// ExtendedSave plugin dictionary (`KKEx`), if any.
    pub kkex: Option<Value>,
    pub kkex_version: i32,
}

fn png_end(bytes: &[u8]) -> Result<usize, String> {
    let (iend, _) = crate::portable::png_snapshot(bytes)?;
    Ok(iend + 12)
}

pub fn read_coordinate_file(bytes: &[u8]) -> Result<CoordinateFile, String> {
    let end = png_end(bytes)?;
    let trailer = &bytes[end..];
    let mut c = Cursor::new(trailer);
    let product = crate::card::read_i32_le(&mut c)?;
    let marker = crate::card::read_dotnet_string(&mut c)?;
    if !marker.contains("KoiKatuClothes") { return Err(format!("not a coordinate card ({marker})")); }
    let version = crate::card::read_dotnet_string(&mut c)?;
    let name = crate::card::read_dotnet_string(&mut c)?;
    let len = crate::card::read_i32_le(&mut c)?;
    if len < 0 { return Err("coordinate data length".into()); }
    let at = c.position() as usize;
    let data = trailer.get(at..at + len as usize).ok_or("coordinate data truncated")?.to_vec();
    c.set_position((at + len as usize) as u64);
    let (mut kkex, mut kkex_version) = (None, 0);
    if let Ok(tag) = crate::card::read_dotnet_string(&mut c) {
        if tag == "KKEx" {
            kkex_version = crate::card::read_i32_le(&mut c)?;
            let n = crate::card::read_i32_le(&mut c)?;
            let at = c.position() as usize;
            let raw = trailer.get(at..at + n.max(0) as usize).ok_or("KKEx truncated")?;
            kkex = rmpv::decode::read_value(&mut Cursor::new(raw)).ok();
        }
    }
    Ok(CoordinateFile { png: bytes[..end].to_vec(), product, marker, version, name, data, kkex, kkex_version })
}

/// Character card ExtendedSave dictionary (`KKEx` block).
pub fn card_kkex(card: &[u8]) -> Result<Option<Value>, String> {
    let blocks = crate::appearance::blocks_from_card(card)?;
    let Some(raw) = blocks.get("KKEx") else { return Ok(None) };
    for input in [&raw[..], raw.get(4..).unwrap_or(&[])] {
        if let Ok(v) = rmpv::decode::read_value(&mut Cursor::new(input)) { if v.is_map() { return Ok(Some(v)); } }
    }
    Ok(None)
}

/// Structure outline for inspection (depth-limited, arrays shortened).
pub fn outline(v: &Value, depth: usize) -> String {
    fn go(v: &Value, depth: usize, out: &mut String) {
        match v {
            Value::Map(m) if depth > 0 => {
                out.push('{');
                for (i, (k, val)) in m.iter().enumerate() {
                    if i > 0 { out.push_str(", "); }
                    if i >= 12 { out.push_str(&format!("…+{}", m.len() - 12)); break; }
                    out.push_str(&k.to_string());out.push_str(": ");go(val, depth - 1, out);
                }
                out.push('}');
            }
            Value::Array(a) if depth > 0 => {
                out.push_str(&format!("[{}× ", a.len()));
                // Short arrays (plugin [version, data]) in full, long ones by their first item.
                for (i, item) in a.iter().take(if a.len() <= 4 { 4 } else { 1 }).enumerate() { if i > 0 { out.push_str(" | "); } go(item, depth - 1, out); }
                out.push(']');
            }
            Value::Binary(b) => {
                // Plugin payloads are often nested msgpack.
                match rmpv::decode::read_value(&mut Cursor::new(&b[..])) {
                    Ok(inner) if depth > 0 && (inner.is_map() || inner.is_array()) => { out.push_str("bin:"); go(&inner, depth - 1, out); }
                    _ => out.push_str(&format!("bin({})", b.len())),
                }
            }
            Value::String(s) => { let s = s.as_str().unwrap_or(""); out.push_str(&format!("{:?}", if s.len() > 40 { &s[..40] } else { s })); }
            Value::Map(m) => out.push_str(&format!("{{{}}}", m.len())),
            Value::Array(a) => out.push_str(&format!("[{}]", a.len())),
            other => out.push_str(&other.to_string()),
        }
    }
    let mut out = String::new();
    go(v, depth, &mut out);
    out
}

pub fn probe(path: &Path) -> Result<(), String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    match read_coordinate_file(&bytes) {
        Ok(f) => {
            println!("COORDINATE product={} marker={} version={} name={:?} data={} kkex_version={}", f.product, f.marker, f.version, f.name, f.data.len(), f.kkex_version);
            if let Some(Value::Map(m)) = &f.kkex { for (k, v) in m { println!("  {k}: {}", outline(v, 6)); } }
        }
        Err(_) => {
            println!("CHARACTER card");
            if let Some(Value::Map(m)) = card_kkex(&bytes)? { for (k, v) in m { println!("  {k}: {}", outline(&v, 6)); } }
        }
    }
    Ok(())
}

/// Print one plugin's data fully (inspection).
pub fn probe_plugin(path: &Path, plugin: &str) -> Result<(), String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let kkex = if let Ok(c) = OkClothes::from_bytes(&bytes) { Some(c.plugins) } else { match read_coordinate_file(&bytes) { Ok(f) => f.kkex, Err(_) => card_kkex(&bytes)? } };
    if let Some(Value::Map(m)) = kkex {
        for (k, v) in m {
            if k.as_str() != Some(plugin) { continue; }
            println!("{}", outline(&v, 12));
            if let Some(x) = find_string(&v) { println!("{x}"); }
            // Every entry of each list (Material Editor's *List, DynamicBoneEditor's), one a line.
            let data = match &v { Value::Array(a) if a.len() == 2 => a[1].clone(), other => other.clone() };
            for (name, list) in data.as_map().into_iter().flatten() {
                if let Value::Array(items) = unbin(list) { for item in items { println!("{name}\t{}", outline(&item, 3)); } }
                // OK_DUMP_TEX=<folder>: Material Editor's textures written there as <TexID>.png.
                if name.as_str() == Some("TextureDictionary") {
                    let Some(dir) = std::env::var_os("OK_DUMP_TEX") else { continue };
                    for (id, png) in unbin(list).as_map().into_iter().flatten() {
                        if let (Some(id), Some(png)) = (int_key(id), png.as_slice()) { let _ = std::fs::write(Path::new(&dir).join(format!("{id}.png")), png); }
                    }
                }
            }
        }
    }
    Ok(())
}
/// Print each outfit's accessory slots (inspection): slot, type, id, parent, whether the HairAccessoryCustomizer lists
/// it and whether wearing an outfit with her hair kept keeps it (HEAD). A character card, a coordinate card or an
/// .okclothes.
pub fn probe_accessories(path: &Path) -> Result<(), String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let (entries, kkex, coordinate): (Vec<Vec<u8>>, Value, bool) = if let Ok(c) = OkClothes::from_bytes(&bytes) {
        (vec![c.coordinate], c.plugins, true)
    } else if let Ok(f) = read_coordinate_file(&bytes) {
        (vec![f.data], f.kkex.unwrap_or(Value::Nil), true)
    } else {
        (coordinate_entries(&crate::appearance::blocks_from_card(&bytes)?)?, card_kkex(&bytes)?.unwrap_or(Value::Nil), false)
    };
    let hair = hair_accessory_slots(&kkex, coordinate);
    for (outfit, entry) in entries.iter().enumerate() {
        let parts = accessory_section(entry).and_then(|(v, _)| map_get(&v, "parts").and_then(|p| p.as_array()).cloned()).unwrap_or_default();
        let slots = acc_slots(&parts, &xml_elements(&kkex, outfit, coordinate));
        println!("outfit {outfit}: {} parts, {} slots", parts.len(), slots.len());
        for (slot, s) in slots.iter().enumerate() {
            if s.kind() == 120 { continue; }
            let id = match s { AccSlot::Part(p) => map_get(p, "id").and_then(int_key).unwrap_or(0).to_string(), AccSlot::Xml(x) => xml_attr(x, "id").unwrap_or("").to_owned() };
            let customizer = hair.get(&(outfit as i64)).is_some_and(|h| h.contains(&(slot as i64)));
            let head = customizer || is_head_accessory(s.parent());
            println!("  {slot:>3} type={} id={id} parent={}{}{}", s.kind(), s.parent(), if customizer { " HAIR(customizer)" } else { "" }, if head { " HEAD" } else { "" });
        }
    }
    Ok(())
}

/// The accessory slots HairAccessoryCustomizer marks as hair, per outfit: it keeps settings for every accessory with a
/// hair component, and `ColorMatch` (follows the hair colour) tells hair from ornaments built from hair parts
/// (Raiden's ankle flower hangs from her heel with ColorMatch off). A character keeps `HairAccessories`
/// {outfit: {slot: info}}; a coordinate `CoordinateHairAccessories` {slot: info} (outfit 0 here).
fn hair_accessory_slots(kkex: &Value, coordinate: bool) -> std::collections::HashMap<i64, std::collections::HashSet<i64>> {
    let mut out: std::collections::HashMap<i64, std::collections::HashSet<i64>> = Default::default();
    let Some((_, data)) = plugin_data(kkex, HAIR_ACCESSORIES) else { return out };
    let slots = |m: &Value| -> std::collections::HashSet<i64> {
        m.as_map().map(|m| m.iter().filter(|(_, info)| map_get(info, "ColorMatch").and_then(Value::as_bool) != Some(false)).filter_map(|(k, _)| int_key(k)).collect()).unwrap_or_default()
    };
    if coordinate {
        if let Some(v) = map_get(data, "CoordinateHairAccessories").map(unbin) { out.insert(0, slots(&v)); }
    } else if let Some(v) = map_get(data, "HairAccessories").map(unbin) {
        for (k, m) in v.as_map().into_iter().flatten() { if let Some(o) = int_key(k) { out.insert(o, slots(&unbin(m))); } }
    }
    out
}

fn find_string(v: &Value) -> Option<String> {
    match v {
        Value::String(s) if s.as_str().is_some_and(|s| s.len() > 60) => s.as_str().map(str::to_owned),
        Value::Array(a) => a.iter().find_map(find_string),
        Value::Map(m) => m.iter().find_map(|(_, v)| find_string(v)),
        _ => None,
    }
}

// ------------------------------------------------------------------ format

pub const CLOTHES_CHUNK: &[u8; 4] = b"okCl";

/// `.okclothes`: a PNG thumbnail carrying one `okCl` chunk with this payload
/// (msgpack). Plugin data is kept in the game's coordinate-level form, so a
/// coordinate card imports losslessly and wearing it is the game's own
/// coordinate-load conversion.
#[derive(Debug, Clone)]
pub struct OkClothes {
    pub name: String,
    /// "coordinate" (imported card) or "character" (exported outfit).
    pub source: String,
    /// ChaFileCoordinate bytes: clothes, accessories, makeup.
    pub coordinate: Vec<u8>,
    /// Coordinate-level ExtendedSave: plugin key -> [version, data].
    pub plugins: Value,
    /// OK base library models the outfit uses (filled when known).
    pub models: Vec<String>,
    /// Plugin data that cannot follow the outfit (reported, not written).
    pub dropped: Vec<String>,
    /// The `okLc` pack of the OK card the outfit came from: its third-party models (not in the shared base library)
    /// go with it, so another OK card can wear it without the zipmods (an `okLc` chunk of the .okclothes PNG).
    pub pack: Option<Vec<u8>>,
    /// That card's `okLt` answers (what its open asks of the mods tree): the outfit's third-party mods are not in the
    /// shared library's tree, so the card wearing it takes these (an `okLt` chunk of the .okclothes PNG).
    pub answers: Option<Vec<u8>>,
}

fn map_get<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    v.as_map()?.iter().find(|(k, _)| k.as_str() == Some(key)).map(|(_, v)| v)
}
fn map_set(v: &mut Value, key: &str, value: Value) {
    if !v.is_map() { *v = Value::Map(Vec::new()); }
    let Value::Map(m) = v else { unreachable!() };
    match m.iter_mut().find(|(k, _)| k.as_str() == Some(key)) { Some((_, slot)) => *slot = value, None => m.push((key.into(), value)) }
}
fn map_remove(v: &mut Value, key: &str) -> Option<Value> {
    let Value::Map(m) = v else { return None };
    let i = m.iter().position(|(k, _)| k.as_str() == Some(key))?;
    Some(m.remove(i).1)
}
fn encode(v: &Value) -> Vec<u8> { let mut b = Vec::new(); let _ = rmpv::encode::write_value(&mut b, v); b }
fn decode(b: &[u8]) -> Option<Value> { rmpv::decode::read_value(&mut Cursor::new(b)).ok() }
/// Plugin payload fields are often msgpack inside a binary.
fn unbin(v: &Value) -> Value { match v { Value::Binary(b) => decode(b).unwrap_or(Value::Nil), other => other.clone() } }
fn bin(v: &Value) -> Value { Value::Binary(encode(v)) }
fn array_mut(v: &mut Value) -> Option<&mut Vec<Value>> { match v { Value::Array(a) => Some(a), _ => None } }
/// [version, data] -> data
fn plugin_data<'a>(plugins: &'a Value, key: &str) -> Option<(Value, &'a Value)> {
    let p = map_get(plugins, key)?;
    match p { Value::Array(a) if a.len() == 2 => Some((a[0].clone(), &a[1])), other => Some((Value::from(0), other)) }
}
fn set_plugin(plugins: &mut Value, key: &str, version: Value, data: Value) { map_set(plugins, key, Value::Array(vec![version, data])); }
fn int_key(v: &Value) -> Option<i64> { v.as_i64().or_else(|| v.as_str().and_then(|s| s.parse().ok())) }

const SIDELOADER: &str = "com.bepis.sideloader.universalautoresolver";
const MATERIAL_EDITOR: &str = "com.deathweasel.bepinex.materialeditor";
const OVERLAYS: &str = "KCOX";
const PUSHUP: &str = "com.deathweasel.bepinex.pushup";
const MORE_ACCESSORIES: &str = "moreAccessories";
const DYNAMIC_BONES: &str = "com.deathweasel.bepinex.dynamicboneeditor";
const MIGRATION: &str = "MigrationHelper";
const HAIR_ACCESSORIES: &str = "com.deathweasel.bepinex.hairaccessorycustomizer";
const ACCESSORY_STATES: &str = "Accessory_States";
const ACCESSORY_SWITCH: &str = "madevil.kk.ass";

// ------------------------------------------------------- per-plugin rules

/// How a worn outfit's accessories meet the character's: the outfit's replace hers (a whole outfit), hers stay (clothes
/// only), or per slot (`SlotPlan`: her hair and head accessories stay, the outfit's others move in).
#[derive(Clone, Copy)]
enum Accessories<'a> { Outfit, Character, Slots(&'a SlotPlan) }

/// Accessory slots of the worn outfit: `keep` hers (same slot), `take` the outfit's slot -> the slot it is worn in.
#[derive(Default, Debug)]
struct SlotPlan { keep: std::collections::HashSet<i64>, take: std::collections::HashMap<i64, i64> }

impl Accessories<'_> {
    /// Her accessory in `slot` of the worn outfit stays.
    fn keeps(&self, slot: i64) -> bool { match self { Self::Outfit => false, Self::Character => true, Self::Slots(p) => p.keep.contains(&slot) } }
    /// The slot the outfit's accessory in `slot` is worn in (None: not worn).
    fn takes(&self, slot: i64) -> Option<i64> { match self { Self::Outfit => Some(slot), Self::Character => None, Self::Slots(p) => p.take.get(&slot).copied() } }
}

/// The slot of a Sideloader property `accessory<N>.ChaFileAccessory...`.
fn accessory_property_slot(p: &str) -> Option<i64> {
    let r = p.strip_prefix("accessory")?;
    let digits = r.len() - r.trim_start_matches(|c: char| c.is_ascii_digit()).len();
    (digits > 0 && r[digits..].starts_with('.')).then(|| r[..digits].parse().ok()).flatten()
}

/// Sideloader: coordinate properties have no `outfitN.` prefix.
fn sideloader(from: &Value, to: &mut Value, outfit: usize, wear: bool, acc: Accessories) {
    let prefix = format!("outfit{outfit}.");
    let entries = |v: Option<(Value, &Value)>| -> Vec<Value> { v.and_then(|(_, d)| map_get(d, "info").and_then(|i| i.as_array()).cloned()).unwrap_or_default() };
    // Hers for other outfits stay; for this one only the accessories that stay.
    let stays = |p: &str| p.strip_prefix(&prefix).is_none_or(|rest| accessory_property_slot(rest).is_some_and(|s| acc.keeps(s)));
    let mut kept: Vec<Value> = if wear { entries(plugin_data(to, SIDELOADER)).into_iter().filter(|e| map_get(&unbin(e), "Property").and_then(|p| p.as_str()).is_none_or(stays)).collect() } else { Vec::new() };
    for e in entries(plugin_data(from, SIDELOADER)) {
        let mut info = unbin(&e);
        let Some(property) = map_get(&info, "Property").and_then(|p| p.as_str()).map(str::to_owned) else { continue };
        let property = if wear {
            let property = match accessory_property_slot(&property) {
                Some(slot) => match acc.takes(slot) {
                    Some(to) => format!("accessory{to}{}", property["accessory".len()..].trim_start_matches(|c: char| c.is_ascii_digit())),
                    None => continue,
                },
                None => property,
            };
            format!("{prefix}{property}")
        } else { match property.strip_prefix(&prefix) { Some(p) => p.to_owned(), None => continue } };
        map_set(&mut info, "Property", property.into());
        kept.push(bin(&info));
    }
    let version = plugin_data(from, SIDELOADER).map(|(v, _)| v).unwrap_or(Value::from(0));
    if kept.is_empty() && !wear { return; }
    set_plugin(to, SIDELOADER, version, Value::Map(vec![("info".into(), Value::Array(kept))]));
}

/// Material Editor: list entries carry CoordinateIndex; clothing (1) and
/// accessory (2) objects follow the outfit, with their textures.
fn material_editor(from: &Value, to: &mut Value, outfit: usize, wear: bool, acc: Accessories) {
    let Some((version, src)) = plugin_data(from, MATERIAL_EDITOR) else { return };
    let src = src.clone();
    let mut dst = if wear { plugin_data(to, MATERIAL_EDITOR).map(|(_, d)| d.clone()).unwrap_or(Value::Map(Vec::new())) } else { Value::Map(Vec::new()) };
    let src_tex = map_get(&src, "TextureDictionary").map(unbin).unwrap_or(Value::Nil);
    let mut dst_tex = if wear { map_get(&dst, "TextureDictionary").map(unbin).unwrap_or(Value::Map(Vec::new())) } else { Value::Map(Vec::new()) };
    if !dst_tex.is_map() { dst_tex = Value::Map(Vec::new()); }
    let mut next_id = dst_tex.as_map().map(|m| m.iter().filter_map(|(k, _)| int_key(k)).max().unwrap_or(-1) + 1).unwrap_or(0);
    let mut tex_map: std::collections::HashMap<i64, i64> = std::collections::HashMap::new();
    let outfit = outfit as i64;
    let lists: Vec<String> = src.as_map().map(|m| m.iter().filter_map(|(k, _)| k.as_str().filter(|k| k.ends_with("List")).map(str::to_owned)).collect()).unwrap_or_default();
    for list in lists {
        let incoming = map_get(&src, &list).map(unbin).and_then(|v| v.as_array().cloned()).unwrap_or_default();
        let mut out: Vec<Value> = if wear { map_get(&dst, &list).map(unbin).and_then(|v| v.as_array().cloned()).unwrap_or_default() } else { Vec::new() };
        let object = |e: &Value| map_get(e, "ObjectType").and_then(int_key).unwrap_or(-1);
        let slot = |e: &Value| map_get(e, "Slot").and_then(int_key).unwrap_or(-1);
        let ours = |e: &Value, index: i64| map_get(e, "CoordinateIndex").and_then(int_key) == Some(index) && matches!(object(e), 1 | 2);
        // Worn: her clothing entries of this outfit go, her accessories' unless they stay.
        if wear { out.retain(|e| !ours(e, outfit) || (object(e) == 2 && acc.keeps(slot(e)))); }
        for mut e in incoming {
            // A coordinate card's entries keep the outfit index they were saved from (bunny.png 5, extra.png 2), and the
            // game's coordinate load takes them all whatever it is: taking index 0 only lost every shader, texture,
            // colour and transparency change of such a card (2026-11-12, the bunny suit opaque and dark, extra white).
            if wear {
                match object(&e) {
                    1 => {}
                    2 => match acc.takes(slot(&e)) { Some(to) => map_set(&mut e, "Slot", Value::from(to)), None => continue },
                    _ => continue,
                }
            } else if !ours(&e, outfit) { continue; }
            map_set(&mut e, "CoordinateIndex", Value::from(if wear { outfit } else { 0 }));
            if let Some(id) = map_get(&e, "TexID").and_then(int_key) {
                let new = *tex_map.entry(id).or_insert_with(|| {
                    let png = src_tex.as_map().and_then(|m| m.iter().find(|(k, _)| int_key(k) == Some(id)).map(|(_, v)| v.clone()));
                    let new = if wear { let n = next_id; next_id += 1; n } else { id };
                    if let (Some(png), Value::Map(m)) = (png, &mut dst_tex) { m.push((Value::from(new), png)); }
                    new
                });
                map_set(&mut e, "TexID", Value::from(new));
            }
            out.push(e);
        }
        if out.is_empty() && !wear { continue; }
        map_set(&mut dst, &list, bin(&Value::Array(out)));
    }
    if dst_tex.as_map().is_some_and(|m| !m.is_empty()) || wear { map_set(&mut dst, "TextureDictionary", bin(&dst_tex)); }
    if dst.as_map().is_some_and(|m| !m.is_empty()) { set_plugin(to, MATERIAL_EDITOR, version, dst); }
}

/// Overlays (KCOX) and Pushup: the character keeps one entry per outfit index.
fn per_outfit_maps(from: &Value, to: &mut Value, outfit: usize, wear: bool, key: &str, fields: &[(&str, &str)]) {
    let Some((version, src)) = plugin_data(from, key) else { return };
    let src = src.clone();
    let mut dst = if wear { plugin_data(to, key).map(|(_, d)| d.clone()).unwrap_or(Value::Map(Vec::new())) } else { Value::Map(Vec::new()) };
    for (coordinate_field, character_field) in fields {
        let (src_field, dst_field) = if wear { (*coordinate_field, *character_field) } else { (*character_field, *coordinate_field) };
        let Some(value) = map_get(&src, src_field).map(unbin) else { continue };
        if wear {
            let mut table = map_get(&dst, dst_field).map(unbin).filter(|v| v.is_map()).unwrap_or(Value::Map(Vec::new()));
            if let Value::Map(m) = &mut table {
                m.retain(|(k, _)| int_key(k) != Some(outfit as i64));
                if !value.is_nil() { m.push((Value::from(outfit), value)); }
            }
            map_set(&mut dst, dst_field, bin(&table));
        } else if let Some(entry) = value.as_map().and_then(|m| m.iter().find(|(k, _)| int_key(k) == Some(outfit as i64)).map(|(_, v)| v.clone())) {
            map_set(&mut dst, dst_field, bin(&entry));
        }
    }
    if dst.as_map().is_some_and(|m| !m.is_empty()) { set_plugin(to, key, version, dst); }
}

fn xml_root_open(x: &str) -> Option<(usize, usize)> { let s = x.find("<additionalAccessories")?; let e = x[s..].find('>')? + s; Some((s, e)) }
/// The body of an `<additionalAccessories>` document.
fn xml_inner(x: &str) -> String {
    let Some((_, e)) = xml_root_open(x) else { return String::new() };
    if x[..=e].ends_with("/>") { return String::new(); }
    let end = x.rfind("</additionalAccessories>").unwrap_or(x.len());
    x[e + 1..end].to_owned()
}
/// Its opening tag without the closing `>`.
fn xml_header(x: &str) -> String { xml_root_open(x).map(|(s, e)| x[s..=e].trim_end_matches("/>").trim_end_matches('>').trim_end().to_owned()).unwrap_or_else(|| "<additionalAccessories version=\"2.0.21\"".into()) }
/// A character body split into accessorySet elements (outfit, element).
fn xml_sets(body: &str) -> Vec<(i64, String)> {
    let mut out = Vec::new();
    let mut rest = body;
    while let Some(s) = rest.find("<accessorySet") {
        let tail = &rest[s..];
        let open_end = tail.find('>').unwrap_or(tail.len() - 1);
        let self_closing = tail[..=open_end].ends_with("/>");
        let end = if self_closing { open_end + 1 } else { tail.find("</accessorySet>").map(|e| e + "</accessorySet>".len()).unwrap_or(tail.len()) };
        let element = &tail[..end];
        let kind = element.split("type=\"").nth(1).and_then(|t| t.split('"').next()).and_then(|t| t.parse().ok()).unwrap_or(-1);
        out.push((kind, element.to_owned()));
        rest = &tail[end..];
    }
    out
}
/// The `<accessory>` elements of a body, in order (slot 20 first).
fn xml_accessories(body: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut rest = body;
    while let Some(s) = rest.find("<accessory") {
        let tail = &rest[s..];
        if tail[10..].starts_with("Set") { rest = &tail[10..]; continue; }
        let open_end = tail.find('>').unwrap_or(tail.len() - 1);
        let end = if tail[..=open_end].ends_with("/>") { open_end + 1 } else { tail.find("</accessory>").map(|e| e + "</accessory>".len()).unwrap_or(tail.len()) };
        out.push(tail[..end].to_owned());
        rest = &tail[end..];
    }
    out
}
fn xml_attr<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let key = format!(" {name}=\"");
    let rest = &tag[tag.find(&key)? + key.len()..];
    Some(&rest[..rest.find('"')?])
}
/// Her MoreAccessories document (`to`'s, else a new one) with outfit `outfit`'s set replaced by `elements` (none: no set).
fn set_outfit_xml(to: &mut Value, outfit: usize, elements: &[String], version: Value) {
    let current = plugin_data(to, MORE_ACCESSORIES).map(|(v, d)| (v, map_get(d, "additionalAccessories").and_then(|v| v.as_str()).map(str::to_owned)));
    let (version, base) = match current {
        Some((v, Some(x))) => (v, x),
        _ if elements.is_empty() => return,
        _ => (version, "<additionalAccessories version=\"2.0.21.1\"></additionalAccessories>".to_owned()),
    };
    let mut groups: Vec<(i64, String)> = xml_sets(&xml_inner(&base)).into_iter().filter(|(k, _)| *k != outfit as i64).collect();
    if !elements.is_empty() { groups.push((outfit as i64, format!("<accessorySet type=\"{outfit}\">{}</accessorySet>", elements.concat()))); }
    groups.sort_by_key(|g| g.0);
    let result = format!("{}>{}</additionalAccessories>", xml_header(&base), groups.into_iter().map(|g| g.1).collect::<String>());
    set_plugin(to, MORE_ACCESSORIES, version, Value::Map(vec![("additionalAccessories".into(), result.into())]));
}

/// moreAccessories: the character XML groups extra slots by
/// `<accessorySet type="outfit">`; a coordinate lists them directly.
fn more_accessories(from: &Value, to: &mut Value, outfit: usize, wear: bool) {
    let Some((version, src)) = plugin_data(from, MORE_ACCESSORIES) else { return };
    let Some(xml) = map_get(src, "additionalAccessories").and_then(|v| v.as_str()).map(str::to_owned) else { return };
    let result = if wear {
        let target = plugin_data(to, MORE_ACCESSORIES).and_then(|(_, d)| map_get(d, "additionalAccessories").and_then(|v| v.as_str()).map(str::to_owned));
        let base = target.unwrap_or_else(|| format!("{}></additionalAccessories>", xml_header(&xml)));
        let mut groups: Vec<(i64, String)> = xml_sets(&xml_inner(&base)).into_iter().filter(|(k, _)| *k != outfit as i64).collect();
        let accessories = xml_inner(&xml);
        if !accessories.trim().is_empty() { groups.push((outfit as i64, format!("<accessorySet type=\"{outfit}\">{accessories}</accessorySet>"))); }
        groups.sort_by_key(|g| g.0);
        format!("{}>{}</additionalAccessories>", xml_header(&base), groups.into_iter().map(|g| g.1).collect::<String>())
    } else {
        let Some((_, set)) = xml_sets(&xml_inner(&xml)).into_iter().find(|(k, _)| *k == outfit as i64) else { return };
        let body = set.find('>').map(|o| { let b = &set[o + 1..]; b.strip_suffix("</accessorySet>").unwrap_or("").to_owned() }).unwrap_or_default();
        format!("{}>{body}</additionalAccessories>", xml_header(&xml))
    };
    set_plugin(to, MORE_ACCESSORIES, version, Value::Map(vec![("additionalAccessories".into(), result.into())]));
}

/// HairAccessoryCustomizer per slot (`SlotPlan`): her settings for the slots that stay, the outfit's for the slots it
/// moves into.
fn hair_accessories_slots(from: &Value, to: &mut Value, outfit: usize, plan: &SlotPlan) {
    let src = plugin_data(from, HAIR_ACCESSORIES);
    let had = plugin_data(to, HAIR_ACCESSORIES);
    let Some(version) = src.as_ref().map(|(v, _)| v.clone()).or_else(|| had.as_ref().map(|(v, _)| v.clone())) else { return };
    let incoming = src.and_then(|(_, d)| map_get(d, "CoordinateHairAccessories").map(unbin)).unwrap_or(Value::Nil);
    let mut dst = had.map(|(_, d)| d.clone()).unwrap_or(Value::Map(Vec::new()));
    let mut table = map_get(&dst, "HairAccessories").map(unbin).filter(|v| v.is_map()).unwrap_or(Value::Map(Vec::new()));
    let Value::Map(m) = &mut table else { return };
    let mut slots: Vec<(Value, Value)> = Vec::new();
    if let Some(i) = m.iter().position(|(k, _)| int_key(k) == Some(outfit as i64)) {
        let (_, hers) = m.remove(i);
        slots.extend(unbin(&hers).as_map().into_iter().flatten().filter(|(k, _)| int_key(k).is_some_and(|s| plan.keep.contains(&s))).cloned());
    }
    for (k, x) in incoming.as_map().into_iter().flatten() {
        if let Some(to) = int_key(k).and_then(|s| plan.take.get(&s)) { slots.push((Value::from(*to), x.clone())); }
    }
    if !slots.is_empty() { m.push((Value::from(outfit), Value::Map(slots))); }
    map_set(&mut dst, "HairAccessories", bin(&table));
    set_plugin(to, HAIR_ACCESSORIES, version, dst);
}

/// Accessory States per slot (`SlotPlan`): her outfit data with the slot info of the slots that stay, plus the outfit's
/// for the slots it moves into.
fn accessory_states_slots(from: &Value, to: &mut Value, outfit: usize, plan: &SlotPlan) {
    let src = plugin_data(from, ACCESSORY_STATES);
    let had = plugin_data(to, ACCESSORY_STATES);
    let Some(version) = src.as_ref().map(|(v, _)| v.clone()).or_else(|| had.as_ref().map(|(v, _)| v.clone())) else { return };
    let incoming = src.and_then(|(_, d)| map_get(d, "CoordinateData").map(unbin)).unwrap_or(Value::Nil);
    let mut dst = had.map(|(_, d)| d.clone()).unwrap_or(Value::Map(Vec::new()));
    let mut table = map_get(&dst, "CoordinateData").map(unbin).filter(|v| v.is_map()).unwrap_or(Value::Map(Vec::new()));
    let Value::Map(m) = &mut table else { return };
    let hers = m.iter().position(|(k, _)| int_key(k) == Some(outfit as i64)).map(|i| unbin(&m.remove(i).1));
    let Some(mut data) = hers.clone().or_else(|| (!incoming.is_nil()).then(|| incoming.clone())) else { return };
    let info = |v: &Value| map_get(v, "_slotinfo").map(unbin).and_then(|i| i.as_map().cloned()).unwrap_or_default();
    let mut slots: Vec<(Value, Value)> = hers.as_ref().map(info).unwrap_or_default().into_iter().filter(|(k, _)| int_key(k).is_some_and(|s| plan.keep.contains(&s))).collect();
    for (k, x) in info(&incoming) {
        if let Some(to) = int_key(&k).and_then(|s| plan.take.get(&s)) { slots.push((Value::from(*to), x)); }
    }
    map_set(&mut data, "_slotinfo", Value::Map(slots));
    m.push((Value::from(outfit), data));
    map_set(&mut dst, "CoordinateData", bin(&table));
    set_plugin(to, ACCESSORY_STATES, version, dst);
}

/// Lists whose entries name their outfit in a field (DynamicBoneEditor
/// `CoordinateIndex`, ASS `Coordinate`); `coordinate_value` is what a
/// coordinate card stores there.
/// Worn per slot (`SlotPlan`), an entry with a `Slot` follows its accessory: hers stay with the slots that stay, the
/// outfit's move with theirs.
fn indexed_lists(from: &Value, to: &mut Value, outfit: usize, wear: bool, key: &str, field: &str, coordinate_value: i64, acc: Accessories) {
    let Some((version, src)) = plugin_data(from, key) else { return };
    let src = src.clone();
    let mut dst = if wear { plugin_data(to, key).map(|(_, d)| d.clone()).unwrap_or(Value::Map(Vec::new())) } else { Value::Map(Vec::new()) };
    let lists: Vec<String> = src.as_map().map(|m| m.iter().filter_map(|(k, v)| {
        let k = k.as_str()?;
        unbin(v).as_array().filter(|a| a.is_empty() || a.iter().any(|e| map_get(e, field).is_some())).map(|_| k.to_owned())
    }).collect()).unwrap_or_default();
    let index = |e: &Value| map_get(e, field).and_then(int_key);
    let mut any = false;
    for list in lists {
        let incoming = map_get(&src, &list).map(unbin).and_then(|v| v.as_array().cloned()).unwrap_or_default();
        let mut out: Vec<Value> = if wear { map_get(&dst, &list).map(unbin).and_then(|v| v.as_array().cloned()).unwrap_or_default() } else { Vec::new() };
        let slot = |e: &Value| map_get(e, "Slot").and_then(int_key);
        if wear { out.retain(|e| index(e) != Some(outfit as i64) || slot(e).is_some_and(|s| acc.keeps(s))); }
        for mut e in incoming {
            // Worn: every entry of the coordinate whatever index it was saved with (DynamicBoneEditor keeps the outfit's,
            // as Material Editor does); ASS writes -1.
            if if wear { index(&e).is_none() } else { index(&e) != Some(outfit as i64) } { continue; }
            if let (true, Some(s)) = (wear, slot(&e)) {
                let Some(to) = acc.takes(s) else { continue };
                map_set(&mut e, "Slot", Value::from(to));
            }
            map_set(&mut e, field, Value::from(if wear { outfit as i64 } else { coordinate_value }));
            out.push(e);
        }
        any |= !out.is_empty();
        map_set(&mut dst, &list, bin(&Value::Array(out)));
    }
    if any || wear { set_plugin(to, key, version, dst); }
}

/// Sideloader migration info: a union of mod versions.
fn migration(from: &Value, to: &mut Value) {
    let Some((version, src)) = plugin_data(from, MIGRATION) else { return };
    let incoming = map_get(src, "Info").map(unbin).unwrap_or(Value::Nil);
    let mut dst = plugin_data(to, MIGRATION).map(|(_, d)| d.clone()).unwrap_or(Value::Map(Vec::new()));
    let mut table = map_get(&dst, "Info").map(unbin).filter(|v| v.is_map()).unwrap_or(Value::Map(Vec::new()));
    if let (Value::Map(t), Some(m)) = (&mut table, incoming.as_map()) {
        for (k, v) in m { if !t.iter().any(|(tk, _)| tk == k) { t.push((k.clone(), v.clone())); } }
    }
    map_set(&mut dst, "Info", bin(&table));
    set_plugin(to, MIGRATION, version, dst);
}

const HANDLED: [&str; 10] = [SIDELOADER, MATERIAL_EDITOR, OVERLAYS, PUSHUP, MORE_ACCESSORIES, DYNAMIC_BONES, MIGRATION, HAIR_ACCESSORIES, ACCESSORY_STATES, ACCESSORY_SWITCH];

/// Outfit-scoped plugin data, both directions (`wear` = coordinate -> character).
/// `acc`: whose accessories the worn outfit has (export: `Accessories::Outfit`). Per slot, the MoreAccessories document
/// is written by `wear_scoped`.
fn convert_plugins(from: &Value, to: &mut Value, outfit: usize, wear: bool, acc: Accessories) {
    sideloader(from, to, outfit, wear, acc);
    material_editor(from, to, outfit, wear, acc);
    per_outfit_maps(from, to, outfit, wear, OVERLAYS, &[("Overlays", "Overlays")]);
    per_outfit_maps(from, to, outfit, wear, PUSHUP, &[("PushupCoordinate_BraData", "Pushup_BraData"), ("PushupCoordinate_TopData", "Pushup_TopData")]);
    match acc {
        Accessories::Character => return,
        Accessories::Outfit => {
            per_outfit_maps(from, to, outfit, wear, HAIR_ACCESSORIES, &[("CoordinateHairAccessories", "HairAccessories")]);
            per_outfit_maps(from, to, outfit, wear, ACCESSORY_STATES, &[("CoordinateData", "CoordinateData")]);
            more_accessories(from, to, outfit, wear);
        }
        Accessories::Slots(plan) => {
            hair_accessories_slots(from, to, outfit, plan);
            accessory_states_slots(from, to, outfit, plan);
        }
    }
    indexed_lists(from, to, outfit, wear, DYNAMIC_BONES, "CoordinateIndex", 0, acc);
    indexed_lists(from, to, outfit, wear, ACCESSORY_SWITCH, "Coordinate", -1, acc);
}

/// Coordinate-level plugin data -> the character's, for outfit `outfit`.
fn wear_plugins(coordinate: &Value, character: &mut Value, outfit: usize, acc: Accessories) -> Vec<String> {
    convert_plugins(coordinate, character, outfit, true, acc);
    migration(coordinate, character);
    coordinate.as_map().map(|m| m.iter().filter_map(|(k, _)| k.as_str()).filter(|k| !HANDLED.contains(k)).map(str::to_owned).collect()).unwrap_or_default()
}

/// The character's plugin data for outfit `outfit` -> coordinate level.
fn export_plugins(character: &Value, outfit: usize) -> Value {
    let mut out = Value::Map(Vec::new());
    convert_plugins(character, &mut out, outfit, false, Accessories::Outfit);
    if let Some(m) = map_get(character, MIGRATION) { map_set(&mut out, MIGRATION, m.clone()); }
    out
}

// ------------------------------------------------------------ operations

/// A card's picture as a still PNG: its first image only (an APNG's other frames dropped) and none of the OK chunks
/// (an OK card's pack, answers and voice sat before IEND and went into the outfit's picture: 112 MB for Raiden).
pub fn still_picture(png: &[u8]) -> Result<Vec<u8>, String> {
    if png.len() < 8 || &png[..8] != b"\x89PNG\r\n\x1a\n" { return Err("not a PNG".into()); }
    let mut out = png[..8].to_vec();
    let mut pos = 8usize;
    while pos + 12 <= png.len() {
        let len = u32::from_be_bytes(png[pos..pos + 4].try_into().unwrap()) as usize;
        let end = pos.checked_add(12 + len).filter(|e| *e <= png.len()).ok_or("truncated PNG chunk")?;
        let kind = &png[pos + 4..pos + 8];
        let keep = !kind.starts_with(b"ok") && kind != b"acTL" && kind != b"fcTL" && kind != b"fdAT";
        if keep { out.extend_from_slice(&png[pos..end]); }
        if kind == b"IEND" { return Ok(out); }
        pos = end;
    }
    Err("missing PNG IEND".into())
}

impl OkClothes {
    pub fn to_bytes(&self, thumbnail: &[u8]) -> Result<Vec<u8>, String> {
        let thumbnail = &still_picture(thumbnail)?;
        let payload = encode(&Value::Map(vec![
            ("format".into(), "okclothes".into()), ("version".into(), 1.into()),
            ("name".into(), self.name.clone().into()), ("source".into(), self.source.clone().into()),
            ("coordinate".into(), Value::Binary(self.coordinate.clone())), ("plugins".into(), self.plugins.clone()),
            ("models".into(), Value::Array(self.models.iter().map(|m| m.clone().into()).collect())),
            ("dropped".into(), Value::Array(self.dropped.iter().map(|m| m.clone().into()).collect())),
        ]));
        // Thumbnail PNG only (no card trailer), plus the okCl chunk.
        let (iend, _) = crate::portable::png_snapshot(thumbnail)?;
        let mut out = thumbnail[..iend].to_vec();
        out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
        let mut chunk = CLOTHES_CHUNK.to_vec();
        chunk.extend_from_slice(&payload);
        out.extend_from_slice(&chunk);
        out.extend_from_slice(&crc32fast::hash(&chunk).to_be_bytes());
        for (kind, data) in [(crate::oklib::PACK_CHUNK, &self.pack), (crate::tree_answers::CHUNK, &self.answers)] {
            let Some(data) = data else { continue };
            out.extend_from_slice(&(data.len() as u32).to_be_bytes());
            let mut chunk = kind.to_vec();
            chunk.extend_from_slice(data);
            out.extend_from_slice(&chunk);
            out.extend_from_slice(&crc32fast::hash(&chunk).to_be_bytes());
        }
        out.extend_from_slice(&thumbnail[iend..iend + 12]);
        Ok(out)
    }
    pub fn from_bytes(bytes: &[u8]) -> Result<OkClothes, String> {
        if bytes.len() < 8 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" { return Err("not an okclothes PNG".into()); }
        let mut pos = 8usize;
        while pos + 12 <= bytes.len() {
            let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
            if &bytes[pos + 4..pos + 8] == CLOTHES_CHUNK {
                let v = decode(bytes.get(pos + 8..pos + 8 + len).ok_or("okCl truncated")?).ok_or("okCl decode")?;
                let s = |k: &str| map_get(&v, k).and_then(|x| x.as_str()).unwrap_or("").to_owned();
                let list = |k: &str| map_get(&v, k).and_then(|x| x.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect()).unwrap_or_default();
                return Ok(OkClothes {
                    name: s("name"), source: s("source"),
                    coordinate: map_get(&v, "coordinate").and_then(|x| x.as_slice()).ok_or("okCl coordinate missing")?.to_vec(),
                    plugins: map_get(&v, "plugins").cloned().unwrap_or(Value::Map(Vec::new())),
                    models: list("models"), dropped: list("dropped"),
                    pack: crate::oklib::png_chunk(bytes, crate::oklib::PACK_CHUNK).map(<[u8]>::to_vec),
                    answers: crate::oklib::png_chunk(bytes, crate::tree_answers::CHUNK).map(<[u8]>::to_vec),
                });
            }
            pos += 12 + len;
        }
        Err("no okCl chunk".into())
    }
}

/// Coordinate card -> okclothes (thumbnail = the card image).
pub fn import_coordinate(card: &[u8]) -> Result<(OkClothes, Vec<u8>), String> {
    let f = read_coordinate_file(card)?;
    let plugins = f.kkex.unwrap_or(Value::Map(Vec::new()));
    let dropped = plugins.as_map().map(|m| m.iter().filter_map(|(k, _)| k.as_str()).filter(|k| !HANDLED.contains(k)).map(str::to_owned).collect()).unwrap_or_default();
    Ok((OkClothes { name: f.name, source: "coordinate".into(), coordinate: f.data, plugins, models: Vec::new(), dropped, pack: None, answers: None }, f.png))
}

fn coordinate_entries(blocks: &std::collections::BTreeMap<String, Vec<u8>>) -> Result<Vec<Vec<u8>>, String> {
    let raw = blocks.get("Coordinate").ok_or("card has no Coordinate block")?;
    let v = decode(raw).ok_or("Coordinate decode")?;
    match v {
        Value::Array(a) => a.into_iter().map(|e| e.as_slice().map(|s| s.to_vec()).ok_or_else(|| "Coordinate entry".to_string())).collect(),
        Value::Binary(b) => Ok(vec![b]),
        _ => Err("Coordinate shape".into()),
    }
}

/// A character card's outfit -> okclothes (thumbnail = the card image).
pub fn export_outfit(card: &[u8], outfit: usize) -> Result<(OkClothes, Vec<u8>), String> {
    let blocks = crate::appearance::blocks_from_card(card)?;
    let entries = coordinate_entries(&blocks)?;
    let coordinate = entries.get(outfit).cloned().ok_or_else(|| format!("card has {} outfits", entries.len()))?;
    let kkex = card_kkex(card)?.unwrap_or(Value::Map(Vec::new()));
    let (iend, _) = crate::portable::png_snapshot(card)?;
    let name = format!("outfit{outfit}");
    // An OK card's own pack goes with the outfit: the third-party models of its clothes are only there.
    let pack = crate::oklib::png_chunk(card, crate::oklib::PACK_CHUNK).map(<[u8]>::to_vec);
    let answers = crate::oklib::png_chunk(card, crate::tree_answers::CHUNK).map(<[u8]>::to_vec);
    Ok((OkClothes { name, source: "character".into(), coordinate, plugins: export_plugins(&kkex, outfit), models: Vec::new(), dropped: Vec::new(), pack, answers },
        card[..iend + 12].to_vec()))
}

/// What of an okclothes a character wears.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum WearScope {
    /// Clothes, accessories and makeup: the game's coordinate load (hair made of accessories changes too).
    All,
    /// Clothes and the outfit's accessories, but her hair and head accessories (`is_head_accessory`) and makeup stay.
    KeepHair,
    /// Clothes only: all her accessories and makeup stay, as the maker loads a coordinate with accessories unticked.
    ClothesOnly,
}

impl WearScope {
    pub fn name(self) -> &'static str { match self { Self::All => "all", Self::KeepHair => "keep-hair", Self::ClothesOnly => "clothes-only" } }
}

/// Wear okclothes as outfit `outfit` of a character card (a new card).
pub fn wear(card: &[u8], clothes: &OkClothes, outfit: usize) -> Result<(Vec<u8>, Vec<String>), String> {
    wear_scoped(card, clothes, outfit, WearScope::All)
}

/// Only the clothes of okclothes worn as outfit `outfit`: the character keeps that outfit's accessories (hair made of
/// accessories among them) and makeup, as the game's maker loads a coordinate card with its accessories unticked.
pub fn wear_clothes_only(card: &[u8], clothes: &OkClothes, outfit: usize) -> Result<(Vec<u8>, Vec<String>), String> {
    wear_scoped(card, clothes, outfit, WearScope::ClothesOnly)
}

/// An accessory on the head (hair, ornaments, glasses, earrings, masks): what `WearScope::KeepHair` keeps hers. Hair
/// made of accessories hangs from head bones (Raiden's whole hair: `a_n_head`, not in HairAccessoryCustomizer), or is
/// marked as hair by HairAccessoryCustomizer wherever it hangs (`hair_accessory_slots`).
fn is_head_accessory(parent: &str) -> bool {
    parent.starts_with("a_n_hair") || parent.starts_with("a_n_head")
        || matches!(parent, "a_n_megane" | "a_n_earrings_L" | "a_n_earrings_R" | "a_n_nose" | "a_n_mouth")
}

/// One accessory slot: its ChaFileAccessory part (slots 0-19) or MoreAccessories element (slots 20 on).
#[derive(Clone)]
enum AccSlot { Part(Value), Xml(String) }

impl AccSlot {
    fn kind(&self) -> i64 {
        match self { Self::Part(p) => map_get(p, "type").and_then(int_key), Self::Xml(x) => xml_attr(x, "type").and_then(|t| t.parse().ok()) }.unwrap_or(120)
    }
    fn parent(&self) -> &str {
        match self { Self::Part(p) => map_get(p, "parentKey").and_then(|v| v.as_str()), Self::Xml(x) => xml_attr(x, "parentKey") }.unwrap_or("")
    }
}

/// Slots of an outfit: the first 20 parts (the rest of a longer array repeats MoreAccessories, which card.rs and the
/// game read instead), then the MoreAccessories elements.
fn acc_slots(parts: &[Value], xml: &[String]) -> Vec<AccSlot> {
    parts.iter().take(20).cloned().map(AccSlot::Part).chain(xml.iter().cloned().map(AccSlot::Xml)).collect()
}

/// The accessory section of a Coordinate entry ([i32][clothes][i32][accessories][makeup...]) decoded, and the bytes
/// after it.
fn accessory_section(entry: &[u8]) -> Option<(Value, &[u8])> {
    let (_, rest) = split_clothes(entry)?;
    let (accessories, after) = split_clothes(rest)?;
    Some((decode(&accessories[4..])?, after))
}

/// Worn per slot: her head accessories stay in their slots, the outfit's other accessories go in theirs, or in the
/// first free slot of the same kind (0-19 parts, 20 on MoreAccessories) when hers is there. Returns the plan, the new
/// parts (20), the new MoreAccessories elements and the outfit's slots that found no room.
fn plan_slots(hers: &[AccSlot], her_hair: &std::collections::HashSet<i64>, outfit: &[AccSlot], outfit_hair: &std::collections::HashSet<i64>, empty: &Value)
    -> (SlotPlan, Vec<Value>, Vec<String>, Vec<i64>) {
    let head = |s: &AccSlot, i: usize, hair: &std::collections::HashSet<i64>| s.kind() != 120 && (hair.contains(&(i as i64)) || is_head_accessory(s.parent()));
    let mut plan = SlotPlan::default();
    let mut result: Vec<Option<AccSlot>> = vec![None; hers.len().max(20)];
    for (i, s) in hers.iter().enumerate() {
        if head(s, i, her_hair) { result[i] = Some(s.clone()); plan.keep.insert(i as i64); }
    }
    let mut full = Vec::new();
    for (i, s) in outfit.iter().enumerate() {
        if s.kind() == 120 || head(s, i, outfit_hair) { continue; }
        let free = |r: &Vec<Option<AccSlot>>, j: usize| r.get(j).is_none_or(Option::is_none);
        let to = if free(&result, i) { Some(i) } else if i < 20 { (0..20).find(|&j| free(&result, j)) } else { (20..).find(|&j| free(&result, j)) };
        let Some(to) = to else { full.push(i as i64); continue };
        if to >= result.len() { result.resize(to + 1, None); }
        result[to] = Some(s.clone());
        plan.take.insert(i as i64, to as i64);
    }
    let parts = (0..20).map(|j| match &result[j] { Some(AccSlot::Part(p)) => p.clone(), _ => empty.clone() }).collect();
    let mut xml: Vec<String> = result.iter().skip(20).map(|s| match s { Some(AccSlot::Xml(x)) => x.clone(), _ => "<accessory type=\"120\" />".to_owned() }).collect();
    while xml.last().is_some_and(|x| xml_attr(x, "type") == Some("120")) { xml.pop(); }
    (plan, parts, xml, full)
}

/// The MoreAccessories elements of outfit `outfit` of a character (`coordinate`: a coordinate's own list).
fn xml_elements(kkex: &Value, outfit: usize, coordinate: bool) -> Vec<String> {
    let Some(xml) = plugin_data(kkex, MORE_ACCESSORIES).and_then(|(_, d)| map_get(d, "additionalAccessories").and_then(|v| v.as_str()).map(str::to_owned)) else { return Vec::new() };
    if coordinate { return xml_accessories(&xml_inner(&xml)); }
    xml_sets(&xml_inner(&xml)).into_iter().find(|(k, _)| *k == outfit as i64).map(|(_, set)| xml_accessories(&set)).unwrap_or_default()
}

/// `WearScope::KeepHair`: the outfit's clothes with her makeup, and the accessories per `plan_slots`.
fn wear_keep_hair(entry: &[u8], clothes: &OkClothes, kkex: &mut Value, outfit: usize) -> Result<(Vec<u8>, Vec<String>), String> {
    let (worn, _) = split_clothes(&clothes.coordinate).ok_or("okclothes coordinate shape")?;
    let (mut her_section, after) = accessory_section(entry).ok_or("card outfit shape")?;
    let (outfit_section, _) = accessory_section(&clothes.coordinate).ok_or("okclothes coordinate shape")?;
    let parts = |v: &Value| map_get(v, "parts").and_then(|p| p.as_array()).cloned().unwrap_or_default();
    let (her_parts, outfit_parts) = (parts(&her_section), parts(&outfit_section));
    let empty = her_parts.iter().chain(&outfit_parts).find(|p| map_get(p, "type").and_then(int_key) == Some(120)).cloned()
        .or_else(|| her_parts.first().cloned().map(|mut p| { map_set(&mut p, "type", 120.into()); map_set(&mut p, "id", 0.into()); map_set(&mut p, "parentKey", "".into()); p }))
        .ok_or("card outfit has no accessory parts")?;
    let hers = acc_slots(&her_parts, &xml_elements(kkex, outfit, false));
    let theirs = acc_slots(&outfit_parts, &xml_elements(&clothes.plugins, 0, true));
    let her_hair = hair_accessory_slots(kkex, false).remove(&(outfit as i64)).unwrap_or_default();
    let outfit_hair = hair_accessory_slots(&clothes.plugins, true).remove(&0).unwrap_or_default();
    let (plan, new_parts, xml, full) = plan_slots(&hers, &her_hair, &theirs, &outfit_hair, &empty);
    map_set(&mut her_section, "parts", Value::Array(new_parts));
    let section = encode(&her_section);
    let entry = [worn, &(section.len() as i32).to_le_bytes(), &section, after].concat();
    let mut dropped = wear_plugins(&clothes.plugins, kkex, outfit, Accessories::Slots(&plan));
    let version = plugin_data(&clothes.plugins, MORE_ACCESSORIES).map(|(v, _)| v).unwrap_or(Value::from(2));
    set_outfit_xml(kkex, outfit, &xml, version);
    if !full.is_empty() { dropped.push(format!("no free accessory slot for outfit slots {full:?}")); }
    Ok((entry, dropped))
}

/// A Coordinate entry's clothes section and the rest (accessories, makeup): [i32 length][clothes][the rest].
fn split_clothes(entry: &[u8]) -> Option<(&[u8], &[u8])> {
    let n = i32::from_le_bytes(entry.get(..4)?.try_into().ok()?);
    let end = 4usize.checked_add(usize::try_from(n).ok()?)?;
    (end <= entry.len()).then(|| entry.split_at(end))
}

fn wear_scoped(card: &[u8], clothes: &OkClothes, outfit: usize, scope: WearScope) -> Result<(Vec<u8>, Vec<String>), String> {
    let mut blocks = crate::appearance::blocks_from_card(card)?;
    let mut entries = coordinate_entries(&blocks)?;
    if outfit >= entries.len() { return Err(format!("card has {} outfits", entries.len())); }
    let mut kkex = card_kkex(card)?.unwrap_or(Value::Map(Vec::new()));
    let dropped = match scope {
        WearScope::All => {
            entries[outfit] = clothes.coordinate.clone();
            wear_plugins(&clothes.plugins, &mut kkex, outfit, Accessories::Outfit)
        }
        WearScope::ClothesOnly => {
            let (worn, _) = split_clothes(&clothes.coordinate).ok_or("okclothes coordinate shape")?;
            let (_, kept) = split_clothes(&entries[outfit]).ok_or("card outfit shape")?;
            entries[outfit] = [worn, kept].concat();
            wear_plugins(&clothes.plugins, &mut kkex, outfit, Accessories::Character)
        }
        WearScope::KeepHair => {
            let (entry, dropped) = wear_keep_hair(&entries[outfit], clothes, &mut kkex, outfit)?;
            entries[outfit] = entry;
            dropped
        }
    };
    blocks.insert("Coordinate".into(), encode(&Value::Array(entries.into_iter().map(Value::Binary).collect())));
    blocks.insert("KKEx".into(), encode(&kkex));
    Ok((crate::appearance::write_blocks(card, blocks)?, dropped))
}

// ------------------------------------------------- the outfit shown first

/// Worn clothes slots (ChaFileClothes.parts ids != 0) and accessories (type != 120) of a Coordinate entry, and whether
/// it has outdoor shoes (parts[8]).
fn outfit_extent(entry: &[u8]) -> Option<(usize, bool)> {
    let mut c = Cursor::new(entry);
    let mut section = || -> Option<Value> {
        let mut n = [0u8; 4];
        std::io::Read::read_exact(&mut c, &mut n).ok()?;
        let start = c.position() as usize;
        let end = start.checked_add(i32::from_le_bytes(n).max(0) as usize)?;
        c.set_position(end as u64);
        decode(entry.get(start..end)?)
    };
    let (clothes, accessories) = (section()?, section()?);
    let parts = |v: &Value| map_get(v, "parts").and_then(|p| p.as_array()).cloned().unwrap_or_default();
    let ids: Vec<i64> = parts(&clothes).iter().map(|p| map_get(p, "id").and_then(int_key).unwrap_or(0)).collect();
    let worn = ids.iter().filter(|&&id| id != 0).count()
        + parts(&accessories).iter().filter(|p| map_get(p, "type").and_then(int_key).is_some_and(|t| t != 120)).count();
    Some((worn, ids.get(8).is_some_and(|&id| id != 0)))
}

/// The outfit a character is shown in when only one is (OK card conversion, street, crowd: outfit 0). Outfit 0 unless
/// it has no outdoor shoes: then the outfit with outdoor shoes that wears the most (clothes and accessories), the lower
/// index on ties. Some cards keep the template school uniform (no shoes) in outfit 0 and the character's own outfit
/// elsewhere (the club outfit); `ChaFileStatus.coordinateType` does not say which, many cards save pajamas there.
pub fn shown_outfit(card: &[u8]) -> Result<usize, String> {
    let entries = coordinate_entries(&crate::appearance::blocks_from_card(card)?)?;
    let extents: Vec<Option<(usize, bool)>> = entries.iter().map(|e| outfit_extent(e)).collect();
    if extents.first().copied().flatten().is_none_or(|(_, shoes)| shoes) { return Ok(0); }
    Ok(extents.iter().enumerate().filter_map(|(i, e)| e.filter(|e| e.1).map(|e| (i, e.0)))
        .max_by(|a, b| a.1.cmp(&b.1).then(b.0.cmp(&a.0))).map(|(i, _)| i).unwrap_or(0))
}

/// ABMX `boneData`: ext 99 of [uncompressed length][LZ4 block] of the bone list; per-coordinate modifiers (lists longer
/// than one) have their entries `a` and `b` exchanged.
fn exchange_abmx(kkex: &mut Value, a: usize, b: usize) -> Result<(), String> {
    const ABMX: &str = "KKABMPlugin.ABMData";
    let Some((version, mut data)) = plugin_data(kkex, ABMX).map(|(v, d)| (v, d.clone())) else { return Ok(()) };
    let Some(raw) = map_get(&data, "boneData").and_then(|v| v.as_slice()).map(<[u8]>::to_vec) else { return Ok(()) };
    let Some(Value::Ext(99, payload)) = decode(&raw) else { return Err("ABMX boneData is not ext 99".into()) };
    let mut c = Cursor::new(&payload[..]);
    let length = rmpv::decode::read_value(&mut c).ok().and_then(|v| v.as_u64()).ok_or("ABMX boneData length")? as usize;
    let list = lz4_flex::block::decompress(&payload[c.position() as usize..], length).map_err(|e| format!("ABMX boneData: {e}"))?;
    let mut bones = decode(&list).ok_or("ABMX bone list decode")?;
    let mut changed = false;
    for bone in array_mut(&mut bones).ok_or("ABMX bone list shape")? {
        let coordinates = match bone { Value::Array(f) => f.get_mut(1), Value::Map(m) => m.iter_mut().find(|(k, _)| k.as_i64() == Some(1)).map(|(_, v)| v), _ => None };
        if let Some(Value::Array(c)) = coordinates { if c.len() > a.max(b) && c[a] != c[b] { c.swap(a, b); changed = true; } }
    }
    if !changed { return Ok(()); }
    let list = encode(&bones);
    let mut payload = encode(&Value::from(list.len() as u64));
    payload.extend(lz4_flex::block::compress(&list));
    map_set(&mut data, "boneData", Value::Binary(encode(&Value::Ext(99, payload))));
    set_plugin(kkex, ABMX, version, data);
    Ok(())
}

/// Outfit-scoped character plugin data of outfits `a` and `b` exchanged (the plugins `wear` converts, and ABMX).
fn exchange_plugins(kkex: &mut Value, a: usize, b: usize) -> Result<(), String> {
    let swap = |i: i64| if i == a as i64 { b as i64 } else if i == b as i64 { a as i64 } else { i };
    let (pa, pb) = (format!("outfit{a}."), format!("outfit{b}."));
    // Rewrites the binary-or-plain field `field` of plugin `key`'s data.
    fn edit(kkex: &mut Value, key: &str, field: &str, f: &dyn Fn(&mut Value)) {
        let Some((version, mut data)) = plugin_data(kkex, key).map(|(v, d)| (v, d.clone())) else { return };
        let Some(old) = map_get(&data, field).cloned() else { return };
        let binary = matches!(old, Value::Binary(_));
        let mut value = unbin(&old);
        f(&mut value);
        map_set(&mut data, field, if binary { bin(&value) } else { value });
        set_plugin(kkex, key, version, data);
    }
    let index_field = |field: &'static str, object_types: bool| move |list: &mut Value| {
        for e in array_mut(list).into_iter().flatten() {
            if object_types && !map_get(e, "ObjectType").and_then(int_key).is_some_and(|t| t == 1 || t == 2) { continue; }
            if let Some(i) = map_get(e, field).and_then(int_key) { map_set(e, field, Value::from(swap(i))); }
        }
    };
    edit(kkex, SIDELOADER, "info", &|list| for e in array_mut(list).into_iter().flatten() {
        let mut info = unbin(e);
        let Some(p) = map_get(&info, "Property").and_then(|p| p.as_str()).map(str::to_owned) else { continue };
        let p = if let Some(rest) = p.strip_prefix(&pa) { format!("{pb}{rest}") } else if let Some(rest) = p.strip_prefix(&pb) { format!("{pa}{rest}") } else { continue };
        map_set(&mut info, "Property", p.into());
        *e = if matches!(*e, Value::Binary(_)) { bin(&info) } else { info };
    });
    let lists: Vec<String> = plugin_data(kkex, MATERIAL_EDITOR).and_then(|(_, d)| d.as_map().map(|m| m.iter().filter_map(|(k, _)| k.as_str().filter(|k| k.ends_with("List")).map(str::to_owned)).collect())).unwrap_or_default();
    for list in lists { edit(kkex, MATERIAL_EDITOR, &list, &index_field("CoordinateIndex", true)); }
    for (key, field) in [(OVERLAYS, "Overlays"), (PUSHUP, "Pushup_BraData"), (PUSHUP, "Pushup_TopData"), (HAIR_ACCESSORIES, "HairAccessories"), (ACCESSORY_STATES, "CoordinateData")] {
        edit(kkex, key, field, &|table| if let Value::Map(m) = table { for (k, _) in m.iter_mut() { if let Some(i) = int_key(k) { *k = Value::from(swap(i)); } } });
    }
    for (key, field) in [(DYNAMIC_BONES, "CoordinateIndex"), (ACCESSORY_SWITCH, "Coordinate")] {
        let lists: Vec<String> = plugin_data(kkex, key).and_then(|(_, d)| d.as_map().map(|m| m.iter().filter_map(|(k, v)| k.as_str().filter(|_| unbin(v).as_array().is_some_and(|l| l.iter().any(|e| map_get(e, field).is_some()))).map(str::to_owned)).collect())).unwrap_or_default();
        for list in lists { edit(kkex, key, &list, &index_field(field, false)); }
    }
    edit(kkex, MORE_ACCESSORIES, "additionalAccessories", &|xml| if let Some(text) = xml.as_str() {
        let (ta, tb) = (format!("<accessorySet type=\"{a}\""), format!("<accessorySet type=\"{b}\""));
        *xml = text.replace(&ta, "\u{0}").replace(&tb, &ta).replace('\u{0}', &tb).into();
    });
    exchange_abmx(kkex, a, b)
}

/// The card with outfit `k` (`shown_outfit`) moved to outfit 0 and outfit 0 to `k`, plugin data following; None when
/// outfit 0 is already the one shown. Everything that opens one outfit opens outfit 0, so the OK card is made from this.
pub fn shown_outfit_first(card: &[u8]) -> Result<Option<(Vec<u8>, usize)>, String> {
    let k = shown_outfit(card)?;
    if k == 0 { return Ok(None); }
    let mut blocks = crate::appearance::blocks_from_card(card)?;
    let mut entries = coordinate_entries(&blocks)?;
    entries.swap(0, k);
    blocks.insert("Coordinate".into(), encode(&Value::Array(entries.into_iter().map(Value::Binary).collect())));
    if let Some(mut kkex) = card_kkex(card)? {
        exchange_plugins(&mut kkex, 0, k)?;
        blocks.insert("KKEx".into(), encode(&kkex));
    }
    if let Some(mut status) = blocks.get("Status").and_then(|s| decode(s)) {
        // The outfit saved as worn: 0 stays (now the shown one), `k` moves to 0 with its outfit, others keep theirs.
        if map_get(&status, "coordinateType").and_then(int_key) == Some(k as i64) {
            map_set(&mut status, "coordinateType", Value::from(0));
            blocks.insert("Status".into(), encode(&status));
        }
    }
    Ok(Some((crate::appearance::write_blocks(card, blocks)?, k)))
}

/// File operations shared by the CLI (`--oklib clothes-*`) and the editor (`ok_clothes_file`). Each returns a one-line
/// summary; unconverted plugin data is named in it.
pub mod file {
    use super::*;
    fn read(p: &Path) -> Result<Vec<u8>, String> { std::fs::read(p).map_err(|e| format!("{}: {e}", p.display())) }
    fn write(p: &Path, bytes: &[u8]) -> Result<(), String> { std::fs::write(p, bytes).map_err(|e| format!("{}: {e}", p.display())) }
    /// Coordinate card (【KoiKatuClothes】) -> .okclothes.
    pub fn import(coordinate: &Path, out: &Path) -> Result<String, String> {
        let original = read(coordinate)?;
        let (clothes, thumb) = import_coordinate(&original)?;
        let bytes = clothes.to_bytes(&thumb)?;
        let ratio = bytes.len() as f64 / original.len().max(1) as f64;
        if ratio > 1.10 { return Err(format!("okclothes is {:.1}% of the coordinate card (limit 110%)", ratio * 100.)); }
        write(out, &bytes)?;
        Ok(format!("import bytes={} ratio={ratio:.4} dropped={:?}", bytes.len(), clothes.dropped))
    }
    /// Outfit `outfit` of a character card -> .okclothes.
    pub fn export(card: &Path, outfit: usize, out: &Path) -> Result<String, String> {
        let (clothes, thumb) = export_outfit(&read(card)?, outfit)?;
        let bytes = clothes.to_bytes(&thumb)?;
        write(out, &bytes)?;
        Ok(format!("export outfit={outfit} bytes={} pack={}", bytes.len(), clothes.pack.as_ref().map_or(0, Vec::len)))
    }
    /// As `export`, with `thumbnail` (a PNG: the outfit as shown) as the file's picture instead of the card's.
    pub fn export_with_thumbnail(card: &Path, outfit: usize, thumbnail: &Path, out: &Path) -> Result<String, String> {
        let (clothes, thumb) = export_outfit(&read(card)?, outfit)?;
        let picture = read(thumbnail).ok().filter(|p| crate::portable::png_snapshot(p).is_ok()).unwrap_or(thumb);
        let bytes = clothes.to_bytes(&picture)?;
        write(out, &bytes)?;
        Ok(format!("export outfit={outfit} bytes={} pack={}", bytes.len(), clothes.pack.as_ref().map_or(0, Vec::len)))
    }
    /// .okclothes worn as outfit `outfit` of a character card, written as a new card.
    pub fn wear_file(card: &Path, okclothes: &Path, outfit: usize, out: &Path) -> Result<String, String> {
        let clothes = OkClothes::from_bytes(&read(okclothes)?)?;
        let (bytes, dropped) = wear(&read(card)?, &clothes, outfit)?;
        write(out, &bytes)?;
        Ok(format!("wear outfit={outfit} dropped={dropped:?}"))
    }
    /// .okclothes worn as outfit `outfit` of a character card, as the card reader and the editor wear it: an OK card
    /// gets the outfit's pack merged into its own and is sealed and made again (its answers, its pack and its models
    /// list cover the new clothes; `ok-extract.exe` does the sealing, one process per step); an original card wearing
    /// an outfit that carries a pack is made an OK card first (from its own zipmods), since the outfit's third-party
    /// models exist only in that pack. `scope`: what of the outfit she wears (`WearScope`). Returns a one-line summary.
    pub fn wear_into(lib: Option<&Path>, game: &Path, card: &Path, okclothes: &Path, outfit: usize, scope: WearScope, out: &Path) -> Result<String, String> {
        let clothes = OkClothes::from_bytes(&read(okclothes)?)?;
        let ok_card = crate::oklib::is_library_card(card);
        let needs_ok = ok_card || clothes.pack.is_some();
        let lib = if needs_ok { Some(lib.map(Path::to_owned).or_else(crate::oklib::configured_library).ok_or("OK base library not configured")?) } else { None };
        let base = if !ok_card && needs_ok {
            // Her own data made into an OK card first (the outfit's models come in its pack, hers from her zipmods).
            let (_, _, made, _) = crate::oklib::remake_ok_card(lib.as_deref().unwrap(), game, card)?;
            made
        } else { read(card)? };
        let (worn, dropped) = wear_scoped(&base, &clothes, outfit, scope)?;
        if !needs_ok {
            write(out, &worn)?;
            return Ok(format!("wear outfit={outfit} scope={} dropped={dropped:?}", scope.name()));
        }
        let lib = lib.unwrap();
        let merged = match &clothes.pack { Some(pack) => crate::oklib::merge_card_pack(&worn, pack)?, None => worn };
        // The outfit's answers with hers: recorded again from the shared library they would lose the outfit's
        // third-party mods (not in its tree). An outfit without answers (a game coordinate card): recorded again.
        let (merged, keep) = match (&clothes.answers, crate::oklib::png_chunk(&merged, crate::tree_answers::CHUNK).is_some()) {
            (Some(answers), true) => (crate::tree_answers::merge(&merged, answers)?, true),
            _ => (crate::cardbake::strip_answers(&merged).into_owned(), false),
        };
        let (sealed, sealing) = crate::oklib::seal_card_with(&lib, &merged, !keep)?;
        write(out, &sealed)?;
        let (digest, _, made, pack) = crate::oklib::remake_ok_card(&lib, game, out)?;
        write(out, &made)?;
        Ok(format!("wear outfit={outfit} scope={} dropped={dropped:?} sealed: {sealing}; digest {digest} pack={pack}", scope.name()))
    }
    /// Only the clothes of .okclothes worn as outfit `outfit` (her accessories kept), written as a new card.
    pub fn wear_clothes_only_file(card: &Path, okclothes: &Path, outfit: usize, out: &Path) -> Result<String, String> {
        let clothes = OkClothes::from_bytes(&read(okclothes)?)?;
        let (bytes, dropped) = wear_clothes_only(&read(card)?, &clothes, outfit)?;
        write(out, &bytes)?;
        Ok(format!("wear clothes only outfit={outfit} dropped={dropped:?}"))
    }
}

#[cfg(test)]
mod tests {
    /// R3-10: March 7th and Alice keep the template uniform (no shoes) in outfit 0 and their own outfit in 4.
    #[test]
    fn shown_outfit_first_exchanges_outfit_data() {
        for (name, shown) in [("[Card] March_7th_keiyuu.png", 4), ("Alice_keiyuu.png", 4)] {
            let path = &crate::test_support::game_path("/UserData/chara/female").join(name);
            let Ok(original) = std::fs::read(&path) else { continue };
            assert_eq!(super::shown_outfit(&original).unwrap(), shown, "{name}");
            let (swapped, k) = super::shown_outfit_first(&original).unwrap().unwrap();
            assert_eq!(k, shown);
            assert_eq!(super::shown_outfit(&swapped).unwrap(), 0, "{name}: worn first");
            for (from, to) in [(k, 0), (0, k), (1, 1)] {
                let a = crate::card::parse_card_bytes_mode(&original, from as i32, false).unwrap();
                let b = crate::card::parse_card_bytes_mode(&swapped, to as i32, false).unwrap();
                assert_eq!(a.clothes_ids, b.clothes_ids, "{name} {from}->{to}");
                assert_eq!(a.resolves.len(), b.resolves.len(), "{name} {from}->{to} resolves");
                assert_eq!(a.accessory.len(), b.accessory.len(), "{name} {from}->{to} accessories");
                for bone in &a.abm {
                    let other = b.abm.iter().find(|o| o.name == bone.name).unwrap();
                    assert_eq!(bone.for_coord(from), other.for_coord(to), "{name} ABMX {} {from}->{to}", bone.name);
                }
            }
        }
    }
}
