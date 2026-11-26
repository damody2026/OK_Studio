# HairDeck：參考圖生成頭髮

日期：2026-11-15。參考 [HairDeck](https://github.com/hyz317/HairDeck)（程式與權重 Apache-2.0）：從一張角色圖生成頭髮片（hair cards）、每片頭髮的顏色與彈簧骨鏈。這裡把推論改寫成 Rust（`Tools/ok-hairdeck`，candle＋CUDA），不需要 Python；生成的頭髮換到角色身上（`ok-extract` 的 `portable_hairdeck.rs`），在 OK Studio 與讀卡器都能用。

## 需要的檔案

權重放在 HairDeck 的工作資料夾，預設 `F:\HairDeckData`（`--weights` 或環境變數 `HAIRDECK_ROOT` 可改）：

| 檔案 | 來源 |
|---|---|
| `ckpt/image_model`、`ckpt/color_model`、`ckpt/chain_model`、`ckpt/card_vae` | HairDeck 的 `scripts/setup/download_weights.py`（`--only hairdeck`） |
| `data/token_stats_head.json`、`data/spring/chain_stats_head.json` | 同上 |
| `third_party/weights/dinov3/model.safetensors` | DINOv3 ViT-L/16（DINOv3 License，需在 Hugging Face 同意授權；`--gated-source modelscope` 可從 ModelScope 下載，SHA-256 `dcb2e451…8179`） |

SAM 3 與 BiRefNet 不需要：Rust 版的前處理改用圖片自己的 alpha（或從純色背景算出遮罩）與自動／手動的裁切框。純色背景：四角裡顏色相同的最多的那個（同數時取上面的角；頭肩照的下面兩角是角色），從圖的邊緣往內填滿同色的像素當背景，角色身上的灰髮、銀髮不會被當成背景。

權重與 DINOv3 都不進版控。

## 建置與指令

```
Tools\ok-hairdeck\cargo-cuda.cmd build --release
Tools\ok-hairdeck\target\release\ok-hairdeck.exe generate --image <參考圖> --out <資料夾> [--box x0,y0,x1,y1] [--seed 0] [--n 1]
```

輸出 `model_input.png`（模型看到的 448×448 裁切）、`cards_seed<s>.json`、`chains_seed<s>.json`、`info.json`，格式與 HairDeck 相同。RTX 5090 上載入約 12 秒、每個變化約 2 秒。

兩人之間的頭髮（配種，2026-11-22）：`--mix <第二張圖> [--mix-box x0,y0,x1,y1] [--mix-weight 0.5]`。兩張圖各自裁切、過 DINOv3，頭髮模型與顏色模型編碼後的條件逐 token 混合（第一張 1 − w、第二張 w），再取樣一次；兩張都要以頭為中心的正方形，同一個 token 才對到頭的同一處。第二張的裁切存成 `model_input_mix.png`，`info.json` 記 `mix`、`mix_box`、`mix_weight`。讀卡器配種用父母的正臉照呼叫它，見 [OK_BREEDING.md](OK_BREEDING.md)「頭髮：父母混合生成」。

不給 `--box` 時從角色遮罩估頭部：取角色上方、寬度與角色上半一致的正方形（全身圖取身高的三分之一）。原作是 SAM 3 找頭髮＋臉的範圍再外擴 8%；長髮或構圖特殊時請手動給框。

**參考圖要把整個髮型拍進去**（2026-11-26）：配種拍的參考圖原本是「臉部網格寬 × 1.5」、以臉為中心的正方形，大約 21 公分——垂到肩膀、胸口的頭髮全在畫面外，模型只看到一張臉，生出來的就是一頂貼頭的短髮帽（使用者：「這頭髮也少太多了」）。`OKCardPreviewCapture.cpp` 的 `BeginHairReference` 改成取**臉＋她所有頭髮**的合併包圍盒、外擴 4%，相機對準它的中心，正交寬度取盒的長邊（配種傳的 `--box 0,143,768,911` 是 768×1024 圖的中央正方形，所以模型看到的就是「正交寬度見方」那一塊，寬高都要塞得進去）。哪些部件算頭髮和 `portable::hairdeck::visible_hair_parts` 同一條線，非頭髮的飾品照樣排除。log：`OK HairDeck reference crop: <寬> x <高> cm ...`。

一份 deck 實際有多少頭髮，不必開卡就能看：`Tools\lua\lua.exe Tools\hairdeck_stats.lua <cards_seed0.json>...` 印髮絲數、控制點數、包圍盒、`drop`（髮尾垂多低，頭骨半徑約 0.064）與前後髮絲數。

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
- 天使環（2026-11-22，使用者：「髮型對了但髮色沒有動漫髮的光澤」、「這光澤是錯誤的光澤，你應該參考更多原作的頭髮」）：照原作頭髮做。量過 C001、C002、C020 與惠惠的遊戲頭髮（`OK_HAIR_INSPECT=<檔.json> ok-hair-pack deck …` 會把角色原髮的頭部座標頂點、UV0、UV1 和光澤貼圖寫出來）：
  - 原生頭髮 shader 在 UV1 與 UV1 往 v 偏 0.008 處各取一次 `_HairGloss`，亮度是兩次的差（亮帶的上下緣），u 隨光線方向微移、v 隨 `_SpeclarHeight` 移。
  - 原作的光澤貼圖都是黑底、v = 0.5 一條橫向的直條紋帶（C001 是沙漏形的灰色條紋群，C002 是細白線）。
  - 遊戲頭髮的 UV1：v 隨頭部座標高度上升（瀏海每單位 3.3～4.5）；亮帶 v = 0.5 落在一個前低後高、兩側低的斜環上，y ≈ a − 0.25～0.4·z − 0.3～0.7·|x|（+Y 往上、+Z 往臉），a 0.19～0.22，約在髮頂下 0.03；u 繞頭每弧度 0.35～0.6。
  - HairDeck 照這個鋪 UV1（`portable_hairdeck::ring_uv`：斜環 a = 頭頂附近髮頂 − 0.03、z 係數 0.33、|x| 係數 0.45，v 每單位 3.6，u 每弧度 0.45 且前後對折、背後沒有接縫，v 夾在 0.01～0.99 免得長髮又繞回亮帶）。遮罩用原髮的：donor 頭髮的 `_HairGloss`，沒有就找她其他原生頭髮部件的；都沒有（mod 頭髮）才用 `gloss_mask` 畫的仿原作條紋帶（照 C001 的沙漏條紋）。
  - tangent 也照 UV1：u 繞頭、bitangent 朝 v 增加（往上）。shader 依「視線 · bitangent」把亮帶沿 v 移 `(_SpeclarHeight − 1)` 倍，每片頭髮自己的 tangent 會讓亮帶各移各的、碎成一塊塊；donor 的 `_SpeclarHeight` 不在 0.8～1（刻晴的 mod 頭髮是 0）時用 0.96（原作 0.95～0.98）。報告 `hair_material.floats` 是 donor 材質的數值。
  - 光澤順著髮束（2026-11-22，使用者：「頭髮光澤要順著頭髮的方向」）：v 不再是頭部高度，改成沿每片頭髮中心線的弧長，從它穿過斜環的地方算起（那裡 v = 0.5，往髮根增加；整片都在環下或環上時用髮根／髮尾到環的高度差延伸）；u 是那片頭髮在穿環處繞頭的位置，加上頂點在片寬上的位置（角 0、2 是兩側）。條紋（u 固定）就沿髮束走，不會在往旁邊梳的頭髮上直直切過去。tangent 框架照舊（繞頭／往上）。
  - 之前錯的做法：把亮帶烘進顏色圖集、用 UV0 取樣（變成每片頭髮各自發亮的白點和等高線）；自己畫的高斯亮帶（成塊）。
- `ok-hair-pack deck` 報告的 `gloss_png` 是用上的遮罩大小、`uv1_range` 是 UV1 的範圍，遮罩另存在 `<輸出>.gloss.png`。
- 原髮不是原生頭髮 shader 的角色（例如貞德的頭髮是 main_item）沒有天使環：HairDeck 頭髮沿用 main_item。
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
- 配種：讀卡器配種時孩子的頭髮用父母正臉照混合生成（`--mix`），存進孩子卡，選項 `mix` 記父母與父親比例；生成不了時照舊，孩子的髮型來自哪一位，就帶那一位的 `okHk`（沒有就不帶），`okDn` 記 `hairdeck`（來自 mother／father）。見 [OK_BREEDING.md](OK_BREEDING.md)。
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

### 取景的對照（2026-11-26，lan × luo_tianyi_2024，種子 7001，只換參考圖取景）

| 取景（`ok.HairRefFraming`） | 模型看到的正方形 | 髮絲 | `drop` | 實拍 |
|---|---:|---:|---:|---|
| 0 舊：臉寬 ×1.5 | 36 cm | 91 | 0.179 | 貼頭的短鮑伯 |
| **1 臉＋頭髮盒 ×1.04（預設）** | 92.5 cm | 111 | 0.726 | 兩條垂到膝蓋的辮子＋後方長髮，父母的髮型都在 |
| 2 上半身：至少臉寬 ×5 | 160 cm | 100 | 1.126 | **壞掉**：頭髮飛離頭部、掉在地上 |

取景太大一樣會壞：160 cm 見方時她的臉只佔畫面八分之一，模型把袖子和腿也讀成頭髮（`drop` 1.13、往後伸到 z −0.79）。HairDeck 自己的前處理就是「頭髮＋臉的範圍外擴 8%」，模式 1 照它做。`ok.HairRefYaw` 可以把參考相機繞到她背後（0 正面、180 背面）；HairDeck 是用正面立繪訓練的，所以預設 0。截圖與各自的 `model_input.png` 在 `Saved/HairRefExperiment/`。

視角（`ok.HairRefYaw`，同一組取景 mode 1、同一個種子）：正面 111 髮絲／`drop` 0.726／前髮 20，背面（180）99／0.683／13，3/4 後視（135）63／0.744／**前髮 0**。背面沒有比較好，3/4 後視最差（一根瀏海都沒生出來）——關鍵是取景不是視角，HairDeck 本來就是用正面立繪訓練的。
