//! Times what a clothing-card click costs on this side: `okclothes::file::wear_into`, exactly as the card reader's
//! clothes grid calls it (`FOkSession::ClothesWear` -> `ok_clothes_file` op 2/3), followed by the open of the card it
//! wrote (what the reader does next with `SelectIndex` + `OnLoad3D`).
//!
//!   ok-clothes-bench LIBRARY GAME CARD OKCLOTHES SCOPE [ROUNDS]
//!
//! SCOPE: `keephair` (點縮圖＝換衣服（保留頭髮）), `clothesonly` (點縮圖＝只換衣服) or `all`.
//! GAME may be a path that does not exist (`X:/NoGame`) for an OK card, which reads no installation.
//! `OK_PROFILE=1` prints `wear:` stage rows to stderr; `OK_CLOTHES_BENCH_NO_OPEN=1` times the wear alone.
//! Each round writes to its own output card under the library's `work/` so no round reuses another's file.
use std::{path::{Path, PathBuf}, time::Instant};

fn run() -> Result<serde_json::Value, String> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() < 6 { return Err("usage: ok-clothes-bench LIBRARY GAME CARD OKCLOTHES SCOPE [ROUNDS]".into()); }
    let (lib, game, card, clothes) = (Path::new(&args[1]), Path::new(&args[2]), Path::new(&args[3]), Path::new(&args[4]));
    let scope = match args[5].as_str() {
        "keephair" => ok_extract::okclothes::WearScope::KeepHair,
        "clothesonly" => ok_extract::okclothes::WearScope::ClothesOnly,
        "all" => ok_extract::okclothes::WearScope::All,
        other => return Err(format!("SCOPE is keephair|clothesonly|all, not {other}")),
    };
    let rounds: usize = args.get(6).and_then(|r| r.parse().ok()).unwrap_or(1);
    let outfit: usize = std::env::var("OK_CLOTHES_BENCH_OUTFIT").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
    std::env::set_var("OK_BASE_LIBRARY", lib);
    if game.is_dir() { std::env::set_var("OK_GAME_ROOT", game); }
    let no_open = std::env::var_os("OK_CLOTHES_BENCH_NO_OPEN").is_some();
    let out_dir = lib.join("work/clothes-bench");
    std::fs::create_dir_all(&out_dir).map_err(|e| format!("{}: {e}", out_dir.display()))?;
    let mut rows = Vec::new();
    for round in 0..rounds {
        let out: PathBuf = out_dir.join(format!("worn_{}_{round}.png", std::process::id()));
        let t = Instant::now();
        let summary = ok_extract::okclothes::file::wear_into(Some(lib), game, card, clothes, outfit, scope, &out)?;
        let wear = t.elapsed().as_secs_f64();
        let (open, parts) = if no_open { (0.0, 0) } else {
            let t = Instant::now();
            let parts = ok_extract::open_card_like_reader(lib, game, &out, outfit as i32, [0; 9])?;
            (t.elapsed().as_secs_f64(), parts)
        };
        eprintln!("ok-clothes-bench: round {round}: wear {wear:.2}s + open {open:.2}s = {:.2}s ({parts} parts)", wear + open);
        eprintln!("ok-clothes-bench: round {round}: {summary}");
        rows.push(serde_json::json!({"round": round, "wear_s": wear, "open_s": open, "total_s": wear + open, "parts": parts, "summary": summary}));
    }
    Ok(serde_json::json!({"card": args[3], "okclothes": args[4], "scope": args[5], "outfit": outfit, "rounds": rows}))
}

fn main() {
    // The machine-wide rule for ok tools (lib.rs MAX_THREADS).
    ok_extract::limit_threads();
    match run() { Ok(r) => println!("{}", serde_json::to_string_pretty(&r).unwrap()), Err(e) => { eprintln!("{e}"); std::process::exit(1); } }
}
