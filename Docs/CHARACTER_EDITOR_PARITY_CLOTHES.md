# 人物编辑器对齐原作：衣服与配件（盘点）

2026-11-19，f-yvonne。只盘点，不含实作。对照来源：

- 原作反编译 `D:\XKoikatuSunshine\kks_decomp\Assembly-CSharp`（不进版控）：`ChaFileClothes.cs`、`ChaFileAccessory.cs`、`ChaFileDefine.cs`、`ChaAccessoryDefine.cs`、`ChaCustom\CvsClothes.cs`、`CustomChangeClothesMenu.cs`、`CvsClothesCopy.cs`、`CvsDrawCtrl.cs`、`CustomBase.cs`（`ChangeClothesState`）、`CvsAccessory.cs`、`CustomAcsMoveWindow.cs`、`CustomAcsParentWindow.cs`、`CvsAccessoryChange.cs`、`CvsAccessoryCopy.cs`、`CustomCoordinateFile.cs`、`ChaControl.cs`（`SetAccessoryPos/Rot/Scl`、`GetClothesDefaultColor`、`GetAccessoryDefaultColor`）。
- 我们这边：`Tools/ok-extract/src/appearance.rs` `targets()`（选图目标）、`appearance/properties.rs` `walk()`（通用属性：只收 float／bool／颜色／`parentKey`）、`appearance/properties/plugins.rs`（MoreAccessories 额外槽的 XML 属性）、`appearance/extra.rs`（额外槽选图）、`Source/OpenKoikatsu/OKReaderScreen.cpp`（新读卡画面的「衣服」「配件」分页）、`OKGalleryWidget.cpp`（穿着状态抽屉）、`OKGalleryProperties.cpp`（属性面板控件）、`OKCharacterMCPRegistry::Parameters()`（MCP 把 `EditorProperties` 全部转成参数，数值范围一律 ±1000000、颜色 0–1）、`okclothes.rs`／`OKGalleryClothing.cpp`（.okclothes）。
- e-fork-2 的控制稽核表 `E:\OpenKoikatsu\Saved\Reports\reader-control-audit-20261119.txt`：它比的是新画面与旧 UMG 画面（4877 个控件里新画面镜像了 4866 个），不是与原作比；衣服与配件页没有缺漏列，所以这份盘点里的「UI 已有」都是指旧画面已有、新画面也镜像到了的。

标记：**已有**／**部分**／**没有**；缺口：**资料端缺**（ok-extract 不读、不写或不渲染）、**UI 缺**（资料能改但画面没有对应控件或形式不对）、**两边都缺**。

## 1. 分页与分类骨架

| 原作 | 原作内容 | 我们（新读卡画面） |
|---|---|---|
| 衣服分页（`CustomChangeClothesMenu`，9 项选单） | 0 上衣、1 下装、2 胸罩、3 内裤、4 手套、5 裤袜、6 袜子、7 鞋子、8 衣装复制 | 「衣服」：穿着状态、服装、外观选择、颜色与设定（按功能分，不按部位分） |
| 衣服分页右侧显示面板（`CvsDrawCtrl`） | 穿着状态（自动／穿／半脱／全脱）、配件显示（主／副）；表情、视线、姿势、灯光、背景（不属本块） | 「衣服›穿着状态」抽屉；配件显示没有 |
| 服装套切换（`CustomControl.ddCoordinate`） | KKS 4 套：Plain、Swim、Pajamas、Bathing（`ChaFileDefine.CoordinateType`）；KK 卡可有 7 套 | 「衣服›服装」下拉＋上下套 |
| 配件分页（`CvsAccessory` × 20 槽） | 每槽：类别、款式、父骨、两组位移、4 色、不摇晃、H 分组 | 「配件›饰品」（选槽、选类别与款式、新增饰品栏位）、「配件›饰品颜色与位置」、「配件›全部属性」 |
| 配件槽交换／复制（`CvsAccessoryChange`） | 来源槽→目标槽复制，位移复制、左右／上下反转 | 没有 |
| 配件复制（`CvsAccessoryCopy`） | 套与套之间按槽复制 | 没有 |
| 服装卡（`CustomCoordinateFile`） | 存／覆盖／删除／读取原作服装卡（含名称） | 部分：读原作服装卡、汇出／穿上 `.okclothes`；不写原作服装卡 |
| 额外配件槽（MoreAccessories，外挂） | 原作没有，外挂在 KKEx XML 里加槽 | 已有：额外槽选图、属性（`extra.rs`、`plugins.rs`），「新增饰品栏位」 |

## 2. 衣服：资料键

`ChaFileCoordinate.clothes`（`ChaFileClothes`），每套一份：

- `parts[9]`（`ClothesKind`：top、bot、bra、shorts、gloves、panst、socks、shoes_inner、shoes_outer）
  - `id`：款式，清单类别 `co_top`105、`co_bot`106、`co_bra`107、`co_shorts`108、`co_gloves`109、`co_panst`110、`co_socks`111、`co_shoes`112（内外鞋同类别）。
  - `colorInfo[4]`：`baseColor`（预设白）、`pattern`（`mt_pattern`，预设 0）、`tiling`（Vector2，预设 0,0）、`patternColor`（预设白）、`offset`（预设 0.5,0.5）、`rotate`（预设 0.5）。
  - `emblemeId`、`emblemeId2`（`mt_emblem`，预设 0）。
  - `hideOpt[2]`（选项 1／2 的隐藏，UI 是「显示」开关，存反值）。
  - `sleevesType`（0–2，只有上衣）。
- `subPartsId[3]`：上衣是水手服（清单 Kind 1）时为 `cpo_sailor_a/b/c`（200–202），外套（Kind 2）时为 `cpo_jacket_a/b/c`（210–212）。
- `hideBraOpt[2]`、`hideShortsOpt[2]`：胸罩、内裤页的选项开关存这里，不存在 `parts[2/3].hideOpt`。
- 穿着状态不在服装资料里：`ChaFileStatus.clothesState[9]`（每件 0 穿、1 半脱、2 再半、3 全脱）、`shoesType`。

### 2.1 衣服细项对照

| 原作细项 | 种类 | 资料键／范围／预设 | 我们 | 缺口 |
|---|---|---|---|---|
| 各部位款式（8 页） | 选图 | `parts[k].id` | 已有（`clothes0..8`） | — |
| 鞋子页编辑哪一槽 | — | 原作只有一个鞋子页；内／外鞋槽都在资料里（哪一槽由 prefab 序列化，未确认） | 我们两槽都给 | 待确认，不影响资料 |
| 水手服／外套子部件 3 个 | 选图，**只在上衣 Kind=1／2 时出现** | `subPartsId[0..2]` | 部分：6 个目标一直都显示，不看上衣种类 | UI 缺（条件显示） |
| 主色 ×4 | 颜色（无透明度） | `colorInfo[i].baseColor` | 部分：通用属性面板四个 0–1 数字框 | UI 缺（颜色选择器） |
| 颜色层可用性 | 显示条件 | 来自模型 `ChaClothesComponent.useColorN01/02/03`；第 4 层只有水手服／外套子部件有 `rendAccessory` 时才有；上衣 Kind 1／2 时取三个子部件的联集 | 没有：四层一直都显示 | 两边都缺（资料端不输出 useColor） |
| 图样 ×4 | 选图 | `colorInfo[i].pattern`（`mt_pattern`） | 已有（`pattern{k}_{i}`），渲染有（`clothes_texture.rs`） | — |
| 图样宽、高 | 滑杆，显示 0–100 | `tiling.x/.y`，存 0–1，预设 0 | 部分：数字框，范围 ±1000000 | UI 缺（范围、滑杆） |
| 图样位置 X、Y | 滑杆 | `offset.x/.y`，存 0–1，预设 0.5 | 部分：同上 | UI 缺 |
| 图样旋转 | 滑杆 | `rotate`，存 0–1，预设 0.5 | 部分：同上 | UI 缺 |
| 图样颜色 ×4 | 颜色（有透明度） | `colorInfo[i].patternColor` | 部分：数字框 | UI 缺 |
| 每个滑杆的「重置」 | 按钮 | 回到进入编辑器时的值（`defChaInfo`），不是 0 | 没有 | UI 缺 |
| 初期设定 | 按钮 | 四层主色回模型预设色（`ChaClothesComponent.defMainColor0x`），图样 0、图样色白、tiling 0、offset/rotate 0.5 | 没有 | 两边都缺（资料端没有模型预设色） |
| 徽章 1、2 | 选图，**只在模型有徽章位时出现**（`IsEmblem`） | `emblemeId`、`emblemeId2` | 部分：两个目标一直都显示 | UI 缺（条件显示） |
| 选项 1、2 | 开关，**只在模型有 `objOpt01/02` 时出现** | `hideOpt[0/1]`；胸罩用 `hideBraOpt`，内裤用 `hideShortsOpt` | 部分：属性面板有 bool，但渲染不看 | 资料端缺（渲染不隐藏 objOpt），UI 缺（条件显示、正反向） |
| 袖子种类 | 三选一，**只在上衣有 `objSleeves01..03` 时出现** | `parts[0].sleevesType`，换上衣时归 0 | 没有：`walk()` 不收整数，渲染也不看 | 两边都缺 |
| 衣装复制 | 来源套→目标套，按部位勾选，上衣另可勾子部件；全开／全关 | 复制 `parts[k]`、`subPartsId` | 没有 | 两边都缺 |

### 2.2 穿着状态与显示

| 原作细项 | 种类 | 资料／行为 | 我们 | 缺口 |
|---|---|---|---|---|
| 穿着状态：自动／穿／半脱／全脱 | 四选一 | 半脱＝上衣、下装、内外鞋 3，其余 0；全脱＝全部 3；「自动」随所在页切换（上衣、下装、鞋页穿上，内衣页半脱） | 部分：「穿上／半脱／全脱」三键＋每件循环切换；没有「自动」 | UI 缺（自动） |
| 每件状态 0–3 | — | `ChaFileStatus.clothesState[k]` | 已有（每件按钮循环；MCP `clothing_states`） | — |
| 男性胸罩页 | 显示条件 | 男性只有服装带胸罩设定时才显示胸罩页 | 未查 | 待确认 |
| 下装／胸罩／内裤页停用 | 显示条件 | 上衣有 `notBot`／`notBra`／`notShorts` 时该页不可点 | 没有 | 两边都缺（资料端不输出 not* 旗标） |
| 配件显示：主／副 | 开关 ×2 | `SetAccessoryStateCategory(0/1)`，对应 `hideCategory` | 没有（MCP 相机的 `hide_accessories` 只全藏） | UI 缺 |

## 3. 配件：资料键

`ChaFileCoordinate.accessory.parts[20]`（`ChaFileAccessory.PartsInfo`），额外槽在 KKEx `moreAccessories` XML：

- `type`：类别，120 无、121 髮、122 头、123 脸、124 颈、125 胴、126 腰、127 腿、128 臂、129 手、130 下腹部。
- `id`：款式。
- `parentKey`：父骨，55 个（`ChaAccessoryDefine.AccessoryParentKey`，`none`＝未设定 + `a_n_hair_pony` … `a_n_ana`）；1–14 是头部骨（`CheckPartsOfHead`）；18 对左右可反转（`GetReverseParent`）。
- `addMove[2,3]`：两组修正 ×（位置、旋转、缩放），预设 (0,0,0)／(0,0,0)／(1,1,1)。
- `color[4]`：预设白；第 4 色给 `rendAlpha`。
- `hideCategory`：0 主、1 副（H 时的配件分组）。
- `noShake`：不摇晃。

### 3.1 配件细项对照

| 原作细项 | 种类 | 资料键／范围／预设 | 我们 | 缺口 |
|---|---|---|---|---|
| 20 个原作槽 | 槽列 | `parts[0..19]` | 已有 | — |
| 额外槽 | 外挂 | KKEx XML，`<accessory type=… />` | 已有（新增、选图、属性） | — |
| 类别 | 下拉 11 项 | `type` | 已有（选图目标按类别分） | — |
| 款式 | 选图 | `id` | 已有 | — |
| 换款时保留父骨／颜色 | 开关 ×2（编辑器设定，不存卡） | `acsTakeOverParent`、`acsTakeOverColor` | 没有：换款时父骨照新款预设填（`extra.rs` 用 `or_insert`，原作槽未查） | UI 缺 |
| 父骨 | 55 选一视窗 | `parentKey` | 部分：属性面板下拉＋文字框 | — |
| 父骨不可改的款式 | 显示条件 | 清单 `HideHair==1` 或 `Parent=="null"` 时父骨、位移整块隐藏 | 没有 | UI 缺 |
| 父骨初始化 | 按钮 | 回清单预设父骨 | 没有 | UI 缺 |
| 父骨左右反转 | 按钮 | `GetReverseParent` 18 对 | 没有 | UI 缺 |
| 位置 X/Y/Z ×2 组 | 输入＋加减按钮 | `addMove[g,0]`，−100–100，取一位小数（公分×10 的单位，未换算） | 部分：数字框，范围 ±1000000，不取整 | UI 缺（范围、取整） |
| 旋转 X/Y/Z ×2 组 | 输入＋加减 | `addMove[g,1]`，0–360 循环，取整数 | 部分：同上 | UI 缺 |
| 缩放 X/Y/Z ×2 组 | 输入＋加减 | `addMove[g,2]`，0.01–100，取两位小数 | 部分：同上 | UI 缺 |
| 第 2 组修正 | 显示条件 | 只有模型有第二个移动节点（`objAcsMove[slot,1]`）才出现 | 部分：两组一直都显示 | UI 缺 |
| 加减步长 | 三档开关 | 位置 0.1／1／10，旋转 1／5／10，缩放 0.01／0.1／1（编辑器设定） | 没有 | UI 缺 |
| 单轴重置、全部重置 | 按钮 | 回预设 0／0／1 | 没有 | UI 缺 |
| 位移复制／贴上 | 按钮 | 编辑器剪贴簿，跨槽 | 没有 | UI 缺 |
| 3D 控制器（gizmo） | 显示开关、移动／旋转二选一、速度、大小 ×2 组 | 编辑器设定 | 没有 | UI 缺 |
| 颜色 1–3 | 颜色，**看模型 `useColor01/02/03`** | `color[0..2]` | 部分：四色一直都显示，数字框 | 两边都缺（资料端不输出 useColor） |
| 颜色 4 | 颜色（透明度），**只在模型有 `rendAlpha`** | `color[3]`；a=0 时不画该 renderer | 部分：渲染已照做（`accessories.rs`），UI 一直都显示 | UI 缺（条件显示） |
| 颜色初始化 | 按钮 | 回模型预设色（`GetAccessoryDefaultColor`） | 没有 | 两边都缺 |
| 不摇晃 | 开关 | `noShake` | 已有（属性面板 bool，`dbone.rs` 照做） | — |
| H 分组（主／副） | 二选一，只在 `Game.isAddH` 时显示 | `hideCategory` | 没有：原作槽的整数 `walk()` 不收；额外槽的 XML 属性会当数字列出 | 资料端缺（原作槽），UI 缺 |
| 槽位交换／复制 | 来源槽、目标槽、复制；位移按组复制、左右反转、上下反转 | — | 没有 | 两边都缺 |
| 套间配件复制 | 来源套、目标套、按槽勾选，全开／全关 | — | 没有 | 两边都缺 |

### 3.2 其它插件资料（属于衣服配件的）

`plugins.rs` 已把 MaterialEditor（衣服 ObjectType 1、配件 2，只列本套）、HairAccessoryCustomizer、AccessoryStates、Pushup、DynamicBoneEditor、Overlay 的数值列进「全部属性」。原作编辑器没有这些页，不在本表对齐范围；它们的分页设计等原作项目补完再排。

## 4. 共同的形式问题

1. **整数字段进不来**：`properties.rs` `walk()` 只收 F32／F64／Bool／`parentKey` 字串，原作的 `sleevesType`、`hideCategory` 是整数，没有入口。
2. **范围一律 ±1000000**：MCP `Parameters()` 与属性面板对非颜色数值都给 ±1000000；原作的范围与取整（见上表）都没有套。
3. **颜色是 RGBA 四个数字框**：原作是颜色视窗（`CvsColor`），主色无透明度、图样色与配件第 4 色有透明度。
4. **不看模型决定显示什么**：原作大量依模型元件（`ChaClothesComponent`、`ChaAccessoryComponent`）开关项目：useColor、徽章、选项、袖子、子部件、第二修正组、父骨可改。我们一律全列，用户会改到没有效果的值。资料端要先输出这些旗标。
5. **没有重置与预设**：原作每个滑杆有重置（回进入编辑器时的值），衣服与配件有「初期设定」（回模型预设色）。

## 5. 建议分批顺序

1. **资料端小补**（只动 `appearance/properties.rs` 与 MCP 范围）：整数字段 `sleevesType`、`hideCategory` 进属性表；每个已知键带原作范围、步长、取整（tiling／offset／rotate 0–1，位置 ±100 一位小数，旋转 0–360 整数，缩放 0.01–100 两位小数），UI 与 MCP 都吃这个范围。
2. **模型旗标输出**：ok-extract 读衣服／配件模型元件，输出 useColor、rendAlpha、徽章位、objOpt01/02、objSleeves01–03、notBot／notBra／notShorts、第二移动节点、模型预设色；同时把 `hideOpt`、`hideBraOpt`、`hideShortsOpt`、`sleevesType` 接进渲染（现在改了没效果）。
3. **条件显示**：UI 按第 2 批的旗标隐藏用不到的项目；子部件按上衣 Kind；父骨按清单 `HideHair`／`Parent`。
4. **颜色选择器与重置**：颜色视窗；每项重置回载入时的值；衣服「初期设定」、配件「颜色初始化」「父骨初始化」「左右反转」。
5. **配件位移视窗**：加减按钮与三档步长、单轴／全部重置、位移复制贴上、换款保留父骨／颜色；3D gizmo 最后做。
6. **复制类**：衣装复制、配件套间复制、配件槽交换／复制（含左右、上下反转）。
7. **显示与服装卡**：穿着状态「自动」、配件主／副显示开关、男性胸罩页条件；写出原作服装卡（现在只读原作服装卡、写 `.okclothes`）。

第 1、2 批是资料端，第 3–7 批主要是 UI。第 2 批要读 prefab 元件，比较费工，可以和第 1 批并行。

## 6. 原先待确认的三项（2026-11-19 实测）

- **鞋子页编哪一槽**：编的是室外鞋 `shoes_outer`（8）。原作的 `KoikatsuSunshine_Data/level3` 里有 8 个 `CvsClothes`，读出它们的 `typeClothes` 是 0–6 和 8，没有 7。`typeClothes` 是元件的第一个序列化栏位；场景档没有型别树，所以按元件标头之后的位移读取（`entries.rs` 的忽略测试 `clothes_page_kinds`）。KKS 编辑器没有室内鞋的页面。我们两槽都给，多出室内鞋。
- **20 槽换款式时父骨怎么填**：原作「保留父骨」（`acsTakeOverParent`）预设是开的（`CustomBase.cs`）。换款时父骨照旧，只有新款在清单里标 `HideHair==1` 时才清空，改回用清单预设。读卡器实测：原作卡 KK_007604，槽 16 原本是腕饰、父骨 `a_n_wrist_L`，换成戒指（清单预设父骨 `a_n_ring_L`）后仍是 `a_n_wrist_L`。这和原作的预设行为一致。缺的部分：`HideHair==1` 时清空，以及「保留父骨／保留颜色」两个开关。
- **男性胸罩页**：原作只有清单里有 `Sex` 不是 3 或 99 的胸罩时，男性才显示胸罩页（`CustomBase.IsMaleCoordinateBra`）。读卡器实测：原作男角卡 KK_224305 的 `clothes2` 选图照样给 1035 项，没有这个条件。归在第 3 批（条件显示）。

## 7. 本机实测环境

- F 树的游戏目录：版控里 `Config/DefaultGame.ini` 写的是 `Root=D:/KoikatuSunshine`，这台机器上没有这个目录；正确的原作目录是 `D:\XKoikatuSunshine`（注意有 **X**）。所以本机的 `Saved/Config/WindowsEditor/GameUserSettings.ini` 加了 `[OKGameRoot] Root=D:/XKoikatuSunshine`。这是本机设定，不进版控；版控那行要不要改，由使用者决定。没有这行时，读卡器开原作卡会读不到任何 bundle，画面是空的。
- 判定鞋子页编哪一槽的方法（复查时照做）：`KoikatsuSunshine_Data/level*` 没有型别树，所以按 MonoBehaviour 标头的位移读：m_GameObject 12 bytes、m_Enabled 4 bytes、m_Script 12 bytes（fileID i32 ＋ pathID i64）、m_Name（长度 i32 ＋ 字串，补齐到 4 的倍数），之后的第一个 i32 就是 `CvsClothes.typeClothes`。把 MonoBehaviour 按 m_Script 分组，找每组 7–10 个、第一个整数都在 0..8 的组。level3 有一组 8 个元件，每个大小 1936 bytes（第 8 个是 1972），值是 0–6 和 8。程式在 `Tools/ok-extract/src/entries.rs` 的忽略测试 `clothes_page_kinds`，执行：`OK_GAME=D:/XKoikatuSunshine cargo test --lib clothes_page_kinds -- --ignored --nocapture`。

## 8. 第 2 批验收纪录与注意事项（2026-11-19）

- **范围是软限制**：`min`／`max` 是原作 UI 滑杆的两端（配合 `display_scale`／`unit` 显示），不是资料的合法范围。原作 `ChaControl.SetShape*Value` 与衣服、配件的数值都不夹值，ABMX／slider unlocker 的卡带 0..1 以外的值。所以：
  - 超出 `min`／`max` 的值接受、不夹住、不拒绝，那一列标 `out_of_range: true`（读进来的值与 `set` 后待套用的值都算）。
  - 只有 `limit_min`／`limit_max` 会拒绝，且只写在资料本身有界的地方：颜色分量 0..1。`shape.*`、图样大小／位置／旋转、配件 `addMove` 都不写。骨骼、物理、怀孕、风格这几组沿用原本的硬界（`Number()` 给的 `limit_*`）。
  - 其他硬拒：非有限数、型别不对、`choice` 给了 `options` 以外的值。
  - 读卡、`apply` 都不按范围改值：只写被编辑的键，送来的值只取整（`decimals`）与 `wrap`。
  - **「现在看不到」不构成写入限制**（一般规则，第三批起适用所有旗标）：`available:false` 的列、原作不能点的页（`model.pages`）、隐藏的父骨与位移，都只决定 UI 显示或变灰，资料端对它们的编辑照收。反例：上衣换成没有选项物件的款式时，`hideOpt` 那列变成 `available:false`；如果这时拒收，卡上存着的值就改不了，换回有那个物件的款式后看到的仍是旧值。原作换款时也只是不显示，值照存。程式注释在 `Tools/ok-extract/src/appearance/model_flags.rs` 开头。
- **衣服选项与袖型实测**（读卡器 parameters＋截图，`Saved/Reports/editor-parity-clothes/shots/`）：KK_007604 服装 1 换成原作上衣 217 セーラーワンピース。截图里看到的：袖型 0 → 1 时领口的蝴蝶结换成长领带（原因见下，**未确认**）；`hideOpt.0`：蓝绿色水手领消失。旗标：颜色层 1～3 可用、第 4 层不可用，选项 1 可用、选项 2 不可用，和 prefab 一致。
  - **袖型组切换的确实是袖子**（CLI 实测，`Saved/Reports/editor-parity-clothes/armcheck/`，`OK_DIAG=1` 导出两次比网格清单）：袖型 0 是短袖 `cf_sode_sailoronep_01` 加扣子 `cf_sode_sailoronep_01_botan`（|x| 到 0.26），袖型 1 是长袖 `cf_sode_sailoronep_02`（|x| 到 0.52，手腕）。两次导出只差这几个网格。（更正：我先前写「这组是领带／蝴蝶结」是错的，那是从截图推的，没有比网格。）
  - **截图上看不出袖子变，是被手套盖住**：这张卡服装 1 的手套（kind 4）是 `o_gloves_magic`，|x| 0.20～0.52，从前臂到手腕。所以三张截图里手臂的长袖与蓝绿袖口都是手套，不是上衣的袖子，也不是配件（手腕的配件槽 16／17 是小爱心 `o_valletta_heart1`）。要在画面上验袖型，先把手套脱掉。
  - 截图 1、2 之间领口从蝴蝶结变长领带：两次 CLI 导出都有同一条领带配件（槽 12 `o_necktie_yure_long`，父骨 `a_n_bust_f`）和蝴蝶结 `cf_top_sailorO_d_ribon`，网格清单没有差别，所以不是袖型组造成的。原因**未确认**（可能是读卡器重载后摆动骨或显示状态不同）。不为它单独开窗口。下次有画面时，顺手查两张截图当下的配件显示旗标（`hideOpt`、各槽是否显示），不必再比网格：两次导出的网格清单相同，所以差别更可能在显不显示，而不在有没有这个物件。
- **要验原作服装功能，先确认那张卡穿的是原作衣服**：KK_007604 原本 7 套的上衣都是 mod 衣服（model 摘要里没有 kind 0），所以原卡上找不到可切换的选项。挑法：`entries.rs` 的忽略测试 `clothes_option_survey` 列出有 `objOpt`／`objSleeves` 的原作衣服，再用 appearance 的 `apply` 换上。和「验头发前先确认 hair0 真的是头发部件」是同一类坑。
- **旧 OK 卡卡内模型没有新查询**：`clothes_option_groups` 是可选查询，卡内的第三方模型转卡时还没有它。`model_flags` 用 `clothes_option_groups_recorded`（`oklib::memo_bytes_recorded`）分辨「没录到」与「合法地全是预设值」：没录到的那件衣服，它的列不标 `available`；有录到的照实标。
- **乾净 clone 对照的已知差异（不是这次补录造成的）**：`kks-verify` 拿原作卡比游戏模式与基础库模式，差在**每个部件**的 `_OKShaderState`、`_OKShaderCull`、`_OKShaderOutline`、`_OKShaderQueue`、`_OKShaderZWrite` 与 `_GlassRamp`：游戏模式从 shader 读出（`unity.rs`），基础库模式（CLI 的 `kks-verify`／`replay`）不套 `shader_states.json`（`shader_states::complete` 只在 `okmodel_view` 与读卡器背景流程呼叫）。从 `ebd5a5329`／`97985fd99` 那条线起就有。完整库与乾净库两边的 live digest 相同、`gaps=0`、`game_reads=0`，所以补录这件的对照算过。
- **`C:\portable\OKGameOnly` 不能当乾净基线**：那是 2026-11-04 只靠游戏还原的快照，比现在的程式少很多查询，拿它比一定不同。乾净对照要用当下 HEAD 的 clone 跑 `original_data.lua restore --game`（本机在 `F:\OKCleanYvonne`，还原跑到一半暂停，等量测让出机器再续跑）。
- **外挂栏位的键是身分式**（`properties/plugins.rs`）：`plugins.<外挂>.<内部路径>`，例如 `plugins.Pushup.a1.@Pushup_BraData.packed.#0.@Firmness`。
  - 第一段是 `PLUGIN_SECTIONS` 的 `id`（`MaterialEditor`、`Pushup`、`KoiClothesOverlayX`…），不是那个区段在这张卡 KKEx 里的位置。位置是每张卡自己的事实：alice 的第 9 个区段是 MaterialEditor，megumin 的是 Pushup。
  - 内部路径：字串键的 map 用 `@<名字>`，整数键的 map（按服装编号）用 `#<数字>`，阵列用 `a<索引>`（阵列项是这张卡自己的条目），解码后的二进位是 `packed`，额外饰品的 XML 是 `xml`。只有键不是字串也不是整数、或字串里有 `.` 时才退回 `m<索引>`，alice 与 megumin 两张卡上都没有出现。
  - 写回时每张卡用名字再查一次位置。这张卡没有那个外挂，就报「這張卡沒有這個模組」，不会退回去写第 N 个区段。测试：`plugin_keys_name_the_plugin_not_its_position`。
  - 「找不到外挂」是**错误**，不是空值，也不是 0：键指名的外挂这张卡没有，`set`／`apply` 就整笔拒绝。拿一张卡的外挂键去改另一张卡时，这正是挡住误写的那一道。
  - 位置式的键（`plugins.m21.a1.m0`）不准外露、不准跨卡复用：MCP 的 `get`／`set`、`pages.json`、文件例子一律用身分式。读卡当下每张卡各解析一次，不缓存跨卡的位置表。
- **`unknown_plugin_sections`**：这张卡 KKEx 里，`PLUGIN_SECTIONS` 没有的区段键（比对原样、不分大小写，不按位置）。认得但没填、卡上没有 KKEx、缺范围都不算。意思是「这个 build 缺支援」，不是卡有问题。读卡器 MCP `state` 另给 `unknown_plugin_sections_status`：
  - `no_card`：没有选卡。
  - `not_read`：这张卡、这套服装的属性还没读，上一张卡留下的清单不显示。
  - `unsupported`：ok-extract 的回覆没有这个栏位，即产生端缺支援。
  - `read`：附 `unknown_plugin_sections` 清单，空清单才是真的 0。

## 9. 第三批（条件显示）：栏位清单与判准（2026-11-19，开工前定稿）

第三批是 UI 依资料端旗标显示或隐藏项目。页面怎么排由 e-fork-2 的 `Config/ReaderEditor/pages.json` 决定。这一节只定资料端：每一列给什么旗标、什么值会被拒。窗口开的时候两边照这份对，不在窗口里临场决定。

### 9.1 三种限制

- **硬界（`limit_min`／`limit_max`，或选项、清单）**：值本身在结构上有界，界外没有意义。会被拒，不夹。
- **软范围（只有 `min`／`max`，界外标 `out_of_range`）**：原作 UI 滑杆的两端。游戏写进卡时不夹，卡上本来就可能有界外的值（ABMX、slider unlocker、外挂改过的卡）。照收、不夹、不拒。
- **没有限制（只检查是有限数）**：原作也没有滑杆，或我们判断不出界线。宁可不写，因为写错的那天不会报错，只会悄悄改坏卡。

### 9.2 衣服

| 键 | 种类 | 限制 | 第三批要用的旗标（资料端） |
|---|---|---|---|
| `clothes{k}`（`parts[k].id`，选图） | 清单项 | 硬：必须是目录里的项目（appearance 选图） | — |
| `sub{200..202,210..212}`（`subPartsId`） | 清单项 | 硬：同上 | 显示：只在上衣 Kind=1（水手服 200–202）或 2（外套 210–212）时显示。资料端给 `model.clothes.0.top_kind`（也在 `model.pages.top_kind`），UI 按它显示 |
| `pattern{k}_{i}`、徽章 1／2 | 清单项 | 硬：同上 | 徽章看 `model.clothes.{k}.emblem[0/1]`，已做 |
| `colorInfo.i.baseColor／patternColor` 分量 | 颜色 | 硬：0..1（结构） | 层可用性看 `available`，已做；初期设定色看 `model.clothes.{k}.default_colors`，已做 |
| `colorInfo.i.tiling.x/y` | 数值 | 软：0..1（显示 0..100%） | 跟着该层的 `available` |
| `colorInfo.i.offset.x/y`、`rotate` | 数值 | 软：0..1，预设 0.5 | 同上 |
| `parts.k.hideOpt.0/1`、`hideBraOpt`、`hideShortsOpt` | 开关 | 结构：bool | `available`（`objOpt01/02`），已做 |
| `parts.0.sleevesType` | 选项 0..2 | 硬：选项以外拒收 | `available`（有 `objSleeves`），已做；`model.clothes.0.sleeves[0..2]` 给哪几种有物件 |
| 下装／胸罩／内裤整页 | 页 | 不限（页内各列照各自的限制） | 显示：`model.pages.bot／bra／shorts`（`false` = 原作不能点）。`bot`：上衣清单 `Coordinate==2`（连身）时关（`ChaControl.notBot`）。`bra`：上衣 `NotBra==1` 时关；水手服（Kind 1）改看子部件 a（`sub200`，没有子部件时看上衣），外套（Kind 2）看子部件 a 或 b（`sub210`／`sub211`），照 `ChangeClothesTop`／`ChangeClothesTopParts` 设 `notBra` 的顺序。`shorts`：胸罩清单 `Coordinate=="2"` 时关（`ChangeClothesBra`）。来源 `CustomChangeClothesMenu.InteractableSetting`：只把页签设成不能点，页内的值照存 |
| 男性胸罩页 | 页 | 不限 | 显示：`model.pages.male_bra`：清单有任何一件胸罩（107）的 `Sex` 不是 3、99 时为 `true`（`CustomBase.IsMaleCoordinateBra`）。原作只在角色是男性时用它（女性永远有胸罩页），所以 UI 要同时看卡的性别 |

### 9.3 配件

| 键 | 种类 | 限制 | 第三批要用的旗标 |
|---|---|---|---|
| `accessory{n}_{type}`（`id`，选图） | 清单项 | 硬：目录项目 | — |
| `type` | 选项 120..130 | 硬 | — |
| `parentKey` | 父骨 | 软：55 键（`editor_accessory_parents.json`）是已知清单，不是限制。清单外的键照收，标 `out_of_range`；只拒控制字元与超过 256 字。**`""` 不是无效值**：它是「素材预设」（用清单的 `Parent`），原作换配件时自己也会写 `""`（`CvsAccessory.UpdateSelectAccessoryKind`），所以不拒也不标（更正：先前写成「硬」是错的，读卡器与资料端本来就收自由输入） | 显示：`model.accessories.{槽}.parent_editable`，同时标在 `parentKey` 与该槽全部 `addMove` 列的 `available`。空槽（type 120）、清单 `HideHair==1` 或 `Parent=="null"` 时为 `false`（`CvsAccessory.ChangeParentAndMoveSettingVisible`，隐藏父骨、初始化／反转父骨与位移第 1 组） |
| `addMove` 位置 | 数值 | 软：−100..100，一位小数 | 显示：第 2 组（`addMove.2.3..5`）另看 `model.accessories.{槽}.move2`：模型有 `N_move2` 节点（`objAcsMove[slot,1] = FindLoop("N_move2")`）才为 `true`。`null` = 这个模型录的时候还没存配件的节点名（2026-11-19 前的基础库与 OK 卡），那几列不标，等重录 |
| `addMove` 旋转 | 数值 | wrap 0..360，取整；永远不拒，也不标 `out_of_range` | 同上 |
| `addMove` 缩放 | 数值 | 软：0.01..100，两位小数。原作输入框不收 0 和负值，但卡上可能有（外挂写的）。照收，不另写 `limit_*` | 同上 |
| `color[0..3]` 分量 | 颜色 | 硬：0..1 | `available`（`useColor01..03`、`rendAlpha`），已做 |
| `hideCategory` | 选项 0..1 | 硬 | 原作只在 `Game.isAddH` 时显示，我们照常显示 |
| `noShake` | 开关 | bool | — |

### 9.4 外挂栏位、身体与脸部

- 外挂栏位（`plugins.<id>.…`）：没有范围中继资料就只检查有限数；颜色依结构 0..1。键是身分式（§8）。
- `shape.*`：软 0..1，不写 `limit_*`（e-cardload 的身体脸部文件第三之二节）。

### 9.5 `available:false` 的列

已提升成软限制的一般规则，写在 §8「现在看不到不构成写入限制」。这一节的旗标全部只影响显示，没有一个影响写入。

### 9.6 资料端完成状态（2026-11-19）

- 四个旗标都由 `appearance` 输出（`model_flags.rs`）：`model.pages`（衣服页）、`model.accessories.{槽}.parent_editable／move2`。语意都来自反编译（`ChaControl.cs`、`CustomChangeClothesMenu`、`CustomBase`、`CvsAccessory`），不是从截图推的。
- `move2` 要配件模型的节点名。转换器从这版起对配件也录 `prefab_node_names`（`oklib_convert.rs`）。旧基础库与旧 OK 卡没录到，查询走 `prefab_node_names_recorded`，回 `None`，不猜。要让它有值，基础库得重录配件那一批，这件排在 e-fork-2 的重录之后。

## 10. 第四批盘点：原作衣服／配件编辑器还没接的栏位（2026-11-19）

依原作 UI 的分页逐页对。语意来源：反编译 `D:\XKoikatuSunshine\kks_decomp\Assembly-CSharp\ChaCustom\`（`CvsClothes`、`CvsClothesCopy`、`CvsAccessory`、`CustomAcsMoveWindow`、`CustomAcsParentWindow`、`CvsAccessoryChange`、`CvsAccessoryCopy`、`CustomChangeClothesMenu`）和卡结构 `ChaFileClothes`／`ChaFileAccessory`，不是从截图推的。我们这边看的是 `properties.rs`／`appearance.rs` 与 E 树 `Config/ReaderEditor/pages.json`（`1c5dfbea7`）。

先说结论：卡上的衣服／配件栏位，资料端**全部都有**（`ChaFileClothes.PartsInfo` 的 7 个栏位、`ColorInfo` 的 6 个栏位、`subPartsId`／`hideBraOpt`／`hideShortsOpt`，以及 `ChaFileAccessory.PartsInfo` 的 7 个存档栏位）。界面也都能改，但只是「颜色与设定」「饰品颜色与位置」两页的通用列表，没有原作那样逐页排版。还缺的分三类：**原作的「操作」**（重设、复制、左右反转）、**换款时原作会顺手改的栏位**、**只属于原作游戏或编辑器自己的东西**。

### 10.1 栏位怎么分

- **A. 资料端有、界面没专用控件**：e-fork-2 的页面工作。资料端已能读能写，原作的排法、显示条件由 UI 照第三批旗标去做。
- **B. 资料端没有**：我的。要新的输出或新的写入操作。
- **C. 原作有、我们刻意不做**：另列理由，不算「还没做」。

限制栏照 §9.1：硬界／软范围／不限。「—」表示这一列是操作或页，本身没有值。

### 10.2 衣服（`CvsClothes`，每个衣服种类一页）

| 原作控件 | 我们的参数 | 资料端 | 界面 | 限制 | 归类 |
|---|---|---|---|---|---|
| 种类选图 `customClothes` | `clothes{k}`（`parts[k].id`） | 有（appearance 选图） | 有（外观选择） | 硬：目录项目 | — |
| 水手服／外套子部件 `customSailor01..03`／`customJacket01..03` | `sub200..202`／`sub210..212`（`subPartsId`） | 有 | 有（外观选择）；按 `top_kind` 显示的条件还没接 | 硬：目录项目 | A |
| 袖型 `tglSleevesType[3]` | `clothes.parts.0.sleevesType` | 有，`available` 与 `model.clothes.0.sleeves` 已有 | 通用列（数字），不是三选一按钮 | 硬：0..2 | A |
| 选项开关 `tglOption[2]` | `clothes.parts.k.hideOpt.0/1`、胸罩页 `hideBraOpt`、内裤页 `hideShortsOpt` | 有，`available` 已有 | 通用列 | 结构：bool | A |
| 颜色 1..4 `btnMainColor01..04` | `clothes.parts.k.colorInfo.i.baseColor.*` | 有，`available`、`default` 已有 | 通用列（分量），没有色票窗口 | 硬：0..1 | A |
| 花纹选图 `customPtn01..04` | `pattern{k}_{i}`（`colorInfo.i.pattern`） | 有 | 有（外观选择） | 硬：目录项目 | — |
| 花纹颜色 `btnPtnColor01..04` | `colorInfo.i.patternColor.*` | 有 | 通用列 | 硬：0..1 | A |
| 花纹位置 X／Y `sldPtn0?OffsetX/Y` | `colorInfo.i.offset.x/y` | 有 | 通用列 | 软：0..1 | A |
| 花纹旋转 `sldPtn0?Rotate` | `colorInfo.i.rotate` | 有 | 通用列 | 软：0..1 | A |
| 花纹宽／高 `sldPtn0?Width/Height` | `colorInfo.i.tiling.x/y` | 有 | 通用列 | 软：0..1 | A |
| 花纹设定区只在选了花纹时显示（`objPtnSetting0?`） | 由 `colorInfo.i.pattern != 0` 判断 | 有（值本身） | 没接 | 不限（只影响显示） | A |
| 每条滑杆旁的重设钮 `btnPtn0?OffsetX…Height` | — | 预设值：位置／旋转 0.5、宽高 0（原作 `ChaFileClothes.ColorInfo.MemberInit`）。范围中继资料没有专给「重设」用的预设 | 没有 | — | A（预设值写死在 UI 也行，原作也是写死的） |
| 徽章 1／2 `customEmblem[2]` | `emblem{k}_{n}`（`emblemeId`／`emblemeId2`） | 有，可用性 `model.clothes.k.emblem` 已有 | 有（外观选择）；显示条件没接 | 硬：目录项目 | A |
| **初期设定钮 `btnInitSetting`**：4 层底色改回模型预设色、花纹色改白、花纹归 0，位置／旋转归 0.5、宽高归 0 | 底色预设已有（`model.clothes.k.default_colors`） | 预设值有，但没有一次写回的操作 | 没有 | — | A：UI 照上面的值组一次 `set` 就行，不需要新 API |
| **换上衣时袖型归 0**（`UpdateSelectClothes`：`sleevesType = 0`） | `clothes.parts.0.sleevesType` | **没有**：appearance `apply` 只写 `id` | — | — | **B**：`apply` 换上衣时同时写 `sleevesType=0`，照原作 |
| 换上衣时子部件回补（`ChaControl.ChangeClothesTop`：子部件 id 不在新种类的清单里时，读 `topPartsDefaultId`，再写回 `subPartsId`） | `sub200..212` | **查到了，原作会写回卡**：`CvsClothes.UpdateSelectClothes`（top）先 `FuncUpdateClothesTop` → `ChaControl.ChangeClothesTop`，把执行期的 `nowCoordinate.clothes.subPartsId` 定下来；接着 `setClothes.subPartsId[i] = clothes.subPartsId[i]`，`setClothes` 就是 `chaFile.coordinate[coordinateType].clothes`。定法（`ChangeClothesTopParts`）：新上衣的 Kind 不是 1／2（或没有上衣物件）→ 三格都写 0；是的话，每格查 `(Kind==1?200:210)+格`，查不到就用 `topPartsDefaultId`（水手服 0,0,1；外套 0,1,1，`LoadCharaFbxData` 的 `defaultId`），写入查到的 `Id`。只读卡不换衣服时只改 `nowCoordinate`，不写卡。**已写（尚未编译）**：`appearance.rs` `apply_item` → `settle_top_sub_parts`，规则在纯函式 `top_sub_parts_plan`。目录从 `apply` 传进来；「查得到」与 `current_selection` 用同一套判断（slot／local slot 加 GUID）。每格的写入走 `patch`，mod 子部件的 resolve 列就跟着处理：改成原作 id 的格移除它的列，保留的格列不动。只在上衣真的换了时才做；重套同一件上衣，输出和只写 `id` 的 `patch` 逐位元组相同（测试 `reapplying_the_worn_top_writes_nothing_more`，需要游戏目录与本机卡）。规则测试：`top_sub_parts_follow_change_clothes_top_parts`。**待补**：「子部件查不到、用 `topPartsDefaultId`」这条，还没有用真实 mod 上衣的案例。手边没找到「mod 水手服／外套带着新种类清单里没有的子部件」的卡，不用捏造的资料凑；找到卡再补。另一个原作条件「上衣物件没载入（`objClothes[0]==null`）时也写 0」我们判断不到，不做 | — | — | **B（写入）** |
| 衣服复制页 `CvsClothesCopy`（从另一套服装复制选定种类；子部件可分开勾） | — | 没有专用操作；读别的服装＋`set` 可以组出来 | 没有 | — | B（低优先：可由 UI 组合） |
| 页签可点与否（`notBot`／`notBra`／`notShorts`、男性胸罩页） | `model.pages` | 有（第三批） | 没接 | 不限（只影响显示） | A |

### 10.3 配件（`CvsAccessory`，每个槽一页）

| 原作控件 | 我们的参数 | 资料端 | 界面 | 限制 | 归类 |
|---|---|---|---|---|---|
| 种类下拉 `ddAcsType`（含「无」= 120） | `accessory.parts.n.type` | 有（选图时一起写；选空 = 120） | 有（外观选择） | 硬：120..130 | — |
| 配件选图 `tglAcsKind` | `accessory{n}_{cat}`（`id`） | 有 | 有 | 硬：目录项目 | — |
| 颜色 1..4 `btnAcsColor01..04` | `accessory.parts.n.color.c.*` | 有，`available`（`useColor`、`rendAlpha`）已有 | 通用列 | 硬：0..1 | A |
| **颜色初期化 `btnInitColor`**（改回 `ChaAccessoryComponent.defColor01..04`） | — | **没有**：配件的预设色没输出（衣服有 `default_colors`，配件没有） | 没有 | — | **B**：`model.accessories.n` 补 `default_colors` |
| 父骨 `tglAcsParent` → 父骨视窗 `CustomAcsParentWindow` | `accessory.parts.n.parentKey` | 有，自由输入加 55 键选单（`editor_accessory_parents.json`），`parent_editable` 已有；清单外的键标 `out_of_range` | 通用列（输入框＋选单） | 软：清单外照收；`""` 是素材预设，不是无效值，不拒不标 | A |
| **父骨初期化 `btnInitParent`**（`parentKey=""`，用清单 `Parent`） | `parentKey` | 值 `""` 在选项里（「素材预设」） | 没有专用钮 | — | A |
| **父骨左右反转 `btnReverseParent`** | `parentKey` | **没有左右对应表**。命名不规则，例如 `a_n_hair_pin` ↔ `a_n_hair_pin_R`，UI 不能只换 `_L`／`_R` | 没有 | — | **B**：父骨表补 `reverse` 栏，照原作 `ChaAccessoryDefine.GetReverseParent` 的对应 |
| 位移第 1／2 组 `tglAcsMove01/02` → `CustomAcsMoveWindow`：位置／旋转／缩放 XYZ 输入 | `accessory.parts.n.addMove.2.{0..5}.{x,y,z}` | 有，`parent_editable`／`move2` 已有 | 通用列 | 位置 软 −100..100；旋转 wrap 0..360；缩放 软 0.01..100 | A |
| 位移视窗的步进切换 `tglPosRate`／`tglRotRate`／`tglSclRate`（0.1／1／10） | — | 不需要 | 没有 | — | A（纯 UI） |
| 位移视窗的重设钮（单项与 `btnAllReset`）、复制／贴上 `btnCopy`／`btnPaste` | — | 预设值：位置／旋转 0、缩放 1 | 没有 | — | A（纯 UI） |
| H 时分组 `tglAcsGroup`（主／副） | `accessory.parts.n.hideCategory` | 有 | 通用列（选项） | 硬：0..1 | A。原作只在 `Game.isAddH` 时显示，我们照常显示（§9.3） |
| 停止摆动 `tglNoShake` | `accessory.parts.n.noShake` | 有 | 通用列 | bool | A |
| 换配件时继承父骨／颜色 `tglTakeOverParent`／`tglTakeOverColor`（编辑器设定，不进卡，预设都是开） | — | 我们 `apply` 换配件时保留 `parentKey` 与颜色，等于两个都开 | 没有开关 | — | 有一处 **B**：原作在新配件 `HideHair==1` 时，不管开关都把 `parentKey` 清成 `""`（`UpdateSelectAccessoryKind`），我们没做。开关本身算 C（编辑器偏好，不进卡），见 10.4 |
| 3D 拖曳控制器 `tglDrawController01/02`、`tglControllerType`、`sldControllerScale`／`Speed` | — | 不需要 | 没有 | — | C（见 10.4） |
| 槽位互换／复制 `CvsAccessoryChange`（`btnSlotCopy`；复制位移值，可左右或上下反转 `btnCopyRevValueLR/UD`） | — | 没有专用操作。互换可由 UI 读两槽再写；左右反转要父骨对应表（同上） | 没有 | — | B（低优先，依赖父骨反转表） |
| 从别套服装复制配件 `CvsAccessoryCopy` | — | 没有专用操作，同衣服复制 | 没有 | — | B（低优先） |
| 第 21 槽以后（MoreAccessories） | `accessory_extra`、`plugins.…` | 有 | 有（新增饰品栏位） | 同上 | — |

### 10.4 刻意不做

| 原作项目 | 理由 |
|---|---|
| `ChaFileAccessory.PartsInfo.partsOfHead` | `[IgnoreMember]`，执行时才算，不进卡 |
| 换配件时继承父骨／颜色的开关（`customSettingSave.acsTakeOverParent/Color`） | 原作编辑器自己的偏好，不进卡。我们固定为原作预设（都开）。若 UI 要做这个开关，资料端只需要在 `apply` 加一个参数 |
| 3D 拖曳控制器（显示、种类、大小、速度） | 原作视窗内的操作手把。读卡器的 3D 预览没有同样的拖曳框架，数值改动走位移列。要做是 UI／视窗工作，不是栏位 |
| `hideCategory` 只在 `Game.isAddH` 时显示 | 原作游戏进度条件，读卡器没有游戏进度，照常显示 |
| `CvsDrawCtrl`（穿着状态预览、姿势、背景等） | 只影响预览、不进卡。我们的「穿着状态」抽屉已经涵盖衣服部分 |

### 10.5 外挂（2026-11-19 盘点）

语意来源：反编译 `D:\XKoikatuSunshine\kks_decomp\plugins\` 下各外挂自己的存档程式（`OnCardBeingSaved`／`OnCoordinateBeingSaved`）。我们这边看的是 `Tools/ok-extract/src/appearance/properties/plugins.rs`（`PLUGIN_SECTIONS`、`visit()`）与读卡算图那一侧（`card.rs`、`card_plugins.rs`）。

**先讲共通的两件事：**

- **界面**：外挂列全在「全部属性」（`pages.json` 的 `property_panel`），没有专用页，所以下表每个外挂的界面都是 A（e-fork-2 的排版工作），表里不再逐列写。
- **资料端只露出一部分栏位**，取舍由 `visit()` 决定：
  - 会露出：浮点数（`F32`／`F64`）、布林、颜色（四个浮点），以及 MoreAccessories 的 XML 字串。
  - **露不出**：整数、一般字串、PNG／`byte[]`。键名含 `texture` 与结尾是 `Original` 的栏位，`visit()` 刻意跳过。
  - 这条规则让几个外挂的主要数值没有列可改，见下表标 **B** 的地方。
  - 「露不露出」是照 `visit()` 规则对外挂存档型别推出来的，还没有逐个外挂拿真卡核对过。

限制一律照 §9.1：外挂没有给范围中继资料的，只检查有限数（「不限」）；颜色依结构 0..1。

| 外挂（区段键，按身分） | 存在哪里 | 栏位 | 资料端 | 算图 | 限制 | 分类 |
|---|---|---|---|---|---|---|
| **MaterialEditor**（`com.deathweasel.bepinex.materialeditor`） | 角色卡＋服装卡；一个区段装全部服装，`CoordinateIndex` 分开 | `MaterialColorPropertyList`（`Value` 是 Color） | 有（颜色列；只露出当前服装的衣服与饰品列，`visit()` 第 76 行） | 有 | 硬：颜色 0..1 | A |
| 同上 | 同上 | `MaterialFloatPropertyList`（`Value` 存成**字串**） | **没有**：字串不露出 | 有 | 原作滑杆预设 0..1，shader 的 `Range` 属性会改写 → 软 | **B** |
| 同上 | 同上 | `MaterialKeywordPropertyList`（`Value` bool） | 有 | 待查 | bool | A |
| 同上 | 同上 | `RendererPropertyList`（`Value` 字串：Enabled／ShadowCastingMode／ReceiveShadows／RecalculateNormals） | **没有** | 有（渲染器开关） | 硬：列举值 | **B** |
| 同上 | 同上 | `MaterialShaderList`（`ShaderName` 字串、`RenderQueue` int?） | **没有** | 有（shader 家族） | 硬：shader 名单；RenderQueue 整数 | **B**（低优先：换 shader 牵涉材质重建） |
| 同上 | 同上 | `MaterialTexturePropertyList`＋`TextureDictionary`（贴图、偏移、缩放） | **已由 f-sceneload 覆盖**（`7ecd947ff`／`3af999058`／`fe5d80d11`，`appearance/textures.rs`，另开动作，不走 `plugins.*`） | 有 | — | 不重做 |
| 同上 | 同上 | `MaterialCopyList`（材质复本） | 没有 | 待查 | — | C：会多出一个材质槽，是结构编辑，不是数值；读卡器照卡原样保留 |
| **KoiSkinOverlayX**（`KSOX`，v2） | 只在角色卡；里面按服装分 | `Lookup`（服装 → 贴图种类 → 贴图 id）＋ `_TextureID_<n>`（PNG） | **没有**：贴图不是属性值 | 有（身体／脸／眼的覆盖贴图） | — | **B**：要像 MaterialEditor 贴图那样另开一个换图动作，与 f-sceneload 的贴图动作同一套做法，做之前先和它对齐 |
| 同上 | 同上 | `EnableInStudioSkin`／`EnableInStudioIris`（只在 false 时写） | 有（bool） | — | bool | C：只影响 Studio |
| **KoiClothesOverlayX**（`KCOX`） | 角色卡（按服装分）＋服装卡 | `Overlays`：衣服物件名或遮罩名（`BodyMask`／`InnerMask`／`BraMask`）→ `[PNG, Override]` | `Override`（bool）有；PNG 没有 | 有；换上衣时一起清掉上衣的覆盖与遮罩（`properties.rs` 约 258 行） | bool | 贴图 **B**（同 KSOX）；`Override` A |
| 同上 | 同上 | `EnableInStudio` | 有 | — | bool | C：只影响 Studio |
| **Pushup**（`com.deathweasel.bepinex.pushup`） | 角色卡：`Pushup_BraData`／`Pushup_TopData`（以服装号为键）、`Pushup_BodyData`；服装卡：`PushupCoordinate_*` | `ClothData`：Firmness／Lift／PushTogether／Squeeze／CenterNipples（浮点）、EnablePushup／FlattenNipples／UseAdvanced（bool）、进阶 12 项身体值 | 有（浮点与 bool；键用 `#<服装号>`） | 有（`card.rs` `apply_pushup_shape`） | 基本五项：原作滑杆 0..1，软；进阶 12 项：滑杆 −1..2，软；没有范围中继资料时只检查有限数 | A；范围中继资料可补（B，低优先） |
| 同上 | 同上 | `Pushup_BodyData`（没推挤前的身体） | 有 | 有 | 软 | C：**不该给人改**。它是原作 `shape.*` 的备份，改了会和身体滑杆打架；同一笔资料两个地方能改，正是 ABMX 不进 `plugins.*` 的理由。写入端要挡，**B**：把它标成 `supported:false`（同 `refuse_unapplied`） |
| **HairAccessoryCustomizer**（`com.deathweasel.bepinex.hairaccessorycustomizer`） | 角色卡 `HairAccessories`（服装 → 饰品栏）；服装卡 `CoordinateHairAccessories` | HairGloss、ColorMatch（bool）；OutlineColor、AccessoryColor、GlossColor（颜色）；HairLength（浮点） | 有 | 有 | 颜色硬 0..1；HairLength 原作 0..1，软 | A。只对有 `ChaCustomHairComponent` 的饰品有效，可用性可从 `model.accessories` 的 `use_color` 那份资料推，UI 要时再补旗标 |
| **MoreAccessories**（`moreAccessories`，v2） | 第 21 栏以后其实存在原作的 `accessory.parts` 阵列（超过 20 个）；`additionalAccessories` 是旧版相容用的 XML 副本 | XML 里每栏：type、id、parentKey、addMove、color、hideCategory、noShake | 有（`accessory_extra`，XML 列） | 有 | 同原作配件（§9.3） | A。**待查**：v2 卡的真资料在 `parts[20..]`，XML 只是副本。我们改的是 XML 那份，要确认原作读 v2 卡时以 `parts` 为准、不读 XML（反编译 `MoreAccessories.cs` 426–485：v2 忽略 XML），否则我们改了也不会生效 → 可能是 **B** |
| 同上 | 同上 | `ShowAccessories`（bool[]） | 有 | — | bool | C：只在 Studio 写 |
| **Accessory States**（`Accessory_States`，v1） | 角色卡 `CoordinateData`（以服装号为键）＋服装卡 | 每个饰品栏：`_binding`（int：0–8 衣服种类，9 以上自订组）、`_state`（`[开始,结束]` 整数区间）、`_shoetype`（byte）、`_parented`（bool）；组名 `_names`（字串） | 只有 `_parented`；**其余都是整数或字串，没露出** | 有（`card_plugins.rs`） | `_binding` 硬（列举）；`_state` 硬 0..3（衣服）或组的最大值 | **B**（原作 UI 是一个下拉加两个 0..3 滑杆，资料端要能露出整数列） |
| **AccessoryStateSync**（`madevil.kk.ass`，v6） | 角色卡 | `TriggerPropertyList`／`TriggerGroupList` | 部分 | 有 | — | C：Accessory States 存档时会**从自己的资料重写**这份相容副本（`CharaEvent.cs` 568–614），单独改它，下次存档就被盖掉。以 `Accessory_States` 为准 |

**其他会影响衣服／饰品的外挂**（这次没展开，只列区段键，都还不在 `PLUGIN_SECTIONS`，会出现在 `unknown_plugin_sections`）：

- `com.deathweasel.bepinex.clothingunlocker`：`ClothingUnlocked`。
- `com.deathweasel.bepinex.moreoutfits`：`CoordinateNames`，服装名，字串。
- `KK_InvisibleBody`：`Visible`。
- `nakay.kk.ClothingBlendShape`：`ClothesDataSet`。已在 `card_plugins.rs` 算图，属性端没有。
- `com.deathweasel.bepinex.dynamicboneeditor`：已在 `PLUGIN_SECTIONS`，`AccessoryDynamicBoneData` 是浮点列。

**两件和先前写法不一致、要更正或核对的**：

- `KKS_MoreAccessoryParents` 反编译里**没有卡资料**：它加的父骨直接以字串写进原作的 `parentKey`。这正是 §10.3 改成软限制要放行的情形。
- `PLUGIN_SECTIONS` 有一列 `HairShadowColorControl`（标「source」），但反编译里这个外挂**找不到卡资料**。那一列可能是空设定，要找一张真卡确认，不要凭推测删。

**B 类（资料端，我的），照优先：**

1. 让 `visit()` 露出整数，以及有已知型别的字串列：Accessory States 的绑定与区间、MaterialEditor 的浮点（字串存）与渲染器开关。照 §8 的身分式键，限制照上表。**已写**（`plugins.rs` `int_spec`／`visit_with`，测试 `known_integer_and_string_fields_are_offered_with_their_type`，尚未编译）：
   - 整数只露出白名单。Accessory States 的 `_binding`：硬 −1..max(8, 卡上值)；卡自己的自订组照样合法，但不在这里凭空开新组。`_state` 的每个端点：衣服绑定时硬 0..3，自订组时 0..max(3, 卡上值)。`_shoetype`：硬 0..2。MaterialEditor `RenderQueue`：硬 −1..5000。其他整数是身分（`ObjectType`、`CoordinateIndex`、`Slot`、贴图 id、列举的 `Property`），改了会把整列挪到别的物件上，所以不露出。
   - 字串只露出 MaterialEditor 的 `Value`：内容是数字的当数字列，`True`／`False` 当布林列，不给自由打字。写回时保持字串（`replace` 照原型别转）。ShadowCastingMode 那种列举字串（`Off`／`On`…）还没露出。
2. `Pushup_BodyData` 标 `supported:false`：它只是身体滑杆的备份，不能有第二个修改入口。**已写**（`properties.rs` `refuse_unapplied`，原因文字 id `reader.unsupported.pushup_body_backup`，测试 `pushup_body_backup_is_offered_but_not_editable`）：挡写不挡读，列照样列出来（它是诊断用的事实，也可以看备份值是多少），MCP 的 `set` 回「Parameter unsupported」；尚未编译。**这个入口在 2026-11-19 之前是开着的**（`plugins.Pushup.@Pushup_BodyData…` 可写）。已经从这里改过的卡不迁移、不自动修；那样的卡，Pushup 会用改过的备份重算身体。
3. **未确认，不动程式**：MoreAccessories v2 的 XML 副本改了有没有效。要等有画面时用真卡核对（清单交给 f-sceneload 的拍照窗口）；若无效，就是 `extra.rs` 改错了地方，改成编辑 `parts[20..]`。`HairShadowColorControl` 那一列同样**未确认**，不删。
4. KSOX／KCOX 换图：和 f-sceneload 的贴图动作对齐后另开动作。
5. 低优先：Pushup 范围中继资料；MaterialEditor 换 shader。

### 10.6 我接下来要做的（B 类，照优先）

1. `apply` 换上衣时写 `sleevesType=0`；换配件时，新配件 `HideHair==1` 就把 `parentKey` 清成 `""`。都照原作的 `UpdateSelect…Kind`。**已写**（`appearance.rs` `coordinate`）：只在 id 真的换了时才改，重套同一个 id 不动，所以 `verify` 照样幂等。测试 `new_top_starts_at_sleeve_zero_and_hide_hair_accessory_drops_parent`，尚未编译。
2. `model.accessories.n.default_colors`（`defColor01..04`），给「颜色初期化」用。**已写**：不能直接在 `AccessoryColorUse` 加栏位（查询结果以 bincode 存进 `.okmodel`，加了栏位，所有已录的模型都会读不回来），所以另开 `accessory_default_colors` 查询（`unity.rs`，与 `accessory_color_use` 用同一套子树对应；`_recorded` 没录到回 `None`），转换器两处都录。只放在 `model.accessories.n.default_colors`，**不**写进各列的 `default`：读卡永远不拿它补值，否则没设过色的卡读出来会像被改过。旧库要对 ao_ 来源再补录一次才有值；e-fork-2 这次窗口的补录，exe 若含这笔就一起录到。尚未编译。
3. 父骨表补 `reverse` 对应（照原作 `ChaAccessoryDefine.GetReverseParent`），给「父骨左右反转」与「左右反转复制」用。**已写**：`Tools/ok-extract/data/editor_accessory_parents.json` 的 18 对共 36 列加了 `reverse`，没有对应的列不加（原作 `_ => ""`，反转钮不显示）。随 `properties` 的 `parents` 输出。测试 `accessory_parent_reverse_pairs_are_symmetric`，尚未编译。
4. 换上衣时子部件回补：查到原作会写回卡，**已写**（出处、做法与待补的 mod 案例见 10.2 那一列），尚未编译。
5. （低优先）服装间复制衣服、复制配件、槽位互换：UI 先用「读别套＋`set`」组合；要不要专用操作，等 UI 做过再说。
6. 外挂父骨键：**已改**。55 键是已知清单不是限制，清单外的键照收、标 `out_of_range`（`mark_unknown_parents`，测试 `parent_outside_the_known_list_is_marked_not_refused`）。`""` 照收不标：它是「素材预设」，原作 `UpdateSelectAccessoryKind` 也会写 `""`，不能当成空值拒。

### 10.7 写入行为与显示旗标分开看

- **只影响显示**（第三批，§9.6）：`model.pages`、`parent_editable`、`move2`、各列 `available`。它们不改卡，也不挡写入。
- **写入行为**（这批，会改卡上的栏位）：`apply` 换上衣时 `sleevesType=0`；换上 `HideHair==1` 的配件时 `parentKey=""`；换上衣时 `subPartsId` 写回定好的值（`ChangeClothesTopParts` 的定法）。出处都是 `UpdateSelectClothes`／`UpdateSelectAccessoryKind`，只在 id 真的换了时才发生。
- **重设用的值**（不改卡，等 UI 按钮用）：衣服 `default_colors`、配件 `default_colors`、父骨 `reverse`。
