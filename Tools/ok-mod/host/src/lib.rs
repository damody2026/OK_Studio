//! `ok-mod-host`: finds the mods in `Mods/`, decides which load (dependencies, target, api), loads
//! their DLLs through abi_stable, dispatches events and disables a mod that panics
//! (Docs/OK_MOD_FRAMEWORK_PLAN.md §3, §6.1, §7).
//!
//! Unreal loads the cdylib `ok_mod_host.dll` and talks to it through the flat `okm_*` C functions
//! (`include/ok_mod_host.h`, `src/ffi.rs`); the ok-extract CLI links the rlib and uses [`ModHost`]
//! directly.

pub mod config;
pub mod ffi;
pub mod manifest;
pub mod resolve;

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};

use ok_mod_api::abi_stable::{
    library::lib_header_from_path,
    prefix_type::PrefixTypeTrait,
    std_types::{RNone, ROption, RResult, RSome, RStr},
};
use ok_mod_api::{
    ConfigValue, ConfigValue_NE, Declaration, Event, Event_NE, HostApi, HostApiRef, LogLevel, ModError, ModErrorKind, ModHandle,
    ModInstanceBox, OkModRef, Reply,
};
use serde::Serialize;

use crate::config::{Entry, Store};
use crate::manifest::Manifest;
use crate::resolve::{Candidate, Verdict};

pub use ok_mod_api;

pub const HOST_VERSION: &str = env!("CARGO_PKG_VERSION");

/// `(major, minor)` of the `ok-mod-api` this host implements.
pub fn host_api() -> (u64, u64) {
    manifest::parse_api(ok_mod_api::API_VERSION.rsplit_once('.').map(|(mm, _)| mm).unwrap_or("0.0")).unwrap_or((0, 0))
}

/// Receives every log line: level, mod id (empty for the host itself), message.
pub type LogSink = Arc<dyn Fn(LogLevel, &str, &str) + Send + Sync>;

#[derive(Debug, Clone)]
pub struct HostConfig {
    /// `<stage root>/Mods` (checkout root `Mods/` while developing).
    pub mods_dir: PathBuf,
    /// Where config values are kept (`UserData/config/mods`); `None` keeps them in memory only.
    pub config_dir: Option<PathBuf>,
    /// `reader`, `studio`, `pair`, `street` or `extract`.
    pub target: String,
    /// `-NoMods`: discover nothing, load nothing.
    pub no_mods: bool,
    /// Mod ids the player turned off.
    pub disabled: HashSet<String>,
}

impl HostConfig {
    pub fn new(mods_dir: impl Into<PathBuf>, target: &str) -> Self {
        HostConfig { mods_dir: mods_dir.into(), config_dir: None, target: target.into(), no_mods: false, disabled: HashSet::new() }
    }
}

/// What the mod list shows for one mod.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ModStatus {
    pub id: String,
    pub name: String,
    pub version: String,
    pub dir: String,
    /// `enabled`, `skipped`, `rejected`, `faulted` or `disabled`.
    pub state: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rustc: Option<String>,
    /// Full console command names, `mod.<id>.<name>`.
    pub commands: Vec<String>,
    pub subscriptions: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
enum State {
    Enabled,
    Skipped(String),
    Rejected(String),
    Faulted(String),
    Disabled(String),
}

/// What a mod's callbacks into the host need; looked up by handle.
struct Shared {
    id: String,
    log: LogSink,
    config: Mutex<Store>,
}

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

fn registry() -> &'static Mutex<HashMap<u64, Arc<Shared>>> {
    static R: OnceLock<Mutex<HashMap<u64, Arc<Shared>>>> = OnceLock::new();
    R.get_or_init(Default::default)
}

fn shared(h: ModHandle) -> Option<Arc<Shared>> {
    lock(registry()).get(&h.0).cloned()
}

static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

// Callbacks a mod calls. They run inside a mod's call stack and must never unwind into it.

extern "C" fn cb_log(h: ModHandle, level: LogLevel, message: RStr<'_>) {
    let _ = std::panic::catch_unwind(|| {
        if let Some(s) = shared(h) {
            (s.log)(level, &s.id, message.as_str());
        }
    });
}

// NonExhaustive is stored as plain bytes; the lint only sees the PhantomData of the enum.
#[allow(improper_ctypes_definitions)]
extern "C" fn cb_config_get(h: ModHandle, key: RStr<'_>) -> ROption<ConfigValue_NE> {
    std::panic::catch_unwind(|| match shared(h).and_then(|s| lock(&s.config).get(key.as_str())) {
        Some(v) => RSome(ConfigValue_NE::new(v)),
        None => RNone,
    })
    .unwrap_or(RNone)
}

#[allow(improper_ctypes_definitions)]
extern "C" fn cb_config_set(h: ModHandle, key: RStr<'_>, value: ConfigValue_NE) -> RResult<(), ModError> {
    let result = std::panic::catch_unwind(|| {
        let s = shared(h).ok_or("unknown mod handle")?;
        let value = value.as_enum().map_err(|_| "config value type unknown to this host".to_string())?.clone();
        let result = lock(&s.config).set(key.as_str(), value);
        result
    })
    .unwrap_or_else(|_| Err("host error while setting config".into()));
    match result {
        Ok(()) => RResult::ROk(()),
        Err(e) => RResult::RErr(ModError::new(ModErrorKind::ERROR, e)),
    }
}

fn host_api_ref() -> HostApiRef {
    static API: OnceLock<HostApiRef> = OnceLock::new();
    *API.get_or_init(|| {
        HostApi { host_version: RStr::from_str(HOST_VERSION), log: cb_log, config_get: cb_config_get, config_set: cb_config_set }
            .leak_into_prefix()
    })
}

struct Loaded {
    instance: ModInstanceBox,
    handle: ModHandle,
    shared: Arc<Shared>,
    commands: Vec<String>,
    subscriptions: HashSet<String>,
    rustc: String,
}

struct ModEntry {
    id: String,
    manifest: Option<Manifest>,
    dir: PathBuf,
    state: State,
    order: Option<usize>,
    loaded: Option<Loaded>,
    /// Load was attempted (successfully or not).
    tried: bool,
}

/// Result of one mod's handling of an event or command.
#[derive(Debug, Clone, PartialEq)]
pub struct ModReply {
    pub id: String,
    pub result: Result<Reply, String>,
}

pub struct ModHost {
    config: HostConfig,
    log: LogSink,
    mods: Vec<ModEntry>,
    /// Indices into `mods`, in load order.
    order: Vec<usize>,
    /// Modes this process has run (`HostConfig::target` first).
    targets: Vec<String>,
    closed: bool,
}

impl ModHost {
    /// Discovers, resolves and loads the mods, then sends `Enabled` to each loaded mod in order.
    /// Never fails as a whole: every problem only affects the mod it belongs to.
    pub fn open(config: HostConfig, log: LogSink) -> ModHost {
        let targets = vec![config.target.clone()];
        let mut host = ModHost { config, log, mods: Vec::new(), order: Vec::new(), targets, closed: false };
        if host.config.no_mods {
            host.host_log(LogLevel::Info, "mods are off (-NoMods)");
            return host;
        }
        host.scan();
        host
    }

    /// Discovers and resolves for every mode of this process, then loads what may load and was not
    /// tried yet, in order, and sends those `Enabled`. A mod tried once (loaded, refused at load,
    /// faulted) is never tried again in this process.
    fn scan(&mut self) {
        let candidates = discover(&self.config.mods_dir);
        let resolved = resolve::resolve(candidates, &self.targets, &self.config.disabled, host_api());
        let mut to_load: Vec<(usize, usize)> = Vec::new();
        for r in resolved {
            let (state, order) = match r.verdict {
                Verdict::Load(n) => (State::Enabled, Some(n)),
                Verdict::Skip(why) => (State::Skipped(why), None),
                Verdict::Reject(why) => (State::Rejected(why), None),
            };
            let idx = match self.mods.iter().position(|m| m.dir == r.dir) {
                Some(i) if self.mods[i].tried => continue,
                Some(i) => i,
                None => {
                    self.mods.push(ModEntry { id: r.id.clone(), manifest: None, dir: r.dir.clone(), state: State::Skipped(String::new()), order: None, loaded: None, tried: false });
                    self.mods.len() - 1
                }
            };
            let m = &mut self.mods[idx];
            m.id = r.id;
            m.manifest = r.manifest;
            m.state = state;
            m.order = order;
            if let Some(n) = order {
                to_load.push((n, idx));
            }
        }
        to_load.sort();
        let mut fresh = Vec::new();
        for (_, idx) in to_load {
            self.mods[idx].tried = true;
            self.load(idx);
            if self.mods[idx].state == State::Enabled {
                self.order.push(idx);
                fresh.push(idx);
            }
        }
        for m in &self.mods {
            match &m.state {
                State::Rejected(why) if !m.tried || m.loaded.is_none() => self.host_log(LogLevel::Warn, &format!("{} not loaded: {why}", m.id)),
                State::Skipped(why) => self.host_log(LogLevel::Verbose, &format!("{} skipped: {why}", m.id)),
                _ => {}
            }
        }
        for idx in fresh {
            let _ = self.call_event(idx, &Event::Enabled);
        }
        let enabled: Vec<&str> = self.order.iter().filter(|i| self.mods[**i].state == State::Enabled).map(|i| self.mods[*i].id.as_str()).collect();
        self.host_log(
            LogLevel::Info,
            &format!("mode {}: {} mod(s) enabled{}{}", self.targets.join("/"), enabled.len(), if enabled.is_empty() { "" } else { ": " }, enabled.join(", ")),
        );
    }

    /// A game mode starts in this process (`reader`, `studio`, `pair`, `street`): mods for it that
    /// are not loaded yet are loaded, then subscribers get `mode_enter`. The street hands over to the
    /// 1-on-1 scene in the same process, so a process can run several modes.
    pub fn enter_mode(&mut self, mode: &str) -> Vec<ModReply> {
        if !self.config.no_mods && !self.targets.iter().any(|t| t == mode) {
            self.targets.push(mode.to_string());
            self.scan();
        }
        self.dispatch(&Event::ModeEnter { mode: mode.into() })
    }

    /// Subscribers get `mode_exit`; the mods stay loaded.
    pub fn exit_mode(&mut self, mode: &str) -> Vec<ModReply> {
        self.dispatch(&Event::ModeExit { mode: mode.into() })
    }

    /// The modes this process has run, first one first.
    pub fn modes(&self) -> &[String] {
        &self.targets
    }

    fn host_log(&self, level: LogLevel, message: &str) {
        (self.log)(level, "", message);
    }

    fn load(&mut self, idx: usize) {
        match self.try_load(idx) {
            Ok(loaded) => self.mods[idx].loaded = Some(loaded),
            Err(state) => self.mods[idx].state = state,
        }
    }

    fn try_load(&mut self, idx: usize) -> Result<Loaded, State> {
        let entry = &self.mods[idx];
        let manifest = entry.manifest.clone().expect("only resolved mods load");
        let dll = entry.dir.join(&manifest.dll);
        let reject = |why: String| State::Rejected(why);
        if !dll.is_file() {
            return Err(reject(format!("{} is missing", dll.display())));
        }
        let header = lib_header_from_path(&dll).map_err(|e| reject(format!("cannot load {}: {}", dll.display(), first_lines(&e.to_string(), 6))))?;
        let root = header.init_root_module::<OkModRef>().map_err(|e| {
            let text = e.to_string();
            self.host_log(LogLevel::Verbose, &format!("{}: abi_stable says:\n{text}", manifest.id));
            reject(format!("not a compatible ok_mod DLL (ok-mod-api ABI {}): {}", ok_mod_api::ABI_VERSION, first_lines(&text, 6)))
        })?;
        let build = (root.build_info())();
        let rustc = build.rustc_version.to_string();
        if !build.panic_unwind {
            return Err(reject("built with panic = \"abort\"; mods must use panic = \"unwind\" so a panic cannot take the game down".into()));
        }
        let embedded = Manifest::parse((root.manifest())().as_str()).map_err(|e| reject(format!("mod.toml compiled into the DLL: {e}")))?;
        if embedded.id != manifest.id || embedded.version != manifest.version {
            return Err(reject(format!(
                "DLL is {} {} but mod.toml says {} {}",
                embedded.id, embedded.version, manifest.id, manifest.version
            )));
        }

        let handle = ModHandle(NEXT_HANDLE.fetch_add(1, Ordering::Relaxed));
        let shared = Arc::new(Shared { id: manifest.id.clone(), log: self.log.clone(), config: Mutex::new(Store::default()) });
        lock(registry()).insert(handle.0, shared.clone());
        let unregister = |state: State| {
            lock(registry()).remove(&handle.0);
            state
        };

        let mut instance = match (root.create())(host_api_ref(), handle).into_result() {
            Ok(i) => i,
            Err(e) => return Err(unregister(fault_or_reject("create", &e))),
        };
        let registration = match instance.register().into_result() {
            Ok(r) => r,
            Err(e) => {
                let state = fault_or_reject("register", &e);
                if e.is_fault() {
                    std::mem::forget(instance);
                }
                return Err(unregister(state));
            }
        };

        let prefix = manifest.text_prefix();
        let mut commands = Vec::new();
        let mut subscriptions = HashSet::new();
        let mut entries: Vec<Entry> = Vec::new();
        let mut problems = Vec::new();
        for decl in registration.declarations.iter() {
            match decl.as_enum() {
                Ok(Declaration::Config(c)) => match Entry::from_decl(c) {
                    Some(e) if valid_key(&e.key) && !entries.iter().any(|x| x.key == e.key) => {
                        if let Err(err) = e.check(e.default.clone()) {
                            problems.push(format!("config {}: default does not fit: {err}", e.key));
                        }
                        if !e.description_id.starts_with(&prefix) {
                            problems.push(format!("config {}: text id {} must start with {prefix}", e.key, e.description_id));
                        }
                        entries.push(e);
                    }
                    Some(e) => problems.push(format!("config key \"{}\" is invalid or declared twice", e.key)),
                    None => problems.push("config entry of a type this host does not know".into()),
                },
                Ok(Declaration::Command(c)) => {
                    let name = c.name.as_str();
                    if valid_key(name) && !commands.iter().any(|x: &String| x == name) {
                        commands.push(name.to_string());
                    } else {
                        problems.push(format!("command \"{name}\" is invalid or declared twice"));
                    }
                    if !c.description_id.as_str().starts_with(&prefix) {
                        problems.push(format!("command {name}: text id {} must start with {prefix}", c.description_id));
                    }
                }
                Ok(Declaration::Subscribe(name)) => {
                    subscriptions.insert(name.to_string());
                }
                Err(_) => problems.push("a declaration of a kind this host does not know (mod built for a newer API?)".into()),
                Ok(_) => problems.push("a declaration of a kind this host does not handle".into()),
            }
        }
        for p in &problems {
            (self.log)(LogLevel::Warn, &manifest.id, p);
        }
        let config_path = self.config.config_dir.as_ref().map(|d| d.join(format!("{}.toml", manifest.id)));
        for w in lock(&shared.config).declare(entries, config_path) {
            (self.log)(LogLevel::Warn, &manifest.id, &w);
        }
        (self.log)(LogLevel::Info, &manifest.id, &format!("loaded {} {} (built with {rustc})", manifest.name, manifest.version));
        Ok(Loaded { instance, handle, shared, commands, subscriptions, rustc })
    }

    fn find(&self, id: &str) -> Result<usize, String> {
        self.mods.iter().position(|m| m.id == id).ok_or_else(|| format!("no mod {id}"))
    }

    /// Calls one enabled mod; a panic (or a mod that already panicked) marks it faulted.
    fn call_event(&mut self, idx: usize, event: &Event) -> Result<Reply, String> {
        if self.mods[idx].state != State::Enabled {
            return Err(format!("{} is not enabled", self.mods[idx].id));
        }
        let loaded = self.mods[idx].loaded.as_mut().expect("enabled mods are loaded");
        let result = loaded.instance.on_event(&Event_NE::new(event.clone())).into_result();
        match result {
            Ok(reply) => Ok(reply.as_enum().ok().cloned().unwrap_or(Reply::None)),
            Err(e) if e.is_fault() => {
                let why = e.message.to_string();
                self.fault(idx, &why);
                Err(why)
            }
            Err(e) => Err(e.message.to_string()),
        }
    }

    fn fault(&mut self, idx: usize, why: &str) {
        let m = &mut self.mods[idx];
        m.state = State::Faulted(why.to_string());
        (self.log)(LogLevel::Error, &m.id, &format!("disabled after a panic: {why}"));
        // The mod's state may be broken: never call it again, not even its destructor.
        if let Some(loaded) = m.loaded.take() {
            lock(registry()).remove(&loaded.handle.0);
            std::mem::forget(loaded.instance);
        }
    }

    /// Sends an event to every enabled mod that subscribed to it, in load order.
    pub fn dispatch(&mut self, event: &Event) -> Vec<ModReply> {
        let name = event.subscription();
        let mut replies = Vec::new();
        for idx in self.order.clone() {
            let wants = self.mods[idx].loaded.as_ref().is_some_and(|l| l.subscriptions.contains(name));
            if self.mods[idx].state == State::Enabled && wants {
                let result = self.call_event(idx, event);
                replies.push(ModReply { id: self.mods[idx].id.clone(), result });
            }
        }
        replies
    }

    /// A named hook (`Event::Hook`) to every enabled mod subscribed to it, in load order.
    pub fn hook(&mut self, name: &str, payload: &str) -> Vec<ModReply> {
        self.dispatch(&Event::Hook { name: name.into(), payload: payload.into() })
    }

    /// Enabled mods subscribed to `name`, in load order.
    pub fn subscribers(&self, name: &str) -> Vec<String> {
        self.order.iter().filter(|&&idx| self.mods[idx].state == State::Enabled
            && self.mods[idx].loaded.as_ref().is_some_and(|l| l.subscriptions.contains(name)))
            .map(|&idx| self.mods[idx].id.clone()).collect()
    }

    /// A named hook to one mod; an error when it is not enabled or did not subscribe to the hook.
    pub fn hook_one(&mut self, id: &str, name: &str, payload: &str) -> Result<Reply, String> {
        let idx = self.find(id)?;
        let wants = self.mods[idx].loaded.as_ref().is_some_and(|l| l.subscriptions.contains(name));
        if !wants {
            return Err(format!("{id} did not subscribe to {name}"));
        }
        self.call_event(idx, &Event::Hook { name: name.into(), payload: payload.into() })
    }

    /// Runs `name` of mod `id` (console `mod.<id>.<name>` or `mod_call`).
    pub fn command(&mut self, id: &str, name: &str, args: &str) -> Result<Reply, String> {
        let idx = self.find(id)?;
        let has = self.mods[idx].loaded.as_ref().is_some_and(|l| l.commands.iter().any(|c| c == name));
        if self.mods[idx].state != State::Enabled {
            return Err(format!("{id} is not enabled"));
        }
        if !has {
            return Err(format!("{id} has no command {name}"));
        }
        self.call_event(idx, &Event::Command { name: name.into(), args: args.into() })
    }

    /// Splits `mod.<id>.<name>` into id and name.
    pub fn split_command(full: &str) -> Option<(&str, &str)> {
        let rest = full.strip_prefix("mod.")?;
        let (id, name) = rest.rsplit_once('.')?;
        Some((id, name))
    }

    /// Declared config entries of a mod with their current values.
    pub fn config(&self, id: &str) -> Result<Vec<(Entry, ConfigValue)>, String> {
        let idx = self.find(id)?;
        let loaded = self.mods[idx].loaded.as_ref().ok_or_else(|| format!("{id} is not loaded"))?;
        let store = lock(&loaded.shared.config);
        Ok(store.entries.iter().map(|e| (e.clone(), store.get(&e.key).unwrap())).collect())
    }

    /// Sets a config value as the player (settings page, MCP): checked, saved, and the mod gets
    /// `ConfigChanged` if it subscribed.
    pub fn set_config(&mut self, id: &str, key: &str, value: ConfigValue) -> Result<(), String> {
        let idx = self.find(id)?;
        let loaded = self.mods[idx].loaded.as_ref().ok_or_else(|| format!("{id} is not loaded"))?;
        lock(&loaded.shared.config).set(key, value)?;
        if loaded.subscriptions.contains("config_changed") && self.mods[idx].state == State::Enabled {
            let _ = self.call_event(idx, &Event::ConfigChanged { key: key.into() });
        }
        Ok(())
    }

    /// Turns a mod off for this session (it gets `shutdown`; the DLL stays loaded).
    pub fn disable(&mut self, id: &str) -> Result<(), String> {
        let idx = self.find(id)?;
        if self.mods[idx].state != State::Enabled {
            return Err(format!("{id} is not enabled"));
        }
        self.shutdown_one(idx);
        self.mods[idx].state = State::Disabled("disabled for this session".into());
        Ok(())
    }

    fn shutdown_one(&mut self, idx: usize) {
        if let Some(mut loaded) = self.mods[idx].loaded.take() {
            loaded.instance.shutdown();
            lock(registry()).remove(&loaded.handle.0);
            drop(loaded);
        }
    }

    pub fn statuses(&self) -> Vec<ModStatus> {
        self.mods
            .iter()
            .map(|m| {
                let (state, reason) = match &m.state {
                    State::Enabled => ("enabled", None),
                    State::Skipped(r) => ("skipped", Some(r.clone())),
                    State::Rejected(r) => ("rejected", Some(r.clone())),
                    State::Faulted(r) => ("faulted", Some(r.clone())),
                    State::Disabled(r) => ("disabled", Some(r.clone())),
                };
                let mut subscriptions: Vec<String> = m.loaded.as_ref().map(|l| l.subscriptions.iter().cloned().collect()).unwrap_or_default();
                subscriptions.sort();
                ModStatus {
                    id: m.id.clone(),
                    name: m.manifest.as_ref().map(|x| x.name.clone()).unwrap_or_default(),
                    version: m.manifest.as_ref().map(|x| x.version.to_string()).unwrap_or_default(),
                    dir: m.dir.display().to_string(),
                    state: state.into(),
                    reason,
                    order: m.order,
                    rustc: m.loaded.as_ref().map(|l| l.rustc.clone()),
                    commands: m.loaded.as_ref().map(|l| l.commands.iter().map(|c| format!("mod.{}.{c}", m.id)).collect()).unwrap_or_default(),
                    subscriptions,
                }
            })
            .collect()
    }

    pub fn target(&self) -> &str {
        &self.config.target
    }

    pub fn no_mods(&self) -> bool {
        self.config.no_mods
    }

    /// `shutdown` to every enabled mod, last loaded first. Also done on drop.
    pub fn close(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        for idx in self.order.clone().into_iter().rev() {
            if self.mods[idx].state == State::Enabled {
                self.shutdown_one(idx);
            }
        }
    }
}

impl Drop for ModHost {
    fn drop(&mut self) {
        self.close();
    }
}

fn valid_key(k: &str) -> bool {
    !k.is_empty() && k.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

fn fault_or_reject(what: &str, e: &ModError) -> State {
    if e.is_fault() {
        State::Faulted(e.message.to_string())
    } else {
        State::Rejected(format!("{what} failed: {}", e.message))
    }
}

fn first_lines(text: &str, n: usize) -> String {
    let lines: Vec<&str> = text.lines().filter(|l| !l.trim().is_empty()).collect();
    if lines.len() <= n {
        lines.join(" / ")
    } else {
        format!("{} / … ({} more lines in the verbose log)", lines[..n].join(" / "), lines.len() - n)
    }
}

/// Every `Mods/<folder>/mod.toml`; folders starting with `.` (`.old`) and `profiles` are not mods.
fn discover(mods_dir: &Path) -> Vec<Candidate> {
    let Ok(read) = std::fs::read_dir(mods_dir) else { return Vec::new() };
    let mut dirs: Vec<PathBuf> = read
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
        .map(|e| e.path())
        .filter(|p| {
            let name = p.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            !name.starts_with('.') && name != "profiles" && p.join("mod.toml").is_file()
        })
        .collect();
    dirs.sort();
    dirs.into_iter()
        .map(|dir| {
            let manifest = std::fs::read_to_string(dir.join("mod.toml")).map_err(|e| format!("mod.toml: {e}")).and_then(|t| Manifest::parse(&t));
            Candidate { dir, manifest }
        })
        .collect()
}
