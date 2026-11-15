-- Native job: the karaoke booths' doors (S48 唱片小室, LoverSpot_KTV_1..3 from Tools/street_city_lover_spots_payload.lua),
-- changed in place, nothing re-placed:
--   lua Tools/street_city_motel_job.lua world_ktv_doors Tools/street_city_ktv_doors_payload.lua
-- Each booth's door gap was 80 cm (front wall 230 cm at side -45), too narrow for the game's 40 cm route grid, and
-- KTV_1's opened onto KTV_2's side wall 50 cm away: nobody walked in or out (c-street-city in game 11-15,
-- StaticMeshActor_16227). Now the gap is 120 cm, on the side whose 1.3 m apron in front is clear (the old side first);
-- the screen moves to the other half of the front wall when the door changes side. The booth is found from its back
-- wall, which is not moved, so a second run gives the same walls. Sofa, table and the seat / screen anchors stay.
-- Runs on the source map (11-15): KTV_3 first (door side 90; KTV_1 and KTV_2 had no clear apron); then, after KTV_2 was
-- taken out (Tools/street_city_ktv_remove_payload.lua), KTV_1 (door side 90, front wall 230 -> 190 cm, 20 cm toward
-- side -90); KTV_3 came out unchanged on the second run.
-- places-v1/ktv-doors-apply.txt holding 1 saves the map; otherwise it only reports what it would set.
-- Output: places-v1/ktv-doors-result.json with every KTV piece before / after and the other LoverSpot_* actors'
-- locations compared before and after (moved must be empty).
return [====[
def motel_world_ktv_doors():
 import math,json,shutil
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'ktv-doors-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 out=base/'ktv-doors-result.json'
 def lab(a):return a.get_actor_label()
 def snap():return {lab(a):[round(a.get_actor_location().x,2),round(a.get_actor_location().y,2),round(a.get_actor_location().z,2),round(a.get_actor_rotation().yaw,2)] for a in SUB.get_all_level_actors() if lab(a).startswith('LoverSpot_') and not lab(a).startswith('LoverSpot_KTV_')}
 before=snap();acts={lab(a):a for a in SUB.get_all_level_actors() if lab(a).startswith('LoverSpot_KTV_')}
 def off(c,yaw,fwd,side=0,up=0):
  r=math.radians(yaw);return V(c.x+math.cos(r)*fwd-math.sin(r)*side,c.y+math.sin(r)*fwd+math.cos(r)*side,c.z+up)
 def clear(c,yaw,z):
  mid=V(c.x,c.y,z+3+100);hit=unreal.SystemLibrary.box_trace_single(world,mid,mid+V(0,0,1),V(65,60,100),unreal.Rotator(roll=0,pitch=0,yaw=yaw),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  t=hit.to_tuple() if hit else [False]
  return (not t[0]),(lab(t[9]) if t[0] and t[9] else None)
 rows=[]
 for k in (1,2,3):
  t='LoverSpot_KTV_%d'%k;back=acts.get(t+'_WallBack');front=acts.get(t+'_WallFront')
  if not back or not front:rows.append(dict(booth=t,skipped='no back or front wall'));continue
  yaw=back.get_actor_rotation().yaw;b=back.get_actor_location();z=b.z-125
  c=off(V(b.x,b.y,z),yaw,125)
  tried=[];door=None
  for s in (90,-90):
   ok,what=clear(off(c,yaw,125+5+65,s),yaw,z);tried.append(dict(side=s,clear=ok,hit=what))
   if ok:door=s;break
  if door is None:rows.append(dict(booth=t,skipped='no clear apron on either side',tried=tried));continue
  wall=-65 if door>0 else 65;scr=-60 if door>0 else 60
  want={t+'_WallFront':(off(c,yaw,125,wall,125),(.1,1.9,2.5)),t+'_Screen':(off(c,yaw,116,scr,110+37.5),None),t+'_ScreenGlow':(off(c,yaw,113.5,scr,113+33.5),None)}
  row=dict(booth=t,centre=[round(c.x,1),round(c.y,1),round(z,1)],yaw=round(yaw,1),door_side=door,tried=tried,pieces=[])
  for name,(p,sc) in want.items():
   a=acts.get(name)
   if not a:row['pieces'].append(dict(actor=name,missing=True));continue
   o=a.get_actor_location();os_=a.get_actor_scale3d()
   ent=dict(actor=name,before=[round(o.x,1),round(o.y,1),round(o.z,1),round(os_.y,3)],after=[round(p.x,1),round(p.y,1),round(p.z,1),sc[1] if sc else round(os_.y,3)])
   if APPLY:
    a.set_actor_location(p,False,False)
    if sc:a.set_actor_scale3d(V(*sc))
   row['pieces'].append(ent)
  rows.append(row)
 after=snap()
 moved=[k for k in before if after.get(k)!=before[k]];gone=[k for k in before if k not in after];new=[k for k in after if k not in before]
 r=dict(status='passed',apply=APPLY,booths=rows,others=len(before),moved=moved,gone=gone,new=new)
 if APPLY:
  assert not moved and not gone and not new,'other LoverSpot actors changed'
  b_=base.parent/'world-edge-v1'/('UniversityCity-before-ktv-doors-'+LOAD_SHA[:16]+'.umap')
  if not b_.exists():shutil.copy2(MAPFILE,b_)
  env=[a for a in SUB.get_all_level_actors() if lab(a)=='CityEnvironmentController']
  if env:env[0].prepare_for_save()
  assert unreal.EditorLevelLibrary.save_current_level();new_sha=sha(MAPFILE)
  installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new_sha);write('motel-install',installed)
  r.update(map_sha256=new_sha,parent_map_sha256=LOAD_SHA,backup=str(b_))
 out.write_text(json.dumps(r,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',apply=APPLY,booths=len(rows),moved=len(moved))
]====]
