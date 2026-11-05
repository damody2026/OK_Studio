# 汽車旅館客房量產規格（2026-10-25）

209 尊爵、303 慾望城市、203 泳池房1、512 香奈兒四間樣板房已經使用者確認。其餘 57 間依這份規格量產：每間房寫一段 JSON 規格，由資料驅動的建模器組出 Blender 模型，再用和樣板房相同的流程匯入 UE。

| 項目 | 位置 |
|---|---|
| 官網照片（61 間、365 張） | `output/street-social-city-production/motel-v1/reference-photos/rooms/<id>-N.jpg`；每間一張總覽 `<id>-sheet.jpg`；清單 `manifest.json` |
| 抓照片 | `Tools/fetch_street_city_motel_room_photos.lua` |
| 房間規格 | `output/.../motel-v1/room-specs/batch-NN.json`（`{"rooms":[...]}`，一個檔可放多間） |
| 產生程序貼圖 | `Tools/build_street_city_motel_room_textures.lua`（掃描全部規格裡的 `gen`） |
| 建模器 | `Tools/build_street_city_motel_rooms_v2.lua [room-id ...]`（不給 id 就全部建） |
| 產物 | `output/.../motel-v1/sample-rooms/models-v2/<id>/{suite.glb,water.glb,suite.blend,build.json}`、總表 `sample-rooms/rooms-v2-build.json`、日誌 `sample-rooms/build-v2.log` |
| Blender 預覽 | `Tools/preview_street_city_motel_sample_rooms.lua <id>`（有 models-v2 就用 v2）→ `sample-rooms/previews/<id>-<view>.png` |
| UE 匯入／安裝／拍照 | 與樣板房相同：`street_city_motel_sample_payload.lua` 的 `sample_import`、`sample_install`，再 `capture_street_city_motel.lua preview samples` |

建模器沿用樣板房建模器（`build_street_city_motel_sample_rooms.lua`）的外殼、材質、浴缸、UV 與路線檢查。所以門洞、車庫、浴室隔間、鏡面凹槽、迷你吧與已驗證的走路路線在每一間都不變，規格只描述裝潢。

## 1. 外殼契約（不可由規格改動）

以房間本地座標（公尺）描述，原點是房間中心，+y 往房間後方（浴室），z 從地板起算。

| 項目 | 一般房 | 泳池房 |
|---|---|---|
| 尺寸 w×d×h | 15.2 × 20.8 × 約 3.9 | 30.4 × 20.8 × 約 3.9 |
| 入口門 | x = w·0.29，前牆 y = −d/2 | 同左 |
| 車庫 | x = −w·0.25 前段（有車庫的房） | 同左 |
| 浴室 | 前牆 y = 6.8，中心 x = w·0.28；化妝鏡 y = 10.12 | 同左，另有泳池大廳在 x < −1 |
| 迷你吧 | (doorx − 2, −8.8, 0.9) | 同左 |
| 走路走廊（必須淨空） | (doorx, −11.2) → (doorx, −5) → (w/2 − 1.25, −5) → (w/2 − 1.25, 2.1) → (−0.54, 2.1) | 加一條到 WC 的路線 |
| 床預設位置 | (−3.34, 4.7)，床頭朝 +y | 同左 |
| 牆內面 | 左 −w/2 + 0.2，右 w/2 − 0.2，前 −d/2 + 0.2，床後隔間 y = 6.66 | |

本地座標換算世界座標：`wx = base + (v0·sin(yaw) + v1·cos(yaw))·100`，`wy = base + (v0·cos(yaw) − v1·sin(yaw))·100`。

傢俱、牆飾不可擋住走廊；建模器在每間建完時跑路線檢查，`build-v2.log` 印出 `ROOM <id> <三角形數> blockers [...]`，最後一行 `FAILED_ROUTE [...]` 必須是空的。

## 2. 規格 JSON

每間房一個物件，未寫的欄位用預設值。

```jsonc
{
 "id": "imore-4aa1b54def22",            // reference-catalog / motel-plan 的房間 id
 "name": "H1 210 杜拜",
 "photo_notes": "逐張照片的觀察（寫給人看）",
 "floor": <材質>, "wall": <材質>, "front": <材質>,   // front 預設同 wall
 "trim": <材質>, "cabinet": <材質>,
 "ceiling": {"type": "tray|mirror|dome|stars|flat|beams", "cove": [r,g,b], "cove_emit": 6,
             "band": 1.0, "drop": 0.35, "field": <材質>, "soffit": <材質>, "trim": "gold|<材質>",
             "domes": [[x,y]...], "dome_field": <材質>, "star": [r,g,b]},
 "walls": [{"side": "left|right|front|rear", "mat": <材質>, "x0": a0, "x1": a1, "z0": 0, "z1": h}],
 "bed": {...},          // 見 3.2
 "living": {"rug": {...}, "seats": [...], "table": {...}, "tables": [...]},
 "chandeliers": [{"kind": "...", "at": [x,y], "glow": [r,g,b], "emit": 4, "mat": "gold", "n": 8, "key": "<Tripo>"}],
 "extras": [{"type": "...", ...}],
 "bath": {...},         // 見 3.6
 "pool": {...},         // 只有泳池房
 "light": {"warm": [r,g,b], "living": 3000, "bed": 2800, "lounge": 1800, "lamp": [r,g,b],
           "bath_color": [r,g,b], "accents": [{"at": [x,y,z], "color": [r,g,b], "lm": 900, "r": 500}]},
 "views": [{"id": "v-...", "eye": [x,y,z], "target": [x,y,z], "fov": 84}],   // 追加視角
 "tripo_wishlist": ["之後若要生成 Tripo 傢俱，這間最需要的品項"]
}
```

`walls[]` 的 `x0`／`x1` 是沿著該面牆的座標範圍（左右牆是 y，前後牆是 x）。後牆會自動在浴室門洞處切開。

### 材質描述 `<材質>`

- 字串：預設貼圖名稱，見第 4 節，例如 `"marble_black"`。
- 物件：`{"color": [r,g,b], "tex": "<預設貼圖>", "gen": {...}, "tile": 1.2, "fit": false, "rough": 0.5, "metal": 0, "emit": 0, "alpha": 1}`。
  - `gen` 是程序貼圖描述，會產生 `textures/gen_<md5 前 10 碼>.png`，見第 5 節。
  - `fit: true` 表示整張貼圖貼滿一個面，不重複。
  - 有貼圖又有 `emit` 時，貼圖本身會發光（銀河牆、螢幕）。
- 顏色一律 0–1 浮點數。

## 3. 元件庫

### 3.1 座椅 `living.seats[]`

`{"kind": ..., "at": [x,y], "rot": 度, "len": 2.4, "mat": <材質>, "frame": "gold|<材質>", "legs": <材質>, "key": "<Tripo>"}`。正面朝 −y，`rot` 繞自己中心旋轉。

| kind | 說明 |
|---|---|
| `baroque` | 金框巴洛克沙發，軟包靠背、拱形雕花頂、捲邊扶手、彎腳 |
| `chesterfield` | 捲扶手、扣子軟包的切斯特菲爾德沙發 |
| `modern` | 方正現代沙發 |
| `curved` | 弧形卡座 |
| `tub` | 桶形單椅 |
| `shell` | 貝殼扇形單椅 |
| `wing` | 高背翼椅 |
| `ottoman` | 圓形軟凳 |
| 其他 | 單人巴洛克扶手椅 |

### 3.2 床 `bed`

`at`；`shape: rect|round`；`base`、`linen`、`pillows`、`throw`（床尾巾）都是材質；`underlight: [r,g,b]` 是床底燈。

- `headboard`：`{"type": "panel|tufted|round_pleat|wing|crown|slats", "mat", "w", "h", "button", "trim"}`。
- `canopy`：`{"posts": <材質>, "drape": <材質>}`，加四柱床幔。
- `lamps`：`pleated|drum|none`，搭配 `shade`（燈罩，通常帶 emit）、`stand`（床頭櫃）。
- `key`：改用已有的 Tripo 床，例如 `canopy_bed`。

### 3.3 桌與地毯

- `table`／`tables[]`：`{"kind": "oval_marble|round_drum|glass_rect|round_glass|wood_rect|booth", "at", "size": [sx,sy], "mat", "base", "glow"}`。
- 第一張桌面是裝飾道具 decorA 的擺放處。
- `rug`：`{"at", "size": [w,d], "mat"}`。

### 3.4 吊燈 `chandeliers[]`

| kind | 說明 |
|---|---|
| `tiers` | 三層水晶 |
| `drum` | 鼓形燈 |
| `disco` | 鏡面球 |
| `ring` | LED 雙環 |
| `arms` | 多臂燈罩，`n` 支 |
| `key` | 已有的 Tripo 吊燈：`crystal_chandelier`、`iron_red_chandelier`、`brass_chandelier` |

### 3.5 其他裝飾 `extras[]`

| type | 主要欄位 | 說明 |
|---|---|---|
| `columns` | `at: [[x,y]...]`, `mat` | 羅馬柱 |
| `drape` | `x0`, `x1`, `y`, `z1`, `axis`, `folds`, `mat` | 布簾 |
| `led_strips` | `side`, `range`, `n`, `color` | 直立 LED 燈條 |
| `led_line` | `a`, `b`, `color` | 任意兩點之間的 LED 線 |
| `stars` | `side`, `range`, `n`, `color` | 牆面星點 |
| `mirror_wall` | `side`, `x0`, `x1`, `z0`, `z1` | 鏡牆 |
| `panel` | `side`, `mat`, `x0`, `x1`, `z0`, `z1` | 貼一塊牆板，同 `walls[]` |
| `wainscot` | `sides`, `mat`, `h`, `rail` | 護牆板加腰線 |
| `brick_arch` | `at`, `r`, `mat` | 磚拱 |
| `screen` | `side`, `at`, `size`, `z`, `mat` | 發光畫面或燈箱 |
| `tv` | `at`, `rot`, `wall`, `ww`, `cw`, `cab`, `screen` | 電視、電視櫃與背牆 |
| `massage_chair` | `at`, `rot` | Tripo 按摩椅 |
| `heart_seat` | `at`, `mat` | 愛心沙發 |
| `birdcage` | `at`, `mat`, `cushion` | 鳥籠座 |
| `swing` | `at`, `mat` | 吊椅 |
| `pole` | `at`, `mat`, `glow` | 舞台鋼管 |
| `bar` | `at`, `len`, `mat`, `top`, `stool` | 吧台與高腳椅 |
| `fiber_curtain` | `at`, `w`, `color` | 光纖簾 |
| `water_column` | `at`, `r`, `color` | 水柱燈 |
| `frames` | `side`, `n`, `range`, `z`, `size`, `art`, `frame` | 掛畫 |
| `plant` | `at`, `pot` | 盆栽 |
| `bookshelf` | `side`, `range`, `mat`, `glow` | 發光書櫃 |
| `desk` | `at`, `mat`, `stool` | 化妝台 |
| `platform` | `at`, `r`, `mat`, `glow` | 圓形地台 |
| `neon` | `side`, `at`, `z`, `size`, `shape: heart|circle`, `color` | 霓虹 |
| `ceiling_fan` | `at`, `mat` | 吊扇 |
| `floor_patch` | `at`, `size`, `mat` | 局部地板（不同磁磚區） |
| `furniture` | `key`, `at`, `rot`, `z` | 任何已有的 Tripo 傢俱 |
| `box` | `at`, `size`, `mat`, `bevel`, `name` | 自由方塊 |

### 3.6 浴室 `bath`

- 材質：`wall`、`front`、`floor`、`counter`、`vanity`、`surround`（浴缸外框）、`mirrorframe`。
- `tub`：`rect`（方形按摩浴缸）、`round`（圓形）或 `clawfoot`（貓腳）。
- 開關與樣式：
  - `vines`：鏡牆藤蔓；
  - `tv`：浴室電視；
  - `sconces`：預設開啟，搭配 `sconce` 指定顏色；
  - `band`：腰帶飾條材質；
  - `rectbasin`、`glassfront`。

### 3.7 泳池房 `pool`

材質欄位：`ceiling`、`pool_wall`、`pool_floor`、`coping`、`stripe`、`lower`、`mural`；另有 `extras`（同 3.5）。泳池、天窗、玻璃隔間、淋浴間的位置固定。

### 3.8 燈光與視角

每間自動放這些燈：客廳、床、休息區、浴室、入口，以及兩盞床頭燈。`light.accents` 可追加色光。

自動視角：

- 一般房：`v-living-to-bed`、`v-bed-front`、`v-entry-overview`、`v-bath`、`v-left-lounge`；
- 泳池房：前四個加 `v-pool-hall`、`v-pool-wall`。

`views` 可追加對準官網照片構圖的視角。

## 4. 預設貼圖

| 類別 | 名稱 |
|---|---|
| 木頭 | `wood_dark`、`wood_walnut` |
| 石材 | `marble_black`、`marble_cream`、`marble_redbrown`、`granite_brown`、`terrazzo_star_bw` |
| 磁磚 | `tile_white_large`、`mosaic_red_white`、`mosaic_pool_blue`、`mosaic_navy`、`mosaic_gold`、`mosaic_black_white_check` |
| 壁紙 | `damask_brown_gold`、`wallpaper_key_purple`、`wallpaper_cream_linen`、`panel_lily` |
| 軟包 | `velvet_tufted_red`、`pleat_radial_cream`、`rug_cream_gold` |
| 其他 | `mirror_lattice_black`、`ceiling_grid_dark`、`pool_floor_design`、`mural_desert` |

另有程式材質 `gold`、`chrome`、`black_glass`、`mirror_wall` 等由元件內部使用。

## 5. 程序貼圖 `gen`

`{"gen": {"kind": ..., ...}}`，產出 1024² 的 PNG（`mural` 是 2048×512），都是二的冪次。

| kind | 參數 |
|---|---|
| `plaster` | `c1`, `c2` |
| `damask` | `bg`, `fg` |
| `stripes` | `bg`, `c2`, `width`, `vertical` |
| `marble` | `base`, `dark`, `vein`, `scale` |
| `wood` | `c1`, `c2`, `rows` |
| `mosaic` | `colors[]`, `tiles`, `grout`, `bands` |
| `check` | `bg`, `fg`, `n` |
| `tufted` | `bg`, `fg`, `line` |
| `lattice` | `bg`, `fg` |
| `brick` | `bg`, `fg` |
| `geo` | `bg`, `fg`（回紋） |
| `floral` | `bg`, `fg`, `fg2` |
| `panels` | `bg`, `fg`, `n` |
| `galaxy` | `bg`, `fg` |
| `mural` | `top`, `bottom`, `ground` |

同一個描述會得到同一張貼圖（以描述的 md5 命名，已存在就不重做）。要改圖時改描述內容，不要覆寫舊檔。

## 6. Tripo 傢俱

這一輪不生成新 Tripo 模型。可重用的已有模型（已用 instant-meshes-rs remesh）如下：

`red_baroque_sofa`、`red_baroque_armchair`、`massage_chair`、`purple_silver_sofa`、`red_shell_armchair`、`crystal_chandelier`、`iron_red_chandelier`、`purple_chesterfield`、`tan_tub_chair`、`brass_chandelier`、`canopy_bed`

使用方式：座椅加 `"key"`；吊燈 `"kind": "key", "key": ...`；床 `bed.key`；其他用 `extras` 的 `furniture`。

每間的 `tripo_wishlist` 記下照片上最有辨識度、程序元件做不像的品項。之後若要生成，依原規則執行：每個模型不超過 30 點、用使用者的設定、一律先用 `E:\Paper\instant-meshes-rs` remesh 再進 UE。

### Grok 生圖貼圖

程序貼圖做不像的壁畫、背光牆、屏風圖案，改用 Grok 生成：

1. 用 `/grok:image` 產生正面、均勻打光、不含文字的平面圖，存在 `grok-media/`。
2. 把來源與 prompt 登記在 `sample-rooms/grok-textures.json`。
3. 執行 `Tools/import_street_city_motel_grok_textures.lua`，轉成二的冪次的 `textures/grok_<key>.png`。
4. 規格裡用 `{"tex":"grok_<key>","fit":true}` 引用。

目前已有的 Grok 貼圖：

| key | 用在哪間 | 內容 |
|---|---|---|
| `branch_lightwall` | 408 沉睡森林 | 樹枝背光牆 |
| `red_floral_screen` | 410 東方之珠 | 紅牡丹屏風床頭 |
| `bottle_wall` | 403 66號公路 | 酒瓶背光牆 |

## 7. 量產流程與驗收

1. 打開 `<id>-sheet.jpg`，逐張寫 `photo_notes`：主色、牆面、床頭板、沙發、吊燈、特殊設施、浴室與浴缸。
2. 把觀察對應到元件與材質，寫進 `room-specs/batch-NN.json`。每批 5～10 間。
3. 執行：

   ```powershell
   .\Tools\lua\lua.exe Tools/build_street_city_motel_room_textures.lua
   .\Tools\lua\lua.exe Tools/build_street_city_motel_rooms_v2.lua <id ...>
   ```

   `FAILED_ROUTE` 必須是空的。
4. Blender 預覽抽查：每批至少看 `v-living-to-bed` 與一張特色視角，對照照片確認主色和招牌設施。
5. 匯入 UE 並拍同構圖對照照片；每批給使用者看過再做下一批的 UE 匯入。
6. 全部完成後，重跑地圖的 audit、routes、physics_plan、cook 與實際走路驗收。

## 8. 樣板房學到的規則

- UE 的貼圖要二的冪次尺寸。非冪次貼圖（例如 512 房的百合板）在 UE 會被當成無 mip 的 UI 貼圖，看起來褪色。
- 不可有共面：裝飾面一律離開牆面至少 1–2 cm，框和板也不能同平面，否則 z-fighting。
- 牆面裝飾要在牆內面之前：左牆內面 x = −w/2 + 0.2，裝飾放在 −w/2 + 0.215～0.235；泳池房左牆在 x = −14.98。
- `plane()` 的朝向參數是法線方向，`'+y'` 必須真的面向 +y（樣板建模器已修正）。
- Tripo 傢俱的正面方向不一定，放進房間後要看預覽確認（按摩椅曾經面朝牆）；顏色不對用 `hue` 校正，不要重新生成。
- 有貼圖的發光材質，發光顏色取自貼圖（銀河牆）；只給顏色會變成一片白光。
- 巴洛克沙發頂部雕花管徑 0.022 m；更粗會看起來像金屬管。
- 傢俱、柱子、拱門、機台不可放在走廊上：右牆前段（x > w/2 − 2）與 y ≈ −5、y ≈ 2.1 兩條橫向走道最容易擋到。

## 9. 目前進度（2026-10-25）

- 其餘 57 間的規格已寫完：`room-specs/batch-01.json`～`batch-10.json`，每間都有 `photo_notes` 與 `tripo_wishlist`。
- 57 間用最終版建模器全部重建一次：`FAILED_ROUTE []`，路線全通。
- 已抽查約 20 間的 Blender 預覽，每批至少 3 間。
- **還沒做**：
  - 匯入 UE、拍同構圖對照照片；
  - 重跑地圖的 audit、routes、physics_plan、cook 與走路驗收；
  - 生成 tripo_wishlist 裡的 Tripo 傢俱。

## 10. 57 間量產房的 UE 安裝與驗收（2026-10-26）

- 57 間全部匯入 UE 並裝進地圖：Tools/street_city_motel_sample_payload.lua 的 ooms_install，每批 10 間，每裝完一間就釋放記憶體。地圖備份在 sample-rooms/UniversityCity-before-rooms-v2-*.umap，motel-install.json 裡各房的 asset 已同步更新（舊值留在 previous_asset）。
- 稽核抓到 511 幻鏡撲克的站立視點（房間本地座標 −0.54, 1.2）被沙發蓋住。已把沙發移開，並在 v2 路線檢查加入這個點；57 間在新規則下全數通過。
- 最終地圖 SHA 5c228f625486…：

| 項目 | 結果 |
|---|---|
| audit / routes | passed，0 個問題 |
| 完整 cook | package 20261026-083621，exit 0 |
| 打包版實拍 | 57 間 × 5 個視角，共 288 張：motel-v1/runtime-views-20261026-084621/（總覽 sheet-01～sheet-19.jpg） |
| 快速物理 | passed（physics-20261026-085933.json） |
| 全部路線實走 | passed：79/79 條（依 route id 去重），127 筆紀錄，0 次輔助跨步，一般輸入與玩家起點都通過（physics-20261026-092427.json） |

- 第一次實走在 207 泳池台階第二圈的第 24 段卡住（physics-20261026-090052.json，同一條路線第一圈有通過）。台階幾何和已通過的 203 樣板相同，原樣重跑後全數通過，沒有放寬任何條件，判定為偶發。若再發生，要檢查泳池台階的碰撞。
- 一律用打包版實拍：在 Editor 跑 -game d3d12 時，載入這張地圖就要約 70 GB。
- 驗收流程整理成 Tools/run_street_city_motel_acceptance.lua [--reuse] [--rooms id ...] [--capture v2 ...]。

## 11. 第二批元件：招牌擺設、浴缸款式、自動補家具（2026-10-26）

新元件都是程序建模，沒有生成 Tripo。

| 欄位 | 值 | 說明 |
|---|---|---|
| `bed.headboard.type` | `heart` | 愛心軟包床頭：兩個圓形加一個 45° 方塊，扣子軟包，背後是黑色背板 |
| `chandeliers[].kind` | `lantern` | 中式燈籠一排（`n` 個，預設 3），會發光，有金色蓋和流蘇 |
| `living.seats[].kind` | `heart_booth` | 愛心鏤空高背卡座（3.2 m 寬、2.7 m 高），取代那張沙發的位置與朝向 |
| `extras[].type` | `heart_booth` | 同上，但當獨立擺設，自動找位置 |
| `extras[].type` | `swing_bed` | 鞦韆床：四條吊繩接到天花板，`vines: true` 時加藤蔓葉 |
| `extras[].type` | `folding_screen` | 折疊屏風（`panels` 片，預設 4），鋸齒狀立在地上 |
| `extras[].type` | `arch_mirror` | 左牆拱頂鏡，金框；`bulbs: true` 時框上加燈泡 |
| `bath.tub` | `platform` | 石砌高台（3.3×2.9×0.5 m，用 `surround` 材質）加沉入式圓形按摩缸和前階 |
| `bath.tub` | `oval` | 橢圓獨立浴缸，加落地龍頭與地墊 |
| `bath.glow` | `[r,g,b]` | 浴缸水中燈：一盞同色點光；`platform` 另加 LED 環 |
| `furnish` | `false` 表示關閉 | 自動補家具，預設開啟，見下方說明 |

- 自動擺放：沒寫 `at` 的招牌件依候選點逐一試，找第一個符合條件的位置：
  - 不碰到已有家具；
  - 離走路走廊 0.5 m 以上；
  - 在房間範圍內（泳池房只用右半，車庫房避開車位）。
  - 找不到位置會在 `build-v2.log` 印出 `SKIP ...`，不會硬塞。
- 自動補家具（`furnish()`，每間都會跑，同樣有空位才放）：
  - 少於兩張座椅時，在茶几四周補一組沙發加兩張桶椅；
  - 床尾凳；
  - 沙發兩端各放一盞立燈（附一盞 350 lm 的點光）和一張邊几（附花瓶）；
  - 左牆邊櫃，附花瓶插花和金框掛畫；
  - 空著的角落放盆栽。
- `Tools/apply_street_city_motel_wishlist_rules.lua [--dry]`：依每間的 `tripo_wishlist` 和 `photo_notes` 關鍵字改規格。
  - 第一次執行會留下 `batch-NN.before-wishlist.json` 備份；重複執行不會重複改。
  - 規則：
    - 巴洛克／切斯特菲爾德沙發、高背翼椅；
    - 四柱床幔；
    - 愛心、軟包、扇形、雕花床頭；
    - 鞦韆床、愛心卡座、燈籠、拱門鏡、屏風；
    - 鼓形茶几；
    - 貓腳浴缸、石砌高台浴缸、浴缸水中燈（發光字眼要緊貼在「浴缸」前面才算）。
  - 這次一共改了 39 項。

### 11.1 驗收結果（2026-10-26 18:31）

- 57 間重建完成（`FAILED_ROUTE []`，沒有出現 `SKIP`）並全部安裝，最終地圖 SHA 1c42021a88b5…：

| 項目 | 結果 |
|---|---|
| audit／routes／physics_plan | passed |
| 完整 cook | package 20261026-172556，exit 0；E 槽的 cook 中間檔已自動清掉 |
| 打包版實拍 | 288 張：motel-v1/runtime-views-20261026-173308/；對照頁 motel-v1/reference-compare-v2/compare-01..29.jpg |
| 快速物理 | passed（physics-20261026-175843.json） |
| 全部路線實走 | passed：79/79 條（依 route id 去重），126 筆紀錄，0 次輔助跨步（physics-20261026-180005.json） |

- 目視檢查：
  - 215：愛心鏤空卡座、愛心床頭、石砌高台浴缸都和官網對得上。
  - 314：紅色鞦韆床、燈籠、紅竹屏風。
  - 503、504：補上沙發組、立燈、邊几、邊櫃，不再只有空曠的地板。
- 記憶體：安裝 57 間時，同一個工作程序一路漲到約 48 GB，沒有超過 60 GB 的停止線。如果之後家具再加多，`--rooms` 要改成每批重開工作程序。

## 12. 第 4 輪擬真度：官網照片對照後的通用修正與新元件（2026-10-28，c-street-city 接手 c-motel-rooms）

依 c-motel-rooms 逐間對照官網照片的結果修改（交接在 side-session-notes `c-motel-rooms-handoff-20261028.md`）。樣板房 209、303、203、512 不動。Tripo 沒有生成。

**通用修正**（`build_street_city_motel_rooms_v2.lua`，所有量產房都會套用）：

| 項目 | 修改 |
|---|---|
| `rect` 浴缸 | 原本的平台（2.7×2.4 m）改成石材檯面。內嵌 1.87×1.27 m 的壓克力缸，靠後牆放，前緣留約 0.5 m 檯面，前面加一階 0.2 m 台階和深色收邊。檯面放捲毛巾、柱狀蠟燭（會亮）、瓶罐和蘭花。佔地不變，路線檢查照樣通過 |
| `clawfoot` 浴缸 | 實心橢圓球改成中空拖鞋缸：捲邊、高起的椅背端、落地龍頭、金色爪腳 |
| 床幔 `bed.canopy` | 預設 `style:'tied'`：四根橫桿都掛扇形垂幔（每段 3 個弧、金色流蘇），四根柱子各有一片落地布簾在 1.05 m 處收束成沙漏形，加綁帶。`style:'flat'` 保留舊樣式。透紗 `sheer` 預設關閉：匯入後材質沒有半透明，會變成兩片白板插進床墊 |
| 窗簾 `extras.drape` | 改用 `drape2`：皺褶深度隨高度增加、下擺外擴並擺動。可加 `tie`（收束高度，預設左右兩片各往外收）和 `valance`（上方扇形垂幔） |
| 印出來的菱格軟包牆 | 牆面 gen 是 `tufted` 時，改成真的立體軟包：菱形塊 0.4 m，兩色交錯，有扣子。後牆會避開浴室開口。規格加 `flat:true` 可保留平面 |
| 印出來的格柵牆 | 牆面 gen 是 `lattice` 時，改成底色素面加金屬 45° 格柵條和邊框 |
| 紅褐大理石 | `marble_redbrown` 改用加深的 `marble_redbrown_deep`（深咖啡色，紋路保留）。樣板房不受影響 |
| 鏡頭位置 | 鏡頭點落在家具 0.3 m 內，或視線前 1.2 m 內有任何物件（包括牆和隔板）時，往四周 0.4～2 m 找沒擋到的點（`VIEW moved` 會記在 log） |

**新元件**：

| 名稱 | 用途 |
|---|---|
| `trellis` | 金屬菱格格柵。`side`、`range`、`z`、`pitch`、`bar`；`back` 可以是材質、`'mirror'` 或 `'none'`；`off` 是離牆距離，疊在軟包上時用 0.16 |
| `padded_wall` | 軟包牆。`pattern` 是 `rect` 或 `diamond`，另有 `size`、`mats`（交錯的顏色）、`button`、`frame` |
| `filigree_screen` | 鏤空金屬屏風。貼牆版用 `side`、`range`、`z`、`glow`（背光）；`side:'free'` 時是落地的多片屏風。材質要明寫在規格裡（gen `filigree`） |
| `pipe_arches` | 213 床兩側的紅色拱形管 |
| `crystal_spiral` | 從天花垂下的螺旋水晶吊飾（201 夏威夷） |
| `bubble_pendant` | 一叢會發光的泡泡吊燈 |
| `drip_frieze` | 牆頂的糖霜滴落飾帶（312） |
| `ceiling_neon` | 天花下方一圈波浪霓虹管（312） |
| `film_strip` | 電影膠卷飾帶，可加海報（214） |
| `gazebo` | 茅草涼亭，可設底座高度 `z`、層數 `layers`（205 的泳池平台） |
| `hanging_chair` | 吊籃椅，可設底座高度 `z` |
| 天花 `ovals` | 金色馬賽克橢圓凹槽，加金色邊框和燈帶（315、402） |
| gen `sky`、`filigree` | 天空白雲彩繪、鏤空花紋 |

**逐間規格**：`Tools/apply_street_city_motel_fidelity_v4.lua` 套用，第一次執行會備份成 `batch-NN.before-fidelity-v4.json`，之後每次都從備份重套。

| 房間 | 修改 |
|---|---|
| 212 | 床頭黑色軟包上加金色格柵 |
| 213 | 床頭金色鏤空屏風（背光）、紅色拱形管 |
| 201 夏威夷 | 黑白菱形軟包加金色格柵、兩組水晶螺旋取代光纖簾 |
| 214 | 天花改成天空彩繪（會亮）、左牆膠卷飾帶 |
| 307 | 客廳圓頂下加泡泡吊燈 |
| 312 | 天花波浪霓虹、三面牆頂加糖霜滴落飾帶 |
| 315、402 | 圓頂改成金色馬賽克橢圓凹槽 |
| 405 | 床頭薰衣草色方格軟包加金框 |
| 205 泳池 | 茅草涼亭、吊籃椅取代原本的方塊 |
| 201 泳池 | 深藍馬賽克池壁、池底 |

**驗收**：
- 地圖 12a96aae2d63…，package 20261028-120946。
- 路線檢查 `FAILED_ROUTE []`，沒有 SKIP。完整實走 79/79、0 次輔助跨步。
- 實拍 `motel-v1/runtime-views-20261028-121559/`：
  - `sheet-v-bath.jpg`：rect 缸都是寬石材檯面加內嵌缸。
  - `sheet-v-bed-front.jpg`：看得到床幔的帷幔和綁帶、213 的拱形管和屏風、212 的格柵、多間的立體軟包。
  - `sheet-v-entry-overview.jpg`：看得到 214 的天空天花、312 的霓虹。

**未完成**：
- 透紗已關，v-left-lounge 鏡頭也改用視線檢查，但這兩項要等下一輪重建、重裝、實拍才看得到效果。
- 交接列的其他招牌件還沒做：307 太陽花鏡（Tripo 的 `gold_petal_round_mirror` 已在）、311 入口紅色藤蔓拱廊（要避開走廊）、泳池水色（`M_SpaWater` 共用材質）。
- 403～416、501～514 只看了一部分。
### 12.1 第 5、6 輪：鏡頭與閃爍修正、57 間重建後的完整驗收（2026-10-28，c-street-city）

**第四輪的結果**（package 20261028-170347）：
- 實拍 288 張，`motel-v1/runtime-views-20261028-171032/`。
- 透紗白板已經消失，v-left-lounge 不再被燈罩擋住。
- 完整實走停在 205 泳池台階回程：角色離地 122 cm，比門檻 120 cm 多 2 cm，判成懸空。這間房三輪的幾何完全一樣，之前三次都走過，所以判斷是偶發誤判。沒改模型，也沒放寬門檻，直接重跑；第六輪通過。

**這兩輪的修正**：

| 問題 | 修正 |
|---|---|
| 213（左牆）、215 的 `panel` 和牆面護板在同一平面，實拍裡格紋沿斜線一半有一半沒有（z-fighting） | `lining()` 加參數 `o`，讓疊上去的那層往房內推出：`panel` 推 1.8 cm，`wainscot` 推 1 cm |
| 304 的紫色單人沙發椅放在床的中軸上、床尾前 2 m，床前視角整個被擋 | `apply_street_city_motel_fidelity_v4.lua` 把它改放到 (-5.5, 3.1)，轉 60° |
| 215 的 v-living-to-bed 被 3.2×2.7 m 的愛心卡座整面擋住（距離 4.1 m） | `sight()` 加中距離檢查：1.5 m 到「到目標距離的 60%」（最多 6 m）之間，畫面中央若有比眼睛高 0.3 m 以上的家具也算擋住，牆和隔間不算。鏡頭找新位置的半徑從 2 m 放寬到 4 m |

**第六輪驗收**：
- 57 間在 Blender 重建：`FAILED_ROUTE []`，74 個鏡頭被挪開。分 12 批裝進地圖，住宅、體育館擺設也重套。
- 地圖 c757889a2744…，package 20261028-195122。

| 項目 | 結果 |
|---|---|
| audit／routes／physics_plan | passed |
| cook | exit 0（11 分鐘） |
| 57 間實拍 | 288 張：`motel-v1/runtime-views-20261028-200119/`，各視角總覽 `sheet-v-*.jpg` |
| 快速物理 | passed（physics-20261028-202118.json） |
| 完整實走 | passed：79/79 條、127 筆紀錄、0 次輔助跨步（physics-20261028-202243.json）。超過 100 ms 的幀有 417 個，最長 580 ms。當時整合的 D 引擎 cook 同時在跑，這項不是驗收門檻 |

- 目視檢查：
  - 213 的格紋完整，閃爍消失。
  - 304 的床前視角只在左下角露出椅子一角。
  - 57 張 v-left-lounge 都沒有被近距離物件擋住。
  - 床幔、浴缸、入口總覽、泳池都正常。
- 215 的卡座在第六輪實拍時仍然擋住畫面：當時中距離檢查的上限只有 3 m。改成 6 m 並放寬找新位置的半徑後，只重建了 215 這間（只有鏡頭位置變，地圖不變），再用同一個 package 補拍 5 張：`motel-v1/runtime-views-20261028-205911/`。現在看得到心形床頭和整張床，卡座只在畫面左側。
- 另外 56 間的鏡頭還是第六輪建模時的結果（中距離上限 3 m）。下次全部重建時會套用 6 m 上限和 4 m 搜尋半徑。

**還沒做**：
- 311 入口的紅色藤蔓拱廊（要避開走廊）。
- 泳池水色：`M_SpaWater` 是共用材質。
- 403～416、501～514 還沒有逐間對照官網照片。
### 12.2 第 7、8 輪：照片修正第 5 輪、311 拱廊、泳池專屬水色、泳池外梯；第 6 輪規格（2026-10-28～29，c-street-city）

**新元件與共通修正**：

| 項目 | 內容 |
|---|---|
| `vine_arcade`（extras） | 入口走道上方一排紅漆圓拱：`at`、`n`（拱數）、`pitch`（間距）、`clear_w`（淨寬）、`spring`（起拱高）、`rise`（拱高）、`mat`。柱子放在淨寬外側，拱肋上有藤莖、葉、花，三條縱向花環，每隔一道拱在柱外垂藤到 0.9 m。起拱高以下不進淨寬，所以不擋走道。311 用 `n=6, pitch=0.6, clear_w=1.5, spring=2.35, rise=0.7`，並加了鏡頭 `v-entry-arcade` |
| 泳池水 `pool.water {color, opacity}` | 泳池水改用自己的 glTF 槽 `S_PoolWater`。安裝時建 `M_MotelPoolWater`（由 `M_SpaWater` 複製，加上 `WaterColor`、`WaterOpacity` 參數），每間建一個 `MI_PoolWater_<id>`。`M_SpaWater` 本身和浴缸水都不變。201 是深藍 (.01,.025,.07)，205、207 是綠藍 |
| 泳池外梯 | v2 泳池套房（201、205、207）的外側台階從 7 階、每階 18 cm 改成 10 階、每階 13.6 cm、踏面 22 cm。實走的懸空判定上限是 120 cm，站立時離地 104.7 cm，18 cm 的台階下行時會超過（第 4、7 輪各誤判一次）；13.6 cm 是 118.3 cm。`street_city_motel_routes_payload.lua` 對 v2 房用新台階，樣板房 203 仍是 7 階 18 cm |
| 鏡面材質（建模器） | 灰色、`metal≥.95`、`rough≤.06`、沒有貼圖的材質，在封閉房間裡沒有東西可反射，實拍是一片藍灰平板（414、506）。改成暖銀 (.78,.74,.7)、metal .65、rough .12 |
| 吊燈和主燈錯開 | 主燈（向下的 spot）若在吊燈 0.9 m 內，移到吊燈旁 1.1 m。之前燈在水晶垂飾裡面，會在地板投出放射狀的黑影（402、407） |

**第 7 輪**（57 間重建＋安裝，package 20261028-223833）：
- 實拍 288 張：`motel-v1/runtime-views-20261028-224509/`。
- 完整實走在 207 外側台階回程誤判（離地 122.6 cm），因此改了上面的外梯。
- 實拍時發現兩個問題：
  - 泳池水那行在改材質時被弄丟，201、205、207 都沒有池水；
  - 311 的拱廊沒有鏡頭拍到。
  - 細節見 `Docs/STREET_ERRORS.md`。

**第 8 輪**（只重裝 201、205、207、311，地圖 97b11930c01f…）：

| 項目 | 結果 |
|---|---|
| cook、實拍 | 通過；實拍 `motel-v1/runtime-views-20261028-234319/` |
| 快速物理 | passed（physics-20261028-234614.json） |
| 完整實走 | passed：79/79 條、126 筆紀錄、0 次輔助跨步（physics-20261028-234738.json） |

- 目視檢查：
  - 205 的池水是藍綠色，看得到池底磁磚。
  - 201 是深藍。
  - 311 的 `v-entry-arcade` 拍到 6 道紅拱和藤葉；柱子比照片粗一些。

**第 6 輪規格**（`apply_street_city_motel_fidelity_v4.lua` 的 `P6`，套在 P、P5 之後）：
- 子代理對照 4F、5F 共 29 間的官網照片後寫成，逐間調整天花、牆、地毯、沙發、床頭、浴室的顏色與材質。
- 修了幾個突兀的東西：
  - 506 的 7 塊扇形床頭方塊改成 `wing` 床頭；
  - 508 浮在 2.6 m 的櫻花改成落地盆栽；
  - 511 的天花從 mirror 改成黑亮 tray。
- 也加了兩個鏡頭：507 一圈 8 道紫珠簾，514 的 `v-bath-niches`。
- 沒做、要新元件的項目：地紋旋轉 45°、藤葉頂棚、金字塔斜頂、下沉浴缸、實心愛心板、波浪漆框、環形珠簾。
- 新增的程序貼圖要先跑 `build_street_city_motel_room_textures.lua`，否則建模器會在讀貼圖時中斷。
- 第 6 輪規格和建模器修正會在第 9 輪一起重建 57 間並驗收。
### 12.3 第 9 輪：57 間全部重建（P6 規格＋鏡面與吊燈修正）後的完整驗收（2026-10-29，c-street-city）

| 項目 | 結果 |
|---|---|
| 安裝 | 57 間；3 間一批，worker 39.2～40.0 GB |
| cook | package `20261029-023245`，地圖 SHA `e85c91c9d084…` |
| 實拍 | 57 間、290 張：`motel-v1/runtime-views-20261029-023959/` |
| 快速物理 | passed（physics-20261029-030049.json） |
| 完整實走 | passed：79/79 條、127 筆、0 次輔助跨步、soak 1796 秒（physics-20261029-030219.json） |

**全域修正**：三個子代理逐間對照官網照片，結果如下。

| 修正項目 | 結果 |
|---|---|
| 鏡面改為暖灰半金屬 | 57 間都不再出現發藍的鏡面 |
| 主燈與吊燈錯開 1.1 m | 57 間都看不到放射狀黑影 |
| 泳池 | 205、207 的池水是藍綠色；201 仍是深藏青 |
| 311 拱廊 | 拱廊和鏡頭都在；藤蔓偏稀，拱廊盡頭頂到電視 |

**仍與照片不符的房間**（總覽圖在 scratchpad 的 `review9/`；之後重拍用同一套 `review.lua`）：

| 房號 | 問題 | 判斷 |
|---|---|---|
| 404 | 軟包牆是亮洋紅（照片是暗酒紅）；板下有一排白色直條 | 疑似收邊錯誤 |
| 405 | 地毯仍整片黃，沙發讀成白色 | P6 已套上，但只加深了地毯的線，底色還是黃；香檳色在粉紅燈下讀成白。要連底色一起改 |
| 406 | 拱門仍是方柱加橫樑；柱上有白色膠囊疑似浮空；`v-left-lounge` 被柱子擋住；看不到階梯浴缸 | — |
| 416 | 窗簾讀成灰柱並擋住 `v-left-lounge`；浴室是粉紫（照片是白銀） | — |
| 510 | 浴缸是凸起的方缸，照片是下沉式並有大盆栽 | 要「下沉浴缸」新元件 |
| 513 | 圓形霓虹是白色（照片是金色）；牆面大片白，照片是深色亮片馬賽克 | — |
| 312 | 霓虹波浪、棒棒糖、旋轉木馬幾乎都缺 | — |
| 306 | 床頭牆一大片藍白棋盤，照片是白色背光方格陣列 | 疑似貼圖錯誤 |

- 曝白的鏡頭：501、502 的 `v-bath`，506 的地板；313、315 的 `v-bath` 接近曝白。浴室燈太亮，也讓 406、416 看不出階梯浴缸。
- 408 的芥黃沙發沒改到：那張是 Tripo 模型 `khaki_long_sofa`（v2），用自己的貼圖，規格的 `mat` 顏色蓋不過去。
- 深色材質在遊戲裡讀成中灰（401、410、503 的牆板）。
- 共同問題：大多數房間用同一款方形按摩浴缸和同一款床；101 與 201 夏威夷的 `v-bath` 幾乎一樣。
- 下一步（第 7 輪規格）：
  - 先修 404、405、406、416、306 的錯誤和鏡頭遮擋；
  - 調降浴室燈；
  - 加入下沉浴缸、環形珠簾、藤葉頂棚等新元件；
  - 讓浴缸和床依房型分出款式。

### 12.4 第 10 輪：第 7 輪規格（P7）＋浴室主燈調暗；第 11 輪的修正（2026-10-29，c-street-city）

**第 10 輪**：重建並安裝 57 間。

| 項目 | 結果 |
|---|---|
| package | `20261029-045539`，地圖 SHA `be18c8c8ebbc…` |
| 完整實走 | passed：79/79 條、0 次輔助跨步（physics-20261029-052726.json） |
| 實拍 | 57 間、290 張：`motel-v1/runtime-views-20261029-050259/` |

**P7**（`apply_street_city_motel_fidelity_v4.lua`，套在 P6 之後）調整了 11 間：404、405、406、408、416、510、513、312、306、201、311。

建模器的改動：
- 浴室主燈改成 `light.bath`，預設 1500 lm（原本 2500）；
- 規格裡和預設鏡頭同 id 的鏡頭，會取代預設鏡頭；
- `vine_arcade` 新增 `leaves`、`flowers`、`trail`、`garland_step` 參數。

**第 10 輪的審查結果**（逐間和第 9 輪比較）：

| 房號 | 結果 |
|---|---|
| 404 | 白色直條沒了，但軟包仍偏亮紫 |
| 405 | 地毯改成深棕配金格，金色偏淡 |
| 406 | 圓角塊拿掉，兩個新鏡頭合理；拱門仍是直角門框 |
| 312 | 進步最多；霓虹偏白青，棒棒糖太小 |
| 408 | 新沙發讀成白色 |
| 416 | alpha 簾子仍讀成實心柱 |
| 510 | 盆栽太小 |
| 513 | 主牆改成整間都套，連白色床頭牆也變黑；金色霓虹讀成白 |
| 306 | 方格對比太低 |
| 201 | 水太不透明 |
| 311 | 新的拱廊鏡頭在拱廊裡，只拍到柱子 |

其他 46 間的回歸檢查：其他鏡頭幾乎逐像素相同，沒有新錯誤。

**浴室曝白的原因**：浴室燈降 40%，v-bath 的亮度只降約 3%。遊戲開著自動曝光（host 的 `r.DefaultFeature.AutoExposure=True`，沒有 PPV），而 `capture_street_city_motel.lua` 切鏡頭後約 100 個 frame 就拍照，曝光還停在上一個較暗的鏡頭。
- 修正：新增 `OK_MOTEL_CAPTURE_SETTLE`（frame 數，預設 100），驗收時傳 300。
- 浴室燈的調整留著，等曝光收斂後再判斷亮度。

**第 11 輪的修正**（仍寫在 P7 裡）：

| 房號 | 修正 |
|---|---|
| 404 | 天花燈槽 `cove_emit` 降為 4 |
| 405 | 金格加亮；沙發改香檳金皮革 |
| 408 | 沙發壓暗成卡其 |
| 416 | 兩道布簾改成 `fiber_curtain` 珠串（香檳色、低發光，新增 `pitch`、`r`、`emit` 參數） |
| 510 | 盆栽 `scale=1.8`（`plant` 新增 `scale`） |
| 513 | 主牆改回原樣；霓虹 `emit=4`（`neon` 新增 `emit`） |
| 312 | 霓虹改飽和藍、`emit=8`；棒棒糖 `r=0.55`（`lollipop` 新增 `r`） |
| 306 | 方格對比加強 |
| 201 | 水的 opacity 改為 0.55 |
| 311 | 拱廊鏡頭改 fov 90、往上仰 |

第 11 輪只重裝這 11 間，以 300 frame 的等待時間重拍 57 間。

### 12.5 第 12 輪：浴缸水、反照率上限、406／510／513／312（2026-10-29，c-street-city）

| 項目 | 結果 |
|---|---|
| 安裝 | 57 間重建並重裝；同一輪加上世界邊緣的遠景地面（`WorldEdge_Skirt`） |
| cook | package `20261029-112318`，地圖 SHA `5e44178a782a…` |
| 實拍 | 57 間、290 張，每個鏡頭等 300 frame：`motel-v1/runtime-views-20261029-113054/` |
| 完整實走 | passed：79/79 條、0 次輔助跨步（physics-20261029-121644.json） |

**修正內容**：
- 浴缸水改用自己的槽 `S_TubWater`，不透明度 0.72；
- `mat()` 把反照率上限壓到 0.85；
- 新元件：`portal`（406）、`sunken` 浴缸（510）、`halo`（513）；
- 513 霓虹改琥珀色、emit 1.5；312 霓虹 emit 3、沙發改珊瑚紅。

**審查結果**：

| 房號 | 結果 |
|---|---|
| 513 | 圓形霓虹變成金色；天花藍色光環有出來；浴缸看得到淺青色的水 |
| 312 | 沙發變成珊瑚橘；霓虹是藍色，不再偏白；浴缸看得到水 |
| 510 | 變成低矮的下沉浴缸，有深色木框和淺色的水 |
| 406 | 門框兩側變成圓角平板。平台浴缸內側仍是白的：水在，但被缸緣的 LED 環（emit 8）和浴室燈打成淺紫白 |
| 506 | 白色地磚仍曝白，平台浴缸內側一樣發白 |

**第 13 輪的修正**（已改，還沒重建）：
- 浴缸水預設改成更深的 (.01,.07,.09)，不透明度 0.85。半透明的水用粗格的體積光照，在白色浴室裡會被照亮成白色。
- 平台浴缸的 LED 環 emit 改成 2.5（規格可用 `glow_emit` 覆寫）。
- 程序貼圖也套上 0.85 的反照率上限（`build_street_city_motel_room_textures.lua` 的 `C()`）。名稱的雜湊加上 `|cap85`，所以會全部重新產生。

### 12.6 第 13 輪結果、第 14 輪修正（2026-10-29，c-street-city）

- 第 13 輪完整驗收通過：打包 20261029-134645，地圖 a06534d1…，79/79 路線、0 assists；實拍 `motel-v1/runtime-views-20261029-135313`（290 張）。
- 浴室曝光：315 等間的白牆、白磁磚已不再截頂成純白（反照率上限 0.85 生效）。
- 仍有問題：浴缸水（406、506 平台浴缸、513 圓浴缸、315 方浴缸）看起來仍是淺灰或淺紫的空碗，看得到噴嘴。半透明材質吃粗格的體積光照，調顏色和不透明度都無效（詳見 STREET_ERRORS.md）。
- 第 14 輪修正：
  - 浴缸水改用不透明材質 `/Game/UniversityCity/MotelV1/Materials/M_MotelTubWaterOpaque`（WaterColor 參數、roughness 0.04、specular 0.6），每間一個 `MI_TubWater_<id>`（`street_city_motel_sample_payload.lua` 的 `motel_tub_water_mi`）；泳池水不變。
  - 506 地板從 tile_white_large 改成 marble_cream（P7），只重建 506，路線檢查通過。