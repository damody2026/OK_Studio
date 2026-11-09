-- Native install of the shop-street sample shops (Tools/build_street_city_shop_samples.lua output).
--   shop_samples_install: localized sign material + sign/feature textures, refit meshes, cut copies of the current
--   floor meshes (GeometryScripting; the depth-repaired originals stay untouched), actors, lights; saves the map.
-- Queued with: lua Tools/street_city_motel_job.lua shop_samples_install Tools/street_city_shop_samples_payload.lua
return [====[
SHOP_OUT=ROOT/'output/street-social-city-production/shop-samples-v1'
SHOP_PREFIX='/Game/UniversityCity/ShopSamplesV1'
LOCS=('zh-Hant','zh-Hans','en')

def shop_texture(path,dest_folder,name):
 dest=dest_folder+'/'+name
 if EAL.does_asset_exist(dest):EAL.delete_asset(dest)
 t=unreal.AssetImportTask();t.set_editor_property('filename',str(path));t.set_editor_property('destination_path',dest_folder);t.set_editor_property('destination_name',name);t.set_editor_property('automated',True);t.set_editor_property('replace_existing',True);t.set_editor_property('save',True)
 ATS.import_asset_tasks([t]);a=EAL.load_asset(dest);assert a,('texture import failed',path);a.set_editor_property('srgb',True);EAL.save_loaded_asset(a,False);return a

def shop_sign_base():
 path=SHOP_PREFIX+'/Materials/M_ShopSign_Localized'
 if EAL.does_asset_exist(path):return EAL.load_asset(path)
 m=ATS.create_asset('M_ShopSign_Localized',SHOP_PREFIX+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
 c=EAL.load_asset('/Game/UniversityCity/Localization/MPC_CityLanguage');assert c
 nodes=[]
 for i,loc in enumerate(LOCS):
  n=MEL.create_material_expression(m,unreal.MaterialExpressionTextureSampleParameter2D,-700,i*240);n.set_editor_property('parameter_name','CityText_'+loc.replace('-','_'));nodes.append(n)
 ctl=MEL.create_material_expression(m,unreal.MaterialExpressionCollectionParameter,-1000,0);ctl.set_editor_property('collection',c);ctl.set_editor_property('parameter_name','LanguageIndex')
 def choose(th,low,high,x):
  n=MEL.create_material_expression(m,unreal.MaterialExpressionIf,x,0);n.set_editor_property('const_b',th);assert MEL.connect_material_expressions(ctl,'',n,'A')
  for pin,src in [('A > B',high),('A == B',high),('A < B',low)]:assert MEL.connect_material_expressions(src,'RGB' if src in nodes else '',n,pin)
  return n
 last=choose(1.5,choose(.5,nodes[0],nodes[1],-350),nodes[2],-100);assert MEL.connect_material_property(last,'',unreal.MaterialProperty.MP_BASE_COLOR)
 glow=MEL.create_material_expression(m,unreal.MaterialExpressionScalarParameter,-100,300);glow.set_editor_property('parameter_name','Glow');glow.set_editor_property('default_value',2.0)
 mul=MEL.create_material_expression(m,unreal.MaterialExpressionMultiply,100,200);assert MEL.connect_material_expressions(last,'',mul,'A');assert MEL.connect_material_expressions(glow,'',mul,'B');assert MEL.connect_material_property(mul,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 r=MEL.create_material_expression(m,unreal.MaterialExpressionConstant,100,400);r.set_editor_property('r',.45);MEL.connect_material_property(r,'',unreal.MaterialProperty.MP_ROUGHNESS)
 MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def shop_simple_material(name,tex):
 path=SHOP_PREFIX+'/Materials/'+name
 if EAL.does_asset_exist(path):EAL.delete_asset(path)
 m=ATS.create_asset(name,SHOP_PREFIX+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
 n=MEL.create_material_expression(m,unreal.MaterialExpressionTextureSample,-400,0);n.set_editor_property('texture',tex);assert MEL.connect_material_property(n,'RGB',unreal.MaterialProperty.MP_BASE_COLOR)
 r=MEL.create_material_expression(m,unreal.MaterialExpressionConstant,-200,200);r.set_editor_property('r',.65);MEL.connect_material_property(r,'',unreal.MaterialProperty.MP_ROUGHNESS)
 MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def shop_front_flip(sm,H):
 # The street facade (door, windows, sign) has many more triangles than the plain back facade; count both strips.
 dm=unreal.DynamicMesh();dm,outcome=unreal.GeometryScript_AssetUtils.copy_mesh_from_static_mesh(sm,dm,unreal.GeometryScriptCopyMeshFromAssetOptions(),unreal.GeometryScriptMeshReadLOD());counts={}
 for flip in (1,-1):
  ya,yb=sorted(((-H-.03)*100*flip,(-H+.215)*100*flip))
  dm,sel=unreal.GeometryScript_MeshSelection.select_mesh_elements_in_box(dm,unreal.Box(unreal.Vector(-581,ya,-1),unreal.Vector(581,yb,370)),unreal.GeometryScriptMeshSelectionType.TRIANGLES,False,1)
  info=unreal.GeometryScript_MeshSelection.get_mesh_selection_info(sel);counts[flip]=info[1] if isinstance(info,tuple) else int(info)
 # glTF import flips Y for every shop GLB (all installed shops measured -1); the counts are kept only as evidence
 return -1,counts
def shop_cut_copy(old,dest,boxes):
 if EAL.does_asset_exist(dest):EAL.delete_asset(dest)
 cut=EAL.duplicate_asset(old.get_path_name(),dest);assert cut
 dm=unreal.DynamicMesh();KEEP.append(dm);dm,outcome=unreal.GeometryScript_AssetUtils.copy_mesh_from_static_mesh(cut,dm,unreal.GeometryScriptCopyMeshFromAssetOptions(),unreal.GeometryScriptMeshReadLOD())
 # WorldSheet-merged floors keep whole facades as a few large triangles: slice along every cut-box face first so the
 # whole-triangle front selection still finds the wall (and the corner piers outside the box survive)
 opt=unreal.GeometryScriptMeshPlaneSliceOptions();opt.set_editor_property('fill_holes',False)
 for b in boxes:
  lo,hi=b['ue_min'],b['ue_max']
  for axis,vals in ((unreal.Vector(1,0,0),(lo[0],hi[0])),(unreal.Vector(0,1,0),(lo[1],hi[1])),(unreal.Vector(0,0,1),(lo[2],hi[2]))):
   for val in vals:
    p=unreal.Vector(axis.x*val,axis.y*val,axis.z*val);frame=unreal.Transform(p,unreal.MathLibrary.make_rot_from_z(axis),unreal.Vector(1,1,1))
    dm=unreal.GeometryScript_MeshBooleans.apply_mesh_plane_slice(dm,frame,opt)
 global GS_EDIT
 GS_EDIT=next(getattr(unreal,n) for n in ('GeometryScript_MeshEdits','GeometryScript_MeshBasicEditFunctions','GeometryScriptLibrary_MeshBasicEditFunctions') if hasattr(unreal,n))
 q=unreal.GeometryScript_MeshQueries;before=next(getattr(q,n)(dm) for n in ('get_num_triangle_i_ds','get_triangle_count','get_num_triangle_ids') if hasattr(q,n));deleted=[]
 for b in boxes:
  box=unreal.Box(unreal.Vector(*b['ue_min']),unreal.Vector(*b['ue_max']))
  # front strip: whole triangles only (keeps the corner piers); fixtures: any vertex inside (catches split depth-repair pieces)
  dm,sel=unreal.GeometryScript_MeshSelection.select_mesh_elements_in_box(dm,box,unreal.GeometryScriptMeshSelectionType.TRIANGLES,False,3 if b['name'].startswith('front') else 1)
  dm,n=GS_EDIT.delete_selected_triangles_from_mesh(dm,sel,True);deleted.append(dict(name=b['name'],triangles=n))
 opts=unreal.GeometryScriptCopyMeshToAssetOptions();opts.set_editor_property('replace_materials',False);opts.set_editor_property('enable_recompute_normals',False);opts.set_editor_property('enable_recompute_tangents',False);opts.set_editor_property('emit_transaction',False)
 dm,outcome=unreal.GeometryScript_AssetUtils.copy_mesh_to_static_mesh(dm,cut,opts,unreal.GeometryScriptMeshWriteLOD())
 cut.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(cut,False)
 return cut,before,deleted

def motel_shop_samples_install():shop_install(SHOP_OUT,'samples-build.json','samples-install.json',None)
def motel_shop_refits_install():
 # batch: shop-refits-v1/install-batch.json {"ids":[...]} (all built refits when absent)
 out=ROOT/'output/street-social-city-production/shop-refits-v1';bf=out/'install-batch.json'
 shop_install(out,'refits-build.json','refits-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json',json.loads(bf.read_text('utf8'))['ids'] if bf.exists() else None)
def shop_install(SHOP_OUT,build_name,receipt_name,only):
 global PREFIX,KEEP,save
 build=[b for b in json.loads((SHOP_OUT/build_name).read_text('utf8'))['shops'] if not only or b['id'] in only];PREFIX=SHOP_PREFIX;KEEP=[];save=save_asset
 src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one']
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};base=shop_sign_base();rows=[]
 backup=SHOP_OUT/('UniversityCity-before-'+build_name.split('-')[0]+'-'+LOAD_SHA[:16]+'.umap')
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 for b in build:
  sid=b['id'];assert sha(b['path'])==b['sha256'];floor=actors[sid+'_F01'];comp=floor.static_mesh_component
  # the original asset path is remembered on the actor so a rerun cuts from the untouched depth-repaired mesh
  orig_path=EAL.get_metadata_tag(comp.static_mesh,'ShopSampleOriginal') or comp.static_mesh.get_path_name()
  old=EAL.load_asset(orig_path);old_slots=[str(s.get_editor_property('material_slot_name')) for s in old.get_editor_property('static_materials')]
  old_component=[comp.get_material(i) for i in range(len(old_slots))] if comp.static_mesh.get_path_name()==orig_path else json.loads(EAL.get_metadata_tag(comp.static_mesh,'ShopSampleComponentMaterials'))
  if old_component and isinstance(old_component[0],str):old_component=[EAL.load_asset(p) if p else None for p in old_component]
  folder=SHOP_PREFIX+'/'+sid
  if b.get('no_cut'):  # special frontages (S18/S19) add to the building without removing anything
   flip,cy,before,deleted,cut=-1,None,None,[],comp.static_mesh
  else:
   flip,cy=shop_front_flip(old,b['H'])
   def ue_box(bx):
    x0,x1,y0,y1,z0,z1=bx;ya,yb=sorted((y0*100*flip,y1*100*flip));return dict(ue_min=[x0*100,ya,z0*100],ue_max=[x1*100,yb,z1*100])
   boxes=[dict(name=c['name'],**ue_box(c['box'])) for c in b['cut']]
   cut,before,deleted=shop_cut_copy(old,folder+'/SM_'+sid+'_F01_Cut',boxes)
   EAL.set_metadata_tag(cut,'ShopSampleOriginal',orig_path);EAL.set_metadata_tag(cut,'ShopSampleComponentMaterials',json.dumps([m.get_path_name() if m else None for m in old_component]));EAL.save_loaded_asset(cut,False)
   assert sum(d['triangles'] for d in deleted)>0,('nothing cut',sid)
   floor.modify();comp.set_static_mesh(cut)
  for i,mm in enumerate(old_component):
   if mm:comp.set_material(i,mm)
  feature=None
  if b.get('feature') and b['feature']['slot'] in old_slots:
   t=shop_texture(Path(b.get('textures_dir',str(SHOP_OUT/'textures')))/(b['feature']['tex']+'.png'),folder+'/Textures','T_'+sid+'_feature');fm=shop_simple_material('M_ShopV1_'+sid+'_feature',t);comp.set_material(old_slots.index(b['feature']['slot']),fm);feature=fm.get_path_name()
  # refit mesh and its localized signs
  mesh=imp(Path(b['path']),'ShopV1-'+sid+'-refit',0,True);mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
  slots=[str(s.get_editor_property('material_slot_name')) for s in mesh.get_editor_property('static_materials')];signs=[]
  for s in b['signs']:
   kind=s['slot'][-1];texs={loc:shop_texture(Path(b['sign_textures'][kind][loc]),folder+'/Textures','T_'+sid+'_'+kind+'_'+loc.replace('-','_')) for loc in LOCS}
   mi_path=folder+'/MI_ShopSign_'+sid+'_'+kind
   if EAL.does_asset_exist(mi_path):EAL.delete_asset(mi_path)
   mi=ATS.create_asset('MI_ShopSign_'+sid+'_'+kind,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,base)
   for loc,t in texs.items():MEL.set_material_instance_texture_parameter_value(mi,'CityText_'+loc.replace('-','_'),t)
   MEL.set_material_instance_scalar_parameter_value(mi,'Glow',float(s['glow']));EAL.save_loaded_asset(mi,False)
   idx=[i for i,n in enumerate(slots) if n.startswith(s['slot'])];assert idx,(sid,s['slot'],slots)
   for i in idx:mesh.set_material(i,mi)
   signs.append(dict(slot=s['slot'],material=mi.get_path_name()))
  assert EAL.save_loaded_asset(mesh,False)
  label='ShopV1_'+sid+'_Refit';old_refit=actors.get(label)
  if old_refit:SUB.destroy_actor(old_refit)
  t=floor.get_actor_transform();ra=SUB.spawn_actor_from_class(unreal.StaticMeshActor,t.translation,floor.get_actor_rotation());ra.set_actor_label(label);ra.set_actor_scale3d(t.scale3d)
  ra.static_mesh_component.set_static_mesh(mesh);ra.set_folder_path('Shops/'+sid);ra.tags=[unreal.Name('ShopSamplesV1')]
  for lab,act in list(actors.items()):
   if lab.startswith('ShopV1_'+sid+'_Light_'):SUB.destroy_actor(act)
  for i,l in enumerate(b['lights']):
   x,y,z=l['local'];p=t.transform_location(unreal.Vector(x*100,y*100*flip,z*100))
   pl=SUB.spawn_actor_from_class(unreal.PointLight,p);pl.set_actor_label('ShopV1_'+sid+'_Light_'+str(i));pl.set_folder_path('Shops/'+sid);pl.tags=[unreal.Name('ShopSamplesV1')]
   c=pl.point_light_component;c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(float(l['lumens']));c.set_editor_property('attenuation_radius',float(l['radius']));c.set_editor_property('cast_shadows',i==0);c.set_light_color(unreal.LinearColor(*l['color'],1))
  # the RomanceName plaque must hang on the street facade; some were placed on the back wall
  name=actors.get('RomanceName_'+sid);moved=None
  if name and not b.get('special'):
   inv=t.inverse_transform_location(name.get_actor_location());front=-b['H']*100*flip
   if (inv.y>0)!=(front>0):
    before=dict(location=num(name.get_actor_location()),rotation=[name.get_actor_rotation().roll,name.get_actor_rotation().pitch,name.get_actor_rotation().yaw])
    name.modify();name.set_actor_location(t.transform_location(unreal.Vector(inv.x,-inv.y,inv.z)),False,False);r0=name.get_actor_rotation();name.set_actor_rotation(unreal.Rotator(r0.roll,r0.pitch,r0.yaw+180),False)
    moved=dict(before=before,after=dict(location=num(name.get_actor_location()),yaw=name.get_actor_rotation().yaw))
  o,e=ra.get_actor_bounds(False);fo,fe=floor.get_actor_bounds(False)
  # free the per-shop DynamicMesh copies, interchange pipelines and textures before the next shop (peak commit was >100 GB)
  KEEP.clear();unreal.SystemLibrary.collect_garbage()
  rows.append(dict(id=sid,original_mesh=orig_path,cut_mesh=cut.get_path_name(),triangles_before=before,cut=deleted,flip_y=flip,centroid_y=cy,refit_mesh=mesh.get_path_name(),refit_triangles=mesh.get_num_triangles(0),signs=signs,feature=feature,lights=len(b['lights']),romance_name_moved=moved,refit_bounds=[num(o),num(e)],floor_bounds=[num(fo),num(fe)]))
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 mi=OUT/'motel-install.json'
 if mi.exists():
  d=json.loads(mi.read_text('utf8'));d.update(parent_map_sha256=LOAD_SHA,map_sha256=new);d.setdefault('shop_refits',[]);d['shop_refits']=sorted(set(d['shop_refits'])|{r['id'] for r in rows});mi.write_text(json.dumps(d,ensure_ascii=False,indent=2),'utf8')
 (SHOP_OUT/receipt_name).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),shops=rows),ensure_ascii=False,indent=2),'utf8')
]====]
