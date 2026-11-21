//! Breeding (配種): a child character card from two parents' cards.
//!
//! The child starts from one parent's card (the "base", drawn at random): her picture, outfits, accessories and the
//! plugin data that goes with them. Her body, face and hair (the card's `Custom` block: three msgpack maps, face, body
//! and hair) are mixed from both parents gene by gene:
//!
//! * shape sliders (`shapeValueFace`, `shapeValueBody`) each take their own point between the two parents' values, and
//!   now and then mutate a little past them;
//! * other numbers blend; colours (four floats) blend as one, and rarely shift;
//! * whole numbers (model ids: head, eyes, eyebrows, hair...) come from one parent: the hair from one parent as a whole
//!   (its parts were made together), the head with its skin, the eyes as a pair.
//!
//! A part from the other parent that is a mod part needs that parent's Sideloader entry: the child carries both
//! parents' face/body/hair entries (an entry only applies where the value is its `Slot`). The hair's Material Editor
//! rows follow the hair. Her name is put together from both names. An `okDn` chunk records the parents, the seed and
//! what came from whom; an `okId` chunk gives her her own identity. The same parents and seed give the same child.
//!
//! When either parent is an OK card the child is one too: both parents' packs and answers go into her card, which is
//! then sealed and made again (as an OK card wearing another card's outfit, `okclothes::file::wear_into`).

use rmpv::Value;
use std::collections::{BTreeMap, HashMap};
use std::io::Cursor;
use std::path::Path;

pub const DNA_CHUNK: &[u8; 4] = b"okDn";
const SIDELOADER: &str = "com.bepis.sideloader.universalautoresolver";
const MATERIAL_EDITOR: &str = "com.deathweasel.bepinex.materialeditor";
const HAIR_OBJECT: i64 = 3;

// ------------------------------------------------------------------ random

/// splitmix64: small, seedable, the same on every machine.
struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }
    fn unit(&mut self) -> f64 { (self.next() >> 11) as f64 / (1u64 << 53) as f64 }
    fn range(&mut self, lo: f64, hi: f64) -> f64 { lo + (hi - lo) * self.unit() }
    fn chance(&mut self, p: f64) -> bool { self.unit() < p }
    fn normal(&mut self) -> f64 {
        let (u, v) = (self.unit().max(1e-12), self.unit());
        (-2.0 * u.ln()).sqrt() * (std::f64::consts::TAU * v).cos()
    }
}

// --------------------------------------------------------------- msgpack

fn encode(v: &Value) -> Vec<u8> { let mut b = Vec::new(); let _ = rmpv::encode::write_value(&mut b, v); b }
fn decode(b: &[u8]) -> Option<Value> { rmpv::decode::read_value(&mut Cursor::new(b)).ok() }
fn map_get<'a>(v: &'a Value, key: &str) -> Option<&'a Value> { v.as_map()?.iter().find(|(k, _)| k.as_str() == Some(key)).map(|(_, v)| v) }
fn map_set(v: &mut Value, key: &str, value: Value) {
    if !v.is_map() { *v = Value::Map(Vec::new()); }
    let Value::Map(m) = v else { unreachable!() };
    match m.iter_mut().find(|(k, _)| k.as_str() == Some(key)) { Some((_, slot)) => *slot = value, None => m.push((key.into(), value)) }
}
fn unbin(v: &Value) -> Value { match v { Value::Binary(b) => decode(b).unwrap_or(Value::Nil), other => other.clone() } }
fn as_f64(v: &Value) -> Option<f64> { match v { Value::F32(x) => Some(*x as f64), Value::F64(x) => Some(*x), _ => None } }
fn like(v: &Value, x: f64) -> Value { if matches!(v, Value::F32(_)) { Value::F32(x as f32) } else { Value::F64(x) } }

/// The `Custom` block's sections: `[u32 length][msgpack]` repeated (face, body, hair), or one map holding the three.
enum Form { Prefixed, Single }
fn sections(raw: &[u8]) -> Result<(Vec<Value>, Form), String> {
    if let Some(v) = decode(raw) {
        if map_get(&v, "face").is_some() && encode(&v).len() == raw.len() {
            let parts = ["face", "body", "hair"].iter().map(|k| map_get(&v, k).cloned().ok_or("Custom section missing")).collect::<Result<Vec<_>, _>>()?;
            return Ok((parts, Form::Single));
        }
    }
    let mut out = Vec::new();
    let mut pos = 0usize;
    while pos < raw.len() {
        let n = u32::from_le_bytes(raw.get(pos..pos + 4).ok_or("Custom block cut short")?.try_into().unwrap()) as usize;
        pos += 4;
        out.push(decode(raw.get(pos..pos + n).ok_or("Custom block cut short")?).ok_or("Custom section is not msgpack")?);
        pos += n;
    }
    if out.len() < 3 { return Err(format!("Custom block has {} sections", out.len())); }
    Ok((out, Form::Prefixed))
}
fn write_sections(parts: &[Value], form: &Form) -> Vec<u8> {
    match form {
        Form::Single => encode(&Value::Map(["face", "body", "hair"].iter().zip(parts).map(|(k, v)| ((*k).into(), v.clone())).collect())),
        Form::Prefixed => parts.iter().flat_map(|v| { let b = encode(v); [(b.len() as u32).to_le_bytes().to_vec(), b].concat() }).collect(),
    }
}

// ------------------------------------------------------------------ genes

/// What the mixing decided: per group, whether the father's (`true`) or the mother's value was taken.
struct Mixer { rng: Rng, picks: BTreeMap<String, bool> }

/// The group a whole-number field belongs to: decided once for all of it.
fn group(section: &str, path: &str) -> String {
    let top = path.split(['.', '[']).next().unwrap_or(path);
    match (section, top) {
        ("hair", _) => "hair".into(),
        ("face", "headId" | "skinId" | "detailId") => "face.head".into(),
        ("body", "skinId" | "detailId") => "body.skin".into(),
        _ => format!("{section}.{top}"),
    }
}

impl Mixer {
    fn pick(&mut self, group: String) -> bool {
        let rng = &mut self.rng;
        *self.picks.entry(group).or_insert_with(|| rng.chance(0.5))
    }
    fn blend(&mut self, a: f64, b: f64, shape: bool) -> f64 {
        let w = if shape { self.rng.range(0.1, 0.9) } else { self.rng.range(0.25, 0.75) };
        let mut x = a + (b - a) * w;
        if shape {
            // A mutation now and then: past both parents a little, within the slider's extended range.
            if self.rng.chance(0.06) { x += self.rng.normal() * 0.12; }
            let (lo, hi) = (a.min(b) - 0.2, a.max(b) + 0.2);
            x = x.clamp(lo.max(-1.0), hi.min(2.0));
        }
        x
    }
    fn colour(&mut self, a: &[Value], b: &[Value]) -> Vec<Value> {
        let w = self.rng.range(0.2, 0.8);
        let shift = self.rng.chance(0.05);
        let jitter: Vec<f64> = (0..a.len()).map(|_| if shift { self.rng.normal() * 0.06 } else { 0.0 }).collect();
        a.iter().zip(b).enumerate().map(|(i, (x, y))| {
            let (p, q) = (as_f64(x).unwrap_or(0.0), as_f64(y).unwrap_or(0.0));
            let mut c = p + (q - p) * w;
            if i < 3 { c = (c + jitter[i]).clamp(0.0, 1.0); }
            like(x, c)
        }).collect()
    }
    /// `a` (the mother's) and `b` (the father's) mixed; the shape of `a` is kept where they differ.
    fn mix(&mut self, section: &str, path: &str, a: &Value, b: &Value) -> Value {
        match (a, b) {
            (Value::F32(_) | Value::F64(_), Value::F32(_) | Value::F64(_)) => {
                let shape = path.starts_with("shapeValue");
                like(a, self.blend(as_f64(a).unwrap(), as_f64(b).unwrap(), shape))
            }
            (Value::Map(ma), Value::Map(_)) => Value::Map(ma.iter().map(|(k, va)| {
                let key = k.as_str().unwrap_or("?");
                let sub = if path.is_empty() { key.to_owned() } else { format!("{path}.{key}") };
                let v = match map_get(b, key) { Some(vb) => self.mix(section, &sub, va, vb), None => va.clone() };
                (k.clone(), v)
            }).collect()),
            (Value::Array(xa), Value::Array(xb)) if xa.len() == xb.len() => {
                let floats = |x: &Vec<Value>| !x.is_empty() && x.iter().all(|v| as_f64(v).is_some());
                if xa.len() == 4 && floats(xa) && floats(xb) && path.to_ascii_lowercase().contains("color") {
                    Value::Array(self.colour(xa, xb))
                } else {
                    Value::Array(xa.iter().zip(xb).map(|(x, y)| self.mix(section, &format!("{path}[]"), x, y)).collect())
                }
            }
            _ => if a == b || !self.pick(group(section, path)) { a.clone() } else { b.clone() },
        }
    }
}

// ------------------------------------------------------------------ names

fn names(parameter: &Value) -> (String, String) {
    let s = |k: &str| map_get(parameter, k).and_then(|v| v.as_str()).unwrap_or("").to_owned();
    (s("lastname"), s("firstname"))
}
/// The front of one first name and the back of the other ("刻晴" + "雷電" -> "刻電").
fn child_first_name(a: &str, b: &str, rng: &mut Rng) -> String {
    let (a, b): (Vec<char>, Vec<char>) = (a.chars().collect(), b.chars().collect());
    if a.is_empty() || b.is_empty() { return if a.is_empty() { b } else { a }.into_iter().collect(); }
    let (first, second) = if rng.chance(0.5) { (a, b) } else { (b, a) };
    let head = first.len().div_ceil(2);
    let tail = second.len() / 2;
    let mut name: String = first[..head].iter().chain(&second[second.len() - tail..]).collect();
    if name.chars().count() < 2 { name = first.iter().chain(second.iter().take(1)).collect(); }
    name
}

// ----------------------------------------------------------------- plugins

/// The other parent's face/body/hair Sideloader entries added to the base's (an entry applies only where the value is
/// its `Slot`, so the parent whose part was not taken costs nothing); outfit entries stay the base's.
fn sideloader_union(base: &mut Value, other: &Value) {
    let entries = |v: &Value| -> Vec<Value> {
        map_get(v, SIDELOADER).and_then(|p| match p { Value::Array(a) if a.len() == 2 => Some(&a[1]), other => Some(other) })
            .and_then(|d| map_get(d, "info")).and_then(|i| i.as_array()).cloned().unwrap_or_default()
    };
    let key = |e: &Value| { let i = unbin(e); (map_get(&i, "Property").and_then(|p| p.as_str()).unwrap_or("").to_owned(), map_get(&i, "Slot").and_then(|s| s.as_i64()).unwrap_or(0)) };
    let mut info = entries(base);
    let had: Vec<(String, i64)> = info.iter().map(key).collect();
    for e in entries(other) {
        let k = key(&e);
        if k.0.starts_with("outfit") || had.contains(&k) { continue; }
        info.push(e);
    }
    let version = match map_get(base, SIDELOADER).or_else(|| map_get(other, SIDELOADER)) { Some(Value::Array(a)) if a.len() == 2 => a[0].clone(), _ => Value::from(0) };
    if info.is_empty() { return; }
    map_set(base, SIDELOADER, Value::Array(vec![version, Value::Map(vec![("info".into(), Value::Array(info))])]));
}

/// The hair's Material Editor rows (ObjectType 3) and their textures taken from `from` instead of the base's.
fn hair_material_rows(base: &mut Value, from: &Value) {
    let data = |v: &Value| map_get(v, MATERIAL_EDITOR).map(|p| match p { Value::Array(a) if a.len() == 2 => (a[0].clone(), a[1].clone()), other => (Value::from(0), other.clone()) });
    let (Some((version, mut dst)), src) = (data(base).or_else(|| data(from).map(|(v, _)| (v, Value::Map(Vec::new())))), data(from)) else { return };
    let src = src.map(|(_, d)| d).unwrap_or(Value::Map(Vec::new()));
    let hair = |e: &Value| map_get(e, "ObjectType").and_then(|t| t.as_i64()) == Some(HAIR_OBJECT);
    let src_tex = map_get(&src, "TextureDictionary").map(unbin).unwrap_or(Value::Nil);
    let mut dst_tex = map_get(&dst, "TextureDictionary").map(unbin).filter(|v| v.is_map()).unwrap_or(Value::Map(Vec::new()));
    let mut next = dst_tex.as_map().map(|m| m.iter().filter_map(|(k, _)| k.as_i64()).max().unwrap_or(-1) + 1).unwrap_or(0);
    let mut moved: HashMap<i64, i64> = HashMap::new();
    let lists: Vec<String> = [&dst, &src].iter().flat_map(|d| d.as_map().into_iter().flatten().filter_map(|(k, _)| k.as_str().filter(|k| k.ends_with("List")).map(str::to_owned))).collect::<std::collections::BTreeSet<_>>().into_iter().collect();
    for list in lists {
        let mut rows: Vec<Value> = map_get(&dst, &list).map(unbin).and_then(|v| v.as_array().cloned()).unwrap_or_default();
        rows.retain(|e| !hair(e));
        for mut e in map_get(&src, &list).map(unbin).and_then(|v| v.as_array().cloned()).unwrap_or_default() {
            if !hair(&e) { continue; }
            if let Some(id) = map_get(&e, "TexID").and_then(|t| t.as_i64()) {
                let new = *moved.entry(id).or_insert_with(|| {
                    let png = src_tex.as_map().and_then(|m| m.iter().find(|(k, _)| k.as_i64() == Some(id)).map(|(_, v)| v.clone()));
                    let n = next; next += 1;
                    if let (Some(png), Value::Map(m)) = (png, &mut dst_tex) { m.push((Value::from(n), png)); }
                    n
                });
                map_set(&mut e, "TexID", Value::from(new));
            }
            rows.push(e);
        }
        map_set(&mut dst, &list, Value::Binary(encode(&Value::Array(rows))));
    }
    map_set(&mut dst, "TextureDictionary", Value::Binary(encode(&dst_tex)));
    map_set(base, MATERIAL_EDITOR, Value::Array(vec![version, dst]));
}

// ------------------------------------------------------------------ chunks

fn chunks(bytes: &[u8]) -> Result<Vec<(usize, usize, [u8; 4])>, String> {
    if bytes.len() < 8 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" { return Err("not a PNG card".into()); }
    let mut out = Vec::new();
    let mut pos = 8usize;
    while pos + 12 <= bytes.len() {
        let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
        let end = pos.checked_add(12 + len).filter(|e| *e <= bytes.len()).ok_or("truncated PNG chunk")?;
        let kind: [u8; 4] = bytes[pos + 4..pos + 8].try_into().unwrap();
        out.push((pos, end, kind));
        if &kind == b"IEND" { return Ok(out); }
        pos = end;
    }
    Err("missing PNG IEND".into())
}
/// The card without chunks of these kinds.
fn without(bytes: &[u8], kinds: &[&[u8; 4]]) -> Result<Vec<u8>, String> {
    let list = chunks(bytes)?;
    let mut out = bytes[..8].to_vec();
    for (pos, end, kind) in &list {
        if &kind == &b"IEND" { out.extend_from_slice(&bytes[*pos..]); return Ok(out); }
        if !kinds.contains(&kind) { out.extend_from_slice(&bytes[*pos..*end]); }
    }
    Err("missing PNG IEND".into())
}

/// The card shown by another picture (a PNG: its first image): the card's `ok*` chunks and its card data stay.
pub fn repicture(card: &[u8], picture: &[u8]) -> Result<Vec<u8>, String> {
    let picture = crate::okclothes::still_picture(picture)?;
    let mut out = picture[..8].to_vec();
    for (pos, end, kind) in chunks(&picture)? { if &kind != b"IEND" { out.extend_from_slice(&picture[pos..end]); } }
    for (pos, end, kind) in chunks(card)? {
        if &kind == b"IEND" { out.extend_from_slice(&card[pos..]); return Ok(out); }
        if kind.starts_with(b"ok") { out.extend_from_slice(&card[pos..end]); }
    }
    Err("missing PNG IEND".into())
}

/// A parent as the okDn record names her.
fn parent_record(bytes: &[u8], file: &Path) -> serde_json::Value {
    let blocks = crate::appearance::blocks_from_card(bytes).unwrap_or_default();
    let (last, first) = blocks.get("Parameter").and_then(|p| decode(p)).map(|p| names(&p)).unwrap_or_default();
    let generation = crate::oklib::png_chunk(bytes, DNA_CHUNK).and_then(|d| serde_json::from_slice::<serde_json::Value>(d).ok()).and_then(|d| d["generation"].as_u64()).unwrap_or(0);
    serde_json::json!({ "id": crate::oklib::card_identity(bytes), "name": format!("{last} {first}").trim(), "file": file.file_name().map(|f| f.to_string_lossy().into_owned()), "generation": generation })
}

/// The child of `mother` and `father` (card bytes), from `seed`: the card (on the base parent's PNG and chunks, with
/// her own `okId` and an `okDn` record), which parent is the base (`true`: the father), and a one-line summary.
pub fn breed(mother: &[u8], father: &[u8], seed: u64, files: (&Path, &Path)) -> Result<(Vec<u8>, bool, String), String> {
    let mut mixer = Mixer { rng: Rng(seed ^ 0x6F6B_4272_6565_6421), picks: BTreeMap::new() };
    let (bm, bf) = (crate::appearance::blocks_from_card(mother)?, crate::appearance::blocks_from_card(father)?);
    let from_father = mixer.rng.chance(0.5);
    let (base_card, base, other) = if from_father { (father, &bf, &bm) } else { (mother, &bm, &bf) };
    let mut blocks = base.clone();

    // Body, face and hair.
    let (cm, form) = sections(bm.get("Custom").ok_or("mother: no Custom block")?)?;
    let (cf, _) = sections(bf.get("Custom").ok_or("father: no Custom block")?)?;
    let mut mixed: Vec<Value> = Vec::new();
    for (i, section) in ["face", "body", "hair"].iter().enumerate() { mixed.push(mixer.mix(section, "", &cm[i], &cf[i])); }
    mixed.extend(cm.iter().skip(3).cloned());
    blocks.insert("Custom".into(), write_sections(&mixed, &form));

    // Her name, and the rest of the parameters mixed as the body is.
    let (pm, pf) = (bm.get("Parameter").and_then(|p| decode(p)).ok_or("mother: no Parameter")?, bf.get("Parameter").and_then(|p| decode(p)).ok_or("father: no Parameter")?);
    let ((lm, fm), (lf, ff)) = (names(&pm), names(&pf));
    let mut parameter = mixer.mix("parameter", "", &pm, &pf);
    let first = child_first_name(&fm, &ff, &mut mixer.rng);
    let last = if from_father { lf.clone() } else { lm.clone() };
    map_set(&mut parameter, "firstname", first.clone().into());
    map_set(&mut parameter, "lastname", last.clone().into());
    map_set(&mut parameter, "nickname", first.clone().into());
    map_set(&mut parameter, "sex", map_get(&pm, "sex").cloned().unwrap_or(Value::from(1)));
    blocks.insert("Parameter".into(), encode(&parameter));

    // Plugin data: the base's, with the other parent's face/body/hair mod entries, and the hair's materials.
    let hair_from_father = mixer.picks.get("hair").copied().unwrap_or(false);
    let mut kkex = base.get("KKEx").and_then(|k| decode(k)).unwrap_or(Value::Map(Vec::new()));
    let other_kkex = other.get("KKEx").and_then(|k| decode(k)).unwrap_or(Value::Map(Vec::new()));
    sideloader_union(&mut kkex, &other_kkex);
    if hair_from_father != from_father { hair_material_rows(&mut kkex, &other_kkex); }
    blocks.insert("KKEx".into(), encode(&kkex));

    // Her own identity: from her parents and the seed (the same child is the same person).
    let (rm, rf) = (parent_record(mother, files.0), parent_record(father, files.1));
    let id = {
        use sha2::Digest;
        let text = format!("ok-breed:{}:{}:{seed}", rm["id"].as_str().unwrap_or(""), rf["id"].as_str().unwrap_or(""));
        sha2::Sha256::digest(text.as_bytes()).iter().map(|b| format!("{b:02x}")).collect::<String>()
    };
    // A KKS card's own id (ChaFileAbout.dataID) is hers, not the base parent's.
    if let Some(mut about) = blocks.get("About").and_then(|a| decode(a)) {
        if map_get(&about, "dataID").is_some() {
            let guid = format!("{}-{}-{}-{}-{}", &id[0..8], &id[8..12], &id[12..16], &id[16..20], &id[20..32]);
            map_set(&mut about, "dataID", guid.into());
            blocks.insert("About".into(), encode(&about));
        }
    }

    let card = crate::appearance::write_blocks(base_card, blocks)?;
    let card = without(&card, &[crate::oklib::IDENTITY_CHUNK, b"okVo", b"okPv", DNA_CHUNK])?;
    let card = crate::oklib::with_card_identity(&card, &id)?;
    let side = |b: bool| if b { "father" } else { "mother" };
    let generation = rm["generation"].as_u64().unwrap_or(0).max(rf["generation"].as_u64().unwrap_or(0)) + 1;
    let record = serde_json::json!({
        "format": "ok-breed", "version": 1, "seed": seed, "generation": generation, "mother": rm, "father": rf,
        "base": side(from_father), "picks": mixer.picks.iter().map(|(k, v)| (k.clone(), side(*v))).collect::<BTreeMap<_, _>>(),
    });
    let card = crate::tree_answers::with_chunk(&card, DNA_CHUNK, &serde_json::to_vec(&record).unwrap())?;
    let summary = format!("child {last} {first} (generation {generation}, seed {seed}, outfits from the {}, hair from the {})", side(from_father), side(hair_from_father));
    Ok((card, from_father, summary.replace("  ", " ")))
}

/// File operations for the CLI (`--oklib breed`) and the reader (`ok_breed_file`).
pub mod file {
    use super::*;
    fn read(p: &Path) -> Result<Vec<u8>, String> { std::fs::read(p).map_err(|e| format!("{}: {e}", p.display())) }
    fn write(p: &Path, bytes: &[u8]) -> Result<(), String> {
        if let Some(dir) = p.parent() { let _ = std::fs::create_dir_all(dir); }
        std::fs::write(p, bytes).map_err(|e| format!("{}: {e}", p.display()))
    }

    /// The child of the cards `mother` and `father` written to `out`. An OK card parent makes her an OK card: a parent
    /// that is not one is made one first (from the game's zipmods), both packs and answers go into her card, and it is
    /// sealed and made again so it opens from her own data and the shared library alone.
    pub fn breed_into(lib: Option<&Path>, game: &Path, mother: &Path, father: &Path, seed: u64, out: &Path) -> Result<String, String> {
        let ok = (crate::oklib::is_library_card(mother), crate::oklib::is_library_card(father));
        let needs_ok = ok.0 || ok.1;
        let lib = if needs_ok { Some(lib.map(Path::to_owned).or_else(crate::oklib::configured_library).ok_or("OK base library not configured")?) } else { None };
        let parent = |path: &Path, is_ok: bool| -> Result<Vec<u8>, String> {
            if needs_ok && !is_ok { let (_, _, made, _) = crate::oklib::remake_ok_card(lib.as_deref().unwrap(), game, path)?; Ok(made) } else { read(path) }
        };
        let (m, f) = (parent(mother, ok.0)?, parent(father, ok.1)?);
        let (child, from_father, summary) = breed(&m, &f, seed, (mother, father))?;
        let Some(lib) = lib else { write(out, &child)?; return Ok(summary); };
        let other = if from_father { &m } else { &f };
        let merged = match crate::oklib::png_chunk(other, crate::oklib::PACK_CHUNK) { Some(pack) => crate::oklib::merge_card_pack(&child, pack)?, None => child };
        // Both parents' answers (her questions ask about both): recorded again from the shared library they would lose
        // the third-party mods of the parent whose pack is not the base's.
        let (merged, keep) = match (crate::oklib::png_chunk(other, crate::tree_answers::CHUNK), crate::oklib::png_chunk(&merged, crate::tree_answers::CHUNK).is_some()) {
            (Some(answers), true) => (crate::tree_answers::merge(&merged, answers)?, true),
            _ => (crate::cardbake::strip_answers(&merged).into_owned(), false),
        };
        let (sealed, sealing) = crate::oklib::seal_card_with(&lib, &merged, !keep)?;
        write(out, &sealed)?;
        let (digest, _, made, pack) = crate::oklib::remake_ok_card(&lib, game, out)?;
        write(out, &made)?;
        Ok(format!("{summary}; sealed: {sealing}; digest {digest} pack={pack}"))
    }

    /// `card` shown by `picture` (a PNG), written to `out` (may be `card`).
    pub fn repicture_into(card: &Path, picture: &Path, out: &Path) -> Result<String, String> {
        let made = repicture(&read(card)?, &read(picture)?)?;
        write(out, &made)?;
        Ok(format!("picture {} bytes", made.len()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixing_is_repeatable_and_between_the_parents() {
        let face = |v: f32| Value::Map(vec![("shapeValueFace".into(), Value::Array((0..52).map(|_| Value::F32(v)).collect())), ("headId".into(), Value::from(if v < 0.5 { 1 } else { 2 }))]);
        let run = |seed| { let mut m = Mixer { rng: Rng(seed), picks: BTreeMap::new() }; m.mix("face", "", &face(0.2), &face(0.8)) };
        assert_eq!(run(7), run(7));
        let child = run(7);
        let values: Vec<f64> = map_get(&child, "shapeValueFace").unwrap().as_array().unwrap().iter().map(|v| as_f64(v).unwrap()).collect();
        assert!(values.iter().all(|v| (0.0..=1.0).contains(v)), "{values:?}");
        assert!(values.iter().any(|v| (v - 0.2).abs() > 1e-3 && (v - 0.8).abs() > 1e-3));
        assert!(matches!(map_get(&child, "headId").and_then(|v| v.as_i64()), Some(1 | 2)));
    }

    #[test]
    fn colours_blend_as_one() {
        let mut m = Mixer { rng: Rng(3), picks: BTreeMap::new() };
        let c = |r: f32| Value::Array(vec![Value::F32(r), Value::F32(r), Value::F32(r), Value::F32(1.0)]);
        let out = m.mix("hair", "baseColor", &c(0.0), &c(1.0));
        let v: Vec<f64> = out.as_array().unwrap().iter().map(|v| as_f64(v).unwrap()).collect();
        assert!((v[0] - v[1]).abs() < 0.2 && (v[1] - v[2]).abs() < 0.2 && v[3] == 1.0, "{v:?}");
    }

    #[test]
    fn names_mix() {
        let mut rng = Rng(1);
        let n = child_first_name("刻晴", "雷電", &mut rng);
        assert_eq!(n.chars().count(), 2);
        assert!(["刻電", "雷晴"].contains(&n.as_str()), "{n}");
    }
}
