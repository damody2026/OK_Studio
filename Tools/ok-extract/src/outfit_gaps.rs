//! What each outfit of a card asks for and nothing provides: a zipmod without the item, or an id no list has. Her slot
//! then stays empty, and what is left can be a bald girl with nothing on (jeanne_alter's outfit 1 names eight items its
//! mod does not have). Read only: the card is not changed, and the outfit can still be worn.
use crate::card::CardInfo;
use crate::list::ChaListCatalog;
use serde::Serialize;
use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};

const CLOTHES_PART: [&str; 9] = ["top", "bottom", "bra", "shorts", "gloves", "pantyhose", "socks", "shoes_inner", "shoes_outer"];

#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Gap {
    /// A slot of `CLOTHES_PART`, or "top_sub", "hair", "hair_accessory", "accessory".
    pub part: String,
    pub category: i32,
    pub id: i32,
    /// The mod the card names; empty: a plain id.
    pub guid: String,
}

#[derive(Serialize, Clone, Debug)]
pub struct OutfitGaps {
    pub outfit: i32,
    /// She would show too much or lose her hair (`is_severe`).
    pub severe: bool,
    pub gaps: Vec<Gap>,
}

/// Nothing over her body (no top, and no bottom either asked for or found), or her hair gone.
pub fn is_severe(gaps: &[Gap], bottom_asked: bool) -> bool {
    let has = |part: &str| gaps.iter().any(|g| g.part == part);
    (has("top") && (has("bottom") || !bottom_asked)) || has("hair") || has("hair_accessory")
}

fn gap(part: &str, category: i32, id: i32, guid: &str) -> Gap { Gap { part: part.to_string(), category, id, guid: guid.to_string() } }

/// The same lookups the open makes for this outfit (`lists_stage`, the hair and accessory passes).
pub(crate) fn of_outfit(card: &CardInfo, outfit: i32, vanilla: &ChaListCatalog, mods: &ChaListCatalog,
    index: &HashMap<String, PathBuf>) -> Vec<Gap> {
    let mut gaps = Vec::new();
    let slots = crate::select_card_clothes(card, outfit, vanilla, mods, index);
    for (kind, name) in crate::CLOTHES_PROP.iter().enumerate() {
        if slots.get(kind).is_some_and(Option::is_some) { continue; }
        let prop = format!("outfit{outfit}.ChaFileClothes.{name}");
        let resolve = card.resolves.iter().find(|r| r.property == prop);
        let id = card.clothes_ids.get(kind).copied().unwrap_or(0);
        if resolve.is_none() && id == 0 { continue; }
        let category = if kind < 7 { 105 + kind as i32 } else { 112 };
        gaps.push(gap(CLOTHES_PART[kind], category, resolve.map_or(id, |r| r.slot), resolve.map_or("", |r| r.mod_id.as_str())));
    }
    let top_type = slots.first().and_then(Option::as_ref).and_then(|(entry, _, _)| entry.info("Kind").parse().ok()).unwrap_or(0);
    if top_type == 1 || top_type == 2 {
        let subparts = crate::select_card_top_subparts(card, outfit, top_type, vanilla, mods, index);
        for (kind, sub) in subparts.iter().enumerate() {
            let id = card.sub_parts_id.get(kind).copied().unwrap_or(0);
            if sub.is_none() && id != 0 { gaps.push(gap("top_sub", (if top_type == 1 { 200 } else { 210 }) + kind as i32, id, "")); }
        }
    }
    let mut lists = HashMap::new();
    for (i, &id) in card.hair_ids.iter().enumerate() {
        if id == 0 { continue; }
        let category = 101 + i as i32;
        let resolve = card.resolves.iter().find(|r| (r.slot == id || r.local_slot == id) && (101..=104).contains(&r.category_no));
        let guid = resolve.map_or("", |r| r.mod_id.as_str());
        let zip = resolve.and_then(|r| crate::guid_path(index, &r.mod_id));
        if crate::lookup_entry(vanilla, &mut lists, zip.map(PathBuf::as_path), guid, category, id, id).is_none() {
            gaps.push(gap("hair", category, id, guid));
        }
    }
    let part = |slot: Option<usize>, name: &str| if slot.is_some_and(|s| card.hair_acc.contains_key(&(outfit, s as i32)))
        || name.to_ascii_lowercase().contains("hair") { "hair_accessory" } else { "accessory" };
    let want = crate::outfit_prefix(outfit);
    let mut resolved = HashSet::new();
    for r in &card.resolves {
        if !crate::is_mesh_category(r.category_no) || !crate::role_for_category(r.category_no, &r.property).starts_with("acc") { continue; }
        let property = r.property.to_ascii_lowercase();
        if property.contains("outfit") && !property.contains(&want) { continue; }
        let slot = crate::accessory_slot_from_property(&r.property);
        resolved.extend(slot);
        if crate::is_dummy_part("", Some(&r.name)) { continue; }
        let zip = crate::guid_path(index, &r.mod_id);
        if crate::lookup_entry(vanilla, &mut lists, zip.map(PathBuf::as_path), &r.mod_id, r.category_no, r.slot, r.local_slot).is_none() {
            gaps.push(gap(part(slot, &r.name), r.category_no, r.slot, &r.mod_id));
        }
    }
    for (slot, a) in card.accessory.iter().enumerate() {
        if a.type_id == 120 || !crate::is_mesh_category(a.type_id) || resolved.contains(&slot) { continue; }
        if !crate::role_for_category(a.type_id, "").starts_with("acc") { continue; }
        if vanilla.get(a.type_id, a.id).is_none() && mods.get(a.type_id, a.id).is_none() {
            gaps.push(gap(part(Some(slot), ""), a.type_id, a.id, ""));
        }
    }
    gaps
}

/// One line per gap: what `lookup_entry` says for an item a zipmod lacks, for all the ways a slot stays empty. To stderr
/// and to the game's log, which stderr does not reach.
pub(crate) fn log(card: &str, outfit: i32, gaps: &[Gap]) {
    for g in gaps {
        let line = format!("ok-extract: ERROR {card} outfit {outfit} item missing part={} cat={} id={} guid={}", g.part, g.category, g.id, g.guid);
        eprintln!("{line}");
        crate::ffi::ffi_log(0, &line);
    }
}

/// Every outfit of a card, opened as the reader opens it: an OK card over its own pack, a card under a game folder with
/// that folder's mods. An original card under a base library names zipmods this cannot see: nothing is reported for it.
pub fn scan(game: &Path, card: &Path) -> Result<Vec<OutfitGaps>, String> {
    let root = crate::oklib::root_for_card(game, Some(card));
    let library = crate::oklib::ensure_library(&root)?;
    if library && !crate::oklib::is_library_card(card) { return Ok(Vec::new()); }
    let _pack = if library { crate::oklib::mount_card_pack(card)? } else { None };
    let bytes = crate::card::card_file_bytes(card).map_err(|e| format!("{}: {e}", card.display()))?;
    let vanilla = crate::list::load_characustom_dir_shared(&root.join("abdata/list/characustom"));
    let mods_dir = root.join("mods");
    let mods = crate::list::load_mods_catalog_shared(&mods_dir);
    let mut outfits = Vec::new();
    for outfit in 0..7 {
        let Ok(mut info) = crate::card::parse_card_bytes_mode(&bytes, outfit, false) else { break };
        // The open drops what a StripAll migration removes before it asks which archives hold the card's GUIDs
        // (extract_session_from_info): asked with those GUIDs too, an OK card has no answer and every mod item reads as
        // missing (拾光.png: kks.co_bra_00 in outfit 3).
        crate::mods::apply_strip_all_migrations(&root, &mut info);
        let wanted: HashSet<String> = info.resolves.iter().map(|r| r.mod_id.clone()).collect();
        let index = if wanted.is_empty() { HashMap::new() } else { crate::mods::find_guids(&mods_dir, Some(&wanted)) };
        let gaps = of_outfit(&info, outfit, &vanilla, &mods, &index);
        log(&card.display().to_string(), outfit, &gaps);
        let prop = format!("outfit{outfit}.ChaFileClothes.{}", crate::CLOTHES_PROP[1]);
        let bottom_asked = info.clothes_ids.get(1).is_some_and(|id| *id != 0) || info.resolves.iter().any(|r| r.property == prop);
        outfits.push(OutfitGaps { outfit, severe: is_severe(&gaps, bottom_asked), gaps });
    }
    Ok(outfits)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn gaps(parts: &[&str]) -> Vec<Gap> { parts.iter().map(|p| gap(p, 0, 1, "")).collect() }
    #[test]
    fn severe_is_her_body_bare_or_her_hair_gone() {
        assert!(is_severe(&gaps(&["top", "bottom"]), true));
        assert!(is_severe(&gaps(&["top"]), false), "a dress that was all she wore");
        assert!(!is_severe(&gaps(&["top"]), true), "her skirt is still on");
        assert!(!is_severe(&gaps(&["gloves", "socks", "accessory"]), true));
        assert!(is_severe(&gaps(&["hair"]), true));
        assert!(is_severe(&gaps(&["hair_accessory"]), true));
        assert!(!is_severe(&[], false));
    }
}
