-- The university city's places as the game reads them: output/street-social-city-production/places-v1/places.json
-- (Tools/build_street_city_places.lua) -> Content/IndependentResources/StreetSocialData/city_places.json.
-- Only what the game uses goes in, so the file is small and does not change when the city's own notes do.
--   Tools\lua\lua.exe Tools\export_street_city_game_places.lua [--check]
-- --check: report what is wrong and write nothing.
local ROOT = (arg[0]:gsub('\\', '/'):match('^(.*)/Tools/[^/]*$') or '.') .. '/'
package.path = ROOT .. 'Tools/lua/?.lua;' .. ROOT .. 'Tools/?.lua;' .. ROOT .. 'Tools/lua/lua/?.lua;' .. package.path
local json = require('json')

local SOURCE = ROOT .. 'output/street-social-city-production/places-v1/places.json'
local TARGET = ROOT .. 'Content/IndependentResources/StreetSocialData/city_places.json'
local check = arg[1] == '--check'

local function read(path)
  local f = assert(io.open(path, 'rb'), 'cannot read ' .. path)
  local s = f:read('a'); f:close(); return s
end

local function num(v)
  if v == math.floor(v) then return string.format('%d', v) end
  return (string.format('%.2f', v):gsub('0+$', ''):gsub('%.$', ''))
end
local function quoted(s) return '"' .. s:gsub('[\\"]', '\\%0') .. '"' end
local function vec(v) return '[' .. num(v[1]) .. ',' .. num(v[2]) .. ',' .. num(v[3]) .. ']' end

local data = json.decode(read(SOURCE))
local problems, lines = {}, {}
local function problem(text) problems[#problems + 1] = text end

local places = data.game_places
table.sort(places, function(a, b) return a.id < b.id end)
local anchors, rooms = 0, 0
-- the lift stops of each multi-storey place, to number the floor of a room inside it that has none
local stops = {}
for _, p in ipairs(places) do
  local z = {}
  for _, an in ipairs(p.anchors or {}) do local k = an.name:match('^lift(%d+):'); if k then z[tonumber(k)] = an.pos[3] end end
  if #z > 1 then
    local box; for _, room in ipairs(p.rooms or {}) do if room.min then box = box or room end end
    if box then stops[#stops + 1] = { box = box, z = z } end
  end
end
local function floorof(room)
  local cx, cy, z0 = (room.min[1] + room.max[1]) / 2, (room.min[2] + room.max[2]) / 2, room.min[3]
  for _, s in ipairs(stops) do
    local b = s.box
    if cx >= b.min[1] and cx <= b.max[1] and cy >= b.min[2] and cy <= b.max[2] then
      local best, d = 1, math.huge
      for k, z in ipairs(s.z) do if math.abs(z - z0) < d then best, d = k, math.abs(z - z0) end end
      return best
    end
  end
  return math.max(2, 1 + math.floor((z0 - 1200) / 400 + .5))
end
-- A door inside something solid: the open-air places took the middle of their landmark for the door (the park's fountain,
-- the skating rental hut, the BBQ grill, the ferris wheel), so a walk there ended against it and the playground's, in its
-- climbing frame, could not be reached at all (11-09). Such a door moves out of the thing to the side nearest a road, onto
-- open ground. The solid things are the map's props and furniture (actors.json), not the buildings' shells, whose doors are
-- in their walls on purpose.
local ACTORS = ROOT .. 'output/street-social-city-production/places-v1/actors.json'
local RASTER = ROOT .. 'output/street-social-city-production/world-edge-v1/road-raster.json'
local solids = {}
do
  local f = io.open(ACTORS, 'rb')
  if f then
    local all = json.decode(f:read('a')).actors; f:close()
    for _, a in ipairs(all) do
      if a.c and a.e then
        local label = a.label or ''
        local prop = label:match('^LoverSpot_') or label:match('^Landmark_') or label:match('_Block$')
          or (a.cls == 'StaticMeshActor' and math.max(a.e[1], a.e[2]) < 300 and not label:match('^S%d+_F%d'))
        if prop and math.max(a.e[1], a.e[2]) < 2000 then solids[#solids + 1] = a end
      end
    end
  else problem('no ' .. ACTORS .. ': doors not checked against the props') end
end
local function solid_at(x, y, z, margin)
  for _, a in ipairs(solids) do
    if math.abs(x - a.c[1]) <= a.e[1] + margin and math.abs(y - a.c[2]) <= a.e[2] + margin
      and z + 170 >= a.c[3] - a.e[3] and z + 15 <= a.c[3] + a.e[3] then return a end
  end
end
local door_raster
local function open_ground(x, y)
  door_raster = door_raster or json.decode(read(RASTER))
  local R = door_raster
  local k = math.floor((x - R.origin[1]) / R.step_cm + 1.5); local i = math.floor((y - R.origin[2]) / R.step_cm + 1.5)
  local row = R.rows[i]; local c = row and row:sub(k, k) or ''
  if c ~= 'r' and c ~= 'g' then return nil end
  -- how far the nearest road cell is (cells), up to 15 m
  for r = 0, 8 do for di = -r, r do for dk = -r, r do
    if math.max(math.abs(di), math.abs(dk)) == r then local w = R.rows[i + di]; if w and w:sub(k + dk, k + dk) == 'r' then return r end end
  end end end
  return 9
end
local moved_doors = 0
for _, p in ipairs(places) do
  local d = p.door
  local hit = d and #d == 3 and solid_at(d[1], d[2], d[3], 0)
  if hit then
    local best, score
    for ring = 1, 6 do
      local m = 40 + ring * 30
      local hx, hy = hit.e[1] + m, hit.e[2] + m
      for s = 0, 31 do
        local t = s / 32 * 2 * math.pi
        local cx, cy = math.cos(t), math.sin(t)
        local scale = math.min(hx / math.max(math.abs(cx), 1e-6), hy / math.max(math.abs(cy), 1e-6))
        local x, y = hit.c[1] + cx * scale, hit.c[2] + cy * scale
        -- on a pier over the water the road picture has no ground: any spot clear of things, nearest first
        local free = not solid_at(x, y, d[3], 35)
        local road_cells = free and (open_ground(x, y) or (ring >= 2 and 20))
        if road_cells then
          local sc = road_cells * 1000 + ring * 100 + math.sqrt((x - d[1]) ^ 2 + (y - d[2]) ^ 2) / 100
          if not score or sc < score then best, score = { x, y, d[3] }, sc end
        end
      end
      if best then break end
    end
    if best then
      print(('door: %s moved out of %s, %.0f,%.0f -> %.0f,%.0f'):format(p.id, hit.label, d[1], d[2], best[1], best[2]))
      p.door = best; moved_doors = moved_doors + 1
    else problem(p.id .. ': door inside ' .. hit.label .. ' and no open ground round it') end
  end
end
if moved_doors > 0 then print(('%d doors moved out of props'):format(moved_doors)) end
-- A spot taken from a room's middle (its source is the room id, 'M1-0901 ...') can land in the furniture: the department
-- store's 'food' was in the ramen shop's counter seats, and a walk there from the 9F lift found no way (R6-197, 11-10). Such an
-- anchor moves to the nearest spot clear of the props round it, on its own floor.
do
  local moved = 0
  for _, p in ipairs(places) do
    for _, an in ipairs(p.anchors or {}) do
      local q = an.pos
      local hit = (an.source or ''):match('^%w+%-%d%d%d%d') and q and solid_at(q[1], q[2], q[3], 35)
      if hit then
        local best, far
        for r = 50, 400, 25 do
          for s = 0, 31 do
            local t = s / 32 * 2 * math.pi; local x, y = q[1] + math.cos(t) * r, q[2] + math.sin(t) * r
            if not solid_at(x, y, q[3], 35) then local d = (x - q[1]) ^ 2 + (y - q[2]) ^ 2; if not far or d < far then best, far = { x, y, q[3] }, d end end
          end
          if best then break end
        end
        if best then
          print(('anchor: %s %s moved out of %s, %.0f,%.0f -> %.0f,%.0f'):format(p.id, an.name, hit.label, q[1], q[2], best[1], best[2]))
          an.pos = best; moved = moved + 1
        else problem(p.id .. ' ' .. an.name .. ': inside ' .. hit.label .. ' and no clear spot within 4 m') end
      end
    end
  end
  if moved > 0 then print(('%d room anchors moved out of props'):format(moved)) end
end
-- A shop upstairs in the mall took the street entrance below it for its door, the same spot on every floor; on the 2F, 8F and
-- 10F that spot is over the atrium, with no floor under it (the game's places_check, 11-09), and a walk to the lingerie
-- shop, the arcade or the observation cafe ended in the air. Its door is its own spot on its floor nearest that entrance:
-- an anchor (each stands on the floor, places-v1/anchor-ground.json), not a lift, stair or gate.
do
  local shared = {}
  for _, p in ipairs(places) do
    local d = p.door
    if d and #d == 3 and d[3] >= 1450 then local key = ('%.0f,%.0f'):format(d[1], d[2]); shared[key] = (shared[key] or 0) + 1 end
  end
  for _, p in ipairs(places) do
    local d = p.door
    if d and #d == 3 and d[3] >= 1450 and shared[('%.0f,%.0f'):format(d[1], d[2])] > 1 then
      local best, far
      for _, an in ipairs(p.anchors or {}) do
        local name = an.name or ''
        if not (name:match('^lift') or name:match('^stair') or name:match('^gate')) and math.abs(an.pos[3] - d[3]) < 100 then
          local dist = (an.pos[1] - d[1]) ^ 2 + (an.pos[2] - d[2]) ^ 2
          if not far or dist < far then best, far = an, dist end
        end
      end
      if best then
        print(('door: %s upstairs, from the entrance below to its %s, %.0f,%.0f -> %.0f,%.0f'):format(p.id, best.name, d[1], d[2], best.pos[1], best.pos[2]))
        p.door = { best.pos[1], best.pos[2], d[3] }
      end
    end
  end
end

-- A shop turned to face east (its ground floor S##_F01 at yaw -90) had its door on its back wall: the street entrance was
-- read in the building's own frame without its turn, so it came out mirrored. The front wall is cut open and rebuilt with
-- the door (shop-refits-v1), the back is whole, and a walk to the karaoke, the bowling alley, the nursery and eight more
-- ended against the back wall (the game's places_check, 11-09). A door on a shop's back half moves to the same spot on its
-- front: mirrored through the building's middle. The street the shops face is between the rows, so the front is +X at yaw
-- -90 and -X at yaw 90.
do
  local f = io.open(ACTORS, 'rb')
  if f then
    local floors = {}
    for _, a in ipairs(json.decode(f:read('a')).actors) do if (a.label or ''):match('^S%d+_F01$') and a.c and a.e then floors[#floors + 1] = a end end
    f:close()
    local mirrored = 0
    for _, p in ipairs(places) do
      local d = p.door
      -- door_measured: chosen and walked through (build_street_city_places.lua ENTRY), not a mirrored entry-A
      if d and #d == 3 and d[3] < 1450 and not p.door_measured then
        for _, a in ipairs(floors) do
          if math.abs(d[1] - a.c[1]) <= a.e[1] + 20 and math.abs(d[2] - a.c[2]) <= a.e[2] + 20 then
            local t = math.rad(a.yaw or 0)
            local fx, fy = -math.sin(t), math.cos(t)
            local along = (d[1] - a.c[1]) * fx + (d[2] - a.c[2]) * fy
            local depth = math.abs(fx) > .5 and a.e[1] or a.e[2]
            if along < -(depth - 100) then
              local x, y = 2 * a.c[1] - d[1], 2 * a.c[2] - d[2]
              print(('door: %s on the back of %s, %.0f,%.0f -> %.0f,%.0f'):format(p.id, a.label, d[1], d[2], x, y))
              p.door = { x, y, d[3] }; mirrored = mirrored + 1
            end
            break
          end
        end
      end
    end
    if mirrored > 0 then print(('%d shop doors moved from the back wall to the front'):format(mirrored)) end
  end
end

-- A gate's spot inside one of its posts: the campus gate's anchor (and door) was the left post's middle, so in the game no
-- road point could be tied to it, the fence cut the whole campus off the roads (3043 points dropped) and every walk to a
-- lecture hall, the dorms or the sports ground ended at the fence (the game's places_check, 11-09). The spot is the middle of
-- the opening between that post and the nearest other post of the same gate.
do
  local posts = {}
  local f = io.open(ACTORS, 'rb')
  if f then
    for _, a in ipairs(json.decode(f:read('a')).actors) do
      if a.c and a.e and (a.label or ''):lower():match('gate') and math.max(a.e[1], a.e[2]) < 500 then posts[#posts + 1] = a end
    end
    f:close()
  end
  local function inside(a, x, y, z) return math.abs(x - a.c[1]) <= a.e[1] and math.abs(y - a.c[2]) <= a.e[2] and z + 100 >= a.c[3] - a.e[3] and z <= a.c[3] + a.e[3] end
  local function opening(x, y, z)
    for _, a in ipairs(posts) do
      if inside(a, x, y, z) then
        local other, far
        for _, b in ipairs(posts) do
          local d = (b.c[1] - a.c[1]) ^ 2 + (b.c[2] - a.c[2]) ^ 2
          if b ~= a and d < 1000 ^ 2 and math.abs(b.c[3] - a.c[3]) < 300 and (not far or d < far) then other, far = b, d end
        end
        if other then
          -- across the axis the two posts stand apart on, the middle between their inner faces
          local gx, gy = (a.c[1] + other.c[1]) / 2, (a.c[2] + other.c[2]) / 2
          if math.abs(other.c[1] - a.c[1]) >= math.abs(other.c[2] - a.c[2]) then
            local lo, hi = a, other; if lo.c[1] > hi.c[1] then lo, hi = hi, lo end
            gx = ((lo.c[1] + lo.e[1]) + (hi.c[1] - hi.e[1])) / 2
          else
            local lo, hi = a, other; if lo.c[2] > hi.c[2] then lo, hi = hi, lo end
            gy = ((lo.c[2] + lo.e[2]) + (hi.c[2] - hi.e[2])) / 2
          end
          return gx, gy, a.label
        end
      end
    end
  end
  for _, p in ipairs(places) do
    for _, an in ipairs(p.anchors or {}) do
      if (an.name or ''):match('^gate') then
        local x, y, post = opening(an.pos[1], an.pos[2], an.pos[3])
        if x then
          local d = p.door
          if d and math.abs(d[1] - an.pos[1]) < 1 and math.abs(d[2] - an.pos[2]) < 1 then p.door = { x, y, d[3] } end
          print(('gate: %s %s out of %s, %.0f,%.0f -> %.0f,%.0f'):format(p.id, an.name, post, an.pos[1], an.pos[2], x, y))
          an.pos = { x, y, an.pos[3] }
        end
      end
    end
  end
end

for _, p in ipairs(places) do
  if not p.door or #p.door ~= 3 then problem(p.id .. ': no door') end
  if not p.rooms or #p.rooms == 0 then problem(p.id .. ': no rooms') end
  local r = {}
  for _, room in ipairs(p.rooms or {}) do
    -- The motel's rooms are a centre, a size and a quarter-turn yaw.
    if room.center and room.size then
      local turned = (room.yaw or 0) % 180 ~= 0
      local hx, hy, hz = (turned and room.size[2] or room.size[1]) / 2, (turned and room.size[1] or room.size[2]) / 2, room.size[3] / 2
      room.min = { room.center[1] - hx, room.center[2] - hy, room.center[3] - hz }
      room.max = { room.center[1] + hx, room.center[2] + hy, room.center[3] + hz }
    end
    if not room.min or not room.max then problem(p.id .. ': a room without min/max')
    else
      -- a room up in a building without a floor number was taken for the ground floor, so the game walked to the gym storage
      -- on the street instead of taking the lift (11-08): above 14.5 m it is numbered by the nearest lift stop of the building
      -- it is in, else 4 m a floor
      local floor = room.floor or (room.min[3] >= 1450 and floorof(room) or 1)
      r[#r + 1] = '{"min":' .. vec(room.min) .. ',"max":' .. vec(room.max) .. ',"floor":' .. num(floor) .. '}'; rooms = rooms + 1
    end
  end
  local a, seen = {}, {}
  for _, anchor in ipairs(p.anchors or {}) do
    if seen[anchor.name] then problem(p.id .. ': anchor ' .. anchor.name .. ' twice') end
    seen[anchor.name] = true
    local row = '{"name":' .. quoted(anchor.name) .. ',"pos":' .. vec(anchor.pos) .. ',"yaw":' .. num(anchor.yaw or 0)
    if anchor.seat_pos then row = row .. ',"seat_pos":' .. vec(anchor.seat_pos) end
    a[#a + 1] = row .. '}'; anchors = anchors + 1
  end
  lines[#lines + 1] = '{"id":' .. quoted(p.id) .. ',"name":' .. quoted(p.name or p.id) .. ',"door":' .. vec(p.door or { 0, 0, 0 })
    .. ',"outdoor":' .. tostring(p.outdoor == true) .. ',"privacy":' .. num(p.privacy or 0)
    .. ',"rooms":[' .. table.concat(r, ',') .. '],"anchors":[\n' .. table.concat(a, ',\n') .. ']}'
end

local lots = {}
for _, lot in ipairs(data.lots or {}) do
  lots[#lots + 1] = '{"id":' .. quoted(lot.id) .. ',"center":' .. vec(lot.center) .. ',"size":[' .. num(lot.size_cm[1]) .. ',' .. num(lot.size_cm[2]) .. '],"yaw":' .. num(lot.yaw or 0) .. '}'
end

-- The walking graph for long walks: a point every LATTICE cells of world-edge-v1/road-raster.json (2 m a cell: 'r' road,
-- 'g' grass, 'o' buildings and water), a link where the straight line between two neighbours stays on road or grass (the
-- roads alone are thin lines that do not meet). The biggest connected part is kept.
local LATTICE, GROUND_Z = 3, 1200 -- 6 m: fine enough to find the gates in the fences
local raster = json.decode(read(ROOT .. 'output/street-social-city-production/world-edge-v1/road-raster.json'))
local rows, step, ox, oy = raster.rows, raster.step_cm, raster.origin[1], raster.origin[2]
-- The campus fence's five gates are 'o' in the picture, the fence round them too, so no link went through a gate: the parts
-- inside were tied on across the fence, the game dropped those ties, and the whole campus (3043 points) was cut off the roads
-- (11-09). Each gate's passage (flat-campus-v1/install.json: centre, yaw facing out, clear width) is opened, 12 m each way.
do
  local f = io.open(ROOT .. 'output/street-social-city-production/flat-campus-v1/install.json', 'rb')
  if f then
    local gates = ((json.decode(f:read('a')).enclosure or {}).gates) or {}; f:close()
    local rows_ = {}
    for i, row in ipairs(rows) do rows_[i] = {} for k = 1, #row do rows_[i][k] = row:sub(k, k) end end
    for _, g in ipairs(gates) do
      local yaw = math.rad(g.yaw or 0)
      local nx, ny = math.cos(yaw), math.sin(yaw)
      local half = (g.clear_width_cm or g.width or 800) / 2 - 100
      for along = -1200, 1200, step / 2 do
        for across = -half, half, step / 2 do
          local x, y = g.center[1] + nx * along - ny * across, g.center[2] + ny * along + nx * across
          local k, i = math.floor((x - ox) / step + 1.5), math.floor((y - oy) / step + 1.5)
          if rows_[i] and rows_[i][k] == 'o' then rows_[i][k] = 'g' end
        end
      end
      print(('road graph: opened the %s gate at %.0f,%.0f'):format(g.id, g.center[1], g.center[2]))
    end
    rows = {}
    for i, cells in ipairs(rows_) do rows[i] = table.concat(cells) end
  else problem('no flat-campus-v1/install.json: the campus gates are not opened') end
end
local function road(k, i) local row = rows[i]; if not row then return false end; local c = row:sub(k, k); return c == 'r' or c == 'g' end
local grid, nodes = {}, {}
for i = 1, #rows, LATTICE do
  for k = 1, #rows[1], LATTICE do
    local best
    for r = 0, LATTICE // 2 do
      for di = -r, r do for dk = -r, r do
        if not best and math.max(math.abs(di), math.abs(dk)) == r and road(k + dk, i + di) then best = { k + dk, i + di } end
      end end
      if best then break end
    end
    if best then nodes[#nodes + 1] = { k = best[1], i = best[2], gk = k, gi = i, links = {} }; grid[k .. ':' .. i] = #nodes end
  end
end
local function clear(a, b)
  local n = math.max(math.abs(a.k - b.k), math.abs(a.i - b.i))
  for s = 0, n do
    if not road(math.floor(a.k + (b.k - a.k) * s / n + .5), math.floor(a.i + (b.i - a.i) * s / n + .5)) then return false end
  end
  return true
end
for index, a in ipairs(nodes) do
  for _, d in ipairs({ { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }) do
    local other = grid[(a.gk + d[1] * LATTICE) .. ':' .. (a.gi + d[2] * LATTICE)]
    if other and clear(a, nodes[other]) then a.links[#a.links + 1] = other; nodes[other].links[#nodes[other].links + 1] = index end
  end
end
local seen, parts = {}, {}
for index in ipairs(nodes) do
  if not seen[index] then
    local part, head = { index }, 1
    seen[index] = true
    while head <= #part do
      for _, next_ in ipairs(nodes[part[head]].links) do if not seen[next_] then seen[next_] = true; part[#part + 1] = next_ end end
      head = head + 1
    end
    parts[#parts + 1] = part
  end
end
table.sort(parts, function(a, b) return #a > #b end)
local biggest = parts[1] or {}
if #biggest < 50 then problem('the road graph has only ' .. #biggest .. ' connected points') end
-- A part beside the main one is usually the raster's mistake: 'o' cells are coarse, and the map lets him through there (checked
-- on foot for three of them, all within 6 m). Tie it on at its closest point; the game sweeps every link against the map when it
-- loads and drops the ones a wall really blocks.
local BRIDGE_CELLS, BRIDGE_MIN_POINTS, BRIDGE_TIES = 5, 20, 12
for p = 2, #parts do
  local part = parts[p]
  if #part >= BRIDGE_MIN_POINTS then
    -- Several ties, the closest few from different points: the game drops the ones a fence blocks, so one is not enough.
    local near = {}
    for _, x in ipairs(part) do
      local best, y_best = (BRIDGE_CELLS + 1) ^ 2
      for _, y in ipairs(biggest) do
        local d = (nodes[x].k - nodes[y].k) ^ 2 + (nodes[x].i - nodes[y].i) ^ 2
        if d < best then best, y_best = d, y end
      end
      if y_best then near[#near + 1] = { d = best, a = x, b = y_best } end
    end
    table.sort(near, function(l, r) return l.d < r.d end)
    local a
    for n = 1, math.min(#near, BRIDGE_TIES) do
      local tie = near[n]; a = a or tie.a
      nodes[tie.a].links[#nodes[tie.a].links + 1] = tie.b; nodes[tie.b].links[#nodes[tie.b].links + 1] = tie.a
    end
    if a then
      for _, x in ipairs(part) do biggest[#biggest + 1] = x end
      print(('road graph: tied a part of %d points on at %.0f,%.0f'):format(#part, ox + (nodes[a].k - 1) * step, oy + (nodes[a].i - 1) * step))
    end
  end
end
-- Walk-through passages inside buildings: the raster has every building as 'o', so a shop opened at both ends adds no
-- points. Each passage is a chain of points (world cm) on its clear floor, its two ends tied to the nearest road points.
-- S32: the shop row S26-S43 stood 222 m unbroken; its ground floor got a back door in the west wall (x 43000,
-- y 28440-28600) facing the shop door on the east (x 45020, y 28780-28980), map cut 11-13 by
-- Tools/street_city_shop_passage_payload.lua (collision grid in places-v1/shop-passage-after-1113.json). East of x 44400 the
-- line keeps to y 28570: the shop counter (ShopV1_S32_Refit) stands at x 44615-44720 up to y 28525, and the game's road check
-- (30 cm capsule) dropped the passage there (places-v1/passage-sweep2.json, 11-13).
-- SP gym corridor: the gym_hall door (77174.7, 34274.6) opens on a 240 cm corridor between the SP walls at x 76880 and 77120
-- that runs north out of the SP block (its north wall, y ~37900-39132, is closed everywhere else). No road point lay in it,
-- so the gym was walked round the whole SP block: campus_e1 72 m straight, 891 m by road. A 30 cm capsule at +105 is clear
-- along x 76950-77050 from y 34500 to 39800 (places-v1/gym-passage-sweep.json, walk probe places-v1/walk-probe.json, 11-13).
-- The north end stops at y 39500, within the tie distance of the y 39100 road row.
local PASSAGES = {
  { id = 's32', pts = { { 42760, 28520 }, { 43200, 28520 }, { 43800, 28520 }, { 44400, 28570 }, { 44800, 28570 }, { 44800, 28880 }, { 45160, 28880 } } },
  { id = 'sp_gym', pts = { { 77174.7, 34274.6 }, { 77000, 34350 }, { 77000, 35400 }, { 77000, 36400 }, { 77000, 37400 }, { 77000, 38400 }, { 77000, 39500 } } },
  -- 11-13 batch (map cut on the source map, Tools/street_city_shop_passage_payload.lua / street_city_fence_gaps_payload.lua;
  -- boxes and walk probes in places-v1/shop-passage-batch*-apply-1113.json, fence-gaps-dorm-apply-1113.json,
  -- walk-probe-batch2-after-1113.json). The shops have no game place on the ground floor; their 3F homes stay.
  -- S56: west shop row (x 33300-35060), cut through at y 31240-31480 (front wall, inner walls, back wall).
  -- The west door's first two points at y 31270: on the 31360 line the game character stuck at x 33170 on a planter and
  -- hose rack just inside (the probe's thinner capsule got by); walked through at 31260-31272 both ways in the WP (11-14).
  { id = 's56', pts = { { 32700, 31270 }, { 33300, 31270 }, { 34000, 31360 }, { 34700, 31360 }, { 35300, 31360 }, { 35700, 31360 } } },
  -- S64: west shop row (x 33200-35160), front and back wall cut at y 41200-41440.
  { id = 's64', pts = { { 32800, 41320 }, { 33300, 41320 }, { 34000, 41320 }, { 34700, 41320 }, { 35300, 41320 }, { 35700, 41320 } } },
  -- S38: east shop row (x 43100-44880), west wall cut at y 36380-36580; the east side was open at y 36740-36920.
  { id = 's38', pts = { { 42800, 36460 }, { 43300, 36460 }, { 44000, 36460 }, { 44420, 36480 }, { 44420, 36820 }, { 45000, 36830 }, { 45400, 36830 } } },
  -- Campus east fence (x 97000) beside the girls' dorm D1: 17 pieces taken out at y 39760-40190 (the fence ran unbroken
  -- from y 20000 to 47800; girls_dorm -> playground was 551 m for 100 m straight).
  { id = 'fence_d1', pts = { { 96500, 39975 }, { 97000, 39975 }, { 97500, 39975 } } },
  -- S16 (west shop row, backs at x 48960 shut off the campus South Walk gate from the shops): front door y 39940-40110,
  -- inside south of the wall at x 48280-48400, out through the back opening y 40220-40420 whose 140 cm panel was cut.
  -- Points follow walk-probe-s16-final-1113.json, except the two at the front door: the probe's line clipped the door's
  -- north jamb (47000, 40110) and the game's wider capsule stuck on it (11-14 WP walk), so they keep 1 m south of it.
  { id = 's16', pts = { { 46300, 40260 }, { 46780, 40260 }, { 46860, 40010 }, { 47420, 40030 }, { 47900, 40060 }, { 48060, 40060 }, { 48220, 40180 }, { 48380, 40260 }, { 48860, 40260 }, { 49340, 40260 }, { 49500, 40380 }, { 49820, 40300 } } },
  -- Campus north fence (y 77000) was shut from x 54800 to 79600 though the campus_gate place stands on it: two fence
  -- panels removed at x 57980-58776 (fence-gaps-north-apply-1113 / apply2-1113). A kiosk stands in the opening west of
  -- x ~58600 and a lamp south of it, so the crossing keeps to x 58680 (walked both ways at x 58650 and 58700 in the WP
  -- on 11-14; x 58400 and 58600 stuck).
  { id = 'campus_north', pts = { { 58400, 76200 }, { 58680, 76700 }, { 58680, 77000 }, { 58680, 77300 }, { 58400, 77800 } } },
  -- Flower field: the road raster (world-edge-v1) ends at y ~110000 and the field (door 71700,114400) lies north of it, so
  -- its door point had no link at all and every walk there left the road graph (11-14). A line due north from the y 109900
  -- road row to the door; its north end is the door itself (no lattice there to tie to, the 'ties' problem is expected).
  { id = 'flower_field', pts = { { 71700, 110000 }, { 71700, 111200 }, { 71700, 112400 }, { 71700, 113400 }, { 71700, 114400 } } },
}
local PASSAGE_TIE_CM, PASSAGE_TIES = 800, 3
for _, pass in ipairs(PASSAGES) do
  local ids = {}
  for n, p in ipairs(pass.pts) do
    nodes[#nodes + 1] = { k = (p[1] - ox) / step + 1, i = (p[2] - oy) / step + 1, links = {} }
    ids[n] = #nodes
    if n > 1 then local a, b = ids[n - 1], ids[n]; nodes[a].links[#nodes[a].links + 1] = b; nodes[b].links[#nodes[b].links + 1] = a end
  end
  local tied = 0
  for _, e in ipairs({ ids[1], ids[#ids] }) do
    local near = {}
    for _, y in ipairs(biggest) do
      local d = math.sqrt((nodes[e].k - nodes[y].k) ^ 2 + (nodes[e].i - nodes[y].i) ^ 2) * step
      if d <= PASSAGE_TIE_CM then near[#near + 1] = { d = d, y = y } end
    end
    table.sort(near, function(l, r) return l.d < r.d end)
    for n = 1, math.min(#near, PASSAGE_TIES) do
      local y = near[n].y; nodes[e].links[#nodes[e].links + 1] = y; nodes[y].links[#nodes[y].links + 1] = e; tied = tied + 1
    end
  end
  for _, x in ipairs(ids) do biggest[#biggest + 1] = x end
  if tied < 2 then problem('passage ' .. pass.id .. ': ' .. tied .. ' ties to the roads') end
  print(('road graph: passage %s, %d points, %d ties'):format(pass.id, #ids, tied))
end
local keep = {}
for order, index in ipairs(biggest) do keep[index] = order - 1 end
local node_rows, link_rows = {}, {}
for order, index in ipairs(biggest) do
  local a = nodes[index]
  node_rows[order] = '[' .. num(ox + (a.k - 1) * step) .. ',' .. num(oy + (a.i - 1) * step) .. ',' .. GROUND_Z .. ']'
  for _, next_ in ipairs(a.links) do if keep[next_] and next_ > index then link_rows[#link_rows + 1] = '[' .. (order - 1) .. ',' .. keep[next_] .. ']' end end
end
-- The street walks' 26 stops: spread along the graph from the middle of town (the park).
local park
for _, p in ipairs(places) do if p.id == 'park' then park = p.door end end
local start, far = 1, math.huge
for order, index in ipairs(biggest) do
  local a = nodes[index]
  local d = (ox + (a.k - 1) * step - park[1]) ^ 2 + (oy + (a.i - 1) * step - park[2]) ^ 2
  if d < far then far = d; start = order end
end
local walk, walked, queue, head = {}, { [biggest[start]] = true }, { biggest[start] }, 1
while head <= #queue and #walk < 26 do
  if (head - 1) % 40 == 0 then walk[#walk + 1] = keep[queue[head]] end
  for _, next_ in ipairs(nodes[queue[head]].links) do if not walked[next_] then walked[next_] = true; queue[#queue + 1] = next_ end end
  head = head + 1
end

for _, text in ipairs(problems) do print('problem: ' .. text) end
print(string.format('%d places, %d rooms, %d anchors, %d lots, map %s', #places, rooms, anchors, #lots, (data.map_sha256 or '?'):sub(1, 12)))
print(string.format('road graph: %d of %d points, %d links, %d walk stops', #biggest, #nodes, #link_rows, #walk))
if check then os.exit(#problems == 0 and 0 or 1) end

local out = assert(io.open(TARGET, 'wb'))
out:write('{"schema":1,"map_sha256":', quoted(data.map_sha256 or ''), ',"places":[\n', table.concat(lines, ',\n'), '\n],"lots":[\n', table.concat(lots, ',\n'), '\n],"road":{"nodes":[', table.concat(node_rows, ','), '],\n"links":[', table.concat(link_rows, ','), '],\n"walk":[', table.concat(walk, ','), ']}}\n')
out:close()
print('wrote ' .. TARGET)
