//! What the worn models allow, for the property editor: the maker hides the colour layers, options, sleeve types and
//! emblems a garment's `ChaClothesComponent` lacks (`CvsClothes.CheckUseColor`／`ChangeEmblemVisible`) and the accessory
//! colours its `ChaAccessoryComponent` lacks (`CvsAccessory.ChangeUseColorVisible`). Rows get `available` (false: the
//! game ignores the value for this model) and colour rows `default` (the model's `defMainColor0x`, 初期設定).
//! A garment or accessory whose model is not found gets nothing: the row stays as it was.
//!
//! `available:false` means the maker does not show the row; it is never a write limit (an edit is taken as usual). The
//! value stays in the card, and switching back to a model that has the thing must find it again — refusing the edit
//! while the row is hidden would leave a value that can never be changed back. Pages work the same way: `pages` below
//! is what the maker lets you click (`CustomChangeClothesMenu.InteractableSetting`), not what may be written.
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

/// Which clothes pages the maker lets you click, from the list entries (no model needed):
/// - `bot`: off when the top's `Coordinate` is 2 (a one-piece; `ChaControl.notBot`).
/// - `bra`: off when the top's `NotBra` is 1; a sailor top (Kind 1) takes it from its sub-part a instead, a jacket
///   (Kind 2) from sub-part a or b (`ChangeClothesTop`／`ChangeClothesTopParts` set `notBra` in that order).
/// - `shorts`: off when the bra's `Coordinate` is "2" (`ChangeClothesBra` sets `notShorts`).
/// - `male_bra`: the bra page exists for a male character only when the list has a bra whose `Sex` is not 3 or 99
///   (`CustomBase.IsMaleCoordinateBra`; a female always has it).
/// Display only: what the card holds for a page that is off is kept and editable (see the module comment).
fn pages(selection:&J,items:&[Item])->J{
 let info=|key:&str,field:&str|worn_item(selection,items,key).map(|i|i.entry.info(field).trim().to_string());
 let is=|v:Option<String>,want:&str|v.is_some_and(|v|v==want);
 let top_kind:i32=info("clothes0","Kind").and_then(|k|k.parse().ok()).unwrap_or(0);
 let not_bot=is(info("clothes0","Coordinate"),"2");
 let not_bra=match top_kind {
  1=>is(info("sub200","NotBra").or_else(||info("clothes0","NotBra")),"1"),
  2=>is(info("sub210","NotBra"),"1")||is(info("sub211","NotBra"),"1"),
  _=>is(info("clothes0","NotBra"),"1"),
 };
 let not_shorts=is(info("clothes2","Coordinate"),"2");
 let male_bra=items.iter().any(|i|i.entry.category_no==107&&!matches!(i.entry.info("Sex").trim().parse::<i32>(),Ok(3|99)));
 json!({"bot":!not_bot,"bra":!not_bra,"shorts":!not_shorts,"male_bra":male_bra,"top_kind":top_kind})
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
 // Accessories: useColor01..03 and rendAlpha (the 4th colour) of the worn item's ChaAccessoryComponent; whether the
 // parent and move rows are offered (`CvsAccessory.ChangeParentAndMoveSettingVisible`): not for an empty slot (type
 // 120), nor when the item's list says `HideHair==1` or `Parent=="null"`; the second move group only when the model
 // has an `N_move2` node. All of these are display only (see the module comment).
 let mut accessories=serde_json::Map::new();
 for slot in 0..20usize {
  let Some(item)=(121..=130).find_map(|cat|worn_item(&selection,&items,&format!("accessory{slot}_{cat}"))) else{
   set(&format!("accessory.parts.{slot}.parentKey"),false,None);set(&format!("accessory.parts.{slot}.addMove."),false,None);
   accessories.insert(slot.to_string(),json!({"parent_editable":false}));continue};
  let parent_editable=!(item.entry.info("HideHair").trim()=="1"||item.entry.info("Parent").trim()=="null");
  let shared=source(root,item);
  let use_color=shared.as_ref().and_then(|s|crate::unity::parse_bundle_ref(&s.0).accessory_color_use(&item.entry.main_data)).map(|u|[u.use01,u.use02,u.use03,!u.alpha.is_empty()]);
  if let Some(use_color)=use_color {for (c,on) in use_color.iter().enumerate(){set(&format!("accessory.parts.{slot}.color.{c}."),*on,None);}}
  // None: the model was recorded before node names were kept for accessories; the second group's rows stay as they were.
  let move2=shared.as_ref().and_then(|s|crate::unity::prefab_node_names_recorded(&s.0,&item.entry.main_data)).map(|n|n.contains("N_move2"));
  // `defColor01..04` for the colour reset button only (`CvsAccessory.btnInitColor`). Not put on the rows as `default`:
  // reading a card never falls back to it. null: not recorded for this model, or the model has no ChaAccessoryComponent.
  let default_colors=shared.as_ref().and_then(|s|crate::unity::accessory_default_colors_recorded(&s.0,&item.entry.main_data)).flatten();
  set(&format!("accessory.parts.{slot}.parentKey"),parent_editable,None);
  for i in 0..3 {set(&format!("accessory.parts.{slot}.addMove.2.{i}."),parent_editable,None);}
  if let Some(m)=move2 {for i in 3..6 {set(&format!("accessory.parts.{slot}.addMove.2.{i}."),parent_editable&&m,None);}}
  else if !parent_editable {for i in 3..6 {set(&format!("accessory.parts.{slot}.addMove.2.{i}."),false,None);}}
  accessories.insert(slot.to_string(),json!({"use_color":use_color,"parent_editable":parent_editable,"move2":move2,"default_colors":default_colors}));
 }
 Ok(json!({"clothes":summary,"accessories":accessories,"pages":pages(&selection,&items)}))
}

#[cfg(test)]
mod tests {
 use super::*;
 fn item(key:&str,cat:i32,info:&[(&str,&str)])->Item{
  Item{key:key.into(),guid:String::new(),source:String::new(),entry:crate::list::ListEntry{category_no:cat,extra:info.iter().map(|(k,v)|(k.to_string(),v.to_string())).collect(),..Default::default()}}
 }
 fn wear(pairs:&[(&str,&str)])->J{J::Object(pairs.iter().map(|(k,i)|(k.to_string(),json!({"item":i}))).collect())}

 #[test]
 fn pages_follow_the_list_entries_as_change_clothes_sets_them(){
  let items=vec![
   item("onepiece",105,&[("Coordinate","2"),("NotBra","1"),("Kind","0")]),
   item("sailor",105,&[("Kind","1"),("NotBra","0")]),item("sailor_a",106,&[("NotBra","1")]),
   item("jacket",105,&[("Kind","2"),("NotBra","1")]),item("jacket_a",106,&[("NotBra","0")]),item("jacket_b",106,&[("NotBra","1")]),
   item("swim",107,&[("Coordinate","2"),("Sex","3")]),item("bra",107,&[("Sex","99")]),
  ];
  let p=pages(&wear(&[("clothes0","onepiece"),("clothes2","swim")]),&items);
  assert_eq!((p["bot"].as_bool(),p["bra"].as_bool(),p["shorts"].as_bool()),(Some(false),Some(false),Some(false)));
  // A sailor top takes NotBra from sub-part a, not from itself.
  let p=pages(&wear(&[("clothes0","sailor"),("sub200","sailor_a")]),&items);assert_eq!(p["bra"],false);assert_eq!(p["bot"],true);
  // A jacket's own NotBra does not count; sub-part b does.
  let p=pages(&wear(&[("clothes0","jacket"),("sub210","jacket_a")]),&items);assert_eq!(p["bra"],true);
  let p=pages(&wear(&[("clothes0","jacket"),("sub210","jacket_a"),("sub211","jacket_b")]),&items);assert_eq!(p["bra"],false);
  // Every bra is Sex 3 or 99: no male bra page.
  assert_eq!(p["male_bra"],false);
  let mut more=items.clone();more.push(item("male",107,&[("Sex","0")]));
  assert_eq!(pages(&wear(&[]),&more)["male_bra"],true);
  assert_eq!(pages(&wear(&[]),&more)["shorts"],true);
 }
}
