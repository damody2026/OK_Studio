-- Current repaired map, staged D3D12 Game; no Editor SceneCapture.
local f=assert(io.open('Tools/capture_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
local first=assert(source:find('local repair=arg[1]',1,true));local last=assert(source:find('local id=os.date',first,true))
source=source:sub(1,first-1)..[[local repair=false
local installed=read(out..'/install.json');local audit=read(out..'/audit.json');local package=read(envout..'/package.json')
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local mapsha=hash.sha256_file(map)
assert(audit.status=='passed' and package.map_sha256==mapsha and audit.map_sha256==mapsha and installed.map_sha256==mapsha)
local baseline=read(out..'/baseline/captures.json');local cameras={map_sha256=baseline.map_sha256};local views={}
for _,r in ipairs(baseline.images)do
 local eye,target,fov=r.eye,r.target,r.fov
 if r.id=='PK-0105-day'then eye={82800,75150,1371};target={85250,75750,1320};fov=75 end
 if r.id=='PK-0106-day'then eye={86000,75500,1371};target={87500,75500,1280};fov=75 end
 if r.id=='entry-RB-entry-B' or r.id=='entry-IN-entry-A' or r.id=='entry-D4-entry-A'then
  local entry=r.id:sub(7);local points={};for _,t in ipairs(read(root..'/output/street-social-city-production/traffic-v1/campus-audit.json').thresholds)do if t.entry==entry then points[#points+1]=t.ground end end
  local p=points[#points];eye={p[1],p[2],p[3]+165}
 end
 views[#views+1]={id=r.id,site=r.site,eye=eye,target=target,fov=fov,hour=r.hour}
end
views[#views+1]={id='waterfront-night',eye={82800,75150,1371},target={85250,75750,1320},fov=75,hour=21}
local inventory=read(out..'/inventory.json');local candidates={}
for _,r in ipairs(inventory.components)do
 if r.visible and not r.hidden and r.mesh:find('/TreeUpgradeV2/Assets/cypress/',1,true)then
  for _,t in ipairs(r.instances or {r.transform})do candidates[#candidates+1]={actor=r.actor,p=t.translation}end
 end
end
local picked={}
for index,region in ipairs({{52750,89000},{77500,89000},{93200,40000}})do
 local best,score
 for _,c in ipairs(candidates)do local key=table.concat(c.p,',');local d=(c.p[1]-region[1])^2+(c.p[2]-region[2])^2;if not picked[key] and (not score or d<score)then best=c;score=d end end
 assert(best);picked[table.concat(best.p,',')]=true;local x,y,z=table.unpack(best.p)
 for _,hour in ipairs({12,21})do views[#views+1]={id='evergreen-'..index..'-'..hour,eye={x+1050,y+1150,z+165},target={x,y,z+350},fov=70,hour=hour}end
end
local preview=read(out..'/preview/captures.json');assert(preview.status=='captured_requires_visual_review')
for _,r in ipairs(preview.images)do
 if r.id:match('^walk%-') or r.id:match('^campus%-ambience%-') or r.id:match('^lantern%-') or r.id:match('^pond%-close%-') or r.id:match('^bench%-clearance%-')then views[#views+1]={id=r.id,eye=r.eye,target=r.target,fov=r.fov,hour=r.hour}end
end
assert(#views==96,'Expected 96 exterior base views')
local focus=read(out..'/focus/captures.json');assert(focus.status=='captured_requires_visual_review')
for _,r in ipairs(focus.images)do if r.id=='second-waterfront-21' or r.id:match('^interior%-')then views[#views+1]={id=r.id,eye=r.eye,target=r.target,fov=r.fov,hour=r.hour}end end
local moved=0
for _,g in ipairs(read(out..'/environment-feet-install.json').groups)do
 if math.abs(g.old_xy_cm[1]-g.new_xy_cm[1])+math.abs(g.old_xy_cm[2]-g.new_xy_cm[2])>1 then
  moved=moved+1;local p=g.new_xy_cm;local z=g.ground_cm[3]
  for _,hour in ipairs({12,21})do views[#views+1]={id='fixture-shoulder-'..moved..'-'..hour,eye={p[1]+400,p[2]+300,z+165},target={p[1],p[2],z+60},fov=70,hour=hour}end
 end
end
assert(moved==2 and #views==107,'Expected 107 staged inspection views')
local extra=read(out..'/extra-outdoor-cameras.json');assert(extra.status=='passed' and extra.map_sha256==mapsha)
for _,r in ipairs(extra.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-overview-'..hour,site=r.id,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
assert(#views==119,'Expected 119 staged Game views')
local followup=read(out..'/followup-cameras.json');local players=read(out..'/outdoor-player-cameras.json');local quality=read(out..'/quality-cameras.json')
for _,set in ipairs({{prefix='repair-',data=followup,count=22},{prefix='outdoor-player-',data=players,count=20},{prefix='quality-',data=quality,count=8}})do
 assert(set.data.status=='passed' and set.data.map_sha256==mapsha and #set.data.rows==set.count)
 for _,r in ipairs(set.data.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=set.prefix..r.id..'-'..hour,site=r.id,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind or 'supported player-height'}end end
end
assert(#views==219,'Expected 219 staged Game views covering all outdoor sites and interior clearance repairs')
local polish=read(out..'/polish-cameras.json');assert(polish.status=='passed' and polish.map_sha256==mapsha and #polish.rows==46)
for _,r in ipairs(polish.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id='polish-'..r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
local gate;for _,v in ipairs(views)do if v.id=='gate-SouthMain-12'then gate=v;break end end;assert(gate)
for hour=0,24 do views[#views+1]={id='cycle-'..string.format('%02d',hour),eye=gate.eye,target=gate.target,fov=gate.fov,hour=hour%24,cycle_hour=hour,date=(hour==24 and '2026.10.27-' or '2026.10.26-')..string.format('%02d',hour%24)..'.00.00'}end
assert(#views==336,'Expected336 actual staged images,including92 polish comparisons and25 true dated hourly snapshots')
local floors=read(out..'/all-floor-cameras.json');assert(floors.status=='passed' and floors.map_sha256==mapsha and #floors.rows==89)
for _,r in ipairs(floors.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,building=r.building,floor=r.floor,room=r.room,camera_kind=r.camera_kind}end end
assert(#views==514,'Expected514 staged images including every one of89 school floors in day/night')
local moon=read(out..'/moon-cameras.json');assert(moon.status=='passed' and moon.map_sha256==mapsha and #moon.rows==3)
for _,r in ipairs(moon.rows)do views[#views+1]={id=r.id,site=r.site,eye=r.eye,target=r.target,fov=r.fov,hour=r.hour,date=r.date,camera_kind=r.camera_kind}end
assert(#views==517,'Expected517 staged images including three actual moon-framed views')
local park=read(out..'/active-park-current-review.json');assert(park.status=='passed' and park.map_sha256==mapsha and #park.cameras==2)
for _,r in ipairs(park.cameras)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
assert(#views==521,'Expected521 staged images including four level-park approach comparisons')
local mirrors=read(out..'/mirror-cameras.json');assert(mirrors.status=='passed' and mirrors.map_sha256==mapsha and #mirrors.rows==26)
for _,r in ipairs(mirrors.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
assert(#views==573,'Expected573 staged images including mirror reflections and restored connection rails')
]]..source:sub(last)
source=source:gsub('ground%-pbr%-v1','immersion-v1'):gsub('/preservation.json','/preservation-after.json')
source=source:gsub("'%-seconds=900'","'-seconds=3900'"):gsub('timeout=1200','timeout=4200')
source=source:gsub("'set CityEnvironmentController LocalDateTime '%.%.v.date","'set CityEnvironmentController Paused true',defer(3,'set CityEnvironmentController LocalDateTime '..v.date)")
source=source:gsub("assert%(text:find%('BugItGo to:'", "assert(not text:find('missing usage flag InstancedStaticMeshes',1,true) and not text:find('Failed to compile Material',1,true),'Runtime material failure');assert(text:find('BugItGo to:'",1)
source=source:gsub('Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.','Actual repaired staged D3D12 Game:573 images covering34 campus entrances,all20 outdoor player sites,traffic/bridges,day/night repairs,92 polish comparisons and25 real dated hourly snapshots through next-day midnight. Includes day/night supported-player views on all89 school floors. Exact reflected clock; no Editor/Python rendering.')
source=dofile('Tools/street_city_immersion_capture_adapter.lua')(source)
if arg[1]=='mirror-repair' then
 source=source:gsub('local id=os.date',function()return [[local subset={};for _,v in ipairs(views)do
 if v.id:match('^mirror%-') or v.id:match('^connection%-') or v.id:match('^moon%-framed%-') or v.id:match('^floor%-SP%-') or v.id:match('^gate%-SouthMain%-') or v.id:match('^street%-paving%-') or v.id:match('^level%-park%-') then subset[#subset+1]=v end
 end;assert(#subset>=63 and #subset<100);views=subset
 local id=os.date]]end,1)
 source=source:gsub("out%.%.'/captures%-running.json'","out..'/render-repair-running.json'")
 source=source:gsub("write%(out%.%.%(repair and '/captures%-repair.json' or '/captures.json'%),", "write(out..'/render-repair-captures.json',",1)
 source=source:gsub('Actual repaired staged D3D12 Game:573 images.-rendering%.','Targeted final full-cook mirror repair replay; original source map and binary unchanged. Images are independently attributed to this final package; previous non-mirror review remains a separate checkpoint.')
 assert(source:find("write(out..'/render-repair-captures.json',",1,true),'Separate renderer repair receipt required')
end
assert(load(source,'immersion-current-game-capture'))()
