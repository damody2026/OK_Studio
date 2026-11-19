# 读卡器拍照清单（2026-11-19 积着的那几组）

窗口一开就照这份机械执行，不要临场想。每一步写明：**呼叫与参数、期望看到什么、档名**。

**为什么是清单而不是 Lua 脚本**：这些是 agent 的 MCP 工具呼叫（`reader_launch`／`ui_exec`／`reader_call`），
Lua 脚本发不出去。只有「把截图改名搬到交付资料夹」那一步是 shell，写在每批末尾。

## 0.0 每一批开拍前先写表头（否则两批不能互比）

**每一批的第一个步骤**，在**建置之后、`reader_launch` 之前**跑这一行（只跑 git，不占机器）：

```powershell
F:\OpenKoikatsu\Tools\lua\lua.exe F:\OpenKoikatsu\Tools\shot_batch_header.lua write --editor F:/OpenKoikatsu --out F:\OpenKoikatsu\Saved\Reports\reader-shots-2026-11-19\<批次资料夹> --label <批次名>
```

| 批次 | `--out` 的 `<批次资料夹>` | `--label` |
|---|---|---|
| A 头发／瞳／两组前后 | `A-hair-eyes` | `A` |
| B `foregroundEyes` 一对 | `B-foreground-eyes` | `B` |
| C `Tohru` 材質貼圖页 | `C-textures-tohru` | `C` |
| D 指派＋偏移缩放 | `D-assign` | `D` |
| E 袖型 0／1 | `E-sleeves` | `E` |
| F 领口旗标 | `F-collar` | `F` |
| G MoreAccessories 第 21 栏 | `G-extra-acc` | `G` |
| H `HairShadowColorControl` | `H-hairshadow` | `H` |

两批要并排比之前先 `... check <A 资料夹> <B 资料夹>`：**`SAME` 才能比**；`DIFFERENT` 会指名哪一项不同，
**「修好前」那批作废重拍**；缺表头回 `MISSING`；旧版写的表头回 `OLD`（那之后程式路径没动的话，
用现在这版**重写一次就是同一批，不必重拍**）。

**`check` 比的是什么**（f-yvonne 2026-11-19 第二版）：九支 `UnrealEditor-*.dll`，加上**只看程式路径**的工作树指纹
（`Source`／`Plugins`／`Tools`／`Config`／`Content`／`OpenKoikatsu.uproject`，排除 `Content/CharacterCards`
与外挂的 `Binaries`／`Intermediate`）——这些路径在 HEAD 的已提交 id，加上这些路径下**未提交的** status／diff。
所以**提交 `Docs` 或改 `Saved` 不会让两批变成 `DIFFERENT`**，而**未提交的 C++ 会**。
**`HEAD` 只记不比**（`check` 会注明 `not compared`）：提交文件会动 HEAD 却不动程式，未提交的 C++ 动了程式却不动 HEAD。
`write` 会逐行列出未提交的程式档，`check` 会印 `compared N items … M differ`（带分母）。

**第三版（`6931d5402`）还记了 git 看不到的原作衍生资料**：`base_v1`（排除 `h/voice` 音档）、`RuntimeAnimations`、
`BodyInteractions`、`KKPreview`，各记档数、总大小、最新 mtime 与档案清单杂凑，分母因此变成 **21**。
**这对场景卡那条线比读卡器更要紧**：载入耗时直接受基础库内容影响，而基础库**不进版控、git 指纹看不到它**；
F 树若重录或还原 `base_v1`，前后两批会被判 `DIFFERENT`，不会被误当成可互比。

> **看 `check` 本身的结束码，而且不要接管线**：`0` = `SAME`（**只有 0 可以比**）、`1` = `DIFFERENT`、
> `2` = `MISSING`、`3` = `OLD`（f-yvonne `0047d05eb` 起四码分开；在那之前 `OLD` 与 `MISSING` 共用 2）。
> **接了 `| head`／`| tee` 就看不到它**——shell 的 `$?` 是管线最后那个程式的码。
> 我自己就因为 `check … | head -4` 看到 `exit=0`，以为 `OLD` 回 0、报成工具的 bug；
> 实际直接跑回的是 3。字串也一起看最稳。

**为什么是 `--editor`，不是某一支 exe**：读卡器（`reader_launch` 的预设 root）跑的是
`F:\UE5.8\Engine\Binaries\Win64\UnrealEditor.exe` 加这个专案——**那支是引擎，我们从来不重建它**
（本机 mtime 停在 10-29），拿它当身分每一批都一样，等于没记。

但**只记专案那支 `UnrealEditor-OpenKoikatsu.dll` 也不够**（f-yvonne 2026-11-19 指出的）：
`ok-extract`（Rust）是连进 `Plugins/KKUnityBundle` 的 `UnrealEditor-KKUnityBundle.dll`，
**只改 Rust 的建置不会动专案那支 DLL**——两批照片会看起来是「同一份程式」，其实解卡的那一半换过了。
所以 `--editor` 一次记**九支**：`Binaries/Win64` 与每个 `Plugins/KK*/Binaries/Win64` 底下的全部
`UnrealEditor-*.dll`（本机现在是 `OpenKoikatsu` 15:14:49；`KKUnityBundle`／`KKRuntimePose`／
`KKCardImporterEditor`／`OKModelEditor` 15:14:36；`KKCard`／`KKSideloader`／`KKImportedAssets`／
`KKCrowdGpuPacking` 更早），`check` 逐支比，**哪一支不同就指名**。
**如果哪一批改用打包版跑**（`reader_launch` 带 `root`），那一批的 `--exe` 要换成
`<那个 root>\...\OpenKoikatsu.exe`，并在该批注明——两种跑法的身分不能混着比。

## 0. 前提

- **不建置**：`reader_launch` 带 `no_build: true`。这些图不需要新的建置，而窗口期间别人可能在量测。
  本机已经建好（`3af999058` 当天两个 Development 目标都成功），要补建置才另外问 `may-build`。
- **问 gate 一律用转发版或 C 那份**：`F:\OpenKoikatsu\Tools\lua\lua.exe F:\OpenKoikatsu\Tools\unreal_slot.lua may-build`
  （`9cf1bd7c7` 起它只转发、不自己回答），回 `go` 才开引擎；exit 4 代表问不到仲裁者，**4 不是 go**。
- **lane**：每批用自己的 lane，收尾 `reader_stop {"lane":"<lane>"}`。lane 名字就是下面每批写的那个。
- **一次启动拍完一批**，不要拍一张重启一次。换卡才重启（`reader_launch` 一次只开一张）。
- **`reader_call` 的 `session`／`revision` 由 MCP 自己填**，不用手写；但会改状态的动作
  （`set`／`apply`／`ops`／`camera`／`textures_apply`）要的是**最新**的 revision，所以每批开头先 `state` 一次，
  中间若收到 `Stale revision; re-query state` 就再 `state` 一次重送，不要改参数。
- **导览只用这一个主控台命令**（`ui_exec`）：
  `ok.ReaderScreen tab <0-3> | category <名> | sub <名> | press <文字> [#N] | scroll <0-1> | width <px> | state`。
  `press` 先精确比对控件文字、再退回子字串，所以 `press 載入3D` 就够。**不要用 `ui_press`**（那是 UMG 的，
  读卡器的画面是 DreamGUI 镜像的）。
- **截图**：`ui_screenshot` 回传游戏自己挑的档名，**要自己搬**到
  `F:\OpenKoikatsu\Saved\Reports\reader-shots-2026-11-19\`，照下面的档名。
- **分类与群组名**（照 `OKReaderScreen.cpp` 的 `BuildCategories`，不是凭印象）：
  `臉`（`臉型`／`下巴`／`臉頰`／`眉毛`／`眼睛`／`鼻子`／`嘴巴`／`耳朵`／`瞳`／`頭型與膚質`）、
  `頭髮`（`後髮`／`前髮`／`側髮`／`附加髮`／`頭髮共通`）、`材質貼圖`（`材質貼圖`）、
  `身子`、`衣服`、`配件`、`角色資訊`；`人物卡總欄` 在 tab 1。

**一句先说清楚的话**：颜色类的改动（外框色、光泽色、主色）**截图只是说明，不是证据**。
每一张颜色图都配一次 `reader_call action=get keys=[…]`，把数值一起贴进文件 ——
一张「看起来好像深了一点」的图证明不了任何事，数值才行。

## 1. 批次 A：头发四页＋瞳＋两组前后对照（alice，lane `f-shot-a`）

卡：`F:\OpenKoikatsu\Content\CharacterCards\StreetHeroines\alice.png`

```jsonc
reader_launch {"card":"F:/OpenKoikatsu/Content/CharacterCards/StreetHeroines/alice.png","lane":"f-shot-a","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}        // 等它开完：reader_call state 的 settling 全部 false
reader_call {"action":"state"}
```

### A1–A4 头发四页

对 `後髮`／`前髮`／`側髮`／`附加髮` 各做一次：

```jsonc
ui_exec {"command":"ok.ReaderScreen category 頭髮"}
ui_exec {"command":"ok.ReaderScreen sub 後髮"}            // 依次换成 前髮／側髮／附加髮
ui_screenshot {}
```

**期望看到**：页面上半是这一槽的挑选与参数（`hair.parts.<N>.*`），下半固定是
**四个开关**（`四槽同步`／`自動漸層`／`連帶外框色`／`連帶光澤色`，全新安装时四个都是开）
加**五个按钮**（`重設外框色`／`重設光澤色`／`髮色反映到眉／陰毛`／`取眉色當髮色`／`取陰毛色當髮色`）。
四页的开关与按钮**必须一模一样**（它们是玩家设定、不是这一槽的资料）；哪一页少一个就是 bug。
页面长、按钮在下面看不到时用 `ui_exec {"command":"ok.ReaderScreen scroll 1"}` 再拍一张，档名加 `-bottom`。

档名：`hair-page-0-back.png`、`hair-page-1-front.png`、`hair-page-2-side.png`、`hair-page-3-option.png`
（必要时各加 `hair-page-N-…-bottom.png`）。

### A5 頭髮共通

```jsonc
ui_exec {"command":"ok.ReaderScreen sub 頭髮共通"}
ui_screenshot {}
```

**期望看到**：只有光泽遮罩种类（`hair.glossId`）这一项——它是每个角色一份、不分槽。
**不该**出现四个开关与五个按钮。档名：`hair-page-common.png`。

### A6 瞳（`臉 › 瞳`）

```jsonc
ui_exec {"command":"ok.ReaderScreen category 臉"}
ui_exec {"command":"ok.ReaderScreen sub 瞳"}
ui_screenshot {}
```

**期望看到**：瞳孔的挑选与参数（`pupil`／`gradation`／`eye_white`／`eye_hi_*`）加两个按钮
`左眼複製到右眼`、`右眼複製到左眼`。**不该**看到眼线、眼影、`foregroundEyes`——那些在 `臉 › 眼睛`
（原作就是分两页：`CvsEye01` 的 目 与 `CvsEye02` 的 瞳）。档名：`eye-page-pupil.png`。

顺手把 `臉 › 眼睛` 也拍一张做对照，证明两页确实分开：

```jsonc
ui_exec {"command":"ok.ReaderScreen sub 眼睛"}
ui_screenshot {}
```

档名：`eye-page-eyeline.png`。

### A7「重設外框色」前后

数值是证据，图是说明。四个槽都要看，因为 `四槽同步` 开着时这个动作写四槽。

```jsonc
ui_exec {"command":"ok.ReaderScreen category 頭髮"}
ui_exec {"command":"ok.ReaderScreen sub 後髮"}
reader_call {"action":"get","keys":["hair.parts.0.baseColor.0","hair.parts.0.baseColor.1","hair.parts.0.baseColor.2",
  "hair.parts.0.startColor.0","hair.parts.0.startColor.1","hair.parts.0.startColor.2",
  "hair.parts.0.endColor.0","hair.parts.0.endColor.1","hair.parts.0.endColor.2"]}   // 记下来，这是 before
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":60,"focus":[0,0,152]}   // 头部特写，外框色在轮廓上
ui_screenshot {}                                                                   // → hair-outline-before.png
ui_exec {"command":"ok.ReaderScreen press 重設外框色"}
reader_call {"action":"state"}                                                     // 等 settling 全 false
ui_screenshot {}                                                                   // → hair-outline-after.png
reader_call {"action":"get","keys":[ …同一组… ]}                                    // after
```

**期望**：外框色变成**各槽自己的 base 明度 −0.4**（保色相与饱和度，只动明度，`ops.rs` 的 `shift_value`）。
`focus` 的 Z 要照这张卡的头高微调：先 `reader_call state` 看 `camera.focus`，拿它的 Z 当起点。
**判准**：`after` 的外框色三通道要等于 `before` 的 base 做 −0.4 明度位移（已经是 0 的会被 clamp 住、不再变低）。
数值对不上就是 bug，不管图看起来像不像。

### A8「主色拖完 apply」前后

这组要证明的是：拖一个主色 → apply 之后写的是**原作那一个动作**（四槽 ＋ 渐层 ＋ 外框 ＋ 光泽），
不是只写被拖的那一个栏位。

```jsonc
reader_call {"action":"get","keys":["hair.parts.0.baseColor.0","hair.parts.1.baseColor.0","hair.parts.2.baseColor.0","hair.parts.3.baseColor.0",
  "hair.parts.0.startColor.0","hair.parts.0.endColor.0"]}                          // before，记下来
ui_screenshot {}                                                                   // → hair-maincolor-before.png
reader_call {"action":"set","edits":[{"key":"hair.parts.0.baseColor.0","value":0.9}]}
ui_screenshot {}                                                                   // → hair-maincolor-staged.png（看得到「已修改 1 項」）
reader_call {"action":"apply"}
reader_call {"action":"state"}                                                     // 等它重开完
ui_screenshot {}                                                                   // → hair-maincolor-after.png
reader_call {"action":"get","keys":[ …同一组… ]}                                    // after
```

**期望**：`四槽同步` 开着 → **四个槽**的 `baseColor.0` 都变成 0.9（不是只有槽 0）；
`自動漸層` 开着 → 槽 0 的 `startColor` 为 base −0.3、`endColor` 为 base ＋0.15；
`連帶外框色`／`連帶光澤色` 开着 → 外框 −0.4、光泽 ＋0.3。开关关掉哪一个，对应那组就不该动。
**这组最值得多花一分钟**：它是「一次 apply 等于原作一个动作」的唯一一张端到端证据。

收尾：

```jsonc
reader_stop {"lane":"f-shot-a"}
```

```powershell
New-Item -ItemType Directory -Force F:\OpenKoikatsu\Saved\Reports\reader-shots-2026-11-19 | Out-Null
```

（每张 `ui_screenshot` 回传的路径，用 `Copy-Item <回传路径> F:\OpenKoikatsu\Saved\Reports\reader-shots-2026-11-19\<档名>` 搬过去。）

## 2. 批次 B：`foregroundEyes` 一对（两张卡，lane `f-shot-b`）

**这一对已经做好，别重做**，在 `F:\OpenKoikatsu\Saved\Reports\foreground-eyes\pair\`：

| 角色 | 档案 | 为什么是这个 |
|---|---|---|
| off | `alice_fg_off2.png` | **走同一条产出管线**重新输出的对照（有 `alice_fg_off2.verified.json`） |
| on | `alice_fg_on.png` | 同一条管线，只差 `face.foregroundEyes` 这一个栏位 |

**不要用 `alice_fg_off.png`**：那是原卡的复本，不是重新输出的，当对照会得到几千个假差异
（这个错今天犯过两次，判准是：A／B 两边必须**只差一件事**，而且**用同一种方式读**）。

两张各启动一次，不要用同一个 process 换卡：

```jsonc
reader_launch {"card":"F:/OpenKoikatsu/Saved/Reports/foreground-eyes/pair/alice_fg_off2.png","lane":"f-shot-b","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":45,"focus":[0,0,152]}   // 眼睛特写
ui_screenshot {}                                                                   // → foreground-eyes-off.png
ui_exec {"command":"ok.ReaderScreen category 臉"}
ui_exec {"command":"ok.ReaderScreen sub 眼睛"}
ui_screenshot {}                                                                   // → foreground-eyes-off-page.png
reader_stop {"lane":"f-shot-b"}
```

再把 `card` 换成 `alice_fg_on.png` 跑同一串，档名 `foreground-eyes-on.png`／`foreground-eyes-on-page.png`。
**两次的 `camera` 参数必须完全一样**，否则两张图不能并排比。

**期望看到**：`on` 那张的目／眉画在脸的**前面**（不被头发或睫毛遮住的那一侧有差），`off` 那张没有；
页面那两张则是 `foregroundEyes` 这一列在 `臉 › 眼睛` 上，两张卡的值不同。
差异细微时，并排图不够，**另外跑一次 `reader_call action=get keys=["face.foregroundEyes"]` 两边各一次**，
把两个值贴进文件。

## 3. 批次 C：材質貼圖页（Tohru，lane `f-shot-c`）

卡：`D:\XKoikatuSunshine\UserData\chara\female\Tohru.png`（第 0 套 6 列，种类与槽号都不同，一张图就看得出分类）

```jsonc
reader_launch {"card":"D:/XKoikatuSunshine/UserData/chara/female/Tohru.png","lane":"f-shot-c","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
ui_exec {"command":"ok.ReaderScreen category 材質貼圖"}
ui_screenshot {}                                                                   // → textures-page-tohru.png
ui_exec {"command":"ok.ReaderScreen scroll 1"}
ui_screenshot {}                                                                   // → textures-page-tohru-bottom.png
```

**期望看到 6 行**，每行 `<种类> 欄 <槽>／<材质>／<属性>（<宽>×<高>, <KB>）` 加「指派」「清除」，
顶上一行说明与一个 PNG 路径输入框加「選 PNG…」。照 CLI 量到的，这 6 行应该是：

| 种类 | 槽 | 材质 | 属性 | 尺寸 |
|---|---:|---|---|---|
| character | 0 | `cf_m_face_00` | `DetailMask` | 1024×1024（约 124 KB） |
| character | 0 | `cf_m_tang` | `MainTex` | 256×256（约 30 KB） |
| character | 0 | `cf_m_body` | `DetailMask` | 512×512（约 104 KB） |
| character | 0 | `cf_m_eyeline_kage` | `MainTex` | 512×512（约 9 KB） |
| character | 0 | `cf_m_eyeline_00_up` | `MainTex` | 512×512（约 41 KB） |
| accessory | 30 | `cf_m_hair_f_20_00` | `DetailMask` | 1024×1024（约 127 KB） |

**对不上就是界面读错了**，不是卡变了 —— 这张卡的清单可以随时用
`OK_TEX_CARD="D:/XKoikatuSunshine/UserData/chara/female/Tohru.png" cargo test --release --lib textures::tests -- --ignored --nocapture`
重新印一次（那支测试会先把这 6 列印出来）。

接着拍一组写回的前后（选最便宜的一列：`cf_m_tang`／`MainTex`，256×256）：

```jsonc
// 清除：原作 RemoveMaterialTexture 只把 TexID 设 nil，这一列没有偏移／缩放，所以整列会消失
ui_exec {"command":"ok.ReaderScreen press 清除 #1"}   // #1 = 第 2 行（从 0 数），即 cf_m_tang
reader_call {"action":"state"}                        // 它会重开卡，等 settling 全 false
ui_exec {"command":"ok.ReaderScreen category 材質貼圖"}
ui_screenshot {}                                      // → textures-after-clear.png
```

**期望**：**剩 5 行**，`cf_m_tang／MainTex` 那行不见了；舌头的贴图回到原版。
按「清除」之前先拍一张当 before（就用 `textures-page-tohru.png`）。
`#N` 是**同文字控件的第几个**（从 0），所以先用上面那张图确认 `清除` 按钮的顺序和表格一致；
顺序不同就按表格里的位置换 `#N`，**不要按印象猜**。

指派那一步**这个窗口不拍**：它需要一张手边的 PNG 当素材，而「指派一张随便的图」拍出来的
只是一张花脸，证明不了写回对不对；写回对不对已经由 CLI 的来回测试证明（`7ecd947ff`）。
要拍就准备一张一眼看得出来的图（例如纯色或带字的 256×256），放进
`Saved\Reports\reader-shots-2026-11-19\assign-source.png`，再走「選 PNG…」→「指派」。

收尾：

```jsonc
reader_stop {"lane":"f-shot-c"}
```

## 4. 拍完要做的事

1. 所有图搬到 `F:\OpenKoikatsu\Saved\Reports\reader-shots-2026-11-19\`，档名照上面。
   **这个资料夹不进版控**（`Saved/` 是本机产物），文件里只写路径与看到了什么。
2. 把每组的**数值**（A7／A8 的 `get` 结果、批次 B 的 `face.foregroundEyes` 两值、批次 C 的 6 行）
   贴进对应文件，和图放在一起。
3. **把「预期」改成「已验证」**，只改真的拍到的那几段：
   - `Docs/CHARACTER_EDITOR_PARITY_HAIR_EYES.md` §8.4（头发／瞳的界面）、§12.9（材質貼圖页）
   - 没拍到的继续写「预期」，不要整段一起改掉。
4. 有任何一项和「期望看到」不符，先记进 `Docs/ERROR_LOG.md` 再改程式——**图是拿来找 bug 的，
   不是拿来确认我们没错的**；拍到不符而只改文件描述，等于把证据丢掉。

## 5. 批次 D：指派一张检查贴图，加偏移／缩放（`KK_110449`，lane `f-shot-d`）

素材：`F:\OpenKoikatsu\Tools\testdata\uv_check_512.png`（进版控，自制内容），
产生脚本 `F:\OpenKoikatsu\Tools\make_uv_check_texture.lua`：

```powershell
F:\OpenKoikatsu\Tools\lua\lua.exe F:\OpenKoikatsu\Tools\make_uv_check_texture.lua
```

**为什么是这张图**：随便指派一张图拍出来只是一张花脸，证明不了写回对不对。这张能同时验四件事——
8×8 **棋盘格**看缩放与平铺、**四角四色**（左上红、右上绿、左下蓝、右下黄）看旋转与镜像、
中央一个**「F」**（两个轴都不对称）看水平翻／垂直翻／转 90°、**外框一圈青**看取样有没有超出 0..1。

卡：`D:\XKoikatuSunshine\UserData\chara\female\KK_110449.png`。指派到**这一列**（CLI 量过的第 0 套 9 列之一）：

| 种类 | 槽 | 材质 | 属性 | 原本 |
|---|---:|---|---|---|
| `clothing` | 0 | `cf_m_top_02` | `MainTex` | 2048×2048，约 38 KB |

挑它是因为它是这张卡上**最大的一片看得见的布**；`DetailMask`／`LineMask` 那两列不要用——它们不是颜色图，
贴棋盘格上去只会变成一片怪阴影，看不出 UV。**这张卡开不开得起来要当场看**（它要游戏的 mods）：
开不了就退而求其次，在页面上挑**任何一列 `MainTex` 且尺寸 ≥ 1024²** 的（例如 `acs_m_neck_knight`／`MainTex`），
并把实际用的那一列写进文件——**不要硬套上表**。

```jsonc
reader_launch {"card":"D:/XKoikatuSunshine/UserData/chara/female/KK_110449.png","lane":"f-shot-d","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
ui_exec {"command":"ok.ReaderScreen category 材質貼圖"}
ui_screenshot {}                       // → assign-page-before.png（先确认页面 9 行、顺序与上表对得上）
reader_call {"action":"textures"}      // 数值版的 before，贴进文件
```

拍身上那片布的特写（上衣在胸腹，相机对准躯干）：

```jsonc
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":120,"focus":[0,0,110]}
ui_screenshot {}                       // → assign-cloth-before.png
```

### D1 指派

界面走「選 PNG…」会开系统对话框，**MCP 点不到那个对话框**，所以窗口里用两种做法之一：

- **拍界面**：`ui_exec {"command":"ok.ReaderScreen press 選 PNG…"}` 之后人手在对话框选档，再
  `ui_exec {"command":"ok.ReaderScreen press 指派 #1"}`（`#N` 是第几个同名按钮，从 0；先用
  `assign-page-before.png` 确认 `cf_m_top_02／MainTex` 是第几行）。
- **不靠对话框**（可完全自动，建议拍图用这条）：直接下

```jsonc
reader_call {"action":"textures_apply","changes":[{"object":1,"coordinate":0,"slot":0,
  "material":"cf_m_top_02","property":"MainTex","png":"F:/OpenKoikatsu/Tools/testdata/uv_check_512.png"}]}
reader_call {"action":"state"}         // 它会重开卡，等 settling 全 false
```

```jsonc
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":120,"focus":[0,0,110]}
ui_screenshot {}                       // → assign-cloth-after.png
ui_exec {"command":"ok.ReaderScreen category 材質貼圖"}
ui_screenshot {}                       // → assign-page-after.png
reader_call {"action":"textures"}      // 数值版的 after，贴进文件
```

**期望**：

- 画面上那片布变成棋盘格＋「F」。**F 正着、没镜像**；四角的红绿蓝黄按左上／右上／左下／右下排。
  （布是曲面又有 UV 切割，所以图会被拉扯、也可能看到好几块——**这正常**。要判的是「有没有贴上去」与
  「有没有整片翻过来」，不是「格子方不方」。）
- 数值上：那一列的 `bytes` = **这个档案的大小**、`size` = **[512, 512]**、`tex_id` 是一个整数。
  **这是证据，图是说明**（和 A7／A8 同一条判准）。
- 其余 8 列**完全不动**（`tex_id` 与 `bytes` 都和 before 一样）。动了就是写回碰到了不该碰的列。

### D2 偏移 `Offset [0.5, 0]`

**走界面**：`材質貼圖` 页每一列底下有一行「偏移 x y 縮放 x y」加「套用偏移／縮放」按钮，
四个格子一开始填着这一列现在的值；**两格都清空＝移除那一笔**（原作的 `RemoveMaterialTextureOffset`／`Scale`）。
窗口里拍的要是**使用者真的会按的那条路**，所以 D2／D3 走按钮；底下的 `reader_call` 版留着当对照，
两条走出来的结果必须一样（它们本来就是同一支写入：按钮也走 `textures_apply`）。

```jsonc
// 走界面：先把四个格子填好，再按按钮。#N 是同文字控件的第几个（从 0），
// 所以 cf_m_top_02／MainTex 是第几行就填几 —— 先用 assign-page-after.png 数，不要按印象猜。
ui_exec {"command":"ok.ReaderScreen press 套用偏移／縮放 #<那一行>"}
```

格子里的文字要先用 `ui_mouse` 点进去再 `ui_type`（DreamGUI 的输入框收不到 `ui_press`）；
嫌麻烦就用下面的 `reader_call` 版，两者写进卡里的东西一模一样。

```jsonc
reader_call {"action":"textures"}      // 先重读：上一次 apply 之后清单已经重建
reader_call {"action":"textures_apply","changes":[{"object":1,"coordinate":0,"slot":0,
  "material":"cf_m_top_02","property":"MainTex","offset":[0.5,0]}]}
reader_call {"action":"state"}
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":120,"focus":[0,0,110]}
ui_screenshot {}                       // → assign-cloth-offset.png
reader_call {"action":"textures"}      // offset 应该读回 [0.5, 0]
```

### D3 缩放 `Scale [2, 2]`

```jsonc
reader_call {"action":"textures_apply","changes":[{"object":1,"coordinate":0,"slot":0,
  "material":"cf_m_top_02","property":"MainTex","scale":[2,2]}]}
reader_call {"action":"state"}
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":120,"focus":[0,0,110]}
ui_screenshot {}                       // → assign-cloth-scale.png
reader_call {"action":"textures"}      // scale 应该读回 [2, 2]
```

**期望与判准**（这一段要写得保守，因为画面上会怎么动**取决于那个材质的取样 wrap 模式**，不是我们定的）：

- **数值是判准**：读回的 `offset` 就是 `[0.5, 0]`、`scale` 就是 `[2, 2]`，一分不差。
  形状照原作的 `Vector2Formatter`（两个 float32 的定长阵列）写，所以读回来不该变成 `null`，
  也不该是 `{x, y}`。读回 `null` = 写进去的形状游戏读不懂，这是**真 bug**，先记 `ERROR_LOG`。
- **画面只当说明**：偏移之后图样应该沿着 U 轴挪半张；缩放之后格子变小、一张图在同一片布上重复更多次
  （wrap 是 clamp 的话会变成边缘拉长——**也算合理**，不要因为「不是我想的那样」就判定失败）。
  `assign-cloth-after.png`／`-offset.png`／`-scale.png` 三张并排放。
- 这是**偏移／缩放那条写回路径第一次有画面证据**，在此之前只有 CLI 的来回测试
  （`unity_structs_are_float32_arrays_on_a_real_card` 只钉住了形状，没有画面）。

收尾：

```jsonc
reader_stop {"lane":"f-shot-d"}
```

**不要把改过的卡留在游戏的卡片资料夹**：`textures_apply` 的输出在
`Saved/`（`AppearanceWorkFolder`）底下，原卡 `KK_110449.png` 不会被改写；拍完确认一下它的 mtime 没变。

## 6. 批次 E：袖型 0／1（`KK_007604` 服装 1，lane `f-shot-e`）

f-yvonne 的题目，画面验证：CLI 已确认 `clothes.parts.0.sleevesType` 的 0 是短袖加扣子、1 是长袖到手腕。

**顺序不能换：先脱手套，再换上衣，最后才拍。** 没脱手套，前臂会被 `o_gloves_magic` 盖住，这组就白拍了——
拍到一半才发现等于整批重来。

```jsonc
reader_launch {"card":"D:/XKoikatuSunshine/UserData/chara/female/KK_007604.png","lane":"f-shot-e","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
```

**切到服装 1**：`reader_call {"action":"controls"}` 列出画面上的控件，找服装选择那个（Gallery 里叫
`OutfitCombo`），再 `reader_call {"action":"control_set","key":"<列出来的 key>","value":1}`。
**key 以 `controls` 列出来的为准，不要按这里的名字硬下**——这份清单写的是哪一年的名字，不保证是窗口当天的。

**脱手套、换上衣**：`reader_call {"action":"catalog"}` 列出 targets 与 items。

1. 找手套那个 target（`kind 4`），`reader_call {"action":"appearance","target":"<它的 key>","item":""}`
   （空字串＝脱掉）。
2. 找上衣那个 target，在 items 里找**原作来源、id 217**（セーラーワンピース）那一笔，
   `reader_call {"action":"appearance","target":"<上衣 target>","item":"<那一笔的 key>"}`。
   **按 id 找，不要按名字找**：名字会因语言与 mod 重名。
3. `reader_call {"action":"state"}` 等 settling 全 false。

**两个袖型各拍正面与侧面**（`sleevesType` 是模型旗标，**staged 不会动模型**，要 `apply` 之后才变）：

```jsonc
reader_call {"action":"set","edits":[{"key":"clothes.parts.0.sleevesType","value":0}]}
reader_call {"action":"apply"}
reader_call {"action":"state"}
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":150,"focus":[0,0,105]}   // 正面，手臂要入镜
ui_screenshot {}                                                                     // → sleeves-0-front.png
reader_call {"action":"camera","yaw":-90,"pitch":0,"distance":150,"focus":[0,0,105]} // 侧面
ui_screenshot {}                                                                     // → sleeves-0-side.png
reader_call {"action":"get","keys":["clothes.parts.0.sleevesType"]}                   // 数值，贴进文件
```

`value` 换成 1 再跑一次，档名 `sleeves-1-front.png`／`sleeves-1-side.png`。

**期望**：0 = 短袖、袖口有扣子；1 = 长袖到手腕。**手腕到手肘那一段必须看得见**（手套已脱），
否则这两张分不出差别，重拍。四张的 `camera` 参数必须完全一样，不然不能并排比。

收尾 `reader_stop {"lane":"f-shot-e"}`。

## 7. 批次 F：领口是旗标还是模型（同一张卡同一套服装，lane `f-shot-f`）

要证明的事：先前截图里领口从蝴蝶结变成长领带，是**显示旗标不同**，不是**模型不同**。
所以**每张图都要配当时的数值**——这组图单看没有意义。

**「两次导出的网格清单相同」这一句是 f-yvonne 先前两次导出比出来的，不是这个窗口量的。**
写清楚是因为照着跑的人会去找「网格清单」在哪个 `reader_call` 里——**没有那个东西**，
别花时间找（这正是 `ERROR_LOG` 那条通则的第一问：先确认来源记的是什么层级的东西）。
窗口里只拿得到下面这几个卡上的键与画面；网格那一半的证据向 f-yvonne 要。

```jsonc
reader_launch {"card":"D:/XKoikatuSunshine/UserData/chara/female/KK_007604.png","lane":"f-shot-f","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
// 切到服装 1（同批次 E 的做法）
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":90,"focus":[0,0,135]}   // 领口特写
ui_screenshot {}                                                                    // → collar-first-open.png
reader_call {"action":"parameters","query":"clothes.parts.0.hideOpt"}               // 记下 .0 与 .1
reader_call {"action":"parameters","query":"accessory.parts.12"}                    // type／id／hideCategory／parentKey，照实记
```

**重新载入，再拍一次同一个画面**：

```jsonc
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
reader_call {"action":"camera","yaw":0,"pitch":0,"distance":90,"focus":[0,0,135]}   // 和上面一字不差
ui_screenshot {}                                                                    // → collar-reloaded.png
reader_call {"action":"parameters","query":"clothes.parts.0.hideOpt"}
reader_call {"action":"parameters","query":"accessory.parts.12"}
```

**判准**（这组特别容易得出错的结论，所以写死）：

**先说清楚能读到什么，免得写出不存在的东西**（f-yvonne 2026-11-19 更正）：
**「配件显示状态」不是卡上的栏位。** 原作的配件显示开关是执行期的 `ChaFileStatus.showAccessory`，
**不进卡**，所以 `parameters` 里不知道有没有对应的键，而且从来没人读过它 —— **不要写成有**。
这一槽能读到的是 `accessory.parts.12.type` 与 `id`（这一槽戴着什么，`catalog` 的 `current` 也看得到）、
`accessory.parts.12.hideCategory`、`accessory.parts.12.parentKey`。槽号**从 0 起算**，
读卡器 UI 上显示为「配件欄 13」—— 写进文件时两个都写，免得下一个人对不上。
另外窗口里用 `reader_call {"action":"controls"}` 看有没有配件显示开关：有就记**当场的值与控件 key**，
找不到就照实写「读卡器没有配件显示开关，只记卡上旗标」。

- 两张图**看起来不同**，而两次的**网格清单相同**，而 `hideOpt` 或上面那几个键**不同**
  → 结论成立：是旗标。
- 两张图看起来不同，但 `hideOpt` 与那几个键**也相同** → **结论不成立**，
  差异来自别的东西（材质、动态骨、载入时序都可能）。这时候**不要**把它写成「旗标问题」，
  记进 `Docs/ERROR_LOG.md` 说「两次不同但已知旗标相同，原因未定」。
- 两张图**看起来一样** → 这次没重现，照实写「没重现」，不要去调参数直到它重现为止
  ——那是在制造证据，不是在找证据。
- 写进文件时**用 `parameters` 列出来的键的实际名字**，不要写成「`o_necktie_yure_long` 开着」——
  配件槽与模型名是两件事，混着写下一个人会以为是同一件。

收尾 `reader_stop {"lane":"f-shot-f"}`。

**两张图的 `camera` 必须一字不差**，否则「看起来不同」可能只是镜头差一点。

## 8. 批次 G：MoreAccessories v2 的第 21 栏以后（lane `f-shot-g`）

f-yvonne 的题目：怀疑 `extra.rs` 改到错的地方。**v2 卡的真资料在原作的 `parts[20..]`，XML 只是副本**，
所以「改了 XML 但没改到真资料」会表现成：apply 当下看起来变了，重开却变回原样。

**选卡**（窗口里做，别事先假设）：`reader_call {"action":"catalog"}` 列出 targets，
找 key 形如 `accessory20_<cat>` 的「額外配件欄」；再确认**那一栏真的戴着东西**（`current` 里不是空的）。
找不到这样的卡就照实写「手上的卡都没有可用的额外配件欄」，**不要为了凑这批去改一张卡**。

```jsonc
reader_launch {"card":"<选到的卡>","lane":"f-shot-g","no_build":true}
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
reader_call {"action":"camera", … }                 // 对准那个额外配件，机位记下来，三张都用同一组
ui_screenshot {}                                    // → extra-acc-before.png
reader_call {"action":"parameters","query":"MoreAccessories"}   // 当场列出键，记下第 21 栏那几列的实际键名与值
```

**改颜色 → apply → 再拍**（键名**以上一步列出来的为准**，下面是形状示意，不是可照抄的键）：

```jsonc
reader_call {"action":"set","edits":[{"key":"plugins.MoreAccessories.….xml.<槽>.color0r","value":<明显不同的值>}]}
reader_call {"action":"apply"}
reader_call {"action":"state"}
reader_call {"action":"camera", … }                 // 和 before 一字不差
ui_screenshot {}                                    // → extra-acc-applied.png
```

**关卡重开，第三张**（这一张才是判准所在）：

```jsonc
ui_exec {"command":"ok.ReaderScreen press 載入3D"}
reader_call {"action":"state"}
reader_call {"action":"camera", … }                 // 同上
ui_screenshot {}                                    // → extra-acc-reopened.png
reader_call {"action":"parameters","query":"MoreAccessories"}   // 读回那一列的值
```

**判准**：

- 重开后**颜色变了、值也读得回来** → `extra.rs` 没问题。
- **apply 当下就没变**，或**重开后变回原样** → **是真 bug**（改到了 XML 副本，没改到 `parts[20..]` 的真资料）。
  记 `Docs/ERROR_LOG.md` 并回报 f-yvonne，附三张图与两次读回的值。
- **看起来没差别** → 照实写「没重现」，**不要去调参数凑**。颜色挑**明显不同**的（例如红 ↔ 绿），
  不要挑差一点点的——差一点点的本来就看不出来，看不出来不等于没写进去，那时候以**读回的值**为准。

收尾 `reader_stop {"lane":"f-shot-g"}`。

## 9. 批次 H：`HairShadowColorControl` 存不存卡（不用拍照，不用自己的 lane）

我们的外挂清单（`PLUGIN_SECTIONS`）有这一列，但反编译里找不到它存卡。**这批不另外开引擎**：
在 A～G **每一次已经开着的卡**上各做一次，两个读取而已。

```jsonc
reader_call {"action":"parameters","query":"HairShadowColorControl"}
reader_call {"action":"state"}        // 看 unknown_plugin_sections 有没有这个键
```

记一张表：卡片路径 → 有／无（有就记键名与栏位）。涵盖这几张（都是别批已经要开的）：
`alice.png`、`alice_fg_off2.png`、`alice_fg_on.png`、`Tohru.png`、`KK_110449.png`、`KK_007604.png`、批次 G 那张。

**判准**：

- **有** → 记下键与栏位，回报 f-yvonne。
- **全都没有** → 照实写「**这几张卡没有**」，**不要推论成「这个外挂不存卡」**，
  `PLUGIN_SECTIONS` 那一列也**不要删**。
  （这正是 `Docs/ERROR_LOG.md` 那条通则的第二问：**「查不到」有两种**——真的没有，
  和这批样本里刚好没有。七张卡答不了「所有卡」，更答不了「这个外挂会不会存卡」；
  那个问题要去反编译里问它的 `OnCardBeingSaved`，不是去卡里问。）

### 8.1 G 还要记一笔：这张卡的 moreAccessories 是 v1 还是 v2

**只有 v2 卡验得到那件事**（v1 会把 `parts` 截到 20，第 21 栏以后根本不存在）。所以三张图旁边要记版本。

**版本在哪**：XML 根节点的属性 —— `<additionalAccessories version="2.0.21.1">`
（`extra.rs:7` 新建这个区段时写的就是这个形状）。

**但读卡器读不到它**，这点要先说清楚，免得窗口里去翻一个不存在的列：
`parameters` 里那些 `plugins.MoreAccessories.….xml.<槽>.<属性>` 的列来自
`appearance/properties/plugins.rs` 的 `xml_rows`，它**只走每个 `<accessory>` 节点的属性**，
**不走根节点**，所以 `version` 从来没有被列出来过。这不是漏读，是那条路本来就不收根属性。

所以版本只有两条路：

1. **离线用 CLI 读那张卡**（窗口外做，不占机器）：把 `moreAccessories` 区段的 XML 根节点属性印出来。
2. **读不到就照实写「版本未知」**，并在结论里写明：**版本未知时，G 的结果不能用来支持或否定那个怀疑**
   ——v1 卡本来就没有第 21 栏，看起来「没变」是正常的，不是 bug。

**f-yvonne 手上也没有确定符合的卡**（2026-11-19 问过：它这条线一直在读程式与反编译，
没有在任何一张卡上实际看到第 21 栏戴着东西）。所以选卡维持「窗口里现找」，
**找不到就记「手上的卡都没有」**，不要因为某条线在做配件就假设它有一张。
