-- Extend this task's running native Game macro chain before its final quit.
-- This avoids loading the entire source scene again; no scene pixels are synthesized.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash');local ok=require('ok')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/immersion-v1'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(type(d)=='string' and d or json.encode(d));f:close()end
local running=read(out..'/preview/captures-running.json');local cameras=read(out..'/interior-cameras.json');local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
assert(running.expected_images==72 and cameras.status=='passed' and cameras.map_sha256==running.map_sha256 and hash.sha256_file(map)==running.map_sha256)
local target=running.folder..'/Binaries/view-72.txt';local f=assert(io.open(target,'rb'));local original=f:read('*a');f:close();assert(original:match('quit\n$'),'Native chain already extended')
local folder=out..'/interiors/runtime-views-'..os.date('%Y%m%d-%H%M%S');assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..folder.."/Binaries' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
local views={};local function defer(n,s)return string.rep('DEFER ',n)..s end
for _,c in ipairs(cameras.rows)do for _,h in ipairs({12,21})do views[#views+1]={id=c.id..'-'..h,room=c.room,name=c.name,building=c.building,floor=c.floor,eye=c.eye,target=c.target,fov=c.fov,hour=h}end end;assert(#views==68)
for i,v in ipairs(views)do
 local dx,dy,dz=v.target[1]-v.eye[1],v.target[2]-v.eye[2],v.target[3]-v.eye[3];local yaw=math.deg(math.atan(dy,dx));local pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)))
 v.path=folder..'/'..v.id..'.png';v.date='2026.10.26-'..string.format('%02d',v.hour)..'.00.00'
 local lines={string.format('BugItGo %.6f %.6f %.6f %.6f %.6f 0',v.eye[1],v.eye[2],v.eye[3],pitch,yaw),'FOV '..v.fov,'set CityEnvironmentController Paused true',defer(3,'set CityEnvironmentController LocalDateTime '..v.date),defer(96,'getall CityEnvironmentController LocalDateTime'),defer(99,'r.HighResScreenshotDelay 8'),defer(100,'HighResShot 1920x1080 filename='..v.path),defer(125,i<#views and 'exec '..folder..'/Binaries/view-'..(i+1)..'.txt' or 'quit')}
 write(folder..'/Binaries/view-'..i..'.txt',table.concat(lines,'\n')..'\n')
end
write(out..'/interiors/captures-running.json',{status='attached_to_running_native_source_game',folder=folder,map_sha256=running.map_sha256,source_folder=running.folder,expected_images=68,views=views,camera_plan_sha256=hash.sha256_file(out..'/interior-cameras.json')})
write(target..'.before-interiors',original);write(target,(original:gsub('quit\n$','exec '..folder..'/Binaries/view-1.txt\n')))
print('Attached 68 day/night room views to native source Game: '..folder)
