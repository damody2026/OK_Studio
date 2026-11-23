# OK Mod 第五波（F 組）：乾淨 stage 安裝測試、Release 互通（2026-11-23）

計畫（主本在 C）§16.5 第 4 項與「已知沒驗到的」。檢出 `F:\OpenKoikatsu`（`master`，從同步點 D 的 `69376f035` 起），引擎 `F:\UE5.8`，Unreal 名額 `f-mod-5`。沒有推送。

## 提交

| 提交 | 內容 |
|---|---|
| `7bae3c4c8` | `ok-mod-pack`：打包 `ui/`（面板的 `.dui`）；`verify` 移走的 mod 從 `.installed.toml` 刪掉 |
| `177ae0496` | 測試：release 與 debug 建置互通 |
| `817864461` | `Tools/pack_mod_examples.lua`：一次打包全部範例 |
| （本回報同批） | 本回報、`Docs/ERROR_LOG.md` |

## 1. 測試 stage

- F 檢出原本沒有 base、host、cook 產物，`--skip-cook` 無從沿用（協調者說「沿用既有 base」，但 base 只在 C，而且是 D: 引擎建的，F 引擎不能用）。所以跑了完整流程：

  ```powershell
  F:\OpenKoikatsu\Tools\lua\lua.exe F:\OpenKoikatsu\Tools\rebuild_street_social_runtime.lua --tag ModInstallF5 --engine F:/UE5.8 --base-dir Saved/StreetSocial/BaseF5
  ```

  - 耗時：host＋執行檔 18 分、cook 6 分、base 1 分、stage 1.5 分。
  - 日誌：`F:\OpenKoikatsu\Saved\StreetSocial\Rebuild-ModInstallF5\`。
  - cook 時占名額約 30 分鐘，超過 20 分鐘上限，照協調者指示沒有中斷。
- stage：`F:\OpenKoikatsu\Saved\StreetSocial\Build\ModInstallF5.stage`。
  - `stage.json` 的 `staged_at` 改成 `1700000000`（2023 年）；F 檢出裡沒有別的 stage。
  - stage 根有空的 `Mods/`，`ok_mod_host.dll` 在 exe 旁。這兩樣由 `stage_street_social.lua` 放進去。
- base：`F:\OpenKoikatsu\Saved\StreetSocial\BaseF5`（F 引擎專用）。

## 2. 打包與安裝

`Tools/pack_mod_examples.lua --out Saved/f-mod-5/packages` 把 19 個範例打成 `.okmod`，放在 `F:\OpenKoikatsu\Saved\f-mod-5\packages\`。

- DLL 取 `Tools/ok-mod/target/release`。
- 三個帶 pak 的範例（glass-shader、toon-post、dream-panel），pak 與 dream-panel 的 `ui/Panel.dui` 取自 `F:\OpenKoikatsu\Mods\`，是之前 F 用 ModKit 做的，`content_build = "1@5.8.4-0"` 和這個 stage 相符。

安裝在 stage 的 `Mods/`。輸出存在 `F:\OpenKoikatsu\Saved\f-mod-5\`：`starter-apply.txt`、`starter-verify.txt`、`full-apply.txt`、`full-verify.txt`、`obsolete.txt`、`full-reapply.txt`。

| 步驟 | 結果 |
|---|---|
| `profile apply starter.toml` | 6 個 `installed`；`verify` OK |
| `profile apply full.toml`（starter 之上） | starter 的 6 個 `already_installed`，另 13 個 `installed`，共 19 個；`verify` OK |
| `.installed.toml` | `profile = "full"`，19 筆（id、version、DLL 的 sha256、folder、package、installed_at） |
| 安裝 `org.openkoikatsu.test.panic`（內建 `obsolete.toml` 有它） | `refused (on the obsolete list: test fixture ...)`，exit 1 |
| `Mods/obsolete.toml` 加 `birthday <0.2` → `verify --dry-run` | 只列出 `would be moved to .old`，不動 |
| 同上 → `verify` | 移到 `Mods/.old/org.openkoikatsu.birthday-0.1.0-<時間>/`，附 `RETIRED.txt`；street 的載入清單少了 birthday |
| 再 `install` birthday | `refused (on the obsolete list: install test ...)` |
| 刪掉 `Mods/obsolete.toml` → `profile apply full.toml` | birthday 重新 `installed`，回到 19 個，`verify` OK |

full 的載入清單：

- extract：hello、profile
- pair：boop、glass-shader、hello、pair_counter、skin-decal、subtitles
- reader：boop、dream-panel、glass-shader、hello、outfit-names、pair_counter、profile、random-chara、skin-decal、subtitles、ui-sample
- street：birthday、glass-shader、hello、skin-decal、subtitles
- studio：boop、glass-shader、hello、idle-breath、light_rig、object_hotkeys、scene_notes、skin-decal、studio_autosave、timeline_flow、toon-post

### 找到並修掉的（F）

1. **`ok-mod-pack` 不打包 `ui/`**（`7bae3c4c8`）。
   - 現象：dream-panel 裝好後，打包版遊戲拒掛它的 pak：`content pak refused: ... no ui/Panel.dui in the mod folder`。
   - 原因：`PACKED_DIRS` 只有 locale／assets／materials／content。
   - 加上 `ui` 後重打包重裝，pak 掛上了。
2. **`verify` 移走 obsolete mod 後，`.installed.toml` 還列著它**（`7bae3c4c8`）。現在 `retire` 一律刪掉該筆。
3. **我的打包腳本的 bug**：範例 `glass-shader` 有一個空的 `content/` 資料夾，第一版腳本因此沒去 `Mods/` 拿 pak，glass-shader 包裡沒有 pak、退回 A 層。改成空資料夾視同沒有。

### 行為（不是 bug，記下來）

- **`profile apply` 只比版本號**：`install` 比版本號＋DLL 的 sha256，pak、`.dui`、locale 不在比對範圍。所以「同版本但重打過的包」不會自動換上（上面修 1、3 之後要用 `install --force`）。
- 這符合「內容改了就升版本」的規矩。發布時改了 pak 或 `.dui`，一定要升 mod 版本。

## 3. 打包版實測

讀卡器用 `reader_launch`，帶 `OK_ENGINE_ROOT=X:/NoEngine`：找不到編輯器時，`run_card_reader_development.lua` 會跑最新的 stage，F 只有這一個。街區用 `game_launch`。

| 項目 | 結果 |
|---|---|
| 讀卡器 mod 清單（`mod.list`） | 19 個 mod：11 個 enabled，8 個 `skipped (not for mode reader)`；宿主是 stage 的 `ok_mod_host.dll`，Mods 是 stage 的 |
| 讀卡器 pak | dream-panel（1 asset）、glass-shader（2 assets）都 `content mounted`；glass 材質用的是 pak 的 `/org_openkoikatsu_glass_shader/M_OKGlass`（B 層） |
| 讀卡器 hello | 啟動 log `hello from hello`；F8 → 畫面提示 `[org.openkoikatsu.hello] hello (reader)` |
| `-NoMods` | `Mods are off for this run (-NoMods)`；沒有 mod、沒有掛 pak；`mod.list` 回「Mods are off」 |
| Shift 跳過 | 啟動時按住 Shift（PowerShell `keybd_event`，25 秒）→ `Mods are off for this run (Shift held at start)` |
| 街區 | 5 個 mod enabled（birthday、glass-shader、hello、skin-decal、subtitles），glass-shader 的 pak 掛上、B 層材質 ready；遊戲正常進入宿舍走廊 |

截圖：

- `F:\OpenKoikatsu\Saved\OKControl\shots\f-mod-5\packaged-reader-hello.png`
- `F:\OpenKoikatsu\Saved\OKControl\shots\f-mod-5\packaged-street.png`

讀卡器 log：

- `F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-105908-4a3e85e2.log`（mod）
- `F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-105942-2f53d951.log`（`-NoMods`）
- `F:\OpenKoikatsu\Saved\Logs\CardReader\20261123-110001-3e20eda9.log`（Shift）

街區 log：`F:\OpenKoikatsu\Saved\StreetSocial\Play-20261123T110022\game.log`。

**沒測**：

- **Studio、1 對 1 的打包版**：這個 stage 是街區 cook（`--studio` 才 cook Studio 地圖），F 開不了 Studio 打包版。1 對 1 要從街區或讀卡器進入。名額時間內沒做，交給協調者最後整合時補。
- 街區裡 birthday 的 `street.load`、subtitles 的字幕沒有觸發驗證，只確認載入與 pak 掛載。
- toon-post（只在 Studio）的 pak 沒在打包版掛過。

## 4. Release 互通

`host/tests/load.rs` `release_and_debug_builds_interoperate`（`177ae0496`）用和測試本身相反的 cargo profile 建 hello，再給宿主載入。驗載入、指令、hook、熱鍵。

- `cargo test`：release 建的 hello → debug 宿主，通過。
- `cargo test --release`：debug 建的 hello → release 宿主，通過。

遊戲用的 `ok_mod_host.dll` 一律是 `Tools/ok-mod/target/release` 的 release 版，Development 或 Shipping 遊戲都一樣。所以玩家會碰到的組合是「release 宿主 × 作者用任一 profile 建的 mod」，兩種都通。stage 裡 19 個範例都是 release 建的，在打包版正常載入。

## 5. 給協調者（不屬 F）

1. **打包版讀卡器沒有 DreamGUI 的 global shader，退回舊版畫面**。
   - 畫面紅字：「DreamGUI 的 global shader 不在這個遊戲的 shader 庫裡（讀卡器的新畫面要用到）。請先執行 `Tools/lua/lua.exe Tools/rebuild_street_social_patch...`」。
   - 街區 stage 的 cook 沒把 DreamGUI 的 global shader 帶進去。
   - 打包版讀卡器的 mod 頁、DreamGUI 面板（dream-panel 的 pak 雖然掛上了）都在新畫面才看得到，所以打包版這部分沒法實測。最後整合跑完整流程時要確認 patch 有做。
2. **`game_stop` 回 `stopped` 但進程還在**：過了約 5 秒仍在，我用 `Stop-Process` 結束。`Tools/ok-game-mcp` 是 F 的範圍，但這一輪沒查，列為待查。
3. **名額**：
   - cook 段占名額約 30 分鐘（完整流程，F 沒有可沿用的 base）；
   - 實測段 claim 時，`e-mod-5` 的編輯器占了約 91 GB commit，只剩 1 GB，排隊等到它放出。

## 驗證

- `cargo test -j 8`（`Tools/ok-mod` 全工作區）：77 項通過，0 失敗；另跑 `cargo test --release` 的互通測試。
- 這一輪沒改 C++，沒有重建 UE。stage 用的執行檔是 `rebuild_street_social_runtime.lua` 從同步點 D 的原始碼建的。
