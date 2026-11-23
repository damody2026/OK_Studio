//! ok-mod-pack end to end on real mod DLLs: pack, install, newest-only, obsolete, verify, profiles, and the refusal
//! while a game uses the Mods folder.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Mutex, MutexGuard, OnceLock};

use ok_mod_pack::*;

fn workspace() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf()
}

fn serial() -> MutexGuard<'static, ()> {
    static M: Mutex<()> = Mutex::new(());
    M.lock().unwrap_or_else(|e| e.into_inner())
}

/// The fixture DLLs, built like the host's tests do (same folder, so one build serves both).
fn dlls() -> PathBuf {
    static DIR: OnceLock<PathBuf> = OnceLock::new();
    DIR.get_or_init(|| {
        let target = workspace().join("target/fixtures-current");
        let mut cmd = Command::new(std::env::var("CARGO").unwrap_or_else(|_| "cargo".into()));
        cmd.args(["build", "-j", "8", "-p", "ok-mod-hello", "-p", "ok-mod-fixture-panic", "-p", "ok-mod-fixture-bad-layout", "--target-dir"]).arg(&target).current_dir(workspace());
        for v in ["RUSTUP_TOOLCHAIN", "RUSTC", "RUSTC_WRAPPER", "CARGO_TARGET_DIR", "RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS"] {
            cmd.env_remove(v);
        }
        let out = cmd.output().unwrap();
        assert!(out.status.success(), "{}", String::from_utf8_lossy(&out.stderr));
        target.join("debug")
    })
    .clone()
}

struct Scratch(PathBuf);
impl Scratch {
    fn new(name: &str) -> Scratch {
        let d = workspace().join("target/test-pack").join(format!("{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        Scratch(d)
    }
    fn p(&self, rel: &str) -> PathBuf {
        self.0.join(rel)
    }
}
impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn pack_hello(s: &Scratch) -> PathBuf {
    let r = pack(
        &workspace().join("examples/hello"),
        &PackOptions { dll: Some(dlls().join("ok_hello.dll")), out: Some(s.p("packages/org.openkoikatsu.hello-0.1.0.okmod")), ..Default::default() },
    )
    .unwrap();
    assert!(r.rustc.as_deref().unwrap().starts_with("rustc"));
    PathBuf::from(r.package)
}

/// A copy of a crate folder's mod.toml (edited) with a DLL, packed without the ABI check.
fn pack_variant(s: &Scratch, name: &str, crate_dir: &str, dll: &str, edit: impl Fn(String) -> String) -> PathBuf {
    let dir = s.p(&format!("variants/{name}"));
    std::fs::create_dir_all(&dir).unwrap();
    let text = std::fs::read_to_string(workspace().join(crate_dir).join("mod.toml")).unwrap();
    std::fs::write(dir.join("mod.toml"), edit(text)).unwrap();
    std::fs::copy(dlls().join(dll), dir.join(dll)).unwrap();
    let r = pack(&dir, &PackOptions { out: Some(s.p(&format!("packages/{name}.okmod"))), skip_dll_check: true, ..Default::default() }).unwrap();
    PathBuf::from(r.package)
}

#[test]
fn pack_install_newest_only_obsolete() {
    let _g = serial();
    let s = Scratch::new("install");
    let hello = pack_hello(&s);

    // The package: mod.toml with the DLL's sha256, the DLL, the locale files.
    let mut zip = zip::ZipArchive::new(std::fs::File::open(&hello).unwrap()).unwrap();
    let names: Vec<String> = zip.file_names().map(String::from).collect();
    assert!(names.contains(&"ok_hello.dll".to_string()) && names.contains(&"locale/en/hello.toml".to_string()), "{names:?}");
    let mut toml_text = String::new();
    zip.by_name("mod.toml").unwrap().read_to_string(&mut toml_text).unwrap();
    assert!(toml_text.contains(&format!("sha256 = \"{}\"", sha256_file(&dlls().join("ok_hello.dll")).unwrap())), "{toml_text}");

    let mods = s.p("Mods");
    let r = install(&[hello.clone()], &mods, &InstallOptions::default()).unwrap();
    assert_eq!(r[0].result, "installed");
    assert!(mods.join("org.openkoikatsu.hello/ok_hello.dll").is_file());
    assert_eq!(install(&[hello.clone()], &mods, &InstallOptions::default()).unwrap()[0].result, "already_installed");
    let rec = read_installed(&mods).unwrap();
    assert_eq!(rec.mods.len(), 1);
    assert_eq!(rec.mods[0].version, "0.1.0");

    // An older copy of the same id is not installed over the newer one, unless forced; the newer then goes to .old.
    let older = pack_variant(&s, "hello-old", "examples/hello", "ok_hello.dll", |t| t.replace("version = \"0.1.0\"", "version = \"0.0.9\""));
    let r = install(&[older.clone()], &mods, &InstallOptions::default()).unwrap();
    assert_eq!(r[0].result, "kept_newer");
    let r = install(&[older], &mods, &InstallOptions { force: true, profile: None }).unwrap();
    assert_eq!(r[0].result, "upgraded", "{r:?}");
    let r = install(&[hello], &mods, &InstallOptions::default()).unwrap();
    assert_eq!(r[0].result, "upgraded");
    assert_eq!(std::fs::read_dir(mods.join(".old")).unwrap().count(), 2);
    assert_eq!(read_installed(&mods).unwrap().mods[0].version, "0.1.0");

    // On the obsolete list: refused.
    let panic = pack_variant(&s, "panic", "fixtures/panic-mod", "ok_fixture_panic.dll", |t| t);
    let r = install(&[panic], &mods, &InstallOptions::default()).unwrap();
    assert_eq!(r[0].result, "refused");
    assert!(r[0].detail.as_deref().unwrap().contains("obsolete"));
    assert!(!mods.join("org.openkoikatsu.test.panic").exists());

    // A tampered DLL fails the sha256 check.
    let bad = pack_variant(&s, "hello-tampered", "examples/hello", "ok_hello.dll", |t| t.replace("org.openkoikatsu.hello", "org.example.tampered"));
    let fixed = s.p("packages/tampered2.okmod");
    {
        let mut src = zip::ZipArchive::new(std::fs::File::open(&bad).unwrap()).unwrap();
        let mut w = zip::ZipWriter::new(std::fs::File::create(&fixed).unwrap());
        for i in 0..src.len() {
            let mut e = src.by_index(i).unwrap();
            let mut bytes = Vec::new();
            e.read_to_end(&mut bytes).unwrap();
            if e.name().ends_with(".dll") {
                bytes[100] ^= 0xff;
            }
            w.start_file(e.name().to_string(), zip::write::SimpleFileOptions::default()).unwrap();
            std::io::Write::write_all(&mut w, &bytes).unwrap();
        }
        w.finish().unwrap();
    }
    assert!(install(&[fixed], &mods, &InstallOptions::default()).unwrap_err().contains("sha256"));
}

#[test]
fn verify_retires_and_checks() {
    let _g = serial();
    let s = Scratch::new("verify");
    let mods = s.p("Mods");
    install(&[pack_hello(&s)], &mods, &InstallOptions::default()).unwrap();
    let r = verify(&mods, false).unwrap();
    assert!(r.ok(), "{r:?}");
    assert_eq!(r.loads["reader"], vec!["org.openkoikatsu.hello".to_string()]);

    // Dropped in by hand: an obsolete mod, an older duplicate and a DLL with the wrong layout.
    let copy_in = |folder: &str, crate_dir: &str, dll: &str, edit: &dyn Fn(String) -> String| {
        let d = mods.join(folder);
        std::fs::create_dir_all(&d).unwrap();
        std::fs::write(d.join("mod.toml"), edit(std::fs::read_to_string(workspace().join(crate_dir).join("mod.toml")).unwrap())).unwrap();
        std::fs::copy(dlls().join(dll), d.join(dll)).unwrap();
    };
    copy_in("panic", "fixtures/panic-mod", "ok_fixture_panic.dll", &|t| t);
    copy_in("hello-old", "examples/hello", "ok_hello.dll", &|t| t.replace("version = \"0.1.0\"", "version = \"0.0.1\""));
    copy_in("bad", "fixtures/bad-layout", "ok_fixture_bad_layout.dll", &|t| t.replace("org.openkoikatsu.test.badlayout", "org.example.badlayout"));
    copy_in("needs", "examples/hello", "ok_hello.dll", &|t| t.replace("org.openkoikatsu.hello", "org.example.needs") + "\n[dependencies]\n\"org.example.missing\" = \"*\"\n");

    let dry = verify(&mods, true).unwrap();
    assert_eq!(dry.retired.len(), 2, "{dry:?}");
    assert!(mods.join("panic").exists());

    let r = verify(&mods, false).unwrap();
    assert!(!r.ok());
    assert_eq!(r.retired.len(), 2, "{r:?}");
    assert!(!mods.join("panic").exists() && !mods.join("hello-old").exists());
    assert!(r.problems["bad"].contains("not a compatible ok_mod DLL"), "{r:?}");
    // "needs" also fails the DLL check (its DLL is hello's); the dependency check reports mods whose DLL passed.
    assert!(r.problems.contains_key("needs"));
    assert_eq!(r.loads["studio"], vec!["org.openkoikatsu.hello".to_string()]);

    // A Mods/obsolete.toml entry retires an installed mod: it leaves .installed.toml too (it used to stay listed).
    assert_eq!(read_installed(&mods).unwrap().mods.len(), 1);
    std::fs::write(mods.join("obsolete.toml"), "[[obsolete]]
id = \"org.openkoikatsu.hello\"
versions = \"<0.2\"
reason = \"test\"
").unwrap();
    let r = verify(&mods, false).unwrap();
    assert!(r.retired.iter().any(|l| l.contains("obsolete: test")), "{r:?}");
    assert!(read_installed(&mods).unwrap().mods.is_empty());
}

#[test]
fn profiles_save_and_apply() {
    let _g = serial();
    let s = Scratch::new("profile");
    let mods = s.p("Mods");
    let hello = pack_hello(&s);
    let extra = pack_variant(&s, "org.example.extra-1.0.0", "examples/hello", "ok_hello.dll", |t| {
        t.replace("org.openkoikatsu.hello", "org.example.extra").replace("version = \"0.1.0\"", "version = \"1.0.0\"")
    });
    install(&[extra], &mods, &InstallOptions::default()).unwrap();

    // A profile of hello alone (the repository's starter needs every starter package; see every_example_is_in_full).
    let starter = s.p("starter.toml");
    std::fs::write(&starter, "name = \"starter\"\n\n[[mod]]\nid = \"org.openkoikatsu.hello\"\nversion = \"0.1.0\"\n").unwrap();
    let r = profile_apply(&starter, &mods, hello.parent().unwrap(), &InstallOptions::default()).unwrap();
    assert!(r.iter().any(|o| o.id == "org.openkoikatsu.hello" && o.result == "installed"), "{r:?}");
    assert!(!mods.join("org.example.extra").exists(), "mods outside the profile go to .old");
    let rec = read_installed(&mods).unwrap();
    assert_eq!(rec.profile.as_deref(), Some("starter"));
    assert_eq!(rec.mods.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), vec!["org.openkoikatsu.hello"]);

    let saved = profile_save(&mods, "mine", None).unwrap();
    let p = read_profile(&saved).unwrap();
    assert_eq!(p.mods, vec![ProfileMod { id: "org.openkoikatsu.hello".into(), version: "0.1.0".into() }]);
    // Applying it again changes nothing.
    let r = profile_apply(&saved, &mods, hello.parent().unwrap(), &InstallOptions::default()).unwrap();
    assert_eq!(r[0].result, "already_installed");
    assert!(read_profile(&workspace().join("profiles/full.toml")).is_ok());
    assert!(read_profile(&workspace().join("profiles/starter.toml")).is_ok());
}

/// The full profile lists every example mod (section 14.4), at its version; the starter profile only examples.
#[test]
fn every_example_is_in_full() {
    let full = read_profile(&workspace().join("profiles/full.toml")).unwrap();
    let starter = read_profile(&workspace().join("profiles/starter.toml")).unwrap();
    let mut examples = Vec::new();
    for e in std::fs::read_dir(workspace().join("examples")).unwrap().flatten() {
        let Ok(text) = std::fs::read_to_string(e.path().join("mod.toml")) else { continue };
        let t: toml::Table = toml::from_str(&text).unwrap();
        examples.push(ProfileMod { id: t["id"].as_str().unwrap().into(), version: t["version"].as_str().unwrap().into() });
    }
    for m in &examples {
        assert!(full.mods.contains(m), "full profile lacks {} {}", m.id, m.version);
    }
    assert_eq!(full.mods.len(), examples.len(), "full lists something that is not an example");
    for m in &starter.mods {
        assert!(examples.contains(m), "starter lists {} {}, not an example", m.id, m.version);
    }
}

#[test]
fn refused_while_a_game_uses_the_folder() {
    let _g = serial();
    let s = Scratch::new("running");
    let mods = s.p("Mods");
    let hello = pack_hello(&s);
    // A game of this "checkout": its control file names this Mods folder and its UI port answers.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    std::fs::create_dir_all(s.p("Saved/OKControl")).unwrap();
    std::fs::write(
        s.p("Saved/OKControl/4242.json"),
        serde_json::json!({"pid": 4242, "port_ui": port.to_string(), "mods_dir": mods.display().to_string().replace('\\', "/")}).to_string(),
    )
    .unwrap();
    assert_eq!(game_using(&mods), Some(4242));
    let e = install(&[hello.clone()], &mods, &InstallOptions::default()).unwrap_err();
    assert!(e.contains("pid 4242"), "{e}");
    assert_eq!(install(&[hello.clone()], &mods, &InstallOptions { force: true, profile: None }).unwrap()[0].result, "installed");
    // The game closed (port no longer answers): allowed.
    drop(listener);
    assert_eq!(game_using(&mods), None);
}

#[test]
fn locale_ids_must_carry_the_prefix() {
    let _g = serial();
    let s = Scratch::new("locale");
    let dir = s.p("m");
    std::fs::create_dir_all(dir.join("locale/en")).unwrap();
    std::fs::copy(workspace().join("examples/hello/mod.toml"), dir.join("mod.toml")).unwrap();
    std::fs::copy(dlls().join("ok_hello.dll"), dir.join("ok_hello.dll")).unwrap();
    std::fs::write(dir.join("locale/en/x.toml"), "\"ui.something\" = \"x\"\n").unwrap();
    let e = pack(&dir, &PackOptions { out: Some(s.p("x.okmod")), ..Default::default() }).unwrap_err();
    assert!(e.contains("mod.org.openkoikatsu.hello."), "{e}");
    // A content pak needs content_build.
    std::fs::remove_dir_all(dir.join("locale")).unwrap();
    std::fs::create_dir_all(dir.join("content")).unwrap();
    std::fs::write(dir.join("content/x.pak"), b"pak").unwrap();
    assert!(pack(&dir, &PackOptions { out: Some(s.p("x.okmod")), ..Default::default() }).unwrap_err().contains("content_build"));
}

#[test]
fn panels_go_into_the_package() {
    // ui/<Name>.dui travels with a pak's panel (the game refuses the pak without it; found on a staged install).
    let _g = serial();
    let s = Scratch::new("ui");
    let dir = s.p("variants/panel");
    std::fs::create_dir_all(dir.join("ui")).unwrap();
    std::fs::write(dir.join("mod.toml"), std::fs::read_to_string(workspace().join("examples/hello/mod.toml")).unwrap()).unwrap();
    std::fs::copy(dlls().join("ok_hello.dll"), dir.join("ok_hello.dll")).unwrap();
    std::fs::write(dir.join("ui/Panel.dui"), "panel").unwrap();
    let r = pack(&dir, &PackOptions { out: Some(s.p("panel.okmod")), skip_dll_check: true, ..Default::default() }).unwrap();
    let zip = zip::ZipArchive::new(std::fs::File::open(&r.package).unwrap()).unwrap();
    assert!(zip.file_names().any(|n| n == "ui/Panel.dui"), "{:?}", zip.file_names().collect::<Vec<_>>());
    let mods = s.p("Mods");
    install(&[PathBuf::from(&r.package)], &mods, &InstallOptions::default()).unwrap();
    assert!(mods.join("org.openkoikatsu.hello/ui/Panel.dui").is_file());
}
