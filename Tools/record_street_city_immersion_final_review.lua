-- Manual attestation only: run after actually viewing all 72 final sheets.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local out='output/street-social-city-production/immersion-v1/'
assert(tonumber(arg[1])==72,'All 72 final contact sheets must be viewed')
local observations=assert(arg[2],'Describe actual observations; unresolved defects require repair before this receipt')
local function read(p)local f=assert(io.open(p,'rb'));local x=j.decode(f:read('*a'));f:close();return x end
local c=read(out..'captures.json');local p=read('output/street-social-city-production/day-night-v1/package.json')
assert(c.exit_code==0 and c.engine=='E:/PhysX/UE5.8' and #c.images==573 and c.package_id==p.id and p.id>='20261024-131500')
assert(c.map_sha256==p.map_sha256 and h.sha256_file('StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==c.map_sha256)
local floors,moon,cycle,ids,mirrors={},{},{},{},{}
for _,r in ipairs(c.images)do
 assert(not ids[r.id] and h.sha256_file(r.path)==r.sha256,'Duplicate ID or altered native image');ids[r.id]=true
 assert(r.actual_camera_cm and r.actual_camera_fov and math.abs(r.actual_camera_fov-r.fov)<.03,'Missing native optical camera verification')
 for i=1,3 do assert(math.abs(r.actual_camera_cm[i]-r.eye[i])<.2,'Optical eye mismatch')end
 if r.id:match('^floor%-')then floors[#floors+1]=r.id end
 if r.id:match('^moon%-framed%-')then moon[#moon+1]=r.id end
 if r.id:match('^cycle%-')then cycle[#cycle+1]=r.id end
 if r.id:match('^mirror%-')then assert(r.configured_mirror_count==12 and r.active_planar_mirrors>=1 and r.active_planar_mirrors<=2);mirrors[#mirrors+1]=r.id end
end
assert(#floors==178 and #moon==3 and #cycle==25 and #mirrors==48,'Final floor/moon/day-cycle/mirror coverage incomplete')
local receipt={status='passed_reviewed_scope',reviewed_at=os.date('%Y-%m-%dT%H:%M:%S')..'+08:00',package_id=p.id,map_sha256=c.map_sha256,original_images=573,contact_sheets_reviewed=72,floor_day_night_images=#floors,framed_moon_images=#moon,dated_hourly_images=#cycle,observations=observations,scope='Manual review of all final staged native D3D12 screenshots. Original pixels and hashes retained. Includes every school floor representative room or public foyer by day/night, five gates, street/crossing approaches, level-park approaches,twelve large indoor mirrors from front/oblique views,restored connection rails,outdoor sites and repair details. Separate final moving CharacterMovement/physics, UI and full-day receipts are required; stills alone do not prove absence of temporal z-fighting.'}
local f=assert(io.open(out..'visual-review-final.json','wb'));f:write(j.encode(receipt));f:close();print('Recorded actual final 573-image manual review for '..p.id)
