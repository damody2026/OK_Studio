-- Isolated E-engine native worker for the user-authorized motel/restroom revision.
local f=assert(io.open('Tools/street_city_romance_pbr.lua','rb'));local source=f:read('*a');f:close()
local helper=assert(source:match('local code=%[====%[(.-)%]====%]')):match('^(.-)\ndef work%(%)')
local ground=dofile('Tools/street_city_ground_pbr_payload.lua'):match('^(.-)\ndef work%(%)')
local code=helper..'\n'..ground..'\n'..dofile('Tools/street_city_motel_payload.lua')
local function replace(p,v)local n;source,n=source:gsub(p,function()return v end);assert(n==1,p)end
replace("local out=root%.%.'/output/street%-social%-city%-production/romance%-pbr%-v1'","local out=root..'/output/street-social-city-production/motel-v1'")
replace('local code=%[====%[.-%]====%]','local code=[====['..code..']====]')
replace("root%.%.'/StreetSocialCity/StreetSocialCity%.uproject'","'E:/StreetSocialCityProduction/environment-packages/20261023-145531/HostProject/StreetSocialCity.uproject'")
replace("local engine=json.decode%(read%('Tools/engine.local.json'%)%)%.engine","local engine='E:/PhysX/UE5.8'")
source=source:gsub('restore=true','restore=true,serve=true'):gsub('StreetSocialCityRomanceUser','StreetSocialCityMotelRevisionUser')
assert(not arg[2] or arg[2]=='d3d12');if arg[2]~='d3d12'then source=source:gsub("'%-d3d12'","'-nullrhi'")end
source=source:gsub("'%-unattended'","'-EnablePlugins=PythonScriptPlugin,EditorScriptingUtilities,CityDepthAudit,GeometryScripting','-unattended','-DDC=(Local)'")
assert(load(source,'motel-native-launcher'))()
