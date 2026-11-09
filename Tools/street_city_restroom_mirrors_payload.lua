return [====[
def motel_wc_probe():
 plan=read('restroom-sinks-plan');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();rows=[];missing=[]
 campus={'E1','EE','MA','T4','T2','IB','T1','RB','AD','LI','SC','IN','SP','D1','D2','D3','D4'}
 for q in plan['sinks']:
  bid=q['building'];label=('Campus_'+bid+'_F01') if bid in campus else ('City_'+bid+'_F01') if 'City_'+bid+'_F01' in actors else 'Mall_M1_F01' if bid=='M1' else bid+'_F01'
  if label not in actors:missing.append(dict(id=q['id'],reason='missing_building_actor',actor=label));continue
  base=actors[label].get_actor_location();x,y,z=q['position_m'];p=base+unreal.Vector(y*100,x*100,z*100+165);hits=[]
  for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
   d=unreal.Vector(dx,dy,0);raw=unreal.SystemLibrary.line_trace_single(world,p,p+d*180,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or not h[9]:continue
   hit=h[4];distance=(hit-p).length()
   if distance<14 or distance>170:continue
   n=-d;t=unreal.Vector(-n.y,n.x,0);backing=True
   for off in [-25,25]:
    w=hit+t*off;rr=unreal.SystemLibrary.line_trace_single(world,w+n*12,w-n*12,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);hh=rr.to_tuple() if rr else [False]
    if not hh[0] or not hh[9] or hh[9]!=h[9]:backing=False;break
   if backing:hits.append(dict(face=num(hit+n*2.5),normal=num(n),tangent=num(t),distance=distance,backing_actor=h[9].get_actor_label(),sink=num(p-unreal.Vector(0,0,165))))
  if not hits:missing.append(dict(id=q['id'],building=bid,owner=q['owner'],position=num(p),reason='No verified backing wall within170cm; investigate actual placement instead of fabricating pass'));continue
  row=dict(q);row.update(min(hits,key=lambda h:h['distance']));rows.append(row)
 assert sha(MAPFILE)==LOAD_SHA
 # Join a contiguous washbasin bank only when the complete span has a real wall.
 banks=[]
 for q in rows:
  n=unreal.Vector(*q['normal']);t=unreal.Vector(*q['tangent']);f=unreal.Vector(*q['face']);half=52.5 if q['asset']=='COMMON-CITY-basin' else 28.5;chosen=None
  for b in banks:
   if b['backing_actor']!=q['backing_actor'] or b['normal']!=q['normal'] or abs(b['face'][2]-f.z)>.2:continue
   center=unreal.Vector(*b['face']);delta=f-center
   if abs(unreal.MathLibrary.dot_vector_vector(delta,n))>.5:continue
   offset=unreal.MathLibrary.dot_vector_vector(delta,t);lo=min(-b['width_cm']/2,offset-half);hi=max(b['width_cm']/2,offset+half)
   if hi-lo>600 or abs(offset)>(b['width_cm']/2+half+100):continue
   nf=center+t*((lo+hi)/2);valid=True
   for k in range(int(math.ceil((hi-lo)/25))+1):
    p=nf+t*(-(hi-lo)/2+(hi-lo)*k/max(1,math.ceil((hi-lo)/25)));rr=unreal.SystemLibrary.line_trace_single(world,p+n*10,p-n*10,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);hh=rr.to_tuple() if rr else [False]
    if not hh[0] or not hh[9] or hh[9].get_actor_label()!=q['backing_actor']:valid=False;break
   if valid:b['face']=num(nf);b['width_cm']=hi-lo;b['basin_ids'].append(q['id']);chosen=b;break
  if chosen is None:
   b=dict(q);b['width_cm']=half*2;b['basin_ids']=[q['id']];banks.append(b)
 write('restroom-wall-probe',dict(status='probed_requires_coverage_resolution' if missing else 'all_sinks_have_verified_backing',map_sha256=LOAD_SHA,expected=len(plan['sinks']),matched=len(rows),mirrors=rows,mirror_banks=banks,unresolved=missing))

def motel_wc_diagnostics():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for q in read('restroom-wall-probe')['unresolved']:
  if 'position' not in q:continue
  p=unreal.Vector(*q['position']);hits=[]
  for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
   end=p+unreal.Vector(dx*450,dy*450,0);raw=unreal.SystemLibrary.line_trace_single(world,p,end,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if h[0]:hits.append(dict(kind='wall',direction=[dx,dy],actor=h[9].get_actor_label(),point=num(h[4]),distance=(h[4]-p).length()))
  for dx,dy in [(0,0),(20,0),(-20,0),(0,20),(0,-20)]:
   start=p+unreal.Vector(dx,dy,-55);raw=unreal.SystemLibrary.line_trace_single(world,start,start-unreal.Vector(0,0,100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if h[0]:hits.append(dict(kind='vanity_support',actor=h[9].get_actor_label(),point=num(h[4]),height_from_base=h[4].z-(p.z-165)))
  rows.append(dict(id=q['id'],hits=hits))
 write('restroom-unresolved-diagnostics',dict(status='read_only',map_sha256=LOAD_SHA,rows=rows))

def motel_wc_install():
 probe=read('restroom-wall-probe');assert probe['map_sha256']==LOAD_SHA;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert not any(k.startswith('MotelV1_WC_') for k in actors),'WC revision already installed'
 # Save partial verified scope explicitly; unresolved basins remain on the work list.
 backup=OUT/('UniversityCity-before-restroom-mirrors-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);cube=EAL.load_asset('/Engine/BasicShapes/Cube');silver=EAL.load_asset('/Game/UniversityCity/ImmersionV1/Mirrors/M_SilverMirror');frame=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');assert cube and silver and frame;made=[]
 for index,q in enumerate(probe['mirror_banks']):
  face=unreal.Vector(*q['face']);n=unreal.Vector(*q['normal']);t=unreal.Vector(*q['tangent']);yaw=math.degrees(math.atan2(n.y,n.x));w=q['width_cm'];h=95
  stem='MotelV1_WC_%04d'%index
  for suffix,p,size,mat in [('Glass',face,[1.5,w,h],silver),('Backing',face-n*1.5,[1.5,w+4,h+4],frame)]:
   a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,p,unreal.Rotator(0,yaw,0));a.set_actor_label(stem+'_'+suffix);a.tags=[unreal.Name('MotelV1'),unreal.Name('RestroomMirror')];a.set_folder_path('UniversityCity/MotelV1/RestroomMirrors');c=a.static_mesh_component;c.set_static_mesh(cube);c.set_material(0,mat);c.set_collision_profile_name('BlockAll');c.set_editor_property('cast_shadow',False);a.set_actor_scale3d(unreal.Vector(*[v/100 for v in size]))
  a=SUB.spawn_actor_from_class(unreal.PlanarReflection,face+n*.9,unreal.MathLibrary.make_rotation_from_axes(t,unreal.Vector(0,0,1),n));a.set_actor_label(stem+'_Reflection');a.tags=[unreal.Name('MotelV1'),unreal.Name('ImmersionLargeMirror'),unreal.Name('RestroomMirror')];a.set_folder_path('UniversityCity/MotelV1/RestroomMirrors');a.set_actor_scale3d(unreal.Vector(w/4000,h/4000,1));c=a.get_components_by_class(unreal.PlanarReflectionComponent)[0]
  for key,value in dict(screen_percentage=75,normal_distortion_strength=0.,prefilter_roughness=0.,distance_from_plane_fadeout_start=5.,distance_from_plane_fadeout_end=15.,show_preview_plane=False,max_view_distance_override=6000.).items():c.set_editor_property(key,value)
  for c in a.get_components_by_class(unreal.StaticMeshComponent):c.set_visibility(False);c.set_hidden_in_game(True);c.set_collision_profile_name('NoCollision')
  made.append(dict(id=q['id'],basin_ids=q['basin_ids'],building=q['building'],owner=q['owner'],actor=stem,face=q['face'],normal=q['normal'],width_cm=w,height_cm=h,eye=num(face+n*180),backing_actor=q['backing_actor']))
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level()
 write('restroom-mirrors-install',dict(status='saved_requires_reopen_and_actual_reflection_review',map_sha256=sha(MAPFILE),parent_map_sha256=LOAD_SHA,backup=str(backup),mirrors=made,unresolved=probe['unresolved'],expected_basins=probe['expected'],covered_basins=sum(len(q['basin_ids']) for q in made),scope='Verified wall-backed vanity banks, continuous wall checked every25cm before joining; kitchen/laboratory sinks excluded. Existing12 training mirrors untouched.'))
]====]
