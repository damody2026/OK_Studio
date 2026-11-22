//! `ok-mod-api`: every type that crosses the DLL boundary between the OK mod host and a mod.
//!
//! Types only, no logic (Docs/OK_MOD_FRAMEWORK_PLAN.md §4, §7). Mod authors depend on `ok-mod-sdk`,
//! which wraps these; the host (`ok-mod-host`) loads mods through [`OkModRef`].
//!
//! Compatibility rules (§7.4):
//! - Prefix structs ([`OkMod`], [`HostApi`]) only ever grow at the end. A field added after the
//!   current `last_prefix_field` is read as `Option` by the other side, so an old host or an old mod
//!   sees "missing" instead of crashing.
//! - Enums that will gain variants are `NonExhaustive` (`*_NE` aliases): an old mod handed a newer
//!   variant gets an `Err` from `as_enum()` and ignores it.
//! - [`ABI_VERSION`] is what abi_stable compares when loading. It stays `0.<minor>.0`: in 0.x a
//!   minor bump means a breaking change, additions keep the same string and rely on the layout
//!   checker (which accepts appended prefix fields and new non-exhaustive variants).

// abi_stable 0.11 derives emit impls the newer non_local_definitions lint flags.
#![allow(non_local_definitions)]

pub use abi_stable;

use abi_stable::{
    declare_root_module_statics,
    library::RootModule,
    sabi_trait,
    sabi_types::VersionStrings,
    std_types::{RBox, ROption, RResult, RStr, RString, RVec},
    StableAbi,
};

/// Crate version of this API (what `mod.toml`'s `api = "0.1"` is checked against).
pub const API_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The version abi_stable checks when a mod DLL is loaded. See the crate docs for why it is
/// separate from [`API_VERSION`].
pub const ABI_VERSION: &str = "0.1.0";

/// Identifies one loaded mod in calls back into the host.
#[repr(transparent)]
#[derive(StableAbi, Copy, Clone, Debug, PartialEq, Eq, Hash)]
pub struct ModHandle(pub u64);

#[repr(u8)]
#[derive(StableAbi, Copy, Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum LogLevel {
    Error = 1,
    Warn = 2,
    Info = 3,
    Verbose = 4,
}

/// Why a call into a mod failed. A `u8` with named constants rather than an enum so new kinds do
/// not change the layout.
#[repr(transparent)]
#[derive(StableAbi, Copy, Clone, Debug, PartialEq, Eq)]
pub struct ModErrorKind(pub u8);

impl ModErrorKind {
    /// The mod reported an error; it stays enabled.
    pub const ERROR: Self = Self(0);
    /// The mod panicked; the SDK caught it. The host disables the mod.
    pub const PANIC: Self = Self(1);
    /// The mod needs a host function this host does not have.
    pub const HOST_TOO_OLD: Self = Self(2);
    /// The mod was already disabled after an earlier panic and refuses further calls.
    pub const POISONED: Self = Self(3);
}

#[repr(C)]
#[derive(StableAbi, Clone, Debug, PartialEq)]
pub struct ModError {
    pub kind: ModErrorKind,
    pub message: RString,
}

impl ModError {
    pub fn new(kind: ModErrorKind, message: impl Into<RString>) -> Self {
        Self { kind, message: message.into() }
    }
    pub fn is_fault(&self) -> bool {
        self.kind == ModErrorKind::PANIC || self.kind == ModErrorKind::POISONED
    }
}

/// Facts about how the mod DLL was built, reported by the SDK.
#[repr(C)]
#[derive(StableAbi, Copy, Clone, Debug)]
pub struct BuildInfo {
    pub sdk_version: RStr<'static>,
    /// `ok-mod-api` version the mod was compiled against.
    pub api_version: RStr<'static>,
    /// `rustc --version` of the compiler that built the mod.
    pub rustc_version: RStr<'static>,
    /// `false` when built with `panic = "abort"`: the host refuses such mods, a panic would abort
    /// the game.
    pub panic_unwind: bool,
}

// ---------------------------------------------------------------------------------------------
// Values, declarations, events, replies
// ---------------------------------------------------------------------------------------------

/// A config value (BepInEx `ConfigEntry` counterpart). Stored by the host in
/// `UserData/config/mods/<id>.toml`.
#[repr(u8)]
#[derive(StableAbi, Debug, Clone, PartialEq)]
#[sabi(kind(WithNonExhaustive(size = [usize; 8], traits(Debug, Clone, PartialEq))))]
#[non_exhaustive]
pub enum ConfigValue {
    Bool(bool),
    Int(i64),
    Float(f64),
    Text(RString),
    /// Key chord in Unreal key names joined by `+`, e.g. `"LeftControl+K"`.
    Hotkey(RString),
}


#[repr(C)]
#[derive(StableAbi, Debug, Clone, PartialEq)]
pub struct ConfigDecl {
    /// `[a-z0-9_]+`, unique within the mod.
    pub key: RString,
    pub default: ConfigValue_NE,
    /// Inclusive range for `Int`/`Float`.
    pub min: ROption<f64>,
    pub max: ROption<f64>,
    /// Semantic text id, must start with `mod.<id>.` (§6.9).
    pub description_id: RString,
}

#[repr(C)]
#[derive(StableAbi, Debug, Clone, PartialEq)]
pub struct CommandDecl {
    /// Registered as console command `mod.<id>.<name>` and reachable through `mod_call`.
    pub name: RString,
    pub description_id: RString,
}

/// Something a mod declares in `register` (§6.1); `register` is the only time a mod can declare.
#[repr(u8)]
#[derive(StableAbi, Debug, Clone, PartialEq)]
#[sabi(kind(WithNonExhaustive(size = [usize; 32], traits(Debug, Clone, PartialEq))))]
#[non_exhaustive]
pub enum Declaration {
    Config(ConfigDecl),
    Command(CommandDecl),
    /// Event name to receive (see [`Event::name`]). Hooks nobody subscribed to are never called.
    Subscribe(RString),
}


#[repr(C)]
#[derive(StableAbi, Debug, Clone, Default, PartialEq)]
pub struct Registration {
    pub declarations: RVec<Declaration_NE>,
}

/// Events the host sends to subscribed mods. `Enabled` and `Command` are always delivered.
#[repr(u8)]
#[derive(StableAbi, Debug, Clone, PartialEq)]
#[sabi(kind(WithNonExhaustive(size = [usize; 16], traits(Debug, Clone, PartialEq))))]
#[non_exhaustive]
pub enum Event {
    /// After every mod registered; the mod may start working.
    Enabled,
    /// A game mode started: `reader`, `studio`, `pair`, `street`.
    ModeEnter { mode: RString },
    ModeExit { mode: RString },
    /// Console command `mod.<id>.<name> <args>` or control channel `mod_call`.
    Command { name: RString, args: RString },
    /// The player changed one of this mod's config values.
    ConfigChanged { key: RString },
}

impl Event {
    /// Subscription name of the event.
    pub fn name(&self) -> &'static str {
        match self {
            Event::Enabled => "enabled",
            Event::ModeEnter { .. } => "mode_enter",
            Event::ModeExit { .. } => "mode_exit",
            Event::Command { .. } => "command",
            Event::ConfigChanged { .. } => "config_changed",
        }
    }
}


#[repr(u8)]
#[derive(StableAbi, Debug, Clone, PartialEq)]
#[sabi(kind(WithNonExhaustive(size = [usize; 8], traits(Debug, Clone, PartialEq))))]
#[non_exhaustive]
pub enum Reply {
    None,
    /// Human-readable text (console output).
    Text(RString),
    /// JSON answer (control channel).
    Json(RString),
}


// ---------------------------------------------------------------------------------------------
// Host -> mod: what the host offers
// ---------------------------------------------------------------------------------------------

/// Host functions a mod may call (§7.1). Only grows at the end; fields after the
/// `last_prefix_field` come back as `Option` to the mod (`None` = host too old).
#[repr(C)]
#[derive(StableAbi)]
#[sabi(kind(Prefix(prefix_ref = HostApiRef)))]
pub struct HostApi {
    /// `ok-mod-host` crate version.
    pub host_version: RStr<'static>,
    pub log: extern "C" fn(ModHandle, LogLevel, RStr<'_>),
    /// Current value of one of the mod's declared config entries.
    pub config_get: extern "C" fn(ModHandle, RStr<'_>) -> ROption<ConfigValue_NE>,
    /// Sets and persists a declared config entry (type and range are checked).
    #[sabi(last_prefix_field)]
    pub config_set: extern "C" fn(ModHandle, RStr<'_>, ConfigValue_NE) -> RResult<(), ModError>,
}

// ---------------------------------------------------------------------------------------------
// Mod -> host: the mod's root module and instance
// ---------------------------------------------------------------------------------------------

/// One loaded mod. Created by [`OkMod::create`], called only from the thread the host chose.
#[sabi_trait]
pub trait ModInstance: Send {
    /// Declare config entries, commands and subscriptions.
    fn register(&mut self) -> RResult<Registration, ModError>;

    fn on_event(&mut self, event: &Event_NE) -> RResult<Reply_NE, ModError>;

    /// Last call; the DLL stays loaded (abi_stable never unloads, §7.5).
    #[sabi(last_prefix_field)]
    fn shutdown(&mut self);
}

pub type ModInstanceBox = ModInstance_TO<'static, RBox<()>>;

/// The root module every mod DLL exports (the SDK's `ok_mod!` writes it).
#[repr(C)]
#[derive(StableAbi)]
#[sabi(kind(Prefix(prefix_ref = OkModRef)))]
pub struct OkMod {
    pub build_info: extern "C" fn() -> BuildInfo,
    /// The `mod.toml` compiled into the DLL; the host compares it with the file next to the DLL.
    pub manifest: extern "C" fn() -> RStr<'static>,
    #[sabi(last_prefix_field)]
    pub create: extern "C" fn(HostApiRef, ModHandle) -> RResult<ModInstanceBox, ModError>,
}

impl RootModule for OkModRef {
    declare_root_module_statics! {OkModRef}
    const BASE_NAME: &'static str = "ok_mod";
    const NAME: &'static str = "ok_mod";
    const VERSION_STRINGS: VersionStrings = VersionStrings::new(ABI_VERSION);
}
