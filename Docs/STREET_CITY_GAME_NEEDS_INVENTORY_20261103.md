# 遊戲需要的地點、店面、景點對照大學城（2026-11-03，c-conquest）

使用者 11-03 要求：c-conquest 和 c-street-city 一起盤點遊戲所有活動、互動需要的地點、店面、景點，缺的補進 `StreetSocialCity`。

**資料來源**

- 遊戲端：
  - 活動表：`Content/IndependentResources/StreetSocialData/rules/activities.toml`（109 項）。
  - 地點規範：`rules/places.toml`。
  - 商店、營業時間、打工站位：`catalog.json` 的 `places`、`items`、`jobs`。
  - 女主住處與工作地點：`Profiles/*.json`。
  - 公司的店面單位與空地：`property.json`。
  - C++ 寫死的地點表與錨點用法：`Source/OpenKoikatsu/OKStreetSocialPlaces.h`、`OKStreetSocialCampus.inl`、`OKStreetSocialOuting.inl`。
  - 規則：`Tools/ok-rules/src/academics.rs`、`errand.rs`、`estate.rs`。
- 城市端：`output/street-social-city-production/places-v1/places.json`（11-03 15:19 版，`game_places` 30 個，`places` 1,107 個）。
- 比對腳本放在 scratchpad，不進版控：
  - `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\73be5e18-f8ea-466d-8357-5af9e42f345e\scratchpad\inv_anchors.lua`
  - `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\73be5e18-f8ea-466d-8357-5af9e42f345e\scratchpad\inv_stations.lua`

## 1. 已經對上的（不用補）

- 活動錨點：活動表 109 項用到的 30 個地點 id 和全部錨點名，`game_places` 都有，0 項缺漏。
- 打工站位：`catalog.json` 32 種打工裡，30 種的站位錨點在城市都找得到。

## 2. 要補進 StreetSocialCity 的（城市端）

| # | 缺什麼 | 遊戲哪裡要用 | 要的錨點／資料 |
|---|---|---|---|
| C1 | 便利商店 S06 沒有收銀台錨點 | 打工 `conveni_clerk` 的站位是 `counter`、`aisle` | `conveni` 加 `counter`（店員站在收銀台後、面向客人） |
| C2 | 彩券行 S20 一個錨點都沒有 | 打工 `lottery_clerk` 站位 `counter`；`places.toml` 寫「牆上有開獎螢幕」 | `lottery` 加 `counter`、客人買彩券的站位（如 `buy`）、開獎螢幕（實體＋錨點 `screen`，供看開獎） |
| C3 | 9 棟上課大樓不在 `game_places`；T1、T2、RB、IB、T4、E1、MA、EE 在 `places.json` 也沒有教室資料 | 課表（`academics.rs`）每門課是「館舍＋樓層 2–5＋教室 1–4」，例如 `campus_t1` 3 樓 2 號教室 | 每棟一個 `game_places`：`campus_t1`、`campus_rb`、`campus_ib`、`campus_t4`、`campus_e1`、`campus_ma`、`campus_t2`、`campus_ee`、`campus_ad`。每棟要：<br>• `door`、`rooms`（每層一個框，遊戲用 `RoomLevels` 分樓層）<br>• 每層樓梯口 `stair1`…`stair5`（`StairHere`／`TakeStairs` 靠它上下樓）<br>• 2–5 樓每間教室的學生座位與講台（命名待定，建議 `class<樓><間>_seat<n>`、`class<樓><間>_board`） |
| C4 | 系辦、行政窗口沒有遊戲錨點 | 系辦（`campus_office`，C++ 找 260 cm 內的 `office_<系代號>`，例如 `office_csie`）；學務處辦助學貸款、繳學費（`errand.rs` 只認 `campus_ad`） | 21 個系各一個 `office_<系代號>` 櫃台錨點，放在所屬學院的館舍，代號照 `academics.rs` 的 `DEPTS`；`campus_ad` 的服務櫃台（AD `ad-0101` 已有 `counter0_0`）也要列進 `game_places`。ACTSPACE-08 的窗口實體已經放好了，只缺遊戲錨點 |
| C5 | 多樓層地點沒有 `lift*`、`hall` 錨點 | `OKStreetPlaceLifts` 依名稱開頭是 `lift` 的錨點排出每層樓，`hall` 是大廳進電梯的路點（`OKStreetSocialOuting.inl`）。要用到的有：<br>• 百貨 9 樓美食街、10 樓景觀餐廳（活動有 `floor = 9/10`）<br>• 飯店 6 樓 `room6`、`bed6_1`<br>• 舊校舍 2 樓 `class2`、3 樓 `music`<br>• 女宿「電梯在 1F 交誼廳」<br>• 男宿 3 樓 `bed3_0` | `department`、`hotel`、`school`、`girls_dorm`、`boys_dorm` 每層一個 `lift<n>`（電梯門口，Z 是那層的地板高度），加一個 `hall` |
| C6 | 10 個活動場景（ACTSPACE-01…10）沒有錨點 | 夜市、海灣步道、煙火觀賞台、錦鯉池、晨練慢跑、行政窗口、繪本區、表演空地都已經擺好道具，但 `places.json` 的 `anchors` 是空的，遊戲沒辦法讓人站或坐在那裡 | 每個場景加遊戲錨點：<br>• 座位 `seat*`、站位 `stand*`<br>• 攤位 `stall*`（夜市）<br>• 觀景點 `view`（步道、觀賞台）<br>• 池邊 `pond`（錦鯉池）<br>• 晨練 `field`、慢跑環線起點 `jog`<br>• 舞台 `stage`、觀眾 `watch*`<br>• 看煙火的遠方效果錨點 `fireworks`（ACTSPACE-05 已預留） |
| C7 | 沒有 Live House | 一位女主的工作是 `livehouse_staff`，但工作地點只能寫 `cafe`；女主唱歌（`sing`）也只能在公共地點 | 一間小型 Live House：室內舞台、吧台、站位觀眾區；錨點 `stage`、`bar`、`watch*`、`counter`（店員站位） |
| C8 | 沒有 KTV 包廂 | 女主唱歌給他聽（`places.toml [acts] sing`，人多會害羞）；目前沒有能關起門唱歌的地方 | 3–6 間 KTV 包廂：沙發、螢幕、麥克風；`seat*`、`screen`，privacy 1（可上鎖但有店員） |
| C9 | 公司的空地座標是舊地圖的 | `property.json` 的 8 塊 `lot_*` 中心點在 ±7000 cm 內，大學城的街區在 18000–100000 cm，對不上 | 在大學城找 8 塊臨路空地（約 14×11 m），輸出 `center`、`size`、`yaw` 與臨路的那一側，給 `-StreetSocialFindLots` 或直接改 `property.json` |
| C10 | 公司辦公室單位沒有實際房間 | `property.json`：<br>• `dept_office` 百貨辦公樓層<br>• `hotel_business` 飯店商務辦公室<br>• `lodge_office` 會館小辦公室<br>• `school_club` 舊校舍社團教室 | M1 一層辦公樓層（11-03 盤點：M1 沒有家具實例）、H1 一間商務辦公室、舊校舍一間社團教室；錨點 `desk*`、`seat*` |
| C11 | 女主自己的房間沒有分配 | 十位女主都住 `girls_dorm`（`home_place_id`）；`sleep`、`bath` 作息和「到她房間」（`needs_invite`）要知道是哪一間 | D1 有 52 間房、208 張床。給一份 D1 房間清單（房號、樓層、床與淋浴錨點），遊戲依女主固定分配。這只是資料，不用改場景 |

## 3. 城市已經有、遊戲還沒有的（遊戲端，整合時做）

以下城市已經建好，但遊戲沒有地點 id、活動或商店資料。這些屬於規則與 C++，在整合時由我（c-conquest）補，不是 c-street-city 的工作。

- **店面**（S21–S96 已有店面樓層）：
  - 花店（送花）、服飾、髮廊、唱片行、桌遊店、相館、單車行、藥妝、自助洗衣。
  - 二手書店、第二家便利店與彩券社可以當分店。
  - 遊戲要補：`places.toml` 規範、`catalog.json` 商品與營業時間、必要時加打工。
- **景點**：
  - 海灘躺椅 84、燈塔、涼亭 2（躲雨、接吻）、鐘塔（約見面）、舞台。
  - 野餐桌 40、戶外咖啡座 16、遊樂設施 4、樹叢 22（人少的接吻點）。
  - 遊戲要補：地點 id 與活動，例如：
    - 海邊看日落、一起躺海灘椅
    - 燈塔看海
    - 涼亭躲雨
    - 鐘塔下等人
    - 野餐
  - 貞德、胡桃說過想去看海（`Docs/STREET_MISSING_ACTIVITIES.md`）。
- **活動場景**（城市端補上 C6 的錨點後）：
  - 夜市逛攤、吃小吃（刻晴、胡桃）
  - 河岸看煙火（惠惠的約定）
  - 錦鯉池餵魚（目前 `park_feed_fish` 用公園 `pond`）
  - 晨練、慢跑（目前在公園 `plaza`、`fountain`）
  - 繪本區（安可找繪本）
  - 表演空地看表演
- **住宿**：
  - 汽車旅館 58 間、公寓 80 間、午睡室 6 間。
  - 遊戲要在 `places.toml` 加 privacy 2／1 的類別（11-03 盤點的「換地圖」第 4 步）。

## 5. 換地圖時遊戲需要地圖提供的東西（逐項給 c-street-city 回答有／沒有／名稱不同）

C++ 的地點結構是 `FOKStreetPlace{Id, Door, Rooms, RoomLevels, Anchors{Name, Position, Yaw}}`（`OKStreetSocialPlaces.h`）。錨點只認名字，不認 actor tag。

| # | 項目 | 遊戲用的名稱／判斷方式 | 問 c-street-city |
|---|---|---|---|
| Q1 | 地點 id（30 個＋C3 的 9 棟） | 第 1 節的 30 個 id 加 `campus_*`；`OKStreetFindPlace(id)` | 已有 30 個；9 棟待補 |
| Q2 | 門 `Door` | 抵達點；離門 3 m 內仍算在店裡；營業時間外會被請離開（`catalog.json places.open`） | 每個 game_place 的 `door` 都是真正的入口嗎？招牌上的營業時間要和 `catalog.json` 一致（例：圖書館週一公休、8–21） |
| Q3 | 所在範圍 `Rooms`／`RoomLevels` | 判斷「現在在哪個地點、哪一樓」；多樓層地點每層一個框 | 多樓層地點有沒有每層分開的框？ |
| Q4 | 上下樓 | `lift<n>`（電梯，`OKStreetPlaceLifts`）、`hall`（大廳路點）、校舍用 `stair<n>`（`StairHere` 在 170 cm、Z 差 100 cm 內） | C5、C3 |
| Q5 | NPC 與帶路的路線 | 舊地圖用寫死的路線點 `OKStreetPlaceRoutePoints()`（約第 420 行），沒有用 NavMesh；附加地面 `OKStreetPlaceGround()` | 城市有 NavMesh 嗎？有的話整合時改用它；沒有的話請由 `world-edge-v1/road-raster.json` 產生路線點（各門口要接到路網） |
| Q6 | 共同活動錨點 | 第 1 節全部對上（`table`、`counter`、`seat`、`shelf`、`pets`、`lounge`、`game`、`bed*_*`、`vending`、`fountain`、`pond`、`plaza`、`bench`、`torii`、`pray`、`gate`、`field`、`tank`、`beauty`、`mirror2/3`、`shoes`、`sofa`、`books`、`phones`、`bear`、`food`、`view`、`pool`、`bar`、`lobby`、`room6`、`lounge2`、`class2`、`music`、`stand`、`aisle`、`wait`、`women`） | 已有 |
| Q7 | 拍照點 | 活動 kind=photo：`park_photo` fountain、`campus_gate_photo` gate、`shrine_photo` torii、`pet_photo` pets、`school_music` music、`dept_beauty/women/men/bear`、`aquarium_photo` tank；照片要拍得到主題物（舊地圖出過「噴水池前合照卻看不到噴水池」，R3-46 大熊不在場） | 每個拍照錨點的鏡頭方向（yaw+90 的反方向）背景裡有主題物嗎？ |
| Q8 | 打工站位 | `catalog.json jobs[].stations`：`counter`、`aisle`、`seat`、`table`、`stand`、`shelf`、`pets`、`beauty`、`mirror2/3`、`shoes`、`sofa`、`books`、`phones`、`bear`、`food`、`view`、`tank`、`lobby`、`bar`、`pool` | 只缺 C1、C2 |
| Q9 | 購物點 | 進入有營業的地點就能開菜單買（`catalog.json items[].place`），19 個地點有商品 | 已有；店內要看得出賣什麼（貨架、菜單看板） |
| Q10 | 一對一、H 用的房間 | `places.toml` privacy ≥ 2 才能 H（`RequestIntimacy`）：`lodge`、`minshuku`、`boys_dorm`；hotel 帶去 `hotel_rest`。H 場景自己生床，不讀場景道具。接吻、擁抱看 privacy 與人數 | 旅館房、民宿、男宿房間已列；整合時 `places.toml` 加 `motel_*`、公寓等類別（第 3 節） |
| Q11 | 「進設施」類活動 | kind=facility：`restaurant_room`（餐廳包廂）、`hotel_spa`、`hotel_rest`、`inn_rest`、`rest`（會館休息房）、`spa`（會館精油護理室）。舊地圖是兩人淡出進房 | S04 有包廂嗎？H1 有 SPA 護理室嗎？`lodge` 現在對到汽車旅館泳池套房，「會館精油護理室」對不上 |
| Q12 | 睡覺 | `sleep_*` 活動找名稱開頭 `bed` 的錨點（`OKStreetNearestBed`，Z 差 150 cm 內）；女主 `sleep`／`bath` 作息回她的 `home_place_id`（都是 `girls_dorm`） | C11：女宿房間清單（床、淋浴 `shower*`） |
| Q13 | 洗澡 | 女主 `bath` 作息在自己宿舍；一起泡澡用 `onsen` 的 `pool`、飯店 `pool` | S19 的 `pool*` 已有；女宿房間的 `shower*` 已有，要和 C11 一起分配 |
| Q14 | 廁所 | `restroom_*` 的 `wait`（他等的位置）、`women`（女廁） | 已有 4 處 |
| Q15 | 販賣機 | `vending`（12 個地點） | 已有 |
| Q16 | 出生點 | 新遊戲他在男宿門口，女主在各自作息的地點；讀檔用存下的座標 | D2 男宿門口的出生點（站在路上、不卡牆）；舊存檔的座標在新地圖無效，整合時要把存檔座標換成「地點 id＋錨點」 |
| Q17 | 地點描述 | `places.toml` 的 label 與 C++ 的地點說明會給 AI 看（例：「舊校舍，社團活動和自習用」「露天溫泉，竹籬笆圍著」「水族館，展區禁止飲食」） | 名稱對上但內容不同的要列出來，整合時改描述：`aquarium`→錦鯉池、`onsen`→室內溫泉會館、`playground`（操場：草地與跑道，打西瓜、潑水、跑步、爆裂魔法）→遊樂場、`school`→第一教學大樓、`lodge`→汽車旅館套房 |

## 6. c-street-city 回覆後的比對（11-03 19:00 版 places.json）

c-street-city 的逐項回答在 `Docs/STREET_CITY_PLACES_INVENTORY_20261103.md` 的「c-conquest 清單逐項回答」一節。比對腳本：

- `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\73be5e18-f8ea-466d-8357-5af9e42f345e\scratchpad\inv_anchors.lua`
- `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\73be5e18-f8ea-466d-8357-5af9e42f345e\scratchpad\inv_stations.lua`
- `C:\Users\Damody\AppData\Local\Temp\claude\C--portable-OpenKoikatsu\73be5e18-f8ea-466d-8357-5af9e42f345e\scratchpad\inv_verify.lua`

**已確認**

- 活動表 109 項的地點與錨點：全部對上（重跑後不變）。
- C3：9 棟 `campus_*` 都有 `door`、5 層框、`stair1`–`stair5`、`lift1`–`lift5`、`hall`。
  - 8 棟上課館舍的 `class2_1`…`class5_4` 16 間都有；`campus_ad` 沒有教室（行政大樓，正常）。
  - 教室名稱 `classK_R` 就是 `OKStreetSocialSchedule.inl` 讀的名稱（`Kind.StartsWith("class")` 時找同名錨點）。
- C4：21 個系的 `office_<系代號>` 全有，另有 `office_registrar`、`office_aa`、`office_student`（`campus_ad`）、`office_general`（`campus_t1`）。
- C5：`department` 10 層、`hotel` 5 層、`school`、`lecture` 各 5 層、兩棟宿舍各 6 層，都有依高度排好的 `lift<n>:<n>F` 和 `hall`。名稱開頭是 `lift`，`OKStreetPlaceLifts` 讀得到。
  - 百貨 `food` 在 9 樓高度、`view` 在 10 樓高度，和活動的 `floor = 9/10` 一致。
- C6：ACTSPACE-02…10 都有錨點：
  - 夜市 `stall`…`stall12`
  - 煙火台 `seat*`、`gate*`、`fireworks`
  - 錦鯉池 `pond`…`pond4`
  - 晨練 `field`、`jog`
  - 表演 `stage`、`watch*`
  - 01 的大熊已經是百貨的 `bear`，沒有另外的錨點，正常。
- C11：`girls_dorm_rooms` 52 間；`girls_dorm` 另有 16 個 `bed*` 錨點。
- Q16：`boys_dorm` 有 `spawn`。

**還沒好**

- C1、C2、C7、C8、C9：chain16 裝好後再比對，都已對上（11-03 晚）。
  - `conveni` 有 `counter`；`lottery` 有 `counter`、`buy`、`screen`。打工站位全部對上。
  - `livehouse`（S96）有 `stage`、`watch`…`watch4`、`bar`、`counter`。
  - `karaoke`（S48，privacy 1）有 3 間包廂的 `seat*`、`screen*`。
  - `lots` 8 塊。編號是 `lot_1`…`lot_8`，和 `property.json` 的 `lot_02`…`lot_12` 不同，整合時要對應或改名。
- C10：`places.json` 頂層的 `office_units`（以單位 id 為鍵的物件）已有 4 個單位，都有房間、`door`、`desk*`：
  - `dept_office`：O01-0201，3 張桌。
  - `hotel_business`：H1-0107，8 張桌。
  - `lodge_office`：O01-0102，3 張桌。
  - `school_club`：SC-0202，2 張桌。
  - 沒有分開的椅子，所以沒有 `seat*`。

**錨點高度和活動名稱的樓層對不上**

| 活動 | 名稱寫的樓層 | 錨點實際高度 | 誰處理 |
|---|---|---|---|
| `school_class2`（學校二樓教室） | 2 樓 | 原本 z=1248（1 樓） | 已修：移到 T1-0201，z=1648（2 樓） |
| `sleep_dorm`（男宿三樓寢室） | 3 樓 | 原本 z=1200（1 樓） | 已修：移到 D2-0301 的床，z=1980（3 樓） |
| `hotel_room6`、`sleep_hotel`（飯店六樓景觀客房） | 6 樓 | `room6` z=1871、`bed6_1` z=1761，是 2 樓；H1 只有 5 層 | 整合時改活動名稱（H1 沒有 6 樓） |

**整合時要處理的（c-street-city 回答，不改 C++，記在這裡）**

- C10 辦公室：
  - `hotel_business` → H1-0107 商務會議室；`school_club` → SC-0202 社團聯合辦公室。
  - M1 沒有辦公樓層、會館沒有辦公室，`dept_office`、`lodge_office` 改指 AD 或 IN 的辦公室。
  - 這些房間還沒有 `desk*`、`seat*` 錨點。
- Q5 導航：城市沒有 NavMesh。`OKStreetPlaceRoutePoints()` 要改成從 `world-edge-v1/road-raster.json` 產生。
- Q11 設施：
  - `restaurant_room` 改指 M1-1008 慶祝包廂餐廳或 H1-0106 私人宴會廳（S04 沒有包廂）。
  - `hotel_spa`、`spa` 改指 H1-0203 精油護理室；另有 H1-0202 私人雙人湯屋。
  - `rest` 改指 H1-0208 靜音午睡沙龍。
- Q17 描述：
  - `aquarium` 是 S28 改建的小水族館（有水槽、長椅），錦鯉池是 ACTSPACE-06，第 5 節寫錯，以這裡為準。
  - `playground` 的活動（打西瓜、潑水、跑步、爆裂魔法）需要草地與跑道，城市的遊樂場沒有。整合時改指 `campus_sports` 的 `field`（跑道操場）。
  - 另外要改描述的地點：
    - `onsen`：S19 室內溫泉會館。
    - `school`：T1。
    - `lodge`：汽車旅館泳池套房。
    - `lecture`：T2，沒有紅磚鐘塔。
    - `restroom_*`：在大樓 1 樓。
    - `shrine`：在公園旁的石板廣場。
- Q7 拍照點的背景：c-street-city 下一輪補拍照確認。

## 7. 婦科診所、醫美診所、美髮店（使用者 11-03 新增）

使用者要的三個設施：
- 婦科小診所：做處女膜重建手術。
- 醫美診所：把臉型換成別人的臉型。
- 美髮店：染頭髮。

**城市端（已請 c-street-city 補，編號接 C12–C14）**

| # | game id | 錨點 |
|---|---|---|
| C12 | `clinic_gyn` | `counter`、`seat*`、`doctor`、`bed_op`、`rest*`、`wait`；privacy 1 |
| C13 | `clinic_beauty` | `counter`、`consult`、`bed_op`、`rest*`、`wait`、`seat*`、`mirror`；privacy 1 |
| C14 | `salon` | `chair*`、`wash`、`seat*`、`counter`、`swatch`；建議用現有的 S31 造型髮廊 |

**遊戲端（已做）**

- 規則：`Tools/ok-rules/src/clinic.rs`
  - `clinic_treat`：`kind` 是 `hymen_restore`、`face_swap`、`face_restore`、`hair_dye`。
  - `appearance_of`、`hair_colors`（12 色）。
  - 處女膜重建記在她的 `hexp.hymen_restored`（`hexp.rs`）：
    - 下一次被插入時，H 場景照第一次演出，流血不管卡片的「已撐開」設定。
    - 之後恢復成已破，她的記憶是「重建的處女膜又被弄破」，不是「失去第一次」。
    - 還是處女、處女膜會再生、已經重建過的，都不能做。
  - 臉型與髮色記在 `ext.appearance.<她的 id>`。
- 卡片：`Tools/ok-extract` 的 `AppearanceRequest` 新增 action `restyle`。
  - 把對方卡的 `face.shapeValueFace.*` 複製到她卡的副本（頭型與其他外觀不變）。
  - 頭髮每一段的 base／start／end／outline 顏色換成新色，保留透明度。
  - 副本放在 `Saved/StreetSocial/Appearance/`。
- 商品：`catalog.json` 的 `clinic` 類。
  - 處女膜重建 ¥4,800、換臉 ¥68,000、臉型還原 ¥38,000、染髮 ¥398。
  - 營業時間：婦科 9–18（週日休）、醫美 10–20、美髮 10–21（週二休）。
- 地點：舊地圖暫時加了三棟能走進去的方塊建築（`OKStreetSocialPlaces.h` 的 `OKStreetWalkInBuilding`）。
  - 婦科在度假區公廁旁 (500,-4300)。
  - 醫美在飯店東側 (2800,-5300)。
  - 美髮在咖啡廳和學生餐廳之間 (3550,4100)。
  - 換成大學城後改用 C12–C14。
- 流程（`OKStreetSocialClinic.inl`）：
  1. 帶她到店裡開菜單。換臉要選「誰的臉型」，染髮要選顏色。
  2. 按鈕會問她要不要。她用自己的話答應或拒絕（choice，和送禮一樣），答應了才付錢、才做。
  3. 做完會告訴她發生了什麼（`game_fact_note`），她也會記得。

**限制**

- 她的新臉型與髮色：
  - 一對一與 H 場景開她時馬上用新卡。
  - 街上的群眾模型要等下次開遊戲才換：群眾的角色一次載入、共用 GPU bank，沒有單人重載。
- 街上即時換色另外要做兩件事：群眾材質裡頭髮的參數分類，以及不和別人共用的材質實體。

## 8. 下一步

1. c-street-city 依第 2 節（C1–C11）補場景與 `places.json`，重跑 `build_street_city_places.lua`。
2. c-conquest 重跑比對腳本確認沒有缺漏。
3. 第 3 節等使用者整合大學城時，由 c-conquest 補規則與活動。
