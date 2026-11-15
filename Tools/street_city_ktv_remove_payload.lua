-- Native job: take the karaoke booth KTV_2 out of S48 (唱片小室); KTV_1 and KTV_3 stay.
--   lua Tools/street_city_motel_job.lua world_ktv_remove Tools/street_city_ktv_remove_payload.lua
-- KTV_2 (Tools/street_city_lover_spots_payload.lua, section 10) faced the shop's south record racks, and its side wall stood
-- 50 cm in front of KTV_1's door: nobody walked into KTV_1, and KTV_2's own door opened onto the racks (S48_F01). The
-- racks are part of the shop's meshes. The only spot in the shop where KTV_2 fits facing an aisle (centre 44550,48625,
-- yaw 90; places-v1/ktv-survey.json, Tools/street_city_ktv_survey_payload.lua) leaves 45 cm between the booth and a rack
-- on the way out, so the booth is removed instead (coordinator, 11-15). Its seat and screen anchors go with it
-- (Tools/street_city_removed_anchors.lua). Run Tools/street_city_ktv_doors_payload.lua after this one: KTV_1's door is
-- still 80 cm and gets its 120 cm door once the apron in front of it is clear.
-- places-v1/ktv-remove-apply.txt holding 1 deletes and saves; otherwise it only lists what it would delete. A second run
-- finds nothing and saves nothing.
-- Output: places-v1/ktv-remove-result.json (the actors deleted with their transforms, the other LoverSpot_* actors
-- compared before and after: moved must be empty)
return [====[
def motel_world_ktv_remove():
 import json,shutil
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'ktv-remove-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 out=base/'ktv-remove-result.json';PRE='LoverSpot_KTV_2_'
 def lab(a):return a.get_actor_label()
 def snap():return {lab(a):[round(a.get_actor_location().x,2),round(a.get_actor_location().y,2),round(a.get_actor_location().z,2),round(a.get_actor_rotation().yaw,2)] for a in SUB.get_all_level_actors() if lab(a).startswith('LoverSpot_') and not lab(a).startswith(PRE)}
 before=snap();gone_=[a for a in SUB.get_all_level_actors() if lab(a).startswith(PRE)]
 rows=[]
 for a in gone_:
  l=a.get_actor_location();s=a.get_actor_scale3d()
  rows.append(dict(actor=lab(a),name=a.get_name(),loc=[round(l.x,1),round(l.y,1),round(l.z,1)],yaw=round(a.get_actor_rotation().yaw,2),scale=[round(s.x,3),round(s.y,3),round(s.z,3)]))
 r=dict(status='passed',apply=APPLY,removed=rows)
 if APPLY and gone_:
  b_=base.parent/'world-edge-v1'/('UniversityCity-before-ktv-remove-'+LOAD_SHA[:16]+'.umap')
  if not b_.exists():shutil.copy2(MAPFILE,b_)
  for a in gone_:assert SUB.destroy_actor(a),'destroy '+lab(a)
  after=snap()
  moved=[k for k in before if after.get(k)!=before[k]];lost=[k for k in before if k not in after];new=[k for k in after if k not in before]
  assert not moved and not lost and not new,'other LoverSpot actors changed'
  assert not [a for a in SUB.get_all_level_actors() if lab(a).startswith(PRE)],'KTV_2 still there'
  env=[a for a in SUB.get_all_level_actors() if lab(a)=='CityEnvironmentController']
  if env:env[0].prepare_for_save()
  assert unreal.EditorLevelLibrary.save_current_level();new_sha=sha(MAPFILE)
  installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new_sha);write('motel-install',installed)
  r.update(others=len(before),moved=moved,lost=lost,new=new,map_sha256=new_sha,parent_map_sha256=LOAD_SHA,backup=str(b_))
 out.write_text(json.dumps(r,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',apply=APPLY,removed=len(rows))
]====]
