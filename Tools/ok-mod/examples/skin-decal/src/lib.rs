//! `skin-decal`: a sticker or tattoo on her body or face (Docs/OK_MOD_FRAMEWORK_PLAN.md §14, KoiSkinOverlayX's editing
//! side). The reference mod for resources in a card (`okMr`, §6.12) and `material.post_texture`.
//!
//! - The reader's "Skin decal" page picks a picture (a built-in heart or star, or a PNG file), where it goes (body or
//!   face texture, UV position, size, rotation), its opacity and tint.
//! - Saving the card (`reader.character_save`) stores the settings as this mod's `okMx` data and the PNG itself as a
//!   resource in `okMr`, named in the data by its sha256 (`hooks::save_with_resources`). The host keeps it once and
//!   drops it when the decal is removed.
//! - Opening the card anywhere (reader, Studio, 1-on-1, street): `material.post_texture` reads this mod's data and the
//!   PNG straight from the card file (`hooks::CardMod`) and draws it into the body or face texture. A card opens from
//!   the open cache when it did not change, so a new decal shows once the card is saved and opened again.
//! - Without this mod the card opens as before, and its data and PNG stay in the card (the core keeps both chunks).

use std::collections::HashMap;

use ok_mod_sdk::prelude::*;
use serde::{Deserialize, Serialize};

/// Version of the data this mod writes. 1: `Decal`.
const DATA_VERSION: u32 = 1;
const ID: &str = "org.openkoikatsu.skin-decal";

/// What the card stores (the PNG itself is the okMr resource `png`).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Decal {
    /// "body" or "head": the part role whose main texture gets it.
    pub target: String,
    /// sha256 hex of the PNG (okMr).
    pub png: String,
    /// Centre in the texture's UV (0..1, v down) and width as a part of the texture's width.
    pub u: f32,
    pub v: f32,
    pub size: f32,
    /// Degrees, clockwise.
    pub rotation: f32,
    pub opacity: f32,
    /// "#RRGGBB" multiplied into the picture.
    pub tint: String,
}

impl Default for Decal {
    fn default() -> Self {
        Decal { target: "body".into(), png: String::new(), u: 0.5, v: 0.5, size: 0.08, rotation: 0.0, opacity: 1.0, tint: "#FFFFFF".into() }
    }
}

/// The reader's choices: the picture source.
#[derive(Clone, Debug, PartialEq)]
enum Source {
    None,
    Heart,
    Star,
    File(String),
}

struct SkinDecal {
    host: Host,
    decal: Decal,
    source: Source,
    /// The PNG chosen in the reader (or read from the card), saved as the resource.
    png: Option<Vec<u8>>,
    /// The card has a section this mod did not read (apply off): saved back as it is unless edited.
    keep_card: bool,
    edited: bool,
    notice: String,
    /// Decoded decals by card file (path, size, modified time), for post_texture.
    cache: HashMap<String, (u64, std::time::SystemTime, Option<(Decal, image::RgbaImage)>)>,
}

fn tint_rgb(text: &str) -> [f32; 3] {
    let hex = text.trim_start_matches('#');
    let c = |i: usize| hex.get(i..i + 2).and_then(|h| u8::from_str_radix(h, 16).ok()).map_or(1.0, |v| v as f32 / 255.0);
    [c(0), c(2), c(4)]
}

/// A built-in picture as a PNG: a heart or a five-pointed star, 256², anti-aliased edge.
pub fn builtin_png(heart: bool) -> Vec<u8> {
    let n = 256u32;
    let img = image::RgbaImage::from_fn(n, n, |x, y| {
        let (px, py) = ((x as f32 + 0.5) / n as f32 * 2.0 - 1.0, 1.0 - (y as f32 + 0.5) / n as f32 * 2.0);
        // Signed "inside" amount: > 0 inside.
        let d = if heart {
            let (x, y) = (px * 1.25, py * 1.25 + 0.25);
            let a = x * x + y * y - 1.0;
            -(a * a * a - x * x * y * y * y) * 4.0
        } else {
            let r = (px * px + py * py).sqrt();
            let t = py.atan2(px) - std::f32::consts::FRAC_PI_2;
            let k = std::f32::consts::TAU / 5.0;
            let m = (t.rem_euclid(k) - k / 2.0).abs() / (k / 2.0);
            let edge = 0.45 + 0.5 * (1.0 - m).powf(3.0);
            (edge - r) * 8.0
        };
        let a = (d * 8.0 + 0.5).clamp(0.0, 1.0);
        if heart { image::Rgba([220, 40, 70, (a * 255.0) as u8]) } else { image::Rgba([250, 200, 40, (a * 255.0) as u8]) }
    });
    let mut out = Vec::new();
    img.write_to(&mut std::io::Cursor::new(&mut out), image::ImageFormat::Png).expect("png into a Vec");
    out
}

/// Draws `decal` (picture `pic`) into the `w`×`h` RGBA texture `rgba`. Returns whether a pixel changed.
pub fn draw(rgba: &mut [u8], w: u32, h: u32, decal: &Decal, pic: &image::RgbaImage) -> bool {
    if w == 0 || h == 0 || pic.width() == 0 || decal.size <= 0.0 || decal.opacity <= 0.0 {
        return false;
    }
    let tint = tint_rgb(&decal.tint);
    let half_w = decal.size * w as f32 / 2.0;
    let half_h = half_w * pic.height() as f32 / pic.width() as f32;
    let (cx, cy) = (decal.u * w as f32, decal.v * h as f32);
    let (s, c) = decal.rotation.to_radians().sin_cos();
    let reach = (half_w * half_w + half_h * half_h).sqrt().ceil() as i64;
    let mut changed = false;
    for y in (cy as i64 - reach).max(0)..(cy as i64 + reach).min(h as i64) {
        for x in (cx as i64 - reach).max(0)..(cx as i64 + reach).min(w as i64) {
            let (dx, dy) = (x as f32 + 0.5 - cx, y as f32 + 0.5 - cy);
            // Into the picture's frame (rotation clockwise on screen).
            let (lx, ly) = (dx * c + dy * s, -dx * s + dy * c);
            let (pu, pv) = (lx / (2.0 * half_w) + 0.5, ly / (2.0 * half_h) + 0.5);
            if !(0.0..1.0).contains(&pu) || !(0.0..1.0).contains(&pv) {
                continue;
            }
            let p = pic.get_pixel((pu * pic.width() as f32) as u32, (pv * pic.height() as f32) as u32);
            let a = p[3] as f32 / 255.0 * decal.opacity;
            if a <= 0.0 {
                continue;
            }
            let i = ((y as u32 * w + x as u32) * 4) as usize;
            for k in 0..3 {
                let src = p[k] as f32 * tint[k];
                rgba[i + k] = (rgba[i + k] as f32 * (1.0 - a) + src * a).round().clamp(0.0, 255.0) as u8;
            }
            changed = true;
        }
    }
    changed
}

#[derive(Deserialize)]
struct PostTexture {
    slot: String,
    #[serde(default)]
    card: Option<String>,
    /// First the texture is offered without pixels: answer whether to get them.
    #[serde(default)]
    query: bool,
    #[serde(default)]
    width: u32,
    #[serde(default)]
    height: u32,
    #[serde(default)]
    rgba: usize,
    #[serde(default)]
    len: usize,
}

impl SkinDecal {
    fn source_value(&self) -> &'static str {
        match self.source {
            Source::None => "none",
            Source::Heart => "heart",
            Source::Star => "star",
            Source::File(_) => "file",
        }
    }

    fn set_source(&mut self, value: &str, path: Option<String>) -> Result<(), String> {
        self.source = match value {
            "none" => Source::None,
            "heart" => Source::Heart,
            "star" => Source::Star,
            "file" => Source::File(path.unwrap_or_else(|| match &self.source { Source::File(p) => p.clone(), _ => String::new() })),
            other => return Err(format!("unknown source {other}")),
        };
        self.png = match &self.source {
            Source::None => None,
            Source::Heart => Some(builtin_png(true)),
            Source::Star => Some(builtin_png(false)),
            Source::File(p) if p.is_empty() => None,
            Source::File(p) => {
                let bytes = std::fs::read(p).map_err(|e| format!("{p}: {e}"))?;
                image::load_from_memory_with_format(&bytes, image::ImageFormat::Png).map_err(|e| format!("{p}: not a PNG: {e}"))?;
                Some(bytes)
            }
        };
        self.decal.png = self.png.as_deref().map(hooks::resource_hash).unwrap_or_default();
        Ok(())
    }

    /// This card's decal, from the card file (cached by size and modified time).
    fn card_decal(&mut self, card: &str) -> Option<(Decal, image::RgbaImage)> {
        let meta = std::fs::metadata(card).ok()?;
        let (len, modified) = (meta.len(), meta.modified().ok()?);
        if let Some((l, m, d)) = self.cache.get(card) {
            if *l == len && *m == modified {
                return d.clone();
            }
        }
        let read = || -> ModResult<Option<(Decal, image::RgbaImage)>> {
            let Some(found) = hooks::CardMod::read(card, ID)? else { return Ok(None) };
            let decal: Decal = found.section.data(DATA_VERSION, |_, v| Ok(v))?;
            let png = found.section.resource(&decal.png).ok_or("the card lacks the decal's picture")?;
            let pic = image::load_from_memory_with_format(&png, image::ImageFormat::Png).map_err(|e| e.to_string())?.to_rgba8();
            Ok(Some((decal, pic)))
        };
        let found = read().unwrap_or_else(|e| {
            self.host.warn(format!("{card}: {e}"));
            None
        });
        if self.cache.len() > 64 {
            self.cache.clear();
        }
        self.cache.insert(card.to_owned(), (len, modified, found.clone()));
        found
    }
}

impl Mod for SkinDecal {
    fn create(host: Host) -> ModResult<Self> {
        Ok(SkinDecal { host, decal: Decal::default(), source: Source::None, png: None, keep_card: false, edited: false, notice: String::new(), cache: HashMap::new() })
    }

    fn register(&mut self, reg: &mut Registrar) -> ModResult<()> {
        for hook in ["reader.character_load", "reader.character_save", "reader.ui", "reader.values", "reader.control", "material.post_texture"] {
            reg.subscribe(hook);
        }
        Ok(())
    }

    fn on_event(&mut self, event: &Event) -> ModResult<Reply> {
        let Event::Hook { name, payload } = event else { return Ok(Reply::None) };
        match name.as_str() {
            "material.post_texture" => {
                let p: PostTexture = hooks::parse(payload)?;
                let Some(card) = p.card.as_deref() else { return Ok(Reply::None) };
                if p.query {
                    // Only the texture this card's decal goes on (one of hundreds an open makes).
                    let want = self.card_decal(card).is_some_and(|(d, _)| d.target == p.slot);
                    return if want { hooks::json(&serde_json::json!({"want": true})) } else { Ok(Reply::None) };
                }
                if p.rgba == 0 || p.len < (p.width as usize * p.height as usize * 4) {
                    return Ok(Reply::None);
                }
                let Some((decal, pic)) = self.card_decal(card) else { return Ok(Reply::None) };
                if decal.target != p.slot {
                    return Ok(Reply::None);
                }
                // SAFETY: the host hands over `len` writable bytes for this call (ok-extract mod_forward.rs).
                let rgba = unsafe { std::slice::from_raw_parts_mut(p.rgba as *mut u8, p.len) };
                if draw(rgba, p.width, p.height, &decal, &pic) {
                    hooks::json(&serde_json::json!({"changed": true}))
                } else {
                    Ok(Reply::None)
                }
            }
            "reader.character_load" => {
                let load: hooks::CharacterLoad = hooks::parse(payload)?;
                self.edited = false;
                self.keep_card = load.section.is_some();
                self.decal = Decal::default();
                self.source = Source::None;
                self.png = None;
                self.notice.clear();
                let read = load.data::<Decal>(DATA_VERSION, |_, v| Ok(v)).unwrap_or_else(|e| {
                    self.host.warn(format!("{}: {e}", load.card));
                    None
                });
                if let Some(decal) = read {
                    self.png = load.section.as_ref().and_then(|s| s.resource(&decal.png));
                    if self.png.is_none() {
                        self.notice = "卡片裡找不到貼紙圖片".into();
                    }
                    self.source = Source::File("（卡片裡的圖）".into());
                    self.decal = decal;
                    self.keep_card = false;
                }
                Ok(Reply::None)
            }
            "reader.character_save" => {
                if self.keep_card && !self.edited {
                    return Ok(Reply::None);
                }
                match (&self.png, self.source != Source::None) {
                    (Some(png), true) => hooks::save_with_resources(DATA_VERSION, &self.decal, &[png.as_slice()]),
                    _ => hooks::remove(),
                }
            }
            "reader.ui" => hooks::json(&serde_json::json!({"pages": [{
                "name": "貼紙／紋身",
                "items": [
                    {"kind": "choice", "key": "source", "label": "圖案", "options": [
                        {"value": "none", "label": "不貼"}, {"value": "heart", "label": "內建：愛心"},
                        {"value": "star", "label": "內建：星星"}, {"value": "file", "label": "PNG 檔案"}]},
                    {"kind": "text", "key": "file", "label": "PNG 路徑", "placeholder": "C:/.../sticker.png"},
                    {"kind": "radio", "key": "target", "label": "貼在", "options": [
                        {"value": "body", "label": "身體"}, {"value": "head", "label": "臉"}]},
                    {"kind": "slider", "key": "u", "label": "左右（UV）", "min": 0.0, "max": 1.0, "step": 0.005},
                    {"kind": "slider", "key": "v", "label": "上下（UV）", "min": 0.0, "max": 1.0, "step": 0.005},
                    {"kind": "slider", "key": "size", "label": "大小", "min": 0.01, "max": 0.5, "step": 0.005},
                    {"kind": "slider", "key": "rotation", "label": "旋轉（度）", "min": -180.0, "max": 180.0, "step": 1.0},
                    {"kind": "slider", "key": "opacity", "label": "不透明度", "min": 0.0, "max": 1.0, "step": 0.01},
                    {"kind": "color", "key": "tint", "label": "顏色"},
                    {"kind": "label", "key": "status", "style": "Caption"},
                    {"kind": "label", "text": "貼紙與圖片存在卡片裡；另存卡片後重新開卡就看得到。沒裝這個 mod 的人開卡看不到貼紙，資料仍留在卡裡。", "style": "Body"},
                ],
            }]})),
            "reader.values" => {
                let status = if !self.notice.is_empty() {
                    self.notice.clone()
                } else {
                    match &self.png {
                        Some(png) => format!("圖片 {} KB，{}", png.len() / 1024, if self.edited { "還沒存進卡片" } else { "和卡片相同" }),
                        None => "沒有貼紙".into(),
                    }
                };
                hooks::json(&serde_json::json!({
                    "source": self.source_value(),
                    "file": match &self.source { Source::File(p) => p.clone(), _ => String::new() },
                    "target": self.decal.target, "u": self.decal.u, "v": self.decal.v, "size": self.decal.size,
                    "rotation": self.decal.rotation, "opacity": self.decal.opacity, "tint": self.decal.tint,
                    "status": status,
                }))
            }
            "reader.control" => {
                let set: hooks::ReaderSet = hooks::parse(payload)?;
                let num = || set.value.as_f64().map(|v| v as f32).ok_or_else(|| format!("{} must be a number", set.key));
                let text = || set.value.as_str().map(str::to_owned).ok_or_else(|| format!("{} must be a string", set.key));
                self.notice.clear();
                match set.key.as_str() {
                    "source" => {
                        if let Err(e) = self.set_source(&text()?, None) {
                            self.notice = e.clone();
                            return hooks::json(&serde_json::json!({"notice": e}));
                        }
                    }
                    "file" => {
                        if let Err(e) = self.set_source("file", Some(text()?)) {
                            self.notice = e.clone();
                            return hooks::json(&serde_json::json!({"notice": e}));
                        }
                    }
                    "target" => {
                        let t = text()?;
                        if t != "body" && t != "head" {
                            return Err(format!("target {t}"));
                        }
                        self.decal.target = t;
                    }
                    "u" => self.decal.u = num()?.clamp(0.0, 1.0),
                    "v" => self.decal.v = num()?.clamp(0.0, 1.0),
                    "size" => self.decal.size = num()?.clamp(0.0, 1.0),
                    "rotation" => self.decal.rotation = num()?,
                    "opacity" => self.decal.opacity = num()?.clamp(0.0, 1.0),
                    "tint" => self.decal.tint = text()?,
                    other => return Err(format!("unknown key {other}")),
                }
                self.edited = true;
                Ok(Reply::None)
            }
            _ => Ok(Reply::None),
        }
    }
}

ok_mod!(SkinDecal);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn builtins_are_pngs_with_a_shape() {
        for heart in [true, false] {
            let pic = image::load_from_memory(&builtin_png(heart)).unwrap().to_rgba8();
            assert_eq!(pic.get_pixel(128, 128)[3], 255, "centre inside");
            assert_eq!(pic.get_pixel(2, 2)[3], 0, "corner outside");
        }
    }

    #[test]
    fn draws_where_it_is_told() {
        let pic = image::RgbaImage::from_pixel(4, 4, image::Rgba([255, 0, 0, 255]));
        let (w, h) = (100u32, 100u32);
        let mut tex = vec![255u8; (w * h * 4) as usize];
        let decal = Decal { u: 0.25, v: 0.75, size: 0.1, ..Decal::default() };
        assert!(draw(&mut tex, w, h, &decal, &pic));
        let px = |tex: &[u8], x: u32, y: u32| tex[((y * w + x) * 4) as usize..][..3].to_vec();
        assert_eq!(px(&tex, 25, 75), [255, 0, 0], "centre painted");
        assert_eq!(px(&tex, 75, 25), [255, 255, 255], "elsewhere untouched");
        let half = Decal { opacity: 0.5, tint: "#00FF00".into(), u: 0.75, v: 0.25, ..decal };
        draw(&mut tex, w, h, &half, &pic);
        assert_eq!(px(&tex, 75, 25), [128, 128, 128], "red tinted green is black, half over white");
    }
}
