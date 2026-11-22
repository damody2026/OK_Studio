//! ok-mod-pack: pack / install / verify OK mods and profiles (Docs/OK_MOD_FRAMEWORK_PLAN.md §9).

use std::path::PathBuf;

use ok_mod_pack::{install, pack, profile_apply, profile_save, verify, InstallOptions, PackOptions};

const USAGE: &str = "\
ok-mod-pack pack <mod folder> [--dll <built dll>] [--out <file.okmod>] [--skip-pak-check]
    check a mod (mod.toml, ABI layout and panic=unwind of the DLL, locale ids, content pak) and write <id>-<version>.okmod
ok-mod-pack install <file.okmod>... --to <Mods> [--force]
    unpack into the Mods folder: refused while a game uses it; same id keeps only the newest (older copy to Mods/.old);
    obsolete mods refused; Mods/.installed.toml records what came from where
ok-mod-pack verify <Mods> [--dry-run]
    offline: obsolete and older duplicate mods to Mods/.old, sha256 and ABI layout of every DLL, which mods load in
    each mode; exit 1 when a mod would not load
ok-mod-pack profile save <name> --mods <Mods> [--out <file>]
    record the installed mods and versions (Mods/profiles/<name>.toml)
ok-mod-pack profile apply <profile.toml> --mods <Mods> --packages <folder of .okmod> [--force]
    make the Mods folder hold exactly the profile
Add --json for a JSON answer.";

struct Args {
    positional: Vec<String>,
    flags: std::collections::HashMap<String, String>,
    switches: std::collections::HashSet<String>,
}

fn parse(argv: Vec<String>) -> Args {
    const VALUED: &[&str] = &["--dll", "--out", "--to", "--mods", "--packages"];
    let mut a = Args { positional: Vec::new(), flags: Default::default(), switches: Default::default() };
    let mut it = argv.into_iter();
    while let Some(x) = it.next() {
        let lower = x.to_ascii_lowercase();
        if VALUED.contains(&lower.as_str()) {
            a.flags.insert(lower, it.next().unwrap_or_default());
        } else if lower.starts_with("--") {
            a.switches.insert(lower);
        } else {
            a.positional.push(x);
        }
    }
    a
}

fn print<T: serde::Serialize + std::fmt::Debug>(json: bool, value: &T, text: impl FnOnce(&T) -> String) {
    if json {
        println!("{}", serde_json::to_string_pretty(value).unwrap_or_default());
    } else {
        println!("{}", text(value));
    }
}

fn run() -> Result<i32, String> {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    if argv.is_empty() || argv[0] == "--help" || argv[0] == "-h" {
        println!("{USAGE}");
        return Ok(0);
    }
    let a = parse(argv);
    let json = a.switches.contains("--json");
    let force = a.switches.contains("--force");
    let pos = |i: usize, what: &str| a.positional.get(i).cloned().ok_or_else(|| format!("missing {what}\n\n{USAGE}"));
    let flag = |name: &str| a.flags.get(name).filter(|v| !v.is_empty()).map(PathBuf::from);
    match pos(0, "command")?.as_str() {
        "pack" => {
            let opt = PackOptions { dll: flag("--dll"), out: flag("--out"), skip_dll_check: false, skip_pak_check: a.switches.contains("--skip-pak-check") };
            let r = pack(&PathBuf::from(pos(1, "mod folder")?), &opt)?;
            print(json, &r, |r| {
                let mut s = format!("{} {} -> {} (sha256 {}, {} files", r.id, r.version, r.package, r.sha256, r.files.len());
                if let Some(rustc) = &r.rustc {
                    s += &format!(", built with {rustc}");
                }
                s += ")";
                for w in &r.warnings {
                    s += &format!("\nwarning: {w}");
                }
                s
            });
            Ok(0)
        }
        "install" => {
            let to = flag("--to").ok_or("install needs --to <Mods>")?;
            let packages: Vec<PathBuf> = a.positional[1..].iter().map(PathBuf::from).collect();
            if packages.is_empty() {
                return Err("install needs at least one .okmod".into());
            }
            let out = install(&packages, &to, &InstallOptions { force, profile: None })?;
            let refused = out.iter().any(|o| o.result == "refused");
            print(json, &out, |out| out.iter().map(|o| format!("{} {}: {}{}", o.id, o.version, o.result, o.detail.as_deref().map(|d| format!(" ({d})")).unwrap_or_default())).collect::<Vec<_>>().join("\n"));
            Ok(if refused { 1 } else { 0 })
        }
        "verify" => {
            let r = verify(&PathBuf::from(pos(1, "Mods folder")?), a.switches.contains("--dry-run"))?;
            print(json, &r, |r| {
                let mut s = format!("Mods: {}", r.mods_dir);
                for l in &r.retired {
                    s += &format!("\nretired: {l}");
                }
                for (m, p) in &r.problems {
                    s += &format!("\nproblem: {m}: {p}");
                }
                for (mode, ids) in &r.loads {
                    s += &format!("\n{mode}: {}", if ids.is_empty() { "(none)".to_string() } else { ids.join(", ") });
                    for (id, why) in &r.rejected[mode] {
                        s += &format!("\n  {id} not loaded: {why}");
                    }
                }
                s += if r.ok() { "\nOK" } else { "\nPROBLEMS" };
                s
            });
            Ok(if r.ok() { 0 } else { 1 })
        }
        "profile" => match pos(1, "profile save|apply")?.as_str() {
            "save" => {
                let mods = flag("--mods").ok_or("profile save needs --mods <Mods>")?;
                let path = profile_save(&mods, &pos(2, "profile name")?, flag("--out").as_deref())?;
                print(json, &path.display().to_string(), |p| format!("profile written: {p}"));
                Ok(0)
            }
            "apply" => {
                let mods = flag("--mods").ok_or("profile apply needs --mods <Mods>")?;
                let packages = flag("--packages").ok_or("profile apply needs --packages <folder>")?;
                let out = profile_apply(&PathBuf::from(pos(2, "profile file")?), &mods, &packages, &InstallOptions { force, profile: None })?;
                let refused = out.iter().any(|o| o.result == "refused");
                print(json, &out, |out| out.iter().map(|o| format!("{} {}: {}{}", o.id, o.version, o.result, o.detail.as_deref().map(|d| format!(" ({d})")).unwrap_or_default())).collect::<Vec<_>>().join("\n"));
                Ok(if refused { 1 } else { 0 })
            }
            other => Err(format!("unknown profile command {other}\n\n{USAGE}")),
        },
        other => Err(format!("unknown command {other}\n\n{USAGE}")),
    }
}

fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(e) => {
            eprintln!("ok-mod-pack: {e}");
            std::process::exit(2);
        }
    }
}
