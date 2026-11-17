//! The OK Studio tools: all listed with well-formed schemas (required keys among the properties), a call without a
//! running studio is a tool error that says to launch it, and missing arguments are refused before any request.
//! Uses a port nothing listens on.
use serde_json::{Value, json};
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};

// The tools this test calls below: they must be listed. Every other studio_* tool is checked by the properties the
// listing must keep (a description, a well-formed schema, no repeated name), never by a count: a count written here
// (33) failed for every group that added a tool (36 on 2026-11-17), so the test was learned to be ignored and a real
// regression could hide in it. The listing is printed (cargo test -- --nocapture) when the changes are wanted.
const CALLED_TOOLS: [&str; 12] = [
    "studio_state", "studio_transform", "studio_delete", "studio_patch", "studio_keys", "studio_catalog", "studio_export",
    "studio_bones", "studio_duplicate", "studio_scene", "studio_ui_shot", "studio_report",
];

#[test]
fn studio_tools_listed_and_called_without_a_studio() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_ok-game-mcp"))
        .env("OK_CONTROL_PORT", "1")
        .env("OK_STUDIO_PORT", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let mut out = BufReader::new(child.stdout.take().unwrap());
    let mut send = |v: Value| writeln!(stdin, "{v}").unwrap();
    let mut read = || -> Value {
        let mut line = String::new();
        out.read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    };
    send(json!({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "0"}}}));
    assert_eq!(read()["result"]["serverInfo"]["name"], "ok-game");
    send(json!({"jsonrpc": "2.0", "method": "notifications/initialized"}));
    send(json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}));
    let listed = read()["result"]["tools"].as_array().unwrap().clone();
    let mut names: Vec<&str> = listed.iter().map(|t| t["name"].as_str().expect("a tool without a name")).collect();
    let studio: Vec<&str> = names.iter().copied().filter(|n| n.starts_with("studio_")).collect();
    eprintln!("studio tools ({}): {}", studio.len(), studio.join(" "));
    assert!(!studio.is_empty(), "no studio_* tool listed");
    for name in CALLED_TOOLS { assert!(studio.contains(&name), "{name} missing"); }
    names.sort_unstable();
    let repeated: Vec<&&str> = names.windows(2).filter(|w| w[0] == w[1]).map(|w| &w[0]).collect();
    assert!(repeated.is_empty(), "tool names listed twice: {repeated:?}");
    for name in studio {
        let tool = listed.iter().find(|t| t["name"] == name).unwrap();
        assert!(!tool["description"].as_str().unwrap_or("").is_empty(), "{name}: no description");
        let schema = &tool["inputSchema"];
        assert_eq!(schema["type"], "object", "{name}: schema type");
        let props = schema["properties"].as_object().unwrap_or_else(|| panic!("{name}: no properties"));
        for r in schema["required"].as_array().map(Vec::as_slice).unwrap_or(&[]) {
            assert!(props.contains_key(r.as_str().unwrap()), "{name}: required {r} is not a property");
        }
        for (key, p) in props {
            assert!(p.is_object(), "{name}.{key}: property schema is not an object");
        }
    }
    // The street tools are still there.
    assert!(listed.iter().any(|t| t["name"] == "game_state"));

    send(json!({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "studio_state", "arguments": {}}}));
    let r = read();
    assert_eq!(r["result"]["isError"], true);
    assert!(r["result"]["content"][0]["text"].as_str().unwrap().contains("OK Studio is not running"));

    send(json!({"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "studio_transform", "arguments": {"location": [0, 0, 0]}}}));
    let r = read();
    assert_eq!(r["result"]["isError"], true);
    assert!(r["result"]["content"][0]["text"].as_str().unwrap().contains("id is required"));

    send(json!({"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "studio_delete", "arguments": {"ids": 3}}}));
    let r = read();
    assert_eq!(r["result"]["isError"], true);
    assert!(r["result"]["content"][0]["text"].as_str().unwrap().contains("ids must be array"));

    // The newer tools: required arguments and types are checked before any request; ui_shot goes to the studio.
    let refused = [
        (6, "studio_patch", json!({"id": 1}), "fields is required"),
        (7, "studio_patch", json!({"id": 1, "fields": [1]}), "fields must be object"),
        (8, "studio_keys", json!({"id": -2}), "action is required"),
        (9, "studio_catalog", json!({"group": 0}), "kind is required"),
        (10, "studio_export", json!({"kind": "mp4", "fps": "30"}), "fps must be number"),
        (11, "studio_bones", json!({}), "id is required"),
        (12, "studio_duplicate", json!({"ids": "1"}), "ids must be array"),
        (13, "studio_scene", json!({"map": 1.5}), "map must be integer"),
        (14, "studio_ui_shot", json!({}), "OK Studio is not running"),
        (15, "studio_report", json!({}), "OK Studio is not running"),
    ];
    for (n, name, args, says) in refused {
        send(json!({"jsonrpc": "2.0", "id": n, "method": "tools/call", "params": {"name": name, "arguments": args}}));
        let r = read();
        assert_eq!(r["result"]["isError"], true, "{name}");
        let text = r["result"]["content"][0]["text"].as_str().unwrap();
        assert!(text.contains(says), "{name}: {text}");
    }
    drop(stdin);
    child.kill().ok();
}
