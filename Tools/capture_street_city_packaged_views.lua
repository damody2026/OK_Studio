-- Actual staged Game screenshots using the engine's native deferred console.
-- No Editor/Python module, map mutation or source binary installation is used.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local out=root..'/output/street-social-city-production/day-night-v1'
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'wb'));f:write(json.encode(v));f:close()end
local package_receipt=read(out..'/package.json');local runtime=read(out..'/runtime-package-launch.json')
assert(package_receipt.engine=='E:/PhysX/UE5.8' and package_receipt.exit_code==0)
assert(runtime.status=='passed' and runtime.engine==package_receipt.engine and runtime.map_sha256==package_receipt.map_sha256,'A current E-engine native Game audit must pass first')
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
local before=hash.sha256_file(map);assert(before==package_receipt.map_sha256)
local native=read(runtime.native_receipt)
assert(native.status=='passed' and native.world_type=='Game' and not native.python_module_loaded)
local moonless=arg[1]=='moonless';assert(not arg[1] or moonless,'Unexpected capture mode')
local receipt_name=moonless and 'packaged-moonless-views' or 'packaged-views'
local views={{id='office-overview-night',eye={37350,78000,5500},target={37350,83500,1200},fov=75},
 {id='picnic-access-ramp-night',eye={36172.5,81100,1345},target={36172.5,82800,1250},fov=70}}
local moon=native.initial.moon.direction;local horizontal=math.sqrt(moon[1]^2+moon[2]^2);assert(horizontal>.001)
local moon_eye={45546.45,41890.81,1700.2}
views[#views+1]={id='moon-skyline-night',eye=moon_eye,target={moon_eye[1]+moon[1]/horizontal*1800,moon_eye[2]+moon[2]/horizontal*1800,moon_eye[3]+math.tan(math.rad(24))*1800},fov=100}
local cameras=read(out..'/cameras.json');assert(cameras.map_sha256==before)
for _,r in ipairs(cameras.rows)do if r.id=='PK-0110' then views[#views+1]={id='picnic-cleared-night',eye=r.camera.eye,target=r.camera.target,fov=r.camera.fov} end end
local polish=read(out..'/render-polish.json');assert(polish.map_sha256==before)
for _,r in ipairs(polish.images)do
 if r.name:match('^dark%-letter%-sign%-S0[139]%-21$') or r.name:match('^tree%-.+%-12$') then
  views[#views+1]={id=r.name:gsub('%-12$','-night'),eye=r.actual_eye_cm or r.eye,target=r.target,fov=r.fov}
 end
end
assert(#views==10,'Office, picnic, ramp, moon, three signs and three flowering trees required')
if moonless then
 assert(native.moonless.moon.lux==0 and native.moonless.moon.discVisibility==0 and native.moonless.skyLight>0,'Native moonless reference is required')
 views={{id='moonless-street-02',eye={45546.45,41890.81,1700.2},target={45900,43800,1800},fov=60,date='2026.11.09-02.00.00'}}
end
local executable=package_receipt.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'
local id='package-views-'..os.date('%Y%m%d-%H%M%S');local folder=out..'/'..id
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..folder.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
local receipt={status='running',engine=package_receipt.engine,package_id=package_receipt.id,map_sha256=before,images={}}
for _,v in ipairs(views)do
 local dx,dy,dz=v.target[1]-v.eye[1],v.target[2]-v.eye[2],v.target[3]-v.eye[3]
 local yaw=math.deg(math.atan(dy,dx));local pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)))
 local image=folder..'/'..v.id..'.png';local log=folder..'/'..v.id..'.log'
 local move=string.format('BugItGo %.6f %.6f %.6f %.6f %.6f 0',v.eye[1],v.eye[2],v.eye[3],pitch,yaw)
 -- DEFER queues commands for the next actual engine tick. Nested commands
 -- give the player camera and lighting budget time to follow the new view.
 local sequence={string.rep('DEFER ',30)..move,string.rep('DEFER ',31)..'FOV '..v.fov}
 if v.date then sequence[#sequence+1]=string.rep('DEFER ',32)..'set CityEnvironmentController LocalDateTime '..v.date;sequence[#sequence+1]=string.rep('DEFER ',147)..'getall CityEnvironmentController LocalDateTime' end
 for _,command in ipairs({string.rep('DEFER ',148)..'LogLoc',string.rep('DEFER ',149)..'r.HighResScreenshotDelay 8',string.rep('DEFER ',150)..'HighResShot 1920x1080 filename='..image,string.rep('DEFER ',240)..'quit'})do sequence[#sequence+1]=command end
 local commands=table.concat(sequence,',')
 local args={executable,'/Game/UniversityCity/Maps/UniversityCity','-unattended','-nosplash','-nosound','-windowed','-ResX=1920','-ResY=1080','-d3d12','-norhithread','-NoVSync','-seconds=120','-UserDir='..root..'/Saved/StreetSocialCityEnvironmentGameUser','-abslog='..log,'-DDC=(Local)','-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem','-ExecCmds='..commands}
 local result=ok.proc.run(args,{cwd=root,hide=true,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=300})
 local f=io.open(image,'rb');local size=f and f:seek('end') or 0;if f then f:close()end
 assert(result.code==0 and size>1000,'Native staged Game screenshot failed: '..log)
 local lf=assert(io.open(log,'rb'));local text=lf:read('*a');lf:close();assert(text:find('BugItGo to:',1,true),'Native camera command did not execute')
 local date_dump
 if v.date then
  for line in text:gmatch('[^\r\n]+')do if line:find('LocalDateTime =',1,true) and line:find(v.date,1,true) then date_dump=line end end
  assert(date_dump,'Actual reflected Game clock date did not match the moonless reference; inspect '..log)
 end
 receipt.images[#receipt.images+1]={id=v.id,path=image,sha256=hash.sha256_file(image),eye=v.eye,target=v.target,fov=v.fov,native_log=log,exit_code=result.code,native_date_dump=date_dump,clock_source=v.date and 'Native Development property command, mirrored through the real shared clock; reflected instance date verified in log' or 'Native audit saved paused 2026-10-26 21:00 through the actual game save/load implementation; shared isolated UserDir'}
 write(out..'/'..receipt_name..'.json',receipt)
end
assert(hash.sha256_file(map)==before,'Main map changed during captures')
receipt.status='captured_requires_visual_review';receipt.scope=(moonless and 'One moonless 02:00 actual staged Game view' or 'Ten actual staged Game views')..'; camera and screenshot use native Development commands, with 120 world ticks after teleport before capture; no Editor/Python';write(out..'/'..receipt_name..'.json',receipt)
print('Actual staged Game views captured: '..folder)
