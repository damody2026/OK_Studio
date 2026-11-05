-- Read-only native probe for the whole-world visual gap inventory (nothing is saved to the map).
--   outdoor_scan: 30 m grid over the ground actors' bounds. A ray from the sky passes through small actors (tree canopies,
--   lamps, props: bounds extent < 15 m) until it lands on a large actor (ground, plaza, road, roof). Points inside a
--   building floor actor's footprint are dropped. Per point: ground label/material, whether a player capsule fits
--   above it, and the small actors within 12 m grouped by label prefix (what dresses the spot).
-- Output: output/street-social-city-production/world-gap-v1/outdoor-scan.json
-- Queued with: lua Tools/street_city_motel_job.lua outdoor_scan Tools/street_city_world_gap_payload.lua
return [====[
GAP_OUT=ROOT/'output/street-social-city-production/world-gap-v1'
def motel_outdoor_scan():
 world=unreal.EditorLevelLibrary.get_editor_world();actors=SUB.get_all_level_actors()
 def ray(a,b,ign):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ign,unreal.DrawDebugTrace.NONE,True)
  return r.to_tuple() if r is not None else (False,)+(None,)*11
 info={};floors=[];big=[]
 for a in actors:
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  label=a.get_actor_label();ext=max(e.x,e.y)
  info[label]=(o,e)
  if re.search(r'(^|_)F\d\d$',label) and ext<20000:floors.append((o.x-e.x+100,o.x+e.x-100,o.y-e.y+100,o.y+e.y-100))
  elif ext>=1500 and e.x<400000 and e.y<400000:big.append((label,o,e))
 # scan area: every building floor actor's bounds plus 150 m. The large ground-like actors are not used for this: an
 # activity-space plane far outside the city (ACTSPACE-04-351, 1.9 x 7.5 km) once made 92 % of the grid empty plane.
 x0=min(f[0] for f in floors)-15000;x1=max(f[1] for f in floors)+15000;y0=min(f[2] for f in floors)-15000;y1=max(f[3] for f in floors)+15000
 near_big=[(l,o,e) for l,o,e in big if o.x+e.x>x0 and o.x-e.x<x1 and o.y+e.y>y0 and o.y-e.y<y1]
 top=max(o.z+e.z for _,o,e in near_big)+3000;bot=min(o.z-e.z for _,o,e in near_big)-3000
 step=3000.;pts=[];prefix=lambda s:re.split(r'[_\-\d]',s)[0] or s
 nx,ny=int((x1-x0)//step),int((y1-y0)//step)
 for i in range(nx+1):
  for k in range(ny+1):
   x=x0+i*step;y=y0+k*step
   if any(a<=x<=b and c<=y<=d for a,b,c,d in floors):continue
   ign=[];passed=[];h=None
   for _ in range(8):
    h=ray(unreal.Vector(x,y,top),unreal.Vector(x,y,bot),ign)
    if not h[0] or h[9] is None:break
    lab=h[9].get_actor_label();o,e=info.get(lab,(None,None))
    if e is not None and max(e.x,e.y)<1500:ign.append(h[9]);passed.append(prefix(lab));continue
    break
   if not h or not h[0] or h[9] is None:continue
   lab=h[9].get_actor_label();p=h[4];mat=''
   try:
    comp=h[10]
    if comp is not None:m=comp.get_material(0);mat=m.get_name() if m else ''
   except Exception:pass
   s=unreal.SystemLibrary.sphere_trace_single(world,unreal.Vector(x,y,p.z+100),unreal.Vector(x,y,p.z+101),35.,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
   walk=not (s is not None and s.to_tuple()[0])
   near={}
   r=unreal.SystemLibrary.sphere_overlap_actors(world,unreal.Vector(x,y,p.z+150),1200.,[unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY1,unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY2],unreal.Actor,[])
   # the binding returns either the out array or (bool, out array) depending on the engine build
   for a in ((r[-1] if isinstance(r,tuple) else r) or []):
    l=a.get_actor_label();o,e=info.get(l,(None,None))
    if e is None or max(e.x,e.y)>=1500:continue
    q=prefix(l);near[q]=near.get(q,0)+1
   pts.append(dict(x=round(x),y=round(y),z=round(p.z),ground=lab,ground_prefix=prefix(lab),mat=mat,walk=walk,passed=passed,near=near))
 assert sha(MAPFILE)==LOAD_SHA
 GAP_OUT.mkdir(parents=True,exist_ok=True)
 (GAP_OUT/'outdoor-scan.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,step_cm=step,bounds=[x0,x1,y0,y1],floors=len(floors),points=pts),ensure_ascii=False,indent=1),'utf8')
]====]
