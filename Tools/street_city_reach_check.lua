-- City-wide reachability check of the places and their anchors, by the game's own walk-grid cell test (NavCellFree, see
-- Tools/street_city_reach_survey_payload.lua) on the source map. One check after crib3, the civic seats and bike_shop
-- were found one at a time (11-16): every place's door reached from the street, every anchor reached from its door.
--   Tools\lua\lua.exe Tools\street_city_reach_check.lua plan            tiles to scan -> places-v1/reach-tiles.json
--   Tools\lua\lua.exe Tools\street_city_reach_check.lua scan [--minutes M] [--batch N]
--       claims an Unreal slot, starts the native editor worker, scans the tiles not scanned yet in batches, stops after M
--       minutes (default 17: a test segment holds the machine at most 20) and releases; run again to go on
--   Tools\lua\lua.exe Tools\street_city_reach_check.lua report          the list, grouped by kind of problem:
--       Docs/STREET_CITY_REACH.md and places-v1/reach-report.json; exit 1 when there are problems
--   ... report --diff   also prints what is new and what is gone against the committed report (git HEAD)
--   Tools\lua\lua.exe Tools\street_city_reach_check.lua probe <z> <x1> <y1> <x2> <y2>
--       whether two points of floor z are joined, and the scanned cells round the first with their blockers
-- The editor reads the source map (StreetSocialCity/.../UniversityCity.umap); the game reads the World Partition copy made
-- from it (Tools/build_street_city_stream.lua + Tools/migrate_street_city_content.lua). Only the game says a way is open:
-- this list is where to look, a fix is checked in a stage (Docs/STREET_ERRORS.md 11-16).
-- After a map change, delete places-v1/reach-grid/ and scan again (the scan keeps what it has).
package.path = 'Tools/lua/?.lua;' .. package.path
local ok = require('ok'); local j = require('ok.json'); local lfs = require('lfs')
local L = ok.lua_exe
local PLACES = 'output/street-social-city-production/places-v1/'
local MOTEL = 'output/street-social-city-production/motel-v1/'
local DATA = 'Content/IndependentResources/StreetSocialData/'
local CELL, TILE = 40, 40 -- cm per cell (the game's OKStreetNavCell), cells per tile side (16 m)
local GOAL_RINGS = 6     -- a goal on furniture: the game takes the nearest free cell within 6 rings (GridSearchStep)
local NEAR_RINGS = 4     -- the game's replacement spots reach 140 cm round an anchor in furniture: 4 cells (160 cm)
local STEP = 40         -- the most a walk steps up or down between cells (GridSearchStep)
local OPEN_CELLS = 150   -- outdoors: a region of at least this many cells (24 m2), or one running off the scan, is open

local K = {
  door_blocked = '門被擋：門口 2.4 m 內沒有可走格',
  no_entry = '樓層沒有入口：這層沒有門、電梯平台或樓梯錨點',
  door_street = '門到不了街上：門口那一片走不出地點的房間',
  unscanned = '沒掃到：錨點不在掃描範圍',
  no_floor = '錨點下沒有地板：高度不對或懸空',
  no_cell = '錨點周圍 2.4 m 沒有可走格',
  sealed = '錨點在封死的格子：附近可走，但連不到門或電梯／樓梯',
  in_furniture = '站位在家具或牆裡：遊戲會改用 1.6 m 內走得到的點（不擋路，只是站位不準）',
  in_sight = '其中站在顯眼位置的（櫃台、收銀、沙發、吧台、接待）：之後優先挪',
}
-- kinds where she is watched standing (the shop's till, the counter, a sofa): their in-furniture rows are listed one by one
local SHOWN = { checkout = true, queue = true, counter = true, cashier = true, reception = true, tv_sofa = true,
  h_sofa = true, sofa = true, bar = true, counter_seat = true, order = true, ticket = true, register = true }

-- Anchors not walked to on foot, by place and name pattern: why
local EXEMPT = {
  pool = { ['^swim%d*$'] = 'in the water (h_pool)' },
}
local function exempt(place, name)
  for pat, why in pairs(EXEMPT[place] or {}) do if name:match(pat) then return why end end
end

local function read(p) local f = io.open(p, 'rb'); if not f then return nil end; local s = f:read('a'); f:close(); return s end
local function write(p, s) local f = assert(io.open(p, 'wb')); f:write(s); f:close() end
local function lua(args) local cmd = { L }; for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local r = ok.proc.run(cmd, { capture = true, merge = true }); return r.code, r.stdout or '' end
local function round(v) return math.floor(v + 0.5) end
local function cellof(v) return round(v / CELL) end
local function tileof(i) return i // TILE end

-- The places and the points to check in each: the door, the rules table's rows (those on, with kinds; rows marked off are
-- not used by the game) and the place's anchors not in the rules table. Each place's points are put on floors: z values
-- within 60 cm are one floor, keyed by the lowest rounded to 10 cm.
local function load_points()
  local P = j.decode(assert(read(DATA .. 'city_places.json'))).places
  local A = j.decode(assert(read(DATA .. 'city_anchors.json'))).anchors
  local rows = {}
  for _, r in ipairs(A) do if r.kinds and #r.kinds > 0 and r.pos then rows[r.place] = rows[r.place] or {}; table.insert(rows[r.place], r) end end
  local out = {}
  for _, p in ipairs(P) do
    local pts, seen = {}, {}
    pts[#pts + 1] = { name = 'door', pos = p.door, door = true }
    for _, r in ipairs(rows[p.id] or {}) do seen[r.name] = true; pts[#pts + 1] = { name = r.name, pos = r.pos, kinds = r.kinds } end
    for _, a in ipairs(p.anchors or {}) do if not seen[a.name] then pts[#pts + 1] = { name = a.name, pos = a.pos, place_only = true } end end
    -- Floors: the door's and the lift landings' and stairs' heights (a lecture room's tiers, a stage, sit up to 1.5 m over
    -- them: the cell test finds that ground from the floor's height). Points over none of them make floors of their own.
    local function z10(z) return round(z / 10) * 10 end
    local entry = { z10(p.door[3]) }
    for _, q in ipairs(pts) do if q.name:match('^lift') or q.name:match('^stair') then entry[#entry + 1] = z10(q.pos[3]) end end
    table.sort(entry); local floors = {}
    for _, z in ipairs(entry) do if #floors == 0 or z - floors[#floors] > 60 then floors[#floors + 1] = z end end
    local function entryof(z) local best; for _, f in ipairs(floors) do if z >= f - 30 and z < f + 150 then best = f end end; return best end
    local rest = {}
    for _, q in ipairs(pts) do if not entryof(z10(q.pos[3])) then rest[#rest + 1] = z10(q.pos[3]) end end
    table.sort(rest); local extra = {}
    for _, z in ipairs(rest) do if #extra == 0 or z - extra[#extra] > 60 then extra[#extra + 1] = z end end
    for _, z in ipairs(extra) do floors[#floors + 1] = z end
    table.sort(floors)
    local function floorof(z) local e = entryof(z); if e then return e end
      local best = extra[1]; for _, f in ipairs(extra) do if z >= f - 30 then best = f end end; return best end
    for _, q in ipairs(pts) do q.z = floorof(z10(q.pos[3])); q.ix, q.iy = cellof(q.pos[1]), cellof(q.pos[2]) end
    out[#out + 1] = { id = p.id, outdoor = p.outdoor, door = p.door, rooms = p.rooms or {}, floors = floors, points = pts }
  end
  return out
end

local function plan()
  local places = load_points()
  local tiles, n = {}, 0
  local function add(tx, ty, z) local key = ('%d_%d_%d'):format(tx, ty, z)
    if not tiles[key] then tiles[key] = { key = key, ix0 = tx * TILE, iy0 = ty * TILE, z = z }; n = n + 1 end end
  local function cover(x0, y0, x1, y1, z)
    for tx = tileof(cellof(x0)), tileof(cellof(x1)) do for ty = tileof(cellof(y0)), tileof(cellof(y1)) do add(tx, ty, z) end end end
  for _, p in ipairs(places) do
    for _, q in ipairs(p.points) do add(tileof(q.ix), tileof(q.iy), q.z) end
    local dz = p.points[1].z; cover(p.door[1] - 400, p.door[2] - 400, p.door[1] + 400, p.door[2] + 400, dz)
    if not p.outdoor then
      for _, f in ipairs(p.floors) do for _, r in ipairs(p.rooms) do
        if r.min and r.min[3] <= f + 60 and r.max[3] >= f then cover(r.min[1], r.min[2], r.max[1], r.max[2], f) end end end
    end
  end
  local list = {}; for _, t in pairs(tiles) do list[#list + 1] = t end
  table.sort(list, function(a, b) return a.key < b.key end)
  write(PLACES .. 'reach-tiles.json', j.encode({ cells = TILE, tiles = list }))
  print(('%d places, %d tiles of %d m (%d cells)'):format(#places, n, TILE * CELL // 100, n * TILE * TILE))
end

-- the tiles already scanned (any batch file holding them)
local function scanned()
  local have = {}
  local d = PLACES .. 'reach-grid'
  if lfs.attributes(d) then for n in lfs.dir(d) do if n:match('%.json$') then
    local g = j.decode(read(d .. '/' .. n))
    for key, rows in pairs(g.tiles) do have[key] = { rows = rows, legend = g.legend } end end end end
  return have
end

local function scan(minutes, batch)
  local cfg = j.decode(assert(read(PLACES .. 'reach-tiles.json'), 'run plan first'))
  local have = scanned(); local todo = {}
  for i, t in ipairs(cfg.tiles) do if not have[t.key] then todo[#todo + 1] = i end end
  print(('%d tiles, %d left'):format(#cfg.tiles, #todo)); if #todo == 0 then return end
  -- the left tiles as runs of consecutive indexes, cut to the batch size
  local runs, i = {}, 1
  while i <= #todo do local a = todo[i]; local b = a
    while i < #todo and todo[i + 1] == b + 1 and b - a + 1 < batch do i = i + 1; b = todo[i] end
    runs[#runs + 1] = { a, b }; i = i + 1 end
  local held, serving = false, false
  local function finish()
    if serving then lua({ 'Tools/street_city_motel_job.lua', 'quit', 'Tools/street_city_walk_probe_payload.lua' }); ok.time.sleep(40) end
    if held then lua({ 'Tools/unreal_slot.lua', 'release', 'c-street-city' }) end
  end
  local done, err = xpcall(function()
    local code, out = lua({ 'Tools/unreal_slot.lua', 'claim', 'c-street-city', 'reach check scan (source map editor, read only)', '--wait', '--need-gb', '45' })
    assert(code == 0, 'claim: ' .. out); held = true
    local t0 = os.time()
    os.remove(MOTEL .. 'serve-ready.json')
    ok.proc.spawn({ L, 'Tools/street_city_motel_native.lua', 'serve' }, { hide = true, stdout_file = MOTEL .. 'serve-reach.log', merge = true })
    serving = true
    local w = 0
    while true do
      local a, b = j.decode(read(MOTEL .. 'serve-ready.json') or 'null'), j.decode(read(MOTEL .. 'serve-payload.json') or 'null')
      if a and b and a.status == 'passed' and a.run_id == b.run_id then break end
      assert(w < 900, 'serve not ready'); ok.time.sleep(10); w = w + 10
    end
    print(('editor ready after %d s'):format(os.time() - t0))
    for k, r in ipairs(runs) do
      -- the segment counts from the claim (the editor takes 5-6 minutes to start); one batch always runs
      if k > 1 and os.time() - t0 > minutes * 60 then print('time is up; run scan again to go on'); break end
      write(PLACES .. 'reach-batch.json', j.encode({ from = r[1], to = r[2] }))
      local s = os.time()
      local c, o = lua({ 'Tools/street_city_motel_job.lua', 'world_reach_survey', 'Tools/street_city_reach_survey_payload.lua' })
      assert(c == 0, 'scan: ' .. o:sub(-600))
      print(('tiles %d-%d in %d s'):format(r[1], r[2], os.time() - s)); io.stdout:flush()
      ok.time.sleep(1) -- job ids are stamped to the second
    end
  end, debug.traceback)
  finish()
  assert(done, err)
end

-- One cell from a code: g = ground minus z (nil: no ground), f40/f30 free, b = blocker label.
local function decode(code, legend)
  if code == 'n' then return nil end
  local k = code:match('^b(%d+)$'); if k then return { b = legend[tonumber(k) + 1] or '?' } end
  local narrow = code:sub(-1) == ','
  return { g = tonumber(narrow and code:sub(1, -2) or code), f30 = true, f40 = not narrow }
end

local function report()
  local cfg = j.decode(assert(read(PLACES .. 'reach-tiles.json'), 'run plan first'))
  ROAD = j.decode(assert(read(DATA .. 'city_places.json'))).road
  local have = scanned()
  -- grid[z][ix][iy] = cell (false: scanned, no ground)
  local grid, missing = {}, 0
  for _, t in ipairs(cfg.tiles) do
    local h = have[t.key]
    if not h then missing = missing + 1 else
      local G = grid[t.z] or {}; grid[t.z] = G
      for jy, row in ipairs(h.rows) do local ix = t.ix0
        for code in row:gmatch('%S+') do local col = G[ix] or {}; G[ix] = col; col[t.iy0 + jy - 1] = decode(code, h.legend) or false; ix = ix + 1 end
      end
    end
  end
  local function at(z, ix, iy) local col = grid[z] and grid[z][ix]; if not col then return nil end; return col[iy] end
  -- passable: free at 30 with ground; upstairs a cell whose ground is more than 60 cm under the floor is not (the void)
  local function pass(z, ix, iy, up) local c = at(z, ix, iy); return c and c.f30 and (not up or c.g >= -60) end
  -- connected regions per (z, upstairs rule)
  local regions = {}
  local function region_of(z, up)
    local key = z .. (up and 'u' or 's'); if regions[key] then return regions[key] end
    local id, size, edge, n = {}, {}, {}, 0
    local function getid(ix, iy) local c = id[ix]; return c and c[iy] end
    for ix, col in pairs(grid[z] or {}) do for iy in pairs(col) do
      if pass(z, ix, iy, up) and not getid(ix, iy) then
        n = n + 1; local stack, cnt, open = { { ix, iy } }, 0, false
        id[ix] = id[ix] or {}; id[ix][iy] = n
        while #stack > 0 do local c = table.remove(stack); local x, y = c[1], c[2]; cnt = cnt + 1
          local here = at(z, x, y)
          for dx = -1, 1 do for dy = -1, 1 do if dx ~= 0 or dy ~= 0 then local nx, ny = x + dx, y + dy
            local nc = at(z, nx, ny)
            if nc == nil then open = true -- the scan ends here: the region runs on
            elseif pass(z, nx, ny, up) and not getid(nx, ny) and math.abs(nc.g - here.g) <= STEP
              and (dx == 0 or dy == 0 or (pass(z, x + dx, y, up) and pass(z, x, y + dy, up))) then
              id[nx] = id[nx] or {}; id[nx][ny] = n; stack[#stack + 1] = { nx, ny } end end end end
        end
        size[n] = cnt; edge[n] = open
      end
    end end
    -- The road graph joins regions too: where the grid finds no way the game walks the road graph, whose passages
    -- (Tools/street_city_roads_add.lua, the cut shop passages) go through gaps the 30 cm cells do not (the body is 28):
    -- the izakaya's NE room is 140 cells on the grid and walked out of in the game every time (11-16). A link of this
    -- floor whose two ends have a passable cell within 2 cells joins their regions.
    local parent = {}
    local function root(a) while parent[a] and parent[a] ~= a do a = parent[a] end; return a end
    local function near(x, y)
      for r = 0, 2 do for dx = -r, r do for dy = -r, r do
        if math.max(math.abs(dx), math.abs(dy)) == r and pass(z, x + dx, y + dy, up) then return getid(x + dx, y + dy) end end end end
    end
    for _, l in ipairs(ROAD.links) do
      local a, b = ROAD.nodes[l[1] + 1], ROAD.nodes[l[2] + 1]
      if a and b and math.abs(a[3] - z) <= 60 and math.abs(b[3] - z) <= 60 then
        local ra, rb = near(cellof(a[1]), cellof(a[2])), near(cellof(b[1]), cellof(b[2]))
        if ra and rb then ra, rb = root(ra), root(rb); if ra ~= rb then parent[rb] = ra end end
      end
    end
    if next(parent) then
      local tot, open = {}, {}
      for r = 1, n do local q = root(r); tot[q] = (tot[q] or 0) + size[r]; open[q] = open[q] or edge[r] end
      for _, col in pairs(id) do for iy, r in pairs(col) do col[iy] = root(r) end end
      for r = 1, n do size[r] = tot[root(r)]; edge[r] = open[root(r)] end
    end
    regions[key] = { id = id, size = size, edge = edge }; return regions[key]
  end
  -- the nearest passable cell within the goal rings, as the game picks a goal on furniture
  local function nearest(z, ix, iy, up)
    if pass(z, ix, iy, up) then return ix, iy, 0 end
    for r = 1, GOAL_RINGS do for dx = -r, r do for dy = -r, r do
      if math.max(math.abs(dx), math.abs(dy)) == r and pass(z, ix + dx, iy + dy, up) then return ix + dx, iy + dy, r end end end end
  end
  -- probe: are two points of one floor joined (as upstairs and as street), and the cells round the first
  if PROBE then
    local z, x1, y1, x2, y2 = table.unpack(PROBE)
    for _, up in ipairs({ true, false }) do
      local R = region_of(z, up)
      local function rid(ix, iy) local c = R.id[ix]; return c and c[iy] end
      local a, b = rid(cellof(x1), cellof(y1)), rid(cellof(x2), cellof(y2))
      print(('%s: first in region %s (%s cells), second in region %s (%s cells)'):format(up and 'upstairs rule' or 'street rule',
        tostring(a), a and R.size[a] or '-', tostring(b), b and R.size[b] or '-'))
    end
    local R = region_of(z, true)
    local cx, cy = cellof(x1), cellof(y1)
    local c0 = at(z, cx, cy)
    print('first cell: ' .. (c0 == nil and 'not scanned' or c0 == false and 'no ground' or c0.b and ('blocked by ' .. c0.b) or ('ground ' .. c0.g .. (c0.f40 and '' or ', free at 30 only'))))
    for iy = cy + 15, cy - 15, -1 do local row = {}
      for ix = cx - 30, cx + 30 do local c = at(z, ix, iy)
        local ch = c == nil and '?' or c == false and ' ' or c.b and '#' or (c.g < -60 and 'v') or (c.f40 and '.' or ',')
        if ix == cx and iy == cy then ch = 'A' elseif ix == cellof(x2) and iy == cellof(y2) then ch = 'B' end
        row[#row + 1] = ch end
      print(('%6d %s'):format(iy * CELL, table.concat(row)))
    end
    print(('x from %d to %d, step 40; ? not scanned, # blocked, v floor below, , free at 30 only'):format((cx - 30) * CELL, (cx + 30) * CELL))
    local blockers = {}
    for ix = cx - 30, cx + 30 do for iy = cy - 15, cy + 15 do local c = at(z, ix, iy); if c and c.b then blockers[c.b] = (blockers[c.b] or 0) + 1 end end end
    for k, v in pairs(blockers) do print(('  %4d %s'):format(v, k)) end
    return true
  end
  local places = load_points()
  local groups, order = {}, {}
  local function add(kind, text) if not groups[kind] then groups[kind] = {}; order[#order + 1] = kind end; table.insert(groups[kind], text) end
  local function xy(q) return ('(%d,%d,%d)'):format(round(q.pos[1]), round(q.pos[2]), round(q.pos[3])) end
  local checked = 0
  for _, p in ipairs(places) do
    for fi, z in ipairs(p.floors) do
      local up = z > p.points[1].z + 60 and not p.outdoor -- over the door's floor
      local R = region_of(z, up)
      local function rid(ix, iy) local c = R.id[ix]; return c and c[iy] end
      -- seeds: the door on its floor; upstairs the lift landings and stairs
      local seeds, has_seed_point = {}, false
      for _, q in ipairs(p.points) do
        if q.z == z and (q.door or (up and (q.name:match('^lift') or q.name:match('^stair')))) then has_seed_point = true
          local x, y = nearest(z, q.ix, q.iy, up)
          if x then seeds[rid(x, y)] = true
          elseif q.door then add(K.door_blocked, ('%s 門 %s'):format(p.id, xy(q))) end
        end
      end
      if not p.outdoor and not has_seed_point then
        local n = 0; for _, q in ipairs(p.points) do if q.z == z then n = n + 1 end end
        add(K.no_entry, ('%s 第 %d 層（z %d），%d 個錨點'):format(p.id, fi, z, n))
      else
        -- the door's region has to reach the street: open (runs off the scan) or holds cells outside the place's rooms
        if z == p.points[1].z and not p.outdoor and next(seeds) then
          local outside = false
          for r_ in pairs(seeds) do if R.edge[r_] then outside = true end end
          if not outside then for ix, col in pairs(R.id) do for iy, r_ in pairs(col) do if seeds[r_] and not outside then
            local x, y = ix * CELL, iy * CELL; local inroom = false
            for _, r in ipairs(p.rooms) do if r.min and x >= r.min[1] and x <= r.max[1] and y >= r.min[2] and y <= r.max[2] then inroom = true end end
            if not inroom then outside = true end end end end end
          if not outside then add(K.door_street, ('%s 門 %s'):format(p.id, xy(p.points[1]))) end
        end
        for _, q in ipairs(p.points) do if q.z == z and not q.door and not exempt(p.id, q.name) then checked = checked + 1
          local c = at(z, q.ix, q.iy)
          local x, y, r = nearest(z, q.ix, q.iy, up)
          local where = ('%s.%s %s'):format(p.id, q.name, xy(q))
          if c == nil then add(K.unscanned, where)
          elseif not x then
            local any = false; for dx = -2, 2 do for dy = -2, 2 do local cc = at(z, q.ix + dx, q.iy + dy); if cc and cc.g then any = true end end end
            if not any then add(K.no_floor, where)
            else add(K.no_cell, where .. (c and c.b and ('，擋住的是 ' .. c.b) or '')) end
          else
            -- The game's spot choice (OKStreetSocialSchedule.inl): a spot in furniture is replaced by one round it, 80
            -- and 140 cm out, that a grid route from inside the door (upstairs: the floor's stair landing) reaches. So
            -- the anchor is reached when any passable cell within NEAR_RINGS is in a region its floor is entered by.
            local function good(reg) if p.outdoor then return R.edge[reg] or R.size[reg] >= OPEN_CELLS or seeds[reg] end; return seeds[reg] end
            local reached, best = false, nil
            for rr = 0, NEAR_RINGS do for dx = -rr, rr do for dy = -rr, rr do
              if not reached and math.max(math.abs(dx), math.abs(dy)) == rr and pass(z, q.ix + dx, q.iy + dy, up) then
                local reg = rid(q.ix + dx, q.iy + dy)
                if good(reg) then reached = rr elseif not best or R.size[reg] > best then best = R.size[reg] end end end end end
            if not reached then add(K.sealed, ('%s，附近最大的區域 %d 格'):format(where, best or 0))
            elseif reached > 0 and c and c.b then
              add(K.in_furniture, ('%s，擋住的是 %s，%d 格外走得到'):format(where, c.b, reached))
              -- in sight: where a player watches her stand (a counter, a till, a sofa): listed one by one
              local shown
              for _, k in ipairs(q.kinds or {}) do if SHOWN[k] then shown = k end end
              if shown then add(K.in_sight, ('%s（%s），擋住的是 %s，%d 格外走得到'):format(where, shown, c.b, reached)) end
            end
          end
        end end
      end
    end
  end
  local md = { '# 大學城地點與錨點可達性（自動產生）', '',
    '由 `Tools/street_city_reach_check.lua report` 產生：在來源地圖上照遊戲的 NavCellFree 逐格判定（40 cm 格點、半徑 40／30 膠囊、WorldStatic 簡單碰撞、相鄰格高差 40 cm 以內），1 樓從門口、樓上從電梯平台與樓梯錨點灌水。只是線索：可不可以走以遊戲裡實際走為準。', '',
    ('檢查 %d 個地點、%d 個錨點；未掃到的區塊 %d 個。'):format(#places, checked, missing), '' }
  local total = 0
  for _, kind in ipairs(order) do local list = groups[kind]; table.sort(list); if kind ~= K.in_sight then total = total + #list end
    md[#md + 1] = ('## %s（%d）'):format(kind, #list); md[#md + 1] = ''
    if kind == K.in_furniture then
      -- thousands: counts per place here, every row in places-v1/reach-report.json
      local per, names = {}, {}
      for _, t in ipairs(list) do local id = t:match('^([%w_%-]+)%.'); if not per[id] then per[id] = 0; names[#names + 1] = id end; per[id] = per[id] + 1 end
      table.sort(names, function(a, b) return per[a] > per[b] or per[a] == per[b] and a < b end)
      local cells = {}; for _, id in ipairs(names) do cells[#cells + 1] = ('%s %d'):format(id, per[id]) end
      md[#md + 1] = '各地點筆數（每一筆在 output/street-social-city-production/places-v1/reach-report.json）：' .. table.concat(cells, '、')
    else for _, t in ipairs(list) do md[#md + 1] = '- ' .. t end end
    md[#md + 1] = '' end
  local text = table.concat(md, '\n') .. '\n'
  -- --diff: against the committed report (git HEAD): what is new and what is gone, item by item (per-place counts for the
  -- in-furniture group), so a map or anchor change shows at once what it broke
  if DIFF then
    local function items(s)
      local set, sec = {}, ''
      for line in s:gmatch('[^\r\n]+') do
        if line:match('^## ') then sec = line:gsub('（%d+）$', ''):gsub('^## ', '')
        elseif line:match('^%- ') then set[sec .. ' :: ' .. line:sub(3)] = true
        elseif line:match('^各地點筆數') then for id, n in line:gmatch('([%w_%-]+) (%d+)') do set[sec .. ' :: ' .. id .. ' ' .. n] = true end end
      end
      return set
    end
    local r = ok.proc.run({ 'git', 'show', 'HEAD:Docs/STREET_CITY_REACH.md' }, { capture = true })
    local old, new = items(r.stdout or ''), items(text)
    local added, gone = {}, {}
    for k in pairs(new) do if not old[k] then added[#added + 1] = k end end
    for k in pairs(old) do if not new[k] then gone[#gone + 1] = k end end
    table.sort(added); table.sort(gone)
    print(('against the committed report: %d new, %d gone'):format(#added, #gone))
    for _, k in ipairs(added) do print('  + ' .. k) end
    for _, k in ipairs(gone) do print('  - ' .. k) end
  end
  write('Docs/STREET_CITY_REACH.md', text)
  write(PLACES .. 'reach-report.json', j.encode({ groups = groups, order = order, checked = checked, missing = missing }))
  for _, kind in ipairs(order) do print(('%5d  %s'):format(#groups[kind], kind)) end
  print(('%d anchors checked, %d problems, %d tiles not scanned'):format(checked, total, missing))
  return total == 0 and missing == 0
end

local cmd = arg[1]
if cmd == 'plan' then plan()
elseif cmd == 'scan' then
  local minutes, batch = 17, 20
  local i = 2; while arg[i] do
    if arg[i] == '--minutes' then minutes = tonumber(arg[i + 1]); i = i + 2
    elseif arg[i] == '--batch' then batch = tonumber(arg[i + 1]); i = i + 2 else error('unknown argument ' .. arg[i]) end end
  scan(minutes, batch)
elseif cmd == 'report' then DIFF = arg[2] == '--diff'; os.exit(report() and 0 or 1)
elseif cmd == 'probe' then PROBE = { tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4]), tonumber(arg[5]), tonumber(arg[6]) }; report()
else print('usage: plan | scan [--minutes M] [--batch N] | report'); os.exit(2) end
