use std::path::Path;
fn main() {
    let a:Vec<String>=std::env::args().collect();
    let result=match a.get(1).map(String::as_str) {
        Some("inspect") if a.len()==4 => ok_extract::portable::inspect_hair_base(Path::new(&a[2]),Path::new(&a[3])),
        Some("import") if a.len()==5 => ok_extract::portable::import_hair_card(Path::new(&a[2]),Path::new(&a[3]),Path::new(&a[4])),
        Some("deck") if a.len()>=6 => {
            let opts:ok_extract::portable::hairdeck::HairDeckOpts=match a.get(6){Some(o)=>serde_json::from_str(o).map_err(|e|e.to_string()),None=>Ok(Default::default())}.unwrap_or_default();
            ok_extract::portable::hairdeck::preview_obj(Path::new(&a[2]),Path::new(&a[3]),Path::new(&a[4]),&opts,Path::new(&a[5]))
        }
        _=>Err("usage: ok-hair-pack inspect BASE.png OUTPUT.json | import BASE.png HAIR.json OUTPUT.png | deck LIB CARD CARDS.json OUT.obj [OPTS]".into()),
    };
    match result {Ok(v)=>println!("{}",serde_json::to_string_pretty(&v).unwrap()),Err(e)=>{eprintln!("{e}");std::process::exit(1)}}
}
