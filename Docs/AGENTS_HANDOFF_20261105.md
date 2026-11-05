# 2026-11-05 整合交接

使用者在 2026-11-05 晚上要求暫停所有 agent、同步 C／E／F 與三個引擎、提交已完成的工作、整合後推上 `master`、清掉 worktree 與沒在用的暫存檔。11-04 開始的 72 小時巡查到此結束，巡查排程已刪除。使用者沒有要求恢復 agent，所有 agent 維持暫停，等使用者開口。

## 現況

| 項目 | 狀態 |
|---|---|
| 專案 | C `master`、E／F `duo2` 都在同一個提交（本文件所在的提交），已推上 `origin/master` |
| 引擎 | `D:\PhysX\UE5.8`、`E:\PhysX\UE5.8`、`F:\UE5.8` 都在 `11576da863ff`。`F:\UE5.8` 顯示的 16 個修改只有換行不同 |
| 建置 | 三邊的 `OpenKoikatsu` Development 與編輯器都連結成功，C 的 `cargo check` 預設與 `--no-default-features` 都通過 |
| C 街區 | stage `Int1105C`，base `Saved/StreetSocial/BaseInt1105C`（D: 引擎），11 位角色就緒，`game.log` 沒有 Error |
| E 街區 | stage `Int1105E`，base `Saved/StreetSocial/BaseInt1105E`（E: 引擎），11 位角色就緒，`game.log` 沒有 Error |
| 讀卡 | C、E 的 `CardReaderDevelopment` 都開得起來，只有已知的 CommonUI 訊息 |
| F OK Studio | `verify_ok_studio.lua --tag Int1105F` 六項全部通過 |
| 基礎庫 | F 重產的 `studio/sky` 與 Studio 節點模型（142 個檔）已複製到 C、E，manifest 已更新，開發資源 zip 已重打 |

## 恢復時要告訴 agent 的事

- 打包改用新 base：C `--base-dir Saved/StreetSocial/BaseInt1105C`、E `--base-dir Saved/StreetSocial/BaseInt1105E`（`--skip-cook --skip-base`，新 tag）。
- 用工作樹編 stage 用的 exe 時要換成 host 的 `.uproject`，完整 `.uproject` 建的 exe 會多連結外掛，一啟動就崩潰（`EGalRound15`，見 `Docs/STREET_ERRORS.md`）。打完 stage 先開一次才能給 tag。
- 控制通道現在所有模式常開（`Docs/GAME_CONTROL_CHANNELS.md`）；舊的 `ok-game-mcp.exe` 要重建才有 `game_instances`、`ui_*`、`reader_call`、`pair_call`。
- Unreal slot 優先序：`FStyle` > e-galgame／e-fork／e-fork-2 > F > c-conquest／e-okcard > c-street-city。改優先表前先看有沒有 `claim --wait` 在跑，否則會排隊死結（`Docs/ERROR_LOG.md`）。

## 各 agent 暫停時的狀態與下一步

| agent | 最後的工作 | 下一步 |
|---|---|---|
| E 主線 | 舌頭、騎乘位鏡頭、`game_launch` 修正、胸部逐幀量測 | 機器安靜時量 H 場景 FPS（兩輪都不算安靜）；胸部要不要忽略對方手臂等決定 |
| e-fork | 沒有待辦 | 等使用者指示。眼睛測試已被使用者叫停 |
| e-fork-2 | 瞳孔滑桿、瞳孔貼圖、改色與愛心 | 沒有待辦 |
| F 主線 | U237～U241 | `Docs/OK_STUDIO_UI_WORKFLOW_PLAN.md` 下一批；U240～U241 已在整合建置驗證 |
| `FStyle` | Q 版／寫實比例、下巴、Q 版胸部，13 張卡重拍 | CardReader 下巴滑桿還沒實測；手腕配件跑位；風格 MCP 工具等使用者說開始 |
| `f-mcp-all-modes` | 控制通道常開、`style.` 滑桿 | 沒有待辦 |
| c-conquest | 文件 | 核對 c-street-city 交回的三項（民宿客房、被擋錨點、樓梯扶手）。新地點接進遊戲要等使用者開口 |
| c-street-city | 民宿、被擋錨點、樓梯扶手，打包 `20261105-174535` 四段實走全過 | 補拍 `R7-minshuku-*`，最後一輪的馬桶、顏色、燈光還沒看過畫面 |

## 沒有進這次整合的東西

- E 工作樹有一批沒有 agent 認領的修改（人群 GPU `OKResidentGpuPose`、`OKCrowdRuntime*`、`KKPreviewLoading.cpp`），不確定是否完成，所以沒有提交，已從工作樹移出。patch 在 `C:\portable\OpenKoikatsu\Saved\Integration20261105\E-wip-crowd-preview.patch`。`Docs/STREET_ERRORS.md` 的列順序差異另存在同目錄 `E-wip-street-errors-order.patch`，內容沒有增減。
- C 根目錄的 `grok-media/` 與 `shop-1080p-all.png` 是圖片，沒有進版控，留在本機。

## 已知未解

- `C:\portable\OKGameOnly` 的 `kks-verify` 差異（見 [11-04 下午交接](AGENTS_HANDOFF_20261104B.md)）沒有再查。
- 這次改了基礎庫但沒有重跑乾淨 clone 的 `kks-verify` 與 `okcard-check`；只用 `original_data.lua verify` 比對三邊與 manifest。
- 這次整合只驗到開遊戲、角色就緒、讀卡開啟與 OK Studio 六項，沒有逐項玩過 H 場景與新地點。
