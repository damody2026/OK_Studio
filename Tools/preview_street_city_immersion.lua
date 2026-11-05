-- Uncooked native Game preview for iteration. This is explicitly separate from
-- the final staged-game acceptance and never replaces its capture receipt.
assert(not arg[1] or arg[1]=='focus' or arg[1]=='detail' or arg[1]=='repair' or arg[1]=='groundcheck' or arg[1]=='layout' or arg[1]=='polish' or arg[1]=='floors' or arg[1]=='mirrors' or arg[1]=='all_current','Use focus, detail, repair, groundcheck, layout,polish or floors for bounded follow-up inspection')
local f=assert(io.open('Tools/capture_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
local first=assert(source:find('local repair=arg[1]',1,true));local last=assert(source:find('local id=os.date',first,true))
source=source:sub(1,first-1)..[[local repair=false
local mainout=root..'/output/street-social-city-production/immersion-v1';local installed=read(mainout..'/install.json')
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local mapsha=hash.sha256_file(map);assert(installed.map_sha256==mapsha)
local project='E:/StreetSocialCityProduction/environment-packages/20261023-122745/HostProject/StreetSocialCity.uproject'
local package={id='uncooked-source-'..os.date('%Y%m%d-%H%M%S'),engine='E:/PhysX/UE5.8'};local cameras={map_sha256=installed.before_map_sha256};local views={}
local previous=read(mainout..'/captures.json')
for _,r in ipairs(previous.images)do
 if r.id:match('^entry%-') or r.id:match('^evergreen%-') or r.id:match('^gate%-') or r.id=='PK-0102-day' or r.id=='PK-0105-day' or r.id=='PK-0103-day' or r.id=='PK-0104-day' then
  local eye=r.eye;local target=r.target;local fov=r.fov
  if r.id=='PK-0105-day'then eye={82800,75150,1371};target={85250,75750,1320};fov=75 end
  if r.id=='entry-RB-entry-B' or r.id=='entry-IN-entry-A' or r.id=='entry-D4-entry-A'then
   local entry=r.id:sub(7);local points={};for _,t in ipairs(read(root..'/output/street-social-city-production/traffic-v1/campus-audit.json').thresholds)do if t.entry==entry then points[#points+1]=t.ground end end
   local p=points[#points];eye={p[1],p[2],p[3]+165}
  end
  views[#views+1]={id=r.id,eye=eye,target=target,fov=fov,hour=r.hour}
 end
end
local gate;for _,v in ipairs(views)do if v.id=='gate-SouthMain-12'then gate=v;break end end;assert(gate)
for _,hour in ipairs({0,6,7,17,18})do views[#views+1]={id='campus-ambience-'..hour,eye=gate.eye,target=gate.target,fov=gate.fov,hour=hour}end
views[#views+1]={id='waterfront-night',eye={82800,75150,1371},target={85250,75750,1320},fov=75,hour=21}
local paths=read(mainout..'/campus-route-plan.json');local fixture=read(mainout..'/path-lamps.json');local used={};local selected=0
for _,lamp in ipairs(fixture.fixtures)do
 if not used[lamp.route] and selected<3 then
  used[lamp.route]=true;selected=selected+1
  for _,route in ipairs(paths.routes)do if route.id==lamp.route then
   local index,best
   for i,p in ipairs(route.points_cm)do local d=(p[1]-lamp.position_cm[1])^2+(p[2]-lamp.position_cm[2])^2;if not best or d<best then index=i;best=d end end
   local p=route.points_cm[index];local j=math.min(#route.points_cm,index+12);if j-index<3 then j=math.max(1,index-12)end;local q=route.points_cm[j]
   for _,hour in ipairs({12,21})do views[#views+1]={id='walk-'..selected..'-'..hour,eye={p[1],p[2],1371},target={q[1],q[2],1330},fov=75,hour=hour}end
  end end
 end
end
if io.open(mainout..'/lantern-install.json','rb')then
 local chosen={}
 for _,lamp in ipairs(read(mainout..'/lantern-install.json').fixtures)do
  local p=lamp.head_cm;local far=true;for _,q in ipairs(chosen)do if (p[1]-q[1])^2+(p[2]-q[2])^2<8000^2 then far=false end end
  if #chosen<3 and far and p[1]>54800 and p[1]<97000 and p[2]>19500 and p[2]<77000 then
   chosen[#chosen+1]=p;for _,hour in ipairs({12,21})do views[#views+1]={id='lantern-'..#chosen..'-'..hour,eye={p[1]+400,p[2]+300,1371},target=p,fov=70,hour=hour}end
  end
 end
 assert(#chosen==3)
end
for _,hour in ipairs({12,21})do
 views[#views+1]={id='pond-close-'..hour,eye={84600,75750,1371},target={85100,75750,1250},fov=75,hour=hour}
 views[#views+1]={id='bench-clearance-'..hour,eye={89550,76200,1371},target={90000,76650,1240},fov=70,hour=hour}
end
assert(#views==72,'Expected 72 native preview views')
if arg[1]=='focus' then
 local wanted={['PK-0102-day']=true,['PK-0105-day']=true,['waterfront-night']=true,['pond-close-12']=true,['pond-close-21']=true,['bench-clearance-12']=true,['bench-clearance-21']=true,['lantern-1-12']=true,['lantern-1-21']=true,['walk-3-21']=true,['gate-SouthMain-12']=true,['gate-SouthMain-21']=true};local selected={}
 for _,v in ipairs(views)do if wanted[v.id]then selected[#selected+1]=v end end;assert(#selected==12);views=selected
 for _,hour in ipairs({12,21})do views[#views+1]={id='second-waterfront-'..hour,eye={86000,75500,1371},target={87500,75500,1280},fov=75,hour=hour}end
 local rooms={['interior-E1-0101-primary']=true,['interior-AD-0102-primary']=true,['interior-D4-0610-upper']=true};local count=0
 for _,r in ipairs(read(mainout..'/interior-cameras.json').rows)do if rooms[r.id]then count=count+1;for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end end
 assert(count==3 and #views==20,'Expected 20 focused native views')
end
if arg[1]=='detail' then
 local detail=read(mainout..'/detail-cameras.json');assert(detail.status=='passed' and detail.map_sha256==mapsha);views={}
 for _,r in ipairs(detail.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end
 local extra=read(mainout..'/extra-outdoor-cameras.json');for _,r in ipairs(extra.rows)do if r.id=='PK-0115' or r.id=='PK-0101' or r.id=='PK-0108' then for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-diagnostic-overview-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end end
 assert(#views==22,'Expected 16 player-height and 6 diagnostic overview views')
end
if arg[1]=='repair' then
 local followup=read(mainout..'/followup-cameras.json');assert(followup.status=='passed' and followup.map_sha256==mapsha);views={}
 for _,r in ipairs(followup.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end
 assert(#views==44,'Expected 44 supported player-height repair previews')
end
if arg[1]=='groundcheck' then
 local players=read(mainout..'/outdoor-player-cameras.json');assert(players.status=='passed' and players.map_sha256==mapsha);views={}
 for _,r in ipairs(players.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end
 assert(#views==40,'Expected all20 outdoor player day/night terrain comparisons')
end
if arg[1]=='layout' then
 local q=read(mainout..'/layout-cameras.json');assert(q.status=='passed' and q.map_sha256==mapsha);views={}
 for _,r in ipairs(q.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end
 assert(#views>=40,'Expected supported layout followup views')
end
if arg[1]=='polish' or arg[1]=='all_current' then
 local q=read(mainout..'/polish-cameras.json');assert(q.status=='passed' and q.map_sha256==mapsha and #q.rows==46);views={}
 cameras.map_sha256=q.map_sha256
 for _,r in ipairs(q.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour}end end
 assert(#views==92)
 for hour=0,24 do views[#views+1]={id='cycle-'..string.format('%02d',hour),eye=gate.eye,target=gate.target,fov=gate.fov,hour=hour%24,cycle_hour=hour,date=(hour==24 and '2026.10.27-' or '2026.10.26-')..string.format('%02d',hour%24)..'.00.00'}end
 assert(#views==117)
 local moon=read(mainout..'/moon-cameras.json');assert(moon.status=='passed' and moon.map_sha256==mapsha and #moon.rows==3)
 for _,r in ipairs(moon.rows)do views[#views+1]={id=r.id,eye=r.eye,target=r.target,fov=r.fov,hour=r.hour,date=r.date,camera_kind=r.camera_kind}end
 assert(#views==120)
 local park=read(mainout..'/active-park-current-review.json');assert(park.status=='passed' and park.map_sha256==mapsha and #park.cameras==2)
 for _,r in ipairs(park.cameras)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
 assert(#views==124)
 local mirrors=read(mainout..'/mirror-cameras.json');assert(mirrors.status=='passed' and mirrors.map_sha256==mapsha and #mirrors.rows==26)
 for _,r in ipairs(mirrors.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
 assert(#views==176)
end
if arg[1]=='mirrors' then
 local q=read(mainout..'/mirror-cameras.json');assert(q.status=='passed' and q.map_sha256==mapsha and #q.rows==26);views={};cameras.map_sha256=q.map_sha256
 for _,r in ipairs(q.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,camera_kind=r.camera_kind}end end
 assert(#views==52)
end
if arg[1]=='floors' or arg[1]=='all_current' then
 local q=read(mainout..'/all-floor-cameras.json');assert(q.status=='passed' and q.map_sha256==mapsha and #q.rows==89);if arg[1]~='all_current'then views={}end
 cameras.map_sha256=q.map_sha256
 for _,r in ipairs(q.rows)do for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-'..hour,eye=r.eye,target=r.target,fov=r.fov,hour=hour,building=r.building,floor=r.floor,room=r.room,camera_kind=r.camera_kind}end end
 assert(#views==(arg[1]=='all_current' and 354 or 178))
end
if arg[1]=='all_current'then
 local ordered={};for _,v in ipairs(views)do if v.id:match('^mirror%-') or v.id:match('^connection%-')then ordered[#ordered+1]=v end end
 for _,v in ipairs(views)do if not(v.id:match('^mirror%-') or v.id:match('^connection%-'))then ordered[#ordered+1]=v end end;assert(#ordered==354);views=ordered
end
]]..source:sub(last)
local modefolder=arg[1] or 'preview'
if arg[1]=='all_current'then source=source:gsub("'%-seconds=900'","'-seconds=1800'"):gsub('timeout=1200','timeout=2100')end
source=source:gsub('ground%-pbr%-v1','immersion-v1/'..modefolder)
source=source:gsub("local executable=package.target%.%.'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'","local executable='E:/PhysX/UE5.8/Engine/Binaries/Win64/UnrealEditor.exe'")
source=source:gsub("local args={executable,'/Game/UniversityCity/Maps/UniversityCity'","local args={executable,project,'/Game/UniversityCity/Maps/UniversityCity','-game'")
source=source:gsub('StreetSocialCityEnvironmentGameUser','StreetSocialCityImmersionPreviewUser')
source=source:gsub("'%-unattended'","'-unattended','-NoAsyncLoadingThread','-NoAsyncPostLoad','-ini:Engine:[ConsoleVariables]:Editor.AsyncAssetCompilationMaxMemoryUsage=6'")
source=source:gsub("'set CityEnvironmentController LocalDateTime '%.%.v.date","'set CityEnvironmentController Paused true',defer(3,'set CityEnvironmentController LocalDateTime '..v.date)")
source=source:gsub("assert%(text:find%('BugItGo to:'", "assert(not text:find('missing usage flag InstancedStaticMeshes',1,true) and not text:find('Failed to compile Material',1,true),'Source Game material fallback');assert(text:find('BugItGo to:'",1)
source=source:gsub('package_id=package.id','source_run_id=package.id,source_runtime="Uncooked UnrealEditor -game; packaged validation still required"')
source=source:gsub("camera_geometry_preservation=out%.%.'/preservation.json'","camera_geometry_preservation=mainout..'/preservation-after.json'")
source=source:gsub('Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.','Uncooked native D3D12 Game preview for visual iteration only. Final freshly staged Game validation remains mandatory. No Editor Python rendering.')
assert(os.execute('if not exist "output/street-social-city-production/immersion-v1/'..modefolder..'" mkdir "output/street-social-city-production/immersion-v1/'..modefolder..'"'))
source=dofile('Tools/street_city_immersion_capture_adapter.lua')(source)
local chunk,err=load(source,'immersion-uncooked-preview')
if not chunk then local debug=assert(io.open('output/street-social-city-production/immersion-v1/preview/expanded-debug.lua','wb'));debug:write(source);debug:close();error(err)end
chunk()
