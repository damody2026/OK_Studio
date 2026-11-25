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

/// What the mixing decided: per group, whether the father's (`true`) or the mother's value was taken; per whole-number
/// field ("face.pupil.0.id"), whose value it has (None: both had it).
struct Mixer { rng: Rng, picks: BTreeMap<String, bool>, sources: BTreeMap<String, Option<bool>>, forced: BTreeMap<String, bool>,
    /// Groups (`group`) whose parent is settled before the draw: the hair of a parent whose own hairstyle cannot be
    /// shown is no hair at all, so it comes from the other one (`file::breed_whole`).
    groups: BTreeMap<String, bool> }

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
        if let Some(&picked) = self.picks.get(&group) { return picked; }
        let settled = self.groups.get(&group).copied();
        // (drawn even for a settled group, exactly once per group as before: the seed's later genes must not move)
        let drawn = self.rng.chance(0.5);
        *self.picks.entry(group).or_insert(settled.unwrap_or(drawn))
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
    /// A colour between the parents'. Hair colours mix in HSV (the user, 2026-11-22: 髮色要用 HSV 混，才不會愈混愈黑):
    /// RGB halfway between two saturated colours is greyer and darker, and generations of it went black.
    fn colour(&mut self, a: &[Value], b: &[Value], hsv: bool) -> Vec<Value> {
        let w = self.rng.range(0.2, 0.8);
        let shift = self.rng.chance(0.05);
        let jitter: Vec<f64> = (0..a.len()).map(|_| if shift { self.rng.normal() * 0.06 } else { 0.0 }).collect();
        let f = |v: &[Value], i: usize| v.get(i).and_then(as_f64).unwrap_or(0.0);
        let rgb = (hsv && a.len() >= 3 && b.len() >= 3).then(|| hsv_mix([f(a, 0), f(a, 1), f(a, 2)], [f(b, 0), f(b, 1), f(b, 2)], w));
        a.iter().zip(b).enumerate().map(|(i, (x, y))| {
            let (p, q) = (as_f64(x).unwrap_or(0.0), as_f64(y).unwrap_or(0.0));
            let mut c = match rgb { Some(m) if i < 3 => m[i], _ => p + (q - p) * w };
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
                    Value::Array(self.colour(xa, xb, section == "hair"))
                } else {
                    Value::Array(xa.iter().zip(xb).enumerate().map(|(i, (x, y))| self.mix(section, &format!("{path}.{i}"), x, y)).collect())
                }
            }
            _ => {
                let mut father = a != b && self.pick(group(section, path));
                // (a gene her parents' data could not show, taken from the other parent: ile::breed_whole)
                if a != b { if let Some(f) = self.forced.get(&format!("{section}.{path}")) { father = *f; } }
                self.sources.insert(format!("{section}.{path}"), (a != b).then_some(father));
                if father { b.clone() } else { a.clone() }
            }
        }
    }
}

fn rgb_to_hsv([r, g, b]: [f64; 3]) -> [f64; 3] {
    let (mx, mn) = (r.max(g).max(b), r.min(g).min(b));
    let d = mx - mn;
    let h = if d <= 1e-9 { 0.0 } else if mx == r { ((g - b) / d).rem_euclid(6.0) / 6.0 } else if mx == g { ((b - r) / d + 2.0) / 6.0 } else { ((r - g) / d + 4.0) / 6.0 };
    [h, if mx <= 1e-9 { 0.0 } else { d / mx }, mx]
}
fn hsv_to_rgb([h, s, v]: [f64; 3]) -> [f64; 3] {
    let h6 = h.rem_euclid(1.0) * 6.0;
    let (i, f) = (h6.floor(), h6 - h6.floor());
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - s * f), v * (1.0 - s * (1.0 - f)));
    match i as i32 { 0 => [v, t, p], 1 => [q, v, p], 2 => [p, v, t], 3 => [p, q, v], 4 => [t, p, v], _ => [v, p, q] }
}
/// `a` to `b` by `w` in HSV: hue the short way round (a near-grey colour has no hue: the other's is taken), saturation
/// and value straight.
fn hsv_mix(a: [f64; 3], b: [f64; 3], w: f64) -> [f64; 3] {
    let (x, y) = (rgb_to_hsv(a), rgb_to_hsv(b));
    let (hx, hy) = (if x[1] < 0.05 { y[0] } else { x[0] }, if y[1] < 0.05 { x[0] } else { y[0] });
    let mut dh = hy - hx;
    if dh > 0.5 { dh -= 1.0; } else if dh < -0.5 { dh += 1.0; }
    hsv_to_rgb([hx + dh * w, x[1] + (y[1] - x[1]) * w, x[2] + (y[2] - x[2]) * w])
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

/// A field of the mixed `Custom` sections by section and path ("face", "pupil.0.id").
fn custom_value<'a>(custom: &'a [Value], section: &str, path: &str) -> Option<&'a Value> {
    let mut v = &custom[["face", "body", "hair"].iter().position(|s| *s == section)?];
    for part in path.split('.') {
        v = match part.parse::<usize>() { Ok(i) => v.as_array()?.get(i)?, Err(_) => map_get(v, part)? };
    }
    Some(v)
}

/// The child's Sideloader entries (an entry applies where the field's value is its `Slot`). A face/body/hair entry is
/// kept when the child's value is its slot and comes from the parent who had it (both parents having the value: the
/// base's entry, else the other's); an entry of a value she does not have is dropped. Kept, a parent's entry whose slot
/// the other parent's value happened to equal (a mod's slot and an original id alike) gave her a mod part neither parent
/// wore, and her strict open asked about it (an eye highlight, cat 410 1919, 2026-11-22). Outfit entries are the base's,
/// those of clothes she took from the other parent (`outfit_from_other`) the other's.
fn sideloader_select(base: &mut Value, other: &Value, base_is_father: bool, custom: &[Value], sources: &BTreeMap<String, Option<bool>>,
    outfit_from_other: &dyn Fn(&str) -> bool) {
    let entries = |v: &Value| -> Vec<Value> {
        map_get(v, SIDELOADER).and_then(|p| match p { Value::Array(a) if a.len() == 2 => Some(&a[1]), other => Some(other) })
            .and_then(|d| map_get(d, "info")).and_then(|i| i.as_array()).cloned().unwrap_or_default()
    };
    let key = |e: &Value| { let i = unbin(e); (map_get(&i, "Property").and_then(|p| p.as_str()).unwrap_or("").to_owned(), map_get(&i, "Slot").and_then(|s| s.as_i64()).unwrap_or(0)) };
    let mut info: Vec<Value> = Vec::new();
    let mut had: Vec<(String, i64)> = Vec::new();
    for (e, from_base) in entries(base).into_iter().map(|e| (e, true)).chain(entries(other).into_iter().map(|e| (e, false))) {
        let k = key(&e);
        if had.contains(&k) { continue; }
        // Outfit entries are the base's, but for the clothes she took from the other parent (`mix_clothes`).
        if k.0.starts_with("outfit") { if from_base == outfit_from_other(&k.0) { continue; } }
        else if let Some((section, path)) = crate::appearance::custom_field_of_property(&k.0) {
            if custom_value(custom, &section, &path).and_then(|v| v.as_i64()) != Some(k.1) { continue; }
            let from_father = if from_base { base_is_father } else { !base_is_father };
            if let Some(Some(source)) = sources.get(&format!("{section}.{path}")) { if *source != from_father { continue; } }
        }
        had.push(k);
        info.push(e);
    }
    let version = match map_get(base, SIDELOADER).or_else(|| map_get(other, SIDELOADER)) { Some(Value::Array(a)) if a.len() == 2 => a[0].clone(), _ => Value::from(0) };
    if info.is_empty() {
        if let Value::Map(m) = base { m.retain(|(k, _)| k.as_str() != Some(SIDELOADER)); }
        return;
    }
    map_set(base, SIDELOADER, Value::Array(vec![version, Value::Map(vec![("info".into(), Value::Array(info))])]));
}

/// The hair's Material Editor rows (ObjectType 3) and their textures taken from `from` instead of the base's.
fn hair_material_rows(base: &mut Value, from: &Value) {
    material_rows(base, from, &|e: &Value| map_get(e, "ObjectType").and_then(|t| t.as_i64()) == Some(HAIR_OBJECT));
}

/// The Material Editor rows `take` picks (and their textures) taken from `from` instead of the base's.
fn material_rows(base: &mut Value, from: &Value, take: &dyn Fn(&Value) -> bool) {
    let data = |v: &Value| map_get(v, MATERIAL_EDITOR).map(|p| match p { Value::Array(a) if a.len() == 2 => (a[0].clone(), a[1].clone()), other => (Value::from(0), other.clone()) });
    let (Some((version, mut dst)), src) = (data(base).or_else(|| data(from).map(|(v, _)| (v, Value::Map(Vec::new())))), data(from)) else { return };
    let src = src.map(|(_, d)| d).unwrap_or(Value::Map(Vec::new()));
    let hair = take;
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

// ------------------------------------------------------------------ clothes mixed between the parents

/// A piece of clothing that goes from one parent as a whole: its gene name, its `ChaFileClothes.parts` slots (the
/// Material Editor clothing slots too), the Sideloader properties after `outfitN.ChaFileClothes.` (prefixes: a piece's
/// pattern and emblem entries go with it), and whether the top's sub parts (sailor, jacket) go with it.
type ClothesGene = (&'static str, &'static [usize], &'static [&'static str], bool);
const CLOTHES_GENES: [ClothesGene; 3] = [
    ("top", &[0], &["ClothesTop", "ClothesSailorSub", "ClothesJacketSub"], true),
    ("bottom", &[1], &["ClothesBot"], false),
    ("underwear", &[2, 3], &["ClothesBra", "ClothesShorts"], false),
];

/// A Coordinate entry's clothes (decoded) and the rest of it: [i32 length][clothes msgpack][accessories, makeup].
fn split_coordinate(entry: &[u8]) -> Option<(Value, Vec<u8>)> {
    let n = i32::from_le_bytes(entry.get(..4)?.try_into().ok()?);
    let end = 4usize.checked_add(usize::try_from(n).ok()?)?;
    Some((decode(entry.get(4..end)?)?, entry.get(end..)?.to_vec()))
}
fn join_coordinate(clothes: &Value, rest: &[u8]) -> Vec<u8> {
    let c = encode(clothes);
    let mut out = (c.len() as i32).to_le_bytes().to_vec();
    out.extend(c);
    out.extend_from_slice(rest);
    out
}
fn coordinate_entries(blocks: &BTreeMap<String, Vec<u8>>) -> Vec<Vec<u8>> {
    blocks.get("Coordinate").and_then(|b| decode(b)).and_then(|v| v.as_array().cloned()).unwrap_or_default()
        .into_iter().filter_map(|e| match e { Value::Binary(b) => Some(b), _ => None }).collect()
}
fn clothes_parts(clothes: &Value) -> Vec<Value> { map_get(clothes, "parts").and_then(|p| p.as_array()).cloned().unwrap_or_default() }
fn wears(clothes: &Value, slot: usize) -> bool {
    clothes_parts(clothes).get(slot).and_then(|p| map_get(p, "id")).and_then(|i| i.as_i64()).is_some_and(|i| i != 0)
}

/// Her top, bottom and underwear each from either parent (user, 2026-11-22: 上衣 下衣 內衣混搭); the rest of every
/// outfit (gloves, pantyhose, socks, shoes, accessories) is the base's. Each gene is drawn once and worn in every outfit
/// both parents have where the other parent wears that piece (taking nothing would undress her). The pieces keep their
/// colours and patterns (they are in the parts entry); their Sideloader and Material Editor entries go with them
/// (`sideloader_select`, `material_rows`). Returns the (outfit, gene) taken from the other parent.
fn mix_clothes(blocks: &mut BTreeMap<String, Vec<u8>>, other: &BTreeMap<String, Vec<u8>>, from_father: bool, mixer: &mut Mixer, unmixed: &[usize]) -> Vec<(usize, ClothesGene)> {
    let draws: Vec<bool> = CLOTHES_GENES.iter().map(|_| mixer.rng.chance(0.5)).collect();
    let (mut mine, theirs) = (coordinate_entries(blocks), coordinate_entries(other));
    let mut taken = Vec::new();
    for (o, entry) in mine.iter_mut().enumerate() {
        let Some(their) = theirs.get(o) else { break };
        if unmixed.contains(&o) { continue; }
        let (Some((mut clothes, rest)), Some((their_clothes, _))) = (split_coordinate(entry), split_coordinate(their)) else { continue };
        let mut changed = false;
        for (gene, take) in CLOTHES_GENES.iter().zip(&draws) {
            if !*take || !gene.1.iter().any(|s| wears(&their_clothes, *s)) { continue; }
            let (mut parts, from) = (clothes_parts(&clothes), clothes_parts(&their_clothes));
            for s in gene.1 { if let (Some(d), Some(v)) = (parts.get_mut(*s), from.get(*s)) { *d = v.clone(); } }
            map_set(&mut clothes, "parts", Value::Array(parts));
            if gene.3 { if let Some(v) = map_get(&their_clothes, "subPartsId").cloned() { map_set(&mut clothes, "subPartsId", v); } }
            taken.push((o, *gene));
            changed = true;
        }
        if changed { *entry = join_coordinate(&clothes, &rest); }
    }
    for (gene, take) in CLOTHES_GENES.iter().zip(&draws) {
        let applied = *take && taken.iter().any(|(_, g)| g.0 == gene.0);
        mixer.picks.insert(gene.0.into(), if applied { !from_father } else { from_father });
    }
    if !taken.is_empty() { blocks.insert("Coordinate".into(), encode(&Value::Array(mine.into_iter().map(Value::Binary).collect()))); }
    taken
}

/// Her lower body covered where mixing left it bare (the user, 2026-11-22: 下體沒穿就補上裙子): an outfit with a top
/// and no bottom gets the bottom the top's parent wore in that outfit, else the other parent's. Only when neither wore
/// one does she stay as she is. (A parent who wore that top without a bottom is no sign it covers her: Raiden's bunny
/// suit is open in front, and her children showed only underwear.) Hers, not one of the
/// game's skirts: a garment neither parent wore asks the sealed open questions neither parent's data answers (the
/// game's プリーツスカートA: skel:bone_implants of co_bot_00), and the outfit went back to the base parent's whole.
/// Returns the (outfit, bottom gene) taken from the other parent, for her Sideloader and Material Editor entries.
fn cover_bare_outfits(blocks: &mut BTreeMap<String, Vec<u8>>, base: &BTreeMap<String, Vec<u8>>, other: &BTreeMap<String, Vec<u8>>,
    taken: &[(usize, ClothesGene)]) -> Vec<(usize, ClothesGene)> {
    let (mut mine, base_c, other_c) = (coordinate_entries(blocks), coordinate_entries(base), coordinate_entries(other));
    let mut out = Vec::new();
    for (o, entry) in mine.iter_mut().enumerate() {
        let Some((mut clothes, rest)) = split_coordinate(entry) else { continue };
        if wears(&clothes, 1) || !wears(&clothes, 0) { continue; }
        let top_from_other = taken.iter().any(|(t, g)| *t == o && g.0 == "top");
        let side = |from_other: bool| (if from_other { other_c.get(o) } else { base_c.get(o) }).and_then(|e| split_coordinate(e)).map(|(c, _)| c).filter(|c| wears(c, 1));
        let Some((source, from_other)) = side(top_from_other).map(|c| (c, top_from_other)).or_else(|| side(!top_from_other).map(|c| (c, !top_from_other))) else { continue };
        let mut parts = clothes_parts(&clothes);
        let (Some(d), Some(v)) = (parts.get_mut(1), clothes_parts(&source).get(1).cloned()) else { continue };
        *d = v;
        map_set(&mut clothes, "parts", Value::Array(parts));
        *entry = join_coordinate(&clothes, &rest);
        if from_other { out.push((o, CLOTHES_GENES[1])); }
    }
    if !out.is_empty() { blocks.insert("Coordinate".into(), encode(&Value::Array(mine.into_iter().map(Value::Binary).collect()))); }
    out
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
    breed_forced(mother, father, seed, files, &BTreeMap::new(), &BTreeMap::new()).map(|b| (b.card, b.from_father, b.summary))
}

/// A child as reed makes her, with what file::breed_whole needs to change genes.
pub struct Bred { pub card: Vec<u8>, pub from_father: bool, pub hair_from_father: bool, pub summary: String, custom: Vec<Value>, sources: BTreeMap<String, Option<bool>>, mixed_outfits: Vec<usize> }

/// `forced` key of an outfit whose clothes stay the base's whole (its mix needed what neither parent's data had).
fn unmixed_key(outfit: usize) -> String { format!("clothes.outfit{outfit}") }

/// reed with some whole-number fields (section.path) taken from the father (	rue) or the mother whatever the draw.
fn breed_forced(mother: &[u8], father: &[u8], seed: u64, files: (&Path, &Path), forced: &BTreeMap<String, bool>,
    groups: &BTreeMap<String, bool>) -> Result<Bred, String> {
    let mut mixer = Mixer { rng: Rng(seed ^ 0x6F6B_4272_6565_6421), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: forced.clone(), groups: groups.clone() };
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
    // Her top, bottom and underwear, each from either parent (drawn after everything above: a seed's earlier genes
    // stay what they were before clothes were mixed).
    let unmixed: Vec<usize> = (0..64).filter(|o| forced.contains_key(&unmixed_key(*o))).collect();
    let mut clothes_taken = mix_clothes(&mut blocks, other, from_father, &mut mixer, &unmixed);
    let covered = cover_bare_outfits(&mut blocks, base, other, &clothes_taken);
    let skirted: Vec<usize> = covered.iter().map(|(o, _)| *o).collect();
    clothes_taken.extend(covered);
    let mut mixed_outfits: Vec<usize> = clothes_taken.iter().map(|(o, _)| *o).collect();
    mixed_outfits.dedup();

    let hair_from_father = mixer.picks.get("hair").copied().unwrap_or(false);
    let mut kkex = base.get("KKEx").and_then(|k| decode(k)).unwrap_or(Value::Map(Vec::new()));
    let other_kkex = other.get("KKEx").and_then(|k| decode(k)).unwrap_or(Value::Map(Vec::new()));
    let outfit_from_other = |p: &str| clothes_taken.iter().any(|(o, gene)| {
        p.strip_prefix(&format!("outfit{o}.ChaFileClothes.")).is_some_and(|rest| gene.2.iter().any(|n| rest.starts_with(n)))
    });
    sideloader_select(&mut kkex, &other_kkex, from_father, &mixed, &mixer.sources, &outfit_from_other);
    if hair_from_father != from_father { hair_material_rows(&mut kkex, &other_kkex); }
    if !clothes_taken.is_empty() {
        // (Material Editor clothing rows: ObjectType 1, the outfit and the slot of ChaFileClothes.parts)
        material_rows(&mut kkex, &other_kkex, &|e: &Value| {
            let int = |k: &str| map_get(e, k).and_then(|v| v.as_i64());
            int("ObjectType") == Some(1) && clothes_taken.iter().any(|(o, gene)| int("CoordinateIndex") == Some(*o as i64)
                && int("Slot").is_some_and(|s| gene.1.contains(&(s as usize))))
        });
    }
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
    // HairDeck hair (okHk) goes with the hair: the parent her hairstyle came from, whoever the base is.
    let hair_parent = if hair_from_father { father } else { mother };
    let card = crate::portable::hairdeck::inherit(&card, hair_parent)?;
    let hairdeck = crate::portable::hairdeck::card_payload(hair_parent).is_some();
    let card = crate::oklib::with_card_identity(&card, &id)?;
    let side = |b: bool| if b { "father" } else { "mother" };
    let generation = rm["generation"].as_u64().unwrap_or(0).max(rf["generation"].as_u64().unwrap_or(0)) + 1;
    let record = serde_json::json!({
        "format": "ok-breed", "version": 1, "name": format!("{last} {first}").trim(), "seed": seed, "generation": generation, "mother": rm, "father": rf,
        "base": side(from_father), "picks": mixer.picks.iter().map(|(k, v)| (k.clone(), side(*v))).collect::<BTreeMap<_, _>>(),
        "changed": forced.iter().filter(|(k, _)| !k.starts_with("clothes.")).map(|(k, v)| (k.clone(), side(*v))).collect::<BTreeMap<_, _>>(),
        "clothes_not_mixed": unmixed,
        "bottom_added": skirted,
        "hairdeck": if hairdeck { serde_json::Value::from(side(hair_from_father)) } else { serde_json::Value::Null },
    });
    let card = crate::tree_answers::with_chunk(&card, DNA_CHUNK, &serde_json::to_vec(&record).unwrap())?;
    let pick = |g: &str| side(mixer.picks.get(g).copied().unwrap_or(from_father));
    let summary = format!("child {last} {first} (generation {generation}, seed {seed}, outfits from the {} with the top from the {}, bottom from the {}, underwear from the {}, hair from the {}{}{})",
        side(from_father), pick("top"), pick("bottom"), pick("underwear"), side(hair_from_father), if hairdeck { ", HairDeck hair" } else { "" },
        if skirted.is_empty() { String::new() } else { format!(", the bottom worn with her top where her lower body was bare (outfits {skirted:?})") });
    Ok(Bred { card, from_father, hair_from_father, summary: summary.replace("  ", " "), custom: mixed, sources: mixer.sources, mixed_outfits })
}

/// The list entries (category, id) an OK card's strict open lacked, as its error names them ("okLt cat 410 1919").
fn catalogue_gaps(error: &str) -> Vec<(i64, i64)> {
    let mut out: Vec<(i64, i64)> = error.match_indices("okLt cat ").filter_map(|(at, m)| {
        let mut words = error[at + m.len()..].split(|c: char| !c.is_ascii_digit()).filter(|w| !w.is_empty());
        Some((words.next()?.parse().ok()?, words.next()?.parse().ok()?))
    }).collect();
    out.sort();
    out.dedup();
    out
}

/// Genes to take from the other parent: the fields of the child whose value is a list entry (category, id) her open
/// lacked and that came from one parent (`sources`).
/// The outfits a strict open failed in, as its error names them ("outfit 4: ...", "| outfit 4 clothes [...]").
fn failing_outfits(error: &str) -> Vec<usize> {
    let mut out: Vec<usize> = error.match_indices("outfit ").filter_map(|(at, m)| {
        let rest = &error[at + m.len()..];
        rest[..rest.find(|c: char| !c.is_ascii_digit()).unwrap_or(rest.len())].parse().ok()
    }).collect();
    out.sort();
    out.dedup();
    out
}

fn genes_to_change(bred: &Bred, gaps: &[(i64, i64)]) -> BTreeMap<String, bool> {
    let mut out = BTreeMap::new();
    for &(category, id) in gaps {
        for (section, path) in crate::appearance::custom_fields_of_category(category as i32) {
            if custom_value(&bred.custom, &section, &path).and_then(Value::as_i64) != Some(id) { continue; }
            let key = format!("{section}.{path}");
            if let Some(Some(father)) = bred.sources.get(&key) { out.insert(key, !father); }
        }
    }
    out
}

// ------------------------------------------------------------------ depending on the parents

/// The `okDn` record of a card (None: not a bred child).
fn dna(bytes: &[u8]) -> Option<serde_json::Value> {
    crate::oklib::png_chunk(bytes, DNA_CHUNK).and_then(|d| serde_json::from_slice(d).ok())
}
/// The parents a child depends on, in the order their packs go (the base parent first): ("mother"|"father").
fn depended_parents(record: &serde_json::Value) -> Vec<&'static str> {
    let base_is_father = record["base"].as_str() == Some("father");
    let order = if base_is_father { ["father", "mother"] } else { ["mother", "father"] };
    order.into_iter().filter(|p| record["depends"][*p].as_bool() == Some(true)).collect()
}
/// A child that depends on her parents: her card carries only what they do not (okDn `depends`).
pub fn is_dependent(bytes: &[u8]) -> bool { dna(bytes).is_some_and(|r| !depended_parents(&r).is_empty()) }

fn absolute(p: &Path) -> std::path::PathBuf {
    if p.is_absolute() { p.to_owned() } else { std::env::current_dir().map(|d| d.join(p)).unwrap_or_else(|_| p.to_owned()) }
}
/// `to` relative to the folder `from` (None: another drive).
fn relative_path(from: &Path, to: &Path) -> Option<String> {
    use std::path::Component;
    let norm = |p: &Path| -> Vec<String> { p.components().filter(|c| !matches!(c, Component::CurDir)).map(|c| c.as_os_str().to_string_lossy().to_lowercase()).collect() };
    let (a, b) = (norm(&absolute(from)), norm(&absolute(to)));
    if a.first() != b.first() { return None; }
    let common = a.iter().zip(&b).take_while(|(x, y)| x == y).count();
    let names: Vec<String> = absolute(to).components().filter(|c| !matches!(c, Component::CurDir)).map(|c| c.as_os_str().to_string_lossy().into_owned()).collect();
    let mut parts: Vec<String> = std::iter::repeat("..".to_owned()).take(a.len() - common).collect();
    parts.extend(names.into_iter().skip(common));
    Some(parts.join("/"))
}

/// The parent's card file a child names: by the path relative to the child, the absolute path, then the same file name
/// beside the child (that one only when it is the same person, `okId`).
fn find_parent(record: &serde_json::Value, child: &Path) -> Result<(std::path::PathBuf, Vec<u8>), String> {
    let dir = child.parent().unwrap_or(Path::new("."));
    let id = record["id"].as_str().unwrap_or("");
    let mut tried = Vec::new();
    let candidates = [record["relative"].as_str().map(|r| dir.join(r)), record["path"].as_str().map(std::path::PathBuf::from)];
    for path in candidates.into_iter().flatten() {
        if let Ok(bytes) = std::fs::read(&path) {
            if crate::oklib::card_identity(&bytes).as_deref() != Some(id) {
                eprintln!("ok-extract: breed: {} is not the card the child was bred from (its identity changed); used anyway", path.display());
            }
            return Ok((path, bytes));
        }
        tried.push(path.display().to_string());
    }
    if let Some(name) = record["file"].as_str() {
        let path = dir.join(name);
        if let Ok(bytes) = std::fs::read(&path) { if crate::oklib::card_identity(&bytes).as_deref() == Some(id) { return Ok((path, bytes)); } }
        tried.push(path.display().to_string());
    }
    Err(format!("{}: her parent {} is missing (looked for {})", child.display(), record["name"].as_str().unwrap_or("?"), tried.join(", ")))
}

/// Gathers the packs and answers a card opens with, in precedence order: her own, then each parent's (the base parent
/// first), an ancestor met twice once.
fn gather(bytes: &[u8], path: &Path, depth: usize, seen: &mut Vec<std::path::PathBuf>, packs: &mut Vec<Vec<u8>>, answers: &mut Vec<Vec<u8>>,
          stamps: &mut Vec<(std::path::PathBuf, u64, Option<std::time::SystemTime>)>) -> Result<(), String> {
    if depth > 64 { return Err(format!("{}: lineage deeper than 64 generations (a card that is its own ancestor?)", path.display())); }
    if let Some(p) = crate::oklib::png_chunk(bytes, crate::oklib::PACK_CHUNK) { packs.push(p.to_vec()); }
    if let Some(a) = crate::oklib::png_chunk(bytes, crate::tree_answers::CHUNK) { answers.push(a.to_vec()); }
    let Some(record) = dna(bytes) else { return Ok(()) };
    for side in depended_parents(&record) {
        let (parent, parent_bytes) = find_parent(&record[side], path)?;
        let key = absolute(&parent);
        if seen.iter().any(|s| s.as_os_str().eq_ignore_ascii_case(key.as_os_str())) { continue; }
        seen.push(key);
        let m = std::fs::metadata(&parent).ok();
        stamps.push((parent.clone(), m.as_ref().map_or(0, |m| m.len()), m.and_then(|m| m.modified().ok())));
        gather(&parent_bytes, &parent, depth + 1, seen, packs, answers, stamps)?;
    }
    Ok(())
}

type Stamps = Vec<(std::path::PathBuf, u64, Option<std::time::SystemTime>)>;
fn stamps_current(stamps: &Stamps) -> bool {
    stamps.iter().all(|(p, len, t)| std::fs::metadata(p).ok().is_some_and(|m| m.len() == *len && m.modified().ok() == *t))
}

/// A card as it opens: a child that depends on her parents gets her own pack and answers merged with theirs (read from
/// their cards now, generations up), an OK card carrying everything; any other card as it is. The last few are kept
/// while none of their files changed.
pub fn with_parents(bytes: Vec<u8>, path: &Path) -> Result<std::sync::Arc<Vec<u8>>, String> {
    use std::sync::{Arc, Mutex};
    if !is_dependent(&bytes) { return Ok(Arc::new(bytes)); }
    static LAST: Mutex<Vec<(Stamps, Arc<Vec<u8>>)>> = Mutex::new(Vec::new());
    let own = { let m = std::fs::metadata(path).ok(); (absolute(path), m.as_ref().map_or(0, |m| m.len()), m.and_then(|m| m.modified().ok())) };
    if let Some(hit) = LAST.lock().unwrap_or_else(|e| e.into_inner()).iter().find(|(s, _)| s.first() == Some(&own) && stamps_current(s)).map(|e| e.1.clone()) {
        return Ok(hit);
    }
    let t = std::time::Instant::now();
    let (mut seen, mut packs, mut answers, mut stamps) = (vec![absolute(path)], Vec::new(), Vec::new(), vec![own]);
    gather(&bytes, path, 0, &mut seen, &mut packs, &mut answers, &mut stamps)?;
    let packs_ref: Vec<&[u8]> = packs.iter().map(Vec::as_slice).collect();
    let answers_ref: Vec<&[u8]> = answers.iter().map(Vec::as_slice).collect();
    let mut card = without(&bytes, &[crate::oklib::PACK_CHUNK, crate::tree_answers::CHUNK])?;
    if let Some(pack) = crate::oklib::merge_pack_payloads(&packs_ref)? { card = crate::tree_answers::with_chunk(&card, crate::oklib::PACK_CHUNK, &pack)?; }
    if let Some(table) = crate::tree_answers::merge_payloads(&answers_ref)? { card = crate::tree_answers::with_chunk(&card, crate::tree_answers::CHUNK, &table)?; }
    eprintln!("ok-extract: breed: {} opens with {} ancestor card(s) ({} packs, {} bytes) in {:.2}s", path.display(), stamps.len() - 1, packs.len(), card.len(), t.elapsed().as_secs_f64());
    let card = Arc::new(card);
    let mut last = LAST.lock().unwrap_or_else(|e| e.into_inner());
    if last.len() >= 2 { last.remove(0); }
    last.push((stamps, card.clone()));
    Ok(card)
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
        breed_into_with(lib, game, mother, father, seed, out, true)
    }

    /// `breed_into`; `depend`: the child carries only what her OK card parents' cards do not (okDn `depends`, the
    /// parents' packs and answers read from their cards when she opens, `with_parents`), else everything (a whole card).
    pub fn breed_into_with(lib: Option<&Path>, game: &Path, mother: &Path, father: &Path, seed: u64, out: &Path, depend: bool) -> Result<String, String> {
        let summary = breed_whole(lib, game, mother, father, seed, out)?;
        let made = read(out)?;
        let Some(mut record) = dna(&made) else { return Ok(summary) };
        let ok = (crate::oklib::is_library_card(mother), crate::oklib::is_library_card(father));
        if !depend || !(ok.0 || ok.1) || crate::oklib::png_chunk(&made, crate::oklib::CARD_CHUNK).is_none() { return Ok(summary); }
        // Where her parents are, and which of them she opens with (an OK card file: a parent that was an original card was
        // made into one only for her, and what that gave stays in her own card).
        let dir = absolute(out).parent().map(Path::to_owned).unwrap_or_default();
        for (side, path, is_ok) in [("mother", mother, ok.0), ("father", father, ok.1)] {
            let abs = absolute(path);
            record[side]["path"] = abs.display().to_string().into();
            record[side]["relative"] = relative_path(&dir, &abs).map_or(serde_json::Value::Null, Into::into);
            record["depends"][side] = is_ok.into();
        }
        let mut theirs: Vec<std::sync::Arc<Vec<u8>>> = Vec::new();
        for side in depended_parents(&record) {
            let path = if side == "mother" { mother } else { father };
            theirs.push(with_parents(read(path)?, path)?);
        }
        let packs: Vec<&[u8]> = theirs.iter().filter_map(|b| crate::oklib::png_chunk(b, crate::oklib::PACK_CHUNK)).collect();
        let answers: Vec<&[u8]> = theirs.iter().filter_map(|b| crate::oklib::png_chunk(b, crate::tree_answers::CHUNK)).collect();
        let own_pack = match crate::oklib::png_chunk(&made, crate::oklib::PACK_CHUNK) { Some(full) => crate::oklib::pack_delta(full, &packs)?, None => None };
        let own_answers = match crate::oklib::png_chunk(&made, crate::tree_answers::CHUNK) {
            Some(full) if answers.is_empty() => Some(full.to_vec()),
            Some(full) => crate::tree_answers::delta(full, &answers)?,
            None => None,
        };
        let mut card = without(&made, &[crate::oklib::PACK_CHUNK, crate::tree_answers::CHUNK])?;
        if let Some(p) = &own_pack { card = crate::tree_answers::with_chunk(&card, crate::oklib::PACK_CHUNK, p)?; }
        if let Some(a) = &own_answers { card = crate::tree_answers::with_chunk(&card, crate::tree_answers::CHUNK, a)?; }
        card = crate::tree_answers::with_chunk(&card, DNA_CHUNK, &serde_json::to_vec(&record).unwrap())?;
        write(out, &card)?;
        Ok(format!("{summary}; depends on her parents: card {} bytes (whole {}), own pack {} bytes, own answers {} bytes", card.len(), made.len(),
            own_pack.as_ref().map_or(0, Vec::len), own_answers.as_ref().map_or(0, Vec::len)))
    }

    /// A child that depends on her parents written as a whole card to `out`: her pack and answers with theirs, every
    /// outfit opened strictly from it (opens from her own data and the shared library alone, the parents not needed).
    pub fn export_into(lib: Option<&Path>, game: &Path, card: &Path, out: &Path) -> Result<String, String> {
        let bytes = read(card)?;
        if !is_dependent(&bytes) { return Err(format!("{}: not a child that depends on her parents (already a whole card)", card.display())); }
        let whole = with_parents(bytes, card)?;
        let mut record = dna(&whole).unwrap_or_default();
        record["depends"] = serde_json::Value::Null;
        record["exported_from"] = absolute(card).display().to_string().into();
        let whole = crate::tree_answers::with_chunk(&whole, DNA_CHUNK, &serde_json::to_vec(&record).unwrap())?;
        write(out, &whole)?;
        let lib = lib.map(Path::to_owned).or_else(crate::oklib::configured_library).ok_or("OK base library not configured")?;
        let (digest, _, made, pack) = crate::oklib::remake_ok_card(&lib, game, out)?;
        write(out, &made)?;
        Ok(format!("whole card {} bytes, pack {pack} bytes, digest {digest}", made.len()))
    }

    fn breed_whole(lib: Option<&Path>, game: &Path, mother: &Path, father: &Path, seed: u64, out: &Path) -> Result<String, String> {
        let ok = (crate::oklib::is_library_card(mother), crate::oklib::is_library_card(father));
        let needs_ok = ok.0 || ok.1;
        let lib = if needs_ok { Some(lib.map(Path::to_owned).or_else(crate::oklib::configured_library).ok_or("OK base library not configured")?) } else { None };
        let parent = |path: &Path, is_ok: bool| -> Result<Vec<u8>, String> {
            // (a parent that depends on her own parents: with theirs, as she opens)
            if needs_ok && !is_ok { let (_, _, made, _) = crate::oklib::remake_ok_card(lib.as_deref().unwrap(), game, path)?; Ok(made) }
            else { Ok(std::sync::Arc::unwrap_or_clone(with_parents(read(path)?, path)?)) }
        };
        let (m, f) = (parent(mother, ok.0)?, parent(father, ok.1)?);
        let Some(lib) = lib else { let (child, _, summary) = breed(&m, &f, seed, (mother, father))?; write(out, &child)?; return Ok(summary); };
        // A gene whose part neither parent's data can show (a mod's list entry neither of them read: Raiden's mod eye
        // highlight, which her Material Editor rows cover, on a granddaughter without them) is taken from the other parent.
        let mut forced = BTreeMap::new();
        // Her hair comes from one parent whole. A parent whose own hairstyle cannot be shown (his card names a back
        // hair no list has: crowd_C011, 2026-11-23) would make her bald, so her hair comes from the other one. Nothing
        // to choose when neither can show hers: the draw stands.
        let mut groups = BTreeMap::new();
        let bald = |path: &Path| match crate::outfit_gaps::hairstyle_gaps(game, path) {
            Ok(gaps) => { if !gaps.is_empty() { eprintln!("ok-extract: breed: {} cannot show her own hairstyle: {}", path.display(),
                gaps.iter().map(|g| format!("cat {} id {} guid {}", g.category, g.id, g.guid)).collect::<Vec<_>>().join(", ")); } !gaps.is_empty() }
            Err(e) => { eprintln!("ok-extract: breed: {}: hairstyle not checked ({e})", path.display()); false }
        };
        match (bald(mother), bald(father)) {
            (false, true) => { groups.insert("hair".to_owned(), false); }
            (true, false) => { groups.insert("hair".to_owned(), true); }
            _ => {}
        }
        for attempt in 0.. {
            let bred = breed_forced(&m, &f, seed, (mother, father), &forced, &groups)?;
            match seal(&lib, game, &bred, if bred.from_father { &m } else { &f }, out) {
                Ok(sealing) => {
                    // Her hairstyle gene only carries the game's hair slots. A parent whose hair is made of accessories
                    // has an empty hairstyle, and her accessories go with the base's outfits, not with the gene: a
                    // child who drew that empty hairstyle from the parent she is not built on came out with no hair at
                    // all (lan x luo_tianyi_2024, 2026-11-25). Seen on the sealed child, the hairstyle comes from the
                    // other parent instead; nothing to do when the other one leaves her bald too.
                    if !groups.contains_key("hair") && bald_card(&lib, game, out) {
                        groups.insert("hair".to_owned(), !bred.hair_from_father);
                        eprintln!("ok-extract: breed: the child had no hair (her hairstyle gene came from the {}, whose own hair is not in the hairstyle slots): taking it from the other parent",
                            if bred.hair_from_father { "father" } else { "mother" });
                        continue;
                    }
                    let changed = if forced.is_empty() { String::new() } else { format!("; genes from the other parent (her parents' data could not show them): {}", forced.keys().cloned().collect::<Vec<_>>().join(", ")) };
                    return Ok(format!("{}; {sealing}{changed}", bred.summary));
                }
                Err(e) => {
                    let mut more = genes_to_change(&bred, &catalogue_gaps(&e));
                    // A mixed outfit that cannot open (a top and a bottom from different parents ask for a body mask
                    // neither parent's data has: texture_payload ... bodymask, 2026-11-22): that outfit stays the base's.
                    if more.is_empty() {
                        for o in failing_outfits(&e) { if bred.mixed_outfits.contains(&o) { more.insert(unmixed_key(o), true); } }
                    }
                    if attempt >= 6 || more.is_empty() || more.iter().all(|(k, v)| forced.get(k) == Some(v)) { return Err(e); }
                    eprintln!("ok-extract: breed: sealing failed: {}", e.chars().take(800).collect::<String>());
                    eprintln!("ok-extract: breed: {} gene(s) her parents' data cannot show, taken from the other parent: {more:?}", more.len());
                    forced.extend(more);
                }
            }
        }
        unreachable!()
    }

    /// She opens with no hair at all (`portable::hairdeck::visible_hair_parts`). A card that cannot be opened is not
    /// called bald: the caller is about to return it, and its own error says more than this would.
    fn bald_card(lib: &Path, game: &Path, card: &Path) -> bool {
        match crate::oklib::open_original_card(game, card, 0).unwrap_or_else(|| crate::session::open(lib, Some(card), 0)) {
            Ok(s) => crate::portable::hairdeck::visible_hair_parts(&s).is_empty(),
            Err(e) => { eprintln!("ok-extract: breed: the child was not checked for hair ({e})"); false }
        }
    }

    /// The child sealed as an OK card with the other parent's pack and answers, written to `out`.
    fn seal(lib: &Path, game: &Path, bred: &Bred, other: &[u8], out: &Path) -> Result<String, String> {
        let child = bred.card.clone();
        let merged = match crate::oklib::png_chunk(other, crate::oklib::PACK_CHUNK) { Some(pack) => crate::oklib::merge_card_pack(&child, pack)?, None => child };
        // Both parents' answers (her questions ask about both): recorded again from the shared library they would lose
        // the third-party mods of the parent whose pack is not the base's.
        let (merged, keep) = match (crate::oklib::png_chunk(other, crate::tree_answers::CHUNK), crate::oklib::png_chunk(&merged, crate::tree_answers::CHUNK).is_some()) {
            (Some(answers), true) => (crate::tree_answers::merge(&merged, answers)?, true),
            _ => (crate::cardbake::strip_answers(&merged).into_owned(), false),
        };
        // (her mix asks questions neither parent did: those the shared library can answer are)
        let (sealed, sealing) = if keep { crate::oklib::seal_card_adding_answers(lib, &merged)? } else { crate::oklib::seal_card_with(lib, &merged, true)? };
        write(out, &sealed)?;
        let (digest, _, made, pack) = crate::oklib::remake_ok_card(lib, game, out)?;
        write(out, &made)?;
        Ok(format!("sealed: {sealing}; digest {digest} pack={pack}"))
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
        let run = |seed| { let mut m = Mixer { rng: Rng(seed), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: BTreeMap::new(), groups: BTreeMap::new() }; m.mix("face", "", &face(0.2), &face(0.8)) };
        assert_eq!(run(7), run(7));
        let child = run(7);
        let values: Vec<f64> = map_get(&child, "shapeValueFace").unwrap().as_array().unwrap().iter().map(|v| as_f64(v).unwrap()).collect();
        assert!(values.iter().all(|v| (0.0..=1.0).contains(v)), "{values:?}");
        assert!(values.iter().any(|v| (v - 0.2).abs() > 1e-3 && (v - 0.8).abs() > 1e-3));
        assert!(matches!(map_get(&child, "headId").and_then(|v| v.as_i64()), Some(1 | 2)));
    }

    #[test]
    fn colours_blend_as_one() {
        let mut m = Mixer { rng: Rng(3), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: BTreeMap::new(), groups: BTreeMap::new() };
        let c = |r: f32| Value::Array(vec![Value::F32(r), Value::F32(r), Value::F32(r), Value::F32(1.0)]);
        let out = m.mix("hair", "baseColor", &c(0.0), &c(1.0));
        let v: Vec<f64> = out.as_array().unwrap().iter().map(|v| as_f64(v).unwrap()).collect();
        assert!((v[0] - v[1]).abs() < 0.2 && (v[1] - v[2]).abs() < 0.2 && v[3] == 1.0, "{v:?}");
        // Hair in HSV: red and blue meet as a bright purple, not RGB's darker half.
        for seed in 0..32 {
            let mut m = Mixer { rng: Rng(seed), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: BTreeMap::new(), groups: BTreeMap::new() };
            let rgb = |r: f32, g: f32, b: f32| Value::Array(vec![Value::F32(r), Value::F32(g), Value::F32(b), Value::F32(1.0)]);
            let out = m.mix("hair", "parts.0.baseColor", &rgb(0.9, 0.1, 0.1), &rgb(0.1, 0.1, 0.9));
            let v: Vec<f64> = out.as_array().unwrap().iter().map(|v| as_f64(v).unwrap()).collect();
            assert!(v[0].max(v[1]).max(v[2]) > 0.8, "darker than the parents: {v:?}");
        }
        let back = hsv_to_rgb(rgb_to_hsv([0.3, 0.6, 0.2]));
        assert!((back[0] - 0.3).abs() < 1e-9 && (back[1] - 0.6).abs() < 1e-9 && (back[2] - 0.2).abs() < 1e-9);
    }

    #[test]
    fn sideloader_entries_follow_the_value() {
        let entry = |slot: i64, guid: &str| Value::Binary(encode(&Value::Map(vec![("ModID".into(), guid.into()), ("Slot".into(), slot.into()), ("Property".into(), "ChaFileFace.hlUpId".into())])));
        let kkex = |rows: Vec<Value>| Value::Map(vec![(SIDELOADER.into(), Value::Array(vec![Value::from(1), Value::Map(vec![("info".into(), Value::Array(rows))])]))]);
        let custom = |v: i64| vec![Value::Map(vec![("hlUpId".into(), Value::from(v))]), Value::Map(vec![]), Value::Map(vec![])];
        let guids = |k: &Value| -> Vec<String> { map_get(k, SIDELOADER).and_then(|p| p.as_array()).map(|a| map_get(&a[1], "info").unwrap().as_array().unwrap().iter()
            .map(|e| map_get(&unbin(e), "ModID").unwrap().as_str().unwrap().to_owned()).collect()).unwrap_or_default() };
        // Her highlight 5 is her father's original one: her mother's dormant mod entry for slot 5 must not take it.
        let sources = BTreeMap::from([("face.hlUpId".to_owned(), Some(true))]);
        let mut base = kkex(vec![entry(5, "mother.mod")]);
        sideloader_select(&mut base, &kkex(vec![]), false, &custom(5), &sources, &|_| false);
        assert!(guids(&base).is_empty());
        // Her father's mod highlight (slot 5) comes with its entry; one for a value she lacks does not.
        let mut base = kkex(vec![entry(9, "mother.mod")]);
        sideloader_select(&mut base, &kkex(vec![entry(5, "father.mod")]), false, &custom(5), &sources, &|_| false);
        assert_eq!(guids(&base), ["father.mod"]);
    }

    #[test]
    fn clothes_mix_by_piece() {
        // Outfit 0: mother (base) wears top 1, bottom 2, bra 3, shorts 4; father top 11, bottom 0 (none), bra 13, shorts 14.
        let outfit = |ids: [i64; 4]| {
            let parts: Vec<Value> = (0..9).map(|i| Value::Map(vec![("id".into(), Value::from(*ids.get(i).unwrap_or(&0)))])).collect();
            join_coordinate(&Value::Map(vec![("parts".into(), Value::Array(parts)), ("subPartsId".into(), Value::Array(vec![]))]), b"rest")
        };
        let blocks = |ids| BTreeMap::from([("Coordinate".to_owned(), encode(&Value::Array(vec![Value::Binary(outfit(ids))])))]);
        let ids = |b: &BTreeMap<String, Vec<u8>>| { let (c, rest) = split_coordinate(&coordinate_entries(b)[0]).unwrap(); assert_eq!(rest, b"rest");
            clothes_parts(&c).iter().take(4).map(|p| map_get(p, "id").unwrap().as_i64().unwrap()).collect::<Vec<_>>() };
        for seed in 0..64 {
            let (mut mine, theirs) = (blocks([1, 2, 3, 4]), blocks([11, 0, 13, 14]));
            let mut m = Mixer { rng: Rng(seed), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: BTreeMap::new(), groups: BTreeMap::new() };
            let taken = mix_clothes(&mut mine, &theirs, false, &mut m, &[]);
            let got = ids(&mine);
            // Never undressed: the father wears no bottom, so hers stays. Bra and shorts go together.
            assert_eq!(got[1], 2);
            assert!((got[2], got[3]) == (3, 4) || (got[2], got[3]) == (13, 14), "{got:?}");
            assert_eq!(taken.iter().any(|(_, g)| g.0 == "top"), got[0] == 11);
            assert_eq!(m.picks.get("top") == Some(&true), got[0] == 11);
        }
        // An outfit kept whole: nothing taken.
        let (mut mine, theirs) = (blocks([1, 2, 3, 4]), blocks([11, 12, 13, 14]));
        let mut m = Mixer { rng: Rng(3), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: BTreeMap::new(), groups: BTreeMap::new() };
        assert!(mix_clothes(&mut mine, &theirs, false, &mut m, &[0]).is_empty());
        assert_eq!(ids(&mine), [1, 2, 3, 4]);
        assert_eq!(failing_outfits("sealing open failed: outfit 4: x | outfit 4 clothes [1] | outfit 12: y"), [4, 12]);
        // Bare below: the base (father) wears top 11 and no bottom; she never stays bare while the mother wears bottom 2.
        let mut skirted_seen = false;
        for seed in 0..64 {
            let (base, other) = (blocks([11, 0, 13, 14]), blocks([1, 2, 3, 4]));
            let mut mine = base.clone();
            let mut m = Mixer { rng: Rng(seed), picks: BTreeMap::new(), sources: BTreeMap::new(), forced: BTreeMap::new(), groups: BTreeMap::new() };
            let taken = mix_clothes(&mut mine, &other, true, &mut m, &[]);
            let skirted = cover_bare_outfits(&mut mine, &base, &other, &taken);
            let got = ids(&mine);
            assert_eq!(got[1], 2, "bare below: {got:?}");
            assert!(skirted.iter().all(|(o, g)| *o == 0 && g.0 == "bottom"));
            skirted_seen |= !skirted.is_empty();
        }
        assert!(skirted_seen);
    }

    #[test]
    fn names_mix() {
        let mut rng = Rng(1);
        let n = child_first_name("刻晴", "雷電", &mut rng);
        assert_eq!(n.chars().count(), 2);
        assert!(["刻電", "雷晴"].contains(&n.as_str()), "{n}");
    }
}
