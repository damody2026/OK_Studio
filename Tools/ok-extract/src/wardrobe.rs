//! Her clothes changed on the same model (one-on-one: no model is replaced once the scene is up, user 2026-11-07).
//! What an outfit puts on her, its clothes and accessories, sits at the end of her parts (`wardrobe_prepare`). Another
//! outfit or garment state is opened elsewhere as a donor and cut down to just that (`wardrobe_strip`); `wardrobe_swap`
//! trades the two ends, so the donor then holds what she took off. The rig is the body, head and hair trees
//! (`skel_export::build`): clothes add no bone to it, so her skeleton, pose and animation are not touched.
use crate::session::{OkSession, SessionPart};

/// Parts that come with an outfit.
fn worn(part: &SessionPart) -> bool {
    part.role.starts_with("clothes") || part.role == "accessory"
}

/// Her main body, whose `_AlphaMask` cuts away the skin her clothes cover.
fn body_index(parts: &[SessionPart]) -> Option<usize> {
    parts.iter().enumerate().filter(|(_, p)| p.role == "body" && p.skel_kind == 1 && p.runtime_accessory.is_none())
        .max_by_key(|(_, p)| p.rest_positions.len()).map(|(index, _)| index)
}

fn white_mask() -> Option<Vec<u8>> {
    crate::texture_bake::encode_png(&image::RgbaImage::from_pixel(4, 4, image::Rgba([255, 255, 255, 255])))
}

fn reorder<T>(values: &mut Vec<T>, order: &[usize]) {
    let mut old: Vec<Option<T>> = std::mem::take(values).into_iter().map(Some).collect();
    *values = order.iter().filter_map(|&index| old.get_mut(index).and_then(Option::take)).collect();
}

impl OkSession {
    /// The first part an outfit put on her.
    pub(crate) fn wardrobe_first(&self) -> usize {
        self.parts.iter().position(worn).unwrap_or(self.parts.len())
    }

    /// Her worn parts to the end, each group in its order. Part indices are only stable after this.
    fn wardrobe_partition(&mut self) {
        let mut order: Vec<usize> = (0..self.parts.len()).filter(|&i| !worn(&self.parts[i])).collect();
        order.extend((0..self.parts.len()).filter(|&i| worn(&self.parts[i])));
        if order.iter().enumerate().all(|(at, index)| at == *index) { return; }
        reorder(&mut self.parts, &order);
        if let Some(export) = &mut self.skel_export {
            reorder(&mut export.part_morphs, &order);
            reorder(&mut export.part_rest, &order);
            reorder(&mut export.part_ref_normals, &order);
            reorder(&mut export.part_ref_tangents, &order);
            reorder(&mut export.part_bone_idx, &order);
        }
        for (part, _) in &mut self.face_runtime.iris_base_settings {
            if let Some(at) = order.iter().position(|index| index == part) { *part = at; }
        }
        crate::assign_draw_layers(&mut self.parts);
    }

    /// As she opens, before anything reads her part indices. Her body always cuts by a mask, white where nothing is
    /// covered: a material cannot go from opaque to masked under a live model.
    pub(crate) fn wardrobe_prepare(&mut self) {
        self.wardrobe_partition();
        // Her body's tables are kept by its address (belly_bulge): a change of clothes must not move her parts.
        self.parts.reserve(256);
        let Some(body) = body_index(&self.parts) else { return };
        let part = &mut self.parts[body];
        if part.alpha_mask.is_none() { part.alpha_mask = white_mask(); }
        if part.alpha_mask.is_some() && part.blend != "masked" {
            part.blend = "masked".into();
            part.blend_c = std::ffi::CString::new("masked").unwrap_or_default();
        }
        self.wardrobe_mask_for(1); // made here, off the game thread; the state change finds it in its cache
    }

    /// The mask her body takes with her top in this state: ChaControl sets `_alpha_a`/`_alpha_b` for it, Koikano/main_skin
    /// is drawn from a mask with those channels already whitened (`body_mask_for_alpha_state`).
    pub(crate) fn wardrobe_mask_for(&self, top_state: u8) -> Option<Vec<u8>> {
        let mask = self.parts[body_index(&self.parts)?].alpha_mask.as_deref()?;
        crate::clothes_texture::body_mask_for_alpha_state(mask, crate::clothes_texture::clothes_alpha_state(top_state))
    }

    /// A donor: only what the outfit puts on her stays, with its export, and the mask it gives her body.
    pub(crate) fn wardrobe_strip(&mut self) {
        self.wardrobe_partition();
        self.ensure_skel_export();
        let first = self.wardrobe_first();
        self.wardrobe_body_mask = body_index(&self.parts).and_then(|body| self.parts[body].alpha_mask.take());
        self.parts.drain(..first);
        if let Some(export) = &mut self.skel_export {
            export.part_morphs.drain(..first);
            export.part_rest.drain(..first);
            export.part_ref_normals.drain(..first);
            export.part_ref_tangents.drain(..first);
            export.part_bone_idx.drain(..first);
        }
    }

    /// Everything but `wardrobe_swap`'s moves, so a refused donor leaves her as she was.
    fn wardrobe_check(&self, donor: &OkSession) -> Result<usize, String> {
        let first = self.wardrobe_first();
        if self.parts[first..].iter().any(|p| !worn(p)) { return Err("wardrobe: her parts were not prepared".into()); }
        if donor.parts.iter().any(|p| !worn(p)) { return Err("wardrobe: the donor was not stripped".into()); }
        let live = self.skel_export.as_ref().ok_or("wardrobe: she has no rig")?;
        let other = donor.skel_export.as_ref().ok_or("wardrobe: the donor has no rig")?;
        if live.name_to_idx != other.name_to_idx || live.bones.len() != other.bones.len()
            || live.bones.iter().zip(&other.bones).any(|(a, b)| a.name != b.name || a.parent != b.parent) {
            return Err("wardrobe: the donor's rig differs from hers".into());
        }
        let count = |e: &crate::skel_export::SkelExport| [e.part_morphs.len(), e.part_rest.len(), e.part_ref_normals.len(), e.part_ref_tangents.len(), e.part_bone_idx.len()];
        if count(live) != [self.parts.len(); 5] || count(other) != [donor.parts.len(); 5] {
            return Err("wardrobe: part exports do not match the parts".into());
        }
        Ok(first)
    }

    /// She takes off what she wears and puts on the donor's; the donor keeps what she took off. Her clothes chains start
    /// again from her current pose on the next frame (`update_clothes_dynamics` settles new ones).
    pub(crate) fn wardrobe_swap(&mut self, donor: &mut OkSession) -> Result<(), String> {
        let first = self.wardrobe_check(donor)?;
        let removed = self.parts.split_off(first);
        self.parts.append(&mut donor.parts);
        donor.parts = removed;
        donor.reset_dynamic_accessories();
        crate::assign_draw_layers(&mut self.parts);
        crate::assign_draw_layers(&mut donor.parts);
        let (live, other) = (self.skel_export.as_mut().unwrap(), donor.skel_export.as_mut().unwrap());
        fn trade<T>(live: &mut Vec<T>, other: &mut Vec<T>, first: usize) {
            let removed = live.split_off(first);
            live.append(other);
            *other = removed;
        }
        trade(&mut live.part_morphs, &mut other.part_morphs, first);
        trade(&mut live.part_rest, &mut other.part_rest, first);
        trade(&mut live.part_ref_normals, &mut other.part_ref_normals, first);
        trade(&mut live.part_ref_tangents, &mut other.part_ref_tangents, first);
        trade(&mut live.part_bone_idx, &mut other.part_bone_idx, first);
        std::mem::swap(&mut self.clothes_dynamics, &mut donor.clothes_dynamics);
        self.clothes_dynamic_runtime = None;
        donor.clothes_dynamic_runtime = None;
        self.wardrobe_quick_settle = true;
        self.hidden_parts.clear();
        std::mem::swap(&mut self.active_shoe_meta, &mut donor.active_shoe_meta);
        std::mem::swap(&mut self.accessory_context, &mut donor.accessory_context);
        if let Some(body) = body_index(&self.parts) {
            let next = donor.wardrobe_body_mask.take().or_else(white_mask);
            donor.wardrobe_body_mask = std::mem::replace(&mut self.parts[body].alpha_mask, next);
        }
        crate::belly_bulge::clothes_changed();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Every outfit of every card in OK_WARDROBE_CARDS opens with all its garment states and trades with her first outfit.
    #[test]
    #[ignore = "reads the local base library and cards"]
    fn every_outfit_opens_with_all_states() {
        if std::env::var("OK_BASE_LIBRARY").is_err() { std::env::set_var("OK_BASE_LIBRARY", "E:/OpenKoikatsu/Content/IndependentResources/base_v1"); }
        std::env::set_var("OK_NOCACHE", "1");
        let dir = std::env::var("OK_WARDROBE_CARDS").unwrap_or_else(|_| "E:/OpenKoikatsu/Content/CharacterCards/StreetHeroines".into());
        let mut failed = Vec::new();
        let mut opened = 0;
        for entry in std::fs::read_dir(&dir).unwrap() {
            let card = entry.unwrap().path();
            if card.extension().is_none_or(|e| !e.eq_ignore_ascii_case("png")) { continue; }
            let root = crate::oklib::root_for_card(std::path::Path::new("X:/NoGame"), Some(&card));
            let _all = crate::profile::scope(&[(crate::unity::ALL_STATES_SWITCH, if std::env::var_os("OK_WARDROBE_PLAIN").is_some() { None } else { Some("1") })]);
            let mut live: Option<OkSession> = None;
            for outfit in 0..crate::tree_answers::outfit_count(&std::fs::read(&card).unwrap()) as i32 {
                match crate::session::open(&root, Some(&card), outfit) {
                    Err(e) => failed.push(format!("{} outfit {outfit}: {}", card.display(), e.chars().take(1500).collect::<String>())),
                    Ok(mut session) => {
                        opened += 1;
                        let marked = session.parts.iter().filter(|p| p.runtime_textures.keys().any(|k| k.starts_with("#state:"))).count();
                        eprintln!("{} outfit {outfit}: {} parts, {marked} with state nodes", card.file_name().unwrap().to_string_lossy(), session.parts.len());
                        match &mut live {
                            None => { session.wardrobe_prepare(); session.ensure_skel_export(); live = Some(session); }
                            Some(her) => { session.wardrobe_strip(); if let Err(e) = her.wardrobe_swap(&mut session) { failed.push(format!("{} outfit {outfit}: {e}", card.display())); } }
                        }
                    }
                }
            }
        }
        eprintln!("opened {opened}, failed {}", failed.len());
        assert!(failed.is_empty(), "{}", failed.join("\n"));
    }

    #[test]
    fn reorder_follows_the_order() {
        let mut values = vec!['a', 'b', 'c', 'd'];
        reorder(&mut values, &[0, 2, 1, 3]);
        assert_eq!(values, ['a', 'c', 'b', 'd']);
    }
}
