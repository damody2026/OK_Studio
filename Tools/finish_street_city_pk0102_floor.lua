package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local out='output/street-social-city-production/pk0102-floor-v1'
local function run(tool,args)
 local list={ok.root..'/Tools/lua/lua.exe',tool};for _,v in ipairs(args or {})do list[#list+1]=v end
 print(tool);io.stdout:flush();local r=ok.proc.run(list,{hide=true,cwd=ok.root,stdout_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.log',stderr_file=out..'/'..tool:match('([^/]+)%.lua$')..'-workflow.stderr',timeout=10800});assert(r.code==0,'Failed: '..tool)
end
if arg[1]~='capture' then
 local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
 local install=read(out..'/install.json');local audit=read(out..'/audit.json')
 if audit.status~='passed' or audit.map_sha256~=install.map_sha256 or audit.changed_slots~=17 then run('Tools/street_city_pk0102_floor.lua',{'revision_audit'})end
 run('Tools/repackage_street_city_pk0102_floor.lua')
end
run('Tools/capture_street_city_pk0102_floor.lua')
print('Targeted floor capture complete; primary review required.')
