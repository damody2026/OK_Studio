# 读卡器拍照清单（2026-11-19 积着的那几组）

窗口一开就照这份机械执行，不要临场想。每一步写明：**呼叫与参数、期望看到什么、档名**。

**为什么是清单而不是 Lua 脚本**：这些是 agent 的 MCP 工具呼叫（`reader_launch`／`ui_exec`／`reader_call`），
Lua 脚本发不出去。只有「把截图改名搬到交付资料夹」那一步是 shell，写在每批末尾。

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
