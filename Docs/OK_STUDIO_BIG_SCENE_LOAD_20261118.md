# 很大的原作场景卡：冷开变快（2026-11-18，F 树，f-studio-ui，进行中、暂停）

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

## 第二处（已改原始码，**没编译、没量测**，等协调者放行）：贴图搬出场景 JSON

63-2 的 365 MB JSON 里 359 MB 是 MaterialEditor 道具贴图的 base64 PNG（200 处，去重后 270 MB）；
SD42 full 是 142 MB base64、去重后 15.5 MB；65 是 130 → 46.5 MB。

- `studio_scene.rs`：`export()` 结尾 `texture_edits_to_files`：每张不同的贴图写成卡目录里的 `mat_<sha256 前 10 位元组>.png`，
  JSON 的 `text` 换成 `file`。关闭开关 `OK_SCENE_TEXTURES_INLINE=1`。附 `unbase64` 与往返测试。
- `OKStudioImport.cpp`：读 `file`，每个档案只编码一次 base64 进 `Edit.Text`（文件格式不变），读完删掉那些档案。

预期拿掉「导出跑两次」与大部分 JSON 解析（63-2 约 5 s）。改了共用的 `Tools/ok-extract`，提交前要跑
`cargo check`（含 `--no-default-features`）并实际建置游戏与编辑器两个目标。

## 还没看的

- `character_open_ms` 约 9.8 s（以原作卡开那 4 位角色，在 worker 上）。
- `OKSceneActor.cpp` 的 `EditTexture`：每次都对整串 base64 算 MD5，并把同一张 PNG 解码两次（sRGB 与 linear）。
- 其余五张场景还没在 UE 里量。
