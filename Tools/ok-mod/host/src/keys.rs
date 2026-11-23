//! Mod hotkeys across every mode (Docs/OK_MOD_HOOKS.md §5): a config entry of the hotkey type (`config_hotkey`) whose
//! mod subscribed to `key.<id>.<entry>` is a key the game watches for it. The game sends the chord pressed
//! (`{"op":"key","chord","mode"}`); every hotkey bound to that chord gets the hook `key.<id>.<entry>` with
//! `{"mode","chord"}`. The player rebinds with `config_set` (settings page, `OKMod.Bind`).
//!
//! A mod subscribes with the short form `key.<entry>` (the SDK's `Registrar::hotkey`); the host makes it
//! `key.<id>.<entry>` when the mod loads, so the hook name always says whose key it is.
//!
//! Chords are Unreal key names joined by `+` (`"LeftControl+K"`, `"F7"`). Left and right modifiers count as the same
//! (`LeftControl`, `RightControl`, `Control`, `Ctrl` all mean Control), letters compare without case, the order of the
//! parts does not matter, and a chord matches only with exactly its modifiers (`K` is not `Control+K`).

use serde_json::{json, Value};

use crate::ModHost;

/// One watched hotkey.
#[derive(Debug, Clone, PartialEq)]
pub struct Hotkey {
    pub id: String,
    pub name: String,
    pub hook: String,
    /// As stored (the player's spelling); empty means unbound.
    pub chord: String,
    pub default: String,
    pub description_id: String,
}

impl Hotkey {
    pub fn json(&self) -> Value {
        json!({"mod": self.id, "name": self.name, "hook": self.hook, "chord": self.chord, "normalized": normalize(&self.chord),
            "default": self.default, "description_id": self.description_id})
    }
}

/// The hook name of hotkey `name` of mod `id`.
pub fn hook_name(id: &str, name: &str) -> String {
    format!("key.{id}.{name}")
}

/// A mod's own subscription `key.<entry>` (no further dot) made `key.<id>.<entry>`; anything else unchanged.
pub fn expand_subscription(id: &str, name: &str) -> String {
    match name.strip_prefix("key.") {
        Some(rest) if !rest.is_empty() && !rest.contains('.') => hook_name(id, rest),
        _ => name.to_string(),
    }
}

fn modifier(part: &str) -> Option<(u8, &'static str)> {
    Some(match part.to_ascii_lowercase().as_str() {
        "control" | "ctrl" | "leftcontrol" | "rightcontrol" => (0, "Control"),
        "alt" | "leftalt" | "rightalt" => (1, "Alt"),
        "shift" | "leftshift" | "rightshift" => (2, "Shift"),
        "command" | "cmd" | "leftcommand" | "rightcommand" => (3, "Command"),
        _ => return None,
    })
}

/// The comparable form: modifiers in a fixed order, then the key, all without case; empty when the chord has no key
/// (unbound, or only modifiers, or two keys).
pub fn normalize(chord: &str) -> String {
    let mut mods = [false; 4];
    let mut key: Option<String> = None;
    for part in chord.split('+').map(str::trim).filter(|p| !p.is_empty()) {
        match modifier(part) {
            Some((i, _)) => mods[i as usize] = true,
            None if key.is_none() => key = Some(part.to_ascii_lowercase()),
            None => return String::new(),
        }
    }
    let Some(key) = key else { return String::new() };
    let names = ["control", "alt", "shift", "command"];
    let mut out: Vec<&str> = names.iter().zip(mods).filter(|(_, on)| *on).map(|(n, _)| *n).collect();
    out.push(&key);
    out.join("+")
}

impl ModHost {
    /// Every hotkey of an enabled mod that subscribed to its hook, in load order, bound or not.
    pub fn hotkeys(&self) -> Vec<Hotkey> {
        let mut out = Vec::new();
        for &idx in &self.order {
            let m = &self.mods[idx];
            if m.state != crate::State::Enabled {
                continue;
            }
            let Some(loaded) = m.loaded.as_ref() else { continue };
            let store = crate::lock(&loaded.shared.config);
            for e in &store.entries {
                let ok_mod_api::ConfigValue::Hotkey(default) = &e.default else { continue };
                let hook = hook_name(&m.id, &e.key);
                if !loaded.subscriptions.contains(&hook) {
                    continue;
                }
                let chord = match store.get(&e.key) {
                    Some(ok_mod_api::ConfigValue::Hotkey(s) | ok_mod_api::ConfigValue::Text(s)) => s.to_string(),
                    _ => default.to_string(),
                };
                out.push(Hotkey { id: m.id.clone(), name: e.key.clone(), hook, chord, default: default.to_string(), description_id: e.description_id.clone() });
            }
        }
        out
    }

    /// A chord was pressed in `mode`: the hook of every hotkey bound to it, in load order.
    pub fn key(&mut self, chord: &str, mode: &str) -> Vec<crate::ModReply> {
        let want = normalize(chord);
        if want.is_empty() {
            return Vec::new();
        }
        let payload = json!({"mode": mode, "chord": chord}).to_string();
        let hits: Vec<Hotkey> = self.hotkeys().into_iter().filter(|h| normalize(&h.chord) == want).collect();
        hits.into_iter()
            .map(|h| crate::ModReply { result: self.hook_one(&h.id, &h.hook, &payload), id: h.id })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chords_compare_without_side_case_or_order() {
        assert_eq!(normalize("LeftControl+K"), "control+k");
        assert_eq!(normalize("k + RightControl"), "control+k");
        assert_eq!(normalize("Shift+Ctrl+F7"), "control+shift+f7");
        assert_ne!(normalize("K"), normalize("Control+K"));
        assert_eq!(normalize(""), "");
        assert_eq!(normalize("LeftShift"), "", "only a modifier is no chord");
        assert_eq!(normalize("A+B"), "", "two keys are no chord");
    }

    #[test]
    fn short_key_subscriptions_get_the_mod_id() {
        assert_eq!(expand_subscription("org.a", "key.toggle"), "key.org.a.toggle");
        assert_eq!(expand_subscription("org.a", "key.org.b.toggle"), "key.org.b.toggle");
        assert_eq!(expand_subscription("org.a", "reader.ui"), "reader.ui");
    }
}
