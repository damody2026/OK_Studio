# 樓上沒有樓梯的地點（導出器產生，勿手改）

`Tools/export_street_city_game_places.lua` 產生，規則在 `Tools/street_city_upstairs_off.lua`（與 `Tools/build_street_city_places.lua` 共用，city_anchors.json 的同一批列一起標）：一樓有門、整個地點沒有任何 lift／stair 錨點時，門以上 2.5 m 的錨點改名為 `off_<原名>` 並加上 `"off"`，女主排程選不到它們（2026-11-15 止血）。補上樓梯錨點並實測「從 1F 走到該樓層座位再走回店門」之後，從這份清單拿掉。

「真樓層」：錨點比門高 3 m 以上（一層 3.8 m，樓層由 room 或高度推得）；「高處物件」：比門高 2.5–3 m（不必補樓梯，標不可用即結案）。school 是校舍、經 campus_t1 的電梯上樓，不在此列。排序：排程與邀約常去的店在前。

「規則錨點數」：city_anchors.json 裡同一地點同一樓層被標掉的列（清空 kinds、加 tag `off`），含員工間、廁所等只在規則表裡的錨點。

| 地點 | 樓層 | 類別 | 錨點數 | 規則錨點數 | 錨點 |
|---|---:|---|---:|---:|---|
| cafe | 2 | 真樓層 | 16 | 23 | seat4 seat5 seat10 seat11 seat12 seat13 seat15 seat16 seat20 seat21 seat26 seat27 seat28 seat29 seat32 seat33 |
| cafe | 3 | 真樓層 | 2 | 5 | seat17 seat34 |
| restaurant | 2 | 真樓層 | 16 | 18 | seat4 seat8 seat9 seat13 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat25 seat28 seat29 seat30 seat32 |
| restaurant | 3 | 真樓層 | 2 | 6 | seat5 seat34 |
| conveni | 2 | 真樓層 | 5 | 7 | seat table seat4 seat5 seat6 |
| conveni | 3 | 真樓層 | 2 | 6 | seat2 seat3 |
| fastfood | 2 | 真樓層 | 16 | 18 | seat8 seat11 seat12 seat16 seat21 seat22 seat23 seat24 seat25 seat26 seat27 seat28 seat31 seat32 seat33 seat35 |
| izakaya | 2 | 真樓層 | 16 | 18 | seat4 seat7 seat8 seat12 seat17 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat27 seat28 seat29 seat31 |
| karaoke | 2 | 真樓層 | 5 | 6 | seat4 seat6 seat8 seat9 seat10 |
| karaoke | 3 | 真樓層 | 0 | 1 |  |
| manga_cafe | 2 | 真樓層 | 7 | 8 | seat seat2 seat3 seat4 seat5 seat6 seat7 |
| manga_cafe | 3 | 真樓層 | 0 | 1 |  |
| onsen | 2 | 真樓層 | 11 | 17 | seat19 seat22 seat24 seat25 seat27 seat30 seat32 seat33 seat35 seat38 seat40 |
| onsen | 3 | 真樓層 | 18 | 33 | seat seat2 seat3 seat4 seat5 seat6 seat7 seat8 seat9 seat10 seat11 seat12 seat13 seat14 seat15 seat16 seat17 seat18 |
| bike_shop | - | 高處物件 | 0 | 2 |  |
| bike_shop | 2 | 真樓層 | 0 | 12 |  |
| bookstore | 2 | 真樓層 | 4 | 8 | seat seat2 seat4 seat5 |
| bookstore | 3 | 真樓層 | 2 | 6 | seat3 seat7 |
| bowling | 2 | 真樓層 | 12 | 13 | seat4 seat5 seat6 seat8 seat11 seat12 seat14 seat15 seat17 seat18 seat21 seat22 |
| breakfast | 2 | 真樓層 | 0 | 1 |  |
| bridal | 2 | 真樓層 | 7 | 8 | seat3 seat4 seat5 seat6 seat7 seat8 seat9 |
| bridal | 3 | 真樓層 | 0 | 1 |  |
| cat_cafe | 2 | 真樓層 | 4 | 9 | seat4 seat7 seat8 seat10 |
| clinic_beauty | 2 | 真樓層 | 3 | 5 | seat3 seat4 seat5 |
| clinic_beauty | 3 | 真樓層 | 0 | 2 |  |
| clothing_s10 | 2 | 真樓層 | 0 | 1 |  |
| clothing_s30 | 2 | 真樓層 | 3 | 4 | seat3 seat4 seat5 |
| clothing_s30 | 3 | 真樓層 | 0 | 1 |  |
| clothing_s46 | 2 | 真樓層 | 0 | 1 |  |
| clothing_s94 | 2 | 真樓層 | 0 | 1 |  |
| craft | 2 | 真樓層 | 4 | 8 | seat7 seat8 seat9 seat10 |
| crepe | 2 | 真樓層 | 0 | 1 |  |
| district_office | 2 | 真樓層 | 12 | 13 | seat5 seat7 seat9 seat10 seat12 seat14 seat15 seat18 seat19 seat20 seat22 seat24 |
| drinkshop | 2 | 真樓層 | 0 | 2 |  |
| drinkshop | 3 | 真樓層 | 2 | 4 | seat seat2 |
| fortune | 2 | 真樓層 | 0 | 1 |  |
| fruitshop | 2 | 真樓層 | 0 | 1 |  |
| fruitshop | 3 | 真樓層 | 2 | 6 | seat seat2 |
| livehouse | 2 | 真樓層 | 5 | 6 | seat seat3 seat5 seat6 seat7 |
| livehouse | 3 | 真樓層 | 0 | 2 |  |
| lottery | 2 | 真樓層 | 2 | 4 | seat seat5 |
| lottery | 3 | 真樓層 | 2 | 6 | seat3 seat6 |
| nail | 2 | 真樓層 | 4 | 5 | seat6 seat8 seat10 seat12 |
| nursery | 2 | 真樓層 | 4 | 5 | seat5 seat6 seat7 seat8 |
| petshop | 2 | 真樓層 | 0 | 1 |  |
| petshop | 3 | 真樓層 | 2 | 6 | seat seat2 |
| photo_studio | 2 | 真樓層 | 0 | 1 |  |
| police | 2 | 真樓層 | 2 | 4 | seat4 seat5 |
| realty | 2 | 真樓層 | 0 | 1 |  |
| salon | 2 | 真樓層 | 7 | 8 | seat3 seat4 seat6 seat8 seat9 seat11 seat12 |
| salon | 3 | 真樓層 | 0 | 2 |  |
| snack | 2 | 真樓層 | 0 | 1 |  |
| snack | 3 | 真樓層 | 2 | 6 | seat3 seat4 |
| supermarket | 2 | 真樓層 | 0 | 2 |  |
| sushi | 2 | 真樓層 | 16 | 18 | seat4 seat7 seat8 seat12 seat17 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat27 seat28 seat29 seat31 |
| swimwear | 2 | 真樓層 | 0 | 1 |  |
| yakiniku | 2 | 真樓層 | 16 | 18 | seat4 seat7 seat8 seat12 seat17 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat27 seat28 seat29 seat31 |
| yukata | 2 | 真樓層 | 0 | 1 |  |

共 58 個地點樓層、233 個錨點。
