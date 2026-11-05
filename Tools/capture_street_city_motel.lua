-- Actual D3D12 Game screenshots; source preview and packaged evidence stay separate.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/motel-v1';local preview=arg[1]=='preview';local focus=arg[2]=='focus'
-- 'decor': one room per style/building, camera from the bed viewpoint onto the Tripo ornament slots A (tea table) and B (minibar).
local decor=arg[2]=='decor'
-- 'samples': the fidelity sample rooms' official-photo compositions from sample-rooms/sample-build.json.
local samples=arg[2]=='samples' or arg[2]=='v2'
-- 'v2': the mass-produced data-driven rooms from sample-rooms/rooms-v2-build.json (optional room ids after it)
local v2=arg[2]=='v2';local v2only={};if v2 then for i=3,#arg do v2only[arg[i]]=true end end
local function read(p)local f=assert(io.open(p,'rb'));local r=j.decode(f:read('*a'));f:close();return r end
local function write(p,r)local f=assert(io.open(p,'wb'));f:write(type(r)=='string' and r or j.encode(r));f:close()end
local install=read(out..'/motel-install.json');local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local sha=h.sha256_file(map);assert(install.map_sha256==sha)
local package=not preview and read(out..'/package.json') or {id='uncooked-source-'..os.date('%Y%m%d-%H%M%S'),engine='E:/PhysX/UE5.8',host='E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject'}
if not preview then assert(package.map_sha256==sha and package.exit_code==0)end
local views={};local plan=read(out..'/motel-plan.json');local picked={}
for _,r in ipairs(install.rooms)do
 local q;for _,p in ipairs(plan.rooms)do if p.id==r.id then q=p;break end end
 local function add_decor()
  local angle=math.rad(q.yaw);local w=q.size_m[1]
  local function world(x,y,z)return {r.position[1]+(x*math.sin(angle)+y*math.cos(angle))*100,r.position[2]+(x*math.cos(angle)-y*math.sin(angle))*100,r.position[3]+z*100}end
  views[#views+1]={id=r.id..'-decorA-12',eye=r.eye,target=world(w*.27,-1.7,.75),fov=50,hour=12}
  views[#views+1]={id=r.id..'-decorB-12',eye=r.eye,target=world(w*.29-2+.36,-8.8,1.1),fov=50,hour=12}
 end
 if decor then
  if not picked[q.style..q.building] then picked[q.style..q.building]=true;add_decor()end
 elseif not focus or ((q.style=='royal' or q.style=='pool' or q.style=='candy' or q.building=='S18')and not picked[q.style..q.building])then
  picked[q.style..q.building]=true
  for _,hour in ipairs({12,21})do views[#views+1]={id=r.id..'-bed-'..hour,eye=r.eye,target=r.target,fov=78,hour=hour}end
  views[#views+1]={id=r.id..'-bath-21',eye=r.bath_eye,target=r.mirror_face,fov=85,hour=21}
  -- Full runs also shoot every room's two Tripo ornaments (A tea table, B minibar).
  if not focus then add_decor()end
 end
end
for _,q in ipairs(plan.rooms)do if q.is_pool_suite and not decor then
 local r;for _,rr in ipairs(install.rooms)do if rr.id==q.id then r=rr;break end end;local angle=math.rad(q.yaw);local right=-q.size_m[1]*.27+4.1
 local function world(x,y,z)return {r.position[1]+(x*math.sin(angle)+y*math.cos(angle))*100,r.position[2]+(x*math.cos(angle)-y*math.sin(angle))*100,r.position[3]+z*100}end
 for _,hour in ipairs({12,21})do views[#views+1]={id=q.id..'-pool-'..hour,eye=world(right+.28,4.2,2.91),target=world(-q.size_m[1]*.27,4.2,1.0),fov=84,hour=hour,camera_kind='Supported exterior pool stair,1.65m above126cm tread'}end
end end
views[#views+1]={id='H1-ground-entry-night',eye={25000,67800,1363},target={26790,67800,1566},fov=75,hour=21}
for _,hour in ipairs({12,21})do views[#views+1]={id='H1-exterior-whole-'..hour,eye={22500,67800,1363},target={29200,70500,2400},fov=75,hour=hour,camera_kind='Street-level exterior architecture inspection'}end
views[#views+1]={id='H1-ramp-diagnostic-day',eye={36300,77900,4900},target={33400,70400,2500},fov=88,hour=12}
views[#views+1]={id='S18-ground-entry-night',eye={46100,50740,1371},target={48400,50740,1750},fov=78,hour=21}
views[#views+1]={id='H1-street-driveway-night',eye={37500,77550,1371},target={35000,77100,1570},fov=85,hour=21}
views[#views+1]={id='H1-guest-gallery-night',eye={29500,65100,1871},target={29650,75400,1830},fov=80,hour=21}
views[#views+1]={id='H1-reception-WC-mirror',eye={31100,71130,1371},target={31468,71130,1371},fov=75,hour=21}
local wc=read(out..'/restroom-mirrors-install.json');local buildings={}
for _,r in ipairs(wc.mirrors)do
 if not buildings[r.building] and (not focus or r.building=='E1' or r.building=='M1')then
  buildings[r.building]=true;views[#views+1]={id='WC-'..r.building,eye=r.eye,target=r.face,fov=75,hour=21}
 end
end
if decor then local d={};for _,v in ipairs(views)do if v.id:find('-decor',1,true)then d[#d+1]=v end end;views=d end
if samples then
 views={};local sb=read(out..'/sample-rooms/'..(v2 and 'rooms-v2-build.json' or 'sample-build.json'))
 for _,b in ipairs(sb.rooms)do if not v2 or not next(v2only) or v2only[b.id] then
  local r,q;for _,rr in ipairs(install.rooms)do if rr.id==b.id then r=rr end end;for _,p in ipairs(plan.rooms)do if p.id==b.id then q=p end end
  local angle=math.rad(q.yaw);local function world(v)return {r.position[1]+(v[1]*math.sin(angle)+v[2]*math.cos(angle))*100,r.position[2]+(v[1]*math.cos(angle)-v[2]*math.sin(angle))*100,r.position[3]+v[3]*100}end
  for _,v in ipairs(b.views)do views[#views+1]={id=b.id..'-'..v.id,eye=world(v.eye),target=world(v.target),fov=v.fov,hour=21,ref=v.ref}end
  -- Extra survey views: four inner corners looking across, centre looking at each wall, and the bathroom from its door.
  local w=q.size_m[1];local x0,x1,y0,y1=-w/2+.7,w/2-.7,-2.7,6.3;local cx,cy=0,1.8
  local survey={{'corner-front-left',{x0,y0,2.0},{x1,y1,.9}},{'corner-front-right',{x1,y0,2.0},{x0,y1,.9}},{'corner-back-left',{x0+.3,y1-.3,2.0},{x1,y0,.9}},{'corner-back-right',{x1-.3,y1-.3,2.0},{x0,y0,.9}},
   {'centre-to-back',{cx,cy-1,1.6},{cx,y1+2,1.3}},{'centre-to-front',{cx,cy+1,1.6},{cx,-4,1.3}},{'centre-to-left',{cx+1,cy,1.6},{-w/2,cy,1.3}},{'centre-to-right',{cx-1,cy,1.6},{w/2,cy,1.3}},
   {'bath-from-door',{w*.28+.15,6.2,1.7},{w*.28+.6,9.6,.8}},{'ceiling-up',{cx,cy,1.4},{cx,cy+2.5,3.9}}}
  for _,s in ipairs(v2 and {} or survey)do views[#views+1]={id=b.id..'-survey-'..s[1],eye=world(s[2]),target=world(s[3]),fov=90,hour=21}end
  if not v2 then views[#views+1]={id=b.id..'-survey-day-corner',eye=world({x1,y0,2.0}),target=world({x0,y1,.9}),fov=90,hour=12} end
 end end
end
local id=os.date('%Y%m%d-%H%M%S');local folder=out..'/'..(preview and 'preview-' or 'runtime-views-')..id;local macros=folder..'/Binaries';assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..macros.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
local function defer(n,s)return string.rep('DEFER ',n)..s end
-- OK_MOTEL_CAPTURE_SETTLE=<frames> before each shot (default 100). The game runs auto exposure: 100 frames after a cut from a dark
-- view the bath close-ups were still blown out (round 10, 2026-10-29), so acceptance rounds pass a longer settle.
local S=tonumber(os.getenv('OK_MOTEL_CAPTURE_SETTLE') or '') or 100
for i,v in ipairs(views)do
 local dx,dy,dz=v.target[1]-v.eye[1],v.target[2]-v.eye[2],v.target[3]-v.eye[3];local yaw=math.deg(math.atan(dy,dx));local pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)));v.path=folder..'/'..v.id..'.png';v.date='2026.10.26-'..string.format('%02d',v.hour)..'.00.00'
 write(macros..'/view-'..i..'.txt',table.concat({string.format('CityImmersionCapturePose %.6f %.6f %.6f %.6f %.6f',v.eye[1],v.eye[2],v.eye[3],pitch,yaw),'FOV '..v.fov,'set CityEnvironmentController LocalDateTime '..v.date,defer(S-4,'getall CityEnvironmentController LocalDateTime'),defer(S-2,'CityImmersionViewPoint '..v.id),defer(S-1,'r.HighResScreenshotDelay 8'),defer(S,'HighResShot 1920x1080 filename='..v.path),defer(S+25,i<#views and 'exec '..macros..'/view-'..(i+1)..'.txt' or 'quit')},'\n')..'\n')
end
write(macros..'/begin.txt',defer(30,'exec '..macros..'/view-1.txt')..'\n')
local log=folder..'/native-game.log';local exe=preview and package.engine..'/Engine/Binaries/Win64/UnrealEditor.exe' or package.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe';local args={exe}
if preview then args[#args+1]=package.host..'/StreetSocialCity.uproject';args[#args+1]='-game'end
for _,v in ipairs({'/Game/UniversityCity/Maps/UniversityCity','-CityImmersionCapture','-unattended','-nosplash','-nosound','-windowed','-ResX=1920','-ResY=1080','-d3d12','-norhithread','-NoVSync','-seconds=3600','-UserDir='..root..'/Saved/StreetSocialCityMotelGameUser','-abslog='..log,'-DDC=(Local)','-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem','-ExecCmds=exec '..macros..'/begin.txt'})do args[#args+1]=v end
write(out..'/capture-running.json',{status='running',package_id=package.id,preview=preview,folder=folder,expected_images=#views,map_sha256=sha,images=views});local result=ok.proc.run(args,{cwd=root,hide=true,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=4000});assert(result.code==0,'Native Game failed: '..log)
local f=assert(io.open(log,'rb'));local text=f:read('*a');f:close();assert(text:find('CITY_IMMERSION_CAPTURE_POSE',1,true));assert(not text:find('missing usage flag InstancedStaticMeshes',1,true))
for _,v in ipairs(views)do
 local f=assert(io.open(v.path,'rb'),'Missing Game image: '..v.path);local header=f:read(24);assert(header:sub(1,8)=='\137PNG\r\n\26\n');local width,height=string.unpack('>I4I4',header,17);assert(width==1920 and height==1080);assert(f:seek('end')>5000);f:close();v.sha256=h.sha256_file(v.path)
 assert(text:find('LocalDateTime = '..v.date,1,true));assert(text:find('CITY_IMMERSION_CAPTURE '..v.id..' eye=',1,true));local escaped=v.id:gsub('([^%w])','%%%1');local configured,active,percent,rough=text:match('CITY_IMMERSION_MIRRORS '..escaped..' configured=(%d+) active=(%d+) capture_percent=(%d+) prefilter=([%d%.]+)');assert(tonumber(configured)==1045 and tonumber(active)<=2,'Reflection selection contract missing');v.active_mirrors=tonumber(active);v.capture_percentage=tonumber(percent);v.prefilter_roughness=tonumber(rough)
 if v.active_mirrors>0 then assert(v.capture_percentage==75 and v.prefilter_roughness==0)end
 if v.id:find('-bath-',1,true)or v.id:match('^WC%-')or v.id=='H1-reception-WC-mirror'then assert(v.active_mirrors>=1,'Bathroom reflection not active')end
end
assert(h.sha256_file(map)==sha);write(out..(v2 and '/v2-captures.json' or samples and '/sample-captures.json' or decor and '/decor-captures.json' or preview and '/preview-captures.json' or focus and '/focus-captures.json' or '/captures.json'),{status='captured_requires_visual_review',preview=preview,focus=focus,expected_images=#views,engine=package.engine,package_id=package.id,map_sha256=sha,exit_code=result.code,native_log=log,images=views,scope=preview and 'Actual uncooked native Game source preview; not packaged acceptance.' or 'Actual staged D3D12 Game screenshots,61 source-page suites and sampled nonhotel restroom mirrors. Screenshots require human/model visual review.'});print('Captured '..#views..' actual Game images: '..folder)
