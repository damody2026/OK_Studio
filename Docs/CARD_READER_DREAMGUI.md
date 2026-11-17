# 讀卡器 DreamGUI 介面（2026-11-18）

`CardReaderDevelopment.cmd` 的讀卡器／人物編輯器改用 [DreamGUI](https://github.com/TypeDreamMoon/DreamGUI)（MIT，`Plugins/DreamGUI/`，commit 4ac86e8f）顯示，版面照使用者 2026-11-18 的草圖：

| 區域 | 內容 |
|---|---|
| 左欄（右緣可拖拉調寬，360–1000 px） | 「返回啟動器」、四個分頁（編輯／人物卡／衣服卡／設定）、分類欄（臉、身子、衣服、配件、角色資訊、人物卡總欄、衣服卡總欄、設定／介面）、二級選單（臉型／下巴／…、全身／胸部／…）、該分類的控制項 |
| 中間 | 3D 視窗本身（不畫東西）、上方鏡頭列（全身、上半身、臉部、腿部、正面、左側、右側、背面、俯視）、右下角卡片名稱 |
| 右欄 | 有標題的抽屜：「人物編輯」（重設到預設值、載入3D、返回、進入1對1、進入工作室、動作時間軸、另存新檔、存成 KKS 卡、左右手動作、服裝）、動作與表情、左右手、選擇動畫；底部固定的外掛工具區 |

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

## MCP

- `ui_*`（ok-game-mcp）照舊操作 UMG 控制項：它們仍在畫面上（只是透明），值改了 DreamGUI 下一幀跟著變。
- 版面本身的導覽（分頁、分類、二級選單、左欄寬度）沒有 UMG 控制項，用主控台指令（`ui_exec`）：
  `ok.ReaderScreen tab <0-3>`、`ok.ReaderScreen category 臉`、`ok.ReaderScreen sub 眼睛`、`ok.ReaderScreen width 640`、`ok.ReaderScreen state`。
- `reader_call state` 多了 `screen`（`tab`、`category`、`left_width`）。

## 已知限制

- 遊戲動作等可搜尋的大清單（`UOKMotionComboBox`）目前是一般下拉選單，沒有搜尋框。
- 卡片清單一頁最多列 400 張。
- 卡片預覽圖片、外觀選擇的縮圖格以 `WBP_OKImage` 顯示 UMG 圖片的貼圖，未逐張驗證。
