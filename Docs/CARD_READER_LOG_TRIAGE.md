# 读卡器 log 的警告与错误盘点（2026-11-19）

使用者要求「一直出现错误，只是没崩也要修正」。这份是 `CardReaderDevelopment.cmd` 走完一轮正常操作后，
log 里**每一条** `Error` 与 `Warning` 的逐条判定：是真缺陷就修（或指名由谁修），是既存外部噪声就写明为什么不修。

量测用的两份 log（本机，`Saved/Logs/CardReader/`）：

| log | 做了什么 | Error | Warning |
|---|---|---:|---:|
| `20261119-012753-256a5055.log` | 开 3 张卡、换服装、播动画、切物理、走 DreamGUI 分页 | **GPU hang 一次**（下面 1.） | 24 |
| `20261119-013525-157b894a.log` | 同上再加 8 轮分页狂切、3 轮换卡换服装换动画 | 1（下面 2.） | 23 |

「走完一轮正常操作后 log 里没有 Error」的目标，现在卡在两条：一条是真缺陷（1.），一条是编辑器版才有的外部外挂噪声（2.）。

## 1. GPU hang：DreamGUI 的 UI 算绘通道（**真缺陷，归 DreamGUI 那边修**）

`20261119-012753-256a5055.log`：

```
LogD3D12RHI: Error: GPU crash detected:
	- Device 0 Removed: DXGI_ERROR_DEVICE_HUNG
LogD3D12RHI: Error: PageFault: PageFault at VA GPUAddress "0x25C36E1000" (GPU 0)
```

Aftermath 的 dump 指名**片段着色器存取记忆体时 MMU fault**：

```
"Faulted Warps": [{ "Fault Description": "A shader instruction caused an MMU fault when accessing memory.
                     This can be caused by shader bugs and binding setup issues.",
                    "Fault Name": "MMU Fault Error",
                    "Shader GPU PC Address": "fragment_02 @ 0x00045f90" }]
```

GPU breadcrumb 指出卡在哪一段：场景本身（BasePass→PostProcessing→SMAA）全部 `Finished`，
还在 `Active` 的只有

```
Frame 55069 → SceneRender - ViewFamilies → RenderGraphExecute → Scene
  → FrameRenderFinish → RenderFinish → ViewFamilyExtension(3) → ViewExtension(0)   [Active]
```

`ViewFamilyExtension → ViewExtension` 这一段就是 **DreamGUI 的 scene view extension**
（`Plugins/DreamGUI/Source/DreamGUIRenderer/Private/DreamUIRender/DreamUIRenderer.cpp`
的 `FDreamUIRenderer::PostRenderView_RenderThread`）。片段着色器的 MMU fault 典型成因是
**绑到了已经释放或还没写好的 GPU 资源**（图集、instance buffer、draw call buffer）。

发生当下在做的事：连续切 DreamGUI 分页与分类（`ok.ReaderScreen press`），也就是
`UOKReaderScreen::Mirror` 整段重建镜像控制项的时候——重建发生在游戏执行绪，而 render thread
同一时间还在用上一批 draw call 资源，这是最像的方向（和先前记录过的
`DreamCanvasDrawCallProcessingRunnable` 相关崩溃同一区）。

**重现状况**：目前 1/3。同一套操作之后又跑了 8 轮分页狂切＋3 轮换卡换服装换动画都没再出现，
所以还不是稳定重现，但 dump 与 breadcrumb 已经把范围缩到上面那一个 pass。
DreamGUI 与读卡器画面是 e-fork-2 的档案，这条已经连同上面的证据转给它修。

## 2. `LogUIActionRouter: Error: Using CommonUI without a CommonGameViewportClient derived game viewport client`（编辑器版才有的外部外挂噪声，不修）

- 来源是 **CommonUI 外挂自己印的**，不是本专案的程式。
- 本专案没有用到 CommonUI：`OpenKoikatsu.uproject`、`Config/DefaultEngine.ini`、各模组的 `.Build.cs` 都没有提到它。
  启用它的是本机商用编辑器外挂 `BpGeneratorUltimate`（`BpGeneratorUltimate.uplugin` 里
  `"Name": "CommonUI", "TargetAllowList": ["Editor"]`），而那个外挂的内容不进版控（见 AGENTS.md）。
- 因为 `TargetAllowList` 只有 `Editor`，**非编辑器的游戏建置根本不会载入 CommonUI**，这条也就不会出现；
  它只出现在 `CardReaderDevelopment.cmd` 这种用编辑器跑 `-game` 的开发版。
- 不能靠换 viewport client 消掉：CommonUI 要的是 `UCommonGameViewportClient` 的子类，
  而读卡器需要的是 DreamGUI 的 `DreamGameViewportClient`（`Config/DefaultEngine.ini`），
  C++ 单一继承下两者不可兼得；2026-11-18 的对照验证也记过，**换成 DreamGUI 的 viewport client 之前这条就已经在**。
- 在专案层把 CommonUI 关掉会让 `BpGeneratorUltimate` 在编辑器里载入失败，代价比这行字大。

## 3. Warning：都是外部与编辑器专用的噪声（不修）

| 条目 | 次数 | 为什么不修 |
|---|---:|---|
| `LogEditorDataStorageUI: Unable to register widget factory '…' as purpose '0' isn't registered.` | 21 | 引擎 Editor Data Storage 的 UI 工厂在 `-game` 模式下没有注册 purpose，全部是引擎自己的建构子（AssetName、DiskSize、Outliner…），本专案没有参与。非编辑器建置没有这个模组。 |
| `LogTextureGraph: Warning: serialize Var v-1: NOT FOUND for None` | 1 | 引擎 TextureGraph 外挂启动时的自身讯息，本专案没有 TextureGraph 资产。 |
| `LogCEF3Utils: Warning: Failed to backup cef3.log` | 1 | 引擎内建浏览器的 log 轮替，和读卡器无关。 |
| `LogWindows: Failed to load 'VtuneApi.dll' / 'aqProf.dll' / 'WinPixGpuCapturer.dll'` | 4 | 不是 Error／Warning 等级，是引擎找不到选用的外部量测工具；装了才有。 |
| `LogTemp: Error test: UE::UnifiedErrorTest::…` | 5 | 引擎自己的错误型别自我测试，字面有 `Error` 但不是错误等级，`grep ": Error:"` 不会命中。 |
| `LogRHICore: Error: Shader debug data not found (<hash>)` | 12 | 只在 1. 的 GPU crash dump 展开时出现（Aftermath 想把着色器位址对回原始码），不是独立缺陷，1. 修好就不会有。 |

## 怎么重跑这份盘点

```powershell
.\Tools\ok-game-mcp\target\release\ok-game-mcp.exe call reader_launch '{\"lane\":\"log-triage\",\"no_build\":true}'
```

开几张卡、换服装、播动画、走一遍分页，然后：

```powershell
Select-String -Path (Get-ChildItem E:\OpenKoikatsu\Saved\Logs\CardReader\*.log | Sort-Object LastWriteTime | Select-Object -Last 1) -Pattern ': (Error|Warning):'
```

同一台机器上可能有别组的读卡器在跑：`ok-game-mcp` 会说 `ambiguous_target`，用 `OK_GAME_PID=<自己的 pid>` 指定，
**不要停掉别人的行程**。
