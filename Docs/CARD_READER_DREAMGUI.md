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
