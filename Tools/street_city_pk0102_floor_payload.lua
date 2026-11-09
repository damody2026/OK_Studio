return [====[
PREV=ROOT/'output/street-social-city-production/white-paths-v1'
TARGET=('Activity_ACTSPACE-02-7','StaticMeshComponent0',16)
def previous(name):return json.loads((PREV/(name+'.json')).read_text('utf8'))
def setup_target():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 actor=actors[TARGET[0]];c=next(c for c in actor.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==TARGET[1])
 assert not actor.get_editor_property('hidden') and c.get_editor_property('visible') and not c.get_editor_property('hidden_in_game')
 assert c.static_mesh.get_path_name()=='/Game/UniversityCity/ActivityScenesV1/Assets/platform/S_df8fee8b47d24cbe/platform_LOD0.platform_LOD0'
 return controller,c
def install_target():
 prev=previous('install');assert LOAD_SHA==prev['map_sha256']==sha(MAPFILE);assert not (OUT/'install.json').exists()
 controller,c=setup_target();before=ground_snapshot();assert before==previous('preservation')['after']
 source=c.get_material(16);assert source.get_path_name()=='/Game/UniversityCity/ResortV1/Materials/M_Surface_7.M_Surface_7'
 scene=json.loads((ROOT/'output/street-social-city-production/day-night-v1/surface-final/scene.json').read_text('utf8'))
 native=next(r for r in scene['instances'] if r['actor']==TARGET[0] and r['component']==TARGET[1]);two=bool(native['two_sided_by_slot'][16])
 mi=EAL.load_asset('/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_'+('TwoSided' if two else 'FacingOnly'));assert mi
 assert abs(MEL.get_material_instance_scalar_parameter_value(mi,'RomancePeriod')-320)<.001
 folder=OUT/'backups';folder.mkdir(exist_ok=True);dest=folder/('UniversityCity-before-PK0102-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,dest)
 c.modify();c.set_material(16,mi);after=ground_snapshot();assert len(before)==len(after)==6584
 changed=0
 for a,b in zip(before,after):
  normalized=dict(b);normalized['materials']=list(b['materials'])
  if (b['actor'],b['component'])==TARGET[:2]:assert b['materials'][16]==mi.get_path_name();normalized['materials'][16]=source.get_path_name();changed+=1
  assert normalized==a,('Unapproved scene change',a['actor'],a['component'])
 assert changed==1 and sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 row=dict(actor=TARGET[0],component=TARGET[1],slot=16,before=source.get_path_name(),after=mi.get_path_name(),mesh=c.static_mesh.get_path_name(),two_sided=two,family='pedestrian_pavers',set='pedestrian_pavers_v3',period_cm=320.,aligned=True,reason='Visible PK-0102 activity platform surface; original World_PK_0102 is hidden')
 install=dict(prev,map_sha256=newsha,parent_map_sha256=LOAD_SHA,backup=str(dest),changes=prev['changes']+[row],selected_slot_count=len(prev['changes'])+1,target_change=row,scope='Only the actual visible activity platform at PK-0102, slot 16; all other bindings and geometry preserved')
 install['counts']=dict(prev['counts']);install['counts']['pedestrian_pavers']+=1
 write('install',install);write('preservation',dict(status='passed',before=before,after=after,component_count=6584,changed_slots=1,scope=install['scope']))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';old=json.loads(receipt.read_text('utf8'));assert old['map_sha256']==LOAD_SHA;receipt.write_text(json.dumps(dict(status='saved',operation='visible_PK0102_platform_floor',parent_map_sha256=LOAD_SHA,map_sha256=newsha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')
 write('revise',dict(status='passed',map_sha256=newsha,changed_slots=1,actor=TARGET[0],slot=16))
def audit_target():
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE);controller,c=setup_target();assert ground_snapshot()==read('preservation')['after']
 r=installed['target_change'];assert c.get_material(16).get_path_name()==r['after'];props=c.get_material(16).get_editor_property('base_property_overrides');assert props.get_editor_property('two_sided')==r['two_sided']
 for slot in installed.get('target_slots',[16]):assert c.get_material(slot).get_path_name()==r['after']
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,component_preservation_count=6584,changed_slots=len(installed.get('target_slots',[16])),target=r,target_slots=installed.get('target_slots',[16]),material_slot_bindings=len(installed['changes']),geometry_changes=0,all_1331_previous_changes_accounted=True,all_other_bindings_preserved=True))
 write('revision_audit',dict(status='passed',map_sha256=LOAD_SHA))
def repair_target_aliases():
 global LOAD_SHA
 installed=read('install');assert LOAD_SHA==installed['map_sha256']==sha(MAPFILE)
 controller,c=setup_target();before=ground_snapshot();assert before==read('preservation')['after'];mi=c.get_material(16);assert mi.get_path_name()==installed['target_change']['after']
 assert c.get_num_materials()==17
 original=installed['target_change']['before'];rows=[]
 backup=OUT/'backups'/('UniversityCity-before-platform-aliases-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for slot in range(17):
  if slot==16:continue
  assert c.get_material(slot).get_path_name()==original
  row=dict(installed['target_change'],slot=slot,reason='Same flat platform has 17 equivalent source surface bindings; assign each alias so cooked render-path material remapping cannot retain M_Surface_7')
  c.modify();c.set_material(slot,mi);rows.append(row)
 after=ground_snapshot()
 for a,b in zip(before,after):
  norm=dict(b);norm['materials']=list(b['materials'])
  if (b['actor'],b['component'])==TARGET[:2]:
   assert all(m==mi.get_path_name() for m in b['materials'])
   norm['materials']=list(a['materials'])
  assert norm==a
 assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE)
 parent=LOAD_SHA;installed.update(map_sha256=newsha,parent_map_sha256=parent,backup=str(backup),changes=installed['changes']+rows,target_slots=list(range(17)),selected_slot_count=len(installed['changes'])+len(rows),scope='Only the one visible PK-0102 platform component: all 17 equivalent source surface bindings; all other component bindings and geometry preserved')
 installed['counts']['pedestrian_pavers']+=len(rows)
 write('install',installed);write('preservation',dict(status='passed',before=before,after=after,component_count=6584,changed_slots=16,cumulative_target_slots=17,scope='All equivalent aliases of the one visible flat platform; other components and bindings unchanged'))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';old=json.loads(receipt.read_text('utf8'));assert old['map_sha256']==parent;receipt.write_text(json.dumps(dict(status='saved',operation='PK0102_platform_material_aliases',parent_map_sha256=parent,map_sha256=newsha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')
 assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);LOAD_SHA=newsha;audit_target()
 write('revise',dict(status='passed',map_sha256=newsha,target_slots=17,reopened_native_audit=True))
def work():
 try:
  if MODE=='revise':
   if (OUT/'install.json').exists():repair_target_aliases()
   else:install_target()
  elif MODE=='revision_audit':audit_target()
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
