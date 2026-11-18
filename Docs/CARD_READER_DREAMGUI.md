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
- 預設就是 DreamGUI 畫面（2026-11-19 起，使用者：以後不要再出現舊版 UI）：`CardReaderDevelopment.cmd`、MCP `reader_launch`、直接跑 stage exe 都一樣；只有 `-LegacyReader`（`CardReaderDevelopment.cmd -LegacyReader` 或遊戲命令列）回舊版 UMG，留著做對照，新版補完並驗證後再刪。`-OKDreamReader` 已不再需要。
- DreamGUI 的 global shader（`DreamUIShaderGate`）：打包的遊戲啟動時不再要求它們（只有 `-DreamGUI` 強制），所以 base cook 在 DreamGUI 之前的 stage 開街區、一對一、Studio 不會 Fatal。讀卡器打開新畫面前先查 `DreamGUIGlobalShadersReady`；缺 shader 時不開新畫面，log 與畫面上寫出要重建什麼（`rebuild_street_social_patch.lua` 或新的完整 cook base），留在舊版控制項。2026-11-19 驗證：
  - 開發版預設是新畫面，命令列沒有 `-OKDreamReader`。
  - `-LegacyReader` 是舊版。
  - `SceneEditor.cmd` 正常。
  - 新 exe 搭舊 base `BaseE1118A` 的測試 stage `EFork1119a`：街區正常啟動、log 沒有 Fatal；直接跑 stage exe 開讀卡器是新畫面，DreamGUI 正常繪製（表示不要求也照樣讀得到 cook 進去的 shader）。
  - 「沒有 DreamGUI shader 的舊 base」這條本機沒有那樣的 base，沒實測。
- 滑鼠輸入：`Config/DefaultDreamGUI.ini` 設 `bUseSlateInputSource=True`、`SlateInputConsumePolicy=WhenOverUI`，DreamGUI 直接從 Slate 收滑鼠（預設的 PlayerController 輸入在讀卡器裡收不到），按在 DreamGUI 控制項上的鍵不再傳給鏡頭。
- 透明的 UMG 層一律 `HitTestInvisible`：`SetModelLayout` 切版面時原本把整個 widget 設回 `SelfHitTestInvisible`，透明控制項又能被點到、搶走 DreamGUI 的點擊（2026-11-18 實測點「身子」卻按到隱藏的「另存 APNG」）；有 `ReaderScreen` 時改成固定 `HitTestInvisible`。
- 左欄拖拉調寬讀 DreamGUI 自己的滑鼠指標資料（`UDreamEventSystem::GetPointerEventData(DreamUIPointerIds::Mouse)`），不讀 PlayerController（按在把手上的鍵被 DreamGUI 吃掉，PlayerController 看不到；`FSlateApplication` 的游標換算也沒抓到）。寬度上限保留鏡頭列按鈕的原始寬度，鏡頭列不會被擠成直排或鑽到右欄底下。
- 鏡頭列的「正面／左側／右側／背面」設定絕對方位（`OrbitYaw`，0 是正面），連按不會轉回來；「全身／半身／臉部／腿部／俯視」保留目前方位，「俯視」從上往下看。
- 2026-11-18 以真實滑鼠實測通過：鏡頭列「背面」（連按兩次）、「俯視」、左欄拖拉調寬、臉部滑桿拖拉（寫回 UMG 數值）、「重置」、分類欄、二級選單、右欄抽屜收合、遊戲動作下拉選單選取並播放。

## MCP

- `ui_*`（ok-game-mcp）照舊操作 UMG 控制項：它們仍在畫面上（只是透明），值改了 DreamGUI 下一幀跟著變。
- 版面本身的導覽（分頁、分類、二級選單、左欄寬度）沒有 UMG 控制項，用主控台指令（`ui_exec`）：
  `ok.ReaderScreen tab <0-3>`、`ok.ReaderScreen category 臉`、`ok.ReaderScreen sub 眼睛`、`ok.ReaderScreen width 640`、`ok.ReaderScreen state`。
- DreamGUI 自己的按鈕（鏡頭列、外觀圖片格、二級選單）MCP 的 `ui_press` 找不到：用 `ok.ReaderScreen press <文字> [#N]`；長頁截圖前用 `ok.ReaderScreen scroll <0–1>`。
- `reader_call state` 多了 `screen`（`tab`、`category`、`left_width`）。

## 各分頁的來源

- 外觀選擇與詳細編輯分到各頁（見下方「舊版控制項盤點」），進入頁面時以該頁的範圍打開（`SetAppearanceScope`／`SetPropertyScope`；控制器忙著讀目錄時每幀重試，`ApplyWantedScopes`）；「角色資訊」進入時把卡片牆的 `InspectCol` 顯示回來（開卡後 `SetModelLayout` 會收起它）；「設定／角色風格」進入時顯示 `StyleBox`（UMG 只在舊的「角色風格」分類下顯示它）。UMG 層透明又不吃點擊，所以這些只讓 DreamGUI 有東西可鏡像。
- 「設定／物理」只鏡像物理下拉與三條滑桿（各自連同前一行說明文字），不是整個動作欄。
- 沒有「介面」頁：UMG 的編輯欄寬度與字級只改看不見的 UMG 層；左欄寬度改用拖拉。

- 右欄抽屜的標題列有外框，右側 ▶（收起）／▼（展開）；整列可點（2026-11-18 實拍）。
- 「人物編輯」按鈕三欄等寬、一行顯示，過長的字（重設到預設值、進入1對1互動場景）自動縮小字級，不再撐高整列（2026-11-18 實拍）。
- 人物卡清單在目前的卡前加 ▶，其他卡稍暗（2026-11-18 實拍）。
- 遊戲動作等大清單（`UOKMotionComboBox`）上方有搜尋框，用 `UOKMotionComboBox::SetSearchText` 篩選（名稱、編號、顯示標籤，空格隔開的詞全部要符合）；下拉選單只列符合的項目，選了照原清單的索引寫回 UMG。2026-11-18 實拍：輸入「01」只剩 01 系列，選「Demo：坐姿 01」後播放該動作。
- 抽屜標題 hover／按下時改為半透明底色（原本不透明的 hover 底色蓋住箭頭）；2026-11-18 實拍滑鼠停在「動作與表情」上，箭頭看得到。
- 鍵盤與搜尋框（2026-11-18 用 MCP 的 `ui_mouse`／`ui_type`／`ui_focus` 走 Slate 實測）：點搜尋框後 `ui_focus` 顯示它在編輯；打「walk」字進框裡，鏡頭位置與角度不變；點 3D 視窗後字與編輯狀態都在；下拉選單開著按 Enter，DreamGUI 只把鍵盤焦點框移到第一項，不播動作（再按一次才選）；搜尋「01」選「Demo：坐姿 01」後搜尋字仍在。先前「打字時鏡頭動了」是用系統 SendKeys 模擬時看到的，走 Slate 的真實路徑沒重現。
- 只留 log、不做處理的兩件事（`ok.ReaderScreen:`）：鏡像面板重建（UMG 子項增減，重建會清掉其下文字框裡打的字）；看不見的 UMG 層拿到鍵盤焦點（DreamGUI 只在遊戲視窗有焦點時收鍵，見 `FDreamUISlateInputSource::IsKeyForThisWorld`）。2026-11-18 用 `ui_type`／`ui_mouse`／`ui_focus` 在打字時播動作、換抽屜、換分頁分類、換卡，兩者都沒發生，所以先前加的「保留字與焦點」「把焦點還給遊戲」處理已拿掉；log 出現了再處理。

## 已知限制

- 「屬性」頁（2026-11-18 修過，實拍對照）：下拉選單與說明文字改成單行，太長的用省略號截斷，數字欄延伸到「撤銷」按鈕前；項目名稱欄寬仍隨文字長短不同，數值欄起點沒有完全對齊。
- 卡片清單一頁最多列 400 張。資料夾裡的 OK 卡與原作 KK／KKS 角色卡（PNG 的 IEND 之後有 `KoiKatuChara` 標記）一起列出，選到哪張就用那張需要的開法（OK 卡用卡內資源，原作卡照「KKS 遊戲目錄卡片」的開法：有設遊戲目錄就讀其 mods，沒有就只用基礎庫）。讀不到或開不起來的卡留在清單上，卡名前標「開不了：」，原因顯示在通知框；不是角色卡的 PNG 不列（2026-11-18 實拍：30 張的測試資料夾 30 張全列，截斷資料的假卡標「開不了：」並顯示 `invalid face png length`，原作卡 kks_haruno_chika 載入完整）。
- 控制器的訊息（已加載3D、儲存結果、缺 mod 等）在 DreamGUI 開著時顯示在相機列下方的通知框（`ok.ReaderScreen` 輸出的 `notice=`），不再用引擎的 on-screen debug 訊息（它畫在左上角，壓在左欄上）；沒開 DreamGUI 的模式照舊用引擎訊息。
- 版面（2026-11-18 全分頁實拍後修正）：身高刻度尺在讀卡器 DreamGUI 介面下畫在角色左側、限在左右欄之間與相機列（及通知框）下方，不再畫進右欄或壓到卡名牌；分頁按鈕的底色跟著目前分頁（原本「編輯」永遠亮著）；卡片的「▶」後接不換行空白，長卡名在名字裡換行；只有按鈕的一排（三個以上，如「匯出這套服裝／穿上 OK 服裝／轉換服裝」）平分欄寬、字太長就縮小，不再超出欄寬。
- 卡片預覽圖片以 `WBP_OKImage` 顯示 UMG 圖片的貼圖，未逐張驗證；外觀選擇的縮圖格改用 `WBP_OKPickTile`（2026-11-18 眉毛、瞳孔、髮型、飾品各頁實拍都有縮圖）。
- 「設定 › 遊戲目錄」的「選資料夾…」沒有自動化驗證：它開的是 Windows 的資料夾對話框（`IFileOpenDialog`），MCP 碰不到，SendKeys 會被輸入法改字，UIA 也看不到對話框裡的資料夾欄與按鈕。手動驗證：按「選資料夾…」，選一個資料夾後按「選擇資料夾」，看 log 有 `ok.ReaderScreen: folder dialog picked <路徑>`、路徑欄顯示同一個路徑、下方狀態列出找到幾個 zipmod；按取消則 log 是 `folder dialog cancelled`、欄位不變。路徑欄直接打字與 `ok.ReaderScreen gameroot|library <資料夾>` 有自動驗證。
- 輸入法（IME）組字沒有測：文字框的中文是用剪貼簿貼上與 `ui_type` 送字元事件驗證的（`DreamGameViewportClient` 把平台字元轉給 DreamGUI），組字中的候選字窗、組字未確定時的顯示都沒驗證。
- `Config/DefaultEngine.ini` 的 `GameViewportClientClassName=DreamGameViewportClient` 是全域設定，每個模式都換成它。2026-11-18 對照驗證（同一份程式，一次用預設的 `GameViewportClient`、一次用 `DreamGameViewportClient`）：OK Studio 開地圖窗、Z 鍵隱藏／恢復 UI 兩邊一樣，log 的警告與錯誤逐行相同（CommonUI 的 viewport client 錯誤兩邊都有，是原本就在的）；街區（打包 stage 以 `-ini:` 套用）`obj list` 確認是 `DreamGameViewportClient`，走 Slate 的 W 鍵能走、除了隨串流範圍多寡浮動的材質 usage flag 警告外 log 逐行相同。兩邊的模擬滑鼠點擊結果也一樣（Studio 的 `ui_mouse`／`studio_mouse` 兩種設定都點不到按鈕、街區在游標鎖定時點不到），所以沒改成只在讀卡器啟動路徑帶 `-ini:`。

## 舊版控制項盤點與新版對照（2026-11-18 起，補完一項劃掉一項）

使用者回報新版找不到「眉毛、眼睛、髮型、飾品」的選材質／選模型。盤點舊版 UMG（`OKGalleryWidget.cpp` 與 `OKGallery*.cpp` 建的全部控制項）後，資料沒有少：舊版的「圖片式外觀選擇」和「顏色／飾品詳細編輯」新版都有鏡像，但全部塞在「衣服／配件」底下，一個下拉列出 600 多個目標（眉毛、瞳孔、髮型、60 個飾品欄 × 10 類都在同一個清單）。而「臉 › 眉毛／眼睛」只有滑桿，也沒有頭髮分類，使用者在該找的地方找不到。

資料來源一律照舊版：外觀目標與素材來自 `ok_appearance_request`（`catalog`／`thumbnails`／`apply`，Rust `appearance.rs` `targets()`＋`extra::targets_for`），詳細屬性來自 `properties`（`appearance/properties.rs`）。外觀目錄需要遊戲目錄（`<遊戲>/abdata`）；沒設時舊版、新版都只顯示「請先設定遊戲目錄」。e-cardload 確認（2026-11-18）：目錄由遊戲的 `abdata/list/characustom` 與 `mods/*.zipmod` 的 ChaList 建立，縮圖也從那裡抽；基礎庫 `base_v1` 沒有 ChaList 與縮圖來源，apply 還要求選到的 mod 真的在 `mods/` 裡，所以沒有只靠基礎庫的入口。首次建目錄約 260 秒，之後走 `Saved/AppearanceEditor/cache`。介面與欄位見 `Docs/READER_UI_APPEARANCE_API.md`（`catalog` 帶 `card` 時的 `current` 可直接標出每個目標目前的選擇，下一批改用它）。新版沒有自己造清單，只是**每頁篩選**：`UOKCharacterController::SetAppearanceScope`（目標鍵前綴）、`SetPropertyScope`（屬性鍵或名稱含的字），由 `UOKReaderScreen` 的頁面進入時設定。

| 分類 | 控制項 | 型別 | 舊版位置／資料來源 | 新版位置 | 狀態 |
|---|---|---|---|---|---|
| 眉毛 | 眉毛種類（257 種，縮圖） | 圖片格 | 外觀選擇 `eyebrow`（cat 406） | 臉 › 眉毛（滑桿下方） | ~~未補~~ 已補 |
| 眉毛 | 眉毛顏色（紅綠藍透明） | 數值＋色碼 | 詳細編輯 `face.eyebrowColor` | 臉 › 眉毛 | ~~未補~~ 已補 |
| 眼睛 | 左／右瞳孔種類（836 種）、左／右瞳孔漸層、眼白、上／下高光、上／下眼線 | 圖片格 | 外觀選擇 `pupil*`、`gradation*`、`eye_white`、`eye_hi_*`、`eyeline_*` | 臉 › 眼睛 | ~~未補~~ 已補 |
| 眼睛 | 瞳孔主要／次要顏色、漸層混合／位移／縮放、瞳孔位置大小、高光位置、眼線顏色與粗細、眼白顏色（51 項） | 數值＋色碼 | 詳細編輯 `face.pupil.*`、`face.hl*`、`face.white*`、`face.eyeline*` | 臉 › 眼睛 | ~~未補~~ 已補 |
| 頭髮 | 後髮、前髮、側髮、附加頭髮、頭髮光澤種類 | 圖片格 | 外觀選擇 `hair0..3`、`hair_gloss` | 頭髮 › 髮型（新分類） | ~~未補~~ 已補 |
| 頭髮 | 主要／髮根／髮梢／輪廓／髮飾顏色、不晃動、髮飾進階設定、頭髮物理 | 數值＋色碼＋下拉 | 詳細編輯 `hair.*`、名稱含「髮」的外掛列 | 頭髮 › 髮色與設定 | ~~未補~~ 已補 |
| 頭髮 | PBR／原作髮材質選擇 | 下拉 | **舊版讀卡器找不到這個控制**（`Source/OpenKoikatsu`、`DUI` 都沒有；只有 `KKPreviewActor.cpp` 內部的 shader 分支） | — | 待使用者指出在哪 |
| 飾品 | 先選欄位（配件欄 1–20、額外配件欄 21 起，這張卡共 60 欄），再選該欄的 10 類（髮飾…私密部位），再選模型（1819 種髮飾） | 下拉＋下拉＋圖片格 | 外觀選擇 `accessory{欄}_{類}`（舊版一個下拉 600 項） | 配件 › 飾品（`AccessorySlotChoice`，換欄位時類別保留） | ~~未補~~ 已補 |
| 飾品 | 新增飾品欄位 | 按鈕 | `OnAddAccessorySlot` | 配件 › 飾品（頁尾） | ~~未補~~ 已補 |
| 飾品 | 四層顏色、兩組位置／旋轉／縮放、不晃動、綁定骨架（文字＋下拉）、飾品物理 | 數值＋色碼＋下拉 | 詳細編輯 `accessory.parts.*`、額外欄 | 配件 › 飾品顏色與位置 | ~~未補~~ 已補 |
| 衣服 | 9 個部位、各 4 花紋 2 徽章、水手服／外套子部件 | 圖片格 | 外觀選擇 `clothes*`、`pattern*`、`emblem*`、`sub*` | 衣服 › 外觀選擇（只列衣服） | ~~未補~~ 已補 |
| 衣服 | 衣服顏色、花紋顏色等 | 數值＋色碼 | 詳細編輯 `clothes.*` | 衣服 › 顏色與設定 | ~~未補~~ 已補 |
| 臉／身體 | 鼻子種類（82 種）；唇線、唇彩；腮紅、痣；眼影；頭型、臉部皮膚細節、臉部彩繪；身體皮膚細節、曬痕、乳頭、陰毛、身體彩繪 | 圖片格＋相關顏色 | 外觀選擇 | 臉 › 鼻子／嘴巴／臉頰／眼睛／頭型與膚質（新頁）、身子 › 皮膚（新頁） | ~~暫放 配件 › 其他外觀~~ 已歸位 |
| 全部 | 不分頁的完整詳細編輯（2086 項） | 數值＋色碼＋下拉 | 詳細編輯 | 配件 › 全部屬性 | 已有 |
| 身子 | 骨骼分類下拉（骨骼調整：頭部…私密部位、全部）、「進階：X／Y／Z、位置與旋轉」勾選、各骨骼滑桿與左右側選擇 | 下拉、開關、滑桿 | `BoneCategoryCombo`、`BoneAxesCheck`、`BoneSliders` | 身子 › 骨骼（預設第一個骨骼分類；只鏡像該分類的列，換分類或勾選時重建） | ~~未補~~ 已補 |
| 身子 | 胸部柔軟度、胸部重量 | 滑桿 | `BoneSliders`（`BodyParameter`） | 身子 › 胸部 | ~~在骨骼頁~~ 已移到胸部 |
| 身子 | 腹部形變（啟用、預設、16 條滑桿） | 開關、下拉、滑桿 | `PregnancyBox`（只在分類「腹部形變」時顯示） | 身子 › 懷孕（進頁時選該分類；先前這頁是空的） | ~~未補~~ 已補 |
| 介面 | 編輯欄寬度、顯示字級 | 數字 | `EditorWidthInput`、`EditorFontInput` | 左欄拖拉寬度 | 刻意不做（只改看不見的 UMG 層） |
| 外觀選擇 | 「關閉」按鈕 | 按鈕 | `OnCloseAppearance` | 新版不鏡像（`AppearanceCloseButton`） | ~~待拿掉~~ 已拿掉 |
| 其他 | 表情、語音、眨眼、視線、嘴型、手勢、動作、影片動作、配對、物理、光影、穿著狀態、服裝、卡片牆、角色資訊、服裝卡 | 各種 | 各抽屜與欄 | 右欄抽屜、各分類頁 | 已有（先前各頁實拍） |
| 外觀選擇 | 沒有遊戲目錄時的說明與「前往 設定 › 遊戲目錄」 | 文字＋按鈕 | 舊版只寫「請先設定遊戲目錄」 | 每個選圖頁：清空選單與格子，寫明「要先在『設定 › 遊戲目錄』指定遊戲資料夾才有選項」與目前路徑哪裡不對，按鈕下一幀切到該頁（`AppearanceRootButton`、`OnWantGameRootSettings`） | 新增 |
| 外觀選擇 | 第一次建外觀目錄（約 260 秒）的進度 | 文字 | 舊版只寫「首次讀取需要較長時間」 | 「正在建立外觀目錄…第一次約需數分鐘，之後會快取…已 N 秒」，每秒更新（`TickAppearanceCatalogStatus`） | 新增 |
| 目前選擇 | 每個目標目前是哪一個（含卡片指名但本機沒裝的 mod） | 標記 | 舊版沒有 | 格子標 ▸ 並翻到那一頁；狀態列寫「目前是「名稱」」或「來源缺失」；飾品欄下拉附名稱（catalog 的 `current`） | 新增 |

新版的圖片格（`WBP_OKPickTile`，`DUI/Reader/Controls/PickTile.dui`）顯示舊版按鈕自己的縮圖與「類型 N · 原始遊戲／模組」，目前的選擇前面加 ▸；格子換行排（`PickGrid`，原本 32 格擠成一排）。舊版翻頁或套用後是「清空再放入同樣數量的新格子」，新版原本只比對數量、不重建，選取標記會停在舊格子上；改成連同子項是哪幾個一起比對（`FOKDreamMirrorPanel::Kids`）。

2026-11-18 實拍（同一張卡 `E:\OpenKoikatsu\Content\CharacterCards\CrowdAPNG\C000.png`，遊戲目錄暫時指向 `D:\XKoikatuSunshine` 測完已還原）：新版與 `-LegacyReader` 的眉毛種類都是 257 項、左瞳孔種類 836 項、配件欄 1 髮飾 1819 項，縮圖順序相同；新版按「類型 2」眉毛後角色重新載入、右眼上方出現粗眉（原本細眉被瀏海擋住），按「類型 3」左瞳孔後格子標 ▸、log 有 `target: pupil0` 的 apply。這張卡的瞳孔外觀換了看不出差別（推測卡上的眼睛材質覆寫蓋過瞳孔種類），舊版同樣路徑，待 e-cardload 確認資料面。

第二批（2026-11-18 實拍同卡）：骨骼頁預設「骨骼調整：頭部」8 列、266 FPS，勾「進階」後重建成 X／Y／Z 分軸列；懷孕頁顯示啟用、預設與 16 條滑桿；從骨骼頁切到懷孕、胸部都正常，胸部頁有胸部柔軟度／重量；飾品頁先選「配件欄 3」，類別自動成「配件欄 3：髮飾」；鼻子頁 82 種。**骨骼頁不要一次鏡像全部骨骼列**：第一版把幾百列（含收起的）全建出來，建頁卡 1.8 秒、DreamGUI 報 `ExpandTexture ... Maximum texture size is 16,384`，接著切到別頁時銷毀這些控制項讓遊戲卡死好幾分鐘；現在只鏡像該分類看得到的列（`FGroup::bShownOnly`），分類或勾選改變時重建（`FGroup::Signature`）。手動選「骨骼調整：全部」仍會建全部列，盡量別選。

### 崩潰排查（2026-11-19）

- 縮圖背景解碼不會懸空：
  - 背景只拿三樣東西：路徑複本、遊戲執行緒先取得的 ImageWrapper 模組指標、清單自己的取消旗標，不碰任何 UObject。
  - 先看 IHDR，超過 2048×2048 不解碼。
  - 清單重建時舉起取消旗標並換 generation，在途的解碼不回寫。
  - 回寫前檢查索引。
- **GPU PageFault（已修）**：
  - 症狀：開發版讀卡器反覆切「卡片來源」（街頭女主角卡片／APNG 內嵌資源卡片），再加 `ok.ReaderScreen scroll 0..1` 快速捲動，約一分多鐘後當掉。重現兩次，第二次沒點任何卡。log 是 `LogD3D12RHI: Error: PageFault`，Aftermath 寫 `fragment_02` MMU fault。
  - 原因：DreamGUI 的圖片把貼圖放進畫布的繪製幾何（`UIGeometry->Texture`）。縮圖貼圖被放開後交給 GC，但畫布已建好的繪製資料不一定在那之前重建，GPU 讀到已釋放的貼圖。先前「放開後保留 3 秒」不夠，同一組測試照樣當。
  - 修正：縮圖改成畫面自己擁有的貼圖池（`ThumbPool`，固定 288×402）。格子放開的貼圖回到池裡，下一張用 `UpdateTextureRegions` 重填。讀卡器存活期間沒有任何縮圖貼圖被回收。
  - 驗證：同一組壓力（切來源＋捲動）跑 10 輪約 4.5 分鐘，含 3 次 `obj gc`，再加點卡跑 8 輪約 5 分鐘，都沒當。log 的 `: Error:` 只有原本就有的 CommonUI 那一行。縮圖重複使用後顯示正確，沒有錯圖。
  - 對照開關：`ok.ReaderThumbs 0` 不解碼縮圖。
  - 外觀選擇的縮圖格（控制器的 `AppearanceTextures`，換頁時重建）是同一類風險，還沒改。
- 使用者那筆 CPU 的 `EXCEPTION_ACCESS_VIOLATION`（`Foreground Worker #0`）沒有拿到 dump，沒有直接重現。上面兩項修正都針對這條路徑。

MCP 用的新指令：`ok.ReaderScreen press <文字> [#N]`（按目前顯示、文字相同（找不到再找包含）的第 N 個控制項，等同滑鼠點）、`ok.ReaderScreen scroll <0–1>`（左欄捲到該位置，給長頁截圖）。

## 「沒按滑鼠鍵，視野也會動」的排查（2026-11-18）

使用者回報讀卡器的視野在滑鼠左鍵沒按住時會跟著滑鼠動。查過的方向與結論：

| 測什麼 | 怎麼測 | 結論 |
|---|---|---|
| 相機只在有按鍵時才轉 | 程式：`AOpenKoikatsuPlayerController::UpdateCameraMouse` 只在 `FOKCameraDrag::Owned`（按鍵從 3D 視窗上按下）時呼叫 `OrbitMouse`；按鍵狀態取自 `FSlateApplication::GetPressedMouseButtons()` | 沒有按鍵就不會轉 |
| 換成 `DreamGameViewportClient`、DreamGUI 接管 Slate 輸入後按鍵狀態會不會卡住 | 引擎碼：Slate 在輸入前處理器（DreamGUI）之前就更新 `PressedMouseButtons`，失焦時清空；DreamGUI 不自己產生滑鼠按鍵事件；`DreamGameViewportClient` 的滑鼠事件原樣轉交 | 這兩項改動不會讓按鍵卡住 |
| 頭／眼跟游標 | `EyeMode` 預設 0（眼睛面向前方），1 才跟游標，2 跟鏡頭；頭只會跟鏡頭（`bHeadLookFollowCamera`），不跟游標 | 預設沒有任何東西跟游標 |
| 開發版（編輯器 `-game`） | MCP `ui_mouse` 走 Slate：沒按鍵移動、在 3D 點一下、點左欄按鈕、點右欄抽屜後再移動，鏡頭參數都不變；3D 上拖曳才轉 | 重現不出來 |
| 打包版 `Studio-20261118e` | 同上；沒按鍵移動前後 3D 區 0 像素差（鏡頭、頭、眼都沒動），左鍵拖曳 yaw 0→-40 | 重現不出來 |
| 真實滑鼠 | Windows `SendInput` 送出的按鍵與相對位移都沒進到遊戲（Slate 看不到按下、游標也不動） | MCP 沒辦法驅動真實滑鼠，這條沒有測到；不能當成「沒問題」的證據 |

下次再遇到時，在主控台（或 MCP `ui_exec`）下 `ok.ReaderScreen look`，一行就能定位：

- `look eye_mode=… eye_tracking=… eye_follows_camera=… gaze=… head_follows_camera=… buttons=…`：眼睛在跟誰（`eye_mode=1(cursor)` 就是眼睛跟游標）、頭是否跟鏡頭、Slate 現在認為按著哪些滑鼠鍵（沒按卻不是 `none` 就是按鍵狀態卡住）。
- `camera yaw=… pitch=… distance=… focus=… last_change=…`：鏡頭最後一次是誰改的（`mouse drag (buttons N)`、`mouse wheel`，或不是滑鼠：鏡頭列按鈕、MCP、載入）、幾秒前、當時 Slate 認為按著的鍵。
