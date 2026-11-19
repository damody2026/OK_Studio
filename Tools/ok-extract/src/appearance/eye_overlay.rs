//! The eye pages' overlay textures (Material Editor `MaterialTexturePropertyList`).
//!
//! `properties` skips every field whose name contains `texture`, so the overlay textures the maker
//! assigned to the eye materials had no read or write path at all. These two actions are that path:
//! `eye_overlays` lists the slots and the candidates a thumbnail grid can draw, `eye_overlay_set`
//! writes one slot. Nothing here guesses a shader property name: the slots come from the opened
//! session's own materials (`MeshMaterial::tex_slots`), the current values from the card's own rows.
use super::*;

/// Head materials this page covers. `kage` (the eyeline shadow) is drawn with the eye, so the page
/// shows it too; everything else on the face belongs to another page.
const MATERIAL_HINTS:&[(&str,&str)]=&[("hitomi","瞳孔"),("pupil","瞳孔"),("sirome","眼白"),("eyeline","眼線"),("kage","眼線陰影")];
/// Friendly names for the texture properties a maker actually replaces here. An unlisted property
/// is still listed (with its raw name): the material decides what exists, not this table.
const PROPERTY_LABELS:&[(&str,&str)]=&[("maintex","本體貼圖"),("gradmask","漸層遮罩"),("gradationmask","漸層遮罩"),
 ("overtex1","上高光覆蓋"),("overtex","上高光覆蓋"),("eyehighlight","上高光覆蓋"),("eyehiuptex","上高光覆蓋"),
 ("overtex2","下高光覆蓋"),("eyehighlight2","下高光覆蓋"),("eyehidowntex","下高光覆蓋"),
 ("expression","表情遮罩"),("alphamask","透明遮罩"),("normalmap","法線貼圖"),("normalmask","法線遮罩"),("detailmask","細節遮罩")];

fn label_for(material:&str,property:&str)->String{
 let m=material.to_ascii_lowercase();let p=property.trim_start_matches('_').to_ascii_lowercase();
 let part=MATERIAL_HINTS.iter().find(|(hint,_)|m.contains(hint)).map(|(_,label)|*label).unwrap_or("眼部");
 let prop=PROPERTY_LABELS.iter().find(|(name,_)|*name==p).map(|(_,label)|*label).unwrap_or("");
 if prop.is_empty(){format!("{part} {}",property.trim_start_matches('_'))}else{format!("{part}{prop}")}
}
/// The eye shader's own texture slots, for a mesh whose bundle material did not come through.
/// `declared:false` on such a slot says so: the row can still be written, as the maker writes it.
const FALLBACK_PROPERTIES:&[(&str,&[&str])]=&[("hitomi",&["MainTex","overtex1","overtex2","expression"]),
 ("pupil",&["MainTex","overtex1","overtex2"]),("sirome",&["MainTex"]),("eyeline",&["MainTex"]),("kage",&["MainTex"])];
/// Whether this open path draws a row written here (`head_body.rs`). The head takes MainTex, the
/// masks and the normal maps on every material; the extra overlay slots are skipped on the iris,
/// whose highlights come from the card's own hlUp/hlDown types instead (`appearance` 410/411).
/// A slot that is not consumed is still listed, with `applies:false`, rather than silently ignored.
fn applies(material:&str,property:&str)->bool{
 let p=property.trim_start_matches('_').to_ascii_lowercase();
 if matches!(p.as_str(),"maintex"|"colormask"|"detailmask"|"linemask"|"normalmap"|"normalmask"|"alphamask"|"glassramp"){return true;}
 !crate::card::me_mat_key(material).contains("hitomi")
}
/// One `MaterialTexturePropertyList` row, in the shape the maker writes it. Head materials are
/// object type 4, coordinate 0, slot 0 (`clear_material_conflicts` scopes them the same way);
/// rows of other kinds are kept only so a candidate can say what else in the card uses it.
struct Row {kind:i64,tex_id:i64,material:String,property:String}
fn me_plugin_key(kkex:&Value)->Option<String>{
 kkex.as_map()?.iter().map(|(k,_)|k.as_str().unwrap_or("")).find(|k|k.to_ascii_lowercase().contains("materialeditor")).map(str::to_owned)
}
const DEFAULT_ME_KEY:&str="com.deathweasel.bepinex.materialeditor";
/// The plugin's own data map, past the `[version, data]` wrapper the maker writes.
fn plugin_data<'a>(kkex:&'a mut Value,key:&str)->Result<&'a mut Value,String>{
 let Value::Map(map)=kkex else{return Err("KKEx 區塊格式錯誤".into())};
 let plugin=map.iter_mut().find(|(k,_)|k.as_str()==Some(key)).map(|(_,v)|v).ok_or("卡片沒有 Material Editor 資料")?;
 Ok(match plugin{Value::Array(a)=>a.get_mut(1).ok_or("Material Editor 資料不足")?,v=>v})
}
fn binary<'a>(data:&'a mut Value,key:&str)->Option<&'a mut Vec<u8>>{
 let Value::Map(map)=data else{return None};
 match map.iter_mut().find(|(k,_)|k.as_str()==Some(key)).map(|(_,v)|v){Some(Value::Binary(b))=>Some(b),_=>None}
}
fn rows_of(data:&mut Value)->Vec<Row>{
 let Some(raw)=binary(data,"MaterialTexturePropertyList") else{return Vec::new()};
 let Ok(Value::Array(rows))=decode(raw) else{return Vec::new()};
 rows.iter().filter_map(|row|{
  let get=|key:&str|row.as_map().and_then(|m|m.iter().find(|(k,_)|k.as_str()==Some(key)).map(|(_,v)|v));
  Some(Row{kind:get("ObjectType").and_then(Value::as_i64).unwrap_or(4),
   tex_id:get("TexID").and_then(Value::as_i64)?,
   material:get("MaterialName").and_then(Value::as_str)?.to_owned(),
   property:get("Property").and_then(Value::as_str)?.to_owned()})
 }).collect()
}
fn dictionary(data:&mut Value)->BTreeMap<i64,Vec<u8>>{
 let Some(raw)=binary(data,"TextureDictionary") else{return BTreeMap::new()};
 let Ok(Value::Map(entries))=decode(raw) else{return BTreeMap::new()};
 entries.into_iter().filter_map(|(k,v)|{let id=k.as_i64()?;
  let bytes=match v{Value::Binary(b)=>b,Value::String(s)=>s.into_bytes(),_=>return None};
  bytes.starts_with(b"\x89PNG").then_some((id,bytes))}).collect()
}
/// PNG dimensions from the IHDR; a candidate grid wants them and decoding the whole image does not.
fn png_size(png:&[u8])->Option<(u32,u32)>{
 if png.len()<24||!png.starts_with(b"\x89PNG"){return None;}
 let n=|i:usize|u32::from_be_bytes([png[i],png[i+1],png[i+2],png[i+3]]);
 (&png[12..16]==b"IHDR").then(||(n(16),n(20)))
}
fn same(a:&str,b:&str)->bool{a.trim_start_matches('_').eq_ignore_ascii_case(b.trim_start_matches('_'))}
fn export(dir:&Path,name:&str,png:&[u8])->Result<PathBuf,String>{
 fs::create_dir_all(dir).map_err(|e|e.to_string())?;let path=dir.join(format!("{name}.png"));
 // Content-addressed names: an unchanged texture is written once and the UI can cache it by path.
 if !path.ok_exists(){fs::write(&path,png).map_err(|e|e.to_string())?;}Ok(path)
}

/// `{"action":"eye_overlays","card":<png>,"outfit":0,"library":["<folder>",...]}`
/// -> `{"slots":[...],"candidates":[...],"current":{slot_key:candidate_id|null}}`.
pub(super) fn list(root:&Path,r:&J)->Result<J,String>{
 let card=Path::new(text(r,"card")?);let outfit=r["outfit"].as_u64().unwrap_or(0) as i32;
 let original=crate::gamefs::read(card).map_err(|e|e.to_string())?;
 let cache=Path::new(text(r,"cache")?);let dir=cache.join("eye_overlays");
 let mut blocks=blocks_from_card(&original)?;if let Some(metadata)=original_metadata(root,cache,&original)?{blocks.insert("KKEx".into(),metadata);}
 let mut kkex=blocks.get("KKEx").map(|b|decode(b)).transpose()?.unwrap_or(Value::Map(Vec::new()));
 let key=me_plugin_key(&kkex);
 let (rows,dict)=match key.as_deref(){
  Some(key)=>{let data=plugin_data(&mut kkex,key)?;(rows_of(data),dictionary(data))},
  None=>(Vec::new(),BTreeMap::new())};
 // The session is the only honest source for which materials this card's eyes actually have and
 // which texture properties their shaders declare. A modded eye keeps its own names.
 let session=crate::session::open(&crate::oklib::root_for_card(root,Some(card)),Some(card),outfit)?;
 let mut slots=Vec::new();let mut seen=std::collections::HashSet::new();let mut skipped=Vec::new();
 for part in session.parts.iter().filter(|p|p.role=="head"){
  // The maker writes a face row against MaterialEditor's own canonical name (`cf_m_hitomi_00`),
  // which is not always the bundle material's name — `me_texture` resolves both, so both are offered
  // here, the canonical one first because that is the name a written row must carry.
  let mut names=crate::material_editor::me_face_mat_names(&part.name);
  if let Some(material)=part.source_material.as_ref(){
   let key=crate::card::me_mat_key(&material.name);
   if !key.is_empty()&&!names.iter().any(|n|crate::card::me_mat_key(n)==key){names.push(material.name.clone());}
  }
  let Some(name)=names.into_iter().find(|n|{let k=crate::card::me_mat_key(n);MATERIAL_HINTS.iter().any(|(hint,_)|k.contains(hint))}) else{
   if part.source_material.is_some()||!part.name.is_empty(){skipped.push(json!({"part":part.name,
    "material":part.source_material.as_ref().map(|m|m.name.clone())}));}
   continue};
  let lower=crate::card::me_mat_key(&name);
  // Property names come from the material the card actually draws. Without one (a mesh whose
  // bundle material did not survive), fall back to the slots the original eye shader declares.
  let declared:Vec<(String,bool)>=match part.source_material.as_ref().filter(|m|!m.tex_slots.is_empty()){
   Some(material)=>material.tex_slots.iter().map(|(p,_)|(p.clone(),true)).collect(),
   None=>FALLBACK_PROPERTIES.iter().filter(|(hint,_)|lower.contains(hint)).flat_map(|(_,props)|props.iter().map(|p|(p.to_string(),false))).collect()};
  for (property,real) in declared {
   if !seen.insert((lower.clone(),property.trim_start_matches('_').to_ascii_lowercase())){continue;}
   let row=rows.iter().find(|row|row.kind==4&&crate::card::me_mat_key(&row.material)==lower&&same(&row.property,&property));
   let png=row.and_then(|row|dict.get(&row.tex_id));
   let size=png.and_then(|png|png_size(png));
   // Material Editor stores the shader property without its leading underscore ("MainTex"), and
   // every head lookup keys on that form. The listed `property` is therefore the one to pass back.
   let property=property.trim_start_matches('_').to_string();
   slots.push(json!({"key":format!("{lower}/{}",property.to_ascii_lowercase()),
    "label":label_for(&name,&property),"material":name,"property":property,"part":part.name,
    "applies":applies(&name,&property),
    "shader":part.source_material.as_ref().map(|m|m.shader.clone()).unwrap_or_default(),"declared":real,
    "present":png.is_some(),"tex_id":row.map(|row|row.tex_id),
    "bytes":png.map(|png|png.len()),"width":size.map(|s|s.0),"height":size.map(|s|s.1),
    "png":png.map(|png|export(&dir,&hash(png)[..16],png)).transpose()?,
    "candidate":png.map(|png|format!("card:{}",&hash(png)[..16]))}));
  }
 }
 // Candidates for the grid: every texture this card already carries, plus the PNG files in the
 // folders the request names. "" is always valid too and means "no override" (clear the slot).
 // `eye` says whether the card uses it on one of the materials above, so a grid can show those
 // first (they are sorted first here) and keep the rest — the clothes textures — behind a filter.
 let mut candidates=Vec::new();let mut known=std::collections::HashSet::new();
 for (id,png) in &dict {
  let digest=hash(png);let cid=format!("card:{}",&digest[..16]);if !known.insert(cid.clone()){continue;}
  let mine=|row:&&Row|row.kind==4&&MATERIAL_HINTS.iter().any(|(hint,_)|crate::card::me_mat_key(&row.material).contains(hint));
  let used:Vec<String>=rows.iter().filter(|row|row.tex_id==*id).map(|row|if mine(&row){label_for(&row.material,&row.property)}
   else{format!("{} {}",row.material,row.property.trim_start_matches('_'))}).collect();
  let eye=rows.iter().filter(|row|row.tex_id==*id).any(|row|mine(&&row));
  let size=png_size(png);
  candidates.push(json!({"id":cid,"name":if used.is_empty(){format!("卡片內貼圖 #{id}")}else{used.join("、")},
   "source":"card","guid":"","eye":eye,"bytes":png.len(),"width":size.map(|s|s.0),"height":size.map(|s|s.1),
   "png":export(&dir,&digest[..16],png)?,"used_by":used}));
 }
 candidates.sort_by_key(|c|!c["eye"].as_bool().unwrap_or(false));
 for folder in r["library"].as_array().map(Vec::as_slice).unwrap_or(&[]).iter().filter_map(J::as_str){
  let Ok(entries)=crate::gamefs::read_dir(Path::new(folder)) else{continue};
  let mut files:Vec<PathBuf>=entries.flatten().map(|e|e.path()).filter(|p|p.extension().is_some_and(|e|e.eq_ignore_ascii_case("png"))).collect();
  files.sort();
  for file in files {
   let Ok(png)=crate::gamefs::read(&file) else{continue};
   if !png.starts_with(b"\x89PNG"){continue;}
   let digest=hash(&png);let cid=format!("file:{}",&digest[..16]);if !known.insert(cid.clone()){continue;}
   let size=png_size(&png);
   candidates.push(json!({"id":cid,"name":file.file_stem().map(|s|s.to_string_lossy().into_owned()).unwrap_or_default(),
    "source":folder,"guid":"","bytes":png.len(),"width":size.map(|s|s.0),"height":size.map(|s|s.1),
    "png":file,"eye":true,"used_by":Vec::<String>::new()}));
  }
 }
 let current:serde_json::Map<String,J>=slots.iter().map(|s|(s["key"].as_str().unwrap_or("").to_owned(),s["candidate"].clone())).collect();
 Ok(json!({"valid":true,"slots":slots,"candidates":candidates,"current":current,"skipped":skipped,
  "plugin":key.unwrap_or_else(||DEFAULT_ME_KEY.into()),"outfit":outfit}))
}

/// `{"action":"eye_overlay_set","card":<png>,"output":<png>,"resources":<v1>,"outfit":0,
///   "material":"cf_m_hitomi_00","property":"_MainTex","png":"<file>"}` — no `png` clears the slot.
/// A candidate id from `eye_overlays` may be given as `candidate` instead of a file path.
pub(super) fn apply(root:&Path,r:&J)->Result<J,String>{
 let card=Path::new(text(r,"card")?);let outfit=r["outfit"].as_u64().unwrap_or(0) as usize;
 let material=text(r,"material")?.to_owned();
 // Material Editor stores the shader property without its leading underscore, and every head
 // lookup keys on that form ("MainTex"): a row written as "_MainTex" parses but is never drawn.
 let property=text(r,"property")?.trim_start_matches('_').to_owned();
 if material.is_empty()||property.is_empty(){return Err("缺少材質或屬性名稱".into());}
 let output=Path::new(text(r,"output")?);if output.ok_exists(){return Err("外觀輸出已存在".into());}
 let original=crate::gamefs::read(card).map_err(|e|e.to_string())?;
 let cache=Path::new(text(r,"cache")?);
 let mut blocks=blocks_from_card(&original)?;if let Some(metadata)=original_metadata(root,cache,&original)?{blocks.insert("KKEx".into(),metadata);}
 let mut kkex=blocks.get("KKEx").map(|b|decode(b)).transpose()?.unwrap_or(Value::Map(Vec::new()));
 let key=me_plugin_key(&kkex).unwrap_or_else(||DEFAULT_ME_KEY.into());
 if me_plugin_key(&kkex).is_none(){
  super::set(&mut kkex,&key,Value::Array(vec![1.into(),Value::Map(vec![
   ("TextureDictionary".into(),Value::Binary(encode(&Value::Map(Vec::new()))?)),
   ("MaterialTexturePropertyList".into(),Value::Binary(encode(&Value::Array(Vec::new()))?))])]))?;
 }
 // The PNG to install: a file path, or a candidate id the list action handed the UI.
 let png=match (r["png"].as_str().filter(|p|!p.is_empty()),r["candidate"].as_str().filter(|c|!c.is_empty())) {
  (Some(path),_)=>{let png=crate::gamefs::read(path).map_err(|e|e.to_string())?;
   if !png.starts_with(b"\x89PNG"){return Err("覆蓋貼圖必須是 PNG".into());}Some(png)},
  (None,Some(id))=>{let digest=id.rsplit(':').next().unwrap_or("");
   let data=plugin_data(&mut kkex,&key)?;
   Some(dictionary(data).into_values().find(|png|hash(png).starts_with(digest)).ok_or("找不到這張候選貼圖，請重新讀取清單")?)},
  (None,None)=>None,
 };
 {
  let data=plugin_data(&mut kkex,&key)?;
  let mut dict=dictionary(data);
  let mut list=match binary(data,"MaterialTexturePropertyList").map(|raw|decode(raw)).transpose()?{Some(Value::Array(rows))=>rows,_=>Vec::new()};
  let target=crate::card::me_mat_key(&material);
  list.retain(|row|{
   let get=|key:&str|row.as_map().and_then(|m|m.iter().find(|(k,_)|k.as_str()==Some(key)).map(|(_,v)|v));
   let kind=get("ObjectType").and_then(Value::as_i64).unwrap_or(4);
   let name=get("MaterialName").and_then(Value::as_str).unwrap_or("");
   let prop=get("Property").and_then(Value::as_str).unwrap_or("");
   !(kind==4&&crate::card::me_mat_key(name)==target&&same(prop,&property))
  });
  if let Some(png)=&png {
   // Reuse the id of an identical texture the card already carries: the maker's own dictionary
   // does the same, and picking "the one the other eye uses" must not duplicate the payload.
   let id=dict.iter().find(|(_,bytes)|*bytes==png).map(|(id,_)|*id).unwrap_or_else(||dict.keys().next_back().map_or(1,|id|id+1));
   dict.insert(id,png.clone());
   list.push(Value::Map(vec![("TexID".into(),id.into()),("ObjectType".into(),4.into()),
    ("CoordinateIndex".into(),0.into()),("Slot".into(),0.into()),
    ("MaterialName".into(),material.clone().into()),("Property".into(),property.clone().into())]));
  }
  // Drop the textures no row names any more, so clearing a slot does not leave the PNG in the card.
  let used:std::collections::HashSet<i64>=list.iter().filter_map(|row|row.as_map().and_then(|m|m.iter().find(|(k,_)|k.as_str()==Some("TexID")).and_then(|(_,v)|v.as_i64()))).collect();
  dict.retain(|id,_|used.contains(id));
  let encoded=Value::Map(dict.into_iter().map(|(id,png)|(id.into(),Value::Binary(png))).collect());
  let data=plugin_data(&mut kkex,&key)?;
  super::set(data,"TextureDictionary",Value::Binary(encode(&encoded)?))?;
  super::set(data,"MaterialTexturePropertyList",Value::Binary(encode(&Value::Array(list))?))?;
 }
 blocks.insert("KKEx".into(),encode(&kkex)?);
 let raw=write_blocks(&original,blocks)?;
 let mut request=r.clone();request["outfit"]=json!(outfit);
 export_edited(root,&request,&raw,output)?;
 Ok(json!({"valid":true,"output":output,"material":material,"property":property,"cleared":png.is_none()}))
}

#[cfg(test)]
mod tests{
 use super::*;
 /// The rule a written row lives or dies by: Material Editor stores the shader property without its
 /// leading underscore, and every head lookup (`head_body.rs`) keys on that form. A row written as
 /// `_MainTex` parses back fine and is never drawn, so the listed property is already trimmed.
 #[test]
 fn property_names_are_stored_without_the_shader_underscore(){
  assert!(same("_MainTex","MainTex"));
  assert_eq!("_MainTex".trim_start_matches('_'),"MainTex");
 }
 /// The iris keeps its highlights from the card's own hlUp/hlDown types, so the overlay slots the
 /// open path skips there are listed as not applying instead of pretending to work.
 #[test]
 fn iris_overlay_slots_are_reported_as_not_applied(){
  assert!(applies("cf_m_hitomi_00","MainTex"));
  assert!(!applies("cf_m_hitomi_00","overtex1"));
  assert!(applies("cf_m_eyeline_00_up","overtex1"));
 }
}
