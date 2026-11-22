# OK Mod 工作項 12 收尾（F 組）：starter／full profile 涵蓋全部範例、verify（2026-11-23）

第三波第 4 項。前半見 [OK_MOD_S12_PACK.md](OK_MOD_S12_PACK.md)（`ok-mod-pack`、profile、obsolete、熱重載）。

## 改了什麼

- `Tools/ok-mod/profiles/full.toml`：18 個範例全部（birthday、boop、dream-panel、glass-shader、hello、idle-breath、object-hotkeys、outfit-names、pair-counter、profile、random-chara、scene-notes、skin-decal、studio-autosave、subtitles、timeline-flow、toon-post、ui-sample），都是 0.1.0。
- `starter.toml`：計畫 §14.4 列的新玩家組合——hello、profile、outfit-names、studio-autosave、object-hotkeys、toon-post。
- `ok-mod-pack` 的 pak 檢查呼叫 ModKit 時改給 content root（`828ea708e`）。原本給 mod id，id 帶 `.` 或 `-` 時 `modkit_cook.lua` 一律拒絕（`--mod must match ...`），所以任何帶 pak 的 mod 都打不了包；之前的測試沒有帶 pak 的範例，沒抓到。
- 測試：`profiles_save_and_apply` 改用只有 hello 的臨時 profile（倉庫的 starter 不再只有 hello）；新增 `every_example_is_in_full`（full 剛好是每個範例的 id 與版本，starter 只列範例）。

## 驗證

腳本（scratchpad，不進版控）對每個範例：複製 mod 資料夾、帶上最新的 ModKit 產物（glass-shader、toon-post、dream-panel 的 `content/*.pak`，dream-panel 另帶 `ui/Panel.dui`），`ok-mod-pack pack --dll target/release/<dll>` 打包，再 `profile apply` 到空的 Mods、`verify`：

| profile | 打包 | 套用 | verify |
|---|---|---|---|
| full | 18 個全部通過（三個帶 pak 的經過 `modkit_cook.lua --verify`） | 18 個 installed | OK；五個模式各自會載入的 mod 都列出，沒有不載入的 |
| starter | （同上） | 6 個 installed | OK |

verify 列出的載入清單（full）：

- extract：hello、profile
- pair：boop、glass-shader、hello、pair_counter、skin-decal、subtitles
- reader：boop、dream-panel、glass-shader、hello、outfit-names、profile、random-chara、skin-decal、subtitles、ui-sample
- street：birthday、glass-shader、hello、skin-decal、subtitles
- studio：boop、glass-shader、hello、idle-breath、object_hotkeys、scene_notes、skin-decal、studio_autosave、timeline_flow、toon-post

`cargo test -p ok-mod-pack` 6 項通過。

## 限制

- 帶 pak 的三個範例，pak 不在版控（ModKit 每次產生）；用 profile 安裝前要先跑 ModKit 再打包。沒有 pak 時 glass-shader、toon-post 退回 A 層／沒有效果，dream-panel 不顯示面板。
- 打包全部範例的流程只在 scratchpad 腳本，沒有做成 `ok-mod-pack` 的指令；最後整合要打包範例時照本文的步驟。
