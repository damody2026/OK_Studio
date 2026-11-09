return [====[
def environment_flower_refine():
 assert latest_map_sha()==LOAD_SHA and not (OUT/'flower_refine.json').is_file();receipt=read('visual_polish');assert receipt['status']=='passed';actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore();folder=ENV+'/VisualPolishV5';backup=OUT/'backups'/('UniversityCity-before-flower-refine-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 path=folder+'/M_NaturalBark';old_bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV1/Materials/M_Bark');bark=EAL.load_asset(path) if EAL.does_asset_exist(path) else EAL.duplicate_asset(old_bark.get_path_name(),path);assert bark
 if not EAL.get_metadata_tag(bark,'BarkRefinement'):
  base=MEL.get_material_property_input_node(bark,unreal.MaterialProperty.MP_BASE_COLOR);out=MEL.get_material_property_input_node_output_name(bark,unreal.MaterialProperty.MP_BASE_COLOR);tint=MEL.create_material_expression(bark,unreal.MaterialExpressionConstant3Vector);tint.set_editor_property('constant',unreal.LinearColor(2.2,2.4,2.6,1));multiply=MEL.create_material_expression(bark,unreal.MaterialExpressionMultiply);assert MEL.connect_material_expressions(base,out,multiply,'A');assert MEL.connect_material_expressions(tint,'',multiply,'B');assert MEL.connect_material_property(multiply,'',unreal.MaterialProperty.MP_BASE_COLOR)
  normal=MEL.get_material_property_input_node(bark,unreal.MaterialProperty.MP_NORMAL);out=MEL.get_material_property_input_node_output_name(bark,unreal.MaterialProperty.MP_NORMAL);soft=MEL.create_material_expression(bark,unreal.MaterialExpressionCustom);inp=unreal.CustomInput();inp.set_editor_property('input_name','N');soft.set_editor_property('inputs',[inp]);soft.set_editor_property('code','return normalize(float3(N.xy*.35,max(N.z,.15)));');soft.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT3);assert MEL.connect_material_expressions(normal,out,soft,'N');assert MEL.connect_material_property(soft,'',unreal.MaterialProperty.MP_NORMAL);EAL.set_metadata_tag(bark,'BarkRefinement','warm grey-brown reflectance and reduced normal strength; source bark texture retained')
 assert not MEL.recompile_material(bark);assert EAL.save_loaded_asset(bark,False)
 # Reuse the same verified import/binding construction with a versioned source
 # directory and namespace. Existing tree meshes and original bark stay intact.
 import textwrap
 source=(ROOT/'Tools/street_city_visual_polish_payload.lua').read_text('utf8');chunk=source.split(' global PREFIX,KEEP,save\n',1)[1].split(' for a in list(actors.values()):',1)[0];assert "OUT/'flowering-trees-v4/assets'" in chunk
 chunk=chunk.replace("OUT/'flowering-trees-v4/assets'","OUT/'flowering-trees-v5/assets'").replace("bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV1/Materials/M_Bark')",'bark=refined_bark');namespace=dict(globals(),folder=folder,refined_bark=bark);exec(textwrap.dedent(chunk),namespace);assets=namespace['assets'];changes=[]
 def tf(t):return [t.translation.x,t.translation.y,t.translation.z,t.rotation.x,t.rotation.y,t.rotation.z,t.rotation.w,t.scale3d.x,t.scale3d.y,t.scale3d.z]
 for r in receipt['trees']:
  a=actors[r['actor']];c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==r['component']);assert c.static_mesh.get_path_name()==r['after'];aid=EAL.get_metadata_tag(c.static_mesh,'TreeUpgradeId');mesh=assets[aid];before=(actor_xform(a),tf(c.get_relative_transform()),str(c.get_collision_profile_name()),c.is_visible(),c.get_editor_property('hidden_in_game'),[tf(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())] if isinstance(c,unreal.InstancedStaticMeshComponent) else []);c.modify();c.set_static_mesh(mesh);c.set_editor_property('override_materials',[mesh.get_material(i) for i in range(len(mesh.get_editor_property('static_materials')))]);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==r['component']);after=(actor_xform(a),tf(c.get_relative_transform()),str(c.get_collision_profile_name()),c.is_visible(),c.get_editor_property('hidden_in_game'),[tf(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())] if isinstance(c,unreal.InstancedStaticMeshComponent) else []);assert before==after,(r['actor'],'tree preservation');changes.append(dict(actor=r['actor'],component=r['component'],before=r['after'],after=mesh.get_path_name()));r['previous_after']=r['after'];r['after']=mesh.get_path_name()
 sky=EAL.load_asset(read('plan')['materials']['sky']);nodes=[n for n in MEL.get_material_expressions(sky) if isinstance(n,unreal.MaterialExpressionCustom) and 'float3 ray=normalize(-V)' in str(n.get_editor_property('code'))];assert len(nodes)==1;code=str(nodes[0].get_editor_property('code'))
 if 'float3(.025,.05,.15)' not in code:assert code.count('return color;')==1;nodes[0].set_editor_property('code',code.replace('return color;','color+=float3(.025,.05,.15)*(1-saturate(D));return color;'))
 assert not MEL.recompile_material(sky);assert EAL.save_loaded_asset(sky,False);controller.initialize_bindings();controller.set_hour(21.);controller.apply_environment();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();record_map_save('refined-petals-bark-and-night-sky');write('visual-polish-before-refine',read('visual_polish'));receipt.update(trees=receipt['trees'],tree_meshes={k:v.get_path_name() for k,v in assets.items()},map_sha256=sha(MAPFILE),refinement_backup=str(backup),visual_review='required');write('visual_polish',receipt);write('flower_refine',dict(status='passed',changes=changes,tree_components=len(changes),map_sha256=sha(MAPFILE),backup=str(backup),preserved='actor/component/instance transforms, collision and visibility',sky_note='A dark-blue visible-sky floor; day colour and ambient cubemap lighting unchanged'))

def environment_visual_polish_audit():
 receipt=read('visual_polish');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};actors['CityEnvironmentController'].deactivate_and_restore();sign_checks=[];tree_checks=[]
 for r in receipt['signs']:
  c=next(q for q in actors[r['actor']].get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==r['component']);mat=c.get_material(r['slot']);old=EAL.load_asset(r['before']);assert mat.get_path_name()==r['after'];assert MEL.get_material_instance_scalar_parameter_value(mat,'SignLightMode')==0.;assert abs(MEL.get_material_instance_scalar_parameter_value(mat,'SignGlowStrength')-2.4)<.0001
  for locale in ['zh_Hant','zh_Hans','en']:
   for prefix in ['CityText_','SignDetail_']:assert MEL.get_material_instance_texture_parameter_value(mat,prefix+locale)==MEL.get_material_instance_texture_parameter_value(old,prefix+locale),(r['actor'],prefix+locale)
  for key in ['SignDepthU','SignDepthV','SignMetallic']:assert MEL.get_material_instance_scalar_parameter_value(mat,key)==MEL.get_material_instance_scalar_parameter_value(old,key),(r['actor'],key)
  sign_checks.append(r['actor'])
 for r in receipt['trees']:
  c=next(q for q in actors[r['actor']].get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==r['component']);assert c.static_mesh.get_path_name()==r['after'];assert EAL.get_metadata_tag(c.static_mesh,'CanopyConstruction').endswith('no opaque flower balls');assert c.get_num_materials()==3;tree_checks.append(r['actor'])
 sky=EAL.load_asset(read('plan')['materials']['sky']);assert sky.get_editor_property('is_sky');assert len(sign_checks)==122 and len(tree_checks)==receipt['tree_components'];write('visual-polish-audit',dict(status='passed',signs=len(sign_checks),trilingual_textures_unchanged=len(sign_checks)*6,tree_components=len(tree_checks),sky_is_sky=True,map_sha256=sha(MAPFILE)))

def environment_visual_polish():
 assert latest_map_sha()==LOAD_SHA
 if (OUT/'visual_polish.json').is_file():
  previous=read('visual_polish');assert previous['status']=='failed','Visual polish already applied';(OUT/'visual_polish.json').rename(OUT/('visual-polish-failed-'+previous['run_id']+'.json'))
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore()
 backup=OUT/'backups'/('UniversityCity-before-visual-polish-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 folder=ENV+'/VisualPolish';signs=[];trees=[]
 # Preserve the existing trilingual textures, physical POM and depth clearance.
 sign_actors=sorted([a for a in actors.values() if a.get_actor_label().startswith('RomanceName_')],key=lambda a:a.get_actor_label());assert len(sign_actors)==122
 original=sign_actors[0].static_mesh_component.get_material(0).get_editor_property('parent');path=folder+'/M_DarkRaisedLetters_01'
 parent=EAL.load_asset(path) if EAL.does_asset_exist(path) else EAL.duplicate_asset(original.get_path_name(),path);assert parent
 colors=[n for n in MEL.get_material_expressions(parent) if isinstance(n,unreal.MaterialExpressionCustom) and (str(n.get_editor_property('code')).startswith('if(Lang<0.5)return Texture2DSampleLevel(C0') or str(n.get_editor_property('code')).startswith('float3 c;if(Lang<0.5)c=Texture2DSampleLevel(C0')) and '.rgb;' in str(n.get_editor_property('code'))];assert len(colors)==1
 colors[0].set_editor_property('code','float3 c;if(Lang<0.5)c=Texture2DSampleLevel(C0,C0Sampler,P.xy,0).rgb;else if(Lang<1.5)c=Texture2DSampleLevel(C1,C1Sampler,P.xy,0).rgb;else c=Texture2DSampleLevel(C2,C2Sampler,P.xy,0).rgb;float letters=1-smoothstep(0.15,0.38,P.z);return lerp(float3(.008,.013,.019)+c*.008,float3(.72,.67,.54),letters);')
 assert not MEL.recompile_material(parent);assert EAL.save_loaded_asset(parent,False)
 for a in sign_actors:
  c=a.static_mesh_component;before=c.get_material(0);path=folder+'/MI_DarkLetters_'+a.get_actor_label().removeprefix('RomanceName_');mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else EAL.duplicate_asset(before.get_path_name(),path);assert mi
  MEL.set_material_instance_parent(mi,parent)
  for key in ['CityTextID','SignArtwork','SignRelief','SignFinish','SignSourceSHA256']:
   value=EAL.get_metadata_tag(before,key)
   if value:EAL.set_metadata_tag(mi,key,value)
  for key,val in [('SignLightMode',0.),('SignGlowStrength',2.4),('SignNightStrength',1.)]:MEL.set_material_instance_scalar_parameter_value(mi,key,val)
  EAL.set_metadata_tag(mi,'SignNightLighting','lit_letters');EAL.set_metadata_tag(mi,'SignPanelFinish','dark charcoal enamel; raised warm-white lettering');MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);c.modify();c.set_material(0,mi)
  signs.append(dict(actor=a.get_actor_label(),component=c.get_name(),slot=0,before=before.get_path_name(),after=mi.get_path_name(),mode=MEL.get_material_instance_scalar_parameter_value(mi,'SignLightMode'),physical_depth_cm=2.8))
 # Import new branch/leaf/blossom geometry into a new namespace. Source trees
 # and separate trunk collision meshes are retained for reversible replacement.
 global PREFIX,KEEP,save
 PREFIX=folder+'/FloweringTrees';KEEP=[];save=save_asset
 source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0]
 source=source.replace("pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials)","pipeline.get_editor_property('material_pipeline').set_editor_property('import_materials',materials);pipeline.get_editor_property('material_pipeline').get_editor_property('texture_pipeline').set_editor_property('import_textures',False)")
 namespace=dict(globals());exec('def import_one('+source,namespace);import_one=namespace['import_one'];api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
 bark=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV1/Materials/M_Bark');leaf=EAL.load_asset('/Game/UniversityCity/TreeUpgradeV1/Materials/M_Leaves');assert bark and leaf
 assets={};source_folder=OUT/'flowering-trees-v4/assets'
 for aid,tint in [('flower-a',(.72,.31,.39)),('golden-flower',(.85,.44,.035)),('white-flower',(.78,.73,.59))]:
  material_path=folder+'/M_Blossoms_'+aid.replace('-','_');blossom=EAL.load_asset(material_path) if EAL.does_asset_exist(material_path) else ATS.create_asset(material_path.rsplit('/',1)[-1],folder,unreal.Material,unreal.MaterialFactoryNew());MEL.delete_all_material_expressions(blossom);blossom.set_editor_property('two_sided',True);blossom.set_editor_property('used_with_instanced_static_meshes',True);blossom.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_TWO_SIDED_FOLIAGE)
  for prop,rgb in [(unreal.MaterialProperty.MP_BASE_COLOR,tint),(unreal.MaterialProperty.MP_SUBSURFACE_COLOR,tuple(v*.22 for v in tint))]:
   n=MEL.create_material_expression(blossom,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(*rgb,1));assert MEL.connect_material_property(n,'',prop)
  n=MEL.create_material_expression(blossom,unreal.MaterialExpressionConstant);n.set_editor_property('r',.82);assert MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_ROUGHNESS);assert not MEL.recompile_material(blossom);assert EAL.save_loaded_asset(blossom,False)
  meshes=[]
  for lod in range(3):
   mesh=import_one(source_folder/aid/('LOD'+str(lod)+'-source.glb'),aid,lod,False)
   for slot,s in enumerate(mesh.get_editor_property('static_materials')):
    name=str(s.get_editor_property('imported_material_slot_name'));material=bark if 'Bark' in name else blossom if 'Blossoms' in name else leaf;mesh.set_material(slot,material)
   assert EAL.save_loaded_asset(mesh,False);meshes.append(mesh)
  mesh=meshes[0]
  for lod,other in enumerate(meshes[1:],1):assert api.set_lod_from_static_mesh(mesh,lod,other,0,True)==lod
  assert api.set_lod_screen_sizes(mesh,[1.,.14,.045]);EAL.set_metadata_tag(mesh,'TreeUpgradeId',aid);EAL.set_metadata_tag(mesh,'CanopyConstruction','open leaf sprays and individual five-petal blossoms; no opaque flower balls');assert EAL.save_loaded_asset(mesh,False);assets[aid]=mesh
 for a in list(actors.values()):
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   old=c.static_mesh;old_path=old.get_path_name()
   if not any('/'+aid.replace('-','_')+'/' in old_path for aid in assets) or '/TreeUpgradeV' not in old_path:continue
   def transform_values(t):return [t.translation.x,t.translation.y,t.translation.z,t.rotation.x,t.rotation.y,t.rotation.z,t.rotation.w,t.scale3d.x,t.scale3d.y,t.scale3d.z]
   aid=EAL.get_metadata_tag(old,'TreeUpgradeId');assert aid in assets,(old_path,aid);mesh=assets[aid];name=c.get_name();xform=actor_xform(a);before_relative=transform_values(c.get_relative_transform());collision=str(c.get_collision_profile_name());instanced=isinstance(c,unreal.InstancedStaticMeshComponent)
   before_instances=[transform_values(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())] if instanced else [];materials=[c.get_material(i).get_path_name() if c.get_material(i) else None for i in range(c.get_num_materials())];c.modify();c.set_static_mesh(mesh);c.set_editor_property('override_materials',[mesh.get_material(i) for i in range(len(mesh.get_editor_property('static_materials')))]);c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==name)
   assert c.static_mesh==mesh,(a.get_actor_label(),'mesh binding');assert actor_xform(a)==xform,(a.get_actor_label(),'actor transform',xform,actor_xform(a));assert transform_values(c.get_relative_transform())==before_relative,(a.get_actor_label(),'component transform',before_relative,transform_values(c.get_relative_transform()));assert str(c.get_collision_profile_name())==collision,(a.get_actor_label(),'collision',collision,str(c.get_collision_profile_name()))
   assert ([transform_values(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())] if instanced else [])==before_instances,(a.get_actor_label(),'instance transforms')
   trees.append(dict(actor=a.get_actor_label(),component=name,before=old_path,after=mesh.get_path_name(),materials_before=materials,instances=len(before_instances) if instanced else 1,transforms_preserved=True,collision_preserved=True))
 assert len(trees)>100,('flower-tree targets missing',len(trees))
 sky=EAL.load_asset(read('plan')['materials']['sky']);sky.set_editor_property('is_sky',True);assert not MEL.recompile_material(sky);assert EAL.save_loaded_asset(sky,False)
 controller.initialize_bindings();controller.set_hour(21.);controller.apply_environment();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();record_map_save('dark-letter-signs-and-natural-flower-trees')
 write('visual_polish',dict(status='passed',signs=signs,trees=trees,sign_count=len(signs),tree_components=len(trees),tree_instances=sum(r['instances'] for r in trees),tree_meshes={k:v.get_path_name() for k,v in assets.items()},map_sha256=sha(MAPFILE),backup=str(backup),sky_is_sky=True,visual_review='required'))
]====]
