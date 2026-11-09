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
if arg[1] ~= '--hlod' then
  local code = editor({ '-run=WorldPartitionConvertCommandlet', '-Verbose' }, log)
  print('convert exit', code, log)
  if code ~= 0 then os.exit(1) end
end
local hlog = log:gsub('convert%-', 'hlod-')
local code = editor({ '-run=WorldPartitionBuilderCommandlet', '-Builder=WorldPartitionHLODsBuilder' }, hlog)
print('hlod exit', code, hlog)
os.exit(code == 0 and 0 or 1)
