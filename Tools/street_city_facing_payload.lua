-- Native geometry partition installer. All authored surfaces and original collision remain recoverable.
return [====[
FACING_ROWS=None

def facing_preservation_row(actor,component,now):
 global FACING_ROWS
 if not (OUT/'facing-install.json').is_file():return now
 if FACING_ROWS is None:FACING_ROWS={(r['actor'],r['component']):r for r in read('facing-install')['components']}
 r=FACING_ROWS.get((actor.get_actor_label(),component.get_name()))
 if not r:return now
 assert now['mesh']==r['mesh_after']
 count=r['original_slot_count'];assert len(now['materials'])==count+len(r['added_slots'])
 def checked(path,parent):
  mi=EAL.load_asset(path);assert isinstance(mi,unreal.MaterialInstanceConstant) and mi.get_editor_property('parent').get_path_name()==parent
  props=mi.get_editor_property('base_property_overrides');assert props.get_editor_property('override_two_sided') and not props.get_editor_property('two_sided')
  for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mi.get_editor_property(field)),(path,field)
 for s in r['added_slots']:
  slot=s['added_slot'];assert now['materials'][slot]==s['material_after'] and now['mesh_materials'][slot]==s['mesh_material_after']
  checked(s['material_after'],s['parent_before']);checked(s['mesh_material_after'],s['mesh_material_parent'])
  assert now['materials'][s['source_slot']]==s['parent_before'] and now['mesh_materials'][s['source_slot']]==s['mesh_material_parent']
 for key in ['materials','mesh_materials','slots']:now[key]=now[key][:count]
 return now

def environment_facing_partition():
 global LOAD_SHA,FACING_ROWS
 assert latest_map_sha()==LOAD_SHA and not (OUT/'facing-install.json').is_file()
 planpath=OUT/'asymmetric-sheet-plan.json';plan=jread(planpath);assert plan['status']=='prepared_requires_native_validation' and not plan['blocked'] and plan['meshes']
 source_dir=OUT/'surface-final';source=jread(source_dir/'scene.json');assert sha(source_dir/'scene.json')==plan['scene_sha256']
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};actors['CityEnvironmentController'].deactivate_and_restore()
 fresh_dir=OUT/('surface-facing-preapply-'+PAYLOAD['run_id']);fresh_dir.mkdir();fresh_report=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(fresh_dir),True));assert fresh_report['status']=='passed'
 fresh=jread(fresh_dir/'scene.json');meshes={m['asset']:m for m in fresh['meshes']};old_instances={i['key']:i for i in source['instances']};new_instances={i['key']:i for i in fresh['instances']};components={a.get_actor_label()+'::'+c.get_name():c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)};snapshots={};hash_checks=0;wpo_checked=set()
 def no_wpo(material):
  if material.get_path_name() in wpo_checked:return
  base=material
  while isinstance(base,unreal.MaterialInstance):base=base.get_editor_property('parent');assert base
  assert isinstance(base,unreal.Material) and not base.get_editor_property('use_material_attributes') and MEL.get_material_property_input_node(base,unreal.MaterialProperty.MP_WORLD_POSITION_OFFSET) is None,('WPO or bundled material attributes prevent coplanar proof',material.get_path_name())
  wpo_checked.add(material.get_path_name())
 for m in plan['meshes']:
  lods={l['lod']:l for l in meshes[m['source_asset']]['lods']}
  for l in m['lods']:assert sha(fresh_dir/lods[l['lod']]['file'])==l['source_sha256'];hash_checks+=1
  for key in m['component_keys']:
   old=old_instances[key];new=new_instances[key]
   for field in ['matrix','two_sided_by_slot','blend_modes','materials','collision']:assert old[field]==new[field],(key,field)
   assert meshes[m['source_asset']]['id']==new['mesh'] and new['two_sided_by_slot']==m['two_sided_by_slot'] and new['blend_modes']==m['blend_modes']
   c=components[key];snapshots[key]=component_row(c.get_owner(),c,{})
   for i in range(c.get_num_materials()):
    if m['blend_modes'][i]==0:no_wpo(c.get_material(i));no_wpo(c.static_mesh.get_material(i))
 backup=OUT/'backups'/('UniversityCity-before-facing-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 native=json.loads(unreal.CityDepthAuditLibrary.apply_facing_partition(world,str(planpath)));assert native['status']=='passed',native
 wrappers={}
 def front_only(parent):
  path=parent.get_path_name()
  if path not in wrappers:
   name='MI_FacingOnly_'+hashlib.sha256(path.encode()).hexdigest()[:24];folder=ENV+'/DepthRepairs/MaterialsFacing';asset=folder+'/'+name
   mi=EAL.load_asset(asset) if EAL.does_asset_exist(asset) else ATS.create_asset(name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());assert mi;MEL.set_material_instance_parent(mi,parent)
   props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',props)
   for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mi.get_editor_property(field))
   for tag in ['CityTextID','CityTextLanguage','CityTextKind']:
    value=EAL.get_metadata_tag(parent,tag)
    if value:EAL.set_metadata_tag(mi,tag,value)
   MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);wrappers[path]=mi
  return wrappers[path]
 rows=[]
 for m in native['meshes']:
  mesh=EAL.load_asset(m['after']);static=list(mesh.get_editor_property('static_materials'));slot_receipts=[]
  for s in m['added_material_slots']:
   parent=static[s['source_slot']].get_editor_property('material_interface');wrapper=front_only(parent);static[s['added_slot']].set_editor_property('material_interface',wrapper);slot_receipts.append(dict(s,mesh_material_parent=parent.get_path_name(),mesh_material_after=wrapper.get_path_name()))
  mesh.set_editor_property('static_materials',static);assert EAL.save_loaded_asset(mesh,False)
  for key in m['component_keys']:
   c=components[key];before=snapshots[key];added=[]
   for s in slot_receipts:
    parent=EAL.load_asset(before['materials'][s['source_slot']]);wrapper=front_only(parent);c.modify();c.set_material(s['added_slot'],wrapper);added.append(dict(s,parent_before=parent.get_path_name(),material_after=wrapper.get_path_name()))
   rows.append(dict(actor=c.get_owner().get_actor_label(),component=c.get_name(),mesh_before=m['before'],mesh_after=m['after'],original_slot_count=m['original_material_slots'],added_slots=added))
 previous=read('depth-install');write('depth-install-before-facing-'+PAYLOAD['run_id'],previous);old_by_after={m['after']:m for m in previous['meshes']};combined={m['before']:m for m in previous['meshes']}
 for m in native['meshes']:
  m=dict(m);m['source_before_this_pass']=m['before'];m['before']=old_by_after[m['before']]['before'] if m['before'] in old_by_after else m['before'];combined[m['before']]=m
 merged=dict(previous,meshes=list(combined.values()),method='surface_union_then_asymmetric_front_only_partition');pending=OUT/('collision-facing-'+PAYLOAD['run_id']+'.json');pending.write_text(json.dumps(merged),'utf8');collision=json.loads(unreal.CityDepthAuditLibrary.preserve_repair_collision(world,str(pending)));assert collision['status']=='passed',collision
 receipt=dict(status='prepared_not_saved',components=rows,meshes=native['meshes'],source_lod_hash_checks=hash_checks,plan_sha256=sha(planpath),native=native,collision=collision,backup=str(backup),before_map_sha256=LOAD_SHA)
 # Install a provisional receipt for the strict preservation normalizer; a
 # failure never saves the main map, and leaves this receipt visibly provisional.
 write('facing-install',receipt);FACING_ROWS=None;replacements={m['before']:m['after'] for m in merged['meshes']};checks=0
 for r in read('inventory-baseline')['actors']:
  if not r['building_floor']:continue
  a=actors[r['label']];assert actor_xform(a)==r['xform'];expected=[dict(c,mesh=replacements.get(c['mesh'],c['mesh'])) for c in r['components']];assert [preserved_component_row(a,c,{},e) for c,e in zip(a.get_components_by_class(unreal.MeshComponent),expected)]==expected,('floor preservation',r['label']);checks+=1
 assert checks==427 and sha(MAPFILE)==LOAD_SHA
 actors['CityEnvironmentController'].initialize_bindings();actors['CityEnvironmentController'].set_hour(21.);actors['CityEnvironmentController'].apply_environment();actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('asymmetric-facing-partition');LOAD_SHA=sha(MAPFILE)
 receipt.update(status='passed',map_sha256=LOAD_SHA,floor_preservation_checks=checks);merged.update(map_sha256=LOAD_SHA);write('facing-install',receipt);write('depth-install',merged);write('facing',dict(status='passed',map_sha256=LOAD_SHA,meshes=len(native['meshes']),modified_source_triangles=native['modified_source_triangles'],floor_preservation_checks=checks))
 archive=OUT/('surface-final-before-facing-'+PAYLOAD['run_id']);assert not archive.exists();source_dir.rename(archive);environment_depth_export()
 exported=jread(source_dir/'scene.json');effective={i['key']:i for i in exported['instances']};slot_checks=0
 for r in rows:
  actual=effective[r['actor']+'::'+r['component']]
  for s in r['added_slots']:assert actual['two_sided_by_slot'][s['added_slot']] is False and actual['blend_modes'][s['added_slot']]==0;slot_checks+=1
 write('facing-effective-culling',dict(status='passed',map_sha256=LOAD_SHA,added_slot_checks=slot_checks,scope='Native MaterialInterface::IsTwoSided and GetBlendMode after geometry installation'))
]====]
