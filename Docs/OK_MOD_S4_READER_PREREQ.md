# OK Mod 工作項 4：讀卡器前置（C 組，2026-11-23）

計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §6.4、§13 第 5 項、§15.4 第 4 列；盤點 `Docs/OK_MOD_HOOK_INVENTORY.md` §3.2、§5.8。

## 做了什麼

### 1. `pages.json` 新控制項種類（新檔 `Source/OpenKoikatsu/OKReaderPageItems.{h,cpp}`）

`items` 清單裡除了 `number`，現在可以寫：

| `kind` | 別名 | 畫面 | 綁什麼 |
|---|---|---|---|
| `bool` | `toggle` | 開關 | 登錄鍵（`OKCharacterMCPRegistry::Parameters` 的 `key`） |
| `choice` | `dropdown` | 下拉；選項取自登錄列的 `options`（`{value, label}`）或 `choices` | 登錄鍵 |
| `color` | — | 色碼框 `#RRGGBB`／`#RRGGBBAA` | 色彩群組鍵，寫到 `<鍵>.r/.g/.b/.a` 或 `<鍵>.0–.3` 四個分量 |
| `text` | — | 輸入框（Enter 或離開時寫入） | 登錄鍵（字串值，例如 `accessory.parts.0.parentKey`） |
| `button` | — | 按鈕 | `action`：讀卡器動作表 |

- 其他欄位：`label`（顯示文字）或 `label_id`（文字表 id，跟著讀卡器語言）；`button` 要有 `action`。
- **做法**：每個項目在控制器那層**透明的 UMG** 裡建一個真的 UMG 控制項（`UOKPageItemToggle`／`Choice`／`Text`／`Button`），放在每頁一個 `UVerticalBox`（掛在 `ShapeBox` 下，平常收起，進那頁才顯示，和 `StyleBox` 同一套），再讓新畫面照常 `Mirror()`。所以：
  - 畫面、樣式、`ok.ReaderScreen controls／press／set` 都和原生控制項一樣；
  - 寫入一律經 `OKCharacterMCPRegistry::SetParameters`，和 `reader_call set` 同一條路（卡片屬性照舊是「暫存，按套用才寫進卡」）；
  - 值每 0.25 秒從登錄讀回來（只在該頁顯示時），所以 `reader_call set` 改了，頁面上的控制項會跟著變；
  - 鍵在建頁時不檢查存不存在：卡片屬性是進頁時才讀，讀到之前控制項是停用狀態。
- **讀卡器自己的鍵** `reader.lang`：只能是 `choice`，選項是繁體中文／简体中文／English。
- **動作表** `OKReaderPageItems::RunAction`：`add_accessory_slot`、`apply_properties`、`reset_properties`、`tpose`、`walk`、`pause`、`replay`、`blink`、`reset_left_hand`、`reset_right_hand`、`speak`。`own_buttons` 也改用這張表（原本只認 `add_accessory_slot`）。工作項 7 會再加 `mod.<id>.<cmd>`。
- 錯誤照設計文件的規則：不認得的 `kind`、不認得的 `action`、`button` 沒有 `action` 等，紅字列出、那一項不建，其他照建。
- 新主控台指令 `ok.ReaderScreen pageitems`：列出每個項目的種類、鍵或動作、UMG 名稱與是否顯示中。
- `Tools/reader_pages.lua`（離線檢查）認得新種類：`bool`／`choice`…算進頁面內容（數值列換成開關會列為 changed），`button` 以動作比對，`reader.lang` 不算未知鍵。
- 正式的 `Config/ReaderEditor/pages.json` 只加了一項：**設定／介面›介面** 加「語言」下拉（`reader.lang`，`label_id = reader.settings.language`）。其他新種類只在測試頁面檔驗證，沒有放進正式頁面。

### 2. 讀卡器的文字與 ICU 格式化（新檔 `Source/OpenKoikatsu/OKReaderText.{h,cpp}`）

- `OKReaderT(id)`、`OKReaderMsg(id, args)`：從共用文字表（`Content/IndependentResources/StreetSocialData/Localization/<lang>/*.toml`，ICU MessageFormat）取字，和街區的 `OKT`／`OKMsg` 同一套，由 ok-rules 格式化。
- 讀卡器原本不開 ok-rules；現在第一次要字時才開（已經有人開了就共用；否則照 1 對 1 的做法複製一份 DLL 再開，不鎖住建置）。開不起來就顯示 id 本身，不會讓控制項消失。
- 語言：`-ReaderLang=<lang>`，否則上次選的（`Saved/CardReader/language.txt`），否則 zh-TW。
- **外掛群組標題**：屬性面板（`OKGalleryProperties.cpp` `RebuildPropertyControls`）在每個外掛區段的第一列前面加一個標題，內容是 `reader.properties.plugin_group_rows`（`{group}（{count, plural, other {# 項}}）`），`group` 是該區段的 `group_id`（`reader.plugin_group.*`，ok-extract `plugins.rs` 本來就有輸出，C++ 之前沒讀）翻成目前語言。
- 文字表新增（三種語言都加）：`[reader.settings] language`、`[reader.properties] plugin_group_rows`。文字表是編進 `ok_rules.dll` 的（`locale.rs` 的 `include_str!`），所以 ok-rules 要重編（已重編，`cargo test --release` 304 個通過）。

### 3. 順手修的既有問題：卡片的 `physics.*` 選單寫不進去（`OKCharacterMCPRegistry.cpp`）

`SetParameters` 把所有 `physics.` 開頭的鍵都當身體物理滑桿（`OnBodyPhysicsChanged(…, AsNumber())`），但卡片屬性也有 `physics.hair.back`、`physics.clothes` 這類 `okPh` 下拉（字串值）。寫入時被當成數字 0 丟掉，`reader_call set` 也一樣。改成只有不屬於卡片屬性（`category != "properties"`）的 `physics.*` 才走身體物理，其餘照一般屬性暫存。

## 驗了什麼

建置：`may-build` 後用 D: 引擎建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development，兩次（含第 3 項修正前後）都 `Result: Succeeded`。

讀卡器實測（`c-mod-4` 占名額，`jeanne.png`，`-ReaderPages=` 指向一份加了「MOD 測試」頁的測試檔，用完已關閉並釋放名額）：

| 項目 | 結果 |
|---|---|
| 新頁面顯示 | toggle、下拉、色碼（`#E8E7E3FF`）、文字（`a_n_wrist_R`）、按鈕、語言下拉都在，值是卡上的值（截圖：`C:\portable\OpenKoikatsu\Saved\OKControl\shots\78136-0001.png`） |
| 錯誤項目 | `action no_such_action`、`kind slider` 兩項紅字列出、不建，其他照建 |
| 經 MCP（`ui_exec` → `ok.ReaderScreen set`）寫入 | toggle `true`、色碼 `#FF000080`（四個分量 1／0／0／0.502）、文字 `a_n_wrist_L`、按鈕「眨眼」；`reader_call get` 讀回的值都對，`pending_properties` 6 |
| 反向（`reader_call set` 改鍵 → 頁面跟著變） | `hair.parts.0.baseColor.1 = 1` 後，頁面色碼變成 `#FFFF0080` |
| 下拉（第 3 項修正後） | `physics.hair.back` 選 KawaiiPhysics，`reader_call get` 讀回 `kawaii` |
| 語言 | 切到 English：`label_id` 的標題變 `Language`，屬性面板外掛標題 `Pushup (292 rows)`（截圖：`C:\portable\OpenKoikatsu\Saved\OKControl\shots\78136-0002.png`）；切回繁中：`內衣塑形（292 項）`；`Saved/CardReader/language.txt` 記住選擇 |
| 收尾 | 測試中暫存的修改都按「撤銷尚未套用」清掉（`pending_properties` 0），卡片沒有被改 |
| 離線檢查 `reader_pages.lua --old <HEAD 的 pages.json> --new Config/ReaderEditor/pages.json` | 只有「設定／介面›介面」一頁變（多一項 `choice reader.lang`） |

## 沒驗什麼、發現的問題

- **`ui_widgets`／`ui_set` 在讀卡器（DreamGUI 新畫面）整個是空的**：`buttons`、`controls` 都是空陣列，連原本鏡像的滑桿、按鈕也沒有，不是這次的新控制項才有的問題。推測是 UMG 層設成 `RenderOpacity 0`（`OKGalleryWidget.cpp:1077`）後，`OKGameControl.cpp` 的 `OnScreen()` 讀到的 cached geometry 是 0，所以全部被濾掉；沒有再查證。`OKGameControl.cpp` 歸 F 組（工作項 6），我沒有改。`Docs/CARD_READER_DREAMGUI.md` 第 49 行「`ui_*` 照舊操作 UMG 控制項」目前不成立。新控制項是真的 UMG 控制項，這個問題修好後自動會出現在 `ui_widgets`。這次 MCP 的驗證改走 `ui_exec`（`ok.ReaderScreen set／press`）與 `reader_call get／set`。
- `ok.ReaderScreen set key=<鍵>` 對卡片屬性一律拒絕（原本就這樣，`SetByKey` 的 `category == "properties"`），所以新控制項綁的屬性鍵要用路徑 `set` 或 `reader_call set`。
- 屬性列本身的標籤（例如「胸罩塑形資料／托高」）是 ok-extract 產生的中文，不跟語言走；這次只翻了群組標題。讀卡器其他寫死的中文字也還沒改走文字表。
- 打包後的 stage：讀卡器找 `Tools/ok-rules/target/release/ok_rules.dll` 的方式和 1 對 1 一樣，沒有在打包版驗證。
- 新控制項只在測試頁驗證；`toggle`／`text` 寫入的是暫存，沒有按「套用」實際寫進卡片看重開後的結果（套用流程本身沒改）。
