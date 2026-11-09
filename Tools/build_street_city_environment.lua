package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json')
local plugin=arg[1] or 'CityEnvironment';assert(plugin=='CityEnvironment' or plugin=='CityDepthAudit')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local engine='E:/PhysX/UE5.8';local out=root..'/output/street-social-city-production/day-night-v1'
assert(os.execute('powershell.exe -NoProfile -Command "New-Item -ItemType Directory -Force -Path \''..out..'\' | Out-Null"'))
local source=root..'/StreetSocialCity/Plugins/'..plugin;local package='E:/StreetSocialCityProduction/plugin-builds/'..plugin..'-'..os.date('%Y%m%d-%H%M%S')
if arg[2]=='reuse' then
 local f=assert(io.open(out..'/'..plugin..'-build.json','rb'));local receipt=json.decode(f:read('*a'));f:close();package=receipt.package:gsub('\\','/');assert(package:match('^E:/StreetSocialCityProduction/plugin%-builds/'..plugin..'%-%d+%-%d+$'),'Unexpected build reuse target')
end
local function q(v)return "'"..v:gsub("'","''").."'" end
local host=package..'/HostProject'
local function ps(code)assert(os.execute('powershell.exe -NoProfile -Command "$ErrorActionPreference=\'Stop\';'..code..'"'))end
ps("New-Item -ItemType Directory -Force -Path "..q(host..'/Plugins/'..plugin).." | Out-Null; foreach($name in @('"..plugin.."','CityLocalization')){$src=Join-Path "..q(root..'/StreetSocialCity/Plugins').." $name; $dest=Join-Path "..q(host..'/Plugins').." $name; New-Item -ItemType Directory -Force -Path $dest|Out-Null; foreach($part in @('Source','Config',($name+'.uplugin'))){$p=Join-Path $src $part;if(Test-Path -LiteralPath $p){Copy-Item -LiteralPath $p -Destination $dest -Recurse -Force}}}; @{FileVersion=3;Plugins=@(@{Name='"..plugin.."';Enabled=$true},@{Name='CityLocalization';Enabled=$true})}|ConvertTo-Json -Depth 4|Set-Content -Encoding UTF8 -LiteralPath "..q(host..'/HostProject.uproject'))
local targets={{'UnrealEditor','Development'}}
if plugin=='CityEnvironment' then targets[#targets+1]={'UnrealGame','Development'};targets[#targets+1]={'UnrealGame','Shipping'} end
local logs={}
for _,t in ipairs(targets)do
 local log=out..'/'..plugin..'-'..t[1]..'-'..t[2]..'-build.log';logs[#logs+1]=log
 local r=ok.proc.run({engine..'/Engine/Binaries/ThirdParty/DotNet/10.0/win-x64/dotnet.exe',engine..'/Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll',t[1],'Win64',t[2],'-Project='..host..'/HostProject.uproject','-plugin='..host..'/Plugins/'..plugin..'/'..plugin..'.uplugin','-WaitMutex','-NoHotReloadFromIDE','-noubtmakefiles','-log='..log},{cwd=root,hide=true})
 assert(r.code==0,plugin..' '..t[1]..' failed: '..tostring(r.code)..'; '..log)
end
local deferred=arg[3]=='defer-copy'
if not deferred then ps("foreach($d in @('Binaries','Intermediate')){$from=Join-Path "..q(host..'/Plugins/'..plugin).." $d;if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination "..q(source).." -Recurse -Force}}") end
local f=assert(io.open(out..'/'..plugin..'-build.json','wb'));f:write(json.encode({status=deferred and 'built_requires_install' or 'passed',installed=not deferred,plugin=plugin,package=package,exit_code=0,targets=targets,logs=logs,mutex='WaitMutex;never stop other builds'}));f:close();print(plugin..(deferred and ' built; copy deferred while validation editor is running' or ' built'))
