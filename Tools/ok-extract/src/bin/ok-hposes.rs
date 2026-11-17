// Writes the original H scene's pose metadata (mode, service kind, anal, experience gates) as JSON:
//   ok-hposes GAME_ROOT OUTPUT.json
fn main() {
    // The machine-wide rule for ok tools (lib.rs MAX_THREADS): without this, rayon sizes its global
    // pool itself and every bare par_iter here takes all of the machine's cores.
    ok_extract::limit_threads();
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 3 {
        eprintln!("usage: ok-hposes GAME_ROOT OUTPUT.json");
        std::process::exit(2);
    }
    let json = ok_extract::h_pose_table(std::path::Path::new(&a[1]));
    if let Err(e) = std::fs::write(&a[2], &json) {
        eprintln!("{e}");
        std::process::exit(1)
    }
    println!("{} bytes", json.len());
}
