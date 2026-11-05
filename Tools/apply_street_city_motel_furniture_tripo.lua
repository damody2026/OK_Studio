-- Put the 50 motel-furniture Tripo models (motel-furniture-tripo-v2, registered by register_street_city_motel_furniture_tripo.lua)
-- into the room specs (motel-v1/room-specs/batch-NN.json) of the rooms listed in plan.json:
--   sofa  -> key on the first sofa-type seat without a Tripo key (len set to the model width)
--   chair -> key on the first single seat without a key
--   ceiling (chandelier / fan) -> key on the first non-lantern chandelier without a key; none -> one over the living table
--   table -> key on the living table;  lamp -> furnish.side_lamp (on a sofa-end side table)
--   otherwise (or nothing left to replace) -> extras {type:'furniture', key} auto-placed by build_street_city_motel_rooms_v2.lua
-- Every change carries v2=<key> so re-runs are idempotent; the first run backs batch-NN.json up as batch-NN.before-furniture-v2.json.
-- Usage: lua Tools/apply_street_city_motel_furniture_tripo.lua [--dry]   -- prints the affected room ids last
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local lfs=require('lfs')
local base='C:/portable/OpenKoikatsu/output/street-social-city-production'
local spec=base..'/motel-v1/room-specs';local dry=arg[1]=='--dry'
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end
local set=os.getenv('OK_TRIPO_SET') or 'motel-furniture-tripo-v2'
local plan=j.decode(read(base..'/'..set..'/plan.json'))
local reg={};for _,r in ipairs(j.decode(read(base..'/'..set..'/oriented/oriented.json')))do reg[r.key]=r end
-- plan item "replaced_by": another registered model (e.g. a sample-rooms piece) is placed instead of a rejected generation
local all={};for _,r in ipairs(j.decode(read(base..'/motel-v1/sample-rooms/furniture/receipts.json')))do all[r.key]=r end
for _,it in ipairs(plan.items)do if it.replaced_by then
 local r=assert(all[it.replaced_by],'replaced_by not registered: '..it.replaced_by);local own=reg[it.key] or {}
 reg[it.replaced_by]={key=it.replaced_by,category=own.category or 'sofa',size_m=r.size_m or {r.len or 2.0,.95,.9}}
 it.key=it.replaced_by end end
local SOFA={baroque=1,chesterfield=1,modern=1,curved=1}
local want={}  -- room label -> list of plan items
for _,it in ipairs(plan.items)do for _,r in ipairs(it.rooms)do local l=r:find('-',1,true) and r or ('H1-'..r);want[l]=want[l] or {};table.insert(want[l],it)end end
local touched={};local log={}
local files={};for n in lfs.dir(spec)do if n:match('^batch%-%d+%.json$')then files[#files+1]=n end end;table.sort(files)
for _,n in ipairs(files)do
 local path=spec..'/'..n;local doc=j.decode(read(path));local changed=false
 for _,room in ipairs(doc.rooms)do
  local b,num=(room.name or ''):match('^(%S+)%s+(%S+)');local label=b and (b..'-'..num)
  for _,it in ipairs(want[label] or {})do
   local rx=reg[it.key]
   if not rx then log[#log+1]=label..' '..it.key..' not registered (remesh failed?)' else
    local done=false;local cat=rx.category
    local function mark(t)t.v2=it.key;done=true;changed=true;touched[room.id]=label end
    local function already(list)for _,t in ipairs(list or {})do if t.v2==it.key or t.key==it.key then return true end end;return false end
    room.living=room.living or {};local seats=room.living.seats or {}
    if already(seats) or already(room.chandeliers) or already(room.extras) or (room.living.table and room.living.table.key==it.key) or (type(room.furnish)=='table' and room.furnish.side_lamp==it.key) then done=true
    elseif cat=='chair' and rx.size_m[2]>1.1 then
     -- a deep chair (massage recliner) does not fit a lounge-chair slot next to the walk corridor: auto-place it instead
    elseif cat=='sofa' or cat=='chair' then
     for _,s in ipairs(seats)do if not done and not s.key and ((cat=='sofa')==(SOFA[s.kind or 'modern']~=nil)) and s.kind~='heart_booth' then s.key=it.key;if cat=='sofa' then s.len=rx.size_m[1] end
      -- a model much deeper than the seat it replaces (sofa + ottoman in one piece): keep the front edge where the old seat's
      -- was by moving it back by half the excess, and drop the room's own ottomans now inside its footprint
      local excess=rx.size_m[2]-(cat=='sofa' and .95 or .9)
      if excess>.3 then local a=math.rad(s.rot or 0);local fx,fy=math.sin(a),-math.cos(a)
       s.at={s.at[1]-fx*excess/2,s.at[2]-fy*excess/2}
       for k=#seats,1,-1 do local o=seats[k];if o~=s and o.kind=='ottoman' and math.abs(o.at[1]-s.at[1])<rx.size_m[1]/2+.5 and math.abs(o.at[2]-s.at[2])<rx.size_m[2]/2+.5 then table.remove(seats,k)end end
      end
      mark(s) end end
    elseif cat=='ceiling' then
     for _,c in ipairs(room.chandeliers or {})do if not done and not c.key and c.kind~='lantern' then c.key=it.key;mark(c) end end
     if not done then local at=(room.living.table and room.living.table.at) or (room.living.rug and room.living.rug.at) or (seats[1] and seats[1].at)
      if at then room.chandeliers=room.chandeliers or {};local c={kind='arms',at={at[1],at[2]},key=it.key};table.insert(room.chandeliers,c);mark(c) end end
    elseif cat=='table' then
     if room.living.table then room.living.table.key=it.key;mark(room.living.table) end
    elseif cat=='lamp' then
     -- first Tripo lamp on the first sofa-end side table, a second one (another set) on the next side table
     if room.furnish~=false then room.furnish=type(room.furnish)=='table' and room.furnish or {}
      local slot=(room.furnish.side_lamp==nil or room.furnish.side_lamp==it.key) and 'side_lamp' or 'side_lamp2'
      room.furnish[slot]=it.key;room.furnish.v2=it.key;done=true;changed=true;touched[room.id]=label end
    end
    if not done then room.extras=room.extras or {};local e={type='furniture',key=it.key};table.insert(room.extras,e);mark(e) end
    log[#log+1]=label..' '..it.key..' '..cat
   end
  end
 end
 if changed and not dry then
  local bak=spec..'/'..n:gsub('%.json$','.before-furniture-v2.json');if not read(bak) then local f=assert(io.open(bak,'wb'));f:write(read(path));f:close() end
  local f=assert(io.open(path,'wb'));f:write(j.encode(doc));f:close()
 end
end
for _,l in ipairs(log)do print(l)end
local ids={};for id in pairs(touched)do ids[#ids+1]=id end;table.sort(ids)
print('ROOMS '..#ids..': '..table.concat(ids,' '))
