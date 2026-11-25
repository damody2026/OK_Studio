//! The mods tree's maps, carried **by the base library** as a database and built once by
//! `--oklib shared-ignore` (or `--oklib mods-index`): which archive declares each GUID, which archive replaces
//! each `abdata/...unity3d`, and which archives declare an UncensorSelector body, penis or balls.
//!
//! An open answers both from here with point queries. It never reads the installation's ~7300 manifests or central
//! directories, and it keeps **no per-card cache** (the user, 2026-11-24: an open must never read every mod, and
//! nothing is cached *per card*; a shared resource's own index is not that kind of cache -- "共用資源的快取是可以接受
//! 的，本來就要做好 db"). Before this, an original card's open reached `mods::tree_guid_index` and
//! `mods::build_override_index`, which read the whole tree (~2.8 s cold) and kept the answers per installation in
//! `mods/.ok_tree_guid_index.bin` and `mods/.ok_override_index.tsv`.
//!
//! The database is library data, like `shared_mods.txt`: the same command that regenerates that list regenerates it,
//! from one walk of the tree at library-build time. A GUID or a bundle it does not name is a **gap** the open reports
//! (`OKMODS unanswered`), not a reason to walk the tree. It is `<lib>/mods_index.db`, SQLite: `archive` (every zipmod
//! of that installation, in walk order) plus `guid`, `override`, `migration` and `uncensor` (rows pointing at
//! archives). `uncensor` was added on 2026-11-25 **without bumping the schema**: a database built before it simply
//! has no such table, the open reads those archives itself as it always did, and every other query keeps working --
//! a bump would have made every tree's index unusable until it was rebuilt, for a table only one caller needs.
//! Nothing is loaded whole: a lookup is one indexed query, so the reader's start and an open pay for the GUIDs they
//! ask about and nothing else.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, RwLock};

use rusqlite::{Connection, OpenFlags};

pub const DB_FILE: &str = "mods_index.db";
/// Bumped when the tables change: an older file is ignored (and reported), never half-read.
pub const SCHEMA: i64 = 2;

/// What state the library's index is in. One judgement for the two callers that need it: the compatibility gate
/// (`resources.rs`, which turns it into `problems[]`) and the open path itself -- `card_absent_mods` must answer
/// "undeterminable" rather than count every GUID of the card as missing when the index is not usable. Two separate
/// judgements would drift apart, and the drift is what the packaged build hit on 2026-11-24 (a schema 1 library under
/// a build needing schema 2 read as 0 GUIDs, so Illya "lacked 42 mods" and the card opened anyway).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IndexHealth {
    /// No `mods_index.db` beside the library.
    Missing,
    /// There is a file, but SQLite cannot open or read it (truncated, not a database).
    Unreadable { detail: String },
    /// Built by another build of this program.
    Schema { found: i64, want: i64 },
    /// Readable and current, but it names no GUID at all: a degenerate index, never "this machine really has no mods".
    Empty,
    Ok { guids: i64, overrides: i64, migrations: i64 },
}

impl IndexHealth {
    pub fn is_ok(&self) -> bool { matches!(self, IndexHealth::Ok { .. }) }
}

/// The state of one library's index, read straight from the file (not through the memoized `open`, which drops the
/// schema it found). Memoized per library path: it is a shared resource's own metadata, read once per process.
pub fn health_of(lib: &Path) -> IndexHealth {
    static SEEN: OnceLock<RwLock<Vec<(PathBuf, IndexHealth)>>> = OnceLock::new();
    let slot = SEEN.get_or_init(|| RwLock::new(Vec::new()));
    if let Some((_, hit)) = slot.read().unwrap_or_else(|e| e.into_inner()).iter().find(|(p, _)| p == lib) {
        return hit.clone();
    }
    let answer = read_health(lib);
    let mut slot = slot.write().unwrap_or_else(|e| e.into_inner());
    slot.retain(|(p, _)| p != lib);
    slot.push((lib.to_path_buf(), answer.clone()));
    answer
}

fn read_health(lib: &Path) -> IndexHealth {
    let path = lib.join(DB_FILE);
    if !path.is_file() { return IndexHealth::Missing; }
    let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    let conn = match Connection::open_with_flags(&path, flags) {
        Ok(conn) => conn,
        Err(e) => return IndexHealth::Unreadable { detail: e.to_string() },
    };
    let schema: i64 = match conn.query_row("SELECT value FROM meta WHERE key='schema'", [], |r| r.get::<_, String>(0)) {
        Ok(v) => v.parse().unwrap_or(0),
        Err(e) => return IndexHealth::Unreadable { detail: e.to_string() },
    };
    if schema != SCHEMA { return IndexHealth::Schema { found: schema, want: SCHEMA }; }
    let count = |sql: &str| -> i64 { conn.query_row(sql, [], |r| r.get(0)).unwrap_or(-1) };
    let guids = count("SELECT count(DISTINCT guid) FROM guid");
    if guids < 0 { return IndexHealth::Unreadable { detail: "guid table unreadable".into() }; }
    if guids == 0 { return IndexHealth::Empty; }
    IndexHealth::Ok {
        guids,
        overrides: count("SELECT count(*) FROM override").max(0),
        migrations: count("SELECT count(*) FROM migration").max(0),
    }
}

/// Does `lib`'s index belong to this mods tree? For the compatibility gate, which runs with **no library active**, so
/// it cannot use `serves` (that asks the active one and would answer false for every library, reporting
/// `mods_index_foreign` about the very tree the index was built from -- scenario 10a of the plan, the false alarm).
///
/// The path the database records answers it without touching the file system. The fallback **lists the tree**, which
/// an open may never do, so only the CLI and the C ABI call this, and only when a game directory is configured.
pub fn index_covers(lib: &Path, mods_dir: &Path) -> bool {
    let Some(db) = open(lib) else { return false };
    if !db.built_from.is_empty() && db.built_from == tree_key(mods_dir) { return true; }
    crate::mods::all_zipmods(mods_dir).iter().any(|z| db.knows(&relative(mods_dir, z).to_ascii_lowercase()))
}

/// The active library's index state ( `Missing` when no library is active).
pub fn health() -> IndexHealth {
    match crate::oklib::active_dir() { Some(lib) => health_of(&lib), None => IndexHealth::Missing }
}

#[derive(Default)]
pub struct Index {
    /// every zipmod of the installation, relative to `mods/`, in walk order
    pub archives: Vec<String>,
    /// lower-case GUID -> every archive declaring it, in walk order: (path relative to `mods/`, declared version)
    pub guids: HashMap<String, Vec<(String, String)>>,
    /// lower-case `abdata/...unity3d` -> every archive shipping it, in walk order
    pub overrides: HashMap<String, Vec<String>>,
    /// `(guidOld, migrationType, archive)`: which legacy ids the installation migrates away, and who says so. Not a
    /// resolution path (nothing is stripped because of this) -- it is how an open tells "this id is gone by design"
    /// from "this mod is missing", so a `StripAll`-ed id does not drown the real gaps in `OKMODS unanswered`.
    pub migrations: Vec<(String, String, String)>,
    /// `(archive, its UncensorSelector manifests)` for the few archives that declare a body, penis or balls, in walk
    /// order. The third map an open used to build by reading every archive: `mods::uncensor_sources` opened all ~7300
    /// of them for these ~25 answers, twice per original card (the installation's tree and the library's recorded
    /// one), ~1.4 s of CPU and 7300 cold directory touches on a card that needs none of it (2026-11-25).
    pub uncensor: Vec<(String, Vec<String>)>,
}

/// Why every candidate and not the winner: an original card's open does not see the whole installation. It sees its
/// own archives plus the shared mods (`gamefs::NarrowMods`), and the maps it used to build were built over that
/// narrow tree, so the archive that wins there is often not the one that wins across all ~7300. Keeping the global
/// winner only changed six of the twenty-one baseline outfits (2026-11-24). The open picks the first candidate its
/// view actually serves.

/// Walks the tree and reads every archive once: **library build only** (`--oklib shared-ignore`), never an open.
pub fn build(mods_dir: &Path) -> Index {
    use rayon::prelude::*;
    // Walk order, not sorted: both maps this replaces let the FIRST archive of the walk win (the override map by
    // `or_insert`, the GUID map by replacing only on a strictly higher rank), so sorting here handed a bundle
    // shipped by two archives to a different one and six original-card outfits came out different.
    let zips = crate::mods::all_zipmods(mods_dir);
    type Row = (String, Vec<(String, String)>, Vec<String>, Vec<(String, String)>, Vec<String>);
    let rows: Vec<Row> = zips
        .par_iter()
        .map(|zip| {
            let rel = relative(mods_dir, zip);
            (rel, crate::mods::guids_and_versions_from_zipmod(zip), crate::mods::zipmod_override_keys(zip),
                crate::mods::migrations_from_zipmod(zip), crate::mods::uncensor_manifest_xmls(zip))
        })
        .collect();
    let mut index = Index::default();
    for (rel, guids, overrides, migrations, uncensor) in rows {
        if !uncensor.is_empty() { index.uncensor.push((rel.clone(), uncensor)); }
        for (old, kind) in migrations {
            index.migrations.push((old.to_ascii_lowercase(), kind, rel.clone()));
        }
        for (guid, version) in guids {
            index.guids.entry(guid.to_ascii_lowercase()).or_default().push((rel.clone(), version));
        }
        for name in overrides {
            index.overrides.entry(name).or_default().push(rel.clone());
        }
        index.archives.push(rel);
    }
    index
}

fn relative(mods_dir: &Path, zip: &Path) -> String {
    zip.strip_prefix(mods_dir).unwrap_or(zip).to_string_lossy().replace('\\', "/")
}

/// How a `mods/` folder is named in `meta.mods_dir`: absolute, forward slashes, no trailing one, ASCII-folded.
fn tree_key(mods_dir: &Path) -> String {
    let absolute = std::path::absolute(mods_dir).unwrap_or_else(|_| mods_dir.to_path_buf());
    absolute.to_string_lossy().replace('\\', "/").trim_end_matches('/').to_ascii_lowercase()
}

/// Writes the database into the library, atomically (built beside it, then renamed over). Called by `shared-ignore`
/// and `mods-index`; returns how many GUID and override rows it holds.
pub fn write(lib: &Path, mods_dir: &Path, index: &Index) -> Result<(usize, usize), String> {
    let final_path = lib.join(DB_FILE);
    let building = lib.join(format!("{DB_FILE}.new"));
    for stale in [&building, &lib.join(format!("{DB_FILE}.new-journal"))] { let _ = std::fs::remove_file(stale); }
    let mut conn = Connection::open(&building).map_err(|e| format!("{}: {e}", building.display()))?;
    let err = |e: rusqlite::Error| format!("{}: {e}", building.display());
    // No WAL: the file is read-only once published, and a sidecar -wal/-shm would have to travel with the library.
    conn.pragma_update(None, "journal_mode", "off").map_err(err)?;
    conn.pragma_update(None, "synchronous", "off").map_err(err)?;
    conn.execute_batch(
        "CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
         CREATE TABLE archive(id INTEGER PRIMARY KEY, path TEXT NOT NULL COLLATE NOCASE UNIQUE);
         CREATE TABLE guid(guid TEXT NOT NULL COLLATE NOCASE, version TEXT NOT NULL, archive INTEGER NOT NULL);
         CREATE INDEX guid_lookup ON guid(guid);
         CREATE TABLE override(bundle TEXT NOT NULL COLLATE NOCASE, archive INTEGER NOT NULL);
         CREATE INDEX override_lookup ON override(bundle);
         CREATE TABLE migration(guid_old TEXT NOT NULL COLLATE NOCASE, kind TEXT NOT NULL, archive INTEGER NOT NULL);
         CREATE INDEX migration_lookup ON migration(guid_old);
         CREATE TABLE uncensor(archive INTEGER NOT NULL, xml TEXT NOT NULL);
         CREATE INDEX uncensor_lookup ON uncensor(archive);",
    ).map_err(err)?;
    // `archive.id` IS the walk position, so every query orders candidates by it and no row carries an order of its own.
    let mut ids: HashMap<&str, i64> = HashMap::new();
    let (mut guid_rows, mut override_rows) = (0usize, 0usize);
    {
        let tx = conn.transaction().map_err(err)?;
        {
            let mut archive = tx.prepare("INSERT INTO archive(id, path) VALUES(?1, ?2)").map_err(err)?;
            for (i, rel) in index.archives.iter().enumerate() {
                let id = i as i64 + 1;
                archive.execute(rusqlite::params![id, rel]).map_err(err)?;
                ids.insert(rel.as_str(), id);
            }
            let mut guid = tx.prepare("INSERT INTO guid(guid, version, archive) VALUES(?1, ?2, ?3)").map_err(err)?;
            let mut guids: Vec<_> = index.guids.iter().collect();
            guids.sort_by(|a, b| a.0.cmp(b.0));
            for (name, candidates) in guids {
                for (rel, version) in candidates {
                    let Some(id) = ids.get(rel.as_str()) else { continue };
                    guid.execute(rusqlite::params![name, version, id]).map_err(err)?;
                    guid_rows += 1;
                }
            }
            let mut over = tx.prepare("INSERT INTO override(bundle, archive) VALUES(?1, ?2)").map_err(err)?;
            let mut overrides: Vec<_> = index.overrides.iter().collect();
            overrides.sort_by(|a, b| a.0.cmp(b.0));
            for (bundle, candidates) in overrides {
                for rel in candidates {
                    let Some(id) = ids.get(rel.as_str()) else { continue };
                    over.execute(rusqlite::params![bundle, id]).map_err(err)?;
                    override_rows += 1;
                }
            }
            let mut migration = tx.prepare("INSERT INTO migration(guid_old, kind, archive) VALUES(?1, ?2, ?3)").map_err(err)?;
            for (old, kind, rel) in &index.migrations {
                let Some(id) = ids.get(rel.as_str()) else { continue };
                migration.execute(rusqlite::params![old, kind, id]).map_err(err)?;
            }
            let mut uncensor = tx.prepare("INSERT INTO uncensor(archive, xml) VALUES(?1, ?2)").map_err(err)?;
            for (rel, xmls) in &index.uncensor {
                let Some(id) = ids.get(rel.as_str()) else { continue };
                for xml in xmls { uncensor.execute(rusqlite::params![id, xml]).map_err(err)?; }
            }
            let mut meta = tx.prepare("INSERT INTO meta(key, value) VALUES(?1, ?2)").map_err(err)?;
            for (k, v) in [
                ("schema", SCHEMA.to_string()),
                ("archives", index.archives.len().to_string()),
                // Which tree it is about, so that `serves` can say yes without listing the tree (see there).
                ("mods_dir", tree_key(mods_dir)),
                ("guid_rows", guid_rows.to_string()),
                ("override_rows", override_rows.to_string()),
                ("migration_rows", index.migrations.len().to_string()),
                ("uncensor_archives", index.uncensor.len().to_string()),
                ("built_at_unix", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_secs().to_string()).unwrap_or_default()),
                ("tool", "ok-extract --oklib shared-ignore / mods-index".to_string()),
            ] { meta.execute(rusqlite::params![k, v]).map_err(err)?; }
        }
        tx.commit().map_err(err)?;
    }
    conn.execute_batch("ANALYZE; VACUUM;").map_err(err)?;
    drop(conn);
    // Replacing the published file: a reader holding the old one keeps reading it (Windows allows the rename while a
    // read-only handle is open only after the old name is gone, so the old file is removed first).
    let _ = std::fs::remove_file(&final_path);
    std::fs::rename(&building, &final_path).map_err(|e| format!("{}: {e}", final_path.display()))?;
    // The text files this database replaces (2026-11-24), and the per-installation caches before them.
    for stale in ["mods_guids.txt", "mods_overrides.txt"] { let _ = std::fs::remove_file(lib.join(stale)); }
    Ok((guid_rows, override_rows))
}

/// One library's database, opened read-only once per process. `rusqlite::Connection` is `Send` but not `Sync`, and a
/// lookup is microseconds, so one connection behind a mutex is enough for the opens' threads.
pub struct Db { conn: Mutex<Connection>, rows: i64, built_from: String }

impl Db {
    fn open(lib: &Path) -> Option<Db> {
        let path = lib.join(DB_FILE);
        if !path.is_file() { return None; }
        let flags = OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX;
        let conn = match Connection::open_with_flags(&path, flags) {
            Ok(conn) => conn,
            Err(e) => { crate::profile::line(format!("OKMODS {}: {e}", path.display())); return None; }
        };
        let schema: i64 = conn.query_row("SELECT value FROM meta WHERE key='schema'", [], |r| r.get::<_, String>(0))
            .ok().and_then(|v| v.parse().ok()).unwrap_or(0);
        if schema != SCHEMA {
            crate::profile::line(format!(
                "OKMODS {} is schema {schema}, this build needs {SCHEMA}: rerun `ok-extract <game> --oklib mods-index {}`",
                path.display(), lib.display()));
            return None;
        }
        let rows: i64 = conn.query_row("SELECT count(*) FROM archive", [], |r| r.get(0)).unwrap_or(0);
        let built_from: String = conn.query_row("SELECT value FROM meta WHERE key='mods_dir'", [], |r| r.get(0))
            .unwrap_or_default();
        Some(Db { conn: Mutex::new(conn), rows, built_from })
    }

    fn guid_rows(&self, guid: &str) -> Vec<(String, String)> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let Ok(mut st) = conn.prepare_cached(
            "SELECT a.path, g.version FROM guid g JOIN archive a ON a.id = g.archive WHERE g.guid = ?1 ORDER BY a.id")
        else { return Vec::new() };
        st.query_map([guid], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))
            .map(|rows| rows.filter_map(Result::ok).collect()).unwrap_or_default()
    }

    fn override_rows(&self, bundle: &str) -> Vec<String> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let Ok(mut st) = conn.prepare_cached(
            "SELECT a.path FROM override o JOIN archive a ON a.id = o.archive WHERE o.bundle = ?1 ORDER BY a.id")
        else { return Vec::new() };
        st.query_map([bundle], |r| r.get::<_, String>(0))
            .map(|rows| rows.filter_map(Result::ok).collect()).unwrap_or_default()
    }

    /// `(migrationType, archive)` if some installed archive migrates this legacy id away.
    fn migration(&self, guid: &str) -> Option<(String, String)> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut st = conn.prepare_cached(
            "SELECT m.kind, a.path FROM migration m JOIN archive a ON a.id = m.archive WHERE m.guid_old = ? ORDER BY a.id LIMIT 1").ok()?;
        st.query_row([guid], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).ok()
    }

    /// Every archive that declares an UncensorSelector body/penis/balls, with its manifests: archive path (relative
    /// to `mods/`, lower case) -> the XMLs, in walk order. `None` when this database was built before the table
    /// existed, which is how an older `mods_index.db` keeps working (the caller reads the archives itself, as before)
    /// without the schema -- and every other query of it -- being invalidated.
    fn uncensor_table(&self) -> Option<UncensorIndex> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let mut st = conn.prepare(
            "SELECT a.path, u.xml FROM uncensor u JOIN archive a ON a.id = u.archive ORDER BY a.id").ok()?;
        let rows = st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))).ok()?;
        let mut parts: HashMap<String, Vec<String>> = HashMap::new();
        for (rel, xml) in rows.filter_map(Result::ok) { parts.entry(rel.to_ascii_lowercase()).or_default().push(xml); }
        // Which archives the database is about, so that "this one declares nothing" (no row, and it must not be read)
        // is told from "the database never saw it" (a zipmod beside the card, which is read). Without this an
        // installation whose mods happen to declare no uncensor part at all would read every archive again.
        let mut known = std::collections::HashSet::new();
        let mut st = conn.prepare("SELECT path FROM archive").ok()?;
        let rows = st.query_map([], |r| r.get::<_, String>(0)).ok()?;
        for rel in rows.filter_map(Result::ok) { known.insert(rel.to_ascii_lowercase()); }
        Some(UncensorIndex { known, parts })
    }

    /// Does the database name this archive (relative to `mods/`)? One indexed lookup.
    fn knows(&self, rel: &str) -> bool {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let Ok(mut st) = conn.prepare_cached("SELECT 1 FROM archive WHERE path = ?1 LIMIT 1") else { return false };
        st.exists([rel]).unwrap_or(false)
    }

    /// Every GUID the installation declares. Only `find_guids(None)` and the reader's start ask for this.
    pub fn all_guids(&self) -> Vec<String> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let Ok(mut st) = conn.prepare("SELECT DISTINCT guid FROM guid ORDER BY guid") else { return Vec::new() };
        st.query_map([], |r| r.get::<_, String>(0)).map(|rows| rows.filter_map(Result::ok).collect()).unwrap_or_default()
    }

    /// `guid<TAB>version<TAB>path relative to mods/`, best archive first per GUID (walk order), for the reader's own
    /// index: it needs the whole map, not one lookup, and this is the one place that reads it whole.
    pub fn guid_table(&self) -> Vec<(String, String, String)> {
        let conn = self.conn.lock().unwrap_or_else(|e| e.into_inner());
        let Ok(mut st) = conn.prepare(
            "SELECT g.guid, g.version, a.path FROM guid g JOIN archive a ON a.id = g.archive ORDER BY g.guid, a.id")
        else { return Vec::new() };
        st.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?)))
            .map(|rows| rows.filter_map(Result::ok).collect()).unwrap_or_default()
    }
}

/// The database of a library by path, whether or not it is the active one (the reader asks by path).
pub fn open(lib: &Path) -> Option<Arc<Db>> {
    static OPEN: OnceLock<RwLock<Vec<(PathBuf, Option<Arc<Db>>)>>> = OnceLock::new();
    let slot = OPEN.get_or_init(|| RwLock::new(Vec::new()));
    if let Some((_, hit)) = slot.read().unwrap_or_else(|e| e.into_inner()).iter().find(|(p, _)| p == lib) {
        return hit.clone();
    }
    let db = Db::open(lib).map(Arc::new);
    if db.is_none() && !lib.join(DB_FILE).is_file() {
        crate::profile::line(format!(
            "OKMODS {} has no {DB_FILE}: run `ok-extract <game> --oklib mods-index {}`", lib.display(), lib.display()));
    }
    let mut slot = slot.write().unwrap_or_else(|e| e.into_inner());
    slot.retain(|(p, _)| p != lib);
    slot.push((lib.to_path_buf(), db.clone()));
    db
}

/// The active library's database.
pub fn active() -> Option<Arc<Db>> {
    open(&crate::oklib::active_dir()?)
}

/// The archives `mods_dir` serves right now, relative and lower case: for an original card its narrow view, for a
/// plain installation all of them. Only names are listed (no archive is opened), and the listing is the one
/// `mods::collect_zipmods` already memoizes per fallback generation.
fn view(mods_dir: &Path) -> Arc<std::collections::HashSet<String>> {
    static VIEW: OnceLock<RwLock<Vec<(PathBuf, u64, Arc<std::collections::HashSet<String>>)>>> = OnceLock::new();
    let slot = VIEW.get_or_init(|| RwLock::new(Vec::new()));
    let generation = crate::gamefs::fallback_generation();
    let dir = mods_dir.to_path_buf();
    if let Some((_, _, hit)) = slot.read().unwrap_or_else(|e| e.into_inner()).iter()
        .find(|(p, g, _)| *p == dir && *g == generation) { return hit.clone(); }
    let set: std::collections::HashSet<String> = crate::mods::all_zipmods(mods_dir).iter()
        .map(|z| relative(mods_dir, z).to_ascii_lowercase()).collect();
    let set = Arc::new(set);
    let mut slot = slot.write().unwrap_or_else(|e| e.into_inner());
    slot.retain(|(p, g, _)| !(*p == dir && *g == generation));
    if slot.len() >= 4 { slot.remove(0); }
    slot.push((dir, generation, set.clone()));
    set
}

/// Whether the database was built from exactly this folder: one string compare, no file system.
fn built_from(mods_dir: &Path) -> bool {
    active().is_some_and(|db| !db.built_from.is_empty() && db.built_from == tree_key(mods_dir))
}

/// Which of the database's archives are there to choose from. `None` means all of them, and that is the normal case:
/// the installation itself with no original card narrowing it. Only then is the listing skipped -- it is a listing of
/// 7296 names whose memo key changes with every card, so asking for it when nothing narrows the view cost every open
/// (the OK cards too, which have nothing to ask the index) about 8% (measured 2026-11-24).
fn visible(mods_dir: &Path) -> Option<Arc<std::collections::HashSet<String>>> {
    if !crate::gamefs::narrow_mods_active() && built_from(mods_dir) { return None; }
    Some(view(mods_dir))
}

/// Which archive declares `guid`, among the ones this view serves, ranked as the tree scan ranked them (a backed
/// archive over an unbacked one, then the higher declared version; walk order breaks a tie). None when the database
/// names none the view has: the caller reports a gap, it never walks the tree.
pub fn guid_archive(mods_dir: &Path, guid: &str) -> Option<PathBuf> {
    let db = active()?;
    debug_assert!(serves(mods_dir) || !available());
    let candidates = db.guid_rows(&guid.to_ascii_lowercase());
    if candidates.is_empty() { return None; }
    let view = visible(mods_dir);
    let mut best: Option<(crate::mods::GuidRank, String)> = None;
    for (rel, version) in candidates {
        if view.as_ref().is_some_and(|v| !v.contains(&rel.to_ascii_lowercase())) { continue; }
        let path = mods_dir.join(&rel);
        let unbacked = crate::gamefs::library_zips_unbacked(std::slice::from_ref(&path)).first().copied().unwrap_or(false);
        let rank = crate::mods::guid_rank_with(unbacked, &version);
        if best.as_ref().is_none_or(|(cur, _)| rank > *cur) { best = Some((rank, rel)); }
    }
    best.map(|(_, rel)| mods_dir.join(rel))
}

/// Which archive replaces `bundle` (a lower-case `abdata/...unity3d` path): the first of this view's archives in
/// walk order, as `build_override_index`'s `or_insert` chose.
pub fn override_archive(mods_dir: &Path, bundle: &str) -> Option<PathBuf> {
    let db = active()?;
    let candidates = db.override_rows(&bundle.to_ascii_lowercase());
    let view = visible(mods_dir);
    candidates.into_iter().find(|rel| view.as_ref().is_none_or(|v| v.contains(&rel.to_ascii_lowercase())))
        .map(|rel| mods_dir.join(rel))
}

/// What the index says about UncensorSelector parts: which archives it is about at all (`known`, relative to `mods/`,
/// lower case) and, of those, which declare a body/penis/balls with their manifests in walk order (`parts`).
pub struct UncensorIndex {
    pub known: std::collections::HashSet<String>,
    pub parts: HashMap<String, Vec<String>>,
}

impl UncensorIndex {
    /// The archive's UncensorSelector manifests, or `None` when the index cannot answer for it (then the caller reads
    /// that one archive). An empty `Vec` is an answer: this archive declares nothing.
    pub fn get(&self, rel: &str) -> Option<&[String]> {
        match self.parts.get(rel) {
            Some(xmls) => Some(xmls),
            None => self.known.contains(rel).then_some(&[] as &[String]),
        }
    }
}

/// The UncensorSelector declarations of the archives the active library's index knows, for `mods::uncensor_sources`:
/// archive path relative to `mods/` (lower case) -> its manifests, in walk order. Read whole, once per process -- it
/// is about 25 rows, while the question it answers used to open every archive of the tree. `None`: no library active,
/// a database that does not serve this tree, or one built before the table existed (then the caller reads the
/// archives itself). An archive the map does not name is **not** "declares nothing": the caller still reads that one
/// (a zipmod beside the card is in the view and not in the index).
pub fn uncensor_manifests(mods_dir: &Path) -> Option<Arc<UncensorIndex>> {
    static SEEN: OnceLock<RwLock<Vec<(PathBuf, Option<Arc<UncensorIndex>>)>>> = OnceLock::new();
    // An empty value is not "set": a measurement script that exports `OK_NO_UNCENSOR_INDEX=""` for the A side would
    // otherwise take the fallback on both sides and the gate would compare the old path with itself (it did, on the
    // first run of 2026-11-25 -- 21/21 and 42/42 "identical" while neither side used the index).
    if std::env::var_os("OK_NO_UNCENSOR_INDEX").is_some_and(|v| !v.is_empty()) { return None; }
    let lib = crate::oklib::active_dir()?;
    if !serves(mods_dir) { return None; }
    let slot = SEEN.get_or_init(|| RwLock::new(Vec::new()));
    if let Some((_, hit)) = slot.read().unwrap_or_else(|e| e.into_inner()).iter().find(|(p, _)| *p == lib) {
        return hit.clone();
    }
    let table = active().and_then(|db| db.uncensor_table()).map(Arc::new);
    if table.is_none() {
        crate::profile::line(format!("OKMODS {} has no uncensor table: rerun `ok-extract <game> --oklib mods-index {}` \
            so an open need not read every archive's manifest", lib.display(), lib.display()));
    }
    let mut slot = slot.write().unwrap_or_else(|e| e.into_inner());
    slot.retain(|(p, _)| *p != lib);
    slot.push((lib, table.clone()));
    table
}

/// Every GUID the active library's installation declares, for the one caller that wants them all.
pub fn all_guids() -> Vec<String> {
    active().map(|db| db.all_guids()).unwrap_or_default()
}

/// Whether the active library carries the database at all, so a caller can tell "not named" (a gap) from "no index".
pub fn available() -> bool {
    active().is_some_and(|db| db.rows > 0)
}

/// Whether the database is about *this* tree: at least one archive the view serves is named in it. An index belongs
/// to the installation its library was built from, so it may not be used to answer about -- or to refuse a walk of --
/// some other tree: a second installation, or the temporary trees the tests build (which is what caught this:
/// `mods::migration_tests::duplicate_guid_prefers_highest_manifest_version` got None because a library another test
/// had left active made this path answer about a tree the index knows nothing about).
///
/// The answer is normally the path the database records (`meta.mods_dir`): one string compare, no file system at all.
/// Asking the view instead means **listing** the tree, and the memo would not even hold, because its key is the
/// fallback generation and that changes with every card -- so an OK card's open, which has nothing to ask the index,
/// paid a listing of all 7296 names anyway (+7% over the six OK baselines, measured 2026-11-24). The listing is only
/// the fallback, for a tree at some other path (a moved installation, the tests' temporary trees), memoized as before.
pub fn serves(mods_dir: &Path) -> bool {
    static SERVES: OnceLock<RwLock<Vec<(PathBuf, u64, bool)>>> = OnceLock::new();
    let Some(db) = active() else { return false };
    if db.rows == 0 { return false; }
    if built_from(mods_dir) { return true; }
    let slot = SERVES.get_or_init(|| RwLock::new(Vec::new()));
    let generation = crate::gamefs::fallback_generation();
    let dir = mods_dir.to_path_buf();
    if let Some((_, _, hit)) = slot.read().unwrap_or_else(|e| e.into_inner()).iter()
        .find(|(p, g, _)| *p == dir && *g == generation) { return *hit; }
    let answer = view(mods_dir).iter().any(|rel| db.knows(rel));
    let mut slot = slot.write().unwrap_or_else(|e| e.into_inner());
    slot.retain(|(p, g, _)| !(*p == dir && *g == generation));
    if slot.len() >= 4 { slot.remove(0); }
    slot.push((dir, generation, answer));
    answer
}

/// An open must never read the whole mods tree: true while a library is active and this tree is the one its index is
/// about -- the reader, the packaged game and the benches -- or while a library is active and carries no index at
/// all, which is the case the user has to fix (`mods-index`) and must not be papered over by a walk. The
/// conversion commands that *build* the library have no library active and walk as before.
pub fn tree_scan_forbidden(mods_dir: &Path) -> bool {
    crate::oklib::active_dir().is_some() && (serves(mods_dir) || !available())
}

pub fn refuse(what: &str, detail: &str) {
    use std::sync::atomic::{AtomicU64, Ordering};
    static SAID: AtomicU64 = AtomicU64::new(0);
    if SAID.fetch_add(1, Ordering::Relaxed) < 20 {
        crate::profile::line(format!("OKMODS unanswered {what}: {detail} (library index; the tree is never walked on an open)"));
    }
}

/// What an id the GUID index cannot place actually is. Only `Missing` is a real gap -- a part the card asks for and
/// nothing provides. The other two used to be printed as gaps too, which drowned the real ones (the packaged
/// Release1124e run, 2026-11-24: five `SAC.*` plus two `kks.*` lines and one genuinely missing mod).
pub enum Unplaced {
    /// Some installed archive declares a migration for this id (`StripAll` of `kks.co_bra_00` by the KKS backport
    /// package): it is a legacy id the installation drops by design, not a mod to go looking for.
    Migrated { kind: String, by: String },
    /// An UncensorSelector body/genital id (`SAC.innie`, `SAC.clit`), which lives in that plugin's own manifests, not
    /// in a zipmod `<guid>`: the mods index is the wrong place to ask.
    UncensorPart,
    Missing,
}

/// Classify before reporting. `game_root` may be `mods/`'s parent; the uncensor question is answered from the
/// library's own `uncensor_v1` pack (25 archives, memoized), never by walking the tree.
pub fn classify(game_root: &Path, guid: &str) -> Unplaced {
    let key = guid.to_ascii_lowercase();
    if let Some(db) = active() {
        if let Some((kind, by)) = db.migration(&key) { return Unplaced::Migrated { kind, by }; }
    }
    if crate::mods::uncensor_guid_known(game_root, guid) { return Unplaced::UncensorPart; }
    Unplaced::Missing
}

/// Report an id the GUID index could not place, as what it is. Returns whether it is a real gap.
pub fn report_unplaced(mods_dir: &Path, guid: &str) -> bool {
    let game_root = mods_dir.parent().unwrap_or(mods_dir);
    match classify(game_root, guid) {
        Unplaced::Migrated { kind, by } => {
            crate::profile::line(format!("OKMODS migrated guid: {guid} ({kind} by {by}; a legacy id, not a missing mod)"));
            false
        }
        Unplaced::UncensorPart => {
            crate::profile::line(format!("OKMODS uncensor part: {guid} (UncensorSelector id, not a zipmod GUID)"));
            false
        }
        Unplaced::Missing => { refuse("guid", guid); true }
    }
}
