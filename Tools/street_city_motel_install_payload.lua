return [====[
MOT='/Game/UniversityCity/MotelV1'

def motel_material(name,col,rough=.5,metal=0,emit=0):
 path=MOT+'/Materials/'+name;m=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset(name,MOT+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
 if EAL.get_metadata_tag(m,'MotelMaterialVersion')=='1':return m
 MEL.delete_all_material_expressions(m);n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(*col,1));MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for prop,v in [(unreal.MaterialProperty.MP_ROUGHNESS,rough),(unreal.MaterialProperty.MP_METALLIC,metal)]:
  c=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);c.set_editor_property('r',v);MEL.connect_material_property(c,'',prop)
 if emit:
  n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(*[v*emit for v in col],1));MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 m.set_editor_property('used_with_instanced_static_meshes',True);MEL.recompile_material(m);EAL.set_metadata_tag(m,'MotelMaterialVersion','1');assert EAL.save_loaded_asset(m,False);return m

def motel_pbr(name,sid,period,tint=(1,1,1),seed=0):
 path=MOT+'/Materials/'+name;mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset(name,MOT+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());parent=EAL.load_asset('/Game/UniversityCity/RomancePBR/Materials/M_RomancePBR');assert parent;MEL.set_material_instance_parent(mi,parent)
 for kind,param in [('basecolor','RomanceBase'),('normal','RomanceNormal'),('orm','RomanceORM')]:
  texture=EAL.load_asset('/Game/UniversityCity/RomancePBR/Textures/T_'+sid+'_'+kind);assert texture,(sid,kind);MEL.set_material_instance_texture_parameter_value(mi,param,texture)
 for param,v in [('RomancePeriod',period),('RomanceSeed',seed),('RomanceStrength',.6)]:MEL.set_material_instance_scalar_parameter_value(mi,param,float(v))
 for param,c in [('RomanceTintA',tint),('RomanceTintB',[v*.97 for v in tint])]:MEL.set_material_instance_vector_parameter_value(mi,param,unreal.LinearColor(*c,1))
 assert EAL.save_loaded_asset(mi,False);return mi

def motel_import(include_arch=True):
 global PREFIX,KEEP,save
 PREFIX=MOT;KEEP=[];save=save_asset;src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one'];plan=read('motel-plan');build=read('suite-build');arch=read('architecture-build');assert len(plan['rooms'])==len(build['rooms'])==61
 common={
 'Wall':motel_pbr('MI_Wall','ivory_lime_plaster_v1',210),
 'Floor':motel_pbr('MI_Floor','teak_wood_v1',220),
 'Stone':motel_pbr('MI_Stone','honed_travertine_v1',180),
 'Wood':motel_pbr('MI_Wood','teak_wood_v2',170,(.72,.64,.52)),
 'Ivory':motel_pbr('MI_Ivory','honed_limestone_v1',180),
 'PoolTile':motel_pbr('MI_PoolTile','handmade_ceramic_v1',70,(.12,.40,.72)),
 'Linen':motel_material('M_Linen',(.88,.86,.82),.84),
 'Gold':motel_material('M_Gold',(.53,.32,.10),.24,.85),
 'Steel':motel_material('M_Steel',(.28,.30,.32),.20,.9),
 'Porcelain':motel_material('M_Porcelain',(.86,.88,.88),.16),
 'Dark':motel_material('M_Dark',(.012,.014,.018),.25),
 'Light':motel_material('M_Light',(.95,.70,.35),.35,0,2),
 'Neon':motel_material('M_Neon',(.22,.20,.80),.3,0,1.5),
 'Water':motel_material('M_Water',(.025,.19,.23),.10,.15)}
 rows=[];byid={r['id']:r for r in plan['rooms']}
 items=build['rooms']+(arch['assets']+read('sign-build')['assets'] if include_arch else [])
 for i,b in enumerate(items):
  aid=b.get('id',b.get('building')+'-architecture' if 'building' in b else None);q=byid.get(aid);mats=dict(common)
  if q:mats['Accent']=motel_material('M_Accent_'+aid.replace('-','_'),q['accent'],.73);mats['Neon']=motel_material('M_Cove_'+aid.replace('-','_'),[min(.7,v+.15) for v in q['accent']],.4,0,1.5)
  assert sha(b['path'])==b['sha256'];mesh=imp(Path(b['path']),aid,0,False);slots=[]
  for k,s in enumerate(mesh.get_editor_property('static_materials')):
   raw=str(s.get_editor_property('imported_material_slot_name'));key=raw.replace('Motel_','').split('.')[0];assert key in mats,(aid,raw);mesh.set_material(k,mats[key]);slots.append(dict(slot=k,semantic=key,material=mats[key].get_path_name()))
  mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(mesh,False);water=None
  if q:
   water=imp(Path(b['water_path']),aid+'-water',0,False)
   for k in range(len(water.get_editor_property('static_materials'))):water.set_material(k,common['Water'])
   assert EAL.save_loaded_asset(water,False)
  rows.append(dict(id=aid,asset=mesh.get_path_name(),water_asset=water.get_path_name() if water else None,source_sha256=b['sha256'],materials=slots,triangles=mesh.get_num_triangles(0)))
  write('import-progress',dict(status='importing',completed=i+1,total=len(items),last=aid))
 assert sha(MAPFILE)==LOAD_SHA;write('imports' if include_arch else 'imports-rooms',dict(status='passed',map_sha256=LOAD_SHA,assets=rows,rooms=61,scope='Imported authored geometry and bound existing Grok2K world-space PBR to stone/wood/plaster. Separate water assets remain NoCollision at placement.'))

def motel_import_rooms():motel_import(False)

def motel_arch_refresh():
 global PREFIX,KEEP,save
 PREFIX=MOT;KEEP=[];save=save_asset;src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one'];installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};imports=read('imports');rows=[]
 names={'Stone':'MI_Stone','Wall':'MI_Wall','Wood':'MI_Wood','Gold':'M_Gold','Dark':'M_Dark','Light':'M_Light','Ivory':'MI_Ivory','Porcelain':'M_Porcelain'}
 for b in read('architecture-build')['assets']:
  assert sha(b['path'])==b['sha256'];aid=b['building']+'-architecture';mesh=imp(Path(b['path']),aid,0,False);slots=[]
  for i,s in enumerate(mesh.get_editor_property('static_materials')):
   key=str(s.get_editor_property('imported_material_slot_name')).replace('Motel_','').split('.')[0];assert key in names;mat=EAL.load_asset(MOT+'/Materials/'+names[key]);assert mat;mesh.set_material(i,mat);slots.append(dict(slot=i,semantic=key,material=mat.get_path_name()))
  mesh.get_editor_property('body_setup').set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);assert EAL.save_loaded_asset(mesh,False);rows.append(dict(id=aid,asset=mesh.get_path_name(),water_asset=None,source_sha256=b['sha256'],materials=slots,triangles=mesh.get_num_triangles(0)))
 backup=OUT/('UniversityCity-before-motel-architecture-repair-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 for r in rows:
  a=actors['MotelV1_Architecture_'+r['id'].split('-')[0]];a.modify();a.static_mesh_component.set_static_mesh(EAL.load_asset(r['asset']))
 imports['assets']=[r for r in imports['assets'] if r['id'] not in [q['id'] for q in rows]]+rows;write('imports',imports)
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new,architecture_repair_backup=str(backup));write('motel-install',installed);write('architecture-repair',dict(status='saved_requires_native_and_render_retest',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),assets=rows,scope='Corrected ramp face orientation and replaced filled stair blocks with supported inclined stringers and individual treads, restoring stacked-flight headroom.'))

def motel_refine():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;imports={r['id']:r for r in read('imports')['assets']};build={r['id']:r for r in read('suite-build')['rooms']};plan={r['id']:r for r in read('motel-plan')['rooms']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};backup=OUT/('UniversityCity-before-motel-render-refinement-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup)
 waterpath=MOT+'/Materials/M_SpaWater';spa=EAL.load_asset(waterpath) if EAL.does_asset_exist(waterpath) else EAL.duplicate_asset('/Game/UniversityCity/ActivityScenesV1/Materials/M_ConstantWater',waterpath);assert spa;assert EAL.save_loaded_asset(spa,False)
 for r in installed['rooms']:
  q=plan[r['id']];b=build[r['id']];im=imports[r['id']];a=actors['MotelV1_Suite_'+r['id']];a.modify();a.static_mesh_component.set_static_mesh(EAL.load_asset(im['asset']));water=actors['MotelV1_Water_'+r['id']];water.modify();water.static_mesh_component.set_static_mesh(EAL.load_asset(im['water_asset']));water.static_mesh_component.set_material(0,spa);assert str(water.static_mesh_component.get_collision_profile_name())=='NoCollision';r['asset']=im['asset'];v=b['bath_eye_local'];p=r['position'];ang=math.radians(q['yaw']);r['bath_eye']=[p[0]+(v[0]*math.sin(ang)+v[1]*math.cos(ang))*100,p[1]+(v[0]*math.cos(ang)-v[1]*math.sin(ang))*100,p[2]+v[2]*100]
 for bid in ['H1','S18']:
  for stem,aid in [('Architecture',bid+'-architecture'),('Signs',bid+'-signs')]:
   a=actors['MotelV1_'+stem+'_'+bid];a.modify();a.static_mesh_component.set_static_mesh(EAL.load_asset(imports[aid]['asset']))
 floor=EAL.load_asset(MOT+'/Materials/MI_Floor');parent=EAL.load_asset('/Game/UniversityCity/ImmersionV1/SportsFinish/M_SportsFinish');assert floor and parent;MEL.set_material_instance_parent(floor,parent);assert EAL.save_loaded_asset(floor,False)
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new,render_refinement_backup=str(backup));write('motel-install',installed);write('render-refinement',dict(status='saved_requires_reopen_and_actual_game_retest',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),rooms=61,scope='Weighted smooth furniture normals, continuous duvet drape, garage stone floors, bathroom towel rails/artwork and aligned mirror cameras; exterior entry signs lowered/moved outside obstructing upper slab; supported portico piers/beams; Grok teak floor gains14cm by120cm plank joints using the previously verified sports-floor parent.'))

def motel_parking_paint():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;assert not any(a.get_actor_label()=='MotelV1_ParkingMarkings' for a in SUB.get_all_level_actors());plan=read('motel-plan');byid={r['id']:r for r in installed['rooms']};world=unreal.EditorLevelLibrary.get_editor_world();mat=motel_material('M_ParkingPaint',(.83,.83,.72),.8);cube=EAL.load_asset('/Engine/BasicShapes/Cube');backup=OUT/('UniversityCity-before-motel-parking-paint-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,cube,mat,'FlatCampus_MotelParkingPaint');assert c;a=c.get_owner();a.set_actor_label('MotelV1_ParkingMarkings');a.tags=[unreal.Name('MotelV1')];a.set_folder_path('UniversityCity/MotelV1/Architecture');c.set_collision_profile_name('NoCollision');c.set_cast_shadow(False);transforms=[]
 for q in plan['rooms']:
  if not q['has_in_room_garage']:continue
  p=byid[q['id']]['position'];ang=math.radians(q['yaw']);gx=-q['size_m'][0]*.25
  for xx in [gx-2.55,gx+2.55]:
   yy=-7;pos=unreal.Vector(p[0]+(xx*math.sin(ang)+yy*math.cos(ang))*100,p[1]+(xx*math.cos(ang)-yy*math.sin(ang))*100,p[2]+3.4);transforms.append(unreal.Transform(location=pos,rotation=unreal.Rotator(yaw=90-q['yaw']),scale=unreal.Vector(.07,5.4,.008)))
 c.add_instances(transforms,False,True,True);assert c.get_instance_count()==104
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed);write('parking-paint',dict(status='saved_requires_retest',map_sha256=new,parent_map_sha256=LOAD_SHA,instances=104,collision='NoCollision',bottom_cm=3.0,top_cm=3.8,scope='Replace buried original striping above the new3cm stone garage finish; no coplanar top faces and no artificial collision ridges.'))

def motel_pool_steps():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;assert not any(a.get_actor_label()=='MotelV1_PoolInteriorSteps' for a in SUB.get_all_level_actors());byid={r['id']:r for r in installed['rooms']};world=unreal.EditorLevelLibrary.get_editor_world();cube=EAL.load_asset('/Engine/BasicShapes/Cube');mat=EAL.load_asset(MOT+'/Materials/MI_PoolTile');assert mat;backup=OUT/('UniversityCity-before-pool-egress-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);c=unreal.CityDepthAuditLibrary.create_flat_world_instances(world,cube,mat,'FlatCampus_MotelPoolInteriorSteps');assert c;a=c.get_owner();a.set_actor_label('MotelV1_PoolInteriorSteps');a.tags=[unreal.Name('MotelV1')];a.set_folder_path('UniversityCity/MotelV1/Architecture');c.set_collision_profile_name('BlockAll');transforms=[];rows=[]
 for q in read('motel-plan')['rooms']:
  if not q['is_pool_suite']:continue
  p=byid[q['id']]['position'];ang=math.radians(q['yaw']);right=-q['size_m'][0]*.27+4.1
  for k in range(6):
   xx=right-.125-(k+.5)*.35;yy=4.2;top=1.36-k*.16;height=top-.4;z=.4+height/2;position=unreal.Vector(p[0]+(xx*math.sin(ang)+yy*math.cos(ang))*100,p[1]+(xx*math.cos(ang)-yy*math.sin(ang))*100,p[2]+z*100);transforms.append(unreal.Transform(location=position,rotation=unreal.Rotator(yaw=90-q['yaw']),scale=unreal.Vector(.35,2.,height)))
  rows.append(dict(id=q['id'],interior_steps=6,riser_cm=16,pool_floor_m=.4,rim_m=1.36))
 c.add_instances(transforms,False,True,True);assert c.get_instance_count()==24 and len(rows)==4
 next(a for a in SUB.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new,pool_egress_rows=rows);write('motel-install',installed);write('pool-egress-install',dict(status='saved_requires_capsule_and_real_character_egress_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),instances=24,rooms=rows,scope='Four private pools gain six16cm interior steps each, supported from the40cm basin floor and connected flush to the rim. Exterior stairs retained. Water remains NoCollision.'))

def motel_pool_mosaic():
 path=MOT+'/Materials/M_PoolMosaic';mat=EAL.load_asset(path) if EAL.does_asset_exist(path) else EAL.duplicate_asset('/Game/UniversityCity/RomancePBR/Materials/M_RomancePBR',path);assert mat
 if EAL.get_metadata_tag(mat,'MotelMosaicVersion')!='1':
  old=MEL.get_material_property_input_node(mat,unreal.MaterialProperty.MP_BASE_COLOR);oldout=MEL.get_material_property_input_node_output_name(mat,unreal.MaterialProperty.MP_BASE_COLOR);p=MEL.create_material_expression(mat,unreal.MaterialExpressionWorldPosition);n=MEL.create_material_expression(mat,unreal.MaterialExpressionVertexNormalWS)
  grid='float3 a=abs(N);float2 uv=(a.z>=a.x&&a.z>=a.y)?P.xy/5.0:(a.x>=a.y?P.yz/5.0:P.xz/5.0);float2 f=frac(uv);float2 d=min(f,1-f)*5.0;float edge=min(d.x,d.y);float aa=max(max(fwidth(uv.x),fwidth(uv.y))*5.0,.015);float tile=smoothstep(.065-aa,.14+aa,edge);'
  def custom(code,typ,withold=False):
   out=MEL.create_material_expression(mat,unreal.MaterialExpressionCustom);inputs=[]
   for name in ['P','N']+(['Old'] if withold else []):i=unreal.CustomInput();i.set_editor_property('input_name',name);inputs.append(i)
   out.set_editor_property('inputs',inputs);out.set_editor_property('output_type',typ);out.set_editor_property('code',code);assert MEL.connect_material_expressions(p,'',out,'P');assert MEL.connect_material_expressions(n,'',out,'N')
   if withold:assert MEL.connect_material_expressions(old,oldout,out,'Old')
   return out
  color=custom(grid+'float rnd=frac(sin(dot(floor(uv),float2(127.1,311.7)))*43758.5453);float detail=clamp(dot(Old,float3(.3,.59,.11))*2+.7,.7,1.2);float3 blue=lerp(float3(.035,.18,.34),float3(.075,.31,.52),rnd)*detail;return lerp(float3(.32,.39,.42),blue,tile);',unreal.CustomMaterialOutputType.CMOT_FLOAT3,True);rough=custom(grid+'return lerp(.74,.20,tile);',unreal.CustomMaterialOutputType.CMOT_FLOAT1);assert MEL.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR);assert MEL.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS);EAL.set_metadata_tag(mat,'MotelMosaicVersion','1');MEL.recompile_material(mat);assert EAL.save_loaded_asset(mat,False)
 errors=compile_errors(mat);assert not errors,errors;mi=EAL.load_asset(MOT+'/Materials/MI_PoolTile');assert mi;MEL.set_material_instance_parent(mi,mat);assert EAL.save_loaded_asset(mi,False);assert sha(MAPFILE)==LOAD_SHA;write('pool-mosaic',dict(status='asset_saved_requires_cooked_pixels',map_sha256=LOAD_SHA,parent=mat.get_path_name(),instance=mi.get_path_name(),tile_cm=5,source='Existing Grok2K handmade ceramic textures with5cm world-space tile layout,anti-aliased grout and per-tile blue variation;normal/ORM retained.'))

def motel_driveway_install():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert 'MotelV1_RoadConnection' not in actors;probe=read('driveway-probe');row=next(r for r in probe['rows'] if r['center_y']==77100);assert not row['car_clearance']['blocked'];world=unreal.EditorLevelLibrary.get_editor_world();p=unreal.Vector(36400,77750,1500);h=unreal.SystemLibrary.line_trace_single(world,p,p-unreal.Vector(0,0,400),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert h[0] and 1190<=h[4].z<=1210,('Pylon requires clear supported ground',num(h[4]) if h[0] else None);backup=OUT/('UniversityCity-before-motel-road-link-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);cube=EAL.load_asset('/Engine/BasicShapes/Cube');path=MOT+'/Materials/MI_DrivewayAsphalt';mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset('MI_DrivewayAsphalt',MOT+'/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());parent=EAL.load_asset('/Game/UniversityCity/GroundPBRV1/Natural/Materials/M_RomancePBR');assert parent;MEL.set_material_instance_parent(mi,parent)
 for kind,param in [('basecolor','RomanceBase'),('normal','RomanceNormal'),('orm','RomanceORM')]:
  tex=EAL.load_asset('/Game/UniversityCity/GroundPBRV1/Textures/T_asphalt_v2_'+kind);assert tex;MEL.set_material_instance_texture_parameter_value(mi,param,tex)
 for name,value in [('RomancePeriod',300.),('RomanceStrength',1.),('RomanceSeed',27.),('GroundRecolor',0.)]:MEL.set_material_instance_scalar_parameter_value(mi,name,value)
 for name,color in [('RomanceTintA',(.985,.985,.985)),('RomanceTintB',(1.015,1.015,1.015))]:MEL.set_material_instance_vector_parameter_value(mi,name,unreal.LinearColor(*color,1))
 assert EAL.save_loaded_asset(mi,False);a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(35550,77100,1200));a.set_actor_label('MotelV1_RoadConnection');a.tags=[unreal.Name('MotelV1')];a.set_folder_path('UniversityCity/MotelV1/Connections');a.static_mesh_component.set_static_mesh(cube);a.static_mesh_component.set_material(0,mi);a.static_mesh_component.set_collision_profile_name('BlockAll');a.set_actor_scale3d(unreal.Vector(29.,4.8,.12))
 im=next(r for r in read('imports')['assets'] if r['id']=='H1-road-sign');pylon=SUB.spawn_actor_from_class(unreal.StaticMeshActor,h[4]+unreal.Vector(0,0,.2),unreal.Rotator(yaw=270));pylon.set_actor_label('MotelV1_RoadsideEntranceSign');pylon.tags=[unreal.Name('MotelV1')];pylon.set_folder_path('UniversityCity/MotelV1/Connections');pylon.static_mesh_component.set_static_mesh(EAL.load_asset(im['asset']));pylon.static_mesh_component.set_collision_profile_name('BlockAll')
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new,road_connection=dict(start_cm=[34100,77100,1206],end_cm=[37000,77100,1206],width_cm=480));write('motel-install',installed);write('road-connection-install',dict(status='saved_requires_route_and_render_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),length_m=29,width_m=4.8,top_cm=1206,pylon_position=num(pylon.get_actor_location()),scope='Connect the existing ground ramp feeder to the street with a supported Grok1K asphalt driveway,avoiding existing tree trunks. Original street geometry/material bindings retained. Roadside dark illuminated Chinese entrance pylon faces the road with arrow toward the driveway.'))

def motel_place():
 plan=read('motel-plan');build={r['id']:r for r in read('suite-build')['rooms']};imports={r['id']:r for r in read('imports')['assets']};site=read('site-boundary-review');assert site['status']=='passed_building_bounds_only';actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert not any(k.startswith('MotelV1_Suite_') for k in actors)
 backup=OUT/('UniversityCity-before-motel-rebuild-'+LOAD_SHA[:16]+'.umap');shutil.copy2(MAPFILE,backup);old=[];bases={r['building']:r['base'] for r in site['sites']};preservation_before=ground_snapshot()
 for label,a in actors.items():
  relevant=label.startswith('City_H1_') or label.startswith('S18_F') or bool(re.search(r'(^RomanceArch_|^RomanceName_|^CityArt_.*_|^CityArtLight_|^ResortLantern_|^CitySign_.*_)(H1|S18)(_|$)',label))
  if not relevant:continue
  old.append(dict(actor=label,hidden=a.get_editor_property('hidden'),components=[dict(name=c.get_name(),visible=c.is_visible(),hidden=c.get_editor_property('hidden_in_game'),collision=str(c.get_collision_profile_name())) for c in a.get_components_by_class(unreal.StaticMeshComponent)]));a.modify();a.set_actor_hidden_in_game(True);a.set_is_temporarily_hidden_in_editor(True)
  for c in a.get_components_by_class(unreal.PrimitiveComponent):c.set_collision_profile_name('NoCollision');c.set_visibility(False,True);c.set_hidden_in_game(True,True)
 def spawn(label,asset,p,yaw=90,collision=True):
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(*p),unreal.Rotator(yaw=yaw));a.set_actor_label(label);a.tags=[unreal.Name('MotelV1')];a.set_folder_path('UniversityCity/MotelV1/Architecture');c=a.static_mesh_component;c.set_static_mesh(EAL.load_asset(asset));c.set_collision_profile_name('BlockAll' if collision else 'NoCollision');return a
 for bid in ['H1','S18']:
  base=list(bases[bid]);base[2]+=6;spawn('MotelV1_Architecture_'+bid,imports[bid+'-architecture']['asset'],base);spawn('MotelV1_Signs_'+bid,imports[bid+'-signs']['asset'],base,collision=False)
 cube=EAL.load_asset('/Engine/BasicShapes/Cube');silver=EAL.load_asset('/Game/UniversityCity/ImmersionV1/Mirrors/M_SilverMirror');roomrows=[]
 for q in plan['rooms']:
  b=build[q['id']];im=imports[q['id']];base=bases[q['building']];lc=q['local_center_m'];p=[base[0]+lc[1]*100,base[1]+lc[0]*100,base[2]+lc[2]*100+6];yaw=90-q['yaw'];a=spawn('MotelV1_Suite_'+q['id'],im['asset'],p,yaw);spawn('MotelV1_Water_'+q['id'],im['water_asset'],p,yaw,False)
  def world(v):
   t=math.radians(q['yaw']);x=v[0]*math.cos(t)-v[1]*math.sin(t);y=v[0]*math.sin(t)+v[1]*math.cos(t);return unreal.Vector(p[0]+y*100,p[1]+x*100,p[2]+v[2]*100)
  mirror=b['bathroom_mirror_local'];face=world(mirror['face']);front=world([mirror['face'][0],mirror['face'][1]-1,mirror['face'][2]]);n=(front-face)/100.;t=unreal.Vector(-n.y,n.x,0)
  glass=spawn('MotelV1_Mirror_'+q['id'],cube.get_path_name(),num(face),math.degrees(math.atan2(n.y,n.x)));glass.set_actor_scale3d(unreal.Vector(.012,mirror['width_m'],mirror['height_m']));glass.static_mesh_component.set_material(0,silver);glass.static_mesh_component.set_cast_shadow(False)
  r=SUB.spawn_actor_from_class(unreal.PlanarReflection,face+n*.9,unreal.MathLibrary.make_rotation_from_axes(t,unreal.Vector(0,0,1),n));r.set_actor_label('MotelV1_Planar_'+q['id']);r.tags=[unreal.Name('MotelV1'),unreal.Name('ImmersionLargeMirror')];r.set_folder_path('UniversityCity/MotelV1/Mirrors');r.set_actor_scale3d(unreal.Vector(mirror['width_m']/40,mirror['height_m']/40,1));c=r.get_components_by_class(unreal.PlanarReflectionComponent)[0]
  for key,value in dict(screen_percentage=75,normal_distortion_strength=0.,prefilter_roughness=0.,distance_from_plane_fadeout_start=5.,distance_from_plane_fadeout_end=15.,show_preview_plane=False,max_view_distance_override=6000.).items():c.set_editor_property(key,value)
  for c in r.get_components_by_class(unreal.StaticMeshComponent):c.set_visibility(False);c.set_hidden_in_game(True);c.set_collision_profile_name('NoCollision')
  for i,v in enumerate(b['lights_local']):
   l=SUB.spawn_actor_from_class(unreal.PointLight,world(v));l.set_actor_label('MotelV1_Light_'+q['id']+'_'+str(i));l.tags=[unreal.Name('MotelV1')];l.set_folder_path('UniversityCity/MotelV1/Lights');c=l.point_light_component;c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(5000 if i<2 else 3000);c.set_editor_property('attenuation_radius',650.);c.set_editor_property('cast_shadows',False);c.set_light_color(unreal.LinearColor(1.,.80,.61,1))
  roomrows.append(dict(id=q['id'],building=q['building'],source_name=q['source_name'],room_number=q['room_number'],floor=q['floor'],asset=im['asset'],position=p,yaw=yaw,eye=num(world(b['eye_local'])),target=num(world(b['target_local'])),bath_eye=num(world(b['bath_eye_local'])),mirror_face=num(face),mirror_normal=num(n),entry=num(world([q['size_m'][0]*.29,-q['size_m'][1]/2-.8,1.65]))))
 # Public reception WC also receives an actual planar mirror.
 base=bases['H1'];face=unreal.Vector(base[0]+1968,base[1]+630,base[2]+171);n=unreal.Vector(-1,0,0);glass=spawn('MotelV1_Reception_WC_Mirror',cube.get_path_name(),num(face),180);glass.set_actor_scale3d(unreal.Vector(.012,1.78,1.12));glass.static_mesh_component.set_material(0,silver);glass.static_mesh_component.set_cast_shadow(False);r=SUB.spawn_actor_from_class(unreal.PlanarReflection,face+n*.9,unreal.MathLibrary.make_rotation_from_axes(unreal.Vector(0,-1,0),unreal.Vector(0,0,1),n));r.set_actor_label('MotelV1_Reception_WC_Reflection');r.tags=[unreal.Name('MotelV1'),unreal.Name('ImmersionLargeMirror')];r.set_actor_scale3d(unreal.Vector(1.78/40,1.12/40,1));c=r.get_components_by_class(unreal.PlanarReflectionComponent)[0]
 for key,v in dict(screen_percentage=75,normal_distortion_strength=0.,prefilter_roughness=0.,show_preview_plane=False,max_view_distance_override=6000.).items():c.set_editor_property(key,v)
 for c in r.get_components_by_class(unreal.StaticMeshComponent):c.set_visibility(False);c.set_hidden_in_game(True);c.set_collision_profile_name('NoCollision')
 # Warm practical fill for reception, covered galleries, ramps and assigned bays.
 practical=[]
 for z in [0,5,9.6,14,18.3]:
  practical += [('H1',[x,0,z+3.3]) for x in range(-54,55,12)]
 for lo,hi in zip([0,5,9.6,14],[5,9.6,14,18.3]):
  for x in [-42,-14,14,42]:
   practical += [('H1',[x,34,lo+(54-x)/108*(hi-lo)/2+2.8]),('H1',[x,45,(lo+hi)/2+(x+54)/108*(hi-lo)/2+2.8])]
 practical += [('H1',[x,y,3.5]) for x in [-43,-20,3] for y in [1,11]]+[('H1',[6.3,16.6,3.0])]+[('S18',[x,-14,2.75]) for x in [-10,0,10]]
 for i,(bid,v) in enumerate(practical):
  b=bases[bid];p=unreal.Vector(b[0]+v[1]*100,b[1]+v[0]*100,b[2]+v[2]*100+6);l=SUB.spawn_actor_from_class(unreal.PointLight,p);l.set_actor_label('MotelV1_Practical_'+str(i));l.tags=[unreal.Name('MotelV1')];l.set_folder_path('UniversityCity/MotelV1/Lights');c=l.point_light_component;c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(2500);c.set_editor_property('attenuation_radius',1000.);c.set_editor_property('cast_shadows',False);c.set_light_color(unreal.LinearColor(1,.80,.62,1))
  # Supported bronze pole/arm on vehicle galleries; sheltered fittings elsewhere.
  parts=[('Head',p+unreal.Vector(0,0,15),[75,45,12],'M_Light')]
  if bid=='H1' and (v[1]==0 or v[1] in [34,45]):
   if v[1]==0:px=round((v[0]+60.8)/15.2)*15.2-60.8;py=3.65;hh=3.3
   else:px=v[0];py=31.2 if v[1]==34 else 47.8;hh=2.8
   post=unreal.Vector(b[0]+py*100,b[1]+px*100,p.z-hh*100);parts.append(('Pole',post+unreal.Vector(0,0,hh*50+10),[10,10,hh*100+20],'M_Gold'))
   # Arms follow local X/Y separately, avoiding an unattached diagonal light.
   corner=unreal.Vector(p.x,post.y,p.z+20);parts += [('CrossArm',(post+unreal.Vector(0,0,hh*100+20)+corner)/2,[abs(post.x-corner.x)+10,10,10],'M_Gold'),('LongArm',(corner+p+unreal.Vector(0,0,20))/2,[10,abs(corner.y-p.y)+10,10],'M_Gold')]
  else:
   mountheight=(3.0 if bid=='S18' else 4.85)-v[2];parts.append(('Suspension',p+unreal.Vector(0,0,max(20,mountheight*50)),[5,5,max(30,mountheight*100)],'M_Gold'))
  for suffix,center,size,key in parts:
   fixture=spawn('MotelV1_PracticalFixture_'+str(i)+'_'+suffix,cube.get_path_name(),num(center),0,suffix=='Pole');fixture.set_actor_scale3d(unreal.Vector(*[a/100 for a in size]));fixture.static_mesh_component.set_material(0,EAL.load_asset(MOT+'/Materials/'+key))
 # Serialize new captures inactive: Game's existing nearby-two policy activates them.
 # This also prevents an editor opening the map from rendering1,033 captures at once.
 for a in SUB.get_all_level_actors():
  if a.get_actor_label().startswith('MotelV1_'):
   for c in a.get_components_by_class(unreal.PlanarReflectionComponent):c.set_visibility(False)
 retired={r['actor'] for r in old};keep=lambda r:r['actor'] not in retired and not r['actor'].startswith('MotelV1_');before=[r for r in preservation_before if keep(r)];after=[r for r in ground_snapshot() if keep(r)];assert before==after,'Unrelated scene components changed';preservation_sha=hashlib.sha256(json.dumps(before,sort_keys=True).encode()).hexdigest()
 next(a for a in actors.values() if a.get_actor_label()=='CityEnvironmentController').prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();write('motel-install',dict(status='saved_requires_reopen_geometry_and_actual_game_review',before_map_sha256=LOAD_SHA,map_sha256=sha(MAPFILE),backup=str(backup),retained_original_actors=old,rooms=roomrows,room_count=len(roomrows),unrelated_preserved_components=len(before),unrelated_preservation_sha256=preservation_sha,scope='61 source-page variants rebuilt as original metric game suites;58 H1 and3 S18. Original hotels hidden with collision disabled, preserved for reversal. Mirrors and water kept separate. All new game/route/reflection checks outstanding.'))
]====]
