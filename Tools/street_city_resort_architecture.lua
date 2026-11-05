-- Reuse the verified hidden editor launcher; all new editor code stays embedded Lua.
local f=assert(io.open('Tools/street_city_romance_pbr.lua','rb'));local s=f:read('*a');f:close()
local helper=assert(s:match('local code=%[====%[(.-)%]====%]'))
helper=assert(helper:match('^(.-)\ndef work%(%)'))
local payload=dofile('Tools/street_city_resort_architecture_payload.lua')
local relief=dofile('Tools/street_city_relief_signs_payload.lua')
payload=payload:gsub('\nassert unreal.EditorLevelLibrary.load_level',function()return '\n'..relief..'\nassert unreal.EditorLevelLibrary.load_level' end)
local function replace(pattern,value)local n;s,n=s:gsub(pattern,function()return value end);assert(n==1,pattern)end
replace("local out=root%.%.'/output/street%-social%-city%-production/romance%-pbr%-v1'","local out=root..'/output/street-social-city-production/resort-architecture-v1'")
replace('shader=true,inventory=true,plan=true,install=true,audit=true,render=true,restore=true','shader=true,inventory=true,plan=true,install=true,audit=true,render=true,restore=true')
replace('local code=%[====%[.-%]====%]','local code=[====['..helper..'\n'..payload..']====]')
s=s:gsub('StreetSocialCityRomanceUser','StreetSocialCityArchitectureUser')
if RESORT_NIGHT_AUDIT then s=s:gsub("'%-d3d12'","'-nullrhi'")
elseif RESORT_NIGHT_CAPTURE then s=s:gsub("'%-d3d12'","'-d3d12','-norhithread'") end
s=s:gsub('Romance PBR ','Resort architecture ')
-- Receipts should point reviewers to this wrapper, not the reused source library.
s=s:gsub("source=root%.%.'/Tools/street_city_romance_pbr.lua::UnrealPayload'","source=root..'/Tools/street_city_resort_architecture.lua::UnrealPayload'")
assert(load(s,'resort-architecture-launcher'))()
