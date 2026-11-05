-- Process-independent PCSS fallback for SM5; VSM-capable renderers keep VSM.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/day-night-v1'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local function hash(p)local code="[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes('"..p.."'))).Replace('-','').ToLowerInvariant()";local r=ok.proc.run({'powershell.exe','-NoProfile','-Command',code},{capture=true,hide=true});assert(r.code==0);return r.stdout:gsub('%s+','')end
local path=root..'/StreetSocialCity/Config/DefaultEngine.ini';local text=read(path);local before_sha=hash(path);local receipt=json.decode(read(out..'/config-migration.json'));local section=false;local found=false;local seen=false;local old=json.null;local lines={}
for line in (text:gsub('\n$','')..'\n'):gmatch('(.-)\n') do
 local stripped=line:gsub('\r$','');local heading=stripped:match('^%s*(%[.-%])%s*$')
 if heading then
  if section and not seen then lines[#lines+1]='r.Shadow.FilterMethod=1';seen=true end
  section=heading=='[/Script/Engine.RendererSettings]';found=found or section
 end
 local key,value=stripped:match('^%s*([^=]+)=(.-)%s*$')
 if section and key=='r.Shadow.FilterMethod' then assert(old==json.null,'Duplicate filter key');old=value;assert(value=='0' or value=='1','Unexpected existing filter method');lines[#lines+1]='r.Shadow.FilterMethod=1';seen=true else lines[#lines+1]=line end
end
assert(found);if section and not seen then lines[#lines+1]='r.Shadow.FilterMethod=1' end
write(path,table.concat(lines,'\n')..'\n');if receipt.after['r.Shadow.FilterMethod']==nil then receipt.before['r.Shadow.FilterMethod']=old end;receipt.after['r.Shadow.FilterMethod']='1';receipt.after_sha256=hash(path);receipt.pcss_source_before_sha256=before_sha;receipt.note='Recorded renderer keys only. VSM when supported; classic directional PCSS uses the same moon source angle on SM5. Unrelated/private configuration retained without logging.';write(out..'/config-migration.json',json.encode(receipt));print('Scoped PCSS fallback configured; actual renderer verification required.')
