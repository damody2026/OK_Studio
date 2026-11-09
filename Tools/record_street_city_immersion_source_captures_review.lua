-- Manual attestation after actually viewing all combined source contact sheets.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/'
local function read(p)local f=assert(io.open(p,'rb'));local x=j.decode(f:read('*a'));f:close();return x end
local c=read(root..'all_current/captures.json');local sheets=assert(tonumber(arg[1]));local notes=assert(arg[2])
assert(c.exit_code==0 and #c.images==354 and sheets==45 and c.source_run_id and c.source_runtime)
local mirrors=0
for _,r in ipairs(c.images)do
 assert(h.sha256_file(r.path)==r.sha256 and r.actual_camera_cm and r.configured_mirror_count==12 and r.active_planar_mirrors<=2)
 if r.id:match('^mirror%-')then assert(r.active_planar_mirrors>=1);mirrors=mirrors+1 end
end
assert(mirrors==48)
local receipt={status='reviewed_source_scope',map_sha256=c.map_sha256,source_run_id=c.source_run_id,original_images=354,contact_sheets_reviewed=sheets,mirror_images=mirrors,observations=notes,scope='Manual source Game iteration review only;fresh cooked matching-map acceptance remains required.'}
local f=assert(io.open(root..'all_current/visual-review.json','wb'));f:write(j.encode(receipt));f:close();print('Recorded354 source images and48 mirror inspections;final cooked acceptance remains separate')
