//! What mods store in an OK card, and the card's identity (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.2, §6.12).
//! Shared by ok-extract (`okmods.rs`, `oklib::card_identity`) and the OK mod host, so both read and write the same bytes.
//!
//! - `okMx`: msgpack map `{ mod_id: { version: u32, requires: { id, version }, data: bin } }`, one section per mod
//!   (ExtendedSave's extended data). A section the running build does not know is carried byte for byte: the map is
//!   kept as raw key and value spans and only the section a mod writes is encoded again.
//! - `okMr` (feature `resources`): the mods' resources (textures, masks, curves) by content: zstd of a msgpack map
//!   `{ sha256 hex: bin }`, referenced from `okMx` data. One copy however many mods use it.
//! - The identity: the card's `okId` chunk (64 hex digits), else the sha256 of the card without `okVo` (her own TTS
//!   voice), `okMx` and `okMr` (`IDENTITY_EXCLUDED`). The same rule as Tools/prepare_street_social_selection.lua and
//!   Source/OpenKoikatsu/OKCardIdentityCore.inl. Writing a chunk with `with_chunk` gives a card without `okId` the
//!   identity it had, so saving mod data never makes her a stranger.

pub const PNG_SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";
/// The card's identity carried over when it is made again (oklib.rs `IDENTITY_CHUNK`).
pub const IDENTITY_CHUNK: &[u8; 4] = b"okId";
/// Mod data (§6.2).
pub const DATA_CHUNK: &[u8; 4] = b"okMx";
/// Mod resources by content (§6.12).
pub const RESOURCE_CHUNK: &[u8; 4] = b"okMr";
/// Chunks a card's identity leaves out: her own TTS voice and the mods' data and resources.
pub const IDENTITY_EXCLUDED: [&[u8; 4]; 3] = [b"okVo", DATA_CHUNK, RESOURCE_CHUNK];

// ------------------------------------------------------------------------------------------------- PNG chunks

/// The payload of the first chunk of `kind` before IEND.
pub fn chunk<'a>(bytes: &'a [u8], kind: &[u8; 4]) -> Option<&'a [u8]> {
    if bytes.len() < 8 || &bytes[..8] != PNG_SIGNATURE { return None; }
    let mut pos = 8usize;
    while pos + 12 <= bytes.len() {
        let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().ok()?) as usize;
        if &bytes[pos + 4..pos + 8] == kind { return bytes.get(pos + 8..pos + 8 + len); }
        if &bytes[pos + 4..pos + 8] == b"IEND" { return None; }
        pos += 12 + len;
    }
    None
}

/// A card's identity (see the crate docs). None: not a PNG, a chunk runs past the end, or an `okId` that is not 64 hex.
pub fn card_identity(bytes: &[u8]) -> Option<String> {
    use sha2::Digest;
    if let Some(id) = chunk(bytes, IDENTITY_CHUNK) {
        return std::str::from_utf8(id).ok().filter(|s| s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit())).map(str::to_owned);
    }
    if bytes.len() < 8 || &bytes[..8] != PNG_SIGNATURE { return None; }
    let mut hash = sha2::Sha256::new();
    hash.update(&bytes[..8]);
    let mut pos = 8usize;
    while pos + 12 <= bytes.len() {
        let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().ok()?) as usize;
        let end = pos.checked_add(12 + len).filter(|e| *e <= bytes.len())?;
        let kind = &bytes[pos + 4..pos + 8];
        if !IDENTITY_EXCLUDED.iter().any(|k| &k[..] == kind) { hash.update(&bytes[pos..end]); }
        pos = end;
        if kind == b"IEND" { break; }
    }
    hash.update(&bytes[pos..]);
    Some(hash.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

fn push_chunk(out: &mut Vec<u8>, kind: &[u8; 4], payload: &[u8]) {
    let mut c = kind.to_vec();
    c.extend_from_slice(payload);
    out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    out.extend_from_slice(&c);
    out.extend_from_slice(&crc32fast::hash(&c).to_be_bytes());
}

/// The card with chunk `kind` set to `payload` (right before IEND; an existing one of that kind removed), and nothing
/// else changed.
pub fn with_chunk_raw(bytes: &[u8], kind: &[u8; 4], payload: Option<&[u8]>) -> Result<Vec<u8>, String> {
    if bytes.len() < 8 || &bytes[..8] != PNG_SIGNATURE { return Err("not a PNG card".into()); }
    if payload.is_some_and(|p| p.len() > 0x7fff_ffff) { return Err("chunk payload over the PNG limit".into()); }
    let mut out = Vec::with_capacity(bytes.len() + payload.map_or(0, |p| p.len() + 12));
    out.extend_from_slice(&bytes[..8]);
    let mut pos = 8usize;
    while pos + 12 <= bytes.len() {
        let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
        let end = pos.checked_add(12 + len).filter(|e| *e <= bytes.len()).ok_or("truncated PNG chunk")?;
        let this = &bytes[pos + 4..pos + 8];
        if this == b"IEND" {
            if let Some(p) = payload { push_chunk(&mut out, kind, p); }
            out.extend_from_slice(&bytes[pos..]);
            return Ok(out);
        }
        if this != kind { out.extend_from_slice(&bytes[pos..end]); }
        pos = end;
    }
    Err("missing PNG IEND".into())
}

/// The card with its `okId` set to `id` (oklib.rs `with_card_identity`).
pub fn with_card_identity(bytes: &[u8], id: &str) -> Result<Vec<u8>, String> {
    with_chunk_raw(bytes, IDENTITY_CHUNK, Some(id.as_bytes()))
}

/// `with_chunk_raw` keeping the card's identity: a card without `okId` gets the one it had before the write.
pub fn with_chunk(bytes: &[u8], kind: &[u8; 4], payload: Option<&[u8]>) -> Result<Vec<u8>, String> {
    let had = chunk(bytes, IDENTITY_CHUNK).is_some();
    let identity = if had { None } else { card_identity(bytes) };
    let out = with_chunk_raw(bytes, kind, payload)?;
    match identity { Some(id) => with_card_identity(&out, &id), None => Ok(out) }
}

// ------------------------------------------------------------------------------------------------- okMx

/// What a mod's section asks of the reader: the mod and the version that wrote it (§6.12 "requires").
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Requires { pub id: String, pub version: String }

/// One mod's section of `okMx`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Section { pub version: u32, pub requires: Option<Requires>, pub data: Vec<u8> }

impl Section {
    pub fn encode(&self) -> Vec<u8> {
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
    pub fn decode(raw: &[u8]) -> Result<Section, String> {
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
    match chunk(card, DATA_CHUNK) { Some(p) => ModData::decode(p), None => Ok(ModData::default()) }
}
/// The card with this `okMx` (none when empty), its identity kept.
pub fn with_data(card: &[u8], data: &ModData) -> Result<Vec<u8>, String> {
    if data.is_empty() {
        if chunk(card, DATA_CHUNK).is_none() { return Ok(card.to_vec()); }
        with_chunk(card, DATA_CHUNK, None)
    } else {
        with_chunk(card, DATA_CHUNK, Some(&data.encode()))
    }
}

// ------------------------------------------------------------------------------------------------- okMr

/// The card's `okMr`: resources by sha256 hex.
#[cfg(feature = "resources")]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Resources { pub by_hash: std::collections::BTreeMap<String, Vec<u8>> }

#[cfg(feature = "resources")]
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

#[cfg(feature = "resources")]
pub fn read_resources(card: &[u8]) -> Result<Resources, String> {
    match chunk(card, RESOURCE_CHUNK) { Some(p) => Resources::decode(p), None => Ok(Resources::default()) }
}
#[cfg(feature = "resources")]
pub fn with_resources(card: &[u8], resources: &Resources) -> Result<Vec<u8>, String> {
    if resources.by_hash.is_empty() {
        if chunk(card, RESOURCE_CHUNK).is_none() { return Ok(card.to_vec()); }
        with_chunk(card, RESOURCE_CHUNK, None)
    } else {
        with_chunk(card, RESOURCE_CHUNK, Some(&resources.encode()?))
    }
}

/// `made` (a card made again from `input`) with `input`'s mod data and resources, exactly as they were: a remade or
/// converted card keeps what mods stored in it (ExtendedSave's "unknown data is kept").
pub fn carry_over(input: &[u8], made: Vec<u8>) -> Result<Vec<u8>, String> {
    let mut out = made;
    for kind in [DATA_CHUNK, RESOURCE_CHUNK] {
        if let Some(payload) = chunk(input, kind) {
            if chunk(&out, kind) != Some(payload) { out = with_chunk_raw(&out, kind, Some(payload))?; }
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn png(chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
        let mut out = PNG_SIGNATURE.to_vec();
        for (kind, data) in chunks { push_chunk(&mut out, kind, data); }
        out
    }
    fn card() -> Vec<u8> { png(&[(b"IHDR", &[0; 13]), (b"IDAT", b"pixels"), (b"IEND", b"")]) }

    #[test]
    fn identity_leaves_out_voice_and_mod_chunks() {
        let plain = card();
        let id = card_identity(&plain).unwrap();
        let mut data = ModData::default();
        data.set("com.example.a", &Section { version: 1, requires: None, data: b"hello".to_vec() });
        let with = with_data(&plain, &data).unwrap();
        assert_eq!(card_identity(&with).unwrap(), id);
        assert_eq!(chunk(&with, IDENTITY_CHUNK), Some(id.as_bytes()), "writing gave the card its identity as okId");
        let bare = png(&[(b"IHDR", &[0; 13]), (b"IDAT", b"pixels"), (DATA_CHUNK, b"\x80"), (RESOURCE_CHUNK, b"x"), (b"okVo", b"v"), (b"IEND", b"")]);
        assert_eq!(card_identity(&bare).unwrap(), id);
        // Emptied: the chunk goes, the identity stays.
        let none = with_data(&with, &ModData::default()).unwrap();
        assert!(chunk(&none, DATA_CHUNK).is_none());
        assert_eq!(card_identity(&none).unwrap(), id);
    }

    #[test]
    fn unknown_sections_are_kept_byte_for_byte() {
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

    #[cfg(feature = "resources")]
    #[test]
    fn resources_dedup_and_round_trip() {
        let mut res = Resources::default();
        let a = res.add(b"same");
        assert_eq!(a, res.add(b"same"));
        assert_eq!(res.by_hash.len(), 1);
        let card = with_resources(&card(), &res).unwrap();
        let back = read_resources(&card).unwrap();
        assert_eq!(back.get(&a), Some(&b"same"[..]));
        assert_eq!(back.total_bytes(), 4);
        let id = card_identity(&card).unwrap();
        let none = with_resources(&card, &Resources::default()).unwrap();
        assert!(chunk(&none, RESOURCE_CHUNK).is_none());
        assert_eq!(card_identity(&none).unwrap(), id);
    }

    #[test]
    fn carry_over_keeps_both_chunks_exactly() {
        let input = png(&[(b"IHDR", &[0; 13]), (DATA_CHUNK, b"\x81\xa1a\x80"), (RESOURCE_CHUNK, b"zstd..."), (b"IEND", b"")]);
        let made = carry_over(&input, card()).unwrap();
        assert_eq!(chunk(&made, DATA_CHUNK), Some(&b"\x81\xa1a\x80"[..]));
        assert_eq!(chunk(&made, RESOURCE_CHUNK), Some(&b"zstd..."[..]));
        assert_eq!(carry_over(&input, made.clone()).unwrap(), made, "already there: unchanged");
    }
}

/// Standard base64 with padding (RFC 4648), how mod data travels in the host's JSON (`data_b64`). Here so ok-extract
/// needs no extra crate for it.
pub mod b64 {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    pub fn encode(bytes: &[u8]) -> String {
        let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
        for c in bytes.chunks(3) {
            let n = (u32::from(c[0]) << 16) | (u32::from(*c.get(1).unwrap_or(&0)) << 8) | u32::from(*c.get(2).unwrap_or(&0));
            for i in 0..4 {
                if i <= c.len() { out.push(ALPHABET[(n >> (18 - 6 * i) & 63) as usize] as char) } else { out.push('=') }
            }
        }
        out
    }
    pub fn decode(text: &str) -> Result<Vec<u8>, String> {
        let text = text.trim_end_matches('=');
        let mut out = Vec::with_capacity(text.len() * 3 / 4);
        let (mut acc, mut bits) = (0u32, 0u32);
        for ch in text.bytes() {
            let v = ALPHABET.iter().position(|&a| a == ch).ok_or_else(|| format!("not base64: {:?}", ch as char))? as u32;
            acc = (acc << 6) | v;
            bits += 6;
            if bits >= 8 { bits -= 8; out.push((acc >> bits) as u8); acc &= (1 << bits) - 1; }
        }
        Ok(out)
    }
    #[cfg(test)]
    #[test]
    fn round_trips() {
        for n in 0..10 { let b: Vec<u8> = (0..n).map(|i| (i * 37 + 5) as u8).collect(); assert_eq!(decode(&encode(&b)).unwrap(), b); }
        assert_eq!(encode(b"hello"), "aGVsbG8=");
    }
}
