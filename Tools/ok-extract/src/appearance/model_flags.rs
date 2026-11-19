//! What the worn models allow, for the property editor: the maker hides the colour layers, options, sleeve types and
//! emblems a garment's `ChaClothesComponent` lacks (`CvsClothes.CheckUseColor`／`ChangeEmblemVisible`) and the accessory
//! colours its `ChaAccessoryComponent` lacks (`CvsAccessory.ChangeUseColorVisible`). Rows get `available` (false: the
//! game ignores the value for this model) and colour rows `default` (the model's `defMainColor0x`, 初期設定).
//! A garment or accessory whose model is not found gets nothing: the row stays as it was.
use super::*;
use crate::unity::ClothesOptionGroups;

struct Garment {groups:ClothesOptionGroups,top_kind:i32}

fn worn_item<'a>(selection:&J,items:&'a [Item],key:&str)->Option<&'a Item>{
 let item=selection.get(key)?.get("item")?.as_str()?;items.iter().find(|i|i.key==item)
}
fn source(root:&Path,item:&Item)->Option<std::sync::Arc<(crate::unity::SourceBytes,Option<PathBuf>)>>{
 let zip=(!item.source.is_empty()).then(||PathBuf::from(&item.source));
 crate::accessories::accessory_bundle_shared(root,zip.as_deref(),&item.entry)
}
fn garment(root:&Path,item:&Item)->Option<Garment>{
 if item.entry.main_data.is_empty()||item.entry.main_data.eq_ignore_ascii_case("p_dummy"){return None}
 let shared=source(root,item)?;
 // None: a model recorded before this query (an older OK card's own model), so its switches are unknown. The rows stay
 // as they were. Told by the store saying "not recorded", never from the value: a garment whose groups are legitimately
 // all defaults (no option, no sleeves, no colour layer) must still have its rows marked.
 let groups=crate::unity::clothes_option_groups_recorded(&shared.0,&item.entry.main_data)?;
 Some(Garment{groups,top_kind:item.entry.info("Kind").trim().parse().unwrap_or(0)})
}

/// Annotate `props` (from `catalog_properties`) and return the per-garment summary (`clothes_model`).
pub(super) fn annotate(root:&Path,cache:&Path,original:&[u8],outfit:usize,props:&mut [J])->Result<J,String>{
 let items=catalog(root,cache)?;let targets=targets();
 let selection=current_selection(original,outfit,&targets,&items)?;
 let mut set=|prefix:&str,available:bool,default:Option<[f32;4]>|{
  for p in props.iter_mut(){let Some(key)=p["key"].as_str().map(str::to_string) else{continue};if !key.starts_with(prefix){continue}
   p["available"]=json!(available);
   if let Some(d)=default {if key.starts_with(&format!("{prefix}baseColor.")) {let c:usize=key.rsplit('.').next().and_then(|c|c.parse().ok()).unwrap_or(0);p["default"]=json!(d.get(c).copied().unwrap_or(1.0));}}}
 };
 let mut summary=serde_json::Map::new();
 let subs:Vec<Garment>=(0..3).filter_map(|i|{
  // The sub-parts the top uses: sailor 200..202 or jacket 210..212, whichever category the selection resolved.
  [200,210].iter().find_map(|base|worn_item(&selection,&items,&format!("sub{}",base+i))).and_then(|it|garment(root,it))
 }).collect();
 for kind in 0..9usize {
  let Some(g)=worn_item(&selection,&items,&format!("clothes{kind}")).and_then(|it|garment(root,it)) else{continue};
  let sailor_or_jacket=kind==0&&matches!(g.top_kind,1|2);
  // CheckUseColor: a sailor／jacket top takes the colour layers (and the 4th, rendAccessory) and emblems of its sub-parts;
  // the option and sleeve toggles are hidden then.
  let (mut use_color,mut emblem)=([false;4],[false;2]);
  if sailor_or_jacket {for s in &subs {for i in 0..3{use_color[i]|=s.groups.use_color[i];}use_color[3]|=s.groups.has_accessory_renderer;for i in 0..2{emblem[i]|=s.groups.emblem[i];}}}
  else {for i in 0..3{use_color[i]=g.groups.use_color[i];}emblem=g.groups.emblem;}
  let opt=if sailor_or_jacket{[false;2]}else{g.groups.opt_present};
  let sleeves=kind==0&&!sailor_or_jacket&&g.groups.sleeves_present.iter().any(|b|*b);
  for i in 0..4 {set(&format!("clothes.parts.{kind}.colorInfo.{i}."),use_color[i],(i<3&&!sailor_or_jacket).then(||g.groups.def_colors[i]));}
  match kind {
   2=>{for i in 0..2{set(&format!("clothes.hideBraOpt.{i}"),opt[i],None);set(&format!("clothes.parts.2.hideOpt.{i}"),false,None);}}
   3=>{for i in 0..2{set(&format!("clothes.hideShortsOpt.{i}"),opt[i],None);set(&format!("clothes.parts.3.hideOpt.{i}"),false,None);}}
   _=>{for i in 0..2{set(&format!("clothes.parts.{kind}.hideOpt.{i}"),opt[i],None);}}
  }
  if kind==0 {set("clothes.parts.0.sleevesType",sleeves,None);}
  summary.insert(kind.to_string(),json!({"use_color":use_color,"option":opt,"sleeves":if kind==0{json!(g.groups.sleeves_present)}else{json!([false,false,false])},
   "emblem":emblem,"default_colors":g.groups.def_colors,"top_kind":if kind==0{json!(g.top_kind)}else{J::Null}}));
 }
 // Accessories: useColor01..03 and rendAlpha (the 4th colour) of the worn item's ChaAccessoryComponent.
 let mut accessories=serde_json::Map::new();
 for slot in 0..20usize {
  let Some(item)=(121..=130).find_map(|cat|worn_item(&selection,&items,&format!("accessory{slot}_{cat}"))) else{continue};
  let Some(shared)=source(root,item) else{continue};
  let Some(u)=crate::unity::parse_bundle_ref(&shared.0).accessory_color_use(&item.entry.main_data) else{continue};
  let use_color=[u.use01,u.use02,u.use03,!u.alpha.is_empty()];
  for (c,on) in use_color.iter().enumerate(){set(&format!("accessory.parts.{slot}.color.{c}."),*on,None);}
  accessories.insert(slot.to_string(),json!({"use_color":use_color}));
 }
 Ok(json!({"clothes":summary,"accessories":accessories}))
}
