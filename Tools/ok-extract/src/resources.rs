//! The resource pack / program compatibility gate.
//!
//! The problem it exists for happened once already (2026-11-24, the first program-only package): a library carrying a
//! **schema 1** `mods_index.db` was overlaid with a build needing schema 2, the index read as **0 GUIDs**, and an
//! original card **still opened** -- claiming the user lacked 42 mods they all had. The standard the user set is:
//! rather refuse and explain than silently drop parts. So the gate judges **before** an open, in `oklib::activate`,
//! which every caller goes through (the reader, OK Studio, the MCP servers, the CLI, mods).
//!
//! Two layers, both needed (the plan, C tree `Docs/RESOURCE_PROGRAM_COMPAT_GATE_PLAN.md` §2.4):
//!
//! 1. **A hand-kept integer.** `RESOURCES.json`'s `version` against this build's `[RESOURCES_MIN, RESOURCES_MAX]`.
//!    It is a *declaration* -- some incompatibilities show up in no machine-readable sub-version (a model file's
//!    internal encoding changes while `oklib.json`'s version does not), and then the integer is the only way to say
//!    so. Outside the range is a mismatch **in both directions**: a resource pack newer than the program means the
//!    program is too old.
//! 2. **Sub-versions the machine actually reads**, against constants in this program: `mods_index.db`'s `meta.schema`
//!    against `modsindex::SCHEMA`, `oklib.json`'s `version`, the existence of the few files without which the library
//!    answers *wrongly*, and one "open the library and ask a known query" selftest. This layer catches the forgotten
//!    `+1`, which is what 11-24 was.
//!
//! The two SHA-256s `RESOURCES.json` records (`shared_mods.txt`, `mods_index.db`) are **recorded, never compared**:
//! `shared_mods.txt` follows which mods this machine has, and rebuilding the index changes its hash while changing
//! nothing about compatibility. A false alarm is worse than no gate, because the user learns to ignore it.
//!
//! `OK_RESOURCES_CHECK=off` is the escape hatch for development; every open then logs that the gate is off.

use std::path::{Path, PathBuf};

use serde_json::{json, Value};

/// The oldest resource pack format this build understands.
pub const RESOURCES_MIN: u32 = 3;
/// The newest resource pack format this build understands. A pack newer than this means the *program* is too old.
pub const RESOURCES_MAX: u32 = 3;
/// What a pack built by this build declares (`--oklib resources-stamp`, which the packaging script copies into
/// `RESOURCES.json`). Normally equal to `RESOURCES_MAX`.
///
/// Version history -- bump all three when a format change makes an older pack open badly under a newer program:
///   3  2026-11-24  the library carries `mods_index.db` instead of two text files (`ae89b2073`), schema 2 with the
///                  migration table (`717297c3b`). Anything packaged before that day is "resources too old".
pub const RESOURCES_VERSION: u32 = 3;

/// `Content/IndependentResources/RESOURCES.json`, written by the full package beside the library.
pub const STAMP_FILE: &str = "RESOURCES.json";

/// How severe a problem is. Only two levels: `block` refuses the open, `warn` is a screen notice.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level { Block, Warn }

impl Level {
    pub fn as_str(self) -> &'static str { match self { Level::Block => "block", Level::Warn => "warn" } }
}

#[derive(Debug, Clone)]
pub struct Problem {
    /// One of the fixed ids (see `IDS`); only ever added to.
    pub id: &'static str,
    pub level: Level,
    /// What the user will see go wrong, in their language. Never a GUID or a schema number as the subject.
    pub what: String,
    pub fix: String,
    pub fixable_locally: bool,
    pub command: Option<String>,
}

/// Every id this gate can report. Fixed on 2026-11-24 so the UE side and the packaging scripts can switch on them.
pub const IDS: &[&str] = &[
    "resources_too_old", "resources_too_new", "no_resources_json", "oklib_version", "mods_index_schema",
    "mods_index_missing", "mods_index_empty", "mods_index_foreign", "shared_mods_missing", "models_ignore_missing",
    "sources_missing", "selftest_failed",
];

/// What the installation is: a shipped one (there is a `PACKAGE.json` above the library saying `program` or `full`)
/// or a development tree. It decides one thing only: whether a missing `RESOURCES.json` blocks (§7.2).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Install {
    /// A shipped installation; the `PACKAGE.json` found and its `kind`.
    Shipped { package: PathBuf, kind: String },
    /// No `PACKAGE.json` above the library: a development tree or a temporary library.
    Development,
}

/// Walk up from the library looking for the installation's `PACKAGE.json`. Capped at six levels: the library sits at
/// `<install>/Content/IndependentResources/base_v1`, so three is enough in practice, and a cap keeps an unrelated
/// `PACKAGE.json` far above (a folder holding several packages) out of the answer.
pub fn install_kind(lib: &Path) -> Install {
    let mut dir = lib.to_path_buf();
    for _ in 0..6 {
        let Some(parent) = dir.parent().map(Path::to_path_buf) else { break };
        dir = parent;
        let marker = dir.join("PACKAGE.json");
        if !marker.is_file() { continue; }
        let kind = std::fs::read(&marker).ok()
            .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
            .and_then(|v| v.get("kind").and_then(Value::as_str).map(str::to_owned))
            .unwrap_or_default();
        if kind == "program" || kind == "full" { return Install::Shipped { package: marker, kind }; }
    }
    Install::Development
}

/// `RESOURCES.json` as read from disk: the library's own folder first, then the resources folder above it (where a
/// full package writes it).
struct Stamp { path: PathBuf, value: Value }

fn read_stamp(lib: &Path) -> Option<Stamp> {
    for candidate in [lib.join(STAMP_FILE), lib.parent().map(|p| p.join(STAMP_FILE)).unwrap_or_default()] {
        if !candidate.is_file() { continue; }
        if let Some(value) = std::fs::read(&candidate).ok().and_then(|b| serde_json::from_slice::<Value>(&b).ok()) {
            return Some(Stamp { path: candidate, value });
        }
    }
    None
}

fn library_version(lib: &Path) -> Option<u32> {
    std::fs::read(lib.join("oklib.json")).ok()
        .and_then(|b| serde_json::from_slice::<Value>(&b).ok())
        .and_then(|v| v.get("version").and_then(Value::as_u64))
        .map(|v| v as u32)
}

/// The rebuild command the index problems hand the user, with their own game directory when one is configured.
fn rebuild_index_command(lib: &Path, game: Option<&Path>) -> String {
    let game = game.map(|g| g.display().to_string()).unwrap_or_else(|| "D:/KoikatuSunshine".into());
    format!("Tools\\ok-extract\\target\\release\\ok-extract.exe {game} --oklib mods-index {}", lib.display())
}

/// The whole check. `game` is the configured game directory when there is one (only `mods_index_foreign` uses it);
/// `want` overrides this build's range (`--want-min/--want-max`, for the acceptance scenarios); `selftest` adds the
/// "open the library and ask a known query" check, which reads a model file and so is not run on every open.
pub fn check(lib: &Path, game: Option<&Path>, want: (u32, u32), selftest: bool) -> Vec<Problem> {
    let (min, max) = want;
    let mut problems = Vec::new();
    let install = install_kind(lib);

    // 1. the hand-kept integer
    match read_stamp(lib) {
        Some(stamp) => {
            let version = stamp.value.get("version").and_then(Value::as_u64).unwrap_or(0) as u32;
            let package = stamp.value.get("package").and_then(Value::as_str).unwrap_or("?").to_owned();
            let made = stamp.value.get("made").and_then(Value::as_str).unwrap_or("?").to_owned();
            if version < min {
                problems.push(Problem {
                    id: "resources_too_old", level: Level::Block,
                    what: format!("資源包太舊，這版程式開不了卡。程式需要資源版本 {min}，這台裝的是 {version}（{package}，{made}）。"),
                    fix: "請下載新的完整包，或至少它的資源部分，解壓覆蓋到安裝資料夾。".into(),
                    fixable_locally: false, command: None,
                });
            } else if version > max {
                problems.push(Problem {
                    id: "resources_too_new", level: Level::Block,
                    what: format!("資源包比程式新，這版程式讀不懂。這台的資源是版本 {version}，程式只懂到 {max}。"),
                    fix: "請下載新的程式包覆蓋安裝；資源包不用再下載一次。".into(),
                    fixable_locally: false, command: None,
                });
            }
        }
        None => match &install {
            Install::Shipped { kind, .. } => problems.push(Problem {
                id: "no_resources_json", level: Level::Block,
                what: format!("這份安裝（{kind} 包）少了資源版本記錄 {STAMP_FILE}，無法確認資源包版本。包可能被破壞，或是裝錯了資料夾。"),
                fix: "請重新解壓完整包到安裝資料夾。".into(),
                fixable_locally: false, command: None,
            }),
            Install::Development => problems.push(Problem {
                id: "no_resources_json", level: Level::Warn,
                what: format!("這個基礎庫不是出貨包（旁邊沒有 {STAMP_FILE}），資源包版本檢查跳過。"),
                fix: "子版本檢查照跑（mod 索引 schema、庫的標記版本、必要檔案）。".into(),
                fixable_locally: false, command: None,
            }),
        },
    }

    // 2. the sub-versions, in both kinds of installation
    match library_version(lib) {
        Some(v) if crate::oklib::LIBRARY_VERSIONS_KNOWN.contains(&v) => {}
        Some(v) => problems.push(Problem {
            id: "oklib_version", level: Level::Block,
            what: format!("基礎庫的標記版本是 {v}，這版程式懂的是 {:?}。整個庫的格式不是這版程式能讀的，開卡會缺件。",
                crate::oklib::LIBRARY_VERSIONS_KNOWN),
            fix: "資源包和程式包要用同一次發佈的版本；請更新比較舊的那一邊。".into(),
            fixable_locally: false, command: None,
        }),
        None => problems.push(Problem {
            id: "oklib_version", level: Level::Block,
            what: format!("{} 的 oklib.json 讀不到版本，這個資料夾不像是基礎庫。", lib.display()),
            fix: "請確認安裝路徑，或重新解壓完整包的資源部分。".into(),
            fixable_locally: false, command: None,
        }),
    }

    let health = crate::modsindex::health_of(lib);
    let rebuild = rebuild_index_command(lib, game);
    match &health {
        crate::modsindex::IndexHealth::Ok { .. } => {}
        crate::modsindex::IndexHealth::Missing => problems.push(Problem {
            id: "mods_index_missing", level: Level::Block,
            what: "資源包沒有 mod 索引。卡片指名的第三方 mod 會查不到，那些部件不會穿上。".into(),
            fix: "本機有遊戲的話，用下面這行建索引；沒有遊戲就下載新的完整包。".into(),
            fixable_locally: true, command: Some(rebuild.clone()),
        }),
        crate::modsindex::IndexHealth::Unreadable { detail } => problems.push(Problem {
            id: "mods_index_missing", level: Level::Block,
            what: format!("資源包的 mod 索引讀不開（{detail}），檔案可能不完整。卡片指名的第三方 mod 會查不到，那些部件不會穿上。"),
            fix: "本機有遊戲的話，用下面這行重建索引；沒有遊戲就下載新的完整包。".into(),
            fixable_locally: true, command: Some(rebuild.clone()),
        }),
        crate::modsindex::IndexHealth::Schema { found, want } => problems.push(Problem {
            id: "mods_index_schema", level: Level::Block,
            what: format!("mod 索引是舊格式（schema {found}），這版程式要 {want}。卡片指名的第三方 mod 會查不到，那些部件不會穿上。"),
            fix: "本機有遊戲的話，用下面這行重建索引；沒有遊戲就下載新的完整包。".into(),
            fixable_locally: true, command: Some(rebuild.clone()),
        }),
        crate::modsindex::IndexHealth::Empty => problems.push(Problem {
            id: "mods_index_empty", level: Level::Block,
            what: "資源包的 mod 索引是空的（一個 GUID 都沒有），這不是「這台真的沒裝 mod」，是索引壞了。卡片指名的第三方 mod 會查不到。".into(),
            fix: "本機有遊戲的話，用下面這行重建索引；沒有遊戲就下載新的完整包。".into(),
            fixable_locally: true, command: Some(rebuild.clone()),
        }),
    }

    // The index belongs to the installation its library was built from. Only worth saying when the user has a game
    // directory at all: a packaged install that only opens OK cards never asks the index anything.
    if health.is_ok() {
        if let Some(mods) = game.map(|g| g.join("mods")).filter(|m| m.is_dir()) {
            if !crate::modsindex::index_covers(lib, &mods) {
                problems.push(Problem {
                    id: "mods_index_foreign", level: Level::Warn,
                    what: "mod 索引不是這個遊戲目錄建的，開原作卡會慢，而且「缺哪些 mod」可能列不準。OK 卡不受影響，照開。".into(),
                    fix: "要修就重建一次索引。".into(),
                    fixable_locally: true, command: Some(rebuild.clone()),
                });
            }
        }
    }

    // The files without which the library answers *wrongly* -- existence only, never content (§2.1).
    for (id, path, what) in [
        ("shared_mods_missing", lib.join("shared_mods.txt"),
         "基礎庫少了共用 mod 清單 shared_mods.txt，開 OK 卡會整個慢下來（窄視圖失效）。"),
        ("models_ignore_missing", lib.join("models").join(".gitignore"),
         "基礎庫少了非共用模型清單 models/.gitignore，庫會替第三方 mod 的模型給出錯的答案，比缺件更難查。"),
    ] {
        if path.is_file() { continue; }
        let id = IDS.iter().find(|i| **i == id).copied().unwrap_or("sources_missing");
        problems.push(Problem {
            id, level: Level::Block, what: what.into(),
            fix: "請重新解壓完整包的資源部分；本機有遊戲的話也可以重建基礎庫的清單。".into(),
            fixable_locally: false, command: None,
        });
    }
    if !lib.join("sources.okidx").is_file() || !lib.join("models").is_dir() {
        problems.push(Problem {
            id: "sources_missing", level: Level::Block,
            what: format!("{} 少了來源索引 sources.okidx 或 models 資料夾，這個資料夾不是完整的基礎庫。", lib.display()),
            fix: "請重新解壓完整包的資源部分。".into(),
            fixable_locally: false, command: None,
        });
    }

    // 3. does it still answer (only when asked: it reads a model file)
    if selftest {
        if let Err(e) = crate::oklib::selftest_model(lib) {
            problems.push(Problem {
                id: "selftest_failed", level: Level::Block,
                what: format!("基礎庫開得起來但答不出東西（{e}）。這版程式配這份資源會開不了卡。"),
                fix: "請重新解壓完整包的資源部分；本機有遊戲的話重建基礎庫。".into(),
                fixable_locally: false, command: None,
            });
        }
    }

    problems
}

/// This build's range, after `--want-min/--want-max`.
pub fn wanted(want_min: Option<u32>, want_max: Option<u32>) -> (u32, u32) {
    (want_min.unwrap_or(RESOURCES_MIN), want_max.unwrap_or(RESOURCES_MAX))
}

/// The JSON of §3.2: what the CLI prints and what `ok_resources_check` hands the UE side.
pub fn check_json(lib: &Path, game: Option<&Path>, want: (u32, u32), selftest: bool) -> Value {
    let problems = check(lib, game, want, selftest);
    let blocked = problems.iter().any(|p| p.level == Level::Block);
    let stamp = read_stamp(lib);
    let health = crate::modsindex::health_of(lib);
    let resources = match &stamp {
        Some(s) => json!({
            "stamp": s.path.display().to_string(),
            "version": s.value.get("version").and_then(Value::as_u64),
            "package": s.value.get("package").and_then(Value::as_str),
            "made": s.value.get("made").and_then(Value::as_str),
            "parts": parts(lib, &health),
        }),
        None => json!({ "stamp": Value::Null, "version": Value::Null, "parts": parts(lib, &health) }),
    };
    json!({
        "ok": !blocked,
        "library": lib.display().to_string(),
        "install": match install_kind(lib) {
            Install::Shipped { package, kind } => json!({ "kind": kind, "package": package.display().to_string() }),
            Install::Development => json!({ "kind": "development" }),
        },
        "resources": resources,
        "program": { "min": want.0, "max": want.1, "version": RESOURCES_VERSION, "commit": build_commit() },
        "problems": problems.iter().map(|p| json!({
            "id": p.id, "level": p.level.as_str(), "what": p.what, "fix": p.fix,
            "fixable_locally": p.fixable_locally, "command": p.command,
        })).collect::<Vec<_>>(),
    })
}

/// The sub-versions as actually read from the library -- never hand-written, and what a full package's `parts` has to
/// equal (the packaging self-check compares them).
fn parts(lib: &Path, health: &crate::modsindex::IndexHealth) -> Value {
    use crate::modsindex::IndexHealth;
    json!({
        "oklib_version": library_version(lib),
        "mods_index_schema": match health {
            IndexHealth::Schema { found, .. } => Some(*found),
            IndexHealth::Ok { .. } | IndexHealth::Empty => Some(crate::modsindex::SCHEMA),
            _ => None,
        },
        "mods_index_guids": match health { IndexHealth::Ok { guids, .. } => Some(*guids), IndexHealth::Empty => Some(0), _ => None },
        "has_shared_mods": lib.join("shared_mods.txt").is_file(),
        "has_models_ignore": lib.join("models").join(".gitignore").is_file(),
        "has_sources": lib.join("sources.okidx").is_file() && lib.join("models").is_dir(),
    })
}

/// What the packaging scripts copy instead of parsing any library format themselves
/// (`--oklib resources-stamp [<lib>]`, `--program` for the program side alone).
pub fn stamp_json(lib: Option<&Path>) -> Value {
    let mut out = json!({
        "format": "ok-resources",
        "schema": 1,
        "version": RESOURCES_VERSION,
        "requires_resources_min": RESOURCES_MIN,
        "requires_resources_max": RESOURCES_MAX,
        "commit": build_commit(),
    });
    if let Some(lib) = lib {
        let health = crate::modsindex::health_of(lib);
        out["parts"] = parts(lib, &health);
    }
    out
}

/// The human summary (stderr), the same text the screen notice and the open's error carry.
pub fn summary(problems: &[Problem]) -> String {
    if problems.is_empty() { return "資源包與程式版本相符。".into(); }
    let mut out = String::new();
    for p in problems {
        let head = match p.level { Level::Block => "擋下", Level::Warn => "注意" };
        out.push_str(&format!("[{head}] {}\n  {}\n", p.what, p.fix));
        if let Some(cmd) = &p.command { out.push_str(&format!("  {cmd}\n")); }
    }
    out
}

/// Which commit this program was built from, when the build script put it in the environment. Only for the JSON's
/// "what am I" line; nothing is judged by it.
fn build_commit() -> &'static str { option_env!("OK_BUILD_COMMIT").unwrap_or("") }

/// Whether the gate is switched off for development (`OK_RESOURCES_CHECK=off`).
pub fn disabled() -> bool {
    std::env::var("OK_RESOURCES_CHECK").map(|v| {
        let v = v.trim().to_ascii_lowercase();
        v == "off" || v == "0" || v == "no"
    }).unwrap_or(false)
}

/// The gate as `oklib::activate` uses it: `Err` with the whole message when something blocks. Nothing here reads a
/// model file (no selftest), so an open pays a JSON read and a few SQLite reads, once per library per process.
pub fn gate(lib: &Path, game: Option<&Path>) -> Result<Vec<Problem>, String> {
    if disabled() {
        crate::profile::line("ok-extract: 相容性閘已關閉（OK_RESOURCES_CHECK=off），這次開卡可能靜默少件".into());
        return Ok(Vec::new());
    }
    let problems = check(lib, game, (RESOURCES_MIN, RESOURCES_MAX), false);
    if problems.iter().any(|p| p.level == Level::Block) {
        let blocks: Vec<Problem> = problems.iter().filter(|p| p.level == Level::Block).cloned().collect();
        return Err(summary(&blocks).trim_end().to_owned());
    }
    for p in problems.iter().filter(|p| p.level == Level::Warn) {
        crate::profile::line(format!("ok-extract: 資源包注意：{}", p.what));
    }
    Ok(problems)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The format fingerprint. Nobody can change a format this gate is about without deciding, here, what it means
    /// for an installed resource pack. This test does **not** judge compatibility -- that cannot be judged
    /// automatically; it only makes sure the decision is made on purpose.
    #[test]
    fn resource_formats_are_pinned_to_the_declared_version() {
        let actual = [
            ("mods_index_schema", crate::modsindex::SCHEMA as u32),
            ("oklib_version", crate::oklib::LIBRARY_VERSION),
            ("card_pack_version", crate::oklib::CARD_PACK_VERSION),
            ("resources_min", RESOURCES_MIN),
            ("resources_max", RESOURCES_MAX),
            ("resources_version", RESOURCES_VERSION),
        ];
        let expected = [
            ("mods_index_schema", 2u32),
            ("oklib_version", 2),
            ("card_pack_version", 2),
            ("resources_min", 3),
            ("resources_max", 3),
            ("resources_version", 3),
        ];
        for ((name, got), (_, want)) in actual.iter().zip(expected.iter()) {
            assert_eq!(got, want, "\n資源包格式變了（{name} {want} -> {got}）。\n  \
                若新程式配舊資源會開不了卡或靜默少件，請把 RESOURCES_MIN/MAX/RESOURCES_VERSION 一起 +1，\n  \
                再把這張表的期望值更新。若確定相容（舊庫照樣能用），只更新期望值，\n  \
                並在 commit 裡寫明為什麼相容。");
        }
    }

    #[test]
    fn every_problem_id_is_in_the_fixed_list() {
        let dir = std::env::temp_dir().join(format!("ok-resources-ids-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        // An empty directory: everything that can be missing is missing, which is the widest set of ids one call can
        // produce. Each one has to be a declared id (the UE side and the packaging scripts switch on them).
        let problems = check(&dir, None, (RESOURCES_MIN, RESOURCES_MAX), false);
        assert!(!problems.is_empty(), "an empty directory must not pass the gate");
        for p in &problems { assert!(IDS.contains(&p.id), "undeclared problem id {}", p.id); }
        assert!(problems.iter().any(|p| p.level == Level::Block));
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// A development tree (no `PACKAGE.json` above the library) must keep opening cards when the only thing missing is
    /// the stamp file: all three working trees build their library locally and have none (§7.2, §9). This is the one
    /// the plan says to write *before* the block, because getting it wrong stops every group from opening a card.
    #[test]
    fn a_development_tree_without_a_stamp_only_warns_about_it() {
        let dir = std::env::temp_dir().join(format!("ok-resources-dev-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        let problems = check(&dir, None, (RESOURCES_MIN, RESOURCES_MAX), false);
        let stamp: Vec<_> = problems.iter().filter(|p| p.id == "no_resources_json").collect();
        assert_eq!(stamp.len(), 1);
        assert_eq!(stamp[0].level, Level::Warn, "a development tree must not be blocked for lacking {STAMP_FILE}");
        assert_eq!(install_kind(&dir), Install::Development);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_shipped_install_without_a_stamp_is_blocked() {
        let root = std::env::temp_dir().join(format!("ok-resources-ship-{}", std::process::id()));
        let lib = root.join("Content").join("IndependentResources").join("base_v1");
        let _ = std::fs::create_dir_all(&lib);
        std::fs::write(root.join("PACKAGE.json"), br#"{"kind":"full"}"#).unwrap();
        let problems = check(&lib, None, (RESOURCES_MIN, RESOURCES_MAX), false);
        let stamp: Vec<_> = problems.iter().filter(|p| p.id == "no_resources_json").collect();
        assert_eq!(stamp.len(), 1);
        assert_eq!(stamp[0].level, Level::Block);
        assert!(matches!(install_kind(&lib), Install::Shipped { .. }));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_pack_newer_than_the_program_says_to_update_the_program() {
        let dir = std::env::temp_dir().join(format!("ok-resources-new-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        std::fs::write(dir.join(STAMP_FILE),
            serde_json::to_vec(&json!({"format":"ok-resources","version": RESOURCES_MAX + 1})).unwrap()).unwrap();
        let problems = check(&dir, None, (RESOURCES_MIN, RESOURCES_MAX), false);
        let p = problems.iter().find(|p| p.id == "resources_too_new").expect("a newer pack must be reported");
        assert_eq!(p.level, Level::Block);
        assert!(p.what.contains("程式"), "the message must point at the program, not at the resources");
        assert!(!problems.iter().any(|p| p.id == "resources_too_old"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_older_pack_is_too_old() {
        let dir = std::env::temp_dir().join(format!("ok-resources-old-{}", std::process::id()));
        let _ = std::fs::create_dir_all(&dir);
        std::fs::write(dir.join(STAMP_FILE),
            serde_json::to_vec(&json!({"format":"ok-resources","version": RESOURCES_MIN - 1,
                                       "package":"Studio-20261123-release-b","made":"2026-11-23"})).unwrap()).unwrap();
        let problems = check(&dir, None, (RESOURCES_MIN, RESOURCES_MAX), false);
        let p = problems.iter().find(|p| p.id == "resources_too_old").expect("an older pack must be reported");
        assert_eq!(p.level, Level::Block);
        assert!(p.what.contains("Studio-20261123-release-b"));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn the_escape_hatch_is_recognised_by_value_not_by_presence() {
        // `OK_RESOURCES_CHECK=1` must not switch the gate off: a variable that exists is not a variable that says off.
        for (value, off) in [("off", true), ("OFF", true), ("0", true), ("no", true), ("1", false), ("on", false)] {
            std::env::set_var("OK_RESOURCES_CHECK", value);
            assert_eq!(disabled(), off, "OK_RESOURCES_CHECK={value}");
        }
        std::env::remove_var("OK_RESOURCES_CHECK");
        assert!(!disabled());
    }
}
