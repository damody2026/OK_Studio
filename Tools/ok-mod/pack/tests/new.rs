//! `ok-mod-pack new` end to end: the template builds on its own (outside the workspace), packs, installs and answers
//! its command and hotkey in the host; inside the workspace it is left to the workspace (no own [workspace]).

use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use ok_mod_host::ok_mod_api::{ConfigValue, Reply};
use ok_mod_host::{HostConfig, ModHost};
use ok_mod_pack::*;

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

const ID: &str = "org.example.tea-time";

#[test]
fn new_mod_builds_packs_and_loads() {
    let root = std::env::temp_dir().join(format!("ok-mod-new-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dir = root.join("tea-time");
    let r = new_mod(&dir, ID, &NewOptions { author: Some("Someone".into()), ..Default::default() }).unwrap();
    assert_eq!((r.crate_name.as_str(), r.dll.as_str(), r.workspace_member.as_deref()), ("ok-mod-tea-time", "ok_tea_time.dll", None));
    let cargo = std::fs::read_to_string(dir.join("Cargo.toml")).unwrap();
    assert!(cargo.contains("[workspace]") && cargo.contains("panic = \"unwind\""), "{cargo}");
    assert!(new_mod(&dir, ID, &NewOptions::default()).unwrap_err().contains("not empty"));
    assert!(new_mod(&root.join("x"), "Bad Id", &NewOptions::default()).is_err());

    // Build it as an author would, with the workspace's lock file so nothing is fetched.
    std::fs::copy(workspace().join("Cargo.lock"), dir.join("Cargo.lock")).unwrap();
    let target = workspace().join("target/fixtures-new");
    let mut cmd = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()));
    cmd.args(["build", "-j", "8", "--offline", "--target-dir"]).arg(&target).current_dir(&dir);
    for v in ["RUSTUP_TOOLCHAIN", "RUSTC", "RUSTC_WRAPPER", "CARGO_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
        cmd.env_remove(v);
    }
    let out = cmd.output().unwrap();
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let dll = target.join("debug").join(&r.dll);

    // pack: mod.toml, ABI layout and unwind of the DLL, every locale id under mod.<id>.
    let p = pack(&dir, &PackOptions { dll: Some(dll), out: Some(root.join("tea.okmod")), skip_pak_check: true, ..Default::default() }).unwrap();
    assert!(p.warnings.is_empty(), "{:?}", p.warnings);
    let mods = root.join("Mods");
    assert_eq!(install(&[PathBuf::from(&p.package)], &mods, &InstallOptions::default()).unwrap()[0].result, "installed");

    let mut host = ModHost::open(HostConfig::new(&mods, "reader"), Arc::new(|_, _, _| {}));
    assert_eq!(host.command(ID, "hello", "").unwrap(), Reply::Text("hello #1 (console)".into()));
    assert!(host.key("F7", "reader").is_empty(), "the template's hotkey starts unbound");
    host.set_config(ID, "hello", ConfigValue::Text("F7".into())).unwrap();
    assert_eq!(host.key("F7", "studio")[0].result, Ok(Reply::Text("hello #2 (studio)".into())));
    host.close();
    drop(host);
    let _ = std::fs::remove_dir_all(&root);
}

#[test]
fn new_mod_inside_the_workspace_is_a_member() {
    let dir = workspace().join("target/test-pack").join(format!("new-member-{}", std::process::id())).join("m");
    let _ = std::fs::remove_dir_all(&dir);
    let r = new_mod(&dir, "org.example.member", &NewOptions::default()).unwrap();
    assert_eq!(r.workspace_member.as_deref(), Some(format!("target/test-pack/new-member-{}/m", std::process::id()).as_str()));
    let cargo = std::fs::read_to_string(dir.join("Cargo.toml")).unwrap();
    assert!(!cargo.contains("[workspace]"), "{cargo}");
    assert!(cargo.contains("path = \"../../../../sdk\""), "{cargo}");
    let _ = std::fs::remove_dir_all(dir.parent().unwrap());
}
