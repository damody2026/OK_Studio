-- One run for a batch of shop passages and the World Partition rebuild that brings them into the game:
--   Tools\lua\lua.exe Tools\street_city_passage_batch.lua --batch r1114 [--from STEP] [--check-only]
-- STEP: claim, serve, measure, apply, probe, prep, stream, migrate, roads (default: claim, the whole run).
-- --check-only: claim, measure and stop (nothing in the map changes).
-- The slot (need 130 GB, the run is alone on the machine) is claimed first and released at the end or on any failure.
--
-- Per passage (a line along x through one shop):
--   measure  apply=0 floor scans at z 1290 and 1220 (20 cm cells) of a band round the candidate lines. On the line
--            itself every block must be a wall, no thicker than 60 cm (the walls on the 11-13 scans are 20-40 cm; a
--            thicker one is a counter or shelf the cut would not remove), and the first and last 2 m must be free. Each
--            wall gets a cut box 40 cm wider than it on both sides, 2.2 m along the line, z 1195-1430. Of the candidates
--            left, the one with the fewest 20 cm columns that have something within 60 cm beside the line wins, then
--            the fewest walls. (11-14: a counter beside the S38 line stopped the walk; a ray along a wall from inside it
--            hits nothing, so the scan, not rays, finds the walls. Try lines on an old scan: --judge.)
--   apply    backs up the shop meshes (places-v1/backup-<batch>/), cuts, and scans the 60 cm band again (reported).
--   probe    world_walk_probe along each cut line decides: a passage not walked through is left out of the roads.
-- Then stream prep, the WP convert + HLOD in 8 groups (a watcher kills the editor below 4 GB free commit), the content
-- migrate, the export with the passages taken (OK_EXTRA_PASSAGES) and street_city_roads_add.lua for each.
-- Report: output/street-social-city-production/places-v1/passage-batch-<batch>.json (and the log beside it).
--   Tools\lua\lua.exe Tools\street_city_passage_batch.lua --watch <log> <stopfile>   (the memory watcher, started by the run)
package.path = 'Tools/lua/?.lua;' .. package.path
local ok = require('ok')
local j = require('ok.json')
local L = ok.lua_exe
local PLACES = 'output/street-social-city-production/places-v1/'
local MOTEL = 'output/street-social-city-production/motel-v1/'

local BATCHES = {
  -- 11-14 (c-street-city): the three shop rows whose passages cut road detours most (classify of the 40 pairs over 2x).
  r1114 = {
    passages = {
      -- S59 (x 33200-35200, y 33960-35160): nail-park, festival-nail, nail-shrine
      { id = 'a1', actors = { 'S59_F01', 'ShopV1_S59_Refit' }, x0 = 32700, x1 = 35700, ys = { 34760, 34640, 34880, 34520, 35000 } },
      -- S69 (x 33300-35100, y 46560-47560): clothing_s46-crepe, crepe-karaoke, karaoke-sushi, crepe-onsen
      { id = 'a2', actors = { 'S69_F01', 'ShopV1_S69_Refit' }, x0 = 32700, x1 = 35700, ys = { 47300, 47180, 47060, 47420 } },
      -- S84 (x 29400-31000, y 36020-37020): breakfast-church, church-yakiniku, church-clinic_beauty. y 37000 runs in the
      -- north wall itself, so the candidates start inside the shop.
      { id = 'c', actors = { 'S84_F01', 'ShopV1_S84_Refit' }, x0 = 29200, x1 = 31600, ys = { 36780, 36660, 36540, 36420 } },
    },
    -- scans for map items handed over by c-conquest (round 7): read only, kept in the report
    extra = {
      { name = 'boys_dorm_3F_lift', box = { 92400, 55800, 93800, 57200 }, z = { 2080, 1720 } }, -- R6-226: 3F against 2F
      { name = 'department_9F_lift_ramen', box = { 45400, 57800, 48400, 60500 }, z = { 4650 } }, -- R6-197
      { name = 'amusement_coaster', box = { 95600, 45200, 101600, 54800 }, z = { 1290 }, step = 40 }, -- R6-241 layout
    },
  },
}

local function read(p) local f = io.open(p, 'rb'); if not f then return nil end; local s = f:read('a'); f:close(); return s end
local function write(p, s) local f = assert(io.open(p, 'wb')); f:write(s); f:close() end
local function now() return os.date('%H:%M:%S') end

-- memory watcher (own process): log free commit every 20 s, kill the editor below 4 GB
if arg[1] == '--watch' then
  local log, stop = arg[2], arg[3]
  while not read(stop) do
    local out = ok.proc.run({ 'powershell', '-NoProfile', '-Command',
      "$f=[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory/1MB); $e=Get-Process UnrealEditor-Cmd -ErrorAction SilentlyContinue; " ..
      "'{0} free={1} {2}' -f (Get-Date -f HH:mm:ss),$f,(($e|%{ '{0}:{1}' -f $_.Id,[int]($_.PagedMemorySize64/1GB) }) -join ' '); " ..
      "if($f -lt 4 -and $e){ $e|Stop-Process -Force; 'KILLED low commit' }" }, { capture = true, hide = true })
    local f = io.open(log, 'ab'); f:write(out.stdout or ''); f:close()
    ok.time.sleep(20)
  end
  return
end

local batch_id, from, check_only = (arg[1] == '--judge') and 'r1114' or nil, 'claim', false
local i = (arg[1] == '--judge') and #arg + 1 or 1
while arg[i] do
  if arg[i] == '--batch' then batch_id = arg[i + 1]; i = i + 2
  elseif arg[i] == '--from' then from = arg[i + 1]; i = i + 2
  elseif arg[i] == '--check-only' then check_only = true; i = i + 1
  else error('unknown argument ' .. arg[i], 0) end
end
local B = assert(BATCHES[batch_id or ''], '--batch <id>: ' .. table.concat((function() local t = {} for k in pairs(BATCHES) do t[#t + 1] = k end return t end)(), ', '))
local STEPS = { 'claim', 'serve', 'measure', 'apply', 'probe', 'prep', 'stream', 'migrate', 'roads' }
local order = {}; for n, s in ipairs(STEPS) do order[s] = n end
assert(order[from], '--from: ' .. table.concat(STEPS, ', '))
local function due(step) return order[step] >= order[from] end

local REPORT = PLACES .. 'passage-batch-' .. batch_id .. '.json'
local LOG = PLACES .. 'passage-batch-' .. batch_id .. '.log'
local rep = j.decode(read(REPORT) or '{}'); rep.batch = batch_id
local function save() write(REPORT, j.encode(rep)) end
local function log(...) local s = now() .. ' ' .. table.concat({ ... }, ' '); print(s); local f = io.open(LOG, 'ab'); f:write(s .. '\n'); f:close() end
local function lua(args, env) local list = { L }; for _, a in ipairs(args) do list[#list + 1] = a end
  local r = ok.proc.run(list, { capture = true, merge = true, env = env }); return r.code, r.stdout or '' end

-- slot + serve bookkeeping, undone on any exit
-- a run picked up after the serve step (--from measure..prep) finds the editor of the run before still serving
local held, serving = false, (order[from] > order["serve"] and order[from] <= order["prep"])
local function quit_serve() if serving then lua({ 'Tools/street_city_motel_job.lua', 'quit', 'Tools/street_city_shop_passage_payload.lua' }); serving = false; ok.time.sleep(40) end end
local function release() if held then quit_serve(); lua({ 'Tools/unreal_slot.lua', 'release', 'c-street-city' }); held = false; log('slot released') end end
local SHOP_CFG = PLACES .. 'shop-passage.json'
local saved_cfg = read(SHOP_CFG)
local function fail(msg)
  write(PLACES .. 'shop-passage-apply.txt', '0'); if saved_cfg then write(SHOP_CFG, saved_cfg) end
  log('FAILED: ' .. msg); rep.failed = msg; save(); release(); os.exit(1)
end
local function job(mode, payload, minutes)
  local code, out = lua({ 'Tools/street_city_motel_job.lua', mode, payload }, { OK_JOB_MINUTES = tostring(minutes or 20) })
  if code ~= 0 then fail(mode .. ' exit ' .. code .. ': ' .. out:sub(-400)) end
end
local function scan(cfg)
  write(PLACES .. 'shop-passage-apply.txt', cfg.apply and '1' or '0')
  write(SHOP_CFG, j.encode({ actors = cfg.actors or {}, slice_z = cfg.z or 1290, cuts = cfg.cuts or {}, traces = cfg.traces or {}, grid = cfg.grid }))
  job('world_shop_passage', 'Tools/street_city_shop_passage_payload.lua')
  write(PLACES .. 'shop-passage-apply.txt', '0')
  write(SHOP_CFG, saved_cfg)
  return j.decode(read(PLACES .. 'shop-passage-result.json'))
end
local function free_commit_gb()
  local out = ok.proc.output({ 'powershell', '-NoProfile', '-Command', '[int]((Get-CimInstance Win32_OperatingSystem).FreeVirtualMemory/1MB)' }, { hide = true })
  return tonumber(out:match('%d+')) or 0
end
local function unreal_running()
  local out = ok.proc.run({ 'tasklist', '/FO', 'CSV', '/NH' }, { capture = true }).stdout or ''
  local n = 0; for name in out:gmatch('"([^"]+)"') do if name:find('^UnrealEditor') or name:find('^OpenKoikatsu') then n = n + 1 end end
  return n
end

-- grid: rows from box[2] up, columns from box[1]; '.' free
local function blocked(grids, x, y)
  for _, g in ipairs(grids) do
    local c = math.floor((x - g.box[1]) / g.step) + 1; local r = math.floor((y - g.box[2]) / g.step) + 1
    local row = g.rows[r]; if row then local ch = row:sub(c, c); if ch ~= '' and ch ~= '.' then return true end end
  end
  return false
end
-- distance from a point to the shop's own wall segments at the scan height (the scan's actors[].walls)
local function near_shop(segs, x, y)
  if not segs then return true end
  for _, s in ipairs(segs) do
    local ax, ay, bx, by = s[1][1], s[1][2], s[2][1], s[2][2]
    local dx, dy = bx - ax, by - ay; local l2 = dx * dx + dy * dy
    local t = l2 > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / l2)) or 0
    if math.sqrt((ax + t * dx - x) ^ 2 + (ay + t * dy - y) ^ 2) <= 40 then return true end
  end
  return false
end
-- pick the line: walls crossing it become cut boxes, the 60 cm band must be free otherwise
local function judge(p, y, grids, segs)
  local step = 20; local walls = {}; local run
  for x = p.x0, p.x1, step do
    local hit = blocked(grids, x, y)
    if hit then if run then run[2] = x else run = { x, x } end
    elseif run then walls[#walls + 1] = run; run = nil end
  end
  if run then walls[#walls + 1] = run end
  for _, w in ipairs(walls) do
    if w[2] + step - w[1] > 60 then return nil, ('block at x %d-%d is %d cm thick (not a wall)'):format(w[1], w[2] + step, w[2] + step - w[1]) end
    if w[1] < p.x0 + 200 or w[2] > p.x1 - 200 then return nil, ('blocked within 2 m of an end at x %d'):format(w[1]) end
    -- the cut only removes the shop's own meshes: a block that is not on one of its walls (a planter outside it on
    -- 11-14, the line y 35000 by S59) stays, so that line is no good
    if not near_shop(segs, (w[1] + w[2]) / 2 + 10, y) then return nil, ('block at x %d-%d is not a wall of %s'):format(w[1], w[2] + step, table.concat(p.actors, '/')) end
  end
  local cuts = {}
  for n, w in ipairs(walls) do cuts[n] = { name = p.id .. '_' .. n, box = { w[1] - 40, y - 110, 1195, w[2] + step + 40, y + 110, 1430 }, actors = p.actors } end
  -- things within 60 cm beside the line outside the cut boxes are warnings, not a rejection: on 11-13 scans the S64 line
  -- had a shelf edge 20 cm beside it and was walked through in the game anyway; the walk probe after the cut decides
  local function in_cut(x) for _, c in ipairs(cuts) do if x >= c.box[1] and x <= c.box[4] then return true end end return false end
  local warn = {}
  for x = p.x0, p.x1, step do
    if not in_cut(x) then for dy = -60, 60, 20 do if dy ~= 0 and blocked(grids, x, y + dy) then warn[#warn + 1] = { x, y + dy }; break end end end
  end
  return cuts, nil, warn
end
local function band(p) local lo, hi = math.huge, -math.huge; for _, y in ipairs(p.ys) do lo = math.min(lo, y); hi = math.max(hi, y) end
  return { p.x0, lo - 200, p.x1 + 20, hi + 200 } end

-- --judge <scan result json> <x0> <x1> <y>...: try lines on a scan made before (no Unreal), print the walls or the reason
if arg[1] == '--judge' then
  local g = j.decode(read(arg[2])).grid
  for k = 5, #arg do
    local cuts, why, warn = judge({ id = 'test', actors = {}, x0 = tonumber(arg[3]), x1 = tonumber(arg[4]) }, tonumber(arg[k]), { g })
    if cuts then local t = {}; for _, c in ipairs(cuts) do t[#t + 1] = c.box[1] .. '-' .. c.box[4] end
      print(('y %s: ok, cut x %s; %d columns with something within 60 cm%s'):format(arg[k], table.concat(t, ' '), #warn, warn[1] and (' (first ' .. warn[1][1] .. ',' .. warn[1][2] .. ')') or ''))
    else print('y ' .. arg[k] .. ': no, ' .. why) end
  end
  return
end

-- the run itself: any error on the way still puts the flag and config back, quits the editor and releases the slot
local function main()
-- 1 claim: exclusive, and only with 130 GB free commit and no other Unreal running
if due('claim') then
  if read('Saved/pause-street-city.flag') then fail('Saved/pause-street-city.flag is set') end
  log('claiming the slot (need 130)')
  local code, out = lua({ 'Tools/unreal_slot.lua', 'claim', 'c-street-city', 'passage batch ' .. batch_id .. ': cuts + WP rebuild (exclusive)', '--wait', '--need-gb', '130' })
  if code ~= 0 then fail('claim: ' .. out) end
  held = true
  local waited = 0
  while free_commit_gb() < 130 or unreal_running() > 0 do
    if waited >= 1800 then fail(('after 30 min: %d GB free commit, %d Unreal running'):format(free_commit_gb(), unreal_running())) end
    ok.time.sleep(60); waited = waited + 60
  end
  log(('claimed: %d GB free commit, no other Unreal'):format(free_commit_gb()))
else held = true end

-- 2 serve
if due('serve') and order[from] <= order['prep'] then
  os.remove(MOTEL .. 'serve-ready.json')
  ok.proc.spawn({ L, 'Tools/street_city_motel_native.lua', 'serve' }, { hide = true, stdout_file = MOTEL .. 'serve-batch.log', merge = true })
  serving = true
  local t = 0
  while true do
    local a, b = j.decode(read(MOTEL .. 'serve-ready.json') or 'null'), j.decode(read(MOTEL .. 'serve-payload.json') or 'null')
    if a and b and a.status == 'passed' and a.run_id == b.run_id then break end
    if t > 1800 then fail('serve not ready after 30 min') end
    ok.time.sleep(10); t = t + 10
  end
  log('serve ready')
end

-- 3 measure
if due('measure') then
  rep.passages = {}; rep.extra = {}
  for _, p in ipairs(B.passages) do
    local grids, segs = {}, {}
    for _, z in ipairs({ 1290, 1220 }) do
      local res = scan({ actors = p.actors, z = z, grid = { box = band(p), z = z, step = 20 } })
      grids[#grids + 1] = res.grid
      for _, row in ipairs(res.actors or {}) do for _, s in ipairs(type(row.walls) == 'table' and row.walls or {}) do segs[#segs + 1] = s end end
    end
    if #segs == 0 then fail(p.id .. ': the scan gave no wall segments of ' .. table.concat(p.actors, '/')) end
    local entry = { id = p.id, actors = p.actors, tried = {}, grids = grids, wall_segments = #segs }
    -- every candidate is judged; the fewest 20 cm columns with something beside the line wins, then the fewest blocks
    -- to cut (an extra block is mostly furniture on the line, which the cut would not remove), then the earlier one
    local best
    for _, y in ipairs(p.ys) do
      local cuts, why, warn = judge(p, y, grids, segs)
      entry.tried[#entry.tried + 1] = { y = y, ok = cuts ~= nil, why = why, walls = cuts and #cuts or nil, beside = warn and #warn or nil, first_beside = warn and warn[1] or nil }
      if cuts and (not best or #warn < best[1] or (#warn == best[1] and #cuts < best[2])) then best = { #warn, #cuts }; entry.y = y; entry.cuts = cuts end
    end
    log(p.id, entry.y and ('line y ' .. entry.y .. ', ' .. #entry.cuts .. ' walls') or 'NO LINE: ' .. j.encode(entry.tried))
    rep.passages[#rep.passages + 1] = entry; save()
  end
  for _, e in ipairs(B.extra or {}) do
    local rows = {}
    for _, z in ipairs(e.z) do rows[#rows + 1] = scan({ z = z, grid = { box = e.box, z = z, step = e.step or 20 } }).grid end
    rep.extra[#rep.extra + 1] = { name = e.name, grids = rows }; save()
    log('scanned ' .. e.name)
  end
  if check_only then log('check only: stop'); release(); return end
end
rep = j.decode(read(REPORT)); rep.batch = batch_id

-- 4 apply: back up the meshes, cut, scan the band again
if due('apply') then
  local todo, actors, cuts = {}, {}, {}
  for _, e in ipairs(rep.passages) do if e.cuts then todo[#todo + 1] = e; for _, a in ipairs(e.actors) do actors[#actors + 1] = a end; for _, c in ipairs(e.cuts) do cuts[#cuts + 1] = c end end end
  if #todo == 0 then fail('no passage has a line') end
  local info = scan({ actors = actors, z = 1290 })
  local backup = PLACES .. 'backup-' .. batch_id .. '/'
  ok.path.mkdir(backup, true)
  for _, row in ipairs(info.actors or {}) do
    for _, m in ipairs({ row.mesh, row.collision }) do
      if type(m) == 'string' then local rel = m:gsub('%..*$', ''):gsub('^/Game/', '')
        for _, ext in ipairs({ '.uasset', '.uexp', '.ubulk' }) do
          local src = 'StreetSocialCity/Content/' .. rel .. ext
          local s = read(src); if s then local dst = backup .. rel:gsub('/', '@') .. ext; if not read(dst) then write(dst, s) end end
        end
      end
    end
  end
  log('meshes backed up in ' .. backup)
  local res = scan({ actors = actors, z = 1260, cuts = cuts, apply = true })
  rep.apply = res; save()
  for _, e in ipairs(todo) do
    local p; for _, q in ipairs(B.passages) do if q.id == e.id then p = q end end
    local g = {}
    for _, z in ipairs({ 1290, 1220 }) do g[#g + 1] = scan({ z = z, grid = { box = band({ x0 = p.x0, x1 = p.x1, ys = { e.y } }), z = z, step = 20 } }).grid end
    local clear = true
    for x = p.x0, p.x1, 20 do for dy = -60, 60, 20 do if blocked(g, x, e.y + dy) then clear = false; e.still = e.still or { x, e.y + dy } end end end
    e.after_clear = clear; log(e.id, clear and 'band clear after the cut' or 'STILL BLOCKED after the cut')
  end
  save()
end

-- 5 probe: walk each cut line
if due('probe') then
  local seeds = {}
  for _, e in ipairs(rep.passages) do
    if e.cuts then
      local p; for _, q in ipairs(B.passages) do if q.id == e.id then p = q end end
      seeds[#seeds + 1] = { name = e.id, from = { p.x0, e.y, 1200 }, to = { p.x1, e.y, 1200 }, box = { p.x0 - 400, e.y - 1200, p.x1 + 400, e.y + 1200 }, cell = 40 }
    end
  end
  write(PLACES .. 'walk-seeds.json', j.encode(seeds))
  job('world_walk_probe', 'Tools/street_city_walk_probe_payload.lua', 30)
  local walked = j.decode(read(PLACES .. 'walk-probe.json'))
  for _, w in ipairs(walked) do for _, e in ipairs(rep.passages) do if e.id == w.name then e.walked = w.reached and w.walked or false end end end
  for _, e in ipairs(rep.passages) do log(e.id, 'walk', tostring(e.walked)) end
  save()
end

-- 6 stream prep, then the editor goes
if due('prep') then
  job('world_stream_prep', 'Tools/street_city_stream_prep_payload.lua', 90)
  log('stream prep done')
end
quit_serve()

-- 7 WP convert + HLOD in 8 groups under the memory watcher
if due('stream') then
  local wlog, stop = PLACES .. 'passage-batch-' .. batch_id .. '-mem.log', PLACES .. 'passage-batch-' .. batch_id .. '.watchstop'
  os.remove(stop)
  ok.proc.spawn({ L, 'Tools/street_city_passage_batch.lua', '--watch', wlog, stop }, { hide = true })
  local code, out = lua({ 'Tools/build_street_city_stream.lua', '--batches', '8' })
  write(stop, '1')
  log('stream exit ' .. code)
  if (read(wlog) or ''):find('KILLED') then fail('the watcher killed the editor (free commit below 4 GB): not migrating') end
  if code ~= 0 then fail('stream: ' .. out:sub(-600)) end
end

-- 8 content migrate (also adds the packages the WP actors reference)
if due('migrate') then
  local code, out = lua({ 'Tools/migrate_street_city_content.lua' })
  log('migrate exit ' .. code .. ' ' .. out:sub(-300):gsub('\n', ' | '))
  if code ~= 0 then fail('migrate') end
end
release()

-- 9 the passages walked through go into the places and the baked roads
if due('roads') then
  local extra = {}
  for _, e in ipairs(rep.passages) do
    if e.cuts and e.walked then
      local p; for _, q in ipairs(B.passages) do if q.id == e.id then p = q end end
      local pts, n = {}, math.max(2, math.ceil((p.x1 - p.x0) / 600))
      for k = 0, n do pts[#pts + 1] = { math.floor(p.x0 + (p.x1 - p.x0) * k / n + 0.5), e.y } end
      extra[#extra + 1] = { id = batch_id .. '_' .. e.id, pts = pts }
    end
  end
  local file = PLACES .. 'passage-batch-' .. batch_id .. '-passages.json'
  write(file, j.encode(extra))
  local code, out = lua({ 'Tools/export_street_city_game_places.lua' }, { OK_EXTRA_PASSAGES = file })
  log('export exit ' .. code)
  for _, e in ipairs(extra) do
    local xs, ys = {}, {}; for _, q in ipairs(e.pts) do xs[#xs + 1] = q[1]; ys[#ys + 1] = q[2] end
    local box = ('%d,%d,%d,%d'):format(math.min(table.unpack(xs)) - 100, math.min(table.unpack(ys)) - 100, math.max(table.unpack(xs)) + 100, math.max(table.unpack(ys)) + 100)
    local c2, o2 = lua({ 'Tools/street_city_roads_add.lua', '--box', box })
    log('roads ' .. e.id .. ' ' .. box .. ': ' .. (o2:match('[^\n]+') or ''))
  end
  rep.passages_file = file; save()
  log('done: copy ' .. file .. ' into PASSAGES of export_street_city_game_places.lua')
end
end
local done, err = xpcall(main, debug.traceback)
if not done then fail(tostring(err)) end
