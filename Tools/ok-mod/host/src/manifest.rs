//! `mod.toml` (Docs/OK_MOD_FRAMEWORK_PLAN.md §5).

use std::collections::BTreeMap;

use semver::{Version, VersionReq};
use serde::Deserialize;

/// Game modes a mod can target (`targets`, the BepInProcess counterpart).
pub const TARGETS: &[&str] = &["reader", "studio", "pair", "street", "extract"];
pub const CATEGORIES: &[&str] = &["feature", "content", "tool", "fix"];

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Manifest {
    pub id: String,
    pub name: String,
    pub version: Version,
    /// `ok-mod-api` version the mod needs, `"<major>.<minor>"`.
    pub api: String,
    pub dll: String,
    #[serde(default)]
    pub sha256: Option<String>,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub description_id: Option<String>,
    pub targets: Vec<String>,
    #[serde(default)]
    pub ext_data: Vec<String>,
    #[serde(default = "default_category")]
    pub category: String,
    /// Integration version a content pak was cooked for (§6.11).
    #[serde(default)]
    pub content_build: Option<String>,
    #[serde(default)]
    pub dependencies: BTreeMap<String, VersionReq>,
    #[serde(default)]
    pub optional_dependencies: BTreeMap<String, VersionReq>,
    #[serde(default)]
    pub incompatible: BTreeMap<String, VersionReq>,
    #[serde(default)]
    pub load_order: LoadOrder,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LoadOrder {
    #[serde(default)]
    pub after: Vec<String>,
    #[serde(default)]
    pub before: Vec<String>,
}

fn default_category() -> String {
    "feature".into()
}

/// Reverse-domain id: at least two dot-separated segments of `[a-z0-9_-]`, each starting with a
/// letter or digit.
pub fn valid_id(id: &str) -> bool {
    let parts: Vec<&str> = id.split('.').collect();
    parts.len() >= 2
        && parts.iter().all(|p| {
            !p.is_empty()
                && p.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_' || c == '-')
                && p.chars().next().is_some_and(|c| c.is_ascii_alphanumeric())
        })
}

/// `"0.1"` / `"1.2"` → (major, minor).
pub fn parse_api(api: &str) -> Option<(u64, u64)> {
    let mut it = api.trim().split('.');
    let major = it.next()?.parse().ok()?;
    let minor = it.next()?.parse().ok()?;
    if it.next().is_some() {
        return None;
    }
    Some((major, minor))
}

/// Whether a mod written for `wanted` runs on a host implementing `host` (§7.4: in 0.x every minor
/// is breaking; from 1.0 the host may be newer within the same major).
pub fn api_compatible(wanted: (u64, u64), host: (u64, u64)) -> bool {
    if wanted.0 == 0 || host.0 == 0 {
        wanted == host
    } else {
        wanted.0 == host.0 && wanted.1 <= host.1
    }
}

impl Manifest {
    pub fn parse(text: &str) -> Result<Manifest, String> {
        let m: Manifest = toml::from_str(text).map_err(|e| format!("mod.toml: {e}"))?;
        m.validate()?;
        Ok(m)
    }

    fn validate(&self) -> Result<(), String> {
        if !valid_id(&self.id) {
            return Err(format!("mod.toml: id \"{}\" is not a reverse-domain id like com.example.name", self.id));
        }
        if parse_api(&self.api).is_none() {
            return Err(format!("mod.toml: api \"{}\" must look like \"0.1\"", self.api));
        }
        if self.dll.contains(['/', '\\']) || !self.dll.to_ascii_lowercase().ends_with(".dll") {
            return Err(format!("mod.toml: dll \"{}\" must be a .dll file name next to mod.toml", self.dll));
        }
        if self.targets.is_empty() {
            return Err("mod.toml: targets is empty".into());
        }
        if let Some(t) = self.targets.iter().find(|t| !TARGETS.contains(&t.as_str())) {
            return Err(format!("mod.toml: unknown target \"{t}\" (known: {})", TARGETS.join(", ")));
        }
        if !CATEGORIES.contains(&self.category.as_str()) {
            return Err(format!("mod.toml: unknown category \"{}\" (known: {})", self.category, CATEGORIES.join(", ")));
        }
        for id in self
            .dependencies
            .keys()
            .chain(self.optional_dependencies.keys())
            .chain(self.incompatible.keys())
            .chain(self.load_order.after.iter())
            .chain(self.load_order.before.iter())
        {
            if id == &self.id {
                return Err(format!("mod.toml: {id} refers to itself"));
            }
        }
        Ok(())
    }

    /// Prefix every text id and command of this mod must use (§6.9).
    pub fn text_prefix(&self) -> String {
        format!("mod.{}.", self.id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids() {
        assert!(valid_id("org.openkoikatsu.hello"));
        assert!(valid_id("com.example.invisible-body"));
        assert!(!valid_id("hello"));
        assert!(!valid_id("Org.Example"));
        assert!(!valid_id("org..x"));
        assert!(!valid_id("org.-x"));
    }

    #[test]
    fn api_rules() {
        assert!(api_compatible((0, 1), (0, 1)));
        assert!(!api_compatible((0, 1), (0, 2)));
        assert!(!api_compatible((0, 2), (0, 1)));
        assert!(api_compatible((1, 0), (1, 3)));
        assert!(!api_compatible((1, 4), (1, 3)));
        assert!(!api_compatible((1, 0), (2, 0)));
    }

    #[test]
    fn parse_full() {
        let m = Manifest::parse(
            r#"
id = "com.example.invisiblebody"
name = "Invisible Body"
version = "1.2.0"
api = "0.1"
dll = "invisible_body.dll"
targets = ["reader", "studio"]
ext_data = ["character"]
category = "feature"
[dependencies]
"com.example.core" = "^1.0"
[incompatible]
"com.other.bodyhider" = "*"
[load_order]
after = ["com.example.core"]
"#,
        )
        .unwrap();
        assert_eq!(m.version, Version::new(1, 2, 0));
        assert!(m.dependencies["com.example.core"].matches(&Version::new(1, 4, 2)));
        assert!(Manifest::parse("id = \"x\"").is_err());
    }
}
