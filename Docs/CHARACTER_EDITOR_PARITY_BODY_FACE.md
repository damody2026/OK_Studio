# 人物编辑器对齐原作：**身体与脸部**的盘点与缺口清单

这一份只盘 **顔（脸）** 与 **体（身体）** 两个分页（2026-11-19 的分工：衣服与配件在
`CHARACTER_EDITOR_PARITY_CLOTHES.md`、头发与眼睛细节与外挂栏位在 `CHARACTER_EDITOR_PARITY_HAIR_EYES.md`，
三份格式相同、可以直接合成总表）。整体骨架（7 个分页、48 个分类、266 个颜色项）在
[CHARACTER_EDITOR_PARITY_PLAN.md](CHARACTER_EDITOR_PARITY_PLAN.md)。

## 一、来源与怎么重新算一次

原作程式码在本机 `D:\XKoikatuSunshine\kks_decomp`（**注意是 `XKoikatuSunshine`**；AGENTS.md／README 写的游戏
路径只是范例，实际路径是本机设定）。**原作程式码不进版控**，这份文件只记结构、项目名与资料键。

```powershell
.\Tools\lua\lua.exe Tools\scan_kks_editor_shape.lua -Markdown
```

[`Tools/scan_kks_editor_shape.lua`](../Tools/scan_kks_editor_shape.lua) 把每个分类的滑杆对到它写的体型索引。
配对**不是**照栏位宣告顺序：每个 `Cvs*.cs` 另外建一个 `sliders = new Slider[N] { ... }` 阵列，**那个阵列**才和
`arrIndex` 一一对应。照宣告顺序配会错——`CvsBodyShapeAll` 宣告 47 个滑杆但阵列里只有 44 个，顺序也不同
（2026-11-19 第一版就是这样错的，发出去之前抓到）。脚本会把阵列没收进去的滑杆单独列出来，不会悄悄吞掉。

自洽检查：脚本产出的资料键去重之后正好是 **52 个 `shape.face.*` ＋ 44 个 `shape.body.*`**，和
`cf_customhead.txt`／`cf_custombody.txt` 第一栏的最大索引（51／43）一致，也和我们现有的滑杆数一致。

## 二、结论（先讲，细节在后面）

1. **体型滑杆 96 项，资料端与 UI 都已经有，是完整的**：原作脸部 52、身体 44，我们的
   `shape.face.0..51`／`shape.body.0..43` 一一对应，读卡器也有这 96 个滑杆。
2. **非体型的细项（光泽、细节强度、胸部柔软度、痣／彩绘／晒痕／指甲／化妆等）资料端几乎都已经有**，
   因为 `appearance/properties.rs` 是**对卡片解码后的区段做通用走访**：face／body／hair／clothes／accessory／makeup
   里每一个数值、布林、颜色都会被列出来（体型值另走 `shape.*`，被明确跳过）。所以这一块的缺口**主要在 UI**：
   没有照原作的分类分组、没有原作的范围与预设、标签是通用推出来的。**这句只对原作本体那一层成立**：走 KoiSkinOverlayX 的叠图（皮肤／妆容／刺青／晒痕的额外层）资料端完全没有，`relevant()` 把整段跳掉了，见第三之三节。
3. **真正要注意的一个差异：滑杆范围。** 原作这 96 个滑杆是 **0–1**（画面显示 0–100），我们给的是 **−1–2**
   （ABMX 扩张，`OKCharacterMCPRegistry.cpp` 第 60 行）。要「和原作一样」的话，UI 预设该夹在 0–1，
   另给一个「扩张」开关才放到 −1–2。这是设计决定，不是 bug，但两边不讲清楚会对不起来。

这一节的「我们有没有」是**读我们自己的程式码判的**（`properties.rs` 的走访范围、`appearance.rs` 的
`targets()`、`Parameters()` 的 96 个滑杆），**没有逐项在跑起来的读卡器上点过**；逐项实测留到实作那一轮。

## 三、非体型细项：原作栏位 ↔ 我们的资料端

下面是「顔／体」两页的分类里**不是体型值**的滑杆与开关，以及它们在卡片里的栏位。
`properties` 的通用走访会把这些栏位列出来，所以标「资料端已有」。

| 原作分类 | 原作项目 | 种类 | 卡片栏位 | 我们 |
|---|---|---|---|---|
| 顔全体 | `sldDetailPow` 细节强度 | 滑杆 | `face.detailPower` | 资料端已有／UI 缺 |
| 顔全体 | 脸型选图 | 选图 | `face.headId` | 已有（`appearance` 的 `head`） |
| 顔全体 | 细节选图 | 选图 | `face.detailId` | 已有（`face_detail`） |
| 頬 | `sldGlossPow` 脸颊光泽 | 滑杆 | `face.cheekGlossPower` | 资料端已有／UI 缺 |
| 口 | `sldGlossPow` 嘴唇光泽 | 滑杆 | `face.lipGlossPower` | 资料端已有／UI 缺 |
| 口 | 虎牙 | 开关 | `face.doubleTooth` | 资料端已有／UI 缺 |
| ほくろ（痣） | 位置 X／Y、大小 | 滑杆 3 | `face.moleLayout` | 资料端已有／UI 缺 |
| ほくろ | 痣选图、颜色 | 选图＋颜色 | `face.moleId`／`face.moleColor` | 已有（`mole`） |
| メイク（妆） | 眼影／腮红／唇／脸部彩绘 | 滑杆 8、开关 7 | `face.baseMakeup`（含各层）、`face.lipLineId`／`lipLineColor` | 资料端已有／UI 缺 |
| 目② | 瞳孔大小与位置 | 滑杆 4 | `face.pupilWidth`／`pupilHeight`／`pupilX`／`pupilY` | **已有**（`eye_page page=eyes` 的 properties） |
| 目② | 左右眼同设定 | 开关 | `face.isPupilSameSetting` | 资料端已有／UI 缺 |
| 目② | 高光位置 | 滑杆 4 | `face.hlUpX`／`hlUpY`／`hlDownX`／`hlDownY` | **已有** |
| 目② | 眼睛画在最前 | 开关 | `face.foregroundEyes` | 资料端已有／UI 缺 |
| 体全体 | `sldDetailPow`／`sldGlossPow` | 滑杆 2 | `body.detailPower`／`body.skinGlossPower` | 资料端已有／UI 缺 |
| 体全体 | 肤色主／次 | 颜色 | `body.skinMainColor`／`skinSubColor` | 资料端已有／UI 缺 |
| 体全体 | 附加线条 | 开关 | `body.drawAddLine` | 资料端已有／UI 缺 |
| 胸 | 柔软度、重量 | 滑杆 2 | `body.bustSoftness`／`body.bustWeight` | 资料端已有／UI 缺 |
| 胸 | 乳晕大小 | 滑杆 | `body.areolaSize` | 资料端已有／UI 缺 |
| 胸 | 乳头光泽 | 滑杆 | `body.nipGlossPower` | 资料端已有／UI 缺 |
| 胸 | 乳头选图、颜色 | 选图＋颜色 | `body.nipId`／`body.nipColor` | 已有（`nipple`） |
| 爪 | 指甲光泽 | 滑杆 | `body.nailGlossPower` | 资料端已有／UI 缺 |
| 爪 | 指甲颜色 | 颜色 | `body.nailColor` | 资料端已有／UI 缺 |
| 下毛 | 选图、颜色 | 选图＋颜色 | `body.underhairId`／`underhairColor` | 已有（`underhair`） |
| 日焼け（晒痕） | 选图、颜色 | 选图＋颜色 | `body.sunburnId`／`sunburnColor` | 已有（`sunburn`） |
| ボディペイント | 两层的位置／大小、选图、颜色 | 滑杆 8、开关 4 | `body.paintId`／`paintColor`／`paintLayout`／`paintLayoutId` | 资料端已有／UI 缺 |

**两边都缺的目前只有一项候选**：原作「体全体」的骨骼类型（`body.typeBone`，体型骨架切换）我们 `card.rs`
读得到，但没有当成可编辑项暴露，也没有 UI。要不要做，要先确认它在 OK 卡上改了会不会和已经烘焙进卡的资源冲突。

**「在不在资料端」是照这两条规则判的，不是看感觉**（读 `appearance/properties.rs` 的 `walk()` 与 `appearance.rs` 的 `targets()`）：

1. **`walk()` 只吐 `F32`／`F64`／`Boolean`，以及 `parentKey` 那个字串**；`shapeValueBody`／`shapeValueFace`／`version` 明确跳过，
   其余落到 `_=>{}`。所以**所有整数栏位（各种 `*Id`、`typeBone`）都不会出现在 properties 里**——
   不是没人接，是这条通道只走浮点与布林。键名就是卡片里 MessagePack 的成员名加区段前缀（`format!("{path}.{k}")`），
   所以上面表格里的 `face.detailPower`、`body.bustSoftness` 就是真的键，不是我照原作 C# 名字抄的。
2. **整数的选图要靠 `appearance.rs` 的 `targets()`**。身体／脸部相关的 target 有
   `head`／`face_detail`／`eyebrow`／`eyeline_up`／`eyeline_down`／`eye_white`／`eye_hi_up`／`eye_hi_down`／`nose`／
   `lipline`／`mole`／`eyeshadow`／`cheek`／`lip`／`body_detail`／`sunburn`／`nipple`／`underhair`，彩绘另有
   `facepaint{i}`（`baseMakeup.paintId.{i}`）与 `bodypaint{i}`（`paintId.{i}`）。**所以彩绘的选图是有的**，
   走的是 appearance 不是 properties。

两条合起来就得到那个唯一的缺口：**`body.typeBone` 是整数（`as_i32`），`walk()` 不吐它，`targets()` 也没有它**，
所以两条通道都看不到。颜色另外注意：`walk()` 把颜色摊成**四列各一个分量**（kind `color`、0–1、标签 紅／綠／藍／透明度），
原作那边是一个取色器——UI 要自己把四列合回一个控制项。

## 三之二、逐参数 metadata：原作的范围、步进与小数位

f-reader-yvonne 发现读卡器现在所有数值的范围都写死 ±1000000，要改成逐参数 metadata。身体＋脸部这一块的原作值
如下，**全部查过，没有例外**（`ChaCustom/Cvs*.cs` 顔／体两页的 23 个分类全扫过，`ConvertTextFromRate` 241 处、每一处的参数都是字面的 `(0, 100, …)`，`ConvertValueFromTextLimit`／`ConvertTextFromValue` **0 处**；`CvsUnderhair`／`CvsSunburn` 没有数值滑杆，只有选图＋颜色）：

| 种类 | 内部范围 | 步进 | 画面小数位 | 画面怎么显示 |
|---|---|---|---|---|
| 所有数值滑杆（含 96 项体型值） | `0.0`–`1.0` | `0.01` | 画面 **0** 位（API 值 2 位） | ×100 后取整，`0`–`100` |
| 颜色 | RGBA 各 `0.0`–`1.0` | 取色器 | － | 原作用取色器，没有数字栏 |
| 开关 | bool | － | － | 勾选框 |
| 选图 | 目录 id（int） | － | － | 缩图清单，不是范围 |

来源是 `ChaCustom/CustomBase.cs` 这两个函式，整个身体／脸部编辑器只用它们换算：

```csharp
public static string ConvertTextFromRate(int min, int max, float value)
{ return ((int)Mathf.Lerp(min, max, value)).ToString(); }           // 永远是 (0, 100, v) → 整数 0–100
public static float ConvertRateFromText(int min, int max, string buf)
{ ... return Mathf.InverseLerp(min, max, result); }                  // 打字进来，InverseLerp 夹回 0–1
```

要填进 metadata 的，身体／脸部每一项都一样：`min=0`、`max=1`、`step=0.01`、`digits=0`、`display_scale=100`。
所以**不需要逐项列范围**，逐项要列的是**预设值**，理由见下面三点。

1. **预设不是常数。** 原作每个滑杆旁的「戻す」读的是 `Singleton<CustomBase>.Instance.defChaInfo.custom.…`，
   也就是**当下性别／人物的预设角色的值**，不是 `0.5`。我们这边对应的是 `OKShapeDefaults::Value`，
   metadata 的 default 要从那里取，不能照抄一个数字。
2. **0–1 是 UI 的范围，不是资料的范围。** `ChaControl.SetShapeFaceValue`／`SetShapeBodyValue`
   **完全不夹值**，任何 float 都写得进卡；ABMX 扩张就是这样来的。所以 metadata 的 `min`／`max` 要当成
   **软范围**（滑杆走到哪、打字夹到哪），而**卡片里已经超出范围的值必须原样保留**，不能在读进来时夹掉——
   不然开一张 ABMX 卡再存回去就把人物改坏了。我们现在给的 −1–2 是这个软范围的扩张版，不是 bug。
3. **两项有额外的 runtime 行为，不是范围限制**：`shape.body.0`（身高）男性会被强制成 `0.6`／`1.0`；
   `shape.body.13`（乳头突起）实际套用时会和 `status.nipStandRate` 再 lerp 一次。写 metadata 时不要把这
   两件事当成 min／max。

**那个 ±1000000 是哪来的**：`Source/OpenKoikatsu/OKCharacterMCPRegistry.cpp` 的 `Parameters()` 最后一段，
把 `G->EditorProperties`（也就是 `properties.rs` 通用走访吐出来的那些列）照抄出去时写死：

```cpp
if(Kind!=TEXT("bool")&&Kind!=TEXT("parent")){
  Copy->SetNumberField(TEXT("min"),Kind==TEXT("color")?0:-1000000);
  Copy->SetNumberField(TEXT("max"),Kind==TEXT("color")?1:1000000);}
```

所以：**颜色那一种刚好是对的（0–1），其他每一个数值都是 ±1000000**，而身体／脸部的非体型细项**全部**走这一条。
逐参数 metadata 要放的就是这里：按 key 查一张表，查不到再退回现在的宽范围。另外 `Validate()` 也读同一组
`min`／`max`，所以范围一夹紧，**MCP 写入超范围的 ABMX 值就会被挡掉**——这就是上面第 2 点说的，范围要当软范围，
夹的是滑杆与打字，不是夹资料。

**照已批准的 metadata 形状填（`min`／`max`／`step`／`decimals`／`wrap`／`default`，列举类 `kind:"choice"` ＋ `options`，
`label` 放文字 id）**，身体＋脸部这一块是这样：

| 栏位 | 填什么 | 理由 |
|---|---|---|
| `min`／`max` | `0`／`1` | **一律用 API 自己读写的那个单位**（协调者 2026-11-19 裁定）。验证与写入走的是 API 的值，metadata 若讲另一个单位，迟早有人拿 0–100 的上限去挡 0–1 的值，而这种错不当场报错，只会悄悄拒绝或悄悄放行 |
| `step` | `0.01` | 原作滑杆一格一个百分点，换成 API 单位就是 0.01 |
| `decimals` | `2` | 跟着 API 单位；画面上的「整数 0–100」由下面两个显示栏位换算出来 |
| `display_scale` | `100` | 只给 UI 看：值 ×100 后显示 |
| `unit` | `"%"` | 只给 UI 看：照原作显示 0–100 的整数、一格一个百分点 |
| `wrap` | `false`（全部） | 身体／脸部没有角度类，没有一项该回绕；`wrap` 只给真的循环的量（饰品旋转 0–360 那种） |
| `default` | `OKShapeDefaults::Value(sex, body, index)`；非体型项取卡片预设 | 原作「戻す」读 `defChaInfo`，不是常数 |
| `kind` | 数值＝滑杆；开关＝`bool`；**选图＝`choice` ＋ `options`**（目录 id ＋ 缩图） | 选图不是范围 |
| `label` | 文字 id（例如 `editor.face.detail_power`），**不要字面字串** | 照 i18n 规矩，翻译在 `Localization/<lang>/*.toml` |

**一个真相给验证，一份换算给显示**：`min`／`max`／`step`／`decimals`／`default` 全都是 API 单位（0–1），
`display_scale`／`unit` 只负责把它变成原作画面上那个 0–100 的整数。不要留两种单位。

**`default` 不用我另外列数字，树里已经有、而且核过原作**：`Source/OpenKoikatsu/OKShapeDefaults.h` 里四张表
（`FemaleBody[44]`／`FemaleFace[52]`／`MaleBody[44]`／`MaleFace[52]`）就是原作 reset 的目标值——原作
`CustomControl.Entry` 从 `abdata/custom/presets_f_00.unity3d`／`presets_m_00.unity3d` 载入
`ill_Default_Female`／`ill_Default_Male`，`Tools/verify_shape_defaults.lua` 可以对着使用者自己的游戏重核一次。
值是 0–1（例如女性身高 `shape.body.0` 是 `0.30`，画面上显示 30）。

**那四张表依性别不同，所以产生端必须按当前角色的性别选表**，不能固定吐女性那张：重置按钮按下去跑到另一个
性别的预设，是很难查的 bug（画面上只会看到「重置之后身材不对」，不会有任何错误讯息）。

超范围的旧值按上面第 2 点处理：**读进来原样保留、照实显示**（滑杆顶到底、数字栏显示真值），只有使用者动了那一项才夹。

两件落地之后的补充（2026-11-19）：

- **顺序是先取整、后 wrap**。身体／脸部**每一项 `wrap` 都是 `false`**，所以这条对我这一块没有影响；记在这里是为了提醒后来的人**不要给这些项目加 wrap**——它们不是角度，0 和 100 不该接起来。
- **没填范围的列现在会标 `range_missing`**，不再把回退上限当成真范围吐出去。所以上面那张表就是「填进去就能把这个旗标清掉」的值，照填即可，不要另写一套。


## 三之三、**真正的资料端缺口：KoiSkinOverlayX（KSOX）整段被跳过**

第二节原本写「非体型细项资料端几乎都有」，这句**要修正**：原作本体的栏位（`face.baseMakeup`、
`body.sunburnId`、`body.paintId` 等）确实都在，但**外挂叠图那一层完全没有**。

`appearance/properties/plugins.rs` 的 `relevant()` 用子字串筛 KKEx 的区段：

```rust
["materialeditor","hairaccessorycustomizer","hairshadowcolor","pushup",
 "dynamicboneeditor","moreaccessories","accessorystates","overlay"]
```

**KoiSkinOverlayX 在卡片里的键是 `KSOX`**（不是带 `overlay` 的长名），上面没有一个子串命中 `ksox`，
所以整段被跳过。实地确认过：`heroine_alice.png` 的 KKEx 里有 `KSOX` 这个键，底下是
`_TextureID_5832` 之类的项目，各自带着 PNG。被跳掉的内容属于我的范围：

| 被跳过的东西 | 影响到的原作分类 |
|---|---|
| 皮肤叠图（身体／脸部的 overlay 贴图） | 体全体、顔全体 |
| 妆容叠图（眼影／腮红／唇的额外层） | メイク |
| 刺青、晒痕的额外层 | 日焼け、ボディペイント |
| 内衣／服装叠图 | 不是我的范围（f-reader-yvonne） |

所以上一节表格里「メイク／日焼け／ボディペイント：资料端已有」只对**本体那一层**成立；
**走 KSOX 的叠图是「资料端缺」**。`relevant()` 是共用判定逻辑，要改先发一则给协调者（已照规则办），
这里只记缺口，不动程式码。

## 四、体型滑杆逐项（96 项，脚本产出）

原作在「顔型全体」「体型全体」两页把同样的值再列一次（全部 52／44 项），所以下面只列**按部位分的那几页**；
那两张全表就是这 96 项的联集。所有项目：种类＝滑杆，原作范围 **0–1**（显示 0–100），我们的范围 **−1–2**，
预设值依性别与项目（`OKShapeDefaults::Value`），卡片里存在 `face.shapeValueFace`／`body.shapeValueBody`。

**顔／顔全体**（6 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldFaceBaseW` | `shape.face.0` |
| 2 | `sldFaceUpZ` | `shape.face.1` |
| 3 | `sldFaceUpY` | `shape.face.2` |
| 4 | `sldFaceUpSize` | `shape.face.3` |
| 5 | `sldFaceLowZ` | `shape.face.4` |
| 6 | `sldFaceLowW` | `shape.face.5` |

**顔／耳**（5 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldEarSize` | `shape.face.47` |
| 2 | `sldEarRotY` | `shape.face.48` |
| 3 | `sldEarRotZ` | `shape.face.49` |
| 4 | `sldEarUpForm` | `shape.face.50` |
| 5 | `sldEarLowForm` | `shape.face.51` |

**顔／あご**（8 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldChinLowY` | `shape.face.6` |
| 2 | `sldChinLowZ` | `shape.face.7` |
| 3 | `sldChinY` | `shape.face.8` |
| 4 | `sldChinW` | `shape.face.9` |
| 5 | `sldChinZ` | `shape.face.10` |
| 6 | `sldChinTipY` | `shape.face.11` |
| 7 | `sldChinTipZ` | `shape.face.12` |
| 8 | `sldChinTipW` | `shape.face.13` |

**顔／頬**（5 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldCheekBoneW` | `shape.face.14` |
| 2 | `sldCheekBoneZ` | `shape.face.15` |
| 3 | `sldCheekW` | `shape.face.16` |
| 4 | `sldCheekZ` | `shape.face.17` |
| 5 | `sldCheekY` | `shape.face.18` |

**顔／眉**（5 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldEyebrowY` | `shape.face.19` |
| 2 | `sldEyebrowX` | `shape.face.20` |
| 3 | `sldEyebrowRotZ` | `shape.face.21` |
| 4 | `sldEyebrowInForm` | `shape.face.22` |
| 5 | `sldEyebrowOutForm` | `shape.face.23` |

**顔／目①**（14 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldEyelidsUpForm1` | `shape.face.24` |
| 2 | `sldEyelidsUpForm2` | `shape.face.25` |
| 3 | `sldEyelidsUpForm3` | `shape.face.26` |
| 4 | `sldEyelidsLowForm1` | `shape.face.27` |
| 5 | `sldEyelidsLowForm2` | `shape.face.28` |
| 6 | `sldEyelidsLowForm3` | `shape.face.29` |
| 7 | `sldEyeY` | `shape.face.30` |
| 8 | `sldEyeX` | `shape.face.31` |
| 9 | `sldEyeZ` | `shape.face.32` |
| 10 | `sldEyeTilt` | `shape.face.33` |
| 11 | `sldEyeH` | `shape.face.34` |
| 12 | `sldEyeW` | `shape.face.35` |
| 13 | `sldEyeInX` | `shape.face.36` |
| 14 | `sldEyeOutY` | `shape.face.37` |

**顔／鼻**（3 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldNoseTipH` | `shape.face.38` |
| 2 | `sldNoseY` | `shape.face.39` |
| 3 | `sldNoseBridgeH` | `shape.face.40` |

**顔／口**（6 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldMouthY` | `shape.face.41` |
| 2 | `sldMouthW` | `shape.face.42` |
| 3 | `sldMouthZ` | `shape.face.43` |
| 4 | `sldMouthUpForm` | `shape.face.44` |
| 5 | `sldMouthLowForm` | `shape.face.45` |
| 6 | `sldMouthCornerForm` | `shape.face.46` |

**体／体全体**（2 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldHeight` | `shape.body.0` |
| 2 | `sldHeadSize` | `shape.body.1` |

**体／胸**（10 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldBustSize` | `shape.body.4` |
| 2 | `sldBustY` | `shape.body.5` |
| 3 | `sldBustRotX` | `shape.body.6` |
| 4 | `sldBustX` | `shape.body.7` |
| 5 | `sldBustRotY` | `shape.body.8` |
| 6 | `sldBustSharp` | `shape.body.9` |
| 7 | `sldBustForm` | `shape.body.10` |
| 8 | `sldAreolaBulge` | `shape.body.11` |
| 9 | `sldNipWeight` | `shape.body.12` |
| 10 | `sldNipStand` | `shape.body.13` |

**体／上半身**（8 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldNeckW` | `shape.body.2` |
| 2 | `sldNeckZ` | `shape.body.3` |
| 3 | `sldBodyShoulderW` | `shape.body.14` |
| 4 | `sldBodyShoulderZ` | `shape.body.15` |
| 5 | `sldBodyUpW` | `shape.body.16` |
| 6 | `sldBodyUpZ` | `shape.body.17` |
| 7 | `sldBodyLowW` | `shape.body.18` |
| 8 | `sldBodyLowZ` | `shape.body.19` |

**体／下半身**（8 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldWaistY` | `shape.body.20` |
| 2 | `sldBelly` | `shape.body.21` |
| 3 | `sldWaistUpW` | `shape.body.22` |
| 4 | `sldWaistUpZ` | `shape.body.23` |
| 5 | `sldWaistLowW` | `shape.body.24` |
| 6 | `sldWaistLowZ` | `shape.body.25` |
| 7 | `sldHip` | `shape.body.26` |
| 8 | `sldHipRotX` | `shape.body.27` |

**体／腕**（7 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldShoulderW` | `shape.body.37` |
| 2 | `sldShoulderZ` | `shape.body.38` |
| 3 | `sldArmUpW` | `shape.body.39` |
| 4 | `sldArmUpZ` | `shape.body.40` |
| 5 | `sldElbowW` | `shape.body.41` |
| 6 | `sldElbowZ` | `shape.body.42` |
| 7 | `sldArmLow` | `shape.body.43` |

**体／脚**（9 項）

| # | 原作滑桿 | 資料鍵 |
|---:|---|---|
| 1 | `sldThighUpW` | `shape.body.28` |
| 2 | `sldThighUpZ` | `shape.body.29` |
| 3 | `sldThighLowW` | `shape.body.30` |
| 4 | `sldThighLowZ` | `shape.body.31` |
| 5 | `sldKneeLowW` | `shape.body.32` |
| 6 | `sldKneeLowZ` | `shape.body.33` |
| 7 | `sldCalf` | `shape.body.34` |
| 8 | `sldAnkleW` | `shape.body.35` |
| 9 | `sldAnkleZ` | `shape.body.36` |

## 五、分批顺序

1. **目②剩下的开关**（`isPupilSameSetting`／`foregroundEyes`）与 **ほくろ**的三个滑杆：最小，而且眼睛三页
   已经做完，接着补最省。
2. **胸**：柔软度／重量／乳晕大小／乳头光泽四项——使用者最容易注意到的身体细项。
3. **光泽与细节强度**六项（脸全体、脸颊、嘴唇、体全体、指甲、乳头）：同一种控制项，一次做完。
4. **ボディペイント**与 **メイク**：两层彩绘与化妆的位置／大小／颜色，项目多但都已在 properties 里。
5. **肤色与附加线条**：颜色类，跟第 3 项一起做也可以。
6. **滑杆范围的设计决定**（0–1 夹住、另给扩张开关）要先敲定，否则上面每一项的 UI 都要改两次。
7. `body.typeBone`：先确认影响再决定做不做。
8. **逐参数 metadata**（`min=0`／`max=1`／`step=0.01`／`digits=0`／`display_scale=100`，预设取`OKShapeDefaults::Value`）：f-reader-yvonne 要的那件事，身体／脸部的值见第三之二节，照抄即可。
9. **KSOX 叠图**：资料端真的缺，但改的是共用的 `relevant()`，要先经协调者同意再动。

每一项的 UI 侧由 e-fork-2 接，资料端若发现缺口由我补；目前盘下来资料端缺的是第 7 项与第 9 项（KSOX 叠图）。

## 六、对得上稽核表的四栏

稽核表现在四栏，我这一块（身体＋脸部）对应如下：

| 稽核栏 | 谁的 | 我这一块落在哪 |
|---|---|---|
| UI 缺 | e-fork-2 | 第三节表格里标「资料端已有／UI 缺」的那些：光泽与细节强度 6 项、胸部 4 项、痣 3 项、妆容、体彩绘、肤色与附加线条、目②的三个开关 |
| 资料端缺 | 我 | 两项：`body.typeBone`（读得到但没当可编辑项暴露），以及 **KSOX 叠图**（`relevant()` 跳过整段，见第三之三节） |
| 还没填范围（`range_missing`） | f-yvonne | 身体＋脸部**全部**数值项，值见第三之二节那张表；96 项体型值与所有非体型数值都是同一组 |
| 不认得的 KKEx 区段 | f-sceneload | `KSOX` 会出现在这一栏。它同时也是我的「资料端缺」——同一件事从两边看，不要当成两个缺口各做一次 |

