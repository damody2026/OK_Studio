# 2026-11-04 下午整合交接（新歷史）

使用者在 2026-11-04 要求把 E、F 更新到 C 的新歷史（版權物移出版控，但檔案不刪、繼續開發）、暫停所有 agent、同步三個專案與三個引擎、清掉沒在用的暫存檔，做完後恢復所有 agent，再進入 72 小時無人值守（到 2026-11-07 13:20）。本文件接在 [2026-11-04 整合交接](AGENTS_HANDOFF_20261104.md) 之後，各 agent 的工作內容與下一步仍以那份的「各 agent 暫停時的狀態與下一步」為準，這裡只寫變動。

## 現況

| 項目 | 狀態 |
|---|---|
| 遠端 | `origin` 是 `https://github.com/damody2026/OK_Studio.git`（公開倉庫），只推 `master`。絕對不要 `git push --tags` 或 `--mirror`：本機的 `old-history-*` 含原作資料 |
| 專案 | C `master`、E／F `duo2` 都在同一個提交（本文件所在的提交）；E 的 `duo2` 工作樹留著 WIP，F 有兩份未追蹤文件 |
| 舊歷史備份 | E、F 的分支 `old-history-duo2-20261104`；reset 前的 patch 與資料副本在 `C:\portable\OpenKoikatsu\Saved\Integration20261104\` |
| 引擎 | `D:\PhysX\UE5.8`、`E:\PhysX\UE5.8`、`F:\UE5.8` 都在 `11576da863ff`。`F:\UE5.8` 顯示 16 個修改只是換行屬性，內容相同，不用處理 |
| C 街區 | stage `Int1104NC`，base `Saved/StreetSocial/BaseInt1104NC`（D: 引擎） |
| E 街區 | stage `Int1104NE`，base `Saved/StreetSocial/BaseInt1104NE`（E: 引擎） |
| F OK Studio | `verify_ok_studio.lua --tag Int1104NF` 全部通過 |
| 開發資源 zip | `C:\portable\OKOriginalData_20261104d.zip`（9.17 GiB）、`C:\portable\OKHVoices_20261104b.zip`（12.19 GiB） |

## 恢復時要告訴 agent 的事

- 歷史已改寫，舊提交編號都失效：舊 `8a57fc422` ＝新 `fc47305e1`。不要 merge 舊歷史，不要把 `base_v1/`、`RuntimeAnimations/*.okanim` 等加回版控（hook 會擋）。檔案都還在磁碟上，開發照常。
- 打包改用新 base：C `--base-dir Saved/StreetSocial/BaseInt1104NC`、E `--base-dir Saved/StreetSocial/BaseInt1104NE`（`--skip-cook --skip-base`，新 tag）。舊的 `BaseInt1104C`、`BaseInt1104E` 已刪除。
- 街區遊戲只用 TTS，不再放原作語音；H 語音另外打包，沒裝時 H 場景沒聲音。
- 共用 mod 清單少了 5 行（mizuha clothes ×2、cleavage shirt ×2、虛子的 mishiki_tight2；原版 `abdata/chara/mishiki_suit.unity3d` 仍是共用資源）。`Tools/base_library_shared_mods.txt` 現在是提交版，F 舊交接裡「工具改寫、不要提交」那段已不適用。
- OK 卡因此全部重封過（見下）。自己的測試卡若出現 `the OK card lacks N thing(s)`，用 `ok-extract X:/NoGame --oklib seal <base_v1> <卡> --out <資料夾>` 修，`okId` 不變，存檔不受影響。

## OK 卡重封

移除 mizuha 後幾乎所有 OK 卡都開不了（它覆蓋原版的 `mt_mask_body_00`、`mt_mask_bra_00`，見 `Docs/ERROR_LOG.md`）。三組的 `Content/CharacterCards/StreetHeroines`、`Demo`、`CrowdAPNG`、`output/StreetSocialAPNG/Male01.png` 與 `UserData/Studio/import`、`UserData/Studio/scene` 的 `*_cards` 都已處理，全部通過 strict 驗證：497 組用 `seal` 補齊，650 張 `seal` 補不了的用 `ok-extract D:/KoikatuSunshine --oklib card <base_v1> <OK 卡> <輸出>` 從遊戲重轉（保留身分）。後者多是 10 月的舊匯入卡，缺基礎庫裡沒有的第三方 mod 資料或 `skel:bone_implants`。報告在 `C:\portable\OpenKoikatsu\Saved\Integration20261104\verify-sealed.txt`、`verify-remade.txt`。原卡備份在 `C:\portable\OpenKoikatsu\Saved\Integration20261104\cards-before-seal\`（街區、Demo、CrowdAPNG；Studio 卡沒備份）。

## 已知未解

- C 完整本機庫的 `kks-verify` 有 5 張卡和 `D:/KoikatuSunshine` 的 live 結果不同，乾淨 clone 有 4 張相同，原因沒查出來。要在 C 把原作卡轉成新 OK 卡時，先比對一張再大量轉。
- `Relife - 日代千鹤.png` 用到沒有指名的 zipmod，沒有遊戲時無法完全還原。
- 其他驗證結果與只靠遊戲還原的缺口見 [原作資料移出版控](ORIGINAL_DATA_OUT_OF_GIT_PLAN_20261104.md) 第六節。

## 清理

- 刪除 C 的 `TtsOnly1104*`、`Int1104C` stage、`BaseInt1104C`、`Rebuild-TtsOnly*`、`Play-*`、沙盒 `TtsOnly`、`Integ1104N*`；E 的 `Int1104E` stage、`BaseInt1104E`、`Play-*`、沙盒 `Integ1104NE`；E、F `CrowdAPNG` 裡 10-24 留下的 `.okremake-*.png`。
- 刪除 `C:\portable` 的 `OKZipTest`、`OKRestoreTest`、`OKHVoiceTest`、`OKRewrite.git`、`OKPublish.git`、`OK*.paths.txt`，以及 `Saved/OriginalData` 的建置目錄。
- 留下：`C:\portable\OKPointer`、`C:\portable\OKGameOnly`（只靠遊戲還原的乾淨 clone，查 `kks-verify` 差異時要用）、zip、agent 自己的沙盒、`F:\backup`。
