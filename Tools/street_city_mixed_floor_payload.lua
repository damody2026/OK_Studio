return [====[

def ground_original_pin(mat,prop,default):
 n=MEL.get_material_property_input_node(mat,prop)
 if not n:
  if isinstance(default,(float,int)):return const(mat,default,-2600,0)
  return vector(mat,'GroundOriginalDefault'+str(prop),default,-2600,0)
 out=MEL.get_material_property_input_node_output_name(mat,prop)
 pin=node(mat,unreal.MaterialExpressionReroute,-2400,0)
 assert MEL.connect_material_expressions(n,out,pin,''),(mat.get_path_name(),str(prop),out)
 return pin

def ground_floor_master(source,example_textures,cache):
 chain,base=material_chain(source);key=base.get_path_name()
 if key in cache:return cache[key]
 assert isinstance(base,unreal.Material) and not base.get_editor_property('use_material_attributes'),('Unsupported packed source material',key)
 name='M_FloorLayer_'+hashlib.sha256(key.encode()).hexdigest()[:18];path=PREFIX+'/FloorLayers/'+name
 mat=EAL.load_asset(path) if EAL.does_asset_exist(path) else EAL.duplicate_asset(key,path);assert mat
 if EAL.get_metadata_tag(mat,'GroundFloorVersion')=='1':
  assert EAL.get_metadata_tag(mat,'GroundOriginalRoot')==key
  diagnostic=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(mat));assert not diagnostic.get('graph_error') and 'world_position_offset_or_displacement' not in diagnostic.get('component_rejection','')
  cache[key]=(mat,diagnostic);return cache[key]
 old_color=ground_original_pin(mat,unreal.MaterialProperty.MP_BASE_COLOR,[.5,.5,.5])
 old_normal=ground_original_pin(mat,unreal.MaterialProperty.MP_NORMAL,[0,0,1])
 old_ao=ground_original_pin(mat,unreal.MaterialProperty.MP_AMBIENT_OCCLUSION,1.)
 old_rough=ground_original_pin(mat,unreal.MaterialProperty.MP_ROUGHNESS,.5)
 old_metal=ground_original_pin(mat,unreal.MaterialProperty.MP_METALLIC,0.)
 pack=node(mat,unreal.MaterialExpressionAppendVector,-2000,600);link(old_ao,pack,'A');link(old_rough,pack,'B')
 old_orm=node(mat,unreal.MaterialExpressionAppendVector,-1800,600);link(pack,old_orm,'A');link(old_metal,old_orm,'B')
 P=node(mat,unreal.MaterialExpressionWorldPosition,-2500,-800);N=node(mat,unreal.MaterialExpressionVertexNormalWS,-2500,-650)
 floor_z=scalar(mat,'GroundFloorZ',0,-2500,-500);period=scalar(mat,'GroundFloorPeriod',140,-2500,-400);seed=scalar(mat,'GroundFloorSeed',0,-2500,-300);strength=scalar(mat,'GroundFloorStrength',1,-2500,-200)
 common=[('P',P),('N',N),('FloorZ',floor_z),('Period',period),('Seed',seed)]
 tex={}
 for label,kind,sampler in [('Base','basecolor',unreal.MaterialSamplerType.SAMPLERTYPE_COLOR),('Norm','normal',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL),('Orm','orm',unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR)]:
  t=node(mat,unreal.MaterialExpressionTextureObjectParameter,-2500,800+len(tex)*150);t.set_editor_property('parameter_name','GroundFloor'+label);t.set_editor_property('texture',example_textures[kind]);t.set_editor_property('sampler_type',sampler);tex[label]=t
 tint_a=vector(mat,'GroundFloorTintA',[.985,.985,.985],-2500,1500);tint_b=vector(mat,'GroundFloorTintB',[1.015,1.015,1.015],-2500,1650)
 prefix='float Mask=smoothstep(.85,.98,N.z)*(1-smoothstep(8.0,12.0,abs(P.z-FloorZ)));[branch] if(Mask<.0001)return Original;\n'
 color_code=aligned_code('Base').replace('return color*lerp(TintA,TintB,macro);','return lerp(Original,color*lerp(TintA,TintB,macro),Mask);')
 normal_code=aligned_code('Norm');old_end='return normalize(nx*w.x+ny*w.y+nz*w.z);'
 tangent=bool(mat.get_editor_property('tangent_space_normal'))
 replacement=('float3 OldW=TransformTangentVectorToWorld(Parameters.TangentToWorld,Original);' if tangent else 'float3 OldW=Original;')+'float3 NewW=normalize(lerp(OldW,normalize(nx*w.x+ny*w.y+nz*w.z),Mask));'+('return TransformWorldVectorToTangent(Parameters.TangentToWorld,NewW);' if tangent else 'return NewW;')
 assert old_end in normal_code;normal_code=normal_code.replace(old_end,replacement)
 orm_code=aligned_code('Orm').replace('return packed;','return lerp(Original,packed,Mask);')
 color=custom(mat,common+[('Original',old_color),('Base',tex['Base']),('TintA',tint_a),('TintB',tint_b)],prefix+color_code,-800,-500)
 normal=custom(mat,common+[('Original',old_normal),('Norm',tex['Norm']),('Strength',strength)],prefix+normal_code,-800,0)
 orm=custom(mat,common+[('Original',old_orm),('Orm',tex['Orm'])],prefix+orm_code,-800,600)
 assert MEL.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR)
 assert MEL.connect_material_property(normal,'',unreal.MaterialProperty.MP_NORMAL)
 for rgba,prop,y in [((True,False,False),unreal.MaterialProperty.MP_AMBIENT_OCCLUSION,700),((False,True,False),unreal.MaterialProperty.MP_ROUGHNESS,800),((False,False,True),unreal.MaterialProperty.MP_METALLIC,900)]:
  m=mask(mat,orm,*rgba,False,-300,y);assert MEL.connect_material_property(m,'',prop)
 assert not compile_errors(mat)
 diagnostic=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(mat))
 assert not diagnostic.get('graph_error');assert 'world_position_offset_or_displacement' not in diagnostic.get('component_rejection',''),diagnostic
 EAL.set_metadata_tag(mat,'GroundFloorVersion','1');EAL.set_metadata_tag(mat,'GroundOriginalRoot',key);save_asset(mat);cache[key]=(mat,diagnostic)
 return mat,diagnostic

def ground_copy_parameters(source,dest):
 sources=[];m=source
 while isinstance(m,unreal.MaterialInstanceConstant):sources.append(m);m=m.get_editor_property('parent')
 for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:
  values={}
  for m in reversed(sources):
   for v in m.get_editor_property(field):
    p=v.get_editor_property('parameter_info');key=(str(p.get_editor_property('name')),str(p.get_editor_property('association')),p.get_editor_property('index'));values[key]=v
  dest.set_editor_property(field,list(values.values()))

def ground_finish():
 installed=read('install');plan=read('mixed-floor-plan');assert plan['status']=='reviewed' and plan['map_sha256']==installed['map_sha256']==LOAD_SHA
 assert not (OUT/'finish.json').exists(),'Floor layer already saved; use audit'
 ground_texture_refresh()
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 before=ground_snapshot();assert before==read('preservation')['after'],'Scene changed after the ground install'
 components={(a.get_actor_label(),c.get_name()):c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)}
 folder=OUT/'backups';dest=folder/('UniversityCity-before-floor-layers-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,dest);assert sha(dest)==LOAD_SHA
 textures={};masters={};changes=[]
 for sid in sorted({r['set'] for r in plan['rows']}):
  textures[sid]={k:import_texture(sid,k,OUT/'sets'/sid/(k+'.png'),k=='basecolor',unreal.TextureCompressionSettings.TC_DEFAULT if k=='basecolor' else (unreal.TextureCompressionSettings.TC_NORMALMAP if k=='normal' else unreal.TextureCompressionSettings.TC_MASKS)) for k in ['basecolor','normal','orm']}
 for r in plan['rows']:
  c=components[(r['actor'],r['component'])];source=c.get_material(r['slot']);assert source.get_path_name()==r['before'] and c.static_mesh.get_path_name()==r['mesh']
  master,diagnostic=ground_floor_master(source,textures[r['set']],masters)
  key=hashlib.sha256((r['actor']+'::'+r['component']+'::'+str(r['slot'])).encode()).hexdigest()[:20];name='MI_FloorLayer_'+key
  mi=ATS.create_asset(name,PREFIX+'/FloorLayers',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());assert mi
  MEL.set_material_instance_parent(mi,master);ground_copy_parameters(source,mi)
  for label,kind in [('Base','basecolor'),('Norm','normal'),('Orm','orm')]:MEL.set_material_instance_texture_parameter_value(mi,'GroundFloor'+label,textures[r['set']][kind])
  for p,v in [('GroundFloorZ',r['floor_z_cm']),('GroundFloorPeriod',r['period_cm']),('GroundFloorSeed',r['seed']),('GroundFloorStrength',1.)]:MEL.set_material_instance_scalar_parameter_value(mi,p,float(v))
  props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',r['two_sided']);mi.set_editor_property('base_property_overrides',props)
  EAL.set_metadata_tag(mi,'GroundSet',r['set']);EAL.set_metadata_tag(mi,'GroundOriginalMaterial',r['before']);MEL.update_material_instance(mi);save_asset(mi)
  c.modify();c.set_material(r['slot'],mi);changes.append(dict(r,after=mi.get_path_name()))
 after=ground_snapshot();expected={(r['actor'],r['component'],r['slot']):r for r in changes}
 for old,new in zip(before,after):
  restored=dict(new);restored['materials']=list(new['materials'])
  for i in range(len(restored['materials'])):
   r=expected.get((new['actor'],new['component'],i))
   if r:assert restored['materials'][i]==r['after'];restored['materials'][i]=r['before']
  assert old==restored,('Floor layer changed geometry or non-target material',old['actor'],old['component'])
 assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new_sha=sha(MAPFILE)
 preservation=read('preservation');preservation['after']=after;preservation['floor_layer_pass_before_map_sha256']=LOAD_SHA;write('preservation',preservation)
 write('install-before-floor-layers',installed);installed['changes']+=changes;installed['map_sha256']=new_sha;installed['selected_slot_count']=len(installed['changes']);installed['texture_sets']=sorted(set(installed['texture_sets'])|set(textures));installed['floor_actors_covered']=427;installed['floor_layer_source_map_sha256']=LOAD_SHA;installed['floor_master_diagnostics']={k:v[1] for k,v in masters.items()};write('install',installed)
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';old=json.loads(receipt.read_text('utf8'));assert old['map_sha256']==LOAD_SHA
 receipt.write_text(json.dumps(dict(status='saved',operation='ground_pbr_mixed_floor_layers',parent_map_sha256=LOAD_SHA,map_sha256=new_sha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')
 write('finish',dict(status='passed',before_map_sha256=LOAD_SHA,map_sha256=new_sha,additional_slots=len(changes),floor_actors_covered=427,backup=str(dest),geometry_changes=0,wall_source_inputs_preserved=True))

def ground_floor_upper_refine():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA==sha(MAPFILE)
 geometric=read('geometry-floor-upper');largest={};planes={}
 for r in geometric['rows']:
  if not re.search(r'_F\d+$',r['actor']):continue
  if r['actor'] not in largest or r['floor_band_area_m2']>largest[r['actor']]['floor_band_area_m2']:largest[r['actor']]=r
  planes[r['actor']]=r['floor_z_cm']
 assert len(largest)==427
 bound={(r['actor'],r['component'],r['slot']) for r in installed['changes']}
 pending=[r for r in largest.values() if (r['actor'],r['component'],r['slot']) not in bound]
 assert all(r['floor_band_area_m2']>4 for r in largest.values())
 assert len(pending)==1 and pending[0]['actor']=='Campus_SP_F01' and pending[0]['slot']==0,'Unexpected extra upper floor binding requires review'
 folder=OUT/'backups'/('floor-upper-'+PAYLOAD['run_id']);folder.mkdir(parents=True);changes=[]
 for r in installed['changes']:
  if not r.get('floor_layer'):continue
  mi=EAL.load_asset(r['after']);assert mi and EAL.get_metadata_tag(mi,'GroundOriginalMaterial')==r['before']
  before=MEL.get_material_instance_scalar_parameter_value(mi,'GroundFloorZ');target=planes[r['actor']]
  if abs(before-target)>.01:
   source=ROOT/'StreetSocialCity/Content'/(r['after'].split('.')[0].replace('/Game/','')+'.uasset');shutil.copy2(source,folder/source.name)
   MEL.set_material_instance_scalar_parameter_value(mi,'GroundFloorZ',target);MEL.update_material_instance(mi);save_asset(mi)
   changes.append(dict(actor=r['actor'],material=r['after'],before_z_cm=before,upper_z_cm=target))
  r['floor_z_before_winding_correction_cm']=r['floor_z_cm'];r['floor_z_cm']=target
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();probes=[];cameras=[]
 for label in ['S01_F01','S01_F02','Campus_D1_F01','Campus_SP_F01','City_O03_F02','Mall_M1_F02']:
  a=actors[label];origin,extent=a.get_actor_bounds(False);z=planes[label];found=None
  attempts=[]
  for fx,fy in [(0,0),(-.4,-.4),(.4,-.4),(-.4,.4),(.4,.4),(-.65,0),(.65,0),(0,-.65),(0,.65)]:
   x=origin.x+extent.x*fx;y=origin.y+extent.y*fy
   hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z+20),unreal.Vector(x,y,z-50),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None
   attempts.append(dict(x=x,y=y,hit_actor=v[9].get_actor_label() if v and v[0] and v[9] else None,hit_z_cm=float(v[4].z) if v and v[0] else None,normal=num(v[7]) if v and v[0] else None))
   if not v or not v[0] or not v[9] or v[9].get_actor_label()!=label or v[7].z<.85 or abs(v[4].z-z)>1.:continue
   found=dict(actor=label,geometric_upper_z_cm=z,native_collision_z_cm=float(v[4].z),normal=num(v[7]),xy_cm=[x,y])
   clear=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(x,y,z+110),unreal.Vector(x,y,z+110),25,95))
   if not clear['blocked']:
    cameras.append(dict(id='floor-'+label,eye=[x,y,z+165],target=[x+130,y+100,z+15],fov=75,hour=12,native_support=found,clearance=clear));break
  write('verify-probe-progress',dict(status='running',actor=label,geometric_z_cm=z,attempts=attempts,completed=probes,cameras=cameras))
  assert found,('Native collision does not confirm the selected upper slab face',label,z)
  probes.append(found)
 assert sha(MAPFILE)==LOAD_SHA
 write('install-before-upper-refine',read('install'));write('install',installed)
 write('verify',dict(status='passed',map_sha256=LOAD_SHA,refined_materials=len(changes),changes=changes,floor_actors=427,largest_upper_floor_surfaces_bound=427-len(pending),pending_floor_assignments=pending,source_geometry_sha256=geometric['scene_sha256'],native_collision_probes=probes,cameras=cameras,map_saved=False,geometry_changes=0,method='Render winding is not a vertex normal. Select the highest broad slab face from both windings in the lowest metre above the actual component datum, then confirm representative heights with real native complex collision traces.'))

def ground_complete_soil():
 global LOAD_SHA
 installed=read('install');proof=read('verify');assert proof['status']=='passed' and installed['map_sha256']==proof['map_sha256']==LOAD_SHA==sha(MAPFILE)
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 before=ground_snapshot();assert before==read('preservation')['after']
 source_actor=actors['LandscapeV3_SoilPlanters'];prototype=next(r for r in installed['changes'] if r['family']=='planting_soil');material=EAL.load_asset(prototype['after']);changes=[]
 for c in source_actor.get_components_by_class(unreal.StaticMeshComponent):
  for slot in range(c.get_num_materials()):
   old=c.get_material(slot)
   if not old or old.get_name()!='Street_soil':continue
   assert material.get_editor_property('base_property_overrides').get_editor_property('two_sided')==old.get_editor_property('two_sided')
   r=dict(prototype,actor=source_actor.get_actor_label(),component=c.get_name(),slot=slot,before=old.get_path_name(),after=material.get_path_name(),mesh=c.static_mesh.get_path_name(),instances=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else 1,reason='Consolidated city landscape planting soil found by final all-material semantic sweep')
   c.modify();c.set_material(slot,material);changes.append(r)
 assert len(changes)==1
 for pending in proof['pending_floor_assignments']:
  r=dict(next(v for v in installed['changes'] if v['actor']==pending['actor'] and v.get('floor_layer')))
  a=actors[pending['actor']];c=next(v for v in a.get_components_by_class(unreal.StaticMeshComponent) if v.get_name()==pending['component']);source=c.get_material(pending['slot']);assert source.get_path_name()==pending['material']
  sid=r['set'];textures={k:EAL.load_asset(PREFIX+'/Textures/T_'+sid+'_'+k) for k in ['basecolor','normal','orm']};master,_=ground_floor_master(source,textures,{})
  name='MI_FloorLayer_'+hashlib.sha256((pending['actor']+'::'+pending['component']+'::'+str(pending['slot'])).encode()).hexdigest()[:20]
  mi=EAL.load_asset(PREFIX+'/FloorLayers/'+name) if EAL.does_asset_exist(PREFIX+'/FloorLayers/'+name) else ATS.create_asset(name,PREFIX+'/FloorLayers',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());assert mi
  MEL.set_material_instance_parent(mi,master);ground_copy_parameters(source,mi)
  for label,kind in [('Base','basecolor'),('Norm','normal'),('Orm','orm')]:MEL.set_material_instance_texture_parameter_value(mi,'GroundFloor'+label,textures[kind])
  for p,v in [('GroundFloorZ',pending['floor_z_cm']),('GroundFloorPeriod',r['period_cm']),('GroundFloorSeed',r['seed']),('GroundFloorStrength',1.)]:MEL.set_material_instance_scalar_parameter_value(mi,p,float(v))
  scene=json.loads((ROOT/'output/street-social-city-production/day-night-v1/surface-final/scene.json').read_text('utf8'));original=next(i for i in scene['instances'] if i['actor']==pending['actor'] and i['component']==pending['component']);sided=original['two_sided_by_slot'][pending['slot']]
  props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',sided);mi.set_editor_property('base_property_overrides',props)
  EAL.set_metadata_tag(mi,'GroundSet',sid);EAL.set_metadata_tag(mi,'GroundOriginalMaterial',source.get_path_name());MEL.update_material_instance(mi);save_asset(mi)
  r.update(actor=pending['actor'],component=pending['component'],slot=pending['slot'],before=source.get_path_name(),after=mi.get_path_name(),mesh=c.static_mesh.get_path_name(),two_sided=sided,floor_z_cm=pending['floor_z_cm'],floor_band_area_m2=pending['floor_band_area_m2']);c.modify();c.set_material(pending['slot'],mi);changes.append(r)
 assert len(changes)==2
 after=ground_snapshot();targets={(r['actor'],r['component'],r['slot']):r for r in changes}
 for old,new in zip(before,after):
  normalized=dict(new);normalized['materials']=list(new['materials'])
  for slot in range(len(normalized['materials'])):
   target=targets.get((new['actor'],new['component'],slot))
   if target:assert normalized['materials'][slot]==target['after'];normalized['materials'][slot]=target['before']
  assert old==normalized
 backup=OUT/'backups'/('UniversityCity-before-final-soil-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA==sha(MAPFILE)
 controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new_sha=sha(MAPFILE);parent=LOAD_SHA
 preservation=read('preservation');preservation['after']=after;write('preservation',preservation)
 write('install-before-final-soil',installed);installed['changes']+=changes;installed['map_sha256']=new_sha;installed['selected_slot_count']=len(installed['changes']);installed['counts']={}
 for r in installed['changes']:installed['counts'][r['family']]=installed['counts'].get(r['family'],0)+1
 write('install',installed)
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';assert json.loads(receipt.read_text('utf8'))['map_sha256']==parent
 receipt.write_text(json.dumps(dict(status='saved',operation='ground_pbr_consolidated_soil',parent_map_sha256=parent,map_sha256=new_sha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')
 write('complete',dict(status='passed',operation='complete_remaining_consolidated_soil',before_map_sha256=parent,map_sha256=new_sha,changes=changes,backup=str(backup),geometry_changes=0))
 assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');assert unreal.EditorLevelLibrary.load_level(MAP);LOAD_SHA=new_sha;ground_audit()
]====]
