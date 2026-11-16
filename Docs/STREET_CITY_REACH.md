# 大學城地點與錨點可達性（自動產生）

由 `Tools/street_city_reach_check.lua report` 產生：在來源地圖上照遊戲的 NavCellFree 逐格判定（40 cm 格點、半徑 40／30 膠囊、WorldStatic 簡單碰撞、相鄰格高差 40 cm 以內），1 樓從門口、樓上從電梯平台與樓梯錨點灌水。只是線索：可不可以走以遊戲裡實際走為準。

檢查 113 個地點、9596 個錨點；未掃到的區塊 0 個。

## 站位在家具或牆裡：遊戲會改用 1.6 m 內走得到的點（不擋路，只是站位不準）（5083）

各地點筆數（每一筆在 output/street-social-city-production/places-v1/reach-report.json）：girls_dorm 1148、boys_dorm 1133、campus_ib 270、campus_ma 270、campus_rb 270、campus_t4 270、campus_t1 258、campus_t2 258、campus_ee 257、park 85、cafeteria 79、civic 62、library 56、campus_sports 48、beach 44、onsen 36、restaurant 36、cafe 33、izakaya 29、sushi 29、station 28、clinic_general 19、district_office 18、clinic_gyn 17、craft 16、manga_cafe 15、bookstore 14、campus_e1 14、cat_cafe 14、conveni 13、fastfood 13、lecture 12、school 12、lottery 11、bridal 10、snack 10、museum 9、yakiniku 9、bowling 8、department 8、fruitshop 8、nursery 8、petshop 8、salon 7、campus_ad 6、clinic_beauty 6、post 6、shrine 6、aquarium 5、dentist 5、police 5、breakfast 4、club_room 4、drinkshop 4、fortune 4、hotel 4、livehouse 4、nail 4、realty 4、karaoke 3、supermarket 3、amusement 2、arcade 2、art_room 2、bbq 2、clothing_s30 2、crepe 2、festival 2、fishing 2、gym_storage 2、pool 2、bank 1、bike_shop 1、boat 1、campus_gate 1、cinema 1、clothing_s10 1、clothing_s46 1、clothing_s94 1、infirmary 1、phone_shop 1、photo_studio 1、swimwear 1、waterpark 1、yukata 1

## 門到不了街上：門口那一片走不出地點的房間（2）

- arcade 門 (44097,63905,4140)
- ramen 門 (47835,60370,4560)

## 錨點在封死的格子：附近可走，但連不到門或電梯／樓梯（144）

- arcade.claw (43991,67045,4140)，附近最大的區域 80167 格
- arcade.claw2 (44121,67090,4140)，附近最大的區域 80167 格
- arcade.claw3 (44082,67194,4140)，附近最大的區域 80167 格
- arcade.claw4 (43866,67246,4140)，附近最大的區域 80167 格
- arcade.counter (43805,63574,4140)，附近最大的區域 80167 格
- arcade.photobooth (43752,66965,4140)，附近最大的區域 80167 格
- boys_dorm.trash10 (94350,65855,1980)，附近最大的區域 167 格
- boys_dorm.trash11 (94350,65855,2700)，附近最大的區域 167 格
- boys_dorm.trash7 (94350,65855,2340)，附近最大的區域 167 格
- boys_dorm.trash8 (94350,65855,1620)，附近最大的區域 167 格
- boys_dorm.trash9 (94350,65855,3060)，附近最大的區域 167 格
- boys_dorm.vanity100 (94293,65770,3060)，附近最大的區域 167 格
- boys_dorm.vanity101 (94293,65770,1620)，附近最大的區域 167 格
- boys_dorm.vanity102 (94293,65770,2340)，附近最大的區域 167 格
- boys_dorm.vanity107 (94359,65700,2340)，附近最大的區域 167 格
- boys_dorm.vanity108 (94359,65700,1980)，附近最大的區域 167 格
- boys_dorm.vanity109 (94359,65700,3060)，附近最大的區域 167 格
- boys_dorm.vanity92 (94293,65630,2700)，附近最大的區域 167 格
- boys_dorm.vanity93 (94293,65630,1620)，附近最大的區域 167 格
- boys_dorm.vanity95 (94293,65630,2340)，附近最大的區域 167 格
- boys_dorm.vanity96 (94293,65630,3060)，附近最大的區域 167 格
- boys_dorm.vanity97 (94293,65630,1980)，附近最大的區域 167 格
- boys_dorm.vanity98 (94293,65770,2700)，附近最大的區域 167 格
- boys_dorm.vanity99 (94293,65770,1980)，附近最大的區域 167 格
- cafeteria.trash10 (70650,49055,1620)，附近最大的區域 173 格
- cafeteria.trash7 (70650,49055,2020)，附近最大的區域 173 格
- cafeteria.trash8 (70650,49055,2820)，附近最大的區域 173 格
- cafeteria.trash9 (70650,49055,2420)，附近最大的區域 173 格
- campus_ad.trash10 (68150,74055,2400)，附近最大的區域 167 格
- campus_ad.trash6 (68150,74055,1600)，附近最大的區域 167 格
- campus_ad.trash8 (68150,74055,2000)，附近最大的區域 167 格
- campus_ad.trash9 (68150,74055,2800)，附近最大的區域 167 格
- campus_e1.trash10 (79450,50555,2000)，附近最大的區域 164 格
- campus_e1.trash7 (79450,50555,2400)，附近最大的區域 164 格
- campus_e1.trash8 (79450,50555,1600)，附近最大的區域 164 格
- campus_e1.trash9 (79450,50555,2800)，附近最大的區域 164 格
- campus_ee.trash10 (84150,65355,1600)，附近最大的區域 164 格
- campus_ee.trash6 (84150,65355,2400)，附近最大的區域 164 格
- campus_ee.trash7 (84150,65355,2000)，附近最大的區域 164 格
- campus_ee.trash8 (84150,65355,2800)，附近最大的區域 164 格
- campus_ib.trash6 (59150,74355,2400)，附近最大的區域 164 格
- campus_ib.trash7 (59150,74355,1600)，附近最大的區域 164 格
- campus_ib.trash8 (59150,74355,2800)，附近最大的區域 164 格
- campus_ib.trash9 (59150,74355,2000)，附近最大的區域 164 格
- campus_ma.trash10 (78150,65355,1600)，附近最大的區域 164 格
- campus_ma.trash6 (78150,65355,2400)，附近最大的區域 164 格
- campus_ma.trash7 (78150,65355,2000)，附近最大的區域 164 格
- campus_ma.trash9 (78150,65355,2800)，附近最大的區域 164 格
- campus_rb.trash10 (59150,48355,2400)，附近最大的區域 164 格
- campus_rb.trash6 (59150,48355,2000)，附近最大的區域 164 格
- campus_rb.trash8 (59150,48355,2800)，附近最大的區域 164 格
- campus_rb.trash9 (59150,48355,1600)，附近最大的區域 164 格
- campus_sports.tennis_net (68380,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net2 (68620,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net3 (68380,129400,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net4 (68620,129400,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net5 (72580,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net6 (72820,124600,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net7 (72580,129400,1203)，附近最大的區域 1522 格
- campus_sports.tennis_net8 (72820,129400,1203)，附近最大的區域 1522 格
- campus_sports.trash11 (78150,38955,4780)，附近最大的區域 164 格
- campus_sports.trash7 (78150,38955,2120)，附近最大的區域 164 格
- campus_sports.trash8 (78150,38955,4160)，附近最大的區域 164 格
- campus_sports.trash9 (78150,38955,3140)，附近最大的區域 164 格
- campus_sports.volleyball_net (79580,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net2 (79820,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net3 (79580,131600,1202)，附近最大的區域 1550 格
- campus_sports.volleyball_net4 (79820,131600,1202)，附近最大的區域 1550 格
- campus_sports.volleyball_net5 (84180,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net6 (84420,122400,1202)，附近最大的區域 1542 格
- campus_sports.volleyball_net7 (84180,131600,1202)，附近最大的區域 1550 格
- campus_sports.volleyball_net8 (84420,131600,1202)，附近最大的區域 1550 格
- campus_t1.trash10 (65150,56355,2000)，附近最大的區域 164 格
- campus_t1.trash7 (65150,56355,2800)，附近最大的區域 164 格
- campus_t1.trash8 (65150,56355,2400)，附近最大的區域 164 格
- campus_t1.trash9 (65150,56355,1600)，附近最大的區域 164 格
- campus_t2.trash10 (78150,74355,2400)，附近最大的區域 164 格
- campus_t2.trash7 (78150,74355,2800)，附近最大的區域 164 格
- campus_t2.trash8 (78150,74355,1600)，附近最大的區域 164 格
- campus_t2.trash9 (78150,74355,2000)，附近最大的區域 164 格
- campus_t4.trash6 (65150,48355,2800)，附近最大的區域 164 格
- campus_t4.trash7 (65150,48355,2000)，附近最大的區域 164 格
- campus_t4.trash8 (65150,48355,1600)，附近最大的區域 164 格
- campus_t4.trash9 (65150,48355,2400)，附近最大的區域 164 格
- civic.trash10 (32650,63755,2510)，附近最大的區域 166 格
- civic.trash7 (32650,63755,2910)，附近最大的區域 166 格
- civic.trash8 (32650,63755,1620)，附近最大的區域 166 格
- civic.trash9 (32650,63755,2020)，附近最大的區域 166 格
- clinic_beauty.rest (29946,33859,1200)，附近最大的區域 322 格
- clinic_beauty.seat2 (30175,33886,1200)，附近最大的區域 322 格
- clinic_beauty.toilet3 (30790,33557,1200)，附近最大的區域 322 格
- clothing_s10.toilet2 (48490,31957,1200)，附近最大的區域 111 格
- festival.fireworks (38755,37519,1430)，附近最大的區域 15 格
- girls_dorm.trash10 (94350,41855,2700)，附近最大的區域 167 格
- girls_dorm.trash11 (94350,41855,3060)，附近最大的區域 167 格
- girls_dorm.trash7 (94350,41855,2340)，附近最大的區域 167 格
- girls_dorm.trash8 (94350,41855,1620)，附近最大的區域 167 格
- girls_dorm.trash9 (94350,41855,1980)，附近最大的區域 167 格
- girls_dorm.vanity100 (94293,41770,2700)，附近最大的區域 167 格
- girls_dorm.vanity101 (94293,41770,1980)，附近最大的區域 167 格
- girls_dorm.vanity102 (94293,41770,3060)，附近最大的區域 167 格
- girls_dorm.vanity103 (94293,41770,1620)，附近最大的區域 167 格
- girls_dorm.vanity107 (94359,41700,3060)，附近最大的區域 167 格
- girls_dorm.vanity108 (94359,41700,1980)，附近最大的區域 167 格
- girls_dorm.vanity109 (94359,41700,2340)，附近最大的區域 167 格
- girls_dorm.vanity92 (94293,41630,1620)，附近最大的區域 167 格
- girls_dorm.vanity93 (94293,41630,2340)，附近最大的區域 167 格
- girls_dorm.vanity94 (94293,41630,2700)，附近最大的區域 167 格
- girls_dorm.vanity95 (94293,41630,1980)，附近最大的區域 167 格
- girls_dorm.vanity96 (94293,41630,3060)，附近最大的區域 167 格
- girls_dorm.vanity98 (94293,41770,2340)，附近最大的區域 167 格
- izakaya.booth (34307,26339,1200)，附近最大的區域 140 格
- izakaya.booth2 (33940,26403,1200)，附近最大的區域 140 格
- izakaya.counter_seat (34293,26152,1200)，附近最大的區域 140 格
- izakaya.counter_seat2 (34218,26152,1200)，附近最大的區域 140 格
- izakaya.counter_seat3 (34143,26152,1200)，附近最大的區域 140 格
- izakaya.seat33 (34277,26439,1200)，附近最大的區域 140 格
- izakaya.seat34 (34337,26439,1200)，附近最大的區域 140 格
- izakaya.seat35 (34337,26379,1200)，附近最大的區域 140 格
- izakaya.seat36 (34277,26379,1200)，附近最大的區域 140 格
- izakaya.seat37 (34040,26433,1200)，附近最大的區域 140 格
- izakaya.seat38 (34040,26373,1200)，附近最大的區域 140 格
- izakaya.seat39 (33980,26373,1200)，附近最大的區域 140 格
- izakaya.seat40 (33980,26433,1200)，附近最大的區域 140 格
- library.trash10 (59150,66555,2000)，附近最大的區域 166 格
- library.trash6 (59150,66555,2800)，附近最大的區域 166 格
- library.trash7 (59150,66555,2400)，附近最大的區域 166 格
- library.trash8 (59150,66555,1600)，附近最大的區域 166 格
- playground.field (102791,33791,1198)，附近最大的區域 0 格
- ramen.counter_seat (48025,60348,4560)，附近最大的區域 77120 格
- ramen.counter_seat2 (48025,60273,4560)，附近最大的區域 77120 格
- ramen.counter_seat3 (48025,60198,4560)，附近最大的區域 77120 格
- ramen.counter_seat4 (48025,60123,4560)，附近最大的區域 77120 格
- ramen.seat (48113,60510,4560)，附近最大的區域 77120 格
- ramen.seat3 (48073,60510,4561)，附近最大的區域 77120 格
- ramen.seat4 (48023,60510,4561)，附近最大的區域 77120 格
- ramen.ticket (48179,60425,4560)，附近最大的區域 77120 格
- restaurant.private_room2 (48100,25215,1200)，附近最大的區域 56 格
- supermarket.aisle3 (34751,50410,1200)，附近最大的區域 104 格
- supermarket.toilet2 (34790,50197,1200)，附近最大的區域 104 格
- swimwear.seat (34361,33682,1200)，附近最大的區域 147 格
- swimwear.seat3 (34376,33717,1200)，附近最大的區域 147 格
- swimwear.seat4 (34316,33717,1200)，附近最大的區域 147 格
- swimwear.toilet2 (34690,32957,1200)，附近最大的區域 147 格

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

