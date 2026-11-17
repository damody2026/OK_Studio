# 大學城地點與錨點可達性（自動產生）

由 `Tools/street_city_reach_check.lua report` 產生：在來源地圖上照遊戲的 NavCellFree 逐格判定（40 cm 格點、半徑 40／30 膠囊、WorldStatic 簡單碰撞、相鄰格高差 40 cm 以內），1 樓從門口、樓上從電梯平台與樓梯錨點灌水。只是線索：可不可以走以遊戲裡實際走為準。

**改動地圖後必跑（安裝家具、切牆、搬道具之後，進遊戲之前）**：`Tools\lua\lua.exe Tools\street_city_reach_check.lua scan`（或只重掃改動處的批次），再 `... gate`。`Tools/build_street_city_stream.lua`（WP 轉換）第一步就跑 gate，沒過不轉換。判準：來源地圖在最新一批掃描之後又存過 → 不過（要重掃）；門被擋、樓層沒有入口、門到不了街上、錨點下沒有地板、錨點周圍沒有可走格、錨點在封死的格子，這六類任一類筆數比已提交的本文件多 → 不過，並列出新增的列。站位在家具裡不擋（遊戲會改站附近走得到的點）。要略過只能 `--skip-reach-gate <原因>`，原因寫進該輪回報。

檢查 113 個地點、9596 個錨點；未掃到的區塊 0 個。

## 站位在家具或牆裡：遊戲會改用 1.6 m 內走得到的點（不擋路，只是站位不準）（5156）

各地點筆數（每一筆在 output/street-social-city-production/places-v1/reach-report.json）：girls_dorm 1155、boys_dorm 1140、campus_ib 274、campus_ma 274、campus_rb 274、campus_t4 274、campus_t1 262、campus_t2 262、campus_ee 261、park 85、cafeteria 83、civic 66、library 60、campus_sports 52、beach 44、onsen 36、restaurant 36、cafe 33、izakaya 31、sushi 29、station 28、clinic_general 19、campus_e1 18、district_office 18、clinic_gyn 17、craft 16、manga_cafe 15、bookstore 14、cat_cafe 14、conveni 13、fastfood 13、lecture 12、school 12、lottery 11、bridal 10、campus_ad 10、snack 10、museum 9、yakiniku 9、bowling 8、department 8、fruitshop 8、nursery 8、petshop 8、salon 7、clinic_beauty 6、post 6、shrine 6、aquarium 5、dentist 5、police 5、supermarket 5、breakfast 4、club_room 4、drinkshop 4、fortune 4、hotel 4、livehouse 4、nail 4、realty 4、karaoke 3、amusement 2、arcade 2、art_room 2、bbq 2、clothing_s10 2、clothing_s30 2、crepe 2、festival 2、fishing 2、gym_storage 2、pool 2、swimwear 2、bank 1、bike_shop 1、boat 1、campus_gate 1、cinema 1、clothing_s46 1、clothing_s94 1、infirmary 1、phone_shop 1、photo_studio 1、ramen 1、waterpark 1、yukata 1

## 其中站在顯眼位置的（櫃台、收銀、沙發、吧台、接待）：之後優先挪（27）

- bank.counter (32860,59393,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- beach.food_cart (17000,12500,1200)（queue），擋住的是 Resort_R025_2_transit-dining，2 格外走得到
- beach.food_cart2 (17000,13000,1200)（queue），擋住的是 Resort_R026_3_transit-dining，2 格外走得到
- cinema.ticket (32780,59633,2510)（queue），擋住的是 LoverSpot_R2_cinema_ticket1_Machine，1 格外走得到
- clinic_gyn.counter (32265,57600,1200)（queue），擋住的是 LoverSpot_R2_fixtures_crib1_End-58，1 格外走得到
- conveni.counter (47938,27505,1200)（queue），擋住的是 ShopV1_S06_Refit，3 格外走得到
- department.shoes_counter (48333,60182,2460)（queue），擋住的是 LoverSpot_R2_dept_shoes_counter1_Top，1 格外走得到
- fastfood.counter (44216,40201,1200)（queue），擋住的是 S41_F01，1 格外走得到
- hotel.seat17 (31450,65270,1206)（h_sofa），擋住的是 MotelV1_Architecture_H1，1 格外走得到
- hotel.tv_sofa (27655,65020,1706)（tv_sofa），擋住的是 MotelV1_Suite_imore-93474c507aaf，2 格外走得到
- onsen.tv (42470,50010,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv2 (42470,51380,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv3 (43090,50090,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv4 (43090,50925,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv5 (43090,51755,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv6 (44910,51345,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv7 (44910,52175,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv8 (45530,50010,2040)（tv_sofa），擋住的是 S19_F03，2 格外走得到
- onsen.tv9 (45530,51380,2040)（tv_sofa），擋住的是 S19_F03，1 格外走得到
- post.counter (32180,57420,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- post.counter2 (32180,57900,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- post.counter3 (32360,57420,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- post.counter4 (32360,57900,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- post.counter5 (32540,57900,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- post.counter6 (32720,57900,1620)（queue），擋住的是 City_CV_F02，2 格外走得到
- shrine.charm (39956,37551,1198)（queue），擋住的是 LoverSpot_Shrine_LanternCap-150，1 格外走得到
- supermarket.checkout (34300,50580,1200)（queue），擋住的是 ShopV1_S72_Refit，1 格外走得到

## 樓層沒有入口：這層沒有門、電梯平台或樓梯錨點（24）

- bridal 第 3 層（z 1770），2 個錨點
- bridal 第 4 層（z 1870），1 個錨點
- clinic_beauty 第 3 層（z 1770），2 個錨點
- clinic_beauty 第 4 層（z 1870），1 個錨點
- clothing 第 2 層（z 2040），32 個錨點
- clothing_s30 第 3 層（z 1770），2 個錨點
- clothing_s30 第 4 層（z 1870），1 個錨點
- club_room 第 2 層（z 2020），6 個錨點
- gym 第 2 層（z 4780），5 個錨點
- hotel 第 3 層（z 1900），1 個錨點
- hotel 第 4 層（z 2090），6 個錨點
- hotel 第 6 層（z 2560），12 個錨點
- hotel 第 9 層（z 3430），10 個錨點
- karaoke 第 3 層（z 1770），2 個錨點
- karaoke 第 4 層（z 1870），1 個錨點
- livehouse 第 3 層（z 1770），2 個錨點
- livehouse 第 4 層（z 1870），1 個錨點
- lodge 第 1 層（z 1200），3 個錨點
- manga_cafe 第 3 層（z 1770），2 個錨點
- manga_cafe 第 4 層（z 1870），1 個錨點
- salon 第 3 層（z 1770），2 個錨點
- salon 第 4 層（z 1870），1 個錨點
- school 第 2 層（z 1650），1 個錨點
- school 第 3 層（z 2020），1 個錨點

## 錨點在封死的格子：附近可走，但連不到門或電梯／樓梯（21）

- campus_sports.tennis_net (68380,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net2 (68620,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net3 (68380,129400,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net4 (68620,129400,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net5 (72580,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net6 (72820,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net7 (72580,129400,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net8 (72820,129400,1203)，附近最大的區域 1522 格
- campus_sports.volleyball_net (79580,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net2 (79820,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net3 (79580,131600,1202)，附近最大的區域 1550 格
- campus_sports.volleyball_net4 (79820,131600,1202)，附近最大的區域 1550 格
- campus_sports.volleyball_net5 (84180,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net6 (84420,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net7 (84180,131600,1202)，附近最大的區域 1550 格
- campus_sports.volleyball_net8 (84420,131600,1202)，附近最大的區域 1550 格
- clinic_beauty.rest (29946,33859,1200)，附近最大的區域 322 格
- clinic_beauty.seat2 (30175,33886,1200)，附近最大的區域 322 格
- clinic_beauty.toilet3 (30790,33557,1200)，附近最大的區域 322 格
- festival.fireworks (38755,37519,1430)，附近最大的區域 15 格
- playground.field (102791,33791,1198)，附近最大的區域 0 格

