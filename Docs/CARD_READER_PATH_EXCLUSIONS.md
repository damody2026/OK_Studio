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
