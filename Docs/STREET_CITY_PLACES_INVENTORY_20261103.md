# 大學城地點盤點：一般活動與 H 地點（2026-11-03）

使用者 11-03 要求：明天把大學城（`StreetSocialCity` 專案的 `/Game/UniversityCity/Maps/UniversityCity`）換進街區遊戲，今天先把所有可以做一般活動、色色姿勢的地點盤點出來，並和 [C組] 街區攻略確認。

- 資料：`output/street-social-city-production/places-v1/places.json`，共 781 個地點。
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
| 商店樓層 `room_shop` | 169 層（S01–S96） | 店內座位 `seat*`、桌子 `table*`、沙發，共 1102 個錨點；都在該店範圍內。咖啡、手搖飲、餐館、甜點、書店等各自對應遊戲的 cafe／drinkshop／restaurant／snack／bookstore |

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

- **百貨**：M1 沒有家具實例，只有規劃資料。
- **H1 原本的飯店房**：被汽車旅館取代的那幾層沒有列入。H1 只列 1 樓大廳。
- **汽車旅館 209**：`imore-93474c507aaf` 是樣板房，床不在預設位置，床錨點是預設值，要再量。
- **沒有鏡子的房間**：`imore-6f5e5a7cdf7b`、`imore-345b250913f7`、`imore-cda5d5e2dcb9`、`wego-linsen-3480fecda6b2`。床邊沒有平整的牆，天花板也不平。
- **宿舍 1 樓 16 張床**：沒有實測資料可以對照。其餘 400 張和地圖實測相差都在 10 cm 內。
- **門口**：室內地點的 `door` 目前是家具範圍的中心，不是真正的房門；汽車旅館用的是真正的入口。
- **等攻略確認**：哪些地點開放 H、戶外隱密點要不要開放、還缺哪些場地。

## 明天把大學城換進遊戲：做法草案（11-03 整理）

現況：大學城在獨立專案 `StreetSocialCity/`，引擎 `E:/PhysX/UE5.8`。

- Content 有 83 GB，裡面有歷史資產；完整 cook 之後約 21.6 GB。
- 地圖依賴兩個 Runtime 外掛：
  - `CityEnvironment`：日夜時鐘、`CityEnvironmentController`、`ACityImmersionWalker`（鏡子「最近兩面」的開關也在這裡），附 ThirdParty。
  - `CityLocalization`：三語招牌。
- 另有 Editor 外掛 `CityDepthAudit`，只有驗收用得到。

建議步驟：

1. **外掛**：把 `CityEnvironment`、`CityLocalization` 複製進 `OpenKoikatsu/Plugins/`，在 `.uproject` 啟用。這是共用程式碼，提交前要照 AGENTS.md 建置遊戲 `OpenKoikatsu` Development 和編輯器，確認連結成功，也要通知 E／F 組。
2. **內容**：用編輯器的 Migrate，從 `/Game/UniversityCity/Maps/UniversityCity` 沿依賴搬到 `OpenKoikatsu/Content/UniversityCity/`，只搬地圖實際用到的資產。
   - 這些是第三方生成模型與大量貼圖，照「版控只放共用資源」不進版控：加 `.gitignore`，只留本機，和角色卡一樣。
3. **玩家與鏡子**：遊戲用自己的 Pawn。地圖裡的 `ACityImmersionWalker` 只用在大學城自己的實走驗收。換進遊戲後，鏡子的「最近兩面」開關要改由遊戲的 Pawn 或場景 Tick 呼叫，或保留一個不受控制、只負責開關鏡子的 actor。
4. **地點**：
   - 把 `OKStreetPlaces()` 的寫死表換成讀 `places.json`（或由它產生 C++ 表）。
   - 遊戲原有 id（`cafe`、`hotel`、`boys_dorm`…）依上面的對照表指到大學城的地點。
   - 汽車旅館、宿舍、公寓等新的可上鎖房間，在 `places.toml` 加 privacy 2 的類別。
5. **地圖路徑**：改兩處，`Tools/run_street_social_development.lua:463` 和 `OKStreetSocialScene.cpp:4661`。路線點（`OKStreetPlaceRoutePoints`）改用大學城的道路與門口。
6. **打包**：照 `rebuild_street_social_runtime.lua` 的完整流程（新 tag、新 base），C 端用 `D:/PhysX/UE5.8`；兩邊引擎都是 5.8 PhysX 分支。
7. **驗收**：`StreetSocial.cmd` 實際啟動、走到各地點、睡覺、H 能在旅館房進行，`CardReaderDevelopment.cmd` 也要能啟動。

步驟 1、3、4、5 動到 C++，要使用者決定由誰做。我（c-street-city）目前只動場景。

### 給整合者：每一步需要的資料

協調者 11-03 決定：C++ 的部分（第 1、3、4、5 步）照使用者 11-01 的說法，留到使用者整合時處理。c-street-city 只負責把資料準備好。

**`places.json` 欄位和遊戲結構的對應**

遊戲結構在 `Source/OpenKoikatsu/OKStreetSocialPlaces.h`：
- `FOKStreetPlace`：約第 130 行。
- `FOKStreetModelAnchor`：約第 38 行。
- 寫死的地點表：`OKStreetPlaces()`，約第 290–411 行。

| `places.json` | 遊戲 | 說明 |
|---|---|---|
| `id` | `FOKStreetPlace::Id` | 新地點的 id。沿用舊 id 的對應表見上方「遊戲現有地點和大學城建築的對應」 |
| `name` | `Name`／`ZhName` | 中文名 |
| `door` [x,y,z] cm | `Door` | 抵達點。汽車旅館是真正的入口，室內房間是家具範圍的中心 |
| `room.center/size/yaw`（汽車旅館）或 `room.min/max`（其他室內） | `Rooms`（FBox） | 汽車旅館的房間框要依 `yaw` 轉，`yaw` 只會是 0、90、180、270 |
| `anchors[].name/pos/yaw` | `Anchors{Name, Position, Yaw}` | yaw 規則和遊戲一樣：角色面向 yaw+90。床錨點名是 `bed1_0`，宿舍、公寓是 `bed0_0`、`bed1_0`…，座位 `seat*`、桌子 `table*`、沙發 `sofa*`、SPA 池 `pool*` |
| `privacy` | `places.toml` 的 `privacy` | 2 才能 H（`RequestIntimacy`，`OKStreetSocialInvite.inl` 約第 285 行） |
| `mirrors[]`（汽車旅館） | 不用讀 | 鏡子已經在地圖上，資料只供參考 |
| `kind`、`uses` | 不用讀 | 給人看的分類 |

**要改的地方**

- **地圖路徑**：兩處都寫 `/Game/Scenes/StreetSocial/StreetSocial`，換成 `/Game/UniversityCity/Maps/UniversityCity`。
  - `Tools/run_street_social_development.lua:463`
  - `Source/OpenKoikatsu/OKStreetSocialScene.cpp:4661`（`UOKBuildStreetSocialMapCommandlet::Main`）
- **地點表**：`OKStreetPlaces()` 改成讀 `places.json`（或由它產生）。`.okmesh` 模型（`OKStreetLoadPlaceModel`）在大學城用不到，因為建築已經在地圖上。
- **路線點**：`OKStreetPlaceRoutePoints()`（約第 420 行）。大學城的道路格點可以從 `output/street-social-city-production/world-edge-v1/road-raster.json` 取（2 m 一格，`r` 是路面），也可以直接用各地點的 `door`。
- **附加地面**：`OKStreetPlaceGround()`（約第 453 行）。大學城地面都有碰撞，可以清空。
- **床**：`OKStreetNearestBed`（約第 478 行）找名稱開頭是 `bed` 的錨點、Z 差 150 cm 以內。`places.json` 的床錨點都照這個命名。
- **鏡子**：`StreetSocialCity/Plugins/CityEnvironment/Source/CityEnvironment/Private/CityImmersionWalker.cpp` 第 97–130 行，是「最近兩面鏡子」的邏輯：找 `ImmersionLargeMirror` tag，玩家眼睛同一層、在鏡子前面、22 m 內的最近兩面開啟。遊戲的 Pawn 要做同樣的事。
- **外掛**：
  - 執行期外掛：`StreetSocialCity/Plugins/CityEnvironment`（含 `CityLocalization` 模組）、`StreetSocialCity/Plugins/CityLocalization`。
  - 地圖上有 `CityEnvironmentController`（日夜與天空）。

**資料重建**：見文件開頭（`world_places_probe` → `build_street_city_places.lua`）。

## 攻略確認（c-conquest，11-03）與 `game_places`

攻略（[C組] 街區攻略：十位女主循環）11-03 回覆：

- **格式**：照 `OKStreetSocialPlaces.h` 的格式，`places.json` 可以直接用。
- **Door**：要用真正的入口，因為它是抵達點，也是「店門口 3 m 內仍算在店」的判斷基準。已改：
  - 房間用房門（往房內 60 cm）。
  - 商店用 `entryframe`。
  - 大樓用 `<棟>-entry-A`。
  - `door_kind` 標示是哪一種。
- **錨點名稱**：照遊戲讀的名稱。這些放在 `places.json` 的 `game_places`（下表），每個遊戲 id 都有 `door`、`rooms`、`anchors`。
- **H（privacy 2）**：
  - 開放：汽車旅館 H1 全部、民宿 S18、男宿 D2 的房間、公寓 R1／R2。
  - 女宿 D1 的房間：要她是住戶或由她邀請（`needs_invite`）。
  - 溫泉包場、午睡室：privacy 1，只能接吻、擁抱。
  - 戶外樹叢：不開 H，只當人少的接吻點（privacy 1）。
- **最缺**：便利店內用座位、女宿交誼廳可以兩人打電動的沙發＋電視。已用 `Tools/street_city_lover_spots_payload.lua` 補上，同時補：
  - 地圖上原本沒有的販賣機，共 11 處。
  - 一座小神社（鳥居、石板參道、小祠、賽錢箱、石燈籠），給 `shrine`。
  - 男宿 D2 交誼廳也一樣有沙發＋電視。

| 遊戲 id | 大學城 | privacy | 錨點 | 還缺 |
|---|---|---:|---|---|
| `aquarium` | 錦鯉池 | 0 | tank、bench | vending |
| `bookstore` | S07 街角書局 | 0 | shelf、seat |  |
| `boys_dorm` | D2 男生宿舍B | 2 | lounge、bed3_0 | vending |
| `cafe` | S01 咖啡書屋 | 0 | counter、seat |  |
| `cafeteria` | SC 學生餐廳 | 0 | table | vending |
| `campus_gate` | 校門 | 0 | gate |  |
| `campus_sports` | SP 運動健康館 | 0 | seat、field |  |
| `conveni` | S06 便利商店 | 0 | aisle | seat、table |
| `department` | M1 大學城百貨 | 0 | mirror2、food、beauty、books、phones、shoes、mirror3、sofa、view、bear | vending |
| `drinkshop` | S02 手搖飲店 | 0 | counter、seat |  |
| `fruitshop` | S05 水果店 | 0 | stand |  |
| `girls_dorm` | D1 女生宿舍A | 0 | lounge | vending |
| `hotel` | H1 星澄豪華溫泉飯店 | 1 | lobby、bar、room6、bed6_1、pool | vending |
| `lecture` | T2 第二教學大樓 | 0 | seat |  |
| `library` | LI 借還書服務大廳 | 0 | seat、shelf | vending |
| `lodge` | H1 泳池套房（星澄汽車旅館 203 Swimming Pool Suite1） | 2 | bed2_0、seat、lounge2 | vending |
| `lottery` | S20 星運彩券行 | 0 |  |  |
| `minshuku` | S18 日式民宿 | 2 | seat、bed1_0 |  |
| `onsen` | S19 溫泉會館 | 1 | pool |  |
| `park` | 中央公園 | 0 | fountain、plaza、pond、bench | vending |
| `petshop` | S08 寵物用品店 | 0 | pets |  |
| `playground` | 遊樂場 | 0 | field | vending |
| `restaurant` | S04 家庭餐館 | 0 | table |  |
| `restroom_campus` | SC 學生中心 1F 廁所 | 1 | wait、women |  |
| `restroom_north` | D3 研究生宿舍C 1F 廁所 | 1 | wait、women |  |
| `restroom_park` | CV 市民文化與生活中心 1F 廁所 | 1 | wait、women |  |
| `restroom_resort` | H1 星澄豪華溫泉飯店 1F 廁所 | 1 | wait、women |  |
| `school` | T1 第一教學大樓 | 0 | seat、class2、music | vending |
| `shrine` | 小神社 | 0 |  | torii、pray |
| `snack` | S03 烘焙甜點店 | 0 | counter、table |  |

「還缺」那一欄是新物件裝進地圖、`lover-spots-install-*.json` 寫出來之前的狀態；`build_street_city_places.lua` 重跑後會自動填進去。
