//! ok-city-props <props.json> <question> '<request json>'
//!   ok-city-props output/street-social-city-production/places-v1/props.json nearby_props '{"pos":[50070,50406,1281],"radius_cm":1000}'
//! Questions: nearby_props, prop_list, area_at, nearest_prop (see PropIndex::eval).
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: ok-city-props <props.json> <nearby_props|prop_list|area_at|nearest_prop> '<request json>'");
        std::process::exit(2);
    }
    let idx = ok_city_props::PropIndex::load(&args[1]).unwrap_or_else(|e| {
        eprintln!("{e}");
        std::process::exit(1)
    });
    let request: serde_json::Value = serde_json::from_str(&args[3]).unwrap_or_else(|e| {
        eprintln!("request: {e}");
        std::process::exit(2)
    });
    match idx.eval(&args[2], &request) {
        Some(v) => println!("{}", serde_json::to_string_pretty(&v).unwrap()),
        None => {
            eprintln!("unknown question or missing pos: {}", args[2]);
            std::process::exit(2)
        }
    }
}
