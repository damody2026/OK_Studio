package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local out='output/street-social-city-production/white-paths-v1'
local function run(tool,args)
 local list={ok.root..'/Tools/lua/lua.exe',tool};for _,v in ipairs(args or {})do list[#list+1]=v end
 print(tool);io.stdout:flush()
 local r=ok.proc.run(list,{hide=true,cwd=ok.root,stdout_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.log',stderr_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.stderr',timeout=10800});assert(r.code==0,'Failed: '..tool)
end
if arg[1]~='capture' then run('Tools/street_city_white_paths.lua',{'revision_audit'});run('Tools/repackage_street_city_white_paths.lua')end
run('Tools/capture_street_city_white_paths.lua')
print('White paths captured. Primary visual review required.')
