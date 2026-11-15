# 樓上沒有樓梯的地點（導出器產生，勿手改）

`Tools/export_street_city_game_places.lua` 產生：一樓有門、整個地點沒有任何 lift／stair 錨點時，門以上 2.5 m 的錨點改名為 `off_<原名>` 並加上 `"off"`，女主排程選不到它們（2026-11-15 止血）。補上樓梯錨點並實測「從 1F 走到該樓層座位再走回店門」之後，從這份清單拿掉。

「真樓層」：錨點比門高 3 m 以上（一層 3.8 m，樓層由 room 或高度推得）；「高處物件」：比門高 2.5–3 m（不必補樓梯，標不可用即結案）。school 是校舍、經 campus_t1 的電梯上樓，不在此列。排序：排程與邀約常去的店在前。

| 地點 | 樓層 | 類別 | 錨點數 | 錨點 |
|---|---:|---|---:|---|
| cafe | 2 | 真樓層 | 16 | seat4 seat5 seat10 seat11 seat12 seat13 seat15 seat16 seat20 seat21 seat26 seat27 seat28 seat29 seat32 seat33 |
| cafe | 3 | 真樓層 | 2 | seat17 seat34 |
| restaurant | 2 | 真樓層 | 16 | seat4 seat8 seat9 seat13 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat25 seat28 seat29 seat30 seat32 |
| restaurant | 3 | 真樓層 | 2 | seat5 seat34 |
| conveni | 2 | 真樓層 | 5 | seat table seat4 seat5 seat6 |
| conveni | 3 | 真樓層 | 2 | seat2 seat3 |
| fastfood | 2 | 真樓層 | 16 | seat8 seat11 seat12 seat16 seat21 seat22 seat23 seat24 seat25 seat26 seat27 seat28 seat31 seat32 seat33 seat35 |
| izakaya | 2 | 真樓層 | 16 | seat4 seat7 seat8 seat12 seat17 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat27 seat28 seat29 seat31 |
| karaoke | 2 | 真樓層 | 5 | seat4 seat6 seat8 seat9 seat10 |
| manga_cafe | 2 | 真樓層 | 7 | seat seat2 seat3 seat4 seat5 seat6 seat7 |
| onsen | 2 | 真樓層 | 11 | seat19 seat22 seat24 seat25 seat27 seat30 seat32 seat33 seat35 seat38 seat40 |
| onsen | 3 | 真樓層 | 18 | seat seat2 seat3 seat4 seat5 seat6 seat7 seat8 seat9 seat10 seat11 seat12 seat13 seat14 seat15 seat16 seat17 seat18 |
| bookstore | 2 | 真樓層 | 4 | seat seat2 seat4 seat5 |
| bookstore | 3 | 真樓層 | 2 | seat3 seat7 |
| bowling | 2 | 真樓層 | 12 | seat4 seat5 seat6 seat8 seat11 seat12 seat14 seat15 seat17 seat18 seat21 seat22 |
| bridal | 2 | 真樓層 | 7 | seat3 seat4 seat5 seat6 seat7 seat8 seat9 |
| cat_cafe | 2 | 真樓層 | 4 | seat4 seat7 seat8 seat10 |
| clinic_beauty | 2 | 真樓層 | 3 | seat3 seat4 seat5 |
| clothing_s30 | 2 | 真樓層 | 3 | seat3 seat4 seat5 |
| craft | 2 | 真樓層 | 4 | seat7 seat8 seat9 seat10 |
| district_office | 2 | 真樓層 | 12 | seat5 seat7 seat9 seat10 seat12 seat14 seat15 seat18 seat19 seat20 seat22 seat24 |
| drinkshop | 3 | 真樓層 | 2 | seat seat2 |
| fruitshop | 3 | 真樓層 | 2 | seat seat2 |
| livehouse | 2 | 真樓層 | 5 | seat seat3 seat5 seat6 seat7 |
| lottery | 2 | 真樓層 | 2 | seat seat5 |
| lottery | 3 | 真樓層 | 2 | seat3 seat6 |
| nail | 2 | 真樓層 | 4 | seat6 seat8 seat10 seat12 |
| nursery | 2 | 真樓層 | 4 | seat5 seat6 seat7 seat8 |
| petshop | 3 | 真樓層 | 2 | seat seat2 |
| police | 2 | 真樓層 | 2 | seat4 seat5 |
| salon | 2 | 真樓層 | 7 | seat3 seat4 seat6 seat8 seat9 seat11 seat12 |
| snack | 3 | 真樓層 | 2 | seat3 seat4 |
| sushi | 2 | 真樓層 | 16 | seat4 seat7 seat8 seat12 seat17 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat27 seat28 seat29 seat31 |
| yakiniku | 2 | 真樓層 | 16 | seat4 seat7 seat8 seat12 seat17 seat18 seat19 seat20 seat21 seat22 seat23 seat24 seat27 seat28 seat29 seat31 |

共 34 個地點樓層、233 個錨點。
