//! Typed, card-derived maker properties. Unknown MessagePack members survive edits.
use super::*;
mod plugins;
mod physics;

fn label(key: &str) -> String {
 let mod_labels=[("AccessoryDynamicBoneData","飾品動態骨骼資料"),("AreolaDepth","乳暈深度"),("CenterNipples","乳頭置中"),("Damping","阻尼"),("Depth","深度"),("Elasticity","彈性"),("EnablePushup","啟用內衣塑形"),("Firmness","緊實度"),("FlattenNipples","壓平乳頭"),("HorizontalAngle","水平角度"),("HorizontalPosition","水平位置"),("Lift","托高"),("NippleDepth","乳頭深度"),("NippleWidth","乳頭寬度"),("PushTogether","向內集中"),("Pushup_BodyData","身體塑形資料"),("Pushup_BraData","胸罩塑形資料"),("Pushup_TopData","上衣塑形資料"),("Radius","半徑"),("Roundness","圓潤度"),("Size","大小"),("Softness","柔軟度"),("Squeeze","擠壓"),("Stiffness","剛性"),("UseAdvanced","使用進階設定"),("VerticalAngle","垂直角度"),("VerticalPosition","垂直位置"),("Weight","重量")];
 if let Some((_,v))=mod_labels.iter().find(|(k,_)|*k==key){return v.to_string();}
 let extra=[("sleevesType","袖子種類"),("hideCategory","H 時分組"),("areolaSize","乳暈大小"),("bustSoftness","胸部柔軟度"),("bustWeight","胸部重量"),("cheekGlossPower","臉頰光澤強度"),("detailPower","細節強度"),("doubleTooth","虎牙"),("drawAddLine","附加線條"),("eyelineUpWeight","上眼線粗細"),("foregroundEyes","眼睛描畫前面"),("foregroundEyebrow","眉毛描畫前面"),("gradBlend","漸層混合"),("gradOffsetY","漸層垂直位移"),("gradScale","漸層縮放"),("hideBraOpt","隱藏胸罩選項"),("hideOpt","隱藏選項"),("hideShortsOpt","隱藏內褲選項"),("hlDownX","下高光水平位置"),("hlDownY","下高光垂直位置"),("hlUpX","上高光水平位置"),("hlUpY","上高光垂直位置"),("lipGlossPower","嘴唇光澤強度"),("moleLayout","痣配置"),("nailGlossPower","指甲光澤強度"),("nipGlossPower","乳頭光澤強度"),("offset","位移"),("paintLayout","彩繪配置"),("pupilHeight","瞳孔高度"),("pupilWidth","瞳孔寬度"),("pupilX","瞳孔水平位置"),("pupilY","瞳孔垂直位置"),("rotate","旋轉"),("skinGlossPower","皮膚光澤強度"),("tiling","紋理重複"),("MaterialColorPropertyList","材質顏色覆寫"),("MaterialFloatPropertyList","材質數值覆寫"),("Color","顏色"),("Value","設定值"),("ColorOriginal","原始顏色"),("ValueOriginal","原始數值"),("additionalAccessories","額外飾品"),("CoordinateHairAccessories","本套服裝的髮飾"),("HairAccessories","髮飾"),("ColorMatch","跟隨髮色"),("HairGloss","頭髮光澤"),("OutlineColor","輪廓色"),("AccessoryColor","飾品顏色"),("GlossColor","光澤色"),("HairLength","頭髮長度")];
 if let Some((_,v))=extra.iter().find(|(k,_)|*k==key){return v.to_string();}
 let pairs=[("face","臉部"),("body","身體"),("hair","頭髮"),("clothes","衣物"),("accessory","飾品"),("makeup","化妝"),("parts","部位"),("pupil","瞳孔"),("baseMakeup","基礎化妝"),("baseColor","主要顏色"),("subColor","次要顏色"),("startColor","髮根顏色"),("endColor","髮梢顏色"),("outlineColor","輪廓顏色"),("glossColor","光澤顏色"),("acsColor","髮飾顏色"),("eyebrowColor","眉毛顏色"),("eyelineColor","眼線顏色"),("whiteBaseColor","眼白主要顏色"),("whiteSubColor","眼白次要顏色"),("hlUpColor","上高光顏色"),("hlDownColor","下高光顏色"),("moleColor","痣顏色"),("lipLineColor","唇線顏色"),("skinMainColor","皮膚主要顏色"),("skinSubColor","皮膚次要顏色"),("nipColor","乳頭顏色"),("underhairColor","陰毛顏色"),("nailColor","指甲顏色"),("sunburnColor","曬痕顏色"),("cheekColor","腮紅顏色"),("eyeshadowColor","眼影顏色"),("lipColor","嘴唇顏色"),("paintColor","彩繪顏色"),("colorInfo","顏色層"),("color","顏色"),("patternColor","花紋顏色"),("pattern","花紋"),("parentKey","綁定骨架"),("addMove","變形組"),("noShake","停止擺動"),("pos","位置"),("rot","旋轉"),("scl","縮放"),("length","長度"),("x","橫軸"),("y","縱軸"),("z","深度"),("r","紅"),("g","綠"),("b","藍"),("a","透明度")];
 pairs.iter().find(|(k,_)|*k==key).map(|(_,v)|v.to_string()).unwrap_or_else(||key.parse::<usize>().map(|n|format!("{}",n+1)).unwrap_or_else(|_|format!("進階設定（{key}）")))
}

/// Mutate one decoded section at a time; retain section prefixes and trailing bytes.
pub(super) fn sections(blocks: &mut BTreeMap<String,Vec<u8>>, outfit: usize, mut f: impl FnMut(&str,&mut Value)->Result<(),String>) -> Result<(),String> {
 let raw=blocks.get("Custom").ok_or("缺少外觀區塊")?.clone();
 if let Some(mut v)=decode(&raw).ok().filter(Value::is_map) {
  for name in ["face","body","hair"] {f(name,at(&mut v,name)?)?;}
  blocks.insert("Custom".into(),encode(&v)?);
 }
 else {
  let mut pos=0;let mut out=Vec::new();let mut i=0;
  while pos<raw.len() {let n=u32::from_le_bytes(raw.get(pos..pos+4).ok_or("外觀長度截斷")?.try_into().unwrap()) as usize;pos+=4;let mut v=decode(raw.get(pos..pos+n).ok_or("外觀資料截斷")?)?;pos+=n;
   if i==0 && at(&mut v,"face").is_ok(){for name in ["face","body","hair"]{f(name,at(&mut v,name)?)?;}}
   else {let name=["face","body","hair"].get(i).ok_or("未知外觀區段")?;f(name,&mut v)?;}
   let b=encode(&v)?;out.extend((b.len() as u32).to_le_bytes());out.extend(b);i+=1;
  }blocks.insert("Custom".into(),out);
 }
 let mut v=decode(blocks.get("Coordinate").ok_or("缺少服裝區塊")?)?;
 let slot=match &mut v {Value::Array(a)=>a.get_mut(outfit).ok_or("服裝索引超出範圍")?,v=>v};
 let Value::Binary(bin)=slot else{return Err("服裝資料格式錯誤".into())};let mut pos=0;let mut out=Vec::new();
 for section in ["clothes","accessory","makeup"] {if section=="makeup" {out.push(*bin.get(pos).ok_or("化妝旗標截斷")?);pos+=1;}
  let n=u32::from_le_bytes(bin.get(pos..pos+4).ok_or("服裝長度截斷")?.try_into().unwrap()) as usize;pos+=4;
  if n==0 {out.extend(0u32.to_le_bytes());continue;}
  let mut data=decode(bin.get(pos..pos+n).ok_or("服裝資料截斷")?)?;pos+=n;f(section,&mut data)?;let b=encode(&data)?;out.extend((b.len() as u32).to_le_bytes());out.extend(b);
 }out.extend(&bin[pos..]);*bin=out;blocks.insert("Coordinate".into(),encode(&v)?);Ok(())
}

fn walk(v:&Value,path:&str,labels:&str,color:bool,out:&mut Vec<J>) {
 let key=path.rsplit('.').next().unwrap_or("");
 if matches!(key,"shapeValueBody"|"shapeValueFace"|"version") {return;}
 // Item ids never become editable properties, whatever `integer_choice` grows to allow: writing an id here would
 // leave the sideloader resolve list untouched, so the card would point at a different mod's slot and open as
 // someone else's part (Docs/READER_UI_APPEARANCE_API.md §6). Changing an item goes through `appearance` instead.
 // This is a rule, not an omission: a future whitelist entry must not be able to open it by accident.
 if key=="id"||key.ends_with("Id")||key.ends_with("Ids") {return;}
 if key=="addMove" {if let Some(a)=v.as_array(){
  if let Some(flat)=a.get(2).and_then(Value::as_array).filter(|a|a.len()==6){for(i,vector)in flat.iter().enumerate(){let base=format!("{labels}／第 {} 組／{}",i/3+1,["位置（公分）","旋轉（度）","縮放"][i%3]);if let Some(axis)=vector.as_array(){for(j,v)in axis.iter().take(3).enumerate(){walk(v,&format!("{path}.2.{i}.{j}"),&format!("{base}／{}",["橫軸","縱軸","深度"][j]),false,out)}}}return;}
 }}
 let color=color||(key!="colorInfo"&&key.to_ascii_lowercase().contains("color"));
 match v {
  Value::Map(m)=>for(k,v)in m {if let Some(k)=k.as_str(){walk(v,&format!("{path}.{k}"),&format!("{labels}／{}",label(k)),color,out)}},
  Value::Array(a)=>for(i,v)in a.iter().enumerate(){let component=if color&&a.len()==4{["紅","綠","藍","透明度"][i].to_string()}else{label(&i.to_string())};walk(v,&format!("{path}.{i}"),&format!("{labels}／{component}"),color,out)},
  Value::F32(n)=>out.push(with_range(json!({"key":path,"label":labels,"kind":if color{"color"}else{"number"},"value":n}),path)),
  Value::F64(n)=>out.push(with_range(json!({"key":path,"label":labels,"kind":if color{"color"}else{"number"},"value":n}),path)),
  Value::Boolean(n)=>out.push(json!({"key":path,"label":labels,"kind":"bool","value":n})),
  Value::String(s) if key=="parentKey"=>out.push(json!({"key":path,"label":labels,"kind":"parent","value":s.as_str()})),
  // The maker's integer choices (CvsClothes sleeve toggles, CvsAccessory H group): only the ones the game reads.
  Value::Integer(n)=>if let Some((max,options))=integer_choice(path){out.push(json!({"key":path,"label":labels,"kind":"choice","value":n.as_i64().unwrap_or(0),
   "integer":true,"min":0,"max":max,"step":1,"decimals":0,"options":options}))},
  _=>{}
 }
}
/// The maker's ranges for the numbers it edits (CvsClothes pattern sliders; CustomAcsMoveWindow and
/// ChaControl.SetAccessoryPos/Rot/Scl), as per-parameter metadata: `min`／`max` (closed), `step`, `decimals` (rounded to
/// before the check), `wrap` (taken modulo [min,max): such a value is never refused for its range), `default` (the
/// game's own default, what a reset goes back to). A number without them keeps the old wide limit.
fn range_meta(path:&str)->Option<J>{
 let parts:Vec<&str>=path.split('.').collect();
 match parts.as_slice() {
  // Pattern size, position and rotation: sliders over 0..1 (shown 0..100); defaults tiling 0, offset 0.5, rotate 0.5.
  // The range is in the API's unit (0..1); display_scale／unit only tell the screen to show 0..100 like the maker.
  ["clothes","parts",_,"colorInfo",_,"tiling",_]=>Some(json!({"min":0.0,"max":1.0,"step":0.01,"default":0.0,"display_scale":100,"unit":"%"})),
  ["clothes","parts",_,"colorInfo",_,"offset",_]|["clothes","parts",_,"colorInfo",_,"rotate"]=>Some(json!({"min":0.0,"max":1.0,"step":0.01,"default":0.5,"display_scale":100,"unit":"%"})),
  // addMove[group][pos／rot／scl][xyz], flattened by walk as `addMove.2.{group*3+kind}.{axis}`.
  ["accessory","parts",_,"addMove","2",i,_]=>match i.parse::<usize>().ok()?%3 {
   0=>Some(json!({"min":-100.0,"max":100.0,"step":0.1,"decimals":1,"default":0.0})),
   1=>Some(json!({"min":0.0,"max":360.0,"step":1.0,"decimals":0,"wrap":true,"default":0.0})),
   _=>Some(json!({"min":0.01,"max":100.0,"step":0.01,"decimals":2,"default":1.0})),
  },
  // Every number of the face／body pages is a 0..100 slider on the maker's screen (CustomBase.ConvertTextFromRate(0,100,…),
  // all 241 uses; Docs/CHARACTER_EDITOR_PARITY_BODY_FACE.md 三之二, e-cardload): 0..1 in the API, no wrap. Colours are
  // left out by with_range (they are 0..1 already).
  ["face",..]|["body",..]=>Some(json!({"min":0.0,"max":1.0,"step":0.01,"decimals":2,"display_scale":100,"unit":"%"})),
  _=>None,
 }
}
/// `min`／`max` are the maker's slider ends (its UI range), not what the card may hold: the game writes these floats
/// without clamping (ABMX／slider unlocker cards carry values outside them), so a value outside is kept as it is and
/// its row says `out_of_range`. Only `limit_min`／`limit_max`, written where the data itself is bounded, refuse.
fn with_range(mut row:J,path:&str)->J{
 if row["kind"]!="number"{return row;}
 if let (Some(J::Object(m)),J::Object(r))=(range_meta(path),&mut row){r.extend(m);}
 if let (Some(v),Some(lo),Some(hi))=(row["value"].as_f64(),row["min"].as_f64(),row["max"].as_f64()){if row["wrap"]!=true&&(v<lo||v>hi){row["out_of_range"]=json!(true);}}
 row
}
/// Apply a row's range metadata to an edit: round to `decimals` first, then take a `wrap` value modulo [min,max)
/// (359.6 rounds to 360 and wraps to 0). Keep this order: wrapping first leaves 359.6 as it is (already inside
/// [0,360)), rounding then gives 360, outside [0,360), not the "0" the user meant.
/// The result is never clamped and never refused for leaving [min,max] (that is the slider range, a soft limit:
/// refusing or clamping would rewrite an ABMX value the card already has). Refused: a value that is not finite, or
/// one outside `limit_min`／`limit_max` when the row has them (the message names the value sent and the rounded one).
pub(crate) fn ranged(p:&J,n:f64)->Result<f64,String>{
 if !n.is_finite(){return Err("數值格式錯誤".into());}
 let mut v=n;
 if let Some(d)=p["decimals"].as_u64(){let k=10f64.powi(d as i32);v=(v*k).round()/k;}
 if let (true,Some(lo),Some(hi))=(p["wrap"]==true,p["min"].as_f64(),p["max"].as_f64()){if hi>lo{v=lo+(v-lo).rem_euclid(hi-lo);}}
 let (lo,hi)=(p["limit_min"].as_f64().unwrap_or(f64::NEG_INFINITY),p["limit_max"].as_f64().unwrap_or(f64::INFINITY));
 if v<lo||v>hi{return Err(if v==n{format!("數值 {n} 超出資料範圍 {lo}～{hi}")}else{format!("數值 {n}（取整後 {v}）超出資料範圍 {lo}～{hi}")});}
 Ok(v)
}
/// Integer fields offered as choices: the top's sleeve type (`parts[0].sleevesType`, 0..2, `ChaControl.DrawSode`) and an
/// accessory's H group (`hideCategory`, 0 main／1 sub). Others (ids, `type`) go through the appearance pickers. Option
/// names are text ids (ui_text.toml `[ui.editor_clothes]`); the UI looks them up and shows the id when one is missing.
fn integer_choice(path:&str)->Option<(i64,J)>{
 let parts:Vec<&str>=path.split('.').collect();
 match parts.as_slice() {
  ["clothes","parts","0","sleevesType"]=>Some((2,json!([{"value":0,"label_id":"ui.editor_clothes.sleeves_1"},{"value":1,"label_id":"ui.editor_clothes.sleeves_2"},{"value":2,"label_id":"ui.editor_clothes.sleeves_3"}]))),
  ["accessory","parts",_,"hideCategory"]=>Some((1,json!([{"value":0,"label_id":"ui.editor_clothes.accessory_group_main"},{"value":1,"label_id":"ui.editor_clothes.accessory_group_sub"}]))),
  // 目／眉の描画前面 (`ChaControl.SetForegroundEyesAndEyebrow`): 0 leaves it to the player's own config
  // (`EtceteraSystem.ForegroundEyes`／`ForegroundEyebrow`, both off in a fresh install), 1 forces it off, 2 on.
  ["face","foregroundEyes"]=>Some((2,json!([{"value":0,"label_id":"ui.editor_eyes.foreground_config"},{"value":1,"label_id":"ui.editor_eyes.foreground_off"},{"value":2,"label_id":"ui.editor_eyes.foreground_on"}]))),
  ["face","foregroundEyebrow"]=>Some((2,json!([{"value":0,"label_id":"ui.editor_eyes.foreground_config"},{"value":1,"label_id":"ui.editor_eyes.foreground_off"},{"value":2,"label_id":"ui.editor_eyes.foreground_on"}]))),
  _=>None,
 }
}
pub(super) fn catalog_properties(original:&[u8],outfit:usize)->Result<Vec<J>,String>{
 Ok(catalog_properties_with_unknown(original,outfit)?.0)
}
/// The editable properties, plus the KKEx section keys this build does not know (`plugins::catalog`).
pub(super) fn catalog_properties_with_unknown(original:&[u8],outfit:usize)->Result<(Vec<J>,Vec<String>),String>{
 let mut blocks=blocks_from_card(original)?;let mut props=physics::catalog(original,outfit)?;sections(&mut blocks,outfit,|name,v|{walk(v,name,&label(name),false,&mut props);Ok(())})?;let unknown=plugins::catalog(&blocks,outfit,&mut props)?;refuse_unapplied(&mut props);Ok((props,unknown))
}
/// Rows the card stores and we parse but **nobody applies**: an edit there would change the saved card and nothing
/// else, which reads as a bug ("I moved the slider and nothing happened") and hides that the data side is fine.
/// `supported:false` makes `set` answer "Parameter unsupported by current model" instead (the same refusal a missing
/// bone gets), so the no-op is stated rather than performed. Remove a line here when its consumer lands.
/// `hair.parts.N.pos/rot/scl`: `card.rs` reads them into `CardInfo.hair_parts`, and the only consumers of that
/// struct take colours and `length` (`accessories.rs`); the C ABI carries no hair transform at all (2026-11-19).
/// **The original does not apply them either**, so this is not a gap to close: in the whole decompiled
/// `Assembly-CSharp`, `.scl` appears 47 times and the only hair one is `ChaFileHair.PartsInfo.Copy`
/// (`scl = _src.scl`); `CvsHair.cs`, the hair editor, mentions `pos`/`rot`/`scl` zero times; and nothing writes
/// `parts[..].pos/rot/scl`. The game stores the three per slot, copies them with the card, and never reads them --
/// like `hair.kind`. Making them editable here would invent a behaviour no card was authored for, so they stay
/// refused rather than implemented (2026-11-19, exhaustive grep; Docs/CHARACTER_EDITOR_PARITY_HAIR_EYES.md §11).
fn refuse_unapplied(props:&mut [J]){
 for p in props.iter_mut(){
  let Some(key)=p["key"].as_str() else{continue};
  let parts:Vec<&str>=key.split('.').collect();
  // Pushup_BodyData is Pushup's copy of the body sliders before the push (`Pushup.cs` BodyData → `shapeValueBody[4..13]`,
  // bustSoftness, bustWeight); the plugin rebuilds `shape.*` from it and the garments' ClothData. A second place to
  // edit the same sliders means one silently overwrites the other — the reason ABMX stays out of `plugins.*` too.
  if key.starts_with("plugins.Pushup.")&&parts.iter().any(|p|*p=="@Pushup_BodyData") {
   p["supported"]=json!(false);
   p["unsupported_reason"]=json!("Pushup's copy of the body sliders; edit the body sliders instead");
   p["unsupported_reason_id"]=json!("reader.unsupported.pushup_body_backup");
   continue;
  }
  if !matches!(parts.as_slice(),["hair","parts",_,"pos"|"rot"|"scl",_]){continue}
  p["supported"]=json!(false);
  p["unsupported_reason"]=json!("Hair slot transform is parsed but not applied by the renderer");
  p["unsupported_reason_id"]=json!("reader.unsupported.hair_transform_not_applied");
 }
}
pub(super) fn patch_properties(original:&[u8],outfit:usize,edits:&[J])->Result<Vec<u8>,String>{
 if edits.is_empty()||edits.len()>8192{return Err("修改清單數量錯誤".into());}
 let (edits,physics_edits)=physics::take_edits(edits);
 if edits.is_empty(){return physics::apply(original,original,outfit,&physics_edits);}
 let edits=&edits[..];
 let allowed=catalog_properties(original,outfit)?;let mut changes=BTreeMap::new();
 for edit in edits {let key=text(edit,"key")?;let p=allowed.iter().find(|p|p["key"]==key).ok_or("找不到可編輯欄位")?;
  if changes.contains_key(key){return Err("修改清單含重複欄位".into());}
  let value=match p["kind"].as_str().unwrap_or("") {
   "bool"=>Value::Boolean(edit["value"].as_bool().ok_or("布林值格式錯誤")?),
   "parent"=>{let s=edit["value"].as_str().ok_or("骨架名稱格式錯誤")?;if s.len()>256||s.chars().any(char::is_control){return Err("骨架名稱不合法".into());}s.into()},
   _ if p["integer"]==true=>{let n=edit["value"].as_f64().ok_or("數值格式錯誤")?;let (lo,hi)=(p["min"].as_f64().unwrap_or(0.0),p["max"].as_f64().unwrap_or(0.0));
    if !n.is_finite()||n.fract()!=0.0||n<lo||n>hi{return Err("數值超出可用範圍".into());}Value::from(n as i64)},
   _ if p.get("min").is_some()&&p["kind"]=="number"=>Value::F32(ranged(p,edit["value"].as_f64().ok_or("數值格式錯誤")?)? as f32),
   // A number without range metadata: only finite (no made-up bound). A colour component is 0..1 by structure.
   kind=>{let n=edit["value"].as_f64().ok_or("數值格式錯誤")?;if !n.is_finite()||(kind=="color"&&!(0.0..=1.0).contains(&n)){return Err("數值超出可用範圍".into());}Value::F32(n as f32)}
  };changes.insert(key.to_string(),value);
 }
 let mut blocks=blocks_from_card(original)?;
 sections(&mut blocks,outfit,|name,v|{for(key,value)in &changes {if let Some(path)=key.strip_prefix(&format!("{name}.")){*at(v,path)?=value.clone();}}Ok(())})?;
 plugins::patch(&mut blocks,&changes,outfit)?;
 let card=super::write_blocks(original,blocks)?;
 if physics_edits.is_empty(){Ok(card)}else{physics::apply(original,&card,outfit,&physics_edits)}
}

/// Set card fields by path (`face.shapeValueFace.30`, `face.pupil.0.id`, `body.shapeValueBody.1`, ...) without the
/// editor's allow-list: tools building cards write ids and shape values too. Each value keeps the stored type
/// (an integer field stays an integer, a colour is four floats).
pub(crate) fn patch_paths(original:&[u8],outfit:usize,edits:&[(String,J)])->Result<Vec<u8>,String>{
 let mut blocks=blocks_from_card(original)?;
 let convert=|old:&Value,new:&J|->Result<Value,String>{Ok(match (old,new) {
  (Value::Integer(_),J::Number(n))=>Value::from(n.as_f64().ok_or("數值格式錯誤")?.round() as i64),
  (Value::Boolean(_),J::Bool(b))=>Value::Boolean(*b),
  (Value::Array(_),J::Array(a))=>Value::Array(a.iter().map(|x|x.as_f64().map(|f|Value::F32(f as f32)).ok_or("顏色格式錯誤")).collect::<Result<_,_>>()?),
  (_,J::Number(n))=>Value::F32(n.as_f64().ok_or("數值格式錯誤")? as f32),
  (_,J::String(s))=>Value::from(s.as_str()),
  _=>return Err("不支援的欄位型別".into()),
 })};
 let mut seen=0usize;
 sections(&mut blocks,outfit,|name,v|{for(key,value)in edits {if let Some(path)=key.strip_prefix(&format!("{name}.")){let slot=at(v,path)?;*slot=convert(slot,value)?;seen+=1;}}Ok(())})?;
 if seen!=edits.len(){return Err(format!("有 {} 個欄位不在卡片裡",edits.len()-seen));}
 super::write_blocks(original,blocks)
}

/// The street's clinics and salon (ok-rules clinic.rs, user 2026-11-03): `card` with the face shape of `donor` (its
/// face.shapeValueFace, the head stays hers) and/or every hair part dyed `rgb` (sRGB 0..1; the root a little darker,
/// the tips a little lighter, the outline darker, gloss and alpha kept). Either may be absent.
pub(crate) fn restyle(card:&[u8],donor:Option<&[u8]>,rgb:Option<[f32;3]>)->Result<Vec<u8>,String>{
 let mut edits:Vec<(String,J)>=Vec::new();
 if let Some(donor)=donor {for(k,v)in list_paths(donor,0)? {if k.starts_with("face.shapeValueFace."){let n:f64=v.parse().map_err(|_|"臉型數值格式錯誤")?;edits.push((k,json!(n)));}}if edits.is_empty(){return Err("對方的卡沒有臉型數值".into());}}
 if let Some(c)=rgb {
  let mine=list_paths(card,0)?;
  let alpha=|key:&str|mine.iter().find(|(p,_)|p==&format!("{key}.3")).and_then(|(_,v)|v.parse::<f32>().ok()).unwrap_or(1.0);
  for part in 0..8 {for(field,k)in [("baseColor",1.0f32),("startColor",0.85),("endColor",1.15),("outlineColor",0.45)] {
   let key=format!("hair.parts.{part}.{field}");
   if mine.iter().any(|(p,_)|p==&format!("{key}.0")){let a=alpha(&key);edits.push((key,json!([(c[0]*k).min(1.0),(c[1]*k).min(1.0),(c[2]*k).min(1.0),a])));}
  }}
  if !edits.iter().any(|(k,_)|k.starts_with("hair.")){return Err("卡片沒有頭髮顏色欄位".into());}
 }
 if edits.is_empty(){return Ok(card.to_vec());}
 let out=patch_paths(card,0,&edits)?;
 // Hair painted into its texture takes no colour from the card: the open recolours it (hair_dye.rs).
 match rgb {Some(c)=>crate::cardbake::with_chunk(&out,crate::hair_dye::CHUNK,&c.map(|v|(v.clamp(0.0,1.0)*255.0+0.5) as u8)),None=>Ok(out)}
}

/// The street's clothes (ok-rules wardrobe.rs, user 2026-11-04): `card` wearing each (outfit, part, list id, main colour)
/// of the original game's clothes; id 0 takes the part off. The new piece's patterns are cleared, its colours otherwise
/// stay what that part had. An outfit without bottoms is a one-piece (a mod's top the library cannot answer for included):
/// bottoms given to her would not show over it (the game's rule), so that top becomes a plain T-shirt, and a top given to
/// her alone comes with plain trousers. No game: the base library has the models, the card stays an OK card.
pub(crate) fn dress(card:&[u8],pieces:&[(usize,usize,i32,Option<[f32;3]>)])->Result<Vec<u8>,String>{
 const PLAIN_TOP:(i32,[f32;3])=(38,[0.95,0.95,0.95]);const PLAIN_BOTTOM:(i32,[f32;3])=(3,[0.18,0.2,0.25]);
 let mut out=card.to_vec();
 for &(outfit,part,id,rgb) in pieces {out=put_on(&out,outfit,part,id,rgb)?;out=overlays_off(&out,outfit,part)?;}
 let mut outfits:Vec<usize>=pieces.iter().map(|p|p.0).collect();outfits.sort_unstable();outfits.dedup();
 for outfit in outfits {
  let given=|part:usize|pieces.iter().find(|p|p.0==outfit&&p.1==part).map(|p|p.2);
  let bare=list_paths(card,outfit)?.iter().find(|(p,_)|p=="clothes.parts.1.id").is_none_or(|(_,v)|v=="0");
  if given(0).is_none()&&given(1).is_some_and(|id|id!=0)&&(bare||one_piece(&out,outfit)?){out=put_on(&out,outfit,0,PLAIN_TOP.0,Some(PLAIN_TOP.1))?;}
  if given(0).is_some_and(|id|id!=0)&&given(1).is_none()&&bare{out=put_on(&out,outfit,1,PLAIN_BOTTOM.0,Some(PLAIN_BOTTOM.1))?;}
  // Her gloves and tights go with her top (爱丽丝's strapped pink sleeves and her pink body suit stayed on under the shop's dress).
  for part in [4,5] {if given(0).is_some_and(|id|id!=0)&&given(part).is_none(){out=put_on(&out,outfit,part,0,None)?;out=overlays_off(&out,outfit,part)?;}}
  if given(0).is_some_and(|id|id!=0)||given(1).is_some_and(|id|id!=0){out=off_the_body(&out,outfit)?;}
 }
 crate::tree_answers::with_plain_bundles(&out)
}
fn put_on(card:&[u8],outfit:usize,part:usize,id:i32,rgb:Option<[f32;3]>)->Result<Vec<u8>,String>{
 let key=format!("clothes{part}");let t=super::targets().into_iter().find(|t|t.key==key).ok_or("沒有這個服裝部位")?;
 let item=(id!=0).then(||super::Item{key:String::new(),guid:String::new(),source:String::new(),entry:crate::list::ListEntry{category_no:t.category,id,..Default::default()}});
 let out=super::patch(card,&t,item.as_ref(),outfit)?;
 if id==0 {return Ok(out);}
 let mut edits:Vec<(String,J)>=(0..3).map(|c|(format!("clothes.parts.{part}.colorInfo.{c}.pattern"),json!(0))).collect();
 if let Some(c)=rgb {edits.push((format!("clothes.parts.{part}.colorInfo.0.baseColor"),json!([c[0],c[1],c[2],1.0])));}
 // A piece's other colour areas are the piece's, not those of what she wore there: the long coat of the floral dress came
 // out in the pink of 爱丽丝's top, in 安可's white in hers. The shop sells one dress.
 if part<=1 {for c in 1..3 {edits.push((format!("clothes.parts.{part}.colorInfo.{c}.baseColor"),json!([1.0,1.0,1.0,1.0])));}}
 patch_paths(&out,outfit,&edits)
}
/// A card's KoiClothesOverlay paints on the slot, not on the piece: 安可's red cheongsam was printed over the shop's floral
/// dress. A new piece in a slot starts without what was painted on the old one.
fn overlays_off(card:&[u8],outfit:usize,part:usize)->Result<Vec<u8>,String>{
 // With the top go the masks painted for it: 爱丽丝's BodyMask was made for her body suit, under the shop's dress the mask of
 // the dress never applied and her skin came through it.
 const SLOTS:[&[&str];9]=[&["ct_clothesTop","ct_top_parts_A","ct_top_parts_B","ct_top_parts_C","BodyMask","BraMask","InnerMask"],&["ct_clothesBot"],&["ct_bra"],&["ct_shorts"],&["ct_gloves"],&["ct_panst"],&["ct_socks"],&["ct_shoes_inner"],&["ct_shoes_outer"]];
 fn field<'a>(v:&'a mut Value,key:&str)->Option<&'a mut Value>{match v {Value::Map(m)=>m.iter_mut().find(|(k,_)|k.as_str()==Some(key)).map(|(_,v)|v),_=>None}}
 let Some(names)=SLOTS.get(part)else{return Ok(card.to_vec())};
 let mut blocks=blocks_from_card(card)?;let Some(raw)=blocks.get("KKEx").cloned()else{return Ok(card.to_vec())};
 let mut root=decode(&raw)?;let mut changed=false;
 if let Value::Map(plugins)=&mut root {for(k,plugin)in plugins.iter_mut(){
  if !k.as_str().is_some_and(|k|k.eq_ignore_ascii_case("KCOX")){continue;}
  let Some(data)=(match plugin {Value::Array(a)=>a.get_mut(1),v=>Some(v)})else{continue};
  let data=if field(data,"data").is_some(){field(data,"data").unwrap()}else{data};
  let Some(Value::Binary(bytes))=field(data,"Overlays")else{continue};
  let mut overlays=decode(bytes)?;
  if let Value::Map(coordinates)=&mut overlays {for(coordinate,values)in coordinates.iter_mut(){
   if coordinate.as_u64()==Some(outfit as u64){if let Value::Map(values)=values{let before=values.len();values.retain(|(name,_)|!name.as_str().is_some_and(|n|names.contains(&n)));changed|=values.len()!=before;}}}}
  *bytes=encode(&overlays)?;}}
 if !changed{return Ok(card.to_vec());}
 blocks.insert("KKEx".into(),encode(&root)?);super::write_blocks(card,blocks)
}
/// Where an accessory may stay when her clothes change: her hair, head and face. off_the_body() and its test both ask
/// this one list, so the rule for the twenty slots and for the MoreAccessories slots cannot drift apart.
const KEEPS:[&str;8]=["a_n_hair","a_n_head","a_n_ear","a_n_megane","a_n_nose","a_n_mouth","a_n_neck","a_n_face"];
/// Many cards build their outfit from accessories (爱丽丝's pink jacket hangs on her bust): with the shop's dress on she still
/// wore it. What hangs on her body comes off with her clothes, what is on her head and face stays hers.
fn off_the_body(card:&[u8],outfit:usize)->Result<Vec<u8>,String>{
 const NONE:i32=120;
 let paths=list_paths(card,outfit)?;let at=|k:String|paths.iter().find(|(p,_)|*p==k).map(|(_,v)|v.trim_matches('"').to_string());
 let mut edits:Vec<(String,J)>=Vec::new();let mut out=card.to_vec();
 for i in 0.. {let Some(kind)=at(format!("accessory.parts.{i}.type"))else{break};if kind==NONE.to_string(){continue;}
  let parent=at(format!("accessory.parts.{i}.parentKey")).unwrap_or_default();
  if !KEEPS.iter().any(|k|parent.starts_with(k)){
   // Through the slot's target: a mod's piece also has its sideloader record, which alone would bring it back.
   if let Some(t)=super::targets().into_iter().find(|t|t.key==format!("accessory{i}_{kind}")){out=super::patch(&out,&t,None,outfit)?;}
   edits.push((format!("accessory.parts.{i}.type"),json!(NONE)));}}
 // The slots past the card's twenty (MoreAccessories), where 爱丽丝 keeps most of her jacket.
 for(i,kind,parent)in super::extra::worn(&blocks_from_card(&out)?,outfit)? {
  if KEEPS.iter().any(|k|parent.starts_with(k)){continue;}
  // A slot of a type no target names (雷电将军's 109 on her waist) empties through any target of the slot.
  let targets=super::extra::targets_for(&blocks_from_card(&out)?,outfit)?;let slot=format!("parts.{i}.id");
  let t=targets.iter().find(|t|t.key==format!("accessory{i}_{kind}")).or_else(||targets.iter().find(|t|t.section=="accessory_extra"&&t.path==slot));
  if let Some(t)=t{out=super::patch(&out,t,None,outfit)?;}}
 if edits.is_empty(){return Ok(out);}
 patch_paths(&out,outfit,&edits)
}
/// Whether the outfit's top hides bottoms. Not knowing (a mod's top the library cannot answer for) is no.
fn one_piece(card:&[u8],outfit:usize)->Result<bool,String>{
 static N:std::sync::atomic::AtomicU64=std::sync::atomic::AtomicU64::new(0);
 let tmp=std::env::temp_dir().join(format!("ok-dress-{}-{}.png",std::process::id(),N.fetch_add(1,std::sync::atomic::Ordering::Relaxed)));
 fs::write(&tmp,card).map_err(|e|e.to_string())?;
 let rules=crate::clothing_rules::load_uncached(Path::new(""),&tmp,outfit as i32);let _=fs::remove_file(&tmp);
 Ok(rules.is_ok_and(|r|r.hides_bottoms()))
}

/// Every scalar field of the card's face/body/hair/outfit sections as (path, value text): what `patch_paths` can set.
pub(crate) fn list_paths(original:&[u8],outfit:usize)->Result<Vec<(String,String)>,String>{
 fn flat(v:&Value,path:&str,out:&mut Vec<(String,String)>){match v {
  Value::Map(m)=>for(k,v)in m {if let Some(k)=k.as_str(){flat(v,&format!("{path}.{k}"),out)}},
  Value::Array(a) if a.len()<=64=>for(i,v)in a.iter().enumerate(){flat(v,&format!("{path}.{i}"),out)},
  Value::Binary(_)|Value::Array(_)=>{},
  v=>out.push((path.to_string(),v.to_string())),
 }}
 let mut blocks=blocks_from_card(original)?;let mut out=Vec::new();
 sections(&mut blocks,outfit,|name,v|{flat(v,name,&mut out);Ok(())})?;Ok(out)
}

#[cfg(test)] mod tests {
 #[test]fn pushup_body_backup_is_offered_but_not_editable(){
  use super::{Value,encode};
  let body=Value::Map(vec![("Size".into(),Value::F32(0.5))]);
  let bra=Value::Map(vec![(Value::from(0),Value::Map(vec![("Firmness".into(),Value::F32(0.9))]))]);
  let kkex=Value::Map(vec![("com.deathweasel.bepinex.pushup".into(),Value::Map(vec![("Pushup_BodyData".into(),body),("Pushup_BraData".into(),bra)]))]);
  let blocks=super::BTreeMap::from([("KKEx".to_string(),encode(&kkex).unwrap())]);
  let mut props=Vec::new();super::plugins::catalog(&blocks,0,&mut props).unwrap();super::refuse_unapplied(&mut props);
  let row=|k:&str|props.iter().find(|p|p["key"]==k).unwrap_or_else(||panic!("{k} not in {props:?}")).clone();
  assert_eq!(row("plugins.Pushup.@Pushup_BodyData.@Size")["supported"],false);
  assert!(row("plugins.Pushup.@Pushup_BraData.#0.@Firmness").get("supported").is_none());
 }
 #[test]fn range_metadata_rounds_wraps_and_names_both_values(){
  let rot=range_meta("accessory.parts.3.addMove.2.4.1").unwrap();assert_eq!(rot["wrap"],true);
  assert_eq!(ranged(&rot,359.6).unwrap(),0.0);assert_eq!(ranged(&rot,-30.0).unwrap(),330.0);assert_eq!(ranged(&rot,725.0).unwrap(),5.0);
  let pos=range_meta("accessory.parts.3.addMove.2.0.2").unwrap();assert_eq!(ranged(&pos,1.26).unwrap(),1.3);
  let err=ranged(&pos,100.04).unwrap();assert_eq!(err,100.0);
  // Soft range: outside the slider is kept (rounded, never clamped); only limit_min／limit_max refuse.
  assert_eq!(ranged(&pos,100.06).unwrap(),100.1);assert_eq!(ranged(&pos,-250.0).unwrap(),-250.0);
  let mut limited=pos.clone();limited["limit_max"]=json!(100.0);let err=ranged(&limited,100.06).unwrap_err();assert!(err.contains("100.06")&&err.contains("100.1"),"{err}");
  assert!(ranged(&pos,f64::NAN).is_err()&&ranged(&pos,f64::INFINITY).is_err());
  let scl=range_meta("accessory.parts.0.addMove.2.5.0").unwrap();assert_eq!(ranged(&scl,0.004).unwrap(),0.0);assert_eq!(ranged(&scl,0.005).unwrap(),0.01);
  let tiling=range_meta("clothes.parts.0.colorInfo.2.tiling.1").unwrap();assert_eq!(ranged(&tiling,1.2).unwrap(),1.2);assert_eq!(tiling["default"],0.0);
  // An ABMX-style body value read from the card stays as it is and is marked, not clamped.
  let row=with_range(json!({"kind":"number","value":1.4}),"body.shapeValueBody.4");assert_eq!((row["value"].as_f64(),row["out_of_range"].as_bool()),(Some(1.4),Some(true)));
  assert!(with_range(json!({"kind":"number","value":0.4}),"body.shapeValueBody.4").get("out_of_range").is_none());
  assert!(with_range(json!({"kind":"number","value":400.0}),"accessory.parts.0.addMove.2.1.0").get("out_of_range").is_none());
  assert_eq!(range_meta("clothes.parts.0.colorInfo.2.rotate").unwrap()["default"],0.5);
  let face=range_meta("face.detailPower").unwrap();assert_eq!((face["max"].as_f64(),face["display_scale"].as_i64(),face.get("wrap")),(Some(1.0),Some(100),None));
  assert!(range_meta("hair.parts.0.length").is_none());
  assert_eq!(integer_choice("clothes.parts.0.sleevesType").unwrap().0,2);assert!(integer_choice("clothes.parts.1.sleevesType").is_none());
  assert_eq!(integer_choice("accessory.parts.12.hideCategory").unwrap().0,1);
 }
 use super::*;
 #[test]#[ignore="game oracle: reads the original KKS installation (set OK_TEST_GAME_ROOT)"]fn lean_card_property_request_recovers_original_mod_controls(){
  let root=&crate::test_support::game_path("");let card=crate::test_support::project_path!("Content/CharacterCards/CrowdAPNG/C000.png");
  let base=catalog_properties(&crate::gamefs::read(card).unwrap(),0).unwrap();
  let path=std::env::temp_dir().join(format!("ok-properties-{}-{}.json",std::process::id(),std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()));
  fs::write(&path,serde_json::to_vec(&json!({"action":"properties","card":card,"outfit":0,"cache":crate::test_support::project_path!("Saved/AppearanceEditor/cache")})).unwrap()).unwrap();
  let result=super::super::request(root,&path).unwrap();let props=result["properties"].as_array().unwrap();assert!(props.len()>base.len());assert!(props.iter().any(|p|p["key"].as_str().is_some_and(|k|k.starts_with("plugins."))));assert_eq!(result["parents"].as_array().unwrap().len(),55);assert!(props.iter().all(|p|!p["label"].as_str().unwrap().contains("進階設定（")));
  fs::write(format!("{}/../../Saved/Tests/EditorPropertiesRecoveredManifest-{}.json",env!("CARGO_MANIFEST_DIR"),std::process::id()),serde_json::to_vec_pretty(&result).unwrap()).unwrap();let _=fs::remove_file(path);
 }
 #[test]fn restyle_gives_her_the_donor_face_and_dyed_hair(){
  let card=crate::gamefs::read(crate::test_support::project_path!("Content/CharacterCards/CrowdAPNG/C000.png")).unwrap();
  let donor=crate::gamefs::read(crate::test_support::project_path!("Content/CharacterCards/CrowdAPNG/C001.png")).unwrap();
  let out=restyle(&card,Some(&donor),Some([0.9,0.56,0.66])).unwrap();
  let (got,want,mine)=(list_paths(&out,0).unwrap(),list_paths(&donor,0).unwrap(),list_paths(&card,0).unwrap());
  let face=|l:&[(String,String)]|l.iter().filter(|(k,_)|k.starts_with("face.shapeValueFace.")).cloned().collect::<Vec<_>>();
  assert!(!face(&want).is_empty());assert_eq!(face(&got),face(&want),"her face shape is the donor's");
  let base=got.iter().find(|(k,_)|k=="hair.parts.0.baseColor.0").unwrap().1.parse::<f32>().unwrap();assert!((base-0.9).abs()<1e-4);
  // Everything else of hers is untouched (her eyes, her head type, her clothes).
  for (k,v) in &mine {if !k.starts_with("face.shapeValueFace.")&&!k.starts_with("hair.parts."){assert_eq!(got.iter().find(|(g,_)|g==k).map(|(_,x)|x),Some(v),"{k}");}}
  let before=blocks_from_card(&card).unwrap();let after=blocks_from_card(&out).unwrap();for(name,bytes)in before{if name!="Custom"{assert_eq!(after[&name],bytes,"{name}");}}
 }
 #[test]fn dress_puts_the_shops_clothes_on_her_without_the_game(){
  let path="C:/portable/OpenKoikatsu/Content/CharacterCards/StreetHeroines/alice.png";if !Path::new(path).exists(){return;}
  let card=crate::gamefs::read(path).unwrap();
  let out=dress(&card,&[(0,0,56,Some([0.2,0.4,0.8])),(0,1,0,None),(0,7,11,None),(0,8,11,None),(3,2,8,None)]).unwrap();
  let (got,mine)=(list_paths(&out,0).unwrap(),list_paths(&card,0).unwrap());
  let at=|l:&[(String,String)],k:&str|l.iter().find(|(p,_)|p==k).map(|(_,v)|v.clone());
  assert_eq!(at(&got,"clothes.parts.0.id").as_deref(),Some("56"));assert_eq!(at(&got,"clothes.parts.1.id").as_deref(),Some("0"));assert_eq!(at(&got,"clothes.parts.8.id").as_deref(),Some("11"));
  assert!((at(&got,"clothes.parts.0.colorInfo.0.baseColor.2").unwrap().parse::<f32>().unwrap()-0.8).abs()<1e-4);
  assert_eq!(at(&list_paths(&out,3).unwrap(),"clothes.parts.2.id").as_deref(),Some("8"),"her swimsuit goes in her swimming outfit");
  // Only what she was given changed: her body, face and hair are hers.
  for(k,v)in &mine {if !k.starts_with("clothes.")&&!k.starts_with("accessory."){assert_eq!(at(&got,k).as_ref(),Some(v),"{k}");}}
  let tmp=std::env::temp_dir().join(format!("ok-dress-{}.png",std::process::id()));fs::write(&tmp,&out).unwrap();
  let opened=crate::oklib::open_test_card(&tmp,0);let _=fs::remove_file(&tmp);
  assert!(opened.unwrap().parts.iter().any(|p|p.role.starts_with("clothes")),"the new clothes are on her");
 }
 #[test]fn every_heroine_takes_the_dye_even_with_hair_painted_into_its_texture(){
  let dir="C:/portable/OpenKoikatsu/Content/CharacterCards/StreetHeroines";if !Path::new(dir).exists(){return;}
  let green=|p:&[u8]|{let i=crate::teximg::load_from_memory(p).unwrap().into_rgba8();let (mut r,mut g,mut n)=(0u64,0u64,0u64);for p in i.pixels(){if p[3]>128{r+=p[0] as u64;g+=p[1] as u64;n+=1;}}n==0||r==g||g>r};
  // Only the cards: a card folder may hold subdirectories (a KKS/ next to the heroines did this), and read_dir
  // hands those out too — opening one as a card is PermissionDenied (os error 5), not a card-reading failure.
  for path in fs::read_dir(dir).unwrap().flatten().map(|e|e.path()).filter(|p|p.extension().is_some_and(|e|e=="png")){let card=crate::gamefs::read(path.to_str().unwrap()).unwrap();
   let tmp=std::env::temp_dir().join(format!("ok-dye-{}-{}",std::process::id(),path.file_name().unwrap().to_string_lossy()));fs::write(&tmp,restyle(&card,None,Some([0.2,0.9,0.3])).unwrap()).unwrap();
   let s=crate::oklib::open_test_card(&tmp,0).unwrap();let _=fs::remove_file(&tmp);assert!(crate::hair_dye::dyeable(&s),"{path:?}");
   for i in crate::hair_dye::hair_parts(&s){let p=&s.parts[i];assert!(p.png.as_ref().is_none_or(|p|green(p)),"{path:?} {}",p.name);}}
 }
 #[test]fn dress_takes_off_what_she_wears_as_accessories(){
  let dir="C:/portable/OpenKoikatsu/Content/CharacterCards/StreetHeroines";if !Path::new(dir).exists(){return;}
  let stays=|parent:&str|super::KEEPS.iter().any(|k|parent.starts_with(k));
  for path in fs::read_dir(dir).unwrap().flatten().map(|e|e.path()).filter(|p|p.extension().is_some_and(|e|e=="png")){let card=crate::gamefs::read(path.to_str().unwrap()).unwrap();let mine=list_paths(&card,0).unwrap();let got=list_paths(&dress(&card,&[(0,0,55,None),(0,1,0,None)]).unwrap(),0).unwrap();
   let at=|l:&[(String,String)],k:&str|l.iter().find(|(p,_)|p==k).map(|(_,v)|v.trim_matches('"').to_string()).unwrap_or_default();
   for i in 0..20 {let k=format!("accessory.parts.{i}.type");let parent=at(&mine,&format!("accessory.parts.{i}.parentKey"));if at(&mine,&k)=="120"||at(&mine,&k).is_empty(){continue;}
    assert_eq!(at(&got,&k)=="120",!stays(&parent),"{k} {parent}");}
   let dressed=dress(&card,&[(0,0,55,None),(0,1,0,None)]).unwrap();
   // The extra (MoreAccessories) slots follow the same rule as the twenty: both are asked of super::KEEPS, so
   // this cannot drift from what dress() does. Spelling a narrower list here once said a mouth accessory had
   // "stayed on" when keeping it is correct — a change of clothes does not take the things off her face.
   for(i,_,parent)in super::super::extra::worn(&blocks_from_card(&dressed).unwrap(),0).unwrap(){assert!(stays(&parent),"extra slot {i} on {parent} stayed on");}
   let parsed=crate::card::parse_card_bytes(&dressed,0).unwrap();assert!(!parsed.clothes_masks.keys().any(|k|k.0==0),"the masks painted for her old top go with it");
   assert_eq!(at(&got,"clothes.parts.4.id"),"0","her gloves go with her top");assert_eq!(at(&got,"clothes.parts.5.id"),"0","her tights too");
   for c in 1..3 {assert_eq!(at(&got,&format!("clothes.parts.0.colorInfo.{c}.baseColor.1")).parse::<f32>().unwrap(),1.,"the dress's own colour area {c}");}}
 }
 /// Every piece the street sells opens and shows on every heroine (the base library has it). Run by hand after changing the stock.
 #[test]#[ignore="opens one card for each piece of catalog.json's clothes on each heroine, ten minutes"]fn every_clothes_item_opens(){
  let catalog:J=serde_json::from_slice(&fs::read("C:/portable/OpenKoikatsu/Content/IndependentResources/StreetSocialData/catalog.json").unwrap()).unwrap();
  if std::env::var_os("OK_BASE_LIBRARY").is_none(){std::env::set_var("OK_BASE_LIBRARY",Path::new(env!("CARGO_MANIFEST_DIR")).join("../../Content/IndependentResources/base_v1"));}
  let roles=["top","bot","bra","shorts","gloves","panst","socks","shoes","shoes"];
  let mut failed=Vec::new();let mut count=0;
  for card in fs::read_dir("C:/portable/OpenKoikatsu/Content/CharacterCards/StreetHeroines").unwrap().flatten().map(|e|e.path()).filter(|p|p.extension().is_some_and(|e|e=="png")) {
   let bytes=crate::gamefs::read(card.to_str().unwrap()).unwrap();let mut seen=std::collections::BTreeSet::new();
   for item in catalog["items"].as_array().unwrap() {
    if item["category"]!="clothes"{continue;}
    let wear=&item["clothes"];let outfit=wear["outfit"].as_i64().unwrap_or(-1).max(0) as usize;if !seen.insert(wear["parts"].to_string()){continue;}
    let pieces:Vec<_>=wear["parts"].as_array().unwrap().iter().map(|p|(outfit,p[0].as_u64().unwrap() as usize,p[1].as_i64().unwrap() as i32,None)).collect();
    let tmp=std::env::temp_dir().join(format!("ok-stock-{}.png",std::process::id()));fs::write(&tmp,dress(&bytes,&pieces).unwrap()).unwrap();count+=1;
    let at=format!("{} on {}",item["id"],card.display());
    match crate::oklib::open_test_card(&tmp,outfit as i32){
     Ok(s)=>{let on:std::collections::BTreeSet<_>=s.parts.iter().filter(|p|p.role.starts_with("clothes")).map(|p|format!("{}:{}",p.role,p.name)).collect();eprintln!("stock {at} {on:?}");
      for &(_,part,id,_) in &pieces {if id!=0&&part!=3&&!on.iter().any(|r|r.starts_with(&format!("clothes_{}:",roles[part]))){failed.push(format!("{at}: part {part} not shown"));}}}
     Err(e)=>failed.push(format!("{at}: {e}"))}
    let _=fs::remove_file(&tmp);
   }
  }
  eprintln!("stock pieces opened {count}");assert!(failed.is_empty(),"{failed:#?}");
 }
 #[test]fn properties_real_card_roundtrip_and_untouched_sections(){
  let original=crate::gamefs::read(crate::test_support::project_path!("Content/CharacterCards/CrowdAPNG/C000.png")).unwrap();
  let props=catalog_properties(&original,0).unwrap();assert!(props.len()>300);
  assert!(props.iter().any(|p|p["key"]=="clothes.parts.0.colorInfo.0.tiling.0"&&p["kind"]=="number"));
  for key in ["hair.parts.0.baseColor.0","face.eyelineColor.0","face.pupil.0.baseColor.0","accessory.parts.0.parentKey"]{assert!(props.iter().any(|p|p["key"]==key),"missing {key}");}
  let edits=vec![json!({"key":"hair.parts.0.baseColor.0","value":0.123}),json!({"key":"face.eyelineColor.0","value":0.234}),json!({"key":"accessory.parts.0.parentKey","value":"a_n_head"})];
  let changed=patch_properties(&original,0,&edits).unwrap();let result=catalog_properties(&changed,0).unwrap();
  for p in &props {let next=result.iter().find(|n|n["key"]==p["key"]).unwrap();if let Some(e)=edits.iter().find(|e|e["key"]==p["key"]){if let Some(v)=e["value"].as_f64(){assert!((next["value"].as_f64().unwrap()-v).abs()<1e-6)}else{assert_eq!(next["value"],e["value"]);}}else{assert_eq!(next,p);}}
  let before=blocks_from_card(&original).unwrap();let after=blocks_from_card(&changed).unwrap();for(name,bytes)in before{if !matches!(name.as_str(),"Custom"|"Coordinate"){assert_eq!(after[&name],bytes);}}
  assert!(patch_properties(&original,0,&[json!({"key":"hair.parts.0.id","value":9})]).is_err());
  assert!(patch_properties(&original,0,&[json!({"key":"hair.parts.0.baseColor.0","value":2})]).is_err());
 }
}
