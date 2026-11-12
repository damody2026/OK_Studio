-- Read-only native job: which actors and materials make up a room? Nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_room_materials Tools/street_city_room_materials_payload.lua
-- Input: output/street-social-city-production/places-v1/room-material-seeds.json, a list of
--   { name, box = [x0,y0,z0,x1,y1,z1] }
-- Output: places-v1/room-materials.json per seed: every static mesh component (plain or instanced) whose bounds overlap the
-- box, with actor label, folder, mesh, and per slot the material, its parent chain and its texture parameters / textures.
return [====[
def motel_world_room_materials():
 world=unreal.EditorLevelLibrary.get_editor_world()
 base=ROOT/'output/street-social-city-production/places-v1'
 seeds=json.loads((base/'room-material-seeds.json').read_text('utf8'))
 cache={}
 def mat_row(m):
  if not m:return None
  k=m.get_path_name()
  if k in cache:return cache[k]
  row=dict(path=k,cls=m.get_class().get_name())
  chain=[];p=m
  while isinstance(p,unreal.MaterialInstance):
   p=p.get_editor_property('parent');chain.append(p.get_path_name() if p else None)
   if not p:break
  row['parents']=chain
  tex=[]
  if isinstance(m,unreal.MaterialInstance):
   for t in m.get_editor_property('texture_parameter_values') or []:
    v=t.get_editor_property('parameter_value')
    tex.append([str(t.get_editor_property('parameter_info').get_editor_property('name')),v.get_path_name() if v else None])
  try:
   for t in unreal.MaterialEditingLibrary.get_used_textures(m):tex.append(['used',t.get_path_name()])
  except Exception as e:row['tex_error']=str(e)
  row['textures']=tex
  cache[k]=row
  return row
 out=[]
 for s in seeds:
  x0,y0,z0,x1,y1,z1=s['box'];hits=[]
  for a in unreal.EditorLevelLibrary.get_all_level_actors():
   for c in a.get_components_by_class(unreal.StaticMeshComponent):
    sm=c.static_mesh
    if not sm:continue
    org,ext,_=unreal.SystemLibrary.get_component_bounds(c)
    if org.x+ext.x<x0 or org.x-ext.x>x1 or org.y+ext.y<y0 or org.y-ext.y>y1 or org.z+ext.z<z0 or org.z-ext.z>z1:continue
    mats=[]
    for i in range(c.get_num_materials()):
     mats.append(mat_row(c.get_material(i)))
    hits.append(dict(actor=a.get_actor_label(),folder=str(a.get_folder_path()),cls=a.get_class().get_name(),component=c.get_name(),
     mesh=sm.get_path_name(),instances=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else None,
     origin=[round(org.x),round(org.y),round(org.z)],extent=[round(ext.x),round(ext.y),round(ext.z)],materials=mats))
  out.append(dict(name=s['name'],box=s['box'],count=len(hits),hits=hits))
 (base/'room-materials.json').write_text(json.dumps(out,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',seeds=len(out),hits=sum(r['count'] for r in out))
]====]
