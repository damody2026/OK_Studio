//! Test fixture for the material hooks (Docs/OK_MOD_S9_MATERIALS.md):
//! - `material.post_texture`: multiplies the texture of the clothes slot named by config `tint_slot` (default
//!   `clothes_top`, a part role) by `tint` (default a green "0.4,1,0.4"), in place;
//! - `material.resolve_shader`: parts whose name contains config `glass_part` (default `socks`) draw with the mod
//!   material `material` (default `org.openkoikatsu.glass-shader/smoky`).
//! Not for players (Tools/ok-mod/obsolete.toml).

use ok_mod_sdk::prelude::*;
use serde::Deserialize;

struct Hooks {
    host: Host,
}

#[derive(Deserialize)]
struct PostTexture {
    slot: String,
    #[serde(default)]
    query: bool,
    #[serde(default)]
    rgba: usize,
    #[serde(default)]
    len: usize,
}

#[derive(Deserialize)]
struct ResolveShader {
    part: String,
}

impl Hooks {
    fn text(&self, key: &str) -> String {
        self.host.config_text(key).unwrap_or_default()
    }
}

impl Mod for Hooks {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Hooks { host })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_text("tint_slot", "clothes_top", "mod.org.openkoikatsu.test.material-hooks.config.tint_slot")
            .config_text("tint", "0.4,1,0.4", "mod.org.openkoikatsu.test.material-hooks.config.tint")
            .config_text("glass_part", "socks", "mod.org.openkoikatsu.test.material-hooks.config.glass_part")
            .config_text("material", "org.openkoikatsu.glass-shader/smoky", "mod.org.openkoikatsu.test.material-hooks.config.material")
            .subscribe("material.post_texture")
            .subscribe("material.resolve_shader");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Hook { name, payload } if name.as_str() == "material.post_texture" => {
                let p: PostTexture = serde_json::from_str(payload.as_str()).map_err(|e| e.to_string())?;
                if p.slot != self.text("tint_slot") {
                    return Ok(Reply::None);
                }
                // Offered without pixels first: only the slot it tints.
                if p.query {
                    return Ok(Reply::Json(r#"{"want":true}"#.into()));
                }
                if p.rgba == 0 {
                    return Ok(Reply::None);
                }
                let tint: Vec<f32> = self.text("tint").split(',').filter_map(|s| s.trim().parse().ok()).collect();
                if tint.len() < 3 {
                    return Err("tint needs r,g,b".into());
                }
                // SAFETY: the host hands over `len` writable bytes for the duration of this call (mod_forward.rs).
                let rgba = unsafe { std::slice::from_raw_parts_mut(p.rgba as *mut u8, p.len) };
                for px in rgba.chunks_exact_mut(4) {
                    for c in 0..3 {
                        px[c] = (px[c] as f32 * tint[c]).clamp(0.0, 255.0) as u8;
                    }
                }
                self.host.info(format!("tinted {} ({} bytes)", p.slot, p.len));
                Ok(Reply::Json(r#"{"changed":true}"#.into()))
            }
            Event::Hook { name, payload } if name.as_str() == "material.resolve_shader" => {
                let p: ResolveShader = serde_json::from_str(payload.as_str()).map_err(|e| e.to_string())?;
                let word = self.text("glass_part");
                if word.is_empty() || !p.part.to_lowercase().contains(&word.to_lowercase()) {
                    return Ok(Reply::None);
                }
                Ok(Reply::Json(serde_json::json!({"material": self.text("material")}).to_string().into()))
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(Hooks);
