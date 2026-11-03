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

## 4. 下一步

1. c-street-city 依第 2 節（C1–C11）補場景與 `places.json`，重跑 `build_street_city_places.lua`。
2. c-conquest 重跑比對腳本確認沒有缺漏。
3. 第 3 節等使用者整合大學城時，由 c-conquest 補規則與活動。
