-- Tries every activity of the street (rules/activities.toml) for real in a running game: he stands at the place's door,
-- she beside him, the outing starts as an agreed invitation does (control /activity_try), and the clock runs until the
-- activity is under way or the outing gives up. For each it records what ran, where the two stand against the anchor
-- and the ground (floating, sunk, inside an obstacle), the message on screen and a screenshot.
--
--   street_activity_audit.lua --port <control port> --out <result.json> [--girl 1] [--only id,id] [--place id,id]
--                             [--timeout 150] [--shots <dir>]
--
-- Results are written after every activity, and an activity already in --out is skipped: run it again to go on.
-- Run it on a sandbox of its own (game_launch -Sandbox <name>).
local ok = require "ok"
local json, path = ok.json, ok.path

local parser = ok.args.parser()
parser:opt("--port", { required = true })
parser:opt("--out", { required = true })
parser:opt("--girl", { default = "1" })
parser:opt("--only", { default = "" })
parser:opt("--place", { default = "" })
parser:opt("--timeout", { default = "150" })
parser:opt("--shots", { default = "" })
local args = parser:parse(arg)

local exe = path.join(ok.root, "Tools/ok-game-mcp/target/release/ok-game-mcp.exe")
local function call(tool, body)
  local req = path.temp(".txt")
  local cmd = ('set "OK_CONTROL_PORT=%s" && "%s" call %s "%s" > "%s" 2>&1'):format(args.port, (exe:gsub("/", "\\")), tool,
    json.encode(body or {}):gsub('"', '\\"'), (req:gsub("/", "\\")))
  os.execute('"' .. cmd .. '"')
  local out = path.exists(req) and path.read_text(req) or ""
  path.remove(req, true)
  return out
end
local function try(body)
  local out = call("game_call", { path = "/activity_try", body = body })
  local okj, v = pcall(json.decode, out)
  return okj and type(v) == "table" and v or { ok = false, error = out:sub(1, 300) }
end
local function sleep(s) os.execute("ping -n " .. (s + 1) .. " 127.0.0.1 >nul") end

-- The activities, read line by line (id, place, kind, anchor of each [[activity]]).
local acts, cur = {}, nil
for line in io.lines(path.join(ok.root, "Content/IndependentResources/StreetSocialData/rules/activities.toml")) do
  line = line:gsub("\r$", "")
  if line:match("^%[%[activity%]%]") then cur = {}; acts[#acts + 1] = cur
  elseif cur then
    local k, v = line:match('^(%w+)%s*=%s*"([^"]*)"')
    if k == "id" or k == "place" or k == "kind" or k == "anchor" then cur[k] = v end
  end
end
local only, places = {}, {}
for id in args.only:gmatch("[^,]+") do only[id] = true end
for id in args.place:gmatch("[^,]+") do places[id] = true end

local results = path.exists(args.out) and json.decode(path.read_text(args.out)) or { activities = {} }
local done = {}
for _, r in ipairs(results.activities) do done[r.id] = true end
local function save()
  local f = args.out .. ".tmp"
  path.write_text(f, json.encode(results, { ensure_ascii = false, indent = 2 }))
  path.replace(f, args.out)
end

-- What is wrong with where they stand once it runs.
local function problems(st, kind)
  local p = {}
  local function body(name, w)
    if not w then return end
    if not w.ground then p[#p + 1] = name .. " has no ground under"
    -- (under 0: the ray from 70 cm up met a counter or a seat beside a seated pair first, not a fault)
    elseif (w.above_ground or 0) > 40 then p[#p + 1] = ("%s %.0f cm over the ground"):format(name, w.above_ground) end
    if w.in_obstacle then p[#p + 1] = name .. " inside an obstacle" end
    if w.in_mesh then p[#p + 1] = name .. " inside the map's geometry" end
  end
  if st.running ~= "sleep" and st.running ~= "facility" then body("he", st.male); body("she", st.female) end
  if st.anchor and (kind == "pair" or kind == "photo" or kind == "solo") and (st.male_from_anchor or 0) > 120 then
    p[#p + 1] = ("he is %.0f cm from the anchor"):format(st.male_from_anchor)
  end
  if st.apart and st.running ~= "sleep" and st.running ~= "facility" and st.running ~= "restroom" and st.apart > 400 then
    p[#p + 1] = ("the two are %.0f cm apart"):format(st.apart)
  end
  return p
end

local expect = { pair = "pair", photo = "pair", solo = "solo", facility = "facility", restroom = "restroom", sleep = "sleep", walk = "stroll" }
call("game_clock", { paused = false })
call("game_call", { path = "/money", body = { amount = 200000 } })

for _, a in ipairs(acts) do
  if a.id and not done[a.id] and (next(only) == nil or only[a.id]) and (next(places) == nil or places[a.place or ""]) then
    local r = { id = a.id, place = a.place, kind = a.kind, anchor = a.anchor }
    local started = os.time()
    -- In the afternoon, when most places are open; a place closed then ("營業 18–2 點") is tried an hour after it opens.
    call("game_clock", { paused = false })
    call("game_call", { path = "/clock", body = { hours = 14, paused = false } })
    local s = try({ op = "start", girl = tonumber(args.girl), id = a.id })
    -- ("營業 17–24 點": the dash is three bytes, so a [–-] class never matched it and a closed place was never retried)
    local opens = not s.ok and (tostring(s.error):match("營業%s*(%d+)") or tostring(s.error):match("(%d+)%s*%-%s*%d+"))
    if not s.ok and tostring(s.error):match("快打烊") then opens = "10" end
    if opens then
      call("game_call", { path = "/clock", body = { hours = (tonumber(opens) + 1) % 24, paused = false } })
      s = try({ op = "start", girl = tonumber(args.girl), id = a.id })
    end
    r.start_ok, r.start_error = s.ok, s.error
    local st = {}
    if s.ok then
      local want = expect[a.kind]
      repeat
        sleep(2)
        st = try({ op = "status", id = a.id })
      until st.running ~= "walking" or os.time() - started > tonumber(args.timeout)
      if want and st.running == want and want == "pair" then sleep(4); st = try({ op = "status", id = a.id }) end
      r.running, r.status = st.running, st
      r.reached = want == nil and st.running == "none" or st.running == want
      if st.running == "walking" then r.reached = false; r.why = ("still walking after %d s (step %s/%s)"):format(os.time() - started, st.route_step, st.route_points) end
      if not r.reached and not r.why then r.why = ("ran %s, message: %s"):format(st.running or "?", st.message or "") end
      r.problems = r.reached and problems(st, a.kind) or {}
      if args.shots ~= "" and r.reached then
        -- What he sees there (the conversation camera), and how bright it is: a lit room blown out white, a dark one black.
        local shot = call("game_screenshot", {})
        r.shot = shot:match("[A-Za-z]:[^\r\n\"]+%.png")
        if r.shot then
          local okj, st2 = pcall(json.decode, call("image_stats", { file = r.shot }))
          if okj and type(st2) == "table" then
            r.light = { mean = st2.mean, white = st2.white, black = st2.black }
            -- (a white shop's own walls and a sunny street through its window are a third of the view: not a fault)
            if st2.white > .4 then r.problems[#r.problems + 1] = ("%.0f%% of the view blown out white"):format(st2.white * 100) end
            if st2.black > .3 or st2.mean < 30 then r.problems[#r.problems + 1] = ("too dark (mean %.0f, %.0f%% black)"):format(st2.mean, st2.black * 100) end
          end
          path.mkdir(args.shots, true)
          local to = path.join(args.shots, a.id .. ".png")
          pcall(path.copy, r.shot, to)
          r.shot = to
        end
      end
    else
      r.reached = false; r.why = "start refused: " .. tostring(s.error)
    end
    -- A meal ended within half a minute of starting waits for its plate: end again until nothing runs.
    for _ = 1, 10 do
      try({ op = "end" })
      sleep(1)
      if (try({ op = "status" }).running or "none") == "none" then break end
    end
    r.seconds = os.time() - started
    results.activities[#results.activities + 1] = r
    save()
    print(("%-26s %-18s %-8s %s %3d s %s"):format(a.id, a.place or "-", a.kind or "-", r.reached and (#r.problems > 0 and "WARN" or "OK  ") or "FAIL",
      r.seconds, r.reached and table.concat(r.problems, "; ") or (r.why or "")))
    io.stdout:flush()
  end
end
