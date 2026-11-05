use super::*;
pub fn prepare(out: &Path) -> R<(Shape, Value)> {
    let dir = out.join("components/canopy");
    fs::create_dir_all(&dir)?;
    let input = dir.join("source.obj");
    let output = dir.join("remeshed.obj");
    let tool = PathBuf::from("E:/Paper/instant-meshes-rs/target/release/instant-meshes.exe");
    let mut obj = String::from("# Closed low-poly canopy, diameter one metre\n");
    let n = 24;
    for k in 0..n {
        let a = k as f64 * std::f64::consts::TAU / n as f64;
        obj.push_str(&format!("v {} {} 0\n", a.cos() * 0.5, a.sin() * 0.5));
    }
    obj.push_str("v 0 0 1\nv 0 0 -0.02\n");
    for k in 0..n {
        obj.push_str(&format!(
            "f {} {} {}\nf {} {} {}\n",
            k + 1,
            (k + 1) % n + 1,
            n + 1,
            (k + 1) % n + 1,
            k + 1,
            n + 2
        ));
    }
    fs::write(&input, obj)?;
    let certificate = dir.join("remesh-report.json");
    let input_sha = sha(&input)?;
    let tool_sha = sha(&tool)?;
    let cache = read_json(&certificate).ok().filter(|v| {
        v["source_sha256"] == input_sha
            && v["tool_sha256"] == tool_sha
            && output.exists()
            && v["output_sha256"] == sha(&output).unwrap_or_default()
    });
    if cache.is_none() {
        let result = std::process::Command::new(&tool)
            .args([
                "--deterministic",
                "-r",
                "6",
                "-p",
                "6",
                "-f",
                "192",
                "-c",
                "25",
                "-S",
                "0",
                "-o",
            ])
            .arg(&output)
            .arg(&input)
            .output()?;
        fs::write(
            dir.join("remesh.log"),
            [result.stdout, result.stderr].concat(),
        )?;
        if !result.status.success() {
            return Err("canopy remesh failed".into());
        }
    }
    let mut points = vec![];
    let mut indices = vec![];
    for line in fs::read_to_string(&output)?.lines() {
        let fields = line.split_whitespace().collect::<Vec<_>>();
        match fields.first().copied() {
            Some("v") => points.push([fields[1].parse()?, fields[2].parse()?, fields[3].parse()?]),
            Some("f") => {
                let face: Vec<u32> = fields[1..]
                    .iter()
                    .map(|s| s.split('/').next().unwrap().parse::<u32>().map(|n| n - 1))
                    .collect::<Result<_, _>>()?;
                for k in 1..face.len() - 1 {
                    indices.extend([face[0], face[k], face[k + 1]]);
                }
            }
            _ => {}
        }
    }
    assert!(!points.is_empty());
    assert!(indices.len() / 3 <= 2000);
    let mut lo = [f64::MAX; 3];
    let mut hi = [f64::MIN; 3];
    for p in &points {
        for k in 0..3 {
            lo[k] = lo[k].min(p[k]);
            hi[k] = hi[k].max(p[k]);
        }
    }
    assert!(hi[2] - lo[2] > 0.9);
    assert!(hi[0] - lo[0] > 0.9);
    let bounds = [lo, hi];
    for p in &mut points {
        for k in 0..3 {
            p[k] = (p[k] - lo[k]) / (hi[k] - lo[k]) - if k == 2 { 0. } else { 0.5 };
        }
    }
    let proof = json!({"status":"passed","source":output,"sha256":sha(&output)?,"input":input,"source_sha256":input_sha,"tool":tool,"tool_sha256":tool_sha,"output":output,"output_sha256":sha(&output)?,"triangles":indices.len()/3,"bounds_before_dimension_normalization":bounds,"postprocess":"unit dimension normalization only; use actual remesh output topology"});
    write(&certificate, &proof)?;
    Ok((
        Shape {
            p: points,
            i: indices,
        },
        proof,
    ))
}
