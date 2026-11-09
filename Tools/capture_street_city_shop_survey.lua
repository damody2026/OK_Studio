-- Shop-street survey: actual uncooked -game D3D12 screenshots of every shop (S01-S96) for the inventory/fix plan.
-- Per shop: storefront from the lane (day), the same storefront at night, and the ground floor from just inside the door.
-- Plus lane overviews. Positions come from shop-survey-v1/shop-probe.json (Tools/street_city_shop_survey_payload.lua)
-- and the entrance table in StreetSocialCityDocs/production/student-street-frontages.md.
-- Usage: lua Tools/capture_street_city_shop_survey.lua [S01 S02 ...]
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/shop-survey-v1'
local function read(p)local f=assert(io.open(p,'rb'));local r=f:read('*a');f:close();return r end
local function write(p,r)local f=assert(io.open(p,'wb'));f:write(type(r)=='string' and r or j.encode(r));f:close()end
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local sha=h.sha256_file(map)
local probe=j.decode(read(out..'/shop-probe.json'));if probe.map_sha256~=sha then print('note: probe is from map '..probe.map_sha256:sub(1,12)..'; shop floor actors are not moved by refit installs') end
-- '--samples' adds a wide storefront view (day/night) and a view from the back of the sales floor toward the street.
local samples=arg[1]=='--samples';local only={};for i=(samples and 2 or 1),#arg do only[arg[i]]=true end
-- '--views <json>': free views [{id,eye,target,fov,hour}] only (world cm), e.g. aerial checks
local free=arg[1]=='--views' and j.decode(read(arg[2])) or nil;if free then only={['--none--']=true} end
-- '--upper': also each shop's F02/F03 (centre of the floor looking at the street windows, and back toward the core)
local upper=false;for i=1,#arg do if arg[i]=='--upper' then upper=true;only['--upper']=nil end end
-- OK_SHOP_CAPTURE_PACKAGE=1: shoot with the cooked package from motel-v1/package.json (Editor -game needs ~70 GB for this map)
local pkg=os.getenv('OK_SHOP_CAPTURE_PACKAGE')=='1' and j.decode(read(root..'/output/street-social-city-production/motel-v1/package.json')) or nil
if pkg then assert(pkg.map_sha256==sha and pkg.exit_code==0,'package is not built from the current map') end
-- entrance table: | S01 咖啡書屋 | 南 | student-lane-1 | -2.60, -9.00 |
local doors={}
for line in read('E:/OpenKoikatsuWorkspace/StreetSocialCityDocs/production/student-street-frontages.md'):gmatch('[^\n]+')do
 local id,name,dir,lane,x,y=line:match('^| (S%d%d) (.-) | (.-) | (student%-lane%-%d) | ([%-%d%.]+), ([%-%d%.]+) |')
 if id then doors[id]={name=name,dir=dir,lane=lane,x=tonumber(x),y=tonumber(y)}end
end
local floors={};for _,a in ipairs(probe.actors)do if a.floor==1 then floors[a.building]=a end end
local views={}
local function add(id,eye,target,fov,hour,shop)views[#views+1]={id=id,eye=eye,target=target,fov=fov,hour=hour,shop=shop}end
local ids={};for id in pairs(doors)do ids[#ids+1]=id end;table.sort(ids)
-- Lanes run along world Y (all shops are yawed +-90). Lane centre X = mean of both facing rows.
local lanes={}
for _,id in ipairs(ids)do local d=doors[id];local a=floors[id];if a then local l=lanes[d.lane] or {n=0,y0=1e18,y1=-1e18,x=0,z=0};local c=a.bounds_origin;l.y0=math.min(l.y0,c[2]);l.y1=math.max(l.y1,c[2]);l.x=l.x+c[1];l.z=l.z+a.location[3];l.n=l.n+1;lanes[d.lane]=l end end
for _,l in pairs(lanes)do l.x=l.x/l.n;l.z=l.z/l.n end
for _,id in ipairs(ids)do if not next(only) or only[id] then
 local d,a=doors[id],floors[id];assert(a,'No F01 actor for '..id)
 local yaw=math.rad(a.yaw);local base=a.location;local sx=a.scale[1]
 local function world(x,y,z)local wx=x*100*sx;local wy=y*100*sx;return {base[1]+wx*math.cos(yaw)-wy*math.sin(yaw),base[2]+wx*math.sin(yaw)+wy*math.cos(yaw),base[3]+z*100}end
 -- S18/S19: the inns' front doors face each other across a ~20 cm gap; shoot the dressed stretch of the south (entry-A) face from the lane end
 local SPECIAL={S18={16,14.5},S19={18,-13.5}}
 if SPECIAL[id] then local X,LY=SPECIAL[id][1],SPECIAL[id][2];local lx=lanes[d.lane].x;local face=world(-X,LY,0)
  local eye={lx,face[2]-900,base[3]+170};for _,hr in ipairs({12,21})do add(id..'-lane-'..hr,eye,{face[1],face[2],base[3]+250},70,hr,id)end
  add(id..'-close-21',world(-X-5.5,LY,1.7),world(-X,LY,2.4),80,21,id)
  goto continue end
 -- The frontage table's north/south sign is not the model's: put the door on whichever local-Y side faces the lane centre.
 local lx=lanes[d.lane].x;local s=math.abs(world(d.x,math.abs(d.y),0)[1]-lx)<math.abs(world(d.x,-math.abs(d.y),0)[1]-lx) and 1 or -1
 local dy=s*math.abs(d.y);local dx=d.x
 add(id..'-front-12',world(dx,dy+s*9,1.7),world(dx,dy,3.2),80,12,id)
 add(id..'-front-21',world(dx,dy+s*9,1.7),world(dx,dy,3.2),80,21,id)
 add(id..'-inside-21',world(dx,dy-s*0.9,1.6),world(dx*0.2,dy-s*8,1.0),90,21,id)
 if samples then
  add(id..'-wide-12',world(0,dy+s*15,4.2),world(0,dy,4.4),62,12,id);add(id..'-wide-21',world(0,dy+s*15,4.2),world(0,dy,4.4),62,21,id)
  add(id..'-inside-back-21',world(1.5,dy-s*(math.abs(dy)*2-8.4),1.7),world(-1.0,dy-s*1.5,0.9),88,21,id)
  add(id..'-inside-12',world(dx,dy-s*0.9,1.6),world(dx*0.2,dy-s*8,1.0),90,12,id)
 end
 if upper then for fl,z in pairs({F02=3.8,F03=7.3})do
  add(id..'-'..fl..'-street-21',world(0,dy-s*math.abs(dy)*0.55,z+1.6),world(0,dy,z+1.3),88,21,id)
  add(id..'-'..fl..'-back-12',world(0,dy-s*1.2,z+1.6),world(0,dy-s*math.abs(dy)*1.1,z+1.0),88,12,id)
 end end
 ::continue::
end end
if not next(only) then for name,l in pairs(lanes)do
 for _,hour in ipairs({12,21})do add(name..'-overview-south-'..hour,{l.x,l.y0-1800,l.z+900},{l.x,l.y0+3000,l.z+250},80,hour);add(name..'-overview-north-'..hour,{l.x,l.y1+1800,l.z+900},{l.x,l.y1-3000,l.z+250},80,hour)end
end end
if free then for _,v in ipairs(free)do add(v.id,v.eye,v.target,v.fov or 80,v.hour or 12)end end
local id=os.date('%Y%m%d-%H%M%S');local folder=out..(samples and '/samples-' or '/captures-')..id;local macros=folder..'/Binaries'
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',"New-Item -ItemType Directory -Path '"..macros.."' -ErrorAction Stop|Out-Null"},{hide=true}).code==0)
local function defer(n,s)return string.rep('DEFER ',n)..s end
for i,v in ipairs(views)do
 local dx,dy,dz=v.target[1]-v.eye[1],v.target[2]-v.eye[2],v.target[3]-v.eye[3];local yaw=math.deg(math.atan(dy,dx));local pitch=math.deg(math.atan(dz,math.sqrt(dx*dx+dy*dy)));v.path=folder..'/'..v.id..'.png';v.date='2026.10.26-'..string.format('%02d',v.hour)..'.00.00'
 write(macros..'/view-'..i..'.txt',table.concat({string.format('CityImmersionCapturePose %.6f %.6f %.6f %.6f %.6f',v.eye[1],v.eye[2],v.eye[3],pitch,yaw),'FOV '..v.fov,'set CityEnvironmentController LocalDateTime '..v.date,defer(96,'getall CityEnvironmentController LocalDateTime'),defer(98,'CityImmersionViewPoint '..v.id),defer(99,'r.HighResScreenshotDelay 8'),defer(100,'HighResShot 1600x900 filename='..v.path),defer(125,i<#views and 'exec '..macros..'/view-'..(i+1)..'.txt' or 'quit')},'\n')..'\n')
end
write(macros..'/begin.txt',defer(30,'exec '..macros..'/view-1.txt')..'\n')
local engine='E:/PhysX/UE5.8';local host='E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject';local log=folder..'/native-game.log'
local args=pkg and {pkg.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'} or {engine..'/Engine/Binaries/Win64/UnrealEditor.exe',host..'/StreetSocialCity.uproject','-game'}
for _,v in ipairs({'/Game/UniversityCity/Maps/UniversityCity','-CityImmersionCapture','-unattended','-nosplash','-nosound','-windowed','-ResX=1600','-ResY=900','-d3d12','-norhithread','-NoVSync','-seconds=7200','-UserDir='..root..'/Saved/StreetSocialCityMotelGameUser','-abslog='..log,'-DDC=(Local)','-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem','-ExecCmds=exec '..macros..'/begin.txt'})do args[#args+1]=v end
write(out..'/capture-running.json',{status='running',folder=folder,expected_images=#views,map_sha256=sha});print('Capturing '..#views..' views into '..folder)
local result=ok.proc.run(args,{cwd=root,hide=true,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=7300});assert(result.code==0,'Native Game failed: '..log)
local missing=0
for _,v in ipairs(views)do local f=io.open(v.path,'rb');if f then f:close();v.sha256=h.sha256_file(v.path)else missing=missing+1;v.missing=true end end
assert(h.sha256_file(map)==sha)
write(out..'/captures.json',{status='captured_requires_visual_review',folder=folder,map_sha256=sha,expected_images=#views,missing=missing,images=views,scope='Actual uncooked native -game preview (E engine), not packaged acceptance.'})
print('Captured '..(#views-missing)..'/'..#views..' images: '..folder)
