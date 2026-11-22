# OK Mod 工作項 6：UE 宿主（2026-11-23，F 組）

對應 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md) §15.4 第 6 列（M0）。檔名用英文：commit hook 讀不了中文檔名（見工作項 1 回報）。

## 提交

| 提交 | 內容 |
|---|---|
| `547d00319` | `ok-mod-host`：一個行程可跑多個模式 |
| `e112b3a9a` | `ok-extract`：`ok_set_mod_dispatch`（新檔 `src/mod_forward.rs`，`lib.rs` 一行，`ok_extract.h` 宣告） |
| `fd325392c` | `Plugins/OKModding`、`Source/OpenKoikatsu/OKModModes.cpp`（新檔），`OpenKoikatsu.cpp`／`OKGameControl.cpp` 各一行，`OpenKoikatsu.Build.cs`、`OpenKoikatsu.uproject` |
| `6359436ab` | `ok-game-mcp`：`mod_call` 工具 |
| `081753689` | `Tools/stage_street_social.lua`：stage 帶上 `ok_mod_host.dll`，stage 根建 `Mods/` |

## 做了什麼

- **`Plugins/OKModding`（Runtime 模組）**：`FOKModHost` 照 `OKStreetRules.cpp` 的寫法 `LoadLibrary` `ok_mod_host.dll`、取 `okm_*`、檢查 `okm_abi_version`。找 DLL 的順序：`OK_MOD_HOST_DLL` → 執行檔旁 → `Tools/ok-mod/target/release/`。沒有 DLL 時寫一行警告，mod 關閉，遊戲照常。
  - 不用 import library，沒建過 Rust 宿主的 checkout 也編得過、跑得動。
- **`Mods/` 位置**：先看 `-ModsDir=`、`OK_MODS_DIR`；接著從執行檔往上找含 `stage.json` 的 stage 根，用它的 `Mods/`；都沒有就用 checkout 根的 `Mods/`。設定存在 `Mods/` 旁的 `UserData/config/mods/`（`OK_MODS_CONFIG_DIR` 可改）。
- **何時開宿主**：哪些 mod 載入取決於模式（`targets`），所以宿主在第一個遊戲模式開始時開（`EnterMode`），不在 `StartupModule` 開。`StartupModule` 只讀 `-NoMods`／Shift（`OKModStart`，`OpenKoikatsu.cpp` 一行）。
- **模式偵測**（`OKModModes.cpp`，不改 C／E 的檔案）：每個遊戲世界 BeginPlay 時判斷：
  - `AOKStudioGameMode` → studio；
  - `AOKInteractionPairGameMode` → pair；
  - 恰好是 `AOpenKoikatsuGameMode` → reader；
  - 其他模式在之後 120 幀內找到 `AOKStreetSocialScene` → street；
  - 世界清除時送 `mode_exit`。
- **一個行程跑多個模式**：街區交接到 1 對 1 在同一個行程。宿主改成記錄已跑過的模式清單；`mode_enter` 遇到新模式時，先補載以它為目標的 mod 再發事件，試過的 mod 不重試。
  - 1 對 1 從街區進入時世界不變，偵測不到；E 的工作項 13 要在 `OKInteractionMode` 進出處呼叫 `FOKModHost::Get().EnterMode(TEXT("pair"))`／`ExitMode`。
- **`-NoMods`／啟動時按住 Shift**：宿主 DLL 不載入，`ok_set_mod_dispatch` 不設，`/mod` 回 `mods are off`。
- **主控台指令**：
  - 核心指令 `mod.list`（每個 mod 的版本、狀態、原因）、`mod.call <JSON>`（原始請求）；
  - mod 宣告的指令在宿主開啟或補載後以 `IConsoleManager::RegisterConsoleCommand` 執行期登記成 `mod.<id>.<name>`，參數合併後傳給 mod，回覆印到主控台與 `LogOKMod`；
  - 關閉時取消登記。
- **log**：類別 `LogOKMod`，mod 的訊息前綴 `[mod id]`。
- **控制通道**：UI 通道加 `POST /mod`，body 就是 `okm_dispatch` 請求，回覆原樣傳回（`OKGameControl.cpp` 的路由表加一行 `OKModControlRoutes()`）。ok-game-mcp 加 `mod_call` 工具，沒給 `op` 時等於 `list`。
- **ok-extract 轉發**（盤點 §5.2）：遊戲內的 ok-extract 經 UE 的宿主送請求，不自己開宿主。
  - 計畫寫「`OkUnrealBindings` 加回呼」，實作改成獨立的 `ok_set_mod_dispatch(dispatch, free)`。原因：KKUnityBundle、KKRuntimePose、OKCrowdQuality 等好幾處各自呼叫 `ok_register_bindings`，每次覆寫整個結構，後呼叫的會把轉發清掉。
  - Rust 端 `crate::mod_forward::dispatch(json)`，沒設定時回 `None`（CLI、測試），可從任何執行緒呼叫（宿主內有鎖）。
- **staging**：`stage_street_social.lua` 先 `cargo build --release -p ok-mod-host`，把 `ok_mod_host.dll` 複製到 exe 旁，並在 stage 根建一般資料夾 `Mods/`（stage 其餘部分是 junction）。
- **啟動參數**：各啟動腳本本來就能把參數傳給遊戲，所以沒改。讀卡、Studio 用 `-- -NoMods`，街區用 `-GameArgs "-NoMods"`。

## 驗了什麼

- `cargo test -j 8`（`Tools/ok-mod`）：全部通過，整合測試多了 `entering_another_mode_loads_its_mods`（street → studio 補載 studio 專用 mod，兩個訂閱者都收到 `mode_enter`，重複進入不重載）。
- `Tools/ok-extract`：`cargo check -j 8` 與 `cargo check -j 8 --no-default-features` 通過，`mod_forward::tests::forwards_and_clears` 通過。
- ok-game-mcp：`cargo check --release` 通過。exe 正被這個 session 的 MCP 伺服器使用，沒能替換，新工具要等 MCP 重啟後的版本。
- **F:\UE5.8 建 `OpenKoikatsu` Win64 Development 與 `OpenKoikatsuEditor`：兩個都 `Result: Succeeded`**（日誌 `F:\OpenKoikatsu\Saved\ModKit\S6\game.log`、`F:\OpenKoikatsu\Saved\ModKit\S6\editor.log`）。
- **四個模式實際啟動**（UnrealEditor -game，`F:\OpenKoikatsu\Mods\hello` 裝了 release 版 hello，slot `f-mod-6`，用完已 release）。每個 log 都有：
  - `Mod host … mode <模式>`
  - `[org.openkoikatsu.hello] loaded Hello 0.1.0 (built with rustc 1.97.1 …)`
  - `hello from hello`
  - `mode <模式>: 1 mod(s) enabled: org.openkoikatsu.hello`
  - `entered mode <模式>`

| 模式 | 啟動 | log |
|---|---|---|
| 讀卡 | `run_card_reader_development.lua -NoBuild` | `F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-013026-38b18134.log` |
| Studio | `run_scene_editor.lua -NoBuild` | `F:\OpenKoikatsu\Saved\Logs\SceneEditor\20261123-013434-0b83d7af.log` |
| 1 對 1 | `run_interaction_pair.lua` | `F:\OpenKoikatsu\Saved\Logs\InteractionPair-20261123-013453.log` |
| 街區 | `run_street_social_development.lua -Editor -Sandbox ModTest -NoCloud -Heroine 1` | `F:\OpenKoikatsu\Saved\StreetSocial\Play-20261123T013515\game.log` |

- 讀卡模式下用 UI 通道實測：
  - `mod.list` 印出 `Mod host 0.1.0 (ok-mod-api 0.1.0), modes reader, 1 mod(s)…  org.openkoikatsu.hello 0.1.0: enabled`；
  - 主控台 `mod.org.openkoikatsu.hello.ping from console` 回 `pong 1 (hello) from console`；
  - `POST /mod {"op":"command",…}` 回 `{"ok":true,"text":"pong 2 (hello) via /mod"}`；
  - `{"op":"config"}` 回出 `greeting` 設定項。
- **`-NoMods`**（讀卡，`-- -NoMods`）：log 只有 `Mods are off for this run (-NoMods)`，沒有載入宿主 DLL；`mod.list` 回「Mods are off」，`/mod` 回 `{"ok":false,"error":"mods are off (-NoMods)"}`。log：`F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-013405-7997e47f.log`。

## 沒驗什麼

- **打包的 stage 沒跑**：`stage_street_social.lua` 的改動沒有實際執行（F 沒有街區 stage；完整打包留給整合）。四個模式都是 UnrealEditor -game。
- **按住 Shift 跳過**沒實測，只實測了 `-NoMods`。
- **`-NoMods` 與現在完全相同**：只確認宿主 DLL 沒載入、沒有任何 mod 程式執行。沒做效能或畫面逐像素比對；`OKModStart` 在 `-NoMods` 時連世界委派都不掛。
- **遊戲內 ok-extract 經轉發呼叫宿主**：目前 ok-extract 裡還沒有掛點呼叫 `mod_forward::dispatch`（工作項 7／9 才有），只驗了 Rust 單元測試與遊戲連結成功。另外，編輯器的模組化建置裡 `ok_extract.lib` 分別連進好幾個模組，各自有一份 static；`OKModModes.cpp` 設的是遊戲模組那份。單體的打包遊戲只有一份，沒有這個問題。工作項 9 在 KKUnityBundle 的開卡路徑用到轉發時，要在那個模組也設一次。
- **從街區進 1 對 1 的 `pair` 事件**：要 E 的工作項 13 在 `OKInteractionMode` 呼叫。
- **mod 指令的自動補全與說明文字**：說明只是 `Mod command (mod.<id>.<name>)`，還沒接 i18n 的 `description_id`。
