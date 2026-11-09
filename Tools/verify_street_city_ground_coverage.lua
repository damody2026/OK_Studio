package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local out='output/street-social-city-production/ground-pbr-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local inv=read(out..'/inventory.json');local install=read(out..'/install.json');local audit=read(out..'/audit.json');local geometry=read(out..'/geometry-floor-upper.json')
assert(audit.status=='passed' and audit.map_sha256==install.map_sha256)
local bound,mat,largest={}, {},{};local slots=0
for _,r in ipairs(install.changes)do local k=r.actor..'::'..r.component..'::'..r.slot;assert(not bound[k],'Duplicate ground override');bound[k]=r end
for _,r in ipairs(inv.materials)do mat[r.path]=r end
local soil=0;local missing={}
for _,c in ipairs(inv.components)do for _,s in ipairs(c.slots)do
 slots=slots+1;local chain=table.concat(mat[s.material].chain,' '):lower()
 if chain:find('street_soil',1,true)then soil=soil+1;if not bound[c.actor..'::'..c.component..'::'..s.slot]then missing[#missing+1]={actor=c.actor,component=c.component,slot=s.slot,reason='planting soil'}end end
end end
for _,r in ipairs(geometry.rows)do if r.actor:match('_F%d+$') and (not largest[r.actor] or r.floor_band_area_m2>largest[r.actor].floor_band_area_m2)then largest[r.actor]=r end end
local floors=0;local floorrows={}
for actor,r in pairs(largest)do
 floors=floors+1;local selected=assert(bound[r.key..'::'..r.slot],'Largest actual upper floor plane has no PBR finish: '..actor)
 if selected.floor_layer then assert(math.abs(selected.floor_z_cm-r.floor_z_cm)<.01,'Floor mask height differs from upper surface: '..actor)end
 floorrows[#floorrows+1]={actor=actor,component=r.component,slot=r.slot,upper_z_cm=r.floor_z_cm,area_m2=r.floor_band_area_m2,material=selected.after,set=selected.set,method=selected.floor_layer and 'height-and-normal floor layer' or 'dedicated ground material'}
end
table.sort(floorrows,function(a,b)return a.actor<b.actor end)
assert(floors==427 and soil==59 and #missing==0 and slots==40392 and #install.changes==audit.material_slot_bindings)
local report={status='passed',map_sha256=install.map_sha256,inventory_component_count=#inv.components,inventory_slot_count=slots,approved_material_overrides=#install.changes,planting_soil_slots=soil,largest_actual_upper_floor_surfaces=floors,unassigned_soil_slots=missing,floors=floorrows,scope='Full-map native material inventory cross-checked against final approved overrides, all canonical planting-soil uses including consolidated landscape, and the actual broad upper slab plane of every floor actor. Furniture, vegetation, water and envelope retain their dedicated shaders.'}
local f=assert(io.open(out..'/coverage.json','wb'));f:write(json.encode(report));f:close();print('Coverage passed: '..slots..' slots inventoried; '..floors..' main upper floors and '..soil..' planting-soil slots accounted for')
