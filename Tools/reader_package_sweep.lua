-- Every card once in a **package's** card reader, with a view of each: the check a package has to pass before it goes
-- out ("打包產物一定要從包裡實際開一張卡再交出去", Docs/ERROR_LOG.md 2026-11-17), including the low-memory path a
-- 16 GB / 8 GB-VRAM machine takes by itself (2026-11-18: the whole 3D view was black there and no card failed to open).
--
--   Tools\lua\lua.exe Tools\reader_package_sweep.lua --package DIR --cards DIR --images DIR --out FILE
--       [--extra "-OKLowMemory"] [--lane a] [--minutes 20] [--only NAME,NAME] [--noslot 1]
--
--   --package   the unpacked package (holds PACKAGE.json, Tools\run_card_reader_development.lua and a stage)
--   --cards     a folder of cards; every *.png in it is opened, in name order (--only picks some by file name)
--   --images    where the views are copied, one `<card>-<view>.png` a card
--   --extra     passthrough reader arguments (after `--`), e.g. `-OKLowMemory`
--   --out       the result file, appended: one `<card> RESULT <pass|fail|check> ...` line a card, then a SUMMARY line
--
-- Unlike `reader_jump_check.lua` this is **one reader for the whole sweep** (a card is `load`ed into it) and takes one
-- set of views a card, so 30 cards fit in a slot claim. It also finds a **packaged** reader, which the jump check
-- cannot: in a package the reader is the staged `OpenKoikatsu.exe`, not `UnrealEditor.exe`.
--
-- A card is `fail` when the reader refuses or fails to load it, when its log gained a failure line while it loaded, or
-- when every view of it looks empty (all black, all white, or a PNG too small to hold a character). A missing accessory
-- or hair is **not** a failure: a card can only show what was sealed into it, and the user's standard (2026-11-18) is
-- that the body must show while a missing part simply does not. `check` is a step that did not take, not the card.
--
-- The slot rule applies (one claim runs at most --minutes): C:\portable\OpenKoikatsu\Tools\unreal_slot.lua, agent from
-- --lane (e-cardload-<lane>). The reader is stopped at the end and the slot given back, always.

local function sleep(s) os.execute(("ping -n %d 127.0.0.1 >nul"):format(math.max(1, math.floor(s + 0.5)) + 1)) end

local args = {}
do
  local i = 1
  while arg[i] do
    local k = arg[i]
    if k:sub(1, 2) == "--" then args[k:sub(3)] = arg[i + 1]; i = i + 2
    else error("unexpected argument " .. k) end
  end
end
local function usage(m) io.stderr:write(m .. "\n(see the top of Tools/reader_package_sweep.lua)\n"); os.exit(1) end
for _, k in ipairs({ "package", "cards", "images", "out" }) do if not args[k] then usage("--" .. k .. " is required") end end
local pkg = args.package:gsub("\\", "/"):gsub("/$", "")
local cards_dir = args.cards:gsub("\\", "/"):gsub("/$", "")
local images = args.images:gsub("\\", "/"):gsub("/$", "")
local lane = args.lane or "a"
local minutes = tonumber(args.minutes or "20")
local mcp = pkg .. "/Tools/ok-game-mcp/target/release/ok-game-mcp.exe"
local ARBITER = "C:/portable/OpenKoikatsu/Tools/unreal_slot.lua"
local AGENT = "e-cardload-" .. lane

local function ps(cmd)
  local p = io.popen('powershell -NoProfile -Command "' .. cmd:gsub('"', '\\"') .. '"')
  local t = p:read("a"); p:close(); return t or ""
end
local function dir_list(d, pattern)
  local out, p = {}, io.popen(('dir /b /a-d "%s" 2>nul'):format(d:gsub("/", "\\")))
  for l in p:lines() do if l:lower():match(pattern) then out[#out + 1] = l end end
  p:close(); table.sort(out); return out
end

local only = {}
if args.only then for n in args.only:gmatch("[^,]+") do only[n] = true end end
local cards = {}
for _, n in ipairs(dir_list(cards_dir, "%.png$")) do if not args.only or only[n] then cards[#cards + 1] = n end end
if #cards == 0 then usage("no cards in " .. cards_dir) end

os.execute(('if not exist "%s" mkdir "%s"'):format(images:gsub("/", "\\"), images:gsub("/", "\\")))
local out = assert(io.open(args.out, "ab"))
local function emit(line) out:write(line, "\n"); out:flush(); print(line) end

-- JSON text for a command line: non-ASCII as \u escapes (the console code page mangles them), quotes escaped.
local function json_arg(s)
  local t, i = {}, 1
  while i <= #s do
    local c = s:byte(i)
    if c < 0x80 then t[#t + 1] = string.char(c); i = i + 1
    else
      local n = c >= 0xF0 and 4 or c >= 0xE0 and 3 or 2
      local cp = c & (n == 2 and 0x1F or n == 3 and 0x0F or 0x07)
      for k = 1, n - 1 do cp = (cp << 6) | (s:byte(i + k) & 0x3F) end
      if cp >= 0x10000 then cp = cp - 0x10000
        t[#t + 1] = ("\\u%04x\\u%04x"):format(0xD800 | (cp >> 10), 0xDC00 | (cp & 0x3FF))
      else t[#t + 1] = ("\\u%04x"):format(cp) end
      i = i + n
    end
  end
  return '"' .. (table.concat(t):gsub('"', '\\"')) .. '"'
end

local pid
local function call_once(tool, json)
  local p = io.popen(("set OK_ROOT=%s&& set OK_GAME_PID=%s&& %s call %s %s 2>&1")
    :format(pkg:gsub("/", "\\"), pid or "", '"' .. mcp:gsub("/", "\\") .. '"', tool, json_arg(json)))
  local text = p:read("a"); p:close()
  local code = text:match("^Error: ([%w_]+):") or text:match("\nError: ([%w_]+):")
  if not code and text:match("^Error:") then code = "refused" end
  return text, code
end
-- busy/not_ready is the reader still working, not a failure of the card: backed off and retried.
local function call(tool, json, tries)
  local wait = 1
  for _ = 1, tries or 8 do
    local text, code = call_once(tool, json)
    if code == "busy" or code == "not_ready" then sleep(wait); wait = math.min(wait * 2, 16)
    else return text, code end
  end
  return "still busy", "busy"
end

local function alive(p)
  if not p then return false end
  local h = io.popen(('tasklist /FI "PID eq %s" /NH 2>nul'):format(p)); local t = h:read("a"); h:close()
  return t:find(" " .. p .. " ", 1, true) ~= nil
end

-- A view that shows no character: all black, all white, or a PNG so small it can only be the bare background.
local function image_bad(path)
  local f = io.open(path, "rb"); if not f then return "missing" end
  local size = f:seek("end"); f:close()
  if size < 150000 then return ("tiny%dB"):format(size) end
  local text = call_once("image_stats", ('{"file":"%s","region":[0,0,1,1]}'):format(path))
  local black = tonumber(text:match('"black"%s*:%s*([%d.]+)'))
  local white = tonumber(text:match('"white"%s*:%s*([%d.]+)'))
  local mean = tonumber(text:match('"mean"%s*:%s*([%d.]+)'))
  if not mean then return nil end
  -- Not the black **fraction**: the front view's background is black, so a perfectly good character sits at 0.6-0.87
  -- of it (2026-11-18). What says "no character here" is the whole frame being one shade.
  if mean < 10 then return ("black%.2f"):format(black or 0) end
  if mean > 245 then return ("white%.2f"):format(white or 0) end
  return nil
end

local function slot(cmd, what, flags)
  -- The arbiter's own order: <cmd> <agent> "<what for>" [--wait]. cmd.exe eats the outer quotes of a line that starts
  -- with one, so the whole command goes inside one more pair ("" .. .. "") instead of quoting the exe by itself.
  local c = ('"C:\\portable\\OpenKoikatsu\\Tools\\lua\\lua.exe" "%s" %s %s%s%s'):format(ARBITER, cmd, AGENT,
    what and (' "' .. what .. '"') or "", flags and (" " .. flags) or "")
  return os.execute('cmd /c "' .. c .. '"')
end

-- The reader: the package's own launcher, with the cards folder and the extra arguments, marked so it is found by its
-- own command line (never "the newest reader": another group's may start at the same moment).
local marker = ("sweep-%s-%d"):format(lane, os.time() % 100000)
local log
local function start_reader()
  local extra = args.extra and (" -- -OKLane=" .. marker .. " " .. args.extra) or (" -- -OKLane=" .. marker)
  local cmd = ('start "" /min "%s\\Tools\\lua\\lua.exe" "%s\\Tools\\run_card_reader_development.lua" -CardDirectory "%s"%s')
    :format(pkg:gsub("/", "\\"), pkg:gsub("/", "\\"), cards_dir:gsub("/", "\\"), extra)
  os.execute('cmd /c "' .. cmd .. '"')
  for _ = 1, 60 do
    sleep(5)
    local line = ps(("Get-CimInstance Win32_Process -Filter \"Name='OpenKoikatsu.exe'\" | Where-Object { $_.CommandLine -like '*%s*' } | ForEach-Object { [string]$_.ProcessId + ' ' + $_.CommandLine }"):format(marker))
    local found = line:match("^(%d+) ")
    if found then return found, line:match("%-abslog=(%S+)") end
  end
  return nil
end

local function log_text()
  local f = log and io.open((log:gsub("\\", "/")), "rb")
  if not f then return "" end
  local t = f:read("a"); f:close(); return t
end

local what = ("package card sweep (%d cards%s)"):format(#cards, args.extra and (", " .. args.extra) or "")
if args.noslot ~= "1" and slot("claim", what) ~= true then
  -- claim exits 2 while queued; wait for it the way the slot tool means it to be waited for. A waiter that is alive is
  -- not a waiter that works (2026-11-18: one refreshed its queue entry for 20 minutes beside a free slot and never
  -- took it), so a wait that long is treated as the waiter being broken: say so and claim once more by hand.
  local got = slot("claim", what, "--wait") == true
  if not got then
    emit("# the waiter came back without a slot; claiming once more (a wait that long means the waiter is broken)")
    got = slot("claim", what) == true
  end
  if not got then emit("SUMMARY env_abort could not claim a slot"); os.exit(2) end
end

-- The slot cap counts from **here**, not from before the wait: the first run of this spent its whole 20 minutes
-- queueing and then stopped "after 0 cards".
local started = os.time()
pid, log = start_reader()
if not pid then
  slot("release")
  emit("SUMMARY env_abort the packaged reader did not start (marker " .. marker .. ")")
  os.exit(2)
end
emit(("# reader pid=%s log=%s marker=%s extra=%s"):format(pid, tostring(log), marker, tostring(args.extra)))

local fails, checks = 0, 0
local seen = #log_text()
for i, name in ipairs(cards) do
  if not alive(pid) then emit(("%s RESULT check reader exited"):format(name)); checks = checks + 1; break end
  if os.time() - started > minutes * 60 then emit(("# stopping at the %d-minute slot cap after %d cards"):format(minutes, i - 1)); break end
  local text, code = call("reader_call", ('{"action":"load","path":"%s/%s","timeout_s":300}'):format(cards_dir, name), 10)
  if code then
    emit(("%s RESULT fail load refused: %s"):format(name, (text:gsub("%s+", " "):sub(1, 160))))
    fails = fails + 1
  else
    sleep(2)
    -- The reader's own framing by default. A fixed focus/distance is tuned for one height and cut the head off a
    -- taller card (2026-11-18, kks_Saria), which is exactly what these shots are supposed to show.
    if args.camera then call("reader_call", args.camera) end
    local vtext, vcode = call("reader_call", '{"action":"views","timeout_s":180}')
    if vcode then
      emit(("%s RESULT check views refused: %s"):format(name, (vtext:gsub("%s+", " "):sub(1, 120))))
      checks = checks + 1
    else
      local names = {}
      for n in vtext:gmatch('"image"%s*:%s*"[^"]-([%w_]+%.png)"') do names[#names + 1] = n end
      local from = pkg .. "/Saved/CharacterMCP/instances/" .. pid .. "/images/"
      if not io.open(from .. (names[1] or "-"), "rb") then from = pkg .. "/Saved/CharacterMCP/images/" end
      local bad, kept = {}, {}
      for _, n in ipairs(names) do
        local f = io.open(from .. n, "rb")
        if f then
          local b = f:read("a"); f:close()
          local to = ("%s/%s-%s"):format(images, name:gsub("%.png$", ""), n)
          local g = io.open(to, "wb")
          if g then g:write(b); g:close(); kept[#kept + 1] = to
            local why = image_bad(to); if why then bad[#bad + 1] = why .. "@" .. n end
          end
        end
      end
      -- New failure lines in the reader's log while this card loaded.
      local t = log_text(); local fresh = t:sub(seen + 1); seen = #t
      local logbad = {}
      for _, needle in ipairs({ "Missing shader", "Default Material", "Fatal error",
        "Attempting to load a BulkData object that cannot be loaded from disk" }) do
        local n = 0; for _ in fresh:gmatch(needle:gsub("%p", "%%%0")) do n = n + 1 end
        if n > 0 then logbad[#logbad + 1] = ("%s x%d"):format(needle, n) end
      end
      -- `the OK card lacks` is only a failure of the card when the card's **own open** returned it (`ok=0`). The same
      -- line on the clothing warm load (a clothing variant of it) leaves the card open and shown: that is a gap to
      -- list, not a card that failed (2026-11-18: march_7th and qiu_wuji opened fine and were called failures).
      if fresh:find("OK load3d result ok=0", 1, true) then
        logbad[#logbad + 1] = "load3d ok=0: " .. ((fresh:match("OK load3d result ok=0[^\r\n]*") or ""):sub(-150))
      end
      local gap = fresh:match("the OK card lacks[^\r\n]*")
      local empty = #kept > 0 and #bad == #kept
      if empty or #logbad > 0 then
        emit(("%s RESULT fail views=%d %s%s"):format(name, #kept, table.concat(bad, " "),
          #logbad > 0 and (" log: " .. table.concat(logbad, "; ")) or ""))
        fails = fails + 1
      else
        emit(("%s RESULT pass views=%d%s%s"):format(name, #kept,
          #bad > 0 and (" (some views look empty: " .. table.concat(bad, " ") .. ")") or "",
          gap and (" GAP " .. gap:gsub(".*completes it%): ", ""):sub(1, 120)) or ""))
      end
    end
  end
end

-- The hard standard for "no game needed": the reader's log must not name a game tree (ERROR_LOG 2026-11-17). Card
-- paths are left out of the count: a card's own file name may contain the game's name.
local t = log_text()
local game_lines = 0
for line in t:gmatch("[^\r\n]+") do
  if line:match("KoikatuSunshine") or line:match("Koikatsu Sunshine") then
    if not line:match("[Cc]ard") and not line:match("%.png") then game_lines = game_lines + 1; emit("# GAMEROOT " .. line:sub(1, 200)) end
  end
end
local function count(needle) local n = 0; for _ in t:gmatch(needle:gsub("%p", "%%%0")) do n = n + 1 end; return n end
emit(("SUMMARY cards=%d fail=%d check=%d game_root_lines=%d lacks=%d open_failed=%d missing_shader=%d default_material=%d fatal=%d log=%s")
  :format(#cards, fails, checks, game_lines, count("the OK card lacks"), count("OK load3d result ok=0"),
    count("Missing shader"), count("Default Material"), count("Fatal error"), tostring(log)))

if alive(pid) then
  -- CIM Terminate first: taskkill has reported success on a process that kept running (2026-11-18).
  ps(('Get-CimInstance Win32_Process -Filter \'ProcessId=%s\' | Invoke-CimMethod -MethodName Terminate | Out-Null'):format(pid))
  sleep(3)
  if alive(pid) then os.execute(("taskkill /PID %s /F >nul 2>&1"):format(pid)); sleep(2) end
end
if args.noslot ~= "1" then slot("release") end
os.exit(fails > 0 and 1 or 0)
