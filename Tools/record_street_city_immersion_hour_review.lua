package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local out='output/street-social-city-production/immersion-v1/'
local function read(n)local f=assert(io.open(out..n..'.json','rb'));local x=j.decode(f:read('*a'));f:close();return x end
local id=assert(arg[1],'Pass immutable physics run ID');assert(id:match('^physics%-%d+%-%d+$'))
local count=assert(tonumber(arg[2]),'Pass actual reviewed sheet count');local observations=assert(arg[3],'Describe actual observations')
local launch=read(id..'-launch');local images=read(id..'-images')
local f=assert(io.open('output/street-social-city-production/day-night-v1/package.json','rb'));local package=j.decode(f:read('*a'));f:close()
local prepared=read(id..'-review/prepared')
assert(launch.status=='passed' and launch.map_sha256==package.map_sha256)
if launch.package_id~=package.id then local eq=read('render-recook-equivalence');assert(eq.status=='passed' and eq.before_package==launch.package_id and eq.after_package==package.id and eq.serialized_chunks_checked==2502 and eq.game_sha256==launch.executable_sha256)end
assert(launch.soak_seconds>=3600 and launch.full_route_coverage_passed and launch.completed_walk_routes>=77)
assert(#images.images==prepared.original_images and count==prepared.contact_sheets and count==math.ceil(#images.images/8))
for _,r in ipairs(images.images)do assert(h.sha256_file(r.path)==r.sha256)end
local review={status='passed_reviewed_scope',reviewed_at=os.date('%Y-%m-%dT%H:%M:%S')..'+08:00',package_id=launch.package_id,map_sha256=launch.map_sha256,native_receipt=id..'.json',original_images=#images.images,contact_sheets_reviewed=count,observations=observations,scope='Manual review of every final native CharacterMovement soak screenshot; all77 planned routes covered. Moving render checks and geometry probes remain separate; no global mathematical zero-z-fighting claim.'}
local f=assert(io.open(out..id..'-review.json','wb'));f:write(j.encode(review));f:close();print('Recorded final walking review '..id)
