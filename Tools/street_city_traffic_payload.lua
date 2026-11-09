return [====[
TP='/Game/UniversityCity/TrafficV1/Repair2'

def traffic_inventory():
 plan=read('plan');assert plan['map_sha256']==LOAD_SHA
 world=unreal.EditorLevelLibrary.get_editor_world();actors=SUB.get_all_level_actors();rows=[]
 for a in actors:
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   if any(s in a.get_actor_label().lower() for s in ['traffic','crosswalk','lane_dash','curb','tactile','drain']):
    q=dict(actor=a.get_actor_label(),component=c.get_name(),mesh=c.static_mesh.get_path_name(),visible=c.get_editor_property('visible'),hidden=c.get_editor_property('hidden_in_game'),actor_hidden=a.get_editor_property('hidden'),transform=actor_xform(a))
    if isinstance(c,unreal.InstancedStaticMeshComponent):q['instances']=[dict(location=num(c.get_instance_transform(i,True).translation),rotation=str(c.get_instance_transform(i,True).rotation)) for i in range(c.get_instance_count())]
    rows.append(q)
 probes=[]
 for j in plan['junctions']:
  points=[('center',j['center_cm'])]
  for i,a in enumerate(j['arms']):
   d=a['direction'];dist=j['radius_cm']+500;points.append(('arm%d'%i,[j['center_cm'][k]+d[k]*dist for k in range(2)]))
  for label,p in points:
   hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*p,1350),unreal.Vector(*p,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple()
   probes.append(dict(junction=j['id'],point=label,xy=p,hit=hit[0],position=num(hit[4]) if hit[0] else None,support=hit[9].get_actor_label() if hit[0] else None))
 write('native-inventory',dict(status='passed',map_sha256=LOAD_SHA,components=rows,junction_probes=probes,baseline=ground_snapshot()))
 write('flat_inventory',dict(status='passed',map_sha256=LOAD_SHA,traffic_components=len(rows),road_probes=len(probes)))

def traffic_export():
 folder=OUT/'surface-current';folder.mkdir(exist_ok=True);result=json.loads(unreal.CityDepthAuditLibrary.export_scene(unreal.EditorLevelLibrary.get_editor_world(),str(folder),False));assert result['status']=='passed',result
 write('surface-current-receipt',dict(status='passed',map_sha256=LOAD_SHA,result=result));write('flat_finalize',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_material(name,q):
 path=TP+'/Materials/M_'+name
 assert not EAL.does_asset_exist(path),path
 m=ATS.create_asset('M_'+name,TP+'/Materials',unreal.Material,unreal.MaterialFactoryNew());assert m
 def scalar(v):
  n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);n.set_editor_property('r',v);return n
 c=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);c.set_editor_property('constant',unreal.LinearColor(*q['color'],1));MEL.connect_material_property(c,'',unreal.MaterialProperty.MP_BASE_COLOR)
 MEL.connect_material_property(scalar(q.get('rough',.65)),'',unreal.MaterialProperty.MP_ROUGHNESS);MEL.connect_material_property(scalar(q.get('metal',0)),'',unreal.MaterialProperty.MP_METALLIC)
 if 'signal_axis' in q:
  dim=MEL.create_material_expression(m,unreal.MaterialExpressionMultiply);dim.set_editor_property('const_b',.015);MEL.connect_material_expressions(c,'',dim,'A');MEL.connect_material_property(dim,'',unreal.MaterialProperty.MP_BASE_COLOR)
  axis=q['signal_axis'];color=q['signal_color'];start,end=(0,26) if axis==0 else (32,58)
  active=('p>=64&&p<76' if color=='green' else 'p<64||p>=76') if axis==2 else ('p>=%d&&p<%d'%(start,end) if color=='green' else 'p>=%d&&p<%d'%(end,end+4) if color=='amber' else 'p<%d||p>=%d'%(start,end+4))
  tm=MEL.create_material_expression(m,unreal.MaterialExpressionTime);fn=MEL.create_material_expression(m,unreal.MaterialExpressionCustom);inp=unreal.CustomInput();inp.set_editor_property('input_name','T');fn.set_editor_property('inputs',[inp]);fn.set_editor_property('code','float p=fmod(T,80.0); return ('+active+') ? 7.0 : 0.0;');fn.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT1);MEL.connect_material_expressions(tm,'',fn,'T');mul=MEL.create_material_expression(m,unreal.MaterialExpressionMultiply);MEL.connect_material_expressions(c,'',mul,'A');MEL.connect_material_expressions(fn,'',mul,'B');MEL.connect_material_property(mul,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def traffic_sign_material(kind):
 task=unreal.AssetImportTask();task.filename=str(OUT/(kind+'.png'));task.destination_path=TP+'/Textures';task.destination_name='T_'+kind;task.automated=True;task.replace_existing=False;task.save=True;ATS.import_asset_tasks([task]);texture=EAL.load_asset(TP+'/Textures/T_'+kind);assert texture;m=ATS.create_asset('M_Sign_'+kind,TP+'/Materials',unreal.Material,unreal.MaterialFactoryNew());assert m
 sample=MEL.create_material_expression(m,unreal.MaterialExpressionTextureSample);sample.set_editor_property('texture',texture);uv=MEL.create_material_expression(m,unreal.MaterialExpressionTextureCoordinate);rot=MEL.create_material_expression(m,unreal.MaterialExpressionCustom);inp=unreal.CustomInput();inp.set_editor_property('input_name','T');rot.set_editor_property('inputs',[inp]);rot.set_editor_property('code','return float2(T.y,1-T.x);');rot.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT2);MEL.connect_material_expressions(uv,'',rot,'T');MEL.connect_material_expressions(rot,'',sample,'UVs');MEL.connect_material_property(sample,'RGB',unreal.MaterialProperty.MP_BASE_COLOR)
 if kind=='speed30':m.set_editor_property('blend_mode',unreal.BlendMode.BLEND_MASKED);MEL.connect_material_property(sample,'A',unreal.MaterialProperty.MP_OPACITY_MASK)
 MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def traffic_install():
 global LOAD_SHA
 traffic_inventory();plan=read('plan');layout=read('layout');inventory=read('native-inventory');assert LOAD_SHA==plan['map_sha256']==layout['map_sha256']==inventory['map_sha256'];assert ground_snapshot()==inventory['baseline'];assert not (OUT/'install.json').exists()
 shutil.copy2(MAPFILE,OUT/('UniversityCity-before-traffic-'+LOAD_SHA[:16]+'.umap'));world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 road=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'road-grade-plan.json')));write('native-road-grade',road);assert road['status']=='passed',road
 # The superseded prototype markings and three-colour blocks are retained but hidden.
 hidden=[]
 for q in plan['legacy_marking_components']:
  a=actors[q['actor']];a.modify();a.set_actor_hidden_in_game(True)
  for c in a.get_components_by_class(unreal.StaticMeshComponent):c.set_visibility(False,True);c.set_hidden_in_game(True);c.set_collision_profile_name('NoCollision')
  hidden.append(q['actor'])
 mats={k:traffic_material(k,q) for k,q in layout['materials'].items()};bp=EAL.load_asset('/Game/UniversityCity/StreetScenery/BP_StreetCluster');assert bp
 def group(name,mesh,material,instances,collision=False):
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,mesh,material,'FlatCampus_Traffic_'+name);assert c;a=c.get_owner();a.set_actor_label('Traffic_'+name);a.tags=[unreal.Name('TrafficV1')];a.set_folder_path('UniversityCity/TrafficV1');c.set_mobility(unreal.ComponentMobility.STATIC);c.set_collision_profile_name('BlockAll' if collision else 'NoCollision');c.set_cull_distances(0,0);c.clear_instances()
  transforms=[unreal.Transform(location=unreal.Vector(*r['center']),rotation=unreal.Rotator(pitch=r.get('pitch',0),yaw=r.get('yaw',0),roll=0),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in instances];c.add_instances(transforms,False,False,False);assert c.get_instance_count()==len(instances);return a,c
 placed=[]
 for key,q in layout['groups'].items():
  a,c=group(key,EAL.load_asset('/Engine/BasicShapes/'+q['mesh']),mats[q['material']],q['instances'],q['collision']);placed.append(dict(actor=a.get_actor_label(),instances=c.get_instance_count(),material=mats[q['material']].get_path_name()))
 signmats={k:traffic_sign_material(k) for k in ['speed30','pedestrian']};poles=[];backs=[]
 for i,q in enumerate(layout['signs']):
  x,y,z=q['center'];d=q['face'];yaw=math.degrees(math.atan2(d[1],d[0]));poles.append(dict(center=[x,y,1345],size=[6,6,290]));backs.append(dict(center=[x,y,z],size=[60,60,2],yaw=yaw,pitch=90));a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x+d[0]*2,y+d[1]*2,z),unreal.Rotator(pitch=90,yaw=yaw+180,roll=0));a.set_actor_label('Traffic_Sign_%03d'%i);a.tags=[unreal.Name('TrafficV1')];a.set_folder_path('UniversityCity/TrafficV1');c=a.static_mesh_component;c.set_static_mesh(EAL.load_asset('/Engine/BasicShapes/Plane'));c.set_material(0,signmats[q['kind']]);c.set_collision_profile_name('NoCollision');a.set_actor_scale3d(unreal.Vector(.6,.6,1))
 group('SignPoles',EAL.load_asset('/Engine/BasicShapes/Cylinder'),mats['Metal'],poles,True);group('SignBacks',EAL.load_asset('/Engine/BasicShapes/Cylinder'),mats['Black'],backs)
 controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);write('install',dict(status='saved_requires_reopen_audit',before_map_sha256=LOAD_SHA,map_sha256=newsha,road_meshes=road['meshes'],hidden_prototypes=hidden,groups=placed,crossings=len(layout['crossings']),vehicle_heads=len(layout['signals']),signs=len(layout['signs']),cycle_seconds=80));write('preservation',dict(before=inventory['baseline'],after=ground_snapshot()))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';receipt.write_text(json.dumps(dict(status='saved',operation='realistic_traffic_and_road_grade',parent_map_sha256=LOAD_SHA,map_sha256=newsha),indent=2),'utf8');LOAD_SHA=newsha
 assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);traffic_audit();write('flat_install',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_audit():
 installed=read('install');assert LOAD_SHA==installed['map_sha256'];actual=ground_snapshot();assert actual==read('preservation')['after'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();probes=[]
 previous={(r['actor'],r['component']):r for r in read('preservation')['before']};now={(r['actor'],r['component']):r for r in actual}
 for key,old in previous.items():assert now[key]['materials']==old['materials'],('unrelated material changed',key)
 for q in read('layout')['crossings']:
  x,y=q['center_cm'];h=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1230),unreal.Vector(x,y,1180),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();probes.append(dict(id=q['id'],hit=h[0],ground=num(h[4]) if h[0] else None,support=h[9].get_actor_label() if h[0] else None));assert h[0] and 1197<=h[4].z<=1220,(q,h)
 for label in installed['hidden_prototypes']:assert actors[label].get_editor_property('hidden')
 campus=json.loads((ROOT/'output/street-social-city-production/flat-campus-v1/install.json').read_text('utf8'));gates=[];thresholds=[]
 for q in campus['enclosure']['gates']:
  x,y=q['center'];angle=math.radians(q['yaw']);dx,dy=math.cos(angle),math.sin(angle);sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x+dx*600,y+dy*600,1300),unreal.Vector(x-dx*600,y-dy*600,1300),35.,88.));assert not sweep['blocked'],q['id'];gates.append(dict(id=q['id'],**sweep))
 foundation=json.loads((ROOT/'output/street-social-city-production/world-ground-v1/campus-foundations.json').read_text('utf8'))
 for b in foundation['buildings']:
  if b['id'] not in ['E1','EE','MA','T4','T2','IB','T1','RB','AD','LI','SC','IN','SP','D1','D2','D3','D4']:continue
  cx,cy,z=b['world_position_m']
  for e in b['entrances']:
   dx,dy={'W':(-1,0),'E':(1,0),'S':(0,-1),'N':(0,1)}[e['facade_side']]
   for distance in [.25,1.,3.4]:
    ex,ey,_=e['position_m'];east=(cx+ex+dx*distance)*100;north=(cy+ey+dy*distance)*100;hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(north,east,1390),unreal.Vector(north,east,900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert hit[0] and 1160<=hit[4].z<=1220,(b['id'],e['id']);thresholds.append(dict(building=b['id'],entry=e['id'],ground=num(hit[4])))
 shader=[]
 for name in read('layout')['materials']:
  m=EAL.load_asset(TP+'/Materials/M_'+name);assert m;diag=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(m));assert not diag.get('graph_error'),(name,diag);shader.append(name)
 write('campus-audit',dict(status='passed',map_sha256=LOAD_SHA,gates=gates,thresholds=thresholds,material_compile_checks=shader))
 bridge_probes=[];bridge_sweeps=[]
 for q in read('bridge-plan')['bridges']:
  x,y=q['center_cm'];dx,dy=q['direction'];nx,ny=-dy,dx
  for side in [0,-1,1]:
   px=x+nx*side*(q['carriageway_cm']/2+110);py=y+ny*side*(q['carriageway_cm']/2+110);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(px,py,1230),unreal.Vector(px,py,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);assert raw is not None,(q['id'],side);h=raw.to_tuple();assert h[0] and abs(h[4].z-(1204 if side==0 else 1205.5))<.1,(q['id'],side,h);bridge_probes.append(dict(bridge=q['id'],side=side,ground=num(h[4])))
   if side:
    length=q['span_cm']/2-150;sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(px-dx*length,py-dy*length,1303.5),unreal.Vector(px+dx*length,py+dy*length,1303.5),35.,88.));assert not sweep['blocked'],(q['id'],side,sweep);bridge_sweeps.append(dict(bridge=q['id'],side=side,**sweep))
 write('bridge-audit',dict(status='passed',map_sha256=LOAD_SHA,ground_probes=bridge_probes,walkway_sweeps=bridge_sweeps,minimum_walkway_width_cm=226))
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,road_probes=probes,crossings=installed['crossings'],vehicle_heads=installed['vehicle_heads'],signs=installed['signs'],preservation_snapshot_matches=True,material_bindings_preserved=True,scope='Saved/reopened geometry, signal material bindings and sampled road support; actual rendering and material phase checks remain required'))
 write('flat_audit',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_repair():
 global LOAD_SHA
 installed=read('install');assert installed['map_sha256']==LOAD_SHA==read('road-final-plan')['map_sha256'];assert ground_snapshot()==read('preservation')['after'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};traffic=[a for a in actors.values() if 'TrafficV1' in [str(t) for t in a.tags]]
 result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'road-final-plan.json')));assert result['status']=='passed',result;write('native-road-final',result)
 bridge=read('bridge-plan');bridge_groups=[]
 for name,parts in bridge['groups'].items():
  mat=EAL.load_asset(bridge['materials'][name]);assert mat,bridge['materials'][name];c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),mat,'FlatCampus_Traffic_Bridge_'+name);assert c;a=c.get_owner();a.set_actor_label('Traffic_Bridge_'+name);a.tags=[unreal.Name('TrafficV1')];a.set_folder_path('UniversityCity/TrafficV1');c.set_mobility(unreal.ComponentMobility.STATIC);c.set_collision_profile_name('BlockAll')
  for r in parts:c.add_instance(unreal.Transform(location=unreal.Vector(*r['center']),rotation=unreal.Rotator(yaw=r['yaw']),scale=unreal.Vector(*[v/100 for v in r['size']])),True)
  assert c.get_instance_count()==len(parts);bridge_groups.append(dict(actor=a.get_actor_label(),instances=len(parts)))
 geometry_support=read('geometry-support')['heights'];support_stats=dict(native_down=0,native_up=0,geometry_fallback=0)
 def height(x,y):
  zs=[]
  for start,end,key in [(1350,1100,'native_down'),(1100,1350,'native_up')]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,start),unreal.Vector(x,y,end),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,traffic,unreal.DrawDebugTrace.NONE,True)
   if raw is not None:
    h=raw.to_tuple()
    if h[0]:zs.append(h[4].z);support_stats[key]+=1
  fallback=geometry_support.get('%d,%d'%(round(x),round(y)))
  if fallback is not None:zs.append(fallback);support_stats['geometry_fallback']+=1
  assert zs,('no supported placement',x,y);return max(zs)
 repaired=[]
 for name in ['White_Cube','Yellow_Cube','Tactile_Cube','Tactile_Cylinder']:
  a=actors['Traffic_'+name];a.modify();c=a.get_component_by_class(unreal.InstancedStaticMeshComponent);deltas=[]
  if name in ['White_Cube','Yellow_Cube']:c.set_cast_shadow(False)
  for i in range(c.get_instance_count()):
   t=c.get_instance_transform(i,True);p=t.translation;z=height(p.x,p.y);half=t.scale3d.z*50;offset=.3 if name!='Tactile_Cylinder' else 1.5;newz=z+half+offset;deltas.append(newz-p.z);t.translation=unreal.Vector(p.x,p.y,newz);assert c.update_instance_transform(i,t,True,False,True)
  c.mark_render_state_dirty() if hasattr(c,'mark_render_state_dirty') else None;repaired.append(dict(actor=a.get_actor_label(),count=len(deltas),min_delta_cm=min(deltas),max_delta_cm=max(deltas),ground_clearance_cm=.3 if name!='Tactile_Cylinder' else 1.5))
 # Bury finite pole foundations rather than leaving their bottom above grass.
 concrete=actors['Traffic_Concrete_Cylinder'].get_component_by_class(unreal.InstancedStaticMeshComponent)
 for i in range(concrete.get_instance_count()):
  t=concrete.get_instance_transform(i,True);p=t.translation;g=height(p.x,p.y);t.translation=unreal.Vector(p.x,p.y,g+5);t.scale3d=unreal.Vector(t.scale3d.x,t.scale3d.y,.3);assert concrete.update_instance_transform(i,t,True,False,True)
 extra=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cylinder'),EAL.load_asset(TP+'/Materials/M_Concrete'),'FlatCampus_Traffic_PoleFeet');assert extra;extra.get_owner().set_actor_label('Traffic_PoleFeet');extra.get_owner().tags=[unreal.Name('TrafficV1')];extra.get_owner().set_folder_path('UniversityCity/TrafficV1');extra.set_collision_profile_name('BlockAll')
 for label in ['Traffic_Metal_Cylinder','Traffic_SignPoles']:
  c=actors[label].get_component_by_class(unreal.InstancedStaticMeshComponent)
  for i in range(c.get_instance_count()):
   t=c.get_instance_transform(i,True)
   if label.endswith('Cylinder') and abs(t.scale3d.z-2.64)>.01:continue
   p=t.translation;g=height(p.x,p.y);extra.add_instance(unreal.Transform(location=unreal.Vector(p.x,p.y,g+1),scale=unreal.Vector(.30,.30,.20)),True)
 controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,final_road_meshes=result['meshes'],bridges=bridge['bridges'],bridge_groups=bridge_groups);write('install',installed);pres=read('preservation');pres['after']=ground_snapshot();write('preservation',pres);write('paint-repair',dict(status='saved_requires_visual_review',map_sha256=newsha,groups=repaired,support_stats=support_stats,reason='Sample actual saved surface for each paint/tactile instance, retaining depth clearance.'))
 (ROOT/'output/street-social-city-production/day-night-v1/current-map.json').write_text(json.dumps(dict(status='saved',operation='native_sampled_traffic_paint_and_road_grade',parent_map_sha256=LOAD_SHA,map_sha256=newsha),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);traffic_audit();write('flat_name_polish',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_bridge_lights():
 global LOAD_SHA
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert ground_snapshot()==read('preservation')['after'];world=unreal.EditorLevelLibrary.get_editor_world();assert not any(a.get_actor_label().startswith('Traffic_BridgeLamp') for a in SUB.get_all_level_actors());parts={'Metal':[],'Opal':[]};lights=[]
 for b in read('bridge-plan')['bridges']:
  cx,cy=b['center_cm'];dx,dy=b['direction'];nx,ny=-dy,dx;count=max(2,math.ceil(b['span_cm']/1100))
  for side in [-1,1]:
   for i in range(count+1):
    along=-b['span_cm']/2+i*b['span_cm']/count;x=cx+dx*along+nx*side*(b['carriageway_cm']/2+230);y=cy+dy*along+ny*side*(b['carriageway_cm']/2+230)
    parts['Metal']+=[dict(center=[x,y,1345],size=[7,7,80]),dict(center=[x,y,1405],size=[24,24,5])];parts['Opal'].append(dict(center=[x,y,1393],size=[17,17,18]))
    a=SUB.spawn_actor_from_class(unreal.SpotLight,unreal.Vector(x,y,1380),unreal.Rotator(pitch=-90));a.set_actor_label('Traffic_BridgeLamp_Light_%03d'%len(lights));a.tags=[unreal.Name('TrafficV1'),unreal.Name('EnvGroup=Path'),unreal.Name('EnvLumens=140')];a.set_folder_path('UniversityCity/TrafficV1');c=a.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(140);c.set_temperature(2800);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',650);c.set_editor_property('inner_cone_angle',55);c.set_editor_property('outer_cone_angle',80);c.set_editor_property('source_radius',12);c.set_cast_shadows(False);lights.append(a.get_actor_label())
 for kind,rows in parts.items():
  mat=EAL.load_asset(TP+'/Materials/M_Metal') if kind=='Metal' else EAL.load_asset('/Game/UniversityCity/EnvironmentV1/Materials/M_EnvironmentOpal_01');assert mat;c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cylinder'),mat,'FlatCampus_Traffic_BridgeLamp_'+kind);assert c;c.get_owner().set_actor_label('Traffic_BridgeLamp_'+kind);c.get_owner().tags=[unreal.Name('TrafficV1')];c.get_owner().set_folder_path('UniversityCity/TrafficV1');c.set_collision_profile_name('NoCollision')
  for r in rows:c.add_instance(unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])),True)
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,lighting_parent_map_sha256=LOAD_SHA,bridge_lights=len(lights));write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);r=read('paint-repair');r['map_sha256']=newsha;write('paint-repair',r);write('bridge-lights',dict(status='saved_requires_visual_review',map_sha256=newsha,lights=lights,lumens_each=140,temperature_kelvin=2800,schedule='EnvGroup=Path; existing day/night controller and LampGlowWeight collection',shadows=False))
 (ROOT/'output/street-social-city-production/day-night-v1/current-map.json').write_text(json.dumps(dict(status='saved',operation='resort_bridge_lanterns',parent_map_sha256=LOAD_SHA,map_sha256=newsha),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);traffic_audit();write('flat_rebuild_enclosure',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_lane_polish():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256'];assert ground_snapshot()==read('preservation')['after'];assert not installed.get('lane_detail_parts');world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};bridges=read('bridge-plan')['bridges'];relocations=[]
 # The river clips the west carriageway edge of path-012 for 42m. Rebuild its
 # nominal road width with a finite retaining slab, wall and riverside barrier.
 bank={'Deck':[],'Wall':[],'Rail':[]};bank['Deck'].append(dict(center=[86200,78500,1179],size=[5000,1540,50]));bank['Wall'].append(dict(center=[86200,77725,1074],size=[5000,30,248]));bank['Rail']+=[dict(center=[86200,77735,1308],size=[5000,8,8]),dict(center=[86200,77735,1250],size=[5000,5,5])]
 for i in range(29):bank['Rail'].append(dict(center=[83700+i*5000/28,77735,1254],size=[8,8,100]))
 bankmats={'Deck':'/Game/UniversityCity/GroundPBRV2/Materials/MI_Detail_932bc009ac742438e2bf','Wall':'/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_TwoSided','Rail':TP+'/Materials/M_Metal'}
 for kind,parts in bank.items():
  mat=EAL.load_asset(bankmats[kind]);assert mat;c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),mat,'FlatCampus_Traffic_Riverbank_'+kind);assert c;c.get_owner().set_actor_label('Traffic_Riverbank_'+kind);c.get_owner().tags=[unreal.Name('TrafficV1')];c.get_owner().set_folder_path('UniversityCity/TrafficV1');c.set_collision_profile_name('BlockAll')
  for r in parts:c.add_instance(unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])),True)
 def native_height(x,y,ignore=[]):
  zs=[]
  for start,end in [(1350,1100),(1100,1350)]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,start),unreal.Vector(x,y,end),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignore,unreal.DrawDebugTrace.NONE,True)
   if raw is not None:
    h=raw.to_tuple()
    if h[0]:zs.append(h[4].z)
  return max(zs) if zs else None
 for q in bridges:
  x,y=q['center_cm'];dx,dy=q['direction'];nx,ny=-dy,dx;length=q['span_cm']/2-150
  for side in [-1,1]:
   px=x+nx*side*(q['carriageway_cm']/2+110);py=y+ny*side*(q['carriageway_cm']/2+110)
   for attempt in range(12):
    sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(px-dx*length,py-dy*length,1303.5),unreal.Vector(px+dx*length,py+dy*length,1303.5),35.,88.))
    if not sweep['blocked']:break
    label=sweep['actor'];assert label.startswith(('Street_recycling_','Street_bench_','Street_bollard_','Street_cycle_rack_','Street_utility_box_')),('Unexpected bridge obstruction',q['id'],side,sweep);a=actors[label];cs=a.get_components_by_class(unreal.InstancedStaticMeshComponent);assert len(cs)==1,label;c=cs[0];point=sweep['point'];idx=min(range(c.get_instance_count()),key=lambda i:math.dist(num(c.get_instance_transform(i,True).translation)[:2],point[:2]));t=c.get_instance_transform(idx,True);old=num(t.translation);end=-1 if (old[0]-x)*dx+(old[1]-y)*dy<0 else 1;destination=None
    for beyond in [800,1200,1800]:
     for away in [450,750,1100]:
      xx=x+dx*end*(q['span_cm']/2+beyond)+nx*side*(q['carriageway_cm']/2+away);yy=y+dy*end*(q['span_cm']/2+beyond)+ny*side*(q['carriageway_cm']/2+away);z=native_height(xx,yy,[a])
      if z is None or not 1180<=z<=1220:continue
      clearance=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(xx,yy,z+110),unreal.Vector(xx+1,yy,z+110),95.,105.))
      if not clearance['blocked']:destination=[xx,yy,z+.2];break
     if destination:break
    assert destination,('No clear dry-bank position',label,idx);a.modify();t.translation=unreal.Vector(*destination);assert c.update_instance_transform(idx,t,True,True,True);relocations.append(dict(actor=label,instance=idx,before_cm=old,after_cm=destination,reason='Clear bridge sidewalk and retain street furniture on dry bank'))
   else:raise RuntimeError('Bridge clearance repair limit reached')
 detail=read('lane-detail-plan');fallback=read('geometry-support')['heights'];ignore=[a for a in SUB.get_all_level_actors() if a.get_actor_label().startswith('Traffic_') and not a.get_actor_label().startswith(('Traffic_Bridge_','Traffic_Riverbank_'))];white=EAL.load_asset(TP+'/Materials/M_White');c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),white,'FlatCampus_Traffic_LaneDetail');assert c;c.get_owner().set_actor_label('Traffic_LaneDetail');c.get_owner().tags=[unreal.Name('TrafficV1')];c.get_owner().set_folder_path('UniversityCity/TrafficV1');c.set_collision_profile_name('NoCollision');c.set_cast_shadow(False)
 omitted=[]
 for index,r in enumerate(detail['parts']):
  x,y,_=r['center'];z=native_height(x,y,ignore);f=fallback.get('%d,%d'%(round(x),round(y)));values=[v for v in [z,f] if v is not None];z=max(values) if values else None
  if z is None or not 1203.5<=z<=1210:
   omitted.append(dict(index=index,kind=r['kind'],xy=[x,y],surface_cm=z,reason='No exposed carriageway here: water/grass or an existing raised facility; do not paint over it.'));continue
  c.add_instance(unreal.Transform(location=unreal.Vector(x,y,z+.4),rotation=unreal.Rotator(yaw=r['yaw']),scale=unreal.Vector(*[v/100 for v in r['size']])),True)
 assert c.get_instance_count()+len(omitted)==len(detail['parts']);write('lane-omissions',dict(status='review_required',before_map_sha256=LOAD_SHA,planned=len(detail['parts']),placed=c.get_instance_count(),omitted=omitted));controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,lane_detail_parts=c.get_instance_count(),lane_detail_planned=len(detail['parts']),lane_detail_omitted=len(omitted),lane_detail_counts=detail['counts']);write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p);write('furniture-relocations',dict(status='saved_requires_reopen_audit',map_sha256=newsha,changes=relocations));r=read('paint-repair');r['map_sha256']=newsha;write('paint-repair',r);r=read('bridge-lights');r['map_sha256']=newsha;write('bridge-lights',r)
 (ROOT/'output/street-social-city-production/day-night-v1/current-map.json').write_text(json.dumps(dict(status='saved',operation='lane_details_and_bridge_access_clearance',parent_map_sha256=LOAD_SHA,map_sha256=newsha),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);traffic_audit();write('flat_site_polish',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_materials_finish():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256'];assert ground_snapshot()==read('preservation')['after'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};roots={}
 for a in actors.values():
  if 'TrafficV1' not in [str(t) for t in a.tags]:continue
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   for i in range(c.get_num_materials()):
    mi=c.get_material(i)
    if mi:
     chain,m=material_chain(mi)
     if m:roots[m.get_path_name()]=m
 rows=[]
 for path,m in sorted(roots.items()):
  source=ROOT/'StreetSocialCity/Content'/(path.split('.')[0].removeprefix('/Game/')+'.uasset');before=sha(source);m.modify();MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);assert m.get_editor_property('used_with_instanced_static_meshes'),path;MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);rows.append(dict(material=path,instanced_usage=True,source_file=str(source),before_sha256=before,sha256=sha(source)))
 # A finite hanger connects each housing to its mast arm.
 original=actors['Traffic_Black_Cube'].get_component_by_class(unreal.InstancedStaticMeshComponent);mounts=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),EAL.load_asset(TP+'/Materials/M_Metal'),'FlatCampus_Traffic_HeadMounts');assert mounts;mounts.get_owner().set_actor_label('Traffic_HeadMounts');mounts.get_owner().tags=[unreal.Name('TrafficV1')];mounts.get_owner().set_folder_path('UniversityCity/TrafficV1');mounts.set_collision_profile_name('NoCollision')
 for i in range(original.get_instance_count()):
  t=original.get_instance_transform(i,True)
  if abs(t.scale3d.z-1.16)>.001:continue
  t.translation=t.translation+unreal.Vector(0,0,63);t.scale3d=unreal.Vector(.16,.16,.22);mounts.add_instance(t,True)
 assert mounts.get_instance_count()==50
 controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(map_sha256=newsha,parent_map_sha256=LOAD_SHA,head_mounts=50);write('install',installed);p=read('preservation');p['after']=ground_snapshot();write('preservation',p)
 for name in ['paint-repair','bridge-lights','furniture-relocations','lane-omissions']:
  q=read(name);q['map_sha256']=newsha;write(name,q)
 write('material-usage',dict(status='saved_requires_game_review',map_sha256=newsha,materials=rows,head_mounts=50,reason='Persist InstancedStaticMeshes usage before cook; do not rely on editor automatic usage.'))
 (ROOT/'output/street-social-city-production/day-night-v1/current-map.json').write_text(json.dumps(dict(status='saved',operation='persist_instanced_material_usage_and_signal_mounts',parent_map_sha256=LOAD_SHA,map_sha256=newsha),indent=2),'utf8');LOAD_SHA=newsha;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);traffic_audit();write('flat_site_grade',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_sign_finish():
 assert LOAD_SHA==read('install')['map_sha256'];usage=read('material-usage');rows=[]
 for kind in ['speed30','pedestrian']:
  m=EAL.load_asset(TP+'/Materials/M_Sign_'+kind);assert m;sample=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_BASE_COLOR);custom=[n for n in MEL.get_inputs_for_material_expression(m,sample) if isinstance(n,unreal.MaterialExpressionCustom)];assert len(custom)==1;m.modify();custom[0].set_editor_property('code','return float2(T.y,1-T.x);');MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);assert m.get_editor_property('used_with_instanced_static_meshes');MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);path=m.get_path_name();source=ROOT/'StreetSocialCity/Content'/(path.split('.')[0].removeprefix('/Game/')+'.uasset');row=dict(material=path,instanced_usage=True,source_file=str(source),sha256=sha(source));usage['materials']=[r for r in usage['materials'] if r['material']!=path]+[row];rows.append(dict(material=path,uv_code=custom[0].get_editor_property('code'),sha256=row['sha256']))
 signal_rows=[]
 for name,q in read('layout')['materials'].items():
  if 'signal_axis' not in q:continue
  m=EAL.load_asset(TP+'/Materials/M_'+name);assert m;m.modify();base=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_BASE_COLOR)
  if isinstance(base,unreal.MaterialExpressionConstant3Vector):
   dim=MEL.create_material_expression(m,unreal.MaterialExpressionMultiply);dim.set_editor_property('const_b',.015);MEL.connect_material_expressions(base,'',dim,'A');MEL.connect_material_property(dim,'',unreal.MaterialProperty.MP_BASE_COLOR)
  else:
   assert isinstance(base,unreal.MaterialExpressionMultiply);base.set_editor_property('const_b',.015)
  emit=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_EMISSIVE_COLOR);custom=[n for n in MEL.get_inputs_for_material_expression(m,emit) if isinstance(n,unreal.MaterialExpressionCustom)];assert len(custom)==1;code=custom[0].get_editor_property('code').replace(' : 0.015;',' : 0.0;');assert ' : 0.0;' in code;custom[0].set_editor_property('code',code);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);path=m.get_path_name();source=ROOT/'StreetSocialCity/Content'/(path.split('.')[0].removeprefix('/Game/')+'.uasset');usage['materials']=[r for r in usage['materials'] if r['material']!=path]+[dict(material=path,instanced_usage=True,source_file=str(source),sha256=sha(source))];signal_rows.append(dict(material=path,inactive_base_multiplier=.015,inactive_emission=0,active_emission=7,phase_code=code))
 write('signal-display',dict(status='saved_requires_game_review',map_sha256=LOAD_SHA,materials=signal_rows,reason='Dark unlit glass and zero inactive emission: an inactive coloured lens must not appear illuminated.'))
 # Include existing campus/streetscape HISM roots as well, so the actual Game
 # cannot silently replace a shared legacy material with Default Material.
 roots={}
 for a in SUB.get_all_level_actors():
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   for i in range(c.get_num_materials()):
    mi=c.get_material(i)
    if mi:
     chain,m=material_chain(mi)
     if m and m.get_path_name().startswith('/Game/') and not m.get_editor_property('used_with_instanced_static_meshes'):roots[m.get_path_name()]=m
 for path,m in sorted(roots.items()):
  m.modify();MEL.set_material_usage(m,unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES);assert m.get_editor_property('used_with_instanced_static_meshes');MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);source=ROOT/'StreetSocialCity/Content'/(path.split('.')[0].removeprefix('/Game/')+'.uasset');usage['materials']=[r for r in usage['materials'] if r['material']!=path]+[dict(material=path,instanced_usage=True,source_file=str(source),sha256=sha(source))]
 write('material-usage',usage);write('sign-uv',dict(status='saved_requires_game_review',map_sha256=LOAD_SHA,materials=rows,additional_hism_roots=list(roots),reason='Correct mirrored front-face sign text without changing campus gate typography; persist every missing project HISM usage flag.'));assert sha(MAPFILE)==LOAD_SHA;traffic_audit();write('traffic_sign_finish',dict(status='passed',map_sha256=LOAD_SHA))

def traffic_signal_brightness():
 assert LOAD_SHA==read('install')['map_sha256'];usage=read('material-usage');display=read('signal-display');collection=EAL.load_asset('/Game/UniversityCity/EnvironmentV1/MPC_CityEnvironment');assert collection
 for row in display['materials']:
  m=EAL.load_asset(row['material']);assert m;m.modify();emit=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_EMISSIVE_COLOR);fn=[n for n in MEL.get_inputs_for_material_expression(m,emit) if isinstance(n,unreal.MaterialExpressionCustom)];assert len(fn)==1;fn=fn[0];inputs=[]
  for name in ['T','N']:
   q=unreal.CustomInput();q.set_editor_property('input_name',name);inputs.append(q)
  fn.set_editor_property('inputs',inputs);time=MEL.create_material_expression(m,unreal.MaterialExpressionTime);night=MEL.create_material_expression(m,unreal.MaterialExpressionCollectionParameter);night.set_editor_property('collection',collection);night.set_editor_property('parameter_name','NightWeight');assert MEL.connect_material_expressions(time,'',fn,'T');assert MEL.connect_material_expressions(night,'',fn,'N');code=fn.get_editor_property('code').replace(' ? 7.0 : 0.0;',' ? (7.0+3493.0*pow(1.0-saturate(N),4.0)) : 0.0;');assert '3493.0' in code;fn.set_editor_property('code',code);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);path=m.get_path_name();source=ROOT/'StreetSocialCity/Content'/(path.split('.')[0].removeprefix('/Game/')+'.uasset');usage['materials']=[r for r in usage['materials'] if r['material']!=path]+[dict(material=path,instanced_usage=True,source_file=str(source),sha256=sha(source))];row.update(active_emission_day=3500,active_emission_night=7,phase_code=code);row.pop('active_emission',None)
 display.update(status='saved_requires_game_review',brightness='7 + 3493 * (1-NightWeight)^4; strong daylight legibility, original low night intensity, zero inactive emission');write('signal-display',display);write('material-usage',usage);assert sha(MAPFILE)==LOAD_SHA;traffic_audit();write('traffic_signal_brightness',dict(status='passed',map_sha256=LOAD_SHA))

def work():
 try:
  if MODE=='flat_inventory':traffic_inventory()
  elif MODE=='flat_install':traffic_install()
  elif MODE=='flat_audit':traffic_audit()
  elif MODE=='flat_finalize':traffic_export()
  elif MODE=='flat_name_polish':traffic_repair()
  elif MODE=='flat_rebuild_enclosure':traffic_bridge_lights()
  elif MODE=='flat_site_polish':traffic_lane_polish()
  elif MODE=='flat_site_grade':traffic_materials_finish()
  elif MODE=='traffic_sign_finish':traffic_sign_finish()
  elif MODE=='traffic_signal_brightness':traffic_signal_brightness()
  else:raise RuntimeError('Unsupported traffic mode')
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
