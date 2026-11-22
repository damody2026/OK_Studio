// Records the compiler that builds the mod (BuildInfo::rustc_version). The SDK is compiled by the
// same rustc as the mod that depends on it.
use std::process::Command;

fn main() {
    let rustc = std::env::var("RUSTC").unwrap_or_else(|_| "rustc".into());
    let version = Command::new(&rustc)
        .arg("--version")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "rustc (unknown)".into());
    println!("cargo:rustc-env=OK_MOD_SDK_RUSTC={version}");
    println!("cargo:rerun-if-env-changed=RUSTC");
}
