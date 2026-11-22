# OK mod 掛點（Hook）：卡片、讀卡器、轉卡

2026-11-23，工作項 7（[OK mod 框架計畫](F:/OpenKoikatsu/Docs/OK_MOD_FRAMEWORK_PLAN.md) §6.2–§6.4、§14.1）。
這份說明 mod 作者怎麼拿到卡片資料、怎麼在讀卡器放控制項，以及遊戲那一側怎麼接。街區（工作項 10）與 1 對 1（工作項 13）會沿用同一套 `Event::Hook`。

## 1. 一個事件承載所有掛點

`ok-mod-api` 只追加了一個 non-exhaustive 變體（相容於 ABI 0.1.0）：

```rust
Event::Hook { name: RString, payload: RString }   // payload 是 JSON
```

- mod 在 `register` 裡 `reg.subscribe("<掛點名>")`，宿主只把該掛點送給有訂閱的 mod（`Event::subscription()` 回的就是 `name`）。
- 回覆用 `Reply::Json`（`hooks::json(&value)`），沒有要回的就 `Reply::None`。
- SDK 的 `ok_mod_sdk::hooks` 提供 payload 型別與回覆小工具：`parse`、`json`、`ExtSection::data`（含版本升級）、`CharacterLoad`、`section`／`save`／`remove`、`Kkex::section`、`ReaderSet`。

這樣新掛點不必再改 ABI 型別，只要文件記下名稱與 JSON 形狀（協調者 2026-11-23 採納，提交 be18a313c）。

- **命名**：一律帶模式前綴、小寫底線：讀卡器 `reader.*`、轉卡 `extract.*`、街區 `street.*`、OK Studio `studio.*`、1 對 1 `pair.*`。
- payload 是 JSON；`okMx` 的位元組以 base64 放在 JSON 裡。
- 每幀掛點（工作項 11）不走 Hook，另外設計。
- 宿主請求 `{"op":"hook","hook","payload","mods"?}` 可直接送任一掛點（`ok_mod_host.h`）。

## 2. 卡片資料：`okMx`

卡片上每個 mod 一段：`{mod_id: {version, requires, data}}`（msgpack，`okMx` chunk）。mod 不碰檔案：宿主讀寫卡片（`Tools/ok-card-mods`，與 ok-extract 同一份程式），別的 mod 的區段一位元組都不動。

- `data` 是 mod 自己的位元組，SDK 寫 JSON；在 JSON 裡以 base64（`data_b64`）傳遞。
- `version` 是 mod 自己的資料版本；`requires` 由宿主填寫該 mod 的 id 與目前安裝的版本。
- **角色／服裝／部件範圍**：區段是整張卡一段，範圍由 mod 自己在資料裡分（`outfit-names` 以服裝編號為鍵）。`reader.character_load` 給 `outfit`，`reader.outfit_change` 告知換裝。
- **身分不變**：寫 `okMx` 不改變角色身分（身分排除 `okVo`／`okMx`／`okMr`；沒有 `okId` 的卡第一次寫入時補上原本的身分）。

### on_upgrade

`ExtSection::data(version, upgrade)`：卡上的資料版本比 mod 舊時先呼叫 `upgrade(舊版本, 值)` 轉成新格式（ExtendedSave 的 `CardBeingImported` 對應）；比 mod 新時回錯誤，mod 應保留預設值、存檔時不覆寫（見 `profile` 的 `keep_card`）。

## 3. 掛點一覽

| 掛點 | 何時 | payload | 回覆 |
|---|---|---|---|
| `extract.kkex_keys` | 轉原作卡之前（ok-extract） | `{}` | `{"keys": ["KK_Profile", ...]}`：要讀的 KKEx 區段鍵（精確比對） |
| `extract.kkex` | 轉原作卡（ok-extract `make_ok_card_for_outfit`） | `{"sections": {"<鍵>": "<msgpack b64>"}}` | `{"version", "data_b64"}`：寫進新 OK 卡的 `okMx`；`null` 不寫 |
| `reader.character_load` | 讀卡器開好一張卡 | `{"card", "outfit", "identity", "apply", "section": {version, requires, data_b64} \| null}` | 可帶讀卡器動作（§5） |
| `reader.outfit_change` | 同一張卡換服裝 | `{"card", "outfit"}` | 可帶讀卡器動作 |
| `reader.character_unload` | 讀卡器換到另一張卡之前 | `{"card"}`（離開的那張） | 可帶讀卡器動作 |
| `reader.character_save` | 讀卡器另存卡片之後 | `{"card", "outfit"}` | `null` 不變；`{"remove": true}` 移除；`{"version", "data_b64"}` 寫入 |
| `reader.ui` | 讀卡器建頁面時（一次） | `{}` | `{"pages": [{"name", "layout"?, "items": [...]}]}`（§4） |
| `reader.values` | 開卡、改值之後 | `{}` | `{"<鍵>": 值, ...}`（不含前綴） |
| `reader.control` | 某個控制項改了（頁面或 `reader_call set`） | `{"key", "value"}`（不含前綴） | 可帶讀卡器動作；回錯誤表示拒絕 |
| `reader.speech_start` | 一句語音開始播放 | `{"mode": "reader", "text", "card"}` | `{"subtitle": {"text", "seconds"}}` 等（§5） |

`apply` 是「載入卡片時套用此 mod 資料」開關（MakerLoadToggle 對應），關掉時 `section` 照給、`apply=false`，`CharacterLoad::data` 回 `None`。

## 4. 讀卡器控制項（DreamGUI 宣告式，工作項 7b）

`reader.ui` 回 `{"pages": [頁, ...]}`。讀卡器用 DreamGUI 原生控制項直接建出每一頁（`Source/OpenKoikatsu/OKReaderModPage.cpp`，控制項的外觀在 `DUI/Reader/Controls/*.dui`），不經 UMG。值從 `reader.values` 讀、改值走 `reader.control`，和 `reader_call get/set` 是同一條路。宿主把每一層的 `key` 改成 `mod.<id>.<key>`、`action` 改成 `mod.<id>.<action>`、`image` 改成 mod 資料夾裡那個檔案的完整路徑（資料夾外的路徑、`..`、不存在的檔案會被拿掉，讀卡器在頁首標紅說哪一項）。

**頁**：`{"name", "layout"?, "items": [...]}`。`layout` 是 `column`（預設，由上往下）、`row`（橫排）、`tabs`（每個子項目一個分頁）、`scroll`（固定高度的捲動區，`height`）。

**容器**（可以再放容器）：

| `kind` | 欄位 | 說明 |
|---|---|---|
| `group` | `label`?、`layout`?、`fold`?、`folded`?、`items` | 一組控制項；有 `label` 時上面一行標題，`fold: true` 時標題可以按下摺疊（`folded: true` 一開始收起） |
| `row` | `items` | 橫排（每項有 `label` 時是「標題＋控制項」一格） |
| `tabs` | `items`、`height`? | 分頁；每個子項目一頁，子項目是 `group` 時它的 `label` 是分頁名、`items` 是內容 |
| `scroll` | `items`、`height`（預設 240） | 固定高度、可捲動 |

**控制項**（有值的都要 `key`；`label` 是左邊的標題，可用 `label_id` 指讀卡器文字表）：

| `kind` | 欄位 | 值 | 原生控制項 |
|---|---|---|---|
| `bool`（`toggle`） | | `true`／`false` | Toggle |
| `choice`（`dropdown`） | `options: [{value, label}]` 或字串陣列 | 選中的 `value`（字串） | Dropdown |
| `radio` | `options`、`layout: "column"`? | 選中的 `value` | RadioButton（一組只會有一個開著） |
| `text` | `placeholder`?、`multiline`?、`height`?、`max_length`? | 字串 | TextInput |
| `number` | `min`、`max`（預設 0～100）、`step`? | 數字（`step` 是整數時取整） | SpinBox |
| `slider` | `min`、`max`（預設 0～1）、`step`? | 數字；旁邊顯示目前值 | Slider |
| `color` | | `"#RRGGBB"`（或 `#RRGGBBAA`，送出時轉大寫） | 色塊＋TextInput |
| `list` | `options`?、`height`?（預設 180） | 有 `options`：選中的 `value`；沒有：字串陣列，只顯示 | ListView |
| `progress` | `min`、`max`（預設 0～1）；或不給 `key`、給 `value` | 數字，只顯示 | ProgressBar |
| `label` | `text`?、`key`?、`style`? | 有 `key` 時顯示值（接在 `text` 後面） | 文字 |
| `image` | `image`（mod 資料夾內的 PNG）、`width`?、`height`? | | 圖片（讀卡器開著期間留著，不會被回收） |
| `button` | `action` | 按下執行 `mod.<id>.<action>` 指令 | Button |

`style` 用主題（`DUI/Theme.dui` 指的 DreamGUI Default preset）的文字樣式名稱：`Heading`、`Title`、`Lead`、`Body`、`Caption`、`Overline`、`Figure`、`AccentText`、`GoodText`、`BadText`、`WarnText`；讀卡器照 preset 的顏色與字級畫（執行時不能套 `.dui` 的 style，所以表格寫在 `OKReaderModPage.cpp`）。目前只有 `label` 吃 `style`；按鈕、容器的外觀樣式還沒開放。

例（`examples/profile`）：

```json
{"pages": [{"name": "角色簡介", "layout": "tabs", "items": [
  {"kind": "group", "label": "簡介", "items": [
    {"kind": "text", "key": "text", "label": "簡介", "multiline": true, "height": 160},
    {"kind": "label", "key": "length", "style": "Caption"}]},
  {"kind": "group", "label": "說明", "items": [{"kind": "label", "text": "簡介存在卡片裡……", "style": "Body"}]}
]}]}
```

- 讀卡器畫面多一個「Mods」分類（設定那一欄）：第一頁是各 mod 的「載入卡片時套用」開關（鍵 `reader.mod_apply.<id>`，存在 `Saved/CardReader/mod_apply.json`），接著是每個 mod 的頁。
- 有值的控制項（`bool`、`choice`、`radio`、`text`、`number`、`slider`、`color`、有 `options` 的 `list`）也是登錄（`OKCharacterMCPRegistry`）的一列，`category: "mods"`，`kind` 是 `bool`、`choice`、`text`、`number`（`color` 是 `text`，另帶 `format: "#RRGGBB"`，和內建 0～1 的顏色分量分開）。`reader_call get/set` 讀寫它們，和內建參數一樣；巢狀在分頁、群組裡的也算。只顯示的（`label`、`progress`、沒有 `options` 的 `list`、`image`、`button`）不是登錄列。
- 畫面上的控制項也登記在讀卡器畫面的控制項清單（`ok.ReaderScreen controls`／`press`／`set`），路徑是「Mods›頁名›…›標題」。`ui_widgets`／`ui_set` 列舉 DreamGUI 畫面的部分在 F 的 9a63c5401，同步點 B 之後才有。
- 按鈕：`mod.<id>.<名>` 走宿主的 `command`，`Reply::Text` 顯示成提示，`Reply::Json` 照 §5 處理。
- 值的顯示：每一幀從讀卡器保存的 `reader.values` 結果拿（開卡、換服裝、每次 `reader.control` 之後重新問一次），所以 mod 改了別的鍵的值（例如 `length`）也會跟著變。輸入框、數字框只在 mod 那邊的值變了時才覆蓋畫面上的內容，正在打的字不會被蓋掉。
- 舊格式（只有 `items`、`bool`／`choice`／`text`／`button`）照樣能用。

## 5. 回覆裡讀卡器會做的事

`reader.character_load`、`reader.outfit_change`、`reader.control`、按鈕指令、`reader.speech_start` 的 JSON 回覆可以帶：

| 欄位 | 讀卡器做什麼 |
|---|---|
| `"set": [{"key", "value"}, ...]` | 照登錄寫入（等同 `reader_call set`），例如 `random-chara` 改 `shape.body.*` |
| `"notice": "文字"` | 畫面提示 6 秒 |
| `"subtitle": {"text", "seconds"}` | 畫面字幕 |
| `"outfit_names": {"0": "制服"}` | 服裝下拉顯示「服裝 1：制服」；空字串移除 |

mod 不直接動模型或 UI 物件，一律經這些要求。

## 6. 遊戲端

- `Source/OpenKoikatsu/OKReaderMods.{h,cpp}`：讀卡器的呼叫點全在這裡；mod 關掉（`-NoMods`、沒有宿主、不是讀卡器模式）時每個呼叫都不做事。
  - `FinishPreparedPreview` 成功 → `Loaded`（`card_load` 或 `reader.outfit_change`），缺 mod 時提示「這張卡用到未安裝的 mod：…」（文字表 `reader.mods.missing`）。
  - 另存：OK 卡在背景重轉完成後、獨立卡複製完服裝資源後 → `Saved`（`card_store`）。
  - `OnSpeak` 成功 → `Speech`（`reader.speech_start`）。
- 宿主請求（`Tools/ok-mod/host/src/card.rs`）：`hook`、`card_mods`、`card_load`、`card_store`、`extract.kkex`、`reader.ui`、`reader.values`、`reader.control`。
- ok-extract：`okmods::set_enabled` 由遊戲呼叫新的 C ABI `ok_set_enabled_mods("id@version\n...")`（`OKModModes.cpp`，每次進出模式後；KKUnityBundle 的那份經 `FOkSession::SetEnabledMods`，dispatcher 也經 `FOkSession::SetModDispatch` 補設）。開卡快取鍵因此不必每次開卡都問宿主。

## 7. 範例

| 範例 | 用到 |
|---|---|
| `examples/profile` | `extract.kkex_keys`／`extract.kkex`（`KK_Profile` 的 `ProfileText`）、`okMx`、讀卡 text、`reader_call` 讀寫 `mod.org.openkoikatsu.profile.text` |
| `examples/outfit-names` | 服裝範圍資料、`reader.outfit_change`、資料版本 1→2 的 `upgrade`、`outfit_names` 回覆 |
| `examples/random-chara` | bool／choice／button、指令回覆 `set` 改身形與臉型 |
| `examples/subtitles` | `reader.speech_start`、`subtitle` 回覆、設定項；`targets` 含 pair、street（那兩邊的掛點在工作項 10、13） |

`Tools/ok-mod/host/tests/card_mods.rs` 載入這四個 DLL，走一遍轉卡、開卡、編輯、存卡、再開、關掉套用開關、停用 mod（缺 mod）、按鈕與語音。

## 8. 街區（工作項 10）

街區的掛點都是 `street.*`，`targets` 要含 `street`。遊戲端在 `Source/OpenKoikatsu/OKStreetSocialMods.inl`，mod 關掉（`-NoMods`、沒有宿主、自我測試）時都不做事。設計守則照計畫 §6.6：**規則只記錄，說什麼由 AI 判斷**；mod 不讀玩家說的話；不加需求壓力。

每個 payload 都帶 `day`（遊戲第幾天）、`date`（`YYYY-MM-DD`）、`minute`（當天第幾分鐘）、`lang`（`zh-TW`／`zh-CN`／`en`）。女角是 `{"id", "name", "birthday": "MM-DD"?}`，`id` 是她的穩定身分（`apng-…`）。

| 掛點 | 何時 | 另外的 payload | 回覆 |
|---|---|---|---|
| `street.load` | 場景讀好存檔後、其他街區掛點之前（新遊戲、讀檔都會重開場景），每個 mod 各送一次 | `state`（自己的 `ext.mods.<id>`，沒有就是 null）、`heroines` | — |
| `street.day_change` | 換日（`NextDay`，存檔之前） | `heroines` | 可帶下表欄位 |
| `street.talk_begin`／`street.talk_end` | 對話開始／他結束對話 | `heroine` | 同上 |
| `street.invite` | 邀約被答應或拒絕（`InviteAllowed`） | `heroine`、`action`、`accepted` | 同上 |
| `street.phone` | 他打電話給她 | `heroine`、`kind: "call"`、`from: "him"`、`answered` | 同上 |
| `street.gift` | 送禮結束（`FinishGift`） | `heroine`、`item`、`accepted`、`birthday` | 同上 |
| `street.speech_start` | 她的回話開始唸（`SpeakFreeTalk`） | `heroine`、`text`（多行以換行接） | 同上 |
| `street.talk_facts` | 組她這一回合的提示（【今天】那行） | `heroine` | `{"facts": ["…", …]}`（最多 8 條、每條 200 字） |
| `street.rule` | 有人叫規則 `"<mod id>.<rule>"`（`OKRulesEval`、控制通道 `/rules eval`） | `rule`（不含前綴）、`request`（整個規則請求） | 規則的答案（JSON 物件） |

回覆裡街區會做的事：

| 欄位 | 街區做什麼 |
|---|---|
| `"state": {…}` | 寫進存檔 `ext.mods.<id>`（null 移除）；跟著下一次存檔寫出，讀檔後由 `street.load` 還給 mod |
| `"notice": "文字"` | 街區的提示行（`S.Message`） |
| `"subtitle": {"text", "seconds"}` | 同一條提示行（她的對話框本來就有字，字幕 mod 主要是給對話框看不到的時候） |
| `"facts": [...]` | 只在 `street.talk_facts`：接在她的【今天】那行後面。那一段本來就每回合變，不會破壞 DeepSeek 的前綴快取 |

- **命名空間規則**：規則名含 `.` 而且前綴是訂閱了 `street.rule` 的已啟用 mod 時，交給那個 mod，不經 ok-rules；其他照舊。
- **開卡快取**：只有訂閱「開卡時會跑的 `extract.*` 掛點」（`extract.kkex`、`extract.kkex_keys` 只影響轉卡，不算）的 mod 會算進開卡快取鍵（`okmods::changes_opens`），街區、讀卡器的 mod 不會讓已快取的開卡失效。
- **模式切換**：`OKModModes.cpp` 每 0.5 秒看一次宿主目前的模式，變了就重送 ok-extract 的啟用清單，所以街區程式自己 `EnterMode("pair")` 也會跟上。

範例：

| 範例 | 用到 |
|---|---|
| `examples/birthday` | `street.load`／`day_change`／`talk_begin`／`gift`／`talk_facts`、`ext.mods` 存讀檔、命名空間規則 `org.openkoikatsu.birthday.upcoming`。核心已經會在她生日那天告訴她「今天是你的生日」、送禮加成；這個 mod 補核心沒有的「每年生日他有沒有來、她有沒有收下禮物」，存在存檔裡，之後的回合當事實交給她，生日早上給玩家一則提示。沒來的那年什麼都不說，也不倒數。 |
| `examples/subtitles` | `street.speech_start`（和讀卡器、1 對 1 同一個 mod） |

`Tools/ok-mod/host/tests/street_mods.rs` 用真的 DLL 走一遍：讀檔、換日提示、對話與送禮記錄、事實、規則、字幕、存檔後重開宿主再讀回。
