-- Offline furniture check, no Unreal: run before a street-city install round, fails on what would cost a round.
--   Tools\lua\lua.exe Tools\check_street_city_placement.lua [--all]
-- Reads places-v1/actors.json (bounds of every actor), places-v1/props.json (rooms, doors) and city_anchors.json.
--   overlap  two placed pieces sink into each other by more than 12 cm
--   door     a placed piece stands within 45 cm of a room door
--   room     a piece's centre is outside the room its name says
--   tv       a TV anchor has no sofa in the same place, or a piece stands on the line between them
-- Pieces of one recipe (same label up to the last _) count as one object; when a recipe has a _Tripo model the boxes
-- behind it are hidden, so only the model counts. Small dressing (fish, plants in tanks, signs) is skipped.
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local base = 'output/street-social-city-production/places-v1/'
local function read(p) local f = assert(io.open(p, 'rb')); local s = f:read('*a'); f:close(); return j.decode((s:gsub('^\239\187\191', ''))) end
local all = arg[1] == '--all'
local SKIP = { 'LoverSpot_R5_', 'LoverSpot_R6_', 'LoverSpot_R9_zoo_pen', 'LoverSpot_R9_waterpark', 'Rail', '_Cloth', 'Reflection', 'balcony', 'Balcony', '_Fish', '_Weed', '_Rock', '_Sand', '_Water', '_Sign', '_Glow', '_Light', '_Screen', '_Rug', '_Mat', 'Aqua_' }
local function skip(l) for _, s in ipairs(SKIP) do if l:find(s, 1, true) then return true end end end
local groups, tripo = {}, {}
local actors = read(base .. 'actors.json')
for _, a in ipairs(actors.actors or actors) do
  if a.label and a.label:find('^LoverSpot') and a.c and a.e and not skip(a.label) and a.e[1] < 1500 and a.e[2] < 1500 then
    local g = a.label:match('^(.*)_[^_]*$') or a.label
    groups[g] = groups[g] or {}; table.insert(groups[g], a)
    if a.label:find('_Tripo$') then tripo[g] = a end
  end
end
local boxes = {}
for g, list in pairs(groups) do
  local use = tripo[g] and { tripo[g] } or list
  for _, a in ipairs(use) do boxes[#boxes + 1] = { g = g, l = a.label, c = a.c, e = a.e } end
end
assert(#boxes > 1000, 'too few placed pieces in actors.json: ' .. #boxes)
table.sort(boxes, function(x, y) return x.l < y.l end)
local CELL, grid = 400, {}
local function key(x, y) return math.floor(x / CELL) * 100000 + math.floor(y / CELL) end
for i, b in ipairs(boxes) do
  for x = b.c[1] - b.e[1], b.c[1] + b.e[1] + CELL, CELL do for y = b.c[2] - b.e[2], b.c[2] + b.e[2] + CELL, CELL do
    local k = key(x, y); grid[k] = grid[k] or {}; grid[k][i] = true end end
end
local bad = { overlap = {}, door = {}, room = {}, tv = {} }
local seen = {}
for _, cell in pairs(grid) do
  local ids = {}; for i in pairs(cell) do ids[#ids + 1] = i end
  for p = 1, #ids do for q = p + 1, #ids do
    local a, b = boxes[ids[p]], boxes[ids[q]]
    local pk = math.min(ids[p], ids[q]) .. ':' .. math.max(ids[p], ids[q])
    if a.g ~= b.g and not seen[pk] then seen[pk] = true
      local dx = a.e[1] + b.e[1] - math.abs(a.c[1] - b.c[1])
      local dy = a.e[2] + b.e[2] - math.abs(a.c[2] - b.c[2])
      local dz = a.e[3] + b.e[3] - math.abs(a.c[3] - b.c[3])
      if dx > 12 and dy > 12 and dz > 12 then table.insert(bad.overlap, string.format('%s x %s (%.0f %.0f cm)', a.l, b.l, dx, dy)) end
    end
  end end
end
local areas = read(base .. 'props.json').areas
local byid = {}
for _, r in ipairs(areas) do byid[r.id] = r
  local d = r.door
  if d and r.kind ~= 'building' then
    local k = {}
    for x = -1, 1 do for y = -1, 1 do local c = grid[key(d[1] + x * CELL, d[2] + y * CELL)]; if c then for i in pairs(c) do k[i] = true end end end end
    for i in pairs(k) do local b = boxes[i]
      local gx = math.abs(b.c[1] - d[1]) - b.e[1]; local gy = math.abs(b.c[2] - d[2]) - b.e[2]
      if gx < 45 and gy < 45 and math.abs(b.c[3] - b.e[3] - d[3]) < 150 then bad.door[#bad.door + 1] = b.l .. ' at door of ' .. r.id end
    end
  end
end
for _, b in ipairs(boxes) do
  local rid = b.l:match('_([a-z]%w*%-%d%d%d%d)')
  local r = rid and byid[rid]
  if r and r.min and r.max and (b.c[1] < r.min[1] or b.c[1] > r.max[1] or b.c[2] < r.min[2] or b.c[2] > r.max[2]) then bad.room[#bad.room + 1] = b.l .. ' outside ' .. rid end
end
local anchors = read('Content/IndependentResources/StreetSocialData/city_anchors.json').anchors
local byplace = {}
for _, a in ipairs(anchors) do byplace[a.place] = byplace[a.place] or {}; byplace[a.place][a.name] = a end
for place, t in pairs(byplace) do
  if t.tv and place:find('-', 1, true) then local s = t.tv_sofa or t.sofa0_0
    if not s then bad.tv[#bad.tv + 1] = place .. ': tv without sofa'
    else
      local ax, ay, bx, by = t.tv.pos[1], t.tv.pos[2], s.pos[1], s.pos[2]
      for _, b in ipairs(boxes) do
        if b.l:find(place, 1, true) and not b.l:find('tv', 1, true) and not b.l:find('sofa', 1, true) and not b.l:find('_TV', 1, true) and not b.l:find('Sofa', 1, true) then
          for u = 0.2, 0.8, 0.1 do local x, y = ax + (bx - ax) * u, ay + (by - ay) * u
            if math.abs(x - b.c[1]) < b.e[1] and math.abs(y - b.c[2]) < b.e[2] and b.c[3] + b.e[3] - t.tv.pos[3] > 90 then bad.tv[#bad.tv + 1] = place .. ': ' .. b.l .. ' blocks the tv'; break end end
        end
      end
    end
  end
end
bad.stand = {}
for _, a in ipairs(anchors) do
  if a.name == 'kitchen' or a.name == 'stove' then
    for _, b in ipairs(boxes) do
      if math.abs(a.pos[1] - b.c[1]) < b.e[1] + 15 and math.abs(a.pos[2] - b.c[2]) < b.e[2] + 15 and math.abs(b.c[3] - a.pos[3] - 90) < b.e[3] + 90 and not b.l:find('kitchen', 1, true) then
        bad.stand[#bad.stand + 1] = a.id .. ' stands in ' .. b.l end
    end
  end
end
local n = 0
for _, kind in ipairs({ 'overlap', 'door', 'room', 'tv', 'stand' }) do
  table.sort(bad[kind]); n = n + #bad[kind]
  print(kind, #bad[kind])
  for i = 1, all and #bad[kind] or math.min(#bad[kind], 12) do print('  ' .. bad[kind][i]) end
end
print(string.format('pieces %d, problems %d', #boxes, n))
os.exit(n == 0 and 0 or 1)
