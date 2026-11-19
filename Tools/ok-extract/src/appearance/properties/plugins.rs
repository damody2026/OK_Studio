use super::*;

fn unpack(b:&[u8])->Option<Value>{if b.len()>16*1024*1024{return None;}let mut c=Cursor::new(b);let v=rmpv::decode::read_value(&mut c).ok()?;((c.position() as usize==b.len())&&(v.is_map()||v.is_array())).then_some(v)}
/// One KKEx section we know the shape of. `key` is **matched exactly**, because a section key is whatever the plugin
/// author wrote in its ExtendedSave id and has nothing to do with the plugin's display name: KoiSkinOverlayX writes
/// `KSOX` and KoiClothesOverlayX writes `KCOX`, so the old `name.contains("overlay")` whitelist dropped both of them
/// without a word (found 2026-11-19 while listing what the maker can and cannot edit). A substring match is wrong in
/// the other direction too — it would hand an unknown third party's section to `visit()` as if we knew its shape.
/// Add a plugin by adding its row here; never by loosening the match.
/// `title_id` is a text id (`Localization/<lang>/*.toml`, shown through `OKT`), not a display string: a Chinese
/// literal here would be a second string source that no translation pass ever finds.
struct PluginSection{
 /// The KKEx section key in the card.
 key:&'static str,
 /// The plugin's name in property keys (`plugins.<id>.…`): one word, no dots, the same on every card. Never the
 /// section's position in KKEx — that is each card's own fact (alice's 9th section is MaterialEditor, megumin's is
 /// Pushup), so a positional key copied to another card writes into another plugin without any error.
 id:&'static str,
 /// Semantic id of the group name shown in the editor; the UI translates it and falls back to the id itself.
 title_id:&'static str,
 /// Plugin name and its BepInEx GUID, for whoever has to find the plugin this data came from. The GUID is often
 /// not the section key (KoiSkinOverlayX's GUID is `KSOX` but MaterialEditor's section is `com.deathweasel.bepinex.materialeditor`).
 plugin:&'static str,
 guid:&'static str,
}
/// Every `key` below marked "card" was read off a real card's KKEx map (`unknown_plugin_sections` on
/// `Content/CharacterCards/CrowdAPNG/C000.png`, 2026-11-19). That check mattered: the section keys are the plugins'
/// GUIDs, **not** the `KK_Plugins.<Name>` strings their source uses for the data classes, so a table filled in from
/// the decompiled source would have dropped MaterialEditor, HairAccessoryCustomizer, Pushup and DynamicBoneEditor —
/// the exact regression the old substring match happened to avoid. Keys marked "source" come from the plugin's
/// `GUID` constant and no local card carries them yet; a card that does will report the key here, and then it gets
/// confirmed rather than guessed.
const PLUGIN_SECTIONS:&[PluginSection]=&[
 // card
 PluginSection{key:"com.deathweasel.bepinex.materialeditor",id:"MaterialEditor",title_id:"reader.plugin_group.material_editor",plugin:"MaterialEditor",guid:"com.deathweasel.bepinex.materialeditor"},
 PluginSection{key:"com.deathweasel.bepinex.hairaccessorycustomizer",id:"HairAccessoryCustomizer",title_id:"reader.plugin_group.hair_accessory",plugin:"HairAccessoryCustomizer",guid:"com.deathweasel.bepinex.hairaccessorycustomizer"},
 PluginSection{key:"com.deathweasel.bepinex.pushup",id:"Pushup",title_id:"reader.plugin_group.pushup",plugin:"Pushup",guid:"com.deathweasel.bepinex.pushup"},
 PluginSection{key:"com.deathweasel.bepinex.dynamicboneeditor",id:"DynamicBoneEditor",title_id:"reader.plugin_group.dynamic_bone_editor",plugin:"DynamicBoneEditor",guid:"com.deathweasel.bepinex.dynamicboneeditor"},
 PluginSection{key:"moreAccessories",id:"MoreAccessories",title_id:"reader.plugin_group.more_accessories",plugin:"MoreAccessories",guid:"com.joan6694.illusionplugins.moreaccessories"},
 // card. Two different plugins keep accessory states, and the old substring whitelist (`accessorystates`) matched
 // neither of them — `Accessory_States` and `madevil.kk.ass` both miss that spelling, so this data was never offered.
 PluginSection{key:"Accessory_States",id:"AccessoryStates",title_id:"reader.plugin_group.accessory_states",plugin:"KKS_Accessory_States",guid:"Accessory_States"},
 PluginSection{key:"madevil.kk.ass",id:"AccessoryStateSync",title_id:"reader.plugin_group.accessory_state_sync",plugin:"Accessory State Sync",guid:"madevil.kk.ass"},
 // source: KoiSkinOverlayX / KoiClothesOverlayX use short ids, which is why `contains("overlay")` dropped them.
 PluginSection{key:"KSOX",id:"KoiSkinOverlayX",title_id:"reader.plugin_group.skin_overlay",plugin:"KoiSkinOverlayX",guid:"KSOX"},
 PluginSection{key:"KCOX",id:"KoiClothesOverlayX",title_id:"reader.plugin_group.clothes_overlay",plugin:"KoiClothesOverlayX",guid:"KCOX"},
 // source
 PluginSection{key:"HairShadowColorControl",id:"HairShadowColorControl",title_id:"reader.plugin_group.hair_shadow_color",plugin:"HairShadowColorControl",guid:"HairShadowColorControl"},
 PluginSection{key:"com.deathweasel.bepinex.eyecontrol",id:"EyeControl",title_id:"reader.plugin_group.eye_control",plugin:"EyeControl",guid:"com.deathweasel.bepinex.eyecontrol"},
 PluginSection{key:"com.deathweasel.bepinex.eyeshaking",id:"EyeShaking",title_id:"reader.plugin_group.eye_shaking",plugin:"EyeShaking",guid:"com.deathweasel.bepinex.eyeshaking"},
 PluginSection{key:"com.deathweasel.bepinex.uncensorselector",id:"UncensorSelector",title_id:"reader.plugin_group.uncensor_selector",plugin:"UncensorSelector",guid:"com.deathweasel.bepinex.uncensorselector"},
 // Deliberately absent, and they will keep showing up in `unknown_plugin_sections` — that is correct, not a gap:
 // `KKABMPlugin.ABMData` and `KKABMX.Core` are edited through `bone.*` (`EditorModsJson`), and the same data offered
 // in two places means an edit in one is silently ignored by the other; `com.bepis.sideloader.universalautoresolver`
 // is the resolve list, which `appearance` rewrites as a whole when an item changes and must never be hand-edited;
 // `OpenKoikatsu.AppearanceSource` is our own provenance block.
];
fn section(name:&str)->Option<&'static PluginSection>{PLUGIN_SECTIONS.iter().find(|s|s.key.eq_ignore_ascii_case(name))}
/// The step of a property key into a map entry, by its key: `@<name>` for a plain string key (no dot, so the property key
/// splits cleanly), `#<n>` for an integer key (Pushup's and the overlays' per-outfit maps are keyed by outfit number),
/// else `m<index>`. By key, so a plugin whose entries come in another order on another card (another plugin version,
/// an outfit missing) still lands on the same field. Array steps stay `a<index>`: a list's entries are this card's own
/// items (MaterialEditor's per-renderer edits), and the property list is read again for every card.
fn map_step(k:&Value,i:usize)->String{match (k.as_str(),k.as_i64()){(Some(s),_) if !s.is_empty()&&!s.contains('.')=>format!("@{s}"),(None,Some(n))=>format!("#{n}"),_=>format!("m{i}")}}
fn xml_rows(xml:&str,outfit:usize)->Result<Vec<(String,String,String,std::ops::Range<usize>)>,String>{
 let doc=roxmltree::Document::parse(xml).map_err(|e|e.to_string())?;let mut out=Vec::new();let mut slot=20;
 for node in doc.descendants().filter(|n|n.has_tag_name("accessory")&&n.ancestors().any(|a|a.has_tag_name("accessorySet")&&a.attribute("type").and_then(|s|s.parse::<usize>().ok())==Some(outfit))){
  for a in node.attributes(){let n=a.name();let label=if n=="parentKey"{"綁定骨架".into()}else if n=="noShake"{"停止擺動".into()}else if let Some(k)=n.strip_prefix("color"){if k.len()!=2{continue;}let c=match &k[1..]{"r"=>"紅","g"=>"綠","b"=>"藍","a"=>"透明度",_=>continue};format!("顏色層 {}／{c}",k[..1].parse::<usize>().unwrap_or(0)+1)}else if let Some(k)=n.strip_prefix("addMove"){if k.len()!=3{continue;}let group=k[..1].parse::<usize>().map_err(|_|"變形組錯誤")?;let ty=k[1..2].parse::<usize>().map_err(|_|"變形種類錯誤")?;if group>1||ty>2{continue;}let axis=match &k[2..]{"x"=>"橫軸","y"=>"縱軸","z"=>"深度",_=>continue};format!("第 {} 組／{}／{axis}",group+1,["位置（公分）","旋轉（度）","縮放"][ty])}else{continue;};
   out.push((format!("{slot}.{n}"),format!("飾品欄 {}／{label}",slot+1),a.value().to_string(),a.range_value()));
  }slot+=1;
 }Ok(out)
}
fn visit(v:&Value,path:&str,labels:&str,color:bool,outfit:usize,out:&mut Vec<J>){visit_with(v,path,labels,color,outfit,out,None)}
/// The largest integer anywhere under `v` (a `_state` list of `[start, stop]` pairs), 0 when there is none.
fn max_int(v:&Value)->i64{match v{Value::Integer(_)=>v.as_i64().unwrap_or(0),Value::Array(a)=>a.iter().map(max_int).max().unwrap_or(0),_=>0}}
/// Integer fields offered as rows, by name, with their hard bounds `(min, max)`. Only these: the other integers in
/// plugin data are identities (`ObjectType`, `CoordinateIndex`, `Slot`, texture ids, enum `Property`) — editing one
/// moves the entry onto another object or breaks a reference, so they stay out.
/// * Accessory States (`Slotdata`, `KKS_Accessory_States/.../Slotdata.cs`): `_binding` is -1 (none), 0–8 a clothes kind,
///   9 and up a custom group the card names in `_names`; offered as -1..max(8, stored) so a card's own group stays
///   valid, a new custom group is not invented here. `_state` holds `[start, stop]` pairs, 0..3 for a clothes binding
///   (`CoordinateData.cs` 276–291: the max state of a clothes kind is 3), up to the stored max for a custom group.
///   `_shoetype` is 0 outer, 1 inner, 2 both.
/// * MaterialEditor `RenderQueue` (`MaterialShader`): Unity's -1 (use the shader's) .. 5000.
fn int_spec(name:&str,path:&str,v:&Value,binding:Option<i64>)->Option<(i64,i64)>{
 if path.starts_with("plugins.AccessoryStates.") {
  return match name {
   "_binding"=>Some((-1,max_int(v).max(8))),
   "_state"=>Some((0,if binding.is_some_and(|b|(0..=8).contains(&b)){3}else{max_int(v).max(3)})),
   "_shoetype"=>Some((0,2)),
   _=>None,
  };
 }
 (path.starts_with("plugins.MaterialEditor.")&&name=="RenderQueue").then_some((-1,5000))
}
fn visit_with(v:&Value,path:&str,labels:&str,color:bool,outfit:usize,out:&mut Vec<J>,int:Option<(i64,i64)>){
 match v{
  // MaterialEditor keeps every outfit's clothes (ObjectType 1) and accessory (2) entries in one list: only the edited
  // outfit's can change the preview, so the others are not offered (an edit there showed no change at all).
  Value::Map(m) if {let int=|key:&str|m.iter().find(|(k,_)|k.as_str()==Some(key)).and_then(|(_,v)|v.as_i64());matches!(int("ObjectType"),Some(1|2))&&int("CoordinateIndex").is_some_and(|c|c!=outfit as i64)}=>{},
  Value::Map(m)=>{let mut context=labels.to_string();for(key,title)in [("MaterialName","材質"),("RendererName","網格"),("Property","屬性")]{if let Some(s)=m.iter().find(|(k,_)|k.as_str()==Some(key)).and_then(|(_,v)|v.as_str()){context.push_str(&format!("／{title} {s}"));}}let binding=m.iter().find(|(k,_)|k.as_str()==Some("_binding")).and_then(|(_,v)|v.as_i64());for(i,(k,v))in m.iter().enumerate(){let name=k.as_str().map(str::to_string).unwrap_or_else(||k.to_string());if name.to_ascii_lowercase().contains("texture")||name.ends_with("Original") {continue;}visit_with(v,&format!("{path}.{}",map_step(k,i)),&format!("{context}／{}",label(&name)),color||name.to_ascii_lowercase().contains("color"),outfit,out,int_spec(&name,path,v,binding))}},
  // An integer spec reaches into lists (`_state`'s pairs), never into a nested map.
  Value::Array(a)=>for(i,v)in a.iter().enumerate(){visit_with(v,&format!("{path}.a{i}"),&format!("{labels}／{}",if color&&a.len()==4{["紅","綠","藍","透明度"][i].into()}else{format!("{}",i+1)}),color,outfit,out,int)},
  Value::Binary(b)=>if let Some(v)=unpack(b){visit(&v,&format!("{path}.packed"),labels,color,outfit,out)},
  Value::Integer(_)=>if let (Some((lo,hi)),Some(n))=(int,v.as_i64()){out.push(json!({"key":path,"label":labels,"kind":"number","integer":true,"decimals":0,"value":n,"min":lo,"max":hi,"limit_min":lo,"limit_max":hi}));},
  // MaterialEditor stores a float override's `Value` as a string (`MaterialFloatProperty`, MaterialEditorCharaController
  // 107–140), and a renderer switch as "True"／"False". Offered as the number／bool it holds — never as free text —
  // and written back as a string (`replace`). Other strings stay out: their type is not known here.
  Value::String(s) if path.starts_with("plugins.MaterialEditor.")&&path.ends_with(".@Value")=>{
   let Some(s)=s.as_str() else{return};
   if let Ok(n)=s.trim().parse::<f64>(){if n.is_finite(){out.push(json!({"key":path,"label":labels,"kind":"number","value":n,"stored_as":"string"}));}}
   else if s.eq_ignore_ascii_case("true")||s.eq_ignore_ascii_case("false"){out.push(json!({"key":path,"label":labels,"kind":"bool","value":s.eq_ignore_ascii_case("true"),"stored_as":"string"}));}
  },
  Value::String(s)=>if let Some(xml)=s.as_str().filter(|s|s.trim_start().starts_with('<')){if let Ok(rows)=xml_rows(xml,outfit){for(key,label,raw,_)in rows {let (kind,value)=if key.ends_with("parentKey"){("parent",json!(raw))}else if key.ends_with("noShake"){("bool",json!(raw.eq_ignore_ascii_case("true")))}else{let Ok(n)=raw.parse::<f64>()else{continue};(if key.contains("color"){"color"}else{"number"},json!(n))};out.push(json!({"key":format!("{path}.xml.{key}"),"label":format!("{labels}／{label}"),"kind":kind,"value":value}));}}},
  Value::F32(n)=>out.push(json!({"key":path,"label":labels,"kind":if color{"color"}else{"number"},"value":n})),
  Value::F64(n)=>out.push(json!({"key":path,"label":labels,"kind":if color{"color"}else{"number"},"value":n})),
  Value::Boolean(n)=>out.push(json!({"key":path,"label":labels,"kind":"bool","value":n})),
  _=>{}
 }
}
/// Properties of the KKEx sections we know, plus the keys of the sections we do **not** know: those are reported,
/// never walked. A card carrying an unlisted section used to lose it silently (that is how `KSOX` went unnoticed),
/// so the caller shows the key and whoever sees it can add the row to `PLUGIN_SECTIONS`.
pub(super)fn catalog(blocks:&BTreeMap<String,Vec<u8>>,outfit:usize,out:&mut Vec<J>)->Result<Vec<String>,String>{
 let mut unknown=Vec::new();
 if let Some(b)=blocks.get("KKEx"){let v=decode(b)?;if let Some(m)=v.as_map(){for(k,v)in m.iter(){
  let Some(name)=k.as_str() else{continue};
  let Some(s)=section(name) else{unknown.push(name.to_string());continue};
  // The group name is `title_id`, not part of `label`: one translated prefix for the whole group beats a
  // Chinese literal glued onto every row (which no translation pass would ever find).
  let first=out.len();
  // Keyed by the plugin's identity (`plugins.MaterialEditor.…`), never by where its section sits in this card's KKEx.
  visit(v,&format!("plugins.{}",s.id),"",false,outfit,out);
  for p in out[first..].iter_mut(){
   p["group_id"]=json!(s.title_id);p["plugin"]=json!(s.plugin);
   if let Some(l)=p["label"].as_str().map(|l|l.trim_start_matches('／').to_string()){p["label"]=json!(l);}
  }
 }}}
 Ok(unknown)
}
fn replace(v:&mut Value,path:&str,value:&Value,outfit:usize)->Result<(),String>{
 // A leaf keeps the type the plugin stored: MaterialEditor's float／bool kept as a string stays a string (its loader
 // parses it; a msgpack float there would not load). The f32 text is the shortest that reads back the same value.
 if path.is_empty(){*v=match (&*v,value){
  (Value::String(_),Value::F32(f))=>Value::String(format!("{f}").into()),
  (Value::String(_),Value::F64(f))=>Value::String(format!("{}",*f as f32).into()),
  (Value::String(_),Value::Boolean(b))=>Value::String((if *b{"True"}else{"False"}).into()),
  _=>value.clone(),
 };return Ok(());}
 let (head,rest)=path.split_once('.').unwrap_or((path,""));
 if head=="packed" {let b=v.as_slice().ok_or("模組二進位格式錯誤")?;let mut decoded=unpack(b).ok_or("模組資料無法解碼")?;replace(&mut decoded,rest,value,outfit)?;*v=Value::Binary(encode(&decoded)?);return Ok(());}
 if head=="xml" {let xml=v.as_str().ok_or("模組 XML 格式錯誤")?;let rows=xml_rows(xml,outfit)?;let (_,_,_,range)=rows.into_iter().find(|r|r.0==rest).ok_or("找不到額外飾品欄位")?;let raw=match value {Value::String(s)=>s.as_str().ok_or("骨架字串錯誤")?.to_string(),Value::Boolean(b)=>b.to_string(),_=>value.to_string()};let escaped=raw.replace('&',"&amp;").replace('<',"&lt;").replace('"',"&quot;").replace('\'',"&apos;");let mut xml=xml.to_string();xml.replace_range(range,&escaped);*v=xml.into();return Ok(());}
 if let Some(name)=head.strip_prefix('@'){
  let child=match v {Value::Map(m)=>m.iter_mut().find(|(k,_)|k.as_str()==Some(name)).map(|(_,v)|v),_=>None}.ok_or_else(||format!("模組欄位不存在：{name}"))?;
  return replace(child,rest,value,outfit);
 }
 if let Some(n)=head.strip_prefix('#'){
  let n=n.parse::<i64>().map_err(|_|"模組路徑錯誤")?;
  let child=match v {Value::Map(m)=>m.iter_mut().find(|(k,_)|k.as_str().is_none()&&k.as_i64()==Some(n)).map(|(_,v)|v),_=>None}.ok_or_else(||format!("模組欄位不存在：{n}"))?;
  return replace(child,rest,value,outfit);
 }
 let (kind,index)=head.split_at(1);let index=index.parse::<usize>().map_err(|_|"模組路徑錯誤")?;
 let child=match v {Value::Map(m) if kind=="m"=>m.get_mut(index).map(|(_,v)|v),Value::Array(a) if kind=="a"=>a.get_mut(index),_=>None}.ok_or("模組欄位不存在")?;replace(child,rest,value,outfit)
}
pub(super)fn patch(blocks:&mut BTreeMap<String,Vec<u8>>,changes:&BTreeMap<String,Value>,outfit:usize)->Result<(),String>{
 if !changes.keys().any(|k|k.starts_with("plugins.")){return Ok(());}
 let mut v=decode(blocks.get("KKEx").ok_or("缺少模組資料")?)?;
 for(k,val)in changes{let Some(path)=k.strip_prefix("plugins.")else{continue};
  // The first step names the plugin; its place in KKEx is looked up again on this card. A plugin this card does
  // not carry is an error, never "the Nth section": that is the write that would land in another plugin.
  let (id,rest)=path.split_once('.').unwrap_or((path,""));
  let s=PLUGIN_SECTIONS.iter().find(|s|s.id==id).ok_or_else(||format!("不認得的模組：{id}"))?;
  let Value::Map(m)=&mut v else{return Err("模組資料格式錯誤".into())};
  let section=m.iter_mut().find(|(k,_)|k.as_str().is_some_and(|k|k.eq_ignore_ascii_case(s.key))).map(|(_,v)|v).ok_or_else(||format!("這張卡沒有這個模組：{id}"))?;
  replace(section,rest,val,outfit)?;}
 blocks.insert("KKEx".into(),encode(&v)?);Ok(())
}
// The KKEx section keys in these tests (`com.deathweasel.bepinex.materialeditor` …) were **read off a real card**,
// not copied from the decompiled source: the section key is the plugin's BepInEx GUID, while its source calls the
// data class `KK_Plugins.MaterialEditor`. A table written from the source matched nothing, and the old
// `name.contains("materialeditor")` whitelist only worked because the GUID happens to contain that word
// (2026-11-19). So do not "tidy" these keys back into `KK_Plugins.<Name>` — that silently drops MaterialEditor,
// HairAccessoryCustomizer, Pushup and DynamicBoneEditor. `unknown_plugin_sections` is how a real key gets found.
#[cfg(test)]mod tests{use super::*;
 #[test]fn material_editor_rows_of_other_outfits_are_not_offered(){
  let entry=|ot:i64,coord:i64,mat:&str|Value::Map(vec![("ObjectType".into(),ot.into()),("CoordinateIndex".into(),coord.into()),("Slot".into(),0.into()),("MaterialName".into(),mat.into()),("Property".into(),"ShadowColor".into()),("Value".into(),Value::Array(vec![Value::F32(0.5),Value::F32(0.5),Value::F32(0.5),Value::F32(1.)]))]);
  let colors=Value::Array(vec![entry(2,4,"other_outfit"),entry(2,0,"this_outfit"),entry(1,3,"other_clothes"),entry(3,4,"hair_any_outfit")]);
  let data=Value::Map(vec![("MaterialColorPropertyList".into(),Value::Binary(encode(&colors).unwrap()))]);
  let root=Value::Map(vec![("com.deathweasel.bepinex.materialeditor".into(),Value::Array(vec![1.into(),data]))]);let blocks=BTreeMap::from([("KKEx".into(),encode(&root).unwrap())]);
  let mut props=Vec::new();catalog(&blocks,0,&mut props).unwrap();
  let labels:Vec<&str>=props.iter().map(|p|p["label"].as_str().unwrap()).collect();
  assert!(labels.iter().any(|l|l.contains("this_outfit"))&&labels.iter().any(|l|l.contains("hair_any_outfit")));
  assert!(!labels.iter().any(|l|l.contains("other_outfit")||l.contains("other_clothes")));
  // Kept rows keep their list index, so an edit still lands on its own entry.
  assert!(props.iter().filter(|p|p["label"].as_str().unwrap().contains("this_outfit")).all(|p|p["key"].as_str().unwrap().contains(".packed.a1.")));
 }
 #[test]fn packed_material_colors_keep_unknown_fields_and_texture_bytes(){
  let colors=Value::Array(vec![Value::Map(vec![("Color".into(),Value::Array(vec![Value::F32(0.2),Value::F32(0.3),Value::F32(0.4),Value::F32(1.)])),("Unknown".into(),"keep".into())])]);
  let data=Value::Map(vec![("MaterialColorPropertyList".into(),Value::Binary(encode(&colors).unwrap())),("MaterialTexturePropertyList".into(),Value::Binary(vec![0,1,2,3]))]);
  let root=Value::Map(vec![("com.deathweasel.bepinex.materialeditor".into(),Value::Array(vec![1.into(),data]))]);let mut blocks=BTreeMap::from([("KKEx".into(),encode(&root).unwrap())]);let mut props=Vec::new();catalog(&blocks,0,&mut props).unwrap();assert_eq!(props.len(),4);let key=props[0]["key"].as_str().unwrap().to_string();patch(&mut blocks,&BTreeMap::from([(key,Value::F32(0.7))]),0).unwrap();
  let next=decode(&blocks["KKEx"]).unwrap();let plugin=&next.as_map().unwrap()[0].1.as_array().unwrap()[1];let m=plugin.as_map().unwrap();assert_eq!(m[1].1,Value::Binary(vec![0,1,2,3]));let decoded=decode(m[0].1.as_slice().unwrap()).unwrap();assert_eq!(decoded.as_array().unwrap()[0].as_map().unwrap()[1].1,Value::from("keep"));assert_eq!(decoded.as_array().unwrap()[0].as_map().unwrap()[0].1.as_array().unwrap()[0],Value::F32(0.7));
 }
 /// The same plugin sits at a different place in another card's KKEx (alice: MaterialEditor 9th, Pushup 23rd; megumin:
 /// Pushup 9th). Keys name the plugin, so a key read off one card edits that plugin on the other — or is refused there
 /// when the card does not carry it — and never writes into whatever sits at the same position.
 #[test]fn plugin_keys_name_the_plugin_not_its_position(){
  let pushup=|v:f32|Value::Map(vec![("Firmness".into(),Value::F32(v))]);
  let me=Value::Map(vec![("Shininess".into(),Value::F32(0.2))]);
  let alice=Value::Map(vec![("com.deathweasel.bepinex.materialeditor".into(),me),("com.deathweasel.bepinex.pushup".into(),pushup(0.5))]);
  let megumin=Value::Map(vec![("com.deathweasel.bepinex.pushup".into(),pushup(0.9))]);
  let mut a=BTreeMap::from([("KKEx".into(),encode(&alice).unwrap())]);let mut b=BTreeMap::from([("KKEx".into(),encode(&megumin).unwrap())]);
  let mut props=Vec::new();catalog(&a,0,&mut props).unwrap();
  let keys:Vec<&str>=props.iter().map(|p|p["key"].as_str().unwrap()).collect();
  assert_eq!(keys,vec!["plugins.MaterialEditor.@Shininess","plugins.Pushup.@Firmness"]);
  let mut other=Vec::new();catalog(&b,0,&mut other).unwrap();assert_eq!(other[0]["key"],"plugins.Pushup.@Firmness");
  // alice's MaterialEditor key on megumin: refused, megumin unchanged (the positional key wrote her Pushup).
  let err=patch(&mut b,&BTreeMap::from([("plugins.MaterialEditor.@Shininess".to_string(),Value::F32(0.7))]),0).unwrap_err();
  assert!(err.contains("MaterialEditor"),"{err}");assert_eq!(decode(&b["KKEx"]).unwrap(),megumin);
  // alice's Pushup key lands on megumin's Pushup, wherever it sits.
  patch(&mut b,&BTreeMap::from([("plugins.Pushup.@Firmness".to_string(),Value::F32(0.3))]),0).unwrap();
  assert_eq!(decode(&b["KKEx"]).unwrap(),Value::Map(vec![("com.deathweasel.bepinex.pushup".into(),pushup(0.3))]));
  patch(&mut a,&BTreeMap::from([("plugins.Pushup.@Firmness".to_string(),Value::F32(0.1))]),0).unwrap();
  assert_eq!(decode(&a["KKEx"]).unwrap().as_map().unwrap()[1].1,pushup(0.1));
  assert!(patch(&mut a,&BTreeMap::from([("plugins.Nope.@x".to_string(),Value::F32(0.1))]),0).is_err());
  // An integer-keyed map (per-outfit data) is stepped into by key, not position: outfit 3 listed first stays `#3`.
  let per_outfit=Value::Map(vec![("com.deathweasel.bepinex.pushup".into(),Value::Map(vec![(Value::from(3),pushup(0.4)),(Value::from(0),pushup(0.6))]))]);
  let mut c=BTreeMap::from([("KKEx".into(),encode(&per_outfit).unwrap())]);let mut rows=Vec::new();catalog(&c,0,&mut rows).unwrap();
  assert_eq!(rows[1]["key"],"plugins.Pushup.#0.@Firmness");
  patch(&mut c,&BTreeMap::from([("plugins.Pushup.#0.@Firmness".to_string(),Value::F32(0.2))]),0).unwrap();
  assert_eq!(decode(&c["KKEx"]).unwrap(),Value::Map(vec![("com.deathweasel.bepinex.pushup".into(),Value::Map(vec![(Value::from(3),pushup(0.4)),(Value::from(0),pushup(0.2))]))]));
 }
 #[test]fn known_integer_and_string_fields_are_offered_with_their_type(){
  let slot=Value::Map(vec![("_binding".into(),Value::from(2)),("_state".into(),Value::Array(vec![Value::Array(vec![Value::from(0),Value::from(3)])])),("_shoetype".into(),Value::from(2)),("_parented".into(),Value::Boolean(false))]);
  let states=Value::Map(vec![("Accessory_States".into(),Value::Map(vec![("CoordinateData".into(),Value::Map(vec![(Value::from(0),Value::Map(vec![("_slotinfo".into(),Value::Map(vec![(Value::from(5),slot)]))]))]))]))]);
  let float=Value::Map(vec![("ObjectType".into(),Value::from(4)),("CoordinateIndex".into(),Value::from(0)),("Slot".into(),Value::from(0)),("Property".into(),"Shininess".into()),("Value".into(),"0.25".into()),("ValueOriginal".into(),"0.5".into())]);
  let me=Value::Map(vec![("com.deathweasel.bepinex.materialeditor".into(),Value::Map(vec![("MaterialFloatPropertyList".into(),Value::Array(vec![float]))]))]);
  let mut root=states.as_map().unwrap().clone();root.extend(me.as_map().unwrap().iter().cloned());
  let mut blocks=BTreeMap::from([("KKEx".into(),encode(&Value::Map(root)).unwrap())]);
  let mut rows=Vec::new();catalog(&blocks,0,&mut rows).unwrap();
  let row=|k:&str|rows.iter().find(|p|p["key"]==k).unwrap_or_else(||panic!("{k} not in {rows:?}")).clone();
  let base="plugins.AccessoryStates.@CoordinateData.#0.@_slotinfo.#5";
  assert_eq!((row(&format!("{base}.@_binding"))["min"].as_i64(),row(&format!("{base}.@_binding"))["max"].as_i64()),(Some(-1),Some(8)));
  // A clothes binding: each state bound is 0..3, hard.
  assert_eq!(row(&format!("{base}.@_state.a0.a1"))["limit_max"],3);assert_eq!(row(&format!("{base}.@_shoetype"))["limit_max"],2);
  // Identities stay out: ObjectType／CoordinateIndex／Slot are integers too.
  assert!(rows.iter().all(|p|!p["key"].as_str().unwrap().ends_with("@Slot")&&!p["key"].as_str().unwrap().ends_with("@ObjectType")));
  // MaterialEditor's float-in-a-string: a number row; written back as a string.
  let k="plugins.MaterialEditor.@MaterialFloatPropertyList.a0.@Value";assert_eq!(row(k)["kind"],"number");assert_eq!(row(k)["value"],0.25);
  patch(&mut blocks,&BTreeMap::from([(k.to_string(),Value::F32(0.3))]),0).unwrap();

  let v=decode(&blocks["KKEx"]).unwrap();let me=v.as_map().unwrap().iter().find(|(k,_)|k.as_str()==Some("com.deathweasel.bepinex.materialeditor")).unwrap().1.clone();
  let entry=&me.as_map().unwrap()[0].1.as_array().unwrap()[0];
  assert_eq!(entry.as_map().unwrap().iter().find(|(k,_)|k.as_str()==Some("Value")).unwrap().1,Value::String("0.3".into()));
 }
 #[test]fn extra_accessory_xml_preserves_unknown_attributes_and_other_outfits(){
  let xml="<root><accessorySet type=\"0\"><accessory parentKey=\"a_n_head\" color0r=\"0.5\" addMove01x=\"0\" unknown=\"keep\" /></accessorySet><accessorySet type=\"1\"><accessory color0r=\"0.9\" /></accessorySet></root>";
  let mut v=Value::from(xml);replace(&mut v,"xml.20.color0r",&Value::F32(0.25),0).unwrap();replace(&mut v,"xml.20.addMove01x",&Value::F32(90.),0).unwrap();let s=v.as_str().unwrap();assert!(s.contains("color0r=\"0.25\""));assert!(s.contains("unknown=\"keep\""));assert!(s.contains("color0r=\"0.9\""));assert!(s.contains("addMove01x=\"90\""));
 }
}
