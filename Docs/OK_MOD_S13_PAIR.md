# OK mod 工作項 13：1 對 1（E 組）

計畫：`Docs/OK_MOD_FRAMEWORK_PLAN.md` §15.4 工作項 13（範例照 §14.3）。前置見 [OK_MOD_S13a_PAIR_PREREQ.md](OK_MOD_S13a_PAIR_PREREQ.md)，Studio 部分見 [OK_MOD_S8_STUDIO_API.md](OK_MOD_S8_STUDIO_API.md)。

## 做了什麼

### 1 對 1 事件到宿主（`Source/OpenKoikatsu/OKPairModBridge.cpp`）

宿主開著時訂閱 `FOKInteractionModEvents`，每個事件以通用掛點送出（`{"op":"hook","hook","payload"}`）：

| hook | 何時 | payload 額外欄位 |
|---|---|---|
| `pair.enter` | 開 1 對 1（還沒載入） | `section`（見下） |
| `pair.ready` | 兩人都載入、開始動 | |
| `pair.exit` | 結束 | `cancelled`、`seconds`（從 ready 起算）、`section` |
| `pair.note` | H 場景記下一件事 | `text`、`react` |
| `pair.finish` | 有人高潮 | `text`（種類：她 `orgW`／`orgS`（插入中）、`orgTouch`（愛撫）、`orgSolo`（她獨自）；兩人 `sameW`／`sameS`；他 `inside`／`outside`） |
| `pair.voice` | 她的語音播放 | `source`（`hvoice`／`tts`）、`path`、`text`（clip 名）、`row` |
| `pair.line` | 她的台詞顯示成文字 | `text` |

每個 payload 都有 `{"pair": 1, "event", "card", "fitting"}`（`card`：她的卡片路徑；`fitting`：街區試衣間，不是 1 對 1）。

**卡片資料**：`pair.enter`、`pair.exit` 在卡片檔存在時改成一次送一個 mod（`"mods": [id]`），payload 帶那個 mod 自己在卡片 `okMx` 的區段 `"section": {"version", "data_b64"}`（和讀卡器 `reader.character_load` 一樣的形狀，SDK 的 `hooks::ExtSection` 直接讀）。任何 `pair.*` 的回覆若是 `{"version", "data_b64"}`（SDK `hooks::save`）就把該 mod 的區段寫回卡片檔，`{"remove": true}` 移除；別的 mod 的區段與卡片身分不動。沒訂閱的 hook 記下來不再送。

**模式**：讀卡器或街區世界裡開的 1 對 1，原本宿主一直停在 `reader`／`street`（只有獨立的 1 對 1 遊戲模式會進 `pair`），`targets = ["pair"]` 的 mod 載不到。橋接在 `pair.enter` 送出前呼叫 `FOKModHost::EnterMode("pair")`（宿主加載 pair 的 mod、送 `mode_enter`），`pair.exit` 送完後 `ExitMode("pair")` 再回到原本的模式；試衣間不切。

**寫不進去時**：卡片檔被別的程式開著（取代失敗）時，這筆資料放進待寫清單（同一張卡同一個 mod 只留最新的），每 0.5 秒的 ticker 依 2、4、8…最多 60 秒的間隔重試；下一次 `pair.enter`／`pair.exit` 交給 mod 的 `section` 用待寫的資料（比檔案新，統計不會倒退）；引擎結束前再試一次，仍失敗才記錯誤。

寫卡片用新加的 C ABI（共用程式碼）：

| 位置 | 內容 |
|---|---|
| `Tools/ok-extract/src/ffi.rs`、`include/ok_extract.h` | `ok_card_mod_section_get`／`ok_card_mod_section_set`：`okmods::read_data`／`with_data`，經暫存檔取代原檔 |
| `Plugins/KKUnityBundle/.../KKRustExtract.{h,cpp}` | `FOkSession::CardModSection`／`SetCardModSection` |

### `pair-counter` 範例（`Tools/ok-mod/examples/pair-counter`）

訂閱 `pair.enter`、`pair.finish`、`pair.exit`。1 對 1 結束時（試衣間、`cancelled` 不算）把 `{"times", "seconds", "her", "him", "last"}` 加進她卡片 `okMx` 的自己區段（版本 1；卡片資料比 mod 新就不寫）。讀卡器顯示要用 C 的 reader hook，同步點 B 後接。

### `subtitles` 的 1 對 1 部分

`pair.voice`（以及文字台詞 `pair.line`）已經送到訂閱的 mod；範例本體由 C 建立，同步點 B 後讓它訂閱 `pair.voice`。字幕的回覆要在 1 對 1 畫面上怎麼顯示（宣告式畫面文字）還沒有介面，等 C 的範例定形狀後在橋接加。

## 驗證（2026-11-23）

- 建置：`OpenKoikatsuEditor`、`OpenKoikatsu` Development（E 引擎）每次提交前建過，成功（含 ok-extract 改動後的 Rust 靜態庫重新連結）。ok-extract：`cargo test --release --lib card_mod_section`（新增 `card_mod_section_round_trip_keeps_identity_and_others`：寫入、讀回、緩衝不夠只回長度、移除、檔案不存在報錯；卡片身分不變、別的 mod 區段原樣保留）、`cargo check --release --no-default-features` 通過。`Tools/ok-mod`：`cargo build -j 8 --release --workspace`，`cargo test -p ok-mod-pair-counter` 2/2。
- **實機**（讀卡器 `-LegacyReader`，卡片用副本 `E:\OpenKoikatsu\Saved\OKModTest\pair\C050.png`，`pair-counter` 裝在 `Mods/`）：
  - 進 1 對 1：log `mode reader/pair: 1 mod(s) enabled: org.openkoikatsu.pair_counter`。
  - 摸胸部後離開：`pair-counter` 回 `1 time(s), 6 s`，橋接 `wrote its card data … (73 bytes, version 1)`，卡片多了 `okMx`。
  - 再進一次、摸頭、離開：`pair.exit` 的 payload 帶回上一筆區段，結果 `2 time(s), 100 s`（第二次停留約 94 秒）。
  - `pair.voice` 有送出（`source: tts`，`path` 是語音檔）；目前沒有 mod 訂閱，回覆是空的。
  - 回到讀卡器後卡片照常載入（`status: applied`）。
- `ok.PairModBridgeSelfTest`（假宿主，七種事件與 payload 欄位，加上寫入重試）：在最後的改動（逐 mod 送、切模式、重試）之後於實機重跑，**21/21 通過**（`E:\OpenKoikatsu\Saved\OKInteraction\pair_mod_bridge_selftest.txt`）。重試的檢查：用 UE 的 `CreateFileReader` 開著卡片檔（不帶 FILE_SHARE_DELETE），寫入失敗被保留、檔案裡還沒有；關掉後 `RetryPending` 寫進去、內容正確。
- **高潮計數**（同一張卡片副本，`ok.HScene.HisRate 20`、`ok.HScene.HerRate 20` 加快量表）：奉仕·手「單手交」開始 → `pair.finish outside`；插入「正常位」→ 插入 → 開始動 → `pair.finish orgW`。離開後 pair-counter 寫入 `{"times":3,"seconds":427.0,"her":1,"him":1}`。
- 實機中發現：愛撫與她獨自的高潮不經 `Finish()`，`pair.finish` 沒送。已補 `orgTouch`／`orgSolo`（提交 5b425d791）。

## 沒驗證的

- 讀卡器顯示這張卡的統計：要 C 的 reader hook（同步點 B 後）。卡片裡的資料目前只用 log 與 payload 的 `section` 確認，沒有在畫面上看。
- 愛撫高潮（`orgTouch`）與她獨自高潮（`orgSolo`）：新加的兩處只確認建置。實機用面板按鈕「摸私處」只摸一下，量表沒滿；持續愛撫要在她身上按住滑鼠，控制通道做不到。
- 從街區進的 1 對 1（`street` → `pair` → `street`）與獨立 1 對 1 遊戲模式：只跑了讀卡器進的那條路。
- `subtitles` 的 1 對 1 部分：事件有送，範例要等 C 建好（同步點 B 後接上並實測）。
- 重試只在同一次執行內：遊戲結束時檔案仍被占用，那筆資料遺失（記錯誤）。
