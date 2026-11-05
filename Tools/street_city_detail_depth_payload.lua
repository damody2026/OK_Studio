return [====[
def environment_water_spacing():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};a=actors['City_H1_Water'];c=a.static_mesh_component;assert str(c.get_collision_profile_name())=='NoCollision'
 existing=read('water-depth-install') if (OUT/'water-depth-install.json').is_file() else None
 if existing:
  assert actor_xform(a)==existing['after'];write('water_spacing',dict(status='passed',already_applied=True,map_sha256=LOAD_SHA));return
 before=actor_xform(a);before_row=component_row(a,c,{})
 for index in range(c.get_num_materials()):
  proof=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(c.get_material(index)));reason=proof['component_rejection'];assert not reason or reason.startswith('per_instance_random:'),('unproved moving water shader',reason)
 backup=OUT/'backups'/('UniversityCity-before-water-depth-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA;location=a.get_actor_location();a.modify();a.set_actor_location(location+unreal.Vector(0,0,2),False,True);after=actor_xform(a);after_row=component_row(a,c,{})
 for key in before_row:
  if key!='relative_location':assert before_row[key]==after_row[key],('water binding or physics changed',key)
 assert after['scale']==before['scale'] and after['rotation']==before['rotation'] and all(abs(after['location'][k]-before['location'][k]-(2 if k==2 else 0))<.001 for k in range(3))
 assert sha(MAPFILE)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();old=LOAD_SHA;record_map_save('water-depth-separation');LOAD_SHA=sha(MAPFILE);write('water-depth-install',dict(status='passed',actor='City_H1_Water',before=before,after=after,before_component=before_row,after_component=after_row,before_map_sha256=old,map_sha256=LOAD_SHA,backup=str(backup),separation_cm=2,scope='Render-only NoCollision pool surfaces raised 2cm; original mesh, materials, rotation, scale and all buildings retained'));write('water_spacing',dict(status='passed',map_sha256=LOAD_SHA))
 current=OUT/'surface-final';archive=OUT/('surface-final-before-water-'+PAYLOAD['run_id']);assert not archive.exists();current.rename(archive)
 context=read('world-sheet-source') if (OUT/'world-sheet-source.json').is_file() else None
 if context and context['scene_folder']=='surface-final':
  assert context['metadata_sha256']==sha(archive/'scene.json');context['scene_folder']=archive.name;write('world-sheet-source',context)
 environment_depth_export();environment_audit()

def environment_prop_preservation_audit():
 receipt=read('prop-solid-cull');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for r in receipt['preservation']:
  a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==r['component']);assert actor_xform(a)==r['xform'] and component_row(a,c,{})==r['after'],('closed prop binding changed',r['actor'],r['component'])
 for r in receipt['changes']:
  a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==r['component']);mat=c.get_material(r['slot']);assert mat.get_path_name()==r['after'] and mat.get_editor_property('parent').get_path_name()==r['before'];check=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(mat));assert check['static_opaque_no_depth_displacement'] and not check['two_sided']
  for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mat.get_editor_property(field))
 write('prop-preservation',dict(status='passed',components=len(receipt['preservation']),slots=len(receipt['changes']),map_sha256=sha(MAPFILE)))

def environment_prop_cull():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA and not (OUT/'prop-solid-cull.json').is_file()
 context=read('prop-solid-source');source_folder=OUT/context['scene_folder'];proof=read('prop-solid-proof');assert proof['status']=='prepared_requires_native_validation' and proof['scene_sha256']==sha(source_folder/'scene.json')==context['metadata_sha256']
 source=jread(source_folder/'scene.json');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();fresh_dir=OUT/('prop-preapply-'+PAYLOAD['run_id']);fresh_dir.mkdir();native=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(fresh_dir),True));assert native['status']=='passed';fresh=jread(fresh_dir/'scene.json');fresh_meshes={m['asset']:m for m in fresh['meshes']};targets=[];blocked=[];source_checks=0
 for r in proof['components']:
  key=r['component_key'];a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==r['component'])
  assert c.static_mesh.get_path_name()==r['source_asset'] and not c.get_editor_property('reverse_culling')
  assert c.is_visible() and not c.get_editor_property('hidden_in_game') and not a.get_editor_property('hidden')
  before_instances=[i for i in source['instances'] if i['key']==key];now_instances=[i for i in fresh['instances'] if i['key']==key];assert len(before_instances)==len(now_instances)==r['instance_count']
  for before,now in zip(before_instances,now_instances):
   for field in ['instance','matrix','materials','two_sided_by_slot','blend_modes','collision']:assert before[field]==now[field],('prop changed',key,field)
   assert source['meshes'][before['mesh']]['asset']==fresh['meshes'][now['mesh']]['asset']==r['source_asset']
  lods=fresh_meshes[r['source_asset']]['lods'];assert len(lods)==len(r['source_lods'])
  for l in r['source_lods']:
   actual=next(x for x in lods if x['lod']==l['lod']);assert sha(fresh_dir/actual['file'])==l['sha256'],('prop source changed',key,l['lod']);source_checks+=1
  safe=[]
  for slot in r['safe_slots']:
   parent=c.get_material(slot);check=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(parent))
   if check['static_opaque_no_depth_displacement'] and check['two_sided']:safe.append(slot)
   else:blocked.append(dict(component_key=key,slot=slot,material=parent.get_path_name(),reason='Native static opaque depth validation rejected'))
  if safe:targets.append((a,c,r,safe,actor_xform(a),component_row(a,c,{})))
 assert targets,'No native-verified closed prop slots'
 backup=OUT/'backups'/('UniversityCity-before-prop-cull-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA;materials={};changes=[];preserved=[]
 for a,c,r,slots,before_transform,before_row in targets:
  for slot in slots:
   parent=c.get_material(slot);path=parent.get_path_name()
   if path not in materials:
    name='MI_SolidProp_'+hashlib.sha256(path.encode()).hexdigest()[:24];folder=ENV+'/DepthRepairs/MaterialsSolidProps';asset=folder+'/'+name;assert not EAL.does_asset_exist(asset),'Unexpected pre-existing solid prop wrapper';mi=ATS.create_asset(name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,parent);props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',props)
    for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mi.get_editor_property(field))
    MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);check=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(mi));assert check['static_opaque_no_depth_displacement'] and not check['two_sided'];materials[path]=mi
   mi=materials[path];c.modify();c.set_material(slot,mi);changes.append(dict(actor=r['actor'],component=r['component'],slot=slot,before=path,after=mi.get_path_name(),source_asset=r['source_asset']))
  after_row=component_row(a,c,{});assert actor_xform(a)==before_transform
  for field in before_row:
   if field not in ['materials','slots']:assert before_row[field]==after_row[field],('prop preservation failed',r['component_key'],field)
  for slot in range(len(before_row['materials'])):
   if slot not in slots:assert before_row['materials'][slot]==after_row['materials'][slot] and before_row['slots'][slot]==after_row['slots'][slot]
  preserved.append(dict(actor=r['actor'],component=r['component'],xform=before_transform,before=before_row,after=after_row))
 assert sha(MAPFILE)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();old=LOAD_SHA;record_map_save('closed-prop-cull');LOAD_SHA=sha(MAPFILE);write('prop-solid-cull',dict(status='passed',changes=changes,preservation=preserved,native_rejected=blocked,source_lod_hash_checks=source_checks,proof_sha256=sha(OUT/'prop-solid-proof.json'),before_map_sha256=old,map_sha256=LOAD_SHA,backup=str(backup),scope='Per-component culling only on exact closed outward solids <=100cm thick in every instance and source LOD. No geometry, transforms, instances, collision or original asset edits.'));write('prop_cull',dict(status='passed',slots=len(changes),components=len(preserved),map_sha256=LOAD_SHA))
 current=OUT/'surface-final';archive=OUT/('surface-final-before-prop-cull-'+PAYLOAD['run_id']);assert not archive.exists();current.rename(archive);environment_depth_export();environment_audit()
def environment_office_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};ignore=[a for label,a in actors.items() if label.startswith(('City_O01_F','City_O02_F','City_O03_F'))];rows=[]
 for x in [36000,36200,36600,37000,37400,37800,38200,38600]:
  for y in [82000,82400,82800,83200,83600,84000,84400,84800,85200]:
   hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,6000),unreal.Vector(x,y,-2000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignore,unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None
   if v and v[0]:rows.append(dict(x=x,y=y,position_cm=num(v[4]),normal=num(v[7]),support=v[9].get_actor_label() if v[9] else ''))
 write('office_probe',dict(status='passed',map_sha256=sha(MAPFILE),rows=rows,scope='Read-only native terrain support with office floors ignored; no map, mesh or actor edits.'))

def environment_footing_preservation_audit():
 receipt=read('fixture-foot-spacing');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for r in receipt['actors']:
  a=actors[r['actor']];assert actor_preservation_xform(a)==r['after'];components=a.get_components_by_class(unreal.StaticMeshComponent);assert len(components)==1
  now=component_row(a,components[0],{});assert all(now[k]==v for k,v in r['component'].items() if k not in ['relative_location','relative_scale'])
  origin,extent=a.get_actor_bounds(False);lo=office_original_point(a,num(origin-extent));hi=office_original_point(a,num(origin+extent));assert max(abs(lo[k]-r['min_after'][k]) for k in range(3))<.002 and max(abs(hi[k]-r['max_before'][k]) for k in range(3))<.002
 write('footing-preservation',dict(status='passed',actors=len(receipt['actors']),map_sha256=sha(MAPFILE),scope='Native bounds match source plus explicit authorized office/site translations; source mesh/material/collision/rotation retained, bottom embed keeps the vertical top fixed.'))

def environment_footing_spacing():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA
 if (OUT/'fixture-foot-spacing.json').is_file():
  prior=read('fixture-foot-spacing');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
  for r in prior['actors']:assert actor_preservation_xform(actors[r['actor']])==r['after']
  write('footing_spacing',dict(status='passed',already_applied=True,map_sha256=LOAD_SHA));return
 source=OUT/'surface-final';scene=jread(source/'scene.json');rows=[];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};materials=set()
 for row in scene['instances']:
  label=row['actor'];owned=(label.startswith('Environment_') and label.endswith('_Foot')) or (label.startswith('ResortLantern_') and label.endswith(('_Plinth','_BollardFoot')))
  if not owned:continue
  a=actors[label];components=a.get_components_by_class(unreal.StaticMeshComponent);assert len(components)==1 and row['instance']==-1
  c=components[0];assert not isinstance(c,unreal.InstancedStaticMeshComponent) and c.get_name()==row['component'] and str(c.get_collision_profile_name())=='NoCollision'
  assert ('CityEnvironmentV1' if label.startswith('Environment_') else 'ResortMoonlight-v1') in [str(t) for t in a.tags]
  assert c.static_mesh.get_path_name()=='/Engine/BasicShapes/Cylinder.Cylinder' and not a.get_attach_parent_actor()
  matrix=row['matrix'];assert all(abs(matrix[k])<1e-8 for k in [2,6,8,9]) and matrix[10]>0
  for slot in range(c.get_num_materials()):
   material=c.get_material(slot);path=material.get_path_name()
   if path not in materials:
    proof=json.loads(unreal.CityDepthAuditLibrary.inspect_solid_material(material));assert proof['static_opaque_no_depth_displacement'] and not proof['two_sided'],(label,proof);materials.add(path)
  origin,extent=a.get_actor_bounds(False);lo=num(origin-extent);hi=num(origin+extent)
  assert max(abs(lo[k]-row['min'][k]) for k in range(3))<.02 and max(abs(hi[k]-row['max'][k]) for k in range(3))<.02
  height=hi[2]-lo[2];assert 7.99<=height<=30.01
  rows.append(dict(actor=label,before=actor_xform(a),component=component_row(a,c,{}),min_before=lo,max_before=hi,height_cm=height))
 assert len(rows)==404 and sha(MAPFILE)==LOAD_SHA
 backup=OUT/'backups'/('UniversityCity-before-foot-spacing-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);changes=[]
 for r in rows:
  a=actors[r['actor']];a.modify();location=a.get_actor_location();scale=a.get_actor_scale3d();a.set_actor_location(location-unreal.Vector(0,0,.25),False,True);a.set_actor_scale3d(unreal.Vector(scale.x,scale.y,scale.z*(r['height_cm']+.5)/r['height_cm']));r['after']=actor_xform(a)
  changes.extend([dict(kind='actor_location',actor=r['actor'],before=num(location),after=num(a.get_actor_location())),dict(kind='actor_scale',actor=r['actor'],before=num(scale),after=num(a.get_actor_scale3d()))])
  origin,extent=a.get_actor_bounds(False);lo=num(origin-extent);hi=num(origin+extent)
  assert max(abs(hi[k]-r['max_before'][k]) for k in range(3))<.002 and max(abs(lo[k]-r['min_before'][k]) for k in range(2))<.002 and abs(lo[2]-(r['min_before'][2]-.5))<.002
  after_component=component_row(a,a.get_components_by_class(unreal.StaticMeshComponent)[0],{})
  assert all(after_component[k]==v for k,v in r['component'].items() if k not in ['relative_location','relative_scale']);r['min_after']=lo;r['max_after']=hi
 assert sha(MAPFILE)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();before=LOAD_SHA;record_map_save('fixture-footing-bottom-embed');LOAD_SHA=sha(MAPFILE)
 write('fixture-foot-spacing',dict(status='passed',before_map_sha256=before,map_sha256=LOAD_SHA,backup=str(backup),actors=rows,changes=changes,source_metadata_sha256=sha(source/'scene.json'),scope='404 owned upright NoCollision cylinder bases extended downward 0.5cm; native world top/XY bounds, materials, mesh and collision unchanged. Lamp stems and lights stay fixed. Original assets untouched.'))
 write('footing_spacing',dict(status='passed',actors=len(rows),map_sha256=LOAD_SHA));archive=OUT/('surface-final-before-foot-spacing-'+PAYLOAD['run_id']);assert not archive.exists();source.rename(archive);environment_depth_export();environment_audit()
]====]
