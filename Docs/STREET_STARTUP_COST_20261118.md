# 街區開場成本（2026-11-18）

從 `game_launch` 到能和女角說話要多久、時間花在哪裡。量測：c1118f，`-NoCloud -Sandbox Check1116`，機器上只有這一個 Unreal（另兩台同時跑時是 105–165 s，不能拿來當開場成本）。

## 分段（c1118f，79 s）

| 段 | 秒 | 在哪裡 | 誰的 |
|---|---:|---|---|
| 啟動器 | 12.1 | 選角準備 11.2 s（`Tools/prepare_street_social_selection.lua`），其餘 0.9 s | 啟動器 |
| 引擎初始化 | ~2 | 進程啟動到 LoadMap | 引擎 |
| LoadMap | 24–27 | 其中約 17 s **完全沒有 log**：World Partition 初始 cell 載入（`UWorldPartition::Initialize` 之後到第一個 cell 的 `AttachTo`）；之後是街區場景初始化 | 地圖 |
| 控制通道就緒 → 11 個角色可見 | 29–35 | 約每 3 s 一個；卡頓幀都在 `STAT_OKCrowd_Prepare`／`Commit`／`Install`（單幀 100–220 ms） | crowd runtime |

啟動器分段由 `launch timing` 行記錄（`Tools/run_street_social_development.lua`，6b512d03e），在 `Saved/StreetSocial/ok-game-mcp-launch-<port>.log`。

## 已處理

- **對話目錄快取**：`dialogue.runtime.json`（29.8 MB）、`rules.json`、`topics.runtime.json`、`relationships.runtime.json` 只取決於目錄來源檔與寫它們的程式，和選角無關。改成做一次放在 `Saved/StreetSocial/DialogueCache/<key>/`，key 是全部輸入的 SHA-256：`catalogue.json`、`zh_tw.json`、`topics.json`、`rules.json`、`relationships.json`、`prepare_street_social_selection.lua`、`build_street_social_localization.lua`、`Tools/lua/ok/json.lua`；任何一個變了就重做。先寫進暫存資料夾再整個改名，兩個啟動器同時跑不會讀到一半。快取出的四個檔與舊做法逐位元組相同。
- **`.ja` 不再另寫**：`dialogue.runtime.ja.json` 和 `dialogue.runtime.json` 內容完全一樣（日語模式讀同一份的 `text_jp`）。讀它的是遊戲的語言切換（`OKStreetSocialScene.cpp`，`S.OtherLanguage`）：manifest 的 `dialogue_catalogue_ja` 現在指向同一個檔，遊戲看到同一路徑就複製已解析的目錄，不再讀第二次。
- **服裝缺件檢查並行**：每張卡一個 `ok-extract --oklib outfit-gaps`，原本一個接一個；改成一次四個、每個兩條執行緒（ok-* 工具合計不超過 8 條）。結果與循序版相同。

- **開局第 3 幀**：`TickInitiative` 卡 305–704 ms，細項 scope 指出全在第一次 `holiday` 規則呼叫：`events.rs` 的 `unwrap_or(&BUILTIN)` 先求值參數、解開 LazyLock，已安裝節日表也照樣在遊戲執行緒上解析整份內建 tuning（22cf299f6）。`Bankruptcy` 卡 72–185 ms，是 ok-mind 金融 `summary` 第一次才讀市場資料（ab47ee102，改在 ok-mind 的 preload 執行緒先讀）。

### 前後對照（c1118f → c1118g，同機、Check1116）

| 項目 | 前 | 後 |
|---|---:|---|
| 啟動器「selection prepared」 | 11.2–11.5 s | 3.8–4.3 s（第一次做快取那次另加約 4 s） |
| 選角 cast 段（讀卡＋服裝檢查） | 8.5 s | 3.1 s |
| 遊戲讀對話目錄 | 讀兩次同一個 29.8 MB 檔（log 間隔 2.9 s，含 talk_load 0.4 s） | 1150–1283 ms |
| 第 3 幀 `TickCalendarAndMind` | 424–1012 ms | 31 ms |
| 第 3 幀 `TickInitiative` | 305–704 ms | 1.8 ms |
| 第 3 幀 `Bankruptcy` | 72–185 ms | 3.3 ms |

第 3 幀剩下的大頭是 `TG_EndPhysics` 等物理 314 ms（引擎），街區本身約 153 ms（TickMirrors 47 ms、RebuildUI 39 ms）。

### 第 3 幀的街區部分（2026-11-19）

- **TickMirrors 47 → 9.2 ms**（e8247e52a，c1118i）：開場時已在場的城市分塊原本在同一幀全部佈置（鏡子、燈光等，每塊幾 ms）。改成持久關卡先、每幀最多 4 ms；30 塊共 62.9 ms，分 10 幀，最長一塊 8.4 ms，鏡子 332 面不變。之後串流進來的分塊仍然到了就佈置。
- **RebuildUI 首次 97.9 ms**（c1118i，`ok.Street.LogUiRebuilds 1`）：shell 19.5、phone 29.9、dialogue 32.3、header 5.1、look 5.2；之後每次 2–4 ms。phone 與 dialogue 主要是第一次在遊戲執行緒讀檔解析：每位女角的 `history/<id>.jsonl`（`HistoryOf`）、`free-talk-log.json`（178 KB）與 `free-talk-memory.json`（251 KB）（`FreeTalkEnsureLog`）。9039742dc 改成讀檔後在執行緒池先讀好，第一次用時取結果；檔案大小或修改時間變了就照舊同步重讀，回滾歸檔與裁剪仍在遊戲執行緒。**已編過（stage c1118j），前後對照尚未量。**

注意：改了 `Tools/ok-mind` 後第一次開場，啟動器會重編 ok-mind（那次「rules / mind / story DLLs」段 40 s），之後是 0.2 s。

## 下一輪候選（未動）

1. **LoadMap 的 17 s World Partition 初始 cell 載入**：這段沒有任何 log，要先錄 trace（`-Trace loadtime,cpu`）看是哪些 cell、哪些資產。
2. **角色每 3 s 一個**：crowd runtime 的 Prepare／Commit／Install 在遊戲執行緒上逐個進行，單幀 100–220 ms。不是街區程式。
