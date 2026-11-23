# OK mod 第六波（E 組）：Studio 設定頁的 mod 熱鍵、1 對 1 熱鍵設量表、名額事件查明（2026-11-23）

## 1. Studio 設定 › Mod 熱鍵

| 檔案 | 內容 |
|---|---|
| `Plugins/OKStudio/.../Public/OKStudioMod.h` | 登錄點加 `ListHotkeys`、`CaptureHotkey`、`BindHotkey`（OKStudio 外掛不依賴 OKModding，由遊戲模組填入） |
| `Plugins/OKStudio/.../Private/SOKStudioMod.cpp`（新函式 `ModHotkeySettings`） | 分頁內容：每個熱鍵一列：說明、`<mod>.<name>`、目前按鍵（按下後等下一個組合鍵，Esc 保留、Backspace 清除）、「清除」、「預設 <鍵>」；搜尋框也篩這一頁 |
| `SOKStudioWindows.cpp`（兩行）、`SOKStudioPanel.h`（宣告） | 設定視窗多一個分頁「Mod 熱鍵」 |
| `Source/OpenKoikatsu/OKModeHotkeys.cpp` | `StudioStart` 時以 `FOKModKeys::List/Display/Capture/Bind` 填入上面三個函式，`StudioStop` 清掉 |
| `OKStudioModBridge.cpp`（一個小函式） | `ModText`：用 mod 的語系檔把說明 id 換成文字 |

**MCP 讀得到也改得到**：按鍵都是一般 Slate 按鈕，`ui_widgets` 列得出（例如 `F8`、`清除`、`預設 F8`），`ui_press` 按得到；改綁就是 `ui_press` 那顆按鍵後用 `ui_type` 送新的組合鍵。目前按鍵那顆另有標記 `ModHotkey_<mod>.<name>`。

實測（Studio，名額 `e-mod-6`）：

| 步驟 | 結果 |
|---|---|
| `app.settings` → `ui_press "Mod 熱鍵"` → `ui_widgets` | 讀到 hello 的一列：`F8`、`清除`、`預設 F8` |
| `ui_press "F8"` | 按鈕變成「按新按鍵…（Esc 取消）」（截圖 `E:\OpenKoikatsu\Saved\OKStudio\mcp_ui\emod6_capturing.png.png`） |
| `ui_type` Ctrl+K | 按鈕顯示 `Ctrl+K`；`OKMod.Keys`：`greet = Control+K (default F8)` |
| 再按 Ctrl+K | `hotkey Control+K in studio: hello (studio)` |
| 「預設 F8」／「清除」／「預設 F8」 | 依序 `F8`、`(none)`（按鈕顯示 `—`）、`F8` |

小缺點：說明欄只有在 mod 也加入 Studio 面板（回 `studio.panel_ui`）時才用它的語系文字；hello 沒加入，所以顯示熱鍵名 `greet`。

## 2. 1 對 1 熱鍵回覆設量表

`Tools/ok-mod/fixtures/pair-gauges` 加熱鍵 `bump`（預設 F9），回 `{"pair": {"her": 90, "his": 10}, "notice": "量表 90／10"}`。

開發版街區（`-Editor -Control -Sandbox EMod4 -PortBase 48130 -Heroine 1`）`hscene open=1`，閒置到量表歸零後按 F9（`ui_type`）：

- 按前：她 0、他 0；
- 按後立刻：她 89.9、他 9.9（之後照閒置每秒 3 衰減，3 秒後 80.5／0.5）；
- H 面板提示列：「[org.openkoikatsu.test.pair_gauges] 量表 90／10」；
- log：`bump in pair`、`hotkey F9 in pair`、`pair hotkey reply shown in the H panel's hint`。

## 3. 「名額沒排到卻照樣開遊戲」是誰的

查明是**我自己在那次對話裡臨時寫的 bash 指令**，不是專案的腳本：指令是 `for i in 1..20; do claim …; done; run_street_social_development.lua …`，迴圈結束後沒判斷有沒有排到就接著啟動。

- `studio_launch`、`game_launch`（ok-game-mcp）、`Tools/run_street_social_development.lua`、`Tools/run_interaction_pair.lua` 本來就不管名額，名額由呼叫的人先 `claim`，這是現行的分工，不是 bug。
- C 的 `unreal_slot.lua` 行為正確：沒排到時回 `queued: …`，不會假裝成功。
- 我之後的做法：只在 `claim` 輸出 `slot1`／`slot2` 時才往下（這一波都這樣做）。`Docs/ERROR_LOG.md` 那一筆已寫明原因與做法，不需要改任何腳本。
- 給協調者參考（不是 E 的檔案，沒動）：若要從工具面擋住，可讓啟動器在設了某個環境變數（例如 `OK_REQUIRE_SLOT=<agent>`）時先查 `unreal_slot.lua` 是否持有名額，沒有就拒絕啟動。

## 4. 驗證

- `cargo test -j 8`（`Tools/ok-mod`）全過；`cargo check -j 8`（`Tools/ok-extract`，另加 `--no-default-features`）過。
- `E:\PhysX\UE5.8` 建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 連結成功。
- 實機如 §1、§2。

## 5. 沒驗到

- 打包版。
- 改綁時按 Esc 保留舊鍵（`FOKModKeys::Capture` 的行為，讀卡器已測；Studio 這次沒按）。
