-- Recook changed ground texture assets with the already compiled, isolated E host.
-- Existing Stage/Archive directories remain independent and are never cleaned or moved.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local engine='E:/PhysX/UE5.8';local out=root..'/output/street-social-city-production/day-night-v1';local ground=root..'/output/street-social-city-production/ground-pbr-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(json.encode(d));f:close()end
local prev=read(out..'/package.json');assert(prev.engine==engine and prev.exit_code==0 and prev.source_map_bytes_and_receipt_unchanged)
local audit=read(ground..'/audit.json');local refreshed=read(ground..'/shader.json');local install=read(ground..'/install.json');local finish=read(ground..'/finish.json');local verified=read(ground..'/verify.json');local complete=read(ground..'/complete.json')
assert(audit.status=='passed' and refreshed.status=='passed' and finish.status=='passed' and verified.status=='passed' and complete.status=='passed' and audit.map_sha256==install.map_sha256 and complete.map_sha256==install.map_sha256 and finish.map_sha256==complete.before_map_sha256 and verified.map_sha256==complete.before_map_sha256 and refreshed.map_sha256==finish.before_map_sha256 and (prev.map_sha256==complete.before_map_sha256 or prev.map_sha256==install.map_sha256))
local host=prev.host;assert(host:match('^E:/StreetSocialCityProduction/environment%-packages/%d+%-%d+/HostProject$'))
local build_id=read(engine..'/Engine/Binaries/Win64/UnrealEditor.modules').BuildId
for _,suffix in ipairs({'/Binaries/Win64/UnrealEditor.modules','/Plugins/CityEnvironment/Binaries/Win64/UnrealEditor.modules','/Plugins/CityLocalization/Binaries/Win64/UnrealEditor.modules'})do assert(read(host..suffix).BuildId==build_id,'E host binary version changed')end
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local config=root..'/StreetSocialCity/Config/DefaultEngine.ini';local game_config=root..'/StreetSocialCity/Config/DefaultGame.ini'
local before=hash.sha256_file(map);local config_before=hash.sha256_file(config);local game_before=hash.sha256_file(game_config)
assert(before==install.map_sha256 and before==read(out..'/current-map.json').map_sha256 and config_before==prev.source_config_sha256)
local executable=host..'/Binaries/Win64/StreetSocialCity.exe';local executable_sha=hash.sha256_file(executable)
local listing=ok.proc.run({'rg','--files','StreetSocialCity/Content/UniversityCity/GroundPBRV1'},{capture=true,hide=true});assert(listing.code==0);local assets={}
for file in listing.stdout:gmatch('[^\r\n]+')do file=file:gsub('\\','/');assert(file:match('^StreetSocialCity/Content/UniversityCity/GroundPBRV1/') and not file:find('..',1,true));assets[#assets+1]={file=file,sha256=hash.sha256_file(root..'/'..file)}end
assert(#assets>100,'Ground asset inventory is incomplete')
local id=os.date('%Y%m%d-%H%M%S');local target='E:/StreetSocialCityProduction/environment-packages/'..id
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"if(Test-Path -LiteralPath '"..target.."'){throw 'Target exists'};if(([IO.DriveInfo]::new('E')).AvailableFreeSpace -lt 100GB){throw 'Insufficient space'};New-Item -ItemType Directory -Path '"..target.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
write(ground..'/package-before-grass-refinement.json',prev);write(ground..'/package-source-assets.json',{status='captured',map_sha256=before,assets=assets,package_id=id})
local log=out..'/package-'..id..'.log';local args={engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/AutomationTool/AutomationTool.dll','BuildCookRun','-project='..host..'/StreetSocialCity.uproject','-nop4','-utf8output','-unattended','-platform=Win64','-clientconfig=Development','-skipbuildeditor','-skipbuild','-cook','-iterativecooking','-skipiostore','-stage','-pak','-archive','-archivedirectory='..target..'/Archive','-stagingdirectory='..target..'/Stage','-map=/Game/UniversityCity/Maps/UniversityCity','-SkipCookingEditorContent','-ubtargs=-WaitMutex','-AdditionalCookerOptions=-SkipZenStore -DDC=(Local) -LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem -ini:Engine:[ConsoleVariables]:Editor.AsyncAssetCompilationMaxMemoryUsage=6'}
write(out..'/package-running.json',{status='running_ground_refined_cook',id=id,engine=engine,host=host,target=target,log=log,map_sha256=before,prebuilt_from_package=prev.id})
local r=ok.proc.run(args,{hide=true,cwd=root,stdout_file=log,stderr_file=log..'.stderr',timeout=7200})
local unchanged=hash.sha256_file(map)==before and hash.sha256_file(config)==config_before and hash.sha256_file(game_config)==game_before and hash.sha256_file(executable)==executable_sha
for _,a in ipairs(assets)do assert(hash.sha256_file(root..'/'..a.file)==a.sha256,'Ground source changed during cook: '..a.file)end
write(out..'/package.json',{status=r.code==0 and unchanged and 'built_requires_runtime_validation' or 'failed',engine=engine,id=id,host=host,target=target,log=log,exit_code=r.code,map_sha256=before,source_config_sha256=config_before,source_game_config_sha256=game_before,source_map_bytes_and_receipt_unchanged=unchanged,prebuilt_from_package=prev.id,prebuilt_game_sha256=executable_sha,ground_asset_manifest=ground..'/package-source-assets.json',scope='Fresh cook after generated grass refinement, existing successful isolated E code host, new Stage/Archive; all ground asset hashes unchanged during cook'})
assert(r.code==0 and unchanged,'Ground recook failed: '..log);print('Refined ground package: '..target)
