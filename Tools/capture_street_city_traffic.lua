local f=assert(io.open('Tools/capture_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
local guard=assert(io.open('output/street-social-city-production/traffic-v1/bridge-audit.json','rb'),'Bridge support/clearance must pass before capture');guard:close()
source=source:gsub('ground%-pbr%-v1','traffic-v1'):gsub('runtime.map_sha256==installed.map_sha256 and ','')
source=source:gsub('local map=root',"local bridge=read(out..'/bridge-audit.json');assert(bridge.status=='passed' and bridge.map_sha256==installed.map_sha256)\nlocal map=root",1)
source=source:gsub("assert%(text:find%('BugItGo to:'", "assert(not text:find('missing usage flag InstancedStaticMeshes',1,true) and not text:find('Please fix material usage flag InstancedStaticMeshes',1,true),'Cooked instanced material fallback detected');assert(text:find('BugItGo to:'",1)
local start=assert(source:find("local cameras=read(envout..'/cameras.json')",1,true));local stop=assert(source:find('local id=os.date',start,true))
source=source:sub(1,start-1)..[[local cameras=read(envout..'/cameras.json');local previous=read(root..'/output/street-social-city-production/flat-campus-v1/captures.json');local plan=read(out..'/plan.json');local views={}
assert(previous.map_sha256==installed.before_map_sha256)
for _,q in ipairs(previous.images)do views[#views+1]={id=q.id,site=q.site,eye=q.eye,target=q.target,fov=q.fov,hour=q.hour}end
for _,j in ipairs(plan.junctions)do local x,y=j.center_cm[1],j.center_cm[2];views[#views+1]={id=j.id..'-aerial',eye={x,y,7000},target={x,y,1200},fov=80,hour=12}end
for _,id in ipairs({'J05','J12','J15'})do for _,j in ipairs(plan.junctions)do if j.id==id then local x,y=j.center_cm[1],j.center_cm[2];for _,hour in ipairs({12,21})do views[#views+1]={id=id..'-street-'..hour,eye={x+2200,y+1100,1390},target={x,y,1500},fov=80,hour=hour}end end end end
for _,q in ipairs(read(out..'/bridge-plan.json').bridges)do local x,y=q.center_cm[1],q.center_cm[2];local dx,dy=q.direction[1],q.direction[2];local nx,ny=-dy,dx;for _,hour in ipairs({12,21})do views[#views+1]={id=q.id..'-'..hour,eye={x-dx*(q.span_cm/2+600)+nx*(q.carriageway_cm/2+125),y-dy*(q.span_cm/2+600)+ny*(q.carriageway_cm/2+125),1390},target={x+dx*800,y+dy*800,1320},fov=80,hour=hour}end end
for _,hour in ipairs({12,21})do views[#views+1]={id='riverbank-road-'..hour,eye={89500,77900,1650},target={85200,78100,1220},fov=75,hour=hour}end
]]..source:sub(stop)
source=source:gsub('Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.','Actual staged D3D12 Game: campus, outdoor sites and all 16 traffic junctions, with targeted street-level day/night traffic views; native reflected clock checked.')
assert(load(source,'traffic-actual-game-views'))()
