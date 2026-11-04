# OK Studio 工作室 UI 與工作流強化計畫

日期：2026-10-29（F 組，`F:\OpenKoikatsu`，引擎 `F:\UE5.8`）。狀態：**計畫，尚未實作**。

這份計畫以現有 OK Studio（`SceneEditor.cmd` 開的遊戲內工作室）為主體，參考 `ref/HS2Studio6`（zzzstudio：HS2 StudioNEOV2 與 KKS CharaStudio 合併復刻的 Unity 工程）的版面與操作流程，整理要補的 UI 與工作流。畫面還原（光影、LUT、天空等）不在本計畫範圍內，那部分繼續照 [OK Studio 計畫](OK_STUDIO_PLAN.md) 進行。

研究方式：
- 程式與文件：逐檔讀 `Plugins/OKStudio/Source/`、`Source/OpenKoikatsu/OKStudioScene.*`、`Tools/run_scene_editor.lua`、`Docs/OK_STUDIO_*.md`；HS2Studio6 讀它的 `Docs/`（StudioUIReplica、StudioFunctionPlan、Studio/*、快捷鍵設置、Rules/UI开发），並以 grep 對照 `Assets/Modules/HS/Runtime/UI/Replica/`、`Assets/Modules/HS/Runtime/Studio/` 的 C# 程式。
- 實機截圖（2026-10-29）：
  - OK Studio：在 F 以 `SceneEditor.cmd` 開樣本場景，截取遊戲視窗。
  - HS2Studio6：安裝 Unity Hub 3.22.5 與 Unity 6000.3.22f1（`F:\Unity\Editors\6000.3.22f1`，與 `ProjectSettings/ProjectVersion.txt` 相同），打開工程後進 `Assets/Scenes/zzzstudio.unity` 的 Play 模式，逐一打開各面板拍 Game 畫面。
  - 精簡包原本缺 KK 資源包，KKS 原作卡讀不起來。合入使用者提供的 `ref/HS2Studio6-BasicResources-WithMeta-20261029.zip` 後，4 張 KKS 原作卡都能讀入（衣服、頭髮、配件齊全），要先選中角色才能開的面板（骨骼 FK/IK 各頁、動畫、狀態、語音、服裝、定制角色／飾品、HairShader）也都拍到了。
  - 截圖、對照圖與觀察整理在第 3.8 節，重拍方式見第 11 節。

下文出處縮寫：

| 縮寫 | 路徑 |
|---|---|
| `Game.cpp` | `Plugins/OKStudio/Source/OKStudio/Private/OKStudioGame.cpp`（4,210 行） |
| `Game.h` | `Plugins/OKStudio/Source/OKStudio/Public/OKStudioGame.h` |
| `Doc.h`／`Doc.cpp` | `Plugins/OKStudio/Source/OKStudio/Public/OKSceneDocument.h`、`Private/OKSceneDocument.cpp` |
| `Actor.cpp` | `Plugins/OKStudio/Source/OKStudio/Private/OKSceneActor.cpp` |
| `Editor.cpp` | `Plugins/OKStudio/Source/OKStudioEditor/Private/OKStudioEditor.cpp` |
| HS:UIR | `ref/HS2Studio6/Docs/StudioUIReplica.md` |
| HS:FP | `ref/HS2Studio6/Docs/StudioFunctionPlan.md` |
| HS:MENU／KIN／SAVE／MCP／IFIX | `ref/HS2Studio6/Docs/Studio/菜单行为.md`、`角色运动学与动画.md`、`保存恢复与资源检查.md`、`MCP.md`、`编辑器玩法与交互修复计划.md` |
| HS:KEY／UIRULE | `ref/HS2Studio6/Docs/快捷键设置.md`、`ref/HS2Studio6/Docs/Rules/UI开发.md` |
| HS:UI/ | `ref/HS2Studio6/Assets/Modules/HS/Runtime/UI/Replica/` |
| HS:ST/ | `ref/HS2Studio6/Assets/Modules/HS/Runtime/Studio/` |

---

## 1. 目標

0. **`SceneEditor.cmd` 的畫面接近 HS2Studio6 工作室**
   - 對象是 `SceneEditor.cmd` → `Tools/run_scene_editor.lua` → `AOKStudioGameMode` 打開的遊戲內工作室，也就是 `SOKStudioPanel` 這套 Slate UI。
   - 畫面照 [版面規格](OK_STUDIO_HS2_LAYOUT_SPEC.md) 重排：
     - 外殼：左上主選單、右上工具列、角色分組、工作區、左下變換列。
     - 主題色、字級，以及每個視窗的位置、尺寸與控制項排列。
   - 驗收方式：同一張 KKS 卡、同一個面板，兩邊並排截圖，並比對版面數據（第 5 節的容許誤差）。
   - 預設視窗由 1600×1000 改成 1600×900，與 HS2Studio6 的參考解析度相同；其他大小依比例縮放。
1. **能用滑鼠直覺操作**：在視窗點選物件、多選、樹狀拖放、右鍵選單、快捷鍵在任何焦點下都有效。
2. **加入東西先看得到再選**：角色卡、道具、地圖、姿勢、場景卡都有縮圖、搜尋、收藏／最近使用。
3. **擺姿勢順手**：視窗中直接顯示並點選 FK 骨點與 IK 目標、整體軸＋骨軸並存、左右鏡像、姿勢庫有預覽。
4. **時間軸可以真的拿來做動畫**：軌道圖、關鍵影格標記可拖、多物件同時打 key、相機與燈光也能 key、輸出有進度與取消。
5. **不怕丟資料**：未存提示、自動輪換備份、讀取報告、先預覽再「覆蓋／疊加」。
6. **所有操作走同一張指令表**：UI 按鈕、快捷鍵、主控台、AI（MCP）呼叫同一個指令，也因此能做 UI 層級的自動驗收。

非目標：
- 重寫成 UMG。
- 逐像素相同：目標是版面、配色、尺寸與操作流程接近，字型與圖示可以不同。
- 原版 CharaStudio 的版面：以 HS2Studio6 為準。
- 移植 HS2 角色。

---

## 2. 現況盤點（OK Studio）

### 2.1 架構

- 外掛 `Plugins/OKStudio`：Runtime 模組 `OKStudio`、Editor 模組 `OKStudioEditor`。遊戲模組依賴 `OKStudio`。
- 啟動：`SceneEditor.cmd` → `Tools/run_scene_editor.lua` → `UnrealEditor.exe -game /Engine/Maps/Entry?game=/Script/OKStudio.OKStudioGameMode`；`AOKStudioGameMode`（`OKStudioGameMode.cpp:16-56`）下一個 tick 讀 `-OKScene=` 後呼叫 `UOKStudioGame::Start`。另有讀卡畫面「進入工作室」（`Source/OpenKoikatsu/OKStudioScene.cpp:1563-1590`）與主控台 `OKStudio.Play`。
- UI 是**純 Slate**：`SOKStudioPanel`（`Game.cpp:183-1238`）以 `GameViewport->AddViewportWidgetContent(..., 10)` 掛上（`Game.cpp:1339`），視窗互動在 `SOKStudioView`（`Game.cpp:102-180`）。
- 核心物件：
  - `UOKStudioGame`（`Game.h:19`）：工作室單例、繞行相機、**單一** `SelectedId`、Gizmo、時間軸播放、Undo、截圖與影片輸出、自測。
  - `UOKSceneDocument`：場景樹、JSON 存讀、`EvaluateTimeline`；已有 `AddObject/RemoveObject/Reparent/Duplicate`（`Doc.cpp:53` 起）。所有修改經 `NotifyChanged` 進 Undo 與同步。
  - `AOKSceneActor`：文件轉世界，分批建置；`ComponentOf`／`PreviewOf`（`Actor.cpp:866-876`）可由 Id 反查元件。
  - `FOKSceneCard`：1280×720 四格 APNG 場景卡，`okSc` chunk 內含 JSON 與 OK 角色卡。
  - `FOKStudioCatalog`：Items、Maps、FkBones（355 根）、Anims、Effects、AccessoryPoints、Filters。
- `.okscene` 欄位（`Doc.cpp:172-255`、`Doc.h:95-705`）：物件樹（Folder／Character／Item／Light／Camera／Effect、Parent、AttachBone）、角色狀態（卡、服裝、動畫、表情、視線、手、FK／IK、衣服狀態、汁、飾品顯示）、道具（Studio 目錄編號、顏色、花紋、MaterialEdits、FK）、燈光、相機（只有 Fov）、`FOKScenePost`（約 35 欄）、時間軸 `tracks[]`（`FOKSceneKey` 有 Transform、Value、Fk、角色狀態、Ease 五種、`bSmoothPath`）。
- 另有舊 UMG 工作室 `UOKStudioWidget`／`UOKStudioTimeline`（`Source/OpenKoikatsu/OKStudioScene.h:50-86`），掛在讀卡畫面「動作時間軸」按鈕（`OKGalleryWidget.cpp:391`）；[OK Studio 計畫](OK_STUDIO_PLAN.md) S2 記載要在 S7 併入，至今未併。
- 編輯器版 `FOKStudioEditor`（`Editor.cpp:275-325`）有 Outliner（真的 `STreeView`，可拖放改父，`Editor.cpp:332-345`）、Viewport、Details（反射）、Pose 分頁，但沒有時間軸、後製、姿勢檔。

### 2.2 遊戲內 UI 現況

版面：全畫面視窗＋左側固定 300 px 面板（標題、按鈕 WrapBox、場景檔區、物件列表、時間軸、狀態列）＋右側固定 330 px 屬性面板（`Game.cpp:192-265`）。沒有選單列、分頁、浮窗、分隔線、圖示。左側 18 顆平鋪按鈕（`Game.cpp:202-224`）：新場景、場景檔、+資料夾、+角色、+道具、+燈光、+相機、+特效、複製、移到根層、刪除、復原、重做、移動、旋轉、縮放、離開、用此相機。

| 項目 | 狀態 | 證據與缺口 |
|---|---|---|
| 物件樹 | 部分 | `SListView` 加縮排模擬（`RefreshRows :431`、`MakeRow :448`），`ESelectionMode::Single`（`:244`）；不能摺疊、拖放、右鍵、搜尋、改名 |
| 視窗點選物件 | 沒有 | 左鍵沒點到把手就繞行相機（`:116-120`） |
| 多選 | 沒有 | `SelectedId` 是單一 int |
| 改父／掛骨 | 部分 | 只有「移到根層」與「新物件放進所選資料夾」（`Add :1458`）；`AttachBone` 只能靠匯入或 Editor Details |
| 複製貼上 | 部分 | 只有「複製」整棵子樹；沒有剪貼簿、複製屬性或姿勢 |
| 加角色 | 部分 | 「+角色」固定用 `Cards[0]`（`:205`），再於屬性區 `SComboBox` 換卡（`:568`）；只有檔名，來源只有 `Content/CharacterCards`（`AvailableCards :1244`） |
| 道具目錄 | 部分 | 先加空道具，再選大分類→中分類→清單（`ItemBrowser :1121-1167`）；純文字，沒有縮圖、搜尋、收藏 |
| 特效 | 部分 | 「特效」按鈕循環切換（`:731`），沒有清單 |
| 動畫 | 已有 | Studio／H、群組、分類、清單（`AnimBrowser :865-918`）；沒有搜尋，`Character.Time` 沒有 UI |
| 表情／手 | 已有 | 眉、眼、嘴、手都是數字 SpinBox（`:576-618`），沒有名稱或預覽 |
| FK | 陽春 | 下拉選骨、XYZ、取目前姿勢、清除（`FkProperties :772-837`）；沒有骨骼樹、部位開關、鏡像 |
| IK | 陽春 | 13 個效果器下拉＋一個把手（`IkProperties :940-970`）；視窗內不顯示全部目標 |
| 姿勢檔 | 已有 | 讀／存 KK `.dat`，檔名自動用時間（`:814-836`）；沒有預覽、命名、刪除 |
| 道具 FK | 已有 | 每根骨三個 SpinBox（`ItemFkProperties :1204-1228`），骨頭多時很長 |
| Gizmo | 已有 | 自繪，世界軸；骨骼模式用骨骼 local 軸（`GuideHandles :1551-1615`、`ApplyGuideDrag :1638-1699`）；沒有 local／world 切換、平面把手、吸附 |
| 相機 | 部分 | 繞行／平移／縮放（`Orbit/Pan/Zoom :1711-1730`）；相機物件只有 FOV、「用此相機」；沒有聚焦所選、存視角、從視口建立相機 |
| 燈光 | 部分 | 種類循環、強度、範圍、角度、RGB SpinBox、陰影（`:750-761`）；`bCharactersOnly` 沒有 UI |
| 後製 | 部分 | 只在沒選物件時出現（`SceneProperties :1022-1118`）；ColorFilter、Background／Frame、BackgroundColor、RampG、FogColor、`MapTransform` 沒有 UI |
| 顏色 | 部分 | `#RRGGBB` 文字框（`:630`、`:660`、`:740`），沒有色盤 |
| 材質編輯 | 部分 | 原始屬性名＋值文字輸入（`:675-719`） |
| 存讀檔 | 部分 | 名稱框＋存檔（一律存場景卡，`SaveNamed :394`）、清單點一下就讀（`MakeFilesBox :346`）、KStudio 匯入要手打路徑；沒有縮圖、另存、刪除、未存提示、自動備份 |
| 時間軸 | 部分 | 單一 `SSlider`、設／刪關鍵幀、平滑、循環、播放、長度只能「+5 秒」（`MakeTimeline :270-343`）；沒有軌道、標記、拖 key、逐幀 |
| 輸出 | 已有 | 截圖 1080p／4K／透明（`:325-327`）、PNG 序列、mp4、`.okanim`（`:328-341`）；沒有進度條與取消、解析度固定 |
| 快捷鍵 | 很少 | 只有 Ctrl+Z／Y、W／E／R（`:138-151`），且要 `SOKStudioView` 有焦點 |
| Undo／Redo | 已有 | 整份 JSON 快照，停 0.4 秒合併一步，最多 100 步或約 256 MB（`:1346-1409`）；選取與相機不在歷史內 |
| Story | 已有 | 只能用命令列 `-OKStory`／`OKStory.Play`，面板沒有入口 |

### 2.3 文件記錄的缺口

- [OK Studio 計畫](OK_STUDIO_PLAN.md) S2～S7 仍「進行中」；舊「動作時間軸」待 S7 併入（`:17`）；MRQ 因 morph 斷言擱置（R3，使用者 2026-10-18 決定）；目標 120 fps 未達（`:574-621`，Slate＋viewport 約 4 ms）。
- 文件與 `Docs/ERROR_LOG.md` 的 Studio 相關列全是工程或畫面還原問題，**沒有 UI 操作性的紀錄**——代表目前沒人以「使用者工作流」的角度驗收過 UI。
- 驗收手段（`OKStudio.GameSelfTest` 24 步、`Tools/verify_ok_studio.lua`、3 個 UE Automation）都直接呼叫 API，**從未操作 Slate widget**；`Tools/ok-game-mcp` 也不支援 SceneEditor。

### 2.4 結構問題

`Game.cpp` 一個檔混了：Slate 視窗與面板（約 1,140 行，`:102-1238`）、`UOKStudioGame` 本體（`:1240-1938`）、七個 `Run*Test`（約 2,000 行，`:1940-3985`）、主控台指令（`:3990-`）。面板類別宣告在 cpp 裡，`Game.h:12` 只有前向宣告。任何 UI 改動都會跟其他 session 在這個檔撞在一起，必須先拆。

---

## 3. HS2Studio6 可借鏡的設計

以下只列與 OK Studio 對應、且他們有實作或驗證證據的部分。

### 3.1 版面與視窗生命週期

- 左上四個主選單：**添加**（角色、項目、地圖、光照、背景、前景框）、**動畫**（狀態、骨骼、動畫、語音、服裝、關節校正…）、**音效**、**系統**（設定、保存、載入、備份恢復、資源檢查、初始化、結束）（HS:UIR#實現狀態；`HS:UI/StudioReplicaUI.cs:895-945`）。
- 右上工具列 `menu／work／move／color／option／camera`，綠＝開、藍＝關（`HS:UI/StudioReplicaUI.cs:370-390`）。
- 右上工作區 240 寬，列高 18、縮排 12，搜尋框在樹下；底部 9 個工具鈕：解除父級、設父級、刪除、複製變換、複製子樹、新資料夾、新相機、新路線、材質編輯器（`HS:UI/StudioReplicaUI.cs:731-755`）。
- **詳情窗互斥**：切到別的條目先關舊窗；再點一次目前條目就關；選中非角色時角色詳情自動關（HS:MENU#選單切換與窗口生命週期）。**獨立浮窗**（Timeline、動畫控制器、道具搜尋、材質編輯器）不受互斥管。
- 通用窗口：標題可拖、點任何可見處置前、視口變窄時等比縮小（HS:UIRULE#遮擋時點擊置前）。

### 3.2 物件與目錄

- 角色載入器：資源管理器式路徑列、多根目錄樹、三欄縮圖、底部搜尋與翻頁、「定位當前」、背景分幀產生縮圖、讀失敗保留原角色並提示「部分恢復」（HS:UIR#角色入口與窗口切換）。
- 項目目錄三欄（分組→分類→條目），懸停約 180 ms 顯示完整名稱與預覽；沒縮圖時用獨立相機即時算 256 px 預覽，最多快取 12 張。
- **瀏覽與套用分開**：地圖要按「讀取」、圖像要按「應用」才生效（HS:UIR#產品區分）。
- 道具快搜（複刻 QuickAccessBox，`HS:UI/StudioReplicaUI.QuickSearch.cs`）：空格分詞 AND、`-詞` 排除；篩選／收藏／隱藏／全部；空搜尋顯示收藏與最近使用；左鍵加入、**中鍵加到所選物件底下**、右鍵收藏／隱藏。
- 樹：雙擊就地改名（Enter／失焦提交、Esc 取消、空白或同名不產生歷史）；Shift 選區間；設父級以最後選的為父；解除父級保留世界變換並拒絕循環；刪除是停用保留實例以便撤銷（HS:UIR#混合工作區命令與存檔）。
- **拖放掛載**：把道具拖到角色部位分組（頭髮、頭、臉、頸、胸背、腰、四肢、手、下腹）或樹上的物件；綠可放、紅拒絕；停 450 ms 自動展開、靠邊自動捲動（HS:UIR#角色掛點與道具跟隨；`HS:ST/StudioCharacterAttachments.cs`）。

### 3.3 姿勢

- 新加入人物預設開 IK；FK 預設開胸、身體、左右手、裙子，關頭髮、頸部；切分頁只瀏覽不切模式（HS:KIN#所選角色操縱）。
- FK 7 組白點加層級連線；IK 13 個目標，紅＝末端、藍＝肘膝。操作軸固定**世界尺寸**（0.1–1，預設 0.4），控制點固定**螢幕尺寸**（FK 約 24 px、IK 約 36 px）；控制點點選優先於遮住它的軸。
- **整體軸＋骨軸並存**，整體軸樞軸取匯入時雙腳中點並固定；左下「主軸：顯示／隱藏」（`HS:UI/StudioReplicaUI.cs:505`）。選到只能移動的 IK 點時暫時改用移動軸。
- 「數值」展開骨骼清單可輸入；「復位」回動畫基態；「跨控制複製」把目前解算姿勢寫進另一模式；權重子頁（`HS:UI/StudioReplicaUI.KinematicWeights.cs`）。
- **FK／IK 有獨立撤銷歷史**，撤銷時不動表情、視線、動畫，也保留目前視口鏡頭（HS:KIN#2026-10-24 撤銷範圍修正）。
- 鏡像他們尚未做（HS:FP#近期實施批次 5），是我們可以超前的地方。

### 3.4 動畫與時間軸

- 動作窗三欄（組、分類、動作），搜尋同時比對中文名與原名；**動畫控制器做成獨立浮窗**（速度、動作變化、輔助 1/2、循環、播放／暫停／停止），關列表後仍留著並記住位置（HS:KIN#動畫窗格與漢化）。
- Timeline（`HS:UI/StudioReplicaUI.Timeline.cs`）：播放、停止、回 0、拖進度、時長、循環、清空、打 key、刪 key、打姿勢幀、單骨加／刪幀；目標以**產品＋穩定 ID** 定位，改名或合併場景後仍對得上。
- 他們自己的已知坑（HS:FP#完善程度）：關鍵幀不在撤銷內、`Seek` 不取樣、**Timeline 在 Update 寫骨骼後 `StudioKinematics.LateUpdate` 又解算覆蓋**、沒有表情／鏡頭軌道、沒有影片輸出。我們的時間軸要從一開始就驅動文件／FK 狀態，而不是直接寫骨骼。

### 3.5 相機、燈光、輸出

- 相機面板：FOV、透視／正交、近遠面；使用此鏡頭、下一鏡頭、聚焦所選、**從視口建立鏡頭**；**十個書籤**（含聚焦距離），書籤操作進撤銷歷史（HS:UIR#燈光與鏡頭參數）。
- 導航（HS:KEY#工作室鏡頭導航）：可切原版軌道模式；**拖動必須從視口開始**；Ctrl+Space 回初始鏡頭。
- 燈光：作用對象（全部／角色／地圖）、內外錐角、陰影軟硬；只有選中的燈在視口顯示標記，輸出時隱藏。
- 截圖導出（F12）：720p／1080p／4K／自訂、透明背景、背景圖、前景框；自動排除 UI 與軸；不覆蓋既有檔；「本次目錄」（HS:UIR#工作室截圖導出）。

### 3.6 存讀與可靠性

- 場景卡窗：目錄樹＋4 欄×3 列縮圖；**點卡片只預覽，再選「覆蓋／疊加／取消」**；疊加保留現有物件並合併時間軸、不動鏡頭與環境（HS:UIR#場景卡瀏覽、覆蓋與疊加）。
- 單一物件讀取失敗只跳過，全部失敗才回滾；讀完跳「讀取報告」可複製。
- 存檔先暫存、預檢再替換，原子寫入。
- 自動備份預設開，每 5 分鐘、保留 10 份；載入中、拖動中、播放中延後；內容沒變跳過（HS:SAVE#自動備份與恢復入口）。
- **未保存提示**：初始化、讀取、恢復備份、結束時問「保存並繼續／不保存繼續／取消」（HS:SAVE#未保存提示）。
- 資源檢查：列出所選角色缺件、空材質、不支援 Shader，可「補齊後重試」（HS:SAVE#所選角色資源檢查）。

### 3.7 快捷鍵、規範、MCP

- 快捷鍵（HS:KEY；`Shared/Runtime/StudioShortcutSettings.cs:8`）：Z 隱藏 UI、W／E／R、L 世界／局部、F 聚焦、Delete、Ctrl+C／V、Ctrl+Z／Y、F2 設定、F5 畫面、F12 截圖、Ctrl+Space、Esc。**全部可重綁、有衝突檢查；文字框有焦點時停用；提示文字依綁定動態產生。**
- Undo：`MaxHistoryEntries = 100`（`HS:ST/StudioItemRuntime.cs:20`）；一次滑桿拖動只記一筆；載入場景後清空。
- UI 規範（HS:UIRULE）：只有「選中」「開啟」用綠色；所有清單同時支援滾輪與可拖捲軸；共用一個調色盤（再點同色塊關閉）；有「當前選中項」的清單頂部要有「定位當前」；說明用 `?` 圖示懸停顯示、點擊固定。
- MCP（HS:MCP#第一階段工具；`HS:ST/StudioMcpBridge.cs`、`StudioMcpCommands.cs`）：本機 TCP，14 個工具（status、scene_inspect、catalog_search、object_spawn、object_transform、object_reparent、object_delete、character_rig、character_pose、camera_set、capture、scene_save、undo、redo）；物件用穩定 ID；**AI 與手動共用同一份歷史**；使用者拖動中、載入中、播放中拒絕 AI 修改；存檔不准覆蓋既有檔。

### 3.8 實機截圖觀察（2026-10-29）

截圖只留本機，不進版控（`Saved/` 與 `ref/` 都已在 .gitignore）：

| 資料夾 | 內容 |
|---|---|
| `Saved/StudioUIRef/ok/` | OK Studio 現況，3 張 |
| `Saved/StudioUIRef/hs2/` | HS2Studio6 各面板，`00`～`67` |
| `Saved/StudioUIRef/compare/` | 兩邊並排的對照圖，10 張 |

**對照圖**

| 對照圖 | OK Studio 現況 | HS2Studio6 | 對應階段 |
|---|---|---|---|
| `compare/01_layout_scene_loaded.png` | 左右兩條固定側欄，左欄塞滿按鈕、物件列表、時間軸與輸出鈕，視窗區被擠窄 | 四個主圖示固定在左上；右上依序是工具列、角色分組欄、工作區；左下是變換列；中間視口留空 | U1 |
| `compare/02_add_character.png` | 選中角色後，在屬性面板的下拉選單裡只看得到檔名 | 角色載入器：女／男、刷新、目錄、路徑列、根目錄樹、縮圖格、搜尋與翻頁、大預覽與角色名、「添加默认角色／读取／替换选中角色」 | U3-1 |
| `compare/03_scene_files.png` | 場景檔是純文字清單，點一下就讀 | 場景卡窗有目錄樹（全部／HS／KK、包含子文件夹、選擇文件夾、搜尋）；點縮圖彈出大預覽，再選「覆盖／叠加／取消」 | U7-1 |
| `compare/04_timeline.png` | 左下一條滑桿，加一排平鋪按鈕 | 獨立 Timeline 浮窗：播放／停止／回 0s、時長、循環、清空軌道、打姿勢幀、打關鍵幀／刪關鍵幀、骨骼搜尋、打骨骼幀／刪骨骼幀、軌道列表 | U6 |
| `compare/05_item_catalog.png` | 先加空道具，再到屬性面板選分類 | 浮窗：HS／KK 頁籤、搜尋框、分組→分類→條目三欄、底部顯示「HS: 1 个项目」計數 | U3-2 |
| `compare/06_settings_post.png` | 沒選物件時，右欄才顯示後製參數 | F2 設定：左邊分類（游戏选项、快捷键、插件设置、键位指南、资源目录），頂部搜尋；每列有 `?` 說明與「应用／默认」；底部提示「滑条即时保存，文本点击应用」 | U8-2、U9-1 |
| `compare/07_pose_fk.png` | FK 在一長串屬性面板中段：下拉選骨＋XYZ | 「骨骼」窗左側子頁（FK、IK、视线、颈部、表情、手势、姿势、权重）；FK 頁有功能開關、「动画位置姿态／IK反向控制姿势」、部位開關（头发、颈部、胸部、身体、右手、左手、裙子）各帶「初始化／复位」、操作軸 0.4、控制點 1、「数值」 | U5 |
| `compare/08_animation.png` | 動畫在同一屬性面板裡，有 Studio／H 切換與群組下拉 | 動畫窗：全部／女／男／共用頁籤，分组→分类→动作三欄，搜尋＋重置，「34 个动作」計數；旁邊是獨立的「动画控制器」浮窗（速度、动作变化、辅助 1/2、循环、播放、停止） | U5、U6-6 |
| `compare/09_character_state.png` | 9 部位衣服各一顆循環鈕 | 狀態窗：「全穿／半脱／全裸」一鍵，加上每部位「穿／半／脱」三態按鈕、飾品逐槽「显示／隐藏」 | U3-5 |
| `compare/10_expression.png` | 眉、眼、嘴是數字 SpinBox | 表情頁：眉毛、眼睛、嘴巴顯示目前編號，各有「上一个／下一个」；眼睛開合、嘴巴開合滑桿；眨眼開關 | U5-7 |

**其他觀察**

- **讀取報告與佔位列**（`hs2/23_scene_loaded_later.png`）
  - 覆蓋讀入後跳出「场景卡读取报告」，逐條列出無法解析的欄位與找不到的 Studio Mod（含 group/category/no），附「复制问题清单」按鈕。
  - 缺件的道具不會消失，而是以「缺失 Studio Mod [19870101/101/3]」佔位列留在工作區；之後補齊資源，再存檔時不會丟掉。這點值得照做，已併入 U7-6。
- **變換列固定在左下**（`hs2/00_start.png`）
  - 位置、旋轉、縮放各一列 XYZ 數值，每列一個「重置」。
  - 旁邊有「复制变换／粘贴变换／重置变换」、「主轴：显示」和移動／旋轉／縮放三個模式圖示。
  - 滑鼠停在圖示上，提示會連快捷鍵一起顯示（例：「旋转 · E；世界/局部轴 · L」）。
  - 已併入 U4-2、U9-2。
- **添加光源**（`hs2/06_light_add.png`）：小窗列出方向光、点光源、聚光灯、区域光四顆按鈕，加一行「当前灯光：1」；連續添加時窗不關。
- **地圖與背景**（`hs2/07_map.png`、`hs2/08_background.png`）：左邊清單，右邊預覽，下方「读取地图」「设置」「应用背景」。瀏覽和套用是分開的。
- **相機**（`hs2/19_camera.png`）
  - 「当前视口镜头」窗：視口操作（原版轨道／自由飞行）、投影（透视／正交）、視野角度、正交大小、近／遠裁剪面、背景顏色、HDR、MSAA，加上「使用这个镜头」「切换到下一镜头」。
  - 標題列有「截图导出」入口。
- **系統選單**（`hs2/10_system_menu.png`）：设置、保存、载入、备份恢复、资源检查、初始化、返回标题、结束。
  - 備份恢復（`hs2/12_backup.png`）：「立即备份／刷新列表／备份设置」。
  - 資源檢查（`hs2/13_resource_check.png`）：「补齐后重试／资源目录／复制报告」；沒選角色時顯示「请先选择角色」。
- **快搜與姿勢庫**（`hs2/16_quick_search.png`、`hs2/17_pose_library.png`）
  - 都是左側小圖示「找／姿」開的獨立浮窗，可與其他窗並存。
  - 快搜有 HS／KK 篩選、「筛选列表」下拉、「刷新目录」，底部提示「输入关键词搜索；空白时显示收藏与最近使用」。
  - 姿勢庫有搜尋、刷新、上一页／下一页、計數。
- **材質編輯器**（`hs2/20_material_editor.png`）：模型、材質、屬性三欄，屬性可篩選，底部有匯出路徑與「应用／默认」。
- **角色的詳情窗按功能拆頁**（`hs2/52`～`67`）
  - 「anim」選單：状态、骨骼、动画、语音、服装、关节校正、定制角色、定制饰品、HairShader。每項開一個詳情窗，標題列都顯示「当前角色：<名字>」。
  - OK Studio 現在把角色的所有屬性放在同一條長捲動面板（`ok/02_character_selected.png`），要捲很久才找得到 FK 或表情。已併入 U1-3：角色詳情改成分頁窗。
- **骨骼各子頁**
  - IK（`hs2/61_bones_ik.png`）：全部、身體、右手、左手、右腳、左腳開關，各帶「复位」。
  - 視線（`hs2/62_bones_look.png`）：相机、正面、背离、固定、指定；指定位置（角色局部座標）XYZ；「取镜头位置」「恢复看镜头」；下方有一行說明文字。
  - 頸部（`hs2/63_bones_neck.png`）：相机、姿势、正面、背离、固定，加「跟随强度」滑桿。
  - 手勢（`hs2/65_bones_hand.png`）：左右手各有上一个、下一个、复位，顯示目前 ptn 與可選總數。
  - 姿勢（`hs2/66_bones_pose.png`）：大字「0 / 63」加上一个、下一个、「复位默认 T-pose」。
  - 權重（`hs2/67_bones_weight.png`）：整體權重、目前目標（上一个目标／下一个目标）、目標位置與旋轉權重、「复位整体与当前目标权重」。
- **讀卡後的回饋**
  - 角色一讀入，視窗立刻顯示 IK 控制點（紅＝末端、藍＝肘膝），工作區與角色分組欄同步出現該角色（13 個分組、54 個部位）。
  - 載入器下方訊息分兩種：完整時顯示「角色已添加」；有缺件時顯示「部分资源未恢复，请查看所选角色资源检查」。已併入 U3-1、U7-7。
- **其他角色窗**
  - 語音（`hs2/55_voice.png`）：左邊原版語音分組，中間性格清單，右邊播放佇列（加入选中语音、顺序到尾停止、播放队列、移除选中、上移／下移、清空）。
  - 服裝（`hs2/56_clothes.png`）：服裝卡瀏覽，「编辑当前角色材质」「服装：开启／关闭」「饰品：开启／关闭」。
  - 定制角色（`hs2/58_custom_char.png`）：左邊部位（上衣～接发），右邊部件清單分頁（例：122 项）。
  - 定制飾品（`hs2/59_custom_acc.png`）：飾品槽切換、校正節點、位置／旋轉／縮放數值、掛點清單（a_n_*）。
  - HairShader（`hs2/60_hairshader.png`）：後髮、前髮、鬢髮、接髮的部件清單，加「编辑头发 Shader / 材质」。
  - 這些屬於在 Studio 裡直接換裝與捏人，不在本計畫範圍（見第 9 節）。
- **反面教材**
  - 以 Game 視窗 1.8 倍縮放顯示時，Timeline 浮窗的「骨骼」那一列文字與按鈕互相重疊（`hs2/18_timeline.png`）。OK Studio 的 UI 驗收要在兩種以上的 DPI／視窗大小截圖檢查（見 U1 驗收）。
  - 聊天框與角色分組欄預設就開著，佔掉右側大片空間；OK Studio 不做聊天（第 9 節），工作區相關的欄預設只開一個。

---

## 4. 差距對照

| 領域 | OK Studio 現況 | HS2Studio6 參考 | 本計畫 |
|---|---|---|---|
| 版面 | 兩條固定側欄、平鋪按鈕 | 主選單＋工具列＋互斥詳情窗＋獨立浮窗 | U1 |
| 指令與快捷鍵 | 5 個鍵、依賴視窗焦點 | 註冊表、可重綁、衝突檢查 | U0、U9 |
| 視窗點選／多選 | 沒有 | 視口點選、Shift 加選 | U2 |
| 物件樹 | 縮排清單 | 改名、拖放、掛載、搜尋 | U2 |
| 角色／道具目錄 | 純文字、下拉 | 縮圖、搜尋、收藏、懸停預覽、中鍵加為子物件 | U3 |
| Gizmo／相機 | 世界軸、無聚焦、無書籤 | L 切軸、F 聚焦、10 書籤、從視口建鏡頭 | U4 |
| 姿勢 | 下拉選骨／效果器 | 視窗骨點、雙軸、跨控制複製、姿勢庫 | U5 |
| 時間軸 | 單一滑桿 | 軌道與 key 操作（但有求值順序坑） | U6 |
| 存讀可靠性 | 點了就讀、無提示 | 預覽→覆蓋／疊加、報告、自動備份、未存提示 | U7 |
| 外觀參數 | `#RRGGBB`、後製欄位缺 UI | 共用調色盤、F5 分類設定與預設 | U8 |
| AI／自動驗收 | API 自測、MCP 不支援 | 14 工具、共用歷史、忙碌時拒絕 | U0、U9 |

---

## 5. 設計原則

1. **文件是唯一真相**：UI、快捷鍵、時間軸、MCP 都只改 `UOKSceneDocument`，再由 `NotifyChanged` → Undo → `AOKSceneActor::Sync`。不在 UI 直接動 Actor 或骨骼（避開 HS2Studio6 時間軸被運動學覆蓋的坑）。
2. **一張指令表**：每個操作有 `Id`、顯示名、預設快捷鍵、`CanExecute`、`Execute`；按鈕、選單、快捷鍵、主控台 `OKStudio.Cmd <id> [json]`、MCP 都走它。這同時解決快捷鍵焦點問題與 UI 驗收問題。
3. **維持 Slate**：遊戲內 UI 已是 Slate（`Game.cpp:183`），繼續用；不引入 UMG。Editor 版 `FOKStudioEditor` 不追求功能對等，只保持能開檔、存檔、反射編輯。
4. **顏色規則**：沿用 HS2Studio6 的「只有選中／開啟用綠色」；一次性動作不用強調色。所有清單可滾輪與拖捲軸；有當前項的清單要有「定位當前」。
5. **效能預算**：UI 改動不得讓 `Tools/run_ok_studio_perf.lua` 量到的幀時間變差超過 0.5 ms；縮圖一律背景解碼、分幀建立。
6. **版面以規格為準**
   - 位置、尺寸、配色、字級都取自 `Docs/StudioUI/hs2studio6_layout_spec.json`，不憑截圖目測。
   - 容許誤差：視窗矩形 ±4 參考單位，控制項 ±2，顏色與字級要相同。
   - 規格沒有涵蓋的 OK 專有功能（Story、`.okanim` 輸出、KStudio 匯入、後製細項），沿用同一套主題，放在最接近的選單或視窗裡。
7. **不破壞格式**：`.okscene` 只加欄位（`version` 照舊或 +1 並保留讀舊版）；場景卡 `okSc` 不變。

---

## 6. 分階段計畫

每階段結束都要：`OKStudio.GameSelfTest` 全過（目前 24 步）、`Tools/lua/lua.exe Tools/verify_ok_studio.lua --tag <名稱>` 結果與前一版相同、`Tools/run_ok_studio_perf.lua` 幀時間不退步，再加上該階段自己的驗收。U1 起每階段都要用 `OKStudio.UiLayout` 輸出該階段動到的面板，與[版面規格](OK_STUDIO_HS2_LAYOUT_SPEC.md)對應步驟比對（第 5 節的容許誤差），並重拍並排截圖。

### U0　拆檔與指令表（先做，P0）

目的：讓後續 UI 工作可以分檔並行，並建立可自動驗收的入口。

| 項目 | 內容 |
|---|---|
| U0-1 拆 `Game.cpp` | `Run*Test` 七個自測搬到 `Private/OKStudioGameTests.cpp`；`SOKStudioView` 搬到 `Private/SOKStudioViewport.h/.cpp`；`SOKStudioPanel` 宣告移到 `Private/SOKStudioPanel.h`，再依區塊拆 `SOKStudioOutliner`、`SOKStudioInspector`（Character／Item／Light／Camera／Effect／Scene 各一個 `.cpp`）、`SOKStudioTimelineBar`、`SOKStudioFileBrowser`。主控台指令留在 `OKStudioGame.cpp` 或移到 `OKStudioConsole.cpp`。純搬移，不改行為。 |
| U0-2 指令表 | 新增 `Private/OKStudioCommands.h/.cpp`：`FOKStudioCommand { FName Id; FText Label; FInputChord Default; TFunction<bool()> CanExecute; TFunction<void(const FJsonObject*)> Execute; }`，註冊現有 18 顆按鈕的動作。按鈕改成 `MakeCommandButton(Id)`。 |
| U0-3 全域快捷鍵 | 用 `FSlateApplication::RegisterInputPreProcessor` 掛工作室專用前處理器：工作室執行中、焦點不在可編輯文字框時，依指令表派發快捷鍵。取代 `SOKStudioView::OnKeyDown`（`Game.cpp:138-151`）只在視窗有焦點才生效的做法。 |
| U0-4 主控台與控制通道 | 主控台 `OKStudio.Cmd <id> [json]`、`OKStudio.UiState`（輸出開著的窗、選取、焦點、指令可用狀態 JSON）。新增 `OKStudio.UiSelfTest`：只透過指令表操作完成「加角色→選取→移動→存檔→讀檔→復原」。 |

驗收：GameSelfTest 24/24、`verify_ok_studio.lua` 與拆檔前結果一致；`OKStudio.UiSelfTest` PASS；在視窗外（例如點過右側屬性面板後）按 Ctrl+Z 仍能復原。

### U1　SceneEditor 外殼改成 HS2Studio6 版面（P0）

尺寸、錨定與配色都取自[版面規格](OK_STUDIO_HS2_LAYOUT_SPEC.md)的「外殼」與「主題」兩節，下表只列對應關係。

| 項目 | 內容 |
|---|---|
| U1-1 左上主選單 | 取代現在左欄的 18 顆平鋪按鈕（`Game.cpp:202-224`）。<br>• 左上直排四個主圖示：加入、角色（anim）、音效、系統；35 寬，對應規格的 `RootToolbar`。<br>• 點一下展開 80 寬的子選單（`AddPanel`／`AnimationMenu`／`SystemMenu`）。<br>• 加入：角色、道具、燈光、相機、特效、資料夾、地圖、背景／前景框。<br>• 角色：狀態、骨骼、動畫。<br>• 系統：設定、儲存、讀取、備份恢復、資源檢查、匯入 KStudio、播放故事、離開。<br>• 選單項目一律來自指令表。<br>• 左側另放「姿」「找」兩個 33×33 小鈕（姿勢庫、快搜）。 |
| U1-2 右上工具列 | 33×33、間距 40 的圖示列，對應 `TopTool_*`：工作區、移動、顏色、選項、相機、角色分組。開啟中用綠 `#00A514`。 |
| U1-3 浮窗框架 | 新增 `SOKStudioWindow`：標題列可拖、點擊置前、關閉鈕、記住位置。<br>• 詳情窗（狀態、骨骼、動畫、道具目錄、燈光…）一次只開一個，預設位置照規格，例如狀態 134,7,252,326、骨骼 134,7,320,390、動畫 135,10,446,370。<br>• 獨立浮窗不受這個限制：動畫控制器 160×332、Timeline 520×260、快搜 360×590、姿勢庫 360×368、相機 300×429。 |
| U1-4 右側兩欄 | 右上依序是角色分組欄（240×429）與工作區（240×429），取代現在左欄的物件列表和右欄的長屬性面板（`SceneProperties :1022` 的後製改到「畫面設定」窗）。<br>• 工作區欄：標題、展開／收起全部、樹（列高 18）、Timeline 鈕加搜尋框、工具圖示兩排（28×28）。<br>• 角色的屬性改成「角色」選單底下的分頁詳情窗：狀態、骨骼（FK／IK／視線／頸部／表情／手勢／姿勢／權重）、動畫。<br>• 標題列顯示目前角色名（參考 `hs2/52`～`67`）。 |
| U1-5 左下變換列 | 478×60，對應 `TransformBar`：位置、旋轉、縮放三列 XYZ 加「重設」、複製／貼上／重設變換、主軸開關、移動／旋轉／縮放模式鈕（細節在 U4-2）。 |
| U1-6 主題與縮放 | `FOKStudioStyle` 集中定義規格的主題色、字級（11／10／12／16）與常用尺寸。以 1600×900 為基準依視窗高度等比縮放；右側群組靠右上錨定，變換列靠左下。`Tools/run_scene_editor.lua` 的預設視窗改成 1600×900。 |
| U1-7 隱藏 UI 與狀態 | `Z`（可重綁）隱藏全部 UI；提示訊息與背景工作進度改成畫面下方的小字列，不占用側欄。 |
| U1-8 版面輸出與保存 | 新增 `OKStudio.UiLayout <名稱>`：把 Slate 版面樹輸出成和 HS2Studio6 dump 相同欄位的 JSON，給 `Tools/studio_layout_spec.lua` 比對。窗口開關與位置記在 `Saved/OKStudio/ui_layout.json`。 |

要動：
- `SOKStudioPanel`（U0 拆檔後的各檔）
- 新增 `SOKStudioWindow.h/.cpp`、`SOKStudioRootMenu.cpp`、`SOKStudioTransformBar.cpp`、`OKStudioStyle.h/.cpp`
- `Tools/run_scene_editor.lua`（預設視窗大小）
- `Tools/studio_layout_spec.lua`（加入比對模式）

驗收：
- 開空場景，用 `OKStudio.UiLayout` 輸出版面，與規格的 `00_empty` 比對。四個主圖示、右上工具列、兩個右側欄、變換列的矩形都在 ±4 以內，顏色與字級相同。
- 加入選單、角色選單、系統選單分別與 `01`、`10`、`40` 比對。
- 並排截圖：`Saved/StudioUIRef/compare/` 重拍 01、06，HS2Studio6 那側用 `hs2/L_00_empty.png`、`hs2/L_01_add_menu.png`。
- `OKStudio.UiState` 確認詳情窗一次只開一個、浮窗不受限制。
- 1280×720 與 1600×900 兩種視窗大小都沒有元件被裁掉。
- 效能不退步。


#### 完成紀錄（2026-10-29，F 組，未 commit）

**U0**
- **拆檔**
  - 面板與視窗類別搬到 `Private/SOKStudioPanel.h`。
  - 自測搬到 `Private/OKStudioGameTests.cpp`。
  - 自測共用的骨骼輔助函式放在 `Private/OKStudioGameInternal.h`。
  - `OKStudioGame.cpp` 從 4,210 行減到 1,074 行。
- **指令表**：52 個指令，按鈕、快捷鍵、主控台共用；清單見 `OKStudio.UiState`。
- **全域快捷鍵**：用 `IInputProcessor` 實作，焦點在文字框或故事模式時不觸發。
  - Ctrl+Z／Y／D／S／C／V：復原、重做、複製物件、儲存、複製變換、貼上變換。
  - W／E／R 切換移動、旋轉、縮放；Z 隱藏介面；Delete 刪除；Esc 關閉視窗或選單。
- **主控台指令**：`OKStudio.Cmd`、`OKStudio.UiState`、`OKStudio.UiLayout`，以及 `OKStudio.RunScript`（逐行執行指令，支援 `wait N`、`shot NAME`、`quit`）。
- 還沒做：`OKStudio.UiSelfTest`。

**U1**
- **外殼**：左上主選單（加入、角色、音效、系統）與固定高度子選單、右上工具列、角色分組欄（10 組、54 個掛點，可掛到所選部位）、工作區樹（可摺疊、搜尋、眼睛鈕、工具鈕）、左下變換列（XYZ、重設、複製／貼上／重設變換、主軸、模式鈕）。
- **詳情窗**：一次只開一個，依頁面定位。狀態、骨骼（FK、IK、視線、頸部、表情、手勢、姿勢檔七個子頁）、動畫、屬性、畫面設定、場景檔、角色載入器、道具目錄（三欄）、添加光源、相機。
- **時間軸**：獨立浮窗。
- **主題與縮放**：`OKStudioStyle.h`；縮放與 HS2Studio6 相同，scale = √((W/1600)·(H/900))。
- `Tools/run_scene_editor.lua` 預設視窗改成 1600×900。
- 10-29 當時還沒做：視窗拖動與置前、`ui_layout.json` 版面保存、各視窗內部改成新樣式、圖示。10-30 已完成（`SOKStudioWindows.cpp` 浮窗與版面保存、`OKStudioStyle.h` 的 `SIcon` 向量圖示），見下方「驗收（2026-10-30）」。

**驗收**
- **版面比對**：`Tools/lua/lua.exe Tools/studio_layout_spec.lua --compare 00_empty,01_add_menu,10_anim_menu,11_state,12_bones_fk,20_animation,40_system_menu,04_item_catalog,05_light_add,53_camera,52_timeline`。所有外殼區塊與已對應的視窗誤差都在 0.2 單位以內（容許 ±4）。報告在 `Saved/StudioUIRef/compare/layout_*.txt`。
- **截圖**：用 `SceneEditor.cmd` 加 `OKStudio.RunScript Saved/StudioUIRef/scripts/u1_shell.txt` 拍攝。並排對照圖是 `Saved/StudioUIRef/compare/U1_*.png`（9 張）。
- **既有自測**：`Tools/lua/lua.exe Tools/verify_ok_studio.lua --tag U1Shell1029`，6 項過 5 項。
  - 通過：GameSelfTest、PatternTest、BloomTest、GradeTest、TransparencyTest。
  - 失敗：EyeSetTest 的「漩渦眼」（swirl）。同一份 log 顯示測試卡 `Content/CharacterCards/CrowdAPNG/C002.png` 缺 3 樣開卡資源（10-28 嚴格開卡之後的檢查）；10-23、10-24 的紀錄是通過。尚未用改動前的版本重跑確認是否與 UI 無關。
- 還沒做：效能（`run_ok_studio_perf.lua`），以及 1280×720 視窗下的檢查。

#### U1 剩餘到 U9 的實作清單與決定（2026-10-29，F 組）

使用者指示：剩下的問題自行決定，列出完整清單後全部實作。以下是逐項清單與做法上的決定；完成後在各階段補完成紀錄。

**檔案配置**：面板仍是 `SOKStudioPanel`（`SOKStudioPanel.h` 宣告，內聯的外殼程式留在原處），新功能的成員函式寫在分檔的 `.cpp`：
- `SOKStudioWindows.cpp`：浮窗框架、版面保存、對話框、角色卡瀏覽器、快搜、姿勢庫、場景瀏覽器、色盤、設定、截圖、輸出、報告、資源檢查、備份恢復。
- `SOKStudioTimeline.h/.cpp`：時間軸元件。
- `OKStudioSettings.h/.cpp`：`Saved/OKStudio/settings.json`（快捷鍵、相機速度、Gizmo 尺寸、吸附步進、自動備份、卡片根目錄、介面縮放）與 `favorites.json`。
- `OKStudioThumbnails.h/.cpp`：縮圖背景解碼與 LRU 快取。
- `OKStudioControl.cpp`：SceneEditor 控制通道（HTTP，127.0.0.1）。

**決定**
1. 快捷鍵衝突：計畫裡 F2 同時是「改名」（U2-3）和「設定窗」（U9-1）。改名用 F2（Windows 慣例，也可雙擊）；設定窗改成 F1。
2. Ctrl+C／Ctrl+V 改成複製／貼上物件（U2-5）；複製／貼上變換改成 Ctrl+Shift+C／Ctrl+Shift+V，變換列按鈕不變。
3. 視窗點選不做 ID buffer：角色用骨架上多個骨點投影到畫面的外框、其他物件用元件 bounds 投影；點中多個時取離相機最近的。
4. 多選時 Gizmo 以主選物件為樞紐，位移與旋轉在世界座標套用到其他選取物件；縮放各自乘上同一比例。
5. 道具懸停預覽：另開一個隱藏的場景 Actor 只放那一個道具，放在遠處，用 `FOKSceneCard::Capture` 拍 256 px，快取 12 張。
6. 地圖沒有縮圖來源（基礎庫沒轉出地圖縮圖），地圖瀏覽器只列名稱與分類，按「讀取」才換。這點記為限制。
7. 表情、手型名稱：基礎庫沒有名稱表，使用遊戲的編號加上已知類別名稱（眉、眼、嘴、手型）；名稱表放在 `OKStudioNames.h`，之後有來源再替換。
8. 時間軸新軌道：相機的 FOV 沿用 `Value`；燈光顏色加 `FOKSceneKey::Color`；畫面設定用 `ObjectId = -2` 的場景軌道，key 加 `Exposure`、`FocalDistance`；角色動畫時間加 `AnimTime`（< 0 不控制）。舊檔欄位不變。
9. 自動備份預設 5 分鐘、10 份；內容雜湊沒變就跳過；拖動中、載入中、播放／輸出中延後。
10. 控制通道沿用 street 的做法（`HTTPServer` 模組），埠由 `-StudioControlPort=`（預設 47890）指定，只在帶 `-Control` 時開。`ok-game-mcp` 新增 `studio_*` 工具，以 `OK_STUDIO_PORT` 指定埠。
11. U6-8：讀卡畫面的「動作時間軸」改成開 OK Studio 並把目前角色放進去。舊 UMG 工作室的「從影片產生動作」新時間軸沒有對應功能，所以影片動作面板保留，其餘舊工作室程式移除。

**清單**
| 階段 | 項目 |
|---|---|
| U0 | `OKStudio.UiSelfTest`：只透過指令表跑「加角色→選取→移動→存檔→讀檔→復原」，之後每階段加步驟 |
| U1 | 浮窗拖動（標題列）與置前（點擊）；詳情窗與浮窗位置、開關、各欄顯示存進 `Saved/OKStudio/ui_layout.json`；窗內控制項（下拉、數值框、勾選、文字框）改成主題樣式；1280×720 檢查；效能量測 |
| U2 | 視窗點選；多選（Shift／Ctrl、樹的區間選）；批次刪除、複製、隱藏，一次 Undo；拖放改父與掛骨；雙擊或 F2 改名；種類篩選；定位當前；右鍵選單；物件剪貼簿（跨場景、重配 Id）；Undo 記住選取 |
| U3 | 角色卡瀏覽器（多根目錄、縮圖網格、搜尋、翻頁、預覽、加入／替換）；道具目錄搜尋、懸停預覽、中鍵加為子物件；快搜（AND、排除、收藏、隱藏、最近使用）；特效清單；地圖瀏覽；表情、手型、衣服狀態改名稱清單 |
| U4 | 世界／局部（L）、平面把手、Ctrl 吸附、拖動時顯示數值、把手大小可調；F 聚焦、Ctrl+Space 回初始、前／側／上視角、自由飛行（按住右鍵 WASD＋QE）；從視角建相機、存視角到相機、近遠面、下一相機；十個視角書籤（Ctrl+數字存、數字讀）；只畫所選燈的範圍或錐角 |
| U5 | 視窗骨點（IK 13 點、FK 骨點與連線）與點選；FK／IK 部位開關；雙軸；鏡像（全部、左→右、右→左）；IK←FK；跨角色複製姿勢；姿勢庫（縮圖、命名、刪除、搜尋、試套）；可搜尋的骨骼樹（角色 FK 與道具 FK）；表情窗與視線按鈕組、注視點拖動 |
| U6 | 時間軸浮窗（時間尺、播放頭、物件列與子列、菱形 key）；key 點選、框選、拖動、刪除、複製貼上、改 Ease、K 打 key；時長輸入、逐幀、首尾、循環區間、速度、30 fps 吸附；新軌道；拖播放頭真的取樣；輸出對話框（範圍、fps、解析度、資料夾、進度、取消、開資料夾）；舊動作時間軸改入口 |
| U7 | 場景瀏覽器（縮圖、搜尋、排序、刪到 Trash、改名、覆蓋／疊加／取消）；`Merge`；另存、Ctrl+S、KStudio 匯入共用瀏覽器；原子寫入；未存提示與標題 `*`；自動備份與備份恢復窗；讀取報告與佔位列；資源檢查 |
| U8 | 色塊與色盤浮窗（最近使用色）；畫面設定分頁（相機、環境／天空、霧、泛光、景深、色調／LUT、暗角、背景／前景框，補 ColorFilter、Background、Frame、BackgroundColor、RampG、FogColor、MapTransform）；後製預設；燈光作用對象與種類按鈕；材質屬性下拉；截圖窗（F12） |
| U9 | 設定窗（F1）；快捷鍵重綁、衝突檢查、恢復預設、提示文字依綁定；`ok-game-mcp` 的 `studio_*` 工具與 `Docs/OK_STUDIO_MCP.md`；「播放故事」選單 |

### U2　選取、多選與物件樹（P0）

| 項目 | 內容 |
|---|---|
| U2-1 視窗點選 | `SOKStudioView::OnMouseButtonDown`（`Game.cpp:116`）先測把手，再做選取：角色用骨骼膠囊或部件 bounds（預覽角色是自訂渲染、未必有碰撞）、道具與燈光相機用元件 bounds／圖示，經 `AOKSceneActor::ComponentOf`／`PreviewOf` 反查 Id。左鍵點擊（按下到放開移動 < 4 px）才算選取，拖動仍繞行相機，維持既有相機手勢（[相機輸入](CAMERA_INPUT390.md)）。 |
| U2-2 多選 | `SelectedId` 改成 `TArray<int32> Selection` 加 `PrimaryId`；Shift／Ctrl 加選；Gizmo 以主選物件為樞紐、同時套用所有選取（`GuideHandles :1551`、`ApplyGuideDrag :1638`）；刪除、複製、隱藏對整批作用、一次 Undo。 |
| U2-3 真的樹 | 工作區改 `STreeView`（Editor 版 `Editor.cpp:332-345` 已有可參考的拖放改父）：摺疊、Shift 區間選、雙擊或 F2 改名（Enter／失焦提交、Esc 取消、空白或同名不入歷史）、可見性眼睛鈕、種類圖示、搜尋與依種類篩選、「定位當前」。 |
| U2-4 改父與掛骨 | 拖放到物件＝改父，保留世界變換、拒絕循環；拖到角色的部位節點＝設 `AttachBone`，部位分組沿用 HS2Studio6 的頭髮／頭／臉／頸／胸背／腰／四肢／手／下腹，對應 `FOKStudioCatalog::AccessoryPoints`；綠可放、紅拒絕、停 450 ms 展開。 |
| U2-5 右鍵選單與剪貼簿 | 右鍵：改名、複製、貼上、刪除、隱藏、移到根層、設為父、聚焦、存成…。Ctrl+C／Ctrl+V／Ctrl+D／Delete。剪貼簿格式用 `UOKSceneDocument::ToJson` 的物件片段（可跨場景貼上，貼上時重新配 Id）；另有「複製變換／貼上變換」「複製角色狀態／姿勢」。 |
| U2-6 選取進 Undo | 復原後恢復當時選取（但不恢復視口相機，同 HS2Studio6）。 |

要動：`Game.h`（`SelectedId` 的全部使用處）、`SOKStudioViewport`、`SOKStudioOutliner`、`Doc.h/.cpp`（`Duplicate(TArray)`、`PasteFragment`、`ReparentKeepWorld`）。

驗收：UiSelfTest 新增「視窗點選角色→Shift 加選道具→一起移動→一次 Undo 還原兩者」「拖道具到角色右手→存讀後仍跟隨」「Ctrl+C 後到新場景 Ctrl+V」；GameSelfTest 既有的 undo／子接點步驟不退步。

### U3　目錄與加入流程（P1）

| 項目 | 內容 |
|---|---|
| U3-1 角色卡瀏覽器 | 浮窗：多根目錄（`Content/CharacterCards`、`Config/DefaultGame.ini` 的遊戲 `UserData/chara`、使用者自訂資料夾，記在 `Saved/OKStudio/settings.json`）、路徑列、縮圖網格（PNG／APNG 第一格，背景解碼、分幀建立）、搜尋、翻頁、「定位當前」。點一下預覽，按「加入」或「替換所選角色」才生效；讀失敗保留原角色並提示。取代 `+角色` 固定用 `Cards[0]`（`Game.cpp:205`）與屬性區下拉（`:568`）。 |
| U3-2 道具目錄 | 三欄（大分類→中分類→條目）＋搜尋；懸停 180 ms 顯示完整名稱與預覽，沒有縮圖時用 SceneCapture 即時算 256 px、快取 12 張；左鍵加入、**中鍵加到所選物件底下**。取代先加空道具再選的流程（`ItemBrowser :1121-1167`）。 |
| U3-3 快搜 | 獨立浮窗（快捷鍵可設）：同時搜尋道具、特效、地圖、動畫、姿勢；空格 AND、`-詞` 排除；收藏、隱藏、最近使用存在 `Saved/OKStudio/favorites.json`。 |
| U3-4 特效與地圖 | 特效改清單選擇（取代循環切換 `:731`）；地圖瀏覽器有縮圖，按「讀取」才換地圖。 |
| U3-5 名稱化 | 表情（眉、眼、嘴）、手型、衣服狀態從數字 SpinBox 改成名稱清單（來源：卡片／目錄已有的名稱表），保留數值輸入作進階。 |

要動：新 `SOKStudioCardBrowser`、`SOKStudioCatalogBrowser`、`SOKStudioQuickSearch`、`OKStudioThumbnails.h/.cpp`（縮圖快取，共用 `FKKAnimatedPng` 解碼）；`FOKStudioCatalog` 補名稱／縮圖查詢。

驗收：100 張卡的資料夾開窗後 UI 不卡頓（perf 量測開窗期間幀時間）；搜尋與中鍵加子物件有 UiSelfTest 步驟；人工檢查清單：從零加一個角色＋三個道具＋換地圖，點擊次數比現況少（記錄在驗收文件）。

### U4　Gizmo 與相機（P1）

| 項目 | 內容 |
|---|---|
| U4-1 Gizmo | 世界／局部切換（L）、平面把手（XY／YZ／XZ）、Ctrl 吸附（移動 0.1 m、旋轉 15°、縮放 0.1，可設）、拖動時在狀態列顯示數值、把手大小固定螢幕尺寸可調。 |
| U4-2 數值輸入 | 照 HS2Studio6 左下變換列（`hs2/00_start.png`）做一條常駐變換列：位置／旋轉／縮放各一列 XYZ（可拖拉、可輸入）＋每列「重設」、「複製／貼上／重設變換」、移動／旋轉／縮放模式鈕、「主軸」開關。屬性面板不再重複放 Transform。 |
| U4-3 相機操作 | F 聚焦所選（多選取合併 bounds）、Ctrl+Space 回初始視角、前／側／上預設視角、可選的自由飛行模式（WASD＋QE，右鍵按住時才生效）；預設仍是現有繞行。拖動必須從視窗開始（現況已如此，[相機輸入](CAMERA_INPUT390.md)）。 |
| U4-4 相機物件 | 「從目前視角建立相機」「把目前視角存到所選相機」、近遠面、下一相機；十個視角書籤（Ctrl+數字存、數字讀，存在場景內），書籤操作進 Undo。 |
| U4-5 燈光標記 | 只顯示所選燈的範圍／錐角線；截圖與影片輸出時隱藏所有標記與 Gizmo（確認 `Screenshot :1914` 已排除）。 |

要動：`SOKStudioViewport`、`UOKStudioGame::GuideHandles/HitGuide/ApplyGuideDrag/Orbit/Pan/Zoom`、`Doc.h`（相機加 Near／Far、場景加 `CameraBookmarks[10]`）。

驗收：UiSelfTest「選角色→F→相機距離落在 bounds 內」「建相機→存書籤→移動→讀書籤回到原位」；吸附後數值為步進倍數；局部軸旋轉後的移動方向以數值檢查。

### U5　姿勢工作流（P1）

| 項目 | 內容 |
|---|---|
| U5-1 視窗骨點 | 姿勢模式下在視窗畫出：IK 13 目標（紅＝末端、藍＝肘膝）、FK 骨點與層級連線；骨點固定螢幕尺寸、點選優先於遮住它的軸。資料來源：`FOkSession::IkEffectorPosition`、`BoneWorldMatrix`。 |
| U5-2 部位開關 | FK 依部位分組（身體、胸、頭髮、頸、左右手、裙子）開關，預設照 HS2Studio6；IK 同理。取代單一下拉選骨（`FkProperties :772-837`）。 |
| U5-3 雙軸 | 選骨點時同時保留角色整體軸（樞軸為雙腳中點、縮小顯示），可用「主軸」開關隱藏；選到只能移動的 IK 點時自動改移動軸。 |
| U5-4 鏡像與複製 | 左右鏡像（整體、只左→右、只右→左），骨名對照用 `FOKStudioCatalog::FkBones` 的 `_L/_R` 規則；「FK←目前姿勢」（現有「取目前姿勢」）、「IK←FK」；跨角色複製姿勢。 |
| U5-5 姿勢庫 | 浮窗：KK `.dat` 與 OK 姿勢列表、縮圖（存姿勢時用目前視角拍 256 px）、命名、刪除、搜尋、套用前預覽（暫套、取消可還原）。目前存檔名自動用時間（`:814-836`）。 |
| U5-6 骨骼清單 | 「數值」展開骨骼樹可直接輸入；道具 FK（`ItemFkProperties :1204-1228`）改同一個樹元件，骨頭多時可搜尋。 |
| U5-7 表情與視線 | 表情窗：眉／眼／嘴名稱清單、開合滑桿、眨眼；視線與頸部（照動畫／看鏡頭／注視點／固定）改成按鈕組，注視點可在視窗拖動。 |

Undo：姿勢拖動仍走整份快照（現有機制已能還原 FK／IK），但一次拖動只記一筆；不另開獨立歷史，避免兩套歷史互相干擾（HS2Studio6 的獨立歷史是因為他們的運動學狀態不在場景資料內；我們的 FK／IK 已在 `FOKSceneCharacter::Fk/Ik` 裡）。

要動：`SOKStudioViewport`（骨點繪製與點選）、`SOKStudioInspector_Character`、新 `SOKStudioPoseLibrary`、`OKStudioPose.cpp`（鏡像）、`Game.cpp` 中 `ok_unity_euler_rotate` 相關骨骼拖曳（`:1667`）。

驗收：UiSelfTest「點右手 IK 點→移動→Undo」「鏡像左右後骨骼尤拉角對稱（數值比對）」「存姿勢→讀回→FK 相同」；既有 `OpenKoikatsu.Studio.SavedPose` Automation 仍過；人工截圖：一個角色擺出坐姿，記錄操作步數。

### U6　時間軸（P2）

| 項目 | 內容 |
|---|---|
| U6-1 時間軸浮窗 | 新 `SOKStudioTimeline`：時間尺、播放頭、每個有軌道的物件一列（可展開成 Transform／FK／角色狀態／數值子列），key 以菱形標示；取代單一 `SSlider`（`MakeTimeline :270-343`）。 |
| U6-2 key 操作 | 點選、框選、Shift 加選 key；拖動改時間、Delete 刪、Ctrl+C／V 複製到播放頭；右鍵改 Ease（現有五種）；「為所有選取物件打 key」（K）。key 操作進 Undo。 |
| U6-3 時間控制 | 時長直接輸入（取代只能 +5 秒）、逐幀（, .）、回開頭／結尾、循環區間、播放速度、吸附到整數幀（30 fps）。 |
| U6-4 新軌道 | 相機（Transform＋FOV）、燈光（顏色、強度）、後製數值（曝光、DOF 距離）。`FOKSceneKey::Value` 已能放數值，必要時加 `Property` 名稱欄位。 |
| U6-5 求值順序 | `EvaluateTimeline` 只寫文件欄位，再交給 `Sync`；動畫播放與 FK／IK 依文件狀態解算，**時間軸絕不直接寫骨骼**，避免 HS2Studio6 已知的覆蓋問題。拖動播放頭時真的取樣（他們的 `Seek` 不取樣是已知缺口）。 |
| U6-6 動畫時間 | 角色的 `Character.Time` 與 `Speed` 給 UI，並可上軌道，讓 Studio 動畫可以被定格在某一幀。 |
| U6-7 輸出 | PNG 序列／mp4／`.okanim` 改成對話框：範圍、fps、解析度、輸出資料夾；進度條與取消；完成後可開啟資料夾。 |
| U6-8 舊動作時間軸 | 把 `UOKStudioTimeline`（`Source/OpenKoikatsu/OKStudioScene.h:50-86`）的功能對照到新時間軸，完成後讀卡畫面「動作時間軸」改為開 OK Studio，舊 UMG 工作室移除（即 [OK Studio 計畫](OK_STUDIO_PLAN.md) S7 的併入項）。 |

要動：新 `SOKStudioTimeline.h/.cpp`；`Doc.h/.cpp`（key 選取不入檔、新軌道屬性）；`UOKStudioGame::SetTimelineTime/TickExport`；`Source/OpenKoikatsu/OKStudioScene.*`、`OKGalleryWidget.cpp:391`（U6-8）。

驗收：GameSelfTest 時間軸步驟不退步；新增「相機軌道兩個 key → 中間時刻 FOV 為插值」「拖 key 後 Undo」「輸出 3 秒 PNG 序列中途取消，不留半成品以外的檔」；人工做一段 5 秒雙物件動畫並輸出 mp4，記錄步驟。

### U7　存讀與可靠性（P1）

| 項目 | 內容 |
|---|---|
| U7-1 場景瀏覽器 | 浮窗：目錄樹＋縮圖網格（場景卡第一格）、搜尋、排序（時間／名稱）、刪除（移到 `Saved/OKStudio/Trash/`）、改名；點卡片只預覽，再選「覆蓋」「疊加」「取消」。取代點一下就讀（`MakeFilesBox :346`）。 |
| U7-2 疊加 | 新 `UOKSceneDocument::Merge`：重新配 Id、保留現有物件、時間軸合併、不改相機與後製。 |
| U7-3 另存與匯入 | 儲存（Ctrl+S，已有檔名就覆寫）、另存新檔、KStudio 匯入改用同一個瀏覽器選檔（取代手打路徑）。存檔先寫暫存檔再替換。 |
| U7-4 未存提示 | 文件有 dirty 旗標；新場景、開檔、恢復備份、離開時問「儲存並繼續／不儲存／取消」；標題列顯示 `*`。 |
| U7-5 自動備份 | 預設每 5 分鐘、保留 10 份，存在 `Saved/OKStudio/Backup/`；載入中、拖動中、播放／輸出中延後；內容雜湊沒變就跳過；「備份恢復」窗列出時間與縮圖。 |
| U7-6 讀取報告 | 單一物件失敗只跳過，讀完顯示報告（缺卡、缺 zipmod、缺道具、無法解析的欄位），附「複製問題清單」；KStudio 匯入沿用現有 `.import.json` 報告。缺件的物件保留為工作區佔位列（例：「缺少道具 [群組/分類/編號]」），原始欄位原樣留在文件裡，補齊資源後重讀即可恢復，存檔也不會遺失（參考 `hs2/23_scene_loaded_later.png`）。 |
| U7-7 資源檢查 | 「場景→資源檢查」列出所有角色與道具的缺件，連到對應物件（點了就選取）。 |

要動：新 `SOKStudioFileBrowser`（U0 已拆出）、`SOKStudioDialog`（通用確認框）、`Doc.cpp`（`Merge`、dirty、原子寫入）、`UOKStudioGame::Save/Load/Tick`（備份計時）。

驗收：UiSelfTest「改動後按開檔→出現未存提示→取消→文件未變」「疊加兩個場景後 Id 不衝突、存讀一致」；手動刪掉一張卡後讀場景，報告列出該卡且其他物件正常；強制中斷存檔（自測注入失敗）時舊檔不受損。

### U8　外觀參數補全（P2）

| 項目 | 內容 |
|---|---|
| U8-1 共用色盤 | 一個 `SOKStudioColorPicker` 浮窗（Slate `SColorPicker` 包裝＋最近使用色），所有顏色欄位改成色塊；再點同一色塊關閉、換選取時解除綁定。取代 `#RRGGBB` 文字框（`:630`、`:660`、`:740`）與燈光 RGB SpinBox（`:750-761`）。 |
| U8-2 後製面板 | 獨立「畫面設定」窗，依分類分頁（相機、環境／天空、霧、泛光、景深、色調／LUT、暗角、背景／前景框）；補上目前沒有 UI 的 ColorFilter、Background／Frame、BackgroundColor、RampG、FogColor、`MapTransform`。滑桿旁可直接輸入數值。 |
| U8-3 預設 | 後製預設存 JSON（`Saved/OKStudio/PostPresets/`），用目前相機拍縮圖。 |
| U8-4 燈光 | 補 `bCharactersOnly`（作用對象）UI；種類改按鈕組。 |
| U8-5 材質編輯 | 屬性名改為下拉（從材質實際參數列出），數值依型別給滑桿／色塊／貼圖選擇；保留原始文字輸入作進階（`:675-719`）。 |
| U8-6 截圖窗 | F12：預設解析度＋自訂、透明背景、輸出資料夾、檔名樣式、不覆蓋既有檔、完成後提示路徑。取代三顆固定按鈕（`:325-327`）。 |

驗收：GameSelfTest 的後製與截圖步驟不退步、`OKStudio.PostTest`／`GradeTest`／`BloomTest` 仍過；每個新增 UI 欄位做存讀來回比對（存檔 JSON 欄位值相同）。

### U9　設定、快捷鍵重綁與 AI 控制（P2）

| 項目 | 內容 |
|---|---|
| U9-1 設定窗 | F2，版面照 `hs2/14_settings.png`：左側分類（一般、快捷鍵、相機與 Gizmo、備份、資源目錄、快捷鍵一覽）、頂部搜尋設定項、每列附 `?` 說明與「套用／預設」，滑桿即時生效、文字欄按套用才生效。內容：快捷鍵、相機速度、Gizmo 尺寸、吸附步進、自動備份、卡片根目錄、介面縮放；存 `Saved/OKStudio/settings.json`。 |
| U9-2 快捷鍵重綁 | 從指令表列出所有指令，可重綁、衝突檢查、恢復預設；按鈕提示文字依綁定動態產生；文字框有焦點時停用（U0-3 已做）。說明選單的快捷鍵一覽也由指令表產生。 |
| U9-3 SceneEditor 控制通道 | `Tools/ok-game-mcp` 加入 SceneEditor 支援（Rust）：沿用 `-Control` 的本機通道，新增 `studio_*` 工具——state、inspect、catalog_search、spawn、transform、reparent、delete、pose、camera、capture、save、undo、redo、cmd（任意指令表 Id）。物件用文件 Id；AI 與手動共用同一份 Undo；使用者拖動中、載入中、播放／輸出中拒絕修改；存檔不覆蓋既有檔。說明寫進 [街區遊戲 MCP](STREET_SOCIAL_GAME_MCP.md) 或另開 `Docs/OK_STUDIO_MCP.md`。 |
| U9-4 Story 入口 | 場景選單加「播放故事」，不必再靠命令列 `-OKStory`。 |

驗收：`ok-game-mcp call studio_spawn ...` 等工具在 `-Sandbox` 下跑一輪完整腳本（加角色、擺姿勢、拍照、存檔）；重綁 W 到別的鍵後按鈕提示同步更新、舊鍵失效。

#### U1 剩餘到 U9 完成紀錄（2026-10-30，F 組，未 commit）

**程式位置**（`Plugins/OKStudio/Source/OKStudio/Private/`）
| 檔案 | 內容 |
|---|---|
| `SOKStudioPanel.h` | 外殼、指令表（約 130 個指令）、快捷鍵（依設定綁定）、樹、屬性頁、主題化的屬性列元件 |
| `SOKStudioWindows.cpp` | 浮窗（拖動、置前、`ui_layout.json`）、確認框與未存提示、樹的編輯（拖放、剪貼簿、右鍵）、場景瀏覽器、備份恢復、讀取報告、資源檢查、播放故事、截圖窗、時間軸窗、輸出窗、設定窗 |
| `SOKStudioBrowsers.cpp` | 角色卡瀏覽器、道具懸停預覽、快搜、特效清單、地圖瀏覽、色盤與色塊、畫面設定九個分頁與預設 |
| `SOKStudioPose.cpp` | 場景視窗的滑鼠（點選、Gizmo、骨點、注視點、飛行）與疊加繪製（多選外框、燈光範圍、骨點、注視點）；FK／IK 頁、鏡像、IK←FK、姿勢庫、骨骼樹、表情、手型、視線 |
| `SOKStudioTimeline.h/.cpp` | 時間軸元件 |
| `OKStudioGameView.cpp` | 點選、聚焦、視角預設、書籤、相機物件、自動備份、讀取報告、忙碌判斷 |
| `OKStudioSettings.h/.cpp`、`OKStudioThumbnails.h/.cpp` | 設定與收藏、縮圖 |
| `OKStudioControl.cpp` | 控制通道 `/studio/<op>` |
| `OKStudioUiSelfTest.cpp` | `OKStudio.UiSelfTest` |

資料模型（`OKSceneDocument`）：相機 `Near`／`Far`、`Bookmarks[10]`、key 的 `Color`／`AnimTime`／`Exposure`／`FocalDistance`、場景軌道（`SceneTrackId = -2`）、`ExportFragment`／`PasteFragment`／`Merge`、原子寫入；角色加 `Blink`。舊檔照常讀取。
`ok-game-mcp`：`studio_*` 19 個工具（`Tools/ok-game-mcp/src/studio.rs`），說明在 [OK Studio MCP](OK_STUDIO_MCP.md)。

**驗收（2026-10-30）**
- `OKStudio.UiSelfTest`：46/46（`Saved/OKStudio/ui_selftest.txt`）。涵蓋 U0 的指令表流程、U2 的點選／多選一起移動／一次 Undo／掛到右手後存讀／跨場景貼上、U3 的快搜與中鍵加子物件、U4 的聚焦／書籤／吸附／局部軸、U5 的 IK 拖動與 Undo／鏡像對稱／姿勢存讀、U6 的 FOV 與曝光插值／key 拖動 Undo／中途取消輸出、U7 的未存提示／疊加／原子寫入失敗不損舊檔／備份、U8 的色盤與新欄位存讀、U9 的快捷鍵重綁與版面保存。
- `Tools/lua/lua.exe Tools/verify_ok_studio.lua`：GameSelfTest（tag `Game1030b`）、PatternTest、BloomTest、GradeTest、TransparencyTest 通過；EyeSetTest 仍失敗，原因見下。GameSelfTest 的三個 Gizmo 檢查原本寫死「3 個把手」，改成只數 X／Y／Z 並另外確認平面把手與角色雙軸存在。
- 版面比對：`studio_layout_spec.lua --compare` 11 個步驟全部在 ±4 以內（最差 0.2）。截圖 `Saved/StudioUIRef/ok/U2_*.png`（30 張，腳本 `Saved/StudioUIRef/scripts/u2_all.txt`）。
- 1280×720：`studio_layout_spec.lua --bounds` 8 個畫面（空場景、系統選單、骨骼、時間軸、角色卡、場景檔、設定、快搜）都沒有元件超出視窗（腳本 `u2_720.txt`；腳本裡每步先 `r.setres 1280x720w`，因為執行中視窗曾被放大）。
- 控制通道：SceneEditor 加 `-Control -StudioControlPort=47890`，用 `ok-game-mcp call studio_*` 跑完加角色、FK＋鏡像、表情與視線、正面聚焦、截圖、存檔、Undo／Redo、時間軸打 key；截圖與存檔都拒絕覆蓋既有檔。
- 效能（2026-10-31，`run_ok_studio_perf.lua --count 8`，1920×1080；機器上同時有另外 2 個 Unreal 在跑）：`perf1031a`（逐像素深度測試開）與 `perf1031b`（`OK_UNITY_DEPTH_TEST=0`）比，關掉反而每張都慢 1～10 ms，代表這時的數字由其他遊戲的負載主導，深度測試本身沒有量得到的成本。和 10-24 的 `final1024` 比，遊戲執行緒多 1～3 ms、GPU 差不到 0.7 ms，同樣受負載影響，不能當成退步的證據；要在只有一個 Unreal 時重量才算數。結果在 `F:\OpenKoikatsu\Saved\OKStudio\perf\perf1031a.json`、`F:\OpenKoikatsu\Saved\OKStudio\perf\perf1031b.json`。
- EyeSetTest：2026-10-31 `verify_ok_studio.lua --tag F1031a` 6 項全過（含 EyeSetTest，`C002.png` 已由 e-okcard 的 `70b762429` 重轉）。
- **EyeSetTest 漩渦眼**：不是 UI 造成的。OK 卡 `C002.png` 平常開得起來（眼型 0 時 69 個部件）；切到眼型 23 時要換成 gag eye 部件重建，而轉卡時只記錄了卡片預設狀態的開卡閉包，模型 `3e5b33000000000056e2c0bf4f4b4331` 的骨架不在卡內也不在基礎庫，10-28 嚴格開卡後就開不了。`ok-extract --oklib seal` 照預設狀態重放，補不到（試過，卡片已還原）。要在 ok-extract 轉卡／seal 時把「會換部件的眼型」也記錄進閉包，或讓基礎庫收 gag eye 模型，屬 OK 卡工具（e-okcard）的範圍。測試另加了「整張卡開不了時換下一張本機卡」。
  - 10-30 e-okcard 回覆：E `duo2` commit `70b762429` 修好（尚未 push）。轉卡在各套服裝之後，對 gag 物件 1／2／3 各取一個眼型（21、23、27），用 outfit 0 再開一次並記錄，每張卡多 3 筆 skeleton，digest 不變。舊卡要用該版之後的 ok-extract 重轉，seal 只用基礎庫，補不到 mod 頭。F 等該 commit 合併進來後，重轉 `C002.png` 再跑 EyeSetTest。
  - 10-30 整合後：70b762429 已在 F 的 HEAD。但 `C002.png` 的 `okId`（原作卡 sha256 `663284207c…`）在 F 這台的遊戲 `UserData`、`Content/CharacterCards`、`Saved` 都找不到相符的原作卡，無法用新版重轉。需要原作卡的人（轉出這批 CrowdAPNG 的 checkout）重轉後放回本機。

**沒做到或做法不同的地方**
- 遠面：Unreal 的透視投影沒有遠面，`Far` 原本只存檔、不影響畫面。2026-11-01 補上：OKStudio 外掛自己註冊一個 SceneViewExtension（`OKStudioGame.cpp` 的 `FOKStudioFarPlaneExtension`，只在工作室用場景相機、`Far` > 0 時啟用，工作室停止就清掉；不改 Config、不換共用的 LocalPlayer，C／E 不受影響），在 `SetupView` 把原點等於工作室視角的視圖（畫面、截圖、`capture`；鏡子與螢幕道具的 capture 看出去的點不同，不套）的無限遠反向 Z 透視投影換成有遠面的版本（`FReversedZPerspectiveMatrix` 的 MinZ／MaxZ），遠面外逐像素裁掉。實測 `83283571_p1` 相機 310：遠面 10 m 只剩前景，25 m 裁掉後牆與天空，設回 0 恢復（`C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\06cb08af-708c-4559-954f-993ce591a332\scratchpad\far_c2500.png`）。正交照舊用 `OrthoFarClipPlane`。屬性列標籤改成「遠面 cm（0 無）」。`verify_ok_studio.lua --tag far_1101` 6/6。近面有效（`UOKStudioViewCamera`）。
- 地圖縮圖：KK Studio 的地圖清單（`abdata/studio/info` 的 `Map` 表）本身就沒有縮圖欄位，原作也只列名稱；維持只列名稱。
- 表情與手型名稱：U11 從遊戲資料補上眼型與手型名稱；眉型、嘴型遊戲資料沒有名稱，維持編號。
- U6-8：讀卡畫面「動作時間軸」改成開 OK Studio 並打開時間軸。舊 UMG 工作室已在 U11 移除（2026-10-30）。

---

### U10　完整 MCP：AI 擺初版、人手細調（2026-10-30 追加並完成，F 組，未 push）

使用者指示：工作室 UI 要接完整的 MCP，之後用 AI 擺初版、再由人細調。

| 項目 | 內容 |
|---|---|
| 控制通道新 op | `patch`（物件任意欄位深合併）、`scene`（畫面設定、地圖與位置、時長、使用中相機、書籤）、`bones`（FK 骨與世界座標、13 個 IK 點、注視點、54 個掛點）、`bounds`（世界範圍與 `built`）、`catalog`（依分類瀏覽道具／地圖／特效／動畫／濾鏡／天空／掛點）、`keys`（列出、打、刪、移、Ease、清除、平滑路徑；`-2` 是場景軌道）、`duplicate`、`export`（PNG／mp4／.okanim，進度在 `state.export`）、`scenes`、`report`、`ui_shot`（含 UI 的視窗截圖） |
| ok-game-mcp | 再加 11 個工具，`studio_*` 共 30 個 |
| 讀取類 op | 使用者拖動、載入、播放時也會回答；修改類照舊回 `busy` |
| 文件 | [OK Studio MCP](OK_STUDIO_MCP.md) 加「AI 擺初版、人手細調」與座標規則（角色 rotation 0 面向 +Y＝前視相機） |

實測：SceneEditor 加 `-Control`，用 `ok-game-mcp call` 依序目錄瀏覽／搜尋 → 加兩個角色與一張桌子 → `studio_bounds` → `studio_patch` 改名 → 動畫與 FK＋表情＋視線 → 天空、泛光、景深 → 兩個 key 加 Ease → 正面相機 → 截圖與 UI 截圖 → 複製／刪除 → 讀取報告 → 存檔 → 場景清單 → Undo／Redo，全部成功。實測中發現並修好：道具是由自己的預覽 Actor 顯示的，原本的範圍計算只看 `ComponentOf`，道具一律回 30 cm 代替框（也影響視窗點選、聚焦、材質屬性下拉、道具懸停預覽）。改完 UiSelfTest 仍 46/46。

EyeSetTest 漩渦眼（使用者 2026-10-30：缺的元件從 `D:\KoikatuSunshine` 補到共用資源）：還沒補成。`ok-extract --oklib record` 加了 `OK_RECORD_STATUS`（Studio 狀態 JSON，例如 `{"eyes_ptn":23}`），能以 Studio 狀態開卡做記錄（不寫 parity）。但 OK 卡開卡只走基礎庫，不讀遊戲的 zipmod；把 C002 去掉 `ok*` 區塊還原成原作卡再以遊戲記錄，0 筆未命中：遊戲版 `[minih] headmod v4` 的記錄已存在，但記在另一個模型 id 下，C002 指名的是 `3e5b33000000000056e2c0bf4f4b4331`。要在轉卡／seal 時對「會換部件的眼型」另外開一次並收進卡或基礎庫，已把細節交給 e-okcard。實驗動到的基礎庫版控檔已還原，C002 嚴格檢查仍通過。重現：`OK_RECORD_STATUS={"eyes_ptn":23} ok-extract X:/NoGame --oklib replay Content/IndependentResources/base_v1 Content/CharacterCards/CrowdAPNG/C002.png`。

### U11　用遊戲資料補完剩下的缺口（2026-10-30，F 組，未 push）

使用者：缺的元件可以到 `D:\KoikatuSunshine` 找，補到共用資源裡。

| 項目 | 結果 |
|---|---|
| 眼型名稱 | 角色清單 `cha_eyeset`（分類 2）41 個名稱（デフォルト、ウィンク、ぐるぐる目…）。`ok-extract D:/KoikatuSunshine --oklib studio-names <base_v1>` 寫進 `base_v1/studio_items.json` 的 `eye_names`（只新增 378 行，其他內容不變）；表情頁的眼型下拉顯示「編號 名稱」 |
| 手型名稱 | Studio `HandAnime` 表（左右各 21 個）寫進 `hand_names`；手型頁顯示中文名與原片段名（例：「1 握拳（goo）」） |
| 眉型、嘴型名稱 | 遊戲清單沒有，維持編號 |
| 地圖縮圖 | KK Studio 的地圖清單本來就沒有縮圖，維持只列名稱 |
| 影片動作 | 影片匯入的結果就是 `Saved/VideoMotions/*.okanim` 與 `*.pair.json`；角色加 `AnimFile`（任何 .okanim，含輸出的時間軸動畫），動畫頁列出雙人動作與動畫檔：雙人動作把女方給主選角色、男方給另一個選取（或下一個）角色，同時從 0 秒開始。指令 `anim.file`、`anim.pair`；MCP 的 `studio_pose` 加 `anim_file`、`video_pair`，`studio_catalog` 加 `video` |
| 舊 UMG 工作室 | 刪除 `Source/OpenKoikatsu/OKStudioScene.h/.cpp` 與 `Tools/video_motion/test_studio.lua`；讀卡畫面進 OK Studio 的程式搬到 `OKGalleryOkStudio.cpp`；人物編輯 MCP 的 `studio` 動作改成 enter／cmd／exit（場景編輯走 `studio_*`） |
| 診斷 | `OK_STUDIO_INFO_DUMP=1` 時 studio 目錄轉換印出各表與角色清單分類 |
| 影片動作的格式 | 影片動作檔是 session 片段（`OKCLIP01`），不是動作庫的 `OKANIM02`，第一版用 anim player 讀而失敗（角色標成「未顯示」）。改成：`AnimFile` 開頭是 `OKCLIP01` 且在 `Saved/VideoMotions` 時，以 `video:\|<名稱>` 交給角色自己的 session 播（`SetGameAnimation`，PoseMode 2），場景時鐘與時間軸也推動 PoseMode 2。實測 `網球示範.okanim` 播放 10.37 秒、循環 |
| 燈光開關（使用者回報） | 角色的卡通著色只讀一盞「角色光」（勾了「只照角色與道具」的方向光），而且不看它有沒有開：關燈、刪燈、或新增一般燈都不影響角色。改成：取「顯示中」的角色光，沒有就取第一盞顯示中的方向光；場景有過燈但全部關掉時角色進入陰影色；燈光頁加「開啟」勾選（等於樹上的顯示）。新燈預設強度 6 → 4（換算 1.0，Studio 角色光的預設），原本 1.5 倍把角色照到泛白。實測（`Saved/StudioUIRef/ok/L0_main.png`～`L4_dir_on_again.png`）：主光、方向光逐一關掉後角色變暗，再開回復 |
| 點光、聚光照角色 | 和原作一致，不需補：原作角色著色器 `Koikano/main_skin` 只有 ForwardBase（描邊、本體）與 ShadowCaster 三個 pass，沒有 ForwardAdd，所以 KKS 裡點光與聚光本來就不會逐像素照到角色（2026-10-30 讀 shader 的 pass 標籤確認）。卡通著色只用一盞前向光，點光與聚光照地圖與一般材質的道具 |

### U12　各種 KKS 場景卡正確載入（2026-10-30，F 組，使用者要求）

批次檢查：`OKStudio.CompareKStudio <資料夾> <數量> 60 exit`（`-OKStudioCompareOutput=<資料夾>`）。每張場景左邊是原作存的縮圖、右邊是 OK Studio 的畫面，另外寫 `report.txt`：每個場景一行，列出物件數量和每個沒顯示的物件及原因。第一輪抽樣 Official 40、vmd 10、根目錄 5 張，55 張全部載入並截圖（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck1030`）。

| 問題 | 處理 |
|---|---|
| 比對指令在場景編輯器模式下直接退出 | `CompareKStudio` 會先 `Start` 新工作室，關掉原本的工作室；工作室一關，整個程式就退出。改成和 `PerfKStudio` 一樣，先沿用已在跑的工作室 |
| 沒網格的輔助道具被標成「未顯示」 | 例如「回転／投げ／振動／ピストン（obj無し）」和 3D 音效（換気扇、風），遊戲裡也不畫。改成當空物件，只用來放子物件，不算錯誤 |
| mod 道具變成空資料夾（vmd `87018458_p3` 有 30 個，舞台布景整個不見） | 新增 `ok-extract <遊戲> --oklib studio-mods <基礎庫> [場景資料夾 [執行緒]]`：<br>• 讀遊戲 `mods/` 每個 zipmod 的 `abdata/studio/info/**/ItemList_*.csv`，用 `converted.tsv` 對到 bundle 的模型 id，寫進 `base_v1/studio_mod_items.json`（第三方內容，只留本機，已加進 `.gitignore`）。<br>• 給了場景資料夾時，先把場景用到、但基礎庫還沒有的 mod bundle 轉進基礎庫（`convert_with`，不重寫 `studio_items.json`）。<br>• 場景解析讀 sideloader 的 `itemInfo`（`ModID`、`Slot`、`SceneDicKey`），匯出時在道具上標 `mod_guid`、`mod_slot`。<br>• 匯入器用 GUID＋Slot 找道具，換成 mod 自己的群組、分類和編號。<br>• 目錄改成用索引查找（mod 道具有兩萬多筆） |
| 場景角色轉不成 OK 卡（vmd `1545919667549` 的角色 560、3） | 舊場景裡的角色沒用 GUID 指名 zipmod，轉卡的閉包因此缺東西。e-okcard 修好（E `duo2` 的 `6dd189247`：從缺口找出沒指名的 zipmod 重轉），F 已 cherry-pick（`779526b70`）。轉卡失敗時，匯入器會把原作卡留在 `char_<key>.kks.png` 方便重現 |
| 子物件繼承了父道具的縮放（vmd 舞台場景鏡頭前擋著 25 m 高的燈籠） | 依反編譯的 `GuideObject.cs`（第 581～586 行）：每幀把 `localScale` 設成 `localScale / lossyScale * 自己的縮放`。所以物件的世界縮放永遠是自己設定的縮放；父物件的縮放只會放大子物件的位置，不會放大子物件本身。`WorldTransform` 改成從根往下算，每層把世界縮放換成物件自己的縮放；`Reparent` 保留世界縮放。往上找父物件的上限從 256 層提高到 `MaxDepth` 4096 層（場景最深約 1024 層） |

結果：mod 道具補轉後，vmd 57 張全部載入、沒有任何未顯示的物件（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck1030b`）；舞台場景修正縮放後，鏡頭、桁架、燈具都和原作一致（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck1030d`）。全部 7,694 張場景用到的 mod 道具共 146 種，47 個 bundle 補轉進基礎庫，全部都有模型了。

尚未一致、尚未處理：
- ~~螢幕道具在原作即時顯示另一台相機拍到的畫面（render texture），OK Studio 顯示灰色或靜態圖。~~ 已在 U13 完成。
- vmd 資料夾的場景靠 MMD 的 VMD 外掛驅動角色姿勢與位置，原作縮圖拍的是外掛播放中的瞬間；OK Studio 沒有這個外掛，角色停在 T 字姿勢。
- 部分地圖的光照與色調不同，例如 `ill_ss_sample_01` 的大浴場、`1546790632203` 的地板。
- cs0004179 火鍋裡約 1 cm 的豆腐沒露出來；豆腐的位置和大小都正確，推測是周圍食材有毫米級的高低差，把它蓋住了。

### U13　螢幕道具的即時畫面（2026-10-30，F 組，使用者選定）

場景裡的「相機道具＋螢幕道具」（例：mod HarvexARC Studio Effects 的 CH1～CH3-Camera 與 CH1～CH3-Screen）在原作是兩個獨立 prefab，靠同一張 RenderTexture 資產相連：相機的 `m_TargetTexture` 指向它，螢幕材質的 `_MainTex` 取樣它。地圖內「相機與螢幕同在一個 prefab」的情形（live stage）原本已支援，這次補的是跨道具的情形。

| 項目 | 做法 |
|---|---|
| 轉檔記錄 | `prefab_render_textures` 每台相機多記 `target_key`（RenderTexture 名稱＋path id 雜湊成 24 位元），另記 `shared`：取樣「本 prefab 沒有相機畫它」的 RenderTexture 的材質。基礎庫紀錄是 bincode，加欄位會讓舊紀錄讀不出來，所以新格式改存在 `prefab_render_textures2`；只有舊紀錄的地圖照舊讀（`PrefabRenderTexturesV1`） |
| mod 道具補記錄 | mod 的 Studio bundle 當初以角色來源轉換，沒有記節點樹與相機。轉檔時 `abdata/studio/` 的 zipmod bundle 補記；已轉過的用 `ok-extract <遊戲> --oklib studio-mod-nodes <基礎庫> <場景資料夾> [執行緒]` 只補場景用到的道具（全部場景：49 個 bundle、145 個 prefab、14 台相機，20 秒） |
| 螢幕 | 零件材質有 `_OKRTShared`（key、寬、高）時，`AKKPreviewActor` 換成不受光的螢幕材質並登記在 `SharedRenderTextureScreens`，預設黑色 |
| 相機道具 | `ok_okmodel_render_cameras` 回傳 prefab 裡的相機（位置、旋轉、FOV、近遠平面、目標尺寸）；`AOKSceneActor::AddRenderCamera` 在道具上建 `USceneCaptureComponent2D`（Unity 垂直 FOV 換成 Unreal 水平 FOV，沿 Unity +Z 看），每個 key 共用一張 render target |
| 配對 | `WireRenderTextures`：每次同步後，螢幕取同 key 第一台相機的畫面；只有被顯示中的螢幕用到的相機才每幀拍；螢幕不出現在自己的相機裡（不受光的螢幕拍自己會回授成白色） |
| 隱藏的相機道具 | Studio 隱藏道具只關 renderer 與粒子（`OCIItem.visible`），GameObject 還在，相機照樣畫。所以相機道具不論顯示與否都拍 |
| 後製 | Studio 的影像效果只在主相機上：相機道具的 capture 用 Studio 的「原樣輸出」設定（無 film curve、固定曝光、無 bloom／濾鏡／霧／暗角） |
| 除錯 | `OK_RT_DUMP=1`：相機道具出現 5 秒後，把畫面存到 `Saved/OKStudio/studio_rt_<key>.png`，並在 log 印出 Unity 座標的位置與方向 |

驗收：vmd 資料夾用到 HarvexARC 相機的 13 張場景全部載入（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck_rt2`）。`80639555_p1` 大螢幕與兩側小螢幕顯示即時畫面，構圖與原作一致；`1585406034802` 的相機道具是隱藏的，修正後螢幕顯示角色特寫（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\rt_debug_1585_nolight2.png`，暫時關掉前方的 tv_light 光暈資料夾後拍）。

仍不一致：
- `1585406034802` 螢幕前的「色影(四角2)」（`Shader Forge/main_item_studio_add`，透明度 0.06～0.38）疊起來比原作亮很多，把螢幕整片蓋白。
- 原作螢幕材質是受光的 Toony Colors Pro（`_Color` 約 0.89），暗場景裡比較暗；OK Studio 的螢幕不受光，略亮。
- `80639555_p1` 中間的小螢幕原作是暗色畫面，OK Studio 是白色，還沒查。
- ~~`2021_1022_2145_32_381` 整張黑畫面~~ 已修（2026-10-30）：場景相機在放大 5 倍的廚房（Petardo 的 CM3D2/Lighted 地圖 mod）牆外，Unity 只畫正面、看得穿；我們多加了卡通描邊外殼而整片黑。CM3D2 系列不再加描邊；CM3D2／Unlit 著色器改畫成不受光、陰影色白。修正後構圖與原作縮圖一致（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\kitchen_fixed.png`），廚房牆面比原作亮，歸入地圖色調。
- 同一張的地圖色調（2026-10-30）：
  - CM3D2 移植的地圖著色器以上下顛倒的 V 取樣（牆取到米白磁磚、櫥櫃門取到家電），CM3D2 部件改用 1-v。
  - 場景的 131 號濾鏡是 `[mzam]Filter.zipmod` 的 `mzam_Lut_004`：`studio-mods` 現在把 mod 的 `Filter_*.csv` 寫進 `studio_mod_items.json` 的 `filters`，並把 LUT 記錄進基礎庫（本機 84 個）；目錄讀 mod 濾鏡時遊戲本身的編號優先。
  - 場景 ramp 850 是 MoreShadowTypes 的 mod ramp，原本用 `kk_850` 找不到，改成依編號找 `<mod>_850`。
  - vmd 全部 57 張整批比對都能載入（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck_vmd3`）。`90697134_p0` 原本被大樓擋住：道具非等比縮放與 prefab 根轉動的組合用 FTransform 相乘算錯，改成矩陣相乘後構圖一致（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\r90697_fixed.png`）；仍缺光束、中央球體的發光線框、霧與景深。`83626612_p1` 背景白（原作星空藍）、`86003286_p4` 缺暗色煙霧背景，待查。
  - 結果見 `F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\kitchen_cap4.png`：愛心 250,117,132 對原作 251,112,131。牆面仍比原作亮約 30（原作的 CM3D2/Lighted 受光，我們畫成不受光），留待地圖色調一併處理。

### U14　以 KKS 原生畫面為準修地圖光照（2026-10-30，F 組）

原作縮圖常是 KK 舊版拍的，不能直接當標準。改用 `Tools/GamePoseProbe/run_scene_visual_audit.lua --tag <名稱> --scenes <場景>`：在 KKS 的 CharaStudio 開同一張場景，存下原生畫面（1280×720）、材質、燈光（含 culling mask）與每個 renderer 的圖層。例如 `F:\OpenKoikatsu\Saved\Tests\kks_maptone_1030\Scene1.png`。

| 問題 | 原因與處理 |
|---|---|
| 操場 `1546790632203` 地面棕色 | 黃沙是 Studio 道具「砂地1」（`o_koi_stu_yuka_02_01`），在 Unity 圖層 11。地圖太陽的 culling mask 是 2048，也照得到這一層。我們的道具光照模擬只取角色燈，所以第 11 層的道具主光源是黑的。改成和 Unity forward 選主平行光相同的規則：照得到道具圖層的平行光中，取最亮的一盞（角色燈或地圖太陽），寫進 `_LightColor0`／`_WorldSpaceLightPos0`。修正後沙地顏色與原生一致 |
| 大浴場 `ill_ss_sample_01` 偏暗偏藍 | 地圖自己的即時燈光（`Map/light/morning` 的點光源、聚光燈，以及只照水面的平行光）沒有建。新增 `prefab_light_modes` 記錄（`m_Lightmapping`、culling mask、陰影、GameObject 是否啟用；由 `studio-nodes` 記錄）與 `ok_okmodel_map_lights`。載入地圖時，不屬於烘焙燈、也不是地圖太陽的燈都建成 Unreal 燈光，掛在 map 的 lighting channel 上，並依時段顯示。衰減以 Unreal 非平方反比衰減近似 Unity 的衰減貼圖 |
| vmd 場景角色姿勢、`80639555_p1` 中間小螢幕 | 場景以 KKVMDPlay 外掛播放 VMD，存檔只記作者電腦上的 VMD 路徑，本機沒有這些檔案。原作的小螢幕拍到的是跳舞中角色的近景。現在匯入報告會列出每個角色用的 VMD 檔名，並說明找不到檔案、不支援播放 |

| 大浴場的貓偏白 | Standard 著色器的反照率是 `_MainTex × _Color`（線性），我們沒乘 `_Color`。Standard 系材質現在把 `_Color` 轉成線性後乘進反照率（卡通道具路徑不受影響）。修正後貓是灰色與豹紋，和原生一致 |
| 沒有反射資料的地圖反射到 UE 天空 | 原生 tsv 的 `reflection_default` 在沒有烘焙預設反射的地圖是 `UnityBlackCube`，probe 沒有貼圖時也一樣。我們之前退回材質預設的天空 cube。改成這種情況一律綁黑色 cube（`OKStudioBlackReflection`）；工作室天空開著時不變 |

| 大浴場地板偏藍、木桶偏綠 | 不是反射（關掉 UE 反射畫面不變）。地板沒有 lightmap，環境光來自 `unity_SHA*`；我們給的是地圖烘焙的 `m_AmbientProbe`，地圖 62 存的是 0。KKS 地圖沒有 LightProbes 物件（KK 地圖的是空的）。地圖 62 的 ambient mode 是 Trilight：Unity 執行時用天空、地平線、地面三色算環境 SH，烘焙值是過時的。拿原生 `renderer_sh` 對三色擬合，三個色版都精確到 1e-5：C0 = (天空+地面)/6 + 2·地平線/3，C1 = √(2/27)·(天空−地面)，C6 = 5/96·(地平線−(天空+地面)/2)，C8 = 3·C6（顏色先轉線性，再乘 ambient intensity）。Flat 是三色相同的特例。`studio-environments` 現在多記 `ambient_sky`／`ambient_equator`／`ambient_ground`，`OKStudioMapAmbient` 在 Trilight／Flat 時改用三色算。72 張地圖中有 15 張 Trilight、27 張 Flat 都受影響 |
| 操場舞台上方一大片模糊 | 不是景深：關掉 DOF、關掉半透明都一樣。這張場景把地圖移了 (−82.5, 3.43, −4.75)（SceneInfo.caMap，Studio 載入時 `MapCtrl.Reflect` 會套用；KK 縮圖舞台後方就是外牆的磚格）。外牆 `mo_koi_map34_sotokabe01_00` 因此緊貼舞台後方，但貼圖被拉滿整面牆。原因是 mesh 解碼挑主 UV 的啟發式：選「數值落在 ±8 內比例最高」的 channel。地圖的主 UV（TexCoord0）重複到 0–30，反而輸給全在 0–1 的 lightmap UV（TexCoord1）。原作地圖 205 個 mesh 中有 27 個、工作室道具中有網子、樓梯、樹等 6 個中招，角色 mesh 全部用 TexCoord0、不受影響。規則：TexCoord1 是 Unity 的 lightmap UV，只要 TexCoord0 是有效 UV（有限、不超過 4096、不是全 0），主 UV 就用 TexCoord0。基礎庫裡已記錄的 mesh 要重錄：`OKLIB_REFRESH=meshes_for_maindata ok-extract <遊戲> --oklib studio-nodes <基礎庫>`（studio-nodes 現在也會重錄已記錄的 `meshes_for_maindata`）|

| `87018458_p3` 舞台地板灰色、沒有倒影 | 地板上鋪的是 mod 鏡子道具（`yamadamod.studioItem_mirror`「鏡 四角 アルファ 64」，著色器 `FX/MirrorReflection_Transparent`），我們沒有鏡子。原作 PS（反組譯 bundle 裡的 DXBC）：`rgb = tex2Dproj(_ReflectionTex, 螢幕座標) × _MainTex × _Color`、`alpha = _MainTex.a × _Color.a`；腳本 `MirrorReflection` 的設定是 1024 解析度、clip 偏移 0、只照圖層 10／11。做法：`AKKPreviewActor` 遇到 `FX/MirrorReflection*` 的零件換成鏡子材質（參數沿用 Unity 名稱，Material Editor 改 `_Color` 仍有效），記下網格平面；`AOKSceneActor::UpdateMirrors` 每幀用主相機對平面鏡射的位置拍一張（右手系相機，所以畫面左右相反，材質取 `1-u`），近平面用 Unity `CalculateObliqueMatrix` 同樣的斜截面（換成 Unreal 反向 Z 投影：`clip.z = w − k·d`），沒有影像後製 |

修正後舞台地板變成暗色、有建築／鼓組／齒輪的倒影，和原作一致（`F:\OpenKoikatsu\Saved\OKStudio\mirror2\87018458_p3.png`）。全部 7,694 張場景中有 17 張用到這組鏡子道具。

兩側布幕：KK 縮圖是紅色，但 KKS 原生畫面（`F:\OpenKoikatsu\Saved\Tests\kks_stage87018_1030\Scene1.png`）的側幕就是藍灰色（Sims4 `LargeFancyCurtains` 的 IBL_Shader 在 KKS 下的樣子），我們和原生一致，不改。

| `87688028_p5` 背景的電路板圖片變成白色 | 圖片是 Material Editor 換上的 `_MainTex`（JPEG，存在場景的 `TextureDictionary`）。Material Editor 把這個字典和其他清單一樣存成 msgpack bytes，我們只當成 map 讀，所以場景裡每一張換過的貼圖都被丟掉（`material_edits` 是空的）。改成先把 bytes 解開；舊存檔的純 map 照樣讀。另外，沒有原生 Forge 程式的通用零件材質把主貼圖參數叫 `KKAppearanceMain`，Material Editor 的 `_MainTex` 找不到參數就沒套上；現在 `_MainTex` 找不到時改套 `KKAppearanceMain`。修正後背景與原作一致（`F:\OpenKoikatsu\Saved\OKStudio\metex1\87688028_p5.png`） |

尚未一致：
- 鏡子的倒影沒有依 `m_ReflectLayers` 篩圖層（目前拍到全部物件）。2026-10-31 查：17 張用鏡子的場景都是遊戲本身的鏡子道具（`p_koi_stu_marukage00_00`、`mo_koi_mirror00`，在 `abdata/studio/00.unity3d`），這個 bundle 裡沒有任何帶反射圖層欄位的 MonoBehaviour（逐一掃過，鏡子物件上只有 ItemComponent），所以沒有可讀的圖層設定，倒影拍全部物件就是預設行為；之後若遇到自帶 MirrorReflection 腳本的 mod 鏡子再讀它的 `m_ReflectLayers`。
- ~~通用零件材質的 `_MainTex_ST` 是建材質時寫死的常數，Material Editor 改貼圖縮放／位移套不上（vmd 有一張場景的 `m_koi_stu_kawa00_00`）。~~ 2026-10-31：通用零件材質（`MakePartMaterial`）取主貼圖的四處座標改成讀向量參數 `_MainTex_ST`（預設值是材質自己的值，`MakeUnityMaskUVParameter`），Material Editor 的 `MainTex` 縮放／位移（`texture_st`，套成 `_MainTex_ST` 覆寫）就套得上。例：`83283571_p1` 的 `m_koi_stu_kawa00_00` 縮放 2.5 與 2.0——這個材質其實是 `Xffect/heat_distortion_t2`（畫面相乘的水面，`OKModulate` 材質），它的參數原本叫 `MainST`，也改名成 `_MainTex_ST`；修正後 log 不再列為 unapplied（`F:\OpenKoikatsu\Saved\OKStudio\mainst3\run.log`，這個視角下畫面幾乎沒變）。`OK material overrides=… unapplied=…` 這行現在另外註明原因：`(no matching part)` 或 `(parameter not in <母材質>)`。同一張場景的 `water_square` `_RimColor` 落在 `WorldGridMaterial`（材質沒建成，用了預設材質），待查。
  - 2026-10-31 `water_square`：mod `DA.xv2stuff` 的水面（Water Plane 1）用第三方著色器 `StylizedWater/Desktop`，沒有主貼圖、也沒有對應的材質圖，所以零件沒有材質。從 zipmod 的 bundle 取出 19 個 DXBC 程式與 `m_ParsedForm` 各子程式的常數名稱／位移，照 ForwardBase DIRECTIONAL 的 PS（blob 4）寫成 `OKStylizedWaterMaterial`：兩次捲動的 `_Normals`（世界或 UV 鋪排）、相機光的 GGX、依水深加深的 `_WaterColor`、交界的 rim 與 `_Shadermap` 泡沫、`_FresnelColor`、表面高光，最後 lerp(依法線折射的 GrabPass, 光照色, alpha)。GrabPass 對到 SceneColor 節點（OffsetFraction 帶折射位移），`_CameraDepthTexture` 對到 SceneDepth／PixelDepth。`okmodel_view` 讓這個著色器也載入 `_Normals`、`_Shadermap`（和 Standard 系列同一段）。結果地面從灰色預設材質變成和原作一樣的青色水面（`F:\OpenKoikatsu\Saved\OKStudio\water1\83283571_p1.png`），Material Editor 的 `RimColor`／`RimSize` 也套上了。沒做：`_Reflection` 立方體貼圖（沒有立方體貼圖的轉出，反射項為 0）；環境光用固定的 `_OKAmbient` 0.2。
- `83572034_p1`：舞台後方缺月亮背景、兩側藍色發光道具顯示成灰白，舞台中間的紅色板子原作沒有。原因是 Material Editor 換著色器（`MaterialShaderList`）：全部 7,694 張場景的統計是 `Shader Forge/main_item_emission` 362 筆／14 張場景、`main_item_studio` 56／2、`main_item_studio_alpha` 31／3、`Unlit/Glitch3DProjection` 15／2（藍色發光手把）、`Goo` 8／1、`main_item` 7／4、`IBL_Shader` 3／1、`HarvexARC-XRay` 2／2（中間的紅板，原作是透視、看得到後面的月亮）、`main_opaque` 2／1、`HarvexARC-Gem` 1／1。`okmodel_view::ItemMaterialEdits::shader_supported` 原本不收這些著色器，一律保留原著色器。處理（KKS 原生畫面 `F:\OpenKoikatsu\Saved\Tests\kks_p1emission_1030\Scene1.png` 為準）：
  - `main_item_emission`：Unreal 共用母材質已有 ForgeEmission 程式。第一次加進去時牆變白／粉——不是 ramp 的問題：控制通道新增 `parts` 的 `params`／`has_param`（列出零件材質的參數值）一看，換成 ForgeEmission 的零件 `_Color` 停在 1、`_ShadowColor` 停在原材質的粉色。Studio 的 ItemComponent 不管換成什麼著色器都照樣寫道具顏色（`_Color`..`_Color3`、`_ShadowColor`），我們只對 `main_item_studio` 的零件套道具顏色（`SessionPart::item_draw`）。改成：Material Editor 把 `main_item_studio` 換成別的著色器時記 `_OKStudioItemColors`，零件仍算道具顏色零件。修正後牆面和地板是黑的，與原生一致。
  - `HarvexARC-XRay`：反組譯 bundle 的 PS：`c = Inside·s + 0.5·max(1 − n_z^RimSize, 0)·(Rim − Inside·s) + Emission`，`alpha = s`（`s = _InsideSize/4`），兩個 pass（SrcAlpha 混合、One One 疊加）、不寫深度、不剔面，合起來是 `dst·(1−s) + c·(1+s)`，用一個 AlphaComposite 材質（`OKXRayMaterial`）畫。
  - `Unlit/Glitch3DProjection`：反組譯 PS（區塊雜訊、Fresnel、世界高度掃描線、閃爍貼圖調整 alpha），`OKGlitchMaterial`；頂點程式偶發的故障位移沒有做（靜止狀態）。程式的色調是 `_Color4`，不是 `_Color`（Studio 會寫 `_Color`）。
  - Material Editor 換著色器時會套 zipmod manifest 裡 `<Shader><Property DefaultValue>` 的預設值：Glitch 的 `Color4` = (0.37, 0.84, 0.93, 0.2)、XRay 的 `InsideColor` = (0,0,0,1)、`EmissionColor` = (0,0,0,0)；材質圖的預設值照這些設定。
  修正後中間的 XRay 板子透出後面的夜空，兩側的藍色全像板、手把、主機都是青色故障效果，與原作一致（`F:\OpenKoikatsu\Saved\OKStudio\mesh6\83572034_p1.png`）。仍缺月亮：月亮與夜空罩是 `main_item_studio_alpha` 的半透明道具，原生這個著色器寫深度（ZWrite On），夜空罩後畫也蓋不掉較近的月亮；Unreal 的半透明不寫深度，夜空罩就蓋掉了月亮。
  - 2026-10-31 修正（通用）：著色器的寫深度從 bundle 讀出——`unity::shader_pass_state` 多記主 pass 的 `zWrite`（固定值或綁定的材質屬性），材質記成 `_OKShaderZWrite`，`shader_states.json` 也收（`ok-extract <遊戲> --oklib shader-states <基礎庫>` 重產，舊檔沒有這欄就當不知道；本機重產 679 種著色器：172 關、300 開、207 看材質屬性）。混合繪製又寫深度的道具零件記進 `AKKPreviewActor::ZWriteBlendedParts`；`AOKSceneActor::PlaceBackground` 每幀看視點是否在零件的包圍盒內：在裡面的（夜空罩這類殼）排序優先度改成 -5000 減半徑，在天空盒之後、其他半透明之前畫，大的殼先畫；離開就回到原本的優先度。理由：Unity 依包圍盒中心由遠到近畫，包住視點的殼中心很近、最後才畫，但寫深度讓它留在被包住的東西後面；不改材質，cook 後的共用母材質也適用。限制：沒包住視點的寫深度半透明零件之間仍照 Unreal 的距離排序（不寫深度的差異只在兩者重疊又排序相反時）。結果月亮出現（`F:\OpenKoikatsu\Saved\OKStudio\moon1\83572034_p1.png`）；原作月亮只有月牙亮、其餘暗，我們整面亮，屬另一個著色差異，待查。vmd 57/57 載入（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck_vmd13`），和前一輪比明顯變化的：`86003286_p4` 600 m 的夜空罩（`stgd2ns051_sky`）先畫，背景從粉紅變成和原作一樣的深藍（單獨重跑結果相同，`F:\OpenKoikatsu\Saved\OKStudio\chess1`）；`1537365251587` 在整批裡海面變亮，單獨跑與換成同樣前一張場景重跑都和上一輪一致（`beach1`、`pair1`），屬一次性的拍攝時機差異；`1565534473667` 只差眨眼。
  - 2026-10-31 `shader_states.json` 自動重產：檔案多記 `version`（目前 2：含寫深度）與 `inventory`（遊戲 bundle 與 zipmod 的數量、總大小、最新修改時間）。工作室場景 Actor 開始時（`AOKSceneActor::BeginPlay`）以設定的遊戲目錄（`KKGameRoot` 的 `Root`）呼叫 `ok_studio_shader_states_ensure`：檔案不存在、版本舊或 inventory 不符（換了遊戲或裝了新 mod）時，在背景執行緒重讀全部 shader 寫回（寫暫存檔再改名；`shader_states.json.lock` 防兩個程序同時跑，超過兩小時的鎖視為失效）；讀取端依檔案修改時間自動重載，執行中的遊戲在重產完成後開的道具就用新資料。不用再手動跑 `shader-states`。本機實測：舊檔（無版本）在工作室啟動後約 4 分鐘換成 version 2。限制：沒有遊戲目錄的環境無法重產；OKStudio 模組裡的 ok_extract 沒註冊 log 回呼，重產訊息不會出現在遊戲 log。
  - 月亮的月牙差異（未修）：月亮 `YK_Yue` 是 8 個三角形的看板，貼圖 alpha 平均只有 32/255，只有右緣接近不透明。Unity 先畫月亮（中心較遠）並在整個看板寫入深度，後畫的夜空罩在月亮範圍內深度測試失敗，所以月亮半透明的部分疊在黑色背景上，只看到亮的月牙；我們讓殼先畫，月亮疊在深藍夜空上，整個圓盤看得到。要完全一致，得讓後畫的寫深度半透明零件逐像素避開較早畫、較近的寫深度零件（custom depth＋依 Unity 繪製順序的排名），這要改共用母材質（`M_ForgeStudioAlpha` 等）並重存母材質、各線重新 cook，留待之後處理。`model-view` 加上診斷用的 `OK_MODEL_VIEW_PNG=<資料夾>`，可把各網格的主貼圖寫出。vmd 57/57 通過（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck_vmd12`）；另外兩張場景用到：`91204049_p0` 一個 Glitch 方塊、`86703995_p3` 的 penthouse 一個 XRay 材質（KKS 原生也是 XRay，`F:\OpenKoikatsu\Saved\Tests\kks_xray_86703995\Scene1.png`）。`86703995_p3` 換成 XRay 後露出後方一些白色物件，這張場景本來就和原生差很多（藍色天空塊、地板顏色），待查。
  - 2026-10-31 逐像素修正（通用，取代上面「包住視點的殼先畫」）：
    - 材質：`OKAddUnityTranslucentDepthTest`（`KKRuntimePose`，`KKRuntimeVertexAmbient.cpp`）把半透明材質的 opacity 包一層測試。零件在 custom primitive data 0 帶自己的 Unity 繪製名次（1..255；0 不測）；某像素的 custom depth 比自己近、而且 custom stencil（畫那個深度的零件名次）比自己早，這個像素就丟掉。材質允許半透明寫 custom depth，`OpacityMaskClipValue` 設 0：Unity 的 ZWrite 對程式沒丟掉的每個片段都寫深度，不論 alpha。共用母材質（`PrepareRuntimeSharedMaterial.cpp`，母材質根目錄改成 `StudioDisplay29`，`DefaultGame.ini` 加進 cook 清單）與自建的半透明圖（`MakePartMaterial`、頂點色、ForgeAlpha／ForgeOpaque、鏡面、XRay、Glitch、水面、粒子、舞台特效、modulate）都套用。
    - 場景：`AKKPreviewActor::BlendedParts` 記角色以外的混合零件（半透明、加算、modulate），附 Unity render queue（`ok_part_material_value` 的 `_OKRenderQueue`；-1 用著色器的，天空盒是 1000）、是否寫深度。工作室模型另記 `_OKRendererGroup`／`_OKSubmesh`（`okmodel_view`，卡片路徑不加）。`AOKSceneActor::RankBlendedParts` 每幀依 Unity 順序排名：先比 queue，再比距離（2500 以下由近到遠，以上由遠到近）。同一個 renderer 的 submesh 用 renderer 整體包圍盒中心的距離，同距離時依 submesh 順序。名次寫進 custom primitive data；寫深度的零件另開 custom depth，stencil 寫名次（`r.CustomDepth 3`）。UE 實際的繪製順序也跟著調：同一 renderer 的 submesh 用 `TranslucencySortDistanceOffset` 拉到 renderer 的距離；各 queue 依序每級加減 100 個 sort priority，3000 不變，保留零件原本的堆疊優先度。
    - 月亮（`83572034_p1`，`F:\OpenKoikatsu\Saved\OKStudio\moon10\83572034_p1.png`）：Night Field 的地面、夜空殼、月亮是同一個 renderer 的 submesh 0／1／2。Unity 先畫殼、再畫月亮，月亮疊在殼上。上面「Unity 先畫月亮」的推測是錯的：先畫月亮的話，殼在月盤處被深度擋掉，會透出 447 m 外的白色 Skybox1，實測整個月盤變白（`moon5`）。目前月盤的深藍比原作亮：月盤 alpha 約 0.18，混合模式和原作一樣是 SrcAlpha／OneMinusSrcAlpha（從 bundle 讀出），差異的來源還沒找到。
    - 中途退步並已修正：拿掉「殼先畫」後，`86003286_p4` 的背景變成天空殼的粉紅色。原因是兩個放大的圓影（`o_shadow`）queue 4999，Unity 在殼之後才畫，UE 原本只看距離。改成依 queue 調整排序後恢復深藍（`F:\OpenKoikatsu\Saved\OKStudio\chess4\86003286_p4.png`）。
    - 只在主視角測：名次是依主視角算的，鏡面、螢幕這類 SceneCapture 從別處看，套用會錯丟像素（`1547385457380` 萬花筒兩側原作有的藍色光條不見了）。custom primitive data 1–3 另存排名用的相機位置，材質只在畫面相機和它的距離小於 1 cm 時測。modulate、加算混合不讀 opacity，UE 會把掛在 opacity 上的測試節點整個省略（`1547730231799` 的 `Xffect/heat_distortion` 地面在沙灘上蓋了一層灰），所以 emissive 也乘一個做同樣測試、回傳 1 的節點。`OK_UNITY_DEPTH_TEST=0` 可關掉排名（診斷用）。最後一輪 vmd 57/57（`F:\OpenKoikatsu\Saved\OKStudio\scenecheck_vmd17`）：和 vmd13 比，`86003286_p4`、`1547385457380`、`1585406034802` 一致；`1537365251587` 出現原作有的海浪線與近岸淺水層；`1547730231799` 的沙色更接近原作；`83283571_p1` 的水面是原作的青綠色。
    - 診斷：控制通道 `parts` 加 `owner`（只列或只隱藏某個預覽 actor 的零件）。log 的 `OK blended part=` 列出每個混合零件的 queue、寫深度、renderer、submesh；`OK sky dome` 多印 queue。
  - 2026-10-31 立方體貼圖轉出（通用）：`ParsedBundle::cube_slot_atlases` 把材質裡指向 Cubemap 的欄位（依名稱比對 bundle 與相依檔的 Cubemap）轉成 cube atlas（`cubemap_atlas`：六面並排，mip 往下），放進 `shader_extra_textures[<欄位>]`。`attach_material_texs` 與 `okmodel_view` 都會跑；原本只有 Skybox/Cubemap 的 `_Tex` 有轉。C++ 端的 atlas 取樣抽成 `OKCubeAtlasSample`（D3D 立方體面規則，Unity 空間方向），天空盒與水面共用。`StylizedWater/Desktop` 照 DXBC 加上反射項：`reflect(-V,n)` 取 `_Reflection`，乘 `_Glossiness`、`saturate(1-roughness)`、`(1-n·v)^5`，以 sRGB 載入。共用母材質（`SharedShaders/*Bindings.inl`）的 cube 貼圖只有 `unity_SpecCube0／1`，沒有材質欄位的 Cubemap；它們由 `OKSceneActor` 綁上地圖反射探針轉出的真正 `UTextureCube`（`OKStudioMapReflection`），不需要改走 atlas。材質欄位的 Cubemap 只出現在自建圖的家族（天空盒、水面），已走 atlas。
  - 2026-10-31 實測水面（`83283571_p1`，[DA]xv2stuff 的 Water Plane 1）：`_Reflection` 原本還是黑色 32×32，三個原因都修了。(1) 這個模型在 atlas 功能之前就轉好，`meshes_for_maindata` 記錄裡的材質沒有 `_Reflection` 欄位（當時外部 bundle 的 Cubemap 取不到名稱）；`studio-mod-nodes` 改成和 `studio-nodes` 一樣，可用 `OKLIB_REFRESH=meshes_for_maindata` 重錄已有的網格記錄。(2) 函式庫模型 replay 時 `cube_slot_atlases` 會讀 bundle 內部而記一筆「未 memo」缺口；改成 cube atlas 是獨立的 memo 查詢 `cube_atlas_named`（只記真的 Cubemap），replay 時有記錄才用；`studio-nodes`／`studio-mod-nodes` 會補錄。(3) `SessionPart::from_mesh` 對一般 shader 只留白名單內的貼圖，`StylizedWater/Desktop` 不在名單上，`_Normals`／`_Shadermap`／`_Reflection` 全被丟掉（水面法線其實也一直沒接上）；加了水面的分支。結果：`_Reflection` 是 3072×1024 的 atlas，`_Normals` 256×256、`_Shadermap` 1024×1024，水面出現波紋與反射（`F:\OpenKoikatsu\Saved\OKStudio\water1031\83283571_p1_after.png`，之前 `F:\OpenKoikatsu\Saved\OKStudio\scenecheck_vmd17\83283571_p1.png`）。這張場景整體過曝（火焰、泛光）是既有問題，另外查。診斷：`ok-extract X:/NoGame --oklib model-view <lib> <id> session:<prefab>` 列出 session 各部件的 shader 貼圖。本機只對這張場景的 mod 道具跑了 `OKLIB_REFRESH=meshes_for_maindata ok-extract D:/KoikatuSunshine --oklib studio-mod-nodes <base_v1> F:/OpenKoikatsu/Saved/OKStudio/mainst_in 4`（第三方 mod 模型不進版控）；原版道具與地圖的 cube 欄位要在整合時跑 `studio-nodes` 補錄進共用基礎庫。

  - 2026-10-31 過曝與月盤偏亮：用 `Tools/GamePoseProbe/run_scene_visual_audit.lua --tag kks_bright_1031` 拍了原生畫面（`F:\OpenKoikatsu\Saved\Tests\kks_bright_1031\Scene1.png`、`Scene2.png`），兩者**不同源**，也都不是泛光或曝光：
    - `83283571_p1` 的白天空：原生天空盒是 mod 的 `Funly/Sky Studio/Skybox/3D Standard`（`m_skybox_simple_daytime`，粉紅夕陽），OK Studio 沒有這個 shader，畫成白色；關掉泛光（`ShowFlag.Bloom 0`）仍是白的（`F:\OpenKoikatsu\Saved\OKStudio\bright1031\b_nobloom.png`）。另外火焰粒子比原生大很多、鋼架被橘光照亮，要分別查粒子尺寸與點光強度。
    - 月盤：原生是新月，未照亮的半邊全黑；我們整個月盤以暗藍顯示。月亮是 `main_item_studio_alpha`（`YK_Yue`），泛光參數（強度 0.79、門檻 0.903）也不高，比較像是月亮貼圖暗面的 alpha 或該 shader 的明暗項沒對上，下一步是讀 `YK_Yue` 暗面像素的 RGBA 與 OK 的 alpha 混合結果逐像素比。
    - 待做：Funly Sky Studio 天空盒（照 DXBC 自建圖，和 `Skybox/Cubemap` 同一條路）、火焰粒子尺寸、月盤暗面。
    - 2026-10-31 更正：`83283571_p1` 畫面上的天空不是 Funly 天空盒（Funly 3D Standard 早已由 `OKStudioSkyMaterial` 支援，而且畫在 100 m 外最遠處），是 mod 道具 `[nashi]Studio Skybox` 的 Skybox4（`Skybox/Cubemap` 天空球）。逐像素比對：原生約是貼圖原色的 1.5～1.8 倍（含泛光），我們乘了 3.62。這個 mod 自帶的 `Skybox/Cubemap` 是在 gamma 專案編譯的：DXBC 是 `add o0.xyz, r0, r0`（unity_ColorSpaceDouble 編進程式成 2），而 KKS 內建的是線性的 4.5948，所以天空亮了 2.3 倍；景深與泛光再把這片過亮的天空擴散到鋼架上，整張畫面發白。修正：轉換時讀 bundle 自己那份 `Skybox/Cubemap` 的像素程式，有 4.5948 常數就是線性、沒有就是 2，存成材質值 `_OKSkyDouble`（memo 查詢 `skybox_color_space_double`）；UE 的天空球乘它而不是寫死 4.5948，bundle 沒帶自己的 shader 時照舊。結果：`F:\OpenKoikatsu\Saved\OKStudio\bright1031\f_fixed.png`（之前 `a_base.png`，原生 `F:\OpenKoikatsu\Saved\Tests\kks_bright_1031\Scene1.png`），天空回到粉紅夕陽、鋼架不再泛白。本機用 `OKLIB_REFRESH=meshes_for_maindata ok-extract D:/KoikatuSunshine --oklib studio-mod-nodes <base_v1> <這張場景的資料夾> 4` 重錄了這個 mod 模型；其他已轉的 `Skybox/Cubemap` 天空球要用同樣的方式重錄才會帶上新值（沒帶時照舊是 4.5948）。剩下的差異是中央光束一團白（光束與火焰道具的大小、點光強度），另外查。
    - 同一輪：`blend_for_mesh` 對 render queue ≥ 3000 的材質一律判成半透明。這張場景的鋼架原本是 alpha 材質，Material Editor 換成 `main_item_studio` 後 queue 仍是 3000，被當成半透明（log 裡 205 個 `main_item_studio queue=3000` 的混合零件）。`main_item_studio` 本身是 One/Zero、寫深度（`_ALPHATEST_ON` 版本會 clip），queue 只決定順序，改成照 shader 判斷：有 alpha test 是 masked，否則 opaque。`verify_ok_studio.lua` 6/6、`cargo test blend` 通過。
    - 查中央白團與右側鋼架的橘白光時的發現（還沒修）：(1) 逐類隱藏道具，只有隱藏 Skybox4 天空球時白團與橘光才消失，光束、火焰、煙、Gas 都不是來源；放大比對，鋼架本身是暗的，是太陽附近過亮的天空在鋼架間透出、再被泛光擴散。原生同一處的天空偏粉紅，整體像多了一層粉紅色調（可能是 AmplifyColor LUT 或雲層），下一步是比對原生的 LUT 與雲層零件（`mo_koi_sky_kumo*`，Standard queue 3000）。(2) 控制通道 `exec` 下的 `ShowFlag.Bloom 0`／`ShowFlag.DepthOfField 0` 不影響 `capture`（它用自己的 SceneCapture 與場景後處理），之前「關掉泛光仍是白的」那張 `b_nobloom.png` 其實沒有關到；要分離泛光得改 capture 或用 `ui_shot`。(3) 原生的光束道具（ビーム・扇）畫成放射狀光線，我們看不到光線。診斷：`OK_SKY_DEBUG=2`（原色）、`4`（alpha）、`5`（×alpha）；`cargo test cubemap_info_dump -- --ignored`（`OK_CUBE_BUNDLE`）列出 bundle 內 cubemap 的格式、編碼與色彩空間。

### U16～U22　對照 HS2Studio6 的第二批缺口（2026-10-31，F 組，依使用頻率排序）

2026-10-31 對照第 3 節與 `Saved/StudioUIRef/hs2/` 逐項讀程式盤點（30 項：9 項沒有、17 項部分完成），整理成以下項目。排序依擺姿勢與擺場景時每分鐘會碰到幾次。

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U16 角色細調頁 | 表情：眉／眼／嘴顯示目前編號＋上一個／下一個、眼睛開合滑桿；手勢：左右手上一個／下一個／復位與「目前／總數」；視線與頸部：加「正面」「背離」模式、「取鏡頭位置」「恢復看鏡頭」、頸部跟隨強度；遊戲內建姿勢：「n / 總數」上一個／下一個、「復位 T-pose」 | 現在只有下拉與數值框；沒有正面／背離；內建姿勢清單沒有 |
| U17 衣服一鍵 | 狀態窗加「全穿／半脫／全裸」 | 只有逐部位三態 |
| U18 動作瀏覽與控制器 | 全部／女／男／共用頁籤、搜尋（譯名與原名）、項目數；獨立的「動畫控制器」浮窗（速度、動作變化、輔助 1／2、循環、播放／暫停／停止），關掉清單仍留著 | 只有群組下拉與清單；控制只有內嵌滑桿 |
| U19 物件樹操作 | 群組／解散群組（Ctrl+G；吸附改 Ctrl+Shift+G）、帶位移複製、只顯示所選（solo）、鎖定不被視窗點選、拖動時靠邊自動捲動；底部工具列補「設父級」「複製變換」「材質編輯」；道具／動作／地圖／特效目錄的「定位當前」 | 沒有群組、solo、鎖定、自動捲動 |
| U20 FK／IK 部位開關 | 每個部位真的啟用／停用 FK 與 IK（不只篩選清單）、各部位初始化／復位、IK「全部」；新角色預設 IK 開、FK 開胸／身體／雙手／裙子；IK 權重頁；明確的 FK←IK | 部位鈕只篩選清單；沒有權重 |
| U21 時間軸骨骼軌 | 骨骼搜尋＋單骨打 key／刪 key、「清空軌道」 | 只能整個物件打 key |
| U22 其他 | 相機正交與正交大小、遠裁面套用；視窗格線／地面開關與「隱藏全部輔助」；場景統計（物件／角色／道具數）；最近開啟的場景；返回標題；面光源；背景圖瀏覽與「套用」；材質編輯器三欄窗；`?` 說明圖示；截圖窗的前景框選項與「本次目錄」 | 見各項 |

**完成紀錄（2026-10-31，F 組）**
- U16（部分）：
  - 表情的眉／眼／嘴、手勢的左右手：清單下方加「◀ ▶」與「目前／總數」（`SOKStudioPanel::Named`，從 -1「照卡片／照動畫」循環）；手勢加「復位」。
  - 視線與頸部加「正面」「背離」模式（`EOKSceneLook::Front`／`Away`，加在列舉最後，舊檔不受影響）：正面是角色正前方頭高的遠點，背離是鏡頭對頭部的鏡射點；控制通道也接受 `front`／`away`。另加「取鏡頭位置」（注視點設為目前鏡頭位置並改成注視模式）與「恢復看鏡頭」。
  - 還沒做：眼睛開合滑桿（`AKKPreviewActor` 只有 `SetMouthOpen`，眼睛沒有後端）、頸部跟隨強度、遊戲內建姿勢清單。
- U17：狀態窗「全穿／半脫／全裸」一鍵。
- U18（部分）：動作瀏覽改用主題按鈕（目前分頁亮綠），加搜尋（空格＝且、`-詞`＝排除；比對動作名與分組、分類名，結果跨分組並標出所在分組／分類）與「N 個動作」計數。修正：每次重建都把分頁同步回目前播放的動作，播 Studio 動作時按「H 動作」會被拉回；改成只在目前動作改變時同步。還沒做：女／男／共用頁籤（目錄沒有性別資料）、獨立的動畫控制器浮窗。
- 截圖：`F:\OpenKoikatsu\Saved\StudioUIRef\ok\U16b_state.png`、`U16b_look.png`、`U16b_expression.png`、`U16b_hand.png`、`U18b_anim.png`（腳本 `Saved/StudioUIRef/scripts/u16_new2.txt`，`OKStudio.RunScript` 要給絕對路徑）。`OKStudio.UiSelfTest` 46/46。
- U16 其餘：表情頁「睜眼」（`FOKSceneCharacter::EyesOpen`，-1 照角色；接到 `AKKPreviewActor::SetFaceControl` 的手動開合，-1 時還原原本的開合與手動旗標）；頸部「跟隨強度」（`NeckFollow`，目標方向從頭的正前方 slerp 過去）；姿勢頁「◀ n／總數 ▶」逐一套用 `UserData/Studio/pose` 的姿勢檔（KKS 沒有內建姿勢預設，HS2Studio6 的內建清單在 KK 對應的就是 Studio 姿勢檔）與「復位 T-pose」。
- U18 其餘：動作瀏覽加「全部／女／男／共用」頁籤。目錄原本沒有性別：`studio_anims.rs` 的 `motion_sex` 從分組／分類名推（含「男」→ 男；含「女」或「レズ」→ 女；其他 → 共用），寫進目錄的 `sex` 欄位；舊目錄沒有欄位時 C++ 讀取端用同一規則推。動畫控制器浮窗還沒做。
- U19：樹工具列（展開／收起下方）加「群組」（Ctrl+G，所選放進第一個物件旁的新資料夾，世界位置不變；吸附改 Ctrl+Shift+G）、「解散」（Ctrl+Shift+U，子物件移到資料夾的上層後刪掉資料夾）、「錯開複製」（Ctrl+Shift+D，複製後沿畫面右方移 20 cm）、「獨顯」（Shift+H，只顯示所選與其上下層，燈光與目前相機保留；再按一次還原各物件原本的顯示）、「鎖定」（`FOKSceneObject::bLocked`，畫面點選略過它，樹上仍可選）、「設父」「拷變換」「貼變換」。樹拖放時游標靠清單上下緣 20 px 會自動捲動。目錄的「定位當前」還沒做。
- U20：FK／IK 部位按鈕改成真的開關（`FkPartsOff`／`IkPartsOff` 位元，關掉的部位保留數值、改跟動畫；清單只列開著的部位）；FK 頁加「復位」一列逐部位清掉 FK；IK 頁加「全部」；新角色預設 FK 關頭髮與頸部、其他與 IK 全開；調某根骨骼時自動打開它的部位。IK 目標加「權重」（`FOKSceneIkTarget::Weight`，經新的 `ok_session_set_studio_ik_weights` 送到 FullBodyBipedIK 的 effector position／rotation weight 與彎曲 goal weight）；加「FK←IK」（把 IK 擺出的身體與雙手姿勢寫成 FK，清掉 IK）。
- U21：時間軸 FK 改成每根骨骼各自一條軌（`SampleTrackFk`：找 Time 前後最近、含這根骨骼的 key 內插，只出現在部分 key 的骨骼也會平順地動）；FK 頁加「骨骼打 key」「骨骼刪 key」（只動目前骨骼，沒有 key 的時間點新增一個只含這根骨骼的 key，其餘值取該時間點的軌道值），時間軸窗加「清空軌道」。骨骼搜尋沿用 FK 頁的搜尋框。
- U22（部分）：相機物件加「正交」與「正交寬度」（`FOKSceneCamera::bOrtho`／`OrthoWidth`；用這台相機時 `UOKStudioViewCamera` 改成正交投影，遠面在正交時套用，透視時 Unreal 沒有遠裁面，仍只存檔）；相機頁加「視窗格線」（場景地面 10 m、50 cm 一格，線段分段投影，穿到鏡頭後方的部分截掉）與「隱藏全部輔助」（把手、骨點、注視點、光源範圍、選取框、格線都不畫，把手與骨點也點不到）；系統選單加「最近場景」浮窗（上方是場景統計：各類物件數與時間軸 key 數；下方是最近開啟或儲存的 10 個場景，`favorites.json` 的 `recent_scenes`），「離開」改名「返回標題」（行為本來就是回到啟動工作室的模式）。控制通道的 `click` 也能按勾選框。截圖 `F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u22_ortho_grid.png`。還沒做：面光源、背景圖瀏覽與套用、材質編輯器三欄窗、`?` 說明圖示、截圖窗的前景框與本次目錄。
- U22（第二批）：光源加「面光」類型（`EOKSceneLightType::Area`，`URectLightComponent`，寬／高 cm 預設 100；和點光、聚光一樣只照地圖與 Standard 部件，卡通角色與道具仍只吃一盞方向光），添加光源頁加「面光源」四種，視窗裡畫出發光矩形與朝向；畫面設定「背景／前景」分頁加「背景圖一覽」「前景框一覽」縮圖格（基礎庫 `studio/bg`、`studio/frame` 與 `UserData/Studio/bg`、`frame`，點一下立即套用，綠框標出目前的，「無」拿掉）；截圖窗加「含前景框」（關掉時拍攝期間把前景框藏起來）與「本次目錄」（這次啟動的截圖放進 `session_<日期時間>` 子資料夾，「開資料夾」也開那裡）。控制通道 `state` 多回報燈光 `light_type`、`background`、`frame_picture`，`ui` 多回報 `shot_frame`、`shot_directory`。還沒做：材質編輯器三欄窗、`?` 說明圖示。
- U22（第三批）與 U18／U19 剩餘：
  - 材質編輯器浮窗（`app.material`；樹工具列「材質」、道具屬性頁「材質編輯器…」）：左欄是所選道具的模型（renderer），中欄是它的來源材質與 shader，右欄是那個材質的全部顏色、數值與貼圖槽（值取自卡片 bundle 的材質，可篩選屬性名）。改值寫成道具的材質編輯（隨場景儲存，名稱前標 ●），每列「預設」拿掉該筆，底部「此材質全部預設」。浮窗跟著選取與道具載入完成自動更新。
  - `?` 說明：共用的 `HelpIcon`，懸停顯示、點一下固定在「說明」浮窗（再點一次收起）；設定窗每列、屬性列（`RowHelp` 表：燈光種類、範圍、聚光角、作用對象、面光寬高、正交寬度、透明度、描邊寬度、背景圖、前景框、背景色）與截圖窗「含前景框」都有。
  - 動畫控制器浮窗（`app.animcontrol`，動畫頁「動畫控制器」）：所選角色的動作名、速度、時間、◀ 變化／變化 ▶（同分類的上一個／下一個動作）、播放（回到暫停前的速度）、暫停、從頭、停止；即時讀選取，關掉動作清單也留著。輔助 1／2 與循環還沒有對應資料，沒做。
  - 定位當前：動畫頁「定位當前」（`anim.locate`，切到正在播的動作的種類／分組／分類並捲到它）、添加道具頁「定位當前道具」（切到所選道具的大／中分類並捲到它）。
  - 控制通道：`click` 加 `"tag": true`，比對控件的 `FTagMetaData`（縮圖與「無」掛 `bg:none`／`frame:none`／檔名 tag）；`state` 的角色多 `speed`、`anime_no`，`ui` 多 `material_part`、`material_properties`、`material_name`、`help`。
  - 驗證：`check_ok_studio_buttons.lua` 86/86（新增縮圖點選套用背景與前景框、兩個「無」、設定 `?` 固定與收起、樹「材質」開材質編輯器並列出 m_koi_stu_desk00_01 的 46 個屬性、此材質全部預設、定位當前道具、控制器播放／暫停／播放、動作定位當前）；UiSelfTest 46/46；`verify_ok_studio.lua` 6/6。截圖 `F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u22_material_editor.png`。
  - 定位當前讀回：`ui.anim_browse`（種類／分組／分類）、`ui.anim_selected`（清單選中的動作名）、`ui.item_browse`（大／中分類）、`ui.item_located`（捲到的道具）。實測：先切到別的分組或「H 動作」，按定位當前後回到正在播的 ポーズ7（0/7/20）、書桌（2/12/681）。按鈕檢查 89/89。
- 2026-10-31 畫面差異（先用診斷確認是誰畫的）：
  - `83283571_p1` 中央白團：逐項隱藏與關閉後處理確認是 SunShafts（`scene` 操作 `{"post":{"bSunShafts":false}}` 後白團和右側鋼架的橘白光都消失）。原生相機的順序是 BloomAndFlares → AmplifyColor → SunShafts，我們把光束和霧、AO 放在同一個泛光前的材質裡，加上去的光束再被泛光擴散成一整團。改成同一段程式跑兩個 pass：霧與 AO 在泛光前，SunShafts 在調色之後（`BL_SceneColorAfterDOF` priority 110）；每個取樣另外夾在 0～1（原生的光束來源是 8 位元 RT）。結果窗口後方出現一條條光線，白團消失：`F:\OpenKoikatsu\Saved\OKStudio\bright1031\u_shafts_after_grade.png`（之前 `r_before.png`）。
  - 「火焰太大、鋼架被橘光照亮」：對照舊圖，其實是過亮天空與被泛光放大的光束，上一項一起修掉。真正的火焰（mod 道具 Fire 1／Fire 4，分組 8422 的 ParticleSystem）目前完全沒畫（`bounds` 的 `built` 為 false、沒有部件）；ParticleSystem 不轉換是 10-17 的決定，要畫得改用 OK 的 Niagara 特效對應。
  - `83572034_p1` 月盤暗面：H_enry 的 `main_item_studio_alpha` 主 pass 是 `AlphaToMask On`（DXBC 確認沒有 0.5 clip，alpha＝貼圖 a×`_alpha`，SrcAlpha/OneMinusSrcAlpha、寫深度）。月亮貼圖（DXT5）暗面 alpha 0.17、月牙接近 1；原生用一個取樣畫，alpha 低於一半的像素不畫，所以只剩月牙。修正：`shader_pass_state` 讀主 pass 的 `alphaToMask`，記成 `_OKShaderAlphaToMask`；建零件時對仍是自己 shader（state key 相符）的 `main_item_studio_alpha` 依 8x MSAA 的 alpha-to-coverage 把貼圖 alpha 換成 alpha×round(alpha×8)/8（第一版是 alpha < 0.5 清成 0，把 `83283571_p1` 的柔和光束「ビーム・扇」整個砍掉，見 U27 記錄）。不透明的 `main_item_studio` 也帶同一個旗標但輸出 alpha 1，不能裁（第一版裁了，活塞頂變成白盤）。逐點：月盤內 (640,90) 原生 (0,0,3)、修正前 (2,7,63)、修正後 (0,0,0)；月牙 (800,120) 兩邊一致。`F:\OpenKoikatsu\Saved\OKStudio\moon1031\d_alpha_only.png`。已轉好的模型不必重錄：`shader_states.json` 改版到 3 也記 AlphaToMask，遊戲啟動時發現目錄版本舊就在背景重建（`shader_states::ensure_in_background`），讀模型時 `complete` 依 shader 名稱補上旗標（記錄時沒帶 AlphaToMask 的舊模型也補）；KKS 原版的 `main_item_studio_alpha` 同樣是 AlphaToMask On。
  - 同一張場景還有未修的差異：原生中央有一個玻璃房間（角色在白磚房裡），我們沒有；兩側螢幕的內容也不同。
- 驗證：新增 `Tools/check_ok_studio_buttons.lua`，經控制通道新的 `click` 操作（`{"text","index","contains"}`，找畫面上文字相符的 `STextBlock`，對它所在的 `SButton` 呼叫 `SimulateClick`，跑的就是按鈕自己的處理）逐一按下 U16～U21 新加的按鈕，再用 `bones`／`state`／`keys` 讀回結果。實測 57/57（加上 U22 後 65/65，第二批後 72/72）；`OKStudio.UiSelfTest` 46/46；`verify_ok_studio.lua` 6/6；`cargo test studio_ik --include-ignored` 通過。

### U23～U28　對照 HS2Studio6 的第三批（2026-10-31，F 組）

U16～U22 做完後，把各階段記錄裡「還沒做」的項目、第 3 節規格裡仍缺的部分與畫面比對的未修差異收在一起，依擺姿勢、擺場景時碰到的頻率排序。

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U23 角色細調補完 | 眼睛開合滑桿、頸部跟隨強度、遊戲內建姿勢清單（「n／總數」上一個／下一個、復位 T-pose） | **已在 87b9c7877 做完**（列表時漏查程式碼，誤列為未做） |
| U24 姿勢鏡像 | 所選角色的 FK 姿勢左右鏡像（含手指）、只鏡像左／右半邊；IK 目標同時鏡像 | **已在 87b9c7877 做完**；按鈕測試補上左→右讀回 |
| U25 動畫控制器補完 | 輔助 1／2（Studio 的 `animeOptionParam1/2`）、動作模式（`animePattern`）、循環開關 | **已做**：輔助與動作模式（下方記錄）、強制循環 |
| U26 mod 粒子道具 | mod 的 ParticleSystem 道具（`83283571_p1` 的 Fire 1／Fire 4）現在完全不畫：依名稱與貼圖對到 OK 的 Niagara 特效，對不到的列進讀取報告 | **已做**（下方記錄） |
| U27 場景比對剩餘 | `83572034_p1` 中央的玻璃房間不見、兩側螢幕內容不同；`83283571_p1` 原生整體偏粉紅（AmplifyColor LUT 或雲層零件）；光束道具ビーム・扇本身的放射光 | 玻璃房間是原生截圖工具的假差異；偏粉紅已修（cube atlas 面上下顛倒）；齒輪的放射光是 SunShafts，queue > 2500 的零件不在原生深度貼圖裡、要當光源，已修（下方記錄）；舞台前地板偏亮未查 |
| U28 效能與小視窗 | `run_ok_studio_perf.lua` 只開一個 Unreal 時量；1280×720 視窗下逐窗檢查不出框 | 小視窗**已做**（下方記錄）；效能未量（等全機只剩一個 Unreal） |
| U29 音效選單 | 左上「音效」主選單（第 3.1 節規格）只是空殼：Studio 背景音樂（BGMCtrl）與外部音源（OutsideSoundCtrl）的播放、循環、隨場景存讀，KStudio 場景帶進來 | **已做**（下方記錄）；KKS 的 Studio 沒有環境音清單（ENVCtrl 只讀過不用）；KKPE 外掛資料見記錄 |
| U30 角色語音 | 角色選單的「語音」（第 3.8 節 `hs2/55_voice.png`）：性格→分類→語音三欄，加入角色的播放清單；清單的播放、停止、循環方式、移除、上移／下移、清空；角色說話時嘴型跟著動；KStudio 場景的 voiceCtrl 帶進來 | **已做**（下方記錄）；語音檔 1.9 GB 進 LFS，分三個提交（81159b7de、f13019417、4fb0b298c，各約 650 MB） |
| U31 燈光細項 | 第 3.5 節：燈光作用對象（全部／角色／地圖）、內外錐角、陰影軟硬 | **已做**（下方記錄）；關節補正改由 U32 做 |
| U32 關節補正 | 角色的關節補正（Studio `OICharInfo.expression`、`MPCharCtrl` 的 JointInfo）：查原作 ExpressionBone 的類別，對應 KStudio 存檔旗標，八個開關、存讀、匯入 | **已做**（下方記錄） |

**U32 關節補正記錄（2026-11-01）**：

- 原作：`ExpressionBone.EnableCategory` 有 10 類，0 左臂（ShoulderL、UpperarmL、ElboL、HandL）、1 右臂、2 左腿（LegL、KneeL、CalfL）、3 右腿、4 左前臂（ForearmL）、5 右前臂、6 左大腿（ThighL）、7 右大腿、8 胸（Bust、BustColDB）、9 飾品掛點（AcsNull）。Studio 的 `OICharInfo.expression` 是 8 個 bool（0.0.9 以前 4 個），預設全關；`AddObjectFemale／Male` 只對 0～7 呼叫 `EnableExpressionCategory`，胸與飾品掛點一直開著。
- Rust：`pose::apply_expression_bone_masked(skel, mask)`，各分支照上面對應類別（ForearmL 寫 `cf_d_hand` 位置與 `cf_d_wrist`、HandL 寫 `cf_d_forearm02`；大腿扭轉是 6／7，膝與小腿是 2／3）。session 多 `expression_mask: Option<u16>`，C ABI `ok_session_set_expression_mask`（`FOkSession::SetExpressionMask`）。設定後不論動畫來源每幀都跑（原生 Studio 每個角色都有這個元件）；沒設定的路徑（Gallery、街區）照舊規則。原本 OK 卡的 session 沒有 game_root，ExpressionBone 從來沒在 OK Studio 跑過（見 ERROR_LOG）。測試 `expression_mask_runs_only_its_categories`。
- 場景：`FOKSceneCharacter::JointCorrection`（位元 0～7），預設 0 = Studio 預設全關；舊 `.okscene` 沒有欄位也是 0，與以前顯示一致。場景物件把 `(JointCorrection & 0xff) | 0x300` 送進角色 session。KStudio 匯入讀 `expression` 陣列。FK 頁加「關節補正」一列：左臂、右臂、左腿、右腿、左前臂、右前臂、左大腿、右大腿、全部。控制通道 `bones` 回報 `joint_correction`，`patch` 用 `{"Character": {"JointCorrection": n}}`。
- 統計：本機 7,652 個場景的角色旗標 `00000000` 26,145 個、`11111111` 12,152 個，其餘混合（`11001100` 1,233 個等）；14 個基礎庫樣本中 `koikatu_cs0000010` 同時有 0、3（`11000000`）、255。
- 驗證：0010 匯入後六個角色各自的旗標正確；角色定格（Speed 0）後全開與全關的截圖平均差 1.88（同設定兩張 0.023），差異在手臂與腿的關節輪廓，沒有撕裂；FK 頁按鈕、存讀（0x55）一致；`ok_studio_ui_fit.lua`（1280×720）0 項、`check_ok_studio_buttons.lua` 97/97、`verify_ok_studio.lua` 全 PASS；`cargo check --release` 與 `--no-default-features`、遊戲 `OpenKoikatsu` 與編輯器 Development 連結成功。

**U31 燈光細項記錄（2026-11-01）**：

- 作用對象改成三選一：全部、角色道具（原本的 `bCharactersOnly`，不照地圖）、地圖（新增 `bMapOnly`：關掉道具的光照通道 0，方向光也不再被選為角色的卡通光）。
- 聚光燈加「內錐角」（`SpotInnerAngle`，-1 照舊用聚光角的八成）；陰影開著時加「陰影軟硬」（`ShadowSoftness` 0～1：點光／聚光的光源半徑 0～30 cm，方向光的太陽角度 0.54°～10°；面光本身就是柔光，不顯示）。
- 驗證：`koikatu_cs0000157` 上方加一盞聚光燈，各設定與基準截圖的平均差（雜訊 0.004）：陰影軟硬 1 為 0.064（變化在書包、牛奶與窗邊牆上的陰影邊緣）、內錐角 0 為 1.58、只照地圖 0.046（只有桌上道具的光不見）、只照角色道具 2.16；存讀一致。1280×720 下「只照角色與道具」選項被截斷，改短成「角色道具」「地圖」，說明放在 `?`。同時修正道具目錄長名稱被截斷（`ガラステーブル(四角)`，改省略號，完整名稱本來就在懸停提示）。

**U30 角色語音記錄（2026-11-01）**：

- 轉換：`ok-extract <遊戲> --oklib studio-voices <base_v1>` 讀 Studio 的 VoiceGroup（40 個性格）、VoiceCategory（`VoiceCategory_<x>_<性格>`）、`Voice_<性格>_<分類>_<n>` 表（編號、性格、分類、台詞、bundle、clip），寫 `studio_voices.json`（另存一檔，8,280 句放進 studio_items.json 太長），clip 寫成 `base_v1/studio/voice/<clip>.ogg`。40 個 `sound/data/pcm/cXX/h/01.unity3d`（共 6.6 GB）每個只載一次、8 執行緒約 5 分鐘；BGM 也改用同一個「一個 bundle 取多個 clip」的函式。寫出 8,020 句、1.94 GB；另外 260 句和 `kks_bgm_14` 一樣是 fsbex 的 `failed to encode Vorbis stream`。原因（錯誤改印 Debug 後看到 `ReadPacket … Incomplete(Size(1))`）：這些串流結尾只剩 1 個對齊位元組，沒有 0／0xFFFF 結束標記，fsbex 還要再讀 2 位元組的封包長度而整首放棄（音訊其實已解完）。fsbex 改用 `Tools/vendor/fsbex`（`[patch.crates-io]`），剩不到 2 位元組就當結束；補轉後 8,280 句全部轉出（2.0 GB）。fsbex 是先解碼再以 quality 1.0 重新編碼，所以 ogg 比原始資料大。
- 場景：角色多存 `Voices`（性格、分類、編號）、`VoiceRepeat`（0 播完停止、1 全部循環、2 單句循環，Studio 的 None／All／Select）、`bVoicePlay`、`VoiceStart`（從清單第幾句開始）。播放用角色自己的 `PlaySpeechPcm`（嘴型跟著音量動）；解碼在背景執行緒；不在基礎庫的句子跳過；匯出影片與靜音時不出聲；改清單不重建角色。
- 建置（2026-11-01 修正，`6ef532add`）：`fsbex` 自帶一份 libvorbis，放進 `ok_extract.lib` 會和 UE 的 libvorbis 重複定義、遊戲執行檔連結失敗；`studio-sounds` 改成 cargo feature，CLI 預設帶著，`build-release.cmd` 建 Unreal 用的靜態庫時加 `--no-default-features` 不帶它。
- KStudio 匯入：OCIChar 的 voiceCtrl（清單每項三個 int、之後一個 repeat）原本讀過就丟，現在帶進來，有清單的角色開場就說。本機 7,652 個場景有 1,059 個角色帶語音（repeat 0：68、1：944、2：47）。
- 語音窗（角色選單「語音」，浮窗 `voice`）：左邊性格、分類、語音三欄（點語音加到所選角色清單；沒轉出的灰色），右邊清單（說到的那句前面標 ▶）、播放（從選中那句開始）、停止、循環方式（點一下輪換）、移除、上移、下移、清空。長台詞以省略號截斷，完整台詞在提示。
- 控制通道：`state` 的角色物件多 `voices`（句數）、`voice_play`、`voice_repeat`、`voice_playing`（正在說第幾句，-1 沒有）；清單用 `patch` 改（`{"Character": {"Voices": [...], "bVoicePlay": true}}`）。驗證：`koikatu_cs0000157` 匯入後角色開口、窗內停止／播放／循環／清空、點語音加入清單、兩句清單 repeat 0 依序說完後停、存讀一致；`ok_studio_ui_fit.lua` 加入 `voice`，1280×720 為 0 項。

**U29 音效記錄（2026-11-01）**：

- 轉換：`ok-extract <遊戲> --oklib studio-sounds <base_v1>` 讀 `abdata/studio/info/` 的 BGM 表（51 首：KK 的 `bgm_00`～`27`、KKS 追加的 `kks_bgm_*`、`kks_song_00` 等；編號、名稱、bundle、clip 名），把 AudioClip 的 `.resource`（FSB5）用 `fsbex` 取出 Vorbis 寫成 `base_v1/studio/bgm/<clip>.ogg`（50 檔、296 MB，LFS），`studio_items.json` 多記 `bgm`。`kks_bgm_14` 原本轉不出來（`failed to encode Vorbis stream`），已修（見 U30 記錄的 fsbex 修補），51 首全部轉出。
- 場景：`.okscene` 多存 `sound`（`Bgm`、`bBgmPlay`、`bBgmRepeat`、`Outside`、`bOutsidePlay`、`bOutsideRepeat`）。音效選單兩個浮窗：背景音樂（清單、播放／停止、循環；沒轉換的灰色）、外部音源（專案 `UserData/audio` 的 ogg／wav 加上場景自己的檔）。解碼在背景執行緒，播完依循環重播或停住；匯出影片與靜音時不出聲。
- KStudio 匯入：SceneInfo 依序存 BGMCtrl（`repeat`、`no`、`play`，repeat 在前）、ENVCtrl（同格式）、OutsideSoundCtrl（`repeat`、檔名、`play`）。本機 7,652 個場景的 repeat 全是 1（全部循環），編號 0～29（清單是 0～29 與 50～70，沒轉出來的列進讀取報告）；外部音源檔從遊戲 `UserData/audio` 或場景旁邊複製進場景的卡片夾，找不到列進報告。
- 控制通道：`state.sound` 回報設定、檔案與是否正在播；`scene` 的 `{"sound": {...}}` 改設定。驗證：BGM 播放、換曲、停止、窗內按鈕、存讀、`koikatu_cs0000383`（BGM 1 自動播放）匯入、外部音源 ogg 播放；`ok_studio_ui_fit.lua` 加入兩個新浮窗，1280×720 為 0 項。
- KKPE（`kkpe` 外掛）：本機有這份資料的 28 個場景全是空的（道具 `<iks/>`、角色的校正全關），沒有可還原的內容，不實作。

**U28 小視窗記錄（2026-11-01）**：控制通道新增 `ui_fit`（`{"open": 浮窗}`／`{"close": …}`／`{"page": n, "bones": k}` 開窗；不帶參數時回報）：走訪工作室畫布上每個顯示中的區塊（浮窗、詳情窗、外殼各欄），列出超出所屬視窗的元件、被截斷的文字（文字想要的寬度大於分到的寬度）、跑出畫面的視窗；捲動區與清單內只看寬度。刻意以省略號截斷的文字掛 `Ellipsis` 標記，不算問題。`Tools/ok_studio_ui_fit.lua --scene <有角色的 .okscene>` 逐一打開 21 個浮窗、詳情頁（骨骼 7 個子頁）並各拍一張 UI 截圖（`Saved/OKStudio/mcp_ui/<tag>_*.png`），有問題時結束碼 1。

- 1280×720（畫布 1600×900，介面依高度等比縮放，所以視窗框本身都在畫面內）第一次跑出 89 項：變換列數值顯示 6 位小數被截斷（每個詳情頁都出現）、骨骼頁的勾選框長文字超出右緣 35、`FK←目前姿勢` 按鈕、注視點與姿勢檔的說明、表情的「張嘴（-1 照動畫）」、角色卡／場景檔／姿勢庫縮圖下的長檔名、道具分類 `STR_MOD(キャラ)`、讀取報告與兩個瀏覽器的提示句、MMD 窗的偏移欄。
- 修法：變換列位置與旋轉顯示 1 位小數、縮放 2 位（SpinBox 的小數位只在建立時讀一次，依數值調整的寫法不會更新）；共用數值框最多 3 位；分段標題、列名稱、勾選框文字改成自動換行（勾選框的文字改放在方塊旁的平面按鈕裡，放在 SCheckBox 內會照全長排列不換行，點文字一樣切換）；縮圖檔名與分類名改成省略號並加完整名稱提示；提示句改換行；`FK←目前姿勢` 改成 `FK←姿勢`；MMD 偏移欄加寬。修完 0 項。

**U25 記錄（2026-10-31）**：OK Studio 播的是動作庫預先烘好的 `.okanim`，每個動作只有控制器預設值那一份，Session 的 Animator 參數 API 對它回 0 個參數（實測 60 多個動作）。改法：

- 轉換器（`ok-extract <遊戲> --oklib anim-convert <lib> <card> [filter] [threads]`）對 H 動作讀控制器，找出 blend tree 真正沿著哪些 Studio 控制變化（`anim::studio_blend_axes`：輔助 1＝`height`／`height1`、輔助 2＝`breast` 系、動作模式＝`motion`），在樹的門檻值與 0、1 的每個格點各烘一份 `<動作>@<控制>-<值>_….okanim`（預設值那點也重烘，不混用舊檔：舊檔可能是別張卡轉的）。轉完逐軸比對：沿某軸所有變體一模一樣（控制器有這個參數、取樣出來的動作卻不跟著變）就去掉那一軸，留第一個值的變體改名、其餘刪除。目錄 `studio_anims.json` 每個動作多記 `axes`（控制、參數名、預設值、取樣值）與 `variants`；讀控制器很慢（全部 H 動作約 20 分鐘），所以記 `blend_checked`，之後的轉換沿用。
- 全部 4,918 個 H 動作的控制器：4,318 個的樹用到身長（0、0.5、1）、558 個另有動作模式（0、1）、14 個用 `height1`、胸部參數沒有任何動作用到、26 個都沒有。實際取樣後比對（853 條軸輸出不變被去掉，例如 `2/112/*` 的身長 0～1 輸出完全相同，`h_motion_along_height`）：3,605 個沿身長、425 個沿身長＋動作模式、137 個只沿動作模式、751 個沒有變體。共 13,639 個變體檔、361 MB（`base_v1/anims/studio/*@*.okanim`，8 執行緒取樣約 3 分鐘；讀控制器約 20 分鐘只在第一次）。
- OK Studio：有變體的動作把格點組成巢狀 1D blend（每層一個控制，`Axis.param` 指定讀第幾個播放器參數，等於多線性內插）；`FOKSceneCharacter::AnimFloats` 以控制名（`option1`／`option2`／`pattern`）記值，沒設的用控制器預設值。動畫控制器浮窗列出這個動作有的控制（輔助 1（身長）、動作模式）與「預設」；KStudio 場景匯入帶入 `animeOptionParam1/2` 與 `animePattern`。控制通道：`state` 每個角色的 `anim_controls`（播放器目前的值），`pose` 的 `anim_controls` 設值（空物件＝全部回預設）。
- 強制循環（KStudio 的 forceLoop）：動畫控制器「強制循環」，播放時間對動作長度取模；KStudio 匯入帶入。
- **變體打包檔（2026-10-31 起進版控）**：13,639 個小檔改成一個打包檔 `base_v1/anims/studio_variants.okpack`（351 MB，Git LFS，`.gitattributes` 的 `base_v1/anims/*.okpack` 規則）。格式：`OKVPACK1`、u32 個數、依名稱排序的索引（u16 名稱長度、UTF-8 名稱、u64 偏移、u32 長度），後面接各變體的 `.okanim` 原始位元組；名稱就是 `studio_anims.json` 的 `variants` 裡的路徑（`anims/studio/<動作>@<控制>-<值>….okanim`），json 照舊記 `axes`／`variants`。OK Studio（`OKSceneActor.cpp` 的 `ReadStudioVariant`）先找同名散檔，沒有就讀打包檔：索引每個檔案只讀一次，單一變體依偏移讀出，不整包載入；打包檔不在時照舊播單一動作（沒有輔助／動作模式）。Rust 端是 `studio_anims::variant_pack`。打包檔讀出的 13,639 個變體和原散檔逐位元組相同；`studio_anims.json` 一起進版控。
- **重新產生變體**：乾淨 clone 建好 ok-extract（`cargo build --release --bin ok-extract --manifest-path Tools/ok-extract/Cargo.toml`）後，一條指令：

  ```powershell
  .\Tools\ok-extract\target\release\ok-extract.exe D:/KoikatuSunshine --oklib anim-convert Content/IndependentResources/base_v1 - hanime_ 8
  ```

  第一個參數換成自己的 KKS 遊戲目錄。`-` 表示用遊戲的預設角色取樣（不讀任何卡；取樣結果帶一點角色的基本姿勢，用同一個角色才能逐位元組重現，任何安裝都有預設角色）；也可以給一張 OK 卡或原作卡。轉換時先把打包檔展開成散檔（已經存在的會跳過、去軸比對也用它們），完成後全部寫回打包檔並刪掉散檔。只想把現有散檔打包時用 `ok-extract X:/NoGame --oklib anim-pack Content/IndependentResources/base_v1`。第一次要讀全部 H 動作的控制器（約 20 分鐘），之後 `studio_anims.json` 記了 `blend_checked` 就沿用；取樣約 3 分鐘（8 執行緒）；最後重建目錄約 20 分鐘。完成時印出 `OKANIM … controls dropped` 與 `OKANIM catalogue 5805 animations`。

**U26 記錄（2026-10-31）**：mod 粒子道具（只有 ParticleSystem）原本完全不畫。`studio_mod_items.json` 的道具若來自粒子包（bundle 路徑含 particle／effect／fx），另存一份（沒有轉出模型的也留，但不進道具瀏覽器）；KStudio 匯入時依名稱與 prefab 對 `effects.json` 新增的 `words`（最長的字優先，可寫成 `["cigarette", 0.1]` 帶縮放）換成 OK 的 Niagara 特效，對不到的列進讀取報告。`83283571_p1`：RSkoi 的 Fire 1／Fire 4 變成火焰、Gas 變成煙、Dust 變成光粉；手上的 Cigarette Smoke 第一版對成全尺寸的煙，畫面中央一大團白，加上 0.1 縮放後消失。`F:\OpenKoikatsu\Saved\OKStudio\u26\83283571_p1_fx2.png`。粒子包裡有模型的道具（螢幕、蝴蝶）照常當模型，只有沒模型又對不到的才進讀取報告。

**U27 記錄（2026-10-31）**：`83572034_p1` 中央「玻璃房間不見、兩側螢幕內容不同」不是我們的問題：場景的地圖是 33 號（空き部室，prefab `p_koi_stu_map49_00`），地圖位移 caMap 是 y＝-100，OK Studio 照樣放在地下 100 m；原生截圖工具（`kks_bright_1031\Scene2`）沒套 caMap，把房間畫在舞台中央，螢幕相機才拍到房間裡的她。場景 PNG 自己的 KK 縮圖中央是暗的、螢幕拍到舞台上的她，和 OK Studio 一致（`F:\OpenKoikatsu\Saved\OKStudio\u27\83572034_p1_a.png`）。

- 光束放射光：齒輪上的「ビーム・扇」（13/26/488）是 `main_item_studio_alpha` 的網格特效（AlphaToMask On），本來就有建，是 AlphaToMask 的第一版模型（alpha < 0.5 清成 0）把 alpha 0.3～0.5 的柔和光束整個砍掉。改成 8x MSAA 的 alpha-to-coverage：貼圖 alpha 換成 alpha×round(alpha×8)/8（`unity::alpha_to_coverage_png`）；道具透明度（Studio 的 `_alpha`）在 `AKKPreviewActor` 也照同一式換算。月亮暗面 (640,90) 現在 (0,1,7)，原生 (0,0,3)；第一版 (0,0,0)、修前 (2,7,63)。
- 偏粉紅：AO 的粉紅 Tint (0.954,0.727,0.727) 與粉紅的 `ambientShadow` (0.389,0.044,0.199) 都已讀進來。差異是逐區量出來的（1280×720，區域平均 RGB）：天空左側 原生 201,110,135／我們 208,123,148；鋼架 51,45,68／128,109,116，關掉 SunShafts 後 57,63,88。所以鋼架變亮全是光束後處理：我們太陽附近的天空偏白（(900,200) 原生 225,134,141、我們 230,219,200；(640,160) 252,182,163 對 249,249,232），白色天空減掉門檻後是飽和的光源，光束把鋼架與舞台一帶打亮，原生那裡是粉紅天空、光源弱。天空 cubemap 已確認是 LDR（alpha 全 1，`OK_SKY_DEBUG=4`），`_Tint` 0.9 × `unity_ColorSpaceDouble` 2；太陽附近為何偏白（取樣方向、atlas 解析度或色彩轉換）**尚未查明**，`OK_SKY_DEBUG=2` 的原始貼圖值在 (900,200) 是 211,168,157，乘上 1.57 會飽和成白，原生卻是 225,134,141（G 更低）：原生在同一個畫面位置取到的是天空的另一個方向（舞台幾何位置兩邊一致，所以是天空的取樣方向或太陽在 cube 裡的位置不同，我們的太陽亮區偏低、偏大）。下一步查 Skybox/Cubemap 在網格上的取樣方向（物件空間頂點、_Rotation、atlas 面的對應）。另外：粒子特效剛載入的幾秒會噴出大團白煙（第一個 capture 會拍到），穩定後消失。
- **偏粉紅已修（2026-10-31 晚）**：原因是 cube atlas 的每個面上下顛倒。`unity::cubemap_atlas` 把面資料當成 Texture2D（由下往上存）翻了一次，但 cubemap 的面資料本來就是由上往下存，翻完反而顛倒。原生量到天球 `_Rotation` 是 0、半徑約 575 m，取樣方向與我們一致；用 `OK_SKY_FLIP` 實驗四種翻法，只有「每面上下翻回來」吻合：天空左側 201,109,135（原生 201,110,135）、天空上方 216,146,146（原生 216,145,144）、鋼架 59,57,81（原生 51,45,68，修前 128,109,116）。基礎庫裡已錄的 atlas 都是這個方向，所以改在讀取端：`OKCubeAtlasSample`（天空球、水面反射）與地圖反射探針的取樣都改成從面的底部取列，不必重錄模型。對照圖 `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\06cb08af-708c-4559-954f-993ce591a332\scratchpad\sky_cmp.png`（左原生、右修後）。
- 光束放射光的更正：齒輪周圍的放射光不是「ビーム・扇」（那兩個是噴火裝置上 45 cm 的小扇形，id 211／227），而是原生 SunShafts（useDepthTexture，太陽在畫面中央）穿過窗戶與齒輪縫隙的光芒。我們的 SunShafts 在窗戶上比原生亮（243 對 229）、齒輪一帶比原生弱（58 對 106，關掉光束是 50）：光芒沒有往外拉長。數學（門檻、距離權重、四次徑向模糊）已逐項對照，**還沒查**的是來源像素（原生的來源是半解析度 RT、每次模糊後存 8 位元）與窗戶是否寫入深度。
- **齒輪一帶的光束已修（2026-11-01，F 組）**：原生的光芒是從齒輪白環、砲管這些近物往外拉的（`OK_STUDIO_SHAFTS_DEPTH=0` 讓所有像素都當光源，形狀就和原生一樣）。原因是 Unity 的 `_CameraDepthTexture` 只畫 render queue ≤ 2500 的物件，而 Studio 基本形「(キャラ)」的材質 `m_koi_stu_kihon00_02` 是 `main_item_studio`、**queue 3000**（studio/61、65、87 的 bundle 都一樣；探針的 `Scene1.scene.tsv` 也顯示齒輪、牆、窗都是這個材質）。SunShafts 在這些像素看到的是遠平面，它們的顏色就成了光源。我們把這類零件畫成不透明、寫深度，所以光束只從窗戶後的天空來。修法：`AKKPreviewActor::DepthTextureAbsentParts` 記下畫成不透明但 `_OKRenderQueue` > 2500 的元件；場景開了 SunShafts 時 `AOKSceneActor::MarkDepthTextureAbsent` 讓它們畫進 custom depth、stencil 255（半透明繪製順序用的 rank 是 1～255 且只比自己小的，不受影響），光束 pass 在可見面是這類元件（stencil 255 且 custom depth 等於場景深度）時當成遠處。沒開 SunShafts 的場景不多一道 custom depth。結果（1280×720，區域平均亮度）：齒輪區 原生 132／修前 58／修後 134，右上齒輪 147／151，窗戶 140／149。對照圖 `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\06cb08af-708c-4559-954f-993ce591a332\scratchpad\shaft_mark_cmp.png`（左原生、右修後）。剩下：舞台前方地板我們亮很多（關光束時就是 167 對原生 87，另一個問題），它也是 queue 3000 的道具，所以台前多了一些光芒（107 對 74）。
- **舞台前地板偏亮：查到一半（2026-11-01，F 組）**：那塊是物件 175（「キューブ(キャラ）」10 cm 厚的板，z 0 到 −5 m，`m_koi_stu_kihon00_02` queue 3000，底色 0.70、圖樣 28 的 u 縮放 0.01、Material Editor 的 `AnotherRamp`（128×8 多段灰階色帶）與 `AnotherRampFull` 1.5）。水面（StylizedWater，−0.81 m）與海水方塊（179，`main_item_studio_alpha` queue 4907，頂面 −0.87 m）都在它露出部分的下方，隱藏方塊只改變 y ≥ 590 的水面，所以不是水的問題。原生板面（1280×720，x=640）由上往下 133,125,125 → 45,69,90，中間有一塊塊柔和的深色斑；我們整片 192,164,154。原生探針記錄主光 `Directional Chara` 是 Soft 陰影、強度 0.8、只照 layer 10（道具都在 layer 10），所以原生道具走的是 `DIRECTIONAL SHADOWS_SCREEN` 版本；我們的 `ForgeStudio` 是 `DIRECTIONAL` 版本（blob 12），沒有陰影項，Studio 道具也關了逐物件的 toon 陰影擷取。推測：Unity 的螢幕空間陰影用相機深度貼圖重建位置，queue 3000 的板不在深度貼圖裡，它拿到的是後方深度貼圖物件那裡的陰影衰減，再經 AnotherRamp 的色帶變成斑塊。
- **舞台前地板：原因查明（2026-11-01，F 組）**：上面的陰影推測**不成立**。原生探針新增 `--shadow-mask`（`Tools/GamePoseProbe/run_scene_visual_audit.lua`；主光掛 `LightEvent.AfterScreenspaceMask` 複製螢幕空間陰影遮罩、相機掛 `BeforeForwardAlpha` 複製 `_CameraDepthTexture`，輸出 `Scene1.shadow-mask.png`、`.depth.r32f`、`.shadow-mask.txt`），拍在 `F:\OpenKoikatsu\Saved\Tests\kks_shadowmask_1101\`。遮罩確實只含深度貼圖收的物件（角色、鐵架、幾棟建築、一塊大平面；齒輪、牆、舞台方塊都不在，陰影距離 50 m、4 cascades），橫板一整片都是 51（全陰影）；但同一排的原生亮度在 101～184 之間，而且和前一次原生截圖的斑塊位置不同。斑塊是會動的：特效「閃亮光粉」（id 184，原生 `CommonSpace/스테이지/바닥+바다/koi_dust`）除了亮粉 `dust_parts`（`dust_01_lit`）還有一層暗色煙 `smoke_02_lit`（`Ethical Motion/Particles/Unity5/Lit Alpha Blend Soft Particle`）飄在舞台前。我們的 OK 特效庫刻意不轉原作粒子，「閃亮光粉」對到 `NS_OK_Sparkle`，只有亮粉，沒有煙。沒有煙的地方原生 175～184、我們 192，接近。要補的是特效庫：給「閃亮光粉」（kks 13/73/1116、1311）加一層低處的暗煙，或另做一個「光粉與煙」效果對到這個原作道具。深度貼圖的複製值看起來有雜訊（相鄰像素 0.03～0.3 跳動），還沒驗證可用。
- **台前暗煙已補（2026-11-01，F 組）**：原作的 Dust 是 mod 粒子包 `[rskoi] studio particle effects` 的 `koi_dust`（亮粉＋一大片低處暗煙），以前因名字含 dust 被對到通用的「閃亮光粉」。`effects.json` 新增兩個效果：`dust`（光粉與低煙；用 `koi_dust` 這個字對到該道具，亮粉沿用 `NS_OK_Sparkle`）與 `dust_smoke`（低處暗煙，`NS_OK_DustSmoke`）。特效庫多了三個欄位：`constants`（`OKStudio.MakeEffects` 生系統時覆寫樣板模組的常數，例如 `InitializeParticle.Uniform Sprite Size Max`、`ShapeLocation.Box Size`、`SpawnRate.SpawnRate`）、`material`（sprite 材質；`M_OK_SmokeSprite` 缺少時用程式建：半透明、不受光、柔和圓形、粒子 alpha、碰到場景 1 m 內淡出。樣板的 `DefaultSpriteMaterial` 是加色混合，深色煙加上去等於沒加）、`layers`（同時顯示的其他效果與位移）。`color` 可帶第四個數字當 alpha。新指令 `OKStudio.DumpEffectInputs <id>` 列出效果每個模組輸入、rapid-iteration 常數與 sprite 材質。結果（1280×720 區域平均；原生兩次截圖，煙會動）：板面 原生 106／137、修前約 190、修後 133；地板 87／120、172、117；台前光芒 74／79、107、92；齒輪區 132、134、135；窗戶 140、149、149；海面 90／86、—、104。既有的 `.okscene` 存的是 `sparkle`，要從原作 PNG 重新匯入才會換成 `dust`。
- **SunShafts 偶爾沒出來（2026-11-01，F 組）**：一次直接載入原作 PNG 後整個程序都沒有光束（窗戶 91、齒輪區 98，正常 149、137），重跑又有。後處理材質是執行時建的，`ReadyInstance` 在 shader map 不完整時補送編譯，但每個 pass 只送 4 次、而且每幀都送；那次是剛建好 `NS_OK_DustSmoke` 後第一次啟動，編譯器忙，4 次在前幾幀就用完，之後 map 一直不完整，光束永遠不會掛上，也沒有任何訊息。改成不完整時每 2 秒補送一次、不設上限；每個 pass 狀態改變時記一行 `OK studio post pass N: <狀態> (<補送次數> submits)`；控制通道 `state` 多回報 `post_opaque`、`post_shafts`、`sun_shafts`、`post_blendables`，`capture` 在場景開著霧／AO／光束但對應 pass 未 ready 時回傳 `warning_post_opaque`／`warning_post_shafts`。正常情況 1 次補送就 ready；那次的忙碌情況沒有再重現。舊 `.okscene` 只存 `"effect": "sparkle"` 與名稱，沒有原作道具的 GUID／prefab，讀檔時分不出原本是不是 `koi_dust`，所以不在讀檔時自動改；要從原作 PNG 重新匯入。
- **舊場景的 sparkle 自動改成 dust（2026-11-01，F 組）**：場景的效果物件新增 `source`（`FOKSceneEffect::Source`），匯入原作場景時記下 mod 粒子道具的名稱＋prefab（小寫，`FOKStudioCatalog::ParticleText`）。讀 `.okscene` 時，有 `source` 的效果物件依效果庫目前的字詞重新對應（`EffectForParticleText`），對到不同效果就換掉並記 log `OK scene: effect <id> (<source>) now <效果>`。效果庫日後新增或改字詞，舊檔也會跟著換。驗收：重新讀 `83283571_p1.png` 寫出的 okscene 有 `"source": "dust koi_dust"`；把它的效果改回 `sparkle` 再讀，log 為 `effect 184 (dust koi_dust) now dust`。**限制**：這次之前存的 okscene 沒有 `source`，無法知道原本是哪個道具，要重新匯入原作 PNG 才會改。
- **海面與台前光芒（2026-11-01，F 組，未完成）**：
  - StylizedWater 的深度改成和 SunShafts 一樣，把原生深度貼圖沒有的 queue > 2500 部件（stencil 255 且 custom depth 等於場景深度）當成無限遠（`bReadsUnityDepthTexture`，`OKSceneActor` 只要有讀深度的水也會標記）。量測幾乎不變（海面 102、左側 104；原生 90、63），因為這張場景前景水底下的是 queue ≤ 2500 的石地。
  - 前景的淺青是三層 `Xffect/heat_distortion(_t2)`（`p_koi_stu_umi00_00`、`kawa00` 兩層，貼圖都是 `t_koi_stu_umi00_00`）乘在石地上。反組譯 `heat_distortion`（`studio/map/*.unity3d` 裡同名 shader，`dump_shader_dxbc`）：GrabPass 後輸出 扭曲背景×`_MainTex`.rgb、alpha `_MainTex`.a，SrcAlpha/OneMinusSrcAlpha，和 t2 相同，所以乘色模型正確。KKS 是 Gamma 色彩空間，乘色係數改成用編碼值做 lerp 再解碼（`OKModulateInstance`）；這張圖前景幾乎沒變（係數本來就接近 1）。
  - 其他場景重比（2026-11-01）：4432 稻田與 `1547730231799` 沙灘（都有 `mo_stneo_zimen_00` 的 heat_distortion 層），原生探針 `Saved/Tests/kks_heat_1101` 對 UE 的 Gamma 版與線性版：兩版逐像素相同（平均差 0、最大差 4/765），因為這兩張的貼圖 alpha 是 1，兩種公式此時相等；與原生的區域平均差都在 10 以內（稻田 46,57,65 對 43,56,63；沙灘 240,224,177 對 238,219,167）。沒有變差，保留 Gamma 版。
  - 結論：原生前景的暗青（23,80,99）是水在那裡不透明；我們的水在前景幾乎透明（隱藏水面前後只差 3～7）。水面石地的實際深度差、水材質數值（探針只錄到 `_Glossiness`、`_Cutoff`）都還沒對過，下一步要讓探針錄出水材質全部數值與真正的 `_CameraDepthTexture`（目前錄到的 `depth.r32f` 看起來是顏色，含天空雲層，不能當深度用）。
  - 台前光芒仍是 93～98（原生 74～79）；隨機暗煙會讓平台與地板在 120～150 之間跳動，單張截圖不能當結論。
- **海面前景：原因是 Standard 道具被畫成卡通道具（2026-11-01，F 組）**：
  - 探針加了兩項：`--material-props <shader 名稱片段|…|all>` 錄出材質的每個屬性（`prop` 列，含 render queue），深度改在渲染後取全域 `_CameraDepthTexture`（`Scene1.depth-global.r32f`，Unity 的 `Depth` 格式、反向 Z；舊的 `depth.r32f` 用名稱 Blit 拿到的是顏色，不能用）；`--depth-hide` 藏掉指定 renderer 兩幀再錄一次深度，`--hide-file` 從 UTF-8 檔讀 `--hide` 清單（路徑有韓文時）。拍在 `F:\OpenKoikatsu\Saved\Tests\kks_water_1101*`、`kks_water_hide*`、`kks_water_hw2`、`kks_water_hs2`。
  - 水材質（`water_square`，StylizedWater/Desktop）：queue 2500、`_Transparency` 0.35、`_Depth` 15、`_Depthdarkness` 0.15、`_RimSize` 1、`_Rimfalloff` 0.5、`_WaterColor` (0, 0.5035, 1, 0.503)、`_RimColor` (0.75, 0.75, 0.5, 0.25)、`_FresnelColor` (0.547, 0.8655, 1, 0.272)、`_Fresnelexponent` 3、`_Glossiness` 0.5、`_RefractionAmount` 0.055，和我們讀到的一樣。這個水本身會寫進原生的深度貼圖（藏掉它，前景的深度才變成底下的地面或遠平面），所以原生水 shader 讀到的「水後深度差」恆為 0。
  - 逐層藏（後處理全關）：原生前景下 83,116,125，藏水 90,119,123、藏 heat 層 98,122,125；水和 heat 層的影響都小。原生最終畫面的暗青（24,81,100）主要是 AmplifyColor 的 LUT（拿掉它變 79,110,118；這張沒有深度遮罩、沒有 volume）。真正的差別在底下：四層水和海水方塊都藏掉後，前景地面原生 121,118,108、我們 219,213,190。
  - 那塊地面是 mod 道具 307「norimen b1r」（材質 `Conc0244`：Unity Standard、`_Color` 0.8、`_Metallic` 0.435，layer 10）。OK Studio 的道具一律用遊戲的道具程式（卡通明暗）畫，Standard 的 `_Color`、`_Metallic` 與受光角度都沒有用到。修法：整個由 Standard 組成的道具改走地圖材質已有的 Standard 路徑（`SpawnPreview` 的 map 參數：自己的材質圖、`_Metallic`／`_Color`、探針環境光與反射），照明通道仍是道具的（Studio 角色燈）。
  - 結果（最終畫面）：前景下 原生 24,80,100／修前 90,128,130／修後 43,94,109；海面左 17,69,94／45,97,124／23,78,106；海面右 20,74,96／54,104,121／23,84,110；藏掉水與海水方塊後的地面 121,118,108／219,213,190／125,109,102。左側建築也跟著變暗，和原生一致。對照圖 `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\06cb08af-708c-4559-954f-993ce591a332\scratchpad\w_cmp1.png`（左原生、右修後）。沙灘 `1547730231799` 與稻田樣本目視沒有變差，`verify_ok_studio.lua` 全 PASS。
  - 剩下：舞台下方那一條（前景中）原生 99,126,130、我們 61,113,129；台前光芒仍比原生強（我們 144～161，原生 115～138，煙會動）。
- **台前光芒與海面（2026-11-01）**：暗煙 alpha 調成 0.6 後（兩次各 40 秒拍）板面 126／128（原生 106／137）、地板 135／126（87／120）、台前光芒 90／93（74／79）、齒輪 136／134、窗戶 149。台前光芒關掉光束是 79，和原生一樣，多出的是光束：原生台前板面被煙壓得更暗，光源較弱。海面兩側（左右各 280 px）我們不論有沒有光束、煙都在 96～116，原生 63，是 StylizedWater 本身偏亮，與這次無關，**另查**。
- **台前光芒：深度替身改成「原生深度貼圖有的東西」（2026-11-01，F 組）**：
  - 以前光束與水把「不在原生深度貼圖的零件」（queue > 2500，stencil 255）當成無限遠。原生不是這樣：SunShafts 在這些零件上看到的是貼圖裡它們**後面**的東西；台前那塊板（queue 3000）後面是水（約 23 m），不遠，所以原生板子不是光源（原生光束在台前只加 +1）。我們把板子當遠處，台前多出光芒。
  - 改成反過來：`AKKPreviewActor::DepthTexturePresentParts` 記下原生深度貼圖會有的零件（不透明、queue ≤ 2500，再加 StylizedWater：它 queue 2500、有 shadow caster，探針證實它在貼圖裡），地圖零件也算；場景有光束或讀深度的水時 `AOKSceneActor::MarkDepthTexture` 讓它們畫進 custom depth（stencil 0）。光束與水把 custom depth 當作 Unity 的深度貼圖讀；水因此讀到自己的深度（和原生一樣，depthDiff 0）。
  - 材質沒存 queue（-1）時 Unity 用 shader 自己的 queue：`unity::shader_pass_state` 多讀 SubShader 的 `Queue` 標籤，材質多一個 `_OKShaderQueue`；`shader_states.json` 升到第 4 版也記 queue（舊目錄會在背景自動重讀，約 4 分鐘）。`main_item_studio` 本身是 2450（AlphaTest），齒輪、牆這些基本形是材質自己存了 3000。
  - 半透明但寫深度的零件（窗戶玻璃 `main_item_studio_alpha`，queue 4907）為了繪製順序也畫進 custom depth（stencil＝排名），蓋掉了替身：窗外的天空被當成近處。光束在 stencil ≠ 0 的地方改讀場景深度（UE 的半透明不寫場景深度，那裡是玻璃後面的東西）。窗框在玻璃後面所以仍算近處，與原生略有差。
  - 診斷：`OK_STUDIO_SHAFTS_DEPTH=show` 把光束讀到的深度畫出來（紅＝遠，綠隨距離到 50 m）。探針 `--material-props` 多錄 `(passes)`：pass 名稱、RenderType、shadowCastingMode。
  - 結果（`83283571_p1`，1280×720，藏掉全部特效後光束開／關）：台前光芒 192／191，光束只加 +1，與原生（138／137）一致；光束差圖的形狀（整面牆與窗外都是光源，齒輪往外拉）與原生相同（`C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\06cb08af-708c-4559-954f-993ce591a332\scratchpad\fx4_cmp.png`，左原生、右我們）。特效開著時台前在 139～169 之間跳（煙與火焰粒子），原生一張是 138。`verify_ok_studio.lua --tag shafts_1101b` 6/6。
- **舞台下方那一條（2026-11-01，F 組，未修，分析）**：
  - 原生分層：藏水（`kks_water_hidew`）、藏 heat（`kks_water_hideh`）那一條都不變（104,129,132），所以它不是水，是台前板子（queue 3000）伸到水面下的部分：原生水 queue 2500、不寫深度，板子在水之後才畫，水面下的板子完全蓋過水。我們的 UE 半透明水一律畫在不透明板子之上，把它染成深青（我們 46～69,106～124,125～139）。
  - 試過的做法：水在「看到的不透明面比深度替身近」（＝原生較晚畫的零件）的地方 `clip`。要做到這點水本身不能在 custom depth 裡；但水一離開 custom depth，整片海就變成深藍（8,31,57；原生 24,80,100），且與 depthDiff 用 0、0.3、1.5 m 或讀 custom depth 都無關；水留在 custom depth 時海面正確（30,92,108）。另外 `clip` 寫在水的程式裡，custom depth 那一趟也會執行（場景貼圖讀不到），把水自己的 custom depth 寫入也砍掉。原因牽涉半透明排序的深度測試（海的立方體、heat 層的 rank 與水在 custom depth 的位置），還沒理清，全部還原。
  - 診斷 `OK_STUDIO_SHAFTS_DEPTH=show` 改成綠色一律顯示 custom depth、藍色標出半透明零件（排序用 rank）寫入的地方。下一步：先逐一藏海的立方體（179）、heat 層（180～182），在水離開 custom depth 的版本找出是誰被排序測試丟掉，再決定板子的做法（例如只把和水相交、queue 比水高的不透明零件改到水之後畫）。
  - **更正與結論（同日，協調者限時一輪）**：照 Unity queue 讓 queue 比水高、和水相交的不透明零件（台前板子）在水之後重畫（半透明複本只輸出 opaque pass 留下的 SceneColor，依自己的 queue 排在水（改成原生的 2500）之後）。結果那一條幾乎不變（前景中 47,107,124；藏特效 74,127,139）。再逐層藏才看清：我們藏掉水那一條仍是青色（45～55,106～113），藏掉海的立方體（179）與 heat 層（180～182）才變回淺色（151,132,129）；原生藏 heat 不變（103,128,132）。所以染色的主要是 heat 層與海的立方體，不是水，上面「水把板子染暗」的判斷錯了。程式已全部還原，**記為已知差異**。之後要修應先比對原生 heat_distortion（原作是 GrabPass 扭曲、不著色）與海立方體在那裡的樣子。
  - **補註（同日稍後）**：原生的 `kks_water_hidew`／`kks_water_hideh`／`kks_water_hideall` 三張在前景下、海面、前景中幾乎一樣（前景下都是 24,80,100，前景中 103～106,128～130,132～133），只有煙會動的台前不同；後處理全開時藏層的差別可能被 AmplifyColor 的 LUT 壓掉，也可能藏層沒生效。所以「原生藏 heat 不變」不能當證據，heat 層（Studio 的海，`Xffect/heat_distortion`，我們照 DXBC 畫成乘上 `lerp(1, _MainTex.rgb, _MainTex.a)`）在原生的實際影響要在後處理全關下重拍才知道。
- **月盤暗面重拍確認（2026-11-01，F 組）**：`83572034_p1` 重拍（`C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\06cb08af-708c-4559-954f-993ce591a332\scratchpad\moon_now.png`）：月盤內 (640,90) 我們 (0,1,7)、原生 (0,0,3)；(620,100) (0,1,7)／(0,0,3)；月牙 (800,120) (66,149,229)／(67,152,230)。U27 的 AlphaToMask 修正之後沒有退步，上面「待做」裡的月盤暗面、火焰粒子（U26）、Funly 天空盒（更正：其實是 Skybox4，已修）都已處理。

**實際做一個完整場景（2026-10-31，F 組）**：全程用畫面上的按鈕（控制通道 `click`，按鈕自己的處理函式）做：地圖 0 自室 → 加女角 C001 → 女 H 挿入／騎乗位／弱ループ、動作模式 1 → 加男角 Male01 → 道具ハート1 → 特效閃亮光粉 → 相機 → 另存 → 新場景 → 開啟讀回。讀回後地圖、兩個角色（位置、動作、`pattern`）、道具、特效、相機都一致，讀取報告沒有缺件。過程中卡手或不直覺、已修掉的：

| 遇到的 | 修法 |
|---|---|
| 讀地圖後畫面中央出現引擎的英文警告「Multiple directional lights are competing…」（地圖自己的平行光、地圖太陽與場景主光的 ForwardShadingPriority 都是 0） | 每盞平行光給不同的優先序：地圖的依序 0、1…，地圖太陽 1000，場景的燈 2000＋id |
| 新增選單的角色卡、地圖、特效、場景檔視窗都開在選單旁同一個位置，一層疊一層；再按一次「角色」會把被蓋住的卡片視窗關掉，選單同時亮三個 | 這幾個清單（含道具目錄、添加光源兩頁）同時只開一個，開新的關舊的；按鈕切換時，被別的視窗蓋住的視窗改成拉到最前而不是關掉（頁面按鈕同樣）；從「新增」切到角色等其他根選單時收起新增清單（HS2Studio6 的做法），動畫頁不再蓋在卡片視窗上 |
| 新道具、新特效放在世界原點，自室的原點在桌子裡，加了看不到 | 放在目前視角的焦點（選了角色按 F 聚焦後加，就出現在角色身邊） |
| 加道具、特效、相機後狀態列還是「加入角色 Male01」 | 改成顯示剛加入的種類與名稱 |
| 選到燈光、相機、道具時，角色專用的「動畫／狀態／骨骼」頁留著一個只寫「先選擇一個角色」的空白大面板 | 選取不是角色時這些頁暫時隱藏（不關閉），選回角色再出現 |
| H 動作要男女各點一次：選男角 → H 動作 → 分組 → 體位 → 同一個動作，再把位置對齊、動作模式再設一次 | 動畫頁加「配給對方」：把另一個選取的角色（沒有就用最近的角色）設成對方性別的同一個動作，放到同一個位置，帶上同樣的輔助／動作模式與速度，兩人從頭同步（`anim.partner`） |
| 資料夾只有兩張卡時縮圖被拉大到填滿整格 | 卡片格固定大小，靠左上排 |
| 場景檔瀏覽器的資料夾列被一排 `*_cards` 佔滿（KStudio 匯入時拆出的卡片） | 旁邊有同名場景的 `<場景>_cards` 不列 |
| 新場景後存檔名稱欄仍是上一個場景的名字（按另存會問要不要覆蓋舊檔） | 新場景給新的預設名、讀檔後換成讀到的檔名，欄位直接顯示實際要存的名字 |
| 控制通道的 `click` 點不到清單列（動作清單、樹狀列），測試只能繞過 UI | `click` 也找 `STableRow`，在列中央送一次 Slate 左鍵 |

看過但不改的：新角色是 T-pose（原作 Studio 的新角色播「初期ポーズ」，這個狀態本身就是 `tpose`）；C001 的雙馬尾在任何動作下都朝後挺著（髮束本身就硬，T-pose 時看起來垂下是角度）。驗證：`check_ok_studio_buttons.lua` 97/97（第一次在用過的場景上跑是 96/97：測試直接用了我手動設成 1 的 C001，「預設」正確還原成動作自己的 0；乾淨的遊戲重跑 97/97）、`OKStudio.UiSelfTest` 46/46、`verify_ok_studio.lua --tag scene1031` 6/6。

**第二個完整場景（2026-11-01，F 組）**：教室講台上三個人。流程寫成步驟檔 `Tools/ok_studio_flows/scene2_classroom.txt`，用 `Tools/ok_studio_ui_flow.lua` 經控制通道照畫面操作跑完（按鈕、清單列、輸入框都走它們自己的處理；只有把角色擺到講台用 `transform` 代替拖把手）：

1. 地圖 4 教室1-1。
2. 角色卡連加 C002、C011，再到 Demo 加 Male01。
3. 移到講台、面向座位。
4. C002 換服裝組 2、表情眉 2／眼 3 笑顏閉眼／嘴 1。
5. 三人各播 Studio 動作 立ち6／立ち3／立ち1。
6. 道具搜尋「本」加「本1」，在角色分組「手」選右手，「掛到所選部位」。
7. 用兩個視角各加一台相機（全景、C002 特寫），逐台「用此相機」拍照。
8. 時間軸：選 Male01，在開頭與結尾各打 key（結尾往座位走 150 cm）；從開頭播放 4 秒後按播放／停止定格，截圖窗「拍攝」。
9. 「另存新檔」輸入名稱，再按「新場景」，然後從場景檔視窗「覆蓋（開啟）」讀回。

讀回後，以下都和存檔前一致，讀取報告沒有缺件：
- 地圖、三人的位置／服裝組／表情／動作；
- 書掛在 C011 的 `a_n_hand_R`；
- 兩台相機與作用中的相機 1；
- Male01 的兩個 key；
- 播放頭 4.27 秒。

對照數據：
- 兩台相機的畫面幾乎全不同（30,578／32,400 個取樣點）。
- 定格後相隔 2 秒的兩張只差 12／32,400：場景有時間軸軌道時，角色動作跟著時間軸時間走，暫停就一起停。

截圖：
- `F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\20261101_031235_*.png`（各步驟）；
- `F:\OpenKoikatsu\Saved\OKStudio\flow\20261101_031235\`（cam1／cam2／freeze_a／freeze_b）；
- `F:\OpenKoikatsu\UserData\Studio\screenshot\okstudio_20261101_031405.png`（定格截圖）。

過程中卡手或不直覺、已修掉的：

| 遇到的 | 修法 |
|---|---|
| 連加三張卡，三人都生在原點疊在一起，教室的原點又在桌子裡 | 新角色站在視角焦點下方的地面；那裡已有角色就沿畫面右方每 60 cm 錯開（`UOKStudioGame::AddCharacter`） |
| 在表情頁按 F（聚焦所選），框的是全身，臉在畫面上緣外 | 骨骼頁的視線／頸部／表情分頁聚焦時對準臉：`cf_j_head` 上方 8 cm、距離 90 cm（`FocusSelection(bFace)`） |
| 選著掛在 C011 手上的書時加相機，新相機被放進 C011 底下（會跟著她動），名稱還是英文「Camera 6」 | 新物件只放進所選的資料夾，或所選物件所在的資料夾，不進角色或道具底下（掛到角色身上是角色分組的工作）；相機、資料夾預設叫「相機 N」「資料夾 N」 |
| 系統選單固定 140 高，MMD 導演合進來後 14 項只露出 7 項，其餘要靠 3 px 的捲軸 | 選單高度至少容得下全部項目（`SubMenuHeight`），HS2Studio6 的高度當下限 |
| 新場景後時間軸播放頭留在上個場景暫停的位置 | 新場景時時長回 10 秒、停止播放、播放頭與循環範圍歸零 |
| 暫停在 4.15 秒存檔，讀回後物件停在 4.15 秒的樣子，播放頭卻是 0 | 播放頭隨場景存讀（文件新欄位 `playhead`，`SetTimelineTime` 同步） |

控制通道為了照畫面操作補的（AI 操作與測試用）：
- `type`：給提示文字或內容相符的輸入框鍵盤焦點，以按鍵事件清空並逐字輸入，`enter` 送出。道具搜尋框是送出才套用，所以要帶 Enter。
- `click` 加 `"tip": true`：只有圖示的按鈕（時間軸的開頭、播放、打 key 等）用提示文字找。`IconButton` 把提示文字另掛成按鈕的 `tip:` tag，比對時不執行任何提示框 lambda（之前讀提示框文字讓遊戲崩潰過，見 ERROR_LOG）。
- 時間軸播放中，原本整個控制通道都回 `busy: playing`，連播放／停止都按不到。現在播放中允許 `click`、`type`、`capture`，和使用者播放中照樣能按按鈕一致。
- `click` 點清單列之前，先釋放殘留的滑鼠擷取。這輪有一次樹狀列點下去只改了反白、沒改選取；之後兩次完整流程都沒再出現，有釋放時 log 會寫一行。
- `Tools/ok_studio_ui_flow.lua` 的步驟支援 `?ui欄位=值`／`?ui欄位!=值`／`?closed:視窗`。根選單、時間軸、截圖窗都是切換鈕，這樣只在沒開時才按。

看過但不改的：
- 「前視／後視」是世界座標的方向，不是所選角色的正面；角色擺向別處時要自己轉鏡頭。
- 時間軸窗會蓋住屬性窗下半。
- 沒有選取時，變換列顯示位置 0、縮放 0。

驗證：
- `check_ok_studio_buttons.lua` 97/97。系統選單那一項原本假設選單是關的，流程結束時選單開著，第一次跑成 96/97；改成沒開才打開。
- `OKStudio.UiSelfTest` 46/46，在新程序跑。在用過的實例裡跑時，「畫面點角色」會因視角不同失敗；接著 Undo 多退一步，第 123 行取到空指標崩潰，已加上防護。
- `verify_ok_studio.lua --tag scene2c_1101` 6/6。GameSelfTest 曾因播放頭只在存檔時寫入而失敗（存檔前的預期內容沒有它），改成播放頭一變就同步到文件。

### U33～U42　對照 HS2Studio6 的第四批（2026-11-01，F 組）

協調者要求重新對照 `Saved/StudioUIRef/hs2/` 與我們的 UI。逐面板看參考截圖、`OK_STUDIO_HS2_LAYOUT_SPEC.md`，再用 grep 確認程式裡真的沒有；第 9 節不做的（Studio 內換裝捏人、角色 MaterialEditor、語音佇列、聊天）不列。依擺姿勢、擺場景時碰到的頻率排序。

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U33 IK 目標轉方向 | 手、腳的 IK 目標可旋轉（`61_bones_ik.png`）：選到手腳 IK 點時把手可切旋轉，IK 頁加旋轉 XYZ 與「用旋轉」開關 | 把手在 IK 時固定為移動（`OKStudioGame.cpp` 的 `F.bIk ? 0`）；`bUseRotation`／`Euler` 只有 KStudio 匯入會設 |
| U34 自由視角鏡頭設定 | 「当前视口镜头」（`19_camera.png`、`L_53_camera.png`）：自由視角也能調視野角度、透視／正交、正交大小、近／遠面；HDR、MSAA 開關 | 自由視角 FOV 寫死 40；近面、正交、遠面只在用場景相機時套用 |
| U35 FK／IK 部位操作 | FK 整體開關、各部位「初始化」（從目前動作取值）；IK 各部位「复位」 | FK 沒有「全部」開關、只能整個角色「FK←姿勢」；IK 只有「全部」與「清除 IK」 |
| U36 IK 權重 | 整體權重；目前目標的位置權重、旋轉權重分開；上一個／下一個目標；「复位整体与当前目标权重」（`67_bones_weight.png`） | 每個目標只有一個 `Weight` |
| U37 頁內把手大小 | FK／IK 頁底部「操作轴」「控制点」大小滑桿 | 只有設定窗的 Gizmo 大小，骨點大小不能調 |
| U38 角色資源檢查 | 逐角色列出缺的 mod 部件與 shader 異常；「补齐后重试」重讀角色（`13_resource_check.png`） | 只檢查卡片檔在不在，重新檢查不重讀角色 |
| U39 材質編輯器補完 | 貼圖槽加載／清空／重置／匯出與縮放偏移；Renderer 顯示與陰影；換 shader、Render Queue；複製／貼上改動、全部重置；匯出 UV、OBJ、全部貼圖（`20_material_editor.png`） | 貼圖、renderer、shader 編輯只能由 KStudio 匯入產生，UI 只能刪除；沒有複製貼上與匯出 |
| U40 場景卡資料夾 | 「包含子文件夹」、「选择文件夹…」（`21_scene_card_choice.png`） | 三個固定根目錄，不遞迴 |
| U41 角色載入器 | 女／男篩選、「添加默认角色」（`02_hs_loader.png`） | 只有資料夾、搜尋、分頁、加入、替換 |
| U42 遊戲設定 | 主音量、背景時繼續執行、垂直同步、幀率上限（`14_settings.png`） | 設定窗沒有這些 |

待確認（HS2 截圖裡看不到或可能已涵蓋）：道具動畫速度／模式／時間與 `LightCancel` 的 UI、快搜「刷新目录」、地圖窗「设置」、FK／IK 頁「动画位置姿态」。

#### U33 完成紀錄

- IK 頁選到左右手、左右腳時多一個「用旋轉（把手按 E 轉方向）」。打開時從手／腳骨目前的方向取 Euler（`IkEffectorEuler`，角色的 Unity 空間、ZXY 順序），所以不會跳；打開後有「轉 X／Y／Z」與「取目前方向」。
- 手腳 IK 點且已開旋轉時，把手照目前的移動／旋轉模式（W／E）切換；旋轉時世界軸換成角色本地、再換成 Unity 軸，增量乘到目標上，讀數顯示「IK 旋轉」。其他 IK 點仍只能移動。
- 驗證（83283571_p1，FK 先把左上臂、前臂彎起來）：開 IK 後手骨局部角 ≈0；開「用旋轉」後目標 Euler 取到 (52.5, 112.9, 7.1)，手骨局部角仍 ≈0（沒跳）；X 加 60 後手骨局部角變成 (5.8, -23.6, -25.9)。遊戲與編輯器都連結成功，`verify_ok_studio --tag u33_1101` 6/6。
- 沒用畫面拖曳實測旋轉把手（控制通道沒有拖曳操作）；拖曳走的是和骨骼旋轉相同的增量路徑。

#### U34 完成紀錄

- 場景文件新欄位 `FreeView`（`FOKSceneCamera`：視野角度、近面、遠面、正交、正交寬度），隨場景存讀，新場景時重設。自由視角套用它；用場景相機時照舊套那台相機的。
- 相機頁在自由視角時多「自由視角鏡頭」一組：視野角度、近面、遠面（0 無）、正交、正交寬度、鏡頭重設。場景相機那組補上遠面。
- 自由視角正交時，滾輪縮放改的是正交寬度（只改距離畫面不會變）；「聚焦所選」依目前視野角度算距離，正交時一併設寬度。「從視角建相機」在自由視角時帶走整組鏡頭設定。
- 控制通道 `state` 回 `free_view`，`scene` 可帶 `free_view` 改它（AI 與測試用）。
- 不做：HDR、MSAA 開關。Unreal 一律 HDR 繪製，MSAA 只在 forward renderer 有，延遲繪製下沒有對應設定。
- 驗證（83283571_p1，實際視窗截圖）：視野 40→20 畫面拉近；正交寬度 800 變平行投影；遠面 450 cm 時距離 5 m 的角色被切掉；重設後回原樣。遊戲與編輯器都連結成功，`verify_ok_studio --tag u34_1101` 6/6。

#### U35 完成紀錄

- FK 頁：部位列多「全部」開關；多一列「初始化」，按部位把那部位的 FK 換成動作目前的值（先拿掉該部位 FK、重算一次姿勢再讀，所以讀到的是動作本身，不是舊的 FK）。原有的「復位」（拿掉該部位 FK）不變。
- IK 頁：多一列「復位」，按部位把該部位的 IK 目標放回四肢目前的位置（`IkFromFk` 加部位參數；該部位沒有目標時建立全部目標），其他部位的目標不動。
- 指令 `pose.fkinit <部位 0..6>`、`pose.ikreset <部位 0..4>`，控制通道與快捷鍵表都能用。
- 注意 FK 部位：手臂屬於「身體」，「左手／右手」是手指。第一次測試拿上臂測「左手」初始化，值當然沒變；改用頸部測才對。
- 驗證（83283571_p1）：頸部 FK 設 (20, 30, -50) 後「初始化 頸」回到動作的 (0, 0, 0)；IK←FK 後把左右手目標各移 30 cm，「復位 左手」後左手回到原位（差 2 cm 內，其他目標仍在拉），右手維持移開。遊戲與編輯器都連結成功，`verify_ok_studio --tag u35_1101` 6/6。

#### U36 完成紀錄

- 角色新欄位 `IkWeight`（整體權重），IK 目標新欄位 `RotationWeight`（旋轉權重）；原本的 `Weight` 在 UI 改叫「位置權重」。每個目標的位置、旋轉權重都乘上整體權重。
- Rust `apply_studio_ik`：權重陣列長度是目標數兩倍時，後半是旋轉權重；否則照舊（旋轉跟位置同權重）。FFI 介面不變，舊呼叫不受影響。
- IK 頁：位置權重、手腳開旋轉時的旋轉權重、整體權重，「上一個目標／下一個目標」在已啟用的目標間輪轉，「權重復位」把整體與目前目標的權重回 1。
- 驗證（83283571_p1，左手目標移 25 cm 並轉 60°）：全 1 時手到位且轉向；旋轉權重 0 時位置不變、轉向取消；整體權重 0 時手回原位、不轉；位置權重 0.5 時走一半。「權重復位」按下後整體與目標權重都回 1。
- Rust 在匯出的 HEAD 樹（只加這次的改動）上 `cargo check --release` 與 `--no-default-features` 都通過；遊戲與編輯器都連結成功，`verify_ok_studio --tag u36_1101` 6/6。

#### U37 完成紀錄

- 設定新欄位 `PointScale`（`settings.json` 的 `point_scale`，0.3～4）：畫面上 FK 骨點、IK 點的大小與點選範圍都乘它。設定窗多「控制點大小」一列。
- FK 頁（骨骼打 key 那列下面）與 IK 頁底部加「操作軸大小」「控制點大小」兩個滑桿，改的就是設定裡的 `GizmoScale`、`PointScale`，即時存檔。
- 驗證：`settings.json` 設 `gizmo_scale` 2、`point_scale` 3 後開場景，FK 頁滑桿顯示 2.0／3.0，骨點變成原本的 3 倍大；測完刪掉設定檔回預設。遊戲與編輯器都連結成功，`verify_ok_studio --tag u37_1101` 6/6。

#### U38 完成紀錄

- 資源檢查窗在缺件清單下多「角色」一段：每個角色一行，寫卡片類型（OK 卡（自帶資源）／原作卡／缺卡片）、已顯示或未顯示；原作卡再逐行列出卡片指名的 mod（sideloader 的 GUID），點任一行選取該角色。
- 「重新讀取角色」（指令 `scene.reloadcharacters`）：沒顯示或有錯誤的角色清掉錯誤、重建；都正常時重建全部角色。補了 zipmod 之後按它就會重找。
- 沒做到的：原作卡指名的 mod 裡哪幾個實際缺少。開卡時缺哪些 zipmod 只在 Rust 轉 OK 卡時記錄（`LAST_ABSENT_ZIPMODS`），執行期的 session 沒有對外的介面；要做得加 FFI，留給之後。Shader 異常也一樣沒有逐角色的資料可讀。
- 驗證（83283571_p1）：OK 卡角色顯示「OK 卡（自帶資源），已顯示」；另加一張原作卡（遊戲 `UserData/chara/female` 的卡複製到 `Saved`，測完刪除）列出「原作卡，已顯示，卡片指名 19 個 mod」與各 GUID；按「重新讀取角色」狀態列顯示「重新讀取 1 個角色」，角色仍正常顯示。遊戲與編輯器都連結成功，`verify_ok_studio --tag u38_1101` 6/6。

#### U39 完成紀錄

材質編輯器（道具）補上 HS2Studio6 Material Editor 其餘的頁面，全部寫成既有的材質編輯（`EOKSceneMaterialEditKind`），執行期本來就會套用，隨場景存檔：
- 貼圖槽：上方一個 PNG 路徑欄（可只寫 `UserData/Studio/texture` 底下的檔名）；每個槽「載入／清空／預設／匯出」，下面一列縮放 X／Y、偏移 X／Y（`TextureST`，起始值取材質自己的 `_ST`）。清空用 1×1 白圖代表沒有貼圖；匯出改過的槽存改過的圖，沒改的從基礎庫取原圖（`FOkModel::TexturePng`）。
- Renderer：目前選的 renderer「顯示」開關與「陰影」切換（不投影／投影／雙面投影／只有影子），值回到預設時拿掉那筆編輯。
- Shader：輸入 shader 名稱按 Enter 套用（空白回原本），Render Queue（-1 不改）。改 shader 會重建道具。
- 「複製改動」「貼上改動」：複製目前材質的改動，貼到目前選的材質（可以是別的 renderer 或別的道具）；「道具全部重置」清掉這個道具的所有材質改動。
- 匯出到 `Saved/OKStudio/MaterialExport/<id>_<名稱>/`（指令 `material.export uv|obj|textures`）：目前 renderer 的 UV 線框（1024 白底黑線）、整個道具的 OBJ（Unity 座標轉成右手、面朝向跟著反轉，含 UV）、每個 renderer 顯示的主貼圖與材質具名的全部貼圖。
- 驗證（83283571_p1 的道具 #309 apart2，11 個 renderer）：OBJ、UV、貼圖共匯出 44 個檔；點「顯示」「陰影」寫出 Renderer 編輯（Enabled 0、ShadowCastingMode 2）；載入一張匯出的貼圖到 `_BumpMap`、清空 `_EmissionMap`、輸入 shader 都寫進文件；從 pipe 的材質複製後貼到 edge renderer 的另一個材質（kabe_3-1），兩邊的改動一致；「道具全部重置」後清空。測完刪掉匯出資料夾。遊戲與編輯器都連結成功，`verify_ok_studio --tag u39_1101` 6/6。
- 沒做：Material Editor 的 shader 下拉清單（目前要自己輸入名稱）與角色的材質編輯（第 9 節不做）。

#### U40 完成紀錄

- 場景檔窗的資料夾欄多「包含子資料夾」：打開時列出目前資料夾底下所有層的場景（`.okscene` 與場景卡 PNG），略過匯入時拆出角色卡的 `*_cards` 資料夾。
- 「選擇資料夾」：貼上任何資料夾路徑按 Enter 就切過去（遊戲以 `-game` 執行，不依賴編輯器的系統對話框）；路徑不存在時狀態列提示。
- 一次最多列 500 張縮圖，其餘顯示「還有 N 個場景沒列出，請用搜尋縮小範圍」。
- 驗證：KStudio 場景資料夾打開「包含子資料夾」後列出 7656 個場景（掃描約 3.8 秒），只建前 500 格；貼上 `D:/KoikatuSunshine/UserData/Studio/scene/vmd` 後切到該資料夾、57 個場景。遊戲與編輯器都連結成功，`verify_ok_studio --tag u40_1101` 6/6。

#### U41 完成紀錄

- 角色卡窗上方多「全部／女／男」切換：依卡片的性別（KK sex，讀整張卡，同一檔案版本只讀一次）篩掉另一性別與讀不出的卡。
- 「加入預設角色」（指令 `add.defaultcharacter female|male`）：加入目前篩選性別的預設卡（篩「全部」時加女角）。預設卡是設定的 `default_card_female`／`default_card_male`，預覽區的「設為預設角色」把選中的卡設成它那個性別的預設；沒設時用 `Content/CharacterCards/Demo` 裡第一張該性別的卡。原作沒有卡片的「預設角色」，這裡用一張使用者自己選的卡代替（角色卡不進版控，所以不內建）。
- 驗證：`CrowdAPNG` 資料夾 104 張，「女」剩 103 張，「男」只剩一張 sex=0 的卡；篩「男」時按「加入預設角色」加入 Demo 的 Male01。遊戲與編輯器都連結成功，`verify_ok_studio --tag u41_1101` 6/6。

#### U42 完成紀錄

- 設定窗「一般」多四列：主音量（0～1，主音訊裝置的暫時主音量）、背景時繼續執行（`t.IdleWhenNotForeground`）、垂直同步（照引擎／關／開，`r.VSync`）、幀率上限（-1 不改、0 不限、其他是上限，`t.MaxFPS`）。改了立刻套用，存在 `settings.json`（`master_volume`、`run_in_background`、`vsync`、`max_fps`）。
- 工作室啟動時只套和預設不同的值：預設是「不改引擎」，所以測試啟動器加的 `t.MaxFPS 60` 等不會被蓋掉。主控台變數以 Console 的優先序設定，和啟動器的 `-ExecCmds` 同級。
- 「全部恢復預設」後會再套一次（音量回 1、背景照常執行；垂直同步與幀率上限回到「不改」，引擎維持當下的值）。
- 驗證：`settings.json` 設音量 0.5、背景不執行、VSync 0、幀率 30 後開工作室，log 讀回 `t.MaxFPS = "30"`、`r.VSync = "0"`、`t.IdleWhenNotForeground = "1"`（LastSetBy: Console），設定窗顯示這些值；測完刪掉設定檔。遊戲與編輯器都連結成功，`verify_ok_studio --tag u42_1101` 6/6。

### U43～U52　對照 HS2Studio6 的第五批（2026-11-01，F 組）

協調者要求再對照一次 `Saved/StudioUIRef/hs2/`。逐張看截圖，排除第 9 節不做的與 U0～U42 已做的，每項都 grep 確認程式裡沒有。依擺姿勢、擺場景時碰到的頻率排序。

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U43 道具動畫與光照欄位 | 道具頁加動作模式、速度、起始時間、光源取消、發光色／強度、描邊色 | `FOKSceneItem` 已有 `AnimePattern`／`AnimeTime`／`AnimeSpeed`／`LightCancel`／`EmissionColor`／`EmissionPower`／`LineColor`，UI 一個都沒有（只能由 KStudio 匯入） |
| U44 動畫位置姿態 | IK 頁「动画位置姿态」：IK 目標放到動作目前的位置；FK 頁補「FK←IK」（`53_bones.png`、`61_bones_ik.png`） | IK 頁只有 IK←FK；FK←IK 只在 IK 頁 |
| U45 場景瀏覽器分頁 | 「第 N / M 頁」與上一頁／下一頁（`21_scene_card_choice.png`） | 超過 500 個只顯示提示，其餘要搜尋 |
| U46 快搜種類篩選、刷新目錄 | 「筛选列表」限定道具／特效／地圖／動畫／姿勢／角色卡，「刷新目录」（`16_quick_search.png`） | 只有全部／收藏／最近／已隱藏；`FOKStudioCatalog::Reload()` 沒有入口 |
| U47 資源目錄擴充 | 音效、姿勢、背景與前景框的根目錄可在設定裡加（`L_32_sound_external.png`、`17_pose_library.png`） | 設定只有角色卡根目錄 |
| U48 外部音源重新掃描 | 外部音源窗「重新掃描」 | 要關掉再開視窗 |
| U49 地圖窗「設定」 | 地圖窗「读取地图」旁的「设置」（`07_map.png`） | 地圖位置／時段在畫面設定分頁，地圖窗沒有入口 |
| U50 角色卡路徑列 | 上一步／下一步／回根目錄與可輸入的路徑列（`51_kk_card1_full.png`） | 只有根目錄、子資料夾與上一層 |
| U51 資源檢查「資源目錄」 | 資源檢查窗跳到設定的資源目錄頁（`15_save.png`） | 沒有 |
| U52 材質編輯器隱藏屬性、接收陰影 | 「隐藏属性」開關、Renderer 接收陰影（`20_material_editor.png`） | `_OK*` 屬性一律不列；Renderer 只有投影模式 |

前一批的「待確認」：道具動畫與 LightCancel 的 UI → U43；快搜「刷新目录」→ U46；地圖窗「设置」→ U49；「动画位置姿态」FK 頁已有（FK←姿勢），IK 頁 → U44。

#### U43 完成紀錄

- 道具頁「描邊寬度」下多七列：描邊顏色、發光顏色（色塊 alpha < 0 是「照模型」）、發光強度與光源取消（-1 照模型）、動作模式（0～99）、動畫起點（0～1）、動畫速度。
- 發光顏色／強度以材質覆寫送到 `_EmissionColor`／`_EmissionIntensity`。描邊顏色原本只寫進材質覆寫 `_LineColor`，實測對 item_draw 描邊沒有作用，改成新欄位 `AKKPreviewActor::ItemLineColorOverride`（共用外掛，預設 alpha -1 不改）：建立道具部件時，有 item_draw 描邊的部件改用這個顏色。
- 驗證：控制通道 `patch` 改輪 #45 的 lineColor／lineWidth、emission 後 `inspect` 讀回新值，重建道具沒有錯誤。畫面上沒能確認：測試場景（83283571_p1）裡有描邊的道具太小，改紅色、寬度 4 前後的截圖分不出差異；立方體 #312、道具 309 不畫描邊，也看不出發光。描邊與發光的實際畫面效果**尚未確認**。遊戲與編輯器都連結成功，`verify_ok_studio --tag u43_1101` 6/6。

#### U44 完成紀錄

- IK 頁第一顆按鈕「IK←動作」（指令 `pose.ikfromanim`）：暫時清掉 FK 與 IK、同步一次取得只有動作時的姿勢，再還原 FK，把 IK 目標放到動作讓手腳所在的位置。原本有開的效應器只更新那些，沒開的時候 13 個全放。
- FK 頁按鈕列改成 FK←姿勢、FK←IK、IK←FK、清除 FK，兩頁都能互轉。
- 驗證：左臂有 FK 時按 IK←動作，FK 保留（1 根骨）、IK 目標 13 個，左手目標在 58.3,-3.3,134.5（動作本身的手位置）。和 U43 同一次建置與 `verify_ok_studio --tag u43_1101` 6/6。

#### U45 完成紀錄

- 場景瀏覽器改成每頁 100 個、下方「‹ N / M 頁 ›」與資料夾、場景數；換資料夾、切子資料夾、貼路徑、搜尋都回到第 1 頁。取代 U40 的「只列前 500 個」。
- 驗證：KStudio 場景打開「包含子資料夾」7656 個場景分成 77 頁，按 › 到 2 / 77 頁顯示下一批縮圖；只有 5 個的資料夾顯示 1 / 1 頁。和 U43 同一次建置與 verify 6/6。

#### U46 完成紀錄

- 快搜在「全部／收藏／最近／已隱藏」下多一列種類：全種類、道具、特效、地圖、動畫、姿勢、角色卡，和上一列可疊用。
- 同一列右邊「刷新目錄」（指令 `catalog.reload`）：丟掉目錄、重新讀 `studio_items.json` 等目錄檔，重建子選單、屬性區與開著的視窗（指向舊目錄的「動作同步」指標一起清掉），狀態列顯示道具／動畫／特效數。
- 驗證：搜「輪」全種類 15 筆（道具 13、動畫 2），「地圖」0 筆，「動畫」2 筆；刷新目錄後狀態列「8231 個道具、5805 個動畫、16 個特效」，快搜仍可用。遊戲與編輯器都連結成功，`verify_ok_studio --tag u46_1101` 6/6。

#### U47 完成紀錄

- 設定「資源目錄」分頁從只有角色卡，改成五組可加可移除的資料夾：角色卡、外部音源（.ogg／.wav）、姿勢庫（.dat）、背景圖、前景框（.png）。各自原本固定列的資料夾照舊列；存姿勢仍存到 `UserData/Studio/pose`。存在 `settings.json`（`audio_roots`、`pose_roots`、`bg_roots`、`frame_roots`）。
- 外部音源窗、姿勢檔（`FOKStudioPose::Files()`，快搜與姿勢頁共用）、背景／前景框一覽都會掃加入的資料夾。
- 驗證：在設定頁輸入三個資料夾，外部音源窗列出測試資料夾裡的 wav；加入 `D:/KoikatuSunshine/UserData/bg` 後背景一覽的 `bg_01.png` 有兩格（基礎庫一格、加入的資料夾一格）；存一個 KK 姿勢後把檔案移到加入的姿勢資料夾，快搜「姿勢」仍列出它。測完已從設定移除測試資料夾。遊戲與編輯器都連結成功，`verify_ok_studio --tag u47b_1101` 6/6。

#### U48 完成紀錄

- 外部音源窗的播放列多「重新掃描」，不用關掉視窗就能重新列出資料夾；沒有檔案時的提示改成叫人按它。
- 驗證：開著視窗時在資料夾多放一個 wav，按重新掃描後清單從 1 個變 2 個。和 U47 同一次建置與 verify 6/6。

#### U49 完成紀錄

- 地圖窗「讀取」旁多「設定」（指令 `scene.tab 1`），打開畫面設定的「環境／天空」分頁：地圖、位置 XYZ、旋轉、時段、天空。
- 驗證：控制通道 `add.map` 開地圖窗看到「設定」，執行它的指令後畫面設定停在環境／天空分頁（`Saved/OKStudio/mcp_ui/u49_map.png`、`u49_map_settings.png`）。遊戲與編輯器都連結成功，`verify_ok_studio --tag u49_1102` 6/6。

#### U50 完成紀錄

- 角色卡窗頂端多一列路徑列：‹ 上一步、› 下一步（最多記 50 步，到新資料夾時清掉往後的）、「根目錄」（回到目前資料夾所在的根，滑過顯示路徑），以及可輸入或貼上資料夾、按 Enter 前往的路徑框；資料夾不存在時狀態列提示。原本的資料夾按鈕與「定位當前角色的卡」也走同一套歷史。
- 驗證：開角色卡窗看到路徑列與目前資料夾（`Saved/OKStudio/mcp_ui/u50_cards.png`）。上一步／下一步沒能用控制通道點按（通道沒有點 UI 的指令），只確認了畫面。同一次建置與 verify 6/6。

#### U51 完成紀錄

- 資源檢查窗下方多「資源目錄」，打開設定窗並切到「資源目錄」分頁（設定窗已開時只換分頁）。
- 驗證：資源檢查窗看到四顆按鈕（`u50_cards.png` 右側）。同一次建置與 verify 6/6。

#### U52 完成紀錄

- 材質編輯器屬性欄的篩選框旁多「隱藏屬性」勾選：勾起來時在數值屬性下另列 `_OK*` 這些匯入時自己加的值（唯讀），標題的屬性數也加上「N 隱藏」。
- Renderer 區多「接收陰影」：存成材質改動 `renderer/ReceiveShadows`（KStudio 場景的 RendererPropertyList 原本就會匯入這一項，之前被丟掉）。Rust `okmodel_view` 把它寫成 `_OKRendererReceiveShadows`；共用外掛 `KKPreviewActor` 建立道具部件時，這個值是 0 的部件不取樣卡通陰影（`ForgeShadowDepth` 不綁、環境陰影深度用 1）。
- 驗證：選一個立方體道具打開材質編輯器，看到「接收陰影」與「隱藏屬性」，標題顯示「11 隱藏」（`Saved/OKStudio/mcp_ui/u52_material.png`）。`cargo check --lib` 與 `--no-default-features` 都通過；遊戲與編輯器都連結成功，`verify_ok_studio --tag u49_1102` 6/6。關掉接收陰影後的畫面差異**尚未確認**（只改了取樣卡通陰影的部件；Unreal 動態光的陰影仍會落在上面，Unreal 沒有逐元件不接收陰影的開關）。

### U53～U56　對照 HS2Studio6 的第六批（2026-11-02，F 組）

U49～U52 做完後再看 `Saved/StudioUIRef/hs2/` 的 07、12、13、14、15、19、20、54、67 號截圖。設定窗（主音量、背景執行、垂直同步、幀率上限、搜尋、每列預設）、IK 權重頁、動畫窗的女／男／共用篩選、相機近裁剪面都已有，剩下這幾項：

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U53 備份窗「刷新列表」「備份設定」 | 備份窗下方三顆按鈕：立即備份、刷新列表、備份設定（`12_backup.png`） | 只有立即備份；間隔與保留份數要自己開設定的「備份」分頁 |
| U54 材質編輯器「刷新」與匯出位置 | 標題列「刷新」；下方匯出位置輸入框加「應用／預設」（`20_material_editor.png`） | 匯出固定在 `Saved/OKStudio/MaterialExport` |
| U55 資源檢查只看所選角色 | 「所選角色資源檢查」只列選取的角色（`13_resource_check.png`、`15_save.png`） | 一律列整個場景 |
| U56 地圖窗「定位當前」 | 地圖清單捲到目前讀入的地圖並選它（`07_map.png`） | 要自己捲動找 |

#### U53 完成紀錄

- 備份窗下方改成三顆按鈕：立即備份、刷新列表、備份設定（打開設定窗的「備份」分頁）。
- 驗證：開 `ill_ss_sample_00` 後 `scene.backups`，看到三顆按鈕與既有備份（`Saved/OKStudio/mcp_ui/u56_map_locate.png` 右側）。遊戲與編輯器都連結成功，`verify_ok_studio --tag u53b_1102` 6/6。

#### U54 完成紀錄

- 材質編輯器底下多一列「匯出位置」：輸入資料夾按 Enter 套用（建不了就提示並還原），「預設」回到 `Saved/OKStudio/MaterialExport`；存在 `settings.json` 的 `material_export_root`。UV／OBJ／貼圖匯出照舊每個道具一個子資料夾。底列右側多「刷新」，重讀道具的模型與材質。
- 驗證：選野原道具開材質編輯器，看到刷新與匯出位置列，路徑顯示預設資料夾（`Saved/OKStudio/mcp_ui/u54_u55.png`）。改路徑後實際匯出沒有測（控制通道不能在輸入框打字）。同一次建置與 verify 6/6。

#### U55 完成紀錄

- 資源檢查窗標題列右側多「只看所選」：勾起來時缺件與角色清單只列選取的物件、不列地圖；沒選東西時顯示「請先選取物件」。換選取後按「重新檢查」更新。
- 驗證：資源檢查窗看到勾選框，未勾時列出兩個角色（`u54_u55.png`）。勾選後的清單沒能用控制通道切換來看。同一次建置與 verify 6/6。

#### U56 完成紀錄

- 地圖窗搜尋框旁多「定位當前」（指令 `map.locate`，地圖窗沒開時會打開）：清掉搜尋、選中場景目前的地圖，等清單排版後捲到中間。第一次直接在建窗時要求捲動沒有作用（子元件還沒排版，SScrollBox 找不到那一列就丟掉請求），改成 active timer 延 0.05 秒再捲。
- 驗證：`ill_ss_sample_00`（地圖 51 民宿）執行 `map.locate`，清單捲到サンシャイン分類、51 民宿反白在中間（`Saved/OKStudio/mcp_ui/u56_map_locate2.png`）。遊戲與編輯器都連結成功，`verify_ok_studio --tag u53b_1102` 6/6。

### U57～U59　第七批（2026-11-02，F 組）

協調者要求先補上一批控制通道測不到的部分，再對照截圖（`L_02_kk_loader.png`、`L_51_pose_library.png`、`07_map.png`）列新缺口。

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U57 控制通道補指令並實測 | U50／U54／U55 的按鈕與輸入框改走指令：`cards.folder`、`cards.back`、`cards.forward`、`cards.root`、`material.exportroot`、`resources.selected`；`studio_state` 的 `ui` 多 `card_folder`、`card_back`、`card_forward`、`material_export_root`、`resources_selected_only`、`resources`（資源檢查窗開著時的清單） | 這些只能點畫面，控制通道看不到結果 |
| U58 姿勢庫「刷新」與分頁 | 搜尋框旁「刷新」，下方「上一頁／下一頁」與「N 個姿勢 · 第 i/n 頁」（`L_51_pose_library.png`） | 一次列出全部、沒有刷新 |
| U59 角色卡窗「刷新」「開資料夾」 | KK 角色載入器的「刷新」「目錄」（`L_02_kk_loader.png`）：重掃資料夾與縮圖、在檔案總管打開目前資料夾 | 沒有 |

#### U57 完成紀錄

- 新指令與 `ui` 欄位如上表；畫面上的按鈕、輸入框、勾選框都改呼叫同一個指令，行為不變。
- 實測（`ill_ss_sample_00`）：
  - 只看所選：選道具 #2 只列「沒有缺少的資源」；選角色 #1 只列 #1；不選時是「請先選取物件」；關掉後列出 #1 與 #4 兩個角色。
  - 匯出位置：設成暫存資料夾後 `material.export obj`、`uv`，檔案寫在 `<新位置>/2_野原/`（`野原.obj`、`o_koi_stu_sougen00_00_uv.png`）；空字串回到預設，`settings.json` 的 `material_export_root` 變回空的。
  - 角色卡路徑列：CrowdAPNG → `cards.folder` Demo（back 1）→ `cards.back` 回 CrowdAPNG（forward 1）→ `cards.forward` 回 Demo → `cards.root` 到 CharacterCards（back 2）；不存在的資料夾回傳失敗、資料夾不變。
  - 接收陰影：新場景放預設女角，腳下一塊壓扁的立方體，`studio_patch` 加 `renderer/ReceiveShadows = 0` 前後各拍一張 800×450，逐像素比對**差異 0**。這個情境下本來就沒有影子落在道具上：角色的影子不會投到別的道具（卡通陰影是每個物件自己拍自己），立方體也不會遮到自己。所以 U52 的「接收陰影」目前只影響會遮到自己的道具，畫面上能看出差別的情況還沒找到；開關仍會存進場景、和 KStudio 場景互通。
- 遊戲與編輯器都連結成功，`verify_ok_studio --tag u57_1102` 6/6。

#### U58 完成紀錄

- 姿勢庫搜尋框旁多「刷新」（指令 `poselib.refresh`：重列姿勢檔、丟掉縮圖快取重讀）；下方多「N 個姿勢 · 第 i / n 頁」與上一頁／下一頁（指令 `poselib.page prev|next|頁碼`），每頁 24 個，搜尋後回第 1 頁；最下面一行說明其他資料夾在設定的資源目錄加。`ui` 多 `pose_page`、`pose_pages`、`pose_count`。
- 驗證：暫時把放了 30 個測試 `.dat` 的資料夾加進設定的姿勢資料夾，姿勢庫顯示 30 個、2 頁；`next` 到第 2 頁，再 `next` 回傳失敗仍在第 2 頁；`poselib.page 1` 回第 1 頁；多放一個檔後 `poselib.refresh` 變 31 個（`Saved/OKStudio/mcp_ui/u58_poselib.png`）。測完已還原 `settings.json`。遊戲與編輯器都連結成功，`verify_ok_studio --tag u58_1102` 6/6。

#### U59 完成紀錄

- 角色卡窗第二列左邊多「刷新」（指令 `cards.refresh`：重掃資料夾、丟掉這些卡的縮圖快取）與「開資料夾」（指令 `cards.explore`，在檔案總管打開目前資料夾）。`ui` 多 `card_count`。
- 驗證：到一個只有 1 張卡的暫存資料夾，再複製一張後 `cards.refresh` 變 2 張；把 a.png 換成另一張卡再刷新，縮圖跟著換（`Saved/OKStudio/mcp_ui/u59_cards.png`、`u59_cards_refresh.png`）。「開資料夾」會在使用者桌面開檔案總管，沒有實際執行。同一次建置與 verify 6/6。

### U60～U63　第八批：工作流實測與剩下的缺口（2026-11-02，F 組）

協調者要求工作流優先（場景存讀、角色與道具操作、時間軸、攝影機、匯出）。再看一次截圖（`52_state`、`57_joint_fix`、`19_camera`、`L_52_timeline`、`L_45_scene_card_choice`）：狀態頁、相機頁、時間軸按鈕、覆蓋／疊加、存檔原子寫入、疊加合併時間軸、燈光作用對象都已有。UI 對得上了，剩下的風險在**整條流程串起來時**有沒有錯，以及各批記下的未完成項。

| 階段 | 內容 | 目前缺的 |
|---|---|---|
| U60 端到端工作流實測 | 用控制通道走一遍：新場景 → 加角色、道具、相機、燈 → 擺 FK、打 key、改相機 → 存檔 → 新場景 → 讀回比對物件與軌道 → 疊加同一場景 → 從備份恢復 → 時間軸輸出 PNG 序列核對幀數。發現錯就修 | 各功能分別測過，沒有串起來測 |
| U61 材質編輯器 shader 下拉 | Shader 欄旁加下拉清單，列出 OK 支援的 shader（換 shader 時不用手打名稱） | 只能自己輸入名稱（U41 紀錄） |
| U62 1280×720 視窗版面 | 以 1280×720 開 Studio，主要浮窗與頁面不超出畫面、可捲動 | U1 紀錄的「還沒做」 |
| U63 道具描邊／發光畫面確認 | 找一個有 item_draw 描邊、有發光的道具，改描邊色與發光前後拍照比對 | U43 紀錄「畫面效果尚未確認」 |

#### U60 完成紀錄

走過的流程（控制通道，結果都對）：
- 新場景，加預設女角、立方體、聚光。左臂 FK -60°，從視角建相機。0 秒與 2 秒各對立方體、聚光打 key（立方體 z 0→100，聚光強度 4→3），1 秒時立方體 z=50、強度 3.5。存成 `_u60_flow.png`。
- 新場景後讀回：5 個物件（含相機）、0／1／2 秒的插值值、FK 都和存檔前一樣。
- 疊加同一場景：新物件 id 6～10，疊進來的立方體與聚光的軌道跟著新 id，0／1／2 秒的值與原本的一樣。
- 立即備份後刪掉 4 個物件，再讀備份：物件回到 10 個。
- 時間軸輸出 PNG，0～2 秒、10 fps、640×360：20 張，立方體從畫面外移進畫面。

找到並修好的：
- **從別處讀備份會蓋掉備份**：只有備份窗的「恢復這份」會把場景當成未存；用 `scene.load`、場景瀏覽器或最近場景讀備份資料夾的檔時，場景檔就是備份本身，按儲存會覆寫備份。改成 `LoadFile` 只要檔案在備份資料夾裡，一律清掉場景檔、標成未存，狀態列提示要另取名稱。實測 `scene.load` 讀備份後 `scene_file` 是空的、`dirty` 為 true。
- **控制通道收下錯的骨名不報錯**：`studio_pose` 給 HS2 的骨名 `cf_J_ArmUp00_L`（KK 是 `cf_j_arm00_L`）會存進 FK 但沒有作用，回 ok。改成先檢查全部 FK 骨名（要在目錄的 FK 骨骼裡）與 IK 效應器（0～12），有錯就整個指令不動、回報哪一個錯。實測錯的骨名、效應器 20 都回錯誤，效應器 3 照常設定。
- **`studio_load` 不接受相對路徑**：工具說明寫「相對 checkout 的路徑」，實際只認絕對路徑。改成相對路徑以專案資料夾為準，找不到時錯誤訊息帶上完整路徑。實測 `UserData/Studio/scene/_u60_flow.png` 讀得到。

記下但沒改的：
- 疊加會把對方場景的「主光」也加進來，變成兩盞方向光、畫面變亮。HS2Studio6 的疊加「不動環境」；OK 的主光是一般燈光物件、沒有標記，分不出是主光還是使用者加的方向光，先不動。
- 測試用的場景卡 `_u60_flow.png` 含角色，測完已刪掉。

遊戲與編輯器都連結成功，`verify_ok_studio --tag u60_1102` 6/6。

#### U61 完成紀錄

- 材質編輯器的 Shader 輸入框下多一個下拉，列出可切換的 11 個 shader（Shader Forge 的 main_item_studio／_alpha／_add、main_item、main_item_emission、main_opaque、main_alpha、main_StandardMDK_studio，以及 Standard、HarvexARC/XRay、Unlit/Glitch3DProjection，和 Rust `okmodel_view::shader_supported` 一致），第一項「（原本的 shader）」等於清掉改動。下拉和輸入框共用同一個設定函式；輸入的名稱不在清單裡時，下拉顯示「（上面輸入的 shader）」。
- 驗證：控制通道的 `click` 打得開下拉（畫面上 11 項都在，`Saved/OKStudio/mcp_ui/u61_combo.png`），但**點不到下拉裡的列**：選單內容走得到（SMenuContentWrapper、SMenuPanel），卻對不到列上的文字。試了三種走訪方式（排版子元件、子視窗、所有頂層視窗）都不行，沒有繼續追，`OKStudioControl.cpp` 的嘗試全部還原。改用 `type` 在輸入框打 `Shader Forge/main_opaque` 加 Enter：場景存成材質改動 `Shader`，下拉同步顯示這個 shader（`u61_typed.png`）。遊戲與編輯器都連結成功，`verify_ok_studio --tag u61_1102` 6/6。
- 更正前面紀錄：U50、U54、U55 寫「控制通道不能點 UI、不能在輸入框打字」是錯的，控制通道本來就有 `click`、`type`（HTTP `POST /studio/click`、`/studio/type`），只是 ok-game-mcp 沒有包成工具；中文參數要用 UTF-8 檔案送（`curl --data-binary @檔案`），直接放在命令列會變成亂碼。

#### U62 完成紀錄

- 以 1280×720 開 Studio，用控制通道 `ui_fit` 逐一打開 20 個浮窗、各詳情頁（含骨骼 10 個子頁、畫面設定 8 個分頁）檢查超出與截字。只有兩處有問題，已修：
  - 材質編輯器：材質名下的 shader 名改成自動換行；說明「Shader（Enter 套用；空白回原本）」縮成「Shader（Enter 套用）」（「原本」改由下拉第一項提供）；長屬性名（`_ShadowExtendAnother`）改成省略號、滑過顯示全名。
  - IK 頁：「IK←動作」被截，按鈕列比例改成 IK←動作 1.3、鏡像 0.8。
- 剩下一項沒改：shader 下拉打開時，選單比材質窗右緣多出 75（canvas 單位），選單本身完整可見。
- 修完再量：材質窗只剩這一項，IK 頁沒有問題。同一次建置與 verify 6/6。

#### U63 紀錄（未解決，交回畫面還原）

- 沙發（`2/13/79`，shader main_item_studio，隱藏屬性 `_OKShaderOutline` = 1，表示原作有描邊 pass）：描邊寬度 1 → 4、描邊色改紅、發光改綠強度 1，前後 800×450 逐像素比對**差異 0**；存檔重讀後再拍也一樣。畫面上這個道具本來就看不到描邊，發光也沒有作用。
- 所以 U43 的描邊色、發光欄位目前在這類道具上沒有畫面效果。原因在描邊／發光的繪製（`KKPreviewActor` 的 outline 條件與 item 材質），屬計畫第 9 節「畫面還原」，交給 [OK Studio 計畫](OK_STUDIO_PLAN.md) 處理，這裡不改。

### U64～U67　第九批：時間軸、角色與道具、輸出的工作流（2026-11-02，F 組）

對照 `hs2/18_timeline.png`、`L_52_timeline.png`、`L_53_camera.png`、`15_save.png` 與現行程式後，工作流仍缺的部分。描邊、發光不再追（交回畫面還原）。

| 項目 | 內容 | 現況 |
|---|---|---|
| U64 時間軸切換相機 | 場景軌的 key 記下當時看出去的相機（自由視角或某台場景相機），播放、拖播放頭、輸出 PNG 序列時照 key 切換（不內插，到了就換）；控制通道 `keys`、`state` 看得到 | 場景軌只記曝光與對焦距離；多台相機只能手動「切換到下一鏡頭」，輸出影片中途不能換鏡頭 |
| U65 時間軸窗的骨骼列 | Timeline 窗加「骨骼」列：搜尋框（輸入後選第一個符合的 FK 骨骼）、目前骨骼名、打骨骼 key／刪骨骼 key（`hs2/18_timeline.png` 的「搜索／打骨骼帧／删骨骼帧」）；指令 `pose.bone <名稱>` | 骨骼 key 只在 FK 頁，要先切到 FK 頁點骨骼 |
| U66 角色與道具操作實測 | 用控制通道走一遍：換角色卡後姿勢與軌道是否保留、換服裝組、道具掛到骨骼後存讀、複製帶軌道的物件、刪除與復原。發現錯就修 | U60 只測了新增、擺姿勢、存讀、疊加 |
| U67 輸出實測 | U64 的鏡頭切換配上 PNG 序列輸出，核對每段用的相機；截圖窗各尺寸與透明背景輸出 | U60 只測了 PNG 序列的張數 |

#### U64 完成紀錄

- 場景軌 key 新欄位 `Camera`（-1 自由視角、相機物件 id、-2 不切換；舊檔沒有這欄就是 -2，行為不變）。「場景 key」打下時記錄目前看出去的鏡頭，狀態列顯示「曝光、對焦距離、鏡頭（名稱）」。播放、拖播放頭、輸出時取「時間點以前最後一個有鏡頭的 key」直接切換，不內插；第一個 key 之前用第一個 key 的鏡頭。相機刪掉後，指向它的 key 略過。
- 時間軸「場景（畫面）」列的 key 旁標出鏡頭名，只顯示到下一個 key 之前放得下的字數。
- 控制通道：`keys` 列表多 `camera`；`set` 可帶 `camera` 指定鏡頭（不是相機物件就整個指令不做，不留下 key）。ok-game-mcp 的 `studio_keys` 說明與參數已補，執行檔要等 MCP 重新載入後才換新（使用中無法覆寫，只做了 `cargo check`）。
- `OKStudio.GameSelfTest` 加一項：0 秒自由視角、1 秒相機，0.99 秒與 1.5 秒分別是 -1 與相機，存讀後保留。
- 實測：三個 key（0 秒自由、1 秒 CamFront、2 秒 CamSide），拖到 0.5／1.2／2.5／0.1 秒，`active_camera` 依序 -1、3、4、-1。截圖 `F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u64_timeline.png`。

#### U65 完成紀錄

- 時間軸窗第三列「骨骼」：搜尋框（Enter 選第一個名稱或骨骼名含這段字的 FK 骨骼）、目前骨骼（「上腕 cf_j_arm00_L」）、打骨骼 key、刪骨骼 key。新指令 `pose.bone <名稱>`，`studio_state` 的 `ui.fk_bone` 回報目前骨骼。
- 實測發現：骨骼沒有 FK 值時「打骨骼 key」什麼都沒做卻顯示「骨骼 key：…」。改成 `SetBoneKey` 回傳是否打上，沒打上時指令失敗，狀態列說明「沒有打上：所選角色的 cf_j_neck 沒有 FK 值（在 FK 頁調整它或按「取目前姿勢」）」（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u65_bonekey_none.png`）。

#### U66 完成紀錄

- 用控制通道走一遍：角色 FK 打 0 秒（40°）與 1 秒（-30°）兩個 key，拖到 0.5 秒是 5°；換卡（C002 → C001）並換服裝組後，軌道與 FK 都還在；手上掛道具（`cf_j_hand_L`）打位置 key；刪除再復原，軌道與掛點都回來；存檔、開新場景、讀回，物件、掛點、角色與道具軌道、場景軌的鏡頭 key 都一致。
- 發現：「複製」（Ctrl+D、`studio_duplicate`）不帶軌道，「複製＋貼上」卻會帶，兩者不一致。改成複製時連同子物件的軌道一起複製（複製出的角色與手上的道具都有 0、1 秒兩個 key）。
- UI 的「替換所選角色」會改名並在讀卡失敗時還原；控制通道 `patch` 換卡不改名，這是 patch 的原樣合併，不改。

#### U67 完成紀錄

- U64 的三個鏡頭 key 配 PNG 序列（0～3 秒、2 fps、480×270）：6 張，第 0、1 張自由視角，第 2、3 張 CamFront（兩張完全相同），第 4、5 張 CamSide；第 2 張與第 4 張是兩個不同機位（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u67_frame2.png`、`u67_frame4.png`）。
- 發現：輸出資料夾給相對路徑時，被放到引擎執行檔目錄（`F:/UE5.8/Engine/Binaries/Win64/Saved/...`）。`ExportFrames`（輸出窗與控制通道共用）改成相對路徑以專案目錄為準；控制通道 `capture` 的 `path`、`scenes` 的 `folder` 一併修正。修正後輸出到 `F:/OpenKoikatsu/Saved/OKStudio/_u67_png/...`。
- 透明背景截圖（`capture` transparent，640×360）：32 位元 ARGB，角落 alpha 0、角色處 255。
- 遊戲與編輯器都連結成功，`verify_ok_studio --tag u64_1102`、`--tag u66_1102` 都是 6/6。測試場景與輸出已刪除。

### U68～U69　第十批：疊加與下拉選單（2026-11-02，F 組）

計畫裡的項目都做完了。再對照 HS2Studio6 截圖：相機頁（`L_53_camera.png`）的截圖輸出、使用這個鏡頭、切換下一鏡頭、背景色在 OK 都有對應；系統選單（`15_save.png`）的八項也都有。剩下的是前幾批記下沒改的兩件事：

| 項目 | 內容 | 現況 |
|---|---|---|
| U68 疊加不重複方向光 | 疊加場景時，這個場景已有方向光就不加入對方的方向光（沒有子物件的才略過），狀態列說明略過幾盞；設定「一般」頁加「疊加保留對方方向光」可改回全部加入 | 每個場景都有「主光」，疊加後變兩盞方向光，地圖變亮（U60 紀錄） |
| U69 下拉選單走控制通道 | 所有下拉選單都登記；控制通道 `combo` 列出畫面上的下拉（目前值與選項），帶 `index`、`pick` 時照點選清單的方式選取；ok-game-mcp 加 `studio_combo`。材質編輯器的 shader 清單去掉「Shader Forge/」前綴，打開時不超出窗外 | 下拉清單是彈出選單，`click` 點不到（U61 紀錄）；shader 清單打開時超出材質窗 75 單位（U62 紀錄） |

#### U68 完成紀錄

- 疊加（場景瀏覽器、控制通道 `load` merge）時，這個場景已有方向光，就把對方沒有子物件的方向光拿掉再加入；狀態列顯示「已疊加 _u68a：1 個物件（略過對方 1 盞方向光，設定可改）」。設定「一般」頁新增「疊加保留對方方向光」（`settings.json` 的 `merge_keep_directional`，預設關）。
- 實測：新場景疊加含主光與相機的場景，關閉時燈只剩 1 盞（只加入相機）；勾選後再疊加，變成 2 盞。截圖 `F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u68_settings.png`。測完已把設定改回關。

#### U69 完成紀錄

- 面板的 `Combo()` 建立每個下拉時都登記（顯示、目前值、選取函式），控制通道新 op `combo`：沒帶 `pick` 時依視窗順序列出畫面上的下拉（`current`、`options`）；帶 `index` 與 `pick`（選項序號或完整文字）時，呼叫與點選清單相同的選取函式。ok-game-mcp 加 `studio_combo`（`cargo check --release` 通過；執行檔使用中，下次 MCP 重新載入後才有這個工具）。
- 材質編輯器的 shader 清單去掉「Shader Forge/」前綴顯示，選到的仍存完整名稱。
- 實測：開沙發的材質編輯器，`combo` 列出 1 個下拉、12 個選項；選 `main_item_emission` 後材質改動存成 `Shader Forge/main_item_emission`，下拉顯示跟著變。打開清單後整張清單在材質窗內（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u69_shader_list.png`），U62 記的超框已解決。
- 遊戲與編輯器都連結成功，`verify_ok_studio --tag u68_1102` 6/6。測試場景已刪除。

### U70～U71　第十一批：鏡頭 key 編輯與時間軸復原（2026-11-02，F 組）

再對照 HS2Studio6 的狀態（`L_11_state.png`：全穿／半脫／全裸、各部位穿半脫、飾品顯示）與動畫（`L_20_animation.png`：女／男／共用、搜尋、動畫控制器的速度／動作變化／輔助 1、2／循環）兩頁，OK 都已有對應。這批補 U64 之後的工作流：

| 項目 | 內容 | 現況 |
|---|---|---|
| U70 鏡頭 key 編輯 | 時間軸右鍵選單在選到場景 key 時多「鏡頭」一組（不切換、自由視角、各台相機），指令 `timeline.cut <id>`（-2 不切換、-1 自由視角、相機 id；作用在選取的場景 key，沒選就是播放頭上的場景 key） | 要先切到那個鏡頭再重打場景 key |
| U71 時間軸操作的復原實測 | 打 key、鏡頭 key、移動 key、刪 key、清空軌道，各自 Ctrl+Z／Ctrl+Y 是否正確 | 沒逐項測過 |

#### U70 完成紀錄

- 右鍵選單：選取的 key 含場景軌時，曲線五項下面多「鏡頭」：不切換、自由視角、場景裡每台相機。按下執行 `timeline.cut`，改完立刻重新取樣，畫面切到新鏡頭；狀態列顯示「N 個場景 key 的鏡頭：CutCam」。沒有場景 key 時指令失敗並提示先按「場景 key」。
- 實測（控制通道）：0 秒打場景 key（自由視角），`timeline.cut 2` 後該 key 的鏡頭變相機 2，`active_camera` 跟著變 2。右鍵選單本身要在畫面上右鍵點 key 才會出現，控制通道沒有右鍵，這部分只測了它呼叫的指令。

#### U71 完成紀錄

- 每步間隔 1 秒逐項測：鏡頭 key（復原回自由視角、重做回相機）、打 key、移動 key（1 秒 → 2 秒，復原回 1 秒）、刪 key、清空軌道，復原與重做都正確。
- 注意：0.4 秒內的連續修改會合併成一步復原（拖曳時的設計，`CommitHistory` 在 0.4 秒沒變動後才記錄）。第一次用控制通道連續送指令時，新增相機、場景 key、鏡頭 key 被合成一步，一次 Ctrl+Z 全部消失；人手操作不會這麼快，不改。之後用控制通道測復原要在每步之間等超過 0.4 秒。
- 遊戲與編輯器都連結成功，`verify_ok_studio --tag u70_1102` 6/6。測試場景已刪除。

### U72～U73　第十二批：右鍵選單與復原步驟（2026-11-02，F 組）

| 項目 | 內容 | 現況 |
|---|---|---|
| U72 控制通道右鍵、修右鍵選單 | 控制通道 `mouse`（視窗像素座標的左／右／中鍵點擊，程序內走 Slate，不動系統游標）；`click`、`type`、`combo` 也走訪子視窗（右鍵選單開在子視窗）；ok-game-mcp 加 `studio_mouse` | U70 的右鍵選單只能測指令 |
| U73 每個指令一步復原 | 按鈕、快捷鍵執行的指令與控制通道的每個修改操作，各自成為一步復原（不和 0.4 秒內的前後修改合併）；指令裡再呼叫指令仍算一步；`studio_state` 回報 `undo_steps` | U71 發現快速連續操作會合成一步 |

#### U72 完成紀錄

- 實測發現時間軸右鍵選單一開就關：右鍵推出選單後又把焦點設回時間軸，選單失焦即關閉，曲線選單與 U70 的「鏡頭」都點不到（寫進 `Docs/ERROR_LOG.md`）。改成開選單時不設焦點。
- `mouse` 右鍵點 1 秒的場景 key：key 變成選取、`menu_open` 為 true，選單顯示曲線五項與「鏡頭：不切換、自由視角、CutCam」（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u72_menu.png`）；再用 `click` 點選單裡的 CutCam，該 key 的鏡頭變成相機 2，`active_camera` 跟著變。
- `timeline.cut` 另修：上一個場景留下的已選 key 在這個場景不存在時，原本整個指令失敗，現在略過不存在的、改用播放頭上的場景 key。

#### U73 完成紀錄

- `SOKStudioPanel::RunCommand` 與控制通道 `Run` 前後各結束一次待記錄的修改（`UOKStudioGame::BeginStep`／`EndStep`，只有最外層生效）。拖曳不經過指令，仍照 0.4 秒合併。
- 實測：不等待連續送「加相機、拖播放頭、場景 key」，`undo_steps` 為 2，Ctrl+Z 第一次拿掉場景 key、第二次拿掉相機（之前三者合成一步）。控制通道 `spawn` 內部呼叫 `add.camera` 再改名，仍是一步。
- 遊戲與編輯器都連結成功；`Tools/ok-game-mcp` `cargo check --release` 通過；`verify_ok_studio --tag u73_1102`（最終版本）6/6。測試場景已刪除。

### U74～U75　第十三批：右鍵選單大小與滑鼠拖曳實測（2026-11-02，F 組）

| 項目 | 內容 | 現況 |
|---|---|---|
| U74 右鍵選單實測與大小 | 樹與時間軸的右鍵選單用 `mouse` 右鍵實際打開；選單字級與面板一致 | U72 只修了時間軸選單會關掉 |
| U75 控制通道拖曳與實測 | `mouse` 加 `to`／`steps`（按住拖到另一點）；實測 gizmo 拖曳、樹拖放改父物件、時間軸拖 key，及各自的復原 | 拖曳只能真人操作 |

#### U74 完成紀錄

- 樹的右鍵選單開得起來，但字比面板大約一倍：選單開在自己的子視窗，不在面板的縮放（`SDPIScaler`）底下。改成選單內容包一層縮放，比例＝面板在畫面上的縮放 ÷ 選單所在位置的縮放（`MenuScaled`，每幀依實際所在的縮放換算；面板縮放抽成 `UiDpiScale`）。樹選單與時間軸曲線選單都套用，現在和面板同大小（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u74_tree_menu_fixed.png`、`u74_ease_menu_fixed.png`；修正前 `u74_tree_menu.png`）。
- 相機頁書籤的右鍵（存視角）沒有測。

#### U75 完成紀錄

- `mouse` 的 `to: [x, y]` 會按住按鍵分 `steps`（預設 10）次移過去再放開；ok-game-mcp 的 `studio_mouse` 同步加參數。
- 實測：拖沙發 gizmo 的綠軸 100 像素，Y 變 15.4 cm，Ctrl+Z 一步回 0；把樹上的 CamA 拖到 Sofa 上，變成 Sofa 的子物件（狀態列「1 個物件移到 Sofa 底下」），Ctrl+Z 回根層；時間軸把 1 秒的 key 拖到 2 秒，Ctrl+Z 回 1 秒。
- 遊戲與編輯器都連結成功；`Tools/ok-game-mcp` `cargo check --release` 通過；`verify_ok_studio --tag u74_1102`（最終版本）6/6。測試場景已刪除。

### U76～U78　第十四批：滑鼠操作實測（2026-11-02，F 組）

用 U72／U75 的 `mouse` 實際以滑鼠操作，補前幾批沒測到的部分。

| 項目 | 內容 |
|---|---|
| U76 相機頁書籤、變換列 | 書籤右鍵存視角、左鍵讀回；沒選物件時下方變換列的顯示 |
| U77 畫面點選與 IK 拖曳 | 在 3D 畫面點角色選取、點空白取消；點 IK 點選取後拖把手 |
| U78 浮窗拖動與版面保存 | 拖浮窗標題列，結束後重開位置是否還原 |

#### U76 完成紀錄

- 相機頁書籤 3：視角 yaw 30 時右鍵存、改成 yaw 120 後左鍵讀，回到 yaw 30、pitch -10、距離 300。
- 沒選物件時，下方變換列縮放顯示 0.0（HS2Studio6 顯示 1）。改成無選取時顯示單位值（位置 0、旋轉 0、縮放 1）並停用欄位（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u76_transform_none.png`）。

#### U77 完成紀錄

- 畫面點角色身上選取（selection [2]），點空白處取消選取。
- IK 頁「IK←FK」後畫面出現 13 個 IK 點；點右手 IK 點會選取它並出現把手（點下去拖不會直接移動點，要拖把手，與 HS2Studio6 相同）。拖把手藍軸 120 像素，右手 IK 目標 Z 118.2 → 102.3，手臂跟著下垂（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u77_ik_moved.png`）；Ctrl+Z 一步回 118.2。

#### U78 完成紀錄

- 拖時間軸窗標題列，從 (160, 458) 移到 (460, 319)；結束 Studio 時寫進 `Saved/OKStudio/ui_layout.json`，重開後在同一位置（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u78_reopen.png`）。詳情頁（骨骼頁）不隨版面保存、重開是關著的，這是原本的設計。
- 遊戲與編輯器都連結成功，`verify_ok_studio --tag u76_1102` 6/6。這批沒有改 ok-game-mcp。測試場景已刪除。

### U79～U81　第十五批：鍵盤快捷鍵與把手實測（2026-11-02，F 組）

| 項目 | 內容 |
|---|---|
| U79 控制通道按鍵 | 控制通道 `key`（Unreal 鍵名加 ctrl／shift／alt，程序內走 Slate，快捷鍵與真人按鍵同一路徑）；ok-game-mcp 加 `studio_key`；`studio_state` 的 `ui.gizmo_mode` 回報把手模式 |
| U80 快捷鍵實測 | K、Ctrl+D、Delete、Ctrl+Z、Ctrl+Y、H、F、W／E／R |
| U81 旋轉、縮放把手與 FK 骨點拖曳 | 物件的旋轉環、軸向縮放、中心等比縮放；角色 FK 骨點點選後拖旋轉環 |

#### U79～U80 完成紀錄

- 沙發道具上逐一按：K 打 key（1 個 key）、Ctrl+D 複製（2 個道具）、Delete 刪除（1 個）、Ctrl+Z 復原（2 個）、Ctrl+Y 重做（1 個）、H 隱藏所選、F 聚焦（焦點從 (500,500,500) 移到沙發）、W／E／R 把手模式依序 move／rotate／scale。全部 `handled` 為 true，結果正確。

#### U81 完成紀錄

- 旋轉：拖藍環（Z 軸）約 70 像素，沙發繞 Z 轉 36°；Ctrl+Z 一步回原。第一次起點剛好落在側看成一直線的綠環上，轉成了 Y 軸，是選點錯，不是程式問題。
- 縮放：拖綠軸 80 像素，Y 縮放 1 → 1.8；拖中心方塊，三軸一起 ×1.6。
- FK：骨骼頁打開時畫面顯示骨點；點右上臂骨點出現旋轉環，拖環後 `cf_j_arm00_R` 得到 Z 32.5°，手臂抬起（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u81_fk_rotated.png`）。
- 發現：在畫面點骨點後，狀態列仍是上一次的骨骼名。改成點到骨點時狀態列顯示「骨骼：名稱 骨骼名」（`u81_fk_status4.png`；骨骼名稱沿用目錄裡的原作日文名，例如「体のトップ cf_j_hips」）。
- 遊戲與編輯器都連結成功；`Tools/ok-game-mcp` `cargo check --release` 通過；`verify_ok_studio --tag u79_1102` 6/6。測試場景已刪除。

### U82～U85　第十六批：樹、姿勢庫、動畫與狀態的實測（2026-11-02，F 組）

計畫各項都做完了。再對照 `16_quick_search.png`、`17_pose_library.png`、`43_animation.png`、`52_state.png` 與樹工具列：UI 都有對應，但這幾組只用指令或 `click` 測過，沒有用快捷鍵、滑鼠走一遍，也沒測存讀後是否保留。

| 項目 | 內容 |
|---|---|
| U82 物件樹快捷鍵 | Ctrl+G 群組、Ctrl+Shift+U 解散、Ctrl+Shift+D 錯開複製、Shift+H 獨顯與還原、Ctrl+C／Ctrl+V、鎖定後在畫面點不到；各自一步復原 |
| U83 姿勢庫工作流 | 存姿勢、搜尋、套用到另一個角色、刪除；角色間複製／貼上姿勢、鏡像 |
| U84 動畫控制器與存讀 | 控制器播放、暫停、變化 ◀ ▶、速度；存檔再讀回後動作、速度、時間是否保留 |
| U85 狀態頁與存讀 | 全穿／半脫／全裸、逐部位衣服、配件顯示、換服裝組；存檔再讀回後是否保留 |

#### U82 完成紀錄

- 兩個椅子道具上用 `key` 按：Ctrl+G 群組（兩個放進新資料夾）、Ctrl+Z 一步回原、Ctrl+Y 重做；Ctrl+Shift+U 解散、Ctrl+Z 回到群組；Ctrl+Shift+D 錯開複製（沿畫面右方 20 cm）；Shift+H 獨顯只留所選，再按一次全部還原；Ctrl+C／Ctrl+V 貼上一份。結果都正確。
- 鎖定：鎖住的椅子在畫面上點不到（selection 仍是空），解鎖後點同一點選到它；鎖定隨存檔讀回保留。
- 發現：樹上看不出哪個物件被鎖。樹列最右邊加「鎖」字（懸停提示「已鎖定：畫面上點不到」），沒鎖時不佔位（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u84_live_time2.png` 的「ソファ1」列）。

#### U83 完成紀錄

- 姿勢庫：在名稱欄輸入「u83測試」按「存目前姿勢」，寫出 `.dat` 與 256 px 縮圖；搜尋「u83」只列這一個（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u83_poselib.png`）。
- 選另一個角色，滑鼠點縮圖試套（出現「試套中」與確定／取消）；取消回到原姿勢；再試套後確定，Ctrl+Z 一步回原、Ctrl+Y 重做。垃圾桶確認後檔案移到 `Saved/OKStudio/Trash`。
- 角色間「複製姿勢／貼上姿勢」帶過 FK；鏡像把右上臂 Z 40° 換成左上臂 Z -40°。
- 發現：同一個 Studio 跑久了以後，`mouse` 點浮窗與樹都只移動了 hover、按不下去（畫面點選仍有反應）；重開後正常，原因沒確定。`mouse` 按下前先釋放殘留的 mouse capture，並在 log 記下是哪個元件（`mouse released a stale capture`），之後再遇到可以查。

#### U84 完成紀錄

- 動畫控制器：◀ 變化／變化 ▶ 在同分類內循環（ポーズ1 ◀ → 最後一個，▶ → 下一個）；暫停把速度設 0、播放回到暫停前的速度；強制循環切換。速度 0.5、起始時間 1.25、強制循環、動作編號存檔讀回都保留。
- 發現：控制器的「時間 秒」是起始時間，播放中看不到動作走到哪裡（HS2Studio6 會顯示）。加一列「目前」：播放中的秒數／動作長度（`AOKSceneActor::PlayTimeOf`，循環動作取餘數），例如ポーズ1 顯示「0.02 / 0.17 秒」（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u84_live_time2.png`）。浮窗高度 150 → 170。

#### U85 完成紀錄

- 狀態頁：全穿／半脫／全裸各自把 9 個部位設成 0／1／3；逐部位上衣「脫」、胸罩「半脫」；服裝組切到 2；飾品從「照卡片」改成逐個開關、只開 3 與 5。存檔讀回後衣服、服裝組、飾品都一樣，畫面也對（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u85_reloaded.png`；這張卡的頭髮是飾品，關掉後頭髮跟著消失，是飾品開關本來的效果）。
- 遊戲與編輯器都連結成功；`verify_ok_studio --tag u82_1102` 6/6。這批沒有改 ok-game-mcp。測試場景與 `_cards` 資料夾、測試姿勢都已刪除。

### U86～U89　第十七批：快搜、場景檔窗、快捷鍵設定、背景音樂的實測（2026-11-02，F 組）

對照 `16_quick_search.png`、`11_scene_load.png`、`15_save.png`、`L_45_scene_card_choice.png`、`14_settings.png`、`L_31_bgm.png`：這幾個窗以前只用指令或 `click` 測過單一按鈕，沒有照使用者的順序走完。

| 項目 | 內容 |
|---|---|
| U86 快搜 | Ctrl+F 開窗、輸入關鍵字、種類篩選、點結果加入道具／套用動作、收藏、最近使用 |
| U87 場景檔窗 | 從窗裡輸入名稱存檔、清單點選讀取、覆蓋／疊加選擇、未存檔提示 |
| U88 快捷鍵重綁 | 設定窗改一個快捷鍵、衝突提示、新鍵生效、重開後保留、恢復預設 |
| U89 背景音樂 | 音效選單開 BGM 窗、播放、換曲、循環、停止；存檔讀回後設定保留 |

#### U86 完成紀錄

- Ctrl+F 開快搜，輸入「椅子 -ソファ」並篩「道具」得 40 筆、沒有ソファ；點一列加入道具；星號收藏後「收藏」頁只剩它；「最近」列出剛用過的；篩「角色卡」點 C050 加入角色；篩「動畫」點ポーズ1 套到所選角色。
- 發現：
  - **按 Esc 關浮窗 Studio 會當掉**（`CloseFloat` 收到 `OpenOrder` 自己元素的參照又從裡面移除，TArray 斷言）。改成先複製；Esc 依序關掉快搜等浮窗不再當。記在 `Docs/ERROR_LOG.md`。
  - 兩張同名卡（`Demo/C050`、`CrowdAPNG/C050`）在快搜分不出來：角色卡名稱後面加所在資料夾（「C050　Demo」）。
  - 跑久了以後 `mouse` 點 UI 偶爾只移動 hover（U83 也遇過）。`mouse` 改用真滑鼠的 pointer index（`FSlateApplication::CursorPointerIndex`，原本是 0，那是觸控的編號），並回報 `under`（點到的元件）、`handled`、`captor`（按下後誰拿到 capture）。改了之後同一個流程重測沒再發生；之後再遇到可以看這三個欄位。

#### U87 完成紀錄

- 場景檔窗：名稱欄輸入「_u87tmp」按儲存；新場景後點縮圖出現預覽與覆蓋／疊加；覆蓋讀回物件相同；疊加加入對方的道具與角色（對方的方向光照 U68 略過）；有未存變更時開新場景會詢問，按取消保留原場景；改名、刪除（移到 Trash）都可用。
- 發現：開過的場景卡旁邊會拆出 `<名稱>_cards`（角色卡），改名或刪除場景後它留下來，變成資料夾欄裡的一個資料夾（`_uiselftest_cards` 就是這樣出現的）。改成：
  - 改名時 `_cards` 跟著改名，目前場景用到的角色卡路徑一起改（改名後另存可正常存）。
  - 刪除時 `_cards` 一起移到 Trash，但目前場景還有角色用到時不動。
  - 只處理 `.png` 場景卡；`.okscene` 的 `_cards` 是它引用的檔案，不動。
  - UI 自測結束時也刪掉 `_uiselftest_cards`。
- 控制通道 `save` 失敗時，原本只回「not saved」，改成附上狀態列的原因（例如「cannot read the character card …」）。

#### U88 完成紀錄

- 設定窗「快捷鍵」：搜尋「打 key」，點「（未綁定）」按 K 把骨骼打 key 綁成 K；把打 key 改成 J 後，J 會打 key、K 不再有作用；「全部快捷鍵恢復預設」清掉自訂。設定存在 `Saved/OKStudio/settings.json`。
- 發現：兩個指令都綁 K 時沒有衝突提示。原因是衝突檢查只看有預設鍵的指令，現在也檢查使用者自己綁的；綁定當下狀態列也會顯示「快捷鍵衝突：k: timeline.key, timeline.bonekey」（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u88_conflict4.png`）。第一版的狀態列訊息用了暫存陣列的指標而印出亂碼，已修（記在 ERROR_LOG）。

#### U89 完成紀錄

- 背景音樂窗：點「05 出会い」再按播放開始播；取消循環；播放中換成「07 怒り」會直接換曲；停止。存檔讀回後曲目 7、播放中、不循環都保留。
- 遊戲與編輯器都連結成功；`verify_ok_studio --tag u86_1102` 6/6。這批沒有改 ok-game-mcp（`mouse` 多回報的欄位不改 MCP 的參數）。測試場景、`_cards`、Trash 裡的測試檔都已刪除。

### U90～U93　第十八批：相機、燈光、地圖、截圖與背景的實測（2026-11-02，F 組）

對照 `19_camera.png`、`L_53_camera.png`、`06_light_add.png`、`07_map.png`、`08_background.png` 與截圖窗：這些窗以前多半只用指令測過，這批用按鈕與滑鼠走一遍，並測存讀與復原。

| 項目 | 內容 |
|---|---|
| U90 相機 | 加相機物件、從目前視角建相機、切換使用中相機與自由視角、正／側／頂視、鎖定相機；存讀後使用中的相機保留 |
| U91 燈光 | 添加光源頁加點光、聚光、面光；改顏色、強度、範圍、作用對象；每步復原；存讀 |
| U92 地圖 | 地圖窗選地圖、改地圖位置旋轉、無地圖；存讀 |
| U93 截圖與背景 | 截圖窗各尺寸與輸出檔；背景圖、前景框一覽套用與「無」；存讀 |

#### U90 完成紀錄

- 相機頁：「從視角建相機」加相機 1、2（各記下當時視角）；前／側／上／初始視角正確（yaw -90／180、上視 pitch -89）；「下一相機」依序切相機 1 → 2，「自由視角」回自由視角；選相機 1 按「使用選中相機」切過去。
- 鎖定：沒鎖時中鍵拖曳畫面會脫離相機回到自由視角；勾「鎖定目前相機」後拖曳仍留在相機 1。
- 存讀：使用中的相機（相機 1）存檔讀回保留；鎖定是介面設定，讀場景時取消（和開新場景時一樣）。
- 復原：建相機一步復原；切換相機不算一步（HS2Studio6 也不算），Ctrl+Z 退的是上一個建相機。

#### U91 完成紀錄

- 添加光源頁按點光源、聚光燈、面光源各加一盞（目前燈光 1 → 4）。聚光屬性頁：拖「強度」4 → 75、作用對象改「角色道具」、關陰影、種類改點光；Ctrl+Z 逐步退回、Ctrl+Y 逐步重做，每一步都正確。存檔讀回後點光（原聚光）與面光的設定都保留。

#### U92 完成紀錄

- 地圖窗點「教室1-1」再按「讀取」載入地圖；「設定」開畫面設定的地圖頁，拖「地圖旋轉」到 64°、時段改「夕」；存檔讀回後地圖、旋轉、時段都保留。「（無地圖）」＋讀取拿掉地圖，Ctrl+Z 一步放回。

#### U93 完成紀錄

- 截圖窗：勾「本次目錄」後 1080×1920 與 1280×720 各拍一張，檔案在 `UserData/Studio/screenshot/session_<時間>/`，尺寸正確。
- 背景／前景：在一覽點 `bg_02.png` 與 `koi_studio_frame_00.png` 套用，存檔讀回保留；前景框畫在最上層（`F:\OpenKoikatsu\Saved\OKStudio\mcp_ui\u93_bg.png`）。
- 未解決：有地圖（教室1-1）時背景圖看不到，地圖外面是黑的；拿掉地圖就看得到（`u93_bg_nomap.png`）。關掉霧、體積霧、後處理仍是黑的，表示是某個幾何擋在背景平面（鏡頭前 1 km）前面，沒查是什麼。屬畫面還原，記在這裡交給它。
- 這批沒有改程式，也沒有改 ok-game-mcp；`verify_ok_studio --tag u90_1102` 6/6。測試場景與截圖已刪除。

### U94～U97　第十九批：骨骼 IK、視線頸部、表情手型、加入角色與道具的實測（2026-11-02，F 組）

對照 `61_bones_ik.png`／`L_13_bones_ik.png`、`62_bones_look.png`／`L_14_bones_look.png`、`63_bones_neck.png`、`64_bones_face.png`、`65_bones_hand.png`、`30_kk_loader_cards.png`、`31_kk_card1_preview.png`、`05_item_catalog.png`：骨骼的 FK 頁、姿勢庫、狀態頁已用滑鼠走過（U81、U83、U85），其餘骨骼分頁與加入窗還沒照使用者的順序走完。

| 項目 | 內容 |
|---|---|
| U94 IK 頁 | IK 頁點目標、拖把手、位置權重、整體權重、上一個／下一個目標、IK←動作、IK←FK、FK←IK、清除 IK；各自一步復原；存讀 |
| U95 視線與頸部 | 眼睛、脖子各模式；注視點數值；取鏡頭位置、恢復看鏡頭；跟隨強度；存讀與復原 |
| U96 表情與手型 | 眉、眼、嘴下拉；張嘴、睜眼、眨眼；左右手型、左→右、右→左、復位；存讀與復原 |
| U97 加入角色與道具 | 角色卡窗瀏覽資料夾、點卡預覽、加入、換卡；道具目錄分類、搜尋、加入；各自一步復原 |

#### U94 完成紀錄

- IK 頁：「IK←動作」建 13 個目標；選右手目標、勾「用 3D 把手移動」後拖藍色軸，右手 Z 109 → 124，畫面上手抬起；拖「位置權重」「整體權重」；「下一個目標」換到左腳，「權重復位」只重設整體與目前目標；「FK←IK」（IK 清空、59 根 FK）、「IK←FK」、「清除 IK」；部位「左手」關掉再打開；右手 Z 拉到 300 後「復位 右手」回到 109。每一步各一步復原，Ctrl+Z／Ctrl+Y 逐步正確。存檔讀回：13 個目標、整體權重 0.93、右手權重 0.93、左手部位關閉都保留。
- 發現：
  - **`mouse` 點按鈕時好時壞的原因**：按鈕已按下但沒有拿到滑鼠 capture。Slate 只在應用程式於前景時設定 capture，Studio 視窗被其他視窗蓋住時點擊全部失敗（U83、U86 遇過的就是這個，U86 猜成 pointer index）。`mouse` 與 `click` 點列表列時暫時打開 `SetHandleDeviceInputWhenApplicationNotActive`；`mouse` 另回報 `path`（點到的元件往上到按鈕，以及按鈕有沒有進入按下狀態）。修正後這輪約 40 次點擊都成功；沒辦法刻意把視窗切到背景重現，之後再遇到看 `path` 與 `captor`。記在 `Docs/ERROR_LOG.md`。
  - 面板下半部點不到：`mouse` 加 `wheel`（滾輪格數，正數往上），ok-game-mcp 的 `studio_mouse` 一起加。
  - 剛捲完就拖數值欄，滾輪慣性還在捲，拖到的是別的欄位；等慣性停了再操作就正常，不是程式問題。

#### U95 完成紀錄

- 視線頁：眼睛切動畫／鏡頭／正面／背離／注視，各一步復原；「取鏡頭位置」把注視點設成鏡頭位置並切到注視，畫面與「鏡頭」模式一致（正面與側面鏡頭都試過）；「背離」眼睛往上看。頸部頁：脖子切注視、X 60 時頭轉向那一側，眼睛也跟著；跟隨強度拖曳、Ctrl+Z／Ctrl+Y 正確。存檔讀回眼睛、脖子模式、注視點、跟隨強度都保留。
- 觀察：頭朝前、只用眼睛注視時，注視點偏到眼睛轉不到的角度（X 25～1000，鏡頭距離 40 cm），眼睛停在原處；X 5 時有小幅轉動。眼睛轉動是 Rust 來源 EyeLook（已有專項比對），這批不追。
- 數值欄要先點一下進入輸入模式，控制通道的 `type` 才找得到輸入框。

#### U96 完成紀錄

- 表情頁：眼型下拉選「5 ウィンク左」，畫面眨左眼；眉 ▶ 兩次（眉型 1）、嘴 ▶ 三次（嘴型 2）、「不眨」；張嘴拖曳。手勢頁：左手選「2 剪刀」，畫面上手指成剪刀；「左→右」、「復位」。每一步各一步復原；存檔讀回表情、眨眼、張嘴、兩手手型都保留。
- 發現：0～1、-1～1 這種小範圍的數值欄（權重、跟隨強度、張嘴、睜眼），拖滿整欄只變 0.1 倍範圍（UE `SSpinBox` 小範圍時的內建步長），張嘴拖兩次滿欄才從 -1 到 -0.7。HS2Studio6 這些是拖到哪就是哪的滑桿。列為下一批。

#### U97 完成紀錄

- 角色卡窗：翻頁、點 C003 看大圖、「加入」（放在旁邊、自動選取、一步復原）；點 C004 按「替換所選角色」；兩次 Ctrl+Z 依序還原成 C003、再拿掉。搜尋輸入「C01」按 Enter 篩出 10 張。道具目錄：家具 → ベッド → 點「自室ベッド」加入（放在鏡頭注視點）；搜尋「椅子」按 Enter 列出結果。
- 發現：
  - 「替換所選角色」可否按只在建窗時算一次：加入後選到新角色仍是灰的，復原後沒有選取卻是亮的。改成每幀依目前選取判斷。
  - 道具目錄「左鍵加入，選著道具時替換」：加入道具會自動選到它，所以連點兩個道具，第二個會把第一個換掉。HS2Studio6 點目錄一律新增。改成左鍵一律加入，Shift＋左鍵才替換所選道具（物件屬性頁的換道具清單照舊）。重測連點兩個道具都是新增；Shift 讀的是實體鍵盤，控制通道沒有測 Shift＋左鍵。
  - 角色卡、道具、動作的搜尋要按 Enter 才套用（逐字篩選會重建整個窗，輸入框失去焦點），快搜則是邊打邊篩。提示字加上「Enter」。
- 遊戲與編輯器都連結成功；`verify_ok_studio --tag u94_1102` 6/6。ok-game-mcp `cargo check` 通過，release 建置成功（執行中的 MCP 鎖著 `target/release`，改建到暫存目錄確認）。測試場景與 `_cards` 已刪除。

### U98～U101　第二十批：小範圍數值欄、關節補正、備份與資源檢查、材質編輯器（2026-11-02 列出，2026-11-03 完成，F 組）

對照 `45_joint_fix.png`／`57_joint_fix.png`、`12_backup.png`／`L_42_backup.png`、`13_resource_check.png`／`L_43_resource_check.png`、`20_material_editor.png`／`L_54_material_editor.png`，加上 U96 發現的數值欄問題。

| 項目 | 內容 |
|---|---|
| U98 小範圍數值欄拖到哪就是哪 | 0～1、-1～1 這類範圍的欄位（權重、跟隨強度、張嘴、睜眼、透明度等），拖曳時依欄寬對應整個範圍（HS2Studio6 的滑桿），點一下仍可輸入數字；大範圍的位置、角度照舊是相對拖曳 |
| U99 關節補正頁 | 各部位開關、全部開關；畫面前後對照；存讀與復原 |
| U100 備份與資源檢查 | 自動備份清單、從備份恢復、刪除；資源檢查列出缺少的卡片與 zipmod、定位；照使用者順序走一遍 |
| U101 材質編輯器 | 選道具 → 材質窗：改顏色、貼圖、shader 下拉、還原；復原與存讀 |

完成紀錄（2026-11-03，全部用控制通道的 `mouse` 點擊與拖曳）：

- U98 數值欄：
  - 引擎 `SSpinBox` 把有上下限的範圍攤在欄寬上，範圍 10 以內每像素只走十分之一：「淚」（-1～3）拖滿整欄只變一成。
  - 底部變換列的範圍是 ±100000，結果反過來：拖 40 像素，角色就跑到 X=68000。
  - 新增 `SOKSpinBox`：範圍 10 以內，拖滿整欄就是整個範圍；超過拖曳門檻才放大，所以單擊仍會進入輸入模式。
  - 範圍比 400 個 Delta 還寬的欄位（位置、距離、光照範圍等）不設上下限，改用線性模式（每像素一個 Delta），上下限改在設值時夾住。變換列是每像素 1 cm、1 度、0.01。
  - 實測：
    - 「淚」從 -1 拖滿整欄到 3。
    - 「臉紅」拖七成到 0.35。
    - 單擊「肌膚光澤」進入輸入模式。
    - 位置 X 拖 80 螢幕像素是 +32 cm，縮放 X 拖 40 像素是 +0.32，旋轉往左拖 -32 度。
  - 當時未解：場景有角色時，控制通道模擬的拖曳偶爾整段無效。U103 已找到原因並修好。
- U99 關節補正：
  - 骨骼頁把手肘、膝蓋各彎 110 度，側面近拍膝蓋，按「全部」前後的膝蓋後側與褲管形狀不同。
  - 單一部位開關（251、243）、「全部」開關（255 ↔ 0）、亮燈狀態、Ctrl+Z／Ctrl+Y、存讀都正確。
- U100 備份與資源檢查：
  - 「立即備份」後新備份排在最上面。
  - 刪掉角色再「恢復這份」：先問未存檔，選不儲存後角色回來（補正值 251），場景成為沒有檔名的未存檔場景。
  - 每份備份旁新增「刪除」（先確認，連同縮圖一起刪），刪後清單立即刷新。HS2Studio6 的備份窗沒有刪除，計畫列了這項。
  - 資源檢查：
    - 把角色卡改成不存在的路徑後，清單列出缺卡片與「未顯示」。點那一行會選到角色。
    - 「只看所選」選道具時顯示「沒有缺少的資源」。
    - 卡片路徑改回後按「重新讀取角色」再「重新檢查」，清單回到沒有缺件。
  - 沒有原作卡，沒測到缺 zipmod 的列。
- U101 材質編輯器：
  - `_Color` 選紅色後方塊變紅；shader 下拉選 `main_item_emission`；存讀後兩筆編輯都在。
  - `_Color` 的「預設」、Ctrl+Z／Ctrl+Y、「道具全部重置」都正確。
  - 貼圖：「載入」一張 PNG 後編輯內嵌進場景，「清空」換成 1×1 白圖。
  - 發現材質窗在換 shader 或重置後不會更新，要按「刷新」才看到新的 shader。原因是窗只在選取或部件數改變時重建，而換 shader 會重建道具、部件數不變。改成連預覽 actor 一起比對，重測換 shader、重置都會自動更新。

### U179～U183　第三十六批：角色流程實測的卡手處（2026-11-05，F 組，完成）

用滑鼠走「加角色 → 找動畫 → 套動作」，選中角色後點了 5 次才找到角色選單。

| 項目 | 內容 |
|---|---|
| U179 物件面板直接到角色頁 | 原本只有一行「狀態、骨骼、動畫在『角色』選單」文字，改成「編輯」列：狀態、骨骼、動畫、姿勢庫、語音 |
| U180 時間軸「輸出…」超出視窗 | 第二列放不下，移到第一列 |
| U181 底部狀態文字被變換列蓋住 | 起點從 490 移到 515 |
| U182 動作清單太矮 | 列高加大，清單從 220 高到 325，視窗從 370 高到 560；一頁約 11 列變 18 列 |
| U183 空的姿勢庫沒有說明 | 空清單顯示要怎麼存第一個姿勢；搜尋沒結果時顯示「沒有符合的姿勢」 |

U179～U183 紀錄：

- 另外把姿勢庫的預設位置移到動畫頁右邊，免得蓋住動畫頁。已存的 `ui_layout.json` 優先，本機實測視窗還在舊位置，所以新位置沒有實際看過。
- `check_ok_studio_buttons.lua` 兩項過期：FK 頁後來多了「初始化」列，「復位」的索引要用 2；時間軸按鈕早就叫「清空」。改好後 97/97。
- U177 實看：用 `[Card] March_7th_keiyuu.png`（Koikano 眼睛）拍臉，虹膜、高光、瞳孔都正常。這張卡的 `_rotation1/2` 是 0.5，旋轉角 0，sincos 修正前後結果相同，所以只確認沒有弄壞。
- 驗證：`check_ok_studio_buttons.lua` 97/97，`verify_ok_studio.lua --tag u179_1105` 六項全 PASS。

### U178　使用者要求：角色風格滑桿（2026-11-05，F 組，完成）

| 項目 | 內容 |
|---|---|
| U178 Q 版／寫實切換 | 狀態窗最上方的「風格」：滑桿 -1 寫實、0 照卡片、1 Q 版，另有三個一鍵按鈕。不重建角色，動畫播放中也能即時切換 |

- 做法：`FOKSceneCharacter::Style` 存進場景，`OKStudioStyleSliders` 把卡片的滑桿往風格目標值拉（最多 75%，保留卡片的個性），再走捏人滑桿的 `MarkShapeDirty`。
- Q 版：身高降、頭變大、胸變小、臉與下巴變寬變圓、眼睛變大、鼻子變小、嘴變窄。身高與頭用超出 0～1 的值（`shape.rs get_info` 照 SliderUnlocker 外插）。身高靠 `cf_n_height` 整體縮放，所以腳留在地上，動畫也跟著縮。
- 寫實：身高增、頭變小、臉變窄、下巴變長、眼睛變小、鼻子變高，胸部照卡片。只改形狀，沒有改材質或光影。
- 時間軸：關鍵影格會存風格，兩個影格之間漸變。`FOKSceneKey::Style` 低於 -1 表示沒存，舊場景不受影響。
- AI 操作：`studio_patch` 的 `{"character":{"style":1}}`。
- 驗證：女角、男角各拍 -1、0、0.5、1；存讀場景後風格還在；動作 `0/7/20/2` 播放中切換 0、1、-1、1，腳都在地上；`OpenKoikatsu.Studio.CharacterStyle` 通過。
- 時間軸實測：0 秒風格 0、4 秒風格 1，停在 0、1、2、3、4 秒時風格是 0、0.25、0.5、0.75、1，頭高 127.3、117.9、108.5、99.1、89.7 cm；實際播放時 1.1 秒 114.0、2.6 秒 102.0、4.1 秒以後 89.7 cm。
- `studio_bounds` 修正：角色的框改成目前畫出的部件。原本包進骨架線段（比模型高 23 cm、低到地面下 14 cm），GPU 畫的部件又用只增不減的裁切框。修好後胡桃 T 姿勢 156 → Q 版 119 cm，動畫中 Q 版 118.8、原樣 154.9、再回 Q 版 118.8 cm，底部約 0。裁切框本身沒改，`UKKAffineProceduralMeshComponent::CurrentWorldBounds` 另外記最新一次的框。

### U174～U177　第三十五批：U173 留下的問題（2026-11-04 列出，F 組，U174、U175、U177 完成，U176 部分完成）

| 項目 | 內容 |
|---|---|
| U174 灯台夜晚的海偏亮偏藍 | 原作 `(53,81,116)`，OK `(73,106,169)`。夜晚 `_DeepFoamColor` 的 alpha 0.92，泡沫項可能太強，對照 `_water` 燈 1.0 的組成 |
| U175 海面波紋太細碎 | 遠處像雜訊，原作平滑、紋路大。查 `_BumpTiling` 換算與遠處的 mip；地圖 50 白天原作泡沫偏白（R 223，OK 149） |
| U176 樹的藍色偏高、地圖 50 地面略亮 | 灯台昼樹 B 64 → 98；地圖 50 草地、沙地各時段都略亮，夜晚沙地 `(159,171,141)` → `(192,189,148)`。一併查 UE 順向著色下多盞平行光實際生效幾盞 |
| U177 `KoikanoEyeProgram.inl` 的 sincos | U170 修好 `shader_program_codegen.lua` 的別名錯誤，這個檔有同樣的寫法（`r6.x=cos(r3.x)`）還沒重新產生，重產後要看眼睛畫面 |

### U169～U172　第三十四批：U164～U168 留下的問題（2026-11-03 列出，F 組，U171、U172 完成，U169、U170 部分完成）

| 項目 | 內容 |
|---|---|
| U169 海面亮度對照原作 | U166 之後灯台海面會跟著時段變，但白天藍色到頂（255）、夜晚比夜空亮。拍原作灯台四個時段的海面，對照 `_OKAmbient`（目前固定 0.2）與反射（`_Reflection` 是黑的、`_BumpMap` 沒讀到，用的是預設法線）該從哪裡來 |
| U170 天空 pattern 對照原作截圖 | U167 只確認 14 個 pattern 顏色互不相同、合乎資料，沒有原作截圖。在原作 Studio 逐一拍 1004～1013，對照雲、星星、日月位置 |
| U171 新角色站進課桌 | U168 教室加第三個角色（Male01）時，找空位把他放在兩排課桌之間，身體和桌子重疊。U146 的找空位要把課桌、椅子這類低家具也當成障礙 |
| U172 UI 截圖縮放不一 | U168 中途 `studio_ui_shot` 有幾張是 1136×625、有幾張是 1600×900，滑鼠座標要跟著換算。查截圖尺寸為什麼會變（視窗大小或 DPI），讓截圖固定用視窗的實際像素 |

U174～U177 紀錄（2026-11-05，關掉濾鏡的畫面，原作 → OK）：

- U174 海面的 `_water` 燈：照燈的高度計算（`-forward.y / 0.6`，0.6 是灯台白天的高度）。灯台夜晚的燈低，藍色降下來；地圖 50 的燈高，泡沫變亮。
  - 灯台夜 `(53,81,116)` → `(73,90,131)`，原本 `(73,106,169)`。
- U175 波紋：`_BumpTiling` 的第一層是 100 m 一個週期，OK 多乘了 2，改回來；Lux 的法線到 300 m 消失（`_FarBumpSampleParams`），遠處改用平均泡沫，不再是雜訊。泡沫遮罩係數是對照畫面調的。
  - 灯台昼 `(62,129,168)` → `(76,134,177)`，夕 `(166,146,82)` → `(169,145,69)`。
  - 地圖 50 昼 `(223,255,255)` → `(191,255,255)`，夕 `(255,209,118)` → `(255,203,140)`，夜 `(85,100,118)` → `(90,94,135)`。
  - 還沒解決：原作的亮斑是 caustics 與泡沫貼圖，OK 只用法線湊，紋路不同。
- U176 環境光：原作這兩張地圖是 Trilight，`SunLightInfo` 每個時段都設天空、赤道、地面三色，OK 三個時段用同一組。`sky.json` 新增 `ambient_equator`、`ambient_ground`，`OKStudioMapTimeTrilight` 依時段換算成 `unity_SHA*`，只用在 Trilight 地圖。探針新增的赤道色和紀錄一致（`0.74492997`）。
  - 環境光現在會隨時段變化，但顏色誤差沒有全部變小：灯台樹夕 `(142,157,66)` → `(136,147,64)` 更接近，昼 `(94,127,64)` → `(104,143,102)` 比之前亮；岩石夕 `(142,131,101)` → `(157,146,117)` 也變亮。
  - 還沒解決：樹的藍色偏高、地圖 50 的草地與沙地各時段略亮，原因不是環境光。`RenderSettings.ambientProbe` 在探針裡讀到 0，無法直接對照係數。
- U177：`generate_runtime_koikano_eye.lua` 重新產生 `KoikanoEyeProgram.inl`，只有 sin、cos 兩行對調。掃過其他 shader 程式，沒有同樣的寫法。`EyeSetTest` 通過，但沒有用 Koikano 眼睛的卡實際看過畫面。
- 要讓別的 checkout 得到環境光：`ok-extract <遊戲> --oklib studio-sky <base_v1>`。
- 驗證：`verify_ok_studio.lua --tag u174_1105` 六項全 PASS。

U173 紀錄（2026-11-04，地圖 50、灯台對照原作；下列顏色都是關掉濾鏡的畫面，原作 → OK，原作截圖只留在 `Saved/Tests/`）：

- 海面：用原作材質與燈光資料重列 Lux Water 的組成。
  - `Directional Light_water` 只照水面（遮罩 16），白天 3.5，新增 `_OKWaterLight`；深水泡沫 `_DeepFoamColor` 新增 `_OKDeepFoam`。泡沫遮罩是用法線湊的，不是原作的泡沫貼圖。
  - 天空控制器的 `Sun/Light`、`Moon/Light` 遮罩也是 16，只照水面。灯台傍晚的棕色就來自這裡。`sky.json` 新增 `_OKSunLightColor` 等欄位，`OKStudioSkyLight` 只取該 pattern 有畫的太陽或月亮，新增 `_OKSkyLight`。
  - 灯台：昼 `(62,129,168)` → `(79,139,181)`、夕 `(166,146,82)` → `(166,144,68)`、夜 `(53,81,116)` → `(73,106,169)`。夜晚偏亮偏藍。
  - 地圖 50：昼 `(223,255,255)` → `(149,241,255)`、夕 `(255,209,118)` → `(246,191,140)`、夜 `(85,100,118)` → `(90,94,135)`。
  - 還沒解決：波紋比原作細碎，沒有原作的泡沫與岸邊淺水。
- 地圖 50 地面：同一個 Plane 網格只留一個材質，草地和沙地畫成同一種灰。新增 `prefab_standard_materials`（`studio-nodes` 記錄），每個節點拿回自己的 Standard 材質；支援 `_DETAIL_MULX2`（`_DetailAlbedoMap`，乘 4.59479）；沒有主貼圖的 Standard 部件改用白色，不再落到引擎預設材質。
- 樹：Nature/SpeedTree 走 gamma 路徑過曝，改走線性 Lambert，也吃 `_Color`。灯台夕 `(142,157,66)` → `(126,140,63)`。樹的藍色還是偏高（昼 B 64 → 98）。
- 岩石：`Koikano/main_item_map` 在 OK 沒有對應程式，不受光，三個時段同一色。改當 Standard（光滑度 0）打光，昼 `(139,139,115)` → `(156,154,129)`、夕 `(142,131,101)` → `(147,141,114)`、夜 `(82,104,102)` → `(109,125,114)`，略亮。這是近似，不是原作的 toon。
- 帶 cookie 的平行光：OK 沒有 cookie，整張地圖都會吃到。新增 `prefab_light_cookies` 記錄，這種燈不建立。目前只有一盞，地圖 50 夜晚沙地 `(159,171,141)` 從 `(255,251,196)` 降到 `(192,189,148)`，還是偏亮。
- 探針：`StudioMapTour.cs` 多記燈的遮罩、烘焙模式、`pixelLightCount` 與 renderer 圖層。
- 要讓別的 checkout 得到這些，依序跑 `ok-extract <遊戲> --oklib studio-sky <base_v1>`、`--oklib studio-nodes <base_v1> 8`、`--oklib studio-standard-textures <base_v1>`。沒跑的基礎庫維持舊畫面，不會出錯。
- 屋頂：地圖 50 六個視角都拍不到建築，U169 說的「屋頂」應該就是從上方看到的 Plane（草地與沙地），這部分已和原作一致。若另有真正的屋頂，要換視角再拍。

U170 星星紀錄（2026-11-04，同一批對照）：

- 不是 8 位元精度：原作的 `StarData` 本來就是 RGBA32。真正原因有三個：
  - `StarData` 的列由南到北存放，是查表用的資料；OK 當成影像做了 V 翻轉，查到的星星全部不對。
  - `shader_program_codegen.lua` 把 `sincos r0.x, r1.x, r0.x` 譯成先寫 sin 再算 cos，cos 吃到 sin 的結果，星星只出現在天空一小塊。
  - `sky.json` 沒有套用 profile 的星星數值（大小、閃爍、旋轉、邊緣、亮度），星星偏大。月亮亮度同時補上。
- 結果：灯台夜晚的星星大小與密度接近原作，原作的紅色星星比 OK 多。地圖 60 的漸層重拍後與原作一致。
- 別的 checkout 要跑 `ok-extract <遊戲> --oklib studio-sky <base_v1>` 才會拿到星星數值。
- `_nopost` 現在真的關掉 Amplify Color，`run_map_tour.lua` 另外寫 `.materials.tsv`（每個 renderer 的材質、lightmap 與屬性）。

U169、U170 紀錄（2026-11-04，用原作 Studio 實拍對照，原作截圖只留在 `Saved/Tests/`）：

- 工具：`Tools/GamePoseProbe/run_map_tour.lua` 讓原作 Studio 依 `地圖:時段` 自動換地圖、拍固定視角，並錄執行時的天空、燈光與水面材質。OK 的 FOV 是水平，原作垂直 60 等於 OK 的 91.5。
- U170 天空：
  - 看起來全部偏淡的主因是 OK 新場景沒有濾鏡。原作新場景是濾鏡 0（`Lut_Amount`）全強度，改成預設 0 後，雲、顏色、太陽、月亮的位置都和原作一致（地圖 50 朝 `(20,107,243)` 對 OK `(20,110,253)`）。
  - `_GradientFadeEnd`：天空控制器把它夾到 1（profile 是 1.5），OK 跟著夾。
  - 還沒解決：星星沒畫出來（`StarData` 只有 8 位元 PNG，疑似精度不足，未確認）。
- U169 海面：
  - 問題的來源：灯台四個時段的海是同一個網格，轉換只留下一個材質（夜晚），所以四個時段都是夜晚的水色與沒有法線。新增 `prefab_water_materials`（`studio-nodes` 記錄），每個節點拿回自己的 Lux Water 材質與 `_BumpMap`。
  - `_OKAmbient`：改用該時段的 `SunLightInfo.ambientSkyColor`（`sky.json` 的 `ambient`），舊的 `sky.json` 沒有這欄時維持 0.2。
  - `_Reflection`：原作 `_LuxWater_ReflectionTex` 是 null，海面不反射天空；試過加天空反射，畫面反而偏離，已拿掉。
  - 水色改用 `_Color`，傍晚的棕色來自 `_TranslucencyIntensity`（傍晚 5.78、白天 0.04）。
  - 目前地平線下的海面（原作 → OK）：昼 `(29,129,199)` → `(0,35,166)`、夕 `(149,101,17)` → `(111,121,23)`、夜 `(0,1,87)` → `(0,6,89)`。夜晚接近；白天偏暗、綠色不足，傍晚偏綠。這是用係數湊近的近似，不是 Lux Water 的完整光照，也沒有原作的泡沫與岸邊淺水。
- 要讓別的 checkout 得到這些：`ok-extract <遊戲> --oklib studio-sky <base_v1>` 與 `--oklib studio-nodes <base_v1>`。沒跑的基礎庫維持舊的海面，不會出錯。
- 另外看到、未處理：灯台的樹在 OK 偏黃、岩石偏暗；地圖 50 的海與屋頂顏色也和原作不同。

U171、U172 完成紀錄（2026-11-04，控制通道實測）：

- U171 新角色站進課桌：
  - 重現：教室 2-1 連加 C050 兩次、Male01 一次，三人都站在課桌與下一排椅子之間 56 cm 的窄縫（Male01 在 y = -37）。
  - 原因：課桌、椅子本來就算障礙（`studio_bounds` 加 `map` 看到的 71 個家具框都有），但身體框只有 ±22 cm，窄縫剛好放得下。
  - 改成新角色與家具留 ±35 cm；整張地圖都沒有這麼寬的空位時才退回 ±22 cm。換地圖的 `SettleCharactersOnMap` 仍用 ±22 cm，不搬動本來沒撞到的角色。
  - 重測：同樣三個角色都站到課桌之間的走道，Male01 在 x = -230。
- U172 UI 截圖尺寸不一：
  - 截圖一直是視窗實際像素，變的是視窗本身。啟動參數都是 1600×900，尺寸在執行途中也會變。
  - 成因（11-04 U169 測試時撞見）：執行中系統 DPI 改變，Windows 依比例縮放視窗。同一個 Studio 從 1600×900（`dpi_scale` 1.25）變成 2247×1279（1.75），比例 1.40；反向 1.25／1.75 ＝ 0.71，就是 1136／1600。先前寫的「啟動時工作區較小」是錯的。
  - `ui_shot` 改成回傳 `width`、`height`、`dpi_scale`，`studio_mouse` 用同一組座標，不必換算。

### U164～U168　第三十三批：U159～U163 實測找到的問題（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U164 輸出窗「到」欄位找不到 | U163 用控制通道 `type {field:"1.0"}` 改輸出窗的「到」欄位，回「0 fields match」，只好照預設輸出 1 秒。查輸出窗的數字欄位為什麼不能用目前文字比對（可能顯示成「1」或用 SpinBox），讓 AI 也能改輸出範圍 |
| U165 另存的檔名用建立時間 | U163 在 16:16 另存，檔名是 `scene_20261103_161038.png`（新場景的時間）。同一場景另存兩次會蓋掉前一份；改用另存當下的時間，或另存時讓使用者確認檔名 |
| U166 灯台海面四個時段同色 | U154 提到的海面顏色沒處理：StylizedWater 的顏色不跟時段變。查原作 Lux Water／海面材質在夕、夜的值，跟著時段換 |
| U167 天空 pattern 1011～1013 實景 | U159 只拍了灯台的夕、夜。到 Studio 的天空設定逐一選 1011～1013 與其他 pattern，對照原作截圖，確認 profile 值套用後顏色、雲、星星正確 |
| U168 第八輪整段實測：教室 | 用滑鼠做：教室地圖、時段「夕」、三個角色、一個道具、相機兩個 key、mp4（含音樂）、另存兩次、重開。繼續觀察 U155 的 mp4 當掉 |

U164～U168 完成紀錄（2026-11-03，控制通道實測）：

- U164 輸出窗的數字欄：
  - 原因：輸出窗的「從」「到」是 spin box，它的文字欄只在打字時才顯示，平常是隱藏的，控制通道的 `type` 走訪時跳過了。
  - `OKStudioControl.cpp` 的 `type` 改成也找 spin box：
    - 用它的數值比對（照輸入的寫法，或照畫面上的一位小數）。
    - 或用同一列左邊的標籤比對（「到」「位置」），一列有多個就用 `index` 選。
    - 找到後以直接設定焦點的方式進入打字模式，再照鍵盤輸入，Enter 提交。
  - 實測：
    - `{field:"到", text:"2.5"}`、`{field:"從", text:"0.5"}` 後輸出 mp4，得到 60 幀（2 秒）。
    - `{field:"位置", index:0}` 改相機的 X。
- U165 另存的檔名：
  - 新場景不再先定好檔名，儲存窗開啟時才用當下的時間；「另存新檔」每次都用新的時間名稱。
  - 名稱欄是空的時候（儲存窗開著時開了新場景），按儲存也用當下的時間。
  - 實測：連續另存兩次得到兩個檔（16:55:58、16:56:06），新場景在 16:56:48 開儲存窗，檔名就是 16:56:48。
- U166 海面跟著時段：
  - 原因：水面材質的光照方向是 StylizedWater 原 mod 的「跟著相機的燈」，程式裡 `L` 是相機前方。從上往下看海時，漫射是 0，只剩固定的環境光，所以四個時段一樣。
  - 水面材質新增 `_OKLightDir`（Unity 空間，朝向光源，w = 1 時使用）。OK Studio 套用地圖時段時，給地圖的水面：
    - `_LightColor0`：太陽顏色乘強度。
    - `_OKLightDir`：太陽方向。
  - 第一次照「朝向光源」直接給 `L`，畫面仍不變，因為程式的 `L` 是光的行進方向。改成取反後就正確了。
  - 實測灯台海面的平均色（地平線附近）：
    - 朝 (120,206,255)
    - 昼 (137,234,255)
    - 夕 (97,161,213)
    - 夜 (72,154,240)
  - 白天的藍色到頂、夜晚比夜空亮，列入 U169 對照原作。
- U167 天空 pattern：
  - 0～3、1004～1013 共 14 個 pattern 都畫出各自的顏色：
    - 朝：白藍。
    - 昼：淺藍。
    - 夕：橘色（1005 是 U159 修好的）。
    - 夜：深藍。
    - 1010：藍紫。
    - 1012：粉褐。
    - 1013：灰藍。
  - 1011（daytime-simple）在地平線是白色、往上是藍色，和資料一致（下段白色、中段在頂端）。
  - 沒有原作截圖，列入 U170。
- U168 第八輪整段實測（教室）：
  - 全程用滑鼠：
    - 新場景 → 地圖窗讀「5 教室2-1」。原點有課桌，視角移到旁邊的空地（U156 的提示）。
    - 設定 →「夕」，教室變成夕陽色。
    - 加 C050 兩次、Male01 一次，三人分開站。
    - 道具目錄加一個方塊。
    - 從視角加相機 1。
    - 0 秒與 5.07 秒各打一個 key，X 用 U164 的 `type` 改成 -200。
    - BGM 選「17 部室」播放。
    - 開著時間軸窗輸出整段 mp4：300 幀，影像與聲音各 10 秒，沒有當掉。
  - 存檔：
    - 開啟／儲存的名稱是開窗時間（17:04:52），存檔。
    - 再「另存新檔」得到新名稱（17:05:27），另存。
    - 兩個檔都在。
  - 讀回第二個：
    - 地圖 5、`sunType` 2（夕）、BGM 17 都還原。
    - 三個角色、方塊、相機 1 與兩個 key 也都在，播放頭在 5.07 秒。
  - 找到的問題列入 U171（新角色站進課桌）、U172（UI 截圖尺寸不一）。
- 驗證：
  - `cargo check -j 8` 與 `--no-default-features` 都通過。
  - 遊戲 OpenKoikatsu Development 與編輯器都建置、連結成功（`MSBUILDDISABLENODEREUSE=1`、`CARGO_BUILD_JOBS=8`、`RAYON_NUM_THREADS=8`）。
  - `verify_ok_studio.lua --tag u164_1103` 六項全 PASS。

### U159～U163　第三十二批：U154～U158 留下的問題（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U159 夕、夜天空的顏色（基礎庫） | U154 補上貼圖後，夕（pattern 1005）與夜（1006）的天空畫出來了，但顏色和白天一樣。原因：這兩個 pattern 的天空材質在別的 bundle，`studio_sky.rs` 只讀到 shader 的預設值（`_GradientSkyUpperColor` 等），貼圖表也是空的；1011～1013 同樣。Funly 的 controller 在執行時從 SkyProfile 的關鍵影格算出材質值。匯出改成讀 SkyProfile 的值（或解析材質所在的 bundle），重新產生 `studio/sky.json`（基礎庫檔案，需協調提交） |
| U160 灯台空中的黑色圓盤 | 從正上方看，灯台草地上空有一個黑色圓盤，地面有它的影子；藏掉草地、岩石等附近的部件後仍在。逐段藏部件找出是哪個物件、材質為什麼是黑的 |
| U161 灯台岩石的條紋貼圖 | U157 未做：岩石有拉長的條紋。查岩石部件的 UV（可能和 U149 一樣讀錯通道）與貼圖 |
| U162 夜晚亮度的實景對照 | U159 修好後，再拍灯台四個時段，對照原作的地圖燈光（夜晚只有灯塔燈光變化，整體亮度幾乎不變） |
| U163 第七輪整段實測：水族館 | 用滑鼠做：水族館（57）、時段「夜」、兩個角色、相機兩個 key、mp4（含音樂）、存檔重開。一併觀察 U155 的 mp4 輸出當掉是否再出現 |

U159～U163 完成紀錄（2026-11-03，控制通道實測）：

- U159 夕、夜天空的顏色：
  - 原因：pattern 1005、1006、1011～1013 的天空材質存的是 shader 預設值。Funly 的 controller 在執行時把 SkyProfile 的關鍵影格（`keyframeGroups` 的數值、顏色、貼圖、球面點）寫進材質。
  - `studio_sky.rs` 新增 `profile_values`，讀各 group 第一個關鍵影格（KKS 的 profile 都只有一個）。再用 `apply_profile` 寫進材質已有的屬性：
    - 天空三段顏色、雲、霧、日月、星星的顏色。
    - 漸層與星星的起點；終點 = 起點 + 長度。
    - 雲的密度、速度、方向、高度與淡出。
    - 日月的大小與邊緣。
    - 日月位置：球面點轉成方向 (cos v·cos h, sin v, cos v·sin h)。
  - 材質沒有的貼圖（雲雜訊、月亮、太陽）從 profile 補上。
  - 對照表是拿材質已有烘焙值的 pattern，逐一比對 profile 值與材質值得來的。controller 會換算的值（霧密度、HDR 強度、星星指數）不改，保留材質的。
  - 重產本機 `studio/sky.json`（14 個 pattern）。實測：灯台的夕是橘色天空，夜是深藍天空。
  - **整合注意**：`studio/sky.json` 是基礎庫檔案，本次不提交。C／E 整合後要重產：`RAYON_NUM_THREADS=8 ok-extract <遊戲> --oklib studio-sky <base_v1>`，提交需協調。
- U160 灯台空中的黑色圓盤：
  - 逐段藏部件，找到是 `SkySystemController` 根物件下的一個網格。它是 Funly 編輯用的示意物件，材質是 WorldGrid，原作執行時不畫。
  - `OKSceneActor.cpp` 讀地圖根物件時，把 `SkySystemController` 底下的網格隱藏並關掉投影，燈光保留。
  - 實測：黑色圓盤和它在草地上的影子都不見了。
- U161 灯台岩石的條紋：
  - 條紋只在從海面下看得到的懸崖底面，是原作 UV 本來就拉長，正常視角看不到。不改。
- U162 夜晚亮度：
  - 灯台夜晚的太陽光照地圖的 SunLightInfo：強度 1.0（白天 1.6），顏色偏藍。所以夜晚本來就不太暗，照資料來。不改。
- U163 第七輪整段實測（水族館）：
  - 全程用滑鼠：
    - 新場景 → 地圖窗搜尋（打字即時過濾）→ 讀 57 → 設定 →「夜」。狀態列：「時段：夜（太陽仰角90°、顏色#C7E7FF）」。
    - 加 C050、Male01，面向對方。
    - 從視角加相機 1，0 秒與 5.07 秒各打一個 key。
    - 選 BGM 13 播放。
    - 開著時間軸窗輸出 mp4（1920×1080、含聲音）：沒有當掉，ffprobe 有影像與聲音軌。
  - 系統選單 → 開啟／儲存 → 另存，再讀回：
    - 地圖 57、`sunType` 3（夜）、BGM 13 都還原。
    - 相機兩個 key 都還原；播放頭停在 5.07 秒（存檔時的位置）。
  - 找到的問題列入 U164（輸出窗的「到」欄位控制通道找不到）、U165（另存檔名用建立時間）。
- 驗證：
  - `cargo check -j 8` 與 `--no-default-features` 通過；`studio_sky_patterns_convert`（ignored）通過。
  - 遊戲 Development 與編輯器都建置成功，`CARGO_BUILD_JOBS=8`、`RAYON_NUM_THREADS=8`。
  - `verify_ok_studio.lua --tag u159_1103` 六項全 PASS。

### U154～U158　第三十一批：U149～U153 實測找到的問題（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U154 時段「夕」天空變黑、夜晚不暗 | U152 在灯台拍朝、昼、夕、夜四張：整體亮度幾乎一樣，夜只多了灯塔的燈光；切到「夕」後天空變成黑色（存檔重開後仍是黑的）；海面顏色四個時段都一樣。查時段切換時天空、環境光與海面該跟著換的值 |
| U155 輸出 mp4 時 Studio 當掉 | U153 第一次輸出 mp4（灯台、兩個角色、相機兩個 key、播著 BGM、時間軸窗開著）到第 9 幀時當掉：Slate 斷言 `RenderBatch.NumIndices > 0`（`SlateRHIRenderingPolicy.cpp:1384`）。之後同樣的條件輸出 1 秒、10 秒與輸出中截 UI 都沒有重現。查哪個自繪元件可能送出沒有索引的批次（`MakeLines` 的點、零尺寸的框），補上防護 |
| U156 灯台初始視角被烏鴉擋住 | 讀灯台後的初始視角正對地圖原點的大烏鴉道具，畫面一半是烏鴉的臉；新加的角色也站進烏鴉裡。初始視角避開它，U146 的落地與找空位也要把它當成障礙 |
| U157 灯台的黑色斑塊與岩石條紋 | 植物修好後，灯台草地上還有幾塊黑色的面，岩石有拉長的條紋貼圖。查這些部件的材質與 UV |
| U158 小操作問題 | 地圖窗的搜尋要按 Enter 才過濾，改成打字就過濾（角色卡窗是按 Enter，說明裡寫明）；讀檔後時間軸的播放頭停在結尾（9.97 秒），改回 0 |

U154～U158 完成紀錄（2026-11-03，控制通道實測）：

- U154 時段的天空：
  - 夕、夜的天空是黑的：記錄寫「sky 1005 not shown: texture _CloudNoiseTexture missing」（夜是 `_MoonTex`）。
  - 基礎庫 `studio/sky.json` 有 5 個 pattern（1005、1006、1011～1013）的貼圖表是空的。
  - `OKStudioSky.cpp` 改成：pattern 缺的貼圖，用目錄裡別的 pattern 同名的貼圖。KKS 的天空共用同一張雲雜訊與月亮。
  - 實測：四個時段的天空都畫出來了。但夕、夜的天空顏色和白天一樣，基礎庫裡就是 shader 的預設值，改列 U159（匯出端，需重產基礎庫檔案）。
- U155 輸出 mp4 時當掉：
  - 沒能重現。引擎的抗鋸齒線段建構會跳過長度 0 的線段；所有點都重合（或不是有限值）時，產生沒有索引的批次，正好觸發這個斷言。
  - 我們的抗鋸齒線有幾處可能如此：
    - 視窗疊加層的輔助線：相機移動時投影點可能重合或成 NaN。
    - 圖示：元件尺寸為 0 時所有點重合。
    - 時間軸播放頭與色相條：高度或寬度為 0 時。
  - 新增 `OKStudioStyle::DrawableLine`：點數不足、有非有限值或總長為 0 的線不畫。上述各處都改用它或加尺寸檢查。
  - U163 再觀察。
- U156 灯台的烏鴉：
  - 烏鴉（Part_77，約 1.1 m 高）正站在地圖原點，Studio 放角色和初始視角都看那裡。
  - 新增 `FrameMapStart`：讀地圖時場景還沒有角色、原點被家具佔住，焦點就移到最近的空地（新角色也從那裡開始找位置）。再從視線不穿過家具的方向看。
  - 實測：
    - 灯台讀進來後焦點移到 (0, 80, 90)，在烏鴉前面。
    - 狀態列寫「原點有地圖物件，視角移到旁邊的空地」。
- U157 黑色斑塊與岩石條紋：
  - 從正上方找到一個懸在草地上空的黑色圓盤（地面有影子）。藏掉附近的草地、岩石部件後仍在，還沒找到是哪個物件。
  - 改列 U160（黑色圓盤）、U161（岩石條紋）。
- U158 小操作：
  - 地圖窗的每張地圖都建好列，搜尋打字就即時隱藏不符的列（比對編號與名稱），不重建視窗，輸入不會失去焦點。
  - 播放頭停在結尾：讀檔是照存檔還原播放頭，問題在輸出影片後播放頭停在最後一幀，存檔就記下來了。改成輸出完成、取消或失敗後，播放頭回到輸出前的位置。
  - 實測：
    - 打「灯台」不按 Enter 就只剩「56 灯台」。
    - 播放頭在 2.5 秒時輸出 1 秒 mp4，完成後仍在 2.5 秒。
- 驗證：
  - 遊戲 Development 與編輯器都建置成功；建置時設 `CARGO_BUILD_JOBS=8`、`RAYON_NUM_THREADS=8`。
  - `verify_ok_studio.lua --tag u154_1103` 六項全 PASS。
  - 這批沒有改 Rust。

### U149～U153　第三十批：U143 修好後 KKS 地圖剩下的問題（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U149 KKS 植物只畫一級 LOD、貼圖正確 | 灯台、地圖 50 的植物（`toon_*`）LOD0～LOD2 全部疊在一起畫（Unity 的 LODGroup 只畫一級），而且有的植物是灰色沒貼圖、有的是拉長的條紋貼圖。讀 LODGroup 只畫該畫的那一級，再查植物的 UV 與貼圖 |
| U150 灯台的海面像法線貼圖 | 灯台的海面是藍紫色的法線貼圖花紋。查海面的材質（水面 shader）讀錯了哪張貼圖 |
| U151 重錄的基礎庫與 OK 卡要提交（需協調） | U143 用 `OKLIB_REFRESH` 在本機 base_v1 重錄了 89 個來源（遊戲 80、mod 9），沒有提交（base_v1 不是 F 組提交的檔案）。要由負責基礎庫的人提交，並照規定在乾淨 clone 跑 `kks-verify` 與 `okcard-check`。另外，用到那 34 個受影響飾品（`abdata/chara/ao_*` 等）的 OK 卡，卡內的資源包也是舊的解碼結果，要重轉 |
| U152 時段光照的實景對照（U144 再延） | 等 U149、U150 修好後，在灯台拍朝、昼、夕、夜四張，對照太陽方向與色溫 |
| U153 第六輪整段實測：KKS 戶外地圖 | 用滑鼠做：灯台、時段「夕」、兩個角色面對面（U145）、相機兩個 key、輸出 mp4（含音樂）、存檔重開。記下點擊次數與卡手處 |

U149～U153 完成紀錄（2026-11-03，控制通道實測）：

- U149 KKS 植物：
  - LOD：
    - Unity 的 LODGroup 一次只畫一級，原本 LOD0～LOD2 全畫，疊成三層。
    - `okmodel_view.rs` 取地圖部件時，同名 `<名稱>_LOD0` 在 prefab 裡時，丟掉 LOD1 以上的部件。讀取時處理，不必重錄。
  - UV：
    - 植物是 SpeedTree 網格（shader `Nature/SpeedTree`），TexCoord0 是 float4（前兩個分量是 UV，後面是其他資料）。
    - 原本只看 2 維的通道，讀成了風力與 LOD 資料的通道，貼圖拉成條紋或變灰。
    - `mesh_decode.rs` 的 `decode_uvs` 改成：14 通道佈局中 TexCoord0 是寬通道時，直接用它的前兩個分量。
    - 中途兩版規則誤傷了別的網格：舊版 8 通道佈局的切線、Studio 鞦韆的 UV0。經過全庫掃描與抽查後收窄成現在這條，見 ERROR_LOG。
  - 樹葉卡片：
    - SpeedTree shader 會在 `_Cutoff` 裁掉樹葉卡片的透明處。原本畫成不透明，透明處成了白色、深色的大片。
    - `okmodel_view.rs` 給 `Nature/SpeedTree` 材質加上 `_ALPHATEST_ON`，走 masked。
  - 掃描與基礎庫：
    - 掃描測試 `sources_with_changed_main_uv` 新增 `OK_UV_SCAN_RULE=wide`。
    - 遊戲 22017 個來源中 21 個有變（`abdata/studio/map` 19、`abdata/studio` 2），全是 `toon_*` 植物，沒有角色部件。
    - 本機以 `OKLIB_REFRESH` 重錄（用的是中途一版掃描的 30 個來源，包含這 21 個；另外 9 個 mod 來源在最終規則下沒有變）。沒有提交（U151）。
  - 實測：灯台的樹、棕櫚、花、草都有正確的貼圖，樹葉卡片的透明處不再畫出來，也不再疊三層。
- U149 整合時的基礎庫重錄（C、E 都要做）：
  - 清單：[`Tools/oklib_rerecord/u149_wide_uv.txt`](../Tools/oklib_rerecord/u149_wide_uv.txt)（21 個，全是遊戲本體，各環境相同，不必重掃）。
  - 指令和 U143 一樣，把清單換成這個檔：

    ```powershell
    # ok 系列的程式（含 cargo 與它們跑的工作）最多 8 個執行緒
    $env:RAYON_NUM_THREADS='8'
    cargo build -j 8 --release --manifest-path Tools\ok-extract\Cargo.toml
    $env:OKLIB_REFRESH='meshes_for_maindata,meshes_for_maindata_including_disabled,decode_all,base_bundle'
    .\Tools\ok-extract\target\release\ok-extract.exe <遊戲目錄> --oklib convert Content\IndependentResources\base_v1 8 "@$PWD\Tools\oklib_rerecord\u149_wide_uv.txt"
    ```

  - 要對 mods 也確認時，照 U143 的做法跑掃描，環境變數換成 `OK_UV_SCAN_RULE=wide`、`OK_UV_SCAN_OUT`，測試名換成 `sources_with_changed_main_uv`（約 45 分鐘）。
- U150 灯台的海面：
  - 海面的 shader 是 `Lux Water/WaterSurface`，UE 端沒有對應，畫成了它的法線貼圖。
  - `KKPreviewActor.cpp` 讓它沿用 StylizedWater 的圖：
    - `_TranslucencyColor` 當水色，`_UnderWaterReflCol` 當 fresnel 色，`_FoamColor` 當岸邊色。
    - `_BumpMap` 當法線，`_BumpTiling` 決定每公尺的重複次數，`_DepthAtten` 當深度。
  - 實測：海面是藍色、有波紋的水面，記錄寫 `lux=1`。
- U151 基礎庫提交（需協調）：U143 的 89 個與 U149 的 21 個來源都只在 F 本機重錄，等負責基礎庫的人提交，並在乾淨 clone 跑 `kks-verify` 與 `okcard-check`。U149 只動 Studio 地圖，沒有 OK 卡要重轉。
- U152 時段光照的實景對照：
  - 灯台四個時段（狀態列寫明太陽仰角與顏色）都能切換。
  - 但整體亮度幾乎一樣，夜只多了灯塔的燈光；「夕」的天空變成黑色。列為 U154。
- U153 第六輪整段實測（灯台）：
  - 用滑鼠完成：
    - 新場景、地圖窗搜尋「灯台」並讀取、「設定」裡的時段選「夕」。
    - 加 C050 與 Male01，各選一次再按「面向對方」。
    - 從目前視角加相機，在 0 秒與 5 秒各打一個 key。
    - 背景音樂選「02 マップ夕方」播放，輸出 mp4，另存新檔，再讀回來。
  - 大約 30 次點擊。
  - 結果：
    - 讀回後地圖、時段「夕」、相機的兩個 key 都在。
    - mp4 有影像與音軌。
  - 卡手處：
    - 第一次輸出到第 9 幀時 Studio 當掉，之後重現不出來（U155）。
    - 初始視角被烏鴉擋住，C050 站進烏鴉裡（U156）。
    - 地圖搜尋要按 Enter 才過濾（U158）。
    - 讀檔後播放頭停在結尾（U158）。
  - 另外：啟動時有兩次停在「Waiting for ZenServer」超過 5 分鐘，關掉自己的編輯器重開就好。
  - 測試場景、影片、截圖都已刪除。

### U143～U148　第二十九批：U138～U142 找到的問題（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U143 KKS 地圖畫面破碎（最優先） | U141 實測時，灯台（56）、水族館（57）、石垣通路（58）、地圖 50 在 Studio 裡都破碎：網格成尖刺、貼圖變平色，灯台的海面像法線貼圖。KK 時代的教室、中庭正常。Rust 端從庫讀出的頂點與 HEAD 版庫比對沒有差（只多一個 Plane），重開 Studio 第一張就讀也一樣，U132／U138 的改動也不影響這些地圖。查 UE 端（`KKPreviewActor` 建網格、11-02 整合進來的改動）是從哪一版開始壞的，修好 |
| U144 時段光照的實景對照（U141 重做） | 等 U143 修好後，在 KKS 戶外地圖拍朝、昼、夕、夜四張，對照太陽方向與色溫 |
| U145 兩個角色面對面 | U142 要讓兩人面對面，只能自己在旋轉欄位算角度（試了兩次）。角色頁加「面向對方」：所選角色轉向另一個（或最近的）角色 |
| U146 換地圖後角色落地 | U140 從教室換到中庭，原本的角色仍在原高度，懸在屋頂上。換地圖時把角色放到新地圖的地面，或在狀態列提示並給「放到地面」 |
| U147 開新場景時視角回到預設 | U142 開新場景後視角留在上一張地圖的遠景，加的角色在畫面裡很小。新場景時視角回到預設，讀地圖後取景整個地圖或焦點附近 |
| U148 mp4「含音樂」但沒有音樂時提示 | U142 勾著「mp4 含音樂」輸出，但沒在播 BGM，影片沒有音軌也沒有提示。輸出完成訊息寫明「沒有播放中的音樂，影片無聲」 |

U143～U148 完成紀錄（2026-11-03，控制通道實測）：

- U143 KKS 地圖畫面破碎：
  - 找法：
    - 在灯台用部件逐段隱藏（二分法），找到兩個破碎的部件：柵欄 `o_ks_m06_saku11_00` 與 `saku13_00`。
    - 它們的頂點包圍盒三個軸都一樣（-21.5～0.2 m），第二個頂點起就是亂數。
    - 從原始 bundle 直接解碼也一樣錯，所以是解碼器的問題，不是基礎庫的資料舊了。
  - 原因：
    - 這個網格的法線通道 dimension 是 52（0x34）。Unity 較新的版本把旗標放在 dimension 的高四位，真正的維度只看低四位（4）。
    - 照 52 算，每個頂點的間距算成 116 bytes，實際是 32（44096 bytes／1378 頂點），從第二個頂點起全部讀錯。
  - 修正：
    - `mesh_decode.rs` 的 `decoded_from_object` 解碼前把每個通道的 dimension 取低四位。
    - 新增掃描測試 `sources_with_flagged_channel_dimensions`（和既有的 UV 掃描同一套做法），列出受影響的來源：遊戲 22017 個來源中有 89 個（角色部件 34、Studio 道具 16、Studio 地圖 30、mod 9）。
    - 不只地圖：眼鏡、耳環、面具等角色飾品也在內。
  - 基礎庫：
    - 以 `OKLIB_REFRESH=meshes_for_maindata,meshes_for_maindata_including_disabled,decode_all,base_bundle convert <base_v1> 8 @<清單>` 重錄這 89 個來源，換掉 5662 筆紀錄。
    - 本機重錄、沒有提交（U151）。
  - 實測：
    - 灯台的柵欄、步道、樓梯、路牌都回到原位。
    - 水族館（57）入口完全正常。
    - 剩下的植物 LOD 與貼圖、海面問題另列 U149、U150。
- U143 整合時的基礎庫重錄（C、E 都要做）：
  - 這筆改了共用的 `ok-extract` 網格解碼。基礎庫 okmodel 存的是解碼後的網格，只換程式不會變，要重錄受影響的來源。否則 C／E／F 的基礎庫會不一致。
  - F 本機重錄的 89 個來源：[`Tools/oklib_rerecord/u143_channel_dimension.txt`](../Tools/oklib_rerecord/u143_channel_dimension.txt)。
    - 遊戲 80 個：`abdata/chara` 34、`abdata/studio` 16、`abdata/studio/map` 30。
    - mod 9 個（F 的 mods 資料夾裡的地圖與服裝 zipmod）。
  - mods 每台不同，C、E 先在自己的環境掃出清單，再重錄：

    ```powershell
    # ok 系列的程式（含 cargo 與它們跑的工作）最多 8 個執行緒
    $env:RAYON_NUM_THREADS='8'
    # 1. 掃出受影響的來源（約 50 分鐘，讀遊戲與 mods 的全部來源）
    $env:OK_TEST_GAME_ROOT='<遊戲目錄>'; $env:OK_DIM_SCAN_OUT="$PWD\Saved\u143_sources.txt"
    cargo test -j 8 --release --manifest-path Tools\ok-extract\Cargo.toml --lib sources_with_flagged_channel_dimensions -- --ignored --nocapture
    # 2. 重錄（新的紀錄附加在 okmodel 後面，讀取時以後面的為準）
    cargo build -j 8 --release --manifest-path Tools\ok-extract\Cargo.toml
    $env:OKLIB_REFRESH='meshes_for_maindata,meshes_for_maindata_including_disabled,decode_all,base_bundle'
    .\Tools\ok-extract\target\release\ok-extract.exe <遊戲目錄> --oklib convert Content\IndependentResources\base_v1 8 "@$PWD\Saved\u143_sources.txt"
    ```

  - 只想對齊遊戲本體的部分時，可以直接用 F 的清單：mod 那 9 行在沒有該 mod 的環境會被略過。
  - F 的重錄沒有提交（base_v1 不是 F 組提交的檔案）。由負責基礎庫的人提交，並照規定在乾淨 clone 跑 `kks-verify` 與 `okcard-check`（U151）。
  - 用到那 34 個角色部件的 OK 卡，卡內資源包也是舊的解碼結果，要重轉。
- U144 時段光照的實景對照：植物與海面還不對，改到 U152。
- U145 兩個角色面對面：
  - 變換列新增「面向對方」，也加到物件清單的右鍵選單（指令 `transform.face`）。
    - 選兩個角色時，兩人面對面。
    - 只選一個時，轉向最近的另一個角色。
  - 實測：Male01 與 C050 各轉 -90°／90°，狀態列寫「Male01 與 C050 面對面」。
- U146 換地圖後角色落地：
  - 中庭的原點剛好在鋪面外，角色站在沒有地面的地方，下面看得到天空。
  - 新增 `SettleCharactersOnMap`：換地圖後，腳下 25 cm 內沒有地圖零件頂面、或身體在家具裡的角色，移到附近最近的有地面的空位。
  - 新角色找空位時，同樣要求腳下有地面；整張地圖找不到時，退回原本的規則。
  - 實測：兩個角色換到中庭，狀態列寫「1 個角色移到地圖的地面上」，C050 站到磚面上，有影子。
- U147 開新場景時視角回到預設：
  - 新場景回到初始視角。
  - 場景裡還沒有角色時，讀地圖後也回到初始視角（地圖原點，Studio 站角色的地方）。
  - 實測：開新場景後，焦點 (0,0,90)、距離 380。
- U148 沒有音樂時提示：
  - 勾「含音樂」但沒有播放中的 BGM 或外部音源時，完成訊息是「完成（沒有播放中的音樂或外部音源，影片無聲）：路徑」。
  - 音樂讀不進來、改輸出無聲影片時也會註明。
  - 提示放在路徑前面：第一版放在後面，被輸出窗的寬度切掉。
- 驗證：
  - `cargo check` 與 `cargo check --no-default-features` 通過。
  - `unity::` 測試 30 個通過；`studio_renderer_shadow_policy_matches_source` 通過。
  - 遊戲 Development 與編輯器都建置成功。
  - `verify_ok_studio.lua --tag u143_1103` 全部通過（`F:\OpenKoikatsu\Saved\OKStudio\Verify-u143_1103`）。

### U138～U142　第二十八批：U132～U137 留下的問題（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U138 KK 時代地圖的時段對應 | 教室 1-1 等 KK 時代地圖只有 SunLightInfo 種類 0～2，內容是「昼、夕、夜」（白 24°、橙 17°、藍 42°，天空材質 hiru／yu／yo），OK 照 KKS 的「朝 0、昼 1、夕 2、夜 3」讀，整個錯一格。查原作 `Map.RangeTimeZone`／地圖清單怎麼把場景時段對到 info 種類，照它讀；狀態列與天空跟著改 |
| U139 有家具時新角色放得太遠 | U134 實測第一次在教室加第二個角色時，放到 7 m 外的教室另一頭（第二次 1.5 m）。往旁邊排與一圈圈找空位都以焦點為起點，課桌擋住近處時就跳很遠。改成先在已有角色周圍找空地，再退回焦點 |
| U140 中庭的 `kage` 網格確認 | U132 讓沒有 Renderer 的網格不再畫出。全部 Studio 地圖掃過，只多藏了九張地圖的透明牆（`Cube`）與中庭的 `mo_koi_map33_kage00`。實際開中庭比對原作截圖，確認地上的影子沒少 |
| U141 時段光照的實景對照 | U133 確認 KKS 地圖（地圖 50）四個時段讀取正確。換到 KKS 戶外地圖各拍朝、昼、夕、夜四張，與原作同位置截圖對照太陽方向與色溫 |
| U142 第五輪整段實測：教室兩人對話場景 | 用滑鼠做：教室 1-1、時段「夕」、兩個角色面對面、相機兩個 key、輸出 mp4（含音樂），存檔重開。記下點擊次數與卡手處 |

U138～U142 完成紀錄（2026-11-03，控制通道實測）：

- U138 KK 時代地圖的時段對應：
  - 全部 Studio 地圖的 SunLightInfo 掃過一遍，分成兩類：
    - KK 時代的學校地圖（`mo_koi_*`）都是剛好種類 0、1、2，內容是昼、夕、夜：天空 `mo_koi_sky_hiru／yu／yo`，窗玻璃 `*_glass`、`*_glass_e`、`*_glass_n`。
    - KKS 地圖（檔名 `*_studio`）的 0～3 才是朝、昼、夕、夜，清單直接叫 morning、daytime、evening、night。
  - 修正（`okmodel_view.rs` 的 `scene_times`）：種類剛好是 {0,1,2} 的地圖往後挪一格成昼、夕、夜，朝沿用昼。
  - 部件依時段顯示、太陽方向與顏色、地圖燈的時段、狀態列與自動天空都讀同一份資料，一起跟著對。
  - 實測（教室 1-1）：
    - 「夕」：太陽仰角 17°、#FF980C，教室照成橘色，窗外換成夕暮的天空。
    - 「夜」：藍色的弱光。
    - 「朝」：與「昼」相同的白光。
  - 窗外的樹是地圖烘焙的貼圖，不隨時段變。
- U139 有家具時新角色放得太遠：
  - 候選位置有三種：往旁邊排、已有角色周圍一圈圈、焦點周圍一圈圈。
  - 每個空位的分數是到焦點的距離加到最近角色的距離，取最低分。
  - 實測：教室裡連加三個角色，彼此相距 1.2～1.5 m。原本第一次被放到 7 m 外。
  - U142 時，第二個角色被放到第一個的正前方，把他擋住。改成：沿視線方向在最近角色前後的空位，加兩倍的距離罰分。重測後兩人左右並排。
- U140 中庭的 `kage` 網格：
  - 中庭從上方看，校舍與樹在地上的影子都在（烘焙在光照貼圖裡）。
  - 藏掉的 `mo_koi_map33_kage00` 沒有 Renderer，原作也不畫。
- U141 時段光照的實景對照：沒做成。
  - 換到 KKS 戶外地圖時，灯台、水族館、石垣通路、地圖 50 的畫面都破碎（列為 U143）。
  - 四時段對照改到 U144。
- U142 第五輪整段實測：
  - 流程：開新場景、地圖窗雙擊「教室1-1」、系統選單「畫面設定」→「環境／天空」→「夕」、加兩個角色、轉成面對面、相機兩個 key（0 秒、3 秒）、輸出 3 秒 mp4、存檔、重開。
  - 地圖、時段、狀態列說明都一次到位。
  - 重開後：地圖 4、時段 2、兩個角色、相機與兩個 key 都在。
  - 卡手處：
    - 第二個角色擋在第一個前面（已在 U139 修正）。
    - 面對面要自己算角度（U145）。
    - 新場景的視角還在上一張地圖的遠景（U147）。
    - 勾了「含音樂」但沒播 BGM，影片無聲且沒有提示（U148）。
  - U140 另看到：換地圖後角色懸在原高度（U146）。
- 驗證：
  - `cargo check` 與 `cargo check --no-default-features` 通過。
  - 遊戲 Development 與編輯器都建置成功。
  - `verify_ok_studio.lua --tag u138_1103` 全部通過（`F:\OpenKoikatsu\Saved\OKStudio\Verify-u138_1103`）。

### U132～U137　第二十七批：U131 整段實測與 U128 留下的問題（2026-11-03 列出，F 組，完成）

U131 用滑鼠做完「兩個角色、書掛在手上、主光從亮到暗、輸出 PNG 序列、存檔重開」，共 27 下。以下照卡手的先後排。

| 項目 | 內容 |
|---|---|
| U132 教室窗外仍是黑的 | U128 讓有地圖的場景自動開天空，沒有地圖時天空正常，但教室 1-1 的窗外仍是黑的。查地圖自己的窗外網格（`mo_koi_sky_*` 等）與天空球的前後關係，讓窗外看得到天空或地圖自己的雲 |
| U133 「夕」的太陽是淺藍色 | 狀態列寫出教室 1-1 的「夕」：太陽仰角 42°、顏色 #97DDFF，和「朝」幾乎一樣。對照原作 SunLightInfo 的各時段資料，確認讀取是否取錯時段 |
| U134 第二個角色的間距 | 第二個角色只往旁邊放 60 cm，T 字姿勢時男角的手臂穿進女角的頭。間距改依前一個角色的包圍盒寬度算，並讓新角色入鏡 |
| U135 打 key 與刪 key 分清楚 | 時間軸的「打 key」是沒有字的 ◇，旁邊有字的是「刪 key」，實測點錯一次。「打 key」加字並放在最前面，「刪 key」改成較不顯眼的樣式 |
| U136 輸出窗記住設定、不蓋時間軸 | 輸出窗每次打開都回到「PNG 序列」、「到」回到 -1，而且開在時間軸窗上面。記住上次的種類與時間範圍，打開時放在時間軸旁邊 |
| U137 道具目錄窗太小 | 道具目錄窗只有 270×230，三欄名稱都被擠。加大預設尺寸，讓第三欄的道具名稱完整顯示 |

U132～U137 完成紀錄（2026-11-03，用控制通道實測，Demo 的 C050 與 Male01）：

- U132 教室窗外是黑的：
  - 原因不是天空。教室 1-1 有一個名為「Cube」的灰盒子包住整間教室（中心 (418,70,88)、半徑 642 cm），把窗戶全擋住。
  - 它在 `o_koi_map08_tkabe00／01` 節點上，只有 MeshFilter，沒有 Renderer（給碰撞用的透明牆），Unity 不畫；OK 照樣畫出來。
  - 修正（`okmodel_view.rs` 的 `mark_renderer`）：地圖有 Renderer 清單、而網格所在節點沒有 Renderer 時，標成不顯示、不投影。
  - 全部 Studio 地圖掃過，多藏的只有九張地圖（1-1、1f、2-1、2-2、2f、3-1、akikyoushitu、ground、rooftop）的 `Cube` 與中庭的 `mo_koi_map33_kage00`（列為 U140 確認）。
  - 實測：教室窗外看得到樹與圍牆，走廊側窗戶看得到走廊牆面。既有測試 `studio_renderer_shadow_policy_matches_source` 通過。
- U133 「夕」的太陽是淺藍色：
  - 讀取沒有錯。教室 1-1 是 KK 時代地圖，SunLightInfo 只有種類 0～2：
    - 0：24°，#E4FFF7（白）
    - 1：17°，#FF980C（橙）
    - 2：42°，#97DDFF（藍）
  - 對照天空材質 hiru／yu／yo，這三種是「昼、夕、夜」。
  - KKS 地圖（地圖 50）的 0～3 才是朝、昼、夕、夜（0／1 60° 白、2 20° #FFECC1、3 90° #C0F7FF），讀取正確。
  - KK 地圖要照原作的時段對應表讀，列為 U138；這批不改程式。
- U134 第二個角色的間距：
  - 已有角色的骨架包圍盒都算進去，新角色要離開它們，並取最寬那個的半寬當自己的寬（25～120 cm）。
  - 往旁邊排的間距改成兩倍半寬加 10 cm。
  - 放好後，頭部位置不在取景空區（U123）內時，視角焦點移到新角色上。第一版只移一半，新角色被放到 7 m 外時仍不在畫面裡，改成直接移過去。
  - 實測：男角在 x=60，女角放在 x=210，T 字姿勢的手臂離她 80 cm，畫面中央就是她。
  - 第一次實測女角被放到 7 m 外（列為 U139）。
- U135 打 key 與刪 key：
  - 時間軸第二排最前面是綠底的「◆ 打 key」，提示寫明快捷鍵 K。
  - 「刪 key」改成 9 pt、輸入框底色，「清空」縮窄。
  - 實測截圖：兩顆一眼分得出來。
- U136 輸出窗記住設定、不蓋時間軸：
  - 種類、起訖、fps、寬高、含音樂、輸出資料夾在按「開始」時寫進設定檔（`export_choices`），打開輸出窗時讀回。
  - 打開時若與時間軸窗重疊，依序改放到時間軸右邊、上面、左邊。
  - 實測：選 mp4、到 1.0 秒、開始輸出後重開 Studio，輸出窗回到 mp4、1.0，位置在時間軸窗右邊。
- U137 道具目錄窗：
  - 預設 440×400；三欄寬改為 90、100、226（搜尋時 420），高 330。
  - 實測：「スフィア(通常)」「穴あきキューブ(通常)」等名稱完整顯示。
- 控制通道 `parts` 新增 `exact`（名稱完全相同才算）與 `main_pass` 欄位：用子字串找「Part_10」會一併改到 Part_100～109 的顯示。
- 驗證：遊戲 Development 與編輯器都建置成功；`cargo check` 與 `cargo check --no-default-features` 通過；`verify_ok_studio.lua --tag u132_1103` 全部通過（`F:\OpenKoikatsu\Saved\OKStudio\Verify-u132_1103`）。
- 留下的問題排成第二十八批。

### U126～U131　第二十六批：U125 整段實測的卡手處（2026-11-03 列出，F 組，完成）

U125 用滑鼠做完「地圖＋時段＋BGM＋兩個相機 key＋3 秒影片＋存檔重開」，共 28 下，其中 4 下是繞路（見 U125 紀錄）。以下照卡手的先後排。

| 項目 | 內容 |
|---|---|
| U126 清單雙擊就執行 | 角色卡雙擊會加入，其他清單不會：地圖清單雙擊只選取（還要按「讀取」）、場景縮圖雙擊只選取（還要按「覆蓋（開啟）」）、BGM 曲目點了不播（還要按「播放」）。改成雙擊直接讀取／開啟／播放，單擊維持選取 |
| U127 新角色放在空地上 | 有地圖時新角色放在地圖原點，教室 1-1 的原點正好在課桌裡，F 取景被前排桌椅擋住。改成放在視角前方的地面空處（像 U106 的新燈），放不下時狀態列說明 |
| U128 時段與天空看得出來 | 選「夕」幾乎看不出變化，窗外一片黑（天空預設關）。有地圖時預設開天空並跟著時段換天色，時段按鈕旁寫出目前的光照（方向、顏色） |
| U129 影片帶聲音 | mp4 只有影像，BGM 沒進去。輸出窗加「含音樂」勾選（預設勾），把時間範圍內的 BGM 與外部音源混進 mp4 |
| U130 工作區圖示與未儲存標記 | 工作區下排的資料夾圖示是「加資料夾物件」，看起來像開檔，實測點錯一次。換圖示並在提示寫明，開檔另放一顆。加了又復原回存檔時的狀態，標題仍有「*」、開別的場景還問要不要存；復原到存檔點時清掉標記 |
| U131 第四輪整段實測：道具與燈光動畫 | 用滑鼠做：兩個角色、一個道具掛在手上、一盞燈在時間軸上從亮到暗、角色動作播放中輸出 PNG 序列，存檔重開。記下點擊次數與卡手處 |

U126～U131 完成紀錄（2026-11-03，用控制通道的 `mouse` 實測，Demo 的 C050 與 Male01）：

- U126 清單雙擊就執行：
  - 新增 `OKStudioStyle::RowButton`：單擊選取，雙擊再執行。
  - 套用在三個地方：
    - 地圖清單雙擊直接讀取，「（無地圖）」也一樣。
    - 場景縮圖雙擊等同「覆蓋（開啟）」，有未存的變更時照樣先問。
    - BGM 曲目雙擊直接播放。
  - 實測：三種雙擊都直接生效。
- U127 新角色放在空地上：
  - 有地圖時，取地圖各零件的包圍盒，只看擋在腳踝到頭之間的零件。地板、牆與天花板的包圍盒涵蓋整間房，不算在內。
  - 先照舊往旁邊排，再從視角焦點一圈一圈往外找空位。找不到時放在焦點，狀態列說明可能重疊。
  - 實測：教室 1-1 的新角色放在 x=60 的課桌走道上，不再卡在桌子裡。
- U128 時段與天空：
  - 讀入沒有自己天空的地圖時，自動開天空，樣式跟著時段（朝 0、昼 1、夕 2、夜 3）。
  - 換時段時，若天空樣式是這四種之一，就跟著換。
  - 狀態列寫出時段在這張地圖上的效果，有三種情況：地圖沒有這個時段、光照烘焙在貼圖裡、太陽仰角與顏色。
  - 實測：
    - 選「夕」後，天空換成「夕暮れの空」，狀態列寫出太陽仰角與顏色。
    - 沒有地圖時天空正常。
    - 教室 1-1 的窗外仍是黑的（列為 U132）。
    - 「夕」的太陽是淺藍色（列為 U133）。
- U129 影片帶聲音：
  - 輸出窗加「mp4 含音樂」，預設勾選。播放中的 BGM 與外部音源從影片開頭混成一條 AAC 音軌，會循環的照樣循環，長度和畫面相同。
  - 帶聲音編碼失敗時，改輸出沒有聲音的影片。
  - 實測：輸出的 mp4 有 h264 與 aac 兩條軌，各 10 秒。
- U130 工作區圖示與未儲存標記：
  - 「加資料夾」換成資料夾加號的圖示，提示寫明是資料夾物件。
  - 旁邊新增「開啟場景」圖示。工作區一排變成 8 個，改為 26 px。
  - 存檔或開檔時記下文件狀態，復原或重做回到這個狀態時清掉「*」。
    - 第一版只在存檔時取文件 JSON，存檔前還沒記進歷史的變更，讓復原停在比存檔更早的狀態，「*」仍在。
    - 改成存檔前先提交歷史。
  - 實測：存檔、加資料夾、復原後，標題沒有「*」。
- U131 第四輪整段實測：
  - 流程：兩個角色、C050「立ち1」、「本1」掛在右手、主光 0 秒強度 4、2 秒強度 0.5、輸出 0～2.5 秒 PNG、存檔、重開，共 27 下。
  - 實測時找到輸出的 bug：
    - 每一幀拿到的是上一幀的角色燈光與手上道具位置，第一幀還是輸出前播放頭（2 秒）的暗光。
    - 原因：卡通角色的燈光（`UpdateItemLighting`）與掛點（`PlaceAttached`）在場景的 Tick 裡更新，比輸出截圖晚。
    - 修正：截圖前先更新這兩項。
    - 修正後第 0、10、30、60、74 幀角色亮度為 111、100、81、67、66，逐幀遞減。
  - 重開後：兩個角色、動作（`studioAnimeNo` 1）、掛在手上的書、兩個燈光 key 都在。
  - 卡手處排成第二十七批。

### U122～U125　第二十五批：選單位置、取景避開面板、清單字級、第三輪整段實測（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U122 選單開在按鈕旁 | 「切鏡頭 ▼」與時間軸 key 的緩動選單開在系統游標的位置。控制通道模擬點擊時選單跑到左下，鍵盤操作也一樣。改成貼著觸發它的按鈕（或 key）開，模擬與真實滑鼠一致 |
| U123 取景避開面板 | F、配對後對準、看臉都以整個視窗的中心取景，左側屬性窗、右側分組與工作區、時間軸窗會擋住角色（U118 的兩人有一半在面板後）。取景改以沒被面板蓋住的區域為中心，並依那塊區域的大小算距離 |
| U124 動作清單字級 | U104 記下的：動作清單的字比其他清單大一號。改成和其他清單相同的 10 號字與行高，並確認長名稱與「（雙人）」標記不被截斷 |
| U125 第三輪整段實測：地圖、音樂、輸出影片 | 用滑鼠做一個有地圖與 BGM 的單人場景：選地圖、調時段、加 BGM、時間軸兩個相機 key、輸出 3 秒影片、存檔重開。記下點擊次數與卡手處，排出下一批 |

U122～U125 完成紀錄（2026-11-03，用控制通道的 `mouse` 實測，Demo 的 C050）：

- U122 選單開在按鈕下：
  - 「切鏡頭 ▼」改成以按鈕自己的位置開選單（按鈕左下角），不再用系統游標。
  - 緩動選單本來就用點擊事件的位置，不用改。
  - 實測：模擬點擊時選單出現在按鈕正下方。
- U123 取景避開面板：
  - 面板每 0.25 秒算一次「沒被面板蓋住的最大區域」，交給遊戲（`UOKStudioGame::ClearView`）。
    - 算法：取所有面板的左右邊當候選，每一對之間找上下最大的空隙。
    - 評分以短邊為主（短邊 × √面積）。只比面積時，時間軸下方的扁長條會贏過旁邊較高的直條，站著的角色反而更小。
  - F、配對後對準、看臉都改用同一個取景：
    - 把目標放在空區中心（移動環繞中心）。
    - 距離用包圍盒投影到畫面左右、上下的半寬半高，對空區的寬高算。原本用包圍球，T 字姿勢的角色在窄空區裡只佔四成高。
    - 看臉用頭部附近 12 cm 的方塊，距離約 70 cm，和原本差不多。
  - 實測：
    - 開著動畫窗與右側兩個面板按 F，C050 落在兩者之間的空區正中，高度填滿。
    - 看臉時臉在兩面板之間。
  - 控制通道的 `camera` 回傳加 `clear_view`，方便檢查。
  - 副作用：環繞中心不在角色身上，之後旋轉視角是繞空區中心轉。
- U124 動作清單字級：
  - 動作清單的列改成 10 號字，和其他清單相同。
  - 實測：H 動作清單的長名稱沒有被截斷。
- U125 第三輪整段實測（教室 1-1、夕、BGM「13 デート」、相機 1／2、3 秒 mp4、存檔重開）：
  - 共 28 下，其中 4 下是繞路：
    - 地圖雙擊沒讀取，多按一下「讀取」。
    - BGM 點了不播，多按一下「播放」。
    - 把工作區的資料夾圖示當成開檔，加出一個資料夾物件，再按 Ctrl+Z 復原。
    - 場景縮圖雙擊沒開，多按一下「覆蓋（開啟）」。
  - 結果都正確：
    - 影片 3 秒 1920×1080，0.5 秒是相機 1、2.5 秒是相機 2。
    - 重開後地圖、時段（`sunType` 2）、BGM（自動播放）、兩台相機與兩個場景 key 都在。
  - 卡手處：
    - 「夕」看不出變化，窗外全黑。
    - 新角色在地圖原點的課桌裡，F 被前排桌椅擋。
    - mp4 沒有聲音。
    - 復原後仍算未儲存。
  - 這些排成第二十六批。

### U117～U121　第二十四批：雙人場景的卡手處（2026-11-03 列出，F 組，完成）

U116 雙人場景每一步都做得到，存讀也正確。卡手的地方集中在雙人：找有對方的動作、配對後的視角、看不到臉。

| 項目 | 內容 |
|---|---|
| U117 標出有對方的動作 | H 動作清單裡，有另一性別對應動作的項目加標記（例如「⇄」），並可篩選「只看雙人」。「配給對方」灰掉時，提示寫出原因（這個動作沒有對方的動作／場景裡沒有另一個角色） |
| U118 配對後對準兩人 | 「配給對方」後把視角對準兩個角色的中點，距離取能同時看到兩人；F 在多選時對準全部所選（U116 的 F 只對準一個） |
| U119 表情與手勢回報 | 表情（眉、眼、嘴）與手勢的 ◀▶、下拉改值後，狀態列寫出部位與編號（例如「C050 眼 2／41」）。另加「看臉」：把視角移到所選角色的臉前（HS2Studio6 的臉部特寫） |
| U120 場景 key 直接選相機 | 時間軸「場景 key」旁加相機下拉（自由視角、相機 1、相機 2…），選了直接在播放頭打切換 key，不用先「用此相機」。U116 每個切點要點三下 |
| U121 卡片窗記住上次的資料夾 | 角色卡窗每次開都在 CrowdAPNG，加 Demo 的卡要先上一層再進去。改成記住上次加卡的資料夾，並在資料夾列加「最近用過」 |

U117～U121 完成紀錄（2026-11-03，用控制通道的 `mouse` 實測，Demo 的 C050 與 Male01）：

- U117 標出有對方的動作：
  - H 動作清單裡，有另一性別對應動作的項目標「（雙人）」，判斷規則和「配給對方」相同（目錄只建一次索引）。
  - 加「只看雙人」勾選。勾了以後，女H奉仕・前待機只剩床、椅子、立ち、プール四個，都標「（雙人）」。
  - 「配給對方」改成選了角色就能按，不能配時狀態列寫原因：
    - 沒有動作：「先在 H 動作選一個標「（雙人）」的動作，再配給對方」。
    - 動作沒有對方：寫出動作名，並提示勾選。
    - 場景只有一個角色：沿用原本的訊息。
- U118 配對後對準兩人：
  - 配給對方後，兩個角色都選上，先同步場景（對方剛移到同一位置，包圍盒才會是新的），再對準全部所選。
  - 角度改成兩人的側面、偏向所選角色正面 10 度，俯角 10 度。
  - 第一版從所選角色正面偏 30 度看，女角被男角擋住；也沒先同步，對準中心偏到男角舊位置。
  - F 本來就會對準全部所選；U116 是因為只選了一個。
  - 實測：「立ち（雙人）」配對後，兩人並排完整入鏡（包圍盒高 208 cm，距離 394）。
- U119 表情與手勢回報、看臉：
  - 表情與手勢的下拉、◀▶ 改值後，狀態列寫出結果，例如「C050 眼：1 両目閉じ」。
  - 表情頁加「看臉」。它和表情頁的 F 共用 `FocusSelection(true)`，新算法如下：
    - 用頭骨相對靜止姿勢的旋轉，推出臉現在的朝向。
    - 對準頭骨上方 8 cm、前方 3 cm。
    - 從臉的正前方往側面轉 40 度，距離 70 cm。
  - 原本固定從角色正面、頭骨上方 8 cm 看。跪姿角色抬頭時會對到脖子，正前方又被對方擋住。
  - 實測：跪姿的 C050 臉部完整入鏡。
- U120 場景 key 直接選相機：
  - 時間軸「場景 key」旁加「切鏡頭 ▼」，選單列出自由視角與每台相機。
  - 選一個就在播放頭打場景 key，設成切到該鏡頭，視角也切過去（新指令 `timeline.cutkey`）。
  - 每個切點從三下（選相機、用此相機、場景 key）變成兩下。
  - 實測：0 秒選相機 1、3.03 秒選相機 2，場景軌道上兩個 key 的鏡頭各是 4、5。
  - 選單開在游標的位置。控制通道不會移動系統游標，所以模擬點擊時選單出現在左下；真實滑鼠會出現在按鈕旁。
- U121 卡片窗記住資料夾：
  - 角色卡窗第一次打開時，進入最近加過的卡所在的資料夾（設定裡最近使用的 `card:` 清單）。
  - 左側加「最近用過」，列出最多四個其他資料夾。
  - 實測：重開 Studio 後，卡片窗直接在 Demo，最近用過列出 CrowdAPNG、female 等。

### U113～U116　第二十三批：U105～U112 留下的問題與第二輪整段實測（2026-11-03 列出，F 組，完成）

| 項目 | 內容 |
|---|---|
| U113 骨骼清單點選後列的位置不動 | U108 保留了捲動位置，但點清單下方的骨骼後，該列仍往下移約 140 像素。找出原因（捲動框的位移、上方內容的高度或焦點捲動），讓點下去的那一列留在原來的位置 |
| U114 道具直接掛到部位 | U104 掛道具要在角色分組先選部位才出現「掛到所選部位」。加道具或選道具時，可以直接從部位清單挑一個掛上去（HS2Studio6 拖到部位上），不用兩邊來回切 |
| U115 新點光的預設強度 | U109 把點光放到角色前方 1.5 m 後，角色明顯過亮。對照 HS2Studio6 的點光預設（強度、範圍），調成加上去不會洗白的值 |
| U116 第二輪整段實測：雙人場景 | 用滑鼠從空場景做雙人場景：加兩個角色（雙擊）、選雙人動作並「配給對方」、調一個手勢與表情、加點光與兩台相機、時間軸在 0 秒與 3 秒切換相機、播放、存檔重開。記下點擊次數與卡手處，和 U104 比較，排出下一批 |

U113～U116 完成紀錄（2026-11-03，用控制通道的 `mouse` 實測）：

- U113 骨骼清單點選後位置不動：
  - 加記錄查到：捲動位置有保留（1280），但點擊後內容總高從 2046 變成 2248。展開的 XYZ 三列只佔約 60 像素，其餘約 140 像素出現在被點的列上方。是哪一段變高沒有找到。
  - 改成從結果處理：點擊時記下那一列在捲動框裡的位置；重建後第三幀，用新的同一列算出位移，把捲動量補回去（`RememberRowPlace`）。
  - 實測：點清單下方的「右胸」，該列留在原來的 y=160，XYZ 展開在它下方。
- U114 道具直接掛到部位：角色分組的部位列可以雙擊，直接把所選物件掛上去；沒選物件時狀態列會提示。實測：加道具後展開「分組：手」、雙擊「右手」，就掛到 `a_n_hand_R`（原本要點部位再按「掛到所選部位」）。
- U115 新點光：U109 記的「角色過亮」是看錯了。點光強度 4、200、800 拍出來的角色都一樣。文件早已確認原作角色著色器沒有 ForwardAdd，點光、聚光本來就不照卡通角色。
  - 真正的問題是新點光沿用方向光的強度 4，而匯入的原作點光強度 1 換算成 800，所以新點光連地圖都幾乎照不亮。
  - 改成新點光、聚光預設 800。
  - 加入後狀態列寫「（照地圖；角色與卡通道具和原作一樣只受方向光影響）」。
- U116 第二輪整段實測（雙人場景，Demo 的 C050 與 Male01）：

  | 步驟 | 點擊 | 結果與卡手處 |
  |---|---|---|
  | 開卡片窗、到 Demo 資料夾 | 4（＋、角色、上一層、Demo） | 卡片窗預設在 CrowdAPNG，要往上一層再進 Demo |
  | 加兩個角色 | 2 次雙擊 | 男角自動放在 X=60，不重疊 |
  | 選女角、開 H 動作 | 3（樹列、角色選單、動畫）＋「H 動作」 | — |
  | 找雙人動作 | 先選「愛撫・キス反応ループ」，「配給對方」是灰的；改選「女H挿入・正常位・弱ループ」 | 看不出哪些動作有對方的動作，灰掉的按鈕也沒說原因 |
  | 配給對方 | 1 | 狀態列「Male01 配上 C050：弱ループ」。之後視角停在男角背後很低的地方，看不到女角的臉 |
  | 表情、手勢 | 骨骼→表情→眼 ▶ 三下、嘴 ▶ 兩下；手勢→右手 ▶ 兩下 | 值都設上了（眼 2、嘴 1、右手 1），但臉被男角擋住看不到，狀態列也沒有回報 |
  | 調視角 | F 只對準所選的一個角色 | 雙人時要自己繞；這次用控制通道設視角 |
  | 兩台相機 | 各 1 下（工作區的加入相機） | — |
  | 點光 | 2（燈光、點光源） | 狀態列說明不照角色 |
  | 時間軸 | 1（右上新的時間軸鈕） | — |
  | 相機切換 key | 每個切點 3 下：選相機列、「用此相機」、「場景 key」，中間點時間尺到 3 秒 | 時間軸顯示「相機 1」「相機 2」兩個 key；1 秒時使用相機 1，4 秒時使用相機 2。播放從播放頭開始（當時在 3 秒） |
  | 存檔、新場景、讀回 | — | 雙方動作（5/142/3）、表情、手勢、兩個切換 key 都回來 |

  和 U104 比：加角色、掛道具、開時間軸都少了步驟。新的卡手處在雙人：找有對方的動作、配對後的視角、看不到臉。這些排進下一批。

### U105～U112　第二十二批：U104 實測的卡手處（2026-11-03 列出，F 組，完成）

U104 從空場景做一個小場景：每一步都做得到，存讀也正確，但有八個地方找不到或點不準。這批照實際操作的順序修。

| 項目 | 內容 |
|---|---|
| U105 卡片雙擊加入 | 加角色視窗裡雙擊卡片等於「加入」，連續加多個角色時少點一下。單擊仍只預覽 |
| U106 狀態列回報動作與骨骼 | 套用動作後狀態列寫「C000 套用 立ち1」；在骨骼清單或畫面上選骨骼後寫骨骼名稱，不再留著上一個 |
| U107 骨點分主次 | 手腳、腰、頭等主要骨點畫大並分色（HS2Studio6 的紅藍球），手指、頭髮、裙子、胸的骨點縮小變淡，點擊優先選主要骨點 |
| U108 骨骼清單不捲回頂端 | 點骨骼清單的一列後，頁面停在原處並把選到的列標亮 |
| U109 新燈光放在視角前方 | 加燈光時放在目前視角前方、角色附近，不固定在 (0, 0, 300) |
| U110 兩個相機圖示分開 | 「加入相機」與「相機設定」用不同圖示並加提示文字，避免誤加相機 |
| U111 時間軸入口 | 右上 ▷ 標明「MMD 導演」；時間軸開關放到右上工具列的明顯位置 |
| U112 最近場景移除不存在的項目 | 最近場景裡標「檔案不在了」的列可以移除，另有「清除不存在的」一鍵整理 |

U105～U112 完成紀錄（2026-11-03，用控制通道的 `mouse` 實測）：

- U105 卡片雙擊加入：卡片格子的內容包一層 `SBorder` 接雙擊，雙擊等於「加入」，單擊仍只預覽。
  - 控制通道的 `mouse` 加 `"double": true`，送出按下、放開、雙擊、放開。
  - 實測：雙擊 C000 加入一個角色，沒有多加。
- U106 狀態列回報：
  - 套用動作後寫「C000 套用動作 立ち1」。
  - 從骨骼清單選骨骼也寫「骨骼：右胸 cf_j_bust01_R」，和點畫面上的骨點一樣。
- U107 骨點分主次：
  - 四肢（肩、上臂、前臂、手、大腿、小腿、腳）是紅色大點；腰、脊椎、頸、頭是藍色大點。
  - 手指、頭髮、裙子、胸是淡色小點。
  - 有 FK 值的骨骼偏綠。
  - 點選時小點的距離乘 1.8，大點優先。
  - 實測：點手肘選到「前腕 cf_j_forearm01_R」。
- U108 骨骼清單：
  - 重建屬性列時，頁面、骨骼分頁與所選物件都沒變，就保留捲動位置（換頁或換物件才回頂端）。
  - 選中的骨骼列標成琥珀色。
  - 實測：捲到清單下方點「右胸」，該列標亮、仍在畫面內，狀態列更新。
  - 限制：那一列會往下移約 140 像素。捲動位置有保留，上方內容也沒變，原因還沒找到。
- U109 新燈光：點光、聚光、面光放在目前視角前方（往相機方向最多 1.5 m，高 60 cm），並朝向焦點；方向光不變。實測點光在 (0, 148.5, 170.9)，朝向角色。
- U110 相機圖示：
  - 工作區下方「加入相機（從目前視角）」改用新的相機加號圖示。
  - 右上的提示改成「相機設定」。
- U111 時間軸入口：
  - 右上的 MMD 導演改用場記板圖示，旁邊加時間軸開關。
  - 工具列多一格，起點左移 40 像素，`Tools/studio_layout_spec.lua` 對照 HS2Studio6 的索引往後移一號。
  - 第一次漏改起點，最右邊的相機設定被擠出畫面（記在 ERROR_LOG）。
- U112 最近場景：
  - 「檔案不在了」的列把「開啟」換成「移除」。
  - 有不存在的項目時，下方出現「清除不存在的場景（N）」。
  - 實測：移除一項、清除八項後，重開 Studio 只剩存在的場景。
  - 第一次存到 `settings.json`，重開後又回來；改用 `SaveFavorites()`（記在 ERROR_LOG）。

### U102～U104　第二十一批：缺少的 zipmod、模擬拖曳失效、整段流程實測（2026-11-03 列出，F 組，完成）

HS2Studio6 參考截圖裡，還沒被本計畫引用的大多是同一畫面的另一張（`L_*`、角色載入後的各頁）。其中定制角色、定制飾品、HairShader 依「在 Studio 裡換裝與捏人」那一條屬人物編輯器，不做。所以這批以工作流程為主：補 U38 留下的缺口、修自動實測的工具，再用滑鼠從頭做一個場景，找出實際使用時卡手的地方。

| 項目 | 內容 |
|---|---|
| U102 資源檢查列出缺少的 zipmod | 原作卡開卡時，把實際找不到的 zipmod（Rust 的 `LAST_ABSENT_ZIPMODS`）經 FFI 交給 session；資源檢查把「卡片指名 N 個 mod」改成標出哪幾個缺少（HS2Studio6 资源检查）。改到 ok-extract 與 C ABI，要跑 `cargo check`（含 `--no-default-features`），並連結遊戲與編輯器 |
| U103 控制通道模擬拖曳偶爾無效 | U98 發現：場景有角色時，`mouse` 的拖曳偶爾整段無效，引擎 `SSpinBox` 的拖曳沒有開始。找出原因（滑鼠移動事件在哪一層被吃掉或改掉），修好或在 `mouse` 回報裡標出，讓自動實測的結果可信 |
| U104 從空場景做一個小場景 | 全程用滑鼠：加角色、選動作、FK 調一隻手、加道具掛到手上、加燈光與相機、時間軸打兩個 key 播放、截圖、存檔、關掉再開。記下每一步要點幾下、哪裡找不到、哪裡要回頭，排出下一批 |

U102 完成紀錄（2026-11-03）：

- 做法：原本計畫用轉 OK 卡時的 `LAST_ABSENT_ZIPMODS`，但那只在轉卡時算。改成新增 `oklib::card_absent_mods`：用開原作卡同一套視野（基礎庫記錄的 mod、卡片旁的 zipmod、`OK_GAME_ROOT` 的 `mods/`）查卡片指名的每個 GUID，找不到的列出來。
  - C 函式 `ok_card_absent_mods`，不在函式表內，不動 `OkRustBindings` 的排列。
  - Unreal 端 `FOkSession::AbsentCardMods`。
- 資源檢查：每張原作卡在背景執行緒查一次，結果回來後視窗自動重建。
  - 查的過程標「檢查中…」。
  - 查完後角色列寫「都找得到」或「缺 N 個」，缺的排在最前面並標「缺少」。
  - 缺的也列進上方缺件區，例如「#3 jeanne_x：缺 zipmod Jeanne_Xetol」，算進缺件數。
  - 「重新檢查」會丟掉快取重查，裝好 mod 後按一下就好。
- 實測：
  - 遊戲裡的原作卡（指名 28 個與 10 個 mod）都標「都找得到」。
  - 把卡片複製一份，GUID `Jeanne_Cetol` 同長度改成 `Jeanne_Xetol`，並以 `OK_GAME_ROOT=X:/NoGame` 開 Studio：顯示「缺 1 個」、「缺少　Jeanne_Xetol」，上方「1 項缺件」。
  - 原卡在同一個場景仍是「都找得到」。
- 限制：本機基礎庫記錄了已轉過的第三方 mod，所以它們算找得到。乾淨 clone 不帶這些 mod 的模型，會改讀實際的 zipmod；要是那時 zipmod 也不在，這裡不會標出來。

U103 完成紀錄（2026-11-03）：

- 原因：引擎 `SSpinBox` 拖曳時只更新內部值，真正的提交延到下一次 Tick。提交前會比對「最後看到的外部值」（`CachedExternalValue`），不同就當成外部改了值，丟掉這次位移。這個快取只在建構時和提交後更新，所以換選取、復原、用 gizmo 改值之後就過期了。
  - 真實滑鼠會丟掉拖曳的第一幀。
  - 控制通道的拖曳全部在同一幀完成，所以整段失效。
  - 「同一欄重拖又會成功」，是因為第一次提交已經把快取更新了。
  - 用記錄確認：失敗那次按下、十次移動都有 capture，也正常放開，提交時拿到的卻是原值。
- 修正：`SOKSpinBox` 按下時呼叫 `ResetCachedValueString()`，先同步快取。
- 重測：
  - 角色的旋轉 X／Y／Z、縮放 X／Y、位置 X 第一次拖各 40 像素，都是 +32 度、+0.32、+32 cm。
  - 改選燈光後拖旋轉 X（-35 → -3），Ctrl+Z 後再拖，也都正確。

U104 完成紀錄（2026-11-03，用 `mouse` 點擊，記下次數與卡手處）：

1. 加角色：「＋」→「角色」→ 點卡片（只預覽）→「加入」→ 關窗，共 5 下。
   - 卡手：卡片不能雙擊直接加入。HS2Studio6 也是預覽加按鈕，但連續加多個角色時多一下。
2. 選動作：角色選單 →「動畫」→ 點「立ち1」，共 3 下，順利。
   - 卡手：狀態列仍顯示「加入角色 C000」，沒有回報套用了哪個動作。
   - 動作清單的字比其他清單大一號。
3. FK 調一隻手：「骨骼」→「FK←姿勢」→ 點畫面上的骨點。
   - 卡手：113 個骨點同色同大小，胸、頭髮、裙子、手指的點和手臂疊在一起。點三次分別選到左胸、拇指，沒點到手臂。HS2Studio6 的主要骨點是大的紅藍球。
   - 改用下方骨骼清單：要先捲到清單才看得到。點「前腕 cf_j_forearm01_R」後頁面捲回頂端，看不到剛選的那一列；狀態列仍顯示上一個骨骼（拇指）。
   - 用控制通道拖 3D 旋轉把手的綠環、紅環，前臂角度都沒變（拖曳被 3D 視窗接走）。U94 拖 IK 把手可以。
   - 原因：3D 視窗按下時先找骨點（7 像素內），再找把手；骨點散在旋轉環上，按在環上會先選到附近的骨點，環永遠抓不到。真實滑鼠也一樣。
   - 修正：點在把手上時，只有正好點在骨點上（3 像素內）才選骨點，否則抓把手。
   - 重測：從骨骼清單選前臂後，拖紅環頂端，前臂從 -95.5 度轉到 -71.5 度，畫面上手從臉旁放到腰邊；另外兩次是沒點準環線（9 像素內才算）。
4. 道具掛到手上：「＋」→「道具」→ 點「スフィア」→ 關窗 → 物件屬性展開「分組：手」→「右手」→「掛到所選部位」，共 7 下，掛上後跟著手動。
   - 卡手：要先在骨骼頁選好部位才看得到「掛到所選部位」，兩個地方要來回切。
5. 燈光：「＋」→「燈光」→「點光」，3 下。
   - 卡手：點光固定出現在 (0, 0, 300)，不在角色或目前視角附近，要再拖回來。
6. 相機：工作區下方的相機圖示一下就從目前視角加入「相機 1」。
   - 卡手：右上的相機圖示是「相機設定」視窗，工作區下方的相機圖示是「加入相機」，外觀一樣；不小心多加了「相機 2」。
7. 時間軸兩個 key：右上的 ▷ 開的是 MMD 導演，不是時間軸；時間軸要從「開啟完整時間軸視窗」或工作區工具列開。選相機 1 在 0 秒打 key、移到 3.07 秒把 X 改成 72 再打 key，播放時 X 從 28 經 63 到 72，內插正確。
   - 卡手：▷ 的位置像播放鈕，實際開的是別的視窗。
   - 播放時控制通道的 `mouse` 回「busy: playing」，要用 `studio_timeline {"play":false}` 停下（真實滑鼠不受影響）。
8. 截圖：在系統選單（齒輪）→「截圖」→「拍攝」，存到 `UserData/Studio/screenshot/okstudio_20261103_031924.png`。
   - 卡手：截圖藏在齒輪選單裡，不是相機圖示。
9. 存檔、關掉再開：「開啟／儲存」輸入名稱存檔 →「新場景」→「最近場景」→「開啟」。角色、動作、道具與掛點、燈光、兩台相機、相機 1 的兩個 key（0 秒、3.07 秒，X=72）都回來了。
   - 卡手：「最近場景」列了很多已刪的測試場景，標「檔案不在了」，但沒有辦法從清單移除。

整段結論：所有步驟都做得到，資料存讀正確；卡手處都在「找得到」與「點得準」。排進下一批（U105～）：

- 卡片雙擊直接加入。
- 套用動作、選骨骼後狀態列回報。
- 主要骨點放大並分色（手腳、腰、頭），手指頭髮裙子的點縮小。
- 骨骼清單點選後不捲回頂端。
- 新加的燈光放在目前視角前方。
- 兩個相機圖示分開（加入相機與相機設定用不同圖示或文字）。
- 右上 ▷ 改標「MMD 導演」，時間軸入口放到明顯位置。
- 最近場景可以移除已不存在的項目。

### U15　工作室模式只顯示工作室 UI（2026-10-30，使用者要求）

從卡片牆等其他模式進入工作室時，畫面上原本的 UI 會留著。改成：工作室面板加到 viewport 後，從 viewport 的 Slate 樹往下找到面板，沿路把其他兄弟節點（其他模式的 UMG、Slate 面板、圖層）全部收起來，並把 HUD 的 `bShowHUD` 關掉；`Stop` 時還原成原本的可見狀態。

控制通道新增 `leave`（`POST /studio/leave`，可帶 `{"name":"<名稱>"}`）：等同按工作室的關閉鈕，回到啟動工作室的模式。工作室關閉時控制通道也會關，所以帶 `name` 時在一秒後另拍一張含 UI 的整個視窗截圖，存到 `Saved/OKStudio/mcp_ui/<名稱>.png`。實測（卡片牆 `-game -Control "-ExecCmds=OKStudio.Play"`）：在工作室時畫面只有工作室 UI；`leave` 之後卡片牆的清單、按鈕與角色資訊完整還原。

診斷用的控制通道指令：`exec`（`{"command":"ShowFlag.Translucency 0"}`，在遊戲世界下主控台指令）、`parts`（`{"match":"Part_133","hide":true}`，列出或隱藏名稱含 match 的預覽元件，附 owner、包圍球中心與半徑）。注意 `camera` 只要設了 focus／yaw／pitch／distance 就會切到自由相機；要回到場景相機用 `{"use_camera":<相機物件 id>}`，`capture` 拍的是目前的相機。另外，`run_scene_visual_audit.lua` 的原生畫面沒有套用場景的地圖位移（caMap），有移動地圖的場景要以 KK 縮圖為準。

## 7. 優先順序總表

| 優先 | 階段 | 理由 |
|---|---|---|
| P0 | U0 拆檔與指令表 | 所有後續工作的前提；同時解決快捷鍵焦點問題與 UI 驗收手段 |
| P0 | U1 SceneEditor 外殼改成 HS2Studio6 版面 | 畫面一打開就接近 HS2Studio6；之後每個面板都放進這個外殼 |
| P0 | U2 選取與物件樹 | 現況最大的操作障礙（不能在視窗點選、不能多選、不能拖放） |
| P1 | U7 存讀與可靠性 | 使用者資料安全；未存提示與自動備份成本低、效益高，可與 U3 並行 |
| P1 | U3 目錄與加入 | 加東西是最常做的事 |
| P1 | U5 姿勢 | Studio 的核心創作工作 |
| P1 | U4 Gizmo 與相機 | 姿勢與擺物件的效率 |
| P2 | U6 時間軸 | 工作量最大，依賴 U2 多選與 U4 相機物件 |
| P2 | U8 外觀參數 | 補 UI 為主，風險低 |
| P2 | U9 設定與 AI | 指令表穩定後再開放 |

建議順序：U0 → U1 → U2 →（U7 ∥ U3）→ U5 → U4 → U6 → U8 → U9。U0 完成、面板拆成獨立檔之後，U3／U7／U8 碰的檔案不重疊，可以分給不同 session 並行。

---

## 8. 風險

| 風險 | 對策 |
|---|---|
| OK Studio 由 E 線負責（[雙線開發](DUAL_LINE_DEVELOPMENT.md)），F 組改動要合回 | 動工前與協調者確認 F 組是否接手 OK Studio UI；U0 拆檔是大搬移，要在 E 線沒有未合併的 `OKStudioGame.cpp` 改動時一次完成並盡快合回，避免長期分叉 |
| 共用工作樹多 session 同改 `OKStudioGame.cpp` | U0 先拆檔；之後每階段只碰自己的面板檔；提交只交自己的 hunk |
| 視窗點選角色：預覽角色是自訂渲染、GPU skin，未必有可用碰撞 | 先用骨骼膠囊（骨位置來自 `BoneWorldMatrix`）與部件 bounds 判定；不夠準再考慮 hit proxy 或 ID buffer |
| 多選＋整份 JSON 快照 Undo 的記憶體與延遲 | 現有上限 100 步／256 MB、沒變的物件不重建（`Game.cpp:1346-1409`）；多選操作合併成一步；量測大場景（`OKStudio.StressItems`）的快照時間 |
| 縮圖大量解碼拖慢 UI | 背景執行緒解碼、每幀建立數量上限、LRU 快取；perf 預算 0.5 ms |
| 時間軸新軌道與既有 `EvaluateTimeline`、Story、`.okanim` 輸出相容 | 只加欄位；舊檔讀取測試列入 `verify_ok_studio.lua`；`.okanim` 輸出結果與改動前位元組比對 |
| 全域快捷鍵前處理器攔到別的 Slate（主控台、故事模式） | 只在工作室執行、非故事模式（`SetStoryMode`，`Game.cpp:1732`）、焦點不在文字輸入時派發 |
| Unreal 實例上限（全機 2 個） | 驗收按 `C:\portable\OpenKoikatsu\Saved\SESSION_RULES_ALL_20261028.md` 的 slot 規則排隊；UiSelfTest 設計成單一程序跑完 |
| 舊 UMG 動作時間軸移除影響讀卡畫面 | U6-8 最後做，先對照功能清單、讀卡畫面改入口後再刪 |

---

## 9. 不做的項目

- **HS2 角色、HS 場景匯入、HS2/KK 混合產品頁**：OK Studio 只處理 KK／KKS 與 OK 卡。
- **局域網聊天與場景同步**（HS:UIR#工作室聯機聊天）。
- **硬體光追出圖**（HS2Studio6 的 TrueTrace）、**MRQ 算圖**（已依使用者 2026-10-18 決定擱置）。
- **原外掛原樣移植**（KKSPlugin、VNGE、NodesConstraints、VMD）：需要時把功能重寫進指令表與面板，不做外掛載入層。
- **Route（路線）系統**：時間軸的平滑路徑（`bSmoothPath`）已涵蓋主要需求，本計畫不另做 HS2Studio6 式路線物件。
- **Editor 版 `FOKStudioEditor` 功能對等**：Editor 版只維持開檔、存檔、反射編輯；新 UI 只做在遊戲內工作室。
- **改用 UMG 或改寫成 Editor Mode**。
- **畫面還原**（光影、LUT、天空、各樣本場景差異）：繼續由 [OK Studio 計畫](OK_STUDIO_PLAN.md) 處理。
- **在 Studio 裡換裝與捏人**：HS2Studio6 的定制角色、定制飾品、HairShader、服裝卡套用（`hs2/56`、`58`～`60`）都屬人物編輯器的工作，本計畫不做；OK Studio 保留換卡、換服裝組、衣服狀態。
- **語音播放佇列**（`hs2/55_voice.png`）：之後若要做，另開計畫。
- **SkinEffects、ClothingBlendShape、ClothColliders、角色 MaterialEditor、汁貼花**：屬資料／渲染功能，仍是 [OK Studio 計畫](OK_STUDIO_PLAN.md) `:331` 的待辦，不在本計畫。

---

## 10. 驗收文件

每階段除了第 6 節的自動驗收，還要在 `Saved/StudioUIRef/compare/` 重拍對應的 OK Studio 畫面，與第 3.8 節的 HS2Studio6 截圖並排檢查，並在完成紀錄中附上對照圖路徑。

每階段完成時在本檔對應章節下方補一段「完成紀錄」：日期、commit、`OKStudio.GameSelfTest`／`OKStudio.UiSelfTest` 結果、`verify_ok_studio.lua` 的 tag、perf 數字與前一版的差、人工檢查截圖路徑。做錯的事照專案規則寫進 `Docs/ERROR_LOG.md`。

---

## 11. 截圖對照的重拍方式

兩邊都不動實體滑鼠：OK Studio 走程式內通道，HS2Studio6 走 Unity 內的 EventSystem（原因見 `Docs/ERROR_LOG.md` 2026-10-29「對別的前景視窗送了合成滑鼠點擊」）。

**HS2Studio6**

1. 先在 Unity Hub 登入並啟用授權。
2. 啟動 Unity，它會直接打開 `zzzstudio.unity` 並進入 Play：

   ```powershell
   & 'F:\Unity\Editors\6000.3.22f1\Editor\Unity.exe' -projectPath 'F:\OpenKoikatsu\ref\HS2Studio6' -logFile 'F:\Unity\logs\hs2studio6.log' -executeMethod OKLocalCapture.Menu
   ```

3. 把指令一行一條寫進 `F:\Unity\okcmd.txt`。輔助腳本會依序執行，結果寫進 `F:\Unity\okcmd.out`，全部做完時最後一行是 `DONE`。可用的指令：

   | 指令 | 作用 |
   |---|---|
   | `list` | 把畫面上可按的元件（路徑、文字、螢幕座標）寫到 `F:\Unity\okui.json` |
   | `clickname <文字或物件名>` | 點第一個名稱或文字包含它的元件 |
   | `click <x> <y>` | 點螢幕座標，原點在左下 |
   | `wait <n>` | 等 n/20 秒 |
   | `shot <名稱>` | 截 Game 畫面到 `Saved/StudioUIRef/hs2/<名稱>.png` |
   | `layout <名稱>` | 輸出整棵 UI 樹到 `Saved/StudioUIRef/layout/<名稱>.json`（第 12 節的版面規格由此產生） |
   | `reload` | 停止 Play、重新編譯後再進 Play |
   | `quit` | 停止 Play 後正常結束 Unity；直接結束行程會留下場景備份，下次啟動卡在「Recovering Scene Backups」對話框 |

4. 輔助腳本在 `ref/HS2Studio6/Assets/OKLocalCapture/Editor/OKLocalCapture.cs`，只留本機。
5. 本機工程的資源狀態（2026-10-29）：
   - 已合入 `ref/HS2Studio6-BasicResources-WithMeta-20261029.zip`：新增 390 檔，與工程內容相同的 865 檔不動，沒有衝突檔。
   - 另外用它的轉換器（`Tools/StandaloneConverter/offline_bundle.py`，模板由 `KKMakerBuilder.BuildTemplate()` 產生）從本機 KKS 安裝轉出一批 KK 包；其中 166 個已改用資源包裡的官方版本，資源包沒有的 23 個（多為 BGM）留著。
   - KK 包只剩 5 個追加 BGM 沒有。
   - 測試用的 KKS 原作卡放在 `ref/HS2Studio6/UserData/KK/chara/female/`（4 張，只留本機）。

**OK Studio**

- 目前：用 `SceneEditor.cmd` 開場景後截取遊戲視窗。截圖前要先拿全機 Unreal 名額（slot），截完放掉。
- U0-4 完成後：改用 `OKStudio.Cmd <id>` 打開面板、`OKStudio.UiState` 確認狀態，截圖由遊戲內輸出。屆時兩邊都可以用腳本重拍，對照圖可以每個階段自動更新。

---

## 12. 整合路線：讓 OK Studio 逼近 HS2Studio6

HS2Studio6 是 C# 與 uGUI，不能在 Unreal 裡執行。做法是把它當規格書，在 OK Studio 裡用 Slate 重做。

1. **版面規格**（已完成）
   - 40 個面板狀態的完整 UI 樹，已整理成 [版面規格](OK_STUDIO_HS2_LAYOUT_SPEC.md) 與 `Docs/StudioUI/hs2studio6_layout_spec.json`。
   - 內容包括：主題色、字級、外殼各區塊錨定與尺寸、每個視窗的矩形與控制項。
2. **外殼**（U0、U1）
   - 拆檔、建立指令表後，照規格的外殼重排：左上 add／anim／sound／system 四個主鈕加子選單、右上工具列、角色分組欄加工作區樹、左下變換列。
   - 主題色與尺寸做成一份 Slate 樣式，以 1600×900 為基準等比縮放。
   - 詳情窗同時只開一個；Timeline、動畫控制器、快搜、姿勢庫、相機窗是獨立浮窗。
3. **逐窗補上**（U2～U9）：照規格表的「OK 對應」欄，每個 HS2Studio6 視窗接到 OK 已有的後端：
   - 狀態：`FOKSceneCharacter::ClothesStates`、`AccessoriesShown`
   - 骨骼各頁：`FOkSession::SetFk`、`PrepareStudioIk`、`IkEffectorPosition`、`SetStudioFixedNeck/Eyes`、`SetHeadLook`
   - 動畫：`FOKStudioCatalog::Anims`
   - 場景卡：`FOKSceneCard`、`UOKSceneDocument`
4. **對照驗收**
   - 同一張 KKS 原作卡在兩邊都讀得起來。
   - U0-4 的 `OKStudio.Cmd`／`OKStudio.UiState` 完成後，OK Studio 也輸出 Slate 版面（相同的 JSON 欄位）。
   - 每階段比對「面板矩形數值差」，並重拍並排截圖（第 10 節）。
5. **不照抄**
   - 原作圖示與 UI 圖片不進 repo。
   - 簡中字串改用文字表的語意 id。
   - 不做聊天、HS 角色、Studio 內換裝捏人。
   - 保留 OK 自有的 Story、`.okanim` 輸出、KStudio 匯入與畫面還原。

OK Studio 依[雙線開發](DUAL_LINE_DEVELOPMENT.md)歸 E 線，動工前先與協調者確認由誰接手。U0 拆檔要一次做完並盡快合回。
