//! `glass-shader`: an example content mod (Docs/OK_MOD_FRAMEWORK_PLAN.md §6.11, §14).
//! The work is in its files, not its code: `content/org_openkoikatsu_glass_shader.pak` (a cooked glass material with its
//! own shader library) and `materials/glass.toml` (which Unity shaders it draws, its parameters and its fallback).
//! The DLL only reports what it brings, through the console command `mod.org.openkoikatsu.glass-shader.about`.

use ok_mod_sdk::prelude::*;

struct Glass {
    host: Host,
}

impl Mod for Glass {
    fn create(host: Host) -> ModResult<Self> {
        Ok(Glass { host })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.command("about", "mod.org.openkoikatsu.glass-shader.cmd.about");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Enabled => self.host.info("glass materials: glass (glasses lenses), smoky; mod.material.list shows which layer loaded"),
            Event::Command { name, .. } if name == "about" => {
                return Ok(Reply::Text(
                    "org.openkoikatsu.glass-shader/glass draws Koikano/main_clothes_item_glasses and Shader Forge/toon_glasses_lod0; \
                     org.openkoikatsu.glass-shader/smoky: mod.material.apply org.openkoikatsu.glass-shader/smoky <part>"
                        .into(),
                ))
            }
            Event::Command { name, .. } => return Err(format!("unknown command {name}")),
            _ => {}
        }
        Ok(Reply::None)
    }
}

ok_mod!(Glass);
