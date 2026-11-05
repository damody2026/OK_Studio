-- Continue a specific E-engine package through native, PIE and content checks.
-- Visual approval is deliberately left to the primary agent after reviewing files.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json')
local root=ok.root:gsub('\\','/'):gsub('%s+$','')
local out=root..'/output/street-social-city-production/day-night-v1'
local id=assert(arg[1],'Pass the exact package ID')
local resume=arg[2];assert(not resume or resume=='resume-logic','Unexpected resume mode')
assert(id:match('^%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d$'),'Unexpected package ID')
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(path,v)local f=assert(io.open(path,'wb'));f:write(json.encode(v));f:close()end
local engine='E:/PhysX/UE5.8'
local state={status='running',package_id=id,engine=engine,stages={}}
local function save()write(out..'/e-validation-workflow.json',state)end
local function stage(name,argv,env)
 state.phase=name;save()
 local log=out..'/e-validation-'..id..'-'..name..'.log'
 local r=ok.proc.run(argv,{cwd=root,hide=true,env=env,stdout_file=log,stderr_file=log..'.stderr',timeout=7200})
 state.stages[#state.stages+1]={name=name,exit_code=r.code,log=log};save()
 assert(r.code==0,name..' failed; inspect '..log)
end
local function work()
 state.phase='waiting_for_exact_E_package';save()
 local started=os.time();local package_receipt
 repeat
  package_receipt=read(out..'/package.json')
  if package_receipt.id~=id then
   assert(os.time()-started<10800,'Timed out waiting for the package')
   assert(ok.proc.run({'powershell.exe','-NoProfile','-Command','Start-Sleep -Seconds 20'},{hide=true,timeout=30}).code==0)
  end
 until package_receipt.id==id
 assert(package_receipt.engine==engine and package_receipt.exit_code==0 and package_receipt.status=='built_requires_runtime_validation','Exact E-engine package did not succeed')
 assert(package_receipt.map_sha256==read(out..'/current-map.json').map_sha256,'Map changed after package')
 state.map_sha256=package_receipt.map_sha256;state.target=package_receipt.target
 local lua=root..'/Tools/lua/lua.exe'
 local executable=package_receipt.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'
 local exists=assert(io.open(executable,'rb'),'Exact staged executable is missing');exists:close();state.executable=executable
 if not resume then
  stage('packaged-runtime',{lua,'Tools/run_street_city_environment_game.lua','package',executable,'profile','motion'})
  stage('prepare-review-host',{lua,'Tools/prepare_street_city_environment_review.lua'})
 else
  local passed=read(out..'/runtime-package-launch.json');local review=read(out..'/review-host.json')
  assert(passed.status=='passed' and passed.engine==engine and passed.map_sha256==package_receipt.map_sha256 and review.status=='passed' and review.engine==engine and review.package_id==id,'Prior package audit and review host must match')
  state.reused_successful_package_audit=passed.native_receipt;state.reused_review_host=review.project
 end
 local env={STREET_CITY_ENVIRONMENT_PROJECT=package_receipt.host..'/StreetSocialCity.uproject'}
 if resume then env.STREET_CITY_ENVIRONMENT_NULL_RHI='1';stage('pie-runtime-logic',{lua,'Tools/run_street_city_environment_game.lua','pie'},env);env.STREET_CITY_ENVIRONMENT_NULL_RHI=nil
 else stage('pie-runtime',{lua,'Tools/run_street_city_environment_game.lua','pie','motion'},env) end
 stage('native-content-validation',{lua,'Tools/street_city_day_night.lua','validate'},env)
 if not resume then
  write(out..'/render-request.json',{set='polish',sequence={'office','preview'}})
  stage('native-detail-captures',{lua,'Tools/street_city_day_night.lua','render'},env)
 else
  stage('actual-packaged-detail-captures',{lua,'Tools/capture_street_city_packaged_views.lua'})
 end
 state.status='automated_checks_complete_requires_visual_review';state.phase='primary_agent_visual_review';save()
end
local passed,err=pcall(work)
if not passed then state.status='failed';state.error=tostring(err);save();error(err)end
print('E-engine automated checks completed; review native captures and depth evidence before acceptance.')
