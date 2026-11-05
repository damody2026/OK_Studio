return [====[
def immersion_path_separation_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA and not (OUT/'path-separation-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};c=actors['Immersion_CampusPaths'].get_components_by_class(unreal.InstancedStaticMeshComponent)[0];original=[c.get_instance_transform(i,True) for i in range(c.get_instance_count())];assert len(original)==1469
 backup=OUT/('UniversityCity-before-path-separation-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c.modify()
 for i,old in enumerate(original):
  assert abs(old.scale3d.z-.09)<.0001,(i,old.scale3d.z);t=unreal.Transform(location=old.translation+unreal.Vector(0,0,1),rotation=old.rotation.rotator(),scale=unreal.Vector(old.scale3d.x,old.scale3d.y,.11));assert c.update_instance_transform(i,t,True,True,True)
 immersion_route_review();assert read('route-native-review')['status']=='passed'
 start=next(a for a in actors.values() if isinstance(a,unreal.PlayerStart));start.modify();start.set_actor_location(start.get_actor_location()+unreal.Vector(0,0,2),False,False);controller=actors['CityEnvironmentController'];controller.modify();controller.set_editor_property('show_time_controls',False);controller.prepare_for_save();after=ground_snapshot();assert len(after)==len(before)
 for old,now in zip(before,after):
  if old['actor']!='Immersion_CampusPaths':assert old==now,old['actor']
 assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('path-separation-install',dict(status='saved_requires_reopen_and_game_review',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),strips=len(original),bottom_cm=1197,top_cm=1208,time_controls_default=False,player_start=num(start.get_actor_location()),policy='Only immersion path cubes thickened upward2cm. Existing ground materials unchanged. F8 time controls remain available; default gameplay captures walking input.'))

def immersion_mirror_context():
 plan=read('interior-probe-plan');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for b in plan['buildings']:
  base=num(actors['Campus_'+b['building']+'_F01'].get_actor_location())
  for r in b['rooms']:
   if not any(w in r['name'] for w in ['舞蹈','健身','更衣','復健','美髮']):continue
   a=actors['Campus_'+b['building']+'_F%02d'%r['floor']];rows.append(dict(building=b['building'],room=r,base=base,components=[dict(name=c.get_name(),mesh=c.static_mesh.get_path_name() if c.static_mesh else None,materials=[m.get_path_name() if m else None for m in c.get_materials()]) for c in a.get_components_by_class(unreal.StaticMeshComponent)]))
 write('mirror-context',dict(status='read_only',map_sha256=LOAD_SHA,rooms=rows))

def immersion_mirrors_install(extend=False):
 previous=read('mirrors-install') if extend else dict(rooms=[],created=[]);assert extend or not (OUT/'mirrors-install.json').exists();installed=read('install');assert installed['map_sha256']==LOAD_SHA;before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};plans=json.loads((OUT/'mirror-room-plan.json').read_text('utf8'));prepared=[]
 for q in plans:
  r=q['room'];rid=r['room_id'];
  if any(old['id']==rid for old in previous['rooms']):continue
  bid=rid.split('-')[0];base=actors['Campus_'+bid+'_F01'].get_actor_location();shell=next(i['asset'] for i in q['related'] if i['asset']['role']=='room_shell');angle=math.radians(r['rotation_z_deg']);co,si=math.cos(angle),math.sin(angle);cx,cy,z=r['position_m'];width=600 if bid=='SC' else 800;height=210 if bid=='SC' else 220;d=shell['size_m'][1];normal=unreal.Vector(co,-si,0);tangent=unreal.Vector(si,co,0)
  def point(x,y,h):return base+unreal.Vector((cy+si*x+co*y)*100,(cx+co*x-si*y)*100,(z+h)*100)
  face=point(0,-d/2+.25,1.35);hits=[]
  for t in [-width/2+5,0,width/2-5]:
   p=face+tangent*t;raw=unreal.SystemLibrary.line_trace_single(world,p+normal*30,p-normal*50,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and h[9].get_actor_label()=='Campus_'+bid+'_F%02d'%r['floor'],('Mirror requires a real backing wall',rid,t);hits.append(num(h[4]))
  face=unreal.Vector(*hits[1])+normal*3
  clearance=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,face+normal*200-unreal.Vector(0,0,37),face+normal*201-unreal.Vector(0,0,37),35.,88.));assert not clearance['blocked'],('Mirror viewing space blocked',rid,clearance);prepared.append(dict(id=rid,name=r['display_name'],face=num(face),normal=num(normal),tangent=num(tangent),width=width,height=height,yaw=-r['rotation_z_deg'],backing_hits=hits,clearance=clearance,eye=num(face+normal*300+unreal.Vector(0,0,30))))
 backup=OUT/('UniversityCity-before-mirrors-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);tools=unreal.AssetToolsHelpers.get_asset_tools();mel=unreal.MaterialEditingLibrary;folder=IMM+'/Mirrors';mat=EAL.load_asset(folder+'/M_SilverMirror') if extend else tools.create_asset('M_SilverMirror',folder,unreal.Material,unreal.MaterialFactoryNew());assert mat;mel.delete_all_material_expressions(mat)
 for prop,value in [(unreal.MaterialProperty.MP_METALLIC,1.),(unreal.MaterialProperty.MP_ROUGHNESS,.015),(unreal.MaterialProperty.MP_SPECULAR,.5)]:
  n=mel.create_material_expression(mat,unreal.MaterialExpressionConstant);n.set_editor_property('r',value);assert mel.connect_material_property(n,'',prop)
 n=mel.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(.92,.94,.95,1));assert mel.connect_material_property(n,'',unreal.MaterialProperty.MP_BASE_COLOR);mat.set_editor_property('used_with_instanced_static_meshes',True);mel.recompile_material(mat);assert EAL.save_loaded_asset(mat,False);cube=EAL.load_asset('/Engine/BasicShapes/Cube');frame_mat=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');created=[]
 for q in prepared:
  face=unreal.Vector(*q['face']);normal=unreal.Vector(*q['normal']);tangent=unreal.Vector(*q['tangent']);w,h=q['width'],q['height']
  for suffix,p,size,material in [('Glass',face,[2,w,h],mat),('Backing',face-normal*2,[2,w+6,h+6],frame_mat)]:
   a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,p,unreal.Rotator(0,q['yaw'],0));a.set_actor_label('Immersion_Mirror_'+q['id']+'_'+suffix);a.set_folder_path('UniversityCity/ImmersionV1/Mirrors');a.tags=[unreal.Name('ImmersionV1')];c=a.static_mesh_component;c.set_static_mesh(cube);c.set_material(0,material);c.set_collision_profile_name('BlockAll');a.set_actor_scale3d(unreal.Vector(*[v/100 for v in size]));created.append(a.get_actor_label())
  a=SUB.spawn_actor_from_class(unreal.PlanarReflection,face+normal*1.1,unreal.MathLibrary.make_rotation_from_axes(tangent,unreal.Vector(0,0,1),normal));a.set_actor_label('Immersion_Mirror_'+q['id']+'_Reflection');a.tags=[unreal.Name('ImmersionV1'),unreal.Name('ImmersionLargeMirror')];a.set_folder_path('UniversityCity/ImmersionV1/Mirrors');a.set_actor_scale3d(unreal.Vector(w/100,h/100,1));c=a.get_components_by_class(unreal.PlanarReflectionComponent)[0];c.set_editor_property('screen_percentage',50);c.set_editor_property('normal_distortion_strength',0.);c.set_editor_property('prefilter_roughness',.01);c.set_editor_property('distance_from_plane_fadeout_start',5.);c.set_editor_property('distance_from_plane_fadeout_end',15.);c.set_editor_property('show_preview_plane',False);c.set_editor_property('max_view_distance_override',18000.);created.append(a.get_actor_label())
 after=ground_snapshot();assert [q for q in after if q['actor'] not in created]==before;controller=actors['CityEnvironmentController'];controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('mirrors-install',dict(status='saved_requires_reopen_and_reflection_render_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),rooms=previous['rooms']+prepared,created=previous['created']+created,flush_mounts=True,material=mat.get_path_name(),policy='Large backed wall mirrors in suitable dance,fitness,rehabilitation,yoga and training rooms, outside door apertures; retained all existing interior functions. Planar reflections require global clip plane support in final renderer configuration and actual rendered validation.'))

def immersion_mirrors_extend():
 immersion_mirrors_install(True)
 for a in SUB.get_all_level_actors():
  if isinstance(a,unreal.PlanarReflection) and a.get_actor_label().startswith('Immersion_Mirror_'):a.modify();a.tags=[unreal.Name('ImmersionV1'),unreal.Name('ImmersionLargeMirror')]
 assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');installed['map_sha256']=newsha;write('install',installed);receipt=read('mirrors-install');receipt['map_sha256']=newsha;write('mirrors-install',receipt);state=read('preservation-after');state['map_sha256']=newsha;write('preservation-after',state)

def immersion_mirror_mounts():
 receipt=read('mirrors-install');assert receipt['map_sha256']==LOAD_SHA and not receipt.get('flush_mounts');before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-mirror-mounts-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for q in receipt['rooms']:
  n=unreal.Vector(*q['normal']);old=unreal.Vector(*q['face']);new=unreal.Vector(*q['backing_hits'][1])+n*3;delta=new-old
  for suffix in ['Glass','Backing','Reflection']:
   a=actors['Immersion_Mirror_'+q['id']+'_'+suffix];a.modify();a.set_actor_location(a.get_actor_location()+delta,False,False)
  q['face']=num(new);q['eye']=num(unreal.Vector(*q['eye'])+delta)
 after=ground_snapshot();assert [q for q in after if not q['actor'].startswith('Immersion_Mirror_')]==[q for q in before if not q['actor'].startswith('Immersion_Mirror_')];actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));receipt.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,flush_mounts=True,mount_backup=str(backup));write('mirrors-install',receipt)

def immersion_connection_restore():
 plan=read('connection-restore-plan');assert plan['map_sha256']==LOAD_SHA and len(plan['meshes'])==1 and not (OUT/'connection-restore-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];row=plan['meshes'][0];assert row['key']=='Outdoor_connection::StaticMeshComponent0';actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};c=actors['Outdoor_connection'].get_components_by_class(unreal.StaticMeshComponent)[0];oldmesh=c.static_mesh;assert oldmesh.get_path_name()==row['before'];backup=OUT/('UniversityCity-before-connection-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);world=unreal.EditorLevelLibrary.get_editor_world();native=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'connection-restore-plan.json')));write('connection-restore-native',native);assert native['status']=='passed';checks=[];sweeps=[]
 for y in range(102000,119001,250):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(77500,y,1250),unreal.Vector(77500,y,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and abs(h[4].z-1206)<.1 and h[10]==c,('Connection support',y,num(h[4]) if h[0] else None);checks.append(num(h[4]))
 for a,b in zip(checks,checks[1:]):
  s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(a[0],a[1],a[2]+98),unreal.Vector(b[0],b[1],b[2]+98),35.,88.));assert not s['blocked'],('Restored connection obstructed',a,s);sweeps.append(s)
 after=ground_snapshot();assert len(after)==len(before)
 for a,b in zip(before,after):
  q=dict(b)
  if a['actor']=='Outdoor_connection':assert q['mesh'].split('.')[0]==row['after'];q['mesh']=a['mesh']
  assert q==a,a['actor']
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('connection-restore-install',dict(status='saved_requires_reopen_render_and_game_review',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),native=native,ground_probes=checks,capsule_sweeps=len(sweeps),scope='Restore112cm guardrails using hashed original geometry and original piecewise deck surface. Flatten only the deck to1206cm,retaining all relative structural heights,XY,topology,UV and materials. Underground original supports remain underground.69 supports and68 capsule segments checked.'))

def immersion_mirror_cameras():
 world=unreal.EditorLevelLibrary.get_editor_world();receipt=read('mirrors-install');rows=[]
 for q in receipt['rooms']:
  face=unreal.Vector(*q['face']);n=unreal.Vector(*q['normal']);t=unreal.Vector(*q['tangent'])
  for role,offset in [('front',0),('oblique',130)]:
   eye=face+n*350+t*offset+unreal.Vector(0,0,30);raw=unreal.SystemLibrary.line_trace_single(world,eye,eye-unreal.Vector(0,0,200),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and abs(h[4].z-(face.z-135))<5,(q['id'],role);eye.z=h[4].z+165;s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,eye-unreal.Vector(0,0,67),eye-unreal.Vector(0,0,66),35.,88.));assert not s['blocked'],(q['id'],role,s);rows.append(dict(id='mirror-'+q['id']+'-'+role,room=q['id'],name=q['name'],eye=num(eye),target=num(face),fov=105,camera_kind='supported mirror front and oblique reflection inspection'))
 for role,y,dy in [('south',103000,1000),('north',118500,-1000)]:rows.append(dict(id='connection-'+role,eye=[77500,y,1371],target=[77500,y+dy,1270],fov=80,camera_kind='restored level connection deck and full-height rails'))
 assert len(rows)==26 and ground_snapshot()==read('preservation-after')['components'];write('mirror-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,scope='Twenty-four supported front/oblique mirror views and two supported connection approaches; native D3D12 reflection review remains required.'));actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};components=[]
 for q in receipt['rooms']:
  a=actors['Immersion_Mirror_'+q['id']+'_Reflection'];c=a.get_components_by_class(unreal.PlanarReflectionComponent)[0];expected=unreal.Vector(*q['face'])+unreal.Vector(*q['normal'])*1.1;assert math.dist(num(a.get_actor_location()),num(expected))<.01;scale=a.get_actor_scale3d();assert abs(scale.x-q['width']/4000)<1e-6 and abs(scale.y-q['height']/4000)<1e-6 and abs(scale.z-1)<1e-6;assert 'ImmersionLargeMirror' in [str(t) for t in a.tags];assert not c.get_editor_property('show_preview_plane');previews=a.get_components_by_class(unreal.StaticMeshComponent);assert all(not p.is_visible() and p.get_editor_property('hidden_in_game') for p in previews);components.append(dict(room=q['id'],transform=actor_xform(a),capture_percent=c.get_editor_property('screen_percentage'),preview_hidden=True))
 write('mirror-components-native-review',dict(status='passed_requires_render_review',map_sha256=LOAD_SHA,components=components,clip_plane_current_process=unreal.SystemLibrary.get_console_variable_int_value('r.AllowGlobalClipPlane'),reflection_method_current_process=unreal.SystemLibrary.get_console_variable_int_value('r.ReflectionMethod'),scope='Saved/reopened12 tagged native planar components at correct face,orientation/size,hidden editor preview planes and50percent captures. Actual D3D12 configuration and reflected pixels remain separate acceptance.'))

def immersion_stair_handrails():
 assert not (OUT/'stair-handrails-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];plan=read('interior-probe-plan');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();cube=EAL.load_asset('/Engine/BasicShapes/Cube');material=next(m for c in actors['Campus_E1_F01'].get_components_by_class(unreal.StaticMeshComponent) for m in c.get_materials() if m and 'Campus_steel' in m.get_path_name());parts=[]
 for b in plan['buildings']:
  base=actors['Campus_'+b['building']+'_F01'].get_actor_location()
  def point(p):return base+unreal.Vector(p[1]*100,p[0]*100,p[2]*100)
  for floor in b['floors'][:-1]:
   for core in [q for q in floor['vertical_circulation'] if q['kind']=='stairs']:
    g=core['walkable_geometry'];per=g['riser_count']//g['flight_count'];rise=floor['height_m']/g['riser_count'];cx,cy,z=core['position_m'];run=g['flight_run_m']
    for j in range(g['flight_count']):
     xx=-.9 if j%2==0 else .9;sign=1 if j%2==0 else -1
     for edge in [-.77,.77]:
      p=point([cx+xx+edge,cy-sign*run/2,z+j*per*rise+.95]);q=point([cx+xx+edge,cy+sign*run/2,z+(j*per+per-1)*rise+.95]);parts.append(dict(building=b['building'],floor=floor['floor'],core=core['id'],start=num(p),end=num(q)))
 assert len(parts)>500,len(parts);backup=OUT/('UniversityCity-before-handrails-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,cube,material,'FlatCampus_ImmersionContinuousHandrails');a=c.get_owner();a.set_actor_label('Immersion_Continuous_StairHandrails');a.set_folder_path('UniversityCity/ImmersionV1');a.tags=[unreal.Name('ImmersionV1')];c.set_collision_profile_name('BlockAll');transforms=[]
 for part in parts:
  p,q=unreal.Vector(*part['start']),unreal.Vector(*part['end']);delta=q-p;length=math.dist(part['start'],part['end']);transforms.append(unreal.Transform(location=(p+q)*.5,rotation=unreal.MathLibrary.make_rot_from_z(delta),scale=unreal.Vector(.04,.04,length/100)))
 c.add_instances(transforms,False,True,True);assert c.get_instance_count()==len(parts);after=ground_snapshot();assert [q for q in after if q['actor']!='Immersion_Continuous_StairHandrails']==before;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('stair-handrails-install',dict(status='saved_requires_reopen_clearance_and_actual_walking',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),rails=parts,material=material.get_path_name(),scope='Continuous sloping4cm steel handrails connect existing tread-height posts on both sides of every existing flight. Existing stairs,posts,treads,landings,floors,doors and room functions retained.'))

def immersion_handrail_material():
 before=ground_snapshot();assert before==read('preservation-after')['components'];a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='Immersion_Continuous_StairHandrails');c=a.get_components_by_class(unreal.InstancedStaticMeshComponent)[0];source=c.get_material(0);backup=OUT/('UniversityCity-before-handrail-material-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);copy=EAL.duplicate_asset(source.get_path_name(),IMM+'/Handrails/M_StairSteel');assert copy;copy.set_editor_property('used_with_instanced_static_meshes',True);unreal.MaterialEditingLibrary.recompile_material(copy);assert EAL.save_loaded_asset(copy,False);c.modify();c.set_material(0,copy);after=ground_snapshot()
 for old,now in zip(before,after):
  q=dict(now)
  if old['actor']=='Immersion_Continuous_StairHandrails':assert q['materials']==[copy.get_path_name()];q['materials']=old['materials']
  assert q==old,old['actor']
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('handrail-material-install',dict(status='saved_requires_shader_and_render_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),source=source.get_path_name(),copy=copy.get_path_name(),scope='Private copy of original campus steel with identical shading graph and explicit ISM usage. Original material asset unchanged;only608 new rail instances rebound. All geometry,transforms and collision unchanged.'))

def immersion_water_path_caps():
 assert not (OUT/'water-path-caps-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='Immersion_Water_Metal');c=a.get_components_by_class(unreal.InstancedStaticMeshComponent)[0];chosen=[]
 for i in range(c.get_instance_count()):
  t=c.get_instance_transform(i,True);p=t.translation
  if abs(p.x-83100)<.01 and min(abs(p.y-75615),abs(p.y-75885))<.01 and abs(p.z-1207)<.01:
   assert abs(t.scale3d.x-.14)<.0001 and abs(t.scale3d.y-.14)<.0001 and abs(t.scale3d.z-.02)<.0001;chosen.append((i,t,ground_transform(t)))
 assert len(chosen)==2,len(chosen);backup=OUT/('UniversityCity-before-water-caps-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c.modify();changes=[]
 for i,old,state in chosen:
  t=unreal.Transform(location=old.translation+unreal.Vector(0,0,.5),rotation=old.rotation.rotator(),scale=unreal.Vector(old.scale3d.x,old.scale3d.y,.03));assert c.update_instance_transform(i,t,True,True,True);changes.append(dict(index=i,before=state,after=ground_transform(c.get_instance_transform(i,True)),bottom_cm=1206,top_cm=1209))
 reflection_bounds=[];mirror_rows=read('mirrors-install')['rooms'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert len(mirror_rows)==12
 for r in mirror_rows:
  a=actors['Immersion_Mirror_'+r['id']+'_Reflection'];old=actor_xform(a);a.modify();a.set_actor_scale3d(unreal.Vector(r['width']/4000,r['height']/4000,1));reflection_bounds.append(dict(room=r['id'],before=old,after=actor_xform(a),width_cm=r['width'],height_cm=r['height']))
 after=ground_snapshot();assert len(after)==len(before)
 for old,now in zip(before,after):
  q=json.loads(json.dumps(now))
  if old['actor']=='Immersion_Water_Metal':
   for r in changes:assert q['instances'][r['index']]==r['after'];q['instances'][r['index']]=r['before']
  if old['actor'].startswith('Immersion_Mirror_') and old['actor'].endswith('_Reflection'):
   r=next(r for r in reflection_bounds if old['actor']=='Immersion_Mirror_'+r['room']+'_Reflection');assert q['actor_transform']==r['after'] and old['actor_transform']==r['before'];assert q['transform']['translation']==old['transform']['translation'] and q['transform']['rotation']==old['transform']['rotation'];assert all(abs(q['transform']['scale'][i]-old['transform']['scale'][i]*(.025 if i<2 else 1))<.00001 for i in range(3));q['actor_transform']=old['actor_transform'];q['transform']=old['transform']
  assert q==old,old['actor']
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('water-path-caps-install',dict(status='saved_requires_reopen_and_depth_rescan',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=changes,scope='Only two14cm square metal footplates thickened upward1cm;bottom stays1206cm,top1209cm stands1cm above new1208cm path. Existing supports and all other instances retained.'));write('mirror-reflection-bounds-install',dict(status='saved_requires_reopen_and_render',map_sha256=newsha,before_map_sha256=LOAD_SHA,changes=reflection_bounds,source='E:/PhysX/UE5.8/Engine/Source/Runtime/Engine/Public/PlanarReflectionSceneProxy.h:MeshExtent2000cm',scope='Native planar proxy has4000cm full extent at unit scale;set12 capture rectangles to actual600/800cm mirror width and210/220cm height. Mirror panels and all indoor layouts unchanged.'))

def immersion_sports_finish():
 assert not (OUT/'sports-finish-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];mel=unreal.MaterialEditingLibrary;mi=EAL.load_asset('/Game/UniversityCity/RomancePBR/Materials/MI_SP_wall');assert mi;parent=base_material(mi);assert parent and not parent.get_editor_property('tangent_space_normal');file=ROOT/'StreetSocialCity/Content/UniversityCity/RomancePBR/Materials/MI_SP_wall.uasset';backup=OUT/'MI_SP_wall-before-sports-finish.uasset';shutil.copy2(file,backup);old_sha=sha(file);copy=EAL.duplicate_asset(parent.get_path_name(),IMM+'/SportsFinish/M_SportsFinish');assert copy;old_inputs={p:mel.get_material_property_input_node(copy,p) for p in [unreal.MaterialProperty.MP_BASE_COLOR,unreal.MaterialProperty.MP_NORMAL,unreal.MaterialProperty.MP_ROUGHNESS,unreal.MaterialProperty.MP_AMBIENT_OCCLUSION]};assert all(old_inputs.values());p=mel.create_material_expression(copy,unreal.MaterialExpressionWorldPosition);n=mel.create_material_expression(copy,unreal.MaterialExpressionVertexNormalWS);textures={}
 for kind,sampler in [('basecolor',unreal.MaterialSamplerType.SAMPLERTYPE_COLOR),('normal',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL),('orm',unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR)]:
  t=EAL.load_asset('/Game/UniversityCity/RomancePBR/Textures/T_teak_wood_v1_'+kind);assert t;node=mel.create_material_expression(copy,unreal.MaterialExpressionTextureObjectParameter);node.set_editor_property('parameter_name','SportsWood_'+kind);node.set_editor_property('texture',t);node.set_editor_property('sampler_type',sampler);textures[kind]=node
 common='float row=floor(P.y/14.0);float stagger=fmod(abs(row),2.0)*60.0;float board=floor((P.x+stagger)/120.0);float hash=frac(sin(dot(float2(board,row),float2(127.1,311.7)))*43758.5453);float2 uv=P.xy/240.0+float2(hash*3.71,row*.017);float2 du=ddx(P.xy/240.0),dv=ddy(P.xy/240.0);float2 f=frac(float2((P.x+stagger)/120.0,P.y/14.0));float dist=min(min(f.x,1-f.x)*120.0,min(f.y,1-f.y)*14.0);float seam=smoothstep(.06,.18,dist);float floorMask=step(.72,normalize(N).z);'
 codes={unreal.MaterialProperty.MP_BASE_COLOR:('basecolor',common+'float3 wood=Texture2DSampleGrad(Wood,WoodSampler,uv,du,dv).rgb*lerp(.94,1.06,hash)*lerp(.48,1.0,seam);return lerp(Old,wood,floorMask);',unreal.CustomMaterialOutputType.CMOT_FLOAT3),unreal.MaterialProperty.MP_NORMAL:('normal',common+'float2 xy=(Texture2DSampleGrad(Wood,WoodSampler,uv,du,dv).rg*2-1)*.25;float3 wn=float3(xy,sqrt(saturate(1-dot(xy,xy))));return normalize(lerp(Old,wn,floorMask));',unreal.CustomMaterialOutputType.CMOT_FLOAT3),unreal.MaterialProperty.MP_ROUGHNESS:('orm',common+'float r=clamp(Texture2DSampleGrad(Wood,WoodSampler,uv,du,dv).g,.45,.8);return lerp(Old,lerp(.82,r,seam),floorMask);',unreal.CustomMaterialOutputType.CMOT_FLOAT1),unreal.MaterialProperty.MP_AMBIENT_OCCLUSION:('orm',common+'float a=Texture2DSampleGrad(Wood,WoodSampler,uv,du,dv).r;return lerp(Old,a*lerp(.65,1.0,seam),floorMask);',unreal.CustomMaterialOutputType.CMOT_FLOAT1)}
 for prop,(kind,code,typ) in codes.items():
  out=mel.create_material_expression(copy,unreal.MaterialExpressionCustom);inputs=[]
  for name in ['P','N','Old','Wood']:i=unreal.CustomInput();i.set_editor_property('input_name',name);inputs.append(i)
  out.set_editor_property('inputs',inputs);out.set_editor_property('output_type',typ);out.set_editor_property('code',code)
  for name,node in [('P',p),('N',n),('Old',old_inputs[prop]),('Wood',textures[kind])]:assert mel.connect_material_expressions(node,'',out,name)
  assert mel.connect_material_property(out,'',prop)
 copy.set_editor_property('used_with_instanced_static_meshes',True);errors=compile_errors(copy);assert not errors,errors;assert EAL.save_loaded_asset(copy,False);mel.set_material_instance_parent(mi,copy)
 for kind,param in [('basecolor','RomanceBase'),('normal','RomanceNormal'),('orm','RomanceORM')]:
  texture=EAL.load_asset('/Game/UniversityCity/RomancePBR/Textures/T_pale_resort_stucco_v1_'+kind);assert texture;mel.set_material_instance_texture_parameter_value(mi,param,texture)
 for param,value in [('RomancePeriod',180.),('RomanceStrength',.45)]:mel.set_material_instance_scalar_parameter_value(mi,param,value)
 for param,color in [('RomanceTintA',unreal.LinearColor(1,.985,.96,1)),('RomanceTintB',unreal.LinearColor(.96,.975,.985,1))]:mel.set_material_instance_vector_parameter_value(mi,param,color)
 EAL.set_metadata_tag(mi,'ImmersionSportsFinish','warm_stucco_and_14cm_staggered_wood_boards');assert EAL.save_loaded_asset(mi,False);assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('sports-finish-install',dict(status='asset_saved_requires_source_and_cooked_render_validation',map_sha256=LOAD_SHA,material=mi.get_path_name(),parent=copy.get_path_name(),source_file=str(file),before_sha256=old_sha,sha256=sha(file),backup=str(backup),board_width_cm=14,board_length_cm=120,wall_set='pale_resort_stucco_v1',floor_set='teak_wood_v1',scope='Repair one SP wall material instance previously applied to both walls and floor. Preserve component bindings and all geometry/collision/functions. Up-facing surfaces use14cm/120cm staggered wood boards with matched base/normal/ORM and nonrepeating per-board grain offsets;walls and ceilings use pale mineral stucco. Existing court-marking and equipment material slots preserved. No map bytes changed.'))

def immersion_fixture_layout_context():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for a in SUB.get_all_level_actors():
  if a.get_editor_property('hidden'):continue
  p,e=a.get_actor_bounds(False);label=a.get_actor_label()
  near_pavilion=abs(p.x-103300)<1800 and abs(p.y-8500)<1800
  near_track=54500<p.x<66700 and 19000<p.y<39500 and max(e.x,e.y)<1000
  if not near_pavilion and not near_track and label not in ['Activity_ACTSPACE-08-289','Outdoor_campus_track']:continue
  meshes=[dict(component=c.get_name(),mesh=c.static_mesh.get_path_name() if c.static_mesh else None,visible=c.is_visible(),hidden=c.get_editor_property('hidden_in_game')) for c in a.get_components_by_class(unreal.StaticMeshComponent)]
  if not meshes:continue
  rows.append(dict(actor=label,location=num(a.get_actor_location()),bounds_cm=[num(p-e),num(p+e)],meshes=meshes))
 assert ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('fixture-layout-native-context',dict(status='read_only',map_sha256=LOAD_SHA,rows=rows))

def immersion_fixture_placement_probe(verify_snapshot=True):
 world=unreal.EditorLevelLibrary.get_editor_world();actors=list(SUB.get_all_level_actors());elevated=[];targets=[]
 for a in actors:
  label=a.get_actor_label()
  if not label.startswith('Environment_') or not label.endswith('_Foot') or a.get_editor_property('hidden'):continue
  p,e=a.get_actor_bounds(False);base=p.z-e.z
  if base<1250:continue
  prefix=label[:-4];ignore=[q for q in actors if q.get_actor_label().startswith(prefix)];hits=[]
  for top,bottom in [(base+30,base-40),(1250,1100)]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p.x,p.y,top),unreal.Vector(p.x,p.y,bottom),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignore,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];hits.append(dict(hit=bool(h[0]),position=num(h[4]) if h[0] else None,actor=h[9].get_actor_label() if h[0] else None))
  elevated.append(dict(actor=label,base_cm=base,xy_cm=[p.x,p.y],hits=hits))
 for x,y in [(66300,28000),(66300,32000),(103300,7950),(102250,7800),(104400,8000)]:
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,1304),unreal.Vector(x,y,1305),35.,88.));targets.append(dict(x=x,y=y,hit=bool(h[0]),ground=num(h[4]) if h[0] else None,actor=h[9].get_actor_label() if h[0] else None,capsule=s))
 assert sha(MAPFILE)==LOAD_SHA
 if verify_snapshot:assert ground_snapshot()==read('preservation-after')['components']
 write('fixture-placement-probe',dict(status='read_only' if verify_snapshot else 'unsaved_candidate_preflight',map_sha256=LOAD_SHA,elevated_environment_feet=elevated,target_candidates=targets))

def immersion_fixture_placement_plan():
 probe=read('fixture-placement-probe');assert probe['map_sha256']==LOAD_SHA;actors=list(SUB.get_all_level_actors());world=unreal.EditorLevelLibrary.get_editor_world();groups=[]
 for row in probe['elevated_environment_feet']:
  prefix=row['actor'][:-4];members=[a for a in actors if a.get_actor_label().startswith(prefix)];assert len(members)==6,(prefix,len(members));ignored=members;ox,oy=row['xy_cm'];candidates=[]
  if prefix=='Environment_E013_0_':candidates.append((103300,7950))
  if prefix=='Environment_E036_0_':candidates.append((102250,7800))
  if prefix=='Environment_PK_0107_1_':candidates.append((ox+350,oy))
  if prefix=='Environment_E021_1_':candidates.append((ox+350,oy))
  candidates.append((ox,oy))
  for d in [100,150,200,300,400]:
   for dx,dy in [(1,0),(-1,0),(0,1),(0,-1),(1,1),(-1,1),(1,-1),(-1,-1)]:candidates.append((ox+dx*d,oy+dy*d))
  chosen=None
  for x,y in candidates:
   hits=[]
   for dx,dy in [(0,0),(-15,-15),(-15,15),(15,-15),(15,15)]:
    raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x+dx,y+dy,1250),unreal.Vector(x+dx,y+dy,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
    if not h[0] or not 1190<=h[4].z<=1240 or h[7].z<.95 or not h[9].get_actor_label().startswith(('G','World_PK_','Outdoor_','FlatCampus_','Immersion_')):break
    hits.append(dict(position=num(h[4]),actor=h[9].get_actor_label()))
   if len(hits)!=5 or max(h['position'][2] for h in hits)-min(h['position'][2] for h in hits)>1:continue
   z=max(h['position'][2] for h in hits);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),40.,88.))
   if s['blocked']:continue
   chosen=dict(xy_cm=[x,y],ground_cm=z,supports=hits,capsule=s);break
  assert chosen,('No supported clear fixture site',prefix);delta=[chosen['xy_cm'][0]-ox,chosen['xy_cm'][1]-oy,chosen['ground_cm']+.2-row['base_cm']];groups.append(dict(prefix=prefix,old_base_cm=row['base_cm'],target=chosen,delta_cm=delta,members=[dict(actor=a.get_actor_label(),before=actor_xform(a)) for a in members]))
 assert len(groups)==11 and ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('fixture-placement-plan',dict(status='prepared_native_support_and_clearance_passed',map_sha256=LOAD_SHA,groups=groups,policy='Translate all six existing parts of each of eleven elevated fixture groups together onto supported level ground. Preserve light intensities/schedules/materials/collision, keep player capsules clear, and recheck all campus routes before saving.'))

def immersion_layout_followup_install():
 installed=read('install');fixture=read('fixture-placement-plan');benches=read('track-bench-plan');alignment=read('stem-render-alignment');render=read('fixture-render-clearance');assert installed['map_sha256']==fixture['map_sha256']==benches['map_sha256']==alignment['map_sha256']==render['map_sha256']==LOAD_SHA and render['status']=='passed';assert len(alignment['unmatched_proxies'])==len(alignment['unmatched_visible_roots'])==1 and not (OUT/'layout-followup-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();backup=OUT/('UniversityCity-before-layout-followup-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for g in fixture['groups']:
  for q in g['members']:assert actor_xform(actors[q['actor']])==q['before']
 for m in benches['meshes']:
  assert not EAL.does_asset_exist(m['after'])
  for l in m['lods']:assert sha(l['vertices'])==l['sha256']
 proxy=actors['LandscapeV3_TrunkCollision'].get_components_by_class(unreal.InstancedStaticMeshComponent)[0];t=proxy.get_instance_transform(283,True);old_proxy=ground_transform(t);assert math.dist(num(t.translation),[53770,57400,1196.320273462])<.01;tree=actors['Resort_camphor_1_5_5'].get_components_by_class(unreal.InstancedStaticMeshComponent)[0];root=tree.get_instance_transform(3,True).translation;assert math.dist(num(root),[53770,56400,1196.320273462])<.01
 native=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'track-bench-plan.json')));write('track-bench-native',native);assert native['status']=='passed',native;changes=[]
 for g in fixture['groups']:
  for q in g['members']:
   a=actors[q['actor']];p=a.get_actor_location();a.modify();assert a.set_actor_location(p+unreal.Vector(*g['delta_cm']),False,True);changes.append(dict(q,after=actor_xform(a),delta_cm=g['delta_cm']))
 proxy.modify();t.translation=root;assert proxy.update_instance_transform(283,t,True,True,True);new_proxy=ground_transform(proxy.get_instance_transform(283,True));assert new_proxy['rotation']==old_proxy['rotation'] and new_proxy['scale']==old_proxy['scale'];checks=[]
 for kind,p,expected in [('new_visible_root',num(root),True),('vacated_ghost_location',old_proxy['translation'],False)]:
  hits=[]
  for dx,dy in [(70,0),(0,70),(-70,0),(0,-70)]:
   center=unreal.Vector(p[0],p[1],p[2]+100);raw=unreal.SystemLibrary.line_trace_single(world,center+unreal.Vector(dx,dy,0),center,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,False,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];hits.append(bool(h[0] and h[10]==proxy))
  assert any(hits) if expected else not any(hits),(kind,hits);checks.append(dict(kind=kind,proxy_hits=hits,passed=True))
 for y in [28000,32000]:
  s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(64000,y,1325),unreal.Vector(64001,y,1325),35.,88.));assert not s['blocked'],('Old field bench position not clear',y,s)
  for x,yy in [(66280,y-65),(66320,y-65),(66280,y+65),(66320,y+65)]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,yy,1200),unreal.Vector(x,yy,1185),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[actors['Outdoor_campus_track']],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and abs(h[4].z-1198)<.3,(x,yy,h)
 after=ground_snapshot();moved={q['actor']:q for q in changes};replacement=benches['meshes'][0];assert len(after)==len(before)
 for old,now in zip(before,after):
  q=json.loads(json.dumps(now));key=q['actor']+'::'+q['component']
  if key==replacement['key']:assert q['mesh'].split('.')[0]==replacement['after'];q['mesh']=old['mesh']
  if q['actor'] in moved:
   row=moved[q['actor']];assert q['actor_transform']==row['after'];assert q['actor_transform']['rotation']==old['actor_transform']['rotation'] and q['actor_transform']['scale']==old['actor_transform']['scale'];assert all(abs(q['transform']['translation'][i]-old['transform']['translation'][i]-row['delta_cm'][i])<.01 for i in range(3));q['actor_transform']=old['actor_transform'];q['transform']=old['transform']
  if q['actor']=='LandscapeV3_TrunkCollision':assert q['instances'][283]==new_proxy;q['instances'][283]=old['instances'][283]
  assert q==old,('Unexpected layout change',key)
 immersion_fixture_placement_probe(False);assert not read('fixture-placement-probe')['elevated_environment_feet'];immersion_door_capsule_probe();immersion_interior_probe();immersion_route_review();assert read('door-capsule-probe')['status']==read('interior-native-probe')['status']==read('route-native-review')['status']=='passed','Layout preflight failed; reopen audit before any further mutation.'
 controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,relocated_elevated_fixture_groups=11,relocated_track_benches=2,corrected_ghost_stem_instance=283);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('layout-followup-install',dict(status='saved_requires_reopen_and_cooked_review',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),fixture_changes=changes,track_mesh=native,ghost_proxy=dict(actor='LandscapeV3_TrunkCollision',instance=283,before=old_proxy,after=new_proxy,checks=checks),policy='Eleven complete fixture groups grounded and cleared of visible props; two original benches moved off track run-off, no sport geometry displaced; only one existing ghost tree proxy translated10m to its unchanged visible trunk. Original materials, lighting schedules, floors and interiors preserved.'))

def immersion_cherry_dense_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/CherriesV2';KEEP=[];save=save_asset;api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);mat=EAL.load_asset(IMM+'/Cherries/Materials/M_Blossoms');bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV2/Materials/M_Bark');green=EAL.load_asset(IMM+'/Palms/Materials/M_Fronds');assert mat and bark and green;source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)");namespace=dict(globals());exec('def import_one('+source,namespace);rows=[]
 for aid in ['cherry-a','cherry-b','cherry-c']:
  meshes=[]
  for lod in range(3):
   mesh=namespace['import_one'](OUT/'cherries-v2'/'assets'/aid/('LOD'+str(lod)+'-source.glb'),aid,lod,False)
   for i,s in enumerate(mesh.get_editor_property('static_materials')):
    name=str(s.get_editor_property('imported_material_slot_name'));assert any(k in name for k in ['Bark','Flowers','Green']);mesh.set_material(i,bark if 'Bark' in name else green if 'Green' in name else mat)
   assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
  mesh=meshes[0]
  for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
  assert api.set_lod_screen_sizes(mesh,[1.,.22,.07]);EAL.set_metadata_tag(mesh,'ImmersionCherry','V2: flower-cluster projected-area coverage retained across180/90/30 clusters per anchor with1/1.4/2.35 radius ratios; original bark and petal materials reused.');assert EAL.save_loaded_asset(mesh,False);bounds=mesh.get_bounds();rows.append(dict(id=aid,asset=mesh.get_path_name(),triangles=[mesh.get_num_triangles(i) for i in range(3)],origin_cm=num(bounds.origin),extent_cm=num(bounds.box_extent),materials=[mesh.get_material(i).get_path_name() for i in range(len(mesh.get_editor_property('static_materials')))]))
 assert ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('cherry-dense-import',dict(status='passed',map_sha256=LOAD_SHA,assets=rows,scope='Three new mesh assets only; original checkpoint assets and all material graphs retained unchanged. Local procedural geometry, not Tripo/Grok generation.'))

def immersion_cherry_dense_install():
 installed=read('install');imported=read('cherry-dense-import');assert installed['map_sha256']==imported['map_sha256']==LOAD_SHA and not (OUT/'cherry-dense-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};changes=[];backup=OUT/('UniversityCity-before-cherry-density-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for i in range(6):
  label='Immersion_Cherry_Tree_'+str(i);a=actors[label];c=a.static_mesh_component;old=c.static_mesh;assert '/ImmersionV1/Cherries/Assets/' in old.get_path_name();row=imported['assets'][i%3];mesh=EAL.load_asset(row['asset']);assert mesh;original_materials=[c.get_material(k).get_path_name() for k in range(c.get_num_materials())];assert original_materials==row['materials'];c.modify();c.set_static_mesh(mesh);changes.append(dict(actor=label,before=old.get_path_name(),after=mesh.get_path_name(),triangles=row['triangles']))
 after=ground_snapshot();expected={r['actor']:r for r in changes};assert len(before)==len(after)
 for old,now in zip(before,after):
  row=dict(now)
  if row['actor'] in expected:assert row['mesh']==expected[row['actor']]['after'];row['mesh']=old['mesh']
  assert row==old,('Unexpected cherry density change',row['actor'])
 actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,cherry_density_revision=2);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('cherry-dense-install',dict(status='saved_requires_reopen_visual_and_cooked_review',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),changes=changes,policy='Increase apparent blossom coverage at all three LODs with projected-area compensation; retain all six original roots/transforms, bark/petal/green materials, hidden stem proxies and narrow crown dimensions. No opaque spherical canopy.'))

def immersion_layout_cameras():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];unavailable=[]
 def camera(name,candidates,target,fov=75):
  for x,y in candidates:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or not 1190<=h[4].z<=1250 or h[7].z<.9:continue
   z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.))
   if s['blocked']:continue
   rows.append(dict(id=name,eye=[x,y,z+165],target=target,fov=fov,ground_cm=z,ground_actor=h[9].get_actor_label(),capsule=s,camera_kind='native supported player-height'));return True
  unavailable.append(name);return False
 for group in read('fixture-placement-plan')['groups']:
  x,y=group['target']['xy_cm'];z=group['target']['ground_cm'];assert camera('fixture-'+group['prefix'].rstrip('_'),[(x+dx,y+dy) for dx,dy in [(400,300),(-400,300),(400,-300),(-400,-300),(0,500),(0,-500)]],[x,y,z+100],70)
 for y in [28000,32000]:assert camera('bench-outer-shoulder-'+str(y),[(66800,y+400),(66800,y-400),(66100,y+400)],[66300,y,1240],70)
 assert camera('field-runoff-cleared',[(65200,32000)],[64000,32000,1270],75)
 for name,p in [('matched-trunk',[53770,56400,1296]),('vacated-ghost',[53770,57400,1296])]:assert camera(name,[(p[0]+dx,p[1]+dy) for dx,dy in [(350,300),(-350,300),(350,-300),(-350,-300)]],p,75)
 for name,x,y in [('cherry-near',44500,79850),('cherry-medium',44500,80650),('cherry-far',44500,81900)]:assert camera(name,[(x,y),(x,y+100),(x,y-100)],[43920,79850,1600],70)
 for i,y in enumerate([23740,27840,31940]):camera('pool-waterline-'+str(i),[(x,y+dy) for x in [77400,77300,77500,77000,82800] for dy in [0,-500,500]],[80000,y,1185],80)
 previous=read('outdoor-player-cameras');r=next(r for r in previous['rows'] if r['id']=='PK-0111');assert camera('pavilion-roof-clear',[(r['eye'][0],r['eye'][1])],r['target'],85)
 assert len(rows)>=20 and ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('layout-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,unavailable=unavailable,scope='Supported player views of eleven corrected fixture groups, two outer-track benches and cleared run-off, visible/ghost stem locations, three blossom distances, pool edges and cleared pavilion roof. Source preview then final cooked capture required.'))

def immersion_refresh_current_reviews():
 if read('install').get('active_park_level_corrected'):immersion_active_park_review()
 assert read('audit')['map_sha256']==LOAD_SHA and read('audit')['status']=='passed';immersion_door_capsule_probe();immersion_interior_probe();immersion_route_review();assert read('door-capsule-probe')['status']==read('interior-native-probe')['status']==read('route-native-review')['status']=='passed';immersion_fixture_placement_probe();assert not read('fixture-placement-probe')['elevated_environment_feet'];immersion_fixture_physics_probe();immersion_retired_lamp_audit();immersion_lighting_audit();assert read('lighting-audit')['status']=='passed';immersion_outdoor_floor_probe();immersion_outdoor_player_cameras();immersion_extra_outdoor_cameras();immersion_followup_cameras();immersion_quality_cameras();immersion_layout_cameras();immersion_polish_cameras();immersion_all_floor_cameras();immersion_moon_cameras();immersion_stair_routes();immersion_game_plan();assert ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('current-review-refresh',dict(status='passed',map_sha256=LOAD_SHA,scope='Read-only reopened current source: all door/interior/campus route probes, environment feet,254 fixture physics rays,retired-light safety,130 warm light settings,current player cameras including89 school-floor poses and cooked physics plan refreshed without scene mutation.'))

def immersion_lamp_spacing_context():
 spacing=read('landscape-spacing');assert spacing['map_sha256']==LOAD_SHA;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for label,a in actors.items():
  if not ((label.startswith('Environment_') and label.endswith('_Light')) or label.startswith('Immersion_NauticalLight_')):continue
  c=a.light_component;rows.append(dict(actor=label,transform=actor_xform(a),tags=[str(t) for t in a.tags],intensity=float(c.get_editor_property('intensity')),affects_world=bool(c.get_editor_property('affects_world')),visible=c.is_visible(),actor_hidden=bool(a.get_editor_property('hidden')),source_radius=float(c.get_editor_property('source_radius')),attenuation_radius=float(c.get_editor_property('attenuation_radius')),temperature=float(c.get_editor_property('temperature'))))
 assert ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('lamp-spacing-native-context',dict(status='read_only',map_sha256=LOAD_SHA,lights=rows))

def immersion_lamp_consolidation_install():
 plan=read('lamp-consolidation-plan');installed=read('install');assert plan['map_sha256']==installed['map_sha256']==LOAD_SHA and len(plan['groups'])==36 and not (OUT/'lamp-consolidation-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-lamp-consolidation-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);retired=set();upgraded=[]
 for g in plan['groups']:
  assert len(g['source_components'])==5 and not g['prefix'].startswith('Environment_PK_')
  for r in g['source_components']:assert next(q for q in before if q['actor']==r['actor'] and q['component']==r['component'])==r
  for r in [g['old_light'],g['upgraded_before']]:assert actor_xform(actors[r['actor']])==r['transform'] and [str(t) for t in actors[r['actor']].tags]==r['tags']
 def retire(g):
  for r in g['source_components']:
   a=actors[r['actor']];a.modify();a.set_actor_hidden_in_game(True);retired.add(r['actor'])
   for c in a.get_components_by_class(unreal.StaticMeshComponent):c.modify();c.set_collision_profile_name('NoCollision');c.set_visibility(False,True);c.set_hidden_in_game(True,True);c.set_editor_property('cast_hidden_shadow',False)
  a=actors[g['old_light']['actor']];a.modify();a.set_actor_hidden_in_game(True);a.tags=[unreal.Name(t) for t in g['old_light']['tags'] if not t.startswith('EnvLumens=')]+[unreal.Name('EnvLumens=0'),unreal.Name('ImmersionRetiredDuplicate')];c=a.light_component;c.modify();c.set_editor_property('affects_world',False);c.set_intensity(0);c.set_visibility(False,True)
 for g in plan['groups']:
  retire(g)
  if g['kind']!='nautical_replacement':continue
  a=actors[g['upgraded_light']];a.modify();a.tags=[unreal.Name(t) for t in g['upgraded_before']['tags'] if not t.startswith('EnvLumens=')]+[unreal.Name('EnvLumens=200')];c=a.light_component;c.modify();c.set_intensity(200);c.set_editor_property('attenuation_radius',900);c.set_editor_property('source_radius',25);c.set_editor_property('volumetric_scattering_intensity',0.);assert not c.get_editor_property('cast_shadows');upgraded.append(a.get_actor_label())
 assert len(upgraded)==32 and len(retired)==180;immersion_door_capsule_probe();immersion_interior_probe();immersion_route_review();assert read('door-capsule-probe')['status']==read('interior-native-probe')['status']==read('route-native-review')['status']=='passed';controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save()
 for g in plan['groups']:retire(g)
 after=ground_snapshot();assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now)
  if row['actor'] in retired:
   assert row['actor_hidden'] and row['hidden'] and not row['visible'] and row['collision']=='NoCollision';row['actor_hidden']=old['actor_hidden'];row['hidden']=old['hidden'];row['visible']=old['visible'];row['collision']=old['collision']
  assert row==old,('Unintended lamp consolidation change',row['actor'])
 for g in plan['groups']:
  a=actors[g['old_light']['actor']];c=a.light_component;assert a.get_editor_property('hidden') and not c.get_editor_property('affects_world') and not c.is_visible() and c.get_editor_property('intensity')==0
 assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,retired_duplicate_fixture_groups=36,consolidated_nautical_lights=32);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('lamp-consolidation-install',dict(status='saved_requires_reopen_day_night_and_cooked_review',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),plan=plan,retired_mesh_actors=sorted(retired),retired_light_actors=[g['old_light']['actor'] for g in plan['groups']],upgraded_surviving_lights=upgraded,policy=plan['policy']))

def immersion_fixture_collision_trial():
 before=ground_snapshot();assert before==read('preservation-after')['components'];actors=SUB.get_all_level_actors();changed=[]
 try:
  for a in actors:
   label=a.get_actor_label()
   if not label.startswith('Environment_') or not label.endswith(('_Foot','_Stem','_Hood','_LowerRing')) or a.get_editor_property('hidden'):continue
   for c in a.get_components_by_class(unreal.StaticMeshComponent):
    old=str(c.get_collision_profile_name());changed.append((c,old));c.set_collision_profile_name('BlockAll')
  immersion_route_review();review=read('route-native-review');write('fixture-collision-trial',dict(status='trial_passed' if review['status']=='passed' else 'trial_requires_placement_repair',map_sha256=LOAD_SHA,temporary_metal_components=len(changed),route_sweeps=review['capsule_sweeps'],blocked=review['blocked'],unsupported=review['unsupported'],scope='Temporary native collision trial for active standard fixture metal parts only. Restored all original profiles in finally; no source save or asset mutation. Render visibility and positive fixture physics require separate checks.'))
 finally:
  for c,old in changed:c.set_collision_profile_name(old)
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA

def immersion_fixture_collision_plan():
 before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();prefix='Environment_PK_0102_1_';members=[a for name,a in actors.items() if name.startswith(prefix)];assert len(members)==6;original=[(a,a.get_actor_location(),actor_xform(a)) for a in members];foot=actors[prefix+'Foot'];p,e=foot.get_actor_bounds(False);base=p.z-e.z;changed=[];chosen=None;trials=[]
 try:
  for a in actors.values():
   label=a.get_actor_label()
   if not label.startswith('Environment_') or not label.endswith(('_Foot','_Stem','_Hood','_LowerRing')) or a.get_editor_property('hidden'):continue
   for c in a.get_components_by_class(unreal.StaticMeshComponent):changed.append((c,str(c.get_collision_profile_name())));c.set_collision_profile_name('BlockAll')
  for dx,dy in [(-150,0),(-200,0),(-250,0),(-150,-150),(150,150)]:
   x,y=p.x+dx,p.y+dy;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,members,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or not 1190<=h[4].z<=1215:continue
   delta=[dx,dy,float(h[4].z)+.2-base]
   for a,location,_ in original:a.set_actor_location(location+unreal.Vector(*delta),False,True)
   immersion_route_review();r=read('route-native-review');trials.append(dict(delta_cm=delta,status=r['status'],blocked=r['blocked'],unsupported=r['unsupported']))
   if r['status']=='passed':chosen=dict(prefix=prefix,delta_cm=delta,ground_cm=num(h[4]),ground_actor=h[9].get_actor_label(),members=[dict(actor=a.get_actor_label(),before=t) for a,_,t in original]);break
 finally:
  for a,location,_ in original:a.set_actor_location(location,False,True)
  for c,old in changed:c.set_collision_profile_name(old)
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('fixture-collision-plan',dict(status='prepared_native_route_trial_passed' if chosen else 'requires_review',map_sha256=LOAD_SHA,metal_components=len(changed),relocation=chosen,trials=trials,policy='Enable real blocking on all124 active standard pole metal fixtures(496 components), keeping opal NoCollision and retired duplicate fixtures hidden/NoCollision. Move the complete PK0102_1 bollard group from the NorthDorm route turn to a supported shoulder. Preserve all assets, materials and lighting tags.'));assert chosen,'No collision-safe PK0102 shoulder candidate'

def immersion_fixture_collision_install():
 plan=read('fixture-collision-plan');installed=read('install');assert plan['map_sha256']==installed['map_sha256']==LOAD_SHA and plan['status']=='prepared_native_route_trial_passed' and not (OUT/'fixture-collision-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();backup=OUT/('UniversityCity-before-fixture-collision-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);changed=set();moves=[]
 for a in actors.values():
  label=a.get_actor_label()
  if not label.startswith('Environment_') or not label.endswith(('_Foot','_Stem','_Hood','_LowerRing')) or a.get_editor_property('hidden'):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):c.modify();c.set_collision_profile_name('BlockAll');changed.add(label+'::'+c.get_name())
 assert len(changed)==496
 for r in plan['relocation']['members']:
  a=actors[r['actor']];assert actor_xform(a)==r['before'];location=a.get_actor_location();a.modify();assert a.set_actor_location(location+unreal.Vector(*plan['relocation']['delta_cm']),False,True);moves.append(dict(r,after=actor_xform(a)))
 physics=[]
 for label,a in actors.items():
  if not label.startswith('Environment_') or not label.endswith('_Stem') or a.get_editor_property('hidden'):continue
  c=a.get_component_by_class(unreal.StaticMeshComponent);t=c.get_world_transform();b=c.static_mesh.get_bounds();p=t.transform_location(b.origin);radius=max(abs(b.box_extent.x*t.scale3d.x),abs(b.box_extent.y*t.scale3d.y))+60;passed=False
  for dx,dy in [(radius,0),(0,radius),(-radius,0),(0,-radius)]:
   start=p+unreal.Vector(dx,dy,0);raw=unreal.SystemLibrary.line_trace_single(world,start,p,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,False,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if h[0] and h[10]==c:physics.append(dict(actor=label,owner_object_name=a.get_name(),component_name=c.get_name(),start=num(start),end=num(p),passed=True));passed=True;break
  assert passed,('Visible standard pole missing positive physics',label)
 assert len(physics)==124;immersion_door_capsule_probe();immersion_interior_probe();immersion_route_review();assert read('door-capsule-probe')['status']==read('interior-native-probe')['status']==read('route-native-review')['status']=='passed';after=ground_snapshot();moved={r['actor']:r for r in moves};assert len(before)==len(after)
 for old,now in zip(before,after):
  row=dict(now);key=row['actor']+'::'+row['component']
  if key in changed:assert row['collision']=='BlockAll';row['collision']=old['collision']
  if row['actor'] in moved:
   assert row['actor_transform']==moved[row['actor']]['after'];assert all(abs(row['transform']['translation'][i]-old['transform']['translation'][i]-plan['relocation']['delta_cm'][i])<.01 for i in range(3));row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  assert row==old,('Unintended fixture collision change',key)
 controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,blocking_standard_fixture_groups=124);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('fixture-collision-install',dict(status='saved_requires_reopen_and_cooked_fixture_replay',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),metal_components=496,moves=moves,positive_physics=physics,policy=plan['policy']))

def immersion_fixture_physics_probe():
 before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();targets=[];rows=[];issues=[];counts=dict(standard_pole=0,nautical_pole=0,path_bollard=0)
 for label,a in actors.items():
  if label.startswith('Environment_') and label.endswith('_Stem') and not a.get_editor_property('hidden'):
   c=a.get_component_by_class(unreal.StaticMeshComponent);t=c.get_world_transform();targets.append((c,-1,t.transform_location(c.static_mesh.get_bounds().origin),80.,'standard_pole',label))
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or '/ImmersionV1/NauticalLantern/Assets/' not in c.static_mesh.get_path_name() or not c.is_visible() or c.get_editor_property('hidden_in_game') or a.get_editor_property('hidden'):continue
   instanced=isinstance(c,unreal.InstancedStaticMeshComponent)
   for i in range(c.get_instance_count()) if instanced else [-1]:
    t=c.get_instance_transform(i,True) if instanced else c.get_world_transform();targets.append((c,i,t.transform_location(unreal.Vector(0,0,100)),80*max(abs(t.scale3d.x),abs(t.scale3d.y))+30,'nautical_pole',label+'/'+str(i)))
 c=actors['Immersion_PathLamp_Metal'].get_components_by_class(unreal.InstancedStaticMeshComponent)[0]
 for i,q in enumerate(read('path-lamps')['fixtures']):p=q['position_cm'];targets.append((c,None,unreal.Vector(p[0],p[1],p[2]+45),80.,'path_bollard','Immersion_PathLamp/'+str(i)))
 for c,instance,p,radius,kind,identity in targets:
  result=None;attempts=[]
  for dx,dy in [(radius,0),(0,radius),(-radius,0),(0,-radius)]:
   start=p+unreal.Vector(dx,dy,0);raw=unreal.SystemLibrary.line_trace_single(world,start,p,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,False,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];attempts.append(dict(hit=bool(h[0]),actor=h[9].get_actor_label() if h[0] else None,item=int(h[13]) if h[0] else None))
   if h[0] and h[10]==c and (instance is None or instance<0 or int(h[13])==instance):result=dict(id=identity,kind=kind,owner_object_name=c.get_owner().get_name(),component_name=c.get_name(),mesh=c.static_mesh.get_path_name(),instance=int(h[13]) if isinstance(c,unreal.InstancedStaticMeshComponent) else -1,start=num(start),end=num(p),hit_point=num(h[4]),passed=True);break
  counts[kind]+=1
  if result:rows.append(result)
  else:issues.append(dict(id=identity,kind=kind,attempts=attempts,point_cm=num(p)))
 assert counts==dict(standard_pole=124,nautical_pole=50,path_bollard=80),counts;assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('fixture-physics-probe',dict(status='passed' if not issues else 'requires_repair',map_sha256=LOAD_SHA,counts=counts,checked=len(targets),rows=rows,issues=issues,scope='Positive simple-collision world rays for every124 active standard pole,50 nautical poles and80 path bollards. Resolve actual hit component and instance; feeds an independent final cooked replay. No source mutation.'));assert not issues,issues[:4]

def immersion_pool_edge_install():
 plan=read('pool-edge-plan');installed=read('install');assert plan['map_sha256']==installed['map_sha256']==LOAD_SHA and not (OUT/'pool-edge-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];source=plan['source_component'];assert next(r for r in before if r['actor']=='Campus_SP_Water')==source;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};c=actors['Campus_SP_Water'].static_mesh_component;shader=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(c.get_material(0)));assert shader['static_opaque_no_depth_displacement'],shader
 for m in plan['meshes']:
  assert not EAL.does_asset_exist(m['after'])
  for l in m['lods']:assert sha(l['vertices'])==l['sha256']
 backup=OUT/('UniversityCity-before-pool-edge-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);native=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'pool-edge-plan.json')));write('pool-edge-native',native);assert native['status']=='passed',native;after=ground_snapshot();assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now)
  if row['actor']=='Campus_SP_Water':assert row['mesh'].split('.')[0]==plan['meshes'][0]['after'] and row['collision']=='NoCollision';row['mesh']=old['mesh']
  assert row==old,('Unexpected pool-edge scene change',row['actor'])
 immersion_door_capsule_probe();immersion_interior_probe();immersion_route_review();assert read('door-capsule-probe')['status']==read('interior-native-probe')['status']==read('route-native-review')['status']=='passed';actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,pool_water_edge_clearance_cm=1);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('pool-edge-install',dict(status='saved_requires_reopen_visual_and_depth_rescan',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),plan=plan,native=native,shader=shader,policy=plan['policy']))

def immersion_tree_spacing_plan():
 before=ground_snapshot();assert before==read('preservation-after')['components'];alignment=read('stem-render-alignment');assert alignment['status']=='matched_visible_roots';actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();roots=[dict(r['tree']) for r in alignment['matches']];buildings=[];ignored=[actors['LandscapeV3_TrunkCollision'],actors['Immersion_Cherry_TrunkColliders']]
 for name,a in actors.items():
  if re.fullmatch(r'(Campus_[A-Z0-9]+|City_O\d+|[A-Z]\d+)_F01',name):p,e=a.get_actor_bounds(False);buildings.append((name,num(p-e),num(p+e)))
 proposals=[]
 for label,index,candidates in [('Resort_camphor_3_7_4',1,[(44100,79200),(44100,79000),(43920,79200)]),('Resort_cherry_3_8_4',1,[(45080,79200),(45080,79300),(45080,79100)])]:
  row=next(r for r in alignment['matches'] if r['tree']['actor']==label and r['tree']['instance']==index);tree=row['tree'];proxy=row['proxy'];a=actors[label];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==tree['component']);t=c.get_instance_transform(index,True);assert math.dist(num(t.translation),tree['root_cm'])<.01;oldp=num(t.translation);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(oldp[0],oldp[1],oldp[2]+50),unreal.Vector(oldp[0],oldp[1],oldp[2]-40),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored+[a],unreal.DrawDebugTrace.NONE,True);oldhit=raw.to_tuple() if raw else [False];assert oldhit[0];offset=oldp[2]-float(oldhit[4].z);chosen=None
  for x,y in candidates:
   if any(lo[0]+20<x<hi[0]-20 and lo[1]+20<y<hi[1]-20 for _,lo,hi in buildings):continue
   if any(math.hypot(x-r['root_cm'][0],y-r['root_cm'][1])<(550 if r['actor'].startswith('Immersion_Cherry_Tree_') else 350) for r in roots if not(r['actor']==label and r['instance']==index)):continue
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or not re.fullmatch(r'G\d\d',h[9].get_actor_label()) or not 1190<h[4].z<1210:continue
   z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.))
   if s['blocked']:continue
   chosen=[x,y,z+offset];break
  assert chosen,('No dry,open,spaced tree target',label,index);proposals.append(dict(actor=label,component=c.get_name(),instance=index,before=ground_transform(t),target_cm=chosen,proxy=proxy,preserved_ground_offset_cm=offset));next(r for r in roots if r['actor']==label and r['instance']==index)['root_cm']=chosen
 assert len(proposals)==2 and ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('tree-spacing-plan',dict(status='prepared_native_support_and_spacing_passed',map_sha256=LOAD_SHA,source_alignment_map_sha256=alignment['map_sha256'],moves=proposals,policy='Move two existing green-canopy trees that obscure the first pink pair to the dry promenade entrance shoulders, at least5.5m from new cherries and3.5m from other roots. Preserve all tree count/geometry/materials/rotation/scale/root-ground offsets and synchronize each existing hidden trunk proxy; do not disable collision.'))

def immersion_tree_spacing_install():
 plan=read('tree-spacing-plan');installed=read('install');assert plan['map_sha256']==installed['map_sha256']==LOAD_SHA and not (OUT/'tree-spacing-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-tree-spacing-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);changes=[]
 for r in plan['moves']:
  a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==r['component']);t=c.get_instance_transform(r['instance'],True);assert ground_transform(t)==r['before'];p=r['proxy'];pc=actors[p['actor']].get_components_by_class(unreal.InstancedStaticMeshComponent)[0];pt=pc.get_instance_transform(p['instance'],True);assert math.dist(num(pt.translation),r['before']['translation'])<.01;t.translation=unreal.Vector(*r['target_cm']);pt.translation=unreal.Vector(*r['target_cm']);c.modify();pc.modify();assert c.update_instance_transform(r['instance'],t,True,True,True) and pc.update_instance_transform(p['instance'],pt,True,True,True);changes.extend([dict(actor=r['actor'],component=c.get_name(),instance=r['instance'],after=ground_transform(t)),dict(actor=p['actor'],component=pc.get_name(),instance=p['instance'],after=ground_transform(pt))])
 after=ground_snapshot();lookup={(r['actor'],r['component']):[] for r in changes}
 for r in changes:lookup[(r['actor'],r['component'])].append(r)
 assert len(after)==len(before)
 for old,now in zip(before,after):
  row=json.loads(json.dumps(now));key=(row['actor'],row['component'])
  for r in lookup.get(key,[]):assert row['instances'][r['instance']]==r['after'];row['instances'][r['instance']]=old['instances'][r['instance']]
  assert row==old,('Unintended tree-spacing change',key)
 immersion_door_capsule_probe();immersion_interior_probe();immersion_route_review();assert read('door-capsule-probe')['status']==read('interior-native-probe')['status']==read('route-native-review')['status']=='passed';actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,cherry_foreground_trees_resited=2);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('tree-spacing-install',dict(status='saved_requires_reopen_positive_proxy_and_visual_review',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),plan=plan,changes=changes,policy=plan['policy']))

def immersion_retired_lamp_audit():
 installed=read('lamp-consolidation-install');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};issues=[];checked=0
 for g in installed['plan']['groups']:
  for r in g['source_components']:
   a=actors[r['actor']];c=a.get_component_by_class(unreal.StaticMeshComponent);checked+=1
   if not a.get_editor_property('hidden') or c.is_visible() or not c.get_editor_property('hidden_in_game') or str(c.get_collision_profile_name())!='NoCollision' or c.get_editor_property('cast_hidden_shadow'):issues.append(dict(actor=r['actor'],kind='retired_mesh_still_active'))
  a=actors[g['old_light']['actor']];c=a.light_component
  if not a.get_editor_property('hidden') or c.get_editor_property('affects_world') or 'EnvLumens=0' not in [str(t) for t in a.tags]:issues.append(dict(actor=a.get_actor_label(),kind='retired_light_still_active'))
 assert checked==180 and sha(MAPFILE)==LOAD_SHA;write('lamp-consolidation-audit',dict(status='passed' if not issues else 'requires_repair',map_sha256=LOAD_SHA,retired_meshes=checked,retired_light_actors=36,issues=issues,scope='Reopened current scene: retired duplicate poles cannot render, cast hidden shadows, block players or contribute light. Existing actors retained for recovery.'));assert not issues,issues[:5]

def immersion_polish_cameras():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 def add(name,positions,target,fov=75):
  for x,y in positions:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or not 1190<=h[4].z<=1250 or h[7].z<.9:continue
   z=float(h[4].z);eye=[x,y,z+165];s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.))
   if s['blocked']:continue
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*eye),unreal.Vector(*target),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);los=raw.to_tuple() if raw else [False]
   if los[0] and math.dist(num(los[4]),target)>80:continue
   rows.append(dict(id=name,eye=eye,target=target,fov=fov,ground_cm=z,ground_actor=h[9].get_actor_label(),capsule=s,line_of_sight=dict(blocking=bool(los[0]),hit_actor=los[9].get_actor_label() if los[0] else None),camera_kind='native supported player-height with target line-of-sight'));return True
  return False
 def around(x,y):return [(x+dx,y+dy) for dx,dy in [(500,400),(-500,400),(500,-400),(-500,-400),(0,650),(0,-650),(650,0),(-650,0),(900,500),(-900,500)]]
 for g in read('lamp-consolidation-install')['plan']['groups']:
  p=num(actors[g['upgraded_light']].get_actor_location());assert add('consolidated-'+g['prefix'].rstrip('_'),around(p[0],p[1]),p,70),g['prefix']
 p=num(actors['Environment_PK_0102_1_Light'].get_actor_location());assert add('PK0102-clear-turn-bollard',around(p[0],p[1]),p,75)
 for r in read('layout-cameras')['rows']:
  if r['id'].startswith(('pool-waterline-','cherry-')) or r['id']=='pavilion-roof-clear':assert add(r['id'],[(r['eye'][0],r['eye'][1])]+around(r['target'][0],r['target'][1]),r['target'],r['fov']),r['id']
 for r in read('tree-spacing-plan')['moves']:
  p=list(r['target_cm']);p[2]+=330;assert add('entrance-tree-'+r['actor'],around(p[0],p[1]),p,75)
 assert len(rows)==46 and ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('polish-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,scope='46 supported player views with physical line-of-sight:36 consolidated lamp areas,corrected route-turn bollard,three pool edges,three blossom distances,two resited entrance trees and cleared pavilion roof. Render day/night, then include in final cooked capture.'))

def immersion_gameplay_start_context():
 world=unreal.EditorLevelLibrary.get_editor_world();settings=world.get_world_settings();mode=settings.get_editor_property('default_game_mode');rows=[]
 for a in SUB.get_all_level_actors():
  if isinstance(a,unreal.PlayerStart):rows.append(dict(actor=a.get_actor_label(),transform=actor_xform(a),tags=[str(t) for t in a.tags]))
 info=dict(world_override=mode.get_path_name() if mode else None)
 if mode:
  default=unreal.get_default_object(mode);pawn=default.get_editor_property('default_pawn_class');info['default_pawn_class']=pawn.get_path_name() if pawn else None
 assert ground_snapshot()==read('preservation-after')['components'] and sha(MAPFILE)==LOAD_SHA;write('gameplay-start-context',dict(status='read_only',map_sha256=LOAD_SHA,game_mode=info,player_starts=rows))

def immersion_moon_cameras():
 import datetime
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};before=ground_snapshot();assert before==read('preservation-after')['components'];state=json.loads(actors['CityEnvironmentController'].get_state_json());moon=state['moon'];assert moon['altitude']>10 and moon['discVisibility']>0,('Saved preview clock does not expose moon',state['localDateTime'],moon);direction=moon['direction'];date=datetime.datetime.fromisoformat(state['localDateTime']).strftime('%Y.%m.%d-%H.%M.%S');players=read('outdoor-player-cameras');assert players['map_sha256']==LOAD_SHA;preferred=['PK-0105','PK-0109','PK-0102'];candidates=sorted(players['rows'],key=lambda r:(preferred.index(r['id']) if r['id'] in preferred else 99,r['id']));rows=[]
 for r in candidates:
  eye=r['eye'];target=[eye[i]+direction[i]*50000 for i in range(3)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*eye),unreal.Vector(*target),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
  if h[0]:continue
  rows.append(dict(id='moon-framed-'+r['id'],site=r['id'],eye=eye,target=target,fov=75,hour=state['hour24'],date=date,camera_kind='supported player pose aimed at actual native moon direction;clear physical sky line-of-sight'))
  if len(rows)==3:break
 assert len(rows)==3 and ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('moon-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,native_clock=state,scope='Three actual supported player locations aimed at the moon calculated by the native celestial model at the saved preview date. No clock/geometry/material mutation. Actual Game images still require visual review.'))

def immersion_walker_start_review(save=False):
 world=unreal.EditorLevelLibrary.get_editor_world();starts=[a for a in SUB.get_all_level_actors() if isinstance(a,unreal.PlayerStart)];assert len(starts)==1;start=starts[0];rows=[]
 for x,y in [(55250,57450),(55500,57500),(55250,57500),(55700,57450)]:
  hits=[];blocked=[]
  for dx in range(0,401,25):
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x+dx,y,1380),unreal.Vector(x+dx,y,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or not 1190<=h[4].z<=1215 or h[7].z<.9:break
   hits.append(dict(x=x+dx,y=y,ground_z=float(h[4].z),actor=h[9].get_actor_label()))
  if len(hits)!=17:continue
  for a,b in zip(hits,hits[1:]):
   s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(a['x'],y,a['ground_z']+98),unreal.Vector(b['x'],y,b['ground_z']+98),35.,88.))
   if s['blocked']:blocked.append(s)
  if not blocked:rows.append(dict(location=[x,y,hits[0]['ground_z']+90],yaw=0,straight_walk_cm=400,ground_probes=hits,capsule_sweeps=16));break
 assert rows,'No supported clear main-gate walking spawn';candidate=rows[0];mode=unreal.load_class(None,'/Script/CityEnvironment.CityImmersionGameMode');assert mode;settings=world.get_world_settings();before=ground_snapshot();assert before==read('preservation-after')['components']
 if save:
  installed=read('install');assert installed['map_sha256']==LOAD_SHA and not (OUT/'walker-start-install.json').exists();backup=OUT/('UniversityCity-before-walker-start-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);previous=dict(mode=settings.get_editor_property('default_game_mode').get_path_name() if settings.get_editor_property('default_game_mode') else None,start=actor_xform(start));settings.modify();settings.set_editor_property('default_game_mode',mode);start.modify();start.set_actor_location(unreal.Vector(*candidate['location']),False,False);start.set_actor_rotation(unreal.Rotator(0,0,0),False);assert ground_snapshot()==before;next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,normal_walking_player=True);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=before));write('walker-start-install',dict(status='saved_requires_reopen_actual_gameplay_validation',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),previous=previous,player_start=candidate,game_mode=mode.get_path_name(),policy='Walking character35cm radius88cm halfheight,165cm camera; supported main-gate start. All geometry/interiors unchanged. F7 collision-preserving tour flight; F8 existing time UI.'))
 else:
  assert settings.get_editor_property('default_game_mode')==mode and math.dist(num(start.get_actor_location()),candidate['location'])<.01;assert sha(MAPFILE)==LOAD_SHA and ground_snapshot()==before;write('walker-start-review',dict(status='passed',map_sha256=LOAD_SHA,player_start=candidate,game_mode=mode.get_path_name(),pawn_class=unreal.get_default_object(mode).get_editor_property('default_pawn_class').get_path_name()))

def immersion_walker_start_install():immersion_walker_start_review(True)

def immersion_depth_visibility_probe():
 plan=read('depth-visibility-plan');assert plan['map_sha256']==LOAD_SHA;world=unreal.EditorLevelLibrary.get_editor_world();before=ground_snapshot();assert before==read('preservation-after')['components'];ignored=[a for a in SUB.get_all_level_actors() if a.get_editor_property('hidden')];rows=[]
 for r in plan['rows']:
  p=r['center_cm'];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p[0],p[1],p[2]+400),unreal.Vector(p[0],p[1],p[2]+.25),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);hit=raw.to_tuple() if raw else [False];q=dict(r,status='requires_geometric_or_render_review',blocking_hit=bool(hit[0]))
  if hit[0]:
   a,c=hit[9],hit[10];opaque=False;materials=[]
   if isinstance(c,unreal.StaticMeshComponent):
    for i in range(c.get_num_materials()):
     m=c.get_material(i);chain,base=material_chain(m) if m else ([],None);blend=str(base.get_editor_property('blend_mode')) if base else 'unknown';materials.append(dict(path=m.get_path_name() if m else None,blend=blend))
    opaque=bool(materials) and all('OPAQUE' in m['blend'] for m in materials)
   visible=c.is_visible() and not c.get_editor_property('hidden_in_game') and not a.get_editor_property('hidden');q.update(hit_actor=a.get_actor_label(),hit_component=c.get_name(),hit_cm=num(hit[4]),clearance_cm=float(hit[4].z-p[2]),materials=materials,visible=visible)
   if opaque and visible and hit[4].z>p[2]+.25:q['status']='local_opaque_visible_cover_above_candidate'
  rows.append(q)
 assert len(rows)==len(plan['rows']) and ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;counts={k:sum(r['status']==k for r in rows) for k in sorted(set(r['status'] for r in rows))};write('depth-visibility-probe',dict(status='sampled_requires_remaining_candidate_review',map_sha256=LOAD_SHA,geometry_scan_map_sha256=plan['geometry_scan_map_sha256'],counts=counts,groups=plan['groups'],rows=rows,scope=('Read-only%d local vertical queries across%d horizontal near-plane groups.'%(len(rows),plan['groups']))+'  Hidden actors excluded; only visible fully opaque material components count as local coverage. Collision queries are local supporting evidence,not a render/temporal or unsampled-triangle certificate.'))

def immersion_outdoor_level_probe():
 plan=read('outdoor-level-context');before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for r in plan['rows']:
  actor=actors[r['actor']]
  for index,sample in enumerate(r['samples']):
   p=sample['point_cm'];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p[0],p[1],p[2]+200),unreal.Vector(p[0],p[1],900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);hit=raw.to_tuple() if raw else [False];row=dict(actor=r['actor'],sample=index,geometry_point_cm=p,blocking_hit=bool(hit[0]))
   if hit[0]:
    row.update(hit_actor=hit[9].get_actor_label(),hit_cm=num(hit[4]));ignored=[actor];upper=float(hit[4].z)-.5
    for attempt in range(8):
     raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p[0],p[1],upper),unreal.Vector(p[0],p[1],900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);sub=raw.to_tuple() if raw else [False]
     if not sub[0]:break
     if re.fullmatch(r'G\d\d',sub[9].get_actor_label()) or sub[9].get_actor_label()=='Outdoor_annex_ground':row.update(substrate_actor=sub[9].get_actor_label(),substrate_cm=num(sub[4]),height_above_substrate_cm=float(hit[4].z-sub[4].z));break
     ignored.append(sub[9]);upper=float(sub[4].z)-.5
   rows.append(row)
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('outdoor-level-native',dict(status='read_only_requires_height_review',map_sha256=LOAD_SHA,geometry_scan_map_sha256=plan['geometry_map_sha256'],rows=rows,scope='Native top support and underlying Gxx ground beneath eight major outdoor assemblies. Props can occlude individual samples;actual hit actor and substrate are preserved,not automatically classified as a ground sheet.'))

def _active_park_routes():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];sweeps=[];issues=[]
 for rid,a,b in [('north-south',[84400,66500],[84400,74000]),('east-west',[80600,70600],[88200,70600])]:
  points=[];count=math.ceil(math.dist(a,b)/75)
  for index in range(count+1):
   p=[a[i]+(b[i]-a[i])*index/count for i in range(2)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*p,1380),unreal.Vector(*p,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);hit=raw.to_tuple() if raw else [False];q=dict(route=rid,index=index,xy_cm=p,passed=bool(hit[0]) and 1190<=hit[4].z<=1220 and hit[7].z>.9)
   if hit[0]:q.update(ground_cm=num(hit[4]),actor=hit[9].get_actor_label())
   rows.append(q)
   if not q['passed']:issues.append(q)
   else:points.append(q['ground_cm'])
  if len(points)!=count+1:continue
  for p,q in zip(points,points[1:]):
   s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(p[0],p[1],p[2]+98),unreal.Vector(q[0],q[1],q[2]+98),35.,88.));sweeps.append(dict(route=rid,start=p,end=q,result=s))
   if s['blocked']:issues.append(sweeps[-1])
 return rows,sweeps,issues

def immersion_active_park_plan():
 before=ground_snapshot();assert before==read('preservation-after')['components'];probe=read('outdoor-level-native');assert probe['map_sha256']==LOAD_SHA;active=[r for r in probe['rows'] if r['actor']=='Outdoor_active_park'];assert len(active)==8 and all(r['hit_actor']=='Outdoor_active_park' and r.get('substrate_actor')=='G15' for r in active);actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};actor=actors['Outdoor_active_park'];original_location=actor.get_actor_location();old=num(original_location);assert abs(old[2]-1306.392)<.01;target=[old[0],old[1],1206.];delta=target[2]-old[2];assert -101<delta< -100
 try:
  actor.set_actor_location(unreal.Vector(*target),False,True);rows,sweeps,issues=_active_park_routes()
 finally:actor.set_actor_location(original_location,False,True)
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('active-park-level-plan',dict(status='passed_native_trial' if not issues else 'requires_route_review',map_sha256=LOAD_SHA,actor='Outdoor_active_park',before_cm=old,target_cm=target,delta_z_cm=delta,ground_probes=rows,capsule_sweeps=sweeps,issues=issues,scope='Reversible unsaved translation trial of the complete existing park assembly,matching reading-park datum1206cm. Two public cross-axis routes tested;all unrelated geometry/materials preserved.'))

def immersion_active_park_install():
 plan=read('active-park-level-plan');assert plan['status']=='passed_native_trial' and plan['map_sha256']==LOAD_SHA and not plan['issues'];assert not (OUT/'active-park-level-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actor=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()==plan['actor']);assert math.dist(num(actor.get_actor_location()),plan['before_cm'])<.01;backup=OUT/('UniversityCity-before-active-park-level-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);actor.modify();actor.set_actor_location(unreal.Vector(*plan['target_cm']),False,True);rows,sweeps,issues=_active_park_routes();assert not issues,issues[:3];after=ground_snapshot();assert len(before)==len(after);changed=0
 for a,b in zip(before,after):
  if a['actor']==plan['actor']:
   normalized=json.loads(json.dumps(b));normalized['actor_transform']['location']=a['actor_transform']['location'];normalized['transform']['translation']=a['transform']['translation'];assert normalized==a;assert abs(b['transform']['translation'][2]-a['transform']['translation'][2]-plan['delta_z_cm'])<.01;changed+=1
  else:assert a==b,('Unrelated park-level change',a['actor'])
 assert changed==1;next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');assert installed['map_sha256']==LOAD_SHA;installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,active_park_level_corrected=True);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('active-park-level-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),actor=plan['actor'],before_cm=plan['before_cm'],target_cm=plan['target_cm'],delta_z_cm=plan['delta_z_cm'],ground_probes=rows,capsule_sweeps=sweeps,scope='Only complete Outdoor_active_park actor translated vertically;all mesh assets,UV,materials,internal relative layout and other scene components unchanged. Removes accidental1.00392m elevation and preserves existing surface finish.'))

def immersion_retire_stray_pool_props():
 before=ground_snapshot();assert before==read('preservation-after')['components'];assert not (OUT/'stray-pool-props-install.json').exists();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};targets={'Resort_R036_0_sports-entry':'Changing screen placed loose on school-front grass','Resort_R038_2_sports-entry':'Pool access steps and rails facing a blank school wall with no pool or entrance'};original=[r for r in before if r['actor'] in targets];assert len(original)==2 and all(r['visible'] and not r['hidden'] and not r['actor_hidden'] for r in original);backup=OUT/('UniversityCity-before-stray-pool-props-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for name in targets:
  a=actors[name];a.modify();a.set_actor_hidden_in_game(True)
  for c in a.get_components_by_class(unreal.StaticMeshComponent):c.modify();c.set_collision_profile_name('NoCollision');c.set_visibility(False,True);c.set_hidden_in_game(True,True);c.set_editor_property('cast_hidden_shadow',False)
 after=ground_snapshot();assert len(after)==len(before)
 for a,b in zip(before,after):
  if a['actor'] in targets:
   assert not b['visible'] and b['hidden'] and b['actor_hidden'] and b['collision']=='NoCollision';q=dict(b)
   for field in ['visible','hidden','actor_hidden','collision']:q[field]=a[field]
   assert q==a,('Unexpected retired prop change',a['actor'])
  else:assert a==b,('Unrelated prop retirement change',a['actor'])
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');assert installed['map_sha256']==LOAD_SHA;installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,retired_misplaced_pool_props=2);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('stray-pool-props-install',dict(status='saved_requires_reopen_and_render',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),targets=targets,before_components=original,scope='Retire two disconnected pool-specific display props at school frontage;actors,instances and original assets retained for recovery. All school stairs,room functions and actual pool/hotel/bay equipment unchanged.'))

def immersion_active_park_review():
 before=ground_snapshot();assert before==read('preservation-after')['components'];installed=read('active-park-level-install');actor=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='Outdoor_active_park');assert math.dist(num(actor.get_actor_location()),installed['target_cm'])<.01;rows,sweeps,issues=_active_park_routes();assert len(rows)==204 and len(sweeps)==202 and not issues,issues[:3];routes=[];cameras=[]
 for rid in ['north-south','east-west']:
  points=[r['ground_cm'] for r in rows if r['route']==rid];routes.append(dict(id='active-park-'+rid,kind='outdoor_park',points=points));p,q=points[0],points[min(25,len(points)-1)];eye=[p[0],p[1],p[2]+165];cameras.append(dict(id='active-park-'+rid,eye=eye,target=[q[0],q[1],eye[2]-60],fov=75,camera_kind='supported public park approach from rechecked cross-axis route;165cm optical eye'))
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('active-park-current-review',dict(status='passed',map_sha256=LOAD_SHA,ground_probes=rows,capsule_sweeps=sweeps,routes=routes,cameras=cameras,issues=issues,scope='Reopened level park;two public routes,204 supported points and202 clear capsule segments. Northern route remains2m inside the shoreline;render and actual CharacterMovement traversal are separate requirements.'))

def immersion_fence_dedupe_install():
 import collections
 plan=read('fence-dedupe-plan');assert plan['map_sha256']==LOAD_SHA and plan['duplicate_solids']==16 and not (OUT/'fence-dedupe-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];lookup={(r['actor'],r['component']):r for r in before};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};removed={};components={}
 for r in plan['groups']:
  key=(r['actor'],r['component']);c=next(c for c in actors[r['actor']].get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==r['component']);assert c.static_mesh.get_path_name()==r['mesh'];components[key]=c
  for index,t in r['source_transforms'].items():assert ground_transform(c.get_instance_transform(int(index),True))==t
  removed.setdefault(key,set()).update(r['removed_instances'])
 assert sum(len(v) for v in removed.values())==16;backup=OUT/('UniversityCity-before-fence-dedupe-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for key,indices in removed.items():
  c=components[key];c.modify()
  for index in sorted(indices,reverse=True):assert c.remove_instance(index)
 after=ground_snapshot();assert len(before)==len(after);encode=lambda x:json.dumps(x,sort_keys=True,separators=(',',':'))
 for a,b in zip(before,after):
  key=(a['actor'],a['component'])
  if key in removed:
   expected=[t for i,t in enumerate(a['instances']) if i not in removed[key]];assert collections.Counter(map(encode,expected))==collections.Counter(map(encode,b['instances']));q=dict(b);q['instances']=a['instances'];assert q==a
  else:assert a==b,('Unrelated fence dedupe change',a['actor'])
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed=read('install');assert installed['map_sha256']==LOAD_SHA;installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,duplicate_fence_instances_removed=16);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('fence-dedupe-install',dict(status='saved_requires_reopen_and_rescan',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),removed_instances=[dict(actor=k[0],component=k[1],indices=sorted(v)) for k,v in removed.items()],source_plan_sha256=sha(OUT/'fence-dedupe-plan.json'),scope='Remove only16 complete render-identical duplicate instances. Keep source assets,retained instance transforms/materials,all other scene components and wall continuity. Native ISM index swaps validated by exact transform multiset.'))

def immersion_glazing_probe():
 plan=read('glazing-plan');assert plan['map_sha256']==LOAD_SHA and plan['floors']==plan['glass_floors']==89;before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];issues=[]
 for r in plan['rows']:
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*r['start_cm']),unreal.Vector(*r['end_cm']),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];q=dict(r,passed=False,blocking_hit=bool(h[0]))
  if h[0]:
   c=h[10];q.update(hit_cm=num(h[4]),hit_actor=h[9].get_actor_label(),hit_component=c.get_name(),distance_from_glass_cm=math.dist(num(h[4]),r['target_cm']),profile=str(c.get_collision_profile_name()),pawn_response=str(c.get_collision_response_to_channel(unreal.CollisionChannel.ECC_PAWN)),probe_kind='complete_window_barrier_from_both_outside_sides');q['passed']=h[9]==actors[r['actor']] and c.get_name()==r['component'] and q['distance_from_glass_cm']<=50.01 and 'BLOCK' in q['pawn_response']
  if q['passed']:
   simple_raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*q['start_cm']),unreal.Vector(*q['end_cm']),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,False,[],unreal.DrawDebugTrace.NONE,True);simple=simple_raw.to_tuple() if simple_raw else [False];simple_ok=bool(simple[0]) and simple[9]==actors[r['actor']] and simple[10].get_name()==r['component'] and math.dist(num(simple[4]),q['hit_cm'])<1
   q['simple_shape_passed']=simple_ok;q['passed']=simple_ok
   if not simple_ok:q['simple_shape_hit_cm']=num(simple[4]) if simple[0] else None
  if not q['passed']:issues.append(q)
  rows.append(q)
 assert len(rows)==len(plan['rows']) and ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('glazing-native-probe',dict(status='passed' if not issues else 'requires_repair',map_sha256=LOAD_SHA,floors=89,checks=len(rows),simple_shape_checks_passed=sum(bool(q.get('simple_shape_passed')) for q in rows),pane_reference_hits=sum(q.get('distance_from_glass_cm',1e9)<1 for q in rows),issues=issues,rows=rows,scope=plan['scope']+' Native same-component simple Visibility impact agrees with complex impact within1cm and Pawn response is BLOCK. This proves the tested complete window barriers,not bidirectional backfaces of every isolated glass triangle. No scene mutation.'));assert not issues,dict(failed=len(issues),examples=issues[:3])

def immersion_quality_cameras():
 probe=read('door-capsule-probe');assert probe['status']=='passed' and probe['map_sha256']==LOAD_SHA;world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 def add(name,x,y,z,target,fov=75):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z+60),unreal.Vector(x,y,z-40),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None
  if not h or not h[0] or abs(h[4].z-z)>30:return False
  g=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,g+98),unreal.Vector(x,y,g+99),35.,88.))
  if s['blocked']:return False
  rows.append(dict(id=name,eye=[x,y,g+165],target=target,fov=fov,ground_cm=g,ground_actor=h[9].get_actor_label(),capsule=s,camera_kind='native supported player-height'));return True
 wanted=[('counter-IB-ground','IB-0106-support1-door','Activity_ACTSPACE-08-289'),('counter-AD-ground','AD-0105-support1-door','Activity_ACTSPACE-08-126'),('counter-IB-upper','IB-0506-support1-door','Activity_ACTSPACE-08-309'),('shower-SP-ground','SP-F01-support-A3-door',None),('shower-SP-upper','SP-F05-support-A3-door',None)]
 for name,did,counter in wanted:
  r=next(q for q in probe['rows'] if q['id']==did);a,b=r['start'],r['end'];nx,ny=b[0]-a[0],b[1]-a[1];length=math.hypot(nx,ny);nx/=length;ny/=length;cx,cy=(a[0]+b[0])/2,(a[1]+b[1])/2;z=r['supports'][1]['expected_floor_cm'];target=num(actors[counter].get_actor_bounds(False)[0]) if counter else [75260,21380,z+120]
  if counter:target[2]+=20
  found=False
  for distance in [150,120,100,80,60]:
   if add(name,cx-nx*distance,cy-ny*distance,z,target):found=True;break
  assert found,('No clear real door viewpoint',did)
 assert add('canopy-junction-separated',45900,49350,1200,[45900,49800,1508],80)
 summary=read('depth-candidate-summary');scope=next(s for s in summary['scopes'] if s['scope']=='outdoor-ground')
 for label in ['G06','G07']:
  q=next((g for g in scope['groups'] if g['lod']==0 and g['a_actor']==label and g['b_actor']==label and g['abs_normal_z']>.99 and abs(g['example']['center_cm'][2]-1198)<.02),None)
  if q is None:
   old=next(r for r in read('quality-cameras')['rows'] if r['id']=='terrain-facing-'+label);assert add(old['id'],old['eye'][0],old['eye'][1],old['ground_cm'],old['target'],old['fov']);continue
  x,y,z=q['example']['center_cm'];found=False
  for dx,dy in [(-250,-300),(-250,300),(-400,0),(0,-450),(0,450)]:
   if add('terrain-facing-'+label,x+dx,y+dy,z,[x,y,z+5],75):found=True;break
  assert found,('No supported terrain-facing viewpoint',label)
 assert len(rows)==8 and sha(MAPFILE)==LOAD_SHA;write('quality-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,scope='Eight additional supported player-height views: service counters and showers at ground/upper floors, separated storefront canopy junction, and two deferred terrain-facing boundaries. Capture day/night in actual cooked Game.'))

def immersion_followup_cameras():
 immersion_detail_cameras();detail=read('detail-cameras');assert detail['status']=='passed';players=read('outdoor-player-cameras');assert players['status']=='passed' and players['map_sha256']==LOAD_SHA;rows=list(detail['rows']);world=unreal.EditorLevelLibrary.get_editor_world();issues=[]
 def camera(name,x,y,tx,ty,tz,fov=80):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1340),unreal.Vector(x,y,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
  if not h[0] or not 1190<h[4].z<1230:return False
  z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.))
  if s['blocked']:return False
  rows.append(dict(id=name,eye=[x,y,z+165],target=[tx,ty,tz],fov=fov,actual_ground_cm=z,ground_actor=h[9].get_actor_label(),capsule=s));return True
 assert camera('cherry-alley-entrance',44500,79250,44500,82500,1380,85)
 assert camera('cherry-blossom-close',44500,81400,43920,81500,1580,80)
 assert camera('basketball-full-markings',61800,60000,63500,60000,1350,90)
 wanted=['PK-0101','PK-0103','PK-0104','PK-0105','PK-0111','PK-0112','PK-0116','PK-0117']
 for pid in wanted:
  q=next(r for r in players['rows'] if r['id']==pid);r=dict(q);r['id']='supported-pavilion-'+pid;rows.append(r)
 for i,q in enumerate(read('shore-tree-install')['changes']):
  x,y,z=q['target_cm'];found=False
  for dx,dy in [(500,300),(-500,300),(500,-300),(-500,-300),(0,600),(600,0),(-600,0),(0,-600)]:
   if camera('shore-tree-root-'+str(i+1),x+dx,y+dy,x,y,z+140,75):found=True;break
  assert found,('No dry player viewpoint for relocated shore tree',q['actor'])
 assert len(rows)==22 and not issues;assert sha(MAPFILE)==LOAD_SHA;write('followup-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,issues=issues,scope='22 supported player-height views, including eight pavilion joints, real visible palms, cherry promenade, court markings and relocated shore roots. Capture day/night; no diagnostic aerial substitutes.'))

def immersion_cherry_uplights_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'cherry-uplights-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();backup=OUT/('UniversityCity-before-cherry-uplights-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');opal=EAL.load_asset('/Game/UniversityCity/EnvironmentV1/Materials/M_EnvironmentOpal_01');parts=dict(Metal=[],Opal=[]);lights=[]
 for i,r in enumerate(read('cherry-trees-install')['trees']):
  tx,ty,tz=r['position_cm'];x=tx+(60 if tx<44500 else -60);y=ty-50;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and 1190<h[4].z<1210;g=float(h[4].z);p=[x,y,g+7];target=[tx,ty,tz+490];axis=[target[k]-p[k] for k in range(3)];length=math.sqrt(sum(q*q for q in axis));axis=[q/length for q in axis];rotation=unreal.MathLibrary.make_rot_from_z(unreal.Vector(*axis));lens=[p[k]+axis[k]*11.2 for k in range(3)];parts['Metal'].append(dict(position_cm=p,rotation=rotation,scale=[.12,.12,.22]));parts['Opal'].append(dict(position_cm=lens,rotation=rotation,scale=[.10,.10,.008]));source=[p[k]+axis[k]*11.8 for k in range(3)];a=SUB.spawn_actor_from_class(unreal.SpotLight,unreal.Vector(*source),unreal.MathLibrary.find_look_at_rotation(unreal.Vector(*source),unreal.Vector(*target)));a.set_actor_label('Immersion_Cherry_Uplight_'+str(i));a.tags=[unreal.Name('ImmersionV1'),unreal.Name('EnvGroup=Feature'),unreal.Name('EnvLumens=250')];a.set_folder_path('UniversityCity/ImmersionV1');c=a.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(250);c.set_temperature(3000);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',850);c.set_editor_property('source_radius',10);c.set_editor_property('inner_cone_angle',20);c.set_editor_property('outer_cone_angle',45);c.set_editor_property('volumetric_scattering_intensity',0.);c.set_cast_shadows(False);lights.append(dict(actor=a.get_actor_label(),tree=r['actor'],source_cm=source,target_cm=target,ground_cm=g,lumens=250,kelvin=3000,source_radius_cm=10,cast_shadows=False))
 labels=[]
 for kind,rows in parts.items():
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cylinder'),metal if kind=='Metal' else opal,'FlatCampus_Immersion_Cherry_Uplight_'+kind);assert c;a=c.get_owner();a.set_actor_label('Immersion_Cherry_Uplight_'+kind);a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll' if kind=='Metal' else 'NoCollision');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*r['position_cm']),rotation=r['rotation'],scale=unreal.Vector(*r['scale'])) for r in rows],False,True,True);labels.append(a.get_actor_label())
 after=ground_snapshot();assert [r for r in after if r['actor'] not in labels]==before and len(after)==len(before)+2;controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),cherry_uplights=6);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('cherry-uplights-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),lights=lights,fixture_actors=labels,policy='Six small physical bronze uplight fixtures on grass shoulders illuminate individual blossom crowns with250lm,3000K,large-source light; existing Feature schedule, no local hard shadows or volumetric beams. Keep fixtures clear of the4m promenade and tree stems.'))

def immersion_tree_collision_reconcile():
 installed=read('install');plan=read('tree-collision-plan');shore=read('shore-tree-install');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA;assert not (OUT/'tree-collision-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();oldc=actors['LandscapeV3_TrunkCollision'].get_components_by_class(unreal.InstancedStaticMeshComponent)[0];assert oldc.get_instance_count()==1634 and str(oldc.get_collision_profile_name())=='BlockAll';backup=OUT/('UniversityCity-before-tree-collision-reconcile-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);moved=[]
 for r in shore['changes']:
  p=r['water_base_cm'];matches=[]
  for i in range(oldc.get_instance_count()):
   t=oldc.get_instance_transform(i,True)
   if math.hypot(t.translation.x-p[0],t.translation.y-p[1])<1:matches.append((i,t))
  assert len(matches)==1,('Shore stem proxy not unique',r['actor'],len(matches));i,t=matches[0];original=ground_transform(t);delta=[r['target_cm'][k]-p[k] for k in range(3)];t.translation=t.translation+unreal.Vector(*delta);assert oldc.update_instance_transform(i,t,True,True,True);moved.append(dict(instance=i,before=original,after=ground_transform(t),tree_actor=r['actor'],delta_cm=delta))
 rows=[r for r in plan['rows'] if r['actor'].startswith('Immersion_Cherry_Tree_')];assert len(rows)==6;mesh=EAL.load_asset('/Engine/BasicShapes/Cylinder');mat=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,mesh,mat,'FlatCampus_Immersion_Cherry_StemCollision');assert c;a=c.get_owner();a.set_actor_label('Immersion_Cherry_TrunkColliders');a.tags=[unreal.Name('ImmersionV1'),unreal.Name('ImmersionStemCollisionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cast_shadow(False);c.set_editor_property('cast_hidden_shadow',False);c.set_visibility(False,True);c.set_hidden_in_game(True,True);transforms=[]
 for r in rows:
  t=unreal.Transform(location=unreal.Vector(*r['center_cm']),scale=unreal.Vector(*[v/100 for v in r['size_cm']]));t.rotation=unreal.Quat(*r['rotation']);transforms.append(t)
 c.add_instances(transforms,False,True,True);assert c.get_instance_count()==6;checks=[]
 targets=[(c,t,'new_cherry') for t in transforms]+[(oldc,oldc.get_instance_transform(r['instance'],True),'resited_shore') for r in moved]
 for target,t,kind in targets:
  b=target.static_mesh.get_bounds();p=t.transform_location(b.origin);s=t.scale3d;radius=max(b.box_extent.x*abs(s.x),b.box_extent.y*abs(s.y))+70;success=False;hits=[]
  for dx,dy in [(radius,0),(0,radius),(-radius,0),(0,-radius)]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p.x+dx,p.y+dy,p.z),p,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,False,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];hits.append(h[9].get_actor_label() if h[0] else None)
   if h[0] and h[10]==target:success=True;break
  checks.append(dict(kind=kind,center_cm=num(p),passed=success,hits=hits))
 write('tree-collision-reconcile-preflight',dict(status='passed' if all(r['passed'] for r in checks) else 'requires_review',map_sha256=LOAD_SHA,checks=checks));assert all(r['passed'] for r in checks),checks;immersion_route_review();assert read('route-native-review')['status']=='passed';immersion_interior_probe();assert read('interior-native-probe')['status']=='passed';after=ground_snapshot();assert len(after)==len(before)+1
 for old,now in zip(before,[r for r in after if r['actor']!='Immersion_Cherry_TrunkColliders']):
  row=dict(now)
  if now['actor']=='LandscapeV3_TrunkCollision':
   instances=list(row['instances'])
   for r in moved:assert instances[r['instance']]==r['after'];instances[r['instance']]=old['instances'][r['instance']]
   row['instances']=instances
  assert row==old,('Unexpected stem reconciliation change',now['actor'],now['component'])
 actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),cherry_stem_colliders=6,shore_stem_colliders_resited=3);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('tree-collision-install',dict(status='saved_requires_reopen_and_game_physics_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),retained_existing_stems=1634,existing_proxy_moves=moved,new_stems=rows,native_positive_physics_checks=checks,proxy_actor='Immersion_Cherry_TrunkColliders',rendering=dict(visible=False,hidden_in_game=True,cast_shadow=False,cast_hidden_shadow=False),collision_profile='BlockAll',policy='Preserve all1634 existing LandscapeV3 stem blockers; synchronize only three relocated shore stems and add six new measured cherry blockers. Keep all rendered trees, other proxies, transforms and material bindings unchanged.'))

def immersion_tree_collision_install():
 raise AssertionError('Retired prototype: existing LandscapeV3 stem blockers must be reconciled, not duplicated. Use immersion_tree_collision_reconcile.')
 installed=read('install');plan=read('tree-collision-plan');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA and plan['total']==1281;assert not (OUT/'tree-collision-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];lookup={(r['actor'],r['component']):r for r in before};world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-tree-collision-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for r in plan['rows']:
  s=lookup[(r['actor'],r['component'])];assert s['mesh']==r['source_mesh'] and s['collision']=='NoCollision' and s['visible'] and not s['hidden'] and not s['actor_hidden'];t=s['instances'][r['instance']] if r['instance']>=0 else s['transform'];assert t==r['source_transform']
 mesh=EAL.load_asset('/Engine/BasicShapes/Cylinder');mat=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,mesh,mat,'FlatCampus_Immersion_Tree_StemCollision');assert c;a=c.get_owner();a.set_actor_label('Immersion_Tree_TrunkColliders');a.tags=[unreal.Name('ImmersionV1'),unreal.Name('ImmersionStemCollisionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.set_cast_shadow(False);c.set_editor_property('cast_hidden_shadow',False);c.set_visibility(False,True);c.set_hidden_in_game(True,True);transforms=[]
 for r in plan['rows']:
  t=unreal.Transform(location=unreal.Vector(*r['center_cm']),scale=unreal.Vector(*[v/100 for v in r['size_cm']]));t.rotation=unreal.Quat(*r['rotation']);transforms.append(t)
 c.add_instances(transforms,False,True,True);assert c.get_instance_count()==1281;checks=[];issues=[]
 for index,r in enumerate(plan['rows']):
  p=r['center_cm'];radius=max(r['size_cm'][:2])/2+60;success=False;hits=[]
  for dx,dy in [(radius,0),(0,radius),(-radius,0),(0,-radius)]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p[0]+dx,p[1]+dy,p[2]),unreal.Vector(*p),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,False,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];hits.append(h[9].get_actor_label() if h[0] else None)
   if h[0] and h[10]==c:success=True;break
  row=dict(instance=index,tree_actor=r['actor'],tree_instance=r['instance'],passed=success,hits=hits);checks.append(row)
  if not success:issues.append(row)
 write('tree-collision-preflight',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,checks=len(checks),issues=issues,results=checks));assert not issues,issues[:3];immersion_route_review();assert read('route-native-review')['status']=='passed';immersion_interior_probe();assert read('interior-native-probe')['status']=='passed';after=ground_snapshot();assert [r for r in after if r['actor']!='Immersion_Tree_TrunkColliders']==before and len(after)==len(before)+1;actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),collidable_tree_stems=1281);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('tree-collision-install',dict(status='saved_requires_reopen_and_game_physics_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),trees=1281,campus_trees=plan['campus'],native_positive_physics_checks=len(checks),proxy_actor='Immersion_Tree_TrunkColliders',plan_sha256=sha(OUT/'tree-collision-plan.json'),rendering=dict(visible=False,hidden_in_game=True,cast_shadow=False,cast_hidden_shadow=False),collision_profile='BlockAll',policy=plan['policy']))

def immersion_depth_export():
 before=ground_snapshot();assert before==read('preservation-after')['components'];folder=OUT/('surface-immersion-'+LOAD_SHA[:12]+'-'+PAYLOAD['run_id']);assert not folder.exists();folder.mkdir();result=json.loads(unreal.CityDepthAuditLibrary.export_scene(unreal.EditorLevelLibrary.get_editor_world(),str(folder),True));assert result['status']=='passed',result;assert sha(MAPFILE)==LOAD_SHA and ground_snapshot()==before;write('depth-export',dict(status='passed',map_sha256=LOAD_SHA,folder=str(folder),metadata_sha256=sha(folder/'scene.json'),geometry=result,scope='Read-only native visible scene export with all available LODs and per-triangle material slots; independent depth analysis remains separate.'))

def immersion_cherry_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/Cherries';KEEP=[];save=save_asset;api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);mel=unreal.MaterialEditingLibrary;tools=unreal.AssetToolsHelpers.get_asset_tools();path=PREFIX+'/Materials/M_Blossoms';mat=EAL.load_asset(path) if EAL.does_asset_exist(path) else tools.create_asset('M_Blossoms',PREFIX+'/Materials',unreal.Material,unreal.MaterialFactoryNew());assert mat;mel.delete_all_material_expressions(mat);mat.set_editor_property('used_with_instanced_static_meshes',True);mat.set_editor_property('two_sided',True);mat.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_TWO_SIDED_FOLIAGE);mat.set_editor_property('dithered_lod_transition',True);uv=mel.create_material_expression(mat,unreal.MaterialExpressionTextureCoordinate);vc=mel.create_material_expression(mat,unreal.MaterialExpressionVertexColor);random=mel.create_material_expression(mat,unreal.MaterialExpressionPerInstanceRandom);custom=mel.create_material_expression(mat,unreal.MaterialExpressionCustom);custom.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT3);inputs=[]
 for name in ['UV','C','R']:
  v=unreal.CustomInput();v.set_editor_property('input_name',name);inputs.append(v)
 custom.set_editor_property('inputs',inputs);custom.set_editor_property('code','float t=smoothstep(0.04,0.9,UV.y); float3 pink=lerp(float3(0.58,0.115,0.21),float3(0.94,0.65,0.72),t); float vein=0.96+0.04*cos((UV.x-0.5)*36+UV.y*14); return pink*C*vein*lerp(0.91,1.04,R);');assert mel.connect_material_expressions(uv,'',custom,'UV');assert mel.connect_material_expressions(vc,'',custom,'C');assert mel.connect_material_expressions(random,'',custom,'R');assert mel.connect_material_property(custom,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for value,prop in [(.82,unreal.MaterialProperty.MP_ROUGHNESS),(0.,unreal.MaterialProperty.MP_METALLIC)]:
  n=mel.create_material_expression(mat,unreal.MaterialExpressionConstant);n.set_editor_property('r',value);assert mel.connect_material_property(n,'',prop)
 sub=mel.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector);sub.set_editor_property('constant',unreal.LinearColor(.08,.024,.035,1));assert mel.connect_material_property(sub,'',unreal.MaterialProperty.MP_SUBSURFACE_COLOR);mel.recompile_material(mat);assert EAL.save_loaded_asset(mat,False);bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV2/Materials/M_Bark');green=EAL.load_asset(IMM+'/Palms/Materials/M_Fronds');assert bark and green
 source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)");namespace=dict(globals());exec('def import_one('+source,namespace);import_one=namespace['import_one'];rows=[]
 for aid in ['cherry-a','cherry-b','cherry-c']:
  meshes=[]
  for lod in range(3):
   mesh=import_one(OUT/'cherries'/'assets'/aid/('LOD'+str(lod)+'-source.glb'),aid,lod,False)
   for i,s in enumerate(mesh.get_editor_property('static_materials')):
    name=str(s.get_editor_property('imported_material_slot_name'));assert any(k in name for k in ['Bark','Flowers','Green']);mesh.set_material(i,bark if 'Bark' in name else green if 'Green' in name else mat)
   assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
  mesh=meshes[0]
  for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
  assert api.set_lod_screen_sizes(mesh,[1.,.22,.07]);EAL.set_metadata_tag(mesh,'ImmersionCherry','Open branches; individual notched five-petal blossoms and small leaves; no opaque canopy balls.');assert EAL.save_loaded_asset(mesh,False);bounds=mesh.get_bounds();rows.append(dict(id=aid,asset=mesh.get_path_name(),triangles=[mesh.get_num_triangles(i) for i in range(3)],origin_cm=num(bounds.origin),extent_cm=num(bounds.box_extent),materials=[mesh.get_material(i).get_path_name() for i in range(len(mesh.get_editor_property('static_materials')))]))
 assert sha(MAPFILE)==LOAD_SHA;write('cherry-import',dict(status='passed',map_sha256=LOAD_SHA,assets=rows,blossom_material=mat.get_path_name(),scope='Native imports only; geometry and procedural petal shader authored locally, existing bark PBR and green foliage shader reused.'))

def immersion_cherry_trees_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'cherry-trees-install.json').exists();imported=read('cherry-import');before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-cherry-planting-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);rows=[];labels=[]
 for index,(x,y) in enumerate([(43920,79850),(45080,79850),(43920,81500),(45080,81500),(43920,83150),(45080,83150)]):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and 1190<h[4].z<1210;z=float(h[4].z)-.5;s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+100),unreal.Vector(x,y,z+105),35.,88.));assert not s['blocked'],s;r=imported['assets'][index%3];mesh=EAL.load_asset(r['asset']);yaw=0 if r['extent_cm'][0]<r['extent_cm'][1] else 90;yaw+=180 if index%2 else 0;a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x,y,z),unreal.Rotator(yaw=yaw));a.set_actor_label('Immersion_Cherry_Tree_'+str(index));a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c=a.static_mesh_component;c.set_static_mesh(mesh);c.set_collision_profile_name('NoCollision');labels.append(a.get_actor_label());rows.append(dict(actor=a.get_actor_label(),asset=r['asset'],position_cm=[x,y,z],yaw_deg=yaw,ground_actor=h[9].get_actor_label()))
 after=ground_snapshot();assert [r for r in after if r['actor'] not in labels]==before and len(after)==len(before)+6;actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),promenade_cherry_trees=6);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('cherry-trees-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),trees=rows,policy='Six narrow-crown blossom trees on dry grass shoulders, clear of the4m path, benches, lamp stems and office facades; retain existing office interiors and site furniture. Stem collision is handled by the separate bounded trunk-proxy pass.'))

def immersion_court_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/Court';KEEP=[];save=save_asset;build=json.loads((OUT/'court'/'build.json').read_text('utf8'));assert sha(build['path'])==build['sha256'];source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)");namespace=dict(globals());exec('def import_one('+source,namespace);mesh=namespace['import_one'](OUT/'court'/'court-markings.glb','basketball-markings',0,False);mat=EAL.load_asset('/Game/UniversityCity/StreetScenery/SeparatedFacilities/Source_d12793efcba8576a/Outdoor_white.Outdoor_white')
 if not mat:
  actor=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='World_PK_0113');mat=actor.static_mesh_component.get_material(6)
 assert mat;mesh.set_material(0,mat);assert EAL.save_loaded_asset(mesh,False);b=mesh.get_bounds();assert abs(b.origin.x)<.1 and abs(b.origin.y)<.1 and abs(b.origin.z)<.1;size=num(b.box_extent);yaw=0 if size[1]>size[0] else 90;assert abs(max(size[:2])-1400)<1 and abs(min(size[:2])-660)<1,(size,yaw);assert sha(MAPFILE)==LOAD_SHA;write('court-import',dict(status='passed',map_sha256=LOAD_SHA,asset=mesh.get_path_name(),material=mat.get_path_name(),extent_cm=size,yaw_deg=yaw,triangles=mesh.get_num_triangles(0),source_sha256=build['sha256']))

def immersion_court_details_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'court-detail-install.json').exists();imported=read('court-import');mesh=EAL.load_asset(imported['asset']);assert mesh;before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-court-detail-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(63500,60000,1216),unreal.Rotator(yaw=imported['yaw_deg']));a.set_actor_label('Immersion_Court_Markings');a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c=a.static_mesh_component;c.set_static_mesh(mesh);c.set_collision_profile_name('NoCollision');c.set_cast_shadow(False);lights=[]
 for i,y in enumerate([58375,61625]):
  p=unreal.Vector(64300,y,1809);target=unreal.Vector(63500,60000,1215);a=SUB.spawn_actor_from_class(unreal.SpotLight,p,unreal.MathLibrary.find_look_at_rotation(p,target));a.set_actor_label('Immersion_Court_Light_'+str(i));a.tags=[unreal.Name('ImmersionV1'),unreal.Name('EnvGroup=Sport'),unreal.Name('EnvLumens=6000')];a.set_folder_path('UniversityCity/ImmersionV1');c=a.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(6000);c.set_temperature(4000);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',4000);c.set_editor_property('source_radius',50);c.set_editor_property('inner_cone_angle',45);c.set_editor_property('outer_cone_angle',80);c.set_editor_property('volumetric_scattering_intensity',.1);c.set_cast_shadows(False);lights.append(dict(actor=a.get_actor_label(),position_cm=num(p),target_cm=num(target),lumens=6000,temperature_kelvin=4000,source_radius_cm=50,cast_shadows=False))
 after=ground_snapshot();assert [r for r in after if r['actor']!='Immersion_Court_Markings']==before and len(after)==len(before)+1;controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),court_details=True);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('court-detail-install',dict(status='saved_requires_reopen_depth_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),marking_asset=mesh.get_path_name(),marking_height_cm=1216,blue_surface_top_cm=1213.5,existing_white_top_cm=1214.5,lights=lights,source_reference=json.loads((OUT/'court'/'build.json').read_text('utf8'))['source'],policy='Retain existing blue15x28m court and both existing hoops. Add missing5cm-wide centre circle/three-point/restricted/free-throw/no-charge markings with no internal polygon overlaps. Two soft Sport-scheduled lights sit at existing lamp heads. Do not claim competition certification.'))

def immersion_cherry_walk_install():
 installed=read('install');plan=read('cherry-walk-plan');mp=read('cherry-mesh-plan');assert installed['map_sha256']==plan['map_sha256']==mp['map_sha256']==LOAD_SHA;assert not (OUT/'cherry-walk-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();backup=OUT/('UniversityCity-before-cherry-alignment-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for m in mp['meshes']:
  assert not EAL.does_asset_exist(m['after'])
  for l in m['lods']:assert sha(l['vertices'])==l['sha256']
 result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'cherry-mesh-plan.json')));write('cherry-native-mesh',result);assert result['status']=='passed',result
 material=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly');assert material_chain(material)[1].get_editor_property('used_with_instanced_static_meshes');c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),material,'FlatCampus_Immersion_Cherry_Path');assert c;a=c.get_owner();a.set_actor_label('Immersion_Cherry_Path');a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*q['center']),rotation=unreal.Rotator(roll=q['roll_deg']),scale=unreal.Vector(*[v/100 for v in q['size']])) for q in plan['path_boxes']],False,True,True)
 for q in plan['fixture_moves']:
  a=actors[q['actor']];assert actor_xform(a)==q['before'];a.modify();assert a.set_actor_location(unreal.Vector(*q['target_cm']),False,True)
 floors=[];sweeps=[];issues=[]
 for lane in [-125,0,125]:
  for p,q in zip(plan['walk_points_cm'],plan['walk_points_cm'][1:]):
   a=[p[0]+lane,p[1]];b=[q[0]+lane,q[1]];n=max(1,math.ceil(math.dist(a,b)/50))
   for i in range(n+1):
    xy=[a[k]+(b[k]-a[k])*i/n for k in range(2)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*xy,1240),unreal.Vector(*xy,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];good=bool(h[0]) and h[9].get_actor_label()=='Immersion_Cherry_Path' and 1198<=h[4].z<=1205;row=dict(xy_cm=xy,passed=good,z_cm=float(h[4].z) if h[0] else None,actor=h[9].get_actor_label() if h[0] else None);floors.append(row)
    if not good:issues.append(row)
   s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*a,1304),unreal.Vector(*b,1304),35.,88.));sweeps.append(s)
   if s['blocked']:issues.append(s)
 write('cherry-walk-preflight',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,floors=floors,sweeps=sweeps,issues=issues));assert not issues,issues[:3];after=ground_snapshot();moved={q['actor']:q for q in plan['fixture_moves']};assert len(after)==len(before)+1
 for old,now in zip(before,[r for r in after if r['actor']!='Immersion_Cherry_Path']):
  row=dict(now)
  if now['actor']==plan['actor']:assert row['mesh']==result['meshes'][0]['after'];row['mesh']=old['mesh']
  elif now['actor'] in moved:assert math.dist(row['actor_transform']['location'],moved[now['actor']]['target_cm'])<.01;row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  assert row==old,('Unexpected cherry alignment change',now['actor'],now['component'])
 controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),cherry_promenade_aligned=True);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('cherry-walk-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),mesh=result['meshes'][0]['after'],ground_probes=len(floors),capsule_sweeps=len(sweeps),fixture_moves=plan['fixture_moves'],policy=plan['policy']))

def immersion_cherry_context():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};bounds=[];sweeps=[];floor=[]
 for name,a in actors.items():
  if name.startswith('City_O') and name.endswith('_F01'):
   p,e=a.get_actor_bounds(False);bounds.append(dict(actor=name,center_cm=num(p),extent_cm=num(e)))
 for direction,p,q in [('old-longitudinal',[42300,81500],[46700,81500]),('north-south',[44500,79200],[44500,83800])]:
  for i in range(0,int(math.dist(p,q)),100):
   length=math.dist(p,q);a=[p[k]+(q[k]-p[k])*i/length for k in range(2)];b=[p[k]+(q[k]-p[k])*min(i+100,length)/length for k in range(2)];s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*a,1304),unreal.Vector(*b,1304),35.,88.));sweeps.append(dict(direction=direction,start_cm=a,end_cm=b,result=s))
 for x in [43800,44000,44200,44500,44800,45000,45200]:
  for y in range(79200,83801,200):
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1340),unreal.Vector(x,y,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,1304),unreal.Vector(x,y,1305),35.,88.));floor.append(dict(xy_cm=[x,y],z_cm=float(h[4].z) if h[0] else None,actor=h[9].get_actor_label() if h[0] else None,capsule=s))
 fixtures=[dict(actor=n,transform=actor_xform(a),center_cm=num(a.get_actor_bounds(False)[0]),extent_cm=num(a.get_actor_bounds(False)[1])) for n,a in actors.items() if n.startswith('Environment_PK_0109_')];assert sha(MAPFILE)==LOAD_SHA;write('cherry-context',dict(status='recorded',map_sha256=LOAD_SHA,offices=bounds,sweeps=sweeps,floors=floor,fixtures=fixtures,scope='Read-only actual PK0109 cherry-walk corridor geometry; AABBs only context, native capsule and support rays determine traversability.'))

def immersion_pavilion_supports_install():
 installed=read('install');plan=read('pavilion-support-plan');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA and len(plan['rows'])==8;assert not (OUT/'pavilion-support-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-pavilion-supports-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);labels=[];materials={};ats=unreal.AssetToolsHelpers.get_asset_tools()
 def instanced_material(m):
  p=m.get_path_name()
  if p in materials:return materials[p]
  chain,base=material_chain(m)
  if base.get_editor_property('used_with_instanced_static_meshes'):materials[p]=m;return m
  dest=IMM+'/PavilionSupports/Materials/'+('M_' if isinstance(m,unreal.Material) else 'MI_')+hashlib.sha256(p.encode()).hexdigest()[:16];copy=EAL.load_asset(dest) if EAL.does_asset_exist(dest) else EAL.duplicate_asset(p,dest);assert copy
  if isinstance(copy,unreal.Material):copy.set_editor_property('used_with_instanced_static_meshes',True);unreal.MaterialEditingLibrary.recompile_material(copy)
  else:unreal.MaterialEditingLibrary.set_material_instance_parent(copy,instanced_material(m.get_editor_property('parent')));unreal.MaterialEditingLibrary.update_material_instance(copy)
  assert EAL.save_loaded_asset(copy,False);materials[p]=copy;return copy
 for q in plan['rows']:
  a=actors[q['actor']];c=next(c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==q['component']);assert c.static_mesh.get_path_name()==q['current_mesh'];mat=instanced_material(EAL.load_asset(q['material']));assert material_chain(mat)[1].get_editor_property('used_with_instanced_static_meshes');label='Immersion_Pavilion_'+q['actor'].replace('World_','');assert label not in actors
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),mat,'FlatCampus_'+label);assert c;a=c.get_owner();a.set_actor_label(label);a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*b['center']),scale=unreal.Vector(*[v/100 for v in b['size']])) for b in q['boxes']],False,True,True);assert c.get_instance_count()==8;labels.append(label)
 after=ground_snapshot();assert [r for r in after if r['actor'] not in labels]==before and len(after)==len(before)+8;actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),pavilions_supported=8);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('pavilion-support-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),actors=labels,parts=64,measured_roof_gaps_cm={q['actor']:[p['gap_cm'] for p in q['pillars']] for q in plan['rows']},material_bindings={p:m.get_path_name() for p,m in materials.items()},policy=plan['policy']))

def immersion_shore_trees_install():
 installed=read('install');plan=read('shore-tree-plan');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA and len(plan['rows'])==3;assert not (OUT/'shore-tree-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-shore-trees-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);changed={}
 for q in plan['rows']:
  a=actors[q['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==q['component']);t=c.get_instance_transform(q['instance'],True);assert ground_transform(t)==q['before'];t.translation=unreal.Vector(*q['target_cm']);assert c.update_instance_transform(q['instance'],t,True,True,True);changed[(q['actor'],q['component'])]=q
 after=ground_snapshot();assert len(before)==len(after)
 for old,now in zip(before,after):
  row=dict(now);key=(old['actor'],old['component'])
  if key in changed:
   q=changed[key];instances=list(row['instances']);original=old['instances'][q['instance']];assert math.dist(instances[q['instance']]['translation'],q['target_cm'])<.01 and instances[q['instance']]['rotation']==original['rotation'] and instances[q['instance']]['scale']==original['scale'];instances[q['instance']]=original;row['instances']=instances
  assert row==old,('Unintended shore tree edit',key)
 actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,shore_trees_resited=3);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('shore-tree-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=plan['rows'],policy=plan['policy']))

def immersion_outdoor_player_cameras():
 probe=read('outdoor-floor-probe');assert probe['map_sha256']==LOAD_SHA;world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];issues=[]
 for site in probe['rows']:
  name=site['actor'];pid='PK-0114' if name=='Outdoor_stadium' else 'PK-0115' if name=='Outdoor_campus_track' else name.replace('World_PK_','PK-');center=site['origin_cm'];chosen=None;tried=[]
  if name=='World_PK_0109' and 'Immersion_Cherry_Path' in actors:
   x,y,z=44500,80100,1204;s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.));assert not s['blocked'];rows.append(dict(id=pid,actor=name,eye=[x,y,z+165],target=[44500,82500,1330],fov=85,camera_kind='native supported player-height',ground_cm=z,ground_actor='Immersion_Cherry_Path',capsule=s));continue
  for p in sorted(site['samples'],key=lambda p:-math.dist(p['xy_cm'],center[:2])):
   if not p.get('owner_hit'):continue
   x,y=p['xy_cm'];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1340),unreal.Vector(x,y,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0] or abs(h[4].z-p['owner_z_cm'])>2:continue
   z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.));tried.append(dict(xy_cm=[x,y],result=s))
   if s['blocked']:continue
   target=[center[0],center[1],z+130]
   if math.dist([x,y],center[:2])<150:target[1]+=500
   chosen=dict(id=pid,actor=name,eye=[x,y,z+165],target=target,fov=85,camera_kind='native supported player-height',ground_cm=z,ground_actor=h[9].get_actor_label(),capsule=s);break
  if chosen:rows.append(chosen)
  else:issues.append(dict(id=pid,actor=name,tried=tried))
 previous=json.loads((OUT/'captures.json').read_text('utf8'));old=next(q for q in previous['images'] if q['id']=='PK-0102-day');x,y=old['eye'][:2];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1340),unreal.Vector(x,y,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0];z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.))
 if not s['blocked']:rows.append(dict(id='PK-0102',actor='Depth-repaired fountain plaza',eye=[x,y,z+165],target=old['target'],fov=old['fov'],camera_kind='native supported player-height',ground_cm=z,ground_actor=h[9].get_actor_label(),capsule=s))
 else:issues.append(dict(id='PK-0102',reason='Prior fountain camera blocked',result=s))
 assert sha(MAPFILE)==LOAD_SHA;write('outdoor-player-cameras',dict(status='passed' if not issues and len(rows)==20 else 'requires_review',map_sha256=LOAD_SHA,rows=rows,issues=issues,scope='All20 outdoor sites from native supported player-height capsule-clear positions. Elevated diagnostic images are separate and cannot substitute for player-height acceptance.'))

def immersion_shore_tree_plan():
 probe=read('tree-ground-probe');assert probe['map_sha256']==LOAD_SHA;world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];alltrees=[q['base_cm'] for q in probe['rows']];routepoints=[p for r in read('campus-route-plan')['routes'] for p in r['points_cm']]
 for q in probe['suspects']:
  if not q.get('water_bed'):continue
  p=q['base_cm'];candidates=[]
  for radius in range(150,2101,150):
   for k in range(24):
    angle=k*math.pi/12;x=p[0]+radius*math.cos(angle);y=p[1]+radius*math.sin(angle)
    if any(math.hypot(x-v[0],y-v[1])<220 for v in alltrees if math.dist(p[:2],v[:2])>1):continue
    if any(math.hypot(x-v[0],y-v[1])<200 for v in routepoints):continue
    ignored=[actors[q['actor']]];h=None
    for attempt in range(12):
     raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1400),unreal.Vector(x,y,900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);hit=raw.to_tuple() if raw else [False]
     if not hit[0]:break
     if re.fullmatch(r'G\d\d',hit[9].get_actor_label()):h=hit;break
     ignored.append(hit[9])
    if not h or not 1190<h[4].z<1210:continue
    z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+100),unreal.Vector(x,y,z+105),80.,88.))
    if s['blocked']:continue
    # Nearby support points keep the trunk clear of a sharp bank edge.
    good=True
    for dx,dy in [(80,0),(-80,0),(0,80),(0,-80)]:
     raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x+dx,y+dy,1250),unreal.Vector(x+dx,y+dy,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[actors[q['actor']]],unreal.DrawDebugTrace.NONE,True);hit=raw.to_tuple() if raw else [False]
     if not hit[0] or abs(hit[4].z-z)>5:good=False;break
    if good:candidates.append(dict(position_cm=[x,y,z-.8],distance_cm=radius,ground_actor=h[9].get_actor_label(),capsule=s))
   if candidates:break
  assert candidates,('No dry bank location',q['actor'],q['instance']);chosen=candidates[0];rows.append(dict(actor=q['actor'],component=q['component'],instance=q['instance'],before=q['transform'],water_base_cm=p,water_bed_cm=q['ground_cm'],target_cm=chosen['position_cm'],native_support=chosen))
 assert len(rows)==3;assert sha(MAPFILE)==LOAD_SHA;write('shore-tree-plan',dict(status='prepared_requires_visual_and_native_install',map_sha256=LOAD_SHA,rows=rows,policy='Relocate only the three confirmed water-bed tree roots onto nearby supported dry banks; retain mesh, yaw, scale, material and collision. No broad changes from aggregate LOD bounds or raised planter heights.'))

def immersion_tree_ground_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];issues=[]
 for a in SUB.get_all_level_actors():
  if a.get_editor_property('hidden'):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or not c.get_editor_property('visible') or c.get_editor_property('hidden_in_game'):continue
   mesh=c.static_mesh;p=mesh.get_path_name()
   if not any(q in p for q in ['/TreeUpgradeV2/Assets/',IMM+'/LandscapeLOD/',IMM+'/Evergreens/',IMM+'/Palms/Assets/']):continue
   bounds=mesh.get_bounds();minz=bounds.origin.z-bounds.box_extent.z;transforms=[c.get_instance_transform(i,True) for i in range(c.get_instance_count())] if isinstance(c,unreal.InstancedStaticMeshComponent) else [c.get_world_transform()]
   for index,t in enumerate(transforms):
    # Authored geometric trunk starts at local zero. Aggregate bounds also include
    # low billboard impostor cards and are not a trunk-ground measurement.
    base=t.transform_location(unreal.Vector(0,0,0));ignored=[a];hit=None
    for attempt in range(12):
     raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(base.x,base.y,max(base.z+100,1500)),unreal.Vector(base.x,base.y,-2000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
     if not h[0]:break
     if re.fullmatch(r'G\d\d',h[9].get_actor_label()):hit=h;break
     ignored.append(h[9])
    row=dict(actor=a.get_actor_label(),component=c.get_name(),mesh=p,instance=index if isinstance(c,unreal.InstancedStaticMeshComponent) else None,base_cm=num(base),aggregate_bounds_min_z_cm=float(minz),transform=ground_transform(t),campus=54800<base.x<97000 and 19500<base.y<77000)
    if hit:row.update(ground_cm=float(hit[4].z),ground_actor=hit[9].get_actor_label(),gap_cm=float(base.z-hit[4].z),water_bed=hit[4].z<1095)
    else:row['missing_terrain']=True
    rows.append(row)
    if not hit or abs(row['gap_cm'])>10:issues.append(row)
 assert sha(MAPFILE)==LOAD_SHA;write('tree-ground-probe',dict(status='recorded_requires_review',map_sha256=LOAD_SHA,trees=len(rows),suspects=issues,rows=rows,scope='Read-only trunk base to native terrain; water-bed trees require shore relocation rather than sinking to the water bed. No scene mutations.'))

def immersion_detail_cameras():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];issues=[];actors=SUB.get_all_level_actors()
 def camera(name,x,y,tx,ty,tz,fov=75):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1280),unreal.Vector(x,y,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
  if not h[0]:issues.append(dict(id=name,reason='No supported player camera',xy_cm=[x,y]));return False
  z=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+98),unreal.Vector(x,y,z+99),35.,88.))
  if s['blocked']:issues.append(dict(id=name,reason='Player capsule obstructed',result=s));return False
  rows.append(dict(id=name,eye=[x,y,z+165],target=[tx,ty,tz],fov=fov,actual_ground_cm=z,ground_actor=h[9].get_actor_label(),capsule=s));return True
 camera('plaza-level-entry',53800,70000,54800,70000,1350)
 camera('fishing-bank-walk',26650,83150,26650,84250,1320)
 camera('fishing-level-deck',27400,84250,28500,84250,1300)
 camera('track-lane-close',65200,32000,64400,32000,1229)
 camera('track-field-lines',64600,33000,60600,30000,1229)
 palms=[]
 for a in actors:
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if a.get_editor_property('hidden') or not c.get_editor_property('visible') or c.get_editor_property('hidden_in_game') or not c.static_mesh or not c.static_mesh.get_path_name().startswith(IMM+'/Palms/Assets/'):continue
   transforms=[c.get_instance_transform(i,True) for i in range(c.get_instance_count())] if isinstance(c,unreal.InstancedStaticMeshComponent) else [c.get_world_transform()]
   for t in transforms:
    p=num(t.translation)
    if not (20000<p[0]<105000 and 17500<p[1]<90000) or any(math.dist(p[:2],q[:2])<10000 for q in palms):continue
    found=False
    for dx,dy in [(500,300),(-500,300),(500,-300),(-500,-300)]:
     old=len(issues)
     if camera('palm-crown-'+str(len(palms)+1),p[0]+dx,p[1]+dy,p[0],p[1],p[2]+550,65):palms.append(p);found=True;break
     del issues[old:]
    if len(palms)==3:break
   if len(palms)==3:break
  if len(palms)==3:break
 assert sha(MAPFILE)==LOAD_SHA;write('detail-cameras',dict(status='passed' if not issues and len(palms)==3 else 'requires_review',map_sha256=LOAD_SHA,rows=rows,issues=issues,palms_selected=palms,scope='Supported player-height native capsule-checked views of platform repairs, measured track markings and three new palm crowns.'));assert len(palms)==3,('No three supported palm viewpoints',len(palms),issues)

def immersion_palm_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/Palms';KEEP=[];save=save_asset;api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);mel=unreal.MaterialEditingLibrary;assettools=unreal.AssetToolsHelpers.get_asset_tools();path=PREFIX+'/Materials/M_Fronds';mat=EAL.load_asset(path) if EAL.does_asset_exist(path) else assettools.create_asset('M_Fronds',PREFIX+'/Materials',unreal.Material,unreal.MaterialFactoryNew());assert mat;mel.delete_all_material_expressions(mat);mat.set_editor_property('used_with_instanced_static_meshes',True);mat.set_editor_property('two_sided',True);mat.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_TWO_SIDED_FOLIAGE);mat.set_editor_property('dithered_lod_transition',True)
 uv=mel.create_material_expression(mat,unreal.MaterialExpressionTextureCoordinate);vc=mel.create_material_expression(mat,unreal.MaterialExpressionVertexColor);random=mel.create_material_expression(mat,unreal.MaterialExpressionPerInstanceRandom);custom=mel.create_material_expression(mat,unreal.MaterialExpressionCustom);custom.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT3);inputs=[]
 for name in ['UV','C','R']:
  v=unreal.CustomInput();v.set_editor_property('input_name',name);inputs.append(v)
 custom.set_editor_property('inputs',inputs);custom.set_editor_property('code','float midrib=1-smoothstep(0.018,0.045,abs(UV.x-0.5)); float grain=0.94+0.06*sin(UV.y*160+UV.x*12); return C*lerp(0.88,1.08,R)*grain*lerp(float3(0.055,0.20,0.026),float3(0.09,0.255,0.038),midrib);');assert mel.connect_material_expressions(uv,'',custom,'UV'),'Palm UV connection';assert mel.connect_material_expressions(vc,'',custom,'C'),'Palm vertex color connection';assert mel.connect_material_expressions(random,'',custom,'R'),'Palm per-instance connection';assert mel.connect_material_property(custom,'',unreal.MaterialProperty.MP_BASE_COLOR),'Palm base connection'
 for value,prop in [(.76,unreal.MaterialProperty.MP_ROUGHNESS),(0.,unreal.MaterialProperty.MP_METALLIC)]:
  n=mel.create_material_expression(mat,unreal.MaterialExpressionConstant);n.set_editor_property('r',value);assert mel.connect_material_property(n,'',prop)
 sub=mel.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector);sub.set_editor_property('constant',unreal.LinearColor(.026,.068,.013,1));assert mel.connect_material_property(sub,'',unreal.MaterialProperty.MP_SUBSURFACE_COLOR);mel.recompile_material(mat);assert EAL.save_loaded_asset(mat,False)
 source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)");namespace=dict(globals());exec('def import_one('+source,namespace);import_one=namespace['import_one'];bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV2/Materials/M_Bark');rows=[]
 for aid in ['palm-a','palm-b','palm-c']:
  meshes=[]
  for lod in range(3):
   mesh=import_one(OUT/'palms'/'assets'/aid/('LOD'+str(lod)+'-source.glb'),aid,lod,False)
   for i,s in enumerate(mesh.get_editor_property('static_materials')):
    name=str(s.get_editor_property('imported_material_slot_name'));assert 'Bark' in name or 'Flowers' in name;mesh.set_material(i,bark if 'Bark' in name else mat)
   assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
  mesh=meshes[0]
  for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
  assert api.set_lod_screen_sizes(mesh,[1.,.20,.065]);EAL.set_metadata_tag(mesh,'ImmersionPalm','Three geometric pinnate frond LODs; individual tapered leaflets, crown spears and per-instance foliage variation.');assert EAL.save_loaded_asset(mesh,False);rows.append(dict(id=aid,asset=mesh.get_path_name(),triangles=[mesh.get_num_triangles(i) for i in range(3)],materials=[mesh.get_material(i).get_path_name() for i in range(len(mesh.get_editor_property('static_materials')))]))
 assert sha(MAPFILE)==LOAD_SHA;write('palm-import',dict(status='passed',map_sha256=LOAD_SHA,assets=rows,frond_material=mat.get_path_name(),scope='Native import only; no scene mutations. Existing bark PBR reused; frond geometry and procedural midrib shader authored locally.'))

def immersion_palm_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'palm-install.json').exists();imported=read('palm-import');before=ground_snapshot();assert before==read('preservation-after')['components'];backup=OUT/('UniversityCity-before-palms-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);changes=[]
 for a in SUB.get_all_level_actors():
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or c.static_mesh.get_path_name()!=IMM+'/LandscapeLOD/SM_palm.SM_palm':continue
   name=c.get_name();old=c.static_mesh.get_path_name();instanced=isinstance(c,unreal.InstancedStaticMeshComponent);transforms=[c.get_instance_transform(i,True) for i in range(c.get_instance_count())] if instanced else [];assert str(c.get_collision_profile_name())=='NoCollision';index=int(hashlib.sha256((a.get_actor_label()+'|'+name).encode()).hexdigest()[:8],16)%3;r=imported['assets'][index];mesh=EAL.load_asset(r['asset']);c.modify();c.set_static_mesh(mesh);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name);c.set_editor_property('override_materials',[EAL.load_asset(p) for p in r['materials']]);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name)
   if instanced and [ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]!=[ground_transform(t) for t in transforms]:c.clear_instances();c.add_instances(transforms,False,True,True)
   if instanced:assert [ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]==[ground_transform(t) for t in transforms]
   changes.append(dict(actor=a.get_actor_label(),component=name,before=old,after=r['asset'],materials=r['materials'],trees=len(transforms) if instanced else 1))
 assert len(changes)==49 and sum(q['trees'] for q in changes)==352;after=ground_snapshot();changed={(q['actor'],q['component']):q for q in changes};assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now);key=(old['actor'],old['component'])
  if key in changed:assert row['mesh']==changed[key]['after'] and row['materials']==changed[key]['materials'];row['mesh']=old['mesh'];row['materials']=old['materials']
  assert row==old,('Unexpected palm change',key)
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,palm_components=49,palm_instances=352);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('palm-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=changes,components=49,trees=352,policy='Keep every palm transform, instance, visibility and NoCollision profile; replace sparse strip fronds with three geometric crown variants and dedicated two-sided foliage shader.'))

def immersion_palm_review():
 rows=[]
 for a in SUB.get_all_level_actors():
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   p=c.static_mesh.get_path_name()
   if not (p.startswith(IMM+'/LandscapeLOD/SM_palm') or '/TreeUpgradeV2/Assets/palm/' in p):continue
   rows.append(dict(actor=a.get_actor_label(),component=c.get_name(),mesh=p,collision=str(c.get_collision_profile_name()),instances=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else 1,materials=[c.get_material(i).get_path_name() if c.get_material(i) else None for i in range(c.get_num_materials())]))
 write('palm-review',dict(status='recorded',map_sha256=LOAD_SHA,rows=rows))

def immersion_track_depth_install():
 installed=read('install');plan=read('track-depth-plan');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA;assert not (OUT/'track-depth-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();backup=OUT/('UniversityCity-before-track-depth-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for m in plan['meshes']:
  assert not EAL.does_asset_exist(m['after'])
  for l in m['lods']:assert sha(l['vertices'])==l['sha256']
 result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'track-depth-plan.json')));write('track-depth-native',result);assert result['status']=='passed',result;after=ground_snapshot();assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now)
  if now['actor']==plan['actor']:assert row['mesh']==result['meshes'][0]['after'];row['mesh']=old['mesh']
  assert row==old,('Unexpected track depth change',now['actor'],now['component'])
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,track_depth_separation_cm=2);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('track-depth-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),mesh=result['meshes'][0]['after'],changes=plan['changes'],proven_defect=plan['proven_defect'],policy='Original rubber/turf materials, dimensions, actor transform, furniture, goals and collision profile retained; raise only measured low white marking vertices.'))

def immersion_remaining_platforms_install():
 installed=read('install');plan=read('remaining-platform-plan');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA;assert not (OUT/'remaining-platform-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();backup=OUT/('UniversityCity-before-remaining-platforms-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 def terrain(x,y):
  ignored=[actors[q['actor']] for q in plan['platforms']]
  for attempt in range(20):
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1280),unreal.Vector(x,y,500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0],(x,y)
   if re.fullmatch(r'G\d\d',h[9].get_actor_label()):return float(h[4].z)
   ignored.append(h[9])
  raise AssertionError(('No terrain',x,y))
 stone=list(plan['groups']['Stone']);piers=[]
 for x,y in plan['bridge_pier_xy_cm']:
  ground=min(terrain(x+dx,y+dy) for dx in [-16,16] for dy in [-16,16]);bottom=ground-8;assert bottom<1202;stone.append(dict(center=[x,y,(bottom+1202)/2],size=[30,30,1202-bottom]));piers.append(dict(xy_cm=[x,y],bottom_cm=bottom))
 result=[]
 for q in plan['platforms']:
  a=actors[q['actor']];assert actor_xform(a)==q['actor_before'];mp=read('platform-'+q['id']+'-mesh-plan');assert mp['map_sha256']==LOAD_SHA
  for m in mp['meshes']:
   assert not EAL.does_asset_exist(m['after'])
   for l in m['lods']:assert sha(l['vertices'])==l['sha256']
  res=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/('platform-'+q['id']+'-mesh-plan.json'))));write('platform-'+q['id']+'-native',res);assert res['status']=='passed',res;assert a.set_actor_location(unreal.Vector(*q['actor_after']['location']),False,True);result.append(res)
 mats=dict(Stone=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly'),Metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze'));labels=[]
 for kind,rows in [('Stone',stone),('Metal',plan['groups']['Metal'])]:
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),mats[kind],'FlatCampus_Immersion_Fishing_'+kind);assert c;a=c.get_owner();a.set_actor_label('Immersion_Fishing_'+kind);a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in rows],False,True,True);labels.append(a.get_actor_label())
 moves=[]
 for pid,index,x,y in [('0101',0,53900,69100),('0101',1,55280,71050),('0108',0,26560,83900),('0108',1,28650,84250)]:
  prefix='Environment_PK_'+pid+'_'+str(index)+'_';foot=actors[prefix+'Foot'];origin,extent=foot.get_actor_bounds(False);delta=[x-origin.x,y-origin.y,1206+.2-(origin.z-extent.z)]
  for label,a in actors.items():
   if not label.startswith(prefix):continue
   p=num(a.get_actor_location());target=[p[i]+delta[i] for i in range(3)];a.modify();assert a.set_actor_location(unreal.Vector(*target),False,True);moves.append(dict(actor=label,target_cm=target))
 assert len(moves)==24
 floors=[];sweeps=[];issues=[]
 for pid,points in plan['walks'].items():
  for k,(p,q) in enumerate(zip(points,points[1:])):
   n=max(1,math.ceil(math.dist(p,q)/50))
   for i in range(n+1):
    xy=[p[j]+(q[j]-p[j])*i/n for j in range(2)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*xy,1240),unreal.Vector(*xy,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];good=bool(h[0]) and 1197<=h[4].z<=1207;row=dict(platform=pid,segment=k,xy_cm=xy,passed=good,hit_cm=num(h[4]) if h[0] else None);floors.append(row)
    if not good:issues.append(row)
   s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*p,1304),unreal.Vector(*q,1304),35.,88.));sweeps.append(dict(platform=pid,segment=k,result=s))
   if s['blocked']:issues.append(sweeps[-1])
 write('remaining-platform-preflight',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,floors=floors,sweeps=sweeps,issues=issues));assert not issues,issues[:3]
 after=ground_snapshot();oldrows={(r['actor'],r['component']):r for r in before};changed={q['actor']:q for q in plan['platforms']};moved={q['actor']:q for q in moves}
 for now in after:
  if now['actor'] in labels:continue
  old=oldrows[(now['actor'],now['component'])];row=dict(now)
  if now['actor'] in changed:
   q=changed[now['actor']];assert row['mesh'].startswith(q['asset']+'.') and math.dist(row['actor_transform']['location'],q['actor_after']['location'])<.01;row['mesh']=old['mesh'];row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  elif now['actor'] in moved:
   assert math.dist(row['actor_transform']['location'],moved[now['actor']]['target_cm'])<.01;row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  assert row==old,('Unintended platform edit',now['actor'],now['component'])
 assert len(after)==len(before)+2;controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),remaining_platforms_leveled=2);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('remaining-platform-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),platforms=plan['platforms'],new_support_piers=piers,fixture_moves=moves,floor_probes=len(floors),capsule_sweeps=len(sweeps),policy=plan['policy']))

def immersion_fishing_bank_review():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};a=actors['World_PK_0108'];rows=[]
 for x in range(24500,30501,250):
  for y in range(81500,87001,250):
   ignored=[a];hits=[]
   for attempt in range(12):
    raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1350),unreal.Vector(x,y,500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
    if not h[0]:break
    name=h[9].get_actor_label();hits.append(dict(actor=name,z_cm=float(h[4].z)));ignored.append(h[9])
    if re.fullmatch(r'G\d\d',name):break
   rows.append(dict(xy_cm=[x,y],hits=hits))
 buildings=[]
 for name,b in actors.items():
  if not name.startswith('Campus_') or not name.endswith('_F01'):continue
  p,e=b.get_actor_bounds(False)
  if abs(p.x-28000)<10000 and abs(p.y-84250)<10000:buildings.append(dict(actor=name,center_cm=num(p),extent_cm=num(e)))
 write('fishing-bank-review',dict(status='recorded',map_sha256=LOAD_SHA,grid=rows,buildings=buildings))

def immersion_outdoor_support_review():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};roots={};ground=[];road=[]
 def terrain(x,y,ignore):
  ignored=list(ignore)
  for attempt in range(20):
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1350),unreal.Vector(x,y,500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0]:return dict(xy_cm=[x,y],missing=True)
   name=h[9].get_actor_label()
   if re.fullmatch(r'G\d\d',name):return dict(xy_cm=[x,y],ground_cm=float(h[4].z),actor=name)
   ignored.append(h[9])
  raise AssertionError(('terrain hidden',x,y))
 for pid in ['0101','0108']:
  a=actors['World_PK_'+pid];g=read('water-platform-'+pid+'-geometry');parts=g['paving_parts'];rows=[]
  for p in parts:
   if p['triangles']!=10:continue
   x=(p['min_cm'][0]+p['max_cm'][0])/2;y=(p['min_cm'][1]+p['max_cm'][1])/2;corners=[terrain(x+dx,y+dy,[a]) for dx in [-16,16] for dy in [-16,16]];assert all('ground_cm' in q for q in corners)
   rows.append(dict(part=p['id'],xy_cm=[x,y],corners=corners,foundation_base_cm=min(q['ground_cm'] for q in corners)-8))
  origin,extent=a.get_actor_bounds(False);near=[]
  for label,q in actors.items():
   if q==a or not (label.startswith('Environment_PK_'+pid) or label.startswith('Activity_') or label.startswith('Resort_')):continue
   p=q.get_actor_location()
   if label.startswith('Environment_PK_'+pid) or (abs(p.x-origin.x)<extent.x+200 and abs(p.y-origin.y)<extent.y+200):near.append(dict(actor=label,transform=actor_xform(q),bounds_origin_cm=num(q.get_actor_bounds(False)[0]),bounds_extent_cm=num(q.get_actor_bounds(False)[1])))
  roots[pid]=dict(actor_before=actor_xform(a),source_mesh=a.static_mesh_component.static_mesh.get_path_name(),piers=rows,nearby=near)
 for x in range(52500,54101,50):
  ignored=[];hits=[]
  for attempt in range(8):
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,70000,1400),unreal.Vector(x,70000,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
   if not h[0]:break
   hits.append(dict(actor=h[9].get_actor_label(),mesh=h[10].static_mesh.get_path_name() if isinstance(h[10],unreal.StaticMeshComponent) and h[10].static_mesh else None,z_cm=float(h[4].z)));ignored.append(h[9])
  road.append(dict(x_cm=x,y_cm=70000,hits=hits))
 for x in range(26100,27701,100):
  for y in [84050,84250,84450]:ground.append(terrain(x,y,[actors['World_PK_0108']]))
 write('outdoor-support-review',dict(status='recorded',map_sha256=LOAD_SHA,roots=roots,road_cross_section=road,PK0108_approach_ground=ground))

def immersion_surface_ledger_review():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};result={}
 for kind in ['street','tactile']:
  path=ROOT/'output'/'street-social-city-production'/'day-night-v1'/(kind+'-surface-install.json');ledger=json.loads(path.read_text('utf8'));rows=[];replacement=[]
  for old in ledger['changes']:
   a=actors.get(old['actor']);c=next((c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==old['component']),None) if a else None
   if not c:rows.append(dict(actor=old['actor'],component=old['component'],missing=True));continue
   rows.append(dict(actor=old['actor'],component=old['component'],mesh=c.static_mesh.get_path_name(),expected_mesh=old['original_mesh'],instance_count=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else 0,expected_instances=old['instance_count'],visible=c.get_editor_property('visible'),hidden=c.get_editor_property('hidden_in_game'),hidden_shadow=c.get_editor_property('cast_hidden_shadow'),collision=str(c.get_collision_profile_name()),expected_collision=old['original']['row']['collision'],materials=[c.get_material(i).get_path_name() if c.get_material(i) else None for i in range(c.get_num_materials())],expected_materials=old['effective_materials'],transform=ground_transform(c.get_world_transform()),expected_matrix=old['component_matrix']))
  for old in ledger['replacements']:
   a=actors.get(old['actor']);cs=a.get_components_by_class(unreal.StaticMeshComponent) if a else [];c=next((c for c in cs if c.static_mesh and c.static_mesh.get_path_name()==old['mesh']),None)
   replacement.append(dict(actor=old['actor'],missing=c is None,components=[dict(mesh=c.static_mesh.get_path_name() if c.static_mesh else None,visible=c.get_editor_property('visible'),hidden=c.get_editor_property('hidden_in_game'),collision=str(c.get_collision_profile_name()),transform=ground_transform(c.get_world_transform())) for c in cs],tags=[str(t) for t in a.tags] if a else []))
  result[kind]=dict(originals=rows,replacements=replacement)
 write('surface-ledger-review',dict(status='recorded',map_sha256=LOAD_SHA,ledgers=result))

def immersion_geometry_metrics():
 rows=[]
 for name,path in [('original_arch','/Game/UniversityCity/ResortV1/Assets/R018/S_9262f97138b8a505/R018_LOD0.R018_LOD0'),('new_arch',read('arch-import')['asset'])]:
  mesh=EAL.load_asset(path);b=mesh.get_bounds();rows.append(dict(name=name,asset=path,origin_cm=num(b.origin),extent_cm=num(b.box_extent)))
 write('geometry-metrics',dict(status='passed',map_sha256=LOAD_SHA,rows=rows))

def immersion_lamps_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'path-lamps.json').exists();plan=read('campus-route-plan');assert len(plan['routes'])==40
 before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();allpoints=[p for r in plan['routes'] for p in r['points_cm']];oldlights=[]
 for a in SUB.get_all_level_actors():
  tags=[str(t) for t in a.tags]
  if 'EnvGroup=Path' in tags or a.get_actor_label().startswith('ResortLantern_'):
   if a.get_components_by_class(unreal.LightComponent):oldlights.append(num(a.get_actor_location())[:2])
 chosen=[];omitted=[]
 for route in plan['routes']:
  points=route['points_cm'];along=0.;next_at=800.
  for start,end in zip(points,points[1:]):
   dx,dy=end[0]-start[0],end[1]-start[1];length=math.hypot(dx,dy)
   if length<1:continue
   while next_at<=along+length and len(chosen)<80:
    t=(next_at-along)/length;cx,cy=start[0]+dx*t,start[1]+dy*t;candidate=None
    for side in [1 if len(chosen)%2 else -1,-1 if len(chosen)%2 else 1]:
     x,y=cx-dy/length*220*side,cy+dx/length*220*side
     if any(math.hypot(x-p[0],y-p[1])<180 for p in allpoints):continue
     if any(math.hypot(x-p[0],y-p[1])<850 for p in oldlights+[r['position_cm'][:2] for r in chosen]):continue
     raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1230),unreal.Vector(x,y,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None
     if not h or not h[0] or not 1190<=h[4].z<=1215:continue
     g=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,g+100),unreal.Vector(x,y,g+105),22.,88.))
     if s['blocked']:continue
     candidate=dict(route=route['id'],position_cm=[x,y,g],ground_actor=h[9].get_actor_label(),side=side);break
    if candidate:chosen.append(candidate)
    else:omitted.append(dict(route=route['id'],center_cm=[cx,cy],reason='Existing lamp, intersecting pedestrian route, unsuitable ground or fixture clearance'))
    next_at+=1600.
   along+=length
 assert len(chosen)>=20,len(chosen)
 metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');opal=EAL.load_asset('/Game/UniversityCity/EnvironmentV1/Materials/M_EnvironmentOpal_01');assert metal and opal
 for m in [metal,opal]:assert material_chain(m)[1].get_editor_property('used_with_instanced_static_meshes')
 backup=OUT/('UniversityCity-before-path-lamps-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);parts=dict(Metal=[],Opal=[]);lights=[]
 def cylinder(kind,x,y,z,diameter,height):parts[kind].append(dict(center=[x,y,z],size=[diameter,diameter,height]))
 for i,q in enumerate(chosen):
  x,y,g=q['position_cm'];cylinder('Metal',x,y,g+2.5,22,5);cylinder('Metal',x,y,g+40,8,70);cylinder('Metal',x,y,g+74.5,17,3);cylinder('Opal',x,y,g+86,15,22);cylinder('Metal',x,y,g+99,30,4);cylinder('Metal',x,y,g+101.5,26,1)
  a=SUB.spawn_actor_from_class(unreal.SpotLight,unreal.Vector(x,y,g+78),unreal.Rotator(pitch=-90));a.set_actor_label('Immersion_PathLamp_Light_%03d'%i);a.tags=[unreal.Name('ImmersionV1'),unreal.Name('EnvGroup=Path'),unreal.Name('EnvLumens=110')];a.set_folder_path('UniversityCity/ImmersionV1');c=a.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(110);c.set_temperature(2800);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',550);c.set_editor_property('inner_cone_angle',55);c.set_editor_property('outer_cone_angle',80);c.set_editor_property('source_radius',12);c.set_editor_property('volumetric_scattering_intensity',.2);c.set_cast_shadows(False);lights.append(a.get_actor_label())
 labels=[]
 for kind,rows in parts.items():
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cylinder'),metal if kind=='Metal' else opal,'FlatCampus_Immersion_PathLamp_'+kind);assert c;a=c.get_owner();a.set_actor_label('Immersion_PathLamp_'+kind);a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll' if kind=='Metal' else 'NoCollision');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in rows],False,True,True);labels.append(a.get_actor_label())
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.refresh_bindings();controller.prepare_for_save();after=ground_snapshot();assert [r for r in after if r['actor'] not in labels]==before;assert len(after)==len(before)+2;assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),campus_path_lamps=len(chosen));write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('path-lamps',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),fixtures=chosen,light_actors=lights,omitted=omitted,lumens=110,temperature_kelvin=2800,shadows=False,schedule='Existing EnvGroup=Path light schedule and MPC LampGlowWeight; low intensity complements moonlit ambient; no additional sharp spotlight shadows.'))

def immersion_water_probe():
 a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='World_PK_0105');world=unreal.EditorLevelLibrary.get_editor_world();geometry=read('water-deck-geometry');rows=[]
 def ground(x,y):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1218),unreal.Vector(x,y,850),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[a],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None
  return dict(xy=[x,y],hit=bool(h and h[0]),ground_cm=float(h[4].z) if h and h[0] else None,actor=h[9].get_actor_label() if h and h[0] else None)
 def foundation(row):
  x,y=row['xy'];row['corner_probes']=[ground(x+dx,y+dy) for dx in [-16,16] for dy in [-16,16]];assert all(r['hit'] for r in row['corner_probes']);row['foundation_base_cm']=min(r['ground_cm'] for r in row['corner_probes'])-8;return row
 for q in geometry['paving_parts']:
  if 1<=q['id']<=20:
   row=ground(*[(q['min_cm'][i]+q['max_cm'][i])/2 for i in range(2)]);row['part']=q['id'];rows.append(foundation(row))
 bank=[]
 for x in range(83050,84600,100):
  for y in [75600,75750,75900]:bank.append(ground(x,y))
 assert len(rows)==20 and all(r['hit'] and 900<=r['ground_cm']<=1210 for r in rows),rows
 path=read('campus-route-plan');points=[p for q in path['routes'] for p in q['points_cm']];nearest=min(points,key=lambda p:math.dist(p,[84050,75750]))
 bridge=[foundation(ground(x,y)) for x in [83400,83700,84000] for y in [75650,75850]]
 write('water-deck-probes',dict(status='passed',map_sha256=LOAD_SHA,mesh=a.static_mesh_component.static_mesh.get_path_name(),component=a.static_mesh_component.get_name(),actor_transform=actor_xform(a),pier_ground=rows,bridge_pier_ground=bridge,bank_ground=bank,nearest_campus_route_cm=nearest,target_deck_top_cm=1206,old_deck_top_cm=1418.0491527280271,delta_z_cm=1206-1418.0491527280271))

def immersion_recover_props():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;expected=read('preservation-after')['components'];lookup={(a.get_actor_label(),c.get_name()):(a,c) for a in SUB.get_all_level_actors() for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.static_mesh};count=0
 for row in expected:
  a,c=lookup[(row['actor'],row['component'])]
  if c.static_mesh.get_path_name()==row['mesh']:continue
  assert c.static_mesh.get_path_name().startswith(IMM+'/GardenArch/') and '/ResortV1/Assets/R018/' in row['mesh'];name=c.get_name();c.set_static_mesh(EAL.load_asset(row['mesh']));c.set_editor_property('override_materials',[EAL.load_asset(p) if p else None for p in row['materials']]);count+=1
 assert ground_snapshot()==expected;assert sha(MAPFILE)==LOAD_SHA;write('props-recovery',dict(status='passed',restored_unsaved_components=count,map_sha256=LOAD_SHA,scope='Restore only the unsaved R018 swaps from the failed pre-save structural pass; exact full snapshot matches again.'))

def immersion_paths_refresh():
 installed=read('install');plan=read('campus-route-plan');review=read('route-native-review');assert installed['map_sha256']==review['map_sha256']==LOAD_SHA and review['status']=='passed' and review['plan_sha256']==sha(OUT/'campus-route-plan.json');assert len(plan['routes'])==40 and not plan['issues']
 before=ground_snapshot();assert before==read('preservation-after')['components'];a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='Immersion_CampusPaths');c=a.get_components_by_class(unreal.InstancedStaticMeshComponent)[0];backup=OUT/('UniversityCity-before-path-extension-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c.modify();c.clear_instances();c.add_instances([unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in plan['boxes']],False,True,True)
 after=ground_snapshot()
 for old,now in zip(before,after):
  row=dict(now)
  if old['actor']=='Immersion_CampusPaths':row['instances']=old['instances']
  assert row==old,('Unintended path extension change',old['actor'])
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,campus_path_strips=len(plan['boxes']),connected_exterior_routes=40);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('path-refresh',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),routes=40,strips=len(plan['boxes']),native_ground_samples=review['ground_samples'],native_capsule_sweeps=review['capsule_sweeps'],reason='Extend the connected campus network to the new grounded waterfront gangway; exact boundary joins prevent overlay on its deck.'))

def immersion_water_install():
 installed=read('install');plan=read('water-deck-plan');meshplan=read('water-deck-mesh-plan');assert installed['map_sha256']==plan['map_sha256']==meshplan['map_sha256']==LOAD_SHA;assert not (OUT/'water-deck-install.json').exists()
 before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};a=actors[plan['actor']];assert actor_xform(a)==plan['actor_before'];assert a.static_mesh_component.static_mesh.get_path_name()==plan['source_mesh']
 for m in meshplan['meshes']:
  assert not EAL.does_asset_exist(m['after'])
  for lod in m['lods']:assert sha(lod['vertices'])==lod['sha256']
 mats=dict(Stone=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly'),Metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze'))
 for m in mats.values():assert m and material_chain(m)[1].get_editor_property('used_with_instanced_static_meshes')
 backup=OUT/('UniversityCity-before-waterfront-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);world=unreal.EditorLevelLibrary.get_editor_world();result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'water-deck-mesh-plan.json')));write('water-native-mesh',result);assert result['status']=='passed',result
 old=a.get_actor_location();a.modify();assert a.set_actor_location(unreal.Vector(old.x,old.y,plan['actor_after_z_cm']),False,True)
 labels=[]
 for kind,rows in plan['groups'].items():
  c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),mats[kind],'FlatCampus_Immersion_Water_'+kind);assert c;owner=c.get_owner();owner.set_actor_label('Immersion_Water_'+kind);owner.tags=[unreal.Name('ImmersionV1')];owner.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in rows],False,True,True);labels.append(owner.get_actor_label())
 after=ground_snapshot();oldrows={(r['actor'],r['component']):r for r in before}
 for now in after:
  if now['actor'] in labels:continue
  old=oldrows[(now['actor'],now['component'])];row=dict(now)
  if now['actor']==plan['actor']:
   assert row['mesh']==result['meshes'][0]['after'];assert abs(row['actor_transform']['location'][2]-1206)<.01;row['mesh']=old['mesh'];row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  assert row==old,('Unintended waterfront change',now['actor'],now['component'])
 assert len(after)==len(before)+2
 floor=[]
 for x in range(83120,85121,100):
  raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,75750,1220),unreal.Vector(x,75750,1170),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None;assert h and h[0] and abs(h[4].z-1206)<.2,(x,h);floor.append(dict(x=x,z=float(h[4].z)))
 sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(83120,75750,1304),unreal.Vector(85100,75750,1304),35.,88.));assert not sweep['blocked'],sweep
 next(q for q in actors.values() if q.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),waterfront_level_cm=1206,waterfront_piers=26,waterfront_access_bridge_cm=950);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('water-deck-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),new_mesh=result['meshes'][0]['after'],deck_top_cm=1206,terrain_grounded_piers=26,access_gangway_cm=950,guardrail_height_cm=112,groups=labels,floor_probes=floor,visitor_capsule_sweep=sweep,policy=plan['policy']))

def immersion_props_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'props-install.json').exists();plan=read('sign-support-plan');assert plan['map_sha256']==LOAD_SHA;arch=read('arch-import');mesh=EAL.load_asset(arch['asset']);assert mesh
 before=ground_snapshot();assert before==read('preservation-after')['components']
 for q in plan['rows']:
  if q['proposed_standalone_support'] and q['actor'].startswith('Activity_ACTSPACE-08-'):assert len(q['furniture_anchors'])==2,q['actor']
 backup=OUT/('UniversityCity-before-prop-supports-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');assert metal;changes=[]
 for a in SUB.get_all_level_actors():
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or '/ResortV1/Assets/R018/' not in c.static_mesh.get_path_name():continue
   old=c.static_mesh.get_path_name();name=c.get_name();wood=c.get_material(0);mats=[None,None];mats[arch['wood_slot']]=wood;mats[arch['metal_slot']]=metal;c.modify();c.set_static_mesh(mesh);c.set_editor_property('override_materials',mats);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name);assert c.static_mesh==mesh
   changes.append(dict(actor=a.get_actor_label(),component=name,before=old,after=mesh.get_path_name(),materials=[m.get_path_name() for m in mats]))
 assert len(changes)==11,len(changes);parts=[];supports=[]
 def box(center,size):parts.append(dict(center=center,size=size))
 for q in plan['rows']:
  if not q['proposed_standalone_support']:continue
  x,y,z=q['center_cm'];ex,ey,ez=q['extent_cm'];bottom=z-ez;normal=q['normal'];tangent=q['tangent'];halfwidth=max(ex,ey);anchors=[];furniture=q['actor'].startswith('Activity_ACTSPACE-08-')
  if furniture:
   assert len(q['furniture_anchors'])==2,q['actor'];anchors=q['furniture_anchors']
  else:
   for side in [-1,1]:anchors.append(dict(point_cm=[x+tangent[0]*halfwidth*.7*side+normal[0]*8,y+tangent[1]*halfwidth*.7*side+normal[1]*8,q['ground_cm']],actor=q['ground_actor']))
  pole=4 if furniture or bottom-q['ground_cm']<200 else 6
  for anchor in anchors:
   px,py,g=anchor['point_cm'];foot=8 if furniture else 18;thick=1.2 if furniture else 2.5;box([px,py,g+thick/2],[foot,foot,thick]);top=bottom-5;assert top>g+thick
   box([px,py,(g+thick+top)/2],[pole,pole,top-g-thick]);dx,dy=x-px,y-py;along=dx*normal[0]+dy*normal[1];size=[abs(along)+4 if normal[0] else pole,abs(along)+4 if normal[1] else pole,4];box([px+normal[0]*along/2,py+normal[1]*along/2,bottom-5],size)
  box([x,y,bottom-2],[4 if tangent[1] else halfwidth*1.56,4 if tangent[0] else halfwidth*1.56,4]);supports.append(dict(sign=q['actor'],type='furniture-mounted bracket' if furniture else 'ground-mounted two-post frame',anchors=anchors))
 assert len(supports)==46,len(supports);world=unreal.EditorLevelLibrary.get_editor_world();c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),metal,'FlatCampus_Immersion_SignSupports');assert c;a=c.get_owner();a.set_actor_label('Immersion_SignSupports');a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*r['center']),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in parts],False,True,True)
 after=ground_snapshot();oldrows={(r['actor'],r['component']):r for r in before};expected={(r['actor'],r['component']):r for r in changes}
 for now in after:
  if now['actor']=='Immersion_SignSupports':continue
  key=(now['actor'],now['component']);old=oldrows[key];row=dict(now)
  if key in expected:assert row['mesh']==expected[key]['after'] and row['materials']==expected[key]['materials'];row['mesh']=old['mesh'];row['materials']=old['materials']
  assert row==old,('Unintended structural support change',key)
 assert len(after)==len(before)+1;next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,tree_changed_components=installed.get('tree_changed_components',installed['changed_components']),changed_components=installed['changed_components']+len(changes),preserved_components=len(after),supported_signs=len(supports),arch_components=len(changes));write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('props-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),arch_changes=changes,sign_supports=supports,sign_support_boxes=len(parts),scope='Connect garden arch frames and support signs; original sign textures, transforms and unrelated components remain unchanged.'))
def immersion_extra_outdoor_cameras():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for sid,label in [('PK-0101','World_PK_0101'),('PK-0106','World_PK_0106'),('PK-0108','World_PK_0108'),('PK-0109','World_PK_0109'),('PK-0114','Outdoor_stadium'),('PK-0115','Outdoor_campus_track')]:
  a=actors[label];p,e=a.get_actor_bounds(False);span=max(e.x,e.y);eye=[p.x-span*1.2,p.y-span*1.35,1200+span*1.8];target=[p.x,p.y,1206];kind='elevated diagnostic overview'
  if sid=='PK-0108':target[2]=1800
  if sid=='PK-0106':eye=[86000,75500,1371];target=[87500,75500,1280];kind='player-height connected waterfront approach'
  if sid=='PK-0109':eye=[44500,80100,1369];target=[44500,82500,1330];kind='player-height aligned cherry promenade between offices'
  result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*eye),unreal.Vector(eye[0],eye[1],eye[2]+1),20.,20.));assert not result['blocked'],(sid,result);rows.append(dict(id=sid,actor=label,eye=eye,target=target,fov=75,camera_kind=kind,source_bounds_cm=dict(origin=num(p),extent=num(e))))
 assert sha(MAPFILE)==LOAD_SHA;write('extra-outdoor-cameras',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,scope='Six previously omitted outdoor roots; four elevated diagnostic overviews and two supported player-height approaches. Clear camera sphere; elevated pictures are not substituted for player traversal.'))

def immersion_outdoor_floor_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();actors=list(SUB.get_all_level_actors());rows=[]
 for a in actors:
  label=a.get_actor_label()
  if not(re.fullmatch(r'World_PK_\d{4}',label) or label in ['Outdoor_stadium','Outdoor_campus_track']) or a.get_editor_property('hidden'):continue
  p,e=a.get_actor_bounds(False);ignored=[q for q in actors if q!=a];samples=[]
  for dx in [-.55,0,.55]:
   for dy in [-.55,0,.55]:
    x,y=p.x+e.x*dx,p.y+e.y*dy;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1350),unreal.Vector(x,y,900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];row=dict(xy_cm=[x,y],owner_hit=bool(h[0]),owner_z_cm=float(h[4].z) if h[0] else None)
    if not h[0]:
     raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,2800),unreal.Vector(x,y,900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);hi=raw.to_tuple() if raw else [False];row['higher_owner_hit_cm']=num(hi[4]) if hi[0] else None
    raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1230),unreal.Vector(x,y,900),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[a],unreal.DrawDebugTrace.NONE,True);support=raw.to_tuple() if raw else [False];row['other_support_cm']=num(support[4]) if support[0] else None;row['other_actor']=support[9].get_actor_label() if support[0] and support[9] else None;samples.append(row)
  rows.append(dict(actor=label,origin_cm=num(p),extent_cm=num(e),campus_or_edge=53300<p.x<98500 and 18000<p.y<78500,samples=samples))
 assert sha(MAPFILE)==LOAD_SHA;write('outdoor-floor-probe',dict(status='diagnostic_requires_review',map_sha256=LOAD_SHA,sites=len(rows),rows=rows,scope='Nine owner-only support rays per outdoor root plus underlying other support. High hits can be furniture/roofs; missing or differing hits are candidates for geometric review, not automatic relocation.'))

def immersion_environment_feet_finish():
 installed=read('install');probe=read('environment-feet-probe');assert installed['map_sha256']==probe['map_sha256']==LOAD_SHA and len(probe['suspects'])==10 and not (OUT/'environment-feet-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors=list(SUB.get_all_level_actors());bylabel={a.get_actor_label():a for a in actors};world=unreal.EditorLevelLibrary.get_editor_world();routes=read('campus-route-plan')['routes'];proposed=[];groups=[]
 for q in probe['suspects']:
  x,y=q['xy_cm'];members=[a for a in actors if a.get_actor_label().startswith(q['prefix'])];assert len(members)==6;ground=q['ground_cm'];assert ground
  if q['support']=='Immersion_CampusPaths':
   nearest=None
   for r in routes:
    for i,p in enumerate(r['points_cm']):
     d=math.dist([x,y],p)
     if nearest is None or d<nearest[0]:nearest=(d,r,i)
   _,r,i=nearest;points=r['points_cm'];a=points[max(0,i-3)];b=points[min(len(points)-1,i+3)];dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);assert length>1;chosen=None
   for side in [-1,1]:
    px=points[i][0]-dy/length*220*side;py=points[i][1]+dx/length*220*side;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(px,py,1240),unreal.Vector(px,py,1150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,members,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
    if not h[0] or not re.fullmatch(r'G\d\d',h[9].get_actor_label()) or not 1190<h[4].z<1215:continue
    result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(px,py,h[4].z+100),unreal.Vector(px,py,h[4].z+101),40.,88.))
    if not result['blocked']:chosen=(px,py,num(h[4]));break
   assert chosen,('No safe lawn-side position',q['actor']);x,y,ground=chosen
  assert 1190<=ground[2]<=1215;delta=ground[2]+.2-q['base_cm'];groups.append(dict(prefix=q['prefix'],old_xy_cm=q['xy_cm'],new_xy_cm=[x,y],ground_cm=ground,old_gap_cm=q['gap_cm']))
  for a in members:
   p=a.get_actor_location();proposed.append(dict(actor=a.get_actor_label(),before=actor_xform(a),target_cm=[p.x+x-q['xy_cm'][0],p.y+y-q['xy_cm'][1],p.z+delta]))
 assert len(proposed)==60;backup=OUT/('UniversityCity-before-campus-fixture-feet-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for q in proposed:bylabel[q['actor']].modify();bylabel[q['actor']].set_actor_location(unreal.Vector(*q['target_cm']),False,False)
 after=ground_snapshot();expected={q['actor']:q for q in proposed};assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now)
  if row['actor'] in expected:assert math.dist(row['actor_transform']['location'],expected[row['actor']]['target_cm'])<.01;row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  assert row==old,('Unexpected fixture footing change',row['actor'])
 c=bylabel['CityEnvironmentController'];c.refresh_bindings();c.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,additional_grounded_environment_fixture_groups=10);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('environment-feet-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),groups=groups,changes=proposed,scope='Ground ten existing campus fixture groups; move two fixtures from new pedestrian paving onto native-clear lawn shoulders. Preserve their geometry, materials, collision policies and lighting configuration.'))

def immersion_environment_feet_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();actors=list(SUB.get_all_level_actors());rows=[];suspects=[]
 for a in actors:
  label=a.get_actor_label()
  if not label.startswith('Environment_') or not label.endswith('_Foot') or a.get_editor_property('hidden'):continue
  p,e=a.get_actor_bounds(False)
  if not(54800<p.x<97000 and 19500<p.y<77000):continue
  low=p.z-e.z;prefix=label[:-4];ignored=[q for q in actors if q.get_actor_label().startswith(prefix)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p.x,p.y,low+80),unreal.Vector(p.x,p.y,low-400),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];row=dict(actor=label,prefix=prefix,xy_cm=[p.x,p.y],base_cm=low,hit=bool(h[0]),support=h[9].get_actor_label() if h[0] else None,ground_cm=num(h[4]) if h[0] else None,gap_cm=low-h[4].z if h[0] else None);rows.append(row)
  if not h[0] or abs(low-h[4].z)>2 or low<1120:suspects.append(row)
 assert sha(MAPFILE)==LOAD_SHA;write('environment-feet-probe',dict(status='passed' if not suspects else 'requires_review',map_sha256=LOAD_SHA,checked=len(rows),suspects=suspects,rows=rows,scope='All Environment fixture feet inside campus against current actual supporting collision, including waterline sanity; source/opal/light parts of each fixture ignored during the support ray.'))

def immersion_water_lamps_finish():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA and not (OUT/'water-lamps-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();groups=[('Environment_PK_0105_0_',83870,75665),('Environment_PK_0105_1_',86330,75420),('Environment_PK_0106_0_',86550,75580),('Environment_PK_0106_1_',88220,75580)];members=[a for label,a in actors.items() if any(label.startswith(prefix) for prefix,_,_ in groups)];assert len(members)==24;changes=[]
 for prefix,x,y in groups:
  foot=actors[prefix+'Foot'];p,e=foot.get_actor_bounds(False);base=p.z-e.z;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1250),unreal.Vector(x,y,950),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,members,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and 1190<=h[4].z<=1210,(prefix,h);target=float(h[4].z)+.2
  for a in members:
   if not a.get_actor_label().startswith(prefix):continue
   location=a.get_actor_location();changes.append(dict(actor=a.get_actor_label(),before=actor_xform(a),target_cm=[location.x+x-p.x,location.y+y-p.y,location.z+target-base],support=h[9].get_actor_label(),ground_z_cm=float(h[4].z)))
 backup=OUT/('UniversityCity-before-water-lamps-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for q in changes:
  a=actors[q['actor']];a.modify();a.set_actor_location(unreal.Vector(*q['target_cm']),False,False)
  if not q['actor'].endswith(('_Light','_Opal')):
   for c in a.get_components_by_class(unreal.StaticMeshComponent):c.set_collision_profile_name('BlockAll')
 after=ground_snapshot();expected={q['actor']:q for q in changes};assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now)
  if row['actor'] in expected:
   assert math.dist(row['actor_transform']['location'],expected[row['actor']]['target_cm'])<.01;row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
   if not row['actor'].endswith('_Opal'):assert row['collision']=='BlockAll';row['collision']=old['collision']
  assert row==old,('Unintended lake lamp change',row['actor'])
 routes=[([83100,75750],[84600,75750]),([85900,75500],[87000,75500])];clear=[]
 for p,q in routes:
  result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*p,1304),unreal.Vector(*q,1304),35.,88.));assert not result['blocked'],result;clear.append(result)
 controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,grounded_lake_lamp_groups=4);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('water-lamps-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=changes,capsule_sweeps=clear,scope='Ground all four lake bollard groups, space them on alternating sides away from center routes and rails, enable physical metal collision while retaining opal/light behavior; all unrelated settings preserved.'))

def immersion_ground_bounce_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA and not (OUT/'ground-bounce-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CitySkyLight');c=a.get_component_by_class(unreal.SkyLightComponent);v=c.get_editor_property('lower_hemisphere_color');old=[v.r,v.g,v.b,v.a];assert old==[0.,0.,0.,1.] and c.get_editor_property('lower_hemisphere_is_black');backup=OUT/('UniversityCity-before-ground-bounce-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c.modify();c.set_editor_property('lower_hemisphere_color',unreal.LinearColor(.12,.115,.10,1));next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,ground_bounce_color=[.12,.115,.10,1]);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=before));write('ground-bounce-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),actor=a.get_actor_label(),before=old,after=[.12,.115,.10,1],scope='Replace pure-black lower hemisphere with restrained warm-neutral diffuse ground bounce. Visible sky, sun/moon lux, exposure and all geometry/material bindings remain unchanged.'))

def immersion_second_water_review():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='World_PK_0106');mesh=a.static_mesh_component.static_mesh;settings=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem).get_lod_build_settings(mesh,0);build_scale=num(settings.get_editor_property('build_scale3d'));task=unreal.AssetExportTask();task.object=mesh;task.filename=str(OUT/'water2-trial.obj');task.automated=True;task.prompt=False;task.replace_identical=True;task.exporter=unreal.StaticMeshExporterOBJ();exported=unreal.Exporter.run_asset_export_task(task)
 for x,y in [(86633,75500),(87500,75500),(88000,76300),(86225,75500)]:
  h=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1236),unreal.Vector(x,y,1180),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();row=dict(x=x,y=y,hit=h[0])
  if h[0]:
   c=h[10];row.update(point=num(h[4]),actor=h[9].get_actor_label(),component=c.get_name(),mesh=c.static_mesh.get_path_name() if c.static_mesh else None,component_transform=ground_transform(c.get_world_transform()),actor_transform=actor_xform(h[9]))
  rows.append(row)
 write('water2-trial-review',dict(status='diagnostic_unsaved_trial',disk_map_sha256=LOAD_SHA,rows=rows,build_scale=build_scale,render_obj_exported=exported))

def immersion_second_water_install():
 installed=read('install');plan=read('water2-plan');meshplan=read('water2-mesh-plan');assert installed['map_sha256']==plan['map_sha256']==meshplan['map_sha256']==LOAD_SHA;assert not (OUT/'water2-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};a=actors[plan['actor']];assert actor_xform(a)==plan['actor_before'] and a.static_mesh_component.static_mesh.get_path_name()==plan['source_mesh'];rail=actors['Immersion_Water_Metal'].get_components_by_class(unreal.InstancedStaticMeshComponent)[0];assert rail.get_instance_count()==plan['old_metal_count']
 for q in plan['fixture_moves']:assert actor_xform(actors[q['actor']])==q['before']
 for q in meshplan['meshes']:
  assert not EAL.does_asset_exist(q['after'])
  for lod in q['lods']:assert sha(lod['vertices'])==lod['sha256']
 backup=OUT/('UniversityCity-before-second-waterfront-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);world=unreal.EditorLevelLibrary.get_editor_world();result=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'water2-mesh-plan.json')));write('water2-native-mesh',result);assert result['status']=='passed',result;a.modify();a.set_actor_location(unreal.Vector(*plan['actor_after']['location']),False,True)
 for q in plan['fixture_moves']:actors[q['actor']].modify();actors[q['actor']].set_actor_location(unreal.Vector(*q['target_cm']),False,False)
 rail.modify();rail.clear_instances();rail.add_instances([unreal.Transform(location=unreal.Vector(*q['center']),scale=unreal.Vector(*[v/100 for v in q['size']])) for q in plan['metal']],False,True,True);assert rail.get_instance_count()==len(plan['metal'])
 stone=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_FacingOnly');c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),stone,'FlatCampus_Immersion_Water_SecondStone');assert c;owner=c.get_owner();label='Immersion_Water_SecondStone';owner.set_actor_label(label);owner.tags=[unreal.Name('ImmersionV1')];owner.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('BlockAll');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*q['center']),scale=unreal.Vector(*[v/100 for v in q['size']])) for q in plan['stone']],False,True,True)
 after=ground_snapshot();oldrows={(q['actor'],q['component']):q for q in before};moved={q['actor']:q for q in plan['fixture_moves']}
 for now in after:
  if now['actor']==label:continue
  old=oldrows[(now['actor'],now['component'])];row=dict(now)
  if now['actor']==plan['actor']:assert row['mesh']==result['meshes'][0]['after'] and math.dist(row['actor_transform']['location'],plan['actor_after']['location'])<.01 and row['actor_transform']['rotation']==old['actor_transform']['rotation'] and row['actor_transform']['scale']==old['actor_transform']['scale'];row['mesh']=old['mesh'];row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  elif now['actor'] in moved:assert math.dist(row['actor_transform']['location'],moved[now['actor']]['target_cm'])<.01;row['actor_transform']=old['actor_transform'];row['transform']=old['transform']
  elif now['actor']=='Immersion_Water_Metal':row['instances']=old['instances']
  assert row==old,('Unexpected second waterfront change',now['actor'])
 assert len(after)==len(before)+1;floors=[];sweeps=[];issues=[]
 for index,(p,q) in enumerate(zip(plan['walk_points_cm'],plan['walk_points_cm'][1:])):
  n=math.ceil(math.dist(p,q)/75)
  for i in range(n+1):
   xy=[p[j]+(q[j]-p[j])*i/n for j in range(2)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*xy,1236),unreal.Vector(*xy,1180),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];row=dict(route=index,xy_cm=xy,passed=bool(h[0]) and abs(h[4].z-1206)<1,hit_cm=num(h[4]) if h[0] else None);floors.append(row)
   if not row['passed']:issues.append(row)
  s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*p,1304),unreal.Vector(*q,1304),35.,88.));sweeps.append(dict(route=index,result=s))
  if s['blocked']:issues.append(sweeps[-1])
 write('water2-walk-preflight',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,floors=floors,sweeps=sweeps,issues=issues));assert not issues,issues[:3]
 controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),second_waterfront_piers=20,second_waterfront_fixture_moves=12);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('water2-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),mesh=result['meshes'][0]['after'],actor_after=plan['actor_after'],fixture_moves=plan['fixture_moves'],connected_floor_probes=len(floors),connected_capsule_sweeps=len(sweeps),shared_metal_parts=len(plan['metal']),policy=plan['policy']))

def immersion_second_water_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};a=actors['World_PK_0106'];g=read('water-platform-0106-geometry');rows=[]
 def ground(x,y):
  ignored=[a]
  for attempt in range(12):
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,1280),unreal.Vector(x,y,800),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignored,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0],(x,y)
   if re.fullmatch(r'G\d\d',h[9].get_actor_label()):return dict(xy_cm=[x,y],ground_cm=float(h[4].z),actor=h[9].get_actor_label())
   ignored.append(h[9])
  raise AssertionError(('No terrain below clutter',x,y))
 for p in g['paving_parts'][1:21]:
  x=(p['min_cm'][0]+p['max_cm'][0])/2;y=(p['min_cm'][1]+p['max_cm'][1])/2-500;corners=[ground(x+dx,y+dy) for dx in [-16,16] for dy in [-16,16]];rows.append(dict(part=p['id'],xy_cm=[x,y],corners=corners,foundation_base_cm=min(q['ground_cm'] for q in corners)-8))
 fixtures=[]
 for index,x,y in [(0,86225,75385),(1,88580,75500)]:
  foot=actors['Environment_PK_0106_%d_Foot'%index];origin,extent=foot.get_actor_bounds(False);base=float(origin.z-extent.z);target=1206 if index==0 else ground(x,y)['ground_cm'];members=[]
  for label,q in actors.items():
   if label.startswith('Environment_PK_0106_%d_'%index):
    p=q.get_actor_location();members.append(dict(actor=label,before=actor_xform(q),target_cm=[p.x+x-origin.x,p.y+y-origin.y,p.z+target+.2-base]))
  assert len(members)==6;fixtures.extend(members)
 write('water2-probes',dict(status='passed',map_sha256=LOAD_SHA,actor_before=actor_xform(a),source_mesh=a.static_mesh_component.static_mesh.get_path_name(),old_top_cm=1414.143570436035,deck_top_cm=1206,delta_cm=[0,-500,1206-1414.143570436035],pier_ground=rows,fixture_moves=fixtures))

def immersion_ceiling_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];skies=[]
 for a in SUB.get_all_level_actors():
  c=a.get_component_by_class(unreal.SkyLightComponent)
  if c:
   color=c.get_editor_property('lower_hemisphere_color');skies.append(dict(actor=a.get_actor_label(),solid_lower=c.get_editor_property('lower_hemisphere_is_black'),lower_color=[color.r,color.g,color.b,color.a],source_type=str(c.get_editor_property('source_type')),intensity=c.get_editor_property('intensity'),cubemap=c.get_editor_property('cubemap').get_path_name() if c.get_editor_property('cubemap') else None))
 for q in read('interior-cameras')['rows']:
  p=q['eye'];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*p),unreal.Vector(p[0],p[1],p[2]+500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];row=dict(id=q['id'],hit=bool(h[0]))
  if h[0]:
   row.update(actor=h[9].get_actor_label(),component=h[10].get_name(),hit_cm=num(h[4]),normal=num(h[7]),face_index=h[15])
   try:
    m,section=h[10].get_material_from_collision_face_index(h[15]);row.update(material=m.get_path_name() if m else None,section=section)
    if m:
     chain,base=material_chain(m);row['chain']=chain;row['solid_diagnostic']=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(m))
   except Exception as e:row['material_query_error']=str(e)
  rows.append(row)
 assert sha(MAPFILE)==LOAD_SHA;write('ceiling-probe',dict(status='diagnostic_requires_review',map_sha256=LOAD_SHA,skylights=skies,ceilings=rows))

def immersion_lighting_audit():
 rows=[];issues=[];counts=dict(path=0,nautical=0);consolidated=set(read('lamp-consolidation-install')['upgraded_surviving_lights']) if (OUT/'lamp-consolidation-install.json').exists() else set()
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label();kind='path' if label.startswith('Immersion_PathLamp_Light_') else 'nautical' if label.startswith('Immersion_NauticalLight_') else None
  if not kind:continue
  c=a.get_component_by_class(unreal.LocalLightComponent);assert c;tags=[str(t) for t in a.tags];expected=110 if kind=='path' else 200 if label in consolidated else 55;row=dict(actor=label,kind=kind,position_cm=num(a.get_actor_location()),mobility=str(c.get_editor_property('mobility')),cast_shadows=c.get_editor_property('cast_shadows'),temperature=c.get_editor_property('temperature'),use_temperature=c.get_editor_property('use_temperature'),intensity_units=str(c.get_editor_property('intensity_units')),radius=c.get_editor_property('attenuation_radius'),source_radius=c.get_editor_property('source_radius'),tags=tags);row['passed']=not row['cast_shadows'] and row['use_temperature'] and row['temperature']==2800 and 350<=row['radius']<=(950 if label in consolidated else 550) and row['source_radius']>=(25 if label in consolidated else 12) and 'EnvGroup=Path' in tags and 'EnvLumens='+str(expected) in tags and 'LUMENS' in row['intensity_units'];counts[kind]+=1;rows.append(row)
  if not row['passed']:issues.append(row)
 assert counts==dict(path=80,nautical=50),counts;assert sha(MAPFILE)==LOAD_SHA;write('lighting-audit',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,counts=counts,issues=issues,rows=rows,scope='Saved native settings for 130 new warm lights: lumens, schedule ownership, temperature, source radius, attenuation and no hard local shadows. Actual rendered day/night and performance remain separate.'))

def immersion_interior_cameras():
 plan=read('interior-probe-plan');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();rows=[];issues=[]
 for b in plan['buildings']:
  rooms=sorted(b['rooms'],key=lambda r:(r['floor'],r['id']));assert rooms;first=rooms[0];upper=next((r for r in reversed(rooms) if r['floor']>first['floor'] and r['type']!=first['type']),rooms[-1]);base=num(actors['Campus_'+b['building']+'_F01'].get_actor_location())
  def point(p):return [base[0]+p[1]*100,base[1]+p[0]*100,base[2]+p[2]*100]
  for role,r in [('primary',first),('upper',upper)]:
   d=r['door'];p=d['position_m'];center=r['position_m'];angle=math.radians(d['yaw_deg']);normal=[-math.sin(angle),math.cos(angle)];tangent=[math.cos(angle),math.sin(angle)];sign=1 if sum((center[i]-p[i])*normal[i] for i in range(2))>0 else -1;chosen=None;tried=[]
   for distance,lane in [(1.5,0),(2.,0),(1.,0),(2.5,0),(1.5,.35),(1.5,-.35)]:
    local=[p[i]+normal[i]*sign*distance+tangent[i]*lane for i in range(2)]+[p[2]];floor=point(local);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*floor[:2],floor[2]+30),unreal.Vector(*floor[:2],floor[2]-30),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
    if not h[0] or abs(h[4].z-floor[2])>5:tried.append(dict(distance=distance,lane=lane,reason='floor support'));continue
    ground=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*floor[:2],ground+98),unreal.Vector(*floor[:2],ground+99),35.,88.));tried.append(dict(distance=distance,lane=lane,result=s))
    if not s['blocked']:chosen=dict(id='interior-'+r['id']+'-'+role,building=b['building'],room=r['id'],name=r['name'],floor=r['floor'],type=r['type'],eye=[*floor[:2],ground+165],target=point([*center[:2],center[2]+1.3]),fov=85,actual_ground_cm=ground);break
   if chosen:rows.append(chosen)
   else:issues.append(dict(building=b['building'],room=r['id'],role=role,tried=tried))
 assert sha(MAPFILE)==LOAD_SHA;write('interior-cameras',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,rows=rows,issues=issues,scope='34 representative campus rooms at current actual world transforms, supported floor and player capsule clearance; day/night rendered review remains required.'))

def immersion_all_floor_cameras():
 plan=read('interior-probe-plan');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();before=ground_snapshot();assert before==read('preservation-after')['components'];rows=[];issues=[]
 for b in plan['buildings']:
  base=num(actors['Campus_'+b['building']+'_F01'].get_actor_location())
  def point(p):return [base[0]+p[1]*100,base[1]+p[0]*100,base[2]+p[2]*100]
  for level in sorted(f['floor'] for f in b['floors']):
   choices=sorted([r for r in b['rooms'] if r['floor']==level],key=lambda r:(r['type'] in ['toilet','shower','storage','bathroom','utility','lift'],r['id']));chosen=None;tried=[]
   for r in choices:
    d=r['door'];p=d['position_m'];center=r['position_m'];angle=math.radians(d['yaw_deg']);normal=[-math.sin(angle),math.cos(angle)];tangent=[math.cos(angle),math.sin(angle)];sign=1 if sum((center[i]-p[i])*normal[i] for i in range(2))>0 else -1
    for distance,lane in [(1.5,0),(2.,0),(1.,0),(2.5,0),(1.5,.35),(1.5,-.35)]:
     local=[p[i]+normal[i]*sign*distance+tangent[i]*lane for i in range(2)]+[p[2]];floor=point(local);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*floor[:2],floor[2]+30),unreal.Vector(*floor[:2],floor[2]-30),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
     if not h[0] or abs(h[4].z-floor[2])>5:continue
     ground=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*floor[:2],ground+98),unreal.Vector(*floor[:2],ground+99),35.,88.))
     if s['blocked']:continue
     eye=[*floor[:2],ground+165];target=point([*center[:2],center[2]+1.3])
     if math.dist(eye[:2],target[:2])<150:target=point([local[0]+normal[0]*sign*2.5,local[1]+normal[1]*sign*2.5,local[2]+1.55])
     target[2]=eye[2]-.04*math.dist(eye[:2],target[:2]);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*eye),unreal.Vector(*target),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);los=raw.to_tuple() if raw else [False]
     if los[0] and math.dist(num(los[4]),eye)<100:continue
     chosen=dict(id='floor-'+b['building']+'-F%02d'%level,building=b['building'],room=r['id'],name=r['name'],floor=level,type=r['type'],eye=eye,target=target,fov=85,actual_ground_cm=ground,camera_kind='native supported player-height interior;one room on every school floor');break
    if chosen:break
   if not chosen and not choices:
    level_plan=next(f for f in b['floors'] if f['floor']==level)
    for space in level_plan.get('open_public_spaces',[]):
     center=space['center_m']
     for offset in [-12.,-8.,-4.,0.,4.,8.,12.]:
      local=[center[0]+offset,center[1],center[2]];floor=point(local);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*floor[:2],floor[2]+30),unreal.Vector(*floor[:2],floor[2]-30),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
      if not h[0] or abs(h[4].z-floor[2])>5:continue
      ground=float(h[4].z);s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*floor[:2],ground+98),unreal.Vector(*floor[:2],ground+99),35.,88.))
      if s['blocked']:continue
      eye=[*floor[:2],ground+165];target=point([local[0]+10,local[1],local[2]+1.25]);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*eye),unreal.Vector(*target),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);los=raw.to_tuple() if raw else [False]
      if los[0] and math.dist(num(los[4]),eye)<100:continue
      chosen=dict(id='floor-'+b['building']+'-F%02d'%level,building=b['building'],room=space['id'],name=space['name'],floor=level,type='open_public_foyer',eye=eye,target=target,fov=85,actual_ground_cm=ground,camera_kind='native supported public foyer on floor without enclosed rooms');break
     if chosen:break
   if chosen:rows.append(chosen)
   else:issues.append(dict(building=b['building'],floor=level,reason='No room or open-foyer candidate met floor,capsule and near-view clearance'))
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('all-floor-cameras',dict(status='passed' if len(rows)==89 and not issues else 'requires_review',map_sha256=LOAD_SHA,rows=rows,issues=issues,buildings=len(plan['buildings']),scope='One physically supported165cm eye with35/88cm capsule clearance on every one of89 school floors;both day/night Game captures required. One room per floor does not represent every room.'));assert len(rows)==89 and not issues,issues

def immersion_stair_routes():
 plan=read('interior-probe-plan');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();before=ground_snapshot();assert before==read('preservation-after')['components'];routes=[];issues=[]
 for b in plan['buildings']:
  base=num(actors['Campus_'+b['building']+'_F01'].get_actor_location());f=b['floors'][0];chosen=None;tried=[]
  def point(p):return [base[0]+p[1]*100,base[1]+p[0]*100,base[2]+p[2]*100]
  for core in [c for c in f['vertical_circulation'] if c['kind']=='stairs']:
   g=core['walkable_geometry'];per=g['riser_count']//g['flight_count'];rise=f['height_m']/g['riser_count'];cx,cy,z=core['position_m'];run=g['flight_run_m'];local=[[cx-.9,cy-run/2-.75,z]];landing_indices=[0]
   for flight in range(g['flight_count']):
    xx=cx+(-.9 if flight%2==0 else .9);sign=1 if flight%2==0 else -1
    for step in range(per-1):local.append([xx,cy+sign*(-run/2+(step+.5)*g['tread_depth_m']),z+(flight*per+step+1)*rise])
    local.append([xx,cy+sign*(run/2+.75),z+(flight+1)*per*rise]);landing_indices.append(len(local)-1)
    if flight+1<g['flight_count']:local.append([cx+(.9 if flight%2==0 else -.9),cy+sign*(run/2+.75),z+(flight+1)*per*rise]);landing_indices.append(len(local)-1)
   points=[];failure=[]
   for i,p in enumerate(local):
    q=point(p);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(q[0],q[1],q[2]+30),unreal.Vector(q[0],q[1],q[2]-30),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
    if not h[0] or abs(h[4].z-q[2])>12 or h[7].z<.9:failure.append(dict(index=i,point=q,reason='stair/landing support',hit=num(h[4]) if h[0] else None));break
    q[2]=float(h[4].z);points.append(q)
    if i in landing_indices:
     s=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(q[0],q[1],q[2]+98),unreal.Vector(q[0],q[1],q[2]+99),35.,88.))
     if s['blocked']:failure.append(dict(index=i,point=q,reason='landing capsule blocked',detail=s));break
   tried.append(dict(core=core['id'],failures=failure))
   if not failure:chosen=dict(core=core['id'],points=points,riser_height_cm=rise*100,flight_count=g['flight_count'],landing_indices=landing_indices);break
  if not chosen:issues.append(dict(building=b['building'],tried=tried));continue
  for direction,points in [('up',chosen['points']),('down',list(reversed(chosen['points'])))]:routes.append(dict(id='interior-stair-'+b['building']+'-'+direction,kind='interior_stair',building=b['building'],core=chosen['core'],points=points,riser_height_cm=chosen['riser_height_cm'],flight_count=chosen['flight_count']))
 assert ground_snapshot()==before and sha(MAPFILE)==LOAD_SHA;write('stair-route-plan',dict(status='prepared_requires_actual_character_traversal' if len(routes)==34 and not issues else 'requires_review',map_sha256=LOAD_SHA,routes=routes,issues=issues,scope='Both directions through one complete first-to-second-floor stair core on each of17 school buildings. All tread/landing centers have native support;landing capsules clear. Actual CharacterMovement is required;stationary treads are not incorrectly rejected by a non-stepping capsule sweep.'));assert len(routes)==34 and not issues,issues

def immersion_prop_ground_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;probe=read('prop-ground-probe');assert probe['map_sha256']==LOAD_SHA and len(probe['suspects'])==9;assert not (OUT/'prop-ground-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();changes=[]
 for q in probe['suspects']:
  a=actors[q['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==q['component']);t=c.get_instance_transform(q['instance'],True);old=ground_transform(t);p=t.translation;x,y=p.x,p.y
  if q['actor']=='Resort_R010_4_campus-lake':y-=350;assert q['support_actor']=='FlatCampus_Fence_Cap'
  else:assert q['support_actor'] in ['G09','G10','G15'],q
  cx=q['center_cm'][0]+x-p.x;cy=q['center_cm'][1]+y-p.y;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(cx,cy,1285),unreal.Vector(cx,cy,1100),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[actors[v['actor']] for v in probe['suspects']],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];assert h[0] and h[9].get_actor_label().startswith('G') and 1190<h[4].z<1215,(q['actor'],h);z=p.z+h[4].z+.2-q['bottom_cm'];changes.append(dict(actor=q['actor'],component=q['component'],instance=q['instance'],before=old,target_cm=[x,y,z],old_gap_cm=q['gap_cm'],support=h[9].get_actor_label(),ground_cm=num(h[4])))
 backup=OUT/('UniversityCity-before-grounded-props-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for q in changes:
  a=actors[q['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==q['component']);t=c.get_instance_transform(q['instance'],True);t.translation=unreal.Vector(*q['target_cm']);assert c.update_instance_transform(q['instance'],t,True,True,True);q['after']=ground_transform(t)
 after=ground_snapshot();expected={(q['actor'],q['component'],q['instance']):q for q in changes};assert len(after)==len(before)
 for old,now in zip(before,after):
  row=json.loads(json.dumps(now))
  for i,t in enumerate(row.get('instances',[])):
   key=(row['actor'],row['component'],i)
   if key in expected:assert t==expected[key]['after'];row['instances'][i]=expected[key]['before']
  assert row==old,('Unintended grounding change',row['actor'])
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,grounded_campus_props=9);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('prop-ground-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=changes,scope='Ground eight sunken/floating garden fixtures, move one bench 3.5m inward out of the campus fence, preserve remaining component state.'))

def immersion_water_walk_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();points=[[83100,75750],[84600,75750],[84600,74900],[85850,74900],[85850,76600],[84600,76600],[84600,75750]];floors=[];sweeps=[];bad=[]
 for route,(a,b) in enumerate(zip(points,points[1:])):
  count=math.ceil(math.dist(a,b)/75)
  for i in range(count+1):
   p=[a[j]+(b[j]-a[j])*i/count for j in range(2)];raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*p,1236),unreal.Vector(*p,1180),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];row=dict(route=route,xy_cm=p,passed=bool(h[0]) and abs(h[4].z-1206)<1,hit_cm=num(h[4]) if h[0] else None);floors.append(row)
   if not row['passed']:bad.append(row)
  q=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*a,1304),unreal.Vector(*b,1304),35.,88.));sweeps.append(dict(route=route,start_cm=a,end_cm=b,result=q))
  if q['blocked']:bad.append(sweeps[-1])
 assert sha(MAPFILE)==LOAD_SHA;write('water-walk-probe',dict(status='passed' if not bad else 'requires_review',map_sha256=LOAD_SHA,points_cm=points,floors=floors,sweeps=sweeps,issues=bad,scope='Native supported access and 35cm-radius/88cm-half-height visitor route around the grounded koi pond; no route passes through pond volume.'))

def immersion_lantern_import():
 global PREFIX,KEEP,save
 PREFIX=IMM+'/NauticalLantern';KEEP=[];save=save_asset
 source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)");namespace=dict(globals());exec('def import_one('+source,namespace);import_one=namespace['import_one'];api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem);meshes=[];metal=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');opal=EAL.load_asset('/Game/UniversityCity/EnvironmentV1/Materials/M_EnvironmentOpal_01');assert metal and opal
 for lod in range(3):
  mesh=import_one(OUT/'nautical-lantern'/('LOD'+str(lod)+'.glb'),'nautical-lantern',lod,False)
  for i,slot in enumerate(mesh.get_editor_property('static_materials')):
   name=str(slot.get_editor_property('imported_material_slot_name')).lower();assert 'bronze' in name or 'opal' in name;mesh.set_material(i,opal if 'opal' in name else metal)
  assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
 mesh=meshes[0]
 for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
 assert api.set_lod_screen_sizes(mesh,[1.,.16,.045]);mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(mesh,False);assert sha(MAPFILE)==LOAD_SHA
 write('lantern-import',dict(status='passed',map_sha256=LOAD_SHA,asset=mesh.get_path_name(),materials=[mesh.get_material(i).get_path_name() for i in range(mesh.get_num_sections(0))],triangles=[mesh.get_num_triangles(i) for i in range(3)]))

def immersion_lantern_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'lantern-install.json').exists();imported=read('lantern-import');mesh=EAL.load_asset(imported['asset']);assert mesh;before=ground_snapshot();assert before==read('preservation-after')['components'];backup=OUT/('UniversityCity-before-nautical-lantern-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);changes=[];fixtures=[]
 for a in SUB.get_all_level_actors():
  if a.get_editor_property('hidden'):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or '/ResortV1/Assets/R057/' not in c.static_mesh.get_path_name() or not c.get_editor_property('visible') or c.get_editor_property('hidden_in_game'):continue
   old=c.static_mesh.get_path_name();name=c.get_name();instanced=isinstance(c,unreal.InstancedStaticMeshComponent);transforms=[c.get_instance_transform(i,True) for i in range(c.get_instance_count())] if instanced else [c.get_world_transform()];assert transforms
   c.modify();c.set_static_mesh(mesh);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name);c.set_editor_property('override_materials',[mesh.get_material(i) for i in range(len(mesh.get_editor_property('static_materials')))]);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name)
   if instanced:
    actual=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]
    if actual!=[ground_transform(t) for t in transforms]:c.clear_instances();c.add_instances(transforms,False,True,True)
    assert [ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]==[ground_transform(t) for t in transforms]
   changes.append(dict(actor=a.get_actor_label(),component=name,before=old,after=mesh.get_path_name(),materials=[c.get_material(i).get_path_name() for i in range(c.get_num_materials())]))
   for t in transforms:fixtures.append(dict(actor=a.get_actor_label(),head_cm=num(t.transform_location(unreal.Vector(46,0,267)))))
 assert len(changes)==10 and len(fixtures)==50,(len(changes),len(fixtures));lights=[]
 for i,q in enumerate(fixtures):
  a=SUB.spawn_actor_from_class(unreal.PointLight,unreal.Vector(*q['head_cm']));a.set_actor_label('Immersion_NauticalLight_%03d'%i);a.tags=[unreal.Name('ImmersionV1'),unreal.Name('EnvGroup=Path'),unreal.Name('EnvLumens=55')];a.set_folder_path('UniversityCity/ImmersionV1');c=a.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(55);c.set_temperature(2800);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',400);c.set_editor_property('source_radius',12);c.set_editor_property('volumetric_scattering_intensity',.15);c.set_cast_shadows(False);lights.append(a.get_actor_label())
 after=ground_snapshot();expected={(q['actor'],q['component']):q for q in changes};assert len(after)==len(before)
 for old,now in zip(before,after):
  row=dict(now);key=(row['actor'],row['component'])
  if key in expected:assert row['mesh']==expected[key]['after'] and row['materials']==expected[key]['materials'];row['mesh']=old['mesh'];row['materials']=old['materials']
  assert row==old,('Unintended lantern change',key)
 controller=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController');controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,nautical_lantern_components=10,nautical_lanterns=50);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('lantern-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=changes,fixtures=fixtures,light_actors=lights,lumens=55,temperature_kelvin=2800,shadows=False,scope='Recognizable metal hanging lanterns replace R057 silhouettes; positions, scale, collision and unrelated geometry preserved; warm low-intensity light follows existing Path day/night schedule.'))

def immersion_water_activity_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;assert not (OUT/'water-activity-install.json').exists();plan=json.loads((ROOT/'output/street-social-city-production/activity-scenes-v1/plan.json').read_text('utf-8-sig'));before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};proposed=[];base=19.7295113
 for q in plan['instances']:
  if q.get('scene')!='ACTSPACE-06':continue
  label='Activity_'+q['id'];a=actors[label]
  if a.get_editor_property('hidden'):continue
  p=q['position_m'];now=num(a.get_actor_location());assert math.dist(now[:2],[p[1]*100,p[0]*100])<1,(label,now,p);target=1206+(p[2]-base)*100;proposed.append(dict(actor=label,asset=q['asset'],before=actor_xform(a),target_location_cm=[now[0],now[1],target]))
 for i,q in enumerate(plan['lights']):
  if q.get('scene')!='ACTSPACE-06':continue
  label='Activity_Light_'+str(i);a=actors[label];p=q['position_m'];now=num(a.get_actor_location());assert math.dist(now[:2],[p[1]*100,p[0]*100])<1;proposed.append(dict(actor=label,asset='light',before=actor_xform(a),target_location_cm=[now[0],now[1],1206+(p[2]-base)*100]))
 assert len(proposed)==22,len(proposed);backup=OUT/('UniversityCity-before-water-activity-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for q in proposed:
  a=actors[q['actor']];a.modify();a.set_actor_location(unreal.Vector(*q['target_location_cm']),False,False);q['after']=actor_xform(a)
 after=ground_snapshot();expected={r['actor'] for r in proposed};oldrows={(r['actor'],r['component']):r for r in before}
 for now in after:
  old=oldrows[(now['actor'],now['component'])]
  if now['actor'] in expected:
   change=next(q for q in proposed if q['actor']==now['actor']);assert now['actor_transform']==change['after'];assert now['actor_transform']['rotation']==old['actor_transform']['rotation'] and now['actor_transform']['scale']==old['actor_transform']['scale'];copy=dict(now);copy['transform']=old['transform'];copy['actor_transform']=old['actor_transform'];assert copy==old,('Unexpected water activity change',now['actor'])
  else:assert now==old,('Unrelated water activity change',now['actor'])
 assert len(after)==len(before);controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,waterfront_activity_objects=20);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('water-activity-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=proposed,scope='Restore all 20 Koi viewing props and two water lights to their authored relative heights on the corrected 1206cm deck; XY, rotation, scale, materials and all unrelated geometry preserved.'))

def immersion_prop_ground_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();rows=[];suspects=[]
 for a in SUB.get_all_level_actors():
  if a.get_editor_property('hidden'):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh or not c.get_editor_property('visible') or c.get_editor_property('hidden_in_game') or '/ResortV1/Assets/' not in c.static_mesh.get_path_name():continue
   b=c.static_mesh.get_bounds();transforms=[(i,c.get_instance_transform(i,True)) for i in range(c.get_instance_count())] if isinstance(c,unreal.InstancedStaticMeshComponent) else [(-1,c.get_world_transform())]
   for index,t in transforms:
    center=t.transform_location(b.origin)
    if not(54800<center.x<97000 and 19500<center.y<77000):continue
    points=[t.transform_location(unreal.Vector(b.origin.x+sx*b.box_extent.x,b.origin.y+sy*b.box_extent.y,b.origin.z+sz*b.box_extent.z)) for sx in [-1,1] for sy in [-1,1] for sz in [-1,1]];low=min(p.z for p in points);high=max(p.z for p in points)
    if high-low>650 or low>1800 or low<950:continue
    raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(center.x,center.y,low+80),unreal.Vector(center.x,center.y,low-500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[a],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False];row=dict(actor=a.get_actor_label(),component=c.get_name(),instance=index,mesh=c.static_mesh.get_path_name(),center_cm=num(center),bottom_cm=low,top_cm=high,hit=bool(h[0]),support_actor=h[9].get_actor_label() if h[0] and h[9] else None,support_cm=num(h[4]) if h[0] else None,gap_cm=low-h[4].z if h[0] else None);rows.append(row)
    if not h[0] or abs(low-h[4].z)>5:suspects.append(row)
 assert sha(MAPFILE)==LOAD_SHA;write('prop-ground-probe',dict(status='diagnostic_requires_review',map_sha256=LOAD_SHA,checked=len(rows),suspects=suspects,rows=rows,scope='Per-instance native mesh-bound bottom against supporting collision, excluding own component owner. Elevated or wall-hung objects are candidates, not automatically errors.'))

def immersion_canopy_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA;probe=read('canopy-probe');assert probe['map_sha256']==LOAD_SHA and len(probe['canopies'])==34;assert not (OUT/'canopy-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];backup=OUT/('UniversityCity-before-campus-canopies-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};changes=[];parts=[]
 for r in probe['canopies']:
  a=actors[r['actor']];c=next(q for q in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if q.get_name()==r['component']);t=c.get_instance_transform(r['instance'],True);assert ground_transform(t)==r['transform'];floor=r['entrance']['world_cm'][2];delta=floor+260-r['bounds_min'][2];old=ground_transform(t);p=t.translation;t.translation=unreal.Vector(p.x,p.y,p.z+delta);assert c.update_instance_transform(r['instance'],t,True,True,True);changes.append(dict(actor=r['actor'],component=r['component'],instance=r['instance'],before=old,after=ground_transform(t),entrance=r['entrance']['entry'],bottom_cm=floor+260,top_cm=r['bounds_max'][2]+delta))
  wx,wy=r['entrance']['world_cm'][:2];nx,ny=p.x-wx,p.y-wy;length=math.hypot(nx,ny);assert length>10;nx/=length;ny/=length;tx,ty=-ny,nx;yaw=math.degrees(math.atan2(ty,tx))
  for side in [-1,1]:
   x,y=wx+tx*side*145,wy+ty*side*145
   parts.extend([dict(center=[x+nx*53,y+ny*53,floor+257],size=[8,114,8],yaw=yaw),dict(center=[x+nx*1,y+ny*1,floor+250],size=[10,8,24],yaw=yaw)])
 world=unreal.EditorLevelLibrary.get_editor_world();material=EAL.load_asset('/Game/UniversityCity/FlatCampusV1/Materials/M_CampusBronze');c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,EAL.load_asset('/Engine/BasicShapes/Cube'),material,'FlatCampus_Immersion_CanopyMounts');assert c;a=c.get_owner();label='Immersion_CanopyMounts';a.set_actor_label(label);a.tags=[unreal.Name('ImmersionV1')];a.set_folder_path('UniversityCity/ImmersionV1');c.set_collision_profile_name('NoCollision');c.set_cull_distances(0,0);c.add_instances([unreal.Transform(location=unreal.Vector(*r['center']),rotation=unreal.Rotator(yaw=r['yaw']),scale=unreal.Vector(*[v/100 for v in r['size']])) for r in parts],False,True,True)
 after=ground_snapshot();expected={(r['actor'],r['component'],r['instance']):r for r in changes}
 for old,now in zip(before,[r for r in after if r['actor']!=label]):
  row=json.loads(json.dumps(now))
  for i,t in enumerate(row.get('instances',[])):
   key=(row['actor'],row['component'],i)
   if key in expected:assert t==expected[key]['after'];row['instances'][i]=expected[key]['before']
  assert row==old,('Unintended canopy change',row['actor'])
 assert len(after)==len(before)+1;next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,preserved_components=len(after),supported_campus_canopies=34);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('canopy-install',dict(status='saved_requires_reopen_and_game_review',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),changes=changes,bracket_parts=len(parts),scope='Lower existing canopy roofs below signage and add wall plates/cantilever arms; keep door apertures and all unrelated components unchanged.'))

def immersion_canopy_probe():
 plan=read('interior-probe-plan');entrances=[];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for b in plan['buildings']:
  base=num(actors['Campus_'+b['building']+'_F01'].get_actor_location())
  for e in b['entrances']:
   p=e['position_m'];entrances.append(dict(building=b['building'],entry=e['id'],world_cm=[base[0]+p[1]*100,base[1]+p[0]*100,base[2]+p[2]*100]))
 for a in actors.values():
  if not a.get_actor_label().startswith('CityArt_canopy') or a.get_editor_property('hidden'):continue
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   if not c.static_mesh or not c.get_editor_property('visible') or c.get_editor_property('hidden_in_game'):continue
   b=c.static_mesh.get_bounds()
   for i in range(c.get_instance_count()):
    t=c.get_instance_transform(i,True);p=num(t.translation);near=min(entrances,key=lambda e:math.dist(p[:2],e['world_cm'][:2]));d=math.dist(p[:2],near['world_cm'][:2])
    if d>200:continue
    points=[num(t.transform_location(unreal.Vector(b.origin.x+sx*b.box_extent.x,b.origin.y+sy*b.box_extent.y,b.origin.z+sz*b.box_extent.z))) for sx in [-1,1] for sy in [-1,1] for sz in [-1,1]]
    rows.append(dict(actor=a.get_actor_label(),component=c.get_name(),instance=i,transform=ground_transform(t),entrance=near,mesh=c.static_mesh.get_path_name(),bounds_min=[min(q[j] for q in points) for j in range(3)],bounds_max=[max(q[j] for q in points) for j in range(3)]))
 write('canopy-probe',dict(status='passed',map_sha256=LOAD_SHA,canopies=rows))

def immersion_door_clearance_install():
 installed=read('install');plan=read('door-clearance-plan');assert installed['map_sha256']==plan['map_sha256']==LOAD_SHA and not (OUT/'door-clearance-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-door-clearance-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);shutil.copy2(OUT/'door-capsule-probe.json',OUT/'door-clearance-before-capsules.json');shutil.copy2(OUT/'interior-native-probe.json',OUT/'door-clearance-before-interiors.json')
 for m in plan['meshes']:
  assert not EAL.does_asset_exist(m['after'])
  for l in m['lods']:assert sha(l['vertices'])==l['sha256']
 for group in plan['groups']:
  assert len(group['members'])==5
  for r in group['members']:assert actor_xform(actors[r['actor']])==r['before']
 native=json.loads(unreal.CityDepthAuditLibrary.apply_flat_world_meshes(world,str(OUT/'door-clearance-plan.json')));write('door-clearance-native',native);assert native['status']=='passed',native;changes=[]
 for group in plan['groups']:
  for r in group['members']:
   a=actors[r['actor']];p=a.get_actor_location();d=r['delta_cm'];assert a.set_actor_location(unreal.Vector(p.x+d[0],p.y+d[1],p.z+d[2]),False,True);changes.append(dict(r,after=actor_xform(a)))
 after=ground_snapshot();moved={r['actor']:r for r in changes};replaced={m['key']:m for m in plan['meshes']};assert len(before)==len(after)
 for old,now in zip(before,after):
  q=json.loads(json.dumps(now));key=q['actor']+'::'+q['component']
  if key in replaced:assert q['mesh'].split('.')[0]==replaced[key]['after'];q['mesh']=old['mesh']
  if q['actor'] in moved:
   r=moved[q['actor']];assert q['actor_transform']==r['after'];assert q['actor_transform']['rotation']==old['actor_transform']['rotation'] and q['actor_transform']['scale']==old['actor_transform']['scale'];assert all(abs(q['transform']['translation'][i]-old['transform']['translation'][i]-r['delta_cm'][i])<.01 for i in range(3));q['actor_transform']=old['actor_transform'];q['transform']=old['transform']
  assert q==old,('Unintended door clearance change',key)
 immersion_door_capsule_probe();doors=read('door-capsule-probe');immersion_interior_probe();interiors=read('interior-native-probe');immersion_route_review();routes=read('route-native-review');write('door-clearance-preflight',dict(status='passed' if doors['status']==interiors['status']==routes['status']=='passed' else 'requires_repair',source_map_sha256=LOAD_SHA,scope='Unsaved candidate: moved30 complete service-counter actors and only902 shower vertices across5 floor meshes; all unrelated vertex positions and component bindings retained. New fixture collision must pass all door/interior/route checks before save.',door_status=doors['status'],door_issues=doors['issues'],door_checks=doors['doors'],interior_status=interiors['status'],interior_issues=interiors['issues'],interior_checks=interiors['checks'],route_status=routes['status'],route_unsupported=routes['unsupported'],route_blocked=routes['blocked']));assert doors['status']==interiors['status']==routes['status']=='passed','Door clearance preflight rejected; do not save candidate. Reopen audit before repair.'
 actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,cleared_door_approaches=11);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('door-clearance-install',dict(status='saved_requires_reopen_and_cooked_capsule_validation',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),counter_changes=changes,mesh_changes=native,geometry_plan_sha256=sha(OUT/'door-clearance-plan.json'),native_pre_save_doors=doors['doors'],native_pre_save_interior_checks=interiors['checks'],native_pre_save_route_sweeps=routes['capsule_sweeps'],policy=plan['policy']))

def immersion_door_capsule_probe():
 plan=read('interior-probe-plan');world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];issues=[]
 for b in plan['buildings']:
  base=num(actors['Campus_'+b['building']+'_F01'].get_actor_location());doors=[dict(d,kind=d.get('kind','interior')) for d in b['doors']]+[dict(e,yaw_deg=e['rotation_z_deg'],floor=1,kind='entrance') for e in b['entrances']]
  for d in doors:
   if d['kind']=='lift' and d['floor']>1:continue
   x,y,z=d['position_m'];theta=math.radians(d['yaw_deg']);nx,ny=math.cos(theta),-math.sin(theta);cx,cy,floor=base[0]+y*100,base[1]+x*100,base[2]+z*100;supports=[];q=dict(building=b['building'],id=d['id'],kind=d['kind'],floor=d['floor'],width_cm=d['width_m']*100,height_cm=d['height_m']*100)
   for side in [-1,0,1]:
    px,py=cx+nx*side*70,cy+ny*side*70;raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(px,py,floor+40),unreal.Vector(px,py,floor-30),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None;supports.append(dict(xy_cm=[px,py],expected_floor_cm=floor,hit=bool(h and h[0]),point_cm=num(h[4]) if h and h[0] else None,actor=h[9].get_actor_label() if h and h[0] and h[9] else None))
   q['supports']=supports
   if not all(r['hit'] for r in supports):q['issue']='missing_door_threshold_support';issues.append(q);rows.append(q);continue
   body_z=max(r['point_cm'][2] for r in supports)+98;start=[*supports[0]['xy_cm'],body_z];end=[*supports[-1]['xy_cm'],body_z];result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*start),unreal.Vector(*end),35.,88.));q.update(start=start,end=end,body_center_cm=body_z,sweep=result,passed=not result['blocked'])
   if result['blocked']:q['issue']='player_capsule_door_obstruction';issues.append(q)
   rows.append(q)
 assert sha(MAPFILE)==LOAD_SHA;write('door-capsule-probe',dict(status='passed' if not issues else 'requires_repair',map_sha256=LOAD_SHA,doors=len(rows),support_rays=len(rows)*3,capsule_radius_cm=35,capsule_half_height_cm=88,rows=rows,issues=issues,scope='All17 buildings: entrance and open interior door passage with3 local floor support rays and real native player-sized capsule. Closed upper-floor lift panels intentionally excluded; max threshold floor used for step-clearance sweep. No source mutation.'))

def immersion_court_light_balance():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA and not (OUT/'court-light-balance.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-court-light-balance-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);rows=[]
 for i in range(2):
  a=actors['Immersion_Court_Light_'+str(i)];c=a.light_component;tags=[str(t) for t in a.tags];assert 'EnvGroup=Sport' in tags and 'EnvLumens=6000' in tags and not c.get_editor_property('cast_shadows');old=dict(actor=a.get_actor_label(),transform=actor_xform(a),source_radius_cm=float(c.get_editor_property('source_radius')),tags=tags);a.tags=[unreal.Name('EnvLumens=3500' if t=='EnvLumens=6000' else t) for t in tags];c.set_intensity(3500);c.set_editor_property('source_radius',70);c.set_editor_property('volumetric_scattering_intensity',0.);assert actor_xform(a)==old['transform'];rows.append(dict(before=old,target_lumens=3500,source_radius_cm=70,cast_shadows=False,temperature_kelvin=4000))
 controller=actors['CityEnvironmentController'];controller.refresh_bindings();controller.prepare_for_save();after=ground_snapshot();assert after==before;assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,court_fixture_target_lumens=3500);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('court-light-balance',dict(status='saved_requires_reopen_day_night_comparison',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),changes=rows,policy='Only two new court lamps:6000→3500lm,50→70cm source radius,zero volumetric scattering. Existing schedule,4000K,aim,positions,all scene meshes/materials,sky and ambient exposure retained. Reduce local glare contrast while keeping court readable.'))

def immersion_ground_facing_install():
 source=read('ground-facing-source');installed=read('install');plan=read('ground-facing-plan');assert source['map_sha256']==installed['map_sha256']==LOAD_SHA and source['plan_sha256']==sha(OUT/'ground-facing-plan.json') and not plan['blocked'] and not (OUT/'ground-facing-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};components={a.get_actor_label()+'::'+c.get_name():c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)};diagnostics=[]
 for m in plan['meshes']:
  assert len(m['component_keys'])==1 and m['component_keys'][0] in ['G06::StaticMeshComponent0','G07::StaticMeshComponent0'];c=components[m['component_keys'][0]];assert c.static_mesh.get_path_name()==m['source_asset']
  for i in range(c.get_num_materials()):
   r=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(c.get_material(i)));assert r['static_opaque_no_depth_displacement'];diagnostics.append(r)
 backup=OUT/('UniversityCity-before-ground-facing-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);native=json.loads(unreal.CityDepthAuditLibrary.apply_facing_partition(world,str(OUT/'ground-facing-plan.json')));write('ground-facing-native',native);assert native['status']=='passed',native;wrappers={}
 def wrapper(parent):
  path=parent.get_path_name()
  if path not in wrappers:
   folder=IMM+'/GroundDepth/Materials';name='MI_ImmersionFacing_'+hashlib.sha256(path.encode()).hexdigest()[:24];mi=EAL.load_asset(folder+'/'+name) or ATS.create_asset(name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,parent);p=mi.get_editor_property('base_property_overrides');p.set_editor_property('override_two_sided',True);p.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',p)
   for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mi.get_editor_property(field))
   MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);wrappers[path]=mi
  return wrappers[path]
 for m in native['meshes']:
  c=components[m['component_keys'][0]];mesh=c.static_mesh;static=list(mesh.get_editor_property('static_materials'))
  for s in m['added_material_slots']:
   parent=static[s['source_slot']].get_editor_property('material_interface');static[s['added_slot']].set_editor_property('material_interface',wrapper(parent));c.set_material(s['added_slot'],wrapper(c.get_material(s['source_slot'])))
  mesh.set_editor_property('static_materials',static);assert EAL.save_loaded_asset(mesh,False)
 collision=json.loads(unreal.CityDepthAuditLibrary.preserve_repair_collision(world,str(OUT/'ground-facing-native.json')));write('ground-facing-collision',collision);assert collision['status']=='passed',collision;after=ground_snapshot();expected={m['component_keys'][0]:m for m in native['meshes']};assert len(before)==len(after)
 for old,now in zip(before,after):
  q=dict(now);key=q['actor']+'::'+q['component']
  if key in expected:
   m=expected[key];assert q['mesh']==m['after'] and q['materials'][:len(old['materials'])]==old['materials'] and len(q['materials'])==len(old['materials'])+len(m['added_material_slots']);q['mesh']=old['mesh'];q['materials']=old['materials']
  assert q==old,('Unexpected terrain facing change',key)
 actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,terrain_opposite_facing_partition_meshes=len(native['meshes']));write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('ground-facing-install',dict(status='saved_requires_reopen_visual_and_depth_rescan',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),native=native,collision=collision,material_diagnostics=diagnostics,source=source,policy='Only covered portions of two-sided opposite faces become single-sided; no geometry/UV/elevation movement, no uncovered surface removal, original materials retained through parameter-free wrappers and original collision hashes identical.'))

def immersion_ground_material_context():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};paths={}
 for label,a in actors.items():
  if not re.fullmatch(r'G\d\d',label):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   for i in range(c.get_num_materials()):
    m=c.get_material(i)
    if m and ('Tripo-ground-' in m.get_path_name()):paths.setdefault(m.get_path_name(),[]).append(dict(actor=label,component=c.get_name(),slot=i))
 registry=unreal.AssetRegistryHelpers.get_asset_registry();options=unreal.AssetRegistryDependencyOptions(include_hard_package_references=True,include_soft_package_references=False,include_searchable_names=False,include_soft_management_references=False,include_hard_management_references=False);rows=[]
 for path,uses in paths.items():
  m=EAL.load_asset(path);queue=[path.split('.')[0]];seen=set();dependencies=[]
  for level in range(5):
   nextqueue=[]
   for package in queue:
    if package in seen:continue
    seen.add(package)
    for name in registry.get_dependencies(unreal.Name(package),options):
     p=str(name)
     if p.startswith('/Game/UniversityCity/') and p not in seen:nextqueue.append(p)
     if p not in dependencies:dependencies.append(p)
   queue=nextqueue
  rows.append(dict(material=path,class_name=m.get_class().get_name(),uses=uses,dependencies=sorted(dependencies)))
 assert sha(MAPFILE)==LOAD_SHA;write('ground-material-context',dict(status='recorded',map_sha256=LOAD_SHA,rows=rows,scope='Read-only dependency provenance of remaining Tripo-named terrain materials; names alone do not establish shader contents.'))

def immersion_canopy_junction_install():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA and not (OUT/'canopy-junction-install.json').exists();before=ground_snapshot();assert before==read('preservation-after')['components'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};changes=[]
 def bounds(mesh,t):
  b=mesh.get_bounds();ps=[num(t.transform_location(unreal.Vector(b.origin.x+sx*b.box_extent.x,b.origin.y+sy*b.box_extent.y,b.origin.z+sz*b.box_extent.z))) for sx in [-1,1] for sy in [-1,1] for sz in [-1,1]];return [[min(p[k] for p in ps) for k in range(3)],[max(p[k] for p in ps) for k in range(3)]]
 for label,delta,back in [('CityArt_canopy_6a2a0d0ad9bd',-22.5,0),('CityArt_canopy_fd8ba9634f3b',22.5,1)]:
  a=actors[label];cs=a.get_components_by_class(unreal.InstancedStaticMeshComponent);assert len(cs)==1;c=cs[0];assert c.get_instance_count()==2 and str(c.get_collision_profile_name())=='NoCollision';t=c.get_instance_transform(1,True);old=ground_transform(t);assert abs(t.translation.x-(45855 if back==0 else 45945))<.01 and abs(t.scale3d.y-1.25)<.001;oldbounds=bounds(c.static_mesh,t);p=t.translation;s=t.scale3d;t.translation=unreal.Vector(p.x+delta,p.y,p.z);t.scale3d=unreal.Vector(s.x,.8,s.z);newbounds=bounds(c.static_mesh,t);assert abs(oldbounds[back][0]-newbounds[back][0])<.01
  changes.append(dict(actor=label,component=c.get_name(),instance=1,before=old,after=ground_transform(t),bounds_before_cm=oldbounds,bounds_after_cm=newbounds));assert c.update_instance_transform(1,t,True,True,True)
 gap=changes[1]['bounds_after_cm'][0][0]-changes[0]['bounds_after_cm'][1][0];assert gap>50
 after=ground_snapshot();expected={(r['actor'],r['component'],r['instance']):r for r in changes};assert len(before)==len(after)
 for old,now in zip(before,after):
  q=json.loads(json.dumps(now))
  for i,t in enumerate(q.get('instances',[])):
   key=(q['actor'],q['component'],i)
   if key in expected:assert t==expected[key]['after'];q['instances'][i]=expected[key]['before']
  assert q==old,('Unexpected canopy junction change',now['actor'])
 backup=OUT/('UniversityCity-before-canopy-junction-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,separated_city_canopy_junction_cm=gap);write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('canopy-junction-install',dict(status='saved_requires_reopen_visual_and_depth_rescan',before_map_sha256=LOAD_SHA,map_sha256=newsha,backup=str(backup),changes=changes,clear_gap_cm=gap,policy='Two overlapping opposite storefront canopy instances shortened125→80cm depth, retaining wall-side edges and320cm widths, original heights/materials/NoCollision. All other instances, buildings and interiors unchanged.'))

def immersion_building_depth_context():
 world=unreal.EditorLevelLibrary.get_editor_world();path=OUT/'depth-campus-buildings-8b1b05a28f1d'/'depth-report.conflicts.jsonl';rows=[];seen=set();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for line in path.read_text('utf8').splitlines():
  r=json.loads(line)
  if r['pass_lod']!=0:continue
  key=(r['a_actor'],r['a_material_slot'],r['b_actor'],r['b_material_slot'],tuple(round(v,1) for v in r['center_cm']))
  if key in seen:continue
  seen.add(key);x,y,z=r['center_cm'];samples=[]
  for dx,dy in [(0,0),(5,0),(-5,0),(0,5),(0,-5)]:
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x+dx,y+dy,z+180),unreal.Vector(x+dx,y+dy,z-10),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else None;samples.append(dict(offset_cm=[dx,dy],hit=bool(h and h[0]),point_cm=num(h[4]) if h and h[0] else None,actor=h[9].get_actor_label() if h and h[0] and h[9] else None))
  rows.append(dict(candidate=r,above_support_probes=samples))
 canopies=[]
 for label in ['CityArt_canopy_6a2a0d0ad9bd','CityArt_canopy_fd8ba9634f3b']:
  a=actors[label]
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   bounds=c.static_mesh.get_bounds();canopies.append(dict(actor=label,component=c.get_name(),mesh=c.static_mesh.get_path_name(),local_origin=num(bounds.origin),local_extent=num(bounds.box_extent),instances=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]))
 assert sha(MAPFILE)==LOAD_SHA;write('building-depth-context',dict(status='diagnostic_requires_manual_review',map_sha256=LOAD_SHA,rows=rows,canopies=canopies,scope='Read-only support rays above building depth candidates; positive upper cover is occlusion evidence, not removal authorization. Geometry positions outside modified terrain retain prior export.'))

def immersion_ground_sheet_preflight():
 source=read('ground-sheet-source');plan=read('ground-sheet-plan');assert source['map_sha256']==LOAD_SHA and plan['scene_sha256']==source['scene_sha256'] and not plan['blocked']
 assert all(re.fullmatch(r'G\d\d',m['component_keys'][0].split('::')[0]) or (source.get('target_mode')=='connection' and m['component_keys'][0].split('::')[0]=='Outdoor_connection') for m in plan['meshes'])
 materials=set(c['material'] for c in plan['covers'])
 for m in plan['meshes']:
  for l in m['lods']:
   for p in l['patches']:materials.add(m['materials'][p['material_slot']])
 rows=[json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(EAL.load_asset(p))) for p in sorted(materials)]
 assert all(r['static_opaque_no_depth_displacement'] for r in rows),rows
 assert sha(MAPFILE)==LOAD_SHA;write('ground-sheet-preflight',dict(status='passed',map_sha256=LOAD_SHA,plan_sha256=sha(OUT/'ground-sheet-plan.json'),meshes=len(plan['meshes']),patches=plan['modified_source_triangles'],materials=rows,policy='Only16 terrain components; no elevation/UV/material replacement; exact original collision retained after render partition. Native area and cover validation required on apply.'))

def immersion_ground_sheet_install():
 installed=read('install');pre=read('ground-sheet-preflight');plan=read('ground-sheet-plan')
 assert installed['map_sha256']==pre['map_sha256']==LOAD_SHA and pre['status']=='passed' and pre['plan_sha256']==sha(OUT/'ground-sheet-plan.json')
 if (OUT/'ground-sheet-install.json').exists():
  old=read('ground-sheet-install');assert read('audit')['map_sha256']==LOAD_SHA and read('audit')['status']=='passed';archive=Path(read('ground-sheet-source')['prior_pass_archive']);assert archive.parent==OUT/'ground-sheet-history' and (archive/'ground-sheet-install.json').read_bytes()==(OUT/'ground-sheet-install.json').read_bytes()
 before=ground_snapshot();assert before==read('preservation-after')['components'];world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};components={a.get_actor_label()+'::'+c.get_name():c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)}
 for m in plan['meshes']:assert len(m['component_keys'])==1 and components[m['component_keys'][0]].static_mesh.get_path_name()==m['source_asset']
 backup=OUT/('UniversityCity-before-ground-sheets-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 result=json.loads(unreal.CityDepthAuditLibrary.apply_world_sheet_repair(world,str(OUT/'ground-sheet-plan.json')));write('ground-sheet-native',result);assert result['status']=='passed',result;wrappers={}
 def wrapper(parent):
  path=parent.get_path_name()
  if path not in wrappers:
   name='MI_ImmersionFacing_'+hashlib.sha256(path.encode()).hexdigest()[:24];folder=IMM+'/GroundDepth/Materials';asset=folder+'/'+name;mi=EAL.load_asset(asset) if EAL.does_asset_exist(asset) else ATS.create_asset(name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,parent);props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',props)
   for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mi.get_editor_property(field))
   MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);wrappers[path]=mi
  return wrappers[path]
 for m in result['meshes']:
  c=components[m['component_keys'][0]];mesh=c.static_mesh;static=list(mesh.get_editor_property('static_materials'))
  for s in m['added_material_slots']:
   parent=static[s['source_slot']].get_editor_property('material_interface');static[s['added_slot']].set_editor_property('material_interface',wrapper(parent));c.set_material(s['added_slot'],wrapper(c.get_material(s['source_slot'])))
  mesh.set_editor_property('static_materials',static);assert EAL.save_loaded_asset(mesh,False)
 collision=json.loads(unreal.CityDepthAuditLibrary.preserve_repair_collision(world,str(OUT/'ground-sheet-native.json')));write('ground-sheet-collision',collision);assert collision['status']=='passed',collision
 after=ground_snapshot();expected={m['component_keys'][0]:m for m in result['meshes']};assert len(before)==len(after)
 for old,now in zip(before,after):
  key=now['actor']+'::'+now['component'];q=dict(now)
  if key in expected:
   m=expected[key];assert q['mesh']==m['after'];assert q['materials'][:len(old['materials'])]==old['materials'];assert len(q['materials'])==len(old['materials'])+len(m['added_material_slots']);q['mesh']=old['mesh'];q['materials']=old['materials']
  assert q==old,('Unexpected ground sheet scene change',key)
 actors['CityEnvironmentController'].prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,terrain_depth_partition_meshes=len(result['meshes']));write('install',installed);write('preservation-after',dict(status='recorded',map_sha256=newsha,components=after));write('ground-sheet-install',dict(status='saved_requires_reopen_visual_and_independent_depth_rescan',map_sha256=newsha,before_map_sha256=LOAD_SHA,backup=str(backup),native=result,collision=collision,plan_sha256=pre['plan_sha256'],policy='Only proven covered overlap pieces are partitioned; original flat heights, existing PBR/UV/material parameters, actor transforms and bit-identical original collision preserved. Original assets retained.'))

def immersion_game_plan():
 interior=read('interior-native-probe');review=read('route-native-review');routes=read('campus-route-plan');doors=read('door-capsule-probe')
 assert interior['status']==review['status']==doors['status']=='passed'
 assert interior['map_sha256']==review['map_sha256']==doors['map_sha256']==LOAD_SHA
 rays=[]
 for r in interior['results']:
  q=dict(start=r['start_cm'],end=r['end_cm'],expected_hit='hit_cm' in r,kind=r['kind'],building=r['building'],id=r['id'])
  if 'hit_cm' in r:q['expected_point']=r['hit_cm']
  rays.append(q)
 floors=[];sweeps=[];walk=[]
 for r in routes['routes']:
  points=r['points_cm'];assert len(points)>=2
  walk.append(dict(id=r['id'],points=points))
  floors.extend(dict(start=[*p,1380],end=[*p,1100],min_z=1190,max_z=1215,route=r['id']) for p in points)
  sweeps.extend(dict(start=[*a,1304],end=[*b,1304],route=r['id']) for a,b in zip(points,points[1:]) if math.dist(a,b)>=1)
 for r in doors['rows']:
  assert r['passed'] and not r['sweep']['blocked'];sweeps.append(dict(start=r['start'],end=r['end'],door=r['id'],building=r['building'],kind='open_door_player_capsule'))
  for s in r['supports']:
   p=s['point_cm'];floors.append(dict(start=[p[0],p[1],p[2]+30],end=[p[0],p[1],p[2]-30],min_z=p[2]-1,max_z=p[2]+1,door=r['id'],building=r['building'],kind='door_threshold_support'))
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};groups=[]
 for label in ['LandscapeV3_TrunkCollision','Immersion_Cherry_TrunkColliders']:
  a=actors[label];cs=[c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_instance_count()>0];assert len(cs)==1
  c=cs[0];mesh=c.static_mesh;bounds=mesh.get_bounds();targets=[]
  for i in range(c.get_instance_count()):
   t=c.get_instance_transform(i,True);p=t.transform_location(bounds.origin);scale=t.scale3d;radius=max(abs(bounds.box_extent.x*scale.x),abs(bounds.box_extent.y*scale.y))+70
   targets.append(dict(instance=i,center=num(p),ray_radius=radius))
  assert not c.get_editor_property('visible') and c.get_editor_property('hidden_in_game') and not c.get_editor_property('cast_hidden_shadow')
  groups.append(dict(owner_object_name=a.get_name(),component_name=c.get_name(),mesh=mesh.get_path_name(),instance_count=c.get_instance_count(),expected_cast_shadow=bool(c.get_editor_property('cast_shadow')),targets=targets))
 alignment=read('stem-render-alignment');assert alignment['map_sha256']==LOAD_SHA and alignment['status']=='matched_visible_roots' and len(alignment['matches'])==1640;links=[];used_trees=set();used_proxies=set()
 for row in alignment['matches']:
  tree=row['tree'];proxy=row['proxy'];a=actors[tree['actor']];c=next(c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==tree['component']);assert c.static_mesh.get_path_name()==tree['mesh'];group=0 if proxy['actor']=='LandscapeV3_TrunkCollision' else 1;tk=(tree['actor'],tree['component'],tree['instance']);pk=(group,proxy['instance']);assert tk not in used_trees and pk not in used_proxies;used_trees.add(tk);used_proxies.add(pk);links.append(dict(tree_owner_object_name=a.get_name(),tree_component_name=c.get_name(),tree_mesh=tree['mesh'],tree_instance=tree['instance'],expected_root_cm=tree['root_cm'],proxy_group=group,proxy_instance=proxy['instance'],proxy_base_local_cm=[0,0,0] if group==0 else [0,0,-50]))
 assert len(used_trees)==len(used_proxies)==1640
 fixtures=read('fixture-physics-probe');assert fixtures['status']=='passed' and fixtures['map_sha256']==LOAD_SHA and len(fixtures['rows'])==254
 assert sha(MAPFILE)==LOAD_SHA
 gameplay={}
 if (OUT/'active-park-current-review.json').exists():
  park=read('active-park-current-review');assert park['status']=='passed' and park['map_sha256']==LOAD_SHA and len(park['routes'])==2 and len(park['ground_probes'])==204 and len(park['capsule_sweeps'])==202;walk.extend(park['routes']);gameplay['active_park_routes']=2;gameplay['source_park_receipt_sha256']=sha(OUT/'active-park-current-review.json')
  for r in park['ground_probes']:
   x,y,z=r['ground_cm'];floors.append(dict(start=[x,y,z+25],end=[x,y,z-25],min_z=z-1,max_z=z+1,kind='active_park_support',route=r['route']))
  for r in park['capsule_sweeps']:
   p,q=r['start'],r['end'];sweeps.append(dict(start=[p[0],p[1],p[2]+98],end=[q[0],q[1],q[2]+98],kind='active_park_clearance',route=r['route']))
 if (OUT/'connection-restore-install.json').exists():
  connection=read('connection-restore-install');points=connection['ground_probes'];assert len(points)==69;walk.append(dict(id='restored-connection',kind='outdoor_connection',points=[[p[0],p[1]] for p in points]));gameplay['connection_routes']=1
  floors.extend(dict(start=[p[0],p[1],p[2]+25],end=[p[0],p[1],p[2]-25],min_z=p[2]-1,max_z=p[2]+1,kind='connection_support') for p in points)
  sweeps.extend(dict(start=[a[0],a[1],a[2]+98],end=[b[0],b[1],b[2]+98],kind='connection_clearance') for a,b in zip(points,points[1:]))
 if (OUT/'stair-route-plan.json').exists():
  stairs=read('stair-route-plan');assert stairs['map_sha256']==LOAD_SHA and len(stairs['routes'])==34 and not stairs['issues'] and stairs['status']=='prepared_requires_actual_character_traversal';walk.extend(stairs['routes']);gameplay['stair_routes']=34;gameplay['source_stair_route_receipt_sha256']=sha(OUT/'stair-route-plan.json')
 if (OUT/'all-floor-cameras.json').exists():
  floor_views=read('all-floor-cameras');outdoor_views=read('outdoor-player-cameras');assert floor_views['status']==outdoor_views['status']=='passed' and floor_views['map_sha256']==outdoor_views['map_sha256']==LOAD_SHA and len(floor_views['rows'])==89 and len(outdoor_views['rows'])==20
  for r in floor_views['rows']+outdoor_views['rows']:
   x,y,z=r['eye'];z-=165;floors.append(dict(start=[x,y,z+25],end=[x,y,z-25],min_z=z-1,max_z=z+1,kind='supported_capture_pose',id=r['id']));sweeps.append(dict(start=[x,y,z+98],end=[x,y,z+99],kind='supported_capture_pose',id=r['id']))
  gameplay['supported_capture_poses']=109;gameplay['source_floor_camera_receipt_sha256']=sha(OUT/'all-floor-cameras.json');gameplay['source_outdoor_camera_receipt_sha256']=sha(OUT/'outdoor-player-cameras.json')
 if (OUT/'glazing-native-probe.json').exists():
  glass=read('glazing-native-probe');assert glass['status']=='passed' and glass['map_sha256']==LOAD_SHA and not glass['issues'];gameplay['glazing_checks']=glass['checks'];gameplay['source_glazing_receipt_sha256']=sha(OUT/'glazing-native-probe.json')
  gameplay['glazing_player_simple_checks']=glass['checks']
  for r in glass['rows']:assert r['passed'];rays.append(dict(start=r['start_cm'],end=r['end_cm'],expected_hit=True,expected_point=r['hit_cm'],kind='school_glazing',building=r['actor'],id=r['id'],pawn_simple_query=True))
 if (OUT/'walker-start-install.json').exists():
  immersion_walker_start_review();gameplay['player_start']=read('walker-start-review')['player_start']
 write('game-physics-plan',dict(status='prepared_requires_cooked_validation',map_sha256=LOAD_SHA,rays=rays,floors=floors,sweeps=sweeps,stem_groups=groups,stem_render_links=links,fixture_positive_rays=fixtures['rows'],walk_routes=walk,source_interior_receipt_sha256=sha(OUT/'interior-native-probe.json'),source_route_receipt_sha256=sha(OUT/'route-native-review.json'),source_door_receipt_sha256=sha(OUT/'door-capsule-probe.json'),source_stem_alignment_receipt_sha256=sha(OUT/'stem-render-alignment.json'),source_fixture_receipt_sha256=sha(OUT/'fixture-physics-probe.json'),open_doors=doors['doors'],scope='Exact native interior rays,3486 open door capsules/thresholds,campus routes,1640 hidden stems with one-to-one visible roots and254 visible lamp/bollard positive physics queries. Cooked-world replay required.',**gameplay))

def immersion_interior_probe():
 plan=read('interior-probe-plan');world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];issues=[]
 def record(ok,kind,bid,name,start,end,hit=None):
  q=dict(passed=bool(ok),kind=kind,building=bid,id=name,start_cm=start,end_cm=end)
  if hit and hit[0]:q.update(hit_cm=num(hit[4]),actor=hit[9].get_actor_label() if hit[9] else None)
  rows.append(q)
  if not ok:issues.append(q)
 for b in plan['buildings']:
  bid=b['building'];base=num(actors['Campus_'+bid+'_F01'].get_actor_location())
  def point(p):return [base[0]+p[1]*100,base[1]+p[0]*100,base[2]+p[2]*100]
  def ray(p,q):
   a,z=point(p),point(q);raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*a),unreal.Vector(*z),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);return a,z,raw.to_tuple() if raw else None
  for d in b['doors']:
   x,y,z=d['position_m'];t=math.radians(d['yaw_deg']);tx,ty=math.cos(t),math.sin(t);nx,ny=-ty,tx;closed=d.get('kind')=='lift' and d['floor']>1
   for lane in [-d['width_m']/3,d['width_m']/3] if closed else [-d['width_m']/3,0,d['width_m']/3]:
    for h in [.25,1.15,2.0]:
     xx,yy=x+tx*lane,y+ty*lane;a,q,hit=ray([xx-nx*.35,yy-ny*.35,z+h],[xx+nx*.35,yy+ny*.35,z+h]);record(bool(hit and hit[0])==closed,'door',bid,d['id']+'/%s/%s'%(lane,h),a,q,hit)
  for f in b['floors'][:-1]:
   for core in [c for c in f['vertical_circulation'] if c['kind']=='stairs']:
    g=core['walkable_geometry'];per=g['riser_count']//g['flight_count'];rise=f['height_m']/g['riser_count'];cx,cy,z=core['position_m']
    for flight in range(g['flight_count']):
     xx=cx+(-.9 if flight%2==0 else .9);sign=1 if flight%2==0 else -1
     for step in range(per-1):
      yy=cy+sign*(-g['flight_run_m']/2+(step+.5)*g['tread_depth_m']);zz=z+(flight*per+step+1)*rise
      for lane in [-.6,0,.6]:
       a,q,hit=ray([xx+lane,yy,zz+.025],[xx+lane,yy,zz-.025]);record(hit and hit[0] and abs(hit[4].z-(base[2]+zz*100))<.8,'stair_support',bid,core['id']+'/%s/%s/%s'%(flight,step,lane),a,q,hit)
       a,q,hit=ray([xx+lane,yy,zz+.03],[xx+lane,yy,zz+2.2]);record(not(hit and hit[0]),'stair_headroom',bid,core['id']+'/%s/%s/%s'%(flight,step,lane),a,q,hit)
  for c in b['corridors']:
   w,d,h=c['size_m'];x,y,z=c['position_m'];t=math.radians(c['yaw']);co,si=math.cos(t),math.sin(t)
   for along in [-max(w,d)/2+.5,0,max(w,d)/2-.5]:
    for lane in [-.7,0,.7]:
     xx,yy=(along,lane) if w>=d else (lane,along);p=[x+co*xx-si*yy,y+si*xx+co*yy,z+.05];a,q,hit=ray(p,[p[0],p[1],p[2]+2.13]);record(not(hit and hit[0]),'corridor_headroom',bid,c['id']+'/%s/%s'%(along,lane),a,q,hit)
 assert sha(MAPFILE)==LOAD_SHA
 write('interior-native-probe',dict(status='passed' if not issues else 'requires_review',map_sha256=LOAD_SHA,buildings=len(plan['buildings']),floors=sum(len(b['floors']) for b in plan['buildings']),checks=len(rows),issues=issues,results=rows,scope='Read-only rays against current native collision at actual rebased building origins; door apertures, stair supports/headroom and corridor clearance. Capsule traversal and rendered review remain separate.'))
]====]

