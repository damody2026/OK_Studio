-- Isolated content-only runtime host; never changes or cleans an existing stage.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local engine='E:/PhysX/UE5.8';local out=root..'/output/street-social-city-production/day-night-v1'
local id=os.date('%Y%m%d-%H%M%S');local target='E:/StreetSocialCityProduction/environment-packages/'..id;local host=target..'/HostProject'
local function q(v)return "'"..v:gsub("'","''").."'" end
local function read(path)local f=assert(io.open(path,'rb'));local t=f:read('*a');f:close();return json.decode(t)end
local function write(path,t)local f=assert(io.open(path,'wb'));f:write(json.encode(t));f:close()end
local function hash(path)
 local result=ok.proc.run({'powershell.exe','-NoProfile','-Command',"[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes("..q(path).."))).Replace('-','').ToLowerInvariant()"},{capture=true,hide=true})
 assert(result.code==0,'Source hash failed: '..tostring(result.stderr or result.stdout));return result.stdout:gsub('%s+','')
end
local before=read(out..'/current-map.json').map_sha256
local source_config=root..'/StreetSocialCity/Config/DefaultEngine.ini';local config_before=hash(source_config)
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';assert(hash(map)==before,'Main map differs from reviewed receipt')
local script="$ErrorActionPreference='Stop';$packageHost="..q(host)..";if(Test-Path -LiteralPath $packageHost){throw 'Target already exists'};if(([IO.DriveInfo]::new('E')).AvailableFreeSpace -lt 150GB){throw 'Insufficient staging space'};New-Item -ItemType Directory -Path $packageHost|Out-Null;New-Item -ItemType Junction -Path (Join-Path $packageHost 'Content') -Target "..q(root..'/StreetSocialCity/Content').."|Out-Null;Copy-Item -LiteralPath "..q(root..'/StreetSocialCity/Config').." -Destination $packageHost -Recurse;New-Item -ItemType Directory -Path (Join-Path $packageHost 'Plugins')|Out-Null;foreach($name in @('CityEnvironment','CityLocalization')){$src=Join-Path "..q(root..'/StreetSocialCity/Plugins').." $name;$dst=Join-Path $packageHost ('Plugins/'+$name);New-Item -ItemType Directory -Path $dst|Out-Null;foreach($part in @('Source','Config',($name+'.uplugin'))){$p=Join-Path $src $part;if(Test-Path -LiteralPath $p){Copy-Item -LiteralPath $p -Destination $dst -Recurse}}};@{FileVersion=3;Modules=@(@{Name='CityEnvironmentHost';Type='Runtime';LoadingPhase='Default'});Category='Environment';Plugins=@(@{Name='CityEnvironment';Enabled=$true},@{Name='CityLocalization';Enabled=$true})}|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $packageHost 'StreetSocialCity.uproject')"
local r=ok.proc.run({'powershell.exe','-NoProfile','-Command',script},{hide=true,cwd=root,timeout=120});assert(r.code==0,'Isolated host preparation failed')
-- A code host makes UAT build the enabled runtime plugins for both Editor
-- (Cook) and the actual game, rather than selecting bare engine targets.
r=ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Force -Path "..q(host..'/Source/CityEnvironmentHost').."|Out-Null"},{hide=true,cwd=root,timeout=30});assert(r.code==0)
local function source_file(path,text)local f=assert(io.open(host..'/'..path,'wb'));f:write(text);f:close()end
for _,target in ipairs({'Game','Editor'})do
 local suffix=target=='Editor' and 'Editor' or '';local name='StreetSocialCity'..suffix
 source_file('Source/'..name..'.Target.cs','using UnrealBuildTool;\npublic class '..name..'Target : TargetRules { public '..name..'Target(TargetInfo Target) : base(Target) { Type = TargetType.'..target..'; DefaultBuildSettings = BuildSettingsVersion.V7; IncludeOrderVersion = EngineIncludeOrderVersion.Latest; BuildEnvironment = TargetBuildEnvironment.Shared; ExtraModuleNames.Add("CityEnvironmentHost"); } }\n')
end
source_file('Source/CityEnvironmentHost/CityEnvironmentHost.Build.cs','using UnrealBuildTool;\npublic class CityEnvironmentHost : ModuleRules { public CityEnvironmentHost(ReadOnlyTargetRules Target) : base(Target) { PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs; PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine" }); } }\n')
source_file('Source/CityEnvironmentHost/CityEnvironmentHost.cpp','#include "Modules/ModuleManager.h"\nIMPLEMENT_PRIMARY_GAME_MODULE(FDefaultGameModuleImpl, CityEnvironmentHost, "CityEnvironmentHost");\n')
-- The Android editor file-server settings are unrelated to a Windows runtime.
-- Omit that section from the isolated copy without reading it into any log.
local copied_config=host..'/Config/DefaultEngine.ini'
local cf=assert(io.open(copied_config,'rb'));local raw=cf:read('*a');cf:close()
local kept,position,skip,filtered={},1,false,0
while position<=#raw do
 local stop=raw:find('\n',position,true) or #raw;local line=raw:sub(position,stop);position=stop+1
 local header=line:gsub('^\239\187\191',''):gsub('[\r\n]+$',''):match('^%s*%[([^%]]+)%]%s*$')
 if header then skip=header=='/Script/AndroidFileServerEditor.AndroidFileServerRuntimeSettings';if skip then filtered=filtered+1 end end
 if not skip then kept[#kept+1]=line end
end
assert(filtered<=1);cf=assert(io.open(copied_config,'wb'));cf:write(table.concat(kept));cf:close();assert(hash(source_config)==config_before,'Original Config changed')
-- Landmass editor gizmo CDOs preload these materials during commandlet
-- startup. Their Engine/EditorMaterials references are not runtime content.
-- Keep the runtime plugin dependency graph intact; exclude only these folders.
local game_config=assert(io.open(host..'/Config/DefaultGame.ini','ab'))
game_config:write('\n[/Script/UnrealEd.ProjectPackagingSettings]\nbUseIoStore=False\nbUseZenStore=False\nbUsePakFile=True\n+DirectoriesToNeverCook=(Path="/Landmass/Landscape/BlueprintBrushes/Materials/Internal")\n+DirectoriesToNeverCook=(Path="/Landmass/Landscape/BlueprintBrushes/Materials/Sprite")\n');game_config:close()
local build_logs={}
for _,target_name in ipairs({'StreetSocialCityEditor','StreetSocialCity'})do
 local build_log=out..'/package-'..id..'-'..target_name..'-build.log';build_logs[#build_logs+1]=build_log
 write(out..'/package-running.json',{status='building_isolated_host',id=id,engine=engine,host=host,target=target,log=build_log,map_sha256=before,source_config_sha256=config_before})
 local build_args={engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll',target_name,'Win64','Development','-Project='..host..'/StreetSocialCity.uproject','-WaitMutex','-NoHotReloadFromIDE','-NoEngineChanges','-log='..build_log}
 r=ok.proc.run(build_args,{hide=true,cwd=root,stdout_file=build_log..'.stdout',stderr_file=build_log..'.stderr',timeout=3600})
 if r.code~=0 and target_name=='StreetSocialCity' then
  local lf=assert(io.open(build_log,'rb'));local diagnostic=lf:read('*a');lf:close()
  local affected=diagnostic:match('Building would modify the following existing engine files:%s*(.-)Please build from an IDE')
  if affected then
   local prefix=(engine..'/Engine/'):lower();local cache_segment='/Intermediate/Build/Win64/x64/UnrealGame/Development/';local count=0
   for line in affected:gmatch('[^\r\n]+')do
    local path=line:match('^%s*(.-)%s*$'):gsub('\\','/');assert(path:lower():sub(1,#prefix)==prefix and path:find(cache_segment,1,true) and not path:find('/../',1,true),'Existing file outside the shared Game compile-cache boundary: '..path);count=count+1
   end
   assert(count>0);write(out..'/package-game-cache-review.json',{status='reviewed_game_compile_cache_only',id=id,existing_outputs=count,allowed_engine_prefix=prefix,required_cache_segment=cache_segment,editor_binaries_unchanged_by_this_exception=true,reason='Only Engine and engine-plugin monolithic Game intermediate caches may rebuild; no existing Editor binary is permitted by this exception.'})
   local retry_args={};for _,v in ipairs(build_args)do if v~='-NoEngineChanges' then retry_args[#retry_args+1]=v end end
   r=ok.proc.run(retry_args,{hide=true,cwd=root,stdout_file=build_log..'.retry.stdout',stderr_file=build_log..'.retry.stderr',timeout=3600})
  end
 end
 if r.code~=0 then write(out..'/package.json',{status='failed',phase='isolated_host_build',id=id,engine=engine,host=host,target=target,map_sha256=before,exit_code=r.code,log=build_log,engine_existing_files_protected=true});error('Isolated build stopped: '..build_log)end
end
local log=out..'/package-'..id..'.log';local args={engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/AutomationTool/AutomationTool.dll','BuildCookRun','-project='..host..'/StreetSocialCity.uproject','-nop4','-utf8output','-unattended','-platform=Win64','-clientconfig=Development','-skipbuildeditor','-cook','-skipiostore','-stage','-pak','-archive','-archivedirectory='..target..'/Archive','-stagingdirectory='..target..'/Stage','-map=/Game/UniversityCity/Maps/UniversityCity','-SkipCookingEditorContent','-ubtargs=-WaitMutex','-AdditionalCookerOptions=-SkipZenStore -DDC=(Local) -LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem -ini:Engine:[ConsoleVariables]:Editor.AsyncAssetCompilationMaxMemoryUsage=6'}
write(out..'/package-running.json',{status='running',id=id,engine=engine,host=host,target=target,log=log,map_sha256=before,source_config_sha256=config_before,omitted_android_editor_sections=filtered})
r=ok.proc.run(args,{hide=true,cwd=root,stdout_file=log,stderr_file=out..'/package-'..id..'-stderr.log',timeout=7200})
local unchanged=hash(map)==before and read(out..'/current-map.json').map_sha256==before and hash(source_config)==config_before
write(out..'/package.json',{status=r.code==0 and unchanged and 'built_requires_runtime_validation' or 'failed',id=id,engine=engine,host=host,target=target,log=log,exit_code=r.code,map_sha256=before,source_config_sha256=config_before,omitted_android_editor_sections=filtered,source_map_bytes_and_receipt_unchanged=unchanged,scope='Isolated plugin sources, Windows Config copy without unused Android editor settings, read-only use of original Content junction; new Cooked/Stage/Archive directories, no cleanup or existing stage replacement'})
assert(r.code==0 and unchanged,'Native packaging or source guard failed: '..log);print('Packaged; exact executable and native runtime validation remain required: '..target)
