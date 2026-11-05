-- Keep the geometry/collision source ledgers immutable; record authorized material overrides separately.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash');local ground='output/street-social-city-production/ground-pbr-v1';local envout='output/street-social-city-production/day-night-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(json.encode(d));f:close()end
local installed=read(ground..'/install.json');local audit=read(ground..'/audit.json');assert(audit.status=='passed' and audit.map_sha256==installed.map_sha256)
local overrides={};for _,r in ipairs(installed.changes)do overrides[r.actor..'::'..r.component..'::'..r.slot]=r end
local snapshots={};for _,r in ipairs(read(ground..'/preservation.json').after)do snapshots[r.actor..'::'..r.component]=r end
local receipts={}
for _,name in ipairs({'street-surface-install','tactile-surface-install'})do
 local source=envout..'/'..name..'.json';local ledger=read(source);assert(ledger.status=='passed');local changed={}
 for _,r in ipairs(ledger.changes)do
  local key=r.actor..'::'..r.component;local snap=assert(snapshots[key])
  for i,path in ipairs(r.effective_materials)do
   local override=overrides[key..'::'..(i-1)]
   if override then assert(path==override.before,'Source material ledger does not match the authorized before binding');r.effective_materials[i]=override.after;changed[#changed+1]={actor=r.actor,component=r.component,slot=i-1,before=path,after=override.after}end
   assert(r.effective_materials[i]==snap.materials[i],'Runtime expected material differs from reopened native audit')
  end
 end
 ledger.ground_override_source_sha256=hash.sha256_file(source);ledger.ground_override_map_sha256=installed.map_sha256;ledger.ground_material_overrides=changed;ledger.ground_scope='Only effective material expectations updated from the independently reopened ground audit. Original geometry, matrix, instance, collision and visibility ledger fields unchanged.'
 local dest=ground..'/'..name..'-runtime.json';write(dest,ledger);receipts[#receipts+1]={source=source,source_sha256=ledger.ground_override_source_sha256,runtime_ledger=dest,material_overrides=#changed}
end
write(ground..'/runtime-ledger-provenance.json',{status='passed',map_sha256=installed.map_sha256,rows=receipts})
if arg[1]=='prepare' then print('Authorized ground runtime material expectations prepared; original geometry ledgers unchanged');return end
local f=assert(io.open('Tools/run_street_city_environment_game.lua','rb'));local script=f:read('*a');f:close()
for _,name in ipairs({'street-surface-install','tactile-surface-install'})do
 local needle="out..'/"..name..".json'";local replacement="root..'/"..ground..'/'..name.."-runtime.json'";local n;script,n=script:gsub(needle:gsub('(%W)','%%%1'),function()return replacement end);assert(n==2,'Runtime ledger argument replacements')
end
assert(load(script,'ground-material-native-runtime'))()
