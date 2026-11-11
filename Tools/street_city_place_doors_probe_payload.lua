-- Read-only native job on the source map: what the game's road check (OKStreetCityCheckRoads, -CitySource) will make of some
-- place doors, lift landings and room floors. Nothing is saved.
--   lua Tools/street_city_motel_job.lua world_place_doors Tools/street_city_place_doors_probe_payload.lua
-- Input: output/street-social-city-production/places-v1/place-door-seeds.json
--   { places = [ids], lifts = [[place, anchor name]], floors = [{ name, box = [x0,y0,x1,y1], z, cell }] }
-- For each place, as the game does it: is the door on a floor with room for a body (Fine: ground within 70 up / 120 down,
-- no more than 50 cm above, a 25x60 capsule clear at 105); if not, where the game moves it (rings of 40..400 cm, the same
-- score); how many road points it ties to (lattice points of city_places.json within 15 m, 2 m of height, a 30x60 capsule
-- sweep at 105 clear) and what blocks the nearest ones; then a 50 cm grid walk from that door to the inside spot the game
-- picks (rooms) and to each anchor on the door's floor; and the open spots round the door that would tie to the roads.
-- Lift landings: what stands within 1.5 m of the landing at 105 cm in the four directions. Floors: every 25 cm cell of the
-- box with the game's Fine test, as clear cells. Points ([{ name, pos }]): Fine and the road ties of a candidate door.
-- Probes ([{ name, pos }]): what blocks a body standing there (25x60 capsule at 105) and lines at 60/105/180 cm in eight
-- directions out to 2 m, with the actor's label, mesh, location and bounds.
-- Spots ([{ place, name, candidates = [pos...] }]): walk from the place's door (moved as the game moves it) to each candidate
-- in turn; the first one reached is the answer.
-- Output: places-v1/place-doors.json
return [====[
def motel_world_place_doors():
 import math,collections
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 OBJ=[unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY1]
 base=ROOT/'output/street-social-city-production/places-v1'
 seeds=json.loads((base/'place-door-seeds.json').read_text('utf8'))
 data=json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_places.json').read_text('utf8'))
 lattice=[tuple(n) for n in data['road']['nodes']]
 cells=collections.defaultdict(list)
 for i,n in enumerate(lattice):cells[(int(n[0]//1500),int(n[1]//1500))].append(i)
 def hit(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return h if h and h[0] else None
 def caps(a,b,r,hh):
  x=unreal.SystemLibrary.capsule_trace_single_for_objects(world,a,b,r,hh,OBJ,True,[],NONE,True);h=x.to_tuple() if x else [False]
  return h if h and h[0] else None
 def what(h):
  if not h:return None
  a=h[9];c=h[10];p=h[5];row=dict(at=[round(p.x),round(p.y),round(p.z)],actor=a.get_actor_label() if a else None,component=c.get_name() if c else None)
  try:row['mesh']=c.static_mesh.get_path_name()
  except Exception:pass
  if a:
   try:
    o,e=a.get_actor_bounds(False);l=a.get_actor_location();row['actor_loc']=[round(l.x),round(l.y),round(l.z)]
    row['bounds']=[[round(o.x-e.x),round(o.y-e.y),round(o.z-e.z)],[round(o.x+e.x),round(o.y+e.y),round(o.z+e.z)]];row['path']=a.get_path_name()
   except Exception:pass
   try:row['hidden']=bool(a.get_editor_property('hidden'));row['visible']=bool(c.get_editor_property('visible')) if c else None
   except Exception:pass
  return row
 # the game's Fine(): a floor at the point's height and room for a body
 def fine(x,y,z):
  h=hit(V(x,y,z+70),V(x,y,z-120))
  if not h or h[1] or h[4].z>z+50:return None
  g=h[4].z
  if caps(V(x,y,g+105),V(x,y,g+105.5),25,60):return None
  return g
 def clear(a,b):
  return caps(V(a[0],a[1],a[2]+105),V(b[0],b[1],b[2]+105),30,60)
 def near(p,r=1500.):
  cx,cy=int(p[0]//1500),int(p[1]//1500);out=[]
  for dx in(-1,0,1):
   for dy in(-1,0,1):
    for i in cells.get((cx+dx,cy+dy),()):
     n=lattice[i];d=math.hypot(n[0]-p[0],n[1]-p[1])
     if d<r and abs(n[2]-p[2])<200:out.append((d,i))
  return sorted(out)
 def ties(p,detail=False):
  k=0;blocked=[]
  for d,i in near(p):
   h=clear(p,lattice[i])
   if not h:k+=1
   elif detail and len(blocked)<3:blocked.append(dict(node=i,pos=list(lattice[i]),dist=round(d),hit=what(h)))
  return (k,blocked) if detail else k
 def sees(p):
  for d,i in near(p):
   if not clear(p,lattice[i]):return True
  return False
 def sph(a,b):
  r=unreal.SystemLibrary.sphere_trace_single(world,a,b,35,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return bool(h and h[0])
 def step(x0,y0,z0,x1,y1):
  h=hit(V(x1,y1,z0+170),V(x1,y1,z0-170))
  if not h:return None
  g=h[4].z
  if abs(g-z0)>40:return None
  if sph(V(x0,y0,z0+60),V(x1,y1,g+60)) or sph(V(x0,y0,z0+140),V(x1,y1,g+140)):return None
  return g
 def walk(a,b,pad=800.,C=50.):
  fx,fy,fz=a;tx,ty,tz=b
  if abs(fz-tz)>=150:return dict(reached=None,why='another floor')
  x0,x1=min(fx,tx)-pad,max(fx,tx)+pad;y0,y1=min(fy,ty)-pad,max(fy,ty)+pad
  goal=(round((tx-fx)/C),round((ty-fy)/C));z={(0,0):fz};q=collections.deque([(0,0)]);n=0
  while q and goal not in z and n<8000:
   u=q.popleft();n+=1;ux,uy=fx+u[0]*C,fy+u[1]*C
   for d in((1,0),(-1,0),(0,1),(0,-1),(1,1),(1,-1),(-1,1),(-1,-1)):
    v=(u[0]+d[0],u[1]+d[1])
    if v in z:continue
    vx,vy=fx+v[0]*C,fy+v[1]*C
    if not(x0<=vx<=x1 and y0<=vy<=y1):continue
    g=step(ux,uy,z[u],vx,vy)
    if g is None:continue
    z[v]=g;q.append(v)
  if goal in z:return dict(reached=True,cells=len(z))
  e=min(z,key=lambda k:(fx+k[0]*C-tx)**2+(fy+k[1]*C-ty)**2)
  return dict(reached=False,cells=len(z),closest=[round(fx+e[0]*C),round(fy+e[1]*C)],left=round(math.hypot(fx+e[0]*C-tx,fy+e[1]*C-ty)))
 byid={p['id']:p for p in data['places']}
 def inside(p,door):
  rooms=[r for r in p['rooms'] if r.get('floor',1)<=1]
  if not rooms:return door
  def d2(r):
   cx=min(max(door[0],r['min'][0]),r['max'][0]);cy=min(max(door[1],r['min'][1]),r['max'][1]);return (cx-door[0])**2+(cy-door[1])**2
  r=min(rooms,key=d2);ix=min(max(door[0],r['min'][0]),r['max'][0]);iy=min(max(door[1],r['min'][1]),r['max'][1])
  mx=(r['min'][0]+r['max'][0])/2;my=(r['min'][1]+r['max'][1])/2;L=math.hypot(mx-ix,my-iy)
  if L>1:k=min(180.,L*.5)/L;ix+=(mx-ix)*k;iy+=(my-iy)*k
  return [ix,iy,door[2]]
 out=dict(status='passed',places=[],lifts=[],floors=[])
 for pid in seeds.get('places',[]):
  p=byid.get(pid)
  if not p:out['places'].append(dict(id=pid,why='no such place'));continue
  d=list(p['door']);row=dict(id=pid,door=d);g=fine(*d)
  if g is None:
   mid=d
   if p.get('outdoor') and p['rooms']:r=p['rooms'][0];mid=[(r['min'][0]+r['max'][0])/2,(r['min'][1]+r['max'][1])/2,d[2]]
   best=None
   for R in range(40,401,30):
    for K in range(24):
     t=2*math.pi*K/24;x,y=d[0]+math.cos(t)*R,d[1]+math.sin(t)*R;gg=fine(x,y,d[2])
     if gg is None:continue
     s=R+(2000 if d[2]<1450 and not sees([x,y,gg]) else 0)+(math.hypot(x-mid[0],y-mid[1])*.5 if p.get('outdoor') else 0)
     if not best or s<best[0]:best=(s,[x,y,gg])
   row['fine']=False;row['moved_to']=[round(v) for v in best[1]] if best else None;d=best[1] if best else d
  else:row['fine']=True;d=[d[0],d[1],g]
  k,blocked=ties(d,True);row['ties']=k;row['blocked']=blocked
  if p['rooms'] and not p.get('outdoor'):
   ins=inside(p,d);row['inside']=[round(v) for v in ins];row['in_walk']=walk(d,ins)
  row['anchors']=[]
  for a in p['anchors']:
   if abs(a['pos'][2]-d[2])>=150 or a['name'].startswith(('lift','stair','seat')):continue
   row['anchors'].append(dict(name=a['name'],walk=walk(d,a['pos'])))
  cand=[]
  for R in range(60,1201,60):
   for K in range(16):
    t=2*math.pi*K/16;x,y=d[0]+math.cos(t)*R,d[1]+math.sin(t)*R;gg=fine(x,y,d[2])
    if gg is None:continue
    n=ties([x,y,gg])
    if n:cand.append(dict(pos=[round(x),round(y),round(gg)],ties=n,r=R))
   if len(cand)>=8:break
  row['open_tied_spots']=cand[:8];out['places'].append(row)
  (base/'place-doors.json').write_text(json.dumps(out,indent=1),'utf8')
 for pid,name in seeds.get('lifts',[]):
  p=byid.get(pid);a=next((x for x in (p or {}).get('anchors',[]) if x['name']==name),None)
  if not a:out['lifts'].append(dict(place=pid,name=name,why='no such anchor'));continue
  x,y,z=a['pos'];g=hit(V(x,y,z+60),V(x,y,z-60));z=g[4].z if g else z;row=dict(place=pid,name=name,pos=[x,y,z],dirs={})
  for lab,(dx,dy) in(('+x',(1,0)),('-x',(-1,0)),('+y',(0,1)),('-y',(0,-1))):
   hs=[]
   for hgt in(60,105,180):
    h=hit(V(x,y,z+hgt),V(x+dx*150,y+dy*150,z+hgt))
    hs.append(dict(h=hgt,dist=round(math.hypot(h[4].x-x,h[4].y-y)) if h else None,hit=what(h)))
   row['dirs'][lab]=hs
  out['lifts'].append(row)
 out['points']=[]
 for s in seeds.get('points',[]):
  x,y,z=s['pos'];g=fine(x,y,z);row=dict(name=s['name'],pos=s['pos'],fine=g is not None)
  if g is not None:k,blocked=ties([x,y,g],True);row['ties']=k;row['blocked']=blocked
  out['points'].append(row)
 out['spots']=[]
 for s in seeds.get('spots',[]):
  p=byid.get(s['place']);row=dict(place=s['place'],name=s['name'],tried=[])
  if not p:row['why']='no such place';out['spots'].append(row);continue
  d=list(p['door']);g=fine(*d)
  if g is None:
   best=None
   for R in range(40,401,30):
    for K in range(24):
     t=2*math.pi*K/24;x,y=d[0]+math.cos(t)*R,d[1]+math.sin(t)*R;gg=fine(x,y,d[2])
     if gg is not None and (not best or R<best[0]):best=(R,[x,y,gg])
   d=best[1] if best else d
  else:d=[d[0],d[1],g]
  row['door']=[round(v) for v in d]
  for c in s['candidates']:
   gg=fine(*c);w=walk(d,[c[0],c[1],gg if gg is not None else c[2]]) if gg is not None else dict(reached=False,why='no room for a body')
   row['tried'].append(dict(pos=c,fine=gg is not None,walk=w))
   if w.get('reached'):row['use']=c;break
  out['spots'].append(row)
  (base/'place-doors.json').write_text(json.dumps(out,indent=1),'utf8')
 out['probes']=[]
 for s in seeds.get('probes',[]):
  x,y,z=s['pos'];row=dict(name=s['name'],pos=s['pos'],body=what(caps(V(x,y,z+105),V(x,y,z+105.5),25,60)),rays={})
  for K in range(8):
   t=2*math.pi*K/8;dx,dy=math.cos(t),math.sin(t);hs=[]
   for hgt in(60,105,180):
    h=hit(V(x,y,z+hgt),V(x+dx*200,y+dy*200,z+hgt));hs.append(dict(h=hgt,dist=round(math.hypot(h[4].x-x,h[4].y-y)) if h else None,hit=what(h)))
   row['rays'][str(K*45)]=hs
  out['probes'].append(row)
 for f in seeds.get('floors',[]):
  x0,y0,x1,y1=f['box'];C=f.get('cell',25);z=f['z'];ok=[]
  x=x0
  while x<=x1:
   y=y0
   while y<=y1:
    g=fine(x,y,z)
    if g is not None:ok.append([round(x),round(y),round(g)])
    y+=C
   x+=C
  out['floors'].append(dict(name=f['name'],box=f['box'],cell=C,clear=ok))
 out['status']='passed';(base/'place-doors.json').write_text(json.dumps(out,indent=1),'utf8')
 return dict(status='passed',places=len(out['places']),lifts=len(out['lifts']),floors=len(out['floors']))
]====]
