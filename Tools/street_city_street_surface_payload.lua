-- Street rendering is repaired separately; original collision components remain.
return [====[
def street_batch():return 'tactile' if MODE.startswith('tactile_') else 'street'
def street_receipt(suffix):return street_batch()+'-'+suffix
def street_tag():return 'CityDepthTactileV1' if street_batch()=='tactile' else 'CityDepthStreetV1'

def street_transform(t):
 return unreal.Transform(location=unreal.Vector(*t['location']),rotation=unreal.Quat(*t['rotation']).rotator(),scale=unreal.Vector(*t['scale']))

def street_saved_targets(actors,batch='street'):
 original=[];replacement=[];cache={};receipt=read(batch+'-surface-install')
 for r in receipt['changes']:
  before=r['original'];a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==r['component']);assert component_row(a,c,cache)==before['row'] and not c.is_visible() and c.get_editor_property('hidden_in_game'),('modified original street component',r['component_key']);t=c.get_world_transform();q=t.rotation;now=dict(location=[t.translation.x,t.translation.y,t.translation.z],rotation=[q.x,q.y,q.z,q.w],scale=[t.scale3d.x,t.scale3d.y,t.scale3d.z]);assert all(math.dist(now[k],before['transform'][k])<.001 for k in now);original.append((c,before))
 for r in receipt['replacements']:
  a=actors[r['actor']];c=a.static_mesh_component;assert actor_xform(a)==r['xform'] and component_row(a,c,cache)==r['component'] and c.get_editor_property('cast_shadow')==r['cast_shadow'] and [str(t) for t in a.tags]==[receipt.get('replacement_tag','CityDepthStreetV1')],('modified street replacement',r['actor']);replacement.append(a)
 return original,replacement

def environment_street_preservation_audit():
 for batch in ['street','tactile']:
  if not (OUT/(batch+'-surface-install.json')).is_file():continue
  original,replacement=street_saved_targets({a.get_actor_label():a for a in SUB.get_all_level_actors()},batch);write(batch+'-preservation',dict(status='passed',original_components=len(original),replacement_chunks=len(replacement),map_sha256=sha(MAPFILE),scope='Exact source component geometry bindings, transforms, instance hashes, materials and collision preserved; expected rendering visibility checked; replacement rows and ownership verified'))

def environment_street_shader():
 paths=sorted({r['reason'].split(':')[-1] for r in read('street-source-native')['blocked']});rows=[]
 for path in paths:
  assert path.startswith('/Game/');material=EAL.load_asset(path);assert material;rows.append(json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(material)))
 write('street_shader',dict(status='passed',scope='Read-only graph diagnostic; no material or map mutation',rows=rows,map_sha256=sha(MAPFILE)))

def environment_street_probe():
 assert unreal.EditorLevelLibrary.get_editor_world().get_path_name().split('.')[0]=='/Engine/Maps/Entry';before_map=sha(MAPFILE);directory=OUT/('street-native-probe-'+PAYLOAD['run_id']);directory.mkdir();sphere=EAL.load_asset('/Engine/BasicShapes/Sphere');assert sphere;owners={};staged=[]
 for index in range(2):
  name='M_StreetProbe_'+PAYLOAD['run_id'].replace('-','_')+'_'+str(index);m=ATS.create_asset(name,ENV+'/DepthRepairs/Tests',unreal.Material,unreal.MaterialFactoryNew());m.set_editor_property('two_sided',False);node=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);node.set_editor_property('constant',unreal.LinearColor(.2+index*.4,.3,.4,1));assert MEL.connect_material_property(node,'',unreal.MaterialProperty.MP_BASE_COLOR);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False)
  c=unreal.CityDepthAuditLibrary.create_street_probe_component(unreal.EditorLevelLibrary.get_editor_world(),sphere,m,'Street_paving_Probe'+str(index));assert c;a=c.get_owner();c.set_collision_profile_name('NoCollision');c.set_static_mesh(sphere);c.set_editor_property('override_materials',[m]);c.clear_instances()
  c.add_instance(unreal.Transform(location=unreal.Vector(5900+index*120,6000,50),rotation=unreal.Rotator(0,30,0),scale=unreal.Vector(1.3,.7,1)),False)
  if index==0:c.add_instance(unreal.Transform(location=unreal.Vector(6000,6000,50),rotation=unreal.Rotator(0,0,0),scale=unreal.Vector(-1,1,1)),False)
  assert c.get_instance_count()==(2 if index==0 else 1),('probe instance creation',index,c.get_instance_count());owners[a.get_actor_label()]=(a,c,component_row(a,c,{}))
 native=json.loads(unreal.CityDepthAuditLibrary.build_street_surface_sources(unreal.EditorLevelLibrary.get_editor_world(),str(directory)));assert native['status']=='prepared_requires_union' and len(native['sources'])==2 and not native['blocked'],native
 for r in native['sources']:
  a,c,row=owners[r['actor']];assert component_row(a,c,{})==row;r=dict(r,stage_actor='DepthStreetStage_'+r['actor'],transform=dict(location=[0,0,0],rotation=[0,0,0,1],scale=[1,1,1]),original=dict(cast_shadow=c.get_editor_property('cast_shadow')));staged.append(r);c.set_visibility(False,False)
 street_stage_actors(staged);combined=json.loads(unreal.CityDepthAuditLibrary.combine_street_surface_sources(unreal.EditorLevelLibrary.get_editor_world(),str(directory)));assert combined['status']=='prepared_requires_union';expected=sum(l['merged_triangles'] for r in native['sources'] for l in r['lods']);assert combined['triangles']==expected
 chunks=json.loads(unreal.CityDepthAuditLibrary.chunk_street_surface(unreal.EditorLevelLibrary.get_editor_world(),combined['asset'],str(directory),6000.));assert chunks['status']=='prepared_requires_native_validation' and chunks['source_triangles']==chunks['chunk_triangles']==expected and len(chunks['chunks'])>=2,chunks
 assert sha(MAPFILE)==before_map;write('street_probe',dict(status='passed',source_components=2,nonuniform_and_reflected_instances=True,original_component_rows_preserved=True,native_source=native,aggregate=combined,chunks=chunks,main_map_unchanged=True,map_sha256=before_map,scope='Native source expansion, standard attributes, source immutability, aggregation and exact single-LOD triangle partition across spatial cells; production street union remains separate'))

def street_stage_actors(rows,use_repaired=False):
 assert unreal.EditorLevelLibrary.get_editor_world().get_path_name().split('.')[0]=='/Engine/Maps/Entry'
 result={}
 for r in rows:
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(*r['transform']['location']));a.set_actor_label(r['stage_actor']);a.set_editor_property('tags',['CityDepthStreetStage']);c=a.static_mesh_component;c.set_collision_profile_name('NoCollision');c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION);c.set_editor_property('generate_overlap_events',False);c.set_static_mesh(EAL.load_asset(r['repaired_mesh'] if use_repaired else r['merged_source']));c.set_editor_property('cast_shadow',r['original']['cast_shadow']);a.set_actor_transform(street_transform(r['transform']),False,True)
  assert [c.get_material(i).get_path_name() for i in range(c.get_num_materials())]==r['effective_materials'];result[r['stage_actor']]=a
 return result

def environment_street_sources():
 assert latest_map_sha()==LOAD_SHA and not (OUT/(street_receipt('surface-install')+'.json')).is_file()
 snapshot={};cache={}
 for a in SUB.get_all_level_actors():
  if not a.get_actor_label().startswith(('Street_tactile_',) if street_batch()=='tactile' else ('Street_paving_','Street_curb_')):continue
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   if not c.static_mesh or c.get_instance_count()==0:continue
   key=a.get_actor_label()+'::'+c.get_name();t=c.get_world_transform();q=t.rotation
   snapshot[key]=dict(actor=a.get_actor_label(),component=c.get_name(),row=component_row(a,c,cache),transform=dict(location=[t.translation.x,t.translation.y,t.translation.z],rotation=[q.x,q.y,q.z,q.w],scale=[t.scale3d.x,t.scale3d.y,t.scale3d.z]),visible=c.is_visible(),hidden_in_game=c.get_editor_property('hidden_in_game'),actor_hidden=a.get_editor_property('hidden'),cast_shadow=c.get_editor_property('cast_shadow'))
 world=unreal.EditorLevelLibrary.get_editor_world();directory=OUT/(street_receipt('source-build')+'-'+PAYLOAD['run_id']);directory.mkdir();native=json.loads(unreal.CityDepthAuditLibrary.build_street_surface_sources(world,str(directory),'tactile' if street_batch()=='tactile' else 'paving-curb'));write(street_receipt('source-native'),native);assert native['status']=='prepared_requires_union' and native['sources'] and not native['blocked'],native.get('blocked',native)
 source_rows=[];excluded=[]
 for r in native['sources']:
  key=r['actor']+'::'+r['component'];before=snapshot[key]
  if not before['visible'] or before['actor_hidden'] or before['hidden_in_game']:excluded.append(key);continue
  a=next(a for a in SUB.get_all_level_actors() if a.get_actor_label()==r['actor']);c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==r['component']);assert component_row(a,c,cache)==before['row'];assert before['row']['materials']==r['effective_materials'] and before['row']['instance_count']==r['instance_count']
  source_rows.append(dict(r,original=before,transform=before['transform'],stage_actor='DepthStreetStage_'+hashlib.sha256(key.encode()).hexdigest()[:20]))
 assert source_rows and sha(MAPFILE)==LOAD_SHA
 a=None;c=None;world=None;assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');street_stage_actors(source_rows)
 combined=json.loads(unreal.CityDepthAuditLibrary.combine_street_surface_sources(unreal.EditorLevelLibrary.get_editor_world(),str(directory)));assert combined['status']=='prepared_requires_union',combined
 write(street_receipt('sources'),dict(status='prepared_requires_union',map_sha256=LOAD_SHA,sources=source_rows,aggregate=combined,excluded_invisible=excluded,native_directory=str(directory),scope='Original components unchanged; all runtime-visible street surfaces combined in a staging source so cross-component overlap is included'))
 folder=OUT/street_receipt('source-export');assert not folder.exists();folder.mkdir();result=json.loads(unreal.CityDepthAuditLibrary.export_scene(unreal.EditorLevelLibrary.get_editor_world(),str(folder),True));assert result['status']=='passed';assert sha(MAPFILE)==LOAD_SHA
 write(MODE,dict(status='passed',map_sha256=LOAD_SHA,components=len(source_rows),export=str(folder),scope='Merged source preparation only; union and main-map installation remain required'))

def environment_street_union():
 receipt=read(street_receipt('sources'));assert receipt['status']=='prepared_requires_union' and receipt['map_sha256']==latest_map_sha()==LOAD_SHA
 planpath=OUT/(street_receipt('surface-union-plan')+'.json');plan=jread(planpath);assert plan['scene_sha256']==sha(OUT/street_receipt('source-export')/'scene.json')
 aggregate=receipt['aggregate'];a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(0,0,0));a.set_actor_label(aggregate['actor']);a.static_mesh_component.set_collision_profile_name('NoCollision');a.static_mesh_component.set_static_mesh(EAL.load_asset(aggregate['asset']));a.static_mesh_component.set_editor_property('cast_shadow',aggregate['cast_shadow']);world=unreal.EditorLevelLibrary.get_editor_world();fresh_dir=OUT/(street_receipt('union-preapply')+'-'+PAYLOAD['run_id']);fresh_dir.mkdir();fresh_result=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(fresh_dir),True));assert fresh_result['status']=='passed';fresh={m['asset']:m for m in jread(fresh_dir/'scene.json')['meshes']};checks=0
 for m in plan['meshes']:
  lods={l['lod']:l for l in fresh[m['source_asset']]['lods']}
  for l in m['lods']:assert sha(fresh_dir/lods[l['lod']]['file'])==l['source_sha256'];checks+=1
 result=json.loads(unreal.CityDepthAuditLibrary.apply_surface_union(world,str(planpath)));assert result['status']=='passed',result
 replacements={m['before']:m['after'] for m in result['meshes']};repaired=replacements.get(aggregate['asset'],aggregate['asset']);directory=OUT/(street_receipt('chunk-build')+'-'+PAYLOAD['run_id']);directory.mkdir();chunks=json.loads(unreal.CityDepthAuditLibrary.chunk_street_surface(world,repaired,str(directory),6000.));assert chunks['status']=='prepared_requires_native_validation' and chunks['chunks'],chunks
 a.static_mesh_component.set_visibility(False,False);a.set_actor_hidden_in_game(True)
 for i,r in enumerate(chunks['chunks']):
  actor=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(0,0,0));actor.set_actor_label('DepthStreetChunk_'+str(i));c=actor.static_mesh_component;c.set_collision_profile_name('NoCollision');c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION);c.set_static_mesh(EAL.load_asset(r['asset']));c.set_editor_property('cast_shadow',aggregate['cast_shadow'])
 write(street_receipt('union'),dict(status='prepared_requires_main_install',map_sha256=LOAD_SHA,sources=receipt['sources'],aggregate=aggregate,repaired_mesh=repaired,chunks=chunks,native=result,source_lod_hash_checks=checks,plan_sha256=sha(planpath)))
 folder=OUT/street_receipt('union-export');assert not folder.exists();folder.mkdir();export=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(folder),True));assert export['status']=='passed' and sha(MAPFILE)==LOAD_SHA
 write(MODE,dict(status='passed',map_sha256=LOAD_SHA,components=len(receipt['sources']),chunks=len(chunks['chunks']),export=str(folder),scope='Native union and nonduplicating spatial chunks applied only to temporary Entry-world actors; main map unchanged'))

def environment_street_apply():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA and not (OUT/(street_receipt('surface-install')+'.json')).is_file()
 receipt=read(street_receipt('union'));assert receipt['status']=='prepared_requires_main_install' and receipt['map_sha256']==LOAD_SHA
 proof=read(street_receipt('union-depth'));assert proof['status']=='scan_complete_requires_review' and proof['candidate_conflicts']==0 and not proof['truncated'] and proof['metadata_sha256']==sha(OUT/street_receipt('union-export')/'scene.json'),'Street source union still has depth candidates or stale proof'
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};targets=[];cache={}
 for r in receipt['sources']:
  before=r['original'];a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent) if c.get_name()==r['component']);assert component_row(a,c,cache)==before['row'] and c.is_visible()==before['visible'] and c.get_editor_property('hidden_in_game')==before['hidden_in_game'];targets.append((c,r))
 materials={m for r in receipt['sources'] for m in r['effective_materials']};chunk_meshes=[]
 for r in receipt['chunks']['chunks']:
  mesh=EAL.load_asset(r['asset']);assert mesh and all(mesh.get_material(i).get_path_name() in materials for i in range(len(mesh.get_editor_property('static_materials'))));chunk_meshes.append((r,mesh))
 backup=OUT/'backups'/('UniversityCity-before-street-union-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA;changes=[]
 replacements=[]
 for r,mesh in chunk_meshes:
  label=('DepthStableTactile_' if street_batch()=='tactile' else 'DepthStableStreet_')+str(r['cell_x'])+'_'+str(r['cell_y']);assert label not in actors
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(0,0,0));a.set_actor_label(label);a.set_folder_path('UniversityCity/EnvironmentV1/DepthRepairs');a.set_editor_property('tags',[street_tag()]);c=a.static_mesh_component;c.set_collision_profile_name('NoCollision');c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION);c.set_editor_property('generate_overlap_events',False);c.set_static_mesh(mesh);c.set_editor_property('cast_shadow',receipt['aggregate']['cast_shadow']);replacements.append(dict(actor=label,mesh=mesh.get_path_name(),xform=actor_xform(a),component=component_row(a,c,cache),cast_shadow=receipt['aggregate']['cast_shadow']))
 for original,r in targets:
  original.modify();original.set_visibility(False,False);original.set_hidden_in_game(True,False);now=component_row(original.get_owner(),original,cache)
  if now!=r['original']['row']:
   write('street-apply-preservation-failure',dict(component_key=r['component_key'],differences={k:dict(before=r['original']['row'].get(k),after=v) for k,v in now.items() if v!=r['original']['row'].get(k)}));assert False,'Original street component changed during visibility update'
  changes.append(r)
 assert sha(MAPFILE)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save(street_receipt('surface-union'));LOAD_SHA=sha(MAPFILE)
 write(street_receipt('surface-install'),dict(status='passed',map_sha256=LOAD_SHA,before_map_sha256=receipt['map_sha256'],backup=str(backup),changes=changes,replacements=replacements,replacement_tag=street_tag(),collision='Original instanced components, profiles and transforms retained; only their rendering hidden. New actors have NoCollision.',plan_sha256=receipt['plan_sha256'],street_union_depth_proof_sha256=sha(OUT/(street_receipt('union-depth')+'.json'))));write(MODE,dict(status='passed',map_sha256=LOAD_SHA,components=len(changes),chunks=len(replacements)))
 folder=OUT/'surface-final';archive=OUT/('surface-final-before-'+street_batch()+'-union-'+PAYLOAD['run_id']);assert not archive.exists();folder.rename(archive)
 context_path=OUT/'world-sheet-source.json'
 if context_path.is_file():
  context=jread(context_path)
  if context['scene_folder']=='surface-final':
   assert context['metadata_sha256']==sha(archive/'scene.json');context['scene_folder']=archive.name;write('world-sheet-source',context)
 environment_depth_export();environment_audit()
]====]
