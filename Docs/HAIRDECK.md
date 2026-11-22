# HairDeck：參考圖生成頭髮

日期：2026-11-15。參考 [HairDeck](https://github.com/hyz317/HairDeck)（程式與權重 Apache-2.0）：從一張角色圖生成頭髮片（hair cards）、每片頭髮的顏色與彈簧骨鏈。這裡把推論改寫成 Rust（`Tools/ok-hairdeck`，candle＋CUDA），不需要 Python；生成的頭髮換到角色身上（`ok-extract` 的 `portable_hairdeck.rs`），在 OK Studio 與讀卡器都能用。

## 需要的檔案

權重放在 HairDeck 的工作資料夾，預設 `F:\HairDeckData`（`--weights` 或環境變數 `HAIRDECK_ROOT` 可改）：

| 檔案 | 來源 |
|---|---|
| `ckpt/image_model`、`ckpt/color_model`、`ckpt/chain_model`、`ckpt/card_vae` | HairDeck 的 `scripts/setup/download_weights.py`（`--only hairdeck`） |
| `data/token_stats_head.json`、`data/spring/chain_stats_head.json` | 同上 |
| `third_party/weights/dinov3/model.safetensors` | DINOv3 ViT-L/16（DINOv3 License，需在 Hugging Face 同意授權；`--gated-source modelscope` 可從 ModelScope 下載，SHA-256 `dcb2e451…8179`） |

SAM 3 與 BiRefNet 不需要：Rust 版的前處理改用圖片自己的 alpha（或從純色背景算出遮罩）與自動／手動的裁切框。

權重與 DINOv3 都不進版控。

## 建置與指令

```
Tools\ok-hairdeck\cargo-cuda.cmd build --release
Tools\ok-hairdeck\target\release\ok-hairdeck.exe generate --image <參考圖> --out <資料夾> [--box x0,y0,x1,y1] [--seed 0] [--n 1]
```

輸出 `model_input.png`（模型看到的 448×448 裁切）、`cards_seed<s>.json`、`chains_seed<s>.json`、`info.json`，格式與 HairDeck 相同。RTX 5090 上載入約 12 秒、每個變化約 2 秒。

不給 `--box` 時從角色遮罩估頭部：取角色上方、寬度與角色上半一致的正方形（全身圖取身高的三分之一）。原作是 SAM 3 找頭髮＋臉的範圍再外擴 8%；長髮或構圖特殊時請手動給框。

## 換到角色上

`ok-extract` 的 `portable::hairdeck`：

- 頭髮片照 HairDeck 的 `cards_vf` 建網格（Bishop frame，每個控制點 4 個頂點）。
- HairDeck 的頭部座標（y 上、臉朝 +z、右手系）以 x 鏡射轉成 Unity，三角形繞序對調。
- 對位：HairDeck 的頭骨橢球（半徑 0.405W、0.5W、0.5W）對到角色臉部網格：縮放用頭頂 45% 的頭寬（排除耳朵），前後用額頭，高度用頭頂。遊戲的 `cf_O_face` 沒有後腦，不能用網格深度。遊戲的頭頂比 HairDeck 的頭骨方，照原尺寸額頭上緣會從瀏海間露出來，所以再放大 4%、上移 0.13 個半徑、前移 0.07 個半徑（C041 實測）。
- 顏色：每片頭髮 16 段顏色畫進一張圖集（每片 4×32 像素）。
- 骨鏈：最多 32 條、每條 3–12 個點，成為私有柔性髮骨（`portable_hair_soft`），每片頭髮跟最近的骨鏈，髮根跟頭。
- 取代角色原本的頭髮（其他飾品槽的角、帽子、衣服保留）：
  - 頭髮部件，以及部件名稱、renderer 名稱或 shader 名稱含 hair、名稱含 `_kami`（日文「髪」）的配件。
  - 同配件中名稱含 shadow／kage 的頭髮陰影。
  - 同一個頭髮網格在同配件再畫一次的疊層：半透明材質（`main_item_studio_alpha`、`main_alpha`）、MaterialEditor 的 copy，或同一張貼圖。
  - 原本用飾品做的頭髮整個藏掉（使用者 2026-11-22：換 HairDeck 後不需要原來的頭髮飾品，會重疊）：卡片上類別 121（髮）的飾品、掛在頭髮掛點（`a_n_hair_*`）上的飾品，以及 HairAccessoryCustomizer 有資料、掛在頭上（`a_n_head*`、`a_n_hair*`）的飾品槽，不管顏色與名稱。這些槽裡的髮夾、緞帶、貓耳也一起藏：它們是照舊髮型擺的，在新頭髮上會浮起或陷進去。之前只藏顏色等於髮色的 renderer，刻晴的雙馬尾、貓耳這類照樣留著。這條要知道卡片路徑，session 開卡時記下（`OkSession::card_path`）。
- 材質：角色原髮是原生頭髮 shader 時沿用它的 ramp 與高光。否則用 main_item，顏色圖集標成 sRGB、不畫外框；直接讀會讓深藍變淡紫，外框會描出每一片頭髮。新部件不留原 renderer 名稱，卡片的 MaterialEditor 設定不會套到它身上。
- 再次套用同一份頭髮不做事（材質名稱記著頭髮檔與選項的雜湊）；換另一份頭髮時取代上一份。

離線檢查：`ok-hair-pack deck <基礎庫> <角色卡> <cards_seed0.json> <輸出.obj>` 輸出頭部與頭髮的 OBJ（頭部座標）。

## OK Studio 與讀卡器

- OK Studio：選角色 → 物件屬性「髮型生成（HairDeck）」：填參考圖路徑，按「生成」，完成後自動換上；「頭髮檔」可直接填既有的 `cards_seed<s>.json`；「原本頭髮」換回角色卡的頭髮。場景會記住 `HairDeck`／`HairDeckOpts`／`HairDeckImage`，重開場景時重新套用。指令：`chara.hairdeck <參考圖>`、`chara.hairdeck.apply <cards json>`（MCP `studio_cmd` 可用）。生成結果在 `Saved/OKStudio/HairDeck/<時間>/`。
- 讀卡器：編輯 › 頭髮 › **HairDeck 生成**（`Config/ReaderEditor/pages.json` 的 builder `hairdeck`）：參考圖路徑欄、「選參考圖…」、「生成並換上」（`ok-hairdeck.exe`，結果在 `Saved/HairDeck/<時間>/`）、「換上頭髮檔…」（選 `cards_seed<s>.json`）、「存進卡片」、「從卡片拿掉」（拿掉後重新載入原本的頭髮），下方顯示上一步的結果。MCP `hairdeck` 給 `image` 走同一個生成。主控台 `ok.ReaderHairDeck <cards_seed0.json> [選項 JSON]`。角色身上記著這份頭髮（`AKKPreviewActor::HairDeckCards`），之後這個角色載入的每個 session（換衣服狀態、重開）都會再套上。
- 換頭髮後要清掉 session 的 `RuntimeMaterials` 與角色的共用材質實例（`CookedRoleMaterials`）：讀卡器用預先烘好的共用材質，不清的話新頭髮會拿舊頭髮的材質與貼圖。

選項 JSON（`HairDeckOpts`）：`scale`（再乘的縮放）、`offset`（頭部座標的位移，公尺）、`native`（沿用原髮 shader，預設 true）、`rigid`（不用骨鏈）、`hair_color`。

## 存進卡片（2026-11-22）

卡片多一個 `okHk` chunk：zstd 壓的 JSON，內含 HairDeck 的頭髮片（`cards`）、骨鏈（`chains`）、選項、存進去時卡片的髮色（`hair_color`）與來源檔名；77 片頭髮約 190 KB。

- 顯示時套上：角色身上沒有另外指定 HairDeck 頭髮時，`AKKPreviewActor::ApplyHairDeckToSession`（`LoadSession`／`BeginSessionLoad` 前，讀卡器原本換髮的同一處）改套卡片的 `okHk`（`ok_session_apply_card_hairdeck` → `portable::hairdeck::apply_card`）。不放在 `session::open`：封裝與 digest 的嚴格開卡每套服裝都會再做一次頭髮。換不上時保留原本頭髮，log 寫 `OK card HairDeck hair not applied`。命令列開卡（digest、封裝）不套。
- 換上時頭髮頂點直接放到目前頭骨的位置（世界座標）：頭髮是執行期飾品，顯示端照頂點現有位置畫，第一次求解前若還是頭部局部座標，剛開卡、角色沒動時頭髮會堆在腳邊。
- 髮色跟著卡片：卡片目前的髮色和存進去時不同（配種混出來的髮色、街區髮廊染髮），每片頭髮的顏色平移同樣的差。
- 重新轉 OK 卡（`remake_ok_card`，`keep_identity`）與讀卡器另存（`appearance.rs`）都保留 `okHk`。卡片沒有 `okId` 時，存頭髮不會改變它的身分（`tree_answers::with_chunk`）。
- 讀卡器：先 `ok.ReaderHairDeck <cards_seed0.json>` 換上，再 `ok.ReaderHairDeckSave` 存進目前這張卡（給路徑則另存一張；`-` 把頭髮從卡片拿掉）。MCP：`{"action":"action","command":"hairdeck","cards":"<cards_seed0.json>","opts":"<可省略>"}`、`{"action":"action","command":"hairdeck_save","out":"<可省略>","remove":false}`。存進目前這張卡後，角色身上記的頭髮清掉，之後照卡片的。
- 命令列：`ok-hair-pack card <卡> <cards_seed0.json 或 -> <輸出卡> [選項 JSON]`。
- 配種：孩子的髮型來自哪一位，就帶那一位的 `okHk`（沒有就不帶），`okDn` 記 `hairdeck`（來自 mother／father）。見 [OK_BREEDING.md](OK_BREEDING.md)。
- OK Studio 場景另外記的 HairDeck 頭髮優先於卡片的；「原本頭髮」回到卡片帶的頭髮。

## 驗證

`F:\OpenKoikatsu\output\characters-2026-09-30-anime\references\02-nightclub-face-reference.png`，同一裁切框與同一組初始雜訊，對照 HairDeck 原版（PyTorch bf16）：

| 項目 | Python | Rust |
|---|---|---|
| 頭髮片 | 52 | 53 |
| 髮根位置差（中位數） | — | 0.7 mm（頭寬約 128 mm） |
| 髮尾位置差（中位數） | — | 2.7 mm |
| 顏色差（平均，0–1） | — | 0.0013 |
| 骨鏈 | 10 | 10（關節數 9 條相同） |

差異來自 bf16 與 f32 的數值誤差。

遊戲內（2026-11-15，C041 Yvonne）：
- 讀卡器：02-nightclub 參考圖的深藍高馬尾換上，正面、側面、背面確認位置；角保留，原本的雙馬尾隱藏。
- OK Studio：`chara.hairdeck` 用 01-campus 參考圖，從生成到換上約 27 秒，金色長直髮。

CrowdAPNG 101 張批次（2026-11-15，讀卡器，nightclub 頭髮）：100 張頭髮位置、顏色、原髮隱藏都正確。C086 頭上的兜帽本來就保留，屬預期行為。C031 的白髮（`Body.049`，main_item）留著：卡片髮色是純白，跟沒染色的飾品分不出來。

## 限制

- 雜訊用自己的亂數，同一個 seed 不會和 Python 版相同（要重現時用 `--noise`）。
- 沒有 SAM 3：參考圖背景要單純，或自己去背成透明 PNG，或手動給框。
- 頭髮材質目前是顏色圖集；沒有法線圖與 HairDeck 的 VRM 材質。
- 讀卡器換的頭髮要按「存進卡片」（或 `ok.ReaderHairDeckSave`）才存進卡片，存的是目前這張卡本身。OK Studio 存在場景裡。
