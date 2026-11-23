//! Starting and stopping the card reader (CardReaderDevelopment.cmd / Tools/run_card_reader_development.lua): in this
//! checkout (the editor build, UnrealEditor -game) or in a package directory (its staged OpenKoikatsu.exe), and waiting
//! until its control channels answer, so no caller polls for it. A lane (-OKLane=<lane> on the reader's command line)
//! names a reader for reader_stop among several sessions' readers.
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub fn tools() -> Vec<Value> {
    let t = |name: &str, description: &str, properties: Value, required: &[&str]| {
        json!({"name": name, "description": description, "inputSchema": {"type": "object", "properties": properties, "required": required}})
    };
    vec![
        t("reader_launch", "Start the card reader (Tools/run_card_reader_development.lua, what CardReaderDevelopment.cmd runs) and wait until its control channels answer (its UI channel and card reader mailbox in Saved/OKControl), then make it the game the tools act on. root: a package directory to run its staged OpenKoikatsu.exe (default this checkout: the editor build, rebuilt first when stale unless no_build). card: a PNG to open; card_directory: the cards listed. lane: put -OKLane=<lane> on its command line (reader_stop finds it by that). extra: more arguments for the game itself (after --), e.g. [\"-LegacyReader\"] (the old UMG gallery; the DreamGUI screen is the default). env: environment variables for it. Returns pid, log, lane, seconds waited.",
          json!({"root": {"type": "string"}, "card": {"type": "string"}, "card_directory": {"type": "string"}, "lane": {"type": "string"}, "extra": {"type": "array", "items": {"type": "string"}}, "env": {"type": "object", "additionalProperties": {"type": "string"}}, "no_build": {"type": "boolean"}, "width": {"type": "integer"}, "height": {"type": "integer"}, "timeout_s": {"type": "number"}}), &[]),
        t("reader_stop", "Stop card readers: by pid, or by lane (every game process whose command line has -OKLane=<lane>). Ends each process with Win32_Process.Terminate (taskkill can report success and leave it running) and waits until it is gone. Only game processes (UnrealEditor, OpenKoikatsu) are stopped.",
          json!({"pid": {"type": "integer"}, "lane": {"type": "string"}, "timeout_s": {"type": "number"}}), &[]),
    ]
}

/// A number that differs between calls in one process (the launcher output file's name).
fn rand_tag() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static N: AtomicU64 = AtomicU64::new(0);
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos() as u64).unwrap_or(0) ^ N.fetch_add(1, Ordering::Relaxed)
}

pub(crate) fn powershell(script: &str) -> Result<String> {
    let out = Command::new("powershell").args(["-NoProfile", "-NonInteractive", "-Command", script]).output().context("could not run powershell")?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

/// Game processes (pid, command line) whose command line carries -OKLane=<lane> as a whole argument.
fn lane_pids(lane: &str) -> Result<Vec<u32>> {
    let script = "Get-CimInstance Win32_Process | Where-Object { ($_.Name -like 'UnrealEditor*' -or $_.Name -like 'OpenKoikatsu*') -and $_.CommandLine } | ForEach-Object { [string]$_.ProcessId + \"`t\" + $_.CommandLine }";
    let marker = format!("-OKLane={lane}");
    Ok(powershell(script)?
        .lines()
        .filter_map(|l| {
            let (pid, cmd) = l.split_once('\t')?;
            cmd.split_whitespace().any(|a| a.trim_matches('"') == marker).then(|| pid.trim().parse().ok())?
        })
        .collect())
}

/// Whether the pid is a running game process (and not whatever Windows gave a dead game's pid to).
fn is_game(pid: u32) -> Result<bool> {
    let name = powershell(&format!("(Get-CimInstance Win32_Process -Filter \"ProcessId={pid}\").Name"))?.to_ascii_lowercase();
    Ok(name.starts_with("unrealeditor") || name.starts_with("openkoikatsu"))
}

pub(crate) fn alive(pid: u32) -> bool {
    powershell(&format!("[bool](Get-Process -Id {pid} -ErrorAction SilentlyContinue)")).is_ok_and(|s| s.eq_ignore_ascii_case("true"))
}

pub fn launch(checkout: &Path, a: &Value) -> Result<Value> {
    let root: PathBuf = match a["root"].as_str().filter(|s| !s.is_empty()) {
        Some(r) => PathBuf::from(r),
        None => checkout.to_path_buf(),
    };
    let lua = root.join("Tools/lua/lua.exe");
    let script = root.join("Tools/run_card_reader_development.lua");
    if !lua.is_file() || !script.is_file() {
        bail!("{} has no Tools/run_card_reader_development.lua (a checkout or a card reader package is needed)", root.display());
    }
    let lane = a["lane"].as_str().filter(|s| !s.is_empty()).map(String::from);
    if let Some(l) = &lane {
        if l.chars().any(|c| c.is_whitespace() || c == '"') {
            bail!("lane must be one word");
        }
        let running = lane_pids(l)?;
        if !running.is_empty() {
            bail!("a reader with lane {l} already runs (pid {running:?}); reader_stop it first or pick another lane");
        }
    }
    let mut cmd = Command::new(&lua);
    cmd.arg(&script);
    if let Some(card) = a["card"].as_str().filter(|s| !s.is_empty()) {
        cmd.arg(card);
    }
    if let Some(dir) = a["card_directory"].as_str() {
        cmd.args(["-CardDirectory", dir]);
    }
    if a["no_build"] == true {
        cmd.arg("-NoBuild");
    }
    if let Some(w) = a["width"].as_u64() {
        cmd.args(["-WindowWidth", &w.to_string()]);
    }
    if let Some(h) = a["height"].as_u64() {
        cmd.args(["-WindowHeight", &h.to_string()]);
    }
    let extra: Vec<String> = a["extra"].as_array().into_iter().flatten().filter_map(|x| x.as_str().map(String::from)).collect();
    if lane.is_some() || !extra.is_empty() {
        cmd.arg("--");
        if let Some(l) = &lane {
            cmd.arg(format!("-OKLane={l}"));
        }
        cmd.args(&extra);
    }
    if let Some(env) = a["env"].as_object() {
        for (k, v) in env {
            cmd.env(k, v.as_str().map(String::from).unwrap_or_else(|| v.to_string()));
        }
    }
    // The launcher spawns the game and exits; it says the pid and the log on stdout (and may build the editor first). Its
    // output goes to a file, not a pipe: the game and its TTS server inherit the launcher's handles, and a pipe stayed
    // open until they exited -- the call never returned while the reader ran (2026-11-18).
    let launch_dir = root.join("Saved/OKControl/launch");
    std::fs::create_dir_all(&launch_dir)?;
    let out_file = launch_dir.join(format!("reader-{}-{}.txt", std::process::id(), rand_tag()));
    let out = std::fs::File::create(&out_file)?;
    cmd.current_dir(&root).stdin(Stdio::null()).stdout(Stdio::from(out.try_clone()?)).stderr(Stdio::from(out));
    let status = cmd.spawn().context("could not run the card reader launcher")?.wait()?;
    let stdout = std::fs::read_to_string(&out_file).unwrap_or_default();
    let _ = std::fs::remove_file(&out_file);
    let pid: u32 = stdout
        .lines()
        .find_map(|l| l.split("PID=").nth(1)?.trim().parse().ok())
        .with_context(|| format!("the launcher did not start a reader (exit {status}):\n{}", stdout.trim()))?;
    let log = stdout.lines().find_map(|l| l.strip_prefix("Log: ").map(|s| s.trim().to_string())).unwrap_or_default();
    // Ready: the reader registered its channels (Saved/OKControl/<pid>.json, under the root it runs from) with the UI
    // channel and the card reader mailbox.
    let timeout = Duration::from_secs_f64(a["timeout_s"].as_f64().unwrap_or_else(|| crate::watchdog::secs("launch", 300.0)));
    let start = Instant::now();
    loop {
        let ready = crate::control::instances(&root)
            .into_iter()
            .find(|v| v["pid"].as_u64() == Some(pid.into()))
            .filter(|v| v["port_ui"].is_string() && v["mailbox"].is_string());
        if let Some(v) = ready {
            if root == checkout {
                crate::control::set_own(pid);
            }
            return Ok(json!({"pid": pid, "log": log, "lane": lane, "root": root.display().to_string(), "seconds": start.elapsed().as_secs_f64(), "instance": v,
                "note": if root == checkout { "the tools act on this reader now" } else { "a package's reader: its channels are under its own root; ui_* and reader_call need OK_GAME_PID / an MCP started there" }}));
        }
        if !alive(pid) {
            bail!("the reader (pid {pid}) exited before its channels came up; see its log {log}");
        }
        if start.elapsed() > timeout {
            // It started but never came up (a hang during load, a GPU device hang): end it rather than leave it
            // sitting there, and say so. Only this pid, which we started ourselves (watchdog.rs).
            bail!("the reader (pid {pid}) runs but its channels did not come up within {:.0} s; see its log {log}
{}",
                timeout.as_secs_f64(),
                crate::watchdog::launch_timed_out(&root, pid, timeout.as_secs_f64(), "the card reader"));
        }
        std::thread::sleep(Duration::from_millis(500));
    }
}

pub fn stop(a: &Value) -> Result<Value> {
    let mut pids: Vec<u32> = Vec::new();
    if let Some(pid) = a["pid"].as_u64() {
        let pid = pid as u32;
        if !is_game(pid)? {
            bail!("pid {pid} is not a running game process (UnrealEditor / OpenKoikatsu)");
        }
        pids.push(pid);
    }
    if let Some(lane) = a["lane"].as_str().filter(|s| !s.is_empty()) {
        pids.extend(lane_pids(lane)?);
    }
    if pids.is_empty() {
        if a["pid"].is_null() && a["lane"].is_null() {
            bail!("pid or lane is required");
        }
        return Ok(json!({"stopped": [], "note": "no reader with that lane runs"}));
    }
    pids.sort_unstable();
    pids.dedup();
    let list = pids.iter().map(u32::to_string).collect::<Vec<_>>().join(",");
    powershell(&format!(
        "foreach ($p in @({list})) {{ Get-CimInstance Win32_Process -Filter \"ProcessId=$p\" | Invoke-CimMethod -MethodName Terminate | Out-Null }}"
    ))?;
    let timeout = Duration::from_secs_f64(a["timeout_s"].as_f64().unwrap_or(20.0));
    let start = Instant::now();
    loop {
        let left: Vec<u32> = pids.iter().copied().filter(|p| alive(*p)).collect();
        if left.is_empty() {
            return Ok(json!({"stopped": pids, "seconds": start.elapsed().as_secs_f64()}));
        }
        if start.elapsed() > timeout {
            bail!("still running after Terminate: {left:?}");
        }
        std::thread::sleep(Duration::from_millis(300));
    }
}
