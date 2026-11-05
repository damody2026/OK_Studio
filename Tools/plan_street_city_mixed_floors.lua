package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local out='output/street-social-city-production/ground-pbr-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local geo=read(out..'/geometry-floor-bands.json');local inv=read(out..'/inventory.json');local installed=read(out..'/install.json');local catalog=read(out..'/catalog.json');local scene=read('output/street-social-city-production/day-night-v1/surface-final/scene.json')
local old,materials,sets,sided={},{},{},{}
for _,r in ipairs(installed.changes)do old[r.actor..'::'..r.component..'::'..r.slot]=r end
for _,r in ipairs(inv.materials)do materials[r.path]=r end
for _,r in ipairs(catalog.sets)do sets[r.family]=sets[r.family] or {};table.insert(sets[r.family],r)end
for _,r in ipairs(scene.instances)do for i,v in ipairs(r.two_sided_by_slot)do sided[r.key..'::'..(i-1)]=v end end
local rows,coverage,all={}, {},{};local area=0
for _,r in ipairs(geo.rows)do
 if r.actor:match('_F%d+$')then
  all[r.actor]=true
  if r.floor_band_area_m2>4 then
   local key=r.key..'::'..r.slot;coverage[r.actor]=true
   if not old[key]then
    local mat=assert(materials[r.material]);local text=table.concat(mat.chain,' '):lower();assert(not text:find('glass',1,true) and not text:find('water',1,true),'Transparent floor requires separate design')
    local family='interior_terrazzo'
    if text:find('oak',1,true) or text:find('wood',1,true)then family='timber_deck'
    elseif text:find('travertine',1,true) or text:find('stone',1,true)then family='limestone_path'
    elseif r.actor:match('^City_[HO]') or r.actor:match('^S%d+')then family='interior_porcelain'end
    local building=r.actor:gsub('_F%d+$','');local hash=0;for i=1,#building do hash=(hash*31+building:byte(i))%1000003 end;local set=sets[family][hash%3+1]
    rows[#rows+1]={actor=r.actor,component=r.component,slot=r.slot,before=r.material,mesh=r.mesh,set=set.id,family=family,period_cm=set.period_m*100,seed=(hash%10000)/100,two_sided=sided[key],floor_z_cm=r.floor_z_cm,floor_band_area_m2=r.floor_band_area_m2,floor_layer=true}
    area=area+r.floor_band_area_m2
   end
  end
 end
end
local total,covered=0,0;for actor in pairs(all)do total=total+1;assert(coverage[actor],'Floor plane not accounted for: '..actor)end;for _ in pairs(coverage)do covered=covered+1 end
assert(total==427 and covered==427)
local f=assert(io.open(out..'/mixed-floor-plan.json','wb'));f:write(json.encode({status='reviewed',map_sha256=installed.map_sha256,source_geometry_sha256=geo.scene_sha256,floor_actors=total,covered_floor_actors=covered,additional_slots=#rows,additional_floor_area_m2=area,method='Largest upward horizontal plane in the lowest metre of each actual floor component, quantized to 1mm. A normal-and-height shader mask affects only this floor plane; shared wall/furniture shader inputs are preserved.',rows=rows}));f:close();print('Mixed floor slots '..#rows..'; all '..covered..' floor actors accounted for; '..math.floor(area)..' square metres')
