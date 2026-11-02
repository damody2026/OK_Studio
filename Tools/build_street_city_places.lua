-- UniversityCity place inventory for the StreetSocial game (Docs/STREET_CITY_PLACES_INVENTORY_20261103.md).
--   Tools\lua\lua.exe Tools\build_street_city_places.lua
-- Inputs (all under output/street-social-city-production/):
--   places-v1/actors.json                 world_places_probe dump (Tools/street_city_places_payload.lua)
--   motel-v1/motel-install.json, motel-plan.json, sample-rooms/models-v2/<id>/build.json
--   world-edge-v1/bed-mirrors-install-*.json (latest)
-- Output: places-v1/places.json. Coordinates are UE cm, +X north, +Y east (the game's frame). Anchor yaw follows the
-- game's OKStreetSocialPlaces.h convention: a character standing on the anchor faces yaw + 90.
local json = require('ok.json')
local root = 'C:/portable/OpenKoikatsu/output/street-social-city-production/'
local function load(p) local f = assert(io.open(root .. p, 'rb'), p); local s = f:read('a'); f:close(); return json.decode(s) end
local function exists(p) local f = io.open(p, 'rb'); if f then f:close() end; return f ~= nil end
local function r1(v) return math.floor(v * 10 + .5) / 10 end
local function P(x, y, z) return { r1(x), r1(y), r1(z) } end

local actors = load('places-v1/actors.json')
local install, plan = load('motel-v1/motel-install.json'), load('motel-v1/motel-plan.json')
local planned = {}; for _, q in ipairs(plan.rooms) do planned[q.id] = q end
local latest
for name in io.popen('ls -1 "' .. root .. 'world-edge-v1" 2>nul'):lines() do
  if name:match('^bed%-mirrors%-install%-.*%.json$') and (not latest or name > latest) then latest = name end
end
local mirrors = {}
if latest then for _, m in ipairs(load('world-edge-v1/' .. latest).mirrors) do mirrors[m.id] = mirrors[m.id] or {}; table.insert(mirrors[m.id], m) end end

local places = {}
local function add(p) places[#places + 1] = p end

-- 1. Motel suites: lockable rooms with a bed, a bath and (mostly) real mirrors. privacy 2 = the game's H threshold.
for _, r in ipairs(install.rooms) do
  local q = planned[r.id]; local a = math.rad(q.yaw); local s, c = math.sin(a), math.cos(a); local b = r.position
  local function W(x, y, z) return P(b[1] + (x * s + y * c) * 100, b[2] + (x * c - y * s) * 100, b[3] + z * 100) end
  local bed = { -3.34, 4.7 }
  local bj = root .. 'motel-v1/sample-rooms/models-v2/' .. r.id .. '/build.json'
  if exists(bj) then local L = load('motel-v1/sample-rooms/models-v2/' .. r.id .. '/build.json').lights; if L[2] then bed = { L[2]['local'][1], L[2]['local'][2] + .4 } end end
  local top = .55
  for _, m in ipairs(mirrors[r.id] or {}) do top = m.bed_top_m or top end
  -- headboard direction (room +y) as a world yaw; a person lying on the bed with the head at the headboard
  local head = math.deg(math.atan(-s, c))
  local w, d = q.size_m[1], q.size_m[2]
  local uses = { 'sleep', 'h_bed', 'h_floor', 'h_wall', 'bath' }
  if mirrors[r.id] then uses[#uses + 1] = 'mirror_h' end
  if q.is_pool_suite then uses[#uses + 1] = 'pool' end
  if q.has_in_room_garage then uses[#uses + 1] = 'garage' end
  local ms = {}
  for _, m in ipairs(mirrors[r.id] or {}) do ms[#ms + 1] = { kind = m.kind, side = m.side, face = m.face, normal = m.normal, width_cm = m.width_cm, height_cm = m.height_cm } end
  add({
    id = 'motel_' .. r.room_number .. '_' .. r.id, game_place = 'hotel', building = r.building, floor = r.floor,
    name = (r.building == 'S18' and '日式民宿 ' or '星澄汽車旅館 ') .. r.room_number .. ' ' .. (r.source_name or ''),
    kind = q.is_pool_suite and 'motel_pool_suite' or 'motel_suite', privacy = 2, lockable = true,
    door = r.entry,
    room = { center = W(0, 0, q.size_m[3] / 2), size = P(w * 100, d * 100, q.size_m[3] * 100), yaw = q.yaw },
    anchors = {
      { name = 'bed1_0', pos = W(bed[1], bed[2], top), yaw = r1(head - 90), note = 'bed centre on the mattress; headboard toward yaw+90' },
      { name = 'bath', pos = r.bath_eye, yaw = 0, note = 'bathroom standing point (vanity mirror face ' .. table.concat(r.mirror_face, ',') .. ')' },
      { name = 'stand', pos = r.eye, yaw = 0, note = 'supported standing point beside the bed' },
    },
    mirrors = ms,
    uses = uses,
  })
end

-- 2. Outdoor props from the actor dump.
local groups = {}
for _, a in ipairs(actors.actors) do
  local l, f, m = a.label, a.folder, a.mesh or ''
  local function put(k) groups[k] = groups[k] or {}; table.insert(groups[k], a) end
  if l:match('^Street_bench_') then put('bench')
  elseif m:match('^beach_lounger') then put('beach_lounger')
  elseif m:match('^beach_umbrella') then put('beach_umbrella')
  elseif m:match('^park_picnic_table') then put('picnic_table')
  elseif m:match('^landmark_gazebo') then put('gazebo')
  elseif m:match('^landmark_plaza_fountain') then put('fountain')
  elseif m:match('^landmark_cafe_set') then put('cafe_set')
  elseif m:match('^landmark_stage') then put('stage')
  elseif m:match('^landmark_lighthouse') then put('lighthouse')
  elseif m:match('^landmark_clock_tower') then put('clock_tower')
  elseif m:match('^landmark_playground') then put('playground')
  elseif l:match('^WorldGap_Grove_%d+_%d+$') then put('grove_tree')
  elseif l:match('^Activity_ACTSPACE') then put('actspace:' .. l:match('ACTSPACE%-%d+'))
  end
end
local outdoor = {
  bench = { 'park_bench', 0, { 'sit_pair', 'talk', 'kiss' } },
  beach_lounger = { 'beach_lounger', 0, { 'lie', 'sunbathe', 'sit_pair' } },
  picnic_table = { 'picnic_table', 0, { 'eat', 'sit_pair' } },
  gazebo = { 'gazebo', 1, { 'sit_pair', 'kiss', 'rain_shelter' } },
  fountain = { 'fountain', 0, { 'photo', 'walk' } },
  cafe_set = { 'outdoor_cafe_set', 0, { 'eat', 'drink', 'sit_pair' } },
  stage = { 'stage', 0, { 'watch', 'perform' } },
  lighthouse = { 'lighthouse', 1, { 'view', 'photo', 'kiss' } },
  clock_tower = { 'clock_tower', 0, { 'meet', 'photo' } },
  playground = { 'playground', 0, { 'play' } },
}
for k, spec in pairs(outdoor) do
  for i, a in ipairs(groups[k] or {}) do
    add({ id = k .. '_' .. i, label = a.label, kind = spec[1], privacy = spec[2], door = P(a.c[1], a.c[2], a.c[3] - a.e[3]),
      anchors = { { name = k, pos = P(a.c[1], a.c[2], a.c[3] - a.e[3]), yaw = r1(a.yaw) } }, uses = spec[3] })
  end
end
-- groves: secluded tree clumps on open lawns (privacy 1 outdoors; candidate outdoor-H spots if the game wants them)
local grove = {}
for _, a in ipairs(groups.grove_tree or {}) do local g = a.label:match('^WorldGap_Grove_(%d+)_'); grove[g] = grove[g] or {}; table.insert(grove[g], a) end
for g, list in pairs(grove) do
  local x, y, z = 0, 0, math.huge
  for _, a in ipairs(list) do x = x + a.c[1]; y = y + a.c[2]; z = math.min(z, a.c[3] - a.e[3]) end
  x, y = x / #list, y / #list
  local rad = 0; for _, a in ipairs(list) do rad = math.max(rad, math.sqrt((a.c[1] - x) ^ 2 + (a.c[2] - y) ^ 2)) end
  add({ id = 'grove_' .. g, kind = 'grove', privacy = 1, trees = #list, radius_cm = r1(rad), door = P(x, y, z),
    anchors = { { name = 'grove_center', pos = P(x, y, z), yaw = 0 } }, uses = { 'walk', 'picnic', 'kiss', 'h_outdoor_hidden' } })
end
for k, list in pairs(groups) do
  local pkg = k:match('^actspace:(.*)$')
  if pkg then
    local x, y, z = 0, 0, math.huge
    for _, a in ipairs(list) do x = x + a.c[1]; y = y + a.c[2]; z = math.min(z, a.c[3] - a.e[3]) end
    add({ id = pkg:lower(), kind = 'activity_scene', privacy = 0, props = #list, door = P(x / #list, y / #list, z), anchors = {}, uses = {} })
  end
end

-- 3. Building interiors. Furniture is baked into the per-floor meshes; its positions come from the assembly reports
-- (building-local metres, X east / Y north, yaw counter-clockwise from east, asset front = local -Y). World:
-- UE X = X0 + north*100, UE Y = Y0 + east*100, UE Z = 1200 + z*100 with (X0, Y0) the floor actor location. The front
-- of an asset faces UE yaw 180 - theta, so a person using it (facing its front) gets anchor yaw 90 - theta.
-- Room boxes and room doors come from the assembly manifest (places-v1/manifest-rooms.json, extracted once from
-- Docs/StreetSocialCity/production/assembly-manifest.json): room centre + rotation + clear size, door relative to it.
local planrooms = {}
local cityplan = load('../../Docs/StreetSocialCity/production/effective-city-plan.json')
for _, r in ipairs(cityplan.rooms) do planrooms[r.id] = r end
local bname = {}; for _, b in ipairs(cityplan.buildings) do bname[b.id] = b.name end
local mrooms = load('places-v1/manifest-rooms.json').rooms
local origin = {}
for _, a in ipairs(load('shop-survey-v1/city-floor-meshes.json')) do local b = a.actor:match('^%a+_(%w+)_F%d+$'); if b and not origin[b] then origin[b] = a.location end end
for _, a in ipairs(actors.actors) do local b = a.label:match('^(S%d+)_F01$'); if b and not origin[b] then origin[b] = a.loc end end
local function BW(b, x, y, z) local o = origin[b]; return P(o[1] + y * 100, o[2] + x * 100, 1200 + z * 100) end
local function rot2(x, y, deg) local a = math.rad(deg or 0); return x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a) end
-- room box (world AABB + oriented size) and the room door moved 60 cm into the room
local function roombox(id)
  local m = mrooms[id]; if not m or not origin[m.building] then return nil end
  local px, py, pz = m.position_m[1], m.position_m[2], m.position_m[3]; local w, d, h = m.clear_size_m[1], m.clear_size_m[2], m.clear_size_m[3]
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs({ { -w / 2, -d / 2 }, { w / 2, -d / 2 }, { w / 2, d / 2 }, { -w / 2, d / 2 } }) do
    local cx, cy = rot2(c[1], c[2], m.rotation_z_deg); local q = BW(m.building, px + cx, py + cy, pz)
    x0 = math.min(x0, q[1]); y0 = math.min(y0, q[2]); x1 = math.max(x1, q[1]); y1 = math.max(y1, q[2])
  end
  local box = { min = { r1(x0), r1(y0), r1(1200 + pz * 100) }, max = { r1(x1), r1(y1), r1(1200 + (pz + h) * 100) }, center = BW(m.building, px, py, pz), size_m = { w, d, h }, yaw = r1(90 - (m.rotation_z_deg or 0)) }
  local door
  if m.door then
    local dx, dy = rot2(m.door[1], m.door[2], m.rotation_z_deg); local L = math.sqrt(dx * dx + dy * dy)
    local k = L > 0 and (L - .6) / L or 0
    door = BW(m.building, px + dx * k, py + dy * k, pz)
  end
  return box, door, m
end
local function inbox(id, p) local m = mrooms[id]; if not m then return false end
  local o = origin[m.building]; local lx, ly = (p[2] - o[2]) / 100 - m.position_m[1], (p[1] - o[1]) / 100 - m.position_m[2]
  local rx, ry = rot2(lx, ly, -(m.rotation_z_deg or 0)); return math.abs(rx) <= m.clear_size_m[1] / 2 + .05 and math.abs(ry) <= m.clear_size_m[2] / 2 + .05 and math.abs((p[3] - 1200) / 100 - m.position_m[3]) < 2
end
local byfloor = {} -- building..floor -> manifest room ids
for id, m in pairs(mrooms) do local k = m.building .. ':' .. m.floor; byfloor[k] = byfloor[k] or {}; table.insert(byfloor[k], id) end
local ANCHOR = { -- asset -> anchor kind
  ['COMMON-CITY-bunk'] = 'bed', ['large-bunk'] = 'bed', ['COMMON-CITY-king'] = 'bed', ['bed'] = 'bed',
  ['COMMON-CITY-sofa'] = 'sofa', ['sofa'] = 'sofa', ['COMMON-CITY-lounge'] = 'sofa', ['large-lounger'] = 'lounger',
  ['COMMON-CITY-spa_basin'] = 'pool', ['large-spa-basin-v2'] = 'pool', ['COMMON-CITY-tub'] = 'bath',
  ['COMMON-CITY-dining'] = 'table', ['table'] = 'table', ['steel-table'] = 'table', ['COMMON-CITY-seat'] = 'seat', ['chair'] = 'seat', ['stool'] = 'seat',
  ['COMMON-CITY-shower'] = 'shower', ['shower'] = 'shower',
  ['service-counter'] = 'counter', ['steel-counter'] = 'counter', ['pos'] = 'counter', ['retail-case'] = 'counter', ['COMMON-CITY-checkout'] = 'counter',
  ['bookshelf'] = 'shelf', ['COMMON-CITY-shelf'] = 'shelf', ['retail-rack'] = 'aisle', ['fruit-bin'] = 'stand', ['display-plinth'] = 'pets',
  ['COMMON-SPORT-change_bench'] = 'seat', ['COMMON-WC-toilet'] = 'toilet', ['COMMON-WC-basin'] = 'washbasin', ['toilet'] = 'toilet', ['handwash'] = 'washbasin',
}
local PRIV = { dorm = 2, apartment = 2, suite = 2, deluxe = 2, executive = 2, inn = 2, nap = 1, spa = 1 }
local reports = {}
for _, dir in ipairs({ 'campus-v1/buildings', 'world-completion-v1/buildings' }) do
  for b in io.popen('ls -1 "' .. root .. dir .. '"'):lines() do
    if exists(root .. dir .. '/' .. b .. '/assembly-report.json') then reports[#reports + 1] = { b, dir .. '/' .. b .. '/assembly-report.json' } end
  end
end
for n = 1, 96 do
  local b = string.format('S%02d', n); local f = b .. '-modular-components-v1/assembly-building/assembly-report.json'
  if exists(root .. f) then reports[#reports + 1] = { b, f } end
end
local motel_floors = { H1 = { [2] = true, [3] = true, [4] = true, [5] = true } } -- replaced by the motel suites
local entry = {}  -- building -> street entrance (world)
local inst = {}   -- every anchor-kind instance: {b, floor, owner, kind, pos, yaw}
for _, rep in ipairs(reports) do
  local b = rep[1]
  if origin[b] then
    local R = load(rep[2])
    for _, d in ipairs(R.doors or {}) do if d.id == b .. '-entry-A' then entry[b] = BW(b, d.position_m[1], d.position_m[2], 0) end end
    for _, i in ipairs(R.instances or {}) do
      if not entry[b] and i.asset == 'entryframe' and i.position_m then entry[b] = BW(b, i.position_m[1], i.position_m[2], 0) end
      local kind = ANCHOR[i.asset]
      if kind and i.position_m and not (motel_floors[b] and motel_floors[b][i.floor]) then
        local theta = i.yaw_deg or math.deg(i.yaw_rad or 0)
        local pos = BW(b, i.position_m[1], i.position_m[2], i.position_m[3])
        local owner = i.owner
        if not owner or owner == b then for _, id in ipairs(byfloor[b .. ':' .. tostring(i.floor)] or {}) do if inbox(id, pos) then owner = id; break end end end
        inst[#inst + 1] = { b = b, floor = i.floor, owner = owner or (b .. '-F0' .. tostring(i.floor)), kind = kind, pos = pos, yaw = r1(90 - theta), asset = i.asset }
      end
    end
  end
end
-- classroom seats live in the functional-interior receipts (moved_seats, building-local 'after'); they face the board
for b in pairs(origin) do
  local lf = root .. 'functional-interiors-v1/buildings/' .. b .. '/latest.json'
  if exists(lf) then
    local rp = load('functional-interiors-v1/buildings/' .. b .. '/latest.json').receipt:gsub('\\', '/'):match('functional%-interiors%-v1/.*$')
    local R = rp and exists(root .. rp) and load(rp)
    if R then
      local gone = {}; for _, x in ipairs(R.removed_seats or {}) do gone[x.name] = true end
      for _, x in ipairs(R.moved_seats or {}) do
        local m = mrooms[x.room]
        if not gone[x.name] and m and x.after then
          local pos = BW(b, x.after[1], x.after[2], x.after[3])
          local bx, by = rot2(0, m.clear_size_m[2] / 2, m.rotation_z_deg); local board = BW(b, m.position_m[1] + bx, m.position_m[2] + by, 0)
          local face = math.deg(math.atan(board[2] - pos[2], board[1] - pos[1]))
          inst[#inst + 1] = { b = b, floor = m.floor, owner = x.room, kind = 'seat', pos = pos, yaw = r1(face - 90), asset = 'classroom-seat' }
        end
      end
    end
  end
end
local rooms = {}
for _, a in ipairs(inst) do
  if a.kind ~= 'toilet' and a.kind ~= 'washbasin' then
    rooms[a.owner] = rooms[a.owner] or { n = {}, list = {}, floor = a.floor, b = a.b }
    local R = rooms[a.owner]; R.n[a.kind] = (R.n[a.kind] or 0) + 1
    R.list[#R.list + 1] = { name = a.kind .. (R.n[a.kind] - 1) .. '_0', pos = a.pos, yaw = a.yaw, asset = a.asset }
  end
end
-- c-conquest 11-03: D1 (women's dorm) rooms need the resident's own invitation (sleep_rule)
for owner, R in pairs(rooms) do
  local b = R.b; local pr = planrooms[owner]
  local typ = pr and pr.type or (b == 'S18' and 'inn' or b == 'S19' and 'spa' or b:match('^S%d+$') and 'shop' or 'building_common')
  local priv = PRIV[typ] or 0
  local has = {}; for _, a in ipairs(R.list) do has[a.name:match('^(%a+)')] = true end
  if has.bed or has.sofa or has.pool or has.bath or has.lounger or priv > 0 or (typ == 'shop' and (has.seat or has.table)) then
    local box, door = roombox(owner)
    local x0, y0, x1, y1, z = math.huge, math.huge, -math.huge, -math.huge, math.huge
    for _, a in ipairs(R.list) do x0 = math.min(x0, a.pos[1]); y0 = math.min(y0, a.pos[2]); x1 = math.max(x1, a.pos[1]); y1 = math.max(y1, a.pos[2]); z = math.min(z, a.pos[3]) end
    if not box then box = { min = P(x0 - 150, y0 - 150, z), max = P(x1 + 150, y1 + 150, z + 320), note = 'furniture bounds + 1.5 m' } end
    if typ == 'shop' or typ == 'building_common' then door = entry[b] or door end
    local uses = {}
    if has.bed and typ ~= 'shop' then uses[#uses + 1] = 'sleep' end
    if has.seat or has.table then uses[#uses + 1] = 'sit_pair' end
    if has.bed and priv >= 2 then uses[#uses + 1] = 'h_bed' end
    if priv >= 2 then uses[#uses + 1] = 'h_floor'; uses[#uses + 1] = 'h_wall' end
    if has.sofa then uses[#uses + 1] = priv >= 2 and 'h_sofa' or 'sit_pair' end
    if has.pool or has.bath then uses[#uses + 1] = 'bath' end
    if has.lounger then uses[#uses + 1] = 'lie' end
    add({ id = owner:lower(), building = b, floor = R.floor, kind = 'room_' .. typ, name = pr and pr.name or ((bname[b] or b) .. (owner:match('%-F0%d$') or '')),
      privacy = priv, lockable = priv >= 2, sleep_rule = pr and pr.sleep or nil, needs_invite = (b == 'D1' and typ == 'dorm') or nil,
      door = door or P((x0 + x1) / 2, (y0 + y1) / 2, z), door_kind = door and ((typ == 'shop' or typ == 'building_common') and 'street_entrance' or 'room_door') or 'furniture_centre',
      room = box, anchors = R.list, uses = uses })
  end
end

-- 4. game_places: the StreetSocial place ids (activities.toml) mapped onto UniversityCity, with the anchor names the
-- game reads (c-conquest 11-03). Each entry: id, door (street entrance or arrival point), rooms (world AABBs), anchors.
-- New scene items (vending machines, the shrine, the convenience-store eat-in counter, dorm lounge sofas) come from the
-- latest world-edge-v1/lover-spots-install-*.json when it exists; until then those anchors are listed in `missing`.
local byid = {}; for _, p in ipairs(places) do byid[p.id] = p end
local alabel = {}; for _, a in ipairs(actors.actors) do alabel[a.label] = a end
local function abase(a) return P(a.c[1], a.c[2], a.c[3] - a.e[3]) end
local newitems = {}
do
  local last
  for name in io.popen('ls -1 "' .. root .. 'world-edge-v1" 2>nul'):lines() do
    if name:match('^lover%-spots%-install%-.*%.json$') and (not last or name > last) then last = name end
  end
  if last then for _, it in ipairs(load('world-edge-v1/' .. last).items or {}) do newitems[it.place .. ':' .. it.anchor] = it end end
end
-- building AABB over all its floor actors
local function bbox(b)
  local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
  for _, a in ipairs(actors.actors) do
    local m = a.label:match('^%a+_(%w+)_F%d+$') or a.label:match('^(S%d+)_F%d+$')
    if m == b then x0 = math.min(x0, a.c[1] - a.e[1]); y0 = math.min(y0, a.c[2] - a.e[2]); z0 = math.min(z0, a.c[3] - a.e[3]); x1 = math.max(x1, a.c[1] + a.e[1]); y1 = math.max(y1, a.c[2] + a.e[2]); z1 = math.max(z1, a.c[3] + a.e[3]) end
  end
  if x0 == math.huge then return nil end
  return { min = P(x0, y0, z0), max = P(x1, y1, z1) }
end
local function aroundbox(p, r) return { min = P(p[1] - r, p[2] - r, p[3] - 100), max = P(p[1] + r, p[2] + r, p[3] + 500) } end
-- anchors of a kind from the instance index, filtered by building / room / floor
local function pick(kind, f)
  local out = {}
  for _, a in ipairs(inst) do
    if a.kind == kind and (not f.b or a.b == f.b) and (not f.room or a.owner == f.room) and (not f.floor or a.floor == f.floor) then out[#out + 1] = a end
  end
  return out
end
local function roomcentre(id) local box, door = roombox(id); return box and box.center, door, box end
local G = {}
local function def(id, t) t.id = id; G[#G + 1] = t end
local function A(name, pos, yaw, src) return { name = name, pos = pos, yaw = yaw or 0, source = src } end
local function first(list, name, src) local a = list[1]; return a and A(name, a.pos, a.yaw, src or a.asset) or nil end
-- shops (S01-S08, S20): the street entrance is the door, the building is the room
local shops = { cafe = { 'S01', { counter = 'counter', seat = 'seat' } }, drinkshop = { 'S02', { counter = 'counter', seat = 'seat' } },
  snack = { 'S03', { counter = 'counter', table = 'table' } }, restaurant = { 'S04', { table = 'table' } }, fruitshop = { 'S05', { stand = 'stand' } },
  conveni = { 'S06', { aisle = 'aisle' } }, bookstore = { 'S07', { shelf = 'shelf', seat = 'seat' } }, petshop = { 'S08', { pets = 'pets' } }, lottery = { 'S20', {} } }
for id, s in pairs(shops) do
  local b = s[1]; local an = {}
  for name, kind in pairs(s[2]) do local l = pick(kind, { b = b, floor = 1 }); if not l[1] then l = pick(kind, { b = b }) end; an[#an + 1] = first(l, name) end
  def(id, { building = b, name = bname[b], door = entry[b], rooms = { bbox(b) }, anchors = an, privacy = 0 })
end
-- campus and dorms
local function roomplace(id, gid, roomid, wants, extra)
  local c, door, box = roomcentre(roomid); local an = {}
  for name, kind in pairs(wants) do an[#an + 1] = first(pick(kind, { room = roomid }), name) end
  for _, e in ipairs(extra or {}) do an[#an + 1] = e end
  return { building = mrooms[roomid] and mrooms[roomid].building, name = planrooms[roomid] and planrooms[roomid].name, door = door or c, rooms = { box }, anchors = an }
end
local t = roomplace('library', 'library', 'LI-0101', {}, { first(pick('seat', { b = 'LI' }), 'seat'), (function() local c = roomcentre('LI-0201'); return c and A('shelf', c, 0, 'LI-0201 文學書庫') end)() }); t.door = entry.LI or t.door; t.rooms = { bbox('LI') }; t.privacy = 0; def('library', t)
t = roomplace('cafeteria', 'cafeteria', 'SC-0101', { table = 'table' }); t.door = entry.SC or t.door; t.rooms = { bbox('SC') }; t.privacy = 0; def('cafeteria', t)
do -- school = T1 (two classrooms) + the SC music club room
  local seats = pick('seat', { b = 'T1', floor = 1 }); local rooms1 = {}
  for _, a in ipairs(seats) do rooms1[a.owner] = rooms1[a.owner] or a end
  local ids = {}; for k in pairs(rooms1) do ids[#ids + 1] = k end; table.sort(ids)
  local mc, md = roomcentre('SC-0301')
  local an = { ids[1] and A('seat', rooms1[ids[1]].pos, rooms1[ids[1]].yaw, ids[1]) or nil, ids[2] and A('class2', rooms1[ids[2]].pos, rooms1[ids[2]].yaw, ids[2]) or nil, mc and A('music', md or mc, 0, 'SC-0301 音樂社練習室') or nil }
  def('school', { building = 'T1', name = bname.T1, door = entry.T1, rooms = { bbox('T1') }, anchors = an, privacy = 0 })
end
do local s = pick('seat', { b = 'T2', floor = 1 }); def('lecture', { building = 'T2', name = bname.T2, door = entry.T2, rooms = { bbox('T2') }, anchors = { first(s, 'seat') }, privacy = 0 }) end
do -- campus_sports = SP with the outdoor track as the field
  local tr = alabel['Outdoor_campus_track']
  def('campus_sports', { building = 'SP', name = bname.SP, door = entry.SP, rooms = { bbox('SP'), tr and { min = P(tr.c[1] - tr.e[1], tr.c[2] - tr.e[2], tr.c[3] - tr.e[3]), max = P(tr.c[1] + tr.e[1], tr.c[2] + tr.e[2], tr.c[3] + tr.e[3] + 300) } or nil },
    anchors = { first(pick('seat', { b = 'SP' }), 'seat'), tr and A('field', abase(tr), 0, 'Outdoor_campus_track') or nil }, privacy = 0 })
end
do local pg = alabel['Landmark_playground_a_98'] or alabel['Landmark_playground_b_99']
  for l, a in pairs(alabel) do if not pg and l:match('^Landmark_playground') then pg = a end end
  if pg then def('playground', { name = '遊樂場', door = abase(pg), rooms = { aroundbox(abase(pg), 1500) }, anchors = { A('field', abase(pg), r1(pg.yaw), pg.label) }, privacy = 0 }) end
end
do local gates = {}; for l, a in pairs(alabel) do if l:match('campus%-gate$') then gates[#gates + 1] = a end end
  table.sort(gates, function(a, b) return a.label < b.label end)
  local g = gates[1]; if g then def('campus_gate', { name = '校門', door = abase(g), rooms = { aroundbox(abase(g), 1200) }, anchors = { A('gate', abase(g), r1(g.yaw), g.label) }, privacy = 0 }) end
end
-- dorms: girls D1, boys D2 (his room: the first D2 dorm room with beds)
for id, b in pairs({ girls_dorm = 'D1', boys_dorm = 'D2' }) do
  local lc, ld = roomcentre(b .. '-0102')
  local an = { lc and A('lounge', lc, 0, b .. '-0102 訪客交誼廳') or nil }
  if b == 'D2' then
    local beds = pick('bed', { b = 'D2' }); table.sort(beds, function(x, y) return x.owner < y.owner end)
    for _, bd in ipairs(beds) do if planrooms[bd.owner] and planrooms[bd.owner].type == 'dorm' then an[#an + 1] = A('bed3_0', bd.pos, bd.yaw, bd.owner); break end end
  end
  def(id, { building = b, name = bname[b], door = entry[b], rooms = { bbox(b) }, anchors = an, privacy = b == 'D2' and 2 or 0, note = b == 'D1' and 'rooms: privacy 2 only when she lives there or invites him (sleep_rule)' or nil })
end
-- hotel = H1 (lobby on F01, a motel suite as room6 / bed6_1, a pool suite's pool); lodge = the four pool suites
do
  local lobby = pick('sofa', { b = 'H1', floor = 1 })
  local suite, pool
  for _, p in ipairs(places) do
    if p.kind == 'motel_suite' and not suite and p.building == 'H1' then suite = p end
    if p.kind == 'motel_pool_suite' and not pool then pool = p end
  end
  local an = { first(lobby, 'lobby'), lobby[2] and A('bar', lobby[2].pos, lobby[2].yaw, 'H1 F01 lounge') or nil }
  if suite then an[#an + 1] = A('room6', suite.door, 0, suite.id); an[#an + 1] = A('bed6_1', suite.anchors[1].pos, suite.anchors[1].yaw, suite.id) end
  if pool then an[#an + 1] = A('pool', pool.room.center, 0, pool.id .. ' (pool suite)') end
  def('hotel', { building = 'H1', name = bname.H1, door = entry.H1, rooms = { bbox('H1') }, anchors = an, privacy = 1, note = 'game leads to hotel_rest; every motel_* place itself is privacy 2' })
  local lodges = {}
  for _, p in ipairs(places) do if p.kind == 'motel_pool_suite' then lodges[#lodges + 1] = p end end
  local l = lodges[1]
  if l then def('lodge', { building = 'H1', name = '泳池套房（' .. l.name .. '）', door = l.door, rooms = { { center = l.room.center, size = l.room.size, yaw = l.room.yaw } },
    anchors = { A('bed2_0', l.anchors[1].pos, l.anchors[1].yaw, l.id), A('seat', l.anchors[3].pos, 0, l.id), A('lounge2', l.room.center, 0, l.id) }, privacy = 2, alternates = (function() local o = {}; for k = 2, #lodges do o[#o + 1] = lodges[k].id end; return o end)() }) end
end
do -- minshuku = S18, onsen = S19
  local s18 = pick('bed', { b = 'S18' })
  def('minshuku', { building = 'S18', name = bname.S18, door = entry.S18, rooms = { bbox('S18') }, anchors = { first(pick('sofa', { b = 'S18' }), 'seat'), first(s18, 'bed1_0') }, privacy = 2 })
  def('onsen', { building = 'S19', name = bname.S19, door = entry.S19, rooms = { bbox('S19') }, anchors = { first(pick('pool', { b = 'S19' }), 'pool') }, privacy = 1 })
end
do -- department = M1 (shop rooms by floor theme; the 8F bear from the activity scene)
  local an = {}
  for name, rid in pairs({ beauty = 'M1-0102', mirror2 = 'M1-0201', mirror3 = 'M1-0301', shoes = 'M1-0401', sofa = 'M1-0501', books = 'M1-0601', phones = 'M1-0701', food = 'M1-0901', view = 'M1-1006' }) do
    local c, d = roomcentre(rid); if c then an[#an + 1] = A(name, c, 0, rid .. ' ' .. (planrooms[rid] and planrooms[rid].name or '')) end
  end
  local bear = alabel['Activity_ACTSPACE-01-1']; if bear then an[#an + 1] = A('bear', abase(bear), r1(bear.yaw), bear.label) end
  local _, mdoor = roomcentre('M1-0101')
  def('department', { building = 'M1', name = bname.M1, door = entry.M1 or mdoor, rooms = { bbox('M1') }, anchors = an, privacy = 0 })
end
do -- park = the fountain plaza; aquarium = the koi pond (ACTSPACE-06)
  local f = alabel['Landmark_plaza_fountain_0']; local pond = alabel['Activity_ACTSPACE-06-76']
  local an = {}
  if f then an[#an + 1] = A('fountain', abase(f), r1(f.yaw), f.label); an[#an + 1] = A('plaza', abase(f), 0, f.label) end
  if pond then an[#an + 1] = A('pond', abase(pond), r1(pond.yaw), pond.label) end
  if f then local best, bd = nil, math.huge
    for l, a in pairs(alabel) do if l:match('^Street_bench_') then local d = (a.c[1] - f.c[1]) ^ 2 + (a.c[2] - f.c[2]) ^ 2; if d < bd then best, bd = a, d end end end
    if best then an[#an + 1] = A('bench', abase(best), r1(best.yaw), best.label) end
    def('park', { name = '中央公園', door = abase(f), rooms = { aroundbox(abase(f), 6000) }, anchors = an, privacy = 0 }) end
  if pond then local best, bd = nil, math.huge
    for l, a in pairs(alabel) do if l:match('^Street_bench_') or (a.mesh or ''):match('^park_picnic') then local d = (a.c[1] - pond.c[1]) ^ 2 + (a.c[2] - pond.c[2]) ^ 2; if d < bd then best, bd = a, d end end end
    def('aquarium', { name = '錦鯉池', door = abase(pond), rooms = { aroundbox(abase(pond), 2000) }, anchors = { A('tank', abase(pond), r1(pond.yaw), pond.label), best and A('bench', abase(best), r1(best.yaw), best.label) or nil }, privacy = 0, note = 'no aquarium in the city: the koi pond (ACTSPACE-06) stands in' }) end
end
-- restrooms: public WC basins (wait) / toilets (women) in four buildings spread over the map
for id, b in pairs({ restroom_campus = 'SC', restroom_north = 'D3', restroom_park = 'CV', restroom_resort = 'H1' }) do
  local w = pick('washbasin', { b = b, floor = 1 }); local tl = pick('toilet', { b = b, floor = 1 })
  if w[1] then def(id, { building = b, name = (bname[b] or b) .. ' 1F 廁所', door = w[1].pos, rooms = { aroundbox(w[1].pos, 800) }, anchors = { A('wait', w[1].pos, w[1].yaw, w[1].asset), tl[#tl] and A('women', tl[#tl].pos, tl[#tl].yaw, tl[#tl].asset) or nil }, privacy = 1 }) end
end
-- shrine: built by the lover-spots install (torii + pray)
def('shrine', { name = '小神社', anchors = {}, privacy = 0 })
-- new scene items and the anchors the game wants that are still missing
local wants = { aquarium = { 'tank', 'vending', 'bench' }, boys_dorm = { 'lounge', 'vending', 'bed3_0' }, girls_dorm = { 'lounge', 'vending' }, cafeteria = { 'table', 'vending' },
  department = { 'beauty', 'mirror2', 'mirror3', 'shoes', 'sofa', 'books', 'phones', 'bear', 'food', 'view', 'vending' }, hotel = { 'room6', 'pool', 'bar', 'lobby', 'vending', 'bed6_1' },
  library = { 'seat', 'shelf', 'vending' }, lodge = { 'lounge2', 'seat', 'vending', 'bed2_0' }, park = { 'bench', 'fountain', 'pond', 'plaza', 'vending' },
  playground = { 'field', 'vending' }, school = { 'seat', 'class2', 'music', 'vending' }, shrine = { 'torii', 'pray' }, conveni = { 'aisle', 'seat', 'table' } }
for _, g in ipairs(G) do
  local have = {}; local an = {}
  for _, a in pairs(g.anchors) do if a then have[a.name] = true; an[#an + 1] = a end end
  for _, name in ipairs(wants[g.id] or {}) do
    local it = newitems[g.id .. ':' .. name]
    if not have[name] and it then an[#an + 1] = A(name, it.pos, it.yaw, it.actor); have[name] = true; if g.id == 'shrine' and name == 'torii' then g.door = it.pos; g.rooms = { aroundbox(it.pos, 1500) } end end
  end
  g.anchors = an
  local miss = {}; for _, name in ipairs(wants[g.id] or {}) do if not have[name] then miss[#miss + 1] = name end end
  if #miss > 0 then g.missing = miss end
end
table.sort(G, function(a, b) return a.id < b.id end)
GAME_PLACES = G

table.sort(places, function(a, b) return a.id < b.id end)
local out = assert(io.open(root .. 'places-v1/places.json', 'wb'))
out:write(json.encode({ schema = 1, map_sha256 = actors.map_sha256, frame = 'UE cm, +X north, +Y east; anchor yaw: character faces yaw+90', mirrors_from = latest, places = places, game_places = GAME_PLACES }))
out:close()
local count = {}; for _, p in ipairs(places) do count[p.kind] = (count[p.kind] or 0) + 1 end
for k, v in pairs(count) do print(k, v) end
print('wrote ' .. root .. 'places-v1/places.json', #places)
