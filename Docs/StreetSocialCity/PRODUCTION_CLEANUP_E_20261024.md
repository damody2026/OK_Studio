# E 槽製作輸出清理（2026-10-24）

範圍為 `E:/StreetSocialCityProduction`，逐檔白名單清理，不遞迴刪除目錄、不走 junction、不修改 StreetSocialCity 專案。

## 清理前盤點

| 分類 | 約 GiB | 處理 |
|---|---:|---|
| environment-packages | 475.57 | 清過期封包、舊 cook 快取 |
| unreal-ddc | 34.23 | 保留，避免下次大量重編 |
| other-artifacts | 29.86 | 保留模型／圖面來源 |
| interior-repair-v1 | 15.83 | 保留 |
| campus-v1 | 9.08 | 保留 |
| world-ground-v1 | 6.80 | 保留 |
| immersion-audit-exports | 5.05 | 保留驗收資料 |
| plugin-builds | 1.90 | 保留 |

C 槽製作輸出有 123 個 junction／連結，其中許多指向 E 槽來源，不能將 E 槽視為無依賴的備份。

## 明確保留

- `environment-packages/20261023-145531/HostProject`：目前封包 receipt 指定的建置專案，包含最新 Saved/Cooked、原始碼、設定與 binaries。
- `environment-packages/20261023-122745/HostProject`：現有原生預覽腳本仍引用的 Editor 專案。
- 其餘 HostProject／plugin 原始碼、模型、材質、圖片、驗收資料及全部 DDC。
- `20261023-145531/Stage`、`20261023-213142/Stage`：兩份 E 槽備用封包。
- C 槽目前驗收通過的 `immersion-v1/packages/20261024-150235` 沒有改動。

## 刪除白名單

1. 上述兩份 Stage 以外的舊 Stage，以及所有舊 Archive 重複副本。
2. `environment-packages/20261023-122745/Cooked`、`environment-packages/20261023-131556/Cooked` 兩份舊 cook 生成檔；保留其目錄及 junction，沒有刪源 Content。歷史 cook 快取如需重用，必須重新 cook；目前 HostProject 的最新 cook 留存。

實際刪除 212,209 個檔案、402,292,436,498 bytes（約 402.29 GB／374.66 GiB），沒有跳過或失敗。E 槽可用容量觀察值從 80,747,376,640 增至 769,052,221,440 bytes（約 769.05 GB／716.24 GiB）。容量變化大於本次刪除檔案的邏輯大小，因此不把整個可用空間增幅全歸功於本次清理；正式刪除量採逐檔清單加總。

## 驗證與紀錄

- 刪除前確認目前 package ID 與 host 符合固定 receipt、候選未被程序使用，且沒有 Unreal／UAT／UnrealPak 執行。
- 每個候選驗證絕對路徑、目錄鏈沒有 reparse point、檔案不是連結，並比較原始盤點的大小與修改時間。變動檔案保留並記入 skipped。
- 保留的 556,152 個檔案大小／修改時間核對通過，沒有額外遺失。
- HostProject 執行檔 SHA-256 符合目前封包 receipt。
- 最終結果通過：9 個原有 E 槽連結全部未變，C 槽連結的 E 槽來源目錄全部存在。

詳細 inventory、links、delete-plan、deleted、skipped、result、preservation 及執行進度位於 `C:/portable/OpenKoikatsu/Saved/ProductionCleanupE/`。

`Tools/cleanup_street_city_production_e.lua` 是這次已盤點版本的限定執行器；未來版本必須重做盤點及保留策略，不能直接當作任意版本的全自動清理器。
