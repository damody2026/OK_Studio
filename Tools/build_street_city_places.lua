-- UniversityCity place inventory for the StreetSocial game (Docs/STREET_CITY_PLACES_INVENTORY_20261103.md).
--   Tools\lua\lua.exe Tools\build_street_city_places.lua
-- Inputs (all under output/street-social-city-production/):
--   places-v1/actors.json                 world_places_probe dump (Tools/street_city_places_payload.lua)
--   motel-v1/motel-install.json, motel-plan.json, sample-rooms/models-v2/<id>/build.json
--   world-edge-v1/bed-mirrors-install-*.json (latest)
-- Output: places-v1/places.json and places-v1/props.json (section 5). Coordinates are UE cm, +X north, +Y east (the game's frame). Anchor yaw follows the
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
  -- sample rooms whose bed is not at the shell default (Tools/build_street_city_motel_sample_rooms.lua: 209 canopy_bed, 203 bx = w*.14)
  if r.id == 'imore-93474c507aaf' then bed = { 1.6, 5.15 } elseif r.id == 'imore-cda5d5e2dcb9' then bed = { q.size_m[1] * .14, 4.7 } end
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
-- street benches, bins, cycle racks and bus shelters are merged into city-wide cluster actors; their real positions come
-- from the street-dressing plan fitted onto the world curbs (Tools/street_city_anchors.lua)
local STREET = dofile('Tools/street_city_anchors.lua')().A.anchors
groups.bench = {}
for _, id in ipairs({ 'bench_oak', 'bench_stone' }) do
  for i, q in ipairs(STREET[id] or {}) do table.insert(groups.bench, { label = id .. '_' .. i, c = { q[1], q[2], 1199 }, e = { 0, 0, 0 }, yaw = (q[4] or 0) - 90 }) end
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
  if last then local inst_ = load('world-edge-v1/' .. last); for _, it in ipairs(inst_.items or {}) do newitems[it.place .. ':' .. it.anchor] = it end; LOTS = inst_.lots end
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
  -- class2 = "the second-floor classroom" (c-conquest 11-03): the first seat on T1 2F
  local s2 = pick('seat', { b = 'T1', floor = 2 }); table.sort(s2, function(x, y) return x.owner < y.owner end); local c2 = s2[1]
  local an = { ids[1] and A('seat', rooms1[ids[1]].pos, rooms1[ids[1]].yaw, ids[1]) or nil, c2 and A('class2', c2.pos, c2.yaw, c2.owner) or nil, mc and A('music', md or mc, 0, 'SC-0301 音樂社練習室') or nil }
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
-- dorms: girls D1, boys D2 (his room: the first D2 dorm room with beds on 3F, the activity's "third-floor room")
for id, b in pairs({ girls_dorm = 'D1', boys_dorm = 'D2' }) do
  local lc, ld = roomcentre(b .. '-0102')
  local an = { lc and A('lounge', lc, 0, b .. '-0102 訪客交誼廳') or nil }
  if b == 'D2' then
    local beds = pick('bed', { b = 'D2' }); table.sort(beds, function(x, y) return x.owner < y.owner end)
    for _, bd in ipairs(beds) do if planrooms[bd.owner] and planrooms[bd.owner].type == 'dorm' and mrooms[bd.owner] and mrooms[bd.owner].floor == 3 then an[#an + 1] = A('bed3_0', bd.pos, bd.yaw, bd.owner); break end end
  else -- D1: the heroines' home; one bed per dorm room, each heroine in her own (OKStreetSocialSchedule.inl sorts by name)
    local beds = pick('bed', { b = 'D1' }); table.sort(beds, function(x, y) return x.owner < y.owner end)
    local seen, n = {}, 0
    for _, bd in ipairs(beds) do
      if n < 16 and not seen[bd.owner] and planrooms[bd.owner] and planrooms[bd.owner].type == 'dorm' and mrooms[bd.owner] then
        seen[bd.owner] = true; an[#an + 1] = A(string.format('bed%d_%02d', mrooms[bd.owner].floor, n), bd.pos, bd.yaw, bd.owner); n = n + 1
      end
    end
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
-- campus_* = the college buildings (effective-city-plan legacy_place), with the anchors the game's campus code reads
-- (OKStreetSocialCampus.inl, Tools/street_models/campus.py): 'stairK' on every floor (stair core A), 'liftK:label'
-- (1.6 m in front of shaft A, yaw = out of the shaft), 'classK_R' (K 2..5: the R-th classroom on floor K) and
-- 'office_<dept>' (department_offices). The dorms get stairK / liftK too. Cores come from building-floor-audit.json.
do
  local audit = load('../../Docs/StreetSocialCity/production/building-floor-audit.json')
  local circ = {}; for _, b in ipairs(audit.buildings) do circ[b.id] = b.floors end
  local function cores(b, an)
    for _, fl in ipairs(circ[b] or {}) do
      local k = fl.floor; local c = fl.circulation or {}
      for _, s in ipairs(c.stairs or {}) do if s.core == 'A' then an[#an + 1] = A('stair' .. k, BW(b, s.position_m[1], s.position_m[2], fl.z_m), 0, s.id); break end end
      for _, l in ipairs(c.lifts or {}) do
        if l.core == 'A' and not l.service and l.landing_position_m then
          local sx, sy = l.position_m[1], l.position_m[2]; local dx, dy = l.landing_position_m[1] - sx, l.landing_position_m[2] - sy
          local L = math.sqrt(dx * dx + dy * dy); if L > 0 then dx, dy = dx / L, dy / L end
          -- building-local X east / Y north -> UE yaw (X north, Y east)
          an[#an + 1] = A('lift' .. k .. ':' .. k .. 'F', BW(b, sx + dx * 1.6, sy + dy * 1.6, fl.z_m), r1(math.deg(math.atan(dx, dy))), l.id); break
        end
      end
    end
  end
  local offices = {}; for _, o in ipairs(cityplan.department_offices or {}) do offices[o.building] = offices[o.building] or {}; table.insert(offices[o.building], o) end
  -- the administration counters (OKCampusOfficeName: registrar / aa / student; any other id = general education)
  for _, o in ipairs({ { 'AD', 'registrar', 'AD-0102' }, { 'AD', 'aa', 'AD-0103' }, { 'AD', 'student', 'AD-0201' }, { 'T1', 'general', 'T1-0106' } }) do
    offices[o[1]] = offices[o[1]] or {}; table.insert(offices[o[1]], { department_id = o[2], room = o[3], department = planrooms[o[3]] and planrooms[o[3]].name or '' })
  end
  for _, b in ipairs(cityplan.buildings) do
    local gid = b.legacy_place
    if type(gid) == 'string' and gid:match('^campus_') then
      local an = {}
      cores(b.id, an)
      for k = 2, 5 do
        local ids = {}; for _, rid in ipairs(b.room_ids or {}) do local r = planrooms[rid]; if r and r.type == 'class' and mrooms[rid] and mrooms[rid].floor == k then ids[#ids + 1] = rid end end
        table.sort(ids)
        for r = 1, math.min(4, #ids) do
          local seat = pick('seat', { room = ids[r] })[1]; local c, d = roomcentre(ids[r])
          if seat then an[#an + 1] = A('class' .. k .. '_' .. r, seat.pos, seat.yaw, ids[r]) elseif c then an[#an + 1] = A('class' .. k .. '_' .. r, d or c, 0, ids[r]) end
        end
      end
      for _, o in ipairs(offices[b.id] or {}) do local c, d = roomcentre(o.room); if c then an[#an + 1] = A('office_' .. o.department_id, d or c, 0, o.room .. ' ' .. o.department) end end
      def(gid, { building = b.id, name = bname[b.id], door = entry[b.id], rooms = { bbox(b.id) }, anchors = an, privacy = 0 })
    end
  end
  -- the other multi-storey game places (department 9F/10F, hotel 6F, school 2F/3F, dorms) get the same, plus 'hall':
  -- the ground-floor lobby point 2 m out from the lift landing that the outing route walks through to the lift
  local multi = { girls_dorm = true, boys_dorm = true, department = true, hotel = true, school = true, lecture = true }
  for _, g in ipairs(G) do
    if multi[g.id] or (g.id:match('^campus_') and g.building) then
      if multi[g.id] then cores(g.building, g.anchors) end
      for _, a in pairs(g.anchors) do
        if a and a.name:match('^lift1:') then local r = math.rad(a.yaw); g.anchors[#g.anchors + 1] = A('hall', P(a.pos[1] + math.cos(r) * 200, a.pos[2] + math.sin(r) * 200, a.pos[3]), a.yaw, 'lobby before ' .. a.source); break end
      end
    end
  end
end
-- shrine: built by the lover-spots install (torii + pray)
def('shrine', { name = '小神社', anchors = {}, privacy = 0 })
-- new scene items and the anchors the game wants that are still missing
local wants = { aquarium = { 'tank', 'vending', 'bench' }, boys_dorm = { 'lounge', 'game', 'vending', 'bed3_0' }, girls_dorm = { 'lounge', 'game', 'vending' }, cafeteria = { 'table', 'vending' },
  department = { 'beauty', 'mirror2', 'mirror3', 'shoes', 'sofa', 'books', 'phones', 'bear', 'food', 'view', 'vending' }, hotel = { 'room6', 'pool', 'bar', 'lobby', 'vending', 'bed6_1' },
  library = { 'seat', 'shelf', 'vending' }, lodge = { 'lounge2', 'seat', 'vending', 'bed2_0' }, park = { 'bench', 'fountain', 'pond', 'plaza', 'vending' },
  playground = { 'field', 'vending' }, school = { 'seat', 'class2', 'music', 'vending' }, shrine = { 'torii', 'pray' }, conveni = { 'aisle', 'seat', 'table' } }
-- c-conquest 11-03: aquarium = the converted shop S28 (not the koi pond); lodge = a shared lounge outside the pool suites
local OVERRIDE = { ['aquarium:tank'] = true, ['aquarium:bench'] = true, ['lodge:lounge2'] = true, ['lodge:seat'] = true }
local aq = newitems['aquarium:door']
for _, g in ipairs(G) do
  if g.id == 'aquarium' and aq then g.building = aq.building; g.name = '水族館（S28 改建）'; g.door = aq.pos; g.rooms = aq.rooms; g.note = nil end
  local have = {}; local an = {}
  for _, a in pairs(g.anchors) do if a then have[a.name] = true; an[#an + 1] = a end end
  for _, name in ipairs(wants[g.id] or {}) do
    local it = newitems[g.id .. ':' .. name]
    if it and OVERRIDE[g.id .. ':' .. name] then for k = #an, 1, -1 do if an[k].name == name then table.remove(an, k) end end; have[name] = nil end
    if not have[name] and it then an[#an + 1] = A(name, it.pos, it.yaw, it.actor); have[name] = true; if g.id == 'shrine' and name == 'torii' then g.door = it.pos; g.rooms = { aroundbox(it.pos, 1500) } end end
  end
  g.anchors = an
  local miss = {}; for _, name in ipairs(wants[g.id] or {}) do if not have[name] then miss[#miss + 1] = name end end
  if #miss > 0 then g.missing = miss end
end
-- other install items: anchors the wants list does not name (conveni counter, lottery counter / buy / screen) join their
-- place; a place the game does not have yet (livehouse, karaoke) comes from its 'door' item (building, name, rooms)
do
  local byid = {}; for _, g in ipairs(G) do byid[g.id] = g end
  local keys = {}; for k in pairs(newitems) do keys[#keys + 1] = k end; table.sort(keys)
  for _, k in ipairs(keys) do local it = newitems[k]
    if it.anchor == 'door' and not byid[it.place] and it.rooms then
      byid[it.place] = { id = it.place, building = it.building, name = it.name, door = it.pos, rooms = it.rooms, anchors = {}, privacy = it.place == 'karaoke' and 1 or 0, new_place = true }
      G[#G + 1] = byid[it.place]
    end
  end
  for _, k in ipairs(keys) do local it = newitems[k]; local g = byid[it.place]
    if g and it.anchor ~= 'door' then
      local have = false; for _, a in pairs(g.anchors) do if a and a.name == it.anchor then have = true end end
      if not have then g.anchors[#g.anchors + 1] = A(it.anchor, it.pos, it.yaw, it.actor) end
    end
  end
end
-- new-game spawn (c-conquest Q16): 3 m out from the boys' dorm entrance, away from the building, facing the door
for _, g in ipairs(G) do
  local whole = g.id == 'boys_dorm' and g.door and bbox(g.building)
  if whole then
    local cx, cy = (whole.min[1] + whole.max[1]) / 2, (whole.min[2] + whole.max[2]) / 2
    local dx, dy = g.door[1] - cx, g.door[2] - cy; local L = math.sqrt(dx * dx + dy * dy); dx, dy = dx / L, dy / L
    -- snap the push to the facade the door is on (the longer side of the offset)
    if math.abs(dx) > math.abs(dy) then dx, dy = dx > 0 and 1 or -1, 0 else dx, dy = 0, dy > 0 and 1 or -1 end
    g.anchors[#g.anchors + 1] = A('spawn', P(g.door[1] + dx * 300, g.door[2] + dy * 300, g.door[3]), r1(math.deg(math.atan(-dy, -dx)) - 90), 'outside ' .. g.building .. '-entry-A')
  end
end
-- multi-storey buildings: one room box per floor (the game derives RoomLevels from the boxes' floor heights and uses
-- them for "which floor am I on" and the lift route), from the building box and the manifest floor heights
local mbuild = load('places-v1/manifest-rooms.json').buildings
for _, g in ipairs(G) do
  local fl = g.building and mbuild[g.building] and mbuild[g.building].floors; local whole = g.building and bbox(g.building)
  if fl and #fl > 1 and whole and #g.rooms == 1 and g.rooms[1].min and g.rooms[1].min[1] == whole.min[1] and g.rooms[1].max[2] == whole.max[2] then
    local boxes = {}
    for k, f in ipairs(fl) do
      local z0 = 1200 + f.z_m * 100; local z1 = fl[k + 1] and 1200 + fl[k + 1].z_m * 100 or whole.max[3]
      boxes[#boxes + 1] = { min = P(whole.min[1], whole.min[2], z0 - 30), max = P(whole.max[1], whole.max[2], z1 - 30), floor = k }
    end
    g.rooms = boxes
  end
end
table.sort(G, function(a, b) return a.id < b.id end)
GAME_PLACES = G

-- 5. Prop index (places-v1/props.json) for "what is around her": every usable or talkable object in the city with its
-- kind, position and the area (room / outdoor place / building) it belongs to. The game loads it once and answers
-- radius queries (10 m / 20 m) through a 10 m grid (Tools/ok-city-props). Kinds carry a Chinese name and what she can
-- do with them; positions are the object base (mirrors: the glass face), `face` is the world yaw the front looks to.
local KIND = { -- id = { zh, category, uses }
  bed = { '床', 'furniture', { 'sleep', 'lie', 'sit' } }, bunk_bed = { '上下舖', 'furniture', { 'sleep', 'lie', 'sit' } }, double_bed = { '雙人床', 'furniture', { 'sleep', 'lie', 'sit' } },
  sofa = { '沙發', 'furniture', { 'sit', 'lie', 'cuddle' } }, chair = { '椅子', 'furniture', { 'sit' } }, bench = { '長椅', 'furniture', { 'sit', 'cuddle' } },
  study_desk = { '課桌', 'furniture', { 'sit', 'study' } }, desk = { '書桌', 'furniture', { 'sit', 'study' } }, table = { '桌子', 'furniture', { 'sit', 'eat' } },
  cabinet = { '矮櫃', 'furniture', {} }, wardrobe = { '衣櫃', 'furniture', { 'change_clothes' } }, locker = { '置物櫃', 'furniture', { 'store' } },
  bookshelf = { '書架', 'furniture', { 'read' } }, lectern = { '講台', 'furniture', { 'stand', 'teach' } }, computer = { '電腦', 'device', { 'use' } },
  tv = { '電視和遊戲機', 'device', { 'watch', 'play_game' } }, screen = { '螢幕', 'device', { 'watch' } },
  toilet = { '馬桶', 'bathroom', { 'toilet' } }, toilet_stall = { '廁所隔間', 'bathroom', { 'toilet', 'hide' } }, urinal = { '小便斗', 'bathroom', {} },
  washbasin = { '洗手台', 'bathroom', { 'wash_hands' } }, mirror = { '鏡子', 'mirror', { 'look_mirror' } },
  shower = { '淋浴間', 'bathroom', { 'shower' } }, bathtub = { '浴缸', 'bathroom', { 'bath' } }, spa_pool = { '浴池', 'bathroom', { 'bath' } },
  lounger = { '躺椅', 'furniture', { 'lie', 'sunbathe' } }, fridge = { '冰箱', 'kitchen', { 'get_drink' } }, kitchen = { '流理台', 'kitchen', { 'cook' } },
  stove = { '爐台', 'kitchen', { 'cook' } }, counter = { '櫃台', 'shop', { 'order', 'pay' } }, checkout = { '收銀台', 'shop', { 'pay' } },
  goods_shelf = { '商品架', 'shop', { 'browse' } }, display_case = { '展示櫃', 'shop', { 'browse' } }, clothes_rack = { '衣架', 'shop', { 'browse', 'try_on' } },
  mannequin = { '人台', 'shop', { 'browse' } }, goods = { '商品', 'shop', { 'browse', 'buy' } }, trash = { '垃圾桶', 'misc', { 'throw_away' } },
  piano = { '鋼琴', 'music', { 'play_music' } }, guitar = { '吉他', 'music', { 'play_music' } }, treadmill = { '跑步機', 'sport', { 'exercise' } },
  weights = { '啞鈴', 'sport', { 'exercise' } }, sport_rack = { '運動器材架', 'sport', { 'exercise' } }, exercise_mat = { '運動墊', 'sport', { 'stretch', 'lie' } },
  salon_chair = { '美髮椅', 'shop', { 'sit', 'haircut' } }, shampoo_station = { '洗頭台', 'shop', { 'wash_hair' } },
  washing_machine = { '洗衣機', 'device', { 'laundry' } }, dryer = { '烘衣機', 'device', { 'laundry' } }, coffee_machine = { '咖啡機', 'kitchen', { 'get_drink' } },
  drink_dispenser = { '飲料機', 'kitchen', { 'get_drink' } }, medical_bed = { '診療床', 'health', { 'lie', 'rest' } }, first_aid = { '急救箱', 'health', { 'treat' } },
  microscope = { '顯微鏡', 'lab', { 'use' } }, printer3d = { '3D 印表機', 'lab', { 'use' } }, robot = { '機器人', 'lab', { 'look' } }, exhibit = { '展品', 'exhibit', { 'look' } },
  indoor_stage = { '舞台', 'music', { 'perform', 'watch' } }, lift = { '電梯', 'building', { 'ride' } }, bicycle = { '腳踏車', 'outdoor', { 'ride' } },
  bike_stand = { '腳踏車架', 'outdoor', {} }, vending = { '自動販賣機', 'shop', { 'buy_drink' } },
  picnic_table = { '野餐桌', 'outdoor', { 'sit', 'eat' } }, cafe_set = { '露天咖啡座', 'outdoor', { 'sit', 'eat', 'drink' } },
  beach_lounger = { '海灘躺椅', 'outdoor', { 'lie', 'sunbathe' } }, beach_umbrella = { '海灘傘', 'outdoor', { 'shade' } }, lifeguard_tower = { '救生員塔', 'outdoor', { 'look' } },
  gazebo = { '涼亭', 'outdoor', { 'sit', 'cuddle', 'rain_shelter' } }, fountain = { '噴水池', 'outdoor', { 'look', 'photo' } }, stage = { '戶外舞台', 'outdoor', { 'perform', 'watch' } },
  lighthouse = { '燈塔', 'landmark', { 'view', 'photo' } }, clock_tower = { '鐘塔', 'landmark', { 'meet', 'photo' } }, playground = { '遊樂設施', 'outdoor', { 'play' } },
  newsstand = { '書報攤', 'shop', { 'browse', 'buy' } }, drinking_fountain = { '飲水機', 'outdoor', { 'drink' } }, notice_board = { '公告欄', 'outdoor', { 'read' } },
  campus_map = { '校園地圖', 'outdoor', { 'read' } }, bus_shelter = { '公車亭', 'outdoor', { 'wait', 'rain_shelter' } }, bike_shelter = { '腳踏車棚', 'outdoor', { 'rain_shelter' } },
  beach_shower = { '沖水台', 'outdoor', { 'rinse' } }, lifebuoy = { '救生圈', 'outdoor', {} }, lantern = { '石燈籠', 'outdoor', { 'look' } },
  cherry_tree = { '櫻花樹', 'outdoor', { 'look', 'photo' } }, fish_pond = { '魚池', 'outdoor', { 'look', 'feed_fish' } }, torii = { '鳥居', 'landmark', { 'photo' } },
  offering_box = { '賽錢箱', 'landmark', { 'pray' } }, aquarium_tank = { '水族箱', 'exhibit', { 'look' } },
}
local BAKED = {
  ['COMMON-CITY-bunk'] = 'bunk_bed', ['large-bunk'] = 'bunk_bed', ['COMMON-CITY-king'] = 'double_bed', ['bed'] = 'bed',
  ['COMMON-CITY-sofa'] = 'sofa', ['sofa'] = 'sofa', ['COMMON-CITY-lounge'] = 'sofa', ['large-lounger'] = 'lounger',
  ['COMMON-CITY-seat'] = 'chair', ['chair'] = 'chair', ['stool'] = 'chair', ['COMMON-SPORT-change_bench'] = 'bench',
  ['COMMON-CITY-student_station'] = 'study_desk', ['COMMON-CITY-study_desk'] = 'desk', ['COMMON-CITY-desk'] = 'desk', ['COMMON-CITY-workstation'] = 'desk',
  ['COMMON-CITY-campus_business'] = 'desk', ['COMMON-CITY-campus_language'] = 'desk', ['COMMON-CITY-campus_drafting'] = 'desk',
  ['COMMON-CITY-dining'] = 'table', ['table'] = 'table', ['steel-table'] = 'table', ['COMMON-SPORT-table'] = 'table',
  ['COMMON-CITY-console'] = 'cabinet', ['COMMON-CITY-campus_wardrobe'] = 'wardrobe', ['COMMON-CITY-wardrobe'] = 'wardrobe', ['wardrobe'] = 'wardrobe',
  ['large-wardrobe'] = 'wardrobe', ['large-campus-wardrobe'] = 'wardrobe', ['COMMON-SPORT-locker'] = 'locker', ['COMMON-CITY-locker'] = 'locker', ['large-locker'] = 'locker',
  ['COMMON-CITY-shelf'] = 'bookshelf', ['bookshelf'] = 'bookshelf', ['COMMON-CITY-lectern'] = 'lectern', ['COMMON-CITY-computer'] = 'computer',
  ['screen-terminal'] = 'screen', ['large-console'] = 'tv',
  ['COMMON-WC-toilet'] = 'toilet', ['toilet'] = 'toilet', ['COMMON-WC-standard_cubicle'] = 'toilet_stall', ['COMMON-WC-accessible_cubicle'] = 'toilet_stall',
  ['large-standard-cubicle'] = 'toilet_stall', ['large-accessible-cubicle'] = 'toilet_stall', ['COMMON-SPORT-wc_cubicle'] = 'toilet_stall', ['COMMON-SPORT-accessible_wc'] = 'toilet_stall',
  ['COMMON-WC-urinal'] = 'urinal', ['COMMON-WC-basin'] = 'washbasin', ['COMMON-CITY-basin'] = 'washbasin', ['sink'] = 'washbasin', ['COMMON-CITY-sink'] = 'washbasin',
  ['handwash'] = 'washbasin', ['double-sink'] = 'washbasin', ['COMMON-WC-mirror'] = 'mirror', ['wall-mirror'] = 'mirror',
  ['COMMON-CITY-shower'] = 'shower', ['shower'] = 'shower', ['COMMON-SPORT-shower'] = 'shower', ['COMMON-SPORT-family_shower'] = 'shower',
  ['COMMON-CITY-tub'] = 'bathtub', ['COMMON-CITY-spa_basin'] = 'spa_pool', ['large-spa-basin-v2'] = 'spa_pool',
  ['COMMON-CITY-fridge'] = 'fridge', ['fridge'] = 'fridge', ['COMMON-CITY-kitchen'] = 'kitchen', ['kitchen'] = 'kitchen', ['COMMON-CITY-cookline'] = 'stove', ['hob'] = 'stove',
  ['COMMON-CITY-prep'] = 'kitchen', ['prep-counter'] = 'kitchen', ['deck-oven'] = 'stove',
  ['service-counter'] = 'counter', ['steel-counter'] = 'counter', ['pos'] = 'checkout', ['COMMON-CITY-checkout'] = 'checkout',
  ['retail-rack'] = 'goods_shelf', ['bread-rack'] = 'goods_shelf', ['retail-case'] = 'display_case', ['display-plinth'] = 'display_case', ['fruit-bin'] = 'goods_shelf',
  ['record-bin'] = 'goods_shelf', ['clothes-rack'] = 'clothes_rack', ['display-mannequin'] = 'mannequin', ['camera'] = 'goods', ['flowers'] = 'goods', ['guitar'] = 'guitar',
  ['COMMON-WC-bin'] = 'trash', ['large-bin'] = 'trash', ['COMMON-CITY-piano'] = 'piano', ['COMMON-CITY-treadmill'] = 'treadmill', ['COMMON-CITY-weights'] = 'weights',
  ['COMMON-SPORT-rack'] = 'sport_rack', ['COMMON-CITY-mat'] = 'exercise_mat', ['salon-chair'] = 'salon_chair', ['shampoo-station'] = 'shampoo_station',
  ['washing-machine'] = 'washing_machine', ['dryer'] = 'dryer', ['coffee-machine'] = 'coffee_machine', ['tea-dispenser'] = 'drink_dispenser',
  ['COMMON-CITY-medical'] = 'medical_bed', ['COMMON-SPORT-treatment'] = 'medical_bed', ['COMMON-SPORT-aid_cabinet'] = 'first_aid',
  ['COMMON-CITY-microscope'] = 'microscope', ['COMMON-CITY-printer3d'] = 'printer3d', ['COMMON-CITY-robot'] = 'robot', ['COMMON-CITY-campus_exhibit'] = 'exhibit',
  ['COMMON-CITY-stage'] = 'indoor_stage', ['lift'] = 'lift', ['bicycle'] = 'bicycle', ['bike-stand'] = 'bike_stand',
}
local GOODS = { camera = '相機', flowers = '花', guitar = '吉他' }
for k, v in pairs({
  pergola = { '花架', 'outdoor', { 'walk', 'photo' } }, food_cart = { '餐車', 'shop', { 'buy', 'eat' } }, bbq = { '燒烤台', 'outdoor', { 'cook', 'eat' } },
  changing_screen = { '更衣屏風', 'outdoor', { 'change_clothes', 'hide' } }, foot_bath = { '足浴池', 'outdoor', { 'sit', 'foot_bath' } },
  railing = { '欄杆', 'outdoor', { 'lean', 'view' } }, telescope = { '望遠鏡', 'outdoor', { 'view' } }, viewpoint = { '觀景平台', 'landmark', { 'view', 'photo' } },
  table_tennis = { '桌球桌', 'sport', { 'play' } }, play_set = { '遊戲設施', 'sport', { 'play' } }, swing = { '鞦韆', 'outdoor', { 'swing', 'sit' } },
  art_installation = { '景觀裝置', 'landmark', { 'look', 'photo' } }, wish_rack = { '許願掛架', 'landmark', { 'make_wish' } }, xylophone = { '木琴', 'music', { 'play_music' } },
  easel = { '畫架', 'exhibit', { 'paint', 'look' } }, festival_gate = { '祭典門', 'landmark', { 'photo' } }, photo_spot = { '合照點', 'landmark', { 'photo' } },
  feed_dispenser = { '飼料機', 'outdoor', { 'feed_fish' } },
}) do KIND[k] = v end
-- resort catalog items (R001-R100, placed by the resort, city-art and activity passes): kind per item, name from the catalog
local RKIND = {
  R001 = 'lounger', R002 = 'lounger', R003 = 'table', R004 = 'chair', R005 = 'bench', R006 = 'bench', R007 = 'chair', R008 = 'bench', R009 = 'chair', R010 = 'sofa',
  R011 = 'beach_umbrella', R012 = 'beach_umbrella', R013 = 'gazebo', R014 = 'pergola', R015 = 'beach_umbrella', R016 = 'gazebo', R017 = 'gazebo', R018 = 'pergola',
  R019 = 'gazebo', R020 = 'beach_umbrella', R021 = 'cafe_set', R022 = 'picnic_table', R023 = 'table', R024 = 'counter', R025 = 'food_cart', R026 = 'food_cart',
  R027 = 'bbq', R029 = 'drinking_fountain', R030 = 'food_cart', R032 = 'locker', R033 = 'lifeguard_tower', R034 = 'lifebuoy', R035 = 'beach_shower',
  R036 = 'changing_screen', R037 = 'foot_bath', R040 = 'bench', R043 = 'pergola', R051 = 'railing', R052 = 'bench', R053 = 'railing', R054 = 'telescope',
  R055 = 'viewpoint', R059 = 'bench', R061 = 'table_tennis', R062 = 'play_set', R063 = 'play_set', R064 = 'play_set', R065 = 'play_set', R066 = 'play_set',
  R067 = 'swing', R068 = 'sport_rack', R069 = 'play_set', R070 = 'play_set', R073 = 'play_set', R075 = 'beach_umbrella', R076 = 'beach_umbrella', R082 = 'counter',
  R086 = 'trash', R090 = 'table', R091 = 'art_installation', R092 = 'art_installation', R093 = 'art_installation', R094 = 'art_installation', R095 = 'art_installation',
  R096 = 'lantern', R097 = 'art_installation', R098 = 'bench', R099 = 'wish_rack', R100 = 'xylophone',
}
local rname = {}
if exists(root .. 'resort-streetscape-v1/catalog.json') then for _, a in ipairs(load('resort-streetscape-v1/catalog.json').assets) do rname[a.id] = a.name end end
-- activity-scene props by mesh (the scene names come from the activity plan)
local AMESH = { bear = { 'photo_spot', '大熊合照點' }, service_counter = { 'counter' }, fountain = { 'fountain' }, fish_pond = { 'fish_pond' }, easel = { 'easel' },
  picture_rack = { 'display_case', '畫作展示架' }, art_display = { 'exhibit', '畫作展示' }, festival_gate = { 'festival_gate' }, practice_stage = { 'stage', '練習舞台' },
  library_wall = { 'bookshelf', '繪本牆' }, binoculars = { 'telescope', '望遠鏡' }, staff_locker = { 'locker' }, feed_dispenser = { 'feed_dispenser' },
  dango = { 'goods', '糰子攤' }, candy = { 'goods', '糖果攤' }, cake = { 'goods', '蛋糕攤' }, ramen = { 'goods', '拉麵攤' }, sushi = { 'goods', '壽司攤' },
  tea = { 'goods', '茶飲攤' }, toy_car = { 'goods', '玩具車' }, rose_bouquet = { 'goods', '玫瑰花束' }, books = { 'goods', '書' }, laptop = { 'computer', '筆電' } }
local scenename = {}
if exists(root .. 'activity-scenes-v1/plan.json') then for _, s in ipairs(load('activity-scenes-v1/plan.json').scenes) do scenename[s.id:lower()] = s.name end end
local PLACE_ZH = { park_bench = '長椅', beach_lounger = '海灘躺椅', picnic_table = '野餐桌', gazebo = '涼亭', fountain = '噴水池廣場', outdoor_cafe_set = '露天咖啡座',
  stage = '戶外舞台', lighthouse = '燈塔', clock_tower = '鐘塔廣場', playground = '遊樂場', grove = '小樹林' }
local props, rooms_idx = {}, {}
local area, areaid = {}, {}
local function addarea(a) area[#area + 1] = a; areaid[a.id] = #area; return #area end
-- areas: every manifest room (classes, restrooms, labs as well), then the outdoor places, then the buildings
local placeby = {}; for _, p in ipairs(places) do placeby[p.id] = p end
local rids = {}; for id in pairs(mrooms) do rids[#rids + 1] = id end; table.sort(rids)
for _, id in ipairs(rids) do
  local box, door, m = roombox(id)
  if box then
    local pr, pl = planrooms[id], placeby[id:lower()]
    addarea({ id = id:lower(), kind = 'room', type = pr and pr.type or 'room', name = pr and pr.name or id, building = m.building, floor = m.floor,
      privacy = pl and pl.privacy or 0, door = door or box.center, min = box.min, max = box.max })
  end
end
-- single-object places (a bench, a lounger) are props, not areas she is "in"
local SINGLE = { park_bench = true, beach_lounger = true, picnic_table = true, outdoor_cafe_set = true }
for _, p in ipairs(places) do
  if not p.room and not p.building and not SINGLE[p.kind] then
    addarea({ id = p.id, kind = 'place', type = p.kind, name = p.name or scenename[p.id] or PLACE_ZH[p.kind], privacy = p.privacy or 0, door = p.door,
      radius_cm = p.radius_cm or (p.kind == 'activity_scene' and 1500) or 600 })
  end
end
local bfl = {} -- building AABB over its floor actors
for _, a in ipairs(actors.actors) do
  local b = a.label:match('^%a+_(%w+)_F%d+$') or a.label:match('^(S%d+)_F%d+$')
  if b and bname[b] then local q = bfl[b] or { 1e9, 1e9, 1e9, -1e9, -1e9, -1e9 }; bfl[b] = q
    q[1] = math.min(q[1], a.c[1] - a.e[1]); q[2] = math.min(q[2], a.c[2] - a.e[2]); q[3] = math.min(q[3], a.c[3] - a.e[3])
    q[4] = math.max(q[4], a.c[1] + a.e[1]); q[5] = math.max(q[5], a.c[2] + a.e[2]); q[6] = math.max(q[6], a.c[3] + a.e[3]) end
end
local bcat = {}; for _, b in ipairs(cityplan.buildings) do bcat[b.id] = b.category end
local bids = {}; for b in pairs(bfl) do bids[#bids + 1] = b end; table.sort(bids)
for _, b in ipairs(bids) do local q = bfl[b]
  addarea({ id = 'building_' .. b:lower(), kind = 'building', type = bcat[b] or '', name = bname[b], building = b, privacy = 0,
    door = entry[b] or P((q[1] + q[4]) / 2, (q[2] + q[5]) / 2, q[3]), min = P(q[1], q[2], q[3]), max = P(q[4], q[5], q[6]) })
end
-- which area a world point is in: the room on that floor, else the building, else the nearest outdoor place in range
local function bldof(p) for _, b in ipairs(bids) do local q = bfl[b]; if p[1] >= q[1] and p[1] <= q[4] and p[2] >= q[2] and p[2] <= q[5] and p[3] >= q[3] - 50 and p[3] <= q[6] then return b end end end
local function areaof(p, b, floor, owner)
  if owner and areaid[owner:lower()] then return areaid[owner:lower()] end
  b = b or bldof(p)
  if b then
    for _, id in ipairs(byfloor[b .. ':' .. tostring(floor)] or {}) do if inbox(id, p) then return areaid[id:lower()] end end
    if not floor then for k, list in pairs(byfloor) do if k:match('^' .. b .. ':') then for _, id in ipairs(list) do if inbox(id, p) then return areaid[id:lower()] end end end end end
    return areaid['building_' .. b:lower()]
  end
  local best, bd
  for i, a in ipairs(area) do if a.kind == 'place' then
    local d = math.sqrt((a.door[1] - p[1]) ^ 2 + (a.door[2] - p[2]) ^ 2); if d <= a.radius_cm + 300 and (not bd or d < bd) then best, bd = i, d end end end
  return best
end
local function prop(kind, p, face, ar, extra)
  assert(KIND[kind], kind)
  local t = { k = kind, p = p, a = ar and (ar - 1) or nil, face = face and r1(face) or nil }
  if extra then for k, v in pairs(extra) do t[k] = v end end
  props[#props + 1] = t
end
-- 5a. baked building furniture (assembly reports; motel suite floors are replaced by the suites below)
for _, rep in ipairs(reports) do
  local b = rep[1]
  if origin[b] then
    for _, i in ipairs(load(rep[2]).instances or {}) do
      local kind = BAKED[i.asset]
      if kind and i.position_m and not (motel_floors[b] and motel_floors[b][i.floor]) then
        local theta = i.yaw_deg or math.deg(i.yaw_rad or 0)
        local pos = BW(b, i.position_m[1], i.position_m[2], i.position_m[3])
        local owner = i.owner ~= b and i.owner or nil
        prop(kind, pos, 180 - theta, areaof(pos, b, i.floor, owner), GOODS[i.asset] and { n = GOODS[i.asset] } or nil)
      end
    end
  end
end
-- classroom seats moved by the functional-interior pass (same list the places use)
for _, a in ipairs(inst) do if a.asset == 'classroom-seat' then prop('chair', a.pos, a.yaw + 90, areaof(a.pos, a.b, a.floor, a.owner)) end end
-- 5b. motel suites: bed, bath, real mirrors
for _, p in ipairs(places) do
  if p.kind == 'motel_suite' or p.kind == 'motel_pool_suite' then
    local ar = addarea({ id = p.id, kind = 'room', type = p.kind, name = p.name, building = p.building, floor = p.floor, privacy = 2, door = p.door,
      min = P(p.room.center[1] - p.room.size[1] / 2 - p.room.size[2] / 2, p.room.center[2] - p.room.size[1] / 2 - p.room.size[2] / 2, p.room.center[3] - p.room.size[3] / 2),
      max = P(p.room.center[1] + p.room.size[1] / 2 + p.room.size[2] / 2, p.room.center[2] + p.room.size[1] / 2 + p.room.size[2] / 2, p.room.center[3] + p.room.size[3] / 2) })
    for _, a in ipairs(p.anchors) do
      if a.name == 'bed1_0' then prop('double_bed', a.pos, a.yaw + 90, ar) elseif a.name == 'bath' then prop('bathtub', a.pos, nil, ar) end
    end
    for _, m in ipairs(p.mirrors or {}) do prop('mirror', m.face, m.kind == 'wall' and math.deg(math.atan(m.normal[2], m.normal[1])) or nil, ar, { n = m.kind == 'ceiling' and '天花板鏡' or '床邊大鏡子' }) end
  end
end
-- 5c. actors: outdoor furniture, landmarks, mirrors, lanterns, cherry trees, the lover-spot items
local ACT = { -- label pattern (Lua), kind
{ '^Park_picnic_table_', 'picnic_table' }, { '^Landmark_cafe_set_', 'cafe_set' }, { '^Beach_lounger_', 'beach_lounger' },
  { '^Beach_umbrella_', 'beach_umbrella' }, { '^Beach_tower_', 'lifeguard_tower' }, { '^Landmark_gazebo_', 'gazebo' }, { '^Landmark_plaza_fountain_', 'fountain' },
  { '^Landmark_stage_', 'stage' }, { '^Landmark_lighthouse_', 'lighthouse' }, { '^Landmark_clock_tower_', 'clock_tower' }, { '^Landmark_playground_', 'playground' },
  { '^Landmark_newsstand_', 'newsstand' }, { '^Park_drinking_fountain_', 'drinking_fountain' }, { '^Park_notice_board_', 'notice_board' }, { '^Park_campus_map_', 'campus_map' },
  { '^Park_bike_shelter_', 'bike_shelter' }, { '^Park_beach_shower_', 'beach_shower' }, { '^Park_lifebuoy_post_', 'lifebuoy' },
  { '^Street_bicycle_', 'bicycle' }, { '^Resort_bicycle_', 'bicycle' },
  { '^ResortLantern_.*_Plinth$', 'lantern' }, { '^Resort_cherry_', 'cherry_tree' }, { '^MotelV1_WC_%d+_Glass$', 'mirror' }, { '^Immersion_Mirror_.*_Glass$', 'mirror' },
}
local MESH = { { '^fish_pond', 'fish_pond' } }
for _, a in ipairs(actors.actors) do
  if not a.label:match('^LoverSpot_') then
    local kind
    for _, r in ipairs(ACT) do if a.label:match(r[1]) then kind = r[2]; break end end
    if not kind then for _, r in ipairs(MESH) do if (a.mesh or ''):match(r[1]) then kind = r[2]; break end end end
    local name = a.label:match('^Immersion_Mirror_') and '練習用大鏡子' or nil
    local rc = a.label:match('_(R%d%d%d)_') or a.label:match('_(R%d%d%d)$') or (a.mesh or ''):match('^(R%d%d%d)_LOD')
    if not kind and rc and RKIND[rc] then kind, name = RKIND[rc], rname[rc] end
    local am = AMESH[((a.mesh or ''):match('^(.-)_LOD') or '')]
    if not kind and am and a.label:match('^Activity_') then kind, name = am[1], am[2] end
    -- a street cluster spanning the whole city (CityArt pools several shops in one actor) has no single position
    if kind and a.cls == 'BP_StreetCluster_C' and math.max(a.e[1], a.e[2]) > 600 then kind = nil end
    if kind then
      local p = kind == 'mirror' and P(a.c[1], a.c[2], a.c[3]) or P(a.c[1], a.c[2], a.c[3] - a.e[3])
      prop(kind, p, nil, areaof(p), name and { n = name } or nil)
    end
  end
end
for id, kind in pairs({ bench_oak = 'bench', bench_stone = 'bench', recycling = 'trash', cycle_rack = 'bike_stand', bus_shelter = 'bus_shelter' }) do
  for _, q in ipairs(STREET[id] or {}) do local p = P(q[1], q[2], 1199); prop(kind, p, q[4], areaof(p)) end
end
local LS = { vending = 'vending', lounge = 'sofa', lounge2 = 'sofa', game = 'tv', seat = 'chair', table = 'table', torii = 'torii', pray = 'offering_box', tank = 'aquarium_tank', bench = 'bench' }
for _, it in pairs(newitems) do
  local kind = LS[it.anchor]
  if kind then prop(kind, it.pos, (it.yaw or 0) + 90, areaof(it.pos)) end
end
-- one entry per object: the baked mirror over a washbasin and the reflective glass the restroom pass added are the same mirror
table.sort(props, function(a, b) if a.k ~= b.k then return a.k < b.k end; if a.p[1] ~= b.p[1] then return a.p[1] < b.p[1] end; return a.p[2] < b.p[2] end)
local kept, cell = {}, {}
for _, t in ipairs(props) do
  local cs = t.k == 'mirror' and 100 or 50
  local key = t.k .. ':' .. math.floor(t.p[1] / cs) .. ':' .. math.floor(t.p[2] / cs) .. ':' .. math.floor(t.p[3] / 100)
  local dup = false
  for dx = -1, 1 do for dy = -1, 1 do
    for _, o in ipairs(cell[t.k .. ':' .. (math.floor(t.p[1] / cs) + dx) .. ':' .. (math.floor(t.p[2] / cs) + dy) .. ':' .. math.floor(t.p[3] / 100)] or {}) do
      local r = t.k == 'mirror' and 100 or 45
      if math.abs(o.p[1] - t.p[1]) < r and math.abs(o.p[2] - t.p[2]) < r and math.abs(o.p[3] - t.p[3]) < (t.k == 'mirror' and 150 or 80) then dup = true; o.face = o.face or t.face; o.n = o.n or t.n end
    end end end
  if not dup then kept[#kept + 1] = t; cell[key] = cell[key] or {}; table.insert(cell[key], t) end
end
-- 5d. game anchors for the activity scenes (c-conquest C6): their props by kind become seat* / stall* / view / pond /
-- stage / watch* / field / jog / fireworks, so the game can stand or sit people there. Anchor yaw = prop face - 90.
do
  local AK = { chair = 'seat', bench = 'seat', sofa = 'seat', picnic_table = 'seat', cafe_set = 'seat', goods = 'stall', food_cart = 'stall', counter = 'stall',
    telescope = 'view', viewpoint = 'view', fish_pond = 'pond', feed_dispenser = 'pond', stage = 'stage', sport_rack = 'field', photo_spot = 'photo', easel = 'stand',
    bookshelf = 'shelf', display_case = 'stand', festival_gate = 'gate', computer = 'stand', fountain = 'fountain' }
  local fw = {}; for _, a in ipairs(actors.actors) do if a.label:match('^ActivityArt_Fireworks_') then fw[#fw + 1] = a end end
  for _, p in ipairs(places) do
    if p.kind == 'activity_scene' and areaid[p.id] then
      local ai = areaid[p.id] - 1; local an, n = {}, {}
      local stagey = p.id == 'actspace-10'
      for _, t in ipairs(kept) do
        local base = t.a == ai and AK[t.k]
        if base == 'seat' and stagey then base = 'watch' end
        if base == 'stall' and p.id == 'actspace-08' then base = 'counter' end
        if base then
          n[base] = (n[base] or 0) + 1
          local name = base .. (n[base] > 1 and tostring(n[base]) or '')
          if n[base] <= 12 then an[#an + 1] = { name = name, pos = t.p, yaw = t.face and r1(t.face - 90) or 0, source = t.n or t.k } end
        end
      end
      if p.id == 'actspace-07' then an[#an + 1] = { name = 'jog', pos = p.door, yaw = 0, source = 'loop start (scene centre)' }; if not n.field then an[#an + 1] = { name = 'field', pos = p.door, yaw = 0, source = 'scene centre' } end end
      if p.id == 'actspace-05' and fw[1] then table.sort(fw, function(a, b) return a.label < b.label end); an[#an + 1] = { name = 'fireworks', pos = P(fw[1].c[1], fw[1].c[2], fw[1].c[3]), yaw = 0, source = fw[1].label } end
      if p.id == 'actspace-04' and not n.view then an[#an + 1] = { name = 'view', pos = p.door, yaw = 0, source = 'scene centre' } end
      p.anchors = an; p.name = p.name or scenename[p.id]
    end
  end
end
-- 5e. places built from furnished rooms (c-conquest C12, C10): the gynaecology clinic in the CV clinic wing
-- (CV-0101 and CV-0104 only, CV-0102 is the dentist and CV-0103 the general clinic: doctor = the chair and bed_op a
-- medical bed in CV-0101, rest* = medical beds in CV-0104; counter / seat* come from
-- the lover-spots install) and the company office units (desk* / seat* in the room)
local function inroom(rid, kind) local out = {}; local ai = areaid[rid] and areaid[rid] - 1
  for _, t in ipairs(kept) do if t.a == ai and t.k == kind then out[#out + 1] = t end end; return out end
local function roomrect(rid) local a = area[areaid[rid] or 0]; return a and { min = a.min, max = a.max, floor = a.floor } end
do
  local a1 = area[areaid['cv-0101'] or 0]
  if a1 then
    local an = {}
    local function put(name, t) if t then an[#an + 1] = A(name, t.p, t.face and r1(t.face - 90) or 0, t.k .. ' ' .. (t.n or '')) end end
    put('doctor', inroom('cv-0101', 'chair')[1]); put('bed_op', inroom('cv-0101', 'medical_bed')[1])
    local rb = inroom('cv-0104', 'medical_bed'); put('rest', rb[1]); put('rest2', rb[2])
    -- he waits in the corridor: 1.5 m out of the clinic door, away from the room centre
    local cx, cy = (a1.min[1] + a1.max[1]) / 2, (a1.min[2] + a1.max[2]) / 2; local dx, dy = a1.door[1] - cx, a1.door[2] - cy
    if math.abs(dx) > math.abs(dy) then dx, dy = dx > 0 and 1 or -1, 0 else dx, dy = 0, dy > 0 and 1 or -1 end
    an[#an + 1] = A('wait', P(a1.door[1] + dx * 150, a1.door[2] + dy * 150, a1.door[3]), r1(math.deg(math.atan(-dy, -dx)) - 90), 'corridor outside CV-0101')
    for _, k in ipairs({ 'counter', 'seat', 'seat2', 'seat3' }) do local it = newitems['clinic_gyn:' .. k]; if it then an[#an + 1] = A(k, it.pos, it.yaw, it.actor) end end
    GAME_PLACES[#GAME_PLACES + 1] = { id = 'clinic_gyn', building = 'CV', name = '婦科小診所（CV 1F 社區診所）', door = a1.door,
      rooms = { roomrect('cv-0101'), roomrect('cv-0104') }, anchors = an, privacy = 1, new_place = true }
    table.sort(GAME_PLACES, function(a, b) return a.id < b.id end)
  end
end
-- 5f. life places that already exist as furnished (or empty) rooms (c-conquest 8.2, round 1: data only). Each game id
-- lists its rooms; anchors come from the props in them by kind (KA, overridable per place), numbered name, name2, ...
-- Rooms without furniture (most M1 shops) only get door and rooms here; round 2 dresses them.
do
  local KA = { checkout = 'counter', counter = 'counter', chair = 'seat', bench = 'seat', sofa = 'seat', desk = 'desk', table = 'table', bookshelf = 'shelf',
    mirror = 'mirror', medical_bed = 'bed', locker = 'locker', shower = 'shower', bathtub = 'bath', kitchen = 'kitchen', stove = 'stove',
    table_tennis = 'pingpong', screen = 'screen', indoor_stage = 'stage', goods_shelf = 'shelf', display_case = 'case', clothes_rack = 'rack', treadmill = 'treadmill' }
  local L = {
    { 'dentist', '牙醫診所（CV-0102）', { 'cv-0102' }, { medical_bed = 'dental_chair' } },
    { 'clinic_general', '家醫科診所與藥局（CV-0103、CV-0105）', { 'cv-0103', 'cv-0105' }, { medical_bed = 'bed_exam', checkout = 'pharmacy' } },
    { 'post', '郵局（CV-0201）', { 'cv-0201' } }, { 'bank', '銀行（CV-0202）', { 'cv-0202' } },
    { 'cinema', '電影院（CV-0402 電影放映室）', { 'cv-0402' }, { indoor_stage = 'screen' } },
    { 'museum', '美術館與城市歷史館（CV-0403、CV-0404）', { 'cv-0403', 'cv-0404' }, { chair = 'bench', bench = 'bench' } },
    { 'gym', '健身房（SP 重量訓練、有氧、瑜伽、飛輪）', { 'sp-0403', 'sp-0404', 'sp-0501', 'sp-0506' } },
    { 'pool', '室內游泳池（SP 50 公尺泳池館）', { 'sp-0101', 'sp-0102', 'sp-0103' } },
    { 'gym_hall', '體育館（SP 籃球、排球、桌球館）', { 'sp-0104', 'sp-0106', 'sp-0108' } },
    { 'club_room', '社團教室（SC 2–3F）', { 'sc-0202', 'sc-0203', 'sc-0305', 'sc-0306', 'sc-0307' } },
    { 'art_room', '美術教室（SC-0401 美術社畫室）', { 'sc-0401' } },
    { 'optician', '眼鏡行（M1-0407）', { 'm1-0407' } }, { 'jewelry', '珠寶飾品（M1-0105、M1-0408）', { 'm1-0105', 'm1-0408' } },
    { 'lingerie', '內衣店（M1-0206）', { 'm1-0206' } }, { 'phone_shop', '手機行（M1-0701）', { 'm1-0701' } },
    { 'ramen', '拉麵店（M1-0901）', { 'm1-0901' } }, { 'arcade', '遊戲中心（M1-0806、M1-0807）', { 'm1-0806', 'm1-0807' } },
    { 'observation', '展望台（M1-1006 高空咖啡館）', { 'm1-1006' } },
    { 'clothing', '服飾店（M1 2F 女裝、3F 男裝）', { 'm1-0201', 'm1-0202', 'm1-0203', 'm1-0204', 'm1-0205', 'm1-0301', 'm1-0302', 'm1-0303', 'm1-0304' } },
    { 'photo_studio', '寫真館（S34 底片相館）', { 's34-0101', 's34-0201' } },
  }
  for _, e in ipairs(L) do
    local rooms, an, n, door, b = {}, {}, {}, nil, nil
    for _, rid in ipairs(e[3]) do
      local r = area[areaid[rid] or 0]
      if r then
        rooms[#rooms + 1] = { min = r.min, max = r.max, floor = r.floor }; door = door or r.door; b = b or r.building
        for _, t in ipairs(kept) do if t.a == areaid[rid] - 1 then
          local base = (e[4] and e[4][t.k]) or KA[t.k]
          if base then n[base] = (n[base] or 0) + 1; if n[base] <= 12 then an[#an + 1] = A(base .. (n[base] > 1 and n[base] or ''), t.p, t.face and r1(t.face - 90) or 0, rid .. ' ' .. t.k) end end
        end end
      end
    end
    if #rooms > 0 then GAME_PLACES[#GAME_PLACES + 1] = { id = e[1], building = b, name = e[2], door = door, rooms = rooms, anchors = an, privacy = 0, new_place = true, furnished = #an > 0 } end
  end
  -- the beach: every beach prop (loungers, umbrellas, lifeguard towers, showers, changing screens) in one box
  -- the shore runs ~1 km along the west coast: one 100 x 100 m box round each lifeguard tower west of x 40000 (the
  -- tower at the inland pool is not the sea); umbrellas also stand at street cafes, so only those inside a box count
  local BK = { lounger = 'lounger', beach_umbrella = 'parasol', lifeguard_tower = 'lifeguard', beach_shower = 'shower', changing_screen = 'changing' }
  local boxes = {}
  for _, t in ipairs(kept) do if t.k == 'lifeguard_tower' and t.p[1] < 40000 then
    boxes[#boxes + 1] = { min = P(t.p[1] - 5000, t.p[2] - 5000, t.p[3] - 400), max = P(t.p[1] + 5000, t.p[2] + 5000, t.p[3] + 800) }
  end end
  local function onshore(p) for _, b in ipairs(boxes) do if p[1] >= b.min[1] and p[1] <= b.max[1] and p[2] >= b.min[2] and p[2] <= b.max[2] then return true end end end
  local x0 = #boxes > 0 and 0 or math.huge
  local an, n = {}, {}
  for _, t in ipairs(kept) do local base = BK[t.k]
    if base and onshore(t.p) then
      n[base] = (n[base] or 0) + 1; if n[base] <= 12 then an[#an + 1] = A(base .. (n[base] > 1 and n[base] or ''), t.p, t.face and r1(t.face - 90) or 0, t.n or t.k) end
    end
  end
  if x0 < math.huge and #an > 0 then
    local door; for _, a in ipairs(an) do if a.name == 'lifeguard' then door = a.pos end end
    GAME_PLACES[#GAME_PLACES + 1] = { id = 'beach', name = '海水浴場', door = door or an[1].pos, rooms = boxes,
      anchors = an, privacy = 0, new_place = true, outdoor = true, note = 'swim*, banana_boat, volleyball, watermelon, sandcastle, rental: round 3' }
  end
  -- every game place: outdoor when it has no building (park, playground, shrine, campus gate, beach); the sports field too
  for _, g in ipairs(GAME_PLACES) do if g.outdoor == nil then g.outdoor = g.building == nil end end
  table.sort(GAME_PLACES, function(a, b) return a.id < b.id end)
end
-- kitchens and baths in the homes (c-conquest 8.2 住家): every lockable room gets kitchen / stove / bath anchors from
-- its own props (apartments and motel suites have them; the dorm rooms only have showers until round 2)
do
  local HK = { kitchen = 'kitchen', stove = 'stove', bathtub = 'bath' }
  for _, p in ipairs(places) do
    if areaid[p.id] and p.anchors and (p.kind == 'room_apartment' or p.kind == 'room_dorm' or p.kind == 'motel_suite' or p.kind == 'motel_pool_suite' or p.kind == 'room_inn') then
      local have = {}; for _, a in ipairs(p.anchors) do have[a.name] = true end
      for _, t in ipairs(kept) do local base = t.a == areaid[p.id] - 1 and HK[t.k]
        if base and not have[base] then have[base] = true; p.anchors[#p.anchors + 1] = { name = base, pos = t.p, yaw = t.face and r1(t.face - 90) or 0, asset = t.k } end
      end
    end
  end
end
local OFFICE_UNITS = {}
for unit, rid in pairs({ dept_office = 'o01-0201', hotel_business = 'h1-0107', lodge_office = 'o01-0102', school_club = 'sc-0202' }) do
  local r = area[areaid[rid] or 0]
  if r then
    local an, n = {}, {}
    for _, kind in ipairs({ 'desk', 'chair', 'sofa' }) do for _, t in ipairs(inroom(rid, kind)) do
      local base = kind == 'desk' and 'desk' or 'seat'; n[base] = (n[base] or 0) + 1
      if n[base] <= 8 then an[#an + 1] = A(base .. (n[base] > 1 and n[base] or ''), t.p, t.face and r1(t.face - 90) or 0, t.k) end
    end end
    OFFICE_UNITS[unit] = { room = rid, building = r.building, name = r.name, floor = r.floor, door = r.door, min = r.min, max = r.max, anchors = an }
  end
end
local kinds = {}; for k, v in pairs(KIND) do kinds[k] = { zh = v[1], category = v[2], uses = v[3] } end
local pout = assert(io.open(root .. 'places-v1/props.json', 'wb'))
pout:write(json.encode({ schema = 1, map_sha256 = actors.map_sha256, frame = 'UE cm, +X north, +Y east; face = world yaw the front looks to', cell_cm = 1000,
  kinds = kinds, areas = area, props = kept }))
pout:close()
local pc = {}; for _, t in ipairs(kept) do pc[t.k] = (pc[t.k] or 0) + 1 end
local noarea = 0; for _, t in ipairs(kept) do if not t.a then noarea = noarea + 1 end end
local l = {}; for k, v in pairs(pc) do l[#l + 1] = k .. '=' .. v end; table.sort(l)
print('props', #kept, '(' .. (#props - #kept) .. ' duplicates merged)', 'areas', #area, 'outside every area', noarea)
print(table.concat(l, ' '))
table.sort(places, function(a, b) return a.id < b.id end)
-- the girls' dorm rooms (c-conquest C11): the game hands each heroine one of them (sleep / bath / "her room")
local dorm_rooms = {}
for _, p in ipairs(places) do
  if p.kind == 'room_dorm' and p.building == 'D1' then
    local beds, showers = {}, {}
    for _, a in ipairs(p.anchors) do if a.name:match('^bed') then beds[#beds + 1] = a.name elseif a.name:match('^shower') then showers[#showers + 1] = a.name end end
    dorm_rooms[#dorm_rooms + 1] = { place = p.id, room = p.room_id or p.id, floor = p.floor or (mrooms[(p.room_id or ''):upper()] or {}).floor, beds = beds, showers = showers, door = p.door }
  end
end
local out = assert(io.open(root .. 'places-v1/places.json', 'wb'))
out:write(json.encode({ schema = 1, map_sha256 = actors.map_sha256, frame = 'UE cm, +X north, +Y east; anchor yaw: character faces yaw+90', mirrors_from = latest, places = places, game_places = GAME_PLACES, girls_dorm_rooms = dorm_rooms, lots = LOTS, office_units = OFFICE_UNITS }))
out:close()
local count = {}; for _, p in ipairs(places) do count[p.kind] = (count[p.kind] or 0) + 1 end
for k, v in pairs(count) do print(k, v) end
print('wrote ' .. root .. 'places-v1/places.json', #places)
