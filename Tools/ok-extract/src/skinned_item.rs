//! A prefab with an Animator of its own (the H caress hands, fingers, tongue and toys of `h/common`): skinned meshes
//! on the prefab's own bones, posed by states of its controller and placed by the caller (at a bone of a character,
//! HandCtrl.SetItem parents it there with its local transform kept). Nothing here is specific to hands.
use std::collections::HashMap;
use std::path::Path;

use crate::pose::{Mat4, Skeleton};
use crate::unity::ExtractedMesh;

pub struct SkinnedItem {
    pub meshes: Vec<ExtractedMesh>,
    /// The prefab's transforms at rest (the union of its skinned meshes' bones and their parents).
    rest: Skeleton,
    pose: Skeleton,
    /// Per mesh: the pose skeleton's index of each of its bones (None: a bone the pose does not have, kept at rest).
    bone_map: Vec<Vec<Option<usize>>>,
}

impl SkinnedItem {
    /// From a prefab's meshes (`meshes_for_maindata`, the skinned ones are kept) and its transform tree
    /// (`prefab_hierarchy`): the tree is the item's skeleton. (Two prefabs drawing the same Mesh, p_handR and
    /// p_fingerR, share a mesh's recorded SMR skeleton, so the skeleton comes from the prefab's own tree.)
    pub fn new(meshes: Vec<ExtractedMesh>, tree: &crate::pose::PrefabHierarchy) -> Result<Self, String> {
        let meshes: Vec<ExtractedMesh> = meshes.into_iter().filter(|m| !m.weights.is_empty() && !m.bone_names.is_empty() && m.bind_poses.len() == m.bone_names.len()).collect();
        if meshes.is_empty() { return Err("no skinned mesh".into()); }
        if tree.nodes.is_empty() { return Err("no transform tree".into()); }
        // Node index + 1 as transform id (0 is never a node); every node is a bone of the skeleton, in tree order.
        let tfs: crate::pose::Tfs = tree.nodes.iter().enumerate().map(|(i, n)| (i as i64 + 1, crate::pose::Tf {
            name: n.name.clone(), parent: (n.parent >= 0).then_some(n.parent as i64 + 1), sibling_index: None, pos: n.pos, rot: n.rot, scale: n.scale,
        })).collect();
        let bone_ids: Vec<i64> = (1..=tree.nodes.len() as i64).collect();
        let mut rest = Skeleton { names: Vec::new(), worlds: Vec::new(), rest: Vec::new(), smr_count: bone_ids.len(), tfs, bone_ids, source_mesh: 0 };
        rest.rebuild_worlds();
        rest.rest = rest.worlds.clone();
        let index: HashMap<&str, usize> = rest.names.iter().enumerate().map(|(i, n)| (n.as_str(), i)).collect();
        let bone_map: Vec<Vec<Option<usize>>> = meshes.iter().map(|m| m.bone_names.iter().map(|n| index.get(n.as_str()).copied()).collect()).collect();
        if let Some((m, _)) = meshes.iter().zip(&bone_map).find(|(_, map)| map.iter().any(Option::is_none)) {
            return Err(format!("{}: bones not in the prefab's tree", m.name));
        }
        Ok(Self { meshes, pose: rest.clone(), rest, bone_map })
    }

    /// Poses the item at `t` seconds into `state` (a playable key of `anim_root`, e.g. a `states:layers@` key of one
    /// layer over its controller's base state), with the controller's float parameters.
    pub fn sample(&mut self, anim_root: &Path, state: &str, t: f32, values: &HashMap<String, f32>) {
        self.pose.restore_from(&self.rest);
        crate::anim::apply_clip_at_parameters(anim_root, &mut self.pose, state, t, values);
        self.pose.rebuild_worlds();
    }

    /// The world (prefab space, Unity metres) of a bone of the current pose.
    pub fn bone_world(&self, name: &str) -> Option<Mat4> { self.pose.world(name) }

    /// Per mesh, its vertices and normals in prefab space at the current pose.
    pub fn skinned(&self) -> Vec<(Vec<[f32; 3]>, Vec<[f32; 3]>)> {
        self.meshes.iter().zip(&self.bone_map).map(|(m, map)| {
            let posed: Vec<Mat4> = map.iter().map(|b| b.map(|b| self.pose.worlds[b]).unwrap_or_else(crate::pose::ident)).collect();
            let positions = crate::pose::skin_positions(m, &posed, &m.bind_poses).unwrap_or_else(|| m.positions.clone());
            let normals = crate::pose::skin_normals(m, &posed, &m.bind_poses).unwrap_or_else(|| m.normals.clone());
            (positions, normals)
        }).collect()
    }
}

// ---- The H caress items (HandCtrl) in the base library -------------------------------------------------------------

/// `h/caress_items.json` in the base library: HandCtrl's items (AibuItemObject) with their library model and the
/// controller their Animator plays, and per touch area (aibulayer_00..05: bust L, bust R, crotch, anal, hip L, hip R)
/// which items go where (LayerInfo).
pub const CARESS_ITEMS: &str = "h/caress_items.json";

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct CaressItem {
    pub id: i64,
    /// Game bundle (relative to abdata), its library model (content id) and the prefab.
    pub bundle: String,
    pub model: String,
    pub prefab: String,
    /// The renderer drawn normally and the silhouette one (HData.SimpleBody).
    pub body: String,
    pub silhouette: String,
    /// What it is (AibuItemObjectData.objKind: 0 hand, 1 finger, 2 tongue, 3 massager, 4 vibrator) and which of
    /// HandCtrl's three item slots it takes (setKind: 0 left, 1 right, 2 mouth).
    pub kind: i64,
    pub slot: i64,
    /// The hand's colour is the male's (HandCtrl.Init SetHandColor), when the item takes it (isMaterialGet).
    pub male_colour: bool,
    /// Its Animator's controller: a `states:` source of the animation root and the controller's name in it.
    pub controller_source: String,
    pub controller: String,
    /// The looping sound it plays while in use (HandCtrl.SetItem), when it has one.
    pub sound_bundle: String,
    pub sound: String,
}

/// One action of a touch area's layer: the item's Animator layer and her body's (front and back pose), and her bust
/// or hip dynamics (ChaInfo.DynamicBoneKind, -1 none) switched on or off.
#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct CaressAction { pub front_item: i64, pub front_body: i64, pub back_item: i64, pub back_body: i64, pub dynamic_area: i64, pub enable_dynamic: bool }

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct CaressLayer {
    pub id: i64,
    /// HandCtrl.LayerInfo: useArray, the items (by id, -1 none; two for both hands), the bones of hers they hang on.
    pub use_kind: i64,
    pub items: Vec<i64>,
    pub parents: Vec<String>,
    pub plays: Vec<i64>,
    /// layerActions: 0 idle (resting there), 1 drag (stroking), 2 click.
    pub actions: Vec<CaressAction>,
}

#[derive(Clone, Debug, Default, serde::Serialize, serde::Deserialize)]
pub struct CaressItems { pub items: Vec<CaressItem>, pub areas: Vec<Vec<CaressLayer>> }

fn value_i64(v: Option<&unity_asset_core::UnityValue>) -> i64 { v.and_then(|v| v.as_i64().or_else(|| v.as_bool().map(i64::from))).unwrap_or(-1) }
fn value_str(v: Option<&unity_asset_core::UnityValue>) -> String { v.and_then(|v| v.as_str()).unwrap_or("").to_owned() }
fn field<'a>(v: &'a unity_asset_core::UnityValue, key: &str) -> Option<&'a unity_asset_core::UnityValue> {
    match v { unity_asset_core::UnityValue::Object(o) => o.get(key), _ => None }
}
fn array(v: Option<&unity_asset_core::UnityValue>) -> Vec<unity_asset_core::UnityValue> {
    let v = v.and_then(|v| match v { unity_asset_core::UnityValue::Object(o) => o.get("Array").or(Some(v)), _ => Some(v) });
    v.and_then(|v| v.as_array()).cloned().unwrap_or_default()
}

/// HandCtrl's lists from the game's `h/list` bundles (later bundles override earlier ids, as LoadItemObject).
pub fn caress_lists(game: &Path) -> CaressItems {
    use unity_asset_decode::object::UnityObject;
    let mut items: std::collections::BTreeMap<i64, CaressItem> = Default::default();
    let mut areas: Vec<std::collections::BTreeMap<i64, CaressLayer>> = vec![Default::default(); 6];
    let mut paths: Vec<std::path::PathBuf> = crate::gamefs::read_dir(game.join("abdata/h/list")).map(|rd| rd.flatten().map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("unity3d"))).collect()).unwrap_or_default();
    paths.sort();
    for path in paths {
        let Ok(bytes) = crate::gamefs::read(&path) else { continue };
        let parsed = crate::unity::parse_bundle_cached(bytes);
        parsed.with_serialized(|files| for file in files { for info in file.objects_of_type(114) {
            let Ok(obj) = UnityObject::from_serialized_file(file, &info) else { continue };
            let Some(name) = obj.name() else { continue };
            let rows = obj.class.properties().get("param").and_then(|v| v.as_array()).cloned().unwrap_or_default();
            if name == "AibuItemObject" {
                for r in &rows {
                    let id = value_i64(field(r, "id"));
                    items.insert(id, CaressItem { id, bundle: value_str(field(r, "bundle")), prefab: value_str(field(r, "asset")),
                        body: value_str(field(r, "nomalObj")), silhouette: value_str(field(r, "objSilhouette")), kind: value_i64(field(r, "objKind")),
                        slot: value_i64(field(r, "setKind")), male_colour: value_i64(field(r, "isMaterialGet")) == 1,
                        sound_bundle: value_str(field(r, "bundleSE")), sound: value_str(field(r, "nameSE")), ..Default::default() });
                }
            } else if let Some(area) = name.strip_prefix("aibulayer_").and_then(|n| n.parse::<usize>().ok()).filter(|a| *a < 6) {
                for r in &rows {
                    let id = value_i64(field(r, "id"));
                    let actions = array(field(r, "layerActions")).iter().map(|a| CaressAction {
                        front_item: field(a, "front").map(|f| value_i64(field(f, "item"))).unwrap_or(-1), front_body: field(a, "front").map(|f| value_i64(field(f, "body"))).unwrap_or(-1),
                        back_item: field(a, "back").map(|f| value_i64(field(f, "item"))).unwrap_or(-1), back_body: field(a, "back").map(|f| value_i64(field(f, "body"))).unwrap_or(-1),
                        dynamic_area: value_i64(field(a, "dynamicArea")), enable_dynamic: value_i64(field(a, "enableDynamic")) == 1 }).collect();
                    areas[area].insert(id, CaressLayer { id, use_kind: value_i64(field(r, "useKind")),
                        items: array(field(r, "idObjects")).iter().map(|v| v.as_i64().unwrap_or(-1)).collect(),
                        parents: array(field(r, "nameParents")).iter().map(|v| v.as_str().unwrap_or("").to_owned()).collect(),
                        plays: array(field(r, "plays")).iter().map(|v| v.as_i64().unwrap_or(-1)).collect(), actions });
                }
            }
        }});
    }
    CaressItems { items: items.into_values().collect(), areas: areas.into_iter().map(|a| a.into_values().collect()).collect() }
}

/// The controller an item prefab's Animator plays: (`states:` source of its bundle, controller name), found by the
/// Animator's controller reference among the controllers of `h/anim/parts`.
fn item_controller(game: &Path, parsed: &crate::unity::ParsedBundle, prefab: &str) -> Option<(String, String)> {
    use unity_asset_decode::object::UnityObject;
    let pid = |v: Option<&unity_asset_core::UnityValue>| v.and_then(|v| field(v, "m_PathID")).and_then(|v| v.as_i64()).unwrap_or(0);
    let wanted = parsed.with_serialized(|files| {
        let roots: Vec<i64> = files.iter().flat_map(|f| f.objects_of_type(1).into_iter().filter_map(|i| UnityObject::from_serialized_file(f, &i).ok()
            .filter(|o| o.name().as_deref() == Some(prefab)).map(|_| i.path_id))).collect();
        files.iter().find_map(|f| f.objects_of_type(95).into_iter().find_map(|i| {
            let a = UnityObject::from_serialized_file(f, &i).ok()?;let p = a.class.properties();
            roots.contains(&pid(p.get("m_GameObject"))).then(|| pid(p.get("m_Controller"))).filter(|c| *c != 0)
        }))
    })?;
    let mut bundles: Vec<std::path::PathBuf> = crate::gamefs::read_dir(game.join("abdata/h/anim/parts")).ok()?.flatten().map(|e| e.path())
        .filter(|p| p.extension().is_some_and(|e| e.eq_ignore_ascii_case("unity3d"))).collect();
    bundles.sort();
    for path in bundles {
        let Ok(bytes) = crate::gamefs::read(&path) else { continue };
        let found = crate::unity::parse_bundle_cached(bytes).with_serialized(|files| files.iter().find_map(|f| f.objects_of_type(91).into_iter()
            .find(|i| i.path_id == wanted).and_then(|i| UnityObject::from_serialized_file(f, &i).ok()?.name())));
        if let Some(name) = found {
            let rel = path.strip_prefix(game.join("abdata")).ok()?.to_string_lossy().replace('\\', "/");
            return Some((format!("states:{rel}"), name));
        }
    }
    None
}

/// `--oklib h-items <lib>`: HandCtrl's items into the base library: each prefab's meshes, transform tree and what an
/// item session reads (as `studio-nodes` records a Studio item), and `h/caress_items.json`.
pub fn record_caress_items(game: &Path, lib: &Path) -> Result<usize, String> {
    let mut lists = caress_lists(game);
    if lists.items.is_empty() { return Err("no AibuItemObject in h/list".into()); }
    let store = crate::oklib::activate(lib, crate::oklib::Mode::Record)?;
    crate::oklib::CONVERTING.store(true, std::sync::atomic::Ordering::Relaxed);
    crate::gamefs::activate(crate::gamefs::Mode::Record, game, lib)?;
    let mut bundles: std::collections::BTreeMap<String, Vec<usize>> = Default::default();
    for (i, item) in lists.items.iter().enumerate() { bundles.entry(item.bundle.clone()).or_default().push(i); }
    let mut recorded = 0;
    let result = (|| -> Result<(), String> {
        for (bundle, indices) in &bundles {
            let bytes = crate::gamefs::read(game.join("abdata").join(bundle)).map_err(|e| format!("{bundle}: {e}"))?;
            let model = crate::oklib::id_hex(&crate::oklib::content_id(&bytes));
            let parsed = crate::unity::parse_bundle_cached(bytes);
            parsed.configure_game_references(game);
            for &i in indices {
                let p = lists.items[i].prefab.clone();
                let tree = parsed.prefab_hierarchy(&p);
                if tree.nodes.is_empty() { return Err(format!("{bundle} {p}: no transform tree")); }
                parsed.meshes_for_maindata(&p); parsed.meshes_for_maindata_including_disabled(&p);
                parsed.prefab_renderer_settings(&p); parsed.prefab_lightmaps(&p);
                parsed.prefab_render_textures(&p); parsed.prefab_reflection_probes(&p); parsed.prefab_animated_materials(&p); parsed.prefab_renderer_visibility(&p);
                parsed.prefab_sun_light(&p); parsed.prefab_light_modes(&p); parsed.prefab_light_cookies(&p); parsed.prefab_light_cookie_maps(&p);
                parsed.prefab_water_materials(&p); parsed.prefab_standard_materials(&p); parsed.prefab_standard_material_lists(&p);
                let (source, controller) = item_controller(game, &parsed, &p).ok_or_else(|| format!("{bundle} {p}: its Animator's controller not found in h/anim/parts"))?;
                let item = &mut lists.items[i];
                item.model = model.clone(); item.controller_source = source; item.controller = controller;
                recorded += 1;
            }
            parsed.record_cube_slot_atlases();
            crate::unity::clear_bundle_cache();
        }
        Ok(())
    })();
    store.flush();
    let saved = crate::gamefs::save(lib);
    crate::oklib::deactivate();
    crate::gamefs::deactivate();
    result?; saved?;
    let out = lib.join(CARESS_ITEMS);
    if let Some(dir) = out.parent() { std::fs::create_dir_all(dir).map_err(|e| e.to_string())?; }
    std::fs::write(&out, serde_json::to_vec_pretty(&lists).map_err(|e| e.to_string())?).map_err(|e| format!("{}: {e}", out.display()))?;
    Ok(recorded)
}

/// An item from the base library (`record_caress_items`), as a preview session draws it (`okmodel_view`).
pub fn open_library(lib: &Path, model: &str, prefab: &str) -> Result<SkinnedItem, String> {
    let id = crate::oklib::id_from_hex_pub(model).ok_or("bad model id")?;
    crate::okmodel_view::with_library(lib, || {
        let view = crate::okmodel_view::ModelView::open(lib, id)?;
        SkinnedItem::new(view.prefab_meshes(prefab, false), &view.hierarchy(prefab))
    })
}

impl SkinnedItem {
    /// A caress item from the base library and the preview session that draws it (the same prefab, okmodel_view).
    pub fn new_session_pair(lib: &Path, item: &CaressItem) -> Result<(SkinnedItem, crate::session::OkSession), String> {
        let id = crate::oklib::id_from_hex_pub(&item.model).ok_or("bad model id")?;
        crate::okmodel_view::with_library(lib, || {
            let view = crate::okmodel_view::ModelView::open(lib, id)?;
            let skinned = SkinnedItem::new(view.prefab_meshes(&item.prefab, false), &view.hierarchy(&item.prefab))?;
            Ok((skinned, view.prefab_session(&item.prefab, false)?))
        })
    }
    /// Writes the current pose's vertices into the session's parts of the same names (a preview session of the same
    /// prefab, `ok_okmodel_open_session`); the count of parts written.
    pub fn write_session(&self, session: &mut crate::session::OkSession) -> usize {
        let skinned = self.skinned();
        let mut written = 0;
        for (m, (positions, normals)) in self.meshes.iter().zip(skinned) {
            for part in session.parts.iter_mut().filter(|p| p.name == m.name && p.positions.len() == positions.len()) {
                part.positions.clone_from(&positions);
                if part.normals.len() == normals.len() { part.normals.clone_from(&normals); }
                written += 1;
            }
        }
        written
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The bones the caress items hang on are in a character session's skeleton (bone_world, ok_bone_world_matrix).
    #[test]
    #[ignore = "needs a local OK card and the base library"]
    fn caress_parents_are_character_bones() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Content");
        let card = std::fs::read_dir(root.join("CharacterCards/CrowdAPNG")).unwrap().flatten().map(|e| e.path()).find(|p| p.extension().is_some_and(|e| e == "png")).unwrap();
        let s = crate::oklib::open_test_card(&card, 0).unwrap();
        let lists: CaressItems = serde_json::from_slice(&std::fs::read(root.join("IndependentResources/base_v1").join(CARESS_ITEMS)).unwrap()).unwrap();
        let parents: std::collections::BTreeSet<&String> = lists.areas.iter().flatten().flat_map(|l| &l.parents).filter(|p| !p.is_empty()).collect();
        let missing: Vec<&&String> = parents.iter().filter(|p| crate::bone_world(s.body_skel.as_ref(), s.head_skel.as_ref(), p).is_none()).collect();
        println!("parents {parents:?} missing {missing:?}");
        assert!(missing.is_empty(), "missing {missing:?}");
    }

    /// From the base library alone (`--oklib h-items` recorded, `paired` converted): every caress item opens with its
    /// controller, poses on each layer its areas use, and writes its vertices into its preview session's parts.
    #[test]
    #[ignore = "needs the local base library with h/caress_items.json"]
    fn library_items_pose_into_their_sessions() {
        let lib = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Content/IndependentResources/base_v1");
        let anim = crate::paired_library::library_root(&lib).expect("paired root");
        let lists: CaressItems = serde_json::from_slice(&std::fs::read(lib.join(CARESS_ITEMS)).unwrap()).unwrap();
        let _ = crate::anim::disk_cache::library_misses();
        for item in &lists.items {
            let mut s = SkinnedItem::new_session_pair(&lib, item).unwrap_or_else(|e| panic!("{}: {e}", item.prefab));
            let layers: std::collections::BTreeSet<i64> = lists.areas.iter().flatten().filter(|l| l.items.contains(&item.id))
                .flat_map(|l| l.actions.iter().flat_map(|a| [a.front_item, a.back_item])).filter(|i| *i > 0).collect();
            let base = crate::anim::controller_base_state(&anim, &item.controller_source, &item.controller).expect("base state");
            // At rest the skinned vertices are the session's own (the same space).
            let before: Vec<Vec<[f32; 3]>> = s.1.parts.iter().map(|p| p.positions.clone()).collect();
            s.0.write_session(&mut s.1);
            let off = before.iter().zip(&s.1.parts).flat_map(|(a, p)| a.iter().zip(&p.positions).map(|(a, b)| (0..3).map(|i| (a[i] - b[i]).abs()).fold(0f32, f32::max))).fold(0f32, f32::max);
            assert!(off < 1e-4, "{}: rest skin {off} m off the session", item.prefab);
            for layer in &layers {
                let key = crate::anim::controller_layer_state(&anim, &item.controller_source, &item.controller, *layer as usize)
                    .unwrap_or_else(|| panic!("{} layer {layer}", item.controller));
                s.0.sample(&anim, &key, 0.3, &HashMap::from([("speedHand".to_string(), 1.)]));
                assert!(s.0.write_session(&mut s.1) > 0, "{} wrote its session", item.prefab);
            }
            println!("{} ({}): {} layers, base {base}", item.prefab, item.controller, layers.len());
        }
        let misses = crate::anim::disk_cache::library_misses();
        assert!(misses.is_empty(), "library misses {misses:?}");
    }

    /// Against the installed game: p_handR on the right-hand controller's first chest layer moves its fingers.
    #[test]
    #[ignore = "needs D:/KoikatuSunshine"]
    fn game_hand_plays_its_controller_layer() {
        let game = Path::new("D:/KoikatuSunshine");
        let bytes = crate::gamefs::read(&game.join("abdata/h/common/01.unity3d")).unwrap();
        let parsed = crate::unity::parse_bundle_cached(bytes);
        let (meshes, _) = parsed.meshes_for_maindata("p_handR");
        println!("meshes {:?}", meshes.iter().map(|m| (&m.name, m.positions.len(), m.bone_names.len(), m.smr_skel.is_some())).collect::<Vec<_>>());
        let mut item = SkinnedItem::new(meshes, &parsed.prefab_hierarchy("p_handR")).unwrap();
        println!("bones {:?}", item.rest.names);
        let source = "states:h/anim/parts/01_00.unity3d";
        println!("base {:?}", crate::anim::controller_base_state(game, source, "khp_te_itemR"));
        let layered = crate::anim::controller_layer_state(game, source, "khp_te_itemR", 1).expect("layer 1 over the base");
        println!("layered {layered}");
        let rest = item.skinned();
        let bind_err = rest[0].0.iter().zip(&item.meshes[0].positions).map(|(a, b)| ((a[0]-b[0]).powi(2)+(a[1]-b[1]).powi(2)+(a[2]-b[2]).powi(2)).sqrt()).fold(0f32, f32::max);
        println!("rest skin vs mesh positions {bind_err:.5} m");
        let mut moved = 0f32;
        for t in [0., 0.25, 0.5, 1.0] {
            item.sample(game, &layered, t, &HashMap::from([("speedHand".to_string(), 1.), ("Breast".to_string(), 0.5)]));
            let changed: Vec<&str> = item.pose.tfs.iter().filter(|(id, tf)| item.rest.tfs.get(id).is_some_and(|r| r.rot != tf.rot || r.pos != tf.pos)).map(|(_, tf)| tf.name.as_str()).collect();
            println!("changed {changed:?}");
            if t == 0. { let mut tree: Vec<String> = item.rest.tfs.values().map(|tf| format!("{}<{}", tf.name, tf.parent.and_then(|p| item.rest.tfs.get(&p)).map(|p| p.name.as_str()).unwrap_or("-"))).collect(); tree.sort(); println!("tree {tree:?}"); }
            let now = item.skinned();
            let d = rest[0].0.iter().zip(&now[0].0).map(|(a, b)| ((a[0]-b[0]).powi(2)+(a[1]-b[1]).powi(2)+(a[2]-b[2]).powi(2)).sqrt()).fold(0f32, f32::max);
            let (lo, hi) = crate::pose::aabb(&now[0].0);
            println!("t {t}: max move from rest {d:.4} m, bounds {lo:?} {hi:?}");
            moved = moved.max(d);
        }
        assert!(moved > 0.005, "the hand moves");
        // The converted animation root (base library `paired`) answers the same states without a bundle.
        let lib = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Content/IndependentResources/base_v1/paired");
        let _ = crate::anim::disk_cache::library_misses();
        let values = HashMap::from([("speedHand".to_string(), 1.), ("Breast".to_string(), 0.5)]);
        let lib_key = crate::anim::controller_layer_state(&lib, source, "khp_te_itemR", 1).expect("the layer state in the library");
        assert_eq!(lib_key, layered);
        item.sample(game, &layered, 0.4, &values);let a = item.skinned();
        item.sample(&lib, &lib_key, 0.4, &values);let b = item.skinned();
        let d = a[0].0.iter().zip(&b[0].0).map(|(a, b)| ((a[0]-b[0]).powi(2)+(a[1]-b[1]).powi(2)+(a[2]-b[2]).powi(2)).sqrt()).fold(0f32, f32::max);
        let misses = crate::anim::disk_cache::library_misses();
        println!("library vs bundle {d:.6} m, misses {misses:?}");
        assert!(misses.is_empty() && d < 1e-4, "the library poses the item like the bundle");
    }
}
