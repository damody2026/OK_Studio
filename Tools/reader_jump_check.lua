-- The card reader's jump check (「Demo：蹦跳」) over OK cards: each card in a fresh reader of its own, lighting views
-- (原作預設, 無陰影) and, for outfits 1..7, two sets of views a moment apart while the jump plays.
-- What it covers: load + jump. It does not go through "made, settings changed, uploaded again": with the low-memory bug
-- put back (kk.RuntimeTextureDropAtUpload=1) C031 still passed, BulkData 0 (11-18). Texture upload / low-memory changes
-- also need ok.VerifyEyeDull under -OKLowMemory (Docs/READER_LOWMEM_FULLRUN_20261118.md).
--
--   Tools\lua\lua.exe Tools\reader_jump_check.lua --out FILE (--cards C025,C026 | --list FILE --from N --to M)
--       [--lane NAME] [--dir CARD_DIR] [--images DIR] [--polite] [--mcp EXE] [--minutes N] [--extra "-OKLowMemory"]
--
--   --cards     card names (C025 -> <dir>/C025.png), or --list (one name per line) with --from/--to (0-based, to exclusive)
--   --dir       default Content/CharacterCards/CrowdAPNG
--   --lane      slot name suffix and reader marker (f-yvonne-<lane>, -OKLane=<lane>-<card>-<pid>); default a
--   --images    copy the view images there (default: left where the reader wrote them)
--   --polite    before each segment wait while another group (not f-yvonne*) holds or waits for an Unreal slot
--   --fair      after each segment wait until every agent queued at the release has had the slot once
--   --minutes   one slot claim runs cards while the next one still fits in N minutes, from the average card so far
--               (default 20, the slot rule's cap); then the slot is given back and claimed again (queueing behind others)
--   --mcp       ok-game-mcp.exe (default Tools/ok-game-mcp/target/release/ok-game-mcp.exe)
--   --extra     more reader arguments, space separated (e.g. -OKLowMemory: the 16 GB laptop path, where textures drop
--               their CPU pixels after upload; RESULT says lowmem=on|off as the reader's log decided it)
--   With --images every view is also checked (all black, all white, or no character: a PNG of the bare background),
--   and the log is counted for "Attempting to load a BulkData object that cannot be loaded from disk" (bulk=):
--   either one makes the card a card_fail.
--
-- Readers start with -LiveCoding=false (UE5.8 LiveCodingModule.cpp reads `-LiveCoding=`, not -NoLiveCoding): no
-- LiveCodingConsole, so another group's editor build is not refused by the Live Coding mutex. That is all it solves: a
-- reader is UnrealEditor with the editor DLLs (UnrealEditor-OpenKoikatsu.dll ..) loaded, and Windows locks loaded DLLs.
--   builds that can run beside a full run: the Rust lib, the game target (OpenKoikatsu), and editor builds that relink
--     none of the editor modules a reader loads;
--   builds that need the run stopped (its slots given back): any that relinks an editor module the reader loaded (a C++
--     change to it), else LNK1104.
--
-- The reader is found by the marker on its own command line, never as "the newest reader", and every call names it
-- (OK_GAME_PID): another session's reader started at the same moment is never taken (C025, 2026-11-16).
--
-- A refusal is read by its code (OKCharacterMCP Finish, ok-game-mcp: "<code>: <message>"):
--   busy, not_ready         the reader is loading, preparing or still starting: backed off and retried (1, 2, 4.. s, at
--                           most 8 tries), counted as the card's `retries`, never a failure of the card;
--   no_reader, ambiguous_target
--                           the environment is wrong (the reader died, or a call went to no picked game): the run stops
--                           at once, says so, and exits 2;
--   anything else           a real refusal of that step.
-- Each card ends with one line `<card> RESULT <pass|card_fail|check|env|env_abort> retries=N ...`: card_fail is the card
-- itself (load refused or failed, an assertion or a failed load in its log, an outfit that cannot be chosen); check is
-- a step that did not take (the jump did not start, a control did not set) with no failure of the card; env is a reader
-- that never got ready for the load (still busy / not ready after every retry; C046 11-18 hung at "Waiting for
-- ZenServer to be ready"), and the card is tried once more in a fresh reader; env_abort is not the card and stops the run.
-- The old full runs wrote a busy reader as LOADFAIL (C025, a misjudgement).

local function sleep(s) os.execute(("ping -n %d 127.0.0.1 >nul"):format(math.max(1, math.floor(s + 0.5)) + 1)) end

local args = {}
do
  local i = 1
  while arg[i] do
    local k = arg[i]
    if k == "--polite" then args.polite = true; i = i + 1
    elseif k == "--fair" then args.fair = true; i = i + 1
    elseif k:sub(1, 2) == "--" then args[k:sub(3)] = arg[i + 1]; i = i + 2
    else error("unexpected argument " .. k) end
  end
end
local function usage(msg) io.stderr:write(msg .. "\n(see the top of Tools/reader_jump_check.lua)\n"); os.exit(1) end
if not args.out then usage("--out is required") end
local lane = args.lane or "a"
local dir = (args.dir or "Content/CharacterCards/CrowdAPNG"):gsub("\\", "/")
local mcp = args.mcp or "Tools/ok-game-mcp/target/release/ok-game-mcp.exe"
local minutes = tonumber(args.minutes or "20")
local root = (io.popen("cd"):read("l") or "."):gsub("\\", "/")
if not dir:match("^%a:") then dir = root .. "/" .. dir end

local cards = {}
if args.cards then
  for c in args.cards:gmatch("[^,]+") do cards[#cards + 1] = c end
elseif args.list then
  local all = {}
  for l in io.lines(args.list) do l = l:gsub("%s+$", ""); if l ~= "" then all[#all + 1] = l end end
  local from, to = tonumber(args.from or "0"), tonumber(args.to or tostring(#all))
  for i = from + 1, math.min(to, #all) do cards[#cards + 1] = all[i] end
else usage("--cards or --list is required") end

local out = assert(io.open(args.out, "ab"))
local function emit(line) out:write(line, "\n"); out:flush(); print(line) end

-- JSON text for a command line: non-ASCII as \u escapes (the console code page would mangle them), quotes escaped.
local function json_arg(s)
  local t, i = {}, 1
  while i <= #s do
    local c = s:byte(i)
    if c < 0x80 then t[#t + 1] = string.char(c); i = i + 1
    else
      local n = c >= 0xF0 and 4 or c >= 0xE0 and 3 or 2
      local cp = c & (n == 2 and 0x1F or n == 3 and 0x0F or 0x07)
      for k = 1, n - 1 do cp = (cp << 6) | (s:byte(i + k) & 0x3F) end
      if cp >= 0x10000 then cp = cp - 0x10000; t[#t + 1] = ("\\u%04x\\u%04x"):format(0xD800 | (cp >> 10), 0xDC00 | (cp & 0x3FF))
      else t[#t + 1] = ("\\u%04x"):format(cp) end
      i = i + n
    end
  end
  return '"' .. table.concat(t):gsub('"', '\\"') .. '"'
end
local function q(s) return '"' .. s:gsub('"', '\\"') .. '"' end

local pid -- the reader of the current card
local retries = 0

-- One call; the output and the refusal code ("busy", "not_ready", ..; nil when it answered).
local function call_once(tool, json)
  local p = io.popen(("set OK_GAME_PID=%s&& %s call %s %s 2>&1"):format(pid or "", q(mcp), tool, json_arg(json)))
  local text = p:read("a"); p:close()
  local code = text:match("^Error: ([%w_]+):") or text:match("\nError: ([%w_]+):")
  if not code and text:match("^Error:") then code = "refused" end
  return text, code
end

local EnvAbort = {}
local function alive(p)
  local h = io.popen(('tasklist /FI "PID eq %s" /NH 2>nul'):format(p)); local t = h:read("a"); h:close()
  return t:find(" " .. p .. " ", 1, true) ~= nil
end
-- A call: busy/not_ready backed off and retried; no_reader/ambiguous_target abort the run, as does a reader that died
-- (its pid then answers not_ready: not a busy reader).
local function call(tool, json)
  local wait = 1
  for _ = 1, 8 do
    local text, code = call_once(tool, json)
    if code == "not_ready" and pid and not alive(pid) then error({ EnvAbort, "the reader (pid " .. pid .. ") exited" }) end
    if code == "busy" or code == "not_ready" then retries = retries + 1; sleep(wait); wait = math.min(wait * 2, 16)
    elseif code == "no_reader" or code == "ambiguous_target" then error({ EnvAbort, code .. ": " .. (text:match("Error: (.-)%s*$") or text) })
    else return text, code end
  end
  return "still busy after 8 tries", "busy"
end

local function state() return (call("reader_call", '{"action":"state"}')) end
local function idle() for _ = 1, 40 do if state():find('"busy": false', 1, true) then return true end sleep(2) end return false end
local function set(key, value)
  for _ = 1, 4 do
    local text, code = call("reader_call", ('{"action":"control_set","key":"%s","value":%s}'):format(key, value))
    if not code and text:find('"revision"', 1, true) then return nil end
    -- (only a stale session/revision is worth another try; a refused value says why, e.g. "Value absent from choices")
    if code ~= "stale" then return (text:gsub("%s+", " "):sub(1, 100)) end
    sleep(1.5)
  end
  return "did not set " .. key .. " (stale 4 times)"
end

local images
-- A view image that shows no character (the low-memory black LUT, 2026-11-17, covered the whole 3D view): a view all
-- black or all white by image_stats (whole image), or a PNG so small it can only be the bare grey background (a view
-- with a character is hundreds of KB; the background alone compresses to a few KB). nil when the image looks fine.
local imgbad = {}
local function image_bad(path)
  local f = io.open(path, "rb"); if not f then return "missing" end
  local size = f:seek("end"); f:close()
  if size < 150000 then return ("tiny%dB"):format(size) end
  local text = call_once("image_stats", ('{"file":"%s","region":[0,0,1,1]}'):format(path))
  local black, white = tonumber(text:match('"black"%s*:%s*([%d.]+)')), tonumber(text:match('"white"%s*:%s*([%d.]+)'))
  local mean = tonumber(text:match('"mean"%s*:%s*([%d.]+)'))
  if not mean then return nil end
  if black > 0.5 or mean < 25 then return ("black%.2f"):format(black) end
  if white > 0.5 or mean > 235 then return ("white%.2f"):format(white) end
  return nil
end
local function views()
  call("reader_call", '{"action":"camera","focus":[0,-14.6,88],"distance":330,"yaw":0,"pitch":0}')
  local text = call("reader_call", '{"action":"views","timeout_s":120}')
  local names = {}
  for n in text:gmatch('"image"%s*:%s*"[^"]-([%w_]+%.png)"') do names[#names + 1] = n end
  if args.images then
    local from = root .. "/Saved/CharacterMCP/instances/" .. pid .. "/images/"
    if not io.open(from .. (names[1] or "-"), "rb") then from = root .. "/Saved/CharacterMCP/images/" end
    for _, n in ipairs(names) do
      local f = io.open(from .. n, "rb")
      if f then local b = f:read("a"); f:close(); local g = io.open(args.images .. "/" .. n, "wb"); if g then g:write(b); g:close() end end
    end
    for _, n in ipairs(names) do
      local bad = image_bad(args.images .. "/" .. n)
      if bad then imgbad[#imgbad + 1] = bad .. "@" .. n end
    end
  end
  return table.concat(names, ",")
end

local function clip()
  for _ = 1, 5 do
    set("control.GameClipCombo", '"Demo：蹦跳"'); sleep(1)
    if state():find("正在播放：Demo：蹦跳", 1, true) then return "" end
  end
  return "NOCLIP"
end

local function ps(cmd)
  local p = io.popen('powershell -NoProfile -Command "' .. cmd .. '"')
  local text = p:read("a"); p:close(); return text
end
local function find_reader(tag)
  local line = ps(("Get-CimInstance Win32_Process -Filter 'Name=''UnrealEditor.exe''' | Where-Object { $_.CommandLine -like '*%s *' -or $_.CommandLine -like '*%s' } | ForEach-Object { [string]$_.ProcessId + ' ' + $_.CommandLine }"):format(tag, tag))
  local found, log = line:match("^(%d+) "), line:match("%-abslog=(%S+)")
  return found, log
end
local function kill(p) if p then os.execute(("taskkill /PID %s /F >nul 2>&1"):format(p)); sleep(3) end end
local function count(log, needle)
  local f = log and io.open(log, "rb"); if not f then return "?" end
  local text = f:read("a"); f:close()
  local n = 0; for _ in text:gmatch(needle) do n = n + 1 end
  return n, text
end

local function slot(cmd, reason)
  return os.execute(("Tools\\lua\\lua.exe Tools\\unreal_slot.lua %s f-yvonne-%s%s"):format(cmd, lane, reason and (" " .. q(reason) .. " --wait") or ""))
end
local function others_waiting()
  local p = io.popen("Tools\\lua\\lua.exe Tools\\unreal_slot.lua status"); local st = p:read("a"); p:close()
  for holder in st:gmatch("slot%d+: (%S+)") do if holder ~= "(free)" and not holder:match("^f%-yvonne") then return true end end
  local queue = st:match("queue:([^\n]*)") or ""
  for item in queue:gmatch("[^,]+") do
    local name = item:match("^%s*(%S+)")
    if name and not item:find("stale", 1, true) and not name:match("^f%-yvonne") then return true end
  end
  return false
end

local function check_card(c)
  retries = 0
  local tag = ("-OKLane=%s-%s-%d"):format(lane, c, math.random(10000, 99999))
  -- -LiveCoding=false: no LiveCodingConsole (LiveCodingModule.cpp reads `-LiveCoding=`), whose mutex made every other
  -- group's editor build fail ("Unable to build while Live Coding is active") while a full run was going.
  imgbad = {}
  local extra = ""
  for a in (args.extra or ""):gmatch("%S+") do extra = extra .. ",'" .. a .. "'" end
  ps(("Start-Process -FilePath '%s\\CardReaderDevelopment.cmd' -ArgumentList '-NoBuild','--','-NoCloud','-LiveCoding=false','%s'%s -WorkingDirectory '%s'"):format(root:gsub("/", "\\"), tag, extra, root:gsub("/", "\\")))
  local log
  pid = nil
  for _ = 1, 90 do
    sleep(5)
    pid, log = find_reader(tag)
    if pid and select(2, call_once("reader_call", '{"action":"state"}')) == nil then break end
  end
  if not pid then error({ EnvAbort, "reader " .. tag .. " never came up" }) end
  sleep(10)
  local fail, note = nil, {}
  local text, code = call("reader_call", ('{"action":"load","path":"%s/%s.png","timeout_s":240}'):format(dir, c))
  if code or not text:find(c .. ".png", 1, true) then
    emit(("%s LOAD %s"):format(c, (text:gsub("%s+", " "):sub(1, 150))))
    -- still busy / not ready after every retry: the reader never got ready (C046 11-18: it hung at "Waiting for
    -- ZenServer to be ready" during start-up), not the card. Written as env; the run tries the card once more.
    fail = (code == "busy" or code == "not_ready") and "env" or "card_fail"
  else
    idle()
    set("control.LightingPresetCombo", '"原作預設"'); sleep(2); local lit = views()
    set("control.LightingPresetCombo", '"無陰影（平光）"'); sleep(2); local flat = views()
    set("control.LightingPresetCombo", '"原作預設"'); sleep(1)
    set("control.LightingShadeSlider", "0"); sleep(1)
    local _, logtext = count(log, "x")
    local scaled = 0
    for n in (logtext or ""):gmatch("reader lighting[^\n]-scaled=(%d+)") do scaled = math.max(scaled, tonumber(n)) end
    set("control.LightingShadeSlider", "1")
    emit(("%s LIGHT scaled=%d lit=%s flat=%s"):format(c, scaled, lit, flat))
    for o = 1, 7 do
      local e = set("control.OutfitCombo", ('"服裝 %d"'):format(o))
      -- (a card saves fewer than 7 outfits: the combo has no "服裝 o"; the old runs wrote C033 O5 as a failure)
      if e and o > 1 and e:find("Value absent from choices", 1, true) then emit(("%s O%d none (the card has %d outfits)"):format(c, o, o - 1)); break end
      if e then emit(("%s O%d NOOUTFIT %s"):format(c, o, e)); fail = fail or "card_fail"; break end
      sleep(1); idle()
      local cf = clip(); if cf ~= "" then note[#note + 1] = ("O%d %s"):format(o, cf) end
      sleep(1); local a = views(); sleep(1.5); local b = views()
      emit(("%s O%d %s a=%s b=%s"):format(c, o, cf, a, b))
    end
  end
  local asserts = count(log, "Assertion failed")
  local loadfails = count(log, "load3d result ok=0")
  -- a texture whose CPU pixels were dropped after upload (low-memory mode) and then asked for again
  local bulk = count(log, "Attempting to load a BulkData object that cannot be loaded from disk")
  local _, logtext = count(log, "x")
  local lowmem = (logtext or ""):match("Runtime low%-memory mode (%a+)") or "?"
  if asserts ~= 0 or loadfails ~= 0 or bulk ~= 0 or #imgbad > 0 then fail = "card_fail" end
  local result = fail or (#note > 0 and "check" or "pass")
  emit(("%s RESULT %s retries=%d assert=%s loadfail=%s bulk=%s lowmem=%s %s%slog=%s pid=%s"):format(c, result, retries,
    asserts, loadfails, bulk, lowmem, #imgbad > 0 and ("img=" .. table.concat(imgbad, ";") .. " ") or "",
    #note > 0 and (table.concat(note, ";") .. " ") or "", log or "unknown", pid))
  kill(pid); pid = nil
  return result
end

math.randomseed(os.time())
local status = 0
local i, per_card, done = 1, 0, 0
while i <= #cards do
  if args.polite then while others_waiting() do sleep(30) end end
  slot("claim", ("jump check from %s (%d cards left)"):format(cards[i], #cards - i + 1))
  local start = os.time()
  local ok, err = pcall(function()
    repeat
      local t = os.time()
      local c = cards[i]; i = i + 1 -- (a card that aborts is not retried: the run stops there)
      -- a reader that never got ready (env): the same card once more in a fresh reader
      if check_card(c) == "env" then emit(("%s RETRY (the reader never got ready)"):format(c)); check_card(c) end
      done = done + 1; per_card = per_card + (os.time() - t)
      -- another card only if it still ends inside the claim (the average so far, plus a minute)
    until i > #cards or os.time() - start + per_card / done + 60 > minutes * 60
  end)
  if not ok then
    kill(pid)
    slot("release")
    if type(err) == "table" and err[1] == EnvAbort then
      emit(("RUN env_abort at %s: %s (not a card failure; fix the environment and rerun from it)"):format(cards[i - 1], err[2]))
      status = 2
    else emit(("RUN error at %s: %s"):format(cards[i - 1], tostring(err))); status = 1 end
    break
  end
  slot("release")
  -- --fair: the agents queued when the slot went back each get it once before the next claim. f-yvonne ranks first in
  -- unreal_slot.lua, so a run that claims again at once keeps the others waiting for as long as it runs (11-18: e-120fps
  -- and e-fork-2 waited 35 minutes while two agents ran segment after segment). Waits until none of them is still
  -- queued (each has claimed), at most an hour.
  if args.fair and i <= #cards then
    local function queued_others()
      local p = io.popen("Tools\\lua\\lua.exe Tools\\unreal_slot.lua status"); local st = p:read("a"); p:close()
      local q, set = st:match("queue:([^\n]*)") or "", {}
      for item in q:gmatch("[^,]+") do
        local name = item:match("^%s*(%S+)")
        if name and not item:find("stale", 1, true) and not name:match("^f%-yvonne") then set[name] = true end
      end
      return set
    end
    local before = queued_others()
    for _ = 1, 120 do
      local now, left = queued_others(), false
      for name in pairs(before) do if now[name] then left = true end end
      if not left then break end
      sleep(30)
    end
  end
end
out:close()
os.exit(status)
