-- Read-only native job: what blocks a walker at given points? Nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_blocker_probe Tools/street_city_blocker_probe_payload.lua
-- Input: output/street-social-city-production/places-v1/blocker-seeds.json ([[x0,y0,x1,y1,z],...]: a 35 cm sphere swept
-- from (x0,y0,z) to (x1,y1,z), the game's walker radius). Output: places-v1/blocker-probe.json with the hit actor (label,
-- folder), component, mesh and, for an instanced component, the instance index and its location.
return [====[
def motel_world_blocker_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 base=ROOT/'output/street-social-city-production/places-v1'
 out=[]
 for x0,y0,x1,y1,z in json.loads((base/'blocker-seeds.json').read_text('utf8')):
  r=unreal.SystemLibrary.sphere_trace_single(world,V(x0,y0,z),V(x1,y1,z),35,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  row=dict(seed=[x0,y0,x1,y1,z],hit=bool(h and h[0]))
  if row['hit']:
   a=h[9];c=h[10];p=h[5]
   row.update(at=[p.x,p.y,p.z],actor=a.get_actor_label() if a else None,folder=str(a.get_folder_path()) if a else None,cls=a.get_class().get_name() if a else None,
    component=c.get_name() if c else None,ccls=c.get_class().get_name() if c else None,item=h[13])
   try:row['mesh']=c.static_mesh.get_path_name()
   except Exception:pass
   if c and isinstance(c,unreal.InstancedStaticMeshComponent) and h[13]>=0:
    t=c.get_instance_transform(h[13],True);row['instance_loc']=[t.translation.x,t.translation.y,t.translation.z]
  out.append(row)
 (base/'blocker-probe.json').write_text(json.dumps(out,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',rows=len(out),hits=sum(1 for r in out if r['hit']))
]====]
