//! MaterialEditor 的**贴图**：作者指派给某个材质属性的 PNG（`TextureDictionary` id → bytes）与指派本身
//! （`MaterialTexturePropertyList` 的一列），加上那列的偏移与缩放。
//!
//! 为什么另开一个动作而不是走 `plugins.*` 属性键：属性那条路只送得出数字、布林与颜色，一张 PNG 不是属性值；
//! 而且 `properties/plugins.rs` 的 `visit()` 刻意按名字跳过所有含 `texture` 的栏位，连同整列的偏移与缩放一起跳掉。
//! **那个跳过应该留着**：同一笔资料在两个地方可改，等于其中一边的修改会被另一边无声盖掉（`plugins.rs` 自己为
//! ABMX 写下的理由）。所以整列贴图（bytes、偏移、缩放）只由这里负责。
//!
//! 语义全部照原作 `MaterialEditorCharaController`（`D:\XKoikatuSunshine\kks_decomp\plugins\KKS_Plugins\
//! KKS_MaterialEditor\KK_Plugins.MaterialEditor\MaterialEditorCharaController.cs`）：
//! * 一列的身分是 5 个栏位 `(ObjectType, CoordinateIndex, Slot, MaterialName, Property)`（`FirstOrDefault` 的条件），
//!   **不是它在清单里的第几个**。清单的顺序是这张卡自己的事。
//! * `SetAndGetTextureID`（1281）：字典里已有**完全相同的 bytes** 就重用那个 id，否则 `max(已有 id)+1`（空字典从 1 起）。
//! * `RemoveMaterialTexture`（2166）：只把 `TexID` 设成 nil，**列不一定删** —— 只有 `NullCheck()`（TexID、Offset、
//!   Scale 三个都没有）才删掉整列。照直觉「清除贴图就删列」会把同一列上的偏移与缩放一起弄丢。
//! * `PurgeUnusedTextures`（2512）：存档前把没有任何列引用的字典项丢掉，所以这里每次写回都做一次，不只在清除时做。
use super::*;

/// `MaterialEditorCharaController.ObjectType`（22）。`slot` 的意思跟着它变：服装是部位、饰品是饰品栏、
/// 头发是四个部位之一、角色本体是 0。原作的 `GetCoordinateIndex` 只有服装与饰品用当前服装号，其他一律 0。
const OBJECT_KINDS: [&str; 5] = ["unknown", "clothing", "accessory", "hair", "character"];

const ME_SECTION: &str = "com.deathweasel.bepinex.materialeditor";
const LIST: &str = "MaterialTexturePropertyList";
const DICT: &str = "TextureDictionary";

/// 一列的身分。原作用这 5 个栏位找列，所以这里也只用这 5 个。
#[derive(Clone, PartialEq, Debug)]
struct Row { object: i64, coordinate: i64, slot: i64, material: String, property: String }
impl Row {
    fn of(v: &Value) -> Option<Self> {
        let i = |k: &str| mget(v, k).and_then(Value::as_i64);
        let s = |k: &str| mget(v, k).and_then(Value::as_str).map(str::to_string);
        Some(Self { object: i("ObjectType")?, coordinate: i("CoordinateIndex").unwrap_or(0),
            slot: i("Slot").unwrap_or(0), material: s("MaterialName")?, property: s("Property")? })
    }
    fn from_request(c: &J, outfit: usize) -> Result<Self, String> {
        let object = c["object"].as_i64().ok_or("缺少 object（材质属于哪一种物件）")?;
        let material = c["material"].as_str().filter(|s| !s.is_empty()).ok_or("缺少 material")?.to_string();
        let property = c["property"].as_str().filter(|s| !s.is_empty()).ok_or("缺少 property")?.to_string();
        // 原作的 `GetCoordinateIndex`：只有服装（1）与饰品（2）用当前服装号，其他一律 0。少给就按这个规则补，
        // 不要默默填成「现在穿的那套」——那会在角色本体的列上写出一个不存在的服装号。
        let coordinate = c["coordinate"].as_i64()
            .unwrap_or(if matches!(object, 1 | 2) { outfit as i64 } else { 0 });
        Ok(Self { object, coordinate, slot: c["slot"].as_i64().unwrap_or(0), material, property })
    }
}
fn mget<'a>(v: &'a Value, k: &str) -> Option<&'a Value> {
    v.as_map()?.iter().find(|(key, _)| key.as_str() == Some(k)).map(|(_, v)| v)
}
fn mset(v: &mut Value, k: &str, val: Value) -> Result<(), String> {
    let Value::Map(m) = v else { return Err("贴图列格式错误".into()) };
    if let Some((_, slot)) = m.iter_mut().find(|(key, _)| key.as_str() == Some(k)) { *slot = val; }
    else { m.push((k.into(), val)); }
    Ok(())
}
/// 两个浮点一组（偏移／缩放）。原作是 `Vector2?`，不同 MessagePack resolver 存成 `[x,y]` 或 `{x,y}`，
/// 读的时候两种都收（`studio_scene.rs` 早就这样读）。
fn vec2(v: Option<&Value>) -> Option<[f64; 2]> {
    let v = v?;
    if v.is_nil() { return None }
    if let Some(a) = v.as_array() { return Some([a.first()?.as_f64()?, a.get(1)?.as_f64()?]) }
    Some([mget(v, "x")?.as_f64()?, mget(v, "y")?.as_f64()?])
}
/// 写出 `Vector2`。形状的权威出处是**原作带的 MessagePack 格式器**，不是某张卡：
/// `D:\XKoikatuSunshine\kks_decomp\Managed\KoikatsuSunshine_Data\Assembly-CSharp-firstpass\
/// MessagePack.Unity\Vector2Formatter.cs` 的 `Serialize`：
/// `WriteFixedArrayHeaderUnsafe(…, 2)` 加两个 `WriteSingle` —— 也就是**两个 float32 的阵列**，
/// 不是 `{x,y}` map，也不是 float64。（`Deserialize` 碰到 nil 直接 throw，所以 `Vector2?` 的 nil
/// 是 Nullable 格式器写的，读到 nil 不会进这支。）
///
/// 这个格式器真的就是在用的那支，有实卡可证：同一家族的 `ColorFormatter.cs` 写的是 4 个 float32 的阵列，
/// 而 alice 的 `MaterialColorPropertyList` 里 `Value` 正是 4 元素阵列（键 `….@Value.a0`）——只有这支格式器
/// 会写成那样。所以「卡上没有偏移所以形状未知」是错的：样本缺一笔不代表形状未知。
fn vec2_value(xy: [f64; 2]) -> Value {
    Value::Array(vec![Value::F32(xy[0] as f32), Value::F32(xy[1] as f32)])
}
fn png_size(b: &[u8]) -> Option<[u32; 2]> {
    if b.len() < 24 || !b.starts_with(b"\x89PNG") { return None }
    Some([u32::from_be_bytes(b[16..20].try_into().ok()?), u32::from_be_bytes(b[20..24].try_into().ok()?)])
}

/// KKEx 里 MaterialEditor 那一节的 data map，可改。形状与 `card::me_plugin_data` 一样（`[版本, data]`，
/// 旧卡是 map，还可能再包一层 `data`），两边要一起改。
fn section_data(kkex: &mut Value) -> Result<&mut Value, String> {
    let Value::Map(m) = kkex else { return Err("模组资料格式错误".into()) };
    let section = m.iter_mut()
        .find(|(k, _)| k.as_str().is_some_and(|k| k.eq_ignore_ascii_case(ME_SECTION)))
        .map(|(_, v)| v).ok_or("这张卡没有 MaterialEditor 的资料")?;
    let data = match section { Value::Array(a) => a.get_mut(1).ok_or("MaterialEditor 资料格式错误")?, v => v };
    let nested = matches!(data, Value::Map(m) if m.iter().any(|(k, _)| k.as_str() == Some("data")));
    if nested {
        let Value::Map(m) = data else { unreachable!("just matched a map") };
        return m.iter_mut().find(|(k, _)| k.as_str() == Some("data")).map(|(_, v)| v)
            .ok_or_else(|| "MaterialEditor 资料格式错误".to_string());
    }
    Ok(data)
}
/// 清单与字典都是「再包一层 msgpack bytes」。读不出来就当空的，不要把整张卡当坏卡：
/// 一张没有任何贴图覆写的卡，这两个键可能根本不在，或是 nil。
fn packed(data: &Value, name: &str) -> Vec<Value> {
    mget(data, name).and_then(Value::as_slice)
        .and_then(|b| rmpv::decode::read_value(&mut Cursor::new(b)).ok())
        .and_then(|v| v.as_array().map(|a| a.to_vec())).unwrap_or_default()
}
fn packed_map(data: &Value, name: &str) -> Vec<(i64, Vec<u8>)> {
    mget(data, name).and_then(Value::as_slice)
        .and_then(|b| rmpv::decode::read_value(&mut Cursor::new(b)).ok())
        .and_then(|v| v.as_map().map(|m| m.iter()
            .filter_map(|(k, v)| Some((k.as_i64()?, v.as_slice()?.to_vec()))).collect()))
        .unwrap_or_default()
}

/// 这张卡（这套服装）的贴图列。身分 5 栏位一起送出去，界面与写回都用它，不用列号。
pub(super) fn list(original: &[u8], outfit: usize) -> Result<Vec<J>, String> {
    let blocks = blocks_from_card(original)?;
    let Some(b) = blocks.get("KKEx") else { return Ok(Vec::new()) };
    let mut v = decode(b)?;
    let Ok(data) = section_data(&mut v) else { return Ok(Vec::new()) };
    let (rows, dict) = (packed(data, LIST), packed_map(data, DICT));
    let mut out = Vec::new();
    for row in &rows {
        let Some(id) = Row::of(row) else { continue };
        // 服装与饰品的列每套服装都在同一份清单里，只有现在穿的那套改得动预览（`plugins.rs` 同一个判断）。
        if matches!(id.object, 1 | 2) && id.coordinate != outfit as i64 { continue }
        let tex = mget(row, "TexID").and_then(Value::as_i64);
        let png = tex.and_then(|t| dict.iter().find(|(k, _)| *k == t)).map(|(_, b)| b);
        out.push(json!({ "object": id.object,
            "kind": OBJECT_KINDS.get(id.object.clamp(0, 4) as usize).copied().unwrap_or("unknown"),
            "coordinate": id.coordinate, "slot": id.slot,
            "material": id.material, "property": id.property, "tex_id": tex,
            "bytes": png.map(Vec::len),
            "size": png.and_then(|b| png_size(b)).map(|s| json!([s[0], s[1]])),
            "offset": vec2(mget(row, "Offset")).map(|o| json!([o[0], o[1]])),
            "scale": vec2(mget(row, "Scale")).map(|s| json!([s[0], s[1]])) }));
    }
    Ok(out)
}

/// 一笔修改。`png` 是档案路径（原作就是 `SetMaterialTextureFromFile`，整个档案的 bytes 原封不动存进字典）；
/// `clear` 清掉贴图；`offset`／`scale` 给两个数就写、给 null 就移除。
pub(super) fn apply(original: &[u8], outfit: usize, changes: &[J]) -> Result<Vec<u8>, String> {
    if changes.is_empty() { return Err("缺少修改清单".into()) }
    let mut blocks = blocks_from_card(original)?;
    let mut v = decode(blocks.get("KKEx").ok_or("缺少模组资料")?)?;
    let data = section_data(&mut v)?;
    let (mut rows, mut dict) = (packed(data, LIST), packed_map(data, DICT));
    for c in changes {
        let want = Row::from_request(c, outfit)?;
        let at = rows.iter().position(|r| Row::of(r).as_ref() == Some(&want));
        if let Some(path) = c["png"].as_str().filter(|s| !s.is_empty()) {
            let bytes = fs::read(path).map_err(|e| format!("读不到贴图档案 {path}：{e}"))?;
            if !bytes.starts_with(b"\x89PNG") { return Err(format!("{path} 不是 PNG")) }
            // `SetAndGetTextureID`：同样的 bytes 重用同一个 id，否则 max+1。
            let id = match dict.iter().find(|(_, b)| *b == bytes) {
                Some((k, _)) => *k,
                None => { let id = dict.iter().map(|(k, _)| *k).max().unwrap_or(0) + 1; dict.push((id, bytes)); id }
            };
            match at {
                Some(i) => mset(&mut rows[i], "TexID", id.into())?,
                None => rows.push(Value::Map(vec![
                    ("ObjectType".into(), want.object.into()), ("CoordinateIndex".into(), want.coordinate.into()),
                    ("Slot".into(), want.slot.into()), ("MaterialName".into(), want.material.clone().into()),
                    ("Property".into(), want.property.clone().into()), ("TexID".into(), id.into())])),
            }
        } else if c["clear"].as_bool() == Some(true) {
            // 找不到列不是错：那就是「本来就没有覆写」，清除的结果一样。
            if let Some(i) = at { mset(&mut rows[i], "TexID", Value::Nil)?; }
        }
        for (name, key) in [("offset", "Offset"), ("scale", "Scale")] {
            // 没提这个键就不动它；提了 null 才是「移除」。
            if !c.as_object().is_some_and(|o| o.contains_key(name)) { continue }
            let Some(i) = rows.iter().position(|r| Row::of(r).as_ref() == Some(&want))
                else { return Err(format!("这张卡没有这一列，不能只改{}：先指派贴图",
                    if name == "offset" { "偏移" } else { "缩放" })) };
            match c[name].as_array() {
                Some(xy) => {
                    let xy = [xy.first().and_then(J::as_f64).ok_or("偏移／缩放要两个数")?,
                        xy.get(1).and_then(J::as_f64).ok_or("偏移／缩放要两个数")?];
                    mset(&mut rows[i], key, vec2_value(xy))?
                }
                None => mset(&mut rows[i], key, Value::Nil)?,
            }
        }
    }
    // `NullCheck`：TexID、Offset、Scale 三个都没有的列才删。
    rows.retain(|r| ["TexID", "Offset", "Scale"].iter().any(|k| mget(r, k).is_some_and(|v| !v.is_nil())));
    // `PurgeUnusedTextures`：没有任何列引用的字典项丢掉。原作每次存档都做。
    let used: Vec<i64> = rows.iter().filter_map(|r| mget(r, "TexID").and_then(Value::as_i64)).collect();
    dict.retain(|(k, _)| used.contains(k));
    let pack = |v: &Value| -> Result<Value, String> { Ok(Value::Binary(encode(v)?)) };
    mset(data, LIST, if rows.is_empty() { Value::Nil } else { pack(&Value::Array(rows))? })?;
    mset(data, DICT, if dict.is_empty() { Value::Nil }
        else { pack(&Value::Map(dict.into_iter().map(|(k, b)| (k.into(), Value::Binary(b))).collect()))? })?;
    blocks.insert("KKEx".into(), encode(&v)?);
    write_blocks(original, blocks)
}

#[cfg(test)]
mod tests {
    use super::*;
    /// 1×1 的合法 PNG，手写在这里：测试要的是「一个档案的 bytes 原封不动进字典」，
    /// 不是图片内容，所以不另外带素材档进版控。
    const TINY_PNG: &[u8] = &[
        0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a,
        0, 0, 0, 13, b'I', b'H', b'D', b'R', 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0,
        0x1f, 0x15, 0xc4, 0x89,
        0, 0, 0, 10, b'I', b'D', b'A', b'T', 0x78, 0x9c, 0x63, 0, 1, 0, 0, 5, 0, 1,
        0x0d, 0x0a, 0x2d, 0xb4,
        0, 0, 0, 0, b'I', b'E', b'N', b'D', 0xae, 0x42, 0x60, 0x82,
    ];

    /// `Vector2`／`Color` 在这个游戏的 MessagePack 里是**float32 的定长阵列**，不是 `{x,y}` map。
    /// 格式器出处写在 `vec2_value` 上；这支测试用实卡把同一家族的 `Color` 钉住，因为目前没有任何一张卡
    /// 带 `Offset`／`Scale`，而 `Color` 与 `Vector2` 是同一支 resolver 下的同一种写法。
    /// 卡片只在本机（不进版控），所以 `#[ignore]`：
    /// `cargo test --release --lib textures::tests -- --ignored --nocapture`
    #[test]
    #[ignore = "需要本机的卡片（Content/CharacterCards/ 不进版控）"]
    fn unity_structs_are_float32_arrays_on_a_real_card() {
        let card = fs::read(concat!(env!("CARGO_MANIFEST_DIR"), "/../../Content/CharacterCards/StreetHeroines/alice.png"))
            .expect("读 alice");
        let blocks = blocks_from_card(&card).expect("blocks");
        let mut v = decode(blocks.get("KKEx").expect("KKEx")).expect("decode");
        let data = section_data(&mut v).expect("MaterialEditor");
        let rows = packed(data, "MaterialColorPropertyList");
        assert!(!rows.is_empty(), "alice 应该有颜色覆写");
        let value = mget(&rows[0], "Value").expect("Value");
        let a = value.as_array().expect("Color 应该是阵列，不是 map");
        assert_eq!(a.len(), 4, "ColorFormatter 写 4 个分量：{value}");
        assert!(a.iter().all(|x| matches!(x, Value::F32(_))), "WriteSingle 写 float32：{value}");
        // 同一个 resolver 的 Vector2Formatter 写 2 个 float32，所以我们也这样写。
        assert_eq!(vec2_value([0.25, -0.5]), Value::Array(vec![Value::F32(0.25), Value::F32(-0.5)]));
    }

    /// 一张真有贴图覆写的卡上的来回：读 → 清除 → 指派 → 同 bytes 重用 id。
    /// 卡片不进版控，所以要卡：`OK_TEX_CARD=<卡片> cargo test --release --lib textures::tests -- --ignored --nocapture`
    /// （f-yvonne 量过的小卡：`D:\XKoikatuSunshine\UserData\chara\female\Re：从零开始的异世界生活 雷姆.png`，`me_tex=1`）
    #[test]
    #[ignore = "需要使用者的卡片"]
    fn round_trip_on_a_real_card() {
        let path = std::env::var("OK_TEX_CARD").expect("OK_TEX_CARD");
        let card = fs::read(&path).expect("读卡");
        let before = list(&card, 0).expect("读贴图列");
        println!("原本 {} 列", before.len());
        for row in &before { println!("  {row}"); }
        let with = before.iter().find(|r| r["tex_id"].as_i64().is_some()).expect("这张卡没有任何贴图覆写，换一张").clone();
        let id = |r: &J| json!({ "object": r["object"], "coordinate": r["coordinate"], "slot": r["slot"],
            "material": r["material"], "property": r["property"] });
        let outfit = with["coordinate"].as_u64().unwrap_or(0) as usize;

        // 清除：这一列只有 TexID，所以照 `NullCheck` 整列要消失，字典也要被 purge 掉。
        let mut cleared = id(&with); cleared["clear"] = json!(true);
        let out = apply(&card, outfit, &[cleared]).expect("清除");
        let after = list(&out, outfit).expect("读回");
        assert!(!after.iter().any(|r| id(r) == id(&with)), "清除后这一列还在：{after:?}");

        // 指派：档案的 bytes 原封不动进字典，列重新出现，大小就是档案大小。
        let png = std::env::temp_dir().join("ok_tex_round_trip.png");
        fs::write(&png, TINY_PNG).expect("写临时 PNG");
        let mut set = id(&with); set["png"] = json!(png.to_string_lossy());
        let out = apply(&out, outfit, &[set.clone()]).expect("指派");
        let after = list(&out, outfit).expect("读回");
        let row = after.iter().find(|r| id(r) == id(&with)).expect("指派后找不到这一列");
        assert_eq!(row["bytes"].as_u64(), Some(TINY_PNG.len() as u64), "{row}");
        assert_eq!(row["size"], json!([1, 1]), "{row}");
        let first = row["tex_id"].as_i64().expect("没有 TexID");

        // `SetAndGetTextureID`：另一个属性指派同一份 bytes，要重用同一个 id，不是再存一份。
        let mut second = id(&with); second["property"] = json!("AlphaMask"); second["png"] = json!(png.to_string_lossy());
        let out = apply(&out, outfit, &[second]).expect("第二个属性");
        let after = list(&out, outfit).expect("读回");
        let other = after.iter().find(|r| r["property"] == json!("AlphaMask")).expect("第二列不见了");
        assert_eq!(other["tex_id"].as_i64(), Some(first), "同样的 bytes 应该重用同一个 id：{after:?}");
    }
}
