//! A hung game never answers again: wait, then end it.
//!
//! A GPU device hang (`DXGI_ERROR_DEVICE_HUNG`, seen 2026-11-19 in the card reader) leaves the process alive with its
//! render thread stuck inside the driver. Every channel keeps listening and nothing ever replies, so a tool that waits
//! "until it answers" waits for ever and a test run looks like it is still going. So every wait has a deadline, and when
//! the deadline passes on a game **this session owns**, the process is ended the only way that works on a hung game:
//! `Win32_Process.Terminate` on that one pid. A hung game cannot close politely -- the thread that would do it is the
//! one that is stuck.
//!
//! Never by window title or executable name: several sessions run their own games on one machine (and someone has
//! already killed another session's game that way). Only the pid the caller named with `OK_GAME_PID`, or one this
//! session started itself (`control::is_mine`).
//!
//! Nothing is deleted: the game's log and the Aftermath / D3D12 crash dump it wrote stay where they are, and the
//! message says where to look.
use anyhow::Result;
use std::path::Path;
use std::time::Duration;

/// A wait's deadline in seconds: `OK_MCP_TIMEOUT_<NAME>` (e.g. `OK_MCP_TIMEOUT_CALL`), else `OK_MCP_TIMEOUT`, else the
/// default. 0 or less means "no deadline" and is honoured as such (nothing is killed either).
pub fn secs(name: &str, default: f64) -> f64 {
    let key = format!("OK_MCP_TIMEOUT_{}", name.to_ascii_uppercase());
    std::env::var(key)
        .or_else(|_| std::env::var("OK_MCP_TIMEOUT"))
        .ok()
        .and_then(|v| v.trim().parse::<f64>().ok())
        .unwrap_or(default)
}

/// Whether ending a hung game is allowed at all (`OK_MCP_KILL_ON_TIMEOUT=0` turns it off, for debugging a hang live).
fn killing_allowed() -> bool {
    !matches!(std::env::var("OK_MCP_KILL_ON_TIMEOUT").as_deref(), Ok("0") | Ok("false") | Ok("no"))
}

fn powershell(script: &str) -> Result<String> {
    let out = std::process::Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn alive(pid: u32) -> bool {
    powershell(&format!("[bool](Get-Process -Id {pid} -ErrorAction SilentlyContinue)")).is_ok_and(|s| s.eq_ignore_ascii_case("true"))
}

/// That pid's process name, to be sure the pid is still a game and not a number Windows handed to something else.
fn process_name(pid: u32) -> String {
    powershell(&format!("(Get-Process -Id {pid} -ErrorAction SilentlyContinue).ProcessName")).unwrap_or_default()
}

fn is_game(pid: u32) -> bool {
    let name = process_name(pid);
    name.starts_with("UnrealEditor") || name.starts_with("OpenKoikatsu")
}

/// Does that game still answer at all? A short probe tells a hang apart from a slow operation: a busy game still
/// answers /health on the UI channel (it is served from the control thread), a hung one does not.
fn answers(root: &Path, pid: u32) -> bool {
    let Some(port) = crate::control::instances(root)
        .into_iter()
        .find(|v| v["pid"].as_u64() == Some(u64::from(pid)))
        .and_then(|v| v["port_ui"].as_str().and_then(|p| p.parse::<u16>().ok()))
    else {
        return false;
    };
    crate::game::http(port, "/health", None, Duration::from_secs_f64(secs("health", 3.0)), String::new).is_ok()
}

/// What to do when a wait ran out. Returns the sentence to put in the error: whether the game was ended, and where its
/// log and crash dump are. `pid` is the game the call was acting on, 0 when it could not be told.
pub fn timed_out(root: &Path, pid: u32, waited: f64, what: &str) -> String {
    let where_to_look = format!(
        "its log and any GPU crash dump are kept: {}, {}",
        root.join("Saved/Logs").display(),
        root.join("Saved/Crashes").display()
    );
    if pid == 0 {
        return format!("{what} did not answer in {waited:.0} s; no pid to end (set OK_GAME_PID to the game you mean). {where_to_look}");
    }
    if !killing_allowed() {
        return format!("{what} did not answer in {waited:.0} s; pid {pid} left running (OK_MCP_KILL_ON_TIMEOUT=0). {where_to_look}");
    }
    if !crate::control::owned(root, pid) {
        return format!(
            "{what} did not answer in {waited:.0} s; pid {pid} is not this session's game, so it was left alone \
             (name it with OK_GAME_PID, or stop it yourself). {where_to_look}"
        );
    }
    if !alive(pid) {
        return format!("{what} did not answer in {waited:.0} s; pid {pid} is already gone. {where_to_look}");
    }
    if answers(root, pid) {
        return format!(
            "{what} did not answer in {waited:.0} s, but pid {pid} still answers /health, so it was left running: \
             the operation is slow, not hung (raise the deadline with OK_MCP_TIMEOUT). {where_to_look}"
        );
    }
    if !is_game(pid) {
        return format!("{what} did not answer in {waited:.0} s; pid {pid} is no longer a game process, nothing ended. {where_to_look}");
    }
    let killed = powershell(&format!(
        "Get-CimInstance Win32_Process -Filter \"ProcessId={pid}\" | Invoke-CimMethod -MethodName Terminate | Out-Null"
    ));
    let gone = {
        let start = std::time::Instant::now();
        loop {
            if !alive(pid) {
                break true;
            }
            if start.elapsed() > Duration::from_secs(10) {
                break false;
            }
            std::thread::sleep(Duration::from_millis(300));
        }
    };
    let line = if gone {
        format!("{what} did not answer in {waited:.0} s and pid {pid} answers nothing: ended it (Win32_Process.Terminate).")
    } else {
        format!(
            "{what} did not answer in {waited:.0} s and pid {pid} answers nothing; Terminate did not end it{}.",
            match killed {
                Ok(_) => String::new(),
                Err(e) => format!(" ({e})"),
            }
        )
    };
    eprintln!("ok-game-mcp: {line}");
    format!("{line} {where_to_look}")
}

/// The same for a game this session has just started itself (the launch wait): the pid is known to be ours.
pub fn launch_timed_out(root: &Path, pid: u32, waited: f64, what: &str) -> String {
    if !killing_allowed() || !alive(pid) {
        return timed_out(root, pid, waited, what);
    }
    if !is_game(pid) {
        return format!("{what} did not come up in {waited:.0} s; pid {pid} is no longer a game process.");
    }
    let _ = powershell(&format!(
        "Get-CimInstance Win32_Process -Filter \"ProcessId={pid}\" | Invoke-CimMethod -MethodName Terminate | Out-Null"
    ));
    let line = format!("{what} did not come up in {waited:.0} s: ended pid {pid} (Win32_Process.Terminate).");
    eprintln!("ok-game-mcp: {line}");
    format!(
        "{line} Its log and any GPU crash dump are kept: {}, {}",
        root.join("Saved/Logs").display(),
        root.join("Saved/Crashes").display()
    )
}
