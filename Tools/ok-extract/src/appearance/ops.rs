//! Composite editor operations: one action a person takes in the original editor, expanded into the whole set of
//! fields that action writes, so the card is patched **once**.
//!
//! Why this exists. In the original (`ChaCustom/CvsHair.cs`) moving the hair colour picker is not one field: with the
//! four settings of `CustomBase.CustomSettingSave` — `hairSameSetting`, `hairAutoSetting`, `hairOutlineSetting`,
//! `hairGlossSetting`, **all four `true` in a fresh install** — it writes every hair slot's `baseColor`,
//! `startColor`, `endColor`, `outlineColor` and `glossColor`: up to 4 slots × 5 colours from one drag. Our editor's
//! property panel writes the one float the slider owns, so a card edited here never looks like a card edited there.
//! That is the real gap on the hair pages, not "the colours cannot be read" (the walk has always exposed them).
//!
//! Why one patch and not a burst of sets. Each `properties_apply` rewrites and reopens the card, so sending the
//! sixteen edits one at a time is both sixteen reopens and fifteen visible half-states (base changed, gradient not
//! yet). The expansion here returns the edits; the caller hands them to `patch_properties` in a single call.
//!
//! The constants are the original's and are not interchangeable: the automatic gradient is **-0.3 / +0.15**, while
//! "take the eyebrow (or underhair) colour as the hair colour" is **-0.2 / +0.1**. They look like the same idea.
//! Outline is **-0.4**, gloss **+0.3**, and both reset buttons recompute from each slot's *own* base colour.
//! `Docs/CHARACTER_EDITOR_PARITY_HAIR_EYES.md` §7 lists every write set with its source line.
use super::properties;
use serde_json::{Value as J, json};
use std::collections::BTreeMap;

/// Unity's `Color.RGBToHSV` / `Color.HSVToRGB` for the one thing the editor does with them: keep hue and saturation,
/// move value. Writing it as "scale the channels" (what `properties::restyle` does for the street's salon) gives a
/// different colour as soon as the hue is not grey, which is why this is here rather than reusing that.
fn shift_value(rgb: [f64; 3], by: f64) -> [f64; 3] {
    let (r, g, b) = (rgb[0], rgb[1], rgb[2]);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let v = (max + by).clamp(0.0, 1.0);
    if max <= 0.0 { return [v, v, v] } // black has no hue to keep: the original's HSVToRGB(h, s, v) returns grey
    let s = (max - min) / max;
    let h = if max == min { 0.0 } else if max == r { (g - b) / (max - min) / 6.0 }
        else if max == g { (2.0 + (b - r) / (max - min)) / 6.0 }
        else { (4.0 + (r - g) / (max - min)) / 6.0 };
    let h = if h < 0.0 { h + 1.0 } else { h };
    hsv_to_rgb(h, s, v)
}

fn hsv_to_rgb(h: f64, s: f64, v: f64) -> [f64; 3] {
    let i = (h * 6.0).floor();
    let f = h * 6.0 - i;
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - f * s), v * (1.0 - (1.0 - f) * s));
    match (i as i64).rem_euclid(6) {
        0 => [v, t, p], 1 => [q, v, p], 2 => [p, v, t],
        3 => [p, q, v], 4 => [t, p, v], _ => [v, p, q],
    }
}

/// Every editable property's current value, by key. The expansion reads the card through the same catalogue the UI
/// does, so an op can only touch fields the editor already admits to owning.
struct Now(BTreeMap<String, f64>);

impl Now {
    fn read(original: &[u8], outfit: usize) -> Result<Self, String> {
        let rows = properties::catalog_properties(original, outfit)?;
        Ok(Now(rows.iter().filter_map(|p| Some((p["key"].as_str()?.to_string(), p["value"].as_f64()?))).collect()))
    }

    fn has(&self, key: &str) -> bool { self.0.contains_key(key) }

    /// A colour as the card stores it: four keys `<prefix>.0..3` (RGBA). Absent channels are not invented.
    fn colour(&self, prefix: &str) -> Option<[f64; 3]> {
        let c = |i: usize| self.0.get(&format!("{prefix}.{i}")).copied();
        Some([c(0)?, c(1)?, c(2)?])
    }

    /// The hair slots this card actually has. The original has four (`ChaFileDefine.HairKind`: back, front, side,
    /// option) and asks the enum for the count; we ask the card, so a card with more parts is dyed whole instead of
    /// its first four.
    fn hair_slots(&self) -> Vec<usize> {
        (0..16).filter(|i| self.has(&format!("hair.parts.{i}.baseColor.0"))).collect()
    }
}

/// `{"op": …}` → the edits it writes. The caller patches them in one go; a later op in the same list overwrites an
/// earlier one's field, in list order, exactly as clicking twice would.
pub(super) fn expand(original: &[u8], outfit: usize, ops: &[J]) -> Result<Vec<J>, String> {
    if ops.is_empty() || ops.len() > 64 { return Err("動作清單數量錯誤".into()) }
    let now = Now::read(original, outfit)?;
    let mut out: BTreeMap<String, f64> = BTreeMap::new();
    for op in ops {
        let name = op["op"].as_str().ok_or("缺少動作名稱")?;
        match name {
            "hair_base_color" => hair_base_color(&now, op, &mut out)?,
            "hair_color_to_eyebrow_and_underhair" => {
                // The original takes slot 0's base colour, not the page you are on (CvsHair.cs btnReflectColor).
                let c = now.colour("hair.parts.0.baseColor").ok_or("卡片沒有頭髮顏色欄位")?;
                set_colour(&now, "face.eyebrowColor", c, &mut out);
                set_colour(&now, "body.underhairColor", c, &mut out);
            }
            "hair_from_eyebrow" | "hair_from_underhair" => {
                let from = if name == "hair_from_eyebrow" { "face.eyebrowColor" } else { "body.underhairColor" };
                let c = now.colour(from).ok_or("卡片沒有這個顏色欄位")?;
                for slot in now.hair_slots() {
                    set_colour(&now, &format!("hair.parts.{slot}.baseColor"), c, &mut out);
                    set_colour(&now, &format!("hair.parts.{slot}.startColor"), shift_value(c, -0.2), &mut out);
                    set_colour(&now, &format!("hair.parts.{slot}.endColor"), shift_value(c, 0.1), &mut out);
                }
            }
            "hair_reset_outline" | "hair_reset_gloss" => {
                let (field, by) = if name == "hair_reset_outline" { ("outlineColor", -0.4) } else { ("glossColor", 0.3) };
                for slot in now.hair_slots() {
                    // Each slot from its own base colour, not from the page's: the reset buttons walk the array.
                    let base = now.colour(&format!("hair.parts.{slot}.baseColor")).ok_or("卡片沒有頭髮顏色欄位")?;
                    set_colour(&now, &format!("hair.parts.{slot}.{field}"), shift_value(base, by), &mut out);
                }
            }
            "eye_copy" => {
                // `PupilInfo.Copy`: seven fields in one write, so "copy the left eye" cannot leave the gradient behind.
                let from = op["from"].as_u64().filter(|i| *i < 2).ok_or("眼睛來源只能是 0 或 1")? as usize;
                let to = 1 - from;
                for field in ["baseColor", "subColor"] {
                    let c = now.colour(&format!("face.pupil.{from}.{field}")).ok_or("卡片沒有瞳孔顏色欄位")?;
                    set_colour(&now, &format!("face.pupil.{to}.{field}"), c, &mut out);
                }
                for field in ["id", "gradMaskId", "gradBlend", "gradOffsetY", "gradScale"] {
                    let key = format!("face.pupil.{from}.{field}");
                    let v = *now.0.get(&key).ok_or("卡片沒有瞳孔欄位")?;
                    out.insert(format!("face.pupil.{to}.{field}"), v);
                }
            }
            _ => return Err(format!("不支援的動作：{name}")),
        }
    }
    Ok(out.into_iter().map(|(key, value)| json!({"key": key, "value": value})).collect())
}

/// The colour picker on a hair page, with the four settings of the original. Each flag defaults to **true**, as in a
/// fresh install: a caller that sends none gets the original's behaviour, not the single-field one.
fn hair_base_color(now: &Now, op: &J, out: &mut BTreeMap<String, f64>) -> Result<(), String> {
    let rgba = op["rgba"].as_array().ok_or("缺少顏色")?;
    if rgba.len() < 3 { return Err("顏色需要三或四個數值".into()) }
    let mut c = [0.0; 3];
    for (i, slot) in c.iter_mut().enumerate() {
        let n = rgba[i].as_f64().ok_or("顏色格式錯誤")?;
        if !(0.0..=1.0).contains(&n) { return Err("顏色超出 0..1".into()) }
        *slot = n;
    }
    let flag = |key: &str| op[key].as_bool().unwrap_or(true);
    let (same, auto, outline, gloss) = (flag("same"), flag("auto"), flag("outline"), flag("gloss"));
    let slots: Vec<usize> = if same { now.hair_slots() } else {
        let slot = op["slot"].as_u64().unwrap_or(0) as usize;
        if !now.has(&format!("hair.parts.{slot}.baseColor.0")) { return Err("卡片沒有這個頭髮槽位".into()) }
        vec![slot]
    };
    if slots.is_empty() { return Err("卡片沒有頭髮顏色欄位".into()) }
    for slot in slots {
        let at = |field: &str| format!("hair.parts.{slot}.{field}");
        set_colour(now, &at("baseColor"), c, out);
        if auto {
            set_colour(now, &at("startColor"), shift_value(c, -0.3), out);
            set_colour(now, &at("endColor"), shift_value(c, 0.15), out);
        }
        if outline { set_colour(now, &at("outlineColor"), shift_value(c, -0.4), out) }
        if gloss { set_colour(now, &at("glossColor"), shift_value(c, 0.3), out) }
    }
    Ok(())
}

/// Write R, G and B, and leave alpha alone — the original's colour windows for hair keep it (`_useAlpha: false`),
/// and a colour whose channels this card does not have is skipped rather than created.
fn set_colour(now: &Now, prefix: &str, rgb: [f64; 3], out: &mut BTreeMap<String, f64>) {
    for (i, v) in rgb.iter().enumerate() {
        let key = format!("{prefix}.{i}");
        if now.has(&key) { out.insert(key, *v); }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Hue and saturation survive a value shift; the original clamps rather than wrapping, so a bright colour's
    /// "+0.3 gloss" stops at white instead of coming back round as black.
    #[test]
    fn a_value_shift_keeps_the_hue_and_clamps() {
        let brown = [0.4, 0.25, 0.1];
        let darker = shift_value(brown, -0.3);
        assert!(darker.iter().zip(brown).all(|(a, b)| *a < b + 1e-9), "{darker:?}");
        let hue = |c: [f64; 3]| (c[1] - c[2]) / (c[0] - c[2]);
        assert!((hue(darker) - hue(brown)).abs() < 1e-6, "hue moved: {darker:?}");
        assert_eq!(shift_value([1.0, 1.0, 1.0], 0.3), [1.0, 1.0, 1.0]);
        assert_eq!(shift_value([0.0, 0.0, 0.0], -0.4), [0.0, 0.0, 0.0]);
    }

    /// Black keeps no hue in the original either (`RGBToHSV` of black gives s = 0), so lightening it must give grey
    /// and not a colour out of nowhere.
    #[test]
    fn black_lightens_to_grey() {
        let grey = shift_value([0.0, 0.0, 0.0], 0.3);
        assert!((grey[0] - 0.3).abs() < 1e-9 && grey[0] == grey[1] && grey[1] == grey[2], "{grey:?}");
    }
}
