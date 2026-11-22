# OK Mod 工作項 2：卡片 chunk 與身分（C 組，2026-11-23）

計畫：F 的 `Docs/OK_MOD_FRAMEWORK_PLAN.md` §6.2、§6.12、§13 第 1～2 項、§15.4 第 2 列；盤點 `Docs/OK_MOD_HOOK_INVENTORY.md` §5.3、§5.4。

## 做了什麼

### 1. 身分三處統一

規則：卡上有 `okId`（64 位十六進位）就用它；否則是整張 PNG 扣掉 **`okVo`（語音）、`okMx`（mod 資料）、`okMr`（mod 資源）** 三種 chunk 之後的 sha256。

| 實作 | 位置 | 改動 |
|---|---|---|
| Rust | `Tools/ok-extract/src/oklib.rs` `card_identity` | 排除清單改用 `okmods::IDENTITY_EXCLUDED`（原本只排除 `okVo`） |
| Lua | `Tools/prepare_street_social_selection.lua` `card_identity` | 同上三種；沒有這三種 chunk 時照舊直接算整檔 sha256（快路徑不變） |
| C++ | 新檔 `Source/OpenKoikatsu/OKCardIdentity.{h,cpp}`＋`OKCardIdentityCore.inl`；`OKReaderTalk.cpp` 改呼叫它 | 原本沒有 `okId` 的卡算**整檔 MD5**、ID 前綴 `reader:`，和街區對不上（盤點 §5.3 的既有問題）。改成和另外兩處同一套 sha256，ID 一律 `apng-<身分>`；只有不是 PNG 時才退回舊的 `reader:<MD5>` |

C++ 的 SHA-256 寫在不含 Unreal 型別的 `OKCardIdentityCore.inl`，可以單獨用 `cl` 編成小工具，拿來和 Rust、Lua 逐張比對（見下方驗證）。UE 沒有現成的 SHA-256，也不想為此在 `OpenKoikatsu.Build.cs` 加 OpenSSL 相依。

### 2. `okMx`／`okMr` 編解碼與原樣保留（新檔 `Tools/ok-extract/src/okmods.rs`）

- `okMx`：msgpack map `{ mod_id: { version: u32, requires: { id, version }, data: bin } }`。
  - `ModData` 把 map 存成「原始 key 位元組＋原始 value 位元組」，只有 mod 自己 `set` 的那一段會重新編碼；別人的區段（包含這一版不認識的欄位、非最短的整數編碼）一個位元組都不動，對應 ExtendedSave 的「不認識的資料原樣保留」。
  - `Section::decode` 只讀 `version`／`requires`／`data`，多的欄位忽略（但原始位元組保留）。
- `okMr`：zstd（level 3）壓縮的 msgpack map `{ sha256 十六進位: bin }`；`Resources::add` 依內容 sha256 去重，`total_bytes` 給宿主算每個 mod 100 MiB 上限用（上限本身由 F 的工作項 9 做）。
- 寫入：`with_data`／`with_resources` 一律經 `tree_answers::with_chunk`，沒有 `okId` 的卡會順便寫入它原本的身分（§6.2「第一次寫 `okMx` 時順便寫 `okId`」）；區段清空時整個 chunk 移除，身分照樣保留。
- 重製卡片：`oklib.rs` `keep_identity` 多叫一次 `okmods::carry_over`，把輸入卡的 `okMx`／`okMr` 原封搬到新卡。`refresh_edited_ok_card`（帶 `okLt` 的卡）原本就整張沿用，`remake_from_card_data`（從卡片資料重轉）原本會丟，現在保留。
- 讀卡器另存（`KKCardWriter::SaveWithEdits`）是把 PNG 段整段複製（`PngEndOffset`），本來就會保留任何 chunk，沒有改。

### 3. 開卡快取鍵加「啟用的 mod 與版本」

- `okmods::set_enabled(Vec<(id, version)>)` 由 mod 宿主在載入 mod 後呼叫（F 的工作項 6 接上；目前沒有呼叫者）。
- `oklib.rs` `session_cache_key` 在有啟用 mod 時多雜湊 `b"mods"`＋排序後的 `id@version` 清單。**沒有 mod 時鍵和以前完全相同**，所以現有的開卡快取不會失效，也不需要升 `SESSION_CACHE_REVISION`（C、E、F 目前都是 44，沒動）。
- `okBk`（卡內烘焙的開卡結果）用同一把鍵查，裝了 mod 時自然對不上而改走一般開卡，不會拿到沒套 mod 的結果。

## 驗了什麼

| 項目 | 結果 |
|---|---|
| `cargo test --release --lib -- okmods card_identity tree_answers cardbake` | 8 個通過（新增 5 個：身分排除三種 chunk、未知區段逐位元組保留、`okMr` 去重與往返、`carry_over`、快取鍵只在有 mod 時加料） |
| 現有卡身分逐張比對：`Content/CharacterCards` 與 `UserData` 共 **368 張** PNG（其中 27 張帶 `okVo`、132 張帶 `okId`） | Rust 新舊實作 368／368 相同（`okmods::tests::identities_unchanged`，`--ignored`）；Lua 新舊 368／368 相同；C++ 新實作與 Lua、Rust 的結果 368／368 相同 |
| 手工加 `okMx`／`okMr` 的卡（`jeanne.png` 有 `okId`；`ill_ss_sample_00_cards/char_0.png` 沒有 `okId`） | 三種實作的身分都和加之前相同 |
| 重製：`ok-extract X:/NoGame --oklib card`（帶 `okLt`，走 `refresh_edited_ok_card`） | `okMx`／`okMr` 原樣還在，身分不變 |
| 重製：拿掉 `okLt` 後 `ok-extract D:/XKoikatuSunshine --oklib card`（走 `remake_from_card_data`，從 zipmod 重轉） | `okMx`／`okMr` 原樣還在，身分不變 |
| `cargo check --lib` 與 `--no-default-features` | 通過，`okmods.rs` 沒有警告 |
| UE：`may-build` 後用 D: 引擎建 `OpenKoikatsuEditor`、`OpenKoikatsu` Development | 兩個都 `Result: Succeeded`、連結成功（`OKCardIdentity.cpp` 有編到） |
| 開卡基準 | 見下方「開卡基準」 |

## 開卡基準

- `card_open_baseline.lua -Compare latest`（5 輪）：TOTAL 8.01 s，對 `latest.json`（**舊提交 5edfc093a**，3 輪）6.48 s 是 +23.6%。但這次各輪 6.92～9.09 s，跑的時候機器 CPU 負載約 77%（其他程式），而且比的是好幾個提交以前的基準，這個百分比不能拿來判斷。**不受負載影響的工作量計數**：474 → 473，相同。
- 所以另外做了**同一時段交錯 A/B**：用 `git archive HEAD` 建一份沒有本次改動的 `ok-card-open-bench`（暫存目錄，獨立 target），和本次改動輪流跑，各兩次、每次 3 輪：

  | 次序 | HEAD（無本次改動） | 本次改動 |
  |---|---|---|
  | 第 1 次 | 10.25 s（10.79／8.56／10.25） | 8.58 s（7.22／8.58／9.85） |
  | 第 2 次 | 7.19 s（7.19／6.90／7.53） | 7.84 s（8.43／7.84／7.20） |
  | 工作量計數 | 474、475 | 473、473 |

  兩邊平均 8.72 s 對 8.21 s，同一份程式前後兩次就差 30%，時間差異完全在雜訊裡；工作量相同。
- 從程式看也碰不到開卡冷路徑：基準關掉開卡快取，`session::open_unconfigured` 在快取、`okBk`、`okMm` 都沒開時根本不算 `session_cache_key`（`keyed` 為 false）；`card_identity` 不在開卡路徑上，只在轉卡、重製、寫 chunk 時用。
- **結論**：沒有看到變慢；但機器安靜時的 < 3% 時間量測沒有做到（負載不是這個 session 能控制的），協調者若需要，可在機器空閒時重跑 `Tools\lua\lua.exe Tools\card_open_baseline.lua -Compare latest`（`latest.json` 現在就是本次改動的結果）。

## 沒驗什麼

- **讀卡器實際開啟帶 `okMx` 的卡並另存**：沒開 Unreal 測；依據是 `KKCardWriter` 整段複製 PNG 的程式碼。M1 驗收（工作項 7）時會實測。
- **C++ 身分在遊戲內**：只用同一份 `OKCardIdentityCore.inl` 編的獨立工具比對；遊戲內 `OKReaderTalk` 的 log 行 `Card reader talk: ... id=` 沒有實際開讀卡對話看。
- **行為改變：讀卡對話的舊記憶**（協調者已同意，也記在 `Docs/ERROR_LOG.md`）：沒有 `okId` 的卡，讀卡對話以前用 `reader:<MD5>` 存在 `mind` 的記憶，現在改用 `apng-<sha256>`（與街區一致），那些舊記憶不會自動搬過去，這些卡在讀卡對話裡等於重新認識。有 `okId` 的卡（所有 OK 卡）不受影響。
- `set_enabled` 還沒有呼叫者，快取鍵「裝了 mod 會變」只有單元測試，等 F 的宿主接上後在同步點 A 之後實測。
- `okMr` 的 100 MiB 上限、`okMx` 的 `on_upgrade` 都不在本項（工作項 9、7）。

## 開卡基準補量（2026-11-23，機器閒時）

`Tools\lua\lua.exe Tools\card_open_baseline.lua -Compare latest`，量之前 `unreal_slot status` 顯示沒有任何 Unreal 在跑。程式是 C master 工作項 7、10 之後（含本工作項的 `okmods` 快取鍵，以及工作項 10 的 `changes_opens` 修正）。

- 總計（5 輪中位數）5.39 秒（各輪 5.36、5.46、5.36、5.60、5.39），對照上一份 `latest.json`（57fd839f6）7.84 秒：**-31.3%，沒有變慢**。上一份是在較忙的機器上量的，變快的幅度不代表本工作項讓開卡變快。
- 和機器忙不忙無關的工作量計數：`work from scratch` 473 → 472（-1）。
- 報告：`C:\portable\OpenKoikatsu\Saved\Reports\card-open-baseline\20261122-194638.json`。

## 後續修正：開卡快取鍵只算會影響開卡的 mod（2026-11-23，工作項 10 發現，協調者已採納）

本工作項原本讓開卡快取鍵（`session_cache_key`）包含**所有啟用的 mod 與版本**。工作項 10 在街區實測時發現這太寬：只要裝了任何 mod（例如只管街區的 birthday），所有卡的快取都不再命中，等於每張卡都冷開；而街區有幾張卡在遊戲內冷開本來就會失敗（既有問題，見 `Docs/ERROR_LOG.md`），平常被快取擋住，鍵一變就全部冒出來。

修正（ok-extract `okmods::changes_opens`）：快取鍵只算**訂閱了開卡時會跑的 `extract.*` 掛點**的 mod。`extract.kkex`、`extract.kkex_keys` 只在轉原作卡時跑，不改變開卡結果，不算。讀卡器、街區、字幕這類 mod 不再讓快取失效；之後真的會改開卡結果的 mod（例如貼圖後處理）仍然會換鍵，快取不會拿到舊結果。`OKModModes.cpp` 送給 ok-extract 的啟用清單也照同一條件過濾。

原因：快取鍵要放「真的會改變結果的東西」，不是「所有可能相關的東西」。這也符合計畫 §6.7「開卡基準不得因『裝了但沒訂閱』的 mod 變慢」（§6.1）。上面的補量（-31.3%、工作量 473 → 472）已含這個修正；上一份基準是在較忙的機器上量的，時間變快主要是機器狀態不同，工作量計數才是可信的那個數。
