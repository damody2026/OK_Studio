# 讀卡器新版 UI：資料驅動的編輯器頁面（設計說明，2026-11-19，e-fork-2）

只寫設計，還沒寫程式。目的：使用者要「參考原作程式碼把人物編輯器所有細項功能都加上去」。e-cardload 會從 `D:\XKoikatuSunshine\kks_decomp` 盤點出缺口清單（`Docs/CHARACTER_EDITOR_PARITY_PLAN.md`），之後補項目時只改資料，不改 UI 程式碼。

## 現況：新版畫面是「鏡像」

`UOKReaderScreen::BuildCategories` 用手寫的 C++，把 `UOKCharacterController` 的 UMG 控制項一個一個掛進分類（`Group(名稱, {UMG 控制項…})`）。`Mirror()` 依 UMG 控制項的型別生出 DreamGUI 控制項，數值與事件都轉回那個 UMG 控制項。這套能用，稽核表 4877 個控制項的缺口也已清零，但有兩個問題：

- **加一項要改兩邊**：先在 UMG 那邊做控制項，再在 `BuildCategories` 把它掛到某頁。原作編輯器的項目數量很大（臉 52、身體 44 個滑桿，加上顏色、選圖、開關、下拉、每個飾品欄位的一整組），每加一批都要改 C++、重編、重排版面。
- **資料端其實已經有一層**：`OKCharacterMCPRegistry::Parameters()` 已經把參數列成「鍵＋種類＋標籤＋範圍＋預設」：`shape.body.N`、`shape.face.N`、`bone.<骨>.<軸>`、`physics.*`、`pregnancy.*`、`style.*`，以及 `SetEditorProperty` 管的屬性樹（`hair.*`、`accessory.parts.*`…）。`SetParameters()` 也能套用。MCP 的 `reader_call get/set` 走的就是這層。新版畫面卻繞過它，去鏡像 UMG。

## 做法：頁面定義檔 ＋ 綁定登錄鍵的控制項

### 1. 定義檔

一份 JSON：`Config/ReaderEditor/pages.json`。放 `Config/`，是因為打包流程本來就整個帶上它（`Tools/package_street_social.lua`），遊戲用一般檔案 IO 讀，不用進 pak。結構是「分頁 → 分類 → 子頁 → 項目」，和現在畫面的三層一致：

```json
{
  "version": 1,
  "tabs": [
    { "id": "edit", "label": "編輯", "categories": [
      { "id": "face", "label": "臉", "subs": [
        { "id": "shape", "label": "臉型", "items": [
          { "key": "shape.face.0", "kind": "number", "label": "臉整体寬度", "display": "percent" },
          { "key": "shape.face.1", "kind": "number", "label": "臉上部前後", "display": "percent" }
        ]},
        { "id": "eyebrow", "label": "眉毛", "items": [
          { "kind": "picker", "target": "eyebrow" },
          { "key": "shape.face.18", "kind": "number", "label": "眉毛上下", "display": "percent" },
          { "key": "face.eyebrowColor", "kind": "color", "label": "眉毛顏色" }
        ]}
      ]}
    ]}
  ]
}
```

每個項目的欄位：

| 欄位 | 必填 | 說明 |
|---|---|---|
| `kind` | 是 | 控制項型別，見下表 |
| `key` | 綁資料的項目必填 | 登錄鍵（`Parameters()` 裡的 `key`），或 `prop:` 開頭的屬性路徑 |
| `label` | 否 | 顯示文字；不填就用登錄裡的 `label`。之後可換成多語系 id（`Localization/<lang>/*.toml` 的語意 id，和街區一樣用 ICU） |
| `min`／`max`／`step`／`default` | 否 | 覆寫登錄的值；不填就用登錄的 |
| `display` | 否 | `percent`（0–1 顯示成 0–100）、`int`、`degrees`… |
| `when` | 否 | 顯示條件，例如 `{"sex": 1}`、`{"has": "accessory.slot"}`、`{"bone_category": "眼球"}` |
| `repeat` | 否 | 依清單展開一組項目，例如每個飾品欄位一組，`"repeat": "accessory.slots"`，項目鍵裡用 `{slot}` |
| `id` | 否 | 路徑裡要和標籤不同的名字時用（例如兩個同名標籤） |

### 2. 控制項型別

每種型別對應一個現有的 `.dui` 範本（`MakeControl` 已在用的那幾個），沿用現在的外觀：

| `kind` | 畫面 | 讀／寫 |
|---|---|---|
| `number` | 標題＋滑桿＋數字框＋重置（現在的 Slider 列） | `Parameters()` 讀值；`SetParameters([{key,value}])` 寫值；重置寫 `default` |
| `color` | 標題＋色塊＋色碼框 | 同上，值是 RGBA |
| `bool` | 開關 | 同上 |
| `choice` | 下拉（選項從登錄的 `choices` 來，30 項以上加搜尋框，和現在一樣） | 同上 |
| `text` | 輸入框 | 同上 |
| `picker` | 選圖格子頁（現有的 PickTile 頁，`target` 是外觀目錄的類別） | 外觀目錄 `catalog`／`apply`（`ApplyAppearanceItem`），快取上限照舊 |
| `bones` | 一組骨骼列（現在的骨骼調整頁，`category` 指定骨骼分類） | `bone.*` 鍵 |
| `button` | 按鈕 | `action` 欄位指定命令（同 MCP `reader_call action`），例如隨機、重置類型 |
| `custom` | 畫面自己的頁（遊戲目錄、卡片牆…） | `builder` 欄位指定一個已註冊的 C++ 函式名，給沒辦法用資料描述的頁 |
| `mirror` | 鏡像一個 UMG 控制項（`widget` 填 UMG 名稱） | 現在的 `Mirror()`；**過渡期用**，讓全部頁面從第一天就由定義檔描述 |

新增型別才需要改 C++；新增項目、移動項目、改標籤、改範圍、改順序都只改 JSON。

### 3. 讀檔與錯誤

- 開讀卡器時讀定義檔，先驗證再建頁面：
  - 鍵必須存在於登錄。
  - 同一頁內路徑不能重複。
  - `kind` 必須是已知型別。
  - `mirror` 的 `widget` 必須找得到。
- 驗不過就在畫面上用紅字列出哪一行錯了（`ScreenNote`），那一項不建，其他照常。**不退回舊版 UI**。
- 開發時可以熱重載：`ok.ReaderScreen reloadpages` 重讀定義檔、重建目前這頁，不用重開遊戲。

## 和現有頁面怎麼銜接

1. **第一步，不改行為**：把現在 `BuildCategories` 手寫的 36 頁照原樣寫成定義檔，全部用 `mirror` 與 `custom`。完成後跑 `ok.ReaderScreen audit`，結果必須和現在一樣（4877 個控制項、缺口 0、同名短名 57 組）。這一步證明「定義檔能完整描述現在的畫面」。
2. **第二步，逐頁換成綁鍵**：一頁一頁把 `mirror` 換成 `number`／`color`／`choice`…。每換一頁，跑一次稽核與那頁的 MCP `set` 實測。先換資料最齊的頁：臉型、身體滑桿（`shape.*`，96 項全在登錄裡）、物理、角色風格。
3. **第三步，補原作缺的項目**：照 e-cardload 的缺口清單分批加。資料端缺的先在登錄補鍵（C++／Rust），UI 只要在定義檔加一行。
4. 我做過的幾頁（遊戲目錄、眼部縮放2、眼睛、瞳孔覆蓋貼圖、介面的顯示字級、選圖頁）：遊戲目錄留 `custom`；顯示字級、眼睛相關的滑桿換成綁鍵；選圖頁換成 `picker`。

UMG 的控制項在第二步之後漸漸不再被新版畫面用到，但舊版（`-LegacyReader`，只作診斷對照）還要它們，所以在 PageFault 真因解掉、舊版拆掉之前都留著。

## 兩條硬要求怎麼守住

**所有控制項都能被 MCP 操作**

- 生成的控制項和現在一樣是 `UOKDreamControl`，路徑是「分類›子頁›標籤（›元件）」。`ok.ReaderScreen controls／press／set` 照舊能用，`IsOnScreen` 的 `[not shown]`、`IsOperable` 的 `[disabled]` 照舊標。
- 讀定義檔時就檢查路徑唯一，重複的直接報錯；短名重複（例如每列的「重置」）照現在的規則回 ambiguous，並列出路徑。
- 每個綁鍵的控制項多記它的登錄鍵：`set` 可以直接給鍵（`ok.ReaderScreen set key=shape.face.0 = 0.4`），`controls` 也能印出鍵，自動化不用依賴標籤文字。
- **稽核表擴充**：`ok.ReaderScreen audit` 除了現在的「舊版 UMG 控制項有沒有鏡像」，再加兩欄：
  - 登錄裡每個鍵有沒有出現在某一頁（沒有＝UI 缺，或列進「刻意不放」清單）；
  - 定義檔裡每個鍵在登錄裡存不存在（不存在＝資料端缺）。

  這兩欄就是 e-cardload 缺口清單的「UI 缺／資料端缺」，以後可以由稽核自動產出。

**新版 UI 是預設、而且是唯一會出現的介面**

- 定義檔、頁面生成都只在新版畫面裡；舊版 UMG 畫面完全不用它，所以不會因為這套而重新出現。
- 定義檔讀不到或驗證失敗，新版畫面照樣開、用紅字講哪裡錯；不會因此退回舊版。
- 舊版只在明確帶 `-LegacyReader` 時出現（診斷對照），維持「舊版 UI 留著不刪」那節的決定。

## 待決定

- 標籤要不要一開始就走多語系 id：一開始先寫中文標籤，等多語系一起做時再換成 id。
- 定義檔要一份還是每個分類一份：先一份，超過一千行再拆。
- 原作每項的「預設值」以誰為準：以登錄（`OKShapeDefaults` 等）為準，盤點發現不一致時記進缺口清單，不在定義檔裡另寫一份。

## 第一步的實作（2026-11-19，e-fork-2）

`Config/ReaderEditor/pages.json` 已照 `BuildCategories` 手寫的頁面原樣寫好，`UOKReaderScreen::BuildCategories` 先讀它，讀不到才用手寫的那份。這一步沒有改任何頁面；上面「定義檔」一節的 `tabs`／`items` 結構留給第二步，第一步的檔案只有「分類 → 子頁」，子頁的內容用下面這些欄位描述：

| 欄位 | 意思 |
|---|---|
| `name` | 子頁名稱（路徑的一段，同一分類內不能重複） |
| `sources` | 要鏡像的 UMG 控制項，依序：`{"shape":"face\|body","group":N}`（`KKShapeRows` 分隔線切出的第 N 組滑桿）、`{"rows":"bones\|bust\|physics"}`（骨骼列、胸部柔軟度／重量、物理的標題＋控制項）、`{"widget":"…"}`（`bone_category`、`bone_axes`、`pregnancy_box`、`style_box`、`appearance_panel`、`property_panel`、`inspect_col`、`card_col`、`outfit_row`、`outfit_nav`、`font_size_row`）、`{"named":"UMG 名稱"}`、`{"drawer":"Clothes\|Lighting"}`（同時在進頁時打開抽屜） |
| `pickers` | `{"targets":[…],"properties":[…]}`：這頁的選圖（外觀目錄的目標前綴）與詳細編輯（屬性鍵或標籤裡的字） |
| `bone_category` | 進頁時把骨骼分類下拉切到這一項 |
| `enter` | 進頁時做的事：`first_bone_category`、`accessory_slot_scope`、`all_properties`、`show_inspect_col` |
| `signature` | `bone_category`：骨骼分類或 X／Y／Z 開關變了就重建這頁 |
| `shown_only` | 只鏡像現在顯示的來源（骨骼列） |
| `builder` | 畫面自己的頁：`eye_overlays`、`game_root` |
| `own_buttons` | 畫面自己的按鈕：`[{"label":"…","action":"add_accessory_slot"}]` |
| `needs` | `bones`：沒有骨骼列就不建這頁 |

分類的欄位是 `name`、`tab`（0 編輯、1 人物卡、2 衣服卡、3 設定）、`subs`。來源全部找不到、又沒有自己的頁的子頁不建（和手寫版一樣，例如沒有懷孕面板時的「懷孕」）。

- **檔案位置**：遊戲讀 `-ReaderPages=<檔案>`，沒給就讀專案的 `Config/ReaderEditor/pages.json`。打包的 stage 只帶打包當時的 Config，所以 `Tools/run_card_reader_development.lua` 一律傳 checkout 裡那份的路徑。
- **錯誤**：讀不到、不是 JSON、`version` 不是 1、沒有 `categories`：用手寫的頁面，紅字說原因。個別分類或子頁寫錯（不認得的欄位、widget、builder、enter、名稱重複…）：那一頁不建，其他照建。錯誤在畫面右邊的通知列（紅字，一直留著）、每一頁最上面（紅字列出全部），log 是 `ok.ReaderScreen pages:` 開頭的 Error。不會退回舊版 UMG 畫面。
- **指令**：`ok.ReaderScreen pages` 報告頁面從哪來、幾頁、有什麼問題；`pages builtin`／`pages file` 換來源並重建；`reloadpages` 重讀檔案（改了 JSON 不用重開遊戲）。
- **稽核的兩欄**：`ok.ReaderScreen audit` 多一行 `registry: …`，報告檔（`Saved/Reports/reader-control-audit.txt`）多三段：
  - 登錄的鍵（`OKCharacterMCPRegistry::Parameters`）在不在某一頁（UI 缺）；
  - 定義檔寫到、登錄沒有的鍵（資料端缺，第二步開始有 `key` 才會有數字）；
  - 定義檔的問題。
  登錄鍵對控制項：`shape.*` 對滑桿，`bone.*` 對骨骼列（骨名＋軸），`physics.*`／`pregnancy.*`／`style.*` 對各自的滑桿，屬性（`category=properties`）對詳細編輯面板。
- **按鍵設定**：`ok.ReaderScreen set key=<登錄鍵> = <值>`：找出顯示那個鍵的控制項所在的頁（先找目前這頁），開到那頁再像人一樣設定，回報路徑。例如 `set key=bone.cf_J_Eye_tz.scale.uniform = 1.1` 會開到「臉›眼部縮放2」（進頁時骨骼分類切到眼球）再設。屬性（`category=properties`）的列是每張卡、每頁 64 筆動態生成，第一步還不能按鍵設定，會明講。

### 驗證（2026-11-19，stage `EFork1119r`，機器上只有這一個 Unreal，載入第 1 張測試卡）

- **稽核相同**：同一行程內先用定義檔、再 `pages builtin`、再 `pages file`，各跑 `audit`。
  - 第一輪：兩邊都是 37 頁、舊畫面可操作控制項 4877、鏡像 4867、新畫面自己畫 10、缺 0、同名短名 57 組。報告檔除了寫來源的那一行，逐字相同。
  - 之後再跑，總數會變成 5037／4995／42／73：第一輪逛過選圖頁、詳細編輯，生出了選圖格子與屬性列。這是狀態變了，不是頁面不同。在這個狀態下，定義檔、內建、再定義檔三份報告的雜湊一樣。
  - 比較時要在同一個狀態下比（同一行程連跑兩次再比），不要拿第一輪和第二輪比。
- **兩欄**：
  - 剛開卡時，登錄 2067 個鍵全在某一頁上。
  - 打開過詳細編輯後是 3665 個鍵（屬性讀進來了），也全在頁上。UI 缺 0。
  - 定義檔還沒有 `key`，所以資料端缺是 0。
- **壞檔**：
  - 不是 JSON 的檔：新版畫面照開，用內建頁面，頁首與通知列都是紅字，寫出檔名與 JSON 錯在哪一行哪一字。
  - 一個子頁寫了不認得的 widget、另一個寫了不認得的 builder：只少那兩頁（35 頁），兩個錯都用紅字列出。
  - 都沒有出現舊版 UMG 畫面。
- **按鍵設定**：`shape.face.0`、`shape.body.3`、`physics.bustSoftness`、`bone.cf_J_Eye_tz.scale.uniform` 都開到正確的頁並設好；不存在的鍵回 `not in the registry`。

## 第二步（逐頁換成綁鍵）與離線檢查（2026-11-19，e-fork-2）

### 做法

- 頁面可以寫 `items`：`[{"key": "shape.face.0"}, …]`，`kind` 目前只有 `number`（不寫就是 `number`）。
- 這一步的 `number` 先**鏡像那個鍵的控制列**：依登錄找出顯示該鍵的控制項（`OKRegistryControl`），滑桿就取它所在的那一列。所以畫面和稽核不變，而定義檔寫的已經是鍵。
- 之後換成畫面自己的控制項時，範圍、小數位、顯示單位都讀登錄的 metadata（`min`／`max`、`step`、`decimals`、`range_missing`…），`pages.json` 不寫範圍。
- 登錄沒有的鍵：紅字列出、那一項不建（其他照建），也算進稽核的「資料端缺」。
- 換頁的順序與判準：一次換一頁，建置後跑 `ok.ReaderScreen pages builtin／file` 對照稽核，差異 0 才提交，再換下一頁。

### 離線檢查（不用開遊戲）：`Tools/reader_pages.lua`

```
Tools\lua\lua.exe Tools\reader_pages.lua --new <新的 pages.json>     （在專案根目錄）
```

- 逐頁列出新增、刪除、移動的頁。對兩邊都有的頁，比較它「顯示的列」：shape 群組展開成那組的鍵，`items` 就是它的鍵，其他來源照原樣。不一樣就列 `changed`。
- 每個 `items` 的鍵對照不用遊戲就知道的登錄鍵：`shape.*` 來自 `KKShapeRows.cpp`，`bone.*` 來自 `OKBoneControls.h`，加上 `physics.bustSoftness／bustWeight`。打錯就列 `unknown key`。只有遊戲執行時才有的鍵（`pregnancy.*`、`style.*`、卡片的屬性）列出來，交給遊戲內稽核判斷。
- 有差異或未知的鍵就 exit 1。測試：`Tools\lua\lua.exe Tools\tests\test_reader_pages.lua`。
- 目前樹外的第二步版本（臉 8 頁、身子 5 頁換成 `items`；「胸部」因為還接著胸部柔軟度／重量兩列，順序要先支援才換）檢查結果是：同樣的頁、同樣的列、每個鍵都認得。

### 稽核第四欄「KKEx 不認得（`unknown_plugin_sections`）」的判準

- **什麼算 unknown**：這張卡 KKEx 區塊裡，這個 build 的認得表（`appearance/properties/plugins.rs` 的 `PLUGIN_SECTIONS`）沒有的**區段鍵**。
  - 區段鍵是外掛的身分（BepInEx GUID 或外掛自己的名字，例如 `com.deathweasel.bepinex.materialeditor`、`KSOX`），原樣比對、不分大小寫。
  - 刻意不列為認得、也不算 unknown 的兩個：ABMX（由 `bone.*` 編輯）與 sideloader 的 `com.bepis.sideloader.universalautoresolver`（來源解析，不是外觀資料）。
- **什麼不算 unknown**：
  - 認得的區段只是沒填值，或填的值這張卡用不到 → 不是 unknown，不列。
  - 沒有 KKEx 區塊 → 空陣列，不是缺欄。
  - 認得的外掛裡某個欄位缺範圍 → 那是「範圍缺（`range_missing`）」欄，不混進這欄。
- **一律按身分，不按位置**：外掛欄位的鍵是位置式的，同一個位置在不同卡上是不同外掛（alice 的 `m8` 是 MaterialEditor、megumin 的 `m8` 是 Pushup）。所以稽核按區段鍵（身分）數，不按位置、不跨卡沿用位置；否則同一個 build 在不同卡上會數出不同結論。
- **它的意思**：「這個 build 缺支援」，不是「這張卡有問題」。換一個認得表更新的 build，同一張卡就會變空。所以歸在「我們缺支援」那一類，不要讓使用者去改卡。
- **接線**：等 C++ 側的 `EditorUnknownPluginSections`（F 樹 `ccde34b12`）在建置窗口進 E 樹後，`ok.ReaderScreen audit` 的 registry 行與報告加這一欄。內容是目前載入的這張卡的清單；沒有載入卡時寫「沒有卡」，不是 0。
