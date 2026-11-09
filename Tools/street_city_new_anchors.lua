-- New anchors for the things people do together (Docs/STREET_CITY_GAME_NEEDS_INVENTORY_20261103.md section 10.1), made from
-- what the place data already knows: props, room doors, building entrances, stairs. Ones that need the ground measured
-- come from places-v1/anchor-fit.json (Tools/street_city_anchor_fit_payload.lua). Called by Tools/build_street_city_places.lua.
-- Returns rows { place, name, pos, yaw, kinds, tags, privacy, outdoor, building, slots }.
local HOME = { dorm = true, apartment = true, motel_suite = true, motel_pool_suite = true, suite = true, deluxe = true, executive = true, inn = true, ['住宿'] = true }
local CAMPUS = { T1 = true, T2 = true, T4 = true, E1 = true, EE = true, MA = true, RB = true, IB = true, AD = true, LI = true, SC = true, IN = true }
local RESIDENCE = { D1 = true, D2 = true, D3 = true, D4 = true, H1 = true, S18 = true, R1 = true, R2 = true }
local BY_PROP = { -- prop kind -> { name, kinds, tags, privacy }
  trash = { 'trash', { 'trash' } }, drinking_fountain = { 'water_fountain', { 'water_fountain' } }, notice_board = { 'notice_board', { 'notice_board' } },
  campus_map = { 'campus_map', { 'notice_board', 'meet' } }, bike_stand = { 'bike_rack', { 'bike_rack' } }, bike_shelter = { 'bike_shelter', { 'bike_rack', 'shelter' }, { 'sheltered' } },
  bus_shelter = { 'bus_stop', { 'bus_stop', 'shelter' }, { 'sheltered' } }, gazebo = { 'gazebo', { 'shelter', 'kiss', 'confess' }, { 'sheltered' }, 1 }, pergola = { 'pergola', { 'shelter', 'kiss' }, { 'sheltered', 'shade' }, 1 },
  cherry_tree = { 'blossom', { 'blossom', 'selfie', 'confess', 'picnic', 'seat_ground' }, { 'spring', 'shade' } }, lantern = { 'lamp', { 'kiss', 'goodbye' }, nil, 1 },
  art_installation = { 'landmark', { 'selfie', 'meet' } }, clock_tower = { 'clock_tower', { 'meet', 'selfie' } }, photo_spot = { 'photo_spot', { 'selfie' } },
  lighthouse = { 'lighthouse', { 'view_sunset', 'view_night', 'stargaze', 'confess', 'gift', 'selfie' }, { 'sunset', 'night_view' } },
  viewpoint = { 'viewpoint', { 'view_sunset', 'view_night', 'stargaze', 'gift' }, { 'sunset', 'night_view' } }, telescope = { 'telescope', { 'view_night', 'stargaze' }, { 'night_view' } },
  food_cart = { 'food_cart', { 'queue' } }, piano = { 'piano', { 'music_piano' } }, tv = { 'tv', { 'tv_sofa' } }, table_tennis = { 'pingpong', { 'h_pingpong' } }, swing = { 'swing', { 'seat_pair' } },
  washing_machine = { 'washer', { 'laundry' } }, dryer = { 'dryer', { 'laundry' } }, newsstand = { 'newsstand', { 'queue' } }, exercise_mat = { 'mat', { 'seat_ground', 'h_floor' }, nil, 1 },
  railing = { 'rail', { 'lean', 'stand_pair', 'h_fence' } },
}
return function(ctx)
  local rows, seq = {}, {}
  local boxes = {}
  for _, g in ipairs(ctx.game_places) do for _, r in ipairs(g.rooms or {}) do
    if r.min then boxes[#boxes + 1] = { g = g, lo = r.min, hi = r.max, v = (r.max[1] - r.min[1]) * (r.max[2] - r.min[2]) } end end end
  table.sort(boxes, function(a, b) return a.v < b.v end)
  local function owner(p)
    for _, b in ipairs(boxes) do if p[1] >= b.lo[1] and p[1] <= b.hi[1] and p[2] >= b.lo[2] and p[2] <= b.hi[2] and p[3] >= b.lo[3] - 30 and p[3] <= b.hi[3] + 30 then return b.g end end
  end
  local function put(prefix, pos, yaw, kinds, o)
    o = o or {}; local g = owner(pos); local place = o.place or (g and g.id) or (o.area and o.area.id) or 'public'
    local k = place .. '/' .. prefix; seq[k] = (seq[k] or 0) + 1
    local a = o.area
    local building = o.building or (g and type(g.building) == 'string' and g.building) or (a and a.building) or nil
    rows[#rows + 1] = { place = place, name = prefix .. (seq[k] > 1 and seq[k] or ''), pos = pos, seat_pos = o.seat_pos, yaw = yaw or 0, kinds = kinds, tags = o.tags, slots = o.slots,
      privacy = o.privacy or (a and a.privacy) or (g and g.privacy) or 0, outdoor = o.outdoor, building = building }
  end
  local function toward(p, q, d) local dx, dy = q[1] - p[1], q[2] - p[2]; local n = math.sqrt(dx * dx + dy * dy); if n < 1 then return { p[1], p[2], p[3] } end
    return { p[1] + dx / n * d, p[2] + dy / n * d, p[3] } end
  local function yaw_to(p, q) return math.deg(math.atan(q[2] - p[2], q[1] - p[1])) - 90 end
  local function centre(a) return { (a.min[1] + a.max[1]) / 2, (a.min[2] + a.max[2]) / 2, a.min[3] } end
  local function pairs_at(p, yaw, d)
    local r = math.rad(yaw); local tx, ty = math.cos(r) * d, math.sin(r) * d
    return { { pos = { p[1] - tx, p[2] - ty, p[3] }, yaw = yaw }, { pos = { p[1] + tx, p[2] + ty, p[3] }, yaw = yaw } }
  end
  -- props by kind
  for _, t in ipairs(ctx.props) do
    local a = t.a and ctx.area[t.a + 1] or nil; local r = BY_PROP[t.k]; local yaw = t.face and t.face - 90 or 0
    local out = not a or a.kind ~= 'room'
    if t.p[1] ~= 0 or t.p[2] ~= 0 then
      if r then put(r[1], t.p, yaw, r[2], { tags = r[3], privacy = r[4], area = a, outdoor = out }) end
      local home = a and HOME[a.type]
      if home and t.k == 'table' then
        -- the two sides of the table: feet on the floor, hips at chair height
        local z = t.p; local f = math.rad(yaw + 90); local dx, dy = math.cos(f) * 70, math.sin(f) * 70
        local function side(s, y) return { pos = { z[1] + s * dx, z[2] + s * dy, z[3] }, seat_pos = { z[1] + s * dx, z[2] + s * dy, z[3] + 45 }, yaw = y } end
        put('dining', z, yaw, { 'dining', 'feed', 'seat_face' }, { area = a, outdoor = false, slots = { side(-1, yaw), side(1, yaw + 180) } })
      elseif home and t.k == 'wardrobe' then put('wardrobe', t.p, yaw, { 'closet' }, { area = a, outdoor = false })
      elseif home and t.k == 'mirror' then put('vanity', t.p, yaw, { 'vanity' }, { area = a, outdoor = false })
      elseif home and t.k == 'bathtub' then put('tub', t.p, yaw, { 'bath' }, { area = a, outdoor = false })
      elseif t.k == 'toilet' then put('toilet', t.p, yaw, { 'toilet', 'h_toilet' }, { area = a, outdoor = false })
      elseif t.k == 'bookshelf' and a and (a.building == 'LI' or a.type == 'study') then put('stacks', t.p, yaw, { 'wall_pin', 'kiss', 'h_bookshelf' }, { area = a, outdoor = false, privacy = 1 })
      end
    end
  end
  -- homes: the entrance inside the door, a wall spot beside it; rooms named for staff or laundry
  for _, a in ipairs(ctx.area) do
    -- H1 floors 2-5 are the motel suites now: the old room boxes are still in the area list, but nothing stands there
    if a.kind == 'room' and a.door and a.min and not (a.building == 'H1' and (a.floor or 0) >= 2) then
      local c = centre(a)
      if HOME[a.type] then
        local e = toward(a.door, c, 70); put('entry', e, yaw_to(a.door, c), { 'entry', 'shoe_change' }, { area = a, place = a.id, outdoor = false })
        put('wall', toward(a.door, c, 110), yaw_to(c, a.door), { 'h_wall', 'wall_pin', 'kiss' }, { area = a, place = a.id, outdoor = false, privacy = math.max(a.privacy or 0, 1) })
      end
      -- the window side of the room, the wall across from the door; balcony rows come from the real slabs (room anchors)
      if a.type == 'apartment' or a.type == 'suite' or a.type == 'deluxe' or a.type == 'executive' then
        put('window', toward(c, a.door, -(math.max(a.max[1] - a.min[1], a.max[2] - a.min[2]) / 2 - 90)), yaw_to(a.door, c), { 'view_night' }, { area = a, place = a.id, outdoor = false, tags = { 'window' } })
      end
      local name = a.name or ''
      if name:find('員工', 1, true) then put('staff', c, 0, { 'staff_room', 'closet', 'changing' }, { area = a, outdoor = false }) end
      if name:find('洗衣', 1, true) then put('laundry', c, 0, { 'laundry' }, { area = a, outdoor = false }) end
      if a.id == 'tr-0102' then put('bus_wait', c, 0, { 'bus_stop', 'station', 'shelter' }, { area = a, outdoor = false, tags = { 'sheltered' } }) end
    elseif a.kind == 'place' and a.type == 'grove' then
      local p = a.door; local yaw = 0
      put('grove', p, yaw, { 'confess', 'kiss', 'picnic', 'seat_ground', 'lie_pair', 'lap_pillow', 'stargaze', 'h_floor' }, { place = 'public', outdoor = true, privacy = 1, tags = { 'shade' }, slots = pairs_at(p, yaw, 35) })
    end
  end
  -- building entrances: goodbyes at the homes, shoe lockers just inside the school buildings
  local bs = {}; for b in pairs(ctx.entry) do bs[#bs + 1] = b end; table.sort(bs)
  for _, b in ipairs(bs) do
    local e = ctx.entry[b]; local c = ctx.bcentre(b)
    if c then
      if RESIDENCE[b] then
        local p = toward(e, c, -180); put('goodbye', p, yaw_to(p, e), { 'goodbye', 'kiss', 'meet' }, { place = 'public', building = b, outdoor = true, slots = pairs_at(p, yaw_to(p, e), 40) })
      end
      if CAMPUS[b] then put('shoe_locker', toward(e, c, 220), yaw_to(e, c), { 'shoe_locker', 'shoe_change' }, { building = b, outdoor = false }) end
    end
  end
  -- stair turns of the campus buildings; the stair anchors stay for walking
  for _, g in ipairs(ctx.game_places) do
    for _, a in ipairs(g.anchors or {}) do
      if a.name:match('^stair%d*$') then put('landing', a.pos, a.yaw, { 'stair_landing', 'kiss', 'wall_pin', 'h_wall' }, { place = g.id, outdoor = false, privacy = 1 }) end
      if a.name:match('^bed_op') and g.id == 'clinic_gyn' then put('ultrasound', a.pos, a.yaw, { 'ultrasound' }, { place = g.id, outdoor = false }) end
    end
  end
  -- single fixtures from the scene install
  local keys = {}; for k in pairs(ctx.items or {}) do keys[#keys + 1] = k end; table.sort(keys)
  local areas = {}; for _, a in ipairs(ctx.area) do if a.id then areas[a.id] = a end end
  for _, k in ipairs(keys) do local it = ctx.items[k]
    if it.place == 'fixtures' then
      local kind = it.anchor:match('^mailbox') and 'mailbox' or it.anchor:match('^crib') and 'crib' or it.anchor:match('^ultrasound') and 'ultrasound'
      if kind then put(kind, it.pos, it.yaw, { kind }, { outdoor = kind == 'mailbox', place = kind ~= 'mailbox' and 'clinic_gyn' or nil }) end
    end
    -- real balconies (round 3): rows of their room, standing on the slab
    if it.anchor == 'balcony' then put('balcony', it.pos, it.yaw, { 'balcony', 'view_night', 'stand_pair' }, { area = areas[it.place], place = it.place, outdoor = true, tags = { 'balcony' } }) end
    -- the school changing booths belong to their building, not to a game place
    local b = it.place:match('^fixtures_changing_(%w+)_')
    if b then put('changing', it.pos, it.yaw, { 'changing' }, { building = b, outdoor = false }) end
  end
  -- changing rooms and shoes off: the door of each place where people change or take off their shoes
  for _, id in ipairs({ 'onsen', 'minshuku', 'izakaya', 'pool', 'gym' }) do
    for _, g in ipairs(ctx.game_places) do if g.id == id and g.door then
      local c = g.rooms and g.rooms[1] and g.rooms[1].min and { (g.rooms[1].min[1] + g.rooms[1].max[1]) / 2, (g.rooms[1].min[2] + g.rooms[1].max[2]) / 2, g.door[3] } or g.door
      local kinds = (id == 'pool' or id == 'gym') and { 'changing' } or id == 'onsen' and { 'changing', 'shoe_change' } or { 'shoe_change' }
      put('change', toward(g.door, c, 120), yaw_to(g.door, c), kinds, { place = id, outdoor = false })
    end end
  end
  -- nets merged into the stadium and track meshes (height map world_round_courts): both sides of each tennis and volleyball
  -- net, in front of the goals, and the far end of the beach net
  for _, n in ipairs({ { 68500, 124600 }, { 68500, 129400 }, { 72700, 124600 }, { 72700, 129400 } }) do
    put('tennis_net', { n[1] - 120, n[2], 1203 }, 90, { 'h_net', 'stand_pair' }, { place = 'campus_sports', outdoor = true })
    put('tennis_net', { n[1] + 120, n[2], 1203 }, -90, { 'h_net', 'stand_pair' }, { place = 'campus_sports', outdoor = true })
  end
  for _, n in ipairs({ { 79700, 122400 }, { 79700, 131600 }, { 84300, 122400 }, { 84300, 131600 } }) do
    put('volleyball_net', { n[1] - 120, n[2], 1202 }, 90, { 'h_net', 'stand_pair' }, { place = 'campus_sports', outdoor = true })
    put('volleyball_net', { n[1] + 120, n[2], 1202 }, -90, { 'h_net', 'stand_pair' }, { place = 'campus_sports', outdoor = true })
  end
  put('soccer_goal', { 60600, 25700, 1225 }, -90, { 'h_net', 'stand_pair' }, { place = 'campus_sports', outdoor = true })
  put('soccer_goal', { 60600, 34300, 1225 }, 90, { 'h_net', 'stand_pair' }, { place = 'campus_sports', outdoor = true })
  put('volleyball_net', { 11795.8, 102156, 1212 }, 0, { 'h_net', 'stand_pair' }, { place = 'beach', outdoor = true })
  -- measured spots: routes, rooftops, shores, bridges (anchor-fit job)
  for _, r in ipairs(ctx.fit or {}) do put(r.name, r.pos, r.yaw, r.kinds, { place = r.place, tags = r.tags, privacy = r.privacy, outdoor = r.outdoor ~= false, building = r.building, slots = r.pair and pairs_at(r.pos, r.yaw, 40) or nil }) end
  return rows
end
