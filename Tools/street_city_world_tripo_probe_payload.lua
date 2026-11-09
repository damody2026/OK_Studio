-- Read-only native probe before the world-tripo install (nothing is saved to the map):
--   lua Tools/street_city_motel_job.lua world_tripo_probe Tools/street_city_world_tripo_probe_payload.lua
--   ground   20 m grid over the city: hit actor and the material of the hit face, so lawns can be told from paving
--   assets   per streetscape asset: mesh bounds, instance count, sample transforms, the side its upper part leans to
-- Output: output/street-social-city-production/world-tripo-v1/probe.json
return [====[
def motel_world_tripo_probe():
 out=ROOT/'output/street-social-city-production/world-tripo-v1';world=unreal.EditorLevelLibrary.get_editor_world();acts=SUB.get_all_level_actors()
 def lean(mesh):
  try:
   r=unreal.ProceduralMeshLibrary.get_section_from_static_mesh(mesh,0,0);vs=list(r[0])
  except Exception as e:return dict(error=str(e))
  bb=mesh.get_bounding_box();lo,hi=bb.min,bb.max;mid=(lo.z+hi.z)/2;up=[v for v in vs if v.z>mid]
  if not up:return dict(n=len(vs))
  return dict(n=len(vs),dx=sum(v.x for v in up)/len(up)-(lo.x+hi.x)/2,dy=sum(v.y for v in up)/len(up)-(lo.y+hi.y)/2)
 assets={}
 for a in acts:
  tags=[str(t) for t in a.tags]
  if 'StreetScenery-v1' not in tags:continue
  aid=next((t[6:] for t in tags if t.startswith('Asset-')),'?');c=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
  if not c or not c.static_mesh:continue
  q=assets.setdefault(aid,dict(actors=0,instances=0,mesh=c.static_mesh.get_path_name(),collision=str(c.get_collision_profile_name()),visible=c.is_visible(),samples=[]));q['actors']+=1;n=c.get_instance_count();q['instances']+=n
  if 'bounds' not in q:
   bb=c.static_mesh.get_bounding_box();q['bounds']=[[bb.min.x,bb.min.y,bb.min.z],[bb.max.x,bb.max.y,bb.max.z]];q['lean']=lean(c.static_mesh);q['materials']=[m.get_path_name() if m else None for m in c.get_materials()]
  if n and len(q['samples'])<3:
   t=c.get_instance_transform(0,True);r=t.rotation.rotator();q['samples'].append(dict(pos=[t.translation.x,t.translation.y,t.translation.z],yaw=r.yaw,scale=[t.scale3d.x,t.scale3d.y,t.scale3d.z]))
 ground={};pts=[];skip=[]
 for i in range(-20,131):
  for k in range(-20,161):
   x,y=i*1000.,k*1000.
   raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,30000),unreal.Vector(x,y,-5000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
   h=raw.to_tuple() if raw else [False]
   if not h[0]:continue
   lab=h[9].get_actor_label() if h[9] else '?';mat='';comp=h[10];face=h[15] if len(h)>15 else -1
   try:
    r=comp.get_material_from_collision_face_index(face);m=r[0] if isinstance(r,tuple) else r;mat=m.get_name() if m else ''
   except Exception as e:
    if len(skip)<5:skip.append(str(e))
   key=re.split(r'[_\-\d]',lab)[0]+'|'+mat;ground[key]=ground.get(key,0)+1
   if i%2==0 and k%2==0:pts.append([round(x),round(y),round(h[4].z),key])
 assert sha(MAPFILE)==LOAD_SHA
 out.mkdir(parents=True,exist_ok=True)
 (out/'probe.json').write_text(json.dumps(dict(assets=assets,ground=sorted(ground.items(),key=lambda q:-q[1]),errors=skip,points=pts),ensure_ascii=False,indent=1),'utf8')
]====]
