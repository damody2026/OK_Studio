-- Peak memory of one StreetSocial run (Docs/STREET_CITY_STREAMING_LOWSPEC_20261114.md): starts the game the way
-- StreetSocial.cmd does, in its own sandbox with no cloud calls, samples the game process every few seconds (private
-- commit, working set, GPU dedicated memory) while it loads, then warps him across the city so the streamed map loads
-- and drops cells, and stops the game it started (only that PID).
--
--   Tools\lua\lua.exe Tools\street_city_memory_probe.lua --tag <name> [--seconds N] [--no-tour] [--no-slot] [-- <launcher args>]
--     --seconds N   sample this long after the map is up before the tour (default 60)
--     --no-tour     no warps (only the start position)
--     --no-slot     the caller holds an Unreal slot already (Tools/unreal_slot.lua)
--     after --      passed to Tools/run_street_social_development.lua, e.g. -- -CitySource
--
-- Output: Saved/StreetSocial/MemProbe/<tag>.csv (one row per sample) and <tag>.json (peaks).
local ok = require "ok"
local json, path, proc = ok.json, ok.path, ok.proc

local AGENT = "c-lowspec"
local o, launcher_args, i = { seconds = 60 }, {}, 1
while arg[i] do
  local a = arg[i]
  if a == "--" then for j = i + 1, #arg do launcher_args[#launcher_args + 1] = arg[j] end break
  elseif a == "--tag" then i = i + 1; o.tag = arg[i]
  elseif a == "--seconds" then i = i + 1; o.seconds = assert(tonumber(arg[i]), "--seconds N")
  elseif a == "--no-tour" then o.notour = true
  elseif a == "--no-slot" then o.noslot = true
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

if not o.noslot then
  local c = proc.run({ path.join(root, "Tools/lua/lua.exe"), path.join(root, "Tools/unreal_slot.lua"), "claim", AGENT, "memory probe " .. o.tag, "--wait", "--need-gb", "40" })
  if not c.ok then error("could not claim an Unreal slot", 0) end
end

local gb = function(b) return b and b / 1073741824 or 0 end
local rows, peak = {}, { commit = 0, ws = 0, gpu = 0, min_free_commit = math.huge }
local csv = io.open(path.join(out_dir, o.tag .. ".csv"), "wb")
csv:write("t,phase,commit_gb,ws_gb,peak_commit_gb,peak_ws_gb,gpu_dedicated_gb,system_free_commit_gb\n")
local started = os.time()
local pid
local ok_run, err = pcall(function()
  local cmd = { path.join(root, "Tools/lua/lua.exe"), path.join(root, "Tools/run_street_social_development.lua"),
    "-Sandbox", sandbox, "-PortBase", tostring(port_base), "-NoCloud", "-Control", "-Window", "1280x720" }
  for _, a in ipairs(launcher_args) do cmd[#cmd + 1] = a end
  say("launch: " .. table.concat(cmd, " "))
  local r = proc.run(cmd, { capture = true })
  io.write(r.stdout or "")
  pid = tonumber((r.stdout or ""):match("game pid (%d+)"))
  if not pid then error("the launcher did not start a game", 0) end
  local phase = "load"
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
  end
  -- Loading: until game.log says the map is up and the control channel answers, at most 15 minutes. The launcher's
  -- last line is its output folder (game.log beside selection.json).
  local output
  for line in (r.stdout or ""):gmatch("[^\r\n]+") do if path.is_file(path.join(line, "selection.json")) then output = line end end
  local log = output and path.join(output, "game.log")
  say("game " .. pid .. ", log " .. tostring(log))
  local deadline = os.time() + 900
  while os.time() < deadline do
    record()
    local text = log and path.is_file(log) and path.read_text(log) or ""
    if text:find("Load map complete", 1, true) and http("GET", "/health"):match('"ok"%s*:%s*true') then break end
    sleep(2)
  end
  peak.load_seconds = os.time() - started
  phase = "idle"
  local idle_end = os.time() + o.seconds
  while os.time() < idle_end do record(); sleep(2) end
  if not o.notour then
    -- Far corners of the city: each warp makes the streamed map load the cells round him and drop the old ones.
    for _, place in ipairs({ "department", "boys_dorm", "skating", "gym", "church", "department" }) do
      phase = "tour:" .. place
      say("warp " .. place .. ": " .. http("POST", "/warp", json.encode({ place = place })))
      local t_end = os.time() + 25
      while os.time() < t_end do record(); sleep(2) end
    end
  end
end)
csv:close()
if pid then proc.run({ "taskkill", "/PID", tostring(pid), "/T", "/F" }, { hide = true, capture = true }) end
if not o.noslot then proc.run({ path.join(root, "Tools/lua/lua.exe"), path.join(root, "Tools/unreal_slot.lua"), "release", AGENT }) end
local summary = { tag = o.tag, launcher_args = launcher_args, completed = ok_run, error = ok_run and nil or tostring(err),
  peak_commit_gb = gb(peak.commit), peak_working_set_gb = gb(peak.ws), peak_gpu_dedicated_gb = gb(peak.gpu),
  min_system_free_commit_gb = peak.min_free_commit < math.huge and gb(peak.min_free_commit) or nil, load_seconds = peak.load_seconds }
for k, v in pairs(peak) do if type(k) == "string" and (k == "load" or k == "idle" or k:match("^tour:")) then summary["commit_gb_" .. k] = gb(v) end end
path.write_text(path.join(out_dir, o.tag .. ".json"), json.encode(summary, { indent = 2 }))
say(json.encode(summary, { indent = 2 }))
if not ok_run then os.exit(1) end
