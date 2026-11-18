# 读卡器全卡回归：30 张测试卡逐张走一遍新版 UI（2026-11-19，E 树）

对象：`E:\OKPackage\TestCards-20261118` 的 30 张卡，用 `CardReaderDevelopment.cmd` 那一套（新版 DreamGUI 画面，预设开启）。
目的：新版 UI 刚换过一批修正（`FinishLoad3D` 失败回退、动作选单回退、字型图集、控制项路径），需要有人用**使用者的操作方式**
整批走一遍，而不是只看单元测试。

**一句话结论：30 张全部开得起来、切服装与切动画都正常、四个外观分页都打得开，卡本身没有一张有问题；
但整批连开的过程中 GPU 卡死（`DXGI_ERROR_DEVICE_HUNG` ＋ PageFault）**两趟都重现了**，一趟开到第 12 张、
一趟开到第 16 张。那是现在读卡器最大的一个问题，而且不是某张卡的问题。**

## 一、怎么走的（可以照着重跑）

每张卡：卡墙上点它 → 开卡（载入 3D）→ 切到「服裝 2」→ 切动画「Demo：站立 01」→ 开四个外观分页
（臉／頭髮／衣服／配件）→ 下一张。每张记下：开得开不开、切服装与动画的结果、分页开不开、
以及**这张卡期间** log 新增的 `Error:`／`Warning:`（按 log 的位元组位移切段，不把前一张的算进来）。

驱动脚本（本机，不进版控）走 `ok-game-mcp`：`ui_exec ok.ReaderScreen tab 1` / `card <N>` 点卡墙，
`reader_call load` 开卡，`reader_call control_set` 切服装与动画（`control.OutfitCombo`／`control.GameClipCombo`），
`ui_exec ok.ReaderScreen category <名>` 翻外观分页。全程 `OK_GAME_PID` 锁自己的行程。

**方法上的一个坑，记下来免得下一个人再踩**：`ok.ReaderScreen card <N>` 只是**点选**那张卡，
名字与 `state.card` 会换，**3D 模型不会重开**（要再按「载入 3D」）。第一趟三十张就是这样跑的，
每一项都「通过」，其实全是对着第一张的模型做的——是**截图**才看出来：名牌写着 Raiden Shogun，
人还是 crowd_C001 那套制服。第二趟改成每张都真的开卡，并用 **`state.session` 有没有换**当「真的重开过」的讯号
（点卡不会换 session，开卡会）。**数字是真的、代表的不是那件事**，又一例。

## 二、结果（30/30）

| # | 卡 | 开卡 | 切服装 | 切动画 | 外观分页 | 这张卡期间的 Error |
|---:|---|---|---|---|---|---|
| 0–9 | crowd_C001／C006／C011／C020／C033／C049／C055／C068／C077／C090 | 全开 | 服裝 2 | 播放中 | 四个都开 | 0 |
| 10–24 | demo_C050、demo_Male01、heroine_alice／hu_tao／jeanne／keqing／klara／march_7th／megumin／raiden_shogun、kks_anwa_subaru／CharacterExport_Female／F_20240615／haruno_chika／KK_402071 | 全开 | 服裝 2 | 播放中 | 四个都开 | 0 |
| 25–29 | kks_Saria、ref_lan／luo_tianyi_2024／luo_tianyi_ai／qiu_wuji | 全开 | 服裝 2 | 播放中 | 四个都开 | 0 |

目视抽查（截图，本机不进版控）：crowd_C001、heroine_raiden_shogun、kks_Saria、ref_qiu_wuji、demo_Male01
都是完整的人（头发、衣服、鞋、配件都在，没有缺件、没有穿模、贴图没黑掉）。

## 三、唯一的真问题：整批连开会 GPU 卡死（两趟两次）

| 趟 | 开到第几张卡时卡死 | log | 当时 |
|---|---|---|---|
| 第二趟 | **12（heroine_alice）**，前面 12 张都正常 | `Saved/Logs/CardReader/20261119-040447-6b373d85.log` | 开卡后约 5 秒 |
| 第三趟 | **25（kks_Saria）**，前面 16 张都正常 | `Saved/Logs/CardReader/20261119-043208-07a5f53e.log` | 同上 |

两次的签章一样：`LogD3D12RHI: Error: GPU crash detected: Device 0 Removed: DXGI_ERROR_DEVICE_HUNG`，
伴随 `PageFault: PageFault at VA GPUAddress ...`、`DRED: No breadcrumb head found.`，
crash dump 在 `Saved/Crashes`（`UECC-Windows-*`）。行程**不会自己结束**：视窗还在、控制通道还在听，但不再回应——
正是 `Tools\ok_hang_check.lua` 认得的那个样子（它两次都判对了），两次都是我自己用 `reader_stop` 结束的。

**不是某张卡的问题**：alice 与 Saria 在新开的读卡器上各自单开都好好的（alice 连开三次都没事），
而两趟卡死的卡不一样。形状是**连开十几张之后才发生**，和 2026-11-18 在 DreamGUI 算绘通道抓到的那次
（[CARD_READER_LOG_TRIAGE.md](CARD_READER_LOG_TRIAGE.md)、[CARD_READER_DREAMGUI.md](CARD_READER_DREAMGUI.md)）是同一类。
以前只有 1/3 的重现率、没有触发条件；**现在有了可重复的作法：拿这 30 张连着开，十几张之内就会中。**

**这条属 e-fork-2 的档案**（DreamGUI 与 `OKReaderScreen.cpp` 的算绘路径），已把两份 log 与 dump 留着。

## 四、其他观察（都不挡事，但记着）

- `LogStreaming: Warning: Failed to read file '' error.`：第一、二趟各出现 326／107 次，**第三、四趟一次都没有**。
  候选原因是缩图贴图建出来没设 `NeverStream`（`Source/OpenKoikatsu/OKReaderScreen.cpp` 的 `MakeTexture`，
  对照 `KKTextureRuntime.cpp` 的 `OKApplyRuntimeTextureSettings` 有设），**但没证实**——真是它的话不该有「某几趟零次」。
  要查的人先量「翻外观分页时会不会稳定冒出来」，再决定。属 e-fork-2 的档案。
- `LogUIActionRouter: Error: Using CommonUI without a CommonGameViewportClient`：每次启动一行，是既有的外部噪音，
  已经在 [CARD_READER_LOG_TRIAGE.md](CARD_READER_LOG_TRIAGE.md) 记过，不是这批改动带来的。
- `Performance warning: Many (31) failed FindConsoleObject()`：偶发一行，查的是不存在的 cvar 名称，无害。
- 外观分页目前只有四个名字吃得到（臉／頭髮／衣服／配件）；`身材`、`表情`、`骨骼`、`風格` 这些名字 `ok.ReaderScreen category`
  会回 failed，不知道是没有那几页还是名字不同，没有深究。

## 五、给下一个人

- 重跑这一轮：启动器带 `-CardDirectory=E:\OKPackage\TestCards-20261118`，然后照第一节的五步逐张走；
  **记得用 `state.session` 确认每张都真的重开过**。
- 要抓 GPU 卡死：直接连着开这 30 张，十几张内就会中；中了之后**不要关视窗**，先跑
  `Tools\lua\lua.exe Tools\ok_hang_check.lua`（会印出 log 与 dump 在哪），把那两样留着再
  `ok-game-mcp call reader_stop '{"pid": N}'`。
