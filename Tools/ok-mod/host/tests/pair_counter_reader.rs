//! E's `pair-counter` seen from the reader (OK mod wave 3): the section a one-on-one writes into her card (pair.exit's
//! reply, which OKPairModBridge.cpp writes into the card's okMx) is what the reader's page then shows, read only.

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use ok_mod_host::{ffi, HostConfig, LogSink, ModHost};
use serde_json::{json, Value};

const ID: &str = "org.openkoikatsu.pair_counter";

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn build() -> PathBuf {
    let target_dir = workspace().join("target").join("fixtures-pair-counter");
    let mut cmd = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()));
    cmd.args(["build", "-j", "8", "-p", "ok-mod-pair-counter", "--target-dir"]).arg(&target_dir).current_dir(workspace());
    for v in ["CARGO_TARGET_DIR", "CARGO_BUILD_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
        cmd.env_remove(v);
    }
    let out = cmd.output().expect("run cargo");
    assert!(out.status.success(), "example build failed:\n{}", String::from_utf8_lossy(&out.stderr));
    target_dir.join("debug")
}

fn open(root: &Path, dlls: &Path, mode: &str) -> ModHost {
    let dest = root.join("Mods").join("pair-counter");
    std::fs::create_dir_all(&dest).unwrap();
    std::fs::copy(workspace().join("examples/pair-counter/mod.toml"), dest.join("mod.toml")).unwrap();
    std::fs::copy(dlls.join("ok_pair_counter.dll"), dest.join("ok_pair_counter.dll")).unwrap();
    let sink: LogSink = Arc::new(|_, id, m| eprintln!("[{id}] {m}"));
    let mut cfg = HostConfig::new(root.join("Mods"), mode);
    cfg.config_dir = Some(root.join("config"));
    let host = ModHost::open(cfg, sink);
    for s in host.statuses() {
        assert_eq!(s.state, "enabled", "{s:?}");
    }
    host
}

fn ask(host: &mut ModHost, req: Value) -> Value {
    ffi::handle(host, &req).unwrap_or_else(|e| panic!("{req}: {e}"))
}

#[test]
fn the_reader_shows_what_a_one_on_one_wrote() {
    let dlls = build();
    let root = workspace().join("target").join("test-mods").join(format!("pair-counter-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);

    // A one-on-one with her: two finishes, 90 seconds; the reply is the section the game writes into her card.
    let mut pair = open(&root.join("pair"), &dlls, "pair");
    let card = "C:/cards/her.png";
    let hook = |host: &mut ModHost, name: &str, payload: Value| {
        let r = ask(host, json!({"op": "hook", "hook": name, "payload": payload}));
        r["replies"].as_array().unwrap().iter().find(|r| r["mod"] == ID).cloned().unwrap()
    };
    hook(&mut pair, "pair.enter", json!({"card": card, "section": null}));
    hook(&mut pair, "pair.finish", json!({"card": card, "text": "org_in"}));
    hook(&mut pair, "pair.finish", json!({"card": card, "text": "same_out"}));
    let exit = hook(&mut pair, "pair.exit", json!({"card": card, "seconds": 90.0, "section": null}));
    let section = exit["json"].clone();
    assert_eq!(section["version"], 1, "{exit}");
    pair.close();

    // The reader opens that card: its page shows the counts, read only (no registry rows: nothing to set).
    let mut reader = open(&root.join("reader"), &dlls, "reader");
    let ui = ask(&mut reader, json!({"op": "reader.ui"})).to_string();
    assert!(ui.contains("1 對 1 統計") && ui.contains(&format!("mod.{ID}.times")), "{ui}");
    let before = ask(&mut reader, json!({"op": "reader.values"}));
    assert_eq!(before[format!("mod.{ID}.summary")], "還沒有開卡。", "{before}");

    let png = root.join("her.png");
    let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
    bytes.extend_from_slice(b"\0\0\0\0IEND\xaeB`\x82");
    std::fs::write(&png, &bytes).unwrap();
    let path = png.to_str().unwrap();
    ask(&mut reader, json!({"op": "card_load", "card": path, "outfit": 0, "imported": {ID: section}}));
    let v = ask(&mut reader, json!({"op": "reader.values"}));
    assert_eq!(v[format!("mod.{ID}.times")], "1 次", "{v}");
    assert_eq!(v[format!("mod.{ID}.time")], "共 1.5 分鐘，平均每次 1.5 分鐘");
    assert_eq!(v[format!("mod.{ID}.finishes")], "她 2 次，他 1 次");
    assert_eq!(v[format!("mod.{ID}.summary")], "");

    // A card without the data.
    let other = root.join("other.png");
    std::fs::write(&other, &bytes).unwrap();
    ask(&mut reader, json!({"op": "card_load", "card": other.to_str().unwrap(), "outfit": 0}));
    let v = ask(&mut reader, json!({"op": "reader.values"}));
    assert_eq!(v[format!("mod.{ID}.summary")], "這張卡還沒有 1 對 1 的紀錄。", "{v}");
    reader.close();
    let _ = std::fs::remove_dir_all(&root);
}
