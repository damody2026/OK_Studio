-- Add the Editor-only audit plugin to the completed isolated E-engine host.
-- No project Content, source Config, installed plugin binary or stage is changed.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local out=root..'/output/street-social-city-production/day-night-v1'
local engine='E:/PhysX/UE5.8'
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'wb'));f:write(json.encode(v));f:close()end
local function q(v)return "'"..v:gsub("'","''").."'" end
local receipt=read(out..'/package.json')
assert(receipt.engine==engine and receipt.status=='built_requires_runtime_validation' and receipt.exit_code==0,'A completed E-engine package is required')
local host=receipt.host
assert(host:match('^E:/StreetSocialCityProduction/environment%-packages/%d+%-%d+/HostProject$'),'Unexpected isolated host')
local plugin='CityDepthAudit'
local script="$ErrorActionPreference='Stop';$reviewHost="..q(host)..";$content=Get-Item -LiteralPath (Join-Path $reviewHost 'Content');if($content.LinkType -ne 'Junction' -or [IO.Path]::GetFullPath(@($content.Target)[0]) -ne [IO.Path]::GetFullPath("..q(root..'/StreetSocialCity/Content')..")){throw 'Unexpected Content junction'};$dst=Join-Path $reviewHost 'Plugins/CityDepthAudit';New-Item -ItemType Directory -Force -Path $dst|Out-Null;foreach($part in @('Source','Config','CityDepthAudit.uplugin')){$src=Join-Path "..q(root..'/StreetSocialCity/Plugins/CityDepthAudit').." $part;if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force}}"
local r=ok.proc.run({'powershell.exe','-NoProfile','-Command',script},{hide=true,cwd=root,timeout=60})
assert(r.code==0,'Review host preparation failed')
local project=host..'/StreetSocialCity.uproject';local data=read(project)
for _,name in ipairs({'CityDepthAudit','PythonScriptPlugin','EditorScriptingUtilities'})do
 local found=false;for _,p in ipairs(data.Plugins)do if p.Name==name then p.Enabled=true;found=true end end
 if not found then data.Plugins[#data.Plugins+1]={Name=name,Enabled=true} end
end
write(project,data)
local log=out..'/review-host-'..receipt.id..'-build.log'
r=ok.proc.run({engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll','StreetSocialCityEditor','Win64','Development','-Project='..project,'-WaitMutex','-NoHotReloadFromIDE','-NoEngineChanges','-log='..log},{hide=true,cwd=root,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=3600})
assert(r.code==0,'E-engine review host build failed: '..log)
local build=read(engine..'/Engine/Binaries/Win64/UnrealEditor.modules').BuildId
for _,name in ipairs({'CityEnvironment','CityLocalization','CityDepthAudit'})do
 assert(read(host..'/Plugins/'..name..'/Binaries/Win64/UnrealEditor.modules').BuildId==build,'Review plugin BuildId mismatch: '..name)
end
write(out..'/review-host.json',{status='passed',engine=engine,project=project,package_id=receipt.id,engine_build_id=build,map_sha256=receipt.map_sha256,exit_code=r.code,log=log,scope='Editor-only diagnostics in isolated E-engine host; original Content junction and source assets retained; completed Stage untouched'})
print('E-engine review host ready: '..project)
