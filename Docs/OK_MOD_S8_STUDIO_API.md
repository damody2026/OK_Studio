# OK mod 工作項 8：Studio API 與範例（E 組）

計畫：`Docs/OK_MOD_FRAMEWORK_PLAN.md` §15.4 工作項 8。前置（工作項 5）見 [OK_MOD_S5_STUDIO_PREREQ.md](OK_MOD_S5_STUDIO_PREREQ.md)。

## 做了什麼

把工作項 5 的 Studio 登錄點（`Plugins/OKStudio` `OKStudioMod.h`）接到 mod 宿主（`ok_mod_host.dll`，`FOKModHost`）：場景控制器（場景存讀、匯入、複製、刪除、選取事件與 mod 自己的場景資料）、面板列（狀態頁、畫面設定頁）、工具列按鈕、物件樹右鍵選單、指令、時間軸（可內插值、標記經過事件、跳時間）、計時器、按鍵與拖曳事件。另寫四個範例 mod。

**呼叫一律走通用掛點**（統籌 2026-11-23 決定）：ok-mod-api 的 `Event::Hook { name, payload }`（payload 為 JSON，mod 以 `Declaration::Subscribe("<hook 名>")` 訂閱，回 `Reply::Json`），宿主 `okm_dispatch` 的 `{"op":"hook","hook","payload","mods"}`。這兩樣由 C 實作、cherry-pick 到 E；本組沒有改 `Tools/ok-mod/api`、`sdk` 的型別。

### 程式

| 位置 | 內容 |
|---|---|
| `Plugins/OKStudio/.../OKStudioMod.h/.cpp` | 登錄點加場景事件：`SceneEventSink`、`NotifySceneLoad`（load／clear／import，import 附舊 id→新 id 對照與匯入場景的 mods）、`NotifySceneSave`、`NotifyObjectsCopied`、`NotifyObjectsDeleted`、`NotifySelected`；`ShowStatus`（mod 的狀態列文字）。沒有接收者時什麼都不做。 |
| `OKSceneDocument.cpp`、`OKStudioGame.cpp`、`SOKStudioPanel.h`、`SOKStudioMod.cpp` | 在刪除、複製、貼上、合併匯入、選取、存檔、開檔、新場景各加一行通知；面板開著時把 `ShowStatus` 接到狀態列。 |
| `Source/OpenKoikatsu/OKStudioModBridge.cpp`（新） | 橋接：Studio 開啟且宿主開著時，對每個已啟用的 mod 送 `studio.panel_ui`，有回覆的就登錄；之後把指令、場景事件、按鍵、拖曳、計時器、時間軸標記以 hook 送給 mod，套用回覆的效果。主控台指令 `OKStudio.ModReload`（重新登錄）、`OKStudio.ModTrace`（列出最近的呼叫與回覆）。 |
| `Tools/ok-mod/studio`（新 crate `ok-mod-studio`） | Rust 端協定小工具：`Call::parse` 讀呼叫內容，`Ui`／`Effect` 組回覆。 |
| `Tools/ok-mod/examples/object-hotkeys`、`studio-autosave`、`scene-notes`、`timeline-flow`（新） | 四個範例。 |

## Studio 協定 1

mod 訂閱要收的 hook。橋接一次只送一個 mod（`"mods": [id]`，因為內容含該 mod 自己的資料），`payload` 是 JSON 物件，含 `"studio": 1` 與 `"event"`；mod 回 `Reply::Json`（效果），回 `Reply::Text` 視為狀態列文字。沒訂閱（沒有回覆）就略過。

| hook | 何時 |
|---|---|
| `studio.panel_ui` | Studio 開啟（或 `OKStudio.ModReload`）時要登錄內容，回覆見「登錄」 |
| `studio.command` | 執行 mod 登錄的指令（`name`、`arg`） |
| `studio.scene_load`、`studio.scene_save`、`studio.objects_copied`、`studio.object_deleted`、`studio.objects_selected` | 場景事件 |
| `studio.timeline_event` | 時間軸標記經過 |
| `studio.panel_control` | 綁定資料的面板列被改 |
| `key.<id>` | 登錄的按鍵（`event` 為 `key` 或拖曳的 `drag`） |
| `timer.<id>` | 登錄的計時器 |

宿主（`ok_mod_host.h`，C 的 be18a313c，E 為 cf0861043）：`payload` 送 JSON 物件，回覆 `{"replies": [{"mod", "ok", "json"｜"text"｜"error"}]}`，橋接取該 mod 那筆。mod 沒訂閱的 hook 宿主回 `did not subscribe`：橋接記下，之後不再送（連內容都不建）。出錯後查宿主清單，mod 不再是 `enabled`（panic 後為 faulted）就從 Studio 移除。

### 呼叫內容（context）

| 欄位 | 說明 |
|---|---|
| `studio` | 協定版本，目前 1（`studio_ui` 另有 `protocol`）。 |
| `data`、`data_version` | 這個 mod 在場景 `mods` 裡自己的資料（存成 JSON 文字，傳過來時已解析），沒有就是 null／0。 |
| `selection`、`primary` | 選取的物件 id 與主要物件。 |
| `time`、`duration`、`playing` | 時間軸播放頭、長度、是否播放中。 |
| `dirty`、`scene_file` | 場景是否有未存的修改、目前檔案。 |
| `objects` | 只有登錄時要求 `objects: true` 才有：`[{id, kind, name, parent, visible}]`。 |
| `arg` | 指令的參數（工具列按鈕、選單、`run` 給的）。 |
| `event` 與事件欄位 | 見下表。 |

| `event` | 額外欄位 | 何時 |
|---|---|---|
| `scene_load` | `kind`（`load`／`clear`／`import`）；import 另有 `map`（`{"舊id": 新id}`）與 `imported_data`（被匯入場景裡這個 mod 的資料） | 開檔、新場景、合併匯入之後 |
| `scene_save` | — | 存檔寫入前（回覆的資料會一起存進檔案） |
| `objects_copied` | `map` | 複製、貼上之後 |
| `objects_deleted` | `ids`（含子物件） | 刪除之後 |
| `objects_selected` | `ids`、`primary` | 選取改變 |
| `key` | `id`、`down`、`shift` | 登錄的按鍵按下／放開（文字框有焦點時不送） |
| `drag` | `id`、`dx`、`dy`、`shift` | 按住登錄為拖曳的鍵時移動滑鼠（每幀合併一次） |
| `timer` | `id` | 登錄的計時器到時 |
| `timeline_pass` | `marks`（經過的標記索引，早的在前）、`from` | 播放中播放頭經過 `timeline_marks` 指到的標記（含循環折返） |
| `control` | `id`、`object`、`value` | 綁定資料的面板列被改（mod 有訂閱時） |

收不收事件由 mod 的訂閱決定（宿主過濾）。

### `studio_ui` 回覆（登錄）

| 欄位 | 內容 |
|---|---|
| `commands` | `[{name, label}]`：成為 Studio 指令 `mod.<id>.<name>`（指令表、控制通道 `cmd` 都能跑），執行時送 `studio.command`。 |
| `toolbar` | `[{id, label, tooltip, command, arg}]`：上方工具列按鈕。 |
| `menu` | `[{id, label, command, arg, kinds}]`：物件樹右鍵選單；`kinds` 限定主要物件種類（folder／character／item／light／camera／effect／model）。 |
| `controls` | `[{id, label, panel: "state"｜"scene", kind, min, max, step, options, bind, command, arg}]`：面板列；`kind` 為 toggle／slider／dropdown／color／text／button。 |
| `interpolables` | `[{id, label, bind, per_object, kinds}]`：時間軸可內插值。 |
| `keys` | `[{id, key: "Ctrl+Shift+G" 形式, drag}]` |
| `timers` | `[{id, ms}]`（最短 50 ms） |
| `timeline_marks` | mod 資料裡標記陣列的路徑（元素是秒數，或含 `time` 的物件）。 |
| `objects` | 呼叫內容要不要帶物件清單。 |

`label`、`tooltip`、`options` 可以寫文字 id（`mod.<id>.…`），橋接從 mod 資料夾的 `locale/<語言>/*.toml` 查（目前語言 → zh-TW → zh-CN → en），查不到就照字面顯示。

**綁定（`bind`）**：點分路徑指到 mod 資料裡的值，`{object}` 換成物件 id（例如 `notes.{object}`）。面板列的讀寫與時間軸的取樣／套用都在橋接裡直接讀寫資料，不呼叫 mod，所以 Studio 的復原／重做（整份文件快照）會連 mod 資料一起回復；拖滑桿、播放時間軸也不會每幀呼叫 mod。toggle 存成布林、slider／dropdown 存成數字、其他存字串，清空的文字會刪掉該鍵。

### 效果（回覆）

| 欄位 | 作用 |
|---|---|
| `data`、`data_version` | 取代這個 mod 的場景資料（`null` 刪除）；`clear_data: true` 也刪除。 |
| `status` | 狀態列文字。 |
| `select` | 改選取（最後一個為主要）。 |
| `run` | `[{command, arg}]`：依序執行 Studio 指令（核心或其他 mod 的）。 |
| `timeline` | `{time, playing}`：移動播放頭、播放／停止。 |
| `nudge` | `{move_view: [右, 上, 前], rotate: [pitch, yaw, roll], scale}`：對選取的根物件，依目前視角方向移動、在世界座標旋轉、等比縮放。 |
| `export` | `{name, keep}`：把目前場景另存一份到 `Saved/OKStudio/ModExports/<mod id>/<name>.okscene`（名稱只留英數、`-`、`_`），資料夾只留最新 `keep` 份（1–100）。 |

復原的單位：指令（工具列、選單、指令表、`cmd`）本來就在 `RunCommand` 的一步裡；按鍵、計時器事件各自包成一步；拖曳不另開步驟（連續的修改併成一步）；場景事件的回覆在引起它的那一步裡。場景事件的回覆只有資料立刻套用，其他效果（選取、`run`、播放頭、nudge、匯出）延到下一幀，避免在刪除／匯入進行中改動文件。

mod 回錯誤會顯示在狀態列；mod 被停用或 panic 後橋接把它從 Studio 移除（登錄的按鈕、列、選單一起消失），場景裡它的資料保留。

## 範例

| 範例 | id | 做什麼 |
|---|---|---|
| object-hotkeys | `org.openkoikatsu.object_hotkeys` | 設定的三個鍵（預設 V／B／N，`speed` 0.5）：按住拖曳滑鼠移動（V，Shift 改前後）、旋轉（B）、縮放（N）選取物件；用 `nudge` 效果。 |
| studio-autosave | `org.openkoikatsu.studio_autosave` | 每 60 秒檢查；場景有未存修改且離上次備份滿 `minutes` 分鐘就用 `export` 另存 `autosave-<UTC 時間>`，留 `keep` 份；指令 `save_now` 與工具列「備」。 |
| scene-notes | `org.openkoikatsu.scene_notes` | 每個物件一則註記（`{"notes": {"<id>": "文字"}}`）：狀態頁文字列綁 `notes.{object}`、右鍵選單新增／刪除、工具列「註」跳到下一個有註記的物件；複製時跟著複製、刪除時清掉、匯入時依 id 對照併入。 |
| timeline-flow | `org.openkoikatsu.timeline_flow` | 時間軸標記（`{"marks": [{time, kind, to}]}`）：工具列 A／B 設循環起訖、「跳」在播放頭放跳躍標記（跳到 `to`）、「停」放停止標記、「清」清空；播放經過標記時循環回 A、跳躍或停止。 |

建置：`cargo build -j 8 --release`（`Tools/ok-mod`），把各範例的 `mod.toml`、`locale/` 與 dll 放到 `Mods/<資料夾>/`。

另有 1 對 1（工作項 13）的轉送骨架 `Source/OpenKoikatsu/OKPairModBridge.cpp`：宿主開著時訂閱 `FOKInteractionModEvents`，每個事件以 `pair.enter`／`pair.ready`／`pair.exit`／`pair.note`／`pair.finish`／`pair.voice`／`pair.line` 送給所有訂閱的 mod（不帶 `mods`），payload `{"pair":1, "event", "card", "text", "path", "source", "row", "react", "cancelled", "seconds", "fitting"}`。回覆目前只記在 `ok.PairModTrace`；回覆能在 1 對 1 裡做什麼（字幕、計數顯示）留到範例時定。

## 驗證（2026-11-23）

- 建置：`OpenKoikatsuEditor`、`OpenKoikatsu` Development，E 引擎（`E:\PhysX\UE5.8`）每次提交前都建過，成功。`Tools/ok-mod`：`cargo build -j 8 --release --workspace`、`cargo test --workspace`（全部通過，含宿主 9 項整合測試）、`cargo check --no-default-features`。
- **真宿主實機**（Studio，`ok_mod_host.dll` 來自 `Tools/ok-mod/target/release`，四個範例裝在 `Mods/`）：四個 mod 都經 `studio.panel_ui` 登錄（指令表 9 個 `mod.*` 指令、7 顆工具列按鈕）；`scene_notes.add` 加註記 → 複製物件 → 工具列「註」顯示「備註 1／2」（複製事件把註記帶到新物件）；`timeline_flow.stop` 在 1.0 秒放停止標記，從 0 播放後停在 1.00；按 V 由 `key.move` 回狀態列「移動：移動滑鼠（放開鍵結束）」（locale 標籤也是）；`timer.minute` 會觸發。截圖 `E:\OpenKoikatsu\Saved\OKStudio\mcp_ui\mod8_toolbar.png`。
- **第二輪實機（統籌要求的補驗，2026-11-23）**：
  - 存檔重開：「甲物件」加備註 → 存成 `E:\OpenKoikatsu\UserData\Studio\scene\mod8_notes_a.png` → 開新場景（`next` 回「場景裡沒有備註」）→ 開回存檔，`next` 回「備註 1／1：甲物件：甲的備註」。
  - 匯入 id 對照：新場景先有「乙物件」(2)、「丙物件」(3)，乙加備註，再疊加 `mod8_notes_a.png`：`studio.scene_load`（import）回 `{"2": 乙的備註, "4": 甲的備註}`，甲物件匯入後是 id 4，備註跟著它；`next` 依序選到 4（甲）與 2（乙）。（備註文字帶引號，是 MCP `studio_cmd` 的 arg 用 JSON 傳字串造成的，不是 mod 的問題。）
  - timeline-flow 循環：0.5 秒放 A、1.5 秒放 B，從 0 播放 4 秒以上，播放頭一直在 0.98～1.31 之間。
  - studio-autosave：用 `mod.call {"op":"config_set",…,"key":"minutes","value":1}` 改成 1 分鐘，場景有未存修改時 `timer.minute` 寫出 `E:\OpenKoikatsu\Saved\OKStudio\ModExports\org.openkoikatsu.studio_autosave\autosave-20261122-190139.okscene`（含 scene_notes 與 timeline_flow 的 mods 資料），狀態列「已自動備份 … （保留最新 5 份）」。
  - zh-TW：四個範例加了 `locale/zh-TW`，右鍵選單顯示「加備註／刪除備註」（截圖 `E:\OpenKoikatsu\Saved\OKStudio\mcp_ui\mod8_menu_zhtw.png`）。
- 實機發現：mod 工具列按鈕接在固定寬的上方工具列後面，全被裁到視窗外（`ui_widgets` 有、畫面沒有），改成上方工具列左邊自己一列（提交 f792ce205）；每次選取都對沒訂閱的 mod 白送一次 hook，加了 NotSubscribed 快取。
- `OKStudio.ModBridgeSelfTest`（`Source/OpenKoikatsu/OKStudioModBridgeTest.cpp`）：在執行中的 Studio（`SceneEditor`，`-NoBuild`）用 C++ 假 mod 取代宿主，**29/29 通過**（`Saved/OKStudio/mod_bridge_selftest.txt`）。項目：`studio.panel_ui` 登錄 7 指令、工具列、右鍵選單（限資料夾）、2 面板列、1 可內插值；`studio.objects_selected`；文字列寫 `notes.<id>`、`studio.panel_control`、復原清掉、重做回來；滑桿列存數字；指令表執行 mod 指令；效果 data／data_version／status／timeline／run／select／export；`key.<id>` nudge 沿視角 10；拖曳縮放；`timer.<id>`；`studio.objects_copied` 複製註記、`studio.object_deleted` 刪除；播放經過標記送 `studio.timeline_event` 並停止播放；可內插值 Apply／Sample；panic 的 mod 離開 Studio、場景資料保留。
- 第一次跑 26/29：重做失敗與連帶的複製失敗是測試沒有像面板一樣 `NotifyChanged`；「panic 的 mod 離開」失敗是橋接在 mod 自己的指令執行中就移除登錄（刪掉正在跑的 `TFunction`），已改成下一幀移除（提交 786595702）。
- `ok.PairModBridgeSelfTest`：假宿主收到 7 種事件對應的 `pair.*` hook 與 payload 欄位，**17/17 通過**（`Saved/OKInteraction/pair_mod_bridge_selftest.txt`）。

## 第三波：四個 Studio 範例一起開（2026-11-23，同步點 B 之後）

`Mods/` 裝 object-hotkeys、scene-notes、studio-autosave、timeline-flow（加上非 Studio 的 pair-counter、subtitles），`studio_launch no_build`：

- **共存**：log 為 `mode studio: 4 mod(s) enabled`，四個各自 `joined the studio`：object-hotkeys 3 鍵、studio-autosave 1 計時器。指令表同時有三個 mod 的 9 個指令，互不干擾。選取時四個都沒訂閱 `studio.objects_selected`，各回一次「did not subscribe」，之後就不再送。
- **各自的資料**：選角色後 scene-notes `add`（寫 `notes.2`）、timeline-flow `loop_start`（寫 `marks`）、studio-autosave `save_now`（匯出 okscene）。匯出檔的 `mods` 有前兩個 mod 的資料，各在自己的鍵下。
- **復原／重做**：復原兩步後存檔（`E:\OpenKoikatsu\UserData\Studio\scene\emod8_undo.png`），重開後匯出的 okscene 沒有 `mods`（備註與迴圈標記都回復掉了）。重做兩步後存檔（`emod8_redo.png`），重開後 `{"notes":{"2":"E組共存測試"}}` 與 `{"marks":[{"kind":"loop_start","time":0}]}` 都在。
- **存讀檔**：上面兩個檔都是存檔、在同一個 Studio 裡重開後再匯出比對，兩個 mod 的資料都照存照讀。
- F 的 toon-post 還沒有（F 的檢出只有 skin-decal），等 F 做好再一起開。

## 沒驗證的

- object-hotkeys 的拖曳：按鍵經過真的 Slate 前處理器（`studio_key V`），但按住鍵同時移動滑鼠沒辦法用控制通道做，移動／旋轉／縮放只在自我測試（直接呼叫橋接）驗過；文字框有焦點時不送按鍵也沒測。
- studio-autosave 的 `keep` 份數修剪（`save_now` 指令第三波已實機用過）。
- timeline-flow 的跳躍標記；scene-notes 的狀態頁文字列畫面、刪除備註。
- 1 對 1：已實機驗證，見 [OK_MOD_S13_PAIR.md](OK_MOD_S13_PAIR.md)。
- 第三波：object-hotkeys 的拖曳仍不能用控制通道做（`studio_key` 是按下立刻放開，狀態列停在「移動：移動滑鼠（放開鍵結束）」）；和 F 的 toon-post 一起開還沒做。

## 狀態

通用 Hook 已 cherry-pick（cf0861043）；`ok-mod-studio` 與四個範例改為訂閱 hook（提交 8cf131fc6），工作項 8 的程式部分完成。工作項 13 目前只有 UE 側轉送骨架（`pair.*`），範例 pair-counter 與 subtitles 的 1 對 1 部分等統籌回覆後做。
