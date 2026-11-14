-- Ties every building's extra ways in (city_places.json anchors named entrance*) into the baked road graph (city_roads.json).
--   Tools\lua\lua.exe Tools\street_city_entrances_tie.lua [--dry]
-- The game goes into and out of a building by its door or one of these (CityRoute picks the nearest), and walks there on
-- city_roads.json, so each must be a road point like a door. A full road bake (-CityBakeRoads) does not know them: run this
-- after one. An entrance with a road point within 50 cm is left as it is; else a point is appended at it, linked to the
-- nearest linked road point on its floor (height within 200 cm) within 8 m. The entrances were picked where the floor scans
-- (z 1290 and 1220) have a clear straight line from that road point into the doorway (11-15), so the link needs no sweep.
-- Rerun safe.
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local DIR = 'Content/IndependentResources/StreetSocialData/'
local dry = arg[1] == '--dry'
local function read(p) local f = assert(io.open(p, 'rb')); local s = f:read('a'); f:close(); return j.decode(s) end
local places = read(DIR .. 'city_places.json').places
local roads = read(DIR .. 'city_roads.json')
local deg = {}
for _, l in ipairs(roads.links) do deg[l[1]] = (deg[l[1]] or 0) + 1; deg[l[2]] = (deg[l[2]] or 0) + 1 end
local function d2(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
-- where the nearest road point has a wall between (floor scans, 11-15): the road point to link to instead, by x,y
local VIA = { ['campus_ee entrance'] = { 79700, 62900 }, ['campus_ad entrance2'] = { 67300, 74500 } }
local added, kept, failed = 0, 0, 0
for _, p in ipairs(places) do
  for _, a in ipairs(p.anchors or {}) do
    if a.name:match('^entrance') then
      local at, near, nd
      for n, q in ipairs(roads.nodes) do
        if math.abs(q[3] - a.pos[3]) < 200 then
          local d = d2(q, a.pos)
          if d <= 50 and (deg[n - 1] or 0) > 0 then at = n - 1 end
          local via = VIA[p.id .. ' ' .. a.name]
          if via and (deg[n - 1] or 0) > 0 and d2(q, via) < 50 then near, nd = n - 1, d
          elseif not via and (deg[n - 1] or 0) > 0 and d <= 800 and (not nd or d < nd) then near, nd = n - 1, d end
        end
      end
      if at then kept = kept + 1
      elseif not near then failed = failed + 1; print(('problem: %s %s at %.0f,%.0f has no road point within 8 m'):format(p.id, a.name, a.pos[1], a.pos[2]))
      else
        local q = roads.nodes[near + 1]
        roads.nodes[#roads.nodes + 1] = { a.pos[1], a.pos[2], q[3] }
        local id = #roads.nodes - 1
        roads.links[#roads.links + 1] = { near, id }; deg[near] = deg[near] + 1; deg[id] = 1
        added = added + 1
        print(('%s %s: point %d at %.0f,%.0f linked to %d (%.1f m)'):format(p.id, a.name, id, a.pos[1], a.pos[2], near, nd / 100))
      end
    end
  end
end
print(('entrances: %d on the roads already, %d tied, %d without a road point near'):format(kept, added, failed))
-- Floors above the street with no road of their own: a line of points from the lift to a place's door, each leg clear on
-- that floor's scans (two heights, 40 cm clearance). Without it the game's graph route between two spots of one floor went
-- down to the street (10 of 12 points off the floor) and fell back to a straight line into the wall.
--   civic 2F, lift2:2F to the bank (door: its counter): the straight line from the bank hit the south wall's corner
--   (StaticMeshActor_496 at 31904,58773, nh1115k 11-15); the scans (z 1710 and 1640) have the way out of the bank's open
--   south side and through the gap at x 31100-31850 in the corridor's south wall, 35 m for 32; the last leg goes east of the counter's low panel (x 32800-32850 at z 1640).
local FLOOR_PATHS = {
  { id = 'civic_2f_bank', z = 1620, pts = { { 31260, 56500 }, { 31380, 56630 }, { 31780, 58780 }, { 31880, 58880 }, { 32930, 59250 }, { 32860, 59393 } } },
}
for _, path in ipairs(FLOOR_PATHS) do
  local prev, new = nil, 0
  for _, q in ipairs(path.pts) do
    local id
    for n, r in ipairs(roads.nodes) do if d2(r, q) <= 50 and math.abs(r[3] - path.z) < 100 then id = n - 1; break end end
    if not id then roads.nodes[#roads.nodes + 1] = { q[1], q[2], path.z }; id = #roads.nodes - 1; new = new + 1 end
    if prev and prev ~= id then
      local have = false
      for _, l in ipairs(roads.links) do if (l[1] == prev and l[2] == id) or (l[1] == id and l[2] == prev) then have = true; break end end
      if not have then roads.links[#roads.links + 1] = { prev, id }; added = added + 1 end
    end
    prev = id
  end
  print(('floor path %s: %d points, %d new'):format(path.id, #path.pts, new))
end
if dry or added == 0 then if dry then print('--dry: not written') end; os.exit(failed == 0 and 0 or 1) end
local rows, lrows = {}, {}
for n, p in ipairs(roads.nodes) do rows[n] = ('[%.1f,%.1f,%.1f]'):format(p[1], p[2], p[3]) end
for n, l in ipairs(roads.links) do lrows[n] = ('[%d,%d]'):format(l[1], l[2]) end
local f = assert(io.open(DIR .. 'city_roads.json', 'wb'))
f:write('{"nodes":[', table.concat(rows, ','), '],"links":[', table.concat(lrows, ','), ']}\n'); f:close()
print('written ' .. DIR .. 'city_roads.json')
os.exit(failed == 0 and 0 or 1)
