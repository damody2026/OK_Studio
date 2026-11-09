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

## 量測規則（來自街區經驗）

- 正式數字一律無 trace、編譯行程 0、只有一個 Unreal；trace 只用來定位。
- A/B 用同一場交替切換，或 ABA 且基準漂移 ≤10%。
- 量多個姿勢和鏡頭方向，用實玩解析度；720p 的數字不算。
- 不把跨執行緒的 CPU 合計加成幀時間。
- 先拆到最細的區段再改。世界矩陣、骨架簽章那次猜錯過。
- 測試用成年角色（雷電將軍、貞德、貞德·Alter）。

## 不要重走

百人矩陣路線（平行 bone packing、GPU matrix gather、exact pose 重用、`RHICmd` 批次、16 workers）都沒有收益。一對一候選裡 `GeometryJobs`、`CoatingParallel`、`WorldReuse`、`AssignedWorldFrame`、`SharedBodyIndex`、`FrozenTransform` 也試過無效。60 Hz pose bank 不能代替雙人即時解算。`ParallelFor` 不加 `BackgroundPriority` 曾凍結主執行緒。多一個 scene renderer 就有固定成本。
