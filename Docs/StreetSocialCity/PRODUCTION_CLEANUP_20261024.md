# 製作輸出清理（2026-10-24）

範圍僅限 `C:/portable/OpenKoikatsu/output/street-social-city-production`。沒有修改 StreetSocialCity 專案、E 槽來源、模型、材質、生成參考圖及實拍驗收圖片。

## 結果

- 刪除 1,492 個檔案，邏輯大小 596,280,160,508 bytes（555.33 GiB）。
- C 槽可用容量由 11,913,207,808 增加到 587,385,167,872 bytes，實際增加約 575.47 GB／535.95 GiB。邏輯大小與磁碟可用容量變化分開記錄，不視為相同數字。
- 1,277 個已被取代的 Stage／Archive 封包檔；215 個有更新且非空 `.blend` 原檔的 `.blend1` 自動備份。
- 盤點中其他檔案沒有額外遺失；保留封包的 352 個檔案大小及修改時間全部一致；123 個 junction／連結的目標全部一致。
- 目前版本執行檔 SHA-256 仍符合既有 package receipt；未為清理重新啟動遊戲。

## 保留的封包

| 路徑（相對製作輸出根目錄） | 用途 |
|---|---|
| `immersion-v1/packages/20261024-150235` | 目前 runtime 驗收成功的版本 |
| `immersion-v1/packages/20261024-135124` | 既有 506 張 checkpoint 實拍的來源版本 |
| `flat-campus-v1/packages/20261024-014032` | 該階段最後封包 |
| `traffic-v1/packages/20261024-031628` | 該階段最後封包 |
| `pk0102-floor-v1/packages/20261023-215553` | 該階段唯一封包 |

舊封包對應的歷史 JSON、log 與照片保留，作為歷史證據；其中指向已清除 Stage 的舊路徑不能再直接啟動，需重新打包。

## 安全界線與紀錄

盤點不走 junction，刪除前逐層檢查絕對路徑與 reparse point；僅刪 inventory 中大小及時間仍一致的白名單檔案。檢查候選封包未被程序使用，未停止任何程序。沒有遞迴刪除目錄。

清理後的額外空資料夾刪除命令遭工具自動審核拒絕，回覆僅為 `blocked by policy`，因此沒有繼續刪空資料夾；不影響已釋放的大檔容量。

詳細紀錄位於 `C:/portable/OpenKoikatsu/Saved/ProductionCleanup/`：

- `inventory.csv`、`links.csv`：清理前盤點。
- `delete-plan.csv`、`plan.json`：精確候選清單與保留策略。
- `deleted.csv`、`skipped.csv`、`result.json`：實際刪除與容量結果。
- `verification.json`：保留封包及 junction 驗證。

`Tools/cleanup_street_city_production.lua` 是本次盤點的限定執行器，包含固定版本與 inventory 前置條件；未來版本應重新盤點並更新保留清單，不能直接視為任意版本的全自動清理器。

## 後續空間管理

每次成功驗收新包後，確認目前使用版本與驗收 checkpoint，再清理被取代的 Stage；避免每輪產生 Stage 與 Archive 的重複長期副本。來源模型、材質、remesh 產物與仍有依賴的測量資料不應僅因資料夾名稱較舊就刪除。
