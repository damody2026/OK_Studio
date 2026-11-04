-- Life-places Tripo plan (c-conquest 8.2, user 11-03: "把模型補完 有缺就用 tripo生家具 其它就用blender生成，有需要就用grok生圖生材質，
-- 最後放到unreal場景裡"): writes output/street-social-city-production/life-tripo-v1/plan.json in the world-tripo-v1 plan format
-- (items: index, key, prompt, size_m [w,d,h] m, tris cap, group, place, instances, priority, batch). batch = the round the
-- piece belongs to (2 interiors, 3 outdoors, 4 amusement park). Pieces world-tripo-v1 already planned are reused, not
-- generated again (list `reuse`); walls, booths, counters, lanes and rinks are Blender geometry, not Tripo (list `blender`).
-- Every item is one generation at <= 30 credits with the user's settings; nothing here submits anything.
-- Usage: Tools\lua\lua.exe Tools\plan_street_city_life_tripo.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/life-tripo-v1'
local OUT_TAIL = '. Entire isolated freestanding object, stable base, no floor, no background, no text, no logos.'
-- {key, description, {w,d,h}, tris, group, place(s), instances, priority, batch}
local L = {
  -- round 2: shops, clinics, leisure interiors
  { 'clothing_rack', 'chrome rolling clothing rack with a row of colourful hanging shirts and dresses', { 1.3, 0.5, 1.6 }, 3000, 'shop', 'clothing lingerie swimwear yukata', 30, 1, 2 },
  { 'swimsuit_rack', 'boutique display rack of colourful bikinis and swimsuits on hangers', { 1.3, 0.5, 1.6 }, 3000, 'shop', 'swimwear', 3, 1, 2 },
  { 'yukata_rack', 'wooden kimono stand with patterned summer yukata robes hanging', { 1.4, 0.5, 1.7 }, 3000, 'shop', 'yukata', 3, 1, 2 },
  { 'lingerie_mannequin', 'female torso mannequin on a stand wearing pastel lace lingerie', { 0.5, 0.4, 1.6 }, 2500, 'shop', 'lingerie', 3, 2, 2 },
  { 'jewelry_case', 'glass jewelry display counter with rings and necklaces on velvet trays, wood base', { 1.5, 0.6, 1.0 }, 2500, 'shop', 'jewelry', 3, 1, 2 },
  { 'phone_display', 'smartphone store display table with rows of phones on stands', { 1.5, 0.6, 0.9 }, 2500, 'shop', 'phone_shop', 3, 2, 2 },
  { 'eyeglass_display', 'optician eyeglass frame display wall shelf with many glasses frames', { 1.2, 0.3, 1.8 }, 2500, 'shop', 'optician', 2, 2, 2 },
  { 'ticket_machine', 'japanese ramen shop meal ticket vending machine with picture buttons', { 0.6, 0.5, 1.7 }, 2000, 'shop', 'ramen cinema', 2, 1, 2 },
  { 'ramen_counter', 'wooden ramen shop counter bar with four red round stools', { 3.0, 1.2, 1.0 }, 3500, 'food', 'ramen izakaya', 2, 1, 2 },
  { 'sushi_conveyor', 'conveyor belt sushi bar counter with plates on the belt and stools', { 4.6, 1.2, 1.0 }, 4000, 'food', 'sushi', 1, 1, 2 },
  { 'yakiniku_table', 'korean bbq restaurant table with a built in round grill and hood, four chairs', { 1.4, 1.4, 1.8 }, 3500, 'food', 'yakiniku', 4, 1, 2 },
  { 'izakaya_lantern_bar', 'japanese izakaya wooden bar back shelf with sake bottles and red paper lanterns', { 2.4, 0.5, 2.0 }, 3500, 'food', 'izakaya', 1, 2, 2 },
  { 'crepe_stand', 'small crepe and ice cream counter stand with menu board and griddle', { 2.0, 1.0, 2.2 }, 3500, 'food', 'crepe', 1, 1, 2 },
  { 'fastfood_counter', 'fast food restaurant order counter with menu light boxes and cash registers', { 2.4, 0.8, 2.2 }, 3500, 'food', 'fastfood', 1, 1, 2 },
  { 'cat_tree', 'tall carpeted cat tree tower with platforms, scratching posts and a sleeping cat', { 0.8, 0.8, 1.6 }, 3000, 'leisure', 'cat_cafe', 2, 1, 2 },
  { 'sleeping_cats', 'two cute cats curled up sleeping on a round cushion', { 0.6, 0.6, 0.25 }, 2000, 'leisure', 'cat_cafe', 3, 2, 2 },
  { 'manga_booth', 'manga cafe private booth with a low couch, desk and computer, partition walls', { 2.0, 1.6, 1.6 }, 3500, 'leisure', 'manga_cafe', 3, 1, 2 },
  { 'manga_shelf', 'tall bookshelf packed with colourful manga volumes', { 2.0, 0.4, 2.0 }, 2500, 'leisure', 'manga_cafe', 2, 2, 2 },
  { 'claw_machine', 'arcade claw crane game machine with plush toys inside, pink and white', { 0.9, 0.9, 1.9 }, 3000, 'leisure', 'arcade', 4, 1, 2 },
  { 'photo_booth', 'japanese purikura photo sticker booth with curtain and bright panels', { 1.8, 1.5, 2.2 }, 3500, 'leisure', 'arcade', 1, 1, 2 },
  { 'rhythm_game', 'arcade drum rhythm game cabinet with a big screen', { 0.9, 0.8, 1.8 }, 3000, 'leisure', 'arcade', 1, 2, 2 },
  { 'racing_game', 'arcade racing game cabinet with seat, steering wheel and screen', { 0.9, 1.8, 1.8 }, 3500, 'leisure', 'arcade', 2, 2, 2 },
  { 'billiards_table', 'pool billiards table with green felt, wooden frame and cues', { 2.5, 1.4, 0.8 }, 2500, 'leisure', 'bowling', 2, 1, 2 },
  { 'bowling_pins_return', 'bowling ball return machine with colourful bowling balls', { 1.2, 0.6, 0.9 }, 2500, 'leisure', 'bowling', 2, 2, 2 },
  { 'dental_chair', 'modern dental treatment chair with overhead lamp and instrument tray', { 1.7, 1.0, 2.0 }, 3500, 'health', 'dentist', 2, 1, 2 },
  { 'hospital_bed_curtain', 'clinic examination bed with white sheets and a curtain rail screen', { 2.1, 1.0, 2.0 }, 3000, 'health', 'clinic_gyn clinic_beauty infirmary clinic_general', 6, 1, 2 },
  { 'gyn_exam_chair', 'gynecology examination chair with leg rests, medical white and grey', { 1.4, 0.9, 1.3 }, 3000, 'health', 'clinic_gyn', 1, 1, 2 },
  { 'surgery_lamp', 'surgical operating light on a stand with two round lamp heads', { 1.0, 0.8, 2.1 }, 2000, 'health', 'clinic_beauty clinic_gyn', 2, 2, 2 },
  { 'consult_desk_screen', 'cosmetic clinic consultation desk with a monitor showing a face and two chairs', { 1.6, 1.4, 1.3 }, 3000, 'health', 'clinic_beauty', 1, 1, 2 },
  { 'salon_chair_mirror', 'hair salon styling chair in front of a framed mirror station with shelf', { 1.0, 1.4, 1.9 }, 3000, 'shop', 'salon', 3, 1, 2 },
  { 'shampoo_station', 'hair salon shampoo backwash basin with reclining chair', { 0.8, 1.6, 1.0 }, 2500, 'shop', 'salon', 1, 1, 2 },
  { 'hair_swatch_board', 'hair colour swatch board with dyed hair samples on a wall panel', { 1.6, 0.1, 1.1 }, 1500, 'shop', 'salon', 1, 2, 2 },
  { 'nail_table', 'nail salon manicure table with lamp, polish bottles and two chairs', { 1.2, 1.4, 1.2 }, 2500, 'shop', 'nail', 3, 1, 2 },
  { 'supermarket_shelf', 'supermarket double sided shelving aisle stocked with groceries', { 3.0, 0.6, 1.7 }, 3500, 'shop', 'supermarket', 3, 1, 2 },
  { 'produce_case', 'supermarket refrigerated produce display with vegetables and fruit', { 2.0, 0.9, 1.0 }, 3000, 'shop', 'supermarket', 1, 1, 2 },
  { 'shopping_cart', 'metal supermarket shopping cart', { 0.9, 0.55, 1.0 }, 1500, 'shop', 'supermarket', 2, 2, 2 },
  { 'atm', 'bank ATM cash machine kiosk, grey metal with screen and keypad', { 0.7, 0.7, 1.6 }, 1500, 'service', 'bank', 1, 1, 2 },
  { 'cinema_seats', 'row of three red cinema seats with cup holders', { 1.8, 0.8, 1.0 }, 2500, 'leisure', 'cinema', 6, 1, 2 },
  { 'popcorn_counter', 'cinema concession counter with popcorn machine and drinks', { 2.2, 0.8, 1.8 }, 3500, 'leisure', 'cinema', 1, 1, 2 },
  { 'planetarium_recliner', 'pair of reclining planetarium seats, dark blue upholstery', { 1.6, 1.2, 0.8 }, 2500, 'leisure', 'planetarium', 4, 1, 2 },
  { 'museum_sculpture', 'abstract bronze sculpture on a white museum plinth', { 0.6, 0.6, 1.6 }, 2500, 'leisure', 'museum', 3, 1, 2 },
  { 'museum_vitrine', 'museum glass display case with an old pottery vase inside', { 0.8, 0.8, 1.5 }, 2500, 'leisure', 'museum', 2, 2, 2 },
  { 'easel_canvas', 'wooden painting easel with a half finished landscape canvas and stool', { 0.7, 0.9, 1.7 }, 2000, 'campus', 'art_room', 3, 1, 2 },
  { 'aquarium_tank_wall', 'large wall aquarium tank with coral, rocks and tropical fish, dark frame', { 4.0, 0.8, 2.3 }, 4000, 'leisure', 'aquarium', 1, 1, 2 },
  { 'jellyfish_column', 'cylindrical jellyfish aquarium column with glowing jellyfish', { 0.9, 0.9, 2.4 }, 2500, 'leisure', 'aquarium', 2, 1, 2 },
  { 'spin_bike', 'indoor spinning exercise bike, black and red', { 1.1, 0.5, 1.1 }, 2000, 'sport', 'gym', 2, 2, 2 },
  { 'yoga_mat_roll', 'purple yoga mat laid flat with a rolled mat and blocks', { 1.8, 0.6, 0.2 }, 1000, 'sport', 'gym', 3, 2, 2 },
  { 'gym_shower_stall', 'tiled gym shower cubicle with glass door', { 1.1, 1.1, 2.2 }, 2000, 'sport', 'gym', 1, 2, 2 },
  { 'studio_backdrop', 'photo studio with a white paper backdrop roll on stands, softbox lights and a stool', { 3.0, 2.0, 2.6 }, 3000, 'shop', 'photo_studio', 1, 1, 2 },
  { 'kitchen_unit', 'compact apartment kitchen counter with sink, two burner stove and cabinets', { 2.4, 0.6, 0.95 }, 3000, 'home', 'girls_dorm boys_dorm', 2, 1, 2 },
  { 'bathtub', 'white freestanding bathtub', { 1.6, 0.8, 0.6 }, 1500, 'home', 'girls_dorm boys_dorm', 20, 1, 2 },
  -- round 3: beach, river and lake, festival, outdoor sports
  { 'banana_boat', 'inflatable yellow banana boat with seats for five and handles', { 5.0, 1.0, 1.0 }, 3000, 'beach', 'beach', 2, 1, 3 },
  { 'watermelon_split', 'whole watermelon on a picnic mat with a wooden stick and blindfold', { 0.9, 0.9, 0.3 }, 1500, 'beach', 'beach', 2, 1, 3 },
  { 'sandcastle', 'large sandcastle with towers and a bucket and spade', { 1.2, 1.2, 0.7 }, 2500, 'beach', 'beach', 2, 1, 3 },
  { 'beach_volleyball_net', 'beach volleyball net with posts and a ball in the sand', { 9.0, 0.5, 2.5 }, 2000, 'beach', 'beach', 1, 1, 3 },
  { 'float_rental_rack', 'beach rental rack of colourful inflatable rings and surfboards', { 2.0, 0.8, 1.8 }, 3000, 'beach', 'beach', 1, 1, 3 },
  { 'beach_house_stall', 'japanese umi no ie beach house counter stall with awning, shaved ice and yakisoba', { 4.0, 3.0, 3.0 }, 4000, 'beach', 'beach_house', 1, 1, 3 },
  { 'changing_hut', 'small wooden beach changing hut with a door', { 1.5, 1.5, 2.3 }, 2000, 'beach', 'beach', 4, 1, 3 },
  { 'jetski', 'red and white jet ski personal watercraft', { 3.0, 1.2, 1.1 }, 3000, 'beach', 'jetski', 2, 1, 3 },
  { 'fishing_spot', 'fishing folding chair with a rod on a stand and a cooler box', { 1.2, 1.0, 1.4 }, 2000, 'outdoor', 'fishing', 3, 2, 3 },
  { 'bbq_grill', 'outdoor charcoal barbecue grill with tongs', { 1.0, 0.6, 1.0 }, 2000, 'outdoor', 'bbq', 3, 1, 3 },
  { 'camping_tent', 'green two person dome camping tent', { 2.2, 1.6, 1.3 }, 2000, 'outdoor', 'bbq', 3, 2, 3 },
  { 'goldfish_stall', 'japanese summer festival goldfish scooping stall with a water tub and lantern', { 2.4, 1.8, 2.3 }, 3500, 'festival', 'festival', 1, 1, 3 },
  { 'shooting_stall', 'japanese festival shooting gallery stall with cork rifles and prize shelves', { 2.4, 1.8, 2.3 }, 3500, 'festival', 'festival', 1, 1, 3 },
  { 'takoyaki_stall', 'japanese festival takoyaki food stall with red awning and lanterns', { 2.4, 1.8, 2.3 }, 3500, 'festival', 'festival', 1, 1, 3 },
  { 'cotton_candy_stall', 'festival cotton candy stall with colourful bags hanging', { 2.0, 1.5, 2.3 }, 3500, 'festival', 'festival', 1, 2, 3 },
  { 'yoyo_pool', 'festival water balloon yoyo fishing pool with colourful balloons', { 2.0, 1.0, 0.7 }, 2500, 'festival', 'festival', 1, 2, 3 },
  { 'lantern_string', 'string of red japanese paper lanterns between two wooden poles', { 6.0, 0.3, 3.0 }, 1500, 'festival', 'festival', 4, 2, 3 },
  { 'christmas_tree', 'large decorated christmas tree with lights, star and gifts', { 3.0, 3.0, 5.0 }, 4000, 'festival', 'xmas_tree', 1, 1, 3 },
  { 'batting_machine', 'baseball pitching machine with a net cage section and home plate', { 3.0, 3.0, 2.8 }, 3000, 'sport', 'batting', 2, 2, 3 },
  { 'skate_rental', 'ice skate rental counter with rows of skates', { 2.0, 0.8, 1.8 }, 2500, 'sport', 'skating', 1, 2, 3 },
  -- round 4: amusement park
  { 'ferris_wheel', 'ferris wheel with enclosed gondola cabins, white steel frame', { 30.0, 8.0, 35.0 }, 8000, 'amusement', 'amusement', 1, 1, 4 },
  { 'carousel', 'merry go round carousel with horses, striped roof and lights', { 10.0, 10.0, 7.0 }, 8000, 'amusement', 'amusement', 1, 1, 4 },
  { 'coaster_station', 'roller coaster boarding station with a train of cars on the track', { 12.0, 5.0, 5.0 }, 6000, 'amusement', 'amusement', 1, 1, 4 },
  { 'coaster_track', 'section of roller coaster steel track with supports and a loop', { 20.0, 6.0, 14.0 }, 6000, 'amusement', 'amusement', 3, 1, 4 },
  { 'haunted_house', 'small haunted house attraction facade, spooky wooden mansion with entrance', { 12.0, 8.0, 8.0 }, 6000, 'amusement', 'amusement', 1, 1, 4 },
  { 'teacup_ride', 'spinning teacup ride with pastel cups', { 9.0, 9.0, 3.0 }, 6000, 'amusement', 'amusement', 1, 2, 4 },
  { 'ticket_gate', 'amusement park entrance ticket gate arch with turnstiles', { 8.0, 2.0, 5.0 }, 4000, 'amusement', 'amusement', 1, 1, 4 },
  { 'popcorn_cart', 'striped amusement park popcorn cart with umbrella', { 1.6, 1.0, 2.4 }, 2500, 'amusement', 'amusement', 2, 2, 4 },
  -- round 5 (doc section 10): what the anchors need and the map lacks
  { 'wedding_chapel', 'small white wedding chapel building with a pitched roof, a little bell tower with a cross, arched double wooden door and stained glass windows', { 9, 14, 11 }, 12000, 'outdoor', 'church', 1, 1, 5 },
  { 'shoe_display_rack', 'tall shoe store display shelf with rows of sneakers, heels and leather shoes, light wood', { 2.0, 0.45, 2.0 }, 3500, 'shop', 'department', 9, 1, 5 },
  { 'shoe_try_bench', 'shoe store try-on bench, padded leather seat with a small slanted floor mirror beside it', { 1.3, 0.8, 0.6 }, 2000, 'shop', 'department', 6, 1, 5 },
  { 'post_box', 'red japanese street post box on a short post with a slot', { 0.5, 0.5, 1.4 }, 1200, 'street', 'dorms post', 4, 1, 5 },
  { 'vaulting_box', 'school gym wooden vaulting box, stacked wooden tiers with a white padded top', { 1.2, 0.7, 1.1 }, 2000, 'sport', 'gym_storage', 2, 1, 5 },
  { 'gym_mat_stack', 'stack of three blue gym exercise floor mats, thick foam', { 2.0, 1.2, 0.3 }, 1000, 'sport', 'gym_storage', 2, 1, 5 },
  { 'baby_crib', 'white wooden baby crib with slatted sides and a soft mattress', { 1.2, 0.65, 0.95 }, 2500, 'clinic', 'clinic_gyn', 1, 1, 5 },
  { 'ultrasound_cart', 'medical ultrasound machine cart with a monitor, keyboard and probe holder on wheels', { 0.6, 0.7, 1.5 }, 2500, 'clinic', 'clinic_gyn', 2, 1, 5 },
  { 'shoe_lockers', 'japanese school entrance shoe locker cabinet, grey steel, grid of small open compartments with indoor shoes', { 2.0, 0.4, 1.8 }, 2500, 'school', 'campus', 12, 1, 5 },
  { 'swan_boat', 'white swan shaped two seat pedal boat with a long curved neck, for a park lake', { 2.6, 1.5, 1.8 }, 3000, 'water', 'boat', 4, 1, 3 },
}
-- world-tripo-v1 keys reused as they are (planned there; generated or still to generate there)
local reuse = { treadmill = 'gym', dumbbell_rack = 'gym', locker_bank = 'gym beach', volleyball_net = 'gym_hall',
  lifeguard_tower = 'beach', beach_umbrella_a = 'beach parasol', beach_shower = 'beach', beach_hut = 'beach', lake_pier = 'boat fishing',
  rowing_boat = 'boat', reception_desk = 'counters', cash_register = 'counters', vending_drinks_a = 'vending', food_cart_a = 'stall',
  picnic_table = 'bbq', kitchen_counter = 'home', dining_set = 'home', conference_set = 'office_units', bleacher_a = 'gym_hall', lectern = 'club_room' }
local blender = { 'fitting rooms with curtain', 'partition walls and booths (KTV, clinics, operating room)', 'counters', 'bowling lanes and gutters',
  'ice rink surface and boards', 'batting cage net', 'rooftop fence and benches', 'swimming area water volume boxes', 'mirrors (engine planar reflection)' }
local items = j.array({})
for i, r in ipairs(L) do
  items[#items + 1] = { index = i, key = r[1], prompt = 'One realistic low poly game asset object: ' .. r[2] .. OUT_TAIL, size_m = r[3], tris = r[4], group = r[5], place = r[6], instances = r[7], priority = r[8], batch = r[9] }
end
local per = {}; for _, it in ipairs(items) do per[it.batch] = (per[it.batch] or 0) + 1 end
os.execute('mkdir "' .. out:gsub('/', '\\') .. '" 2>nul')
local f = assert(io.open(out .. '/plan.json', 'wb'))
-- id_prefix names the prepared / imported assets (lt-###-key) apart from the motel sets (mf-, md-)
f:write(j.encode({ status = 'planned_not_submitted', id_prefix = 'lt',
  approved = 'user 2026-11-03 via c-conquest: 把模型補完 有缺就用 tripo生家具 其它就用blender生成，有需要就用grok生圖生材質，最後放到unreal場景裡',
  per_model_credits = 30, settings = 'H3.1, Texture 2K, PBR on, Remove Lighting on, Triangle topology, Ultra Mesh off; check the Generate button shows 30 before submitting',
  rounds = per, reuse_world_tripo_v1 = reuse, blender_geometry = blender, items = items }, { indent = 1 }))
f:close()
print('LIFE TRIPO PLAN', #items, 'items; round 2:', per[2], 'round 3:', per[3], 'round 4:', per[4], 'credits', #items * 30)
