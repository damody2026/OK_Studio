-- Continue the ordered E-engine delivery after the upper-floor native verification.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local out='output/street-social-city-production/ground-pbr-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local proof=read(out..'/verify.json');assert(proof.status=='passed' and #proof.native_collision_probes==6)
local function run(tool,args)
 local list={ok.root..'/Tools/lua/lua.exe',tool};for _,v in ipairs(args or {})do list[#list+1]=v end
 print('Ground delivery: '..tool..' '..table.concat(args or {},' '));io.stdout:flush()
 local r=ok.proc.run(list,{hide=true,cwd=ok.root,stdout_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.log',stderr_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.stderr',timeout=10800});assert(r.code==0,'Delivery step failed: '..tool)
end
assert(not arg[1] or arg[1]=='runtime','Only runtime resumes the final two steps')
if arg[1]~='runtime' then
 run('Tools/street_city_ground_pbr.lua',{'complete'})
 run('Tools/repackage_street_city_ground_pbr.lua')
end
local package=read('output/street-social-city-production/day-night-v1/package.json');assert(package.exit_code==0 and package.engine=='E:/PhysX/UE5.8')
run('Tools/run_street_city_ground_runtime.lua',{'package',package.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe','profile','motion'})
run('Tools/capture_street_city_ground_pbr.lua')
print('Native ground delivery captured. Primary visual review and publication remain required.')
