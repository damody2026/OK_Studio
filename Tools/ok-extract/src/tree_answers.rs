//! What an OK card's open asks of the whole mods tree, answered by the card itself (`okLt` PNG chunk).
//!
//! An OK card opens from the base library and its own pack (`okLc`), but a few questions of the open are asked of
//! every mod archive the library records (~7300): which list entries exist (the merged ChaList catalogue), which
//! archive declares a GUID, whether a MaterialEditor shader is registered. Each answer needed the whole tree read or
//! merged (0.7–1.6 s in a fresh process, more under load) although the card only asks a few dozen questions.
//!
//! The card carries those answers. They are recorded by opening the finished OK card from the library and its pack,
//! every saved outfit, with the questions logged (`record`); the open of the card then takes them (`lookup`) and
//! touches no archive of the tree. A question it was never asked is a gap of the OK card's strict open (okstrict.rs):
//! the open fails naming it, nothing is asked of the tree. Archive paths are kept relative to the mods folder and
//! rebased on the folder of the open.
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};

pub const CHUNK: &[u8; 4] = b"okLt";
const VERSION: u32 = 1;
const PLAIN_BUNDLES: &str = "plain-bundles";

pub type Table = HashMap<(String, Vec<u8>), Vec<u8>>;

#[derive(serde::Serialize, serde::Deserialize)]
struct Saved { version: u32, rows: Vec<(String, Vec<u8>, Vec<u8>)> }

static RECORDING: AtomicBool = AtomicBool::new(false);
/// (mods folder of the recorded open, answers).
static RECORD: Mutex<Option<(String, Table)>> = Mutex::new(None);

/// Starts logging the answers opens of `game_root` take from its mods tree.
pub fn begin(game_root: &Path) {
    *RECORD.lock().unwrap_or_else(|e| e.into_inner()) = Some((mods_prefix(&game_root.join("mods")), Table::new()));
    RECORDING.store(true, Ordering::Relaxed);
}

/// Stops logging; the `okLt` payload (zstd of the answers).
pub fn end() -> Result<Vec<u8>, String> {
    RECORDING.store(false, Ordering::Relaxed);
    let table = RECORD.lock().unwrap_or_else(|e| e.into_inner()).take().map(|r| r.1).unwrap_or_default();
    encode(table)
}

fn encode(table: Table) -> Result<Vec<u8>, String> {
    let mut rows: Vec<(String, Vec<u8>, Vec<u8>)> = table.into_iter().map(|((k, key), v)| (k, key, v)).collect();
    rows.sort();
    let raw = bincode::serialize(&Saved { version: VERSION, rows }).map_err(|e| e.to_string())?;
    zstd::stream::encode_all(&raw[..], 19).map_err(|e| e.to_string())
}

/// `card` (an OK card; any other stays as it is) answering, in a strict open, that no mod overrides a bundle it was never
/// asked about: it now wears the original game's clothes its open never read (appearance/properties.rs `dress`), from
/// bundles the recording could not know. With the game's mods at hand they are asked as ever: a mod's top she keeps
/// lives in a bundle of its own (raiden_shogun's baal_clothes went missing when this answered there too).
pub fn with_plain_bundles(card: &[u8]) -> Result<Vec<u8>, String> {
    let Some(table) = parse(card) else { return Ok(card.to_vec()) };
    let mut table = (*table).clone();
    table.insert((PLAIN_BUNDLES.to_owned(), Vec::new()), Vec::new());
    with_answers(card, &encode(table)?)
}

/// Whether the open's card took `with_plain_bundles`.
pub fn plain_bundles() -> bool { table().is_some_and(|t| t.contains_key(&(PLAIN_BUNDLES.to_owned(), Vec::new()))) }

pub fn recording() -> bool { RECORDING.load(Ordering::Relaxed) }

/// Logs one answer (the first one asked wins: an open asks the same question the same way every time).
pub fn record<T: serde::Serialize>(kind: &str, key: &[u8], value: &T) {
    if !recording() { return; }
    let Ok(value) = bincode::serialize(value) else { return };
    if let Some((_, table)) = RECORD.lock().unwrap_or_else(|e| e.into_inner()).as_mut() {
        table.entry((kind.to_owned(), key.to_vec())).or_insert(value);
    }
}

/// The answers carried by a card's bytes.
pub fn parse(card: &[u8]) -> Option<Arc<Table>> {
    let chunk = crate::oklib::png_chunk(card, CHUNK)?;
    let raw = zstd::stream::decode_all(chunk).ok()?;
    let saved: Saved = bincode::deserialize(&raw).ok()?;
    (saved.version == VERSION).then(|| Arc::new(saved.rows.into_iter().map(|(k, key, v)| ((k, key), v)).collect()))
}

/// The open's card answers (None: the card has none, or answers are being recorded).
pub fn table() -> Option<Arc<Table>> {
    if recording() { return None; }
    crate::oklib::pack_scope()?.tree.clone()
}

/// A question the card has no answer to: under an OK card's strict open (okstrict.rs) a gap, and the caller answers it
/// as nothing, never from the tree. False otherwise (the caller asks the tree, recording the answer).
pub fn unanswered(kind: &str, key: &[u8]) -> bool {
    if recording() || crate::okstrict::active().is_none() { return false; }
    // Say how many when the question holds a list: one gap whose text named twenty guids read as "lacks 1 thing(s)"
    // and sent someone looking for a single missing mod (2026-11-19, C000 in the reader).
    crate::okstrict::gap(|| {
        let text = String::from_utf8_lossy(key);
        let n = text.split('\n').filter(|s| !s.is_empty()).count();
        // Which of the names no answer of hers was ever asked about: a set question is answered from the answers that
        // together cover it (`lookup_covered`), so of twenty guids the one that is new is the whole gap, and the
        // reader's error named all twenty (2026-11-25, a bred child whose mix asked about a mod neither parent used).
        if n > 1 {
            let missing = uncovered(kind, key);
            let tail = if missing.is_empty() { String::new() } else { format!(", never asked: {}", missing.join(",")) };
            format!("okLt {kind} ({n}{tail}): {}", text.replace('\n', ","))
        } else { format!("okLt {kind} {}", text.replace('\n', ",")) }
    });
    true
}

/// The names of a set question (one a line) that no answer the card carries was asked about.
pub fn uncovered(kind: &str, key: &[u8]) -> Vec<String> {
    let Some(table) = table() else { return Vec::new() };
    let lines = |text: &'_ [u8]| text.split(|b| *b == b'\n').filter(|l| !l.is_empty()).map(<[u8]>::to_vec).collect::<Vec<_>>();
    let asked: std::collections::HashSet<Vec<u8>> = table.iter().filter(|((k, _), _)| k == kind).flat_map(|((_, q), _)| lines(q)).collect();
    let mut out: Vec<String> = lines(key).into_iter().filter(|n| !asked.contains(n))
        .map(|n| String::from_utf8_lossy(&n).into_owned()).collect();
    out.sort();
    out.dedup();
    out
}

/// The card's answer to a question, if it carries one.
pub fn lookup<T: serde::de::DeserializeOwned>(kind: &str, key: &[u8]) -> Option<T> {
    let table = table()?;
    let value = table.get(&(kind.to_owned(), key.to_vec()))?;
    let _spot = crate::profile::spot("tree answer");
    bincode::deserialize(value).ok()
}

/// The card's answer to a question about a set of names (`key`, one a line), or the answer it recorded for a larger set:
/// a card that took a mod's piece off after its answers were recorded (the street's clothes, appearance/properties.rs
/// `dress`) asks about fewer mods. The answer can name more than was asked.
pub fn lookup_within<T: serde::de::DeserializeOwned>(kind: &str, key: &[u8]) -> Option<T> {
    if let Some(found) = lookup(kind, key) { return Some(found); }
    let table = table()?;
    let lines = |text: &'_ [u8]| text.split(|b| *b == b'\n').map(<[u8]>::to_vec).collect::<std::collections::HashSet<_>>();
    let wanted = lines(key);
    let (_, value) = table.iter().find(|((k, asked), _)| k == kind && wanted.is_subset(&lines(asked)))?;
    bincode::deserialize(value).ok()
}

/// `lookup_within` for a question whose answer is a list about the names asked (which of them a migration strips,
/// which archive declares each): when no one answer covers every name, the answers of the questions that together
/// cover them, put together. A card wearing another card's outfit (okclothes) asks about her names and the outfit's
/// at once, and each card recorded only its own (2026-11-21).
pub fn lookup_covered<E: serde::de::DeserializeOwned + Ord>(kind: &str, key: &[u8]) -> Option<Vec<E>> {
    if let Some(found) = lookup_within::<Vec<E>>(kind, key) { return Some(found); }
    let table = table()?;
    let lines = |text: &'_ [u8]| text.split(|b| *b == b'\n').filter(|l| !l.is_empty()).map(<[u8]>::to_vec).collect::<std::collections::HashSet<_>>();
    let wanted = lines(key);
    if wanted.is_empty() { return None; }
    let mut covered = std::collections::HashSet::new();
    let mut out: Vec<E> = Vec::new();
    for ((k, asked), value) in table.iter() {
        if k != kind { continue; }
        let asked = lines(asked);
        if asked.is_disjoint(&wanted) { continue; }
        let Ok(part) = bincode::deserialize::<Vec<E>>(value) else { continue };
        covered.extend(asked.intersection(&wanted).cloned());
        out.extend(part);
    }
    if !wanted.is_subset(&covered) { return None; }
    out.sort();
    out.dedup();
    Some(out)
}

/// The card's answers with `other`'s (an `okLt` payload, e.g. an outfit's from another OK card) added: its own answer
/// wins where both answer one question.
pub fn merge(card: &[u8], other: &[u8]) -> Result<Vec<u8>, String> {
    let read = |chunk: &[u8]| -> Result<Table, String> {
        let raw = zstd::stream::decode_all(chunk).map_err(|e| e.to_string())?;
        let saved: Saved = bincode::deserialize(&raw).map_err(|e| e.to_string())?;
        if saved.version != VERSION { return Err(format!("okLt version {}", saved.version)); }
        Ok(saved.rows.into_iter().map(|(k, key, v)| ((k, key), v)).collect())
    };
    let mut table = match crate::oklib::png_chunk(card, CHUNK) { Some(chunk) => read(chunk)?, None => Table::new() };
    for (key, value) in read(other)? { table.entry(key).or_insert(value); }
    with_answers(card, &encode(table)?)
}

fn read_payload(chunk: &[u8]) -> Result<Table, String> {
    let raw = zstd::stream::decode_all(chunk).map_err(|e| e.to_string())?;
    let saved: Saved = bincode::deserialize(&raw).map_err(|e| e.to_string())?;
    if saved.version != VERSION { return Err(format!("okLt version {}", saved.version)); }
    Ok(saved.rows.into_iter().map(|(k, key, v)| ((k, key), v)).collect())
}

/// `okLt` payloads merged into one in precedence order (the first answer to a question wins); None when there are none.
pub fn merge_payloads(payloads: &[&[u8]]) -> Result<Option<Vec<u8>>, String> {
    if payloads.is_empty() { return Ok(None); }
    let mut table = Table::new();
    for p in payloads { for (key, value) in read_payload(p)? { table.entry(key).or_insert(value); } }
    encode(table).map(Some)
}

/// The answers of `full` that `parents` (merged in precedence order) lack or answer otherwise; None: none.
pub fn delta(full: &[u8], parents: &[&[u8]]) -> Result<Option<Vec<u8>>, String> {
    let mut theirs = Table::new();
    for p in parents { for (key, value) in read_payload(p)? { theirs.entry(key).or_insert(value); } }
    let own: Table = read_payload(full)?.into_iter().filter(|(k, v)| theirs.get(k) != Some(v)).collect();
    if own.is_empty() { return Ok(None); }
    encode(own).map(Some)
}

/// How many outfits (coordinates) the card saves.
pub fn outfit_count(card: &[u8]) -> usize {
    crate::card::parse_card_bytes_mode(card, 0, false).map(|c| c.coordinate_count).unwrap_or(1).max(1)
}

/// A mods folder as the text archive paths under it start with.
fn mods_prefix(mods_dir: &Path) -> String { mods_dir.to_string_lossy().into_owned() }

/// An archive path under the recorded open's mods folder, relative to it (None: elsewhere, not recordable). Compared
/// as gamefs keys compare (case and separators do not matter: a tree walk and a listing spell one archive differently).
pub fn relative(path: &Path) -> Option<String> {
    let record = RECORD.lock().unwrap_or_else(|e| e.into_inner());
    let (prefix, _) = record.as_ref()?;
    let text = path.to_string_lossy();
    if let Some(rest) = text.strip_prefix(prefix.as_str()) { return Some(rest.to_owned()); }
    let (path, prefix) = (crate::gamefs::normalize(path), crate::gamefs::normalize(Path::new(prefix)));
    path.strip_prefix(prefix.as_str()).filter(|rest| rest.starts_with('/')).map(str::to_owned)
}

/// A relative archive path rebased on this open's mods folder (the text the tree walk gives for it).
pub fn rebase(mods_dir: &Path, relative: &str) -> PathBuf {
    PathBuf::from(format!("{}{relative}", mods_prefix(mods_dir)))
}

/// `bytes` with `okLt` set to `payload` (right before IEND, replacing one it had). A card without `okId` gets the
/// identity it had before, so names, saves and caches that know it by its bytes keep knowing it.
pub fn with_answers(bytes: &[u8], payload: &[u8]) -> Result<Vec<u8>, String> { with_chunk(bytes, CHUNK, payload) }

/// `bytes` with chunk `kind` set to `payload` (right before IEND, replacing one it had), keeping the card's identity
/// as `with_answers` does.
pub fn with_chunk(bytes: &[u8], kind: &[u8; 4], payload: &[u8]) -> Result<Vec<u8>, String> {
    let replaced = kind;
    let identity = crate::oklib::card_identity(bytes);
    let had_identity = crate::oklib::png_chunk(bytes, crate::oklib::IDENTITY_CHUNK).is_some();
    if bytes.len() < 8 || &bytes[..8] != b"\x89PNG\r\n\x1a\n" { return Err("not a PNG card".into()); }
    let mut out = bytes[..8].to_vec();
    let mut pos = 8usize;
    let mut done = None;
    while pos + 12 <= bytes.len() {
        let len = u32::from_be_bytes(bytes[pos..pos + 4].try_into().unwrap()) as usize;
        let end = pos.checked_add(12 + len).filter(|e| *e <= bytes.len()).ok_or("truncated PNG chunk")?;
        let kind = &bytes[pos + 4..pos + 8];
        if kind == b"IEND" {
            let mut chunk = replaced.to_vec();
            chunk.extend_from_slice(payload);
            out.extend_from_slice(&(payload.len() as u32).to_be_bytes());
            out.extend_from_slice(&chunk);
            out.extend_from_slice(&crc32fast::hash(&chunk).to_be_bytes());
            out.extend_from_slice(&bytes[pos..]);
            done = Some(out);
            break;
        }
        if kind != replaced { out.extend_from_slice(&bytes[pos..end]); }
        pos = end;
    }
    let out = done.ok_or("missing PNG IEND")?;
    match identity { Some(id) if !had_identity => crate::oklib::with_card_identity(&out, &id), _ => Ok(out) }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn png(chunks: &[(&[u8; 4], &[u8])]) -> Vec<u8> {
        let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
        for (kind, data) in chunks {
            out.extend_from_slice(&(data.len() as u32).to_be_bytes());
            let mut c = kind.to_vec();
            c.extend_from_slice(data);
            out.extend_from_slice(&c);
            out.extend_from_slice(&crc32fast::hash(&c).to_be_bytes());
        }
        out
    }
    #[test]
    fn answers_replace_and_keep_identity() {
        let card = png(&[(b"IHDR", &[0; 13]), (b"okLb", b"{}"), (b"IEND", b"")]);
        let id = crate::oklib::card_identity(&card).unwrap();
        let a = with_answers(&card, b"one").unwrap();
        assert_eq!(crate::oklib::png_chunk(&a, CHUNK), Some(&b"one"[..]));
        assert_eq!(crate::oklib::card_identity(&a).unwrap(), id);
        let b = with_answers(&a, b"two").unwrap();
        assert_eq!(crate::oklib::png_chunk(&b, CHUNK), Some(&b"two"[..]));
        assert_eq!(crate::oklib::card_identity(&b).unwrap(), id);
        assert_eq!(b.windows(4).filter(|w| *w == CHUNK).count(), 1);
    }
}
