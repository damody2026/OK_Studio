-- World Partition conversion of the streaming copy (Tools/street_city_stream_prep_payload.lua makes it from the source map).
--   Tools\lua\lua.exe Tools\build_street_city_stream.lua
-- 128 m cells, 250 m loading range; rerun after every map round, the WP map is generated and never edited by hand.
package.path = 'Tools/lua/?.lua;' .. package.path
local ok = require('ok')
local engine = 'E:/PhysX/UE5.8'
-- the host project carries the built city plugins; its Content is the same folder
local project = 'E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject/StreetSocialCity.uproject'
local out = 'output/street-social-city-production/stream-v1/'
-- the commandlet reads the settings from an ini beside the map
local ini = 'C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCityWP.ini'
local f = assert(io.open(ini, 'wb'))
f:write('[/Script/UnrealEd.WorldPartitionConvertCommandlet]\n')
f:write('EditorHashClass=/Script/Engine.WorldPartitionEditorSpatialHash\n')
f:write('RuntimeHashClass=/Script/Engine.WorldPartitionRuntimeSpatialHash\n\n')
f:write('[/Script/Engine.WorldPartitionRuntimeSpatialHash]\n')
f:write('+Grids=(GridName="MainGrid",CellSize=12800,LoadingRange=25000,bBlockOnSlowStreaming=False,Priority=0)\n')
f:close()
local log = 'C:/portable/OpenKoikatsu/' .. out .. 'convert-' .. os.date('%Y%m%d-%H%M%S') .. '.log'
local function editor(args, path)
  local cmd = { engine .. '/Engine/Binaries/Win64/UnrealEditor-Cmd.exe', project, '/Game/UniversityCity/Maps/UniversityCityWP' }
  for _, a in ipairs(args) do cmd[#cmd + 1] = a end
  for _, a in ipairs({ '-AllowCommandletRendering', '-unattended', '-nosplash', '-nop4', '-SCCProvider=None', '-abslog=' .. path }) do cmd[#cmd + 1] = a end
  return ok.proc.run(cmd, { hide = true }).code
end
-- --hlod: only the distance models, on a map that is already converted
-- --batches N: build the HLODs in N separate editor runs (setup writes a manifest splitting the HLOD actors
--   into N groups, then one run per group). One run over all 123 HLODs peaked at 146 GiB commit (11-13);
--   a fresh process per group keeps the peak to the heaviest group.
-- --from I: with --batches, start at group I (the setup and earlier groups are already done)
-- --no-hlod: the conversion only, no distance models (11-14: the HLOD build peaks near 146 GB and the low-spec PC cannot
--   hold even the built HLODs). The conversion empties the map's actor folder, so the result has no HLOD actor; the run
--   checks that and writes stream-v1/no-hlod-<stamp>.ini, which Tools/migrate_street_city_content.lua takes as "this WP
--   has no distance models on purpose" (an HLOD run stopped halfway is still refused). The HLOD layer assets the
--   conversion makes (UniversityCityWP_HLODLayer_*) stay: the map names them, and with no HLOD actor they build nothing.
local hlod_only, batches, from, no_hlod = false, nil, 0, false
local i = 1
while arg[i] do
  if arg[i] == '--hlod' then hlod_only = true
  elseif arg[i] == '--batches' then i = i + 1; batches = assert(tonumber(arg[i]), '--batches N')
  elseif arg[i] == '--from' then i = i + 1; from = assert(tonumber(arg[i]), '--from I'); hlod_only = true
  elseif arg[i] == '--no-hlod' then no_hlod = true
  else error('unknown argument ' .. arg[i]) end
  i = i + 1
end
if not hlod_only then
  local code = editor({ '-run=WorldPartitionConvertCommandlet', '-Verbose' }, log)
  print('convert exit', code, log)
  if code ~= 0 then os.exit(1) end
end
if no_hlod then
  assert(not hlod_only, '--no-hlod converts; it does not go with --hlod or --from')
  local lfs = require('lfs')
  local dir = 'C:/portable/OpenKoikatsu/StreetSocialCity/Content/__ExternalActors__/UniversityCity/Maps/UniversityCityWP'
  local files, hlods = 0, 0
  local function walk(d) for n in lfs.dir(d) do if n ~= '.' and n ~= '..' then local q = d .. '/' .. n
    if lfs.attributes(q, 'mode') == 'directory' then walk(q) elseif n:find('%.uasset$') then files = files + 1
      local h = assert(io.open(q, 'rb')); local s = h:read(65536); h:close()
      if s:find('WorldPartitionHLOD', 1, true) then hlods = hlods + 1 end end end end end
  walk(dir)
  print('actor files', files, 'HLOD actors', hlods)
  if hlods > 0 then print('the conversion left HLOD actors: not marking this WP as no-HLOD'); os.exit(1) end
  local stamp = log:match('convert%-(%d+%-%d+)%.log$')
  local m = assert(io.open('C:/portable/OpenKoikatsu/' .. out .. 'no-hlod-' .. stamp .. '.ini', 'wb'))
  m:write('[General]\nNoHLOD=1\nConvert=' .. stamp .. '\nActorFiles=' .. files .. '\nHLODActors=0\n'); m:close()
  print('no-HLOD WP marked', stamp)
  os.exit(0)
end
local hlog = log:gsub('convert%-', 'hlod-')
local builder = { '-run=WorldPartitionBuilderCommandlet', '-Builder=WorldPartitionHLODsBuilder' }
local function hlod(extra, path)
  local a = {}
  for _, v in ipairs(builder) do a[#a + 1] = v end
  for _, v in ipairs(extra) do a[#a + 1] = v end
  return editor(a, path)
end
if not batches then
  local code = hlod({}, hlog)
  print('hlod exit', code, hlog)
  os.exit(code == 0 and 0 or 1)
end
local manifest = 'C:/portable/OpenKoikatsu/' .. out .. 'hlod-manifest.ini'
if from == 0 then
  local code = hlod({ '-SetupHLODs', '-BuildManifest=' .. manifest, '-BuilderCount=' .. batches }, (hlog:gsub('%.log$', '-setup.log')))
  print('hlod setup exit', code, manifest)
  if code ~= 0 then os.exit(1) end
end
for b = from, batches - 1 do
  local path = hlog:gsub('%.log$', '-b' .. b .. '.log')
  local code = hlod({ '-BuildHLODs', '-BuildManifest=' .. manifest, '-BuilderIdx=' .. b }, path)
  print('hlod batch', b, 'exit', code, path)
  io.stdout:flush()
  if code ~= 0 then os.exit(1) end
end
os.exit(0)
