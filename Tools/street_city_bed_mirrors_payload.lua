-- Bed-side mirrors for the motel suites: one real (planar-reflection) wall mirror per suite where a couple on the
-- bed can see themselves. Native jobs, queued with
--   lua Tools/street_city_motel_job.lua <job> Tools/street_city_bed_mirrors_payload.lua
--   world_bed_mirrors_probe    read-only: picks the wall for every suite -> world-edge-v1/bed-mirrors-plan.json
--   world_bed_mirrors_install  probe again, (re)place BedMirror_<room>_{Wall,Ceiling}_{Frame,Glass,Reflection}, save the map
-- Placement (room-local frame of Docs/STREET_CITY_MOTEL_ROOM_SPEC_20261025.md, +y = headboard side):
--   bed centre   v2 rooms: the bed downlight of models-v2/<id>/build.json (lights[1], 0.4 m toward the foot);
--                the four approved sample rooms: the shell default (-3.34, 4.7), except 209 (canopy bed at 1.6, 5.15)
--                and 203 (bed at x = width * 0.14, y 4.7), as built by build_street_city_motel_sample_rooms.lua. A down ray must find a bed top
--                0.3-1.1 m above the floor, otherwise the suite is skipped.
--   wall         rays from 1.3 m over the bed centre to the left, the right and the foot; the hit must be the suite
--                shell 1.3-6.5 m away. The mirror (z 0.4-2.2 m, 1.4 / 1.1 / 0.8 m wide) needs a flat face there
--                (every 20 cm sample within 1.5 cm of the plane, so TVs, shelves, lamps and windows rule it out) and
--                a clear sight line from 0.5 m above the bed to every sample at 1.2 m and higher.
--                Side walls beat the foot wall, then the wider mirror, then the nearer wall.
--   ceiling      also a 1.8 x 1.4 m mirror on the ceiling right over the bed (the only one where no wall qualifies:
--                pool suites have a pool hall beside the bed, some rooms are open there), if the ceiling there is flat (20 cm samples within 1.5 cm) and
--                nothing hangs between the bed and it.
-- The reflections carry the ImmersionLargeMirror tag, so the Game walker's nearby-two policy turns them on, and they
-- are saved inactive like every other new capture. Names stay outside MotelV1_ so the motel audit's fixed capture
-- count is unchanged.
return [====[
BM_OUT=ROOT/'output/street-social-city-production/world-edge-v1'
BM_V2=ROOT/'output/street-social-city-production/motel-v1/sample-rooms/models-v2'
BM_IGNORE=[]
def _bm_ray(world,a,b):
 raw=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,BM_IGNORE,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
 return h if h[0] else None
def _bm_plan():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 # mirrors from an earlier install must not stand in for the wall or ceiling they hang on
 BM_IGNORE[:]=[a for k,a in actors.items() if k.startswith('BedMirror_')]
 installed=read('motel-install');plan={r['id']:r for r in read('motel-plan')['rooms']};rows=[];skipped=[]
 dot=unreal.MathLibrary.dot_vector_vector
 for r in installed['rooms']:
  rid=r['id'];q=plan[rid];suite=actors.get('MotelV1_Suite_'+rid)
  if suite is None:skipped.append(dict(id=rid,reason='no_suite_actor'));continue
  ang=math.radians(q['yaw']);s,c=math.sin(ang),math.cos(ang);base=r['position']
  def W(x,y,z):return unreal.Vector(base[0]+(x*s+y*c)*100,base[1]+(x*c-y*s)*100,base[2]+z*100)
  def D(dx,dy):return unreal.Vector(dx*s+dy*c,dx*c-dy*s,0)
  bed=(-3.34,4.7);bj=BM_V2/rid/'build.json'
  if bj.exists():
   L=json.loads(bj.read_text('utf8'))['lights']
   if len(L)>1:bed=(L[1]['local'][0],L[1]['local'][1]+.4)
  # sample rooms whose bed is not at the shell default (build_street_city_motel_sample_rooms.lua: 209 canopy_bed, 203 bx=w*.14)
  if rid=='imore-93474c507aaf':bed=(1.6,5.15)
  elif rid=='imore-cda5d5e2dcb9':bed=(q['size_m'][0]*.14,4.7)
  h=_bm_ray(world,W(bed[0],bed[1],2.5),W(bed[0],bed[1],-.2));top=(h[4].z-base[2])/100 if h else None
  if top is None or not .3<top<1.1:skipped.append(dict(id=rid,reason='no_bed_top',bed=bed,top=top));continue
  eye=W(bed[0],bed[1],top+.5);best=None;tried=[]
  for side,(dx,dy),pref in [('left',(-1,0),0),('right',(1,0),0),('foot',(0,-1),1)]:
   o=W(bed[0],bed[1],1.3);d=D(dx,dy);h=_bm_ray(world,o,o+d*700)
   if not h or h[9]!=suite:tried.append(dict(side=side,reason='no_shell_hit',actor=h[9].get_actor_label() if h and h[9] else None));continue
   dist=(h[4]-o).length()
   if not 130<=dist<=650:tried.append(dict(side=side,reason='distance',cm=dist));continue
   n=d*-1.;t=unreal.Vector(-n.y,n.x,0);f=h[4];plane=dot(f,n);fit=None
   for w in (140,110,80):
    ok=True;why=None
    for k in range(int(w/20)+1):
     u=k*20-w/2
     for z in (40,80,120,160,200,220):
      p=unreal.Vector(f.x,f.y,base[2]+z)+t*u;hh=_bm_ray(world,p+n*20,p-n*20)
      if not hh or hh[9]!=suite or abs(dot(hh[4],n)-plane)>1.5:ok=False;why='not_flat';break
      if z>=120 and _bm_ray(world,eye,hh[4]+n*4):ok=False;why='sight';break
     if not ok:break
    if ok:fit=w;break
   if fit is None:tried.append(dict(side=side,reason=why,cm=dist));continue
   cand=dict(side=side,width_cm=fit,height_cm=180,distance_cm=dist,face=num(unreal.Vector(f.x,f.y,base[2]+130)),normal=num(n),tangent=num(t),pref=pref)
   tried.append(dict(side=side,fit=fit,cm=dist))
   if best is None or (pref,-fit,dist)<(best['pref'],-best['width_cm'],best['distance_cm']):best=cand
  found=0
  if best is not None:best.update(kind='wall',id=rid,bed=bed,bed_top_m=top,eye=num(eye),tried=tried);rows.append(best);found+=1
  if True:
   # and a mirror on the flat ceiling right over the bed (the only one for pool suites and open rooms)
   best=None;o=W(bed[0],bed[1],top+.3);h=_bm_ray(world,o,o+unreal.Vector(0,0,600))
   if h and h[9]==suite:
    a=D(0,1);b=D(1,0);cz=h[4].z;ok=True
    for i in range(10):
     for k in range(8):
      p=o+a*(-90+i*20)+b*(-70+k*20);hh=_bm_ray(world,p,p+unreal.Vector(0,0,600))
      if not hh or hh[9]!=suite or abs(hh[4].z-cz)>1.5:ok=False;break
     if not ok:break
    if ok:best=dict(kind='ceiling',side='ceiling',width_cm=180,height_cm=140,distance_cm=cz-o.z,face=num(unreal.Vector(o.x,o.y,cz)),normal=[0.,0.,-1.],tangent=num(a),pref=2)
   if best is not None:best.update(id=rid,bed=bed,bed_top_m=top,eye=num(eye));rows.append(best);found+=1
   else:tried.append(dict(side='ceiling',reason='not_flat_or_blocked'))
  if not found:skipped.append(dict(id=rid,reason='no_wall_or_ceiling',bed=bed,tried=tried))
 return rows,skipped
def motel_world_bed_mirrors_probe():
 rows,skipped=_bm_plan()
 (BM_OUT/'bed-mirrors-plan.json').write_text(json.dumps(dict(status='read_only',map_sha256=LOAD_SHA,mirrors=rows,skipped=skipped),ensure_ascii=False,indent=1),'utf8')
def motel_world_bed_mirrors_install():
 rows,skipped=_bm_plan()
 b=BM_OUT/('UniversityCity-before-bed-mirrors-'+LOAD_SHA[:16]+'.umap')
 if not b.exists():shutil.copy2(MAPFILE,b)
 for a in SUB.get_all_level_actors():
  if a.get_actor_label().startswith('BedMirror_'):SUB.destroy_actor(a)
 cube=EAL.load_asset('/Engine/BasicShapes/Cube');silver=EAL.load_asset('/Game/UniversityCity/ImmersionV1/Mirrors/M_SilverMirror');gold=EAL.load_asset('/Game/UniversityCity/MotelV1/Materials/M_Gold');assert cube and silver and gold
 views=[]
 for q in rows:
  face=unreal.Vector(*q['face']);n=unreal.Vector(*q['normal']);t=unreal.Vector(*q['tangent']);w=q['width_cm'];h=q['height_cm'];ceil=q['kind']=='ceiling';stem='BedMirror_'+q['id']+('_Ceiling' if ceil else '_Wall')
  # wall: cube x = thickness along the normal; ceiling: cube x along the bed (t), y across, z = thickness
  rot=unreal.Rotator(roll=0,pitch=0,yaw=math.degrees(math.atan2(t.y,t.x)) if ceil else math.degrees(math.atan2(n.y,n.x)))
  dims=(lambda th,ww,hh:[ww,hh,th]) if ceil else (lambda th,ww,hh:[th,ww,hh])
  for suffix,p,size,mat in [('Frame',face+n*.75,dims(1.5,w+8,h+8),gold),('Glass',face+n*2.25,dims(1.5,w,h),silver)]:
   a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,p,rot);a.set_actor_label(stem+'_'+suffix);a.tags=[unreal.Name('BedMirror')];a.set_folder_path('UniversityCity/MotelV1/BedMirrors');c=a.static_mesh_component;c.set_static_mesh(cube);c.set_material(0,mat);c.set_collision_profile_name('BlockAll');c.set_editor_property('cast_shadow',False);a.set_actor_scale3d(unreal.Vector(*[v/100 for v in size]))
  a=SUB.spawn_actor_from_class(unreal.PlanarReflection,face+n*3.1,unreal.MathLibrary.make_rotation_from_axes(t,unreal.MathLibrary.cross_vector_vector(n,t),n));a.set_actor_label(stem+'_Reflection');a.tags=[unreal.Name('BedMirror'),unreal.Name('ImmersionLargeMirror')];a.set_folder_path('UniversityCity/MotelV1/BedMirrors');a.set_actor_scale3d(unreal.Vector(w/4000,h/4000,1));c=a.get_components_by_class(unreal.PlanarReflectionComponent)[0]
  for key,value in dict(screen_percentage=75,normal_distortion_strength=0.,prefilter_roughness=0.,distance_from_plane_fadeout_start=5.,distance_from_plane_fadeout_end=15.,show_preview_plane=False,max_view_distance_override=2200.).items():c.set_editor_property(key,value)
  c.set_visibility(False)
  for m in a.get_components_by_class(unreal.StaticMeshComponent):m.set_visibility(False);m.set_hidden_in_game(True);m.set_collision_profile_name('NoCollision')
  e=unreal.Vector(*q['eye'])
  if ceil:e=e-t*200   # from the foot of the bed, so the shot is not straight up
  views.append(dict(id=('BMC-' if ceil else 'BMW-')+q['id'][-6:],eye=num(e),target=num(face),fov=70,hour=21))
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (BM_OUT/'bed-mirror-views.json').write_text(json.dumps(views,indent=1),'utf8')
 (BM_OUT/('bed-mirrors-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_cooked_reflection_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),mirrors=rows,skipped=skipped),ensure_ascii=False,indent=1),'utf8')
]====]
