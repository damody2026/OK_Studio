return [====[
IMM='/Game/UniversityCity/ImmersionV1'

def immersion_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/Evergreens';KEEP=[];save=save_asset
 source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0]
 source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)")
 namespace=dict(globals());exec('def import_one('+source,namespace);import_one=namespace['import_one'];api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
 bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV2/Materials/M_Bark');leaves=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV2/Materials/M_Leaves');assert bark and leaves
 rows=[]
 for aid in ['evergreen-a','evergreen-b','evergreen-c']:
  meshes=[]
  for lod in range(3):
   mesh=import_one(OUT/'evergreens'/'assets'/aid/('LOD'+str(lod)+'-source.glb'),aid,lod,False)
   for slot,s in enumerate(mesh.get_editor_property('static_materials')):
    name=str(s.get_editor_property('imported_material_slot_name'));mesh.set_material(slot,bark if 'Bark' in name else leaves)
   assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
  mesh=meshes[0]
  for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
  assert api.set_lod_screen_sizes(mesh,[1.,.16,.045]);EAL.set_metadata_tag(mesh,'ImmersionCanopy','Open branches and masked leaf sprays; no opaque spherical masses; three geometric LODs')
  EAL.set_metadata_tag(mesh,'ImmersionSourceId',aid);assert EAL.save_loaded_asset(mesh,False)
  rows.append(dict(id=aid,asset=mesh.get_path_name(),triangles=[mesh.get_num_triangles(i) for i in range(api.get_lod_count(mesh))],materials=[mesh.get_material(i).get_path_name() for i in range(len(mesh.get_editor_property('static_materials')))]))
 assert sha(MAPFILE)==LOAD_SHA
 write('imports',dict(status='passed',map_sha256=LOAD_SHA,assets=rows));write('shader',dict(status='passed',map_sha256=LOAD_SHA,assets=len(rows)))

def immersion_tree_install():
 baseline=read('inventory');assert LOAD_SHA==baseline['map_sha256'];imports=read('imports');assert imports['status']=='passed';assert not (OUT/'install.json').exists()
 before=ground_snapshot();write('preservation-before',dict(status='recorded',map_sha256=LOAD_SHA,components=before));backup=OUT/('UniversityCity-before-immersion-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};changes=[]
 for old in baseline['components']:
  if '/TreeUpgradeV2/Assets/cypress/' not in old['mesh']:continue
  a=actors[old['actor']];name=old['component'];c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name);assert c.static_mesh.get_path_name()==old['mesh']
  index=int(hashlib.sha256((old['actor']+'|'+name).encode()).hexdigest()[:8],16)%3;row=imports['assets'][index];mesh=EAL.load_asset(row['asset']);materials=[EAL.load_asset(p) for p in row['materials']]
  c.modify();c.set_static_mesh(mesh);c.set_editor_property('override_materials',materials);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name);assert c.static_mesh==mesh
  assert ground_transform(c.get_world_transform())==old['transform'];assert str(c.get_collision_profile_name())==old['collision']
  if 'instances' in old:assert [ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]==old['instances']
  changes.append(dict(actor=old['actor'],component=name,before=old['mesh'],after=row['asset'],materials=row['materials'],instances=len(old.get('instances',[1]))))
 assert len(changes)==29,len(changes)
 after=ground_snapshot();expected={(r['actor'],r['component']):r for r in changes};assert len(before)==len(after)
 for old,now in zip(before,after):
  key=(old['actor'],old['component']);copy=dict(now)
  if key in expected:
   assert copy['mesh']==expected[key]['after'];copy['mesh']=old['mesh'];copy['materials']=old['materials']
  assert copy==old,('Unintended change',key)
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level()
 write('install',dict(status='saved_requires_reopen_audit',before_map_sha256=LOAD_SHA,map_sha256=sha(MAPFILE),backup=str(backup),changes=changes,preserved_components=len(after),changed_components=len(changes)))
 write('preservation-after',dict(status='recorded',map_sha256=sha(MAPFILE),components=after))

def immersion_audit():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;expected=read('preservation-after')['components']
 assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);assert sha(MAPFILE)==LOAD_SHA
 actual=ground_snapshot();assert actual==expected
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,preserved_components=len(actual),changed_tree_components=installed.get('tree_changed_components',installed['changed_components']),scope='Saved/reopened all component transforms, instance transforms, mesh/material bindings, visibility and collision profiles match the bounded installation snapshot.'))

def immersion_paths_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;plan=read('campus-route-plan');review=read('route-native-review');assert review['status']=='passed' and review['map_sha256']==LOAD_SHA and review['plan_sha256']==sha(OUT/'campus-route-plan.json');assert len(plan['routes'])==39 and not plan['issues'];assert not (OUT/'path-install.json').exists()
 before=ground_snapshot();assert before==read('preservation-after')['components'];backup=OUT/('UniversityCity-before-campus-paths-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 world=unreal.EditorLevelLibrary.get_editor_world();material=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly');cube=EAL.load_asset('/Engine/BasicShapes/Cube');assert material and cube
 c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,cube,material,'FlatCampus_Immersion_Paths');assert c;a=c.get_owner();a.set_actor_label('Immersion_CampusPaths');a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.set_mobility(unreal.ComponentMobility.STATIC)
 transforms=[unreal.Transform(location=unreal.Vector(*r['center']),rotation=unreal.Rotator(),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in plan['boxes']];c.add_instances(transforms,False,True,True);assert c.get_instance_count()==len(plan['boxes'])
 after=ground_snapshot();others=[r for r in after if r['actor']!='Immersion_CampusPaths'];assert others==before;assert len(after)==len(before)+1
 next(q for q in SUB.get_all_level_actors() if q.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),campus_path_strips=len(plan['boxes']),connected_exterior_routes=len(plan['routes']));write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('path-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),routes=len(plan['routes']),nonoverlapping_strips=len(plan['boxes']),native_preinstall_ground_samples=review['ground_samples'],native_preinstall_capsule_sweeps=review['capsule_sweeps'],material=material.get_path_name(),top_cm=1206,bottom_cm=1197))

def immersion_route_review():
 plan=read('campus-route-plan');world=unreal.EditorLevelLibrary.get_editor_world();unsupported=[];blocked=[];probes=0;sweeps=0
 for route in plan['routes']:
  points=route['points_cm']
  for index,p in enumerate(points):
   hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*p,1380),unreal.Vector(*p,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();probes+=1
   if not hit[0] or not 1190<=hit[4].z<=1215:unsupported.append(dict(route=route['id'],index=index,point_cm=p,hit=hit[0],position=num(hit[4]) if hit[0] else None,actor=hit[9].get_actor_label() if hit[0] else None))
  for index,(a,b) in enumerate(zip(points,points[1:])):
   if math.dist(a,b)<1:continue
   result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*a,1304),unreal.Vector(*b,1304),35.,88.));sweeps+=1
   if result['blocked']:blocked.append(dict(route=route['id'],index=index,start_cm=a,end_cm=b,result=result))
 write('route-native-review',dict(status='passed' if not unsupported and not blocked and not plan['issues'] else 'requires_repair',map_sha256=LOAD_SHA,plan_sha256=sha(OUT/'campus-route-plan.json'),ground_samples=probes,capsule_sweeps=sweeps,unsupported=unsupported,blocked=blocked,unresolved_plan_issues=plan['issues']))
 write('plan',dict(status='passed',map_sha256=LOAD_SHA,review_status='passed' if not unsupported and not blocked else 'requires_repair',ground_samples=probes,capsule_sweeps=sweeps))

def immersion_lod_inspect():
 api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);rows=[]
 for q in read('inventory')['meshes']:
  if not re.search(r'/TreeUpgradeV[12]/|/FloweringTrees/',q['mesh']):continue
  mesh=EAL.load_asset(q['mesh']);n=api.get_lod_count(mesh);row=dict(mesh=q['mesh'],lod_triangles=[mesh.get_num_triangles(i) for i in range(n)],positive_bounds_extension=num(mesh.get_editor_property('positive_bounds_extension')),negative_bounds_extension=num(mesh.get_editor_property('negative_bounds_extension')))
  try:row['screen_sizes']=list(api.get_lod_screen_sizes(mesh))
  except:row['screen_sizes_query']='unavailable'
  rows.append(row)
 assert sha(MAPFILE)==LOAD_SHA;write('inspect',dict(status='passed',map_sha256=LOAD_SHA,trees=rows))

def immersion_sight_probe():
 if (OUT/'sight-request.json').exists():
  request=read('sight-request');world=unreal.EditorLevelLibrary.get_editor_world();eye=request['eye'];target=request['target'];forward=[target[i]-eye[i] for i in range(3)];length=math.sqrt(sum(v*v for v in forward));forward=[v/length for v in forward];right=[-forward[1],forward[0],0];length=math.hypot(right[0],right[1]);right=[v/length for v in right];up=[forward[1]*right[2]-forward[2]*right[1],forward[2]*right[0]-forward[0]*right[2],forward[0]*right[1]-forward[1]*right[0]];rows=[]
  for px,py in request['pixels']:
   u=(px/1920*2-1)*math.tan(math.radians(request['fov']/2));v=(1-py/1080*2)*math.tan(math.radians(request['fov']/2))/(1920/1080);end=[eye[i]+(forward[i]+right[i]*u+up[i]*v)*15000 for i in range(3)];hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*eye),unreal.Vector(*end),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();rows.append(dict(pixel=[px,py],hit=hit[0],point=num(hit[4]) if hit[0] else None,actor=hit[9].get_actor_label() if hit[0] else None,component=hit[10].get_path_name() if hit[0] and hit[10] else None))
  write('sight-probe',dict(status='passed',map_sha256=LOAD_SHA,request=request,rays=rows));return
 world=unreal.EditorLevelLibrary.get_editor_world();eye=[79100.,56150.,1392.00004];target=[80000.,57250.,1332.];forward=[target[i]-eye[i] for i in range(3)];length=math.sqrt(sum(v*v for v in forward));forward=[v/length for v in forward];right=[-forward[1],forward[0],0];length=math.hypot(right[0],right[1]);right=[v/length for v in right];up=[forward[1]*right[2]-forward[2]*right[1],forward[2]*right[0]-forward[0]*right[2],forward[0]*right[1]-forward[1]*right[0]];rows=[]
 for px,py in [(860,700),(800,482),(590,280),(960,600),(1200,800),(900,550)]:
  u=(px/1920*2-1)*math.tan(math.radians(30));v=(1-py/1080*2)*math.tan(math.radians(30))/(1920/1080);direction=[forward[i]+right[i]*u+up[i]*v for i in range(3)];end=[eye[i]+direction[i]*15000 for i in range(3)];hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*eye),unreal.Vector(*end),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple()
  rows.append(dict(pixel=[px,py],hit=hit[0],point=num(hit[4]) if hit[0] else None,actor=hit[9].get_actor_label() if hit[0] else None,component=hit[10].get_path_name() if hit[0] and hit[10] else None))
 names=[dict(label=a.get_actor_label(),name=a.get_name(),path=a.get_path_name()) for a in SUB.get_all_level_actors()]
 write('sight-probe',dict(status='passed',map_sha256=LOAD_SHA,rays=rows,actor_names=names))

def immersion_arch_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/GardenArch';KEEP=[];save=save_asset
 source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0]
 source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)")
 namespace=dict(globals());exec('def import_one('+source,namespace);import_one=namespace['import_one'];api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);meshes=[]
 wood=EAL.load_asset('/Game/UniversityCity/ActivityScenesV1/ArtV2/M_walnut');metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');assert wood and metal
 for lod in range(3):
  mesh=import_one(OUT/'arch'/('LOD'+str(lod)+'.glb'),'supported-garden-arch',lod,False)
  for i,slot in enumerate(mesh.get_editor_property('static_materials')):
   name=str(slot.get_editor_property('imported_material_slot_name')).lower();assert 'walnut' in name or 'bronze' in name;mesh.set_material(i,wood if 'walnut' in name else metal)
  assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
 mesh=meshes[0]
 for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
 assert api.set_lod_screen_sizes(mesh,[1.,.20,.06]);body=mesh.get_editor_property('body_setup');body.set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(mesh,False)
 slots=[str(s.get_editor_property('imported_material_slot_name')) for s in mesh.get_editor_property('static_materials')];assert len(slots)==2
 write('arch-import',dict(status='passed',asset=mesh.get_path_name(),slots=slots,wood_slot=next(i for i,s in enumerate(slots) if 'walnut' in s.lower()),metal_slot=next(i for i,s in enumerate(slots) if 'bronze' in s.lower()),triangles=[mesh.get_num_triangles(i) for i in range(api.get_lod_count(mesh))],map_sha256=LOAD_SHA))

def immersion_sign_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];small=[]
 for item in SUB.get_all_level_actors():
  if item.get_actor_label().startswith('Activity_'):
   _,e=item.get_actor_bounds(False)
   if min(e.x,e.y)<30 and max(e.x,e.y)<200 and e.z<200:small.append(item)
 for a in SUB.get_all_level_actors():
  if not a.get_actor_label().startswith('Activity_') or a.get_editor_property('hidden'):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or not c.get_editor_property('visible') or c.get_editor_property('hidden_in_game') or '/Assets/sign/' not in c.static_mesh.get_path_name():continue
   origin,extent=a.get_actor_bounds(False);x,y,z=num(origin);ex,ey,ez=num(extent)
   if min(ex,ey)>10 or ez>90:continue
   normal=[1,0] if ex<ey else [0,1];tangent=[0,1] if ex<ey else [1,0];halfwidth=max(ex,ey);bottom=z-ez;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,bottom-4),unreal.Vector(x,y,bottom-650),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[a],unreal.DrawDebugTrace.NONE,True);hit=raw.to_tuple() if raw else None
   if not hit or not hit[0] or not 65<bottom-hit[4].z<300:continue
   wall=[]
   for side in [-1,1]:
    raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z),unreal.Vector(x+normal[0]*100*side,y+normal[1]*100*side,z),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[a],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None
    if h and h[0]:wall.append(h[9].get_actor_label())
   poles=[]
   for side in [-1,1]:
    px=x+tangent[0]*halfwidth*.7*side;py=y+tangent[1]*halfwidth*.7*side;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(px,py,bottom-5),unreal.Vector(px,py,bottom-80),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[a],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None
    if h and h[0]:poles.append(h[9].get_actor_label())
   anchors=[]
   if a.get_actor_label().startswith('Activity_ACTSPACE-08-'):
    for side in [-1,1]:
     candidates=[]
     for offset in [-20,-8,8,20]:
      px=x+tangent[0]*halfwidth*.7*side+normal[0]*offset;py=y+tangent[1]*halfwidth*.7*side+normal[1]*offset;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(px,py,bottom-5),unreal.Vector(px,py,bottom-300),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,small+[a],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None
      if h and h[0] and hit[4].z+35<h[4].z<bottom-8:candidates.append(dict(point_cm=num(h[4]),actor=h[9].get_actor_label(),offset=offset))
     if candidates:anchors.append(max(candidates,key=lambda q:q['point_cm'][2]))
   rows.append(dict(actor=a.get_actor_label(),component=c.get_name(),center_cm=[x,y,z],extent_cm=[ex,ey,ez],normal=normal,tangent=tangent,ground_cm=float(hit[4].z),ground_actor=hit[9].get_actor_label(),nearby_support=wall,existing_vertical_support=poles,proposed_standalone_support=not wall and not poles,furniture_anchors=anchors))
 write('sign-support-plan',dict(status='requires_review',map_sha256=LOAD_SHA,rows=rows))

def immersion_lod_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'lod-install.json').exists();assert ground_snapshot()==read('preservation-after')['components']
 before=ground_snapshot();backup=OUT/('UniversityCity-before-lod-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);assets={}
 for r in read('inspect')['trees']:
  p=r['mesh']
  if '/TreeUpgradeV2/' not in p or '/cypress/' in p:continue
  family=EAL.get_metadata_tag(EAL.load_asset(p),'TreeUpgradeId');assert family in ['banyan','columnar','terminalia','palm','willow']
  dest=IMM+'/LandscapeLOD/SM_'+family;mesh=EAL.load_asset(dest) if EAL.does_asset_exist(dest) else EAL.duplicate_asset(p,dest);assert mesh
  assert api.set_lod_screen_sizes(mesh,[1.,.30,.13,.055]);EAL.set_metadata_tag(mesh,'ImmersionLOD','Match the already refined camphor thresholds: retain geometric tree shape through pedestrian mid-distance; impostor only at farther distance.');assert EAL.save_loaded_asset(mesh,False);assets[p]=mesh
 changes=[]
 for a in SUB.get_all_level_actors():
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or c.static_mesh.get_path_name() not in assets:continue
   old=c.static_mesh.get_path_name();name=c.get_name();mats=[c.get_material(i) for i in range(c.get_num_materials())];c.modify();c.set_static_mesh(assets[old]);c.set_editor_property('override_materials',mats);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name);assert c.static_mesh==assets[old]
   changes.append(dict(actor=a.get_actor_label(),component=name,before=old,after=assets[old].get_path_name(),materials=[m.get_path_name() if m else None for m in mats]))
 assert len(assets)==5 and len(changes)==296,(len(assets),len(changes));after=ground_snapshot();changed={(r['actor'],r['component']):r for r in changes}
 for old,now in zip(before,after):
  row=dict(now);key=(old['actor'],old['component'])
  if key in changed:assert row['mesh']==changed[key]['after'];row['mesh']=old['mesh']
  assert row==old,('Unintended LOD-pass change',key)
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,changed_components=installed['changed_components']+len(changes),lod_changes=changes);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('lod-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),assets={k:v.get_path_name() for k,v in assets.items()},changes=changes))

def immersion_serve():
 # Private local job queue avoids repeatedly reloading this large map. Each
 # command has an expected map hash, code hash, unique receipt and error record.
 import datetime
 global IMM_SERVER_STATE,IMM_SERVER_HANDLE
 jobs=OUT/'jobs';jobs.mkdir(exist_ok=True);deadline=datetime.datetime.fromisoformat('2026-10-24T15:29:11+08:00').timestamp()
 IMM_SERVER_STATE=dict(busy=False,last_poll=0.,run_id=PAYLOAD['run_id'])
 write('serve-ready',dict(status='passed',map_sha256=LOAD_SHA,deadline='2026-10-24T15:29:11+08:00',jobs=str(jobs),note='Only this task local queue; close with a quit request.'))
 def close(reason):
  PAYLOAD['run_id']=IMM_SERVER_STATE['run_id'];write('serve-ready',dict(status='stopped',map_sha256=sha(MAPFILE),reason=reason));write('serve',dict(status='passed',map_sha256=sha(MAPFILE),reason=reason));unreal.unregister_slate_post_tick_callback(IMM_SERVER_HANDLE);unreal.SystemLibrary.quit_editor()
 def poll(dt):
  global LOAD_SHA,MODE
  if IMM_SERVER_STATE['busy'] or time.monotonic()-IMM_SERVER_STATE['last_poll']<1:return
  IMM_SERVER_STATE['last_poll']=time.monotonic()
  if time.time()>deadline:close('Twelve-hour unattended deadline reached');return
  for path in sorted(jobs.glob('*.request.json')):
   result=path.with_name(path.name.replace('.request.json','.result.json'))
   if result.exists():continue
   try:q=json.loads(path.read_text('utf8'))
   except:continue
   IMM_SERVER_STATE['busy']=True;started=time.time();PAYLOAD['run_id']=q['id']
   try:
    if q['function']=='quit':
     result.write_text(json.dumps(dict(status='passed',id=q['id'],reason='Requested clean close')),encoding='utf8');close('Requested clean close');return
    LOAD_SHA=sha(MAPFILE);assert q['expected_map_sha256']==LOAD_SHA,'Source map changed before queued job'
    assert hashlib.sha256(q['code'].encode('utf8')).hexdigest()==q['code_sha256'];assert re.fullmatch(r'immersion_[a-z_]+',q['function'])
    exec(compile(q['code'],'Tools/street_city_immersion_payload.lua::queued-definitions','exec'),globals());MODE=q['mode'];globals()[q['function']]()
    data=dict(status='passed',id=q['id'],function=q['function'],before_map_sha256=q['expected_map_sha256'],map_sha256=sha(MAPFILE),elapsed_seconds=time.time()-started,note='Function completed. Inspect its detailed acceptance/review receipt before continuing.')
   except BaseException:data=dict(status='failed',id=q['id'],error=traceback.format_exc(),elapsed_seconds=time.time()-started);unreal.log_error(traceback.format_exc())
   result.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8');IMM_SERVER_STATE['busy']=False;break
 IMM_SERVER_HANDLE=unreal.register_slate_post_tick_callback(poll)

def immersion_inventory():
 rows=[];meshes={};materials={};actors=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label();origin,extent=a.get_actor_bounds(False)
  actors.append(dict(label=label,class_name=a.get_class().get_name(),origin=num(origin),extent=num(extent),transform=actor_xform(a),hidden=a.get_editor_property('hidden')))
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh
   if not m:continue
   path=m.get_path_name();inst=isinstance(c,unreal.InstancedStaticMeshComponent)
   row=dict(actor=label,component=c.get_name(),mesh=path,visible=c.get_editor_property('visible'),hidden=c.get_editor_property('hidden_in_game'),collision=str(c.get_collision_profile_name()),materials=[c.get_material(i).get_path_name() if c.get_material(i) else None for i in range(c.get_num_materials())],transform=ground_transform(c.get_world_transform()))
   if inst:row['instances']=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]
   rows.append(row)
   if path not in meshes:
    bounds=m.get_bounds();entry=dict(mesh=path,bounds_origin=num(bounds.origin),bounds_extent=num(bounds.box_extent),uses=0,instances=0,examples=[])
    try:entry['lod0_vertices']=unreal.EditorStaticMeshLibrary.get_number_verts(m,0)
    except:pass
    meshes[path]=entry
   entry=meshes[path];entry['uses']+=1;entry['instances']+=len(row.get('instances',[1]))
   if len(entry['examples'])<8:entry['examples'].append(dict(actor=label,component=c.get_name(),materials=row['materials']))
   for mi in [c.get_material(i) for i in range(c.get_num_materials())]:
    if not mi or mi.get_path_name() in materials:continue
    chain,base=material_chain(mi);mr=dict(path=mi.get_path_name(),chain=chain)
    if base:mr.update(two_sided=base.get_editor_property('two_sided'),blend=str(base.get_editor_property('blend_mode')),instanced_usage=base.get_editor_property('used_with_instanced_static_meshes'))
    materials[mi.get_path_name()]=mr
 write('inventory',dict(status='passed',map_sha256=LOAD_SHA,actors=actors,components=rows,meshes=list(meshes.values()),materials=list(materials.values()),scope='Read-only complete native scene inventory for immersion review. No map or asset modifications.'))
 assert sha(MAPFILE)==LOAD_SHA

def work():
 try:
  if MODE=='inventory':immersion_inventory()
  elif MODE=='shader':immersion_import()
  elif MODE=='install':immersion_tree_install()
  elif MODE=='audit':immersion_audit()
  elif MODE=='plan':immersion_route_review()
  elif MODE=='inspect':immersion_lod_inspect()
  elif MODE=='serve':immersion_serve();return
  else:raise RuntimeError('Unsupported immersion mode')
 except BaseException:write(MODE+'-error',dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc())
 unreal.SystemLibrary.quit_editor()
assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry' if MODE in ['shader','inspect'] else MAP)
unreal.EditorPythonScripting.set_keep_python_script_alive(True)
frames=0
def tick(dt):
 global frames
 frames+=1
 if frames<90:return
 unreal.unregister_slate_post_tick_callback(handle);work()
handle=unreal.register_slate_post_tick_callback(tick)
]====]
