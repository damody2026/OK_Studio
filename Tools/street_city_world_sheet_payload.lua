return [====[

def environment_world_shader():
 paths=sorted({c['material'] for c in read('world-sheet-plan')['covers']});rows=[]
 for path in paths:rows.append(json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(EAL.load_asset(path))))
 write('world_shader',dict(status='passed',rows=rows,scope='Read-only shader diagnostics for proposed cover materials; no map modification'))
def environment_world_apply():
 global LOAD_SHA,FACING_ROWS
 assert latest_map_sha()==LOAD_SHA;before_sha=LOAD_SHA
 context=read('world-sheet-source');folder=OUT/context['scene_folder'];planpath=OUT/'world-sheet-plan.json';plan=jread(planpath);assert plan['status']=='prepared_requires_native_validation' and plan['method']=='world_opaque_sheet_partition' and plan['meshes'] and not plan['blocked'];assert plan['scene_sha256']==sha(folder/'scene.json')==context['metadata_sha256']
 if context.get('selection'):
  immutable={a['label'] for a in read(context['selection'].removesuffix('.json'))['actors'] if a.get('cover_only')};assert not any(m['component_keys'][0].split('::',1)[0] in immutable for m in plan['meshes']),'Verified street sources are immutable covers'
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};components={a.get_actor_label()+'::'+c.get_name():c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore();facing=read('facing-install');face_rows={r['actor']+'::'+r['component']:r for r in facing['components']};source_scene=jread(folder/'scene.json');source_instances={i['key']:i for i in source_scene['instances'] if i['instance']==-1};fresh_dir=OUT/('world-preapply-'+PAYLOAD['run_id']);fresh_dir.mkdir();export=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(fresh_dir),True));assert export['status']=='passed';fresh=jread(fresh_dir/'scene.json');fresh_mesh={m['asset']:m for m in fresh['meshes']};fresh_instances={i['key']:i for i in fresh['instances'] if i['instance']==-1};hash_checks=0
 for source in plan['sources']:
  lod=next(l for l in fresh_mesh[source['source_asset']]['lods'] if l['lod']==source['lod']);assert sha(fresh_dir/lod['file'])==source['source_sha256'],('world source changed',source);hash_checks+=1
 keys={m['component_keys'][0] for m in plan['meshes']}|{c['component_key'] for c in plan['covers']};checked_materials=set()
 touched={key:set() for key in keys}
 for m in plan['meshes']:
  for lod in m['lods']:
   for patch in lod['patches']:touched[m['component_keys'][0]].add(patch['material_slot'])
 for cover in plan['covers']:touched[cover['component_key']].add(cover['material_slot'])
 for key in keys:
  before=source_instances[key];now=fresh_instances[key]
  for field in ['matrix','materials','two_sided_by_slot','blend_modes','collision']:assert before[field]==now[field],(key,field)
  assert source_scene['meshes'][before['mesh']]['asset']==fresh['meshes'][now['mesh']]['asset']
  c=components[key]
  for slot,blend in enumerate(now['blend_modes']):
   if blend!=0 or slot not in touched[key]:continue
   parent=c.get_material(slot)
   if parent.get_path_name() in checked_materials:continue
   checked_materials.add(parent.get_path_name());base=parent
   while isinstance(base,unreal.MaterialInstance):base=base.get_editor_property('parent');assert base
   assert isinstance(base,unreal.Material)
   # Native validator rejects WPO, displacement and pixel-depth offsets for every target and cover; some MaterialProperty enums are hidden from Editor Python.
 for m in plan['meshes']:
  key=m['component_keys'][0]
  if key not in face_rows:
   actor,component=key.split('::',1);c=components[key];face_rows[key]=dict(actor=actor,component=component,mesh_before=m['source_asset'],mesh_after=m['source_asset'],original_slot_count=len(m['materials']),added_slots=[],original_component=component_row(c.get_owner(),c,{}))
  assert face_rows[key]['mesh_after']==m['source_asset'];expected={s['source_slot']:s['added_slot'] for s in face_rows[key]['added_slots']};planned={s['source_slot']:s['existing_slot'] for s in m['front_slot_map']};assert len(planned)==len(m['front_slot_map']) and all(expected.get(slot)==value for slot,value in planned.items()),(key,'invalid forward material reuse');needed={p['material_slot'] for l in m['lods'] for p in l['patches'] if p['operation'] in ('front_only','paired_front_only')};assert all(slot not in expected or planned.get(slot)==expected[slot] for slot in needed),(key,'missing forward material reuse')
 backup=OUT/'backups'/('UniversityCity-before-world-sheets-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA;native=json.loads(unreal.CityDepthAuditLibrary.apply_world_sheet_repair(world,str(planpath)));assert native['status']=='passed',native
 wrappers={}
 def wrapper(parent):
  path=parent.get_path_name()
  if path not in wrappers:
   name='MI_FacingOnly_'+hashlib.sha256(path.encode()).hexdigest()[:24];asset=ENV+'/DepthRepairs/MaterialsFacing/'+name;mi=EAL.load_asset(asset) if EAL.does_asset_exist(asset) else ATS.create_asset(name,ENV+'/DepthRepairs/MaterialsFacing',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,parent);props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',props)
   for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mi.get_editor_property(field))
   MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);wrappers[path]=mi
  return wrappers[path]
 for m in native['meshes']:
  key=m['component_keys'][0];c=components[key];r=face_rows[key];mesh=c.static_mesh;static=list(mesh.get_editor_property('static_materials'));new=[]
  for s in m['added_material_slots']:
   parent=static[s['source_slot']].get_editor_property('material_interface');mi=wrapper(parent);static[s['added_slot']].set_editor_property('material_interface',mi);effective=c.get_material(s['source_slot']);child=wrapper(effective);c.modify();c.set_material(s['added_slot'],child);new.append(dict(s,mesh_material_parent=parent.get_path_name(),mesh_material_after=mi.get_path_name(),parent_before=effective.get_path_name(),material_after=child.get_path_name()))
  mesh.set_editor_property('static_materials',static);assert EAL.save_loaded_asset(mesh,False);r['added_slots']+=new;r.setdefault('world_passes',[]).append(dict(before=m['before'],after=m['after'],plan_sha256=sha(planpath)));r['mesh_after']=m['after']
 previous=read('depth-install');write('depth-install-before-world-'+PAYLOAD['run_id'],previous);write('facing-install-before-world-'+PAYLOAD['run_id'],read('facing-install'));old_by_after={m['after']:m for m in previous['meshes']};combined={m['before']:m for m in previous['meshes']}
 for m in native['meshes']:
  row=dict(m);row['source_before_this_pass']=row['before'];row['before']=old_by_after[row['before']]['before'] if row['before'] in old_by_after else row['before'];combined[row['before']]=row
 merged=dict(previous,meshes=list(combined.values()),method='original material union, within-mesh and cross-floor sheet repair');pending=OUT/('world-collision-'+PAYLOAD['run_id']+'.json');pending.write_text(json.dumps(merged),'utf8');collision=json.loads(unreal.CityDepthAuditLibrary.preserve_repair_collision(world,str(pending)));assert collision['status']=='passed',collision
 facing['components']=list(face_rows.values());FACING_ROWS={(r['actor'],r['component']):r for r in facing['components']};replacements={m['before']:m['after'] for m in merged['meshes']};count=0
 for r in read('inventory-baseline')['actors']:
  if not r['building_floor']:continue
  a=actors[r['label']];assert actor_preservation_xform(a)==r['xform'];expected=[dict(c,mesh=replacements.get(c['mesh'],c['mesh'])) for c in r['components']];actual=a.get_components_by_class(unreal.MeshComponent);assert len(actual)==len(expected) and [preserved_component_row(a,c,{},e) for c,e in zip(actual,expected)]==expected,('world floor preservation',r['label']);count+=1
 assert count==427 and sha(MAPFILE)==LOAD_SHA;controller.initialize_bindings();controller.set_hour(21.);controller.apply_environment();controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('cross-floor-world-sheets');LOAD_SHA=sha(MAPFILE);facing.update(status='passed',map_sha256=LOAD_SHA);merged.update(status='passed',map_sha256=LOAD_SHA);write('facing-install',facing);write('depth-install',merged);write('world-sheet-install',dict(status='passed',map_sha256=LOAD_SHA,before_map_sha256=before_sha,backup=str(backup),native=native,collision=collision,source_lod_hash_checks=hash_checks,floor_preservation_checks=count,plan_sha256=sha(planpath),source_context=context));write('world_apply',dict(status='passed',map_sha256=LOAD_SHA,meshes=len(native['meshes']),floor_preservation_checks=count))
 current=OUT/'surface-final';archive=OUT/('surface-final-before-world-'+PAYLOAD['run_id']);assert not archive.exists();current.rename(archive)
 if context['scene_folder']=='surface-final':
  context['scene_folder']=archive.name;write('world-sheet-source',context);installed=read('world-sheet-install');installed['source_context']=context;write('world-sheet-install',installed)
 environment_depth_export();environment_audit()
]====]
