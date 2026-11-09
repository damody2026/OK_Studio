-- Update only the isolated E-engine validation host; never the private live editor.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1';local host='E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject';local engine='E:/PhysX/UE5.8'
local rel='Plugins/CityEnvironment/Source/CityEnvironment/Private/'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(type(d)=='string' and d or j.encode(d));f:close()end
-- Source Game also loads this editor DLL: never replace it during a soak.
local stopped_guard="$p=Get-CimInstance Win32_Process|Where-Object {($_.Name -like '*UnrealEditor*' -or $_.Name -eq 'StreetSocialCity.exe') -and $_.CommandLine -like '*20261023-145531*'};if($p){throw 'Validation host is still loaded; finish its active Game/editor run before rebuilding'}"
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',stopped_guard},{hide=true}).code==0,'Refusing to rebuild a loaded validation host')
local module=read(root..'/StreetSocialCity/'..rel..'CityEnvironmentModule.cpp');local previous=read(host..'/'..rel..'CityEnvironmentModule.cpp');local original=module:gsub('#include "CityEnvironmentImmersionAudit.h"\r?\n',''):gsub(' StartCityEnvironmentImmersionAudit%(%)%;',''):gsub('StopCityEnvironmentImmersionAudit%(%)%; ','')
assert(previous:gsub('\r','')==original:gsub('\r','') or previous:gsub('\r','')==module:gsub('\r',''),'Isolated host startup has unrelated edits; do not overwrite')
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"$p=Get-Item -LiteralPath '"..host.."/Plugins/CityEnvironment';if($p.LinkType){throw 'Expected an independent physical plugin copy'};New-Item -ItemType Directory -Path '"..out.."/native-audit-build' -Force|Out-Null"},{hide=true}).code==0)
local id=os.date('%Y%m%d-%H%M%S');write(out..'/native-audit-build/module-before-'..id..'.cpp',previous);local files={}
local prior=io.open(out..'/native-audit-build/build.json','rb')
if prior then local text=prior:read('*a');prior:close();local receipt=j.decode(text);local archive=out..'/native-audit-build/build-'..receipt.game_sha256:sub(1,16)..'.json';if not io.open(archive,'rb')then write(archive,text)end end
for _,name in ipairs({'CityEnvironmentImmersionAudit.h','CityEnvironmentImmersionAudit.cpp','CityEnvironmentModule.cpp','CityImmersionWalker.h','CityImmersionWalker.cpp','CityImmersionInputAudit.h','CityImmersionInputAudit.cpp'})do local source=root..'/StreetSocialCity/'..rel..name;write(host..'/'..rel..name,read(source));files[#files+1]={file=name,sha256=h.sha256_file(source)}end
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local before=h.sha256_file(map)
for _,target in ipairs({'StreetSocialCityEditor','StreetSocialCity'})do
 local log=out..'/native-audit-build/'..id..'-'..target..'.log';local command="& '"..engine.."/Engine/Build/BatchFiles/Build.bat' "..target.." Win64 Development '-Project="..host.."/StreetSocialCity.uproject' -WaitMutex -NoHotReloadFromIDE -NoUBTMakefiles -gather -ForceRulesCompile -MaxParallelActions=8;exit $LASTEXITCODE"
 local result=ok.proc.run({'powershell.exe','-NoProfile','-Command',command},{hide=true,cwd=root,stdout_file=log,stderr_file=log..'.stderr',timeout=3600});write(out..'/native-audit-build/'..target..'-latest.json',{status=result.code==0 and 'passed' or 'failed',exit_code=result.code,engine=engine,host=host,log=log,files=files});assert(result.code==0,'Native immersion audit build failed: '..log)
end
assert(h.sha256_file(map)==before,'Source map changed during code-only validation build')
local executable=host..'/Binaries/Win64/StreetSocialCity.exe';write(out..'/native-audit-build/build.json',{status='passed',engine=engine,host=host,map_sha256=before,source_files=files,game_executable=executable,game_sha256=h.sha256_file(executable),scope='Opt-in cooked physics/walking soak audit only; normal scene runtime remains inert without CityImmersionAudit argument. Independent E code host; private live editor and other E project untouched.'});print('Native immersion physics/soak auditor built with isolated E engine host.')
