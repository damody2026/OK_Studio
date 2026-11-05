return [====[
V1=ROOT/'output/street-social-city-production/ground-pbr-v1'
V2=ROOT/'output/street-social-city-production/ground-pbr-v2'
NEW_PREFIX='/Game/UniversityCity/WhitePathsV1'
def previous(name):return json.loads((V2/(name+'.json')).read_text('utf8'))
def oldread(name):return json.loads((V1/(name+'.json')).read_text('utf8'))
def setup_paths():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 return controller,{(a.get_actor_label(),c.get_name()):c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)}
def path_plan():
 inv=oldread('inventory');mats={m['path']:m for m in inv['materials']};plan=[];sided={(r['actor'],r['component'],r['slot']):r['two_sided'] for r in oldread('install')['changes']}
 for c in inv['components']:
  if c['instances']<=0:continue
  for s in c['slots']:
   chain=' '.join(mats[s['material']]['chain']).lower()
   is_path='outdoor_stone' in chain or '/walk.walk' in chain
   is_access=c['actor'] in ['OfficeSetback_PK0110_Ramp','OfficeSetback_PK0110_Deck']
   if not (is_path or is_access):continue
   assert c['actor'].startswith(('Outdoor_','World_PK_','OfficeSetback_'))
   key=(c['actor'],c['component'],s['slot']);assert key in sided
   plan.append(dict(actor=c['actor'],component=c['component'],slot=s['slot'],before=s['material'],mesh=c['mesh'],two_sided=sided[key],family='pedestrian_pavers',set='pedestrian_pavers_v3',period_cm=320.,seed=0.,aligned=True,reason='Previously untextured white outdoor path, platform or picnic access; 80 by 40 cm stone slabs'))
 assert len(plan)==31
 return plan
def install_paths():
 global PREFIX
 prev=previous('install');assert LOAD_SHA==prev['map_sha256']==sha(MAPFILE)
 assert not (OUT/'install.json').exists()
 controller,components=setup_paths();before=ground_snapshot();assert before==previous('preservation')['after']
 plan=path_plan();folder=OUT/'backups';folder.mkdir(exist_ok=True);dest=folder/('UniversityCity-before-white-paths-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,dest)
 path=NEW_PREFIX+'/Materials/M_StoneSlabs';assert not EAL.does_asset_exist(path)
 master=EAL.duplicate_asset(PREFIX+'/Aligned/Materials/M_RomancePBR',path);assert master
 color=MEL.get_material_property_input_node(master,unreal.MaterialProperty.MP_BASE_COLOR);code=str(color.get_editor_property('code'));assert '.70,1.3' in code
 color.set_editor_property('code',code.replace('.70,1.3','.30,1.7'))
 assert str(MEL.get_material_property_input_node(master,unreal.MaterialProperty.MP_NORMAL).get_editor_property('code')).startswith('N*=Parameters.TwoSidedSign;')
 assert not compile_errors(master);save_asset(master)
 diag=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(master));assert not diag.get('graph_error') and not diag.get('global_rejection') and not diag.get('component_rejection'),diag
 luma=oldread('texture-luma')['pedestrian_pavers_v3'];cache={};changes=[]
 textures={};old_prefix=PREFIX;PREFIX=NEW_PREFIX
 try:
  for k in ['basecolor','normal','orm']:textures[k]=import_texture('pedestrian_pavers_v3',k,V1/'sets'/'pedestrian_pavers_v3'/(k+'.png'),k=='basecolor',unreal.TextureCompressionSettings.TC_DEFAULT if k=='basecolor' else (unreal.TextureCompressionSettings.TC_NORMALMAP if k=='normal' else unreal.TextureCompressionSettings.TC_MASKS))
 finally:PREFIX=old_prefix
 for r in plan:
  c=components[(r['actor'],r['component'])];assert c.static_mesh.get_path_name()==r['mesh'] and c.get_material(r['slot']).get_path_name()==r['before']
  key=r['two_sided']
  if key not in cache:
   name='MI_StoneSlabs_'+('TwoSided' if key else 'FacingOnly');mi=ATS.create_asset(name,NEW_PREFIX+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());assert mi;MEL.set_material_instance_parent(mi,master)
   for p,k in [('RomanceBase','basecolor'),('RomanceNormal','normal'),('RomanceORM','orm')]:
    t=textures[k];assert t and t.blueprint_get_size_x()==1024;MEL.set_material_instance_texture_parameter_value(mi,p,t)
   for p,v in [('RomancePeriod',320.),('RomanceSeed',0.),('RomanceStrength',1.),('GroundRecolor',1.),('GroundLumaRef',luma)]:MEL.set_material_instance_scalar_parameter_value(mi,p,float(v))
   for p,v in [('RomanceTintA',[1,1,1]),('RomanceTintB',[1,1,1]),('GroundTarget',[.40,.39,.35])]:MEL.set_material_instance_vector_parameter_value(mi,p,unreal.LinearColor(*v,1))
   props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',key);mi.set_editor_property('base_property_overrides',props)
   MEL.update_material_instance(mi);save_asset(mi);cache[key]=mi
  mi=cache[key];c.modify();c.set_material(r['slot'],mi);changes.append(dict(r,after=mi.get_path_name()))
 after=ground_snapshot();expected={(r['actor'],r['component'],r['slot']):r for r in changes}
 assert len(before)==len(after)==6584
 for a,b in zip(before,after):
  normalized=dict(b);normalized['materials']=list(b['materials'])
  for i,m in enumerate(b['materials']):
   r=expected.get((b['actor'],b['component'],i))
   if r:assert m==r['after'];normalized['materials'][i]=r['before']
  assert a==normalized,('Non-path change',a['actor'],a['component'])
 assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 restored=[r for r in prev['restored'] if (r['actor'],r['component'],r['slot']) not in expected];assert len(restored)==1163
 allchanges=prev['changes']+changes;assert len(allchanges)==168
 write('preservation',dict(status='passed',before=before,after=after,component_count=6584,scope='Only 31 white-path bindings changed; original gray street paving, interior floors and all 137 enlarged ground slots remain byte-for-byte bound to the previous materials. Meshes, instances, transforms, collision, visibility and shadows unchanged.'))
 counts=dict(prev['counts']);counts['pedestrian_pavers']=31
 write('install',dict(status='passed',map_sha256=newsha,parent_map_sha256=LOAD_SHA,before_map_sha256=prev['before_map_sha256'],backup=str(dest),changes=allchanges,path_changes=changes,restored=restored,selected_slot_count=168,restored_slot_count=1163,counts=counts,texture_sets=sorted(set(prev['texture_sets']+['pedestrian_pavers_v3'])),geometry_changes=0,pdo_or_wpo=False,master_diagnostic=diag,scope='31 formerly untextured white outdoor stone paths and access slabs, all other v2 bindings preserved'))
 write('path-plan',dict(status='passed',rows=plan,inventory_slots=40392,candidate_slots=31,excluded='Existing gray street paving, textured campus terrain, interior floors, furnishings, white sports lines and grass proxy material'))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';old=json.loads(receipt.read_text('utf8'));assert old['map_sha256']==LOAD_SHA;receipt.write_text(json.dumps(dict(status='saved',operation='white_outdoor_stone_paths',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')
 write('revise',dict(status='passed',map_sha256=newsha,path_slots=31))
def audit_paths():
 install=read('install');assert LOAD_SHA==install['map_sha256']==sha(MAPFILE)
 controller,components=setup_paths();assert ground_snapshot()==read('preservation')['after']
 for r in install['path_changes']:
  mi=components[(r['actor'],r['component'])].get_material(r['slot']);assert mi.get_path_name()==r['after'];assert abs(MEL.get_material_instance_scalar_parameter_value(mi,'RomancePeriod')-320)<.001
  props=mi.get_editor_property('base_property_overrides');assert props.get_editor_property('two_sided')==r['two_sided']
  for p,k in [('RomanceBase','basecolor'),('RomanceNormal','normal'),('RomanceORM','orm')]:
   t=MEL.get_material_instance_texture_parameter_value(mi,p);assert t and t.blueprint_get_size_x()==1024 and t.blueprint_get_size_y()==1024;assert EAL.get_metadata_tag(t,'RomanceSourceSHA')==sha(V1/'sets'/'pedestrian_pavers_v3'/(k+'.png'))
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,path_slots=31,component_preservation_count=6584,material_slot_bindings=168,restored_material_slots=1163,all_1331_previous_changes_accounted=True,geometry_changes=0,all_maps_1024=True,unchanged_previous_ground_slots=137))
 write('revision_audit',dict(status='passed',map_sha256=LOAD_SHA))
def work():
 try:
  if MODE=='revise':install_paths()
  elif MODE=='revision_audit':audit_paths()
  else:raise RuntimeError('Use revise or revision_audit')
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
