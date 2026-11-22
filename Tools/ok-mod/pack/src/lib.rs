//! `ok-mod-pack`: what HF_Patch does for the original game, for OK mods (Docs/OK_MOD_FRAMEWORK_PLAN.md §9):
//!
//! - [`pack`]: check a mod folder and zip it into `<id>-<version>.okmod`, with the DLL's sha256 written into its mod.toml;
//! - [`install`]: unpack `.okmod` files into a Mods folder (refused while a game uses that folder), keep only the newest
//!   copy of an id, move the replaced one to `Mods/.old/`, record `Mods/.installed.toml`;
//! - [`verify`]: offline, what the host would do with a Mods folder: obsolete and duplicate mods moved to `.old`, every
//!   DLL's sha256 and ABI layout checked, which mods load in each mode;
//! - [`profile_save`] / [`profile_apply`]: a named set of mods and versions (HF_Patch's aligned versions).
//!
//! No downloading, no online updates.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::path::{Component, Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use ok_mod_host::manifest::{Manifest, TARGETS};
use ok_mod_host::resolve::{self, Candidate, Verdict};
use semver::{Version, VersionReq};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Obsolete list maintained with the core; `Mods/obsolete.toml` adds to it.
pub const BUILT_IN_OBSOLETE: &str = include_str!("../../obsolete.toml");

/// Folders inside a mod that go into its package besides mod.toml and the DLL.
const PACKED_DIRS: &[&str] = &["locale", "assets", "materials", "content"];

pub type Result<T> = std::result::Result<T, String>;

fn io<T>(what: &Path, r: std::io::Result<T>) -> Result<T> {
    r.map_err(|e| format!("{}: {e}", what.display()))
}

pub fn sha256_file(path: &Path) -> Result<String> {
    let bytes = io(path, std::fs::read(path))?;
    Ok(sha256_hex(&bytes))
}

fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

/// mod.toml text with `sha256 = "<hex>"` set (replaced, or added after the `dll` line).
pub fn with_sha256(text: &str, hex: &str) -> String {
    let line = format!("sha256 = \"{hex}\"");
    let mut out: Vec<String> = Vec::new();
    let mut done = false;
    for l in text.lines() {
        if l.trim_start().starts_with("sha256") && l.contains('=') && !done {
            out.push(line.clone());
            done = true;
        } else {
            out.push(l.to_string());
        }
    }
    if !done {
        let at = out.iter().position(|l| l.trim_start().starts_with("dll") && l.contains('=')).map(|i| i + 1).unwrap_or(out.len());
        out.insert(at, line);
    }
    out.join("\n") + "\n"
}

// ---------------------------------------------------------------------------------------------
// pack
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Default, Clone)]
pub struct PackOptions {
    /// The built DLL when it is not in the mod folder (e.g. `target/release/<dll>`).
    pub dll: Option<PathBuf>,
    pub out: Option<PathBuf>,
    /// Skip loading the DLL for the ABI check (only for tests building odd packages).
    pub skip_dll_check: bool,
    /// Skip the content pak check (it needs Tools/modkit_cook.lua and the engine's UnrealPak).
    pub skip_pak_check: bool,
}

#[derive(Debug, Serialize)]
pub struct PackReport {
    pub id: String,
    pub version: String,
    pub package: String,
    pub sha256: String,
    pub files: Vec<String>,
    pub rustc: Option<String>,
    pub warnings: Vec<String>,
}

/// Checks a mod folder and writes its `.okmod`.
pub fn pack(dir: &Path, opt: &PackOptions) -> Result<PackReport> {
    let manifest_path = dir.join("mod.toml");
    let text = io(&manifest_path, std::fs::read_to_string(&manifest_path))?;
    let manifest = Manifest::parse(&text)?;
    let dll = match &opt.dll {
        Some(p) => p.clone(),
        None if dir.join(&manifest.dll).is_file() => dir.join(&manifest.dll),
        None => {
            // A crate in the Tools/ok-mod workspace: its release build.
            let mut found = None;
            for up in dir.ancestors().skip(1) {
                let candidate = up.join("target/release").join(&manifest.dll);
                if candidate.is_file() {
                    found = Some(candidate);
                    break;
                }
            }
            found.ok_or_else(|| format!("{} not found next to mod.toml or in a target/release above it (give --dll)", manifest.dll))?
        }
    };
    let mut warnings = Vec::new();
    let rustc = if opt.skip_dll_check {
        None
    } else {
        Some(ok_mod_host::check_dll(&dll, &manifest)?.rustc)
    };
    check_locale(dir, &manifest)?;
    let paks = list_files(&dir.join("content"))?.into_iter().filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("pak"))).collect::<Vec<_>>();
    if !paks.is_empty() {
        if manifest.content_build.is_none() {
            return Err("content/*.pak needs content_build = \"<integration version>\" in mod.toml (section 6.11)".into());
        }
        for pak in &paks {
            if opt.skip_pak_check {
                warnings.push(format!("{}: pak check skipped", pak.display()));
            } else {
                check_pak(&manifest.id, pak)?;
            }
        }
    }

    let sha = sha256_file(&dll)?;
    let manifest_text = with_sha256(&text, &sha);
    let out = opt.out.clone().unwrap_or_else(|| PathBuf::from(format!("{}-{}.okmod", manifest.id, manifest.version)));
    if let Some(parent) = out.parent().filter(|p| !p.as_os_str().is_empty()) {
        io(parent, std::fs::create_dir_all(parent))?;
    }
    let file = io(&out, std::fs::File::create(&out))?;
    let mut zip = zip::ZipWriter::new(file);
    let options = zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
    let mut files = Vec::new();
    let mut add = |zip: &mut zip::ZipWriter<std::fs::File>, name: String, bytes: &[u8]| -> Result<()> {
        zip.start_file(name.clone(), options).map_err(|e| format!("{}: {e}", out.display()))?;
        zip.write_all(bytes).map_err(|e| format!("{}: {e}", out.display()))?;
        files.push(name);
        Ok(())
    };
    add(&mut zip, "mod.toml".into(), manifest_text.as_bytes())?;
    add(&mut zip, manifest.dll.clone(), &io(&dll, std::fs::read(&dll))?)?;
    for sub in PACKED_DIRS {
        for f in list_files(&dir.join(sub))? {
            let rel = f.strip_prefix(dir).unwrap().to_string_lossy().replace('\\', "/");
            add(&mut zip, rel, &io(&f, std::fs::read(&f))?)?;
        }
    }
    zip.finish().map_err(|e| format!("{}: {e}", out.display()))?;
    Ok(PackReport {
        id: manifest.id,
        version: manifest.version.to_string(),
        package: out.display().to_string(),
        sha256: sha,
        files,
        rustc,
        warnings,
    })
}

fn list_files(dir: &Path) -> Result<Vec<PathBuf>> {
    let mut out = Vec::new();
    if !dir.is_dir() {
        return Ok(out);
    }
    let mut stack = vec![dir.to_path_buf()];
    while let Some(d) = stack.pop() {
        for e in io(&d, std::fs::read_dir(&d))? {
            let p = io(&d, e)?.path();
            if p.is_dir() {
                stack.push(p);
            } else {
                out.push(p);
            }
        }
    }
    out.sort();
    Ok(out)
}

/// Every text id in `locale/<lang>/*.toml` must start with `mod.<id>.` (section 6.9).
fn check_locale(dir: &Path, manifest: &Manifest) -> Result<()> {
    let prefix = manifest.text_prefix();
    for f in list_files(&dir.join("locale"))? {
        if !f.extension().is_some_and(|e| e == "toml") {
            continue;
        }
        let table: toml::Table = toml::from_str(&io(&f, std::fs::read_to_string(&f))?).map_err(|e| format!("{}: {e}", f.display()))?;
        if let Some(bad) = table.keys().find(|k| !k.starts_with(&prefix)) {
            return Err(format!("{}: text id \"{bad}\" must start with {prefix}", f.display()));
        }
    }
    Ok(())
}

/// The pak check lives in Tools/modkit_cook.lua --verify for now (it reads the cooked assets' headers with UnrealPak).
fn check_pak(id: &str, pak: &Path) -> Result<()> {
    let cwd = std::env::current_dir().unwrap_or_default();
    let root = cwd.ancestors().find(|d| d.join("Tools/modkit_cook.lua").is_file()).ok_or("content pak check needs Tools/modkit_cook.lua (run from the ModKit checkout, or pass --skip-pak-check)")?;
    let out = std::process::Command::new(root.join("Tools/lua/lua.exe"))
        .arg(root.join("Tools/modkit_cook.lua"))
        // The ModKit names a mod by its content root (the plugin name: the id with `.` and `-` made `_`).
        .args(["--mod", &ok_mod_host::content::content_root(id), "--verify"])
        .arg(pak)
        .current_dir(root)
        .output()
        .map_err(|e| format!("modkit_cook.lua: {e}"))?;
    if !out.status.success() {
        return Err(format!("{} rejected by the pak check:\n{}{}", pak.display(), String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr)));
    }
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// obsolete list, installed record
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Deserialize)]
pub struct Obsolete {
    pub id: String,
    pub versions: VersionReq,
    pub reason: String,
}

#[derive(Debug, Default, Deserialize)]
struct ObsoleteFile {
    #[serde(default)]
    obsolete: Vec<Obsolete>,
}

/// The built-in list plus `Mods/obsolete.toml`.
pub fn obsolete_list(mods: &Path) -> Result<Vec<Obsolete>> {
    let mut list = toml::from_str::<ObsoleteFile>(BUILT_IN_OBSOLETE).map_err(|e| format!("built-in obsolete.toml: {e}"))?.obsolete;
    let extra = mods.join("obsolete.toml");
    if extra.is_file() {
        list.extend(toml::from_str::<ObsoleteFile>(&io(&extra, std::fs::read_to_string(&extra))?).map_err(|e| format!("{}: {e}", extra.display()))?.obsolete);
    }
    Ok(list)
}

fn obsolete_reason(list: &[Obsolete], id: &str, version: &Version) -> Option<String> {
    list.iter().find(|o| o.id == id && o.versions.matches(version)).map(|o| o.reason.clone())
}

#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq)]
pub struct InstalledRecord {
    #[serde(default)]
    pub profile: Option<String>,
    #[serde(default, rename = "mod")]
    pub mods: Vec<InstalledMod>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InstalledMod {
    pub id: String,
    pub version: String,
    pub sha256: String,
    pub folder: String,
    pub package: String,
    pub installed_at: u64,
}

pub fn read_installed(mods: &Path) -> Result<InstalledRecord> {
    let p = mods.join(".installed.toml");
    if !p.is_file() {
        return Ok(InstalledRecord::default());
    }
    toml::from_str(&io(&p, std::fs::read_to_string(&p))?).map_err(|e| format!("{}: {e}", p.display()))
}

fn write_installed(mods: &Path, rec: &InstalledRecord) -> Result<()> {
    let p = mods.join(".installed.toml");
    let text = format!("# Written by ok-mod-pack: what was installed from which package.\n{}", toml::to_string(rec).map_err(|e| e.to_string())?);
    io(&p, std::fs::write(&p, text))
}

/// Installed mods: folder → manifest (folders whose mod.toml does not parse are listed with the error).
fn installed(mods: &Path) -> Result<Vec<(PathBuf, std::result::Result<Manifest, String>)>> {
    let mut out = Vec::new();
    if !mods.is_dir() {
        return Ok(out);
    }
    for e in io(mods, std::fs::read_dir(mods))? {
        let p = io(mods, e)?.path();
        let name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        if !p.is_dir() || name.starts_with('.') || name == "profiles" || !p.join("mod.toml").is_file() {
            continue;
        }
        let m = std::fs::read_to_string(p.join("mod.toml")).map_err(|e| e.to_string()).and_then(|t| Manifest::parse(&t));
        out.push((p, m));
    }
    out.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(out)
}

/// Moves a mod folder to `Mods/.old/<folder>-<version>-<time>/` and writes why next to it.
fn retire(mods: &Path, folder: &Path, version: &str, reason: &str) -> Result<PathBuf> {
    let old = mods.join(".old");
    io(&old, std::fs::create_dir_all(&old))?;
    let name = folder.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let mut dest = old.join(format!("{name}-{version}-{}", now()));
    let mut n = 1;
    while dest.exists() {
        dest = old.join(format!("{name}-{version}-{}-{n}", now()));
        n += 1;
    }
    io(folder, std::fs::rename(folder, &dest))?;
    let _ = std::fs::write(dest.join("RETIRED.txt"), format!("{reason}\n"));
    Ok(dest)
}

// ---------------------------------------------------------------------------------------------
// install
// ---------------------------------------------------------------------------------------------

/// A running game of the checkout that holds `mods` and uses that Mods folder: its pid. Read from the games' control
/// files (`Saved/OKControl/<pid>.json`, `mods_dir` published by the game) and confirmed by its UI port answering.
pub fn game_using(mods: &Path) -> Option<u64> {
    let target = normalize(mods);
    for root in mods.ancestors() {
        let dir = root.join("Saved/OKControl");
        let Ok(read) = std::fs::read_dir(&dir) else { continue };
        for e in read.flatten() {
            let Ok(text) = std::fs::read_to_string(e.path()) else { continue };
            let Ok(v) = serde_json::from_str::<serde_json::Value>(&text) else { continue };
            let Some(dir) = v["mods_dir"].as_str() else { continue };
            if normalize(Path::new(dir)) != target {
                continue;
            }
            let port = v["port_ui"].as_str().and_then(|p| p.parse::<u16>().ok()).or_else(|| v["port_ui"].as_u64().map(|p| p as u16));
            if let Some(port) = port {
                if TcpStream::connect_timeout(&SocketAddr::from(([127, 0, 0, 1], port)), Duration::from_millis(300)).is_ok() {
                    return v["pid"].as_u64().or(Some(0));
                }
            }
        }
    }
    None
}

fn normalize(p: &Path) -> String {
    let abs = if p.is_absolute() { p.to_path_buf() } else { std::env::current_dir().unwrap_or_default().join(p) };
    let mut parts: Vec<String> = Vec::new();
    for c in abs.components() {
        match c {
            Component::ParentDir => {
                parts.pop();
            }
            Component::CurDir => {}
            other => parts.push(other.as_os_str().to_string_lossy().to_lowercase().trim_end_matches(['\\', '/']).to_string()),
        }
    }
    parts.join("/")
}

#[derive(Debug, Default, Clone)]
pub struct InstallOptions {
    /// Install even when a game uses the folder or the installed copy is newer.
    pub force: bool,
    pub profile: Option<String>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct InstallOutcome {
    pub package: String,
    pub id: String,
    pub version: String,
    /// installed, upgraded, already_installed, kept_newer, refused
    pub result: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

pub fn install(packages: &[PathBuf], mods: &Path, opt: &InstallOptions) -> Result<Vec<InstallOutcome>> {
    if let Some(pid) = game_using(mods) {
        if !opt.force {
            return Err(format!("a game (pid {pid}) is using {}; close it first (or --force)", mods.display()));
        }
    }
    io(mods, std::fs::create_dir_all(mods))?;
    let obsolete = obsolete_list(mods)?;
    let mut record = read_installed(mods)?;
    let mut out = Vec::new();
    for package in packages {
        out.push(install_one(package, mods, &obsolete, &mut record, opt)?);
    }
    if opt.profile.is_some() {
        record.profile = opt.profile.clone();
    }
    write_installed(mods, &record)?;
    Ok(out)
}

fn install_one(package: &Path, mods: &Path, obsolete: &[Obsolete], record: &mut InstalledRecord, opt: &InstallOptions) -> Result<InstallOutcome> {
    let staging = mods.join(".staging").join(format!("{}-{}", now(), std::process::id()));
    let _ = std::fs::remove_dir_all(&staging);
    io(&staging, std::fs::create_dir_all(&staging))?;
    let result = (|| {
        let file = io(package, std::fs::File::open(package))?;
        let mut zip = zip::ZipArchive::new(file).map_err(|e| format!("{}: {e}", package.display()))?;
        for i in 0..zip.len() {
            let mut entry = zip.by_index(i).map_err(|e| format!("{}: {e}", package.display()))?;
            let Some(rel) = entry.enclosed_name() else {
                return Err(format!("{}: entry \"{}\" points outside the mod folder", package.display(), entry.name()));
            };
            let dest = staging.join(rel);
            if entry.is_dir() {
                io(&dest, std::fs::create_dir_all(&dest))?;
                continue;
            }
            if let Some(parent) = dest.parent() {
                io(parent, std::fs::create_dir_all(parent))?;
            }
            let mut bytes = Vec::new();
            entry.read_to_end(&mut bytes).map_err(|e| format!("{}: {e}", package.display()))?;
            io(&dest, std::fs::write(&dest, bytes))?;
        }
        let manifest = Manifest::parse(&io(&staging.join("mod.toml"), std::fs::read_to_string(staging.join("mod.toml")))?)?;
        let sha = manifest.sha256.clone().ok_or_else(|| format!("{}: mod.toml has no sha256 (not made by ok-mod-pack pack)", package.display()))?;
        let actual = sha256_file(&staging.join(&manifest.dll))?;
        if !actual.eq_ignore_ascii_case(&sha) {
            return Err(format!("{}: {} sha256 is {actual}, mod.toml says {sha}", package.display(), manifest.dll));
        }
        Ok((manifest, sha))
    })();
    let (manifest, sha) = match result {
        Ok(v) => v,
        Err(e) => {
            let _ = std::fs::remove_dir_all(&staging);
            return Err(e);
        }
    };
    let outcome = |result: &str, detail: Option<String>| InstallOutcome {
        package: package.display().to_string(),
        id: manifest.id.clone(),
        version: manifest.version.to_string(),
        result: result.into(),
        detail,
    };
    if let Some(reason) = obsolete_reason(obsolete, &manifest.id, &manifest.version) {
        let _ = std::fs::remove_dir_all(&staging);
        return Ok(outcome("refused", Some(format!("on the obsolete list: {reason}"))));
    }
    // Same id already there: only the newest stays.
    let mut replaced = None;
    for (folder, m) in installed(mods)? {
        let Ok(m) = m else { continue };
        if m.id != manifest.id {
            continue;
        }
        if m.version == manifest.version && m.sha256.as_deref().is_some_and(|s| s.eq_ignore_ascii_case(&sha)) && !opt.force {
            let _ = std::fs::remove_dir_all(&staging);
            return Ok(outcome("already_installed", None));
        }
        if m.version > manifest.version && !opt.force {
            let _ = std::fs::remove_dir_all(&staging);
            return Ok(outcome("kept_newer", Some(format!("{} {} is installed", m.id, m.version))));
        }
        let moved = retire(mods, &folder, &m.version.to_string(), &format!("replaced by {} {} from {}", manifest.id, manifest.version, package.display()))?;
        replaced = Some(moved);
    }
    let dest = mods.join(&manifest.id);
    if dest.exists() {
        // A folder of that name holding something else (no or broken mod.toml).
        retire(mods, &dest, "unknown", "folder name taken by the new install")?;
    }
    io(&dest, std::fs::rename(&staging, &dest))?;
    let _ = std::fs::remove_dir(mods.join(".staging"));
    record.mods.retain(|r| r.id != manifest.id);
    record.mods.push(InstalledMod {
        id: manifest.id.clone(),
        version: manifest.version.to_string(),
        sha256: sha,
        folder: manifest.id.clone(),
        package: package.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default(),
        installed_at: now(),
    });
    record.mods.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(match replaced {
        Some(old) => outcome("upgraded", Some(format!("previous copy moved to {}", old.display()))),
        None => outcome("installed", None),
    })
}

// ---------------------------------------------------------------------------------------------
// verify
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Default, Serialize)]
pub struct VerifyReport {
    pub mods_dir: String,
    /// Mods moved to .old (obsolete, older duplicate), with the reason.
    pub retired: Vec<String>,
    /// Per mod folder: problems found (sha256, ABI layout, mod.toml).
    pub problems: BTreeMap<String, String>,
    /// Per mode: the mods that would load, in order.
    pub loads: BTreeMap<String, Vec<String>>,
    /// Per mode: mods that would not load and why.
    pub rejected: BTreeMap<String, BTreeMap<String, String>>,
}

impl VerifyReport {
    pub fn ok(&self) -> bool {
        self.problems.is_empty() && self.rejected.values().all(|r| r.is_empty())
    }
}

/// `dry_run`: report what would be moved, move nothing.
pub fn verify(mods: &Path, dry_run: bool) -> Result<VerifyReport> {
    let mut report = VerifyReport { mods_dir: mods.display().to_string(), ..Default::default() };
    let obsolete = obsolete_list(mods)?;
    // Obsolete mods, then older duplicates, go to .old.
    let mut list = installed(mods)?;
    let mut newest: BTreeMap<String, Version> = BTreeMap::new();
    for (_, m) in &list {
        if let Ok(m) = m {
            let v = newest.entry(m.id.clone()).or_insert_with(|| m.version.clone());
            if m.version > *v {
                *v = m.version.clone();
            }
        }
    }
    let mut seen_newest: HashSet<String> = HashSet::new();
    let mut keep = Vec::new();
    for (folder, m) in list.drain(..) {
        let retire_why = match &m {
            Ok(m) => obsolete_reason(&obsolete, &m.id, &m.version).map(|r| format!("obsolete: {r}")).or_else(|| {
                if m.version < newest[&m.id] || !seen_newest.insert(m.id.clone()) {
                    Some(format!("duplicate: {} {} is also installed", m.id, newest[&m.id]))
                } else {
                    None
                }
            }),
            Err(_) => None,
        };
        match retire_why {
            Some(why) => {
                let version = m.as_ref().map(|m| m.version.to_string()).unwrap_or_default();
                let line = if dry_run {
                    format!("{} would be moved to .old ({why})", folder.display())
                } else {
                    format!("{} moved to {} ({why})", folder.display(), retire(mods, &folder, &version, &why)?.display())
                };
                report.retired.push(line);
            }
            None => keep.push((folder, m)),
        }
    }
    for (folder, m) in &keep {
        let key = folder.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
        match m {
            Err(e) => {
                report.problems.insert(key, e.clone());
            }
            Ok(m) => {
                let dll = folder.join(&m.dll);
                if let Some(sha) = &m.sha256 {
                    match sha256_file(&dll) {
                        Ok(actual) if actual.eq_ignore_ascii_case(sha) => {}
                        Ok(actual) => {
                            report.problems.insert(key.clone(), format!("{} sha256 is {actual}, mod.toml says {sha}", m.dll));
                            continue;
                        }
                        Err(e) => {
                            report.problems.insert(key.clone(), e);
                            continue;
                        }
                    }
                }
                if let Err(e) = ok_mod_host::check_dll(&dll, m) {
                    report.problems.insert(key, e);
                }
            }
        }
    }
    // What the host would load in each mode (dependencies, api, cycles) from the mods that passed.
    let bad: BTreeSet<String> = report.problems.keys().cloned().collect();
    for target in TARGETS {
        let candidates = keep
            .iter()
            .filter(|(f, _)| !bad.contains(&f.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()))
            .map(|(f, m)| Candidate { dir: f.clone(), manifest: m.clone() })
            .collect();
        let resolved = resolve::resolve(candidates, &[target.to_string()], &HashSet::new(), ok_mod_host::host_api());
        let mut order: Vec<(usize, String)> = Vec::new();
        let mut rejected = BTreeMap::new();
        for r in resolved {
            match r.verdict {
                Verdict::Load(n) => order.push((n, r.id)),
                Verdict::Reject(why) => {
                    rejected.insert(r.id, why);
                }
                Verdict::Skip(_) => {}
            }
        }
        order.sort();
        report.loads.insert(target.to_string(), order.into_iter().map(|(_, id)| id).collect());
        report.rejected.insert(target.to_string(), rejected);
    }
    Ok(report)
}

// ---------------------------------------------------------------------------------------------
// profiles
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Profile {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description_id: Option<String>,
    #[serde(default, rename = "mod")]
    pub mods: Vec<ProfileMod>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ProfileMod {
    pub id: String,
    pub version: String,
}

pub fn read_profile(path: &Path) -> Result<Profile> {
    toml::from_str(&io(path, std::fs::read_to_string(path))?).map_err(|e| format!("{}: {e}", path.display()))
}

/// Records the installed mods and versions as `Mods/profiles/<name>.toml` (or `out`).
pub fn profile_save(mods: &Path, name: &str, out: Option<&Path>) -> Result<PathBuf> {
    let mut profile = Profile { name: name.into(), ..Default::default() };
    for (_, m) in installed(mods)? {
        if let Ok(m) = m {
            profile.mods.push(ProfileMod { id: m.id, version: m.version.to_string() });
        }
    }
    profile.mods.sort_by(|a, b| a.id.cmp(&b.id));
    let path = out.map(Path::to_path_buf).unwrap_or_else(|| mods.join("profiles").join(format!("{name}.toml")));
    if let Some(parent) = path.parent() {
        io(parent, std::fs::create_dir_all(parent))?;
    }
    io(&path, std::fs::write(&path, toml::to_string(&profile).map_err(|e| e.to_string())?))?;
    Ok(path)
}

/// Makes the Mods folder hold exactly the profile: missing or other versions are installed from `packages`
/// (`<id>-<version>.okmod`), mods not in the profile go to `.old`.
pub fn profile_apply(profile_path: &Path, mods: &Path, packages: &Path, opt: &InstallOptions) -> Result<Vec<InstallOutcome>> {
    let profile = read_profile(profile_path)?;
    if let Some(pid) = game_using(mods) {
        if !opt.force {
            return Err(format!("a game (pid {pid}) is using {}; close it first (or --force)", mods.display()));
        }
    }
    io(mods, std::fs::create_dir_all(mods))?;
    let wanted: BTreeMap<String, String> = profile.mods.iter().map(|m| (m.id.clone(), m.version.clone())).collect();
    let mut record = read_installed(mods)?;
    for (folder, m) in installed(mods)? {
        let Ok(m) = m else { continue };
        if !wanted.contains_key(&m.id) {
            retire(mods, &folder, &m.version.to_string(), &format!("not in profile {}", profile.name))?;
            record.mods.retain(|r| r.id != m.id);
        }
    }
    write_installed(mods, &record)?;
    let mut to_install = Vec::new();
    let mut out = Vec::new();
    let have: BTreeMap<String, String> = installed(mods)?.into_iter().filter_map(|(_, m)| m.ok()).map(|m| (m.id, m.version.to_string())).collect();
    for (id, version) in &wanted {
        if have.get(id) == Some(version) {
            out.push(InstallOutcome { package: String::new(), id: id.clone(), version: version.clone(), result: "already_installed".into(), detail: None });
            continue;
        }
        let package = packages.join(format!("{id}-{version}.okmod"));
        if !package.is_file() {
            return Err(format!("profile {} needs {id} {version}: {} not found", profile.name, package.display()));
        }
        to_install.push(package);
    }
    // A different version that is newer would be kept: the profile pins versions, so force the swap.
    let opt = InstallOptions { force: true, profile: Some(profile.name.clone()) };
    out.extend(install(&to_install, mods, &opt)?);
    let mut record = read_installed(mods)?;
    record.profile = Some(profile.name.clone());
    write_installed(mods, &record)?;
    Ok(out)
}
