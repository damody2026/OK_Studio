# OK Mod 第六波（F 組）：打包版的 DreamGUI global shader、game_stop、Studio 打包版（2026-11-23）

協調者在第五波回報後指派。檢出 `F:\OpenKoikatsu`（`master`），引擎 `F:\UE5.8`，名額 `f-mod-6`。沒有推送；E 改的 `OKModKeys.cpp` 那一行沒動。

## 提交

| 提交 | 內容 |
|---|---|
| `f99921be0` | stage 自帶 runtime patch：打包版不再被舊的共享 patch 蓋掉 global shader |
| `09960cf27` | `ok-game-mcp` `game_stop`：等進程真的結束再回報，逾時就強制結束 |
| （本回報同批） | 本回報、`Docs/ERROR_LOG.md` |

## 1. DreamGUI global shader 不在打包版

### 原因

- 讀卡器打開新畫面前會檢查 DreamGUI 的 global shader（`DreamUIShaderGate.cpp`）。不在時，畫面紅字要人跑 `Tools/rebuild_street_social_patch.lua`。
- 第五波的 stage 是**新 cook 的 base**，裡面本來就有 DreamGUI 的 global shader。但打包版啟動時，啟動器另外掛了 `Launch/runtime.json` 指定的**共享 patch**（F 是 `Saved/StreetSocial/Build/NH1115.patch`，2026-11-17 做的）。
- 它的 `RuntimeGlobalShaderPatch-*_P.pak` 帶一份完整的 global shader map，`_P` 優先，蓋掉了 base 的那份。那份做在 DreamGUI 加進來之前，所以 DreamGUI 的 shader 不見了。
- 人群 rig（`KKCrowdGpuPacking`）的 global shader 有同樣的問題：用的是共享 patch 那時的版本。
- 所以光是 cook 一個新 base 不夠。共享 patch 會一直落後，靠人記得重做也不可靠。

### 修法（`f99921be0`，全在 F 擁有的 staging 腳本）

- **`rebuild_street_social_runtime.lua`**：完整流程多第 5 步，用 `rebuild_street_social_patch.lua --output` 在 `<tag>.stage/Patch` 做**這個 stage 自己的** patch（material、audio、global shader 三個 pak）。
  - 它和 base 用同一個編輯器建置，`--skip-patch` 可省。
  - 這一步要開 Unreal cook，在 F 約 4 分鐘。
- **`street_stage.lua`**：新增 `own_patch(exe)`、`patch_for(root, exe, launch)`。stage 有自己的 `Patch/`（裡面有 `.pak`）就用它，否則照舊用 `runtime.json` 的共享 patch。
  - `packaged_launch` 改用 `patch_for`，讀卡器（`run_card_reader_development.lua`）、Studio（`run_scene_editor.lua`）都經它。
- **`run_street_social_development.lua`**（StreetSocial.cmd、`game_launch`）：選好 stage 後同樣用 `patch_for`；`-PatchDir` 仍然優先。
- **`package_street_social.lua`**：stage 有自己的 patch 就把它打進包（`<stage>/Patch`），玩家那邊的啟動器會用它；沒有就照舊打共享 patch。
- 沒有改 C 的檔案，也沒有改 `runtime.json`。舊的 stage 沒有 `Patch/`，照舊用共享 patch。

### 實測（`ModInstallF5.stage`）

跑 `--skip-exe --skip-cook --skip-base`，只重做 stage 與 patch：

```powershell
F:\OpenKoikatsu\Tools\lua\lua.exe F:\OpenKoikatsu\Tools\rebuild_street_social_runtime.lua --tag ModInstallF5 --engine F:/UE5.8 --base-dir Saved/StreetSocial/BaseF5 --skip-exe --skip-cook --skip-base
```

| 模式 | 結果 |
|---|---|
| 讀卡器（打包版） | 掛 `ModInstallF5.stage/Patch` 的三個 pak；**DreamGUI 新畫面開出來**；Mods 頁所有分頁都在；dream-panel 的 `.dui` 面板（「還沒打招呼／打招呼／歸零」）顯示 |
| Studio（打包版，`run_scene_editor.lua`） | 掛同一份 patch；mode studio 11 個 mod；toon-post 與 glass-shader 的 pak `content mounted`，`M_OKToonPost` ready；light_rig、scene_notes、timeline_flow 等的指令都在 `ui.commands` |
| 街區 | `game.log` 掛了 stage 的 3 個 patch pak |

截圖：

- `F:\OpenKoikatsu\Saved\OKControl\shots\f-mod-6\packaged-reader-new-screen.png`
- `F:\OpenKoikatsu\Saved\OKControl\shots\f-mod-6\packaged-reader-dreamgui-panel.png`

log：

- `F:\OpenKoikatsu\Saved\f-mod-5\rebuild-patch.log`
- `F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-111323-0715ebee.log`
- `F:\OpenKoikatsu\Saved\Logs\SceneEditor\20261123-111406-2bebb4d1.log`

**沒驗**：

- `package_street_social.lua` 的改動只確認能載入，沒有實際打一個包。
- `run_crowd_*.lua`（百人房間等）仍讀 `runtime.json` 的共享 patch，沒改；它們不跑 stage，或另有自己的流程。

## 2. game_stop 回 stopped 但進程還在（`09960cf27`）

- 原因：`Tools/ok-game-mcp/src/game.rs` 的 `stop` 只送 `taskkill /PID`（沒有 `/F`，只是請視窗關閉），送完就回 `stopped`；遊戲其實還在關。
- 修法：
  1. 先請它關閉，最多等 20 秒；
  2. 還在就 CIM `Terminate`，再等 15 秒；
  3. 回 `how`（`closed`／`terminated after the close request did not end it`）與秒數；仍在就回錯。
  - 工具說明同步更新。`reader.rs` 的 `alive`／`powershell` 改成 `pub(crate)` 共用。
- 實測：街區打包版。用新編的 `ok-game-mcp.exe call game_stop`，回 `how: closed`、5.9 秒，之後 `tasklist` 已沒有那個 pid。
  - 新的執行檔編在 `Tools/ok-game-mcp/target/f-mod-6/`：`target/release/ok-game-mcp.exe` 正被執行中的 MCP 鎖住，覆蓋不了。
  - **各 session 重開 MCP 前要重建一次 release**：`cargo build --release -j 8`（`Tools/ok-game-mcp`）。

## 3. Studio 打包版：一次完整流程就夠

- **街區 stage 就能跑 Studio、1 對 1、toon-post**：
  - 街區 cook 本來就包含 `/Engine/Maps/Entry` 與 `Template_Default`（`Saved/Interaction/FreeTalk01Host/Saved/Cooked/Windows/Engine/Content/Maps/`）；
  - OKStudio 沒有要 cook 的內容；
  - `run_scene_editor.lua` 本來就接受街區 stage（`street_stage.newest(..., "any")`）；
  - 1 對 1 從讀卡器或街區進入；toon-post 是 mod 的 pak，跟 cook 無關。
  - 上面第 1 節已在同一個 stage 實際開了 Studio。
- 最後整合只要跑一次（先建編輯器）：

  ```powershell
  F:\OpenKoikatsu\Tools\lua\lua.exe F:\OpenKoikatsu\Tools\rebuild_street_social_runtime.lua --tag <新 tag> --base-dir Saved/StreetSocial/<新 base>
  ```

  不帶 `--skip-*`，換引擎建置時用新的 `--base-dir`。產出的 stage 自帶 patch，讀卡器、街區、Studio、1 對 1 都在它上面測。
- **`--studio` 只是較小的「純 Studio」包**：
  - 不 cook 街區與城市地圖，tag 必須以 `Studio` 開頭，StreetSocial.cmd 不會選它。
  - 要另給一個 `--base-dir`：base staging 會清掉並重放 base 裡的 pak，和街區共用 base 會把街區的 pak 換掉。
  - 只有要發純 Studio 包（`package_street_social.lua --studio`）時才需要。
- 以上寫進了 `rebuild_street_social_runtime.lua` 的檔頭說明。

## 給協調者

- 舊 stage（C 的 `BaseC1118A` 系列）沒有自己的 `Patch/`，仍掛 `runtime.json` 的共享 patch。最後整合用新流程做新 stage 就會自帶。
- 共享 patch（`runtime.json` 的 `patch`）要不要也跟著換新：由擁有 `runtime.json` 的一方決定。有了 stage 自帶的 patch，打包版已經不依賴它。

## 驗證

- `Tools/ok-game-mcp`：`cargo build --release` 與 `cargo test` 通過（另一個 target 目錄）。
- Lua：四個改到的腳本都能載入，並在上面的實測裡實際跑過，`package_street_social.lua` 除外。
- 沒改 C++，沒有建置 UE 的兩個目標。編輯器只為了 patch 的 cook 先建了一次（`Saved/f-mod-5/editor6.log`，成功）。
