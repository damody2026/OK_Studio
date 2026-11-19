# 人物编辑器对齐原作：盘点与缺口清单

目标（使用者 2026-11-19 交办）：读卡器的人物编辑器参考原作程式码，**把所有细项功能都加上去**。
这份文件是**盘点**，不是实作纪录：先把「全部」有多大讲清楚，才知道缺什么、按什么顺序补。

**细项盘点已经分成三份平行做**（2026-11-19 分工，这一份只留整体骨架）：身体与脸部 [CHARACTER_EDITOR_PARITY_BODY_FACE.md](CHARACTER_EDITOR_PARITY_BODY_FACE.md)（E 树，已交）、衣服与配件 `CHARACTER_EDITOR_PARITY_CLOTHES.md`（F 树）、头发与眼睛细节与外挂栏位 `CHARACTER_EDITOR_PARITY_HAIR_EYES.md`（F 树）。三份格式相同，可以合成总表。

**这一轮交的是分页与分类层级的骨架**（第二、三、四节），细项逐项的清单留给后续几轮（第六节列了顺序）。
每一格的「我们有没有」是**读我们自己的程式码判的初判，还没有逐项实测**，标注在每一节里。

## 一、来源与方法

原作程式码在本机 `D:\XKoikatuSunshine\kks_decomp`（**注意是 `XKoikatuSunshine`**，不是 `KoikatuSunshine`；
AGENTS.md／README 写的游戏路径只是范例，实际路径是本机设定）。编辑器的程式在
`Assembly-CSharp/ChaCustom/`（84 个档案）。**原作程式码与它的截图都不进版控**，这份文件只记结构与项目名。

这一轮的数字是这样得到的，任何人都可以重新算一次：

| 要什么 | 怎么算 |
|---|---|
| 有哪些分页 | `CustomChangeMainMenu.cs` 的 `[SerializeField]` 子选单（7 个） |
| 有哪些分类 | `CustomBase.cs` 的 `updateCvs*` 旗标（**48 个**），对应 `ChaCustom/Cvs*.cs` |
| 每个分类几个滑杆／开关／下拉 | 数那个 `Cvs*.cs` 里的 `private Slider sld*`／`Toggle tgl*`／`Dropdown` |
| 有哪些颜色项 | `CvsColor.cs` 的 `enum ConnectColorKind`（**266 项**） |
| 身体／脸部滑杆各几项 | `cf_custombody.txt`／`cf_customhead.txt` 第一栏的最大索引（**44** 与 **52**） |

我们这边对照的是：`OKCharacterMCPRegistry::Parameters()`（语义参数：`shape.*`／`bone.*`／`physics.*`／
`pregnancy.*`／`style.*` ＋ properties）、`Tools/ok-extract/src/appearance.rs` 的 `targets()`（选图类目标）、
以及读卡器画面上的控制项（e-fork-2 的控制稽核表：旧版 4877 项、新版镜像 4866＋1）。

## 二、分页骨架（7 个）

| # | 原作分页 | 子选单类别 | 分类数 | 我们现在 |
|---|---|---|---|---|
| 1 | 顔（脸） | `CustomChangeFaceMenu` | 12 | 大部分有 |
| 2 | 体（身体） | `CustomChangeBodyMenu` | 11 | 大部分有 |
| 3 | 髪（头发） | `CustomChangeHairMenu` | 5（4 槽＋共通） | 部分 |
| 4 | 服（服装） | `CustomChangeClothesMenu` | 10（9 槽＋复制） | 部分 |
| 5 | アクセサリ（饰品） | `CustomAcsChangeSlot` | 20 槽＋变更／复制 | 部分 |
| 6 | パラメータ（参数） | `CustomChangeParameterMenu` | 7 | **几乎没有** |
| 7 | システム（系统） | `CustomChangeSystemMenu` | 1（`CvsConfig`）＋存读档 | 不适用／部分 |

## 三、每个分页的分类与规模

数字是**原作那个分类里的 UI 元件数**（滑杆／开关／下拉），颜色项另计在第四节。
「我们」栏是初判：**已有**＝资料端读得到也改得动；**部分**＝读得到但改不全或只有一部分项；**没有**＝资料端没有。

### 1. 顔（`CustomChangeFaceMenu`，12 个分类）

| 分类 | 原作类别 | 滑杆 | 开关 | 我们 | 备注 |
|---|---|---:|---:|---|---|
| 顔全体 | `CvsFaceAll` | 7 | 2 | 部分 | 脸型选图有；轮廓类滑杆要逐项核 |
| 耳 | `CvsEar` | 5 | 0 | 部分 | 属 52 项脸部滑杆的一部分 |
| あご（下巴） | `CvsChin` | 8 | 0 | 部分 | 同上 |
| 頬（脸颊） | `CvsCheek` | 6 | 0 | 部分 | 同上 |
| 眉 | `CvsEyebrow` | 5 | 1 | **已有** | `appearance_page page=eyebrow` ＋ 颜色 |
| 目① | `CvsEye01` | 14 | 2 | **已有** | `eye_page page=eyes` 的 14 项 |
| 目② | `CvsEye02` | 11 | 5 | **已有** | 瞳孔／白目／高光／眼线，`eye_overlays` |
| 鼻 | `CvsNose` | 3 | 1 | 部分 | |
| 口 | `CvsMouth` | 7 | 2 | 部分 | |
| ほくろ（痣） | `CvsMole` | 3 | 2 | 部分 | 位置／大小／颜色 |
| メイク（妆） | `CvsMakeup` | 8 | 7 | 部分 | 眼影／腮红／唇／脸部彩绘 |
| 顔型全体 | `CvsFaceShapeAll` | **52** | 0 | **已有** | 就是我们的 `shape.face.0..51` |

### 2. 体（`CustomChangeBodyMenu`，11 个分类）

| 分类 | 原作类别 | 滑杆 | 开关 | 我们 | 备注 |
|---|---|---:|---:|---|---|
| 体全体 | `CvsBodyAll` | 4 | 2 | 部分 | 身高／头身等 |
| 胸 | `CvsBreast` | 14 | 1 | 部分 | 形状 ＋ 乳头 |
| 上半身 | `CvsBodyUpper` | 8 | 0 | 部分 | 属 44 项身体滑杆 |
| 下半身 | `CvsBodyLower` | 8 | 0 | 部分 | 同上 |
| 腕（手臂） | `CvsArm` | 7 | 0 | 部分 | 同上 |
| 脚 | `CvsLeg` | 9 | 0 | 部分 | 同上 |
| 爪 | `CvsNail` | 1 | 0 | 部分 | 颜色为主 |
| 下毛 | `CvsUnderhair` | 0 | 1 | 部分 | 选图 ＋ 颜色 |
| 日焼け（晒痕） | `CvsSunburn` | 0 | 1 | 部分 | 选图 ＋ 颜色 |
| ボディペイント | `CvsBodyPaint` | 8 | 4 | 部分 | 两层，位置／大小／颜色 |
| 体型全体 | `CvsBodyShapeAll` | 47 | 0 | **已有 44** | 我们的 `shape.body.0..43`；原作这页 47 个滑杆里有 3 个不是体型表的项（身高等），**下一轮要确认是哪 3 个** |

### 3. 髪（`CustomChangeHairMenu`）

4 个槽（後髪／前髪／横髪／エクステ）各一组 `CvsHair`（滑杆 1、开关 6）＋ `CvsHairEtc`（共通，开关 1）。
我们：选图端 **已有**（`appearance_page page=hair`：hair0-3 ＋ hair_gloss），每个槽的颜色与细项 **部分**。

### 4. 服（`CustomChangeClothesMenu`）

9 个槽（トップス／ボトムス／ブラ／ショーツ／手袋／パンスト／靴下／室内履き／外履き）共用 `CvsClothes`
（滑杆 20、开关 11，3653 行——原作最大的一个编辑器类）＋ `CvsClothesCopy`（在不同服装之间复制）。
我们：选图与穿着状态 **部分**，图样（Ptn）／颜色／细项 **部分**。

### 5. アクセサリ（`CustomAcsChangeSlot`）

20 个槽（`CvsAccessory`：滑杆 4、下拉 1、开关 5）＋ `CvsAccessoryChange`／`CvsAccessoryCopy`。
我们：槽位与选图 **已有**（`appearance_page page=accessory`，C001 实测 51 格，原作 20 ＋ 卡片 KKEx 多出来的），
每槽的位置／旋转／缩放／父节点 **部分**（`bone.*` 有，但不是照原作那 4 个滑杆的语义）。

### 6. パラメータ（`CustomChangeParameterMenu`，7 个分类）

`CvsChara`（滑杆 1、下拉 3、开关 3）、`CvsCharaEx`、`CvsH`（下拉 1）、`CvsQA`、`CvsInterest`、
`CvsAttribute`、`CvsADK`。这些是**人物设定而不是外观**：姓名／昵称／性格／声线／生日／H 相关／兴趣／属性。
我们：**几乎没有**——卡片里读得到（`Selected.Personality` 等），但编辑器没有这一页。
这一页的资料端入口在卡片的 parameter 区段与 `ChaFileParameter`，**下一轮要列出每个栏位**。

### 7. システム（`CustomChangeSystemMenu`）

`CvsConfig`（画面设定）＋ 拍照／存读档／还原。我们有自己的设定页与另存，**不必照原作对齐**，
但「还原到读入时的状态」这类功能值得抄。

## 四、颜色项（266 个）

`CvsColor.ConnectColorKind` 列出编辑器里每一个可调颜色。按家族分：

| 家族 | 数量 | 例 | 我们 |
|---|---:|---|---|
| 脸部 | 15 | `Eyebrow`／`Eyeline`／`EyeW01`／`Pupil01`／`Lipline`／`Mole`／`BaseEyeShadow`／`BaseCheek`／`BaseLip`／`BaseFacePaint01-02` | **已有**（`eye_page page=eyes` 的 properties 46 项涵盖瞳孔／高光／白目） |
| 身体 | 7 | `SkinMain`／`SkinSub`／`Nip`／`Nail`／`Underhair`／`Sunburn`／`BodyPaint01-02` | 部分 |
| 头发 | 28 | 4 槽 × （`Base`／`Start`／`End`／`Acs01-03`／`Outline`） | 部分 |
| 服装 | 72 | 9 槽 × （4 主色 ＋ 4 图样色） | 部分 |
| 饰品 | 约 140 | 20 槽 × 每槽多色 | 部分 |

## 五、我们现在的资料端（对照基准）

- `OKCharacterMCPRegistry::Parameters()`：`shape.face.0..51`（52）、`shape.body.0..43`（44）、
  `bone.*`（ABMX，两张测试卡上 1928 列）、`physics.*`、`pregnancy.*`、`style.*`，以及 properties。
  写入统一走 `set`（超出范围拒绝、不支援拒绝）。
- `appearance.rs` 的 `targets()`：`head`／`face_detail`／`eyebrow`／`eyeline_up`／`eyeline_down`／`eye_white`／
  `eye_hi_up`／`eye_hi_down`／`nose`／`lipline`／`mole`／`eyeshadow`／`cheek`／`lip`／`body_detail`／`sunburn`／
  `nipple`／`underhair`／`hair_gloss`／`hair0-3`／`clothes`／`accessory*`。
- 读卡器画面：六页的资料端已经做好（`Docs/READER_UI_APPEARANCE_API.md` 第 9、10 节）。

## 六、下一轮的顺序（按使用者会先看到的分页，不照程式码顺序）

1. **顔**：把 12 个分类的每一个滑杆对到 `shape.face.*` 的哪一项（或指出没有对应），缺的标「资料端缺／UI 缺」。
   先做这一页是因为它是开卡后的预设页，也是我们已经做最多的一页，差距最容易量。
2. **体**：同上，另外确认 `CvsBodyShapeAll` 那 47 对 44 的 3 个差额是什么。
3. **髪**：4 槽 × 颜色 7 项 ＋ 每槽的细项开关。
4. **服**：9 槽 × （主色 4 ＋ 图样 4 ＋ 20 个滑杆 ＋ 11 个开关）——这一页最大，要再切。
5. **アクセサリ**：20 槽的位置／旋转／缩放语义对到我们的 `bone.*`。
6. **パラメータ**：这一页我们几乎是零，要先列出 `ChaFileParameter` 的每个栏位与卡片区段。
7. **システム**：只挑「还原」这类值得抄的，不做全面对齐。

每一轮的输出都是同一个格式：项目名、种类、资料键、范围与预设、我们有没有、缺在资料端还是 UI。
