return [====[
def motel_site():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for bid,rect in [('H1',[-63,-27,73,50]),('S18',[-16,-20,16,20])]:
  root=actors['City_H1_F01' if bid=='H1' else 'S18_F01'].get_actor_location();x0,y0,x1,y1=rect;lo=[root.x+y0*100,root.y+x0*100,root.z];hi=[root.x+y1*100,root.y+x1*100,root.z+2400];hits=[]
  for label,a in actors.items():
   if not re.match(r'(City_|Campus_|S\d\d_|Mall_)',label) or not re.search(r'_F\d',label) or (bid=='H1' and label.startswith('City_H1_')) or (bid=='S18' and label.startswith('S18_')):continue
   p,e=a.get_actor_bounds(False);mn=[p.x-e.x,p.y-e.y,p.z-e.z];mx=[p.x+e.x,p.y+e.y,p.z+e.z]
   if all(min(hi[i],mx[i])-max(lo[i],mn[i])>1 for i in range(3)):hits.append(dict(actor=label,min=mn,max=mx))
  rows.append(dict(building=bid,base=num(root),proposed_local_bounds_m=rect,overlapping_foreign_buildings=hits))
 write('site-boundary-review',dict(status='passed_building_bounds_only' if all(not r['overlapping_foreign_buildings'] for r in rows) else 'requires_boundary_repair',map_sha256=LOAD_SHA,sites=rows,scope='Read-only foreign building AABB overlap; ground/props/player and car clearance remain separate required checks.'))

def motel_prop_probe():
 rows=[]
 for a in SUB.get_all_level_actors():
  if not a.get_actor_label().startswith('Street_'):continue
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   near=[]
   for i in range(c.get_instance_count()):
    tr=c.get_instance_transform(i,True);p=tr.translation
    if 32000<p.x<35000 and 64000<p.y<66000:near.append(dict(index=i,position=num(p),rotation=[tr.rotation.rotator().pitch,tr.rotation.rotator().yaw,tr.rotation.rotator().roll],scale=num(tr.scale3d)))
   if near:rows.append(dict(actor=a.get_actor_label(),component=c.get_name(),mesh=c.static_mesh.get_path_name(),total_instances=c.get_instance_count(),instances=near))
 write('ramp-props-probe',dict(status='read_only',map_sha256=LOAD_SHA,rows=rows))

def motel_stop_candidates():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for x in [35900,36300,36600,36800]:
  for y in [64600,65600]:
   hits=[]
   for dx,dy in [(0,0),(-180,-480),(-180,480),(180,-480),(180,480)]:
    p=unreal.Vector(x+dx,y+dy,1500);h=unreal.SystemLibrary.line_trace_single(world,p,p-unreal.Vector(0,0,500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();hits.append(dict(offset=[dx,dy],point=num(h[4]) if h[0] else None,actor=h[9].get_actor_label() if h[0] and h[9] else None))
   rows.append(dict(center=[x,y],support=hits))
 write('bus-stop-candidates',dict(status='read_only',map_sha256=LOAD_SHA,rows=rows))

def motel_stop_move():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};a=actors['Street_bus_shelter_05_02'];c=a.get_components_by_class(unreal.InstancedStaticMeshComponent)[0];old=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())];tr=c.get_instance_transform(0,True);assert (tr.translation-unreal.Vector(32700,64600,1200.2)).length()<1
 world=unreal.EditorLevelLibrary.get_editor_world();target=unreal.Vector(36720,64600,1206.2)
 for dx in [-220,0,220]:
  for dy in [-600,0,600]:
   p=target+unreal.Vector(dx,dy,200);h=unreal.SystemLibrary.line_trace_single(world,p,p-unreal.Vector(0,0,400),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert h[0] and 1190<=h[4].z<=1205.1,(dx,dy,num(h[4]) if h[0] else None)
 backup=OUT/('UniversityCity-before-motel-bus-stop-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);tr.translation=target;c.modify();assert c.update_instance_transform(0,tr,True,True,True);now=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())];assert now[1:]==old[1:]
 pad=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(36720,64600,1200));pad.set_actor_label('MotelV1_BusStop_WidenedPavement');pad.tags=[unreal.Name('MotelV1')];pad.set_folder_path('UniversityCity/MotelV1/Connections');pad.static_mesh_component.set_static_mesh(EAL.load_asset('/Engine/BasicShapes/Cube'));pad.static_mesh_component.set_material(0,EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly'));pad.static_mesh_component.set_collision_profile_name('BlockAll');pad.set_actor_scale3d(unreal.Vector(4.4,12.,.12))
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new,bounded_external_changes=[dict(actor=a.get_actor_label(),instance=0,before=old[0],after=now[0],other_instances_unchanged=True)]);write('motel-install',installed);write('bus-stop-relocation',dict(status='saved_requires_route_and_render_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),actor=a.get_actor_label(),instance=0,before=old[0],after=now[0],other_instances_unchanged=True,scope='Only the shelter instance under the new west ramp turning deck is moved to the street edge, with a supported widened stone footway. All other instances in the same cluster preserved.'))

def motel_driveway_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for y in [76700,77100,77500,77900]:
  points=[]
  for x in [34100,35000,36000,36700,37000,37200,37500]:
   p=unreal.Vector(x,y,1600);h=unreal.SystemLibrary.line_trace_single(world,p,p-unreal.Vector(0,0,500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();points.append(dict(point=num(h[4]) if h[0] else None,actor=h[9].get_actor_label() if h[0] and h[9] else None))
  clearance=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(34100,y,1331),unreal.Vector(37200,y,1331),110.,100.));rows.append(dict(center_y=y,ground=points,car_clearance=clearance))
 write('driveway-probe',dict(status='read_only',map_sha256=LOAD_SHA,rows=rows))

def motel_branch_space_probe():
 installed=read('motel-install');ids=[r['id'] for r in installed['rooms'] if r['building']=='S18'];actors=SUB.get_all_level_actors();ignore=[a for a in actors if a.get_actor_label() in ['MotelV1_Architecture_S18','MotelV1_Signs_S18'] or any(r in a.get_actor_label() for r in ids)];world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for shift in [800,1000,1200]:
  base=[48000+shift,50740,1200];lo=[base[0]-2000,base[1]-1600,1200];hi=[base[0]+2000,base[1]+1600,2700];hits=[]
  for a in actors:
   label=a.get_actor_label()
   if not re.match(r'(City_|Campus_|S\d\d_|Mall_)',label) or not re.search(r'_F\d',label) or label.startswith('S18_'):continue
   p,e=a.get_actor_bounds(False);mn=[p.x-e.x,p.y-e.y,p.z-e.z];mx=[p.x+e.x,p.y+e.y,p.z+e.z]
   if all(min(hi[i],mx[i])-max(lo[i],mn[i])>1 for i in range(3)):hits.append(label)
  ground=[]
  for x in [lo[0],48000,hi[0]]:
   for y in [lo[1]+100,50740,hi[1]-100]:
    p=unreal.Vector(x,y,1500);h=unreal.SystemLibrary.line_trace_single(world,p,p-unreal.Vector(0,0,400),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignore,unreal.DrawDebugTrace.NONE,True).to_tuple();ground.append(dict(point=num(h[4]) if h[0] else None,actor=h[9].get_actor_label() if h[0] and h[9] else None))
  rows.append(dict(shift_x_cm=shift,new_base=base,overlapping_foreign_buildings=hits,ground=ground))
 write('branch-space-probe',dict(status='read_only',map_sha256=LOAD_SHA,candidates=rows))
def motel_branch_expand():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;assert not installed.get('branch_expansion');probe=read('branch-space-probe');assert probe['map_sha256']==LOAD_SHA;candidate=next(r for r in probe['candidates'] if r['shift_x_cm']==1000);assert not candidate['overlapping_foreign_buildings'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};ids=[r['id'] for r in installed['rooms'] if r['building']=='S18'];owned=read('branch-objects');assert owned['map_sha256']==LOAD_SHA;labels=[r['actor'] for r in owned['rows'] if r['owned']];assert len(labels)==35,len(labels)
 backup=OUT/('UniversityCity-before-motel-branch-expansion-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);moves=[]
 for label in labels:
  a=actors[label];p=a.get_actor_location();a.modify();a.set_actor_location(p+unreal.Vector(1000,0,0),False,False);moves.append(dict(actor=label,before=num(p),after=num(a.get_actor_location())))
 # Relocate only the identified landscape instances occupying the enlarged rear edge.
 props=[]
 for label,index,delta in [('Street_cherry_04_04',7,1500),('Resort_cherry_0_5_5',0,1500),('LandscapeV3_SoilPlanters',6,1500),('LandscapeV3_TrunkCollision',268,1500),('Street_lamp_lantern_03_04',7,1500)]:
  a=actors[label];c=a.get_components_by_class(unreal.InstancedStaticMeshComponent)[0];old=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())];t=c.get_instance_transform(index,True);assert 50800<t.translation.x<51000;t.translation=t.translation+unreal.Vector(delta,0,0);c.modify();assert c.update_instance_transform(index,t,True,True,True);new=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())];assert all(old[i]==new[i] for i in range(len(old)) if i!=index);props.append(dict(actor=label,instance=index,before=old[index],after=new[index],delta=[delta,0,0],other_instances_unchanged=True))
 cube=EAL.load_asset('/Engine/BasicShapes/Cube');stone=EAL.load_asset('/Game/UniversityCity/MotelV1/Materials/MI_Stone');asphalt=EAL.load_asset('/Game/UniversityCity/MotelV1/Materials/MI_DrivewayAsphalt');assert cube and stone and asphalt
 for label,p,scale,mat in [('MotelV1_S18_SupportedFoundation',[49000,50740,1172.9],[40,32,.178],stone),('MotelV1_S18_TurningForecourt',[46500,50740,1185],[10,32,.42],asphalt)]:
  assert label not in actors;a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(*p));a.set_actor_label(label);a.tags=[unreal.Name('MotelV1')];a.set_folder_path('UniversityCity/MotelV1/Connections');a.set_actor_scale3d(unreal.Vector(*scale));a.static_mesh_component.set_static_mesh(cube);a.static_mesh_component.set_material(0,mat);a.static_mesh_component.set_collision_profile_name('BlockAll')
 for r in installed['rooms']:
  if r['building']=='S18':
   for key in ['position','eye','target','bath_eye','mirror_face','entry']:r[key][0]+=1000
 site=read('site-boundary-review');s=next(r for r in site['sites'] if r['building']=='S18');s['original_base']=s['base'];s['base']=candidate['new_base'];s['forecourt_world_bounds_cm']=[46000,49140,47000,52340]
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);receipt=dict(status='saved_requires_native_and_game_review',parent_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),building='S18',delta=[1000,0,0],actors=moves,landscape_instances=props,forecourt_size_m=[10,32],floors_preserved=3,rooms_preserved=3);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,branch_expansion=receipt);write('motel-install',installed);site['map_sha256']=newsha;write('site-boundary-review',site);write('branch-expansion',receipt)

def motel_branch_objects():
 rows=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label();p,e=a.get_actor_bounds(False)
  if p.x+e.x<45800 or p.x-e.x>51000 or p.y+e.y<49140 or p.y-e.y>52340:continue
  if label.startswith('MotelV1_') and ('S18' in label or any(r['id'] in label for r in read('motel-install')['rooms'] if r['building']=='S18') or label.startswith(('MotelV1_Practical_89','MotelV1_Practical_90','MotelV1_Practical_91','MotelV1_PracticalFixture_89_','MotelV1_PracticalFixture_90_','MotelV1_PracticalFixture_91_'))):rows.append(dict(actor=label,position=num(a.get_actor_location()),owned=True))
  elif a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
    for i in range(c.get_instance_count()):
     t=c.get_instance_transform(i,True);v=t.translation
     if 45800<v.x<51000 and 49140<v.y<52340:rows.append(dict(actor=label,component=c.get_name(),instance=i,position=num(v),owned=False,mesh=c.static_mesh.get_path_name() if c.static_mesh else None))
 write('branch-objects',dict(status='read_only',map_sha256=LOAD_SHA,rows=rows))
]====]
