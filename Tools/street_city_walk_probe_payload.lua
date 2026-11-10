-- Read-only native job: can a walker get from one point to another on the source map? Nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_walk_probe Tools/street_city_walk_probe_payload.lua
-- Input: output/street-social-city-production/places-v1/walk-seeds.json, a list of
--   { name, from = [x,y,z], to = [x,y,z], box = [x0,y0,x1,y1] (search area), cell = cm (default 50) }
-- (z = the floor). A breadth-first walk over a lattice of `cell`, each step tested like the road bake
-- (Tools/street_city_road_bake_payload.lua): ground within 40 cm of the last step, room for a 35 cm body at 60 and 140 cm.
-- Output: places-v1/walk-probe.json per seed: reached, the walked length, the path (every 4th point), and when it fails the
-- reached cell nearest the goal with what a sweep from there to the goal hits (actor label, folder, mesh, component).
return [====[
def motel_world_walk_probe():
 import math,collections
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 STEP=40.
 def hit(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return h if h and h[0] else None
 def sweep(a,b):
  r=unreal.SystemLibrary.sphere_trace_single(world,a,b,35,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return h if h and h[0] else None
 def ground(x,y,z):
  h=hit(V(x,y,z+170),V(x,y,z-170))
  return h[4].z if h else None
 def step(x0,y0,z0,x1,y1):
  g=ground(x1,y1,z0)
  if g is None or abs(g-z0)>STEP:return None
  if sweep(V(x0,y0,z0+60),V(x1,y1,g+60)) or sweep(V(x0,y0,z0+140),V(x1,y1,g+140)):return None
  return g
 def what(h):
  if not h:return None
  a=h[9];c=h[10];p=h[5];row=dict(at=[round(p.x),round(p.y),round(p.z)],actor=a.get_actor_label() if a else None,folder=str(a.get_folder_path()) if a else None,
   cls=a.get_class().get_name() if a else None,component=c.get_name() if c else None)
  try:row['mesh']=c.static_mesh.get_path_name()
  except Exception:pass
  if c and isinstance(c,unreal.InstancedStaticMeshComponent) and h[13]>=0:
   t=c.get_instance_transform(h[13],True);row['instance_loc']=[round(t.translation.x),round(t.translation.y),round(t.translation.z)]
  return row
 base=ROOT/'output/street-social-city-production/places-v1'
 out=[]
 for s in json.loads((base/'walk-seeds.json').read_text('utf8')):
  C=float(s.get('cell',50));fx,fy,fz=s['from'];tx,ty,tz=s['to'];x0,y0,x1,y1=s['box']
  g0=ground(fx,fy,fz);row=dict(name=s['name'],start_ground=g0)
  if g0 is None:row['reached']=False;row['why']='no ground at the start';out.append(row);continue
  def key(x,y):return (round((x-fx)/C),round((y-fy)/C))
  start=(0,0);goal=key(tx,ty);z={start:g0};prev={start:None};q=collections.deque([start]);n=0
  while q and goal not in z and n<int(s.get('max',40000)):
   u=q.popleft();n+=1;ux,uy=fx+u[0]*C,fy+u[1]*C
   for d in((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
    v=(u[0]+d[0],u[1]+d[1])
    if v in z:continue
    vx,vy=fx+v[0]*C,fy+v[1]*C
    if not(x0<=vx<=x1 and y0<=vy<=y1):continue
    g=step(ux,uy,z[u],vx,vy)
    if g is None:continue
    z[v]=g;prev[v]=u;q.append(v)
  row['cells']=len(z);row['reached']=goal in z
  end=goal if goal in z else min(z,key=lambda k:(fx+k[0]*C-tx)**2+(fy+k[1]*C-ty)**2)
  path=[];k=end
  while k is not None:path.append([round(fx+k[0]*C),round(fy+k[1]*C),round(z[k])]);k=prev[k]
  path.reverse();row['walked']=round(sum(math.hypot(path[i][0]-path[i-1][0],path[i][1]-path[i-1][1]) for i in range(1,len(path))))
  row['straight']=round(math.hypot(tx-fx,ty-fy));row['path']=path[::4]+([path[-1]] if len(path)%4!=1 else [])
  xs=[fx+k[0]*C for k in z];ys=[fy+k[1]*C for k in z];row['reached_box']=[round(min(xs)),round(min(ys)),round(max(xs)),round(max(ys))]
  if goal not in z:
   ex,ey,ez=path[-1];row['nearest']=path[-1];row['gap']=round(math.hypot(tx-ex,ty-ey))
   row['blocked_by']=[what(sweep(V(ex,ey,ez+h),V(tx,ty,ez+h))) for h in(60,140)]
  out.append(row)
  (base/'walk-probe.json').write_text(json.dumps(out,indent=1,ensure_ascii=False),'utf8')
 (base/'walk-probe.json').write_text(json.dumps(out,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',seeds=len(out),reached=sum(1 for r in out if r.get('reached')))
]====]
