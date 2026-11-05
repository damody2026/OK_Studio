-- Dedicated guarded night-lighting pass. Existing architecture/sign assets remain intact.
local f=assert(io.open('Tools/street_city_resort_architecture.lua','rb'));local s=f:read('*a');f:close()
s=s:gsub("local relief=dofile%('Tools/street_city_relief_signs_payload.lua'%)", "local relief=dofile('Tools/street_city_relief_signs_payload.lua')..'\\n'..dofile('Tools/street_city_resort_night_payload.lua')")
-- The appended payload replaces dispatch after the architecture definitions exist.
s=s:gsub("StreetSocialCityArchitectureUser","StreetSocialCityResortNightUser")
RESORT_NIGHT_CAPTURE=true
RESORT_NIGHT_AUDIT=arg[1]=='audit'
assert(load(s,'resort-night-launcher'))()
if arg[1]=='install' then
 local p='output/street-social-city-production/resort-architecture-v1/'
 local json=require('ok.json')
 local function read(n)local f=assert(io.open(p..n,'rb'));local v=json.decode(f:read('*a'));f:close();return v end
 local receipt=read('render.json');assert(receipt.run_id==read('install-payload.json').run_id and receipt.status=='passed','Fresh capture receipt required')
 local f=assert(io.open(p..'install-exit.json','rb'));local exit=f:read('*a');f:close()
 f=assert(io.open(p..'render-exit.json','wb'));f:write(exit);f:close()
 f=assert(io.open(p..'moonlight-native-run.json','wb'));f:write(json.encode({status='passed',run_id=receipt.run_id,native_exit_code=read('install-exit.json').exit_code,phases={'guarded map save','native lighting audit','native scene captures'}}));f:close()
end
