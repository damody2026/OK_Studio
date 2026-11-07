-- Copy what UniversityCity uses (migrate-v1/closure.json, Tools/street_city_migrate_payload.lua) from StreetSocialCity/Content to
-- Content/, same /Game paths. Rerun after a map round: unchanged files are skipped. A file that already exists in Content with
-- other bytes and is not ours (outside UniversityCity) is never overwritten, it is listed and the run fails.
--   Tools\lua\lua.exe Tools\migrate_street_city_content.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json'); local lfs = require('lfs')
local out = 'output/street-social-city-production/migrate-v1/'
local f = assert(io.open(out .. 'closure.json', 'rb')); local c = j.decode(f:read('*a')); f:close()
local function mkdirs(p) local acc = ''; for part in p:gmatch('[^/]+/') do acc = acc .. part; lfs.mkdir(acc) end end
local function copy(a, b)
  local i = assert(io.open(a, 'rb')); mkdirs(b); local o = assert(io.open(b, 'wb'))
  while true do local s = i:read(8388608); if not s then break end; o:write(s) end
  i:close(); o:close()
end
local copied, skipped, bytes, total, missing, clash = 0, 0, 0, 0, {}, {}
for _, p in ipairs(c.packages) do
  local rel = p:gsub('^/Game/', ''); local found = false
  for _, ext in ipairs({ '.uasset', '.umap', '.uexp', '.ubulk', '.uptnl' }) do
    local src, dst = 'StreetSocialCity/Content/' .. rel .. ext, 'Content/' .. rel .. ext
    local a = lfs.attributes(src)
    if a then found = true; total = total + a.size
      local b = lfs.attributes(dst)
      if b and b.size == a.size and b.modification >= a.modification then skipped = skipped + 1
      elseif b and not rel:find('^UniversityCity/') then clash[#clash + 1] = dst
      else copy(src, dst); copied = copied + 1; bytes = bytes + a.size end
    end
  end
  if not found then missing[#missing + 1] = p end
end
print(string.format('packages %d, files copied %d, unchanged %d, copied %.2f GB, total %.2f GB', #c.packages, copied, skipped, bytes / 2 ^ 30, total / 2 ^ 30))
print('missing', #missing); for i = 1, math.min(#missing, 20) do print('  ' .. missing[i]) end
print('clash', #clash); for i = 1, math.min(#clash, 20) do print('  ' .. clash[i]) end
local outside_game = 0; for _, p in ipairs(c.packages) do if not p:find('^/Game/UniversityCity/') then outside_game = outside_game + 1 end end
print('packages outside UniversityCity', outside_game)
print('outside /Game', #c.outside); for _, p in ipairs(c.outside) do print('  ' .. p) end
os.exit(#clash == 0 and #missing == 0 and 0 or 1)
