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
 ctl=[a for a in SUB_.get_all_level_actors() if a.get_actor_label()=='CityEnvironmentController']
 if ctl:ctl[0].refresh_bindings();ctl[0].prepare_for_save();ctl[0].set_editor_property('is_spatially_loaded',False)
 assert unreal.EditorLoadingAndSavingUtils.save_map(world,DEST),DEST
 o=ROOT/'output/street-social-city-production/stream-v1';o.mkdir(parents=True,exist_ok=True)
 r=dict(status='passed',map=DEST,split_actors=len(gone),instances=inst,cell_actors=made,kept_small=kept,lights=lights,light_scale=LIGHT_SCALE)
 (o/'prep.json').write_text(json.dumps(r,indent=1),'utf8');return r
]====]
