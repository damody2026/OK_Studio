-- Read-only native job for the end of scene round 3 (c-conquest 8.2.4); nothing is saved to the map:
--   lua Tools/street_city_motel_job.lua world_round_sites Tools/street_city_round6_sites_payload.lua
--   walk      every anchor moved by places-v1/anchor-ground.json: floor under it, room for a person (44 x 44 x 140 cm box
--             from 25 cm over the floor), and the nearest clear spot within 1.5 m when it is blocked
--   minshuku  walkable 1 m cells on the three real S18 floors, outside the motel suites
--   nets      goals, nets and umpire chairs: actors and instances, and the actors of the south sports area
-- Output: places-v1/round6-sites.json
return [====[
def motel_world_round_sites():
 out=ROOT/'output/street-social-city-production/places-v1';world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return h if h[0] else None
 def clear(x,y,z):
  mid=V(x,y,z+95);r=unreal.SystemLibrary.box_trace_single(world,mid,mid+V(0,0,1),V(22,22,70),unreal.Rotator(0,0,0),Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return (not h[0]),(h[9].get_actor_label() if h[0] and h[9] else None)
 def floor(x,y,z):
  h=ray(V(x,y,z+40),V(x,y,z-30));return h[4].z if h and h[7].z>.8 else None
 ground=json.loads((out/'anchor-ground.json').read_text('utf8'));walk=[];bad=0
 for k,to in ground.items():
  x,y,z=to;f=floor(x,y,z);ok,who=clear(x,y,z if f is None else f);fix=None
  if f is None or not ok:
   bad+=1
   for rad in range(30,151,30):
    for q in range(12):
     px,py=x+rad*math.cos(q*math.pi/6),y+rad*math.sin(q*math.pi/6);g=floor(px,py,z)
     if g is not None and abs(g-z)<=25 and clear(px,py,g)[0]:fix=[round(px,1),round(py,1),round(g,1)];break
    if fix:break
  walk.append(dict(key=k,to=to,floor=f,clear=ok,by=who,fix=fix))
 cells={}
 for lv in (1206,1646,2086):
  rows=[];x=46000
  while x<=50000:
   y=49140
   while y<=52340:
    if not (48840<=x<=50360 and 49700<=y<=51780):
     g=floor(x,y,lv)
     if g is not None and abs(g-lv)<=25 and clear(x,y,g)[0]:rows.append([x,y,round(g,1)])
    y+=100
   x+=100
  cells[str(lv)]=rows
 nets=[];south=[]
 for a in SUB.get_all_level_actors():
  lb=a.get_actor_label();c=a.get_component_by_class(unreal.StaticMeshComponent);m=c.static_mesh.get_name() if c and c.static_mesh else ''
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  if re.search('soccer_goal|umpire|tennis|volley|badminton|_net|net_|goal',(lb+' '+m).lower()):
   ic=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
   inst=[[round(v) for v in (t.x,t.y,t.z)] for t in [ic.get_instance_transform(i,True).translation for i in range(ic.get_instance_count())]] if ic else []
   nets.append(dict(label=lb,mesh=m,c=[round(o.x),round(o.y),round(o.z)],e=[round(e.x),round(e.y),round(e.z)],inst=inst))
  if 40000<o.x<105000 and 105000<o.y<150000 and max(e.x,e.y)<4000:south.append([lb,m,round(o.x),round(o.y),round(o.z),round(e.x),round(e.y),round(e.z)])
 (out/'round6-sites.json').write_text(json.dumps(dict(walk=walk,minshuku=cells,nets=nets,south=south[:400]),ensure_ascii=False),'utf8')
 return dict(status='passed',walk=len(walk),blocked=bad,fixed=sum(1 for w in walk if w['fix']),cells={k:len(v) for k,v in cells.items()},nets=len(nets))
def motel_world_round_stairs():
 # every tread of the six fire stairs: a person-sized box over it must be free, the ground under the first tread within 30 cm
 out=ROOT/'output/street-social-city-production/places-v1';world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 res={}
 for a in SUB.get_all_level_actors():
  m=re.match(r'LoverSpot_R5_(\w+)Stair_(\d+)$',a.get_actor_label())
  if not m:continue
  o,e=a.get_actor_bounds(False);z=o.z+e.z;row=res.setdefault(m.group(1),dict(treads=0,blocked=[],first=None));row['treads']+=1
  mid=V(o.x,o.y,z+95);r=unreal.SystemLibrary.box_trace_single(world,mid,mid+V(0,0,1),V(20,20,70),unreal.Rotator(0,0,0),Q,True,[],N,True);h=r.to_tuple() if r else [False]
  if h[0]:row['blocked'].append([int(m.group(2)),h[9].get_actor_label() if h[9] else '?',round(h[4].x),round(h[4].y),round(h[4].z)])
  if int(m.group(2))==1:
   g=unreal.SystemLibrary.line_trace_single(world,V(o.x,o.y,z-12),V(o.x,o.y,z-120),Q,True,[],N,True).to_tuple();row['first']=[round(z),round(g[4].z) if g[0] else None]
 (out/'round6-stairs.json').write_text(json.dumps(res,ensure_ascii=False),'utf8')
 return dict(status='passed',stairs={k:(v['treads'],len(v['blocked']),v['first']) for k,v in res.items()})
def motel_world_round_courts():
 # height map of the stadium annex and the campus track: nets and goals are merged into those meshes, thin raised lines find them
 out=ROOT/'output/street-social-city-production/places-v1';world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def top(x,y):
  r=unreal.SystemLibrary.line_trace_single(world,V(x,y,2600),V(x,y,1000),Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return round(h[4].z) if h[0] else 0
 res={}
 for name,(x0,y0,x1,y1) in dict(stadium=(58000,119000,96800,135000),track=(55000,20000,66600,40000)).items():
  rows=[];x=x0
  while x<=x1:
   rows.append([top(x,y) for y in range(y0,y1+1,100)]);x+=100
  res[name]=dict(x0=x0,y0=y0,step=100,rows=rows)
 (out/'round6-courts.json').write_text(json.dumps(res),'utf8')
 return dict(status='passed')
]====]
