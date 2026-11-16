//! Every mode's control channels, always open (Docs/GAME_CONTROL_CHANNELS.md): each running game writes
//! Saved/OKControl/<pid>.json with its ports and mailbox. game_instances lists them, game_select picks which one the tools
//! act on. ui_* speak to any mode's UI channel, reader_call to the card reader's mailbox, pair_call to the 1-on-1 scene.
use crate::game::{http, http_text};
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::path::Path;
use std::process::Command;
use std::cell::Cell;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

static SELECTED: AtomicU32 = AtomicU32::new(0);
/// The game this server started (game_launch): with nothing selected the tools act on it, not on the newest game of the
/// checkout. The newest was another session's sandbox game, and that session's game_stop closed it (2026-11-08, the
/// conquest game's "silent ends" at 00:24, 01:15 and 19:04: the window closed, no error in the log).
static OWN: AtomicU32 = AtomicU32::new(0);
static LAST_ID: AtomicU64 = AtomicU64::new(0);

/// Starting a game makes it the one the tools act on: a pid selected before (game_select) is dropped with it. Kept, the
/// launch waited on the selected game, closed for the restart, and timed out after half an hour (R6-188).
pub fn set_own(pid: u32) {
    OWN.store(pid, Ordering::Relaxed);
    SELECTED.store(0, Ordering::Relaxed);
}

/// This server's own game, when it started one that still runs and has written its channels.
pub fn own_ready(root: &Path) -> bool {
    let own = OWN.load(Ordering::Relaxed);
    own != 0 && instances(root).iter().any(|v| v["pid"].as_u64() == Some(own.into()) && v["port_street"].is_string())
}

/// Whether the game the tools act on now is one this server may stop: selected (game_select), or started here.
pub fn may_stop(root: &Path) -> bool {
    SELECTED.load(Ordering::Relaxed) != 0 || own_ready(root)
}

/// The pids alive now.
fn live_pids() -> Vec<u32> {
    let Ok(out) = Command::new("tasklist").args(["/NH", "/FO", "CSV"]).output() else { return Vec::new() };
    String::from_utf8_lossy(&out.stdout).lines().filter_map(|l| l.split("\",\"").nth(1)?.parse().ok()).collect()
}

/// The running games of this checkout, oldest first.
pub fn instances(root: &Path) -> Vec<Value> {
    let Ok(dir) = std::fs::read_dir(root.join("Saved/OKControl")) else { return Vec::new() };
    let live = live_pids();
    let mut found: Vec<Value> = dir
        .flatten()
        .filter(|e| e.path().extension().is_some_and(|x| x == "json"))
        .filter_map(|e| serde_json::from_str::<Value>(std::fs::read_to_string(e.path()).ok()?.trim_start_matches('\u{feff}')).ok())
        .filter(|v| v["pid"].as_u64().is_some_and(|p| live.contains(&(p as u32))))
        .collect();
    found.sort_by_key(|v| v["started"].as_i64().unwrap_or(0));
    found
}

thread_local! {
    /// Whether the tool call running on this thread changes a game (load, set, press, key...) rather than only reads it.
    static CALL_MUTATES: Cell<bool> = const { Cell::new(false) };
    /// The game the call went to when nothing picked it (game_select, OK_GAME_PID, game_launch): shown in the reply.
    static DEFAULT_TARGET: Cell<u32> = const { Cell::new(0) };
}

/// Marks the call about to run on this thread; returns nothing to undo (every call sets it first).
pub fn begin_call(mutates: bool) {
    CALL_MUTATES.with(|c| c.set(mutates));
    DEFAULT_TARGET.with(|c| c.set(0));
}

/// The pid the last call on this thread went to by default (nothing selected), or 0.
pub fn default_target() -> u32 {
    DEFAULT_TARGET.with(Cell::get)
}

/// Whether a tool call changes the game it goes to. Reads may go to the newest game when several run; changes may not
/// (2026-11-16: reader_call load with nothing selected opened a card in another session's card reader).
pub fn mutates(name: &str, a: &Value) -> bool {
    match name {
        "game_instances" | "game_select" | "game_launch" | "game_stop" | "image_stats" => false,
        "game_state" | "game_buttons" | "game_screenshot" | "game_log" => false,
        "ui_state" | "ui_widgets" | "ui_screenshot" => false,
        "reader_call" => !matches!(a["action"].as_str().unwrap_or(""), "state" | "cards" | "parameters" | "get" | "controls" | "views" | "measure" | "catalog" | "screenshot" | "snapshot"),
        "pair_call" => !a["path"].as_str().is_some_and(|p| p.starts_with("/stats") || p.starts_with("/pose")),
        "studio_launch" => false,
        "studio_state" | "studio_inspect" | "studio_scenes" | "studio_catalog" | "studio_catalog_search" | "studio_bones" | "studio_bounds"
        | "studio_report" | "studio_capture" | "studio_ui_shot" => false,
        _ => true,
    }
}

/// This process's Claude session: the nearest claude.exe above it, "pid yyyyMMddHHmmss" (as Tools/ok_instance.lua
/// record_launch writes it), or None outside a session.
fn my_session() -> Option<&'static str> {
    static SESSION: OnceLock<Option<String>> = OnceLock::new();
    SESSION
        .get_or_init(|| {
            let script = format!(
                "$p = Get-CimInstance Win32_Process -Filter \"ProcessId={}\"; for ($i = 0; $i -lt 16 -and $p; $i++) {{ $p = Get-CimInstance Win32_Process -Filter \"ProcessId=$($p.ParentProcessId)\"; if ($p -and $p.Name -eq 'claude.exe') {{ '' + $p.ProcessId + ' ' + $p.CreationDate.ToString('yyyyMMddHHmmss'); break }} }}",
                std::process::id()
            );
            let out = Command::new("powershell").args(["-NoProfile", "-Command", &script]).output().ok()?;
            let text = String::from_utf8_lossy(&out.stdout).trim().to_string();
            (!text.is_empty()).then_some(text)
        })
        .as_deref()
}

/// Whether this session started the game: game_launch here, or CardReaderDevelopment.cmd / SceneEditor.cmd /
/// studio_launch run from this Claude session (their launchers record it under Saved/OKControl/launched).
fn is_mine(root: &Path, pid: u64) -> bool {
    if pid == u64::from(OWN.load(Ordering::Relaxed)) && pid != 0 {
        return true;
    }
    let Some(me) = my_session() else { return false };
    std::fs::read_to_string(root.join("Saved/OKControl/launched").join(format!("{pid}.json")))
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(t.trim_start_matches('\u{feff}')).ok())
        .is_some_and(|v| v["session"].as_str() == Some(me))
}

/// The games listed for a caller that has to pick one.
fn listing(all: &[Value]) -> String {
    all.iter()
        .map(|v| format!("pid {} ({} {})", v["pid"], v["game_mode"].as_str().or(v["mode"].as_str()).unwrap_or("?"), v["map"].as_str().unwrap_or("?")))
        .collect::<Vec<_>>()
        .join(", ")
}

/// The game the tools act on for this value: the selected one (game_select, OK_GAME_PID), else this session's own, else
/// the only one that has it. With several and none picked, a change is refused (listing them); a read goes to the newest
/// and the reply says which pid answered.
fn target(root: &Path, key: &str) -> Result<Option<Value>> {
    let all = instances(root);
    // OK_GAME_PID picks the game as game_select does, for `ok-game-mcp call` (a process per call keeps no selection).
    let env_pid = std::env::var("OK_GAME_PID").ok().and_then(|p| p.trim().parse::<u32>().ok()).unwrap_or(0);
    let selected = if env_pid != 0 { env_pid } else { SELECTED.load(Ordering::Relaxed) };
    if selected != 0 {
        return Ok(all.into_iter().find(|v| v["pid"].as_u64() == Some(selected.into())));
    }
    let own = OWN.load(Ordering::Relaxed);
    if own != 0 {
        if let Some(v) = all.iter().find(|v| v["pid"].as_u64() == Some(own.into())) {
            return Ok(v[key].is_string().then(|| v.clone()));
        }
    }
    let with: Vec<Value> = all.into_iter().filter(|v| v[key].is_string()).collect();
    let mine: Vec<Value> = with.iter().filter(|v| v["pid"].as_u64().is_some_and(|p| is_mine(root, p))).cloned().collect();
    let pool = if mine.is_empty() { &with } else { &mine };
    if pool.len() > 1 && CALL_MUTATES.with(Cell::get) {
        bail!(
            "{} games run and none is picked for a change: game_select one (or OK_GAME_PID for ok-game-mcp call): {}",
            pool.len(),
            listing(pool)
        );
    }
    let chosen = pool.last().cloned();
    if let Some(pid) = chosen.as_ref().and_then(|v| v["pid"].as_u64()) {
        DEFAULT_TARGET.with(|c| c.set(pid as u32));
    }
    Ok(chosen)
}

/// The channel's port in the running game (the registry writes values as text), else the default.
pub fn port(root: &Path, channel: &str, default: u16) -> Result<u16> {
    let key = format!("port_{channel}");
    Ok(target(root, &key)?.and_then(|v| v[&key].as_str()?.parse().ok()).unwrap_or(default))
}

fn base(root: &Path) -> u16 {
    std::fs::read_to_string(root.join("local-instance.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(t.trim_start_matches('\u{feff}')).ok())
        .and_then(|v| v["port_base"].as_u64())
        .unwrap_or(47860) as u16
}

fn ui(root: &Path, path: &str, body: Option<&Value>) -> Result<Value> {
    let port = port(root, "ui", base(root) + 12)?;
    let r = http(port, path, body, Duration::from_secs(60), || format!("no game answers on the UI channel 127.0.0.1:{port} (game_instances lists what runs)"))?;
    if r["ok"] == false {
        bail!("{}", r["error"].as_str().unwrap_or("failed"));
    }
    Ok(r)
}

/// One request through the card reader's mailbox; the reply's result. Edits need the session and revision of now: they are
/// read first when not given.
fn reader(root: &Path, a: &Value) -> Result<Value> {
    let action = a["action"].as_str().context("action is required")?;
    let mailbox = target(root, "mailbox")?.and_then(|v| v["mailbox"].as_str().map(String::from)).context("no running game has a card reader mailbox (game_instances)")?;
    let mut body = a.clone();
    if action != "state" && body["session"].is_null() {
        let state = mailbox_call(Path::new(&mailbox), &json!({"action": "state"}), 10.)?;
        body["session"] = state["session"].clone();
        if body["revision"].is_null() {
            body["revision"] = state["revision"].clone();
        }
    }
    let timeout = a["timeout_s"].as_f64().unwrap_or(if action == "state" { 10. } else { 120. });
    mailbox_call(Path::new(&mailbox), &body, timeout)
}

fn mailbox_call(root: &Path, body: &Value, timeout: f64) -> Result<Value> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
    let id = format!("{:032x}", now.as_nanos() + u128::from(LAST_ID.fetch_add(1, Ordering::Relaxed)));
    let name = format!("{id}.json");
    let mut payload = body.clone();
    payload["deadline"] = (now.as_secs_f64() + timeout).into();
    let request = root.join("requests").join(&name);
    let temp = root.join("requests").join(format!("{id}.tmp"));
    std::fs::write(&temp, payload.to_string())?;
    std::fs::rename(&temp, &request)?;
    let response = root.join("responses").join(&name);
    let start = Instant::now();
    while start.elapsed().as_secs_f64() < timeout {
        if let Ok(text) = std::fs::read_to_string(&response) {
            let _ = std::fs::remove_file(&response);
            let r: Value = serde_json::from_str(&text)?;
            if r["ok"] != true {
                bail!("{}", r["error"].as_str().unwrap_or("failed"));
            }
            return Ok(r["result"].clone());
        }
        std::thread::sleep(Duration::from_millis(25));
    }
    let _ = std::fs::remove_file(&request);
    bail!("the card reader did not answer in {timeout} s")
}

pub fn tools() -> Vec<Value> {
    let t = |name: &str, description: &str, properties: Value, required: &[&str]| {
        json!({"name": name, "description": description, "inputSchema": {"type": "object", "properties": properties, "required": required}})
    };
    let which = || json!({"label": {"type": "string"}, "index": {"type": "integer", "description": "which of several with this label, from 0"}});
    let mut set = which();
    set["key"] = json!({"type": "string", "description": "a control's key from ui_widgets"});
    set["value"] = json!({"description": "number, text, true/false or one of the choices"});
    vec![
        t("game_instances", "The games running from this checkout, in any mode: pid, game mode, map, ports (port_ui, port_street, port_studio, port_pair) and the card reader's mailbox. Every mode opens its channels by itself; started by hand, it is here too.", json!({}), &[]),
        t("game_select", "Which game the tools act on when several run: a pid from game_instances; 0 goes back to the newest.", json!({"pid": {"type": "integer"}}), &["pid"]),
        t("ui_state", "Any mode: pid, map, game mode, fps, viewport, camera, and what the mode adds (the crowd room: its girls).", json!({}), &[]),
        t("ui_widgets", "Any mode: everything operable on screen now: buttons (label, index) and controls (key, label, kind, value, min, max, choices).", json!({}), &[]),
        t("ui_press", "Any mode: press the on-screen button with this label.", which(), &["label"]),
        t("ui_set", "Any mode: set a control from ui_widgets, by key or by label, the way a person's change does.", set, &["value"]),
        t("ui_key", "Any mode: press a key as the player's keyboard (W, E, Escape, ...), held for seconds.", json!({"key": {"type": "string"}, "seconds": {"type": "number"}}), &["key"]),
        t("ui_camera", "Any mode with a free camera (the crowd room): place it.", json!({"location": {"type": "array", "items": {"type": "number"}}, "rotation": {"type": "array", "items": {"type": "number"}}}), &["location", "rotation"]),
        t("ui_exec", "Any mode: run an engine console command and return what it printed.", json!({"command": {"type": "string"}}), &["command"]),
        t("ui_screenshot", "Any mode: a screenshot of the window (ui=false leaves the UI out).", json!({"ui": {"type": "boolean"}}), &[]),
        t("reader_call", "The card reader through its mailbox. action: state, cards (the card wall: offset, limit, query), select (index), load (path), parameters (query; shape.*, bone.*, physics.*, pregnancy.*, style.* and properties), get (keys), set (edits [{key, value}]), reset (keys), apply, controls, control_set (key, value), action (command), camera, screenshot, views, measure, catalog, appearance, snapshot, restore, save, studio, video_import, partner. session and revision are filled in. Docs/CHARACTER_EDITOR_MCP_USAGE.md.",
          json!({"action": {"type": "string"}, "timeout_s": {"type": "number"}}), &["action"]),
        t("pair_call", "The 1-on-1 interaction scene's channel: /stats, /reset, /exec?cmd=<url-encoded command>, /pose?filter=<text>. Returns its text.", json!({"path": {"type": "string"}}), &["path"]),
    ]
}

fn text(v: &Value) -> Value {
    json!({"content": [{"type": "text", "text": serde_json::to_string_pretty(v).unwrap_or_default()}], "isError": false})
}

pub fn run(root: &Path, name: &str, a: &Value) -> Result<Value> {
    Ok(match name {
        "game_instances" => text(&json!({"selected": SELECTED.load(Ordering::Relaxed), "instances": instances(root)})),
        "game_select" => {
            let pid = a["pid"].as_u64().context("pid is required")? as u32;
            if pid != 0 && !instances(root).iter().any(|v| v["pid"].as_u64() == Some(pid.into())) {
                bail!("no running game with pid {pid}");
            }
            SELECTED.store(pid, Ordering::Relaxed);
            text(&json!({"selected": pid}))
        }
        "ui_state" => text(&ui(root, "/state", None)?),
        "ui_widgets" => text(&ui(root, "/widgets", None)?),
        "ui_press" | "ui_set" => text(&ui(root, "/widget", Some(a))?),
        "ui_key" => text(&ui(root, "/key", Some(a))?),
        "ui_camera" => text(&ui(root, "/camera", Some(a))?),
        "ui_exec" => text(&ui(root, "/exec", Some(a))?),
        "ui_screenshot" => {
            let r = ui(root, "/screenshot", Some(a))?;
            let file = r["path"].as_str().context("no screenshot path")?.to_string();
            json!({"content": [{"type": "text", "text": file}, crate::image_part(&file)?], "isError": false})
        }
        "reader_call" => text(&reader(root, a)?),
        "pair_call" => {
            let port = port(root, "pair", base(root) + 11)?;
            let path = a["path"].as_str().context("path is required")?;
            let reply = http_text(port, path, None, Duration::from_secs(60), || format!("no 1-on-1 scene answers on 127.0.0.1:{port}"))?;
            json!({"content": [{"type": "text", "text": reply}], "isError": false})
        }
        other => bail!("unknown tool {other}"),
    })
}
