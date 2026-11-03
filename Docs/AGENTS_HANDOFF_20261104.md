# 2026-11-04 整合交接

使用者在 2026-11-04 約 00:00 要求整合 C／E／F 三個專案與三個引擎、暫停所有 agent、把已完成的工作提交並同步後推上 master、清掉 worktree 與沒在用的暫存檔，並交代「全部做完之後不要恢復 agent」。本文件接在 [2026-11-03 整合交接](AGENTS_HANDOFF_20261103.md) 之後；協調者的工作方式、整合流程、各 agent 的規則仍以 [2026-11-01 整合交接](AGENTS_HANDOFF_20261101.md) 為準，這裡只寫變動與現況。

## 整合結果

| 項目 | 狀態 |
|---|---|
| 專案 | C `master`、E `duo2`、F `duo2` 都在 `167fee388`（併 E：`77f15fcf2`、併 F：`1c816f532`，加三筆整合修正），推上 `origin/master` 與 `origin/duo2`；本文件另外提交 |
| 引擎 | `D:\PhysX\UE5.8`、`E:\PhysX\UE5.8`、`F:\UE5.8` 都在 `11576da863ff`，沒有變動（`F:\UE5.8` 有 16 個 .bat／.sh 只差換行，內容相同） |
| Rust | `ok-extract`、`ok-rules`、`ok-mind`、`ok-game-mcp` 預設與 `--no-default-features` 都 `cargo check` 通過；`ok-rules` 263＋3 測試通過（全部 `-j 8`） |
| C 街區 | 完整重建 `Int1104C`，base `Saved/StreetSocial/BaseInt1104C`（D: 引擎），cook 0 錯 0 警告；沙盒實際啟動 11/11 角色就緒、無缺資源 |
| E 街區 | 完整重建 `Int1104E`，base `Saved/StreetSocial/BaseInt1104E`（E: 引擎），cook 0 錯 0 警告；沙盒實際啟動 11/11 角色就緒、無缺資源 |
| F OK Studio | 編輯器與遊戲建置連結成功；`verify_ok_studio.lua --tag Int1104Fb` 6/6 通過（`F:\OpenKoikatsu\Saved\OKStudio\Verify-Int1104Fb`） |
| 讀卡器 | C、E 的 `CardReaderDevelopment` 編輯器建置連結成功並啟動到地圖，只有已知的 CommonUI 錯誤 |

合併衝突：

- `Tools/ok-rules/src/hexp.rs`：C 的處女膜重建（`hymen_restored`、`pub fn of` 給 clinic.rs）與 E 的保險套／高潮次數欄位都保留。
- `Tools/ok-extract/src/ffi.rs`：F 把 `set_eye_gaze` 搬進 `OkSession::set_eye_gaze_rates`；E 的翻白眼（水平限 `eye_look::most()`、垂直 ±2、`st_rolled`＋`apply_st`）改寫進該函式。
- `Docs/STREET_ERRORS.md`：兩邊的列都保留（union）。

整合時發現並修正的三件事（都記進 `Docs/STREET_ERRORS.md`）：

1. e-fork 的 `a6d2681da` 提交進去的 C++ 函式插錯位置，三邊都編不過；`441f3447d`＋`e7bc32d05` 修正。
2. F 的 `53aafe10f`（併 feat/mmd-vnge-support）誤刪 4 個 base_v1 okmodel，街區 6 張卡無法載入；`167fee388` 還原。
3. c-street-city 回報已停的 chain21 其實還在跑、沒拿 slot 開著 StreetSocialCity；協調者停掉。

## 本輪併入的提交（429650157 之後）

- **C**：c-conquest 婦科診所、醫美診所、美髮店（`b487834d9`，遊戲內未實測）與大學城地點比對文件 7 筆；c-street-city 學院大樓錨點、遊戲需求補場景、生活場所第 2～4 輪（`462fab1fe`、`8d5031b9b`、`7b4315b2f`）。
- **E**：開發度 A 方案（`e438a5961`）、一對一修正（`ebc872305`、`295bc2e99`、`96f141270` 保險套要買才能戴等）、e-fork-2 高潮／做愛次數（`3a72699db`、`9bcbf2b04`）、e-fork 眼睛跟鏡頭與胸臀物理分開（`a6d2681da`）。
- **F**：`feat/mmd-vnge-support`（`e424bc62c`、`6a17f7722`：MMDD／VNGE、StudioDisplay30、KK/KKS 外掛相容），F 以 `53aafe10f` 合併。F 的 session 依使用者直接指示，已先把 `53aafe10f` 推上 `origin/duo2`。

## 各 agent 暫停時的狀態與下一步

使用者交代整合後不要恢復 agent。巡檢排程（cron `dcf5f7d6`）已刪除。

| agent | session | checkout |
|---|---|---|
| E 主線（一對一 H，slot 名 e-galgame，沙盒 EMain） | `local_aa5c7d4c-6156-46b9-b8e1-27aaecbea477` | `E:\OpenKoikatsu` |
| e-fork（眼睛，slot 名 e-fork） | `local_9e379b04-7799-4d85-94cc-580b2d7f6f52` | `E:\OpenKoikatsu` |
| e-fork-2（一對一，slot 名 e-fork-2，沙盒 EFork2，埠 48110） | `local_adfbe047-dacb-4441-ae3f-b031f5dec3f3` | `E:\OpenKoikatsu` |
| F（OK Studio） | `local_705cc0ce-72ee-49cf-99da-588059f7b129` | `F:\OpenKoikatsu` |
| c-conquest | `local_5567d4d2-964d-485f-94d0-6520c0da73c5` | `C:\portable\OpenKoikatsu` |
| c-street-city | `local_9c146b39-2af2-41cc-8a68-98cb6aa12e6e` | `C:\portable\OpenKoikatsu` |

- **E 主線**：工作樹留著兩個未提交修正：足交「射在她腳上」（遊戲內測過，建置驗證沒跑完）與保險套用完後改成不戴套繼續（重現失敗：放進 EMain 存檔的保險套啟動後被清空）。恢復後在臨時 worktree 建遊戲＋編輯器後只提交足交；再查保險套被清空的原因。
- **e-fork**：眼睛工作已完成（讀卡 100 張、街區 10 位 Eye20 全過），沒有待辦。
- **e-fork-2**：恢復後實測開發度 0 對 100 的噴水、乳汁、高潮持續倍率與翻白眼近拍；一律用 `e-fork-2`／`EFork2`／48110，只關自己的 PID。
- **F**：沒有待辦。工作樹的 `base_v1/models/.gitignore`、`base_v1/shared_mods.txt`、`Tools/base_library_shared_mods.txt` 是工具改寫的（刪了 5 個本機沒有的付費 mod），不要提交。Addiction 重現資源在 `F:\OpenKoikatsu\Saved\Repro\Addiction\`（啟動設 `OK_MMDD_SEARCH_DIR=F:\OpenKoikatsu\Saved\Repro\Addiction\mmd`）。
- **c-conquest**：使用者要求不玩遊戲，待命。恢復後等 c-street-city 通知第 2 輪（chain18 以後）完成，重跑錨點比對並更新 `Docs/STREET_CITY_GAME_NEEDS_INVENTORY_20261103.md` 第 8 節，再照 8.3 節把新場所接進遊戲端。打包改用 `--base-dir Saved/StreetSocial/BaseInt1104C`（`--skip-cook --skip-base`，新 tag）。
- **c-street-city**：chain21（遊樂園改放地面）已安裝、重建 places.json，但驗收、實走、重拍沒跑；恢復後先跑這些。82 個 world-tripo 模型還沒決定放哪；新地點（beach_house、jetski、festival、xmas_tree、batting、skating、fishing、bbq、amusement）要通知 c-conquest。Chrome 已能自己下載 Tripo，餘額 21040 點。未版控的工具留在工作樹：`Tools/street_city_motel_job.lua`（OK_JOB_MINUTES）、`Tools/prepare_street_city_motel_furniture_tripo.lua`、`Tools/remesh_street_city_asset.py` 等。

## 三邊工作樹留著的未提交改動

- **C**：`OKCharacterMCP.cpp`、`OKGalleryWidget.cpp`（來源不明）與 street-city 的工具與文件。C 原本 `Docs/STREET_ERRORS.md` 的未提交改動只是把幾列重新排序（內容相同），合併時改用提交版，備份在協調者 scratchpad（`C_STREET_ERRORS_WIP_20261104.md`／`.diff`）。
- **E**：E 主線的足交與保險套修正、`ONEONE_PERFECTION_CHECKLIST.md` 一列；e-okcard 舊 WIP（`OKResidentGpuPose.cpp/.h`、`OKCrowdRuntimeScene.cpp` 效能 hunk、`OKCrowdRuntimeProgressiveGpu.inl`、`KKPreviewLoading.cpp`）；`base_v1/missing.txt`。
- **F**：上述三個工具改寫的清單檔。
- **三邊**：`OKExtractBuildStamp.h` 是建置自動改的，不提交。

## Unreal slot

- slot 名稱：E 主線 `e-galgame`、e-fork `e-fork`、e-fork-2 `e-fork-2`（PRIORITY 沒有它，排最低）。兩個 session 不可共用 slot 名稱與沙盒（11-03 e-fork-2 誤關 E 主線遊戲）。
- 全機最多 3 個 Unreal（含 `UnrealEditor-Cmd` cook 與 `StreetSocialCity.exe`），用完馬上關、release。

## 清理

- 刪除 E 的開發 stage（Eye6～Eye20、EGal1～EGal8、EGalFoot1／2）、C／E 的 `Play-*`、`Rebuild-*`、`PatchRebuild-*`、舊的 `Int1103C`／`Int1103E` stage 與 `BaseInt1103C`／`BaseInt1103E`、驗證沙盒 `Integ1103*`／`Integ1104*`、F 的 `Verify-Int1103F`／`Verify-Int1104F`。
- `E:\OKHeadBuild` 已不存在，`git worktree prune` 清掉紀錄。三個專案與三個引擎都沒有額外的 git worktree。

## 待使用者決定

- 陰莖、插入、皮膚問題（龜頭穿出、正常位入口細黑線、桌球桌後入、口交斜側露出）何時處理；肛門深度上限要不要接回隨開發度 40%→90%。
- F 的 H 動作變體檔是否進版控（10-31 起未決）。
- 何時恢復 agent（使用者交代這次整合後不恢復）。

## 之後：原作資料移出版控（2026-11-04 凌晨）

整合後使用者另外要求：原作資料移出版控、打包 zip、寫還原腳本、改寫歷史並 force push。只在 C 處理，E、F 沒動。詳見 [原作資料移出版控](ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md)。

- 舊歷史備份：`https://github.com/damody/OpenKoikatsu` 的 `master2`（`8a57fc422`，含全部 LFS）。
- 新歷史：`damody2026/OpenKoikatsu` 的 `master`、`duo2` 都改寫並 force push；C 已對齊。**E、F 還在舊歷史**，下次恢復 agent 或整合前要先 `git fetch` 再 `reset --mixed origin/duo2`，絕對不能 merge 舊歷史。
- zip：`F:\backup\OKOriginalData_20261104.zip`；新 checkout 用 `Tools\lua\lua.exe Tools\original_data.lua restore --archive <zip>`。
- 測試用的乾淨 clone：`C:\portable\OKZipTest`（source＋zip，已實測遊戲與 OK Studio）、`C:\portable\OKRestoreTest`（原作＋zip）、改寫用 bare clone `C:\portable\OKRewrite.git`；確認不需要後可刪除（`OKZipTest` 的 `.stage` 裡有 junction，用 `cmd /c rmdir /s /q`）。