// Times opening a card the way the one-on-one's wardrobe does (OKOpenWardrobeItem): an original KKS card (a coordinate card
// worn on her card) from the OK base library plus the installation's zipmods it names, every clothes state, live GPU env.
//   ok-wardrobe-bench LIBRARY GAME CARD OUTFIT [ROUNDS]
// Each round is timed; OK_PROFILE=1 prints the open's stages to stderr.
use std::{path::Path, time::Instant};

fn run() -> Result<serde_json::Value, String> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() < 5 { return Err("usage: ok-wardrobe-bench LIBRARY GAME CARD OUTFIT [ROUNDS]".into()); }
    for key in ["OK_GPU_SKIN", "OK_SKELMESH", "OK_NOPOSE", "OK_UE_ANIM", "OK_HEAD_GPUSKIN", "OK_CLOTHES_ALL_STATES"] { std::env::set_var(key, "1"); }
    std::env::set_var("OK_BASE_LIBRARY", &args[1]);
    std::env::set_var("OK_GAME_ROOT", &args[2]);
    let outfit: i32 = args[4].parse().map_err(|_| "OUTFIT is a number")?;
    let rounds: usize = args.get(5).and_then(|r| r.parse().ok()).unwrap_or(2);
    let mut rows = Vec::new();
    // OK_BENCH_PREWARM=1: the library's prewarm first (as the street starts it), timed on its own.
    if std::env::var_os("OK_BENCH_PREWARM").is_some() {
        let t = Instant::now();
        ok_extract::prewarm(Path::new(&args[1]))?;
        let seconds = t.elapsed().as_secs_f64();
        eprintln!("ok-wardrobe-bench: prewarm {seconds:.2}s");
        rows.push(serde_json::json!({"prewarm": seconds}));
    }
    for round in 0..rounds {
        let t = Instant::now();
        let parts = ok_extract::open_card_like_reader(Path::new(&args[1]), Path::new(&args[2]), Path::new(&args[3]), outfit, [0; 9])?;
        let seconds = t.elapsed().as_secs_f64();
        eprintln!("ok-wardrobe-bench: round {round}: {seconds:.2}s, {parts} parts");
        rows.push(serde_json::json!({"round": round, "seconds": seconds, "parts": parts}));
    }
    Ok(serde_json::json!({"card": args[3], "outfit": outfit, "rounds": rows}))
}
fn main() { match run() { Ok(r) => println!("{}", serde_json::to_string_pretty(&r).unwrap()), Err(e) => { eprintln!("{e}"); std::process::exit(1); } } }
