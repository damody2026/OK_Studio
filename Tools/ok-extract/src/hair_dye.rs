//! Dyed hair (the street's salon). The hair colours of a card only reach hair the game tints: many mods paint their
//! hair's colour into its texture and set `_Color` white through MaterialEditor, so 安可 stayed pink whatever the card
//! said. A dyed card carries the colour (`okHd`, three bytes) and every hair renderer of an open gets its texture
//! recoloured: the shading of the old texture (its brightness around the mean) in the new colour. Hair is told from the
//! material, whatever the card, not from who she is. The open cache keeps the result.
use crate::session::{OkSession, SessionPart};
use std::collections::HashMap;

/// The colour of a dyed card: red, green, blue (sRGB bytes).
pub const CHUNK: &[u8; 4] = b"okHd";

fn named_hair(p: &SessionPart) -> bool {
    let name = p.name.to_lowercase();
    let Some(m) = p.source_material.as_ref() else { return name.contains("hair") };
    let material = m.name.to_lowercase();
    if material.starts_with("acs_m_") { return false; } // an ornament of the game, whatever its mesh is called
    m.shader.to_lowercase().contains("main_hair") || material.contains("hair") || name.contains("hair")
}
fn overlay(p: &SessionPart) -> bool {
    p.source_material.as_ref().is_some_and(|m| m.shader.contains("studio_alpha") || m.name.to_lowercase().contains("copy"))
}
/// The parts that are her hair: hair slots, hair materials, and the MaterialEditor copies drawn over those.
pub fn hair_parts(s: &OkSession) -> Vec<usize> {
    let hair = |p: &SessionPart| p.role.starts_with("hair") || (p.role == "accessory" && named_hair(p));
    // The same mesh and slot under another material: a copy drawn over it, or the same texture (雷电将军's hair itself is
    // a main_item called Minus_screw, only the flower of that mesh a hair material).
    s.parts.iter().enumerate().filter(|(_, p)| hair(p) || (p.role == "accessory"
        && s.parts.iter().any(|h| hair(h) && h.name == p.name && h.source_property == p.source_property && (overlay(p) || h.png == p.png)))).map(|(i, _)| i).collect()
}
/// Whether the salon can change this hair: something of it has a colour to change.
pub fn dyeable(s: &OkSession) -> bool {
    s.parts.iter().enumerate().any(|(i, p)| p.png.is_some() && hair_parts(s).contains(&i))
}

/// The texture in `target` (sRGB 0..1): brightness around the mean keeps its shading, the brightest parts go towards white.
fn recolor(png: &[u8], target: [f32; 3]) -> Option<Vec<u8>> {
    let mut img = crate::teximg::load_from_memory(png).ok()?.into_rgba8();
    let lum = |p: &image::Rgba<u8>| (0.2126 * p[0] as f32 + 0.7152 * p[1] as f32 + 0.0722 * p[2] as f32) / 255.0;
    let (mut sum, mut n) = (0f64, 0f64);
    for p in img.pixels() { if p[3] > 16 { sum += lum(p) as f64; n += 1.0; } }
    if n == 0.0 || sum <= 0.0 { return None; }
    let mean = (sum / n) as f32;
    for p in img.pixels_mut() {
        let l = lum(p) / mean;
        for c in 0..3 {
            let t = target[c];
            let v = if l <= 1.0 { t * l } else { t + (1.0 - t) * ((l - 1.0) / (1.0 / mean - 1.0).max(1e-3)).min(1.0) * 0.7 };
            p[c] = (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
        }
    }
    crate::teximg::png_fast_bytes(&img)
}

/// The colour a dyed card carries, on its hair (nothing for any other card).
pub fn apply(s: &mut OkSession, card: &[u8]) {
    let Some(&[r, g, b]) = crate::oklib::png_chunk(card, CHUNK).and_then(|c| <&[u8; 3]>::try_from(c).ok()) else { return };
    let target = [r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0];
    let srgb_close = |c: [f32; 4]| (0..3).all(|i| (c[i] - target[i]).abs() < 0.02);
    // Hair the game tints (its `_Color` is the dye already): the texture only loses the colour painted into it.
    let mut jobs: HashMap<(u32, usize, bool), Vec<u8>> = HashMap::new();
    let hair = hair_parts(s);
    let tinted = |p: &SessionPart| p.source_material.as_ref().and_then(|m| m.color("_Color")).is_some_and(srgb_close);
    let key = |png: &[u8], plain: bool| (crc32fast::hash(png), png.len(), plain);
    for &i in &hair { let p = &s.parts[i]; let plain = tinted(p);
        for png in p.png.iter().chain(p.shader_textures.get("_MainTex")) { jobs.entry(key(png, plain)).or_insert_with(|| png.clone()); } }
    let done: HashMap<(u32, usize, bool), Vec<u8>> = crate::oklib::pack_parallel(|| { use rayon::prelude::*;
        jobs.into_par_iter().filter_map(|(k, png)| recolor(&png, if k.2 { [1.0; 3] } else { target }).map(|out| (k, out))).collect() });
    for i in hair {
        let plain = tinted(&s.parts[i]);
        let p = &mut s.parts[i];
        if let Some(out) = p.png.as_ref().and_then(|png| done.get(&key(png, plain))) { p.png = Some(out.clone()); }
        if let Some(out) = p.shader_textures.get("_MainTex").and_then(|png| done.get(&key(png, plain))) { let out = out.clone(); p.shader_textures.insert("_MainTex".into(), out); }
        if !plain { if let Some(m) = p.source_material.as_mut() { for k in ["_Color", "_Color2", "_Color3"] { if m.colors.contains_key(k) { m.colors.insert(k.into(), [1.0; 4]); } } } }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn recolor_keeps_the_shading_in_the_new_colour() {
        let mut img = image::RgbaImage::new(2, 1);
        img.put_pixel(0, 0, image::Rgba([200, 100, 100, 255]));
        img.put_pixel(1, 0, image::Rgba([100, 50, 50, 255]));
        let out = recolor(&crate::teximg::png_fast_bytes(&img).unwrap(), [0.2, 0.8, 0.2]).unwrap();
        let out = crate::teximg::load_from_memory(&out).unwrap().into_rgba8();
        let (a, b) = (out.get_pixel(0, 0), out.get_pixel(1, 0));
        assert!(a[1] > b[1] && a[1] > a[0] && b[1] > b[0], "green, the lit pixel brighter: {a:?} {b:?}");
        assert_eq!(a[3], 255);
    }
}
