-- The campus buildings' north restroom door (one template in 13 buildings, every floor): the shell's door in the corridor
-- wall opens straight onto the back of the stall row (an inner wall, the stall partitions and their WCs), so nobody gets in
-- (Tools/street_city_reach_check.lua, 11-16: 52 trash anchors sealed on floors 2-5; on 1F the same, the trash only reached
-- through the outer wall). One rule, from the restroom's trash anchor (tx, ty) as the template places it:
--   the corridor wall's door  x tx+295..tx+405 at y ty-560..ty-545
--   the stall row behind it   y ty-540..ty-275, a WC bowl at x tx+235..tx+265 and one at tx+385..tx+415
-- cut: an aisle x tx+265..tx+385 (120 cm, between the two bowls), y ty-565..ty-260, from 2 cm over the floor to 2.6 m,
-- out of the floor's shell (drawn mesh and its complex collision source). 120 cm holds a free cell of the game's 40 cm
-- lattice at radius 40 wherever the lattice falls; two would take a WC out.
--   Tools\lua\lua.exe Tools\street_city_restroom_doors.lua [apply] [--served]
-- --served: the source map editor is already serving (a session script that holds the slot runs this inside it).
-- Without apply: measure only (lists the shell actors and their meshes, nothing changes). apply: backs the meshes up to
-- output/street-social-city-production/world-edge-v1/restroom-doors-<stamp>/, cuts, then scans the doors with the game's
-- cell test (room survey `game`). Claims an Unreal slot (source map editor) and releases it.
-- (11-16 c-street-city, coordinator's reach list class A; the two dorms' washrooms, the same module on 2F-6F, added after)
package.path = 'Tools/lua/?.lua;' .. package.path
local ok = require('ok'); local j = require('ok.json'); local lfs = require('lfs'); local L = ok.lua_exe
local PLACES = 'output/street-social-city-production/places-v1/'
local MOTEL = 'output/street-social-city-production/motel-v1/'
local BACK = 'output/street-social-city-production/world-edge-v1/'
local OUT = PLACES .. 'restroom-doors-result.json'
local APPLY, SERVED = false, false
for _, a in ipairs(arg) do if a == 'apply' then APPLY = true elseif a == '--served' then SERVED = true end end
local function read(p) local f = io.open(p, 'rb'); if not f then return nil end; local s = f:read('a'); f:close(); return s end
local function write(p, s) local f = assert(io.open(p, 'wb')); f:write(s); f:close() end
local function lua(args) local cmd = { L }; for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  local r = ok.proc.run(cmd, { capture = true, merge = true }); return r.code, r.stdout or '' end

-- place -> { shell label prefix, the north restroom's trash y }
local BUILDINGS = {
  campus_t1 = { 'Campus_T1', 56355 }, campus_t2 = { 'Campus_T2', 74355 }, campus_t4 = { 'Campus_T4', 48355 },
  campus_ee = { 'Campus_EE', 65355 }, campus_ib = { 'Campus_IB', 74355 }, campus_ma = { 'Campus_MA', 65355 },
  campus_rb = { 'Campus_RB', 48355 }, campus_ad = { 'Campus_AD', 74055 }, campus_e1 = { 'Campus_E1', 50555 },
  library = { 'Campus_LI', 66555 }, cafeteria = { 'Campus_SC', 49055 }, campus_sports = { 'Campus_SP', 38955 },
  civic = { 'City_CV', 63755 },
  -- the dorms' washroom (same module, 2F-6F; 11-16 reach list: 36 vanity/trash anchors sealed, room survey 10 cm at z 1980:
  -- the door in the corridor wall at tx+295..tx+405, the stall row behind it, D2 the same as D1 24 m north)
  girls_dorm = { 'Campus_D1', 41855 }, boys_dorm = { 'Campus_D2', 65855 },
}

-- the cuts, one per floor: that restroom's trash anchors (rules table and places), floors numbered by height from 1F
local function cuts()
  local A = j.decode(assert(read('Content/IndependentResources/StreetSocialData/city_anchors.json'))).anchors
  local P = j.decode(assert(read('Content/IndependentResources/StreetSocialData/city_places.json'))).places
  local at = {}
  local function take(place, a) local b = BUILDINGS[place]
    if b and a.name:match('^trash') and math.abs(a.pos[2] - b[2]) < 1 then
      at[place] = at[place] or {}; at[place][math.floor(a.pos[3] + .5)] = { a.pos[1], a.pos[2] } end end
  for _, r in ipairs(A) do take(r.place, r) end
  for _, p in ipairs(P) do for _, a in ipairs(p.anchors or {}) do take(p.id, a) end end
  local list, actors = {}, {}
  local names = {}; for k in pairs(BUILDINGS) do names[#names + 1] = k end; table.sort(names)
  for _, place in ipairs(names) do local zs = {}
    for z in pairs(at[place] or {}) do zs[#zs + 1] = z end; table.sort(zs)
    assert(#zs >= 5, place .. ': expected a trash anchor on 5 floors, found ' .. #zs)
    -- the shells are numbered from 1F (z 1200, 3.6 m a floor); the dorms' washrooms start on 2F
    local first = math.floor((zs[1] - 1200) / 360 + .5)
    for i, z in ipairs(zs) do local tx, ty = at[place][z][1], at[place][z][2]
      local label = ('%s_F%02d'):format(BUILDINGS[place][1], i + first)
      actors[#actors + 1] = label
      list[#list + 1] = { name = ('%s_%dF'):format(place, i), actors = { label }, z = z, door = { tx + 325, ty - 600, z },
        box = { tx + 265, ty - 565, z + 2, tx + 385, ty - 260, z + 260 } }
    end
  end
  return list, actors
end

local held, serving = false, false
local function finish()
  write(PLACES .. 'shop-passage-apply.txt', '0')
  if serving then lua({ 'Tools/street_city_motel_job.lua', 'quit', 'Tools/street_city_walk_probe_payload.lua' }); ok.time.sleep(40) end
  if held then lua({ 'Tools/unreal_slot.lua', 'release', 'c-street-city' }) end
end
local function main()
  local list, actors = cuts()
  print(('%d cuts in %d shells'):format(#list, #actors))
  write(PLACES .. 'shop-passage.json', j.encode({ actors = actors, cuts = list, slice_z = 1300 }))
  write(PLACES .. 'shop-passage-apply.txt', '0')
  if not SERVED then
    local code, out = lua({ 'Tools/unreal_slot.lua', 'claim', 'c-street-city', 'restroom doors ' .. (APPLY and 'cut' or 'measure') .. ' (source map editor)', '--wait', '--need-gb', '45' })
    assert(code == 0, 'claim: ' .. out); held = true
    os.remove(MOTEL .. 'serve-ready.json')
    ok.proc.spawn({ L, 'Tools/street_city_motel_native.lua', 'serve' }, { hide = true, stdout_file = MOTEL .. 'serve-restroom-doors.log', merge = true })
    serving = true
    local t = 0
    while true do
      local a, b = j.decode(read(MOTEL .. 'serve-ready.json') or 'null'), j.decode(read(MOTEL .. 'serve-payload.json') or 'null')
      if a and b and a.status == 'passed' and a.run_id == b.run_id then break end
      assert(t < 900, 'serve not ready'); ok.time.sleep(10); t = t + 10
    end
  end
  -- measure: the shells and their meshes
  local c, o = lua({ 'Tools/street_city_motel_job.lua', 'world_shop_passage', 'Tools/street_city_shop_passage_payload.lua' })
  assert(c == 0, 'measure: ' .. o:sub(-600))
  local m = j.decode(read(PLACES .. 'shop-passage-result.json'))
  local found, files = {}, {}
  for _, row in ipairs(m.actors) do found[row.actor] = true
    for _, path in ipairs({ row.mesh, row.collision }) do if type(path) == 'string' then
      local f = 'StreetSocialCity/Content/' .. path:gsub('^/Game/', ''):gsub('%.[^/]*$', '') .. '.uasset'; files[f] = true end end end
  local missing = {}; for _, a in ipairs(actors) do if not found[a] then missing[#missing + 1] = a end end
  assert(#missing == 0, 'shell actors not found: ' .. table.concat(missing, ' '))
  local nf = 0; for _ in pairs(files) do nf = nf + 1 end
  print(('measured: %d shells, %d mesh files'):format(#actors, nf))
  local all = list
  -- Already cut: an aisle whose inside (5 cm in from the box) is clear on a 10 cm scan is left alone, so a second run
  -- cuts nothing (the boolean re-triangulates a mesh even where the box is empty, so the mesh itself cannot tell).
  do
    local areas = {}
    for _, cut in ipairs(list) do local b = cut.box
      areas[#areas + 1] = { name = cut.name, box = { b[1] + 10, b[2] + 10, b[4] - 10, b[5] - 10 }, z = cut.z, step = 10 } end
    write(PLACES .. 'room-survey.json', j.encode({ areas = areas }))
    c, o = lua({ 'Tools/street_city_motel_job.lua', 'world_room_survey', 'Tools/street_city_room_survey_payload.lua' })
    assert(c == 0, 'pre-survey: ' .. o:sub(-600))
    local s = j.decode(read(PLACES .. 'room-survey-result.json'))
    local clear = {}
    for _, a in ipairs(s.areas) do local ok_ = true
      for _, row in ipairs(a.thin) do if row:find('[^%. ]') then ok_ = false end end
      clear[a.name] = ok_ end
    local left = {}
    for _, cut in ipairs(list) do if not clear[cut.name] then left[#left + 1] = cut end end
    print(('%d of %d aisles already clear, %d to cut'):format(#list - #left, #list, #left))
    list = left
    local acts = {}; for _, cut in ipairs(list) do acts[#acts + 1] = cut.actors[1] end
    write(PLACES .. 'shop-passage.json', j.encode({ actors = acts, cuts = list, slice_z = 1300 }))
  end
  local result = { apply = APPLY, cuts = list, files = {} }
  if APPLY and #list > 0 then
    local dir = BACK .. 'restroom-doors-' .. os.date('%Y%m%d-%H%M%S') .. '/'; lfs.mkdir(dir)
    for f in pairs(files) do assert(lfs.attributes(f, 'mode') == 'file', 'mesh file missing: ' .. f)
      write(dir .. f:gsub('/', '@'), assert(read(f))); result.files[#result.files + 1] = f end
    print('backed up to ' .. dir); result.backup = dir
    write(PLACES .. 'shop-passage-apply.txt', '1')
    c, o = lua({ 'Tools/street_city_motel_job.lua', 'world_shop_passage', 'Tools/street_city_shop_passage_payload.lua' })
    write(PLACES .. 'shop-passage-apply.txt', '0')
    assert(c == 0, 'cut: ' .. o:sub(-600))
    result.cut = j.decode(read(PLACES .. 'shop-passage-result.json')).cuts
    local saved, errors = 0, 0
    for _, row in ipairs(result.cut) do for _, e in ipairs(row.meshes) do if e.saved then saved = saved + 1 end; if e.error then errors = errors + 1; print('error', row.name, e.error) end end end
    print(('cut: %d meshes saved, %d errors'):format(saved, errors))
  end
  -- the doors with the game's cell test: from the corridor through the door into the restroom
  local areas = {}
  for _, cut in ipairs(all) do local b = cut.box
    areas[#areas + 1] = { name = cut.name, box = { b[1] - 120, b[2] - 120, b[4] + 120, b[5] + 120 }, z = cut.z, step = 10 } end
  write(PLACES .. 'room-survey.json', j.encode({ areas = areas }))
  c, o = lua({ 'Tools/street_city_motel_job.lua', 'world_room_survey', 'Tools/street_city_room_survey_payload.lua' })
  assert(c == 0, 'survey: ' .. o:sub(-600))
  local s = j.decode(read(PLACES .. 'room-survey-result.json'))
  result.doors = {}
  for _, a in ipairs(s.areas) do
    -- the aisle's column of game cells (the lattice x inside tx+305..tx+345) from the corridor to the restroom
    local open = 0
    for _, row in ipairs(a.game) do for ch in row:gmatch('.') do if ch == '.' or ch == ',' then open = open + 1 end end end
    result.doors[#result.doors + 1] = { name = a.name, game = a.game, game_origin = a.game_origin, free_cells = open }
    print(a.name); for _, row in ipairs(a.game) do print('  ' .. row) end
  end
  write(OUT, j.encode(result))
end
local done, err = xpcall(main, debug.traceback)
finish()
if not done then print('FAILED', err); os.exit(1) end
print('done; ' .. OUT)
