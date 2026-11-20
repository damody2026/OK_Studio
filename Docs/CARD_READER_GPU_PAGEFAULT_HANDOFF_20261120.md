# 讀卡器 GPU PageFault 交接（2026-11-20，整合時封存）

**2026-11-20 下午已找到根因並修正**：引擎 online descriptor heap 留著舊描述子，硬體讀到指向已交回 heap 的那一個。見 [查找紀錄](CARD_READER_GPU_PAGEFAULT_SLOTS_20261120.md) 第 10 節；第 9 節的止血已撤回。以下是當時的交接內容。

這份是接手這個當機的人要先讀的東西。**持有者還沒指認**，但排除面已經很大，而且每一條排除都附了「什麼觀察會讓它復活」。
整合（三樹合一、推上 master）在這一刻發生，所以下面提到的 commit 都在 `master` 上。

相關紀錄：`Docs/CARD_READER_PATH_EXCLUSIONS.md`（排除清單，編號條目）、`Docs/ERROR_LOG.md`（量測與流程的錯誤）、
`F:\OpenKoikatsu\Docs\DREAMGUI_PAGEFAULT_CANDIDATES_20261119.md`（§9–§37 的讀碼清查）、
`Saved/Reports/card-reader-dreamgui/`（各趟報告）。

## 1. 症狀與重現

讀卡器（Dream 讀卡器畫面，`CardReaderDevelopment.cmd` 的預設路徑）連續開卡約一兩分鐘後
`LogD3D12RHI: Error: PageFault`，遊戲關閉。固定六十張卡單 `E:/OKPackage/ext60` 連續開，
基線重現率在不同建置上量到 6/6、3/3、1/1、以及 `cards=14` 與 `cards=22～46` 兩種落點。
**故障發生的卡序不固定（第 3、14、19、22、46 張都量到過）**，所以不是「固定水位」或「固定工作量」。

## 2. 量到的事實（這些是地基，不要重新推導）

- 故障是**讀取**一塊**已釋放的卡片 runtime 貼圖**所在的位址：`B8G8R8A8_TYPELESS`；
  **尺寸會變——量到 256×512（0.69 MB）、512×512（1.38 MB）、1024×1024（5.38 MB）——所以尺寸不能當篩選條件**
  （2026-11-20 更正：原本這一行寫「1024×1024 或 512×512、大小隨卡片 mip」，那是把前幾趟的尺寸當成了身分）。
  擁有者與釋放路徑在 `KKRuntimePose`（`KKRuntimeMaterial.cpp:378` 的 `CreateTransient`）。
- **會故障的那十七張，編號全部在 `Texture2D_25` 之後**（`_89`、`_247`、`_320`、`_550`、`_647`、`_660`、`_869`、
  `_870`、`_874`、`_893`、`_895`、`_901`、`_956`、`_1007`、`_1430`、`_2323`、`_2961`），
  而 DreamGUI 的內建 draw 綁過的卡片類貼圖只有 `Texture2D_7`..`_25` 連號 19 張（實測窗口 7914 幀，
  見排除清單第二十九條）。**所以「它是卡片 runtime 貼圖」成立，「它是 DreamGUI 綁的那些之一」不成立。**
- 故障位址**落在那張貼圖自己的區間內**（十趟十次，區間檢查 7/7），**不是前任房客的偏移**。
- 那塊 64 MB `PoolAllocator Heap` 在貼圖釋放後**整塊被交回**，所以故障當下
  `Found 0 active heaps containing page fault address`——**那個位址是空的、沒有映射**。
- 著色器是**單一像素著色器**：`Active Shaders: 1 total`、`Function = MainPS`、PC 落在它裡面，
  `Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF`（所有趟次同一顆）。`MainPS` 就是 DreamGUI 的
  `IMPLEMENT_GLOBAL_SHADER(FDreamUIBasePS, …, "MainPS", SF_Pixel)`。
- 釋放是正常 GC（`unreachable → released → heap → fault`），MID 在清掃放手後還把貼圖撐活約 6459 幀。
- **Dream 讀卡器畫面是必要條件**：`-LegacyReader` 三趟 0/3 故障，對照基線 6/6，而且乾淨趟做的工更多。
- **時間差（十趟，`FrameID` 就是蓋章用的那個 frame fence）**：

  | 貼圖釋放 | heap 釋放 | 故障當幀 | heap−貼圖 | 故障−heap |
  |---:|---:|---:|---:|---:|
  | 7353 | 7375 | 7475 | 22 | 100 |
  | 16678 | 16701 | 16926 | 23 | 225 |
  | 16432 | 16454 | 16463 | 22 | 9 |
  | 17132 | 17154 | 17169 | 22 | 15 |
  | 16520 | 16542 | 16677 | 22 | 135 |
  | 16170 | 16193 | 20309 | 23 | **4116** |
  | 18422 | 18444 | 18488 | 22 | 44 |
  | 18168 | 18190 | 18203 | 22 | 13 |
  | 8217 | 8240 | 8264 | 23 | 24 |
  | 18697 | 18719 | 19178 | 22 | 459 |

  **`heap−貼圖` 永遠是 22 或 23，而那是讀出來的常數不是線索**：`D3D12PoolAllocator.cpp:850` 的空 heap 修剪
  用寫死的 `InFrameLag = 20`（`D3D12Allocation.cpp:1910`、`D3D12Adapter.cpp:1841`，沒有任何 cvar），
  加上 `GetLastUsedFrameFence() <= CompletedFence` 的浮動。**不要再為這個 20 幾幀開新的一條線。**
  它同時說明那塊 heap 在貼圖釋放之後沒人再動過（`Max` 語義）。
- **`故障−heap` 是 9 到 4116 幀**，所以：不是「fence 只早了一點」（否則故障會緊貼銷毀），
  也不是「下一個房客」（短命房客解釋不了四千幀後才被讀）。
- **蓋章點在「釋放記帳」那一刻**：`D3D12PoolAllocator.cpp:650/656`，`DeallocateResource` 裡
  `DeleteRequest.FrameFence = FrameFence.GetNextFenceToSignal()`，同一個值拿去 `UpdateLastUsedFrameFence`。
  所以它涵蓋「釋放那一幀以前提交的 GPU 工作」，**不涵蓋釋放之後才提交的使用**。

## 3. 剩下唯一的形狀

把第 2 節合起來只剩一種可能：**有東西握著一個烘進去的位址，跨越數千幀，並在任意晚的時間取樣它；
而它不持有參照計數**（否則那塊配置不會被釋放），**也不是 C++ 裸指標**（全 plugin 掃過，見第 4 節）。
descriptor 正是這個形狀：SRV descriptor 本身就把資源位址烘在裡面，而它不是 C++ 指標，
所以不會出現在任何「掃裸指標」或「看 `UTexture*`／`FTextureReferenceRHIRef`」的量具視野裡。

## 4. 排除清單（附復活條件）

| 排除的東西 | 怎麼排除的 | 什麼會讓它復活 |
|---|---|---|
| 卡片的靜態特徵（像素總量、服裝數…） | 三次不同切法都否掉；C001 像素更多卻開得好 | 無（否定得很硬） |
| 固定水位／固定門檻 | 死亡當下 tex 337–518、actors 5–13，卡序 3～46 | 無 |
| bindless 表 | 這個 build 只開給 ray tracing（`Configuration=RayTracing`），故障是 raster 的 `MainPS` | 若有人開 `Minimal` 以上 |
| residency、VT feedback | 讀碼與趟次 | — |
| 我方清掃／MID／GC 行為 | `NeverDeleteProxy` 三趟 3/3 且 `leak_lines=0`：**proxy 解構在讀卡器裡從不發生**（兩個獨立量具同結論） | 讀卡器哪天會換掉或釋放材質（換主題、換 skin、關畫布後重開） |
| DreamGUI 延遲釋放佇列當釋放者 | `LogEntries` 只放手 `DreamUIDataTexture_N` | — |
| 九個 reference 槽當持有者 | `slot_hits_fault_texture=0`（四趟）**＋它們持 `TRefCountPtr`，結構上只看得見活的綁定** | 見下方「這個零的三個洞」 |
| backdrop 的**讀取**側 | `NoBackdrop=2` 三趟 3/3（副本照配置，只把綁定換成黑圖） | 重跑要回到 `c9fd56d5d` 之前的碼（見第 6 節） |
| backdrop 的**配置／交接**側 | `NoBackdrop=1` 三趟 3/3（`CopyFrom` 在任何 `CreateTexture` 之前就回 null，整趟沒有副本） | 同上 |
| 「取樣者是落在已釋放記憶體上的 backdrop 副本」 | mode 1 根本不存在那個副本；且故障當下那個位址沒有任何活的東西 | — |
| 群組 render target 回池重用 | `DreamUI_GroupTexture` 整份 log **0 次**：讀卡器從沒取得過 group render target（**機制點不存在**，不是「走過但沒出問題」） | 讀卡器用到會讀背景的混色模式時，這條與相關兩條一起復活 |
| RDG transient 別名／transient heap | 本機是 **TIER_2**（`Logging all resource enabled: Yes` 的必要條件就是 TIER_2），所以 transient heap 會被追蹤、**連銷毀都會寫進已釋放名單**；`retention=400000` 那趟窗口覆蓋 4139 幀，包住故障位址的只有 pool heap 與那張卡片貼圖，`TransientResourceAllocator Backing Heap` 字樣 0 次 | 在 TIER_1 的機器上本條不成立（不是跨機器結論） |
| 材質 uniform expression cache | 寫進 resource table 的是 `TextureReference.TextureReferenceRHI`（有 refcount 的間接層，`MaterialUniformExpressions.cpp:1729`），引擎在 `:1708-1711` 把競態寫明並退回 `GWhiteTexture`；MID 的貼圖參數是 UPROPERTY 強參照 | — |
| D3D12 descriptor／state cache 的 ABA | `DirtyStateForNewCommandList` 對 SRV/UAV/CBV/Sampler 都 `DirtyAll`，窗口只有一條 command list，**撐不出 4116 幀** | — |
| DreamGUI 跨幀裸指標 | 全 plugin 掃過：跨幀的只有 mesh proxy 的兩個 buffer 指標，而它們**只當比較鍵、從不解參**；backdrop 的 `FRHITexture*` 不跨幀（只有型別定義、函式參數、兩個 pass lambda 的區域變數） | — |
| 縮圖 brush | `FDreamUIImageBrush::ResourceObject` 是 `UPROPERTY TObjectPtr<UObject>`，`Brush` 本身也是 `UPROPERTY`，兩層都是 GC 看得見的強參照 | — |

### `slot_hits_fault_texture=0` 這個零的三個洞（別把它當「從沒綁過」）

1. `LogSlot` **只在值變了或每 600 幀心跳才印**，所以「一直交出同一個」會被稀釋到 1/600（但進入綁定那一幀會印成 `changed`，所以「曾發生」抓得到）。
2. 回查**靠名字比對**（`referenced_name` 取自 `FRHITexture::GetName()`，`src=` 取自 UObject 的 `FName`），而 `LogSlot` 取名字前沒驗有效性——物件已死時名字可能讀不出來。
3. **最致命**：那條路持 `TRefCountPtr<FRHITexture>`（`RHITextureReference.h:53`），**所以只要某個槽真的綁著那張貼圖，那塊配置就不會被釋放**。這個量具在結構上只看得見活的綁定，而我們要找的東西在定義上不持有參照計數。

## 5. 現成的旋鈕與樁（整合後三樹都有）

| 名稱 | 位置 | 用途 |
|---|---|---|
| `DreamGUI.LogTextureSlots` | `DreamUIBaseShaders.cpp` | 九個 reference 槽各印 `src= ref= referenced= referenced_name=`，值變或每 600 幀 |
| `DreamGUI.LogStaleTextures` | 同上 | resolve 當下該貼圖的 UObject 是否已是垃圾 |
| `DreamGUI.Experiment.NoBackdrop` | `DreamUICompositor.cpp` | 1 = 不配置也不取樣；2 = 照配置但綁全域黑圖 |
| `DreamGUI.Experiment.NeverDeleteProxy` | `DreamUIMaterialProxy.cpp` | 洩漏 proxy 而不解構（**診斷，不是修法**，註解自己寫明） |
| `DreamGUI.Experiment.LogPoolReuse` | `DreamUICompositor.cpp` | 群組 RT 同一塊再發出的距離 |
| `DreamGUI.DeferredRelease.LogEntries` | `DreamUIDeferredRelease.cpp` | 這個佇列放手了什麼（`kind= name= WxH held= now=`） |
| `D3D12.TrackAllAllocations` | 引擎，寫 `[SystemSettings]` | 故障報告才會列出相關配置；`Logging all resource enabled: Yes` 是它的到達證據 |
| `D3D12.TrackedReleasedAllocationFrameRetention` | 引擎，純 `int32` 無 clamp | 已釋放紀錄的保留窗（量過 400000 可用，等於永不修剪） |
| `rhi.DumpResourceMemory 1` | 引擎 | 印 `Total tracked resource size:`，**全引擎只有它印這個字串**，適合當閘門 |

腳本：`Saved/Reports/card-reader-dreamgui/` 有各趟報告；改動前後比較用的驅動是同一支（同一份六十張卡單、
同一組旋鈕、固定取樣卡序 3/6/9/12/15/19/25/30）。**基線與改動後要用同一把尺**，零旋鈕的趟次回答的是別的問題。

## 6. 這次整合帶進來、會影響實驗的改動

DreamGUI 去裸指標那一輪（`c9fd56d5d`、`2e0a02bdf`，F 樹原生，整合後在 master）把
`FDreamUIBuiltInBackdrop::Texture` 從裸 `FRHITexture*` 改成 `FTextureRHIRef`（持有參照）。
**那會讓 backdrop 的 RHI 貼圖在 draw 期間多一份參照，那一幀內延遲釋放佇列不可能釋放它。**
`NoBackdrop` 兩格都在這個改動**之前**跑完，所以第 4 節那兩條結論有效；
**今後要重跑 backdrop 實驗，必須回到 `c9fd56d5d` 之前的碼。**

同一輪也把九個 reference 槽改成 weak、把兩個位址比較鍵改成持有參照（而不是自建序號：序號要每個造 buffer 的
地方去升，漏一個就讀成「沒變」，正是要去掉的失效模式）。**這一輪是把「不帶參照計數又跨幀」整類形狀去掉，
不是指認後的修法**，所以：

- **若當機消失，不等於指認完成**。要用同一份六十張卡單跑三趟確認（基線：Dream 路徑 6/6、`NoBackdrop=2` 3/3、
  `NeverDeleteProxy` 3/3），然後**逐處回退**找出是哪一處，那才是指認。
  最可能的那一處是 `FDreamUISectionProxy_Mesh::Material`——原本會在 render thread 解一個裸 UObject 位址
  （`Material->GetRenderProxy()`），材質在 section 還在池子裡時被回收就是讀已死位址。**從它開始退。**
- **若當機照舊，那也是資訊**：持有者不在那一類裡，第 4 節的排除更硬。

**Editor 模組 14 處、Tests 模組 41 處的裸指標還沒改**（刻意留著：測試模組編不過會同時擋住 C／E／F 三組的
編輯器目標）。靜態檢查也還沒加——這個 repo 沒有可擴充的 C++ 檢查層，唯一 in-tree 去處是 `DreamGUITests`
的 automation test。要加的話，條文寫寬一點比較有用：**「不得跨幀持有沒有參照計數背書的 GPU 資源身分」**，
那會同時蓋住裸指標、烘死的位址、以及用指標當鍵的 ABA（例如 `FRHITextureViewCache` 的鍵只有 `CreateInfo`、
不含資源身分，目前兩個持有者都把貼圖釘死所以安全，但形狀在）。

## 7. 下一步（建議）

純讀的排除路徑已經用完：剩下的形狀**在定義上看不見於現有每一個量具**。所以下一步是**設計並插一個樁，
記下每一筆 draw 真正綁出去的那個位址**，再和 `fault_va` 直接比對。要回答的設計問題：

1. 挂點要在綁定真正發生那一行（`SetShaderParameters` 那條路上，或更底層 RHI 把資源交給 command list 的地方）；
   挂在 DreamGUI 的 resolve 會重新落入第 4 節那三個洞。
2. 能不能在那個點取到 GPU virtual address；取不到就退而記 `FRHITexture*` ＋名字＋尺寸格式，並講明少掉什麼。
3. 便宜：讀卡器一幀有九百多筆綁定、整趟上萬幀，全印會撐爆 log 也會改時序（而時序影響重現）。
   需要取樣或過濾設計，並講明過濾會不會把要找的那一筆濾掉。
4. **乾淨趟也要讀得到的到達證據**——只在出事時說話的量具，在我們預期的結果裡讀不了。

## 8. 量測規則（這次付過學費，別再踩）

- **閘門要抓它所守護的量具獨有的字串。** `MB total`／`total`／`Memory` 這類通用詞不合格：
  `rhi.DumpMemory` 一行都沒印（它從統計系統讀，而統計沒在收集），而閘門字串被 `LogMemory` 的主記憶體行滿足，於是誤放行。
- **每個計數欄位旁邊必須有一個舉例欄位，樣本為空算失敗而不是沒資料。**
  「一個計數說有、它的樣本說沒有，就是量具在說自己壞了。」（這條救回了 `NeverDeleteProxy` 那一格的結論：
  不分大小寫的 `OOM` 命中了 `Bloom`，若只看計數會把三趟正常故障判成作廢。）
- **三個字母的縮寫不要用 `-i` 去 grep**（OOM／RHI／ID／VA 同病），抓實際整句。
- **缺席證據要先確認「有的話會看得見」。** 兩次都在這裡犯錯：`Found 0 active heaps` 那三個零是在追蹤關閉時取的
  （不是量測）；而純貼圖 transient heap 因為旗標隱含 `DENY_BUFFERS` 根本不進 `TrackedHeaps`，
  所以「名單裡沒有 transient」一度被誤讀成排除。**排除要記成路徑排除，不是 cvar 排除。**
- **正在執行中的腳本不要改**（bash 按位元組位移邊讀邊執行），要記就記在旁邊的文件。
- **中途停掉驅動之後，要再查一次機器上還有沒有引擎**，並按 cmdline 指認歸屬再停——孤兒引擎會佔住槽。
- **機制點不存在 ≠ 陰性結果**，分開記，兩者的復活條件不同。
- 1/3、2/3 一律記「沒有結論」；某趟 `Shader Hash` 不同就是另一個故障，那趟不算。

## 9. 止血修法：空的 pool heap 不交回（2026-11-20 08:00–08:32，C 樹）

> **已撤回（2026-11-20 下午）**：引擎 revert `db4ae5671283`、`Config/DefaultEngine.ini` 那行已刪、`RetainEmptyPoolHeaps.patch` 已移除。根因修正是 `ClearRecycledOnlineDescriptors.patch`，見 [查找紀錄](CARD_READER_GPU_PAGEFAULT_SLOTS_20261120.md) 第 10 節。

持有者仍未指認，但第 2 節已經量死「故障 = 讀到一塊**已交回、沒有映射**的 heap」：
那塊 64 MB `PoolAllocator Heap` 只要還在，同樣的讀取只會讀到錯的內容，不會頁錯誤。所以不等指認，直接讓空的 pool heap 留著。

- 引擎補丁 `Tools/EnginePatches/RetainEmptyPoolHeaps.patch`（D: 引擎 `D3D12PoolAllocator.cpp` 的 `CleanUpAllocations`）：
  新增 `D3D12.OK.RetainEmptyPoolMB`（預設 0＝引擎原行為），每個 pool allocator 在這個預算內保留空 heap、之後的配置會重用它們；
  強制釋放（`bForceFree`）與 allocator 解構時的 lag 0 清理照舊全部釋放。
- 專案 `Config/DefaultEngine.ini` `[ConsoleVariables]` 設 `D3D12.OK.RetainEmptyPoolMB=2048`。沒套補丁的引擎只會警告不認得這個 cvar。
- 代價：顯示記憶體停在讀卡過程中的高水位、不會縮回（重用空 heap，所以不會一直長）。

**驗證**（同一份建置、同一份 `E:/OKPackage/ext60`、驅動逐張 `reader_call load`，每張之後查程序存活與 log 的
`PageFault`／`GPU crash`，出事就強制關遊戲；開完六十張再空跑兩分鐘；到達證據＝每趟啟動後用 `ui_exec` 回讀旋鈕值）：

| 趟 | 旋鈕回讀 | 結果 |
|---|---|---|
| retain-trip1 | 2048 | 60/60 張＋空跑，沒有故障 |
| control-trip1 | 0 | 第 11 張故障：`PageFault`、`Function = MainPS`、`Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF`、`Found 0 active heaps` |
| retain-trip2 | 2048 | 60/60，沒有故障 |
| control-trip2 | 0 | 第 13 張故障，同一顆 Shader Hash |
| retain-trip3 | 2048 | 60/60，沒有故障 |

保留 3/3 存活、對照 2/2 故障，而且兩組只差一個執行期 cvar，所以差異歸因到這個旋鈕。報告在
`Saved/Reports/card-reader-pagefault-fix/`。

**這不是指認**：那個舊描述子（或其他東西）仍然會讀已釋放的位置，只是讀不到未映射的頁。可能的副作用是某一幀 UI 取樣到錯的內容；
三趟裡都沒有看到。保留預算超出時，超出的空 heap 仍會交回，舊問題就可能回來。E 樹的指認工作（第 7 節）照舊有意義。
E 引擎（`E:\PhysX\UE5.8`）還沒套這個補丁：`git -C E:/PhysX/UE5.8 apply --check` 已確認可以乾淨套上。
