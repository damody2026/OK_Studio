//! Measure linear HDR grey-card captures; do not infer illuminance from LDR JPEGs.
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, fs, path::PathBuf};
fn percentile(values: &mut [f64], q: f64) -> f64 {
    assert!(!values.is_empty() && values.iter().all(|v| v.is_finite() && *v >= 0.));
    values.sort_by(f64::total_cmp);
    values[((values.len() - 1) as f64 * q).round() as usize]
}
fn main() {
    let args: Vec<_> = std::env::args().collect();
    let manifest = PathBuf::from(args.get(1).expect("HDR probe manifest"));
    let output = PathBuf::from(args.get(2).expect("report JSON"));
    let bytes = fs::read(&manifest).unwrap();
    let source: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        source["grey_card_linear_reflectance"].as_f64(),
        Some(0.18),
        "Same 18% grey-card contract required"
    );
    assert_eq!(
        source["capture_space"].as_str(),
        Some("linear scene radiance before exposure")
    );
    let mut rows = vec![];
    let mut groups: BTreeMap<String, Vec<(f64, f64, String)>> = BTreeMap::new();
    for q in source["probes"].as_array().unwrap() {
        let p = PathBuf::from(q["hdr_path"].as_str().unwrap());
        let p = if p.is_absolute() {
            p
        } else {
            manifest.parent().unwrap().join(p)
        };
        assert_eq!(
            p.extension()
                .unwrap()
                .to_string_lossy()
                .to_ascii_lowercase(),
            "hdr",
            "Only linear HDR inputs accepted"
        );
        let data = fs::read(&p).unwrap();
        let im = image::load_from_memory_with_format(&data, image::ImageFormat::Hdr)
            .unwrap()
            .to_rgb32f();
        let roi = q["roi_xywh"].as_array().unwrap();
        let r: Vec<u32> = roi.iter().map(|v| v.as_u64().unwrap() as u32).collect();
        assert!(
            r.len() == 4
                && r[2] > 0
                && r[3] > 0
                && r[0] + r[2] <= im.width()
                && r[1] + r[3] <= im.height()
        );
        let mut y = vec![];
        for py in r[1]..r[1] + r[3] {
            for px in r[0]..r[0] + r[2] {
                let p = im.get_pixel(px, py);
                y.push(0.2126 * p[0] as f64 + 0.7152 * p[1] as f64 + 0.0722 * p[2] as f64);
            }
        }
        let p10 = percentile(&mut y, 0.1);
        let median = percentile(&mut y, 0.5);
        let p90 = percentile(&mut y, 0.9);
        assert!(median > 0., "Black/invalid grey-card capture");
        let group = format!(
            "{}@{}",
            q["region"].as_str().unwrap(),
            q["hour"].as_f64().unwrap()
        );
        let role = q["role"].as_str().unwrap().to_string();
        groups
            .entry(group.clone())
            .or_default()
            .push((median, p10 / median, role));
        rows.push(json!({"id":q["id"],"group":group,"path":p,"sha256":format!("{:x}",Sha256::digest(data)),"roi_xywh":r,"p10":p10,"p50":median,"p90":p90,"p10_over_p50":p10/median}));
    }
    let mut checks = vec![];
    for (key, values) in groups {
        assert!(
            values.len() >= 3,
            "At least bright, middle and dim samples per region/time"
        );
        let lo = values.iter().map(|v| v.0).fold(f64::INFINITY, f64::min);
        let hi = values.iter().map(|v| v.0).fold(0., f64::max);
        let limit = if values.iter().any(|v| v.2 == "feature") {
            4.
        } else {
            3.
        };
        let p10 = values.iter().map(|v| v.1).fold(f64::INFINITY, f64::min);
        checks.push(json!({"group":key,"grey_card_ratio":hi/lo,"limit":limit,"min_p10_over_p50":p10,"passed":hi/lo<=limit&&p10>=0.2}));
    }
    assert!(!checks.is_empty());
    let passed = checks.iter().all(|r| r["passed"] == true);
    let result = json!({"status":if passed{"passed"}else{"failed"},"source_map_sha256":source["map_sha256"],"render_run_id":source["render_run_id"],"method":"Rec709 linear HDR luminance; same 18% rough grey cards and orientation; pre-exposure scene captures","manifest_sha256":format!("{:x}",Sha256::digest(bytes)),"rows":rows,"checks":checks});
    fs::write(output, serde_json::to_vec_pretty(&result).unwrap()).unwrap();
    if !passed {
        std::process::exit(1);
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn outliers_do_not_replace_median() {
        let mut x = vec![1., 1., 1., 1., 100.];
        assert_eq!(percentile(&mut x, 0.5), 1.);
    }
    #[test]
    #[should_panic]
    fn nonfinite_hdr_is_rejected() {
        percentile(&mut [0., f64::NAN], 0.5);
    }
}
