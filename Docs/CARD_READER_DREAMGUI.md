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

## 第 11 條（協調者編號）：陰性對照同時給出量具的分辨率

> 把設定重設成它**本來就是**的那個值再量一次，兩次之間的差就是**噪聲地板**。
> **低於地板的結果寫「判不出來」，不寫「沒效果」**——兩者要做的事完全不同：
> 「沒效果」去查干預有沒有到達（第 7、10 條），「判不出來」去壓噪聲或換更銳的指標。
> 報結果時要把地板的數值一起寫出來。

這條補上第 7 條缺的一塊：**7 管量具會不會動，11 管量具動得夠不夠細**——
一個量具可以自測通過（會動）卻仍然分不出你要的差異。

### 套到我這兩把尺上，但有兩處要比協調者的說法更保守

**一、啟動期那把尺的地板「目前是 0.4 秒」，但那是 n=3 的全距，不能當成分辨率定案。**
25.0／25.3／25.4 只有三趟，而**小樣本的全距會系統性低估散布**。
照第 11 條，地板要由**尺 1 的六趟**（同一組態、不動任何別的旋鈕，正是「把設定設成它本來就是的值」）算出來，
而且六趟的全距很可能比 0.4 秒寬。
**在那六趟之前不要把 0.4 秒寫成這把尺的分辨率**，否則會把一個 0.5 秒的移動當成真效果，
而真地板也許是 2 秒。尺 1 的第一個產物就是這個數值。

**二、卡數那把尺的地板「是 2..30+」要再精確一點。**
2..30+ 是把 A1、A2、AP **三種不同旋鈕**的趟混在一起算的，
而「混進來的旋鈕都沒有效果」正是我們要檢驗的事——拿它當地板是循環論證。
嚴謹的說法是：**同組態重複量測只有三對，每對 n=2**：

| 同組態的一對 | 兩趟 |
|---|---|
| A1（`NoBackdrop=1`） | 7 與 **30+** |
| A2（`NoBackdrop=2`） | 9 與 2 |
| AP（`Frames.Pooled=240`） | **30+** 與 15 |

**每一對自己就跨了很大一段**（A1 從 7 到天花板、AP 從 15 到天花板），
所以不必混組也能說「這把尺的地板大過任何合理效果」——結論不變，但依據不循環。

而且照第 11 條，`loopx` 六趟基線的第一個產物就是**那把尺的地板數值**；
地板算出來之後才知道什麼效果大小是它能看見的。
**若地板仍大到任何修法都落在裡面，那把尺就該放棄，不要再為它補趟。**

### 連帶要改的措辭

先前寫過的「卡數分不出東西」，照第 11 條應該寫成**「這把尺的噪聲地板大過任何合理效果，所以判不出來」**，
而不是「卡數和當機無關」。這和 PSO 那一格的措辭規則是同一條：
**一個乾淨的排除要寫清楚它排除了什麼、沒排除什麼**，而「判不出來」根本不是排除。

## 第 10 條附則 a：結果有三種，不是兩種——而我要提議把第 2 種再拆成兩半

協調者定的三分法：

1. **干預沒到達**（旋鈕沒接上）→ 去查接線；
2. **干預到達了，但這個指標不可能反應**（指標在那個方向上飽和，或根本量錯東西）→ 換指標；
3. **干預到達、指標也夠靈敏，卻沒有動** → 這才是真正的「沒效果」，也**只有這種**可以寫成排除。

f-yvonne 的實例（抄進來，因為它把第 2 種講得最清楚）：她的「環境光歸零」日誌寫著
`ambient=0.00 ... scaled=116`（到達了，116 個材質被寫入），照片卻完全不變——因為原作著色公式
在主光為 1 時恆取 1，**調低環境光本來就看不到變化**。
沒有那行日誌，這會被寫成「沒效果」然後去查接線，查一整天查不出東西。

**提議（內容我提，號請協調者給）：第 2 種要再拆成兩半，因為補救方向相反。**

| 類 | 情形 | 補救 |
|---|---|---|
| 2a | **干預到達，但沒有作用對象**——程式路徑上根本沒有它能作用的東西 | 不是換指標。結論是「**這個旋鈕在這條路徑上無事可做**」，是一個真的（雖然狹窄的）結論 |
| 2b | **干預到達、也真的作用了，但指標反應不出來**（飽和／量錯東西） | 換指標再量 |

f-yvonne 的環境光是 **2b**：旋鈕確實寫了 116 個材質，是照片這個指標看不見。
而 **Frames.Pooled 是 2a 不是 2b**：如果讀卡器從來沒開過 group，那麼「延後歸還 group 貼圖」這件事
**沒有任何對象**——不是「卡數這個指標飽和」（它一點也不飽和，它在別的格子裡會動）。
把 2a 寫成 2b 會把人送去換指標，而正確的動作是認定這個旋鈕與這條路徑無關。

### 照這個三分法重新分類我那三個降級結論

| 格／量具 | 現在的分類 | 還缺什麼才能定案 |
|---|---|---|
| `Frames.Pooled`（AP 格） | **2a 的候選**，但「到達與否」未知 | `Note()` 的到達次數（分母）。`reached=0` 而 `frames` 很大 ⇒ 確認 2a；`reached>0` ⇒ 其實是第 3 種，要重讀 |
| AP 是「偽裝的基線」 | **跟著上一列**：只有在 `Frames.Pooled` 確認是 2a 之後，AP 才真的等於基線 | 同上 |
| `LogStaleTextures` 命中 0 | **第 1 種與第 2a 種分不開** | `StaleChecked`（分母）。`checked>0, hits=0` ⇒ 第 3 種（真的沒有過期貼圖）；`checked=0` ⇒ 第 1 種（量具沒跑到） |

**所以那兩個分母補丁要回答的，正是「這是第 1 種、2a 種還是第 3 種」**——
這比我原本寫的「證明記錄機制能印」更準確地說明了它們的用途。

## 第 11 條附則 a：地板不只要量到，還要**定位**

> 一個沒解釋的地板可能是**可以移除的伪影**，而不是必須繞過的噪聲。

f-yvonne 的實例：地板 2.90 → 追到最差格 (216,72) → 發現那是只有基準張才有的「正在打開」提示框 →
改成只量身體區域，地板降到約 0，而原本「判不出來」的那一項立刻變成**有效果**。

**對我那把 0.4 秒的尺的下一步**：那 0.4 秒**來自什麼，目前沒人知道**。
尺 1 六趟跑完之後，若六趟仍落在約 0.4 秒內，就花一點**不用機器**的力氣去定位它——
逐趟的 I/O 抖動？某個固定的等待？還是時戳本身的取樣解析度（log 的時戳只到毫秒，而我是從
「第一個有時戳的行」算起，那一行本身出現的時機就有抖動）？
**定位得出來，這把尺可能比 0.4 秒更銳**；定位不出來，就照實把 0.4 秒當分辨率寫進紀錄。
**不為此另跑趟數。**

## 第 12 條：截圖要自帶「拍到的確實是它聲稱的東西」的證明

f-yvonne 查出：**讀卡器載卡失敗會保留上一張畫面**（`OK load3d result ok=0`），
所以一張看起來正常的截圖可以是上一張的殘影。

**我的量測不拍照，但同形狀的風險在我這裡是：一趟「跑完 30 張卡」要能對到 30 筆逐卡證據，
而不是只對到「迴圈結束」。** 查了，已經滿足，而且是用資料查的不是用記憶：

| 趟 | 逐卡行數 | `.tex` 檔數 | 最後一筆卡號 | faults |
|---|---:|---:|---:|---:|
| `bg_A1_2`（跑完 30 張） | **30** | **30** | **30** | 0 |
| `bg_AP_1`（跑完 30 張） | **30** | **30** | **30** | 0 |
| `bg_A2_2`（死在第 2 張） | 2 | — | — | 1 |
| `bg_A1_1`（死在第 7 張） | 7 | — | — | 1 |

逐卡行數和死亡卡號逐一對上，所以「跑完 30 張」有 30 筆獨立證據支撐。
尺 2 跑的時候會順手確認 `wrapped_past_30=` 那行和逐卡行數一致（繞過天花板時卡號會超過 30）。

## 第 7 條附則 e（協調者編號，內容是我這次踩到的）

> **一個把全部樣本都判成失敗的量具，看起來很像「發現了問題」。**
> 全部樣本都失敗時，**先懷疑量具、再懷疑被量的東西**；
> 而要能這樣懷疑，手上必須有一個**已知為正的樣本**。

這是第 7 條第一次攔下**這個方向**的錯誤——前面四次攔的都是「安靜的零」（量具什麼都沒找到，
看起來像「量到了沒有問題」），這次攔的是反過來的「假的陽性發現」。
我當時能立刻判定是量具壞了而不是樹壞了，唯一的理由是**那份 patch 本來就是從這棵樹產生的**，
所以「四個檔全部對不上」在邏輯上不可能是真的。
**已知為正的樣本不只用來證明量具會動，也用來攔假的發現。**

具體地雷寫下來：**`awk` 的 `split()` 分隔符是正規表示式**，所以 `split($2, a, "..")` 的 `..`
會 match **任意兩個字元**，不是字面的兩個點。要照字面切就用 `index()`／`substr()`，
或寫成 `split($2, a, /\.\./)`。

## 第 8 條的驗證定版

| 檢查 | 做法 | 回答什麼 |
|---|---|---|
| 正向重建 | `git apply --check --cached <patch>`，前提是 `git diff --cached --quiet` 通過（索引等於 `HEAD`） | 日後能不能把這份 patch 套回記錄的 `HEAD` |
| 基底一致 | patch 每個 hunk 的 `index <舊>..<新>` 舊 blob，對記錄 `HEAD` 上同檔的 blob | 我記的 `HEAD` 和這份 patch 是不是同一個基底 |
| 未追蹤檔 | `git ls-files --others --exclude-standard`；有就一起存檔，沒有就明寫 `untracked: none` | 有沒有「會被編進執行檔但不在 diff 裡」的檔 |
| worktree 正向套用 | **只有在索引不等於 `HEAD` 時才需要** | 同第一列，但要付 11 GiB／13,461 檔的檢出成本 |

`git apply --check --reverse` **不列入**：它只證明 patch 和**當下這棵樹**對得上，對日後重建什麼都沒說。

## 別組清掉 `.git` 裡 9 GiB 之後，我自己驗了一次完整性

協調者清掉 E 與 F 各 39 個 `tmp_pack_*`（共 9.06 GiB，全是 10-17／10-18 的殘留），只刪 `tmp_pack_*`、
沒碰真正的 `.pack`／`.idx`。**我的量測依賴這個 repo，所以不是聽說沒事就算沒事**，自己查了：

- `git count-objects -vH`：**不再有 `warning: garbage found`**，`size-pack` 仍是 11.07 GiB（暫存包本來就不算在內）；
- `HEAD` 正常解析（`827221a27`）；
- 我接下來要用的兩個關鍵 blob（`OKReaderScreen.cpp`、`DreamUICompositor.cpp`）都讀得出來；
- **存檔的那份 patch 仍然有效**：`git apply --check --cached` 照樣通過。

結論：清理沒有影響我的量測基礎。

**順帶記一條處置原則**（協調者也記了）：**共用資源的清理是調度層的事，不是正在量測的人該順手做的**——
尤其 `git gc` 會長時間鎖住 repo，而三組同時在提交與建置。
共用 repo、共用快取、共用 slot 檔這類東西，一律通報、不自己動。

### 定位那個地板的第一步做完了（零機器時間）：**參考點不是來源，而且總長比它的各段更穩**

照附則 11a，地板要定位。我自己列的三個候選裡，協調者點名先查「參考點本身的抖動」——
因為 `fault_secs` 是從「第一個有時戳的行」算起，而那一行出現的時機本身可能抖。

**先確認參考點的身分穩定**：五趟的第一個有時戳的行**每次都是同一行**
（`LogConfig: CVar [[con.DebugLateDefault`，frame 0）。所以它不是「隨便哪一行」，身分是穩的。

**然後換參考點重算**（15:05 執行檔上的三趟，`anchors.lua`）：

| 參考點 → 故障 | B1_1 | B1_2 | B2_1 | 全距 |
|---|---:|---:|---:|---:|
| 第一個有時戳的行 | 25.364 | 24.987 | 25.347 | **0.377** |
| `Chosen D3D12 Adapter` | 24.636 | 24.297 | 24.639 | **0.342** |
| `Game Engine Initialized` | 18.760 | 18.210 | 18.444 | **0.550** |
| `LogLoad: Took` | 16.756 | 16.198 | 16.488 | **0.558** |

（`late shader associations` 那列不是合法參考點：它是 crash handler 印的，在故障**之後**，
它那 0.007 秒的「全距」只是那個寫死的一秒等待。）

**兩個結論**：

1. **參考點不是地板的來源。** 換成最早的硬體層錨點（選定 D3D12 介面卡）只從 0.377 降到 0.342 秒——
   幾乎沒動。所以**這把尺沒辦法靠換參考點變銳**。
2. **更有意思的是：總長比它的各段更穩。** 從引擎初始化完成算起反而更散（0.550／0.558），
   比從頭算起（0.377）**更糟**。也就是說啟動各階段之間互相抵消，
   **故障發生在距離行程啟動大致固定的時間點上**，而不是落在某個啟動里程碑之後固定的工作量上。
   這對「成因」是一條有方向的線索：它比較像「從啟動起算的某個累積量」而不是「某個階段做完之後的某件事」。

**照附則 11b／11c 標註**：以上是 **n=3**，所以**不報中位數或平均**，只印原始值與全距；
而且 **0.377／0.342 秒是 n=3 的全距，不是這把尺的分辨率**——
分辨率要等尺 1 的六趟，小樣本全距會系統性低估散布。

## 附則 7h（協調者編號）：別人說沒事不構成自測，調度者說的也不構成

> 你的結果所依賴的東西被第三方改動過，由**依賴它的人**驗證，不是由改動的人宣告。

協調者清 `.git` 那 9.06 GiB 時給的四個依據是**它的判斷**，不是我的證據；
我驗的那四項（`garbage found` 消失、`size-pack` 仍 11.07 GiB、`HEAD` 解析、關鍵 blob 讀得出、存檔 patch 的
`--cached` 照樣通過）才是我能引用的東西。**位階不改變舉證責任。**

## 我的資料指紋覆蓋率只有 **22 / 140,376**，是對帳別人的數字才發現的

協調者報 `models` 有 **4543** 個檔。我去對自己的指紋覆蓋了哪些檔，才發現 `fp-rule-2` 的
`-maxdepth 2` **只走到 22 個檔**：模型檔住在 `base_v1/models/<兩位十六進位>/<名稱>.okmodel`，
那是 base_v1 底下**第 3 層**，所以 4,543 個 models、5,806 個 anims、8,443 個 studio、121,580 個 `h`
**全部不在指紋裡**。

**它之所以看起來能用，是因為補錄也會重寫 `sources.okidx`，而那個檔剛好在覆蓋範圍內**——
又是一次「意外的覆蓋」。如果哪天有人只改模型不動索引，我會量出一組和之前不可比的數字而毫無所覺。

**而當初把它拆成「便宜的淺層／昂貴的深層」的那個 94 秒，是冷快取下量的**，
而且當時補錄正在寫 `work/`。暖快取下整棵（扣掉 `work/`）只要 **約 6 秒**，連跑兩次雜湊相同。
所以**沒有理由再分淺／深**：

- **`fp-rule-3`**：整棵 `base_v1`（扣掉 `work/`）**全深度、逐趟取**。覆蓋 **140,388** 個檔，暖快取約 6 秒，
  最壞（冷）約 95 秒一次。`sources.okidx` 的大小與 mtime 仍單獨印出來當人眼可讀的快速指標。
- `fp-rule-2`（`-maxdepth 2`）**標記為有覆蓋率缺陷**，不是只是「比較粗」——它漏掉 99.98% 的檔。

舊的 `data_fingerprint_shallow` 留成別名指向新函式，**免得舊呼叫點安靜地量了個空**。

### 另外記下 e-fork-2 給的事實

- `base_v1` **沒有** `catalog.json`（不是漏記），所以指紋不該去找它；我的指紋用的是 `sources.okidx`，正確。
- A 段後的身分：`sources.okidx` size=1077443567 / mtime 16:51:52、`converted.tsv` size=7534181 /
  mtime 16:51:35、`models` 4543 個檔（補錄前也是 4543，沒新增）、`shared_mods.txt` 自 11-04 未變。
  **B 段會再變一次，以 B 段後那組為準**——我這邊 16:54:36 已經看到 `sources.okidx` 又動了，和它說的一致。
- `work/` 那 570 多個是別人留下的舊殘留（最舊 10-22），已排除在指紋外，不影響我。

### 幀數檢查：**不是幀驅動的**，而且這一條直接打到 `Frames.*` 那整條線

故障當下的幀數（log 每行自帶的 `[frame]`），15:05 執行檔上三趟：

| 趟 | 到故障幾秒 | 故障當下幀數 | log 裡的最大幀數 |
|---|---:|---:|---:|
| B1_1 | 25.364 | **395** | 877 |
| B1_2 | 24.987 | **212** | 665 |
| B2_1 | 25.347 | **520** | 936 |

**n=3**：幀數全距 **212..520（差 308，約 59%）**；秒數全距 **24.987..25.364（差 0.377，約 1.5%）**。

照事前登記的讀法：**幀數抖得遠比秒數大 ⇒ 不是幀驅動的。**
說得更強一點：**秒數幾乎是常數而幀數差了 2.5 倍**，所以這件事是由「從行程啟動起算的時間或工作量」決定的，
**不是由「跑了幾幀」決定的**。

**這一條直接打到 `Frames.*` 那整條線**：`FDreamUIDeferredRelease` 是**以幀計數**的
（`Frames.Texture`／`Buffer`／`Pooled`／`Func`，比較的是 `GFrameNumberRenderThread`）。
如果故障是那個佇列在第 N 幀放掉某個東西造成的，**故障幀數應該大致固定**，而它差了 308 幀。
所以在這個啟動期重現裡，**幀計數的延後釋放不是觸發者**。
（這和先前撤回「只有 `Later()` 會移動當掉時機」是一致的：那條撤回是因為沒有同執行檔的對照，
現在這條是正面證據，方向相同。）

**連帶修正一個我先前算錯的前提**：我曾用「讀卡器 165 FPS，所以 240 幀＝1.45 秒」去推論佇列的時間尺度。
**那是穩態幀率**，而這三趟顯示啟動期的幀率低且變動極大（同樣約 25 秒內跑了 212 到 520 幀，差 2.5 倍）。
所以凡是「幀數 ÷ 165」得到的秒數，在啟動期都不成立。

**照 11b／11c 標註**：n=3，只印原始值與全距，不報中位數；那兩個全距都**不是**分辨率。
三趟指向同一個方向（幀數抖得遠大於秒數）算乾淨，但要六趟才算數。

## 附則 7g 的範圍（協調者擴充）：**讀取狀態的腳本也會把「不存在」說成「空」**

> 不只量具的輸出要區分「沒量到」與「量到 0」——`cat` 一個不存在的檔、`grep` 一個不存在的 log、
> `ls` 一個不存在的目錄，預設都會給你一個看起來像「空」的答案。

協調者自己踩到的實例：它的巡檢腳本寫 `[ -s "$f" ] && cat "$f" || echo "(empty)"`，
而仲裁者只有 **2** 個 slot，於是不存在的 `slot3/owner.txt` 被印成「(empty)」——
**「檔案不存在」和「槽位空著」變成同一個字串**，結果它叫 f-yvonne 去搶一個不存在的 slot3。

照這條回頭查自己的腳本：`stoptrip.sh` 開頭就是 `[ -f "$T" ] || { echo "no such table"; exit 2; }`（分得開）；
`faultsecs.py` 對開不了的檔印 `cannot read log: <原因>`，和 `NO_FAULT` 是不同字串（分得開）；
`knob1x.sh` 的 `grep -ca ... "$LOG"` 作用在它自己剛建立的 log 上，不存在時會是 0 而不是靜默——
**這一個是靠「那個檔一定存在」撐著的，不是靠檢查**，所以記在這裡當已知弱點。

## 附則 7j（協調者編號）：量具要申報自己的覆蓋率

> 不是「它會不會動」（第 7 條），也不是「它動得夠不夠細」（第 11 條），
> 而是**它實際看了多少、應該看多少**——用 `N / M` 寫出來。
> **覆蓋率沒申報的量具，它的陰性結果不能當證據**；
> 一個靠「剛好有個檔在範圍內」而成立的量具，是靠運氣而不是靠設計。

## 把 7j 套在自己身上，又找到一個洞：**我的身分指紋只蓋執行檔，卻把它當成「趟」**

`BUILDPATHS` 是「會不會改到**執行檔**」的集合。但有一整類東西**不改執行檔的任何一個位元組、卻會改讀卡器的行為**：

| 檔 | 影響 |
|---|---|
| `Config/DefaultEngine.ini` | cvar 預設、RHI 設定 |
| `Config/DefaultDreamGUI.ini` | DreamGUI 自己的設定 |
| `Config/DefaultGame.ini` | 遊戲根目錄等 |
| `Config/ReaderEditor/pages.json` | **讀卡器的 UI 頁面定義**，而且今天**別組才剛提交過它** |

所以改成兩個集合，刻意分開：

- **`BUILDPATHS`**：會改到**執行檔**的。**patch 存檔**與**和 e-fork-2 可比的那個雜湊**只用這一組——
  後者只有在兩組算同一組路徑時才有意義。
- **`IDPATHS` = `BUILDPATHS` + `Config`**：會改到**一趟**的。身分雜湊用這一組。

`fp-rule-4`：身分涵蓋 `Config`。目前兩個雜湊值相同（`Config` 現在是乾淨的），**這正是它該有的樣子**——
有人動 `Config` 時它們才會分開。

### 覆蓋率申報（每格的表頭都會印）

```
coverage base_v1=140388/140959 (work/ 571 excluded by fp-rule-4)
coverage cards=31/31  identity_paths=7035 tracked=7035 untracked=0
```

## 成本量測也會被污染（這是那個覆蓋率錯誤的根因）

> **在別人跑重 IO／重 CPU 時量出來的「這個操作太貴」，不能直接拿來做設計決定。**
> 機器安靜時重量一次，往往就不需要那個為了省錢而加的複雜度。

那 94 秒是**在補錄正在寫 `work/`、冷快取下**量的；暖快取只要 6 秒。
「太貴，必須拆成淺層／深層」這個設計決定，建立在一個**受污染的成本量測**上，
而代價正好是：為了省 94 秒而拆出來的淺層，漏掉 99.98%。

## 「逐趟取」不是改主意，是**前提變了**

我先前主張資料指紋「一格取一次」，依據是「樹在這六趟之間不會變，因為 e-fork-2 同意不建置」。
**那個前提現在不成立**：補錄正在改基礎庫，我自己也看到 `sources.okidx` 在 16:54:36 又動了一次。
所以改成**逐趟取**，而且六趟的 `fp-rule-4` 值**不全相同就整組作廢**。
（寫清楚這層關係，免得後人看到兩個相反的決定而不知道哪個對：**前提沒變時一格一次，前提會變時逐趟。**）

### 把「幀數 ÷ 165」支撐過的每一句話找出來（協調者要求的清查）

一個依據被推翻時，要回去找它支撐過的每一句話。清查結果如下，**而且結論比我上一節寫的更窄**：

| 文件處 | 那句話 | 它講的是哪個重現 | 判定 |
|---|---|---|---|
| 「讀卡器 165.5 FPS（35,704 幀／215.7 秒）」 | 幀率的來源 | **開卡**（走 30 張卡、跑了 215.7 秒的那種趟） | **成立**——它就是在那種趟上量的 |
| 「240 幀 = 1.45 秒」「沒有任何待跑的命令清單能撐 1.45 秒」 | 延後釋放的時間尺度 | 開卡 | **成立**（在開卡那個重現裡） |
| 「240 幀（1.45 秒）只是把扣扳機的那一下推遠」 | `DelayFrames=240` 的讀法 | 開卡 | **成立**，但那一格本來就另有問題（沒有同執行檔的基線對照），那是另一回事 |
| 「100 幀 = 0.6 秒，所以那三個 0 沒有排除任何東西」 | `TrackedReleasedAllocationFrameRetention` 的視窗 | 開卡（故障發生在第 4／第 7 張之後，已進入穩態） | **成立**（約略） |
| **任何把這個換算套到啟動期零張卡那個重現上的推論** | — | **啟動期** | **不成立**：同樣約 25 秒內跑了 212 到 520 幀，差 2.5 倍 |

**所以正確的修正是「分重現」而不是「全部作廢」**：165 FPS 是在**開卡**那種趟上量出來的平均值，
在那個重現裡用它換算是合理的；**啟動期不能用**，因為那段的幀率低且變動 2.5 倍。
我上一節寫「凡是幀數 ÷ 165 得到的秒數在啟動期都不成立」——範圍是對的，
但沒有把「開卡那邊仍然成立」講出來，等於讓讀者以為整個換算都廢了。這裡補上。

**另外標一個沒人提過、但這次清查才看到的限制**：那個 165.5 FPS 是**單一一趟**的平均
（35,704 幀 ÷ 215.7 秒），**n=1**。照附則 11b，n < 3 不報集中趨勢量——
所以它只能當「那一趟的平均」，不能當「讀卡器的幀率」。要當常數用，得有至少三趟。

### 措辭照第 10 條收窄（幀數那條）

**允許**：「**在這個啟動期零張卡的重現裡**，以幀計數的延後釋放不是觸發者。」
**不得**寫成「`Frames.*` 已排除」或「延後釋放和當機無關」。

理由：排除的是**啟動期那個重現**的觸發者。**開卡那個重現（跑幾張卡之後死）是另一個重現**，
而且是使用者真正會遇到的那個——它那裡的幀數行為**完全沒量過**。

### B 段後的基礎庫身分：**我自己量的和 e-fork-2 報的逐項相同**

| 項目 | e-fork-2 報的 | 我自己量的 |
|---|---|---|
| `sources.okidx` | size 1077443567 / 16:54:36 | size **1077443567** / **16:54:36.288** |
| `converted.tsv` | size 7557062 / 16:54:21 | size **7557062** / **16:54:21.695** |
| `models` | 4543 個檔 | **4543** |
| `shared_mods.txt` | size 2799 / 11-04 | size **2799** / **11-04 10:59:22** |
| `catalog.json` | 沒有這個檔 | **不存在** |

我的 `fp-rule-4` 值：`base_v1=8e31a6552bb6af42`，`work/` 571 個檔（已排除）。
**兩邊獨立算出同一組數字**，所以這組身分可以綁。

### 尺 1 的分類規則（**在六趟結果出來之前**登記，第 1 趟還在跑時寫的）

第 1 趟**走過了啟動期**，正在開卡（開到第 5 張時寫下這段）。
B1／B2 在**同一個旋鈕**下是在啟動期約 25 秒就死的。所以同一個設定底下至少有兩種結局，
而「秒數」在這兩種結局裡**不是同一個量**：

| 結局 | 秒數在量什麼 | 可否和 B1／B2 的 25 秒比 |
|---|---|---|
| 啟動期當掉（零張卡） | 從行程啟動到故障 | **可以** |
| 開卡途中當掉 | 啟動 + 開了幾張卡的時間 | **不可以**——多了一段由卡數決定的時間 |
| 跑完 30 張存活 | 沒有故障時間 | 設限觀測（censored） |

**所以六趟要先按「死在哪裡」分類，再談分布，不能把秒數倒進同一個分布。**
這條是在看到任何一趟的秒數之前寫的——等數字出來再決定怎麼分類，就是挑對自己有利的切法。

**對照預先登記的判讀**：原本寫的是「6/6 當 ⇒ 這把尺成立；任一趟存活 ⇒ 不可判」。
第 1 趟既然已經走過啟動期，**「啟動期 25 秒」那個重現就已經不是 6/6 了**（n=1 就足以否證全稱句）。
這不改判讀，只是提早知道結果會落在哪一邊；六趟仍要跑完，因為要的是比率不是存在性。

## 附則 10c（協調者編號）：撤回要和原主張一樣精確地劃範圍

> 一個依據被推翻時，只作廢**依賴那個依據的那些結論**，不是作廢所有提過它的句子。
> **過度撤回和過度主張一樣，都是把範圍講錯**，而且它會丟掉仍然成立的結果。

今天撤回很多，所以這條有實際風險。上一節那張表（三句對開卡仍成立、只有套到啟動期的不成立）
就是正確的粒度；我原先寫的「凡是幀數 ÷ 165 在啟動期都不成立」範圍對，但漏講「開卡那邊仍成立」。

### 但那三句「仍然成立」要照 11b 標上它的地基

165.5 FPS 是**單一一趟**的平均（35,704 ÷ 215.7），**n=1**。所以：

> 「240 幀 = 1.45 秒」「100 幀 = 0.6 秒」這幾句**在開卡那個重現裡仍然成立，
> 但它們的依據是一個 n=1 的幀率估計，成立的程度不會高於那個估計。**

要變硬需要幾趟開卡的幀率；**現在不為此跑趟數**，只標註。

## 尺 1 的三種結局，動作現在寫死（協調者的事前登記）

| 結局 | 判定 | 後續動作 |
|---|---|---|
| **A** 6/6 全當、全距窄 | 尺成立 | 分辨率 = 六趟全距（n=6 才能這樣寫）。機制格依序：`NeverDeleteProxy` → `gclrun` → retention／名字格；每格照 7j 申報覆蓋率、照 7 申報陽性樣本、照 10 四分類寫結論、照 10a 只有第 3 種能寫成排除 |
| **B** 6/6 全當、全距寬 | 尺可用但鈍 | 分辨率就是那個寬度，每個機制格的結論都要帶「這把尺只能偵測到 X 秒以上的移動」。**不因為它比卡數那把好就當它銳** |
| **C** 不是 6/6 | 不可判 | 三個機制格都沒有可用的尺，**整條線停下來重新設計量測**。出路只有兩條：(1) 換一個更早、更確定的觀察量（故障前確定性的前驅：固定 log 里程碑、某計數到達某值）；(2) 換配方找 6/6 全當的組態——但那要先付搜尋成本，只有第 1 條走不通才做 |

**三種結局都不包含「挑趟」「補趟到好看」「把某趟歸因為機器忙而剔除」。**
要剔除一趟，理由必須**獨立於結果**（`fp-rule-4` 不同、當時板子上有別人），
而且要在看數字之前就能判定。

### 這組登記和我自己那條分類規則的交互（**必須先講，否則 A／B 會被誤用**）

A 和 B 都在講「六趟全距」，那預設**六個秒數是同一個分布**。
但我在看數字之前已經登記（`bbcaeedbc`）：**秒數在不同結局裡不是同一個量**。
第 1 趟證實了這不是空談——它**faulted 在開卡途中（94.3 秒、第 5 張卡後）**，
不是 B1／B2 那種啟動期約 25 秒。這兩個數字放進同一個全距是沒有意義的。

所以 A／B／C 要這樣讀：

- **先分類**（啟動期當／開卡途中當／跑完存活），**再在同一類裡面談全距**；
- 「6/6 全當」指的是**六趟都故障**（不論死在哪裡）——這是原本登記的字面意思，不改；
- 但**只有同一類裡的趟數才能算全距**，所以若六趟分散在兩類，
  每一類的 n 都 < 6，照 11c **就還不能談分辨率**，結論會是 B 或 C 而不是 A。

這一段是在六趟還沒跑完時寫的，寫下來正是為了不讓將來的自己按結果挑讀法。

## 分類欄位要用 `entered`／`returned`，不能用「故障卡號」——把規則套在 B 段上就露餡

修補條款說分類依據是客觀的「有沒有逐卡行、故障卡號」。**把它套在 B 段那三趟上，
會把其中兩趟分錯類**，所以先把欄位定死再分類：

| 趟 | 執行檔 | `entered`／`returned` | 驅動寫的行 | 正確類別 |
|---|---|---|---|---|
| `bg_B1_1` | 11-19_15:05 | **0／0** | `STOP at card 1 … unreal=0` | **啟動期** |
| `bg_B1_2` | 11-19_15:05 | **0／0** | `STOP at card 1 … unreal=0` | **啟動期** |
| `bg_B2_1` | 11-19_15:05 | **0** | （沒有 STOP／DEAD 行） | **啟動期** |
| `trans6_1` | 11-19_16:25 | **1／1**、6 條逐卡行 | `DEAD after card 6` | **開卡期** |

B1 那兩趟的 `STOP at card 1` **不代表開過第 1 張卡**。錯誤訊息自己講明白了：
`not_ready: game pid … has no card reader mailbox yet (still starting)`，而且 `unreal=0`——
**行程在讀卡器信箱還沒開起來之前就已經沒了**。那個「card 1」只是迴圈的計數，
是驅動的標籤，不是觀測。照「故障卡號」分類就會把兩趟啟動期故障算進開卡期。

**所以分類欄位定為 `entered`／`returned`（讀卡器實際開過幾張卡），不是迴圈計數。**
`entered=0` ⇒ 啟動期；`entered≥1` 且有逐卡行 ⇒ 開卡期（故障卡號取最後一條逐卡行的號碼）。

### 這個檢查的結論是**支持**協調者的說法，不是推翻

我原本懷疑「n=3 其實是 1 趟啟動期 + 2 趟第 1 張卡」。**查下去不是**：三趟都是 `entered=0`，
**啟動期 n=3 成立**。三趟也都在**同一個舊執行檔 11-19_15:05** 上（我自己逐檔查的 `# build:` 行），
所以「n=3、單一執行檔」這個脆弱性描述準確。

順帶記一個不解釋的觀察（照 10b 不替消失的現象找機制）：B1 那兩趟的旋鈕是
`DreamGUI.Experiment.NoBackdrop=1`、B2_1 是 `=2`，**都不是 `r.RDG.TransientAllocator=0`**。
所以「啟動期約 25 秒」那三趟和現在尺 1 的組態**連旋鈕都不同**。
這讓「啟動期重現在新組態消失了」更不值得解釋——它本來就不是同一個組態下的東西。

### 附則 7k 的第三個實例：分類用了旁邊最容易讀的欄位

> 量一件事要用**那件事自己的證據**，不是用它旁邊最容易讀到的欄位。

| 實例 | 旁邊好讀的欄位 | 那件事自己的證據 |
|---|---|---|
| `grep` 壓縮位元組 | 壓縮後的位元組數 | 解壓後的內容 |
| f-sceneload 的 `scaled>0` | 有沒有縮放值 | shader 真的收到了 |
| **這次：故障分類** | **`STOP at card N` 的卡號** | **`entered`／`returned`（讀卡器真的開過卡沒有）** |

協調者不給新號，理由是規則編號也會通膨（今天已從第 6 條長到 13b），
**一條規則配三個具體實例比三個新號有用**。往後先問既有規則蓋不蓋得住。

### 照 7g 修掉來源：`STOP at card 1` 在沒開過卡時印出一個確定的卡號

這個欄位在我自己的量測腳本裡（`knob1x.sh`／`loopx.sh`，不在 `Tools/` 也不在 `IDPATHS`），
**不動指紋**，所以現在就改，不必等窗口。改成：

```
STOP card=none (crowd_C001.png) reader_started=0 (never returned to gallery) ...
```

**自測（照第 7 條，陽性與陰性各一）**：
- 陰性 `20261119-154052`（B1_1，信箱沒開就死）→ `0`
- 陽性 `20261119-170615`（尺 1 第 1 趟）→ `1`

**而且自測當場抓到我差點犯下我正在修的那個錯**：
第 1 趟開了 **6 張**卡，這個計數卻是 **1**——`returned to gallery` 一個 session 只印一次，
**它不是卡數**。我原本把欄位叫 `opened=`，那就是又一次「用旁邊的欄位冒充那件事」。
已改名為 `reader_started=` / `returned_to_gallery=`，名字只講它實際量到的東西。

### `late shader associations` 的耗時在兩趟之間差 63 倍，這正好是它**在故障之後**的旁證

| 趟 | 秒數 | 故障卡 | `Created late shader associations` |
|---|---|---|---|
| 1 | 94.3 | 第 5 張後 | **16 ms** |
| 2 | 86.9 | 第 5 張後 | **1012 ms** |

兩趟都當、簽名相同，這個欄位卻差 63 倍。先前已從程式碼確認它來自
**Aftermath 當機傾印的解碼器**（`RHICoreNvidiaAftermath.cpp:848-857`，註解寫著 `// Allow association after a fault`），
那 ~1008 ms 是 `CreateShaderAssociations` 裡寫死的 1 秒逾時（`D3D12NvidiaExtensions.cpp:62`）。
**這兩趟的數字和那個解釋一致**：它量的是解碼器等了多久，不是故障前發生了什麼。

所以這一條**不是新發現，是把一個已經靠讀原始碼定性的結論，補上行為上的證據**：
1012 ms 那趟等滿了逾時，16 ms 那趟沒等到就拿到了。**兩者都在故障之後。**

**明確堵住一個誘人的讀法**：不可以寫成「1008 ms 是前兆」或「它和故障有關」——
第 1 趟只有 16 ms 照樣當。這個欄位在尺 1 裡**沒有判別力**，往後的機制格不要拿它當指標。

## 故障卡是第 **6** 張（`crowd_C049.png`），不是第 5 張——而且趟 1 的第 6 行不是一次成功開卡

協調者依我的回報把兩趟記成「都在第 5 張之後」，**這是我上一封講得不夠精確造成的**。原始資料：

| 趟 | 逐卡行數 | 最後一行 | 驅動的結束行 |
|---|---:|---|---|
| 1 | **6** | `6 actors=0 tex=0 trans2d=0 lsa=2` | `DEAD after card 6 (crowd_C049.png)` |
| 2 | **5** | `5 actors=5 tex=337 trans2d=218` | `FAULTED after card 6 (crowd_C049.png)` |

**兩趟指的是同一張卡：第 6 張 `crowd_C049.png`。** 行數差 1 的原因不是故障位置不同，而是：

> **趟 1 的第 6 行整排是 0**（`actors=0 tex=0 trans2d=0`）。那不是「開了一張空卡」，
> 是**對一個已經故障的引擎做探測**，探測回不了東西就印成 0。
> **又一次把量不到印成一個確定的值**（7g／7k 家族，這次在我自己的驅動裡）。

趟 2 沒有這一行，因為它跑的是加了故障檢查的驅動：偵測到故障就直接收尾，不再探測。
**趟 3–6 也都不會再有這種零值行。** 趟 1 的那一行是舊版驅動的遺留，判讀時**不得計入開卡數**。

### 卡號欄位的定義（照 7k：用那件事自己的證據）

> **故障卡號 = `FAULTED`／`DEAD` 行裡那張卡**（故障當下在手上的那張），
> **不是逐卡行的行數**——兩者在趟 1、趟 2 之間差 1，差的純粹是那排零值。

照這個定義：**趟 1 = 第 6 張，趟 2 = 第 6 張，全距 0。**
協調者「卡號散布為 0」的結論**成立**，只是卡號是 6 不是 5。

### 兩個只記不解釋的觀察

- 兩趟的**第 5 張**數字完全一樣（`actors=5 tex=337 trans2d=218`）；
- 但**第 4 張**不一樣（趟 1 `tex=258 trans2d=139`，趟 2 `tex=562 trans2d=436`）。

所以「逐卡狀態完全決定性」**不成立**，不要用這兩趟去推它。等六趟跑完再看這兩欄。

## 我自己在這把尺上製造了沒記錄的負載（而我正是因為這個理由叫自己別去查 C049）

協調者的理由是：趟 3 正在跑，任何磁碟／CPU 活動都進那把尺的噪聲。**那個理由同樣適用於我一直在做的事**——
我在六趟進行中持續寫文件並提交。逐趟對照：

| 趟 | 秒數 | 該趟進行中我的提交次數 |
|---|---:|---:|
| 1 | 94.3 | **2**（17:11:53、17:12:09） |
| 2 | 86.9 | **3**（17:15:16、17:17:55、17:20:14） |
| 3 | 進行中 | **2**（17:21:32、17:23:35） |

**每一趟都有。** 而秒數那 8% 的散布，先前被登記為「若六趟都死在 C049，就只剩機器狀態可以解釋」——
**機器狀態的一部分是我自己造成的，而且沒有記錄在任何地方。**

### 我**不**改這個做法，理由是改了更糟

直覺上該立刻停止提交。但那會讓趟 1–3（有提交）和趟 4–6（無提交）**成為兩種條件**，
而六趟要當一個分布來讀。**中途改條件正是讓一組資料作廢的典型做法**，
比「條件不理想但一致」更糟。所以：**維持現狀到六趟結束**，但把次數逐趟記下來，
並在報告裡明講這把尺的秒數欄位**帶有未量化的自製負載**。

### 不假裝知道它多大

提交一個文字檔的 IO 和開一張卡比起來「應該很小」——**但我今天已經犯過一次
把猜測講成量測**（那個「每趟浪費 13 分鐘」）。所以這裡只寫：
**影響未量化，方向未知**（趟 2 提交較多反而較快，n=2 看不出方向）。
要量它得另開一格，而那一格現在不值得花機器時間。

### 這也是 `loadstate.sh` 那一格的前置為什麼要存在

我寫那個記錄器時想的是「別組在跑什麼」，**沒想到要記自己**。
已在該檔補一行註記：負載來源包含執行量測的這個 session 自己。

## 協變量要取「故障**之前**的提交」，取「該趟進行中的提交」會算錯——而且改對之後方向相反

協調者提議把秒數對「該趟進行中的提交次數」並排。**那個欄位不對**：
秒數量的是**行程啟動到故障**那一段，**故障之後發生的事不可能影響它**。
而驅動在故障後還要收尾（探測、收掉卡死的引擎、寫表），那段時間我照樣在提交。

逐趟對齊（故障時刻取 log 裡 Aftermath 那行，UTC+8）：

| 趟 | 起 | 故障 | 秒數 | 該趟進行中提交 | **故障前提交** |
|---|---|---|---:|---:|---:|
| 1 | 17:06:15 | **17:07:52** | 94.3 | 2（17:11:53、17:12:09） | **0**（兩次都在故障後） |
| 2 | 17:13:59 | **17:15:26** | 86.9 | 3（17:15:16、17:17:55、17:20:14） | **1**（17:15:16，故障前 10 秒） |

**所以「每趟 2～3 次」那張表是對的但不相關**；正確的協變量是 **0 和 1**。

### 而且改對之後，方向和直覺相反

趟 1 **0 次**前置負載 → **94.3 秒**；趟 2 **1 次** → **86.9 秒**。
**負載較多的那趟反而較快。** n=2，什麼都證明不了，但它足以說明一件事：
**如果我用「進行中提交次數」（2 vs 3）去做那個檢查，會得到一個同樣單調、同樣好看、
但建立在不可能有因果的欄位上的相關。** 這正是 7k：用旁邊好讀的欄位，不是那件事自己的證據。

### 事前登記（在看到趟 4–6 之前）

- 協變量 = **該趟故障時刻之前**我的提交次數（以及協調者提供的巡檢次數，同樣只取故障前）；
- 六趟跑完後並排列出，**若秒數隨故障前負載單調上升且幅度涵蓋那 8%** ⇒ 歸因於量測者自身活動，
  紀錄寫明「秒數受量測者自身活動污染，卡號不受影響」；
- **否則照實寫「散布來源未知」，不找第二個解釋**；
- n=6 很弱，這個檢查只能支持或不支持，**不能證明**。

協調者那邊的處置（獨占 claim 期間只 `cat` slot 檔、不跑行程枚舉）收下；
請一併提供**各趟故障時刻之前**的巡檢次數，時間軸用上表的故障時刻。

### 程序原則（協調者的，記下來）

> **實驗進行中改變程序，會把一組趟變成兩種條件。**
> 一個已知但恆定的干擾，好過一個在中途改變的干擾——前者可以被解釋或抵銷，後者讓前後兩半不可比。

補一句：**我的干擾不是恆定的（0、1、…），是逐趟變動的協變量**，不是常數。
差別在於它現在有記錄、而且登記了怎麼用。

## 趟 3 推翻了「啟動期重現在新組態上沒出現」——它只是不是每趟都出現

趟 3：`entered=0 returned=0`、**25.3 秒**、簽名相同（`MainPS`）、零張卡。**這是啟動期故障。**

| 趟 | 類別 | 秒數 | 卡 |
|---|---|---:|---|
| 1 | 開卡期 | 94.3 | `crowd_C049.png`（第 6 張） |
| 2 | 開卡期 | 86.9 | `crowd_C049.png`（第 6 張） |
| **3** | **啟動期** | **25.3** | **零張** |

### 兩個直接後果

**一、尺 1 照修補條款是結局 C。** 六趟分散兩類 ⇒ 尺 1 不可判，不能當機制格的尺。
（三個機制格 `NeverDeleteProxy`／`gclrun`／retention 因此都還沒有可用的尺。）

**二、先前那整串「新組態 vs 舊組態有差別」的推論，前提沒了。**
協調者原本要把主線移回開卡期、把啟動期降級成「偶發、組態相關、待確認」，
依據是「舊組態三趟全是啟動期，新組態前兩趟都進到第 4／第 5 張」。
**趟 3 顯示那個差別是抽樣造成的**：新組態一樣會啟動期故障。
「偶發」這個詞是對的，「組態相關」沒有證據。

### 25.3 秒這個數字跨越三種旋鈕設定

| 組 | 旋鈕 | 執行檔 | 秒數 |
|---|---|---|---|
| B1 | `DreamGUI.Experiment.NoBackdrop=1` | 15:05 | 25.4、25.0 |
| B2 | `DreamGUI.Experiment.NoBackdrop=2` | 15:05 | 25.3 |
| **尺 1 趟 3** | **`r.RDG.TransientAllocator=0`** | **16:25** | **25.3** |

**四趟、三種旋鈕、兩個執行檔，秒數 25.0–25.4（全距 0.4 秒）。**
照 10a 這只能寫成第 3 類（這些旋鈕都沒有移動它），**不能寫成機制**。
而先前那個「0.4 秒的地板」正是這個數字——現在它多了一趟、跨到新執行檔，仍在同一個 0.4 秒內。

### 驅動又補一個同樣的洞（收尾，不動量測）

啟動期等待迴圈和先前的開卡迴圈有**同一個盲點**：故障不會結束行程，
`alive_engine()` 對卡在 crash reporter 裡的引擎回傳 true，於是它會一路問到 900 秒上限。
趟 3 就這樣卡了約 7 分鐘。已補上「log 裡有故障且信箱不回應 ⇒ 收掉」。
**趟 1–3 和趟 4–6 的收尾路徑因此不同，但量到的東西（log 裡的故障時刻）相同。**

## 二元尺（「會不會死」）：接受，但有三處要先改，否則它會比舊尺更容易給出錯的綠燈

這把尺迴避了今天所有的麻煩（混合分布、截斷、秒數散布、自製負載都不影響它），
解析度粗也是已知代價。**但有三件事必須在它變成門檻之前定死。**

### 一、基線**不能**用尺 1 那六趟——那是個使用者不會跑的組態

尺 1 的旋鈕是 `r.RDG.TransientAllocator=0`。這在 `trans6run.sh` 開頭就寫明：
**「TransientAllocator=0 不是使用者會跑的組態，所以這把尺不得成為修法的驗收門檻」**。
拿它那六趟當二元尺的基線，等於把那個旋鈕**偷渡進協定**，
往後每一格機制格都在一個非預設組態上驗收。

> **二元尺的基線要用預設組態自己跑六趟**（這正是尺 2 `loopx` 原本的用途）。
> 尺 1 那三趟（3/3 故障）可以當**旁證**，**不能當基線率**。

### 二、截斷**會**影響它——這正是卡數那把尺被判死的理由之一

「30 張內沒死就是沒死」不成立：**一個只把故障從第 6 張推到第 35 張的修法，會讀成 0/6 = 修好了。**
今天稍早卡數那把尺就是栽在這個 30 張天花板上（「30+」是設限觀測）。

> **任何讀到 0/6 的格子，必須在無天花板的協定（`loopx`）上重跑才能叫修好。**
> 0/6 在 30 張協定下只代表「在 30 張內沒死」，不代表「不死」。

### 三、它看不見「只修好一類」的修法——這要事前登記成次要讀數

兩類都算「死」，所以一個**消掉啟動期故障、但開卡期照死**的修法會讀成 6/6＝無效。
那其實是個有效的修法，只是不完整。

> **次要讀數（事前登記，不是事後去挖）**：每格除了 `故障趟數/總趟數`，一併報**兩類各自的 n**。
> 若二元結果不變（仍 6/6）但**類別組成明顯移動**（例如基線 2 啟動/4 開卡 → 該格 0 啟動/6 開卡），
> 紀錄寫成「二元無效，但類別組成移動，值得單獨追」——**不得**因此宣告部分有效，
> 因為 n=6 下的類別比例本來就抖（基線自己前三趟就是 1 啟動/2 開卡）。

### 其餘照收

- 結局 C 不討價還價，尺 1 不可判；
- 「兩個組態之間確實有差別」撤回（同一組態內就會出現兩類）；
- 「開卡期是一直都重現的那個」同樣是抽樣造成的印象，一併收窄；
- 25.3 秒跨三旋鈕兩執行檔、全距 0.4 秒，是目前最像線索的東西；
- C049 三候選降級到二元尺之後。

## 附則 13c（協調者編號）：正在執行的腳本也算「在飛的東西」

> bash **以位元組位移讀檔**，中途編輯會讓它跳行或回頭重跑一段——而且**不會報錯**，
> 只會在輸出裡留下像「表格出現兩份 `build` 標頭」這種看起來像小毛病的痕跡。
> 要改就複製一份改，或等它跑完。

和 13a（存個檔就足以改變指紋）同一家族：
**「我只是編輯一下，又沒提交／又沒重啟」在共用工作樹與執行中的程序上都不成立。**

## 趟 3 標記：程序受擾（procedure perturbed）

| | 趟 1 | 趟 2 | **趟 3** |
|---|---|---|---|
| 類別 | 開卡期 | 開卡期 | **啟動期** |
| 秒數 | 94.3 | 86.9 | **25.3** |
| 程序 | 完整 | 完整 | **中途被改，有一段重跑** |

**在任何牽涉秒數的比較裡，趟 3 都要標成程序受擾。**
對二元尺（有沒有故障）影響不大——故障時刻從 log 讀、`entered=0` 明確——
但照我自己立的「實驗進行中改變程序會變成兩種條件」，**標記是義務，不是看結果好壞決定**。
**受損與否是讀者該自己判斷的事**，不是我先替他們判斷完再決定要不要講。

## 尺 1 的結果定位（協調者裁定）

趟 4–6 照跑完，但這六趟的故障率標明是 **`r.RDG.TransientAllocator=0` 組態的基線率**，
**不是協定基線**，**不得當成任何修法的驗收門檻**。那個組態自己的故障率仍是一個有用的數字。

排程：六趟 → `release`（f-sceneload 的 Q1 先跑，它等很久而且分段）
→ Q1 之後再跑**預設組態六趟**的二元基線，那才是協定基線，機制格全部掛在它後面。

## 20 分鐘上限的例外（協調者批准本次超時），以及它的理由**比事實強**的那一部分

> **不可分割的量測組（同一組要互比的趟）不受 20 分鐘上限切割**，但必須：
> (a) 事先說明這一組要跑幾趟、估多久；(b) 跑完立刻 `release`，不接著做別的；
> (c) 佇列上有人時不得在同一次 claim 裡追加新的格子。

(a) 已在 claim 訊息寫「6 short trips」；(b)(c) 照辦——**六趟一跑完就 `release`**，
第 2、3 點的裁定與預設組態六趟都等 Q1 之後。

### 但這個理由要照 10c 收窄：這六趟**已經不是同質的**

批准的理由是「中間插進 Q1 會讓趟 1–3 和趟 4–6 隔著完全不同的機器狀態，六趟變成兩組 n=3」。
**那個擔心是對的，但它要防的事已經部分發生了**：

| | 趟 1 | 趟 2 | 趟 3 | 趟 4–6 |
|---|---|---|---|---|
| 收尾路徑 | 舊（無故障檢查） | 開卡迴圈有檢查 | **程序受擾（中途被改、重跑一段）** | 開卡＋啟動迴圈都有檢查 |
| 自製負載（故障前提交） | 0 | 1 | 待算 | 待算 |

所以**正確的說法不是「不切割就保持同質」，而是「切割會再加一個更大的不同質來源」**。
前者是我和協調者都想要的結論，後者才是事實。**跑完六趟仍然是對的決定**
（多一個干擾比多兩個好，而且 Q1 那種重 IO 的干擾量級明顯更大），
但不要把它寫成「這六趟條件一致」。

這也是為什麼二元尺（有沒有死）在這堆爛條件下反而是最穩的讀法：
**上面每一項干擾都影響秒數，沒有一項明顯會把「死」變成「不死」。**

## 旋鈕實驗前置清單（第 7 條的操作化，F 組查到環境變數蓋過 cvar 之後）

f-sceneload 發現 `OK_STUDIO_FIND_INDEX=0` 這個**環境變數會蓋過同名 cvar**：
環境裡殘留一個，整格就跑在它以為自己關掉的那條路上，**兩種設定看起來一模一樣**，
結論會是「這個旋鈕沒有效果」——**而且沒有任何跡象**。那正是我最怕的那種結果：
一個看起來乾淨的「沒效果」。

> 1. **列出所有能設定這個旋鈕的輸入**——cvar、環境變數、`Default*.ini`、命令列、
>    程式裡的預設與硬寫死值——每一個都控制或記錄。**贏的那個往往不是你設的那個。**
> 2. **在機制作用的那一點找到達證據**，不是 setter 那一點。
> 3. **事前寫下預測，包含方向與量級。**

### 第 1 項對 cvar 已經有一半的自動解：`LastSetBy`

我每趟都印旋鈕讀回值，而 UE 的讀回值**自己就說了是誰贏的**：

```
# knob now: r.RDG.TransientAllocator = "0"   LastSetBy: SystemSettingsIni
```

`SystemSettingsIni` 正是我用 `-ini:Engine:[ConsoleVariables]:` 送進去的那條路。
**所以對「有好幾個來源都在寫同一個 cvar」這種情況，`LastSetBy` 直接給出答案**，
不必去逐一排查 ini／命令列／程式預設——**只要把 `LastSetBy` 記進表頭就夠了**（已經在記）。

### 但 `LastSetBy` **蓋不住 F 組那一類**，殘差風險要講清楚

`LastSetBy` 只在**值是經由 cvar 系統設定**時才有意義。兩種情況它看不見：

1. **環境變數被程式直接讀取**（`getenv`／`FPlatformMisc::GetEnvironmentVariable`），
   完全繞過 cvar 系統——**cvar 讀回值會顯示我設的值，而程式用的是別的值**。f-sceneload 那個就是這類。
2. **程式在某處讀了自己的欄位／常數而不是 cvar**，或把 cvar 的值快取在啟動時。

**所以三格的前置各加一步（純讀碼，零機器時間，排在 `release` 與 Q1 之後、跑格子之前）**：

| 格 | 旋鈕 | 要查的殘差來源 |
|---|---|---|
| `NeverDeleteProxy` | `DreamGUI.*` | `Config/DefaultDreamGUI.ini` 有沒有這個 key（**它已在 `IDPATHS` 裡，正因為它能蓋過 cvar**）；有沒有同名環境變數被直接讀 |
| `gclrun` | `RHI.TransientAllocator.GarbageCollectLatency` | 引擎端有沒有在啟動時快取這個值；`Default*.ini` 有沒有設 |
| retention／名字 | `DreamGUI.*` retention | 同 `NeverDeleteProxy`，另查該值是否在物件建構時取樣一次 |

查法：對每個旋鈕名在 `Source/`、`Plugins/`、`Config/` 各搜一次，並搜 `GetEnvironmentVariable`／`getenv`
附近有沒有同名字串。**完全不用機器**，而且它能救的正是那種看起來乾淨的「沒效果」。

第 2 項我已有範例（`1008 → 11 ms` 之於 `EnableAsyncCacheConsolidation`、`Note()` 到達次數之於 `Frames.Pooled`）；
第 3 項也做過（`1008 → 11` 就是事前預測）。**三格真正缺的就是第 1 項。**

## 7k 第五個實例，而且這個是**結構上不可能準**，不只是不準

我用「讀卡器信箱不回應」當作「引擎卡死」的判據。`OKControl` 是**獨立執行緒**
（AGENTS.md：socket 與信箱在獨立執行緒，所有模式啟動就開著），
**算繪裝置死了它照樣回應**，所以那個條件永遠不成立，趟 4 會一路等到 900 秒上限。

| 實例 | 問了什麼 | 該問什麼 |
|---|---|---|
| `grep` 壓縮位元組 | 壓縮後的位元組 | 解壓後的內容 |
| `scaled>0`（f-sceneload） | 有沒有縮放值 | shader 真的收到了 |
| `STOP at card 1` | 迴圈計數 | `entered`／`returned` |
| `opened=`（我自己自測時抓到） | `returned to gallery` 次數 | 實際開卡數 |
| **信箱回不回應** | **一個設計上就獨立於故障源的執行緒** | **算繪裝置還活著沒有** |

前四個是「問了旁邊的東西，剛好不準」；**這一個是問了一個設計上就不會隨故障改變的東西，
所以它不是不準，是結構上不可能準**——再怎麼調逾時、再問幾次都沒用。

### 代替判據（三個都接，不只挑一個）

1. **`CrashReportClient.exe` 出現** ＝ 算繪已死（故障後我手動收的就是這個狀態）；
2. **log 最後一行時戳停止前進**超過 N 秒；
3. **我自己表裡的 `FAULTED`／`DEAD` 行**——已經信任的欄位，用它觸發收尾比問信箱可靠。

**這一格不改腳本**（13c：趟 5 的 shell 隨時會讀同一個檔），剩兩趟手動監看，改在交機之後。

## 趟 4 標記：程序受擾（故障後由人工收尾）

| 趟 | 類別 | 秒數 | 程序 |
|---|---|---:|---|
| 1 | 開卡期 | 94.3 | 完整（舊收尾路徑） |
| 2 | 開卡期 | 86.9 | 完整 |
| 3 | 啟動期 | 25.3 | **受擾：腳本中途被改、重跑一段** |
| 4 | 啟動期 | 26.3 | **受擾：故障後由人工 `taskkill` 收尾** |

對二元尺（有沒有故障）沒影響；**任何牽涉秒數或收尾時間的比較都要帶著標籤**。
照趟 3 的先例：標記是義務，不因為「看起來沒受損」而省略。

**另記**：啟動期四趟現在是 25.4、25.0、25.3、**26.3**，全距從 0.4 秒變成 **1.3 秒**。
先前「0.4 秒的地板」那個說法要照 10c 收窄成「**在前三趟上是 0.4 秒**」，
26.3 這一趟是人工收尾那趟——但收尾發生在**故障之後**，不影響故障時刻，所以**不能拿受擾當理由排除它**。

### 趟 4 在自己這一格裡重現了 B1 那個誤標

趟 4 的結束行是 **`FAULTED after card 1 (crowd_C001.png)`**，但同一張表裡 `entered=0`、零條逐卡行。
**它一張卡都沒開過。**（引擎在啟動期就故障，我人工收掉之後，shell 的等待迴圈才退出、
進到開卡迴圈，第 1 圈就被故障檢查攔下，於是印出「card 1」。）

這正是幾小時前我從 B1 那兩趟查出來、並據以把分類欄位改成 `entered`／`returned` 的同一個誤標——
**現在在我自己這一格裡又出現一次**。差別是這次它無害：分類規則早就不看那個欄位了。

**值得記的點**：那條規則當初是從**別人的舊資料**裡發現的，
如果當時沒改，趟 4 今天就會被分成開卡期，六趟的類別組成會變成 3 開卡／1 啟動——
**一個錯誤的分類，會直接改變結局 A／B／C 的判定。**

# 尺 1 結果（n=5，因佇列壓力提前結束；此組態非協定基線）

**組態**：`r.RDG.TransientAllocator=0`、`noclear`、30 張卡上限、`TestCards-20261118`。
**這不是使用者會跑的組態，所以這組數字不得當成任何修法的驗收門檻。**
提前結束的理由與數值無關（佇列上壓著三組，而這一組的角色已降級），**在看到趟 5 的值之前就已裁定**。

## 五趟

| 趟 | 類別（`entered`） | 秒數 | 故障卡 | 故障前我的提交 | 程序 |
|---:|---|---:|---|---:|---|
| 1 | 開卡期（1） | 94.3 | `crowd_C049.png`（第 6 張） | 0 | 完整（舊收尾路徑） |
| 2 | 開卡期（1） | 86.9 | `crowd_C049.png`（第 6 張） | 1 | 完整 |
| 3 | 啟動期（0） | 25.3 | 零張 | 0 | **受擾：腳本中途被改** |
| 4 | 啟動期（0） | 26.3 | 零張 | 1 | **受擾：人工收尾** |
| 5 | 開卡期（1） | 84.9 | `crowd_C049.png`（第 6 張） | 1 | **受擾：人工收尾** |

### 開卡期三趟**全部**死在同一張卡

`crowd_C049.png`（第 6 張），三趟卡號全距 **0**，而同三趟的秒數是 94.3／86.9／84.9（散布約 10%）。
照先前登記的判法：**卡號是主尺、秒數是副尺**，而這組資料正好說明為什麼——
**同一個現象，用卡號看是完全重現，用秒數看是 10% 的散布。**

這也讓 C049 那三個互斥候選（那張卡特別／那個位置特別／兩者都要）更值得查：
**n=3、全距 0**，不再是兩趟的巧合。但它回答的是「故障發生在哪」，
照裁定仍排在二元尺（「修法有沒有用」）之後。

- **故障趟數／總趟數 = 5/5。**
- **類別：開卡期 3、啟動期 2。**
- **身分**：五趟全部相同——`dll=11-19_16:25:48`、`efork2_style=1bd7eedf5c5a7b062f290bd82d54bdb7d3e81c42`、
  `base_v1=8e31a6552bb6af42`；覆蓋率 `base_v1=140388/140959`、`cards=31/31`、`identity_paths=7035`。
  **沒有一趟因身分不同而作廢。**

## 照事前登記判讀

**結局 C**：五趟分散兩類 ⇒ **尺 1 不可判**，不能當機制格的尺。每一類 n 都 < 6，照 11c 連分辨率都不能談。

**自製負載的檢查（事前登記：單調上升且幅度涵蓋散布才歸因，否則寫「來源未知」）**：

| 類別 | 0 次提交 | 1 次提交 | 方向 |
|---|---|---|---|
| 開卡期 | 94.3 | 86.9、84.9 | 負載多 ⇒ **較快** |
| 啟動期 | 25.3 | 26.3 | 負載多 ⇒ **較慢** |

**兩類方向相反。** 不單調，照登記：**秒數散布來源未知，不再找第二個解釋。**

## 唯一變強的東西：二元結果

五趟、兩類、三種程序擾動、兩種負載條件，**全部故障**。
上面每一項干擾都影響秒數，**沒有一項把「死」變成「不死」**——這正是二元尺該取代秒數尺的理由。
但**這個 5/5 是 `TransientAllocator=0` 組態的**，協定基線仍要在預設組態上重跑。

## 「每次都死在 C049」是**那個組態**的性質，不是普遍性質——A 段四趟死在四張不同的卡

在排三趟去分辨 C049 的三個候選之前，先查了同一份卡單在**別的組態**下死在哪：

| 趟 | 旋鈕 | 故障卡 | 第幾張 |
|---|---|---|---:|
| `bg_A1_1` | `NoBackdrop=1` | `crowd_C055.png` | 7 |
| `bg_A1_2` | `NoBackdrop=1` | （跑完 30 張未故障） | — |
| `bg_A2_1` | `NoBackdrop=2` | `crowd_C077.png` | 9 |
| `bg_A2_2` | `NoBackdrop=2` | `crowd_C006.png` | 2 |
| `bg_AP_1` | `Frames.Pooled=240` | （跑完 30 張未故障） | — |
| `bg_AP_2` | `Frames.Pooled=240` | `heroine_jeanne.png` | 15 |
| **尺 1 趟 1／2／5** | **`TransientAllocator=0`** | **`crowd_C049.png` ×3** | **6、6、6** |

**四張不同的卡、第 2／7／9／15 張，還有兩趟跑完 30 張沒死。**
所以**「故障固定在某一張卡」只在 `r.RDG.TransientAllocator=0` 這個組態下成立**（3/3），
在其他三個組態下**完全不成立**。

### 這對 C049 那三個候選的意義：問題要重新表述

原本的三候選（那張卡特別／那個位置特別／兩者都要）預設了「有一張特別的卡」。
**上表顯示沒有一張普遍特別的卡**，所以正確的問題是：

> **為什麼 `TransientAllocator=0` 會讓故障位置從「隨機散在第 2～15 張、有時不死」
> 變成「每次都是第 6 張」？**

這比「C049 哪裡特別」更值得問，因為**它問的是那個旋鈕做了什麼**，
而那個旋鈕的作用是已知的（`RenderGraphBuilder.cpp:591`：沒有暫態配置器，於是沒有暫態堆）。
一個讓故障變得**位置確定**的旋鈕，比一張卡更像線索。

**但照 10a 這還不能寫成機制**：A 段三個組態各自只有 n=2，尺 1 只有 n=3，
而且兩邊的旋鈕不同、執行檔也不同（15:05 對 16:25）。**目前只能寫成「值得問的差異」。**

### 排程建議（交給協調者裁定）

C049 的三趟重排**仍然值得跑**，但**要在 `TransientAllocator=0` 組態下跑**，
因為那是唯一觀察到固定卡號的組態；在預設組態下跑重排，很可能只會看到卡號又散開，
那回答不了任何候選。優先度仍在協定基線之後、機制格之前，和現在的排程一致。

## 三個機制格的旋鈕輸入盤點（前置第 1 項，零機器時間，已完成）

| 輸入來源 | 查到什麼 |
|---|---|
| `Config/DefaultDreamGUI.ini` | **只有輸入政策**（`bUseSlateInputSource=True`、`SlateInputConsumePolicy=WhenOverUI`）。**沒有任何一個 key 碰到這三個旋鈕。** |
| `Config/DefaultEngine.ini` 的 `[ConsoleVariables]` | 只有 `r.SkyLight…`、`r.MotionBlurQuality`、`r.AntiAliasingMethod`、`r.OK.OpaqueSortPriority`、`r.Nanite.Editor.DrawLists.AsyncUpdates` 等；**沒有 DreamGUI 或暫態配置器相關的 key。** |
| `[SystemSettings]` | **這個區段不存在。** |
| 環境變數 | `Source/`、`Plugins/` 裡所有 `GetEnvironmentVariable`／`getenv` 都是 `OK_ALBEDO_*`、`OK_APNG_*`、`OK_PROFILE_*`、`OK_RUNTIME_*`、`OK_EYE_AUDIT_*`、`OK_NO_CLOTH_DYNAMICS` 等**別的功能**；**沒有一個名字對應這三個旋鈕**。 |
| 命令列 | 啟動器自己會加 `r.RDG.ParallelExecute=0`、`-OKPhysics=verlet`、`-ReaderPages=…`。**這些就是預設協定的一部分**（讀卡器平常就這樣跑），每趟的 log 都記著完整命令列。 |

### `NeverDeleteProxy` 這一格：前置三項**都已經就緒**

`Plugins/DreamGUI/Source/DreamGUIRenderer/Private/DreamUIRender/DreamUIMaterialProxy.cpp:95` 註冊
`DreamGUI.Experiment.NeverDeleteProxy`，預設 `0`，`ECVF_RenderThreadSafe`。

- **第 1 項（輸入）**：只有 cvar 一條路，預設 `0`，而且是 `GetValueOnAnyThread()` **即時讀取、沒有在啟動時快取**
  （`:105`），所以不存在「值在物件建構時取樣一次」那個殘差風險。贏的來源仍由 `LastSetBy` 記在表頭。
- **第 2 項（機制作用點的到達證據）**：**程式自己就會記**——
  `DreamGUI EXPERIMENT: material proxy leaked on purpose, total=N`（`:112`）。
  **這一格不需要另外加儀器**：`total=0` 或這行完全沒出現，就代表旋鈕沒有到達那一點，該趟作廢。
- **第 3 項（事前預測含方向）**：若材質代理的解構是觸發者，開了旋鈕應得 **0/6**；若不是，應得 **6/6**。
  洩漏量有界（30 張卡是有限次），而 `total=` 和該趟的行程 RAM 要一起讀，證明有界。
  **這個旋鈕永遠不能出貨**：一個靠洩漏讓當機消失的改動是診斷，不是修法。

`gclrun` 與 retention 兩格的同類盤點等基線跑完再做（都不用機器）。

## 「C049 第 6 張」的混淆我自己查清楚了，而且 14:38 那趟**不是預設組態**

### 一、順序完全相同 ⇒ 卡與位置**完全混淆**

我的卡單（`/e/OKPackage/TestCards-20261118/*.png`，glob 順序）前六張是：

```
1 crowd_C001.png   2 crowd_C006.png   3 crowd_C011.png
4 crowd_C020.png   5 crowd_C033.png   6 crowd_C049.png
```

**和 14:38 那趟的開卡順序逐張相同。** 所以四筆資料都是同一個順序，
**「C049」與「第 6 張」在現有全部資料裡完全混淆**，分不出是哪一個。
（這一條不必去問 e-fork-2，列一下目錄就有。）

### 二、14:38 那趟帶了三個旋鈕，**不是預設組態**

它的命令列有：

```
DreamGUI.DeferredRelease.Frames.Texture=240
gc.TimeBetweenPurgingPendingKillObjects=10
DreamGUI.LogStaleTextures=1
```

所以目前「C049 第 6 張」的 4/4 是**兩組不同的旋鈕設定**各自的結果
（14:38 那三個旋鈕 ×1、`TransientAllocator=0` ×3），跨兩個執行檔與兩份基礎庫。
**不變性比我原本以為的更強**——但**仍然沒有任何一筆是預設組態**。

而同一份卡單在另外三組旋鈕下**不是**死在第 6 張：
`NoBackdrop=1` → C055 第 7 張（或跑完 30 張）、`NoBackdrop=2` → C077 第 9 張與 C006 第 2 張、
`Frames.Pooled=240` → `heroine_jeanne` 第 15 張（或跑完）。**所以它不是普遍的。**

### 三、所以協定基線**不該讓位給那三趟判別**——它正好補上唯一缺的那一格

缺的那一格是：**預設組態會不會也死在第 6 張。**
協定基線跑的就是預設組態＋同一份卡單，所以**它自己就會回答這個問題**，
不必另外設計。而三趟重排判別要分辨的是「卡 vs 位置」，
那是**在已知某個組態穩定死在第 6 張之後**才有意義的下一步。

### 事前預測（在結果出來之前寫下，趟 1 正跑到第 5 張）

> **若「C049 第 6 張」在預設組態也成立，基線趟 1 應當死在第 6 張。**
> 死在第 6 張 ⇒ 這個重現**不依賴任何非預設旋鈕**，可以直接當二元尺的基線，
>   而且它便宜（約 95 秒、6 張卡），機制格立刻可以開始；
> 跑完 30 張不死，或死在別的位置 ⇒ 「C049 第 6 張」是**旋鈕相關**的，
>   那三趟重排判別就要在 `TransientAllocator=0` 組態下跑，而協定基線另算。

**兩種結果都有用，而且都已經寫下動作**——這是今天第一次在結果出來之前就把兩條路都定好的格子。

# 事前預測在趟 1 成立、趟 2 **不成立**：預設組態的故障位置會動

基線趟 1（**沒有任何旋鈕**）死在第 6 張 `crowd_C049.png`、98.5 秒——正是事前預測的結果。
**趟 2 死在第 4 張 `crowd_C020.png`、78.0 秒。**

| 基線趟（預設組態） | 秒數 | 故障卡 | 第幾張 |
|---:|---:|---|---:|
| 1 | 98.5 | `crowd_C049.png` | 6 |
| 2 | 78.0 | `crowd_C020.png` | **4** |

**所以「第 6 張 C049」不是預設組態的性質。** 趟 1 單獨看符合預測，**趟 2 推翻了它**。

## 我差點用 n=1 發表一個結論

趟 2 的通知到達之前，我已經把這一節寫好了，標題是
「**事前預測成立：預設組態也死在第 6 張**」，內文列了一張 5/5 的表，
寫著「同一張卡、同一個位置，橫跨兩個執行檔、兩份基礎庫、三種旋鈕設定（其中一種是沒有旋鈕）」，
並據此宣告「這個重現不依賴任何非預設旋鈕，可以當二元尺的基線」。

**那是一個 n=1 的預設組態觀測**，而我早上才因為別人把 n=3 當成穩定而要求收窄。
它沒有進版控，純粹因為提交前通知先到了——**不是因為我多謹慎**。
照 11b，預設組態當時 n=1，本來就連「集中趨勢」都不該談，更不該宣告不依賴旋鈕。

**教訓不是「要更小心」，是「事前登記的預測在 n=1 上成立時，誘惑最大」**：
預測命中的那一刻感覺像是最強的證據，而它其實只是一趟。
**事前登記保護的是判讀方式，不保護樣本數。**

## 修正後的範圍

目前唯一觀察到「故障位置固定」的組態仍然只有 `r.RDG.TransientAllocator=0`（3/3 全在 C049 第 6 張）。
其他組態的故障位置都會動：

| 組態 | 故障位置 |
|---|---|
| **預設（無旋鈕）** | **C049 第 6 張、C020 第 4 張**（n=2，兩趟兩個位置） |
| `NoBackdrop=1` | C055 第 7 張；另一趟跑完 30 張沒死 |
| `NoBackdrop=2` | C077 第 9 張、C006 第 2 張 |
| `Frames.Pooled=240` | `heroine_jeanne` 第 15 張；另一趟沒死 |
| `TransientAllocator=0` | C049 第 6 張 ×3 |
| 14:38 的三旋鈕組合 | C049 第 6 張 ×1 |

**不變的是「會故障」，會動的是「在哪裡故障」。** 這再次指向二元尺：
位置在五種組態裡有四種會動，而**故障本身在 7 趟裡出現 7 次**（含兩趟跑完 30 張未死的除外；
含那兩趟則是 9 趟 7 次）。

## 判別三格：премиса變了，但**更值得跑**，而且要改判讀

原本三格要分辨「C049 這張卡 vs 第 6 張這個位置」。
**預設組態下位置會動，所以在預設組態跑這三格，很可能只會看到位置又散開——那回答不了任何候選。**

照先前自己寫過的同一個理由（組態不同就不能混算），**三格要在
`r.RDG.TransientAllocator=0` 組態下跑**，因為那是唯一觀察到位置固定的組態，
也是唯一能讓「卡 vs 位置」這個問題有意義的組態。

### 設計（目錄已建好，硬連結，不複製位元組）

`-SelectionFile` 這條路**不存在**：`Tools/ok-game-mcp/src/reader.rs:16-17` 顯示
`reader_launch` 只有 `card`、`card_directory`、`lane`、`extra`、`env`——
`-SelectionFile` 是街區的旗標，不是讀卡器的，照著做會得到「旗標被忽略」的無聲失敗。
順序既然來自檔名排序，就用檔名控制：

| 格 | 目錄 | 內容（排序後） |
|---|---|---|
| 1 | `E:/OKPackage/disc-c049-first` | `01_crowd_C049.png`（只這一張） |
| 2 | `E:/OKPackage/disc-c049-tenth` | `01_crowd_C055` … `09_heroine_klara`，第 10 張 `10_crowd_C049` |
| 3 | `E:/OKPackage/disc-pos6-other` | `01_crowd_C001` … `05_crowd_C033`，**第 6 張換成 `06_crowd_C055`** |

驅動 `disc1x.sh` 是 `knob1x.sh` 的**副本**（基線正在跑那個檔，附則 13c 不原地改）。

### 兩個設計上的誠實註記

**一、暖機那張卡不動，所以「第 1 張」不等於「前面什麼都沒有」。**
驅動在卡片迴圈之前會先載入 `crowd_C001.png`、進 1 對 1、再回來（`disc1x.sh:95`，**刻意保留絕對路徑**），
所以基線裡 C001 被載入兩次，而 C049 是**整趟的第 7 次載入**。
三格保留同樣的暖機，protocol 才是常數；代價是它們分辨的是**卡片迴圈裡的第幾張**。

**二、格 2 的「已知不當的卡」在任何組態下都是未知的。**
預設組態只跑過兩趟，且第二趟就死在 C020（第 4 張）——
**所以連 C001…C033 都不能稱為「已知不致命」**。格 2 的前九張是未測卡；
若它在到 C049 之前就死，該格對「卡 vs 位置」無法判讀，但仍是資料（它會指名哪一張殺的）。

### 事前登記的判讀（在 `TransientAllocator=0` 組態下）

| 格 1（C049 第 1 張） | 格 3（第 6 張換 C055） | 結論 |
|---|---|---|
| 當 | 不當 | **是那張卡**（C049 本身） |
| 不當 | 當 | **是那個位置／累積狀態** |
| 當 | 當 | 兩者各自充分 |
| 不當 | 不當 | **「那張卡在那個位置」才觸發** |

格 2 作為格 1 的補強。**三格各 1 趟，有矛盾再加 n**——而且照上面那個教訓，
**任何單趟結果都不得當成結論**，哪怕它正好命中事前預測。

## 讀卡器**沒有** `-SelectionFile`：這條路第三次被建議，但它不存在

`grep -rniE 'selectionfile'` 全樹只命中 `Tools/run_crowd_behavior_development.lua` 與
`Tools/run_crowd_development.lua`——**人群／街區場景**的啟動器。
讀卡器走 `Tools/run_card_reader_development.lua`，而 `reader_launch` 的參數只有
`card`、`card_directory`、`lane`、`extra`、`env`、`no_build`、`width`、`height`、`timeout_s`
（`Tools/ok-game-mcp/src/reader.rs:16-17`）。

**所以用 `-SelectionFile` 指 C048 的絕對路徑不會「沒生效」，而是會被整個忽略，
那一趟仍然讀 `card_directory`，而且表頭看不出差別**——正是今天反覆出現的那種無聲失敗。

替代做法已經在用，而且**滿足「不要把檔案複製進 `TestCards-20261118`」這個要求**：
另建專用目錄，裡面放**硬連結**（同磁碟，不複製位元組），原目錄一個位元組都沒動。
C048 在 `Content/CharacterCards/CrowdAPNG/`，硬連結同樣適用。

## 但在排離群值那幾格之前：**基線趟 2 的死法已經和離群值分析衝突**

基線（預設組態）趟 2 死在 **`crowd_C020.png`（第 4 張）**。
把它放進 f-yvonne 那張表看：

| 卡 | ME 資料量 | 內嵌 PNG | 總像素 | 這一趟的結果 |
|---|---:|---:|---:|---|
| C001（第 1 張） | 50.1 MB | 45 | **310.6 Mpx** | 開過沒事（兩趟都沒事） |
| **C020（第 4 張）** | **25.6 MB** | **39** | 280.9 Mpx | **趟 2 死在這張** |
| C049（第 6 張） | 88.8 MB | 120 | 300.9 Mpx | 趟 1 死在這張 |

**C020 在兩個倖存的離群維度上都不離群**——ME 資料量 25.6 MB 是開過的卡裡**倒數**，
內嵌 PNG 39 張比 C001 的 45 張還少。而 C001（兩個維度都比 C020 高）**兩趟都開過沒事**。

> **所以「那張卡的貼圖資源個數／ME 位元組太多」不是必要條件**：
> 一張在這兩個維度上都不突出的卡，在預設組態下照樣讓它死。

這和「總像素」被卡單自己否掉是同一回事，只是這次否掉的是**倖存的那兩項**。
照 10a，這只能寫成**第 3 類（這個維度不能解釋故障發生與否）**，不能寫成「離群值無關」——
C049 那兩項仍然是真的離群，只是**它不是故障的必要條件**。

### 對判別次序的影響（建議，交協調者裁定）

**基線剩下的四趟本身就是最便宜的判別**：它每趟都會指名死在哪一張，
而那正是「死的卡會不會變、變了之後跟不跟離群維度走」的直接觀測，**零額外成本**（已經在跑）。
目前 n=2 就已經有兩張不同的卡、其中一張不離群。

所以建議：**先把基線六趟跑完**（約再 6 分鐘），
再決定要不要跑格 1。若基線六趟死在四五張不同的卡上、彼此在離群維度上沒有共同點，
那「那張卡」這一側就已經被基線自己排除，**格 1、格 3、格 4、C051／C052 全部不必跑**，
重點直接回到累積與 `FDreamUIDeferredRelease`——f-yvonne 自己也指向那條線（到第 6 張累積約 892 Mpx）。

若基線六趟反而集中在少數幾張且都是高 ME／高張數的卡，那格 1 與梯度三格就值得跑。
**兩種結果的動作都已寫下。**

## 離群值那條線收掉，判別四格取消；`-SelectionFile` 記為協調者提的儀器

### 撤回一：`-SelectionFile`（提議者：協調者，連續三封據此設計判別）

讀卡器沒有這個旗標（全樹只有人群／街區啟動器有）。**危險之處不是它無效，而是它無聲**：
若照著做，四個格子會全部跑成原卡單，四個「結果」看起來彼此一致，
而那四趟其實是同一個條件——**一個會讓判別看起來成功的失敗**。
這是「儀器沒到達機制作用點」的又一例（7k 家族），**而這次儀器是協調者提的**，
照他要求把提議者記下來。替代：專用目錄＋硬連結，原卡單一個位元組未動。

### 撤回二：卡的靜態特徵不能預測哪張會死 ⇒ 判別四格與 C051／C052 全部取消

| 卡 | ME 資料量 | 內嵌 PNG | 結果 |
|---|---:|---:|---|
| C001 | 50.1 MB | 45 | 兩趟都沒事 |
| **C020** | **25.6 MB** | **39** | **趟 2 死在這張** |
| C049 | 88.8 MB | 120 | 趟 1 死在這張 |

**離群既不必要也不充分。** 而「C049 必死」不是定律，是
**前四趟同一份卡單順序＋同一族組態綁在一起造成的假恆定**——預設組態一換，故障卡就換了。

f-yvonne 那條離線分析產出的是一個**否定結果**（靜態特徵不能預測），**那也是結果**。
它同時留下一個仍然有用的數字：到第 6 張為止 ME 貼圖累積約 892 Mpx，
若未釋放約 3.6 GB（RGBA8 不含 mip）——那指向 `FDreamUIDeferredRelease`，和既有旋鈕同一塊。

### 現在只剩一把尺：二元尺（固定協定下會不會故障），在預設組態量

1. 六趟跑完，**中途不改協定**；每趟記死在第幾張、哪一張卡，以及 `entered`／`returned`。
2. 六趟的「故障卡清單」本身就是證據：**死在六張不同的卡 ⇒ 成因是累積／時間，與卡內容無關**，
   `FDreamUIDeferredRelease` 成為主線；集中在少數幾張才回頭談卡。
3. **基礎率寫成分數，不寫「必死」。** 目前故障位置分散，所以尺的輸出是
   **「每趟故障機率接近 1」**，不是「第 N 張必死」。這兩種說法對「要跑幾趟才算修好」
   的要求差很多——前者需要的趟數由機率算，後者會讓人誤以為一趟就能判。

## `gclrun` 與 retention 兩格的輸入盤點（前置第 1 項，純讀碼完成）

### retention／`DeferredRelease`：乾淨，而且到達證據已內建

`Plugins/DreamGUI/Source/DreamGUIRenderer/Private/DreamUIRender/DreamUIDeferredRelease.cpp:11-24`
四個 cvar，**預設值都是 3**（不是 0——先前以為要和 0 比的那三個「都沒排除任何東西」的推論，
基準點是 3 不是 0）：

| cvar | 預設 |
|---|---:|
| `DreamGUI.DeferredRelease.Frames.Texture` | 3 |
| `DreamGUI.DeferredRelease.Frames.Buffer` | 3 |
| `DreamGUI.DeferredRelease.Frames.Pooled` | 3 |
| `DreamGUI.DeferredRelease.Frames.Func` | 3 |

- **輸入**：只有 cvar；`Config/` 無對應 key、無同名環境變數。
- **讀法**：`GetValueOnRenderThread()`（`:54-55`、`:62-63`），**即時讀取、沒有快取**。
- **到達證據**：`:54-55` 已經把四個值一起記進 log，**不必另外加儀器**。

### `gclrun`：**值在 RHI 初始化時被快取進 `Initializer`，`LastSetBy` 抓不到這個洞**

`/e/PhysX/UE5.8/Engine/Source/Runtime/RHICore/Private/RHICoreTransientResourceAllocator.cpp`：

```
41:  static int32 GRHITransientAllocatorGarbageCollectLatency = 16;
42:  FAutoConsoleVariableRef CVarRHITransientAllocatorGarbageCollectLatency(...)
528: Initializer.GarbageCollectLatency = GRHITransientAllocatorGarbageCollectLatency;  // FRHITransientHeapCache::FInitializer::CreateDefault()
1280:Initializer.GarbageCollectLatency = GRHITransientAllocatorGarbageCollectLatency;  // FRHITransientPagePoolCache::FInitializer::CreateDefault()
607: if (Heap->GetLastUsedGarbageCollectCycle() + Initializer.GarbageCollectLatency <= GarbageCollectCycle)
1372:if (PagePool->GetLastUsedGarbageCollectCycle() + Initializer.GarbageCollectLatency <= GarbageCollectCycle)
```

**驅逐判斷讀的是 `Initializer.GarbageCollectLatency`，而那是 `CreateDefault()` 在建構 cache 時
從全域變數抄過去的一份快照。** cache 在 RHI 初始化時建立一次，所以：

> **在主控台（`game_exec`）設這個 cvar 會讀回成功、`LastSetBy: Console`，
> 但配置器仍用初始化時那份舊值——一個 `LastSetBy` 完全看不見的無聲失效。**

這正是前置清單第 1 項要防的那一類，而且**`LastSetBy` 這個半自動解在這裡失效**
（先前寫「對 cvar 已經有一半的自動解」，範圍要收窄成「只對**多來源互相覆蓋**有效，
對**啟動時快照**無效」）。

**所以 `gclrun` 必須用命令列設**（`-ini:Engine:[ConsoleVariables]:` → `SystemSettingsIni`，
在第一帧之前生效，也就是在 RHI 初始化之前）。我的驅動本來就是這個形式，**方法是對的**，
但這條必須寫下來，否則將來有人想「現場調一下看看」就會得到一個乾淨的假陰性。

### 這一格的到達證據比較弱，照 7j 申報

沒有任何 log 會印出配置器實際使用的 latency。能申報的只有：

1. **「設定在初始化之前」**——log 開頭的 `LogConfig: Set CVar [[RHI.TransientAllocator.GarbageCollectLatency:N]]`
   與命令列那一行；這證明值進了 cvar 系統且在 init 前，**不證明 cache 用了它**。
2. **行為代理**：latency 加大 ⇒ 閒置堆更晚被 `delete`（`:612`）⇒ 若「0 active heaps」來自堆被刪，
   故障該變晚或消失。這是**預測**，不是到達證據。

**覆蓋率申報：`gclrun` 的到達證據 = 1/2（只有「設定時機」，沒有「機制點使用」）。**
照 7j，這一格的**陰性結果不能當排除**——若它 6/6 照樣當，只能寫成
「在這個 latency 下故障仍發生」，不能寫成「堆回收不是成因」。

## 寫進協定：我的 0/6 回答的是「**有沒有修好**」，不是「殘餘率低於多少」

f-sceneload 的算術（`F:\OpenKoikatsu\Docs\CRASH_FIX_EVIDENCE_MATH_20261119.md`，提交 `48b2e61f1`）要求
在看到任何修法結果之前先講清楚問的是哪一個。**現在定下來：**

> **主要問題：相對於基線（每趟故障機率接近 1），這個改動有沒有改變故障發生與否。**
> 判據：同一協定六趟 **0/6**。
>
> **0/6 不建立「殘餘率低於某個值」。** 它給的 95% 單邊上界是 **p ≤ 0.393**——
> 也就是「殘餘率若高於 39%，連跑六趟全淨的機率不到 5%」，
> **不是「修好的機率 95%」**，也不是 p<0.1。
>
> 要 p<0.3 需 **9 趟**、p<0.1 需 **29 趟**、p<0.05 需 **59 趟**。
> **那些趟數我不會跑，也因此不會宣告那些上界。**
> 若將來有人要「殘餘率低於 10%」那種保證，必須另外付 29 趟，**不能從 0/6 推出來**。

### 為什麼選這一個問題

基線接近 1，所以**第一趟乾淨就已經把「完全沒修好」打掉幾十倍**（f-sceneload 的似然比表）。
在這個狀況下，六趟的邊際價值是壓上界，而**我要的是「這條路對不對」的方向判斷**，
不是出貨保證。機制格是在找成因，不是在驗收產品——**用 29 趟去壓一個診斷格的上界是浪費機器時間。**

### 「乾淨」的定義寫死（我今天踩過兩次這個坑）

> **一趟算乾淨，必須是跑完全部卡片且 `entered`／`returned` 證明讀卡器真的開過那些卡。**
> **不是「沒看到錯誤訊息」。**

今天兩次教訓都在這一點上：MCP 的 `not_ready` 回話讓 `STOP at card 1` 印在一張
一張卡都沒開過的表上（B1 兩趟）；`FAULTED after card 1` 也印在 `entered=0` 的趟上（趟 4）。
**沒有錯誤訊息不等於沒有故障，而迴圈計數不等於開過卡。**

### 「每趟 vs 每卡」：加長卡單**另開一組協定**，不混進六趟

卡單是身分的一部分（`fp-rule-4` 的 `cards=` 欄位），混進去會讓六趟不可比。
**事前預測寫下來**：

| 模型 | 加長卡單（m 變大）的預測 |
|---|---|
| 每趟一次機會 | 故障率**不隨 m 上升** |
| 每卡都有機會（危險率 q） | 故障率**隨 m 上升** |

m=6 跑 6 趟全淨 ⇒ q ≤ 0.080；m=24 跑 3 趟全淨 ⇒ q ≤ 0.041。
**所以若是每卡模型，長卡單便宜得多（29 趟 vs 2～5 趟）**——這個差距比任一模型自己的數字重要。
加長卡單同樣**從 `CrowdAPNG/` 另建硬連結目錄**，原卡單一個位元組不動。

### 「每卡恆定 vs 累積」要看故障位置的分布——六趟的位置清單就是那份資料

- **恆定危險率** ⇒ 位置近似幾何分布，**第 1、2 張也該常見**；
- **累積**（延遲釋放堆積）⇒ 位置集中在中後段，**幾乎不會在第 1、2 張**。

目前四趟的位置是 **6、4、6、≥17**（趟 4 寫到第 17 張時仍在跑）。
**沒有一趟死在第 1 或第 2 張**，而且位置散開到 17 以上——
照 11b，n=4 不報結論，但這份清單正是要看的東西，六趟齊了再讀。

### 不獨立這一點照實記

六趟是**同一台機器、同一份卡單、連續跑**，熱狀態與驅動狀態共用。
f-sceneload 標了這會**高估排除力**。所以上面那個 p ≤ 0.393 是**樂觀值**，
真實的排除力更弱。**回報時要帶這句，不能只報數字。**

## 位置那一層的檢定接受，但「平均故障位置反推 q̂」在我的資料上會偏——因為會有設限趟

f-sceneload 的方法（文件第 6 節，`5f05105f5`）是用**平均故障位置**反推恆定危險率 q̂，
再問「n 次故障一次都沒落在前 j 張」有多罕見。模型對，但套在我這批資料上有一個會踩的點：

> **30 張是天花板，所以跑完 30 張不死的趟是「設限觀測」（censored），不是「位置 = 30」。**
> 若把設限趟丟掉、只對「有故障的趟」取平均位置，那是一個**截斷平均**，
> **會把 q̂ 估高**（漏掉了那些撐得久的證據），於是「沒落在前兩張」看起來比實際更罕見，
> **偏向「排除恆定危險率」的方向**——正好是會讓人下錯結論的那一邊。

這不是假設性的：**趟 4 已經開到第 20 張還活著**（趟 1／2／3 是第 6／4／6 張）。
A 段也有兩趟跑完 30 張未故障。所以設限趟在這份資料裡**一定會出現**。

### 正確做法（不必多跑任何趟，只是換算法）

q̂ 要從**完整的似然**估，讓每一趟按它實際提供的資訊貢獻：

- 第 k 張故障的趟 ⇒ 貢獻 `(1-q)^(k-1) · q`
- 跑完 m 張未故障的趟 ⇒ 貢獻 `(1-q)^m`（**不是丟掉，也不是當成 k=m**）

六趟齊了我用這個式子解 q̂，再算「沒有一趟落在前 j 張」的機率。
**同一批趟次、同一份逐卡記錄，不改協定。**

### 另外兩個必須一起申報的前提

**一、位置的定義**：用**逐卡行**（`entered`／`returned` 證明真的開到那一張），
**不用結束行**。今天結束行誤報過兩次（`STOP at card 1` 在 `entered=0` 的趟上、
`FAULTED after card 1` 同理）。這一點 f-sceneload 自己也點了，我照辦。

**二、暖機那張卡讓「第 1 張」不是真的第一次載入**：
每趟在卡片迴圈之前先載入 `crowd_C001.png`、進 1 對 1、再回來。
所以「第 k 張」實際是**整趟第 k+1 次開卡**，而第 1 張還是 C001 的**第二次**載入。
**對恆定 vs 累積的檢定，這會讓「前兩張」這個窗口實際上是第 2、3 次載入**——
幾何模型的 j 要照這個偏移讀，否則「沒落在前兩張」這句話對應的不是前兩次載入。
（這一條沒人提過；它不改方法，但會改 j 的數值。）

### 無記憶性檢查也一起算

「撐過第 j 張之後還要再開幾張才死」——恆定危險率下與 j 無關，累積下隨 j 下降。
六趟的逐卡記錄足夠算，**同樣不必多跑**。
但 n=6 下這個檢查的檢定力很低，照 11b **只報數字與方向，不下結論**。

## 更正：趟 4 **故障了**（第 21 張、170.3 秒），基礎率仍是 4/4——我的中途回報引出了一個錯誤的重新規劃

我上一封寫「趟 4 已開到第 20 張還活著」。那句話在寫下的當時是對的，
**但它被讀成「可能會跑完 30 張」，協調者據此開始重算整條證據線**
（基礎率可能不接近 1 ⇒ 0/6 的證據力要全部重算 ⇒ 第一趟乾淨的似然比不成立）。

**趟 4 在 18:39:31 故障，第 21 張、170.3 秒、`entered=1 returned=1`。**

| 基線趟（預設組態） | 秒數 | 故障位置（卡片迴圈） | 故障卡 |
|---:|---:|---:|---|
| 1 | 98.5 | 6 | `crowd_C049.png` |
| 2 | 78.0 | 4 | `crowd_C020.png` |
| 3 | 84.1 | 6 | `crowd_C049.png` |
| 4 | **170.3** | **21** | （第 21 張，表的最後一條逐卡行是 20） |

**4/4 故障，沒有設限趟。** 所以「基礎率可能不接近 1」這個擔心**目前沒有資料支持**，
那整套重算不必做。

### 這是我的回報方式造成的，不是協調者誤讀

我報的是一個**還在進行中的趟**的中間狀態，而且沒有同時說明
「它還沒結束，faults 欄位要等收尾才寫」。一個進行中的狀態被當成結果，
是回報方式的問題——**進行中的數字要標成進行中**，否則對方沒有辦法知道該不該拿它做決定。
（今天我自己也踩過反面：把一個進行中的卡死狀態外推成「每趟浪費 13 分鐘」。）

### 但設限那個方法論問題**仍然成立**，只是不是因為趟 4

A 段確實有兩趟跑完 30 張未故障（`bg_A1_2`、`bg_AP_1`），所以設限趟**存在於這份資料集裡**，
完整似然那個算法仍然必要。**它不依賴趟 4 的結果**——這一點先前沒分清楚，現在分清楚：

> **設限趟在 A 段已經出現過，所以 `(1−q)^m` 那一項不是為了趟 4 準備的。**

### 位置的散布開始有形狀了（n=4，照 11b 不下結論）

位置 **6、4、6、21**（換成「整趟第幾次開卡」是 7、5、7、22，含暖機那次）。
**沒有一趟落在第 1 或第 2 張**，而最久的一趟撐到第 21 張。
秒數 78～170 的範圍（2.2 倍）比先前三趟的 10% 散布大得多——
**先前「秒數散布約 10%」那句話的範圍要收窄成「前三趟」。**

## 閉式完整似然算在**實際資料**上：結論和 f-sceneload 一樣，但它表裡的輸入不是我的趟次

f-sceneload 的對照表（`57cfabeff`）寫的觀察是「**5 趟故障、平均第 5 張，另 1 趟開到第 20 張仍活著**」。
**那不是我的資料**——它用的是我那封被自己撤回的中途回報（趟 4 當時還活著）衍生出來的集合。

**實際四趟**：全部故障，迴圈位置 **6、4、6、21**，換成實際開卡次數（含暖機）為 **7、5、7、22**，
**沒有設限趟**。

照它給的閉式 `q̂ = D / (D + S)`，S = 存活過的開卡次數總和：

```
D = 4
S = (7-1) + (5-1) + (7-1) + (22-1) = 6 + 4 + 6 + 21 = 37
q̂ = 4 / 41 = 0.0976
```

「四次故障都沒落在前兩次開卡」的機率：`((1-q̂)^2)^4 = 0.8144^4 =` **0.44**。

> **44%——什麼證據都不是**，和 f-sceneload 的結論一致（它算的是 0.356）。
> **結論正確，輸入不對**；兩邊獨立算出同一個方向，所以這個結論可以綁。

**先前那兩個數字（6.9%、0.8%）照它說的作廢，不要再引用。**

### q̂ ≈ 0.098 讓「哪張卡特別」第二次被否定，而且這次是定量的

若每次開卡約 9.8% 機率故障：

- 一趟 30 張（31 次開卡）的故障機率 ≈ `1 - 0.902^31` ≈ **96%**——和我觀察到的 4/4 相容；
- **撐過前 21 次開卡的機率 ≈ 11.5%**，而趟 4 正是在第 22 次開卡故障的——**不罕見**；
- 位置 4、6、6、21 在幾何分布下完全不需要「某張卡特別」或「累積」來解釋。

> **目前全部資料都和「每次開卡約 10% 的恆定危險率」相容。**
> 照 10a 這是**第 3 類**（這個模型足以解釋觀察），**不是**「已證明是恆定危險率」——
> 幾何分布擬合不排除累積，只是累積**不再是必要的**。

### 排程照這個收斂

- **「每卡恆定 vs 累積」不再為它多跑趟**：現有 n 量不出來，六趟也不會夠；
  它要的 n 遠大於二元尺要的 n，而且**它不是「修好與否」的必要條件**。
- **還活著的鑑別只剩加長卡單**（每趟 vs 每卡）。而 q̂ ≈ 0.1 讓它更值得跑：
  每趟能取到的卡次變多，上界就壓得更快（m=24、3 趟 ⇒ q ≤ 0.041）。
- **基礎率寫成分數**：目前 **4/4**（n=4），六趟齊了改寫成 x/6。

### 故障卡清單（n=4）：三張不同的卡

| 趟 | 位置 | 故障卡 |
|---:|---:|---|
| 1 | 6 | `crowd_C049.png` |
| 2 | 4 | `crowd_C020.png` |
| 3 | 6 | `crowd_C049.png` |
| 4 | 21 | `kks_CharacterExport_Female.png` |

**三張不同的卡**，而第四張（`kks_CharacterExport_Female`）**根本不在 f-yvonne 那份離群值分析的清單裡**
（那份只比了 crowd 系列的前十張）。所以「卡的靜態特徵」那條線不只被否定，**連樣本都沒覆蓋到實際故障的卡**——
照 7j，那份分析的覆蓋率是 10/31（只比了卡單裡的十張 crowd 卡），而 4 次故障裡有 1 次落在它沒看的 21 張裡。

## 新形狀：**數字是真的，但它不是這個系統產生的**——撤回要追到所有引用它的地方

協調者的自查：我那句「趟 4 已開到第 20 張還活著」被轉述成 f-sceneload 的**設限觀測**，
再被用來跟我說「基礎率不是接近 1」。**那不是觀測，是傳話。** 我撤回之後，
轉述者手上只有一句話、沒有資料，所以**最容易漏掉回頭更正**。

> **一個數字被撤回時，撤回要追到所有引用它的地方。**
> 而**轉述者是最容易漏的環節**——它沒有原始資料可以重算，只能依賴上游主動通知。

這條和今天其他幾條的差別在於：前面那些是「量錯了」或「問錯了欄位」，
**這一條的數字每一位都是真的**（趟 4 當時確實開到第 20 張、確實還活著），
**錯的是它被當成了哪一類東西**——一個進行中的狀態被當成一個終局觀測。

我這邊要負的責任也寫下來：**我報進行中的狀態時沒有標成進行中**。
標了的話，轉述時就不會變成設限觀測。所以對策有兩半：
**上游標明狀態、下游追蹤引用**，缺一半都會再發生。

## 以實際四趟為準的現況（取代所有先前版本）

| 趟 | 結果 | 迴圈位置 | 實際開卡次數 | 秒數 | 故障卡 |
|---:|---|---:|---:|---:|---|
| 1 | 故障 | 6 | 7 | 98.5 | `crowd_C049.png` |
| 2 | 故障 | 4 | 5 | 78.0 | `crowd_C020.png` |
| 3 | 故障 | 6 | 7 | 84.1 | `crowd_C049.png` |
| 4 | 故障 | 21 | 22 | 170.3 | `kks_CharacterExport_Female.png` |

**4/4，無設限趟**，`q̂ = 0.0976`，「四次都沒落在前兩次開卡」≈ **44%**。

- **基礎率寫成分數與 q̂，不寫「必死」**：q̂≈0.1 下跑完 31 次開卡的故障機率約 **95.5%**，
  **95.5% 和 100% 對門檻的意思不同**，所以這個區別要留著。
- 位置那一層照舊**不為它多跑趟**（44% 比先前轉述的 35.6% 更弱）。
- 「哪張卡特別」**第三次被否定**，而且這次最乾淨：三張不同的卡，
  其中一張**連離群值分析的樣本都沒包含**（覆蓋率 10/31）。

## 「0/6 回答哪個問題」**已經寫死了**，不必再寫一次

協調者再次要求把這件寫進協定。**它在 `f53d479b4` 已經提交**：
主要問題是「**有沒有修好**」（相對基線的方向判斷），判據同協定六趟 0/6，
上界 **p ≤ 0.393（樂觀值，六趟不獨立）**，且**明文不宣告 p<0.3／0.1／0.05 那類保證**
（那要 9／29／59 趟，我不跑也因此不宣告）。
「乾淨」的定義也在同一筆裡定死：跑完全部卡片且 `entered`／`returned` 證明真的開過卡。

## 趟 5：**跑完 30 張未故障**——這批的第一個設限趟，而它把 q̂ 砍掉 43%

終局明確（照協定的「乾淨」定義）：`cards=30`、無任何提早結束行、`fault_secs: NO_FAULT`
（讀了 19832 行帶時戳的紀錄）、`entered=1 returned=1`。**跑完全部卡片，且有證據它真的開過。**

| 趟 | 終局 | 迴圈位置 | 實際開卡次數 | 秒數 | 故障卡 |
|---:|---|---:|---:|---:|---|
| 1 | 故障 | 6 | 7 | 98.5 | `crowd_C049.png` |
| 2 | 故障 | 4 | 5 | 78.0 | `crowd_C020.png` |
| 3 | 故障 | 6 | 7 | 84.1 | `crowd_C049.png` |
| 4 | 故障 | 21 | 22 | 170.3 | `kks_CharacterExport_Female.png` |
| 5 | **設限** | — | **31 次全部存活** | — | — |

### 完整似然重算（設限趟按 `(1−q)^m` 計入，這是它第一次真的派上用場）

```
D = 4
S = (7−1)+(5−1)+(7−1)+(22−1) + 31 = 6+4+6+21+31 = 68
q̂ = 4 / 72 = 0.0556
```

**q̂ 從 0.0976 掉到 0.0556，低了 43%。** 這正是先前那個方法論警告的量級：
**把設限趟丟掉會把 q̂ 估高近一倍。** 當時那個警告是對「會不會出現設限趟」的預判，
**現在它出現了，而且影響不是邊際的。**

連帶的數字一起更新：

| | 丟掉設限趟 | 完整似然 |
|---|---:|---:|
| q̂ | 0.0976 | **0.0556** |
| 「四次故障都沒落在前兩次開卡」 | 0.44 | **0.63** |
| 撐過 31 次開卡的機率 | 4.4% | **17.0%** |

**位置那一層的證據又更弱了（0.63）**，照舊不為它多跑趟。
而「撐過 31 次開卡約 17%」和趟 5 真的撐過了**完全相容**——不需要任何額外解釋。

### 基礎率必須改寫，而且這正是協調者先前擔心的那件事（只是來源不是趟 4）

> **基礎率：5 趟中 4 趟故障、1 趟設限（跑完 30 張未故障）。**
> 不是 4/4，也不是「接近 1」。

**這對門檻的影響是實質的**：若每趟故障機率約 0.8 而不是接近 1，
那麼「修好後六趟全淨」所排除的東西比基礎率 1.0 時弱——
`f53d479b4` 裡登記的 **p ≤ 0.393** 是在「基礎率接近 1」下算的上界，
**基礎率 0.8 時同樣六趟能排除的範圍更窄**。六趟齊了要連這點一起重算，
而**不是**把設限趟當成雜訊剔掉。

**提醒自己：先前協調者說「基礎率可能不接近 1」時，我回報「4/4、那套重算不必做」。
當時那句話對（趟 4 確實故障了），但它只對到趟 4。設限趟在趟 5 出現了，
所以那套重算現在**必須**做——只是理由不同。**

## 寫進協定：乾淨趟的似然比 = `1 / (1−q̂)^m`，m 用**實際開卡次數**

協調者的換算接受，兩處用我這邊的數字收緊：

**一、m 是 31 不是 30**（暖機那次開卡要算進去，和位置那一層同一個偏移）。
協定的一趟是 30 張卡 ＋ 1 次暖機載入 = **31 次開卡**。

**二、這個似然比比的是「完全沒修好」對「完全修好（q=0）」**，
也就是 `f53d479b4` 登記的那個問題（有沒有修好）。
若某個改動只是把 q 減半而非歸零，乾淨趟的機率是 `(1−q/2)^m`，**似然比會小得多**。
**所以這個公式不能用來論證「部分有效」**，只能用在那個二元問題上。

### 在 q̂ = 0.0556、m = 31 下

| 觀察 | 「完全沒修好」下的機率 | 似然比（修好 vs 沒修好） |
|---|---:|---:|
| 一趟乾淨 | **0.170** | **5.9** |
| 0/3 | 4.9×10⁻³ | 204 |
| **0/6** | **2.4×10⁻⁵** | **4.2×10⁴** |

- **單一趟乾淨幾乎不是證據**（5.9 倍）。協調者先前轉述的「第一趟乾淨打掉幾十倍」**作廢**——
  那是基礎率接近 1 下的數字，而那個前提來自被撤回的輸入。
- **0/6 仍然夠強，不要往下砍到 0/3。** 這個「六」現在有實測的 q̂ 支撐，不是估的。
- **反向只要一次故障就夠推翻**：在「完全修好」假設下故障機率為 0，**一次就足夠**，
  不必再跑剩下的趟。

### 它自動給出加長卡單的第二個理由

m 一變，門檻自動跟著動，不必重新談：

| m（實際開卡次數） | 一趟乾淨的機率 | 單趟似然比 | 0/6 |
|---:|---:|---:|---:|
| 31（30 張） | 0.170 | 5.9 | 2.4×10⁻⁵ |
| **61（60 張）** | **0.031** | **32.8** | **8.1×10⁻¹⁰** |

**m=61 時單趟乾淨的證據力就超過現在六趟的三分之一。**
所以加長卡單同時改善兩件事：分辨「每趟 vs 每卡」，以及**讓每趟都更有資訊**。
但卡單是身分的一部分，**仍然要另開一組協定、不混進這六趟**。

### 位置那一層結案

0.63，在這個 n 下量不出來。**不再提，也不為它多跑趟。**

### 旋鈕格全部等基礎率定案

`NeverDeleteProxy`、`gclrun`、retention **在基礎率定下來之前不跑**——
分母沒定，任何旋鈕的「有效」都無法判讀。前置盤點（輸入來源、到達證據、事前預測）
已經做完並提交，所以基礎率一定案就能直接開跑。

# 協定基線完成（預設組態，六趟）：**4/6 故障、2 趟設限**

全部六趟身分**完全相同**：`efork2_style=1bd7eedf5c5a7b062f290bd82d54bdb7d3e81c42`、
`base_v1=8e31a6552bb6af42`、`dll=11-19_16:25:48`。**沒有一趟因身分不同而作廢。**
跑完後槽位已釋放、引擎 0 個。

| 趟 | 終局 | 迴圈位置 | 實際開卡次數 | 秒數 | 故障卡 |
|---:|---|---:|---:|---:|---|
| 1 | 故障 | 6 | 7 | 98.5 | `crowd_C049.png` |
| 2 | 故障 | 4 | 5 | 78.0 | `crowd_C020.png` |
| 3 | 故障 | 6 | 7 | 84.1 | `crowd_C049.png` |
| 4 | 故障 | 21 | 22 | 170.3 | `kks_CharacterExport_Female.png` |
| 5 | **設限** | — | 31（全部存活） | — | — |
| 6 | **設限** | — | 31（全部存活） | — | — |

**基礎率 = 6 趟中 4 趟故障（0.67/趟）＋2 趟設限。** 不是「必死」，也不是 5/5。

## 完整似然

```
D = 4   S = 6+4+6+21 + 31 + 31 = 99   n = 103 次開卡
q̂ = 4/103 = 0.0388        Wilson 95% CI：[0.0152, 0.0956]
```

模型自我一致：`1−(1−q̂)^31 = 0.707` 對觀察到的 **4/6 = 0.667**。

## 最重要的一件事：**0/6 這個門檻的強度本身不確定，差四個數量級**

把 q 的信賴區間傳遞進門檻：

| q | 一趟乾淨的機率 | 0/6 的 p | 0/6 的似然比 |
|---:|---:|---:|---:|
| **0.0152**（CI 下界） | 0.622 | 5.8×10⁻² | **17** |
| 0.0388（點估計） | 0.293 | 6.4×10⁻⁴ | 1,573 |
| 0.0956（CI 上界） | 0.044 | 7.6×10⁻⁹ | 1.3×10⁸ |

> **在 q 的信賴下界上，0/6 的似然比只有 17 倍——幾乎不是證據。**
> 所以 `128858513` 裡寫的「0/6 似然比 4.2×10⁴，六趟夠強」**要撤回**：
> 那是用 q̂=0.0556（n=5）算的點估計，而且**沒有把 q̂ 自己的不確定性算進去**。

而 q̂ 一直在往下走，**每多一個設限趟就把門檻削弱一次**：

```
0.0976 (n=4) → 0.0556 (n=5) → 0.0388 (n=6)
```

**這不是估計在收斂，是基礎率比先前以為的低。** 它直接的後果是：**六趟不夠。**

## 兩條出路，代價差一倍（在 CI 下界上要求 0/n 似然比 ≥ 1000）

| 協定 | 需要的趟數 |
|---|---:|
| 現在的 30 張（m=31） | **15 趟** |
| 60 張（m=61） | **8 趟** |

**加長卡單把需要的趟數砍掉將近一半**，而每趟只長一倍。這是它的第三個理由
（前兩個：分辨「每趟 vs 每卡」、讓每趟更有資訊），而這次是**定量的**。

## 所以下一步的建議（交協調者裁定）

1. **不要用 0/6 當門檻。** 在 q 的下界上它只有 17 倍。
2. **先建 60 張的加長卡單**（從 `CrowdAPNG/` 硬連結，原卡單不動），
   **先量它自己的基礎率**（它同時回答「每趟 vs 每卡」：趟模型預測故障率不隨 m 升、
   每卡模型預測升到 `1−(1−q̂)^61 ≈ 0.91`）。
3. **再用那個協定定門檻**，趟數照 CI 下界算，不照點估計算。
4. 旋鈕三格仍然等門檻定案——**分母的不確定性就是門檻的不確定性**，這次有數字了。

## 加長卡單（60 張）開跑：三件配套的記錄

### 一、前綴名 ↔ 原卡名的對照已存進報告目錄

`Saved/Reports/card-reader-dreamgui/ext60-card-map.txt`（65 行，位置 → 連結名 → 原始卡路徑）。

**為什麼需要**：日誌裡出現的是 `01_crowd_C001.png` 這種前綴名，和既有六趟的 `crowd_C001.png` **不同**。
前綴**只用來固定排序**，檔案是硬連結、位元組完全相同。
沒有這份對照，後來的人看兩批日誌會以為是不同的卡。
**存在版控外的 `Saved/` 而不是只留在腳本裡**——腳本會被改，報告目錄是這批趟次的檔案。

卡單指紋另記：`ext60_cards=bc2fb150bb6841ec count=60`。

### 二、後段（31–60）那 30 張是從沒開過的卡——故障落在後段時要先排除「卡本身壞」

這 30 張來自 `CrowdAPNG/`，**在這個讀卡器協定下從沒被開過**。
它們可能有與當機無關的自身問題（缺資料開不了、`okLc` 不完整等）。

> **規則（只在後段故障時才需要執行）**：
> 若某趟的故障落在位置 31–60，**先單獨開那張卡確認它本身是好的**，
> 才把它算成一次故障事件。否則一個「這張卡開不了」會被誤記成一次 GPU 頁錯誤。

前 30 張不需要這道檢查——它們在既有六趟裡都開過。

### 三、那個 `exit 2` 是什麼，為什麼不影響終局判定

啟動指令是 `nohup bash ext3run.sh … & sleep 10; date; head -2 claim_ext3.txt; grep -E … ext3_fingerprint.txt`。
**整串的退出碼等於最後那個 `grep` 的退出碼**，而那個 `grep` 是我加的**診斷行**
（想立刻印出卡單指紋確認），它在檔案還沒寫完的瞬間執行就會回非零。

- **量測本身在背景的 `nohup` 裡，和那個退出碼無關**：
  已確認槽位 18:57:10 claim 成功、指紋檔 18:57:06 寫好、引擎 1 個、`bash` 行程 8 個在跑。
- **終局判定只讀每趟表裡的 `# faults=`、`# fault_secs:`、逐卡行與 `entered_from_log=`**，
  不讀啟動包裝的退出碼。

**寫下來的理由**：一個「看起來像故障、其實是診斷行」的東西，
如果不解釋清楚，就會變成下一個被誤讀的訊號——今天已經有過
`STOP at card 1`、`FAULTED after card 1`、「信箱還回應」三個同類。

# 加長卡單三趟：3/3 故障、**位置與秒數都緊到不可能是恆定危險率**，而且我的設計前提被自己的資料否掉

三趟都是獨立的執行（pid 71104／76576／73400，三個不同的 log），身分相同
（`efork2_style=1bd7eedf…`、`ext60_cards=bc2fb150bb6841ec count=60`），槽位已釋放、引擎 0 個。

| 趟 | 終局 | 迴圈位置 | 實際開卡次數 | 秒數 | 故障卡 |
|---:|---|---:|---:|---:|---|
| 1 | 故障 | 15 | 16 | **139.3** | `15_heroine_jeanne.png` |
| 2 | 故障 | 16 | 17 | **138.6** | `16_heroine_keqing.png` |
| 3 | 故障 | 16 | 17 | **139.2** | `16_heroine_keqing.png` |

**秒數全距 138.6–139.3，0.5%。** 對照 30 張那批的故障秒數 78.0–170.3（2.18 倍）。

## 恆定每卡危險率被這批資料推翻

三次故障**全部落在第 16 或 17 次開卡**。在恆定危險率下（用合併 q̂=0.0458 或只用 A 批的 0.0388）：

```
P(一次故障落在第 16 或 17 次開卡) ≈ 0.044
P(三次都落在那裡)              ≈ 8.7 × 10⁻⁵
```

> **所以「每次開卡約 5% 的恆定危險率」不能解釋這批資料。**
> 它看起來像**某個接近決定性的門檻**：約 139 秒、約第 16–17 次開卡。

## 但更要緊的是：**兩批不可交換，我的「前 31 次開卡逐位置可比」前提是錯的**

兩批的**前 30 個位置是同樣的卡、同樣的順序**，所以它們本該在那段統計上一致。實際上：

| 批 | 故障位置（開卡次數） | 每趟故障率 | q̂ |
|---|---|---:|---:|
| A：30 張目錄 | 7、5、7、22（另 2 趟設限於 31） | 4/6 = 0.67 | 0.0388 |
| B：60 張目錄 | **16、17、17** | 3/3 = 1.00 | 0.0600 |

**A 批在前 7 次開卡就死了三次，B 批三趟都活過第 15 次。** 同樣的卡、同樣的順序。
**所以兩批之間有某個不是「卡片內容」的差異，而那個差異就是我加進去的東西。**

### 原因幾乎確定是**目錄大小本身**（讀卡器為目錄裡每張卡持有一張縮圖）

`Source/OpenKoikatsu/OKReaderScreen.cpp` 有一整套按目錄張數擴張的縮圖機制：
`CardThumbs`（`:1304-1305`，收回時逐張 `GiveBackThumb`）、`OKReaderThumbs`（`:1368-1373`，
每張縮圖一份 `Bgra` 像素）、`ThumbsInFlight`、`ThumbGeneration`。

> **目錄從 31 個檔變成 61 個檔，縮圖紋理就約翻倍——在第一張卡被開之前就已經翻倍。**
> 所以 B 批不是「A 批加上更多曝險」，而是**一個起始壓力更高的不同組態**。

這解釋了觀察到的形狀：起始壓力高 ⇒ 更早接近某個資源上限 ⇒ 故障時間變成**近乎決定性**
（139 秒、0.5% 全距），而不是隨機散布。

**而這也是今天第一個把當機和一個具體的、按數量擴張的 UI 資源連起來的證據**，
而且它正落在 `FDreamUIDeferredRelease` 那條線上——縮圖是 UI 紋理。

## 因此三件事要改

1. **不要合併兩批的 q̂。** 合併值 0.0458 建立在可交換性上，而可交換性已被否證。
   A 批的 q̂=0.0388 只適用於**31 個檔的目錄**；B 批的 0.0600 只適用於 61 個檔的目錄。
2. **協定必須把「目錄裡有幾個檔」寫成身分的一部分**（和卡單指紋並列）。
   先前 `fp-rule-4` 記了卡單內容雜湊，但**沒有把「目錄張數會改變起始壓力」當成一個變數**。
3. **「每趟 vs 每卡」這個二分法本身不足**。B 批既不是「每趟一次機會」（3/3 且位置集中），
   也不是「每卡恆定危險率」（8.7×10⁻⁵）。**第三個模型更合適：累積資源壓力跨過一個門檻。**
   照 10a，這是**第 2 類（有強訊號，不足以定因）**——我還沒證明是縮圖，只證明了
   「目錄大小是兩批唯一的系統性差異，而程式確實按目錄大小持有紋理」。

## 下一格（最便宜、能直接驗這件事）

**同樣 61 個檔的目錄，但只開前 30 張就停**。
- 若照樣在約 139 秒／第 16–17 次開卡故障 ⇒ **故障由目錄大小（起始壓力）決定，不是由開了幾張卡**；
- 若變回 A 批那種散布 ⇒ 目錄大小無關，差異在別處。

**這一格的事前預期現在就寫下**，而且它比先前那個「每趟 vs 每卡」更能分辨東西。

# 量 VRAM：RHI 指令全都不印，但讀卡器本來就在記位元組

## 一、五個候選主控台指令，沒有一個可用

| 指令 | 結果 |
|---|---|
| `rhi.DumpMemory` | log 多了 588 行，**但那些是開卡時的非同步紀錄**（`OK eye draw`、`OK head item draw`），不是它的輸出 |
| `rhi.DumpResourceMemory` | 多了 86 行，同樣多半是讀卡器自己的紀錄 |
| `stat rhi` | **1 行**（螢幕統計，不進 log） |
| `r.DumpRenderTargetPoolMemory` | **1 行** |
| `D3D12.DumpTrackedResidentAllocations` | **1 行** |

**而且我的探針量錯了**：我用「log 長了幾行」當作「指令有輸出」，
但開卡的紀錄是非同步寫入的，所以那 588 行**根本不是那個指令產生的**。
這是今天第 N 次「量了旁邊的東西」——這次在我自己剛寫的探針裡，
而它**正是為了避免這種事而寫的**。幸好它的輸出保留了行內容，否則我會以為 `rhi.DumpMemory` 可用。

## 二、真正的量具：讀卡器自己每次換卡都印位元組

```
OK kept GPU textures: released 12 (38.7 MB) from the card just left, keeping 107 (352.2 MB)
```

**每一趟的 log 裡都有**（基線趟 16 行、加長趟 45–46 行），
所以**九趟的 VRAM 曲線早就在磁碟上**，不必加任何儀器、不必花機器時間。

## 三、把九趟的峰值抓出來：**保留的 GPU 紋理位元組也不是門檻，而且方向是反的**

| 趟 | 目錄張數 | 故障 | 峰值保留 MB |
|---|---:|:---:|---:|
| base6_1 | 30 | 是 | 512.6 |
| base6_2 | 30 | 是 | 509.3 |
| base6_3 | 30 | 是 | 512.6 |
| base6_4 | 30 | 是 | 509.3 |
| **base6_5** | 30 | **否** | 407.2 |
| **base6_6** | 30 | **否** | **512.6** |
| ext3_1 | 60 | 是 | 407.2 |
| ext3_2 | 60 | 是 | 407.2 |
| ext3_3 | 60 | 是 | 407.2 |

- **`base6_6` 在 512.6 MB 存活，而 `base6_1`／`base6_3` 在同樣的 512.6 MB 故障。**
- **三趟 60 張目錄全部在 407.2 MB 故障，而 `base6_5` 在同樣的 407.2 MB 存活。**
- 峰值只出現 512.6／509.3／407.2 三個值 ⇒ 這個快取有**上限**（約 512 MB），峰值是撞到上限。

> **所以「保留的 GPU 紋理位元組」不是門檻**，而且 60 張目錄那批**保留得更少卻更會死**——
> 方向相反。這和先前兩個量（`tex` 張數、`actors` 個數）一樣被自己的資料否掉。

**三個候選門檻全部否掉**（張數、角色數、保留位元組），照 10a 都是第 3 類
（這個量不能解釋故障與否），**不是**「記憶體無關」。

## 四、程式裡**已經記著這個當機**，而且記著一個已經做過的緩解

`Source/OpenKoikatsu/OKReaderScreen.cpp:1462-1467`：

> 卡片清單的圖片在工作執行緒解碼、捲出視野就丟掉；圖片活在畫面自己的池子（`ThumbPool`）裡，
> **讀卡器執行期間沒有任何圖片紋理會被回收，所以換 brush 之前建好的 DreamGUI 繪製資料
> 不可能活得比它的紋理久**
> （**2026-11-19：切換卡片來源並快速捲動，約一分鐘後以 GPU 頁錯誤結束**）。

**那就是這個當機**，而且那段註解描述的機制正是
`Found 0 active heaps containing page fault address` 的意思——**繪製資料引用了已經不在的紋理**。
池子是當時的緩解；**故障仍然存在**，所以池子沒有蓋住全部路徑，或成因在別處。

## 五、因此先跑 `ok.ReaderThumbs=0`，而不是目錄大小三格

`:1468` 有一個**為這種比較而存在的旋鈕**：
`ok.ReaderThumbs`，`1` 解碼卡片清單圖片（預設），`0` 完全不解碼（說明文字自己寫著 for comparison runs）。

**為什麼先跑它**：60 張協定是今天唯一可靠的重現（3/3、秒數 0.5% 全距）。
**對一個可靠的重現測旋鈕，三趟就能讀出答案**；對 30 張協定（4/6、位置 5–22）測同一個旋鈕讀不出來。

**到達證據**（前置第 2 項）：`OKReaderPicturesShown()` 在設 brush 的那一行被讀
（`:1456-1457`，`if(!OKReaderPicturesShown()) Texture=nullptr`），
而 `ok.ReaderScreen resources` 會印 `screen thumbPool=N free=N cardThumbs=N …`。
**旋鈕關掉時池子必須保持 0；池子有成長的趟代表旋鈕沒到達那一點，該趟作廢而不是結果。**
為此在驅動裡加了兩次 `ok.ReaderScreen resources`（開卡迴圈前、收尾前）。

**事前登記的判讀**：0/3 全存活 ⇒ 圖片路徑有關；3/3 仍故障 ⇒ 圖片路徑非必要，改跑目錄大小三格；
1/3 或 2/3 ⇒ 照既有規則，「變罕見但還會當」不算進展也不算成因。

## 六、目錄大小三格已就緒，排在後面

`E:/OKPackage/dirsize30`、`dirsize60`、`dirsize90`（硬連結），
**前 10 張完全相同**（同名同位元組），只有目錄張數不同；驅動 `dirsize10x.sh` 只開前 10 張。
它要回答的是「目錄張數」與「開幾張卡」哪個是壓力來源。
但照 `:1758` 的程式，縮圖**只在捲動視窗附近**才常駐（遠的會 `GiveBackThumb` 設回 null），
**所以縮圖數不隨目錄張數線性成長**——我先前那個「61 個檔就翻倍」的說法要收窄：
翻倍的是 `CardThumbs`／`CardPaths` 這些**指標陣列**與卡片按鈕數，不是常駐紋理。

## 縮圖那一格作廢：卡片清單在這個協定裡根本沒建起來

趟 1 確實故障（140.1 秒、第 14 張），但**到達證據不成立**：

```
screen thumbPool=0 free=0 cardThumbs=0 controls=167 pageWidgets=1 cards=0
```

**`cards=0` 表示卡片清單根本沒建起來。** 這個協定是進 1 對 1 互動場景之後在那裡開卡，
**卡片清單畫面從來不是作用中的 UI**，所以 `ok.ReaderThumbs` 在這個協定裡沒有作用點。
另外表裡的旋鈕讀回是空的（`# knob now: ok.ReaderThumbs =`），而先前每一格都會印出
`= "0"  LastSetBy: SystemSettingsIni`——所以連「旋鈕有生效」都沒有證據。

照自己的規矩，那一趟是 **7k 作廢而不是結果**；剩下兩趟停掉，省約 7 分鐘機器時間。
附帶價值：它是 60 張協定的**第 4 次故障**（140.1 秒，對照 138.6／139.2／139.3），
所以那個重現現在是 **4/4、秒數全距約 1%**。

**這也削弱「縮圖占 descriptor 所以 61 張目錄更早當」那個解釋**：卡片清單沒顯示，縮圖就沒解碼。
目錄大小的**觀察**仍然成立，但它的**機制解釋目前沒有依據**。

## bindless descriptor heap：引擎原始碼查核與 32768 的真正來源

`D3D12BindlessDescriptors.cpp:203` 在配置器滿時呼叫 `ResizeGrowAndAllocate`；
`:230-257` 把容量**翻倍**（`CurrentNumDescriptors * 2`，上限 `MaxResourceHeapSize`）並 `GrowCPUHeap`，
配合 `bCPUHeapResized`／`ActiveGpuHeapIndex`／`FinalizeHeapOnState` 在舊新 heap 之間切換。
**所以成長會建新 heap 並退掉舊的**，而還在飛的繪製若引用退掉那份裡的 descriptor，
正好就是 pixel shader 的頁錯誤——和 `Found 0 active heaps containing page fault address` 字面一致。

**更正 32768 的來源**：不是這個專案設的，是**引擎自己的**
`Engine/Config/Windows/BaseWindowsEngine.ini:24` 覆寫了 C++ 預設 `1000000`；
硬體回報 `MaxNonSamplerDescriptors: 1000000`。所以取 **262144（8 倍）**仍遠低於兩者。

### 到達證據與其限制（先申報，照 7j）

- **可驗**：`:155` 在 init 印 `Initializing allocators with %d Resource and %d Sampler descriptors`。
  **log 沒印 262144 的趟作廢。** 而且這個值在 init 被讀，**必須用命令列／ini 設**——
  主控台設會是無聲失效（和 `RHI.TransientAllocator.GarbageCollectLatency` 同一個陷阱）。
- **不可得**：**成功成長完全不印日誌**（`:248` 只在無法再成長時 `Fatal`）。
  所以**這一格無法顯示成長有沒有發生**，對機制點的覆蓋率是 **1/2**。
  照 7j，若 3/3 仍故障，**不得寫成「heap 成長不是成因」**，只能寫成「在 262144 之下故障仍發生」。

# bindless heap 格：趟 1 作廢，因為旋鈕打在錯的 ini 區段

## 一、作廢，不是結果

趟 1 的到達證據自己說了不算：

```
# knob now: D3D12.Bindless.ResourceDescriptorHeapSize = "32768"   LastSetBy: SystemSettingsIni
# heap_init: Initializing allocators with 32768 Resource and 2048 Sampler descriptors
# heap_knob_arrived=0
```

照這一格事前登記的規則（「log 沒印 262144 的趟就作廢」），**這一趟是作廢而不是結果**。
它跑到第 4 張（`04_crowd_C020.png`）才停，是我中止這一格造成的，不是故障；`# faults=0`。
停在那裡省下的機器時間約 20 分鐘（三趟）。

## 二、為什麼沒到達：我打在錯的區段

我用的是 `-ini:Engine:[ConsoleVariables]:D3D12.Bindless.ResourceDescriptorHeapSize=262144`，
但這個值不是從 `[ConsoleVariables]` 來的。查了來源：

```
/e/PhysX/UE5.8/Engine/Config/Windows/BaseWindowsEngine.ini:24
  D3D12.Bindless.ResourceDescriptorHeapSize=32768
section for line 24: [SystemSettings] (at line 15)
```

`LastSetBy: SystemSettingsIni` 正好指著它。所以要壓過它，**覆寫必須打在同一個區段**
（`-ini:Engine:[SystemSettings]:…`），不是 `[ConsoleVariables]`。

**這是「旋鈕讀回」這項前置檢查第二次救回一整格**：
第一次是 `r.RHICmdBypass`（ERROR_LOG 2026-11-19），這次是 bindless heap。
兩次都不是「設了沒效果」，而是**設的地方不對、而讀回會講出來**。

## 三、連帶：旋鈕來源有三種不同的失效方式，不能混為一談

今天已經撞到三種，每一種的徵狀不同：

| 失效方式 | 例子 | 徵狀 |
|---|---|---|
| 值在 init 被讀，主控台設是無聲失效 | `RHI.TransientAllocator.GarbageCollectLatency` | 讀回**是新值**，但程式用的是 init 時的快照 ⇒ 讀回看不出來 |
| 命令列打在錯的 ini 區段 | `D3D12.Bindless.ResourceDescriptorHeapSize` | 讀回**是舊值**＋`LastSetBy` 指出誰贏 ⇒ 讀回看得出來 |
| 旋鈕的作用點在這個協定裡不存在 | `ok.ReaderThumbs`（卡片清單沒建起來） | 讀回可能正常，但**機制點的計數器全是 0** ⇒ 只有作用點的量具看得出來 |

所以「讀回等於新值」**不足以**證明到達；要看的是**那個值實際被使用的地方**留下什麼。


# 路徑排除清單另立一份：[CARD_READER_PATH_EXCLUSIONS.md](CARD_READER_PATH_EXCLUSIONS.md)

今天同一條死路（bindless descriptor heap）以兩個不同的 cvar 名字各被推上「主線」一次，
而第一次取消它的理由就足以否掉第二次。所以排除改成一份獨立清單，每條三欄：
**排除的是哪條程式路徑、依據是哪一行、什麼觀測會讓它復活**。
**沒有第三欄的排除不算排除**，因為那是不可反駁的。提出任何一格之前先查那份清單。

# residency：引擎自己用來「暴露漏掉的 UpdateResidency」的工具，一點都沒動到這個故障

## 一、儀器檢查一趟（`D3D12.ResidencyDebugBudgetMB=128`）

| 項目 | 值 |
|---|---|
| 旋鈕讀回 | `D3D12.ResidencyDebugBudgetMB = "128"`（預設 -1 ＝停用） |
| 終局 | `DEAD after card 16 (16_heroine_keqing.png)`、`faults=1` |
| 秒數 | **139.3 s** |
| 對照（60 張協定基線 4/4） | 138.6／139.2／139.3／140.1 s，開第 14／16／17／17 張 |
| `residency_off_log` / `forced_resident_log` | 0 / 0（所以常駐管理開著、資源真的從 evicted 開始） |
| 峰值保留 | 509.3 MB |

**把常駐預算壓到 128 MB，故障的秒數落在基線四趟的正中間（139.3，全距 1%）、位置也在基線的 14–17 內。**
往早、往晚都沒有移動。

## 二、為什麼這是對 residency 不利的證據，而不只是「沒差」

這個旋鈕不是我挑的方向，是**引擎作者寫給這件事用的**（`D3D12Adapter.cpp:204-212`）：

> 「用小值（例如 128）強迫積極的 eviction／MakeResident 來回，**暴露漏掉的 UpdateResidency 呼叫**
> ——那些呼叫平常被驅動的隱式分頁掩蓋住。」

漏掉 `UpdateResidency` 的資源會被當成「沒在用」而被逐出，所以**預算壓小應該讓它更早故障**。
結果是**完全沒有移動**。照事前登記的判讀，這落在
「秒數不變 ⇒ 預算覆寫在這裡什麼都沒改：要嘛沒到達那條路徑，要嘛逐出壓力不是這個故障的時鐘」。

**覆蓋率照 7j 申報**：旋鈕到達是**有**證據的（cvar 以 `FAutoConsoleVariableRef` 綁定
`GD3D12ResidencyDebugBudgetMB`，而 `D3D12Adapter.cpp:1930` 每次讀的就是它，不是 init 快照）；
**「逐出真的變積極了」沒有觀測**（沒有對應的 log 或統計）。所以這一趟是 **1/2 覆蓋、n=1**，
不能寫成「residency 已排除」，只能寫成
**「引擎指定用來暴露這類漏洞的壓力工具，對這個故障的時間沒有任何影響」**。

因此 `D3D12.ResourcesStartResident=1` 那一格（判別格，腳本已寫好）**降級**：
它測的是「初始常駐狀態」，而上面的壓力測試已經說了逐出壓力不是時鐘。要跑的話它仍然有效，
但不該排在前面。

## 三、順手查完我自己標為缺口的那一條：DreamGUI 的釋放走不走 RHI 的圍欄

查了 `FDreamUIDeferredRelease` 的全部呼叫點：

| 種類 | 呼叫點 | 到期時發生什麼 |
|---|---|---|
| `Hold(FTextureRHIRef)` | `DreamUIDataTexture.cpp:143`、`DreamUIRenderer.cpp:1253` | 丟掉一個 RHI 貼圖參照 ⇒ **走 RHI 的延遲刪除（EOP sync point 圍欄）** |
| `Hold(TRefCountPtr<IPooledRenderTarget>)` | `DreamUICompositor.cpp:408` | 還給 render target 池 ⇒ heap 留著 |
| `Later(TUniqueFunction)` | **只有兩處**：`DreamUIMaterialProxy.cpp:134` 與 `:140`，都是 `delete InProxy` | 直接 `delete` 一個 material proxy |

**所以 DreamGUI 裡唯一不是「丟 RHI 參照」的銷毀，就是 material proxy 的 `delete`。**
而 `DreamUIMaterialProxy.cpp:88-90` 的註解寫的正是這個假設：

> 「……destructor 本身（它放掉其 uniform buffer 為材質持有的那些貼圖 refcount，
> **而 `MainPS` 綁的是同一批貼圖**）。」

**但這裡有一個我必須講明的矛盾**：`delete InProxy` 的 destructor 放掉的也是 **RHI 參照**
（uniform buffer、貼圖），而那些一樣走 `FD3D12DeferredDeleteObject` 的圍欄。
**所以在排除清單第二條成立的前提下，DreamGUI 的任何一條路都不可能在 GPU 用完之前真的釋放記憶體。**
兩者不能同時為真，所以下一步必須先決定哪一個錯：

1. **排除清單第二條錯**（例如那個 sync point 沒覆蓋到相關佇列，或某樣東西不走 `FD3D12DeferredDeleteObject`）；或
2. **故障不是「記憶體被釋放」**，而是別的東西指到一個失效位址（繪製資料裡的指標、
   非 RHI 的配置、或 Aftermath 那句 "heaps" 根本是另一個意思）。

**這個分叉比再轉一個旋鈕重要**，而且兩邊都用讀程式碼就能推進。

## 四、`NeverDeleteProxy` 這一格的前置已齊（含到達證據）

- 旋鈕：`DreamGUI.Experiment.NeverDeleteProxy`（`DreamUIMaterialProxy.cpp:95`，預設 0，
  `ECVF_RenderThreadSafe`、`GetValueOnAnyThread()` ⇒ **主控台設即生效，不是 init 快照**）。
- **到達證據**：`:112` 印 `DreamGUI EXPERIMENT: material proxy leaked on purpose, total=N`
  （前 10 個每個都印，之後每 50 個印一次）。**那個計數沒有成長的趟＝旋鈕沒到達，作廢而不是結果。**
- 另有兩個現成的量具：`DreamGUI.LogDeferredRelease` 印 `deferred release: %d waiting`
  （`DreamUIDeferredRelease.cpp:146-153`），以及隊列第一次 tick 時印的
  `DreamGUI deferred release frames in effect: texture=%d buffer=%d pooled=%d func=%d`。
- 程式裡的註解也已經事先寫好這一格的判讀與界線：
  「若仍故障，destructor 不是觸發點」、「**這絕不能出貨：讓當機消失的洩漏是診斷，不是修復**」。

# `Found 0 active heaps` 很可能是「沒有資料」，不是「沒有堆」——而整場「銷毀 vs 重用」都架在這個零上

## 一、那段報告的完整原文（11-18 的 dump，`20261118-194613-6ae05c77.log:4806-4813`）

```
PageFault: PageFault at VA GPUAddress "0x25C4061000" (GPU 0)
PageFault: Last completed frame ID: -1 (cached: 32150) - Current frame ID: 32153
PageFault: Logging all resource enabled: No
PageFault: Found 0 active tracked resources in 16.00 MB range of page fault address
PageFault: Found 0 active heaps containing page fault address
PageFault: Found 0 released resources containing the page fault address during last 100 frames
DRED: No PageFault data.
```

**第三行是關鍵，而我們（我、協調、f-sceneload）都跳過了它**：
`Logging all resource enabled: No`。

## 二、三個零全部來自同一個沒開的追蹤

印出那三行的是 `D3D12Util.cpp:671-716`，它們查的三個清單是
`FD3D12Adapter::FindResourcesNearGPUAddress`（`D3D12Adapter.cpp:2029`）、
`FindHeapsContainingGPUAddress`（`:2062`）、`FindReleasedAllocationData`（`:2079`）。
三個函式的**全部內容**都包在 `#if TRACK_RESOURCE_ALLOCATIONS` 裡，而真正決定清單裡有沒有東西的是
`IsTrackingAllAllocations()`（`D3D12Adapter.h:458`，由 `D3D12.TrackAllAllocations` 決定，
`ECVF_ReadOnly`、預設 **off**）：

```cpp
// D3D12Resources.cpp:720-744，FD3D12Heap::SetHeap
if ((bForceGetGPUAddress || Adapter->IsTrackingAllAllocations())
    && !(HeapDesc.Flags & D3D12_HEAP_FLAG_DENY_BUFFERS)
    && HeapDesc.Properties.Type == D3D12_HEAP_TYPE_DEFAULT)
{
    ...                                  // 先建一個 placed buffer 才拿得到 heap 的 GPU 位址
#if TRACK_RESOURCE_ALLOCATIONS
    if (bTrack) { Adapter->TrackHeapAllocation(this); }   // ← 只有進得了上面那個 if 才會登記
#endif
```

**追蹤關著 ⇒ 絕大多數 heap 從來沒進過 `TrackedHeaps`，連 GPU 位址都沒去取** ⇒
`FindHeapsContainingGPUAddress` 當然回 0。同理，`0 active tracked resources` 與
`0 released resources ... during last 100 frames` 也都是空清單的 0。
最後一行 `DRED: No PageFault data.` 更是字面上的「沒有資料」。

## 三、所以要撤回的是什麼

**「出錯的位址落在一塊已經不存在的記憶體裡」這個讀法沒有依據**——
那個零不是「找遍了都沒有」，是「沒有在找」。照 7g（**不要把缺資料印成一個值**），
這是今天第二次踩到同一個形狀：上一次是把開卡的非同步 log 行數當成主控台指令的輸出。

**連帶撤回的推論**（之前都寫成「字面一致」）：
- 「`Found 0 active heaps` 和 descriptor heap 被退掉字面一致」——bindless 那條死路一半來自這個零；
- 「池化重用解釋不了，所以一定是真正的銷毀」——**兩邊都解釋不了這個零，因為它什麼都沒說**；
- 「資源記憶體 heap vs descriptor heap」的爭論——**在沒有資料的情況下無法區分**。

**還站得住的**：故障本身（`Error_DMA_PageFault`）、`MainPS` 的身分、位址
`0x25C4061000`、以及兩個協定的重現率。那些不依賴這三個零。

## 四、下一格因此換成一個儀器，而不是機制旋鈕

`D3D12.TrackAllAllocations=1`（`D3D12Adapter.cpp:191-195`，`ECVF_ReadOnly` ⇒ 必須命令列／ini）。
開了之後同一份報告會印出：

- 故障位址 16 MB 範圍內**每一個**活著的資源：位址區間、大小、**距離故障位址多遠**、
  是不是 transient、**名字**、以及 resource desc（`D3D12Util.cpp:682-698`）；
- **包含**故障位址的每一個 heap：位址、大小、**名字**（`:705-711`）；
- **最近 100 幀內被釋放**而包含該位址的資源（`:716` 起，照釋放時間倒序）。

**到達證據是現成且在機制點上的**：同一份報告的第三行會從
`Logging all resource enabled: No` 變成 **`Yes`**。印 `No` 的趟作廢而不是結果。
**這是今天第一個覆蓋率 2/2 的格子**（旋鈕到達有證據、要觀測的量也正是它產生的）。

**先申報它的風險**：全量追蹤會為每個 DEFAULT heap 多建一個 placed buffer 去取 GPU 位址，
並記錄每筆配置（可選 callstack），**所以它會改變時間與記憶體行為，可能移動或蓋掉這個重現**。
事前登記：

- **仍然故障 ⇒ 報告直接點出位址屬於誰**（活著的資源、含它的 heap、或最近釋放的那一筆），
  「銷毀 vs 重用 vs 從未常駐」當場分開，不必再猜；
- **不再故障 ⇒ 這一格沒有讀數**（不是修好）。那時改用 60 張協定多跑幾趟確認是不是真的被壓掉，
  而不是把它當成修復。

# 追蹤開啟後的報告：故障位址落在「最近 100 幀內已釋放」的貼圖與它背後的 64 MB PoolAllocator Heap 裡

**趟 1 乾淨（60 張全開）、趟 2 與趟 3 故障**（138.2 s 第 16 張、139.3 s 第 15 張，在基線帶 138.6–140.1 內）。
所以「儀器一開就不發生、故障對時序敏感」那條判讀**作廢**——1/3 乾淨只是既有的趟間變異，
而我沒有把它寫成結論。三趟的 `tracking_arrived=1`、身分與基線相同
（`dll=11-19_16:25:48`、`cards=ec4082d53b456b86`）。

完整報告存在 `Saved/Reports/card-reader-dreamgui/track-allocations-trip2.txt` 與 `-trip3.txt`。只列事實：

```
PageFault: PageFault at VA GPUAddress "0x2606A01000" (GPU 0)
PageFault: Last completed frame ID: -1 (cached: 20795) - Current frame ID: 20798
PageFault: Logging all resource enabled: Yes
PageFault: Found 0 active tracked resources in 16.00 MB range of page fault address
PageFault: Found 0 active heaps containing page fault address
PageFault: Found 2 released resources containing the page fault address during last 100 frames
	GPU Address: [0x2602E00000 .. 0x2606E00000] - Size: 67108864 bytes, 64.00 MB - FrameID: 20777 - DefragFree: 0 - Transient: 0 - Heap: 1 - Name: PoolAllocator Heap - Desc: Unknown
	GPU Address: [0x2606680000 .. 0x2606BE0000] - Size: 5636096 bytes, 5.38 MB - FrameID: 20754 - DefragFree: 0 - Transient: 0 - Heap: 0 - Name: Texture2D_1003 - Desc: Texture 1024x1024x1 DXGI_FORMAT_B8G8R8A8_TYPELESS
[2026.11.19-12.22.49:259][798]LogD3D12RHI: Error:
```

```
PageFault: PageFault at VA GPUAddress "0x260FF71000" (GPU 0)
PageFault: Last completed frame ID: -1 (cached: 20052) - Current frame ID: 20055
PageFault: Logging all resource enabled: Yes
PageFault: Found 0 active tracked resources in 16.00 MB range of page fault address
PageFault: Found 0 active heaps containing page fault address
PageFault: Found 2 released resources containing the page fault address during last 100 frames
	GPU Address: [0x260C800000 .. 0x2610800000] - Size: 67108864 bytes, 64.00 MB - FrameID: 20017 - DefragFree: 0 - Transient: 0 - Heap: 1 - Name: PoolAllocator Heap - Desc: Unknown
	GPU Address: [0x260FDF0000 .. 0x26100A0000] - Size: 2818048 bytes, 2.69 MB - FrameID: 19995 - DefragFree: 0 - Transient: 0 - Heap: 0 - Name: Texture2D_978 - Desc: Texture 1024x512x1 DXGI_FORMAT_B8G8R8A8_TYPELESS
[2026.11.19-12.26.22:289][ 55]LogD3D12RHI: Error:
```

DRED 兩趟字面相同：`Commandlist "FD3D12CommandList 29 (GPU 0)" on CommandQueue "3D Queue (GPU 0)", 138 completed of 244`，
其後是交替的 `DrawIndexedInstanced` / `ResourceBarrier`（Op 38..68），接 `EndEvent`、`WriteBufferImmediate`。

**可直接讀出的數字**（不是解釋）：趟 2 的貼圖釋放於第 20754 幀、heap 於 20777，故障時 current frame 20798
⇒ 相距 **44 幀**與 **21 幀**；趟 3 的貼圖釋放於 19995、heap 於 20017，故障時 20055 ⇒ 相距 **60 幀**與 **38 幀**。
兩趟「含故障位址的已釋放資源」都是 2 筆，都是一張 `B8G8R8A8_TYPELESS` 貼圖加上包住它位址區間的 64 MB
`PoolAllocator Heap`；貼圖尺寸與名字兩趟不同（1024x1024 `Texture2D_1003`、1024x512 `Texture2D_978`）。
**而這一次追蹤是開的，active 資源與 active heap 仍然是 0。**

# 擁有者那一格：第三趟給出不同的報告（0 筆已釋放），而那可能只是窗口 100 幀太短

## 一、這一趟的事實（`D3D12.TrackAllAllocations=1` ＋ `DreamGUI.LogStaleTextures=1`）

```
FAULTED after card 7 (07_crowd_C055.png)   fault_secs: 92.2
PageFault at VA GPUAddress "0x5BF051000" (GPU 0)
Last completed frame ID: -1 (cached: 10839) - Current frame ID: 10842
Logging all resource enabled: Yes
Found 0 active tracked resources in 16.00 MB range of page fault address
Found 0 active heaps containing page fault address
Found 0 released resources containing the page fault address during last 100 frames
DRED: No breadcrumb head found.      ← 這一趟沒開 DRED
DRED: No PageFault data.
Video Memory Stats from frame ID 10841:
    Local Budget: 31419.00 MB    Local Used: 2219.39 MB
# stale_hits=0
```

**和前兩趟不同的兩件事**：故障在 **92.2 秒、第 7 張**（前兩趟是 138.2／139.3 秒、第 15–16 張），
而且**「含故障位址的已釋放資源」是 0 筆**，儘管**追蹤是開的**。

## 二、那個 0 不能直接讀成「沒有東西被釋放」——窗口只有 100 幀

`GTrackedReleasedAllocationFrameRetention = 100`（`D3D12Adapter.cpp:49-55`，
cvar `D3D12.TrackedReleasedAllocationFrameRetention`，`ECVF_RenderThreadSafe`，以參照綁定）。
**100 幀在這裡大約只有 1.5 秒**，而前兩趟點到名的那兩筆，釋放距故障是 **21–60 幀**——**已經接近窗口邊緣**。
所以「0 筆」有兩種可能，而這一趟分不出來：

1. 那個位址的東西**在 100 幀之前**就被釋放了（窗口太短）；
2. 那個位址**從來不屬於任何被追蹤的配置**。

**這正是前面那個「把缺資料印成一個值」的同一個形狀**，只是這次換成「窗口外」而不是「沒在記錄」。
所以下一趟把 `D3D12.TrackedReleasedAllocationFrameRetention=4000`（約一分鐘）打開再看。

## 三、`stale_hits=0`，而這個 0 的強度要講清楚

`DreamGUI.LogStaleTextures`（`DreamUIBaseShaders.cpp:25`）在**內建繪製解析每個貼圖槽的那一行**檢查
`IsValid()`／`IsUnreachable()`。這一趟 0 命中，**和那段程式自己登記的預期一致**
（`UTexture` 的 `IsReadyForFinishDestroy` 會等資源釋放 fence）。

**但這個 0 不能當成「旋鈕到達」的證據**：那一行只在真的解析到過期貼圖時才印，
**沒命中與沒生效在 log 上長得一樣**。今天第二次踩到「量具只在壞事發生時才自我證明」。

## 四、`DreamGUI.LogDeferredRelease` 不是旋鈕，而它要的那份紀錄不存在

它是 `FAutoConsoleCommand`（`DreamUIDeferredRelease.cpp:146`），只印一個**數量**
（`deferred release: %d waiting`）。`FDreamUIDeferredRelease` 對每一筆到期項目**什麼都不印**
（沒有名字、沒有位址、沒有幀號）。所以**「那張被釋放的貼圖有沒有出現在 DreamGUI 的釋放紀錄裡」做不到**，
因為那份紀錄不存在。要做得在 `Tick_RenderThread` 的 `Due` 迴圈加一行 log——那是共用外掛的改動，沒有自己動。

## 五、命名線索（交給程式碼那一側，不在這裡往下推論）

報告裡的名字是 `Texture2D_1003`／`Texture2D_978`，**那是 UE 對 runtime 建立的 `UTexture2D` UObject
自動取名的樣子**；而 `UTexture2D::CreateTransient` 的**預設格式正是 `PF_B8G8R8A8`**，
與報告的 `B8G8R8A8_TYPELESS` 相符。`CreateTransient` 在本專案的使用檔案有六個，含
`Source/OpenKoikatsu/OKReaderScreen.cpp`。**建立點與綁定的追查歸程式碼那一側，這裡只記線索。**

## 第四趟（`D3D12.TrackedReleasedAllocationFrameRetention=4000`）：相距不是 21–60 幀，是**兩千八百多幀**

```
FAULTED after card 27 (27_ref_lan.png)   fault_secs: 213.2
PageFault at VA GPUAddress "0x260F161000" (GPU 0)
Last completed frame ID: -1 (cached: 35119) - Current frame ID: 35122
Logging all resource enabled: Yes
Found 0 active tracked resources in 16.00 MB range of page fault address
Found 0 active heaps containing page fault address
Found 2 released resources containing the page fault address during last 100 frames
  [0x260B200000 .. 0x260F200000] 67108864 bytes 64.00 MB FrameID: 32290 Heap: 1  Name: PoolAllocator Heap
  [0x260F140000 .. 0x260F1A0000]   393216 bytes  0.38 MB FrameID: 32268 Heap: 0  Name: Texture2D_1413
        Desc: Texture 256x256x1 DXGI_FORMAT_B8G8R8A8_TYPELESS
# stale_hits=0      # tracking_arrived=1
# retention_logconfig: CVar [[D3D12.TrackedReleasedAllocationFrameRetention:4000]] deferred - dummy variable created
```

**相距**：貼圖釋放於第 **32268** 幀、heap 於 **32290**，故障時 current frame **35122**
⇒ **2854 幀**與 **2832 幀**（約 40 秒、約 5 張卡之前）。

### 這一趟推翻了我自己上一節的數字，而且推翻的方式值得記

1. **先前量到的「21–60 幀」是窗口造成的假象。** 預設 `retention=100` 只保留 100 幀內釋放的紀錄，
   所以**凡是更早釋放的都不會出現**，而出現的那些必然落在 21–60 幀這個靠邊的範圍裡。
   把窗口開到 4000 之後，真正的相距是**兩千八百多幀**。
   **「不是圍欄差幾幀，是圍欄沒管到」這個推論的方向沒變，但支撐它的數字從 21–60 換成約 2850。**
2. **而那句話裡的「last 100 frames」是寫死的字串**
   （`D3D12Util.cpp:716` 的格式字串裡就是 `100`，不讀 cvar）。
   所以這一趟的輸出字面上自相矛盾：它說「最近 100 幀」，卻列出 2854 幀前釋放的東西。
   **到達證據反而是這個矛盾本身**——只有窗口真的變大才可能列出窗口外的紀錄。
   **這是今天第三個「印出來的數字不是真正的值」**：第一個是 `Found 0`（沒在記錄），
   第二個是量具只在壞事發生時自我證明，這是第三個（寫死的窗口大小）。
3. **第三趟那個「0 筆已釋放」因此有了解釋**：那一趟窗口只有 100 幀，而真正的釋放在**兩千多幀前**，
   所以 0 筆是**窗口外**，不是「沒有東西被釋放」。

### 四趟的共同形狀（事實，不含解釋）

| 趟 | 位置／秒數 | 故障位址 | 已釋放的貼圖 | 相距幀 | 同時被釋放的 heap |
|---|---|---|---|---|---:|
| 2 | 第 16 張／138.2 s | `0x2606A01000` | `Texture2D_1003` 1024×1024 BGRA8_TYPELESS | 44 | 64 MB PoolAllocator（21 幀） |
| 3 | 第 15 張／139.3 s | `0x260FF71000` | `Texture2D_978` 1024×512 BGRA8_TYPELESS | 60 | 64 MB PoolAllocator（38 幀） |
| 擁有者格 | 第 7 張／92.2 s | `0x5BF051000` | （窗口外，0 筆） | — | — |
| 保留窗口格 | 第 27 張／213.2 s | `0x260F161000` | `Texture2D_1413` **256×256** BGRA8_TYPELESS | **2854** | 64 MB PoolAllocator（**2832**） |

- **四趟都是 `B8G8R8A8_TYPELESS` 的 `Texture2D_<數字>`**，尺寸每趟不同（1024×1024、1024×512、256×256）。
- **每一次都伴隨同一種 64 MB `PoolAllocator Heap` 被釋放**，而故障位址落在它的區間內。
- `stale_hits` 四趟都是 0（而這個 0 不能當到達證據，見上一節）。
- 那張貼圖的名字在整份 log 裡**只出現一次**，就是故障報告這一行——所以 log 本身不含它的建立或釋放紀錄。

## 建立點對上了：故障的那些貼圖是卡片的 runtime 角色貼圖（`KKTextureRuntime`）

**三件事同時對上**（事實，不含機制解釋）：

| 線索 | 報告裡的樣子 | 程式裡的樣子 |
|---|---|---|
| 名字 | `Texture2D_1003`／`_978`／`_1413` | `UTexture2D::CreateTransient(..., PF_B8G8R8A8, NAME_None, ...)`（`KKTextureRuntime.cpp:240-241`，另 `:96`）⇒ UObject 自動取名 `Texture2D_<數字>` |
| 格式 | `DXGI_FORMAT_B8G8R8A8_TYPELESS` | 三個建立點都寫死 `PF_B8G8R8A8` |
| 尺寸 | 1024×1024、1024×512、256×256（**每趟不同**） | 尺寸來自卡片自己的 mip（`Entry.Mips[First].Width/Height`）⇒ **隨卡片內容而變** |

**而釋放是整批的、發生在換卡時**：`KKPreviewActor.cpp:8116-8126` 在每次卡片載入完成後呼叫
`OKReleaseStaleRecentRuntimeTextures()` 與 `OKReleaseStaleKeptRuntimeTextures()`
（`KKTextureRuntime.cpp:389` 起），然後印出那行量具：
`OK kept GPU textures: released N (X MB) from the card just left, keeping N (Y MB)`。

### 用尺寸排除掉的候選（事實）

| 建立點 | 尺寸 | 對得上嗎 |
|---|---|---|
| `KKTextureRuntime.cpp:96/240/241`（卡片角色貼圖） | 依卡片 mip，可變 | **對得上**（名字＋格式＋可變尺寸） |
| `OKReaderScreen.cpp:1435`（卡片清單縮圖） | **固定 288×402**（`TileWidth/TileHeight`，而且尺寸不符就回 `nullptr`） | **排除**（尺寸不符；且這個協定 `cards=0`，清單沒建起來） |
| `OKHScene.cpp:4722`（套裝卡圖片） | 依 PNG，可變 | 尺寸可能對上，但要那個面板被打開過才會建 |
| `OKHScene.cpp:2481` | 固定 128×128 | 排除 |
| `OKEyeCameraAudit.cpp:74`、`OKEyeDullAudit.cpp:61` | 固定 **256×256** | 第四趟那張是 256×256，所以**尺寸上無法排除**；但這兩個是 audit 工具的路徑 |
| `OKGalleryWidget.cpp:140/1431`、`OKGalleryAppearance.cpp:70` | 依 PNG／APNG 影格 | 尺寸可能對上 |

**所以尺寸只排除掉兩個，名字樣式對所有 `CreateTransient` 都一樣**——`Texture2D_<數字>` 不足以單獨指認是哪一個建立點。
要再縮小，需要在建立與釋放兩處印出名字與尺寸（我們自己的程式碼，比改共用外掛影響面小），
或由程式碼側把「誰把這種貼圖交給 UI 繪製」釘住。

### 相距約 2850 幀這件事與上面的對照

第四趟的貼圖釋放於第 32268 幀、它的 64 MB pool heap 於 32290，故障於 35122。
一趟約 8 秒開一張卡、約 70 幀／秒 ⇒ **2854 幀約等於 5 張卡之前**。
也就是說，**被釋放的那張貼圖不是「剛離開的那張卡」的，而是更早幾張卡的**；
而每次換卡都會跑一次上面那個整批釋放。這一段是從兩個數字相除得來的，不是機制結論。

# 完整的生命週期鍊量到了：換卡 sweep 放掉強參照、3 幀後記憶體被釋放、105 幀後 GPU 還在取樣那個位址

## 一、同一張貼圖的六個時間點（全部來自同一趟的 log，不是推論）

```
frame 22948   created                      Texture2D_1407 256x256 BGRA8      ← KKRuntimeMaterial.cpp:378（KKRuntimePose）
frame 22948   kept                         進入 512 MB 的 TStrongObjectPtr 快取（bytes=349525）
frame 22955   census: alive
frame 23322   census: alive
frame 24298   census: alive（同一幀最後一次）
frame 24298   let go(stale on card switch)  ← OKReleaseStaleKeptRuntimeTextures 把強參照移出陣列
frame 24301   D3D12 released the allocation（報告的 FrameID，比放手晚 3 幀）
frame 24326   64 MB PoolAllocator Heap released（比貼圖晚 25 幀）
frame 24406   PageFault at 0x2588DC1000，落在 [0x2588DA0000 .. 0x2588E00000] 之內
```

**所以：強參照在換卡 sweep 被移出 → 3 幀後記憶體真的被釋放 → 再過 105 幀，GPU 仍然在取樣那個位址。**
這是 use-after-free，而擁有者、釋放點、時間差三件現在都是量到的。

## 二、這一趟的其他數字

| 項目 | 值 |
|---|---|
| 終局 | `DEAD after card 22`、`fault_secs: 202.1` |
| 建立紀錄 | **1300 筆**（`OK kept texture life: created`） |
| 放手紀錄 | **1537 筆**＝換卡 sweep **1421** ＋ 超 512 MB 淘汰 **116** |
| 故障那張 | `Texture2D_1407` 256×256 `B8G8R8A8_TYPELESS`、0.38 MB |
| 放手 → 記憶體釋放 | **3 幀** |
| 貼圖釋放 → heap 釋放 | **25 幀** |
| 記憶體釋放 → 故障 | **105 幀** |

**對照先前四趟的「相距」**（44／60／2854／1148 幀）：那些是用**報告的 FrameID** 減故障幀，
而現在知道**放手與釋放只差 3 幀**，所以那些差距量的其實是「**釋放之後又畫了多久才撞上**」。
**而它每趟都不同（105～2854 幀），這正是「位置與秒數會變」的來源。**

## 三、前面兩趟我找錯模組，這是這一天最大的量測錯誤

我一路只 grep `KKUnityBundle` 與 `Source/OpenKoikatsu`，而**真正的建立與釋放都在 `KKRuntimePose`**：

- 建立：`KKRuntimeMaterial.cpp:378`，`CreateTransient(T.Mips[First].Width, T.Mips[First].Height, PF_B8G8R8A8)`；
- **釋放：`OKReleaseStaleKeptRuntimeTextures` 本身就在同一個檔**（`:265`），管一個
  **512 MB、以 `TStrongObjectPtr` 持有**的快取（`:236`），`KKPreviewActor` 換卡時呼叫；
- 另有 `:227` 的 `TMap<FString, TWeakObjectPtr<UTexture2D>> RuntimeTextureCache`（**弱**參照，不持有）。

**所以先前「`life_released=1`」不是「幾乎沒有釋放」，而是我插在另一個模組的另一條 sweep 上。**
而揭穿它的是**普查與建立紀錄的差集**：1439 張活著的 transient 貼圖對上我只印出的 87 筆。
**量具自己的覆蓋率要用另一個量具去查**——這是今天第三次「量了旁邊的東西」，也是最貴的一次（兩次建置、三趟）。

## 四、現在缺的只有一件：誰在釋放之後還拿著那個位址

已知的反面事實：
- 我們的程式**沒有長期保存裸 `FRHITexture*`**（`KKTextureRuntime` 只有兩處，都在 render command 內當場用完）；
- 快取持的是 `TStrongObjectPtr`（移出即可回收）、identity 快取持的是 `TWeakObjectPtr`（不延命）；
- DreamGUI 的延遲釋放佇列放掉的都是 `DreamUIDataTexture_N`，**不是**這些 `Texture2D_<數字>`。

所以剩下的是：**在 sweep 之後 105～2854 幀之間，每幀都還在畫的那個綁定裡，存的是這張貼圖的位址。**
下一步要查的是材質／MID／uniform buffer／shader binding 這一側——那是修法要動的地方。

# 三題：貼圖怎麼交給材質、換卡時 MID 怎麼處理、sweep 之前有沒有清引用（純讀碼）

## 一、卡片貼圖是怎麼交給材質的

只有一條路：**`SetTextureParameterValue` 到一個當場新建的 MID**。

```
KKRuntimeMaterial.cpp:378  CreateTransient(W,H,PF_B8G8R8A8)        ← 貼圖在這裡誕生
      ↓ 以 UTexture2D* 陣列往下傳（TConstArrayView<UTexture2D*>）
KKRuntimeSharedMaterial.cpp:419  UMaterialInstanceDynamic::Create(Parent,GetTransientPackage())
KKRuntimeSharedMaterial.cpp:420  for(const auto& T:B.Textures) M->SetTextureParameterValue(T.Key,Textures[T.Value]);
```

讀卡器自己另有幾處同樣形狀的（`KKPreviewActor.cpp:3701/4551/4662/4727/5190/5244/5274`），
差別只在 Outer 給的是 **元件或 Actor**（`Create(Mat,Comp)`、`Create(Parent,this)`），然後
`Comp->SetMaterial(Slot,Dynamic)`。

所以材質那一側持有貼圖的只有兩個東西：

1. **MID 的 `TextureParameterValues`**（`UPROPERTY`）—— GC 看得見，會延命；
2. **`FMaterialInstanceResource` 在 render thread 上的 `const UTexture*`** —— **裸指針**，GC 看不見。

## 二、換卡時 MID 怎麼處理：整個丟掉重建

**不沿用。每次載入、每個部件都新建一個。**

- 全專案 `OKCreateRuntimeSharedMaterial` 只有 `:419` 一個 `UMaterialInstanceDynamic::Create`，沒有任何
  MID 快取：grep `TMap<...UMaterialInstanceDynamic>`、`TStrongObjectPtr<UMaterialInstanceDynamic>`、
  `MaterialCache`、`SharedMaterials` 在這些檔案裡**都沒有命中**。
- 唯一的重用是**同一次載入之內**的去重（`OKCrowdRuntimeScene.cpp:798` 比對 identity／FaceClass 相同就沿用
  `E.Materials[Match]`，`:825` 的 `OutlineSlots` 同理）。跨卡沒有。
- `KKRuntimeMaterial.cpp` 全檔 **`SetTextureParameterValue` 命中 0 次**——它只生產貼圖，從不改既有材質的綁定。

**而這一題有一個比讀碼更硬的證據：記憶體真的在放手後 3 幀被釋放。**
MID 的 `TextureParameterValues` 是 `UPROPERTY`。若換卡後還有任何一個活著的 MID 指著那張貼圖，
GC 就**不可能**回收它。它被回收了，所以那一刻**沒有任何 GC 看得見的材質引用存在**。
`KKRuntimeMaterial.cpp:230` 的註解本來就這樣寫：「*the materials of the card just left are gone*」——
量到的 3 幀把這句話從設計假設變成事實。

## 三、sweep 把 `TStrongObjectPtr` 移出之前有沒有清引用：**沒有，確認的反面事實**

`OKReleaseStaleKeptRuntimeTextures`（`:265`）全身只有三件事：倒著走陣列、看 `bTouched`、`RemoveAt`。

- 沒有 `SetTextureParameterValue`、沒有 `MarkRenderStateDirty`、沒有 `CacheUniformExpressions`、
- 沒有 `FlushRenderingCommands`、沒有 `ENQUEUE_RENDER_COMMAND`、沒有任何 render thread 同步。

它是**純 game thread 的記帳**。預期的「沒有」成立。

## 四、這三題把嫌疑縮到哪裡

既然 GC 回收成功 ⇒ **換卡後活著的 MID／元件不可能是那個消費者**（它們若活著，貼圖就不會被釋放）。
而我們的程式**也沒有長期保存裸 `FRHITexture*`**：全專案只有三處（`KKRuntimeMaterial.cpp:372`、
`KKTextureRuntime.cpp:149/197`），**三處都在 render command 裡當場讀完就丟**，沒有存起來。
`FMaterialRenderProxy` 也沒有任何快取持有（grep 0 命中）。

所以剩下的嫌疑只在 **GC 看不見、但 GC 回收時應該要被一起拆掉的那一側**：
`FMaterialInstanceResource` 的裸 `const UTexture*`、它的 uniform expression cache，
或已錄好的 mesh draw command。**換卡後 105～2854 幀之間每幀都還在畫的那個綁定，就在這裡面。**

這一節是讀碼，沒有新建置、沒有新趟數。

# 交接反查這一格：事前預期（在建置之前寫下）

## 要量的

每張卡片貼圖在 `SetTextureParameterValue` 那一刻記一條「交給了誰」（貼圖名 → MID 名 → 參數名 → 幀），
然後在 `OKReleaseStaleKeptRuntimeTextures` 把強參照移出的那一刻，對同一張貼圖反查：
它曾交給哪些 MID、那些 MID 現在還在不在、還在的話那個參數現在指向什麼。

## 事前預期（三種結果，各自指向不同的修法檔案）

| 量到 | 讀法 | 修法會在哪 |
|---|---|---|
| **A：MID 還活著，參數已換成新卡的貼圖** | game thread 乾淨，舊位址只留在 render thread 那份 `FMaterialInstanceResource`／已建好的 uniform buffer 裡，直到 uniform expressions 重算 | sweep 之前（或換參數之後）強制 `CacheUniformExpressions`／`MarkRenderStateDirty` |
| **B：MID 還活著，參數還指著這張**（即將被釋放的那張） | 那就不是「沒人指著」，而是有人指著卻讓它被回收——`UPROPERTY` 本該延命，所以表示那個 MID 自己已經不可達（GC 一起收） | 元件／MID 的擁有關係那一側 |
| **C：MID 已經不在了** | 消費者不在材質這一層 | 元件或 mesh draw command 的快取那一側 |

協調押 **A**，我也押 A——理由是 GC 成功回收了貼圖，這表示放手那一刻沒有任何 GC 看得見的材質引用，
而「MID 活著但參數已改」正好同時滿足這兩件（MID 可達、但它不再指向舊貼圖）。

**但 A 有一個我現在就看得出來的內部矛盾，所以要特別注意**：若 MID 還活著且參數已改，
那 `SetTextureParameterValue` 本身就會走 UE 自己的 `CacheUniformExpressions`／render state 更新路徑
（它不是只改一個 `TMap`）。若量到 A 而修法「強制重算」又無效，那表示重算有發生、但**舊位址還在別處**——
那時要回頭看的是 draw command 與 shadow／outline 那幾條另外建的 MID（`KKPreviewActor.cpp` 的七處）。
**先把量測做出來，不要先寫修法。**

## 這一格不做什麼

`ok.RuntimeTextureRelease=0` 那一格**作廢，協調拍板**：它要證的「故障需要這條釋放路徑」，
放手→3 幀釋放→105 幀後仍在取樣的鍊子已經證了，再花一次建置加三趟確認已知的事不值得。

# 交接反查這一趟：三個預期全部落空，而落空的方式把候選 A 直接淘汰了

趟次：60 張卡單、`FAULTED after card 15`（`15_heroine_jeanne.png`）、`fault_secs: 146.8`、
`tracking_arrived=1`、交接 10246 筆、反查 7709 筆。log：
`E:\OpenKoikatsu\Saved\Logs\CardReader\20261119-221813-716b80e4.log`

## 一、放手那一刻，材質還活著而且**還指著這張貼圖**

| 反查結果 | 筆數 |
|---|---:|
| `ALIVE` 且 `same=1`（參數仍指著即將被放手的那張） | **7187** |
| `ALIVE` 且 `same=0`（參數已指向別張） | **4** |
| `mid=GONE` | 506 |
| 沒有交接紀錄 | 12 |

故障那張 `Texture2D_507` 的六條反查**全部**是 `ALIVE same=1`：

```
created / kept                      frame 9245
handoff -> MID_M_KoikanoClothesOpaque_55,56  param=_MainTex   frame 9246
handoff -> ..._62,63                         param=_MainTex   frame 9438
handoff -> ..._69,70                         param=_MainTex   frame 9568
let go(stale on card switch)                                  frame 10356
lookup  x6: ALIVE  param=_MainTex  now=Texture2D_507  same=1  frame 10356
let-go watch: unreachable_at_frame=16894  (after=6538)
```

**所以「換卡 sweep 放手 ⇒ 沒有任何材質再指著它」是錯的。** 放手之後那六個 MID 都還在、都還指著它，
而貼圖一直到 **6538 幀之後**才變成不可達。

## 二、因此**候選 A（在 sweep 上加 fence）不必建置了**

頁錯誤報告說 `Texture2D_507` 的配置在 **FrameID 16815** 釋放，故障在 **frame 17775**；
而 sweep 放手是 **10356**。**放手與釋放相距 6459 幀**——sweep 的放手根本不是釋放點，
fence 門控一個不是釋放點的地方，擋不到任何東西。**這一趟省掉了那次建置與三趟驗收。**

## 三、第十二條的那條排除要收回（它自己寫的失效條件被打中）

第十二條用「記憶體在放手後 3 幀真的被釋放」推出「放手那一刻不存在任何 GC 看得見的材質引用」。
**這一趟直接量到那個前提是錯的**：放手時有 7187 筆 `ALIVE same=1`，而釋放是 6459 幀之後。

**先前那個「3 幀」只是一張貼圖、一趟的巧合，不是定律**——而我把 n=1 的時間差當成了定律，
**這正是我自己登記過的「單趟不足以下結論」那條規則**。方法（用系統自己的全域判斷當排除依據）照留，
**但這一次的套用作廢**：GC 回收的時機由那些 MID 何時變成不可達決定，而不是由 sweep 決定。

## 四、MID 的衝突：量測結果是「兩種都有，在不同的站點」

- **同一個 `(mid, param)` 收到多於一張貼圖的次數：`0`。** 所以在 `KKRuntimeSharedMaterial` 這條路上
  **沒有任何參數被重新指向**，每個 MID 的每個參數只被設定一次。`MID_...Opaque_55` 收到六張貼圖，
  但是六個**不同的參數**（`_RampG`／`_Texture2`／`_liquidmask`／`_MainTex`／`_DetailMask`／`_NormalMap`），
  同一幀設定完就不再變——所以我先前統計的 `mids_carrying_multiple_texs=2549` **是個被混淆的指標**
  （一個 MID 本來就有很多張貼圖參數），**它不能當成重用的證據**，決定性的是 `(mid,param)` 那個 0。
- **但那 4 筆 `same=0` 證實了 f-sceneload 的站點**：`_AlphaMask` 在四個 MID 上被改成了 `Texture2D_159`，
  而我的交接 log **沒有裝在**讀卡器自己那七處 `SetTextureParameterValue` 上。
  所以那 4 筆是「別的站點改了參數」留下的痕跡，正是它指的
  `KKPreviewActor.cpp:5241-5246` 的 `SetSharedTextureParameter`。**它那條讀法在那個站點上成立。**
- 而新事實是**兩邊都沒料到的**：舊 MID **不會被銷毀**。frame 9246 建的 MID 到 10356 還活著、還指著舊貼圖。

## 五、這一趟的量測邊界（照 7j 先宣告，不要當成沒有的證據）

- **`after=` 是上界，不是確值**：`OKPollLetGoWatch` 只在 `KeepRecentRuntimeTexture` 與 sweep 開頭輪詢，
  兩者都集中在載入期間，所以兩次輪詢之間可能隔上千幀。`unreachable_at_frame=16894` 只表示
  「**到這一幀時已經不可達**」。釋放幀 16815 落在前一次輪詢與 16894 之間，
  **所以這一趟還分不出「釋放先於回收」或「回收造成釋放」**。要分，輪詢得改成每幀一次。
- **`ALIVE` 比「可達」弱**：`TWeakObjectPtr::Get()` 對已不可達、只是還沒被收的物件也回傳非 null。
  要判斷那是真引用還是屍體，需要「那個 MID 在不在某個活著的元件材質槽裡」——
  **那一欄的程式已經寫好（`OKBuildMidOwnerIndex`，每幀最多建一次），這一趟的執行檔還沒有它。**
- 交接 log 只覆蓋 `KKRuntimeSharedMaterial` 的綁定（10246 筆）；讀卡器自己的七處沒裝。

## 六、下一步（按這一趟的結果，不是按原計畫）

1. **候選 A 淘汰**，不建置。
2. 下一次建置帶兩件：已寫好的 **owner 欄**（判 `ALIVE` 是真引用還是屍體，以及是否掛在
   `BodyMesh`／`HeadMesh` 這兩個持久元件上），與 **每幀輪詢的 let-go watch**（把釋放與回收的先後分開）。
3. 真正要回答的問題已經換了：**不是「誰在 sweep 之後還拿著它」，而是
   「那六個 MID 為什麼到換卡之後還活著、還指著舊貼圖，而它們是誰在畫」。**

# owner／ordering 那一趟：釋放確定是 GC 做的，而故障在釋放之後 244 幀、在 DreamGUI 的 draw 裡

趟次：60 張卡單、`FAULTED after card 50`（`50_apng_C023.png`）、`fault_secs: 387.0`、
交接 34856 筆、反查 26844 筆、`OK mid params` 11844 行。
log `Saved\Logs\CardReader\20261119-222817-6c799c21.log`，
報告 `Saved\Reports\card-reader-dreamgui\handoff-lookup-trip2.txt`、
breadcrumb `...\breadcrumbs-trip-handoff2.txt`。

## 一、先宣告一件會影響比較的事：這個建置變慢了

故障從上一趟的 **146.8 s／第 15 張**變成 **387.0 s／第 50 張**。量具每趟多印上萬行
（`OK mid params` 一行就有十幾個參數）。**所以「位置與秒數」在這兩個建置之間不能比**，
但下面的順序量都是**幀號**，不受這件事影響。

## 二、`ordering`：釋放是 GC 做的，這次是確值不是上界

`Texture2D_2999`（512×512 BGRA，`_overtex1`）：

```
bound  -> 12 個 MID，frame 48200 / 48468 / 48718 / 49909 / 50139 / 50286
let go    49061（第一次）與 50748（第二次）
unreachable          51209   ← 每幀輪詢，確值
released (allocation) 51214   ← 比不可達晚 5 幀
released (64 MB heap) 51236   ← 再晚 22 幀
PageFault             51458   ← 比配置釋放晚 244 幀
```

**不可達先於釋放 5 幀**，正是 GC → `BeginDestroy` → `ReleaseResource` → fence 刪除那條路的形狀。
**所以「釋放是 GC 造成的」現在是量到的，不是推測**；上一趟分不出來是因為輪詢只在載入期間，
改成每幀之後就分開了。

## 三、owner 欄：三分之二的 `ALIVE` 是屍體，三分之一是活元件槽裡的真引用

| | 筆數 |
|---|---:|
| `owner=<no live component>`（`ALIVE` 但沒有任何活著的元件材質槽指著它 ⇒ 還沒被收的屍體） | **16121** |
| `owner=<Actor>/<元件>[槽]`（真引用） | **8557** |
| `outer=/Engine/Transient` | **24678（全部）** |

活著的那些 owner 長這樣：`KKPreviewActor_70/Skel_0[0]`、`KKPreviewActor_136/Skel_2[0]`、
`KKPreviewActor_86/Part_14[0]`、`KKPreviewActor_130/SkinOutline_2[0]`——
**都是當前 actor 的一般部件元件，不是特別落在 `BodyMesh`／`HeadMesh` 上。**
而 `outer` 100% 是 `/Engine/Transient`，和 `Create(Parent,GetTransientPackage())` 一致：
**這條路上的 MID 沒有一個是用元件當 Outer 建的**，所以讀卡器自己那七處
`Create(.., Comp)` 不在這條反查覆蓋的路上（那 4 筆 `same=0` 是它們唯一漏進來的痕跡）。

故障那張的 12 個 MID 裡，**每次放手都有兩個是活元件槽裡的**（49061 時是 `KKPreviewActor_130` 的
`Skel_2[0]` 與 `SkinOutline_2[0]`，50748 時是 `KKPreviewActor_136` 的那兩個），其餘是屍體。
**注意這兩個 actor 是不同的卡**——同一張貼圖透過 identity 快取交給了後來那張卡的 MID。

## 四、第 2 欄：舊 MID 的**每一個**槽都還指著舊卡的貼圖

```
mid=MID_M_ForgeSkin_Flat_72 params=15
  _MainTex=Texture2D_3159  _overtex1=Texture2D_2999  _overtex2=Texture2D_46
  _DetailMask=Texture2D_3160  _NormalMap=Texture2D_3161  _NormalMask=Texture2D_2581
  _liquidmask=Texture2D_2576  _Texture2=Texture2D_370  _Texture3=Texture2D_371
  _RampG=Texture2D_3152  …（其餘是 T_white／T_black／T_bump 等內建預設）
```

12 個 MID 的 `_overtex1` **全部**還是 `Texture2D_2999`。這正是「參數設定後就不再變」的後果：
**舊卡的 MID 只要還活著，它的每個槽都還指著舊卡的貼圖**，不只我們查的那一個。
（`_RampG` 三個 MID 各不相同——`3152`／`3207`／`3209`——所以這些 MID 不是彼此的複本。）

## 五、breadcrumb：兩趟形狀完全相同

`active_nodes=31`、`texture2d_in_breadcrumbs=0`、
`active_main_variants: 4 main=DreamUIDynamicSpriteAtlasData_Texture_0  4 main=DreamUIPreset_WhiteSolid`。
**八個 `DreamUIDraw` 同時 `[Active]`，atlas 與 `WhiteSolid` 各四個**，底下的
`widget=DreamUIDataTexture_6 clip=DreamUIDataTexture_3`、
`rect=DreamUIDataTexture_4 paint=DreamUIDataTexture_1 mask0=fallback` 全部相同，
和第一趟（`0x803542d4/d7/da`）是同一個形狀。**所以 `main=` 不是線索：兩種都在同一段裡同時在飛。**

## 六、因此問題收斂成一句

**GC 回收了那些 MID 與貼圖，配置也依 fence 正常釋放了，而 244 幀之後 DreamGUI 的 draw 還在取樣那個位址。**
兩個 UObject 都已死，所以**持有者只能是 render thread 上不經 UObject 的結構**——
而 breadcrumb 指的 pass 就是 DreamGUI 的 view extension。下一步在 DreamGUI 送 draw data 到
render thread 那條路上（f-sceneload 正在查），而**不在**換卡 sweep、不在 MID、不在貼圖的生命週期上：
那三者這兩趟都量過了，行為正常。

# `-LegacyReader` 三趟：0/3 故障，對上基線 6/6

**陳述句（照第十八條的限制寫）：Dream 讀卡器畫面路徑是這個故障的必要條件。**
**不是**「DreamGUI 的 draw 是取樣者」——這一格把畫布、它的 draw、與讀卡器畫面那條互動流程一起移除了，
三者分不開。

| | 趟 1 | 趟 2 | 趟 3 |
|---|---|---|---|
| `cmdline_has_legacyreader`（到達證據，乾淨趟可讀） | **1** | **1** | **1** |
| `dreamgui_letgo`（Dream 基線 **7**） | **0** | **0** | **0** |
| `dreamgui_created`（Dream 基線 **1**） | — | — | **0** |
| 開到第幾張 | **60/60** | **60/60** | **60/60** |
| `faults` | **0** | **0** | **0** |
| `fault_secs` | `NO_FAULT`（138345 行） | `NO_FAULT`（140875 行） | `NO_FAULT`（141414 行） |
| `shader_hash`／`shader_active_total` | 空 | 空 | 空 |
| 我的量具：`kept_created` | **3423** | **3417** | **3450** |
| 我的量具：`handoffs` | **40255** | **41276** | **41130** |

**基線是 6/6 故障**（Dream 路徑四趟 ＋ 兩趟交接趟）。

## 為什麼「沒故障」不是「什麼都沒跑」

三趟的 `kept_created`（3423／3417／3450）與 `handoffs`（40255／41276／41130）
**都高於會故障的那趟 Dream 路徑**（2888／34856），而那趟還**只跑到第 50 張就掛了**。
所以 legacy 這三趟各自開完 60 張、建立的角色貼圖更多、交接次數更多，**仍然一次都沒故障**。
`lookups=32035`、`watch_unreachable=3510`（趟 3）——換卡 sweep、放手、回收這些路**照常在跑**。

## 三個欄位各自排除什麼

- **`cmdline_has_legacyreader=1`**：旗標確實到達（引擎自己把命令列回音進 log）。
  **這是這一格唯一在乾淨趟也可讀的到達證據**——breadcrumb 段落只在故障時才印，
  所以「沒有 `DreamUIDraw`」在 0/3 這個結果上恰好讀不到（第九條）。
- **`dreamgui_letgo=0`／`dreamgui_created=0`，對上基線 7／1**：DreamGUI 的資源路徑確實沒有啟動，
  **而且是對著一個非零基線的 0，不是孤立的 0。**
- **`shader_hash` 三趟皆空**：沒有第二個故障混進來。若有一趟故障而 hash 等於
  `E6753E1EA9F1F20775D8BC0AD963B1EF`，必要性就不成立（第十七、十八條）。

## 下一步（不是再換旗標）

要把那一束拆開只能**插樁**：在 DreamGUI 實際綁貼圖的那一處，每幀印出綁進每個槽的 **GPU 位址**，
故障後與報告的 `GPU VA` 比對。**命中就是指認；從沒命中就把 DreamGUI 這一側排掉**，
而「讀卡器畫面路徑」裡剩下的東西成為下一個目標。那一格的到達證據天生在乾淨趟可見（每幀都印）。
插樁位置等 DreamGUI 槽／descriptor 那題的答案，**位置沒定不先動碼**。

# 槽位那一趟：故障那張從沒進過任何槽，而 DreamGUI 確實會綁別的 `Texture2D_<n>`

趟次：一趟（一趟一 claim）、`FAULTED after card 17`（`17_heroine_klara.png`）、`fault_secs 142.6`、
`shader_hash=E6753E1EA9F1F20775D8BC0AD963B1EF`（**同一顆**）、`fault_texture=Texture2D_901`。

| 讀數 | 值 |
|---|---|
| `slot_lines` | **6461**（全部 `changed`） |
| **`slot_hits_fault_texture`** | **0** |
| `slot_named_texture2d` | **928** |
| `slots_seen` | `Main`／`Font`／`WidgetData`／`ClipData`／`RectBlockData`／`PaintData` |
| 從未出現 | **`RenderLayerTable`、`MaskTexture0`、`MaskTexture1`**（始終為空，和 breadcrumb 的 `mask0=fallback` 一致） |
| `distinct_referenced_names`（前幾名） | `DreamUIPreset_WhiteSolid` 2297、`DreamUIDynamicSpriteAtlasData_Texture_0` 1366、`DreamUIFontData_DistanceField_Texture_0` 931、`none` 930、`Texture2D_9` 57、`Texture2D_24` 52、`Texture2D_7`／`_19`／`_20`／`_22`／`_23`／`_25` 各 50 |

## 兩個事實要一起讀

1. **故障那張（`Texture2D_901`）從頭到尾沒有被綁進任何槽。**
   所以「某個 DreamUI 槽指著那張已死的貼圖」在**解參層面是陰性**。
   這和那九個槽的型別一致：全是 `FTextureReferenceRHIRef`，持有 `TRefCountPtr<FRHITexture>`
   （`RHITextureReference.h:53`），**指著就不會被釋放**。
2. **但 DreamGUI 真的會把 `Texture2D_<n>` 綁進槽**——928 行，編號都很小（`_7`／`_9`／`_19`–`_25`）。
   **照第十五條，名字不唯一**：那些極可能是 UI 縮圖／預覽（CPU 解碼那群），
   而角色 runtime 貼圖的編號是幾百到幾千（故障那張是 `_901`、前幾趟是 `_507`／`_2999`／`_1407`）。
   **所以既不能說「卡片貼圖會進 DreamGUI」，也不能說「`Texture2D_` 都不進」——要靠語意分。**

## 因此 DreamGUI 這一側只剩兩個

`DreamUI_SceneDepthTex`，以及 **`DreamUI_BackdropTex`**——
`FDreamUIBuiltInBackdrop::Texture` 是整個 renderer 裡**唯一的裸 `FRHITexture*`**（`DreamUIRenderer.h:29`，
寫入點 `DreamUIRenderer.cpp:1619`／`:2365`，綁定點 `:1015`，fallback `GBlackTexture`），
**既沒有引用計數、不在任何 breadcrumb 裡、也不在那九個槽裡**。下一格（`NoBackdrop=2`）判它的必要性。

# `NoBackdrop=2` 三趟：**3/3 照樣故障**，所以 backdrop 不是必要條件（讀取那一側）

事前預期（協調與我都押 0/3）**被否掉**。

| | 趟 1 | 趟 2 | 趟 3 |
|---|---|---|---|
| `# knob now`（驅動回讀主 cvar） | `NoBackdrop = "2"` `LastSetBy: SystemSettingsIni` | 同 | 同 |
| `cmdline_has_nobackdrop` | **1** | **1** | **1** |
| `faults` | **1** | **1** | **1** |
| `Shader Hash` | `E6753E1E…` | **同一顆** | **同一顆** |
| 故障那張 | `Texture2D_320` | `Texture2D_1007` | `Texture2D_550` |
| 開到第幾張／秒數（僅附註，不可比） | 4／79.4 s | 17／139.6 s | 15／140.4 s |
| `slot_named_texture2d` | 927 | 943 | 961 |
| `kept_created`／`handoffs` | 377／4557 | 945／10391 | 900／9980 |
| `Backdrop` 出現在 breadcrumb | **0** | **0** | **0** |
| `[Active]` 總數／其中 DreamUI | 33／24 | 36／27 | 32／24 |

**到達證據兩層都成立**：驅動用 `ui_exec` 回讀主 cvar 得到 `"2"`（`LastSetBy: SystemSettingsIni`），
加上命令列回音。**這是這一串格子裡第一次到達證據從設計時就在乾淨趟與故障趟都可讀**（實際上三趟都故障）。

## 結論的範圍，照先前標好的限制

mode 2 **複製照做**（`CopyFrom` 正常、pass 結構與配置不變），**只把綁進 `DreamUI_BackdropTex` 的那一張換成全域黑貼圖**。
所以這三趟排除的是：**「故障需要經由那個槽讀到的那塊記憶體」**——**不成立**。
**沒有**排除 backdrop 的**配置／歸還**路徑（那條要另一格，而現在沒有理由去設計它）。

## 一個白撿的對照，讓第二十一條更強

趟 3 的報告列了**三筆**已釋放資源，而其中 `SSR.TemporalAA` 的區間**不包含**故障位址：

```
VA=0x1CA4381000
  out  [0x1CA0E00000..0x1CA4000000]  SSR.TemporalAA
  IN   [0x1CA4000000..0x1CA8000000]  PoolAllocator Heap
  IN   [0x1CA42C0000..0x1CA4420000]  Texture2D_550
```

**所以報告確實會列出其他已釋放資源，而只有卡片貼圖那一筆的區間包含故障位址。**
這正是第二十一條的推理要的對照：若懸空的指標屬於別的資源，**那個資源自己的區間**必須包含故障位址。
加上這三趟，區間檢查累計 **7/7 都落在卡片貼圖自己的區間內**。

## 所以 DreamGUI 這一側還剩什麼

1. **`DreamUI_SceneDepthTex`**（唯一還沒量過的綁定槽）；
2. **descriptor／綁定表那一層**——第二十二條那個約束指向這裡：九個 reference 槽從沒綁過那張貼圖，
   所以讀它的人拿的是「它還活著時取得的位址或 descriptor」；
3. **「有活引用計數還被釋放」**（比原假說更大的那個可能）。

**不再查的**：換卡 sweep、MID、GC、`ok.RuntimeTextureRelease`（都量過、行為正常），
以及 backdrop 的讀取側（這三趟）。

# 觀察趟（pool reuse ＋ 延遲釋放 ＋ retention 400000）：group 那整條路**讀卡器根本沒用到**

趟次：一趟一 claim、`FAULTED`、`fault_secs` 略、`shader_hash=E6753E1E…`（同一顆）、
`fault_texture=Texture2D_869`、`slot_lines=6052`。
log `Saved\Logs\CardReader\20261120-000336-0c9b04e8.log`。

## 一、`DreamGUI.Experiment.LogPoolReuse` 到達了，而讀數是「這條路沒被走過」

```
# knob now: DreamGUI.Experiment.LogPoolReuse = "1"   LastSetBy: SystemSettingsIni   ← 到達證據
DreamGUI group pool        … 0 行
DreamUI_GroupTexture       … 整份 log 0 次
```

`Note()` 只在 `DreamUICompositor.cpp:302` 被呼叫，就在
`GRenderTargetPool.FindFreeElement(…, TEXT("DreamUI_GroupTexture"))` 成功之後（`:296-303`）。
**0 行 ⇒ `Note()` 從沒被呼叫 ⇒ 讀卡器一次都沒有取得 group render target。**

**所以下面這一整條在讀卡器裡是「機制點不存在」（第 7k 條：作廢，不是陰性）**：
- group render target 的池子重用（`Frames.Pooled=3`、零 GPU fence、`RenderTargetPool.cpp:202` 只看 `IsFree()`）；
- `SetGroupSectionComposite` 的 `bSame` 比 `TWeakObjectPtr`（物件死了也和自己相等）那條「沒有新值就不動」的路；
- `DreamUIRenderer.cpp:1222-1234` 那個已修 bug 所在的同一層（pool element 提早回池）。

**三個候選一次清掉，而且是用一個現成旋鈕、一趟、零建置。**
**注意這條的可用性取決於「這個場景」**：街區／Studio 若會用到 group（混色模式讀背景），那裡仍要各自量。

## 二、延遲釋放佇列：第二次量到它沒放過卡片貼圖

```
# frames_in_effect: texture=3 buffer=3 pooled=3 func=3     ← LogEntries 的到達證據
# letgo_entries=7     # letgo_kinds: 7 kind=texture
# letgo_names: 4 name=DreamUIDataTexture_4 ; 3 name=DreamUIDataTexture_6
# letgo_texture2d=0   # fault_texture_in_letgo=0   # held_values: 7 held=3
```

**七筆全是 `kind=texture`、全是 DreamUI 自己的資料貼圖、全部 `held=3`**；
`kind=pooled`／`buffer`／`func` **一筆都沒有**——`func` 就是 proxy 的 `delete`，
**所以這一趟連一個 proxy 都沒經過這個佇列**。
而故障那張 `Texture2D_869` 在佇列裡出現 **0** 次。**第二次確認：放手它的不是這個佇列。**

## 三、`retention=400000` 第二趟也一致

（第一趟見「retention 那一趟」。）這一趟同樣只列出卡片貼圖與包住它的 heap，沒有更早的住戶。

## 四、所以持有者那一側剩下什麼

`FDreamUIMaterialProxy` 繼承的 **uniform expression cache**（一個 uniform buffer，resource table 持有該材質的貼圖，
只在三處重建、沒有每幀重建）——**f-sceneload 查完 descriptor 那一層之後唯一剩下的跨幀持有者**。
下一格就是前人留的判別器 `DreamGUI.Experiment.NeverDeleteProxy=1`。

# `NeverDeleteProxy=1` 三趟：3/3 故障，**但它不是「解構無害」，而是「解構從沒跑過」**

| | 趟 1 | 趟 2 | 趟 3 |
|---|---|---|---|
| `# knob now` | `NeverDeleteProxy = "1"` `SystemSettingsIni` | 同 | 同 |
| `cmdline_has_neverdelete` | 1 | 1 | 1 |
| `faults` | **1** | **1** | **1** |
| `Shader Hash` | `E6753E1E…` | 同一顆 | 同一顆 |
| **`leak_lines`（洩漏計數器印了幾行）** | **0** | **0** | **0** |
| `cards`／`fault_secs` | 14／140.6 | 14／140.0 | 14／142.1 |
| `kept_created`／`kept_letgo` | 863／1035 | 864／1036 | 864／1036 |
| `last_local_used` | 2648.98 MB | 2576.54 MB | 2645.46 MB |

## 關鍵在 `leak_lines=0`：那個旋鈕沒有東西可以阻止

`LeakInsteadOfDeleting()` 就在 proxy 的自訂 deleter 裡（`DreamUIMaterialProxy.cpp:127`），
緊接著才是 `FDreamUIDeferredRelease::Later([InProxy]{ delete InProxy; })`（`:134`／`:140`）。
它開著時**每一次**被呼叫都會計數並印 log（前 10 筆、之後每 50 筆）。
**三趟 `leaked on purpose` 都是 0 行 ⇒ 那個 deleter 一次都沒被呼叫 ⇒ 整趟沒有任何 proxy 失去最後一個參照。**

**所以這一格對那個旋鈕來說是「機制點沒被走到」（第 7k 條），不是陰性結果。**
而對那個**假說**來說，結論比 3/3 更強：**proxy 的解構在讀卡器裡根本不會發生**，
所以它不可能是觸發者——**是「從不發生」而不是「發生但無害」**。

**兩個獨立量具同時說同一件事**（這正是第十一條要的交叉查核）：
- 這一格的 `leak_lines=0`（從 deleter 那一側看）；
- 觀察趟的 `kind=func` **0 筆**（從延遲釋放佇列那一側看——`func` 就是那個 `delete InProxy`）。
**兩者原理不同、資料不同，結論一致。**

**復活條件**：若哪天讀卡器的材質會被換掉或釋放（例如換主題、換 skin、關閉畫布後重開），
proxy 就會失去最後一個參照，這條就要重測。

## 同時排除：顯存不足不是終局

`last_local_used` 三趟都在 2.6 GB 左右（預算 31.4 GB），而且真正的 OOM 字樣 **0 筆**——
**所以「洩漏把趟次跑掉」這個風險沒有發生**（事前登記的那個作廢條件沒有觸發），三趟都是正常故障。

# 那個 fence 蓋章在「釋放記帳」那一刻，而且傾印的 `FrameID` 就是同一個數字——所以答案在既有 log 裡，一趟都不用跑

**全部零建置、零趟次：讀引擎碼 ＋ 讀十份既有故障 log。**

## 一、蓋章點：`LastUsedFrameFence` 是在**釋放**時蓋的，不是在 GPU 實際使用時蓋的

`D3D12PoolAllocator.cpp:656`，在 `DeallocateResource` 裡：

```cpp
DeleteRequest.FrameFence = FrameFence.GetNextFenceToSignal();      // :650
((FD3D12MemoryPool*)Pools[PoolIndex])->UpdateLastUsedFrameFence(DeleteRequest.FrameFence);  // :656
```

`GetNextFenceToSignal()` 是**當前這一幀**將要簽的 frame fence 值
（`D3D12DirectCommandListManager.h:44`，`NextFenceValueTOP + 1`，每幀 `AdvanceTOP`／`AdvanceBOP` 各推一次）。
所以它記的是**「池子最後一次動這塊的那一幀」**，不是「這塊記憶體最後一次被 GPU 讀到的那一幀」。

**它涵蓋什麼**：等到那個 fence 完成，代表**釋放那一幀以前（含該幀）提交的 GPU 工作都做完了**，再加寫死的 20 幀。
**它不涵蓋什麼**：**釋放之後才提交的使用**。一個在釋放前取得、卻在之後的幀才被綁定的 descriptor，
完全在這個保證之外——那 20 幀只多買 20 幀的寬裕。

## 二、是**每塊 heap 一個**，不是每筆配置一個

`FD3D12MemoryPool::LastUsedFrameFence`（`D3D12PoolAllocator.h:115`），
`UpdateLastUsedFrameFence` 取 `Max`（`:103`）。所以同一塊 heap 裡任何**更晚的釋放**都會把它往後推。
銷毀條件還要求 `IsEmpty()`（`:850`）。

## 三、傾印的 `FrameID` 就是同一個數字——所以上面兩條可以直接用既有 log 驗證

`D3D12Adapter.cpp:1988`：`ReleasedData.ReleasedFrameID = GetFrameFence().GetNextFenceToSignal();`
**和蓋章用的是同一個 frame fence、同一個取值方式。** 於是十份故障 log 可以直接算：

| log | 貼圖釋放 | heap 釋放 | 故障當幀 | heap − 貼圖 | 故障 − heap |
|---|---:|---:|---:|---:|---:|
| 002501 | 7353 | 7375 | 7475 | **22** | 100 |
| 001422 | 16678 | 16701 | 16926 | **23** | 225 |
| 001056 | 16432 | 16454 | 16463 | **22** | 9 |
| 000731 | 17132 | 17154 | 17169 | **22** | 15 |
| 000336 | 16520 | 16542 | 16677 | **22** | 135 |
| 235517 | 16170 | 16193 | 20309 | **23** | 4116 |
| 234908 | 18422 | 18444 | 18488 | **22** | 44 |
| 234607 | 18168 | 18190 | 18203 | **22** | 13 |
| 234422 | 8217 | 8240 | 8264 | **23** | 24 |
| 234105 | 18697 | 18719 | 19178 | **22** | 459 |

**`heap − 貼圖` 十趟十次都是 22 或 23**，正好是寫死的 20 加上 fence 完成的一兩幀延遲。
**所以池子的行為完全照碼走，而且那張卡片貼圖的釋放就是那塊 pool 的最後一次活動**
（`Max` 語義下沒有更晚的釋放把它往後推），這本身是一條資訊：那塊 heap 在貼圖釋放之後就沒人再動過。

**而 `故障 − heap` 從 9 幀到 4116 幀**（9／13／15／24／44／100／135／225／459／4116）。

## 四、這張表否掉的與指向的

**否掉「fence 早了一點」**：若是 fence 差幾幀，故障會緊貼在銷毀之後；
**4116 幀**那一趟不可能用任何時序寬裕解釋。
**也否掉「下一個房客」**：短命的房客解釋不了四千幀後才被讀到。

**指向**：有東西**跨越數千幀持有那個位址**，並在任意晚的時間取樣它——
**那不可能是任何「以幀為生命期」的物件**（那樣會在一兩幀內就故障）。
而那張貼圖的配置在第一欄那一刻就已經歸還，**所以持有者握的是一個烘進去的位址，不是一個有參照計數的物件**：
形狀是**殘留的 descriptor／被快取下來、沒人去失效的綁定**，不是殘留的 C++ 指標。
這和「全 plugin 裸指標掃完沒有跨幀持有」不矛盾——**descriptor 不是 C++ 指標**，
也不會出現在我們那九個槽的量具裡（那個量具看的是 resolve 當下的 `UTexture*`／`FTextureReferenceRHIRef`）。

## 五、同時順手除名：bindless 在這個 build 只開給 ray tracing

`Bindless is enabled (Configuration=RayTracing)`（啟動 log）。故障的是 raster pass 的像素著色器 `MainPS`，
所以**不是 bindless 表**那條路。這條是免費的，但覆蓋率限於這個 build 的這個設定。

# D3D12 descriptor／state cache 這一層：預測的那個 ABA **確實存在於碼裡**，但它的壽命只有一個 command list，所以撐不出 4116 幀

**零建置、零趟次，純讀引擎碼。**

## 一、SRV 的 descriptor table **沒有跨 draw 快取**；唯一有內容鍵的跨 draw 快取是 sampler

`BuildSRVTable`（`D3D12DescriptorCache.cpp:439`）每次都**新保留一段 online heap 槽位**
（`FirstSlotIndex = HeapSlot; HeapSlot += SlotsNeeded;`），再從各 view 的 offline descriptor
`CopyDescriptors` 抄一份。**沒有以指標或 hash 判「這段沿用上次」的路徑。**

有跨 draw 快取的是 **sampler**：`FD3D12SamplerMap`／`FD3D12SamplerSet`
（`D3D12DescriptorCache.h:126/174`），**鍵是 `FD3D12SamplerArrayDesc`，也就是 sampler desc 本身的內容**
（`:101-123`）——不可變狀態、裡面沒有任何資源位址。**所以 sampler 那層產不出這個故障。**

## 二、但跨 draw 保留的是一個**裸的 view 指標**，而且槽位以**指標相等**判「不必重設」

`D3D12StateCache.cpp:1578`：

```cpp
if ((CurrentShaderResourceViews[ResourceIndex] != SRV) || GD3D12SkipStateCaching)
```

`FD3D12ShaderResourceViewCache::Views[Stage][Slot]` 是裸 `FD3D12ShaderResourceView*`（無參照計數），
`Cache.Resources[..]` 同樣是裸 `FD3D12Resource*`。**這就是預測的那個 ABA 形狀，而且是真的碼**
（和 `FDreamUISectionProxy_Mesh::DrawStateVertexBuffer` 同族：舊物件死、新物件恰好落在同址 ⇒ 鍵說沒變）。

## 三、**但它的窗口只有一個 command list**，所以它不是那個「持有者」

`DirtyStateForNewCommandList()`（`D3D12StateCache.cpp:196`）最後四行：

```cpp
PipelineState.Common.SRVCache.DirtyAll();
PipelineState.Common.UAVCache.DirtyAll();
PipelineState.Common.CBVCache.DirtyAll();
PipelineState.Common.SamplerCache.DirtyAll();
```

**每一條新的 command list 都把所有 view 槽位重新標脏**，下一次 draw 必定重抄 descriptor。
所以這個快取**無法跨幀、更無法跨四千幀**地留著一段烘死位址的 descriptor。
照第 7k 條，**「跨幀的 descriptor table 快取」這個機制點在這個後端不存在**；
它最多只能是**近端讀者**（呼叫端把一個已死的 view 交給它），不是跨數千幀的持有者。

## 四、這一層引擎自己還防了三道

1. `SetShaderResourceView` 開頭：`if (SRV && SRV->GetResource() == nullptr) SRV = nullptr;`
   （`:1573`）——失去資源的 view 綁成 null，不會綁出一個死位址。
2. 資源死亡時有失效路徑：`FD3D12CommandContext::ConditionalClearShaderResource`
   → 逐 frequency `StateCache.ClearResourceViewCaches`（`D3D12CommandContext.cpp:718`），
   由 `ClearShaderResources(FD3D12BaseShaderResource*)`（`:730`）帶進來。
3. 資源的配置換位置時，view 的 descriptor 會被同步重寫：`ResourceRenamed`／`UpdateDescriptor`
   （`D3D12View.cpp:300/367`，`D3D12Resources.cpp:1602`）。

## 五、現成判別器存在，但它是 **exec 指令不是 cvar**；而我認為**不該為它燒趟次**

`TOGGLESTATECACHE`（`D3D12StateCache.cpp:91-104`，`FSelfRegisteringExec`）會翻轉
`GD3D12SkipStateCaching`，使每個槽位都重設、不吃指標相等那條捷徑。
**到達證據是它自己回印的那行 `D3D12 State Caching: OFF`**（沒有可回讀的數值，而且它是 toggle 不是 set，
只能下一次）。它是個 bundle（viewport／scissor／PSO 的比較也一起跳過），
但那些額外效果只是把冗餘狀態重設一遍，**不會生出也不會消掉一個死位址**。

**不跑的理由**：第三點已經證明這一層的窗口是一個 command list，
而我們手上的資料是**故障比頁面消失晚 9 到 4116 幀**。
一個撐不到下一條 command list 的機制，解釋不了四千幀後的取樣——
**為它跑三趟只能得到一個已經知道答案的格子**。若之後有證據把窗口縮回單一 command list，再回來跑它。

## 六、剩下的形狀

這一層關掉之後，還能同時滿足「跨數千幀、無參照計數、取樣時間任意晚」的只剩：
**每次那個 UI 元素被畫時，呼叫端都重新交出同一個已死的位址**——
也就是**呼叫端自己持有的東西**（不是 D3D12 的快取）在每次繪製時提供那個位址。
而 f-sceneload 掃完 plugin 的裸指標只有一處跨幀且不解參，
所以下一步要問的是**呼叫端交出去的那個 view／貼圖是從哪個容器取出來的**，
而不是繼續往 RHI 內部的快取挖。

# `NoBackdrop=1` 四趟（含對照）：**3/3 故障 ⇒ backdrop 兩個方向都除名**，連「取樣者是 backdrop 副本」也一併否掉

| | 對照 trip 0 | mode 1 趟 1 | 趟 2 | 趟 3 |
|---|---|---|---|---|
| `# knob now` | `NoBackdrop = "0"` | `"1"` | `"1"` | `"1"` |
| `cmdline_has_nobackdrop1` | 0 | 1 | 1 | 1 |
| `faults` | **1** | **1** | **1** | **1** |
| `Shader Hash` | `E6753E1E…` | 同一顆 | 同一顆 | 同一顆 |
| `cards` | 3 | **46** | 22 | 22 |
| `fault_texture` | `Texture2D_89` | `Texture2D_2961` | `Texture2D_1430` | `Texture2D_959` |
| `kept_created` | 301 | 2719 | 1321 | 1300 |
| `handoffs` | 4155 | — | 14069 | 13808 |

**mode 1 三趟 3/3 故障，而且做的工比 mode 2 那三趟多**（`kept_created` 1300–2719 對 377–900，
`handoffs` 約 14000 對 4557–9980），所以不是「還沒跑到就結束」。

## 讀法（事前登記的那一條）

**`3/3` ⇒ backdrop 整條除名**：
- **讀取側**由 `NoBackdrop=2` 排除（副本照配置照交接，只把綁定換成 `GBlackTexture`，3/3 故障）；
- **配置與交接側**由這一格排除（`CopyFrom` 在任何 `CreateTexture` 之前就 `return nullptr`，
  `DreamUICompositor.cpp:365-368`，所以整趟**沒有任何 backdrop 副本被配置**，
  `FDreamUIBuiltInBackdrop::Texture` 永遠是 null，而故障照樣 3/3）。

**而且這一格同時否掉了那個反向假說**：「故障位址落在卡片貼圖的舊區間內，取樣者是 backdrop 副本
（配置在那塊已釋放的記憶體上）」——**mode 1 根本不存在那個副本，故障卻照舊**。

## 這一格的對照與混淆判讀，以及它為什麼不影響上面的結論

事前登記的混淆是「關掉配置會挪動卡片貼圖的落點」，判據是固定卡序的顯存數字。
**那個取樣器壞了**（見下），所以顯存比較做不成。
**但那個比較只在 `0/3` 時才需要**——它是用來分辨「乾淨是因為機制被移除」還是「乾淨是因為落點被挪開」。
**這一格是 `3/3`，沒有任何乾淨的趟次要解釋**，所以取樣器壞掉不削弱結論。

## 取樣器壞了，而且是**閘門誤放行**，不是誤攔

- `vram_samples` 四趟都是**空的**，而同一份報告裡 `control_sample_points=4` 說有四個取樣點。
- 原因有兩層：`rhi.DumpMemory` 的 VRAM 行**根本沒出現**（它在 `#if STATS` 裡），
  而我的閘門抓的字串 `MB total` **被 `LogMemory` 的主記憶體行命中**
  （`Physical Memory: 43190.67 MB used, 85436.03 MB free, 128626.70 MB total`）；
  同時取數字的 `[0-9.]+MB total` 又因為那些行的數字和 `MB` 之間有空白而不匹配。
- **所以閘門是靠一個別的子系統的輸出通過的**：它本來要證明「那個量具活著」，
  結果證明的是「主記憶體日誌活著」。
- 救命的仍然是那個配對的樣本欄位（`vram_samples` 空）——**計數說有、樣本說沒有**，
  和 11-20 的 Bloom／OOM 同族，但這次方向更糟：**誤放行**。
  修法寫進錯誤紀錄：**閘門要抓它所守護的那個量具獨有的字串**（這裡該抓
  `rhi.DumpMemory` 自己的標題或 `LogD3D12RHI` 的 VRAM 行），不要抓任何別人也會印的子字串。

## 去裸指標那一輪對前面那些格子的影響（在它進 E 樹之前先記下來）

那一輪在 F 樹先改（`F:\OpenKoikatsu\Plugins\DreamGUI`，commit `c9fd56d5d`、`2e0a02bdf`），之後才搬到 E 樹。
**前面所有量測都在它之前跑完**，但有兩件要先寫進來，否則以後會看不懂。

### 一、`NoBackdrop` 那兩格（mode 2 與 mode 1）**以後要重跑，必須回到 `c9fd56d5d` 之前的碼**

那一輪把 `FDreamUIBuiltInBackdrop::Texture` 從裸 `FRHITexture*` 改成 `FTextureRHIRef`（持有參照）。
**那會讓 backdrop 的 RHI 貼圖在繪製期間多一份參照，於是那一幀內延遲釋放佇列不可能放掉它**——
也就是改動本身就改了那兩格要測的東西。
**mode 2（3/3）與 mode 1（3/3）都在改動之前跑完，所以結論有效**；
但在改動之後的樹上重跑那兩格**量到的不是同一件事**。

### 二、逐處回退要從哪一處開始退

若改動後當機真的消失，**先退 `FDreamUISectionProxy_Mesh::Material` 那一處**：
它原本會在 render thread 解一個裸 UObject 位址（`Material->GetRenderProxy()`），
材質在 section 還在池子裡時被回收就會讀到已死位址，
**而那是那一輪裡唯一一處原本真的會發生這件事的地方**。
它本身解釋不了「整頁不在頁表」（那需要整塊 heap 被銷毀），
但**「當機消失」這件事要指認到某一處，這一處的先驗最高**。

### 三、驗收時那四個診斷 cvar 要還能印，而 `LogTextureSlots` 是搬運正確性的直接證據

九個槽改成 weak 之後，E 樹獨有的 `LogSlot` 印 `src=` 那裡要從 weak 解出來。
**所以啟動驗收時 `DreamGUI.LogTextureSlots=1` 還能印出 `slot … src=…`，就是搬運沒搬壞的直接證據**；
印不出來或印成空的，就是那一處沒接好，而不是「量具剛好沒觸發」。


# 去裸指標那一輪之後：**5/5 照樣故障**，所以持有者不在「不帶參照計數又跨幀」那一類裡

樹：`d0742c2b7`（整合後，三棵樹同一個 commit），工作區只有一個產生檔是脏的。
同一把尺：同一份 60 張卡單、同一組旋鈕、固定取樣卡序、同樣的報告欄位。

| | 趟 1 | 趟 2 | 趟 3 | 趟 4 | 趟 5 |
|---|---|---|---|---|---|
| `faults` | **1** | **1** | **1** | **1** | **1** |
| `Shader Hash` | `E6753E1E…` | 同一顆 | 同一顆 | 同一顆 | 同一顆 |
| `cards` | 4 | 14 | 14 | 36 | 14 |
| `fault_texture` | `Texture2D_85` | `_874` | `_901` | `_2323` | `_893` |
| `kept_created` | 392 | 864 | 864 | 2115 | 863 |
| `handoffs` | 4557 | 9860 | 9883 | 22480 | 9931 |
| `last_local_used` | 2259 MB | 2578 MB | 3088 MB | 2863 MB | 2576 MB |

**五趟的 `Shader Hash` 都是同一顆**，所以五趟都算（第十七條）。對上歷史基線累計 13/13，現在是 **18/18**。

## 讀法（事前登記的那一條）

**`5/5` ⇒ 持有者不在那一類裡。** 那一輪把「跨幀又不帶參照計數」整類形狀去掉
（UObject 裸指標 ⇒ weak、RHI 裸指標 ⇒ 持有參照、只當比較鍵的 ⇒ 改序號），而故障完全沒有變化：
重現率、故障的著色器、故障貼圖的型態、幀數關係全部照舊。

**所以前面那些排除更硬了**：backdrop（兩個方向）、transient heap、pool 側 fence、
descriptor／state cache、材質 uniform expression、proxy 解構、group RT、縮圖 brush——
**再加上「DreamGUI 裡任何不帶參照計數的跨幀持有」整類**。

## 幀數關係在新的 build 上完全複製

| | 趟 1 | 趟 2 | 趟 3 | 趟 4 | 趟 5 |
|---|---:|---:|---:|---:|---:|
| 貼圖釋放 | 7623 | 18628 | 18703 | 56820 | 18981 |
| heap 釋放 | 7645 | 18651 | 18725 | 56844 | 19004 |
| 故障當幀 | 8049 | 18708 | 18729 | 56878 | 19092 |
| **heap − 貼圖** | **22** | **23** | **22** | **24** | **23** |
| 故障 − heap | 404 | 57 | **4** | 34 | 88 |

**`heap − 貼圖` 現在是 15 趟 15 次落在 22–24**（跨兩個 build），池配置器的行為與寫死的 20 幀完全相符。
**`故障 − heap` 的全距現在是 4 到 4116 幀**——趟 3 的 4 幀是目前最短的一次。

## 兩個量具的覆蓋率，照實記

- **新的 `collected` 狀態一次都沒印**（五趟 `collected` 0 行）。那是整合時加進 `LogSlot` 的狀態
  （weak 指標指向的貼圖已被回收）。**所以這五趟裡，九個槽從來沒有在綁一個已被回收的 `UTexture`**——
  但這條的覆蓋率仍受第二十六條限制（只印變化＋心跳、靠名字比對、而且那條路持有參照）。
- **`slot_hits_fault_texture` 五趟都是 0**，和改動前四趟一致。
- **重建過的顯存取樣器還是沒有資料**（`rhi_total_lines=0`，而樣本欄位是空的）。
  **照我自己登記的規則，這算量具失敗，不算「沒資料」**，原因見錯誤紀錄第十二條：
  那個命令的輸出走的是 console 的 output device，**會回在 `ui_exec` 的回應裡，而不是進 log**，
  而我的驅動把那個回應丟進了 `/dev/null`。**所以落點比較這一欄在這一格仍然是空的**，
  不過 `5/5` 的讀法用不到它。


# 著色器身分驗了：傾印自己說出那顆是 **`FDreamUIBasePS`**，而且是同一個 `Shader Hash`

## 一、先說為什麼非驗不可：`Function = MainPS` 從來不是指認

`MainPS` 是入口點名，不是身分。**光這個專案就有八顆 pixel shader 用這個入口點，其中七顆在 DreamGUI 裡**：
`FDreamUIBasePS`、`FDreamUICompositePS`、`FDreamUILayerStyleCompositePS`、
`FDreamUIScreenRenderPS`／`FDreamUIWorldRenderPS`／`FDreamUIWorldRenderDepthFadePS`、
`FDreamUIBackdropCompositePS`，外加 `KKCrowdGpuPacking` 的 `FOKSourceMaterialPS`；
引擎原始碼裡另有 51 個檔案含這個字串。
**所以那一行連「DreamGUI 內是哪一顆」都分不出來**，更不足以撐起「取樣者在 DreamGUI 的繪製裡」這個前提。

## 二、一趟就問出來了

旋鈕：`r.Shaders.ExtraData=1`（`ShaderCompiler.cpp:451-457`，`ECVF_ReadOnly`，
由驅動以 `-ini:Engine:[ConsoleVariables]` 在鎖定前設；到達證據是回讀 `= "1"`）。
它會把著色器名寫進 shader code 的選用資料（`D3D12Shaders.cpp:38`），
再經 `D3D12NvidiaExtensions.cpp:40` 交給 Aftermath，故障時印成 `DebugName`
（`RHICoreNvidiaAftermath.cpp:405-408`）。

```
Active Shaders:
  Type = Pixel
  Function = MainPS
  DebugName = 'Global/FDreamUIBasePS/0:/Plugin/DreamGUI/Private/DreamUIBase.usf|MainPS'
  Shader Hash = E6753E1EA9F1F20775D8BC0AD963B1EF
```

**`Shader Hash` 和先前每一次故障都是同一個值**，所以這次的指認**可以套用到之前所有趟次**
（同一顆著色器，不是只有這一趟）。`Failed to associate Aftermath hash` 0 筆。

**前提成立：取樣者就是 DreamGUI 的基礎 UI 像素著色器。** 之前的框架不必重排。

## 三、代價與量具的覆蓋率，照實記

- 整趟 **542 秒**（約 9 分鐘）走到故障，`cards=4`。重編著色器的代價在一趟之內，可以接受。
- **`shader_compile_lines=0`**：我抓編譯行的那組樣式一行都沒命中，**而樣本欄位也是空的**。
  依第十一條這算那個小量具失敗（樣式不對，或這次走了 DDC），
  **不能據此宣稱「沒有重編」**；真正的到達證據是另外兩層：旋鈕回讀為 `1`，
  以及**先前所有趟次都沒有的 `DebugName` 行這次出現了**——那一行只有這個設定開著才可能存在。
- `shader_pdb` 是空的（沒開符號），本條不需要它。

## 四、這顆著色器的參數長相，下一步的起點

`FDreamUIBasePS::FParameters`（`DreamUIBaseShaders.h:157-187`）的**十一個貼圖參數全部是
`SHADER_PARAMETER_TEXTURE`**（`DreamUI_MainTex`、`DreamUI_FontTex`、`DreamUI_WidgetDataTex`、
`DreamUI_ClipDataTex`、`DreamUI_RectBlockDataTex`、`DreamUI_PaintDataTex`、
`DreamUI_MaskTex0/1`、`DreamUI_SceneDepthTex`、`DreamUI_BackdropTex`，
以及另一個結構裡的 `DreamUI_RenderLayerTable`／`DreamUI_RenderLayerWidgetData`）。

**`SHADER_PARAMETER_TEXTURE` 收的是裸 `FRHITexture*`，RDG 不會為它延長生命期**
（那是 `SHADER_PARAMETER_RDG_TEXTURE` 才有的保證）——**繫結期間由呼叫端負責讓它活著**。
而第二十六條已經說明：我那九個槽的量具看的是 `FTextureReferenceRHIRef` 那一側，
**結構上只看得到活著的綁定**。
**所以下一步要問的是：這十一個參數分別從哪裡取值，哪些不是經過那九個槽。**


# 那顆著色器的貼圖參數盤完了：**十一個全部有擔保人**，而且懷疑的那個缺口不是缺口

純讀碼，零趟次。綁定點在 `DreamUIRenderer.cpp:981-1014`。

| 參數 | 值從哪裡來 | 繫結那一刻誰擔保 | 可能是卡片 runtime 貼圖嗎 |
|---|---|---|---|
| `DreamUI_MainTex` | `Params.MainTextureRHI`（槽 0） | `FTextureReferenceRHIRef`，由 draw params 持有 | **可能**（卡片縮圖／預覽就走這裡） |
| `DreamUI_FontTex` | `FontTextureRHI`（槽 1） | 同上 | 否：`Texture2DArray`，字型圖集 |
| `DreamUI_WidgetDataTex` | `WidgetDataTextureRHI`（槽 2） | 同上 | 否：DreamGUI 自建的資料貼圖 |
| `DreamUI_ClipDataTex` | `ClipDataTextureRHI`（槽 3） | 同上 | 否：同上 |
| `DreamUI_RectBlockDataTex` | `RectBlockDataRHI`（槽 5） | 同上 | 否：同上 |
| `DreamUI_PaintDataTex` | `PaintDataRHI`（槽 6） | 同上 | 否：同上 |
| `DreamUI_MaskTex0/1` | `MaskTexture0/1RHI`（槽 7、8） | 同上 | 可能（遮罩可以是任意 `UTexture`） |
| `DreamUI_SceneDepthTex` | 傳進來的 `SceneDepthTexture`，否則 `GBlackTexture` | pass 之內取值，RDG 保證 | 否：場景深度 |
| `DreamUI_BackdropTex` | 當幀的 backdrop 副本，否則 `GBlackTexture` | 同上；**且兩個方向都已除名** | 否 |
| `DreamUI_RenderLayerTable`（VS） | `RenderLayerTableRHI`（槽 4） | `FTextureReferenceRHIRef` | 否 |
| `DreamUI_RenderLayerWidgetData`（VS） | **`WidgetDataTextureRHI`（槽 2）** | 同上 | 否 |

## 一、懷疑的那個缺口不成立：`RenderLayerWidgetData` 沒有自己的來源

協調 session 推測 `RenderLayerWidgetData` 既不在九個槽裡也沒被排除過。**不是這樣**：
`DreamUIRenderer.cpp:982` 是

```cpp
VSParameters.DreamUI_RenderLayerWidgetData = TextureOrFallback(Params.WidgetDataTextureRHI.GetReference(), GBlackTexture);
```

**它和 `DreamUI_WidgetDataTex` 讀的是同一個槽（槽 2 `WidgetData`）**，所以它在量具視野內，
而且它是**頂點著色器**的參數——**故障的是 pixel shader**（`Type = Pixel`），
所以那兩個 VS 參數本來就不會是這次被取樣的那一張。

## 二、十一個都有擔保人，所以照事前登記的讀法，矛盾落在量具那一側

九個走 `FTextureReferenceRHIRef`（draw params 持有，計數有效）、
`SceneDepthTex` 與 `BackdropTex` 在 pass 之內取值。**沒有一個是「沒有擔保人的裸值」。**
而第二十六條的三個洞說那個量具**結構上看不到懸空的綁定**。
**兩者正面矛盾 ⇒ 東西藏在洞裡 ⇒ 下一步要把量具補到「每一筆 draw 真正綁出去的那個值」。**

## 三、補量具時要量什麼：綁出去的是**參照物件本身**，不是被參照的貼圖

`TextureOrFallback(Params.MainTextureRHI.GetReference(), …)` 交給
`SHADER_PARAMETER_TEXTURE` 的是 **`FRHITextureReference` 這個物件**（它本身就是一種 `FRHITexture`）。
**GPU 真正取樣的是它當下所指的那一張**，而那層指向可以在繫結之後改變：

- `FD3D12RHITextureReference::SwitchToNewTexture`（`D3D12TextureReference.cpp:43-79`）最後一行是
  `SetReferencedTexture(InNewTexture)`——**傳進來的原值**；
  `NewTexture`（在 null 時退回 `GetDefaultTexture()`）只用在 bindless 那一段。
  所以清掉參照時，`ReferencedTexture` 變成 **nullptr**，不是黑貼圖。
- `FRHITextureReference::ReferencedTexture` 是 `TRefCountPtr`（`RHITextureReference.h:53`），
  **所以「參照指著它」與「它的配置被釋放」不能同時成立**——
  這正是第二十六條第三個洞說的：**量具只看得到活著的那一半**。

**所以樁要下在每一筆 draw 繫結的那一刻，記錄「參照物件 ⇒ 它當下指向的貼圖 ⇒ 那張貼圖的名字與位址」，
並且在貼圖已經不在時也要印得出來**（不能靠讀它的名字，因為那時讀的就是已釋放的記憶體）。
這就是交接文件第 7 節那個樁要解決的問題，而這次盤點把它的規格講清楚了：
**量的對象是「參照 → 被參照」那一跳，不是槽位解析那一刻。**


## 數清楚了：填 `FDreamUIBasePS::FParameters` 的只有**兩處**，第二處全部是全域貼圖，而且沒有任何一處把參數結構存起來

全樹 grep（`Plugins`、`Source`，排除 `Intermediate`／`Binaries`）：`FDreamUIBasePS`／`FDreamUIBaseVS`
出現 25 行，其中**宣告與 `IMPLEMENT_GLOBAL_SHADER` 以外，只有兩處建立 `FParameters`**：

| | `DreamUIRenderer.cpp:988`（主路徑） | `DreamUIRenderer.cpp:2883`（編輯器外框，`FPlainColor`） |
|---|---|---|
| 十一個貼圖欄位 | 九個走 `TextureOrFallback(Params.*RHI.GetReference(), …)`，即**參照物件本身**；`SceneDepthTex`、`BackdropTex` 走當幀的值或 `GBlackTexture` | **全部是全域**：`GWhiteTexture`／`GBlackTexture`／`GBlackArrayTexture` |
| 沒填的欄位 | 無 | `DreamUI_BlendParams`、`DreamUI_BackdropTex` |
| 沒填會是什麼 | — | **`nullptr`**：`SHADER_PARAMETER_TEXTURE` 的巨集帶 `= nullptr` 預設值（`ShaderParameterMacros.h:1637-1638`），所以不是未初始化的堆疊垃圾 |
| 結構生命期 | 區域變數，當場 `SetShaderParameters(RHICmdList, …)` 消費 | 同左 |

**所以第二處不可能交出一張卡片 runtime 貼圖**（它只交全域貼圖），**而且兩處都沒有把參數結構留到下一幀**
（`SHADER_PARAMETER_TEXTURE` 存的是裸值，結構若活過一幀就等於裸值活過一幀——這裡沒有）。
`InOutCache->Pipeline.Remember(...)` 只記 PSO 的組合，不記貼圖。

**permutation 共用同一個參數結構**（第二處的註解自己寫著「the parameter struct is shared」），
`FBlendDepth`／`FDepthFade`／`FPlainColor`／`FBackdrop` 只換 define，不換結構。

### 讀法：落在第一種分支

**只有一處會交出卡片貼圖，而它交的是參照物件**（`TextureOrFallback` 回的是
`static_cast<FRHITexture*>(InReference)`，`DreamUIRenderer.cpp:972-975`）。
所以問題不在「誰填」，而在**填進去之後那一跳（參照 → 被參照）在執行時指向什麼**。
**這一格不是指認**：第二處存在，但它只交全域貼圖，照 7k 條它是「機制點不可能帶著卡片貼圖」。

**於是那個樁的目標與位置都確定了**：下在 `DreamUIRenderer.cpp:988-1015` 這一段**參數結構填好、
`SetShaderParameters` 之前**，逐欄位記下指標值；對走參照的那九個，另外記下
`GetReferencedTexture()` 當下指向誰、以及那張的名字與位址——**並且在它已經不在時也要印得出來**。

## 2026-11-20（第二趟樁）**故障那張貼圖，整趟從來沒有被任何一筆內建 draw 綁過**

樹 `96615a0c7`，一趟，`DreamGUI.LogBoundTextures=1`、`DreamGUI.BoundRingSize=131072`、
`D3D12.TrackAllAllocations=1`、`TrackedReleasedAllocationFrameRetention=400000`。

### 一、先說量具：第一趟倒不出來，第二趟倒完了

第一趟（同一個樁，觸發掛在 `OnHandleSystemError`／`OnShutdownAfterError`／`OnEnginePreExit` 三條委派上）
**`ring_blocks=0`——三條一條都沒燒到**，log 停在 RHI 自己那份崩潰報告的最後一行。
那一趟**不是陰性結果，是量具沒能講話**（ERROR_LOG 第十一條）。
換成**掛在 log 串流上的 `FOutputDevice`**（看到 `PageFault`／`MMU Fault` 就當場同執行緒倒出）之後：

| | |
|---|---|
| `DreamUI bound ring allocated: slots=131072` | 啟動就印（到達證據，與故障無關） |
| `ring_blocks` / `ring_end_blocks` | **1 / 1**——開頭與結尾都在，**沒有被截斷** |
| 倒出行數 | **40,750** |
| 環內紀錄 | `next=7751`、`draws=138823`（已繞過，保留最後 131072 筆） |

### 二、窗口覆蓋得住，而且幾乎覆蓋整趟

**實測窗口 `frame=166..8079`，span 7914 幀。** 這一趟自己的距離：

| | 幀 |
|---|---:|
| `Texture2D_247` 的配置釋放 | 8037 |
| 包住它的 pool heap 釋放 | 8059 |
| 故障當幀 | **8079** |
| 故障 − heap | **20** |
| 故障 − 貼圖釋放 | **42** |

**7914 ≫ 42**，窗口起點（幀 166）幾乎就是趟次開頭。**所以這個陰性不是窗口太短。**

### 三、答案

**`fault_texture_in_ring = 0`。** `Texture2D_247` 在整份 log 裡只出現**一次**——在頁錯誤傾印自己那一行；
**環形緩衝的 40,750 行裡一次都沒有。**（回查樣式本身是好的：同一個樣式在環裡命中 **35,118 行**。）

**而且更進一步**：環裡曾被綁過的卡片類貼圖只有 **19 張，`Texture2D_7` 到 `_25` 連號，沒有任何編號更高的**。
而歷次故障的那些是 `_89`、`_247`、`_320`、`_550`、`_647`、`_660`、`_869`、`_870`、`_874`、`_893`、`_895`、
`_901`、`_956`、`_1007`、`_1430`、`_2323`、`_2961`——**全部在 `_25` 之後，一張都沒進過那十一個欄位。**
十一個欄位裡**只有 `MainTex` 會帶卡片類貼圖**（35,118 行全是它），其餘十個一次都沒有。

### 四、順帶更正一個被當成前提的描述

故障那張**不是**一直在講的 1024×1024。這一趟是
**`Texture 256x512x1 DXGI_FORMAT_B8G8R8A8_TYPELESS`（720,896 bytes，0.69 MB）**；
先前量到的是 1024×1024（5.38 MB）與 512×512（1.38 MB）。
**尺寸會變，所以「故障的是卡片 runtime 貼圖」這個身分是靠格式與命名推測的，不是量到的。**

### 五、讀法（照跑之前登記的那條）

登記的讀法是：「有倒出來但沒有那張 ⇒ 同時給實測窗口幀數與這趟自己的『故障 − heap』距離；
窗口短於距離就只是窗口太短，不是結果。」這裡窗口遠大於距離，且結尾標記在，**所以走硬陰性那一支**。

**著色器身分已確認是 `FDreamUIBasePS`，而被取樣的那張從沒從它的十一個欄位進去過。**
於是剩下的形狀只有兩種：

1. **同一條 command list 上還有別人綁了東西**——別的 pass／著色器把 descriptor 留在同一張
   descriptor table 的槽位，而 `FDreamUIBasePS` 某個未使用槽位讀到了它（狀態快取 ABA 的窗口已量過是
   「一條 command list」，這一條正是在那個窗口之內，所以和先前的排除不衝突）；
2. **綁進去的值在執行時指向的東西和記錄當下不同**——但第二十七條已排除參照那一跳，
   要成立得走**不經參照的那條**（`SceneDepthTex`／`BackdropTex`，兩者都另有排除）。

**下一步往第 1 種走：同一條 command list 上還有誰綁了東西。**

## 2026-11-20（讀碼）D3D12 的 SRV 狀態快取：**裸指標陣列、整張表一起重抄、而且貼圖銷毀時沒人清它**

接著「同一條 command list 上還有誰綁了東西」那一格，先把這條路在引擎裡的實際形狀讀出來
（`E:\PhysX\UE5.8`，讀碼，沒有跑任何東西）。

### 一、十一個欄位之外的槽位**不會**讀到別人留下的描述子

`FD3D12DescriptorCache::BuildSRVTable`（`D3D12DescriptorCache.cpp:439-485`）對範圍內每一槽：
有 SRV 就抄它的 offline handle，**沒有就抄 `DefaultViews.NullSRV`**，且 `check(SrcDescriptors[i].ptr != 0)`。
**所以「著色器宣告但沒填的槽位讀到上一筆的描述子」這個形狀在這個引擎裡不成立。**
（也呼應前面量到的：`SHADER_PARAMETER_TEXTURE` 沒填就是 `nullptr`，而 `ValidateShaderParameters`
對著色器**真的會綁**的 null 參數直接 `EmitNullShaderParameterFatalError`，`ShaderParameterStruct.cpp:542-553`。）

### 二、但整張表是「有一個髒就全部重抄」，而且抄的來源是**裸指標**

`FD3D12ShaderResourceViewCache`（`D3D12StateCachePrivate.h:224-225`）：

```cpp
FD3D12ShaderResourceView* Views[SF_NumStandardFrequencies][MAX_SRVS];
FD3D12Resource*           Resources[SF_NumStandardFrequencies][MAX_SRVS];
```

**兩個都是裸、不持有的指標。** 而 `D3D12StateCache.cpp:705-724`：只有當
`CurrentShaderDirtySRVSlots[Stage]`（當前著色器暫存器遮罩 ∩ 髒遮罩）不為零時才建表，
**但建表時是 `for (SlotIndex < SlotsNeeded)` 整個範圍一起抄**，髒不髒都抄。
**「髒」只表示要再抄一次，不表示槽位被清掉。**
而 `DirtyStateForNewCommandList()` 每條新 command list 都 `DirtyAll()`，
所以**每一幀都會把整個範圍重抄一遍**——抄的就是那兩個裸指標陣列裡當下的內容。

### 三、**緩衝區銷毀會清狀態快取，貼圖銷毀不會**

`ConditionalClearShaderResource`（`D3D12CommandContext.cpp:712-717`）會把指到某個
`FD3D12ResourceLocation` 的槽位清掉。它的呼叫點**全部**是：

| 呼叫點 | 對象 |
|---|---|
| `D3D12Buffer.cpp:687`、`:804` | **緩衝區**（lock／rename） |
| `D3D12ResourceCollection.cpp:119` | 緩衝區 |
| `D3D12Commands.cpp:904`、`:922` | 貼圖，但**是在它被設成 render target 的時候** |
| `D3D12RenderTarget.cpp:169`、`:266` | 貼圖，**在 RT 複製的時候** |
| `D3D12Commands.cpp:451`、`:505`、`D3D12WorkGraph.cpp:1032`、`:1274` | UAV |

**`~FD3D12Texture`（`D3D12Texture.cpp:1612-1618`）只做統計，一個字都沒碰狀態快取。**
所以一張普通貼圖銷毀之後，指著它的 `Views[]`／`Resources[]` 槽位**留在原地**。

### 四、這條路為什麼還沒被排除，以及它預期的時間形狀

延後刪除會等 GPU 過了才真的放，所以「銷毀當下還在槽位裡」本身不致命；
**致命的是上面第二點：下一幀整個範圍會被重抄，而重抄會去解參照那個裸 `FD3D12ShaderResourceView*`。**
它什麼時候會燒，取決於「什麼時候有個 SRV 範圍涵蓋那一槽的著色器來畫」——
**這正好是「故障 − heap 釋放 = 4…4116 幀」那種事件驅動、不是每幀的分布**（十五趟都是這個形狀）。

**還不是指認**，因為 DreamUI 這一筆 draw 的十一槽**每一筆都自己填滿**，
所以它自己那張表的範圍內沒有空槽可以留舊東西（第一點也排掉了空槽讀舊值）。
缺的那一塊是：**故障位址是否落在這一筆 draw 真的綁進去的某張貼圖的記憶體裡**——
上一趟用「名字」比對是陰性，而**名字不是故障報告用來指認的東西，位址才是**。

### 五、下一格：把環裡的名字比對換成**位址**比對

同一個樁，每個欄位多記兩個值：被指到那張貼圖的 **GPU 虛擬位址與大小**
（`FRHITexture::GetNativeResource()` → `ID3D12Resource::GetGPUVirtualAddress()` 與 `GetDesc()`）。
**登記讀法**：

- 故障位址落在環裡某一筆的某個欄位的 [VA, VA+size) 內 ⇒ **那一欄就是入口**，名字對不上只是名字不是同一張；
- 落不進任何一筆，而窗口又涵蓋這一趟自己的「故障 − heap」距離 ⇒
  **那個位址從來沒有以「這一筆 draw 綁的貼圖」的身分出現過**，於是第三點那條裸指標路成為主要嫌疑，
  下一步就是在引擎側補上貼圖的 `ConditionalClearShaderResource`（有 cvar、預設關）並做干預測試；
- 倒不出來或窗口短於距離 ⇒ 照第十一條，不算結果。

## 2026-11-20（第三趟樁）位址比對**量不到**——而且原因在 API 本身；但這一趟換來一個比位址更強的副產品

### 一、照登記的讀法，這是量具失敗（第二條），不是陰性

| | |
|---|---|
| `ring_blocks` / `ring_end_blocks` | 1 / 1（倒出完整） |
| `bound_lines` | 5,632 |
| **`va_nonzero`** | **0**——**每一個欄位的位址都是 0** |
| `distinct_vas` | 1（就是 `0x0`） |

**原因不是程式碼寫錯，是我沒先查那個 API 的語義**：
`ID3D12Resource::GetGPUVirtualAddress()` **對非緩衝資源（貼圖）就是定義回傳 0**。
貼圖的位址範圍在 D3D12 配置器自己的簿記裡（頁錯誤報告印的就是那份），
**那份資料在 RHI 內部，渲染外掛拿不到**。所以這個比對**從設計上就不可能**在外掛裡做成，
程式碼已拿掉，並把理由留在原地（`DreamUIBaseShaders.cpp` 的 `RecordOne`），免得下一個人再走一次。

### 二、副產品：**這一趟 DreamGUI 連一張卡片貼圖都沒綁過，而故障照樣發生**

| | |
|---|---|
| 這一趟開的卡 | **15 張** |
| 環裡保留的 draw | **131,072 筆**（整趟 246,159 筆的後 53%） |
| 環裡出現過的貼圖名字（全部） | `DreamUIDataTexture_1/3/4/6`、`DreamUIDynamicSpriteAtlasData_Texture_0`、`DreamUIFontData_DistanceField_Texture_0`、`DreamUIPreset_WhiteSolid`、`FBlackTextureWithSRV`、`FWhiteTexture` |
| 其中卡片類（`Texture2D_<n>`） | **0 筆** |
| 故障讀到的 | `Texture2D_867`，`512x512 B8G8R8A8_TYPELESS`，1.38 MB |
| 故障當幀 / heap 釋放 / 貼圖釋放 | 18765 / 18577 / 18553（故障−heap **188** 幀，故障−貼圖 212 幀） |
| 著色器 | 同一顆 `E6753E1EA9F1F20775D8BC0AD963B1EF` |

**這比第二趟更強**：第二趟 DreamGUI 綁過 19 張開頭的縮圖（`_7`..`_25`），
這一趟**整個保留窗口裡一張卡片貼圖都沒綁**，開了 15 張卡、故障仍然發生在一張死掉的卡片貼圖上。
**所以「DreamGUI 綁的東西裡沒有會故障的那一張」不是第二趟的巧合，是常態**（排除清單第二十九條更強了一層）。

覆蓋的話要照實說：卡片類名字的比對涵蓋**整個 131,072 筆環**（過濾器是按名字的，所以任何
`Texture2D_*` 都會被印出來），**但這一趟印出來的幀號只來自尾段 512 筆（span 52 幀）**，
因為非尾段只印卡片類，而這一趟卡片類是零筆——**於是「實測窗口」這個數字反而測不到了**。

### 三、第二個量具缺陷，已修

**窗口不能依賴這一趟剛好綁了什麼。** 倒出改成三段、各自有結尾標記，
而**第一段先印在全部紀錄上算出來的窗口**（`recorded`、`draws`、`frames=min..max`、`span`），
不經任何名字過濾；第二段是最後 512 筆完整內容（故障當下那一刻），第三段才是卡片類的全史。
最重要的先印，因為這段是在 GPU 崩潰報告正在寫的時候跑的，進程隨時可能被收掉。
