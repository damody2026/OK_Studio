# 读卡器低记忆体模式全跑（2026-11-18）

F 组 f-yvonne。验的是低记忆体模式（RAM < 48 GB 或 VRAM < 20 GB 自动开，或 `-OKLowMemory`）下贴图「上传后丢像素」的两个修正：

- E 组 `4e9a7ebe3`：调色 LUT 建立时就设好设定，只上传一次。之前第二次上传是空的，整个画面全黑。
- C 组 c-lowspec `fa8bb92a4`：执行期贴图的像素改到上传那一帧结束才丢（`OKDropRuntimeTexturePixelsAfterFrame`）；之后几帧才改设定的地方先从 GPU 读回（`OKRestoreRuntimeTexturePixels`）。瞳孔去高光（`OKIrisWithoutHighlights`）因此不再变白眼。

## 先看这段：全跑证明了什么、没证明什么

**读卡器的「载入 + Demo：蹦跳」全跑，根本不经过「建好 → 改设定 → 再上传」那条路径。**
证据：用测试开关 `kk.RuntimeTextureDropAtUpload=1` 把旧 bug 放回去（像素在上传当下就丢；用读卡器的主控台确认值为 1），照样跑 C031 的全跑，结果是 pass，BulkData 错误 0。旧 bug 回来了，全跑却看不到。

所以两件事要分开讲，由不同的检查证明：

| 要证明的事 | 由谁证明 | 结果 |
|---|---|---|
| LUT 修正有效、低记忆体模式整体没有退步 | 53 张全跑（`-OKLowMemory`） | 53/53 pass |
| 帧结束才丢像素的机制本身（去高光瞳孔不变白） | `ok.VerifyEyeDull` 的阳性对照 | 开关 1：3/3 失败；开关 0：3/3 通过 |

**「全跑过了」不等于「这类 bug 不会再发生」**。这个 bug 当初就是这样逃掉的：开发机记忆体大，不进低记忆体模式；就算进了，读卡器的一般流程也不经过出问题的路径。改到贴图上传、低记忆体相关的程式，要跑 `VerifyEyeDull`（低记忆体），不能只跑全跑。

## 结果

### 阳性对照：`ok.VerifyEyeDull 0 3`（`-OKLowMemory`，C000–C002）

| 开关 `kk.RuntimeTextureDropAtUpload` | 判定 | BulkData 错误 | 去高光造成的变化 hi | iris_px |
|---|---|---|---|---|
| 1（旧行为） | 3/3 失败 | 30 | 5454–9809 | 3078–4929 |
| 0（现行） | 3/3 通过 | 0 | 381–703 | 6879–12131 |

开关 1 的 sheet（`Saved/Tests/EyeDull/20261118-035029/sheet_00.png`）：去高光后瞳孔整个消失、眼睛全白，就是 11-18 使用者踩到的 bug。审核新增的「瞳孔还在」判定（`fa8bb92a4`）在该失败时确实失败。

开关的第一版用 `RemoveBulkData`，在编辑器建置里留下 0 大小的 mip，重建贴图时 assert（Array index out of bounds），还没跑到判定就崩溃了；改成「设 SingleUse 后 `GetCopy(discard)` 一次」，和当年第一次上传时做的事一样（`0f778eeac`）。

### 全跑：`Tools/reader_jump_check.lua --extra "-OKLowMemory"`，53 张

- 53/53 pass：每张 `lowmem=on`，日志 BulkData 错误 0，截图「整片黑／整片白／只剩背景」判定 0。
- C046 第一次读卡器启动卡在 "Waiting for ZenServer to be ready"，载入 8 次都是 busy。这是环境问题，重跑通过。工具改成把这种情况记为 `env`，并换新读卡器重试一次（`f8d5d0ff1`）。
- 中间为别组的独占量测暂停三次（整合 #16、c-lowspec 两次），从断点续跑。
- 已知未解：开关 1 跑 C041 时，读卡器（pid 17860，08:55:06）在 MCP views 操作中途消失。日志没有错误也没有退出讯息，
  Saved/Crashes、WER、Windows Application／System 事件记录都没有纪录。runner 只在卡跑完后、或已判定读卡器不在时才关行程；
  e-fork-2 查过它没碰过这个 pid。原因未明。C041 的开关 1 没重跑（C031 与 VerifyEyeDull 已足以证明）。

### 「该有的东西不见了」：`image_diff`／`Tools/reader_jump_compare.lua`

整片黑白判定抓不到「一小块不见了」（白眼），所以加了逐区块像素差（`76f150ad1`）。

- 阳性对照：眼睛审核 sheet 开关 1 对开关 0，最差区块 172.5，正落在瞳孔，变化超过 80 的像素 17542；两次开关 0 互比，最差区块 0.5。
- 低记忆体全跑对 11-16 旧图，只比静止的 LIGHT 视图（`e10f17190`；起跳中的视图每轮落在不同帧，不能比）：最差的区块都在眼睛，C083、C069、C045、C041、C038、C070、C040 是眨眼的时间点不同（区块差 35–110），放大图逐张看过，瞳孔都在；其余是裙摆、512 上限造成的细节变软（≤ 30）。
- 限制：单张截图里，眨眼和瞳孔消失分数可能一样，分数只负责排序，前几名要看放大图。

## 档案

- 报告与截图：`Saved/Reports/reader-jump-20261118-lowmem/`（`full_low.txt`、`full_drop.txt`、`img_*`、`cmp_low_vs_1116/`、`README.txt`）。本机产物，不进版控。
- 一般模式对照（同 53 张，不加 `-OKLowMemory`）：**只跑到 26/53，全部 pass**（lowmem=off，BulkData 0，图片判定 0），
  15:1x 因 C／E／F 整合全部暂停。第 23 张起用的是 12:19 f-sceneload 重新连结的编辑器 DLL（它只改 OKStudio 量测，读卡器路径没动）。
  剩下 27 张（cards53.txt 第 26 号起）与「低记忆体对一般模式」的 `reader_jump_compare.lua` 比对、`--lighting` 光影检查（C031／C044／C048）
  整合后再跑：`Tools\lua\lua.exe Tools\reader_jump_check.lua --out …\full_norm.txt --list …\cards53.txt --from 26 --lane norm --fair`。
