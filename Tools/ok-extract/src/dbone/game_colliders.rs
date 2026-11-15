//! KKS_Colliders 1.3: config/extended-card precedence and generated body colliders.
#[allow(unused_imports)] use crate::gamefs::GamePath as _;
use super::{BodyCollider, Skeleton};
use std::path::Path;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct CardOverrides {
    pub breast: Option<bool>, pub floor: Option<bool>, pub skirt: Option<bool>,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub struct Flags { pub installed: bool, pub breast: bool, pub floor: bool, pub skirt: bool }
#[derive(Clone, Copy, Debug, serde::Serialize, serde::Deserialize)]
pub struct Settings { installed: bool, global: Flags, studio_default: u8 }
impl Default for Settings {
    fn default() -> Self {Self {installed:false,global:Flags::default(),studio_default:0}}
}
const PLUGINS: [&str; 4] = [
    "BepInEx/plugins/KKS_Plugins/KKS_Colliders.dll",
    "BepInEx/plugins/KKS_Colliders.dll",
    "BepInEx/plugins/KK_Plugins/KK_Colliders.dll",
    "BepInEx/plugins/KK_Colliders.dll",
];
const CONFIG: &str = "BepInEx/config/com.deathweasel.bepinex.colliders.cfg";
impl Settings {
    fn from_installation(root: &Path) -> Self {
        let installed = PLUGINS.iter().any(|p| root.join(p).ok_is_file());
        let text = crate::gamefs::read_to_string(root.join(CONFIG)).unwrap_or_default();
        Self::parse(installed, &text)
    }
    /// A game installation decides by its plugin and configuration. An OK card opened without one (the library is
    /// no installation, and a card pack records no plugin) takes the installation given with the card, else the
    /// project's `Config/KKS_Colliders.cfg` (`OK_COLLIDERS_CONFIG` overrides it), as UncensorSelector does: without
    /// it a skirt had no thigh colliders and the legs went through it.
    pub fn load(root: &Path) -> Self {
        if root.join("BepInEx").is_dir() { return Self::from_installation(root); }
        if let Some(game) = crate::gamefs::fallback_installation() { return Self::from_installation(&game); }
        match project_config() {
            Some(text) => Self::parse(true, &text),
            None => Self::from_installation(root),
        }
    }
    /// What an open reads for these settings without an installation, for the open cache (oklib).
    pub fn library_identity() -> String {
        let root = crate::oklib::active_dir().unwrap_or_default();
        format!("colliders:{:?}", Self::load(&root))
    }
    fn parse(installed: bool, text: &str) -> Self {
        let mut settings = Self { installed, global: Flags { installed, breast: true, floor: true, skirt: true }, studio_default: 2 };
        let mut section = false;
        for line in text.lines().map(str::trim) {
            if line.starts_with('#') || line.is_empty() { continue; }
            if line.starts_with('[') { section = line == "[Config]"; continue; }
            if !section { continue; }
            let Some((key, value)) = line.split_once('=') else { continue; };
            let value = value.trim();
            match key.trim() {
                "Breast Colliders" => if let Ok(v) = value.parse() { settings.global.breast = v; },
                "Floor Collider" => if let Ok(v) = value.parse() { settings.global.floor = v; },
                "Skirt Colliders" => if let Ok(v) = value.parse() { settings.global.skirt = v; },
                "Default Studio Settings" => settings.studio_default = match value { "Config" => 0, "On" => 1, _ => 2 },
                _ => {},
            }
        }
        settings
    }
    pub fn resolve(self, studio: bool, card: CardOverrides) -> Flags {
        if !self.installed { return Flags::default(); }
        if !studio { return self.global; }
        let mut flags = match self.studio_default {
            0 => self.global,
            1 => Flags { installed: true, breast: true, floor: true, skirt: true },
            _ => Flags { installed: true, ..Flags::default() },
        };
        if let Some(v) = card.breast { flags.breast = v; }
        if let Some(v) = card.floor { flags.floor = v; }
        if let Some(v) = card.skirt { flags.skirt = v; }
        flags
    }
}

/// The project's KKS_Colliders configuration: `OK_COLLIDERS_CONFIG`, else `<project>/Config/KKS_Colliders.cfg`
/// found from the library (<project>/Content/IndependentResources/base_v1, also through a stage's junction).
fn project_config() -> Option<String> {
    let mut candidates: Vec<std::path::PathBuf> = std::env::var_os("OK_COLLIDERS_CONFIG").map(Into::into).into_iter().collect();
    if let Some(dir) = crate::oklib::active_dir() {
        for lib in [Some(dir.clone()), std::fs::canonicalize(&dir).ok()].into_iter().flatten() {
            if let Some(project) = lib.parent().and_then(Path::parent).and_then(Path::parent) {
                candidates.push(project.join("Config").join("KKS_Colliders.cfg"));
            }
        }
    }
    candidates.into_iter().find_map(|p| std::fs::read_to_string(p).ok())
}

// ColliderController.AddCollider parents an identity child to each named bone.
// Binding the collider directly to that bone preserves the exact world matrix.
const ARMS: [(&str, f32, f32, [f32; 3]); 6] = [
    ("cf_s_hand_L", 0.02, 0.075, [-0.03, -0.005, 0.0]),
    ("cf_s_hand_R", 0.02, 0.075, [0.03, -0.005, 0.0]),
    ("cf_s_forearm02_L", 0.025, 0.25, [-0.03, 0.0, 0.0]),
    ("cf_s_forearm02_R", 0.025, 0.25, [0.03, 0.0, 0.0]),
    ("cf_s_arm02_L", 0.025, 0.25, [0.0; 3]),
    ("cf_s_arm02_R", 0.025, 0.25, [0.0; 3]),
];
const LEGS: [(&str, f32, f32, [f32; 3]); 6] = [
    ("cf_s_thigh01_L", 0.095, 0.32, [0.05, -0.1, -0.015]),
    ("cf_s_thigh01_R", 0.095, 0.32, [-0.05, -0.1, -0.015]),
    ("cf_s_thigh01_L", 0.095, 0.32, [0.01, -0.125, -0.015]),
    ("cf_s_thigh01_R", 0.095, 0.32, [-0.01, -0.125, -0.015]),
    ("cf_s_thigh02_L", 0.083, 0.35, [-0.0065, 0.0, -0.012]),
    ("cf_s_thigh02_R", 0.083, 0.35, [0.0065, 0.0, -0.012]),
];
pub(super) fn ordinary_colliders(skel: &Skeleton, flags: Flags, skirt: bool) -> Vec<BodyCollider> {
    let mut colliders = Vec::new();
    if !flags.installed { return colliders; }
    let named = |name: &str| skel.tfs.iter().find(|(_, tf)| tf.name == name).map(|(id, _)| *id);
    if flags.floor {
        if let Some(transform) = named("cf_j_root") {
            colliders.push(BodyCollider { transform, center: [0.0, -100.01, 0.0], radius: 100.0, height: 0.0, direction: 0, inside: false });
        }
    }
    if skirt && flags.skirt {
        for (name, radius, height, center) in LEGS {
            if let Some(transform) = named(name) {
                colliders.push(BodyCollider { transform, center, radius, height, direction: 1, inside: false });
            }
        }
    }
    colliders
}
pub(super) fn breast_colliders(skel: &Skeleton, flags: Flags) -> Vec<BodyCollider> {
    if !flags.installed || !flags.breast { return Vec::new(); }
    let mut colliders = Vec::new();
    let named = |name: &str| skel.tfs.iter().find(|(_, tf)| tf.name == name).map(|(id, _)| *id);
    if flags.floor {
        if let Some(transform) = named("cf_j_root") {
            colliders.push(BodyCollider { transform, center: [0.0, -100.01, 0.0], radius: 100.0, height: 0.0, direction: 0, inside: false });
        }
    }
    for (name, radius, height, center) in ARMS {
        if let Some(transform) = named(name) {
            colliders.push(BodyCollider { transform, center, radius, height, direction: 0, inside: false });
        }
    }
    colliders
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn plugin_config_and_studio_card_precedence() {
        let text = "[Config]\nBreast Colliders = false\nFloor Collider = true\nSkirt Colliders = false\nDefault Studio Settings = Off\n[Unrelated]\nFloor Collider = false\n";
        let card = CardOverrides { breast: Some(true), floor: Some(false), skirt: None };
        let settings = Settings::parse(true, text);
        assert_eq!(settings.resolve(false, card), Flags { installed: true, breast: false, floor: true, skirt: false });
        assert_eq!(settings.resolve(true, card), Flags { installed: true, breast: true, floor: false, skirt: false });
        assert_eq!(Settings::parse(false, text).resolve(true, card), Flags::default());
        assert!(Settings::parse(true, "[Config]\nDefault Studio Settings = On").resolve(true, CardOverrides::default()).skirt);
        assert!(Settings::parse(true, "[Config]\nDefault Studio Settings = Config").resolve(true, CardOverrides::default()).breast);
    }
}
