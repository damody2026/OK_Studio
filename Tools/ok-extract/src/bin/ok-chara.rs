use std::path::Path;
const USAGE: &str = "usage: ok-chara skeleton LIB BASE_CARD OUT.json OUT.obj\n       ok-chara build LIB BASE_CARD RIGGED.glb OPTIONS.json OUT.png [PREVIEW.obj]";
fn main() {
    let a: Vec<String> = std::env::args().collect();
    let p = |i: usize| Path::new(&a[i]);
    let result = match a.get(1).map(String::as_str) {
        Some("skeleton") if a.len() == 6 => ok_extract::okchara::dump_skeleton(p(2), p(3), p(4), p(5)),
        Some("project") if a.len() == 4 => std::fs::read(p(3)).map_err(|e| format!("{}: {e}", a[3]))
            .and_then(|b| serde_json::from_slice::<ok_extract::okchara::ProjectOptions>(&b).map_err(|e| e.to_string()))
            .and_then(|o| ok_extract::okchara::project_texture(p(2), &o)),
        Some("fields") if a.len() == 3 => ok_extract::okchara::card_fields(p(2)),
        Some("pose-test") if a.len() == 5 => ok_extract::okchara::pose_test(p(2), p(3), p(4)),
        Some("build") if a.len() == 7 || a.len() == 8 => std::fs::read(p(5)).map_err(|e| format!("{}: {e}", a[5]))
            .and_then(|b| serde_json::from_slice::<ok_extract::okchara::BuildOptions>(&b).map_err(|e| e.to_string()))
            .and_then(|o| ok_extract::okchara::build(p(2), p(3), p(4), &o, p(6), a.get(7).map(Path::new))),
        _ => Err(USAGE.into()),
    };
    match result { Ok(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap()), Err(e) => { eprintln!("{e}"); std::process::exit(1) } }
}
