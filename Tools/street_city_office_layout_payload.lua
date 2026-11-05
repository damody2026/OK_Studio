return [====[
OFFICE_LAYOUT_ACTIVE=None

def office_layout_data():
 global OFFICE_LAYOUT_ACTIVE
 if OFFICE_LAYOUT_ACTIVE is None and (OUT/'office-layout.json').is_file():OFFICE_LAYOUT_ACTIVE=read('office-layout')
 return OFFICE_LAYOUT_ACTIVE

def office_layout_actor_row(a):
 data=office_layout_data();return data.get('actor_rows',{}).get(a.get_actor_label()) if data else None

def actor_preservation_xform(a):
 now=actor_xform(a);row=office_layout_actor_row(a)
 if row:
  assert now==row['after'],('authorized office layout changed',a.get_actor_label());return row['before']
 return now

def office_original_component_location(a,c,now):
 row=office_layout_actor_row(a)
 if row and c.get_name() in row['components_before']:
  before=row['components_before'][c.get_name()];after=row['components_after'][c.get_name()]
  assert now['relative_location']==after['relative_location'];now['relative_location']=before['relative_location']
 return now

def office_original_point(a,p):
 row=office_layout_actor_row(a)
 return [p[k]-row['delta_cm'][k] for k in range(3)] if row else p

def office_instance_tf(t):
 r=t.rotation.rotator();return dict(location=num(t.translation),rotation=[round(r.pitch,3),round(r.yaw,3),round(r.roll,3)],scale=num(t.scale3d))

def environment_office_layout_audit():
 data=office_layout_data();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for label,row in data['actor_rows'].items():
  a=actors[label];assert actor_xform(a)==row['after'];actual={}
  for c in a.get_components_by_class(unreal.MeshComponent):
   now=component_row(a,c,{});expected=row['components_after'][c.get_name()]
   for slot in range(c.get_num_materials()):
    material=c.get_material(slot);parent=material
    while isinstance(parent,unreal.MaterialInstanceDynamic):parent=parent.get_editor_property('parent')
    if parent!=material and parent.get_path_name()==expected['materials'][slot]:now['materials'][slot]=expected['materials'][slot];now['slots'][slot]=expected['slots'][slot]
   actual[c.get_name()]=now
  assert actual==row['components_after'],('office member changed',label,{n:[k for k,v in expected.items() if actual[n].get(k)!=v] for n,expected in row['components_after'].items() if actual[n]!=expected})
 for row in data['instance_groups']:
  a=actors[row['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==row['component']);assert instance_record(c)[0]==row['after_hash'] and c.static_mesh.get_path_name()==row['mesh'] and str(c.get_collision_profile_name())==row['collision']
 for row in data['new_paths']:
  a=actors[row['actor']];assert actor_xform(a)==row['xform'] and str(a.static_mesh_component.get_collision_profile_name())=='BlockAll'
 write('office-layout-preservation',dict(status='passed',actor_translations=len(data['actor_rows']),instance_groups=len(data['instance_groups']),floors_preserved=6,rooms_preserved=24,new_access_paths=len(data['new_paths']),map_sha256=sha(MAPFILE),scope='Explicit O03 uniform translation and PK0110 fixture resiting; mesh/material/collision/rotation/scale retained, six floor IDs and room geometry unchanged.'))

def environment_office_layout(apply):
 global OUT,read,write,OFFICE_LAYOUT_ACTIVE,LOAD_SHA
 assert latest_map_sha()==LOAD_SHA and not (OUT/'office-layout.json').is_file()
 source_sha=LOAD_SHA;base_out=OUT;base_read=read;base_write=write;world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore()
 previous_preview=read('office_preview') if apply else None
 if apply:assert previous_preview['status']=='prepared_requires_apply' and previous_preview['source_map_sha256']==LOAD_SHA
 data=dict(status='prepared_requires_apply',source_map_sha256=LOAD_SHA,actor_rows={},instance_groups=[],new_paths=[],reason='User requested fixing office encroachment. Only O03 overlaps the PK0110 scenery; O02 remains in place and its incorrectly indoor viewpoint is replaced.');OFFICE_LAYOUT_ACTIVE=data
 def move_actor(a,delta):
  label=a.get_actor_label();assert label not in data['actor_rows'];before=actor_xform(a);components={c.get_name():component_row(a,c,{}) for c in a.get_components_by_class(unreal.MeshComponent)};a.modify();a.set_actor_location(a.get_actor_location()+unreal.Vector(*delta),False,True);after=actor_xform(a);after_components={c.get_name():component_row(a,c,{}) for c in a.get_components_by_class(unreal.MeshComponent)}
  assert before['rotation']==after['rotation'] and before['scale']==after['scale'];assert all(after_components[n][k]==v for n,row in components.items() for k,v in row.items() if k!='relative_location')
  data['actor_rows'][label]=dict(before=before,after=after,delta_cm=delta,components_before=components,components_after=after_components)
 labels=[label for label in actors if label.startswith('City_O03_F') or label in ['RomanceArch_O03','RomanceName_O03','CityArtLight_O03'] or label.startswith('ResortLantern_O03_')]
 assert sum(label.startswith('City_O03_F') for label in labels)==6 and len(labels)>=22
 for label in labels:move_actor(actors[label],[-500.,0.,0.])
 requests=json.loads((ROOT/'output/street-social-city-production/city-art-v1/install.json').read_text('utf8'))['dressing']['groups'];instance_moves={}
 for group in requests:
  indices=[index for index,q in enumerate(group['requests']) if q['building']=='O03']
  if not indices:continue
  a=actors[group['label']];c=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent);assert c.get_instance_count()==group['count']
  for index in indices:
   q=group['requests'][index];p=c.get_instance_transform(index,True).translation;assert math.dist(num(p),[q['position_m'][1]*100,q['position_m'][0]*100,q['position_m'][2]*100])<.1
  instance_moves[(group['label'],c.get_name())]=set(indices)
 scene=jread(base_out/'surface-final/scene.json')
 for i in scene['instances']:
  if i['actor'].startswith('Resort_') and i['actor'].endswith('_hotel-wellness') and i['instance']>=0 and 30900<=i['matrix'][12]<=31150 and 79555<=i['matrix'][13]<=85245:
   instance_moves.setdefault((i['actor'],i['component']),set()).add(i['instance'])
 for (label,name),indices in instance_moves.items():
  a=actors[label];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==name);before_hash=instance_record(c)[0];all_before=[office_instance_tf(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())];changes=[];c.modify()
  for i in sorted(indices):
   t=c.get_instance_transform(i,True);t.translation=t.translation+unreal.Vector(-500,0,0);assert c.update_instance_transform(i,t,True,True,True);changes.append(dict(index=i,before=all_before[i],after=office_instance_tf(c.get_instance_transform(i,True))))
  assert all(office_instance_tf(c.get_instance_transform(i,True))==p for i,p in enumerate(all_before) if i not in indices)
  data['instance_groups'].append(dict(actor=label,component=name,before_hash=before_hash,after_hash=instance_record(c)[0],mesh=c.static_mesh.get_path_name(),collision=str(c.get_collision_profile_name()),changes=changes))
 cube=EAL.load_asset('/Engine/BasicShapes/Cube.Cube');stone=actors['ResortLantern_O03_Plinth'].static_mesh_component.get_material(0);proof=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(stone));assert proof['static_opaque_no_depth_displacement'] and not proof['two_sided']
 def path_part(label,location,scale,rotation=unreal.Rotator()):
  assert label not in actors;a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,location,rotation);a.set_actor_label(label);a.set_editor_property('tags',['CityOfficeSetbackV1']);a.set_folder_path('UniversityCity/OfficeSetbackV1');c=a.static_mesh_component;c.set_static_mesh(cube);c.set_material(0,stone);c.set_collision_profile_name('BlockAll');a.set_actor_scale3d(unreal.Vector(*scale));actors[label]=a;data['new_paths'].append(dict(actor=label,xform=actor_xform(a)))
 top=1211.6176719665527;width=230.;x=36172.5;start_y=81700.;end_y=82300.;rise=top-1165.;length=end_y-start_y;hyp=math.hypot(length,rise);normal=unreal.Vector(0,-rise/hyp,length/hyp);rot=unreal.MathLibrary.make_rot_from_xz(unreal.Vector(0,length,rise),normal);mid=unreal.Vector(x,(start_y+end_y)*.5,(1165.+top)*.5)-normal*10.
 path_part('OfficeSetback_PK0110_Ramp',mid,[hyp/100,width/100,.2],rot)
 path_part('OfficeSetback_PK0110_Deck',unreal.Vector(36178.75,83500,top-25),[2.425,24.,.5])
 approaches=[]
 for y in [81700,82000,82250,82400,83200,84000,84600]:
  hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,4000),unreal.Vector(x,y,800),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None;assert v and v[0] and v[7].z>.85
  z=v[4].z;result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+120),unreal.Vector(x,y+60,z+120),100,110));assert not result['blocked'],('new public ramp obstructed',y,result);approaches.append(dict(position_cm=num(v[4]),support=v[9].get_actor_label(),clearance=result))
 sites=read('sites');site=next(r for r in sites['rows'] if r['id']=='PK-0110');data['site_before']=json.loads(json.dumps(site));chosen=[]
 for px,py in [(px,py) for px in [36700,37900,37100,37500] for py in [82700,84200,83200,83700]]:
  hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(px,py,4000),unreal.Vector(px,py,800),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None
  if not v or not v[0] or v[9].get_actor_label()!='World_PK_0110' or not 1205<v[4].z<1220 or v[7].z<.85:continue
  p=num(v[4]);begin=[px,py+125,p[2]+120];end=[px,py+385,p[2]+120];sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*begin),unreal.Vector(*end),100,110))
  if sweep['blocked'] or any(math.dist(p,q['position_cm'])<800 for q in chosen):continue
  template=json.loads(json.dumps(site['sites'][len(chosen)]));template.update(position_cm=p,support_actor='World_PK_0110',normal=num(v[7]),approach_start_cm=begin,approach_end_cm=end);chosen.append(template)
  if len(chosen)==2:break
 assert len(chosen)==2,'No pair of real outdoor PK0110 standing positions';site['sites']=chosen;site['anchor_cm']=[37350.,83500.,top];site['camera']=dict(eye=[x,83500.,top+180],target=[37350.,83500.,top+110],fov=70);site['status']='located_on_corrected_outdoor_ground';data['site_after']=site
 install=read('install');data['fixtures_before']=[json.loads(json.dumps(r)) for r in install['fixtures'] if r['id']=='PK-0110']
 for fixture in install['fixtures']:
  if fixture['id']!='PK-0110':continue
  new=chosen[fixture['site']];delta=[new['position_cm'][k]-fixture['position_cm'][k] for k in range(3)]
  for label in fixture['actors']:move_actor(actors[label],delta)
  for key in ['position_cm','support_actor','approach_start_cm','approach_end_cm']:fixture[key]=new[key]
 data['fixtures_after']=[r for r in install['fixtures'] if r['id']=='PK-0110'];data['access_checks']=approaches
 origin,extent=actors['RomanceArch_O03'].get_actor_bounds(False);assert origin.x+extent.x<=36100 and 36300-(origin.x+extent.x)>=200
 proposal_out=base_out/('office-validation-'+PAYLOAD['run_id']);proposal_out.mkdir()
 def proposed_read(name):
  if name=='sites':return sites
  if name=='install':return install
  return json.loads((base_out/(name+'.json')).read_text('utf-8-sig'))
 read=proposed_read
 def proposed_write(name,value):
  value['run_id']=PAYLOAD['run_id'];(proposal_out/(name+'.json')).write_text(json.dumps(value,ensure_ascii=False,indent=2),'utf8')
 write=proposed_write
 try:
  environment_audit();environment_office_layout_audit();environment_camera_validation();cameras=jread(proposal_out/'cameras.json');assert all(r['camera'] for r in cameras['rows']),[r['id'] for r in cameras['rows'] if not r['camera']]
  data['camera_count']=len(cameras['rows']);data['validation_folder']=proposal_out.name;data['room_geometry_preserved']=True
 finally:OUT=base_out;read=base_read;write=base_write
 assert sha(MAPFILE)==source_sha
 if not apply:write('office_preview',data);return
 assert previous_preview['site_after']==data['site_after'] and set(previous_preview['actor_rows'])==set(data['actor_rows'])
 backup=OUT/'backups'/('UniversityCity-before-office-setback-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);write('office-layout-pending-'+PAYLOAD['run_id'],data);controller.initialize_bindings();controller.set_hour(21.);controller.apply_environment();controller.prepare_for_save();assert sha(MAPFILE)==source_sha;assert unreal.EditorLevelLibrary.save_current_level();record_map_save('O03-setback-and-PK0110-outdoor-access');LOAD_SHA=sha(MAPFILE);data.update(status='passed',map_sha256=LOAD_SHA,backup=str(backup));write('office-layout',data);write('sites-before-office-setback',read('sites'));sites['map_sha256']=LOAD_SHA;write('sites',sites);write('install-before-office-setback',read('install'));write('install',install);write('office_apply',dict(status='passed',map_sha256=LOAD_SHA,translated_floors=6,room_geometry_preserved=True,cameras=80))
 current=OUT/'surface-final';archive=OUT/('surface-final-before-office-'+PAYLOAD['run_id']);assert not archive.exists();current.rename(archive);environment_depth_export();environment_audit()
]====]
