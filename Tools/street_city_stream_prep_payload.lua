-- Native job: make the streaming copy of the city. The source map is never saved; everything happens in memory and goes to
-- /Game/UniversityCity/Maps/UniversityCityWP, which Tools/build_street_city_stream.lua then converts to World Partition.
--   lua Tools/street_city_motel_job.lua world_stream_prep Tools/street_city_stream_prep_payload.lua
--   split   an actor whose instances spread over more than one 128 m cell would sit in a high grid level and stay loaded:
--           its instances go to one instanced actor per mesh and cell
--   lights  the game renders at a fixed exposure of 1, the city's lamps are in real lumens for auto exposure:
--           point, spot and rect lights are scaled by LIGHT_SCALE (the source map keeps its values, the survey photos need them)
-- Output: output/street-social-city-production/stream-v1/prep.json
return [====[
def motel_world_stream_prep():
 CELL=12800.;LIGHT_SCALE=.125;DEST='/Game/UniversityCity/Maps/UniversityCityWP'
 world=unreal.EditorLevelLibrary.get_editor_world();SUB_=unreal.get_editor_subsystem(unreal.EditorActorSubsystem);LIB=unreal.CityDepthAuditLibrary
 actors=SUB_.get_all_level_actors();groups={};gone=[];kept=0;inst=0
 for a in actors:
  comps=[c for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent)]
  if not comps:continue
  o,e=a.get_actor_bounds(False)
  if max(e.x,e.y)*2<CELL:kept+=1;continue
  other=[c for c in a.get_components_by_class(unreal.StaticMeshComponent) if not isinstance(c,unreal.InstancedStaticMeshComponent)]
  for c in comps:
   m=c.static_mesh;n=c.get_instance_count()
   if not m or not n:continue
   mats=tuple(c.get_material(i) for i in range(c.get_num_materials()))
   prof=str(c.get_collision_profile_name());shadow=c.cast_shadow
   for i in range(n):
    t=c.get_instance_transform(i,True)
    if isinstance(t,tuple):t=t[-1]
    p=t.translation;k=(m.get_path_name(),tuple(x.get_path_name() if x else '' for x in mats),prof,shadow,int(p.x//CELL),int(p.y//CELL))
    g=groups.get(k)
    if g is None:g=groups[k]=dict(mesh=m,mats=mats,prof=prof,shadow=shadow,items=[],name=a.get_actor_label())
    g['items'].append(t);inst+=1
   if other:c.clear_instances()
  if not other:gone.append(a)
 made=0
 for k,g in groups.items():
  made+=1;c=LIB.create_flat_world_instances(world,g['mesh'],g['mats'][0] if g['mats'] and g['mats'][0] else g['mesh'].get_material(0),'FlatCampus_Stream_%d'%made)
  assert c,k[0]
  for i,x in enumerate(g['mats']):
   if x:c.set_material(i,x)
  c.set_collision_profile_name(g['prof']);c.set_cast_shadow(g['shadow']);c.add_instances(g['items'],False,True)
  o=c.get_owner();o.set_actor_label('Stream_%s_%d_%d_%d'%(g['name'][:24],k[4],k[5],made));o.set_folder_path('UniversityCity/Stream')
 for a in gone:SUB_.destroy_actor(a)
 lights=0
 for a in SUB_.get_all_level_actors():
  if isinstance(a,(unreal.PointLight,unreal.SpotLight,unreal.RectLight)):
   c=a.light_component;c.set_editor_property('intensity',c.get_editor_property('intensity')*LIGHT_SCALE);lights+=1
 # a room with no lamp of its own goes black at night once the sky light is down (dance studio SC-0303, c-conquest 11-07):
 # up to four ceiling lights a room, no shadows, as bright as a shop lamp after LIGHT_SCALE
 spots=[(a.get_actor_location(),) for a in SUB_.get_all_level_actors() if isinstance(a,(unreal.PointLight,unreal.SpotLight,unreal.RectLight))]
 rooms=[r for r in json.loads((ROOT/'output/street-social-city-production/places-v1/props.json').read_text('utf8'))['areas'] if r.get('kind')=='room' and 'min' in r]
 added=0;darkrooms=0
 for r in rooms:
  lo,hi=r['min'],r['max']
  if any(lo[0]<=p[0].x<=hi[0] and lo[1]<=p[0].y<=hi[1] and lo[2]-20<=p[0].z<=hi[2]+60 for p in spots):continue
  darkrooms+=1;w,d=hi[0]-lo[0],hi[1]-lo[1];nx,ny=(1 if w<900 else 2),(1 if d<900 else 2)
  for i in range(nx):
   for j in range(ny):
    a=SUB_.spawn_actor_from_class(unreal.PointLight,unreal.Vector(lo[0]+w*(i+.5)/nx,lo[1]+d*(j+.5)/ny,lo[2]+260),unreal.Rotator(0,0,0))
    a.set_actor_label('RoomLight_%s_%d'%(r['id'],i*2+j));a.set_folder_path('UniversityCity/RoomLights');c=a.light_component
    c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_editor_property('intensity',275.);c.set_editor_property('attenuation_radius',800.);c.set_editor_property('cast_shadows',False);c.set_editor_property('light_color',unreal.Color(r=255,g=240,b=220,a=255));added+=1
 # what the game did to every piece as it came in (OKStreetCityDress) is saved here, so a cell needs no render state rebuilt on arrival:
 # local lights cast nothing and end at 120 m, and the smaller a mesh the sooner it goes (an instanced one by the size of the mesh it draws)
 far=lambda r:6000. if r<100 else 15000. if r<300 else 40000. if r<1000 else 0.
 culled=0;dressed=0
 for a in SUB_.get_all_level_actors():
  for c in a.get_components_by_class(unreal.LocalLightComponent):
   c.set_editor_property('cast_shadows',False);c.set_editor_property('max_draw_distance',12000.);c.set_editor_property('max_distance_fade_range',2000.);dressed+=1
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh
   if not m:continue
   if isinstance(c,unreal.InstancedStaticMeshComponent):
    f=far(m.get_bounds().sphere_radius)
    if f>0 and c.get_editor_property('instance_end_cull_distance')<=0:c.set_editor_property('instance_start_cull_distance',int(f*.9));c.set_editor_property('instance_end_cull_distance',int(f));culled+=1
   elif c.get_editor_property('ld_max_draw_distance')<=0:
    f=far(unreal.SystemLibrary.get_component_bounds(c)[2])
    if f>0:c.set_editor_property('ld_max_draw_distance',f);culled+=1
 # the clock, lamps and sky run from this one actor: in a cell it was unloaded and began again at every return, 60-78 ms a scan of the map
 ctl=[a for a in SUB_.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController']
 if ctl:ctl[0].refresh_bindings();ctl[0].prepare_for_save();ctl[0].set_editor_property('is_spatially_loaded',False)
 assert unreal.EditorLoadingAndSavingUtils.save_map(world,DEST),DEST
 o=ROOT/'output/street-social-city-production/stream-v1';o.mkdir(parents=True,exist_ok=True)
 r=dict(status='passed',map=DEST,split_actors=len(gone),instances=inst,cell_actors=made,kept_small=kept,lights=lights,light_scale=LIGHT_SCALE,dark_rooms=darkrooms,room_lights=added,lights_dressed=dressed,culled=culled,controller=len(ctl))
 (o/'prep.json').write_text(json.dumps(r,indent=1),'utf8');return r
]====]
