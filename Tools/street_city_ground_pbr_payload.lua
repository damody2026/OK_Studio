return [====[
PREFIX='/Game/UniversityCity/GroundPBRV1'
MAPFILE=ROOT/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
LOAD_SHA=sha(MAPFILE)

def material_chain(m):
 out=[];seen=set()
 while m and m.get_path_name() not in seen:
  seen.add(m.get_path_name());out.append(m.get_path_name())
  if isinstance(m,unreal.Material):break
  m=m.get_editor_property('parent')
 return out,m

def input_graph(m,prop):
 nodes=[];seen=set()
 def walk(n):
  if not n or n.get_path_name() in seen:return
  seen.add(n.get_path_name());row={'class':n.get_class().get_name()}
  for k in ['texture','parameter_name','default_value','r','g','b','a','code']:
   try:
    v=n.get_editor_property(k)
    if isinstance(v,unreal.Object):v=v.get_path_name()
    elif not isinstance(v,(str,float,int,bool,type(None))):v=str(v)
    row[k]=v
   except:pass
  nodes.append(row)
  for child in MEL.get_inputs_for_material_expression(m,n):walk(child)
 walk(MEL.get_material_property_input_node(m,prop));return nodes

def ground_inventory():
 materials={};components=[];actor_labels=[]
 for a in SUB.get_all_level_actors():
  actor_labels.append(a.get_actor_label())
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   origin,extent=c.get_component_bounds()[:2] if hasattr(c,'get_component_bounds') else a.get_actor_bounds(False)
   row=dict(actor=a.get_actor_label(),component=c.get_name(),mesh=c.static_mesh.get_path_name(),collision=str(c.get_collision_profile_name()),origin=num(origin),extent=num(extent),xform=str(c.get_world_transform()),instances=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else 1,slots=[])
   for slot in range(c.get_num_materials()):
    m=c.get_material(slot)
    if not m:continue
    p=m.get_path_name();row['slots'].append(dict(slot=slot,material=p))
    if p not in materials:
     chain,root=material_chain(m);entry=dict(path=p,chain=chain,uses=0,examples=[],texture_overrides=[])
     if root:
      entry['two_sided']=root.get_editor_property('two_sided');entry['blend']=str(root.get_editor_property('blend_mode'))
      entry['graphs']={key:input_graph(root,prop) for key,prop in [('basecolor',unreal.MaterialProperty.MP_BASE_COLOR),('normal',unreal.MaterialProperty.MP_NORMAL),('roughness',unreal.MaterialProperty.MP_ROUGHNESS),('metallic',unreal.MaterialProperty.MP_METALLIC)]}
     if isinstance(m,unreal.MaterialInstanceConstant):
      for t in m.get_editor_property('texture_parameter_values'):
       v=t.get_editor_property('parameter_value');entry['texture_overrides'].append(dict(parameter=str(t.get_editor_property('parameter_info')),texture=v.get_path_name() if v else None))
     materials[p]=entry
    materials[p]['uses']+=1
    if len(materials[p]['examples'])<12:materials[p]['examples'].append(dict(actor=row['actor'],component=row['component'],slot=slot))
   components.append(row)
 write('inventory',dict(status='passed',map_sha256=LOAD_SHA,scope='Every StaticMeshComponent and material slot across the loaded city, including HISM counts; classification is a separate reviewed plan',actor_count=len(actor_labels),component_count=len(components),materials=list(materials.values()),components=components))

def ground_transform(t):
 return dict(translation=[round(float(getattr(t.translation,k)),9) for k in ['x','y','z']],rotation=[round(float(getattr(t.rotation,k)),9) for k in ['x','y','z','w']],scale=[round(float(getattr(t.scale3d,k)),9) for k in ['x','y','z']])

def ground_snapshot():
 rows=[]
 for a in SUB.get_all_level_actors():
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   d=dict(actor=a.get_actor_label(),actor_transform=actor_xform(a),component=c.get_name(),mesh=c.static_mesh.get_path_name(),transform=ground_transform(c.get_world_transform()),collision=str(c.get_collision_profile_name()),visible=c.get_editor_property('visible'),hidden=c.get_editor_property('hidden_in_game'),actor_hidden=a.get_editor_property('hidden'),cast_shadow=c.get_editor_property('cast_shadow'),materials=[c.get_material(i).get_path_name() if c.get_material(i) else None for i in range(c.get_num_materials())])
   if isinstance(c,unreal.InstancedStaticMeshComponent):d['instances']=[ground_transform(c.get_instance_transform(i,True)) for i in range(c.get_instance_count())]
   rows.append(d)
 return sorted(rows,key=lambda r:(r['actor'],r['component']))

STOCHASTIC_CODES=(COLOR_CODE.replace('+Inst*19.0',''),NORM_CODE.replace('+Inst*19.0',''),ORM_CODE.replace('+Inst*19.0',''))
def aligned_code(kind):
 lines=['float period=max(Period,20.0);float3 an=abs(N);float3 w=an/max(an.x+an.y+an.z,.0001);']
 for axis,swizzle in [('X','zy'),('Y','xz'),('Z','xy')]:
  ch='rg' if kind=='Norm' else 'rgb';typ='float2' if kind=='Norm' else 'float3'
  lines.append(f'float2 uv{axis}=P.{swizzle}/period;{typ} r{axis}=Texture2DSampleGrad({kind},{kind}Sampler,uv{axis},ddx(uv{axis}),ddy(uv{axis})).{ch};')
 if kind=='Norm':
  lines+=['float2 ax=(rX*2-1)*Strength;float2 ay=(rY*2-1)*Strength;float2 az=(rZ*2-1)*Strength;','float3 nx=float3(sqrt(saturate(1-dot(ax,ax)))*sign(N.x),ax.y,ax.x);float3 ny=float3(ay.x,sqrt(saturate(1-dot(ay,ay)))*sign(N.y),ay.y);float3 nz=float3(az.x,az.y,sqrt(saturate(1-dot(az,az)))*sign(N.z));return normalize(nx*w.x+ny*w.y+nz*w.z);']
 elif kind=='Orm':lines+=['float3 packed=rX*w.x+rY*w.y+rZ*w.z;packed.b=0;return packed;']
 else:lines+=['float3 color=rX*w.x+rY*w.y+rZ*w.z;float macro=.5+.25*sin(P.x/2300.0+Seed)+.25*sin(P.y/3100.0+Seed*.7);return color*lerp(TintA,TintB,macro);']
 return '\n'.join(lines)

def ground_master(textures,aligned):
 global PREFIX,COLOR_CODE,NORM_CODE,ORM_CODE,node
 prefix=PREFIX;PREFIX=prefix+('/Aligned' if aligned else '/Natural')
 COLOR_CODE,NORM_CODE,ORM_CODE=(aligned_code('Base'),aligned_code('Norm'),aligned_code('Orm')) if aligned else STOCHASTIC_CODES
 old=EAL.load_asset(PREFIX+'/Materials/M_RomancePBR')
 if old:EAL.set_metadata_tag(old,'RomancePBRVersion','0');EAL.set_metadata_tag(old,'GroundVersion','')
 original_node=node
 def ground_node(mat,cls,x,y):return original_node(mat,unreal.MaterialExpressionConstant if cls==unreal.MaterialExpressionPerInstanceRandom else cls,x,y)
 node=ground_node
 try:master,mode=build_master(textures)
 finally:node=original_node
 assert mode=='custom','Ground shader must use coherent world-space PBR sampling'
 if EAL.get_metadata_tag(master,'GroundVersion')!='1':
  original=MEL.get_material_property_input_node(master,unreal.MaterialProperty.MP_BASE_COLOR)
  recolor=scalar(master,'GroundRecolor',0,-300,-400);target=vector(master,'GroundTarget',[1,1,1],-300,-500);ref=scalar(master,'GroundLumaRef',.2,-300,-600)
  adjusted=custom(master,[('Color',original),('Recolor',recolor),('Target',target),('Reference',ref)],'float l=dot(Color,float3(.2126,.7152,.0722));return lerp(Color,Target*clamp(l/max(Reference,.015),.70,1.3),Recolor);',300,-200)
  assert MEL.connect_material_property(adjusted,'',unreal.MaterialProperty.MP_BASE_COLOR);assert not compile_errors(master)
  EAL.set_metadata_tag(master,'GroundVersion','1');save_asset(master)
 diagnostic=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(master))
 assert not diagnostic.get('graph_error') and not diagnostic.get('global_rejection') and not diagnostic.get('component_rejection'),diagnostic
 PREFIX=prefix;return master,diagnostic

def ground_install():
 assert not (OUT/'install.json').exists(),'A ground install already exists; audit it before creating a new revision'
 plan=read('plan');assert plan['status']=='reviewed_ready_for_generation' and not plan['blocked'] and plan['map_sha256']==LOAD_SHA
 verification=read('verification');assert verification['status']=='passed'
 assert sha(MAPFILE)==LOAD_SHA
 (OUT/'backups').mkdir(exist_ok=True);dest=OUT/'backups'/('UniversityCity-before-ground-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,dest);assert sha(dest)==LOAD_SHA
 catalog={s['id']:s for s in read('catalog')['sets']};wanted=[r for r in plan['decisions'] if r['action']=='replace'];textures={};luma=read('texture-luma')
 for sid in sorted({r['set'] for r in wanted}):
  meta=catalog[sid];paths={k:OUT/meta[k] for k in ['basecolor','normal','orm']};generation=json.loads((paths['basecolor'].parent/'generation.json').read_text('utf8'));assert generation['status']=='generated'
  for k in paths:assert generation[k+'_sha256']==sha(paths[k]),(sid,k)
  textures[sid]={k:import_texture(sid,k,paths[k],k=='basecolor',unreal.TextureCompressionSettings.TC_DEFAULT if k=='basecolor' else (unreal.TextureCompressionSettings.TC_NORMALMAP if k=='normal' else unreal.TextureCompressionSettings.TC_MASKS)) for k in paths}
  assert sid in luma and luma[sid]>0,'Missing independently measured texture mean'
 masters={};diagnostics={}
 for aligned in [False,True]:masters[aligned],diagnostics[str(aligned)]=ground_master(next(iter(textures.values())),aligned)
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();controller.set_actor_tick_enabled(False)
 before=ground_snapshot();components={(a.get_actor_label(),c.get_name()):c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)};changes=[];instances={}
 for r in wanted:
  c=components[(r['actor'],r['component'])];assert c.static_mesh.get_path_name()==r['mesh'] and c.get_material(r['slot']).get_path_name()==r['before'],('inventory binding changed',r)
  aligned=r['family'] in ['pedestrian_pavers','terracotta_paving','timber_deck','tactile_paving','interior_porcelain','interior_terrazzo']
  identity=json.dumps([r['set'],r['period_cm'],r['seed'],r['two_sided'],r.get('recolor')],sort_keys=True);key=hashlib.sha256(identity.encode()).hexdigest()[:20]
  if key not in instances:
   name='MI_Ground_'+key;mi=EAL.load_asset(PREFIX+'/Materials/'+name) or ATS.create_asset(name,PREFIX+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());assert mi
   MEL.set_material_instance_parent(mi,masters[aligned])
   for p,k in [('RomanceBase','basecolor'),('RomanceNormal','normal'),('RomanceORM','orm')]:MEL.set_material_instance_texture_parameter_value(mi,p,textures[r['set']][k])
   for p,v in [('RomancePeriod',r['period_cm']),('RomanceSeed',r['seed']),('RomanceStrength',1.),('GroundRecolor',1. if r.get('recolor') else 0.),('GroundLumaRef',luma[r['set']])]:MEL.set_material_instance_scalar_parameter_value(mi,p,float(v))
   for p,v in [('RomanceTintA',[.985,.985,.985]),('RomanceTintB',[1.015,1.015,1.015]),('GroundTarget',r.get('recolor') or [1,1,1])]:MEL.set_material_instance_vector_parameter_value(mi,p,unreal.LinearColor(*v,1))
   props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',r['two_sided']);mi.set_editor_property('base_property_overrides',props)
   EAL.set_metadata_tag(mi,'GroundSet',r['set']);EAL.set_metadata_tag(mi,'GroundFamily',r['family']);MEL.update_material_instance(mi);save_asset(mi);instances[key]=mi
  mi=instances[key];c.modify();c.set_material(r['slot'],mi);changes.append(dict(r,after=mi.get_path_name(),aligned=aligned))
 after=ground_snapshot();assert len(before)==len(after)==plan['component_count'];by_key={(r['actor'],r['component']):r for r in changes}
 expected={(r['actor'],r['component'],r['slot']):r for r in changes}
 for old,new in zip(before,after):
  assert (old['actor'],old['component'])==(new['actor'],new['component'])
  normalized=dict(new);normalized['materials']=list(new['materials'])
  for i,mat in enumerate(normalized['materials']):
   r=expected.get((new['actor'],new['component'],i))
   if r:assert mat==r['after'];normalized['materials'][i]=r['before']
  assert old==normalized,('non-material scene change',old['actor'],old['component'])
 assert sha(MAPFILE)==LOAD_SHA and sha(dest)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new_sha=sha(MAPFILE)
 write('preservation',dict(status='passed',before=before,after=after,component_count=len(before),scope='Exact all-component mesh identity, actor/component/instance transforms, collision, visibility and shadow preservation; only approved material slots differ'))
 write('install',dict(status='saved_requires_reopen_audit',before_map_sha256=LOAD_SHA,map_sha256=new_sha,backup=str(dest),changes=changes,counts=plan['counts'],selected_slot_count=len(changes),master_diagnostics=diagnostics,texture_sets=sorted(textures),material_instances=len(instances),geometry_changes=0,pdo_or_wpo=False))
 receipt=ROOT/'output/street-social-city-production/day-night-v1/current-map.json';old=json.loads(receipt.read_text('utf8'));assert old['map_sha256']==LOAD_SHA
 receipt.write_text(json.dumps(dict(status='saved',operation='ground_pbr_1k',parent_map_sha256=LOAD_SHA,map_sha256=new_sha,saved_at_utc=time.time(),run_id=PAYLOAD['run_id']),indent=2),'utf8')

def ground_audit():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA==sha(MAPFILE)
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};actors['CityEnvironmentController'].prepare_for_save();actors['CityEnvironmentController'].set_actor_tick_enabled(False)
 assert ground_snapshot()==read('preservation')['after'],'Reopened scene differs from the material-only saved snapshot'
 components={(a.get_actor_label(),c.get_name()):c for a in actors.values() for c in a.get_components_by_class(unreal.StaticMeshComponent)};checked=set();bound=0
 for r in installed['changes']:
  c=components[(r['actor'],r['component'])];mi=c.get_material(r['slot']);assert mi.get_path_name()==r['after'];assert c.static_mesh.get_path_name()==r['mesh'];bound+=1
  props=mi.get_editor_property('base_property_overrides');assert props.get_editor_property('override_two_sided') and props.get_editor_property('two_sided')==r['two_sided']
  if mi.get_path_name() in checked:continue
  checked.add(mi.get_path_name());assert EAL.get_metadata_tag(mi,'GroundSet')==r['set']
  params=[('GroundFloorBase','basecolor'),('GroundFloorNorm','normal'),('GroundFloorOrm','orm')] if r.get('floor_layer') else [('RomanceBase','basecolor'),('RomanceNormal','normal'),('RomanceORM','orm')]
  for p,k in params:
   t=MEL.get_material_instance_texture_parameter_value(mi,p);assert t and t.blueprint_get_size_x()==1024 and t.blueprint_get_size_y()==1024 and t.get_editor_property('max_texture_size')==1024
   assert EAL.get_metadata_tag(t,'RomanceSourceSHA')==sha(OUT/'sets'/r['set']/(k+'.png')),('source texture revision differs',r['set'],k)
   assert bool(t.get_editor_property('srgb'))==(k=='basecolor')
   if k=='normal':assert t.get_editor_property('compression_settings')==unreal.TextureCompressionSettings.TC_NORMALMAP and not t.get_editor_property('flip_green_channel')
  assert abs(MEL.get_material_instance_scalar_parameter_value(mi,'GroundFloorPeriod' if r.get('floor_layer') else 'RomancePeriod')-r['period_cm'])<.001
  if r.get('floor_layer'):assert abs(MEL.get_material_instance_scalar_parameter_value(mi,'GroundFloorZ')-r['floor_z_cm'])<.01
 write('audit',dict(status='passed',map_sha256=LOAD_SHA,component_preservation_count=len(read('preservation')['after']),material_slot_bindings=bound,unique_material_instances=len(checked),all_maps_1024=True,geometry_changes=0,world_aligned_contiguous_terrain=True,source_map_unchanged=True))

def ground_texture_refresh():
 installed=read('install');assert sha(MAPFILE)==installed['map_sha256']==LOAD_SHA
 assert read('verification')['status']=='passed';changes=[]
 folder=OUT/'backups'/('textures-'+PAYLOAD['run_id']);folder.mkdir(parents=True)
 for sid in installed['texture_sets']:
  for k in ['basecolor','normal','orm']:
   file=OUT/'sets'/sid/(k+'.png');name='T_'+sid+'_'+k;path=PREFIX+'/Textures/'+name;asset=EAL.load_asset(path);assert asset
   old=EAL.get_metadata_tag(asset,'RomanceSourceSHA');new=sha(file)
   if old==new:continue
   source=ROOT/'StreetSocialCity/Content'/('UniversityCity/GroundPBRV1/Textures/'+name+'.uasset');dest=folder/source.name;shutil.copy2(source,dest)
   t=import_texture(sid,k,file,k=='basecolor',unreal.TextureCompressionSettings.TC_DEFAULT if k=='basecolor' else (unreal.TextureCompressionSettings.TC_NORMALMAP if k=='normal' else unreal.TextureCompressionSettings.TC_MASKS))
   assert EAL.get_metadata_tag(t,'RomanceSourceSHA')==new
   changes.append(dict(asset=path,before_source_sha256=old,source_sha256=new,backup=str(dest)))
 assert sha(MAPFILE)==LOAD_SHA
 write('shader',dict(status='passed',map_sha256=LOAD_SHA,changes=changes,scope='Refresh only changed generated ground texture assets; no map save or geometry changes'))

def ground_backface_fix():
 installed=read('install');assert installed['map_sha256']==LOAD_SHA==sha(MAPFILE)
 paths=[PREFIX+'/Natural/Materials/M_RomancePBR',PREFIX+'/Aligned/Materials/M_RomancePBR']+[r['base_material'] for r in installed['floor_master_diagnostics'].values()]
 assert len(set(paths))==6;folder=OUT/'backups'/('backface-'+PAYLOAD['run_id']);folder.mkdir(parents=True);rows=[]
 for path in sorted(set(paths)):
  assert path.startswith(PREFIX+'/');m=EAL.load_asset(path);assert isinstance(m,unreal.Material)
  relative=path.split('.')[0].replace('/Game/','')+'.uasset';source=ROOT/'StreetSocialCity/Content'/relative;dest=folder/relative;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
  changed=[]
  if '/FloorLayers/' not in path:
   n=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_NORMAL);code=str(n.get_editor_property('code'));assert n.get_class().get_name()=='MaterialExpressionCustom'
   if not code.startswith('N*=Parameters.TwoSidedSign;'):n.set_editor_property('code','N*=Parameters.TwoSidedSign;\n'+code);changed.append('world normal visible-face orientation')
  else:
   nodes={};seen=set()
   def walk(n):
    if not n or n.get_path_name() in seen:return
    seen.add(n.get_path_name())
    if n.get_class().get_name()=='MaterialExpressionCustom' and str(n.get_editor_property('code')).startswith('float Mask='):nodes[n.get_path_name()]=n
    for child in MEL.get_inputs_for_material_expression(m,n):walk(child)
   for prop in [unreal.MaterialProperty.MP_BASE_COLOR,unreal.MaterialProperty.MP_NORMAL,unreal.MaterialProperty.MP_ROUGHNESS]:walk(MEL.get_material_property_input_node(m,prop))
   assert len(nodes)==3
   normal=MEL.get_material_property_input_node(m,unreal.MaterialProperty.MP_NORMAL)
   for n in nodes.values():
    code=str(n.get_editor_property('code'));code=code.replace('smoothstep(.85,.98,N.z)','smoothstep(.85,.98,N.z*Parameters.TwoSidedSign)')
    if n==normal and not m.get_editor_property('tangent_space_normal'):
     if 'N*=Parameters.TwoSidedSign;' not in code:code=code.replace('float period=max(Period,20.0);','N*=Parameters.TwoSidedSign;\nfloat period=max(Period,20.0);')
     code=code.replace('float3 OldW=Original;','float3 OldW=Original*Parameters.TwoSidedSign;')
    n.set_editor_property('code',code);changed.append(n.get_name())
  assert not compile_errors(m)
  diagnostic=json.loads(unreal.CityDepthAuditLibrary.inspect_street_material(m));assert not diagnostic.get('graph_error') and 'world_position_offset_or_displacement' not in diagnostic.get('component_rejection',''),diagnostic
  EAL.set_metadata_tag(m,'GroundVisibleFaceNormals','1');save_asset(m);rows.append(dict(material=path,changes=changed,backup=str(dest),diagnostic=diagnostic))
 assert sha(MAPFILE)==LOAD_SHA
 write('normal_fix',dict(status='passed',map_sha256=LOAD_SHA,rows=rows,source_binding_audit_sha256=sha(OUT/'audit.json'),scope='World-space normals are explicitly oriented to the visible face for two-sided materials. Floor masks use the visible-face direction. Tangent-space output retains the engine automatic flip. Geometry, culling, texture bindings and source map bytes unchanged.'))

def work():
 try:
  if MODE=='inventory':ground_inventory()
  elif MODE=='install':ground_install()
  elif MODE=='audit':ground_audit()
  elif MODE=='shader':ground_texture_refresh()
  elif MODE=='finish':ground_finish()
  elif MODE=='verify':ground_floor_upper_refine()
  elif MODE=='complete':ground_complete_soil()
  elif MODE=='normal_fix':ground_backface_fix()
  else:raise RuntimeError('Unsupported ground operation')
 except BaseException:
  write(MODE+'-error',dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc())
 unreal.SystemLibrary.quit_editor()

assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry' if MODE in ['shader','normal_fix'] else MAP)
unreal.EditorPythonScripting.set_keep_python_script_alive(True)
frames=0
def tick(dt):
 global frames
 frames+=1
 if frames<90:return
 unreal.unregister_slate_post_tick_callback(handle);work()
handle=unreal.register_slate_post_tick_callback(tick)
]====]
