//! Mod data in an OK card (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.2, §6.12): two PNG chunks the mod host reads and writes,
//! and the core keeps exactly as they are.
//!
//! - `okMx`: msgpack map `{ mod_id: { version: u32, requires: { id, version }, data: bin } }`, one section per mod
//!   (ExtendedSave's extended data). A section the running build does not know is carried byte for byte: the map is
//!   kept as raw key and value spans and only the section a mod writes is encoded again.
//! - `okMr`: the mods' resources (textures, masks, curves) by content: zstd of a msgpack map
//!   `{ sha256 hex: bin }`, referenced from `okMx` data. One copy however many mods use it.
//!
//! Neither counts toward the card's identity (`oklib::card_identity`, `IDENTITY_EXCLUDED`), so saving mod data never
//! makes her a stranger; writing either goes through `tree_answers::with_chunk`, which gives a card without `okId` the
//! identity it had. A remade OK card carries both over (`carry_over`).
//!
//! The open cache (`oklib::session_cache_key`) also hashes the mods enabled in this process and their versions
//! (`set_enabled`), so an open built with a mod's hooks is never served to a process without it, or the other way.
//! With no mod enabled the key is what it was before mods existed.
use std::sync::RwLock;

/// Mod data (§6.2).
pub const DATA_CHUNK: &[u8; 4] = b"okMx";
/// Mod resources by content (§6.12).
pub const RESOURCE_CHUNK: &[u8; 4] = b"okMr";
/// Chunks a card's identity leaves out: her own TTS voice and the mods' data and resources.
pub const IDENTITY_EXCLUDED: [&[u8; 4]; 3] = [b"okVo", DATA_CHUNK, RESOURCE_CHUNK];

/// What a mod's section asks of the reader: the mod and the version that wrote it (§6.12 "requires").
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Requires { pub id: String, pub version: String }

/// One mod's section of `okMx`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Section { pub version: u32, pub requires: Option<Requires>, pub data: Vec<u8> }

impl Section {
    fn encode(&self) -> Vec<u8> {
        use rmpv::Value;
        let mut map = vec![(Value::from("version"), Value::from(self.version))];
        if let Some(r) = &self.requires {
            map.push((Value::from("requires"), Value::Map(vec![
                (Value::from("id"), Value::from(r.id.as_str())),
                (Value::from("version"), Value::from(r.version.as_str())),
            ])));
        }
        map.push((Value::from("data"), Value::Binary(self.data.clone())));
        let mut out = Vec::new();
        rmpv::encode::write_value(&mut out, &Value::Map(map)).expect("msgpack into a Vec");
        out
    }
    fn decode(raw: &[u8]) -> Result<Section, String> {
        use rmpv::Value;
        let value = rmpv::decode::read_value(&mut &raw[..]).map_err(|e| format!("okMx section: {e}"))?;
        let Value::Map(fields) = value else { return Err("okMx section is not a map".into()) };
        let field = |name: &str| fields.iter().find(|(k, _)| k.as_str() == Some(name)).map(|(_, v)| v);
        let version = field("version").and_then(Value::as_u64).and_then(|v| u32::try_from(v).ok())
            .ok_or("okMx section without a version")?;
        let data = match field("data") {
            Some(Value::Binary(b)) => b.clone(),
            Some(Value::String(s)) => s.as_bytes().to_vec(),
            None | Some(Value::Nil) => Vec::new(),
            Some(_) => return Err("okMx section data is not bytes".into()),
        };
        let requires = match field("requires") {
            Some(Value::Map(r)) => {
                let get = |name: &str| r.iter().find(|(k, _)| k.as_str() == Some(name)).and_then(|(_, v)| v.as_str()).map(str::to_owned);
                Some(Requires { id: get("id").unwrap_or_default(), version: get("version").unwrap_or_default() })
            }
            _ => None,
        };
        Ok(Section { version, requires, data })
    }
}

/// A card's `okMx`, as raw (key, value) msgpack spans in the card's order.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ModData { entries: Vec<(String, Vec<u8>, Vec<u8>)> }

impl ModData {
    /// Parses an `okMx` payload. Keys must be strings; values are kept as they are.
    pub fn decode(payload: &[u8]) -> Result<ModData, String> {
        let mut rest = payload;
        let n = read_map_len(&mut rest).ok_or("okMx: not a msgpack map")?;
        let mut entries = Vec::with_capacity(n as usize);
        for _ in 0..n {
            let (key, key_raw) = take_value(&mut rest)?;
            let key = key.as_str().ok_or("okMx: a key that is not a string")?.to_owned();
            let (_, value_raw) = take_value(&mut rest)?;
            entries.push((key, key_raw.to_vec(), value_raw.to_vec()));
        }
        if !rest.is_empty() { return Err(format!("okMx: {} bytes after the map", rest.len())); }
        Ok(ModData { entries })
    }
    pub fn encode(&self) -> Vec<u8> {
        let mut out = Vec::new();
        write_map_len(&mut out, self.entries.len() as u32);
        for (_, key, value) in &self.entries { out.extend_from_slice(key); out.extend_from_slice(value); }
        out
    }
    pub fn is_empty(&self) -> bool { self.entries.is_empty() }
    /// Mod ids with a section, in the card's order.
    pub fn ids(&self) -> impl Iterator<Item = &str> { self.entries.iter().map(|(k, _, _)| k.as_str()) }
    /// One mod's section, decoded.
    pub fn get(&self, id: &str) -> Option<Result<Section, String>> {
        self.entries.iter().find(|(k, _, _)| k == id).map(|(_, _, v)| Section::decode(v))
    }
    /// One mod's section as the card stores it (msgpack).
    pub fn raw(&self, id: &str) -> Option<&[u8]> { self.entries.iter().find(|(k, _, _)| k == id).map(|(_, _, v)| v.as_slice()) }
    /// Sets one mod's section (in place when it had one, else appended); every other section stays byte for byte.
    pub fn set(&mut self, id: &str, section: &Section) {
        let value = section.encode();
        match self.entries.iter_mut().find(|(k, _, _)| k == id) {
            Some(e) => e.2 = value,
            None => {
                let mut key = Vec::new();
                rmpv::encode::write_value(&mut key, &rmpv::Value::from(id)).expect("msgpack into a Vec");
                self.entries.push((id.to_owned(), key, value));
            }
        }
    }
    pub fn remove(&mut self, id: &str) -> bool {
        let n = self.entries.len();
        self.entries.retain(|(k, _, _)| k != id);
        n != self.entries.len()
    }
}

/// A msgpack map header from the front of `rest`: its entry count.
fn read_map_len(rest: &mut &[u8]) -> Option<u32> {
    let (&tag, tail) = rest.split_first()?;
    let (n, used) = match tag {
        0x80..=0x8f => (u32::from(tag & 0x0f), 0),
        0xde => (u32::from(u16::from_be_bytes(tail.get(..2)?.try_into().ok()?)), 2),
        0xdf => (u32::from_be_bytes(tail.get(..4)?.try_into().ok()?), 4),
        _ => return None,
    };
    *rest = &tail[used..];
    Some(n)
}
fn write_map_len(out: &mut Vec<u8>, n: u32) {
    if n < 16 { out.push(0x80 | n as u8) }
    else if n <= 0xffff { out.push(0xde); out.extend((n as u16).to_be_bytes()) }
    else { out.push(0xdf); out.extend(n.to_be_bytes()) }
}

/// One msgpack value from the front of `rest`: decoded, and the bytes it took.
fn take_value<'a>(rest: &mut &'a [u8]) -> Result<(rmpv::Value, &'a [u8]), String> {
    let start = *rest;
    let value = rmpv::decode::read_value(rest).map_err(|e| format!("okMx: {e}"))?;
    Ok((value, &start[..start.len() - rest.len()]))
}

/// The card's `okMx` (empty when it has none).
pub fn read_data(card: &[u8]) -> Result<ModData, String> {
    match crate::oklib::png_chunk(card, DATA_CHUNK) { Some(p) => ModData::decode(p), None => Ok(ModData::default()) }
}
/// The card with this `okMx` (none when empty), its identity kept.
pub fn with_data(card: &[u8], data: &ModData) -> Result<Vec<u8>, String> {
    if data.is_empty() { without_chunk(card, DATA_CHUNK) } else { crate::tree_answers::with_chunk(card, DATA_CHUNK, &data.encode()) }
}

/// The card's `okMr`: resources by sha256 hex.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Resources { pub by_hash: std::collections::BTreeMap<String, Vec<u8>> }

impl Resources {
    pub fn decode(payload: &[u8]) -> Result<Resources, String> {
        use rmpv::Value;
        let raw = zstd::decode_all(payload).map_err(|e| format!("okMr: {e}"))?;
        let Value::Map(items) = rmpv::decode::read_value(&mut &raw[..]).map_err(|e| format!("okMr: {e}"))? else { return Err("okMr is not a map".into()) };
        let mut by_hash = std::collections::BTreeMap::new();
        for (k, v) in items {
            let (Some(k), Value::Binary(v)) = (k.as_str(), v) else { return Err("okMr: an entry that is not sha256 -> bytes".into()) };
            by_hash.insert(k.to_owned(), v);
        }
        Ok(Resources { by_hash })
    }
    pub fn encode(&self) -> Result<Vec<u8>, String> {
        use rmpv::Value;
        let map = Value::Map(self.by_hash.iter().map(|(k, v)| (Value::from(k.as_str()), Value::Binary(v.clone()))).collect());
        let mut raw = Vec::new();
        rmpv::encode::write_value(&mut raw, &map).expect("msgpack into a Vec");
        zstd::encode_all(&raw[..], 3).map_err(|e| format!("okMr: {e}"))
    }
    /// Adds a resource and returns its sha256 hex (the same bytes are stored once).
    pub fn add(&mut self, bytes: &[u8]) -> String {
        use sha2::Digest;
        let hash: String = sha2::Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect();
        self.by_hash.entry(hash.clone()).or_insert_with(|| bytes.to_vec());
        hash
    }
    pub fn get(&self, hash: &str) -> Option<&[u8]> { self.by_hash.get(hash).map(Vec::as_slice) }
    pub fn remove(&mut self, hash: &str) -> bool { self.by_hash.remove(hash).is_some() }
    /// Stored bytes, uncompressed (what the host's per-mod limit counts, §6.12).
    pub fn total_bytes(&self) -> usize { self.by_hash.values().map(Vec::len).sum() }
}

pub fn read_resources(card: &[u8]) -> Result<Resources, String> {
    match crate::oklib::png_chunk(card, RESOURCE_CHUNK) { Some(p) => Resources::decode(p), None => Ok(Resources::default()) }
}
pub fn with_resources(card: &[u8], resources: &Resources) -> Result<Vec<u8>, String> {
    if resources.by_hash.is_empty() { without_chunk(card, RESOURCE_CHUNK) } else { crate::tree_answers::with_chunk(card, RESOURCE_CHUNK, &resources.encode()?) }
}

/// The card without chunk `kind`, its identity kept (a card without `okId` gets the one it had).
fn without_chunk(card: &[u8], kind: &[u8; 4]) -> Result<Vec<u8>, String> {
    if !crate::oklib::png_has_chunk(card, kind) { return Ok(card.to_vec()); }
    let identity = crate::oklib::card_identity(card);
    let had = crate::oklib::png_chunk(card, crate::oklib::IDENTITY_CHUNK).is_some();
    let out = crate::cardbake::strip_kinds(card, &[kind]).into_owned();
    match identity { Some(id) if !had => crate::oklib::with_card_identity(&out, &id), _ => Ok(out) }
}

/// `made` (a card made again from `input`) with `input`'s mod data and resources, exactly as they were: a remade or
/// converted card keeps what mods stored in it (ExtendedSave's "unknown data is kept").
pub fn carry_over(input: &[u8], made: Vec<u8>) -> Result<Vec<u8>, String> {
    let mut out = made;
    for kind in [DATA_CHUNK, RESOURCE_CHUNK] {
        if let Some(payload) = crate::oklib::png_chunk(input, kind) {
            if crate::oklib::png_chunk(&out, kind) != Some(payload) { out = crate::cardbake::with_chunk(&out, kind, payload)?; }
        }
    }
    Ok(out)
}

static ENABLED: RwLock<Vec<(String, String)>> = RwLock::new(Vec::new());

/// The mods enabled in this process with their versions (the mod host sets it after loading; empty: no mods).
pub fn set_enabled(mut mods: Vec<(String, String)>) {
    mods.sort();
    mods.dedup();
    *ENABLED.write().unwrap_or_else(|e| e.into_inner()) = mods;
}
pub fn enabled() -> Vec<(String, String)> { ENABLED.read().unwrap_or_else(|e| e.into_inner()).clone() }
/// What the open-cache key hashes for the enabled mods; None with none (the key is then what it was before mods).
pub fn cache_key_bytes() -> Option<Vec<u8>> { key_bytes(&ENABLED.read().unwrap_or_else(|e| e.into_inner())) }
fn key_bytes(mods: &[(String, String)]) -> Option<Vec<u8>> {
    if mods.is_empty() { return None; }
    let mut out = Vec::new();
    for (id, version) in mods.iter() { out.extend_from_slice(id.as_bytes()); out.push(b'@'); out.extend_from_slice(version.as_bytes()); out.push(b'\n'); }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn png(chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
        let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
        for (kind, data) in chunks {
            out.extend((data.len() as u32).to_be_bytes());
            let mut c = kind.to_vec();
            c.extend_from_slice(data);
            out.extend(&c);
            out.extend(crc32fast::hash(&c).to_be_bytes());
        }
        out
    }
    fn card() -> Vec<u8> { png(&[(b"IHDR", &[0; 13]), (b"IDAT", b"pixels"), (b"IEND", b"")]) }

    #[test]
    fn identity_leaves_out_voice_and_mod_chunks() {
        let plain = card();
        let id = crate::oklib::card_identity(&plain).unwrap();
        let mut data = ModData::default();
        data.set("com.example.a", &Section { version: 1, requires: None, data: b"hello".to_vec() });
        let with = with_data(&plain, &data).unwrap();
        assert_eq!(crate::oklib::card_identity(&with).unwrap(), id);
        let mut res = Resources::default();
        res.add(b"texture bytes");
        let with = with_resources(&with, &res).unwrap();
        assert_eq!(crate::oklib::card_identity(&with).unwrap(), id);
        // Writing gave the card the identity it had, as an okId chunk.
        assert_eq!(crate::oklib::png_chunk(&with, crate::oklib::IDENTITY_CHUNK), Some(id.as_bytes()));
        // A card that never had okId: mod chunks dropped from the hash alone (no okId written).
        let bare = png(&[(b"IHDR", &[0; 13]), (b"IDAT", b"pixels"), (DATA_CHUNK, b"\x80"), (RESOURCE_CHUNK, b"x"), (b"okVo", b"v"), (b"IEND", b"")]);
        assert_eq!(crate::oklib::card_identity(&bare).unwrap(), id);
    }

    #[test]
    fn unknown_sections_are_kept_byte_for_byte() {
        // A section another build wrote, with a non-minimal integer encoding and a field this build does not know.
        let s = |v: &str| { let mut o = Vec::new(); rmpv::encode::write_value(&mut o, &rmpv::Value::from(v)).unwrap(); o };
        let mut payload = vec![0x81];
        payload.extend(s("com.other.mod"));
        let mut other = vec![0x83];
        other.extend(s("version"));
        other.extend([0xce, 0, 0, 0, 7]); // not the minimal 0x07
        other.extend(s("data"));
        other.extend([0xc4, 6]);
        other.extend(b"theirs");
        other.extend(s("future"));
        other.push(0xc3);
        payload.extend_from_slice(&other);
        let mut data = ModData::decode(&payload).unwrap();
        assert_eq!(data.encode(), payload, "decoded and encoded again unchanged");
        assert_eq!(data.get("com.other.mod").unwrap().unwrap().data, b"theirs");
        data.set("com.example.mine", &Section { version: 2, requires: Some(Requires { id: "com.example.mine".into(), version: "1.2.0".into() }), data: vec![1, 2, 3] });
        let again = ModData::decode(&data.encode()).unwrap();
        assert_eq!(again.raw("com.other.mod").unwrap(), &other[..], "the other mod's section is unchanged");
        let mine = again.get("com.example.mine").unwrap().unwrap();
        assert_eq!((mine.version, mine.data.as_slice(), mine.requires.unwrap().version.as_str()), (2, &[1u8, 2, 3][..], "1.2.0"));
        assert_eq!(again.ids().collect::<Vec<_>>(), ["com.other.mod", "com.example.mine"]);
    }

    #[test]
    fn resources_dedup_and_round_trip() {
        let mut res = Resources::default();
        let a = res.add(b"same");
        let b = res.add(b"same");
        assert_eq!(a, b);
        assert_eq!(res.by_hash.len(), 1);
        let card = with_resources(&card(), &res).unwrap();
        let back = read_resources(&card).unwrap();
        assert_eq!(back.get(&a), Some(&b"same"[..]));
        assert_eq!(back.total_bytes(), 4);
        // Emptied: the chunk goes, the identity stays.
        let id = crate::oklib::card_identity(&card).unwrap();
        let none = with_resources(&card, &Resources::default()).unwrap();
        assert!(!crate::oklib::png_has_chunk(&none, RESOURCE_CHUNK));
        assert_eq!(crate::oklib::card_identity(&none).unwrap(), id);
    }

    #[test]
    fn carry_over_keeps_both_chunks_exactly() {
        let input = png(&[(b"IHDR", &[0; 13]), (DATA_CHUNK, b"\x81\xa1a\x80"), (RESOURCE_CHUNK, b"zstd..."), (b"IEND", b"")]);
        let made = carry_over(&input, card()).unwrap();
        assert_eq!(crate::oklib::png_chunk(&made, DATA_CHUNK), Some(&b"\x81\xa1a\x80"[..]));
        assert_eq!(crate::oklib::png_chunk(&made, RESOURCE_CHUNK), Some(&b"zstd..."[..]));
        assert_eq!(carry_over(&input, made.clone()).unwrap(), made, "already there: unchanged");
    }

    #[test]
    fn cache_key_bytes_only_with_mods() {
        // (the process-wide list is left alone: other tests compute open-cache keys meanwhile)
        assert!(key_bytes(&[]).is_none());
        assert!(cache_key_bytes().is_none(), "no mod enabled in tests");
        assert_eq!(key_bytes(&[("a".into(), "2.0.0".into()), ("b".into(), "1.0.0".into())]).unwrap(), b"a@2.0.0\nb@1.0.0\n");
    }

    /// Every card under OK_IDENTITY_DIR keeps the identity the code before mods gave it (only okVo left out).
    /// `OK_IDENTITY_DIR=<folder> cargo test --release --lib okmods::tests::identities_unchanged -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn identities_unchanged() {
        fn before(bytes: &[u8]) -> Option<String> {
            use sha2::Digest;
            if let Some(id) = crate::oklib::png_chunk(bytes, crate::oklib::IDENTITY_CHUNK) {
                return std::str::from_utf8(id).ok().filter(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())).map(str::to_owned);
            }
            if bytes.len() < 8 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" { return None; }
            let mut hash = sha2::Sha256::new();
            hash.update(&bytes[..8]);
            let mut pos = 8usize;
            while pos + 12 <= bytes.len() {
                let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().ok()?) as usize;
                let end = pos.checked_add(12 + len).filter(|e| *e <= bytes.len())?;
                let kind = &bytes[pos + 4..pos + 8];
                if kind != b"okVo" { hash.update(&bytes[pos..end]); }
                pos = end;
                if kind == b"IEND" { break; }
            }
            hash.update(&bytes[pos..]);
            Some(hash.finalize().iter().map(|b| format!("{b:02x}")).collect())
        }
        let dirs = std::env::var("OK_IDENTITY_DIR").expect("OK_IDENTITY_DIR");
        let mut files = Vec::new();
        fn walk(d: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
            let Ok(rd) = std::fs::read_dir(d) else { return };
            for e in rd.flatten() {
                let p = e.path();
                if p.is_dir() { walk(&p, out) } else if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("png")) { out.push(p) }
            }
        }
        for d in std::env::split_paths(&dirs) { walk(&d, &mut files); }
        let (mut same, mut differ) = (0, Vec::new());
        for f in &files {
            let Ok(bytes) = std::fs::read(f) else { continue };
            let (a, b) = (before(&bytes), crate::oklib::card_identity(&bytes));
            if a == b { same += 1 } else { differ.push(f.clone()) }
            if let Some(b) = &b { println!("{b}\t{}", f.display()); }
        }
        eprintln!("identities: {} cards, {same} unchanged, {} changed", files.len(), differ.len());
        assert!(differ.is_empty(), "changed: {differ:?}");
    }
}
