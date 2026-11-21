# 服裝卡：匯出一套服裝、穿到別的角色（2026-11-21）

讀卡器讀進一張角色卡後，可以把目前顯示的這套服裝匯出成服裝卡 `.okclothes`，之後讀別的角色，再把任一張服裝卡套到她身上。

## 使用

讀卡器 › 衣服卡 › 衣服卡總欄 › 服裝卡（舊 UMG 介面在模型版面的服裝組下方），四個按鈕：

| 按鈕 | 作用 |
|---|---|
| 匯出服裝卡 | 目前顯示的這套服裝 → `<另存資料夾>/<卡名>_outfit<N>.okclothes`（另存資料夾沒填就是 `UserData/okclothes/`）。縮圖是角色現在穿著這套服裝的正面 T-pose（讀卡用的四視圖擷取）；角色沒顯示時用卡片原圖。 |
| 套用服裝卡 | 選一張 `.okclothes`，穿成目前角色的這套服裝（衣服＋飾品，和遊戲的服裝卡一樣）。結果是工作卡 `Saved/OKClothes/Worn/<角色>+<服裝卡>.png`，套完立刻開啟；原卡不變，要保留請另存。 |
| 只換衣服 | 同上，但保留角色自己的飾品（髮飾、耳飾等），只換衣服。 |
| 轉換服裝卡 | 遊戲的服裝卡（KoiKatuClothes PNG）→ `.okclothes`。 |

MCP（`reader_call`）：`{"action":"action","command":"clothes_export","out":"<可省略>"}`、`{"action":"action","command":"clothes_wear","path":"<.okclothes>","clothes_only":false}`，結果寫在 log（`MCP clothes_export ok: ...`／`MCP clothes_wear ok: ...`）。

命令列：`ok-extract.exe <遊戲> --oklib clothes-wear <角色卡> <服裝卡> <服裝組> <輸出卡> [--clothes-only]`，與讀卡器走同一段程式（`okclothes::file::wear_into`）；`OK_BASE_LIBRARY` 指定基礎庫。

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

## 未做

- 服裝卡瀏覽清單（縮圖牆、點一下套用）；目前用檔案對話框選。
- 資源包裁切（只帶這套服裝用到的模型）與套用速度（OK 卡要重新封裝，數十秒）。
