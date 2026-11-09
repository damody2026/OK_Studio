-- Diagnostic cooked mirror variants; no asset, map, or staged-file mutation.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local o=root..'/output/street-social-city-production/immersion-v1'
local function read(p)local f=assert(io.open(p,'rb'));local x=j.decode(f:read('*a'));f:close();return x end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(type(s)=='string' and s or j.encode(s));f:close()end
local p=read(root..'/output/street-social-city-production/day-night-v1/package.json');local cameras=read(o..'/mirror-cameras.json')
local source=arg[1]=='source';local id=os.date('%Y%m%d-%H%M%S');local folder=o..'/'..(source and 'mirror-source-filter-probe-' or 'mirror-filter-probe-')..id;local macro=folder..'/Binaries'
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..macro.."' -Force|Out-Null"},{hide=true}).code==0)
local variants={{75,0},{75,.001},{50,0},{50,.01}};local rows={}
local function defer(n,s)return string.rep('DEFER ',n)..s end
for i,v in ipairs(variants)do
 local camera=cameras.rows[1];local eye,t=camera.eye,camera.target;local dx,dy,dz=t[1]-eye[1],t[2]-eye[2],t[3]-eye[3];local yaw=math.deg(math.atan(dy,dx));local pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)))
 local image=folder..'/variant-'..i..'.png';rows[#rows+1]={path=image,screen_percentage=v[1],prefilter=v[2]}
 local commands={'CityImmersionCapturePose 45546 41890 1700 0 0','set CityEnvironmentController Paused true','set CityEnvironmentController LocalDateTime 2026.10.26-12.00.00',defer(20,'set PlanarReflectionComponent PrefilterRoughness '..v[2]),defer(20,'set PlanarReflectionComponent ScreenPercentage '..v[1]),defer(25,string.format('CityImmersionCapturePose %.6f %.6f %.6f %.6f %.6f',eye[1],eye[2],eye[3],pitch,yaw)),defer(25,'FOV '..camera.fov),defer(98,'CityImmersionViewPoint variant-'..i),defer(99,'r.HighResScreenshotDelay 8'),defer(100,'HighResShot 1920x1080 filename='..image),defer(140,i<4 and 'exec '..macro..'/view-'..(i+1)..'.txt' or 'quit')}
 write(macro..'/view-'..i..'.txt',table.concat(commands,'\n')..'\n')
end
local exe=p.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe';local before=h.sha256_file(exe);local log=folder..'/native.log'
local args={exe,'/Game/UniversityCity/Maps/UniversityCity','-CityImmersionCapture','-d3d12','-norhithread','-unattended','-nosplash','-nosound','-windowed','-ResX=1920','-ResY=1080','-NoVSync','-seconds=180','-UserDir='..root..'/Saved/CityMirrorFilterProbeUser','-abslog='..log,'-ExecCmds=exec '..macro..'/view-1.txt'}
if source then args[1]='E:/PhysX/UE5.8/Engine/Binaries/Win64/UnrealEditor.exe';table.insert(args,2,p.host..'/StreetSocialCity.uproject');args[#args+1]='-game';args[#args+1]='-NoAsyncLoadingThread';args[#args+1]='-NoAsyncPostLoad';args[#args+1]='-DDC=(Local)';args[#args+1]='-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem';for i,v in ipairs(args)do if v=='-seconds=180' then args[i]='-seconds=600' end end end
write(folder..'/running.json',{package_id=p.id,folder=folder,rows=rows})
local result=ok.proc.run(args,{hide=true,cwd=root,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=source and 900 or 300})
assert(result.code==0 and h.sha256_file(exe)==before);for _,r in ipairs(rows)do r.sha256=h.sha256_file(r.path)end
write(folder..'/result.json',{status='captured_requires_manual_review',package_id=p.id,map_sha256=p.map_sha256,rows=rows,log=log});print(folder)
