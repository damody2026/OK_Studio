//! Per-frame calls (feature `frame`): the boop example's `ok_mod_frame`, reached through `okm_frame` as ok-extract calls
//! it. `cargo test -p ok-mod-host --features frame`.
#![cfg(feature = "frame")]

use std::ffi::{c_char, c_void, CString};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;

use ok_mod_host::{HostConfig, LogSink, ModHost};

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct Bone {
    pos: [f32; 3],
    rot: [f32; 4],
    scale: [f32; 3],
}
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
struct Force {
    center: [f32; 3],
    radius: f32,
    force: [f32; 3],
    reserved: f32,
}
/// Tools/ok-extract/src/mod_frame.rs OkModFrame.
#[repr(C)]
struct Frame {
    struct_size: u32,
    version: u32,
    kind: u32,
    sex: i32,
    character: u64,
    dt: f32,
    time: f32,
    bone_count: u32,
    names: *const *const c_char,
    bones: *mut Bone,
    worlds: *const [f32; 16],
    forces: *mut Force,
    force_cap: u32,
    force_count: u32,
}

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn translate(x: f32, y: f32, z: f32) -> [f32; 16] {
    [1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z, 0.0, 0.0, 0.0, 1.0]
}

#[test]
fn boop_pushes_through_okm_frame() {
    let target_dir = workspace().join("target").join("fixtures-frame");
    let out = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()))
        .args(["build", "-j", "8", "-p", "ok-mod-boop", "--target-dir"])
        .arg(&target_dir)
        .current_dir(workspace())
        .env_remove("CARGO_TARGET_DIR")
        .output()
        .expect("cargo");
    assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
    let root = workspace().join("target").join("test-mods").join(format!("frame-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let dest = root.join("Mods").join("boop");
    std::fs::create_dir_all(&dest).unwrap();
    std::fs::copy(workspace().join("examples/boop/mod.toml"), dest.join("mod.toml")).unwrap();
    std::fs::copy(target_dir.join("debug").join("ok_boop.dll"), dest.join("ok_boop.dll")).unwrap();

    let sink: LogSink = Arc::new(|_, id, m| eprintln!("[{id}] {m}"));
    let mut host = ModHost::open(HostConfig::new(root.join("Mods"), "reader"), sink);
    host.enter_mode("reader");

    // A character: head 1 above the waist, the bust between.
    let names: Vec<CString> = ["cf_j_hips", "cf_j_head", "cf_j_bust01_L", "cf_j_waist02"].iter().map(|n| CString::new(*n).unwrap()).collect();
    let name_ptrs: Vec<*const c_char> = names.iter().map(|n| n.as_ptr()).collect();
    let mut bones = vec![Bone::default(); 4];
    let worlds = [translate(0.0, 0.0, 0.0), translate(0.0, 1.0, 0.0), translate(0.1, 0.6, 0.1), translate(0.0, 0.0, 0.0)];
    let mut forces = [Force::default(); 8];
    assert_eq!(std::mem::size_of::<Frame>() as u32, ok_mod_host::frame::FRAME_V1_SIZE);
    let mut frame = Frame { struct_size: std::mem::size_of::<Frame>() as u32, version: ok_mod_host::frame::FRAME_VERSION, kind: 0, character: 42, sex: 1, dt: 0.016, time: 0.0, bone_count: 4,
        names: name_ptrs.as_ptr(), bones: bones.as_mut_ptr(), worlds: worlds.as_ptr(), forces: forces.as_mut_ptr(), force_cap: 8, force_count: 0 };
    let call = |frame: &mut Frame| unsafe { ok_mod_host::frame::okm_frame(frame as *mut Frame as *mut c_void) };

    assert_eq!(call(&mut frame), 0, "boop never changes bones");
    assert_eq!(frame.force_count, 0, "no poke yet");

    host.command("org.openkoikatsu.boop", "poke", "chest").unwrap();
    call(&mut frame);
    assert_eq!(frame.force_count, 1, "{:?}", &forces[..1]);
    assert_eq!(forces[0].center, [0.1, 0.6, 0.1], "pushed at the bust");
    assert!(forces[0].radius > 0.0);

    // A frame of a version the host does not know reaches nobody.
    frame.version = 2;
    frame.force_count = 0;
    call(&mut frame);
    assert_eq!(frame.force_count, 0, "unknown version");
    frame.version = ok_mod_host::frame::FRAME_VERSION;

    let stats = ok_mod_host::frame::stats_json();
    assert_eq!(stats["mods"][0]["id"], "org.openkoikatsu.boop");
    assert_eq!(stats["mods"][0]["calls"], 2);
    assert_eq!(stats["mods"][0]["stopped"], false);

    // Turned off: frames reach nobody.
    host.disable("org.openkoikatsu.boop").unwrap();
    frame.force_count = 0;
    call(&mut frame);
    assert_eq!(frame.force_count, 0);
    host.close();
}
