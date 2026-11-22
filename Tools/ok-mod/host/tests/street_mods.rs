//! The street hooks (Docs/OK_MOD_HOOKS.md §8) with the real `birthday` and `subtitles` DLLs, sent the way the street
//! sends them (OKStreetSocialMods.inl): load with a saved state, a new day, a talk, a gift, her facts, the namespaced
//! rule, a voice line, and the state coming back after a "save and load".

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use ok_mod_host::{ffi, HostConfig, LogSink, ModHost};
use serde_json::{json, Value};

const BIRTHDAY: &str = "org.openkoikatsu.birthday";

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn build() -> PathBuf {
    let target_dir = workspace().join("target").join("fixtures-street");
    let mut cmd = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()));
    cmd.args(["build", "-j", "8", "-p", "ok-mod-birthday", "-p", "ok-mod-subtitles", "--target-dir"]).arg(&target_dir).current_dir(workspace());
    for v in ["CARGO_TARGET_DIR", "CARGO_BUILD_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
        cmd.env_remove(v);
    }
    let out = cmd.output().expect("run cargo");
    assert!(out.status.success(), "example build failed:\n{}", String::from_utf8_lossy(&out.stderr));
    target_dir.join("debug")
}

fn open(root: &Path, dlls: &Path) -> ModHost {
    let mods = root.join("Mods");
    for (folder, dll) in [("birthday", "ok_birthday.dll"), ("subtitles", "ok_subtitles.dll")] {
        let dest = mods.join(folder);
        std::fs::create_dir_all(&dest).unwrap();
        std::fs::copy(workspace().join("examples").join(folder).join("mod.toml"), dest.join("mod.toml")).unwrap();
        std::fs::copy(dlls.join(dll), dest.join(dll)).unwrap();
    }
    let sink: LogSink = Arc::new(|_, id, m| eprintln!("[{id}] {m}"));
    let mut cfg = HostConfig::new(mods, "street");
    cfg.config_dir = Some(root.join("config"));
    ModHost::open(cfg, sink)
}

fn hook(host: &mut ModHost, name: &str, payload: Value, mods: Option<&[&str]>) -> Vec<Value> {
    let mut req = json!({"op": "hook", "hook": name, "payload": payload});
    if let Some(m) = mods { req["mods"] = json!(m); }
    let answer = ffi::handle(host, &req).unwrap();
    answer["replies"].as_array().unwrap().clone()
}

fn json_of<'a>(replies: &'a [Value], id: &str) -> &'a Value {
    let r = replies.iter().find(|r| r["mod"] == id).unwrap_or_else(|| panic!("no reply from {id}: {replies:?}"));
    assert_eq!(r["ok"], true, "{r}");
    &r["json"]
}

#[test]
fn birthday_and_subtitles_on_the_street() {
    let dlls = build();
    let root = workspace().join("target").join("test-mods").join(format!("street-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let mut host = open(&root, &dlls);
    for s in host.statuses() {
        assert_eq!(s.state, "enabled", "{s:?}");
    }
    let alice = json!({"id": "apng-a", "name": "愛麗絲", "birthday": "11-23"});
    let bea = json!({"id": "apng-b", "name": "Bea", "birthday": "12-01"});
    let heroines = json!([alice, bea]);

    // A new game: no saved state.
    hook(&mut host, "street.load", json!({"state": null, "heroines": heroines, "date": "2026-11-22", "lang": "zh-TW"}), Some(&[BIRTHDAY]));
    // The day before: nothing. Her birthday: a notice.
    let r = hook(&mut host, "street.day_change", json!({"date": "2026-11-22", "lang": "zh-TW", "heroines": heroines}), None);
    assert!(r.iter().all(|r| r["json"].is_null()), "{r:?}");
    let r = hook(&mut host, "street.day_change", json!({"date": "2026-11-23", "lang": "zh-TW", "heroines": heroines}), None);
    assert_eq!(json_of(&r, BIRTHDAY)["notice"], "今天是愛麗絲的生日。");

    // He talks to her and she takes his gift: recorded, the state handed back for ext.mods.
    let r = hook(&mut host, "street.talk_begin", json!({"date": "2026-11-23", "lang": "zh-TW", "heroine": alice}), None);
    assert!(json_of(&r, BIRTHDAY)["state"]["years"]["apng-a"]["2026"]["met"].as_bool().unwrap());
    let r = hook(&mut host, "street.gift", json!({"date": "2026-11-23", "heroine": alice, "item": "cake", "accepted": true, "birthday": true}), None);
    let state = json_of(&r, BIRTHDAY)["state"].clone();
    assert_eq!(state["years"]["apng-a"]["2026"], json!({"met": true, "gift": true}));
    // A declined gift, or another heroine's ordinary day: nothing changes.
    let r = hook(&mut host, "street.gift", json!({"date": "2026-11-23", "heroine": bea, "item": "x", "accepted": true}), None);
    assert!(json_of(&r, BIRTHDAY).is_null());

    // Her facts today; Bea has none.
    let r = hook(&mut host, "street.talk_facts", json!({"date": "2026-11-23", "lang": "zh-TW", "heroine": alice}), None);
    assert_eq!(json_of(&r, BIRTHDAY)["facts"], json!(["今天是你生日，你收下了他的禮物"]));
    let r = hook(&mut host, "street.talk_facts", json!({"date": "2026-11-23", "lang": "zh-TW", "heroine": bea}), None);
    assert!(json_of(&r, BIRTHDAY).is_null());

    // The namespaced rule.
    let r = hook(&mut host, "street.rule", json!({"rule": "upcoming", "request": {"date": "2026-11-24", "within": 30}}), Some(&[BIRTHDAY]));
    assert_eq!(json_of(&r, BIRTHDAY)["upcoming"][0]["id"], "apng-b");

    // A voice line on the street: the subtitle.
    let r = hook(&mut host, "street.speech_start", json!({"date": "2026-11-23", "heroine": alice, "text": "謝謝你記得。"}), None);
    assert_eq!(json_of(&r, "org.openkoikatsu.subtitles")["subtitle"]["text"], "謝謝你記得。");
    host.close();

    // Saved and loaded again (a new host, the state from ext.mods): next year she remembers.
    let mut host = open(&root.join("again"), &dlls);
    hook(&mut host, "street.load", json!({"state": state, "heroines": heroines, "date": "2027-03-01", "lang": "en"}), Some(&[BIRTHDAY]));
    let r = hook(&mut host, "street.talk_facts", json!({"date": "2027-03-01", "lang": "en", "heroine": alice}), None);
    assert_eq!(json_of(&r, BIRTHDAY)["facts"], json!(["on your birthday in 2026 he came to see you and you took a gift from him"]));
    host.close();
    let _ = std::fs::remove_dir_all(&root);
}
