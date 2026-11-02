-- Read-only actor dump for the StreetSocial place inventory of UniversityCity (Docs/STREET_CITY_PLACES_INVENTORY_20261103.md).
--   lua Tools/street_city_motel_job.lua world_places_probe Tools/street_city_places_payload.lua
-- Writes output/street-social-city-production/places-v1/actors.json: every level actor with label, class, folder,
-- tags, yaw, bounds (centre/extent, cm) and the static mesh path; instanced components report mesh + instance count.
-- Nothing is saved; Tools/build_street_city_places.lua turns the dump into the game place table.
return [====[
PL_OUT=ROOT/'output/street-social-city-production/places-v1'
def motel_world_places_probe():
 PL_OUT.mkdir(parents=True,exist_ok=True);rows=[]
 for a in SUB.get_all_level_actors():
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  r=dict(label=a.get_actor_label(),cls=a.get_class().get_name(),folder=str(a.get_folder_path()),tags=[str(t) for t in a.tags],yaw=a.get_actor_rotation().yaw,loc=num(a.get_actor_location()),c=num(o),e=num(e))
  if isinstance(a,unreal.StaticMeshActor) and a.static_mesh_component.static_mesh:r['mesh']=a.static_mesh_component.static_mesh.get_path_name().split('.')[-1]
  inst=[]
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   if c.static_mesh:inst.append([c.static_mesh.get_path_name().split('.')[-1],c.get_instance_count()])
  if inst:r['inst']=inst
  rows.append(r)
 (PL_OUT/'actors.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,actors=rows),ensure_ascii=False),'utf8')
]====]
