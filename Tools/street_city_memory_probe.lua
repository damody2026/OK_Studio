-- Peak memory of one StreetSocial run (Docs/STREET_CITY_STREAMING_LOWSPEC_20261114.md): starts the game the way
-- StreetSocial.cmd does, in its own sandbox with no cloud calls, samples the game process every few seconds (private
-- commit, working set, GPU dedicated memory) while it loads, then warps him across the city so the streamed map loads
-- and drops cells, and stops the game it started (only that PID).
--
--   Tools\lua\lua.exe Tools\street_city_memory_probe.lua --tag <name> [--seconds N] [--no-tour] [--no-slot] [-- <launcher args>]
--     --seconds N   sample this long after the map is up before the tour (default 60)
--     --no-tour     no warps (only the start position)
--     --no-slot     the caller holds an Unreal slot already (Tools/unreal_slot.lua)
--     --memreport   "memreport -full" at the end of the idle samples
--     --shots       a screenshot 10 s after each warp (control_shots beside the run's report)
--     --soak MIN    after the tour, MIN minutes of rounds: warp to a far place, then walk to a heroine for 45 s (the
--                   autopilot, /navigate); each round's lowest commit goes to <tag>.json soak_rounds, so memory that
--                   keeps climbing shows as a rising floor (soak_floor_first_gb / soak_floor_last_gb)
--     --segment MIN one test holds the machine at most 20 minutes (user 2026-11-15): the soak runs in segments of MIN
--                   minutes from the claim, load included (default 18); between them the game stops, the slot is
--                   released and claimed again, and the next segment relaunches (rows keep going into the same CSV,
--                   phase load2, load3...). Each segment is a new process, so a rising floor shows within a segment.
--     --exec "A;B"  console commands sent through the control channel once the map is up (before the idle samples),
--                   e.g. "wp.Runtime.OverrideRuntimeSpatialHashLoadingRange -grid=0 -range=12800" (until the map reloads)
--     after --      passed to Tools/run_street_social_development.lua, e.g. -- -CitySource
--
-- Output: Saved/StreetSocial/MemProbe/<tag>.csv (one row per sample) and <tag>.json (peaks).
local ok = require "ok"
local json, path, proc = ok.json, ok.path, ok.proc

local AGENT = "c-lowspec"
local o, launcher_args, i = { seconds = 60, segment = 18 }, {}, 1
while arg[i] do
  local a = arg[i]
  if a == "--" then for j = i + 1, #arg do launcher_args[#launcher_args + 1] = arg[j] end break
  elseif a == "--tag" then i = i + 1; o.tag = arg[i]
  elseif a == "--seconds" then i = i + 1; o.seconds = assert(tonumber(arg[i]), "--seconds N")
  elseif a == "--no-tour" then o.notour = true
  elseif a == "--no-slot" then o.noslot = true
  elseif a == "--exec" then i = i + 1; o.exec = arg[i]
  elseif a == "--memreport" then o.memreport = true
  elseif a == "--shots" then o.shots = true
  elseif a == "--soak" then i = i + 1; o.soak = assert(tonumber(arg[i]), "--soak MINUTES")
  elseif a == "--segment" then i = i + 1; o.segment = assert(tonumber(arg[i]), "--segment MINUTES")
  else error("unknown argument " .. a, 0) end
  i = i + 1
end
assert(o.tag and o.tag:match("^[%w%-_]+$"), "--tag <name> (letters, digits, - and _)")

local root = ok.root
local out_dir = path.join(root, "Saved/StreetSocial/MemProbe")
path.mkdir(out_dir, true)
local sandbox = "MemProbe"
local port_base = 48160
local control = port_base + 10

local function say(s) io.write(s, "\n"); io.flush() end
local function sleep(s) proc.run({ "powershell", "-NoProfile", "-Command", "Start-Sleep -Milliseconds " .. math.floor(s * 1000) }, { hide = true }) end

local function sample(pid)
  local script = ([[
$p = Get-Process -Id %d -ErrorAction SilentlyContinue
if (-not $p) { 'gone'; exit }
$g = 0
try { $c = Get-Counter ('\GPU Process Memory(pid_%d_*)\Dedicated Usage') -ErrorAction Stop; $g = ($c.CounterSamples | Measure-Object CookedValue -Sum).Sum } catch {}
$os = Get-CimInstance Win32_OperatingSystem
'{0} {1} {2} {3} {4} {5}' -f $p.PrivateMemorySize64, $p.WorkingSet64, $p.PeakPagedMemorySize64, $p.PeakWorkingSet64, [int64]$g, ([int64]$os.FreeVirtualMemory * 1024)
]]):format(pid, pid)
  local r = proc.run({ "powershell", "-NoProfile", "-Command", script }, { hide = true, capture = true })
  local s = r.stdout or ""
  if s:match("gone") then return nil end
  local v = {}
  for n in s:gmatch("%-?%d+") do v[#v + 1] = tonumber(n) end
  if #v < 6 then return false end
  return { commit = v[1], ws = v[2], peak_commit = v[3], peak_ws = v[4], gpu = v[5], free_commit = v[6] }
end

local function http(method, route, body)
  local args = { "curl.exe", "-s", "-m", "20", "-X", method, ("http://127.0.0.1:%d%s"):format(control, route) }
  if body then args[#args + 1] = "-H"; args[#args + 1] = "Content-Type: application/json"; args[#args + 1] = "-d"; args[#args + 1] = body end
  local r = proc.run(args, { hide = true, capture = true })
  return r.stdout or ""
end

-- One test holds the machine at most 20 minutes (user 2026-11-15, Tools/unreal_slot.lua): a soak runs in segments of
-- --segment minutes from the claim (load included); between them the game is stopped, the slot released and claimed
-- again (queueing behind whoever waits), and the next segment relaunches and appends to the same CSV.
local slot_held = false
local function claim()
  if o.noslot then return end
  local c = proc.run({ path.join(root, "Tools/lua/lua.exe"), path.join(root, "Tools/unreal_slot.lua"), "claim", AGENT, "memory probe " .. o.tag, "--wait", "--need-gb", "40" })
  if not c.ok then error("could not claim an Unreal slot", 0) end
  slot_held = true
end
local function release()
  if o.noslot or not slot_held then return end
  proc.run({ path.join(root, "Tools/lua/lua.exe"), path.join(root, "Tools/unreal_slot.lua"), "release", AGENT })
  slot_held = false
end

local gb = function(b) return b and b / 1073741824 or 0 end
local rows, peak = {}, { commit = 0, ws = 0, gpu = 0, min_free_commit = math.huge }
local csv = io.open(path.join(out_dir, o.tag .. ".csv"), "wb")
csv:write("t,phase,commit_gb,ws_gb,peak_commit_gb,peak_ws_gb,gpu_dedicated_gb,system_free_commit_gb\n")
local started = os.time()
local pid
local ok_run, err = pcall(function()
  local phase = "load"
  local log
  local function launch()
    local cmd = { path.join(root, "Tools/lua/lua.exe"), path.join(root, "Tools/run_street_social_development.lua"),
      "-Sandbox", sandbox, "-PortBase", tostring(port_base), "-NoCloud", "-Control", "-Window", "1280x720" }
    for _, a in ipairs(launcher_args) do cmd[#cmd + 1] = a end
    say("launch: " .. table.concat(cmd, " "))
    local r = proc.run(cmd, { capture = true })
    io.write(r.stdout or "")
    pid = tonumber((r.stdout or ""):match("game pid (%d+)"))
    if not pid then error("the launcher did not start a game", 0) end
    -- The launcher's last line is its output folder (game.log beside selection.json).
    local output
    for line in (r.stdout or ""):gmatch("[^\r\n]+") do if path.is_file(path.join(line, "selection.json")) then output = line end end
    log = output and path.join(output, "game.log")
    say("game " .. pid .. ", log " .. tostring(log))
  end
  local function record()
    local s = sample(pid)
    if s == nil then error("game " .. pid .. " exited during " .. phase, 0) end
    if not s then return end
    local t = os.time() - started
    csv:write(("%d,%s,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n"):format(t, phase, gb(s.commit), gb(s.ws), gb(s.peak_commit), gb(s.peak_ws), gb(s.gpu), gb(s.free_commit)))
    csv:flush()
    peak.commit = math.max(peak.commit, s.peak_commit, s.commit); peak.ws = math.max(peak.ws, s.peak_ws, s.ws)
    peak.gpu = math.max(peak.gpu, s.gpu); peak.min_free_commit = math.min(peak.min_free_commit, s.free_commit)
    peak[phase] = math.max(peak[phase] or 0, s.commit)
    say(("%4ds %-10s commit %.1f GB (peak %.1f)  ws %.1f GB  gpu %.1f GB  free commit %.0f GB"):format(t, phase, gb(s.commit), gb(s.peak_commit), gb(s.ws), gb(s.gpu), gb(s.free_commit)))
    return s
  end
  -- Loading: until game.log says the map is up and the control channel answers, at most 15 minutes.
  local function wait_loaded()
    local deadline = os.time() + 900
    while os.time() < deadline do
      record()
      local text = log and path.is_file(log) and path.read_text(log) or ""
      if text:find("Load map complete", 1, true) and http("GET", "/health"):match('"ok"%s*:%s*true') then return end
      sleep(2)
    end
  end
  claim()
  local segment_start = os.time()
  launch()
  wait_loaded()
  peak.load_seconds = os.time() - started
  if o.exec then for c in o.exec:gmatch("[^;]+") do say("exec " .. c .. ": " .. http("POST", "/exec", json.encode({ command = c }))) end end
  phase = "idle"
  local idle_end = os.time() + o.seconds
  while os.time() < idle_end do record(); sleep(2) end
  -- --memreport: where the memory is (Saved/Profiling/MemReports under the stage's OpenKoikatsu folder).
  if o.memreport then
    say("memreport: " .. http("POST", "/exec", json.encode({ command = "memreport -full" })))
    -- it writes ~13 MB over several seconds; the game must not be stopped before it is done
    local t_end = os.time() + 30
    while os.time() < t_end do record(); sleep(2) end
  end
  if not o.notour then
    -- Far corners of the city: each warp makes the streamed map load the cells round him and drop the old ones.
    for _, place in ipairs({ "department", "boys_dorm", "skating", "gym", "church", "department" }) do
      phase = "tour:" .. place
      say("warp " .. place .. ": " .. http("POST", "/warp", json.encode({ place = place })))
      local t_end, shot = os.time() + 25, os.time() + 10
      while os.time() < t_end do
        record(); sleep(2)
        if o.shots and shot and os.time() >= shot then say("shot " .. place .. ": " .. http("POST", "/screenshot", "{}")); shot = nil end
      end
    end
  end
  if o.soak then
    local places = { "department", "boys_dorm", "skating", "gym", "church", "cinema", "ramen", "bank" }
    local soak_left, round = math.floor(o.soak * 60), 0
    local segment_limit = math.floor(o.segment * 60)
    peak.soak_rounds = {}
    peak.soak_segments = 1
    while soak_left > 0 do
      -- No room for another round (~70 s) in this segment: stop the game, give the machine back, queue again, relaunch.
      if os.time() - segment_start + 70 > segment_limit then
        http("POST", "/navigate", json.encode({ stop = true }))
        proc.run({ "taskkill", "/PID", tostring(pid), "/T", "/F" }, { hide = true, capture = true })
        pid = nil
        release()
        say(("segment %d done (%.0f min held); %.0f min of soak left, queueing again"):format(peak.soak_segments, (os.time() - segment_start) / 60, soak_left / 60))
        claim()
        segment_start = os.time()
        peak.soak_segments = peak.soak_segments + 1
        phase = ("load%d"):format(peak.soak_segments)
        launch()
        wait_loaded()
      end
      local round_start = os.time()
      round = round + 1
      local place, girl = places[(round - 1) % #places + 1], (round - 1) % 5 + 1
      phase = ("soak%d:%s"):format(round, place)
      say("warp " .. place .. ": " .. http("POST", "/warp", json.encode({ place = place })))
      local floor_before = math.huge
      local t_end = os.time() + 20
      while os.time() < t_end do record(); sleep(2) end
      say("walk to girl " .. girl .. ": " .. http("POST", "/navigate", json.encode({ girl = girl })))
      t_end = os.time() + 45
      while os.time() < t_end do local s = record(); if s then floor_before = math.min(floor_before, s.commit) end; sleep(2) end
      peak.soak_rounds[#peak.soak_rounds + 1] = gb(floor_before)
      say(("round %d floor %.2f GB"):format(round, gb(floor_before)))
      soak_left = soak_left - (os.time() - round_start)
    end
    http("POST", "/navigate", json.encode({ stop = true }))
  end
end)
csv:close()
if pid then proc.run({ "taskkill", "/PID", tostring(pid), "/T", "/F" }, { hide = true, capture = true }) end
release()
local summary = { tag = o.tag, launcher_args = launcher_args, completed = ok_run, error = ok_run and nil or tostring(err),
  peak_commit_gb = gb(peak.commit), peak_working_set_gb = gb(peak.ws), peak_gpu_dedicated_gb = gb(peak.gpu),
  min_system_free_commit_gb = peak.min_free_commit < math.huge and gb(peak.min_free_commit) or nil, load_seconds = peak.load_seconds }
for k, v in pairs(peak) do if type(k) == "string" and (k == "load" or k == "idle" or k:match("^tour:")) then summary["commit_gb_" .. k] = gb(v) end end
if peak.soak_rounds and #peak.soak_rounds > 0 then
  local r = peak.soak_rounds
  summary.soak_rounds = r
  summary.soak_segments = peak.soak_segments
  summary.soak_floor_first_gb, summary.soak_floor_last_gb = r[1], r[#r]
  local hi = 0; for k, v in pairs(peak) do if type(k) == "string" and k:match("^soak") and type(v) == "number" then hi = math.max(hi, v) end end
  summary.soak_peak_commit_gb = gb(hi)
end
path.write_text(path.join(out_dir, o.tag .. ".json"), json.encode(summary, { indent = 2 }))
say(json.encode(summary, { indent = 2 }))
if not ok_run then os.exit(1) end
