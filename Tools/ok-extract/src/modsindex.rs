//! The mods tree's two maps, carried **by the base library** as a database and built once by
//! `--oklib shared-ignore` (or `--oklib mods-index`): which archive declares each GUID, and which archive replaces
//! each `abdata/...unity3d`.
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
//! (`OKMODS unanswered`), not a reason to walk the tree. It is `<lib>/mods_index.db`, SQLite, three tables:
//! `archive` (every zipmod of that installation, in walk order), `guid` and `override` (rows pointing at archives).
//! Nothing is loaded whole: a lookup is one indexed query, so the reader's start and an open pay for the GUIDs they
//! ask about and nothing else.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, RwLock};

use rusqlite::{Connection, OpenFlags};

pub const DB_FILE: &str = "mods_index.db";
/// Bumped when the tables change: an older file is ignored (and reported), never half-read.
const SCHEMA: i64 = 2;

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
    let rows: Vec<(String, Vec<(String, String)>, Vec<String>, Vec<(String, String)>)> = zips
        .par_iter()
        .map(|zip| {
            let rel = relative(mods_dir, zip);
            (rel, crate::mods::guids_and_versions_from_zipmod(zip), crate::mods::zipmod_override_keys(zip),
                crate::mods::migrations_from_zipmod(zip))
        })
        .collect();
    let mut index = Index::default();
    for (rel, guids, overrides, migrations) in rows {
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
         CREATE INDEX migration_lookup ON migration(guid_old);",
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
            let mut meta = tx.prepare("INSERT INTO meta(key, value) VALUES(?1, ?2)").map_err(err)?;
            for (k, v) in [
                ("schema", SCHEMA.to_string()),
                ("archives", index.archives.len().to_string()),
                // Which tree it is about, so that `serves` can say yes without listing the tree (see there).
                ("mods_dir", tree_key(mods_dir)),
                ("guid_rows", guid_rows.to_string()),
                ("override_rows", override_rows.to_string()),
                ("migration_rows", index.migrations.len().to_string()),
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
