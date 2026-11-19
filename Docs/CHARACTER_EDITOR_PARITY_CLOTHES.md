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
- **衣服选项与袖型实测**（读卡器 parameters＋截图，`Saved/Reports/editor-parity-clothes/shots/`）：KK_007604 服装 1 换成原作上衣 217 セーラーワンピース。袖型 0 → 1：领口的蝴蝶结换成长领带；`hideOpt.0`：蓝绿色水手领消失。旗标：颜色层 1～3 可用、第 4 层不可用，选项 1 可用、选项 2 不可用，和 prefab 一致。
  - **`objSleeves` 不等于袖长**。它是 prefab 里一组随袖型切换的物件，内容由 prefab 决定。セーラーワンピース的这组是领带／蝴蝶结，所以切袖型时画面上变的是领口。拿这件验袖型、看到领口在变，是对的。
  - 三张截图里手臂的长袖与蓝绿袖口都没变。是不是卡上的手臂配件盖住了上衣本身的袖子：**未确认**。
- **要验原作服装功能，先确认那张卡穿的是原作衣服**：KK_007604 原本 7 套的上衣都是 mod 衣服（model 摘要里没有 kind 0），所以原卡上找不到可切换的选项。挑法：`entries.rs` 的忽略测试 `clothes_option_survey` 列出有 `objOpt`／`objSleeves` 的原作衣服，再用 appearance 的 `apply` 换上。和「验头发前先确认 hair0 真的是头发部件」是同一类坑。
- **旧 OK 卡卡内模型没有新查询**：`clothes_option_groups` 是可选查询，卡内的第三方模型转卡时还没有它。`model_flags` 用 `clothes_option_groups_recorded`（`oklib::memo_bytes_recorded`）分辨「没录到」与「合法地全是预设值」：没录到的那件衣服，它的列不标 `available`；有录到的照实标。
- **乾净 clone 对照的已知差异（不是这次补录造成的）**：`kks-verify` 拿原作卡比游戏模式与基础库模式，差在**每个部件**的 `_OKShaderState`、`_OKShaderCull`、`_OKShaderOutline`、`_OKShaderQueue`、`_OKShaderZWrite` 与 `_GlassRamp`：游戏模式从 shader 读出（`unity.rs`），基础库模式（CLI 的 `kks-verify`／`replay`）不套 `shader_states.json`（`shader_states::complete` 只在 `okmodel_view` 与读卡器背景流程呼叫）。从 `ebd5a5329`／`97985fd99` 那条线起就有。完整库与乾净库两边的 live digest 相同、`gaps=0`、`game_reads=0`，所以补录这件的对照算过。
- **`C:\portable\OKGameOnly` 不能当乾净基线**：那是 2026-11-04 只靠游戏还原的快照，比现在的程式少很多查询，拿它比一定不同。乾净对照要用当下 HEAD 的 clone 跑 `original_data.lua restore --game`（本机在 `F:\OKCleanYvonne`，还原跑到一半暂停，等量测让出机器再续跑）。
