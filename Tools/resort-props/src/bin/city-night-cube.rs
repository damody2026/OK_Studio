//! Low-frequency night irradiance, independent of the visible dark sky.
use image::{codecs::hdr::HdrEncoder, Rgb};
use std::{fs::File, io::BufWriter, path::PathBuf};
fn main() {
    let day = std::env::args().any(|s| s == "--day");
    let p = PathBuf::from(std::env::args().nth(1).expect("output .hdr"));
    let (w, h) = (512usize, 256usize);
    let mut pixels = vec![];
    for y in 0..h {
        let z = (std::f32::consts::PI * (y as f32 + 0.5) / h as f32).cos();
        let top = if day {
            [0.18, 0.42, 0.85]
        } else {
            [0.46, 0.62, 0.91]
        };
        let horizon = if day {
            [0.62, 0.78, 0.92]
        } else {
            [0.62, 0.75, 0.95]
        };
        let lower = if day {
            [0.08, 0.07, 0.05]
        } else {
            [0.10, 0.13, 0.18]
        };
        let t = z.abs().sqrt();
        let c = std::array::from_fn(|k| {
            if z >= 0. {
                horizon[k] * (1. - t) + top[k] * t
            } else {
                horizon[k] * (1. - t) + lower[k] * t
            }
        });
        for _ in 0..w {
            pixels.push(Rgb(c));
        }
    }
    HdrEncoder::new(BufWriter::new(File::create(p).unwrap()))
        .encode(&pixels, w, h)
        .unwrap();
}
