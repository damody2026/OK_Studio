-- Stage already-successful loose-file Cook output into a fresh classic PAK build.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/day-night-v1';local engine='E:/PhysX/UE5.8'
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'wb'));f:write(json.encode(v));f:close()end
local previous=read(out..'/package.json');assert(previous.engine==engine and previous.exit_code==1 and previous.source_map_bytes_and_receipt_unchanged)
local host=previous.host;assert(host:match('^E:/StreetSocialCityProduction/environment%-packages/%d+%-%d+/HostProject$'))
local lf=assert(io.open(previous.log,'rb'));local logtext=lf:read('*a');lf:close();assert(logtext:find('********** COOK COMMAND COMPLETED **********',1,true),'Successful native Cook is required')
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local config=root..'/StreetSocialCity/Config/DefaultEngine.ini';local game_config=root..'/StreetSocialCity/Config/DefaultGame.ini'
assert(hash.sha256_file(map)==previous.map_sha256 and hash.sha256_file(config)==previous.source_config_sha256 and hash.sha256_file(game_config)==previous.source_game_config_sha256)
local game=host..'/Binaries/Win64/StreetSocialCity.exe';assert(hash.sha256_file(game)==previous.prebuilt_game_sha256)
local cook=previous.target..'/Cooked';local cooked_map=cook..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local cooked_sha=hash.sha256_file(cooked_map)
write(out..'/package-E-cook-success-stage-layout-failure.json',previous)
local cf=assert(io.open(host..'/Config/DefaultGame.ini','ab'));cf:write('\n[/Script/UnrealEd.ProjectPackagingSettings]\nbUseIoStore=False\nbUseZenStore=False\nbUsePakFile=True\n');cf:close()
local id=os.date('%Y%m%d-%H%M%S');local target='E:/StreetSocialCityProduction/environment-packages/'..id
local ps="$ErrorActionPreference='Stop';if(Test-Path -LiteralPath '"..target.."'){throw 'Target exists'};New-Item -ItemType Directory -Path '"..target.."/Cooked'|Out-Null;New-Item -ItemType Junction -Path '"..target.."/Cooked/Windows' -Target '"..cook.."'|Out-Null"
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',ps},{hide=true}).code==0)
local log=out..'/package-'..id..'.log'
local receipt={status='running',id=id,engine=engine,host=host,target=target,log=log,map_sha256=previous.map_sha256,source_config_sha256=previous.source_config_sha256,source_game_config_sha256=previous.source_game_config_sha256,prebuilt_from_package=previous.prebuilt_from_package,prebuilt_game_sha256=previous.prebuilt_game_sha256,cook_from_package=previous.id,cook_source=cook,cooked_map_sha256=cooked_sha,packaging='Classic PAK; SkipIoStore; existing successful Cook exposed under a new Windows junction; no previous directory moved or deleted'}
write(out..'/package-running.json',receipt)
local args={engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/AutomationTool/AutomationTool.dll','BuildCookRun','-project='..host..'/StreetSocialCity.uproject','-nop4','-utf8output','-unattended','-platform=Win64','-clientconfig=Development','-skipbuildeditor','-skipcook','-skipiostore','-stage','-pak','-archive','-archivedirectory='..target..'/Archive','-stagingdirectory='..target..'/Stage','-CookOutputDir='..target..'/Cooked'}
local result=ok.proc.run(args,{hide=true,cwd=root,stdout_file=log,stderr_file=log..'.stderr',timeout=3600})
local unchanged=hash.sha256_file(map)==previous.map_sha256 and hash.sha256_file(config)==previous.source_config_sha256 and hash.sha256_file(game_config)==previous.source_game_config_sha256 and hash.sha256_file(game)==previous.prebuilt_game_sha256 and hash.sha256_file(cooked_map)==cooked_sha
receipt.exit_code=result.code;receipt.source_map_bytes_and_receipt_unchanged=unchanged;receipt.status=result.code==0 and unchanged and 'built_requires_runtime_validation' or 'failed';write(out..'/package.json',receipt)
assert(result.code==0 and unchanged,'E-engine staging failed: '..log);print('E-engine staged package ready: '..target)
