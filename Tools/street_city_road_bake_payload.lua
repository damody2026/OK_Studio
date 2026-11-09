-- Read-only native job on the source map: corrects Content/IndependentResources/StreetSocialData/city_roads.json. The map is not saved.
--   lua Tools/street_city_motel_job.lua world_road_bake Tools/street_city_road_bake_payload.lua
-- The game's own bake (-CityBakeRoads) takes each point's height from 4 m above it, so a point under a roof or a canopy landed on top
-- and its links were tested up there, over the walls he then walked into. Here:
--   points  a point above the street goes back to the ground under it, except on the hill, which is ground; no ground, and its links go
--   links   every link touching a moved point or climbing more than 40 cm is walked in 1 m steps: ground within 40 cm of the last step,
--           room for a 35 cm body at knee and chest height
--   dense   every empty 6 m lattice cell with street-height ground and room to stand gets a point (squares, courtyards)
--   fill    every unlinked pair within 9 m is walked both ways and linked when clear (courtyards the road picture missed)
--   parts   a part cut off from the biggest one is joined by a 1 m flood over the same test, its path added as new points every 6 m
-- Point numbers stay, new ones go at the end. Output: city_roads.json, and places-v1/road-bake.json for the numbers.
return [====[
def motel_world_road_bake():
 import collections,math
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 STREET=1300.;STEP=40.;MIN_PART=2;FLOOD_S=60;FILL_S=6000
 def hit(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return h if h and h[0] else None
 def body(a,b):
  r=unreal.SystemLibrary.sphere_trace_single(world,a,b,35,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return bool(h and h[0])
 def ground(x,y,z):
  h=hit(V(x,y,z+170),V(x,y,z-170))
  return h[4].z if h else None
 def step(x0,y0,z0,x1,y1):
  g=ground(x1,y1,z0)
  if g is None or abs(g-z0)>STEP:return None
  if body(V(x0,y0,z0+60),V(x1,y1,g+60)) or body(V(x0,y0,z0+140),V(x1,y1,g+140)):return None
  return g
 def walk(a,b):
  n=max(1,int(math.hypot(b[0]-a[0],b[1]-a[1])/100+.999));x,y,z=a
  for i in range(1,n+1):
   nx=a[0]+(b[0]-a[0])*i/n;ny=a[1]+(b[1]-a[1])*i/n;g=step(x,y,z,nx,ny)
   if g is None:return False
   x,y,z=nx,ny,g
  return abs(z-b[2])<=STEP
 path=ROOT/'Content/IndependentResources/StreetSocialData/city_roads.json'
 # always from the game's own bake (copied here when it is made), so a rerun does not work on its own output
 source=ROOT/'output/street-social-city-production/places-v1/city_roads-before-bake.json'
 data=json.loads(source.read_text('utf8'));nodes=[list(n) for n in data['nodes']];links=[tuple(l) for l in data['links']]
 # after the lattice come the doors and gates, some of them up a floor on purpose: they keep their height and their links
 lattice=len(json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_places.json').read_text('utf8'))['road']['nodes'])
 moved=set();gone=set();hills=set()
 for i,n in enumerate(nodes[:lattice]):
  if n[2]<=STREET:continue
  # the hill is the one thing above the street that is ground: under its surface lies the old flat ground
  h=hit(V(n[0],n[1],n[2]+60),V(n[0],n[1],n[2]-60))
  if h and h[9] and h[9].get_actor_label().startswith('LoverSpot_R5_hill'):n[2]=h[4].z;hills.add(i);continue
  g=ground(n[0],n[1],1200.)
  if g is None:gone.add(i)
  else:n[2]=g;moved.add(i)
 kept=[];tested=0;cut=0
 for a,b in links:
  if a in gone or b in gone:cut+=1;continue
  if a in moved or b in moved or (a<lattice and b<lattice and abs(nodes[a][2]-nodes[b][2])>STEP):
   tested+=1
   if not walk(nodes[a],nodes[b]):cut+=1;continue
  kept.append((a,b))
 # the picture of the roads draws the campus squares and courtyards as buildings, so neighbours there never got a link and
 # the walk from the department store to MA went round by the southern road, five times the straight line (c-conquest 11-08):
 # every pair of points within 9 m that is not linked is walked, and linked when he gets through
 # and the points themselves: where the picture saw a building or a square there is no point at all. Every empty 6 m cell of
 # the lattice with ground at street height (11.5-13.1 m) and room to stand gets one; walls and closed rooms fail the walk below
 ras=json.loads((ROOT/'output/street-social-city-production/world-edge-v1/road-raster.json').read_text('utf8'))
 ox,oy,st=ras['origin'][0],ras['origin'][1],ras['step_cm']*3;nx_,ny_=len(ras['rows'][0])*ras['step_cm'],len(ras['rows'])*ras['step_cm']
 taken={(round((n[0]-ox)/st),round((n[1]-oy)/st)) for i,n in enumerate(nodes) if i not in gone}
 dense=0
 for gi in range(int(nx_//st)+1):
  for gj in range(int(ny_//st)+1):
   if (gi,gj) in taken:continue
   x,y=ox+gi*st,oy+gj*st;h=hit(V(x,y,1370.),V(x,y,1100.))
   if not h or not(1150<=h[4].z<=1310):continue
   z=h[4].z
   if body(V(x,y,z+60),V(x,y,z+61)) or body(V(x,y,z+140),V(x,y,z+141)):continue
   nodes.append([x,y,z]);dense+=1
 grid=collections.defaultdict(list)
 for i,n in enumerate(nodes):
  if i not in gone:grid[(int(n[0]//900),int(n[1]//900))].append(i)
 have={(min(a,b),max(a,b)) for a,b in kept};added=0;tried=0;stop=time.time()+FILL_S
 for i,n in enumerate(nodes):
  if i in gone or time.time()>stop:continue
  gx,gy=int(n[0]//900),int(n[1]//900)
  for dx in(-1,0,1):
   for dy in(-1,0,1):
    for j in grid[(gx+dx,gy+dy)]:
     if j<=i or (i,j) in have:continue
     m=nodes[j];d=math.hypot(m[0]-n[0],m[1]-n[1])
     if d<1 or d>900 or abs(m[2]-n[2])>120:continue
     tried+=1
     if walk(n,m) and walk(m,n):kept.append((i,j));have.add((i,j));added+=1
 def parts():
  adj=collections.defaultdict(list)
  for a,b in kept:adj[a].append(b);adj[b].append(a)
  seen={};out=[]
  for s in list(adj):
   if s in seen:continue
   seen[s]=len(out);q=[s];p=[s]
   while q:
    for y in adj[q.pop()]:
     if y not in seen:seen[y]=len(out);q.append(y);p.append(y)
   out.append(p)
  out.sort(key=len,reverse=True);return out
 ps=parts();main={(round(nodes[i][0]/100),round(nodes[i][1]/100)):i for i in ps[0]};before=[len(p) for p in ps[:8]]
 joined=0;failed=[]
 for p in ps[1:]:
  if len(p)<MIN_PART:continue
  s0=nodes[p[0]];s=(round(s0[0]/100),round(s0[1]/100));seen={s:s0[2]};par={};q=collections.deque([s]);end=time.time()+FLOOD_S;found=None
  while q and time.time()<end and not found:
   c=q.popleft();z=seen[c]
   for d in ((1,0),(-1,0),(0,1),(0,-1)):
    n=(c[0]+d[0],c[1]+d[1])
    if n in seen:continue
    g=step(c[0]*100.,c[1]*100.,z,n[0]*100.,n[1]*100.)
    if g is None:continue
    seen[n]=g;par[n]=c;q.append(n)
    if n in main:found=n;break
  if not found:failed.append(s0);continue
  w=[];e=found
  while e in par:w.append(e);e=par[e]
  w=w[::-1];last=p[0]
  for k,c in enumerate(w[:-1]):
   if (k+1)%6==0:
    nodes.append([c[0]*100.,c[1]*100.,seen[c]]);kept.append((last,len(nodes)-1));last=len(nodes)-1
  kept.append((last,main[found]));joined+=1
  for i in p:main[(round(nodes[i][0]/100),round(nodes[i][1]/100))]=i
 ps=parts()
 row=lambda n:'[%.1f,%.1f,%.1f]'%tuple(n)
 path.write_text('{"nodes":['+','.join(row(n) for n in nodes)+'],"links":['+','.join('[%d,%d]'%l for l in kept)+']}\n','utf8')
 r=dict(status='passed',points=len(nodes),moved=len(moved),hill=len(hills),gone=len(gone),links=len(kept),tested=tested,cut=cut,dense=dense,fill_tried=tried,filled=added,fill_finished=time.time()<=stop,parts_before=before,joined=joined,failed=failed[:40],failed_count=len(failed),parts_after=[len(p) for p in ps[:8]],highest=max(n[2] for n in nodes))
 (ROOT/'output/street-social-city-production/places-v1/road-bake.json').write_text(json.dumps(r,indent=1),'utf8');return r
]====]
