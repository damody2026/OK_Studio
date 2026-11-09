-- Explicitly attributed phased review; never relabel old pixels as a new cook.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local o='output/street-social-city-production/immersion-v1/'
local function read(p)local f=assert(io.open(p,'rb'));local r=j.decode(f:read('*a'));f:close();return r end
local function write(p,r)local f=assert(io.open(p,'wb'));f:write(j.encode(r));f:close()end
local old=read(o..'checkpoint-20261024-135124/captures.json');assert(#old.images==573 and old.package_id=='20261024-135124')
if arg[1]=='checkpoint' then
 assert(tonumber(arg[2])==521,'View all65 complete sheets plus the first image of sheet66')
 local rows={};for i=1,521 do local r=old.images[i];assert(not r.id:match('^mirror%-') and not r.id:match('^connection%-'));assert(h.sha256_file(r.path)==r.sha256);rows[#rows+1]={id=r.id,path=r.path,sha256=r.sha256}end
 write(o..'checkpoint-20261024-135124/nonmirror-visual-review.json',{status='passed_nonmirror_scope',package_id=old.package_id,map_sha256=old.map_sha256,original_images=521,complete_sheets=65,partial_sheet=66,observations=assert(arg[3]),images=rows,scope='All521 non-mirror/non-connection original checkpoint images personally viewed. Its failed mirror images are expressly excluded and cannot be published as passing.'});print('Recorded521 actual non-mirror checkpoint reviews');return
end
assert(arg[1]=='final','Use checkpoint or final')
local previous=read(o..'checkpoint-20261024-135124/nonmirror-visual-review.json');local c=read(o..'render-repair-captures.json');local p=read('output/street-social-city-production/day-night-v1/package.json');local eq=read(o..'render-recook-equivalence.json')
assert(previous.status=='passed_nonmirror_scope' and previous.original_images==521 and c.exit_code==0 and c.package_id==p.id and c.map_sha256==p.map_sha256 and p.map_sha256==old.map_sha256)
assert(eq.status=='passed' and eq.before_package==old.package_id and eq.after_package==p.id and eq.serialized_chunks_checked==2502 and eq.game_sha256==p.prebuilt_game_sha256)
assert(tonumber(arg[2])==math.ceil(#c.images/8),'View every final renderer repair sheet')
local fresh={};local mirrors,connections=0,0
for _,r in ipairs(c.images)do
 assert(not fresh[r.id] and h.sha256_file(r.path)==r.sha256 and r.actual_clip_plane_enabled and r.actual_reflection_method==2)
 if r.id:match('^mirror%-')then assert(r.configured_mirror_count==12 and r.active_planar_mirrors>=1 and r.active_planar_mirrors<=2 and r.mirror_capture_percent==75 and r.mirror_prefilter_roughness==0);mirrors=mirrors+1 end
 if r.id:match('^connection%-')then connections=connections+1 end
 r.package_id=c.package_id;fresh[r.id]=r
end
assert(mirrors==48 and connections==4)
local merged={};local reused=0
for i,r in ipairs(old.images)do
 local new=fresh[r.id]
 if new then merged[#merged+1]=new;fresh[r.id]=nil else assert(i<=521 and h.sha256_file(r.path)==r.sha256);r.package_id=old.package_id;merged[#merged+1]=r;reused=reused+1 end
end
assert(not next(fresh) and #merged==573)
local result={status='reviewed_with_explicit_checkpoint_provenance',package_id=p.id,map_sha256=p.map_sha256,engine='E:/PhysX/UE5.8',executable=c.executable,expected_images=573,exit_code=0,images=merged,final_renderer_images=#c.images,prior_checkpoint_images=reused,geometry_equivalence='render-recook-equivalence.json',scope='Same source map, executable and2502 serialized map/static-mesh chunks. Every image retains its actual package_id. All48 mirror views and4 connection views are from the repaired full cook; old failed mirror pixels are excluded.'}
write(o..'captures-final-reviewed.json',result)
write(o..'visual-review-final.json',{status='passed_reviewed_scope',package_id=p.id,map_sha256=p.map_sha256,original_images=573,final_repair_images=#c.images,prior_checkpoint_images=reused,final_repair_contact_sheets=tonumber(arg[2]),checkpoint_nonmirror_review='checkpoint-20261024-135124/nonmirror-visual-review.json',observations=assert(arg[3]),scope=result.scope,reviewed_at=os.date('%Y-%m-%dT%H:%M:%S')..'+08:00'});print('Recorded explicitly attributed573-view review: '..#c.images..' repaired-cook images, '..reused..' unchanged-geometry checkpoint images')
