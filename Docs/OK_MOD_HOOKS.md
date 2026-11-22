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
| `reader.ui` | 讀卡器建頁面時（一次） | `{}` | `{"pages": [{"name", "items": [...]}]}`（§4） |
| `reader.values` | 開卡、改值之後 | `{}` | `{"<鍵>": 值, ...}`（不含前綴） |
| `reader.control` | 某個控制項改了（頁面或 `reader_call set`） | `{"key", "value"}`（不含前綴） | 可帶讀卡器動作；回錯誤表示拒絕 |
| `reader.speech_start` | 一句語音開始播放 | `{"mode": "reader", "text", "card"}` | `{"subtitle": {"text", "seconds"}}` 等（§5） |

`apply` 是「載入卡片時套用此 mod 資料」開關（MakerLoadToggle 對應），關掉時 `section` 照給、`apply=false`，`CharacterLoad::data` 回 `None`。

## 4. 讀卡器控制項

`reader.ui` 的 items 用 pages.json 的格式：`bool`（`toggle`）、`choice`（`dropdown`，`options: [{value, label}]`）、`text`、`button`（`action` 是 mod 的指令名）。宿主把 `key` 改成 `mod.<id>.<key>`、`action` 改成 `mod.<id>.<action>`。

- 讀卡器畫面多一個「Mods」分類（設定那一欄）：第一頁是各 mod 的「載入卡片時套用」開關（鍵 `reader.mod_apply.<id>`，存在 `Saved/CardReader/mod_apply.json`），接著是每個 mod 的頁。
- 每個控制項也是登錄（`OKCharacterMCPRegistry`）的一列，`category: "mods"`。所以 `reader_call get/set`、`ui_set` 都能讀寫，和內建參數一樣。
- 按鈕：`mod.<id>.<名>` 走宿主的 `command`，`Reply::Text` 顯示成提示，`Reply::Json` 照 §5 處理。
- 數字滑桿與顏色還沒有給 mod 用（數字列目前沿用既有控制項的鏡像，mod 沒有對應的 UMG 控制項）；要用時在讀卡器補 `OKReaderPageItems` 的數字種類。

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
