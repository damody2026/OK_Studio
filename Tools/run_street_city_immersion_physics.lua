-- Replay native physics expectations and optionally soak an immutable cooked stage.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/immersion-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=j.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(j.encode(d));f:close()end
local seconds=tonumber(arg[1] or '0');assert(seconds and seconds>=0 and seconds<=7200)
local package=read(root..'/output/street-social-city-production/day-night-v1/package.json');local build=read(out..'/native-audit-build/build.json');local planpath=out..'/game-physics-plan.json';local plan=read(planpath)
assert(package.engine=='E:/PhysX/UE5.8' and package.exit_code==0 and package.source_map_bytes_and_receipt_unchanged)
assert(plan.map_sha256==package.map_sha256 and build.status=='passed' and package.prebuilt_game_sha256==build.game_sha256,'Stage must contain the reviewed opt-in audit binary and matching physics plan')
local expected=out..'/packages/'..package.id;assert(package.target==expected,'Unexpected stage target')
local exe=expected..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe';local exe_before=h.sha256_file(exe);assert(exe_before==build.game_sha256)
local listing=ok.proc.run({'rg','--files','-uuu',expected..'/Stage/Windows/StreetSocialCity/Content/Paks'},{capture=true,hide=true});assert(listing.code==0);local paks={}
for p in listing.stdout:gmatch('[^\r\n]+')do p=p:gsub('\\','/');assert(p:sub(1,#expected)==expected and p:match('%.pak$'),'Unexpected staged data file');paks[#paks+1]={path=p,sha256=h.sha256_file(p)}end
assert(#paks>0);local id=os.date('%Y%m%d-%H%M%S');local plan_source_sha=h.sha256_file(planpath);planpath=out..'/physics-'..id..'-plan.json';assert(not io.open(planpath,'rb'));write(planpath,plan);local plan_sha=h.sha256_file(planpath);local receipt=out..'/physics-'..id..'.json';local log=out..'/physics-'..id..'.log'
local args={exe,'/Game/UniversityCity/Maps/UniversityCity','-CityImmersionAudit='..receipt,'-CityImmersionPlan='..planpath,'-CityImmersionSoakSeconds='..seconds,'-unattended','-nosplash','-nosound','-windowed','-ResX=1920','-ResY=1080','-NoVSync','-d3d12','-norhithread','-UserDir='..root..'/Saved/StreetSocialCityImmersionPhysicsUser','-abslog='..log,'-DDC=(Local)','-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem','-ExecCmds=t.MaxFPS 60'}
for i,v in ipairs(args)do if v:find('-UserDir=',1,true)==1 then args[i]=v..'-'..id end end
write(out..'/physics-running.json',{status='running',package_id=package.id,map_sha256=plan.map_sha256,native_receipt=receipt,log=log,soak_seconds=seconds})
local r=ok.proc.run(args,{hide=true,cwd=root,stdout_file=log..'.stdout',stderr_file=log..'.stderr',timeout=seconds+1200})
local f=io.open(receipt,'rb');local report=f and read(receipt) or {};if f then f:close()end
local unchanged=exe_before==h.sha256_file(exe) and plan_sha==h.sha256_file(planpath)
for _,p in ipairs(paks)do unchanged=unchanged and h.sha256_file(p.path)==p.sha256 end
local passed=r.code==0 and report.status=='passed' and report.supplied_plan_map_sha256==plan.map_sha256 and report.cooked_physics_passed==true and unchanged and (not plan.player_start or report.player_start_passed and report.normal_input_smoke_passed)
local length=0;for _,route in ipairs(plan.walk_routes)do for i=2,#route.points do local a,b=route.points[i-1],route.points[i];length=length+math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)end end
local full_route_expected=seconds>=length/140+300;local coverage_ok=not full_route_expected or (report.completed_walk_routes or 0)>=#plan.walk_routes
local image_rows={};for _,v in ipairs(report.soak_images or {})do local f=assert(io.open(v.path,'rb'),'Missing actual native soak image: '..v.path);local header=f:read(24);f:close();assert(header:sub(1,8)=='\137PNG\r\n\26\n');local w,height=string.unpack('>I4I4',header,17);assert(w==1920 and height==1080,'Unexpected native soak image dimensions');image_rows[#image_rows+1]={path=v.path,sha256=h.sha256_file(v.path),width=w,height=height}end
passed=passed and coverage_ok and (seconds<=60 or #image_rows>0)
write(out..'/physics-'..id..'-images.json',{status='verified_native_files',package_id=package.id,map_sha256=plan.map_sha256,images=image_rows})
local launch={status=passed and 'passed' or 'failed',package_id=package.id,map_sha256=plan.map_sha256,engine=package.engine,executable=exe,executable_sha256=exe_before,paks=paks,plan_sha256=plan_sha,source_plan_sha256=plan_source_sha,immutable_plan_path=planpath,immutable_stage_unchanged=unchanged,native_receipt=receipt,log=log,exit_code=r.code,soak_seconds=seconds,walk_routes_expected=#plan.walk_routes,completed_walk_routes=report.completed_walk_routes,route_loop_metres=length/100,full_route_expected=full_route_expected,full_route_coverage_passed=coverage_ok,native_images_manifest=out..'/physics-'..id..'-images.json',native_image_count=#image_rows,scope='Actual cooked D3D12 Game physics; source map can evolve separately while this immutable staged checkpoint is soaked.'}
write(out..'/physics-'..id..'-launch.json',launch);write(out..'/physics-launch-latest.json',launch)
assert(passed,'Cooked physics/walking audit failed or full-route coverage incomplete: '..receipt);print('Cooked physics/walking audit passed: '..receipt)
