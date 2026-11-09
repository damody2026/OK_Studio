return [====[
V1=ROOT/'output/street-social-city-production/ground-pbr-v1'
REV_PREFIX='/Game/UniversityCity/GroundPBRV2'
FACTORS={'planting_soil':5.,'lawn_turf':5.,'meadow_grass':5.,'asphalt':4.,'river_gravel':4.,'beach_sand':4.,'rubber_track':4.,'acrylic_court':4.}

def oldread(name):return json.loads((V1/(name+'.json')).read_text('utf8'))

def revision_controller():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 return controller,{(a.get_actor_label(),c.get_name()):c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)}

def revision_master():
 path=REV_PREFIX+'/Materials/M_GroundNatural'
 assert not EAL.does_asset_exist(path),'Revision assets already exist; inspect receipt before retry'
 m=EAL.duplicate_asset(PREFIX+'/Natural/Materials/M_RomancePBR',path);assert m
 n=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_BASE_COLOR)
 code=str(n.get_editor_property('code'))
 needle='return lerp(Color,Target*clamp(l/max(Reference,.015),.70,1.3),Recolor);'
 assert needle in code
 # Preserve palette and random sampling, making local variation survive blending.
 contrast=scalar(m,'GroundDetailContrast',1.35,-300,-750)
 ins=list(n.get_editor_property('inputs'));v=unreal.CustomInput();v.set_editor_property('input_name','DetailContrast');ins.append(v);n.set_editor_property('inputs',ins)
 assert MEL.connect_material_expressions(contrast,'',n,'DetailContrast')
 code=code.replace(needle,'float3 c=lerp(Color,Target*clamp(l/max(Reference,.015),.70,1.3),Recolor);float avg=lerp(max(Reference,.001),max(dot(Target,float3(.2126,.7152,.0722)),.001),Recolor);float ratio=max(dot(c,float3(.2126,.7152,.0722)),.001)/avg;return saturate(c*clamp(pow(ratio,DetailContrast-1),.65,1.5));')
 n.set_editor_property('code',code)
 normal=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_NORMAL)
 assert str(normal.get_editor_property('code')).startswith('N*=Parameters.TwoSidedSign;')
 assert not compile_errors(m);save_asset(m)
 diag=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(m));assert not diag.get('graph_error') and not diag.get('global_rejection') and not diag.get('component_rejection'),diag
 return m,diag

def revise_ground():
 previous=oldread('install');assert LOAD_SHA==previous['map_sha256']==sha(MAPFILE)
 assert not (OUT/'install.json').exists(),'Revision already installed; use revision_audit'
 controller,components=revision_controller();before=ground_snapshot()
 assert before==oldread('preservation')['after'],'Scene changed outside the approved material revision'
 folder=OUT/'backups';folder.mkdir(exist_ok=True);backup=folder/('UniversityCity-before-scale-revision-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 master,diagnostic=revision_master();cache={};changes=[];restored=[];counts={}
 for r in previous['changes']:
  c=components[(r['actor'],r['component'])];assert c.static_mesh.get_path_name()==r['mesh'] and c.get_material(r['slot']).get_path_name()==r['after']
  c.modify()
  if r['family'] not in FACTORS:
   original=EAL.load_asset(r['before']);assert original;c.set_material(r['slot'],original);restored.append(dict(r,revision_action='restore_original_paving_floor_finish'))
   continue
  assert not r.get('floor_layer')
  factor=FACTORS[r['family']];key=r['after']
  if key not in cache:
   path=REV_PREFIX+'/Materials/MI_Detail_'+hashlib.sha256(key.encode()).hexdigest()[:20]
   assert not EAL.does_asset_exist(path)
   mi=EAL.duplicate_asset(key,path);assert mi
   MEL.set_material_instance_parent(mi,master)
   MEL.set_material_instance_scalar_parameter_value(mi,'RomancePeriod',float(r['period_cm']*factor))
   MEL.set_material_instance_scalar_parameter_value(mi,'GroundDetailContrast',1.35)
   MEL.update_material_instance(mi);save_asset(mi);cache[key]=mi
  mi=cache[key];c.set_material(r['slot'],mi)
  changes.append(dict(r,after=mi.get_path_name(),period_cm=r['period_cm']*factor,previous_period_cm=r['period_cm'],detail_size_factor=factor,previous_material=r['after'],aligned=False))
  counts[r['family']]=counts.get(r['family'],0)+1
 after=ground_snapshot();assert len(before)==len(after)==6584
 allowed={(r['actor'],r['component'],r['slot']):r for r in previous['changes']}
 expected={(r['actor'],r['component'],r['slot']):r['after'] for r in changes}
 for a,b in zip(before,after):
  normalized=dict(b);normalized['materials']=list(b['materials'])
  for i,path in enumerate(b['materials']):
   r=allowed.get((b['actor'],b['component'],i))
   if r:
    assert path==expected.get((b['actor'],b['component'],i),r['before'])
    normalized['materials'][i]=r['after']
  assert normalized==a,('Unexpected scene edit',a['actor'],a['component'])
 assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 write('preservation',dict(status='passed',before=before,after=after,component_count=len(before),scope='All mesh, transform, instance, collision, visibility and shadow fields unchanged. Only the explicitly listed material bindings differ.'))
 write('install',dict(status='passed',map_sha256=newsha,parent_map_sha256=LOAD_SHA,before_map_sha256=previous['before_map_sha256'],backup=str(backup),changes=changes,restored=restored,selected_slot_count=len(changes),restored_slot_count=len(restored),counts=counts,texture_sets=sorted({r['set'] for r in changes}),material_instances=len(cache),geometry_changes=0,pdo_or_wpo=False,master_diagnostic=diagnostic,factors=FACTORS,source_install_sha256=sha(V1/'install.json')))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';old=json.loads(receipt.read_text('utf8'));assert old['map_sha256']==LOAD_SHA
 receipt.write_text(json.dumps(dict(status='saved',operation='restore_paving_and_enlarge_ground_detail',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')
 write('revise',dict(status='passed',map_sha256=newsha,restored_slot_count=len(restored),enlarged_slot_count=len(changes),component_count=len(before)))

def audit_revision():
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE)
 controller,components=revision_controller();actual=ground_snapshot();assert actual==read('preservation')['after']
 current={(r['actor'],r['component']):r for r in actual};checked=set()
 for r in installed['restored']:
  assert current[(r['actor'],r['component'])]['materials'][r['slot']]==r['before']
 for r in installed['changes']:
  mi=components[(r['actor'],r['component'])].get_material(r['slot']);assert mi.get_path_name()==r['after']
  assert abs(MEL.get_material_instance_scalar_parameter_value(mi,'RomancePeriod')-r['period_cm'])<.001
  assert abs(r['period_cm']/r['previous_period_cm']-FACTORS[r['family']])<.0001
  if r['after'] in checked:continue
  checked.add(r['after']);assert mi.get_editor_property('parent').get_path_name().startswith(REV_PREFIX+'/')
  for p,k in [('RomanceBase','basecolor'),('RomanceNormal','normal'),('RomanceORM','orm')]:
   t=MEL.get_material_instance_texture_parameter_value(mi,p);assert t and t.blueprint_get_size_x()==1024 and t.blueprint_get_size_y()==1024
   assert EAL.get_metadata_tag(t,'RomanceSourceSHA')==sha(V1/'sets'/r['set']/(k+'.png'))
 master=EAL.load_asset(REV_PREFIX+'/Materials/M_GroundNatural');assert not compile_errors(master)
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,component_preservation_count=len(actual),restored_material_slots=len(installed['restored']),material_slot_bindings=len(installed['changes']),unique_material_instances=len(checked),all_maps_1024=True,geometry_changes=0,all_1331_previous_changes_accounted=len(installed['restored'])+len(installed['changes'])==1331))
 write('revision_audit',dict(status='passed',map_sha256=LOAD_SHA))

def work():
 try:
  if MODE=='revise':revise_ground()
  elif MODE=='revision_audit':audit_revision()
  else:raise RuntimeError('Use revise or revision_audit')
 except BaseException:
  write(MODE+'-error',dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc())
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
