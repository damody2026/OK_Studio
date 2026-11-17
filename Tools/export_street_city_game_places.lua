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
-- The anchors standing at a door's old spot move with it (DOOR_MOVES below): the playground's 'field' was its landmark's
-- middle like its door, in the swing set's collision box, 2 m from any open cell (out of the 80/140 cm rings the game
-- tries); the festival's 'fireworks' was fitted onto the ground at its door (Tools/street_city_anchor_fit_payload.lua)
-- and the trace down found the goldfish stall's top, 2.3 m up (the reach check, C4, 11-17).
local DOOR_MOVES = {}
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
      DOOR_MOVES[p.id] = { from = d, to = best }
      p.door = best; moved_doors = moved_doors + 1
    else problem(p.id .. ': door inside ' .. hit.label .. ' and no open ground round it') end
  end
end
if moved_doors > 0 then print(('%d doors moved out of props'):format(moved_doors)) end
-- the row (a place anchor or a rules-table row) to the door's new spot when it stood at the old one (x y within 5 cm, any
-- height); its seat and pair slots by the same offset. true when it moved.
local function with_door(place, r)
  local m = DOOR_MOVES[place]; local q = r.pos
  if not (m and q and math.abs(q[1] - m.from[1]) < 5 and math.abs(q[2] - m.from[2]) < 5) then return false end
  local to = { m.to[1], m.to[2], m.to[3] }
  print(('anchor: %s %s moved with its door, %.0f,%.0f,%.0f -> %.0f,%.0f,%.0f'):format(place, r.name, q[1], q[2], q[3], to[1], to[2], to[3]))
  dofile('Tools/street_city_moved_props.lua').carry(r, q, to); r.pos = to
  return true
end
for _, p in ipairs(places) do for _, an in ipairs(p.anchors or {}) do with_door(p.id, an) end end
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
-- Nor an anchor standing on something: the arcade's door was its racing2, on the racing seat 50 cm up, and the ramen
-- shop's its table2, 45 cm up; the walk grid steps 40 cm at most, so each door was an island and neither shop was reached
-- (Tools/street_city_reach_check.lua, 11-16). The walk-grid scan of that check (places-v1/reach-grid, the game's own cell
-- test) gives the ground under each candidate: one more than 40 cm off the floor, or not walkable, is not taken. Without
-- the scan (a fresh checkout) every candidate stays and a warning says so; the check finds an island door either way.
local reach_cell
do
  local tf = io.open(ROOT .. 'output/street-social-city-production/places-v1/reach-tiles.json', 'rb')
  local dir = ROOT .. 'output/street-social-city-production/places-v1/reach-grid/'
  if tf then
    tf:close()
    local okl, lfs = pcall(require, 'lfs')
    local cells = {}
    if okl and lfs.attributes(dir) then
      for n in lfs.dir(dir) do if n:match('%.json$') then
        local g = json.decode(read(dir .. n))
        for key, rows in pairs(g.tiles) do
          local tx, ty, z = key:match('^(%-?%d+)_(%-?%d+)_(%-?%d+)$'); tx, ty, z = tonumber(tx), tonumber(ty), tonumber(z)
          for jy, row in ipairs(rows) do local ix = tx * 40
            for code in row:gmatch('%S+') do cells[z .. ':' .. ix .. ':' .. (ty * 40 + jy - 1)] = code; ix = ix + 1 end end
        end end end
    end
    if next(cells) then
      local zs = {}; for k in pairs(cells) do local z = tonumber(k:match('^(%-?%d+)')); zs[z] = true end
      reach_cell = function(x, y, z)
        local code
        for zk in pairs(zs) do if math.abs(zk - z) <= 60 then
          code = cells[zk .. ':' .. math.floor(x / 40 + .5) .. ':' .. math.floor(y / 40 + .5)]
          if code then local g = code:match('^(%-?%d+),?$'); if not g then return false end; return math.abs(tonumber(g) + zk - z) <= 40 end end end
        return nil -- not scanned
      end
    end
  end
  if not reach_cell then print('warning: no walk-grid scan (Tools/street_city_reach_check.lua scan): upstairs doors not checked for raised spots') end
end
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
        -- nor a spot to sit or lie on: the ramen shop's door was its counter_seat4, behind the counter, and the walk from
        -- the 9F lift stopped at the counter (R6-197, 11-15)
        local sit = name:find('seat') or name:find('chair') or name:find('bed') or name:find('sofa') or name:find('bench')
        local raised = reach_cell and reach_cell(an.pos[1], an.pos[2], d[3]) == false
        if raised and not sit then print(('door: %s upstairs, %s not taken: raised or not walkable on the walk grid'):format(p.id, name)) end
        if not (name:match('^lift') or name:match('^stair') or name:match('^gate') or sit or raised) and math.abs(an.pos[3] - d[3]) < 100 then
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

-- Doors picked by hand where the nearest anchor is in a mesh: the bank's (civic 2F) was its counter, inside the counter's
-- collision (StaticMeshActor_496, pen=1), and every walk from the bank began wedged (nh1115k, 11-15). Its room is open to the
-- corridor along the south (floor scans z 1710 and 1640): the door is in that opening.
-- The arcade's (M1 8F, 44097,63905) and the ramen shop's (M1 9F, 47835,60370) doors stood on something 45-50 cm high (the
-- arcade's racing seat LoverSpot_R2_arcade_racing1_Seat), a step the walk grid does not take (40 cm): each door was an
-- island of 4-7 cells, so neither shop was reached from the mall floor (Tools/street_city_reach_check.lua, 11-16); the doors
-- move to the mall floor beside them, cells checked joined to the floor's 77-80 thousand cells (reach_check probe).
-- 11-16: the bank's (counter), the arcade's and the ramen shop's are now left to the rule above (raised or unwalkable
-- candidates are not taken); keep this for a door no rule can place, with the reason
local DOORS = {}
for _, p in ipairs(places) do
  local d = DOORS[p.id]
  if d then print(('door: %s by hand, %.0f,%.0f -> %.0f,%.0f'):format(p.id, p.door[1], p.door[2], d[1], d[2])); p.door = { d[1], d[2], d[3] } end
end
-- Spots picked by hand where the anchor is inside furniture the props list (actors.json) does not have: the cafeteria's
-- 'table' (COMMON-CITY-dining) was in the middle of its long table (StaticMeshActor_362, swept at 70223,42655 z 1275), so
-- he stood in it after a meal, no grid route found a first cell, and each walk out hit the table 30 times and gave up
-- (nh1115m, rounds 10 and 11). The aisle south of it (floor scans z 1290 and 1220) is open 1.5 m wide along y 42400-42500;
-- the spot is there, 85 cm off the table's edge at y 42555, facing it as before (yaw 90).
-- The cafe's 1F seats behind its first row of chairs: the game's nav grid (40 cm cells, a 40 cm capsule) floods from the
-- door only to y 21720 in the west seating block (x 47100-47800, chair rows at y 21775-21800 and 22100-22175, tables
-- between, the wall stub StaticMeshActor_6795 at its door end; scans z 1270 and 1245 at 25 cm), so a heroine sent to
-- seat3 (惠惠) or seat14 (三月七) was moved to a clear spot nobody could walk to (nh1115q round 13). These ten have no
-- reachable spot within the 80/140 cm rings SpotFor tries; they stand in the aisle in front of the block (y 21600) and
-- in the open aisle east of it (x 47920-48080), each checked clear and reachable on that grid, facing the tables (4th value: yaw).
-- The cafe's 'seat' (47378,21800, a chair of the first row) is also the activity anchor cafe_seat and cafe_meal pick: the
-- game's grid found no way to it from the door or from inside, at 40 nor at 30 cm (c-conquest /places_check, nh1115y);
-- it stands in the open aisle by the counter (y 21520) facing the tables, 80 cm off the row at y 21600.
local SPOTS = { ['cafeteria table'] = { 70230, 42470, 1200 }, ['cafe seat'] = { 47440, 21520, 1200, 90 },
  ['cafe seat3'] = { 47320, 21600, 1200, 90 }, ['cafe seat7'] = { 47400, 21600, 1200, 90 }, ['cafe seat8'] = { 47480, 21600, 1200, 90 },
  ['cafe seat9'] = { 47560, 21600, 1200, 90 }, ['cafe seat14'] = { 47640, 21600, 1200, 90 },
  ['cafe seat19'] = { 47920, 21840, 1200, 180 }, ['cafe seat23'] = { 47920, 21960, 1200, 180 }, ['cafe seat24'] = { 47920, 22080, 1200, 180 },
  ['cafe seat25'] = { 47920, 22200, 1200, 180 }, ['cafe seat31'] = { 48080, 22000, 1200, 180 },
  -- The sushi bar's conveyor stools (x 34307) and booth1's bench are in the shop's north-east room (x 33880-34400,
  -- y 48120-48960), walled off from the hall like the izakaya's (same S-row template; scans z 1270/1245, grid at 40 and
  -- 30 cm, 11-15): they stand at the conveyor's other side in the east aisle (x 34560) and in the hall west of the booth.
  ['sushi conveyor_seat'] = { 34560, 48520, 1200, 180 }, ['sushi conveyor_seat2'] = { 34560, 48440, 1200, 180 },
  ['sushi conveyor_seat3'] = { 34560, 48360, 1200, 180 }, ['sushi conveyor_seat4'] = { 34560, 48240, 1200, 180 },
  ['sushi seat33'] = { 33720, 48440, 1200, 0 }, ['sushi seat34'] = { 33720, 48520, 1200, 0 },
  -- The gyn clinic's seat20 is in the 30 cm slot between its cubicle (x 32305-32405) and the waiting room's wall (x 32435,
  -- City_CV_F01): the slot's open north end, the nearest open cell a 40 cm box reaches from the street (room survey 11-16)
  -- its waiting room's bench (LoverSpot_Gyn_Bench_Seat, x 32475-32525): seat, seat2, seat3 stood on the seat board; at
  -- its front edge now, the cells a 40 cm box reaches once crib3 moved (Tools/street_city_moved_props.lua, 11-16)
  -- (each also clear 20 cm round it on that grid: the game's 30 cm cells closed in on spots in 40 cm strips, nav1116c;
  -- seat3 has no such cell by the bench, it stands in the waiting room's middle)
  ['clinic_gyn seat'] = { 32605, 57345, 1200 }, ['clinic_gyn seat2'] = { 32605, 57385, 1200 },
  ['clinic_gyn seat3'] = { 32700, 57400, 1200 }, ['clinic_gyn seat20'] = { 32395, 57295, 1200 },
  -- The civic 5F lounges (City_CV_F05, StaticMeshActor_499): seat6 seat7 seat8 seat9 stood in the desks in front of their
  -- chairs (x 30535-30595), seat seat2 seat3 seat4 in the sofas; the game started each walk embedded in 499 (pen=1,
  -- c-conquest nav1116d). The cells by the chairs are 40 cm strips between desk, sofa and wall, where the game's 30 cm grid
  -- was closed in (6 cells, nav1116c). They stand in the open floor between the two lounges (y 61545-61705), each cell
  -- reached by a 40 cm box from the 5F corridor and clear 30 cm round it (room survey 11-16, box x 29000-31700
  -- y 61100-64000; the first box, to x 30200 only, missed the lounges' way in), 1.5-3 m off their seats: stand spots.
  ['civic seat6'] = { 30575, 61585, 2910 }, ['civic seat7'] = { 30645, 61585, 2910 },
  ['civic seat'] = { 30715, 61585, 2910 }, ['civic seat2'] = { 30805, 61585, 2910 },
  ['civic seat8'] = { 30575, 61665, 2910 }, ['civic seat9'] = { 30645, 61665, 2910 },
  ['civic seat3'] = { 30715, 61665, 2910 }, ['civic seat4'] = { 30805, 61665, 2910 },
  -- The nail salon's 2F chairs: each stand spot was 16 cm off its chair's collision (S59_F02, the editor walk probe from
  -- stair2 stopped 40 cm short of seat6, 11-16); 40 cm further from the chair, the seat stays 80 cm off
  ['nail seat6'] = { 33470, 34510, 1580 }, ['nail seat8'] = { 33470, 34890, 1580 },
  ['nail seat10'] = { 33890, 34510, 1580 }, ['nail seat12'] = { 33890, 34890, 1580 } }
for _, p in ipairs(places) do
  for _, an in ipairs(p.anchors or {}) do
    local s = SPOTS[p.id .. ' ' .. an.name]
    if s then print(('anchor: %s %s by hand, %.0f,%.0f -> %.0f,%.0f'):format(p.id, an.name, an.pos[1], an.pos[2], s[1], s[2]))
      -- moved off its seat (the cafe's back rows): a stand spot now, not sat down on a chair metres away
      if an.seat_pos and math.sqrt((an.seat_pos[1] - s[1]) ^ 2 + (an.seat_pos[2] - s[2]) ^ 2) > 150 then an.seat_pos = nil end
      an.pos = { s[1], s[2], s[3] }; if s[4] then an.yaw = s[4] end end
  end
end
-- The same spots for the rules' rows (city_anchors.json, below): the game's activities and c-conquest's navigation read the
-- anchors from there, and until 11-16 the spots were only in city_places.json (nav1116d still started civic seat6 in the desk)
local function spot_row(r)
  local s = SPOTS[(r.place or '') .. ' ' .. (r.name or '')]
  if not s or r.slots then return false end
  if r.pos and r.pos[1] == s[1] and r.pos[2] == s[2] and r.pos[3] == s[3] then return false end
  if r.seat_pos and math.sqrt((r.seat_pos[1] - s[1]) ^ 2 + (r.seat_pos[2] - s[2]) ^ 2) > 150 then r.seat_pos = nil end
  r.pos = { s[1], s[2], s[3] }; if s[4] then r.yaw = s[4] end
  return true
end

-- Anchors of furniture taken off the source map (the karaoke's KTV_2, 11-15): dropped here and from city_anchors.json
-- below (Tools/street_city_removed_anchors.lua, shared with Tools/build_street_city_places.lua)
local REMOVED = dofile('Tools/street_city_removed_anchors.lua')
-- Seats over no floor of their own: the S-row shops' third floor has a sofa and a chair planned over the stairwell
-- (places-v1/seats-fit.json, fit 'nominal', never measured; z 1960 where that floor has a hole). The build's floor
-- measurement (Tools/build_street_city_places.lua, 'at most one storey down') put their stand points on the stair's
-- landing (z 1770) and on its flight (1849, 1865), the seats staying up at 2002 / 1897: 188 rows, 14 floors of 7 shops
-- with no way up, girls sent to sit on a stair (the reach check's B1, S82 seen in the game 11-17). A row whose nominal
-- seats-fit source stood 60 to 300 cm above where it stands now is dropped; a measured one is never touched.
local VOID_SEATS = {}
do local f = io.open('output/street-social-city-production/places-v1/seats-fit.json', 'rb')
  if f then for _, r in ipairs(json.decode(f:read('a')).rows) do
    if r.fit == 'nominal' then local k = ('%.0f,%.0f'):format(r.pos[1], r.pos[2]); VOID_SEATS[k] = VOID_SEATS[k] or {}; table.insert(VOID_SEATS[k], r.pos[3]) end end
    f:close()
  else problem('no places-v1/seats-fit.json: seats over the stairwells not dropped') end
end
local function void_seat(r)
  local q = r.pos; if not (q and r.seat_pos) then return nil end
  for _, z in ipairs(VOID_SEATS[('%.0f,%.0f'):format(q[1], q[2])] or {}) do
    if z - q[3] > 60 and z - q[3] < 300 then return ('a nominal seat at z %.0f, its stand point pulled down to %.0f'):format(z, q[3]) end end
end
-- anchors of props moved on the source map after the install (Tools/street_city_moved_props.lua) move with them
do local PROPS = dofile('Tools/street_city_moved_props.lua')
  for _, p in ipairs(places) do for _, an in ipairs(p.anchors or {}) do local q = PROPS.shift(p.id, an.name, an.pos)
    if q then print(('anchor: %s %s moved with its prop'):format(p.id, an.name)); PROPS.carry(an, an.pos, q); an.pos = q end end end end
for _, p in ipairs(places) do
  if p.anchors then local kept = {}
    for _, an in ipairs(p.anchors) do
      local why = REMOVED.gone(p.id, an.name) or void_seat(an)
      if why then print(('anchor: %s %s dropped, %s'):format(p.id, an.name, why)) else kept[#kept + 1] = an end
    end
    p.anchors = kept end
end
-- Rooms left out of a place (REMOVED.rooms), then the check that a place is one building with its door: an indoor place's
-- rooms grouped by being within REMOVED.apart_cm of each other (xy, any floor); a group without the door is a part a girl
-- would be walked to from another building's door (bike_shop, 116 m, 11-16). Listed as problems unless REMOVED.apart_ok.
-- The dropped rooms' boxes per place: the rules-table rows standing in them go too (city_anchors.json below).
local DROPPED_ROOMS = {}
do
  local function bounds(room)
    if room.min and room.max then return room.min, room.max end
    if room.center and room.size then local h = math.max(room.size[1], room.size[2]) / 2
      return { room.center[1] - h, room.center[2] - h }, { room.center[1] + h, room.center[2] + h } end
  end
  local function gap(a, b)
    local a0, a1 = bounds(a); local b0, b1 = bounds(b)
    local dx = math.max(0, a0[1] - b1[1], b0[1] - a1[1]); local dy = math.max(0, a0[2] - b1[2], b0[2] - a1[2])
    return math.sqrt(dx * dx + dy * dy)
  end
  for _, p in ipairs(places) do
    if p.rooms then local kept = {}
      for _, room in ipairs(p.rooms) do local why = REMOVED.room_gone(p.id, room)
        if why then print(('room: %s room dropped, %s'):format(p.id, why))
          local a0, a1 = bounds(room); DROPPED_ROOMS[p.id] = DROPPED_ROOMS[p.id] or {}; table.insert(DROPPED_ROOMS[p.id], { min = a0, max = a1 })
        else kept[#kept + 1] = room end end
      p.rooms = kept end
    if REMOVED.names[p.id] then p.name = REMOVED.names[p.id] end
  end
  -- Every indoor room of every place, so a building is followed through the rooms of its other places (the sports hall's
  -- parts join through the gym's floors); rooms of one place are one building when a chain of rooms, each within
  -- apart_cm of the next, joins them.
  local all = {}
  for _, q in ipairs(places) do if not q.outdoor then for _, room in ipairs(q.rooms or {}) do if bounds(room) then all[#all + 1] = room end end end end
  local link = {}
  for i = 1, #all do link[i] = i end
  local function root(i) while link[i] ~= i do link[i] = link[link[i]]; i = link[i] end; return i end
  for i = 1, #all do for k = i + 1, #all do if gap(all[i], all[k]) <= REMOVED.apart_cm then link[root(k)] = root(i) end end end
  local index = {}; for i, room in ipairs(all) do index[room] = i end
  for _, p in ipairs(places) do
    if not p.outdoor and p.rooms and #p.rooms > 1 and p.door and not REMOVED.apart_ok[p.id] then
      local n = #p.rooms
      local function find(i) return index[p.rooms[i]] and root(index[p.rooms[i]]) or -i end
      local door
      for i = 1, n do local a0, a1 = bounds(p.rooms[i])
        if a0 and p.door[1] >= a0[1] - 300 and p.door[1] <= a1[1] + 300 and p.door[2] >= a0[2] - 300 and p.door[2] <= a1[2] + 300 then door = find(i) end end
      local far = {}
      for i = 1, n do if find(i) ~= door then local a0, a1 = bounds(p.rooms[i]); if a0 then
        far[#far + 1] = ('(%d,%d)-(%d,%d)'):format(a0[1], a0[2], a1[1], a1[2]) end end end
      if #far > 0 then problem(('%s: rooms not in the building of its door (%d m apart or more): %s'):format(p.id, REMOVED.apart_cm // 100, table.concat(far, ' '))) end
    end
  end
end

-- The shops' stairs (Tools/street_city_shop_stairs.lua, found on the source map 11-16): stairN on each floor's end of the
-- stair, the game's way up in a shop with no lift (c-conquest's shop stairs, stair1116c). Shared with
-- Tools/build_street_city_places.lua; with them the place is no longer upstairs-off (Tools/street_city_upstairs_off.lua).
local STAIRS = dofile('Tools/street_city_shop_stairs.lua')
for _, p in ipairs(places) do
  for _, s in ipairs(STAIRS[p.id] or {}) do
    p.anchors = p.anchors or {}
    local had = false
    for _, an in ipairs(p.anchors) do if an.name == s.name then an.pos = { s.pos[1], s.pos[2], s.pos[3] }; had = true end end
    if not had then p.anchors[#p.anchors + 1] = { name = s.name, pos = { s.pos[1], s.pos[2], s.pos[3] }, yaw = 0 } end
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

-- More ways into a building than its door: the game goes into and out of a place indoors by the outermost building's way in
-- nearest the walk (CityRoute, entrance* anchors on the door's floor). The sports building's door is its south end
-- (77000,21000) and the gym hall's 34274, so campus_e1 -> gym_hall went 341 m for 72 and 27 pairs over 2x (11-15); its north
-- way in is where the e1_pool corridor enters (77030,39080), a road point, clear at z 1290 and 1220 with 40 cm clearance.
-- Each entrance must be a point of city_roads.json, like a door: Tools/street_city_entrances_tie.lua ties them in.
-- The rest (11-15): floor scans (z 1290 and 1220, 50 cm, every big ground-floor building and 10 m round it); from a spot
-- 9 m inside the door, with the door shut, the shortest way out of the rooms, the narrowest point where it leaves them, then
-- that shut too and again; kept 25 m or more from the door and from each other (the campus blocks' side corridor ends and
-- back doors, the dorms', the library's...). Not the hotel: its door is 10 m south of the building, the search began outside.
local ENTRANCES = {
  campus_sports = { { name = 'entrance', pos = { 77030, 39080, 1200 } }, { name = 'entrance2', pos = { 66925, 21625, 1200 } },
    { name = 'entrance3', pos = { 66725, 25475, 1200 } }, { name = 'entrance4', pos = { 66925, 38425, 1200 } },
    { name = 'entrance5', pos = { 66925, 29825, 1200 } }, { name = 'entrance6', pos = { 66925, 34075, 1200 } } },
  boys_dorm = { { name = 'entrance', pos = { 90625, 60343, 1200 } }, { name = 'entrance2', pos = { 93125, 65993, 1200 } } },
  cafeteria = { { name = 'entrance', pos = { 66925, 44793, 1200 } }, { name = 'entrance2', pos = { 69425, 49193, 1200 } } },
  campus_ad = { { name = 'entrance', pos = { 64425, 69793, 1200 } }, { name = 'entrance2', pos = { 66925, 74193, 1200 } } },
  campus_e1 = { { name = 'entrance', pos = { 76025, 44543, 1200 } }, { name = 'entrance2', pos = { 78225, 50693, 1200 } } },
  campus_ee = { { name = 'entrance', pos = { 80425, 62643, 1200 } }, { name = 'entrance2', pos = { 82925, 65493, 1200 } } },
  campus_ib = { { name = 'entrance', pos = { 57925, 74493, 1200 } }, { name = 'entrance2', pos = { 55425, 71843, 1200 } } },
  campus_ma = { { name = 'entrance', pos = { 74425, 62643, 1200 } }, { name = 'entrance2', pos = { 76925, 65493, 1200 } } },
  campus_rb = { { name = 'entrance', pos = { 57975, 48843, 1200 } }, { name = 'entrance2', pos = { 55425, 45843, 1200 } } },
  campus_t1 = { { name = 'entrance', pos = { 61425, 53643, 1200 } }, { name = 'entrance2', pos = { 63925, 56493, 1200 } } },
  campus_t2 = { { name = 'entrance', pos = { 74175, 71393, 1200 } }, { name = 'entrance2', pos = { 76925, 74493, 1200 } } },
  campus_t4 = { { name = 'entrance', pos = { 61425, 45643, 1200 } }, { name = 'entrance2', pos = { 63925, 48493, 1200 } } },
  civic = { { name = 'entrance', pos = { 31447, 63930, 1200 } } },
  department = { { name = 'entrance', pos = { 40825, 65425, 1200 } }, { name = 'entrance2', pos = { 45925, 73225, 1200 } } },
  girls_dorm = { { name = 'entrance', pos = { 90625, 36343, 1200 } }, { name = 'entrance2', pos = { 93125, 41993, 1200 } } },
  library = { { name = 'entrance', pos = { 55425, 62293, 1200 } }, { name = 'entrance2', pos = { 57925, 66693, 1200 } } },
  station = { { name = 'entrance', pos = { 20835, 15825, 1200 } } },
}
for _, p in ipairs(places) do
  for _, e in ipairs(ENTRANCES[p.id] or {}) do
    p.anchors = p.anchors or {}
    if p.door and math.abs(e.pos[3] - p.door[3]) >= 150 then problem(p.id .. ': ' .. e.name .. ' not on the door\'s floor') end
    p.anchors[#p.anchors + 1] = { name = e.name, pos = e.pos, yaw = 0 }
  end
end

-- Upstairs anchors of a street-level place with no lift or stair anchor at all (Tools/street_city_upstairs_off.lua, the
-- one rule shared with Tools/build_street_city_places.lua for city_anchors.json): no route leads up there, yet the
-- schedule sent heroines up and they stood stuck (the cafe's 2F seats, 11-15). Kept, not dropped: renamed off_<name> so
-- no activity's anchor prefix picks them, with "off" saying why; the list is the work list for adding stairs, written
-- to Docs/STREET_CITY_UPSTAIRS_NO_STAIRS.md. The rules' rows of the same anchors get the same name and no kinds.
local UPSTAIRS_FIRST = { 'cafe', 'restaurant', 'conveni', 'fastfood', 'izakaya', 'karaoke', 'manga_cafe', 'onsen' }
local UP = dofile('Tools/street_city_upstairs_off.lua')(places)
local offrows = {}
local function offrow(id, o) local key = id .. ' ' .. tostring(o.floor or '-')
  local row = offrows[key]; if not row then row = { place = id, floor = o.floor, real = o.real, names = {}, rules = 0 }; offrows[key] = row end
  return row end
for _, p in ipairs(places) do
  for _, an in ipairs(p.anchors or {}) do local o = UP.off(p.id, an.pos)
    if o then local row = offrow(p.id, o); row.names[#row.names + 1] = (an.name:gsub('^' .. UP.PREFIX, '')); UP.mark(an); an.off = 'no lift or stair in the place' end
  end
end
-- city_anchors.json: the same rows marked in place (Tools/build_street_city_places.lua marks them too when it is re-run;
-- its output drifted from the committed table on 11-15, so the table is not rebuilt here); a second run changes nothing
do
  local path = 'Content/IndependentResources/StreetSocialData/city_anchors.json'
  local f = assert(io.open(path, 'rb')); local s = f:read('a'); f:close()
  local okj = require('ok.json'); local T = okj.decode(s); local n = 0
  local back = 0
  for _, r in ipairs(T.anchors) do local o = UP.off(r.place, r.pos)
    if o then local row = offrow(r.place, o); row.rules = row.rules + 1
      -- the kinds are kept beside it (off_kinds), for when the place gets its stairs
      if UP.mark(r) then r.id = r.place .. '.' .. r.name; r.off_kinds = r.kinds; r.kinds = {}; r.tags = r.tags or {}; r.tags[#r.tags + 1] = 'off'; n = n + 1 end
    elseif r.tags and r.name:sub(1, #UP.PREFIX) == UP.PREFIX then
      -- off before, its place has a way up now (the shops' stairs): its name, kinds and tags back
      local tags = {}; for _, t in ipairs(r.tags) do if t ~= 'off' then tags[#tags + 1] = t end end
      if #tags < #r.tags and r.off_kinds then UP.unmark(r); r.id = r.place .. '.' .. r.name; r.kinds = r.off_kinds; r.off_kinds = nil
        r.tags = #tags > 0 and tags or nil; back = back + 1 end
    end
  end
  -- the stair rows (Tools/street_city_shop_stairs.lua), as the dorms' and the campus's: no kinds, the building and floor
  -- of the place's rows on that floor
  local have, stairs = {}, 0
  for _, r in ipairs(T.anchors) do have[r.id] = r end
  for id, list in pairs(STAIRS) do for k, s in ipairs(list) do
    local fl = tonumber(s.name:match('^stair(%d+)')); local like
    for _, r in ipairs(T.anchors) do if r.place == id and (r.floor or 1) == fl and r.building then like = r; break end end
    if not like then for _, r in ipairs(T.anchors) do if r.place == id and r.building then like = r; break end end end
    local rid = id .. '.' .. s.name; local r = have[rid]
    if not r then r = { id = rid, place = id, name = s.name, kinds = {}, outdoor = false, privacy = 0, yaw = 0 }; T.anchors[#T.anchors + 1] = r; have[rid] = r; stairs = stairs + 1 end
    if not (r.pos and r.pos[1] == s.pos[1] and r.pos[2] == s.pos[2] and r.pos[3] == s.pos[3]) then r.moved = true end
    r.pos = { s.pos[1], s.pos[2], s.pos[3] }; r.building = like and like.building or r.building; r.floor = fl > 1 and fl or nil
  end end
  -- anchors of props moved on the source map (Tools/street_city_moved_props.lua): with them
  local spotted = 0
  for _, r in ipairs(T.anchors) do if spot_row(r) then r.moved = true; spotted = spotted + 1 end end
  print(('city_anchors.json: %d rows moved to their spots by hand'):format(spotted))
  for _, r in ipairs(T.anchors) do if with_door(r.place, r) then r.moved = true end end
  local PROPS = dofile('Tools/street_city_moved_props.lua')
  for _, r in ipairs(T.anchors) do local q = PROPS.shift(r.place, r.name, r.pos)
    if q then print(('anchor: %s %s moved with its prop, %.0f,%.0f -> %.0f,%.0f'):format(r.place, r.name, r.pos[1], r.pos[2], q[1], q[2]))
      PROPS.carry(r, r.pos, q); r.pos = q; r.moved = true end end
  local moved = 0; for _, r in ipairs(T.anchors) do if r.moved then moved = moved + 1; r.moved = nil end end
  print(('city_anchors.json: %d rows back from off (the place has stairs now), %d stair rows added'):format(back, stairs))
  local kept, dropped = {}, 0
  -- rows of a removed anchor, and rows standing in a room left out of their place (REMOVED.rooms: bike_shop's S81 racks)
  local function in_gone_room(r)
    for _, box in ipairs(DROPPED_ROOMS[r.place] or {}) do
      if r.pos and r.pos[1] >= box.min[1] and r.pos[1] <= box.max[1] and r.pos[2] >= box.min[2] and r.pos[2] <= box.max[2] then return true end
    end
  end
  local voids = 0
  for _, r in ipairs(T.anchors) do
    if REMOVED.gone(r.place, r.name) or in_gone_room(r) then dropped = dropped + 1
    elseif void_seat(r) then voids = voids + 1 else kept[#kept + 1] = r end end
  print(('city_anchors.json: %d seat rows over a stairwell dropped'):format(voids))
  T.anchors = kept
  table.sort(T.anchors, function(a, b) return a.id < b.id end)
  if n > 0 or dropped > 0 or voids > 0 or back > 0 or moved > 0 then local out = okj.encode(T); f = assert(io.open(path, 'wb')); f:write(out); f:close() end
  print(('city_anchors.json: %d rows marked off now, %d rows of removed furniture dropped'):format(n, dropped))
end
do
  local rank = {}; for i, id in ipairs(UPSTAIRS_FIRST) do rank[id] = i end
  local rows = {}; for _, r in pairs(offrows) do rows[#rows + 1] = r end
  table.sort(rows, function(l, r) local a, b = rank[l.place] or 99, rank[r.place] or 99
    if a ~= b then return a < b end; if l.place ~= r.place then return l.place < r.place end; return (l.floor or 0) < (r.floor or 0) end)
  local md, total = { '# 樓上沒有樓梯的地點（導出器產生，勿手改）', '',
    '`Tools/export_street_city_game_places.lua` 產生，規則在 `Tools/street_city_upstairs_off.lua`（與 `Tools/build_street_city_places.lua` 共用，city_anchors.json 的同一批列一起標）：一樓有門、整個地點沒有任何 lift／stair 錨點時，門以上 2.5 m 的錨點改名為 `off_<原名>` 並加上 `"off"`，女主排程選不到它們（2026-11-15 止血）。補上樓梯錨點並實測「從 1F 走到該樓層座位再走回店門」之後，從這份清單拿掉。',
    '', '「真樓層」：錨點比門高 3 m 以上（一層 3.8 m，樓層由 room 或高度推得）；「高處物件」：比門高 2.5–3 m（不必補樓梯，標不可用即結案）。school 是校舍、經 campus_t1 的電梯上樓，不在此列。排序：排程與邀約常去的店在前。', '',
    '「規則錨點數」：city_anchors.json 裡同一地點同一樓層被標掉的列（清空 kinds、加 tag `off`），含員工間、廁所等只在規則表裡的錨點。', '',
    '## 現況（2026-11-16）', '',
    '11-15 止血時是 34 個地點、58 個樓層、233 個錨點。11-16 從來源地圖量出 S 排店面的折返樓梯（做在店殼網格裡），36 家補上 stairN（`Tools/street_city_shop_stairs.lua`，2dc5b8ee8，遊戲那邊是 c-conquest 的商店樓梯 C++ 76bbbbe65）：這 233 個錨點恢復可用，規則表 off 的 376 列還原 355 列（原 kinds 存在 `off_kinds`）。city1116a 遊戲內 36 家逐一驗過：站在 stair1 有「上樓到 2F」，按下後到 2F 樓梯口。', '',
    '下表是剩下的：這幾家沒有可用的樓梯，維持 off，不再追。', '',
    '| 地點 | 樓層 | 類別 | 錨點數 | 規則錨點數 | 錨點 | 為什麼還 off |', '|---|---:|---|---:|---:|---|---|' }, 0
  local WHY = {
    bike_shop = '只留 S35（原本併了相距 116 m、沒有門的 S81，11-16 拿掉，Tools/street_city_removed_anchors.lua）；S35 沒有量到樓梯，樓上只有規則表的高處物件',
    crepe = '只量到上半段樓梯，找不到 1F 的樓梯腳；樓上沒有座位',
    nail = '只量到上半段樓梯，找不到 1F 的樓梯腳',
    photo_studio = '樓上沒有量到任何樓梯；樓上沒有座位',
  }
  for _, r in ipairs(rows) do total = total + #r.names
    md[#md + 1] = ('| %s | %s | %s | %d | %d | %s | %s |'):format(r.place, r.floor and tostring(r.floor) or '-', r.real and '真樓層' or '高處物件', #r.names, r.rules, table.concat(r.names, ' '), WHY[r.place] or '沒有樓梯') end
  md[#md + 1] = ''; md[#md + 1] = ('共 %d 個地點樓層、%d 個錨點。'):format(#rows, total)
  local f = assert(io.open('Docs/STREET_CITY_UPSTAIRS_NO_STAIRS.md', 'wb')); f:write(table.concat(md, '\n') .. '\n'); f:close()
  print(('upstairs without stairs: %d place floors, %d anchors marked off'):format(#rows, total))
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
    if anchor.off then row = row .. ',"off":' .. quoted(anchor.off) end
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
-- The door goes through the gap in the corridor's east wall (x 77100-77150), open at y 34200-34350 on the scans (z 1290 and
-- 1220); the first corridor point keeps to the door's y 34275, the gap's middle. At y 34350 the line ran along the gap's
-- north edge and the walk from gym_hall hit the wall there (StaticMeshActor_372 at 77128,34310, nh1115m 11-15).
local PASSAGES = {
  { id = 's32', pts = { { 42760, 28520 }, { 43200, 28520 }, { 43800, 28520 }, { 44400, 28570 }, { 44800, 28570 }, { 44800, 28880 }, { 45160, 28880 } } },
  -- The restaurant's door (46810,24880) opens into a 2 m vestibule whose south wall ends at (46925,24750)
  -- (StaticMeshActor_9): the straight line from the door to the 'seat' anchor (47078,24670) cut that corner, he wedged
  -- there for 70 game minutes (c-conquest, nh1115y). A point past the vestibule (scans z 1270/1245: open y 24775-24975),
  -- not tied to the street, so the road graph's nearest point inside the restaurant is in it, not behind its walls.
  { id = 'restaurant_in', pts = { { 46810, 24880 }, { 47000, 24875 } }, tie = { true, false }, min_ties = 1 },
  -- The izakaya's north-east room (booths, counter stools): its doorway off the hall is 1 m (x 33890-33990 at y 26000,
  -- S52_F01's partition), then a 1.2 m corridor x 33820-33930 north to y 26290 and east into the room (10 cm scan 11-16).
  -- The grid route cut the doorway's west jamb, 24 replans before he got out (c-street-city, city1116a). Through the
  -- doorway's middle: from the shop's door (the hall has no road point; the street's are 8 m off, outside) along the
  -- line the editor's walk probe took across the hall, the far end untied (it is in the room).
  { id = 'izakaya_ne', pts = { { 33050, 25880 }, { 33400, 25900 }, { 33860, 25900 }, { 33940, 26000 }, { 33875, 26140 }, { 33875, 26290 }, { 34100, 26290 } }, tie = { true, false }, min_ties = 1 },
  { id = 'sp_gym', pts = { { 77174.7, 34274.6 }, { 77000, 34275 }, { 77000, 35400 }, { 77000, 36400 }, { 77000, 37400 }, { 77000, 38400 }, { 77000, 39500 } } },
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
  -- Inside, a counter (x 44280-44380, y 36480-36720) had its south edge on the old y 36480 line and stopped the walk
  -- (11-14); the line goes along y 36400 and turns north at x 44720. 11-15: the turn at x 44480 ran into low tables and
  -- chairs (x 44400-44660, y 36490-36710, StaticMeshActor_111 on nh1115b) that a scan at z 1290 does not see; x 44720 is
  -- clear at z 1290 and 1220 (70 cm from the furniture, 170 from the east wall).
  { id = 's38', pts = { { 42800, 36460 }, { 43300, 36460 }, { 44000, 36400 }, { 44720, 36400 }, { 44720, 36830 }, { 45000, 36830 }, { 45400, 36830 } } },
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
  -- campus_sports 1F corridor (x 76860-77080, floor 1200): the lattice ran along x 77000 but stopped at y 25200/25600 and
  -- 29200/29800 and turned back west, so lift1:1F (76760,21300) -> gym_hall went 323 m for 41 m (11-14). The floor scan
  -- (z 1290 and 1250, grid 20 cm) has the corridor clear from y 24400 to 31000; a middle point closes each gap.
  -- This lattice is indoors and only city_roads.json (the bake) has it, so here the ends find nothing to tie to; the
  -- roads add (street_city_roads_add.lua) matches them to the baked points by x,y.
  { id = 'sports_1f_a', min_ties = 0, pts = { { 77000, 25200 }, { 77000, 25400 }, { 77000, 25600 } } },
  { id = 'sports_1f_b', min_ties = 0, pts = { { 77000, 29200 }, { 77000, 29500 }, { 77000, 29800 } } },
  -- D3 1F WC (restroom_north, room 94400-95100 x 44410-44630): its door is the building entrance (93200,44100) and no road
  -- went in, so walks there went straight at the walls at x 93380 and 94170 and were stopped three times (11-14). The floor
  -- scan (z 1290, 20 cm) is clear up x 93200, along y 44720-44900 and into the room's open north side at x 94600.
  -- Infirmary (door 63840,53398 on the east face of the T1 block): the roads went south round the block, infirmary ->
  -- library 189 m for 77 m (11-14). The floor scan (z 1290, 40 cm) has a passage 1.6 m wide between walls at x 63880 and
  -- 64080 from y 53200 to 55360 (both cross walls open at x 63920-64080) and open ground north of it up to y 57800. Both
  -- ends are baked points (the door, 64100,57500), so no ties: one through the walls would land inside T1.
  { id = 'infirmary_north', tie = { false, false }, min_ties = 0, pts = { { 63840, 53399 }, { 63980, 53480 }, { 63980, 54200 }, { 63980, 55000 }, { 63980, 55600 }, { 64000, 56400 }, { 64000, 56900 }, { 64100, 57500 } } },
  { id = 'restroom_north_in', tie = { true, false }, pts = { { 93200, 44100 }, { 93200, 44400 }, { 93200, 44700 }, { 93200, 44800 }, { 93900, 44800 }, { 94600, 44800 }, { 94600, 44550 } } },
  -- campus_e1 to the pool: straight through the sports building's ground floor (x 77000-77200), open at z 1290 and 1220 with
  -- 40 cm clearance on a 50 cm grid of the box between the doors (11-15); the road went round by x 87100, 390 m for 194.
  -- The south end goes through the lobby wall's gap (x 76925-77025, y 21825) to the building's door: the game routes to
  -- the pool by campus_sports' door (77000,21000), and an end at the pool's own door left the corridor unused
  { id = 'e1_pool', pts = { { 78330, 41430 }, { 77180, 39480 }, { 77030, 39080 }, { 77030, 34300 }, { 77030, 29830 }, { 76980, 29780 }, { 76980, 25400 }, { 76980, 22130 }, { 76980, 21750 } } },
  -- r1114 (11-14, Tools/street_city_passage_batch.lua): walls cut through S59, S69 and S84, the paths the walk probe took
  { id = 'r1114_a1', pts = { { 32700, 34760 }, { 33260, 34760 }, { 33820, 34760 }, { 34140, 34880 }, { 34620, 34720 }, { 35160, 34740 }, { 35700, 34760 } } },
  -- A2 east of 33820: up x 33980 and out along y 47360 (11-15). The probe's path went on through a room closed to the
  -- north (wall y 47150) and out by a 40 cm gap at the stub of the east wall (x 35080, y < 47100, below the cut's 47080):
  -- the walk on nh1115b hit StaticMeshActor_204 there. Checked on the cut map's scans at z 1290 and 1220 (a2-after-*).
  { id = 'r1114_a2', pts = { { 32700, 47300 }, { 33180, 46980 }, { 33820, 46940 }, { 33980, 47000 }, { 33980, 47360 }, { 34800, 47360 }, { 35400, 47360 }, { 35700, 47300 } } },
  { id = 'r1114_c', pts = { { 29200, 36520 }, { 29840, 36520 }, { 30480, 36520 }, { 30960, 36640 }, { 31440, 36640 }, { 31600, 36520 } } },
}
-- OK_EXTRA_PASSAGES=<json list of {id, pts}>: passages a batch run has just cut (Tools/street_city_passage_batch.lua picks
-- the line in each shop and writes them); once the run is checked they are copied into the list above.
if os.getenv('OK_EXTRA_PASSAGES') then
  for _, p in ipairs(json.decode(read(os.getenv('OK_EXTRA_PASSAGES')))) do PASSAGES[#PASSAGES + 1] = p end
end
local PASSAGE_TIE_CM, PASSAGE_TIES = 800, 3
for _, pass in ipairs(PASSAGES) do
  local ids = {}
  for n, p in ipairs(pass.pts) do
    nodes[#nodes + 1] = { k = (p[1] - ox) / step + 1, i = (p[2] - oy) / step + 1, links = {} }
    ids[n] = #nodes
    if n > 1 then local a, b = ids[n - 1], ids[n]; nodes[a].links[#nodes[a].links + 1] = b; nodes[b].links[#nodes[b].links + 1] = a end
  end
  local tied = 0
  -- pass.tie = { first, last }: false leaves that end untied (an end inside a room would tie through its walls to the
  -- street outside); pass.min_ties: fewer ties expected, e.g. a corridor whose lattice the baked graph has but this one not
  for side, e in ipairs({ ids[1], ids[#ids] }) do
    local near = {}
    if pass.tie and pass.tie[side] == false then goto untied end
    for _, y in ipairs(biggest) do
      local d = math.sqrt((nodes[e].k - nodes[y].k) ^ 2 + (nodes[e].i - nodes[y].i) ^ 2) * step
      if d <= PASSAGE_TIE_CM then near[#near + 1] = { d = d, y = y } end
    end
    table.sort(near, function(l, r) return l.d < r.d end)
    for n = 1, math.min(#near, PASSAGE_TIES) do
      local y = near[n].y; nodes[e].links[#nodes[e].links + 1] = y; nodes[y].links[#nodes[y].links + 1] = e; tied = tied + 1
    end
    ::untied::
  end
  for _, x in ipairs(ids) do biggest[#biggest + 1] = x end
  if tied < (pass.min_ties or 2) then problem('passage ' .. pass.id .. ': ' .. tied .. ' ties to the roads') end
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
