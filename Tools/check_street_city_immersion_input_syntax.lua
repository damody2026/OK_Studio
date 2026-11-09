-- MSVC /Zs with PCH disabled: no object/link/DLL output, safe beside live soak.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1';local host='E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject';local private='/Plugins/CityEnvironment/Source/CityEnvironment/Private/'
local function raw(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s:gsub('^\239\187\191','')end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local latest=j.decode(raw(out..'/native-audit-build/StreetSocialCity-latest.json'));local chain=assert(raw(latest.log):match('toolchain %((.-)%) and Windows'));local compiler=chain:gsub('\\','/')..'/bin/Hostx64/x64/cl.exe'
local dll=host..'/Plugins/CityEnvironment/Binaries/Win64/UnrealEditor-CityEnvironment.dll';local executable=host..'/Binaries/Win64/StreetSocialCity.exe';local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local before={dll=h.sha256_file(dll),exe=h.sha256_file(executable),map=h.sha256_file(map)}
local reflected='CityImmersionWalker.h';local header=root..'/StreetSocialCity'..private..reflected
if raw(header)~=raw(host..private..reflected)then
 write(out..'/input-syntax.json',j.encode({status='pending_full_UHT_build',header_sha256=h.sha256_file(header),map_sha256=before.map,live_editor_dll_unchanged=h.sha256_file(dll)==before.dll,scope='Reflected Walker header changed;cached generated-body line numbers are stale. Wait for active source Game exit,then use full UHT/editor/game build. Do not misclassify a stale-generated-header /Zs failure as a scene or runtime failure.'}))
 print('Reflected header changed: full UHT build required after active Game exits; no DLL/map mutation.');return
end
local folder=out..'/input-syntax-'..os.date('%Y%m%d-%H%M%S');assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..folder.."'|Out-Null"},{hide=true}).code==0)
local source=raw(host..'/Plugins/CityEnvironment/Intermediate/Build/Win64/x64/UnrealGame/Development/CityEnvironment/CityImmersionWalker.cpp.obj.rsp');local base={}
for line in source:gmatch('[^\r\n]+')do if not line:match('%.cpp"$') and not line:match('^/Yu') and not line:match('^/Fp') and not line:match('^/Fo') and not line:match('^/experimental:log') and not line:match('^/sourceDependencies')then base[#base+1]=line end end
local rows={}
for _,name in ipairs({'CityImmersionInputAudit.cpp','CityEnvironmentImmersionAudit.cpp','CityImmersionWalker.cpp'})do
 local rsp=folder..'/'..name..'.rsp';write(rsp,'"'..root..'/StreetSocialCity'..private..name..'"\n'..table.concat(base,'\n')..'\n/Zs\n/Y-\n');local log=folder..'/'..name..'.log';local result=ok.proc.run({compiler,'@'..rsp},{hide=true,cwd='E:/PhysX/UE5.8/Engine/Source',stdout_file=log,stderr_file=log..'.stderr',timeout=300});rows[#rows+1]={file=name,exit_code=result.code,log=log};assert(result.code==0,'Syntax check failed: '..log)
end
assert(h.sha256_file(dll)==before.dll and h.sha256_file(executable)==before.exe and h.sha256_file(map)==before.map,'Syntax-only check changed runtime or map')
write(out..'/input-syntax.json',j.encode({status='passed_syntax_only_requires_full_build_and_runtime',compiler=compiler,checks=rows,live_editor_dll_unchanged=true,game_executable_unchanged=true,map_sha256=before.map,scope='MSVC /Zs /Y- only. No object,PCH,link or DLL output;full editor/game build and controller-event runtime acceptance remain required after active soak exits.'}));print('Input/helper and main auditor syntax passed;live DLL and map unchanged.')
