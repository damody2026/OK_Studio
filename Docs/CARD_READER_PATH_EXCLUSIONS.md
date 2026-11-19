# 讀卡器 GPU 頁錯誤：路徑排除清單

**2026-11-19 建立。** 為什麼要這份清單：今天同一條死路（bindless descriptor heap）以兩個不同的
cvar 名字各被推上「主線」一次——第一次以 `D3D12.Bindless.GarbageCollectLatency`、第二次以
`D3D12.Bindless.ResourceDescriptorHeapSize`，而第一次取消它的理由（光追關著、圖形不走那個 heap）
就足以否掉第二次。代價是約 25 分鐘機器時間與兩次污染重跑。

**所以排除一律記成「路徑排除」，不是「某個 cvar 排除」。** 每一條寫三件事：
**排除的是哪條程式路徑**、**依據是哪一行**、**什麼觀測會讓它復活**。
沒有第三欄的排除不算排除，因為那是不可反駁的。

這份清單是 [主紀錄](CARD_READER_DREAMGUI.md) 的索引，不取代它；每條的完整推導在主紀錄裡。

## 一、故障本身已確定的部分（不是排除，是地基）

| 事實 | 依據 |
|---|---|
| 當掉的 shader 是 DreamGUI 自己的基底 pixel shader `FDreamUIBasePS` | dump 的 `Active Shaders:` 只有一個：`Function = MainPS`、`Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF`；`IMPLEMENT_GLOBAL_SHADER(FDreamUIBasePS, "/Plugin/DreamGUI/Private/DreamUIBase.usf", "MainPS", SF_Pixel)` |
| 錯誤型態是 `Error_DMA_PageFault` | dump 的 `Device state`；故障位址 `0x25C4061000` |
| ~~位址不屬於任何 active heap~~ **已撤回（2026-11-19）**：`Found 0 active heaps` 與其餘兩個零都來自沒開的追蹣——同一段報告第三行寫著 `Logging all resource enabled: No`，而 `FindHeapsContainingGPUAddress`（`D3D12Adapter.cpp:2062`）查的 `TrackedHeaps` 只在 `IsTrackingAllAllocations()` 成立時才有東西（`D3D12Resources.cpp:720-744`） | 照 7g：**那是「沒有在找」，不是「找遍了都沒有」** |
| GPU 故障**不會殺掉程序**：Aftermath 寫 dump、引擎卡在 crash reporter | 多趟觀測；`OKControl` 是獨立執行緒，照樣回應 |
| 60 張目錄的協定是目前最可靠的重現：**4/4**，138.6／139.2／139.3／140.1 秒，開第 14–17 張 | 四趟 log |
| 30 張協定是 **4/6 故障＋2 設限**，位置 5–22，`q̂ = 0.0388`（Wilson 95% CI 0.0152–0.0956） | 協定基線六趟 |

## 二、路徑排除

### 1. bindless descriptor heap（成長、回收、重用）

- **排除的路徑**：`FD3D12BindlessDescriptorManager` 的圖形側——heap 成長
  （`D3D12BindlessDescriptors.cpp:203` `ResizeGrowAndAllocate`、`:230-257` 翻倍）與
  heap 回收（`:420` `GarbageCollect`、`:425` `ReleaseGPUHeaps`）。
- **依據**：這台機器的 log 自己印 `Bindless is enabled (Configuration=RayTracing).`，而
  `RHIDefinitions.h:1462` 的 `IsBindlessEnabledForAnyGraphics` 是 `Configuration >= Minimal`，
  枚舉順序 `Disabled < RayTracing < Minimal < All` ⇒ **false**。
  `D3D12BindlessDescriptors.cpp` 圖形側的 `:100`、`:108`、`:312`、`:584`、`:600`、`:614`
  全擋在那個判斷後面。再加上 `Ray tracing is disabled. Reason: disabled through project setting
  (r.RayTracing=0)`。
- **什麼會讓它復活**：專案把 bindless 設定改成 `Minimal` 或 `All`（log 的 `Configuration=` 會變）；
  或 Aftermath 那句 "heaps" 確定指 descriptor heap **且**有證據顯示圖形 draw 會引用它。
- **注意**：旋鈕到達過（`Initializing allocators with 262144 Resource`），所以這**不是**
  「heap 成長已排除」式的實驗結論，而是**路徑從頭不在**。三趟沒跑完，不得引用為實驗結果。

### 2. 走 `FD3D12DeferredDeleteObject` 的資源記憶體釋放

- **排除的路徑**：RHI 的延遲刪除——「一張貼圖的記憶體在 draw 還在取樣時被釋放」。
- **依據**：`FD3D12DynamicRHI::EnqueueEndOfPipeTask`（`D3D12RHI.cpp:320`）對每個佇列建一個
  `FD3D12SyncPoint`（`GPUAndCPU`）當前置條件，刪除在那個 EOP 工作裡才執行
  ⇒ **凡走這條路的東西都要等 GPU 過了那個點**。
- **什麼會讓它復活**：有東西**不走**這條路被銷毀（外掛自己 `Release`、第三方配置器、
  非 RHI 路徑），或某個佇列沒被 sync point 覆蓋。
  **DreamGUI 自己的釋放是否走這條路，尚未查證——這是目前最該查的缺口。**

### 3. `D3D12.DeleteQueueMaxEOPTimeDelta` 作為「把釋放往後推」的旋鈕

- **排除的是這個旋鈕的語意**，不是路徑：`D3D12RHI.cpp:62-67` 的意思是
  「處理刪除佇列時，RHI 執行緒會為比這個時間差更舊的 EOP 工作停下來等」，**0 ＝不停等**。
  調大只會讓 RHI 執行緒更不受約束地往前跑，方向與要測的事無關。
- **什麼會讓它復活**：不會；要延後釋放得用別的手段。

### 4. 卡片清單縮圖路徑（`ok.ReaderThumbs`）

- **排除的範圍是「在這個協定裡」**，不是這條路徑本身。
- **依據**：`ok.ReaderScreen resources` 印
  `screen thumbPool=0 free=0 cardThumbs=0 controls=167 pageWidgets=1 cards=0` ⇒ **`cards=0`**，
  卡片清單從未建起來（協定是進 1 對 1 場景之後在那裡開卡）。旋鈕讀回也是空的。
- **什麼會讓它復活**：改用**真的會顯示卡片清單**的協定；那時這條路徑要重測。
- **連帶**：「目錄張數大 ⇒ 縮圖占用多 ⇒ 更早當」這個**機制解釋失去依據**
  （縮圖沒解碼）。**目錄張數的觀測仍然成立**（60 張比 30 張穩定且更早），只是沒有機制。

### 5. `Created late shader associations` 作為前兆

- **撤回的是這個線索本身**：它是 **Aftermath 產生 dump 時**去註冊 shader binary
  （`D3D12NvidiaExtensions.cpp:62` `CreateShaderAssociations`，由
  `RHICoreNvidiaAftermath.cpp:851` 呼叫，引擎註解 "Allow association after a fault"）。
  **它是故障的結果**，所以「fault 前 25 ms 出現」是必然。各趟表裡的 `lsa` 計數量的是當機本身。
- **什麼會讓它復活**：不會。

## 三、量值排除（照 10a 第 3 類：這個量不能解釋故障與否）

| 量 | 自己的資料如何否掉它 |
|---|---|
| 場上貼圖張數 `tex` | **231 張時故障、908 張時存活** |
| 角色數 `actors` | **37 個存活、35 個故障** |
| 讀卡器保留的 GPU 貼圖 MB | **512.6 MB 同時有存活與故障**；**407.2 MB 同時有存活與故障，而且方向相反**（保留更少的 60 張那批更會死）。峰值只出現 512.6／509.3／407.2 三個值 ⇒ 那個快取有約 512 MB 上限，峰值是撞上限 |
| 「哪一張卡特別」 | **三次被否掉**：A 階段死在四張不同的卡；`crowd_C001`（每個離群指標都更高）存活，而更輕的 `crowd_C020` 殺死；`kks_CharacterExport_Female` 甚至不在 f-yvonne 的 10/31 覆蓋樣本裡 |

**這些都不是「記憶體無關」**，只是這幾個量不能當門檻。

## 四、統計與量測方法的排除

| 被否掉的 | 依據 |
|---|---|
| 恆定的每張卡危險率 | 60 張協定 3/3 落在第 16／17／17 張、138.6–139.3 秒（全距 0.5%），對恆定危險率 p ≈ 8.7e-5 ⇒ **批次間不可交換**，合併的 `q̂` 無效，「前 31 張開卡可比」這個前提也被否掉 |
| 以「信箱有回應」判斷遊戲還活著 | `OKControl` 是獨立執行緒，GPU 故障不殺程序 ⇒ **結構上不可能正確**；改以 log 的 `MMU Fault Error` 標記判定 |
| 六趟乾淨足以證明修好 | 0/6 的概似比是 17（CI 下界）／1,573（點估計）／1.3e8（CI 上界）——**強度本身差四個數量級** ⇒ 30 張要 15 趟、60 張要 8 趟 |
| `rhi.DumpMemory` 等五個主控台指令當 VRAM 量具 | 全都不印可用輸出（`stat rhi`、`r.DumpRenderTargetPoolMemory`、`D3D12.DumpTrackedResidentAllocations` 各 1 行）；而我第一次量成「有輸出」是因為把開卡的非同步 log 行數算成指令輸出。可用的量具是讀卡器自己每次換卡就印的 `OK kept GPU textures: released N (X MB) ... keeping N (Y MB)` |

## 五、旋鈕到達的三種失效方式（每一種的徵狀不同）

| 失效方式 | 例子 | 徵狀 |
|---|---|---|
| 值在 init 被讀，主控台設是無聲失效 | `RHI.TransientAllocator.GarbageCollectLatency`（`RHICoreTransientResourceAllocator.cpp:528/:1280` 存進 `Initializer`，`:607/:1372` 比對） | 讀回**是新值**，程式用的是快照 ⇒ **讀回看不出來** |
| 命令列打在錯的 ini 區段 | `D3D12.Bindless.ResourceDescriptorHeapSize`：32768 在 `BaseWindowsEngine.ini:24` 的 **`[SystemSettings]`**，所以 `-ini:Engine:[ConsoleVariables]:` 壓不過 | 讀回**是舊值**＋`LastSetBy` 指出誰贏 ⇒ 看得出來 |
| 作用點在這個協定／設定裡不存在 | `ok.ReaderThumbs`（卡片清單沒建）、bindless heap（圖形不走） | 讀回可能正常，但**機制點的計數器全是 0**、或路徑被設定擋掉 ⇒ 只有作用點的量具或程式碼看得出來 |

**所以「讀回等於新值」不足以證明到達**；要看那個值**實際被使用的地方**留下什麼。

## 六、還活著的候選（連同各自缺的證據）

| 候選 | 為什麼還活著 | 缺什麼 |
|---|---|---|
| **真正的銷毀**（某塊資源記憶體被 destroy 而 GPU 還在用） | 這是 `Found 0 active heaps` 的字面讀法：**池化重用解釋不了頁錯誤**——池子留著 heap，位址仍屬 active heap，內容變了只會畫出壞東西 | Aftermath 那句 "heaps" 到底指資源記憶體 heap 還是 descriptor heap（協調已請 f-sceneload 確認）；以及引擎裡哪些配置器真的銷毀、哪些只回收 |
| **DreamGUI 的 material proxy `delete`**（`FDreamUIDeferredRelease::Later` 的唯一兩個使用者：`DreamUIMaterialProxy.cpp:134`／`:140`；`Hold()` 的三處到期時只是丟 RHI 參照或還給池子） | 若上面的重讀成立，方向就從「重用太早」轉成「刪得太早」；`DreamGUI.DeferredRelease.Frames.{Texture,Buffer,Pooled,Func}` 預設 3，`DreamUIDeferredRelease.cpp:54-55` 已經在印四個值 | 先找到到達證據：`DreamGUI.Experiment.NeverDeleteProxy`（`DreamUIMaterialProxy.cpp:95`，預設 0，`:112` 印 `material proxy leaked on purpose, total=N`）——開了之後那個計數要成長，不成長就是沒到達 |
| **residency：資源預設 start EVICTED，漏掉的 `UpdateResidency`**（**2026-11-19 降級**：`D3D12.ResidencyDebugBudgetMB=128` 一趟故障在 139.3 s／第 16 張，落在基線 4/4 的 138.6–140.1 正中間，往早往晚都沒動——而這個旋鈕正是引擎寫來暴露漏掉的 `UpdateResidency` 的。n=1、覆蓋 1/2，所以是降級不是排除） | `D3D12.ResourcesStartResident` 預設 0，說明文字自己寫「所有資源 start EVICTED」；兩條 opt-out 的 log（`residency management is disabled`、`CREATE_NOT_RESIDENT is not supported ... forcing resources to start resident`）在所有讀卡器 log 裡都**沒有出現** ⇒ 這台機器上資源真的從 evicted 開始。被畫到而沒常駐 ⇒ 位址不在任何常駐堆裡 | 判別格已寫好（`ResourcesStartResident=1` × 3 對 4/4 基線）。到達證據強：cvar 以 `FAutoConsoleVariableRef` **綁定** `GD3D12StartResourceResident`，而那正是 `D3D12Allocation.cpp:303`、`D3D12PoolAllocator.cpp:86/:493`、`D3D12Resources.cpp:813`、`D3D12TransientResourceAllocator.cpp:51`、`D3D12Residency.h:63` 讀的變數 ⇒ 讀回即真值 |
| **`ok.Experiment.ReaderScreenUnderOtherModes` 的趟間差異** | 那個 cvar 管的是 1 對 1／Studio 期間讀卡器畫不畫，**回到讀卡器之後兩邊應該一樣**，但兩組的結果不同 | 可能只是趟間差異；需要重複才知道是不是真的 |

## 七、這份清單怎麼用

1. **提出任何一格之前**，先在第二節與第三節找有沒有同一條路徑。
   找到了就回答「什麼觀測會讓它復活」——答不出來就不要跑。
2. **換旋鈕名字不算換路徑。** 同一個 manager、同一條釋放路線、同一個作用點，就是同一條。
3. **排除可以被推翻**，但要用第三欄說的那個觀測推翻，不是用新的猜測推翻。

## 八、一個必須先解決的矛盾（2026-11-19）

`delete InProxy` 的 destructor 放掉的也是 **RHI 參照**（uniform buffer、貼圖），
一樣走 `FD3D12DeferredDeleteObject` 的 EOP 圍欄。
**所以在第二節第 2 條成立的前提下，DreamGUI 沒有任何一條路能在 GPU 用完之前真的釋放記憶體。**
兩者不能同時為真，下一步必須先決定哪一個錯：

1. **第二節第 2 條錯**：那個 sync point 沒覆蓋到相關佇列，或有東西**不走** `FD3D12DeferredDeleteObject`
   （外掛自己 `Release`、第三方配置器、非 RHI 配置）。
2. **故障不是「記憶體被釋放」**：而是別的東西指到一個失效位址——繪製資料裡的指標、
   非 RHI 的配置，或 Aftermath 那句 "heaps" 根本是另一個意思。

**這個分叉比再轉一個旋鈕重要，而且兩邊都用讀程式碼就能推進。**

## 九、量具的一種失效形狀：只在壞事發生時才自我證明（2026-11-19 立為一條）

今天撞到三次，每次都讓一整格變成不可判讀，所以單獨立條：

| 量具 | 它的到達證據 | 為什麼乾淨的趟不可判讀 |
|---|---|---|
| `D3D12.TrackAllAllocations` | 故障報告第三行 `Logging all resource enabled: Yes` | **報告只在故障時印** ⇒ 60 張全開完的那一趟拿不到到達證據（`tracking_arrived=0` 不代表沒到達） |
| `DreamGUI.LogStaleTextures` | `DreamGUI stale texture at resolve: ...` | 那行**只在真的解析到過期貼圖時**才印 ⇒ `stale_hits=0` 與「旋鈕沒生效」在 log 上長得一樣 |
| `D3D12.TrackedReleasedAllocationFrameRetention` | 報告列出窗口外的紀錄 | 同上，只在故障時可見；而且報告那句 `during last 100 frames` 的 `100` 是**寫死的字串**（`D3D12Util.cpp:716`），不讀 cvar |

**規則**：挑量具時要先問「**沒出事的那一趟，我憑什麼說它生效了**」。
到達證據在**啟動時**可見的量具（例如 `r.D3D12.DRED` 的 `[DRED] DRED enabled`）優於只在故障時可見的。
兩者都只有故障時可見時，**乾淨趟一律記成「無讀數」而不是「陰性結果」**。

**什麼會讓這條失效**：若某個量具另有啟動時或每幀的計數器可讀（例如把配置數印在趟末），
那它就不屬於這一類，該格的覆蓋率可以寫 2/2。
