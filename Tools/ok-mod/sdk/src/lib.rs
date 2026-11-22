//! `ok-mod-sdk`: what a mod author uses (Docs/OK_MOD_FRAMEWORK_PLAN.md §4, §7).
//!
//! ```ignore
//! use ok_mod_sdk::prelude::*;
//!
//! struct Hello { host: Host }
//!
//! impl Mod for Hello {
//!     fn create(host: Host) -> ModResult<Self> { Ok(Hello { host }) }
//!     fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
//!         reg.command("ping", "mod.org.example.hello.cmd.ping");
//!         Ok(())
//!     }
//!     fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
//!         Ok(match event {
//!             Event::Command { name, .. } if name == "ping" => Reply::Text("pong".into()),
//!             _ => Reply::None,
//!         })
//!     }
//! }
//!
//! ok_mod!(Hello);   // mod.toml next to Cargo.toml is compiled in
//! ```
//!
//! Every call from the host into the mod goes through [`ok_mod!`]'s adapter, which catches panics
//! and turns them into a `PANIC` error; the host then disables the mod and the game keeps running.
//! The mod crate must build with `panic = "unwind"` (the host refuses `abort` builds).

pub use ok_mod_api as api;
pub use ok_mod_api::abi_stable;

use std::cell::RefCell;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Once;

use abi_stable::{
    prefix_type::PrefixTypeTrait,
    sabi_trait::TD_Opaque,
    std_types::{RNone, RResult, RSome, RStr, RVec},
};
use api::{
    BuildInfo, CommandDecl, ConfigDecl, ConfigValue_NE, Declaration, Declaration_NE, Event_NE,
    HostApiRef, ModError, ModErrorKind, ModHandle, ModInstance, ModInstanceBox, ModInstance_TO,
    OkMod, OkModRef, Registration, Reply_NE,
};

pub use api::{ConfigValue, Event, LogLevel, Reply};

pub type ModResult<T> = Result<T, String>;

pub mod prelude {
    pub use crate::{ok_mod, ConfigValue, Event, Host, LogLevel, Mod, ModResult, Registrar, Reply};
}

pub const SDK_VERSION: &str = env!("CARGO_PKG_VERSION");
/// `rustc --version` of the compiler building this SDK, which is the one building the mod.
pub const RUSTC_VERSION: &str = env!("OK_MOD_SDK_RUSTC");

/// Name abi_stable looks up in a mod DLL (`abi_stable::library::ROOT_MODULE_LOADER_NAME`); the
/// `ok_mod!` macro exports its header under this name. Checked by a test.
pub const ROOT_MODULE_LOADER_NAME: &str = "_1as_0lib_1header_0root_bmodule_bloader";

/// What a mod implements. All methods are called on the thread the host chose (the game thread
/// unless the hook says `worker`), never two at once.
pub trait Mod: Send + Sized + 'static {
    fn create(host: Host) -> ModResult<Self>;

    /// Declare config entries, commands and the events to receive. The only chance to declare.
    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        let _ = reg;
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let _ = event;
        Ok(Reply::None)
    }

    fn shutdown(&mut self) {}
}

/// The host as seen from a mod: logging and the mod's own config values.
#[derive(Clone)]
pub struct Host {
    api: HostApiRef,
    handle: ModHandle,
}

impl Host {
    pub fn host_version(&self) -> &'static str {
        self.api.host_version().as_str()
    }

    pub fn log(&self, level: LogLevel, message: impl AsRef<str>) {
        (self.api.log())(self.handle, level, RStr::from_str(message.as_ref()));
    }
    pub fn error(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Error, message)
    }
    pub fn warn(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Warn, message)
    }
    pub fn info(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Info, message)
    }
    pub fn verbose(&self, message: impl AsRef<str>) {
        self.log(LogLevel::Verbose, message)
    }

    /// Current value of a declared config entry.
    pub fn config(&self, key: &str) -> Option<ConfigValue> {
        match (self.api.config_get())(self.handle, RStr::from_str(key)) {
            RSome(v) => v.as_enum().ok().cloned(),
            RNone => None,
        }
    }
    pub fn config_bool(&self, key: &str) -> Option<bool> {
        match self.config(key)? {
            ConfigValue::Bool(b) => Some(b),
            _ => None,
        }
    }
    pub fn config_int(&self, key: &str) -> Option<i64> {
        match self.config(key)? {
            ConfigValue::Int(i) => Some(i),
            _ => None,
        }
    }
    pub fn config_float(&self, key: &str) -> Option<f64> {
        match self.config(key)? {
            ConfigValue::Float(f) => Some(f),
            ConfigValue::Int(i) => Some(i as f64),
            _ => None,
        }
    }
    pub fn config_text(&self, key: &str) -> Option<String> {
        match self.config(key)? {
            ConfigValue::Text(s) | ConfigValue::Hotkey(s) => Some(s.into_string()),
            _ => None,
        }
    }

    /// Sets and persists a declared config entry (the host checks type and range).
    pub fn set_config(&self, key: &str, value: ConfigValue) -> ModResult<()> {
        (self.api.config_set())(self.handle, RStr::from_str(key), ConfigValue_NE::new(value))
            .into_result()
            .map_err(|e| e.message.into_string())
    }
}

/// Collects what a mod declares in [`Mod::register`].
#[derive(Default)]
pub struct Registrar {
    declarations: Vec<Declaration>,
}

impl Registrar {
    fn config(&mut self, key: &str, default: ConfigValue, range: Option<(f64, f64)>, description_id: &str) -> &mut Self {
        self.declarations.push(Declaration::Config(ConfigDecl {
            key: key.into(),
            default: ConfigValue_NE::new(default),
            min: range.map(|r| r.0).into(),
            max: range.map(|r| r.1).into(),
            description_id: description_id.into(),
        }));
        self
    }
    pub fn config_bool(&mut self, key: &str, default: bool, description_id: &str) -> &mut Self {
        self.config(key, ConfigValue::Bool(default), None, description_id)
    }
    pub fn config_int(&mut self, key: &str, default: i64, min: i64, max: i64, description_id: &str) -> &mut Self {
        self.config(key, ConfigValue::Int(default), Some((min as f64, max as f64)), description_id)
    }
    pub fn config_float(&mut self, key: &str, default: f64, min: f64, max: f64, description_id: &str) -> &mut Self {
        self.config(key, ConfigValue::Float(default), Some((min, max)), description_id)
    }
    pub fn config_text(&mut self, key: &str, default: &str, description_id: &str) -> &mut Self {
        self.config(key, ConfigValue::Text(default.into()), None, description_id)
    }
    pub fn config_hotkey(&mut self, key: &str, default: &str, description_id: &str) -> &mut Self {
        self.config(key, ConfigValue::Hotkey(default.into()), None, description_id)
    }
    /// Console command `mod.<id>.<name>`, also reachable through the control channel's `mod_call`.
    pub fn command(&mut self, name: &str, description_id: &str) -> &mut Self {
        self.declarations.push(Declaration::Command(CommandDecl {
            name: name.into(),
            description_id: description_id.into(),
        }));
        self
    }
    /// Receive an event (`mode_enter`, `mode_exit`, `config_changed`; `enabled` and `command`
    /// always arrive).
    pub fn subscribe(&mut self, event: &str) -> &mut Self {
        self.declarations.push(Declaration::Subscribe(event.into()));
        self
    }

    fn finish(self) -> Registration {
        Registration {
            declarations: self.declarations.into_iter().map(Declaration_NE::new).collect::<RVec<_>>(),
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Panic isolation
// ---------------------------------------------------------------------------------------------

thread_local! {
    static LAST_PANIC: RefCell<Option<String>> = const { RefCell::new(None) };
}

static PANIC_HOOK: Once = Once::new();

/// Each mod DLL links its own std, so this hook only sees this mod's panics. It records the message
/// and location instead of printing to stderr (nobody reads Unreal's stderr).
fn install_panic_hook() {
    PANIC_HOOK.call_once(|| {
        std::panic::set_hook(Box::new(|info| {
            let text = info.to_string();
            LAST_PANIC.with(|p| *p.borrow_mut() = Some(text));
        }));
    });
}

fn panic_text(payload: Box<dyn std::any::Any + Send>) -> String {
    if let Some(text) = LAST_PANIC.with(|p| p.borrow_mut().take()) {
        return text;
    }
    if let Some(s) = payload.downcast_ref::<&str>() {
        (*s).to_string()
    } else if let Some(s) = payload.downcast_ref::<String>() {
        s.clone()
    } else {
        "panic with a non-string payload".into()
    }
}

fn guard<T>(poisoned: &mut bool, what: &str, f: impl FnOnce() -> ModResult<T>) -> RResult<T, ModError> {
    if *poisoned {
        return RResult::RErr(ModError::new(ModErrorKind::POISONED, format!("{what}: mod disabled after an earlier panic")));
    }
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => RResult::ROk(v),
        Ok(Err(message)) => RResult::RErr(ModError::new(ModErrorKind::ERROR, message)),
        Err(payload) => {
            *poisoned = true;
            RResult::RErr(ModError::new(ModErrorKind::PANIC, format!("{what} panicked: {}", panic_text(payload))))
        }
    }
}

struct Adapter<M: Mod> {
    inner: M,
    poisoned: bool,
}

impl<M: Mod> ModInstance for Adapter<M> {
    fn register(&mut self) -> RResult<Registration, ModError> {
        let inner = &mut self.inner;
        guard(&mut self.poisoned, "register", || {
            let mut reg = Registrar::default();
            inner.register(&mut reg)?;
            Ok(reg.finish())
        })
    }

    fn on_event(&mut self, event: &Event_NE) -> RResult<Reply_NE, ModError> {
        // An event newer than this mod's API: not for us.
        let Ok(event) = event.as_enum() else {
            return RResult::ROk(Reply_NE::new(Reply::None));
        };
        let inner = &mut self.inner;
        guard(&mut self.poisoned, event.name(), || inner.on_event(event).map(Reply_NE::new))
    }

    fn shutdown(&mut self) {
        if !self.poisoned {
            let inner = &mut self.inner;
            let _ = guard(&mut self.poisoned, "shutdown", || {
                inner.shutdown();
                Ok(())
            });
        }
    }
}

#[doc(hidden)]
pub extern "C" fn __build_info() -> BuildInfo {
    BuildInfo {
        sdk_version: RStr::from_str(SDK_VERSION),
        api_version: RStr::from_str(api::API_VERSION),
        rustc_version: RStr::from_str(RUSTC_VERSION),
        panic_unwind: cfg!(panic = "unwind"),
    }
}

#[doc(hidden)]
pub extern "C" fn __create<M: Mod>(api: HostApiRef, handle: ModHandle) -> RResult<ModInstanceBox, ModError> {
    install_panic_hook();
    let mut poisoned = false;
    let made = guard(&mut poisoned, "create", || M::create(Host { api, handle }));
    made.map(|inner| ModInstance_TO::from_value(Adapter { inner, poisoned: false }, TD_Opaque))
}

#[doc(hidden)]
pub fn __root_module<M: Mod>(manifest: extern "C" fn() -> RStr<'static>) -> OkModRef {
    OkMod { build_info: __build_info, manifest, create: __create::<M> }.leak_into_prefix()
}

/// Exports the mod's root module. Put it once at the crate root; `mod.toml` must sit next to the
/// crate's `Cargo.toml` (it is compiled in and compared with the installed copy).
#[macro_export]
macro_rules! ok_mod {
    ($ty:ty) => {
        #[doc(hidden)]
        extern "C" fn __ok_mod_manifest() -> $crate::abi_stable::std_types::RStr<'static> {
            $crate::abi_stable::std_types::RStr::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"), "/mod.toml")))
        }

        #[doc(hidden)]
        fn __ok_mod_root() -> $crate::api::OkModRef {
            $crate::__root_module::<$ty>(__ok_mod_manifest)
        }

        // Same as abi_stable's #[export_root_module], spelled out so mod crates do not need
        // abi_stable as a direct dependency.
        #[doc(hidden)]
        #[export_name = "_1as_0lib_1header_0root_bmodule_bloader"]
        pub static __OK_MOD_LIB_HEADER: $crate::abi_stable::library::LibHeader = {
            extern "C" fn erased() -> $crate::abi_stable::library::RootModuleResult {
                $crate::abi_stable::library::__call_root_module_loader(__ok_mod_root)
            }
            unsafe {
                $crate::abi_stable::library::LibHeader::from_constructor::<$crate::api::OkModRef>(
                    erased,
                    $crate::abi_stable::library::CheckTypeLayout::Yes,
                )
            }
        };
    };
}

#[cfg(test)]
mod tests {
    #[test]
    fn loader_name_matches_abi_stable() {
        assert_eq!(super::ROOT_MODULE_LOADER_NAME, ok_mod_api::abi_stable::library::ROOT_MODULE_LOADER_NAME);
    }
}
