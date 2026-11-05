-- Update only the two canonical O03 coordinate objects, retaining other bytes.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json')
local out='output/street-social-city-production/day-night-v1/'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close()end
local applied=json.decode(read(out..'office_apply.json'))
assert(applied.status=='passed' and applied.map_sha256==json.decode(read(out..'current-map.json')).map_sha256)
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
local receipts={}
for index,path in ipairs({'Docs/StreetSocialCity/production/effective-city-plan.json','Docs/StreetSocialCity/world-terrain-layout.json'})do
 local raw=read(path);local id=assert(raw:find('"id"%s*:%s*"O03"'))
 local begin=assert(raw:sub(1,id):match('.*(){'));local depth,quoted,escape=0,false,false;local finish
 for p=begin,#raw do
  local c=raw:sub(p,p)
  if quoted then if escape then escape=false elseif c=='\\'then escape=true elseif c=='"'then quoted=false end
  elseif c=='"'then quoted=true elseif c=='{'then depth=depth+1 elseif c=='}'then depth=depth-1;if depth==0 then finish=p;break end end
 end
 assert(finish);local part=raw:sub(begin,finish);local before=json.decode(part);assert(before.id=='O03'and before.world_center_m)
 if before.world_center_m.north==335 then
  assert(index==1 or before.center_map_m[2]==765);receipts[#receipts+1]={path=path,already_synced=true}
 else
  assert(before.world_center_m.north==340,'Concurrent coordinate edit: '..path)
  local revised,count=part:gsub('("north"%s*:%s*)([-%d%.]+)',function(prefix,value)assert(tonumber(value)==340);return prefix..'335.0'end);assert(count==1)
  before.world_center_m.north=335
  if index==2 then
   local n;revised,n=revised:gsub('("center_map_m"%s*:%s*%[%s*[%d%.]+%s*,%s*)([%d%.]+)',function(prefix,value)assert(tonumber(value)==760);return prefix..'765.0'end);assert(n==1);before.center_map_m[2]=765
  end
  assert(equal(before,json.decode(revised)),'Unrelated canonical object data changed')
  local updated=raw:sub(1,begin-1)..revised..raw:sub(finish+1);assert(json.decode(updated));assert(read(path)==raw,'Canonical source changed during patch')
  local backup=out..'backups/office-canonical-'..index..'-'..os.date('%Y%m%d-%H%M%S')..'.json';write(backup,raw);write(path,updated)
  receipts[#receipts+1]={path=path,backup=backup,building='O03',world_north_m_before=340,world_north_m_after=335,other_bytes_preserved=true}
 end
end
write(out..'office-canonical-sync.json',json.encode({status='passed',map_sha256=applied.map_sha256,rows=receipts}))
print('O03 canonical coordinates synchronized; unrelated bytes preserved')
