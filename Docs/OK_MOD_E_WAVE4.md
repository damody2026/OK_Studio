# OK mod 第四波（E 組）：Studio 物件操作、共存測試、Studio／1 對 1 相對 KKAPI 的缺口（2026-11-23）

計畫：`Docs/OK_MOD_FRAMEWORK_PLAN.md` §16.4 的 E 段（主本在 C）。檢出 `E:\OpenKoikatsu`（`master`），引擎 `E:\PhysX\UE5.8`。

## 1. 提交

| 提交 | 內容 |
|---|---|
| `0e52b8e05` | Studio C++：mod 回覆的 `ops` 經控制通道的 op 改物件（整批一個 undo 步驟）、`studio.get`、`studio.ops_result`、`studio.character_changed`、呼叫內容加 `lang`、`Ui::details`、系統 → Mod 頁（`panel: "mods"`）、工具列 studio 圖示與按下狀態 |
| `f44e52cea` | `ok-mod-studio` SDK 的 `op` 模組；新範例 `light-rig`；`profiles/full.toml` 列入 light-rig |
| `5d4ae8b0c` | 1 對 1：`pair.*` 在 H 場景帶 `her_gauge`／`his_gauge`／`inserted`，回覆 `{"pair": {"her", "his"}}` 設量表；街區開的 1 對 1 在 `pair.enter` 時也拿得到女角卡（從控制器補）與控制器 |
| `3312b37b0` | 修正：mod 的 `pose` op 會把選取換成那個角色（見 §4） |

當機前留下的改動（§16.4 表）全部收進前三個提交；其中 `OKHScene.h` 的 `SetGauges`／`InsertedNow` 當機時還沒有呼叫端，這次在 `OKPairModBridge.cpp` 接上。`OKExtractBuildStamp.h` 沒提交。

## 2. Studio 物件操作（mod 端）

mod 在任何回覆（指令、按鍵、事件、`ops_result` 本身）加 `"ops": [...]`，宿主依序執行，**和回覆的其他效果一起是一個 undo 步驟**；結果陣列以 `studio.ops_result`（`results`、`tag`）回給同一個 mod，mod 回覆的資料與再發的 ops 仍在同一步內（最多巢狀 4 層，防止自己打自己）。Studio 忙（播放、讀檔、匯出、模態操作）時 op 回 `busy`，和控制通道一致。

| 操作 | op | SDK（`ok_mod_studio::op`） |
|---|---|---|
| 新增物件（角色、道具、燈、相機、特效、資料夾、模型） | `spawn` | `spawn(kind, extra)`，新 id 在結果 `id` |
| 刪除、複製、改父物件 | `delete`、`duplicate`、`reparent` | `delete`、`duplicate`、`reparent` |
| 位移、旋轉、縮放 | `transform` | `transform(id, loc, rot, scale)` |
| 顯示／隱藏 | `show`（= `patch` `bVisible`） | `show(id, bool)` |
| 名稱 | `rename`（= `patch` `name`） | `rename(id, name)` |
| 服裝組、穿著狀態 | `dress`（`outfit` 0..6；`clothes` 九格或 `part`＋`state`） | `outfit`、`clothes`、`clothes_all` |
| 動作 | `pose` `anim`（`kind/group/category/no`）、`anim_file` | `anim(id, key)` |
| 表情 | `pose` `expression` | `expression(id, eyebrow, eyes, mouth, mouth_open)` |
| FK／IK | `pose` `fk`、`ik`（骨名、效應器先全部檢查，錯一個整個 op 不改） | `fk(id, &[(bone, euler)])`、`ik(id, &[(effector, pos, weight)])` |
| 其餘任意欄位 | `patch`（`FOKSceneObject` 的 JSON，同 `studio_inspect`） | `patch(id, fields)` |
| 讀 | `studio.get` = op `get`（場景狀態同 `studio_state`，給 `id` 時另附該物件全文）；`inspect`、`bones`、`bounds` | `get(Some(id))`、`inspect(id)` |

不開放給 mod 的 op：存讀檔、匯出、視窗、滑鼠鍵盤、相機、undo／redo、離開（白名單在 `OKStudioRunModOp`）。

`studio.character_changed`：每幀比對角色的卡、服裝組、穿著、動作、顯示用 actor，變了就在下一幀通知（`changes`: `added`／`card`／`outfit`／`clothes`／`animation`／`loaded`）。undo／redo 也會觸發，所以只收狀態列，回覆的 data／ops 等被忽略並記警告（否則會產生新步驟、吃掉 redo 歷史）。

`ok-mod-api` 型別**沒有改**：全部走 `Event::Hook` 與 JSON。

## 3. 共存測試

`Mods/` 裝：toon-post、idle-breath、object-hotkeys、studio-autosave、scene-notes、timeline-flow、light-rig（另有非 Studio 的 pair-counter、subtitles，在 Studio 正確被略過）。全部用這次的 SDK 重編（`cargo build --release -j 8`）。Studio 以 `studio_launch -ModDevContent` 開（控制埠 47990，`OK_STUDIO_PORT=47990`），用 ok-game MCP 的 `studio_*` 與 `ok-game-mcp.exe call` 操作。

| 測試 | 結果 |
|---|---|
| 載入 | `mode studio: 7 mod(s) enabled`；7 個都登錄，指令表有 16 個 `mod.*` 指令 |
| light-rig 補光 | 選 C000 按 toggle：`spawn` 加點光 #4（名稱「補光 → C000」，位置上方 150 cm），`ops_result` 記下 id，狀態列「補光 #4 加在 #2 上方 150 cm」，只多 1 個 undo 步驟 |
| aim（`get` 讀位置 → `transform`） | 選 #3 執行：補光移到 (80, 0, 150) |
| smile（`expression`＋`clothes`） | 兩個角色 `eyesPattern 1`、`mouthPattern 1`、`mouthOpen 0.3`、`clothesStates[0]=1` |
| solo（`show`）／再按全部顯示 | 藏起 3 個物件；存檔重開後再按，狀態列「全部顯示（3 個）」，四個都回來（資料隨場景存讀） |
| rename | 修正後選 2 個角色改名為「C000 1」「C000 2」（修正前見 §4） |
| 其他 mod 同時操作 | scene-notes 加備註、timeline-flow 放迴圈起點、studio-autosave 立即備份（「已自動備份 … 保留最新 5 份」）、toon-post 重設 |
| undo／redo | 共 9 步（2 個 spawn＋7 個 mod 指令，autosave 不算步驟）；undo 3 步可見性與資料回復，redo 3 步回來 |
| 存讀檔 | `E:\OpenKoikatsu\UserData\Studio\scene\emod4_coexist.png`（本機，不進版控）。重開後 light-rig 的 `solo`、`rig`，scene-notes 的備註（「備註 1／1：C001 1：E組第四波共存」）都在；toggle 刪掉了記住的補光 |
| toon-post | 掛上內容外掛、材質 ready；reset 後畫面有網點與描線，undo 後消失。前 `E:\OpenKoikatsu\Saved\OKControl\shots\emod4_toon_on2.png`、後 `E:\OpenKoikatsu\Saved\OKControl\shots\emod4_toon_off2.png` |
| `studio.character_changed` | `studio_patch` 把 #3 換成服裝組 1：狀態列先「角色 #3：outfit」，重建完成後「角色 #3：loaded」 |
| `frame_stats` | idle-breath（每幀呼叫）與其他 6 個並存：第一次 7143 次呼叫、1 次超過 500 µs（594 µs）、未停；第二次開 4286 次、0 次超時、最慢 80 µs |
| log | 第二次開整段沒有 `LogOKStudioMods`／`LogOKMod` 的警告或錯誤 |

## 4. 過程中發現並修掉的

- **`pose` op 改掉選取**（`3312b37b0`）：控制通道的 `pose` 會 `Select` 那個角色（面板的動作選取依選取運作）。mod 在同一個回覆裡對多個角色發 `pose`，選取就被換成最後一個，使用者的多選不見，下一個指令只作用在一個物件（實測：smile 後 rename 只改到一個）。`OKStudioRunModOp` 對 `pose` 記下並還原選取。
- **E 的 `Mods/toon-post` 缺 `content/` 的 pak**：`-ModDevContent` 也要先有 `content/*.pak`（宿主依它決定 `content_root`）才會去掛未 cook 的外掛，否則記「no usable material」，效果完全不出現、卻沒有別的錯誤。從 F 的 `Mods/toon-post/content/` 複製後正常。記在 `Docs/ERROR_LOG.md`。

## 5. Studio／1 對 1 相對 KKAPI 的缺口清單

對照 KKAPI（`StudioAPI`、`StudioSaveLoadApi`、`SceneCustomFunctionController`、`StudioObjectExtensions`、`CurrentStateCategory*`、`ToolbarManager`、`TimelineCompatibility`、`CharaCustomFunctionController`、`GameAPI` 的 H 場景部分）與 KK_Plugins 實際用法。

### 5.1 Studio：已對上的

場景控制器的 load／import（含 id 對照）／clear／save、複製、刪除、選取；場景資料（`.okscene` `mods`，快照式 undo 自動涵蓋）；CurrentState（狀態頁）與 SceneEffects（畫面設定）控制列；工具列（文字或 studio 圖示、按下狀態）；右鍵選單；mod 指令進指令表（自動 undo）；時間軸可插值的 mod 值與標記通知；按鍵、拖曳、計時器；每幀後姿勢（`ok_mod_frame`）；這一波的物件新增／刪除／修改與 `studio.get`。

### 5.2 Studio：缺的

| # | KKAPI／原作插件用法 | OK 現況 | 建議 |
|---|---|---|---|
| S1 | `OnObjectVisibilityToggled`（`StudioObjectExtensions` 的顯示切換事件） | 沒有事件；只能從 `objects` 的 `visible` 自己比對 | 加 `studio.object_visibility`（Hook，`ids`、`visible`）；和 `character_changed` 一樣在 undo 時也會發，只收狀態列 |
| S2 | Studio 裡的 `CharaCustomFunctionController`：角色卡的 mod 資料（ExtendedSave 角色範圍）在 Studio 讀寫、`OnReload`、`OnCardBeingSaved` | Studio 角色只給卡路徑；mod 讀不到也寫不了卡內 `okMx`，資料只能存在場景 | 加 `studio.character_load`（帶該 mod 的 `okMx` 區段，同 `reader.character_load`）與場景內的角色覆寫資料（存場景、不改卡檔） |
| S3 | `PoseBeingSaved/Loaded`（姿勢檔的擴充資料） | 計畫 §6.5 已延後 | 等有 mod 需要再開 `studio.pose_save`／`pose_load` |
| S4 | `GetSelectedControllers<T>()`、`OCIChar.GetChaControl()`：插件直接拿角色的骨架、ABMX、表情、材質物件 | mod 只看得到 `FOKSceneObject` JSON 與 op；骨骼即時讀數只能經每幀呼叫 | 開唯讀 op：角色目前姿勢的骨骼世界座標（`bones` 只有清單）、bounds 已有 |
| S5 | `CurrentStateCategoryTextbox`、按鈕列之外的自訂 IMGUI 視窗（KK_Plugins 大多自畫視窗） | 有 Toggle／Slider／Dropdown／Color／Text／Button 列與 Mod 頁；沒有 mod 自己的浮動視窗 | DreamGUI（§6.13）接進 Studio，或給 Mod 頁分組／標題列 |
| S6 | 匯入／合併時的物件 id 對照給所有物件事件（`ObjectsCopied` 之外，例如 undo 後物件 id 重用） | undo 會把刪掉的物件以同 id 還原；mod 記的 id 不會壞，但 `objects_deleted` 之後的 undo 沒有「物件回來了」的事件 | 加 `studio.objects_restored`（或讓 `scene_load` 帶 `kind: undo`），讓依 id 清資料的 mod 不會在 undo 後少一筆；目前因資料在快照內，mod 的資料會一起回來，實務上影響小 |
| S7 | 道具（`OCIItem`）材質、顏色、圖樣的插件（MaterialEditor Studio 端） | 可經 `patch` 的 `item.colors`／`materialEdits` 改，但沒有材質清單查詢 | 開唯讀 op 列出道具材質槽與 shader 參數 |
| S8 | Timeline 的「動態可插值」（依所選物件產生的 interpolable，例如每個骨頭） | mod 的可插值是登錄時固定的 | 允許 `panel_ui` 之外在 `objects_selected` 回覆更新可插值清單 |
| S9 | 讀場景前的 `SceneLoad` 前置事件（插件在載入前清狀態） | 只有載入後的 `scene_load` | 需要時加 `studio.scene_before_load` |
| S10 | 相機、場景燈光、BGM 的修改（StudioSceneSettings 一類） | op 白名單刻意不含 camera／scene；toon-post 走自己的後處理 | 若要做 StudioSceneSettings 類範例，開 `scene` op 的 post 子集（一樣進 undo） |

### 5.3 1 對 1：已對上的

`pair.enter`／`ready`／`exit`（含女角卡的 `okMx` 讀寫、檔案被占用時重試）、`note`、`finish`、`voice`、`line`、`speech_start`（字幕回覆顯示在字幕列）、每幀呼叫（配對時鐘的 `dt`）、這一波的量表讀寫與是否插入。

### 5.4 1 對 1：缺的（對 `GameAPI`／`HSceneProc` 的插件用法，例如 KK_Plugins 的 H 場景類、HCharaAdjustment、HSceneCrowdReaction 一類）

| # | 原作用法 | OK 現況 | 建議 |
|---|---|---|---|
| P1 | 體位／動作切換事件（`HSceneProc.ChangeAnimator` 的 postfix） | 沒有；mod 只看到 note／line | `pair.motion`（體位 id、名稱、類別、是否插入） |
| P2 | H 狀態（愛撫、插入、高潮、射精、外／內）逐步事件 | `finish` 只有結束一次 | `pair.state`（狀態名、量表），`finish` 帶內外 |
| P3 | 插件讓角色換服裝、穿著狀態（衣服半脫、全脫） | 1 對 1 沒有 mod 能用的操作；Studio 有 `dress` | 1 對 1 也開 op 白名單：`dress`、`expression`、`look`（同 Studio 的 JSON） |
| P4 | 角色位置／高度微調（HCharaAdjustment） | 沒有 | `pair` op `adjust`（男女相對位移，進每回合重置） |
| P5 | 速度、強弱、自動模式的讀寫 | 讀不到也改不了 | payload 帶 `speed`、`strong`；回覆 `{"pair": {"speed"}}` |
| P6 | H 場景 UI 加按鈕（KKAPI 沒有官方 API，插件大多自畫） | 沒有登錄點 | 1 對 1 的 `ui.<mod id>.*` 按鈕列（同讀卡器的作法） |
| P7 | 男方的卡、身分 | payload 只有女角卡 | 加 `his_card` |
| P8 | 量表回覆在 H 場景以外（街區試衣間、讀卡器開的 1 對 1） | 沒有 H 面板時只記 trace | 目前合理；文件已註明 |

## 6. 驗證與沒驗到的

- `cargo test -j 8`（`Tools/ok-mod`）全過；`cargo check -j 8`（`Tools/ok-extract`，另加 `--no-default-features`）過；`E:\PhysX\UE5.8` 建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 連結成功（修 `pose` 後再建一次，兩個都過）。
- Studio 共存實機測試如 §3（兩次開 Studio，各在 20 分鐘內，名額 `e-mod-4` 用完即釋放）。
- 補驗結果見 §7。
- **沒驗到**：
  - object-hotkeys 的拖曳（控制通道的 `studio_key` 是按下立刻放開，同第三波）。
  - timeline-flow 迴圈在這次只放了標記，沒有播放確認（第三波已測過）。
  - 讀卡器開的 1 對 1、試衣間的量表回覆（沒有 H 面板時只記 trace）。
  - 打包版（stage）裡的 mod 與 toon-post pak。

## 7. 補驗（協調者要求，同步點 D 之前）

新增：測試用 mod `Tools/ok-mod/fixtures/pair-gauges`（不進範例與 full 設定檔）；light-rig 加 `tilt`（FK，參數為骨名，預設 `cf_j_neck` 轉 20°）、`reach`（IK，參數為效應器，預設 3 移到 (30, -20, 140)）、`anim`（參數為 `kind/group/category/no`）三個指令，結果以 `ops_result` 回狀態列（失敗時帶原因）。

### 7.1 1 對 1 量表（開發版街區）

`Tools\lua\lua.exe Tools\run_street_social_development.lua -Editor -Control -Sandbox EMod4 -PortBase 48130 -Heroine 1 -NoCloud`（控制埠 48140），`hscene open=1`：

- 宿主進 `street/pair` 模式，3 個 mod：subtitles、pair_counter、pair-gauges。
- `pair.ready` 的 payload：`"card":"…/StreetHeroines/jeanne_alter.png","her_gauge":0,"his_gauge":0,"inserted":false`；pair-gauges 回 `{"pair": {"her": 77, "his": 33}}`，trace「gauges her=77 his=33 set」。
- 約 4 秒後 `hscene` 讀到她 64.0、他 20.0：兩條都正好少 13，等於閒置時每秒 3 的衰減（`OKHScene.cpp` 1883 行），沒有 mod 時從 0 開始只會停在 0，所以設定確實生效。
- 按「摸胸部」後的 `pair.note` 帶 `her 3.0 his 0.0 inserted false`（量表跟著場景走）。
- **街區開的 1 對 1**：`pair.enter` 的 `card` 仍是空的（街區先開 1 對 1、之後才載入她，控制器那時也還沒有卡路徑）；`pair.ready` 起都有卡。pair-counter 本來就以第一個帶卡的事件補上，行為不變；`5d4ae8b0c` 從控制器補卡的那一行在這條路徑上沒有作用，留著給控制器先有卡的情況。
- `ok.PairModBridgeSelfTest`（遊戲內）：0 failed of 23。

### 7.2 Studio 的 FK／IK／動作

新場景放 C000（#2），選取後依序執行：

| 指令 | 物件資料 | undo 步驟 |
|---|---|---|
| `tilt` | `fk: cf_j_neck (0, 0, 20)` | 1 → 2 |
| `reach` | `ik: 3 (30, -20, 140)` | 2 → 3 |
| `anim 0/0/10/1`（あくび） | `studioAnime 0/0/10/1`，`character_changed` 報 `animation` | 3 → 4 |
| `tilt cf_J_ArmUp00_L`（錯骨名） | 狀態列「tilt 沒做成：unknown FK bone …」，什麼都沒改 | 仍是 4 |

undo 三步依序拿掉動作、IK、FK，redo 三步依序回來，每一步讀回的資料都對。畫面：前 `E:\OpenKoikatsu\Saved\OKControl\shots\emod4b_0_before.png`、FK＋IK `E:\OpenKoikatsu\Saved\OKControl\shots\emod4b_1_fkik.png`（身體前彎、頭偏）、動作 `E:\OpenKoikatsu\Saved\OKControl\shots\emod4b_2_anim.png`、undo 後 `E:\OpenKoikatsu\Saved\OKControl\shots\emod4b_3_undone.png`、redo 後 `E:\OpenKoikatsu\Saved\OKControl\shots\emod4b_4_redone.png`。

### 7.3 自動測試

| 測試 | 結果 |
|---|---|
| `OKStudio.ModBridgeSelfTest`（執行中的 Studio） | 0 failed of 29 |
| `ok.PairModBridgeSelfTest`（執行中的街區） | 0 failed of 23 |
| UE Automation `OpenKoikatsu.Interaction.ModEvents`、`OpenKoikatsu.Studio.ModData`、`OpenKoikatsu.Gallery.EditorMods`、`OpenKoikatsu.Gallery.EditorModsCoordinates`（`UnrealEditor-Cmd -NullRHI`，log `E:\OpenKoikatsu\Saved\Logs\emod4-automation.log`） | 4 個都 Success |
| `cargo test -j 8`（`Tools/ok-mod`，含新 fixture） | 全過 |

沒發現新 bug。拖曳與打包版照協調者安排留到乾淨 stage 測試。
