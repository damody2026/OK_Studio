# 讀卡器 DreamGUI 介面（2026-11-18）

`CardReaderDevelopment.cmd` 的讀卡器／人物編輯器改用 [DreamGUI](https://github.com/TypeDreamMoon/DreamGUI)（MIT，`Plugins/DreamGUI/`，commit 4ac86e8f）顯示，版面照使用者 2026-11-18 的草圖：

| 區域 | 內容 |
|---|---|
| 左欄（右緣可拖拉調寬，540 px 起，最寬到 3D 視窗只剩鏡頭列的寬度） | 「返回啟動器」、四個分頁（編輯／人物卡／衣服卡／設定）、分類欄（臉、身子、衣服、配件、角色資訊、人物卡總欄、衣服卡總欄、設定／介面）、二級選單（臉型／下巴／…、全身／胸部／…）、該分類的控制項 |
| 中間 | 3D 視窗本身（不畫東西）、上方鏡頭列（全身、半身、臉部、腿部、正面、左側、右側、背面、俯視）、右下角卡片名稱 |
| 右欄 | 上方是有標題、預設收起的抽屜（動作與表情、左右手、選擇動畫），下方是「人物編輯」按鈕區（重設到預設值、載入3D、返回、進入1對1、進入工作室、動作時間軸、另存新檔、存成 KKS 卡、左右手動作、服裝）；底部固定的外掛工具區 |

分類欄在四個分頁都顯示，「設定／介面」固定在分類欄最下方。

「返回啟動器」：專案沒有獨立的啟動器程式，按下會回到卡片牆並切到「人物卡」分頁（挑卡、開卡的地方）。

## 架構

```
UOKCharacterController（UMG 控制項 = 模型，處理常式、存檔、MCP 都讀寫它們）
        │ 透明（RenderOpacity 0）、HitTestInvisible，不再看得到
        ▼ 每幀同步（值、選項、啟用、顯示）／DreamGUI 的操作照 ui_set 的步驟寫回 UMG 並觸發事件
UOKReaderScreen（DUI/Reader/ReaderScreen.dui → /Game/UI/Reader/WBP_ReaderScreen）
   └ UOKDreamControl × N（DUI/Reader/Controls/*.dui → /Game/UI/Reader/Controls/WBP_OK*）
```

- 程式：`Source/OpenKoikatsu/OKReaderScreen.h/.cpp`。`UOKDreamControl` 是一個鏡像控制項（Label／Button／Slider／Toggle／Choice／Input／Image／Drawer，由各自的 `.dui` 決定有哪些部件）；`UOKReaderScreen::Mirror` 把一棵 UMG 子樹轉成 DreamGUI 控制項，橫向列（`UHorizontalBox`）保留成橫列，UMG 面板的子項增減時整段重建。
- 版面與外觀改 `.dui`（`DUI/Reader/`，主題 `DUI/Theme.dui` 用 DreamGUI 的 Default preset），改完執行：

  ```powershell
  .\Tools\lua\lua.exe Tools\build_reader_ui.lua
  ```

  它用 DreamGUI 的 `DreamUICompileWidgets` commandlet 依 `DUI/Reader/widgets.json` 重建 `Content/UI/Reader/` 的 widget Blueprint（需先建好編輯器目標）。編輯器開著時存檔 `.dui` 會自動重編。
- 打包：`Config/DefaultGame.ini` 的 `DirectoriesToAlwaysCook` 含 `/Game/UI/Reader`（按路徑載入，沒有地圖參照它們）；DreamGUI 自己的內容由外掛的 `Config/Game.ini` 加進 cook。
- 目前要加啟動參數 `-OKDreamReader` 才開 DreamGUI（畫面驗收前的開關）；不加時照舊顯示 UMG 控制項。
- 滑鼠輸入：`Config/DefaultDreamGUI.ini` 設 `bUseSlateInputSource=True`、`SlateInputConsumePolicy=WhenOverUI`，DreamGUI 直接從 Slate 收滑鼠（預設的 PlayerController 輸入在讀卡器裡收不到），按在 DreamGUI 控制項上的鍵不再傳給鏡頭。
- 透明的 UMG 層一律 `HitTestInvisible`：`SetModelLayout` 切版面時原本把整個 widget 設回 `SelfHitTestInvisible`，透明控制項又能被點到、搶走 DreamGUI 的點擊（2026-11-18 實測點「身子」卻按到隱藏的「另存 APNG」）；有 `ReaderScreen` 時改成固定 `HitTestInvisible`。
- 左欄拖拉調寬讀 DreamGUI 自己的滑鼠指標資料（`UDreamEventSystem::GetPointerEventData(DreamUIPointerIds::Mouse)`），不讀 PlayerController（按在把手上的鍵被 DreamGUI 吃掉，PlayerController 看不到；`FSlateApplication` 的游標換算也沒抓到）。寬度上限保留鏡頭列按鈕的原始寬度，鏡頭列不會被擠成直排或鑽到右欄底下。
- 鏡頭列的「正面／左側／右側／背面」設定絕對方位（`OrbitYaw`，0 是正面），連按不會轉回來；「全身／半身／臉部／腿部／俯視」保留目前方位，「俯視」從上往下看。
- 2026-11-18 以真實滑鼠實測通過：鏡頭列「背面」（連按兩次）、「俯視」、左欄拖拉調寬、臉部滑桿拖拉（寫回 UMG 數值）、「重置」、分類欄、二級選單、右欄抽屜收合、遊戲動作下拉選單選取並播放。

## MCP

- `ui_*`（ok-game-mcp）照舊操作 UMG 控制項：它們仍在畫面上（只是透明），值改了 DreamGUI 下一幀跟著變。
- 版面本身的導覽（分頁、分類、二級選單、左欄寬度）沒有 UMG 控制項，用主控台指令（`ui_exec`）：
  `ok.ReaderScreen tab <0-3>`、`ok.ReaderScreen category 臉`、`ok.ReaderScreen sub 眼睛`、`ok.ReaderScreen width 640`、`ok.ReaderScreen state`。
- `reader_call state` 多了 `screen`（`tab`、`category`、`left_width`）。

## 各分頁的來源

- 「配件／屬性」進入時呼叫 `OnOpenProperties`（屬性編輯器要打開才讀卡）；「角色資訊」進入時把卡片牆的 `InspectCol` 顯示回來（開卡後 `SetModelLayout` 會收起它）；「設定／角色風格」進入時顯示 `StyleBox`（UMG 只在舊的「角色風格」分類下顯示它）。UMG 層透明又不吃點擊，所以這些只讓 DreamGUI 有東西可鏡像。
- 「設定／物理」只鏡像物理下拉與三條滑桿（各自連同前一行說明文字），不是整個動作欄。
- 沒有「介面」頁：UMG 的編輯欄寬度與字級只改看不見的 UMG 層；左欄寬度改用拖拉。

- 右欄抽屜的標題列有外框，右側 ▶（收起）／▼（展開）；整列可點（2026-11-18 實拍）。
- 「人物編輯」按鈕三欄等寬、一行顯示，過長的字（重設到預設值、進入1對1互動場景）自動縮小字級，不再撐高整列（2026-11-18 實拍）。
- 人物卡清單在目前的卡前加 ▶，其他卡稍暗（2026-11-18 實拍）。
- 遊戲動作等大清單（`UOKMotionComboBox`）上方有搜尋框，用 `UOKMotionComboBox::SetSearchText` 篩選（名稱、編號、顯示標籤，空格隔開的詞全部要符合）；下拉選單只列符合的項目，選了照原清單的索引寫回 UMG。2026-11-18 實拍：輸入「01」只剩 01 系列，選「Demo：坐姿 01」後播放該動作。
- 抽屜標題 hover／按下時改為半透明底色（原本不透明的 hover 底色蓋住箭頭）；2026-11-18 實拍滑鼠停在「動作與表情」上，箭頭看得到。
- 鍵盤與搜尋框（2026-11-18 用 MCP 的 `ui_mouse`／`ui_type`／`ui_focus` 走 Slate 實測）：點搜尋框後 `ui_focus` 顯示它在編輯；打「walk」字進框裡，鏡頭位置與角度不變；點 3D 視窗後字與編輯狀態都在；下拉選單開著按 Enter，DreamGUI 只把鍵盤焦點框移到第一項，不播動作（再按一次才選）；搜尋「01」選「Demo：坐姿 01」後搜尋字仍在。先前「打字時鏡頭動了」是用系統 SendKeys 模擬時看到的，走 Slate 的真實路徑沒重現。
- 鏡像面板重建（UMG 子項增減）時，搜尋框保留已打的字，正在打字的話新的框接回編輯；看不見的 UMG 層拿到鍵盤焦點時，焦點移回遊戲視窗（DreamGUI 只在遊戲視窗有焦點時收鍵，見 `FDreamUISlateInputSource::IsKeyForThisWorld`）。兩者都寫 log（`ok.ReaderScreen:`）；實測那一段沒有觸發，只驗了程式能建、平常不誤觸。

## 已知限制

- 「屬性」頁的長選項會折成多行、數字欄偏窄。
- 卡片清單一頁最多列 400 張。
- 卡片預覽圖片、外觀選擇的縮圖格以 `WBP_OKImage` 顯示 UMG 圖片的貼圖，未逐張驗證。
