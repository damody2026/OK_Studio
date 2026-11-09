return [====[
MAPFILE=ROOT/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
LOAD_SHA=sha(MAPFILE)
ENV='/Game/UniversityCity/EnvironmentV1'
ENV_TAG='CityEnvironmentV1'
CULL_MATERIAL_ROWS=None

def latest_map_sha():
 return read('current-map')['map_sha256'] if (OUT/'current-map.json').is_file() else read('install')['map_sha256']

def preserved_component_row(actor,component,cache,expected):
 global CULL_MATERIAL_ROWS
 now=facing_preservation_row(actor,component,component_row(actor,component,cache))
 now=office_original_component_location(actor,component,now)
 if (OUT/'closed-floor-cull.json').is_file():
  if CULL_MATERIAL_ROWS is None:
   CULL_MATERIAL_ROWS={}
   for r in read('closed-floor-cull')['changes']:CULL_MATERIAL_ROWS.setdefault((r['actor'],r['component']),[]).append(r)
  for r in CULL_MATERIAL_ROWS.get((actor.get_actor_label(),component.get_name()),[]):
   mat=component.get_material(r['slot']);assert mat.get_path_name()==r['after'] and mat.get_editor_property('parent').get_path_name()==r['before'];props=mat.get_editor_property('base_property_overrides');assert props.get_editor_property('override_two_sided') and not props.get_editor_property('two_sided')
   for field in ['scalar_parameter_values','vector_parameter_values','texture_parameter_values']:assert not list(mat.get_editor_property(field)),('unexpected material parameter override',r['after'],field)
   # The authorized wrapper changes culling only. Material identity/role in
   # the preservation comparison is its verified, unmodified original parent.
   now['materials'][r['slot']]=r['before'];now['slots'][r['slot']]=expected['slots'][r['slot']]
 return now

def environment_cull_proven_floor_solids():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA and not (OUT/'closed-floor-cull.json').is_file()
 proof=read('closed-floor-proof');assert proof['status']=='passed' and proof['scene_sha256']==sha(OUT/'surface-export/scene.json');safe={r['source_asset']:r['safe_slots'] for r in proof['meshes']};source={i['key']:i for i in jread(OUT/'surface-export/scene.json')['instances']};original={m['after']:m['before'] for m in read('depth-install')['meshes']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};changes=[];materials={}
 for row in read('inventory-baseline')['actors']:
  if not row['building_floor']:continue
  a=actors[row['label']]
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   mesh=c.static_mesh.get_path_name();asset=original.get(mesh,mesh);ref=source[row['label']+'::'+c.get_name()]
   for slot in safe.get(asset,[]):
    if not ref['two_sided_by_slot'][slot] or ref['blend_modes'][slot]!=0:continue
    parent=c.get_material(slot);before=parent.get_path_name();assert before==ref['materials'][slot],('material edited',row['label'],slot)
    if before not in materials:
     name=parent.get_name()[:36]+'_Closed_'+hashlib.sha256(before.encode()).hexdigest()[:12];folder=ENV+'/DepthRepairs/MaterialsClosed';path=folder+'/'+name;mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset(name,folder,unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,parent);props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',props);MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);materials[before]=mi
    mi=materials[before];c.modify();c.set_material(slot,mi);changes.append(dict(actor=row['label'],component=c.get_name(),slot=slot,before=before,after=mi.get_path_name(),source_asset=asset))
 assert changes
 backup=OUT/'backups'/('UniversityCity-before-closed-solids-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('closed-floor-solids');write('closed-floor-cull',dict(status='passed',changes=changes,material_instances=len(materials),proof_sha256=sha(OUT/'closed-floor-proof.json'),map_sha256=sha(MAPFILE),backup=str(backup),scope='Only opaque slots wholly made of closed, outward solid shells in every original LOD. Thin/open surfaces and all other material parameters remain inherited from original parents.'));LOAD_SHA=sha(MAPFILE);write('cull_solids',dict(status='passed',map_sha256=LOAD_SHA,slots=len(changes)))
 folder=OUT/'surface-final';archive=OUT/'surface-final-before-floor-cull';assert folder.resolve().parent==OUT.resolve() and archive.resolve().parent==OUT.resolve() and not archive.exists();folder.rename(archive);environment_depth_export()

def environment_review_solid_scope():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA;receipt=read('closed-floor-cull');proof=read('closed-floor-proof');safe={r['source_asset']:set(r['safe_slots']) for r in proof['meshes']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};retained=[];restored=[]
 for r in receipt['changes']:
  a=actors[r['actor']];c=next(c for c in a.get_components_by_class(unreal.MeshComponent) if c.get_name()==r['component']);assert c.get_material(r['slot']).get_path_name()==r['after']
  if r['slot'] in safe.get(r['source_asset'],set()):retained.append(r)
  else:restored.append((c,r))
 backup=OUT/'backups'/('UniversityCity-before-solid-scope-review-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 for c,r in restored:c.modify();c.set_material(r['slot'],EAL.load_asset(r['before']))
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('solid-scope-review');write('closed-floor-cull-before-scope-review',receipt);receipt.update(changes=retained,proof_sha256=sha(OUT/'closed-floor-proof.json'),map_sha256=sha(MAPFILE),excluded_occupiable_hulls=[r for _,r in restored]);write('closed-floor-cull',receipt);LOAD_SHA=sha(MAPFILE);write('cull_review',dict(status='passed',retained_slots=len(retained),restored_slots=len(restored),map_sha256=LOAD_SHA));folder=OUT/'surface-final';archive=OUT/'surface-final-before-scope-review';assert folder.resolve().parent==OUT.resolve() and archive.resolve().parent==OUT.resolve() and not archive.exists();folder.rename(archive);environment_depth_export()

def environment_sport_schedule():
 assert latest_map_sha()==LOAD_SHA and not (OUT/'sports.json').is_file();receipt=read('install');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};mpc=EAL.load_asset(ENV+'/MPC_CityEnvironment');params=list(mpc.get_editor_property('scalar_parameters'))
 if not any(str(p.get_editor_property('parameter_name'))=='SportGlowWeight' for p in params):
  p=unreal.CollectionScalarParameter();p.set_editor_property('parameter_name','SportGlowWeight');p.set_editor_property('default_value',0.);params.append(p);mpc.set_editor_property('scalar_parameters',params);assert EAL.save_loaded_asset(mpc,False)
 path=ENV+'/Materials/M_EnvironmentSportOpal';material=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset('M_EnvironmentSportOpal',ENV+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
 if not EAL.get_metadata_tag(material,'SportProfile'):
  material.set_editor_property('two_sided',False);material.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
  def color(value):n=MEL.create_material_expression(material,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(*value,1));return n
  base=color((.8,.76,.68));glow=color((2.2,1.92,1.45));weight=MEL.create_material_expression(material,unreal.MaterialExpressionCollectionParameter);weight.set_editor_property('collection',mpc);weight.set_editor_property('parameter_name','SportGlowWeight');multiply=MEL.create_material_expression(material,unreal.MaterialExpressionMultiply);MEL.connect_material_expressions(glow,'',multiply,'A');MEL.connect_material_expressions(weight,'',multiply,'B');MEL.connect_material_property(base,'',unreal.MaterialProperty.MP_BASE_COLOR);MEL.connect_material_property(multiply,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR);EAL.set_metadata_tag(material,'SportProfile','NightWeight*SportSchedule; public path fixture remains separate')
 MEL.recompile_material(material);assert EAL.save_loaded_asset(material,False)
 for asset in read('plan')['materials'].values():
  m=EAL.load_asset(asset)
  if isinstance(m,unreal.Material):MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False)
 changes=[]
 for fixture in receipt['fixtures']:
  if fixture['id'] not in ['PK-0113','PK-0114','PK-0115'] or fixture['site']!=1:continue
  fixture['group']='Sport'
  for name in fixture['actors']:
   a=actors[name];a.modify();a.set_editor_property('tags',[('EnvGroup=Sport' if str(t)=='EnvGroup=Path' else str(t)) for t in a.tags])
   if name.endswith('_Opal'):
    c=a.static_mesh_component;before=c.get_material(0).get_path_name();c.modify();c.set_material(0,material);receipt['material_changes'].append(dict(actor=name,component=c.get_name(),material_before=before,material_after=material.get_path_name()))
   if name.endswith('_Light'):changes.append(dict(id=fixture['id'],actor=name,public_path_site=0,sport_site=1))
 assert len(changes)==3
 backup=OUT/'backups'/('UniversityCity-before-sport-schedule-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('sport-schedule');receipt['map_sha256']=sha(MAPFILE);write('install',receipt);write('sports',dict(status='passed',rows=changes,map_sha256=sha(MAPFILE),backup=str(backup),note='One independent Sport fixture per field closes at 23:00; its paired public Path fixture stays on. Emission and actual light share the Sport schedule. Fresh runtime validation required.'))

def record_map_save(operation):
 write('current-map',dict(status='saved',operation=operation,parent_map_sha256=LOAD_SHA,map_sha256=sha(MAPFILE),saved_at_utc=time.time()))

def quit_clean():
 global env_quit_handle,env_quit_frames
 assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry');unreal.SystemLibrary.collect_garbage();env_quit_frames=0
 def tick_quit(dt):
  global env_quit_frames
  env_quit_frames+=1
  if env_quit_frames>=120:unreal.unregister_slate_post_tick_callback(env_quit_handle);unreal.SystemLibrary.quit_editor()
 env_quit_handle=unreal.register_slate_post_tick_callback(tick_quit)

def environment_inventory():
 inventory();write('inventory-baseline',read('inventory'));world=unreal.EditorLevelLibrary.get_editor_world();export=OUT/'surface-export';export.mkdir(exist_ok=True)
 result=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(export),True));assert result['status']=='passed',result
 coverage=jread(ROOT/'openspec/changes/resort-day-night-cycle/coverage.json');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[];geometry=jread(export/'scene.json');parts={}
 for p in geometry['instances']:parts.setdefault(p['actor'],[]).append(p)
 for q in coverage['rows']:
  label=q.get('source_actor') or {'PK-0114':'Outdoor_stadium','PK-0115':'Outdoor_campus_track'}.get(q['id'],'World_'+q['id'].replace('-','_'));a=actors.get(label);assert a,('missing coverage actor',q['id'],label)
  if label in parts:
   lo=[min(p['min'][k] for p in parts[label]) for k in range(3)];hi=[max(p['max'][k] for p in parts[label]) for k in range(3)];center=[(lo[k]+hi[k])*.5 for k in range(3)];extent=[(hi[k]-lo[k])*.5 for k in range(3)];anchor=[center[0],center[1],lo[2]];basis='native individual static-mesh/ISM instance bounds'
  else:
   x,y,z=q['position_m'];anchor=[y*100,x*100,z*100];center=anchor;extent=[0,0,0];basis='hidden/replaced source;source anchor requires terrain and clearance validation'
  rows.append(dict(id=q['id'],name=q['name'],actor=label,center_cm=center,extent_cm=extent,native_anchor_cm=anchor,bounds_basis=basis,source_position_m=q['position_m'],xform=actor_xform(a)))
 lights=[]
 for a in actors.values():
  for c in a.get_components_by_class(unreal.LightComponent):
   props={}
   for k in ['intensity','intensity_units','attenuation_radius','temperature','use_temperature','cast_shadows','inner_cone_angle','outer_cone_angle','source_radius','source_length','light_color']:
    try:
     v=c.get_editor_property(k);props[k]=v if isinstance(v,(int,float,bool,str)) else str(v)
    except Exception:pass
   lights.append(dict(actor=a.get_actor_label(),component=c.get_name(),class_name=c.get_class().get_name(),properties=props,xform=actor_xform(a)))
 write('coverage-native',dict(status='passed',rows=rows,coverage_count=len(rows),lights=lights,map_sha256=sha(MAPFILE)))
 assert sha(MAPFILE)==LOAD_SHA,'Read-only inventory changed map'
 inv=read('inventory');inv.update(surface_export=result,coverage_count=len(rows));write('inventory',inv)

def jread(path):return json.loads(Path(path).read_text('utf-8-sig'))

def environment_assets():
 path=ENV+'/MPC_CityEnvironment';mpc=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset('MPC_CityEnvironment',ENV,unreal.MaterialParameterCollection,unreal.MaterialParameterCollectionFactoryNew());assert mpc
 if not mpc.get_editor_property('scalar_parameters'):
  scalars=[]
  for k,v in [('NightWeight',1),('DayWeight',0),('SignGlowWeight',1),('LampGlowWeight',1),('MoonPhase',180),('MoonIllumination',1)]:
   p=unreal.CollectionScalarParameter();p.set_editor_property('parameter_name',k);p.set_editor_property('default_value',v);scalars.append(p)
  vectors=[]
  for k,v in [('MoonDirection',(.57,.26,.77)),('SunDirection',(-.57,-.26,-.77)),('MoonBrightDirection',(-.57,-.26,-.77)),('SkyTop',(.015,.035,.09)),('SkyHorizon',(.10,.16,.27))]:
   p=unreal.CollectionVectorParameter();p.set_editor_property('parameter_name',k);p.set_editor_property('default_value',unreal.LinearColor(*v,1));vectors.append(p)
  mpc.set_editor_property('scalar_parameters',scalars);mpc.set_editor_property('vector_parameters',vectors);assert EAL.save_loaded_asset(mpc)
 def collection(m,k):
  n=MEL.create_material_expression(m,unreal.MaterialExpressionCollectionParameter);n.set_editor_property('collection',mpc);n.set_editor_property('parameter_name',k);return n
 def shader(name,inputs,code,blend=None,lit=False):
  dest=ENV+'/Materials/'+name
  if EAL.does_asset_exist(dest):return EAL.load_asset(dest)
  m=ATS.create_asset(name,ENV+'/Materials',unreal.Material,unreal.MaterialFactoryNew());m.set_editor_property('two_sided',True);m.set_editor_property('shading_model',unreal.MaterialShadingModel.MSM_DEFAULT_LIT if lit else unreal.MaterialShadingModel.MSM_UNLIT)
  if blend is not None:m.set_editor_property('blend_mode',blend)
  e=MEL.create_material_expression(m,unreal.MaterialExpressionCustom);defs=[];nodes=[]
  for k,typ in inputs:
   if typ=='primitive':
    n=MEL.create_material_expression(m,unreal.MaterialExpressionScalarParameter);n.set_editor_property('parameter_name','EnvironmentVisibility');n.set_editor_property('default_value',1.);n.set_editor_property('use_custom_primitive_data',True);n.set_editor_property('primitive_data_index',0)
   else:n=MEL.create_material_expression(m,unreal.MaterialExpressionPixelNormalWS if typ=='normal' else unreal.MaterialExpressionCameraVectorWS) if typ in ['normal','view'] else collection(m,typ)
   i=unreal.CustomInput();i.set_editor_property('input_name',k);defs.append(i);nodes.append((k,n))
  e.set_editor_property('inputs',defs);e.set_editor_property('output_type',unreal.CustomMaterialOutputType.CMOT_FLOAT3);e.set_editor_property('code',code)
  for k,n in nodes:assert MEL.connect_material_expressions(n,'',e,k)
  assert MEL.connect_material_property(e,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
  if lit:
   n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(.9,.72,.45,1));assert MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_BASE_COLOR)
   r=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);r.set_editor_property('r',.45);assert MEL.connect_material_property(r,'',unreal.MaterialProperty.MP_ROUGHNESS)
  if blend==unreal.BlendMode.BLEND_ADDITIVE:
   n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);n.set_editor_property('r',1);assert MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_OPACITY)
  assert not MEL.recompile_material(m),(name,'material compile failed');assert EAL.save_loaded_asset(m);return m
 source=(ROOT/'Tools/street_city_resort_night_payload.lua').read_text('utf8');lunar=re.search("if halo else '''(.*?)'''",source,re.S).group(1)
 lunar=lunar.replace('return float3(1.0,.96,.88)*','float phaseLight=smoothstep(-.025,.025,dot(normalize(N),normalize(S)));return lerp(.025,1.,phaseLight)*float3(1.0,.96,.88)*')
 lunar=lunar.replace('return lerp(.025,1.,phaseLight)*','return smoothstep(.056,1.,F)*lerp(.025,1.,phaseLight)*')
 moon=shader('M_EnvironmentMoon_04',[('N','normal'),('V','view'),('S','SunDirection'),('F','primitive')],lunar,unreal.BlendMode.BLEND_ADDITIVE)
 moon.set_editor_property('two_sided',False);assert not MEL.recompile_material(moon);assert EAL.save_loaded_asset(moon)
 halo=shader('M_EnvironmentHalo_02',[('N','normal'),('V','view'),('P','MoonIllumination'),('F','primitive')],'float f=saturate(dot(normalize(N),normalize(V)));float r=sqrt(saturate(1-f*f));return smoothstep(.056,1.,F)*float3(.30,.32,.38)*pow(saturate(1-r),2.6)*sqrt(saturate(P));',unreal.BlendMode.BLEND_ADDITIVE)
 sky=shader('M_EnvironmentSky_02',[('V','view'),('D','DayWeight'),('S','SunDirection'),('Top','SkyTop'),('Horizon','SkyHorizon')],'''float3 ray=normalize(-V);float h=pow(saturate(ray.z),.55);float facing=saturate(dot(ray,normalize(S)));float dusk=4*saturate(D)*(1-saturate(D));float3 horizon=lerp(Horizon,float3(.72,.28,.14),dusk*pow(facing,6)*.55);float3 color=lerp(horizon,Top,h)*exp2(12.6662*saturate(D));float sun=smoothstep(cos(radians(.32)),cos(radians(.26)),facing);color+=sun*float3(1,.92,.76)*90000.*D;color+=pow(facing,650)*float3(1,.65,.35)*120.*D;return color;''')
 opal=shader('M_EnvironmentOpal_01',[('G','LampGlowWeight')],'return float3(.95,.62,.28)*2.2*G;',lit=True)
 line=shader('M_EnvironmentLine_01',[('G','LampGlowWeight')],'return float3(1,.68,.36)*1.5*G;',lit=True)
 cube_path=ENV+'/T_NightAmbient'
 if not EAL.does_asset_exist(cube_path):
  assert unreal.CityDepthAuditLibrary.import_ambient_cube(str(OUT/'night-ambient.hdr'),ENV,'T_NightAmbient')
 cube=EAL.load_asset(cube_path);assert isinstance(cube,unreal.TextureCube),('Night ambient import must be TextureCube',cube);cube.set_editor_property('srgb',False);assert EAL.save_loaded_asset(cube)
 day_path=ENV+'/T_DayAmbient'
 if not EAL.does_asset_exist(day_path):assert unreal.CityDepthAuditLibrary.import_ambient_cube(str(OUT/'day-ambient.hdr'),ENV,'T_DayAmbient')
 day=EAL.load_asset(day_path);assert isinstance(day,unreal.TextureCube);day.set_editor_property('srgb',False);assert EAL.save_loaded_asset(day)
 write('plan',dict(status='passed',collection=mpc.get_path_name(),night_ambient_cubemap=cube.get_path_name(),day_ambient_cubemap=day.get_path_name(),materials={k:v.get_path_name() for k,v in [('moon',moon),('halo',halo),('sky',sky),('opal',opal),('line',line)]},note='Assets only;native world unchanged;phase and emissive parameters controlled by one runtime clock.'))

def sun_position_reference():
 from datetime import datetime,timedelta
 reference=read('ephemeris-reference-check');rows=[];rise=[]
 for q in reference['rows']:
  if q['body']!=10:continue
  t=datetime.fromisoformat(q['utc'])+timedelta(hours=8);p=unreal.CitySunPositionReference.get_sun_position(23.5,121.,8.,False,t.year,t.month,t.day,t.hour,t.minute,0)
  az=float(p.azimuth);alt=float(p.elevation)-180.;expected=q['actual_az_alt'];delta=abs((az-expected[0]+180)%360-180);a,b=map(math.radians,[alt,expected[1]]);angle=math.degrees(math.acos(max(-1,min(1,math.sin(a)*math.sin(b)+math.cos(a)*math.cos(b)*math.cos(math.radians(delta))))))
  rows.append(dict(utc=q['utc'],az_alt=[az,alt],reference_az_alt=expected,angular_error_degrees=angle,above_5_degrees=expected[1]>5))
 for q in reference['rise_set']:
  y,m,d=map(int,q['date'].split('-'));p=unreal.CitySunPositionReference.get_sun_position(23.5,121.,8.,False,y,m,d,12,0,0);r=unreal.MathLibrary.get_total_hours(p.sunrise_time);s=unreal.MathLibrary.get_total_hours(p.sunset_time);rise.append(dict(date=q['date'],sunrise_local_hours=r,sunset_local_hours=s,rise_error_minutes=abs(r-q['sunrise_local_hours'])*60,set_error_minutes=abs(s-q['sunset_local_hours'])*60))
 worst=max(q['angular_error_degrees'] for q in rows if q['above_5_degrees']);rise_error=max(max(q['rise_error_minutes'],q['set_error_minutes']) for q in rise)
 write('sun-position-reference',dict(status='passed' if worst<=.25 and rise_error<=5 else 'failed',rows=rows,rise_set=rise,max_angular_error_degrees=worst,max_rise_set_error_minutes=rise_error,note='Native Epic SunPosition airless Elevation minus its UE-specific 180 degree offset; corrected refraction field deliberately not mixed with airless reference.'))
 assert worst<=.25 and rise_error<=5,(worst,rise_error)

def environment_sites():
 import zipfile,array,ast
 with zipfile.ZipFile(ROOT/'output/street-social-city-production/world-ground-v1/world-field.npz') as archive:raw=archive.read('height_map.npy')
 start=10 if raw[6]==1 else 12;length=int.from_bytes(raw[8:start],'little');header=ast.literal_eval(raw[start:start+length].decode());assert header['descr']=='<f4' and header['shape']==(1101,1101);heights=array.array('f');heights.frombytes(raw[start+length:])
 world=unreal.EditorLevelLibrary.get_editor_world();scene=jread(OUT/'surface-export/scene.json');source=jread(ROOT/'openspec/changes/resort-day-night-cycle/coverage.json');by_actor={};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for p in scene['instances']:by_actor.setdefault(p['actor'],[]).append(p)
 rows=[]
 def ground(x,y,z):
  # Imported landmark bounding-box bottoms can be buried well below the
  # walking surface. Use the native terrain field only as a trace seed.
  seed=heights[max(0,min(1100,round(1100-x/100)))*1101+max(0,min(1100,round(y/100)))]*100
  h=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,seed+450),unreal.Vector(x,y,seed-300),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  v=h.to_tuple() if h else None
  if not v or not v[0]:return None
  a=v[9];label=a.get_actor_label() if a else '';normal=v[7]
  if normal.z<.85 or label.startswith(('Destination_','ResortFacade','ResortSign','ResortLantern','ResortBollard','CityArt_')):return None
  return dict(position_cm=[x,y,float(v[4].z)],support_actor=label,normal=num(normal))
 for q in source['rows']:
  aid=q['id'];label=q.get('source_actor') or {'PK-0114':'Outdoor_stadium','PK-0115':'Outdoor_campus_track'}.get(aid,'World_'+aid.replace('-','_'));parts=by_actor.get(label,[]);x,y,z=q['position_m'];anchor=[y*100,x*100,z*100]
  if parts:
   lo=[min(p['min'][k] for p in parts) for k in range(3)];hi=[max(p['max'][k] for p in parts) for k in range(3)];anchor=[(lo[0]+hi[0])*.5,(lo[1]+hi[1])*.5,lo[2]];ext=[(hi[k]-lo[k])*.5 for k in range(3)]
  else:ext=[350,350,50]
  group='Sport' if aid in ['PK-0113','PK-0114','PK-0115'] else 'Market' if aid=='PK-0118' else 'Camp' if aid in ['PK-0119','PK-0120','D023'] else 'Feature';sites=[];attempts=[]
  # Search only around this landmark. Verify real ground and a clear 2 m
  # pedestrian approach before reserving a fixture; bounds alone are insufficient.
  for side in [-1,1]:
   found=None
   offsets=[]
   for extra in [180,260,380,550,800]:
    for tangent in [0,-180,180,-360,360,-650,650]:offsets.append((side*(ext[0]+extra),tangent))
   for extra in [150,300,550]:
    for tangent in [0,-300,300,-650,650]:offsets.append((tangent,side*(ext[1]+extra)))
   for dx,dy in offsets:
     if found:break
     p=ground(anchor[0]+dx,anchor[1]+dy,anchor[2])
     if not p:continue
     if any(math.dist(p['position_cm'][:2],s['position_cm'][:2])<250 for s in sites):continue
     xyz=p['position_cm'];start=unreal.Vector(xyz[0],xyz[1]+125,xyz[2]+120);end=start+unreal.Vector(0,260,0)
     clear=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,start,end,100,110));attempts.append(dict(position_cm=xyz,blocked=clear['blocked'],blocking_actor=clear['actor']))
     if clear['blocked']:continue
     found=dict(**p,group=group,fixture='shielded-garden-lantern' if aid.startswith(('D','E')) else 'shielded-path-bollard',approach_start_cm=num(start),approach_end_cm=num(end));break
   if found:sites.append(found)
  rows.append(dict(id=aid,actor=label,anchor_cm=anchor,extent_cm=ext,sites=sites,attempts=attempts,status='located' if len(sites)==2 else 'needs_siting',camera=dict(eye=[anchor[0]-max(ext[0]+500,900),anchor[1]-max(ext[1]+650,1100),anchor[2]+180],target=[anchor[0],anchor[1],anchor[2]+120],fov=60)))
 assert sha(MAPFILE)==LOAD_SHA,'Read-only siting changed map'
 write('sites',dict(status='passed' if all(r['status']=='located' for r in rows) else 'needs_siting',rows=rows,located=sum(r['status']=='located' for r in rows),coverage_count=len(rows),map_sha256=LOAD_SHA,note='Ground traces and native 2m capsule approaches; no map save or fixtures installed.'))
 if MODE!='sites':write(MODE,dict(status='passed' if all(r['status']=='located' for r in rows) else 'needs_siting',located=sum(r['status']=='located' for r in rows),coverage_count=len(rows)))

def environment_fixtures(selected=None):
 sites=read('sites');assert sites['status']=='passed' and sites['coverage_count']==len(jread(ROOT/'openspec/changes/resort-day-night-cycle/coverage.json')['rows']),'Every landmark needs validated light sites before installation'
 assert sites['map_sha256']==LOAD_SHA,'Map changed since siting;repeat siting'
 assets=read('plan')['materials'];bronze=EAL.load_asset('/Game/UniversityCity/ResortArchitectureV1/NightLighting/M_LanternBronze')
 if not bronze:
  candidates=EAL.list_assets('/Game/UniversityCity/ResortArchitectureV1',True,False)
  bronze=next((EAL.load_asset(p) for p in candidates if 'Bronze' in p or 'bronze' in p),None)
 assert bronze,'Existing resort bronze material required'
 opal=EAL.load_asset(assets['opal']);line=EAL.load_asset(assets['line']);assert opal and line
 if selected is None:assert not any(ENV_TAG in [str(t) for t in a.tags] for a in SUB.get_all_level_actors()),'Existing environment install must be audited or restored first'
 rows=[]
 def spawn(cls,label,p,group):
  a=SUB.spawn_actor_from_class(cls,unreal.Vector(*p),unreal.Rotator());a.set_actor_label(label);a.set_folder_path('UniversityCity/EnvironmentV1');a.set_editor_property('tags',[ENV_TAG,'EnvGroup='+group]);return a
 def part(label,shape,p,size,m,group):
  a=spawn(unreal.StaticMeshActor,label,p,group);c=a.static_mesh_component;c.set_static_mesh(EAL.load_asset('/Engine/BasicShapes/'+shape+'.'+shape));c.set_material(0,m);c.set_collision_profile_name('NoCollision');c.set_editor_property('cast_shadow',False);a.set_actor_scale3d(unreal.Vector(*(v/100 for v in size)));return a
 for q in sites['rows']:
  if selected is not None and q['id'] not in selected:continue
  for i,s in enumerate(q['sites']):
   x,y,z=s['position_cm'];prefix='Environment_'+q['id'].replace('-','_')+'_'+str(i);group='Path';tall=s['fixture']=='shielded-garden-lantern';h=215 if tall else 85
   # Distinct solids meet at explicit joints; glowing insert is recessed and
   # separated from the opaque hood/rings. No coplanar ornamental overlays.
   made=[]
   for suffix,shape,p,size,m in [
    ('Foot','Cylinder',[x,y,z+4],[30,30,8],bronze),
    ('Stem','Cylinder',[x,y,z+8+(h-30)*.5],[9,9,h-30],bronze),
    ('LowerRing','Cylinder',[x,y,z+h-20],[30,30,4],bronze),
    ('Opal','Cylinder',[x,y,z+h-8],[24,24,18],opal),
    ('Hood','Cone',[x,y,z+h+10],[48,48,16],bronze)]:
    # Engine BasicShapes has no Cone on some builds; use a flattened sphere
    # for the gently domed resort hood, keeping it above the opal insert.
    if shape=='Cone':shape='Sphere';size=[48,48,12]
    a=part(prefix+'_'+suffix,shape,p,size,m,group);made.append(a.get_actor_label())
   a=spawn(unreal.SpotLight,prefix+'_Light',[x,y,z+h-12],group);a.set_actor_rotation(unreal.Rotator(pitch=-90,yaw=0,roll=0),False);c=a.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);lumens=380 if tall else 140;c.set_intensity(lumens);c.set_temperature(2800);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',1000 if tall else 650);c.set_editor_property('inner_cone_angle',55);c.set_editor_property('outer_cone_angle',80);c.set_editor_property('source_radius',12);c.set_editor_property('cast_shadows',False);a.set_editor_property('tags',[ENV_TAG,'EnvGroup=Path','EnvLumens='+str(lumens)]);made.append(a.get_actor_label())
   rows.append(dict(id=q['id'],site=i,position_cm=s['position_cm'],fixture=s['fixture'],actors=made,support_actor=s['support_actor'],approach_start_cm=s['approach_start_cm'],approach_end_cm=s['approach_end_cm'],lumens=lumens))
 write('fixtures-prepared',dict(status='prepared',rows=rows,fixture_count=len(rows),coverage_count=len(set(r['id'] for r in rows)),note='Prepared in memory; map is saved only after controller binding and preservation checks pass.'))
 return rows

def environment_routes():
 import zipfile,array,ast
 with zipfile.ZipFile(ROOT/'output/street-social-city-production/world-ground-v1/world-field.npz') as archive:raw=archive.read('height_map.npy')
 start=10 if raw[6]==1 else 12;length=int.from_bytes(raw[8:start],'little');heights=array.array('f');heights.frombytes(raw[start+length:]);assert len(heights)==1101*1101
 world=unreal.EditorLevelLibrary.get_editor_world();sites=read('sites');assert sites['map_sha256']==LOAD_SHA;anchors={r['id']:r['anchor_cm'] for r in sites['rows']};roads=jread(ROOT/'output/street-social-city-production/world-ground-v1/ground-plan.json')['roads'];groups={
 'bay-walk-beach-rest':['PK-0117','D010','D024'],'hotel-garden':['D002','D012','D021'],'campus-connections':['PK-0101','PK-0102','PK-0103','PK-0104'],
 'library-entry':['D004'],'dorm-garden':['D008'],'shopping-north-central-south':['D013','D014','D015','D016','D030'],'mall-plaza':['D026'],
 'office-civic-gardens':['D003','D019','D020','D022','D028'],'residential-garden':['D025'],'station-court-transit':['D017','D018'],
 'riverside-bridge-ramps':['PK-0107','D009','D011','D029'],'market-stage-exit':['PK-0118','PK-0112']}
 segments=[]
 for road in roads:
  points=[[110000-p[1]*100,p[0]*100] for p in road['points_map_m']]
  for n,(a,b) in enumerate(zip(points,points[1:])):
   length=math.dist(a,b)
   if length<1:continue
   segments.append(dict(road=road['id'],segment=n,a=a,b=b,width_cm=road['width_m']*100,kind=road['kind'],length=length))
 def project(p,s):
  a,b=s['a'],s['b'];v=[b[k]-a[k] for k in range(2)];t=max(0,min(1,sum((p[k]-a[k])*v[k] for k in range(2))/sum(x*x for x in v)));return math.dist(p[:2],[a[k]+t*v[k] for k in range(2)])
 selected={}
 for group,ids in groups.items():
  for aid in ids:
   ranked=sorted(segments,key=lambda s:project(anchors[aid],s))
   for s in ranked[:2]:selected.setdefault((s['road'],s['segment']),dict(**s,groups=set()))['groups'].add(group)
 rows=[]
 floor_labels={r['label'] for r in read('inventory-baseline')['actors'] if r['building_floor']};ignore_floors=[a for a in SUB.get_all_level_actors() if a.get_actor_label() in floor_labels]
 def ground(p):
  x,y=p;z=heights[max(0,min(1100,round(1100-x/100)))*1101+max(0,min(1100,round(y/100)))]*100
  h=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z+300),unreal.Vector(x,y,z-300),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=h.to_tuple() if h else None
  if not v or not v[0] or v[7].z<.8:
   # Raised block-ground surfaces can be >3m above the old heightfield.
   # Trace a wider terrain band, excluding building floors, then sweep the
   # actual world collision on every selected transition as before.
   h=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z+2500),unreal.Vector(x,y,z-1500),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignore_floors,unreal.DrawDebugTrace.NONE,True);v=h.to_tuple() if h else None
  if not v or not v[0] or v[7].z<.8:return None
  label=v[9].get_actor_label() if v[9] else ''
  if re.match(r'(?:S\d+_F|[A-Z]+\d*_F)',label):return None
  return [x,y,float(v[4].z)]
 for s in selected.values():
  a,b=s['a'],s['b'];n=max(1,math.ceil(s['length']/600));dx=(b[0]-a[0])/s['length'];dy=(b[1]-a[1])/s['length'];offset=s['width_cm']*.5+150 if s['kind']=='asphalt' else 0
  points=[];checks=[]
  for i in range(n+1):
   t=i/n;p=ground([a[0]+(b[0]-a[0])*t-dy*offset,a[1]+(b[1]-a[1])*t+dx*offset]);points.append(p)
  for p,q in zip(points,points[1:]):
   if p is None or q is None:checks.append(dict(blocked=True,reason='unsupported segment'));continue
   check=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(p[0],p[1],p[2]+120),unreal.Vector(q[0],q[1],q[2]+120),100,110));checks.append(check)
  detour=None
  if any(c['blocked'] for c in checks):
   # Search a narrow band along the actual road. Each transition is swept,
   # so a tree/bench detour never becomes an unchecked line through a wall.
   # Asphalt candidates stay on one sidewalk side for the entire segment.
   def solve(side):
    count=max(1,math.ceil(s['length']/300));layers=[]
    offsets=[side*(offset+v) for v in [0,120,240,360,500,750,1000,1500,2200]] if offset else [0,-120,120,-240,240,-360,360,-500,500,-750,750,-1000,1000,-1500,1500,-2200,2200]
    for i in range(count+1):
     t=i/count;layer={}
     for lateral in offsets:
      p=ground([a[0]+(b[0]-a[0])*t-dy*lateral,a[1]+(b[1]-a[1])*t+dx*lateral])
      if p is None:continue
      center=unreal.Vector(p[0],p[1],p[2]+120)
      if not i:
       c=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,center,center,100,110))
       if not c['blocked']:layer[lateral]=(abs(lateral-offset*side)*.01,p,None)
       continue
      for old,(cost,previous,_) in sorted(layers[-1].items(),key=lambda x:x[1][0]+abs(x[0]-lateral))[:4]:
       if abs(old-lateral)>750 or abs(previous[2]-p[2])>max(45,math.dist(previous[:2],p[:2])*.6):continue
       c=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(previous[0],previous[1],previous[2]+120),center,100,110))
       if c['blocked']:continue
       value=cost+math.dist(previous,p)+abs(lateral-offset*side)*.02
       if lateral not in layer or value<layer[lateral][0]:layer[lateral]=(value,p,old)
     if not layer:return None
     layers.append(layer)
    key=min(layers[-1],key=lambda k:layers[-1][k][0]);cost=layers[-1][key][0];chosen=[]
    for layer in reversed(layers):_,p,parent=layer[key];chosen.append(p);key=parent
    return dict(points_cm=list(reversed(chosen)),cost=cost,side=side,method='dynamic programming; native 2m capsule on every transition; max 22m public-ground adjustment; no unchecked height jumps')
   candidates=[r for r in [solve(1),solve(-1)] if r] if offset else [r for r in [solve(1)] if r]
   if candidates:
    detour=min(candidates,key=lambda r:r['cost']);verification=[]
    for p,q in zip(detour['points_cm'],detour['points_cm'][1:]):verification.append(json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(p[0],p[1],p[2]+120),unreal.Vector(q[0],q[1],q[2]+120),100,110)))
    assert not any(c['blocked'] for c in verification),'Selected detour failed independent replay';detour['verification']=verification
  rows.append(dict(road=s['road'],segment=s['segment'],groups=sorted(s['groups']),kind=s['kind'],source_width_cm=s['width_cm'],sidewalk_offset_cm=offset,points_cm=detour['points_cm'] if detour else points,original_checks=checks,checks=detour['verification'] if detour else checks,detour=detour,blocked_segments=0 if detour else sum(c['blocked'] for c in checks),status='clear' if detour or not any(c['blocked'] for c in checks) else 'requires_route_adjustment'))
 assert sha(MAPFILE)==LOAD_SHA
 write('routes',dict(status='passed' if all(r['status']=='clear' for r in rows) else 'requires_route_adjustment',groups=groups,rows=rows,map_sha256=LOAD_SHA,source='world-ground-v1/ground-plan.json existing route polylines; asphalt is sampled on its sidewalk side, never across buildings between landmarks',clear_segments=sum(not c['blocked'] for r in rows for c in r['checks']),blocked_segments=sum(c['blocked'] for r in rows for c in r['checks'])))

def environment_install():
 cls=unreal.load_class(None,'/Script/CityEnvironment.CityEnvironmentController');assert cls,'Runtime binary must be built and enabled first'
 tests=json.loads(unreal.get_default_object(cls).run_clock_self_tests());assert tests.get('passed') is True and tests.get('failed')==0,tests
 from datetime import datetime
 full=datetime.fromisoformat(read('ephemeris-reference-check')['full_moon_local']);initial_date=unreal.DateTime(full.year,full.month,full.day,21,0,0,0)
 baseline=read('inventory-baseline');assert baseline['map_sha256']==LOAD_SHA,'Map changed since baseline; reconcile before writing'
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert 'CityEnvironmentController' not in actors,'Use audit for an existing installation'
 backups=OUT/'backups';backups.mkdir(exist_ok=True);backup=backups/('UniversityCity-before-environment-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 protected=[r for r in baseline['actors'] if r['building_floor']];assert len(protected)==427
 fixtures=environment_fixtures();materials=read('plan')['materials'];changed=[];tag_changes=[]
 activity=jread(ROOT/'output/street-social-city-production/activity-scenes-v1/plan.json')['lights']
 for label,a in actors.items():
  before=[str(t) for t in a.tags];tags=list(before);role=None;group=None;lumens=None
  if label in ['CitySun','CityStreetFill','CitySkyLight','ResortMoonlight','ResortMoonBounce','ResortNightSky','ResortMoonDisc','ResortMoonHalo']:role=label
  if label.startswith('ResortLantern_') and label.endswith('Light'):role=label;group='Path';lumens=140 if label.endswith('BollardLight') else 1200
  if label in {'Destination_'+r['id']+'_Light' for r in jread(ROOT/'openspec/changes/resort-day-night-cycle/coverage.json')['rows'] if r['kind']=='landmark'}:role=label;group='Camp' if label in ['Destination_D023_Light','Destination_E033_Light'] else 'Market' if label=='Destination_E022_Light' else 'Feature';lumens=350 if label=='Destination_D021_Light' else 180
  if label.startswith('Activity_Light_'):
   index=int(label.rsplit('_',1)[1]);assert index<len(activity);scene=activity[index]['scene']
   # ACTSPACE-01 is the 8F indoor bear/photo room; preserve its lighting.
   if scene not in ['ACTSPACE-01','ACTSPACE-08','ACTSPACE-09']:role=label;group='Market' if scene in ['ACTSPACE-03','ACTSPACE-10'] else 'Feature';lumens=min(float(next(r['properties']['intensity'] for r in read('coverage-native')['lights'] if r['actor']==label)),900.)
  if role:tags.append('EnvRole='+role)
  if group:tags.append('EnvGroup='+group)
  if lumens is not None:tags.append('EnvLumens='+str(lumens))
  if tags!=before:a.modify();a.set_editor_property('tags',list(dict.fromkeys(tags)));tag_changes.append(dict(actor=label,before=before,after=[str(t) for t in a.tags]))
  if label.startswith('ResortLantern_') and label.endswith(('Opal','BollardOpal')):
   c=a.static_mesh_component;changed.append(dict(actor=label,component=c.get_name(),material_before=c.get_material(0).get_path_name(),material_after=materials['opal']));c.modify();c.set_material(0,EAL.load_asset(materials['opal']))
 for label,key in [('ResortNightSky','sky'),('ResortMoonDisc','moon'),('ResortMoonHalo','halo')]:
  a=actors[label];c=a.static_mesh_component;changed.append(dict(actor=label,component=c.get_name(),material_before=c.get_material(0).get_path_name(),material_after=materials[key],transform_before=actor_xform(a)));c.modify();c.set_material(0,EAL.load_asset(materials[key]))
 controller=SUB.spawn_actor_from_class(cls,unreal.Vector(55000,55000,0));controller.set_actor_label('CityEnvironmentController');controller.set_folder_path('UniversityCity/EnvironmentV1');controller.set_editor_property('tags',[ENV_TAG]);controller.set_editor_property('paused',True);controller.set_editor_property('minutes_per_day',60.);controller.initialize_bindings()
 from datetime import datetime
 controller.set_date_time(initial_date);controller.apply_environment();controller.save_clock();write('runtime-self-tests',tests)
 # Preserve every original floor mesh, material, transform and collision.
 cache={};checks=0
 for row in protected:
  a=actors.get(row['label']);assert a and actor_xform(a)==row['xform'],('floor transform changed',row['label'])
  now=[component_row(a,c,cache) for c in a.get_components_by_class(unreal.MeshComponent)];assert now==row['components'],('floor component changed',row['label']);checks+=1
 assert sha(MAPFILE)==LOAD_SHA,'Concurrent map save detected; refusing to overwrite'
 controller.prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level(),'Map save failed'
 record_map_save('install')
 write('install',dict(status='saved_requires_reopen_audit',backup=str(backup),before_sha256=LOAD_SHA,map_sha256=sha(MAPFILE),floor_preservation_checks=checks,controller=controller.get_path_name(),state=json.loads(controller.get_state_json()),fixtures=fixtures,material_changes=changed,tag_changes=tag_changes,source_inventory_run=baseline['run_id'],note='Requires fresh editor audit, HDR calibration, runtime cycle and depth review before acceptance.'))

def environment_audit():
 moon=EAL.load_asset(read('plan')['materials']['moon'])
 if moon.get_name()=='M_EnvironmentMoon_04':
  assert moon.get_editor_property('blend_mode')==unreal.BlendMode.BLEND_ADDITIVE and not moon.get_editor_property('two_sided'),'Moon fade must not occlude the sky or draw the rear hemisphere'
 if office_layout_data():environment_office_layout_audit()
 if (OUT/'visual_polish.json').is_file():environment_visual_polish_audit()
 if (OUT/'fixture-foot-spacing.json').is_file():environment_footing_preservation_audit()
 if (OUT/'prop-solid-cull.json').is_file():environment_prop_preservation_audit()
 environment_street_preservation_audit()
 receipt=read('install');depth=read('depth-install') if (OUT/'depth-install.json').is_file() else None;expected_sha=latest_map_sha();replacements={m['before']:m['after'] for m in depth['meshes']} if depth and depth['status']=='passed' else {};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors.get('CityEnvironmentController');assert controller,'Missing persisted runtime controller';assert sha(MAPFILE)==expected_sha,'Map changed since install'
 controller.initialize_bindings();controller.apply_environment();tests=json.loads(controller.run_clock_self_tests());assert tests.get('passed') is True and tests.get('failed')==0,tests;checks=0;cache={}
 for r in read('inventory-baseline')['actors']:
  if not r['building_floor']:continue
  a=actors.get(r['label']);assert a and actor_preservation_xform(a)==r['xform'];expected=[dict(c,mesh=replacements.get(c['mesh'],c['mesh'])) for c in r['components']];components=a.get_components_by_class(unreal.MeshComponent);assert len(components)==len(expected);assert [preserved_component_row(a,c,cache,e) for c,e in zip(components,expected)]==expected,r['label'];checks+=1
 coverage={}
 for r in receipt['fixtures']:
  for name in r['actors']:assert name in actors,('missing fixture part',name)
  coverage[r['id']]=coverage.get(r['id'],0)+1
 assert len(coverage)==len(jread(ROOT/'openspec/changes/resort-day-night-cycle/coverage.json')['rows']) and checks==427
 native_clock_checks(controller)
 original_time=controller.get_editor_property('local_date_time');states=[]
 for hour in range(25):controller.set_hour(float(hour));states.append(json.loads(controller.get_state_json()))
 controller.set_date_time(original_time);controller.apply_environment()
 write('audit',dict(status='passed',scope='Fresh-load content and clock audit; explicit office translations are checked separately, visual/depth/packaged acceptance remain separate',floor_preservation_checks=checks,authorized_office_floor_translations=6 if office_layout_data() else 0,absolute_floor_transforms_preserved=checks-(6 if office_layout_data() else 0),coverage=coverage,states=states,self_tests=tests,map_sha256=sha(MAPFILE)))

def native_clock_checks(controller):
 from datetime import datetime,timedelta
 original=json.loads(controller.get_state_json());reference=read('ephemeris-reference-check');rows=[]
 for q in reference['rows']:
  t=datetime.fromisoformat(q['utc'])+timedelta(hours=8);controller.set_date_time(unreal.DateTime(t.year,t.month,t.day,t.hour,t.minute,t.second,0));state=json.loads(controller.get_state_json());body=state['sun' if q['body']==10 else 'moon'];expected=q['apparent_normal_az_alt'];az=abs((body['azimuth']-expected[0]+180)%360-180);alt=abs(body['altitude']-expected[1]);assert state['valid'] and az<.0001 and alt<.0001,(q['utc'],q['body'],az,alt)
  if body['altitude']<=0:assert body['lux']==0
  rows.append(dict(utc=q['utc'],body=q['body'],az_error_degrees=az,alt_error_degrees=alt,direction=body['direction'],lux=body['lux']))
 # Exercise the real SaveGame API with different date, geography and scale,
 # then restore the previous clock. This is distinct from pure math tests.
 controller.set_editor_property('latitude',25.);controller.set_editor_property('north_yaw_degrees',35.);controller.set_date_time(unreal.DateTime(2028,2,29,23,58,59,0));controller.set_time_scale(2.);controller.set_paused(True);controller.save_clock();controller.set_editor_property('latitude',10.);controller.set_editor_property('north_yaw_degrees',0.);controller.set_date_time(unreal.DateTime(2027,1,1,0,0,0,0));controller.set_time_scale(1.);controller.load_clock();loaded=json.loads(controller.get_state_json());assert loaded['localDateTime']=='2028-02-29T23:58:59.000' and loaded['latitude']==25. and loaded['northYawDegrees']==35. and loaded['timeScale']==2. and loaded['paused'],loaded
 for key,prop in [('latitude','latitude'),('longitude','longitude'),('utcOffsetHours','utc_offset_hours'),('northYawDegrees','north_yaw_degrees'),('minutesPerDay','minutes_per_day')]:controller.set_editor_property(prop,original[key])
 t=datetime.fromisoformat(original['localDateTime']);controller.set_date_time(unreal.DateTime(t.year,t.month,t.day,t.hour,t.minute,t.second,t.microsecond//1000));controller.set_time_scale(original['timeScale']);controller.set_paused(original['paused']);controller.save_clock();controller.apply_environment()
 write('native-clock-checks',dict(status='passed',samples=len(rows),max_az_error_degrees=max(r['az_error_degrees'] for r in rows),max_alt_error_degrees=max(r['alt_error_degrees'] for r in rows),reference_sha256=sha(OUT/'ephemeris-reference-check.json'),real_save_load=dict(status='passed',loaded_state=loaded,restored_state=json.loads(controller.get_state_json())),rows=rows))

def environment_depth_export():
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];dynamic=[]
 for r in read('visual_polish')['signs']:
  c=next(q for q in actors[r['actor']].get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==r['component']);mat=c.get_material(r['slot']);base=EAL.load_asset(r['after'])
  if isinstance(mat,unreal.MaterialInstanceDynamic):
   assert mat.get_editor_property('parent')==base,('unexpected sign MID parent',r['actor']);checks={}
   for name in ['SignDepthU','SignDepthV','SignMetallic','SignLightMode','SignGlowStrength']:
    actual=mat.get_scalar_parameter_value(name);expected=MEL.get_material_instance_scalar_parameter_value(base,name);assert abs(actual-expected)<.000001,('runtime sign relief override',r['actor'],name,actual,expected);checks[name]=actual
   dynamic.append(dict(actor=r['actor'],dynamic=mat.get_path_name(),parent=base.get_path_name(),depth_and_mode_parameters=checks))
  else:assert mat==base,('unexpected sign source material',r['actor'])
 controller.prepare_for_save()
 folder=OUT/('surface-final' if (OUT/'depth-install.json').is_file() and read('depth-install').get('cross_slot') else 'surface-after');folder.mkdir(exist_ok=True);result=json.loads(unreal.CityDepthAuditLibrary.export_scene(unreal.EditorLevelLibrary.get_editor_world(),str(folder),True));assert result['status']=='passed';assert sha(MAPFILE)==LOAD_SHA;write('depth_export',dict(status='passed',geometry=result,folder=str(folder),map_sha256=LOAD_SHA,material_state='Serialized asset bindings after PrepareForSave; dynamic relief parameters checked before reset; main map not saved',dynamic_signs_checked=dynamic))

def environment_prepare():
 assert latest_map_sha()==LOAD_SHA
 materials={}
 for actor in SUB.get_all_level_actors():
  for component in actor.get_components_by_class(unreal.InstancedStaticMeshComponent):
   for material in component.get_materials():
    if not material:continue
    parent=material
    while isinstance(parent,unreal.MaterialInstance):parent=parent.get_editor_property('parent')
    if parent and parent.get_path_name().startswith('/Game/'):materials[parent.get_path_name()]=parent
 saved=[]
 for path,material in sorted(materials.items()):
  material.set_editor_property('used_with_instanced_static_meshes',True)
  assert unreal.EditorAssetLibrary.save_loaded_asset(material,False),path
  saved.append(path)
 result=json.loads(unreal.CityDepthAuditLibrary.preserve_repair_collision(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'depth-install.json')))
 assert result['status']=='passed',result
 write('collision-preservation',result)
 assert sha(MAPFILE)==LOAD_SHA
 write('prepare',dict(status='passed',instanced_materials=saved,collision_meshes=len(result['meshes']),map_sha256=LOAD_SHA))
 environment_depth_export()

def environment_spacing():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA and not (OUT/'spacing.json').is_file(),'Spacing is a guarded one-time change'
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};changes=[];sign_plan=read('sign-clearance-plan');assert sign_plan['source_scene_sha256']==sha(OUT/'surface-after/scene.json');signs={r['actor']:r for r in sign_plan['rows']}
 for label,r in signs.items():
  a=actors[label];assert a.static_mesh_component.static_mesh.get_path_name()==r['mesh'] and math.dist(actor_xform(a)['location'],r['location'])<.001,label
 for label,a in actors.items():
  if label.startswith('Street_tactile_'):
   for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
    assert str(c.get_collision_profile_name())=='NoCollision',label
    p=c.get_editor_property('relative_location');before=[p.x,p.y,p.z];after=[p.x,p.y,p.z+2.]
    c.modify();c.set_relative_location(unreal.Vector(*after),False,True);changes.append(dict(kind='component_location',actor=label,component=c.get_name(),before=before,after=after,reason='2cm physical separation from paving; render-only tactile strip'))
  elif label.startswith('ResortLantern_') and label.endswith('Opal'):
   c=a.static_mesh_component;assert str(c.get_collision_profile_name())=='NoCollision',label
   before=actor_xform(a);v=a.get_actor_scale3d();assert v.z>.02;after=[v.x,v.y,v.z-.01];a.modify();a.set_actor_scale3d(unreal.Vector(*after));changes.append(dict(kind='actor_scale',actor=label,before=before['scale'],after=after,reason='Shrink luminous insert 1cm overall; 5mm air gap at cap contact'))
  elif label.startswith('RomanceName_'):
   # Source face is 19cm in front of its board centre. The opaque frame
   # reaches 16cm. Add 2cm so the 2.8cm POM envelope has >=2.2cm clearance.
   direction=signs[label]['direction_world'];p=a.get_actor_location();before=[p.x,p.y,p.z];after=[before[k]+direction[k]*2 for k in range(3)];a.modify();a.set_actor_location(unreal.Vector(*after),False,True);changes.append(dict(kind='actor_location',actor=label,before=before,after=after,reason='2cm outward POM clearance; native geometric normal; artwork and relief preserved'))
 assert len([c for c in changes if c['actor'].startswith('RomanceName_')])==122
 backup=OUT/'backups'/('UniversityCity-before-spacing-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(MAPFILE)==LOAD_SHA
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('spacing');write('spacing',dict(status='passed',changes=changes,before_map_sha256=LOAD_SHA,map_sha256=sha(MAPFILE),backup=str(backup)));LOAD_SHA=sha(MAPFILE)
 environment_prepare()

def environment_cull_closed_street():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA and not (OUT/'closed-street-cull.json').is_file()
 scan=read('depth-final');assert scan['metadata_sha256']==sha(OUT/'surface-final/scene.json') and not scan['truncated'],'Complete matching scan required before changing or archiving its input'
 proof=read('closed-street-proof');assert proof['status']=='passed' and proof['source_scene_sha256']==sha(OUT/'surface-export/scene.json');allowed={r['source_asset'] for r in proof['meshes']};original={m['after']:m['before'] for m in read('depth-install')['meshes']};changes=[];materials={};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for label,a in actors.items():
  if not label.startswith(('Street_paving_','Street_curb_')):continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   path=c.static_mesh.get_path_name();assert original.get(path,path) in allowed,('unverified closed source',label,path)
   for index,mat in enumerate(c.get_materials()):
    before=mat.get_path_name()
    if before not in materials:
     name='MI_Closed_'+hashlib.sha256(before.encode()).hexdigest()[:20];asset=ENV+'/DepthRepairs/Materials/'+name;mi=EAL.load_asset(asset) if EAL.does_asset_exist(asset) else ATS.create_asset(name,ENV+'/DepthRepairs/Materials',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew());MEL.set_material_instance_parent(mi,mat);props=mi.get_editor_property('base_property_overrides');props.set_editor_property('override_two_sided',True);props.set_editor_property('two_sided',False);mi.set_editor_property('base_property_overrides',props);MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);materials[before]=mi
    mi=materials[before];c.modify();c.set_material(index,mi);changes.append(dict(actor=label,component=c.get_name(),slot=index,before=before,after=mi.get_path_name()))
 assert changes
 backup=OUT/'backups'/('UniversityCity-before-closed-cull-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(MAPFILE)==LOAD_SHA;actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('closed-street-cull');write('closed-street-cull',dict(status='passed',changes=changes,proof_sha256=sha(OUT/'closed-street-proof.json'),map_sha256=sha(MAPFILE),backup=str(backup),method='Outward faces only on proven watertight opaque paving/curb solids. Their touching internal faces cannot render together. Collision and original materials remain unchanged.'))
 folder=OUT/'surface-final';archive=OUT/'surface-final-before-cull';assert folder.resolve().parent==OUT.resolve() and archive.resolve().parent==OUT.resolve() and not archive.exists();folder.rename(archive)
 LOAD_SHA=sha(MAPFILE);environment_depth_export();write('cull',dict(status='passed',map_sha256=LOAD_SHA))

def environment_refine():
 receipt=read('install');assert latest_map_sha()==LOAD_SHA,'Reconcile concurrent map changes before refining';actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore();base_tags={r['actor']:r['before'] for r in receipt['tag_changes']};activity=jread(ROOT/'output/street-social-city-production/activity-scenes-v1/plan.json')['lights'];source_lights={r['actor']:r for r in read('coverage-native')['lights']};coverage=jread(ROOT/'openspec/changes/resort-day-night-cycle/coverage.json')['rows'];landmark_labels={'Destination_'+r['id']+'_Light' for r in coverage if r['kind']=='landmark'};changes=[];indoor_checks=[]
 for label,a in actors.items():
  if label.startswith('Environment_') or label=='CityEnvironmentController':continue
  current=[str(t) for t in a.tags];before=base_tags.get(label,current);tags=list(before);role=None;group=None;lumens=None
  if label in ['CitySun','CityStreetFill','CitySkyLight','ResortMoonlight','ResortMoonBounce','ResortNightSky','ResortMoonDisc','ResortMoonHalo']:role=label
  if label.startswith('ResortLantern_') and label.endswith('Light'):role=label;group='Path';lumens=140 if label.endswith('BollardLight') else 1200
  if label in landmark_labels:role=label;group='Camp' if label in ['Destination_D023_Light','Destination_E033_Light'] else 'Market' if label=='Destination_E022_Light' else 'Feature';lumens=float(source_lights[label]['properties']['intensity'])
  if label.startswith('Activity_Light_'):
   index=int(label.rsplit('_',1)[1]);scene=activity[index]['scene']
   if scene in ['ACTSPACE-01','ACTSPACE-08','ACTSPACE-09']:
    tags.append('EnvIndoor');c=a.light_component;props=source_lights[label]['properties']
    for key,value in props.items():
     if isinstance(value,(int,float,bool)):c.set_editor_property(key,value)
     elif key=='light_color':
      color={k:int(v) for k,v in re.findall(r'([rgba]):\s*(\d+)',value)};assert len(color)==4;c.set_editor_property(key,unreal.Color(**color))
     elif key=='intensity_units':
      match=re.search(r'LightUnits\.(\w+)',value);assert match;c.set_editor_property(key,getattr(unreal.LightUnits,match.group(1)))
    assert abs(c.intensity-props['intensity'])<.001;indoor_checks.append(dict(actor=label,scene=scene,intensity=c.intensity))
   else:role=label;group='Market' if scene in ['ACTSPACE-03','ACTSPACE-10'] else 'Feature';lumens=min(float(source_lights[label]['properties']['intensity']),900.)
  if role:tags.append('EnvRole='+role)
  if group:tags.append('EnvGroup='+group)
  if lumens is not None:tags.append('EnvLumens='+str(lumens))
  if tags!=current:a.modify();a.set_editor_property('tags',list(dict.fromkeys(tags)))
  if tags!=before or label in base_tags:changes.append(dict(actor=label,before=before,after=[str(t) for t in a.tags]))
 covered={r['id'] for r in receipt['fixtures']};missing={r['id'] for r in coverage}-covered;fixtures=environment_fixtures(missing) if missing else []
 backup=OUT/'backups'/('UniversityCity-before-environment-refine-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 controller.initialize_bindings();from datetime import datetime
 full=datetime.fromisoformat(read('ephemeris-reference-check')['full_moon_local']);controller.set_date_time(unreal.DateTime(full.year,full.month,full.day,21,0,0,0));controller.save_clock();controller.apply_environment()
 for r in indoor_checks:assert abs(actors[r['actor']].light_component.intensity-r['intensity'])<.001,('Indoor light was re-managed',r['actor'])
 assert len(covered|missing)==len(coverage) and len(indoor_checks)==39;assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level()
 record_map_save('refine');receipt.update(map_sha256=sha(MAPFILE),fixtures=receipt['fixtures']+fixtures,tag_changes=changes,state=json.loads(controller.get_state_json()),refinement_backup=str(backup),indoor_preservation_checks=indoor_checks,coverage_count=len(coverage));write('install',receipt);write('refine',dict(status='passed',map_sha256=sha(MAPFILE),coverage_count=len(coverage),added_fixture_count=len(fixtures),indoor_light_preservation_checks=len(indoor_checks)))

def environment_moon_refine():
 global LOAD_SHA
 assert latest_map_sha()==LOAD_SHA
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore();plan=read('plan');receipt=read('install');component=actors['ResortMoonDisc'].static_mesh_component;source=component.get_material(0)
 assert source.get_path_name()==plan['materials']['moon'] and source.get_editor_property('blend_mode') in [unreal.BlendMode.BLEND_OPAQUE,unreal.BlendMode.BLEND_ADDITIVE]
 backup=OUT/'backups'/('UniversityCity-before-moon-fade-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 dest=ENV+'/Materials/M_EnvironmentMoon_04';assert not EAL.does_asset_exist(dest),'Review existing moon migration before rerunning'
 moon=EAL.duplicate_asset(source.get_path_name(),dest);assert moon
 moon.set_editor_property('blend_mode',unreal.BlendMode.BLEND_ADDITIVE)
 moon.set_editor_property('two_sided',False)
 one=MEL.create_material_expression(moon,unreal.MaterialExpressionConstant);one.set_editor_property('r',1.);assert MEL.connect_material_property(one,'',unreal.MaterialProperty.MP_OPACITY)
 assert not MEL.recompile_material(moon);assert EAL.save_loaded_asset(moon)
 component.modify();component.set_material(0,moon);plan['materials']['moon']=moon.get_path_name();write('plan',plan)
 changes=[r for r in receipt['material_changes'] if r['actor']=='ResortMoonDisc'];assert len(changes)==1;changes[0]['material_after']=moon.get_path_name()
 controller.initialize_bindings();controller.set_hour(21.);controller.apply_environment();controller.prepare_for_save();assert sha(MAPFILE)==LOAD_SHA;assert unreal.EditorLevelLibrary.save_current_level();record_map_save('moon_refine');LOAD_SHA=sha(MAPFILE);receipt.update(map_sha256=LOAD_SHA);write('install',receipt)
 write('moon_refine',dict(status='passed',before=source.get_path_name(),after=moon.get_path_name(),backup=str(backup),map_sha256=LOAD_SHA,reason='Front-face-only additive lunar sphere prevents black twilight sky occlusion and duplicate back-hemisphere phase/emission. Existing crater/phase/visibility shader and night illuminance retained; native twilight visual verification required.'))
 environment_audit()

def environment_lookdev():
 receipt=read('install');assert latest_map_sha()==LOAD_SHA;actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.deactivate_and_restore();plan=read('plan');backup=OUT/'backups'/('UniversityCity-before-night-fill-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 controller.set_editor_property('day_ambient_cubemap',EAL.load_asset(plan['day_ambient_cubemap']));controller.set_editor_property('night_ambient_cubemap',EAL.load_asset(plan['night_ambient_cubemap']))
 for label,key in [('ResortNightSky','sky'),('ResortMoonDisc','moon'),('ResortMoonHalo','halo')]:
  a=actors[label];a.modify();a.static_mesh_component.modify();a.static_mesh_component.set_material(0,EAL.load_asset(plan['materials'][key]))
  for r in receipt['material_changes']:
   if r['actor']==label:r['material_after']=plan['materials'][key]
 controller.initialize_bindings();controller.set_hour(21.);controller.apply_environment();controller.save_clock();assert sha(MAPFILE)==LOAD_SHA;controller.prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();record_map_save('lookdev');receipt.update(map_sha256=sha(MAPFILE),night_ambient_cubemap=plan['night_ambient_cubemap'],lookdev_backup=str(backup),state=json.loads(controller.get_state_json()));write('install',receipt);write('lookdev',dict(status='passed',map_sha256=sha(MAPFILE),night_ambient_cubemap=plan['night_ambient_cubemap'],note='Native HDR and visual calibration must be repeated for the new ambient.'))

def environment_depth_apply():
 installed=read('install');assert latest_map_sha()==LOAD_SHA,'Depth repair must start from the reviewed environment install'
 request=read('depth-request') if (OUT/'depth-request.json').is_file() else dict(plan='surface-union-plan.json',export='surface-export')
 assert request['plan'] in ['surface-union-plan.json','surface-union-plan-v2.json'] and request['export'] in ['surface-export','surface-after']
 path=OUT/request['plan'];plan=jread(path);assert plan['scene_sha256']==sha(OUT/request['export']/'scene.json'),'Union plan source export changed'
 world=unreal.EditorLevelLibrary.get_editor_world();pre=OUT/'surface-preapply';pre.mkdir(exist_ok=True);result=json.loads(unreal.CityDepthAuditLibrary.export_scene(world,str(pre),True));assert result['status']=='passed';fresh={m['asset']:m for m in jread(pre/'scene.json')['meshes']};source_checks=0
 # Re-export the live source descriptions and compare complete binary hashes,
 # not only paths or triangle counts, before applying the offline clipping.
 for m in plan['meshes']:
  assert m['source_asset'] in fresh,('source missing',m['source_asset']);lods={l['lod']:l for l in fresh[m['source_asset']]['lods']}
  for lod in m['lods']:assert lod['lod'] in lods and sha(pre/lods[lod['lod']]['file'])==lod['source_sha256'],('source geometry changed',m['source_asset'],lod['lod']);source_checks+=1
 backup=OUT/'backups'/('UniversityCity-before-depth-union-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 repaired=json.loads(unreal.CityDepthAuditLibrary.apply_surface_union(world,str(path)));assert repaired['status']=='passed',repaired
 previous=read('depth-install') if (OUT/'depth-install.json').is_file() else None
 if previous:
  write('depth-install-before-'+PAYLOAD['run_id'],previous);old_by_after={m['after']:m for m in previous['meshes']};combined={m['before']:m for m in previous['meshes']}
  for m in repaired['meshes']:
   m['source_before_this_pass']=m['before'];m['before']=old_by_after[m['before']]['before'] if m['before'] in old_by_after else m['before'];combined[m['before']]=m
  repaired['meshes']=list(combined.values())
 replacements={m['before']:m['after'] for m in repaired['meshes']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};cache={};checks=0
 for r in read('inventory-baseline')['actors']:
  if not r['building_floor']:continue
  a=actors[r['label']];assert actor_preservation_xform(a)==r['xform'];expected=[dict(c,mesh=replacements.get(c['mesh'],c['mesh'])) for c in r['components']];assert [component_row(a,c,cache) for c in a.get_components_by_class(unreal.MeshComponent)]==expected,('non-mesh floor data changed',r['label']);checks+=1
 assert checks==427 and sha(MAPFILE)==LOAD_SHA,'Preservation or concurrent-save guard failed';actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level()
 record_map_save('depth');repaired.update(status='passed',before_map_sha256=LOAD_SHA,map_sha256=sha(MAPFILE),backup=str(backup),source_lod_hash_checks=source_checks,floor_preservation_checks=checks,plan_sha256=sha(path),method=plan['method'],cross_slot=plan.get('cross_slot',False),note='Original-material planar union; baseline-to-current ledger flattened across passes. Native residual and motion QA required.');write('depth-install',repaired);write('depth',dict(status='passed',map_sha256=sha(MAPFILE),mesh_count=len(repaired['meshes']),source_lod_hash_checks=source_checks))

def environment_guard_test():
 global read
 original_read=read;before_count=len(SUB.get_all_level_actors());caught=False
 def stale(name):
  value=original_read(name)
  if name=='inventory-baseline':value=dict(value,map_sha256='0'*64)
  return value
 try:
  read=stale
  try:environment_install()
  except AssertionError as e:caught='Map changed since baseline' in str(e)
 finally:read=original_read
 assert caught and sha(MAPFILE)==LOAD_SHA and len(SUB.get_all_level_actors())==before_count,'Stale-save guard was not cleanly rejected'
 write('guard',dict(status='passed',stale_baseline_rejected=True,no_actor_mutation=True,map_sha256=LOAD_SHA))

def environment_restore(config_override=None):
 request=read('restore-request') if (OUT/'restore-request.json').is_file() else {};apply=bool(request.get('apply',False));geometry=bool(request.get('geometry',False));receipt=read('install');actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors.get('CityEnvironmentController');assert controller,'No environment controller to restore';controller.deactivate_and_restore();known={name for r in receipt['fixtures'] for name in r['actors']}|{'CityEnvironmentController'};conflicts=[];actions=[]
 for name in known:
  a=actors.get(name)
  if not a or ENV_TAG not in [str(t) for t in a.tags]:conflicts.append(dict(actor=name,reason='missing or ownership tag changed'))
  else:actions.append(dict(action='remove_owned_fixture_or_controller',actor=name))
 for label,a in actors.items():
  if ENV_TAG in [str(t) for t in a.tags] and label not in known:conflicts.append(dict(actor=label,reason='unknown actor carrying environment tag; preserve and reconcile'))
 material_targets=[]
 for r in receipt['material_changes']:
  a=actors.get(r['actor']);c=next((c for c in a.get_components_by_class(unreal.MeshComponent) if c.get_name()==r['component']),None) if a else None
  if not c or not c.get_material(0) or c.get_material(0).get_path_name()!=r['material_after']:conflicts.append(dict(actor=r['actor'],reason='controlled material was edited after install'));continue
  material_targets.append((a,c,r));actions.append(dict(action='restore_controlled_material',actor=r['actor'],before=r['material_after'],after=r['material_before']))
 mesh_targets=[];spacing_targets=[];cull_targets=[];restore_faces={(r['actor'],r['component']):r for r in read('facing-install')['components']} if geometry and (OUT/'facing-install.json').is_file() else {}
 if geometry and (OUT/'depth-install.json').is_file():
  for m in read('depth-install')['meshes']:
   for key in m['component_keys']:
    label,name=key.split('::',1);a=actors.get(label);c=next((c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==name),None) if a else None
    if not c or c.static_mesh.get_path_name()!=m['after']:conflicts.append(dict(actor=label,reason='repaired mesh was edited after install'));continue
    face=restore_faces.get((label,name))
    if face and (c.get_num_materials()!=face['original_slot_count']+len(face['added_slots']) or any(not c.get_material(r['added_slot']) or c.get_material(r['added_slot']).get_path_name()!=r['material_after'] for r in face['added_slots'])):conflicts.append(dict(actor=label,reason='owned front-only slots or trailing material slots were changed'));continue
    mesh_targets.append((c,m['before'],face));actions.append(dict(action='restore_original_mesh',component=key,before=m['after'],after=m['before']))
 spacing_changes=read('spacing')['changes'] if geometry and (OUT/'spacing.json').is_file() else []
 if geometry and (OUT/'fixture-foot-spacing.json').is_file():spacing_changes=spacing_changes+[r for r in read('fixture-foot-spacing')['changes'] if r['actor'] not in known]
 if geometry and (OUT/'water-depth-install.json').is_file():
  w=read('water-depth-install');spacing_changes=spacing_changes+[dict(actor=w['actor'],kind='actor_location',before=w['before']['location'],after=w['after']['location'])]
 if geometry:
  for r in spacing_changes:
   a=actors.get(r['actor']);c=next((c for c in a.get_components_by_class(unreal.SceneComponent) if c.get_name()==r.get('component')),None) if a and r['kind']=='component_location' else None
   office=office_layout_actor_row(a) if a else None
   if office and r['kind']=='actor_location':
    assert math.dist(num(a.get_actor_location()),office['after']['location'])<.001,('office restore location changed',r['actor'])
    r=dict(r,before=[r['before'][k]+office['delta_cm'][k] for k in range(3)],after=[r['after'][k]+office['delta_cm'][k] for k in range(3)])
   value=c.get_editor_property('relative_location') if c else a.get_actor_location() if a and r['kind']=='actor_location' else a.get_actor_scale3d() if a else None
   if value is None or math.dist([value.x,value.y,value.z],r['after'])>.001:conflicts.append(dict(actor=r['actor'],reason='spacing target was edited after install'));continue
   spacing_targets.append((a,c,r));actions.append(dict(action='restore_original_spacing',actor=r['actor'],kind=r['kind']))
 for ledger in ['closed-street-cull','closed-floor-cull','prop-solid-cull'] if geometry else []:
  if not (OUT/(ledger+'.json')).is_file():continue
  for r in read(ledger)['changes']:
   a=actors.get(r['actor']);c=next((c for c in a.get_components_by_class(unreal.MeshComponent) if c.get_name()==r['component']),None) if a else None
   if not c or c.get_material(r['slot']).get_path_name()!=r['after']:conflicts.append(dict(actor=r['actor'],reason='closed-solid material was edited after install'));continue
   cull_targets.append((c,r));actions.append(dict(action='restore_original_closed_solid_material',actor=r['actor'],slot=r['slot']))
 street_original=[];street_replacement=[]
 if geometry:
  for batch in ['street','tactile']:
   if not (OUT/(batch+'-surface-install.json')).is_file():continue
   try:original,replacement=street_saved_targets(actors,batch);street_original+=original;street_replacement+=replacement
   except (AssertionError,KeyError,StopIteration) as error:conflicts.append(dict(reason=batch+' restoration target changed',details=str(error)))
  for c,before in street_original:actions.append(dict(action='restore_original_street_visibility',actor=before['actor'],component=before['component']))
  for a in street_replacement:actions.append(dict(action='remove_owned_street_render_chunk',actor=a.get_actor_label()))
 # Revert only recorded rendering keys. Unrelated config/map changes survive.
 config=Path(config_override) if config_override else ROOT/'StreetSocialCity/Config/DefaultEngine.ini';config_sha=sha(config);config_bytes=config.read_bytes();config_bom=b'\xef\xbb\xbf' if config_bytes.startswith(b'\xef\xbb\xbf') else b'';text=config_bytes.decode('utf-8-sig');migration=read('config-migration');section=False;seen={};lines=text.splitlines(keepends=True);updated=[]
 for line in lines:
  if line.strip().startswith('['):section=line.strip()=='[/Script/Engine.RendererSettings]'
  match=re.match(r'([^=]+)=(.*)',line.strip()) if section else None;key=match.group(1) if match else None
  if key in migration['after']:
   seen[key]=seen.get(key,0)+1
   if match.group(2).strip()!=migration['after'][key]:conflicts.append(dict(config_key=key,reason='controlled rendering key changed'))
   old=migration['before'][key]
   if old is not None:updated.append(key+'='+old+('\r\n' if line.endswith('\r\n') else '\n' if line.endswith('\n') else ''))
  else:updated.append(line)
 for key in migration['after']:
  if seen.get(key)!=1:conflicts.append(dict(config_key=key,reason='missing or duplicate rendering key'))
 if conflicts:write('restore',dict(status='conflict_requires_reconcile',applied=False,conflicts=conflicts,map_sha256=LOAD_SHA));assert not apply,'Restore has conflicting targets';return
 if not apply:
  assert sha(MAPFILE)==LOAD_SHA;write('restore',dict(status='passed',applied=False,dry_run=True,geometry=geometry,actions=actions,controlled_tag_rows=len(receipt['tag_changes']),unrelated_actor_count=len(actors)-len(known),map_sha256=LOAD_SHA,note='Targeted dry run; does not overwrite the map with a backup. Actual application requires an explicit restore request.'));return
 backup=OUT/'backups'/('UniversityCity-before-targeted-restore-'+PAYLOAD['run_id']+'.umap');shutil.copy2(MAPFILE,backup);assert sha(backup)==LOAD_SHA
 for a,c,r in material_targets:
  c.modify();c.set_material(0,EAL.load_asset(r['material_before']))
  if 'transform_before' in r:
   t=r['transform_before'];a.set_actor_location(unreal.Vector(*t['location']),False,True);a.set_actor_rotation(unreal.Rotator(pitch=t['rotation'][0],yaw=t['rotation'][1],roll=t['rotation'][2]),False);a.set_actor_scale3d(unreal.Vector(*t['scale']));c.set_visibility(True,True);a.set_actor_hidden_in_game(False);a.set_is_temporarily_hidden_in_editor(False)
 for c,path,face in mesh_targets:
  overrides=list(c.get_editor_property('override_materials'));c.modify();c.set_static_mesh(EAL.load_asset(path))
  # Remove only our appended material slots; retain unrelated base-slot edits.
  if face:c.set_editor_property('override_materials',overrides[:face['original_slot_count']])
 for c,before in street_original:c.modify();c.set_visibility(before['visible'],False);c.set_hidden_in_game(before['hidden_in_game'],False)
 for a in street_replacement:assert SUB.destroy_actor(a)

 for a,c,r in spacing_targets:
  if r['kind']=='component_location':c.modify();c.set_relative_location(unreal.Vector(*r['before']),False,True)
  elif r['kind']=='actor_location':a.modify();a.set_actor_location(unreal.Vector(*r['before']),False,True)
  else:a.modify();a.set_actor_scale3d(unreal.Vector(*r['before']))
 for c,r in cull_targets:c.modify();c.set_material(r['slot'],EAL.load_asset(r['before']))
 lights={r['actor']:r for r in read('coverage-native')['lights']}
 for r in receipt['tag_changes']:
  a=actors.get(r['actor'])
  if not a:continue
  added=set(r['after'])-set(r['before']);a.modify();a.set_editor_property('tags',[str(t) for t in a.tags if str(t) not in added])
  if r['actor'] in lights:
   c=a.get_component_by_class(unreal.LightComponent);props=lights[r['actor']]['properties']
   for key,value in props.items():
    if isinstance(value,(int,float,bool)):c.set_editor_property(key,value)
    elif key=='light_color':c.set_editor_property(key,unreal.Color(**{k:int(v) for k,v in re.findall(r'([rgba]):\s*(\d+)',value)}))
    elif key=='intensity_units':c.set_editor_property(key,getattr(unreal.LightUnits,re.search(r'LightUnits\.(\w+)',value).group(1)))
   if isinstance(a,unreal.DirectionalLight):t=lights[r['actor']]['xform'];a.set_actor_rotation(unreal.Rotator(pitch=t['rotation'][0],yaw=t['rotation'][1],roll=t['rotation'][2]),False)
 sky=actors['CitySkyLight'].light_component;cube=EAL.load_asset('/Engine/MapTemplates/Sky/DaylightAmbientCubemap');sky.set_editor_property('source_type',unreal.SkyLightSourceType.SLS_SPECIFIED_CUBEMAP);sky.set_cubemap_blend(cube,None,0.);sky.set_intensity(1.5)
 for name in known:assert SUB.destroy_actor(actors[name]),('failed to remove owned actor',name)
 assert sha(MAPFILE)==LOAD_SHA and sha(config)==config_sha,'Concurrent changes during restore; refusing save';assert unreal.EditorLevelLibrary.save_current_level();config.write_bytes(config_bom+''.join(updated).encode('utf8'));record_map_save('restore');write('restore',dict(status='passed',applied=True,geometry=geometry,actions=actions,backup=str(backup),map_sha256=sha(MAPFILE),config_sha256=sha(config),note='Only owned actors, recorded material/mesh bindings and controlled rendering keys restored; unrelated INI bytes, BOM and line endings preserved.'))

def environment_restore_probe():
 global OUT,MAPFILE,LOAD_SHA
 main_out=OUT;main_file=MAPFILE;main_sha=sha(main_file);main_config=ROOT/'StreetSocialCity/Config/DefaultEngine.ini';config_sha=sha(main_config);original_load=LOAD_SHA;world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.prepare_for_save();suffix=PAYLOAD['run_id'].replace('-','_');testmap=ENV+'/Tests/RestoreProbe_'+suffix;probe_out=OUT/'restore-probe'/suffix;probe_out.mkdir(parents=True,exist_ok=True);(probe_out/'backups').mkdir(exist_ok=True)
 for name in ['install','coverage-native','config-migration','depth-install','facing-install','spacing','closed-street-cull','closed-floor-cull','prop-solid-cull','street-surface-install','tactile-surface-install','water-depth-install','fixture-foot-spacing','office-layout']:
  if (OUT/(name+'.json')).is_file():shutil.copy2(OUT/(name+'.json'),probe_out/(name+'.json'))
 # Save-as targets a dedicated test map; verify its package and the untouched
 # main map before exercising actual removal/restoration on the copy.
 assert unreal.EditorLoadingAndSavingUtils.save_map(world,testmap)
 assert sha(main_file)==main_sha
 probe_file=ROOT/'StreetSocialCity/Content'/((testmap.removeprefix('/Game/'))+'.umap');assert probe_file.is_file()
 assert unreal.EditorLevelLibrary.load_level(testmap)
 assert unreal.EditorLevelLibrary.get_editor_world().get_path_name().split('.')[0]==testmap,'Explicit test-map load did not switch packages'
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController']
 sentinel=SUB.spawn_actor_from_class(unreal.Actor,unreal.Vector(12345,23456,3456));sentinel.set_actor_label('UserUnrelatedRestoreSentinel');sentinel.set_editor_property('tags',['UserUnrelatedEdit']);sun=actors['CitySun'];sun.set_editor_property('tags',[str(t) for t in sun.tags]+['UserUnrelatedTag']);sentinel_before=actor_xform(sentinel);floors_before={r['label']:(actor_xform(actors[r['label']]),[c.static_mesh.get_path_name() for c in actors[r['label']].get_components_by_class(unreal.StaticMeshComponent)]) for r in read('inventory-baseline')['actors'] if r['building_floor']}
 assert unreal.EditorLevelLibrary.save_current_level()
 fake_config=probe_out/'DefaultEngine-test.ini';migration=read('config-migration');fake_config.write_bytes(b'\xef\xbb\xbf'+('[/Script/Engine.RendererSettings]\r\n'+''.join(k+'='+v+'\r\n' for k,v in migration['after'].items())+'r.UserUnrelatedSetting=7\r\n[UserUnrelatedSection]\r\n; untouched spacing  \r\nName=User Sentinel\r\n').encode('utf8'))
 try:
  OUT=probe_out;MAPFILE=probe_file;LOAD_SHA=sha(probe_file);write('restore-request',dict(apply=False,geometry=True));environment_restore(fake_config);dry=read('restore');assert dry['status']=='passed' and not dry['applied'];write('restore-request',dict(apply=True,geometry=False));environment_restore(fake_config);applied=read('restore');assert applied['status']=='passed' and applied['applied']
  after={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert 'CityEnvironmentController' not in after and 'UserUnrelatedRestoreSentinel' in after;assert actor_xform(after['UserUnrelatedRestoreSentinel'])==sentinel_before and 'UserUnrelatedTag' in [str(t) for t in after['CitySun'].tags]
  for label,(xform,meshes) in floors_before.items():assert actor_xform(after[label])==xform and [c.static_mesh.get_path_name() for c in after[label].get_components_by_class(unreal.StaticMeshComponent)]==meshes,label
  config_after=fake_config.read_bytes();assert config_after.startswith(b'\xef\xbb\xbf') and b'r.UserUnrelatedSetting=7\r\n[UserUnrelatedSection]\r\n; untouched spacing  \r\nName=User Sentinel\r\n' in config_after and sha(main_file)==main_sha and sha(main_config)==config_sha
  report=dict(status='passed',test_map=testmap,applied_restore_on_copy=True,geometry_restore_dry_run=True,unrelated_actor_preserved=True,unrelated_tag_preserved=True,unrelated_config_preserved=True,floors_and_repaired_meshes_preserved=len(floors_before),main_map_unchanged=True,main_config_unchanged=True,main_map_sha256=main_sha)
 finally:OUT=main_out;MAPFILE=main_file;LOAD_SHA=original_load
 write('restore-probe',report)

def environment_verify():
 environment_audit();environment_guard_test();environment_camera_validation();environment_routes();environment_restore_probe();write('verify',dict(status='passed',scope='Fresh content, 200 native ephemeris samples, real save/load, stale-save rejection, camera/route reports and actual targeted restore on a test copy; camera/route statuses are independently recorded',map_sha256=sha(MAPFILE)))

def environment_finish():
 global LOAD_SHA
 if not (OUT/'sports.json').is_file():environment_sport_schedule();LOAD_SHA=sha(MAPFILE)
 environment_audit();environment_guard_test()
 folder=OUT/'surface-final';archive=OUT/('surface-final-before-polish-'+PAYLOAD['run_id'])
 assert folder.resolve().parent==OUT.resolve() and archive.resolve().parent==OUT.resolve() and not archive.exists();folder.rename(archive);environment_depth_export()
 environment_camera_validation();environment_routes();environment_restore_probe()
 write('finish',dict(status='passed',scope='Content/clock/save guards/restore on copy; camera and route report statuses remain independently binding; visual, motion and package checks are separate',map_sha256=sha(MAPFILE)))

def environment_validate():
 environment_audit();environment_guard_test()
 folder=OUT/'surface-final';archive=OUT/('surface-final-before-validation-'+PAYLOAD['run_id']);assert folder.resolve().parent==OUT.resolve() and archive.resolve().parent==OUT.resolve() and not archive.exists();folder.rename(archive);environment_depth_export()
 sites=read('sites');world=unreal.EditorLevelLibrary.get_editor_world();checks=[]
 for row in sites['rows']:
  for site in row['sites']:
   x,y,z=site['position_cm'];hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z+50),unreal.Vector(x,y,z-50),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None;ground_ok=bool(v and v[0] and abs(v[4].z-z)<.5 and v[7].z>.85);sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*site['approach_start_cm']),unreal.Vector(*site['approach_end_cm']),100,110));checks.append(dict(id=row['id'],position_cm=[x,y,z],ground_unchanged=ground_ok,clear=not sweep['blocked'],sweep=sweep))
 assert all(r['ground_unchanged'] and r['clear'] for r in checks),[r for r in checks if not r['ground_unchanged'] or not r['clear']]
 write('sites-before-recheck-'+PAYLOAD['run_id'],sites);sites['previous_map_sha256']=sites['map_sha256'];sites['map_sha256']=LOAD_SHA;sites['position_recheck_scope']='160 current positions and approach sweeps repeated, including two authorized PK0110 corrections; outdoor/interior and camera suitability remain separate';write('sites',sites);write('sites-position-recheck',dict(status='passed',rows=checks,map_sha256=LOAD_SHA))
 environment_camera_validation();environment_routes();environment_restore_probe();write('validate',dict(status='passed',scope='Preservation, native clock, source guard, position recheck and targeted restore; camera and route statuses remain independently binding',map_sha256=sha(MAPFILE)))

def environment_camera_validation():
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};floor_ids={r['label']:r['building_id'] for r in read('inventory-baseline')['actors'] if r['building_floor']};rows=[]
 def trace(p,q):
  hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(*p),unreal.Vector(*q),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None;return v if v and v[0] else None
 for site in read('sites')['rows']:
  original=site['camera'];target=original['target'];candidates=[original['eye']]+[[s['approach_start_cm'][0],s['approach_start_cm'][1],s['approach_start_cm'][2]+60] for s in site['sites']];delta=[original['eye'][k]-target[k] for k in range(2)]
  for degrees in [30,-30,60,-60,90,-90,180]:
   angle=math.radians(degrees);candidates.append([target[0]+delta[0]*math.cos(angle)-delta[1]*math.sin(angle),target[1]+delta[0]*math.sin(angle)+delta[1]*math.cos(angle),original['eye'][2]])
  attempts=[];chosen=None
  for p in candidates:
   down=trace([p[0],p[1],target[2]+2500],[p[0],p[1],target[2]-3000])
   if not down or down[7].z<.8:attempts.append(dict(seed=p,reason='no walkable native support'));continue
   label=down[9].get_actor_label() if down[9] else '';eye=[p[0],p[1],float(down[4].z)+180]
   up=trace(eye,[eye[0],eye[1],eye[2]+1500]);up_label=up[9].get_actor_label() if up and up[9] else ''
   if label in floor_ids and up_label in floor_ids and floor_ids[label]==floor_ids[up_label]:attempts.append(dict(seed=p,reason='inside a protected building',support=label,ceiling=up_label));continue
   sweep=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,unreal.Vector(*eye),unreal.Vector(*eye),20,20))
   if sweep['blocked']:attempts.append(dict(seed=p,reason='camera overlaps native collision',collision=sweep));continue
   hit=trace(eye,target);hit_label=hit[9].get_actor_label() if hit and hit[9] else ''
   if hit and hit_label!=site['actor'] and math.dist(eye,[hit[4].x,hit[4].y,hit[4].z])<math.dist(eye,target)*.9:attempts.append(dict(seed=p,reason='target is obstructed',actor=hit_label));continue
   chosen=dict(eye=eye,target=target,fov=original['fov'],support_actor=label,clearance=sweep);break
  rows.append(dict(id=site['id'],actor=site['actor'],status='passed' if chosen else 'needs_camera_adjustment',camera=chosen,attempts=attempts))
 write('cameras',dict(status='passed' if all(r['camera'] for r in rows) else 'needs_camera_adjustment',rows=rows,map_sha256=LOAD_SHA,method='Native walkable support, 20cm camera clearance, protected-interior rejection and target line of sight; final visual review remains required'))

def environment_render():
 environment_audit()
 missing_cameras=[]
 initial_request=read('render-request')
 if initial_request.get('refresh_cameras'):environment_camera_validation();environment_routes()
 request=read('render-request');assert request['set'] in ['calibration','preview','full','polish','office'];actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};controller=actors['CityEnvironmentController'];controller.set_paused(True);controller.initialize_bindings();world=unreal.EditorLevelLibrary.get_editor_world();jobs=[];sites={r['id']:r for r in read('sites')['rows']};folder=OUT/'renders'/request['set']/PAYLOAD['run_id'];folder.mkdir(parents=True,exist_ok=True)
 if request['set']=='office':
  cameras=read('cameras');assert cameras['map_sha256']==LOAD_SHA;camera=next(r['camera'] for r in cameras['rows'] if r['id']=='PK-0110');assert camera
  for hour in [12,21,2]:jobs.append(dict(name='picnic-cleared-'+str(hour),id='PK-0110',hour=hour,grey=False,**{k:camera[k] for k in ['eye','target','fov']}))
  jobs.append(dict(name='office-setback-overview-12',id='office-overview',hour=12,grey=False,eye=[37350,78000,5500],target=[37350,83500,1200],fov=75))
  jobs.append(dict(name='picnic-access-ramp-12',id='picnic-access',hour=12,grey=False,eye=[36172.5,81100,1345],target=[36172.5,82800,1250],fov=70))
 elif request['set']=='polish':
  for hour in [21,12]:jobs.append(dict(name='approved-street-'+str(hour),id='approved-street',hour=hour,grey=False,eye=[45546.45,41890.81,1700.2],target=[45900,43800,1800],fov=60))
  receipt=read('visual_polish')
  for aid,path in receipt['tree_meshes'].items():
   candidates=[]
   for r in receipt['trees']:
    if r['after']!=path:continue
    a=actors[r['actor']];c=next(q for q in a.get_components_by_class(unreal.StaticMeshComponent) if q.get_name()==r['component']);t=c.get_instance_transform(0,True) if isinstance(c,unreal.InstancedStaticMeshComponent) else c.get_world_transform();p=t.translation;candidates.append((math.dist([p.x,p.y],[45546,41890]),c,t))
   _,c,t=min(candidates,key=lambda q:q[0]);bounds=c.static_mesh.get_bounding_box();target=unreal.MathLibrary.transform_location(t,(bounds.min+bounds.max)*.5);width=max((bounds.max.x-bounds.min.x)*abs(t.scale3d.x),(bounds.max.y-bounds.min.y)*abs(t.scale3d.y));eye=target+unreal.Vector(-width*.65,-width*1.65,0)
   jobs.append(dict(name='tree-'+aid+'-12',id=aid,hour=12,grey=False,eye=num(eye),target=num(target),fov=48))
  directions={r['actor']:r['direction_world'] for r in read('sign-clearance-plan')['rows']}
  for bid in ['S01','S03','S09']:
   a=actors['RomanceName_'+bid];origin,extent=a.get_actor_bounds(False);direction=unreal.Vector(*directions[a.get_actor_label()]);distance=max(extent.x,extent.y,extent.z)*3.1;eye=origin+direction*distance
   jobs.append(dict(name='dark-letter-sign-'+bid+'-21',id=bid,hour=21,grey=False,eye=num(eye),target=num(origin),fov=50))
 elif request['set']=='calibration':
  for region,aid in [('shopping','D014'),('hotel-garden','D002'),('lake-deck','PK-0106')]:
   site=sites[aid]['sites'][0];x,y,z=site['position_cm']
   for hour in [21,2]:
    for n,dy in enumerate([125,255,385]):jobs.append(dict(name=region+'-'+str(hour)+'-grey-'+str(n),region=region,id=aid,hour=hour,grey=True,seed=[x,y+dy,z],sample=n,fov=60))
 else:
  camera_receipt=read('cameras');camera_rows={r['id']:r for r in camera_receipt['rows']};assert camera_receipt['map_sha256']==LOAD_SHA,'Fresh native cameras required; legacy LI views are not accepted'
  for name,aid in [('hotel-garden','D002'),('campus-lake','PK-0106'),('shop-dining','D014'),('bay-camp','E033'),('sports-entry','PK-0113'),('public-park','PK-0101')]:
   row=camera_rows[aid];assert row['status']=='passed' and row['camera'],('Representative camera did not pass',name,aid);camera={k:v for k,v in row['camera'].items() if k in ['eye','target','fov']}
   for hour in ([21,2,12,17.5] if request['set']=='preview' else range(24)):jobs.append(dict(name=name+'-'+str(hour),id=name,camera_source_id=aid,hour=hour,grey=False,**camera))
  if request['set']=='full':
   camera_receipt=read('cameras');camera_rows={r['id']:r for r in camera_receipt['rows']};assert camera_receipt['map_sha256']==LOAD_SHA,'Camera validation from this exact map required'
   for aid,q in sites.items():
    if camera_rows[aid]['status']!='passed' or not camera_rows[aid]['camera']:
     missing_cameras.append(dict(id=aid,status=camera_rows[aid]['status'],reason='Native support, exterior or line-of-sight validation did not pass'));continue
    camera={k:v for k,v in camera_rows[aid]['camera'].items() if k in ['eye','target','fov']}
    for hour in [17.5,21,2]:jobs.append(dict(name=aid+'-'+str(hour),id=aid,hour=hour,grey=False,**camera))
  jobs.append(dict(name='moon-skyline-21',id='moon-skyline',hour=21,grey=False,eye=[45546.45,41890.81,1700.2],target=[45900,43800,2500],fov=100,follow_moon=True))
 assert jobs
 grey_path=ENV+'/Materials/M_EnvironmentGrey18'
 if not EAL.does_asset_exist(grey_path):
  material=ATS.create_asset('M_EnvironmentGrey18',ENV+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
  for value,prop in [(.18,unreal.MaterialProperty.MP_BASE_COLOR),(1.,unreal.MaterialProperty.MP_ROUGHNESS),(0.,unreal.MaterialProperty.MP_SPECULAR)]:
   n=MEL.create_material_expression(material,unreal.MaterialExpressionConstant);n.set_editor_property('r',value);assert MEL.connect_material_property(n,'',prop)
  MEL.recompile_material(material);assert EAL.save_loaded_asset(material)
 grey=EAL.load_asset(grey_path);state=dict(i=0,phase='setup',wait=60,images=[],probes=[],refs=[],captures=[],card=None,busy=False)
 from datetime import datetime
 full=datetime.fromisoformat(read('ephemeris-reference-check')['full_moon_local'])
 def cleanup():
  for a,c,rt,kind in state['captures']:c.set_editor_property('texture_target',None);SUB.destroy_actor(a);unreal.RenderingLibrary.release_render_target2d(rt)
  state['captures']=[];state['refs']=[]
  if state['card']:SUB.destroy_actor(state['card']);state['card']=None
 def tick(dt):
  if state['busy']:return
  if state['wait']>0:state['wait']-=1;return
  state['busy']=True
  try:
   if state['phase']=='setup':
    q=jobs[state['i']];controller.set_date_time(unreal.DateTime(full.year,full.month,full.day,int(q['hour']),int(round((float(q['hour'])%1)*60)),0,0));controller.apply_environment()
    if q['grey']:
     x,y,z=q['seed'];hit=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z+150),unreal.Vector(x,y,z-150),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);v=hit.to_tuple() if hit else None;assert v and v[0] and v[7].z>.85,('unsupported grey probe',q)
     normal=v[7];center=v[4]+normal*5.;card=SUB.spawn_actor_from_class(unreal.StaticMeshActor,center,unreal.MathLibrary.make_rot_from_z(normal));card.set_actor_label('EnvironmentTemporaryGreyProbe');c=card.static_mesh_component;c.set_static_mesh(EAL.load_asset('/Engine/BasicShapes/Cube.Cube'));c.set_material(0,grey);c.set_collision_profile_name('NoCollision');c.set_editor_property('cast_shadow',False);card.set_actor_scale3d(unreal.Vector(1.2,1.2,.01));state['card']=card;eye=center+normal*1000;target=center;q['actual_probe_cm']=num(center);q['normal']=num(normal)
    else:
     eye=unreal.Vector(*q['eye']);target=unreal.Vector(*q['target'])
     if q.get('follow_moon'):
      direction=json.loads(controller.get_state_json())['moon']['direction'];length=math.hypot(direction[0],direction[1]);assert length>.001;target=eye+unreal.Vector(direction[0]/length*1800,direction[1]/length*1800,math.tan(math.radians(24))*1800)
    q['actual_eye_cm']=num(eye);rot=unreal.MathLibrary.find_look_at_rotation(eye,target);unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).set_level_viewport_camera_info(eye,rot);controller.set_lighting_view_override(eye,True);controller.apply_environment()
    for kind in (['hdr'] if q['grey'] else ['hdr','ldr']):
     a=SUB.spawn_actor_from_class(unreal.SceneCapture2D,eye,rot);c=a.capture_component2d;c.set_editor_property('capture_every_frame',True);c.set_editor_property('capture_on_movement',False);c.set_editor_property('always_persist_rendering_state',True);size=(256,256) if q['grey'] else (1600,1000);rt=unreal.RenderingLibrary.create_render_target2d(world,*size,unreal.TextureRenderTargetFormat.RTF_RGBA16F if kind=='hdr' else unreal.TextureRenderTargetFormat.RTF_RGBA8_SRGB);state['refs'].append(rt);c.set_editor_property('texture_target',rt);c.set_editor_property('capture_source',unreal.SceneCaptureSource.SCS_SCENE_COLOR_HDR_NO_ALPHA if kind=='hdr' else unreal.SceneCaptureSource.SCS_FINAL_COLOR_LDR);c.set_editor_property('fov_angle',q['fov']);c.set_editor_property('max_view_distance_override',0.)
     c.set_editor_property('show_flag_settings',[unreal.EngineShowFlagsSetting(show_flag_name='EyeAdaptation',enabled=kind=='ldr'),unreal.EngineShowFlagsSetting(show_flag_name='TemporalAA',enabled=kind=='ldr'),unreal.EngineShowFlagsSetting(show_flag_name='MotionBlur',enabled=False)])
     if q['grey']:c.set_editor_property('projection_type',unreal.CameraProjectionMode.ORTHOGRAPHIC);c.set_editor_property('ortho_width',300.)
     state['captures'].append((a,c,rt,kind))
    state['current']=q;state['phase']='capture';state['wait']=90
   elif state['phase']=='capture':
    unreal.AutomationLibrary.finish_loading_before_screenshot()
    for a,c,rt,kind in state['captures']:c.set_editor_property('capture_every_frame',False);c.capture_scene()
    state['phase']='export';state['wait']=8
   else:
    q=state['current'];files={}
    for a,c,rt,kind in state['captures']:
     path=folder/(q['name']+('.hdr' if kind=='hdr' else '.png'));unreal.RenderingLibrary.export_render_target(world,rt,str(folder),path.name);assert path.is_file() and path.stat().st_size>1000;files[kind]=dict(path=str(path),sha256=sha(path))
    local_lights=[dict(actor=a.get_actor_label(),intensity=a.light_component.get_editor_property('intensity'),distance_cm=math.dist(num(a.get_actor_location()),q['actual_eye_cm'])) for a in SUB.get_all_level_actors() if isinstance(a,(unreal.PointLight,unreal.SpotLight)) and math.dist(num(a.get_actor_location()),q['actual_eye_cm'])<2500];lamp_weight=unreal.MaterialLibrary.get_scalar_parameter_value(world,EAL.load_asset(ENV+'/MPC_CityEnvironment'),'LampGlowWeight');row=dict(**q,files=files,state=json.loads(controller.get_state_json()),actual_lamp_mpc_weight=lamp_weight,nearby_local_lights=local_lights,shadow_filter_method=unreal.SystemLibrary.get_console_variable_int_value('r.Shadow.FilterMethod'));state['images'].append(row)
    if q['grey']:state['probes'].append(dict(id=q['name'],region=q['region'],hour=q['hour'],role='path',hdr_path=files['hdr']['path'],roi_xywh=[112,112,32,32],position_cm=q['actual_probe_cm'],normal=q['normal']))
    cleanup();state['i']+=1;write('render-progress',dict(status='running',completed=state['i'],total=len(jobs),set=request['set']))
    if state['i']==len(jobs):
     unreal.unregister_slate_post_tick_callback(environment_render_handle);assert sha(MAPFILE)==LOAD_SHA;receipt=dict(status='captured_with_missing_cameras' if missing_cameras else 'passed',set=request['set'],images=state['images'],count=len(state['images']),missing_cameras=missing_cameras,map_sha256=LOAD_SHA,note='Native paired linear HDR/LDR captures; missing viewpoints remain explicit and visual review remains mandatory.');write('render',receipt);write('render-'+request['set'],receipt)
     if state['probes']:write('hdr-probes',dict(status='captured_requires_measurement',map_sha256=LOAD_SHA,render_run_id=PAYLOAD['run_id'],grey_card_linear_reflectance=.18,capture_space='linear scene radiance before exposure',probes=state['probes']))
     pending=list(request.get('sequence',[]))
     if pending:
      write('render-request',dict(set=pending[0],sequence=pending[1:]));environment_render();return
     quit_clean();return
    state['phase']='setup';state['wait']=8
  except BaseException:
   unreal.unregister_slate_post_tick_callback(environment_render_handle);cleanup();write('render',dict(status='failed',error=traceback.format_exc(),completed=state['i']));unreal.log_error(traceback.format_exc());quit_clean()
  finally:state['busy']=False
 global environment_render_handle,ENV_RENDER_STATE
 ENV_RENDER_STATE=state;environment_render_handle=unreal.register_slate_post_tick_callback(tick)

def work_environment():
 try:
  if MODE=='inventory':environment_inventory();quit_clean()
  elif MODE=='plan':environment_assets();sun_position_reference();quit_clean()
  elif MODE in ['shader','sites']:environment_sites();quit_clean()
  elif MODE=='routes':environment_routes();quit_clean()
  elif MODE=='install':environment_install();quit_clean()
  elif MODE=='audit':environment_audit();quit_clean()
  elif MODE=='render':environment_audit();environment_render();return
  elif MODE=='depth':environment_depth_apply();quit_clean()
  elif MODE=='street_shader':environment_street_shader();quit_clean()
  elif MODE=='world_apply':environment_world_apply();quit_clean()
  elif MODE=='water_spacing':environment_water_spacing();quit_clean()
  elif MODE=='footing_spacing':environment_footing_spacing();quit_clean()
  elif MODE=='office_probe':environment_office_probe();quit_clean()
  elif MODE=='office_preview':environment_office_layout(False);quit_clean()
  elif MODE=='office_apply':environment_office_layout(True);quit_clean()
  elif MODE=='prop_cull':environment_prop_cull();quit_clean()
  elif MODE=='world_shader':environment_world_shader();quit_clean()
  elif MODE=='world_probe':
   result=json.loads(unreal.CityDepthAuditLibrary.probe_world_sheet_repair(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'world-probe')));write('world_probe',result);assert result['status']=='passed',result;quit_clean()
  elif MODE=='street_probe':environment_street_probe();quit_clean()
  elif MODE in ['street_sources','tactile_sources']:environment_street_sources();quit_clean()
  elif MODE in ['street_union','tactile_union']:environment_street_union();quit_clean()
  elif MODE in ['street_apply','tactile_apply']:environment_street_apply();quit_clean()
  elif MODE=='facing':environment_facing_partition();quit_clean()
  elif MODE=='depth_export':environment_depth_export();quit_clean()
  elif MODE=='prepare':environment_prepare();quit_clean()
  elif MODE=='spacing':environment_spacing();quit_clean()
  elif MODE=='cull':environment_cull_closed_street();quit_clean()
  elif MODE=='cull_solids':environment_cull_proven_floor_solids();quit_clean()
  elif MODE=='cull_review':environment_review_solid_scope();quit_clean()
  elif MODE=='sports':environment_sport_schedule();quit_clean()
  elif MODE=='visual_polish':environment_visual_polish();quit_clean()
  elif MODE=='flower_refine':environment_flower_refine();quit_clean()
  elif MODE=='finish':environment_finish();quit_clean()
  elif MODE=='validate':environment_validate();quit_clean()
  elif MODE=='guard':environment_guard_test();quit_clean()
  elif MODE=='refine':environment_refine();quit_clean()
  elif MODE=='lookdev':environment_lookdev();quit_clean()
  elif MODE=='moon_refine':environment_moon_refine();quit_clean()
  elif MODE=='restore':environment_restore();quit_clean()
  elif MODE=='facing_probe':
   result=json.loads(unreal.CityDepthAuditLibrary.probe_facing_partition(unreal.EditorLevelLibrary.get_editor_world(),str(OUT/'facing-probe')));write('facing_probe',result);assert result['status']=='passed',result;quit_clean()
  elif MODE=='probe':environment_restore_probe();write('probe',dict(status='passed',main_map_sha256=sha(MAPFILE)));quit_clean()
  elif MODE=='verify':environment_verify();quit_clean()
  else:raise RuntimeError('Mode not implemented yet: '+MODE)
 except BaseException:
  write(MODE,dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc());quit_clean()

assert unreal.EditorLevelLibrary.load_level('/Engine/Maps/Entry' if MODE in ['plan','facing_probe','street_union','tactile_union','street_probe','world_probe','world_shader','street_shader'] else MAP)
env_frames=0
def tick_environment(dt):
 global env_frames
 env_frames+=1
 if env_frames<120:return
 unreal.unregister_slate_post_tick_callback(env_handle);work_environment()
env_handle=unreal.register_slate_post_tick_callback(tick_environment)
]====]
