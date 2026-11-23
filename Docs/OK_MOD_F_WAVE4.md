# OK Mod 第四波（F 組）：按鍵服務收尾、熱重載保留狀態、GPU 動態骨外力調查、`ok-mod-pack new`（2026-11-23）

計畫 [OK_MOD_FRAMEWORK_PLAN.md](OK_MOD_FRAMEWORK_PLAN.md)（主本在 C）§7.5、§7.6、§16.4 的 F 段。檢出 `F:\OpenKoikatsu`（`master`，從同步點 C `573a1c6bb` 起），引擎 `F:\UE5.8`。沒有推送、沒有合併其他檢出。

## 提交

| 提交 | 內容 |
|---|---|
| `4c6fc245e` | 跨模式按鍵服務（當機前的未提交改動收尾，補了讀卡器缺的兩條文字 id） |
| `0162e11c0` | 熱重載保留狀態 `dev.save_state`／`dev.restore_state` |
| `aea79a3cb` | `ok-mod-pack new` 子指令與測試 |
| `8dea071f4` | 讀卡器熱鍵頁：改綁時按鈕文字跟著變（實測找到的 bug）、提示縮短 |
| `e4cd5ad3f` | 按鍵服務：訂閱照 mod 寫的保留（`4c6fc245e` 的短名改寫會讓 OK Studio 面板按鍵失效，寫回報時發現）|
| （本回報同批） | `Docs/OK_MOD_AUTHORING.md`（新）、`Docs/OK_MOD_HOOKS.md` §9、`Docs/ERROR_LOG.md`、註解改指 §9 |

沒提交（照分派）：`Tools/ok-extract/src/entries.rs`（別人的改動）、`OKExtractBuildStamp.h`、`UserData/`。

## 1. 按鍵服務（hook `key.<name>`）

當機前的改動（`git diff` 檢查）大致完整：宿主 `host/src/keys.rs`、`ffi.rs` 的 `hotkeys`／`key` 請求、`ok_mod_host.h`、SDK `Registrar::hotkey`／`hooks::hotkey`／`hooks::KeyPress`、UE `FOKModKeys`、讀卡器熱鍵頁、hello 的 F8 `greet`、測試。缺的是讀卡器用到的文字 id `reader.mods.hotkeys`、`reader.mods.press_key`，三語 `ui_text.toml` 都沒有，收尾時補上。

規格寫在 [OK_MOD_HOOKS.md](OK_MOD_HOOKS.md) §9。重點：

- mod 用 `key.<entry>` 訂閱（長名 `key.<mod id>.<entry>` 也認），hook 只送給該 mod；第一版在宿主載入時把短名改寫成長名，會讓 OK Studio 面板按鍵（同樣送 `key.<id>`）全部失效，已在 `e4cd5ad3f` 改回原樣保留；
- 組合鍵比對不分左右修飾鍵、大小寫、順序，修飾鍵要完全相同；
- UE 端是一個 Slate 輸入前處理器，模式呼叫 `FOKModKeys::Listen` 才收；打字中、按住滑鼠、重複鍵不觸發。

**只有讀卡器接了 `Listen`**。Studio、1 對 1、街區各要在自己的模式啟動處加一行 `FOKModKeys::Listen(TEXT("studio"|"pair"|"street"), 回覆處理)`，那些檔案屬 E／C，我沒動，交給協調者分派。

## 2. 熱重載保留狀態

開發模式（`-ModDev`）`mod.reload <id>` 時：

1. 舊實例收 `dev.save_state {"version"}`，回 JSON（或文字）狀態；
2. 舊實例 `shutdown`，載入新副本，送 `Enabled`；
3. 新實例收 `dev.restore_state {"from_version", "to_version", "state"}`。

失敗處理：

- 存狀態失敗 → 照樣換上，從頭開始，回答註明；
- 還原失敗 → `reload` 回錯，panic 時新副本 faulted；
- 新版沒訂閱 → 回答註明從頭開始。

SDK：`Registrar::keep_state()`、`hooks::SAVE_STATE`、`hooks::RESTORE_STATE`、`hooks::RestoreState<T>`。hello 保留 ping 次數。panic fixture 改用 `event.subscription()` 判斷在哪裡 panic（原本 `event.name()` 對所有 hook 都是 `"hook"`），並加上 `keep_state`，用來測兩個失敗路徑。

## 3. GPU 動態骨外力：沒有實作，原因如下

調查結果：

- **CPU 路徑已有外力。** 每幀呼叫 `ok_mod_frame` 回的 `OkModForce`（球心、半徑、加速度）由 `ok-extract` `mod_frame::with_force` 加進 `m_Force`，涵蓋 `dbone.rs` 的四個求解點與 `dbone/ver02.rs`。這條路服務讀卡器、Studio、1 對 1 的角色。
- **GPU rig 的角色根本不經過 mod 每幀呼叫。** GPU 路徑是 `Tools/ok-extract/src/gpu_rig/physics.rs` 匯出 → `Plugins/KKCrowdGpuPacking` `FOKGpuRig` → `Shaders/GpuRig.usf` `PhysicsCS`。
  - 它只用在人群場景（`OKCrowdRuntimeScene`：街區路人、百人房間、Render Studio）。
  - 那些角色沒有 ok-extract Session，CPU 上沒有她們的骨骼。所以沒有 `ok_mod_frame` 的呼叫可以回外力，`Frame::character` 也對不到人。
  - 鏈的 `force` 在匯出時固定進 `PhysChainValues`（每鏈 `(force, 0)`），每幀不更新。
  - `PhysicsCS` 的世界座標是每個角色自己的 Unity 空間，不含 actor 擺放。

做得到的設計（要先經協調者，因為牽涉 API 語義與共用 shader）：

1. **mod 端**：新增「每幀一次、整個場景」的呼叫。可以沿用 `OkModFrame` 版面，用 `kind = 2`、`character = 0`、沒有骨骼表示；mod 回世界座標（Unity 空間）的 `OkModForce`。版面不變，但這是 `ok_mod_frame` 語義的追加，照 §7.6 要協調者決定。現有 mod 對 `kind = 2` 的反應也要確認：boop 找不到錨點不推，idle-breath 沒骨骼不動。
2. **UE 端**：`OKCrowdRuntimeScene` 每幀把世界外力球依每個 actor 的擺放換到她自己的空間，上傳一個小的 per-actor 外力緩衝（例如每人最多 4 顆）。
3. **shader**：`StepChainV02` 與一般鏈的 `force` 加上根節點落在球內的外力。改的是 `KKCrowdGpuPacking`（C／E／F 共用），要在人群場景實測不退步。

沒有做的理由：

- 要新增 API 語義；
- 要改三組共用的 shader；
- 目前沒有任何 mod 需要對路人施力；
- 驗證要開人群場景，量不退步。

這不是一行能收的尾，風險不值得在無人值守時單獨推進。

## 4. `ok-mod-pack new` 與作者文件

- `ok-mod-pack new <folder> --id <id> [--name] [--author] [--sdk] [--json]`（新檔 `Tools/ok-mod/pack/src/new.rs`）產生：
  - `Cargo.toml`：cdylib，相對路徑依賴 SDK；在工作區外時自帶空 `[workspace]` 與 `panic = "unwind"` profile；
  - `mod.toml`；
  - `src/lib.rs`：設定項、主控台指令、熱鍵（預設不綁）、`keep_state`；
  - `locale/en`、`locale/zh-CN`。
- 產生在 `Tools/ok-mod` 裡時，沿用工作區設定，回答提示要加的 `members` 一行。
- [OK_MOD_AUTHORING.md](OK_MOD_AUTHORING.md)（新）：產生範本、範本各部分、建置／打包／安裝、開發時的熱重載迴圈（含「載入過的 DLL 整個行程都鎖著，先改名再複製」）、範例對照。

## API 變動（給協調者）

- **`ok-mod-api` 型別沒有改**；`Event` 沒有加變體，全部走 `Event::Hook`。
- **新增 hook 名前綴 `dev.*`**（`dev.save_state`、`dev.restore_state`）。§7.6 的前綴清單要補上。`key.*` 本來就在清單裡。
- **SDK 只有追加**：
  - `Registrar::hotkey`、`Registrar::keep_state`；
  - `hooks::hotkey`、`hooks::KeyPress`、`hooks::SAVE_STATE`、`hooks::RESTORE_STATE`、`hooks::RestoreState<T>`。
- **宿主追加**：
  - 請求 `{"op":"hotkeys"}`、`{"op":"key"}`；
  - `ModHost::hotkeys`、`ModHost::key`；
  - 常數 `SAVE_STATE`、`RESTORE_STATE`；
  - `reload` 的回答多了 `(state kept)` 等註記。
- **沒有行為改變**：訂閱照 mod 寫的保留（第一版的改寫已撤回）。mod 的熱鍵設定項 `x` 若也是 Studio 面板按鍵 `x`，兩邊送的是同一個 hook `key.x`。
  - E 的 Studio 範例（`ok-mod-studio::subscribe` 訂 `key.<k>`）照舊可用；`object-hotkeys` 的 `config_hotkey` 沒訂對應的 `key.<name>`，所以不會被全域熱鍵服務接手（它自己在 Studio 裡處理）。

## 驗證

| 項目 | 結果 |
|---|---|
| `cargo test -j 8`（`Tools/ok-mod` 全工作區） | 通過，0 失敗。新增 `hotkeys_reach_their_mod_in_any_mode_and_rebind`、`reload_state_survives_failures_of_either_copy`、`new_mod_builds_packs_and_loads`（工作區外產生、用工作區 `Cargo.lock` 離線建置、pack、install、宿主載入後指令與改綁熱鍵都回答）、`new_mod_inside_the_workspace_is_a_member`；`dev_mode_reload_swaps_in_a_fresh_copy` 改驗狀態接續 |
| `cargo check`（`Tools/ok-extract`，另加 `--no-default-features`） | 通過 |
| `OpenKoikatsuEditor`、`OpenKoikatsu` Development（`F:\UE5.8`） | 兩次都 `Result: Succeeded`：按鍵服務收尾後一次、熱鍵頁修正後一次（`F:\OpenKoikatsu\Saved\f-mod-4-editor2.log`、`F:\OpenKoikatsu\Saved\f-mod-4-game2.log`） |
| 讀卡器實測（編輯器版，`-ModDev`，名額 `f-mod-4`，共約 6 分鐘） | 見下 |

讀卡器實測（log `F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-094248-68b52fdc.log`）：

- `OKMod.Keys` → `org.openkoikatsu.hello greet = F8`；
- F8（`ui_type`，經 Slate）→ log `hotkey F8 in reader: hello (reader)`，畫面提示；
- `OKMod.Bind ... LeftControl+G` 後 Ctrl+G 觸發、F8 不再被攔；
- `mod.org.openkoikatsu.hello.ping` 兩次 → `mod.reload` 回 `(state kept)`，log `kept 2 pings from 0.1.0` → 再 ping 得 `pong 3`；
- 熱鍵頁：按按鈕 → 「請按鍵…」→ F9 → 按鈕顯示 F9；Esc 保留原綁定。實測後綁定還原成 F8。

截圖：

- `F:\OpenKoikatsu\Saved\OKControl\shots\f-mod-4\hotkey-page-capturing.png`（等待按鍵）；
- `F:\OpenKoikatsu\Saved\OKControl\shots\f-mod-4\hotkey-page-rebound.png`（改綁成 F9）。

## 沒驗到／已知限制

- Studio、1 對 1、街區沒有接 `FOKModKeys::Listen`，熱鍵在那三個模式不會觸發（見 §1）。
- **熱鍵頁的列名顯示 `org.openkoikatsu.hello greet`**，沒有顯示 mod 的 locale 文字（`mod.org.openkoikatsu.hello.config.greet`）。`OKReaderT` 只查遊戲的 `ui_text.toml`；hello 也沒有 `zh-TW` locale。要讓讀卡器讀 mod locale 是另一件事，沒做。
- 打字中不觸發的判斷是看 Slate 焦點 widget 的型別名（`EditableText`／`TextBox`／`TextInput`）。DreamGUI 文字框編輯中是否也擋住，沒有實測。
- 熱重載只在讀卡器實測。Studio 的物件狀態類 mod 沒有試。
- 打包版（stage）沒測；`ok-mod-pack new` 只在這台機器、目前的 rustc 測過。
- GPU 動態骨外力沒做（§3）。
