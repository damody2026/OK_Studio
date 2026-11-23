# OK mod 第五波（E 組）：Studio 與 1 對 1 接上 mod 熱鍵（2026-11-23）

照 `Docs/OK_MOD_F_WAVE4.md` §5「熱鍵接線說明」，在同步點 D（`69376f035`）之後接。檢出 `E:\OpenKoikatsu`，引擎 `E:\PhysX\UE5.8`。

## 1. 改了什麼

| 檔案 | 內容 |
|---|---|
| 新 `Source/OpenKoikatsu/OKModeHotkeys.h/.cpp` | `StudioStart/Stop`、`PairStart/Stop`：`FOKModKeys::Listen("studio"/"pair", …)` 與 `Stop`；1 對 1 回覆的處理；`UOKHScenePanel::ShowHint` 的定義 |
| `OKStudioModBridge.cpp`（加一個函式與兩行呼叫） | `ApplyHotkeyReply`：熱鍵回覆當作 Studio 的效果套用（`status`、`data`、`ops`、`run`…），和面板按鍵一樣自成一個 undo 步驟；JSON 只有 `notice` 時顯示在狀態列。`Build` 結尾 `StudioStart`，`Teardown` 時 `StudioStop` |
| `OKPairModBridge.cpp`（兩行） | `pair.enter` 與 `pair.ready` 時 `PairStart(控制器)`，`pair.exit` 時 `PairStop`；街區試衣間不算 |
| `OKHScene.h`（一行宣告） | `ShowHint`：把文字放進 H 面板提示列，不算場景事件（不呼叫 `Note`，不會再觸發 `pair.note`） |
| `Plugins/OKModding/.../OKModKeys.cpp`（**F 的檔案，一行**） | 前處理器改成排第一（`RegisterInputPreProcessor(GProcessor, 0)`），見 §3 |

1 對 1 的回覆：`{"pair": {"her", "his"}}` 設量表（和其他 `pair.*` 回覆一樣）；文字（`text`，或 JSON 的 `notice`／`status`）在 H 場景裡顯示在提示列，不在 H 場景時（獨立 1 對 1 的一般畫面）以畫面提示顯示。

設定頁的熱鍵列表／改綁沒做（可選）；Studio 裡可用主控台 `OKMod.Keys`、`OKMod.Bind`。

## 2. 實測

裝 `hello`（F8 `greet`）與第四波的 Studio mod 們。

| 項目 | 結果 |
|---|---|
| Studio：按 F8 | `hotkey F8 in studio: hello (studio)`，狀態列「hello (studio)」；沒改到文件，不產生 undo 步驟 |
| Studio：改名文字框編輯中按 F8 | 不觸發（`handled: false`，log 沒有新的一筆），字照常進文字框 |
| Studio：DreamGUI 文字框 | Studio 沒有 DreamGUI 文字框，沒得測 |
| Studio：和既有快捷鍵同鍵（`OKMod.Bind … greet E`，E 是 Studio 配置的「旋轉」） | 修正前：Studio 先吃掉，工具變成旋轉，mod 沒收到。修正後：mod 收到（`hotkey E in studio`），工具維持「移動」；沒綁的 R 照常切到縮放。測完綁回 F8 |
| 1 對 1（從街區進入，開發版街區 `-Editor -Control -Sandbox EMod4`，`hscene open=1`） | `hotkey F8 in pair: hello (pair)`，H 面板提示列「[org.openkoikatsu.hello] hello (pair)」 |
| 1 對 1（獨立，`Tools/run_interaction_pair.lua --control`） | `hotkey F8 in pair`，沒有 H 面板，以畫面提示顯示 |
| 街區本身（非 1 對 1） | F8 不觸發：街區還沒接（C 的工作），符合預期 |

按鍵經 `studio_key`／`ui_type` 送（都走 `FSlateApplication::ProcessKeyDownEvent`，前處理器看得到，和真鍵盤同路）。

## 3. 實測時發現並修掉的

- **mod 熱鍵和 Studio 快捷鍵同鍵時，Studio 先吃掉**：F 的前處理器在第一次 `Listen` 才註冊，而 Studio 面板的前處理器在面板建立時就註冊了，排在前面。F 文件寫的是「mod 熱鍵優先：玩家綁的」，實際相反。改成註冊時插在最前面（index 0）。這一行在 F 的 `Plugins/OKModding`，**請協調者在同步點轉給 F**（讀卡器、街區也受影響：之後任何模式先註冊的前處理器都排在 mod 熱鍵之後）。
- **街區進入的 1 對 1 回覆沒顯示**：`pair.enter` 那刻街區的控制器還沒設好（`card` 也是空的），熱鍵回覆處理拿到空指標，只寫 log。改成 `pair.ready` 時再 `Listen` 一次帶上控制器。

## 4. 驗證

- `cargo test -j 8`（`Tools/ok-mod`）全過；`cargo check -j 8`（`Tools/ok-extract`，另加 `--no-default-features`）過。
- `E:\PhysX\UE5.8` 建 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 連結成功（最後一次改動後再建，兩個都過）。
- 實機如 §2，名額 `e-mod-5`。

## 5. 沒驗到

- 打包版（stage）。
- Studio 設定頁的熱鍵改綁 UI（沒做）。
- 1 對 1 熱鍵回覆設量表：程式和 `pair.*` 回覆同一個欄位，沒有用熱鍵實測（hello 只回文字）。
- 有一次排名額沒排到，腳本卻照樣開了遊戲（約 2 分鐘，沒做任何測試就停掉），記在 `Docs/ERROR_LOG.md`。
