# 讀卡器 GPU PageFault：DreamGUI 貼圖槽判別與讀碼結論（2026-11-20，C 樹）

接續 [交接文件](CARD_READER_GPU_PAGEFAULT_HANDOFF_20261120.md)（第 1–9 節）。這份記 2026-11-20 09:50–12:10 在 C 樹（`C:\portable\OpenKoikatsu`，引擎 `D:\PhysX\UE5.8`）做的判別實驗與之後的純讀碼結論。

**一句話（已解，見第 10 節）**：根因在引擎 D3D12RHI。online descriptor heap 的格子被重複使用時不清空，沒被這一輪寫到的格子會一直留著很久以前的 SRV 描述子。NVIDIA 硬體會讀綁定表附近、著色器根本不取樣的描述子，其中一個若指向已交回的 pool heap，就是裝置移除的 PageFault。修法是每塊 online 區塊從 GPU 回來時清成 null 描述子（引擎補丁 `ClearRecycledOnlineDescriptors.patch`）。DreamGUI 的 Main 槽每筆 draw 換貼圖、每筆 draw 都重建表，所以最常踩到，但 DreamGUI 本身沒有錯。

第 1–9 節是查找過程（當時的結論，部分已被第 10 節推翻）。

## 1. 背景與止血狀態

- 第 9 節的止血（`D3D12.OK.RetainEmptyPoolMB=2048`，D: 引擎 `3bcd76878bef`、專案 `d1cdae0e9`）已撤回：引擎 `db4ae5671283` revert，專案 `Config/DefaultEngine.ini` 那行已刪，改用第 10 節的根因修正。查找期間所有實驗都在啟動後把它設回 0，讓故障看得見。
- 曾把同一補丁套到 E 引擎（`E:\PhysX\UE5.8` `1de8c76d7f57`），使用者表示要修根因後已用 `f70800f9510d` revert 撤回，E 引擎程式碼等同原狀。E 專案 `Config/DefaultEngine.ini` 的改動也已還原。

## 2. 實驗方法

- 驅動：`Saved/Reports/card-reader-pagefault-slots/ext60slots.lua <名稱> <輸出資料夾> <FallbackSlots> [額外主控台指令]`（環境變數 `OKEXTRA` 可給 `reader_launch` 的 `extra`）。逐張 `reader_call load` 開 `E:/OKPackage/ext60` 六十張卡；每張後查程序存活與 log 的 `PageFault`／`GPU crash` 等字串，出事就 `reader_stop` + `taskkill`；開完再空跑兩分鐘。
- 到達證據：每趟啟動後用 `ui_exec` 回讀 `D3D12.OK.RetainEmptyPoolMB`（必為 0）與 `DreamGUI.Experiment.FallbackSlots`；渲染端第一次讀到新值時印 `DreamGUI FallbackSlots now N`。
- 每趟報告：`Saved/Reports/card-reader-pagefault-slots/<名稱>.txt`（最後一行有 `verdict=`、`opened=`、遊戲 log 路徑）。
- 所有故障趟都核對過：`Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF`、`Found 0 active heaps`，與原本的故障相同。

### 實驗旋鈕 `DreamGUI.Experiment.FallbackSlots`（位元遮罩，預設 0，`DreamUIRenderer.cpp` 的 `DrawBuiltInBatch`）

| 位元 | 作用 |
|---|---|
| 1 / 2 / 64 / 128 / 256 | Main / Font / Mask0 / Mask1 / SceneDepth 綁各自的全域備援貼圖（`GWhiteTexture` 等） |
| 4 / 8 / 16 / 32 | WidgetData / ClipData / RectBlock / PaintData 綁備援（會改變著色器分支，判讀時不用） |
| 512 | 只有 Main 是動態圖集頁時才換成備援 |
| 1024 | 只有 Main 不是圖集頁時才換成備援 |
| 2048 | 所有槽在 render thread 先把 `FRHITextureReference` 解成實際 RHI 貼圖再綁 |
| 4096 | Main 固定綁第一次看到的 `DreamUIPreset_WhiteSolid`（真的 pool 貼圖、經 texture reference） |

開 512/1024 時會印 `DreamGUI Main texture seen: <名字> <寬>x<高> atlas=<0/1>`（每個名字第一次出現時）。

## 3. 結果

| 臂（FallbackSlots） | 趟數 | 結果 | 故障卡序 |
|---|---|---|---|
| 0（對照） | ctrl0-trip1、trip2 | 2/2 故障 | 39、13 |
| 451（Main+Font+Mask0+Mask1+SceneDepth 全換） | 3 | **3/3 開完 60 張** | — |
| 1（只換 Main） | 3 | **3/3 開完 60 張** | — |
| 450（換 Main 以外那四個影像槽） | 3 | 3/3 故障 | 57、26、13 |
| 512（只在 Main 是圖集時換） | 1 | 故障 | 9 |
| 1024（只在 Main 不是圖集時換） | 1 | 故障 | 41 |
| 2048（render thread 先解 reference） | 3 | 2/3 故障 | 13、49（trip1 開完） |
| 4096（Main 固定為 DreamUIPreset_WhiteSolid） | 1 完成 | 1/1 開完 60 張 | —（trip2 中途斷掉，不算） |
| 0 ＋ `D3D12.OK.CheckDescriptorBytes 1` | 2 | 2/2 故障 | 12、12 |
| 0 ＋ `D3D12.OnlineDescriptorHeapSize=1000000`、`BlockSize=20000` | 3 | 3/3 故障 | 12、12、12 |
| 0 ＋ rename 記錄 ＋ `D3D12.TrackAllAllocations=1` | 1 | 故障 | 56 |

512 與 1024 兩臂各只跑一趟就停：兩個子集都已出現故障，答案已定。

### Main 槽實際綁過的貼圖（512、1024 兩趟整趟記錄）

- `DreamUIDynamicSpriteAtlasData_Texture_0` 2048×2048（動態 sprite 圖集）
- `DreamUIPreset_WhiteSolid` 4×4
- 19 張 `Texture2D_N` 288×402：讀卡器卡片列表的縮圖，`OKReaderScreen.cpp` 的 `ThumbPool`，整個讀卡器執行期間都不釋放（`OKReaderThumbs::Refill` 只用 `UpdateTextureRegions` 重填）

**一張角色貼圖都沒有**，三類全都一直活著。這修正了先前「Main 只出現 Dream 自己貼圖」的說法：縮圖是直接綁進 Main 的，沒有經過圖集。

### 開著配置追蹤的那次故障（`Saved/Logs/CardReader/20261120-115446-08036804.log`）

- 故障位址 `0x263A081000`，落在 `Texture2D_3340`（1024×1024 B8G8R8A8，含 mip，5.38 MB，`[0x2639D00000 .. 0x263A260000]`）。
- 時間：貼圖在第 44095 幀釋放，那塊 64 MB `PoolAllocator Heap` 在第 44117 幀交回，故障在第 44119 幀。
- 同一段位址先前住過 `Texture2D_1586`（第 34577 幀釋放），配置位置完全一樣。
- 「故障位址前後 16 MB 內沒有任何活著的資源」，所以不是活貼圖越界讀進相鄰配置。
- GPU 最多落後幾幀，而讀取發生在貼圖釋放後 24 幀：**這筆讀取是在貼圖釋放之後才錄製的。**

## 4. 量測排除的引擎層

| 假設 | 怎麼排除 |
|---|---|
| 某張活貼圖的**離線 SRV 描述子位元組**被別人改寫（離線槽重複發出等） | D: 引擎診斷 `D3D12.OK.CheckDescriptorBytes`：每個 view 寫描述子都會讓 `OfflineCpuHandle` 版本號加一；在 `BuildSRVTable` 抄表前比對 32 位元組，版本沒變、位元組卻變了就記一次。兩趟約 820 萬、1260 萬次比對，**0 次不符**，故障照樣在第 12 張 |
| 活貼圖的 view 被 **rename／搬家**到角色貼圖的位置 | `TD3D12View::ResourceRenamed` 每次都記 `OK view renamed`：整趟 **0 次** |
| online descriptor heap **區塊換手**（RollOver／回收時機） | 總 heap 1,000,000、區塊 20000（原本 2000），換手少一個數量級：3/3 照樣在第 12 張故障，時機完全沒變 |
| 經 `FRHITextureReference` 綁定（RHI 執行緒才解開） | 2048 臂：render thread 先解開，2/3 照樣故障 |
| 縮圖或圖集**單獨**是兇手 | 512、1024 兩臂都故障 |

## 5. 純讀碼確認沒問題的部分（引擎 `D:\PhysX\UE5.8\Engine\Source\Runtime\D3D12RHI\Private`）

- **離線描述子配置** `FD3D12OfflineDescriptorManager::FreeHeapSlot`（`D3D12Descriptors.cpp:411`）：重複釋放會打到 `check`；Development 的 `check` 是開的。
- **SRV 設定** `FD3D12StateCache::SetShaderResourceView`（`D3D12StateCache.cpp:1563`）：以指標相等判斷不必重設；失去資源的 view 改綁 null。
- **建表** `BuildSRVTable`（`D3D12DescriptorCache.cpp`）：每次新保留一段 online 槽，從各 view 的離線 handle `CopyDescriptors`。
- **表的沿用**：`ApplyResourceTables`（`D3D12StateCache.cpp:654`）只在目前著色器範圍內有髒槽時才重建表，否則沿用 command list 上已綁的表。這就是 Main 交替與否的差別：交替時每筆 draw 重建，固定時沿用。
- **換 PSO**：`SetGraphicsPipelineState`（`:1437`）換了像素著色器、root signature 不變時，只經 `SetNewShaderData` 更新 SRV 數量，不標髒；但 `SetSRVTable` 每次建表後都把表範圍外的槽標髒（`D3D12DescriptorCache.cpp` `SetSRVTable`），所以新著色器用到更多槽時照樣會重建。root signature 換了則 `InternalSetRootSignature`（`:370`）全部標髒。
- **換 heap**：`FD3D12DescriptorCache::SetDescriptorHeaps`（`D3D12DescriptorCache.cpp:103`）heap 換了就 `DirtyViewDescriptorTables`，`ApplyState`（`D3D12StateCache.cpp:523-524`）同時強制重設 root signature。
- **bindless**：這個 build 是 `Configuration=RayTracing`，raster draw 走一般 heap（`D3D12StateCache.cpp:479-519`）。`FD3D12OnlineDescriptorManager::Init`（`D3D12Descriptors.cpp:218`）在非完全 bindless 時另開 `Device Global - Online View Heap`，和 bindless heap 是不同的 D3D12 heap，bindless 寫入碰不到 DreamGUI 的表。
- **區塊回收**：`FD3D12SubAllocatedOnlineHeap` 只在 `RollOver` 時把 `CurrentBlock` 交給 `FreeHeapBlock` → `DeferredDelete`（`D3D12DescriptorCache.cpp:1177-1184`），沒有其他交回點。每個 context 一直用同一區塊，跨很多 command list，直到寫滿。
- **local heap 退路**：所有趟次的 log 都沒有 `ran out of sub allocated` 或 `OnlineHeap RollOver Detected`，全程走子配置區塊。

## 6. DreamGUI 側讀碼

- `FDreamUIBuiltInDrawCache`（`DreamUIRenderer.cpp:860`）只快取 VS／PS 與 PSO 參數，符合時跳過 `SetGraphicsPipelineState`；貼圖參數每筆 draw 都經 `SetShaderParameters` 重設。
- 同一個 pass 的 lambda 裡交錯錄製內建 draw（`DrawBuiltInBatch`）與走 material 的 draw（`FDreamUIScreenRenderVS/PS`，`DreamUIRenderer.cpp:2420-2530`）。material draw 之後把 `BuiltInCache.Pipeline.bSet` 清掉，下一筆內建 draw 會重設 PSO。讀起來是對的。
- Main 的來源：`FDreamUIBuiltInDrawParams::ResolveTextures_RenderThread`（`DreamUIBaseShaders.cpp:140`）在 render thread 把 `TWeakObjectPtr<UTexture>` 解成 `UTexture::TextureReference.TextureReferenceRHI`。
- 讀卡器把舊 UMG 的影像鏡射到 DreamGUI：`OKReaderScreen.cpp` 192–197 行（外觀縮圖）、251–259 行（**任何** `UImage`，包括卡片預覽 `PreviewImage`）、`OKReaderThumbs::Show`（卡片列表縮圖）。本輪整趟記錄中，Main 只出現第 3 節那三類。
- 動態圖集 `FDreamUIDynamicSpriteAtlasData::CopySpriteTextureToAtlas`（`DreamUIDynamicSpriteAtlasData.cpp:362`）在 render command 裡捕捉裸 `FTexture2DResource*`。這是 CopyTexture（複製，不是 MainPS 取樣），而且 Main 換成全域白圖並不會改變它，所以不是這次故障的讀取者；但裸指標本身仍是潛在問題。

## 7. 結論與卡住的地方

1. **確定**：故障需要 DreamGUI 內建 draw 的 Main 槽在連續 draw 之間換貼圖（breadcrumb 裡就是圖集／WhiteSolid 一筆一筆交替）。Main 整槽固定（全域白圖 6/6，WhiteSolid 1/1）就不故障。
2. **確定**：Main 綁的貼圖全都活著；離線描述子位元組正確；沒有 rename；區塊大小無關。
3. **確定**：被讀到的是一張 24 幀前已釋放的角色貼圖，讀取是在它釋放之後才錄製的。
4. **未解**：從程式碼找不到一條路徑能把角色貼圖的位址放進 DreamGUI 的表。交替 → 每筆 draw 重建表，這是兩種情況唯一的引擎層差別；但重建本身讀起來是對的。
5. 使用者的判斷：閃退是引進 DreamGUI 之後才出現的，問題在 DreamGUI。這和第 1 點一致。

## 8. 建議的下一步

- **用 Nsight 對回原始碼行**（最直接）：Nsight Graphics 2026.4.0 已安裝，附 `C:\Program Files\NVIDIA Corporation\Nsight Graphics 2026.4.0\host\windows-desktop-nomad-x64\nv-aftermath-format.exe`，能把 `.nv-gpudmp` 對回原始碼行（參數 `-d` 給 `.nvdbg`、`-b` 給 `.dxil`、`-g` 給 `.pdb`）。
  - 只讓 `FDreamUIBasePS` 帶符號編譯：在它的 `ModifyCompilationEnvironment` 加 `CFLAG_GenerateSymbols`。DXC 會同時產出 `.pdb` 與 `.dxil`（`D3DShaderCompilerDXC.cpp:244-262、768-789`）。
  - 啟動加 `-ini:Engine:[ConsoleVariables]:r.GPUCrashDebugging.Aftermath.DumpShaderDebugInfo=1` 以產出 `.nvdbg`。
  - 目前的建置下約 80 秒、第 12 張卡（`12_demo_Male01.png`）就會穩定故障，重現成本低。
  - 得到的是「哪一行、取樣哪個變數」，可以直接驗證「是 `DreamUI_MainTex` 的取樣」這個推論。
- **繼續讀 DreamGUI**：往「Main 為什麼會交替」追，也就是批次怎麼決定 Main、什麼時候切批次（`FDreamUIDrawCall` 的合批條件、`CanConsumeUIGeometryForBatchMesh`）。
- 4096 臂只完成一趟，若要拿它下結論需補到 3 趟。

## 9. 診斷碼的去向

查找用的診斷碼全部沒有提交，已從工作樹還原；需要時可從 patch 套回：

- DreamGUI 實驗（`FallbackSlots`、`Main texture seen`、著色器符號旗標）：`Saved/Reports/card-reader-pagefault-slots/dreamgui-experiments-20261120.patch`。
- 引擎診斷（下表各項，加上第 4 節的 `CheckDescriptorBytes`、rename 記錄、區塊回收延遲）：`Saved/Reports/card-reader-pagefault-slots/engine-diagnostics-20261120.patch`。

## 10. 根因與修正（2026-11-20 13:10–16:30）

### 10.1 再排除四層（每項都量測過）

| 假設 | 診斷 | 結果 |
|---|---|---|
| 命令列表綁的 view heap 和表的 GPU handle 不在同一個 heap（explicit／bindless heap 沒還原） | `SetSRVTable` 每次檢查表落在 `LastSetViewHeap` 範圍內 | 約 1700 萬張表 `outside=0`，照樣故障 |
| 狀態快取裡留著已銷毀的 view（懸空指標） | 全域登記活著的 `FD3D12View`，建表時逐槽檢查 | 0 次，照樣故障 |
| view 活著但底下的 `FD3D12Resource` 已銷毀 | 全域登記活著的 resource | 0 次，照樣故障 |
| bindless 路徑 | `-BindlessOff` | 2/2 照樣在第 11 張故障 |

### 10.2 決定性的量測

建表時把每個抄進表的 SRV 的資源 GPU 位址範圍記進環形緩衝（約 1150 幀），故障時倒出涵蓋故障位址的那幾次抄寫：

- 涵蓋故障位址的抄寫：**0 次**。
- 那塊記憶體原本住的是 `Texture2D_2016`（256×256），在故障前約 **850 幀**就釋放，它的 64 MB pool heap 在故障前約 830 幀交回。

也就是說，GPU 讀到的描述子不是這段時間任何一張表寫進去的，而是 online heap 裡很久以前留下的舊描述子。heap 交回後的 830 幀都沒出事，表示這個舊描述子平常不會被讀；某次 draw 的表剛好排在它旁邊時才被讀到。

### 10.3 證實「硬體會讀表外的描述子」

引擎在 tier 2/3 硬體上，root signature 每個階段宣告 `MAX_SRVS` 個 SRV，但只把著色器自己的數量（DreamGUI 是 8）寫進 online heap，宣告範圍內其餘的格子保留舊內容。

| 做法（RTX 5090，ext60 六十張） | 結果 |
|---|---|
| 原狀 | 26 趟中 24 趟故障 |
| 保留整個宣告範圍，全部寫入 | 4/4 開完 |
| 保留整個宣告範圍，只寫著色器的 8 格（尾端留舊資料） | 2/2 故障（第 10、12 張） |
| root signature 縮成 2 的冪次（DreamGUI＝8），寫滿 | 1/3 故障（第 24 張）：表外的舊描述子仍會被讀到 |
| **online 區塊回收時清成 null 描述子**（表的大小照原狀） | **3/3 開完** |

所以不只宣告範圍內，硬體連表後面一段也會碰；只要 heap 裡存在指向已交回記憶體的舊描述子，就有機會故障。

### 10.4 修正

引擎補丁 `Tools/EnginePatches/ClearRecycledOnlineDescriptors.patch`（`D3D12Descriptors.cpp/.h`；D: 引擎 `2bfba231ca29`，E: 引擎 `28c2baa4c1fa` 已提交、尚未在 E 建置）：

- `FD3D12OnlineDescriptorManager::Init` 建一段 CPU 端的 null SRV（一個區塊大小），並把整個 online view heap 清成 null 一次。
- `Recycle`（GPU 用完一個區塊、`DeferredDelete` 回來時）把整個區塊 `CopyDescriptorsSimple` 成 null，再放回空閒佇列。
- 開關 `D3D12.ClearRecycledOnlineDescriptors`，預設 1。

成本：每個區塊回收時多抄一個區塊大小的描述子（同一份 null 來源），量級和建表本身相同。

不需要 DreamGUI 改任何東西；止血補丁 `RetainEmptyPoolHeaps` 已撤回。

### 10.5 驗證

乾淨建置（診斷碼全部移除、`RetainEmptyPoolMB` 不存在、DreamGUI 原樣），ext60 六十張、開完再空跑兩分鐘：**3/3 開完沒有故障**（`final-trip1..3`，15:51–16:12）。加上 10.3 只開清空的 3 趟，修正後共 6/6；修正前同一流程 26 趟中 24 趟故障。報告在 `Saved/Reports/card-reader-pagefault-slots/`。

## 11. F 樹與並行 RDG（2026-11-22，F 樹 `F:\OpenKoikatsu`，引擎 `F:\UE5.8`）

### 11.1 F 引擎漏了這個補丁

配種時讀卡器兩次當機（`Saved/Logs/CardReader/20261122-114412-05145dcc.log`、`20261122-125724-5a80437e.log`），簽章和本文件相同（`Shader Hash = E6753E1E…`、`fragment_02 @ 0x45f90`、DreamGUI `ViewExtension(0)`），當時是 `r.RDG.ParallelExecute=0` 啟動、另有一個 Unreal（C 組布料）共用 GPU。C（`D:\PhysX\UE5.8`）與 E（`E:\PhysX\UE5.8`）引擎已有 `ClearRecycledOnlineDescriptors`，**F 引擎沒有**。已用 `git am -3` 套上（F 引擎本機 commit `2a5e98ac5fa2`，未推送），`D3D12Descriptors.cpp` 和 D: 引擎逐位元相同。

為了不再發生，`Source/OpenKoikatsu/OpenKoikatsu.Build.cs` 加上這個補丁的標記檢查（`OK_D3D12_CLEAR_RECYCLED_DESCRIPTORS`，標記 `ClearRecycledOnlineDescriptors`）：引擎缺補丁時建置直接失敗。三個引擎都已有，不會讓任何一組建置失敗。

### 11.2 量測（RTX 5090，機器上只有這一個 Unreal，`E:/OKPackage/TestCards-20261118` 逐張開不同的卡、每張停 6 秒）

驅動與每趟紀錄：`Saved/Reports/card-reader-pagefault-f-20261122/`（`dwell.lua`、`dwell_<名稱>.txt`，本機）。

| 趟 | 引擎 | RDG | 結果 |
|---|---|---|---|
| control | 沒補丁 | 並行（`-ParallelRDG`） | 第 15 張故障 |
| keep1 | 沒補丁＋空 pool heap 不銷毀（暫時改的，等於已撤回的 `RetainEmptyPoolHeaps`） | 並行 | 60 張開完 |
| fix1 | 補丁 | 並行 | **第 11 張故障** |
| age1 | 補丁＋區塊年齡上限 8 幀＋區塊尾端 128 格保護（見 11.4） | 並行 | **第 37 張故障** |
| serial1 | 補丁（11.4 的兩個開關關掉） | 序列（讀卡器啟動器預設 `r.RDG.ParallelExecute=0`） | **60 張開完** |
| serial2 | 同上 | 序列 | **60 張開完** |

### 11.3 讀法

- **讀卡器平常的啟動方式（序列 RDG）下，補丁在 F 上成立**，和第 10.5 節一致。配種那兩次當機是 F 引擎沒有補丁。
- **第 10 節的驗證全部是序列 RDG**（`ext60slots.lua` 經 `reader_launch`，命令列都有 `r.RDG.ParallelExecute=0`），**並行 RDG 從來沒有在補丁下驗過**。並行下補丁擋不住（fix1、age1），所以根因修正只涵蓋序列 RDG；讀卡器啟動器的 `r.RDG.ParallelExecute=0` 不能拿掉。
- 並行時另有舊描述子的來源。空 pool heap 不銷毀（keep1）在並行下擋得住，因為不管描述子從哪來，它指的記憶體都還有對應；但它是止血、不是根因，這次沒有加回。

### 11.4 試過、已撤回：online 區塊年齡上限與尾端保護

推論：每個 context 的 online 區塊要寫滿才交回，並行 RDG 的 context 很少錄製，區塊裡留著幾百幀前的表，就在新表旁邊；補丁只在交回時清。試做兩個開關：`D3D12.OK.OnlineBlockMaxAgeFrames`（開新 command list 時區塊超過 N 幀就換一塊）、`D3D12.OK.OnlineBlockGuard`（每塊最後 N 格不給表用、保持 null）。age1 照樣在第 37 張故障，所以這不是並行時的來源（或不是唯一的），程式碼已從 F 引擎還原，差異留在 `Saved/Reports/card-reader-pagefault-f-20261122/online-block-age-guard.diff`。

### 11.5 還沒解

並行 RDG 下的舊描述子來源。第 4 節的排除實驗（離線描述子位元組、rename、區塊大小、texture reference）全部是序列 RDG 做的，並行下要重做才算數。
