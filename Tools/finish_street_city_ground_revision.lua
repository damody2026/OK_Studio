package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local out='output/street-social-city-production/ground-pbr-v2'
local function run(tool,args)
 local list={ok.root..'/Tools/lua/lua.exe',tool};for _,v in ipairs(args or {})do list[#list+1]=v end
 print(tool);io.stdout:flush()
 local r=ok.proc.run(list,{hide=true,cwd=ok.root,stdout_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.log',stderr_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.stderr',timeout=10800});assert(r.code==0,'Failed: '..tool)
end
if arg[1]~='runtime' then run('Tools/street_city_ground_revision.lua',{'revision_audit'});run('Tools/repackage_street_city_ground_revision.lua')end
local f=assert(io.open('output/street-social-city-production/day-night-v1/package.json','rb'));local package=json.decode(f:read('*a'));f:close();assert(package.exit_code==0)
run('Tools/run_street_city_ground_revision_runtime.lua',{'package',package.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe','profile','motion'})
run('Tools/capture_street_city_ground_revision.lua')
print('Revision captured; primary image review remains required.')
