//! The reader / card requests (host/src/card.rs) with the real example mods `profile`, `outfit-names`, `random-chara`
//! and `subtitles` (Docs/OK_MOD_HOOKS.md): conversion from KKEx, load, edit, save into the card, load again, the
//! apply-on-load switch, a missing mod, a button command and a voice line.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use base64::Engine;
use ok_mod_host::{ffi, HostConfig, LogSink, ModHost};
use serde_json::{json, Value};

const PROFILE: &str = "org.openkoikatsu.profile";
const NAMES: &str = "org.openkoikatsu.outfit-names";
const RANDOM: &str = "org.openkoikatsu.random-chara";

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn build() -> PathBuf {
    let target_dir = workspace().join("target").join("fixtures-examples");
    let mut cmd = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()));
    cmd.args(["build", "-j", "8", "-p", "ok-mod-profile", "-p", "ok-mod-outfit-names", "-p", "ok-mod-random-chara", "-p", "ok-mod-subtitles", "--target-dir"])
        .arg(&target_dir)
        .current_dir(workspace());
    for v in ["CARGO_TARGET_DIR", "CARGO_BUILD_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
        cmd.env_remove(v);
    }
    let out = cmd.output().expect("run cargo");
    assert!(out.status.success(), "example build failed:\n{}", String::from_utf8_lossy(&out.stderr));
    target_dir.join("debug")
}

fn install(mods: &Path, dlls: &Path, folder: &str, dll: &str) {
    let dest = mods.join(folder);
    std::fs::create_dir_all(&dest).unwrap();
    std::fs::copy(workspace().join("examples").join(folder).join("mod.toml"), dest.join("mod.toml")).unwrap();
    std::fs::copy(dlls.join(dll), dest.join(dll)).unwrap();
}

fn ask(host: &mut ModHost, req: Value) -> Value {
    ffi::handle(host, &req).unwrap_or_else(|e| panic!("{req}: {e}"))
}

fn values(host: &mut ModHost) -> Value {
    ask(host, json!({"op": "reader.values"}))
}

#[test]
fn examples_round_trip_through_a_card() {
    let dlls = build();
    let root = workspace().join("target").join("test-mods").join(format!("cards-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let mods = root.join("Mods");
    for (folder, dll) in [("profile", "ok_profile.dll"), ("outfit-names", "ok_outfit_names.dll"), ("random-chara", "ok_random_chara.dll"), ("subtitles", "ok_subtitles.dll")] {
        install(&mods, &dlls, folder, dll);
    }
    let sink: LogSink = Arc::new(|_, id, m| eprintln!("[{id}] {m}"));
    let mut cfg = HostConfig::new(mods.clone(), "reader");
    cfg.config_dir = Some(root.join("config"));
    let mut host = ModHost::open(cfg, sink);
    for s in host.statuses() {
        assert_eq!(s.state, "enabled", "{s:?}");
    }

    // A PNG with nothing but IEND is enough for the chunk code.
    let card = root.join("card.png");
    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    png.extend_from_slice(b"\0\0\0\0IEND\xaeB`\x82");
    std::fs::write(&card, &png).unwrap();
    let path = card.to_str().unwrap();

    // Conversion: KK_Profile = [0, {"ProfileText": "hi"}] in msgpack.
    let mut kk = vec![0x92, 0x00, 0x81, 0xab];
    kk.extend_from_slice(b"ProfileText");
    kk.extend_from_slice(&[0xa2, b'h', b'i']);
    let b64 = base64::engine::general_purpose::STANDARD;
    let kkex = ask(&mut host, json!({"op": "extract.kkex", "sections": {"KK_Profile": b64.encode(&kk)}}));
    let section = &kkex["sections"][PROFILE];
    assert_eq!(section["version"], 1, "{kkex}");
    assert_eq!(b64.decode(section["data_b64"].as_str().unwrap()).unwrap(), br#"{"text":"hi"}"#);
    assert_eq!(section["requires"]["id"], PROFILE);
    let keys = ask(&mut host, json!({"op": "hook", "hook": "extract.kkex_keys", "payload": {}}));
    assert!(keys.to_string().contains("KK_Profile"), "{keys}");

    // Opening that original card: the section made from its KKEx is handed over as imported, and the next save
    // writes it (the reader passes ok-extract's ok_kkex_mod_sections as "imported").
    let original = root.join("original.png");
    std::fs::write(&original, &png).unwrap();
    let opath = original.to_str().unwrap();
    ask(&mut host, json!({"op": "card_load", "card": opath, "outfit": 0, "imported": {PROFILE: section.clone()}}));
    assert_eq!(values(&mut host)[format!("mod.{PROFILE}.text")], "hi");
    let store = ask(&mut host, json!({"op": "card_store", "card": opath, "outfit": 0}));
    assert!(store["written"].to_string().contains(PROFILE), "{store}");

    // A card without data: nothing missing, nothing to apply.
    let load = ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0}));
    assert_eq!(load["missing"], json!([]), "{load}");
    assert_eq!(values(&mut host)[format!("mod.{PROFILE}.text")], "");

    // The reader's pages: keys and actions are mod.<id>.*.
    let ui = ask(&mut host, json!({"op": "reader.ui"})).to_string();
    assert!(ui.contains(&format!("mod.{PROFILE}.text")) && ui.contains(&format!("mod.{RANDOM}.roll")), "{ui}");
    // Inside tabs and groups too (profile and outfit-names put their fields on tabs).
    assert!(ui.contains(&format!("mod.{NAMES}.all")) && ui.contains(&format!("mod.{PROFILE}.length")) && !ui.contains(r#""key":"text""#), "{ui}");

    // Edit, then save into the card.
    let set = ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{PROFILE}.text"), "value": "她喜歡貓"}));
    assert_eq!(set["ok"], true, "{set}");
    let set = ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{NAMES}.name"), "value": "制服"}));
    assert_eq!(set["json"]["outfit_names"]["0"], "制服", "{set}");
    let refused = ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{RANDOM}.spread"), "value": "huge"}));
    assert_eq!(refused["ok"], false, "{refused}");
    let identity = ask(&mut host, json!({"op": "card_mods", "card": path}))["identity"].clone();
    let store = ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert_eq!(store["ok"], true, "{store}");
    let mut written: Vec<String> = serde_json::from_value(store["written"].clone()).unwrap();
    written.sort();
    assert_eq!(written, vec![NAMES.to_string(), PROFILE.to_string()]);
    let listed = ask(&mut host, json!({"op": "card_mods", "card": path}));
    assert_eq!(listed["identity"], identity, "writing mod data keeps the card's identity");
    assert_eq!(listed["sections"].as_array().unwrap().len(), 2, "{listed}");

    // Another card in between, then this one again: the text comes back from the card.
    ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{PROFILE}.text"), "value": "x"}));
    let load = ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0}));
    assert_eq!(values(&mut host)[format!("mod.{PROFILE}.text")], "她喜歡貓");
    let names = load["replies"].as_array().unwrap().iter().find(|r| r["mod"] == NAMES).unwrap();
    assert_eq!(names["json"]["outfit_names"]["0"], "制服", "{load}");

    // Apply-on-load off for profile: nothing shown, and saving keeps the card's section as it was.
    ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0, "skip_apply": [PROFILE]}));
    assert_eq!(values(&mut host)[format!("mod.{PROFILE}.text")], "");
    let store = ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert!(!store["written"].to_string().contains(PROFILE) && !store["removed"].to_string().contains(PROFILE), "{store}");
    ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0}));
    assert_eq!(values(&mut host)[format!("mod.{PROFILE}.text")], "她喜歡貓");

    // A mod that is not here: named as missing, its data stays in the card.
    assert_eq!(ask(&mut host, json!({"op": "disable", "mod": NAMES}))["ok"], true);
    let load = ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0}));
    assert_eq!(load["missing"], json!([{"id": NAMES, "version": "0.1.0"}]), "{load}");
    ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    let listed = ask(&mut host, json!({"op": "card_mods", "card": path}));
    assert!(listed.to_string().contains(NAMES), "{listed}");

    // The random page's button, and a voice line.
    let roll = ask(&mut host, json!({"op": "command", "command": format!("mod.{RANDOM}.roll")}));
    assert_eq!(roll["json"]["set"].as_array().unwrap().len(), 96, "{roll}");
    let speech = ask(&mut host, json!({"op": "hook", "hook": "reader.speech_start", "payload": {"mode": "reader", "text": "早安"}}));
    let subtitle = &speech["replies"][0]["json"]["subtitle"];
    assert_eq!(subtitle["text"], "早安", "{speech}");
    assert!(subtitle["seconds"].as_f64().unwrap() >= 2.0);

    host.close();
    let _ = std::fs::remove_dir_all(&root);
}
