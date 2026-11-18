# 读卡器 UI：外观选择的查询与套用 API（2026-11-18）

新版 UI 要补回「眉毛、眼睛、发型、饰品」的选材质／模型控制项。**清单与 ID 一律从下面这些查询拿，
不要在 UI 层自己造清单、也不要猜 ID**：原作与 mod 的项目在同一个槽位可能撞 ID，只有目录能分辨。

资料面全部已经存在（`Tools/ok-extract/src/appearance.rs` + `Source/OpenKoikatsu/OKGalleryAppearance.cpp`），
这一轮只补了一个缺的查询：**目前选的是哪一个**（下方第 3 节 `current`）。

## 0. 前提：要有有效的游戏目录

外观目录是从**游戏的 `abdata` 与 `mods/`** 建出来的（`appearance::catalog`；首次建要几分钟，之后走
`Saved/AppearanceEditor/cache` 里的 `catalog-v1-<签章>.json`）。目录无效时 `RefreshAppearanceCatalog`
直接显示「請先設定遊戲目錄，才能讀取新增外觀的原始素材。」，不是 bug。

游戏目录来自 `UKKGameRoot`（使用者设定优先，`Config/DefaultGame.ini` 的 `Root` 当预设）。
**现况（2026-11-18）**：`Root=D:/KoikatuSunshine` 这个路径已经不存在，实际安装在 `D:/XKoikatuSunshine`，
所以现在一进外观面板就是「請先設定遊戲目錄」。设定页要能改这个值（可先用 `ok_zipmod_count` 验证，
见 [缺件回报](OK_CARD_MISSING_PARTS_REPORTING.md)）。

## 1. 四类控制项各自是哪些 target

`targets` 是一张固定表（`appearance::targets()`），每一项长这样：

```json
{"key":"eyebrow","label":"眉毛種類","category":406,"section":"face","path":"eyebrowId",
 "property":"ChaFileFace.eyebrowId","block":"Custom"}
```

- `key`：套用时要传的 target 识别码
- `category`：项目的 `entry.category_no`，用来筛 `items`
- `section` + `path`：这个选择写进卡片的哪个栏位
- `property`：sideloader 的 Property 名（mod 来源的解析列用它对应）

| UI 控制项 | target key | category | 这台机器上的项目数（kks_Saria，`D:/XKoikatuSunshine`） |
|---|---|---:|---:|
| 眉毛 | `eyebrow` | 406 | 257 |
| 上眼线／下眼线 | `eyeline_up`／`eyeline_down` | 412／413 | 741／165 |
| 眼白 | `eye_white` | 407 | 15 |
| 左右瞳孔 | `pupil0`／`pupil1` | 408 | 836 |
| 左右瞳孔渐层 | `gradation0`／`gradation1` | 409 | 52 |
| 上／下眼睛高光 | `eye_hi_up`／`eye_hi_down` | 410／411 | 565／423 |
| 后髮／前髮／侧髮／附加头髮 | `hair0`…`hair3` | 101／102／103／104 | 306／174／22／18 |
| 头髮光泽 | `hair_gloss` | 433 | 104 |
| 饰品欄 1–20 | `accessory{0..19}_{cat}` | 121–130 | 髮飾 1819、头飾 7885、脸部 2225、颈部 645、身体 993、腰 1157、腿 485、手臂 806、手 974、私密 293 |
| 额外饰品欄（MoreAccessories） | `accessory{20+}_{cat}` | 同上 | 随卡片而定，要带 `card` 才会出现 |

饰品每一欄对十个类别各有一个 target（20 欄 × 10 类 = 200 项）；**一欄同时只穿一个类别**，
要知道「这欄现在是什么」看第 3 节的 `current`。

## 2. 查清单

### UI 内部（C++，新版 UI 应该走这条）

```cpp
UOKCharacterController::RefreshAppearanceCatalog();   // 非同步，完成后填好下面两个
TArray<TSharedPtr<FJsonObject>> AppearanceTargets;    // 第 1 节那张表
TArray<TSharedPtr<FJsonObject>> AppearanceItems;      // 全部项目，用 entry.category_no 筛
```

项目（`Item`）：

```json
{"key":"<内容杂凑，套用时传这个>","guid":"<zipmod GUID，原作项目为空>",
 "source":"<zipmod 绝对路径，原作项目为空>",
 "entry":{"category_no":406,"id":9,"name":"…","main_ab":"…","main_data":"…","main_tex":"…",
          "parent":"","extra":{"ThumbAB":"…","ThumbTex":"…","__zip":"…"}}}
```

`source` 为空＝原作素材，非空＝模组。**不要用 `entry.id` 当唯一键**（不同 mod 会撞），要用 `key`。

### 外部／离线（MCP 或 CLI，验证用）

```
ok-game-mcp call reader_call '{"action":"catalog","target":"eyebrow","query":"","offset":0,"limit":64}'
Tools/ok-extract/target/release/ok-appearance.exe <游戏目录> <request.json> <report.json>
  request.json: {"action":"catalog","card":"<卡>","outfit":0,"cache":"Saved/AppearanceEditor/cache"}
```

`reader_call catalog` 支援 `target`（只回该类别）、`query`（名称／key 子字串）、`offset`／`limit` 分页，
回传带 `total` 与 `next_offset`。CLI 会把整份报告同时印到 stdout（Saria 这张 45 MB），记得导向档案。

## 3. 目前选的是哪一个：`current`（2026-11-18 新增）

`catalog` 带 `card` 时多回一个 `current`，key 是 target key：

```json
"current":{
 "eyebrow":        {"stored_id":9,"ids":[9],"guid":"","item":"<item key>","name":"…"},
 "hair0":          {"stored_id":500,"ids":[500,100083550],"guid":"yamadamod.nohairB","item":"<item key>","name":"…"},
 "accessory11_122":{"stored_id":19118911,"ids":[19118911,100070010],"guid":"Saria_Acc_Mod","item":null,"name":"[Arknights]Saria_Mod"}
}
```

- `item` 有值 → UI 直接把那个项目标成「目前选取」。
- `item` 是 `null` → 卡片指名的 mod **这台机器没装**；`guid`／`name` 照样告诉使用者它原本是什么，
  UI 要显示「来源缺失」，不要装作没选（跟缺件回报同一条原则）。
- `ids` 是卡片栏位值与解析列的 LocalSlot，照 `ChaListCatalog::get_slot` 的顺序比对。
- 饰品只会出现**实际穿着那一类**的 target（看 `accessory.parts.N.type`），所以每个用到的欄位只有一行。
  额外饰品欄（MoreAccessories）的 id 在 KKEx XML 里，目前不在 `current` 内。

量测（kks_Saria，`D:/XKoikatuSunshine`）：600 个 target、38730 个项目，`current` 115 行、109 行对得上
目录项目；对不上的 6 行都是这台机器没装的 mod（`Saria_Acc_Mod` 等）。

## 4. 缩图

```
RunAppearanceRequest({"action":"thumbnails","keys":[item key…]})   // 一次最多 48 个
→ {"thumbnails":[{"key":"…","path":"<本机 PNG 路径>"}]}
```

没有缩图的素材不会出现在回传里，UI 显示「素材未提供縮圖」。

## 5. 套用

```cpp
UOKCharacterController::ApplyAppearanceItem(ItemKey);   // 空字串＝清空这个槽位
UOKCharacterController::OnAddAccessorySlot();           // 新增一个额外饰品欄（MoreAccessories）
```

外部：

```
reader_call '{"action":"appearance","target":"hair0","item":"<item key>"}'
reader_call '{"action":"add_accessory"}'
```

套用会**另存一张新的工作卡片**（原始卡片不会被覆写），非同步；期间 `bAppearanceBusy` 为真，
MCP 会等到画面稳定才回。套用前若有未套用的属性编辑会被拒绝（先 `apply` 或 `reset`）。

## 6. 颜色与材质参数（不是「换模型」那一类）

换模型／换贴图走上面的目录；**颜色、光泽、花纹、材质覆写**是另一组：

```
reader_call '{"action":"parameters"}'                         // 全部可调参数（分页）
reader_call '{"action":"get","keys":["hair.parts.0.baseColor.r"]}'
reader_call '{"action":"set","values":[{"key":"…","value":0.5}]}'   // 进 PendingProperties
reader_call '{"action":"apply"}'                              // 真正写回并重开
reader_call '{"action":"reset","keys":["…"]}'
```

C++ 侧同一组是 `EditorProperties`（现值）／`PendingProperties`（待套用）／`OnApplyProperties()`。
这些 key 是卡片栏位的扁平路径（`face.eyebrowId`、`hair.parts.0.baseColor.r`…）。
**`*.id` 这类栏位不要用 `set` 去改**：直接写 id 不会同时更新 sideloader 的解析列，mod 素材会变成别的东西；
换素材一律走 `appearance`。

## 7. 「PBR 或原作髮材质」这个选项

README 里那句指的是**匯入流程**（Tripo 头髮，`Tools/ok-extract/src/bin/ok-hair-pack.rs`，
见 [Tripo 头髮 APNG](TRIPO_HAIR_APNG.md)），不是读卡器上的一个开关——现行程式里没有这个控制项，
旧版 UI 也没有。头髮在 UI 上可调的是：髮型模型（`hair0`…`hair3`）、头髮光泽种类（`hair_gloss`），
以及颜色／光泽那一组参数（第 6 节）。要做成开关得另外设计，不属于「补回不见的控制项」。
