-- Dedicated launcher for runtime day/night integration and independent surface audits.
local f=assert(io.open('Tools/street_city_romance_pbr.lua','rb'));local s=f:read('*a');f:close()
local helper=assert(s:match('local code=%[====%[(.-)%]====%]')):match('^(.-)\ndef work%(%)')
local payload=dofile('Tools/street_city_day_night_payload.lua')
payload=dofile('Tools/street_city_office_layout_payload.lua')..'\n'..payload
payload=dofile('Tools/street_city_detail_depth_payload.lua')..'\n'..dofile('Tools/street_city_world_sheet_payload.lua')..'\n'..dofile('Tools/street_city_street_surface_payload.lua')..'\n'..dofile('Tools/street_city_facing_payload.lua')..'\n'..dofile('Tools/street_city_visual_polish_payload.lua')..'\n'..payload
local function replace(p,v)local n;s,n=s:gsub(p,function()return v end);assert(n==1,p)end
replace("local out=root%.%.'/output/street%-social%-city%-production/romance%-pbr%-v1'","local out=root..'/output/street-social-city-production/day-night-v1'")
replace('local code=%[====%[.-%]====%]','local code=[====['..helper..'\n'..payload..']====]')
s=s:gsub('StreetSocialCityRomanceUser','StreetSocialCityEnvironmentUser')
local project=os.getenv('STREET_CITY_ENVIRONMENT_PROJECT')
if not project then
 local f=io.open('output/street-social-city-production/day-night-v1/review-host.json','rb')
 if f then local review=require('ok.json').decode(f:read('*a'));f:close();if review.status=='passed' and review.engine=='E:/PhysX/UE5.8' then project=review.project end end
end
if project then
 project=project:gsub('\\','/')
 assert(project:match('^E:/StreetSocialCityProduction/environment%-packages/%d+%-%d+/HostProject/StreetSocialCity%.uproject$'),'Unexpected isolated E-engine project')
 local n;s,n=s:gsub("root%.%.'/StreetSocialCity/StreetSocialCity%.uproject'",function()return string.format('%q',project)end);assert(n==1,'Project override failed')
 s=s:gsub("'%-unattended'","'-EnablePlugins=PythonScriptPlugin,EditorScriptingUtilities,CityDepthAudit','-unattended'")
end
s=s:gsub('restore=true','restore=true,probe=true,facing_probe=true,facing=true,water_spacing=true,prop_cull=true,world_probe=true,world_shader=true,world_apply=true,street_shader=true,street_probe=true,street_sources=true,street_union=true,street_apply=true,tactile_sources=true,tactile_union=true,tactile_apply=true,sites=true,routes=true,depth=true,depth_export=true,prepare=true,spacing=true,cull=true,cull_solids=true,cull_review=true,sports=true,visual_polish=true,flower_refine=true,finish=true,validate=true,guard=true,refine=true,lookdev=true,verify=true')
if ({inventory=true,audit=true,shader=true,sites=true,routes=true,depth=true,depth_export=true,prepare=true,spacing=true,cull=true,cull_solids=true,cull_review=true,sports=true,visual_polish=true,flower_refine=true,finish=true,validate=true,guard=true,refine=true,restore=true,verify=true,probe=true,facing_probe=true,facing=true,water_spacing=true,prop_cull=true,world_probe=true,world_shader=true,world_apply=true,street_shader=true,street_probe=true,street_sources=true,street_union=true,street_apply=true,tactile_sources=true,tactile_union=true,tactile_apply=true})[arg[1]] then s=s:gsub("'%-d3d12'","'-nullrhi'") else s=s:gsub("'%-d3d12'","'-d3d12','-norhithread'") end
s=s:gsub('spacing=true','spacing=true,footing_spacing=true,office_probe=true,office_preview=true,office_apply=true,moon_refine=true')
if arg[1]=='footing_spacing' or arg[1]=='office_probe' or arg[1]=='office_preview' or arg[1]=='office_apply' or arg[1]=='moon_refine' then s=s:gsub("'%-d3d12'","'-nullrhi'") end
s=s:gsub('Romance PBR ','City day-night ')
s=s:gsub("result.status=='passed' or", "result.status=='passed' or (mode=='render' and result.status=='captured_with_missing_cameras') or (mode=='office_preview' and result.status=='prepared_requires_apply') or")
s=s:gsub("print%('City day%-night '%.%.mode%.%.' passed'%)", "print('City day-night '..mode..' '..result.status)")
s=s:gsub("'%-unattended'","'-unattended','-DDC=(Local)','-LocalDataCachePath=E:/StreetSocialCityProduction/unreal-ddc/FileSystem','-ini:Engine:[ConsoleVariables]:Editor.AsyncAssetCompilationMaxMemoryUsage=6'")
s=s:gsub("local engine=json.decode%(read%('Tools/engine.local.json'%)%)%.engine",[====[
local syntaxResult=require('ok').proc.run({'python','-c','import ast,json,sys;ast.parse(json.load(open(sys.argv[1],encoding="utf8"))["code"])',payloadpath},{hide=true,timeout=20})
assert(syntaxResult.code==0,'Embedded Python syntax failed before Editor launch: '..tostring(syntaxResult.stderr or syntaxResult.stdout))
local engine='E:/PhysX/UE5.8'
]====])
assert(load(s,'city-environment-launcher'))()
