-- Reuse a successfully compiled E-engine host after an Editor startup-content cook error.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local out=root..'/output/street-social-city-production/day-night-v1';local engine='E:/PhysX/UE5.8'
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'wb'));f:write(json.encode(v));f:close()end
local previous=read(out..'/package.json');assert(previous.engine==engine and previous.exit_code==25 and previous.source_map_bytes_and_receipt_unchanged)
local host=previous.host;assert(host:match('^E:/StreetSocialCityProduction/environment%-packages/%d+%-%d+/HostProject$'))
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
local config=root..'/StreetSocialCity/Config/DefaultEngine.ini';local game_config=root..'/StreetSocialCity/Config/DefaultGame.ini'
local before=hash.sha256_file(map);local config_before=hash.sha256_file(config);local game_before=hash.sha256_file(game_config)
assert(before==previous.map_sha256 and before==read(out..'/current-map.json').map_sha256 and config_before==previous.source_config_sha256)
local game=host..'/Binaries/Win64/StreetSocialCity.exe';local gf=assert(io.open(game,'rb'));assert(gf:seek('end')>1000000);gf:close()
local build_log=out..'/package-'..previous.id..'-StreetSocialCity-build.log'
local bf=assert(io.open(build_log,'rb'));local build=bf:read('*a');bf:close();assert(build:find('Result: Succeeded',1,true),'Previous native Game build did not succeed')
local proof=read(out..'/package-source-review.json');assert(proof.package_id==previous.id and proof.engine==engine)
for _,r in ipairs(proof.rows)do
 local file=r.file:gsub('\\','/');assert(not file:find('..',1,true))
 assert(hash.sha256_file(host..'/Plugins/'..file)==r.sha256 and hash.sha256_file(root..'/StreetSocialCity/Plugins/'..file)==r.sha256,'Runtime source changed since successful build')
end
local baseline=read(out..'/inventory-baseline.json')
for _,a in ipairs(baseline.actors)do local c=a.object_class:lower();assert(not c:find('landmass',1,true) and not c:find('landscape',1,true) and not c:find('waterbody',1,true),'Landscape/water-brush runtime actor requires review')end
local context=read(out..'/post-office-ground-scan-source.json');local scene=read(out..'/'..context.scene_folder..'/scene.json')
assert(hash.sha256_file(out..'/'..context.scene_folder..'/scene.json')==context.metadata_sha256)
local function check(path)assert(not path:match('^/Landmass/') and not path:match('^/Water/'),'Runtime plugin content dependency requires review')end
for _,m in ipairs(scene.meshes)do check(m.asset)end
for _,i in ipairs(scene.instances)do for _,m in ipairs(i.materials)do if type(m)=='string' then check(m)end end end
write(out..'/package-E-landmass-failure.json',previous)
local copied=host..'/Config/DefaultGame.ini';local cf=assert(io.open(copied,'ab'))
cf:write('\n[/Script/UnrealEd.ProjectPackagingSettings]\n+DirectoriesToNeverCook=(Path="/Landmass/Landscape/BlueprintBrushes/Materials/Internal")\n+DirectoriesToNeverCook=(Path="/Landmass/Landscape/BlueprintBrushes/Materials/Sprite")\n');cf:close()
local id=os.date('%Y%m%d-%H%M%S');local target='E:/StreetSocialCityProduction/environment-packages/'..id
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"if(Test-Path -LiteralPath '"..target.."'){throw 'Target exists'};if(([IO.DriveInfo]::new('E')).AvailableFreeSpace -lt 100GB){throw 'Insufficient staging space'};New-Item -ItemType Directory -Path '"..target.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
local log=out..'/package-'..id..'.log'
local receipt={status='running',id=id,engine=engine,host=host,target=target,log=log,map_sha256=before,source_config_sha256=config_before,source_game_config_sha256=game_before,prebuilt_from_package=previous.id,prebuilt_game_sha256=hash.sha256_file(game),cook_exclusion='Two unused Landmass Editor brush material directories; E source Landmass/Source/Editor/Private/LandmassActor.cpp preloads them only for editor gizmos. Original project, enabled plugins and runtime dependencies unchanged.'}
write(out..'/package-running.json',receipt);write(out..'/package-editor-content-fix.json',receipt)
local args={engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/AutomationTool/AutomationTool.dll','BuildCookRun','-project='..host..'/StreetSocialCity.uproject','-nop4','-utf8output','-unattended','-platform=Win64','-clientconfig=Development','-skipbuildeditor','-cook','-stage','-pak','-archive','-archivedirectory='..target..'/Archive','-stagingdirectory='..target..'/Stage','-CookOutputDir='..target..'/Cooked','-map=/Game/UniversityCity/Maps/UniversityCity','-SkipCookingEditorContent','-ubtargs=-WaitMutex','-AdditionalCookerOptions=-SkipZenStore -DDC=(Local) -LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem -ini:Engine:[ConsoleVariables]:Editor.AsyncAssetCompilationMaxMemoryUsage=6'}
local r=ok.proc.run(args,{hide=true,cwd=root,stdout_file=log,stderr_file=log..'.stderr',timeout=7200})
local unchanged=hash.sha256_file(map)==before and hash.sha256_file(config)==config_before and hash.sha256_file(game_config)==game_before and hash.sha256_file(game)==receipt.prebuilt_game_sha256
receipt.exit_code=r.code;receipt.source_map_bytes_and_receipt_unchanged=unchanged;receipt.status=r.code==0 and unchanged and 'built_requires_runtime_validation' or 'failed';write(out..'/package.json',receipt)
assert(r.code==0 and unchanged,'E-engine recook failed: '..log)
print('E-engine package completed: '..target)
