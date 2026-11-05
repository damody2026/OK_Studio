-- One actual staged D3D12 Game session; native console files form a bounded camera chain.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/ground-pbr-v1';local envout=root..'/output/street-social-city-production/day-night-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(type(d)=='string' and d or json.encode(d));f:close()end
local repair=arg[1]=='repair';assert(not arg[1] or repair,'Use repair only for elevated ground inspection cameras')
local installed=read(out..'/install.json');local audit=read(out..'/audit.json');local package=read(envout..'/package.json');local runtime=read(envout..'/runtime-package-launch.json');local native=read(runtime.native_receipt)
assert(audit.status=='passed' and audit.map_sha256==installed.map_sha256 and package.map_sha256==installed.map_sha256 and runtime.map_sha256==installed.map_sha256 and runtime.status=='passed')
assert(package.engine=='E:/PhysX/UE5.8' and package.exit_code==0 and native.world_type=='Game' and native.status=='passed' and not native.python_module_loaded)
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';assert(hash.sha256_file(map)==installed.map_sha256)
local cameras=read(envout..'/cameras.json');assert(cameras.map_sha256==installed.before_map_sha256,'Only unchanged camera geometry from the immediately preceding map is accepted')
local views={};for _,r in ipairs(cameras.rows)do if r.id:match('^PK%-') and r.camera then local c=r.camera;views[#views+1]={id=r.id..'-day',site=r.id,eye=c.eye,target=c.target,fov=c.fov,hour=12} end end
assert(#views==20,'All twenty outdoor sites require a native view')
for _,r in ipairs(views)do if r.site=='PK-0110' then views[#views+1]={id='picnic-night',site=r.site,eye=r.eye,target=r.target,fov=r.fov,hour=21};break end end
local polish=read(envout..'/render-polish.json');assert(polish.map_sha256==installed.before_map_sha256)
for _,r in ipairs(polish.images)do if r.name:match('^tree%-.+%-12$')then views[#views+1]={id=r.name:gsub('%-12$','-soil-day'),eye=r.actual_eye_cm or r.eye,target=r.target,fov=r.fov,hour=12};if r.name=='tree-flower-a-12'then views[#views+1]={id='pink-tree-soil-night',eye=r.actual_eye_cm or r.eye,target=r.target,fov=r.fov,hour=21}end end end
for _,hour in ipairs({12,21})do views[#views+1]={id='street-paving-'..hour,eye={45546.45,41890.81,1700.2},target={45546.45,44000,1320},fov=75,hour=hour}end
for _,x in ipairs({27500,82500})do for _,y in ipairs({27500,82500})do views[#views+1]={id='city-ground-aerial-'..x..'-'..y,eye={x,y,72000},target={x,y,1200},fov=90,hour=12}end end
local floorproof=read(out..'/verify.json');local completion=read(out..'/complete.json');assert(floorproof.status=='passed' and floorproof.map_sha256==completion.before_map_sha256 and completion.map_sha256==installed.map_sha256)
for _,v in ipairs(floorproof.cameras)do views[#views+1]=v end
do
 local targets={['PK-0101-day']='World_PK_0101',['PK-0108-day']='World_PK_0108',['PK-0109-day']='World_PK_0109',['PK-0114-day']='Outdoor_stadium',['PK-0115-day']='Outdoor_campus_track'}
 local inventory=read(out..'/inventory.json');local boxes={}
 for _,c in ipairs(inventory.components)do if c.instances>0 and not boxes[c.actor]then boxes[c.actor]=c end end
 local elevated={}
 for _,v in ipairs(views)do if targets[v.id]then
  local box=assert(boxes[targets[v.id]]);local span=math.max(box.extent[1],box.extent[2]);local z=box.origin[3]+box.extent[3]+math.max(2400,span*1.5)
  elevated[#elevated+1]={id=v.id,site=v.site,eye={box.origin[1],box.origin[2],z},target=box.origin,fov=85,hour=12,camera_kind='elevated ground inspection',source_actor=box.actor}
 end end
 assert(#elevated==5)
 if repair then views=elevated else local by_id={};for _,v in ipairs(elevated)do by_id[v.id]=v end;for i,v in ipairs(views)do if by_id[v.id]then views[i]=by_id[v.id]end end end
end
if not repair then
 local f=io.open(out..'/road-camera.json','rb')
 if f then local road=json.decode(f:read('*a'));f:close();assert(road.source_geometry_map_sha256==installed.before_map_sha256)
  for _,hour in ipairs({12,21})do views[#views+1]={id='asphalt-road-'..hour,eye=road.eye,target=road.target,fov=75,hour=hour,camera_kind='native road-surface inspection'}end
 end
end
local id=os.date('%Y%m%d-%H%M%S');local folder=out..'/runtime-views-'..id;assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..folder.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
-- ULocalPlayer::ExecMacro accepts an absolute macro path only when it contains Binaries.
local macro=folder..'/Binaries';assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..macro.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
local function defer(n,c)return string.rep('DEFER ',n)..c end
for i,v in ipairs(views)do
 local dx,dy,dz=v.target[1]-v.eye[1],v.target[2]-v.eye[2],v.target[3]-v.eye[3];local yaw=math.deg(math.atan(dy,dx));local pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)))
 v.path=folder..'/'..v.id..'.png';v.date=v.date or ('2026.10.26-'..string.format('%02d',v.hour)..'.00.00')
 local lines={string.format('BugItGo %.6f %.6f %.6f %.6f %.6f 0',v.eye[1],v.eye[2],v.eye[3],pitch,yaw),'FOV '..v.fov,'set CityEnvironmentController LocalDateTime '..v.date,defer(96,'getall CityEnvironmentController LocalDateTime'),defer(98,'LogLoc'),defer(99,'r.HighResScreenshotDelay 8'),defer(100,'HighResShot 1920x1080 filename='..v.path),defer(125,i<#views and 'exec '..macro..'/view-'..(i+1)..'.txt' or 'quit')}
 write(macro..'/view-'..i..'.txt',table.concat(lines,'\n')..'\n')
end
write(macro..'/begin.txt',defer(30,'exec '..macro..'/view-1.txt')..'\n')
local log=folder..'/native-game.log';local executable=package.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'
write(out..'/captures-running.json',{status='running',package_id=package.id,engine=package.engine,folder=folder,expected_images=#views,map_sha256=installed.map_sha256,views=views})
local args={executable,'/Game/UniversityCity/Maps/UniversityCity','-unattended','-nosplash','-nosound','-windowed','-ResX=1920','-ResY=1080','-d3d12','-norhithread','-NoVSync','-seconds=900','-UserDir='..root..'/Saved/StreetSocialCityEnvironmentGameUser','-abslog='..log,'-DDC=(Local)','-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem','-ExecCmds=exec '..macro..'/begin.txt'}
local result=ok.proc.run(args,{cwd=root,hide=true,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=1200})
assert(result.code==0,'Ground capture process failed: '..log)
local f=assert(io.open(log,'rb'));local text=f:read('*a');f:close();assert(text:find('BugItGo to:',1,true),'Native camera chain was not executed')
for _,v in ipairs(views)do local f=assert(io.open(v.path,'rb'),'Missing native screenshot: '..v.path);assert(f:seek('end')>5000);f:close();v.sha256=hash.sha256_file(v.path);assert(text:find('LocalDateTime = '..v.date,1,true),'Reflected Game date missing: '..v.date) end
assert(hash.sha256_file(map)==installed.map_sha256,'Source map changed during actual Game captures')
write(out..(repair and '/captures-repair.json' or '/captures.json'),{status='captured_requires_visual_review',expected_images=#views,engine=package.engine,package_id=package.id,executable=executable,map_sha256=installed.map_sha256,source_camera_map_sha256=cameras.map_sha256,camera_geometry_preservation=out..'/preservation.json',exit_code=result.code,native_log=log,images=views,scope=repair and 'Five elevated ground inspection views replace obstructed or under-platform legacy cameras; actor geometry unchanged, native reflected clock checked.' or 'Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.'})
print('Captured '..#views..' actual Game views: '..folder)
