//! Test fixture: claims to be an `ok_mod` root module of ABI 0.1.0, but its `OkMod` has a different
//! layout (`create` has the wrong signature). abi_stable's layout check must refuse it before any
//! of its functions is called.
#![allow(non_local_definitions)]

use abi_stable::{
    declare_root_module_statics, export_root_module, library::RootModule, prefix_type::PrefixTypeTrait,
    sabi_types::VersionStrings, std_types::RStr, StableAbi,
};

#[repr(C)]
#[derive(StableAbi, Copy, Clone)]
pub struct BuildInfo {
    pub sdk_version: RStr<'static>,
}

#[repr(C)]
#[derive(StableAbi)]
#[sabi(kind(Prefix(prefix_ref = OkModRef)))]
pub struct OkMod {
    pub build_info: extern "C" fn() -> BuildInfo,
    pub manifest: extern "C" fn() -> RStr<'static>,
    #[sabi(last_prefix_field)]
    pub create: extern "C" fn(u32) -> u32,
}

impl RootModule for OkModRef {
    declare_root_module_statics! {OkModRef}
    const BASE_NAME: &'static str = "ok_mod";
    const NAME: &'static str = "ok_mod";
    const VERSION_STRINGS: VersionStrings = VersionStrings::new("0.1.0");
}

extern "C" fn build_info() -> BuildInfo {
    BuildInfo { sdk_version: RStr::from_str("bad") }
}
extern "C" fn manifest() -> RStr<'static> {
    RStr::from_str(include_str!("../mod.toml"))
}
extern "C" fn create(x: u32) -> u32 {
    x
}

#[export_root_module]
pub fn get_library() -> OkModRef {
    OkMod { build_info, manifest, create }.leak_into_prefix()
}
