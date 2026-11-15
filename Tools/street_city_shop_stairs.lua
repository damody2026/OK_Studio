-- The stairs of the shops with floors (the S-row shop template: one switchback stair per building, its flights in the
-- shell mesh, not separate actors). Anchors stairN, N the floor, on the floor at the stair's end (the game's stair rule:
-- campus and shops alike, c-conquest stair1116c): stair1 on the ground floor 40 cm before the first flight, stair2 on the
-- 2F where the second flight arrives, stair3 the same on the 3F. Found from the source map by
-- Tools/street_city_room_survey_payload.lua (heights: a line down per 20 cm cell from over the upper floor; a flight is a
-- straight run of rising heights), 2026-11-16, c-street-city. Read by Tools/export_street_city_game_places.lua: a place
-- with stair anchors is no longer "upstairs with no way up" (Tools/street_city_upstairs_off.lua).
-- Left out: bike_shop (its two rooms are two shops 116 m apart, S35 and S81; the flight found is S81's); photo_studio (no flight in
-- the scan). crepe and nail (added 11-16 by hand): the same switchback, but the first flight's lowest metre has no collision
-- (the line down hits the ground floor there), so no foot was found; their stair1/stair2 are the cafe's (same S-row
-- template, same orientation) moved by the offset of the flights' start (nail -13660,+12800; crepe -13800,+25200).
-- stair1 moved (walk probe 11-16, door -> stair1): the flight's foot is behind the stair's side wall, 1.1-1.3 m from
-- the nearest cell walked to from the door; stair1 is that cell (the game reaches a stair within 170 cm): bookstore, bowling, breakfast, bridal, cafe, cat_cafe, clothing_s10, clothing_s30, clothing_s46, clothing_s94, conveni, craft, district_office, drinkshop, fastfood, fortune, fruitshop, izakaya, livehouse, lottery, nursery, petshop, police, realty, restaurant, salon, snack, sushi, yakiniku, yukata
-- Four more whose flight's foot is a pocket walled off by the shop's fittings (the stair is 80 cm wide between walls):
-- stair1 is the nearest cell reached from the door, 3.4-7.5 m off (clinic_beauty, manga_cafe, supermarket, swimwear).
-- karaoke: its stair stands in a shut-off part north of the west room (y 48000-48300, shell partitions all round):
-- stair1 is on the shop's main aisle, 6 m off. (The west room itself got its 1.2 m hole on 11-16 and is walked in and
-- out of in the game, city1116a.)
return {
  crepe = {
    { name = "stair1", pos = { 34630, 47380, 1200 } },
    { name = "stair2", pos = { 34610, 47430, 1580 } },
  },
  nail = {
    { name = "stair1", pos = { 34770, 34980, 1200 } },
    { name = "stair2", pos = { 34750, 35030, 1580 } },
  },
  bookstore = {
    { name = "stair1", pos = { 48430, 29340, 1200 } }, -- was 48450, 29210
    { name = "stair2", pos = { 48410, 29390, 1580 } },
    { name = "stair3", pos = { 48410, 29390, 1960 } },
  },
  bowling = {
    { name = "stair1", pos = { 29570, 29500, 1200 } }, -- was 29550, 29610
    { name = "stair2", pos = { 29590, 29430, 1580 } },
  },
  breakfast = {
    { name = "stair1", pos = { 29770, 39580, 1200 } }, -- was 29750, 39690
    { name = "stair2", pos = { 29790, 39510, 1580 } },
  },
  bridal = {
    { name = "stair1", pos = { 29770, 24660, 1200 } }, -- was 29750, 24770
    { name = "stair2", pos = { 29790, 24590, 1580 } },
    { name = "stair3", pos = { 29790, 24590, 1960 } },
  },
  cafe = {
    { name = "stair1", pos = { 48430, 22180, 1200 } }, -- was 48450, 22050
    { name = "stair2", pos = { 48410, 22230, 1580 } },
    { name = "stair3", pos = { 48410, 22230, 1960 } },
  },
  cat_cafe = {
    { name = "stair1", pos = { 34630, 45260, 1200 } }, -- was 34650, 45130
    { name = "stair2", pos = { 34610, 45310, 1580 } },
  },
  clinic_beauty = {
    { name = "stair1", pos = { 30390, 33880, 1200 } }, -- was 29650, 33790: its foot is walled off, 745 cm away
    { name = "stair2", pos = { 29690, 33610, 1580 } },
    { name = "stair3", pos = { 29690, 33610, 1960 } },
  },
  clothing_s10 = {
    { name = "stair1", pos = { 48430, 32720, 1200 } }, -- was 48450, 32590
    { name = "stair2", pos = { 48410, 32770, 1580 } },
  },
  clothing_s30 = {
    { name = "stair1", pos = { 43570, 25880, 1200 } }, -- was 43550, 25990
    { name = "stair2", pos = { 43590, 25810, 1580 } },
    { name = "stair3", pos = { 43590, 25810, 1960 } },
  },
  clothing_s46 = {
    { name = "stair1", pos = { 43570, 45840, 1200 } }, -- was 43550, 45950
    { name = "stair2", pos = { 43590, 45770, 1580 } },
  },
  clothing_s94 = {
    { name = "stair1", pos = { 29770, 48000, 1200 } }, -- was 29750, 48110
    { name = "stair2", pos = { 29790, 47930, 1580 } },
  },
  conveni = {
    { name = "stair1", pos = { 48530, 28080, 1200 } }, -- was 48550, 27950
    { name = "stair2", pos = { 48510, 28130, 1580 } },
    { name = "stair3", pos = { 48510, 28130, 1960 } },
  },
  craft = {
    { name = "stair1", pos = { 34630, 30340, 1200 } }, -- was 34650, 30210
    { name = "stair2", pos = { 34610, 30390, 1580 } },
  },
  district_office = {
    { name = "stair1", pos = { 48630, 36700, 1200 } }, -- was 48650, 36570
    { name = "stair2", pos = { 48610, 36750, 1580 } },
  },
  drinkshop = {
    { name = "stair1", pos = { 48330, 23240, 1200 } }, -- was 48350, 23110
    { name = "stair2", pos = { 48310, 23290, 1580 } },
    { name = "stair3", pos = { 48310, 23290, 1960 } },
  },
  fastfood = {
    { name = "stair1", pos = { 43270, 39540, 1200 } }, -- was 43250, 39650
    { name = "stair2", pos = { 43290, 39470, 1580 } },
  },
  fortune = {
    { name = "stair1", pos = { 34530, 24240, 1200 } }, -- was 34550, 24110
    { name = "stair2", pos = { 34510, 24290, 1580 } },
  },
  fruitshop = {
    { name = "stair1", pos = { 48430, 26820, 1200 } }, -- was 48450, 26690
    { name = "stair2", pos = { 48410, 26870, 1580 } },
    { name = "stair3", pos = { 48410, 26870, 1960 } },
  },
  izakaya = {
    { name = "stair1", pos = { 34930, 26760, 1200 } }, -- was 34950, 26630
    { name = "stair2", pos = { 34910, 26810, 1580 } },
  },
  karaoke = {
    { name = "stair1", pos = { 44150, 48640, 1200 } }, -- was 43550, 48270: in the west room, 6 m away
    { name = "stair2", pos = { 43590, 48090, 1580 } },
    { name = "stair3", pos = { 43590, 48090, 1960 } },
  },
  livehouse = {
    { name = "stair1", pos = { 29670, 50320, 1200 } }, -- was 29650, 50430
    { name = "stair2", pos = { 29690, 50250, 1580 } },
    { name = "stair3", pos = { 29690, 50250, 1960 } },
  },
  lottery = {
    { name = "stair1", pos = { 48330, 43000, 1200 } }, -- was 48350, 42870
    { name = "stair2", pos = { 48310, 43050, 1580 } },
    { name = "stair3", pos = { 48310, 43050, 1960 } },
  },
  manga_cafe = {
    { name = "stair1", pos = { 30050, 22300, 1200 } }, -- was 29750, 22450: its foot is walled off, 335 cm away
    { name = "stair2", pos = { 29790, 22270, 1580 } },
    { name = "stair3", pos = { 29790, 22270, 1960 } },
  },
  nursery = {
    { name = "stair1", pos = { 29770, 44420, 1200 } }, -- was 29750, 44530
    { name = "stair2", pos = { 29790, 44350, 1580 } },
  },
  onsen = {
    { name = "stair1", pos = { 44490, 49250, 1200 } },
    { name = "stair2", pos = { 44450, 49430, 1620 } },
    { name = "stair3", pos = { 44450, 49430, 2040 } },
  },
  petshop = {
    { name = "stair1", pos = { 48430, 30400, 1200 } }, -- was 48450, 30270
    { name = "stair2", pos = { 48410, 30450, 1580 } },
    { name = "stair3", pos = { 48410, 30450, 1960 } },
  },
  police = {
    { name = "stair1", pos = { 34530, 44000, 1200 } }, -- was 34550, 43870
    { name = "stair2", pos = { 34510, 44050, 1580 } },
  },
  realty = {
    { name = "stair1", pos = { 48330, 45320, 1200 } }, -- was 48350, 45190
    { name = "stair2", pos = { 48310, 45370, 1580 } },
  },
  restaurant = {
    { name = "stair1", pos = { 48730, 25760, 1200 } }, -- was 48750, 25630
    { name = "stair2", pos = { 48710, 25810, 1580 } },
    { name = "stair3", pos = { 48710, 25810, 1960 } },
  },
  salon = {
    { name = "stair1", pos = { 43470, 26940, 1200 } }, -- was 43450, 27050
    { name = "stair2", pos = { 43490, 26870, 1580 } },
    { name = "stair3", pos = { 43490, 26870, 1960 } },
  },
  snack = {
    { name = "stair1", pos = { 48430, 24300, 1200 } }, -- was 48450, 24170
    { name = "stair2", pos = { 48410, 24350, 1580 } },
    { name = "stair3", pos = { 48410, 24350, 1960 } },
  },
  supermarket = {
    { name = "stair1", pos = { 34730, 51400, 1200 } }, -- was 34750, 51030: its foot is walled off, 371 cm away
    { name = "stair2", pos = { 34710, 51210, 1580 } },
  },
  sushi = {
    { name = "stair1", pos = { 34930, 48840, 1200 } }, -- was 34950, 48710
    { name = "stair2", pos = { 34910, 48890, 1580 } },
  },
  swimwear = {
    { name = "stair1", pos = { 34350, 33200, 1200 } }, -- was 34650, 33590: its foot is walled off, 492 cm away
    { name = "stair2", pos = { 34610, 33770, 1580 } },
  },
  yakiniku = {
    { name = "stair1", pos = { 29470, 40640, 1200 } }, -- was 29450, 40750
    { name = "stair2", pos = { 29490, 40570, 1580 } },
  },
  yukata = {
    { name = "stair1", pos = { 29770, 25920, 1200 } }, -- was 29750, 26030
    { name = "stair2", pos = { 29790, 25850, 1580 } },
  },
}
