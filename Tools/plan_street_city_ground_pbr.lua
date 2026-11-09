-- Offline, complete slot-by-slot classification against the native full-map inventory.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json')
local out='output/street-social-city-production/ground-pbr-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local function write(name,d)local f=assert(io.open(out..'/'..name..'.json','wb'));f:write(json.encode(d));f:close()end
local inv=read(out..'/inventory.json');local geo=read(out..'/geometry-inventory.json');local cat=read(out..'/catalog.json')
local native_scene=read('output/street-social-city-production/day-night-v1/surface-final/scene.json');local sided={}
for _,r in ipairs(native_scene.instances)do for i,v in ipairs(r.two_sided_by_slot)do local k=r.key..'::'..(i-1);if sided[k]~=nil then assert(sided[k]==v,'Instance culling disagreement')end;sided[k]=v end end
local mats={};for _,m in ipairs(inv.materials)do mats[m.path]=m end
local metrics={};for _,r in ipairs(geo.rows)do local k=r.key..'::'..r.slot;local q=metrics[k] or {up=0,down=0,triangles=0};q.up=q.up+r.upward_surface_m2;q.down=q.down+r.downward_surface_m2;q.triangles=q.triangles+r.triangles;metrics[k]=q end
local roles={};local old=read('output/street-social-city-production/romance-pbr-v1/plan.json')
for _,r in ipairs(old.decisions)do if r.action=='override' and (r.role=='floor' or r.role=='stairs')then roles[r.actor..'::'..r.component..'::'..r.slot]=r.role end end
local function has(s,p)return s:find(p,1,true)~=nil end
local function classify(c,s,m)
 local a=c.actor;local text=table.concat(m.chain,' '):lower();local key=a..'::'..c.component..'::'..s.slot
 if c.instances==0 then return nil,'empty source component; active replacement chunks classified separately' end
 if a:match('^G%d+_Water$') or has(text,'m_ocean') or has(text,'water') or has(text,'glass') then return nil,'water or glass; retained dedicated transparency and lighting' end
 if a:match('^G%d+$')then
  if has(text,'grass')then return 'meadow_grass','full terrain turf' end
  if has(text,'asphalt')then return 'asphalt','vehicular asphalt' end
  if has(text,'riverbank')then return 'river_gravel','riverbank sediment and gravel' end
  if has(text,'sand')then return 'beach_sand','sandy ground' end
  if has(text,'urban')then return 'pedestrian_pavers','urban pedestrian surface' end
  if has(text,'campus')then return 'campus_concrete','campus circulation ground' end
  return false,'unresolved terrain material chain'
 end
 if has(text,'street_soil')then return 'planting_soil','all-map planting soil, including consolidated landscape planters' end
 if a:match('^DepthStableTactile_') or a:match('^Street_tactile_')then return 'tactile_paving','tactile micrograin; existing raised geometry retained' end
 if a:match('^DepthStableStreet_') or a:match('^Street_paving_') or a:match('^Street_curb_')then
  if has(text,'ivory')then return 'limestone_path','paving joint/edge finish' end
  return 'pedestrian_pavers','street pavers and curb stone'
 end
 if a:match('^Street_lane_dash_') or a:match('^Street_crosswalk_') or a:match('^Street_parking_mark_')then return 'campus_concrete','road marking paint; white recolour retains legibility',{.83,.83,.78} end
 if a:match('^OfficeSetback_')then return 'limestone_path','picnic access ramp and side deck' end
 if a:match('^World_PK_') or a:match('^Outdoor_')then
  if has(text,'m_32148') or has(text,'m_19f4') or has(text,'grass') or has(text,'pitch.')then return 'lawn_turf','park/campus lawn or sports turf' end
  if has(text,'sand.')then return 'beach_sand','sand activity surface' end
  if has(text,'rubber')then return 'rubber_track','rubber running track; line geometry preserved' end
  if has(text,'court') or has(text,'tennis.') or has(text,'/blue.')then return 'acrylic_court','sports acrylic; preserve source court colour',has(text,'tennis.') and {.075,.28,.13} or (has(text,'court') and {.05,.19,.22} or {.06,.2,.4}) end
  if has(text,'white_001') or has(text,'outdoor_white')then return 'campus_concrete','sports marking paint; preserve white',{.84,.85,.79} end
  if has(text,'walk.') or has(text,'outdoor_stone')then return 'limestone_path','park/campus paved paths and platform finish' end
  if has(text,'outdoor_tile')then return 'terracotta_paving','outdoor tile decking' end
  if has(text,'outdoor_wood') or has(text,'/wood.')then return 'timber_deck','outdoor timber, shared with matching timber site furniture' end
  if has(text,'solidprop_e031232')then return 'limestone_path','closed campus path solid; verified source walk material' end
  if has(text,'roof') or has(text,'steel') or has(text,'metal') or has(text,'net') or has(text,'light') or has(text,'orange') or has(text,'fabric')then return nil,'site furnishing, roof, structural metal or fixture' end
  if has(text,'tripo_material')then return nil,'separate imported furnishing/vegetation asset; not the metric site ground' end
  return false,'unresolved outdoor material chain'
 end
 if roles[key] or (has(text,'/romancepbr/') and (has(s.material,'_floor.') or has(s.material,'_stairs.')))then
  local inputs=m.graphs.basecolor or {};local t=text
  for _,n in ipairs(inputs)do if n.texture then t=t..' '..n.texture:lower()end end
  for _,n in ipairs(m.texture_overrides)do if type(n.texture)=='string'then t=t..' '..n.texture:lower()end end
  if has(t,'wood') or has(t,'teak') or has(t,'oak')then return 'timber_deck','building floor/step: timber' end
  if has(t,'terracotta')then return 'terracotta_paving','building floor/step: terracotta' end
  if has(t,'terrazzo')then return 'interior_terrazzo','building floor/step: terrazzo' end
  if has(t,'stone') or has(t,'travertine')then return 'limestone_path','building floor/step: honed stone' end
  return 'interior_porcelain','building floor/step: matte porcelain'
 end
 return nil,'not a ground/floor slot: building envelope, furnishing, vegetation, sign, light or utility'
end
local sets={};for _,s in ipairs(cat.sets)do sets[s.family]=sets[s.family] or {};table.insert(sets[s.family],s)end
local decisions,counts,blocked={}, {},{};local compcount,slotcount,selected=0,0,0
for _,c in ipairs(inv.components)do
 compcount=compcount+1
 for _,s in ipairs(c.slots)do
  slotcount=slotcount+1;local m=assert(mats[s.material]);local family,reason,recolor=classify(c,s,m);local k=c.actor..'::'..c.component..'::'..s.slot;local metric=metrics[k] or {up=0,down=0,triangles=0}
  local r={actor=c.actor,component=c.component,slot=s.slot,before=s.material,mesh=c.mesh,instances=c.instances,collision=c.collision,action=family and 'replace' or 'preserve',reason=reason,upward_area_m2=metric.up,downward_area_m2=metric.down,triangles=metric.triangles}
  if family==false then table.insert(blocked,r) end
  if family then
   -- Connected terrain tiles and street chunks share world coordinates, set and seed.
   -- Choosing a new palette at every chunk would recreate the reported colour blocks.
   local region=(c.actor:match('^G%d+$') or c.actor:match('^DepthStable') or c.actor:match('^Street_paving_') or c.actor:match('^Street_curb_') or c.actor:match('^Street_tactile_')) and 'continuous-world' or c.actor:gsub('_F%d+$','')
   local hash=0;local sample_key=region..'::'..family;for i=1,#sample_key do hash=(hash*31+sample_key:byte(i))%1000003 end
   local set=assert(sets[family])[hash%3+1];r.family=family;r.set=set.id;r.period_cm=set.period_m*100;r.seed=(hash%10000)/100;r.recolor=recolor;r.two_sided=sided[k];if r.two_sided==nil then r.two_sided=m.two_sided end
   selected=selected+1;counts[family]=(counts[family] or 0)+1
  end
  table.insert(decisions,r)
 end
end
write('plan',{status=#blocked==0 and 'reviewed_ready_for_generation' or 'blocked',map_sha256=inv.map_sha256,scene_sha256=geo.scene_sha256,component_count=compcount,slot_count=slotcount,selected_slot_count=selected,counts=counts,blocked=blocked,decisions=decisions,scope='Full native city inventory classified slot by slot. All terrain, outdoor metric ground, soil, street surfaces, tactile, marking paint and known building floor/step slots. Imported furnishings, water, vegetation and envelope explicitly retained.'})
print('Components '..compcount..'; slots '..slotcount..'; replacements '..selected..'; unresolved '..#blocked)
for k,v in pairs(counts)do print(k..': '..v)end
assert(#blocked==0,'Review unresolved outdoor/terrain slots before installation')
