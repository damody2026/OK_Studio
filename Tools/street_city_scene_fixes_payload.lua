-- Scene fixes before the UniversityCity swap into StreetSocial (Docs/STREET_CITY_PLACES_INVENTORY_20261103.md). Native jobs:
--   lua Tools/street_city_motel_job.lua <job> Tools/street_city_scene_fixes_payload.lua
--   world_fix_probe    read-only: what the G113 / G086 views actually hit -> world-edge-v1/fix-probe.json
--   world_fix_install  (1) the four restroom vanity mirrors that were spawned lying flat (Rotator(0,yaw,0) is
--                          roll/pitch/yaw in Python) are turned upright, facing their recorded normal;
--                      (2) the 10 cm step where the city ground (1198) meets Outdoor_annex_ground (1188) along
--                          y = 110000 gets a 1 m sloped strip of world-aligned grass on the annex side
-- The install backs the map up to world-edge-v1/UniversityCity-before-scene-fixes-<sha>.umap.
return [====[
FX_OUT=ROOT/'output/street-social-city-production/world-edge-v1'
def _fx_hit(world,a,b):
 raw=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
 if not h[0]:return None
 act=h[9];comp=h[10] if len(h)>10 else None;mats=[]
 try:
  for k in range(comp.get_num_materials()):m=comp.get_material(k);mats.append(m.get_path_name() if m else None)
 except Exception:pass
 return dict(actor=act.get_actor_label() if act else None,cls=act.get_class().get_name() if act else None,point=num(h[4]),normal=num(h[5]),mesh=(comp.static_mesh.get_path_name() if hasattr(comp,'static_mesh') and comp.static_mesh else None),materials=mats)
def motel_world_fix_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 views=[dict(id='G113',eye=[73257,92999,1171],target=[70757,92999,1126]),dict(id='G086',eye=[58257,119999,1353],target=[58257,117499,1308]),dict(id='G085',eye=[58257,110999,1353],target=[55757,110999,1308])]
 for v in views:
  e=unreal.Vector(*v['eye']);t=unreal.Vector(*v['target']);f=(t-e);f.z=0;f=f.normal();r=unreal.Vector(-f.y,f.x,0)
  for ang in (-40,-25,-10,0,10,25,40):
   for pitch in (-20,-8,0,8,20):
    a=math.radians(ang);p=math.radians(pitch);d=(f*math.cos(a)+r*math.sin(a))*math.cos(p)+unreal.Vector(0,0,math.sin(p))
    rows.append(dict(view=v['id'],yaw=ang,pitch=pitch,hit=_fx_hit(world,e,e+d*6000)))
 (FX_OUT/'fix-probe.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,rows=rows),ensure_ascii=False,indent=1),'utf8')
def motel_world_fix_install():
 b=FX_OUT/('UniversityCity-before-scene-fixes-'+LOAD_SHA[:16]+'.umap')
 if not b.exists():shutil.copy2(MAPFILE,b)
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()};done=[]
 # (1) flat restroom mirrors: any WC Glass/Backing whose bounds are thinner in z than in y is lying down
 wc={r['actor']:r for r in read('restroom-mirrors-install')['mirrors']}
 for stem,r in wc.items():
  g=acts.get(stem+'_Glass')
  if not g:continue
  o,e=g.get_actor_bounds(False)
  if e.z>5:continue
  n=unreal.Vector(*r['normal']);yaw=math.degrees(math.atan2(n.y,n.x))
  for s in ('_Glass','_Backing'):acts[stem+s].set_actor_rotation(unreal.Rotator(roll=0,pitch=0,yaw=yaw),False)
  done.append(dict(fix='restroom_mirror_upright',actor=stem,yaw=yaw))
 # (2) annex step strip
 for a in list(acts.values()):
  if a.get_actor_label().startswith('SceneFix_AnnexStep'):SUB.destroy_actor(a)
 cube=EAL.load_asset('/Engine/BasicShapes/Cube');grass=EAL.load_asset('/Game/UniversityCity/GrassHillsV1/M_GrassWorldTriplanar_v2');assert cube and grass
 ann=acts['Outdoor_annex_ground'];o,e=ann.get_actor_bounds(False);x0,x1=o.x-e.x,o.x+e.x
 run,drop=100.,10.;L=math.hypot(run,drop);s=drop/L;c=run/L
 rot=unreal.MathLibrary.make_rotation_from_axes(unreal.Vector(1,0,0),unreal.Vector(0,c,-s),unreal.Vector(0,s,c))
 seg=2000.;k=0;x=x0
 while x<x1-1:
  w=min(seg,x1-x);centre=unreal.Vector(x+w/2,110000+run/2,1193-1.0)
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,centre,rot);a.set_actor_label('SceneFix_AnnexStep_%02d'%k);a.set_folder_path('UniversityCity/SceneFixesV1');a.tags=[unreal.Name('SceneFix')]
  m=a.static_mesh_component;m.set_static_mesh(cube);m.set_material(0,grass);m.set_collision_profile_name('NoCollision');m.set_editor_property('cast_shadow',False);a.set_actor_scale3d(unreal.Vector(w/100,L/100,.02))
  k+=1;x+=w
 done.append(dict(fix='annex_step_strip',segments=k,x=[x0,x1],y=110000,top=1198,bottom=1188))
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (FX_OUT/('scene-fixes-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),fixes=done),ensure_ascii=False,indent=1),'utf8')
]====]
