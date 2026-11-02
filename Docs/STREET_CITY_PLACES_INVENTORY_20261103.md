# 大學城地點盤點：一般活動與 H 地點（2026-11-03）

使用者 11-03 要求：明天把大學城（`StreetSocialCity` 專案的 `/Game/UniversityCity/Maps/UniversityCity`）換進街區遊戲，今天先把所有可以做一般活動、色色姿勢的地點盤點出來，並和 [C組] 街區攻略確認。

- 資料：`output/street-social-city-production/places-v1/places.json`，共 612 個地點。
- 重建：
  1. 拿 Unreal slot，跑 `lua Tools/street_city_motel_job.lua world_places_probe Tools/street_city_places_payload.lua`，輸出 `places-v1/actors.json`（地圖全部 actor）。
  2. 跑 `Tools\lua\lua.exe Tools\build_street_city_places.lua`。
- 座標：UE 公分，+X 北、+Y 東，和遊戲 `OKStreetSocialPlaces.h` 同一套。錨點 yaw 照遊戲規則：站在錨點上的角色面向 yaw + 90。

## 遊戲讀地點的方式（換地圖要知道的事）

- 遊戲的地點全部寫死在 `Source/OpenKoikatsu/OKStreetSocialPlaces.h` 的 `OKStreetPlaces()`。每個地點有：
  - `Id`
  - `Door`（抵達點）
  - `Rooms`（世界座標框，用來判斷「現在在哪」）
  - `Anchors{Name, Position, Yaw}`
  - `.okmesh` 模型
- 活動在 `Content/IndependentResources/StreetSocialData/rules/activities.toml` 綁「地點 id ＋ 錨點名」：
  - `bench`、`seat`、`table`、`counter`、`pool`
  - `bed1_0`、`bed2_0`、`bed3_0`、`bed6_1`
  - `vending`、`fountain` 等
- **H 的條件**：`RequestIntimacy` 要求所在地點 `places.toml` 的 privacy ≥ 2（目前是 lodge、minshuku、boys_dorm）。hotel 是 1，會帶去 `hotel_rest`。
- **H 姿勢和地點無關**：姿勢來自 `h_poses.json`，床由 H 場景自己生出來，不讀地點錨點。接吻、擁抱也不綁地點，只看 `places.toml [acts]` 的尷尬度（kiss 要 privacy ≥ 1、人少）。
- **換地圖要做的事**：把地點表從寫死的方塊建築改成讀這份 `places.json`（或照它產生 C++ 表）。地圖路徑寫死在：
  - `Tools/run_street_social_development.lua:463`
  - `OKStreetSocialScene.cpp:4661`

## 可以做 H 的地點（privacy 2、可上鎖）

| 類別 | 數量 | 位置 | 錨點 | 備註 |
|---|---:|---|---|---|
| 汽車旅館客房 `motel_suite` | 54 + 4 泳池房 | H1 星澄汽車旅館 2–5 樓 | `bed1_0`（床中心、床面高度）、`bath`、`stand`、門口 | 56 間有真的會反射的鏡子：47 面床邊牆鏡（1.8 m 高）、41 面床正上方天花板鏡（1.8 × 1.4 m）。遊戲只開最近兩面。泳池房另有泳池；多數房有車庫 |
| 日式民宿客房 | 3 間汽車旅館式套房 ＋ S18 原有 3 間和室 | S18 | 同上；S18 和室有 `bed`、`sofa` | 對應遊戲的 `minshuku` |
| 宿舍房 `room_dorm` | 208 間（D1–D4 各 52） | D1 女宿、D2 男宿、D3 研究生、D4 國際生 | 每間 2 張上下鋪 `bed*`（下鋪約 37 cm、上鋪約 138 cm）、書桌座位、淋浴 | `sleep_rule`：需住戶或受邀。D2 對應遊戲的 `boys_dorm`，D1 對應 `girls_dorm` |
| 公寓 `room_apartment` | 80 間（R1、R2 各 40） | 青年租屋公寓、河景家庭公寓 | 雙人床（king）、2 張沙發、淋浴 | 床和沙發都可以 H（`h_bed`、`h_sofa`） |

## 半私密地點（privacy 1）

- 溫泉會館 S19：1–2 樓各 5 個 SPA 池（`pool*`）與 11 張躺椅，3 樓有休息床。對應遊戲 `onsen`。H 要看遊戲要不要開放包場。
- 午睡室：CV、LI、SC、TR 各 1 間，各 2 張床。
- 戶外：
  - 樹叢 22 處（`grove_*`，每處最多 16 棵樹，離道路與物件 25 m 以上，城市邊緣的空草地）。是戶外隱密點的候選。
  - 涼亭 2 座、燈塔 1 座：接吻、看海、躲雨。

## 一般活動地點（privacy 0）

| 類別 | 數量 | 用途 |
|---|---:|---|
| 公園長椅 `park_bench` | 55 | 並坐、聊天、接吻（要人少） |
| 海灘躺椅 `beach_lounger` | 84 | 躺、曬太陽、看日落 |
| 野餐桌 `picnic_table` | 40 | 吃東西、並坐 |
| 戶外咖啡座 `outdoor_cafe_set` | 16 | 喝飲料 |
| 噴水池 | 2 | 合影（`park_photo`、`fountain`） |
| 舞台、鐘塔、遊樂場 | 1 / 1 / 4 | 看表演、約見面、玩 |
| 活動場景 `actspace-01…10` | 10 | 8F 大熊、噴水池寫生、夜市、海灣步道、煙火觀賞台、錦鯉池、晨練慢跑、行政窗口、繪本區、表演空地（見 `Docs/StreetSocialCity/production/activity-scenes-implementation.md`） |
| 大樓共用區 `room_building_common` | 11 棟 | 宿舍交誼區、接待大廳沙發等 |

遊戲現有地點和大學城建築的對應：

- 商店：
  - `department` → M1 大學城百貨
  - `cafe` → S01 咖啡書屋
  - `drinkshop` → S02 手搖飲店
  - `restaurant` → S04 家庭餐館
  - `fruitshop` → S05
  - `conveni` → S06
  - `bookstore` → S07
  - `petshop` → S08
  - `lottery` → S20
- 校園：
  - `library` → LI
  - `cafeteria` → SC 學生中心
  - `campus_*` → 同代號館舍
  - `campus_sports`、`playground` → SP 運動健康館
- 住宿：
  - `girls_dorm`、`boys_dorm` → D1、D2
  - `hotel` → H1
  - `minshuku` → S18
  - `onsen` → S19
- 戶外：`park` → PK 公園。

另有 40 多家同類小店（S21–S96）可以當分店或新地點。

## 還沒做或有疑問

- **店內座位**：S01–S96 的模組化商店只有 S18、S19 讀進了錨點，其他店的桌椅還沒換算。
- **百貨**：M1 沒有家具實例，只有規劃資料。
- **H1 原本的飯店房**：被汽車旅館取代的那幾層沒有列入。H1 只列 1 樓大廳。
- **汽車旅館 209**：`imore-93474c507aaf` 是樣板房，床不在預設位置，床錨點是預設值，要再量。
- **沒有鏡子的房間**：`imore-6f5e5a7cdf7b`、`imore-345b250913f7`、`imore-cda5d5e2dcb9`、`wego-linsen-3480fecda6b2`。床邊沒有平整的牆，天花板也不平。
- **宿舍 1 樓 16 張床**：沒有實測資料可以對照。其餘 400 張和地圖實測相差都在 10 cm 內。
- **門口**：室內地點的 `door` 目前是家具範圍的中心，不是真正的房門；汽車旅館用的是真正的入口。
- **等攻略確認**：哪些地點開放 H、戶外隱密點要不要開放、還缺哪些場地。
