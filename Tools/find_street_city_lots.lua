-- Empty roadside lots for the company game (c-conquest C9, property.json lot_*): 14 x 11 m grass blocks in the 2 m road
-- raster (world-edge-v1/road-raster.json) whose 2 m margin is grass too and whose front edge touches a road. The front
-- is the road side; `yaw` is the direction from the lot centre to the road (UE yaw, +X north). Nearest to a place door
-- first; candidates keep 40 m apart and 15 m from every place door. The editor job (street_city_lover_spots_payload.lua section 9) keeps the first
-- eight that are flat and empty in the map and writes them as lot_1..lot_8.
-- Output: world-edge-v1/lot-candidates.json.  Usage: Tools\lua\lua.exe Tools\find_street_city_lots.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json'); local dir = 'output/street-social-city-production/'
local function load(p) local f = assert(io.open(dir .. p, 'rb'), p); local d = j.decode(f:read('a')); f:close(); return d end
local R = load('world-edge-v1/road-raster.json')
local S, ox, oy, rows = R.step_cm, R.origin[1], R.origin[2], R.rows
local NY, NX = #rows, #rows[1]
local function at(k, i) if i < 1 or i > NY or k < 1 or k > NX then return nil end return rows[i]:sub(k, k) end
local doors = {}
for _, p in ipairs(load('places-v1/places.json').places) do if p.door then doors[#doors + 1] = p.door end end
local L, D = 7, 6 -- cells along the road (14 m) and deep (12 m, 11 m usable)
local function grass(k0, i0, k1, i1) for i = i0, i1 do for k = k0, k1 do if at(k, i) ~= 'g' then return false end end end return true end
local function road(k0, i0, k1, i1) local n = 0; for i = i0, i1 do for k = k0, k1 do if at(k, i) == 'r' then n = n + 1 end end end return n end
local cand = {}
for i = 1, NY do for k = 1, NX do
  -- both orientations: wide along x (cells k) or along y (cells i)
  for _, o in ipairs({ { L, D }, { D, L } }) do
    local w, h = o[1], o[2]
    if grass(k - 1, i - 1, k + w, i + h) then
      -- road within 2 cells of one edge, on most of that edge
      local sides = { { 0, -1, road(k, i - 3, k + w - 1, i - 2), w }, { 0, 1, road(k, i + h + 1, k + w - 1, i + h + 2), w },
        { -1, 0, road(k - 3, i, k - 2, i + h - 1), h }, { 1, 0, road(k + w + 1, i, k + w + 2, i + h - 1), h } }
      for _, s in ipairs(sides) do
        if s[3] >= s[4] then
          local cx, cy = ox + (k - 1 + (w - 1) / 2) * S, oy + (i - 1 + (h - 1) / 2) * S
          cand[#cand + 1] = { x = cx, y = cy, sx = w * S, sy = h * S, yaw = math.floor(math.deg(math.atan(s[2], s[1])) + .5) % 360, score = s[3] }
          break
        end
      end
    end
  end
end end
-- nearest first to the places people go (a lot by the shops, not at the city edge)
for _, c in ipairs(cand) do local m = math.huge; for _, d in ipairs(doors) do m = math.min(m, (d[1] - c.x) ^ 2 + (d[2] - c.y) ^ 2) end; c.near = m end
table.sort(cand, function(a, b) if a.near ~= b.near then return a.near < b.near end; return a.x < b.x end)
local keep = {}
for _, c in ipairs(cand) do
  local ok = true
  for _, o in ipairs(keep) do if (o.x - c.x) ^ 2 + (o.y - c.y) ^ 2 < 4000 ^ 2 then ok = false; break end end
  if ok then for _, d in ipairs(doors) do if (d[1] - c.x) ^ 2 + (d[2] - c.y) ^ 2 < 1500 ^ 2 then ok = false; break end end end
  if ok then keep[#keep + 1] = c end
  if #keep >= 40 then break end
end
-- raster cells are x by column, y by row; the lot frame: size = {along x, along y} in cm, yaw toward the road
local out = {}
for n, c in ipairs(keep) do out[n] = { center = { c.x, c.y }, size = { c.sx, c.sy }, yaw = c.yaw } end
local f = assert(io.open(dir .. 'world-edge-v1/lot-candidates.json', 'wb'))
f:write(j.encode({ raster_map_sha256 = R.map_sha256, candidates = out })); f:close()
print('lot candidates', #out, 'of', #cand)
