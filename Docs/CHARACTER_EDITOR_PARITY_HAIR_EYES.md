# 人物编辑器对照：头发、眼睛细节、外挂扩充栏位（2026-11-19）

目标是把原作人物编辑器（Koikatsu Sunshine，`CustomBase` 那一套 UI）里**头发**与**眼睛**两块的全部细项，
以及外挂在这两块多出来的栏位，逐项对到我们读卡器（`CardReaderDevelopment.cmd`）现有的能力上，
标出「资料端缺／UI 缺／两边都缺」，并给一个分批顺序。

**这一轮只做盘点，没有写实作程式码**，也没有动 `Source/` 或 `Plugins/`。
原作程式码来自 `D:\XKoikatuSunshine\kks_decomp`（不进版控），本文只引用类别名、栏位名与数值范围。

姊妹文件：[读卡器 UI：外观选择的查询与套用 API](READER_UI_APPEARANCE_API.md)（e-cardload 写的六页读写表，
「换模型／换贴图」那一类已经成表，本文不重复盘点，重点放在它没涵盖的颜色、数值、开关与外挂栏位）。

## 0. 三态，不要混在一起说「有没有」

同一个栏位在我们这边可能处在三种不同状态，混着讲会得出错的结论，所以每一项都分三栏判断：

| 栏 | 意思 | 对应程式 |
|---|---|---|
| 卡片读取 | 开卡时读得到、会影响画面 | `Tools/ok-extract/src/card.rs`、`card_plugins.rs`、`accessories.rs` 等 |
| 编辑读写 | 读卡器能查询并改写、能存成新卡 | `appearance::targets()`（换素材）＋ `appearance/properties*.rs`（数值／颜色／开关） |
| UI | 画面上真的有这个控制项 | `OKGalleryProperties.cpp` 的属性面板、外观面板 |

「卡片读取有、编辑读写没有」= 画得出来但改不了；「编辑读写有、UI 没有」= 走 MCP 改得动、使用者点不到。
两者要补的东西完全不同，所以表格里的「缺在哪」只写这三者之一或其组合。

## 1. 已经确认的底盘（省得重查）

- **换素材（种类／选图）那一类已经齐**：`appearance::targets()` 里头发四槽 `hair0…hair3`、头发光泽 `hair_gloss`、
  左右瞳孔 `pupil0/1`、左右渐层 `gradation0/1`、上下眼线 `eyeline_up/down`、眼白 `eye_white`、
  上下高光 `eye_hi_up/down`、眉毛 `eyebrow`、眼影 `eyeshadow` 都在，且有 `current` 可知道「现在选的是哪一个」。
- **颜色／数值／开关那一类，资料端大多也已经齐**，但是**靠自动走访拿到的**：
  `appearance/properties.rs` 的 `walk()` 把 `face`／`body`／`hair` 区段里**每一个 `F32`/`F64`/`bool`** 都列成一项，
  所以 `hair.parts.0.baseColor.r`、`hair.parts.2.length`、`face.pupil.0.gradBlend`、`face.hlUpY` 这些**都已经读写得到**。
  它也**有明确不收的东西**：`shapeValueFace`／`shapeValueBody`／`version` 直接 return，**整数栏位（`id`、`byte`）一律不产生项目**。
- **脸型滑杆另一条路**：`OKCharacterMCPRegistry::Parameters()` 另外产生 `shape.face.0…51`／`shape.body.0…43`，
  所以原作「目」那一页的 14 根眼睛形状滑杆（`shapeValueFace[24..37]`）我们是有的。
- **ABMX 骨骼也是另一条路**：`OKBoneControls`（1194 行）已经照抄 KKSABMX 的 `InterfaceData`，
  眉毛、双眼球、眼球缩放 1／2、上睫毛 1–5、下睫毛 1–3 都在，范围与原作一致（眼球 0–3、睫毛 0–5）。

结论先讲：**这两块的大缺口不在「颜色与数值读不到」，而在三处**——
(a) 原作编辑器的**整数／byte 栏位**（`foregroundEyes` 这种）我们的属性清单不产生；
(b) 原作 UI 的**操作语义**（左右同步、左右分离、L→R 复制、跟随发色、初始化配件色、自动渐层、轮廓／光泽开关）没有对应控制项；
(c) **外挂栏位**只收了一半，`relevant()` 的白名单漏掉好几个，而且**所有贴图类栏位都被跳过**。

## 2. 头发（原作四页：后髮／前髮／側髮／附加髮，外加「頭髮共通」）

原作资料结构 `ChaFileHair`：`parts[4]`（后／前／侧／附加，`ChaFileDefine.HairKind`）＋ `kind`（整髮型組）＋ `glossId`。
每槽 `PartsInfo`：`id`、`baseColor`、`startColor`、`endColor`、`length`、`pos`／`rot`／`scl`、`acsColor[4]`、
`outlineColor`、`glossColor`、`noShake`。预设：颜色白、`length 0`、`outlineColor` 黑、`glossColor` = `#D9D9D9`、`noShake false`。

| 原作细项 | 种类 | 资料键 | 范围／预设 | 卡片读取 | 编辑读写 | UI | 缺在哪 |
|---|---|---|---|---|---|---|---|
| 髮型（四槽各一） | 选图 | `hair.parts.N.id` | 目录 id | 有 | 有（`hair0…hair3`） | 有 | — |
| 髮长 | 滑杆 | `hair.parts.N.length` | 存 0–1／显示 0–100，预设 0 | 有 | 有 | **只在属性面板的扁平清单里** | UI（没有做成原作那样的分页滑杆） |
| 停止摆动 | 开关 | `hair.parts.N.noShake` | bool，预设 false | 有 | 有 | 同上 | UI |
| 主色 | 颜色 | `hair.parts.N.baseColor` | RGBA 0–1，预设白 | 有 | 有 | 同上 | UI |
| 髮根色／髮梢色（渐层） | 颜色 ×2 | `hair.parts.N.startColor`／`endColor` | 同上 | 有 | 有 | 同上 | UI |
| 轮廓色 | 颜色 | `hair.parts.N.outlineColor` | 预设黑 | 有 | 有 | 同上 | UI |
| 光泽色 | 颜色 | `hair.parts.N.glossColor` | 预设 `#D9D9D9` | 有 | 有 | 同上 | UI |
| 髮饰色 1–3（＋第 4 个未用） | 颜色 ×4 | `hair.parts.N.acsColor.0…3` | 预设白 | 有 | 有 | 同上 | UI |
| 頭髮光泽种类 | 选图 | `hair.glossId` | 目录 id，预设 0 | 有 | 有（`hair_gloss`） | 有 | — |
| 位置／旋转／缩放 | 数值 ×9 | `hair.parts.N.pos`／`rot`／`scl` | `scl` 预设 1，其余 0 | **读了但没套用** | 有（走访会列出） | 没有 | `card.rs:1969-1977` 把三者读进 `CardInfo.hair_parts`，全仓库没有第二处消费它们（`accessories.rs` 只用颜色与 `length`）。所以现在改这九项**画面不会变**；要给 UI 之前得先让它真的套用 |
| 整髮型組 | 下拉 | `hair.kind` | 整数 | **没读**（`card.rs` 没有 `kind` 分支） | **没有（整数不列）** | 没有 | 资料端＋UI |
| 四槽同步设定 | 开关 | 不在卡片里（`CustomBase.customSettingSave.hairSameSetting`，预设 true） | — | 不适用 | — | 没有 | UI（是编辑器状态，不是卡片资料） |
| 「反映」把主色套到全部槽 | 按钮 | `btnReflectColor` → 写四槽 | — | 不适用 | 可用现有 set 做 | 没有 | UI |
| 把髮色套到眉毛／陰毛 | 按钮 ×2 | `btnEyebrowColor`／`btnUnderhairColor` → `face.eyebrowColor`／`body.underhairColor` | — | 有 | 有（两个目标栏位都读写得到） | 没有 | UI |
| 自动渐层 | 开关 | `tglAutoSetting`（由主色推 start/end） | — | 不适用 | 可用现有 set 做 | 没有 | UI |
| 变更轮廓色／变更光泽色 | 开关 ×2 | `tglChangeOutline`／`tglChangeGloss`（是否连动） | — | 不适用 | — | 没有 | UI |
| 初始化髮饰色 | 按钮 | `btnInitAcsColor` | — | 不适用 | 可用现有 set 做 | 没有 | UI |

**小结（头发）**：资料端几乎不缺，缺的是 `hair.kind` 与 `pos/rot/scl` 是否真的套用；
其余全部是 **UI 缺**——现在只能在属性面板那张扁平清单里改 `hair.parts.0.baseColor.r` 这种 key，
没有原作那样的「四页 × 颜色块 × 同步开关」版面。

## 3. 眼睛细节（原作两页：目 `CvsEye01`／瞳 `CvsEye02`）

### 3.1 目（`CvsEye01`）

14 根滑杆全部写进 `face.shapeValueFace[24..37]`（`arrIndex`），显示值 `ConvertTextFromRate(0,100,…)`，
预设来自 `ChaFileDefine.cf_faceInitValue`：上眼睑形状 1–3、下眼睑形状 1–3、眼睛 Y／X／Z、倾斜、
高度、宽度、内侧 X、外侧 Y。

| 原作细项 | 种类 | 资料键 | 卡片读取 | 编辑读写 | UI | 缺在哪 |
|---|---|---|---|---|---|---|
| 14 根眼睛形状滑杆 | 滑杆 | `shapeValueFace[24…37]` | 有 | 有（`shape.face.24…37`） | 有（Gallery 52 根脸部滑杆内） | — |
| 上眼线种类／下眼线种类 | 选图 ×2 | `face.eyelineUpId`／`eyelineDownId` | 有 | 有（`eyeline_up`／`eyeline_down`） | 有 | — |
| 眼线颜色 | 颜色 | `face.eyelineColor` | 有 | 有 | 扁平清单 | UI |
| 上眼线粗细 | — | `face.eyelineUpWeight`（预设 1） | 待查（原作也只存不改） | 有（走访列出，已有中文标签「上眼線粗細」） | 没有 | **原作编辑器本身也没有这个控制项**（整份 decomp 只在 `MemberInit`／`Copy` 出现），要做是我们加的 |

### 3.2 瞳（`CvsEye02`）

`face.pupil[2]`（左／右），每边 `PupilInfo`：`id`、`baseColor`、`subColor`、`gradMaskId`、`gradBlend`、
`gradOffsetY`、`gradScale`。瞳孔几何与高光是**左右共用**的单一栏位。预设：`pupilWidth/Height 0.9`、
`pupilX/Y 0.5`、`hlUpX/Y 0.5`、`hlDownX/Y 0.5`、各色白。

| 原作细项 | 种类 | 资料键 | 卡片读取 | 编辑读写 | UI | 缺在哪 |
|---|---|---|---|---|---|---|
| 瞳孔种类（左／右） | 选图 ×2 | `face.pupil.N.id` | 有 | 有（`pupil0`／`pupil1`） | 有 | — |
| 瞳孔主色／次色（左／右） | 颜色 ×4 | `face.pupil.N.baseColor`／`subColor` | 有 | 有 | 扁平清单 | UI |
| 瞳孔渐层种类（左／右） | 选图 ×2 | `face.pupil.N.gradMaskId` | 有 | 有（`gradation0/1`） | 有 | — |
| 渐层混合／垂直位移／缩放（左／右） | 滑杆 ×6 | `face.pupil.N.gradBlend`／`gradOffsetY`／`gradScale` | 有 | 有（已有中文标签） | 扁平清单 | UI |
| 瞳孔宽／高 | 滑杆 ×2 | `face.pupilWidth`／`pupilHeight` | 有 | 有 | 扁平清单 | UI |
| 瞳孔水平／垂直位置 | 滑杆 ×2 | `face.pupilX`／`pupilY` | 有 | 有 | 扁平清单 | UI |
| 眼白种类 | 选图 | `face.whiteId` | 有 | 有（`eye_white`） | 有 | — |
| 眼白主色／次色 | 颜色 ×2 | `face.whiteBaseColor`／`whiteSubColor` | 有 | 有 | 扁平清单 | UI |
| 上高光种类／下高光种类 | 选图 ×2 | `face.hlUpId`／`hlDownId` | 有 | 有（`eye_hi_up/down`） | 有 | — |
| 上／下高光颜色 | 颜色 ×2 | `face.hlUpColor`／`hlDownColor` | 有 | 有 | 扁平清单 | UI |
| 上／下高光 X／Y | 滑杆 ×4 | `face.hlUpX/Y`、`hlDownX/Y` | 有 | 有（已有中文标签） | 扁平清单 | UI |
| 眼睛描画前后（三选一） | 单选 ×3 | `face.foregroundEyes`（byte 0/1/2） | **没读**（全仓库 grep 无此栏位） | **没有（byte 不列）** | 没有 | **资料端＋UI**；连开卡渲染都没套用 |
| 眉毛描画前后 | 单选 | `face.foregroundEyebrow`（byte） | **没读** | **没有** | 没有 | 资料端＋UI（严格说属眉毛页，一起补） |
| 左右同时／左／右 切换 | 三选一 | `selEyeSetType`（编辑器状态，非卡片） | 不适用 | — | 没有 | UI |
| 左右是否同设定 | 唯读 | `face.isPupilSameSetting`（计算属性） | 不适用 | — | 没有 | UI |
| 左→右／右→左 复制 | 按钮 ×2 | `btnCopyLtoR`／`btnCopyRtoL` | 不适用 | 可用现有 set 做 | 没有 | UI |
| 眼影种类／颜色 | 选图＋颜色 | `face.baseMakeup.eyeshadowId`／`eyeshadowColor` | 有 | 有（`eyeshadow` ＋ 颜色） | 选图有、颜色在扁平清单 | UI（颜色） |

**小结（眼睛）**：唯一真正的**资料端缺口是 `foregroundEyes` / `foregroundEyebrow`**（byte 栏位，`walk()` 不产生项目，
也没有 appearance target）。其余全是 UI 缺：现在使用者没有「瞳」这一页，只有一张扁平 key 清单。

## 4. 外挂扩充栏位（这块最可能根本读不到）

我们的编辑属性只收白名单内的 KKEx 外挂（`appearance/properties/plugins.rs` 的 `relevant()`）：
`materialeditor`、`hairaccessorycustomizer`、`hairshadowcolor`、`pushup`、`dynamicboneeditor`、
`moreaccessories`、`accessorystates`、`overlay`。**而且 `visit()` 会跳过名称含 `texture` 的栏位与 `*Original` 栏位。**

| 外挂 | 卡片区段键 | 编辑器多出来的栏位 | 卡片读取 | 编辑读写 | UI | 缺在哪 |
|---|---|---|---|---|---|---|
| HairAccessoryCustomizer | `KK_Plugins.HairAccessoryCustomizer`（含 `CoordinateHairAccessories`） | 跟随髮色、頭髮光澤、轮廓色、饰品色、髮长、光澤色（每个饰品槽一组） | 有（`accessories.rs`） | 有（白名单内，已有中文标签） | 扁平清单 | UI |
| HairShadowColorControl | 实际写在 MaterialEditor 的 `ShadowColor` 属性；自身区段键 `HairShadowColorControl` | 四个髮槽各一个「Hair shadow color」 | 待查 | 有（`hairshadowcolor` 与 `materialeditor` 都在白名单） | 扁平清单 | UI |
| MaterialEditor | `KK_Plugins.MaterialEditor` | 每个 renderer／material 的 float、color、keyword、**texture**、renderer 属性 | 有 | float、color、**keyword 都读写得到**（`MaterialKeywordProperty.Value` 是 bool，`visit()` 收 bool）；**texture 被跳过**（名称含 `texture`）；**RendererProperty 也读写不到**（它的 `Value` 是字串 `"0"`／`"True"`，`visit()` 只收长得像 XML 的字串） | 扁平清单 | 贴图：资料端＋UI；renderer 开关（Enabled／ShadowCastingMode／ReceiveShadows／RecalculateNormals）：资料端＋UI |
| ABMX（KKSABMX / `KKABMX.Core`） | `KKABMX.Core` | 眉毛／双眼球／眼球缩放 1–2／上睫毛 1–5／下睫毛 1–3（本文第 1 节） | 有（`abmx.rs`） | 有（`bone.*`，经 `EditorModsJson`） | 有（骨骼滑杆） | 部分：`BoneData` 只取 `location<10`，**饰品本地骨（location≥10）的修改读不到** |
| KoiSkinOverlayX | **`KSOX`** | 脸／身体 under/over 贴图，**`EyeUnderL/R`、`EyeOverL/R`、`EyelineUnder`、`EyebrowUnder`** | 有（`card.rs` 认 `KSOX`） | **没有**：`relevant("KSOX")` 不含 `overlay` 字样，整段不收 | 没有 | 资料端＋UI（眼睛这块的重点漏项） |
| KoiClothesOverlayX | **`KCOX`** | 衣物贴图层、BodyMask／BraMask／InnerMask | 有 | 部分：`properties.rs` 另有一段专门认 `KCOX` 的 `Overlays`，但贴图本身仍不是可编辑项 | 没有 | 贴图：资料端＋UI |
| EyeControl | `com.deathweasel.bepinex.eyecontrol` | `EyeOpenMax`（0–1，预设 1）、`DisableBlinking`（bool） | 有（`card_plugins::apply_eyecontrol`） | **没有**（不在白名单） | 没有 | 资料端＋UI |
| EyeShaking | `com.deathweasel.bepinex.eyeshaking` | `EyeShaking`（bool） | **没读**（全仓库 grep 无此 GUID） | **没有** | 没有 | 资料端＋UI；原作这项只在 H 场景生效，优先度低 |
| UncensorSelector | `com.deathweasel.bepinex.uncensorselector` | 身体／部件 GUID 选择 | 有（`card.rs` 有 `uncensorselector` 分支） | **没有**（不在白名单） | 没有 | 资料端＋UI（不属头发眼睛，但在我这块的点名范围内） |

### 4.1 哪些外挂真的会在「头发／眼睛」这两页加栏位（已穷举）

对 `kks_decomp\plugins` 全文 grep `MakerSlider`／`MakerToggle`／`MakerColor`／`MakerDropdown`／`MakerCategory`，
会注册 Maker 控制项的外挂有 17 个；再按分页过滤（`00_FaceTop/tglEye01`＝目、`tglEye02`＝瞳、头发四页、饰品窗），
**真的落在我这两块的只有四个**：

- **EyeControl** → 目／瞳分页加「Eye Open Max」滑杆（0–1，预设 1）与「Disable Character Blinking」开关。
- **HairShadowColorControl** → 四个头发分页各加一个「Hair shadow color」颜色块（实际存进 MaterialEditor 的 `ShadowColor`）。
- **HairAccessoryCustomizer** → 饰品窗里对「髮饰类」饰品加六项（跟随髮色、頭髮光澤、轮廓色、饰品色、髮长、光澤色）。
- **KKSABMX** → 自建分页 `tglEye02ABM`（Eyes 2）、`tglEyelashUpABM`／`tglEyelashLoABM`（上／下睫毛），并沿用原作的眉毛分页。

其余（SkinEffects、EditFangs、SexFaces、Bulge、BecomeTrap、Pregnancy、ClothingBlendShape、
ClothingStateMenu、AccessoryStates、SliderHighlight、GeBo、IllusionFixes、FKIK…）都不在这两页，
属于别人那两块或与编辑栏位无关。**所以「外挂扩充」这一块的清单就是上面四个＋MaterialEditor／Overlay 这两个通用层**，
不必再回去翻一遍 plugins 目录。

## 5. 分批顺序

1. **第一批（资料端真缺、改动小、立刻有用）**
   - `face.foregroundEyes` / `face.foregroundEyebrow`：byte 栏位要能读写（`walk()` 现在整数一律不收，
     要的是「白名单式的整数项」而不是放开全部整数，否则 `*.id` 会被使用者直接改坏，踩到
     [读写表第 6 节](READER_UI_APPEARANCE_API.md) 已经写明的那个坑）。
   - EyeControl 两项、EyeShaking 一项：把 `relevant()` 白名单补上，它们本来就是 KKEx 里的纯量与 bool。
2. **第二批（UI：把扁平清单变成原作那样的两组分页）**
   - 头发四页：髮型、髮长、停止摆动、六个颜色块、髮饰色 ×3 ＋ 同步／反映／初始化按钮。
   - 眼睛两页：目（14 滑杆＋眼线）、瞳（左右切换＋瞳孔／渐层／眼白／高光），含 L→R 复制。
   - 这批不需要新的资料能力，全部可以用现有 `properties get/set/apply` 与 `appearance` 做。
3. **第三批（贴图与 overlay，工程量最大）**
   - `KSOX` 的眼睛／眼线／眉毛 overlay 贴图读写；MaterialEditor 的 texture 属性。
   - 要先决定「贴图怎么在读卡器里给／存」（档案选择、存回卡片的体积），不是单纯补栏位。
4. **第四批（边角）**
   - `hair.parts.N.pos/rot/scl`：**先让它真的套用**（现在读进 `CardInfo` 就没人用了），否则 UI 上调了没反应比没有更糟；
     `hair.kind` 连读都还没读。
   - MaterialEditor 的 `RendererProperty`（renderer 开关，`Value` 是字串）。
   - ABMX `location≥10` 的饰品本地骨。
   - UncensorSelector 的选择（跨到身体那一块，和别人的盘点合并再做）。

## 6. 本文的证据边界

- 全部结论来自读 `D:\XKoikatuSunshine\kks_decomp` 的程式码与本仓库的程式码，**没有启动游戏、没有启动读卡器、没有实拍**。
  标「待查」的项目就是只凭读码不敢断言的（目前只剩 `face.eyelineUpWeight` 一项，原作自己也只存不改）。
- 「没读」是对本仓库 `Tools/ok-extract/src/` 全文 grep 该栏位名／GUID 没有命中；
  「读了但没套用」是读进 `CardInfo` 之后没有第二处消费。两者都是读码结论，不是实测。
- 「扁平清单」指的是属性面板现在呈现 `hair.parts.0.baseColor.r` 这种 key 的样子；
  我没有实际开读卡器截图确认它当下长什么样，所以第 2、3 节的「UI」栏是按程式与读写表推出来的，
  要动手做之前应该先开一次读卡器拍一张现况图。
