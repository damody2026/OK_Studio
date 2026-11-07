# OK Studio：C／E 同步前要知道的事（2026-11-07，F 組）

F 的 `duo2` 同步到 C、E 時，場景檔與控制通道會碰到的差異。這裡只記查到的狀況，**F 組沒有做同步**。

查的基準：F `duo2`（U260 之後）、C `master` 463402e62、E `duo2` 83c09ef66。

## 場景卡版本

| 寫入端 | 版本 | C／E 現在能開嗎 | 同步後 |
|---|---|---|---|
| C、E 現在的程式 | 1 | 能 | 能，F 保留版本 1 的讀取 |
| F，場景沒有動作檔與音樂 | 2 | **不能**，顯示「scene card version 2 is newer than this build」 | 能 |
| F，場景帶動作檔、語音或音樂 | 3 | **不能**，同上 | 能 |

- C、E 的 `OKSceneCard.cpp` 還是 `PayloadVersion = 1`，比盤點時想的舊一版，所以不只版本 3，**F 存的每一張場景卡 C、E 都開不了**。
- 開不了時只有錯誤訊息，不會損壞檔案。
- 風險在順序：同步前把 F 存的卡拿到 C、E 開會失敗。同步後舊卡都能開，不用轉檔。
- 反方向沒有問題：同步後新程式存的卡，舊版程式一樣開不了，所以三組要一起更新，不要只更新一組。
- `.okscene`（純 JSON）不受影響，三邊 `FormatVersion` 都是 3。

## 場景的新欄位

| 欄位 | 舊程式讀到 | 新程式讀舊檔 |
|---|---|---|
| `FaceStyle`（角色與 key，F 風格組） | 忽略，臉跟著身體走 | 預設 -2，表示臉跟身體同一個 `Style`，和舊場景看起來一樣 |
| `view`（`SavedView`，存檔時的視角） | 忽略，用舊的取景 | 沒有這欄就走舊流程 |

- 兩邊都不會讀檔失敗，JSON 用 `JsonObjectToUStruct`，未知欄位直接略過。
- 舊程式重新存檔時，這些欄位會被丟掉。同步前不要用 C、E 存 F 做的場景。

## 動作檔與音樂

- VMD 動畫檔名多了內容的 CRC（`vmd_2_dance_d081123e.okanim`）。舊場景存的是舊檔名，路徑照舊有效，不用改。
- 卡裡的動作與音樂開卡時解到 `<場景>_cards/`。

## 自動化腳本

新程式有兩個行為不同，C、E 的腳本要注意：

- `studio_load` 回覆後場景還在建，`busy` 是 `loading`。開場景後馬上動物件會被拒，要等 `busy` 清空。驗收用的 `bSyncBuildsAll` 路徑不變。
- 開啟中控制通道只放行 `click`、`mouse`、`key`、`select`、`load`、`leave`，以及 `scene.new`、`app.quit`。`add.map` 這類 `cmd` 在開啟中會回 `busy: loading`。

## 本機資料

- 地圖縮圖在 `Saved/OKStudio/MapThumbnails/`，不進版控，同步不會帶過去，每組按一次「製作縮圖」，全部約 6 分鐘。
- 輸出範圍不再記住上次的值（U262）；`settings.json` 舊的 `export_choices` 照讀，只是不用裡面的起訖秒數。

## 合併時的衝突點

F 這輪改動集中在 `OKSceneActor.cpp`、`OKStudioGame.cpp`、`SOKStudioPanel.h`、`SOKStudioBrowsers.cpp`、`SOKStudioWindows.cpp`、`OKStudioControl.cpp`、`OKSceneCard.cpp`。C、E 改到同檔時要逐段看。

同步後建議的驗收：

1. 在 C、E 開一張 F 存的版本 3 場景卡，確認動作與音樂都在。
2. 開一張 C、E 自己以前存的版本 1 卡。
3. 跑 `kks-verify`、`verify_ok_studio.lua`、`scene2_classroom`。
