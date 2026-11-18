//! BC7 (BPTC) block decoding, same output bytes as `texture2ddecoder::decode_bc7`, less time per texel.
//!
//! Why this exists: a cold OK-card open spends more time here than anywhere else. Measured 2026-11-18/19
//! (`Docs/CARD_OPEN_PERF_20261117.md` 第四节): one card decodes 24 BC7 textures / 24.0 Mtexel at about
//! 21 ns/texel, and `OK_SKIP_BC=1` (hand back black blocks, wrong output, measurement only) put the ceiling of
//! making this decode free at −0.18~0.21 s wall. `texture2ddecoder` is at its newest version (0.1.2), so the only
//! way at that time was a faster decoder.
//!
//! What was actually slow in the crate: every field — including two index reads **per texel** — goes through
//! `getbits_raw`, which does a `copy_from_slice` of a run-time length into a 4-byte scratch array, i.e. a memcpy
//! call per read (~50 per block). A BC7 block is 16 bytes, so it fits in one `u128`: here every field is a shift
//! and a mask on a register, and nothing is copied.
//!
//! **This is not a new decoder design.** The mode table, the partition tables and the interpolation are the BPTC
//! specification's (the same tables ship with every implementation; transcribed from `texture2ddecoder` 0.1.2,
//! MIT OR Apache-2.0, whose layout they follow — `S_BPTC_P2`/`P3` pack the per-texel subset numbers into one
//! integer). BC7 decoding is fully determined by the spec, so a correct implementation **must** produce the same
//! bytes; `bc7_matches_reference_decoder` checks that against the crate over random blocks of every mode, and the
//! card-open gate (`--fresh-dump`, byte-for-byte session bytes) is the real guard. Kill switch `OK_SLOW_BC7=1`
//! goes back to the crate.

// The anchor index of subset 1 for each 2-subset partition.
static A2: [usize; 64] = [
    15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 2, 8, 2, 2, 8, 8, 15, 2, 8,
    2, 2, 8, 8, 2, 2, 15, 15, 6, 8, 2, 8, 15, 15, 2, 8, 2, 2, 2, 15, 15, 6, 6, 2, 6, 8, 15, 15, 2,
    2, 15, 15, 15, 15, 15, 2, 2, 15,
];

// The anchor indices of subsets 1 and 2 for each 3-subset partition.
static A3: [[usize; 64]; 2] = [
    [
        3, 3, 15, 15, 8, 3, 15, 15, 8, 8, 6, 6, 6, 5, 3, 3, 3, 3, 8, 15, 3, 3, 6, 10, 5, 8, 8, 6,
        8, 5, 15, 15, 8, 15, 3, 5, 6, 10, 8, 15, 15, 3, 15, 5, 15, 15, 15, 15, 3, 15, 5, 5, 5, 8,
        5, 10, 5, 10, 8, 13, 15, 12, 3, 3,
    ],
    [
        15, 8, 8, 3, 15, 15, 3, 8, 15, 15, 15, 15, 15, 15, 15, 8, 15, 8, 15, 3, 15, 8, 15, 8, 3,
        15, 6, 10, 15, 15, 10, 8, 15, 3, 15, 10, 10, 8, 9, 10, 6, 15, 8, 15, 3, 6, 6, 8, 15, 3, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 3, 15, 15, 8,
    ],
];

// Interpolation weights (out of 64) for 2-, 3- and 4-bit indices.
static FACTORS: [[u8; 16]; 3] = [
    [0, 21, 43, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 9, 18, 27, 37, 46, 55, 64, 0, 0, 0, 0, 0, 0, 0, 0],
    [0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64],
];

// Two-subset partitions: one bit a texel, texel `i` in bit `i`.
static P2: [u32; 64] = [
    0xcccc, 0x8888, 0xeeee, 0xecc8, 0xc880, 0xfeec, 0xfec8, 0xec80, 0xc800, 0xffec, 0xfe80, 0xe800,
    0xffe8, 0xff00, 0xfff0, 0xf000, 0xf710, 0x008e, 0x7100, 0x08ce, 0x008c, 0x7310, 0x3100, 0x8cce,
    0x088c, 0x3110, 0x6666, 0x366c, 0x17e8, 0x0ff0, 0x718e, 0x399c, 0xaaaa, 0xf0f0, 0x5a5a, 0x33cc,
    0x3c3c, 0x55aa, 0x9696, 0xa55a, 0x73ce, 0x13c8, 0x324c, 0x3bdc, 0x6996, 0xc33c, 0x9966, 0x0660,
    0x0272, 0x04e4, 0x4e40, 0x2720, 0xc936, 0x936c, 0x39c6, 0x639c, 0x9336, 0x9cc6, 0x817e, 0xe718,
    0xccf0, 0x0fcc, 0x7744, 0xee22,
];

// Three-subset partitions: two bits a texel, texel `i` in bits `2i..2i+2`.
static P3: [u32; 64] = [
    0xaa685050, 0x6a5a5040, 0x5a5a4200, 0x5450a0a8, 0xa5a50000, 0xa0a05050, 0x5555a0a0, 0x5a5a5050,
    0xaa550000, 0xaa555500, 0xaaaa5500, 0x90909090, 0x94949494, 0xa4a4a4a4, 0xa9a59450, 0x2a0a4250,
    0xa5945040, 0x0a425054, 0xa5a5a500, 0x55a0a0a0, 0xa8a85454, 0x6a6a4040, 0xa4a45000, 0x1a1a0500,
    0x0050a4a4, 0xaaa59090, 0x14696914, 0x69691400, 0xa08585a0, 0xaa821414, 0x50a4a450, 0x6a5a0200,
    0xa9a58000, 0x5090a0a8, 0xa8a09050, 0x24242424, 0x00aa5500, 0x24924924, 0x24499224, 0x50a50a50,
    0x500aa550, 0xaaaa4444, 0x66660000, 0xa5a0a5a0, 0x50a050a0, 0x69286928, 0x44aaaa44, 0x66666600,
    0xaa444444, 0x54a854a8, 0x95809580, 0x96969600, 0xa85454a8, 0x80959580, 0xaa141414, 0x96960000,
    0xaaaa1414, 0xa05050a0, 0xa0a5a5a0, 0x96000000, 0x40804080, 0xa9a8a9a8, 0xaaaaaa44, 0x2a4a5254,
];

struct Mode {
    subsets: usize,
    partition_bits: u32,
    rotation_bits: u32,
    index_selection_bits: u32,
    color_bits: u32,
    alpha_bits: u32,
    endpoint_pbits: u32,
    shared_pbits: u32,
    index_bits: [u32; 2],
}

// subsets, partition, rotation, index selection, colour, alpha, endpoint P-bits, shared P-bits, index bits
static MODES: [Mode; 8] = [
    Mode { subsets: 3, partition_bits: 4, rotation_bits: 0, index_selection_bits: 0, color_bits: 4, alpha_bits: 0, endpoint_pbits: 1, shared_pbits: 0, index_bits: [3, 0] },
    Mode { subsets: 2, partition_bits: 6, rotation_bits: 0, index_selection_bits: 0, color_bits: 6, alpha_bits: 0, endpoint_pbits: 0, shared_pbits: 1, index_bits: [3, 0] },
    Mode { subsets: 3, partition_bits: 6, rotation_bits: 0, index_selection_bits: 0, color_bits: 5, alpha_bits: 0, endpoint_pbits: 0, shared_pbits: 0, index_bits: [2, 0] },
    Mode { subsets: 2, partition_bits: 6, rotation_bits: 0, index_selection_bits: 0, color_bits: 7, alpha_bits: 0, endpoint_pbits: 1, shared_pbits: 0, index_bits: [2, 0] },
    Mode { subsets: 1, partition_bits: 0, rotation_bits: 2, index_selection_bits: 1, color_bits: 5, alpha_bits: 6, endpoint_pbits: 0, shared_pbits: 0, index_bits: [2, 3] },
    Mode { subsets: 1, partition_bits: 0, rotation_bits: 2, index_selection_bits: 0, color_bits: 7, alpha_bits: 8, endpoint_pbits: 0, shared_pbits: 0, index_bits: [2, 2] },
    Mode { subsets: 1, partition_bits: 0, rotation_bits: 0, index_selection_bits: 0, color_bits: 7, alpha_bits: 7, endpoint_pbits: 1, shared_pbits: 0, index_bits: [4, 0] },
    Mode { subsets: 2, partition_bits: 6, rotation_bits: 0, index_selection_bits: 0, color_bits: 5, alpha_bits: 5, endpoint_pbits: 1, shared_pbits: 0, index_bits: [2, 0] },
];

/// The quantized value in `bits` bits, stretched to 8 bits by repeating the top bits.
/// `bits == 8` leaves it alone (the crate's `overflowing_shr(8)` wraps to a shift of 0, so `s | s == s`).
#[inline(always)]
fn expand(v: u8, bits: u32) -> u8 {
    let s = ((v as u16) << (8 - bits)) as u8;
    if bits >= 8 { s } else { s | (s >> bits) }
}

/// One 16-byte block into 16 texels, packed as the crate packs them: `u32::from_le_bytes([b, g, r, a])`.
#[inline]
fn decode_block(block: u128, out: &mut [u32; 16]) {
    #[inline(always)]
    fn bits(v: u128, pos: u32, n: u32) -> u32 {
        if n == 0 { return 0; }
        ((v >> pos) as u32) & ((1u32 << n) - 1)
    }

    // The mode is the number of leading zero bits before the first 1 (eight zeros = a reserved block).
    let mode = (block.trailing_zeros() as usize).min(8);
    if mode == 8 {
        out.fill(0);
        return;
    }
    let mi = &MODES[mode];
    let mut pos = mode as u32 + 1;

    let pbits = if mi.endpoint_pbits != 0 { mi.endpoint_pbits } else { mi.shared_pbits };
    let partition = bits(block, pos, mi.partition_bits) as usize;
    pos += mi.partition_bits;
    let rotation = bits(block, pos, mi.rotation_bits);
    pos += mi.rotation_bits;
    let index_selection = bits(block, pos, mi.index_selection_bits) as usize;
    pos += mi.index_selection_bits;

    let mut ep = [[0u8; 6]; 4]; // r, g, b, a endpoints, two a subset
    for ch in 0..3 {
        for i in 0..mi.subsets * 2 {
            ep[ch][i] = (bits(block, pos, mi.color_bits) << pbits) as u8;
            pos += mi.color_bits;
        }
    }
    if mi.alpha_bits > 0 {
        for i in 0..mi.subsets * 2 {
            ep[3][i] = (bits(block, pos, mi.alpha_bits) << pbits) as u8;
            pos += mi.alpha_bits;
        }
    } else {
        ep[3] = [0xff; 6];
    }

    if pbits != 0 {
        for i in 0..mi.subsets {
            let pda = bits(block, pos, pbits) as u8;
            pos += pbits;
            let pdb = if mi.shared_pbits == 0 {
                let v = bits(block, pos, pbits) as u8;
                pos += pbits;
                v
            } else {
                pda
            };
            for ch in 0..4 {
                ep[ch][i * 2] |= pda;
                ep[ch][i * 2 + 1] |= pdb;
            }
        }
    }

    let color_bits = mi.color_bits + pbits;
    for ch in 0..3 {
        for i in 0..mi.subsets * 2 {
            ep[ch][i] = expand(ep[ch][i], color_bits);
        }
    }
    if mi.alpha_bits > 0 {
        let alpha_bits = mi.alpha_bits + pbits;
        for i in 0..mi.subsets * 2 {
            ep[3][i] = expand(ep[3][i], alpha_bits);
        }
    }

    let two_index_sets = mi.index_bits[1] != 0;
    let factors = [
        &FACTORS[mi.index_bits[0] as usize - 2],
        &FACTORS[if two_index_sets { mi.index_bits[1] as usize - 2 } else { mi.index_bits[0] as usize - 2 }],
    ];
    // Both index arrays start after the header: the second one after every subset's first-array indices
    // (the anchor of each subset carries one bit less).
    let mut at = [pos, pos + mi.subsets as u32 * (16 * mi.index_bits[0] - 1)];

    for idx in 0..16usize {
        let (mut subset, anchor_of) = match mi.subsets {
            2 => {
                let s = ((P2[partition] >> idx) & 1) as usize;
                (s, if s != 0 { A2[partition] } else { 0 })
            }
            3 => {
                let s = ((P3[partition] >> (2 * idx)) & 3) as usize;
                (s, if s != 0 { A3[s - 1][partition] } else { 0 })
            }
            _ => (0, 0),
        };
        let anchor = (idx == anchor_of) as u32;
        let n0 = mi.index_bits[0] - anchor;
        let i0 = bits(block, at[0], n0) as usize;
        at[0] += n0;
        let i1 = if two_index_sets {
            let n1 = mi.index_bits[1] - anchor;
            let v = bits(block, at[1], n1) as usize;
            at[1] += n1;
            v
        } else {
            i0
        };
        let index = [i0, i1];

        let fc = factors[index_selection][index[index_selection]] as u16;
        let fa = factors[1 - index_selection][index[1 - index_selection]] as u16;
        subset *= 2;
        let lerp = |ch: usize, f: u16| -> u8 {
            ((ep[ch][subset] as u16 * (64 - f) + ep[ch][subset + 1] as u16 * f + 32) >> 6) as u8
        };
        let mut rr = lerp(0, fc);
        let mut gg = lerp(1, fc);
        let mut bb = lerp(2, fc);
        let mut aa = lerp(3, fa);
        match rotation {
            1 => std::mem::swap(&mut aa, &mut rr),
            2 => std::mem::swap(&mut aa, &mut gg),
            3 => std::mem::swap(&mut aa, &mut bb),
            _ => {}
        }
        out[idx] = u32::from_le_bytes([bb, gg, rr, aa]);
    }
}

/// What the callers use: this decoder, or the crate's when `OK_SLOW_BC7=1` (the A/B switch, and the way back
/// if these two ever disagree on a real texture).
pub fn decode(data: &[u8], width: usize, height: usize, image: &mut [u32]) -> Result<(), &'static str> {
    static SLOW: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    if *SLOW.get_or_init(|| std::env::var_os("OK_SLOW_BC7").is_some()) {
        return texture2ddecoder::decode_bc7(data, width, height, image);
    }
    decode_bc7(data, width, height, image)
}

/// `texture2ddecoder::decode_bc7`'s contract: 16 bytes a block, blocks left to right then top to bottom,
/// edge blocks clipped to `width`/`height`. The error strings match the crate's so callers can keep theirs.
pub fn decode_bc7(data: &[u8], width: usize, height: usize, image: &mut [u32]) -> Result<(), &'static str> {
    let (bx_n, by_n) = (width.div_ceil(4), height.div_ceil(4));
    if data.len() < bx_n * by_n * 16 { return Err("Not enough data to decode image!"); }
    if image.len() < width * height { return Err("Image buffer is too small!"); }
    let mut texels = [0u32; 16];
    for by in 0..by_n {
        let rows = (height - by * 4).min(4);
        for bx in 0..bx_n {
            let off = (by * bx_n + bx) * 16;
            let block = u128::from_le_bytes(data[off..off + 16].try_into().unwrap());
            decode_block(block, &mut texels);
            let cols = (width - bx * 4).min(4);
            for y in 0..rows {
                let at = (by * 4 + y) * width + bx * 4;
                image[at..at + cols].copy_from_slice(&texels[y * 4..y * 4 + cols]);
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    /// Byte-for-byte against `texture2ddecoder` over random blocks of every mode, including the reserved
    /// all-zero-header block and the anchor-index edge cases every partition has.
    #[test]
    fn bc7_matches_reference_decoder() {
        let mut state = 0x1234_5678_9abc_def0u64;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        // 4x4 one block at a time, plus a clipped image to cover the edge copy.
        for round in 0..20_000 {
            let mut data = [0u8; 16];
            for c in data.chunks_exact_mut(8) {
                c.copy_from_slice(&next().to_le_bytes());
            }
            // Spread the modes evenly instead of leaving it to chance (mode = leading zeros of byte 0).
            let mode = round % 9; // 8 = the reserved block
            data[0] = if mode == 8 { 0 } else { (data[0] & !((1 << (mode + 1)) - 1)) | (1 << mode) };
            let (mut ours, mut theirs) = ([0u32; 16], [0u32; 16]);
            super::decode_bc7(&data, 4, 4, &mut ours).unwrap();
            texture2ddecoder::decode_bc7(&data, 4, 4, &mut theirs).unwrap();
            assert_eq!(ours, theirs, "mode {mode}, block {data:02x?}");
        }
        // A size that is not a multiple of four: the edge blocks must land the same way.
        let mut data = vec![0u8; 16 * 2 * 2];
        for c in data.chunks_exact_mut(8) {
            c.copy_from_slice(&next().to_le_bytes());
        }
        for b in 0..4 {
            data[b * 16] |= 1 << (b % 7);
        }
        let (mut ours, mut theirs) = (vec![0u32; 5 * 7], vec![0u32; 5 * 7]);
        super::decode_bc7(&data, 5, 7, &mut ours).unwrap();
        texture2ddecoder::decode_bc7(&data, 5, 7, &mut theirs).unwrap();
        assert_eq!(ours, theirs);
        assert!(super::decode_bc7(&data[..16], 8, 8, &mut ours).is_err());
    }
}
