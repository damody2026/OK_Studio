# 一對一場景 120 FPS 計畫

2026-11-08 的靜態研究：只讀程式碼與既有紀錄，沒有編譯，也沒有新量測。下面的 ms 估值都是推測，要用 trace 證實後才算數。

目標：實玩解析度 1920×1080，每幀 8.33 ms。開始條件：C 組街區攻略完成後（使用者 2026-11-07）。

## 現況

| 來源 | 條件 | 結果 |
|---|---|---|
| `H_SCENE_ADDITIONS_PLAN.md:420` | 11-05 安靜機器，`Int1105E`，1280×720 | 43～50 FPS；遊戲執行緒 19～25 ms，render 3～5 ms，GPU 2～3 ms |
| `INTERACTION_ALL_CONTROLS_120FPS_PLAN.md:115` | 10-07 展示場景乾播放，1600×1000 | 5.8 ms |
| `EGalWardrobe3` 測試截圖 | 11-07，雷電將軍，未插入，機器未確認安靜 | 62～75 FPS |

結論：瓶頸在遊戲執行緒，不是 GPU。從 5.8 ms 到 19～25 ms 的差距沒有文件解釋，這是第一個要查的。街區的遊戲執行緒優化幫不到一對一，因為街區 Tick 在 `TickPrivate` 就返回。

每幀順序：`SyncAsync` 等上一幀 → 顯示 → `ReadPairSessions`（肚子、衣物、讀 Rust）→ 這些全跑完才啟動下一幀解算。所以解算和主執行緒的工作沒有重疊。

## 嫌疑（依估計影響排序）

| # | 問題 | 位置 | 估值 | 改法 |
|---|---|---|---|---|
| 1 | `IsOpen()` 的 `Handle != nullptr` 會走轉型運算子並等解算，每幀至少兩次，抵銷背景解算（已看程式確認） | `KKRustExtract.h:173`、`OKHScene.cpp:1889`、`OKInteractionMode.cpp:453` | 2～6 ms | 改用 `Handle.Raw` |
| 2 | 解算太晚啟動，worker 在顯示和讀取時閒置 | `KKPairedPlayback.cpp:74→112` | 2～5 ms | sync 後先 snapshot，立刻啟動解算 |
| 3 | 遺留 DIAG 寫檔與統計，在衣物路徑上（已看程式確認） | `belly_bulge/cover.rs:415-422`、`56-65`、`215` | 未知 | 移除（本來就要移除） |
| 4 | 每幀在遊戲執行緒重建 morph set，本體和外框各壓一次 | `KKPreviewActor.cpp:10177`、`10201-10216` | 1～4 ms | 壓縮移到 worker，本體和外框共用 |
| 5 | 全狀態保留後，隱藏部件仍在解算、蒙皮、更新 pose | `session.rs:2279-2310`、`KKPreviewActor.cpp:7944`、`8021`、`8322` | 1～4 ms | 隱藏時跳過，重新顯示時 settle |
| 6 | `ReadPairSessions` 的同步 Rust 讀取，`skin_check` 全掃 | `belly_bulge.rs:486`、`536-547` | 1～3 ms | 不送用不到的點，降頻，空間索引 |
| 7 | ToonShadow 每人每幀 capture，1024² RGBA32f | `KKPairedPlayback.cpp:139`、`KKPreviewActor.cpp:7604` | CPU 0.5～2 ms | 隔幀交錯、R32F；遊戲執行緒降下來後才是下一關 |
| 8 | `RefreshSkinnedDisplay` 主迴圈 | `KKPreviewActor.cpp:7902`、`10992`、`KKSkeletalBuilder.cpp:1021` | 1～2 ms | 批次取 pose，移除環境變數查詢 |
| 9 | `wrap_solve` 5～9 ms，單 worker，120 FPS 時會趕不上 | `belly_bulge.rs:745` | 影響更新率 | 只算影響範圍，重用 buffer |
| 10 | 每幀 UMG 文字，`DevLine` 22 參數 | `OKHScene.cpp:1462-1478` | 0.2～1 ms | 值變才更新，降到 5 Hz |

還沒量的成本：`TickPrivate` 每幀把街上角色移到地底（`OKStreetSocialContacts.inl:474`）；水槍濕面累積後 `OK_PaintTick` 曾到 50 ms。

## 順序

1. 不改程式，用現有 `EGalWardrobe5` 量基準：佔名額，1080p，走正常流程進場，固定一個姿勢，分未插入、抽插、加快三段。控制埠 `/fps` 每秒取樣 `game_ms`、`render_ms`、`gpu_ms`。
2. 第一批小改一起編：第 1、3 項，加上 `ReadPairSessions`、`UOKHScenePanel::NativeTick`、`SetPartWrapDeltas` 的 trace scope。這三處現在沒有 scope。
3. 錄 trace（`-Trace default,cpu,gpu,frame`，`-GameArgs "-OKNativeTrace"`），用 Insights 匯出，重排嫌疑。第 1 項改完後排序可能會變。
4. 依 trace 做第 2、4、5 項。第 2 項影響最大也最危險，要確認讀到的是同一幀的資料。
5. 遊戲執行緒進 8 ms 後再看 render 和 GPU：ToonShadow、外框。

## 進度（2026-11-08）

量法：1920×1080，雷電將軍，背面騎乘位，鎖定，鏡頭固定；閒置、抽插（速度 1）、加快（速度 3）各取 8 秒 `/fps`，ABA 交替，機器上只有一個 Unreal。腳本在 scratchpad（`perf_measure.lua`、`run_perf.sh`）。

| 版本 | 改動 | 閒置 | 抽插 | 加快 |
|---|---|---|---|---|
| EGalWardrobe5 | 基準 | 83.7 | 73.7 | 74.8 |
| EGalPerf1 | `IsOpen` 用 raw、移除 DIAG、補 trace scope | 83.3 | 73.6 | 76.5（無差別） |
| EGalPerf2 | 解算進行中，H 面板的 tick 延到下一幀 `OnSessionsIdle` | 89.2 | 77.4 | 81.5 |
| EGalPerf3／4 | 隱藏部件（全狀態保留的另一狀態、脫掉的）不解算、不蒙皮 | 110.2 | 94.8 | 88.4 |

trace 的結論，和靜態研究的排序不同：

- 第 1 項（`IsOpen`）量不到差別。真正的等待在 H 面板的 tick：它在 Slate tick 讀寫 session，第一次呼叫就等背景解算，每幀 3.5 ms。改成解算進行中時延到配對下一幀的空閒點（解算啟動前）執行。
- 配對解算約 8 ms，其中 7 ms 在等動態骨（配件與衣物鏈）。全狀態保留後衣物部件約多一倍，隱藏的也在解算和蒙皮。現在 Rust 依 `ok_session_set_parts_hidden` 跳過隱藏部件，重新顯示時重設那條鏈並要求一幀解算（暫停中也會）。
- 水槍 `OK_PaintTick` 每幀約 3 ms，只在射精後有液體時才有，不是閒置成本。

剩下（Perf3 trace，抽插中 10.5 ms／幀）：解算 5.6 ms（動態骨等待 4.3），解算啟動前串行的顯示 2.3 ms、`ReadPairSessions` 1.6 ms、場景 tick 0.7 ms，主執行緒仍等解算 3.1 ms。下一步：縮短解算前的串行段（第 2 項，要先把 `ReadPairSessions` 讀的骨頭改成讀 session），或縮短動態骨。

### 第二輪（2026-11-08 下午）

細分後，解算啟動前的串行段：顯示 2.3 ms、`ReadPairSessions` 1.5 ms（包覆 0.51、背部裁切 0.46、凸起 0.25、皮膚檢查 0.22，平均分散）、場景 tick 0.7 ms。解算裡女角最長：衣物物理 1.37 ms，配件 2.47 ms，其中衣服推出肚子／胸部（`CoverPush`）每件最多約 1 ms、`CoverField` 每角色 0.3 ms。

不等解算（`ok.Anim.PairNoWait`，使用者 2026-11-08 提議，像 render thread 那樣）：解算沒做完的 tick 保留姿勢，時間補給下一次解算。`/fps` 加了 `pair_frames`，量角色姿勢真正的更新率：

| EGalPerf9 | 畫面 FPS（閒置／抽插／加快） | 角色姿勢 Hz |
|---|---|---|
| 不等（3） | 256 / 210 / 131 | 88 / 76 / 73 |
| 每幀等（0） | 110 / 96 / 86 | 110 / 99 / 89 |

畫面幀率上去，角色反而變慢：主執行緒多畫一倍多的幀，和解算搶 CPU，而且做完的解算要等下一個 tick 才接走。衣服推出改成件內平行、密集索引，在每幀等的模式下量不出差別（Perf7 109／95／92）。

### 第三輪（2026-11-08 傍晚，協調者轉達恢復）

`PairNoWait` 加畫面上限 120：畫面 117～120，角色只剩 60 Hz（解算鏈放不進一幀，變成每兩幀一次）。預設改回 0，程式保留。

| 版本 | 改動 | 閒置 | 抽插 | 加快（姿勢 Hz） |
|---|---|---|---|---|
| EGalPerf9（每幀等） | 基準 | 110 | 99 | 89 |
| EGalPerf10 | `CoverField` 和衣物物理同時建（`rayon::join`，骨架先取快照） | 115 | 102 | 96 |
| EGalPerf11 | 配對顯示時串流生成門檻降到 4096 頂點（`GKKStreamParallelMinVertices`，只在 `ShowFrame` 內） | 130 | 114 | 100 |
| EGalPerf12 | `back_exit` 整身蒙皮快取（同一姿勢只算一次）、平行蒙皮與三角形測試 | 130 | 116 | 110 |
| EGalPerf13 | `past` 凸起頂點清單快取＋平行；皮膚檢查改網格 k 近鄰（測試確認與線性掃描完全相同） | 130 | 115 | 104（雜訊內） |

Perf11 trace（抽插）：每換一次姿勢 8.85 ms＝解算 4.87（取樣 0.64、接觸 0.66、動態骨 3.5：女角身體 0.3 → 衣物鏈 1.4 → 配件 1.45）＋串行段 3.7（顯示 1.47、讀取 1.56、場景 tick 0.65）。主執行緒其餘 2.8 ms 和解算重疊。

加快階段（射精後有液體）變成主執行緒瓶頸：水槍每幀 4.8 ms（`OK_PaintMaskTransport` 1.7 ms 單執行緒、表面頂點已平行），解算只等 0.5 ms。

剩下要到穩定 120 的路，都是結構性的：

1. 顯示和下一次解算重疊：解算結束時在 worker 上發布顯示要讀的資料（骨架矩陣、私有部件串流），`ShowFrame` 讀發布的那份；`ReadPairSessions` 的 `HBone` 改讀 session。串行段可省 1.5 ms。
2. 水槍遮罩傳輸移到背景（它的累加刻意串行，要整段搬，不是拆）。
3. 小項：包覆的 C++ 陣列轉換（約 0.5 ms 未細分）、場景 tick 0.4～0.65 ms。

衣物鏈（1.4 ms）依 Unity 順序串行處理重疊的鏈，不平行化；全狀態保留沒有讓它變多（每個 prefab 一份）。

### 水槍遮罩傳輸移到背景（EGalPerf14）

`ok.Paint.AsyncTransport`（預設 1）：每個表面步驟的遮罩傳輸延到 tick 畫完上色後，在 worker 上跑到下一個 tick 開頭（或任何公開呼叫）為止；滴落改用上一步的傳輸結果。量測腳本加了第四段「射精後」8 秒。

| 版本 | 閒置 | 抽插 | 加快 | 射精後（姿勢 Hz） |
|---|---|---|---|---|
| EGalPerf13（A 兩次） | 130 | 110～118 | 102～103 | 92～100 |
| EGalPerf14 | 131 | 119 | 107～109 | 104～105 |

trace（射精後）：傳輸已全部在背景（主執行緒只等 0.15 ms）。主執行緒每幀 10.3 ms，仍是瓶頸：配對 4.1（顯示 2.2、讀取 0.9、場景 tick 0.43）、水槍上色 3.0（她的身體是骨架網格，上色走 CPU 蒙皮：`PaintCoatingVertices`、atlas 填塊 0.9、擷取幾何 0.6、貼圖上傳 0.55）、Slate 0.9、街區 0.4。要再降，水槍上色得走 GPU（現有 GPU 上色只支援 `UKKAffineProceduralMeshComponent` 來源）。

### 水槍 atlas 填塊與上傳平行（EGalPerf15）

atlas 填塊兩塊以上就分到執行緒池（以前 32 塊以下單執行緒），上傳先排好每塊位置再平行複製每一列（以前主執行緒逐列複製，尖峰 2.7 ms）。同一場 ABA：

| 版本 | 閒置 | 抽插 | 加快 | 射精後（姿勢 Hz） |
|---|---|---|---|---|
| EGalPerf14 | 128 | 116 | 109 | 102 |
| EGalPerf15 | 134 | 123 | 117 | 112 |
| EGalPerf14 | 132 | 119 | 109 | 103 |

trace（EGalPerf15 射精後，主執行緒 10.0 ms／幀）：配對 4.3（雙角色顯示 2.1、等求解 0.95、讀取 0.9 其中包覆 0.55、場景 tick 0.43）、水槍 2.6（上色 0.9、atlas 填塊 0.73、擷取幾何 0.63、上傳 0.38）、Slate 0.3。求解約 5.1 ms（配件 1.2×2、衣服貼皮推開 0.48×4、衣物物理 0.94×2）。

試過無效：衣服貼皮推開（`pushes_from`）的環狀擴散與翻面檢查改平行（EGalPerf16，ABA 在雜訊內），已還原。

試過無效（二）：衣服貼皮推開另建只含靜止皮膚的格子（EGalPerf17，結果逐位元相同，ABA 在雜訊內），已還原。

抽插 trace（EGalPerf15，主執行緒 8.58 ms／幀）：等求解 2.1 ms，所以抽插卡在求解鏈「顯示 1.47 → 讀取 1.15 → 場景 tick 0.73 → 求解 4.9」。求解關鍵路徑：取樣 0.63 → 接觸 0.6 → 身體 0.28 → 衣物物理 1.41（依 Unity 順序串行）→ 她的配件 1.86（尾巴是衣服貼皮推開 0.7～1.1）。顯示裡能移出鏈的只有配件串流的生成與上傳（0.52 ms），它直接讀 Rust 的頂點記憶體，下一次求解會換掉那塊；身體姿勢套用（0.3 ms）不能移，H 場景的 `HBone` 讀的是元件骨頭。

剩下的路是結構性的：顯示讀求解結束時發布的快照、與下一次求解重疊（拿掉 0.95 ms 等待，主要幫抽插／加快），以及水槍上色改走 GPU（骨架網格目前走 CPU 蒙皮）。

### 顯示拆兩段，配件串流和下一次求解重疊（EGalPerf18）

`ok.Anim.PairSplitDisplay`（預設 1）：`RefreshRuntimeAccessories` 拆成 `PrepareRuntimeAccessories`（遊戲執行緒讀 session，配件頂點的指標改指向我們自己的副本：大部件本來就有逐位元快照 `RuntimeSourceGeometry`，其他部件另外複製到 `RuntimeDeferredGeometry`）和 `FinishRuntimeAccessories`（轉換、生成、上傳，只讀副本）。配對的 `Advance` 在顯示時只做前半段，後半段在下一次求解啟動後才做（`FinishDeferredStreams`，任何離開 `Advance` 的路徑都會做完），和求解並行。畫面仍是同一幀：串流在這個遊戲幀內、畫面送出前就生成好。

肚子變形（`ReadPairSessions`、`ReadBulge`、衣服覆蓋）照使用者要求不移到求解之後，仍和顯示同一幀讀 session（使用者 2026-11-08：不要因為雙緩衝讓肚子變形慢一幀，怕陰莖穿模）。

安靜機器（c-conquest 暫停，只有一個 Unreal），同一執行檔切換開關，姿勢 Hz（閒置／抽插／加快／射精後），每段確認狀態（WLoop、OLoop、OUT_A）：

| ok.Anim.PairSplitDisplay | 閒置 | 抽插 | 加快 | 射精後 |
|---|---|---|---|---|
| 0 | 124 | 116 | 114 | 100 |
| 1 | 138 | 127 | 128 | 102 |
| 0 | 127 | 118 | 118 | 99 |

射精後 trace（EGalPerf18，主執行緒 9.9 ms／幀）：配對 3.6（等求解只剩 0.18，延後的串流 0.81 在求解期間跑），水槍 3.5（上色 1.5、等遮罩傳輸 0.6、步進 0.5、atlas 上傳 0.36），Slate 1.75，H 讀取 1.1（包覆 0.57、皮膚檢查 0.38、凸起 0.13），場景 tick 0.45。射精後已不等求解，瓶頸是主執行緒本身。

量測腳本注意：整合後姿勢名稱後面多了「　New」，第一次按「插入」只出「沒戴套插入」的提示，要按到狀態離開 Idle；每段量完要記狀態，不然量到的是沒插入的閒置。

### 衣服覆蓋檢查平行與兩個無效嘗試（EGalPerf19～22）

`BellyWrapTake` 主執行緒 0.56 ms 幾乎都在 `keep_cover`：每件會包覆的衣服各算一份蒙皮 palette 再抽樣碰她被推的皮膚。改成各件衣服用 rayon 平行（`COVER` 鎖先放掉），trace 0.56 → 0.39 ms。安靜機器 ABA（姿勢 Hz，抽插／加快）：EGalPerf18 129/129、128/127，EGalPerf20 133/132、136/134、131/131。

試過無效，已還原：

- 水槍遮罩傳輸任務改高優先度、各表面 `ParallelFor`（EGalPerf19、21）：射精後 ABA 在雜訊內（每次液體量不同，射精後一段在 92～120 Hz 間跳）。trace 看出原因：她身體那一個表面的傳輸一次就 10 ms 以上，比一幀長，每次表面步進（約每秒 13 次）下一幀開頭都要等，平行化分不開單一表面。
- H 面板文字值沒變不 `SetText`、`DevLine` 降到 5 Hz（EGalPerf19）：Slate 每幀 0.83～0.87 ms 不變。

EGalPerf21 射精後 trace（主執行緒 10.05 ms／幀）：水槍 3.6（上色 1.4、等傳輸 0.82、步進 0.57）、配對 3.5（顯示 1.2、延後串流 0.83、讀取 0.97）、Slate 1.7。抽插與加快已穩定在 120 以上；射精後要到 120，水槍傳輸得跨幀（畫面先用上一步的遮罩、只在下一次表面步進前才等），或上色走 GPU。


### 大學城（新地圖）的一對一（2026-11-13）

一對一移到大學城後，在 1920×1080、安靜的機器上量，ABA 交替（EGalVerify195 ↔ EGalPerfCity1），結果如下：

| 版 | 閒置 | 抽插 | 加快 | 射精後 |
|---|---|---|---|---|
| EGalVerify195（改動前） | 165／166 | 146／150 | 136／137 | 133／136 |
| EGalPerfCity1（改動後） | 168／165 | 141／153 | 135／139 | 133／134 |

四段都在 120 以上，game 6～7.5 ms，GPU 約 3.3 ms，瓶頸仍是主執行緒。同一時段第一次量到抽插 125、射精後 113，那次是 c-street-city 剛還 slot、機器還沒完全安靜，不算數。

trace（-statnamedevents）裡大學城才有的開銷約 0.8 ms／幀：
- 隱藏的平面反射約 640 個仍在 tick，約 0.2 ms。
- 街區 Tick 0.4 ms：TickAutoFriendship 0.15、TickRestroom 0.09、TickCampusProximity 0.065。
- OKCrowdController 加 CityEnvironmentController 約 0.12 ms。

EGalPerfCity1 的改動：
- 平面反射隱藏時一併關掉 tick。
- 自動成為朋友改為每 0.1 秒問一個人。
- 廁所與校園樓梯／辦公室判斷只在男主角移動後才重算。

trace 估計省約 0.4 ms，但 ABA 的差距落在雜訊（±3 FPS）內。剩下的大項仍是配對解算鏈：等 worker 1.0 ms、顯示 1.8 ms、讀取 1.0 ms。

大學城第二輪（2026-11-13，EGalPerfCity1 ↔ EGalPerfCity3 ABA，獨佔整台機器）：

| 版 | 閒置 | 抽插 | 加快 | 射精後 |
|---|---|---|---|---|
| EGalPerfCity1 | 166／172 | 156／151 | 140／141 | 137／136 |
| EGalPerfCity3 | 188／180 | 148／158 | 146／140 | 133／142 |

trace（-statnamedevents，抽插）：
- 整幀 7.11 → 6.71 ms。
- keep_cover：衣服碰到她被推的皮膚後，同一批先留在 CPU 路線 8 幀再重驗；沒碰到仍每幀查。OK_HWrapTake 0.31 → 0.08 ms。
- 街區 Tick 0.39 → 0.09 ms（EGalPerfCity1 的節流）。
- skin_now 平行化反而變慢：OK_HSkinCheck 0.23 → 0.28 ms，因為解算正佔著 worker pool。已撤回。

主執行緒省下的時間全變成等解算：KK_PairOKWait 0.65 → 1.40 ms。關鍵路徑已經是背景的配對解算本身，下一步要縮短解算，或讓顯示與下一次解算重疊。

native trace（EGalPerfCity4，-OKNativeTrace -statnamedevents，抽插）：
- 背景解算 KK_NativeFrameWait 每幀 4.47 ms（牆鐘）：等動態骨 2.52、等取樣 0.92、接觸 0.76、驗證 0.18。
- 動態骨內各 rayon 執行緒的加總：衣服貼皮推開 CoverPush 2.64（PushAt 1.21、PushRings 0.50）、配件 2.55、衣物物理 0.75、身體物理 0.50。這些早已平行；PushAt 每頂點看格子，不改結果就沒有便宜的空間。之前「只看上一幀推過的附近」的近似算法，使用者否決過（推得慢）。
- 每幀 ≈ 顯示加讀取（序列約 2.4 ms）+ 解算 4.5 ms ≈ 6.9 ms，所以抽插的上限約 145～155 FPS，和實測一致。

要再往上，只剩兩條結構性的路：顯示改讀解算結束時發布的快照，與下一次解算重疊（省掉序列的 2.4 ms）；或縮短解算本身（衣服貼皮推開、配件）。

顯示與下一次解算重疊，第一步（ok.Anim.PairLateDisplay，2026-11-13 預設開）：
- 兩個角色照舊在解算空檔裡，從同一份解算結果讀完 session，包括大腿晃動的資料。寫回 session 的動作（視線、頭部注視、IK、陰莖大小、衣服包覆）也都留在這段時間內。
- 下一次解算啟動後，才做兩件不讀 session 的 UE 工作：臉部零件跟上身體骨架（SyncMouthPose）、大腿晃動的 morph 上傳（KK_LateDisplay 約 0.4 ms）。顯示的仍是剛解完的那一幀。
- 身體骨架不能延後：H 場景的 HBone 讀的是 BodySkel 的骨頭。
- ABA（EGalPerfCity5，同一個執行檔，開關 0/1 交替，獨佔整台機器）：

| 開關 | 閒置 | 抽插 | 加快 | 射精後 |
|---|---|---|---|---|
| 0 | 154／171 | 156／131 | 136／141 | 134／130 |
| 1 | 171／171 | 166／147 | 148／141 | 140／129 |

開關 1 時正面看她頭頸接合、加快時大腿和衣服都正常（Saved/StreetSocial/Play-20261113T144711/control_shots/）。
## 量測規則（來自街區經驗）

- 正式數字一律無 trace、編譯行程 0、只有一個 Unreal；trace 只用來定位。
- A/B 用同一場交替切換，或 ABA 且基準漂移 ≤10%。
- 量多個姿勢和鏡頭方向，用實玩解析度；720p 的數字不算。
- 不把跨執行緒的 CPU 合計加成幀時間。
- 先拆到最細的區段再改。世界矩陣、骨架簽章那次猜錯過。
- 測試用成年角色（雷電將軍、貞德、貞德·Alter）。

## 不要重走

百人矩陣路線（平行 bone packing、GPU matrix gather、exact pose 重用、`RHICmd` 批次、16 workers）都沒有收益。一對一候選裡 `GeometryJobs`、`CoatingParallel`、`WorldReuse`、`AssignedWorldFrame`、`SharedBodyIndex`、`FrozenTransform` 也試過無效。60 Hz pose bank 不能代替雙人即時解算。`ParallelFor` 不加 `BackgroundPriority` 曾凍結主執行緒。多一個 scene renderer 就有固定成本。

### 最重女角全穿（2026-11-13 晚，蘭＝第 9 位，正常位）

- City10（5b8a7a96f）：配件／衣服的平行派工照上一幀耗時由大到小排。效果在雜訊內。
- City11（1b3b99986）：包覆的翻面修正只重驗變動的三角形，跟隨表改成密集陣列並平行。結果不變，FPS 也在雜訊內。
- 單執行緒剖析（OK_NATIVE_WORKERS=1、RAYON_NUM_THREADS=1、OKAnim.Profile），每幀工作：
  - 包覆 9.8 ms：格子推開 3.3、翻面 1.8、外圈 1.3、抬起 clear 1.3、抬起 rise 0.9、跟隨 0.6
  - 衣服蒙皮約 3.9 ms
  - 8 執行緒時配件 pass 牆鐘約 6 ms，平行效率只有約 40%。
- 上限診斷（City11）：

  | 條件 | loop FPS |
  |---|---|
  | 全穿 | 約 80 |
  | 全穿，關掉包覆（`ok.HScene.ClothCover 0`） | 104 |
  | 裸體 | 145 |

  就算包覆完全不做，全穿也到不了 120。差的部分是 CPU 蒙皮的衣服本身：約 32 件衣服的 CPU 蒙皮、主執行緒上傳頂點（KK_SourceRanges 約 1.8 ms），以及 render 從 4.6 ms 增加到 6.4 ms。
- 要讓全穿到 120，只剩結構性的路：
  - 衣服回到 GPU 蒙皮，包覆的推開改成 GPU 上的位移（compute，或每幀上傳的稀疏位移），不再整件從 CPU 上傳；
  - 或把包覆算進下一次解算（晚一幀顯示，像 WrapAsync）。

  兩條都要先由使用者決定。

- 晚一幀顯示（使用者選的，c675cad99，已撤回）：
  - 做法：衣服先套用上一幀算好的推開，這幀的推開丟到 native pool 背景算。
  - 結果：蘭全穿 loop 74～76 FPS，沒有比當幀算快；同一個執行檔關掉晚一幀還有 85。
  - 原因：背景工作和下一次解算搶同一個 8 執行緒的 pool，沒有離開最長路徑。
  - 剩下的路：衣服回 GPU 蒙皮，推開改成 GPU 位移。
### 分流與上限（2026-11-14）

- 9a1f1def9：`ok.HScene.ClothCoverSplit` 也分開大腿晃動的衣服（預設 0）。衣服跟隨皮膚的對照表包含她全身的皮膚，原本只要衣服貼著身體就被當成碰到晃動。改成只看晃動區域後，蘭的 CPU 衣服從 25 件降到 20 件。FPS 只有 after 78→81，其他階段不變；剩下 20 件確實在推開或晃動範圍內。
- 診斷指令 `ok.PrivateGpuGates`：列出每個部件走 GPU 或 CPU 的原因。
- 上限（EGalSplit4，蘭全穿，`ok.HScene.ClothCover 0` 加 `ok.ThighJiggle 0`，衣服全走 GPU）：idle 132～145、loop 132～134、fast 124～136、after 127～147 FPS。所以只要推開和晃動不把衣服留在 CPU，全穿就能過 120。
- 蘭全脫（EGalOcc5）：idle 164～172、loop 154～156、fast 146～158、after 145～153 FPS，正常。
- 還沒做（使用者 2026-11-14：做不到就算了）：推開與晃動改成 GPU 上的位移。Rust 照舊在背景算蒙皮與位移，但只輸出有動到的頂點；`RuntimeDeform.usf` 在 PostTransform 之後、轉 UE 座標之前加上每頂點位移；`OKEvaluatePrivateGpuPosition` 也加同一份位移。CPU 路徑上這兩者都只改位置、不改法線，所以結果可以和 CPU 相同。
### 衣服推開與晃動上 GPU（2026-11-14，使用者：「把 lan 的衣服物理全部都用 gpu 算，優化到 120fps」）

量測：EGal1114c，蘭全穿，正常位。

| 設定 | loop FPS | 配對解算 |
|---|---|---|
| 預設 | 77 | 9.1 ms |
| 推開關掉 | 106 | 5.8 ms |
| 晃動關掉 | 84 | 8.3 ms |
| 兩個都關 | 146 | 4.0 ms |

`OKAnim.Profile`：推開本身在解算執行緒上佔約 3.3 ms，`cover.garments` 各執行緒合計 9.2 ms/幀。
- push_at 3.1 ms
- flip 1.6 ms
- rings 1.2 ms
- lift_clear 1.0 ms
- follows 1.0 ms
- lift_rise 0.7 ms

CPU 蒙皮加晃動跟隨約 1.8 ms。每幀大約是解算時間再加 3 ms 顯示。

結論：只把上傳搬到 GPU（Rust 照樣在 CPU 蒙皮和推開，只把位移交給 GPU 加）最多到約 83 FPS。這部分已寫好：`ok.ClothGpu`、Rust `cloth_gpu.rs`、`RuntimeDeform.usf` 的 `Displacements`。要到 120，推開演算法本身也要在 GPU 上算，同一套算法、不用近似：

1. 每幀的皮膚場在 CPU 建一次（`CoverField::from_still`，已和衣服鏈平行），上傳後所有衣服共用：
   - skin (p0, p, n)
   - grid（展平成 CSR）
   - follow
   - Lift 的 way／side／skin／belly／grid
   - 大腿晃動的 moves
2. 每件衣服的固定資料在 CPU 算一次，上傳一次：
   - 鄰接表（CSR）、三角形
   - follows 的四近鄰對照（`map_to_skin`）
   - 晃動的四近鄰對照（`map_for`）
   - 兩張對照都在第一次看到這件衣服時，用 CPU 蒙皮的位置建。
3. 每件衣服每幀的 GPU pass：
   1. 蒙皮到 native 空間（PostTransform 之後）。
   2. follows：用對照表從 follow 加總。
   3. Lift：
      - rise 每頂點平行算。
      - clear 依三角形順序逐一累加，每個三角形讀到前面改過的 rise，所以在 GPU 上也要單執行緒依序做，只處理落在 Lift 範圍內的三角形。
      - rings 六輪：原本就用上一輪的快照，等於 Jacobi，可以平行。
   4. push_at 每頂點平行。
   5. rings 六輪（同樣 Jacobi）。
   6. flip 六輪：每輪平行檢查三角形，每個頂點乘上 0.5 的翻面三角形數次方。CPU 原本對同一頂點每個翻面三角形各減半一次，乘 2 的冪在浮點數上是精確的。
   7. 晃動跟隨：用對照表加總。
   8. 加到位置上，再轉 UE 座標並打包（現有的 DeformPacked）。
4. 開關 `ok.ClothGpu 2`（預設 0）：1 是只把上傳搬到 GPU，2 是推開也在 GPU 上算。逐段比對 CPU 路徑的頂點，再截圖比對外觀與貼合。

#### 實作與量測（2026-11-14 上午）

- `ok.ClothGpu 2` 已接上：
  - Rust 每幀把皮膚場整理成一塊 `uint32`，依修訂版號給出每件衣服的固定資料（`cloth_gpu.rs`、`cover.rs gpu_field/gpu_garment`）。
  - C++ 每個 actor 每幀讀一次皮膚場，衣服固定資料依版號快取。
  - `ClothCover.usf` 照上面的步驟計算，結果交給 `RuntimeDeform.usf` 加上去。
- 截圖（正常位，兩個角度，`ok.ClothGpu 0/1/2/0`）：
  - 模式 1、2 的外觀與貼合相同。
  - 和模式 0 只差膝上一個花紋貼片的深淺：模式 1 本來就這樣，屬於 GPU 顯示路線，不是推開造成的。
- 每件衣服的多個 section 原本各算一次，改成第一個 section 算完，其餘沿用；GPU view 每件衣服只建一次。
- 量測：

| 設定 | loop FPS | game | render | GPU | 配對推進 |
|---|---|---|---|---|---|
| 0（預設） | 78 | 12.8 | 6.7 | 4.2 | 9.1 ms |
| 1 | 79 | 13.0 | 7.4 | 4.4 | 9.2 ms |
| 2 | 71～73 | 7.0 | 15～16 | 6.8～8.4 | 4.9 ms |
| 2，跳過 clear（只診斷，結果不對） | 101 | 10.1 | 7.9 | 6.9 | — |

- Insights trace：模式 2 每幀多出約 10 ms GPU 時間（`FXSystemPreRender` 範圍內），來源是 clear 的單執行緒迴圈。
- clear 改法（結果不變）：
  - `ClearHits` 平行找出每個三角形內的皮膚取樣點，記下權重和要到的高度；這兩者都不讀 rise。
  - `Clear` 用一個 64 執行緒的 group 分批讀入命中數，第一個執行緒照三角形順序只做加減。
  - 命中超過容量時退回原本的單執行緒迴圈。
  - 結果（EGalCloth6）：模式 2 loop 98 FPS（預設 81），game 8.1、render 9.8、GPU 5.9 ms，配對推進 5.1 ms；截圖與先前一致。
- 接著把 rings 每輪的擴張與平均合成一個 pass：兩組 buffer 輪流讀寫，算式不變，每件衣服少 12 個 pass（EGalCloth7）：101 FPS，render 只少 0.3 ms。
- Insights：render thread 每兩幀建一次 private GPU graph，每次約 4.2 ms，大多是 RDG 處理每個 pass 的開銷（約 11 件衣服 × 33 個 pass）。
- 改成每件衣服一個 RDG pass，各步驟在 pass 裡依序 dispatch，中間插 UAV barrier；GPU 上做的事相同（`ok.ClothGpuOnePass`，預設 1，0 是每步一個 pass）。EGalCloth8：

| 設定 | loop FPS | game | render | GPU |
|---|---|---|---|---|
| 0（預設） | 82 | 12.7 | 6.9 | 4.2 |
| 2，每步一個 pass | 103 | 9.4 | 8.8 | 6.6 |
| 2，一個 pass | 107 | 8.4 | 7.7 | 5.8～8.0 |

- 截圖（兩個角度）與模式 0 一致。剩下的差距 game、render、GPU 三條線各差約 1 ms，都要再壓。
- 診斷 cvar：`ok.ClothGpuSkip`（每個步驟一個位元，只用來找成本，結果會錯）。
- 打包注意：global shader 改了，要自己的 runtime patch（`rebuild_street_social_patch.lua --output`），並以 `-PatchDir` 啟動；共用 patch 的 `RuntimeGlobalShaderPatch-*_P.pak` 會蓋過新 base 的 shader（見 `Docs/ERROR_LOG.md`）。
