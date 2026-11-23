//! `ok-mod-pack new`: a new mod folder that builds and packs as it is (Docs/OK_MOD_AUTHORING.md).
//!
//! Writes `Cargo.toml` (a cdylib on the SDK, `panic = "unwind"`), `mod.toml`, `src/lib.rs` (a config entry, a console
//! command, a hotkey and state kept across a development hot reload) and `locale/en`, `locale/zh-CN` with every text
//! id the code names. Outside the ok-mod workspace the crate is its own workspace (so a parent workspace does not take
//! it in) and carries the unwind profiles itself; inside, the workspace's profiles apply and the answer says which
//! `members` line to add.

use std::path::{Component, Path, PathBuf};

use serde::Serialize;

use crate::Result;

#[derive(Clone, Debug, Default)]
pub struct NewOptions {
    /// Shown name; default: the id's last part, capitalised.
    pub name: Option<String>,
    /// The SDK crate (`Tools/ok-mod/sdk`); default: the one this tool was built from.
    pub sdk: Option<PathBuf>,
    pub author: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct NewReport {
    pub id: String,
    pub dir: String,
    pub crate_name: String,
    pub dll: String,
    pub files: Vec<String>,
    /// Set when the folder is inside the ok-mod workspace: the `members` entry to add to its Cargo.toml.
    pub workspace_member: Option<String>,
}

/// The ok-mod workspace this tool was built in.
fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).parent().map(Path::to_path_buf).unwrap_or_default()
}

/// `org.example.my-mod` style: two or more parts of lower-case letters, digits and `-`, each starting with a letter.
pub fn check_id(id: &str) -> Result<()> {
    let parts: Vec<&str> = id.split('.').collect();
    let ok = parts.len() >= 2
        && parts.iter().all(|p| {
            p.chars().next().is_some_and(|c| c.is_ascii_lowercase())
                && p.chars().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
                && !p.ends_with('-')
        });
    if ok {
        Ok(())
    } else {
        Err(format!("mod id {id:?}: use reverse-domain parts of a-z, 0-9 and '-' (org.example.my-mod)"))
    }
}

fn absolute(p: &Path) -> PathBuf {
    let p = if p.is_absolute() { p.to_path_buf() } else { std::env::current_dir().unwrap_or_default().join(p) };
    let mut out = PathBuf::new();
    for c in p.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

/// `to` relative to `from` (both absolute), with `/`; the absolute path when they are on different drives.
fn relative(from: &Path, to: &Path) -> String {
    let (f, t): (Vec<_>, Vec<_>) = (from.components().collect(), to.components().collect());
    let lower = |c: &Component| c.as_os_str().to_string_lossy().to_ascii_lowercase();
    if f.first().map(lower) != t.first().map(lower) {
        return to.to_string_lossy().replace('\\', "/");
    }
    let common = f.iter().zip(&t).take_while(|(a, b)| lower(a) == lower(b)).count();
    let mut parts: Vec<String> = std::iter::repeat("..".to_string()).take(f.len() - common).collect();
    parts.extend(t[common..].iter().map(|c| c.as_os_str().to_string_lossy().into_owned()));
    if parts.is_empty() {
        ".".into()
    } else {
        parts.join("/")
    }
}

fn inside(dir: &Path, root: &Path) -> bool {
    let lower = |p: &Path| p.to_string_lossy().replace('\\', "/").to_ascii_lowercase();
    let (d, r) = (lower(dir), lower(root));
    d.starts_with(&format!("{}/", r.trim_end_matches('/')))
}

/// A TOML basic string.
fn q(s: &str) -> String {
    toml::Value::String(s.to_string()).to_string()
}

/// Writes a new mod `id` into `dir` (which must not exist or be empty).
pub fn new_mod(dir: &Path, id: &str, opt: &NewOptions) -> Result<NewReport> {
    check_id(id)?;
    let dir = absolute(dir);
    if dir.exists() && std::fs::read_dir(&dir).map_err(|e| format!("{}: {e}", dir.display()))?.next().is_some() {
        return Err(format!("{} is not empty", dir.display()));
    }
    let short = id.rsplit('.').next().unwrap_or(id);
    let snake = short.replace('-', "_");
    let type_name: String = short
        .split('-')
        .map(|w| {
            let mut c = w.chars();
            c.next().map(|f| f.to_ascii_uppercase().to_string() + c.as_str()).unwrap_or_default()
        })
        .collect();
    let type_name = if type_name.chars().next().is_some_and(|c| c.is_ascii_digit()) { format!("Mod{type_name}") } else { type_name };
    let name = opt.name.clone().unwrap_or_else(|| short.split('-').collect::<Vec<_>>().join(" ")).trim().to_string();
    let name = if opt.name.is_some() {
        name
    } else {
        let mut c = name.chars();
        c.next().map(|f| f.to_ascii_uppercase().to_string() + c.as_str()).unwrap_or_default()
    };
    let crate_name = format!("ok-mod-{short}");
    let lib = format!("ok_{snake}");
    let dll = format!("{lib}.dll");
    let author = opt.author.clone().unwrap_or_default();

    let root = workspace_root();
    let sdk = absolute(&opt.sdk.clone().unwrap_or_else(|| root.join("sdk")));
    if !sdk.join("Cargo.toml").is_file() {
        return Err(format!("no SDK crate at {} (give --sdk <Tools/ok-mod/sdk>)", sdk.display()));
    }
    let member = inside(&dir, &root).then(|| relative(&root, &dir));

    let mut cargo = format!(
        "[package]\nname = {}\nversion = \"0.1.0\"\nedition = \"2021\"\ndescription = {}\npublish = false\n\n[lib]\nname = {}\ncrate-type = [\"cdylib\"]\n\n[dependencies]\nok-mod-sdk = {{ path = {} }}\n",
        q(&crate_name),
        q(&format!("OK mod {id}")),
        q(&lib),
        q(&relative(&dir, &sdk)),
    );
    if member.is_none() {
        cargo += "\n# Its own workspace: a parent workspace must not take it in (and its profiles would not apply).\n[workspace]\n\n\
# Mods must unwind: the SDK turns a panic into an error and the host turns the mod off; with \"abort\" a panic\n\
# takes the game down (ok-mod-pack pack refuses such a DLL).\n[profile.dev]\npanic = \"unwind\"\n\n[profile.release]\npanic = \"unwind\"\n";
    }

    let manifest = format!(
        "id = {}\nname = {}\nversion = \"0.1.0\"\napi = \"0.1\"\ndll = {}\nauthors = [{}]\ndescription_id = {}\n\
# Where it loads: reader (card reader), studio (OK Studio), pair (1-on-1), street, extract (opening cards).\n\
targets = [\"reader\", \"studio\", \"pair\", \"street\"]\n\
# feature, tool, content, ui, fix\ncategory = \"feature\"\n",
        q(id),
        q(&name),
        q(&dll),
        if author.is_empty() { String::new() } else { q(&author) },
        q(&format!("mod.{id}.description")),
    );

    let lib_rs = TEMPLATE.replace("{id}", id).replace("{name}", &name).replace("{Type}", &type_name);

    let t = |k: &str| format!("mod.{id}.{k}");
    let locale_en = format!(
        "{} = {}\n{} = {}\n{} = {}\n{} = {}\n",
        q(&t("description")),
        q(&format!("{name}: made from the ok-mod-pack template.")),
        q(&t("config.greeting")),
        q("Greeting the hello command and hotkey answer with"),
        q(&t("config.hello")),
        q("Hotkey: say hello"),
        q(&t("cmd.hello")),
        q("Says hello and how many times it has"),
    );
    let locale_cn = format!(
        "{} = {}\n{} = {}\n{} = {}\n{} = {}\n",
        q(&t("description")),
        q(&format!("{name}：由 ok-mod-pack 范本产生。")),
        q(&t("config.greeting")),
        q("hello 指令与热键回答的问候语"),
        q(&t("config.hello")),
        q("热键：打招呼"),
        q(&t("cmd.hello")),
        q("打招呼，并说已经打了几次"),
    );

    let files: Vec<(String, String)> = vec![
        ("Cargo.toml".into(), cargo),
        ("mod.toml".into(), manifest),
        ("src/lib.rs".into(), lib_rs),
        (format!("locale/en/{short}.toml"), locale_en),
        (format!("locale/zh-CN/{short}.toml"), locale_cn),
    ];
    for (rel, text) in &files {
        let path = dir.join(rel);
        if let Some(p) = path.parent() {
            std::fs::create_dir_all(p).map_err(|e| format!("{}: {e}", p.display()))?;
        }
        std::fs::write(&path, text).map_err(|e| format!("{}: {e}", path.display()))?;
    }
    Ok(NewReport {
        id: id.to_string(),
        dir: dir.display().to_string(),
        crate_name,
        dll,
        files: files.into_iter().map(|(r, _)| r).collect(),
        workspace_member: member,
    })
}

const TEMPLATE: &str = r#"//! {name} (`{id}`), made by `ok-mod-pack new`; Docs/OK_MOD_AUTHORING.md explains each part.
//!
//! - a config entry `greeting` (the reader's Mods page shows it);
//! - the console command `mod.{id}.hello` (also `mod_call` on the control channel);
//! - a hotkey `hello`, unbound until the player binds it (Mods › hotkeys, or `OKMod.Bind {id} hello F7`);
//! - its count survives a development-mode hot reload (`-ModDev`, console `mod.reload {id}`).

use ok_mod_sdk::prelude::*;

struct {Type} {
    host: Host,
    count: u64,
}

impl {Type} {
    fn hello(&mut self, from: &str) -> String {
        self.count += 1;
        let greeting = self.host.config_text("greeting").unwrap_or_default();
        format!("{greeting} #{} ({from})", self.count)
    }
}

impl Mod for {Type} {
    fn create(host: Host) -> ModResult<Self> {
        Ok({Type} { host, count: 0 })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        reg.config_text("greeting", "hello", "mod.{id}.config.greeting")
            .command("hello", "mod.{id}.cmd.hello")
            .hotkey("hello", "", "mod.{id}.config.hello")
            .keep_state()
            .subscribe("mode_enter");
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        match event {
            Event::Enabled => self.host.info("enabled"),
            Event::ModeEnter { mode } => self.host.info(format!("entered {mode}")),
            Event::Command { name, .. } if name.as_str() == "hello" => return Ok(Reply::Text(self.hello("console").into())),
            Event::Command { name, .. } => return Err(format!("unknown command {name}")),
            Event::Hook { name, payload } if hooks::hotkey(name.as_str()) == Some("hello") => {
                let key: hooks::KeyPress = hooks::parse(payload)?;
                return Ok(Reply::Text(self.hello(&key.mode).into()));
            }
            Event::Hook { name, .. } if name.as_str() == hooks::SAVE_STATE => return hooks::json(&self.count),
            Event::Hook { name, payload } if name.as_str() == hooks::RESTORE_STATE => {
                self.count = hooks::parse::<hooks::RestoreState<u64>>(payload)?.state;
            }
            _ => {}
        }
        Ok(Reply::None)
    }
}

ok_mod!({Type});
"#;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_and_paths() {
        assert!(check_id("org.example.my-mod").is_ok());
        assert!(check_id("mymod").is_err());
        assert!(check_id("org.Example.x").is_err());
        assert!(check_id("org.example.1x").is_err());
        assert_eq!(relative(Path::new("C:/a/b/c"), Path::new("C:/a/sdk")), "../../sdk");
        assert_eq!(relative(Path::new("C:/a"), Path::new("D:/sdk")), "D:/sdk");
        assert!(inside(Path::new("F:/x/ok-mod/examples/m"), Path::new("F:/x/ok-mod")));
        assert!(!inside(Path::new("F:/x/ok-mod-other/m"), Path::new("F:/x/ok-mod")));
    }
}
