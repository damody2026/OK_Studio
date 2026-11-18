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

## 未結案：讀卡器第三條 GPU PageFault（2026-11-19，追查中）

**當前假設：累積型資源成長**（協調者與 e-cardload 提出，正在量）。2026-11-19 05:45 那次量測先排除了它的「VRAM 吃緊、常駐資源被逐出」這條機制，見下方「連開 30 張的量測」。

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
