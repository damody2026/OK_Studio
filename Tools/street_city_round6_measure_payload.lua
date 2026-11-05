-- Read-only native measurements for scene round 3 (c-conquest 8.2.3); nothing is saved to the map:
--   lua Tools/street_city_motel_job.lua world_round_measure Tools/street_city_round6_measure_payload.lua
--   sunk     anchors with no floor within 60 cm under them, with the surfaces in their column
--   walls    each home room's four sides: what the inside and outside rays hit, the ground beyond
--   rooms    actors standing in a few sample rooms
--   s19      the S19 hot spring: actors and a 40 cm height grid (steps and pool depth)
--   roofs    a 2 m height grid on each flat roof, ground heights around each building
-- Seats whose hip point is only estimated (45 cm over the foot point) are measured here too: a flat surface 25-65 cm
-- over the floor within 1 m. Tools/build_street_city_places.lua reads places-v1/seat-measured.json.
-- Output: places-v1/round6-measure.json, places-v1/seat-measured.json
return [====[
def motel_world_round_measure():
 out=ROOT/'output/street-social-city-production/places-v1';world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return h if h[0] else None
 def lab(h):return h[9].get_actor_label() if h[9] else '?'
 def col(x,y,top,bot):
  res=[];t=top
  for _ in range(5):
   h=ray(V(x,y,t),V(x,y,bot))
   if not h:break
   res.append([round(h[4].z,1),lab(h)]);t=h[4].z-2
   if t<=bot:break
  return res
 anchors=json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_anchors.json').read_text('utf8'))['anchors']
 places=json.loads((out/'places.json').read_text('utf8'))['places']
 sunk=[]
 for r in anchors:
  x,y,z=r['pos']
  if ray(V(x,y,z+5),V(x,y,z-60)):continue
  near=None
  if True:
   for rad in range(60,481,60):
    for k in range(8):
     px,py=x+rad*math.cos(k*math.pi/4),y+rad*math.sin(k*math.pi/4);h=ray(V(px,py,z+30),V(px,py,z-30))
     if h and h[7].z>.8:near=[round(px,1),round(py,1),round(h[4].z,1)];break
    if near:break
  sunk.append(dict(id=r.get('id'),name=r.get('name'),place=r.get('place'),kinds=r['kinds'][:6],pos=r.get('raw') or r['pos'],near=near,col=col(x,y,z+300,z-800)))
 walls=[]
 for p in places:
  rm=p.get('room');b=str(p.get('building') or '')
  if not rm or 'min' not in rm or not re.match('^(R1|R2|H1|D[1-4]|S[0-9]+)$',b):continue
  lo,hi=rm['min'],rm['max'];c=[(lo[0]+hi[0])/2,(lo[1]+hi[1])/2];z=lo[2];row=dict(id=p['id'],building=b,kind=p['kind'],min=lo,max=hi,sides={})
  for nm,dx,dy,half in (('n',1,0,(hi[0]-lo[0])/2),('s',-1,0,(hi[0]-lo[0])/2),('e',0,1,(hi[1]-lo[1])/2),('w',0,-1,(hi[1]-lo[1])/2)):
   s={}
   for hh in (30,120,200):
    h=ray(V(c[0],c[1],z+hh),V(c[0]+dx*(half+500),c[1]+dy*(half+500),z+hh))
    s['in%d'%hh]=[round((h[4]-V(c[0],c[1],z+hh)).length()-half),lab(h)] if h else None
   q=V(c[0]+dx*(half+500),c[1]+dy*(half+500),z+120);h=ray(q,V(c[0],c[1],z+120))
   s['out']=[round(500-(h[4]-q).length()),lab(h)] if h else None
   h=ray(V(c[0]+dx*(half+150),c[1]+dy*(half+150),z+150),V(c[0]+dx*(half+150),c[1]+dy*(half+150),z-3000))
   s['down']=[round(h[4].z),lab(h)] if h else None
   row['sides'][nm]=s
  walls.append(row)
 acts=[]
 for a in SUB.get_all_level_actors():
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  if max(e.x,e.y)>30000:continue
  c=a.get_component_by_class(unreal.StaticMeshComponent)
  acts.append(dict(label=a.get_actor_label(),mesh=c.static_mesh.get_name() if c and c.static_mesh else '',cls=a.get_class().get_name(),lo=[round(o.x-e.x),round(o.y-e.y),round(o.z-e.z)],hi=[round(o.x+e.x),round(o.y+e.y),round(o.z+e.z)]))
 def inside(lo,hi):return [q for q in acts if q['hi'][0]>=lo[0] and q['lo'][0]<=hi[0] and q['hi'][1]>=lo[1] and q['lo'][1]<=hi[1] and q['hi'][2]>=lo[2] and q['lo'][2]<=hi[2]][:200]
 rooms={}
 byid={p['id']:p for p in places}
 for rid in ('r1-0201','h1-0301','s20-0201','s05-0201','d1-0201','d3-0201'):
  p=byid.get(rid)
  if p and (p.get('room') or {}).get('min'):
   lo,hi=p['room']['min'],p['room']['max'];rooms[rid]=inside([lo[0]-150,lo[1]-150,lo[2]],[hi[0]+150,hi[1]+150,hi[2]])
 s19=byid['s19-0101']['room'];lo,hi=s19['min'],s19['max'];grid=[];x=lo[0]
 while x<=hi[0]:
  y=lo[1]
  while y<=hi[1]:
   h=ray(V(x,y,lo[2]+300),V(x,y,lo[2]-300))
   if h:grid.append([round(x),round(y),round(h[4].z,1),lab(h)])
   y+=40
  x+=40
 roofs={}
 for b,(x0,y0,x1,y1) in dict(T1=(61500,49468,66500,56531),T2=(74500,67468,79500,74531),T4=(61500,41468,66500,48531),LI=(55500,58268,60500,66731),D1=(90700,31968,95700,42031),D2=(90700,55968,95700,66031)).items():
  rows=[];x=x0
  while x<=x1:
   y=y0
   while y<=y1:
    h=ray(V(x,y,9000),V(x,y,1000))
    if h:rows.append([round(x),round(y),round(h[4].z),lab(h)])
    y+=200
   x+=200
  ring=[]
  for off in (120,420):
   for k in range(int((x1-x0)/200)+1):
    for y in (y0-off,y1+off):
     h=ray(V(x0+k*200,y,3000),V(x0+k*200,y,900));ring.append([x0+k*200,y,round(h[4].z) if h else None,lab(h) if h else None])
   for k in range(int((y1-y0)/200)+1):
    for x in (x0-off,x1+off):
     h=ray(V(x,y0+k*200,3000),V(x,y0+k*200,900));ring.append([x,y0+k*200,round(h[4].z) if h else None,lab(h) if h else None])
  roofs[b]=dict(top=rows,ring=ring)
 (out/'round6-measure.json').write_text(json.dumps(dict(sunk=sunk,walls=walls,rooms=rooms,s19=dict(actors=inside([lo[0],lo[1],lo[2]-300],[hi[0],hi[1],hi[2]]),grid=grid),roofs=roofs),ensure_ascii=False),'utf8')
 seats=[];miss=[]
 for r in anchors:
  s=r.get('seat_pos')
  if not s:continue
  x,y,z=r['pos']
  if abs(s[0]-x)>.2 or abs(s[1]-y)>.2 or abs(s[2]-z-45)>.3:continue
  best=None
  for rad in (0,25,50,75,100):
   for k in range(8 if rad else 1):
    px,py=x+rad*math.cos(k*math.pi/4),y+rad*math.sin(k*math.pi/4);h=ray(V(px,py,z+85),V(px,py,z+20))
    if h and h[7].z>.8 and 25<=h[4].z-z<=65:best=[round(px,1),round(py,1),round(h[4].z,1)];break
   if best:break
  if best:seats.append(dict(id=r.get('id'),seat=best))
  else:miss.append(dict(id=r.get('id'),place=r.get('place'),name=r.get('name'),kinds=r['kinds'][:5],pos=r['pos']))
 (out/'seat-measured.json').write_text(json.dumps(dict(measured=seats,unmeasured=miss),ensure_ascii=False),'utf8')
 return dict(status='passed',sunk=len(sunk),walls=len(walls),seats=len(seats),unmeasured=len(miss))
def motel_world_round_transect():
 # lines across the beach and the canal banks: height, actor and material every 25 cm, and what stands over the water sheet
 out=ROOT/'output/street-social-city-production/places-v1';world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return h if h[0] else None
 rows={}
 def line(name,x0,y0,x1,y1,step=25):
  n=int(math.hypot(x1-x0,y1-y0)/step);res=[]
  for i in range(n+1):
   x,y=x0+(x1-x0)*i/n,y0+(y1-y0)*i/n;h=ray(V(x,y,3500),V(x,y,300))
   res.append([round(x),round(y),round(h[4].z,1) if h else None,h[9].get_actor_label() if h and h[9] else None])
  rows[name]=res
 for y in (12000,21000,30000,39000,48000,60000,72000):line('sea%d'%y,8000,y,24000,y)
 for x in (35000,50000,70000,95000):line('canal%d'%x,x,80000,x,100000,50)
 line('lake',82500,76300,89500,76300);line('lake2',85800,73500,85800,79000)
 sea=[]
 for a in SUB.get_all_level_actors():
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  if o.x-e.x<16000 and o.z+e.z>850 and o.z-e.z<1200 and o.y+e.y>0 and max(e.x,e.y)<60000:
   c=a.get_component_by_class(unreal.StaticMeshComponent)
   sea.append([a.get_actor_label(),c.static_mesh.get_name() if c and c.static_mesh else '',round(o.x-e.x),round(o.y-e.y),round(o.z-e.z),round(o.x+e.x),round(o.y+e.y),round(o.z+e.z)])
 (out/'round6-transect.json').write_text(json.dumps(dict(lines=rows,sea=sea),ensure_ascii=False),'utf8')
 return dict(status='passed',sea=len(sea))
]====]
