-- Copy what UniversityCity uses (migrate-v1/closure.json, Tools/street_city_migrate_payload.lua) from StreetSocialCity/Content to
-- Content/, same /Game paths. Rerun after a map round: unchanged files are skipped. A file that already exists in Content with
-- other bytes and is not ours (outside UniversityCity) is never overwritten, it is listed and the run fails.
--   Tools\lua\lua.exe Tools\migrate_street_city_content.lua
--   Tools\lua\lua.exe Tools\migrate_street_city_content.lua --refs-only   (only the reference step below: adds missing packages)
-- A full run refuses (exit 2) while an HLOD batch of the last WP conversion has not ended with Success (check below).
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
-- The World Partition actor files are synced whole, but closure.json only lists what the map named when it was made, so
-- whatever a later map round's actors use (Grok wall materials, Source_* textures) never came over: the editor logged
-- "dependent package ... was not available" and those walls drew without their material (11-14, 281 packages). This step
-- reads every /Game path in Content's WP files and adds those Content lacks and the source has, following each new package's
-- own references. It only adds files; nothing that exists is overwritten.
local exts = { '.uasset', '.umap', '.uexp', '.ubulk', '.uptnl' }
local function follow_references()
  local queue, seen, added, added_bytes = {}, {}, 0, 0
  local function walk(d) if not lfs.attributes(d) then return end
    for n in lfs.dir(d) do if n ~= '.' and n ~= '..' then local p = d .. '/' .. n
      if lfs.attributes(p, 'mode') == 'directory' then walk(p) elseif n:find('%.uasset$') or n:find('%.umap$') then queue[#queue + 1] = p end end end end
  walk('Content/__ExternalActors__/UniversityCity/Maps/UniversityCityWP'); walk('Content/__ExternalObjects__/UniversityCity/Maps/UniversityCityWP')
  for n in lfs.dir('Content/UniversityCity/Maps') do if n:find('^UniversityCityWP') and n:find('%.umap$') then queue[#queue + 1] = 'Content/UniversityCity/Maps/' .. n end end
  local i = 1
  while i <= #queue do
    local fh = assert(io.open(queue[i], 'rb')); local s = fh:read('*a'); fh:close(); i = i + 1
    for p in s:gmatch('/Game/[%w_/%-]+') do if not seen[p] then seen[p] = true
      local rel = p:gsub('^/Game/', ''); local here, there = false, {}
      for _, ext in ipairs(exts) do
        if lfs.attributes('Content/' .. rel .. ext) then here = true end
        if lfs.attributes('StreetSocialCity/Content/' .. rel .. ext, 'mode') == 'file' then there[#there + 1] = ext end
      end
      if not here and #there > 0 then
        for _, ext in ipairs(there) do local src = 'StreetSocialCity/Content/' .. rel .. ext
          copy(src, 'Content/' .. rel .. ext); added_bytes = added_bytes + lfs.attributes(src, 'size')
          if ext == '.uasset' or ext == '.umap' then queue[#queue + 1] = src end end
        added = added + 1
      end end end
  end
  print(string.format('referenced packages added %d (%.2f GB), files read %d', added, added_bytes / 2 ^ 30, #queue))
end
if arg[1] == '--refs-only' then follow_references(); os.exit(0) end
-- The WP copy only goes into the game when its last conversion and every HLOD batch after it ended with "Success - 0
-- error(s)" (Tools/build_street_city_stream.lua logs). 11-14: a run stopped in HLOD batch 1 of 8 left a converted map
-- with most distance models unbuilt in StreetSocialCity, over the old complete one; nothing must copy that into Content.
-- --allow-incomplete-hlod copies anyway (only when that is what you want).
do
  local dir = 'output/street-social-city-production/stream-v1/'
  local function ok_log(p) local f = io.open(dir .. p, 'rb'); if not f then return false end; local s = f:read('*a'); f:close(); return s:find('Success %- 0 error%(s%)') ~= nil end
  local convert, setup, batch, single = nil, nil, {}, nil
  for n in lfs.dir(dir) do
    local st = n:match('^convert%-(%d+%-%d+)%.log$'); if st and (not convert or st > convert) then convert = st end
  end
  local why
  if not convert then why = 'no conversion log in ' .. dir
  elseif not ok_log('convert-' .. convert .. '.log') then why = 'the last conversion (' .. convert .. ') did not end with Success'
  else
    for n in lfs.dir(dir) do
      local st = n:match('^hlod%-(%d+%-%d+)%-setup%.log$'); if st and st >= convert and (not setup or st > setup) then setup = st end
      local sb, b = n:match('^hlod%-(%d+%-%d+)%-b(%d+)%.log$'); if sb and sb >= convert and (not batch[b] or sb > batch[b]) then batch[b] = sb end
      local s1 = n:match('^hlod%-(%d+%-%d+)%.log$'); if s1 and s1 >= convert and (not single or s1 > single) then single = s1 end
    end
    if setup then
      local mf = io.open(dir .. 'hlod-manifest.ini', 'rb'); local count = mf and tonumber(mf:read('*a'):match('BuilderCount=(%d+)')); if mf then mf:close() end
      if not ok_log('hlod-' .. setup .. '-setup.log') then why = 'the HLOD setup (' .. setup .. ') did not end with Success'
      elseif not count then why = 'hlod-manifest.ini has no BuilderCount'
      else
        for b = 0, count - 1 do
          local st = batch[tostring(b)]
          if not st then why = ('HLOD batch %d of %d was not built after the conversion %s'):format(b, count, convert); break end
          if not ok_log(('hlod-%s-b%d.log'):format(st, b)) then why = ('HLOD batch %d (%s) did not end with Success'):format(b, st); break end
        end
      end
    elseif not (single and ok_log('hlod-' .. single .. '.log')) then why = 'no successful HLOD run after the conversion ' .. convert
    end
  end
  if why then
    if arg[1] == '--allow-incomplete-hlod' then print('WARNING, copying anyway: ' .. why)
    else
      print('refused: the World Partition copy in StreetSocialCity is not complete: ' .. why)
      print('  build the rest (Tools/build_street_city_stream.lua --batches 8 --from <first missing batch>) or pass --allow-incomplete-hlod')
      os.exit(2)
    end
  end
end
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
-- the World Partition copy: its map, HLOD layers and one file per actor, which the map's own dependency list does not name
local function walk(dir, fn) for n in lfs.dir(dir) do if n ~= '.' and n ~= '..' then local p = dir .. '/' .. n
  if lfs.attributes(p, 'mode') == 'directory' then walk(p, fn) else fn(p) end end end end
local stream = 0
local function sync(src)
  local a = lfs.attributes(src); local dst = 'Content/' .. src:gsub('^StreetSocialCity/Content/', ''); local b = lfs.attributes(dst)
  total = total + a.size; stream = stream + 1
  if b and b.size == a.size and b.modification >= a.modification then skipped = skipped + 1 else copy(src, dst); copied = copied + 1; bytes = bytes + a.size end
end
-- a conversion gives every actor a new file, so files of the previous one left in Content stay loaded with the map (2026-11-10:
-- a wall of the removed S44 blocked the new alley in game); whatever the source folder no longer has is deleted here
local stale = 0
for _, d in ipairs({ '__ExternalActors__', '__ExternalObjects__' }) do
  local p = 'StreetSocialCity/Content/' .. d .. '/UniversityCity/Maps/UniversityCityWP'
  if lfs.attributes(p) then walk(p, sync) end
  local q = 'Content/' .. d .. '/UniversityCity/Maps/UniversityCityWP'
  if lfs.attributes(q) then walk(q, function(dst)
    if not lfs.attributes('StreetSocialCity/' .. dst) then assert(os.remove(dst)); stale = stale + 1 end
  end) end
end
print('stale World Partition files deleted', stale)
for n in lfs.dir('StreetSocialCity/Content/UniversityCity/Maps') do if n:find('^UniversityCityWP') and not n:find('%.ini$') then sync('StreetSocialCity/Content/UniversityCity/Maps/' .. n) end end
print('World Partition files', stream)
follow_references()
print(string.format('packages %d, files copied %d, unchanged %d, copied %.2f GB, total %.2f GB', #c.packages, copied, skipped, bytes / 2 ^ 30, total / 2 ^ 30))
print('missing', #missing); for i = 1, math.min(#missing, 20) do print('  ' .. missing[i]) end
print('clash', #clash); for i = 1, math.min(#clash, 20) do print('  ' .. clash[i]) end
local outside_game = 0; for _, p in ipairs(c.packages) do if not p:find('^/Game/UniversityCity/') then outside_game = outside_game + 1 end end
print('packages outside UniversityCity', outside_game)
print('outside /Game', #c.outside); for _, p in ipairs(c.outside) do print('  ' .. p) end
os.exit(#clash == 0 and #missing == 0 and 0 or 1)
