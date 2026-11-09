-- Copy this task's verified editor code only while its private host is stopped.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1';local base='E:/StreetSocialCityProduction/environment-packages/'
local source=base..'20261023-145531/HostProject/Plugins/CityEnvironment';local target=base..'20261023-122745/HostProject/Plugins/CityEnvironment'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local build=j.decode(read(out..'/native-audit-build/build.json'));assert(build.status=='passed' and build.engine=='E:/PhysX/UE5.8')
local guard="$p=Get-CimInstance Win32_Process | Where-Object { $_.Name -like '*UnrealEditor*' -and $_.CommandLine -like '*20261023-122745*' };if($p){throw 'Private host still running'};foreach($t in @('"..source.."','"..target.."')){if((Get-Item -LiteralPath $t).LinkType){throw 'Expected physical plugin directory'}}"
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',guard},{hide=true}).code==0)
assert(j.decode(read(source..'/Binaries/Win64/UnrealEditor.modules')).BuildId==j.decode(read(target..'/Binaries/Win64/UnrealEditor.modules')).BuildId)
local id=os.date('%Y%m%d-%H%M%S');local backup=out..'/private-code-backup-'..id
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..backup.."'|Out-Null"},{hide=true}).code==0)
local rows={}
for _,r in ipairs(build.source_files)do
 local rel='/Source/CityEnvironment/Private/'..r.file;assert(h.sha256_file(source..rel)==r.sha256);local f=io.open(target..rel,'rb');if f then f:close();write(backup..'/'..r.file,read(target..rel))end;write(target..rel,read(source..rel));assert(h.sha256_file(target..rel)==r.sha256);rows[#rows+1]={file=rel,sha256=r.sha256}
end
for _,name in ipairs({'UnrealEditor-CityEnvironment.dll','UnrealEditor-CityEnvironment.pdb'})do
 local rel='/Binaries/Win64/'..name;local f=io.open(source..rel,'rb');if f then f:close();write(backup..'/'..name,read(target..rel));write(target..rel,read(source..rel));assert(h.sha256_file(target..rel)==h.sha256_file(source..rel));rows[#rows+1]={file=rel,sha256=h.sha256_file(source..rel)}end
end
write(out..'/private-code-sync.json',j.encode({status='passed',source=source,target=target,backup=backup,files=rows,policy='Private editor verified stopped; same E engine module build ID; only this task runtime code/binaries copied, prior files retained.'}))
local ready=j.decode(read(out..'/serve-ready.json'));ready.status='stopped';write(out..'/serve-ready.json',j.encode(ready));print('Private host code updated while stopped; prior code backed up.')
