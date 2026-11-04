//! The KKS display colour transform for Unreal previews (Content/KKPreview/KKSDefaultSaturationLUT*.png), from
//! BetterColorPicker's saturation-filter table (`BepInEx/plugins/KKS_BetterColorPicker.dll`).
//!
//! The plugin embeds a 64³ RGB table (a 512×512 atlas of 8×8 tiles) that maps a filtered screen colour back to its
//! unfiltered colour. It is inverted numerically once and written as the forward transform: a 512×512 atlas of the 64³
//! cube and Unreal's 256×16 colour-grading atlas (16 blue slices). No card colours or reference pixels are used.
//! Port of the retired Tools/generate_kks_saturation_lut.py (same arithmetic in f32).
use std::path::Path;

type Cube = Vec<[f32; 3]>; // index (b * 64 + g) * 64 + r

/// The first embedded 512×512 PNG of the plugin, as RGB.
fn embedded_atlas(dll: &[u8]) -> Result<image::RgbImage, String> {
    const SIGNATURE: &[u8] = b"\x89PNG\r\n\x1a\n";
    let mut at = 0;
    while let Some(start) = dll[at..].windows(SIGNATURE.len()).position(|w| w == SIGNATURE).map(|p| p + at) {
        if let Ok(img) = image::load_from_memory_with_format(&dll[start..], image::ImageFormat::Png) {
            if img.width() == 512 && img.height() == 512 { return Ok(img.to_rgb8()); }
        }
        at = start + SIGNATURE.len();
    }
    Err("no embedded 512x512 colour cube".into())
}

fn cube_from_atlas(atlas: &image::RgbImage) -> Cube {
    let mut cube = vec![[0f32; 3]; 64 * 64 * 64];
    for b in 0..64u32 {
        for g in 0..64u32 {
            for r in 0..64u32 {
                let p = atlas.get_pixel((b % 8) * 64 + r, (b / 8) * 64 + g);
                cube[((b * 64 + g) * 64 + r) as usize] = [p[0] as f32 / 255.0, p[1] as f32 / 255.0, p[2] as f32 / 255.0];
            }
        }
    }
    cube
}

fn trilinear(cube: &Cube, color: [f32; 3]) -> [f32; 3] {
    let mut lower = [0usize; 3];
    let mut upper = [0usize; 3];
    let mut frac = [0f32; 3];
    for i in 0..3 {
        let pos = color[i].clamp(0.0, 1.0) * 63.0;
        let l = pos.floor();
        lower[i] = l as usize;
        upper[i] = (lower[i] + 1).min(63);
        frac[i] = pos - l;
    }
    let mut out = [0f32; 3];
    for b in 0..2 {
        let (ib, wb) = if b == 1 { (upper[2], frac[2]) } else { (lower[2], 1.0 - frac[2]) };
        for g in 0..2 {
            let (ig, wg) = if g == 1 { (upper[1], frac[1]) } else { (lower[1], 1.0 - frac[1]) };
            for r in 0..2 {
                let (ir, wr) = if r == 1 { (upper[0], frac[0]) } else { (lower[0], 1.0 - frac[0]) };
                let w = wb * wg * wr;
                let c = cube[(ib * 64 + ig) * 64 + ir];
                for k in 0..3 { out[k] += c[k] * w; }
            }
        }
    }
    out
}

/// The forward transform: for every grid colour, the colour the inverse table maps onto it (damped fixed-point
/// iteration; the table is smooth and monotone through the usable gamut, clipped colours stay at the edge).
fn forward_cube(inverse: &Cube) -> Cube {
    use rayon::prelude::*;
    (0..64 * 64 * 64usize).into_par_iter().map(|i| {
        let (b, g, r) = (i / 4096, (i / 64) % 64, i % 64);
        let wanted = [r as f32 / 63.0, g as f32 / 63.0, b as f32 / 63.0];
        let mut result = wanted;
        for _ in 0..70 {
            let got = trilinear(inverse, result);
            for k in 0..3 { result[k] = (result[k] + (2.2f32 * (wanted[k] - got[k])).clamp(-0.06, 0.06)).clamp(0.0, 1.0); }
        }
        result
    }).collect()
}

fn byte(v: f32) -> u8 { (v * 255.0).round_ties_even().clamp(0.0, 255.0) as u8 }

/// Writes `<dir>/KKSDefaultSaturationLUT.png` (512×512) and `<dir>/KKSDefaultSaturationLUT16.png` (256×16, Unreal's
/// colour-grading layout) from the game's BetterColorPicker plugin. Returns the plugin path read.
pub fn convert(game: &Path, dir: &Path) -> Result<String, String> {
    let dll = game.join("BepInEx/plugins/KKS_BetterColorPicker.dll");
    let bytes = std::fs::read(&dll).map_err(|e| format!("{}: {e}", dll.display()))?;
    let forward = forward_cube(&cube_from_atlas(&embedded_atlas(&bytes).map_err(|e| format!("{}: {e}", dll.display()))?));
    let mut atlas = image::RgbImage::new(512, 512);
    for b in 0..64u32 {
        for g in 0..64u32 {
            for r in 0..64u32 {
                let c = forward[((b * 64 + g) * 64 + r) as usize];
                atlas.put_pixel((b % 8) * 64 + r, (b / 8) * 64 + g, image::Rgb([byte(c[0]), byte(c[1]), byte(c[2])]));
            }
        }
    }
    let mut small = image::RgbImage::new(256, 16);
    for z in 0..16u32 {
        for g in 0..16u32 {
            for r in 0..16u32 {
                let c = trilinear(&forward, [r as f32 / 15.0, g as f32 / 15.0, z as f32 / 15.0]);
                small.put_pixel(z * 16 + r, g, image::Rgb([byte(c[0]), byte(c[1]), byte(c[2])]));
            }
        }
    }
    std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    atlas.save(dir.join("KKSDefaultSaturationLUT.png")).map_err(|e| e.to_string())?;
    small.save(dir.join("KKSDefaultSaturationLUT16.png")).map_err(|e| e.to_string())?;
    Ok(dll.display().to_string())
}
