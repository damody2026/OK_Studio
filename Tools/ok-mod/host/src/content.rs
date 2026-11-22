//! What an enabled mod brings besides code (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.11): its cooked material pak
//! (B layer) and its material declarations `materials/*.toml` (A layer, shader families). The host only reads and
//! checks the files; Unreal mounts the pak and builds the materials.
//!
//! ```toml
//! [[material]]
//! name = "glass"                                   # [a-z0-9_]+; full id "<mod id>/glass"
//! asset = "/org_openkoikatsu_glass_shader/M_OKGlass.M_OKGlass"   # B layer: in the mod's pak, under its content root
//! parent = "translucent"                           # A layer: a core parent (opaque, masked, translucent, xray);
//!                                                  # with `asset`, the fallback when the pak cannot be used
//! families = ["Shader Forge/main_glass"]           # Unity shader names this material draws (§6.11 shader families)
//! main_texture = "_MainTex"                        # parameter that gets the part's own texture (optional)
//! copy_source_values = true                        # card material values go to same-named parameters (default)
//! [material.scalars]
//! GlassOpacity = 0.35
//! [material.vectors]
//! GlassTint = [0.75, 0.9, 1.0, 1.0]                # linear RGBA
//! [material.textures]
//! _DetailTex = "textures/detail.png"               # a PNG inside the mod folder
//! ```

use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};

use serde::{Deserialize, Serialize};

/// Core parents an A-layer material may name (Content/IndependentResources/PreviewMaterials).
pub const OPEN_PARENTS: &[&str] = &["opaque", "masked", "translucent", "xray"];

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct MaterialFile {
    #[serde(default)]
    material: Vec<MaterialDecl>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(deny_unknown_fields)]
struct MaterialDecl {
    name: String,
    #[serde(default)]
    asset: Option<String>,
    #[serde(default)]
    parent: Option<String>,
    #[serde(default)]
    families: Vec<String>,
    #[serde(default)]
    main_texture: Option<String>,
    #[serde(default = "yes")]
    copy_source_values: bool,
    #[serde(default)]
    scalars: BTreeMap<String, f64>,
    #[serde(default)]
    vectors: BTreeMap<String, Vec<f64>>,
    #[serde(default)]
    textures: BTreeMap<String, String>,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ModMaterial {
    /// `<mod id>/<name>`
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub asset: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent: Option<String>,
    pub families: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub main_texture: Option<String>,
    pub copy_source_values: bool,
    pub scalars: BTreeMap<String, f64>,
    /// Always four components.
    pub vectors: BTreeMap<String, [f64; 4]>,
    /// Absolute paths, checked to be PNG files inside the mod folder.
    pub textures: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ModContent {
    pub id: String,
    pub dir: String,
    /// Package root of the mod's cooked content: `/<content_root>/` (the ModKit plugin name, the id with `.` and `-`
    /// turned into `_`).
    pub content_root: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_build: Option<String>,
    /// `content/*.pak`, absolute.
    pub paks: Vec<String>,
    /// Shader library name the ModKit cook gives the mod (`OKModCook_<content_root>`).
    pub shader_library: String,
    pub materials: Vec<ModMaterial>,
    /// Declarations that were dropped, with why.
    pub problems: Vec<String>,
}

pub fn content_root(id: &str) -> String {
    id.chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' { c } else { '_' }).collect()
}

fn inside(dir: &Path, rel: &str) -> Option<PathBuf> {
    let p = Path::new(rel);
    if p.is_absolute() || p.components().any(|c| !matches!(c, Component::Normal(_))) {
        return None;
    }
    Some(dir.join(p))
}

fn files_with_ext(dir: &Path, ext: &str) -> Vec<PathBuf> {
    let Ok(read) = std::fs::read_dir(dir) else { return Vec::new() };
    let mut out: Vec<PathBuf> = read
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.is_file() && p.extension().is_some_and(|e| e.eq_ignore_ascii_case(ext)))
        .collect();
    out.sort();
    out
}

/// Reads one mod's content declarations. Never fails as a whole: a bad declaration is dropped and listed in
/// `problems`.
pub fn read(id: &str, dir: &Path, content_build: Option<&str>) -> ModContent {
    let root = content_root(id);
    let mut out = ModContent {
        id: id.to_string(),
        dir: dir.display().to_string(),
        content_root: root.clone(),
        content_build: content_build.map(str::to_string),
        paks: files_with_ext(&dir.join("content"), "pak").iter().map(|p| p.display().to_string()).collect(),
        shader_library: format!("OKModCook_{root}"),
        materials: Vec::new(),
        problems: Vec::new(),
    };
    if !out.paks.is_empty() && content_build.is_none() {
        out.problems.push("content/*.pak without content_build in mod.toml: the pak is not used".into());
        out.paks.clear();
    }
    for file in files_with_ext(&dir.join("materials"), "toml") {
        let parsed = std::fs::read_to_string(&file).map_err(|e| e.to_string()).and_then(|t| toml::from_str::<MaterialFile>(&t).map_err(|e| e.to_string()));
        let decls = match parsed {
            Ok(f) => f.material,
            Err(e) => {
                out.problems.push(format!("{}: {e}", file.display()));
                continue;
            }
        };
        for d in decls {
            match check(id, dir, &root, &d) {
                Ok(m) if out.materials.iter().any(|x| x.id == m.id) => out.problems.push(format!("material {} declared twice", m.id)),
                Ok(m) => out.materials.push(m),
                Err(e) => out.problems.push(format!("{}: material {}: {e}", file.display(), d.name)),
            }
        }
    }
    out
}

fn check(id: &str, dir: &Path, root: &str, d: &MaterialDecl) -> Result<ModMaterial, String> {
    if d.name.is_empty() || !d.name.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_') {
        return Err("name must be [a-z0-9_]+".into());
    }
    if d.asset.is_none() && d.parent.is_none() {
        return Err("needs asset (B layer) or parent (A layer)".into());
    }
    if let Some(asset) = &d.asset {
        let prefix = format!("/{root}/");
        if !asset.starts_with(&prefix) || asset.contains("..") || !asset.contains('.') {
            return Err(format!("asset \"{asset}\" must be an object path under {prefix} (e.g. {prefix}M_X.M_X)"));
        }
    }
    if let Some(parent) = &d.parent {
        if !OPEN_PARENTS.contains(&parent.as_str()) {
            return Err(format!("parent \"{parent}\" is not one of {}", OPEN_PARENTS.join(", ")));
        }
    }
    if d.families.iter().any(|f| f.trim().is_empty()) {
        return Err("empty shader family name".into());
    }
    let mut vectors = BTreeMap::new();
    for (k, v) in &d.vectors {
        let a = match v.as_slice() {
            [r, g, b] => [*r, *g, *b, 1.0],
            [r, g, b, a] => [*r, *g, *b, *a],
            _ => return Err(format!("vector {k} needs 3 or 4 numbers")),
        };
        vectors.insert(k.clone(), a);
    }
    if let Some((k, _)) = d.scalars.iter().find(|(_, v)| !v.is_finite()) {
        return Err(format!("scalar {k} is not a number"));
    }
    let mut textures = BTreeMap::new();
    for (k, rel) in &d.textures {
        let path = inside(dir, rel).ok_or_else(|| format!("texture {k}: \"{rel}\" must be a path inside the mod folder"))?;
        if !path.is_file() || !path.extension().is_some_and(|e| e.eq_ignore_ascii_case("png")) {
            return Err(format!("texture {k}: {} is not a PNG file", path.display()));
        }
        textures.insert(k.clone(), path.display().to_string());
    }
    Ok(ModMaterial {
        id: format!("{id}/{}", d.name),
        asset: d.asset.clone(),
        parent: d.parent.clone(),
        families: d.families.clone(),
        main_texture: d.main_texture.clone(),
        copy_source_values: d.copy_source_values,
        scalars: d.scalars.clone(),
        vectors,
        textures,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_and_checks() {
        let dir = std::env::temp_dir().join(format!("ok-mod-content-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("materials")).unwrap();
        std::fs::create_dir_all(dir.join("textures")).unwrap();
        std::fs::create_dir_all(dir.join("content")).unwrap();
        std::fs::write(dir.join("textures/a.png"), b"png").unwrap();
        std::fs::write(dir.join("content/x.pak"), b"pak").unwrap();
        std::fs::write(
            dir.join("materials/m.toml"),
            r#"
[[material]]
name = "glass"
asset = "/a_b/M_G.M_G"
parent = "translucent"
families = ["Shader Forge/main_glass"]
[material.vectors]
Tint = [1, 0, 0]
[material.textures]
_Detail = "textures/a.png"

[[material]]
name = "bad_parent"
parent = "M_Whatever"

[[material]]
name = "escape"
parent = "opaque"
[material.textures]
T = "../outside.png"

[[material]]
name = "foreign"
asset = "/Game/M_Core.M_Core"
"#,
        )
        .unwrap();
        let c = read("a.b", &dir, None);
        assert_eq!(c.content_root, "a_b");
        assert!(c.paks.is_empty(), "no content_build: pak not used");
        assert_eq!(c.materials.len(), 1);
        assert_eq!(c.materials[0].id, "a.b/glass");
        assert_eq!(c.materials[0].vectors["Tint"], [1.0, 0.0, 0.0, 1.0]);
        assert_eq!(c.problems.len(), 4, "{:?}", c.problems);
        let c = read("a.b", &dir, Some("1@5.8.4"));
        assert_eq!(c.paks.len(), 1);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
