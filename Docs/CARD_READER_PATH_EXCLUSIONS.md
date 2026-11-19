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

## 十、作廢：「約 22 幀的固定差值」（協調 session 的推測，2026-11-19 被量測否掉）

**原本的推測（提出者：協調 session `local_22ff1036`，按其要求掛名）**：故障幀與「釋放」之間存在一個
約 22 幀的穩定差值，可以當成時序指紋來對齊。

**否掉它的量測**：同一張貼圖（`Texture2D_1407`）六個時間點來自同一趟 log：
放手 24298 → 記憶體釋放 24301（**3 幀**）→ 64 MB heap 釋放 24326（比貼圖晚 **25 幀**）→ 故障 24406。
所以真正穩定的是**放手→釋放 3 幀**與 **heap 晚 25 幀**；而先前四趟記下的 44／60／2854／1148
量的根本不是這段，是「**釋放之後又畫了多久才撞上**」，它每趟都不同（105～2854 幀）。

**為什麼這個區別重要**：那個變動量就是「位置與秒數每趟都變」的來源。把它誤當固定差值，
會讓人去找一個不存在的穩定時序，也會讓「每趟不同」被當成雜訊而不是訊號。

**什麼會讓它復活**：若有一趟量到放手→釋放不是 3 幀，或 heap 落差不是 22～25 幀，
那表示釋放時序本身受某個條件影響，這條差值就重新有意義。

## 十一、量具自己的覆蓋率要用另一個量具去查（2026-11-19 立為一條，今天最貴的一條）

**形狀**：量具本身的輸出看起來是一個合法讀數（`0`、`1`、空的），而它真正的意思是
「**我沒有裝在你以為的那個地方**」。量具不會報告自己裝錯位置，所以**它的覆蓋率必須由另一個獨立量具去查**。

今天三次，都是「量了旁邊的東西」：

| 次 | 量具說什麼 | 實際是什麼 | 被什麼揭穿 | 成本 |
|---|---|---|---|---|
| 1 | `Found 0 active heaps containing page fault address` → 三個零 | 追蹤預設關著，**什麼都沒在記錄** | 打開 `D3D12.TrackAllAllocations` 之後報告就點名了貼圖與 heap | 一趟＋一次回撤 |
| 2 | 「相距 21–60 幀」 | 預設 100 幀保留窗口的**切邊假象** | 把保留窗口開到 4000，差距變成 105～2854 | 一趟 |
| 3 | **`life_released=1`**（「幾乎沒有釋放」） | 我把 log 插在 `KKUnityBundle` 的另一條 sweep 上；真正的建立與釋放都在 `KKRuntimePose` | **普查與建立紀錄的差集**：1439 張活著的 transient 貼圖，只對上 87 筆建立紀錄 | **兩次建置、三趟**（最貴） |

**怎麼用**：每加一個量具，先問「**如果它裝錯地方，它會印出什麼？**」
若答案是一個看起來正常的讀數（尤其是 `0`、`1`、空），那就必須同時有**第二個、原理不同的量具**
去量同一件事的總量——第 3 次就是靠普查（列舉現存物件）去對帳建立紀錄（事件計數）才抓到的。
**兩個量具的原理要不同**：同一條程式路徑上的兩個 log 會一起錯。

**什麼會讓這條失效**：沒有東西會。這是方法層面的，不依賴這個故障的任何細節——
所以它是今天最有轉移價值的一條。

## 十二、用執行期事實排除一整類假說，比列舉搜尋可靠（2026-11-19 立為一條）

**被排除的一整類**：「換卡後還活著的 MID 或元件仍指著那張貼圖」——包含所有形式的材質引用。

**排除它的不是搜尋，是一個執行期事實**：那張貼圖的記憶體在強參照被移出後 **3 幀真的被釋放了**。
MID 的 `TextureParameterValues` 是 `UPROPERTY`，GC 看得見它；只要還有一個可達的 MID 指著那張貼圖，
GC 就**不可能**回收它。它被回收了，所以放手那一刻**不存在任何 GC 看得見的材質引用**。
一個量到的釋放時間，一次否掉了整類假說——而且不必列舉任何一個持有者。

**為什麼這比搜尋可靠**：搜尋的陰性結果只覆蓋「我想到要搜的形狀」。
今天 grep `FMaterialRenderProxy`、`UMaterialInstanceDynamic*`、`MaterialCache` 都 0 命中，
但那只排除了我寫得出 pattern 的那些；**漏掉一個命名方式，陰性就是假的**——今天第 11 條那三次正是這樣錯的
（`life_released=1` 那次就是只 grep 了兩個模組）。
而「GC 回收成功」這個事實不依賴我有沒有想到某個持有者的名字：**它是由 GC 自己的可達性分析得出的，
覆蓋率等於 GC 的覆蓋率**，也就是全部 `UPROPERTY` 引用。

**怎麼用**：遇到「誰還拿著它」這類問題，**先找一個由系統自己做的全域判斷**（GC 可達性、refcount 歸零、
fence 通過、allocator 真的歸還），把它的結果當成排除依據；只有在系統沒有這種判斷的那一側
（這裡是 render thread 上 GC 看不見的裸指針與已錄好的指令）才回去用搜尋與插樁。

**什麼會讓這條失效**：若那 3 幀的釋放其實不是 GC 造成的（例如是某處顯式 `ReleaseResource`／`ConditionalBeginDestroy`
把資源拆了而 UObject 還在），那「GC 回收成功」就不成立，這個排除要收回。
**查法**：在放手與釋放之間印一次該 UObject 是否仍存在（`TWeakObjectPtr::Get()`）——
若它還在而記憶體已經沒了，就是顯式釋放，不是 GC。

## 第十二條的套用作廢（2026-11-19，交接反查那一趟）

第十二條的**方法照留**（用系統自己的全域判斷當排除依據），**但它在這個故障上的套用作廢**，
因為它自己寫的失效條件被打中了：它的前提是「記憶體在放手後 3 幀真的被釋放 ⇒ 放手那一刻沒有任何
GC 看得見的材質引用」。交接反查趟量到的是——**放手那一刻有 7187 筆 `ALIVE same=1`**
（材質還活著、參數還指著那張貼圖），而故障那張的配置是放手後 **6459 幀**才釋放。

**那個「3 幀」是一張貼圖、一趟的巧合，不是定律。** 我把 n=1 的時間差當成定律，
違反的是我自己登記過的「單趟不足以下結論」。
**所以「活著的 MID 與元件」這一類重新回到候選**，而且現在是量到的事實而不是候選。

## 十三、第十二條的下游推論一併作廢（2026-11-19，協調 session 自己要求記上）

第十二條那把尺（「放手後 3 幀釋放 ⇒ 放手那刻沒有任何 GC 看得見的材質引用」）作廢之後，
**所有以它為前提的下游推論也一起作廢**，逐條列出以免有人沿用：

| 作廢的 | 它的前提 | 現在的事實 |
|---|---|---|
| 「活著的 MID 與元件」已被排除 | 那把尺 | **回到候選，而且是量到的事實**：放手時 7187 筆 `ALIVE same=1` |
| 「MID 被 GC，而 proxy 的裸指標還指著它的 `FMaterialInstanceResource`」這個機制（協調一路主張的） | 那把尺 | 前提沒了，機制回到未驗證；舊 MID 在放手時**還活著**，不是被 GC |
| 「`ALIVE same=1` 是矛盾，要重新檢視」 | 那把尺 | 不是矛盾，**是這一趟的主要讀數**（7187/7191） |
| `mids_carrying_multiple_texs=2549` 可當重用證據 | 我自己的混淆指標 | 作廢：一個 MID 本來就有多個**不同參數**的貼圖；決定性的是同一個 `(mid,param)` 收到多張貼圖的次數＝**0** |

**這條的教訓與第十一條是同一族，但更貴**：第十一條是「量具裝錯地方」，這一條是
**「把一趟一個樣本的時間差當成定律，再用它排除一整類假說」**。
排除一整類的依據必須是**機制上的**（某條路不存在、某個量不在圖形路徑上），
或是**系統自己做的全域判斷**；**一個時間差不論多乾淨，都只是一個樣本**。

**怎麼用**：任何「因為量到 X 幀，所以 Y 不可能」的句子，先問「X 在幾趟上成立？」
答案是 1 就不能用來排除，只能列為待驗。

## 十四、DreamGUI 拆成兩條：釋放端排除，消費端不排除（2026-11-19）

先前寫成一條「DreamGUI 已排除」，**那太寬了**。它其實是兩個互不相干的問題，而兩條的答案相反：

| | 問題 | 答案 | 依據 |
|---|---|---|---|
| **釋放端** | 是 DreamGUI 的延遲釋放佇列放掉那張卡片貼圖的嗎？ | **排除** | 那個佇列放掉的全是 `DreamUIDataTexture_N`，沒有一筆 `Texture2D_<數字>`；`kind=func`（proxy delete）一趟都沒觸發 |
| **消費端** | 故障當下在畫的是 DreamGUI 嗎？ | **不排除，而且很可能是** | 故障後的 `Active GPU breadcrumbs`：`BasePass`／`ShadowDepths`／`RenderDeferredLighting`／`Translucency`／`PostProcessing` 全部 `[Finished]`，唯一還在跑的是 `RenderFinish → ViewFamilyExtension(3) → ViewExtension(0) → DreamUIDraw` |

**我自己的趟獨立證實了這段**（`20261119-221813-716b80e4.log`，故障幀 17772）。而且多出兩個細節：

1. **同時有三個 `DreamUIDraw` 兄弟節點是 `[Active]`**（ID `0x803542d4`／`d7`／`da`），
   `main=` 在 `DreamUIDynamicSpriteAtlasData_Texture_0` 與 `DreamUIPreset_WhiteSolid` 之間交替，
   三者的 `DreamUIData widget=DreamUIDataTexture_6 clip=DreamUIDataTexture_3` 與
   `DreamUIMore rect=DreamUIDataTexture_4 paint=DreamUIDataTexture_1 mask0=fallback` 完全相同。
   **所以 breadcrumb 給的是「還在飛的一段」，不是單一 draw**——它說得出是哪個 pass，說不出是哪一個 draw。
2. **那段裡 `Texture2D_` 零命中**：只有 DreamUI 自己的資源（atlas、font、widget、clip、rect、paint、
   `mask0=fallback`）。**所以那張卡片貼圖綁在 breadcrumb 沒印出來的槽上。**

**什麼會讓「消費端」也被排除**：若某一趟的 `Active` 路徑不在 `ViewExtension` 底下
（例如落在 `BasePass` 或 `Translucency`），那消費者就不是 DreamGUI 的 draw，這條要改寫。
**所以每一趟都要把那段存進報告**，不是只存一次——這也是這條的量測要求。

**這條的教訓**：「排除 DreamGUI」把釋放端與消費端混成一件。
**排除要連同「排除的是哪一個角色」一起寫**——同一個子系統可以在一條路上無罪、在另一條路上正是嫌疑人。

## 十五、歸屬：名字與格式不唯一，材質參數名才是（2026-11-19）

**f-sceneload 提的保留是對的**：外觀縮圖也叫 `Texture2D_<數字>`、也是 `B8G8R8A8_TYPELESS`、
也會進 `OK kept texture life` 這本生命日誌。**所以單憑「名字長這樣、格式是 BGRA8」，
把故障那張歸給卡片 runtime 貼圖並不唯一**——那只是「符合這一類」，不是「就是這一個」。

**解掉它的是交接反查，而不是名字**：故障那張被交給 12 個 MID，每一條都帶著**材質參數名**：

```
tex=Texture2D_2999 -> mid=MID_M_KoikanoSkin_Flat_56      param=_overtex1
tex=Texture2D_2999 -> mid=MID_M_ForgeSkin_Outline_Flat_72 param=_overtex1
…（12 條，全部 _overtex1）
mid=MID_M_ForgeSkin_Flat_72 params=15 _MainTex=Texture2D_3159 _overtex1=Texture2D_2999 …
```

**外觀縮圖不會被 `SetTextureParameterValue` 設成 `_overtex1`**，也不會出現在
`M_KoikanoSkin`／`M_ForgeSkin` 這些角色材質的參數表裡。**所以歸屬是量到的。**

**這條可以直接套用的部分**：故障報告給的是「名字 ＋ 大小 ＋ 格式」，而這三樣在一個專案裡**通常不唯一**
（UE 的 `Texture2D_<n>` 是自動編號，任何 `CreateTransient` 都長這樣）。
**要把一個位址歸給某個子系統，得靠那個子系統獨有的語意**——這裡是材質參數名與母材質名；
在別的故障裡可能是 Outer、擁有元件、或建立時的呼叫站點。
**在拿到那種語意之前，「名字符合」只能寫成「符合這一類」。**

**什麼會讓這條的結論失效**：若某處把外觀縮圖當成角色材質的 `_overtex1`／`_MainTex` 餵進去
（目前沒有這種站點），歸屬就要重新判。

## 十六、`[Active]` breadcrumb 有選擇效應：它偏向「排在最後的 pass」，不是「出錯的 pass」（2026-11-19）

**結構上的理由**（協調 session 提出）：DreamUI 的那串 draw 是**整幀最後才送的**——三份 log 的祖先鏈
完全固定：`Frame` → `SceneRender` → `RenderGraphExecute` → `Scene` → `FrameRenderFinish` →
`RenderFinish` → `ViewFamilyExtension(3)` → `ViewExtension(0)`。而 GPU 當機是在**幀末**被偵測到。
**所以不論真正出錯的是誰，只要 GPU 在幀末卡住，「還沒結束」的就會是最後送的那一串。**

**我這邊有一個數字正好支持它**：三份 log 裡 `[Active]` 的 `DreamUIDraw` 數量**不一樣**——
3、8、8（總節點 17／31／33）。若 `[Active]` 標的是「出錯的那一個 draw」，數量不會這樣浮動；
**它浮動正是因為那是「送出順序的一個尾段」，尾段多長取決於 GPU 停在哪裡。**

**因此這條的寫法要改**：
- **不可以**寫成「DreamUI 是取樣者」或「故障發生在 DreamGUI 的 draw 裡」；
- **只能**寫成「在這三趟中，DreamUI 的那串 draw 都是幀末未完成的那些」。

**連帶降級的**：先前第十四條裡「消費端不排除，而且很可能是」那個「很可能」，
**依據是這個有選擇效應的集合，所以降級為「尚無指認」**。釋放端的排除不受影響（那是另一組證據）。

**這條怎麼用**：`[Active]`／「最後未完成」這類讀數要先問一句——
**這個集合是由「出錯」決定的，還是由「順序」決定的？** 若是順序，它只能用來排除
「已 `Finished` 的那些」，不能用來指認還在飛的任何一個。
（所以 `BasePass`／`ShadowDepths`／`Translucency` 已 `Finished` **仍然是有效的排除**：
那些 pass 的工作已經完成，不是它們在撞那個位址。）

**什麼會讓它可用**：若 DRED 給出 `PageFault data`（指名哪個資源、哪個操作），那就不靠順序了。
目前三趟都是 `DRED: No breadcrumb head found.` ／ `DRED: No PageFault data.`，**所以這條路現在沒有讀數**。

## 十七、地基（不是排除）：出錯當下只有一顆 pixel shader 在飛，而三趟是同一顆

Aftermath 的傾印段落（例如 `20261119-222817-6c799c21.log:120960`）給的是**出錯的 warp 執行的 shader**，
不是「哪些 pass 還沒結束」。**所以它不受第十六條那個尾段選擇效應影響。**

三份當機 log 逐一核過，**完全一致**：

| log | `Active Shaders` | Type | Function | Shader Hash | 故障 VA |
|---|---|---|---|---|---|
| `20261119-212848` | **1 total** | Pixel | `MainPS` | `E6753E1EA9F1F20775D8BC0AD963B1EF` | `0x25b0681000` |
| `20261119-221813` | **1 total** | Pixel | `MainPS` | **同一個** | `0x257b321000` |
| `20261119-222817` | **1 total** | Pixel | `MainPS` | **同一個** | `0x256bd01000` |

`Aftermath Hash = 7159920291841742735` 三趟也相同；
`Page Fault Info: Type AddressTranslationError, Access Read, Engine Graphics, Resource: <no info>`。

**三趟是三張不同的貼圖、三個不同的位址、三個不同的卡片位置，而出錯的是同一顆 pixel shader。**
這是這個調查裡最強的一條：它把「取樣者」從一個集合收到**一個**對象。

**一個一致性檢查，而且它支持 DreamUI 的歸屬**：第二趟有**八個** `DreamUIDraw` 還在飛，
而 `Active Shaders` 只有 **1**。**八個 draw 共用一顆 pixel shader，正是 UI 繪製的形狀**
（一個材質、很多個 quad）。若還在飛的工作跨越不同的 pass，`Active Shaders` 就不會是 1。

**它仍然不能給名字**：`E6753E1E…` 是 DXIL 容器的 hash，而那個 hash 在整份 log 裡**只出現一次**
（沒有 shader map 表可以對回去）。`MainPS` 這個進入點名字本身沒有識別力
（四個 global shader 都叫它，UE 的材質 pixel shader 也叫它）——**識別力來自 `1 total` ＋ `Type = Pixel`
＋ 已 `Finished` 的那些 pass 的排除，而不是名字。**

**不要為了名字去重編**：舊的 `.nv-gpudmp` 事後解不了（f-sceneload 查到：符號相關的三個旗標都進
shader map key，容器一變 hash 就變），所以「開符號再回頭解舊傾印檔」這條路不存在；
要名字就得重編 shader 再重現一次故障。**現有證據已經夠窄，那個成本現在不值得。**

**什麼會改變這條**：若某趟的 `Shader Hash` 不同，那趟就是**另一個故障**，不能併進同一組算。
所以每一趟都要抓這個欄位——`-LegacyReader` 那三趟尤其：
若它照樣故障而 hash 相同，又沒有 DreamUI 在飛，**那就表示這顆 `MainPS` 不是 DreamUI 的**。

## 十八、`-LegacyReader` 這一格操縱的是一整束，不是「DreamGUI 畫不畫」（2026-11-19）

**和第十六條並列，因為是同一族的錯**：第十六條是「我以為 `[Active]` 指的是出錯的 pass，
其實它指的是排在最後的 pass」；這一條是「**我以為旗標只關掉繪製，其實它關掉一整條路**」。

`-LegacyReader` 讓 `OKGalleryWidget.cpp:1055` **整個跳過 `UOKReaderScreen::Open`**，所以被一起移除的至少有三樣：

1. DreamGUI 的畫布（`OKReaderScreen.cpp:409`／`438`／`2449` 是全專案唯一取得 `UDreamCanvas` 的地方）；
2. 它的那串 draw（`DreamUIDraw`／`DreamUIData`／`DreamUIMore`）；
3. **讀卡器畫面那條互動流程**——證據是我自己報的 `entered=0 returned=0`，
   那兩個 marker 在 legacy 路徑**根本不存在**。

**所以這一格的陳述句只能是**：
「**Dream 讀卡器畫面路徑是這個故障的必要條件**」（0/3 對上基線 6/6），
**而不是**「DreamGUI 的 draw 是取樣者」。**本格無法把上面三樣分開。**

**它不受影響的部分**：必要性本身是乾淨的——到達證據三層齊
（命令列回音 `cmdline_has_legacyreader=1`、`dreamgui_letgo=0` 對上 Dream 基線 7、
我的量具仍在輸出），而且**legacy 趟的工作量比會故障那趟更大**
（`kept_created` 3423／3417 對 2888，`handoffs` 40255／41276 對 34856，而那趟在第 50 張就掛了），
**所以「沒故障」不是「什麼都沒跑」。**

**怎麼拆開那一束**：換另一個旗標只會換成另一束。要指認就得**插樁**：
在 DreamGUI 實際綁貼圖的那一處，每幀印出綁進每個槽的 **GPU 位址**，故障後和報告的 `GPU VA` 比對。
**命中就是指認；從沒命中就能把 DreamGUI 這一側排掉**，而「讀卡器畫面路徑」裡剩下的東西成為下一個目標。
（這一格的到達證據天生在乾淨趟可見——每幀都印綁定——符合第九條。）

**什麼會讓這條的必要性失效**：若某趟 legacy 也故障**且 `Shader Hash` 與
`E6753E1EA9F1F20775D8BC0AD963B1EF` 相同**，必要性就不成立；
若 hash 不同，那是另一個故障（第十七條），不能併進同一組算。

## 十九、故障的位置與秒數連「同一個建置內」都不可比（2026-11-19，比先前寫的更嚴）

先前只宣告「跨建置不可比」（量具讓那個建置慢了一倍以上）。**同一個建置內也不可比**：

| 趟 | 建置 | 終局 |
|---|---|---|
| 交接趟 2 | 有 `OK mid params` 的那版 | 第 **50** 張、**387.0 s** |
| 槽位趟 | **同一個建置**，加上 `DreamGUI.LogTextureSlots=1` | 第 **17** 張、**142.6 s** |
| Dream 路徑早期四趟 | 無這些量具 | 第 5～17 張不等 |

**所以「位置」與「秒數」只能當成「這趟有沒有故障」的附註，不能當讀數。**
照這條，所有格子的判讀一律只看**故障與否**（以及 `Shader Hash` 是否同一顆，第十七條）。

**為什麼**：每個量具都改變 game thread／render thread 的工作量與時序，而故障本身的觸發點
（釋放之後又畫了多久才撞上）先前就量到是 105～2854 幀的變動量。**那個變動量本來就比任何位置差異大。**

## 二十、`DreamUI` 的九個槽：解參層面陰性（2026-11-19）

`DreamGUI.LogTextureSlots=1` 一趟 6461 行，**故障那張 `Texture2D_901` 的命中數 0**。
九個槽全是 `FTextureReferenceRHIRef`，持有 `TRefCountPtr<FRHITexture>`（`RHITextureReference.h:53`），
**所以「槽指著它」與「它被釋放」在機制上不能同時成立**——這條排除同時有機制與量測。

**沒有被排除的**：`DreamUI_SceneDepthTex`、以及 `DreamUI_BackdropTex`
（`FDreamUIBuiltInBackdrop::Texture`，整個 renderer 唯一的裸 `FRHITexture*`，無引用計數、不在 breadcrumb、不在九槽內）。

**一個不能跳過的細節**：同一趟有 **928** 行槽位綁的是 `Texture2D_<n>`（`_7`／`_9`／`_19`–`_25`）。
**所以「DreamGUI 不碰 `Texture2D_`」是錯的**；它碰的是編號很小的那群（UI 縮圖／預覽），
而角色 runtime 貼圖是幾百到幾千。**第十五條在這裡第二次救場：名字不是身分。**

**什麼會讓這條排除失效**：若某趟出現 `referenced_name=` 等於該趟故障那張，
那就是「有活引用計數還被釋放」，比原本的假說更大。

## 二十一、地基：故障位址落在那張貼圖**自己的區間**內，四趟都是（2026-11-19）

曾有一個重讀（協調 session 提出）：報告那段的標題是
`Found N released resources containing the page fault address`，列的是「那塊位址的歷任住戶」，
所以卡片貼圖可能只是**前房客**，真正懸空的指標屬於別的資源（例如住在同一塊 `PoolAllocator Heap` 裡的 pooled RT）。

**逐趟驗過，不成立**：

| log | 故障 VA | heap 區間 | 貼圖區間 | 位移 |
|---|---|---|---|---|
| `212848` | `0x25B0681000` | **IN** `[0x25AD800000..0x25B1800000]` | **IN** `Texture2D_1329 [0x25B0300000..0x25B0860000]` | `+0x381000` |
| `221813` | `0x257B321000` | **IN** `[0x2578A00000..0x257CA00000]` | **IN** `Texture2D_507 [0x257B1F0000..0x257B750000]` | `+0x131000` |
| `222817` | `0x256BD01000` | **IN** `[0x2568200000..0x256C200000]` | **IN** `Texture2D_2999 [0x256BC40000..0x256BDA0000]` | `+0xC1000` |
| `234105` | `0x2607661000` | **IN** `[0x2605800000..0x2609800000]` | **IN** `Texture2D_901 [0x26072E0000..0x2607840000]` | `+0x381000` |

**那個重讀要成立需要「落在 heap 內、但不落在貼圖區間內」——出現 0/4。**

**兩條獨立的支持**：
- 報告同時說 `Found 0 active tracked resources in 16.00 MB range of page fault address`，**那塊位址沒有活著的住戶**；
- 列出的已釋放資源中，**區間包含該位址的只有那張卡片貼圖**（加上包住它的 heap）。
  若懸空的是別的資源，位址會落在**那個資源**的區間裡，而它也會被列出——沒有。

**方向性的限制，免得這條被反過來用**：
「落在貼圖區間內」**與「取樣者正在讀那個貼圖物件」相容，但不等於後者**——
那塊記憶體已被釋放，任何人讀到它都是讀已釋放的位元組。**這條排除的是那個特定版本的重讀，不是全部。**

**這個檢查唯一的縫**：`retention=4000` 表示「更早於 4000 幀前被釋放」的住戶不會被列出來。
若某個資源在更久以前占過那個位址，這份清單看不到它。要補這個縫就得把保留窗口再開大。

## 二十二、現在的狀態，一句話（2026-11-19）

**被讀到的那塊記憶體已經指認（就是那張卡片貼圖的那塊，第二十一條，四趟）；讀它的人還沒指認。**

而這兩件之間有一個已經量到的約束，它決定下一步往哪找：
**DreamUI 的九個 reference 槽從沒綁過那張貼圖**（`slot_hits_fault_texture=0`，第二十條），
而那九個槽是 `FTextureReferenceRHIRef`，**解參時會給出「現在」的目標**。

**所以讀它的人拿的不是一個現在還解得出它的參照，而是「它還活著時取得的位址或 descriptor」。**
這把下一步限定在 **descriptor／綁定表那一層**，以及任何**跨幀保存已取得位址**的地方——
`FDreamUIBuiltInBackdrop::Texture`（唯一的裸 `FRHITexture*`）是這一類裡已知的第一個，
`DreamUI_SceneDepthTex` 是第二個。

**什麼會推翻這個限定**：若某趟出現 `referenced_name=` 等於該趟故障那張，
那就是「有活引用計數還被釋放」，那時九個槽重新回到候選（第二十條的失效條件）。

## 二十三、「heap 比貼圖晚 20 幾幀」是**正常行為**，不是線索（2026-11-20，讀引擎原始碼）

每趟的頁錯誤報告都把兩筆已釋放資源一起列出，而 **64 MB `PoolAllocator Heap` 的 `FrameID` 總是比那張貼圖晚 20 幾幀**
（量到 22、25、22…）。曾經被當成可疑的時間差。**它是寫死的常數加上一個 fence 條件。**

```cpp
// D3D12PoolAllocator.cpp:845-856  —— Trim empty allocators if not used in last n frames
const uint64 CompletedFence = FrameFence.GetCompletedFenceValue(/*bUpdateCachedFenceValue*/ true);
if (MemoryPool->IsEmpty() && (bForceFree || (MemoryPool->GetLastUsedFrameFence() + InFrameLag <= CompletedFence)))
{ MemoryPool->Destroy(); delete MemoryPool; }
```

`InFrameLag` 的兩個呼叫端**都寫死 20，沒有任何 cvar**：

```
D3D12Allocation.cpp:1910   PoolAllocators[PoolIndex]->CleanUpAllocations(20);   ← 貼圖池
D3D12Adapter.cpp:1841      uint64 FrameLag = 20;  GetUploadHeapAllocator(GPUIndex).CleanUpAllocations(FrameLag);
```

**所以那 20 幾幀 = 寫死的 20 ＋ fence 完成時機造成的幾幀浮動。不要再把它當成一條線。**

**而且這一段比「不是線索」更強：它是 fence 背書的。**
空 heap 只在「最後一次使用那一幀的 fence 已完成，再過 20 幀」才被銷毀——**它等過了 GPU**。
**所以「整頁從頁表消失」這一側本身沒有 bug**，
會出事的只能是**在那之後還在用那塊記憶體的人**，也就是持有者那一側。
**這把故障的兩側從「等重」改成「一側正確、一側有 bug」。**

**延伸出的一條格子取消（照第 7k 條：機制點不存在 ≠ 陰性結果）**：
曾打算找「延遲釋放空 heap」的旋鈕來判這一側。
掃過 `D3D12PoolAllocator.cpp`／`D3D12Allocation.cpp`／`D3D12Adapter.cpp` 全部
`Pool|Heap|Defrag|Release|Empty|Delay|Evict` 的 cvar，只有 `TrackedReleasedAllocationFrameRetention`、
`EvictAllResidentResourcesInBackground` 與描述符堆大小那幾個，**沒有一個管空 heap 的釋放延遲**。
**該格作廢，不是陰性。** 要延遲它只能改引擎（`Tools/EnginePatches`），
**而為一個判別器去打引擎補丁不值得**——那一層動了三棵樹都要跟。

## 第二十四條（2026-11-20）故障那塊記憶體是**非 transient 的池記憶體**，十趟十次——所以「RDG transient 別名」那一格照原樣登記的讀法不成立

**來源：既有十份故障 log 的 PageFault 傾印，零建置、零趟次。**
那份傾印每一行都印 `Transient:` 旗標，而十趟十次都是：

| | 包住故障位址的那塊 | 位址所屬的前任房客 |
|---|---|---|
| 名稱 | `PoolAllocator Heap`（64.00 MB） | `Texture2D_<n>`（5.38 MB，1024×1024 BGRA） |
| `Transient` | **0** | **0** |
| `Heap` | 1 | 0 |

十份 log（`Texture2D_89 / _320 / _550 / _647 / _660 / _869 / _870 / _895 / _901 / _1007`）全部同形。

**推論一（成立）**：GPU 讀到的那塊記憶體來自**池配置器**，不是 `FD3D12TransientHeap`。
transient 資源有自己專屬的 heap（`D3D12TransientResourceAllocator.cpp:64` 自己 `CreateHeap`、
`:82 SetIsTransient(true)`、名稱 `TransientResourceAllocator Backing Heap`），
和卡片貼圖所在的池 heap 是不同的 VA 配置。

**推論二（成立）**：backdrop 副本是 `GraphBuilder.CreateTexture`
（`DreamUICompositor.cpp` 的 `CopyFrom`），**而 RDG 的紋理在 transient 不適用時會回退到池化路徑**。
所以「副本落在卡片貼圖剛釋放的那塊上」這個說法要成立，**那個副本必須走池化路徑**，不是 transient 別名。

**推論三（因此那一格的讀法要改）**：事前登記的
「`r.RDG.TransientAllocator 0` 若 0/3 ⇒ transient 別名是機制的一部分」**不成立**——
故障現場的記憶體本來就是非 transient 的，**關掉 transient 只會把更多 RDG 紋理推上池化路徑，
也就是推向故障現場已經成立的那個條件**，方向是反的。一個 0/3 在這個設計下無法讀成那句話。
照第 7k 條：那一格要測的機制點（transient 別名）在故障現場不存在。

**覆蓋率聲明（第 7j、第十一條）**：上面那個 `Transient: 0` 只覆蓋傾印印出的那兩行，
**不是整趟的普查**。`D3D12TransientResourceAllocator.cpp:210` 確實會呼叫 `TrackAllocationData`，
所以追蹤器涵蓋 transient 配置；但「整趟有沒有 transient 資源存在」要用另一個量具查，
**本條不主張「這個 build 沒用 transient」**，只主張**故障位址所在那兩塊是非 transient 的**。

**改過的判別器方向**：要判的不是「關掉 transient 會不會不故障」，而是
**那個池化副本有沒有在前任房客等夠之前就被配置到同一塊上**——
也就是池配置器重用一塊剛釋放的記憶體時，等的是哪個 fence、覆不覆蓋那張貼圖的最後一次使用。
那條線索在池配置器自己，不在 RDG。
