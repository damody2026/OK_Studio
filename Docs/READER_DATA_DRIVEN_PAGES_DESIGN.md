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
