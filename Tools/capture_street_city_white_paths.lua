-- Same code/executable was already validated in v2; this bounded material revision
-- needs new rendered scene evidence, not another identical clock/profile test.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash')
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local env='output/street-social-city-production/day-night-v1';local out='output/street-social-city-production/white-paths-v1'
local runtime=read(env..'/runtime-package-launch.json');local package=read(env..'/package.json');local install=read(out..'/install.json')
assert(runtime.status=='passed' and runtime.map_sha256==install.parent_map_sha256)
local sha=hash.sha256_file(runtime.executable);assert(sha==hash.sha256_file(package.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe') and sha==package.prebuilt_game_sha256)
local f=assert(io.open(out..'/reused-runtime.json','wb'));f:write(json.encode({status='passed',source_receipt=runtime.native_receipt,source_map_sha256=runtime.map_sha256,map_sha256=install.map_sha256,executable_sha256=sha,scope='Prior Game clock/UI/save-load/profile tests reuse the exact same executable. This material-only map revision is freshly cooked and separately captured in D3D12.'}));f:close()
f=assert(io.open('Tools/capture_street_city_ground_revision.lua','rb'));local wrapper=f:read('*a');f:close()
local original=load
load=function(source,name)
 assert(name=='ground-revision-capture');source=source:gsub('ground%-pbr%-v2','white-paths-v1')
 local needle='runtime.map_sha256==installed.map_sha256';local n;source,n=source:gsub(needle:gsub('(%W)','%%%1'),'runtime.map_sha256==installed.parent_map_sha256');assert(n==1)
 return original(source,name)
end
assert(original(wrapper,'white-path-capture-wrapper'))()
