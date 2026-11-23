# OK Mod 第四波（C 組，2026-11-23，同步點 C 之後）

接手當機前沒提交的改動，補完讀卡器與街區相對 KKAPI 的缺口（`OK_MOD_C_WAVE3.md` 第 6 節）。`ok-mod-api` 型別沒有改：全部新功能都是 `Event::Hook` 的新掛點名稱與 JSON 欄位，宿主的新 op 也是 JSON。

提交（一種改動一個）列在最後一節。

## 1. 當機前的改動：判斷與收尾

| 檔案 | 當機時的狀態 | 處理 |
|---|---|---|
| `Tools/ok-mod/host/src/card.rs` | 完整：飾品區段 `<mod>/acc/<outfit>/<slot>`（服裝卡裡是 `<mod>/acc/<slot>`）、`clothes_store`／`clothes_load` op、`reader.values`／`reader.control` 帶 `accessory`；有測試 | 驗過直接提交 |
| `Tools/ok-extract/src/appearance/accessory_ops.rs`（新）、`appearance.rs`、`appearance/properties.rs` | 完整：`accessory_transfer`（同一套服裝的 A 欄複製到 B 欄）、`accessory_copy`（別套服裝的幾欄複製到目前這套），連 sideloader 解析列一起搬；有測試 | 驗過直接提交（含 `#[ignore]` 的真卡測試，`C000.png` 本機跑過） |
| `Source/OpenKoikatsu/OKReaderMods.h` | 只有宣告，`OKReaderMods.cpp` 沒有實作，也沒有呼叫點 | 補實作與呼叫點（第 2 節） |
| `Source/OpenKoikatsu/OKReaderModPage.cpp` | 分隔線控制項 `separator` 已寫好 | 保留，另加每格控制項的欄位選單 |

計畫 §16.4 的表把 `acc_sections`／`store_acc`／`remove_all` 寫成在 `accessory_ops.rs`，實際在 `card.rs`；`accessory_ops.rs` 是 ok-extract 的複製／轉移動作。

## 2. 讀卡器

所有 payload 都帶 `card`（目前角色的卡片路徑）。

| 掛點／功能 | 何時送 | payload／回覆 |
|---|---|---|
| `reader.accessory_change` | 外觀頁套用飾品後（`ApplyAppearanceItem` 完成）；新增飾品欄也送 | `{outfit, slot, item, added}`；新增欄位時沒有 `slot`、`added: true` |
| `reader.accessory_transfer` | `ops` 裡的 `accessory_transfer` 套用成功後 | `{outfit, from, to}` |
| `reader.accessory_copy` | `ops` 裡的 `accessory_copy` 套用成功後 | `{from_outfit, to_outfit, slots}` |
| 飾品範圍的卡片資料 | 開卡 `reader.character_load` 的 `accessories: [{outfit, slot, version, data_b64}]`；存卡時回覆 `accessories` 整批取代該 mod 的飾品區段 | 宿主 `card.rs`；沒裝 mod 的卡片資料原樣保留 |
| 每格控制項 | 頁面宣告 `"accessory": true`：頁首自動加「飾品欄」選單與分隔線，切換欄位後重讀 `reader.values` | `reader.values`／`reader.control` 帶 `accessory: {outfit, slot}`；登錄鍵 `reader.mod_accessory_slot`（0–19），外觀頁選飾品欄時也跟著換 |
| `reader.coordinate_save` | 「匯出服裝卡」成功後（宿主 op `clothes_store`） | `{clothes, card, outfit}`；回覆 `{version, data_b64}` 與 `accessories: [{slot, …}]` 寫進服裝卡 |
| `reader.coordinate_load` | 「套用服裝卡」成功後（宿主 op `clothes_load`） | `{clothes, card, outfit, section, accessories}`，來自服裝卡 |
| 工作卡 | 外觀套用、屬性套用、穿服裝卡都會產生新的工作卡；`SetWorkingCardPath` 與穿服裝卡時告訴 mod 層「同一個角色」 | 不再送 `character_unload` + `character_load`，mod 手上還沒存的資料不會被卡片上的舊資料蓋掉 |
| `reader.clothes_state` | 穿脫按鈕（`OnClothesState`）改變狀態後 | `{outfit, kind, states: [9]}` |
| `reader.property_change` | 滑桿、詳細編輯、登錄寫入（含 mod 回覆的 `set`）；最後一次改動 0.25 秒後合成一次 | `{outfit, keys: [...], values: {鍵: 現值}}`；`mod.*`、`reader.mod_apply.*` 不送；mod 自己回覆造成的改動不回送（避免迴圈） |
| mod 讀登錄值 | 任何回覆帶 `"get": ["body.height", "shape.face.*", …]`（鍵或以 `*` 結尾的前綴，最多 256 個） | 只給那個 mod 送 `reader.get_result {values, outfit}`；它的回覆照一般回覆處理，但不能再 `get`（一輪）。`mod.*` 不給 |
| 分隔線 | 項目 `{"kind": "separator", "label"?}` | 有 `label` 時是兩段線中間夾文字 |

沒做的：
- `ApplyPreparedGeometry`（`OK_APPEARANCE_GEOMETRY=1` 才開的飾品幾何快速路徑）沒有送 `reader.accessory_change`。
- 讀卡器沒有「飾品複製／轉移」視窗，`accessory_copy`／`accessory_transfer` 目前只能經 `reader_call` 的屬性 ops 或 mod 回覆的 `ops` 發出。
- 服裝卡穿上後的工作卡是否保留原卡的 `okMx`（`okclothes::wear_into` 經 `seal`／`remake`）沒查證；mod 在記憶體裡的資料不受影響，存卡時會寫回。

## 3. 街區

| 掛點／功能 | 何時送 | payload |
|---|---|---|
| `street.period_change` | 每 0.5 秒看一次遊戲時間，時段變了就送：morning 5–11、day 11–17、evening 17–20、night 20–5 | `{period, previous}` |
| `street.load` 加 `new_game` | 讀存檔時存檔還沒有日曆（`CalendarMinute < 0`）＝新遊戲 | `new_game: true/false`；每個女角多 `section`：這個 mod 在她卡片 `okMx` 的區段（沒有是 null） |
| 寫回女角卡片 | 任何街區回覆 `{"cards": [{"heroine": id, "version", "data_b64"} 或 {"heroine", "remove": true}]}` | `FOkSession::SetCardModSection`；寫她自己的卡（`BaseCards`，診所改造卡是從它重做的），沒有才寫目前顯示的卡；每筆上限 1 MiB |
| `street.touch` | 觸碰結算成功後（`CompleteTouch`） | `{heroine, part: head/cheek/hand_l/hand_r/chest_l/chest_r, look, repeat}` |
| `street.action` | `Interact` 結束時：做了、只記錄（`record_only`）、被拒絕都送 | `{heroine, act, hers, record_only, done, refused, why?, reaction, place}` |
| `street.arrive` | 他走進一個地點（`PlaceHere` 變成非空的另一個地點）；第一次只記錄不送 | `{who: "him", place, place_name, from, heroine?}`（`heroine`：約會中或對話中的她） |
| `street.phone` `from: her` | 她打來：他接了（`answered: true`）、他掛掉（`declined: true`）、沒接到（20 秒逾時） | 和 `from: him` 相同形狀 |

都守「規則只記錄，說什麼由 AI 判斷」：掛點只告訴 mod 發生了什麼，沒有新的需求壓力。

**注意**：寫回她的卡會改變原卡的大小與時間，診所改造卡的鍵（`7af0e8906`）會因此重做。mod 應該只在少數時候寫（例如換日、一段關係的節點），不要每個事件都寫。

### 資料表擴充（調查結論，沒動手）

計畫 §1 表第 56 列與 §6.6 說「物品、地點、對話素材以資料檔（toml）加入，經宿主驗證」。目前沒有實作。現況：

- **商品、禮物、地點的商店資料**：UE 讀單一檔 `Content/IndependentResources/StreetSocialData/catalog.json`（`OKStreetSocialEconomy.inl` 的 `OKStreetLoadCatalog`，打包版從 `OK_FREE_TALK_PERSONAS` 旁邊找）。只能整檔換掉。
- **規則表**（`acts`、`places`、`events`、`activities`、`bonds`、`needs`、`motions`）：`Tools/ok-rules/src/tuning.rs` 用 `include_str!` 編進 DLL，執行期不能加。
- **話題、邀約**：選角 JSON 的 `topic_catalogue`、`invitation_catalogue` 路徑，各一檔。
- mod 目前能做的只有 `street.talk_facts`（加事實）與命名空間規則 `<mod>.<rule>`。

建議做法（下一波，要協調者決定）：
1. mod 資料夾 `Mods/<id>/street/*.toml`，宿主 `content` op 列出（和材質內容一樣經宿主驗證、id 加上 mod 命名空間）；
2. UE 在 `OKStreetLoadCatalog` 之後併入商品（物品 id 必須是 `<mod id>.<名稱>`，價格以元寫，`region.rs` 換算）；
3. 規則表的追加要 ok-rules 開一個「疊加表」請求（例如 `tuning_overlay`），在每次 eval 前帶入；這改到 ok-rules 的公開 JSON，屬共用程式碼；
4. 話題要先決定是給 AI 的素材（放進 `talk_facts` 的固定段落即可）還是規則選題（要改 `topic_catalogue` 成多檔）。

## 4. 驗證

- `Tools/ok-mod`：`cargo test -j 8` 全過（含 `accessory_sections_are_replaced_whole_and_named_by_owner`）。
- `Tools/ok-extract`：`cargo test --release --lib accessory_ops`（2 過；`--ignored` 的真卡測試 `transfer_and_copy_on_a_real_card` 用本機 `CrowdAPNG/C000.png` 過）；`cargo check --release` 與 `--no-default-features` 過。
- UE：D: 引擎建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development，結果見最後一節。

**沒驗到的**：沒開讀卡器或街區實測任何新掛點（沒有訂閱這些掛點的範例 mod）。`reader.get_result`、`reader.property_change` 的合併、街區 `cards` 寫回都只過編譯。

## 5. 給協調者

- `ok-mod-api` 沒改。新增的掛點名稱與欄位要併進 `Docs/OK_MOD_HOOKS.md`（F 的文件，我沒動）。
- F 也改了 `OKReaderMods.h`／`.cpp`（按鍵服務）：我加的都在新函式與 `Follow` 的結尾（`AnswerGet`），`RefreshValues` 與 `Set` 多帶 `accessory`。合併時兩邊都保留。
- 我另外動到的共用檔：`OKGalleryWidget.cpp`（`SetWorkingCardPath`、`OnClothesState` 各一行）、`OKGalleryAppearance.cpp`、`OKGalleryClothing.cpp`、`OKGalleryProperties.cpp`、`OKGalleryPregnancyControls.cpp`、`OKCharacterMCPRegistry.cpp`、`OKStreetSocialScene.{h,cpp}`、`OKStreetSocialHeroine.inl`、`OKStreetSocialPhoneInbox.inl`、`OKStreetSocialMods.inl`。
- SDK 若要給 mod 作者方便的寫法（`hooks::get`、街區 `cards` 回覆的輔助函式），屬 F 的 SDK，建議下一波加。

## 6. 提交

| 提交 | 內容 |
|---|---|
| `d1aae0d61` | ok-mod 宿主：飾品範圍區段、`clothes_store`／`clothes_load`、`accessory` 參數 |
| `05824dcef` | ok-extract：`accessory_transfer`／`accessory_copy` |
| `fd01247eb` | 讀卡器：第 2 節全部 |
| `864563cd5` | 街區：第 3 節全部 |

建置：D: 引擎 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 都是 `Result: Succeeded`（第一次編輯器建置抓到 `OKStreetSocialMods.inl` 裡 `if(...)UE_LOG(...);else` 沒加大括號的 C2181，加上後重建通過）。
