-- Walks the player to every place of the street (city_places.json) in a running game, the way a player walks
-- (ok-game-mcp game_goto: the in-game navigation, clock running), and records for each whether he got there, how
-- long it took and what he can do there (the buttons on screen on arrival).
--
--   street_place_audit.lua --port <control port> --out <result.json> [--only id,id] [--timeout 600] [--retries 2]
--
-- Results are written after every place, and a place already in --out is skipped: run it again to go on.
-- Run it on a sandbox of its own (game_launch -Sandbox <name>): the walks take game days.
local ok = require "ok"
local json, path = ok.json, ok.path

local parser = ok.args.parser()
parser:opt("--port", { required = true })
parser:opt("--out", { required = true })
parser:opt("--only", { default = "" })
parser:opt("--timeout", { default = "600" })
parser:opt("--retries", { default = "2" })
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

local places = json.decode(path.read_text(path.join(ok.root, "Content/IndependentResources/StreetSocialData/city_places.json")))
places = places.places or places
local only = {}
for id in args.only:gmatch("[^,]+") do only[id] = true end

local results = path.exists(args.out) and json.decode(path.read_text(args.out)) or { places = {} }
local done = {}
for _, r in ipairs(results.places) do done[r.id] = true end

-- Where he stands now (the state line "player (x,y)").
local function here()
  local s = call("game_state", {})
  local x, y = s:match("player %((%-?[%d%.]+),(%-?[%d%.]+)%)")
  return tonumber(x) or 0, tonumber(y) or 0, s
end

-- Nearest place next: a walk from one to the next, not across the city each time.
local todo = {}
for _, p in ipairs(places) do
  if not done[p.id] and (next(only) == nil or only[p.id]) then todo[#todo + 1] = p end
end

local function save()
  local f = path.join(path.parent(args.out), path.name(args.out) .. ".tmp")
  path.write_text(f, json.encode(results, { ensure_ascii = false, indent = 2 }))
  path.replace(f, args.out)
end

while #todo > 0 do
  local x, y = here()
  table.sort(todo, function(a, b)
    local da = (a.door[1] - x) ^ 2 + (a.door[2] - y) ^ 2
    local db = (b.door[1] - x) ^ 2 + (b.door[2] - y) ^ 2
    return da < db
  end)
  local p = table.remove(todo, 1)
  local dist = math.sqrt((p.door[1] - x) ^ 2 + (p.door[2] - y) ^ 2) / 100
  local r = { id = p.id, name = p.name, from = { x, y }, door = p.door, meters = math.floor(dist + .5), tries = {} }
  local started = os.time()
  local arrived = false
  for attempt = 1, tonumber(args.retries) + 1 do
    local out = call("game_goto", { place = p.id, timeout_s = tonumber(args.timeout) })
    local at = out:match("place=([%w_]+)")
    r.tries[#r.tries + 1] = { place = at, error = out:match("^Error[^\n]*") or out:match("refused[^\n]*"), line = out:match("[^\n]*") }
    if at == p.id then arrived = true break end
    if out:match("refused") then break end
  end
  r.arrived = arrived
  r.seconds = os.time() - started
  local _, _, state = here()
  r.state = state:match("[^\n]*")
  local buttons = call("game_buttons", {})
  local ok_b, list = pcall(json.decode, buttons)
  r.buttons = ok_b and list or buttons
  results.places[#results.places + 1] = r
  save()
  print(("%-18s %s %4d m %4d s %s"):format(p.id, arrived and "OK  " or "FAIL", r.meters, r.seconds, arrived and "" or (r.tries[#r.tries].place or "?")))
  io.stdout:flush()
end
