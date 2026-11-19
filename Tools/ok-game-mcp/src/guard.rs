//! What a call is allowed to do before it reaches the game: the argument check and the engine-start check.
//!
//! Both exist because of one morning (2026-11-19, Docs/ERROR_LOG.md). Someone wanted to know which fields
//! `reader_launch` takes and sent `{"help":true}` to find out. There was no way to ask, unknown fields were ignored,
//! and nothing looked at the machine — so "let me check the usage" started a card reader inside another session's
//! exclusive GPU measurement. Three things follow from that, and all three are here:
//!
//! * asking is free (`--describe` prints the schema and runs nothing);
//! * a field we do not know is an error that names the fields we do know, never a silent no-op;
//! * a call that starts an engine reads the slot board and the machine first, and refuses rather than barge in.
use anyhow::{Result, bail};
use serde_json::Value;
use std::path::PathBuf;
use std::process::Command;

/// Fields every tool tolerates: the card reader's own round-trip bookkeeping, which callers echo back.
const ALWAYS: &[&str] = &["session", "revision"];
/// Set on a launch call to go ahead although the machine says no. Deliberately not in any tool's schema: it is a
/// person's decision, not a parameter a script should learn to pass.
pub const FORCE: &str = "force";

/// The arguments this tool declares, from its `inputSchema`.
fn allowed(tools: &Value, name: &str) -> Option<Vec<String>> {
    let tool = tools.as_array()?.iter().find(|t| t["name"] == name)?;
    Some(tool["inputSchema"]["properties"].as_object()?.keys().cloned().collect())
}

/// Refuse an argument the tool does not declare, naming what it does take. Silently ignoring a misspelled field is
/// worse than failing: the caller believes they set something they did not (and `{"help":true}` quietly launched a game).
pub fn check_args(tools: &Value, name: &str, a: &Value) -> Result<()> {
    let Some(known) = allowed(tools, name) else { return Ok(()) };
    let Some(given) = a.as_object() else { return Ok(()) };
    // A tool that dispatches on `action` carries a payload whose fields are the action's, not the tool's: reader_call
    // alone takes path, index, offset, limit, query, keys, edits, page, key, value, command … each only for its own
    // action, and its inputSchema declares none of them. Checking those against one static schema refused every
    // correct call and broke the card reader's whole command-line automation (2026-11-19, within an hour of shipping
    // this check). So here the envelope is all we can judge; the game itself rejects a payload field it does not know.
    if known.iter().any(|k| k == "action") { return Ok(()) }
    let unknown: Vec<&str> = given.keys()
        .map(String::as_str)
        .filter(|k| *k != FORCE && !ALWAYS.contains(k) && !known.iter().any(|w| w == k))
        .collect();
    if unknown.is_empty() { return Ok(()) }
    let takes = if known.is_empty() { "no arguments".to_string() } else { known.join(", ") };
    bail!("{name} does not take {}: it takes {takes}. `ok-game-mcp call {name} --describe` prints the schema \
        without running anything.", unknown.join(", "));
}

fn slots_root() -> PathBuf {
    std::env::var("OK_UNREAL_SLOTS").map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("C:/portable/OpenKoikatsu/Saved/UnrealSlots"))
}

/// Each held slot's owner line (agent, what for, since when, and `[need N]` for an exclusive claim).
fn slot_owners() -> Vec<(usize, String)> {
    let root = slots_root();
    (1..=2).filter_map(|i| {
        let text = std::fs::read_to_string(root.join(format!("slot{i}")).join("owner.txt")).ok()?;
        let text = text.trim().to_string();
        (!text.is_empty()).then_some((i, text))
    }).collect()
}

/// Unreal processes on the whole machine, not just this checkout's: the cap is the machine's, and another tree's
/// editor loads the same GPU.
fn unreal_processes() -> Option<usize> {
    let script = "(Get-CimInstance Win32_Process | Where-Object { $_.Name -like 'UnrealEditor*' -or $_.Name -like 'OpenKoikatsu*' } | Measure-Object).Count";
    let out = Command::new("powershell").args(["-NoProfile", "-NonInteractive", "-Command", script]).output().ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

/// Before a call that starts an engine (`*_launch`): refuse while someone else's measurement owns the machine, or
/// while the machine already runs the two Unreal processes the user allows. `force: true` goes ahead anyway and says so.
///
/// This is not a replacement for claiming a slot — it is the floor under it. A slot is claimed by agreement; this
/// check is what stops the next person who simply forgot to look (that person was me).
pub fn check_launch(name: &str, a: &Value) -> Result<Option<String>> {
    if !name.ends_with("_launch") { return Ok(None) }
    let forced = a[FORCE].as_bool() == Some(true);
    let owners = slot_owners();
    // An exclusive claim (`--need-gb 60`, recorded as `[need N]`) means: nobody else's engine, not even for a minute.
    // Two slots held by the same agent is the same thing in practice.
    let exclusive = owners.iter().find(|(_, line)| line.contains("[need "));
    let both = owners.len() == 2 && owners[0].1.split_whitespace().next() == owners[1].1.split_whitespace().next();
    let busy = exclusive.map(|(i, line)| format!("slot{i} is held exclusively: {line}"))
        .or_else(|| both.then(|| format!("one agent holds both slots: {}", owners[0].1)));
    let running = unreal_processes();
    let too_many = running.filter(|n| *n >= 2).map(|n| format!("{n} Unreal processes already run (the machine's limit is 2)"));
    let Some(reason) = busy.or(too_many) else { return Ok(None) };
    if forced {
        return Ok(Some(format!("{name} started although {reason} (force: true)")));
    }
    bail!("{name} refused: {reason}. Wait for it to finish (`unreal_slot.lua status` says who and since when), or \
        pass \"force\": true if you really mean to start an engine beside it.");
}
