# OK mod 工作項 5：OK Studio 前置（2026-11-23，E 組）

計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §6.5、§15.4 第 5 項。檢出 `E:\OpenKoikatsu`（master），引擎 `E:\PhysX\UE5.8`。

## 提交

| 提交 | 內容 |
|---|---|
| `6854f5669` | `.okscene` 加 `mods` 欄位（FormatVersion 4） |
| `5f995a2be` | mod 外部登記介面：指令、工具列、右鍵選單、狀態／畫面設定面板、時間軸 |
| `ee41db573` | 測試：`OpenKoikatsu.Studio.ModData`（自動化）、`OKStudio.ModSelfTest`（執行中的 Studio） |

## 做了什麼

### 1. 場景的 mod 資料（`OKSceneDocumentMods.cpp`）

- `UOKSceneDocument::Mods`：`TMap<FString, FOKSceneModData>`，鍵是 mod id，值是 `{ Version, Data(base64) }`，對應計畫 §6.2 的 `okMx` scene 範圍。
- 檔案格式：

  ```json
  "mods": { "<mod id>": { "version": 3, "data": "AAEC/w==" } }
  ```

- 有 mod 資料時寫成 version 4；沒有時照舊寫成 1～3，舊版程式仍讀得到這些場景。讀取上限 `FormatVersion` 改成 4，5 以上拒絕。
- 沒裝的 mod 的資料原樣寫回。格式壞的單一項目會丟掉並寫警告，場景照開。
- 寫出時 id 排序：undo 比對的是整份文件的 JSON 文字，順序固定才不會多出假的步驟。
- 存在文件裡，所以存檔、場景卡、undo／redo（整份文件快照）、未存檔標記都自動包含，mod 不用回傳 do／undo（盤點 §5.6）。
- 新場景（`scene.new`）清空 `Mods`。讀另一個沒有 `mods` 的場景也會清空。
- API：`GetModData`／`SetModData`／`RemoveModData`。

### 2. 外部登記介面（`Public/OKStudioMod.h`、`OKStudioMod.cpp`、`SOKStudioMod.cpp`）

`FOKStudioModRegistry::Get()` 是單一登記處，只在 game thread 使用。工作項 8 會讓 UE 宿主（OKModding）依各 mod 在 `register()` 宣告的內容填進來；目前用 C++ 測試登記。

| 登記 | 在 Studio 的哪裡 | 對應 KKAPI |
|---|---|---|
| `AddCommand` | 指令表，id 為 `mod.<mod id>.<名稱>`；`RunCommand` 照舊包成一個 undo 步驟；`OKStudio.Cmd`、控制通道 `cmd`（MCP `studio_cmd`）都叫得到 | — |
| `AddToolbarButton` | 頂端工具列最右邊，標籤 `ModTool_<id>.<名稱>` | `ToolbarManager` |
| `AddMenuItem` | 物件樹右鍵選單最下方，可設顯示條件，標籤 `ModMenu_<id>.<名稱>` | `StudioContextMenus` |
| `AddControl`（`CurrentState`） | 角色「狀態」頁最下方，以「Mod：<id>」分組 | `CurrentStateCategory` |
| `AddControl`（`SceneEffects`） | 「畫面設定 › 相機」分頁最下方 | `SceneEffectsCategory` |
| `AddInterpolable` | 時間軸：軌道 `Owner = "mod.<id>"`。宿主在兩個關鍵幀間線性插值後交給 mod 的 `Apply`；打新關鍵幀時用 `Sample` 取目前值；「添加插值軌」選單列出 mod 的值 | `TimelineCompatibility` |
| `RemoveOwner` | mod 被停用時移除它登記的全部項目 | — |

- 控制項種類：Toggle、Slider、Dropdown、Color、Text、Button。值一律以文字傳遞，方便之後跨 ABI。
- 控制項的 `Set` 回傳 true 時，面板呼叫 `NotifyChanged`，這次改動成為一個 undo 步驟。
- 指令的 `Run` 自己透過文件修改並呼叫 `NotifyChanged`（和其他 Studio 編輯相同）；沒改到東西就不會留下步驟。
- 執行中登記或移除時，指令表（`RunCommand` 前同步）、工具列與開著的狀態／畫面設定頁會自動更新。
- 已移除的 mod：指令失敗，面板列消失；它的時間軸軌道保留在文件裡、不動作，它的場景資料也保留。
- id 規則：
  - mod id：英數加 `.`、`_`、`-`（反向網域，同 `mod.toml` 的 `id`）；
  - 名稱：英數加 `_`、`-`，不能有 `.`，這樣 `mod.<id>.<名稱>` 才能拆開；
  - 重複登記會被拒絕並寫 log。

### 3. 既有檔案的改動（都只加一行呼叫或宣告）

- `OKSceneDocument.cpp`：版本號、`WriteMods`、`ReadMods`、`EvaluateTimeline` 的 mod 軌、`SampleCurrentTimelineValue` 的 mod 軌、include。
- `SOKStudioPanel.h`：成員宣告（一個區塊）、`RunCommand` 前同步、`scene.new` 清空、工具列、狀態頁。
- `SOKStudioWindows.cpp`：右鍵選單、「添加插值軌」選單。
- `SOKStudioBrowsers.cpp`：畫面設定相機分頁。

## 驗了什麼

- 建置：`OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 都在 `E:\PhysX\UE5.8` 建置成功。
- `OpenKoikatsu.Studio.ModData`（UnrealEditor-Cmd，NullRHI）：**通過**。驗了：
  - 沒有 mod 資料的場景仍寫成第 1 版、不帶 `mods`；
  - 寫入二進位與文字資料後是第 4 版，讀回位元組相同，再寫一次文字完全相同；
  - 未知 mod 的項目（version 7、`AAEC/w==`）原樣寫回；
  - 壞項目被丟掉、場景照開；
  - 讀沒有 `mods` 的場景會清空 `Mods`；
  - 第 5 版被拒絕；
  - 本機 `UserData/Studio/scene` 的 64 個舊 `.okscene` 全部能開，寫回時不帶 `mods`、版本不超過 3；
  - 登記檢查：mod id 有空白、名稱帶點、重複登記都被拒絕；
  - mod 時間軸軌：在 0 秒與 1 秒各打一個關鍵幀（0、10），0.5 秒播放時得到 5；
  - 移除 mod 後：登記清空，軌道不動作且仍存在。
- `OKStudio.ModSelfTest`（SceneEditor 實際執行，MCP `studio_launch` 加 `ui_exec`）：**14/14**，結果在 `E:\OpenKoikatsu\Saved\OKStudio\mod_selftest.txt`。驗了：
  - mod 指令從指令表執行；undo 清掉、redo 還原，是一個步驟；未登記的指令失敗；
  - 工具列按鈕（模擬點擊）執行指令；
  - 右鍵選單項執行指令；
  - 狀態頁出現 mod 的 Toggle 列，切換後寫入該角色的資料，undo 清掉；
  - 畫面設定出現 mod 的 Slider 列；
  - 存成場景卡、開新場景（資料清空）、再讀回，資料都在；
  - 移除 mod 後指令消失，資料保留。

## 沒驗什麼

- 沒有實際接上 mod DLL 宿主：那是工作項 8，要等同步點 A 之後才能編譯依賴 F 的 `Tools/ok-mod`。
- 沒看畫面：沒有截圖確認工具列按鈕、面板列的版面與樣式，只用程式確認元件存在、點得到。
- Dropdown、Color、Text、Button 四種面板列只寫了程式，自我測試只跑了 Toggle 和 Slider。
- 時間軸 mod 軌只在自動化測試用文件層級驗過，沒有在 Studio 時間軸視窗裡實際加軌並播放。
- 「追加場景」（`Merge`）與貼上片段時，匯入那份場景的 mod 資料不會合進來：目前保留現有場景的資料。計畫裡新舊 id 對照與 `on_scene_load(Import)` 屬於工作項 8。
- 姿勢檔的 mod 資料：計畫 §6.5 已定為延後。
- 編輯器內的 Studio（`OKStudioEditor`）只確認編譯通過，沒有實際操作。

## 順帶發現（沒改）

- `scene.tab` 指令把分頁夾在 0～7，可是畫面設定有 9 個分頁（第 8 個是「預設」），用指令到不了「預設」分頁。和 mod 無關，留給 Studio UI 的負責人。
