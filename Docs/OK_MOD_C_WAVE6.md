# OK Mod 第六波（C 組，2026-11-23）：街區資料表擴充與補測

依協調者的決定，第四波回報建議的 1、2、4 都做了，3 不做：
- 1：mod 的 `street/*.toml`；
- 2：商品與禮物併進街區目錄；
- 4：話題當 AI 素材；
- 3（ok-rules 規則表疊加）：見 §5 待辦。

`ok-mod-api` 沒改，`Event` 沒有新增變體。宿主只加了一個新檔與兩行接線（§2）。

## 1. 資料表格式：`Mods/<id>/street/*.toml`

同一資料夾裡的檔案依檔名順序讀，每個檔案可以有兩種表：

```toml
[[items]]                 # 一件商品／禮物，形狀同 catalog.json 的 items
id = "birthday_cake"      # 名稱 [a-z0-9_]、最多 48 字；宿主一律改成 <mod id>.<名稱>
name = "生日小蛋糕"
names = { "zh-CN" = "生日小蛋糕", en = "Small birthday cake" }  # 選填，依街區語言挑
place = "department"      # 哪家店賣（必須是街區現有的店）
category = "gift"         # 預設 gift
price = 88                # 以元寫（基準地區）；或 { "" = 88, L = 120 } 分尺寸；1..1000000
giftable = true           # 預設 true
consumable = true         # 預設 false
tags = ["sweet", "birthday"]
effects = { mood = 8 }    # 數字表
# 也接受 options、season、prop、floor，意思同 catalog.json

[[topics]]                # 她聊天時可用的素材
lang = "zh-TW"            # 選填；沒寫就每種語言都用
text = "生日那天，被記得的人準備一點小東西，比東西本身更讓人開心。"   # 最多 300 字
```

限制：
- 一個 mod 最多 200 件商品、50 段話題；
- 壞掉的列會被丟掉，並寫進 `problems`，同檔案的其他列照常讀；
- 不認得的表（例如 `[[shops]]`）也記進 `problems`。

## 2. 宿主：列出與驗證（`Tools/ok-mod/host`，同步點請協調者處理）

- **新檔** `host/src/street_data.rs`：
  - 新的 op `{"op":"street_data"}` 讀取所有 enabled 的 mod，回 `{"items","topics","problems"}`；
  - 驗證 id 前綴、價格範圍、tags／effects 型別與字數；
  - 附一個單元測試。
- **接線**：
  - `host/src/lib.rs` 加 `pub mod street_data;`；
  - `host/src/ffi.rs` 的 op 分派加一行 `other if crate::street_data::OPS.contains(&other) => …`。
- **`Tools/ok-mod/pack/src/lib.rs`（F 的範圍）**：`PACKED_DIRS` 加了 `"street"`，這樣打包時會帶上 mod 的街區資料表。只改了這一個字，同步時請 F 確認。
- 只有街區知道的事由 UE 檢查：店要存在，商品 id 不能蓋掉內建商品。

## 3. 街區（UE）與規則（ok-rules）

- **併進商品目錄**：
  - `LoadCatalog()` 最後呼叫 `ModsMergeStreetData()`，所以順序是 `OKStreetLoadCatalog` 之後。
  - catalog 一列的解析抽成 `OKStreetCatalogItemFrom`（`OKStreetSocialEconomy.h`），內建商品和 mod 商品用同一份。
  - 會跳過與內建 id 重複的列，也會跳過店不存在的列。名稱取 `names[語言]`。
- **規則也要認得**：送禮與價格規則依商品 id 查目錄，ok-rules 的目錄是編進 DLL 的，所以新增了規則請求 `catalog_extend`（`Tools/ok-rules/src/lib.rs`、`tuning.rs`）：
  - `Tuning::load_with(dir, extra_items)` 把 mod 商品接在目錄 JSON 的 `items` 後面再解析，每個地區與語言的目錄都跟著換算；
  - `Rules` 記住這份清單，`reload()` 時沿用；
  - 清單沒變不重載，空清單就移除 mod 商品。
  - 街區在 `S.Rules` 建好後的那個 Tick 送出一次。
  - 這不是被否決的「3. 規則表疊加」：只接受商品列，不疊加規則或數值。
  - 測試 `catalog_extend_adds_mod_items_in_every_region` 驗證四件事：美國價格有換算、不蓋內建商品、同樣的清單不重載、空清單移除。
- **話題素材**：
  - 依語言篩選（完全相同，或兩字前綴相同），組成「`ui.director.mod_topics_header`＋每行一段」，接在她 system prompt 的 World 段（`OKStreetPlaceCatalogue()` 後面）。
  - 這是靜態段，同一局不變，所以守住 DeepSeek 快取前綴規則。
  - `topic_catalogue` 沒動。
  - 標題文字加進三語 `ui_text.toml`。

## 4. 範例：`birthday`

`Tools/ok-mod/examples/birthday/street/birthday.toml` 包含：
- 一件 ¥88 的「生日小蛋糕」，在大學城百貨賣，可送禮；
- 每種語言兩段生日話題。

本機 `Mods/birthday/street/` 有一份複本。

## 5. 待辦：ok-rules 規則表疊加（3）

照決定不做。需要時的方向：
- 讓 mod 提供 `tuning` 片段（數值覆寫，不提供規則程式），沿用 `load_with` 的作法在 `reload()` 時疊上；
- 每個值都要記錄是哪個 mod 改的；
- 衝突時以載入順序為準，並寫進 `problems`。

## 6. 實測

**街區**：stage `probe1123e`（`staged_at` 1700000002，比 `c1119a` 早，所以 StreetSocial.cmd 不會挑到它），`-Sandbox cmod6 -PortBase 48160`。

| 項目 | 結果 |
|---|---|
| 讀資料表 | log 有 `street data: 1 item(s) into the catalog, 2 topic line(s) for her prompt` 與 `the rules know 1 of 1` |
| 商品出現在店裡 | 大學城百貨的選單有「生日小蛋糕 ¥88」 |
| 買 | 現金 1783 → 1695 |
| 送禮 | 送給克拉拉，她收下；`street.gift` 有觸發 |
| 話題進入 prompt | mind 的 context 裡有「可以聊的素材（已安裝的 mod 提供；合適時才用）：」，只有 zh-TW 的兩行；之後幾輪都命中快取（19968 tokens） |
| 熱鍵回 JSON | hook-probe 加了 F9（`probe_notice`），回覆 `{"notice": …}` 加上 `street::with_cards` 刪除自己的卡片資料。按 F9（`ui_type`）後訊息列出現 `hook-probe: F9 in street`；接著做 `street.load`，log 有 `removed its data in apng-21399…'s card (0 bytes)`，`notice` 與 `cards` 兩條路都通 |
| 卡片沒被汙染 | `Content/CharacterCards/StreetHeroines/*.png` 和 `Saved/HookProbe/cards_backup/` 比對，內容相同 |

**讀卡器**（`-ini:Game:[/Script/KKSideloader.KKGameRoot]:Root=D:/XKoikatuSunshine`）：
- `reader.accessory_transfer`：`{from:0,to:7}` 有觸發；SDK 型別解析沒有任何一行警告。
- **`subtitles` mod**（計畫 §16.5「缺 `comm_lines.json`」）：
  - **來源**：`comm_lines.json` 是遊戲語音匯出 `voice_extract` 的一部分，這台機器在 `D:\XKoikatuSunshine\voice_extract\comm_lines.json`，由 `KKSpeech.cpp` 從「語音根目錄」讀取。
  - **為什麼之前讀不到**：讀卡器的 `DefaultVoiceRoot()` 依序找 `OK_VOICE_ROOT`、基礎庫 `base_v1/h/voice`、`<GameRoot>/voice_extract`、開發用路徑，第一個有 `h_breath_index.json` 的就用。基礎庫的 `h/voice` 只有 H 語音，沒有一般對話的 `comm_lines.json`，但它排在前面，所以一般對話永遠讀不到。
  - **補法**：以 `OK_VOICE_ROOT=D:/XKoikatuSunshine/voice_extract` 啟動。log 出現 `Voice root: D:/XKoikatuSunshine/voice_extract`，然後 `load_speech`、`speak`，畫面上出現字幕通知「そうね、なにをして遊ぶか迷っちゃうわ♡」（`ok.ReaderScreen notice`）。也就是 `reader.speech_start` → subtitles 回覆 → 讀卡器顯示，整條路都通。
  - **沒改程式**：語音根目錄的優先順序是讀卡器原本的設計，H 語音確實要用基礎庫。若要讓一般對話自動找到 `<GameRoot>/voice_extract`，應該讓 `DefaultVoiceRoot` 分開挑 H 語音和一般對話的根目錄。這是另外的工作，見 §8。

## 7. 驗證

- `cargo test`（`Tools/ok-mod` workspace）全部通過；`Tools/ok-rules` 305 passed（release）；
- `cargo check` `Tools/ok-extract`，以及加 `--no-default-features`，都通過；
- `may-build` 確認後，在 D: 引擎建置 `OpenKoikatsuEditor` 與 `OpenKoikatsu` Development，連結成功（建置時間晚於最後一次改原始碼）；
- Unreal 名額 `c-mod-6`，用完已釋放。

## 8. 沒驗證／留給之後

- mod 商品在美國等其他地區的價格，只在 ok-rules 單元測試驗過，沒有實機切換地區看。
- `price` 分尺寸（`{ "" = …, L = … }`）只有宿主單元測試，沒有實機買。
- 一般對話自動找 `<GameRoot>/voice_extract`（§6 讀卡器）沒做。
- stage `probe1123c`／`probe1123d`／`probe1123e` 都留著，最後整合時請協調者處理（裡面有 junction，不能遞迴刪除）。
