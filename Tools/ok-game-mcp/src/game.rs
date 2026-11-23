//! The game side: the StreetSocial control channel (HTTP on 127.0.0.1, always open; Source/OpenKoikatsu/OKStreetSocialControl.inl),
//! the checkout it belongs to, and starting or stopping that game.
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

pub struct Game {
    pub root: PathBuf,
    pub port: u16,
}

impl Game {
    /// The checkout is the folder holding OpenKoikatsu.uproject (OK_ROOT, else up from the exe, else up from here).
    /// The port is OK_CONTROL_PORT, else local-instance.json port_base + 10 (Tools/ok_instance.lua), else 47870.
    pub fn locate() -> Result<Game> {
        let root = match std::env::var_os("OK_ROOT") {
            Some(r) => PathBuf::from(r),
            None => {
                let starts = [std::env::current_exe().ok(), std::env::current_dir().ok()];
                starts
                    .iter()
                    .flatten()
                    .flat_map(|p| p.ancestors().map(Path::to_path_buf).collect::<Vec<_>>())
                    .find(|p| p.join("OpenKoikatsu.uproject").is_file())
                    .context("OpenKoikatsu.uproject not found above the exe or the working folder; set OK_ROOT")?
            }
        };
        let port = match std::env::var("OK_CONTROL_PORT").ok().and_then(|p| p.parse().ok()) {
            Some(p) => p,
            None => {
                let base = std::fs::read_to_string(root.join("local-instance.json"))
                    .ok()
                    .and_then(|t| serde_json::from_str::<Value>(t.trim_start_matches('\u{feff}')).ok())
                    .and_then(|v| v["port_base"].as_u64())
                    .unwrap_or(47860);
                (base + 10) as u16
            }
        };
        Ok(Game { root, port })
    }

    /// The running street game's port (OK_CONTROL_PORT fixes it; a game takes the next free one when another has it).
    fn live_port(&self) -> Result<u16> {
        if std::env::var_os("OK_CONTROL_PORT").is_some() { Ok(self.port) } else { crate::control::port(&self.root, "street", self.port) }
    }

    /// GET (body None) or POST JSON to the control channel; the reply is JSON.
    pub fn call(&self, path: &str, body: Option<&Value>) -> Result<Value> {
        let port = self.live_port()?;
        // A hung game keeps the socket open and never replies: wait only so long, then end it (watchdog.rs).
        let deadline = crate::watchdog::secs("call", 60.);
        let began = Instant::now();
        match http(port, path, body, Duration::from_secs_f64(deadline.max(1.)), || {
            format!("the game's control channel is not up on 127.0.0.1:{port} (start it with game_launch)")
        }) {
            Ok(v) => Ok(v),
            Err(e) => {
                let waited = began.elapsed().as_secs_f64();
                if waited < deadline * 0.9 {
                    return Err(e);
                }
                let pid = crate::control::acting_pid();
                anyhow::bail!("{e}\n{}", crate::watchdog::timed_out(&self.root, pid, waited, &format!("the street control channel {path}")));
            }
        }
    }

    pub fn up(&self) -> bool {
        self.call("/health", None).is_ok()
    }
}

/// `X-OK-From:` for every control request, ending in CRLF (empty if there is nothing to say): this process's pid, and
/// the lane or session name from `OK_MCP_FROM` / `OK_LANE` when the caller set one. The game logs it per request.
pub fn from_header() -> String {
    format!("X-OK-From: {}\r\n", from_who())
}

/// The same identity as plain text, for the card reader's mailbox (its requests are files, not HTTP).
pub fn from_who() -> String {
    let who = std::env::var("OK_MCP_FROM").or_else(|_| std::env::var("OK_LANE")).unwrap_or_default();
    let who = who.chars().filter(|c| !c.is_control()).take(64).collect::<String>();
    if who.is_empty() { format!("pid={}", std::process::id()) } else { format!("pid={} {who}", std::process::id()) }
}

/// GET (body None) or POST JSON to a local HTTP control server; the reply is JSON. down: the error when nothing listens.
pub fn http(port: u16, path: &str, body: Option<&Value>, timeout: Duration, down: impl FnOnce() -> String) -> Result<Value> {
    let text = http_text(port, path, body, timeout, down)?;
    serde_json::from_str(&text).with_context(|| format!("{path}: reply is not JSON"))
}

/// The same, the reply as text.
pub fn http_text(port: u16, path: &str, body: Option<&Value>, timeout: Duration, down: impl FnOnce() -> String) -> Result<String> {
    {
        let mut stream = TcpStream::connect(("127.0.0.1", port)).with_context(down)?;
        stream.set_read_timeout(Some(timeout))?;
        let payload = body.map(|b| b.to_string()).unwrap_or_default();
        // Who is asking, for the game's log. Several sessions drive games on one machine and a tool that forgets
        // OK_GAME_PID lands on someone else's game; without this the log cannot say whose command a page turn was
        // (2026-11-19: another session's script paged through a reader in the middle of a measurement).
        let from = from_header();
        let head = if body.is_some() {
            format!(
                "POST {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json; charset=utf-8\r\n{from}Content-Length: {}\r\nConnection: close\r\n\r\n",
                payload.len()
            )
        } else {
            format!("GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\n{from}Connection: close\r\n\r\n")
        };
        stream.write_all(head.as_bytes())?;
        stream.write_all(payload.as_bytes())?;
        let mut raw = Vec::new();
        stream.read_to_end(&mut raw)?;
        let split = raw.windows(4).position(|w| w == b"\r\n\r\n").context("malformed HTTP reply")?;
        let headers = String::from_utf8_lossy(&raw[..split]).to_lowercase();
        let status: u16 = headers.split_whitespace().nth(1).and_then(|s| s.parse().ok()).unwrap_or(0);
        let mut data = raw[split + 4..].to_vec();
        if headers.contains("transfer-encoding: chunked") {
            data = unchunk(&data)?;
        }
        let text = String::from_utf8_lossy(&data).into_owned();
        if !(200..300).contains(&status) {
            bail!("{path}: HTTP {status}: {}", text.chars().take(400).collect::<String>());
        }
        Ok(text)
    }
}

/// The game game_launch started here (0 before): game_instances marks it, the launch reply names it.
static LAUNCHED: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

pub fn launched() -> u32 {
    LAUNCHED.load(std::sync::atomic::Ordering::Relaxed)
}

/// Moves the channel files of games that no longer run out of Saved/OKControl (into Saved/OKControl/stale): the pid is
/// gone, or it now belongs to a process created after that game wrote its file (Windows gives pids out again). A pid
/// alone is not enough (2026-11-18: game_instances listed three dead games whose pids were ShellExperienceHost, conhost
/// and nothing). Returns how many were moved; any error leaves the files as they are.
pub fn prune_stale_channels(root: &Path) -> usize {
    let dir = root.join("Saved/OKControl");
    let Ok(entries) = std::fs::read_dir(&dir) else { return 0 };
    // Every process's creation time in unix seconds, one query.
    let script = "Get-CimInstance Win32_Process | ForEach-Object { '' + $_.ProcessId + ' ' + ([DateTimeOffset]$_.CreationDate).ToUnixTimeSeconds() }";
    let Ok(out) = Command::new("powershell").args(["-NoProfile", "-Command", script]).output() else { return 0 };
    if !out.status.success() {
        return 0;
    }
    let created: std::collections::HashMap<u64, i64> = String::from_utf8_lossy(&out.stdout)
        .lines()
        .filter_map(|l| {
            let mut f = l.split_whitespace();
            Some((f.next()?.parse().ok()?, f.next()?.parse().ok()?))
        })
        .collect();
    if created.is_empty() {
        return 0;
    }
    let mut moved = 0;
    for e in entries.flatten() {
        let path = e.path();
        if path.extension().is_none_or(|x| x != "json") {
            continue;
        }
        let Some(v) = std::fs::read_to_string(&path).ok().and_then(|t| serde_json::from_str::<Value>(t.trim_start_matches('\u{feff}')).ok()) else {
            continue;
        };
        let (Some(pid), Some(started)) = (v["pid"].as_u64(), v["started"].as_i64()) else { continue };
        // The game writes its file a few seconds after its process starts; a process created later is another program.
        let stale = match created.get(&pid) {
            None => true,
            Some(&c) => c > started + 120,
        };
        if stale {
            let to = dir.join("stale");
            if std::fs::create_dir_all(&to).is_ok() && std::fs::rename(&path, to.join(e.file_name())).is_ok() {
                moved += 1;
            }
        }
    }
    moved
}

fn pid_alive(pid: &str) -> Result<bool> {
    let out = Command::new("tasklist").args(["/FI", &format!("PID eq {pid}"), "/NH", "/FO", "CSV"]).output()?;
    Ok(String::from_utf8_lossy(&out.stdout).contains(&format!("\"{pid}\"")))
}

impl Game {
    /// Starts the game with the control channel (Tools/run_street_social_development.lua -Control), windowed, and waits
    /// until the channel answers. extra: more launcher options ("-Trace", "-Exec", "stat unit", "-Sandbox", "x", ...).
    pub fn launch(&self, window: &str, extra: &[String], timeout: Duration) -> Result<Value> {
        // Only this server's own game stands in the way: another session's sandbox game runs on its own ports.
        if crate::control::own_ready(&self.root) && self.up() {
            bail!("this session's game still answers on port {}; game_stop it first", self.live_port()?);
        }
        crate::control::set_own(0);
        LAUNCHED.store(0, std::sync::atomic::Ordering::Relaxed);
        prune_stale_channels(&self.root);
        let lua = self.root.join("Tools/lua/lua.exe");
        let script = self.root.join("Tools/run_street_social_development.lua");
        let logs = self.root.join("Saved/StreetSocial");
        std::fs::create_dir_all(&logs)?;
        let log = std::fs::File::create(self.launch_log())?;
        let mut cmd = Command::new(lua);
        cmd.arg(script).args(["-Control", "-Window", window]).args(extra).current_dir(&self.root);
        cmd.stdout(Stdio::from(log.try_clone()?)).stderr(Stdio::from(log)).stdin(Stdio::null());
        let mut child = cmd.spawn().context("could not start the launcher")?;
        let start = Instant::now();
        while start.elapsed() < timeout {
            if let Some(status) = child.try_wait()? {
                if !status.success() && !self.up() {
                    bail!("the launcher stopped ({status}); see {}:\n{}", self.launch_log().display(), self.launch_log_tail());
                }
                // The launcher leaves once the game is started: a game that dies before it answers would wait out the timeout.
                if let Some(pid) = self.launched_pid() {
                    if !self.up() && !pid_alive(&pid)? {
                        bail!("the game (pid {pid}) exited before the control channel came up; see the newest Saved/StreetSocial/Play-*/game.log");
                    }
                }
            }
            // Up means the game just started answers (its channels written under its pid), not the newest of another session.
            let pid = self.launched_pid().and_then(|p| p.parse::<u32>().ok());
            if let Some(pid) = pid {
                crate::control::set_own(pid);
            }
            if crate::control::own_ready(&self.root) && self.up() {
                // The tools now act on this game (set_own drops any game_select); the reply names it so no one looks it up.
                let pid = pid.unwrap_or(0);
                LAUNCHED.store(pid, std::sync::atomic::Ordering::Relaxed);
                return Ok(json!({"ok": true, "pid": pid, "acts_on": pid, "port": self.live_port()?, "seconds": start.elapsed().as_secs()}));
            }
            std::thread::sleep(Duration::from_secs(2));
        }
        // Started but never answered (a hang during load, a GPU device hang): end that pid rather than leave it
        // sitting there for ever. Only the game this call started (watchdog.rs).
        let hung = self.launched_pid().and_then(|p| p.parse::<u32>().ok()).unwrap_or(0);
        bail!("the control channel did not come up in {}s; launcher log:
{}
{}", timeout.as_secs(), self.launch_log_tail(),
            crate::watchdog::launch_timed_out(&self.root, hung, timeout.as_secs_f64(), "the street game"))
    }

    /// One per control port: games of other sessions in this checkout start at the same time.
    fn launch_log(&self) -> std::path::PathBuf {
        self.root.join(format!("Saved/StreetSocial/ok-game-mcp-launch-{}.log", self.port))
    }

    /// The game the launcher last started (its "game pid N" line).
    fn launched_pid(&self) -> Option<String> {
        let text = std::fs::read_to_string(self.launch_log()).ok()?;
        text.lines().rev().find_map(|l| l.trim().strip_prefix("game pid ").map(String::from))
    }

    fn launch_log_tail(&self) -> String {
        let text = std::fs::read_to_string(self.launch_log()).unwrap_or_default();
        let lines: Vec<&str> = text.lines().collect();
        lines[lines.len().saturating_sub(20)..].join("\n")
    }

    /// The process listening on this checkout's control port: the game this server drives.
    fn port_pid(&self) -> Result<Option<String>> {
        let out = Command::new("netstat").args(["-ano", "-p", "TCP"]).output()?;
        let text = String::from_utf8_lossy(&out.stdout);
        let port = self.live_port()?;
        let local = format!("127.0.0.1:{port}");
        let any = format!("0.0.0.0:{port}");
        Ok(text
            .lines()
            .map(|l| l.split_whitespace().collect::<Vec<_>>())
            .find(|f| f.len() >= 5 && (f[1] == local || f[1] == any) && f[3].eq_ignore_ascii_case("LISTENING"))
            .map(|f| f[4].to_string()))
    }

    /// Stops only the game listening on this checkout's control port (another session's sandbox game keeps running) and
    /// answers once its process is gone: closed, or terminated when it did not close within 20 s.
    pub fn stop(&self) -> Result<Value> {
        // Never the newest game of the checkout by default: that was another session's (see control::OWN). OK_CONTROL_PORT
        // names the port outright; otherwise the game started here or one picked with game_select.
        if std::env::var_os("OK_CONTROL_PORT").is_none() && !crate::control::may_stop(&self.root) {
            bail!("no game started by this session runs (another session's games are not stopped); game_select the pid to stop another, see game_instances");
        }
        let Some(pid) = self.port_pid()? else { return Ok(json!({"ok": true, "stopped": null, "note": "no game on that port"})) };
        // The port is machine-wide: E:'s server, with the same port base, closed C:'s game listening there (2026-11-08 19:03).
        // Only a game of this checkout (its channels under Saved/OKControl) is stopped.
        if !crate::control::instances(&self.root).iter().any(|v| v["pid"].as_u64().map(|p| p.to_string()) == Some(pid.clone())) {
            bail!("the game on port {} (pid {pid}) is not a game of this checkout; not stopped", self.live_port()?);
        }
        // taskkill without /F only asks the window to close and returns at once: "stopped" used to come back while the
        // game was still shutting down (seen alive 5 s later, F wave 5). Ask, wait until it is gone, else terminate it.
        let n: u32 = pid.parse().with_context(|| format!("pid {pid}"))?;
        let asked = Command::new("taskkill").args(["/PID", &pid]).output()?;
        let start = Instant::now();
        if wait_gone(n, Duration::from_secs(20)) {
            return Ok(json!({"ok": true, "stopped": pid, "how": "closed", "seconds": start.elapsed().as_secs_f64()}));
        }
        crate::reader::powershell(&format!(
            "Get-CimInstance Win32_Process -Filter \"ProcessId={n}\" | Invoke-CimMethod -MethodName Terminate | Out-Null"
        ))?;
        if wait_gone(n, Duration::from_secs(15)) {
            return Ok(json!({"ok": true, "stopped": pid, "how": "terminated after the close request did not end it",
                "close_request_ok": asked.status.success(), "seconds": start.elapsed().as_secs_f64()}));
        }
        bail!("pid {pid} still runs after the close request and Terminate ({:.0} s)", start.elapsed().as_secs_f64())
    }

    /// The log of the game on this control port (the Play-* folder whose game.pid is that process), else the newest
    /// game log; its last lines, optionally only those containing a text. The newest alone was another session's
    /// sandbox game.
    pub fn log(&self, lines: usize, contains: Option<&str>) -> Result<Value> {
        let dir = self.root.join("Saved/StreetSocial");
        let plays: Vec<std::path::PathBuf> = std::fs::read_dir(&dir)?
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with("Play-"))
            .map(|e| e.path())
            .filter(|p| p.join("game.log").is_file())
            .collect();
        let pid = self.port_pid().ok().flatten();
        let modified = |p: &&std::path::PathBuf| p.join("game.log").metadata().and_then(|m| m.modified()).ok();
        // The newest of the folders with that pid: Windows gives a pid out again, and the first match was a game of an
        // hour before (its log read as this one's).
        let ours = pid.and_then(|pid| plays.iter().filter(|p| std::fs::read_to_string(p.join("game.pid")).is_ok_and(|t| t.trim() == pid)).max_by_key(modified).cloned());
        let newest = ours
            .or_else(|| plays.iter().max_by_key(modified).cloned())
            .map(|p| p.join("game.log"))
            .context("no Saved/StreetSocial/Play-*/game.log yet")?;
        let bytes = std::fs::read(&newest)?;
        // The tail only: logs grow to hundreds of MB.
        let tail = &bytes[bytes.len().saturating_sub(8 << 20)..];
        let text = String::from_utf8_lossy(tail);
        let picked: Vec<&str> = text.lines().filter(|l| contains.is_none_or(|c| l.contains(c))).collect();
        let shown = picked[picked.len().saturating_sub(lines)..].join("\n");
        Ok(json!({"file": newest.to_string_lossy(), "lines": shown}))
    }
}

fn unchunk(data: &[u8]) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    let mut at = 0;
    loop {
        let end = data[at..].windows(2).position(|w| w == b"\r\n").context("bad chunk")? + at;
        let size = usize::from_str_radix(String::from_utf8_lossy(&data[at..end]).split(';').next().unwrap_or("0").trim(), 16)?;
        if size == 0 {
            return Ok(out);
        }
        out.extend_from_slice(&data[end + 2..end + 2 + size]);
        at = end + 2 + size + 2;
    }
}

/// Whether `pid` is gone within `timeout` (checked every 300 ms).
fn wait_gone(pid: u32, timeout: Duration) -> bool {
    let start = Instant::now();
    loop {
        if !crate::reader::alive(pid) {
            return true;
        }
        if start.elapsed() > timeout {
            return false;
        }
        std::thread::sleep(Duration::from_millis(300));
    }
}
