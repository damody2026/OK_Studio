# 2026-11-07 整合交接

使用者在 2026-11-07 早上要求暫停所有 agent、同步 C／E／F 與三個引擎、提交已完成的工作、推上 `master`、清掉 worktree 與暫存檔。11-06 開始的 96 小時巡查到此結束，排程已刪除。所有 agent 暫停，等使用者開口才恢復。

## 現況

| 項目 | 狀態 |
|---|---|
| C、F | 都在本文件所在的提交，已推上 `origin/master`。C 的 `cargo check` 兩種設定通過，C、F 的遊戲與編輯器連結成功 |
| E | **沒有同步**，停在 `83c09ef66`（`duo2`），比 master 舊 |
| 引擎 | `D:\PhysX\UE5.8`、`E:\PhysX\UE5.8`、`F:\UE5.8` 都在 `11576da863ff` |
| C 街區 | stage `Int1107C`，base `Saved/StreetSocial/BaseInt1107C`，cook 0 錯誤。啟動後角色載到 10/11 時已可遊玩，`game.log` 沒有 Error；11/11 沒有等到 |
| 基礎庫 | C 的 `original_data.lua verify`：153803 相同，1 個 `base-byproducts` 不同（已知的 `missing.txt`），沒有變動，不用重打開發資源 zip |

## 沒有進這次整合的東西

- **E 的提交與工作樹：** E 比舊 master 多 8 個提交，主要是 H 場景內容，涉及看起來未成年的角色，協調者不合併也不推送。`f8fc72b7c` 的修正 C 已有同樣的版本。E 工作樹有 30 個未提交的檔案，其中 11 個和 master 的改動重疊，所以也沒有把 master 合併進 E。這些都原樣留在 `E:\OpenKoikatsu`。
- **未驗證的修改**（patch 在 `C:\portable\OpenKoikatsu\Saved\Integration20261107\`，已從工作樹移出）：
  - `C-wip-conquest-finance.patch`：刮刮卡與帳簿用地區幣別、夜班顯示、彩券名稱轉簡體，編過但沒進遊戲。
  - `F-wip-U263.patch`：OK Studio 第 14、15 項與按鈕檢查，連結成功但最新版沒實測。
- C 根目錄的 `grok-media/`、`shop-1080p-all.png` 留在本機，沒進版控。

## 恢復時要告訴 agent 的事

- C 打包用 `--base-dir Saved/StreetSocial/BaseInt1107C`，加 `--skip-cook --skip-base`，用新 tag。E 的 `BaseInt1105E` 沒動。
- Unreal slot 優先序：c-conquest、c-street-city > FStyle > e-galgame／e-fork／e-fork-2 > F > e-okcard。兩個 fork 要用自己的名字 claim。
- E 沒同步，讀不了 F 存的版本 2 場景卡，見 `Docs/OK_STUDIO_SYNC_NOTES_20261107.md`。

## 各 agent 的下一步

| agent | 下一步 |
|---|---|
| F 主線 | 套回 `F-wip-U263.patch`，實測第 14、15 項 |
| FStyle | 下巴公式等使用者判斷（看新版 `real_eye`）；風格 MCP 工具等使用者開口 |
| c-conquest | 套回 `C-wip-conquest-finance.patch` 並進遊戲驗證；實玩還沒跑到一輪無新問題 |
| c-street-city | 第 85 輪三戶新床補拍照片；泳池台階懸空誤判要改 `StreetSocialCity` 的 C++，不在它的範圍；水族館空玻璃缸 |

## 清理

- 刪除 F 的 worktree `F:\OKVerifyStyle`（先拆 `BpGeneratorUltimate` junction，外掛本體還在）。
- 刪除 C 的舊 stage（`Audit*`、`Int1105C`）、`BaseInt1105C`、`Rebuild-*`、`Play-*`、整合測試沙盒，共約 23.8 GB。
- `F:\okx-u36`、`E:\okx_okcard`、`E:\OKRustTarget` 還在：工具擋下刪除磁碟根目錄下的資料夾，要使用者自己刪。

## 已知未解

- `street_onani_*` 動作片段出現在餐廳、圖書館等公共場所，協調者沒有派人處理，等使用者決定。
- E 沒有建置或啟動驗證，這次也沒開 `CardReaderDevelopment.cmd`。
- 乾淨 clone 的 `kks-verify`、`okcard-check` 沒跑。
