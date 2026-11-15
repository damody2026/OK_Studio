# 樓上沒有樓梯的地點（導出器產生，勿手改）

`Tools/export_street_city_game_places.lua` 產生，規則在 `Tools/street_city_upstairs_off.lua`（與 `Tools/build_street_city_places.lua` 共用，city_anchors.json 的同一批列一起標）：一樓有門、整個地點沒有任何 lift／stair 錨點時，門以上 2.5 m 的錨點改名為 `off_<原名>` 並加上 `"off"`，女主排程選不到它們（2026-11-15 止血）。補上樓梯錨點並實測「從 1F 走到該樓層座位再走回店門」之後，從這份清單拿掉。

「真樓層」：錨點比門高 3 m 以上（一層 3.8 m，樓層由 room 或高度推得）；「高處物件」：比門高 2.5–3 m（不必補樓梯，標不可用即結案）。school 是校舍、經 campus_t1 的電梯上樓，不在此列。排序：排程與邀約常去的店在前。

「規則錨點數」：city_anchors.json 裡同一地點同一樓層被標掉的列（清空 kinds、加 tag `off`），含員工間、廁所等只在規則表裡的錨點。

| 地點 | 樓層 | 類別 | 錨點數 | 規則錨點數 | 錨點 |
|---|---:|---|---:|---:|---|
| bike_shop | - | 高處物件 | 0 | 2 |  |
| bike_shop | 2 | 真樓層 | 0 | 12 |  |
| crepe | 2 | 真樓層 | 0 | 1 |  |
| nail | 2 | 真樓層 | 4 | 5 | seat6 seat8 seat10 seat12 |
| photo_studio | 2 | 真樓層 | 0 | 1 |  |

共 5 個地點樓層、4 個錨點。
