local f=assert(io.open('Tools/capture_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v1','flat-campus-v1')
source=source:gsub('runtime.map_sha256==installed.map_sha256 and ','')
local start=assert(source:find("local cameras=read(envout..'/cameras.json')",1,true));local stop=assert(source:find('local id=os.date',start,true))
source=source:sub(1,start-1)..[[local cameras=read(envout..'/cameras.json');local plan=read(out..'/plan.json');local prior=read(root..'/output/street-social-city-production/white-paths-v1/captures.json')
local delta={};for _,q in ipairs(plan.changes)do if q.kind=='actor'then delta[q.actor]=q.delta_z_cm end end
local views={}
for _,v in ipairs(prior.images)do if v.id:match('^PK%-%d+%-day$')then
 local site=v.id:match('^(PK%-%d+)');local label='World_'..site:gsub('-','_');local dz=delta[label] or (site=='PK-0102' and -800 or site=='PK-0115' and -800 or 0)
 local eye={v.eye[1],v.eye[2],v.eye[3]+dz};local target={v.target[1],v.target[2],v.target[3]+dz}
 views[#views+1]={id=v.id,site=site,eye=eye,target=target,fov=v.fov,hour=12}
end end
assert(#views==20)
for _,v in ipairs(views)do
 if v.site=='PK-0106'then v.eye={87000,74800,3300};v.target={87500,76000,1200};v.fov=75 end
 if v.site=='PK-0108'then v.eye={26500,81600,3100};v.target={28000,84250,1200};v.fov=75 end
end
for _,q in ipairs(plan.gates)do
 local x,y=q.center[1],q.center[2];local angle=math.rad(q.yaw);local nx,ny=math.cos(angle),math.sin(angle)
 for _,hour in ipairs(q.id=='SouthMain' and {12,21} or {12})do views[#views+1]={id='gate-'..q.id..'-'..hour,eye={x+nx*2200,y+ny*2200,1500},target={x,y,1580},fov=65,hour=hour}end
end
views[#views+1]={id='campus-overview',eye={72000,49000,76000},target={72000,49000,1200},fov=70,hour=12}
views[#views+1]={id='campus-AD-threshold',eye={67450,65050,1380},target={67000,65800,1230},fov=75,hour=12}
views[#views+1]={id='campus-reading-ground',eye={80000,54500,10200},target={80000,54500,1200},fov=80,hour=12}
views[#views+1]={id='campus-city-connection',eye={53000,57500,1800},target={55400,57500,1200},fov=80,hour=12}
for _,x in ipairs({27500,82500})do for _,y in ipairs({27500,82500})do views[#views+1]={id='flat-city-'..x..'-'..y,eye={x,y,64000},target={x,y,1200},fov=90,hour=12}end end
views[#views+1]={id='annex-ground-connection',eye={77500,114000,1650},target={77500,121000,1200},fov=75,hour=12}
]]..source:sub(stop)
source=source:gsub('Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.','Actual staged D3D12 Game: twenty outdoor sites, five campus gates, school thresholds and global flat-land overviews; native reflected clock checked. No Editor/Python.')
assert(load(source,'flat-campus-actual-game-views'))()
