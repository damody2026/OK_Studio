# 2026-11-03 整合交接

使用者在 2026-11-03 約 17:00 要求整合 C／E／F 三個專案與三個引擎、暫停所有 agent、把已完成的工作提交並同步後推上 master、清掉 worktree 與沒在用的暫存檔；並要求 **F 的全部修改都提交並同步**（F 的功能有人要接手），以及 **推送前先瘦身**（不需要的 binary 不上傳）。本文件接在 [2026-11-02 整合交接](AGENTS_HANDOFF_20261102.md) 之後；協調者的工作方式、整合流程、各 agent 的規則仍以 [2026-11-01 整合交接](AGENTS_HANDOFF_20261101.md) 為準，這裡只寫變動與現況。

## 整合結果

| 項目 | 狀態 |
|---|---|
| 專案 | C `master`、E `duo2`、F `duo2` 都快轉到合併提交 `33506b4eb`（併 E：`319303c04`、併 F：`33506b4eb`），推上 `origin/master` 與 `origin/duo2`；本文件另外提交 |
| 引擎 | `D:\PhysX\UE5.8`、`E:\PhysX\UE5.8`、`F:\UE5.8` 都在 `11576da863ff`，這輪沒有變動 |
| Rust | `ok-extract` 預設與 `--no-default-features` 都 `cargo check` 通過；`ok-rules` 257＋3 測試通過、`--no-default-features` 通過；`ok-mind`、`ok-game-mcp` check 通過（全部 `-j 8`） |
| C 街區 | 完整重建 `Int1103C`，base `Saved/StreetSocial/BaseInt1103C`（D: 引擎），cook 0 錯 0 警告；sandbox `Integ1103C` 實際啟動到「所有角色已就緒」 |
| E 街區 | 完整重建 `Int1103E`，base `Saved/StreetSocial/BaseInt1103E`（E: 引擎），cook 0 錯 0 警告；sandbox `Integ1103E` 實際啟動到「所有角色已就緒」 |
| F OK Studio | 編輯器與遊戲目標建置連結成功；`verify_ok_studio.lua --tag Int1103F` 6/6 通過（`F:\OpenKoikatsu\Saved\OKStudio\Verify-Int1103F`） |

建置時三邊未提交的程式先 `git stash` 停放（只建已提交的內容），建完放回。合併衝突只有 `Docs/STREET_ERRORS.md`，以兩邊的列都保留（union）解決。

## 瘦身（LFS）

- 三邊 `.git/lfs/objects` 原本各約 490～583 GB（36k 個物件，大多是 base_v1 歷次重錄的舊版本）。全部互相複製時把 E 槽寫滿（0 GB），已停止並改做法。
- 以 `git lfs prune --verify-remote` 刪掉三邊已在 GitHub 上、近期 commit 不再引用的舊物件（每邊約 21,600 個、約 567 GB）。之後 C 剩 665 GB、E 剩 441 GB、F 剩 1,314 GB。需要舊版本時 `git lfs fetch` 可從 GitHub 取回。
- 本輪推送要上傳的 LFS 只有 129 個物件、約 4.8 GB：F 重錄的 base_v1 okmodel 127 個（3.7 GB）與 `sources.okidx`（1.1 GB）。
- 已知：`base_v1/anims/studio/*.okanim` 有 5,805 個檔案在 git 內是一般 blob 而非 LFS 指標，`origin/master` 本來就這樣，這輪沒改。

## 本輪併入的提交（9416704b3 之後，120 個非合併提交）

- **C（35）**：c-conquest R6-147～R6-172（飲料客製、行程、合照、宿舍「一起打電動」等），最後 `02a9ddd7b`；c-street-city 戀人地點、汽車旅館 209／203 床位置、places.json 重建，最後 `92aaa0cb6`；協調者 `9a224f132`（unreal_slot 的 e-fork 優先序）。
- **E（49）**：書籤與事後時間、H 經驗與懷孕邊界測試、服務次數換姿勢繞過修正、含著／戴套台詞、記恨 ≥90 拒絕單獨進房、H 場景補充（懷孕延伸、摸與親、水槍體液、結果統計、啊嘿顏），最後 `a237f125f`。
- **F（36）**：OK Studio U149～U168、ok-extract 植物 LOD／寬 UV／天空、**以及使用者要求的 F 全部修改**：okchara（新版 OK 卡 okCh、`ok-chara` 工具、`make_ok_chara_card.lua`、`Docs/OK_CHARA_CARD.md`）、base_v1 重錄 okmodel／`converted.tsv`／`missing.txt`／`sources.okidx`／`studio/sky.json`／`shader_states.json`、KStudio 匯入場景的 `.okscene`／`.import.json`（角色以本機 `_cards` 參照）與 Studio 截圖，最後 `abede2ca6`。

## 各 agent 暫停時的狀態與下一步

| agent | session | checkout |
|---|---|---|
| E 主線（一對一 H） | `local_aa5c7d4c-6156-46b9-b8e1-27aaecbea477` | `E:\OpenKoikatsu` |
| e-fork（一對一，使用者自己帶的對話） | `local_9e379b04-7799-4d85-94cc-580b2d7f6f52` | `E:\OpenKoikatsu` |
| F（OK Studio） | `local_705cc0ce-72ee-49cf-99da-588059f7b129` | `F:\OpenKoikatsu` |
| c-conquest | `local_5567d4d2-964d-485f-94d0-6520c0da73c5` | `C:\portable\OpenKoikatsu` |
| c-street-city | `local_9c146b39-2af2-41cc-8a68-98cb6aa12e6e` | `C:\portable\OpenKoikatsu` |

### E 主線

- 恢復後第一件：**開發度 A 方案**（協調者在無人值守期間代使用者決定，使用者可改）：`hexp.rs` 結束時開發度只加 +10×高潮，countKokanH（crotch_h／anal_h）只用來判斷經驗等級（不慣れ／慣れ），改掉刻意相加的測試，`STREET_ERRORS` 記「協調者 11-03 代決定 A，使用者回來可改」。
- 之後繼續換女主與組合實玩（1～10 號都至少玩過一輪），找到問題就修。
- 陰莖角度、插入、皮膚 mesh 照使用者指示只記錄不改。
- `E:\OKHeadBuild` 已刪除；只建已提交內容時請重新 `git worktree add`（用完即刪），或在主工作樹 stash 後建。

### e-fork

- 工作樹未提交（自己的，未驗證）：
  - 眼睛視線：`KKPreviewActor.cpp/.h`、`KKSkeletalBuilder.cpp/.h`、`Tools/ok-extract/src/eye_gaze.rs`、`ffi.rs`、`OKHScene.cpp` 的 AhegaoGaze 預設值（`KKPreviewActor.cpp` 裡有一段要刪的 DIAG log）。
  - 胸／臀物理分開：`Tools/ok-extract/src/dbone/ver02.rs`、`ffi.rs`、`include/ok_extract.h`、`KKRustExtract.cpp/.h`、`KKPreviewActor.cpp` 的 `ok.Physics.*` CVar。
- 下一步：眼睛 UV 寫進 morph 元件的實機驗證、屁股物理實測、街區平時模式的眼睛控制（使用者新要求）、補 `6029f8b4c` 在乾淨建置的驗證。
- Unreal slot 名稱用 `e-fork`（與 e-galgame 同級，各自排隊）。今天曾四次沒拿 slot 就開遊戲，原因是 `claim e-galgame` 會回傳 E 主線已持有的 slot。

### F

- 第三十三批 U164～U168 完成；下一步第三十四批 U169～U172（見 `Docs/OK_STUDIO_UI_WORKFLOW_PLAN.md`）。
- F 的功能有人要接手：F 的工作樹已全部提交，只剩被 hook 擋下的三張 PNG 場景卡（`UserData/Studio/scene/scene_20261031_183348.png`、`scene_20261102_125742.png`、`教室三人_20261101_031235.png`）與 `UserData/Studio/import/`（角色卡）。
- base_v1 重錄清單（`Tools/oklib_rerecord/u143_channel_dimension.txt`、`u149_wide_uv.txt`）的結果已隨 `e4d9e438b` 提交，C、E 不必再重錄。

### c-conquest

- 第 12 輪，存檔欄位 6（遊戲日 10/4（一）20:56）。恢復後讀第 6 格，約三月七試「一起打電動」（`33042f79c`，未在遊戲內驗證），接著玩 10/5。尚未在遊戲內重現驗證：R6-165、R6-167、R6-168。
- 打包改用新 base：`--base-dir Saved/StreetSocial/BaseInt1103C`（`--skip-cook --skip-base`，新 tag）。
- 暫停時 DeepSeek 回 503（服務太忙），女角說不出話；恢復時先確認 API 恢復。

### c-street-city

- 地圖 sha `3b918b72…`：戀人地點 24 處與汽車旅館 209、203 床邊鏡重裝的驗收 TRIAL DONE，實走 slice 0 通過；slice 1～3 與截圖（`world-edge-v1/lover-spots-views.json`）未跑。恢復後先跑這些，看斜坡上的神社與販賣機。
- 只改場景，不碰 C++；一次只開一個 Unreal／Blender，slot 最低優先，背景鏈每步 `yield`。

## 三邊工作樹留著的未提交改動

- **E**：e-fork 上述兩件 WIP；e-okcard 舊 WIP（`OKResidentGpuPose.cpp/.h`、`OKCrowdRuntimeScene.cpp`、`OKCrowdRuntimeProgressiveGpu.inl`、`KKPreviewLoading.cpp`）。E 原本的 `base_v1/missing.txt` WIP 因與 F 提交衝突改用提交版，舊內容備份在協調者 scratchpad（`E_missing_txt_WIP.txt`）；E 本機兩組重新匯入的場景（`83283571_p1`、`koikatu_cs0004432`）與提交版不同，已改用提交版。
- **C**：`OKCharacterMCP.cpp`、`OKGalleryWidget.cpp`（來源不明）與先前未提交的 street-city 工具與文件。
- **三邊**：`OKExtractBuildStamp.h` 是建置自動改的，不提交。

## Unreal slot 與巡檢

- `Tools/unreal_slot.lua` 的 PRIORITY 加上 `["e-fork"] = 1`（C `9a224f132`、E `c84154466`、F `d01e4b93e`，內容相同）。slot 資料夾三邊共用，三邊的副本必須一致，否則不認得的名字會被排到最低。
- 使用者 11-03 新規定：
  - ok 系列程式（ok-extract、ok-rules、ok-game-mcp、ok-city-props、ok-mind）與其 cargo 建置測試最多 8 個執行緒（`-j 8`、`RAYON_NUM_THREADS=8`）。
  - Unreal（遊戲、編輯器、Studio）用完要自己馬上關掉並 release slot，不要一直開著（會鎖住編譯、浪費算力）。
- 協調者計數 Unreal 時也要算 `UnrealEditor-Cmd.exe`（cook 用）。

## 清理

- 刪除 E 的開發 stage 71 個（Belly*／Hair*／Cover*／HOutfit*／HPose*／Climax*／Preg1／Onani*／BackDiag1／DevStep*／Add*／Eye*）、C 的 Conq1103a～y stage、兩邊的 `Play-*`、`Rebuild-*`、`PatchRebuild-*` 紀錄、22 個舊的驗證 sandbox（`Verify*`、`integ1029`、`VoiceTest`、`SelfT`、`VoiceOff`、`Phys1028B/C`、`Fresh27`）、`E:\Saved\okx-*`。
- 刪除 `E:\OKHeadBuild` worktree。三個專案與三個引擎都沒有額外的 git worktree，`.claude/worktrees` 也沒有。
- 舊的 `Int1102C`／`Int1102E` stage 與 `BaseInt1102C`／`BaseInt1102E` 在新版確認後刪除。

## 待使用者決定

- 開發度 A／B（協調者已代決定 A，可改）。
- 腹部包覆走哪條（B／B 加套筒／肚皮骨），以及何時接回深度上限。
- F 的 H 動作變體檔是否進版控（10-31 起未決）。
- 喘息加速的聽感。

## 恢復 agent

巡檢排程已刪除，五個 agent 都停在等恢復指示。恢復時重建二十分鐘巡檢（`CronCreate`），把本文件各 agent 的下一步派給對應 session。
