use serde_json::{json, Value};
use std::{
    error::Error,
    fs,
    path::{Path, PathBuf},
};
mod publication;
mod variation;
type Result<T> = std::result::Result<T, Box<dyn Error>>;
struct Glb {
    doc: Value,
    bin: Vec<u8>,
}
impl Glb {
    fn read(path: &Path) -> Result<Self> {
        let bytes = fs::read(path)?;
        if bytes.len() < 20 || &bytes[..4] != b"glTF" {
            return Err("Not GLB".into());
        }
        let size = u32::from_le_bytes(bytes[12..16].try_into()?) as usize;
        let doc = serde_json::from_slice(&bytes[20..20 + size])?;
        let offset = 20 + size;
        let bin = if offset + 8 <= bytes.len() {
            let len = u32::from_le_bytes(bytes[offset..offset + 4].try_into()?) as usize;
            bytes[offset + 8..offset + 8 + len].to_vec()
        } else {
            vec![]
        };
        Ok(Self { doc, bin })
    }
    fn image(&self, index: usize) -> Result<&[u8]> {
        let view = &self.doc["bufferViews"][self.doc["images"][index]["bufferView"]
            .as_u64()
            .ok_or("External image unsupported")?
            as usize];
        let off = view["byteOffset"].as_u64().unwrap_or(0) as usize;
        let len = view["byteLength"].as_u64().ok_or("Missing buffer length")? as usize;
        Ok(&self.bin[off..off + len])
    }
    fn save(&self, path: &Path) -> Result<()> {
        let mut doc = serde_json::to_vec(&self.doc)?;
        while doc.len() % 4 != 0 {
            doc.push(b' ')
        }
        let mut bytes = vec![];
        bytes.extend_from_slice(b"glTF");
        bytes.extend(2u32.to_le_bytes());
        bytes.extend(((28 + doc.len() + self.bin.len()) as u32).to_le_bytes());
        bytes.extend((doc.len() as u32).to_le_bytes());
        bytes.extend_from_slice(b"JSON");
        bytes.extend(doc);
        bytes.extend((self.bin.len() as u32).to_le_bytes());
        bytes.extend_from_slice(b"BIN\0");
        bytes.extend_from_slice(&self.bin);
        fs::write(path, bytes)?;
        Ok(())
    }
}
fn load(path: &Path) -> Result<Value> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}
fn write(path: &Path, value: &Value) -> Result<()> {
    if let Some(p) = path.parent() {
        fs::create_dir_all(p)?;
    }
    fs::write(path, serde_json::to_vec_pretty(value)?)?;
    Ok(())
}
fn inspect(root: &Path) -> Result<()> {
    let base = root.join("output/street-social-city-production/streetscape-v1");
    let out = root.join("output/street-social-city-production/streetscape-variations-v1");
    fs::create_dir_all(out.join("source-inspection"))?;
    let assets = load(&base.join("delivery.json"))?;
    let mut rows = vec![];
    for asset in assets["assets"].as_array().ok_or("Missing assets")? {
        let id = asset["id"].as_str().unwrap();
        if !["scooter", "bicycle", "camphor", "cherry"].contains(&id) {
            continue;
        }
        let path = PathBuf::from(asset["lods"][0]["path"].as_str().unwrap());
        let glb = Glb::read(&path)?;
        for (i, _) in glb.doc["images"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .enumerate()
        {
            let pic = image::load_from_memory(glb.image(i)?)?;
            pic.save(out.join("source-inspection").join(format!("{id}-{i}.png")))?;
        }
        rows.push(json!({"id":id,"source":path,"materials":glb.doc["materials"],"textures":glb.doc["textures"],"images":glb.doc["images"]}));
    }
    write(&out.join("source-inspection.json"), &json!(rows))?;
    println!("Inspected vehicle and foliage source materials");
    Ok(())
}
fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let command = args.next().unwrap_or("inspect".into());
    let root = PathBuf::from(args.next().unwrap_or(".".into())).canonicalize()?;
    match command.as_str() {
        "inspect" => inspect(&root),
        "build" => {
            variation::build(&root)?;
            publication::publish(&root)
        }
        "publish" => publication::publish(&root),
        "finalize" => {
            publication::finalize(&root, args.next().as_deref() == Some("--visual-reviewed"))
        }
        "verify" => variation::verify(&root),
        "serve" => variation::serve(&root, args.next().unwrap_or("47982".into()).parse()?),
        _ => Err("Unknown command".into()),
    }
}
