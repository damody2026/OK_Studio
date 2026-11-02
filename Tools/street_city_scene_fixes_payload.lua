-- Scene fixes before the UniversityCity swap into StreetSocial (Docs/STREET_CITY_PLACES_INVENTORY_20261103.md). Native jobs:
--   lua Tools/street_city_motel_job.lua <job> Tools/street_city_scene_fixes_payload.lua
--   world_fix_probe    read-only: what the G113 / G086 views actually hit -> world-edge-v1/fix-probe.json
--   world_fix_install  (1) the four restroom vanity mirrors that were spawned lying flat (Rotator(0,yaw,0) is
--                          roll/pitch/yaw in Python) are turned upright, facing their recorded normal;
--                      (2) the 10 cm step along the south border (y = 110000; city ground 1198 against the annex /
--                          skirt): measured every 2 m, a 1 m sloped strip of world-aligned grass where the outside is
--                          3-30 cm lower
--                      (3) WorldEdge_Seawall (river-mouth quay, the white slope in G113) gets the river gravel MI
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
 # height profiles: down-traces every 25 cm along the G086 view line and across the south border at three x
 prof=[]
 for name,(ax,ay),(bx,by) in [('G086_line',(58257,120500),(58257,108500)),('border_x30000',(30000,111500),(30000,108500)),('border_x58000',(58000,111500),(58000,108500)),('border_x80000',(80000,111500),(80000,108500))]:
  n=int(math.hypot(bx-ax,by-ay)/25);pts=[]
  for i in range(n+1):
   x=ax+(bx-ax)*i/n;y=ay+(by-ay)*i/n;h=_fx_hit(world,unreal.Vector(x,y,1600),unreal.Vector(x,y,900))
   pts.append([round(x),round(y),round(h['point'][2],1) if h else None,h['actor'] if h else None])
  prof.append(dict(name=name,points=pts))
 (FX_OUT/'fix-probe.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,rows=rows,profiles=prof),ensure_ascii=False,indent=1),'utf8')
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
 # measured: along the whole south border (y = 110000) every 2 m, the walk surface just inside (y 109950) and just
 # outside (y 110050); a strip goes only where the outside is 3-30 cm lower, from the inside height down to it
 world=unreal.EditorLevelLibrary.get_editor_world()
 def top(x,y):
  h=_fx_hit(world,unreal.Vector(x,y,1600),unreal.Vector(x,y,900))
  return h['point'][2] if h else None
 run=100.;k=0;runs=[];cur=None
 for i in range(0,110000//200):
  x=i*200.+100;zi=top(x,109950);zo=top(x,110050)
  ok=zi is not None and zo is not None and 3<=zi-zo<=30
  if ok and cur and abs(zi-cur['zi'])<2 and abs(zo-cur['zo'])<2 and x-cur['x1']<=200.5:cur['x1']=x+100
  elif ok:
   cur=dict(x0=x-100,x1=x+100,zi=zi,zo=zo);runs.append(cur)
  else:cur=None
 for r in runs:
  drop=r['zi']-r['zo'];L=math.hypot(run,drop);s=drop/L;c=run/L;w=r['x1']-r['x0']
  rot=unreal.MathLibrary.make_rotation_from_axes(unreal.Vector(1,0,0),unreal.Vector(0,c,-s),unreal.Vector(0,s,c))
  centre=unreal.Vector(r['x0']+w/2,110000+run/2,(r['zi']+r['zo'])/2-1.0)
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,centre,rot);a.set_actor_label('SceneFix_AnnexStep_%02d'%k);a.set_folder_path('UniversityCity/SceneFixesV1');a.tags=[unreal.Name('SceneFix')]
  m=a.static_mesh_component;m.set_static_mesh(cube);m.set_material(0,grass);m.set_collision_profile_name('NoCollision');m.set_editor_property('cast_shadow',False);a.set_actor_scale3d(unreal.Vector(w/100,L/100,.02))
  k+=1
 done.append(dict(fix='south_border_step_strip',segments=k,runs=runs))
 # (3) G113: the river-mouth quay kept the glb's light concrete (a blank white slope); river gravel like the bed
 sw=acts.get('WorldEdge_Seawall');gravel=EAL.load_asset('/Game/UniversityCity/GroundPBRV2/Materials/MI_Detail_9ea1c3103a2d3f4c9850')
 if sw and gravel:
  c=sw.static_mesh_component
  if any(c.get_material(i)!=gravel for i in range(c.get_num_materials())):
   for i in range(c.get_num_materials()):c.set_material(i,gravel)
   done.append(dict(fix='seawall_gravel',slots=c.get_num_materials()))
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (FX_OUT/('scene-fixes-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),fixes=done),ensure_ascii=False,indent=1),'utf8')
]====]
