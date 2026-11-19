//! KoiSkinOverlayX（`KSOX`）与 KoiClothesOverlayX（`KCOX`）的覆盖图：读一张卡有哪些、换图、清除、`Override`。
//!
//! 照 MaterialEditor 贴图（`textures.rs`）同一个形状：一个读的动作（`overlays`）、一个写的动作（`overlays_apply`），
//! 界面、`reader_call`、MCP 共用这一支写法。和那边不一样的地方：
//! * **卡上存的是 PNG bytes，不是 MaterialEditor 那种 texture id 指向共用字典的列**，所以身分也不同：
//!   KSOX 是（服装号, 覆盖种类 `TexType`），KCOX 是（服装号, 衣服物件名或遮罩名）。**都不用列号**：
//!   两个外挂都以字典存，顺序是每张卡自己的事。
//! * 放进卡的 bytes 就是使用者给的 PNG 档，**不压缩、不缩图、不重新编码**（那会改使用者的素材）。原作两个外挂
//!   读图时会 `EncodeToPNG` 重编一次，所以同一张图经原作存档后 bytes 会不同，但读回来是同一张图。
//!
//! 语意出处（`D:\XKoikatuSunshine\kks_decomp\plugins\KKS_OverlayMods\`）：
//! * KSOX `OverlayStorage.SetTexture`：给 bytes 就 `StoreTexture`（同 bytes 重用同一个 id），给 null 就从这套服装的
//!   `Lookup` **移除那一种**（清除＝该种类不存在，不是存一张空图）。`SetOverlayTex`：`EyeOver`／`EyeUnder`（6／5）
//!   不写自己，而是写左右两种（+2、+4）。`GetOverlayTextures`：某套服装还没有表时，若卡不是「每套服装各自」
//!   （`IsPerCoord()==false`）就复制第一套的表。`KoiSkinOverlayGui.SetTexAndUpdate`：「每套服装各自」没勾时，
//!   改完 `CopyToOtherCoords()`，所以一次改会套到所有服装。存档 `PurgeUnused`：没有任何服装引用的 `_TextureID_` 丢掉。
//! * KCOX `ClothesTexData`：`[Key(0)] TextureBytes`、`[Key(1)] Override`（隐藏原本的贴图）。GUI 清除是
//!   `SetTexAndUpdate(null, …)`，只把 bytes 设成 null；`CleanupTextureList` 在存档时把 `IsEmpty()`（没有 bytes 且
//!   `Override` 为 false）的项与空的服装丢掉——所以「清除」在 `Override` 开着时项还在。KCOX 没有跨服装复制。
//!
//! 体积：覆盖图建议大小是身体 2048²、脸 1024²、眼／眉／眼线 512²（`Util.GetRecommendedTexSize`）。一次换图让卡
//! 大约多出那个 PNG 档的大小（同一张图在同一张卡里只存一份：KSOX 按 bytes 去重；KCOX 每个物件各存一份）。
use super::*;

const KSOX: &str = "KSOX";
const KCOX: &str = "KCOX";
/// `KoiClothesOverlayMgr` 的衣服物件名，加 `MaskKind` 的三种遮罩。
const KCOX_SLOTS: &[&str] = &["ct_clothesTop", "ct_clothesBot", "ct_bra", "ct_shorts", "ct_gloves", "ct_panst", "ct_socks",
    "ct_shoes_inner", "ct_shoes_outer", "ct_top_parts_A", "ct_top_parts_B", "ct_top_parts_C", "BodyMask", "InnerMask", "BraMask"];
/// `KoiSkinOverlayX.TexType`。5／6（两眼一起）只是写入时的捷径，表里存的是左右各一。
const KSOX_TYPES: &[(i64, &str)] = &[(1, "BodyOver"), (2, "FaceOver"), (3, "BodyUnder"), (4, "FaceUnder"), (5, "EyeUnder"),
    (6, "EyeOver"), (7, "EyeUnderL"), (8, "EyeOverL"), (9, "EyeUnderR"), (10, "EyeOverR"), (20, "EyebrowUnder"), (30, "EyelineUnder")];

fn mget<'a>(v: &'a Value, k: &str) -> Option<&'a Value> { v.as_map()?.iter().find(|(key, _)| key.as_str() == Some(k)).map(|(_, v)| v) }
fn mset(v: &mut Value, k: &str, val: Value) -> Result<(), String> {
    let Value::Map(m) = v else { return Err("模组资料格式错误".into()) };
    match m.iter_mut().find(|(key, _)| key.as_str() == Some(k)) { Some((_, old)) => *old = val, None => m.push((k.into(), val)) }
    Ok(())
}
fn mremove(v: &mut Value, k: &str) { if let Value::Map(m) = v { m.retain(|(key, _)| key.as_str() != Some(k)); } }
fn png_size(b: &[u8]) -> Option<[u32; 2]> {
    (b.len() >= 24 && b.starts_with(b"\x89PNG")).then(|| [u32::from_be_bytes(b[16..20].try_into().unwrap()), u32::from_be_bytes(b[20..24].try_into().unwrap())])
}
fn read_png(path: &str) -> Result<Vec<u8>, String> {
    let bytes = fs::read(path).map_err(|e| format!("读不到覆盖图档案 {path}：{e}"))?;
    if png_size(&bytes).is_none() { return Err(format!("{path} 不是 PNG")) }
    Ok(bytes)
}
/// 这张卡的服装数（`ChaFile.coordinate.Length`）：KSOX 的「套到所有服装」就到这里为止。
fn coordinate_count(blocks: &BTreeMap<String, Vec<u8>>) -> usize {
    blocks.get("Coordinate").and_then(|b| decode(b).ok()).and_then(|v| v.as_array().map(Vec::len)).unwrap_or(1).max(1)
}
/// KKEx 里一个外挂那一节的 data map（`[版本, data]`，或旧卡直接是 map），没有就建一个（版本照外挂现行：KSOX 2、KCOX 1）。
fn section<'a>(kkex: &'a mut Value, key: &str, create_version: Option<i64>) -> Result<Option<&'a mut Value>, String> {
    let Value::Map(root) = kkex else { return Err("模组资料格式错误".into()) };
    let at = root.iter().position(|(k, _)| k.as_str().is_some_and(|k| k.eq_ignore_ascii_case(key)));
    let at = match (at, create_version) {
        (Some(i), _) => i,
        (None, Some(version)) => { root.push((key.into(), Value::Array(vec![version.into(), Value::Map(Vec::new())]))); root.len() - 1 }
        (None, None) => return Ok(None),
    };
    let v = &mut root[at].1;
    Ok(Some(match v { Value::Array(a) => a.get_mut(1).ok_or("模组资料格式错误")?, v => v }))
}
fn section_version(kkex: &Value, key: &str) -> Option<i64> {
    kkex.as_map()?.iter().find(|(k, _)| k.as_str().is_some_and(|k| k.eq_ignore_ascii_case(key)))
        .and_then(|(_, v)| v.as_array()).and_then(|a| a.first()).and_then(Value::as_i64)
}

// ---- KSOX ----
type Lookup = Vec<(i64, Vec<(i64, i64)>)>;
fn ksox_lookup(data: &Value) -> Lookup {
    mget(data, "Lookup").and_then(Value::as_slice).and_then(|b| decode(b).ok()).and_then(|v| v.as_map().map(|m| m.iter().filter_map(|(c, t)| {
        Some((c.as_i64()?, t.as_map()?.iter().filter_map(|(k, v)| Some((k.as_i64()?, v.as_i64()?))).collect()))
    }).collect())).unwrap_or_default()
}
fn ksox_textures(data: &Value) -> Vec<(i64, Vec<u8>)> {
    data.as_map().map(|m| m.iter().filter_map(|(k, v)| Some((k.as_str()?.strip_prefix("_TextureID_")?.parse().ok()?, v.as_slice()?.to_vec()))).collect()).unwrap_or_default()
}
/// `OverlayStorage.IsPerCoord`：任两套服装的表不同，才算「每套服装各自」。
fn ksox_per_coord(lookup: &Lookup) -> bool {
    let norm = |t: &Vec<(i64, i64)>| { let mut t = t.clone(); t.sort(); t };
    lookup.windows(2).any(|w| norm(&w[0].1) != norm(&w[1].1))
}
fn ksox_name(t: i64) -> &'static str { KSOX_TYPES.iter().find(|(k, _)| *k == t).map(|(_, n)| *n).unwrap_or("Unknown") }

// ---- KCOX ----
/// `ClothesTexData` 的两个栏位，存成 `[bytes, override]`（int key 的 MessagePack 物件），旧卡也可能是 `{0:…,1:…}`。
fn kcox_field(v: &Value, i: usize) -> Option<&Value> {
    v.as_array().and_then(|a| a.get(i)).or_else(|| v.as_map().and_then(|m| m.iter().find(|(k, _)| k.as_i64() == Some(i as i64)).map(|(_, v)| v)))
}
fn kcox_set(v: &mut Value, i: usize, val: Value) {
    match v {
        Value::Array(a) => { while a.len() <= i { a.push(if a.is_empty() { Value::Nil } else { Value::Boolean(false) }); } a[i] = val; }
        Value::Map(m) => match m.iter_mut().find(|(k, _)| k.as_i64() == Some(i as i64)) { Some((_, old)) => *old = val, None => m.push(((i as i64).into(), val)) },
        other => { let mut a = vec![Value::Nil, Value::Boolean(false)]; a[i] = val; *other = Value::Array(a); }
    }
}
fn kcox_overlays(data: &Value) -> Vec<(Value, Vec<(String, Value)>)> {
    mget(data, "Overlays").and_then(Value::as_slice).and_then(|b| decode(b).ok()).and_then(|v| v.as_map().map(|m| m.iter().filter_map(|(c, items)| {
        Some((c.clone(), items.as_map()?.iter().filter_map(|(k, v)| Some((k.as_str()?.to_string(), v.clone()))).collect()))
    }).collect())).unwrap_or_default()
}

/// 这张卡（这套服装）的覆盖图。身分栏位一起送出去，界面与写回都用它。
pub(super) fn list(original: &[u8], outfit: usize) -> Result<J, String> {
    let blocks = blocks_from_card(original)?;
    let Some(raw) = blocks.get("KKEx") else { return Ok(json!({"skin": [], "clothes": []})) };
    let mut kkex = decode(raw)?;
    let mut skin = Vec::new();
    let version = section_version(&kkex, KSOX);
    let mut per_coord = None;
    if let Some(data) = section(&mut kkex, KSOX, None)? {
        let lookup = ksox_lookup(data);let textures = ksox_textures(data);
        per_coord = Some(ksox_per_coord(&lookup));
        if let Some((_, types)) = lookup.iter().find(|(c, _)| *c == outfit as i64) {
            for (t, id) in types {
                let png = textures.iter().find(|(k, _)| k == id).map(|(_, b)| b.as_slice());
                skin.push(json!({"plugin": KSOX, "outfit": outfit, "type": t, "type_name": ksox_name(*t),
                    "bytes": png.map(<[u8]>::len), "size": png.and_then(png_size)}));
            }
        }
    }
    let mut clothes = Vec::new();
    if let Some(data) = section(&mut kkex, KCOX, None)? {
        for (c, items) in kcox_overlays(data) {
            if c.as_i64() != Some(outfit as i64) { continue }
            for (slot, v) in items {
                let png = kcox_field(&v, 0).and_then(Value::as_slice);
                clothes.push(json!({"plugin": KCOX, "outfit": outfit, "slot": slot, "override": kcox_field(&v, 1).and_then(Value::as_bool).unwrap_or(false),
                    "bytes": png.map(<[u8]>::len), "size": png.and_then(png_size)}));
            }
        }
    }
    // `per_coord`：false 时，原作改一套就会套到所有服装（见模组注释）；`overlays_apply` 也照这样做。
    Ok(json!({"skin": skin, "clothes": clothes, "skin_version": version, "skin_per_outfit": per_coord,
        "skin_types": KSOX_TYPES.iter().map(|(k, n)| json!({"type": k, "name": n})).collect::<Vec<_>>(), "clothes_slots": KCOX_SLOTS}))
}

/// 一批修改。每一笔：`plugin` 是 `KSOX` 或 `KCOX`；KSOX 给 `type`（`TexType` 数值），KCOX 给 `slot`（物件名或遮罩名）。
/// 动作三选一或合用：`png`（档案路径，换图）、`clear: true`（清除）、`override`（只有 KCOX）。服装号是请求的 `outfit`。
pub(super) fn apply(original: &[u8], outfit: usize, changes: &[J]) -> Result<Vec<u8>, String> {
    if changes.is_empty() || changes.len() > 256 { return Err("修改清单数量错误".into()) }
    let mut blocks = blocks_from_card(original)?;
    let coordinates = coordinate_count(&blocks);
    if outfit >= coordinates { return Err("服装索引超出范围".into()) }
    let mut kkex = match blocks.get("KKEx") { Some(b) => decode(b)?, None => Value::Map(Vec::new()) };
    for c in changes {
        let png = match c["png"].as_str().filter(|s| !s.is_empty()) { Some(p) => Some(read_png(p)?), None => None };
        let clear = c["clear"].as_bool() == Some(true);
        if png.is_some() && clear { return Err("换图与清除不能同时给".into()) }
        match c["plugin"].as_str() {
            Some(KSOX) => {
                if c.get("override").is_some() { return Err("KSOX 没有 override".into()) }
                let t = c["type"].as_i64().ok_or("缺少覆盖种类 type")?;
                if !KSOX_TYPES.iter().any(|(k, _)| *k == t) { return Err(format!("不认得的覆盖种类：{t}")) }
                if png.is_none() && !clear { return Err("KSOX 要给 png 或 clear".into()) }
                if section_version(&kkex, KSOX).is_some_and(|v| v <= 1) { return Err("这张卡的 KSOX 是旧版格式（v1），先在原作重新存一次".into()) }
                let data = section(&mut kkex, KSOX, Some(2))?.ok_or("无法建立 KSOX 资料")?;
                ksox_apply(data, outfit, coordinates, t, png)?;
            }
            Some(KCOX) => {
                let slot = c["slot"].as_str().ok_or("缺少覆盖物件 slot")?;
                if !KCOX_SLOTS.contains(&slot) { return Err(format!("不认得的覆盖物件：{slot}")) }
                let ov = match c.get("override") { None | Some(J::Null) => None, Some(v) => Some(v.as_bool().ok_or("override 要是布林")?) };
                if png.is_none() && !clear && ov.is_none() { return Err("KCOX 要给 png、clear 或 override".into()) }
                let data = section(&mut kkex, KCOX, Some(1))?.ok_or("无法建立 KCOX 资料")?;
                kcox_apply(data, outfit, coordinates, slot, png, clear, ov)?;
            }
            _ => return Err("plugin 要是 KSOX 或 KCOX".into()),
        }
    }
    blocks.insert("KKEx".into(), encode(&kkex)?);
    write_blocks(original, blocks)
}

fn ksox_apply(data: &mut Value, outfit: usize, coordinates: usize, t: i64, png: Option<Vec<u8>>) -> Result<(), String> {
    let mut lookup = ksox_lookup(data);let mut textures = ksox_textures(data);
    let per_coord = ksox_per_coord(&lookup);
    let outfit = outfit as i64;
    if !lookup.iter().any(|(c, _)| *c == outfit) {
        // `GetOverlayTextures`：还没有表时，不是每套各自就复制第一套的表。
        let start = if per_coord { Vec::new() } else { lookup.first().map(|(_, t)| t.clone()).unwrap_or_default() };
        lookup.push((outfit, start));
    }
    let id = match png {
        // `StoreTexture`：同 bytes 重用；新 id 原作取 1000..9989 的乱数，这里取 1000 起第一个没用过的（任何没用过的 id 都合法）。
        Some(bytes) => Some(match textures.iter().find(|(_, b)| *b == bytes) {
            Some((k, _)) => *k,
            None => { let id = (1000..).find(|k| !textures.iter().any(|(t, _)| t == k)).unwrap(); textures.push((id, bytes)); id }
        }),
        None => None,
    };
    let kinds: Vec<i64> = if t == 5 || t == 6 { vec![t + 2, t + 4] } else { vec![t] };
    let table = &mut lookup.iter_mut().find(|(c, _)| *c == outfit).unwrap().1;
    for k in kinds {
        table.retain(|(x, _)| *x != k);
        if let Some(id) = id { table.push((k, id)); }
    }
    // `SetTexAndUpdate` + 「每套服装各自」没勾：`CopyToOtherCoords`。
    if !per_coord {
        let current = table.clone();
        for c in 0..coordinates as i64 {
            match lookup.iter_mut().find(|(x, _)| *x == c) { Some((_, t)) => *t = current.clone(), None => lookup.push((c, current.clone())) }
        }
    }
    // 存档时 `PurgeUnused`：没有任何服装引用的贴图丢掉。
    textures.retain(|(id, _)| lookup.iter().any(|(_, t)| t.iter().any(|(_, x)| x == id)));
    lookup.sort_by_key(|(c, _)| *c);
    let packed = Value::Map(lookup.into_iter().map(|(c, t)| (c.into(), Value::Map(t.into_iter().map(|(k, v)| (k.into(), v.into())).collect()))).collect());
    mset(data, "Lookup", Value::Binary(encode(&packed)?))?;
    let stale: Vec<String> = data.as_map().map(|m| m.iter().filter_map(|(k, _)| k.as_str().filter(|k| k.starts_with("_TextureID_")).map(str::to_string)).collect()).unwrap_or_default();
    for k in stale { mremove(data, &k); }
    for (id, bytes) in textures { mset(data, &format!("_TextureID_{id}"), Value::Binary(bytes))?; }
    Ok(())
}

fn kcox_apply(data: &mut Value, outfit: usize, coordinates: usize, slot: &str, png: Option<Vec<u8>>, clear: bool, ov: Option<bool>) -> Result<(), String> {
    let mut all = kcox_overlays(data);
    let key = Value::from(outfit as i64);
    if !all.iter().any(|(c, _)| c.as_i64() == Some(outfit as i64)) { all.push((key, Vec::new())); }
    let items = &mut all.iter_mut().find(|(c, _)| c.as_i64() == Some(outfit as i64)).unwrap().1;
    if !items.iter().any(|(s, _)| s == slot) {
        if clear && ov.is_none() { return Ok(()) } // 本来就没有：清除的结果一样。
        items.push((slot.to_string(), Value::Array(vec![Value::Nil, Value::Boolean(false)])));
    }
    let entry = &mut items.iter_mut().find(|(s, _)| s == slot).unwrap().1;
    if let Some(bytes) = png { kcox_set(entry, 0, Value::Binary(bytes)); }
    if clear { kcox_set(entry, 0, Value::Nil); }
    if let Some(b) = ov { kcox_set(entry, 1, Value::Boolean(b)); }
    // `CleanupTextureList`：没有图又没开 Override 的项、空的服装、超出服装数的服装丢掉。
    for (_, items) in all.iter_mut() {
        items.retain(|(_, v)| kcox_field(v, 0).is_some_and(|b| b.as_slice().is_some()) || kcox_field(v, 1).and_then(Value::as_bool) == Some(true));
    }
    all.retain(|(c, items)| !items.is_empty() && c.as_i64().is_some_and(|c| c >= 0 && (c as usize) < coordinates));
    let packed = Value::Map(all.into_iter().map(|(c, items)| (c, Value::Map(items.into_iter().map(|(s, v)| (s.into(), v)).collect()))).collect());
    mset(data, "Overlays", Value::Binary(encode(&packed)?))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn png(w: u32, h: u32, tag: u8) -> Vec<u8> {
        let mut b = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();b.extend(w.to_be_bytes());b.extend(h.to_be_bytes());b.push(tag);b
    }
    fn ksox(lookup: Value, textures: &[(i64, Vec<u8>)]) -> Value {
        let mut m = vec![("Lookup".into(), Value::Binary(encode(&lookup).unwrap()))];
        for (id, b) in textures { m.push((format!("_TextureID_{id}").into(), Value::Binary(b.clone()))); }
        Value::Array(vec![2.into(), Value::Map(m)])
    }
    fn table(pairs: &[(i64, i64)]) -> Value { Value::Map(pairs.iter().map(|(k, v)| ((*k).into(), (*v).into())).collect()) }

    #[test]
    fn ksox_clear_removes_the_kind_and_shared_edits_reach_every_outfit() {
        // Two outfits with the same table: not per-outfit, so an edit to outfit 1 lands on both (CopyToOtherCoords).
        let lookup = Value::Map(vec![(0.into(), table(&[(1, 1500)])), (1.into(), table(&[(1, 1500)]))]);
        let mut data = match ksox(lookup, &[(1500, png(2048, 2048, 1))]) { Value::Array(mut a) => a.remove(1), _ => unreachable!() };
        ksox_apply(&mut data, 1, 2, 2, Some(png(1024, 1024, 2))).unwrap();
        let l = ksox_lookup(&data);
        assert!(l.iter().all(|(_, t)| t.iter().any(|(k, _)| *k == 2)), "{l:?}");
        // Clear: the kind leaves the table (not an empty picture); its texture is purged when nothing uses it.
        ksox_apply(&mut data, 0, 2, 2, None).unwrap();
        assert!(ksox_lookup(&data).iter().all(|(_, t)| t.iter().all(|(k, _)| *k != 2)));
        assert_eq!(ksox_textures(&data).len(), 1);
        // Both eyes (6) write left and right (8, 10), not 6.
        ksox_apply(&mut data, 0, 2, 6, Some(png(512, 512, 3))).unwrap();
        let t = &ksox_lookup(&data)[0].1;assert!(t.iter().any(|(k, _)| *k == 8) && t.iter().any(|(k, _)| *k == 10) && !t.iter().any(|(k, _)| *k == 6));
    }

    #[test]
    fn ksox_per_outfit_edit_stays_on_its_outfit_and_reuses_identical_bytes() {
        let lookup = Value::Map(vec![(0.into(), table(&[(1, 1500)])), (1.into(), table(&[(2, 1501)]))]);
        let a = png(2048, 2048, 1);
        let mut data = match ksox(lookup, &[(1500, a.clone()), (1501, png(1024, 1024, 2))]) { Value::Array(mut v) => v.remove(1), _ => unreachable!() };
        ksox_apply(&mut data, 1, 2, 3, Some(a.clone())).unwrap();
        let l = ksox_lookup(&data);
        assert!(!l[0].1.iter().any(|(k, _)| *k == 3));
        assert_eq!(l[1].1.iter().find(|(k, _)| *k == 3).map(|(_, id)| *id), Some(1500), "same bytes reuse the same id");
        assert_eq!(ksox_textures(&data).len(), 2);
    }

    #[test]
    fn kcox_clear_keeps_an_override_entry_and_drops_an_empty_one() {
        let mut data = Value::Map(Vec::new());
        kcox_apply(&mut data, 0, 2, "ct_clothesTop", Some(png(512, 512, 1)), false, Some(true)).unwrap();
        kcox_apply(&mut data, 0, 2, "ct_bra", Some(png(512, 512, 2)), false, None).unwrap();
        // Clearing the top keeps its entry (Override still hides the base texture); clearing the bra drops it.
        kcox_apply(&mut data, 0, 2, "ct_clothesTop", None, true, None).unwrap();
        kcox_apply(&mut data, 0, 2, "ct_bra", None, true, None).unwrap();
        let all = kcox_overlays(&data);
        let items = &all.iter().find(|(c, _)| c.as_i64() == Some(0)).unwrap().1;
        assert_eq!(items.len(), 1);assert_eq!(items[0].0, "ct_clothesTop");
        assert!(kcox_field(&items[0].1, 0).unwrap().is_nil());assert_eq!(kcox_field(&items[0].1, 1).and_then(Value::as_bool), Some(true));
        // Turning Override off on an entry without a picture removes it, and the empty outfit with it.
        kcox_apply(&mut data, 0, 2, "ct_clothesTop", None, false, Some(false)).unwrap();
        assert!(kcox_overlays(&data).is_empty());
    }

    #[test]
    fn stored_bytes_are_the_users_file_unchanged() {
        let mut data = Value::Map(Vec::new());let b = png(2048, 2048, 7);
        kcox_apply(&mut data, 0, 1, "ct_clothesBot", Some(b.clone()), false, None).unwrap();
        let all = kcox_overlays(&data);assert_eq!(kcox_field(&all[0].1[0].1, 0).and_then(Value::as_slice), Some(b.as_slice()));
    }
}
