-- Invoke only after viewing every contact sheet for this immutable source run.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local out='output/street-social-city-production/immersion-v1/'
local id=assert(arg[1],'Pass source-physics run ID');assert(id:match('^source%-physics%-%d+%-%d+$'))
local sheets=assert(tonumber(arg[2]));local notes=assert(arg[3],'Describe actually viewed results and remaining scope')
local function read(p)local f=assert(io.open(p,'rb'));local x=j.decode(f:read('*a'));f:close();return x end
local launch=read(out..id..'-launch.json');local manifest=read(out..id..'-images.json');local native=read(out..id..'.json');local prepared=read(out..id..'-review/prepared.json')
assert(launch.status=='passed' and launch.source_unchanged and launch.full_route_coverage_passed and native.status=='passed')
assert(manifest.map_sha256==launch.map_sha256 and native.supplied_plan_map_sha256==launch.map_sha256)
assert(#manifest.images>0 and prepared.original_images==#manifest.images and sheets==math.ceil(#manifest.images/8) and prepared.contact_sheets==sheets)
for _,r in ipairs(manifest.images)do assert(h.sha256_file(r.path)==r.sha256,'Reviewed image changed')end
local review={status='passed_reviewed_source_scope',reviewed_at=os.date('%Y-%m-%dT%H:%M:%S')..'+08:00',run_id=id,map_sha256=launch.map_sha256,native_receipt=id..'.json',native_images_manifest=id..'-images.json',original_images=#manifest.images,contact_sheets_reviewed=sheets,soak_seconds=launch.soak_seconds,completed_walk_routes=launch.completed_walk_routes,observations=notes,scope='Actually viewed native source Game images and matching immutable physics receipt. This is source iteration evidence; final freshly cooked scene and its own moving/render/UI acceptance remain required. Stills do not certify global temporal zero z-fighting.'}
local f=assert(io.open(out..id..'-visual-review.json','wb'));f:write(j.encode(review));f:close();print('Recorded '..#manifest.images..' source native images; final cooked acceptance remains separate.')
