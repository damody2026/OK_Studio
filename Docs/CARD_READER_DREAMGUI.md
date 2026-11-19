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
- **讀卡器的物理預設就是「原始 Verlet」**（使用者 2026-11-18；啟動旗標 `-OKPhysics=verlet` → `OKPhysXSecondary.Enabled 0`，在建選單之前套用，`OKCharacterController::ApplyStartupPhysicsBackend`）。2026-11-19 實機再確認：啟動日誌 `Card reader physics: verlet (OKPhysXSecondary.Enabled 0, Backend -1)`、選單值「物理：原始 Verlet」。同一張卡（C011，九條尾巴＋外套，走路動作）切到「PhysX 5.11」再切回來：原始 Verlet 下尾巴與外套自然垂散、PhysX 下收得較緊，切回來恢復，兩邊都沒有穿模或爆炸；畫面右下角的讀數 48 FPS／20.7 ms（Verlet）對 99 FPS／10.1 ms（PhysX），**原始 Verlet 這張卡大約慢一倍**（單次讀數，不是基準測試）。**不要為了讀卡器去改 `Tools/ok-extract/src/px.rs` 的 `PhysicsComponent::default_solver()`**：那是全域設定，街區、一對一與 Studio 都吃它（`dbone.rs`、`okphysics.rs`），而且 host solver 關著時它根本不生效（`solve_batch` 直接回 false，每條鏈都走 ok-extract 自己的 DynamicBone 更新，也就是原始 Verlet）；它只有在選「依元件（卡片／預設）」時才有影響。
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

| 分類 | 控制項 | 型別 | 舊版位置／資料來源 | 新版位置 | 狀態 | MCP 操作（路徑／指令） |
|---|---|---|---|---|---|---|
| 眉毛 | 眉毛種類（257 種，縮圖） | 圖片格 | 外觀選擇 `eyebrow`（cat 406） | 臉 › 眉毛（滑桿下方） | ~~未補~~ 已補 | `press 臉›眉毛›<種類名>`（格子以顯示文字命名，同名加 #N）；未逐項實測 |
| 眉毛 | 眉毛顏色（紅綠藍透明） | 數值＋色碼 | 詳細編輯 `face.eyebrowColor` | 臉 › 眉毛 | ~~未補~~ 已補 | `ui_set` 改原 UMG 欄位；路徑 `臉›眉毛›<欄位>›Input`；未逐項實測 |
| 眼睛 | 左／右瞳孔種類（836 種）、左／右瞳孔漸層、眼白、上／下高光、上／下眼線 | 圖片格 | 外觀選擇 `pupil*`、`gradation*`、`eye_white`、`eye_hi_*`、`eyeline_*` | 臉 › 眼睛 | ~~未補~~ 已補 | `press 臉›眼睛›<種類名>`；換頁 `臉›眼睛›下一頁`（第二組是 `下一頁 #2`）；實測路徑存在 |
| 眼睛 | 瞳孔主要／次要顏色、漸層混合／位移／縮放、瞳孔位置大小、高光位置、眼線顏色與粗細、眼白顏色（51 項） | 數值＋色碼 | 詳細編輯 `face.pupil.*`、`face.hl*`、`face.white*`、`face.eyeline*` | 臉 › 眼睛 | ~~未補~~ 已補 | `ui_set` 原 UMG 欄位；未逐項實測 |
| 頭髮 | 後髮、前髮、側髮、附加頭髮、頭髮光澤種類 | 圖片格 | 外觀選擇 `hair0..3`、`hair_gloss` | 頭髮 › 髮型（新分類） | ~~未補~~ 已補 | `press 頭髮›髮型›<種類名>`；未逐項實測 |
| 頭髮 | 主要／髮根／髮梢／輪廓／髮飾顏色、不晃動、髮飾進階設定、頭髮物理 | 數值＋色碼＋下拉 | 詳細編輯 `hair.*`、名稱含「髮」的外掛列 | 頭髮 › 髮色與設定 | ~~未補~~ 已補 | `ui_set` 原 UMG 欄位；未逐項實測 |
| 頭髮 | PBR／原作髮材質選擇 | 下拉 | **舊版讀卡器找不到這個控制**（`Source/OpenKoikatsu`、`DUI` 都沒有；只有 `KKPreviewActor.cpp` 內部的 shader 分支） | — | 待使用者指出在哪 | 不適用（不存在） |
| 飾品 | 先選欄位（配件欄 1–20、額外配件欄 21 起，這張卡共 60 欄），再選該欄的 10 類（髮飾…私密部位），再選模型（1819 種髮飾） | 下拉＋下拉＋圖片格 | 外觀選擇 `accessory{欄}_{類}`（舊版一個下拉 600 項） | 配件 › 飾品（`AccessorySlotChoice`，換欄位時類別保留） | ~~未補~~ 已補 | `press 配件›飾品›<欄位>`；未逐項實測 |
| 飾品 | 新增飾品欄位 | 按鈕 | `OnAddAccessorySlot` | 配件 › 飾品（頁尾） | ~~未補~~ 已補 | `press` 按鈕文字；未逐項實測 |
| 飾品 | 四層顏色、兩組位置／旋轉／縮放、不晃動、綁定骨架（文字＋下拉）、飾品物理 | 數值＋色碼＋下拉 | 詳細編輯 `accessory.parts.*`、額外欄 | 配件 › 飾品顏色與位置 | ~~未補~~ 已補 | `ui_set` 原 UMG 欄位；未逐項實測 |
| 衣服 | 9 個部位、各 4 花紋 2 徽章、水手服／外套子部件 | 圖片格 | 外觀選擇 `clothes*`、`pattern*`、`emblem*`、`sub*` | 衣服 › 外觀選擇（只列衣服） | ~~未補~~ 已補 | `press 衣服›外觀選擇›<種類名>`；未逐項實測 |
| 衣服 | 衣服顏色、花紋顏色等 | 數值＋色碼 | 詳細編輯 `clothes.*` | 衣服 › 顏色與設定 | ~~未補~~ 已補 | `ui_set` 原 UMG 欄位；未逐項實測 |
| 臉／身體 | 鼻子種類（82 種）；唇線、唇彩；腮紅、痣；眼影；頭型、臉部皮膚細節、臉部彩繪；身體皮膚細節、曬痕、乳頭、陰毛、身體彩繪 | 圖片格＋相關顏色 | 外觀選擇 | 臉 › 鼻子／嘴巴／臉頰／眼睛／頭型與膚質（新頁）、身子 › 皮膚（新頁） | ~~暫放 配件 › 其他外觀~~ 已歸位 | `press <分類›二級›種類名>`；未逐項實測 |
| 全部 | 不分頁的完整詳細編輯（2086 項） | 數值＋色碼＋下拉 | 詳細編輯 | 配件 › 全部屬性 | 已有 | 只能 `ui_set`（2086 項）；未逐項實測 |
| 身子 | 骨骼分類下拉（骨骼調整：頭部…私密部位、全部）、「進階：X／Y／Z、位置與旋轉」勾選、各骨骼滑桿與左右側選擇 | 下拉、開關、滑桿 | `BoneCategoryCombo`、`BoneAxesCheck`、`BoneSliders` | 身子 › 骨骼（預設第一個骨骼分類；只鏡像該分類的列，換分類或勾選時重建） | ~~未補~~ 已補 | 下拉與勾選 `ui_set`；換頁時頁面重建，路徑跟著變；未逐項實測 |
| 身子 | 胸部柔軟度、胸部重量 | 滑桿 | `BoneSliders`（`BodyParameter`） | 身子 › 胸部 | ~~在骨骼頁~~ 已移到胸部 | `ui_set`；路徑 `身子›胸部›<名稱>›Slider`；未逐項實測 |
| 身子 | 腹部形變（啟用、預設、16 條滑桿） | 開關、下拉、滑桿 | `PregnancyBox`（只在分類「腹部形變」時顯示） | 身子 › 懷孕（進頁時選該分類；先前這頁是空的） | ~~未補~~ 已補 | `ui_set`；未逐項實測 |
| 介面 | 編輯欄寬度、顯示字級 | 數字 | `EditorWidthInput`、`EditorFontInput` | 左欄拖拉寬度 | 刻意不做（只改看不見的 UMG 層） | `ok.ReaderScreen width <px>`（新版用拖拉取代）；實測 |
| 外觀選擇 | 「關閉」按鈕 | 按鈕 | `OnCloseAppearance` | 新版不鏡像（`AppearanceCloseButton`） | ~~待拿掉~~ 已拿掉 | 不適用（新版沒有） |
| 其他 | 表情、語音、眨眼、視線、嘴型、手勢、動作、影片動作、配對、物理、光影、穿著狀態、服裝、卡片牆、角色資訊、服裝卡 | 各種 | 各抽屜與欄 | 右欄抽屜、各分類頁 | 已有（先前各頁實拍） | 右欄抽屜：`press 抽屜›<標題>` 展開，按鈕 `press <抽屜›名稱>`，滑桿等 `ui_set`；EyeMode `press 動作與表情›眼睛：面向前方` 實測三模式循環 |
| 外觀選擇 | 沒有遊戲目錄時的說明與「前往 設定 › 遊戲目錄」 | 文字＋按鈕 | 舊版只寫「請先設定遊戲目錄」 | 每個選圖頁：清空選單與格子，寫明「要先在『設定 › 遊戲目錄』指定遊戲資料夾才有選項」與目前路徑哪裡不對，按鈕下一幀切到該頁（`AppearanceRootButton`、`OnWantGameRootSettings`）；還沒載入角色時選圖頁改說「要先選卡並載入3D」，載入後自動重建 | 新增，2026-11-19 實拍 | `press` 頁上的「前往 設定 › 遊戲目錄」按鈕；實測（2026-11-18） |
| 外觀選擇 | 第一次建外觀目錄（約 260 秒）的進度 | 文字 | 舊版只寫「首次讀取需要較長時間」 | 「正在建立外觀目錄…第一次約需數分鐘，之後會快取…已 N 秒」，每秒更新（`TickAppearanceCatalogStatus`） | 新增，2026-11-19 實拍（快取命中約 3 秒） | 唯讀文字，`ok.ReaderScreen controls` 看得到 |
| 目前選擇 | 每個目標目前是哪一個（含卡片指名但本機沒裝的 mod） | 標記 | 舊版沒有 | 格子標 ▸ 並翻到那一頁；狀態列寫「目前是「名稱」」或「來源缺失」；飾品欄下拉附名稱（catalog 的 `current`） | 新增，2026-11-19 實拍：眉毛停在 3/9 頁、類型 503 有標記；配件欄 1 寫「[SolityL]Elysia_Hair」、類別自動是頭飾、第 128 頁 | 唯讀標記（▸），`controls` 看得到；`reader_call` 的 `catalog` 回 `current` |

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

### 打包版才出現的問題（2026-11-19）

- **CPU 蒙皮讀回當機**：鏡頭列的構圖原本用 `FrameCurrentPose`（`GetCPUSkinnedVertices`），打包版在 render thread 的 `FSkeletalMeshObjectCPUSkin::CacheVertices` 存取違規。改用 `AKKPreviewActor::FrameCurrentPoseRealtime`：只用目前的關節與邊界框。
- **Disregard for GC**：DreamGUI 字型換掉的圖集曾用 UPROPERTY 保留；打包版的預設字型在 disregard-for-GC 池，引用沒有 root 的物件，第一次 GC 就 fatal。改成和目前圖集一樣 AddToRoot，最多留 4 張，字型釋放時一起解除。
- **新控制項要重新 cook**：`WBP_OKCardTile`、`WBP_OKPickTile` 是 2026-11-18 晚上才加的，用 `--skip-cook` 沿用更早 cook 的 base 打出來的 stage 沒有這兩個資產（log：`Reader control WBP_OKCardTile missing`），卡片牆與圖片格是空的。加了 `/Game/UI/Reader` 下的資產後要重新 cook，並換新的 `--base-dir`。
- **缺 DreamGUI global shader 的 base**：沒有實測。降級路徑會改開舊版、在畫面與 log 寫出重建指示，不會 Fatal。

### 換資源後立刻解除 root／釋放：DreamGUI 盤點（2026-11-19）

| 地方 | 做法 | 結論 |
|---|---|---|
| 交給繪製的所有貼圖（圖片、精靈圖頁、字型圖集、縮圖、render target） | `UDreamCanvas::DrawTextureHolds`：繪製資料用到的貼圖持有強引用，不再用之後再留 8 幀 | 這是通則，GC 不會在畫布還拿著舊繪製資料時回收任何一張 |
| 字型圖集擴張（`RenewFontTexture`） | 舊圖集保持 root，留最近 4 張 | 已修（同上一節） |
| 動態／靜態精靈圖集頁（`UpdatePermanentHolderRoots`、`ReleasePermanentHolderRoots`） | 只替 disregard-for-GC 池裡的持有者 root 頁面；頁面本身由圖集的陣列持有 | 換頁後舊頁的繪製由 `DrawTextureHolds` 保住，不用改 |
| 讀卡器縮圖 | 畫面自己的貼圖池，不交給 GC | 已修 |
| 網格、uniform buffer（`DreamUIMeshComponent`、`DreamUIGizmoMesh`、render target 幾何） | 在 render thread 釋放，或以共享指標由最後一個持有者釋放 | 沒有提前釋放 |
| 小工具與 tween（`MarkAsGarbage`） | 標垃圾，不是直接 `ConditionalBeginDestroy` | 沒有提前釋放 |

GPU PageFault 的真正觸發是 D3D12 貼圖池整理（`d3d12.VRAMTexturePoolDefrag`），它搬動貼圖記憶體，不是 GC 回收。e-cardload 在 log 盤點時抓到的 `DXGI_ERROR_DEVICE_HUNG`（`fragment_02` MMU fault，停在 `FDreamUIRenderer::PostRenderView_RenderThread`，`Docs/CARD_READER_LOG_TRIAGE.md` 第 1 節），發生在讀卡器關掉整理之前的版本，症狀與位置都和這條相同。關掉整理後同類壓力沒有再重現；是哪一個 draw 還拿著被搬走貼圖的舊綁定，還沒找到。

### 開卡失敗時的畫面（2026-11-19）

使用者回報「換角色時套用上一個角色的物理、mesh 變形」：開卡失敗時舊模型留在畫面，但名牌、滑桿與選取已經是新卡，新卡的身形驅動舊模型。現在換別張卡失敗就退掉舊模型，只留錯誤訊息與卡片上的「開不了」；同一張卡換服裝或外觀失敗時才放回舊模型（`UOKCharacterController::RestoreStaleAfterFailedLoad`）。實拍：`E:\OpenKoikatsu\Saved\Reports\reader-failload-20261119\after-fail.png`。

### MCP 能不能操作（2026-11-19）

只要有控制項 MCP 碰不到，那條路徑上的 bug 就測不到。以控制項的種類列：

| 控制項 | MCP 怎麼操作 | 實測 |
|---|---|---|
| 分頁、分類、二級選單、左欄寬度、捲動 | `ok.ReaderScreen tab／category／sub／width／scroll` | 完整驗證腳本逐頁走過 34 頁 |
| 卡片牆的卡片 | `ok.ReaderScreen card <N>`（照清單順序），或 `press <名字>` | 30 張逐張開 |
| 鏡頭列、圖片格、抽屜標題、「人物編輯」按鈕區、遊戲目錄頁 | `ok.ReaderScreen press <文字> [#N]` | 實測 |
| 「眼睛：面向前方／看鼠標／看 Camera」（EyeMode，在「動作與表情」抽屜） | `press 動作與表情›眼睛：面向前方`（路徑），或目前顯示的完整文字；按一次換下一個模式，文字跟著變 | 2026-11-19 實測三個模式循環 |
| 滑桿、數值、色碼、下拉、勾選（鏡像自 UMG） | `ok.ReaderScreen set <路徑> = <值>`：滑桿給數字（UMG 滑桿本身的值，例如縮放 1.6 顯示成 160，超出範圍回報 `out of range`），勾選給 `on／off／1／0`，下拉給選項文字或序號，輸入框給文字；等同人去改。勾選也能 `press`（切換）。`ui_set` 改 UMG 原控制項也照樣可用 | 2026-11-19「臉›眼部縮放2」實測滑桿、下拉（雙側／左／右）、勾選（press 與 set）、超出範圍 |
| 3D 視窗的滑鼠（拖曳轉鏡頭、眼睛跟游標） | `ui_mouse`（走 Slate） | 實測；真實 `SendInput` 進不了遊戲，只能用 `ui_mouse` |
| 只在 DreamGUI 有、沒有 UMG 來源的控制 | 都是按鈕，走 `press` | 新增時要能被 `press` 找到 |

**控制項路徑**：每個顯示中的控制項有一條路徑，`ok.ReaderScreen controls [篩選]` 列出全部：

- 區域或抽屜，或「分類›二級選單」，再接控制項。例如 `動作與表情›眼睛：面向前方`、`臉›眼睛›上眼瞼形狀1›重置`、`鏡頭›全身`、`抽屜›選擇動畫`、`分類›臉`、`卡片›Alice`。
- 滑桿列裡的控制項前面加上該列的標籤。
- 沒有文字、或文字是數值的控制項用種類命名（`Slider`、`Label`、`Input`…），數值會變，不拿來當名字。
- 同一路徑的第二個以後加 ` #2`、` #3`，照畫面順序。

`press` 與 `set` 的規則（兩者找控制項的方式相同）：

- 文字帶 `›` 就照路徑比對，否則照顯示文字比對。先找完全相同的，沒有才找包含的。
- 符合的超過一個時不按，回報 `ambiguous` 並列出各候選的路徑；要指定其中一個，用路徑或 `#N`。
- 只有一個完全相同、但另有控制項包含這段文字時，照樣按下那一個，並列出另外那些的路徑。例如 `press 眼睛` 按的是「臉›眼睛」，同時列出 `動作與表情›眼睛：面向前方`。

### 控制稽核：舊版 UMG 的每個控制項新版有沒有（2026-11-19）

`ok.ReaderScreen audit`：逐頁打開新版畫面的 36 頁，記下每頁鏡像的 UMG 控制項，再把舊版 controller 的 UMG 樹裡每個能操作的控制項（按鈕、滑桿、勾選、下拉、輸入框、數字框）對一遍；結果也寫到 `Saved/Reports/reader-control-audit.txt`。骨骼頁只畫目前選的骨骼分類，其他分類的列算「切換分類可達」。打包 stage `EFork1119y`、開了一張卡之後跑（`E:\OpenKoikatsu\Saved\Reports\reader-control-audit-20261119.txt`）：

| 結果 | 數量 |
|---|---|
| 舊版能操作的控制項 | 4877 |
| 新版有鏡像（都能用路徑按到、`set` 設值） | 4866 |
| 新版自己畫（抽屜標題、選圖格、選圖面板的「關閉」、卡片牆） | 6 |
| 新版用別的方式做 | 4 |
| **缺口** | **1 → 0**（顯示字級，已補） |

新版用別的方式做的四個：

| 舊版 | 新版 |
|---|---|
| 新增飾品欄位 | 配件›飾品 頁上畫面自己的「新增飾品欄位」按鈕 |
| 圖片式外觀選擇 | 選圖頁（臉、頭髮、身子›皮膚、衣服›外觀選擇、配件）進入時自動打開 |
| 顏色／飾品詳細編輯 | 顏色與設定、飾品顏色與位置、全部屬性頁進入時自動打開 |
| 編輯欄寬度（`EditorPanelWidth`） | 左欄右緣的拖曳把手、`ok.ReaderScreen width` |

**唯一的缺口：顯示字級（`EditorFontSize`，6–24），已補（2026-11-19）**。舊版是 UMG 的字級，新版放在 **設定／介面 › 介面**（鏡像同一個數字框，存在同一個 `GameUserSettings.ini` 的 `[OpenKoikatsu.EditorDisplay] PanelFontSize`，兩版共用）。新版把它當成整個畫面的縮放：預設 8 是設計大小，`字級÷8`，夾在 0.75（6）到 1.5（12 以上；再大兩欄之間就沒有 3D 視圖了）。畫布的參考解析度跟著改成 `1920×1080÷縮放`，拖曳把手、HUD 避開兩欄、滑鼠在不在 UI 上的判斷都乘上同一個縮放。MCP：`set 設定／介面›介面：顯示字級 = 10`。

**同一頁有兩個以上同名的短名（57 組）**：用短名 `press` 會回報 ambiguous 並列出路徑，路徑一律唯一，所以都能操作。大多是預期的（每列各自的「重置」、選圖與屬性兩組「上一頁／下一頁」、遊戲目錄與卡片資料夾各一組「選資料夾…／還原預設」）。值得記的兩個：鏡頭列的「全身」「腿部」和 身子 的二級選單同名；卡片牆有兩張都叫 Alice 的卡（用 `ok.ReaderScreen card <N>` 或路徑的 ` #2`）。

### 決定：舊版 UI 留著，不刪程式碼（2026-11-19，協調者裁示）

- **使用者「以後不要再出現舊版ui」已經達成**：新版是預設，舊版只有明確帶 `-LegacyReader` 才會出現，正常操作看不到。
- **保留作為 PageFault 的診斷對照**：真因還沒找到。「帶 `-LegacyReader` 30 張不當」正是證明 DreamGUI 是必要條件的那一組；對照組刪掉，下次再出事就沒有比較的基準。
- **真因解掉之後才拆**，照下面的前置清單做。這不是忘了拆。

### 廢掉舊版 UI 的前置條件（2026-11-19，只列清單，未動手）

稽核缺口已清零（顯示字級補上）。使用者說「以後不要再出現舊版ui」，但**要等 PageFault 有結論才拆**：`-LegacyReader` 是目前唯一的對照組（帶它 30 張不當）。

**先講清楚「舊版 UI」能拆到哪裡**：新版畫面是**鏡像**，不是另寫一套。每個控制項的 `Source` 指向 `UOKCharacterController` 的 UMG 控制項，數值、事件、存檔都走那棵 UMG 樹。所以能拆的是「讓舊版顯示出來的路徑」；UMG 控制項本身是資料層，要留著（隱形、不可點）。把資料層也拿掉，等於做先前否決的「參數快照化」重構，不在這次範圍。

要拆的地方：

| # | 位置 | 現在做什麼 | 拆掉後 |
|---|---|---|---|
| 1 | `OKGalleryWidget.cpp` 1050–1054 | 沒帶 `-LegacyReader` 才開新版；帶了就顯示 UMG | 一律開新版 |
| 2 | `OKReaderScreen.cpp` `Open` 開頭兩個退路 | DreamGUI 全域 shader 不在（舊 base cook 的 stage）、`ReaderScreen.dui` 類別找不到時回 `nullptr`，畫面退回 UMG | 改成顯示錯誤並說要重建什麼，不再退回舊版；先確認所有發佈中的 stage／package 的 base 都有 DreamGUI shader |
| 3 | `Tools/run_card_reader_development.lua` 24、133–148 行 | `--legacyreader` 開關；`-ParallelRDG` 的判斷也看它 | 移除開關；RDG 那段照 PageFault 的結論改 |
| 4 | `Tools/ok-game-mcp/src/reader.rs` 16 行 | `reader_launch` 的說明提到 `-LegacyReader` | 改說明（要重編 ok-game-mcp） |
| 5 | `if(ReaderScreen)` 的分支：`OKGalleryWidget.cpp` 972、1094、1708、2542；`OKHUD.cpp` 67；`OKCharacterMCP.cpp` 176；`OKInteractionMode.cpp`、`OKGalleryOkStudio.cpp` 的 RDG 切換 | 有新版走新版，沒有走 UMG | `ReaderScreen` 必定存在，`else` 那支（`AddOnScreenDebugMessage` 當通知、整個視窗當 3D 範圍、UMG 可點）可刪 |
| 6 | 文件 | `AGENTS.md`、本文件等提到 `-LegacyReader` 對照 | 改寫 |

**還依賴舊版 gallery 的東西（拆完要確認不壞）**：

- **Automation 測試**：`Source/OpenKoikatsu/Tests` 54 個檔案中，34 個直接用 `UOKGalleryWidget`／`UOKCharacterController`。其中 15 個碰可見性、幾何或 Slate 輸入（例如 `OKCameraControls.spec.cpp`、`OKCardScrollAudit.cpp`、`OKPaintGalleryAudit.cpp`），假設 UMG 在畫面上、可以點；新版下 UMG 是 `HitTestInvisible`。拆之前要逐一跑過，標出哪些要改成走 `ok.ReaderScreen press/set`。
- **遊戲 MCP 的 `ui_widgets`／`ui_press`／`ui_set`**：對的是 UMG 層，新版下照樣能用（1 對 1 的「離開（回到讀卡）」就是這樣按的）。拆掉 #1 之後行為不變，但「畫面上看到的」和「`ui_widgets` 列出的」是兩棵樹，說明要寫清楚，或改成優先走 `reader_call`／`ok.ReaderScreen`。
- **Lua 工具**：`Tools/reader_jump_check.lua`、`Tools/reader_package_sweep.lua` 透過 MCP 操作讀卡器，要在新版下跑一次確認。
- **1 對 1（`bInteractionOnly` 的 `UOKCharacterController`）**：從讀卡器或街區進去，H 面板與互動控制是 UMG。那是 1 對 1 的介面，不是讀卡器舊版 UI，不在這次拆除範圍；若「不要舊版 UI」也包括它，那是另一件事。
- **OK Studio**：自己的 UI，不依賴讀卡器的 UMG 顯示。

**拆除順序（建議）**：PageFault 結案 → 跑一次 Automation，列出依賴可見 UMG 的測試並改掉 → 處理 #2 的退路 → #1、#3、#4、#5 一次改掉 → 兩個目標建置 → `ok.ReaderScreen audit` 再跑一次，確認仍是 0 缺口。

## 臉›眼部縮放2（2026-11-19）

原遊戲 ABMX 的眼球骨骼頁（`FaceEyes2`：`cf_J_Eye_tz` 雙眼球、`cf_J_Eye_rz_L／R` 眼球 縮放 1、`cf_J_Eye_tx_L／R` 眼球 縮放 2）。內容就是「身子›骨骼」選「骨骼調整：眼球」時的那幾列，但頁面固定在這個分類、不顯示分類下拉：一般模式 3 列（縮放＋左右選擇＋重置），勾「進階：X／Y／Z、位置與旋轉」後 27 列（各軸縮放、位移、旋轉）。寫入走原本的骨骼滑桿（`OnBoneChanged`），和讀卡器其他骨骼頁相同。

實測（打包 stage `EFork1119q`，第 1 張卡，`E:\OpenKoikatsu\Saved\Reports\reader-eyebones-20261119b\results.txt`）：

| 項目 | 結果 |
|---|---|
| 頁面與控制項路徑 | `臉›眼部縮放2›雙眼球 縮放›Slider` 等，一般 3 列、進階 27 列；左右成對的列第二個帶 ` #2` |
| 雙眼球 縮放 = 1.6 | 兩眼一起放大（截圖 `E:\OpenKoikatsu\Saved\OKControl\shots\66248-0002.png`） |
| 眼球 縮放 1：雙側／左／右 0.5 | 雙側兩眼變小、左或右只變一邊；和雙眼球 1.6 疊加也正確（`66248-0006.png`、`66248-0007.png`、`66248-0009.png`、`66248-0010.png`） |
| 超出範圍 `= 9` | 不改，回報 `out of range 0..3` |
| 進階勾選 | `press` 切換、`set … = off` 關掉，列數 3 ↔ 27 |
| 重置 | 三列重置後回到原樣（`66248-0005.png`） |
| 切回「身子›骨骼」「臉›眼睛」 | 骨骼頁照舊有分類下拉；眼睛頁回到原遊戲參數 |
| log | 0 個 Error／Fatal／ensure |

有一張截圖（`66248-0003.png`，雙眼球 1.6 後第一次把眼球 縮放 1 設成左 0.5）另一隻眼的眼皮看起來被拉開，同樣步驟再做三次都沒出現，未能重現。

## 完整驗證結果（2026-11-19）

腳本逐頁切換（每頁截圖）、照清單逐張開卡（等 log 的 `OK load3d result`）、每 5 張下一次 `obj gc`、六輪「切卡片來源＋隨機捲動＋點卡」壓力，最後檢查行程還在、log 的 `: Error:`。MCP 一律用 `OK_GAME_PID` 鎖住自己的行程。遊戲目錄暫時指向 `D:\XKoikatuSunshine`（測完還原）。

| 項目 | 怎麼驗 | 開發版（編輯器 `-game`） | 打包版（stage `EFork1119g`，新 cook 的 `BaseE1119A`） |
|---|---|---|---|
| 每個分頁與控制項 | 34 頁逐頁切換、截圖 | 34／34 通過 | 32／34；「身子›全身」「身子›腿部」用 `press` 時和鏡頭列同名，被判成有歧義而不按（預期行為，腳本已改用 `category`／`sub`，第二輪 34／34） |
| 30 張卡逐張開 | `ok.ReaderScreen card N` ＋「載入3D」，等 `OK load3d result ok=1` | 30／30，每張 1–4 秒 | 30／30 |
| 切卡片來源與捲動 | 六輪切來源＋隨機捲動＋點卡 | 6／6 | 6／6 |
| 連續 10 分鐘以上＋多次 GC | 全程計時，每 5 張 `obj gc` | 11 分鐘、13 次 GC，存活 | 第一輪 501 秒、6 次 GC 存活；同一行程第二輪約 15 分鐘時，開第 12 張卡發生 GPU PageFault（見下） |
| log 沒有 `: Error:` | `grep ": Error:"` | 只有原本就有的 CommonUI `Using CommonUI without a CommonGameViewportClient` | 第一輪 0 個；第二輪的錯誤都是那次 PageFault |
| 卡片格、圖片格 | 打包版要有 `WBP_OKCardTile`、`WBP_OKPickTile` | 有 | 舊 base 沒有（見上一節），重新 cook 後有 |
| 開卡失敗 | 一張好卡、一張 `okLc` 開頭清零的壞卡，先好後壞 | 名牌、滑桿、模型一致（無模型＋錯誤訊息） | 未測 |
| EyeMode 按鈕 | `press 動作與表情›眼睛：面向前方` 連按三次 | 三個模式循環，文字跟著變 | 有路徑 |

**第三條 GPU PageFault（2026-11-19）**：

- **症狀**：打包版第二輪的 GPU PageFault。當時 `d3d12.VRAMTexturePoolDefrag` 已經是 0，breadcrumb 停在 `FrameRenderFinish › RenderFinish › ViewFamilyExtension(5) › ViewExtension(0)`（DreamGUI），發生在開卡後約 5 秒。不是 GC、也不是貼圖池整理，是第三條。log 保存在 `E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-g2\pagefault.log`。
- **重現**：stage `EFork1119h` 用 `-gpucrashdebugging -ini:Engine:[ConsoleVariables]:r.D3D12.TrackAllAllocations=1` 啟動。同一行程第一輪完整驗證通過（559 秒），第二輪切到第 11 頁時當掉，位置一樣是 DreamGUI ViewExtension。資源追蹤的結果是：故障位址 16 MB 內沒有存活的資源，沒有 heap 包含它，最近 100 幀內也沒有釋放過包含它的資源。所以找不到是哪一個（`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-h2\pagefault.log`）。
- **處置：防禦性延遲釋放**。兩段時間盒內沒抓到具體資源，改成 DreamGUI 放開的 GPU 資源一律晚 3 個 render frame 才真正釋放（`FDreamUIDeferredRelease`）。涵蓋這幾處：資料貼圖變大時換掉的舊貼圖（WidgetData／ClipData／RectBlockData／PaintData，重建頁面時會變大）、合成群組用完的 pooled render target、畫布的目標貼圖、材質 proxy 的刪除。`DreamGUI.LogDeferredRelease` 印出等待中的數量。
- **延遲釋放沒有解掉這條**：stage `EFork1119i`（含延遲釋放，資源追蹤開著）約 7 分鐘、第一輪第 27 張卡時照樣 PageFault（`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-i1\pagefault.log`）。DRED 這次記到操作：故障在 DreamGUI ViewExtension 的**第一個** `DrawIndexedInstanced`（`BeginEvent [ViewExtension(0)]` 是最後完成的）。Aftermath 每次都指向同一個著色器位址 `fragment_02 @ 0x00045f90`，和 e-cardload 抓到的 `DXGI_ERROR_DEVICE_HUNG` 相同。
- **排除了什麼**：GC 回收（`DrawTextureHolds`）、貼圖池整理（已關）、最近 100 幀內釋放的資源（追蹤結果是 0）、DreamGUI 自己換掉的資料貼圖、pooled RT、材質 proxy（延遲釋放後照當）。
- **剩下的方向**：故障位址不屬於任何追蹤到的資源或 heap，比較像上傳記憶體（uniform buffer、動態緩衝）或描述子指到早已不存在的位置。下一步是拿到帶除錯資訊的著色器（`r.Shaders.Symbols=1` 重新 cook），把 `0x45f90` 對到 DreamGUI 哪個 pixel shader 的哪一行讀取；或在開發版開 D3D12 GPU-based validation 重現。
- 延遲釋放留著當防護，代價是被放開的 pooled RT 多留 3 幀才回池。
- **字型圖集 slice 越界（協調者提的方向，2026-11-19 查過）**：三次當機前都有 `AddAtlasSlice … Expend Texture2DArray slice to: 2`，但都是在當機前 4–14 分鐘，不是緊接著。DreamGUI 的 pixel shader 對字型圖集用 `Sample`（`DreamUIText.ush`、`DreamUIShade.ush`），對資料貼圖用 `Texture.Load`。D3D12 的 `Sample` 會把 array index 夾到實際 slice 數，`Load` 越界回傳 0，兩者都不會造成 MMU fault。上傳端 `FlushFontTexture` 也先檢查 `Slice < SliceCount` 才寫。要造成 page fault，必須是描述子本身指到沒有對應的記憶體，所以單純在 shader 裡 clamp slice 不會改變結果，這次沒有加。
- **GPU-based validation（2026-11-19，第一長段）**：打包 stage `EFork1119i` 開 `-gpuvalidation`，每輪先切 22 頁讓字型圖集擴張，再開第 18–29 張卡。21 輪、約 250 次開卡，0 個 D3D12 ERROR／WARNING，也沒當（`E:\OpenKoikatsu\Saved\Reports\reader-gbv-20261119`）。GBV 會把提交序列化，序列化後就不重現，比較像時序或競態問題，不是固定的錯綁。
- **`Failed to read file ''` 與 NeverStream（查過，不成立）**：三次當機的 log 都有 LogStreaming `Failed to read file ''`，出現時刻正好在建外觀縮圖時。曾懷疑是 `CreateTransient` 的貼圖被串流器搬動。開著讀卡器跑 `ListTextures`（`E:\OpenKoikatsu\Saved\Reports\reader-seg2-20261119\listtextures.json`）：598 張 `/Engine/Transient` 貼圖全部 `Streaming=NO`；串流中的只有 13 張引擎內建貼圖（天空、DefaultDiffuse、DefaultTexture 等），都卡在 64×64。這個警告是串流器讀不到這些引擎貼圖的 mip，屬於打包內容的問題，DreamGUI 不畫它們。給讀卡器縮圖補 NeverStream 之後警告照樣出現，所以改動已撤回。
- **資料貼圖變大**：`DreamUIDataTexture` 變大時記一行 log（`DreamUIDataTexture <名稱> grows to <列數> rows`），並先等 RDG 非同步執行完成才換貼圖與更新參照，供下次當機時對時間點。
- **Aftermath dump**：`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-i1\D3D12.0.2026.11.19-04.02.23.nv-gpudmp`。要用 Nsight Graphics 打開才看得到出錯的著色器與綁定的資源；這台機器只有 Nsight Compute／Systems／VS Edition，沒有 Nsight Graphics。

## 未結案：讀卡器第三條 GPU PageFault（2026-11-19，真因未找到，目前靠關掉 RDG 並行執行迴避）

**這不是修好，是迴避。真因未找到。** 若要恢復讀卡器的 RDG 並行執行，必須先找到並解掉真因，不能只是拿掉這個設定。

**現況（2026-11-19 08:30）**：讀卡器新版畫面啟動時關掉 RDG 並行執行（`804306bad`，`run_card_reader_development.lua` 加 `-ini:Engine:[ConsoleVariables]:r.RDG.ParallelExecute=0`）。**代價**：讀卡器的渲染少了一層平行，所有 RDG pass 都在 render thread 依序錄製命令。用下面的重現配方，關掉後三趟共 160 次開卡不當；開著時每趟第 5–17 張就當。e-cardload 用它定稿的配方再驗兩趟：兩趟乾淨就降級為「未再重現，但未證明根因消除」。

**三個必要條件**（各有對照，其他條件不動）：

1. 新版 DreamGUI 畫面：同一個 build 帶 `-LegacyReader` 開 30 張不當（e-cardload）。
2. 真的載入 3D：只在卡片牆點卡（不重開 3D）＋捲動，360 次點卡、60 次捲動不當（e-cardload）。
3. 載入後停幾秒：不停、一張接一張開 30 張不當；每張停 6 秒，第 6–13 張就當（e-cardload）。

再加上這輪量到的：**RDG 並行執行開著**（引擎預設 2；設 1 也當；只把 DreamGUI 自己的 pass 設 `NeverParallel` 也當；要從啟動參數關掉才不當，讀卡器開啟時由程式關掉照當）。

**重現配方**（e-cardload 定稿）：新版 UI（不帶 `-LegacyReader`）、`-CardDirectory=E:\OKPackage\TestCards-20261118`、逐張開**不同**的卡（`reader_call load` 或卡片牆點卡＋「載入3D」，看 `state.session` 換了才算真的重開）、每張開完停 6 秒。通常第 6–13 張、1–4 分鐘內 `DXGI_ERROR_DEVICE_HUNG`＋PageFault。驗防護時帶 `-ParallelRDG`（保留引擎預設）就能重現。

**已排除的七條**：

| # | 假設 | 怎麼排除 |
|---|---|---|
| 1 | GPU 資源提前釋放 | `r.D3D12.TrackAllAllocations=1`：故障位址不屬於存活資源，也不屬於最近 100 幀內釋放的資源；加了 `FDreamUIDeferredRelease`（晚 3 幀放）照樣當 |
| 2 | 延遲釋放佇列積壓 | 每張卡記一次，佇列都是 0；每幀放掉所有到期的，沒有上限 |
| 3 | 字型圖集 `Texture2DArray` slice 越界 | `Sample` 會夾 index、`Load` 越界回 0、上傳端檢查 slice 數；圖集擴張都在當機前 1.5–14 分鐘 |
| 4 | 跨幀懸空描述子 | 繪製參數在 render command 才解析成 `TextureReference`（引用計數持有）；GBV 下約 250 次開卡、0 個 D3D12 錯誤 |
| 5 | NeverStream／串流器搬動 transient 貼圖 | `ListTextures`：所有 transient 貼圖都是 `Streaming=NO` |
| 6 | GC use-after-free | 每幀 GC（`gc.CollectGarbageEveryFrame 1`）照樣第 12 張當；三條 GC 驗證（`gc.VerifyUObjectsAreNotFGCObjects`、`gc.VerifyAssumptions`、`gc.VerifyNoUnreachableObjects`）0 個報告；`DrawTextureHolds` 是 `UPROPERTY`（強引用） |
| 7 | VRAM 吃緊或 bindless 描述子堆擴張 | 當機時 `Local Used` 2.0–2.7 GB／預算 31.4 GB；描述子堆起始設成 100 萬（不會擴張）照樣第 10 張當 |

另外不是必要條件的：外觀縮圖快取（當機時它是 0；上限 128 照當）、卡片牆縮圖與所有圖片（`ok.ReaderThumbs 0`＋`ok.ReaderPictures 0` 照當）、角色貼圖累積（e-cardload 修掉 `RecentRuntimeTextures` 與色彩分級 LUT 兩個成長源後照當）。

**範圍：以「哪個行程」決定，啟動時設、之後不還原（2026-11-19 09:30 起）**

e-cardload 的四格實驗（協調者裁示依據）：

| 格 | 條件 | 結果 |
|---|---|---|
| 1 | 啟動時設 0 | 兩趟 ×30 張乾淨 |
| 2 | 啟動時平行開著、執行中設 0（讀值確認 2→0） | 第 7 張當 |
| 3 | 從 Studio 回讀卡器（執行中還原再關一輪） | 第 4 張當 |
| 4 | 以 0 啟動、執行中設回 2（e-fork-2 量） | 第 11 張當 |

**只有算圖開始之前就設好的 0 擋得住**，執行中切換無效。所以先前「進 1 對 1／Studio 還原、回讀卡器再關」那套（`26e7e91e0`、`340b70e56`）已拆掉：

- 讀卡器的啟動器（`run_card_reader_development.lua`）在啟動參數加 `-ini:Engine:[ConsoleVariables]:r.RDG.ParallelExecute=0`，整個行程到結束都是 0，同一個行程裡的 1 對 1 與 OK Studio 也一樣，不還原。
- 會顯示讀卡器的行程都經過這個啟動器：`CardReaderDevelopment.cmd`（開發樹與打包版都有）、遊戲 MCP 的 `reader_launch`、`Tools/reader_package_sweep.lua`。沒有另外的啟動器程式（讀卡器的「返回啟動器」回到卡片牆）。
- 獨立行程不設：`StreetSocial.cmd`（街區 stage）、`SceneEditor.cmd`／`OKStudio.cmd`、百人房間，都不會顯示讀卡器，維持引擎預設 2。
- 漏洞：直接執行 stage 的 `OpenKoikatsu.exe` 不帶地圖時，預設地圖就是讀卡器，但沒有這條。讀卡器開啟時若讀到不是 0，會在 log 寫一行 Warning（`ok.ReaderScreen: r.RDG.ParallelExecute is N, not 0 from startup ...`）。帶 `-ParallelRDG` 的對照趟也會看到這行，是預期的。
- 代價：同一個行程裡的 1 對 1／Studio 也少一層平行。1 對 1 的 FPS 對照見下。
- 貼圖池 defrag：讀卡器開啟時由程式關掉，之後也不還原。

以下兩段是拆掉之前的紀錄。

**（已拆）作用範圍（只限讀卡器）**：這條只由讀卡器的啟動器（`CardReaderDevelopment.cmd` → `run_card_reader_development.lua`）加，而且只在新版畫面時加（`-LegacyReader` 不加，`-ParallelRDG` 不加）；街區（`StreetSocial.cmd`）、OK Studio（`SceneEditor.cmd`）、百人房間的啟動器都不加，那些程序是引擎預設的 2。讀卡器裡按「進入1對1互動場景」或「進入工作室」（OK Studio）時 `UOKReaderScreen::ReaderRenderSettings(false)` 把它設回引擎預設，貼圖池 defrag 也還原；回到讀卡器時再設回 0（`ok.ReaderScreen: r.RDG.ParallelExecute ...` 會寫進 log）。注意：執行中才設 0 量過擋不住，所以從 1 對 1 回來之後的讀卡器只有「執行中設 0」那一層，沒驗證過；真正量過有效的是啟動時就是 0。

**設回去是不是真的恢復平行（2026-11-19 08:30 量）**：引擎每建一個 RDG builder 就讀一次這個 cvar（`RenderGraphBuilder.cpp` 604–605 行），照程式設回 2 就會恢復。實測：stage `EFork1119w` 以 0 啟動，執行中 `r.RDG.ParallelExecute 2`，再跑上面的配方，**第 11 張就當**，簽章和對照趟一樣（PageFault、唯一的 Active Shader 是 Pixel `MainPS`，Shader Hash `E6753E1EA9F1F20775D8BC0AD963B1EF`）。所以執行中設回 2 確實讓平行執行回來了，1 對 1 拿回的是真的平行，不只是值寫回去。（`E:\OpenKoikatsu\Saved\Reports\reader-dwell-runtime2-20261119\progress.txt`，log `E:\OpenKoikatsu\Saved\Logs\CardReader\stage-EFork1119w-reader.log`。）來回切換的 log：進 1 對 1 時 `ok.ReaderScreen: r.RDG.ParallelExecute 2 (left the card reader)` 與 `d3d12.VRAMTexturePoolDefrag 1`，回讀卡器時 `... 0 (the card reader)` 與 `... 0`（stage `EFork1119z`）；進出工作室同樣（stage `EFork1119v`，`OKStudio.Stop` 關掉後設回 0）。

兩個方向不對稱、還沒解釋：執行中設 2 會當，但執行中設 0 擋不住（只有啟動時設 0 才擋得住）。可能是啟動時為 0 讓某個只建一次的東西走了不同的路，尚未查證。

**迴避的是哪一類**：RDG 把畫面的 pass 分到多個工作執行緒並行錄製命令時，有東西和 DreamGUI 的繪製在 GPU 上讀到失效的記憶體。這是一個競態：它跟哪些 pass 恰好同時在飛行中的幀裡錄製有關，所以要停幾秒、跑到第幾張才出現。關掉並行執行後所有 pass 在 render thread 依序錄製，這一類時序問題就不會發生；但被蓋掉的是症狀出現的條件，讀到失效記憶體的那個東西還在。還不知道是哪一個 pass、讀到哪一塊；從啟動參數關才有效，表示讀卡器開啟前已經跑過的那幾幀也有關（例如 D3D12 的並行命令 context 在那時建好），尚未查證。breadcrumb 取證保留，萬一再發生，那是最有用的資料。

以下是追查過程的紀錄。

| 項目 | 內容 |
|---|---|
| 症狀 | `LogD3D12RHI: Error: GPU crash detected`，`DXGI_ERROR_DEVICE_HUNG`／`PageFault at VA GPUAddress …`，Aftermath `MMU Fault Error`，著色器位址每次都是 `fragment_02 @ 0x00045f90` |
| 位置 | DreamGUI 的 view extension（`FrameRenderFinish › RenderFinish › ViewFamilyExtension › ViewExtension(0)`）。DRED 的「最後完成」停在第一個 `DrawIndexedInstanced`，以前因此寫成「第一個 draw」；05:45 那次的 breadcrumb 顯示當時 GPU 上同時有 13 個 DreamGUI draw 已開始未結束，出錯的是其中哪一個，DRED 分不出來（見下） |
| 情境 | 都在連續瀏覽卡片、切分頁時，約 4–15 分鐘或開十幾張卡之後；打包版四次（stage `EFork1119g`、`EFork1119h`、`EFork1119i`、`EFork1119r`），e-cardload 用開發版兩次 |
| 最好的重現 | e-cardload：把 `E:\OKPackage\TestCards-20261118` 的 30 張連著開（開卡、服裝 2、播一段動畫、翻四個外觀分頁），兩趟各在第 12（heroine_alice）、第 25 張（kks_Saria）卡死；每張單開都正常、每趟卡死的卡不同（`Docs/CARD_READER_30CARD_REGRESSION_20261119.md`）。e-fork-2 同一批卡連開（開卡、翻 5 個分頁），第 9 張卡（第 8 號）開完 12 秒後卡死 |
| 目前的判斷 | 時序／競態：序列化提交（GBV）後不重現，故障位址不屬於任何追蹤到的資源。累積型成長在量（下節）；VRAM 吃緊已排除 |
| 修了的不是它 | D3D12 貼圖池整理（已關）、縮圖改貼圖池、字型圖集保留、DrawTextureHolds：它們各自修掉了前兩條，這條照樣出現 |
| 加了的防護 | `FDreamUIDeferredRelease`（放開的 GPU 資源晚 3 幀）、資料貼圖變大前等 RDG 非同步執行：保留，但不是這條的解 |

**排除了的五條**

1. 資源提前釋放：開 `r.D3D12.TrackAllAllocations=1` 時，故障位址不屬於存活資源，也不屬於最近 100 幀內釋放的資源；加了延遲釋放佇列照樣當。
2. 字型圖集 `Texture2DArray` slice 越界：`Sample` 會夾 index、`Load` 越界回 0，上傳端也檢查 slice 數。圖集擴張都在當機前 4–14 分鐘，不是緊接著。
3. 跨幀懸空描述子：繪製參數在 game thread 用 `.Get()` 取 `UTexture*`，到 render command 才解析成 `TextureReference`（引用計數持有，貼圖釋放時改指預設貼圖）；UObject 要等 render thread 處理完它的 release 才釋放。
4. NeverStream／串流器搬動 transient 貼圖：`ListTextures` 量到所有 transient 貼圖都是 `Streaming=NO`。`Failed to read file ''` 是 13 張引擎內建貼圖讀不到 mip。
5. GBV：`-gpuvalidation` 21 輪、約 250 次開卡，0 個 D3D12 錯誤也不當。

**取證**：DreamGUI 每個內建繪製在 GPU breadcrumb 寫一筆 `DreamUIDraw main=… font=… widget=… clip=… rect=… paint=… mask0=…`（綁定的每張貼圖的 RHI 名稱）。用 `-gpucrashdebugging` 啟動時，下一次 DRED／Aftermath 指到那個 draw，就能直接看出是哪張貼圖。

**連開 30 張的量測（2026-11-19 05:42，stage `EFork1119r`，`-gpucrashdebugging`）**：每張卡開完、翻完分頁後記 `ok.ReaderScreen resources`（新指令：縮圖池、外觀縮圖快取、鏡像控制項、存活 DreamGUI widget、依類別分的存活貼圖與大小、RHI 貼圖記憶體）與 DreamGUI 延遲釋放佇列，另外每 10 秒記 `nvidia-smi` 的 VRAM。開到第 9 張（05:45:47）卡死。資料在 `E:\OpenKoikatsu\Saved\Reports\reader-grow-20261119\`（`resources.txt`、`vram.txt`、`pagefault.log`、`D3D12.0.2026.11.19-05.45.47.nv-gpudmp`）。

| 量 | 第 1 → 第 8 張 | 判斷 |
|---|---|---|
| 這台的 GPU | RTX 5090，32 GB；當機那幀 D3D12 回報 `Local Used 2365 MB / Budget 31419 MB` | VRAM 遠沒吃緊，「逐出常駐資源」這條機制不成立（8 GB 是低配機的目標，不是這台） |
| transient `Texture2D` | 452 → 635 → 751 → 1048 → **592** → 825 → 972 → **642** MiB | 角色貼圖，GC 會收回，不是單調上升 |
| 外觀縮圖快取 `AppearanceThumbCache` | 88 → 448 張，12 → 102 MiB，只增不減 | 依縮圖檔路徑存、沒有上限；但它屬於遊戲目錄的項目，總數有上限，且這些貼圖一直被引用、不會被放掉 |
| 存活 DreamGUI widget／鏡像控制項 | 1472–1477／184，平穩 | 重建頁面有回收 |
| 卡片縮圖池 | 18–20 張，平穩 | 有重用 |
| DreamGUI 延遲釋放佇列 | 每次記錄都是 0 | 沒有積壓 |
| 字型圖集 slice | 第 4 張時擴張到 2（當機前 1.5 分鐘），之後不變 | 不是緊接著當機 |
| 資料貼圖擴張 | 只在第 1 張（當機前 2 分 47 秒） | 不是緊接著當機 |

**breadcrumb 第一次派上用場**：當機那幀 GPU 上「已開始未結束」的 DreamGUI draw 有 13 個：2 個畫精靈圖集（`DreamUIDynamicSpriteAtlasData_Texture_0`）、6 個畫白底（`DreamUIPreset_WhiteSolid`）、4 個畫圖片格的 transient 貼圖（`Texture2D_2147445830`–`833`，連號，是同一批剛建的縮圖）。所以出錯的 draw 不一定是第一個，圖片格的貼圖也是嫌疑。breadcrumb 文字在約 128 字被截斷，`clip／rect／paint／mask0` 欄位看不到；下一版要把欄位拆短或分成兩筆。

**對照：圖片格不畫貼圖（2026-11-19 05:58，stage `EFork1119t`，`ok.ReaderPictures=0`）**：同一個連開腳本、同一批卡，只差圖片格（外觀選擇、瞳孔覆蓋貼圖、卡片牆、鏡像的 UMG 圖片）不畫貼圖。跑滿 18 分鐘、43 張（第二輪到第 13 張），沒有當，log 0 個 Error。畫圖片時這個流程在第 9 張（約 4 分鐘）當；e-cardload 兩趟在第 12、25 張。外觀縮圖快取在這一輪照樣長到 1056 張／457 MiB，所以「快取變大」本身不是觸發條件，有沒有畫才是（`E:\OpenKoikatsu\Saved\Reports\reader-nopics-20261119\resources.txt`）。一次對照還不算定論，但方向一致：嫌疑落在圖片格的 transient 貼圖被 DreamGUI 畫的那一段。

**再兩次對照（2026-11-19 06:23–07:00，stage `EFork1119u`，breadcrumb 已拆成三筆、看得到全部欄位）**：

| 條件 | 結果 | 當時在 GPU 上的 DreamGUI draw |
|---|---|---|
| 外觀縮圖快取上限 128（`ok.AppearanceThumbCacheMax=128`，快取停在 128 張／14.4 MiB） | 第 24 張、約 9.5 分鐘卡死（`E:\OpenKoikatsu\Saved\Reports\reader-lru128-20261119\`，含 dump `D3D12.0.2026.11.19-06.33.27.nv-gpudmp`） | 2 個：一個卡片牆縮圖（`Texture2D_2147452573`，288×402，縮圖池的貼圖）、一個白底 |
| 卡片牆縮圖關掉（`ok.ReaderThumbs=0`），外觀圖片照畫 | 第 23 張、約 16 分鐘卡死（`E:\OpenKoikatsu\Saved\Reports\reader-nothumbs-20261119\`） | 只有精靈圖集與白底的 draw，沒有任何圖片 |

**這兩次推翻了兩條**：快取變大不是原因（上限 128 照當）；卡片牆縮圖池也不是唯一原因（關掉照當，而且當時根本沒有圖片 draw 在跑）。前面「圖片全關 43 張沒當」只跑過一次，目前看起來可能只是運氣（已見的當機張數：9、12、23、24、25）。

**所有當機都相同的部分**：每個 DreamGUI draw 都綁同一組四張資料貼圖（`widget`、`clip`、`rect`、`paint`，`DreamUIDataTexture_*`，每幀用 `UpdateTexture2D` 更新改到的列）；PageFault 的 VA 每次都不同（21 個不同位址，大多以 `…1000` 結尾），所以不是固定某一塊資源被放掉。下一步往兩處查：資料貼圖每幀的部分更新（`DreamUIDataTexture.cpp` 的 `Upload_RenderThread`，非整張時走 staging＋`EnqueueLambda` 複製）和 draw 的錄製順序；以及 bindless 下 `TextureReference` 的描述子在更新時的處理。

**新指令**：`ok.ReaderScreen resources`（量累積用）、`ok.ReaderPictures 0`（對照用，預設 1）。breadcrumb 拆成三筆（`DreamUIDraw main/font`、`DreamUIData widget/clip`、`DreamUIMore rect/paint/mask0`），每筆都在 128 字內。

**下一步**：
1. 用拆短的 breadcrumb 在「畫圖片」下再重現一次，看在途的圖片 draw 綁的完整資源。
2. 再跑一次 `ok.ReaderPictures=0` 加強對照。
3. 查圖片格貼圖從建立到給 DreamGUI 畫的路徑（`Thumbnail()`／`EyeOverlayThumb`／卡片縮圖池的 `CreateTransient`＋`UpdateResource`，DreamGUI 圖片筆刷取 `TextureReference` 的時機）。
4. Nsight Graphics 開 dump（見下）。

**需要的工具**：用 Nsight Graphics 打開 Aftermath dump，就能直接點名出錯的著色器與資源，這台機器沒有裝（只有 Nsight Compute／Systems／VS Edition），要不要裝由使用者決定。dump：`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-i1\D3D12.0.2026.11.19-04.02.23.nv-gpudmp`；log：`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-g2\pagefault.log`、`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-h2\pagefault.log`、`E:\OpenKoikatsu\Saved\Reports\reader-verify-20261119-stage-i1\pagefault.log`。

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
| 真實滑鼠（2026-11-19 再試） | 先 `SetForegroundWindow` 把遊戲視窗帶到前景，再用 `SendInput` 送絕對座標與相對位移：沒按鍵移動 240 px，`ok.ReaderScreen look` 的 yaw／pitch／distance／focus 與 `last_change` 都沒變、`buttons=none`；**接著送真實左鍵拖曳 180 px，鏡頭一樣沒轉** | 真實輸入到現在還是進不到遊戲（連拖曳都沒反應），所以這條仍然測不到，不能當成「沒問題」的證據 |
| MCP（Slate）輸入 2026-11-19 複測 | 沒按鍵在 3D 區移動五個位置：鏡頭參數完全不變、`last_change=none`；從左欄（x=200）按下再拖過 3D 區：不轉；在 3D 區按下拖曳：yaw 0→-120，`last_change=mouse drag (buttons 1)` | 相機只在「按鍵從 3D 視窗上按下」時才轉，程式這層是對的 |

### 2026-11-19 的第二輪：改查「跟著游標的是誰」與「有沒有自動轉」

輸入那條已經查到底（上表），所以這輪改查兩個會被描述成「視野會轉」的東西：

- **眼睛跟游標（`EyeMode=1`，選單上的「眼睛：看鼠標」）**：預設是 0（面向前方），要按「眼睛」按鈕才會切到跟游標。但切到之後，`TickEyeMode` 直接拿 Slate 的游標座標算視線，**游標移到左右面板上、移出視窗、甚至移到另一個螢幕，她的眼睛都還在跟**。使用者看到的「畫面上的東西跟著滑鼠動」最可能就是這個。2026-11-19 已修：游標不在 3D 視窗範圍內（面板上、視窗外）就保持上一個視線不再更新；範圍取自 `UOKReaderScreen::ViewSpan`（兩片面板之間的 3D 區），舊版介面（`-LegacyReader`）沒有面板時以視窗範圍為準；MCP 與眼睛審核用的明確像素座標不受影響。修完實測（`ok.Reader.EyeMode 1`，游標用 `ui_mouse` 移動，讀 `ok.ReaderScreen look` 的 `gaze`）：3D 區內三個位置各自不同（`0.275,-0.201,-0.459` → `0.293,-0.220,-1.000` → `0.130,-0.345,-0.499`），移到左欄（x=200）兩個位置與鏡頭列（y=40）都停在最後那組不再變；證據圖 `Saved/Reports/reader-eyes-20261119/cursor-in-3d.png`、`cursor-on-panel.png`（本機，不進版控）。`EyeMode=2`（看 Camera）沒有同樣的毛病：它跟的是 `StudioCam` 的位置（`FollowEyeLookCamera`），實測移動游標 `gaze` 不變。那顆「眼睛」按鈕是純 UMG、DreamGUI 沒鏡像，`ui_press` 與 `control_set` 都碰不到，所以加了 `ok.Reader.EyeMode [0|1|2]`（無參數則循環，`OKEyeCameraAudit.cpp`）讓外部測得到；正式的控制項等 DreamGUI 鏡像那顆按鈕。
- **自動環繞／待機轉台／跟拍：沒有**。全專案搜過 `OrbitYaw` 的每一個寫入點，讀卡器這邊只有鏡頭列按鈕、`ok.ReaderScreen`／MCP、換卡換服裝時從舊 Actor 沿用（`OKGalleryClothing.cpp`、`OKGalleryWidget.cpp`），其餘是 1 對 1／H 場景與人物編輯 MCP 截圖流程各自設定後還原。`AKKPreviewActor` 裡沒有任何一行按時間推進 yaw，也沒有 turntable／auto-rotate 之類的 cvar，`OrbitFocus` 在 `KKPreviewActor.cpp` 裡只有讀沒有寫。所以「沒碰滑鼠它自己在動」在讀卡器裡不存在。

下次再遇到時，在主控台（或 MCP `ui_exec`）下 `ok.ReaderScreen look`，一行就能定位：

- `look eye_mode=… eye_tracking=… eye_follows_camera=… gaze=… head_follows_camera=… buttons=…`：眼睛在跟誰（`eye_mode=1(cursor)` 就是眼睛跟游標）、頭是否跟鏡頭、Slate 現在認為按著哪些滑鼠鍵（沒按卻不是 `none` 就是按鍵狀態卡住）。
- `camera yaw=… pitch=… distance=… focus=… last_change=…`：鏡頭最後一次是誰改的（`mouse drag (buttons N)`、`mouse wheel`，或不是滑鼠：鏡頭列按鈕、MCP、載入）、幾秒前、當時 Slate 認為按著的鍵。

### 2026-11-19 e-cardload-physics：累积型假设量到底了（分两层，哪一层确证写明）

协调者提的「连开卡时 GPU 侧的东西一直长 → GC 放掉 → 有人还握着被放掉的那块」这条，量完的结论是：
**累积是真的，但它不是这条 PageFault 的原因；而且累积的大头也不是「被谁握着」，是 GC 还没来收。**

**第一层：被 refcount 钉死、GC 永远收不掉的那一批（确证，已修）**

| 量什么 | 怎么量 | 结果 |
|---|---|---|
| 换卡＋强制 GC 之后，前一张卡的贴图还活着吗 | 开 crowd_C001 → 开 crowd_C006 → 连三次 `obj gc` → 两次 `ListTextures` 取差集 | 第一张卡的贴图**还活着 233 张／419 MB**，其中 transient（只能是开卡建出来的）137 张／370 MB |
| 谁握着它 | `obj refs name=Texture2D_99`（引用链搜寻） | `(refcounted<1>) ... is not currently reachable but it does have 1 refcount set.` —— **没有任何 UObject 参照它**，是纯 refcount 钉住，所以 GC 收不掉 |

凶手是 `Plugins/KKRuntimePose/Source/KKRuntimePose/Private/KKRuntimeMaterial.cpp` 的 `RecentRuntimeTextures`：
512 MB 预算、`TStrongObjectPtr` 持有的「切回去很快」快取（它上面的 `RuntimeTextureCache` 是**弱**引用，所以持住贴图的只有它一个）。
UE 5.8 里 `TStrongObjectPtr` 就是用 UObject refcount 实作的，所以引用链只会说「不可达但有 1 refcount」，不会给出链。
**跨卡永远不会命中**（不同卡＝不同像素＝不同 identity），所以那是纯浪费。

改法：开卡时（`DestroyAllParts()` 之后）把快取全标「没碰过」，这次载入用到的会被重新碰到，载入完成把没碰过的当场放掉并印一行
（`OK kept GPU textures: released N (X MB) from the card just left, keeping M (Y MB)`）。同卡换服装照样命中。
新增 `ok.KeptTextures`／`ok.KeptTexturesClear`（角色贴图侧）与 `ok.RuntimeTextureCache`／`ok.RuntimeTextureCacheClear`
（`KKTextureRuntime` 侧的同名孪生快取，读卡器不走那条路径，一起补上）。

验收（30 张连开，改后）：每张卡都放掉 1～30 张（5～69 MB），跑完强制 GC 后 `ok.KeptTextures` 回
`91 (288.9 MB); not touched by the current card: 0 (0.0 MB)` —— **「被钉死的前一张卡贴图」这一项归零，这是确证的。**

**同一轮量到的、要讲清楚的三件事（别误读成修好了）**

1. **贴图总量的峰值没有变小**：改后 30 张照样锯齿上升到 1512 MB（改前第 7 张 1376 MB）。原因是峰值的大头**不是这个快取**，
   是**还没被 GC 收的垃圾**：`gc.TimeBetweenPurgingPendingKillObjects` 是 61 秒，一张卡约 5 秒，所以一次清理之间会堆十几张卡的垃圾。
   跑完两次 `obj gc` 后总量回到 485 MB（transient 436 MB＝快取 289 MB ＋ 两张图集 32 MB ＋ 当前这张卡约 115 MB），**没有无法解释的残留**。
2. **行程没有漏物件**：`getall KKPreviewActor` 全程只有 3 个（当前＋`StalePreview`＋影子），`MaterialInstanceDynamic` 575、`SkeletalMesh` 47，
   都是当下这张卡的量级，不是每开一张就多一份。
3. **所以「换卡时主动释放」解决的是浪费，不是当机。**

**第二层：当机（没有解决，而且把一个方向排除掉了）**

| 量什么 | 怎么量 | 结果 |
|---|---|---|
| GC 频率是不是放大器 | `gc.CollectGarbageEveryFrame 1`（log 每帧都有 `Compacting FUObjectHashTables`，确认真的在跑），连开 30 张 | **照样在第 12 张（demo_Male01）PageFault**，约 5 分 40 秒；签章相同（`DXGI_ERROR_DEVICE_HUNG`、`MMU Fault Error`、`fragment_02 @ 0x00045f90`） |
| 便宜的 GC 验证会不会点名 | `gc.VerifyUObjectsAreNotFGCObjects 1`、`gc.VerifyAssumptions true`、`gc.VerifyNoUnreachableObjects 1`（这版引擎三条都有；第一条专案设定关成 0，预设是 1） | 从第 11～12 张开到当机，**log 里零个 FGCObject／Unreachable 报告** |
| 当机那刻的资源追踪 | log 里 `PageFault: Found 0 released resources ... during last 100 frames` | **不算证据**：同一段也写着 `Logging all resource enabled: No`，追踪没开 |

**由此排除：「GC 把还在用的贴图收掉」这条机制。** 每帧 GC 的话垃圾来不及累积，如果是生命週期问题应该第二三张就炸；
它却和自然 GC 那两趟一样要开到第 12（或第 25）张。**驱动量是「开了几张卡」，不是时间、不是 GC 频率、不是 VRAM 占用**
（当机那刻 `Local Used 2512.78 MB / Budget 31419 MB`，只用 8%）。

**剩下最像的方向（协调者提，归 e-fork-2 那侧查）**：有某个**随开卡次数单调增长**的量被 UI 合成那个 draw 用到，长到越界。
位址固定、和 GC 无关、和 VRAM 无关、要十几张才发生、GBV 下不重现，都符合这个形状。
我这侧（`KKRuntimePose`／`KKRuntimeMaterial`／材质与贴图建立）**查不到同类的量**：持久容器只有刚修的 `RecentRuntimeTextures`（有预算、现在换卡就放）、
`RuntimeTextureCache`（弱引用，key 是像素内容 hash，不是递增 id）、toon shadow 的 `Shared[2]`（固定两张轮替）；
没有递增的 handle／slot id，角色材质用的是 MID 的具名贴图参数，没有被打包进顶点属性或常数的贴图索引，所以**位宽不够那种在这侧不成立**。
现有量过的东西里，唯一**真正单调上升又会被 UI 合成取样**的是外观缩图快取（88 → 448 张、12 → 102 MiB，依缩图档路径存、没有上限），
其次是 DreamGUI 的精灵／字型图集（`Texture2DArray`，第 4 张卡时扩张到 2 个 slice）。

**这一轮犯的错（留着当例子）**：我第一次指认的凶手是 `KKUnityBundle` 的 `KKTextureRuntime.cpp` 里**同名写法的孪生快取**，
推论链（refcount、预算、bytes 公式）全都对得上，但**那条路径读卡器根本不走** —— 新版一跑，`ok.RuntimeTextureCache` 回
`kept 0 textures 0.0 MB ... hits=0 misses=0`，而且旧 log 里 `OK readonly GPU textures hits=0 misses=0 entries=0` 一直是零，我没看那行就下了结论。
**认定某份快取是凶手之前，先确认那条路径真的被走到。**

### 2026-11-19 的一刀切实验：开卡 20 次但只用两张卡（不炸）

协调者设计的实验，目的是分开两个混在一起的变数：**开卡的次数** 与 **开过的不同资源有几套**。

做法上有一个坑：**同一张卡连开两次会被读卡器跳过**（`reader_call load` 同路径回来 `session` GUID 不变，3D 不会重开），
所以「同卡 20 次」拿不到 20 次真的开卡。改成等价版本：**crowd_C001／crowd_C006 交替开 20 次**，各 10 次、每次停 6 秒，
其他条件与 30 张那趟完全相同（同一个 build、同一台机器、锁自己的 `OK_GAME_PID`）。

| 量 | 结果 |
|---|---|
| 会不会当 | **20 次全部正常，没有 PageFault**（约 4 分钟；对照组是只开卡不翻分页的 30 张流程，分别在第 8 与第 12 张当） |
| 贴图总量 | 第 2 次之后就停在 **689～693 MB**，不再上升；每 6 次一个 GC 把它压回 303 MB（锯齿有上界） |
| 贴图张数 | 在 354～398 之间来回；GC 后的**地板每一圈多 6 张**（246 → 252 → 258），也就是每次开卡约多 1 张、约 0.1 MB |
| 外观缩图快取 | `ok.ReaderScreen resources` 回 `appearanceCache=0 (0.0 MiB) appearanceTextures=0`：**光开卡不会喂它**，要翻外观分页才会 |

**判读（照实验设计前就写好的两条）**：开卡动作一样做了 20 次、资源却被压在两套的量级 → **不当**。
所以驱动量是**开过的不同资源有几套**，不是「开卡这个动作本身」。
这支持「有某个随不同资源数单调增长的量被 UI 合成那个 draw 用到，长到越界」这条假设。

**同时排除一条**：外观缩图快取（88 → 448 张、只增不减）**不是必要条件** ——
两趟当掉的流程（vram 量测那趟第 8 张、每帧 GC 那趟第 12 张）都只开卡、没翻外观分页，当时那个快取必然是 0，却照样当。
它是另一笔独立的浪费，不是这条 PageFault 的原因。

**留给下一个人的两条线**：
1. 「每次开卡多约 1 张贴图」这个小幅单调成长（只有两张卡时仍然存在），是现在唯一还在爬的量，值得查它是什么。
2. 要找的那个容器必须是**依「不同资源」成长**的：同一张卡反复开不会让它长。按这个条件筛 DreamGUI 绘制路径上的持久容器。

### 2026-11-19 的第三刀：换掉 UI 这一层（`-LegacyReader`）—— DreamGUI 是必要条件

同一个 build（含 `8889387c2` 换卡释放与 `ca466b2aa` LUT 快取两笔修正）、同一批 30 张卡、
同样「只开卡，不翻分页、不切服装」、每张停 6 秒、锁自己的 `OK_GAME_PID`，只换掉 UI 这一层。

| 趟 | UI | build | 结果 |
|---|---|---|---|
| 1 | 新版 DreamGUI | `8889387c2`（只有换卡释放） | 30 张跑完，**没当** |
| 2 | **旧版 UMG**（`-LegacyReader`） | 含两笔修正 | 30 张跑完，**没当**；贴图总量照样锯齿（464 → 1371 MB，GC 压回 455 MB） |
| 3 | 新版 DreamGUI | 含两笔修正（与第 2 趟同 build） | **第 6 张（crowd_C049）就 PageFault** |

**判读：DreamGUI 这一层是必要条件。** 第 2、3 趟只差 UI 这一个变数，旧版 30 张干净、新版第 6 张就当。
（第 1 趟留着当提醒：**它整趟没当，所以单独一趟「没当」没有鉴别力** —— 这个缺陷本来就不是每趟必中，
先前是第 8、12、25 张。以后重做这个对照的人不要用一趟的结果下结论。）

先验过旧版真的生效才敢跑：命令列里有 `-LegacyReader`，log 里 `ok.ReaderScreen` **零行**（DreamGUI 画面没开起来）。

**第 3 趟当机那一刻的完整数字**（两个已知的成长源都已修掉，杂讯比前四次少）：

- 签章与前四次相同：`DXGI_ERROR_DEVICE_HUNG`、`MMU Fault Error`、`PageFault at VA GPUAddress 0x2578C91000`，
  着色器位址 `fragment_02 @ 0x00045f90`（执行中另有 0x00046000／0x0004a740／0x0004a7a0）。
- **GPU 上「已开始未结束」的 draw 全部是 DreamGUI 自己的**：`DreamUIDraw main=DreamUIDynamicSpriteAtlasData_Texture_0`
  与 `main=DreamUIPreset_WhiteSolid`，底下 `DreamUIData widget=DreamUIDataTexture_6 clip=DreamUIDataTexture_3`、
  `DreamUIMore rect=DreamUIDataTexture_4 paint=DreamUIDataTexture_1 mask0=fallback`。
  **没有一个绑着角色贴图**，位置在 `RenderGraphExecute - CanvasRenderThreadScope` 之后的 ViewExtension(0)。
- 修正后的两个量都正常：`OK kept GPU textures: released 65 (159.9 MB) from the card just left, keeping 74 (212.4 MB)`，
  `256x16` 色彩分级 LUT 固定 1 张。所以当机**不是**这两个成长源造成的。
- log 与 dump：`Saved/Logs/CardReader/20261119-064041-1c8e4928.log`、`Saved/Crashes` 的 `UECC-Windows-*`。

**所以这条对 e-cardload-physics 这侧结案**：真因在 DreamGUI 的绘制路径（绑定的是它自己的图集与 data texture），
角色／预览／材质那条路径上已查无可疑的单调成长量（见上一节）。两笔修正解决的是两笔浪费，不是这条 PageFault。

### 2026-11-19：第三条 GPU PageFault 的正式重现步骤（1～4 分钟内会中）

两次独立命中（第 6 张／约 70 秒、第 13 张／251 秒），再加上关掉缩图与图片那趟（第 12 张／125 秒），共三次。

```powershell
# 1. 新版 UI 读卡器（不要带 -LegacyReader）
.\Tools\ok-game-mcp\target\release\ok-game-mcp.exe call reader_launch '{"lane":"repro","card_directory":"E:/OKPackage/TestCards-20261118"}'
# 2. 逐张开「不同」的卡，每张开完停 6 秒；用 state.session 换了确认真的重开（同路径再开会被跳过）
#    OK_GAME_PID 锁自己的行程；通常第 6～13 张就 DXGI_ERROR_DEVICE_HUNG ＋ PageFault
```

驱动脚本（本机，不进版控）就是 `reader_call load` ＋ `Start-Sleep 6` ＋ 每张查一次 log 的 `GPU crash detected`。

**三个必要条件，各有对照**

| 条件 | 对照 | 结果 |
|---|---|---|
| **新版 DreamGUI 画面** | 同 build 带 `-LegacyReader` 跑同样 30 张 | 旧版 UMG **不当** |
| **真的载入 3D** | 只在卡片清单点卡（`ok.ReaderScreen card <N>` 只选取不重开）＋捲动，12 轮＝360 次点卡、60 次捲动 | **不当** |
| **载入后要停几秒** | 不等待、一张接一张连开 30 张（约 4 秒一张、共 125 秒） | **不当** |

最后那条把危险窗口定在**大规模 UI 重建之后的那几秒 idle 绘制**，不是重建的那一瞬间：连开不停时下一次载入很快把一切推掉，停 6 秒才给了飞行中的帧足够时间用旧绑定去画。

**排除：卡片缩图的背景解码与图片绘制都不是必要条件**

`ok.ReaderThumbs 0`（不再解码缩图）＋ `ok.ReaderPictures 0`（磁砖／镜像图／卡片清单都不画）两条一起设 0
（读回确认 `LastSetBy: Console`、值为 0），其他条件全部不动 —— **照样在第 12 张／125 秒当**。
所以 `TickThumbnails()` 与 `OKReaderThumbs` 那一段可以排除。
（注：APNG 2D 预览的 `NativeTick` 推进是**旧版 UMG gallery** 的事，新版 `UOKReaderScreen::Tick` 里没有 APNG，
所以「停掉 APNG」这个对照在新版画面上不适用，改用上面两条 cvar 等价替代。）

**所以剩下的范围**：关掉图片之后，当机那一帧飞行中的 draw 仍然是
`DreamUIDraw main=DreamUIPreset_WhiteSolid font=DreamUIFontData_DistanceField_Texture_0`
→ `DreamUIData widget=DreamUIDataTexture_6 clip=DreamUIDataTexture_3`
→ `DreamUIMore rect=DreamUIDataTexture_4 paint=DreamUIDataTexture_1 mask0=fallback`，
着色器位址照旧 `fragment_02 @ 0x00045f90`。也就是**基本 UI 绘制路径与它的四张 data texture ＋ 字型图集**，
与卡片图片无关。下一步该查的是这些 data texture 在**大规模重建**（载入完成后镜像控制项整段重建）时的
重建／扩张，以及那一刻飞行中的帧里的绑定是不是还指着旧的那张
（`FDreamUIDeferredRelease` 与「资料贴图变大前等 RDG 非同步执行」已经加过，但重建路径未必走同一条等待）。

log 与 dump：`Saved/Logs/CardReader/20261119-065520-5f723fec.log`（第 13 张）、
`Saved/Logs/CardReader/20261119-070006-26970b24.log`（关图片，第 12 张）、`Saved/Crashes` 的 `UECC-Windows-*`。

### 2026-11-19 07:00–07:12 e-fork-2：用短配方排除 bindless 描述子堆擴張

用 e-cardload 的短配方（新版 UI、`TestCards-20261118`、逐張開不同的卡、每張停 6 秒，腳本只開卡不翻頁），stage `EFork1119u`，`-gpucrashdebugging`。

| 條件 | 結果 |
|---|---|
| 不改設定 | 第 9 張、269 秒卡死（`E:\OpenKoikatsu\Saved\Reports\reader-dwell-base-20261119\`） |
| bindless 資源描述子堆一開始就 1,000,000（`-ini:Engine:[SystemSettings]:D3D12.Bindless.ResourceDescriptorHeapSize=1000000`，log 確認 `Initializing allocators with 1000000 Resource`，不會擴張） | 第 10 張、118 秒卡死（`E:\OpenKoikatsu\Saved\Reports\reader-dwell-heap1m-20261119\`） |

**為什麼查這條**：引擎 `BaseWindowsEngine.ini` 把描述子堆的起始大小設成 32768（引擎程式預設是 100 萬），滿了會翻倍並換一個 GPU 堆（`FD3D12BindlessDescriptorAllocator::ResizeGrowAndAllocate`），而「開過幾套不同資源」正好會讓描述子數量越過界。**結果不成立**：起始就是 100 萬、不會擴張，照樣在第 10 張當。

**當時 GPU 上的狀態（不改設定那趟）**：DreamGUI 這一幀前 47 個 draw 已完成，第 48、49 個（精靈圖集、白底）在跑，後面 49 個還沒開始；98 個 draw 綁的是同一組貼圖（資料貼圖四張、字型圖集、精靈圖集或白底）。載入在 8 秒前完成，中間 log 沒有任何 DreamGUI 的變大、擴張或重建紀錄。DreamGUI 的著色器只綁固定的幾張貼圖，沒有動態描述子索引。所以出錯的位址比較像來自這兩個 draw 自己讀到的東西（頂點資料、或資料貼圖裡的列內容），而不是綁定換了。

### 2026-11-19 07:13–08:05 e-fork-2：RDG 並行執行是必要條件，讀卡器啟動時關掉

同一個短配方（新版 UI、`TestCards-20261118`、逐張開不同的卡、每張停 6 秒；`dwell.sh` 只開卡），每趟最多 40 或 60 張：

| 條件 | stage | 結果 |
|---|---|---|
| 預設（`r.RDG.ParallelExecute=2`） | `EFork1119u` | 第 9 張當（前一節） |
| 啟動參數 `-ini:Engine:[ConsoleVariables]:r.RDG.ParallelExecute=0` | `EFork1119u` | **40 張不當**（482 秒） |
| 同上，第二趟 | `EFork1119u` | **60 張不當**（724 秒） |
| `r.RDG.ParallelExecute=1`（並行、但等所有工作做完） | `EFork1119u` | 第 5 張當（57 秒） |
| DreamGUI 自己的 RDG pass 全加 `ERDGPassFlags::NeverParallel`，其餘預設 | `EFork1119v` | 第 17 張當（359 秒）；改動已撤回 |
| 讀卡器畫面開啟時由程式設 `r.RDG.ParallelExecute 0`（log 確認 `LastSetBy: Code`、frame 0） | `EFork1119w` | 第 6 張當（241 秒）；改動已撤回 |
| 同一個 `EFork1119w`，改用啟動參數設 0 | `EFork1119w` | **60 張不當**（741 秒） |

**結論**：引擎的 RDG 並行執行是必要條件；只讓 DreamGUI 自己的 pass 不並行不夠，並行的是畫面其他 pass。從啟動參數就關掉的三趟共 160 次開卡都沒當；同樣的值改成讀卡器開啟時由程式設，照樣當。引擎每建一個 graph 都重讀這個值（`RenderGraphBuilder.cpp`），兩者的差別應該在讀卡器開啟前就已經跑過的幾幀（例如 D3D12 並行命令 context 在那時建好），還沒查證。哪一個並行 pass 和 DreamGUI 的繪製互相干擾，仍未找到。

**修正（暫時的防護，不是根因）**：`Tools/run_card_reader_development.lua`（`CardReaderDevelopment.cmd` 與 ok-game-mcp 的 `reader_launch` 都走它）開新版畫面時加上 `-ini:Engine:[ConsoleVariables]:r.RDG.ParallelExecute=0`；`-LegacyReader`（不論放在 `--` 前後）不加，`-ParallelRDG` 保留引擎預設（重現與追根因用）。讀卡器只有一個角色，關掉並行執行的成本小。

資料：`E:\OpenKoikatsu\Saved\Reports\reader-dwell-noparallel-20261119\`、`reader-dwell-pe0b-20261119\`、`reader-dwell-pe1-20261119\`、`reader-dwell-neverparallel-20261119\`、`reader-dwell-fix-20261119\`、`reader-dwell-fixini-20261119\`。

## 防護的驗收與對照（2026-11-19，e-cardload-physics）

**結論：在 `r.RDG.ParallelExecute=0` 的條件下，兩趟 ×30 張未再重現；真因仍未找到。這是迴避措施，不是修復。**
同一份配方、同一個樹（`804306bad` 之後）把防護拿掉，**第 15 張就當**，崩潰簽章和先前三次一模一樣。
所以「關掉 RDG 並行執行」確實是迴避成功的原因，不是被別的改動壓掉的——真因還在，只是被繞過。

| 趟 | 條件 | 卡數 | 結果 |
|---|---|---|---|
| 先前三次 | 引擎預設並行 | — | 當在第 **6／12／13** 張（1～4 分鐘內） |
| 1 | `-ini ... r.RDG.ParallelExecute=0`（`reader_launch`，lane `e-pf1`） | 30 | 乾淨 |
| 2 | 同上（lane `e-pf2`） | 30 | 乾淨 |
| 對照 | `-ParallelRDG`（引擎預設，lane `e-pf3`） | 15 | **當**：第 15 張開完、停留中 |

兩趟乾淨的那 60 次都是真的開卡：log 裡各 30 次 `ok.ReaderScreen notice: 已加载3D`。
防護生效的證據：命令列有那個 `-ini`，log 第 0 幀 `LogConfig: Set CVar [[r.RDG.ParallelExecute:0]]`，
主控台查 `r.RDG.ParallelExecute = "0" LastSetBy: SystemSettingsIni`（引擎預設是 2）。對照那趟 log 裡**沒有**那一行。

### 對照那趟的崩潰細節（給追根因用）

- 日誌 `Saved/Logs/CardReader/20261119-082405-73d69668.log`，Aftermath dump `Saved/Logs/D3D12.0.2026.11.19-08.27.05.nv-gpudmp`。
- `Status: PageFault`、`Type: AddressTranslationError`、`Access: Read`、`Engine: Graphics`、
  `Client: GraphicsProcessingCluster`、`GPU VA 0x000000257a8e1000`、`Resource: <no info>`、`Engine Reset: True`。
- **Active Shaders 只有一個**：`Type = Pixel`、`Function = MainPS`、`Shader Hash E6753E1EA9F1F20775D8BC0AD963B1EF`、
  Aftermath hash `7159920291841742735`；`Shader GPU PC Address: fragment_02 @ 0x00045f90`（和先前三次同一個位址）。
- `Found 0 active tracked resources in 16.00 MB range`、`0 active heaps`、
  `0 released resources containing the page fault address during last 100 frames`、`DRED: No PageFault data.`
  ——頁錯位址**不在任何還活著或最近釋放的資源裡**，所以不是「用到剛釋放的貼圖」那種單純的 UAF，
  比較像描述子／bindless 讀到一個從來沒對應過的位址。
- 飛行中的 breadcrumb 全是 `[Not Started]` 的 DreamGUI 繪製鏈：
  `DreamUIDraw main=DreamUIDynamicSpriteAtlasData_Texture_0|DreamUIPreset_WhiteSolid font=DreamUIFontData_DistanceField_Texture_0`
  → `DreamUIData widget=DreamUIDataTexture_6 clip=DreamUIDataTexture_3`
  → `DreamUIMore rect=DreamUIDataTexture_4 paint=DreamUIDataTexture_1 mask0=fallback`。

### 那條 cvar 誰設的、什麼時機、會不會還原

- **誰**：只有 `Tools/run_card_reader_development.lua:148`。`Config/*.ini` 沒有，C++／Rust 沒有任何地方讀寫它，
  `SceneEditor.cmd`／`StreetSocial.cmd`／`CrowdRoom100.cmd` 都沒有（全專案另一處是 DreamGUI 自己的 RHI 自動化測試，它自己設組合）。
- **時機**：行程啟動、第 0 幀的命令列 ini 覆寫，**在引擎開始算圖之前**。這就是它有效、而由程式在開畫面時設無效的原因。
- **還原**：**不會**，沒有任何程式碼重設它，是那個行程一輩子的值。
  因此有一個真實的洩漏面：讀卡器行程**自己**可以進 OK Studio（`reader_call studio enter`）與一對一（`bEnterInteractionAfterLoad`），
  在同一個行程裡那兩個畫面也是在 `ParallelExecute=0` 下跑的。各自用自己的 `.cmd` 啟動時不受影響。
  要「只關讀卡器畫面」就得離開時設回去，但照上面量到的不對稱，**由程式設回去恐怕也不會讓平行執行真的回來**，要先驗再寫。

### 四格實驗：只有「算圖開始之前就設好的值」擋得住（2026-11-19，e-cardload-physics）

同一份配方（新版畫面、`E:\OKPackage\TestCards-20261118`、逐張開不同的卡、每張開完停 6 秒）跑四種條件：

| 格 | 條件 | 結果 |
|---|---|---|
| 1 | **啟動時** `-ini ... r.RDG.ParallelExecute=0` | 兩趟 ×30 張**乾淨** |
| 2 | 啟動時平行開著（`-ParallelRDG`），**執行中**設 `0`（確認讀回 `2`→`0`） | **當，第 7 張** |
| 3 | 啟動時 `0` → 進 OK Studio（還原成 `2`）→ 回讀卡器（關回 `0`，每步都讀值確認） | **當，第 4 張** |
| 4 | 啟動時不設（引擎預設 `2`） | **當，第 15 張** |
| 4′ | e-fork-2 量的：啟動時 `0`、**執行中**設 `2` | **當，第 11 張** |

四格的崩潰簽章完全一樣：`Pixel MainPS`、`Shader Hash E6753E1EA9F1F20775D8BC0AD963B1EF`、
`fragment_02 @ 0x00045f90`、`MMU Fault Error` / `AddressTranslationError`。

**結論（兩條，要分開講）**：

1. **執行中關不掉，執行中開得回來。** 設 `2` 在執行中是有效的（4′ 會當），設 `0` 在執行中沒有保護力（格 2、格 3 都當）。
   所以能擋住的不是「這個 cvar 現在是 0」，而是「**行程開始算圖之前它就是 0**」。
2. 因此 `26e7e91e0`／`340b70e56` 的「進 1 對 1／Studio 還原、回讀卡器再關」在**回程那一段不是真的防護**：
   值寫回去了，保護沒回來（格 3，第 4 張就當）。要有保護只能在**行程啟動時**決定。

**還要小心一件事**：格 1 乾淨、格 4 會當，兩者的差別是「啟動時的值」，**不一定**等於「平行執行本身是機制」。
也可能是那個值在啟動時造成了別的差異（例如並行命令 context／RDG 的 parallel 路徑只在啟動時建起來，
之後設 0 只擋掉一部分派送），而真正踩記憶體的是那條已經建好的路徑。要分辨得從 `MainPS` 那個 shader
怎麼綁那幾張 data texture 的 SRV 下手，不是再多跑幾趟開卡。

資料：格 2 `Saved/Logs/CardReader/20261119-084556-7c116d38.log`、
格 3 `Saved/Logs/CardReader/20261119-084231-097a2ef0.log`、
格 4 `Saved/Logs/CardReader/20261119-082405-73d69668.log` 與 `Saved/Logs/D3D12.0.2026.11.19-08.27.05.nv-gpudmp`。

### 三個模式是不是同一個行程（決定「按行程設」的代價，2026-11-19 查證）

**同一個執行檔，模式在啟動時由參數決定，三個入口各自是獨立行程**：

| 入口 | 行程裡有什麼 | 會不會設那條 cvar |
|---|---|---|
| `CardReaderDevelopment.cmd`／`reader_launch`（`run_card_reader_development.lua`） | 讀卡器畫面（`OKGalleryWidget.cpp:1054` 建 `UOKReaderScreen`，`-LegacyReader` 則不建） | **會**（唯一一處） |
| `SceneEditor.cmd`（`run_scene_editor.lua`） | 只有 Studio（空地圖＋`AOKStudioGameMode`），不建讀卡器畫面 | 不會 |
| 街區 stage（`StreetSocial.cmd`） | 街區＋從街區進的 1 對 1（`AOKInteractionMode::EnterCards`），不建讀卡器畫面 | 不會 |

**但讀卡器那個行程可以在執行中切進另兩個模式**，而且是同一個行程（不是另開 exe）：
- OK Studio：`OnEnterOkStudio()`／`reader_call studio enter`——實測同一個 pid，cvar `0→2→0`。
- 1 對 1：`AOKInteractionMode::EnterReader(Source)` 在同一個 `APlayerController` 上 `CreateWidget`。

**所以「按行程、啟動時設、不還原」的代價只落在「從讀卡器進去的 Studio／1 對 1」**。
街區那條線的 1 對 1（120 FPS 的目標）與單獨開的 `SceneEditor.cmd` 是不同行程、不設那條 cvar，**完全不受影響**。
要量代價，量的對象就只有「從讀卡器進 1 對 1／Studio」這一種用法。

## 代價：從讀卡器進的 1 對 1，RDG 串行對平行的 FPS（2026-11-19，e-fork-2）

條件：stage `EFork1119u`（`4dabc065a`）、1600×1000 視窗、RTX 5090、slot 獨佔；同一張卡（`E:\OKPackage\TestCards-20261118` 第 2 張，Ahri）、從讀卡器「進入1對1互動場景」、等 30 秒、按「站立愛撫」、等 15 秒，再 `startfpschart`／`stopfpschart` 20 秒。0 與 2 交錯各跑兩趟，每趟重開行程（只有啟動時的值有意義）。

| 啟動參數 | 趟 | 平均 FPS | 遊戲執行緒 | 算圖執行緒 | GPU | 120 FPS 錯過 |
|---|---|---:|---:|---:|---:|---:|
| `r.RDG.ParallelExecute=0`（讀卡器現行） | 1 | 82.46 | 12.11 ms | 5.05 ms | 3.51 ms | 31.3 % |
| 同上 | 2 | 87.08 | 11.47 ms | 4.60 ms | 3.40 ms | 27.4 % |
| 不設（引擎預設 2） | 1 | 87.72 | 11.39 ms | 4.26 ms | 3.12 ms | 26.9 % |
| 同上 | 2 | 84.56 | 11.82 ms | 4.43 ms | 3.48 ms | 29.5 % |

- **平均：0 是 84.8 FPS，2 是 86.1 FPS，差約 1.5 %，比同條件兩趟之間的差（約 5 %）還小**，在雜訊內。遠低於協調者設的 10 % 門檻。
- 這個場景卡在遊戲執行緒（11.4–12.1 ms），不是算圖。串行讓算圖執行緒多約 0.5 ms（4.3–4.4 → 4.6–5.1 ms）、GPU 多約 0.15 ms，都還在 8.33 ms 預算內。
- 所以等遊戲執行緒優化到 120 FPS 時，算圖執行緒 5 ms 左右仍不會是瓶頸。但若之後遊戲執行緒降到 5 ms 以下，這 0.5 ms 才會開始算數，到時要重量。
- 只影響從讀卡器進的 1 對 1／Studio；街區的 1 對 1 與 `SceneEditor.cmd` 是不同行程，不受影響。
- 原始資料：log `E:\OpenKoikatsu\Saved\Logs\CardReader\fps1on1-p0b.log`、`fps1on1-p0c.log`、`fps1on1-p2b.log`、`fps1on1-p2c.log`（`LogChartCreation` 那段）。

順手看到的（未處理）：從讀卡器進 1 對 1 時，讀卡器的 DreamGUI 畫面沒有藏起來，疊在 1 對 1 的 UMG 介面底下（`OKInteractionMode.cpp` `EnterReader` 只把 UMG controller 設成 Collapsed）。

## 外觀縮圖快取的上限（2026-11-19，e-fork-2）

選圖頁的縮圖依檔案路徑快取，原本只增不減：開第 1 張卡後 88 張，開滿 30 張卡後 448 張、102 MiB。它和 PageFault 無關（當機時它是 0）。現在預設 `ok.AppearanceThumbCacheMax 128`（四頁，每頁 32 格），用 LRU 淘汰；設 0 是不設上限。淘汰只是從快取拿掉，畫面上還在顯示的格子會繼續持有自己的貼圖。`ok.ReaderScreen resources` 多了 `decodes=`，記從檔案解碼了幾次，也就是快取沒命中的次數。

量測：stage `EFork1119t`。開卡後依序走過眉毛、眼睛、髮型、飾品四頁，再到髮型往後翻 6 頁、往前翻 6 頁：

| 時點 | 快取張數 | MiB | 累計解碼 |
|---|---:|---:|---:|
| 四個選圖頁各看一頁 | 128 | 8.5 | 128 |
| 髮型往後翻 1～6 頁 | 128 | 8.5 → 50.3 | 160 → 281（每頁 +29～32） |
| 往前翻 1～4 頁（最近四頁內） | 128 | 50.3 | 281（**沒有重新解碼**） |
| 往前翻第 5、6 頁（超過四頁） | 128 | 33.9 → 10.9 | 313 → 345（每頁 +32） |

- 張數封頂在 128。沒有上限時，同一趟會留住全部 281 張，開 30 張卡後是 448 張、102 MiB。
- MiB 隨內容浮動：後面幾頁的髮型縮圖比較大張。
- 加上限的風險是捲動、翻頁時一直重新解碼。量到的是：**最近四頁內來回翻不會重新解碼**；只有翻回四頁以前，才會每頁重新解碼一次（32 張）。這和第一次看到那頁的成本一樣，不會在同一頁上反覆解碼。

## 完整驗證：使用者回報的清單（2026-11-19，新版 UI，打包版）

條件：stage `EFork1119t`（含 `4dabc065a` 與縮圖上限），以 `CardReaderDevelopment.cmd` 的參數（`r.RDG.ParallelExecute=0`、`-OKPhysics=verlet`）啟動，卡片 `E:\OKPackage\TestCards-20261118`，遊戲目錄用 `D:\XKoikatuSunshine`，全程用 MCP（`ok.ReaderScreen`、`reader_call`、`ui_mouse`）操作。結果在 `E:\OpenKoikatsu\Saved\Reports\reader-fullcheck-20261119\`（`results.txt`、`results2.txt`、`results3.txt`），截圖在 `E:\OpenKoikatsu\Saved\OKControl\shots\56548-*.png`，log 在 `E:\OpenKoikatsu\Saved\Logs\CardReader\fullcheck-t.log`。

| # | 項目 | 結果 | 怎麼驗的 |
|---|---|---|---|
| 1 | 卡片選擇要有縮圖 | 通過 | 人物卡總欄截圖（`56548-0001.png`、`-0025.png`）：30 張卡，看得到的格子都有縮圖與名字。`state` 的 `thumbs=0/30` 是剛切頁時取的值，截圖時已經畫上 |
| 2 | 設定裡能設遊戲目錄，指錯會大聲講 | 通過 | `gameroot D:/NoSuchGameFolder`：回 `mods=no zipmods=0`；**設定／介面›遊戲目錄**頁顯示「✗ 設定的遊戲目錄不存在：D:/NoSuchGameFolder」（`-0002.png`）。改回 `D:/XKoikatuSunshine`：`mods=yes zipmods=7296` |
| 3 | 眉毛、眼睛、髮型、飾品能選材質與模型 | 通過（顯示問題已修，見下） | 四個選圖頁都有圖片格（眉毛 257 項、髮型 306 項、飾品 2225 項）。按眉毛「類型 3」、髮型「類型 3」、飾品「類型 5」，各自觸發重新載入（`OK load3d result ok=1`），格子上標 ▸，模型跟著換（`-0021`～`-0024.png`）。**顯示問題**：套用後眉毛、髮型頁上方的說明仍寫「目前是「」：來源缺失，這台沒裝 mod（無 GUID）」，和已標 ▸ 的格子不一致 |
| 4 | 眼睛三頁 | 通過 | 臉›眼部縮放2（18 個控制項）、臉›眼睛（285）、臉›瞳孔覆蓋貼圖（15）都打得開、有內容（`-0011`～`-0013.png`）；內容細節前面「臉›眼部縮放2」一節另驗過 |
| 5 | 視角不按左鍵不轉 | 通過 | `ui_mouse` 不按鍵在 3D 視窗移動四個點，前後 `ok.ReaderScreen look` 都是 `yaw=0.00 pitch=0.00 distance=478.8`、`last_change=none` |
| 6 | 換卡不會把上一個角色的物理套上去 | 通過（參數層） | 卡 C（Hayase Yuuka）原本 `bustSoftness 0.62／bustWeight 0.642`，改成 1／1；開卡 D 讀到 D 自己的 0.30／0.64；再開回 C，讀到卡上的 0.62／0.642，不是 1／1。Session 裡實際套用的物理值讀不到，所以只驗到參數層 |
| 6b | 開卡失敗時退掉舊模型 | 通過（讀卡失敗這一支，見下） | `reader_call load` 給壞卡，MCP 在開卡前就拒絕（`Card could not be read`），沒有走到開卡流程；測試卡資料夾裡沒有壞卡。沿用前面「開卡失敗時的畫面」一節的驗證 |
| 7 | log 零 Error（打包版） | 通過 | 整趟（含 4 次選圖套用、4 次開卡、遊戲目錄指錯又改回）`Error:` 0 條、Fatal／Ensure 0 條；Warning 72 條，未逐條分類 |

要補的兩條已補（2026-11-19 09:35，stage `EFork1119s`，`E:\OpenKoikatsu\Saved\Reports\reader-twofix-20261119\results.txt`）：

- **#3「目前是…」**：原因是說明讀的是外觀目錄的 `current`。那是讀目錄時卡片上存的值，套用之後不會重讀。▶ 標記讀的則是剛套上的（`AppearanceSelectedKeys`）。資料端的 `current_card_stale` 是同一類問題。現在說明以剛套上的為準，並附上套用前的值。實測：眉毛套用「類型 2」後顯示「目前是「タイプ３」（剛套用，第 1 頁，名稱前標 ▶；套用前是「タイプ１０」）」，和 ▶ 一致（`68036-0003.png`）。格子上的「類型 N」是編號，「タイプ…」是遊戲自己的名字，兩者差 1 是原作命名。
- **#6b 開卡失敗**：卡片資料夾只放三張卡（`crowd_C001`、`kks_broken_test`、`kks_haruno_chika`）。先開 Alice，再開壞卡：上方紅字「讀不到這張角色卡：kks_broken_test.png／invalid face png length」，卡片牆那格標「開不了」；**名牌、卡片牆的 ▸、模型三者都還是 Alice**，一致（`68036-0004.png`）。壞卡在讀卡階段就失敗，所以選取沒有換，舊模型留著是對的。「卡讀得到但 3D 載入失敗、退掉舊模型」那一支，這三張卡觸發不到，沿用前面「開卡失敗時的畫面」一節的驗證。
- **e-cardload 回報的 `press` 假成功（2026-11-19 10:00 更正）**：
  - **可見性**：`81f4ae9b8` 只看控制項自己的 `GetShown()`，抓不到收起的抽屜和別的分頁，因為隱藏是在上層做的。e-cardload 重驗時整份 `controls` 沒有一個 `[not shown]`。現在改看 `UOKDreamControl::IsOnScreen()`：自己和每一層父元件都要顯示、而且在階層裡啟用。實測（stage `EFork1119q`）：166 個控制項中 97 個標 `[not shown]`，都是收起的「動作與表情」「左右手動作」抽屜裡的；對其中一個 `press`／`set` 回 `not pressed: … is not shown now` 加 `failed`。停用的那一支 `81f4ae9b8` 已經有效（e-cardload 驗過）。
  - **進 1 對 1**：e-cardload 更正了原本的病例。這顆按鈕沒有分頁條件；卡片還在載入時按，會記下來、等 3D 載完才進（`bEnterInteractionAfterLoad`），也算成功。它原本按了沒反應，是 `81f4ae9b8` 之前的 build。現在 `EnterReader` 每種拒絕都講原因。原本「已經在 1 對 1 裡」只看 `InteractionWidget`，從讀卡器進的 1 對 1 用的是另一個 controller，所以一直沒擋到；現在改看場景裡有沒有還在進行的 `AOKInteractionMode`。實測：進 1 對 1 後再按一次，`notice=沒有進入 1 對 1：已經在 1 對 1 裡。`，log 有 `OK enter one-on-one refused`。
  - **語義**：`press` 回 `pressed` 表示按鈕確實被按到了。按鈕背後的動作有沒有成立，看 `notice=`（拒絕會寫在那裡）或該動作自己的 log；`press` 不會替每顆按鈕判斷結果。
  - 驗這類 UI 改動要建 `OpenKoikatsuEditor`：`reader_launch` 跑的是 `UnrealEditor.exe`（e-cardload 踩到）。
- 整趟 log 0 個 Error。

### PageFault 防護的限制：同一張 GPU 上有第二個 Unreal 遊戲時擋不住（e-cardload 2026-11-19）

e-cardload 對照了時間點：它所有乾淨的趟都是機器上只有它一個 Unreal 的時候，包括讀卡器自己 30 張 ×2、讀卡器→Studio→回來同一行程累計 60 次。會當的三趟都在 09:12 之後，當時這邊的量測 stage（pid 56548）也在同一張 GPU 上跑：

- 讀卡器→1 對 1→回來：第 9、第 17 張當。
- **純讀卡器、不進任何模式：第 12 次開卡當。**

四趟簽章都一樣（`E6753E1E…`、`fragment_02 @ 0x00045f90`）。所以：

- `4dabc065a` 在安靜機器上擋得住，但同一張 GPU 上有另一個 Unreal 遊戲時擋不住。這也符合「真因未解，這只是迴避」。
- 之前「1 對 1 回程是洞」的結論有這個混淆變數，**撤回**。「安靜機器 + 1 對 1 回程」這一格，e-cardload 排時段補量，量到之前不改 1 對 1 的路徑。
- 以後量這條線，先確認機器上只有一個 Unreal。

**迴避措施的成立條件**（寫給之後看這條的人）：

- **有效**：機器安靜，同一張 GPU 上只有這一個 Unreal 行程，而且行程以 `r.RDG.ParallelExecute=0` 啟動。
- **無效**：多個 Unreal 行程共用同一張 GPU（另一組的遊戲、編輯器 -game、量測 stage）時，照樣會當，簽章不變。
- **新線索，也是追真因的起點**：這次的兩個開關（RDG 並行、另一個行程）都只改變 GPU 上的提交時序和競用，不改 DreamGUI 綁定的資源。所以真因很可能和 **GPU 競用、命令提交的時序**有關：某個讀取在別的工作插進來時，讀到一個尚未對應或已經換掉的位址。追查時，可以拿「第二個 Unreal 行程」當觸發條件，比停幾秒等它更快、更穩定重現。
- **先前「乾淨」的驗證要打折**：如果當時機器上有別組的遊戲在跑，它們本來就比較容易當，反過來也一樣。不知道當時有幾個 Unreal 的趟，不能當作有效或無效的證據。**以後驗這條，先確認 `unreal processes: 1`**（`C:\portable\OpenKoikatsu\Tools\lua\lua.exe C:\portable\OpenKoikatsu\Tools\unreal_slot.lua` 不帶參數執行，看 `unreal processes:` 那行），寫進結果。


## 定稿：兩條獨立的觸發路徑，迴避措施的成立條件（2026-11-19，e-cardload-physics）

**迴避措施（非修復）**：`r.RDG.ParallelExecute=0` 必須在**行程啟動、算圖開始之前**設好，之後不還原
（`4dabc065a`）。執行中才設 0 沒有保護力，執行中設回 2 則平行真的回來。

**有效**（每格開跑前後都確認 `unreal_slot.lua status` 的 `unreal processes: 1`）：

| 流程 | 結果 |
|---|---|
| 讀卡器自己，啟動時設 0 | 30 張乾淨 ×2 |
| 讀卡器 → **OK Studio** → 回讀卡器 | 同一行程累計 **60 次開卡乾淨** |

**無效——兩條互相獨立的觸發路徑**：

| 觸發 | 機器 | 結果 |
|---|---|---|
| 執行中才設 0（啟動時平行開著） | 安靜 | 第 7 張當 |
| 進出模式時切換還原（`26e7e91e0` 的舊設計） | 安靜 | 第 4 張當 |
| **讀卡器 → 1 對 1 → 回讀卡器** | **安靜** | **第 10 張、第 9 張當（兩趟）** |
| **純讀卡器，不進任何模式** | **忙：同一張 GPU 上另有一個 Unreal 遊戲** | 第 12 次開卡當 |

後兩條是**各自獨立**的：1 對 1 回程在安靜機器上也當（所以不是機器忙造成的），而機器忙的時候
連碰都沒碰 1 對 1 也當（所以也不是 1 對 1 造成的）。Studio 回程與 1 對 1 回程的差別尚未解釋——
兩者都沒有動那條 cvar（全程讀回 `0`），所以破壞保護的是 1 對 1 進出動到的**其他**東西。

所有命中的簽章相同：`Pixel MainPS`、`Shader Hash E6753E1EA9F1F20775D8BC0AD963B1EF`、
`fragment_02 @ 0x00045f90`、`MMU Fault Error` / `AddressTranslationError`，頁錯位址不在任何活著或
最近 100 幀釋放的資源裡。**真因仍未找到**；「多個 Unreal 共用 GPU 就擋不住」是指向 GPU 競用／提交時序的新線索。

**量這條時的硬規矩**：每一格開跑前後都要記 `unreal_slot.lua status`（`unreal processes` 與 slot 持有者），
各格必須在**同一種機器狀態**下跑。2026-11-19 就有一次把「機器上多了一個別組的遊戲」誤判成
「1 對 1 回程有洞」（`Docs/ERROR_LOG.md` 同日那條），救回來靠的是一格「不含那個流程」的對照。

### 排查表：自動化按鈕時的假成功（2026-11-19 更新，`81f4ae9b8` 之後重驗）

- **`press` 碰到停用的控制項已經不再回 `pressed`**（`81f4ae9b8`）：回
  `not pressed: <路徑> is disabled` ＋ `failed`，`controls` 列表也在那一行後面標 `  [disabled]`。
  實測：`press 動作與表情›眼睛開合›Slider`（當下停用）→ `not pressed: … is disabled`。
- **`[not shown]` 也補上了**（`dbb0674ba`，我重驗過）：原本只看控制項自己的 `GetShown()`，
  收起的抽屜裡的控制項因此一個都沒標到；現在連每一層父元件一起看（`IsOnScreen`）。
  實測整份 `controls` 有 110 行標 `[not shown]`，`press 動作與表情›嘴巴開合›Slider`（收起的抽屜裡）→
  `not pressed: … is not shown now` ＋ `failed`。
- **「進入1對1互動場景」的前置條件沒有分頁這一條**（我先前在這裡寫成「要在編輯分頁」是錯的，已更正）：
  重驗時從「人物卡」分頁按它一樣進得去；而且**卡片還在載入中就按也會成功**——它會記下來、等 3D 載完才進去
  （`bEnterInteractionAfterLoad`）。真正會被拒的是選到男性卡、已經在 1 對 1 裡、或編輯還沒套用，
  那時畫面與 notice 會寫「沒有進入 1 對 1：<原因>」、log 有 `OK enter one-on-one refused`（`81f4ae9b8`）。
  我先前兩趟按了沒反應是 `81f4ae9b8` 之前的舊 build。
- **所以規矩不變：`pressed` 只表示那顆按鈕真的被按到，按鈕背後的動作有沒有成立要看 notice。**
  進了 1 對 1 要看 log 的「OK pair 背景載入男性角色」或 `ui_widgets` 裡有沒有「離開（回到讀卡）」，
  被拒則看 notice 的「沒有進入 1 對 1：<原因>」。實測（`dbb0674ba`）：卡片還在載入中按 → 回 `pressed`、
  當下什麼都沒發生，**3D 載完才真的進去**；進去之後再按一次 → notice「沒有進入 1 對 1：已經在 1 對 1 裡。」
  ＋ log `OK enter one-on-one refused`。**查證時要等那一步做完再判斷**——我就差點把「按完立刻查、還沒進去」
  當成新的靜默失敗回報出去。
- 同理，`reader_call` 回 `"status": "applied"` 不等於那張卡真的開了：`load` 吃的是 `path`，而
  `state` 的 `card` 跟著**選取的那一列**走，不是跟著剛才載入的路徑走。一趟開卡配方到底開了幾張，
  看 log 裡 `ok.ReaderScreen notice: 已加载3D` 的次數最準。

## 1 對 1 回程會當、Studio 回程不會：差集與第一輪盤點（2026-11-19，e-fork-2，進行中）

e-cardload 在安靜機器上量到：讀卡器→Studio→回來，同一行程累計 60 次開卡乾淨；讀卡器→1 對 1→回來，兩趟分別在第 10、第 9 張當。兩條路徑全程 `r.RDG.ParallelExecute` 都是 0。所以「進 1 對 1 有做、進 Studio 沒做的事」就是嫌疑範圍。

### 差集（從程式讀出來的：`AOKInteractionMode::EnterReader`／`Exit` 對 `UOKCharacterController::OnEnterOkStudio`／`OnOkStudioStopped`）

| # | 1 對 1 有、Studio 沒有 | 離開時怎麼收 |
|---|---|---|
| 1 | `Session.CloneForInteraction` 複製一份女角 session，生一個新的 `AKKPreviewActor`（`LoadingFemale`）重建她的網格、材質、貼圖 | `Exit`：`LoadingFemale->Destroy()`；`OwnController` 時把共用 controller 的 `PreviewActor` 也 Destroy |
| 2 | 背景載入男角（`OK pair 背景載入男性角色`），第三個角色的貼圖與材質 | 同上（`OnStopPair`） |
| 3 | 另建一個 `UOKCharacterController`（`Shared`，UMG）＋ 1 對 1 的 H 面板 UI，疊在讀卡器的 DreamGUI 畫面上；讀卡器的 DreamGUI 畫面**沒有藏起來**，整段都在畫 | Shared 隨 Mode 結束 |
| 4 | 配對播放（`AKKPairedPlayback`）接管兩個 actor 的 Tick、雙角色接觸求解、`AddPairPhysics` | `RemovePairPhysics`、`OnStopPair` |
| 5 | H 場景的附加物：油漆水槍 `AOKPaintSprayer`（兩張 render target）、鏡子、水窪、液體、`SceneCaptureComponent2D` 多 4 個 | 隨 Mode／場景物件結束 |
| 6 | `r.Shadow.DistanceScale` 在 1 對 1 期間改掉 | `Exit` 以 `SetByConsole` 設回 |
| 7 | 規則 DLL（`ok_rules`）與對話（`FOKReaderTalk`，沒有 API key 時只是錯誤訊息） | `ReaderTalk->End()` |

Studio 這邊：只把讀卡器的 actor 藏起來、在原地開 Studio 場景、加一個角色；關掉時把 actor 顯示回來。

### 第一輪盤點：回來之後還留著什麼（stage `EFork1119q`，機器上只有這一個 Unreal）

每個時點先 `obj gc`，再數物件與 `ok.ReaderScreen resources` 的 transient 貼圖（`E:\OpenKoikatsu\Saved\Reports\reader-leftover-20261119\`、`reader-leftover2-20261119\`）：

| 時點 | KKPreviewActor | OKCharacterController | OKInteractionMode | PaintSprayer | RenderTarget | SceneCapture | Texture2D(transient) |
|---|---:|---:|---:|---:|---:|---:|---|
| 讀卡器、卡 2 | 3 | 1 | 0 | 1 | 2 | 3 | 115 張／284.7 MiB |
| 在 1 對 1 裡 | 5 | 2 | 1 | 2 | 4 | 7 | 162／437.4 MiB |
| **從 1 對 1 回來** | 3 | 1 | 0 | 1 | 2 | 3 | **158／437.3 MiB** |
| （另一趟）從 Studio 回來 | — | — | — | — | — | — | 127／238.0 MiB（進 Studio 前 124／237.8） |

- **物件都回到原數，但 transient 貼圖多留了 43 張、約 150 MiB**；Studio 回程只多 3 張、0.2 MiB。
- 用 `obj refs` 看最新建的幾張：持有者是讀卡器現存的 `KKPreviewActor` 的 `Parts`（refcounted），而且同一張貼圖同時掛在兩個 actor 上（讀卡器目前的角色和另一個常駐的 actor）。也就是說，1 對 1 期間建的貼圖，回來後被讀卡器自己的 actor 接手了，不是沒人要的孤兒。
- 下一張卡開完，transient 降到 145／352.8 MiB：這些貼圖在之後的開卡中**陸續被放掉**。
- **同一趟在「從 1 對 1 回來」之後的第 2 張卡就當了**，簽章和其他趟一樣（PageFault、唯一的 Active Shader 是 `MainPS`，Shader Hash `E6753E1EA9F1F20775D8BC0AD963B1EF`）。log `E:\OpenKoikatsu\Saved\Logs\CardReader\leftover-q.log`。這是目前最快的重現：進一次 1 對 1、出來、開兩張卡。

### 第二輪（2026-11-19 10:15）：那 43 張是快取，不是洩漏；「第 2 張就當」不是穩定重現

- **43 張的歸屬**：從 1 對 1 回來後下 `ok.KeptTexturesClear`，transient 貼圖從 158 張／437.3 MiB 降到 118 張／288.7 MiB，少了 40 張、約 149 MiB。所以它們是 `KKRuntimePose` 的 `RecentRuntimeTextures`（e-cardload 的 kept 快取，預算 512 MB）照設計留下的。換卡時會先標 stale，開完再放掉；log 有 `OK kept GPU textures: released 61 (197.5 MB) from the card just left`。「之後隨開卡陸續放掉」就是這條路徑，不是 1 對 1 漏放。
- **重現率**：同條件的對照趟（stage `EFork1119q`，單一 Unreal，進 1 對 1 待 30 秒、出來，再開 10 張、每張停 6 秒）**10 張都沒當**。上一輪「第 2 張就當」只是單一一趟，不能當作穩定的快速重現。要排除差集，每格得照 e-cardload 的配方跑 30 張、至少兩趟。
- 還沒排除的仍是上面差集的第 1～5 項。可以接著做的 A/B：從 1 對 1 回來後先 `ok.KeptTexturesClear`，再照配方開卡，看還當不當。這能回答「回程留在快取裡的貼圖，被放掉的那一刻是不是觸發點」。

### 下一步（逐項排除）

1. 找出那 43 張是誰建的：第 1 項的複製 session 和讀卡器的 session 共用貼圖快取，最可能。如果是，就是「別的 actor 建的貼圖被讀卡器的 actor 共用，之後隨開卡放掉」。這和 GPU 讀到失效位址的形狀吻合：貼圖放掉時，還在飛行中的幀如果有東西引用它，就會讀到失效位址。
2. 對照實驗，每格用上面的快速重現（進出 1 對 1 一次、再開 10 張）：
   - 進 1 對 1 後**馬上**離開（第 2、5 項還沒開始）；
   - 進去等她載完、不載男角就離開；
   - 照常進出，但離開時先把讀卡器的 actor 整個重開一次（不接手 1 對 1 期間的貼圖）。
   哪一格不當，嫌疑就縮到那一項。
3. 第 3 項（讀卡器的 DreamGUI 畫面在 1 對 1 期間沒藏起來，一直在畫）本身也是 bug，要另外修。Studio 期間它是否也在畫還沒確認；如果 Studio 期間是藏起來的，它也要列進差集。


## 計數格：每開一張卡數「還活著幾個」，沒有一項單調增長（2026-11-19 11:02–11:11，e-cardload-physics）

VRAM 只用到 8%，所以凶手不會是「用了多少 MB」，而該是「有多少個還活著的東西」。於是改成**不再排除候選，而是量數量**：
1 對 1 回程之後每開一張卡記四個數——`ListTextures` 的筆數、其中 `/Engine/Transient.Texture2D_*` 的筆數、
`rhi.DumpResourceMemory` 的 **total with info**（活的那個，不是累計的 total tracked）、
`r.DumpRenderTargetPoolMemory` 的筆數。兩格背靠背、同一種機器狀態：**clear**（回程後 `ok.KeptTexturesClear`）與
**noclear**（不清）。原始輸出逐張留檔（`counts/<mode>/<n>.tex|.rsc|.rtp`），下面的數字可以重抽。

| 卡號 | clear：tex／transient2d／total with info | noclear：tex／transient2d／total with info |
|---:|---|---|
| 1 | 341／215／2211 | 341／215／2220 |
| 2 | 416／290／2227 | 416／290／2235 |
| 3 | 473／347／1611 | 240／121／1619 |
| 5 | 410／291／2074 | 410／291／2073 |
| 8 | 559／440／2786 | 559／440／2783 |
| 10 | 657／538／3157 | 661／542／3164 |
| 11 | **693／574／3290** | 261／142／1724 |
| 12 | 262／143／1677 | 318／199／1889 |
| 14 | 431／312／2203 | 472／353／2408 |
| 15 | 482／363／2434 | **當機**（`faults=1`） |
| 18 | **675／556／3371** | － |
| 19 | 320／201／1877 | － |
| 24 | 651／532／3054 | － |
| 25 | 345／226／1975 | － |
| 30 | 616／497／3230 | － |

**結論：沒有一項單調增長。**

- **render target pool 的筆數是平的**：clear 全程 43 筆、noclear 全程 41 筆，一張卡都沒變。
- **貼圖筆數是鋸齒**：連開幾張往上爬（峰值 693／574），然後掉回起點（262／143），再爬。掉回**不是 kept 釋放**——
  同期 `OK kept character textures` 一直在 54～147 件、108～509 MB 之間上下，每換一張卡就釋放一批，沒有累積趨勢；
  峰值那時有約 450 個**活著但不在 kept 清單裡**的 transient 貼圖 UObject，它們是等 GC 才被收的，掉回那一次就是 GC 掃過。
- **同一張卡在兩格裡的數字幾乎一樣**（341/416/410/559… 逐張對得上），所以這些數量是「**開的是哪張卡**」的函數，
  不是「**開過幾張**」的函數。這就是「不是累積」最直接的證據。
- **當機點和任何一個計數都對不上**：noclear 當在第 15 張，而它前一張的 transient2d 是 353——遠低於同一格第 10 張
  活過的 542，也低於 clear 格活過的 574 與 556。

**順帶推翻我自己之前兩句話**：

1. 這一對裡 **clear 格 30 張全過（`faults=0`）、noclear 格第 15 張當**，看起來像「清快取有用」。但兩格的 kept 水位
   **幾張卡之內就收斂到一樣**（兩格的 `keeping` 峰值都是 147 件／509.3 MB），清掉的只是回程那一批、差異是暫時的。
   所以這個 30 比 15 更可能是趟與趟之間的變異，不是因果——也就是說我 10:18 那句「清了撐久一倍」當噪音看是對的，
   而「kept 不是根因」這個結論在這一對裡仍然站得住。
2. **不能把「不是累積」直接推成「就是兩個 Unreal 搶 GPU」**：這一格機器上只有我一個 Unreal（除了 11:04:59–11:05:45
   f-sceneload 誤開的 46 秒，落在 clear 格第 9～13 列，而那一格反而全過），noclear 格照樣當。所以 1 對 1 回程這條
   單獨成立，和「第二個 Unreal」那條是兩件事，這點和上面「兩條獨立觸發路徑」那節一致。

**被報「可能汙染」之後的查證（2026-11-19）**：e-fork-2 來說它 11:04–11:15 與 11:22–11:38 各開過讀卡器，請我作廢。
對了 log 的時間戳之後**沒有重疊，兩格都不用作廢**：我的 clear 格是 11:02:39–11:07:43、noclear 格 11:07:50–11:10:37，
而它最早那個（`inspect-1000.log`）是 **11:12:17** 起，中間空了 1 分 40 秒（`Saved/Logs/CardReader/<lane>.log` 的第一條與
最後一條時間戳就是那個行程的生命週期，log 裡是 UTC，要 ＋8；比 pid 與記憶都可靠）。那段期間唯一的入侵仍然只有
f-sceneload 誤開的 46 秒。**同儕報來的汙染也要查，不要照收**——照收會白白作廢一趟乾淨數據。

**這一格的量測本身有一個漏洞，記下來**：我只在兩格之前、之間、之後各取一次 `unreal_slot.lua status`，而那三個時間點
正好都是我的讀卡器沒在跑的時候（三次都是 `unreal processes: 0`），所以 f-sceneload 在 clear 格中間誤開的那 46 秒
**我的檔案完全沒抓到**，是對方自己來講我才知道。下一格要**每張卡記一次機器狀態**，和計數寫在同一列。

### 下一格：生命週期旋鈕，以及「旋鈕是定位用的，不是修法」（2026-11-19）

計數格證明不是累積（上一節），而計數是「開的是哪張卡」的函數 ⇒ 不同卡在換卡那一帧要釋放的數量不同 ⇒ 懷疑
**換卡釋放資源的那個窗口裡，DreamGUI 仍持著已經被放掉的 handle**（當機那一刻在飛的 draw 全是 DreamGUI 自己的、
`mask0=fallback`，正是「它要的那張已經不在了」的樣子；而 `r.RDG.ParallelExecute=0` 改的是並行錄製，會把窗口拉寬）。

**兩個旋鈕的名字都要先核過才轉**（協調者憑印象給的兩個，一個不存在、一個不生效；這是「旋鈕沒接上卻以為轉了」
那一類，見 [ERROR_LOG](ERROR_LOG.md) 2026-11-19）：

| 想轉的東西 | 以為是 | 在 UE 5.8 ＋ D3D12 實際是 |
|---|---|---|
| 延後刪除的等待 | `rhi.DeferredDeletionLatency` | **不存在**（`Runtime/RHI` 底下沒有任何 deletion cvar，帶 `DeferredDeletionQueue` 的只有 VulkanRHI）。真正的是 **`D3D12.DeleteQueueMaxEOPTimeDelta`**（`D3D12RHI.cpp:63`，預設 **0.1 秒**）：RHI 執行緒處理刪除隊列時，會為比這個時間差更舊的 EOP 工作停下來等它完成；**0 秒＝完全不等** |
| 關掉命令錄製的並行 | `r.RHICmdBypass=1` | **RHI 執行緒獨立時直接被忽略**（`RHICommandList.cpp:1897`：`(IsInGameThread() \|\| bypass>=1) && !IsRunningRHIInSeparateThread()`），cvar 查起來是 1、行為沒變。要生效得同時 `-norhithread`／`r.RHIThread.Enable 0`，但那也改了執行緒拓樸，只能證明「錄製期＋RHI 執行緒」整包有關，不能單獨歸因錄製期。所以錄製這條改用已驗過的 `r.RDG.ParallelExecute`（0／2）當對照軸，加 `r.RHICmdWidth`（預設 8）調粒度 |

`D3D12.DeleteQueueMaxEOPTimeDelta` 的劑量**不是單調的**，所以三格一起跑才驗得出我們有沒有把語義讀反：
`0.001`＝幾乎所有待刪都算「更舊」⇒ 幾乎每次都停等 ⇒ 最安全；`0`＝完全不等 ⇒ 最危險；
`10`＝幾乎沒有東西算「更舊」⇒ 實際上也幾乎不等 ⇒ **應該和 0 一樣危險**。若 `0.001` 乾淨而 `0` 與 `10` 都更早當，
方向、劑量、兩側都對上；**若 `10` 反而乾淨，就是我們把語義讀反了，結論重來**。

**先講明免得之後走偏：就算 `0.001` 真的擋住了，那個 cvar 不是修法。** 它是用「每次都停等 GPU」換安全，代價直接落在
帧時間上（這個專案還有 120 FPS 的目標）。真正的修法是讓 DreamGUI 在它要用的資源上持住參照，或改走 RDG 自己的
生命週期管理，而不是全域調慢刪除。**旋鈕的價值是定位，不是上線**——看到「設這個就不當了」不要把它塞進啟動參數當解法。

## 「InspectorScroll 捲不到」的重現與全頁掃描（2026-11-19，e-fork-2）

e-cardload 給的條件：

- 編輯器 target 09:43 的建置，1600×1000。
- OK 卡 `alice.png`。當時資訊頁還會把卡內每個 mod 列成「缺少同目錄 zipmod」，31bcc261e 之後才改成一行。
- 結果：「角色資訊」頁長到一百多行，新版畫面看不到尾巴。e-cardload 是用 `-LegacyReader` 才讀到那段字。

**重現**：原作卡仍會列「缺少同目錄 zipmod」。把四張原作卡放在暫存資料夾、不設遊戲目錄開讀卡器，選 `Alice_keiyuu.png`，「角色資訊」頁就有同樣一百多行。stage `EFork1119r`（含 1c5dfbea7）上：

- 1000 高：`ok.ReaderScreen scroll 1` 與滑鼠滾輪（`ui_mouse wheel`）都捲到最後一行（「匯出這套服裝」那一列）。
- 700 高：滾輪一樣捲到底。
- **用現在的程式重現不出來。** 09:43 那個建置為什麼捲不到，沒有再追：那個建置的程式已不在、條件也回不去。

**全頁掃描**：新指令 `ok.ReaderScreen pagefit` 回報目前這頁的四個量：

- 頁面本身的高度；
- 左欄捲動框的可視高度；
- 捲動框允許捲到的距離；
- 結果：頁面比可視高度高、卻捲不到底時標 `MISMATCH`。

腳本照 `pages.json` 逐頁開、等一下、讀 `pagefit`：

- 1000 高、700 高、載入 3D 卡：37 頁都是 `ok`，`MISMATCH` 0。
- 最長的「臉›眼睛」6349，可捲 5542 = 6349 − 可視 806。
- 掃描期間 log 沒有 `GPU crash`。

**視窗高度本身不改變溢出與否**：畫布以 1080 為設計高度、跟著視窗縮放（`ScaleWithScreenSize`，以高度為準）。所以 700 和 1000 的可視高度在設計單位裡一樣（806／850／894／946，依頁首有沒有子選單而不同），頁面高度也一樣，只是整體縮小。會改變的是「顯示字級」（`EditorFontSize`，canvas 參考解析度除以它）：字級放大時，可視高度的設計單位變小。這條還沒掃。

**之後再有人回報「看不到／捲不到」**：先在那一頁跑 `ok.ReaderScreen pagefit`。`MISMATCH` 才是捲動範圍沒跟上；`ok` 但看不到，就是控制項沒被鏡像或被藏起來，查 `controls` 的 `[not shown]`。

## `ui_screenshot {"ui":false}` 會拍到 DreamGUI 面板（2026-11-19，e-fork-2，已修）

- **原因**：`/screenshot` 用 `FScreenshotRequest::RequestScreenshot(檔名, bShowUI)`，`bShowUI=false` 只去掉 Slate（UMG）。DreamGUI 把畫面畫進場景，所以讀卡器的左右面板、相機列都留在圖裡。
- **修法**（`OKGameControl.cpp`）：`ui:false` 時，把 DreamGUI 每個玩家的畫面根（`UDreamScreenUISubsystem` 的 screen root）先藏起來，隔一幀再拍，檔案寫出後（最多 5 秒）再顯示回來。回覆多一個 `dream_screens_hidden`。
- **驗收**（stage `EFork1119r`，同一畫面 `ui:true`／`ui:false` 各一張，`E:\OpenKoikatsu\Saved\OKControl\shots\11172-0001.png`～`0007.png`）：
  - 讀卡器：`ui:false` 沒有任何面板、相機列、通知。
  - 1 對 1：`ui:false` 只剩場景與角色，讀卡器面板、H 面板、字幕都沒有。
  - Studio：`ui:false` 只剩角色，Studio 工具列、gizmo、讀卡器面板都沒有。
  - 拍完再 `ui:true`，面板都回來了。
- **順便看到（另一件，未修）**：`ui:true` 的 1 對 1 與 Studio 畫面裡，讀卡器的 DreamGUI 面板（左欄、相機列、右欄）整段都畫在底下。之前記過「1 對 1 期間讀卡器畫面沒藏起來」，Studio 也一樣。

## `reader_call select N` ＋ 載入3D 載入了上一張（2026-11-19，e-fork-2）

- **f-sceneload 撞到的那次**：真因是 `ok-game-mcp` 的啟動守衛把 `index` 當成未知欄位擋掉，請求沒送到遊戲（f-sceneload 已在 63318f926／b08e9be8b 修好）。讀卡器沒有錯。
- **讀卡器這邊確實有的假成功**：`SelectIndex` 遇到讀不成角色卡的檔案（例如資料夾裡的場景 PNG）時，選取留在原來那張，卻沒有回報。所以 MCP `select` 會回成功，下一次「載入3D」開的是上一張。`ok.ReaderScreen card N` 的格子在忙時按下也一樣。
  - 現在 `select` 會比對選取有沒有真的換：沒換就回 `load_failed`，寫出那張卡為什麼開不了、選取還停在第幾張。
  - `card N` 沒換就回 `not selected: …`（原因或「busy」），不再印 `card=N`。
- **驗收**（stage `EFork1119r`，資料夾三張 OK 卡＋一個非角色卡 PNG）：
  - 非角色卡的 PNG 本來就不進卡片列表（`cards_total 3`）。
  - `select 2 → 1 → 0 → 2`，每次之後 `press 人物編輯›載入3D`，log 的 `OK load3d card=` 都是剛選的那張，`result ok=1`。
- **附帶**：新版畫面下，`ui_press {"label":"載入3D"}` 回 `no such button on screen`（那顆 UMG 按鈕在收起的抽屜裡）。在新版讀卡器裡按「載入3D」，請用 `ok.ReaderScreen press 人物編輯›載入3D`。

### 乾淨基線（獨占、逐張記機器狀態）：當機跟著「峰值」走，而決定峰值的是 GC 有沒有來（2026-11-19 12:21–12:30）

兩格背靠背、同一機器狀態、每張卡都記下機器上的 Unreal 數（全程 `unreal=1`，所以這兩格沒有任何汙染）：

| | GC 掃過幾次 | 峰值 tex／transient2d | 結果 |
|---|---|---|---|
| **clear**（回程後 `ok.KeptTexturesClear`） | **一次都沒有**（第 4～15 張連續爬） | **912／793** | **第 17 張當，`faults=1`** |
| **noclear**（不清） | 3 次（第 14、22、30 張掉回） | 823／704 | **30 張全過，`faults=0`** |

clear 格逐張：`341/215 416/290 481/355` → GC → `331/212 403/284 466/347 503/384 554/435 608/489 650/531 685/566 727/608 818/699 865/746 912/793` → 第 16 張 `tex=0`（`ListTextures` 已經答不出來）→ 第 17 張 `heroine_klara.png` 行程沒了。

**結論要照這個範圍講：GC 時機決定峰值，峰值決定當不當；清 kept 會推遲 GC，所以它讓當機更容易發生。**
機制：清掉 kept 清單等於放掉一批參照、降低記憶體壓力 ⇒ GC 被延後 ⇒ transient 貼圖一路累積到 912 ⇒ 當。
**不要把它寫成「別清快取」**——不清只是運氣好讓 GC 按時來，不是修好了；真正的變數是 GC 時機，而那不是我們
控制的東西。**這同時更正上一節那句「不是累積」**：是累積，只是 GC 通常會先掃掉，前幾趟看到的鋸齒就是被掃掉的樣子。

**還沒解的矛盾（下一格要解的）**：早先量過 `gc.CollectGarbageEveryFrame 1` 照樣在第 12 張當。若峰值論對，每帧 GC 應該讓計數一直很低。所以要嘛那趟計數其實沒降（當時沒量），要嘛峰值只是**同一個原因的另一個指標**。下一格把它重跑並**逐張記計數**。

**當機前 6 秒工具就先失靈**：第 16 張（`heroine_keqing.png`）`04:24:04` 載入成功（`OK load3d result ok=1 已加载3D`），但那一張的 `ListTextures` 回 `tex=0`；`04:24:10` 才 fault。當機前一瞬間的 log 是

```
[04.24.10:177] LogD3D12RHI: Created late shader associations, took 16ms
[04.24.10:199] LogRHICore: Error: Shader debug data not found (7159920291841742735)   ← 連續十餘行
[04.24.10:202] LogNvidiaAftermath: Error: Writing Aftermath dump to: …nv-gpudmp
```

`Created late shader associations` 整趟只出現這一次，就在 fault 前 25 ms。

**bindless 描述子這條（源碼核過，不是憑印象）**：
- 這台的 log：`Bindless is enabled (Configuration=RayTracing). Initializing allocators with 32768 Resource and 2048 Sampler descriptors`。
- 32768／2048 是**引擎自己的 Windows 預設**（`Engine/Config/Windows/BaseWindowsEngine.ini` 的 `[SystemSettings]`），不是本專案設的；cvar 本身的預設是 1,000,000（`D3D12BindlessDescriptors.cpp:10`）。
- **log 裡沒有任何 `ran out of` 或描述子耗盡的警告**，所以不是乾淨的「用光了」，更像是**索引被回收重用**。
- 貼合的旋鈕不是堆大小，而是 **`D3D12.Bindless.GarbageCollectLatency`**（預設 **600**，`ECVF_ReadOnly`，注解：「heap 被釋放前要經過幾個 update cycle」）——描述子的生命週期旋鈕，兩側都能轉：調大（6000）若 30 張全過、調到 1 若更早當，方向與劑量兩側都對上。三個 cvar 都是 ReadOnly，只能啟動參數設。

**DreamGUI 面板在 1 對 1 期間不該畫，這件已經不是候選而是定案**（使用者 2026-11-19 裁定：進 1 對 1 時讀卡器的
編輯器 UI 本來就該隱藏），所以 e-fork-2 的開關預設會變成「不畫」，cvar 只用來還原舊行為跑 A／B。on／off 兩格
還是要跑，但量的是**它能不能解釋當機**，不是「要不要這樣做」。

**工作假設（標明是假設，等 DreamGUI 開關那格的結果）**：讀卡器的 DreamGUI 面板在 1 對 1／Studio 期間**整段還在畫**（e-fork-2 的 `ui:true` 截圖），每帧都要綁貼圖；換卡釋放的那批 transient 貼圖若還沒被 GC 收走、仍掛在 UObject 上，面板綁到的就可能是「已放掉但還沒真刪」的那一份——`mask0=fallback` 正是這個樣子。Studio 期間面板雖然也在畫，但**換卡的釋放不在那條路上**，所以 Studio 回程不當。這是目前唯一能同時容納正反兩面證據的說法。


### 不對稱檢驗：兩條線索衝突時，「Studio 回程不當」當場判勝負（2026-11-19，讀碼核過）

| | Studio 進場 | 1 對 1 進場 |
|---|---|---|
| 讀卡器畫面 | Collapsed | Collapsed |
| **PreviewActor／PartnerActor** | **`SetActorHiddenInGame(true)`**（`OKGalleryOkStudio.cpp:29`，離場 48 還原） | **不藏**——`OKInteractionMode.cpp:72` 是「除了 PreviewActor 與 PartnerActor 以外都藏」，574 行還明確 `SetActorHiddenInGame(false)` |

- **DreamGUI 面板那條過不了這個檢驗**：面板在兩個模式底下都在畫（e-fork-2 的 `ui:true` 截圖 11172-0003／0005），
  但只有 1 對 1 回程會當。**兩邊都有的東西解釋不了只有一邊當。**
- **角色 actor 的可見性正好是那個差集**：Studio 藏、1 對 1 不藏；Studio 回程不當、1 對 1 回程當。而留下來的那批
  transient 貼圖的持有者就是讀卡器現存的 `KKPreviewActor` 的 `Parts`，它們在之後的開卡裡陸續被放掉——
  「沒藏起來的 actor 的貼圖被提交進 draw、稍後被放掉」和 page fault ＋ 唯一 Active Shader 是 `MainPS` ＋
  `mask0=fallback` 的簽章吻合，也和上一節「峰值越高越容易當」一致（活著的 transient 越多，綁到已放掉那一份的機會越大）。

**所以下一格應該是：照 Studio 的做法，在 1 對 1 進場也把那兩個 actor hidden、離場還原，再跑 30 張。** 過不了就排除，
過了就同時拿到根因與修法。（改的是 `OKInteractionMode.cpp` 的 `EnterReader`／`Exit`，不是我的檔案，等協調者裁示。）

**沒核到的一項**：f-sceneload 提到「1 對 1 期間多 4 個 `SceneCaptureComponent2D`」，但 `OKInteraction*.cpp` 裡
grep 不到這個字，所以那部分未經證實，要當證據得先指出是哪個檔案建的。

**這一節本身也是個方法**：手上有兩條都「說得通」的線索時，先找一個**兩條預測不同**的現成觀察（這裡是 Studio 回程），
不必等新實驗就能砍掉一條。

## 1 對 1／Studio 期間讀卡器畫面照畫：改成藏起（2026-11-19，e-fork-2）

- **現象**：進 1 對 1 或 Studio 後，讀卡器的 DreamGUI 面板（左欄、相機列、右欄）整段都畫在那個畫面底下（`E:\OpenKoikatsu\Saved\OKControl\shots\11172-0003.png`、`11172-0005.png`）。但 `press` 與 `controls` 回報它們是 `[not shown]`：**可見性回報和實際繪製不一致**。
- **原因**：兩種模式都把讀卡器的 UMG 控制器設為 `Collapsed`（`OKInteractionMode.cpp` 的 `Source->SetVisibility(Collapsed)`、`OKGalleryOkStudio.cpp` 的 `SetVisibility(Collapsed)`）。`Collapsed` 的 UMG 不跑 `NativeTick`，而讀卡器畫面的 `Tick` 是從那裡呼叫的，所以沒有東西去藏 DreamGUI 畫面。
  - 鏡像控制項的來源是 UMG，UMG 是 `Collapsed`，所以 `IsOnScreen` 回報不顯示；DreamGUI 本身照畫。
- **改法**：讀卡器畫面自己掛一個 ticker，每幀跟著控制器（`UOKReaderScreen::FollowController`）：
  - 控制器 `Collapsed`（別的模式占了畫面）時，整個畫面 `SetShown(false)`，不送繪製；
  - 回到讀卡器時再顯示。log 會印 `ok.ReaderScreen hidden／shown`。
  - **預設就是藏起**（使用者 2026-11-19 裁定：進 1 對 1 時原本的編輯器 UI 就該隱藏）。
- **實驗開關**：`ok.Experiment.ReaderScreenUnderOtherModes`，預設 0（藏）；1 還原舊行為（照畫）。只給當機 A／B 用，不是設定。
  - 執行中下主控台指令就生效。
  - 啟動時設：`-ini:Engine:[ConsoleVariables]:ok.Experiment.ReaderScreenUnderOtherModes=1`。
- **驗收**（stage `EFork1119r`，`E:\OpenKoikatsu\Saved\OKControl\shots\65124-0001.png`～`0003.png`）：
  - 預設進 1 對 1：`ui:true` 截圖底下沒有讀卡器面板，`controls` 全部 `[not shown]`，log `hidden`。
  - 離開：log `shown`，`controls` 不再標 `[not shown]`。
  - 開關設 1 再進 1 對 1：面板照畫，`controls` 也回報顯示中，兩者一致。
  - 開關回 0 進 Studio：底下沒有讀卡器面板，`controls` `[not shown]`。
- **和當機的關係（待 e-cardload 量）**：當機那一刻在飛的 draw 全是 DreamGUI 自己的（`mask0=fallback`），最容易當的是 1 對 1 回程，所以這是嫌疑之一。反證是 Studio 期間也照畫、Studio 回程卻不當。f-sceneload 另提一條：Studio 會把讀卡器的 `PreviewActor` 藏起，1 對 1 不會。開關 0／1 各跑 30 張，交給 e-cardload。


### 釘在這裡：**能讓當機消失的旋鈕，不等於修好了**（2026-11-19）

今天有三個旋鈕差點被當成解法：`r.RDG.ParallelExecute=0`、`D3D12.Bindless.GarbageCollectLatency`、
`ok.ShadowCaptureStagger`／`ok.ShadowCapturesPerFrame`／`ok.ShadowCaptureFullView`。它們都可能讓當機消失，
但**沒有一個是修法**：

- `r.RDG.ParallelExecute=0` 是用「不並行錄製」換安全，代價是帧時間，而且只在機器上只有一個 Unreal 時成立；
- `D3D12.Bindless.GarbageCollectLatency` 調大只是讓描述子晚一點被回收重用，窗口還在；
- `ok.ShadowCapture*` 若能擋住，更可能說明的是**傷害的途徑**（孤兒 actor 每帧跑自己的 capture、綁自己的貼圖），
  而不是另一個原因——那兩條其實是同一條。

**旋鈕的價值是定位，不是上線。** 這個專案還有 120 FPS 的目標，把全域的刪除／回收調慢是直接付在帧時間上的；
而且旋鈕擋住的那一天，真正的錯還在，只是要更多張卡才撞到。真修法在交換處：**1 對 1 進場把 controller 的
`PreviewActor` 換成 clone 時，把舊的那個 actor 退休（`OKRetireActor`）**——前提是下面那格真的數出孤兒。

### 要搭下一輪建置一起上的 dump（條件：那兩格數出孤兒）

`ok.ReaderScreen` 那組加一條，一次印完，免得之後為它再建一次：每個 `KKPreviewActor` 的**名字**、
`Session.IsOpen()`、`Parts` 數、它持有的貼圖件數與 MB，以及**它是不是現在 controller 的 `PreviewActor`
或 `StalePreview`**。最後那項才是關鍵——「世界裡有三個 actor」本身不是問題，「有一個誰都不指它」才是問題，
而現在只能從數量反推。這條是我的檔案，和 e-fork-2 的 `OKRetireActor` 同一輪進去，各自提交自己的 hunk。

### 數出來了：活著的 `KKPreviewActor` 每開一張卡多 2～3 個，爬到 25（2026-11-19 12:40／12:43）

兩格都在 e-fork-2 **12:34 的建置**上跑（`HEAD f0b2791e3`，`ok.Experiment.ReaderScreenUnderOtherModes = 0`，
即「1 對 1／Studio 期間讀卡器畫面不畫」），所以**和 12:21 的乾淨基線不是同一份程式**，兩者不能直接比。

**第一格（`obj list class=KKPreviewActor` ＋ `ListTextures`，開 10 張，沒當）**

| 時點 | actors | tex |
|---|---:|---:|
| 開第一張卡後 | 1 | 271 |
| 1 對 1 場景內 | 4 | 338 |
| 回到讀卡 | **5** | 340 |
| 之後第 1 張 | 3 | 277 |
| 第 2 張 | 5 | 364 |
| 第 3 張 | 8 | 430 |
| 第 4 張 | 10 | 513 |
| 第 5 張 | 13 | 580 |
| 第 6 張 | 15 | 642 |
| 第 7 張 | 18 | 682 |
| 第 8 張 | 22 | 732 |
| 第 9 張 | **25** | **784** |
| 第 10 張 | 3 | 272 |

三件事一次對上：**貼圖件數就是 actor 數的影子**（每個 actor 約 25～30 張），所以 12:21 基線量到的 912 張貼圖
換算就是**大約 30 個角色 actor 同時活著**；**跨卡累積的實體不是貼圖，是整個角色 actor**，貼圖只是被它們握著；
第 10 張掉回 3 就是 GC 掃過，所以「GC 時機決定峰值、峰值決定當不當」在這裡有了實體。

**第二格（回程後連跑兩次 `obj gc` 再數）**：`before_trip` 1 個（`_0`）→ `after_trip` 5 個
（`_0 _1 _2 _3 _4`）→ **`after_gc` 3 個（`_0 _1 _4`）**。

- **數量會掉 ⇒ 大部分不是「有人抓著參照」，是等 GC。** 退休流程本身是對的：`OKRetireActor`
  （`OKGalleryWidget.cpp:1290`）把 actor 藏起來、每帧用 2 ms 的預算逐一 `UnregisterComponent`，然後
  `Destroy()`。被 `Destroy()` 的 actor 已經是 pending kill，但 `obj list` 照樣數得到它，**它的 UObject 與貼圖
  要等 GC 才真的放掉**——所以積壓的是「已經銷毀、還沒被回收」的角色，一個約 25～30 張貼圖。
- **`obj refs` 指到的持有者是 `UOKGalleryWidget::ClothingPreviews`**（`OKCharacterController.h:580`）
  和 `ULevel::AddReferencedObjects`。前者是**刻意的服裝預覽快取，`OKGalleryClothing.cpp:60` 把它封在 3 個**，
  所以「GC 後剩 3 個」也正好是這個快取滿載的樣子——**單憑一趟分不出「封頂的快取」和「每趟漏一個」**。
  第三格（進出三趟、每趟後強制 GC 再數）才分得開：**數字一趟一趟往上 ⇒ 真漏；停在 3～4 ⇒ 只是等 GC。**

**所以「1 對 1 交換處補 `OKRetireActor(舊的)`」這條還不能提交**：它只管得到那一趟的 1～2 個，而**主要的量是
每開一張卡就多 2～3 個、要等 GC 才放掉的積壓**。上面那條「真修法在交換處」要按這一格修正：真正該修的是
**積壓沒有上限**——要嘛開卡後積壓超過 N 就主動收一次，要嘛退休時就把 GPU 資源放掉而不是等 UObject GC。
前者便宜且有界，後者才對症（當的是 GPU page fault），但要確認那張貼圖沒有還在飛的 draw 在用。

這也和上面 472 行那筆舊紀錄（`getall KKPreviewActor` 全程只有 3 個）不衝突：那筆沒有 1 對 1 進出、也沒有連開
十張卡，**取樣點落在積壓還沒長起來的時候**——又一次「量的區間不對就什麼都看不到」。

#### 為什麼剛好是 25 個：預設的 GC 間隔是 61.1 秒，而讀卡器自己從不收

- `obj list` **數得到已經 `Destroy()`、還沒被 GC 回收的 actor**：它走的是 `FThreadSafeObjectIterator`
  （`UnrealEngine.cpp:9611` 的 `obj LIST`），預設排除的只有 `Unreachable`／`PendingConstruction`／
  async loading（`UObjectIterator.h` 的 `GetObjectIteratorDefaultInternalExclusionFlags`），**沒有排除
  pending kill／garbage**。所以「25 個活著」就是「25 個已銷毀但還沒回收」，這條是去引擎原始碼確認的，不是推論。
- 引擎預設 `gc.TimeBetweenPurgingPendingKillObjects=61.1`（`BaseEngine.ini:1749`），**本專案的
  `Config/*.ini` 沒有覆寫**。一張卡開起來約 5～10 秒，所以兩次清掃之間大約開 6～12 張，
  每張留 2～3 個 → **同時活著 15～30 個**。量到的 25 個與 784 張貼圖正好落在這個區間。
- 而且**讀卡器的開卡路徑裡一行 GC 都沒有**：全專案 `CollectGarbage`／`ForceGarbageCollection` 的呼叫點只有
  人群／匯入 commandlet、`OKCardLoadProfile.cpp`（量測用）和 **OK Studio**
  （`OKSceneActor.cpp:1766`、`OKStudioGame.cpp:930`）。**Studio 會自己收，讀卡器不會**——
  這也是「Studio 回程不當、1 對 1 回程會當」的另一個差集，和可見性那條各自獨立。

所以峰值不是誰漏了，而是**積壓的上限只由一個 61.1 秒的計時器決定**。在這個數字上，
「清 kept 貼圖讓當機更容易」也說得通：它推遲的正是這個清掃。

#### 第三格：沒有漏，是純粹的 GC 延遲（2026-11-19 12:49，同一份 12:34 建置）

1 對 1 進出三趟，每趟後連跑兩次 `obj gc` 再數：

| 時點 | actors | tex | 名字 |
|---|---:|---:|---|
| 開卡後先 GC | 3 | 274 | `_0 _1 _2` |
| 第 1 趟回程 | 5 | 339 | `_0 _1 _2 _3 _4` |
| 第 1 趟 GC 後 | **3** | 328 | **`_0 _1 _2`** |
| 第 2 趟回程 | 5 | 339 | `_0 _1 _2 _5 _6` |
| 第 2 趟 GC 後 | **3** | 328 | **`_0 _1 _2`** |
| 第 3 趟回程 | 5 | 339 | `_0 _1 _2 _7 _8` |
| 第 3 趟 GC 後 | **3** | 328 | **`_0 _1 _2`** |

**GC 後的數量與名字三趟完全一樣**（`_0 _1 _2`，貼圖也固定 328），每一趟新生的兩個（`_3 _4`／`_5 _6`／`_7 _8`）
都被收掉了。**所以 1 對 1 進出沒有留下任何孤兒——那三個是 `PreviewActor` 加封頂在 3 的服裝預覽快取，照設計該在。**
記名字而不是只記數量，正是這一格能下結論的原因：數量三趟都是 3，但如果是每趟漏一個，名字會換人。

**定案**：`OKInteractionMode` 交換處補 `OKRetireActor(舊的)` **不是這條的修法**，已請 e-fork-2 不要為這個原因提交。
真正該修的是**積壓沒有上限**：讀卡器開卡路徑一行 GC 都沒有，上限只由 61.1 秒的全域計時器決定。
下一格用 `gc.TimeBetweenPurgingPendingKillObjects=10` 直接驗這個機制（當機消失＝峰值就是原因），
**但那是定位用的旋鈕不是上線的修法**：全域 10 秒清掃是付在帧時間上的，這個專案有 120 FPS 的目標；
上線的做法是**積壓超過上限才收一次**。

#### 為什麼一張卡會多 2～3 個 actor：服裝暖機，每個暖機都是一整個隱藏角色

`objlist_*` 的名字與建立順序（第一格的原始檔）：

```
開卡後      0
1 對 1 裡   0 1 2 3
回程        0 1 2 3 4
第 1 張     0 1 4          ← _2 _3 被收掉了（clone 與男角）
第 2 張     0 1 4 5 6
第 3 張     0 1 4 5 6 7 8 9
第 5 張     … 到 14
第 9 張     … 到 26
第 10 張    25 28 29       ← GC 掃過
```

**`_2 _3` 在回程後的下一次取樣就不見了**，正好對上 e-fork-2 的讀碼：1 對 1 的 clone 與男角由
`OwnController` 那條 `Destroy` 收掉，讀卡器原本那個（`_0`）從頭到尾都在。**所以回程沒有孤兒，那張
「1 對 1 不藏」的舊表是把 `Shared` 當成 `Source`。**

多出來的 2～3 個是**服裝暖機**：`TickClothingPreviews`（`OKGalleryClothing.cpp:127`）對
`for(int32 Action:{100,101,103})` 三種脫衣轉移各算一個 key，每個 key
**`SpawnActor<AKKPreviewActor>` 一個隱藏的完整角色**，自己的 Rust session、自己的貼圖、自己的材質
（`SetActorHiddenInGame(true)`＋關 tick＋`SuspendDisplayTicks`）。所以一次開卡建的是
**1 個 `PreviewActor` ＋ 最多 3 個暖機 actor**，上一張那一組同時退休。

- **這不是獨立的 bug，是設計**：`ClothingPreviews` 的活快取封在 3 個（`:60`），`ResetClothingPreviews`
  換卡時會把上一組退休（`:46`）。但它把**每張卡的 churn 乘了三到四倍**，
  而每一個都是「一整個角色的 GPU 資源」——這就是峰值衝到 25 個 actor／784 張貼圖的速度來源。
- **所以有界積壓的上限不能訂 8～10 個**：光是「該在的」就有 `PreviewActor` ＋ 3 個暖機 ＋
  `StalePreview` ≈ 5 個，上限 10 等於**每開一張多一點就要收一次**。上限要照「該在的穩態」往上留，
  不是照峰值往下留；穩態是量出來的 3（GC 後三趟都一樣），加上窗口期的一組 4，**合理的上限在 12～14**，
  而且要記每次觸發的耗時——那是使用者感覺得到的代價。
- 有一個**不用改程式的對照旋鈕**：`OK_NO_CLOTHING_WARM=1`（`OKGalleryClothing.cpp:110`）整個關掉暖機，
  churn 掉回每張一個。它同樣**只是定位用**（關掉換服裝就不再是即時的），但它能把
  「峰值是不是當機的原因」和「GC 時機」分開量。

#### DreamGUI 抓的是 UObject 參照，不是裸 RHI 參照——但第二條修法會繞過它的保護

- `UDreamCanvas::DrawTextureHolds` 是 **`UPROPERTY TMap<TObjectPtr<UTexture>,uint64>`**
  （`DreamCanvas.h:982`）：**UObject 參照**，GC 看得到，在用時標 `MAX_uint64`，停用後再留 8 帧。
- `FDreamUIDeferredRelease` 握的是 `FTextureRHIRef`／`FBufferRHIRef`／`TRefCountPtr<IPooledRenderTarget>`
  （`DreamUIDeferredRelease.cpp:8-13`）——**都是 refcount，不是裸指標**，只會延後銷毀，不會變成懸空參照。

**所以「DreamGUI 握著裸參照」這個嫌疑不成立。** 但這段程式的註解本身是一段歷史證詞：
> 內建 shader 的 draw 只留弱指標與 render thread 的參照，而一張 widget 放掉的貼圖
> （圖片被換成另一張）在那些 draw 還在取樣時被回收——一個 GPU page fault。

**這正是我們現在這個當機的同一個形狀，而 DreamGUI 已經用「把 UObject 多留 8 帧」修過一次。**
關鍵的推論是：**它的保護是「讓 UObject 活著」，不是「讓 RHI 資源活著」**。所以第二條修法
（退休時就 `ReleaseResource()` 放掉 GPU 貼圖）**會從它底下穿過去**：UObject 還活著、
`DrawTextureHolds` 也還抓著，但 RHI 已經空了，而那些 draw 只有弱指標。
第二條要做就得帶同樣的延遲（至少 8 帧，或走 `FDreamUIDeferredRelease` 那種 latency），不能當下就放。

#### 峰值是把機率推高，不是扳機（2026-11-19，重跑基線時發現）

在 **12:34 這份建置**上重跑乾淨基線（clear 配方、同一批卡同一順序），每一張卡都把活著的
`KKPreviewActor` 數記在同一行：

```
… 11 actors=24 tex=686   12 actors=28 tex=735   13 actors=30 tex=824
14 actors=33 tex=871 ← 沒當      15 actors=6 tex=276（GC 掃過）
… 22 actors=25 tex=719 還活著
```

**第 14 張到 33 個 actor／871 張貼圖卻沒當，而且撐到第 22 張**；旧建置那笔同一個配方在**第 17 張**就當，
當掉那趟是 912 張。871 和 912 只差 5%，所以：

**「峰值過某條線就當機」只能當成「機率被推高」，不能當成扳機。** 真正扣扳機的還有別的——哪一張貼圖
正好在飛、同一批描述子被回收重用的時機。這一條要記住，因為它決定了修法的驗收標準：
**有界積壓把峰值壓住之後，不能因為「沒當」就宣告修好**，要跑夠多趟、而且把兩條路徑（純翻卡、
1 對 1 進出再翻卡）都跑到 `faults=0`。

這也再次說明為什麼基線必須在**同一份建置**上重跑：拿 12:21 那筆當基線，會得到一個錯的「當機門檻」。

**已知差別只剩一個**：協調查過 commit 時間，DreamGUI 的兩筆（`0d0de3346` 延遲釋放 04:07、
`cc524c891` 等 RDG 05:07）**都早於** 12:21 的基線，兩個建置都含它們。所以 12:21 → 12:34 之間已知的差別
就是 e-fork-2 的面板隱藏（`7d9465d39`）——它改掉的正是「1 對 1／Studio 期間讀卡器的 DreamGUI 畫面還在畫」。
**少了那些每帧綁貼圖的 draw，退休中的貼圖被取樣的機會就少**，這對「撐更久」是個合理解釋。
而它留了實驗 cvar `ok.Experiment.ReaderScreenUnderOtherModes=1`（還原舊行為），
所以這件**可以在同一份建置上**跑 on／off 兩格乾淨地驗——這正是先前缺的那個對照
（當時兩格跨了不同建置，所以不能比）。若 on 明顯更早當，那就是
**積壓提供燃料、那些 draw 扣扳機**，兩件各自可修，而且兩件都已經有東西可上
（`ok.PreviewBacklogLimit` 與它的隱藏）。

### 對照表：縮短 purge 週期不但沒擋住當機，還讓它在**更低的水位**就當（2026-11-19 12:53–13:12）

四格都在同一份 12:34 建置上、同一批卡同一順序、獨占機器，每張卡的 actor 數與貼圖件數記在同一行。
四格**都當**，而且四次的 fault 完全同一個：`MMU Fault Error`／`Error_DMA_PageFault`／
**`fragment_02 @ 0x00045f90`**——所以四格可以互相比較，比的是同一個 bug。

| 格 | 當在第幾張 | 當機前一張的 actors | 當機前一張的貼圖 | 該格的峰值 |
|---|---:|---:|---:|---:|
| 基線 clear | 23 | 25 | 719 | 33 actors／871 張（第 14 張） |
| 基線 noclear | 14 | 29 | 767 | 29／767 |
| `gc=10` clear | 15 | **5** | **328** | 約 8／約 400 |
| `gc=10` noclear | **7** | **5** | **306** | 約 8／約 408 |

**結論與我們原本的方向相反**：

1. **峰值不是原因。** `gc=10` 兩格的峰值只有基線的四分之一到五分之一
   （5～8 個 actor、300～400 張貼圖，對基線的 25～33 個、719～871 張），**卻當得更早**
   （第 7、第 15 張，對基線的第 14、第 23 張）。「活著的東西越多越容易當」在這組數據裡不成立。
2. **更可疑的是「釋放」這件事本身。** `gc.TimeBetweenPurgingPendingKillObjects=10` 做的事就是
   **把回收做得更頻繁**，於是貼圖被真正放掉的次數也更頻繁——而當機提前了。
   這和 DreamGUI 那段註解描述的形狀一致：**一張貼圖在還有 draw 在取樣時被放掉**。
   照這個方向，**當機的機率跟「單位時間內的釋放事件次數」正相關，而不是跟活著的件數正相關**。
3. **所以 `ok.PreviewBacklogLimit`（有界積壓）不能當修法上線。** 它做的正是「讓回收更常發生」，
   按這組數據那是**把當機提前**的方向。那個 patch 先留著當診斷旋鈕
   （把界調大／設 0 可以反過來驗「回收越少越安全」），**但不能說它修了什麼**。
   這是「能讓當機消失的旋鈕不等於修好了」的鏡像版本：**我自己寫的修法，量下去是往反方向走的。**

**還有一個相關的觀察**：兩格「硬當」（行程直接不見，`unreal=0`）的那兩次，
log 裡 `Created late shader associations` 剛好各出現 2 次；另外兩格（行程還在、但讀卡失敗）是 0 次。
樣本太小不能下結論，但它是 bindless 描述子那條線索還活著的證據，值得在下一輪繼續記。

**下一步因此要改**：先問「是誰在取樣一張已經放掉的資源」，而不是「怎麼把峰值壓低」。
面板 on／off 那一格（`ok.Experiment.ReaderScreenUnderOtherModes`）現在更值得跑——
它正是在問「那些每帧綁貼圖的 draw 是不是扣扳機的那一環」。

#### 修正：那四格**兩條軸都沒立起來**，所以下三格各只動一件事

上面「峰值不是原因」那句下過頭了，**撤回**：`gc=10` 同時做了兩件事——把活著的件數壓到五分之一
（往好的方向）**而且**把回收事件的頻率拉高（往壞的方向）。兩個變量一起動的格子，
不能用來宣告其中一條軸無效，只能說**另一條軸更強**。

但「配對內讀：活著的少的那側活得久，所以峰值軸確認存在」也不成立，**同樣是兩個變量**：
- 配對內的差別是 **clear vs noclear**，也就是**清不清 kept 貼圖**——那本身就是一個「釋放」變量；
- 而兩側的 actor 數只差 25 對 29、22 對 29，**不到兩成**。拿兩成的件數差去解釋
  「第 23 張 vs 第 14 張」這麼大的差別，比例不對；更簡單的解釋是 **clear 這個動作本身**。

**所以誠實的位置是：這四格兩條軸都沒立起來。** 下三格各只動一件事，預測寫在跑之前：

| 格 | 只動的那一件 | 撐過第 23 張代表 | 還在 23 附近當代表 |
|---|---|---|---|
| `OK_NO_CLOTHING_WARM=1` | 少生角色（**不新增回收事件**） | 件數軸存在，且有不碰回收的壓法 | 件數這條線可以收掉 |
| `gc.TimeBetweenPurgingPendingKillObjects=300` | 回收更少（活著更多） | 釋放頻率是主軸 | 連「釋放頻率」也只是跟著別的東西動 |
| `-gpucrashdebugging` ＋ `r.D3D12.DRED=1` | 不是軸：去拿**名字** | — | — |

**拿名字那格的前提先查過引擎，不要再犯「旋鈕沒接上卻以為轉了」**：
- cvar 是 **`r.D3D12.DRED`**（`D3D12Adapter.cpp:157`），不是 `D3D12.DRED`，而且是 **`ECVF_ReadOnly`**，
  執行中設不生效，必須啟動時給；
- **`-gpucrashdebugging` 會把所有 GPU crash 功能一起強制打開**（`RHI.cpp:2092`
  `ShouldEnableGPUCrashFeature`，命令行開關優先於 cvar）；
- 而 page-fault 的**配置名字**還需要 `bTrackAllAllocation`，它要 `UseGPUCrashDebugging()`
  **且 resource heap tier 2**（`D3D12Adapter.cpp:1532`）——所以要在 log 裡確認 tier 2 成立才算這格有效。
- DRED 有 GPU 開銷，**那一格的「第幾張當」不能和別格比**，它是去拿名字的，不是拿時間的。

四次 fault 的簽名完全相同（`fragment_02 @ 0x00045f90`），意思是它**穩定可復現**——
這正是拿名字最好的時機，比再跑五格「第幾張當」值錢得多。

### 釋放事件可以從已有的 dump 算出來，不必另跑一格（2026-11-19）

`knob.sh` 每張卡都把整份 `ListTextures` 存成 `<卡號>.tex`，所以**前後兩張卡的名字集合相減**就得到
那張卡期間**新建**（只在後者）與**被放掉**（只在前者）的 transient 貼圖張數——**釋放事件是算出來的，
不是從「我設了哪個 cvar」推出來的**，而且六格全部可以回溯算，成本是一支 20 行的腳本。

| 格 | 當在第幾張 | 大批釋放次數 | 次／卡 | 累計釋放 | 存量峰值 | 最後一次釋放在第幾張 |
|---|---:|---:|---:|---:|---:|---:|
| 基線 clear（面板隱藏） | 23 | 3 | 0.13 | 1486 | 752 | **23** |
| 基線 noclear（面板隱藏） | 14 | 2 | 0.14 | 887 | 648 | **14** |
| `gc=10` clear | 15 | 7 | 0.47 | 880 | 286 | 14 |
| `gc=10` noclear | 7 | 4 | 0.57 | 599 | 309 | **7** |
| 面板照畫 clear | 14 | 2 | 0.14 | 944 | 710 | **14** |
| 面板照畫 noclear | 10 | 1 | 0.11 | 234 | 494 | 4 |

**兩件事得到支持，而且它們指向同一個機制：**

1. **當機落在「剛做過一次大批釋放」的那張卡上。** 六格裡有四格的最後一次大批釋放**就是當掉的那張卡**
   （23／14／7／14），第五格差一張（釋放在 14、當在 15）。只有面板照畫 noclear 是例外（釋放在 4、當在 10）。
2. **存量峰值排不出生死。** 752 張的那格活到第 23 張，286 張的那格第 15 張就當；
   累計釋放最多的那格（1486）反而活得最久。**所以「存量」與「累計釋放量」都不是軸，
   「什麼時候釋放」才是。**

合起來就是一句話：**一次清掃把貼圖真的放掉，而那一刻有 draw 還在取樣它。**
`gc=10` 更早當因此有了解釋（清掃次數變 3～4 倍，撞上的機會也變 3～4 倍），
而我那個有界積壓的 patch 之所以是錯的方向也有了解釋（它增加清掃次數）。

### 面板照畫的兩格：兩排都提前當，但這是 n=1，不能下結論

同一份 12:34 建置、同一批卡同一順序，只動 `ok.Experiment.ReaderScreenUnderOtherModes`：

| | 面板隱藏（預設 0） | 面板照畫（1） |
|---|---:|---:|
| clear | 第 **23** 張 | 第 **14** 張 |
| noclear | 第 **14** 張 | 第 **10** 張 |

兩排同方向，而且兩排的釋放次數／卡與存量峰值都差不多（0.13 對 0.14、0.14 對 0.11），
**也就是在另外兩條軸大致不變的情況下，把面板畫出來讓當機提前了一半**。這和上面的機制吻合：
面板畫出來就有大量每帧綁貼圖的 draw，撞上「剛被放掉的那張」的機會跟著上去。

**但這是每格一趟，不能當結論**，理由就在今天自己的數據裡：**同一個配方在舊建置當在第 17 張、
在這份建置當在第 23 張**。同配方的趟間差異本來就有 6 張那麼大，而這裡要解釋的差異是 9 張。
所以這兩格要**各再跑一趟**才能說話；在那之前寫成「方向一致，未定案」。

**還有一個這一格自己冒出來的疑問**：這些格子只在開頭進出 1 對 1 一次，之後全在讀卡器裡翻卡，
而那個 cvar 管的是「1 對 1／Studio 期間讀卡器畫不畫」——**回到讀卡器之後兩邊應該一樣**。
那它為什麼會影響後面 30 張？可能是進出那一趟留下的狀態不同（畫布在隱藏期間放掉並重建 vs 一直抓著），
也可能根本就是趟間差異。**這個疑問本身就是要再跑一趟的理由。**

#### 更正：`D3D12.DeleteQueueMaxEOPTimeDelta` 不是「把釋放往後推」，而且資源記憶體這條路**本來就有圍欄**

查引擎才寫，不要再轉第三個沒接上的旋鈕：

- `D3D12.DeleteQueueMaxEOPTimeDelta`（`D3D12RHI.cpp:62-67`）的語意是
  **「處理刪除佇列時，RHI 執行緒會為比這個時間差更舊的 EOP 工作停下來等它完成」**，
  目的是「限制 RHI 執行緒能比其他執行緒超前多少」，**0 秒＝不停等**。
  所以把它調到 10 **不會**讓「GPU 真的看不到那塊記憶體」晚 10 秒發生，
  它只會讓 RHI 執行緒**更不受約束地往前跑**。方向和我們想測的那件事無關。
- 更關鍵的是：**資源的延遲刪除本來就是圍欄過的**。`FD3D12DynamicRHI::EnqueueEndOfPipeTask`
  （`D3D12RHI.cpp:320`）對每一個佇列建一個 `FD3D12SyncPoint`（`GPUAndCPU`），
  把它們當成 EOP 工作的前置條件，刪除才在那個工作裡執行。
  **所以凡是走 `FD3D12DeferredDeleteObject` 的東西，都要等 GPU 過了那個點才真的被放掉。**
  「一張貼圖的記憶體在 draw 還在取樣時被釋放」**在這條路上不可能發生**——引擎已經擋住了。

**那麼「釋放」那個相關性要重新解釋，而且有一個沒被圍欄保護的候選：bindless 描述子堆。**
`FD3D12BindlessResourceManager::GarbageCollect`（`D3D12BindlessDescriptors.cpp:420`）
把整個 GPU 堆在 active 與 pooled 之間搬，而且在 **`ERHIBindlessConfiguration::RayTracing`**
（正是這台機器的設定）下，當堆有 `D3D12.Bindless.GarbageCollectLatency` 個 update cycle 沒被用到就
**`ReleaseGPUHeaps()` 全部放掉**（預設 600）。**一個回到池子又被拿出來重用的堆，它的描述子會被覆寫**，
而還在飛的命令列表若引用那個堆裡的描述子，讀到的就是覆寫後的東西——
**就是「shader 取樣時 page fault、偏移固定、而資源本身還好好活著」**，和四次完全相同的
`fragment_02 @ 0x00045f90` 對得上。

所以下一格是 `D3D12.Bindless.GarbageCollectLatency`（`ECVF_ReadOnly`，啟動時給）：
**6000（堆留久）對 1（馬上重用）**，clear 配方 30 張，和死在第 23 張的基線可比。
6000 活下來而 1 明顯更早當 ⇒ 描述子堆重用就是機制；兩邊沒差 ⇒ 這條也不是，
那就只能從 DRED 拿到的名字往下追，不要再轉 cvar。

### 不必再轉 cvar：當掉的那個 shader 就是 DreamGUI 自己的 `MainPS`，而兩個旋鈕線都已排除

**一、描述子堆那格不跑，因為旋鈕接不上。** log 第一行就講明了：
`LogRendererCore: Ray tracing is disabled. Reason: disabled through project setting (r.RayTracing=0)`。
而這台機器的 bindless 設定是 **`ERHIBindlessConfiguration::RayTracing`**——也就是
**bindless 只給光追用**，而光追是關的。`FD3D12BindlessResourceManager::GarbageCollect` 的那段
`ReleaseGPUHeaps()` 又正好只在 `GetConfiguration() == RayTracing` 時走。
所以讀卡器那些普通 raster draw **根本不碰那個堆**，`D3D12.Bindless.GarbageCollectLatency`
6000 對 1 會是轉一個與它無關的旋鈕。**那格取消**（腳本留著，若哪天改成 `AllShaders` 再用）。

**二、`Created late shader associations` 要從線索裡撤掉——它是當機的結果，不是前兆。**
它是 **NVIDIA Aftermath 在產生 crash dump 時**去把 shader binary 註冊起來、好在 dump 裡解析名字
（`D3D12NvidiaExtensions.cpp:62` `CreateShaderAssociations`，由
`RHICoreNvidiaAftermath.cpp:851` 在組 `Active Shaders:` 那段時呼叫，engine 自己的註解是
**"Allow association after a fault"**）。所以「它在 fault 前 25 ms 出現」是**因為 fault 已經發生了**。
我之前把它當線索、還在每張卡記 `lsa` 計數——**那個計數量的是當機本身**，撤回。

**三、當掉的 shader 身分可以定了：DreamGUI 自己的基底 pixel shader。**
dump 的 `Active Shaders:` 只有一個：`Type = Pixel`、`Function = MainPS`、
`Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF`。而
`IMPLEMENT_GLOBAL_SHADER(FDreamUIBasePS, "/Plugin/DreamGUI/Private/DreamUIBase.usf", "MainPS", SF_Pixel)`
（`DreamUIBaseShaders.cpp`）——**`MainPS` 就是 `FDreamUIBasePS`**，不是 Slate 也不是角色材質。
今天四格的 breadcrumb 也一致：`RHIThread → EndDrawingViewport → Frame NNNNN`，
而 11-18 那份有 DRED 的 dump 更細：
`BeginEvent [FrameRenderFinish] → [RenderFinish] → [ViewFamilyExtension(5)] → [ViewExtension(0)]`
之後是一長串 `DrawIndexedInstanced`，停在第 24 個（第 23 個 LAST COMPLETED）。
**所以是 DreamGUI 的 ViewExtension 在畫它自己那批 UI draw 時，pixel shader 取樣時 page fault。**

**四、「頁錯位址不屬於任何資源」這句要分兩種情況講，否則會互相矛盾。**

| 那一次 | `Logging all resource enabled` | 那三個 `Found 0` 代表 |
|---|---|---|
| 11-18 `EFork1119h`（`-gpucrashdebugging`） | **Yes** | **是證據**：位址真的不在任何追蹤到的資源、heap，或**最近 100 帧內**釋放過的資源裡 |
| 今天這四格（沒給任何 GPU crash 開關） | **No** | **不是證據**：追蹤沒開，當然找不到 |

而「最近 100 帧內」這個限制本身就指出一個完全吻合的可能：
**一個超過 100 帧前就被放掉的東西，它的描述子還被綁著**。
DreamGUI 的保護期是 8 帧（`DrawTextureHolds`）與 3 帧（`FDreamUIDeferredRelease`），都遠小於 100——
所以若有東西逃過那兩層，到當機時早就超出 100 帧的統計窗口了。

**五、下一格因此不是旋鈕，是 DreamGUI 自己為這個問題準備的診斷：`DreamGUI.LogHeldTextures=1`。**
它就在 `DreamCanvas.cpp` 那段裡，說明寫得很直接：
「印出每一張 canvas 開始使用的貼圖（名稱、大小、mip、outer），**用來判斷 GPU page fault 取樣到的是哪一張**」。
配 `-gpucrashdebugging`（讓 `Logging all resource enabled: Yes`）跑同一個配方，
當機時就有「這條 canvas 綁過哪些貼圖」加上「頁錯位址附近有哪些存活／最近釋放的配置」兩份名單可以對。

另外 `DrawBuiltInBatch` 綁的是 **`FTextureReferenceRHIRef`**（`DreamUIBaseShaders.cpp:30`
的 `Reference()` 取 `InTexture->TextureReference.TextureReferenceRHI`），
也就是**貼圖參照物件**而不是貼圖本身。參照物件的生命週期和它指向的那張貼圖是兩回事，
這正是「資源本身沒事、取樣卻 page fault」要查的下一個接縫。

### 定案：存量那條軸死了，釋放事件那條軸立起來了（2026-11-19 13:23–13:35）

三格都是同一份 12:34 建置、同一批卡同一順序、clear 配方、獨占機器，**三格全部跑完 30 張且 `faults=0`**。
釋放事件由 per-card 的 `ListTextures` 名字相減算出。

| 格 | 跑了幾張 | 大批釋放次數 | 次／卡 | 累計釋放 | **存量峰值** | 結果 |
|---|---:|---:|---:|---:|---:|---|
| `gc=10` clear | 15 | 7 | **0.47** | 880 | 286 | **第 15 張當** |
| 預設 61.1 clear（基線） | 23 | 3 | 0.13 | 1486 | 752 | **第 23 張當** |
| **`gc=300` clear** | **30** | **0** | **0.00** | **0** | **1690（85 個 actor）** | **全過** |
| `OK_NO_CLOTHING_WARM=1` clear | 30 | 3 | 0.10 | 1300 | 694 | 全過 |
| `-gpucrashdebugging` ＋ `r.D3D12.DRED=1` clear | 30 | 3 | 0.10 | 1424 | 752 | 全過 |

**一、存量那條軸**可以收掉了，不是「不是唯一」而是**直接被推翻**：`gc=300` 那格活著的角色 actor 到
**85 個、transient 貼圖 1690 張**——遠高於當掉那趟的 912 張、30 個 actor——**完全沒當**。
所以「活著的件數多就會當」是錯的，而且錯得很明確。

**二、釋放事件那條軸立起來了**，同一個變數三個刻度、同配方同建置，單調：

```
0.47 次/卡（gc=10）    → 第 15 張當（noclear 那側第 7 張）
0.13 次/卡（預設 61.1）→ 第 23 張當
0.00 次/卡（gc=300）   → 30 張全過，而且是史上最高的存量
```

**`gc=300` 那格一次大批釋放都沒發生**（300 秒比整格的時長還長），而它正是唯一完全沒事的高水位格。
**沒有釋放就沒有當機**，不管存量多高。

**三、但釋放不是充分條件。** `OK_NO_CLOTHING_WARM` 與 DRED 兩格各發生 3 次釋放、放掉 1300～1424 張，
照樣跑完 30 張。它們的次／卡（0.10）和死在第 23 張的基線（0.13）其實差不多——
**所以在每卡 0.1 次這個量級，過或不過是機率問題，23 對 30 落在趟間差異裡**。
能拉開差距的是 `gc=10`（0.47）對 `gc=300`（0）這兩端。
結論要寫成：**每一次大批釋放是一次擲骰，釋放越頻繁就擲越多次**；
至於單次命中的機率由「那一刻有什麼 draw 在取樣」決定——那正是面板 on／off 那兩格指向的方向。

**四、`OK_NO_CLOTHING_WARM` 這格要講清楚它測不到想測的東西。** 它確實把峰值壓到 694／8 個 actor，
但它**同時**把累計釋放量從 1486 降到 1300——**少生就少放**，兩條軸綁在一起，
所以「它全過」不能單獨歸給哪一條。能分開的是 `gc=300`。

**五、DRED 那格沒拿到名字，因為它沒當。** 那份 page-fault 報告只有真的當掉才會產生。
所以拿名字要**配最容易當的配方**，不是配基線：下一格是
**`gc=10` ＋ noclear（今天最早當的組合，第 7 張）＋ `-gpucrashdebugging` ＋ `DreamGUI.LogHeldTextures=1`**。
`-gpucrashdebugging` 一個開關就把 DRED 與 `bTrackAllAllocation` 都打開
（`RHI.cpp:2092`：命令行開關強制全開；`D3D12Adapter.cpp:1532`：`UseGPUCrashDebugging()` 設
`bTrackAllAllocation`），所以 `Logging all resource enabled` 應該會是 `Yes`。

#### 同時排除掉的三條：描述子環重用、參照被改指、資源逐出

- **描述子環（online view heap）重用：排除。** 引擎自己在 `CanReserveSlots` 裡把 wrap around 關掉了
  （`D3D12DescriptorCache.cpp`：`// TEMP: Disable wrap around by not allowing it to reserve slots if the heap is full.`，
  下面還留著 `// TEMP: Uncomment this code once the heap wrap around is fixed.`），
  而真的發生 rollover 時 `FD3D12LocalOnlineHeap::RollOver()` 會印一行
  `OnlineHeap RollOver Detected`。**今天四格與 11-18 那份 dump 全部 grep 不到這行（0 次）**，所以沒發生。
- **「`FTextureReferenceRHIRef` 被改指，導致已錄好的 draw 讀到新目標」：排除，理由是結構性的。**
  `FRHITextureReference::ReferencedTexture` 是 **`TRefCountPtr<FRHITexture>`**（`RHITextureReference.h`），
  改指只是放掉舊的一份 refcount，舊貼圖的銷毀照樣走被圍欄保護的延遲刪除；
  而 D3D12 的 SRV **描述子是在錄命令時就被複製進 online heap 的槽位**（`FD3D12OnlineHeap::ReserveSlots`），
  **之後改指動不到已經複製好的描述子**。所以「改指」既不會變成懸空指標，也不會回頭改寫已錄好的 draw。
  這條和前一條（記憶體被提前釋放）作廢的理由不同，但結論一樣：**不是它。**
- **資源被逐出、VA 沒映射：排除。** `D3D12.ResidencyManagement` 預設是開的（`D3D12Adapter.cpp`），
  但今天的 log 裡 `Evict`／`Residency`／`MakeResident` 一次都沒出現（0 次）。

#### 機器狀態的時間窗：13:40 左右有一輪別人的 CPU 工作，但它落在哪一格要查過才算

f-yvonne 自己報告 **13:40 左右在 F 樹跑了一輪純 CPU 的 `cargo test`**（約 170 張卡的唯讀解析，
一兩分鐘），而當時 `may-build` 已經回 wait、機器是這邊獨占。

**查過之後：上面那三格不受影響，不需要重跑。** 三格的 log 時間窗是

```
OK_NO_CLOTHING_WARM  13:23:41 – 13:27:40
gc=300               13:27:50 – 13:31:50
DRED（基線配方）      13:32:00 – 13:35:56
```

**三格都在 13:35:56 之前結束**，而 13:40 那輪落在之後開始的「拿名字」那格
（log `20261119-133734-3b580665`，13:37:34 起）。那一格要的是**故障位址對到哪一個配置的名字**，
不是「第幾張當」，所以 CPU 爭用不影響它的結論；真要說有影響，也只是讓它更容易當，
而那一格本來就是去把它弄當的。**但時間窗照樣記在這裡**，和「舊建置第 17 張／新建置第 23 張」
那筆一樣：**讓後面的人知道這個數上面有記號。**

一般規則（今天第二次用到）：**別人進來的時間窗，要和各格的 log 時間窗對過才知道污染到誰。**
憑印象說「那段我在量」或「應該在噪聲裡」都不算——每一格的起訊時間都在它自己的 log 第一行。

### 唯一沒被圍欄保護、也不是快照的那條路：VRAM defrag 會把貼圖搬家

**先更正一處讀法：`0x00045f90` 不是堆裡的位移，是 shader 的 program counter。**
同一份 dump 裡還有 `fragment_02 @ 0x00046000`、`0x0004a780`、`0x0004a7a0`，
全部落在 `"Shader size": 375040` 之內——那是**同一個 shader 裡不同 warp 的指令位置**。
所以它每次相同的原因是「同一個 shader 的同一條取樣指令」，和記憶體布局無關。
真正的故障位址是 **`0xEFB481000`**。不要再從 `0x45f90` 推記憶體結構。

**四個 D3D12 貼圖池裡只有一個開 defrag**（`D3D12Allocation.cpp` 建池處）：

| 池 | `bDefragEnabled` |
|---|---|
| `D3D12 ReadOnly4K Texture Pool Allocator` | `false`（註解：都是 4K 的倍數，不會碎） |
| **`D3D12 ReadOnly Texture Pool Allocator`** | **`true`** |
| `D3D12 RenderTarget Pool Allocator` | `false` |
| `D3D12 UAV Pool Allocator` | `false` |

**唯一會 defrag 的是「唯讀貼圖池」——普通被取樣的貼圖住的地方**，也就是
`FDreamUIBasePS` 在取樣的那些卡片／角色貼圖。defrag 走 `HandleDefragRequest` ＋
`FD3D12VRAMCopyOperation`，**把 placed resource 搬到另一個堆**；舊的塊還給池子，
池子空了就 `MemoryPool->Destroy()`（`D3D12PoolAllocator.cpp:850`，條件是
`IsEmpty() && LastUsedFrameFence + InFrameLag <= CompletedFence`）。

**這是第一個能同時解釋全部證據的機制：**

| 證據 | defrag 怎麼解釋 |
|---|---|
| 故障位址**不屬於任何追蹤到的資源、堆、或最近 100 帧釋放過的資源**（11-18 那份、追蹤開著） | 那個資源**從來沒被釋放，它被搬走了**；舊塊還給池子、池子被 trim 掉，位址底下什麼都不剩 |
| 延遲刪除的 EOP 圍欄擋不住 | 圍欄保護的是**資源物件的銷毀**；defrag 釋放舊塊掛在**帧 fence** 上並重建描述子，**搬家前錄好的描述子快照可以在搬家後才執行** |
| 釋放是必要條件（`gc=300` 零釋放、三十張全過） | defrag 需要碎洞，碎洞來自 free |
| 釋放不是充分條件（每卡 0.1 次那幾格過了） | defrag 還要 `Usage < RHIPoolAllocator.DefragSizeFraction`（預設 0.9），而且每次最多清 `DefragMaxPoolsToClear` 個池（預設 1） |
| 面板畫出來更容易當 | 取樣的 draw 越多，撞到過期描述子的機會越大 |
| 存量高卻沒事（1690 張） | 存量高＝池子用得滿＝`Usage` 高＝**不符合 defrag 條件**，反而更安全 |

最後一列是個額外的好處：它讓「存量軸被推翻」從一個反直覺的結果變成**可預期的結果**。

**可以不建置就關掉，兩條獨立的路**：池子只有在
`Usage < GRHIPoolAllocatorDefragSizeFraction` 時才會成為 defrag 目標（`RHIPoolAllocator.cpp:986`），
所以 **`RHIPoolAllocator.DefragSizeFraction=0`** 讓那個條件永遠為假；
另外 `MaxPoolsToDefrag == 0` 直接 return（`:993`），所以 **`DefragMaxPoolsToClear=0`** 也能關。
**兩個都設**，免得「其中一個沒接上」又變成一次假陰性。

**決定性的格子**：`gc=10` ＋ noclear（今天最快當的組合，第 7 張）＋ 關掉 defrag。
活過 30 張就是 **7 → 30** 的跳動，遠在 6 張的趟間差異之外；還是第 7 張附近當，
那 defrag 也不是，而且那時整條「釋放 → 某個東西被搬走或歸還」的線就只剩實際拿到名字一條路。

### 拿到名字了：畫面上那條 canvas 綁的是 18 張 288×402 的 transient 卡片縮圖

配最快當的配方（`gc=10` ＋ noclear）＋ `-gpucrashdebugging` ＋ `DreamGUI.LogHeldTextures=1`，
**第 4 張就當**（今天最快），而且 `Logging all resource enabled: **Yes**`。

`DreamGUI.LogHeldTextures` 印出來的名單（21 行，去重後）——**全部屬於同一條 canvas**
`WBP_ReaderScreen_C_0.DreamCanvas_0`，也就是讀卡器那片面板：

```
DreamUIDynamicSpriteAtlasData_Texture_0   Texture2D      2048x2048 mips=1  outer=/Engine/Transient
DreamUIFontData_DistanceField_Texture_0   Texture2DArray 0x0       mips=0  outer=/Engine/Transient
DreamUIPreset_WhiteSolid                  Texture2D      4x4       mips=1  outer=/DreamGUI/Textures/...
Texture2D_7 … Texture2D_24（共 18 張）     Texture2D      288x402   mips=1  outer=/Engine/Transient
```

**那 18 張 288×402 的 transient 貼圖就是卡片列表的縮圖**，每張約 288×402×4 ≈ 463 KB——
**大於 4K 池的門檻，所以它們住在唯讀貼圖池，也就是四個池裡唯一開 defrag 的那個**。
翻卡時這批縮圖被銷毀重建，正是量到的「大批釋放」。
至此「誰在取樣」「取樣什麼」「住在哪個池」三件都有名字了。

#### 故障位址那三行：追蹤開著，而且**第二次**得到全部為零

```
PageFault: PageFault at VA GPUAddress "0x257C901000" (GPU 0)
PageFault: Last completed frame ID: -1 (cached: 7473) - Current frame ID: 7476
PageFault: Logging all resource enabled: Yes
PageFault: Found 0 active tracked resources in 16.00 MB range of page fault address
PageFault: Found 0 active heaps containing page fault address
PageFault: Found 0 released resources containing the page fault address during last 100 frames
DRED: Last tracked GPU operations:
DRED: Commandlist "FD3D12CommandList 16 (GPU 0)" on CommandQueue "3D Queue (GPU 0)", 112 completed of 244
DRED: No PageFault data.
```

**`Found 0 active heaps containing page fault address` 是最關鍵的一行**：那個位址
**不在 RHI 目前擁有的任何堆裡面**。所以不是「記憶體被別人拿去用」（那會讀到垃圾、不會 page fault），
而是**那塊記憶體已經不屬於這個行程的任何堆**。
另外 `Last completed frame ID 7473 / Current 7476` 說明 **GPU 落後 CPU 約 3 帧**。

#### 三個「誰把描述子帶過搬家那條線」的答案，其中第三個對我自己的假設不利

1. **defrag 有重建 view，但重建的是 offline 的那一份。** `HandleDefragRequest` →
   `FD3D12ResourceLocation::OnAllocationMoved` → `Owner->ResourceRenamed(Contexts)` →
   `FD3D12ShaderResourceView::ResourceRenamed` → `UpdateView` → `UpdateDescriptor`，
   改的是這個 view 自己的 **offline descriptor**。
   而 `Contexts` 這個參數**只在 bindless 那條路上被用到**
   （`FD3D12View::UpdateBindlessSlot`：`if (BindlessHandle.IsValid())`）——
   **bound 的那條路沒有任何東西去碰「已經複製進 online heap 槽位的那些舊快照」**。
   所以「描述子被帶過搬家線」在結構上是可能的。
2. **它等的是帧 fence，不是具體那批命令列表。** `DeallocateResource` 把釋放掛進
   `FrameFencedOperations`，fence 值取 `FrameFence.GetNextFenceToSignal()`；
   池子被 trim 的條件是 `IsEmpty() && LastUsedFrameFence + InFrameLag <= CompletedFence`。
3. **但那個 `InFrameLag` 是 20**（`D3D12Allocation.cpp:1910`：`PoolAllocators[PoolIndex]->CleanUpAllocations(20)`）。
   **20 帧的餘裕，對「GPU 只落後 3 帧」來說太寬了**——
   所以「舊塊所在的堆在那條命令列表還沒跑完就被還掉／解除提交」這個情節
   **很難在 20 帧內發生**。這一條是**對我自己這個假設不利的證據**，要先講。

**所以結論先放在這裡，不要超過證據**：我找到了**唯一一條不是快照、也不被 EOP 圍欄覆蓋的路**
（defrag 搬家 ＋ bound 路徑不更新已複製的快照），但**它的堆歸還有 20 帧餘裕，而 GPU 只落後 3 帧**，
所以它要成立還缺一個解釋：**要嘛舊塊被還回池子之後很快被別的配置拿走並且那次配置讓堆重新佈局，
要嘛根本不是這條**。關掉 defrag 那一格（`gc=10`＋noclear ＋
`RHIPoolAllocator.DefragSizeFraction=0` ＋ `DefragMaxPoolsToClear=0`）會直接回答：
**第 4 張附近當 ⇒ 不是 defrag，整條「搬家」線作廢**；**活過 30 張 ⇒ 是它，而且 20 帧那個餘裕有漏洞要查。**

### 關掉 defrag 還是當 ⇒ 搬家那條線作廢（2026-11-19 13:46）

`gc=10` ＋ noclear ＋ `RHIPoolAllocator.DefragSizeFraction=0` ＋ `DefragMaxPoolsToClear=0`，
**第 15 張當**。

**兩個旋鈕都確認接上了**（log 是 `Set CVar`，不是 `deferred - dummy variable created`）：

```
LogConfig: Set CVar [[RHIPoolAllocator.DefragSizeFraction:0]]
LogConfig: Set CVar [[RHIPoolAllocator.DefragMaxPoolsToClear:0]]
```

**按跑之前就寫下的判準：還是當 ⇒ 不是 defrag。** 同配方今天另外兩趟當在第 7 張與第 4 張，
這趟第 15 張雖然晚一些，但**預測是「活過 30 張」，而它當了**。
15 對 7 可能有部分效果（defrag 也許貢獻一點機率），但**機制不可能只是 defrag**。
搬家那條線作廢，連同它那個「20 帧餘裕對 3 帧落後太寬」的缺口一起——
那個缺口本來就是對它不利的證據，現在量測同意了。

**到此，所有「結構性」的候選都被排除過一遍：**

| 候選 | 怎麼排除的 |
|---|---|
| 記憶體被提前釋放 | `EnqueueEndOfPipeTask` 每佇列 GPU sync point 圍欄（讀碼） |
| 貼圖參照被改指 | `TRefCountPtr` ＋ 描述子在錄命令時就複製成快照（讀碼） |
| bindless 描述子堆重用 | `r.RayTracing=0` 而 bindless 只給光追（log） |
| 描述子環 rollover | 引擎自己關掉 wrap around ＋ `OnlineHeap RollOver Detected` 0 次（log） |
| 資源被逐出 | `Evict`／`Residency`／`MakeResident` 0 次（log） |
| **defrag 搬家** | **兩個旋鈕關掉、確認 `Set CVar`，照樣當（量測）** |

### 剩下最具體的一條：**我們自己外掛裡的 3 帧**

`FDreamUIDeferredRelease::DelayFrames` 是 **`static constexpr uint32 DelayFrames = 3`**
（`DreamUIDeferredRelease.h:18`），而同一個外掛的 `UDreamCanvas::DrawTextureHolds`
**留的是 8 帧**（`DreamCanvas.cpp` 的 `constexpr uint64 KeepFrames = 8`）。
**同一個外掛裡兩個保護期不一致（3 對 8），這本身就是一個味道。**

而 page fault 報告裡的 `Last completed frame ID: -1 (cached: 7473) - Current frame ID: 7476`
看起來正好是 **GPU 落後 3 帧**——和 `DelayFrames = 3` **一點餘裕都沒有**。

**但這條推論有一個我必須自己標出來的弱點**：那個 `-1` 表示 fence 已經讀不到了（device removed），
`7473` 是最後一次快取的值。所以「落後 3 帧」是**在裝置已經死掉那一刻量到的**，
**有可能是當機的結果而不是當機前的常態**——和今天 `late shader associations` 那個坑同一個形狀，
所以不能拿它當證據，只能拿它當「值得一試」的理由。

真正站得住的理由是另外兩件，都不依賴那個數字：
1. **3 帧對一個允許多帧延遲的渲染管線本來就薄**，而
2. **同一個外掛自己在另一處用 8 帧**——哪一個是對的，至少有一個是錯的。

所以下一步要**建置**：把 `DelayFrames` 從 3 調大（例如 12，比 `KeepFrames = 8` 再寬一些），
用今天最快當的配方（`gc=10` ＋ noclear，第 4／7 張）跑。改一個常數，
而且**兩邊都要帶**（E 樹的 `Plugins/DreamGUI` 與上游 `damody/DreamGUI` 的 clone）。
活過 30 張 ⇒ 保護期太短就是機制，而修法是把兩個保護期統一；
還是第 4／7 張當 ⇒ 連這條也不是，那就只剩「拿帶除錯資訊的 shader 把 `0x45f90`
對到 `MainPS` 的哪一行取樣」這條路，而那需要重新 cook。

#### 正式修法的挂点与条件（出处先给，程式等判准格的结果）

**判准**：把「等几帧」换成「等 GPU 跑完」。
- `FRHIGPUFence`（`RHIResources.h:2397`）的 `Poll()`：当且仅当 fence 已插入**且 GPU 已发讯**才为真，
  注释自己写明「不要在循环里 poll……回 false 就继续做有用的事，**稍后再查，最好是下一帧**」——
  正是 `Tick_RenderThread` 的形状。
- 写入端 `FRHICommandList::WriteGPUFence`（`RHICommandList.h:3163` → `RHIWriteGPUFence_TopOfPipe`）。
- 队列现在被 tick 的位置是 `FDreamUIRenderer::PostRenderView_RenderThread`
  （`DreamUIRenderer.cpp:250`），那里手上有 `FRDGBuilder`，所以 fence 用一个极小的 RDG pass 写。

**哪几支真的需要 fence**（条件一，先确认再写，不要给已经安全的那支再加一层）：

| 支 | 现在的行为 | 需要 fence 吗 |
|---|---|---|
| `Hold(FTextureRHIRef)` | 放掉一份 refcount | **不需要**。refcount 归零时 `FRHIResource::MarkForDelete` 把它丢进 `PendingDeletes`（`RHIResources.cpp:45`），再由 `DeleteResources` 经 `ImmediateFlush(..., ERHISubmitFlags::DeleteResources)` 在 RHI 执行绪上销毁，而 D3D12 那一层是 EOP sync point 围栏过的。**引擎已经等 GPU 了。** |
| `Hold(TRefCountPtr<IPooledRenderTarget>)` | 还回 render target 池等着被重用 | **需要**。重用不等于销毁，池子可以在 GPU 还在读的时候把它交给别人。 |
| `Later(TUniqueFunction)` | 裸 `delete`（例如材质 proxy） | **需要**。完全不经过 RHI 的 refcount 与延迟删除。 |

**条件二（不准有「永远不释放」）**：fence 比帧数严格，代价是**没有下一帧就永远 poll 不到**
（读卡器关掉、canvas 停止绘制、viewport 拆掉、模组 shutdown）。排水路用
`SubmitAndBlockUntilGPUIdle()`（`RHICommandList.h:4674`；`BlockUntilGPUIdle()` 在 5.9 标为 deprecated，
所以用前者）在拆除／shutdown 时一次放干。
**不用「超过 N 帧就放」当保险**——那等于把这个 bug 原样请回来，这句要写进注释。

**条件三**：fence 用小轮替池重复用，不每帧新配；写 fence 的成本要有数字，不靠「应该可忽略」。

**条件四**：两个窗口都接到同一个判准之后，把 `DelayFrames = 12` 那笔诊断常数**退回去**，
不要让树里同时留着「诊断值 12」和 fence 判准。诊断那笔留在 git 历史里就够。

**验收**：最凶配方两趟 ＋ 1 对 1 进出 ×3 → 30 张一趟，报「配方／释放事件／水位／张数」，
并讲明峰值到了多少，而不是只说「没当」。

### `DelayFrames = 12` 兩趟都當（第 9 張、第 15 張）——所以只否掉 12，接著跑 240

建置 13:54（`UnrealEditor-DreamGUIRenderer.dll` 13:53），兩趟跑的是**同一個二進位**
（兩趟記的 HEAD 不同只是因為我中間提交過文件，DLL 的 mtime 兩趟都是 13:54）。
配方是今天最凶的那個：`gc=10` ＋ noclear。

| 趟 | 當在第幾張 | 大批釋放次數 | 次／卡 | 累計釋放 | transient 存量峰值 |
|---|---:|---:|---:|---:|---:|
| 第 1 趟 | **9** | 4 | 0.44 | 578 | 289 |
| 第 2 趟 | **15** | 7 | 0.47 | 883 | 304 |

同配方的對照：`DelayFrames = 3` 那兩趟當在**第 7 張**與**第 4 張**（後者開著 crash 診斷）；
關 defrag 那趟第 15 張。**9 與 15 落在同一堆數字裡，沒有跳出趟間差異。**

**判準照跑之前寫的執行：預測是「活過 30 張」，而它當了，所以 12 被否掉。**
但**否掉 12 不等於否掉「保護期太短」**——12 這個數字本身沒有依據
（「GPU 落後 3 帧」那個數字已經被標成不可用，因為它是在裝置已死那一刻量到的）。
所以下一步**不是**去付 `r.Shaders.Symbols=1` 重新 cook 的錢，而是
**把 `DelayFrames` 調到 240 再跑兩趟**：240 大到蓋住任何合理的 GPU 落後，
**240 還當才能說這個隊列不是機制**。一趟的成本遠低於重新 cook。
（建置 11.16 秒，所以這個退路幾乎是免費的。）

**附帶一個對機制有用的觀察**：這兩趟的釋放次／卡是 **0.44 與 0.47**，
和 `gc=10` 的其他趟（0.47、0.57）一致，而 transient 存量峰值只有 289／304——
**再一次：水位低、釋放密，照樣當。** 釋放密度這條軸在這兩趟裡又被複製了一次。

### 那 18 張縮圖走哪一支：**它們就是 `DrawTextureHolds` 的名單**，而被取樣的集合比被保護的集合大

**直接答案**：`DreamGUI.LogHeldTextures` 那行 log **就印在登記進 `DrawTextureHolds` 的那個迴圈裡**
（`DreamCanvas.cpp`：`if (LogHeld->GetInt() != 0 && !DrawTextureHolds.Contains(Texture)) UE_LOG(...)`
緊接著 `DrawTextureHolds.Add(Texture, InUse);`）。
**所以那份名單就是 `DrawTextureHolds` 的內容**——那 18 張縮圖**確實在 8 帧的 UObject 窗口裡**，
不是「被取樣但沒進任何窗口」。

**於是按第二個分支推下去：它們本該是安全的**（8 帧 UObject hold ＋ 銷毀後 RHI 那側有 EOP 圍欄），
**所以受害者很可能不是那 18 張之一**。而查下去會看到一件更根本的事：

**`MainPS` 綁的貼圖比 `DrawTextureHolds` 收的多。** `DrawTextureHolds` 的 `Now` 集合只收
`MaterialProxyReferences` 裡的貼圖，加上每個 draw call 的 `Texture`／`FontTexture`／
`MaskTextures.Slots[0]`／`Slots[1]`。而 `DrawBuiltInBatch` 實際綁進 pixel shader 的是：

| 綁進 `MainPS` 的 | 在 `DrawTextureHolds`（8 帧 UObject）裡嗎 | 它的保護是什麼 |
|---|---|---|
| `MainTex`／`FontTex`／`MaskTex` | **在** | 8 帧 UObject hold |
| `WidgetDataTex`／`ClipDataTex`／`RectBlockDataTex`／`PaintDataTex` | **不可能在**——它們是 `FDreamUIDataTexture` 的裸 `FTextureRHIRef`（`RHICmdList.CreateTexture` 建的），**根本不是 UObject** | 只有長大重建時那 3 帧（`DreamUIDataTexture.cpp:143` 的 `Hold(TextureRHI)`），而且是經 `UpdateTextureReference` 綁的 |
| `BackdropTex`／`SceneDepthTex` | **不在** | **完全沒有**——它們不是 DreamGUI 的東西，是場景／RDG 那邊的 |

**所以「被取樣的集合」比「被保護的集合」大，而且大出來的部分有兩類**：
外掛自己的資料貼圖（只有 3 帧，長大就重建），以及**根本不屬於外掛的場景貼圖**
（`SceneDepthTex`、`BackdropTex`，由 RDG／場景那邊管生命週期，DreamGUI 對它們沒有任何窗口）。

**這一條也解釋了為什麼 3→12 沒有用**：12 只放寬了外掛自己那個隊列，
而**場景那兩張完全不在這個隊列裡**，放寬多少都不會動到它們。

**所以 240 那格的結果要這樣讀**（先登記，免得事後拿它解釋任何結果）：
- **240 活過 30 張 ⇒** 受害者在外掛自己握的那幾支裡，fence 修法直接對症；
- **240 還是當 ⇒ 受害者很可能是 `SceneDepthTex`／`BackdropTex` 那一類**，
  也就是**外掛綁了一張它不擁有、也沒有任何窗口保護的貼圖**。
  那麼 fence 那筆仍然該做（它修的是 pooled RT 與裸 `delete` 兩個真實存在的裸洞），
  **但不准拿它當這個 crash 的修法**——照協調立的標準，那會是「讓當機消失的旋鈕」換成一筆程式。
  那種情況下該查的是**外掛對這兩張的取用方式**（是否該改成 RDG 的 external texture
  讓 RDG 管生命週期，或在錄命令那一刻確認它們仍然有效）。

### 那 18 張縮圖**已經是一個固定重複用的池**，所以「改成不銷毀」那一格不用建——它已經是現況

`OKReaderScreen.cpp` 的縮圖是池，不是每翻一張卡 create／destroy：
`MakeTexture(const FThumb&)` 只在**池要長大**時建一張（`constexpr int32 TileWidth=288,TileHeight=402`），
而換圖走 `Refill(UTexture2D*, const FThumb&)`——**原地更新同一張貼圖**
（`FUpdateTextureRegion2D` ＋ 自己一份 pixel 複本交給 render thread）。

而且這件可以用已有的 dump 直接證明，不必建置：`ListTextures` 的每一列都帶尺寸，
所以把 `288x402` 那些挑出來比名字——**兩個格子、前十二張卡，18 張縮圖的名字一次都沒變**：

```
gcbase_clear  card 1..12: 18 thumbs, new=0 gone=0（每一張卡都是）
d12_pass2     card 1..12: 18 thumbs, new=0 gone=0（每一張卡都是）
```

**結論有三層：**

1. **那一格不用跑**：「把縮圖從每翻一張卡銷毀重建改成不銷毀」**已經是現況**，
   建了也量不到任何差別。（這是今天第二次「要測的那個狀態已經是現狀」——
   第一次是面板那條 cvar 的預設已經改掉了。）
2. **縮圖不可能是受害者**：它們既在 `DrawTextureHolds` 的 8 帧窗口裡（名單就是那個窗口的內容），
   **又從頭到尾沒有被釋放過**。沒被釋放的東西不會變成「取樣到已經放掉的資源」。
3. **所以我量到的那些「大批釋放」不是 UI 貼圖，是角色貼圖**——退休的 `KKPreviewActor` 那一批。
   這把問題推到一個更尖的形狀：**被釋放的東西（角色貼圖）和故障的取樣器（UI 的 `MainPS`）
   屬於兩個不同的子系統，它們只共用同一個配置器**（唯讀貼圖池）。
   也就是說，要解釋的不是「DreamGUI 放掉了它還在用的東西」，
   而是「**別人放掉東西，卻讓 DreamGUI 的 draw 讀到一個不屬於任何堆的位址**」。

**順手再關掉一個候選**：`BackdropTex` 不是裸的——那個 pass 的參數結構用
`RDG_TEXTURE_ACCESS(BackdropTexture, ERHIAccess::SRVGraphics)` 宣告它（`DreamUIRenderer.cpp:850`），
所以 RDG 會保證它活過這個 pass。`SceneDepthTex` 同一條路。
**所以「外掛綁了一張沒人保護的場景貼圖」這個候選也站不住**，
上一節登記的「240 還是當 ⇒ 受害者是場景那兩張」那條讀法要收回：它們有 RDG 管。

**所以 240 的結果現在只剩兩種讀法**：
- **活過 30 張 ⇒** 受害者在外掛自己握的那幾支（資料貼圖、圖集）裡，fence 修法對症；
- **還是當 ⇒** 受害者既不是縮圖（沒被釋放）、也不是場景那兩張（RDG 管），
  那就只剩**資料貼圖／圖集**（都在外掛手上、都會重建）或**跨子系統的配置器層面**。
  後者的話，便宜的下一格是**把那 18 張縮圖之外的 UI 貼圖也排除掉**：
  用 `DreamGUI.LogHeldTextures` 的名單比對當機前最後一次圖集／資料貼圖重建的時間點。

### `DelayFrames = 240`：第一趟活過 30 張，第二趟當在第 27 張——所以隊列**在機制裡**，但**帧數不是判準**（2026-11-19 14:01–14:10）

同一個二進位（`UnrealEditor-DreamGUIRenderer.dll` 13:54 之後重建，`build-delay.sh 240`），同配方（`gc=10` ＋ noclear）兩趟。

| 格 | `DelayFrames` | 當在第幾張 | 大批釋放次數 | 次／卡 | 累計釋放 | transient 存量峰值 |
|---|---:|---:|---:|---:|---:|---:|
| 第 1 趟 | 3 | 7 | 4 | 0.57 | 599 | 309 |
| 第 2 趟 | 3 | 4 | — | — | — | — |
| 第 1 趟 | 12 | 9 | 4 | 0.44 | 578 | 303 |
| 第 2 趟 | 12 | 15 | 7 | 0.47 | 883 | 318 |
| 第 1 趟 | 240 | **活過 30 張** | 17 | **0.57** | 1983 | **305** |
| 第 2 趟 | 240 | 27 | 15 | 0.58 | 1720 | 299 |

**一、這是今天第一個「控制住其他兩條軸、只動一個變數」的結果。**
`DelayFrames=3` 的第 1 趟和 `DelayFrames=240` 的第 1 趟，**釋放次／卡一樣（0.57 對 0.57）、
存量峰值一樣（309 對 305）**，一個死在第 7 張，另一個跑完 30 張。
之前兩條軸（存量、釋放密度）都是在它們自己也在動的時候比的；這一格不是。
**所以隊列確實在機制裡**——如果受害者從來不經過 `FDreamUIDeferredRelease`，
把 3 改成 240 就不可能改變當機的分布，而它改變了四倍。

**二、同時它也否掉「GPU 還沒跑完那張命令清單」這個解釋。**
讀卡器這一趟是 **165.5 FPS**（從 log 的帧號計數器累加 35,704 帧／215.7 秒算出，
`GFrameNumberRenderThread`，不是 per-view 的 tick），所以 **240 帧 = 1.45 秒**。
GPU 落後是毫秒級的事，**沒有任何待跑的命令清單能撐 1.45 秒**。
那麼在資源被放掉之後還去讀它的，不是「一張已錄好還沒跑的 draw」，
而是**某個把它快取起來、每帧重新提交、直到自己被重建才換掉的東西**。

**三、對已批准的 fence 修法的影響（要講清楚，不要把它當成這個 crash 的修法）：**
fence 比帧數嚴格，而且它補的兩個洞（pooled RT 還池重用、裸 `delete`）是真的洞，該做；
**但照這一格的數字，它大概修不掉這個 crash**——fence 只保證「已錄／已送出的命令跑完」，
而這裡要對付的是一個撐過 1.45 秒的快取引用。照協調立的標準，
那會是「拿一筆程式換掉一個讓當機消失的旋鈕」，所以**驗收不算過，先不動手**。

**四、收穫是候選集被縮到五個呼叫點**（全樹只有這五個，`grep` 可查）：

| 呼叫點 | 交出去的是什麼 | 由什麼觸發 |
|---|---|---|
| `DreamUIDataTexture.cpp:143` | 資料貼圖長大時換掉的舊 `FTextureRHIRef` | UI 的 draw data 變多 |
| `DreamUICompositor.cpp:325` | `PopAndComposite` 還回池的 `IPooledRenderTarget` | 每次 composite |
| `DreamUIMaterialProxy.cpp:89`／`:95` | `delete FDreamUIMaterialProxy`（一個 `FMaterialRenderProxy`） | **GC**（`PostReachabilityAnalysis` → `LetGoOfUnreachable`） |
| `DreamUIRenderer.cpp:1252` | canvas target texture | canvas 重建 |

**第三行值得注意**：proxy 的生命週期是**掛在 GC 上的**——
`FDreamUIMaterialProxy::Create` 把 `LetGoOfUnreachable` 註冊在 `PostReachabilityAnalysis`，
而 `RenderThreadParameters.Textures` 裡存的是**裸 `const UTexture*`**，
只有在 reachability 那一刻才被剔除（`DreamUIMaterialProxy.cpp:143-173`）。
這和 `gc` 那條軸是同一個東西：`gc=10` 最快當、`gc=300`（整格沒發生過一次 GC）唯一完全沒事。
而且**數字對得上**：`gc=10` 一張卡約 8 秒 → 0.8 次 GC／卡，量到的大批釋放是 0.57／卡；
基線 61.1 秒 → 0.13 次／卡，量到的是 0.13／卡。
**所以我一直在數的「大批釋放事件」其實就是 GC 的 purge。**

**五、下一格的提案（一次建置、兩個格子、每格兩趟，不必付重新 cook 的錢）**：
把 `DelayFrames` 拆成**每個呼叫點各自一個**，
先讓 **只有 proxy 那條** 是 240、其餘維持 3，再反過來（proxy 是 3、其餘 240）。
**預先登記讀法**：哪一半帶著「活過 30 張」，受害者就在那一半的呼叫點裡；
兩半都早當 ⇒ 受害者不只一個呼叫點，或 240 那格的第 1 趟只是運氣。
這是同一條「同一個變數、不同刻度」的做法，今天只有它產生過可用的結論。

### 盲點查完了：`MainPS` **一個 buffer SRV 都沒綁**，所以受害者是貼圖；而背景那張的來源是 `GRenderTargetPool`＋RDG transient（2026-11-19）

**問題**：`MainPS` 會不會其實在讀一個**緩衝區**？那樣一整天的 `ListTextures` 比對就看不到它，
而 page fault 看起來和「取樣一張死掉的貼圖」一模一樣。

**答案：沒有。** `FDreamUIBasePS::FParameters`（`DreamUIBaseShaders.h:152-184`）裡**每一個資源參數**
都是 `SHADER_PARAMETER_TEXTURE`（`Texture2D`／`Texture2DArray`）或 `SHADER_PARAMETER_SAMPLER`，
其餘是純量。整個 `DreamGUIRenderer` 模組 grep
`SHADER_PARAMETER_SRV`／`SHADER_PARAMETER_RDG_BUFFER`／`StructuredBuffer`／`ByteAddressBuffer`
**一行都沒有**。per-draw 的 widget／clip／rect block／paint 陣列全部走**資料貼圖**
（`FDreamUIDataTexture`），這正是那個類別存在的理由。
**所以這條分支關掉：受害者是一張貼圖**，而且是 `MainPS` 綁的那十張之一。

**順著看下去，背景那張的真實身分比我上一節寫的更有意思**（`DreamUICompositor.cpp:234-241`、`:306-325`）：

```
GRenderTargetPool.FindFreeElement(..., Frame.Pooled, TEXT("DreamUI_GroupTexture"));
Frame.Texture    = GraphBuilder.RegisterExternalTexture(Frame.Pooled, ...);
Frame.TextureRHI = Frame.Pooled->GetRHI();        // 裸 FRHITexture*，存在 frame 結構上
...
FRDGTextureRef Copy = GraphBuilder.CreateTexture(Desc, InName);   // 背景「拷貝」是 RDG transient
...
FDreamUIDeferredRelease::Hold(Top.Pooled);        // 還池之前先壓住 DelayFrames 帧
```

有兩件事因此對上：

1. **`Hold(Top.Pooled)` 就在這個隊列裡**，所以 `DelayFrames` 那一格會動到它——
   這和 240 的結果一致（受害者必須經過這個隊列）。它壓住的是**還池重用**，
   不是銷毀：`GRenderTargetPool.FindFreeElement` 會把同一個元素交給下一個要求者。
2. **背景拷貝是 `GraphBuilder.CreateTexture` 建的 RDG transient**，
   transient allocator 會把它的記憶體**和別的資源疊在同一塊堆上**。
   這是目前唯一能產生「位址不屬於任何堆」而**不需要 defrag** 的路，
   而「`Found 0 active heaps containing page fault address`」正是還沒解釋掉的那件事。

（`SceneDepthTex` 仍然出局：它不進這個隊列，而且 `RDG_TEXTURE_ACCESS` 宣告過。
而 `BackdropTex` 不一樣——它的來源同時在隊列裡、又是被疊記憶體的 transient。）

**引擎自己就有關掉這條路的開關，四個都查過出處、都不是 read-only**
（`Engine/Source/Runtime/RenderCore/Private/RenderGraphPrivate.cpp`，全部 `ECVF_RenderThreadSafe`）：

| cvar | 行 | 作用 |
|---|---:|---|
| `r.RDG.TransientAllocator` | 251 | `0` 整個關掉 transient allocator，所有 transient 資源改走普通池 |
| `r.RDG.Debug.ExtendResourceLifetimes` | 43 | 圖內資源不得與任何其他資源共用記憶體——引擎自己寫「用來查 transient aliasing 是不是元凶」 |
| `r.RDG.Debug.DisableTransientResources` | 53 | 把資源從 transient allocator 濾掉 |
| `r.RDG.Debug.FlushGPU` | 34 | 每個 pass 之後 flush GPU——任何「GPU 還沒跑完」的危害都不可能成立 |

**跑的是第一個**，而且**先把 `DelayFrames` 退回 3**：240 那格的基線是「一趟活、一趟死在第 27 張」，
拿一個「活過 30 張」去對這種基線讀不出東西；3 那格同配方死在第 7 張（帶診斷的那趟第 4 張），這才是尖的。
**讀法先登記**：`r.RDG.TransientAllocator=0` 兩趟都活過 30 張 ⇒ 受害者是被 allocator 疊記憶體的 RDG transient
（`MainPS` 讀到的只有背景拷貝這一個）；還是死在第 4–9 張 ⇒ aliasing 出局，
隊列裡剩下的就是 `GRenderTargetPool` 那個元素（`Frame.Pooled`）或資料貼圖（`DataTexture.cpp:143`）。

### 內建路徑的貼圖生命週期其實是設計過的，所以「proxy 存裸 `UObject*`」這個嫌犯比看起來弱（2026-11-19）

協調提的機制是：外掛存裸 `const UTexture*`，物件被 purge 之後還拿它去取
`TextureReference.TextureReferenceRHI`，於是**每一帧現算出一個壞的 RHI 指標**。
這個形狀很漂亮（壞指標不是舊的、是新產生的，所以 EOP 圍欄、描述子快照、defrag 全都不相干），
**但照程式看，這條路有兩層保護，而且是刻意做的**：

1. **遊戲執行緒那側是弱參照。** `FDreamUIBuiltInDrawParams` 的九支貼圖全是
   `TWeakObjectPtr<const UTexture>`（`DreamUIBaseShaders.h:55-77`，欄位註解寫明
   「Game thread: the textures, as the canvas names them. **Never read on the render thread.**」），
   由 `GetTexturesForRenderCommand()` 在遊戲執行緒上 `Get()` 成裸指標再交給 render command。
2. **繪製執行緒那側是計數參照，而且死了會變黑。**
   `ResolveTextures_RenderThread`（`DreamUIBaseShaders.cpp:26-55`）存的是
   `FTextureReferenceRHIRef`——**貼圖參照物件**的計數參照，不是貼圖本身。
   而 `FDynamicRHI::RHIUpdateTextureReference`（引擎 `RHI/Private/DynamicRHI.cpp:586`）是
   `InReferencedTexture ? InReferencedTexture : FRHITextureReference::GetDefaultTexture()`，
   所以**貼圖死掉之後，那個參照指向全域黑貼圖，不是懸空**（`RHITextureReference.h:61`
   的註解也寫明這個 fallback 的用途）。

**剩下的窗口只有一個**：遊戲執行緒 `Get()` 出來的裸指標，到繪製執行緒 `ResolveTextures_RenderThread`
真的 deref 它之間。而這段**被引擎自己的 destroy fence 蓋住**：`UTexture` 的
`IsReadyForFinishDestroy` 要等資源釋放的 fence 過了才允許 purge，
也就是繪製執行緒走過那個點之後——在它之前排進去的 render command 早就消費掉了。

**所以預測是「斷言一次都不會命中」。** 斷言還是值得加（命中就是真發現，而且是便宜的），
但**不要把它當成主要證據**，拆常數那兩格才是。
欄位註解最後一段還留著上一次的病歷：
「The resource pointers they replace were kept across frames and left dangling by each of those until the next
rebuild of the draw call」——**作者已經為了同一類 bug 把裸資源指標換成參照過一次**。
這也是為什麼我不認為第二次還會是同一個形狀。

**同時要承認這條路解釋不了的事**：它完全不解釋 `DelayFrames` 為什麼有效，
而那是今天唯一控制住其他兩條軸測出來的效應。所以要嘛有兩個洞，
要嘛 `DelayFrames` 是透過某種時序副作用起作用的，這點目前沒有證據，不要替它編故事。

### aliasing 那格的前提查清了：`BackdropTex` 綁的是 **transient 拷貝**，所以旋鈕接上了——但它**不跨帧**，所以我預測它還是會當（2026-11-19，跑完之前寫）

**前提（跑之前查，不事後補）**：`MainPS` 的 `DreamUI_BackdropTex` 來自 `Backdrop->GetRHI()`
（`DreamUIRenderer.cpp:1014`／`:1618`），而那個 `FRDGTextureRef` 一路追上去是
`FDreamUICompositeStack::CopyFrom`（`DreamUICompositor.cpp:285-320`）用
**`GraphBuilder.CreateTexture`** 建的（MSAA 走 `:306` 的 resolve，其餘走 `:315` 的 copy），
**不是** `Frame.Pooled->GetRHI()` 那個池子元素。
**所以 `r.RDG.TransientAllocator=0` 確實動得到它，這一格是可讀的。**

**但同一次追蹤也否掉了這一格的修法前提。** `Backdrop` 是 `PopAndComposite` 裡的**區域** `FRDGTextureRef`，
`->GetRHI()` 是在 **pass 的 lambda 之內**讀的（`:450` 合成、`:1618` 內建），
而那個 `FDreamUIBuiltInDrawCache`（`DreamUIRenderer.cpp:860-890`）**只存 shader 與 pipeline 狀態，沒有任何貼圖**，
而且是 lambda 裡的區域變數（`:1610`／`:2359`）。
**沒有任何東西把背景拷貝留到下一帧**，所以它的用法正好就是 RDG transient 的語意。
**因此預測登記成：這一格還是會當。** 若真的活過 30 張，那要先解釋為什麼——
不能直接當成「aliasing 就是元凶」。

`ERDGTextureFlags::MultiFrame` 確實存在（引擎 `RenderGraphDefinitions.h:191`），
但它的用途寫的是「survive through frame, that is important for **multi GPU alternate frame rendering**」；
既然沒有東西跨帧留著那張拷貝，這個旗標也不是修法。

**另記一筆（不是這個 crash 的線）**：`Frame.TextureRHI = Frame.Pooled->GetRHI()`（`DreamUICompositor.cpp:241`）
是裸指標，但池子元素被交給下一個要求者之後，它仍然指著**一張活著的貼圖**——
所以它的失效形狀是「畫出別人的內容」，不是 page fault。
以後若有人報「UI 偶爾閃出別的畫面」，答案在這裡，不要再從當機這條線找。

**還要修正一個把兩條線接起來的猜想**：`Hold(Top.Pooled)` 延後的是**還給 `GRenderTargetPool`**，
而背景拷貝走的是 **RDG transient allocator**——**在引擎這一層是兩個不同的池**，
所以 `DelayFrames` 與 `TransientAllocator` 不是同一件事的兩頭。
它們要到 **D3D12 那一層才共用同一個唯讀貼圖池配置器**，
這正好是之前記下的「被釋放的子系統和取樣的子系統只共用一個配置器」那個形狀。

### F 樹那份過期 `unreal_slot.lua` 回過假的 `go`：用**每張卡的實際耗時**判污染，結論是今天沒有一格需要重跑（2026-11-19）

協調通報：F 樹的 `unreal_slot.lua` 是過期副本，今天至少回過一次假的 `go`，
f-sceneload 照那個 `go` 做了一次完整建置（兩個 Development 目標＋515 個測試，吃滿 CPU），
時間落在我獨占機器的時段裡。

**判法不必等對方的時間點**：`knob.sh` 每張卡都寫一個 `<卡號>.tex`，
所以**那些檔案的 mtime 就是每張卡的牆上時間**，吃滿 CPU 的建置一定會讓我的每卡耗時整段變長。
全部格子算下來：

| 格 | 時間窗 | 張數 | 每卡中位數 | 異常長的間隔 |
|---|---|---:|---:|---|
| `base_clear` | 12:22:52–12:24:54 | 16 | 4.9 s | 第 16 張（當機那張） |
| `gcbase_clear` | 12:54:44–13:02:01 | 23 | 5.9 s | 第 23 張（當機那張） |
| `gc10_clear` | 13:06:29–13:07:45 | 15 | 5.2 s | — |
| `gc10_noclear` | 13:10:02–13:15:33 | 7 | 6.2 s | 第 7 張（當機那張） |
| `panel_on_clear` | 13:18:03–13:20:24 | 14 | 6.1 s | 第 14 張（當機那張） |
| `ax_nowarm`／`ax_gc300`／`ax_dred` | 13:24:40–13:35:54 | 30／30／30 | 5.8／5.9／5.7 s | — |
| `name_gc10` | 13:38:37–13:44:56 | 4 | 5.9 s | 第 4 張（當機那張） |
| `defrag_off` | 13:46:54–13:48:01 | 14 | 4.9 s | — |
| `d12_pass1`／`d12_pass2` | 13:55:31–13:59:31 | 9／15 | 4.9／5.1 s | — |
| `d240_pass1`／`d240_pass2` | 14:02:19–14:10:11 | 30／27 | 6.2／5.8 s | 第 27 張（當機那張） |

**每一個「異常長的間隔」都正好是當機／逾時那一張，沒有任何一格出現中途變慢的區段**，
而每卡中位數整天都在 4.9–6.5 秒之間，沒有一格偏離。
**所以兩個 Development 目標＋515 個測試那段吃滿 CPU 的工作沒有重疊到任何一格的量測區間**，
今天沒有一格需要重跑。（之前記下的 13:40 那次 CPU 爭用落在 `name_gc10` 的窗裡，
而那一格的中位數 5.9 秒也沒有異常，與當時的判斷一致。）

**要留的記號**：這個判法只看得到「卡的吞吐變慢」。若爭用只改變時序而不明顯拖慢每卡耗時，
它測不出來，所以上面寫的是「沒有證據顯示污染」，不是「保證沒有污染」。

**另外確認一件事**：我今天 33 處問 slot／gate 全部用的是 C 那份的絕對路徑
`/c/portable/OpenKoikatsu/Tools/unreal_slot.lua`（`grep` 查過，沒有一處問樹裡的副本），
所以我拿到的 `go`／`wait` 都是真仲裁者回的。E 樹那份副本仍是舊的，等 e-fork-2 的窗口把 `9cf1bd7c7` cherry-pick 進來。

### 四個呼叫點的篩選：只有兩個「被放掉之後還跨帧被用」，所以拆 cvar 那格是二選一而不是四選一（2026-11-19，純讀碼）

判準：那個隊列唯一的作用是**延後「放掉／還池」**，所以**能被 `DelayFrames` 影響的受害者，
必須是「被放掉之後還有人在後面的帧裡繼續用它」**。嚴格在帧內用完的東西，延後釋放對它沒有意義。

| 呼叫點 | 放掉的是什麼 | 跨帧被繼續用？ | 出處 |
|---|---|---|---|
| `DreamUIDataTexture.cpp:143` | 資料貼圖長大時**被換掉的舊 RHI** | **否** | 沒有任何結構留著舊的裸 RHI：所有 draw 綁的是**參照**，而 `ReplaceTexture` 當場 `UpdateTextureReference` 指到新的（`:146-148`）。只有「長大之前已經錄好的 draw」還讀舊的，那是**一帧內**的危害，3 帧本來就蓋住 |
| `DreamUICompositor.cpp:325` | 還給 `GRenderTargetPool` 的 `Frame.Pooled` | **否** | `FDreamUICompositeStack Stack(...)` 是建 pass 那個函式裡的**區域變數**（`DreamUIRenderer.cpp:1571`、`:2227`），整個堆疊活在**一張圖之內** |
| `DreamUIMaterialProxy.cpp:89`／`:95` | `delete FDreamUIMaterialProxy` | **是** | proxy 本來就是跨帧物件：`LiveProxies()` 記著它、widget 持有 shared ref、`RenderThreadParameters` 存在 proxy 上；最後一個參照消失才 delete |
| `DreamUIRenderer.cpp:1252` | `CanvasTargetTexture` | **是，定義上就是** | 它是 view extension 的**成員**（`DreamUIRenderer.h:345`），由 `:2800` 從外面設定、`:396` 與 `:1209-1211` 跨帧讀，換回螢幕目標時才放掉 |

**所以拆 cvar 那格從「四選一」變成「二選一」**：material proxy 與 canvas target。
**但要注意刻度不是一對一的**：`CanvasTargetTexture` 是 `FTextureRHIRef`，和資料貼圖**共用 `Frames.Texture` 這一個刻度**。
篩選已經把資料貼圖排除，所以讀法可以寫得更緊：

- **`Frames.Texture` 動了當機 ⇒ 受害者是 canvas target**（`Renderer.cpp:1252`），
  因為同一個刻度下的另一個（資料貼圖舊 RHI）不跨帧；
- **`Frames.Func` 動了 ⇒ material proxy**（`MaterialProxy.cpp:89/95`）；
- **`Frames.Pooled` 動了 ⇒ 和這份篩選矛盾**（堆疊是帧內的），那就是篩選錯了，
  要回去找「被 pop 掉的 frame 還被誰留著」；
- **四個都不動 ⇒** 240 那個效應不是這個隊列本身，或 240 第 1 趟的存活是運氣。

**canvas target 這一條還有一個額外的理由值得先寫下來**：render-target 類型的 canvas
（`EDreamUIRendererType::RenderTarget`）畫出來的目標，**會被別的 widget 當成貼圖取樣**——
那正是 `MainPS` 的 `MainTex`。所以它同時滿足「跨帧持有」與「被 `MainPS` 取樣」兩件事，
是目前唯一同時滿足的候選。

### 污染這件結清了：那一分鐘的 CPU 測試落在兩格之間的空檔（2026-11-19）

f-sceneload 給了確切時間，兩件都對得上，**而且和我用每卡耗時判出來的結果一致**：

| 它做了什麼 | 時間 | 落在哪 |
|---|---|---|
| 515 個 Rust lib 測試、8 執行緒吃滿 CPU | **13:50:31–13:51:35** | **兩格之間的空檔**：`defrag_off` 13:48:01 結束，`d12_pass1` 13:55:31 才開始 |
| 兩個 Development 目標建置 | 14:14:23–14:16:35 | 我 14:19:49 才 claim slot1；中間我自己在 14:19:44 建置（建置不是量測） |
| f-yvonne 的 9 秒 `cargo check` | 14:17:42 | 同上，落在我自己的建置時段，不是量測 |

**所以沒有任何一格的量測區間被壓到，一格都不用重跑**，兩種方法（每卡耗時、確切時間窗）互相印證。
它那個假 `go` 的推論它自己也更正了：當時我還沒 claim，所以那個 `go` 是對的。

### `r.RDG.TransientAllocator=0`：兩趟都在**開第一張卡之前**就當，而且是**一模一樣的簽章**——這一格讀不出張數，但給出今天最便宜的重現（2026-11-19 14:19–14:35）

兩趟都沒跑到第一張卡：`STOP at card 1 ... no card reader mailbox yet`、`unreal=0`。
第 2 趟的 log 把事情說清楚了（`20261119-143243-7d0fdb96.log`）：

```
SecondsSinceStart 19        <CrashType>GPUCrash</CrashType>
Active Shaders: Function = MainPS   Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF
"Device state": "Error_DMA_PageFault"      "Shader name": "fragment_02"
PageFault at VA GPUAddress "0x2E87F9000"   Current frame ID: 2132
PageFault: Logging all resource enabled: No
PageFault: Found 0 active heaps containing page fault address
```

**簽章和整天那幾次完全一樣**（同一個 `MainPS`、同一個 shader hash、同樣的 `fragment_02`、
同樣「位址不屬於任何堆」，而且 `Logging all resource enabled: No`，所以那幾個 0 仍然是 artifact）。
差別是**它發生在第 19 秒、第 2132 帧，一張卡都還沒開**。

**先照登記的讀法判定：這一格對「死在第幾張」是不可讀的**（旋鈕副作用太大），**不是 aliasing 的證據**。
判準是：今天在預設配置下跑過 19 趟，**沒有一趟在啟動階段當過**，
所以「啟動就當」是這個旋鈕自己足以造成的，不能拿它去支持或反對 aliasing 那個假設。

**但它有兩個獨立的價值：**

1. **這是今天最便宜、最穩的重現**：**19–25 秒、兩趟兩中**，相對於原本要翻 4–30 張卡的擲骰。
   任何候選修法都可以先拿它篩一遍（**過不了就一定不對；過了也只是必要條件**）。
2. **它證明這個外掛可以在「一張卡都沒開」的情況下讓 `MainPS` page fault**，
   也就是沒有角色貼圖被釋放、沒有卡片資料被 GC purge。
   所以**受害者可以完全只在 UI／外掛自己這條路上**。
   這沒有推翻「釋放事件＝GC purge」那條在**預設配置**下的相關性（那是另一個配置），
   但它把「受害者必須是被卡片流程釋放的東西」這個隱含前提拿掉了。

**所以 transient allocator 這條線的狀態是**：關掉它會讓同一個故障**更早、更穩**地發生，
而不是消失——這和「aliasing 是元凶」的方向相反（元凶被關掉應該不當），
也和我跑之前登記的「預測還是會當」一致，只是當得比預期早得多。

### 自我反證：canvas target 在讀卡器裡**大概根本不會被設定**，所以我自己的最強候選要降級（2026-11-19，純讀碼）

照「別只找支持的證據」做了三個檢查，三個都對 canvas target 不利：

**一、它要有一個 `RenderTarget` 模式的 canvas 才會存在。**
`CanvasTargetTexture` 只由 `FDreamUIRenderer::UpdateRenderTargetRenderer` 設定
（`DreamUIRenderer.cpp:2784-2803`），而那條路要走到
`UDreamCanvas::UpdateRootCanvas` 的 `case EDreamRenderMode::RenderTarget:`
（`DreamCanvas.cpp:313-320`，`RenderTarget = 2`，要資產自己選）才會建起 RenderTarget 類型的 view extension。
**查下去找不到任何證據讀卡器用了這個模式**：`Content/UI` 底下沒有一個資產提到 `RenderTarget`，
讀卡器 log 裡唯一的 `RenderTarget` 字樣是 `Set CVar [[r.RenderTargetPoolMin:400]]`（無關的引擎 cvar）。
**若讀卡器沒有 RenderTarget 模式的 canvas，`Hold(CanvasTargetTexture)`（`:1252`）就從來不會觸發**，
那它不可能是受害者。
（保留一點：對 `.uasset` 做二進位 grep 不完美——預設值可能根本不序列化。所以寫的是「大概不會」。）

**二、它的生命週期和 GC 無關。** 它由 canvas 的繪製週期決定（換回螢幕目標時放掉），
所以它**完全解釋不了 `gc` 那條軸**——而 `gc=10` 最快當、`gc=300` 整格沒事，是今天重複過的事實。

**三、所以 `Frames.Texture` 那一格的讀法要改**：那個刻度下原本有兩個住戶
（canvas target 與資料貼圖舊 RHI），我先前排除了資料貼圖、留下 canvas target。
現在 canvas target 大概根本不觸發，於是：

- **`Frames.Texture=240` 真的活過 30 張 ⇒ 受害者是資料貼圖舊 RHI**（`DataTexture.cpp:143`），
  **也就是我那份篩選把它排除掉是錯的**——那就要回去找「誰把舊的裸 RHI 留到了下一帧」；
- **`Frames.Texture` 不動、`Frames.Func` 動 ⇒ material proxy**，它是篩選剩下的另一個，
  而且它的生命週期**掛在 GC 上**（`PostReachabilityAnalysis`），和 `gc` 那條軸對得上；
- **兩個都不動 ⇒** 240 那個效應不是這個隊列本身。

**結論**：篩選剩下的兩個候選裡，**canvas target 這一個被我自己推翻了**，
而 material proxy 是唯一同時能解釋 `DelayFrames`（跨帧物件）與 `gc`（reachability 驅動的刪除）兩條軸的候選。
這一節寫在那四趟跑完之前，免得事後拿結果去挑一個說法。

### 把 19 秒重現當工具：改成「切功能」而不是「轉旋鈕」（2026-11-19）

單格成本從「翻 4–30 張卡擲骰」變成「19–25 秒、兩趟兩中」之後，該問的不再是旋鈕，而是
**畫面上有什麼**，一項一項拿掉。**先更正兩件會影響設計的事**：

1. **`ok.Experiment.ReaderScreenUnderOtherModes` 不是「不畫面板」的開關**，
   它管的是其他模式底下要不要顯示讀卡器畫面（整天每一格都讀回 `0`）。
2. **外掛裡沒有任何現成的 cvar 可以關掉 DreamGUI 的繪製或背景合成。**
   全樹只有這些 `DreamGUI.*`：`DeferredRelease.Frames.{Texture,Buffer,Pooled,Func}`、
   `LogDeferredRelease`、`LogHeldTextures`、`LogStaleTextures`、`Memory`、`Text.*`、
   `Debug.PermanentSpriteOnStaticAtlas`、`Diag.FindTreeBridges`、`Scroll.SnapToDevicePixels`、
   `LayerSection.*`、`GeneratedAssets.ForgetFullPaths`、`OldAssetFixtures.*`。
   **所以「切功能」那幾格要自己加 gate**，不是設定現成開關。

**第一個 gate 已經寫好（兩棵樹都有）**：`DreamGUI.Experiment.NoBackdrop`（預設 0），
加在 `FDreamUICompositeStack::CopyFrom` 的最前面（`DreamUICompositor.cpp:298-304`）：
開著時 `CopyFrom` 直接回 `nullptr`，**所有呼叫者都走它們本來就有的「沒有背景」那條路**
（`bReadBackdrop = false`，而會讀背景的混合模式照既有邏輯改畫 Alpha），
**一張背景拷貝都不會被配置或取樣**。開著時讀背景的混合模式會長得不對，其餘不變。
選 `CopyFrom` 這一點是因為它是**唯一**產生背景拷貝的地方，合成與內建兩條路都經過它。

**跑之前登記的讀法**：
- **拿掉背景就不當（兩趟）⇒ 受害者就是背景拷貝**，而且修法的形狀是
  「那張拷貝的生命週期要由持有者保證，不靠配置器的語意」；
- **拿掉背景照樣當 ⇒ 背景出局**，接著往下切（字型圖集、遮罩、資料貼圖）。

**一條硬規矩，先寫下來**：**這個 19 秒重現不能單獨當驗收。**
它是另一個配置（`TransientAllocator=0`），任何候選修法要**同時**過兩關：
19 秒重現兩趟不當，**而且**預設配置下最凶配方（`gc=10`＋noclear，今天死在第 4／7 張）
兩趟活過 30 張。只過前者就宣告修好，等於拿只在非預設配置下成立的證據當結論。

### 關鍵的一問：delete 一個 proxy 會放掉任何 `MainPS` 綁的東西嗎？**不會。**（2026-11-19，純讀碼）

`FDreamUIMaterialProxy`（`DreamUIMaterialProxy.h:42-78`）私有的全部狀態是：
`GameThreadSource`／`RenderThreadSource`（`UMaterialInterface*`，裸指標）與
`GameThreadParameters`／`RenderThreadParameters`，而 `FDreamUIMaterialParameters` 只有三個陣列：
`TArray<TPair<FName, const UTexture*>> Textures`、`Vectors`、`Scalars`——**全是裸指標與數值，沒有任何擁有權**。
它另外從 `FMaterialRenderProxy` 繼承的是**材質自己的** uniform expression 快取／uniform buffer，
那只有材質那條 draw 會綁。
**所以 delete 一個 proxy 不會釋放任何 `MainPS` 綁的資源。**

於是把兩個篩選並起來看，**它們沒有乾淨的交集**：

| 呼叫點 | ①放掉的東西跨帧被繼續用？ | ②放掉的是 `MainPS` 綁的東西？ |
|---|---|---|
| `DataTexture.cpp:143` | **否**（draw 綁參照，當場 re-point） | **是**——資料貼圖就是 `WidgetDataTex`／`ClipDataTex`／`RectBlockDataTex`／`PaintDataTex` |
| `Compositor.cpp:325` | **否**（堆疊是建 pass 那個函式的區域變數） | **間接**：`Frame.Pooled` 是 group 的目標，`MainPS` 綁的是從它**拷貝**出來的那張 |
| `MaterialProxy.cpp:89/95` | **是**（跨帧物件、GC 驅動 delete） | **否**（上面這一段） |
| `Renderer.cpp:1252` | **是**（view extension 的成員） | **原則上是**，但讀卡器大概沒有 `RenderTarget` 模式的 canvas，所以大概不觸發 |

**所以四個呼叫點沒有一個同時滿足兩個條件。** 照協調登記的分支，這表示
**`DelayFrames` 的效應大概不是「保護了受害者」，而是改變了某種時序**，
而主力工具要換成那個 19 秒重現（切功能那條路）。

### 兩個重現要分開記，目前只有簽章是共同的（2026-11-19）

| | A：預設配置 | B：`r.RDG.TransientAllocator=0` |
|---|---|---|
| 何時當 | 翻到第 4–30 張卡 | **第 19 秒，一張卡都沒開** |
| 穩定度 | 擲骰（同配方同建置會差 4→15） | **兩趟兩中** |
| 和 `gc` 那條軸的關係 | 對得上（`gc=10` 最快、`gc=300` 沒事） | **對不上**（沒有卡片、幾乎沒有 purge） |
| 共同點 | `MainPS`、`Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF`、`fragment_02`、`Error_DMA_PageFault`、位址不在任何堆 | 同左 |

**在有一個機制能同時解釋兩邊之前，紀錄寫成「兩個重現、一個共同簽章」，不假設是同一個 bug。**
任何修法仍然要兩關都過。

### `Frames.Texture=240` 第 1 趟：第 6 張就當（2026-11-19 14:38–14:40）

**首先，cvar 確認接上了**——協調要的那行 in-effect log 正是為此：
`DreamGUI deferred release frames in effect: texture=240 buffer=3 pooled=3 func=3`。
只抬 Texture 這一個刻度，其餘留 3。

結果：**當在第 6 張**（表裡最後一張是 5），簽章一樣
（`MainPS`／同 hash／`fragment_02`／`PageFault at VA 0xDFDD21000`／`Found 0 active heaps`）。
第 4–15 張是 `DelayFrames=3` 同配方的範圍，**所以只抬 Texture 沒有救到它**。
**`DreamGUI.LogStaleTextures` 在這一趟 0 次命中**，與登記的預測一致。

照登記的讀法，這一趟指向：受害者不在 Texture 這個刻度裡（資料貼圖、canvas target 都不是）。
等第 2 趟與 `Func` 那兩趟跑完再定案。

### `Frames.Texture=240` 兩趟：第 6、第 7 張，斷言 0 次命中（2026-11-19 14:38–14:47）

兩趟的 in-effect log 都確認只抬了一個刻度：
`DreamGUI deferred release frames in effect: texture=240 buffer=3 pooled=3 func=3`。

| 趟 | 當在第幾張 | `LogStaleTextures` 命中 | 簽章 |
|---|---:|---:|---|
| 1 | **6** | **0** | `MainPS`／`PageFault at VA 0xDFDD21000`／`Found 0 active heaps` |
| 2 | **7** | **0** | 同上（`0x25BC871000`） |

`DelayFrames=3` 同配方是第 4／7 張，**6 與 7 完全落在裡面，所以 Texture 這個刻度沒救到它**——
資料貼圖（`DataTexture.cpp:143`）與 canvas target（`Renderer.cpp:1252`）一起出局，
和「兩個篩選沒有交集」那張表的推論一致。
**斷言兩趟都 0 次命中，與登記的預測相符**：內建路徑沒有在解析一個已經被放掉的 `UTexture`。

### reuse 量測要比的是同一個 frame 區間，不是「整趟 vs 啟動」（2026-11-19，跑之前登記）

B 配置（`TransientAllocator=0`）在**第 19 秒、一張卡都沒開**就當，
所以它的 reuse 數字只涵蓋啟動畫面；A 配置的數字會涵蓋翻了好幾張卡。
**卡片流程本身就會改變 group 合成的密度**，所以「B 的 gap 比 A 短」可能只是兩邊在量不同的畫面。

**控住的辦法**：`LogPoolReuse` 每 600 個 render frame 報一行，而 min／max 是從啟動累計的，
所以**對同一個 frame 區間讀**——A 在 frame ≈1800／2400 那兩行，對 B 在同一區間那兩行
（B 在第 2132 帧當掉，約有三行可讀）。

**讀法**：同一區間下 B 的 gap 明顯短、distinct 明顯少 ⇒「同一個薄弱點、重用間距不同」成立，
A／B 第一次有合併的理由；兩邊差不多 ⇒ 池子周轉不是共同變數；
**只有在不同區間下才看得出差別 ⇒ 那是工作量差異，不是機制，不准拿來合併兩個重現。**

另記一條這一格的額外價值：B 配置下背景拷貝**不走 transient、改從池子配置**，
所以若模式 2（拷貝照做、綁黑）讓 19 秒的當機消失，
那同時證明「那張拷貝確實是從池子來的」與「綁的那塊記憶體就是受害者」兩件事。

### `Frames.Func=240` 第 1 趟：第 19 張（基線是第 4／7 張），第 2 趟作廢重跑（2026-11-19 14:52–14:55）

in-effect log 確認只抬了一個刻度：`texture=3 buffer=3 pooled=3 func=240`。

| 刻度 | 第 1 趟 | 第 2 趟 |
|---|---:|---:|
| 基線 `DelayFrames=3`（四個刻度都是 3） | 7 | 4 |
| `Frames.Texture=240` | 6 | 7 |
| **`Frames.Func=240`** | **19** | 作廢（見下），重跑 |

**第 19 張明顯跳出基線**（同配方同建置，`=3` 與 `Texture=240` 四趟都落在 4–7），
簽章一樣（`MainPS`／`PageFault at VA 0x25603D1000`／`Found 0 active heaps`），斷言 0 次命中。
**但它沒有活過 30 張，所以這是「推遲」不是「修掉」。**

**第 2 趟作廢的原因寫在 [ERROR_LOG](ERROR_LOG.md) 2026-11-19 那條**：
我停「第一個 UnrealEditor pid」時，第 1 趟的引擎已經自己退了，
拿到的是第 2 趟剛啟動的引擎，於是把它殺在開頭。重跑在**同一個二進位**上做。

**跑第 2 趟之前先登記讀法**（`Func` 這一條本來是被我否掉的，所以要寫清楚兩種結果各代表什麼）：
- **第 2 趟也明顯晚於基線（比如 ≥15）⇒ `Later()` 這條真的有效**，而它和
  「delete 一個 proxy 不放掉任何 `MainPS` 綁的東西」矛盾。
  出路**不是**改口說 proxy 是受害者，而是 `Tick_RenderThread` 自己的註解：
  「a release may hand something else over (a proxy's delete releasing its resources)」——
  也就是 **proxy 的 delete 是扣扳機的那一個，真正被放掉的是它跑起來時連帶交出的東西**。
  那就要去查 `~FDreamUIMaterialProxy` 實際會連帶釋放什麼。
  這也剛好對上 `gc` 那條軸（proxy 的 delete 是 reachability 驅動的）。
- **第 2 趟回到 4–7 ⇒ 第 1 趟的 19 是擲骰的上緣**，`Func` 不成立，
  四個刻度全部沒救到它，`DelayFrames` 的效應就要完全歸給時序（reuse 量測那一格）。

### 更正：**delete 一個 proxy 確實會放掉 `MainPS` 綁的東西**——經由它的 uniform buffer 的 resource table（2026-11-19）

前面我寫過「delete 一個 proxy 不放掉任何 `MainPS` 綁的東西，因為 `FDreamUIMaterialProxy` 只有裸指標與數值」。
**那句是錯的**：我只看了外掛自己的成員，沒看 `~FMaterialRenderProxy` 會放掉什麼。鏈條是：

```
delete FDreamUIMaterialProxy
  -> ~FMaterialRenderProxy            (引擎 MaterialRenderProxy.cpp:773)
       -> ReleaseResource()           (:851 -> FRenderResource::ReleaseResource)
            -> FUniformExpressionCache::UniformBuffer 被釋放   (MaterialRenderProxy.h:51)
                 -> FRHIUniformBuffer 的 ResourceTable 放掉它持有的 TRefCountPtr<FRHIResource>
                    (RHIResources.h:1286, GetResourceTable)
                      -> 那些是材質綁的貼圖；若那是最後一個參照，貼圖的 RHI 就被銷毀
```

**`FRHIUniformBuffer` 的 `ResourceTable` 是 `TArray<TRefCountPtr<FRHIResource>>`——它替材質持有那些貼圖的計數。**
而 DreamGUI 的材質參數是用名字設進去的（`FDreamUIMaterialParameters::SetTexture`），
**設的就是 canvas 那幾張貼圖（圖集、資料貼圖、sprite atlas），而內建的 `MainPS` 綁的是同一批**。
所以 proxy 的 delete **的確會放掉 `MainPS` 綁的東西**，只是不是它自己擁有，而是經由 uniform buffer。

**這解掉了我登記的那個矛盾**，而且形狀正是隊列註解自己寫的
「a release may hand something else over (a proxy's delete releasing its resources)」：
**proxy 是扣扳機的那一個，被放掉的是它的 uniform buffer 替別人持有的計數。**

另外兩條（協調問的）答案是「不會」與「有順序」：

- **`LiveProxies()` 的移除不會讓任何 UObject 失去參照**：它存的是
  `TWeakPtr`（`DreamUIMaterialProxy.cpp:43-46`），而 `GameThreadSource` 是裸 `UMaterialInterface*`，
  兩者都不持有 UObject。所以 delete 不會「讓下一次 GC 把材質或貼圖收走」。
- **同一次 tick 裡，`Later()` 的 lambda 全部先跑，`Hold` 的計數才掉**：
  `Tick_RenderThread` 先把到期的項目 `MoveTemp` 進區域 `Due`、解鎖、跑完每一個 `Entry.Release()`，
  而 `FTextureRHIRef`／`FBufferRHIRef`／`Pooled` 的計數要到 `Due` 在函式結束時解構才放掉。
  **所以 proxy 的 delete 一定跑在同一批 `Hold` 項目釋放之前。**

**這條鏈同時解釋四件已知事實**：`Func=240` 推遲當機（delete 被延後 ⇒ 計數下降被延後）、
`gc` 那條軸（delete 是 reachability 驅動的）、故障的是 `MainPS`（貼圖被材質路徑與內建路徑共用）、
以及斷言從不命中（UObject 那側沒事，掉的是 RHI 的計數）。
**還沒解釋的**：引擎的 EOP 圍欄本該蓋住「計數歸零 ⇒ 銷毀」這一步
（`FRHIResource::MarkForDelete` → `PendingDeletes` → `DeleteResources`），
所以若這條鏈成立，必須找出哪一步繞過了那個圍欄。**在找到之前，這仍是假設，不是結論。**

### 找繞過 EOP 圍欄那一步：**還沒找到**，所以 uniform buffer 那條鏈仍是假設（2026-11-19，純讀碼）

查到的（引擎出處）：

1. **計數歸零從不就地銷毀。** `FRHIResource::Release()`（`RHI/Public/RHIResources.h:80-91`）在歸零時呼叫
   `MarkForDelete()`，而它（`RHI/Private/RHIResources.cpp:46-59`）只是把資源丟進
   `PendingDeletes` 或 `PendingDeletesWithLifetimeExtension`。
2. **排空點在送交時，而且會一直排到空為止。**
   `FRHICommandListExecutor::FSubmitState::Submit_Close`（`RHI/Private/RHICommandList.cpp:1414-1437`）
   在 `ERHISubmitFlags::DeleteResources` 之下 `while(true)` 反覆
   `GatherResourcesToDelete` ＋ `DeleteResources` **直到隊列空**。
   **這個迴圈正好涵蓋「連鎖釋放」**：uniform buffer 被銷毀時才掉貼圖的計數，
   那張貼圖於是進 `PendingDeletes`，而同一趟迴圈會把它一起處理掉。
3. **延長生命週期那條岔路不是破口**：`bIncludeExtendedLifetimeResources` 只在
   `GRHIResourceLifetimeRefCount == 0` 時才排空擴充隊列（`:1590-1591`），
   而 `DisableLifetimeExtension()` 全引擎只有 ray tracing geometry 與 `DumpGPU` 在用，
   和 UI 貼圖無關。

**所以照這幾段讀，引擎這條路是有圍欄的，我沒有找到繞過它的那一步。**
D3D12 那一層把真正的記憶體釋放推到 EOP（`FD3D12DynamicRHI::EnqueueEndOfPipeTask`，
`D3D12RHI.cpp:320`，每個佇列一個 `FD3D12SyncPoint(GPUAndCPU)`），
所以「C++ 物件在送交時被 delete」不等於「GPU 記憶體在送交時被釋放」。

**結論寫成**：uniform buffer 那條鏈**解釋得了四件事實，但還缺一個破口**，
所以它是**假設**，不是結論；`Func=240` 的「推遲」也還可以只是時序。
**下一個該讀的兩處**（還沒讀，不要當成已查）：
`Submit_Close` 裡「先 delete 還是先送交」的實際順序，
以及 D3D12 的 EOP 任務是否涵蓋**已錄好但當下還沒送交**的命令清單——
若不涵蓋，那就是破口。

### 拆刻度的結果：**只有 `Later()` 那一支會動到當機位置**（2026-11-19 14:38–15:05）

同一個二進位、同一個配方（`gc=10` ＋ noclear），每趟的 in-effect log 都確認只抬了一個刻度。

| 刻度設成 240 | 第 1 趟 | 第 2 趟 | 和基線（4／7）比 |
|---|---:|---:|---|
| 都是 3（基線） | 7 | 4 | — |
| `Frames.Texture` | 6 | 7 | **沒有效果**，落在基線裡 |
| **`Frames.Func`** | **19** | **15**（重跑） | **明顯推遲，兩趟都在基線之外、不重疊** |
| `Frames.Pooled` | 待跑 | 待跑 | — |
| `Frames.Buffer` | 不必跑 | — | **全樹沒有任何 `Hold(FBufferRHIRef)` 呼叫點，這個刻度是空的** |

四趟 `Func`／`Texture` 的斷言（`DreamGUI.LogStaleTextures`）**全部 0 次命中**，簽章每趟相同。

**所以隊列裡會動到當機位置的是 `Later()` 這一支**，也就是
`DreamUIMaterialProxy.cpp:89/95` 的 `delete FDreamUIMaterialProxy`。
**但兩趟都沒活過 30 張，所以這是「推遲」不是「修掉」**——
240 帧（1.45 秒）只是把扣扳機的那一下推遠。

**和前面幾節接起來**：`Later()` 跑的是**裸 `delete`**，不經 RHI 的計數與延遲刪除，
而 proxy 的解構會經由 uniform buffer 的 `ResourceTable` 放掉**材質綁的那些貼圖的計數**
（上一節，`MainPS` 綁的是同一批）。兩件合起來說明**扳機在 `Later()`**，
而被放掉的東西是它連帶交出的。缺的仍然是「哪一步繞過 EOP 圍欄」。

**還有一個刻度共用的細節要記住**：`Frames.Texture` 這個刻度同時管
資料貼圖（`DataTexture.cpp:143`）與 canvas target（`Renderer.cpp:1253`），
而它兩趟都沒效果，**所以這兩個一起出局**，不必再各測一次。

### EOP 同步點**只涵蓋「enqueue 當下已經送交」的工作**——協調猜的那一步結構上成立（2026-11-19，純讀碼）

`FD3D12DynamicRHI::EnqueueEndOfPipeTask`（`D3D12RHI/Private/D3D12RHI.cpp:320-361`）的做法是：
**當下**為每個佇列 `new FD3D12Payload`、在裡面放一個新的
`FD3D12SyncPoint::Create(ED3D12SyncPointType::GPUAndCPU, ...)`，然後 **`SubmitPayloads(...)` 當場送交**，
最後把那些同步點的 graph event 當成 EOP 任務的 prereq。

**所以那個屏障的語意是「在 enqueue 那一刻之前已經送交的工作跑完」，不是「已經錄好的工作跑完」**：
payload 被插在佇列裡**已送交工作的後面**，而**之後才送交**的命令清單排在這個 payload **後面**，
同步點對它們一無所知。**協調猜的那一步，結構上確實是這樣。**

排空點也查到了：`RHIProcessDeleteQueue()` 由
`FRHICommandListExecutor::FSubmitState::Submit_Close`（`RHI/Private/RHICommandList.cpp:1442`）呼叫，
就在那個 `while(true)` 的 delete 迴圈（`:1414-1437`）之後，**也就是送交的時點**。

**所以破口的形狀是**：若有一次帶 `ERHISubmitFlags::DeleteResources` 的送交，
發生在「DreamGUI 錄完它那批 draw」與「那批 draw 真的被送交」**之間**，
那麼這一輪釋放的 EOP 同步點不涵蓋那批 draw——
記憶體可以在那批 draw 還沒開始跑之前就被放掉，取樣到的就是不屬於任何堆的位址。

**還缺的最後一塊（不要當成已查）**：DreamGUI 在 `PostRenderView_RenderThread` 錄的那批 draw，
在這一帧**實際是什麼時候被送交**的，以及那之間有沒有一次帶 `DeleteResources` 的送交。
RDG 的平行錄製會把 pass 錄進各自的 `FRHICommandList` 稍後才送交，所以這個窗口**可能存在**，
但「可能存在」不是「存在」。**在量到或讀到那個順序之前，破口仍然沒有被證實。**

**若破口證實**，修法就不是常數、也不只是給 `Later` 掛 fence，而是
**要等到「包含那批 draw 的送交」完成之後才允許這一輪釋放**。

### 下一格：**故意不 delete**（刻意洩漏），把「解構發生」和「解構晚 240 帧發生」分開（2026-11-19，gate 已寫好）

`DreamGUI.Experiment.NeverDeleteProxy`（預設 0，`DreamUIMaterialProxy.cpp:95`）：
開著時，失去最後一個參照的 proxy **完全不被 delete**，而是刻意洩漏
（`LeakInsteadOfDeleting()` 在那個 deleter 的最前面直接 `return`）。
`Frames.Func=240` 只能把當機從第 4／7 張推到第 19／15 張，
所以**一個數字說不出「解構是不是扳機」，而「永遠不跑解構」說得出**。

**跑之前登記的讀法**：
- **兩種重現都不當 ⇒ 扳機就是 proxy 的解構本身**（它放掉 uniform buffer 替材質持有的貼圖計數，
  而 `MainPS` 綁的是同一批），而且**不必先搞懂圍欄在哪一步失效**；
- **還是當 ⇒ 扳機不是解構**，`Func` 那兩趟的推遲是別的時序副作用，整條線重新看。

**洩漏要量出有界，不能只假設**：那一格記 `Leaked` 計數（log 前 10 次與每 50 次）
與行程 RAM；30 張卡是有限次數，所以應該是線性且小的。
**註解裡寫明這是診斷、不是修法候選**——
一個「讓當機消失」的洩漏是診斷，不是修復。

#### 協調提的第二條修法路（把計數先轉移給隊列）只能做一半

那條路是：delete 之前先把那些貼圖的計數交給 `Hold(FTextureRHIRef)`（那一支被引擎的延遲刪除蓋住），
這樣 proxy 什麼時候 delete 都無所謂，而且**不改任何時序**。
查下去**部分可行、但不完整**：

- **可行的一半**：外掛知道自己設過哪些貼圖（`RenderThreadParameters.Textures`），
  而 `InTexture->TextureReference.TextureReferenceRHI` 是
  `TRefCountPtr<FRHITextureReference>`，`FRHITextureReference` 繼承 `FRHITexture`，
  所以可以直接 `Hold()` 成 `FTextureRHIRef`；而 `FRHITextureReference::ReferencedTexture`
  本身是 `TRefCountPtr<FRHITexture>`（`RHITextureReference.h:53`），
  所以押住參照也押住被參照的那張。
- **做不到的一半**：uniform buffer 的 `ResourceTable` 裡**不只有外掛設過的參數**——
  材質自己取樣的任何東西都在裡面，而外掛沒有枚舉它的途徑。
  所以這條路只蓋得住「外掛設過的那些」，蓋不住其餘。

**結論**：第 2 條不是完整修法，但它可能剛好蓋住這個 crash（受害者正是外掛設的 canvas 貼圖）。
要不要用它，取決於「故意不 delete」那一格的結果，以及受害者到底是哪一張。

### 帶 `DeleteResources` 的送交只有三處，而其中兩處**不 flush RHI 執行緒**（2026-11-19，純讀碼）

全引擎（RHI ＋ RenderCore）帶 `ERHISubmitFlags::DeleteResources` 的只有三處：

| 處 | 形式 | 會不會先 flush RHI 執行緒 |
|---|---|---|
| `RHI/Private/RHICommandList.cpp:1731` | `ImmediateFlush(FlushRHIThreadFlushResources)` 時加上這個 flag | **會**（`:1724-1727` 同時加 `FlushRHIThread`） |
| `RenderCore/Private/RenderGraphBuilder.cpp:383` | `ImmediateFlush(DispatchToRHIThread, DeleteResources)`，在 RDG 的 `EndFlushResourcesRHI` 裡，受 `r.pso.EnableAsyncCacheConsolidation` 控制 | **不會** |
| `RHI/Private/RHIResources.cpp:98` | `GRHIResourceLifetimeRefCount` 歸零時，`ImmediateFlush(DispatchToRHIThread, DeleteResources)` | **不會** |

**這一條把破口的形狀講清楚了。** 佇列是先進先出：
帶同步點的 payload 在時刻 T 被送交，**T 之後才送交的工作排在它後面**，
所以 payload 的同步點發訊（EOP 任務跑、記憶體真的被放掉）時，那些工作**還沒執行**。
**屏障保護的只有「T 之前已經送交」的工作。**

於是：
- `FlushRHIThreadFlushResources` 那一處**先 flush RHI 執行緒**，
  所以已經 dispatch 的命令清單都會先被送交，窗口被關上；
- 另外兩處只 `DispatchToRHIThread`——**只 dispatch 立即命令列，不等 RHI 執行緒**，
  所以**當下還沒送交的命令清單會排在 payload 後面**，
  而它們是在釋放之前就錄好的。**結構上，這兩處可以在「先前錄好、尚未送交」的工作之前放掉記憶體。**

**還沒證實的那一塊（不要當成已查）**：DreamGUI 在 `PostRenderView_RenderThread` 錄的那批 draw，
是否確實在這兩處之一的**之前錄、之後送交**。
這一塊由**刻意洩漏那一格**給實證答案（若「永不 delete」讓兩種重現都不當，
就說明這個形狀在實際執行裡真的發生，不必把每條送交路徑讀完）。

**修法形狀要連著這句一起寫**（免得下一個人把它簡化掉）：
**給 `Later` 掛一個 GPU fence 不等於修好**——fence 等的是「GPU 跑到某個點」，
而這裡的問題是「**哪一批工作被那個同步點涵蓋**」。
正確的條件是**等到「包含那批 draw 的送交」完成之後**才允許這一輪釋放。

### 兩半的界線（先定下來，免得結果出來時才爭）

協調的分層我接受，而且它把「只能做一半」改寫成「**分層正確**」：

| 誰的責任 | 是什麼 | 修在哪 |
|---|---|---|
| **外掛** | `RenderThreadParameters.Textures` 是外掛**自己設進材質的**，所以在 proxy 失去最後一個參照之前先 `Hold()` 那幾張（押住 `FRHITextureReference` 也押住被參照的那張，`RHITextureReference.h:53`），是外掛自己的契約：**誰把資源交給別人用，誰負責它活到對方用完**。與 GC 節奏、帧數、配置器全無關。 | DreamGUI |
| **引擎** | `ResourceTable` 裡**外掛枚舉不到**的那些（材質自己取樣的）。它們會被放掉是因為「EOP 同步點只涵蓋 enqueue 當下已送交的工作」，而帶 `DeleteResources` 的三處送交裡有兩處不 flush RHI 執行緒。 | 引擎分支或上游 UE，**不是 DreamGUI** |

**所以文件與注解都要寫明：外掛押住自己那幾張不是這個 crash 的通解。**
下一次中獎的是材質自己取樣的貼圖時，不能讓人以為已經修過了。

**實作上有一個會咬人的細節先記下來**：那個 deleter 有兩條路
（`DreamUIMaterialProxy.cpp:84-97`）——在繪製執行緒上直接 `Later(delete)`，
否則 `ENQUEUE_RENDER_COMMAND` 再 `Later(delete)`。
而 `RenderThreadParameters` 只能在繪製執行緒上讀，
`TextureReference.TextureReferenceRHI` 也是（`DreamUIBaseShaders.cpp:26-31` 的註解寫明）。
**所以 `Hold()` 那幾張必須做在繪製執行緒那一側**，不能放在 deleter 的入口。

**驗收與立案**：若「故意不 delete」兩種重現都不當 ⇒ 先做外掛那一半，
最凶配方兩趟 ＋ 19 秒重現兩趟驗收；**驗收過也要同時把引擎那一半寫成獨立紀錄**
（含 `EnqueueEndOfPipeTask`／`Submit_Close`／三處 `DeleteResources` 的出處），標明還沒修。
若外掛那一半驗收**不過** ⇒ 直接證明受害者是材質自己取樣的東西，
這個 crash 只能靠引擎那一半修掉。

### 順序查到了，而且它**削弱**我自己上一節的破口形狀（2026-11-19，純讀碼）

**先做跑格子前的檢查**（今天立的規矩：確認旋鈕真的 gate 住、不是 read-only、知道預設值）：

- `r.pso.EnableAsyncCacheConsolidation`：`GEnablePSOAsyncCacheConsolidation = true`，
  `ECVF_RenderThreadSafe`（**不是** read-only，可以設），
  出處 `RHI/Private/PipelineStateCache.cpp:179-186`。
- 它 gate 的正是 RDG 那一處：`EndFlushResourcesRHI`（`RenderGraphBuilder.cpp:379-392`）
  在 `GetBool()` 為真時走 `ImmediateFlush(DispatchToRHIThread, DeleteResources)`，
  **為假時走 `ImmediateFlush(FlushRHIThreadFlushResources)`**——後者會 flush RHI 執行緒。
  所以 **`r.pso.EnableAsyncCacheConsolidation=0` 正好把那個窗口關上**，是個真的對照旋鈕。
- 這條路**每帧發生一次**：`SetFlushResourcesRHI()` 只有一個呼叫點，
  `Renderer/Private/SceneRenderBuilder.cpp:913`，註解寫明
  「The final graph builder is responsible for flushing resources」，就在 `GraphBuilder.Execute()` 之前。

**但順序一查下去，它削弱了我上一節寫的形狀**：在 `FRDGBuilder::Execute()` 裡，
`BeginFlushResourcesRHI()` 在 **:1810**、**`EndFlushResourcesRHI()` 在 :2036**，
而 pass 的派送與執行（`SetupDispatchPassExecute()` 等）在 **:2059 之後**。
**也就是那次帶 `DeleteResources` 的 flush 跑在「這張圖自己的 pass 被錄之前」**，
所以「先錄好、尚未送交」這個形狀**對同一張圖自己的 pass 不成立**——那時它們還沒被錄。

**所以要改的是形狀，不是結論**：能和這個順序相容的是
「**在 :2036 被放掉，然後 :2059 之後的 pass 綁了一個它更早就快取起來的指標**」。
而外掛確實會跨時點快取 RHI 指標（`FDreamUIBuiltInDrawParams` 的那幾支、`Frame.TextureRHI`）——
但那幾支存的是 `FTextureReferenceRHIRef`（計數參照，死了指向黑貼圖），
所以它們不會懸空，這也正是斷言從不命中的原因。

**誠實的狀態**：讀碼到這裡為止，**我沒有把破口讀成立**，而且剛剛那個順序讓上一節的形狀變窄了。
**所以刻意洩漏那一格現在是決定性的一步**：它不需要先讀懂任何送交順序，
直接回答「解構這件事發生，是不是扳機」。
`r.pso.EnableAsyncCacheConsolidation` 那一格仍然值得跑（旋鈕已確認接得上、每帧都走到），
但它的預測要跟著改：**若兩邊沒差，不代表那一處不是破口，只代表「關掉 RHI 執行緒那次同步」沒有改變結果。**

### 這條線收掉：payload 和一般工作走**同一條佇列**，而且 `Submit_Close` 排在送交之後（2026-11-19，純讀碼）

協調問的是：payload 的同步點建立時，「已經 dispatch 給 RHI 執行緒、但還沒送交給 GPU 佇列」的工作算哪一邊？
**答案是同一條、而且有順序，所以窗口是關的。**

1. **同一條佇列**：`FD3D12DynamicRHI::SubmitPayloads`（`D3D12RHI/Private/D3D12Submission.cpp:297-322`）
   把 payload 丟進 `PendingPayloadsForSubmission` 這**一個**佇列，再 `SubmissionThread->Kick()`
   （沒有送交執行緒時就在呼叫執行緒上加鎖處理）。**EOP 的 payload 和一般命令清單的 payload 走的是同一條路。**
2. **而且有順序**：`Submit_Close`（裡面才呼叫 `RHIProcessDeleteQueue()` → `EnqueueEndOfPipeTask`）
   是由 `Dispatch_CloseSubmission` 透過 `EnqueueSubmitTask` 排進**送交 pipe** 的
   （`RHI/Private/RHICommandList.cpp:1065-1091`），而 `:1544` 的註解寫明
   「Once all finalized tasks have completed, `FSubmitState::Submit_SubmitToGPU()` called which hands the
   platform GPU command lists down to the RHI」——**先把命令清單交下去，才跑 close。**
   送交 pipe 是序列的，所以**這次送交自己的命令清單一定排在 EOP payload 前面**。

**所以我自己提的那個結構破口收掉了**：
「已 dispatch 未送交」的工作不會排在 payload 後面；
而上一節已經說明「尚未錄製」的 pass 在 :2036 那時還不存在。
**兩邊一起關上，這條線到此結束**——不是「還沒證實」，是**讀出來不成立**。

**剩下的候選因此變清楚**（都還沒驗）：
- **扣扳機的是 proxy 的解構本身**（刻意洩漏那一格直接回答，不需要任何送交順序）；
- 或者 `Func=240` 的推遲是**別的**時序副作用，那就要回到 reuse 那一格與背景那幾格的數字。

今天在這條線上花掉的讀碼時間不是白費：它把「EOP 圍欄有沒有洞」這個最容易拿來解釋一切的說法
**關掉了**，所以後面不准再用它當理由。

### 修正前面那張「兩半的界線」：**沒有發現引擎層的洞**（2026-11-19）

前面那一節把責任分成「外掛那一半」與「引擎那一半（EOP 同步點只涵蓋已送交的工作）」，
並說引擎那一半要另開獨立紀錄。**後來讀出來那條線是關的，所以那個分法要改：**

- **不要寫成「引擎有個洞還沒修」。** 要留的紀錄是**「這條線為什麼被關掉」**，
  三件出處放在一起：
  1. `SubmitPayloads` 把 EOP payload 丟進和一般命令清單**同一個** `PendingPayloadsForSubmission`
     （`D3D12RHI/Private/D3D12Submission.cpp:297-322`）；
  2. `Submit_Close`（裡面才 `RHIProcessDeleteQueue()`）由序列的送交 pipe 排在
     `Submit_SubmitToGPU` **之後**（`RHI/Private/RHICommandList.cpp:1065-1091`、`:1544` 的註解）；
  3. `EndFlushResourcesRHI` 在 `FRDGBuilder::Execute()` 的 **:2036**，
     而 pass 派送在 **:2059 之後**，所以那時這張圖自己的 pass 還沒被錄。
  **結論是：沒有發現引擎層的洞。**
- **外掛那一半仍然該做，但理由只剩一條**：
  「**誰把資源交給別人用，誰負責它活到對方用完**」這條契約。
  **不再有「因為引擎漏了」這個支撐**——這句要留著，免得下一個人在一個不存在的引擎 bug 上蓋房子。

### 跟著重新加權：背景那五格現在是最重的一組（2026-11-19）

如果 RHI refcount ＋ EOP 圍欄這條路是關的，那麼**受害者的記憶體就不可能是經由那條路被放掉的**。
於是「位址不屬於任何堆」只剩**不走那條路的配置器**能解釋：

| 候選配置器 | 誰在用 | 哪一格會動它 |
|---|---|---|
| RDG transient allocator | 背景拷貝（`GraphBuilder.CreateTexture`） | `NoBackdrop=1`／`=2`、B 配置那兩格 |
| `GRenderTargetPool` | group 目標（`FindFreeElement`） | `Frames.Pooled=240`、`LogPoolReuse` 的數字 |

**所以正在跑的那五格從「順手一格」變成現在最重的一組**，
`LogPoolReuse` 的 handouts／distinct／reuse gap 也跟著重要起來。
**報齊時的解讀規則**：哪一格動了，就指向那個**不走圍欄**的配置器；
五格全不動，則「位址不屬於任何堆」還沒有任何配置器可以解釋，那本身就是下一個要追的事實。

### 那三個 0 的保存期只有 **100 帧＝0.6 秒**，所以它們沒有排除任何東西（2026-11-19）

13:37 那一格開著資源追蹤（`Logging all resource enabled: Yes`），回報：

```
PageFault: Found 0 active tracked resources in 16.00 MB range of page fault address
PageFault: Found 0 active heaps containing page fault address
PageFault: Found 0 released resources containing the page fault address during last 100 frames
```

**第三行的「last 100 frames」是一個 cvar 的預設值**：
`D3D12.TrackedReleasedAllocationFrameRetention`（`D3D12Adapter.cpp:49-55`，預設 **100**，
`ECVF_RenderThreadSafe` 所以可以設），字面意思是
「Amount of frames for which we keep freed allocation data around when resource tracking is enabled」。
而那行 log 的 100 是寫死在訊息字串裡的（`D3D12Util.cpp:716`），**實際用的是那個 cvar**。

**關鍵**：讀卡器是 **165 FPS**，所以 100 帧 = **0.6 秒**。
而今天量到的時間尺度是**秒**級（`DelayFrames=240` 就是 1.45 秒，而它只是把當機推遲）。
**所以那個 0 的意思是「最近 0.6 秒內沒有東西在那個位址被釋放」，
不是「從來沒有東西在那個位址被釋放」。** 我先前把這三個 0 當成「位址從不屬於任何追蹤配置」是過度解讀。

**於是協調想要的東西有一個便宜得多的做法，不必改引擎**：
把 `D3D12.TrackAllAllocations=1` 和 **`D3D12.TrackedReleasedAllocationFrameRetention` 調大**
（例如 20000 帧 ≈ 2 分鐘，涵蓋整格）一起設上去，再跑最凶配方與 19 秒重現各兩趟。
當機時引擎自己的 page-fault 處理器就會**把那個已釋放資源的名字印出來**——
這正是「受害者那一側直接拿名字」，而且是 cvar，不是引擎改動。

**跑之前登記的讀法**：
- **印出名字 ⇒ 受害者有名字了**，連同它的大小與釋放帧號，直接指向擁有它的子系統；
- **保存期調到涵蓋整格之後仍然 0 ⇒ 那個位址真的不屬於任何追蹤過的配置**，
  那麼候選就換成「垃圾描述子／垃圾位址」這一類（不是「被放掉的記憶體」），
  而那會解釋為什麼所有延後釋放的旋鈕都只能改機率、不能修掉。
- 兩種結果都比再猜一個子系統值錢，而且這一格**不必改引擎樹**。

### `NoBackdrop=1` 兩趟分裂：第 7 張 ／ **跑完 30 張**（2026-11-19 15:11–15:24）

| 趟 | 結果 | 斷言命中 |
|---|---|---:|
| 1 | 當在第 7 張 | 0 |
| 2 | **30 張跑完，`faults=0`** | 0 |

兩趟都確認旋鈕接上（`DreamGUI.Experiment.NoBackdrop = "1"`）。
**這是今天第二次出現「一趟活、一趟死」的分裂**（前一次是 `DelayFrames=240` 的 30／27），
所以**單憑這一格不能說背景出局，也不能說背景就是元凶**。

**而且 `=1` 這一格本來就有兩種解釋**（這也是當初做 `=2` 的理由）：
拷貝不存在，**以及** draw 的組合／permutation／取樣次數都變了。
**所以判定要等 `=2`（拷貝照做、只綁黑，draw 與預設完全相同）那兩趟**：
- `=2` 兩趟也出現「活過 30 張」⇒ 差別在**那塊記憶體**；
- `=2` 兩趟都在基線裡 ⇒ 差別在**讀背景那條路上的 draw**，不是記憶體。

順帶一筆：`LogPoolReuse` 在這兩趟同樣 0 條報告，
再次確認讀卡器從來沒開過 group（`Frames.Pooled` 是空刻度）。

#### A1 第 1 趟落在別組佔機區間內——查過了，**沒有證據顯示污染**

f-sceneload 自報 2026-11-19 **15:09:29–15:14:50** 佔機（最重的是 15:11:23–≈15:12:45 的 523 個測試，8 執行緒滿載；
15:13:00–15:13:58 只有單檔編譯；全程沒開引擎、沒用 GPU）。A1 第 1 趟的卡 1 在 **15:12:42**、故障在 **15:13:19**，
**整段都在那個區間裡**。

逐卡時間（`.tex` mtime 差，秒）：

| 趟 | 逐卡 | 中位數 |
|---|---|---:|
| A1-1（在別組佔機區間內） | 4.90 4.61 5.78 5.04 6.78 | **5.78** |
| A1-2（之後，機器只有我） | 4.57 4.64 5.70 4.44 6.20 5.33 4.97 4.81 4.68 5.81 4.15 5.93 … | **5.72** |

**吞吐沒有抬高**（中位數 5.78 vs 5.72，逐卡區間也重疊），所以**沒有證據顯示那趟被污染**。
但照自己定的話講清楚界線：這個判法只看得見「機器變慢」，
看不見「別人的負載改了時序而改了當掉的機率」，所以這是「沒有證據」，不是「保證沒有」。

（最後一格 366 秒的間隔是當掉後 crash handler 卡在那裡等我發現，不是一張卡的耗時。）

### 讀出來的兩件事：背景那張拷貝是 **RDG transient** 的，而且模式 2 **沒有**退化成模式 1

**一、那塊記憶體是哪來的**（`DreamUICompositor.cpp:396-399`）：

```
const FRDGTextureDesc Desc = FRDGTextureDesc::Create2D(Local.Size(), Source.Format, ...);
FRDGTextureRef Copy = GraphBuilder.CreateTexture(Desc, InName);
AddCopyTexturePass(GraphBuilder, InFrame.Texture, Copy, ...);
```

`GraphBuilder.CreateTexture` ⇒ **RDG 的 transient allocator**。這是目前所有候選裡**唯一**一塊記憶體來自 transient allocator 的，
而 19 秒那個重現用的旋鈕正好就是 `r.RDG.TransientAllocator=0`；
`Found 0 active heaps containing page fault address` 也和「那個 transient heap 已經被釋放掉了」對得上
（還活著的 transient heap 是會被找到的）。

**但不能就這樣接起來，而且方向是反的**：關掉 transient allocator（改走 pooled）之後當得**更快**（19 秒、一張卡都還沒開），
不是不當了。所以「受害者是一張 transient 貼圖」解釋不了那個重現。**兩個重現先繼續分開放**，等有一個機制同時說明兩邊才合併。

**二、差點把自己的判讀寫錯**（在看到 A2 結果之前先改掉，不是之後）：

我原本登記的讀法是「模式 1 不當 ＋ 模式 2 照樣當 ⇒ 受害者不是那塊記憶體」。
這會錯，因為模式 2 有可能根本沒配置那塊記憶體：`GRDGCullPasses` 預設 **1**（`RenderGraphPrivate.cpp:231`），
而 RDG 會把「輸出沒人讀」的 pass 整個剔掉（`RenderGraphBuilder.cpp:2373-2376`）。
模式 2 只改了 PS 綁什麼（`DreamUIRenderer.cpp:1014-1015` 綁 `GBlackTexture`），
如果拷貝沒有別的消費者，那個 copy pass 會被剔掉、貼圖根本不會配置，模式 2 就等於模式 1，鑑別力歸零。

**查過了，沒有退化**：那張貼圖本來就以 pass 參數的身分宣告了 SRV 存取——
`RDG_TEXTURE_ACCESS(BackdropTexture, ERHIAccess::SRVGraphics)`（`:850`）、`PassParameters->BackdropTexture = InBackdrop`（`:1588`），
而且 `MarkResourceAsUsed()`（`:1618`）與 `GetRHI()`（`:1619`）在模式 2 照樣跑。
所以模式 2 裡那塊記憶體**照樣配置、照樣被拷進去、照樣轉成 SRVGraphics、RHI 指標照樣被取出**，只有**著色器取樣**讀到黑。

**據此改寫的判讀（仍在看到 A2 之前登記）**：

| A2（模式 2，只綁黑） | 讀法 |
|---|---|
| 兩趟都活過 30 張 | 當掉需要 `MainPS` **取樣**那張貼圖 ⇒ 受害者就是它（經由 PS 綁的那個 descriptor） |
| 兩趟都在基線裡 | 當掉**不需要**取樣：配置＋拷貝＋轉狀態就夠 ⇒ 指向 transient allocator 的 heap 生死，不是綁定 |
| 又分裂 | 這條線這樣問不出來，要換成不配置／配置但不進 pass 參數的對照 |

### 找到一條和「`Found 0 active heaps`」字面對得上的機制：**transient heap 被 `delete` 掉**

`RHICoreTransientResourceAllocator.cpp`：

- `RHI.TransientAllocator.GarbageCollectLatency` 預設 **16** 個 update cycle（`:41-46`，`ECVF_ReadOnly`，只能啟動時由 ini 設）；
- 空掉的 heap 先進 `FreeList` 並記下 `LastUsedGarbageCollectCycle`（`Forfeit`，`:583-595`）；
- `GarbageCollect()` 裡，閒置超過 latency 的 heap 直接 **`delete Heap`**（`:598-626`，第 612 行）。

**`delete` 掉的是那塊記憶體本身（連 D3D12 heap 物件一起）**，所以之後任何還指著它的 descriptor，
位址就會**不屬於任何還活著的 heap**——這正是故障報告那句 `Found 0 active heaps containing page fault address` 的字面意思。
而背景那張拷貝（上一節）就住在這種 heap 裡。

這是目前**唯一**一條能把故障報告的那句話照字面解釋完的機制，其他候選都只能解釋「記憶體被放掉」而解釋不了「不屬於任何 heap」。

**下一格（已寫好，等窗口）**：`RHI.TransientAllocator.GarbageCollectLatency` 設成大到整趟都不回收。
- 兩個重現都活 ⇒ 受害者是**被 `delete` 掉的 transient heap 裡的位址**；
- 照樣當 ⇒ 不是 heap 回收。
- **死於 VRAM 不足不算結果**：heap 最小 128 MB 且只進不出，這台只有 8 GB VRAM，所以這格要連 VRAM 一起報，
  OOM 的趟重跑或換較小的 latency，不能當成「當掉」。

**順帶一個對驗收門檻的影響，先講不要最後才講**：這條機制解釋不了 19 秒那個重現
（那是 `r.RDG.TransientAllocator=0`，根本沒有 transient heap 可以被 `delete`）。
所以**兩個重現有可能是兩個洞**。那不是放寬門檻的理由：門檻照舊兩道都要過，
只是如果某個候選過了一道、過不了另一道，我會照這個事實回報「這裡有兩個洞，兩個都要補」，而不是把過不了的那道說成雜訊。

### 背景這條線出局：模式 1、模式 2 四趟裡三趟都在基線範圍

| 格 | 旋鈕（四趟都確認接上） | 趟 1 | 趟 2 |
|---|---|---|---|
| 基線（對照） | gc=10 ＋ noclear | 第 4 張 | 第 7 張 |
| A1 | `NoBackdrop=1`：拷貝根本不做 | 第 7 張 | 跑完 30 張 |
| A2 | `NoBackdrop=2`：照配置、照拷貝、照轉 SRVGraphics，只有著色器綁黑 | 第 **9** 張 | 第 **2** 張 |

照先前登記的讀法（「兩個都當 ⇒ 背景整條出局」）：**出局**。
把拷貝完全不做（模式 1）都還會當在第 7 張，所以**那塊記憶體不是受害者**，
`MainPS` 取不取樣它也不是條件（模式 2 兩趟都當，其中一趟只撐 2 張）。
斷言命中數四趟都是 0；`LogPoolReuse` 四趟都 0 條，再次確認讀卡器從來沒開過 group。

A1 第 2 趟那個「跑完 30 張」**沒有解釋**，就記成沒有解釋。

### 這件事反過來咬了驗收門檻：**基線自己可能也會偶然活過 30 張**

今天已經出現兩次「一趟活一趟死」：`DelayFrames=240`（30／27）與 `NoBackdrop=1`（7／30）。
兩次都發生在「改了旋鈕」的格子上，純基線目前是 2 趟 2 死（第 4、第 7 張），
**但 2 趟撐不起一個機率**。如果最兇配方自己就有相當的機率活過 30 張，
那麼「30 張 ×2 全過」就分不出「補對了」和「運氣好兩次」——**門檻會變成量不出東西的門檻**。

所以在拿任何候選去撞門檻之前，要先把**基線的活存率**量出來：最兇配方（gc=10 ＋ noclear，不動任何旋鈕）連跑 6 趟，
只記每趟死在第幾張或活過 30。這不是額外的好奇心，是門檻能不能用的前提：
- 6 趟全死 ⇒ 「30 張 ×2」有意義，門檻照用；
- 6 趟裡有 1 趟以上活過 30 ⇒ 門檻要加趟數（或改用「死在第幾張」的分布比較），而且**今天所有「活過 30 張」的單趟證據都要照這個機率重新加權**。

### 基線活存率不必等那 6 趟就有第一個數字：**AP 這一格本來就是一趟偽裝的基線**，而它活過 30 張

`AP` 格設的是 `DreamGUI.DeferredRelease.Frames.Pooled=240`，而這個刻度**已經量成空的**：
`LogPoolReuse` 在約兩萬幀裡 0 條報告 ⇒ 讀卡器從來沒開過 group ⇒ `Hold(TRefCountPtr<IPooledRenderTarget>)` 一次都沒被呼叫 ⇒
那個刻度沒有東西可以延後。所以**這一格的旋鈕什麼都沒改，它實際上就是一趟基線**。

而 **AP 趟 1 跑完 30 張、`faults=0`**。

把「旋鈕證明無效」的趟算進基線，目前基線等價的趟是：

| 趟 | 結果 |
|---|---|
| 基線 趟 1 | 第 4 張 |
| 基線 趟 2 | 第 7 張 |
| AP 趟 1（旋鈕空刻度＝基線） | **跑完 30 張** |
| AP 趟 2 | 在跑 |

**所以最兇配方自己就會活過 30 張，機率不是零。** 這直接證成了上一節的擔憂，而且不必等 `baserate.sh`：
- 「30 張 ×2 全過」**不能**當驗收門檻；
- 今天那兩個「活過 30 張」（`DelayFrames=240`、`NoBackdrop=1` 趟 2）**不再需要特別的解釋**，它們和 AP 趟 1 是同一件事；
- `baserate.sh` 那 6 趟仍要跑，但它的任務從「有沒有」變成「多高」——要的是機率，不是存在性。

**先把這個數字的界線講清楚，不要當成純基線**：AP 那趟跑的是背景那次的建置（實驗閘門都編進去了但預設關），
而且多開了 `LogStaleTextures=1` 與 `LogPoolReuse=1` 兩個記錄旋鈕。
`LogPoolReuse` 因為沒有 group 所以零成本，但 `LogStaleTextures` 每個 draw 會檢查九個指標，是有成本的。
所以它是「基線＋一點記錄成本」，延後釋放的行為與基線完全相同，但不是同一個執行檔的純基線。
`baserate.sh` 跑的是不帶任何旋鈕的純基線，兩邊的數字要分開記。

## 驗收標準（2026-11-19 定版，後面每一格都引這一節，不要各自寫一套）

舊門檻「最兇配方 30 張 ×2 全過」**已經死了**：基線自己就會活過 30 張（上一節，AP 趟 1）。改成這五條：

1. **基線率要用純基線**：`DreamGUI.LogStaleTextures`／`LogPoolReuse` 全關。
2. **指標從「過／不過」改成「撐了幾張」**：每趟記死在第幾張，活過 30 記 `30+`。有序的量；在基線本身就會過的情況下「過／不過」沒有資訊。
3. **候選修法用分布比較，門檻明寫**：修法那組 N 趟的**最小值要大於基線那組的最大值**（純無母數），N ≥ 6；做不到就寫「未測出」。只要有一趟落在基線範圍內就不算修好。
4. **優先找一個基線 100% 死的配方**，門檻才便宜。候選是早上備好的兇配方（1 對 1 進出 ×3 → 開 30 張，每趟多一組 clone 與男角）：在純基線 6 趟之後用同一套跑它的基線 6 趟，6/6 全死就當主配方。
5. **今天所有已寫下的「活過 30 張」結論全部重新加權**，紀錄裡標明「在門檻失效的前提下取得」。

### 兩件要補在標準上的事

**一、第 1 條不需要重新建置，只要不設那兩個旋鈕——有根據，不是想省事。**
`CheckNotStale`（`DreamUIBaseShaders.cpp:33-38`）第一件事就是 `InTexture == nullptr || CVarLogStaleTextures.GetValueOnRenderThread() == 0` 就 return。
旋鈕為 0 時每個 draw 的成本是九次空指標檢查加九次內聯 int 讀取，**不碰 `UTexture` 物件、不上鎖、不配置**；
`IsValid()`／`IsUnreachable()` 要到旋鈕為 1 才會跑。
所以「閘門編進去但旋鈕全 0」的執行檔，對量測而言就是純基線，`baserate.sh` 本來就不設那兩個旋鈕（`MORE=""`）。
AP 那趟之所以要標成「基線＋記錄成本」，是因為它**把旋鈕設成 1**，不是因為程式編進去了。

**二、第 3 條依賴第 4 條成功，否則它是一條永遠過不了的門檻。**
「修法的最小值 > 基線的最大值」在基線最大值是 `30+` 時無解：沒有任何一組的最小值能大於 `30+`。
所以**第 4 條不是優化，是第 3 條能不能用的前提**：必須先有一個基線 6/6 全死、而且最大值明顯小於 30 的配方。
如果兇配方也做不到 6/6 全死，第 3 條要改成比較兩組「撐了幾張」的分布（例如兩組的中位數與全距一起報），不能繼續用完全分離。

順帶把第 3 條的強度算出來，這樣它才站得住：兩組各 6 趟、虛無假設下完全分離的機率是 `2 / C(12,6) = 2/924 ≈ 0.2%`。
所以它不是隨便定的嚴格，是一個偽陽性率算得出來的檢定。

### 第 5 條重新加權的結果：**今天幾乎每一個靠「死在第幾張」得到的結論都站不住，包括我自己的頭條**

AP 趟 2 回來了：**死在第 15 張**。所以 AP（＝基線＋記錄成本）是 `{30+, 15}`，
把基線等價的趟全部排在一起：

| 趟 | 撐了幾張 |
|---|---|
| 基線 趟 1 | 4 |
| 基線 趟 2 | 7 |
| AP 趟 1（空刻度） | **30+** |
| AP 趟 2（空刻度） | **15** |

**基線的全距是 4 到 30+。** 兩件事馬上成立：

**一、第 3 條現在確定不能用**（不是推測，是量到的）：基線最大值是 `30+`，沒有任何一組的最小值能超過它。
所以第 4 條那個「找一個基線 6/6 全死的配方」是**接下來最優先的一格**，比 `gclrun`／`retainrun` 都優先——
沒有它，後面每一格跑完都無法判。

**二、我自己那個頭條結論要撤回**：先前寫「只有 `Later()` 這個呼叫點會移動當掉時機」，
依據是 `Frames.Func=240` 的 `{19, 15}` 對基線的 `{4, 7}`，而 `Frames.Texture=240` 的 `{6, 7}` 沒動。
**19、15、6、7 全部落在基線的 4..30+ 裡**，所以那兩格都和基線分不開，
「`Later()` 會移動、`Texture` 不會」**沒有證據支持**。`DelayFrames=240` 的 `{30+, 27}` 同樣落在裡面。

照第 5 條，這些結論在紀錄裡標成**「在門檻失效的前提下取得」**，並且**不再當作已知**：
要重新主張任何一條，得按第 2、3 條用 N ≥ 6 重跑。

**今天靠量測站得住的只剩兩條**：
1. `r.RDG.TransientAllocator=0` 之下有一個 **19 秒、一張卡都沒開**就當掉的重現（2/2）。
   它和卡數分布不是同一個量——零張卡、十幾秒，落在基線那個「開幾十張卡、幾分鐘」的分布之外，所以不受這次加權影響。
2. 基線的「撐了幾張」全距是 4..30+。

**靠讀程式站得住的那些不受影響**（它們不是從卡數推出來的）：`Buffer`／`Pooled` 兩個刻度是空的、
`Pooled` 的空刻度另有兩萬幀 0 條報告的實測、EOP 圍欄那條線逐步讀成不成立、
背景那格（A2 兩趟 9 與 2 都在基線低端，而拷貝完全不做也還當）——
不過**背景的結論也要降級**：它是「兩個模式都沒有把當掉移出基線範圍」，不是「背景已被排除」，差別在於前者只要 N ≥ 6 才能變成後者。

### 兩個修正：19 秒重現**不能**當 transient heap 那條機制的尺；而「30+」不是全距寬，是**被截斷的觀測**

**一、`r.RDG.TransientAllocator=0` 和 `RHI.TransientAllocator.GarbageCollectLatency` 不是同一塊東西，方向還是反的。**

`RenderGraphBuilder.cpp:591`：

```
TransientResourceAllocator(GRDGTransientAllocator != 0 && !::IsImmediateMode() ? GRDGTransientResourceAllocator.Get() : nullptr)
```

旋鈕為 0 ⇒ builder 根本沒有 transient allocator ⇒ 不會有 transient 資源 ⇒ 不會有 transient heap ⇒
`GarbageCollectLatency` **沒有東西可以回收**。所以：

- **拿 19 秒那把尺去量 `gclrun`，等於量一個在那個組態裡已證明斷線的旋鈕**——和 `Frames.Pooled` 的空刻度一模一樣；
- 而且證據方向是**反**的：沒有 transient heap 可以被 `delete` 的時候當得**更快**（19 秒、零張卡），
  所以「heap 被 delete」解釋不了 19 秒那個重現，它只可能解釋**預設組態**那個。

兩個重現仍然要分開：19 秒那個的受害者更可能在「關掉 transient 之後改走的那條 pooled 路」上。
`gclrun` 必須在**預設組態**下量，而預設組態的尺就是卡數——所以下一段才是真正要先解決的事。

**二、卡數那條線不是「全距太寬所以不可判」，是「量尺有天花板」。**

每趟只走 30 張卡，所以活下來的趟記成 `30+`：那是**被截斷的觀測（censored）**，不是一個數字。
基線那四趟 4／7／30+／15 之中有一趟被截斷，而第 3 條（一組的最小值大於另一組的最大值）
**在有截斷觀測時根本算不出來**——這才是它不能用的真正原因，比我上一節寫的「最大值是 30+」更根本。

**所以不需要去搜「基線 6/6 全死」的兇配方。** 把天花板拿掉就好：同一套配方、同一組卡，
**循環重複開到當掉為止**，記「開了幾張」與「幾秒」，只在很長的時間上限（預設 480 秒）才截斷。
這樣幾乎每一趟都會給出真數字，第 2、3 條就能照原樣用，而且不必換配方、不必重新建立和既有資料的可比性
（配方與逐卡取樣都沒變，只有迴圈外多包一層）。

驅動腳本已寫好：`loopx.sh`（由 `knob1x.sh` 複製後改迴圈，`CAP_S` 可調）。

### 自己抓到的錯：上一節那個基線組**混了兩個執行檔**

查各趟表頭的 `# build:` 行：

| 趟 | 執行檔 | 撐了幾張 |
|---|---|---|
| 基線 趟 1、趟 2 | **沒有記錄**（當時腳本還沒印這行） | 4、7 |
| `split_Texture`／`split_Func` 四趟 | 11-19 **13:54** | 6、7、19、15 |
| `bg_A1`／`A2`／`AP` 六趟 | 11-19 **15:05** | 7、30+、9、2、30+、15 |

所以我上一節把 4、7、30+、15 放成一個「基線等價組」是**錯的**：4 與 7 不只來自別的執行檔，
而是**連執行檔都沒記**，它們不能當任何東西的基線。

**但結論不變，而且現在的依據更乾淨**：光看 11-19 15:05 這一個執行檔上的六趟就是
**7、30+、9、2、30+、15 ⇒ 全距 2..30+**，其中兩趟被截斷。
「卡數分不出東西」這件事不需要混執行檔也成立。
（`split_*` 那四趟的 6、7、19、15 在 13:54 的執行檔上，和 15:05 的不能混；撤回那條頭條的理由因此也要改寫成：
`Func=240` 的 19、15 和**同一個執行檔上**的基線趟沒有對照——13:54 那個執行檔上**沒有跑過基線**。
結果一樣是「沒有證據支持」，但理由是缺對照，不是落在全距裡。）

### 第 6 條（補進驗收標準）：**尺綁在執行檔上**

- 每一趟都要印 `# build:` 的執行檔時間與 `HEAD`；沒有這行的趟不能當任何組的成員。
- **只有同一個執行檔上的趟可以互相比較。** 基線組與候選組必須在同一個執行檔上量；中間若重新建置，
  基線組作廢，要在新執行檔上重新量。
- 這條不是形式要求：這個工作樹是三組共用的，`OKReaderScreen.cpp`（讀卡器畫面本身）此刻就在別人的未提交改動裡，
  任何一次建置都會把它編進去，讀卡器的行為因此可能在兩組趟之間改變。

### B1 趟 1：**19 秒那個重現不需要背景**（而且差點又讀了一個沒驗過的旋鈕）

B1 ＝ `NoBackdrop=1`（拷貝根本不做）＋ `r.RDG.TransientAllocator=0`。趟 1 結果：
**零張卡、啟動期間就當掉**（`STOP at card 1 ... no card reader mailbox yet`、`faults=1`），和該組態的基線（2/2 當）一樣。
所以**把背景拷貝整條拿掉，救不了 19 秒那個重現**。等趟 2。

**表格格式的洞，先記下來**：這一格的表頭只回讀**主旋鈕**（`DreamGUI.Experiment.NoBackdrop = "1"`），
`r.RDG.TransientAllocator=0` 是走附帶的 ini 清單，**表裡沒有它的回讀**。
我是去翻那趟自己的 log 才確認的（裡面有 `r.RDG.TransientAllocator:0]]` 的生效值）。
這等於是「沒驗過的旋鈕」那個老問題換了個位置：主旋鈕驗了，次旋鈕沒驗。

**要改的是驅動腳本**：`knob1x.sh` 應該把附帶 ini 清單裡的每一個旋鈕都回讀進表頭，不是只讀主旋鈕。
這一輪的鏈還在跑，不動正在跑的驅動（改壞了就是一整格重跑），所以**等鏈結束後再改**，
在那之前每一格的次旋鈕都照這次的做法去 log 裡核對一次，並把核對結果寫進紀錄。

### 第 6 條補完，以及「19 秒」這個名字是錯的

**第 6 條（定版）**：

- 每趟表頭要有 `# build:` 的執行檔時間與 `HEAD`，**再加一個工作樹指紋**：
  `git status --porcelain` 與 `git diff` 的內容雜湊（兩個都記），至少要看得出當時哪些檔被改過。
  **`HEAD` 不足以認一個執行檔**——這棵樹三組共用，同一個 `HEAD` 可以編出行為不同的兩個執行檔。
- 只有同一個執行檔、同一個指紋上的趟可以互比。
- **只要有人在 E 建置，手上的基線組就作廢**：重量基線再繼續，不拿舊基線去比新執行檔上的候選組。（常規，不是個案。）
- 指紋在**格子開始時取一次**就夠，不必每趟取：取的時機要在「樹不會變」的前提下，
  而這一輪 e-fork-2 已經同意在鏈結束前不建置。若沒有這個前提，就得每趟取。

### 讀取器自己的 bug，在用它之前自測抓到

量「幾秒當掉」的小工具第一版要求「同一行既有時戳又有 `MMU Fault Error`」，
結果對一個**表裡明明寫著 `faults=1`** 的 log 印出 `NO_FAULT`。原因：那個標記不在有時戳的行上，
它在一段 JSON 裡（`"Fault Name": "MMU Fault Error",`，有縮排、沒有自己的時戳）；另外 log 是帶 BOM 的 UTF-8。
改成「記住最後看到的時戳，標記出現時就算在那個時戳上」，並用 `utf-8-sig` 讀。
**這正是這整個調查一再遇到的那種靜默的零**：工具什麼都沒找到，看起來卻像「量到了沒有故障」。
所以它在拿去跑六趟之前先對四種情況自測（已知有故障的 log、原本那兩趟、一趟存活的 log、不存在的檔），四種都對。

### 「19 秒」要改名：實際量到的是 **24.2 秒與 34.0 秒**

用修好的工具回頭量那兩趟原始重現，從 log 第一個有時戳的行到故障：

| 趟 | 幾秒 |
|---|---:|
| `trans_pass1` | **34.0** |
| `trans_pass2` | **24.2** |
| `bg_B1_1`（＋`NoBackdrop=1`） | **25.4** |

先前寫的「19 秒」是我當時看掛鐘估的，不是量出來的，**以後一律稱「啟動期零張卡的重現」並附量到的秒數**。
這也順便說明那個組態裡的時間**本身就有 24–34 秒的散佈**，所以尺 1 要比的是秒數分布，不是「19 秒」這個單一數字；
它仍然遠在「開幾十張卡、好幾分鐘」之外，所以當它自己那個洞的尺還是成立的。

## 第 7 條（加進標準）：量具要先自測，否則它的輸出不能進紀錄

> 任何用來判定結果的量具（偵測腳本、計數器、log 剖析器），在用它量任何一格之前，
> 必須對**至少一個已知為正的樣本**和**一個已知為負的樣本**自測通過，並把自測結果記下來。
> 沒有自測紀錄的量具，它的輸出不能進紀錄。

今天已經踩到四次同一個形狀——**一個安靜的零**：`Frames.Pooled` 空刻度、AP 的空刻度、`gclrun` 接到錯的組態、
以及秒數剖析器那個 `NO_FAULT`。第 7 條專門攔這個形狀。
標準做法引那個剖析器的四種自測（已知有故障的 log、原本那兩趟、一趟存活的 log、不存在的檔）。

### 照第 7 條回頭查自己的量具，查出一個**沒有通過的**

| 量具 | 已知為正 | 已知為負 | 結論 |
|---|---|---|---|
| `faults=`（`grep -ca 'MMU Fault Error'`） | `bg_B1_1`（1） | `bg_A1_2`（0，兩萬行） | 通過 |
| `fault_secs`（秒數剖析器） | 三個 log | 一趟存活的 log、不存在的檔 | 通過 |
| `act`（KKPreviewActor 計數） | 十次開卡 1 → 25 | — | 正樣本有，負樣本沒有，但它不是判定用的 |
| **`LogPoolReuse`（`DreamUIGroupPoolReuse::Note`）** | **沒有** | 零條報告 | **不通過** |

**`LogPoolReuse` 只有負樣本。** 我用「約兩萬幀 0 條報告」推出「讀卡器從來沒開過 group ⇒ `Frames.Pooled` 是空刻度」，
但我**從來沒確認過 `Note()` 真的印得出東西**。如果記錄本身壞了（日誌分類不對、旋鈕在錯的執行緒上讀、`Note` 根本沒被編進去），
零條報告就什麼都不代表——這就是第 7 條要攔的那個形狀，而我自己正好犯在上面。

**影響範圍，照實說**：
- 「`Frames.Pooled` 是空刻度」目前**只有負樣本支持**，要降級成「尚未證實」。
- 「AP 那一格其實是偽裝的基線」是從它推出來的，所以**同樣降級**。
- **但今天最大的那個結論不受影響**：「卡數分不出東西」不需要 AP。
  光 `bg_A1` 自己兩趟（同一個執行檔、同一個旋鈕設定）就是 **7 與 30+**，全距已經跨到天花板；
  加上 `A2` 的 9 與 2，15:05 那個執行檔上的六趟就是 2..30+。這些都和 `LogPoolReuse` 無關。

**怎麼補這個正樣本**（排在尺 2 之前，很便宜）：這個主張其實有兩半——
(a) 記錄機制能印、(b) 那個呼叫點在讀卡器裡從不執行。
負樣本只能同時涵蓋兩半，所以要**把 (a) 單獨測**：加一個獨立旋鈕，在每幀必經的地方強制呼叫一次 `Note()`，
確認它真的印得出來。(a) 通過之後，零條報告才能歸因到 (b)。
這需要改一次 DreamGUI 並重建，所以排在 e-fork-2 建置之後一起做，不另外佔一次建置。

### 第 7 條附則（陰性結果同時蓋住兩個假設），以及照它申報剩下每一格的陽性樣本

**附則**：一個未自測量具的**陰性結果同時蓋住兩個假設**——「記錄機制壞了」與「被記錄的事從沒發生」。
兩者都會產生零條報告，所以陰性結果在量具自測通過之前不能歸因到任何一個。
要分開，必須造一個陽性樣本：讓記錄機制在**已知會發生**的情況下印出東西。

**順手查到第二個同形狀的量具：`LogStaleTextures` 也只有陰性證據。**
`DreamUIBaseShaders.cpp` 裡只有 `StaleHits`（命中計數），**沒有「檢查了幾次」的計數**。
所以「斷言命中四趟都是 0」同樣蓋住兩個假設：可能真的沒有過期貼圖，也可能 `CheckNotStale` 一次都沒被呼叫到
（或旋鈕在那條路上讀不到）。這條結論現在也只能算**尚未證實**。

**補法比 `Note()` 那個更簡單，而且不需要造假資料**：加一個 `StaleChecked` 計數，
把輸出從「hits=0」改成「**checked=N, hits=0**」。`N > 0` 本身就是陽性樣本——它證明量具跑過了，
於是 0 次命中才能歸因到「沒有過期貼圖」。這比強制塞一個已知壞掉的指標進去安全得多。

**剩下每一格的陽性樣本申報（申報不出來的格子不跑）**：

| 格 | 陽性樣本：怎麼知道旋鈕這次真的生效 |
|---|---|
| `NeverDeleteProxy` | `Leaked` 計數必須 > 0 並隨開卡上升；外加行程記憶體隨之增加。**只看「沒當掉」不算**——那正好是旋鈕沒生效時的樣子。 |
| retention／名字格 | log 裡要出現 `Logging all resource enabled: Yes`（那是 `bTrackAllAllocation` 的回讀），且回報的保存期視窗要大於預設的 100 幀。 |
| `gclrun` | 需要一個「回收行為真的變了」的跡象：常駐的 transient heap 數或 VRAM 佔用要比預設組態高且不回落。**沒有這個跡象就不要讀它的結果**——否則一個斷線的旋鈕會長得像「補好了」。 |
| 尺 1（啟動期零張卡） | 主旋鈕回讀 `r.RDG.TransientAllocator = "0"`，**並且**到那趟的 log 裡確認生效值（`r.RDG.TransientAllocator:0]]`）。次旋鈕不在表頭回讀，這點已記。 |
| 尺 2（`loopx` 無截斷） | 不設任何旋鈕，所以陽性樣本是**迴圈真的繞過 30 張**：表裡要出現卡號 > 30 的行。沒有就是迴圈沒生效。 |

### 第 6 條修正：指紋只涵蓋**會影響執行檔**的路徑

第一版把整個工作樹拿去雜湊，但那樣**我自己的 `Docs/` 提交就會在格子進行中改掉指紋**——
紀錄會說「兩趟之間樹變了」，而其實沒有一行會編譯的東西變過。
**一個會因為和量測無關的原因而變動的指紋，比沒有指紋更糟**，因為它會作廢好資料。

所以指紋改成只涵蓋 `Source`、`Plugins`、`Tools`、`*.Build.cs`、`Cargo.toml`／`Cargo.lock`、`.uproject`。
`HEAD` 照舊記，但**明寫 `HEAD` 單獨不能認一個執行檔**：一次文件提交會動 `HEAD` 而不動任何程式碼，
一個未提交的 `OKReaderScreen.cpp` 會動程式碼而不動 `HEAD`。要兩個合起來看。

### 排程衝突，照「保住量測」的那邊解

「`Note()` 旋鈕現在就寫好、提交、等 e-fork-2 那次重建捎帶」和第 6 條直接相撞：
**提交會改掉 `HEAD` 與建置相關的 diff，而尺 1 的六趟正要用現在這個指紋。**
所以：**程式碼現在寫好但不套用、不提交**；等尺 1 六趟跑完、交機之前才套用與提交。
這樣它一樣趕得上 e-fork-2 的重建（基線只作廢一次），而尺 1 的六趟仍共用同一個指紋。

### 第 7 條第二條附則：**每一個計數都要帶分母**

> 回報「某事發生了 N 次」時，同時回報「有幾次機會發生」。
> **沒有分母的 0 不是觀測結果**，它和「量具沒跑」無法區分；
> 有分母的 0（`checked=40000, hits=0`）本身就自帶陽性樣本，不必另外造假資料。

並把今天所有空刻度的共同教訓抄進標準：
**「只看『沒當掉』不算，那正好是旋鈕沒生效時的樣子。」**

據此**改掉 `LogPoolReuse` 的補法**：原本打算加一個旋鈕強制呼叫一次 `Note()`，
改成在 `Note()` 的呼叫點加一個**到達次數**計數，輸出 `reached=N, reused=M`。
更安全（不改任何行為、不塞假資料）、少改一處，而且一次就把這一類攔掉。
`LogStaleTextures` 同樣改成 `checked=N, hits=M`。

### `gclrun` 的直接讀數找到了，**不必靠 VRAM 推**

引擎自己就有，而且不用改一行程式：

- `stat RHITransientMemory`（`RHICoreTransientResourceAllocator.cpp:69-78`）：
  Memory Used／Aliased／Requested，外加 Resources／Textures／Buffers 三個計數。
- `rhi.DumpResourceMemory ... Transient=yes`（`RHI/Private/RHI.cpp:1037-1039`）：直接把 transient 資源列出來。

常駐 heap 數（`LiveList.Num()`）本身只有 trace 計數（`TransientAllocator/MemoryRangeCount`，`:64`），只有 Insights 看得到；
但 `Memory Used` 是配置器自己報的數字，retention 調大之後它應該只升不降——這比用 VRAM 推一層好。

**而這個量具的自測不花額外機器時間**，因為兩個樣本都已經在排程裡：
- **陰性**：`TransientAllocator=0` 的組態下沒有 transient allocator，這個 stat 應該是 0／缺席；
- **陽性**：預設組態下應該 > 0。

所以把兩次查詢各放進尺 2（`loopx`）那個格子的第一趟與一次刻意加的 `TransientAllocator=0` 探針裡，
同一次 claim 內完成。**在這個自測通過之前不跑 `gclrun`**——照第 7 條，不然它的輸出不能進紀錄。
（尺 1 的趟只活 25–34 秒，來不及查詢，所以不在那裡做。）

### B1 兩趟都當：**背景拷貝和啟動期零張卡的重現無關**（2/2）

| 趟 | 次旋鈕核對（log 裡的生效值） | 幾秒 | 結果 |
|---|---|---:|---|
| B1 趟 1 | `r.RDG.TransientAllocator:0` ✓ | **25.4** | 啟動期當掉，零張卡 |
| B1 趟 2 | `r.RDG.TransientAllocator:0` ✓ | **25.0** | 啟動期當掉，零張卡 |

`NoBackdrop=1` 是「拷貝根本不做」，所以**把背景整條拿掉，救不了這個重現**，2/2。
次旋鈕照上次記下的做法逐趟到 log 裡核對過（表頭只回讀主旋鈕）。

兩趟 25.4 與 25.0 秒，和不帶 `NoBackdrop` 的原始兩趟（34.0、24.2）放在一起是 24.2–34.0 秒；
照第 6 條，原始那兩趟在 **13:54** 的執行檔上、B1 兩趟在 **15:05** 的，
所以**不能併成一個分布**——尺 1 那六趟就是要在 15:05 這個執行檔上把這件事做對。

### 兩個量具的分母補丁寫好了（`denom.py`），六個錨點都確認唯一

設計照第二條附則改過：**不加強制呼叫的旋鈕**（那是改行為來量行為），改成
- `Note()` 進入點加 `Reached` 計數（在所有早退之前）；
- `CheckNotStale` 加 `StaleChecked` 計數（同樣在早退之前）；
- 兩個數字由**每幀必經**的 `FDreamUIRenderer::PostRenderView_RenderThread` 每 600 幀印一行：
  `DreamGUI denominators: frames=F note_reached=N stale_checked=M stale_hits=H`。

**那一行印得出來本身就是記錄機制的陽性樣本**，行裡的數字就是分母。
於是「`note_reached=0` 而 `frames=20000`」才是一個觀測，0 才能歸因到呼叫點。

六個錨點逐一確認在現在的檔案裡各只出現一次（`Note` 簽名、建構式行、`DreamUIExperimentBackdropMode` 宣告行、
`StaleHits` 宣告、`CheckNotStale` 簽名、`Tick_RenderThread()` 呼叫點）。**尚未套用**：
尺 1 的六趟要共用現在這個建置指紋，所以等它跑完、交機之前才套用與提交，趕 e-fork-2 那次重建。

### 這一輪到此為止的全部結果（15:05 那個執行檔，e-fork-2 建置**之前**）

建置指紋：`UnrealEditor-OpenKoikatsu.dll 11-19_15:05`；建置相關的髒檔是
`OKExtractBuildStamp.h`（建置產物）與 e-fork-2 未提交的 `OKCharacterController.h`、`OKCharacterMCP.cpp`、`OKReaderScreen.cpp`。
以下每趟的 `# build:` 都是這一個。

| 格 | 旋鈕（全部核對過） | 趟 1 | 趟 2 |
|---|---|---|---|
| A1 | `NoBackdrop=1` | 第 7 張 | 30 張跑完 |
| A2 | `NoBackdrop=2` | 第 9 張 | 第 2 張 |
| AP | `Frames.Pooled=240`（刻度是否為空：尚未證實） | 30 張跑完 | 第 15 張 |
| B1 | `NoBackdrop=1` ＋ `TransientAllocator=0` | 啟動期 **25.4 秒**，零張卡 | 啟動期 **25.0 秒**，零張卡 |
| B2 | `NoBackdrop=2` ＋ `TransientAllocator=0` | 啟動期 **25.3 秒**，零張卡 | **沒跑**（驅動卡住，見 ERROR_LOG） |

**沒跑到的**：B2 趟 2、A1 趟 1′、尺 1 六趟。原因是驅動卡住十分鐘而我沒察覺，不是結論改變。

**三件要照這份結果處理的事**：

1. **B2 不補跑了，理由不是趕進度**：B1 是**更強**的干預（拷貝根本不做），兩趟都照樣在 25 秒當掉；
   B2 只是較弱的干預（照配置、只不取樣）。既然「完全不配置」都沒有改變結果，
   「配置了但不取樣」這個問題就沒有可問的空間了。B2 趟 1 的 25.3 秒也和 B1 的 25.4／25.0 一致。
2. **A1 趟 1′ 永久取消**：它唯一的用途是把 A1 趟 1 的污染記號拿掉，而那只有在**同一個執行檔**上才有意義（第 6 條）。
   e-fork-2 一建置，它就比不了了。所以 A1 趟 1 的記號**永久留在紀錄裡**，
   旁邊那句照舊：這一格的結論不靠它（B1 的 2/2 和 A2 的兩趟才是依據）。
3. **尺 1 六趟改到建置之後**：反正建置會讓基線作廢（第 6 條），在建置前跑就是白跑一次。

### 共用程式碼的規矩擋下了「搭便車提交」

協調者要我把兩個量具的分母補丁**現在就提交**，好搭 e-fork-2 那次重建的便車（基線只作廢一次）。
**不照辦，理由是專案自己的規矩**：`Plugins/` 是 C／E／F 三組共用的程式碼，
而規矩寫明改到共用程式碼的提交，提交前要實際建置會連結它的 Unreal 目標並確認連結成功。
把**沒編譯過**的 DreamGUI 改動提交進去，等於把「別組編譯失敗」這個最高優先的 bug 的風險丟給 e-fork-2。
省下一次重建不值這個風險。

所以：補丁（`denom.py` ＋ 兩段手寫的部分）留在我自己的窗口裡**套用、建置、確認連結、才提交**，
代價是多一次重建，這個代價我接受。

### 34.0 秒那筆不需要單獨解釋：**它在另一個執行檔上**，而緊的那個帶是同一個執行檔內的

把每一趟「啟動期零張卡」的身分和秒數排在一起：

| 趟 | 幾秒 | 執行檔（dll mtime） | `HEAD` | late shader associations |
|---|---:|---|---|---|
| `trans_pass1` | **34.0** | 11-19 **13:54** | `1da9bcf34` | 1009 ms |
| `trans_pass2` | **24.2** | 11-19 **13:54** | `a135e8d35` | **11 ms** |
| `bg_B1_1` | **25.4** | 11-19 **15:05** | `b9e6f4979` | 1008 ms |
| `bg_B1_2` | **25.0** | 11-19 **15:05** | `450255784` | 1008 ms |
| `bg_B2_1` | **25.3** | 11-19 **15:05** | `e7c6f36ad` | 1009 ms |

所以那個「1.2 秒寬的帶」要修正成更準確、也更強的說法：
**15:05 這個執行檔上三趟是 25.0／25.3／25.4——寬 0.4 秒**；
而 34.0 與 24.2 是 **13:54** 那個執行檔上的兩趟，照第 6 條它們**本來就不能和那三趟放進同一個分布**。
所以 34.0 不是一個需要查身分的離群值，它是另一個執行檔上的量測，而那個執行檔上只有兩筆（34.0 與 24.2）。

**這張表同時是第 6 條最好的例證**：那三趟的 `HEAD` **三個都不一樣**（`b9e6f4979`、`450255784`、`e7c6f36ad`，
中間是我自己的文件提交），但 dll mtime 完全相同、秒數落在 0.4 秒內。
**`HEAD` 動了三次而執行檔一次都沒變**——這就是為什麼 `HEAD` 單獨不能認一個執行檔。

**順手看到一個可能有用的差異**：`trans_pass2` 的 late shader associations 只有 **11 ms**，
另外四趟都是 1008–1009 ms。它也正好是最快當掉的那一趟（24.2 秒）。n=2 還不能說什麼，
但建置後的尺 1 六趟值得把這個數字一起記下來：如果秒數和那 1 秒的著色器工作有關，六趟裡就會看得出來。

### `late shader associations` 那個欄位：**是上限，但它在故障之後才產生**，所以不能當趟的身分

讀出來的兩件事：

**一、是上限，不是耗時**（協調者猜對了這一半）：`CreateShaderAssociations`
（`D3D12NvidiaExtensions.cpp:62-229`）開頭就是
`PipelineStateCache::GetPipelineStates(PipelineResources, true, FTimeout(FTimespan::FromSeconds(1)))`，
註解寫明「allow one second for consolidation to finish」。所以 **1008／1009 ms 就是那個寫死的一秒等滿**，
而 `trans_pass2` 的 **11 ms** 意思是「PSO 合併早就做完了，不用等」。這個欄位實際上是**二元訊號**（等滿／沒等），不是時間。
（順帶：`r.GPUCrashDebugging.Aftermath.LateShaderAssociations.TimeLimit` 預設是 **7.5 秒**，不是那個一秒，兩者別混。）

**二、但它是故障之後才跑的，所以不能當「冷趟／暖趟」的身分**：
`GLateShaderAssociateFunc` 的唯一呼叫點在 Aftermath 的 **GPU crash dump 解碼流程裡**
（`RHICoreNvidiaAftermath.cpp:848-857`，上面那行註解是 `// Allow association after a fault`，
緊接著就是把 `Active Shaders:` 接到 `CrashResult.OutputLog`）。
我自己那份 log 裡 `Active Shaders:` 只出現一次，就在那個位置。

所以這個欄位描述的是**當掉當下與當掉之後**的狀態，不是開跑前的著色器快取冷暖。
**六趟不可以按它分成冷／暖兩組**——那會把一個下游產物當成上游條件。
（故障報告裡那句 `"Shader name": "fragment_02"` 也是從這條路來的，所以 Aftermath 在這些趟裡是開著的。）

**它仍然有一個弱訊號，但方向要講對**：四趟等滿一秒＝**當掉當下 PSO 合併還在進行**；
`trans_pass2` 的 11 ms＝當掉當下合併已經結束。
不過有一個同樣合理的解釋必須並列：**正在處理 GPU 當機時管線本來就卡住了，合併當然推不動**，
那樣「等滿一秒」就只是「當機中」的同義詞，和成因無關。
目前沒有東西能分開這兩種讀法，所以**不改計畫**；只記一條：
這一點讓先前因為「那個窗口讀成關上的」而放掉的 `r.pso.EnableAsyncCacheConsolidation` 那格值得重開，
優先序放在尺 1、尺 2 之後。

### 第 6 條再補一個維度：**趟的身分還包括「讀卡器讀的那份資料」**

e-fork-2 指出它接下來要做 `base_v1` 補錄（15–20 分鐘），而**補錄改的是開卡時讀的資料**，
所以補錄前後量出來的不是同一份資料。這是第 6 條原本漏掉的一整個維度：
先前只綁了**執行檔**與**建置相關的工作樹**，沒有綁**資料**。
而這個維度和 `late shader associations` 那個欄位不同——它**確實在開卡這條路的上游**。

所以趟的身分加上：

- `base_v1` 的**淺層清單雜湊**（`find -maxdepth 2 -type f -printf '%s %T@ %P'` 排序後雜湊）＋
  `sources.okidx` 的大小與 mtime（補錄會重寫這個索引，所以它是最靈敏的單一檔案）；
- 測試卡目錄的同樣雜湊（卡片集換了也不是同一個實驗）。

**為什麼用淺層而不是整棵樹**：整棵樹（140,963 個檔）跑一次 `printf`＋排序＋雜湊要 **94 秒**，
淺層只要 **0.1 秒**。尺 2 在**趟與趟之間會 release**，所以別組有可能在我兩趟之間做補錄——
因此資料指紋**必須逐趟取**，不能一格取一次。94 秒 × 6 趟＝9.4 分鐘的獨佔時間只為了指紋，不值得。

**代價寫明**：淺層清單漏得掉「只動 `models/` 深處、不動上兩層」的改動。
補錄會重寫 `sources.okidx` 與 `oklib.json`，所以實務上蓋得到；
為了把這個漏洞補上，整棵樹的那個 94 秒雜湊在**整格的頭尾各取一次**當括號——
兩端相同，就表示這一格之內深處沒有變過。

### 順帶：兩組的指紋算法不一樣，記下來以免日後對不上

e-fork-2 用的是 `git diff HEAD -- <build paths> | git hash-object --stdin`（單一雜湊）；
我用的是 `git status --porcelain -- <build paths>` 與 `git diff -- <build paths>` 兩個 sha256 前 16 字。
**兩者都有效但不可互相比較**。它那份的值是 `1bd7eedf5c5a7b062f290bd82d54bdb7d3e81c42`，四個髒檔
（`OKExtractBuildStamp.h` ＋ 它那三個 C++）。我在自己的表裡**兩種都記**，這樣跨組對照時不必重算。

**新執行檔的身分**（e-fork-2 給的，我的基線從這裡起作廢）：
`UnrealEditor-OpenKoikatsu.dll 2026-11-19 16:25:48`、`OpenKoikatsu.exe 16:27:10`、`ok_extract.lib 16:25:11`。

#### 資料指紋第一版就不穩，而且不穩的原因正好證明它有用

剛寫好就測了兩次（相隔三秒），**雜湊不一樣**。查下去是 `base_v1/work/` 裡有檔案正在被寫入
（`work/strict_28092_0.png` 等，mtime 就是當下），也就是 e-fork-2 的補錄**正在跑**。

兩個結論：

1. **`work/` 要排除**：那是抽取程式的暫存輸出，**不是讀卡器讀的資料**。
   把它算進指紋，指紋就會因為和量測無關的原因變動——正是我自己寫下的那條
   「一個會因為無關原因變動的指紋比沒有指紋更糟」。排除之後兩次相隔四秒的雜湊相同。
2. **這次不穩本身就是這個量具的陽性樣本**：它確實偵測到了一個正在發生的資料改動
   （第 7 條要的陽性樣本，而且是自己撞上來的，不用造）。陰性樣本是排除 `work/` 之後的穩定重複。

同時也確認了一件排程上的事：**補錄此刻正在跑**，所以現在不能量，和 e-fork-2 的提醒一致。

#### 一個獨立的交叉確認：我的樹就是那個 binary 建出來的那棵

用 e-fork-2 的算法在我這邊算，得到 `1bd7eedf5c5a7b062f290bd82d54bdb7d3e81c42`，
**和它公布的值完全相同**；`dll` 也是 `11-19_16:25:48`。
所以我接下來量的，確實是它建的那個執行檔配上它建置時的那份原始碼——
這是第 6 條第一次真的派上用場，而不只是記錄一個欄位。

### 冷暖這個維度：**未受控，也未量到**，而且找過一個候選指標、沒看到差異

原則保留——**同一個執行檔上的冷趟與暖趟不是同一個實驗**——但照實寫明：
這個量測裡**目前沒有任何可觀察的量能說開跑前的快取是冷是暖**。所以六趟當一組看，
紀錄裡標明這個維度**未受控、也未量到**；若尺 1 六趟出現無法用別的因素解釋的雙峰，再回來找真指標，
**不要事後拿崩潰報告的欄位去追認**。

順手把協調者提的候選指標之一查了：**載入過程本身的著色器編譯活動**。
比對 1008 ms 那趟（`bg_B1_1`）與 11 ms 那趟（`trans_pass2`）的 `LogShaderCompilers` 行——
**兩趟逐行相同**（同樣是 16 個本機 worker、同樣兩個 autogen 檔「unchanged, skipping write」，沒有編譯批次差異）。
所以在這個候選指標上也**看不到冷暖差異**，這又多一分支持「那個欄位不是冷暖的代理」。
（這是一個陰性結果，但它有分母：兩趟的該類日誌行都存在且可比，不是「沒抓到東西」。）

### `r.pso.EnableAsyncCacheConsolidation` 重開前的陽性樣本申報（第 7 條）

先把那個欄位的機制讀乾淨：crash handler 的一秒等待走
`GetResources` → `WaitAndFinishAsyncCacheConsolidation(Timeout)`（`PipelineStateCache.cpp:1883`、`:2026-2041`），
而那個函式**在 `RHICompletionEvent` 為空時立刻回 `true`**；一秒被吃掉是因為
`RHICompletionEvent->FTaskBase::Wait(Timeout)` 等不到完成。
而那個完成事件只有在 `GEnablePSOAsyncCacheConsolidation` 為真時才會建立（`:1821`）。

**所以陽性樣本是（在跑之前登記）**：把 `r.pso.EnableAsyncCacheConsolidation=0` 之後，
**`Created late shader associations` 的毫秒數應該從約 1008 ms 掉到很小的值**（11 ms 那種量級）。
這是一個**行為讀數**，不是旋鈕回讀，而且它在每一趟的表裡本來就有，不必加任何工具。
- 掉下來 ⇒ 旋鈕真的生效，那一格的結果可以讀；
- 還是 1008 ms ⇒ 旋鈕沒接上（或那一秒另有來源），**那一格的結果不能進紀錄**，照第 7 條辦。

**兩種讀法仍然並列，而且第二種現在有了明確依據**：`:1882` 的註解寫著
「Consolidation is predicated on command context completion, allow for a timeout in case it's blocked」——
合併本來就依賴 command context 完成，而 GPU 當掉時那當然推不動。
所以「等滿一秒」可能只是「當機中」的同義詞。這一格能分開的是**旋鈕有沒有生效**，
不是**那一秒的成因**；成因要另外設計。

### `r.pso.EnableAsyncCacheConsolidation` 這一格的範圍再收緊，而且收緊之後出現一個新衝突

協調者的收緊是對的，而且比我寫的更窄：`1008 → 11 ms` 的掉落**按建構就會發生**
（旋鈕為 0 ⇒ 完成事件不建立 ⇒ 等待立刻返回），所以它證明的是**那個 cvar 的值走到了那條路**，
**不是「執行期不再做非同步合併」**。後者才是可能和當機有關的部分，因為合併本身跑在正常執行期，
crash handler 只是在等它。兩件分開記：

- **旋鈕被讀到**：`Created late shader associations` 從約 1008 掉到 11 ms 量級。沒掉就把那一格丟掉。
- **當機有無改變**：只用那把 0.4 秒的尺（到故障幾秒、撐幾張卡）。那個欄位在故障之後才產生，
  **不能既當生效證明又當結果**。

**新衝突，先講清楚**：要證明「執行期行為真的變了」，目前**沒有主控台可見的計數**。
`PipelineStateCache.cpp` 裡有 `stat PipelineStateCache`（PSO hitch 計數、precached 總數）與 `DumpPipeline` 命令，
但**沒有任何「合併跑了幾次」的計數**。唯一的直接觀察是 `:1903` 的
`SCOPED_NAMED_EVENT(ConsolidateThreadedCaches, ...)`，那要開 Unreal Insights trace 才看得到。

而 **trace 的額外負擔會動到時間**，而我的尺只有 **0.4 秒寬**。
所以：**證明行為改變的那一趟和量尺的那一趟不能是同一趟。**
要做就分成兩種趟——帶 trace 的趟只回答「合併行為變了沒」，不帶 trace 的趟才進尺的分布。
在那之前，這一格誠實的結局就是協調者說的那個：**旋鈕生效、尺沒動 ⇒ 乾淨的排除**，
不要因為欄位變了就讀成有進展。

### 指紋規則加上版本號，而且剛好抓到補錄已經改了基礎庫

照協調者要的把排除寫進規則敘述並**版本化**（`FP_RULE`，每次輸出都印）：

- `fp-rule-2`（2026-11-19）：`base_v1` 淺層清單**排除 `work/`**（抽取程式的暫存，補錄期間會被寫）；
  建置路徑如前；同時印 e-fork-2 的單一 `git hash-object` 值與我的兩個 sha256 前綴，
  因為**那兩者彼此不可比較**。
- `fp-rule-1`（已汰換）：同上但含 `work/`——補錄進行中會不穩。

**規則變了而沒記，兩組的指紋會互相誤判為可比**，所以版本號和值一起印。

另外加一個 `work_dir_state`：每格報一次 `work/` 的檔數。補錄完它應該是空的或不存在；
若還留著東西就值得問一句，因為殘留的暫存會進下一次比較。

**剛才取指紋時看到的現況**（也就是這個量具又一次做對了事）：
`sources.okidx` 已經從 `1077443477 @ 11-16_13:33` 變成 `1077443567 @ 11-19_16:36`，
`work/` 有 **571** 個檔——**補錄已經改掉基礎庫了**，所以現在量任何東西都不對，和排程一致。

## 第 8、9 條（定版），以及一個編號上的提醒

**編號先講清楚**：先前只定到第 7 條（＋兩條附則）。協調者把「擾動量尺的量具要分趟」直接叫**第 9 條**，
另一條（舉證責任）沒給號、只說「放在第 7 條旁邊」。
為了不讓兩邊的紀錄各自長出不同的編號，**我把舉證責任那條定為第 8 條**，並在這裡寫明是我指派的。
（這和 `fp-rule` 版本化是同一類問題：規則本身也要有版本與來源，否則兩份紀錄會互相誤判為同一套。）

**第 8 條（舉證責任隨主張放大）**：

> **「沒有效果」只需要證明干預到達；「有效果」才需要證明干預做了什麼。**

所以 PSO 那一格的順序是：先跑**不帶 trace** 的趟（0.4 秒的尺＋`1008 → 11 ms` 當「cvar 走到那條路」的生效證明）；
**尺沒動就到此為止**，不必再花一趟 trace——結論是「沒影響」，更強的證明只會讓同一個「沒影響」更確定，換不到新決定。
**尺動了才需要那趟 trace**，因為那時「是什麼變了」才成為必須回答的問題；
否則就會把一個不知道機制的效果寫成結論，而那正是今天撤回那幾條的原因。

**第 9 條（會擾動量尺的量具要分趟）**：

> trace、逐幀日誌、額外計數這類有成本的觀測，一旦其成本和量尺的解析度同一個量級
> （這把尺只有 0.4 秒寬，Insights trace 的負擔遠超過它），就不能和量尺放在同一趟。
> 帶觀測的趟只回答「機制有沒有變」，不帶觀測的趟才進量尺的分布。

第 9 條是「陽性樣本優先用本來就會被記錄的行為讀數」這條的**例外處理**：
當既有讀數不足、必須另造觀測時，那個觀測要自己一趟。

### 第 8 條用在這一格時，排除的範圍要寫對

「尺沒動」能排除的是**那個旋鈕（以它實際被讀到的程度）沒有改變當掉時機**，
**不是**「非同步 PSO 合併這個機制和當機無關」。兩者差一大截：
我們已經讀出 `1008 → 11 ms` 只證明 cvar 的值走到那條路，沒證明執行期真的不再做合併。
所以紀錄裡的措辭必須是**排除旋鈕**，不是排除機制；要排除機制，就得補那趟帶 trace 的（第 9 條）。
把前者寫成後者，就是把一個「未知」寫成「已排除」——今天撤回的那幾條都是同一個毛病。

## 編號改正：我那條從 8 改成 **10**（協調者裁定）

我自行指派的第 8 條**撞到既有的第 8 條**——協調者早先在 f-sceneload 那條線上已經定過第 8 條，
而且已經寫進那邊的文件。所以**編號由協調者裁定，三棵樹統一用這套**：

| 條 | 內容 |
|---|---|
| 6 | 趟的身分（執行檔 mtime／大小、`HEAD`、收窄後的工作樹指紋、不進版控的資料四個資料夾）；只有同一個執行檔上的趟可互比；有人建置則基線作廢；`HEAD` 單獨不能認人 |
| 7 | 量具使用前要對已知為正與已知為負的樣本自測並留紀錄 |
| 7a | 未自測量具的陰性結果同時蓋住「記錄壞了」與「被記錄的事沒發生」 |
| 7b | 每個計數都要帶分母 |
| 7c | 驗量具不要接管線（`$?` 是管線最後一個指令的碼）——這條來自 f-sceneload 那條線 |
| 7d | 陽性樣本優先用**本來就會被記錄的行為讀數**，而不是另造記錄機制 |
| 8 | **量測用到的未提交改動必須在量測前固定下來**：提交，或把 `git diff` 存成存檔的 patch 並把 patch 雜湊記進表頭 |
| 9 | 會擾動量尺的量具必須和量尺不同趟 |
| **10** | **舉證責任隨主張放大**——「沒有效果」只需證明干預到達；「有效果」才需證明干預做了什麼 |

原先自行指派為 8，因與既有第 8 條衝突而改為 10。**往後新規則一律由協調者編號**（內容由提出者寫、號由它給），
避免兩份紀錄各自長號——這正是我上一節擔心的那個問題，而它已經發生了一次。

### 第 8 條（別人的那條）直接落在我身上，已經實作

我接下來要量的那個執行檔，是從帶著**四個未提交改動**的樹建出來的
（`OKExtractBuildStamp.h` 是建置產物，另外三個 C++ 是 e-fork-2 的，**不是我能提交的**）。
照第 8 條，提交不是我的選項，所以走另一半：**存檔 patch 並記雜湊**。

`build_fingerprint` 現在會把 `git diff HEAD -- <建置路徑>` 存到
`Saved/Reports/card-reader-dreamgui/tree-<雜湊>.diff` 並印出路徑與大小。
`Saved/` 不進版控，又是這個專案放本機量測產物的地方，所以存那裡，不放會被清掉的 scratchpad。

目前那份是 `tree-1bd7eedf5c5a7b062f290bd82d54bdb7d3e81c42.diff`（14,442 bytes），
並且**驗過它真的能重建**：`git apply --check --reverse` 乾淨通過，
所以這份存檔不只是「一個雜湊」，而是能把樹還原回已提交狀態的實體 patch。
（光有雜湊只能偵測到樹不一樣，不能重建它是什麼——這就是第 8 條要存檔不只要雜湊的理由。）

### 第 8 條的存檔補強了三處，其中一處是我的驗證方向錯了

**一、未追蹤檔**：`git diff HEAD` **不含未追蹤檔**，而一個從來沒 `git add` 的新 `.cpp` 照樣會被編進執行檔。
所以 `build_fingerprint` 現在對建置路徑跑 `git ls-files --others --exclude-standard`，有東西就連檔案一起存進
`untracked-<樹雜湊>/`，沒有就明寫 **`untracked: none`**——
**記「沒有」和記「有」一樣重要**，否則下次看到只有 `.diff` 的存檔，分不清是當時沒有未追蹤檔還是當時沒去看。
目前是 `none`。

**二、我的驗證方向錯了一半**：`git apply --check --reverse` 乾淨通過，證明的只是
「這份 patch 和**現在這棵樹**對得上、可以被移除」，對**日後重建**什麼都沒說。
要的是「檢出當時記錄的 `HEAD`，把 patch 正向套上去」。

**但不必開 worktree，有一個零成本的等價做法**：`git apply --check --cached` 是對**索引**套用，
而這四個檔在索引裡等於 `HEAD`（`git status --porcelain` 顯示 `" M"` 而不是 `"M "`，腳本裡也先用
`git diff --cached --quiet` 斷言這一點），所以 `--cached` 的正向套用**就是**「套到 `HEAD` 上」。
結果：**`patch_rebuilds=yes`**。
（協調者建議的 scratch worktree 要從 **11.07 GiB** 的 pack 檢出 **13,461** 個追蹤檔，
而此刻 e-fork-2 正在做 IO 很重的補錄——那會跟別組搶 IO，而且換不到多一分確定性。）

**三、另外一個獨立的基底檢查**（純讀、零成本）：patch 每個 hunk 的 `index <舊>..<新>` 裡的舊 blob 雜湊，
應該等於記錄的 `HEAD` 上同一個檔的 blob。四個檔**全部相符**。
這比 `--cached` 更直接地回答「我記的 `HEAD` 和這份 patch 是不是同一個基底」。

**寫這個檢查時自己踩了一次**：第一版用 `awk 'split($2,a,"..")'`，
而 **awk 的 `split` 分隔符是正規表示式**，`..` 於是match任意兩個字元，四個檔全部報 MISMATCH。
改成 `split($2,a,/\.\./)` 之後四個都 OK。**一個會把全部樣本都判成失敗的量具，看起來很像「發現了問題」**——
這次是因為我手上有一個已知為正的樣本（那份 patch 本來就是從這棵樹產生的）才立刻看出是量具壞了，
正是第 7 條的用處。

**四、那份 patch 不要在 e-fork-2 提交那三個 C++ 之後刪掉**：
它們成為 commit 之後，同樣內容會以 commit 形式存在、看起來 patch 變多餘，
但存檔記的是「這個執行檔是從什麼狀態建出來的」，而那個狀態**當時並不是任何一個 commit**。留著。

### 順帶發現：`.git/objects/pack` 裡有 39 個 `tmp_pack_*` 殘留

`git count-objects -vH` 對 39 個 `tmp_pack_*` 檔報 `warning: garbage found`。
那是中斷的 fetch／push／repack 留下的暫存包。**這是三組共用的 repo，我不動它**，
只記在這裡並通報協調者：它們會一直佔磁碟，而 `git gc` 之類的清理要由誰做、什麼時候做，是整組的決定，不是我的。
