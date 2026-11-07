-- Compares the anchors of each furnished kind with the actors really in the map, after the chain's places probe.
--   Tools\lua\lua.exe Tools\count_street_city_pieces.lua
-- Inputs: world-edge-v1/lover-spots-install-*.json (latest), places-v1/actors.json. An item whose actor is not in the map is a fault.
local json = require('ok.json')
local lfs = require('lfs')
local root = 'output/street-social-city-production/'
local function load(p) local f = assert(io.open(p, 'rb')); local s = f:read('a'); f:close(); return json.decode((s:gsub('^\239\187\191', ''))) end
local last
for n in lfs.dir(root .. 'world-edge-v1') do if n:match('^lover%-spots%-install%-.*%.json$') and (not last or n > last) then last = n end end
local inst = load(root .. 'world-edge-v1/' .. last)
local actors = {}
-- a piece made of parts is <actor>_Body, <actor>_Seat ...: the prefix counts
local labels = {}
for _, a in ipairs(load(root .. 'places-v1/actors.json').actors) do actors[a.label] = true; labels[#labels + 1] = a.label end
table.sort(labels)
local function present(name)
  if actors[name] then return true end
  local lo, hi = 1, #labels
  while lo < hi do local m = (lo + hi) // 2; if labels[m] < name then lo = m + 1 else hi = m end end
  return labels[lo] and labels[lo]:sub(1, #name) == name
end
local rows, bad = {}, 0
for _, it in ipairs(inst.items or {}) do
  local kind = it.anchor:gsub('[%d_]*$', '')
  local r = rows[kind] or { anchors = 0, actors = 0, room = 0, gone = {} }; rows[kind] = r
  r.anchors = r.anchors + 1
  if not it.actor or it.actor == 'room' or not it.actor:match('^LoverSpot') then r.room = r.room + 1
  elseif kind == 'door' or present(it.actor) then r.actors = r.actors + 1
  else r.gone[#r.gone + 1] = it.place .. ':' .. it.actor; bad = bad + 1 end
end
local names = {}; for k in pairs(rows) do names[#names + 1] = k end; table.sort(names)
print(last)
print('kind\tanchors\tin map\tscene piece\tmissing')
for _, k in ipairs(names) do local r = rows[k]; print(('%s\t%d\t%d\t%d\t%d'):format(k, r.anchors, r.actors, r.room, #r.gone)); for i = 1, math.min(3, #r.gone) do print('  ' .. r.gone[i]) end end
print('skipped:')
for _, s in ipairs(inst.skipped or {}) do print('  ' .. tostring(s.place) .. ': ' .. tostring(s.reason)) end
if bad > 0 then io.stderr:write(bad .. ' anchors stand on nothing\n'); os.exit(1) end
