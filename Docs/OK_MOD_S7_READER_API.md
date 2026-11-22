# OK Mod 工作項 7：讀卡 API＋範例（C 組，2026-11-23）

計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §6.2–§6.4、§10 M1～M3、§14.1、§15.4 第 7 列。給 mod 作者的說明在 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md)。

## `ok-mod-api` 加了一個變體（協調者已採納）

`Event` 追加 `Hook { name: RString, payload: RString }`（non-exhaustive 列舉追加，ABI 0.1.0 相容；舊 mod 收不到也不受影響），另加 `Event::subscription()`（Hook 回它的 `name`，其他回 `name()`）讓宿主依掛點名分送。

理由：卡片、讀卡器、轉卡、之後街區與 1 對 1 的掛點都是「名稱＋JSON」，一個變體就能全部承載，加新掛點不必再改 ABI 型別；SDK 用 `hooks` 模組提供型別化的 payload（`CharacterLoad`、`ExtSection`、`Kkex`、`ReaderSet`）。
協調者 2026-11-23 採納（ABI_VERSION 不動），並規定 hook 名帶模式前綴（`reader.*`、`extract.*`、`street.*`…）。api、SDK `hooks`、宿主 `hook` 請求與測試先單獨提交為 **be18a313c**（只動 `Tools/ok-mod/`，給 E、F cherry-pick）；卡片與讀卡器的部分在之後的提交。

`ext.upgrade` 沒有另發 hook：資料升級在 SDK 的 `ExtSection::data(version, upgrade)`，mod 讀資料時就地做。另外多兩個掛點：`reader.values`（讀卡器要控制項目前值）、`extract.kkex_keys`（mod 宣告要讀的 KKEx 區段）。

## 做了什麼

### 1. 共用卡片程式碼 `Tools/ok-card-mods`（新 crate）

`okMx`／`okMr` 的編解碼、角色身分（排除 `okVo`／`okMx`／`okMr`）、寫 chunk 時保留身分、`carry_over`，從 ok-extract 抽出來，ok-extract 與 mod 宿主共用同一份（宿主不帶 zstd：`default-features = false`，`okMr` 還不由宿主寫）。ok-extract 的 `oklib::card_identity`／`with_card_identity` 改呼叫它，結果不變（368 張卡身分重算一致）。

### 2. ok-extract

- `okmods::set_enabled` 由宿主呼叫：新 C ABI `ok_set_enabled_mods("id@version\n…")`（null 清掉、改回問宿主）。`OKModModes.cpp` 每次進出模式後把啟用清單送給本模組與 KKUnityBundle 的 ok_extract 副本（`FOkSession::SetEnabledMods`；editor 的模組化建置每個模組各有一份 static），dispatcher 也經 `FOkSession::SetModDispatch` 補設。開卡快取鍵因此不必每次開卡都問宿主。
- `on_kkex`：`make_ok_card_for_outfit` 轉卡時先問 `extract.kkex_keys`（mod 宣告要讀的 KKEx 區段鍵），把原作卡的這些區段以 msgpack 交給 `extract.kkex`，回來的區段寫進新 OK 卡的 `okMx`。沒有宿主（CLI、測試）時不做事。
- 開原作卡時也一樣：新 C ABI `ok_kkex_mod_sections(card, out, cap)` 回傳 mod 從該卡 KKEx 做出的區段（JSON），讀卡器把它經 `card_load` 的 `imported` 交給 mod（payload `imported: true`），所以開卡就看得到 `KK_Profile` 的簡介，存檔時照寫（見 ERROR_LOG 同日條目：沒有這一步時存檔會把轉卡寫入的區段刪掉）。

### 3. 宿主（`Tools/ok-mod/host`，新增 `okm_dispatch` 請求種類）

`src/card.rs`：`hook`、`card_mods`、`card_load`、`card_store`、`extract.kkex`、`reader.ui`、`reader.values`、`reader.control`。宿主自己讀寫卡片的 `okMx`，mod 不碰檔案，其他 mod 的區段原樣保留；`card_load` 回報卡上用到但沒啟用的 mod（`missing`）；`reader.ui` 把鍵與動作加上 `mod.<id>.` 前綴，`reader.control` 依最長的已啟用 mod id 拆鍵。

### 4. SDK（`Tools/ok-mod/sdk/src/hooks.rs`）

`parse`／`json`、`ExtSection::data(version, upgrade)`（**on_upgrade**：卡上資料比 mod 舊時先升級，比 mod 新時回錯）、`CharacterLoad`（含 `apply`、`imported`）、`section`／`save`／`remove`、`Kkex::section`、`ReaderSet`。

### 5. 讀卡器（`Source/OpenKoikatsu/OKReaderMods.{h,cpp}` 與呼叫點）

- 開好一張卡（`FinishPreparedPreview`）→ `card_load`（先送離開那張的 `reader.character_unload`）；同一張卡換服裝 → `reader.outfit_change`。
- **缺 mod 提示**：卡上有未安裝 mod 的資料時畫面提示「這張卡用到未安裝的 mod：…」（文字表 `reader.mods.missing`，三語）；資料原樣留在卡上。
- 另存（OK 卡背景重轉完成後、獨立卡複製完服裝資源後、「存成 KKS 卡」、MCP `save`）→ `card_store`。
- 說話（`OnSpeak`）→ `reader.speech_start`。
- **Mods 分類**（設定那一欄）：第一頁「載入卡片時套用 mod 資料」各 mod 一個開關（`reader.mod_apply.<id>`，存 `Saved/CardReader/mod_apply.json`），之後是各 mod 的 `reader.ui` 頁。控制項沿用工作項 4 的 `OKReaderPageItems`（bool、choice、text、button）；按鈕動作 `mod.<id>.<cmd>` 走宿主 `command`。
- 每個 mod 控制項都是登錄（`OKCharacterMCPRegistry`）的一列（`category: "mods"`），`reader_call get/set` 讀得到也改得到。
- 回覆裡讀卡器會做的事：`set`（照登錄寫入）、`notice`、`subtitle`、`outfit_names`（服裝下拉顯示「服裝 1：制服」）。

### 6. 範例（`Tools/ok-mod/examples`）

| 範例 | 內容 |
|---|---|
| `profile` | 角色簡介；轉卡時從原作卡 `KK_Profile` 的 `ProfileText` 匯入；讀卡 text；存卡；套用開關關閉時存檔不覆寫卡上資料 |
| `outfit-names` | 每套服裝的名稱（服裝範圍資料）；資料版本 1（清單）→ 2（以編號為鍵）的 `upgrade` |
| `random-chara` | bool／choice／button；按鈕回 `set` 隨機調整 44 個身形、52 個臉型滑桿 |
| `subtitles` | `reader.speech_start` 回字幕（讀卡部分；街區、1 對 1 在工作項 10、13） |

## 驗了什麼

- **cargo**：`Tools/ok-mod` 整個 workspace `cargo test` 全過，含新的 `host/tests/card_mods.rs`（實際載入四個範例 DLL：轉卡 `extract.kkex`、`imported` 開卡、開卡／編輯／存卡／再開、套用開關關閉時存檔不動卡上區段、停用 mod 後 `missing` 與資料保留、按鈕指令、`reader.speech_start` 字幕）與 `load.rs` 的 `hooks_reach_their_subscribers`。ok-extract `cargo check` 與 `--no-default-features` 都通過，`okmods` 測試通過。`be18a313c` 另在只含該提交的獨立 checkout 跑過 `cargo test`。
- **建置**：`may-build` 後用 D: 引擎建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development，最後一次改動後兩個都 `Result: Succeeded`。
- **讀卡器實測**（`c-mod-7` 占名額，四個範例裝在 checkout 的 `Mods/`，用完已關閉並釋放）：

| 項目 | 結果 |
|---|---|
| 載入 | 宿主載入 4 個 mod，log 沒有警告 |
| 登錄 | `reader_call parameters` 有 5 個 `mod.*` 列與 2 個 `reader.mod_apply.*` 列（`category: mods`） |
| Mods 分類 | 設定欄多「Mods」，四頁：載入卡片時套用 mod 資料、服裝名稱、角色簡介、隨機角色（截圖 `C:\portable\OpenKoikatsu\Saved\OKControl\shots\69676-0001.png`） |
| `reader_call set` | `outfit-names.name = 制服` 後服裝下拉顯示「服裝 1：制服」；`spread = wide` 讀回正確 |
| 按鈕 | 「隨機」：提示「隨機調整了 96 個滑桿」，`shape.body.0` 0.65→0.31、`shape.face.0` 0.12→0.39 |
| 原作卡 `KK_Profile` | `Alice_keiyuu.png`（原作卡，複製到 `Saved/ModTest7/cards`）：開卡即顯示作者寫的簡介；「另存新卡」轉成 OK 卡，`card_mods` 列出 profile 區段（version 1、requires profile 0.1.0） |
| 編輯後存卡再開 | 改簡介與服裝名稱後 MCP `save`（`Saved/CharacterMCP/cards/ModTest7_….png`），log「2 mod section(s) saved」，重開兩個值都在 |
| 套用開關 | `reader.mod_apply.org.openkoikatsu.profile = false`（寫進 `Saved/CardReader/mod_apply.json`）後重開：簡介空白、服裝名稱照常；測完已刪掉該檔 |
| 缺 mod | 停用 outfit-names 後開卡：畫面黃字「這張卡用到未安裝的 mod：org.openkoikatsu.outfit-names 0.1.0。它們的資料會原樣留在卡裡。」（截圖 `C:\portable\OpenKoikatsu\Saved\OKControl\shots\84704-0001.png`） |


## 沒驗什麼、已知限制

- **說話字幕沒在遊戲內實測**：這台機器沒有一般對話語音索引（`comm_lines.json`），讀卡器的「說話」不能播放，`OnSpeak` → `reader.speech_start` → 字幕只由宿主測試涵蓋。
- **開卡基準 3% 還沒補量**：建置完時機器閒著，但實測結束時 F 組的 Unreal 正在跑（slot1 `f-mod-9`），不符合「沒有 Unreal 在跑」的條件；S2 回報仍待補。
- `存成 KKS 卡` 的 `card_store` 接上了但沒有實際按過。
- `reader.character_unload` 只在宿主層與程式路徑上確認，範例沒有訂閱它。

- mod 頁面還沒有數字滑桿與顏色控制項（`number` 目前只鏡像既有控制項）。
- `subtitles` 的字幕是讀卡器的畫面提示（`ScreenNote`），不是獨立的字幕列；街區與 1 對 1 的呈現在工作項 10、13 決定。
- `pair` 模式由街區程式自己 `EnterMode` 時不會重送 ok-extract 的啟用清單（`OKModModes.cpp` 只在世界的模式切換時送）；街區開卡在工作項 10 一起處理。
- `random-chara` 沒做髮色（計畫寫了「髮色」）：髮色是卡片屬性，要經「套用」流程，留到之後。
