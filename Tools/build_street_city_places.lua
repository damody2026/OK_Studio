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
local planrooms = {}
for _, r in ipairs(load('../../Docs/StreetSocialCity/production/effective-city-plan.json').rooms) do planrooms[r.id] = r end
local origin = {}
for _, a in ipairs(load('shop-survey-v1/city-floor-meshes.json')) do local b = a.actor:match('^%a+_(%w+)_F%d+$'); if b and not origin[b] then origin[b] = a.location end end
for _, a in ipairs(load('shop-survey-v1/actor-bounds.json').rows) do local b = a.actor:match('^(S%d+)_F%d+$'); if b and not origin[b] then origin[b] = a.location end end
local ANCHOR = { -- asset -> anchor name prefix, uses
  ['COMMON-CITY-bunk'] = 'bed', ['large-bunk'] = 'bed', ['COMMON-CITY-king'] = 'bed', ['bed'] = 'bed',
  ['COMMON-CITY-sofa'] = 'sofa', ['sofa'] = 'sofa', ['COMMON-CITY-lounge'] = 'sofa', ['large-lounger'] = 'lounger',
  ['COMMON-CITY-spa_basin'] = 'pool', ['large-spa-basin-v2'] = 'pool', ['COMMON-CITY-tub'] = 'bath',
  ['COMMON-CITY-dining'] = 'table', ['table'] = 'table', ['COMMON-CITY-seat'] = 'seat', ['chair'] = 'seat',
  ['COMMON-CITY-shower'] = 'shower', ['shower'] = 'shower',
}
-- room types the game can treat as lockable (privacy 2: H allowed) or semi-private (1)
local PRIV = { dorm = 2, apartment = 2, suite = 2, deluxe = 2, executive = 2, inn = 2, nap = 1, spa = 1 }
local reports = {}
for _, dir in ipairs({ 'campus-v1/buildings', 'world-completion-v1/buildings' }) do
  for b in io.popen('ls -1 "' .. root .. dir .. '"'):lines() do
    if exists(root .. dir .. '/' .. b .. '/assembly-report.json') then reports[#reports + 1] = { b, dir .. '/' .. b .. '/assembly-report.json' } end
  end
end
for _, b in ipairs({ 'S18', 'S19' }) do reports[#reports + 1] = { b, b .. '-modular-components-v1/assembly-building/assembly-report.json' } end
local motel_floors = { H1 = { [2] = true, [3] = true, [4] = true, [5] = true } } -- replaced by the motel suites
for _, rep in ipairs(reports) do
  local b, o = rep[1], origin[rep[1]]
  if o then
    local rooms = {}
    for _, i in ipairs(load(rep[2]).instances or {}) do
      local kind = ANCHOR[i.asset]
      local owner = i.owner or (b .. '-F0' .. tostring(i.floor))
      if kind and not (motel_floors[b] and motel_floors[b][i.floor]) then
        local p = i.position_m
        local wx, wy, wz = o[1] + p[2] * 100, o[2] + p[1] * 100, 1200 + p[3] * 100
        rooms[owner] = rooms[owner] or { n = {}, list = {}, floor = i.floor }
        local R = rooms[owner]; R.n[kind] = (R.n[kind] or 0) + 1
        R.list[#R.list + 1] = { name = kind .. (R.n[kind] - 1) .. '_0', pos = P(wx, wy, wz), yaw = r1(90 - (i.yaw_deg or 0)), asset = i.asset }
      end
    end
    for owner, R in pairs(rooms) do
      local pr = planrooms[owner]
      local typ = pr and pr.type or (b == 'S18' and 'inn' or b == 'S19' and 'spa' or 'building_common')
      local priv = PRIV[typ] or 0
      local has = {}; for _, a in ipairs(R.list) do has[a.name:match('^(%a+)')] = true end
      if has.bed or has.sofa or has.pool or has.bath or has.lounger or priv > 0 then
        local x0, y0, x1, y1, z = math.huge, math.huge, -math.huge, -math.huge, math.huge
        for _, a in ipairs(R.list) do x0 = math.min(x0, a.pos[1]); y0 = math.min(y0, a.pos[2]); x1 = math.max(x1, a.pos[1]); y1 = math.max(y1, a.pos[2]); z = math.min(z, a.pos[3]) end
        local uses = {}
        if has.bed then uses[#uses + 1] = 'sleep' end
        if has.bed and priv >= 2 then uses[#uses + 1] = 'h_bed' end
        if priv >= 2 then uses[#uses + 1] = 'h_floor'; uses[#uses + 1] = 'h_wall' end
        if has.sofa then uses[#uses + 1] = priv >= 2 and 'h_sofa' or 'sit_pair' end
        if has.pool or has.bath then uses[#uses + 1] = 'bath' end
        if has.lounger then uses[#uses + 1] = 'lie' end
        add({ id = owner:lower(), building = b, floor = R.floor, kind = 'room_' .. typ, name = pr and pr.name or owner,
          privacy = priv, lockable = priv >= 2, sleep_rule = pr and pr.sleep or nil,
          door = P((x0 + x1) / 2, (y0 + y1) / 2, z),
          room = { min = P(x0 - 150, y0 - 150, z), max = P(x1 + 150, y1 + 150, z + 320), note = 'furniture bounds + 1.5 m' },
          anchors = R.list, uses = uses })
      end
    end
  end
end
table.sort(places, function(a, b) return a.id < b.id end)
local out = assert(io.open(root .. 'places-v1/places.json', 'wb'))
out:write(json.encode({ schema = 1, map_sha256 = actors.map_sha256, frame = 'UE cm, +X north, +Y east; anchor yaw: character faces yaw+90', mirrors_from = latest, places = places }))
out:close()
local count = {}; for _, p in ipairs(places) do count[p.kind] = (count[p.kind] or 0) + 1 end
for k, v in pairs(count) do print(k, v) end
print('wrote ' .. root .. 'places-v1/places.json', #places)
