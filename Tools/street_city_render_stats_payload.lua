-- Read-only native job: what the renderer has to draw. Nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_render_stats Tools/street_city_render_stats_payload.lua
-- Output: places-v1/render-stats.json
--   meshes  per static mesh: actors and instances using it, LOD count, LOD0 vertices, material sections
--   lights  every point, spot and rect light: class, position, intensity, radius, shadow
return [====[
def motel_world_render_stats():
 SML=unreal.EditorStaticMeshLibrary;meshes={};lights=[];comp_n=0
 def add(m,label,n,pos):
  k=m.get_path_name();e=meshes.get(k)
  if e is None:
   try:v=SML.get_number_verts(m,0);l=SML.get_lod_count(m);s=m.get_num_sections(0)
   except Exception:v=l=s=-1
   e=meshes[k]=dict(mesh=k,actors=0,instances=0,lods=l,verts=v,sections=s,sample=label,pos=pos)
  e['actors']+=1;e['instances']+=n
 for a in unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors():
  p=a.get_actor_location();pos=[round(p.x),round(p.y),round(p.z)];lab=a.get_actor_label()
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh
   if not m:continue
   comp_n+=1;n=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else 1
   add(m,lab,n,pos)
  if isinstance(a,(unreal.PointLight,unreal.SpotLight,unreal.RectLight)):
   c=a.light_component
   lights.append(dict(label=lab,cls=a.get_class().get_name(),pos=pos,intensity=c.get_editor_property('intensity'),units=str(c.get_editor_property('intensity_units')),radius=c.get_editor_property('attenuation_radius'),shadow=c.get_editor_property('cast_shadows'),mobility=str(c.get_editor_property('mobility'))))
 o=ROOT/'output/street-social-city-production/places-v1/render-stats.json'
 o.write_text(json.dumps(dict(components=comp_n,meshes=sorted(meshes.values(),key=lambda e:-e['instances']*max(e['verts'],0)),lights=lights),indent=0),'utf8')
 return dict(status='passed',meshes=len(meshes),lights=len(lights))
]====]
