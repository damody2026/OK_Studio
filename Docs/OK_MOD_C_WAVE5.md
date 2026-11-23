# OK Mod 第五波（C 組，2026-11-23，同步點 D 之後）

起點 `69376f035`（同步點 D）。`ok-mod-api` 沒改，SDK 沒動。

## 1. 街區接上按鍵服務

照 `Docs/OK_MOD_F_WAVE4.md` §5：

- `OKStreetSocialMods.inl`：
  - 新增 `ModsListenKeys`：呼叫 `FOKModKeys::Listen("street", …)`。回覆有 JSON 就交給 `ModsFollow`，純文字（`FOKModKeys::ShownText`）放到街區訊息列。
  - 原本 `ModsHook` 迴圈裡處理每個 mod 回覆的那段（`cards`、`state`、`notice`、`subtitle`）抽成 `ModsFollow`，掛點回覆和熱鍵回覆走同一條路。`state` 改成每筆回覆各自寫一次 ext，不再整批最後才寫，結果一樣。
- 開始收：`ModsTick` 第一次執行時（場景已經在 Tick）。
- 停止：`EndPlay` 的第一行呼叫 `FOKModKeys::Stop("street")`。
- 1 對 1 從街區進入時的 `"pair"` 是 E 的範圍，這裡沒登記。

實測（`probe1123d` stage，hello 0.1.0）：

| 狀況 | 結果 |
|---|---|
| 焦點在 3D 畫面，按 F8（`ui_type`，經 Slate） | `[org.openkoikatsu.hello] hotkey F8 in street: hello (street)` |
| 點進自由對話的輸入框（Slate `SEditableText` 有焦點），按 F8 | 沒觸發，按鍵交給輸入框（`handled: false`） |

`game_key` 走的是 `APlayerController::InputKey`，Slate 的前處理器收不到，所以用它按 F8 不會觸發。測熱鍵要用 `ui_type`。

## 2. 補驗第四波沒實測的掛點

hook-probe（`Tools/ok-mod/fixtures/hook-probe`）改用 F 的 SDK 輔助：
- `get` 改用 `hooks::reader::get`；
- 寫回卡片改用 `hooks::street::cards` 搭配 `CardWrite::write`；
- 每個新掛點的 payload 都再用 SDK 型別（`hooks::reader::*`、`hooks::street::*`）解析一次，讀不了就寫 warning。

這次讀卡器與街區兩邊的 log 裡，`SDK type does not read` 都是 0 筆。

### 讀卡器（C: 編輯器建置；遊戲目錄用 `-ini:Game:[/Script/KKSideloader.KKGameRoot]:Root=D:/XKoikatuSunshine` 只對這次啟動生效，沒有改使用者設定）

| 掛點 | 觸發方式 | payload |
|---|---|---|
| `reader.accessory_change`（新增欄） | `reader_call add_accessory` | `{added: true, item: "", outfit: 0}`，沒有 `slot`（設計如此） |
| `reader.accessory_change`（換飾品） | `reader_call appearance`，target `accessory2_121` | `{added: false, item: "381bc984…", outfit: 0, slot: 2}` |
| `reader.accessory_copy` | 屬性 ops `{"op":"accessory_copy","from_outfit":1,"slots":[0,1]}` | `{from_outfit: 1, to_outfit: 0, slots: [0,1]}` |

注意：外觀套用之後，ops 會回 `Character or outfit changed; reopen the detailed editor`。要先 `reader_call parameters` 重讀屬性，ops 才能用。這是既有規則，不是這次的錯。

### 街區（`probe1123d`，`-Sandbox cmod5 -PortBase 48160`）

| 掛點 | 結果 |
|---|---|
| `street.arrive`（修過的） | 開場後直接瞬移到女生宿舍，沒有任何其他掛點，先送 `street.load`，再送 `{who: "him", place: "girls_dorm", place_name: "校外女生宿舍", from: "boys_dorm"}`。修正確認 |
| `street.phone` `from: her`，他拒接 | `{from: "her", answered: false, declined: true}` |
| 同上，沒接到（20 秒逾時） | `{from: "her", answered: false}`；她隨後傳訊息「又沒接…」 |
| 同上，他接聽 | `{from: "her", answered: true}`，通話開始 |

為了能觸發她打來，新增控制端點 `/ring {girl, why}`（`OKStreetSocialControl.inl`）：手機立刻響 20 秒，和 `ReachOutByPhone` 讓戀人隨機打來時一樣，之後由接聽、拒接按鈕或逾時結束。已加進 ok-game-mcp `game_call` 的說明。它是測試用端點，不是規則。

這次沒觸碰，也沒寫任何女角卡片。測試前把 `Content/CharacterCards/StreetHeroines/*.png` 備份到 `Saved/HookProbe/cards_backup/`，測完逐檔比對，都沒有變。

## 3. 驗證

- `Tools/ok-mod`：`cargo test -j 8` 全過。
- `Tools/ok-game-mcp`：`cargo check --release` 過。
- `Tools/ok-extract`：這一波沒改，沒重跑。
- D: 引擎：`OpenKoikatsuEditor` 與 `OpenKoikatsu` Development 都是 `Result: Succeeded`。
- 測試 stage：`probe1123d`（`--skip-cook --skip-base`、base `BaseC1118A`），`staged_at` 已調早，`StreetSocial.cmd` 不會挑到它。第四波的 `probe1123c` 也還在，兩個都可刪；目錄裡有 junction，不要遞迴刪除。

沒驗到：
- 街區的熱鍵回覆走 `ModsFollow`（`notice`、`cards` 等）沒實測：hello 的 F8 只回文字，那條路是 log 加訊息列。
- 1 對 1 的 `"pair"` 熱鍵屬 E。

## 4. 提交
- `1e0ec2006` hook-probe：改用 SDK 的 hooks::reader／street 型別與 get、cards 輔助
- `c583fcfd4` 街區控制端點 /ring：讓她現在打電話來（測 street.phone from her）
- `e9004ce7f` 街區 mod：接上按鍵服務（FOKModKeys street，EndPlay 停止），回覆處理抽成 ModsFollow 與掛點共用

文件本身是最後一個提交。
