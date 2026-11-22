//! Resources in a card (`okMr`, plan §6.12) with the `skin-decal` example: saved once by sha256 and named in the mod's
//! data, handed back on load, dropped when no section names them, and refused over the per-mod limit.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use ok_mod_host::{ffi, HostConfig, LogSink, ModHost};
use serde_json::{json, Value};

const DECAL: &str = "org.openkoikatsu.skin-decal";

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn ask(host: &mut ModHost, req: Value) -> Value {
    ffi::handle(host, &req).unwrap_or_else(|e| panic!("{req}: {e}"))
}

#[test]
fn decal_png_lives_in_okmr() {
    let target_dir = workspace().join("target").join("fixtures-resources");
    let mut cmd = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()));
    cmd.args(["build", "-j", "8", "-p", "ok-mod-skin-decal", "--target-dir"]).arg(&target_dir).current_dir(workspace());
    for v in ["CARGO_TARGET_DIR", "CARGO_BUILD_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
        cmd.env_remove(v);
    }
    let out = cmd.output().expect("cargo");
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let root = workspace().join("target").join("test-mods").join(format!("resources-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dest = root.join("Mods").join("skin-decal");
    std::fs::create_dir_all(&dest).unwrap();
    std::fs::copy(workspace().join("examples/skin-decal/mod.toml"), dest.join("mod.toml")).unwrap();
    std::fs::copy(target_dir.join("debug").join("ok_skin_decal.dll"), dest.join("ok_skin_decal.dll")).unwrap();

    let sink: LogSink = Arc::new(|_, id, m| eprintln!("[{id}] {m}"));
    let mut cfg = HostConfig::new(root.join("Mods"), "reader");
    cfg.config_dir = Some(root.join("config"));
    let mut host = ModHost::open(cfg, sink);
    assert_eq!(host.statuses()[0].state, "enabled", "{:?}", host.statuses());

    let card = root.join("card.png");
    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    png.extend_from_slice(b"\0\0\0\0IEND\xaeB`\x82");
    std::fs::write(&card, &png).unwrap();
    let path = card.to_str().unwrap();
    let identity = ok_card_mods::card_identity(&png);

    // A heart on her face, saved into the card.
    ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0}));
    for (key, value) in [("source", json!("heart")), ("target", json!("head")), ("u", json!(0.3)), ("opacity", json!(0.5))] {
        let r = ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{DECAL}.{key}"), "value": value}));
        assert_eq!(r["ok"], true, "{r}");
    }
    let store = ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert_eq!(store["written"], json!([DECAL]), "{store}");
    assert_eq!(store["resources"]["count"], 1, "{store}");
    let bytes = std::fs::read(&card).unwrap();
    assert_eq!(ok_card_mods::card_identity(&bytes), identity, "her identity is kept");
    let res = ok_card_mods::read_resources(&bytes).unwrap();
    let (hash, heart) = res.by_hash.iter().next().unwrap();
    let section = ok_card_mods::read_data(&bytes).unwrap().get(DECAL).unwrap().unwrap();
    assert!(String::from_utf8_lossy(&section.data).contains(hash.as_str()), "the data names the picture");

    // Opened again: the mod gets the picture with its section.
    let load = ask(&mut host, json!({"op": "card_load", "card": path, "outfit": 0}));
    assert_eq!(load["replies"][0]["ok"], true, "{load}");
    let values = ask(&mut host, json!({"op": "reader.values"}));
    assert_eq!(values[format!("mod.{DECAL}.target")], "head", "{values}");
    assert!(values[format!("mod.{DECAL}.status")].as_str().unwrap().contains("KB"), "{values}");
    // Saved without changes: same bytes, same single resource.
    ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert_eq!(ok_card_mods::read_resources(&std::fs::read(&card).unwrap()).unwrap().by_hash.len(), 1);

    // A star instead: the heart nobody names any more leaves the card.
    ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{DECAL}.source"), "value": "star"}));
    let store = ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert_eq!(store["resources"]["pruned"], 1, "{store}");
    let res = ok_card_mods::read_resources(&std::fs::read(&card).unwrap()).unwrap();
    assert_eq!(res.by_hash.len(), 1);
    assert_ne!(res.by_hash.values().next().unwrap(), heart, "the star replaced the heart");

    // Over the limit: not written, and the card keeps the star.
    std::env::set_var("OK_MOD_RESOURCE_LIMIT", "100");
    ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{DECAL}.source"), "value": "heart"}));
    let store = ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    std::env::remove_var("OK_MOD_RESOURCE_LIMIT");
    assert_eq!(store["ok"], false, "{store}");
    assert!(store["errors"][0]["error"].as_str().unwrap().contains("over the limit"), "{store}");
    let res = ok_card_mods::read_resources(&std::fs::read(&card).unwrap()).unwrap();
    assert_ne!(res.by_hash.values().next().unwrap(), heart);

    // No decal: section and picture both leave.
    ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{DECAL}.source"), "value": "none"}));
    let store = ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert_eq!(store["removed"], json!([DECAL]), "{store}");
    let bytes = std::fs::read(&card).unwrap();
    assert!(ok_card_mods::chunk(&bytes, ok_card_mods::RESOURCE_CHUNK).is_none(), "okMr gone");
    assert_eq!(ok_card_mods::card_identity(&bytes), identity);

    // The core's own section (the reader's material overrides): written, read, kept by a mod save, removed.
    let none = ask(&mut host, json!({"op": "card_core", "card": path, "id": "ok.materials"}));
    assert!(none["data_b64"].is_null(), "{none}");
    let data = "eyJvdmVycmlkZXMiOltdfQ=="; // {"overrides":[]}
    ask(&mut host, json!({"op": "card_core", "card": path, "id": "ok.materials", "data_b64": data}));
    ask(&mut host, json!({"op": "reader.control", "key": format!("mod.{DECAL}.source"), "value": "heart"}));
    ask(&mut host, json!({"op": "card_store", "card": path, "outfit": 0}));
    assert_eq!(ask(&mut host, json!({"op": "card_core", "card": path, "id": "ok.materials"}))["data_b64"], data);
    assert!(ffi::handle(&mut host, &json!({"op": "card_core", "card": path, "id": DECAL, "data_b64": data})).is_err(), "only ok.* ids");
    let removed = ask(&mut host, json!({"op": "card_core", "card": path, "id": "ok.materials", "data_b64": null}));
    assert_eq!(removed["changed"], true);
    assert_eq!(ok_card_mods::card_identity(&std::fs::read(&card).unwrap()), identity);
    host.close();
}
