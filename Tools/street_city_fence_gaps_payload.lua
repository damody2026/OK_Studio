-- Native job: open gaps in the campus perimeter fence where a park straddles it.
--   lua Tools/street_city_motel_job.lua world_fence_gaps Tools/street_city_fence_gaps_payload.lua
-- The amusement park lies across the campus's north fence (x ~97000): the carousel, haunted house and teacups inside,
-- the ferris wheel, coaster station and ticket gate outside. The fence (FlatCampus_Fence_Stone / _Bronze / _Cap, one actor
-- each with instanced pieces) ran unbroken along it, so from one ride to the next the walk went out of the park and round
-- (c-conquest conq1112e, 11-12: 69 m took 55 game minutes, route planned again 30+ points). Each gap box takes out every
-- piece whose instance origin lies in it, in all three actors.
-- Input: places-v1/fence-gaps.json { gaps = [{ name, box = [x0,y0,x1,y1] }] }
-- places-v1/fence-gaps-apply.txt holds 1 to remove and save (map backed up first); otherwise it only lists what is in the boxes.
-- Output: places-v1/fence-gaps-result.json
return [====[
def motel_world_fence_gaps():
 import hashlib,shutil
 SUB_=unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
 MAP=ROOT/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'fence-gaps-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 gaps=json.loads((base/'fence-gaps.json').read_text('utf8'))['gaps']
 out=base/'fence-gaps-result.json';r=dict(status='passed',apply=APPLY,gaps=[])
 fences=[a for a in SUB_.get_all_level_actors() if a.get_actor_label() in('FlatCampus_Fence_Stone','FlatCampus_Fence_Bronze','FlatCampus_Fence_Cap')]
 r['actors']=[a.get_actor_label() for a in fences]
 if APPLY:
  b=base/('UniversityCity-before-fence-gaps-'+sha(MAP)[:16]+'.umap')
  if not b.exists():shutil.copy2(MAP,b)
  r['backup']=str(b);r['parent_map_sha256']=sha(MAP)
 removed=0
 for g in gaps:
  x0,y0,x1,y1=g['box'];row=dict(name=g['name'],box=g['box'],pieces=[])
  for a in fences:
   for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
    hit=[]
    for i in range(c.get_instance_count()):
     t=c.get_instance_transform(i,True);p=t.translation
     if x0<=p.x<=x1 and y0<=p.y<=y1:hit.append((i,[round(p.x),round(p.y),round(p.z)]))
    for i,p in hit:row['pieces'].append(dict(actor=a.get_actor_label(),component=c.get_name(),mesh=c.static_mesh.get_path_name() if c.static_mesh else None,index=i,at=p))
    if APPLY and hit:
     a.modify();c.modify()
     for i,_ in sorted(hit,reverse=True):
      assert c.remove_instance(i);removed+=1
  r['gaps'].append(row)
 r['removed']=removed
 if APPLY and removed:assert unreal.EditorLevelLibrary.save_current_level()
 if APPLY:r['map_sha256']=sha(MAP)
 out.write_text(json.dumps(r,indent=1),'utf8')
 return dict(status='passed',apply=APPLY,removed=removed,found=sum(len(g['pieces']) for g in r['gaps']))
]====]
