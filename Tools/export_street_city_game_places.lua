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
    else r[#r + 1] = '{"min":' .. vec(room.min) .. ',"max":' .. vec(room.max) .. ',"floor":' .. num(room.floor or 1) .. '}'; rooms = rooms + 1 end
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
local BRIDGE_CELLS, BRIDGE_MIN_POINTS = 5, 20
for p = 2, #parts do
  local part = parts[p]
  if #part >= BRIDGE_MIN_POINTS then
    local near, a, b = (BRIDGE_CELLS + 1) ^ 2
    for _, x in ipairs(part) do
      for _, y in ipairs(biggest) do
        local d = (nodes[x].k - nodes[y].k) ^ 2 + (nodes[x].i - nodes[y].i) ^ 2
        if d < near then near, a, b = d, x, y end
      end
    end
    if a then
      nodes[a].links[#nodes[a].links + 1] = b; nodes[b].links[#nodes[b].links + 1] = a
      for _, x in ipairs(part) do biggest[#biggest + 1] = x end
      print(('road graph: tied a part of %d points on at %.0f,%.0f'):format(#part, ox + (nodes[a].k - 1) * step, oy + (nodes[a].i - 1) * step))
    end
  end
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
