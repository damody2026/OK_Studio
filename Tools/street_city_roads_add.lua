-- Adds road points of city_places.json that the baked graph (city_roads.json) has not got yet, inside a box, with their links.
--   Tools\lua\lua.exe Tools\street_city_roads_add.lua [--box x0,y0,x1,y1] [--dry]
-- The streamed map (UniversityCityWP) cannot sweep its links at start, so it reads city_roads.json, which only a run on the
-- source map makes (-CityBakeRoads, then Tools/street_city_road_bake_payload.lua). A passage opened since then
-- (export_street_city_game_places.lua PASSAGES, e.g. S32 on 11-13) is in city_places.json alone and the streamed map's
-- walks went round it. Points are matched by x,y (the bake keeps them and only sets their height): a city_places point in
-- the box with no baked point at its x,y is appended, every city_places link of it to a baked or appended point is added.
-- Height: the mean of the baked points it is tied to, carried along the chain. Default box: the S32 passage.
-- Rerun safe (points already there are matched). The next full bake makes the same points itself.
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local DIR = 'Content/IndependentResources/StreetSocialData/'
local box = { 42600, 28300, 45300, 29000 }
local dry = false
local i = 1
while arg[i] do
  if arg[i] == '--box' then
    box = {}; for v in arg[i + 1]:gmatch('[^,]+') do box[#box + 1] = assert(tonumber(v), '--box x0,y0,x1,y1') end
    assert(#box == 4, '--box x0,y0,x1,y1'); i = i + 2
  elseif arg[i] == '--dry' then dry = true; i = i + 1
  else error('unknown argument ' .. arg[i], 0) end
end
local function read(p) local f = assert(io.open(p, 'rb')); local s = f:read('a'); f:close(); return j.decode(s) end
local places = read(DIR .. 'city_places.json').road
local roads = read(DIR .. 'city_roads.json')
local function key(n) return math.floor(n[1] + .5) .. ',' .. math.floor(n[2] + .5) end
local at = {}
for n, p in ipairs(roads.nodes) do at[key(p)] = n end
local function inside(p) return p[1] >= box[1] and p[1] <= box[3] and p[2] >= box[2] and p[2] <= box[4] end
-- city_places links by point (1-based)
local adj = {}
for _, l in ipairs(places.links) do
  local a, b = l[1] + 1, l[2] + 1
  adj[a] = adj[a] or {}; adj[b] = adj[b] or {}
  adj[a][#adj[a] + 1] = b; adj[b][#adj[b] + 1] = a
end
local new, map = {}, {}
for n, p in ipairs(places.nodes) do
  if at[key(p)] then map[n] = at[key(p)]
  elseif inside(p) then new[#new + 1] = n end
end
if #new == 0 then print('nothing to add: every city_places point in the box is in city_roads.json'); return end
-- heights: from the baked neighbours, then along the chain until every new point has one
local z = {}
for _ = 1, #new do
  local changed = false
  for _, n in ipairs(new) do
    if not z[n] then
      local sum, cnt = 0, 0
      for _, m in ipairs(adj[n] or {}) do
        if map[m] then sum = sum + roads.nodes[map[m]][3]; cnt = cnt + 1 elseif z[m] then sum = sum + z[m]; cnt = cnt + 1 end
      end
      if cnt > 0 then z[n] = sum / cnt; changed = true end
    end
  end
  if not changed then break end
end
local added, links, ties = 0, 0, 0
for _, n in ipairs(new) do
  if not z[n] then error(('point %s,%s has no link to a baked point'):format(places.nodes[n][1], places.nodes[n][2]), 0) end
  local p = places.nodes[n]
  roads.nodes[#roads.nodes + 1] = { p[1], p[2], z[n] }; map[n] = #roads.nodes; added = added + 1
end
local isnew = {}
for _, n in ipairs(new) do isnew[n] = true end
for _, n in ipairs(new) do
  for _, m in ipairs(adj[n] or {}) do
    if map[m] and (not isnew[m] or m > n) then
      roads.links[#roads.links + 1] = { map[n] - 1, map[m] - 1 }; links = links + 1
      if not isnew[m] then ties = ties + 1 end
    end
  end
end
print(('box %s: %d points added (%d..%d), %d links, %d of them to baked points'):format(table.concat(box, ','), added,
  #roads.nodes - added, #roads.nodes - 1, links, ties))
for _, n in ipairs(new) do local p = places.nodes[n]; print(('  %d,%d  z %.1f'):format(p[1], p[2], z[n])) end
if ties < 2 then error('fewer than two ties to the baked roads: not written', 0) end
if dry then print('--dry: not written'); return end
-- same layout as the bake writes (street_city_road_bake_payload.lua)
local rows, lrows = {}, {}
for n, p in ipairs(roads.nodes) do rows[n] = ('[%.1f,%.1f,%.1f]'):format(p[1], p[2], p[3]) end
for n, l in ipairs(roads.links) do lrows[n] = ('[%d,%d]'):format(l[1], l[2]) end
local f = assert(io.open(DIR .. 'city_roads.json', 'wb'))
f:write('{"nodes":[', table.concat(rows, ','), '],"links":[', table.concat(lrows, ','), ']}\n'); f:close()
print('written ' .. DIR .. 'city_roads.json')
