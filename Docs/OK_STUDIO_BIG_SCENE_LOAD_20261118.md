# 很大的原作场景卡：冷开变快（2026-11-18，F 树，f-studio-ui）

使用者要求：「能快速读取 `E:\OpenKoikatsu\ref\很大的卡`」。那六张 PNG（130–615 MB）**不是角色卡，是原作 KStudio 场景**
（IEND 后面是场景版本 `4.2`／`1.0.4.2`、ColorCorrection、camera…），在 OK Studio 里走「导入原作场景」那条路。
样本复制在 `F:\OpenKoikatsu\Saved\BigCards\`（本机，不进版控）。

## 63-2.png（4 角色、395 物件、365 MB 场景 JSON）的冷开分布（改前）

| 阶段 | 秒 |
|---|---:|
| 场景导出（Rust）＋解析 JSON | 约 9.4（导出 5.0 —— JSON 超过 64 MB 缓冲区，**导出跑了两次**；解析 2.8） |
| 4 个子行程转 OK 卡，**全部失败** | 9–11.5 |
| 失败后回到本行程依序**再转一次，同样失败** | 约 19 |
| 之后的建构（`build_ms`） | 4.5–6.5 |

转卡失败的原因：这几位角色用到的 zipmod 不在基础库、F 机器上也没有（`[makise]zzz-ling`、`taka_co_panst_02` 等），
`ok-extract` 回报 `the OK card lacks N thing(s) ...`。那是**对这张卡、这份库、这棵 mods 树的确定结论**，同一次转换在
本行程再跑一次只会再说一次。角色最后都以原作卡开启。

## 第一处（已改、已量）：子行程判定「缺资料」的卡，本行程不再重转

`OKStudioImport.cpp`：`ConvertCardsInWorkers` 把「exit 1 且输出含 `the OK card lacks`」的卡记进
`CardsUnconvertible`（带那行结论），走树时直接拿结论当 note，只保留「场景旁边有 mods 资料夹」那条重试。
其他失败（崩溃、被杀）照旧回本行程重转。关闭开关：`OK_NO_UNCONVERTIBLE_SKIP=1`（回旧行为）。
另外加了一行 log：`import scene export X s, JSON Y MB parsed in Z s`。

**A/B**（同一执行档、开关切换、交错两轮、冷开＝全新行程第一个场景、`OK_NOCACHE=1`、`RAYON_NUM_THREADS=8`、
F 树 `8bf22542f` ＋ 未提交的改动、编辑器 `-game`、`OKStudio.ProfileSceneLoad 1 exit`）：

| | 第 1 轮 `ready_ms` | 第 2 轮 | 中位数 |
|---|---:|---:|---:|
| 旧（`OK_NO_UNCONVERTIBLE_SKIP=1`） | 41 409 | 42 553 | **41 981** |
| 新 | 24 347 | 24 659 | **24 503** |

**−41.6%（约 −17.5 s）**。`load_call_ms` 旧 36.9／37.2 s → 新 17.8／18.5 s。
开关确认真的在切：每趟日志的 `opened ... in` 旧 36.6／36.8 s、新 17.5／18.1 s。
这个收益只在「卡缺 mods」的机器上有（使用者给测试者的环境正是如此）；卡能转成功的机器上行为不变。

## 缺 zipmod 的角色照样转成 OK 卡（`6059c50f8`）

使用者要求：缺的部件不显示，身体一定要显示，有模型没材质就用预设材质。转卡时「只有本机没有的 zipmod 才补得上」的缺口
不再让整张卡失败：照样写出 OK 卡、记进 `okAb` 区块，严格开卡接受它们。关闭开关 `OK_STRICT_CONVERT=1`。

六张场景的 38 位角色全部转成（CLI `--oklib card-outfit`，outfit 0）：

| 场景 | 角色 | 每张略过的部件 |
|---|---:|---|
| 63-2 | 4 | 2–6 |
| 2026_0221_1637_17_768 | 5 | 4–15 |
| 65 | 3 | 4–6 |
| SD42 full | 10 | 2–6 |
| [EveKaczmarek] Evelyn on Top | 8 | 1–9 |
| 認識阻害おじさんvs授業中ギャル（TimeLine） | 8 | 3–6 |

改之前这 38 张全部转卡失败。OK Studio 实际导入 63-2：4/4 角色转成 OK 卡、身体完整、缺 zipmod 的头发等不显示
（`Saved/Reports/scene-load/big63-absent_63-2_pass0.png`）。

## 第二处：贴图搬出场景 JSON（`4a07d42fa`，CLI 与 UE 端都已量）

63-2 的 365 MB JSON 里 359 MB 是 MaterialEditor 道具贴图的 base64 PNG（200 处，去重后 270 MB）；
SD42 full 是 142 MB base64、去重后 15.5 MB；65 是 130 → 46.5 MB。

- `studio_scene.rs`：`export()` 结尾 `texture_edits_to_files`：每张不同的贴图写成卡目录里的 `mat_<sha256 前 10 位元组>.png`，
  JSON 的 `text` 换成 `file`。关闭开关 `OK_SCENE_TEXTURES_INLINE=1`。附 `unbase64` 与往返测试。
- `OKStudioImport.cpp`：读 `file`，每个档案只编码一次 base64 进 `Edit.Text`（文件格式不变），读完删掉那些档案。

预期拿掉「导出跑两次」与大部分 JSON 解析（63-2 约 5 s）。

**CLI 导出 A/B**（同一执行档，`OK_SCENE_TEXTURES_INLINE=1` 对照，各一趟）：

| 场景 | 内嵌 JSON | 档案版 JSON | 写出的贴图档 | 导出 ms 内嵌 → 档案 |
|---|---:|---:|---:|---:|
| 63-2 | 347 MB | 3 MB | 143 | 3610 → 4150 |
| 65 | 297 MB | 2 MB | 41 | 3231 → 3491 |
| SD42 full | 144 MB | 8 MB | 7 | 1530 → 1417 |
| Evelyn on Top | 20 MB | 0.3 MB | 10 | 2695 → 2399 |
| TimeLine | 34 MB | 1 MB | 10 | 689 → 725 |
| 2026_0221 | 4 MB | 0.1 MB | 1 | 1708 → 1628 |

Rust 导出本身差不多（写档多 0.3–0.5 s）；省下的在 UE 端：JSON 不再超过 64 MB 缓冲区（不再导出两次），也不必解析几百 MB。

**正确性**：六张场景两种 JSON 去掉贴图栏位与输出资料夹之后**逐位元组相同**；452 处贴图引用，每个档案重新编成 base64
都与内嵌版本的文字完全相同（含 JPEG 贴图，副档名一律写 `.png`，UE 端按内容辨识格式）。

**UE 端导入 A/B**：同一执行档，交错两轮；`OK_SCENE_TEXTURES_INLINE=1` 是旧行为。冷开，`OK_NOCACHE=1`，
`RAYON_NUM_THREADS=8`，F 树 `fe70e946e`（整合 #16 之后）。量测时机器上**还有另一个 Unreal**（e-fork-2 的读卡器），
所以绝对数字偏高、`build_ms` 抖动大，请看同轮的差值。

| 场景 | | 导出＋解析 s（两轮） | `load_call_ms` 中位数 | `ready_ms` 中位数 |
|---|---|---|---:|---:|
| 63-2 | 内嵌（347.7 MB JSON） | 6.38+3.12／5.38+3.05 | 22 689 | 27 894 |
| 63-2 | 档案（3.6 MB JSON） | 3.94+0.23／3.01+0.13 | **18 420** | **25 112** |
| 65 | 内嵌（297.3 MB JSON） | 4.57+2.67／4.53+2.59 | 21 960 | 33 781 |
| 65 | 档案（2.6 MB JSON） | 2.76+0.10／2.39+0.09 | **18 903** | **31 855** |

导出＋解析：63-2 约省 5.3 s，65 约省 4.5 s。`load_call_ms` 各省 4.3／3.1 s，`ready_ms` 各省 2.8／1.9 s。
`ready_ms` 少省的那一截，是两轮 `build_ms` 的抖动（65 档案版第 1 轮 14.2 s，其余 11.7 s 左右）。
开关确认真的在切：每趟日志 `import scene export ... JSON X MB` 的 X 是 3.6／2.6 MB 对 347.7／297.3 MB。
两种都是 4/4、3/3 角色转成 OK 卡（`import converted`）。

## 其余五张场景进 OK Studio（实拍，`cf87fee50` 的建置，1920×1080）

冷开，`OK_NOCACHE=1`，每张一个全新行程。截图在 `F:\OpenKoikatsu\Saved\Reports\scene-load\big-look<N>_<场景>_pass0.png`
（建好的成品）与 `..._loading.png`（建构中第 40 帧）。

| 场景 | 角色转成 OK 卡 | 子行程转卡 s | `ready_ms` |
|---|---:|---:|---:|
| 2026_0221_1637_17_768 | 5/5 | 18.9 | 25 783 |
| 65 | 3/3 | 14.7 | 29 646 |
| SD42 full | 10/10 | 23.0 | 34 643 |
| [EveKaczmarek] Evelyn on Top | 8/8 | 16.8 | 24 363 |
| 認識阻害おじさんvs授業中ギャル（TimeLine） | 8/8 | 19.3 | 30 198 |

五张成品都看得到角色身体和场景（道具、背景、文字看板）。卡片引用、但本机没有的 zipmod，它们的部件不显示，
这是照使用者 2026-11-18 的决定：「部份沒有成功的元件就不顯示 但身材一定要顯示」。缺的多数是头发，所以角色是光头。
根因是本机没有那些 zipmod：F:、C:\portable\KoikatuSunshine、D:、E: 都找不到（抽查 4 个），
基础库 `sources.okidx` 只记了路径，所以转卡时没有资料可以封进 OK 卡。要补齐，只能拿到那些 zipmod 再重转（`okId` 不变）。
33 张 OK 卡各缺哪些部件（`okAb` 区块原文）整理在协调者的共享笔记 `f-studio-ui-okab-missing-parts-20261118.md`，
约 40 个 zipmod，最常见的是 `[dale] ecchange v1.5`、`[makise]zzz-ling`、`[xne]swimset01`。

**别把两种「缺」混在一起：**

- **转卡时就没有的部件**（这 33 张卡）：卡一产生就没有那些资料，缺口记在 `okAb` 区块里。
  这种卡在任何机器上开都一样缺，和那台机器有没有原作游戏无关。补法是拿到 zipmod 重转（`okId` 不变）。
  测「没有原作游戏的电脑能不能开 OK 卡」时，这些卡缺部件不能算成「没有游戏就开不了」。
- **开卡时才缺的部件**：卡里有资料，却开不出来（严格开卡回报缺口，而且那条缺口不在卡的 `okAb` 里）。
  这才是 bug，违反 OK 卡自带资源的契约。
载入中那张显示 Slate 载入框（「載入場景」、进度条、「已建 n / 共 n 個物件」）。
SD42 另外用 1024×576 窗口开一次，载入框完整没被裁掉（`big-small-sd42_SD42 full_loading.png`）。
那次的建构阶段场景名是空的，因为匯入的场景在存档前没有自己的档名；已改成沿用匯入时的场景名。
量的时候机器上同时还有别的 Unreal（slot 机制下另一格），`ready_ms` 只能当参考。

## 还没看的

- `character_open_ms` 约 9.8 s（以原作卡开那 4 位角色，在 worker 上）。
- `OKSceneActor.cpp` 的 `EditTexture`：改成只解码一次、快取键改用 CityHash，并加了 `OK_EDIT_TEXTURE_OLD=1` 关闭开关。
  代码已在 `496dabade`（共用工作树被一起提交）。63-2 冷开交错 A/B 三轮（机器上同时有别的 Unreal）：

  | | `build_ms` 第 1／2／3 轮 | `ready_ms` 第 1／2／3 轮 |
  |---|---|---|
  | 新 | 7 269 / 7 755 / 5 878 | 27 224 / 33 135 / 23 750 |
  | 旧（`OK_EDIT_TEXTURE_OLD=1`） | 6 236 / 9 500 / 5 462 | 25 566 / 29 180 / 21 439 |

  **量不出差别**：同一模式轮与轮之间就差 2–4 s，比 63-2 那 143 张贴图省下的解码时间大得多。
  改动保留，开关也还在，但不能写成「变快了」。第 2 轮两边的成品截图（`etx-63-new-2_63-2_pass0.png`／`etx-63-old-2_…`），
  动画时刻不同，不能逐像素比；看得到的 MaterialEditor 贴图（左上角的文字看板）两边一致。
