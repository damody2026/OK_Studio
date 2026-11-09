return [====[
def motel_audit():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();plan=read('motel-plan');source={r['id']:r for r in plan['rooms']};rows=[];issues=[];rays=0;sweeps=0
 for r in installed['rooms']:
  q=source[r['id']];a=actors['MotelV1_Suite_'+r['id']];assert a.static_mesh_component.static_mesh.get_path_name()==r['asset'];assert str(a.static_mesh_component.get_collision_profile_name())=='BlockAll';assert str(actors['MotelV1_Water_'+r['id']].static_mesh_component.get_collision_profile_name())=='NoCollision';p=r['position'];yaw=math.radians(q['yaw'])
  def point(x,y,z):return unreal.Vector(p[0]+(x*math.sin(yaw)+y*math.cos(yaw))*100,p[1]+(x*math.cos(yaw)-y*math.sin(yaw))*100,p[2]+z*100)
  checks=[]
  # Supported eye positions and real pedestrian thresholds, not elevated aerial cameras.
  for key,eye in [('bed',r['eye']),('bath',r['bath_eye']),('entry',r['entry'])]:
   v=unreal.Vector(*eye);h=unreal.SystemLibrary.line_trace_single(world,v,v-unreal.Vector(0,0,200),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();rays+=1;ok=h[0] and abs(h[4].z-p[2])<12
   checks.append(dict(kind=key,supported=ok,hit_actor=h[9].get_actor_label() if h[0] and h[9] else None,hit=num(h[4]) if h[0] else None))
   if not ok:issues.append(dict(id=r['id'],kind=key,check=checks[-1]))
  # Walk from gallery through the actual1.4m pedestrian opening into the suite.
  x=q['size_m'][0]*.29;v0=point(x,-11.2,1.04);v1=point(x,-9.2,1.04);result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,v0,v1,35.,88.));sweeps+=1
  if result['blocked']:issues.append(dict(id=r['id'],kind='entry_capsule',result=result))
  # Mirror face has the authored backing behind it, and the correct orientation.
  f=unreal.Vector(*r['mirror_face']);n=unreal.Vector(*r['mirror_normal']);h=unreal.SystemLibrary.line_trace_single(world,f-n*2,f-n*25,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();rays+=1
  if not h[0] or not h[9] or h[9]!=a:issues.append(dict(id=r['id'],kind='mirror_backing_missing'))
  rows.append(dict(id=r['id'],checks=checks,entry_capsule_blocked=result['blocked'],mirror_backing=bool(h[0])))
 wc=read('restroom-mirrors-install');mirrorbanks=0
 for r in wc['mirrors']:
  assert r['actor']+'_Glass' in actors and r['actor']+'_Backing' in actors and r['actor']+'_Reflection' in actors;glass=actors[r['actor']+'_Glass'];assert glass.static_mesh_component.get_material(0).get_path_name()=='/Game/UniversityCity/ImmersionV1/Mirrors/M_SilverMirror.M_SilverMirror';assert str(glass.static_mesh_component.get_collision_profile_name())=='BlockAll';scale=glass.get_actor_scale3d();assert abs(scale.y-r['width_cm']/100)<.001 and abs(scale.z-.95)<.001;mirrorbanks+=1
 new_reflections=[]
 for a in actors.values():
  if a.get_actor_label().startswith('MotelV1_'):
   for c in a.get_components_by_class(unreal.PlanarReflectionComponent):
    assert not c.is_visible(),'New captures must serialize inactive until Game nearby-two selection';assert c.get_editor_property('screen_percentage')==75;assert c.get_editor_property('prefilter_roughness')==0.;new_reflections.append(a.get_actor_label())
 assert len(new_reflections)==971+61+1,len(new_reflections);assert 'MotelV1_Reception_WC_Mirror' in actors
 for r in installed['retained_original_actors']:
  a=actors[r['actor']];assert a.get_editor_property('hidden'),r['actor']
  for c in a.get_components_by_class(unreal.PrimitiveComponent):assert str(c.get_collision_profile_name())=='NoCollision',r['actor']
 assert sha(MAPFILE)==LOAD_SHA;write('audit',dict(status='passed' if not issues else 'requires_repair',map_sha256=LOAD_SHA,rooms=len(rows),vanity_banks=mirrorbanks,new_reflection_components=len(new_reflections),covered_nonhotel_basins=wc['covered_basins'],rays=rays,capsule_sweeps=sweeps,rows=rows,issues=issues,scope='Fresh reopen:61 suite meshes/materials/water collision, supported bed/bath/entry positions, player threshold capsules, mirror backing,971 nonhotel vanity banks,all1,033 new capture settings and retired originals. Car ramp/stair route and reflected Game pixels require separate validation.'))
]====]
