# OK Mod 工作項 7b：DreamGUI D1 宣告式（C 組，2026-11-23）

計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §6.13（D1 歸 C，D2 `.dui` 歸 F）。給 mod 作者的格式在 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md) §4。沒有改 `ok-mod-api`：`reader.ui` 的回覆本來就是自由的 JSON，新種類與容器只是多了欄位。

## 做了什麼

### 1. 頁面 JSON：`layout`、`kind`、`style`

- 頁與 `group` 可帶 `layout`：`column`（預設）、`row`、`tabs`、`scroll`。容器 `group`（可摺疊：`fold`）、`row`、`tabs`、`scroll` 可以互相巢狀。
- 新種類：`number`（SpinBox）、`slider`、`radio`、`color`（`#RRGGBB`）、`list`（可選，或只顯示一串字）、`progress`、`label`（可顯示某個鍵的值）、`image`（mod 資料夾裡的 PNG）。原有的 `bool`、`choice`、`text`（新增 `multiline`、`placeholder`、`max_length`）、`button` 照舊。
- `style`：主題（`DUI/Theme.dui` → DreamGUI Default preset）的文字樣式名稱（Title、Lead、Body、Caption、AccentText、GoodText、BadText、WarnText 等），目前只套在 `label` 上。

### 2. 宿主（`Tools/ok-mod/host/src/card.rs`）

`reader.ui` 每一層都改寫：`key` → `mod.<id>.<key>`、`action` → `mod.<id>.<action>`、`image` → mod 資料夾內的完整路徑。資料夾外的路徑、`..`、不存在的檔案都會被拿掉，mod 只能顯示自己的圖。

### 3. 讀卡器：直接建 DreamGUI 原生控制項（新檔 `Source/OpenKoikatsu/OKReaderModPage.cpp`）

- Mods 分類的每一頁改由 `FGroup.Build` 直接建 DreamGUI 控制項，**不再經 UMG 鏡像**（原本是 `OKReaderPageItems` 先建 UMG 再 `Mirror`）。
- 新增七種控制項 `.dui`（`DUI/Reader/Controls/`：Spin、Progress、Radio、Color、List、Tabs、Scroll），照 `CARD_READER_DREAMGUI.md` 的流程用 `build_reader_ui.lua`（`DreamUICompileWidgets`）編成 `Content/UI/Reader/Controls/WBP_OK*.uasset`。
- `UOKDreamControl` 新增：
  - 綁定值的 `Pull`／`Push`：`Pull` 每幀從 `OKReaderMods::Value` 顯示值，`Push` 經 `OKReaderMods::Set` 走 `reader.control`；
  - 新元件成員：Spin、Progress、Radio、Tabs、List、Scroll、Swatch。
- 值與事件照舊走 `reader.values`／`reader.control`。顯示 mod 傳來的值時不會被當成使用者的修改再送回 mod。輸入框和數字框只在 mod 那邊的值改變時才覆蓋，正在打的字不會被蓋掉。
- 每個控制項都登記在讀卡器畫面的控制項清單，可以用 `ok.ReaderScreen controls`／`press`／`set` 操作，路徑是「Mods›頁名›…」。
- **數字滑桿與顏色**（工作項 7 留下的）在這裡補齊了。`OKReaderMods::Rows` 改成走巢狀項目：
  - 每個有值的控制項都是登錄列，`reader_call get/set` 都讀寫得到；
  - mod 的顏色登錄成 `kind: "text"`、`format: "#RRGGBB"`，和內建 0～1 的顏色分量分開。

### 4. 範例

- **profile**：兩個分頁。「簡介」頁是多行 TextInput，下面顯示字數；「說明」頁是 Body 樣式的文字。
- **outfit-names**：兩個分頁。「這一套」頁用 TextInput 寫名稱，並標出目前是第幾套；「全部」頁是唯讀的 ListView，列出這張卡已命名的服裝。
- **random-chara**：幅度改成 `radio`。
- **ui-sample**（新，`targets = ["reader"]`）：每一種控制項與容器各放一次，值只存在記憶體裡。給 mod 作者照抄，也是這次的實測頁。附一張自製的 32×32 `icon.png`。

## 驗了什麼

- **cargo**：`Tools/ok-mod` 整個 workspace 的 `cargo test` 全過。新增的測試有三項：
  - 宿主單元測試 `nested_items_are_rewritten_and_images_stay_in_the_mod_folder`；
  - `card_mods.rs` 確認分頁、群組裡的鍵也有前綴；
  - ui-sample 的兩個單元測試。
  - ok-extract 沒動。
- **建置**：每次建置前都跑 `may-build`，用 D: 引擎建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development，最後一次改動後兩個都是 `Result: Succeeded`。
- **讀卡器實測**（`c-mod-7b` 拿到 slot1 後才開，用完已關閉並釋放；開的卡是 `C000.png`）：

| 項目 | 結果 |
|---|---|
| `reader_call get`（巢狀在分頁裡的鍵） | ui-sample 的 `count`、`tint`（`kind: text`、`format: #RRGGBB`）、`size`、`fruit`；profile 的 `text`、outfit-names 的 `name`、random-chara 的 `spread` 都列出，值正確 |
| `reader_call set` | 改 `count`、`tint`、`size`、`fruit`、`volume` → `applied`。畫面上數字框顯示 7、滑桿 0.8、進度條 80%、色塊與字串 `#C04050`、AccentText 摘要「數量 7，音量 80%，顏色 #C04050」 |
| 畫面操作 → mod | `ok.ReaderScreen set …›數量›Spin = 5` → mod 的 count 變 5；`press …›小`（單選）→ size 變 `s`；滑鼠點清單的「葡萄」→ fruit 變 `grape`；`set …›Input = 第一行備註` → note 正確 |
| 分頁 | 滑鼠點「數值」「選擇」「文字與其他」三個分頁都能切換，內容正確 |
| 可摺疊群組、捲動區、唯讀清單 | 「目前的值」按下會收起與展開，裡面的清單列出每個值 |
| 按鈕 | 「恢復初始值」→ 執行 mod 指令，提示「範例控制項已恢復初始值」，值回到初始 |
| 圖片 | mod 資料夾裡的 `icon.png` 以 64×64 顯示 |
| profile | `set` 簡介後多行欄位顯示內容，字數即時變成「12 / 2000 字」 |
| outfit-names | `set` 名稱「旗袍」→ 右側服裝下拉顯示「服裝 1：旗袍」，「全部」分頁列出「服裝 1：旗袍」 |
| 效能 | 停在 mod 頁時約 440 FPS（Frame 2.3 ms），和其他頁一樣；切分頁那一幀有一次瞬間掉幀 |

截圖在 `C:\portable\OpenKoikatsu\Saved\OKControl\shots\`，`82184-0002.png`～`0007.png` 和 `8380-0002.png`～`0003.png`。

### 實測中發現並修好的

- 色塊太暗：它套了 Card 樣式的漸層底色，`SetColor` 只是染色，顏色被乘暗。改成關掉漸層、直接設 RectBlock 的 BodyColor。
- 圖片被擠窄：只設寬度時，欄位把它當最小值，圖片被壓窄。改成寬高都固定。

## 沒驗什麼、限制

- **`ui_widgets`／`ui_set`**：C 還沒有 F 的 DreamGUI 鏡像列舉（9a63c5401），同步點 B 之後再驗。目前畫面這一側用 `ok.ReaderScreen controls/press/set` 驗證，資料這一側用 `reader_call get/set` 驗證。
- **藏在別的分頁裡的控制項，`press`／`set` 照樣做得到**：TabView 收起分頁的方式不經 `GetShown`，所以 `IsOnScreen` 認為它還在畫面上。結果仍然正確（值照樣寫到 mod），只是不像真人那樣「看不到就點不到」。
- `style` 只套在 `label`。按鈕與容器的外觀樣式（ButtonPrimary、Card、Well）還沒開放，因為執行時不能套 `.dui` 的 style，要的話得逐一寫成程式。
- 多行輸入框在可摺疊群組收起後會被撐高，因為 TabView 的頁固定高度、欄位補滿空間。不影響使用。
- **random-chara 的髮色仍延後**：髮色是屬性列（每張卡分頁），不是登錄鍵，mod 的 `set` 還寫不到。
- 打包的 stage 沒有重建驗證，只用編輯器建置的讀卡器測。新的 `.uasset` 在 `/Game/UI/Reader`，本來就在 `DirectoriesToAlwaysCook` 裡。
- 舊的 `OKReaderPageItems` 仍給 pages.json 的內建頁面用，mod 頁已經不用它。
