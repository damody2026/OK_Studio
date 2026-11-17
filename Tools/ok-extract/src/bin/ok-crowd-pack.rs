//! Threads: 8 by default; a large batch may ask for more with OK_THREADS=<n> (at most the hardware threads).
#[path="ok-preview-pack.rs"]mod pack;
fn main(){
    // The machine-wide rule for ok tools (lib.rs MAX_THREADS): without this, rayon sizes its global
    // pool itself and every bare par_iter here takes all of the machine's cores.
    ok_extract::limit_threads();let a:Vec<_>=std::env::args().collect();
    if a.len()!=8{eprintln!("usage: ok-crowd-pack GAME LIST WORKER_RESOURCES OUTPUT START END PUBLISH_RESOURCES");std::process::exit(1);}
    let result=pack::batch_shared_range(std::path::Path::new(&a[1]),std::path::Path::new(&a[2]),std::path::Path::new(&a[3]),std::path::Path::new(&a[4]),a[5].parse().unwrap(),a[6].parse().unwrap(),Some(std::path::Path::new(&a[7])));
    match result{Ok(report)=>println!("{}",serde_json::to_string_pretty(&report).unwrap()),Err(error)=>{eprintln!("{error}");std::process::exit(1);}}
}
