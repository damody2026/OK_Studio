return [====[
DECOR_OUT=ROOT/'output/street-social-city-production/motel-decor-tripo-v1'
DECOR_PREFIX='/Game/UniversityCity/MotelDecorTripoV1'

def motel_decor_import():
 global PREFIX,KEEP,save
 # instant-meshes-rs results (Tools/remesh_street_city_motel_tripo_decor.lua) go into Unreal only where they cut triangles;
 # otherwise the prepared mesh, decided per model (user 2026-10-27).
 p=json.loads((DECOR_OUT/'remeshed.json').read_text('utf8'));assets=[r for r in p['assets'] if r['status']=='passed'];assert assets;PREFIX=DECOR_PREFIX;KEEP=[];save=save_asset;source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+source,ns);imp=ns['import_one'];rows=[]
 for r in assets:
  use_prep=r['triangles']>=r['prepared_triangles'];path,digest=(r['prepared'],r['prepared_sha256']) if use_prep else (r['path'],r['sha256'])
  assert sha(path)==digest;mesh=imp(Path(path),r['id'],0,True);assert mesh.get_num_triangles(0)<=35000;slots=[]
  for i,s in enumerate(mesh.get_editor_property('static_materials')):
   m=mesh.get_material(i);assert m;slots.append(m.get_path_name())
  assert slots and EAL.save_loaded_asset(mesh,False);rows.append(dict(id=r['id'],room_id=r['room_id'],slot=r['slot'],index=r['index'],asset=mesh.get_path_name(),triangles=mesh.get_num_triangles(0),source_sha256=digest,tripo_model_id=r['tripo_model_id'],remesh_rung='prepared' if use_prep else r['rung'],materials=slots))
 assert sha(MAPFILE)==LOAD_SHA;(DECOR_OUT/'imports.json').write_text(json.dumps(dict(status='imported_requires_placement' if len(rows)==122 else 'partial_import_only',map_sha256=LOAD_SHA,assets=rows,completed=len(rows),required=122),ensure_ascii=False,indent=2),'utf8')

def motel_decor_slot_position(room,q,slot):
 w=q['size_m'][0];v=[w*.27,-1.7,.53] if slot=='A' else [w*.29-2+.36,-8.8,.90];angle=math.radians(q['yaw']);base=room['position']
 return unreal.Vector(base[0]+(v[0]*math.sin(angle)+v[1]*math.cos(angle))*100,base[1]+(v[0]*math.cos(angle)-v[1]*math.sin(angle))*100,base[2]+v[2]*100)

def motel_decor_probe():
 # Read-only: trace every planned A/B slot against the suite actor; nothing is spawned or saved.
 installed=read('motel-install');rooms=installed['rooms'];plan={r['id']:r for r in read('motel-plan')['rooms']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for room in rooms:
  q=plan[room['id']]
  for slot in 'AB':
   p=motel_decor_slot_position(room,q,slot);hit=unreal.SystemLibrary.line_trace_single(world,p+unreal.Vector(0,0,40),p-unreal.Vector(0,0,40),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple()
   footprint=[]
   for dx,dy in [(18,0),(-18,0),(0,18),(0,-18),(13,13),(-13,13),(13,-13),(-13,-13)]:
    c=p+unreal.Vector(dx,dy,0);t=unreal.SystemLibrary.line_trace_single(world,c+unreal.Vector(0,0,40),c-unreal.Vector(0,0,40),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();footprint.append(float(t[4].z-p.z) if t[0] else None)
   suite=actors.get('MotelV1_Suite_'+room['id']);rows.append(dict(room_id=room['id'],slot=slot,planned=num(p),footprint_dz_cm=footprint,hit=bool(hit[0]),hit_actor=hit[9].get_actor_label() if hit[0] and hit[9] else None,hit_component=hit[10].get_name() if hit[0] and hit[10] else None,hit_z=float(hit[4].z) if hit[0] else None,dz_cm=float(hit[4].z-p.z) if hit[0] else None,suite_present=bool(suite)))
 (DECOR_OUT/'placement-probe.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,rows=rows),ensure_ascii=False,indent=2),'utf8')

def motel_decor_place():
 imports=json.loads((DECOR_OUT/'imports.json').read_text('utf8'));assert imports['completed']==122 and len(imports['assets'])==122,'Only install a complete122-asset set';installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;rooms={r['id']:r for r in installed['rooms']};plan={r['id']:r for r in read('motel-plan')['rooms']};actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};assert not any(k.startswith('MotelDecorTripoV1_') for k in actors),'Refuse duplicate placement';world=unreal.EditorLevelLibrary.get_editor_world();pending=[]
 for r in imports['assets']:
  room=rooms[r['room_id']];q=plan[r['room_id']];w=q['size_m'][0];v=[w*.27,-1.7,.53] if r['slot']=='A' else [w*.29-2+.36,-8.8,.90];angle=math.radians(q['yaw']);base=room['position'];p=unreal.Vector(base[0]+(v[0]*math.sin(angle)+v[1]*math.cos(angle))*100,base[1]+(v[0]*math.cos(angle)-v[1]*math.sin(angle))*100,base[2]+v[2]*100);mesh=EAL.load_asset(r['asset']);assert mesh;hit=unreal.SystemLibrary.line_trace_single(world,p+unreal.Vector(0,0,8),p-unreal.Vector(0,0,8),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();assert hit[0] and hit[9]==actors['MotelV1_Suite_'+r['room_id']] and abs(hit[4].z-p.z)<.4,('Table support failed',r['id'],num(hit[4]) if hit[0] else None);pending.append((r,room,p,mesh,num(hit[4])))
 backup=DECOR_OUT/('UniversityCity-before-tripo-decor-'+LOAD_SHA[:16]+'.umap');assert not backup.exists() or sha(backup)==LOAD_SHA,'Backup name taken by a different map'
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 rows=[]
 for r,room,p,mesh,support in pending:
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,p,unreal.Rotator(yaw=room['yaw']));a.set_actor_label('MotelDecorTripoV1_'+r['id']);a.tags=[unreal.Name('MotelDecorTripoV1'),unreal.Name(r['room_id'])];a.set_folder_path('UniversityCity/MotelDecorTripoV1/'+r['room_id']);c=a.static_mesh_component;c.set_static_mesh(mesh);c.set_collision_profile_name('NoCollision');c.set_cast_shadow(True);a.set_actor_location(p+unreal.Vector(0,0,.12),False,False);rows.append(dict(id=r['id'],room_id=r['room_id'],slot=r['slot'],actor=a.get_actor_label(),asset=r['asset'],position=num(a.get_actor_location()),support=support,tripo_model_id=r['tripo_model_id'],triangles=r['triangles']))
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();newsha=sha(MAPFILE);installed.update(parent_map_sha256=LOAD_SHA,map_sha256=newsha,tripo_decor_count=122);write('motel-install',installed);(DECOR_OUT/'placement.json').write_text(json.dumps(dict(status='saved_requires_fresh_audit_game_pixels_and_walking',map_sha256=newsha,parent_map_sha256=LOAD_SHA,backup=str(backup),assets=rows,rooms=61,ornaments=122,scope='Only122 unique actual Tripo imports placed on native traced existing furniture surfaces; small nonblocking decorations,0.12cm seating gap; requires full visual/route validation.'),ensure_ascii=False,indent=2),'utf8')
]====]
