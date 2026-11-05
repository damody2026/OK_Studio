-- Which kinds an anchor is (rules/anchor_kinds.toml), from its name and its place. Used by Tools/build_street_city_places.lua
-- for StreetSocialData/city_anchors.json; names stay what they are, the activities and jobs look anchors up by name.
local M = {}
local BY_NAME = {
  seat = { 'seat' }, chair = { 'seat' }, counter_seat = { 'seat' }, conveyor_seat = { 'seat' }, wait = { 'seat' }, rest = { 'seat' }, dental_chair = { 'seat', 'lie' },
  bench = { 'seat_pair', 'lap_pillow' }, sofa = { 'seat_pair', 'lap_pillow' }, lounge = { 'seat_pair', 'lap_pillow', 'tv_sofa' }, game = { 'tv_sofa' },
  table = { 'seat_face', 'feed' }, grill_table = { 'seat_face', 'feed' }, booth = { 'seat_face', 'feed' }, nail_table = { 'seat_face' },
  lounger = { 'lie' }, bed_exam = { 'lie' }, bed_op = { 'lie' }, pool = { 'h_pool' }, bath = { 'bath' }, shower = { 'shower', 'h_shower' }, women = { 'toilet', 'h_toilet' },
  tank = { 'stand_pair' }, jelly = { 'stand_pair' }, exhibit = { 'stand_pair' }, display = { 'stand_pair' }, pets = { 'stand_pair' }, cats = { 'stand_pair' },
  gate = { 'meet', 'selfie' }, fountain = { 'meet', 'selfie' }, plaza = { 'meet' }, christmas_tree = { 'meet', 'selfie' }, torii = { 'selfie', 'confess' }, pray = { 'confess' },
  photobooth = { 'selfie' }, backdrop = { 'wedding', 'selfie' }, camera = { 'selfie' }, case = { 'gift', 'stand_pair' }, view = { 'view_night', 'view_sunset', 'stand_pair' },
  counter = { 'queue' }, checkout = { 'queue' }, ticket = { 'queue' }, ticket_gate = { 'queue', 'station' }, atm = { 'queue' }, concession = { 'queue' },
  ferris_wheel = { 'ride_pair', 'view_night', 'kiss' }, carousel = { 'ride_pair' }, coaster_station = { 'ride_pair', 'queue' }, teacup_ride = { 'ride_pair' }, jetski = { 'ride_pair' }, banana_boat = { 'ride_pair', 'h_boat' },
  stove = { 'cook' }, kitchen = { 'cook' }, desk = { 'desk_study' }, mirror = { 'vanity' }, class = { 'empty_class' }, music = { 'music_piano' }, fitting = { 'fitting' }, changing_women = { 'changing' }, changing_men = { 'changing' }, changing_hut = { 'changing' }, locker = { 'changing' },
  pingpong = { 'h_pingpong' }, net = { 'h_net' }, beach_volleyball_net = { 'h_net' }, parasol = { 'seat_ground', 'lie_pair', 'lap_pillow' }, camping_tent = { 'lie_pair', 'h_floor' }, bbq_grill = { 'picnic' }, field = { 'seat_ground' },
  try_shoes = { 'try_shoes', 'seat' }, shoe_rack = { 'shoe_rack' }, shoes = { 'try_shoes', 'shoe_rack' }, vault_box = { 'h_box', 'storage_room' }, gym_mat = { 'storage_room', 'h_floor', 'seat_ground', 'lie_pair' },
  wedding_chapel = { 'wedding', 'selfie', 'gift', 'confess', 'meet' }, ultrasound_cart = { 'ultrasound' },
  vending = { 'lean' }, fishing_spot = { 'seat_ground' }, pond = { 'stand_pair' },
  poolside = { 'seat_ground', 'lap_pillow' }, swim = { 'h_pool' }, swan_boat = { 'ride_pair', 'h_boat' }, rowing_boat = { 'ride_pair', 'h_boat' }, dock = { 'stand_pair' },
  telescope = { 'stargaze', 'view_night' }, fence = { 'h_fence', 'lean', 'stand_pair' }, rink = { 'stand_pair' }, court = { 'stand_pair', 'h_net' }, bleacher = { 'seat_pair' }, crib = { 'crib' }, wedding_aisle = { 'wedding', 'selfie' },
}
function M.base(name) return (name:gsub('[%d_]*$', '')) end
local ZONES = { 'women_', 'men_', 'shoes_', 'accessory_' }
local WEAR = { clothing = true, lingerie = true, swimwear = true, yukata = true, department = true, clothing_s10 = true, clothing_s30 = true, clothing_s46 = true, clothing_s94 = true }
local function add(t, seen, k) if not seen[k] then seen[k] = true; t[#t + 1] = k end end
-- a: the anchor; ctx: { privacy, outdoor, place }
function M.classify(a, ctx)
  local out, seen = {}, {}; local tags = {}
  local b = M.base(a.name)
  for _, z in ipairs(ZONES) do if b:sub(1, #z) == z then b = b:sub(#z + 1) end end
  if WEAR[ctx.place] then
    if b == 'rack' or b == 'shoe_rack' then add(out, seen, 'browse'); add(out, seen, 'stand_pair') end
    if b == 'seat' then add(out, seen, 'fitting_wait') end
    if b == 'mirror' then add(out, seen, 'fitting_show') end
    if b == 'counter' or b == 'checkout' then add(out, seen, 'checkout') end
  end
  for _, k in ipairs(BY_NAME[b] or {}) do add(out, seen, k) end
  if a.name:match('^bed') and not a.name:match('^bed_') then add(out, seen, 'lie') end
  if (ctx.place == 'infirmary' or ctx.place:match('^clinic_')) and (b:match('^bed') or b:match('^rest')) then add(out, seen, 'infirmary_bed') end
  if ctx.place == 'tr' or ctx.place == 'station' then add(out, seen, 'station') end
  if b == 'shelf' and (ctx.place == 'library' or ctx.place == 'bookstore') then add(out, seen, 'h_bookshelf') end
  local sk = a.seat_kind
  if sk then
    add(out, seen, 'seat')
    if a.pair then
      if sk == 'picnic_table' or sk == 'cafe_set' then add(out, seen, 'seat_face'); add(out, seen, 'feed') else add(out, seen, 'seat_pair') end
      if sk == 'bench' or sk == 'sofa' then add(out, seen, 'lap_pillow'); add(out, seen, 'feed') end
    end
    if sk == 'picnic_table' then add(out, seen, 'picnic') end
    if sk == 'gazebo' or sk == 'bus_shelter' or sk == 'pergola' then add(out, seen, 'shelter'); tags[#tags + 1] = 'sheltered' end
    if sk == 'bus_shelter' then add(out, seen, 'bus_stop'); add(out, seen, 'station') end
    if sk == 'beach_lounger' or sk == 'lounger' then add(out, seen, 'lie') end
    if sk == 'stand' then add(out, seen, 'seat_pair'); add(out, seen, 'fireworks') end
  end
  local private = ctx.privacy >= 2
  if seen.seat and private then add(out, seen, 'h_chair') end
  if (seen.seat_pair or seen.tv_sofa) and ctx.privacy >= 1 and not ctx.outdoor then add(out, seen, 'h_sofa') end
  if sk == 'bench' and ctx.outdoor and (ctx.privacy >= 1 or ctx.place ~= 'public') then add(out, seen, 'h_bench') end
  if seen.desk_study and ctx.privacy >= 1 then add(out, seen, 'h_desk') end
  if seen.lie and private then add(out, seen, 'lie_pair'); add(out, seen, 'h_floor'); add(out, seen, 'h_group') end
  if seen.empty_class then add(out, seen, 'h_desk'); add(out, seen, 'h_chair') end
  table.sort(out)
  return out, tags
end
return M
