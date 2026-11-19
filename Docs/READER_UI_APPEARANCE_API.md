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

## 8. 外观这一侧的背景工作：为什么不会回写到已释放的资料（2026-11-18 查）

使用者遇到 `EXCEPTION_ACCESS_VIOLATION` 崩在 `Foreground Worker #0`，所以把外观目录这条背景路径查了一遍。
结论：**这一侧没有悬空回写，不需要另外加取消旗标或强参考**，理由逐条写在这里，省得下次再查一遍。

| 路径 | 背景做什么 | 为什么安全 |
|---|---|---|
| `RunAppearanceRequest`（catalog／thumbnails／apply 都走它） | `Async(EAsyncExecution::ThreadPool)` 里呼叫 `FOkSession::AppearanceRequest`，读写 `Saved/AppearanceEditor` 的请求／报告档 | worker 的 lambda **只捕获值**（`Root`、`Input`／`Output` 路径、`RequestOutfit`、`RequestClothes` 复本、`CardJob` 的 thread-safe shared ptr），从头到尾不解参照任何 UObject；控制器只以 `TWeakObjectPtr` 捕获，而且只在游戏执行绪的完成 lambda 里 `Weak.Get()` |
| 完成回写 | `AsyncTask(ENamedThreads::GameThread,…)` | 除了 `Weak.Get()`，还比对 `SelectedIndex`／`LoadGeneration`／`OutfitIndex` 才会 rebase `AppearanceContext`；catalog 的回呼另外比对这三个，thumbnails 比对 `AppearancePageGeneration`，apply 比对 Selection／Generation／Outfit |
| 缩图解码 | **不在 worker**：`Thumbnail(Path)`（PNG → `UTexture2D::CreateTransient`）在游戏执行绪的完成 lambda 里跑，且先挡掉 >2048×2048 | 产生的贴图存进 `UPROPERTY() TArray<TObjectPtr<UTexture2D>> AppearanceTextures`，按钮存进 `UPROPERTY() TArray<TObjectPtr<UOKAppearanceButton>>`，GC 期间都有强参考 |
| 两个请求同时在途 | `bAppearanceBusy`（catalog／apply）与 `bAppearanceThumbBusy`（thumbnails）是两个旗标，所以切卡时**可能**有两个请求同时进 Rust | FFI `ok_appearance_request`（`ffi.rs`）本身有 `static LOCK:Mutex<()>` 把每个请求序列化，外面再包 `catch_unwind`，所以两边不会在 Rust 里互踩，panic 也不会穿过 FFI |
| 切游戏目录 | 每次请求把 `AppearanceRoot` **复制**进 lambda | 在途的请求用的是发出当下的目录；Rust 的目录快取用 canonical root 当 key，换目录自然重建，不会把旧目录的结果当新的 |

也就是说，外观目录这条路上没有「worker 直接写回 UI 资料」的地方；真的要改的是别的地方（见下一段给 e-fork-2 的三点）。

## 9. 眼部三页要用的读写接口（2026-11-19）

e-fork-2 要做「眼部缩放2 / 眼睛 / 瞳孔覆盖贴图」三页。前两页的接口都已经存在，第三页**还没有接口**，
要什么说一声我补。三页共用同一组读写：

```
reader_call '{"action":"parameters","query":"<子字串>","offset":0,"limit":128}'   // 列出可调参数（分页）
reader_call '{"action":"get","keys":[...]}'                                      // 现值
reader_call '{"action":"set","values":[{"key":"…","value":1.2}]}'                 // 进 PendingProperties
reader_call '{"action":"apply"}'                                                  // 真正写回并重开
reader_call '{"action":"reset","keys":[...]}'                                     // 回到 default
```

每一笔 parameter 都带 `key`／`label`／`value`／`min`／`max`／`default`／`category`／`supported`，
骨骼那些另带 `bone`／`axis`／`unit`／`coordinate_specific`，不支援时还有 `unsupported_reason`。
**UI 不要自己假设范围**，照回传的 `min`／`max`／`default` 画。

### 9.1 眼部缩放2（ABMX 骨骼）

key 形如 `bone.<骨骼名>.<轴>`，`category` 是 `FaceEyes2`（标签「眼球」）。使用者说的「眼部缩放2」
就是 `cf_J_Eye_tx_L`／`cf_J_Eye_tx_R` 这组（`OKBoneControls.h`，分类 `FaceEyes2` 共 30 笔）：

| 这一页该放的 | 骨骼 | 轴（`axis`） | 范围 | 单位 |
|---|---|---|---|---|
| 眼球 縮放 2（整体） | `cf_J_Eye_tx_L` / `cf_J_Eye_tx_R` | −1 | 0–3 | multiplier |
| 眼球 縮放 2 X／Y／Z | 同上 | 0／1／2 | 0–3 | multiplier |
| 眼球 位移 X／Y／Z | 同上 | 4／5／6 | −1–1 | source_units |
| 眼球 旋轉 X／Y／Z | 同上 | 7／8／9 | −180–180 | degrees |

同一分类里另有「眼球 縮放 1」(`cf_J_Eye_rz_L/R`) 与「雙眼球」(`cf_J_Eye_tz`，没有左右之分) 两组，
轴与范围一样。左右各是一个 key（`Def.Bone` 与 `Def.Right`），UI 要同步时自己写两笔 `set`。
`supported=false` 表示这张卡的骨架没有这根骨头，要画成不可用而不是省略。

### 9.2 眼睛

两部分，都已经有接口：

1. **形状滑杆**（原作 52 项脸部的其中 14 项）：`shape.face.24` … `shape.face.37`，
   依序是上眼瞼形狀 1/2/3、下眼瞼形狀 1/2/3、眼睛上下、眼睛水平位置、眼睛前後、眼睛角度、
   眼睛寬度、眼睛长度、眼頭左右位置、眼尾上下位置（`Plugins/KKCard/.../KKShapeRows.cpp`）。
   范围一律 `min=-1`／`max=2`，`default` 由 `OKShapeDefaults::Value(sex, body=false, index)` 给。
2. **种类选择**（第 1–3 节的外观目录）：`pupil0`／`pupil1`（408）、`gradation0`／`gradation1`（409）、
   `eye_white`（407）、`eye_hi_up`／`eye_hi_down`（410／411）、`eyeline_up`／`eyeline_down`（412／413）、
   `eyeshadow`（401）。清单用 `catalog`，目前选的看 `current`，套用用 `appearance`。

眼睛颜色、瞳孔大小位置那些是 properties：`face.pupil.0.baseColor.r`、`face.pupil.0.pupilWidth`、
`face.pupil.0.pupilHeight`、`face.pupil.0.pupilX/Y`、`face.hlUpColor.*`、`face.whiteBaseColor.*` 等，
用 `parameters` 的 `query` 过滤 `pupil`／`hl`／`white` 就列得出来。

### 9.3 瞳孔覆盖贴图：**目前没有读写接口**

卡片里这些覆盖贴图是 Material Editor 的 `MaterialTexturePropertyList`（KKEx 区块），按材质＋属性定位
（`appearance.rs` `clear_material_conflicts`）：

| 这一页的项目 | 材质名含 | 属性（`Property`，去掉开头底线、不分大小写） |
|---|---|---|
| 瞳孔本体贴图 | `hitomi`／`pupil` | `maintex` |
| 瞳孔渐层遮罩 | `hitomi`／`pupil` | `gradmask`／`gradationmask` |
| 上高光覆盖 | `hitomi`／`pupil` | `overtex`／`overtex1`／`eyehighlight`／`eyehiuptex` |
| 下高光覆盖 | `hitomi`／`pupil` | `overtex2`／`eyehighlight2`／`eyehidowntex` |
| 眼白贴图 | `sirome`／`white` | `maintex` |

**缺口**：`properties` 这条路会**跳过**所有名字含 `texture` 的栏位
（`appearance/properties/plugins.rs`：`if name.to_ascii_lowercase().contains("texture") { continue }`），
所以这些列根本不会出现在 `parameters`／`get` 里，UI 现在**既读不到也写不了**。

要做这一页需要我在 Rust 侧补两个动作，说一声我就做：

- 列出：`{"action":"eye_overlays"}` → 每一列 `{material, property, slot:"maintex|gradmask|overtex1|overtex2", present:true/false, bytes, png:"<导出的本机路径>"}`，
  让 UI 显示现在有没有覆盖、长什么样。
- 设定／清除：`{"action":"eye_overlay_set","slot":"overtex1","path":"<PNG>"}`／`{"slot":"overtex1","path":""}`，
  比照 `appearance` 另存一张工作卡片（原卡不覆写），写完重开。

已知的交互规则（做 UI 时要知道）：**用 `appearance` 换瞳孔／渐层／高光的种类，会自动清掉会冲突的那几列覆盖贴图**
（`clear_material_conflicts`：换 410 清 `overtex/overtex1/eyehighlight/eyehiuptex`，换 411 清 `overtex2/…`，
换 408/409 清 `maintex/gradmask`）。所以 UI 的「覆盖贴图」页在使用者换了种类之后要重新读一次。

### 9.4 照这个接：每一页的读与写（函式名、参数、回传）

UI 在读卡器行程内，所以**走 C++ 直接呼叫**（下表左栏）；右栏是同一件事的 MCP 版本，给测试与自动化用。
`UOKCharacterController` 的成员都在 `Source/OpenKoikatsu/OKCharacterController.h`。

#### 读

| 要的东西 | C++ | MCP |
|---|---|---|
| 这张卡的脸部形状值（52 项，含眼睛 24–37） | `Selected.Face.ShapeValueFace`（`TArray<float>`，`-1..2`）；预设 `OKShapeDefaults::Value(Selected.Sex,false,Index)`；标签 `KKShapeRows()`（`Plugins/KKCard/.../KKShapeRows.h`，`{Label,Index,bBody,bLast}`） | `{"action":"parameters","query":"shape.face."}` → 每项 `{key,label,value,min:-1,max:2,default,category:"face"}` |
| ABMX 骨骼现值（眼部缩放 1／2、双眼球） | `EditorModsJson()` → JSON 的 `abm` 阵列，每笔 `{name,location,coord:[{scale:[x,y,z],length,pos:[x,y,z],rot:[x,y,z]}]}`；候选清单与范围是 `OKBoneControls`（`Source/OpenKoikatsu/OKBoneControls.h`，`{Category,Label,Bone,Right,Axis,Min,Max}`） | `{"action":"parameters","query":"bone.cf_J_Eye"}` → `{key,label,value,min,max,default,category:"FaceEyes2",bone,axis,unit,supported,coordinate_specific}` |
| 种类候选（瞳孔／渐层／眼白／高光／眼线／眼影） | `RefreshAppearanceCatalog()` 之后读 `AppearanceTargets`（挑 `category` 等于 408/409/407/410/411/412/413/401 的 target）与 `AppearanceItems`（用 `entry.category_no` 筛） | `{"action":"catalog","target":"pupil0","query":"","offset":0,"limit":64}` |
| 目前选的是哪一个 | 同上的 `catalog` 回传里的 `current[<target key>]`（第 3 节） | 同左 |
| 缩图 | `RunAppearanceRequest({"action":"thumbnails","keys":[...]} , cb)`，一次 ≤48 个；回呼里 `Thumbnail(Path)` 做成 `UTexture2D`（游戏执行绪，>2048² 会被挡掉） | `{"action":"thumbnails","keys":[...]}` → `[{key,path}]` |
| 瞳孔覆盖贴图现况 | **没有**（`properties` 跳过名字含 `texture` 的栏位），见 9.3 | 同左 |

#### 写

| 要做的事 | C++ | MCP |
|---|---|---|
| 改一个脸部形状值 | `OnShapeChanged(false, Index, Value)`（即时套到模型；`ResetShape(false,Index)` 回预设） | `set` → `apply` |
| 改一个 ABMX 骨骼值 | `OnBoneChanged(Slider, Value)`，Slider 带 `ModBone`／`ModRight`／`ModAxis`／`ModSide`（0=左 1=双 2=右）／`ModCoordinateSpecific`；内部写进 KKEx 的 `abm` 再 `CommitEditorMods` | `set` → `apply`（左右各一个 key） |
| 换种类（瞳孔／渐层／眼白／高光／眼线／眼影） | `AppearanceTargetKey = <target key>;` 然后 `ApplyAppearanceItem(<item key>)`；空字串＝清空这个槽位 | `{"action":"appearance","target":"pupil0","item":"<item key>"}` |
| 改颜色等 properties | `SetEditorProperty(Key, Value)` 进 `PendingProperties`，再 `OnApplyProperties()` | `set` → `apply` |
| 设定／清除瞳孔覆盖贴图 | **要我补**（9.3 列的两个动作） | 同左 |

#### 缩图网格的候选是哪里来的

`AppearanceItems` 的每一项就是一格。判断来源只看两个栏位：

- `source` 空 → **原作素材**（来自游戏 `abdata/list/characustom`），格子上标「原始遊戲」。
- `source` 非空 → **模组**，值是那个 zipmod 的绝对路径，`guid` 是它的 sideloader GUID；格子上标「模組」，
  tooltip 用 `entry.name` ＋ `source`。
- 缩图从 `entry.extra` 的 `ThumbAB`／`ThumbTex` 抽出来（`thumb()`）；这两个是 `0` 或空的素材**不会**有缩图，
  `thumbnails` 的回传里就没有它，UI 显示「素材未提供縮圖」。
- **共享资源（基础库）不在这个清单里**：目录只从游戏的 `abdata` 与 `mods/` 建（第 0 节），
  所以没有设定游戏目录时这三页的种类格子本来就是空的，要先把使用者导去设定页。
- 排序与筛选照旧在 UI 侧做：`AppearanceItems` 已按 `(category_no, source, id)` 排好，
  搜寻字串比对的是「原始遊戲／模組 類型 ＋ `entry.name` ＋ `entry.id` ＋ `source`」（旧版 `RebuildAppearancePage` 的作法）。

#### 选取之后走哪一条路径

```
ApplyAppearanceItem(key)
  → ApplyPreparedAppearance(key)            // 眼睛这几类（eyebrow/eyeline_*/eye_white/eye_hi_*/nose/pupil*/gradation*）
      → AppearanceContext->Prepare/Capture  // worker：只换贴图，不重建几何
      → PreviewActor->ApplyHeadTextureCandidate(...)   // 游戏执行绪；失败就退回下面那条
  → 否则：完整交易（另存一张新的工作卡片 → 重新开卡）
```

两条都**不覆写原始卡片**，成功后 `Selected` 换成新的工作卡片、`bIndependentCards=true`、
`AppearanceSelectedKeys[target]=key`。期间 `bAppearanceBusy=true`，UI 要把这三页设成不可用；
有未套用的 properties 时会被拒绝（先 `OnApplyProperties()` 或重置）。

## 10. `ops`：一个动作一次写入（2026-11-19 新增，已实测）

`properties_apply` 除了 `edits`（一个栏位一笔）之外，现在收 `ops`——**原作编辑器里的一个动作**，由
`appearance/ops.rs` 展开成它实际写的那一整组栏位，再**交给 `patch_properties` 一次写完**。
`ops` 与 `edits` 只能给一个（同时给会报错）。为什么要这样：原作拉一下髮色会写 4 槽 × 5 色（见
[对照文件](CHARACTER_EDITOR_PARITY_HAIR_EYES.md) §7），前端连发 60 笔 `set` 会出现中间状态
（base 改了、start 还没改），而且每一笔都触发一次重开。

```jsonc
{"action":"properties_apply","card":"<卡>","outfit":0,"cache":"<快取>",
 "resources":"<v1 共用资源>","output":"<输出卡>",
 "ops":[{"op":"hair_base_color","rgba":[0.2,0.6,0.9]}]}
```

| `op` | 参数 | 写什么 |
|---|---|---|
| `hair_base_color` | `rgba`（3 或 4 个 0..1）、`slot`（`same:false` 时才看）、`same`／`auto`／`outline`／`gloss` | 预设四个旗标**全部 true**（原作新安装的状态）：每个槽的 `baseColor`，再加 `startColor`（明度 -0.3）、`endColor`（+0.15）、`outlineColor`（-0.4）、`glossColor`（+0.3） |
| `hair_color_to_eyebrow_and_underhair` | — | `face.eyebrowColor` 与 `body.underhairColor` ← **第 0 槽**的 `baseColor`（原作取第 0 槽，不是当前页那槽） |
| `hair_from_eyebrow`／`hair_from_underhair` | — | 所有槽的 `baseColor` ← 该颜色，`startColor` -0.2、`endColor` +0.1（**和自动渐层的 -0.3／+0.15 不是同一组常数**） |
| `hair_reset_outline`／`hair_reset_gloss` | — | 每个槽依**自己的** `baseColor` 重算（-0.4／+0.3） |
| `eye_copy` | `from`：0 或 1 | 另一眼的 7 个栏位一次写完（`id`、`baseColor`、`subColor`、`gradMaskId`、`gradBlend`、`gradOffsetY`、`gradScale`） |

两件实作上的事：

- **明度位移是原作的 HSV**（保留色相与饱和，只移明度并夹在 0..1），不是 `properties::restyle` 给街区美容院用的
  「通道乘系数」——非灰色上两者给的颜色不同。黑色没有色相，变亮得到灰，和原作 `HSVToRGB(h, 0, v)` 一致。
- **只写卡片真的有的通道**，`alpha` 不动（原作头发的取色窗是 `_useAlpha: false`）；槽位数问卡片而不是写死 4，
  所以部件比原作多的卡会整头染到，不是只染前四槽。

**实测（2026-11-19）**：`StreetHeroines/alice.png`，`ops:[{"op":"hair_base_color","rgba":[0.2,0.6,0.9]}]`。
对照卡走同一条管线（只写一个无关栏位），两张读回来比对：**差异正好 60 个栏位＝4 槽 × 5 色 × 3 通道**，
其余 5747 个可编辑栏位与 `alpha` 都没动；数值与手算一致（base 0.2/0.6/0.9、start 0.133/0.400/0.600、
end 与 gloss 0.222/0.667/1.000、outline 0.111/0.333/0.500，色相比例保持）。
**注意对照要同卡型同读法**：先前拿「读 OK 卡」比「读剥过 OK 区块的输出卡」，diff 里会混进
`accessory.parts.N.hideCategory`、`clothes.parts.0.sleevesType`、`physics.*` 等读法差异，不是写入差异。
