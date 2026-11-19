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
    // A tool that dispatches on `action` checks the envelope only: the fields belong to the action, not to the tool,
    // so no static schema can list them (`reader_call`'s `select` takes `index`, `get` takes `keys`, `set` takes
    // `edits`…). Checked against the schema, every documented call is "unknown fields" — which is how this check
    // stopped a measurement grid on its first card and sent its owner back to the pre-guard exe. **A check that
    // calls correct usage an error is worse than no check**, because the way around it is to switch the guard off.
    // The game rejects an action it does not know, so the payload is its business.
    if known.iter().any(|k| k == "action") { return Ok(()) }
    let Some(given) = a.as_object() else { return Ok(()) };
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

/// The lane this call belongs to: the argument the launch already takes (`reader_launch`'s `lane`, which also goes
/// on the game's command line as `-OKLane=`), else the environment. It is how a slot holder says "this engine is the
/// one I claimed the machine for".
fn caller_lane(a: &Value) -> Option<String> {
    a["lane"].as_str().map(str::to_string)
        .or_else(|| std::env::var("OK_LANE").ok())
        .or_else(|| std::env::var("OK_UNREAL_LANE").ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// The `[lane=<name>]` an owner line carries (`unreal_slot.lua claim --lane <name>`), when it carries one.
fn owner_lane(line: &str) -> Option<&str> {
    let rest = line.split("[lane=").nth(1)?;
    let lane = rest.split(']').next()?.trim();
    (!lane.is_empty()).then_some(lane)
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
    let lane = caller_lane(a);
    // Exclusive means the one explicit mark, `[need N]` (`--need-gb 60`): nobody else's engine, not even for a minute.
    // Not "one agent holds both slots" — that inference is gone. It was an unwritten second signal for the same thing,
    // and the two read each other wrong: the agent that held both slots to own the GPU had its own `reader_launch`
    // refused, which left `force` as the only way through. A guard that the holder has to force is not a guard.
    //
    // The holder's own engine is told apart by lane: the claim records `[lane=<name>]` and the call carries the same
    // name. An exclusive claim with no lane recorded still refuses everyone, the claimant included — say who you are
    // and the guard can tell; treating "no lane" as "must be you" would mean anyone passes.
    let busy = owners.iter()
        .find(|(_, line)| line.contains("[need ") && owner_lane(line) != lane.as_deref())
        .map(|(i, line)| match (owner_lane(line), lane.as_deref()) {
            (Some(_), Some(mine)) => format!("slot{i} is held exclusively by another lane (you are \"{mine}\"): {line}"),
            (Some(theirs), None) => format!("slot{i} is held exclusively by lane \"{theirs}\": {line} — pass \"lane\": \"{theirs}\" if this engine is that claim's"),
            _ => format!("slot{i} is held exclusively: {line}"),
        });
    let running = unreal_processes();
    let too_many = running.filter(|n| *n >= 2).map(|n| format!("{n} Unreal processes already run (the machine's limit is 2)"));
    let Some(reason) = busy.or(too_many) else { return Ok(None) };
    if forced {
        return Ok(Some(format!("{name} started although {reason} (force: true)")));
    }
    bail!("{name} refused: {reason}. Wait for it to finish (`unreal_slot.lua status` says who and since when), or \
        pass \"force\": true if you really mean to start an engine beside it.");
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// The schema of an action-dispatched tool cannot list the fields its actions take, so it must not be used to
    /// reject them. This is the regression, not a style preference: with the check on, no `reader_call` but a bare
    /// `state` worked, and the failure read like the game ignoring the call rather than the call never arriving.
    #[test]
    fn a_passthrough_tool_keeps_the_fields_its_action_needs() {
        let tools = json!([{ "name": "reader_call",
            "inputSchema": {"properties": {"action": {"type": "string"}, "timeout_s": {"type": "number"}}} }]);
        for a in [json!({"action": "select", "index": 1}),
                  json!({"action": "get", "keys": ["face.foregroundEyes"]}),
                  json!({"action": "set", "values": [{"key": "face.foregroundEyes", "value": 2}]})] {
            check_args(&tools, "reader_call", &a).expect("a reader_call action's own fields must reach the game");
        }
    }

    /// A tool that does declare its arguments still refuses a field it never heard of, and says what it takes.
    #[test]
    fn a_declared_tool_still_names_what_it_takes() {
        let tools = json!([{ "name": "reader_launch",
            "inputSchema": {"properties": {"card": {"type": "string"}, "lane": {"type": "string"}}} }]);
        check_args(&tools, "reader_launch", &json!({"card": "x.png"})).unwrap();
        let err = check_args(&tools, "reader_launch", &json!({"help": true})).unwrap_err().to_string();
        assert!(err.contains("help") && err.contains("card") && err.contains("--describe"), "{err}");
    }
}

#[cfg(test)]
mod lane_tests {
    use super::*;
    use serde_json::json;

    /// The owner line is free text with markers at the end; only an explicit `[lane=…]` counts.
    #[test]
    fn a_lane_is_read_from_the_owner_line_only_when_it_is_written_there() {
        assert_eq!(owner_lane("e-cardload 旋鈕（需獨占） 2026-11-19 11:46 [need 60] [lane=e-knob]"), Some("e-knob"));
        assert_eq!(owner_lane("e-cardload 旋鈕 2026-11-19 11:46 [need 60]"), None);
        assert_eq!(owner_lane("f-sceneload 實拍 [lane=]"), None);
    }

    /// The call says which lane it is, through the argument the launch already takes.
    #[test]
    fn the_calls_lane_comes_from_its_own_argument() {
        assert_eq!(caller_lane(&json!({"lane": "e-knob"})).as_deref(), Some("e-knob"));
        assert_eq!(caller_lane(&json!({"lane": "  "})), None);
        assert_eq!(caller_lane(&json!({"card": "x.png"})), std::env::var("OK_LANE").ok()
            .or_else(|| std::env::var("OK_UNREAL_LANE").ok()));
    }
}
