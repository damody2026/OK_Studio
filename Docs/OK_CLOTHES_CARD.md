# 服裝卡：匯出一套服裝、穿到別的角色（2026-11-21）

讀卡器讀進一張角色卡後，可以把目前顯示的這套服裝匯出成服裝卡 `.okclothes`，之後讀別的角色，再把任一張服裝卡套到她身上。

## 使用

讀卡器 › 衣服卡 › 衣服卡總欄 › 服裝卡（舊 UMG 介面在模型版面的服裝組下方），四個按鈕：

| 按鈕 | 作用 |
|---|---|
| 匯出服裝卡 | 目前顯示的這套服裝 → `<另存資料夾>/<卡名>_outfit<N>.okclothes`（另存資料夾沒填就是 `UserData/okclothes/`）。縮圖是角色現在穿著這套服裝的正面 T-pose（讀卡用的四視圖擷取）；角色沒顯示時用卡片原圖。 |
| 套用服裝卡 | 選一張 `.okclothes`，穿成目前角色的這套服裝：衣服與身上的飾品換成服裝卡的，**頭髮與頭上的飾品保留角色自己的**（見下方「保留頭髮」）。結果是工作卡 `Saved/OKClothes/Worn/<角色>+<服裝卡>.png`，套完立刻開啟；原卡不變，要保留請另存。 |
| 只換衣服 | 同上，但角色自己的飾品全部保留，服裝卡的飾品都不穿。 |
| 轉換服裝卡 | 遊戲的服裝卡（KoiKatuClothes PNG）→ `.okclothes`。 |
| 開啟資料夾（2026-11-23） | 用檔案總管開啟服裝卡資料夾（另存資料夾，沒填就是 `UserData/okclothes/`；不存在就先建）。把檔案丟進去再回來，按下它或「重新整理」就會出現。 |

按鈕下方是**服裝卡清單**：另存資料夾（匯出服裝卡寫到的地方）與 `UserData/okclothes/` 裡的 `.okclothes`，**以及直接丟進這兩個資料夾的遊戲原版服裝卡**（`*.png`，2026-11-23），新的在前，每張顯示縮圖與檔名。

**原版服裝卡不用先轉換**（2026-11-23）：把遊戲 `UserData/coordinate/` 的服裝卡 PNG 複製進資料夾就會列出來，點縮圖直接套（`okclothes::file::read_outfit`：先當 `.okclothes` 讀，不是就當 coordinate card 讀）。資料夾裡也可能放著**角色卡**（另存資料夾就是），所以清單只收**檔尾標記是 `【KoiKatuClothes】`** 的 PNG：讀的時候只 seek 走過 PNG 的 chunk 找到 `IEND`，再讀它後面 64 個位元組看標記，不會為了判斷而讀進一張上百 MB 的角色卡。原版服裝卡沒有自帶資源包，它的第三方 mod 和以前一樣來自安裝目錄的 zipmod；「轉換服裝卡」按鈕仍然留著（想先存成 `.okclothes` 時用）。點縮圖就套到目前選的角色身上；上方的「點縮圖＝換衣服（保留頭髮）／只換衣服（飾品全保留）」切換點下去的做法。匯出或轉換完的服裝卡馬上出現在清單最前面；自己把檔案放進資料夾，或換了另存資料夾，按「重新整理」。

**保留頭髮**（2026-11-22）：很多卡的頭髮是用飾品做的（刻晴、雷電、Alice 的雙馬尾），遊戲套服裝卡會連飾品一起換，頭髮就變成服裝卡那位的。讀卡器套用時逐格決定：

- 角色的飾品掛在頭上（`a_n_hair*`、`a_n_head*`、眼鏡、耳環、鼻、嘴），或 HairAccessoryCustomizer 標成頭髮的（有它的設定且「跟隨髮色」開著），保留在原格。
- 服裝卡的其他飾品（頸飾、腳環、手環、戒指等）照穿；服裝卡的頭髮與頭上飾品不穿。雷電的頭髮掛在 `a_n_head`，HairAccessoryCustomizer 沒有它，靠掛點認出；她腳踝的花是用頭髮零件做的（HairAccessoryCustomizer 有它，但「跟隨髮色」關著），算裝飾，照穿。
- 服裝卡的飾品要放的那格已被角色的頭髮佔用，就換到同一區（0–19 格，或 MoreAccessories 的 20 格以後）的第一個空格；Sideloader、Material Editor、HairAccessoryCustomizer、Accessory States、DynamicBoneEditor、ASS 的資料跟著換格。0–19 格全滿時放不下的會列在結果的 `dropped`。
- 化妝保留角色的。

遊戲原本的整套套用（頭髮一起換）只留在命令列 `--all` 與 FFI op 5。檢查一張卡哪幾格會被當成頭部保留：`ok-extract.exe X:/NoGame --oklib clothes-accessories <角色卡或 .okclothes>`（`HEAD` 是保留的格）。

**搜尋**：人物卡總欄與服裝卡清單上方各有一個搜尋框，打字就篩選。

- 空格隔開多個詞，每個詞都要符合（`apng 01`）。
- 沒有 `*`、`?` 的詞：名字或檔名裡含有就算（`刻晴`、`raiden`）。
- 有 `*`、`?` 的詞是萬用字元，比對整個名字或檔名（`*heroine_k*`、`raiden*`、`??_crowd_*`）。
- 不分大小寫。人物卡比對卡上的名字與檔名，服裝卡比對檔名。清單最多列 400 張，超過時請用搜尋縮小。

MCP 操作清單與搜尋（`ui_exec`）：`ok.ReaderScreen set 人物卡總欄›人物卡›Input = <搜尋>`、`ok.ReaderScreen set 衣服卡總欄›服裝卡›Input = <搜尋>`、`ok.ReaderScreen card <N>`（第 N 張縮圖，從 0 起；在服裝卡清單是套用那張服裝卡）、`ok.ReaderScreen press 點縮圖＝換衣服（保留頭髮）`（切換做法）。資料驅動頁面用 builder `okclothes_grid`。

MCP（`reader_call`）：`{"action":"action","command":"clothes_export","out":"<可省略>"}`、`{"action":"action","command":"clothes_wear","path":"<.okclothes>","clothes_only":false}`，結果寫在 log（`MCP clothes_export ok: ...`／`MCP clothes_wear ok: ...`）。

命令列：`ok-extract.exe <遊戲> --oklib clothes-wear <角色卡> <服裝卡> <服裝組> <輸出卡> [--clothes-only | --all]`（預設保留頭髮），與讀卡器走同一段程式（`okclothes::file::wear_into`）；`OK_BASE_LIBRARY` 指定基礎庫。

## 格式

`.okclothes` 是靜態 PNG（第一幀，不含 APNG 其他幀與 `ok*` chunk）加上：

| chunk | 內容 |
|---|---|
| `okCl` | msgpack：服裝 coordinate bytes、外掛資料（KKEx）、名稱、來源 |
| `okLc` | 來源 OK 卡的卡內資源包（第三方 mod 的模型、貼圖、zip 索引）；來源不是 OK 卡時沒有 |
| `okLt` | 來源 OK 卡的 tree answers（開卡時對 mods 樹的問答）；同上 |

雷電服裝 1：`okCl` 7.7 MB＋`okLc` 52 MB，整張 60 MB。目前帶的是來源卡整個資源包，沒有裁到這套服裝實際用到的部分。

## 穿到 OK 卡上

OK 卡只能用卡內資源包＋共用基礎庫開（strict），所以換了衣服的卡要重新封裝：

1. 角色不是 OK 卡但服裝卡帶資源包：先把角色做成 OK 卡（`remake_ok_card`）。
2. `wear_scoped` 寫入新的 coordinate（`--clothes-only` 保留角色的飾品）。
3. `merge_card_pack`：角色自己的資源包加上服裝卡的，兩邊都有的項目以角色的為準。
4. `tree_answers::merge`：角色的 answers 加上服裝卡的，同一題以角色的為準；**不重錄** answers（`seal_card_with(..., false)`），因為共用基礎庫的樹裡沒有服裝的第三方 mod，重錄會遺失。
5. 封裝（complete＋strict-check，各在獨立的 `ok-extract.exe` 程序），再 `remake_ok_card` 算 digest。

以一組 GUID 為題目的 answers（`guids`、`strip-all`）：穿了別人衣服的卡會一次問到兩張卡的 GUID，沒有任何一筆記錄剛好是這個集合；`tree_answers::lookup_covered` 在單筆找不到時，把題目集合和要問的名稱有交集的記錄合起來，只要合起來涵蓋全部名稱就用。

## 驗證（2026-11-21，F）

- 命令列：惠惠（OK 卡）穿雷電服裝 1，約 23 秒，封裝 `added zips=28`，嚴格重開成功。
- 讀卡器：刻晴套用雷電服裝卡（全套）約 40 秒，顯示紫紗袍、泳裝、腳環與雷電髮飾；「只換衣服」刻晴保留自己的髮飾，只換衣服，log 無 unanswered。
- 匯出：服裝卡縮圖是穿著這套服裝的正面 T-pose。
- 清單：點雷電服裝卡縮圖套到 Alice（整套，頭髮換成雷電的；只換衣服，保留白色雙馬尾與耳機）；刻晴匯出後清單從 2 張變 3 張，新卡在最前面且有縮圖。
- 搜尋：`*heroine_k*` → 刻晴、Klara 2 張；`apng 01` → 9 張；`刻晴` → 1 張；服裝卡 `raiden*` → 1 張。
- 保留頭髮（2026-11-22）：點雷電服裝卡縮圖，刻晴保留淡紫長髮與頭飾（0、1、2、3、5 格），穿上雷電的大袖、泳裝、頸飾、腳環與腳踝的花，腳環從第 3 格換到第 4 格（Sideloader、Material Editor 跟著換）；Alice 保留白色雙馬尾與耳機，她用飾品做的外套袖子換成雷電的。命令列 `clothes-wear` 刻晴＋雷電約 38 秒。

## 未做

- 資源包裁切（只帶這套服裝用到的模型）。套用速度見下一節（2026-11-23：47.9 → 11.7 s，還有一步可做）。

## 套用很慢：時間花在哪，與只重封一套（2026-11-23，F）

使用者：「在衣服卡總欄點一張服裝卡縮圖套到角色身上，套用之後明顯很慢。」**先量再改**：量的是
`okclothes::file::wear_into`（讀卡器點縮圖 → `WearOkClothesReported` → `FOkSession::ClothesWear` →
`ok_clothes_file` op 2 走的就是這一段）加上它之後讀卡器重開那張卡。

量法：`ok-clothes-bench`（新增，`Tools/ok-extract/src/bin/ok-clothes-bench.rs`），全新程序、`OK_NOCACHE=1`、
`RAYON_NUM_THREADS=8`、一次一個行程，`OK_PROFILE=1` 印出 `wear:` 各段。題目用讀卡器實際會遇到的組合：
`crowd_C020`（OK 卡，**7 套服裝**）穿 `raiden_outfit1.okclothes`（60 MB，帶資源包），scope `keephair`
（畫面上寫「點縮圖＝換衣服（保留頭髮）」那個做法）。走的是和讀卡器同一段 Rust 程式與同一個基礎庫，
UE 那邊只是把結果的卡重開一次（量到 0.64 s，見下表）。

**改前的分解**（47.9 s，每一行都是真的跑過的那一段，沒跑的階段就不印那一行）：

| 階段 | ms | 占比 |
|---|---:|---:|
| 讀服裝卡＋讀角色卡＋寫入 coordinate＋`merge_card_pack`＋answers | 838 | 1.7% |
| `seal: answers step`（answers 保留，沒重錄） | 43 | 0.1% |
| **`seal: complete step`**（獨立 `ok-extract.exe`，**7 套 × 6 次開卡 = 42 次**） | **13 353** | 27.9% |
| **`seal: strict-check step`**（又一個獨立程序，再 42 次＋gag eyes） | **14 665** | 30.6% |
| **`refresh: every outfit opened`**（`remake_ok_card`，再 42 次） | **17 859** | 37.3% |
| `refresh: models+digest (outfit 0)` | 466 | 1.0% |
| **合計** | **47 913** | |
| 之後讀卡器重開那張卡 | 640 | — |

也就是**97% 是三趟「整個衣櫃」的重複開卡，共 126 次**，而使用者只換了其中一套；而且封裝的結果是
`added files=0 zips=40 zip entries=0 model records=0 (0 bytes)` —— **28.6 秒的封裝什麼都沒加進去**。
讀卡器重開卡只占 1.3%，所以**慢的不是「整張卡重開」，是重新封裝**。

**改動：只重封換掉的那一套**（`oklib::OnlyOutfitScope` / `OK_SEAL_ONLY_OUTFIT`）。穿服裝卡只改一套
coordinate，其他幾套的位元組完全沒動，而上面第 3、4 步的兩個合併都**只會加不會刪**，所以封裝、
strict-check 與 remake 這三趟只需要開那一套。`open_outfits` 是這三趟共同的瓶頸點，所以改一處就夠；
`with_tree_answers`（重錄 answers）有自己的迴圈，**不受影響**，answers 仍然涵蓋全部服裝。
`OK_SEAL_EVERY_OUTFIT=1` 回到舊行為（A/B 用）。

**同一把尺重量**（同一個執行檔、環境變數切換、同時段）：

| | 舊（每套都開） | 新（只開換掉的那一套） |
|---|---:|---:|
| `wear` | 47.9 / 45.7 / 57.3 / 60.9 s | 11.7 / 11.2 / 14.2 / 14.6 s |
| 之後重開卡 | 0.64 s | 0.63 s |
| **點縮圖到可互動** | **57.9 s** / **61.6 s**（兩對同時段的） | **14.8 s（−74.5%）** / **15.3 s（−75.2%）** |
| `seal: complete` / `strict-check` / `refresh` | 13.4 / 14.7 / 17.9 s | 3.5 / 3.0 / 3.2 s |

**開關是活的**：log 多一行 `refresh: only outfit 0 of 7 (the others are unchanged)`，封裝摘要的 `zips` 40 → 20。

**正確性**：
- 兩邊的卡 `digest` 相同（`4c1587cdf942b99d8f7b043699430b24`），資源包長度相同（103 670 502），
  兩邊都 `added ... 0 bytes`，重開的 parts 都是 63。
- 兩張卡各跑一次**完整**的 `--oklib strict-check`（7 套 × 每種服裝狀態，不是只檢查那一套）：都 `OKSTRICT ok`
  （15.8 s / 15.0 s）。
- **唯一的差別**：`okLb` 的 models 清單少一個 id（`8892020000000000af5ef8844f4b4331`，35 bytes）。那是
  **別的服裝**才會碰到、而且**她原本那張卡的清單裡本來就沒有**的模型（原卡 91 個，舊做法變 97 個，新做法 96 個）：
  舊做法順手補的是「這張卡封裝時還沒有這筆」留下的舊缺口，和這次換衣服無關。這份清單**只被開卡快取的
  鍵用到**（`session_cache_key`），而開卡磁碟快取在這個專案永久關閉，所以今天沒有任何可見影響；要補那個
  缺口就是對整張卡重封（`--oklib seal`）。

**還能拿的（下一步怎麼查）**：剩下的 14 s 裡約 11 s 還是**同一套服裝被開了 18 次**（三趟各 6 種服裝狀態）
＋digest 那一次。要再縮就得讓後兩趟不必重開：封裝那個子程序已經知道「自己碰了哪些模型」與
「嚴格開卡過不過」，把這兩樣從子程序的 stdout 帶回父程序，取代 strict-check 與 refresh 的重開。
這會動到 strict 開卡之間的狀態共享，而那正是花火（11-12）與 alice（11-16）兩個 bug 的來源，所以要先把
「每趟各自冷開」這條不變式想清楚再動，不要為了省時間讓兩趟共用解析結果。

## 服裝卡資料夾與原版服裝卡（2026-11-23，F）

使用者：「還要能打開衣服卡的資料夾，放原版的衣服卡。」

- **開啟資料夾**按鈕（衣服卡總欄 › 服裝卡，和「重新整理」同一排）：用檔案總管開啟服裝卡資料夾
  （`UOKCharacterController::OkClothesFolderPath`，不存在就先建），按下它回來時順手重讀清單。
- **原版服裝卡直接列、直接套**：`okclothes::file::read_outfit` 先把檔案當 `.okclothes` 讀，不是就當遊戲的
  coordinate card 讀（`import_coordinate`）；`wear_into`／`wear_file`／`wear_clothes_only_file` 都走它，所以讀卡器、
  命令列 `--oklib clothes-wear` 與 FFI 都一樣。清單只收檔尾標記 `【KoiKatuClothes】` 的 PNG（`OKIsCoordinateCardFile`：
  只 seek 走 chunk 找 `IEND`，再讀後面 64 bytes，不把上百 MB 的角色卡讀進來）。
- **連帶修掉一個真的 bug**：原本只要服裝卡沒有自己的 answers（原版服裝卡就是），就把**角色自己的 answers 整個丟掉重錄**
  （`strip_answers` ＋ `Answers::Record`），而共用基礎庫的樹答不出她自己那些題，於是封裝直接失敗：
  `5 unanswered question(s): okLt cat 403 1881; 410 4; 411 2; 423 702; 424 9017` —— **五題全是她自己的**（體毛、臉、
  身體貼圖），和服裝無關。現在：她有 answers 就一定保留，服裝卡沒帶 answers 時改用 `Answers::Add`
  （保留她的，再從共用基礎庫補錄），因為穿上別人的衣服之後問的 mod GUID 集合變了，她原本那一筆蓋不住。
  帶 answers 的 `.okclothes` 走的還是原本的 merge，**量測那條路一個位元組都沒變**。

**驗證**（2026-11-23，F，`crowd_C020` 7 套服裝，基礎庫 `base_v1`）：

| 題目 | 結果 |
|---|---|
| `KKCoordeF_20201021052531777.png`（遊戲原版服裝卡，只用原版與共用資源） | 套成功，封裝 `added files=1 zips=18 zip entries=3 model records=21 (2 718 661 bytes)`；worn 卡跑**完整** `--oklib strict-check`（7 套 × 每種服裝狀態）`OKSTRICT ok` 11.4 s |
| `raiden_outfit1.okclothes`（帶資源包） | 不受影響（走 merge 那條），parts 63，`digest` 與改前相同 |
| `Chun.png`（原版服裝卡，衣服來自非共用的 `[makise]chun.zipmod`） | **還是不行**：`1 unanswered question: GAMEFS zip-entry mods/.../[makise]chun.zipmod\|abdata/chara/[makise]chun.unity3d`（修之前是 6 題） |

**沒做、卡在哪**：原版服裝卡**用到非共用 mod** 時套不到 OK 卡上。原因是封裝那兩個子程序是用 `X:/NoGame` 跑的
（OK 卡的嚴格封裝本來就不該看安裝目錄），所以那個 zipmod 的 entry 沒人能提供。下一步是把安裝目錄
（`wear_into` 已經有的 `game`）傳進 `seal_card_with` 的子程序，讓封裝**把那筆 entry 複製進 worn 卡的資源包**
（和原作卡轉 OK 卡時一樣），封完的卡仍然自足；要先確認 `okstrict` 對「來自遊戲根目錄的讀取」是記成 addition
還是只是答掉（只答掉就白做）。現成的替代做法：從**有那個 mod 的角色卡**匯出服裝卡，那樣的 `.okclothes` 自帶資源包。
