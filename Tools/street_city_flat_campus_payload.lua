return [====[
FLAT='/Game/UniversityCity/FlatCampusV1'

def flat_inventory():
 actors=SUB.get_all_level_actors();rows=[]
 for a in actors:
  origin,extent=a.get_actor_bounds(False)
  rows.append(dict(label=a.get_actor_label(),name=a.get_name(),class_name=a.get_class().get_name(),xform=actor_xform(a),origin=num(origin),extent=num(extent),tags=[str(t) for t in a.tags],hidden=a.get_editor_property('hidden')))
 write('inventory',dict(status='passed',map_sha256=LOAD_SHA,actors=rows,components=ground_snapshot()))
 write('flat_inventory',dict(status='passed',map_sha256=LOAD_SHA,actors=len(rows)))

def flat_material(name,rgb,metal=0.,rough=.7):
 path=FLAT+'/Materials/'+name
 if EAL.does_asset_exist(path):return EAL.load_asset(path)
 m=ATS.create_asset(name,FLAT+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
 v=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);v.set_editor_property('constant',unreal.LinearColor(*rgb,1));MEL.connect_material_property(v,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for val,prop in [(metal,unreal.MaterialProperty.MP_METALLIC),(rough,unreal.MaterialProperty.MP_ROUGHNESS)]:
  n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);n.set_editor_property('r',val);MEL.connect_material_property(n,'',prop)
 MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def flat_sign(q):
 name='T_Gate_'+q['id'];task=unreal.AssetImportTask();task.filename=q['texture'];task.destination_path=FLAT+'/Signs';task.destination_name=name;task.automated=True;task.replace_existing=True;task.save=True;ATS.import_asset_tasks([task]);t=EAL.load_asset(FLAT+'/Signs/'+name);assert t;t.set_editor_property('max_texture_size',2048);t.set_editor_property('lod_group',unreal.TextureGroup.TEXTUREGROUP_UI);assert EAL.save_loaded_asset(t,False)
 path=FLAT+'/Signs/M_Gate_'+q['id'];m=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset('M_Gate_'+q['id'],FLAT+'/Signs',unreal.Material,unreal.MaterialFactoryNew());MEL.delete_all_material_expressions(m);m.set_editor_property('two_sided',True)
 s=MEL.create_material_expression(m,unreal.MaterialExpressionTextureSample);s.set_editor_property('texture',t);MEL.connect_material_property(s,'RGB',unreal.MaterialProperty.MP_BASE_COLOR)
 uv=MEL.create_material_expression(m,unreal.MaterialExpressionTextureCoordinate);rot=MEL.create_material_expression(m,unreal.MaterialExpressionCustom);inp=unreal.CustomInput();inp.set_editor_property('input_name','T');rot.set_editor_property('inputs',[inp]);rot.set_editor_property('code','return float2(1-T.y,1-T.x);');rot.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT2);MEL.connect_material_expressions(uv,'',rot,'T');MEL.connect_material_expressions(rot,'',s,'UVs')
 mul=MEL.create_material_expression(m,unreal.MaterialExpressionMultiply);mul.set_editor_property('const_b',1.8);MEL.connect_material_expressions(s,'RGB',mul,'A');MEL.connect_material_property(mul,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 r=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);r.set_editor_property('r',.55);MEL.connect_material_property(r,'',unreal.MaterialProperty.MP_ROUGHNESS);MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def flat_enclosure(plan):
 world=unreal.EditorLevelLibrary.get_editor_world();cube=EAL.load_asset('/Engine/BasicShapes/Cube');plane=EAL.load_asset('/Engine/BasicShapes/Plane');assert cube and plane
 stone=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly');bronze=flat_material('M_CampusBronze',[.055,.075,.065],.75,.45);cap=flat_material('M_CampusCap',[.14,.09,.045],.4,.48)
 groups={}
 for name,mat in [('Stone',stone),('Bronze',bronze),('Cap',cap)]:
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,cube,mat,'FlatCampus_Fence_'+name);assert c;c.set_collision_profile_name('BlockAll');c.get_owner().set_folder_path('UniversityCity/FlatCampusV1');groups[name]=c
 def box(group,center,size,yaw=0):
  t=unreal.Transform(location=unreal.Vector(*center),rotation=unreal.Rotator(pitch=0,yaw=yaw,roll=0),scale=unreal.Vector(*[v/100 for v in size]));groups[group].add_instance(t,True)
 bounds=plan['campus_bounds_cm'];xmin,ymin,xmax,ymax=bounds;edges=[([xmin,ymin],[xmin,68600]),([xmin,68600],[55450,68600]),([55450,68600],[55450,71400]),([55450,71400],[xmin,71400]),([xmin,71400],[xmin,ymax]),([xmax,ymin],[xmax,ymax]),([xmin,ymin],[xmax,ymin]),([xmin,ymax],[xmax,ymax])];fence_intervals=[]
 for start,end in edges:
  dx,dy=end[0]-start[0],end[1]-start[1];length=math.hypot(dx,dy);tx,ty=dx/length,dy/length;yaw=math.degrees(math.atan2(ty,tx));intervals=[(0,length)]
  for q in plan['gates']:
   cx,cy=q['center'];cross=abs((cx-start[0])*ty-(cy-start[1])*tx)
   if cross>1:continue
   middle=(cx-start[0])*tx+(cy-start[1])*ty;gap=q['width']/2+150;lo,hi=middle-gap,middle+gap;intervals=[v for a,b in intervals for v in [(a,min(b,lo)),(max(a,hi),b)] if v[1]-v[0]>1]
  for a,b in intervals:
   count=max(1,math.ceil((b-a)/400));step=(b-a)/count
   for i in range(count):
    t=a+(i+.5)*step;x,y=start[0]+t*tx,start[1]+t*ty
    box('Stone',[x,y,1222],[step-2,32,44],yaw);box('Cap',[x,y,1249],[step-2,38,10],yaw)
    for z in [1280,1378]:box('Bronze',[x,y,z],[step-6,8,7],yaw)
    for k in range(1,10):
     u=a+i*step+k*step/10;box('Bronze',[start[0]+u*tx,start[1]+u*ty,1320],[4,4,130],yaw)
   for i in range(count+1):
    t=a+i*step;box('Stone',[start[0]+t*tx,start[1]+t*ty,1305],[45,45,210]);box('Cap',[start[0]+t*tx,start[1]+t*ty,1415],[55,55,10])
   fence_intervals.append(dict(start=[start[0]+a*tx,start[1]+a*ty],end=[start[0]+b*tx,start[1]+b*ty]))
 gate_rows=[]
 for q in plan['gates']:
  x,y=q['center'];angle=math.radians(q['yaw']);nx,ny=math.cos(angle),math.sin(angle);tx,ty=-ny,nx;width=q['width'];half=width/2+60
  for sign in [-1,1]:
   px,py=x+tx*sign*half,y+ty*sign*half
   box('Stone',[px,py,1460],[130,130,520]);box('Cap',[px,py,1725],[150,150,20])
  box('Bronze',[x,y,1700],[65,width+240,150],q['yaw']);box('Cap',[x,y,1780],[82,width+280,10],q['yaw'])
  mat=flat_sign(q)
  for side in [-1,1]:
   a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x+side*nx*34,y+side*ny*34,1700),unreal.Rotator(pitch=90,yaw=q['yaw']+(180 if side<0 else 0),roll=0));a.set_actor_label('FlatCampus_Gate_'+q['id']+('_Outer' if side>0 else '_Inner'));a.tags=[unreal.Name('FlatCampusV1')];a.set_folder_path('UniversityCity/FlatCampusV1');c=a.static_mesh_component;c.set_static_mesh(plane);c.set_material(0,mat);c.set_collision_profile_name('NoCollision');a.set_actor_scale3d(unreal.Vector(1.35,(width+160)/100,1));c.set_cast_shadow(False)
  # A thick approach slab bridges the ground datum without coplanar overlapping faces.
  outward={'SouthMain':1300,'SouthWalk':1300,'WestSport':1300,'NorthDorm':1000,'EastGarden':800}[q['id']];offset=(outward-500)/2
  box('Stone',[x+nx*offset,y+ny*offset,1194.5],[outward+500,width-40,14],q['yaw'])
  gate_rows.append(dict(q,clear_width_cm=width,lintel_clear_height_cm=425,sign_faces=2,lettering='large warm luminous text on dark background'))
 return dict(bounds_cm=bounds,fence_intervals=fence_intervals,gates=gate_rows,instance_counts={k:c.get_instance_count() for k,c in groups.items()},school_name=plan['school_name'])

def flat_install():
 plan=read('plan');baseline=read('inventory');assert plan['map_sha256']==baseline['map_sha256']==LOAD_SHA==sha(MAPFILE);assert not (OUT/'install.json').exists();assert ground_snapshot()==baseline['components']
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 backup=OUT/('UniversityCity-before-flat-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'plan.json')));write('native-meshes',result);assert result['status']=='passed',result
 for q in plan['changes']:
  a=actors[q['actor']]
  if q['kind']=='actor':
   assert actor_xform(a)==q['before'];a.modify();a.set_actor_location(a.get_actor_location()+unreal.Vector(0,0,q['delta_z_cm']),False,True)
  else:
   c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==q['component']);assert c.get_instance_count()==q['count'];c.modify()
   for r in q['changes']:
    t=c.get_instance_transform(r['index'],True);t.translation=t.translation+unreal.Vector(0,0,r['delta_z_cm']);assert c.update_instance_transform(r['index'],t,True,False,True)
   c.mark_render_state_dirty() if hasattr(c,'mark_render_state_dirty') else None
 enclosure=flat_enclosure(plan);assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 write('install',dict(status='saved_requires_reopen_audit',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),datum_cm=1200,meshes=result['meshes'],enclosure=enclosure,groups_rebased=len(plan['changes'])))
 write('preservation',dict(status='recorded_requires_audit',before=baseline['components'],after=ground_snapshot()))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='flat_city_named_campus_enclosure',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8')
 write('flat_install',dict(status='passed',map_sha256=newsha,groups=len(plan['changes']),meshes=len(result['meshes']),gates=len(enclosure['gates'])))

def flat_audit():
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE);actual=ground_snapshot();expected=read('preservation')['after'];assert actual==expected,'Saved flat map differs after reopening'
 old={(r['actor'],r['component']):r for r in read('preservation')['before']};new={(r['actor'],r['component']):r for r in actual};meshes={r['key']:r for r in installed['meshes']};count=0
 for key,before in old.items():
  after=new[key];assert after['materials']==before['materials'] and after['collision']==before['collision'] and after['visible']==before['visible'] and after['hidden']==before['hidden'] and after['actor_hidden']==before['actor_hidden'],key
  assert after['transform']['scale']==before['transform']['scale'] and after['transform']['rotation']==before['transform']['rotation'],key
  assert after['mesh']==(meshes[key[0]+'::'+key[1]]['after'] if key[0]+'::'+key[1] in meshes else before['mesh']),key
  if 'instances' in before:assert len(before['instances'])==len(after['instances']),key
  count+=1
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();probes=[]
 for q in installed['enclosure']['gates']:
  x,y=q['center'];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1500),unreal.Vector(x,y,1000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert raw[0],q['id'];p=num(raw[4]);assert abs(p[2]-1201.5)<.5,(q['id'],p);probes.append(dict(id=q['id'],ground_cm=p,support=raw[9].get_actor_label()))
  for suffix in ['Outer','Inner']:assert 'FlatCampus_Gate_'+q['id']+'_'+suffix in actors
 clearance=[]
 for q in installed['enclosure']['gates']:
  x,y=q['center'];r=math.radians(q['yaw']);nx,ny=math.cos(r),math.sin(r)
  sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x+nx*600,y+ny*600,1300),unreal.Vector(x-nx*600,y-ny*600,1300),35.,88.));clearance.append(dict(gate=q['id'],**sweep));assert not sweep['blocked'],('gate passage blocked',q['id'],sweep)
 thresholds=[];exterior=[];foundation=json.loads((ROOT/'output/street-social-city-production/world-ground-v1/campus-foundations.json').read_text('utf8'))
 for b in foundation['buildings']:
  if b['id'] not in ['E1','EE','MA','T4','T2','IB','T1','RB','AD','LI','SC','IN','SP','D1','D2','D3','D4']:continue
  cx,cy,z=b['world_position_m']
  for e in b['entrances']:
   dx,dy={'W':(-1,0),'E':(1,0),'S':(0,-1),'N':(0,1)}[e['facade_side']]
   for distance in [.25,1.,3.4]:
    ex,ey,_=e['position_m'];east=(cx+ex+dx*distance)*100;north=(cy+ey+dy*distance)*100;hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(north,east,1390),unreal.Vector(north,east,900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert hit[0],('missing threshold support',b['id'],e['id'],distance);p=num(hit[4]);assert 1160<=p[2]<=1220,('threshold height',b['id'],e['id'],p);thresholds.append(dict(building=b['id'],entry=e['id'],distance_m=distance,ground_cm=p,support=hit[9].get_actor_label()))
   if installed.get('exterior_ground_grade_cm'):
    for distance in [5.,7.]:
     ex,ey,_=e['position_m'];east=(cx+ex+dx*distance)*100;north=(cy+ey+dy*distance)*100;hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(north,east,1220),unreal.Vector(north,east,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert hit[0],('exterior support missing',b['id'],e['id'],distance);p=num(hit[4]);assert 1190<=p[2]<=1210,('exterior grade',b['id'],e['id'],distance,p);exterior.append(dict(building=b['id'],entry=e['id'],distance_m=distance,ground_cm=p,support=hit[9].get_actor_label()))
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,components_preserved=count,material_bindings_preserved=True,building_floors_preserved=True,gates=5,gate_ground_probes=probes,gate_capsule_sweeps=clearance,threshold_probes=thresholds,exterior_grade_probes=exterior,scope='Saved/reopened map, component preservation, gate support/capsule sweeps and campus threshold/approach samples; rendered review remains required'))
 write('flat_audit',dict(status='passed',map_sha256=LOAD_SHA))

def flat_finalize():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};c=actors['FlatCampus_Fence_Stone'].get_component_by_class(unreal.InstancedStaticMeshComponent);changed=[]
 for q in installed['enclosure']['gates']:
  found=[]
  for i in range(c.get_instance_count()):
   t=c.get_instance_transform(i,True)
   if abs(t.translation.x-q['center'][0])<.01 and abs(t.translation.y-q['center'][1])<.01 and abs(t.translation.z-1193)<.01 and abs(t.scale3d.z-.14)<.001:found.append((i,t))
  assert len(found)==1,(q['id'],len(found));i,t=found[0];t.translation=t.translation+unreal.Vector(0,0,1.5);assert c.update_instance_transform(i,t,True,True,True);changed.append(dict(gate=q['id'],instance=i,top_cm=1201.5))
 controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,approach_depth_separation_cm=1.5);write('install',installed);preserved=read('preservation');preserved['after']=ground_snapshot();write('preservation',preserved);write('approach-separation',dict(status='passed',map_sha256=newsha,changes=changed,reason='Separate new gate paving from existing 1200cm path faces by 1.5cm, without a visible step.'))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='campus_gate_paving_depth_separation',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha
 assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);flat_audit();write('flat_finalize',dict(status='passed',map_sha256=LOAD_SHA))

def flat_rebuild_enclosure():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];plan=read('plan');plan['gates'][0]['center']=[54800,57500];write('plan',plan)
 for a in SUB.get_all_level_actors():
  if a.get_actor_label().startswith('FlatCampus_'):
   assert 'FlatCampusV1' in [str(t) for t in a.tags];assert SUB.destroy_actor(a)
 installed['enclosure']=flat_enclosure(plan);controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed['map_sha256']=newsha;installed['approach_depth_separation_cm']=1.5;write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p)
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='campus_gate_obstacle_clearance',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);flat_audit();write('flat_rebuild_enclosure',dict(status='passed',map_sha256=LOAD_SHA))

def flat_name_polish():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];oldsha=LOAD_SHA;plan=read('plan');assert plan['school_name']=='影輝大學'
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};ocean=actors['Activity_ACTSPACE-04-351'];pos=ocean.get_actor_location();assert abs(pos.z-1488)<.01;ocean.set_actor_location(pos+unreal.Vector(0,0,-400),False,True)
 moved=[]
 for label,index in [('Resort_camphor_1_5_5',3),('Street_drain_04_04',3)]:
  a=actors[label];c=a.get_component_by_class(unreal.InstancedStaticMeshComponent);t=c.get_instance_transform(index,True);assert abs(t.translation.y-57400)<.01;t.translation=t.translation+unreal.Vector(0,-1000,0);assert c.update_instance_transform(index,t,True,True,True);moved.append(dict(actor=label,index=index,delta_cm=[0,-1000,0]))
 for a in SUB.get_all_level_actors():
  if a.get_actor_label().startswith('FlatCampus_'):assert 'FlatCampusV1' in [str(t) for t in a.tags];assert SUB.destroy_actor(a)
 installed['enclosure']=flat_enclosure(plan);controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=oldsha,school_name='影輝大學');write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);write('name-polish',dict(status='passed',map_sha256=newsha,school_name='影輝大學',ocean_surface_cm=1100,landscape_relocations=moved,fence_notch_cm=[54800,68600,55450,71400],lettering_uv='upright on Engine Plane'))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='yinghui_gate_name_and_boundary_polish',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);flat_audit();write('flat_name_polish',dict(status='passed',map_sha256=LOAD_SHA))

def flat_grade():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==read('grade-plan')['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];shutil.copy2(MAPFILE,OUT/('UniversityCity-before-ground-fill-'+LOAD_SHA[:16]+'.umap'))
 result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'grade-plan.json')));write('native-grade',result);assert result['status']=='passed',result
 bykey={r['key']:r for r in installed['meshes']}
 for r in result['meshes']:bykey[r['key']]['grade_before']=r['before'];bykey[r['key']]['after']=r['after']
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,exterior_ground_grade_cm=1198);write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='fill_exterior_residual_foundation_depressions',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);flat_audit();write('flat_grade',dict(status='passed',map_sha256=LOAD_SHA,ground_grade_cm=1198))

def flat_annex():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==read('annex-plan')['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'annex-plan.json')));write('native-annex',result);assert result['status']=='passed',result
 row=result['meshes'][0];r=next(q for q in installed['meshes'] if q['key']==row['key']);r['annex_before']=row['before'];r['after']=row['after'];a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='Outdoor_annex_ground');c=a.static_mesh_component;c.set_cull_distance(0.)
 for key,value in [('never_distance_cull',True),('allow_cull_distance_volume',False)]:c.set_editor_property(key,value)
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,annex_grade_cm=1198);write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='flat_annex_and_ground_distance_visibility',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP)
 a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='Outdoor_annex_ground');c=a.static_mesh_component;b=c.static_mesh.get_bounding_box();t=c.get_world_transform();low=t.transform_location(b.min);high=t.transform_location(b.max);assert abs(low.z-1188)<.01 and abs(high.z-1198)<.01;assert c.get_editor_property('never_distance_cull') and not c.get_editor_property('allow_cull_distance_volume');write('annex-grade',dict(status='passed',map_sha256=LOAD_SHA,min_z_cm=low.z,max_z_cm=high.z,never_distance_cull=True,allow_cull_distance_volume=False))
 flat_audit();write('flat_annex',dict(status='passed',map_sha256=LOAD_SHA))

def flat_site_polish():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];assert not (OUT/'site-polish.json').exists()
 a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='World_PK_0112');before=actor_xform(a);shutil.copy2(MAPFILE,OUT/('UniversityCity-before-PK0112-floor-'+LOAD_SHA[:16]+'.umap'));a.modify();a.set_actor_location(a.get_actor_location()+unreal.Vector(0,0,6.),False,True);after=actor_xform(a)
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,site_polish_actor='World_PK_0112',site_polish_delta_cm=6);write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='PK0112_clear_grass_intersection',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);flat_audit()
 annex=read('annex-grade');annex['map_sha256']=LOAD_SHA;write('annex-grade',annex);write('site-polish',dict(status='passed',map_sha256=LOAD_SHA,actor='World_PK_0112',before=before,after=after,reason='Primary 408m2 thin paving was 1196cm, below the 1198cm grass datum; raise complete site 6cm to 1202cm while preserving internal furniture relationships.'));write('flat_site_polish',dict(status='passed',map_sha256=LOAD_SHA))

def flat_site_grade():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==read('PK0112-grade-plan')['map_sha256']==sha(MAPFILE);assert ground_snapshot()==read('preservation')['after'];result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'PK0112-grade-plan.json')));write('native-PK0112-grade',result);assert result['status']=='passed',result;installed['meshes']+=result['meshes']
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,PK0112_paving_cm=1202);write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='PK0112_paving_and_furniture_support_field',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time()),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);flat_audit();annex=read('annex-grade');annex['map_sha256']=LOAD_SHA;write('annex-grade',annex);write('flat_site_grade',dict(status='passed',map_sha256=LOAD_SHA,paving_cm=1202))

def work():
 try:
  if MODE=='flat_inventory':flat_inventory()
  elif MODE=='flat_install':flat_install()
  elif MODE=='flat_audit':flat_audit()
  elif MODE=='flat_finalize':flat_finalize()
  elif MODE=='flat_rebuild_enclosure':flat_rebuild_enclosure()
  elif MODE=='flat_name_polish':flat_name_polish()
  elif MODE=='flat_grade':flat_grade()
  elif MODE=='flat_annex':flat_annex()
  elif MODE=='flat_site_polish':flat_site_polish()
  elif MODE=='flat_site_grade':flat_site_grade()
  else:raise RuntimeError('Use flat_inventory, flat_install, flat_audit')
 except BaseException:write(MODE+'-error',dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc())
 unreal.SystemLibrary.quit_editor()
assert unreal.EditorLevelLibrary.load_level(MAP)
unreal.EditorPythonScripting.set_keep_python_script_alive(True)
frames=0
def tick(dt):
 global frames
 frames+=1
 if frames<90:return
 unreal.unregister_slate_post_tick_callback(handle);work()
handle=unreal.register_slate_post_tick_callback(tick)
]====]
