-- Read-only native job: can a person really walk from a point to the game's road graph? Nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_gate_probe Tools/street_city_gate_probe_payload.lua
-- Seeds come from output/street-social-city-production/places-v1/gate-seeds.json ([[x,y],...]). From each seed a 1 m flood walks
-- the ground: a step needs ground within 40 cm of height and room for a 35 cm radius body on the straight line. It stops
-- at the first node of city_places.json (the biggest connected part, so reaching one means connected).
-- Output: places-v1/gate-probe.json
return [====[
def motel_world_gate_probe():
 import collections
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def hit(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return h if h and h[0] else None
 def body(a,b):
  r=unreal.SystemLibrary.sphere_trace_single(world,a,b,35,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return bool(h and h[0])
 def ground(x,y,z):
  h=hit(V(x,y,z+170),V(x,y,z-170))
  return h[4].z if h else None
 base=ROOT/'output/street-social-city-production/places-v1'
 nodes={(round(p[0]/100),round(p[1]/100)) for p in json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_places.json').read_text('utf8'))['road']['nodes']}
 out=[]
 for sx,sy in json.loads((base/'gate-seeds.json').read_text('utf8')):
  z0=None
  for dz in (1200,1300,1500):
   z0=ground(sx,sy,dz)
   if z0 is not None:break
  row=dict(seed=[sx,sy],ground=z0,cells=0,reached=None,box=None)
  if z0 is not None:
   s=(round(sx/100),round(sy/100));seen={s:z0};par={};q=collections.deque([s]);end=time.time()+180;lo=[s[0],s[1]];hi=[s[0],s[1]]
   while q and time.time()<end and not row['reached']:
    c=q.popleft();z=seen[c];row['cells']+=1
    if c in nodes and row['cells']>1:
     row['reached']=[c[0]*100,c[1]*100,z];w=[];e=c
     while e in par:w.append([e[0]*100,e[1]*100,seen[e]]);e=par[e]
     row['path']=w[::-1];break
    for d in ((1,0),(-1,0),(0,1),(0,-1)):
     n=(c[0]+d[0],c[1]+d[1])
     if n in seen:continue
     g=ground(n[0]*100,n[1]*100,z)
     if g is None or abs(g-z)>40:continue
     a=V(c[0]*100,c[1]*100,z);b=V(n[0]*100,n[1]*100,g)
     if body(V(a.x,a.y,z+60),V(b.x,b.y,g+60)) or body(V(a.x,a.y,z+140),V(b.x,b.y,g+140)):continue
     seen[n]=g;par[n]=c;q.append(n);lo=[min(lo[0],n[0]),min(lo[1],n[1])];hi=[max(hi[0],n[0]),max(hi[1],n[1])]
   row['box']=[lo[0]*100,lo[1]*100,hi[0]*100,hi[1]*100];row['exhausted']=not q and not row['reached']
  out.append(row)
 (base/'gate-probe.json').write_text(json.dumps(out,indent=1),'utf8')
 return dict(status='passed',rows=len(out))
]====]
