-- Fails before the editor opens when Tools/street_city_lover_spots_payload.lua names a model that has no file.
--   Tools\lua\lua.exe Tools\check_street_city_models.lua
-- Keys come from place_mesh / tripo_mesh / r_mesh calls; a key is fine when a prepared set lists it or hill-v1 has <key>.glb.
local json = require('ok.json')
local root = 'output/street-social-city-production/'
local function read(p) local f = io.open(p, 'rb'); if not f then return nil end; local s = f:read('a'); f:close(); return s end
local src = assert(read('Tools/street_city_lover_spots_payload.lua'))
local have = {}
for _, set in ipairs({ 'life-tripo-v1', 'world-tripo-v1', 'city-add-tripo-v1', 'furniture-add-tripo-v1' }) do
  local s = read(root .. set .. '/prepared.json')
  if s then
    s = s:gsub('^\239\187\191', '')
    for _, a in ipairs(json.decode(s).assets) do have[a.key] = true end
  end
end
-- models assigned straight to a path: ltr['key'], and the `for k_ in (...)` lists that fill ltr
local used, missing = {}, {}
for _, pat in ipairs({ "tripo_mesh%('([%w_]+)'%)", "place_mesh%([^,\n]+,'([%w_]+)'", "r_mesh%('([%w_]+)'" }) do
  for k in src:gmatch(pat) do used[k] = true end
end
for k in pairs(used) do
  if not have[k] and not read(root .. 'hill-v1/' .. k .. '.glb') and not src:find("ltr['" .. k .. "']=", 1, true) then missing[#missing + 1] = k end
end
table.sort(missing)
if #missing > 0 then io.stderr:write('models with no file: ' .. table.concat(missing, ', ') .. '\n'); os.exit(1) end
local n = 0; for _ in pairs(used) do n = n + 1 end
print('models ok: ' .. n)
