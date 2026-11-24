# OK 卡與存檔的跨版本相容（方案，2026-11-24）

**範圍**：玩家手上的 OK 卡（互傳的卡、以前轉的卡）和街區／1 對 1 的存檔，在只更新程式之後還能不能用。兩件事共用同一條標準，所以寫在一份裡：**寧可擋下來講清楚，也不要靜默少件**——存檔版的「靜默少件」是關係、好感、懷孕狀態安靜歸零，比少一件衣服嚴重。

不含資源包的版本閘（已完成，[相容性閘](RESOURCE_PROGRAM_COMPAT_GATE_PLAN.md)）與資源包格式紀律（[資源包格式凍結](RESOURCE_PACK_FREEZE_PLAN.md)）。版本的語意一律沿用閘那套（**區間**：最舊與最新各一個常數，兩個方向都算不符），不要再發明第二套。

---

# 一、OK 卡

## 1.1 現況

一張 OK 卡身上有**三個各自獨立的版本面**，而且分散在三處：

| 面 | 常數 | 現在的行為 |
|---|---|---|
| `okLc`（資源包，`oklib.rs`） | `CARD_PACK_VERSION = 2` | 不等於就 `Err("card pack version 1 (expected 2)")` |
| `okLb`（模型清單＋digest） | payload 裡的 `"version":1`（`ok_card_with_answers`） | 沒有人比 |
| `okLt`（mods 樹答案，`tree_answers.rs`） | `VERSION` | 讀的時候**不等於就靜默當成「沒有答案」**（`tree_answers.rs:81`），寫的時候才報錯 |

三個問題：

1. **只有相等，沒有區間。** 加一個欄位就讓全世界的舊卡開不了，哪怕新程式完全讀得懂舊卡。
2. **沒有修復路徑的文案。** `card pack version 1 (expected 2)` 是給開發者看的；玩家不知道這張卡還救不救得回來（救得回來）。
3. **`okLt` 版本不符會被當成「這張卡沒有答案」**，最後報出來的訊息是 `made before 2026-10-28; ... --oklib seal`（`oklib.rs:1155`）——把「版本換了」講成「你這張卡太老」，指令也給錯了。

## 1.2 關鍵事實：OK 卡的升級不需要原作遊戲

`refresh_edited_ok_card`（`oklib.rs:1757`）已經在做這件事了：帶 `okLt` 的 OK 卡，**每套服裝都只從它自己的 pack 加共用資源嚴格開一次**，再把 `okLb` 的 digest 與模型清單寫回去。不碰遊戲、不碰 zipmod。`okId` 也已經有「重做時沿用」的規則（`oklib.rs:859`）。

所以升級器不用從零寫，要做的是**接線**：把版本不符接到這條路上，而不是接到錯誤訊息上。

唯一真的需要遊戲的，是 2026-10-28 以前那批**沒有 `okLt`** 的 OK 卡（走 `remake_from_card_data`，要讀 zipmod）。這批要單獨講。

## 1.3 要做的

1. **區間**：`CARD_PACK_MIN` / `CARD_PACK_MAX` / `CARD_PACK_VERSION`（新封的卡寫哪一號），語意同閘。落在區間內直接開，低於 MIN 才要升級，高於 MAX 是「這張卡是較新版本做的，請更新程式」。`okLb`、`okLt` 各自也給一組，三者的常數**集中在一處**（`resources.rs` 已經有 `card_pack_version` 這個欄位的位置，`resources.rs:404`），別再散在三個檔。
2. **升級指令**：`ok-extract --oklib upgrade-card <卡> [--out <卡>]`，內部就是 `refresh_edited_ok_card`。
   - 不給 `--out` 時，原卡先備份成 `<卡>.v<舊版>.bak` 再覆寫（覆寫前備份，不是之後）。
   - **`okId` 不變**（測試要釘這一條：升級前後 `card_identity` 相等）。這是和存檔的接縫——heroine 的身分就是 `okId`，變了名字和關係全對不上。
   - `okVo` 等不屬於 OK 資料的 chunk 原樣保留。
3. **讀卡器**：卡牆上掃到低於 MIN 的卡，標示「要升級」，按一下就升（長動作 → `OKBusy` 進度條，不自己做文字提示）。多張一起升要能排隊，中間失敗的那張**原卡不動**。
4. **`okLt` 的版本不符要和「太老」分開講**。`tree_answers.rs:81` 那個靜默 `None` 要改成帶理由回報：是「沒有這個 chunk」還是「版本是 N」。訊息分兩種，指令也分兩種（前者要遊戲重做，後者本機升級就好）。
5. **真的救不回來的那種**：升級時發現 pack 裡缺新版必需的記錄 → **明確列出缺什麼**，並說「這張卡要用原作卡重新轉一次」。這是唯一會要求玩家有遊戲的情況，文案要直說。
6. **只記不比**：卡裡加 `made_by`（封卡時的 commit）。方便追，但**不准拿來比**——理由同閘 §2.4，假警報比沒有閘更糟。

## 1.4 互傳的兩個方向

| 情形 | 要發生什麼 |
|---|---|
| 我的程式新、拿到舊卡 | 一鍵升級，`okId` 不變，照常開 |
| 我的程式舊、拿到新卡 | 「這張卡是較新版本做的，更新程式才能開」——**不要**試著開，也不要說卡壞了 |

---

# 二、存檔

## 2.1 現況

街區的存檔是一個資料夾的純 JSON（`OKStreetSocialSaves.inl`）：`relationships.json`、`phone.json`、`roster.json`、`free-talk-log.json`、`free-talk-memory.json`、`songs.json`、`heroine-settings.json`，加 `accounts/`、`history/`、`mind/`、`Photos/` 四個目錄。規則那頭由 `Tools/ok-rules` 的 serde 結構讀。

**裡面沒有任何版本欄位。** 而 `ok-rules` 有 128 處 `serde(default)`、只有 25 處 `deny_unknown_fields`。後果分兩種，而且很不對稱：

- 程式**加**欄位 → 舊存檔缺欄位走預設 → 多半是對的，可接受，這也正是那 128 處 default 的用意。
- 程式**改名、刪掉或改型**欄位 → 舊存檔那一段被**靜默丟掉**（多數結構沒有 `deny_unknown_fields`），下一次自動存檔（每 10 分鐘，而且離開時也存）就把歸零的狀態固定下來。玩家不會收到任何訊息。

這就是存檔版的 11-24：資料沒了，程式沒報錯。

## 2.2 要做的

1. **存檔自己帶戳記**：每個存檔資料夾一個 `save.json`：

   ```json
   { "format": "ok-save", "version": 1, "program": "<commit>", "written": "2026-11-24T11:49:57Z" }
   ```

   常數 `SAVE_MIN` / `SAVE_MAX` / `SAVE_VERSION` 放在 `ok-rules`（規則的擁有者就是格式的擁有者），語意同閘。
2. **載入時三種結果**：
   - 區間內 → 開。
   - 低於 MIN → **跑遷移**：`ok-rules` 裡一串純函式（`migrate_v1_to_v2` …），逐版往上，每一步一條測試加一份釘住的樣本存檔（自製內容，不含角色卡）。
   - 高於 MAX → 「這個存檔是較新版本的遊戲存的」，不開，不試。
3. **遷移在寫任何東西之前做完**。自動存檔每 10 分鐘覆寫，半遷移的狀態一旦被存下去就回不來了。遷移是長動作 → `OKBusy`。
4. **遷移前整個資料夾備份**成 `Saves/<slot>.before-v<N>/`。`OKStreetSaveKeeps` 已經把 `.before-` 排除在「遊戲檔案」之外，正好沿用這個命名，備份不會被當成遊戲的一部分跟著複製。
5. **讓靜默丟棄變成看得見**：關鍵的那幾個結構加 `deny_unknown_fields`——`relationships`、`roster`、`pregnancy`、`bank`、`bonds`。這樣改名會在測試和載入時炸出來，而不是安靜吃掉。**不是全部都加**：那 128 處 default 多半是刻意的向後相容，全加會讓加欄位也變成破壞性改動。
6. **沒有 `save.json` 的舊存檔**（現在所有存檔都是這種）算 version 0：跑一次遷移把戳記補上，不當成壞檔、不報錯。
7. **`roster.json` 的 `okId` 絕不重算**。遷移不准動它；卡被升級過（§1.3）也保證不變。這條在兩份都要寫，因為它是兩邊唯一的共用鍵。

## 2.3 1 對 1 與 OK Studio

同一套戳記與區間套到：`mind/` 的狀態、`.okscene`（OK Studio 場景）、以及 1 對 1 那邊自己的存檔。場景檔另有一條：**它會被玩家互傳**，所以要和 OK 卡一樣有「較新版本做的」這個方向的文案，不能只擋舊的。

---

# 三、要改哪裡

| 檔 | 改什麼 | 誰 |
|---|---|---|
| `Tools/ok-extract/src/oklib.rs`、`tree_answers.rs` | 三個版本面的區間常數集中；`okLt` 版本不符與缺 chunk 分開回報 | e-cardload |
| `Tools/ok-extract/src/oklib.rs`（CLI） | `--oklib upgrade-card`，備份、`okId` 不變的測試 | e-cardload |
| 讀卡器（`Source/OpenKoikatsu`） | 卡牆標示要升級的卡、一鍵升級、`OKBusy`、兩個方向的文案 | 讀卡器那組 |
| `Tools/ok-rules` | `SAVE_*` 常數、`save.json`、遷移函式與樣本、關鍵結構加 `deny_unknown_fields` | 街區／1 對 1 規則的擁有者 |
| `Source/OpenKoikatsu/OKStreetSocialSaves.inl` | 載入前遷移、備份、`OKBusy`、高於 MAX 的擋法 | 街區那組 |
| OK Studio | `.okscene` 的戳記與兩個方向的文案 | F 組 |

# 四、驗收

1. 拿一張 `CARD_PACK_VERSION` 比現在舊的 OK 卡（人工改 pack 版本號）：讀卡器標示要升級，升級成功，`okId` 前後相同，升級後能開，原卡備份存在。
2. 同一張卡，把版本改成比 MAX 新：講「較新版本做的」，不試著開，不說卡壞了。
3. 2026-10-28 以前沒有 `okLt` 的 OK 卡：訊息講的是「要用原作卡重轉」並給正確指令，**不是**「版本不符」。
4. `okLt` 版本不符的卡（人工改）：訊息和第 3 條不同，給的是本機升級指令。
5. 升級中途砍掉程式：原卡完好，備份完好，沒有半成品覆寫原卡。
6. 一份沒有 `save.json` 的現有存檔：補戳記後照常載入，關係、好感、`roster.json` 的 `okId` 全部對得上（和載入前逐欄比）。
7. 人工把 `relationships.json` 的一個欄位改名：載入要**報錯並擋下**，不是靜默歸零（這條就是 §2.2 第 5 點的證明）。
8. 把 `save.json` 的 version 改成比 MAX 新：不開，講清楚。
9. 遷移失敗（人工放一份壞 JSON）：原存檔不動，備份不動，遊戲不進去，畫面講清楚。

# 五、風險

- **遷移鏈會越長越難測**。對策：每一版一份釘住的樣本存檔（小、自製、不含角色卡），測試逐版跑；不准「跳版遷移」的捷徑。
- **`deny_unknown_fields` 加錯地方會讓加欄位變成破壞性改動**。只加在那五個關鍵結構上，加之前先確認該結構沒有在被別處當成寬鬆容器用。
- **卡升級要整庫活著**（`refresh_edited_ok_card` 會 `ensure_library`）。玩家只有包、沒有遊戲時這條成立；但庫自己要先過資源閘，兩者的先後順序要定：**先閘、後升級卡**，不然會拿壞庫去重封卡。
- **共用程式碼**：`Tools/ok-extract`、`Tools/ok-rules` 是三組共用，改完要 `cargo check --release` 與 `--no-default-features`，並實際連結 `OpenKoikatsu` Win64 Development 與 `OpenKoikatsuEditor`。
