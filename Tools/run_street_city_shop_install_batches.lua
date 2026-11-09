-- Install shop refits in small batches, restarting the E-engine native worker for every batch so its memory
-- (GeometryScripting mesh copies, Interchange imports, thumbnails) never accumulates across the whole street.
-- Usage: lua Tools/run_street_city_shop_install_batches.lua [batch_size] [S02 S03 ...]   (default: every built refit not yet installed)
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local ok=require('ok')
local root='C:/portable/OpenKoikatsu';local o=root..'/output/street-social-city-production/shop-refits-v1';local m=root..'/output/street-social-city-production/motel-v1'
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local r=f:read('*a');f:close();return r end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local size=tonumber(arg[1]) or 12;local ids={}
for i=(tonumber(arg[1]) and 2 or 1),#arg do ids[#ids+1]=arg[i]end
if #ids==0 then
 local done={};local mi=j.decode(read(m..'/motel-install.json') or '{}');for _,id in ipairs(mi.shop_refits or {})do done[id]=true end
 for _,s in ipairs(j.decode(read(o..'/refits-build.json')).shops)do if not done[s.id] then ids[#ids+1]=s.id end end
 table.sort(ids)
end
assert(#ids>0,'nothing to install')
local function editors()local r=ok.proc.run({'powershell.exe','-NoProfile','-Command',[[(Get-Process UnrealEditor -ErrorAction SilentlyContinue | ? { $_.Path -like 'E:\PhysX\*' } | Measure-Object).Count]]},{hide=true});return tonumber((r.stdout or ''):match('%d+')) or 0 end
local function run(args,timeout)return ok.proc.run(args,{cwd=root,hide=true,timeout=timeout})end
print(('installing %d shops in batches of %d'):format(#ids,size))
for b=1,#ids,size do
 local batch={};for k=b,math.min(#ids,b+size-1)do batch[#batch+1]=ids[k]end
 assert(editors()==0,'another UnrealEditor is running; stop it before installing')
 write(o..'/install-batch.json',j.encode({ids=batch}))
 -- launch the worker detached, then wait for its ready receipt
 os.execute('start "" /B "'..root..'/Tools/lua/lua.exe" Tools/street_city_motel_native.lua serve > "'..o..'/serve-batch-'..b..'.log" 2>&1')
 local ready=false
 for _=1,900 do
  local r,p=j.decode(read(m..'/serve-ready.json') or '{}'),j.decode(read(m..'/serve-payload.json') or '{}')
  if r.status=='passed' and r.run_id==p.run_id and r.run_id and r.run_id:match('^serve%-')then ready=true;break end
  run({'powershell.exe','-NoProfile','-Command','Start-Sleep -Seconds 2'},10)
 end
 assert(ready,'worker did not become ready')
 local res=run({root..'/Tools/lua/lua.exe','Tools/street_city_motel_job.lua','shop_refits_install','Tools/street_city_shop_samples_payload.lua'},2000)
 run({root..'/Tools/lua/lua.exe','Tools/street_city_motel_job.lua','quit'},600)
 for _=1,120 do if editors()==0 then break end;run({'powershell.exe','-NoProfile','-Command','Start-Sleep -Seconds 2'},10)end
 assert(res.code==0,'batch failed: '..table.concat(batch,' ')..'\n'..(res.stderr or res.stdout or ''))
 print('installed '..table.concat(batch,' '))
end
