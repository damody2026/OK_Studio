# 大學城道具索引：女主知道身邊有什麼（2026-11-03）

聊天時，女主要知道自己在哪個房間或地點、附近有哪些道具（鏡子、椅子、床、廁所……）與店面，能拿來聊，也能走過去互動。場景這邊提供兩樣東西：

| 東西 | 位置 | 說明 |
|---|---|---|
| 道具索引資料 | `output/street-social-city-production/places-v1/props.json`（約 3 MB） | 由 `Tools/build_street_city_places.lua` 第 5 節產生，跟 `places.json` 一起重建 |
| 查詢模組（Rust） | `Tools/ok-city-props/` | 讀 `props.json`，在 10 m 格網上查半徑 10 m／20 m 內的道具、所在區域與附近地點；介面和 ok-rules 一樣是 JSON request／response，之後整段搬進 ok-rules |

重建：

```powershell
.\Tools\lua\lua.exe Tools\build_street_city_places.lua
cargo test --release --manifest-path Tools\ok-city-props\Cargo.toml
```

## 資料內容

座標是 UE cm，+X 北、+Y 東（和遊戲、`places.json` 相同）。

- `kinds`：道具種類 → `zh`（中文名）、`category`（furniture、bathroom、mirror、shop、outdoor、landmark、sport、music、kitchen、device、lab、health、exhibit、building、misc）、`uses`（她能做的事：sit、lie、sleep、look_mirror、toilet、wash_hands、shower、bath、buy_drink、play_game、pray、photo、view……）。
- `areas`：她可能「在裡面」的地方。
  - `kind = room`：組裝清單的所有房間（宿舍、教室、廁所、店面、汽車旅館房），有 `min`／`max` 盒子、門口 `door`、`privacy`、`building`、`floor`、`type`。
  - `kind = place`：戶外地點，例如噴水池廣場、涼亭、燈塔、鐘塔、遊樂場、小樹林、十個活動場景，以 `door` 加 `radius_cm` 表示範圍。
  - `kind = building`：每棟建築與店面，有街道入口與外框盒子。
- `props`：每件道具都有 `k`（種類）、`p`（位置；鏡子是鏡面中心，其他是物件底部）、`a`（所屬 area 的索引，戶外沒有歸屬時省略）、`face`（正面朝向的世界 yaw，已知時才有）、`n`（專名，例如「天花板鏡」「床邊大鏡子」「練習用大鏡子」「腳凳休憩椅」「拉麵攤」）。

目前 33,330 件道具、1,506 個區域。主要種類件數：

| 類別 | 種類（件數） |
|---|---|
| 床與座位 | 上下舖 854、雙人床 221、床 102、沙發 388、椅子 4,510、長椅 576、躺椅 28、海灘躺椅 84 |
| 桌櫃 | 課桌 5,230、書桌 4,026、桌子 748、衣櫃 1,970、置物櫃 1,163、矮櫃 1,204、書架 396 |
| 衛浴 | 鏡子 1,437、馬桶 1,778、廁所隔間 941、洗手台 1,633、淋浴間 1,257、浴缸 61、浴池 10、小便斗 250 |
| 店面 | 櫃台 110、收銀台 170、商品架 212、展示櫃 57、衣架 18、人台 60、商品 173、自動販賣機（安裝後）、餐車 9、書報攤 4 |
| 生活設備 | 冰箱 347、流理台 202、爐台 142、電腦 521、電視和遊戲機 17、洗衣機 8、烘衣機 16、咖啡機 6、電梯 94、垃圾桶 479 |
| 戶外與地標 | 野餐桌 45、露天咖啡座 23、涼亭 18、花架 13、噴水池 3、燈塔、鐘塔、戶外舞台、遊樂設施、鞦韆、桌球桌、望遠鏡、觀景平台、景觀裝置 19、許願掛架、木琴、石燈籠 125、櫻花樹 163、魚池、救生員塔、沖水台 |
| 活動場景 | 大熊合照點、畫架、繪本牆、夜市各攤（糰子、拉麵、壽司、茶飲……）、玫瑰花束、飼料機、祭典門、練習舞台 |

資料來源：

1. 建築內烘進樓層網格的家具：讀各棟 `assembly-report.json` 的 instances，教室座位則改用 functional-interiors 回執中移動後的位置。
2. 汽車旅館房：從 `places.json` 的套房取床、浴缸，以及實際裝上的牆鏡和天花板鏡（含鏡面法線）。
3. 地圖 actor：戶外家具、地標、廁所和練舞教室的反射鏡、石燈籠、櫻花樹；度假村道具用 `resort-streetscape-v1/catalog.json` 的中文名。
4. 街道上的長椅、回收桶、腳踏車架、公車亭：地圖裡併成整座城市的 cluster actor，從 actor 取不到單件位置，改用街道擺放計畫套到實測路緣（`Tools/street_city_anchors.lua`）。
5. 戀人地點：販賣機、交誼廳沙發與電視、神社、水族箱等，讀最新的 `world-edge-v1/lover-spots-install-*.json`。
6. 去重：同種道具間距 45 cm 內視為同一件，鏡子放寬到 1 m。洗手台上方烘進牆裡的鏡子，和後來補裝的反射玻璃是同一面鏡子。

## 查詢方式（Rust）

```rust
let idx = ok_city_props::PropIndex::load(path)?;          // 載入一次，約 30 ms
let v = idx.eval("nearby_props", &json!({ "pos": [x, y, z], "radius_cm": 1000 }));
```

| `kind` | request | 回傳 |
|---|---|---|
| `nearby_props` | `pos`、`radius_cm`（預設 1000）、可選 `kinds`／`categories`／`through_walls`／`area_radius_cm`（預設半徑×2） | `here`（她所在的區域）、`props`（依名稱分組：件數、最近距離、最近那件的位置與朝向、方位、uses）、`areas`（附近的店面、地點，以及同棟的房間）、`text`（給聊天 prompt 的一段中文） |
| `prop_list` | 同上，可加 `limit` | 每件道具的 index、kind、name、pos、face、area、dist_cm，由近到遠 |
| `nearest_prop` | `pos`、`kinds` 或 `categories`、`radius_cm` | 最近的一件，附位置與方位，讓她走過去用 |
| `area_at` | `pos` | 她所在的房間、地點或建築 |

`text` 範例（實際資料）：

- 宿舍房：「妳在「訪客住宿房A」。附近有：上下舖×2（最近 0.0 公尺）、椅子×4（最近 1.2 公尺）、衣櫃×4、書桌×4、馬桶（3.1 公尺）、洗手台（5.5 公尺）、鏡子（6.0 公尺）、淋浴間（6.4 公尺）。附近的地點：2樓寢室09（西北邊 7.3 公尺）、自習室……」
- 民宿房：「妳在「日式民宿 101 峇里島」。附近有：雙人床（0.0 公尺）、天花板鏡（3.1 公尺）、床邊大鏡子（4.1 公尺）、浴缸（6.1 公尺）。」
- 8F 合照點：「妳在「模型玩具店」。附近有：環形日落框景、大熊合照點（1.0 公尺）、玫瑰花束×4……附近的地點：8F 大熊合照點（就在旁邊）、拉麵店（西南邊 14 公尺）、手機店……」

可見範圍規則：

- 她在房間裡，只看到這個房間的道具。
- 她在走廊、大廳或戶外，看到不屬於任何房間的道具；別的房間裡的家具隔著牆看不到。
- 高度差 2.5 m 以內才算同一層；鏡子多算 1.5 m，因為牆鏡的鏡面中心比較高。
- `through_walls: true` 會忽略牆，例如用來問「這棟樓裡最近的廁所在哪」。

效能：單次 20 m 查詢約 10 µs（2,000 次實測，release 版）。

CLI（手動抽查用）：

```powershell
Tools\ok-city-props\target\release\ok-city-props.exe output\street-social-city-production\places-v1\props.json nearby_props '{"pos":[50070,50406,1281],"radius_cm":1000}'
```

## 給整合者：併進 ok-rules

1. 把 `Tools/ok-city-props/src/lib.rs` 搬成 `Tools/ok-rules/src/city_props.rs`（測試一起搬）。ok-rules 已經有 `serde`／`serde_json`，不用新增依賴。
2. 在 ok-rules 的 eval 串接加上 `city_props::eval`，問題種類就是上表四種。`PropIndex` 在 rules 載入時讀一次就好，它是不可變的資料，可以跟 tuning 放在一起。
3. `props.json` 搬進 Content，例如 `Content/StreetSocial/Data/city_props.json`，因為 `Saved/` 與 `output/` 都不隨遊戲出貨。Rust 用一般檔案 IO 讀取，所以要比照 `v1` 共用資源，在 Build.cs 宣告成 NonUFS runtime dependency。
4. 中文名目前寫在 `kinds[*].zh`。照文字表規則，整合時可以改成 `Localization/<lang>/props.toml` 的 `prop.<kind>` id，再用 `tr::t` 取名稱；`describe` 的句型改用 ICU 訊息。
5. C++ 只負責轉送：聊天前送出 `nearby_props`（帶女主位置），把 `text` 放進 prompt；她決定去用某件道具時，用 `nearest_prop` 或 `props[i].nearest.pos` 走過去。

## 已知限制

- `COMMON-PROP-<hash>` 這類沒有名稱的組裝道具，以及結構件（門、窗、天花燈、通風口）、書本與商品紙箱，沒有列入。
- 路燈、花圃、地磚、灌木與一般樹（樟樹、行道樹）不列。櫻花樹只列有單件位置的 163 棵。部分 CityArt 與度假村樹木是整座城市一個 cluster，從 actor 取不到單件位置，也不列。
- 自動販賣機、交誼廳沙發與電視、神社、S28 水族箱，要等戀人地點安裝（chain10）完成、重新跑一次產生器之後才會出現。
- 房間盒子沿用組裝清單的淨尺寸；落在房間外框邊緣的道具，可能被歸到建築而不是房間。
