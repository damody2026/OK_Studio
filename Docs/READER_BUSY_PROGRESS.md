# 讀卡器的進度條（2026-11-24，F）

規則（使用者 2026-11-24）：**`CardReaderDevelopment.cmd` 裡任何超過 0.5 秒的 UI 動作都要顯示載入進度條。**

條子在 3D 視圖上方（通知列原本的位置，有條子時通知往下讓位），一行字加一條進度。實拍：

| 畫面 | 內容 |
|---|---|
| `Saved/ClothesBugCheck/busy_wear_percent.png` | `24%　套用服裝卡 · 封裝：把卡片缺的共用資源複製進去（3 秒）`，條子填到 24% |
| `Saved/ClothesBugCheck/busy_load3d_marquee.png` | `載入3D · 建立顯示（2 秒）`，報不出比例，條子是來回掃的那一小段 |

## 怎麼運作

| 檔案 | 做什麼 |
|---|---|
| [`Source/OpenKoikatsu/OKBusyProgress.h/.cpp`](../Source/OpenKoikatsu/OKBusyProgress.h) | 全行程一份、有鎖的工作清單。`OKBusy::Begin(標題)` 開一筆、回傳 id，`Progress(id, 0..1, 步驟名)` 更新，`End(id)` 收掉；`FScope` 是 RAII 版本。任何執行緒都能呼叫。 |
| `UOKReaderScreen::TickBusy`（[OKReaderScreen.cpp](../Source/OpenKoikatsu/OKReaderScreen.cpp)） | 每幀看最新那一筆：跑**超過 0.5 秒**才顯示（`OKBusy::ShowAfterSeconds`）。 |
| `UOKCharacterController::TickBusyProgress`（[OKGalleryClothing.cpp](../Source/OpenKoikatsu/OKGalleryClothing.cpp)） | 10 Hz 把 ok-extract 自己的進度（`FOkSession::JobProgress`，Rust `progress.rs`）餵進有標 `bFollowsExtract` 的那一筆。 |
| `DUI/Reader/ReaderScreen.dui` 的 `Busy` / `BusyText` / `BusyBar` | 版面。改完要跑 `Tools\lua\lua.exe Tools\build_reader_ui.lua` 重編 `Content/UI/Reader/WBP_ReaderScreen`。 |

**0.5 秒才出現**，所以一瞬間就做完的動作不會閃一下條子——這條規則本身就是「超過半秒的才要講」。

**沒有假百分比**：報得出比例的才填條子，報不出的走 marquee（一小段來回掃），字上只有真實的經過秒數。`UDreamProgressBar::SetIsMarquee`。

## 哪些動作在條子上

| 動作 | 進度來源 |
|---|---|
| 載入3D（開卡、換服裝狀態、換套裝） | 步驟名（讀卡片／建立顯示）＋ marquee |
| 套用服裝卡（點縮圖、套用服裝卡、只換衣服） | **真實百分比**，封裝與嚴格檢查的子行程自己回報 |
| 匯出服裝卡 / 轉換服裝卡 | marquee（**這兩個本來卡在遊戲執行緒上，這次搬到背景執行緒**，不然畫面整個停住也畫不出條子） |
| 另存：轉成 OK 卡 / 保存服裝資源 / 產生低模 | marquee |
| 拍人物視圖 / 編碼人物視圖（四視圖 APNG、服裝卡封面、配種參考圖） | marquee |
| 配種 / 匯出完整卡 / 寫回孩子的卡面 | marquee |
| 生成頭髮（HairDeck） | marquee |
| 載入配對角色 / 準備配對動畫 / 準備配對動作片段 | marquee |
| 載入動作 / 整理動畫清單 | marquee |
| 套用外觀 / 寫入人物卡 | marquee |

**不在條子上的**，因為不是使用者按出來的動作：開場 prewarm、卡片縮圖與 metadata 的背景解碼、鄰居卡預載、衣物狀態的投機預熱、語音 ogg 預解碼。這些跑在背景、使用者沒有在等，跳出條子只會吵。

## 剩下的限制

**在遊戲執行緒上跑完的工作畫不出動態條子**：UI 這段時間根本不重繪。目前知道還在遊戲執行緒上、可能超過 0.5 秒的是 `FinishLoad3D` 的顯示建立（實測約 0.3 s，開卡那一段才是大頭）與卡片牆掃描 `ScanAndShow`（卡片很多時）。要讓它們也有會動的條子，得先把工作搬開，不是加一行 `Begin`。

**載入3D 沒有真百分比**：ok-extract 的 `progress.rs` 目前只有封卡那條路在填（`wear_into`）。開卡那條路要填就得在 `extract.rs` 的階段上加 `progress::step`，而讀卡器會同時有背景預熱在開別的卡，共用那一個全行程插槽會互相蓋掉——要做得先讓插槽分執行緒。先給步驟名與 marquee。

## 驗證

`ok.ReaderScreen tab`（或 MCP 的 `ui_exec`）現在多印一欄 `busy=`，列出**所有**正在跑的動作（條子只顯示最新的那一個，而且要過半秒）：

沒有動作在跑時是 `busy=-`。2026-11-24 在 F 的讀卡器裡點一次服裝卡縮圖，每秒查一次拿到的：

```
busy=套用服裝卡 2.3s 0.16 封裝：把卡片缺的共用資源複製進去
busy=套用服裝卡 4.7s 0.62 封裝：把卡片缺的共用資源複製進去
busy=套用服裝卡 6.9s 0.62 嚴格檢查：確認這張卡自己開得起來
busy=套用服裝卡 9.3s 0.97 寫入卡片
busy=載入3D 1.5s - 讀卡片、組出她的模型      ← 交棒，條子沒有斷
busy=-
```

`載入3D` 那一筆的比例是 `-`（報不出），所以它走 marquee；交棒是靠「套用服裝卡」那一筆在 `OnLoad3D()` **之後**才收掉（`ON_SCOPE_EXIT`），不然中間會閃一下沒有條子。
