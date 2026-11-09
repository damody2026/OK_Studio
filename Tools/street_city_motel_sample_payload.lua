return [====[
SAMPLE_OUT=ROOT/'output/street-social-city-production/motel-v1/sample-rooms'
SAMPLE_PREFIX='/Game/UniversityCity/MotelRoomsV2'
MOT='/Game/UniversityCity/MotelV1'

def motel_sample_import():
 # Textured sample suites keep their glTF materials (Interchange) instead of the semantic Motel_* slot binding.
 global PREFIX,KEEP,save
 b=json.loads((SAMPLE_OUT/'sample-build.json').read_text('utf8'));PREFIX=SAMPLE_PREFIX;KEEP=[];save=save_asset
 src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one'];rows=[]
 spa=EAL.load_asset(MOT+'/Materials/M_SpaWater');assert spa
 for r in b['rooms']:
  assert sha(r['path'])==r['sha256'];mesh=imp(Path(r['path']),r['id']+'-v2',0,True)
  mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(mesh,False)
  water=imp(Path(r['water_path']),r['id']+'-v2-water',0,False)
  for k in range(len(water.get_editor_property('static_materials'))):water.set_material(k,spa)
  assert EAL.save_loaded_asset(water,False)
  rows.append(dict(id=r['id'],asset=mesh.get_path_name(),water_asset=water.get_path_name(),source_sha256=r['sha256'],triangles=mesh.get_num_triangles(0),materials=len(mesh.get_editor_property('static_materials'))))
 assert sha(MAPFILE)==LOAD_SHA;(SAMPLE_OUT/'sample-imports.json').write_text(json.dumps(dict(status='imported',map_sha256=LOAD_SHA,assets=rows),ensure_ascii=False,indent=2),'utf8')

def motel_pool_water_parent():
 # M_SpaWater is one translucent constant colour shared by every motel tub and pool. Pool suites need their own water
 # colour (201 navy, 205/207 green-blue), so a copy with WaterColor / WaterOpacity parameters is the parent of per-room
 # instances; M_SpaWater itself and everything using it stay unchanged.
 path=MOT+'/Materials/M_MotelPoolWater'
 if EAL.does_asset_exist(path):return EAL.load_asset(path)
 m=EAL.duplicate_asset(MOT+'/Materials/M_SpaWater',path);assert m
 for prop,cls,name,x in ((unreal.MaterialProperty.MP_BASE_COLOR,unreal.MaterialExpressionVectorParameter,'WaterColor',-700),(unreal.MaterialProperty.MP_OPACITY,unreal.MaterialExpressionScalarParameter,'WaterOpacity',-700)):
  old=MEL.get_material_property_input_node(m,prop);p=MEL.create_material_expression(m,cls,x,0 if name=='WaterColor' else 260);p.set_editor_property('parameter_name',name)
  if isinstance(old,unreal.MaterialExpressionConstant3Vector):p.set_editor_property('default_value',old.get_editor_property('constant'))
  elif isinstance(old,unreal.MaterialExpressionConstant4Vector):p.set_editor_property('default_value',old.get_editor_property('constant'))
  elif isinstance(old,unreal.MaterialExpressionConstant) and name=='WaterOpacity':p.set_editor_property('default_value',old.get_editor_property('r'))
  elif name=='WaterOpacity':p.set_editor_property('default_value',.8)
  else:p.set_editor_property('default_value',unreal.LinearColor(.03,.2,.25,1))
  assert MEL.connect_material_property(p,'',prop),name
 MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def motel_pool_water_mi(rid,pw):
 path=MOT+'/Materials/MI_PoolWater_'+rid.replace('-','_');parent=motel_pool_water_parent()
 mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset('MI_PoolWater_'+rid.replace('-','_'),MOT+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
 MEL.set_material_instance_parent(mi,parent);c=pw.get('color',[.03,.2,.25])
 MEL.set_material_instance_vector_parameter_value(mi,'WaterColor',unreal.LinearColor(c[0],c[1],c[2],1))
 if pw.get('opacity') is not None:MEL.set_material_instance_scalar_parameter_value(mi,'WaterOpacity',float(pw['opacity']))
 assert EAL.save_loaded_asset(mi,False);return mi

def motel_tub_water_parent():
 # Tub water is opaque: every translucent attempt (M_SpaWater, then a dark .85 WaterColor instance, rounds 11-13) still
 # read as a pale empty bowl in the bright bathrooms, because translucency is lit by the coarse lighting volume. A dark,
 # very smooth opaque surface gets proper Lumen reflections and reads as still water.
 path=MOT+'/Materials/M_MotelTubWaterOpaque'
 if EAL.does_asset_exist(path):return EAL.load_asset(path)
 m=ATS.create_asset('M_MotelTubWaterOpaque',MOT+'/Materials',unreal.Material,unreal.MaterialFactoryNew());assert m
 p=MEL.create_material_expression(m,unreal.MaterialExpressionVectorParameter,-500,0);p.set_editor_property('parameter_name','WaterColor');p.set_editor_property('default_value',unreal.LinearColor(.01,.07,.09,1))
 assert MEL.connect_material_property(p,'',unreal.MaterialProperty.MP_BASE_COLOR)
 r=MEL.create_material_expression(m,unreal.MaterialExpressionConstant,-500,200);r.set_editor_property('r',.04)
 assert MEL.connect_material_property(r,'',unreal.MaterialProperty.MP_ROUGHNESS)
 s=MEL.create_material_expression(m,unreal.MaterialExpressionConstant,-500,300);s.set_editor_property('r',.6)
 assert MEL.connect_material_property(s,'',unreal.MaterialProperty.MP_SPECULAR)
 MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m

def motel_tub_water_mi(rid,tw):
 path=MOT+'/Materials/MI_TubWater_'+rid.replace('-','_')
 mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset('MI_TubWater_'+rid.replace('-','_'),MOT+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
 MEL.set_material_instance_parent(mi,motel_tub_water_parent());c=tw.get('color',[.01,.07,.09])
 MEL.set_material_instance_vector_parameter_value(mi,'WaterColor',unreal.LinearColor(c[0],c[1],c[2],1))
 assert EAL.save_loaded_asset(mi,False);return mi

def motel_rooms_install():
 # Mass-produced data-driven rooms (Tools/build_street_city_motel_rooms_v2.lua): import + install one batch per job
 # (sample-rooms/rooms-v2-batch.json {"ids":[...]}); GC after every room keeps the worker's commit flat.
 global PREFIX,KEEP,save
 b=json.loads((SAMPLE_OUT/'rooms-v2-build.json').read_text('utf8'));only=set(json.loads((SAMPLE_OUT/'rooms-v2-batch.json').read_text('utf8'))['ids'])
 build={r['id']:r for r in b['rooms'] if r['id'] in only};assert build,'empty batch'
 PREFIX=SAMPLE_PREFIX;KEEP=[];save=save_asset
 src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one']
 spa=EAL.load_asset(MOT+'/Materials/M_SpaWater');assert spa
 installed=read('motel-install');rooms={r['id']:r for r in installed['rooms']};plan={r['id']:r for r in read('motel-plan')['rooms']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 backup=SAMPLE_OUT/('UniversityCity-before-rooms-v2-'+LOAD_SHA[:16]+'.umap')
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 rows=[]
 for rid,r in sorted(build.items()):
  assert sha(r['path'])==r['sha256'];mesh=imp(Path(r['path']),rid+'-v2',0,True)
  mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(mesh,False)
  water=imp(Path(r['water_path']),rid+'-v2-water',0,False)
  pw=r.get('pool_water')
  for k,s in enumerate(water.get_editor_property('static_materials')):
   slot=str(s.get_editor_property('material_slot_name'))+' '+str(s.get_editor_property('imported_material_slot_name'))
   # tub water has its own slot and an opaque dark material (motel_tub_water_parent)
   tw=r.get('tub_water')
   water.set_material(k,motel_pool_water_mi(rid,pw) if pw and 'PoolWater' in slot else motel_tub_water_mi(rid,tw) if tw and 'TubWater' in slot else spa)
  assert EAL.save_loaded_asset(water,False)
  room=rooms[rid];q=plan[rid];ang=math.radians(q['yaw']);base=room['position']
  def world(v):return unreal.Vector(base[0]+(v[0]*math.sin(ang)+v[1]*math.cos(ang))*100,base[1]+(v[0]*math.cos(ang)-v[1]*math.sin(ang))*100,base[2]+v[2]*100)
  a=actors['MotelV1_Suite_'+rid];a.modify();a.static_mesh_component.set_static_mesh(mesh)
  # drop the component-level slot-0 M_SpaWater override left by the v1 install so the mesh's own slots (pool MI) show
  wa=actors['MotelV1_Water_'+rid];wa.modify();wa.static_mesh_component.set_static_mesh(water);wa.static_mesh_component.set_editor_property('override_materials',[])
  for label,act in list(actors.items()):
   if label.startswith('MotelV1_Light_'+rid+'_') or label.startswith('MotelV2_Light_'+rid+'_'):SUB.destroy_actor(act)
  for i,l in enumerate(r['lights']):
   # 'spot': [inner, outer] cone degrees -> downward recessed light; otherwise an omni point light
   p=SUB.spawn_actor_from_class(unreal.SpotLight if l.get('spot') else unreal.PointLight,world(l['local']),unreal.Rotator(0,-90,0) if l.get('spot') else unreal.Rotator(0,0,0));p.set_actor_label('MotelV2_Light_'+rid+'_'+str(i));p.tags=[unreal.Name('MotelV1'),unreal.Name('MotelV2Rooms')];p.set_folder_path('UniversityCity/MotelV1/Lights')
   if l.get('spot'):c=p.spot_light_component;c.set_inner_cone_angle(float(l['spot'][0]));c.set_outer_cone_angle(float(l['spot'][1]))
   else:c=p.point_light_component
   c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(float(l['lumens']));c.set_editor_property('attenuation_radius',float(l['radius']));c.set_editor_property('cast_shadows',i==0);c.set_light_color(unreal.LinearColor(*l['color'],1))
  for slot,key in [('A','decorA_local'),('B','decorB_local')]:
   d=actors.get('MotelDecorTripoV1_'+rid+'-decor-'+slot)
   if d:d.modify();p=world(r[key]);d.set_actor_location(unreal.Vector(p.x,p.y,p.z+.12),False,False)
  room['previous_asset']=room.get('asset');room['asset']=mesh.get_path_name();room['water_asset_v2']=water.get_path_name()
  rows.append(dict(id=rid,asset=mesh.get_path_name(),water_asset=water.get_path_name(),triangles=mesh.get_num_triangles(0),lights=len(r['lights'])))
  KEEP.clear();unreal.SystemLibrary.collect_garbage()
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);installed.setdefault('rooms_v2',[]);installed['rooms_v2']=sorted(set(installed['rooms_v2'])|set(build));write('motel-install',installed)
 (SAMPLE_OUT/('rooms-v2-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),rooms=rows),ensure_ascii=False,indent=2),'utf8')

def motel_sample_install():
 imports={r['id']:r for r in json.loads((SAMPLE_OUT/'sample-imports.json').read_text('utf8'))['assets']};build={r['id']:r for r in json.loads((SAMPLE_OUT/'sample-build.json').read_text('utf8'))['rooms']}
 installed=read('motel-install');rooms={r['id']:r for r in installed['rooms']};plan={r['id']:r for r in read('motel-plan')['rooms']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 backup=SAMPLE_OUT/('UniversityCity-before-sample-rooms-'+LOAD_SHA[:16]+'.umap')
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 rows=[]
 for rid,b in build.items():
  room=rooms[rid];q=plan[rid];ang=math.radians(q['yaw']);base=room['position']
  def world(v):return unreal.Vector(base[0]+(v[0]*math.sin(ang)+v[1]*math.cos(ang))*100,base[1]+(v[0]*math.cos(ang)-v[1]*math.sin(ang))*100,base[2]+v[2]*100)
  im=imports[rid];a=actors['MotelV1_Suite_'+rid];a.modify();a.static_mesh_component.set_static_mesh(EAL.load_asset(im['asset']))
  wa=actors['MotelV1_Water_'+rid];wa.modify();wa.static_mesh_component.set_static_mesh(EAL.load_asset(im['water_asset']))
  for label,act in list(actors.items()):
   if label.startswith('MotelV1_Light_'+rid+'_') or label.startswith('MotelV2_Light_'+rid+'_'):SUB.destroy_actor(act)
  for i,l in enumerate(b['lights']):
   p=SUB.spawn_actor_from_class(unreal.PointLight,world(l['local']));p.set_actor_label('MotelV2_Light_'+rid+'_'+str(i));p.tags=[unreal.Name('MotelV1'),unreal.Name('MotelV2Sample')];p.set_folder_path('UniversityCity/MotelV1/Lights')
   c=p.point_light_component;c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(float(l['lumens']));c.set_editor_property('attenuation_radius',float(l['radius']));c.set_editor_property('cast_shadows',i==0);c.set_light_color(unreal.LinearColor(*l['color'],1))
  moved=[]
  for slot,key in [('A','decorA_local'),('B','decorB_local')]:
   d=actors.get('MotelDecorTripoV1_'+rid+'-decor-'+slot)
   if d:d.modify();p=world(b[key]);d.set_actor_location(unreal.Vector(p.x,p.y,p.z+.12),False,False);moved.append(dict(slot=slot,position=num(d.get_actor_location())))
  rows.append(dict(id=rid,asset=im['asset'],lights=len(b['lights']),decor=moved))
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new,sample_rooms=[r['id'] for r in rows]);write('motel-install',installed)
 (SAMPLE_OUT/'sample-install.json').write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),rooms=rows),ensure_ascii=False,indent=2),'utf8')
]====]
