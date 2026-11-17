//! Threads: 8 by default; a large batch may ask for more with OK_THREADS=<n> (at most the hardware threads).
// Exports every shadow ramp of a Koikatsu Sunshine install (the graphics
// settings' list) for the render-style picker:
//   ok-ramps GAME_ROOT OUTPUT_DIR
fn main() {
    // The machine-wide rule for ok tools (lib.rs MAX_THREADS): without this, rayon sizes its global
    // pool itself and every bare par_iter here takes all of the machine's cores.
    ok_extract::limit_threads();
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 3 {
        eprintln!("usage: ok-ramps GAME_ROOT OUTPUT_DIR");
        std::process::exit(2);
    }
    match ok_extract::export_character_ramps(std::path::Path::new(&a[1]), std::path::Path::new(&a[2])) {
        Ok(v) => println!("{} ramps", v["ramps"].as_array().map_or(0, Vec::len)),
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1)
        }
    }
}
