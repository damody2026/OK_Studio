-- Recover diagnostic source-game views whose fresh user profile allowed the
-- clock to advance seconds. Preserve reflected actual times; never relabel as
-- exact-time packaged acceptance. Future captures explicitly pause the clock.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash')
local out='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/preview'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local running=json.decode(read(out..'/captures-running.json'));local logpath=running.folder..'/native-game.log';local log=read(logpath)
assert(not log:find('missing usage flag InstancedStaticMeshes',1,true) and not log:find('Failed to compile Material',1,true))
local times={};for d in log:gmatch('LocalDateTime = (%d%d%d%d%.%d%d%.%d%d%-%d%d%.%d%d%.%d%d)')do times[#times+1]=d end
assert(#times==#running.views,'Reflected source Game clock count differs')
for i,v in ipairs(running.views)do
 assert(times[i]:sub(1,13)==v.date:sub(1,13) and tonumber(times[i]:sub(15,16))<5,'Actual preview time is outside the diagnostic five-minute window: '..times[i]);v.actual_date=times[i]
 local bytes=read(v.path);assert(bytes:sub(1,8)=='\137PNG\13\10\26\10');v.sha256=hash.sha256_file(v.path)
end
assert(log:find('LogExit: Exiting.',1,true));assert(hash.sha256_file('C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==running.map_sha256)
local result={status='diagnostic_uncooked_preview',source_runtime='UnrealEditor -game; not staged acceptance',source_run_id=running.source_run_id,map_sha256=running.map_sha256,native_log=logpath,images=running.views,clock_note='Initial fresh source-Game profile advanced while shaders compiled. Actual reflected timestamps are preserved, within five minutes of the requested hour; future captures explicitly pause. These are diagnostic previews. Final staged exact-clock capture remains required.'}
local f=assert(io.open(out..'/captures.json','wb'));f:write(json.encode(result));f:close();print('Preserved '..#times..' diagnostic source-game views with actual reflected timestamps')
