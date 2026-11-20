# 引擎補丁清單

本專案使用的引擎是 `E:\PhysX\UE5.8`，分支 `UE5.8-physX-5.11-ok`（[damody2026/UnrealEngineOK](https://github.com/damody2026/UnrealEngineOK/tree/UE5.8-physX-5.11-ok)，需先把 GitHub 帳號綁定 Epic Games 帳號才看得到）（5.8.4 + GameWorks Flex / PhysX 5.11）。
下列補丁都要以 commit 形式存在於這個分支上。來源是原本 `D:\UE5.8`（分支 `5.8`）的本機 commit，用 `git format-patch` 加 `git am -3` 搬過去。

| 引擎 commit 主旨 | 給本專案的作用 | 標記（`OpenKoikatsu.Build.cs` 會檢查） |
|---|---|---|
| 修正 Hot Reload 只收集目前專案的 DLL 模組 | 熱重載 | — |
| 修正渲染執行緒上反射捕獲淡入的時鐘來源 | 反射捕獲 | — |
| 為位元壓縮動畫加入可選的常數縮放軌快取 | 群眾動畫解碼（`ConstantScaleCache.patch`） | `PrepareAnimConstantScaleCache` |
| 允許單節點骨骼元件使用加權骨骼階層作為 RequiredBones 種子 | 群眾 RequiredBones（`WeightedRequiredPoseSeed.patch`） | `SetSkeletalWeightedPoseSeed` |
| 為 CPU 蒙皮矩陣加入可選的逐位元重用快取 | 群眾蒙皮矩陣（`ExactComponentMatrixCache.patch`、`ExactRefToLocalMatrixCache.patch`） | `GetSkeletalComponentMatrixCacheStats`、`GetSkeletalFullRefMatrixCacheStats` |
| 讓骨骼除錯姿勢複本可跳過，並修正跟隨者的複製範圍 | `LeanDevelopmentDebugPose.patch`、`../Patches/DevelopmentFollowerLocalDebug.patch` | — |
| 以執行緒群組重排非 Nanite 虛擬陰影的每頁繪製命令 | `VsmQueueReuse/` | — |
| 新增非 Nanite 虛擬陰影的平行繪製開關 | `../Patches/ParallelVirtualShadowDraw.patch` | — |
| 新增動畫庫的完整蒙皮矩陣計算著色器 | `../Patches/MatrixBank/` | — |
| 不透明 base pass 可依 primitive 的 TranslucencySortPriority 排序（`r.OK.OpaqueSortPriority`） | 重合服裝層（Material Editor 複製材質、重複飾品）照 Unity 繪製順序，不再閃爍（`OpaqueSortPriority.patch`，見 [計畫](../../Docs/OPAQUE_DRAW_ORDER_ENGINE_PLAN.md)） | `OKOpaqueSortPriority` |
| GPU 蒙皮 morph 雙緩衝：目前緩衝尚未寫入時改讀有資料的緩衝，不再 check 失敗 | OK Studio 載入場景時偶發 `Assertion failed: Index == 1`（`FMorphVertexBufferPool::GetReadingIndex`）當機（`MorphDoubleBufferRead.patch`） | — |
| D3D12：online view descriptor 區塊回收時清成 null 描述子（`D3D12.ClearRecycledOnlineDescriptors`，預設 1） | 讀卡器連續開卡的 `LogD3D12RHI: Error: PageFault`（DreamGUI `MainPS`）：online heap 沒被寫到的格子留著很久以前的 SRV 描述子，NVIDIA 硬體會讀綁定表附近、著色器不取樣的描述子，指到已交回的 pool heap 就是裝置移除。清空後 heap 裡沒有比區塊這次使用更舊的描述子（`ClearRecycledOnlineDescriptors.patch`，見 [查找紀錄](../../Docs/CARD_READER_GPU_PAGEFAULT_SLOTS_20261120.md) 第 10 節）。取代先前的止血 `RetainEmptyPoolHeaps.patch`（已撤回） | — |
| D3D12：可選的 SRV 槽位有效性檢查（`D3D12.OK.ValidateSRVSlots`，**預設 0**） | 讀卡器的 GPU 頁錯誤診斷與干預（`ValidateSRVSlots.patch`，見 [記錄](../../Docs/CARD_READER_DREAMGUI.md) 與 [排除清單](../../Docs/CARD_READER_PATH_EXCLUSIONS.md) 第二十八、二十九條）。**三棵樹共用同一個引擎 checkout，所以這個補丁三組都會拿到**；關著時只多一個 bool 測試，行為與未套用時相同 | — |
| D3D12：回收 online descriptor 區塊時可選的下毒（`D3D12.OK.PoisonRecycledDescriptorBlocks`，**預設 0**） | 讀卡器 GPU 頁錯誤的「描述子副本」那一格（`PoisonRecycledDescriptorBlocks.patch`）：`Recycle` 把區塊推回 `FreeBlocks` 前填成 NullSRV，栅欄正確時看不出差別。**三棵樹共用同一個引擎 checkout** | — |

**`ValidateSRVSlots.patch`（2026-11-20，診斷用）**：SRV 狀態快取存的是裸、不持有的指標，建表時整個範圍一起重抄，
而 `~FD3D12Texture` 完全沒碰狀態快取（`ConditionalClearShaderResource` 只在緩衝區、RT 設定與 UAV 的路上被呼叫）。
開著時每個 view 向登記表報到，`BuildSRVTable` 在解參照前問「它還活著嗎」，死的就印 stage／slot／指標並換成 null view；
另有到達證據（第一次檢查與每四百萬次各印一行），所以「沒印出 stale」能和「檢查沒跑」分開。
**它看得到「view 物件沒了」，看不到「view 活著但資源死了」。** 查完若沒有用，連同這一列一起移除。

**`PoisonRecycledDescriptorBlocks.patch`（2026-11-20，診斷用）**：GPU 讀的是 `BuildSRVTable` 抄進 online heap 區塊的
那份描述子**副本**，不是狀態快取裡的裸指標（狀態快取兩半都量過、各自零次）。區塊經
`FreeHeapBlock` → `DeferredDelete` → EOP `Recycle` 交回，若栅欄沒涵蓋用過那張表的 command list，
區塊可能在 GPU 還讀著時被重用。開著時 `Recycle` 先把整個區塊填成 NullSRV。
**只涵蓋走 `Recycle` 的區塊**：不涵蓋 `FD3D12LocalOnlineHeap` 的溢出堆、全域取樣器堆、
以及區塊還被持有時槽位在區塊內重新發出的情形。查完若沒有用，連同那一列一起移除。

不搬的項目：
- `BitwiseDecodeScopes.patch`：只加 profiler 範圍，D: 也沒有套。
- D: 上 5 個「記錄 … 覆蓋層路徑」的 commit：只記錄 D: 本機的私有 staged 引擎，不適用。

建置時任何一個標記找不到，`OpenKoikatsu.Build.cs` 會直接讓建置失敗。以前會默默變成 0，群眾變慢卻沒有任何錯誤。
用原版引擎做實驗時，可以設 `OK_ALLOW_UNPATCHED_ENGINE=1` 放行。

換新的引擎版本時，照這張表重做一次：

```
git -C <舊引擎> format-patch -o <dir> <base>..<tip>
git -C <新引擎> am -3 <dir>/*.patch
```
