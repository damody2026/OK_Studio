//! Threads: 8 by default; a large batch may ask for more with OK_THREADS=<n> (at most the hardware threads).
fn main(){
    // The machine-wide rule for ok tools (lib.rs MAX_THREADS): without this, rayon sizes its global
    // pool itself and every bare par_iter here takes all of the machine's cores.
    ok_extract::limit_threads();
    let args:Vec<_>=std::env::args().collect();
    if args.len()!=3{eprintln!("usage: ok-normalize-pack INPUT.png OUTPUT.png");std::process::exit(1);}
    match ok_extract::portable::normalize(std::path::Path::new(&args[1]),std::path::Path::new(&args[2])){
        Ok(report)=>println!("{}",serde_json::to_string_pretty(&report).unwrap()),
        Err(error)=>{eprintln!("{error}");std::process::exit(1);}
    }
}
