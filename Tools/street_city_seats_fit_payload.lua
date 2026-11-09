-- Read-only native job: measures every place to sit in UniversityCity (c-conquest 11-04), nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_seats_fit Tools/street_city_seats_fit_payload.lua
-- Sources: places-v1/props.json (baked furniture), the live street bench / bus shelter instances, and the seat parts of
-- the LoverSpot_* recipes in places-v1/actors.json. Tools/build_street_city_places.lua turns the rows into game anchors.
-- A row is one person (grp numbers the object, so a bench's two rows can pair up): seat = the hips (seat surface, middle of the seat), pos = the foot point on the
-- floor she walks to (40 cm in front of the seat, or right under it when the front is blocked), face = world yaw she looks to.
--   chair        straight down onto the seat; the backrest found 38 cm above the seat corrects `face`
--   bench, sofa  seat width and depth from height scans, one row per 58 cm
--   bed          the free long sides, sitting on the edge looking out
--   ring         picnic tables, cafe sets, gazebos, shelters: flat spots at seat height around the object, looking in
-- fit = surface when the seat was hit, nominal when the object has no collision (floor + the kind's usual height).
-- Output: places-v1/seats-fit.json
return [====[
SEAT_OUT=ROOT/'output/street-social-city-production/places-v1'
def motel_world_seats_fit():
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return h if h[0] else None
 def col(x,y,top,bot):
  # every upward-facing surface under (x,y), highest first
  out=[];z=top
  for _ in range(6):
   h=ray(V(x,y,z),V(x,y,bot))
   if not h:break
   p=h[4]
   if h[7].z>.7:out.append(p.z)
   z=p.z-2
   if z<=bot:break
  return out
 def pol(a,r):return math.cos(math.radians(a))*r,math.sin(math.radians(a))*r
 NOM=dict(chair=45,salon_chair=50,bench=45,sofa=42,lounger=35,beach_lounger=35,bed=50,bunk_bed=45,double_bed=50,medical_bed=65)
 rows=[];stats={};G=[0]
 def add(kind,src,x,y,z,face,fit,area=None,fl=None):
  # the floor under the seat is the first surface well below it: the slab under that belongs to the storey below
  if fl is None:
   u=[s for s in col(x,y,z+5,z-130) if s<z-25];fl=u[0] if u else z-45
  fx,fy=pol(face,40);c=col(x+fx,y+fy,fl+60,fl-12)
  if c and abs(c[0]-fl)<15:foot=[x+fx,y+fy,c[0]]
  else:foot=[x,y,fl];k='foot_under';stats[k]=stats.get(k,0)+1
  rows.append(dict(grp=G[0],kind=kind,src=src,pos=[round(v,1) for v in foot],seat=[round(x,1),round(y,1),round(z,1)],face=round(face,1),fit=fit,a=area));k=kind+':'+fit;stats[k]=stats.get(k,0)+1
 def seat_at(x,y,base,lo,hi):
  # (seat z, floor z) straight under (x,y); the lowest surface is the floor, a slab above the seat (a desk) does not count
  c=col(x,y,base+140,base-40)
  if not c:return None,None
  # the object's base is on its floor; a lower surface is the ceiling slab of the storey below
  fl=min(c,key=lambda z:abs(z-base));fl=fl if abs(fl-base)<=15 else c[-1];s=[z for z in c if lo<=z-fl<=hi]
  return (s[-1] if s else None),fl
 def back_of(x,y,z,face):
  # the side with something 38 cm above the seat and nothing opposite it
  hit=[]
  for k in range(8):
   dx,dy=pol(k*45,60);hit.append(bool(ray(V(x,y,z+38),V(x+dx,y+dy,z+38))))
  for k in sorted(range(8),key=lambda k:abs(((k*45-(face+180))+180)%360-180)):
   if hit[k] and not hit[(k+4)%8]:return (k*45+180)%360
  return None
 def span(x,y,z,a,reach):
  # how far the surface at height z runs along yaw a, both ways
  e=[]
  for s in (1,-1):
   d=0
   while d<reach:
    dx,dy=pol(a,s*(d+10));c=col(x+dx,y+dy,z+40,z-30)
    if not c or abs(c[0]-z)>6:break
    d+=10
   e.append(d)
  return e
 def single(t,kind):
  G[0]+=1;x,y,b=t['p'];f=t.get('face') or 0;lo,hi=28,72;z,fl=seat_at(x,y,b,lo,hi)
  if z is None:
   for k in range(8):
    dx,dy=pol(k*45,20);z,fl2=seat_at(x+dx,y+dy,b,lo,hi)
    if z is not None:x,y=x+dx,y+dy;break
  if z is None:add(kind,t.get('n') or kind,x,y,(fl if fl is not None else b)+NOM[kind],f,'nominal',t.get('a'),fl if fl is not None else b);return
  g=back_of(x,y,z,f);add(kind,t.get('n') or kind,x,y,z,g if g is not None else f,'surface',t.get('a'),fl)
 def wide(t,kind,x=None,y=None,b=None,f=None,src=None,nmin=2):
  G[0]+=1;x=t['p'][0] if x is None else x;y=t['p'][1] if y is None else y;b=t['p'][2] if b is None else b;f=(t.get('face') or 0) if f is None else f;a=t.get('a');src=src or t.get('n') or kind
  z,fl=seat_at(x,y,b,28,72)
  if z is None:
   tx,ty=pol(f+90,30);fb=fl if fl is not None else b;add(kind,src,x+tx,y+ty,fb+NOM[kind],f,'nominal',a,fb);add(kind,src,x-tx,y-ty,fb+NOM[kind],f,'nominal',a,fb);return
  g=back_of(x,y,z,f);f=g if g is not None else f
  l,r=span(x,y,z,f+90,170);fr,bk=span(x,y,z,f,90);W=l+r+10
  dx,dy=pol(f,(fr-bk)/2);cx,cy=x+dx,y+dy;n=max(nmin if W>=100 else 1,min(5,int(W/58)));tx,ty=pol(f+90,1)
  for i in range(n):
   o=(l-r)/2+(i-(n-1)/2)*W/n;add(kind,src,cx+tx*o,cy+ty*o,z,f,'surface',a,fl)
 def bed(t,kind):
  G[0]+=1;x,y,b=t['p'];f=t.get('face') or 0;z,fl=seat_at(x,y,b,25,80)
  if z is None:
   for k in range(4):
    dx,dy=pol(f+k*90,60);z,fl=seat_at(x+dx,y+dy,b,25,80)
    if z is not None:x,y=x+dx,y+dy;break
  if z is None:stats['bed_miss']=stats.get('bed_miss',0)+1;return
  a0,a1=span(x,y,z,f,150);b0,b1=span(x,y,z,f+90,150);long_=f if a0+a1>=b0+b1 else f+90;cx,cy=pol(long_,(a0-a1 if long_==f else b0-b1)/2);x,y=x+cx,y+cy;half=(min(a0+a1,b0+b1)+10)/2;got=0
  for s in (90,-90):
   dx,dy=pol(long_+s,half-12);ex,ey=pol(long_+s,half+45)
   c=col(x+ex,y+ey,z+50,fl-10)
   if c and c[0]-fl<15 and not ray(V(x,y,z+25),V(x+ex,y+ey,z+25)):add('bed_edge',kind,x+dx,y+dy,z,long_+s,'surface',t.get('a'),fl);got+=1
  if not got:stats['bed_blocked']=stats.get('bed_blocked',0)+1
 def ring(kind,src,x,y,base,rad,area,outward=False,lo=35,hi=60,cap=8,step=15):
  G[0]+=1;pts=[]
  r=int(rad/step)
  for i in range(-r,r+1):
   for k in range(-r,r+1):
    px,py=x+i*step,y+k*step
    if i*i+k*k>r*r:continue
    c=col(px,py,base+140,base-40)
    if len(c)>=2 and lo<=c[0]-c[-1]<=hi:pts.append((px,py,c[0],c[-1]))
  pts.sort(key=lambda q:-math.hypot(q[0]-x,q[1]-y));keep=[]
  for q in pts:
   if all(math.hypot(q[0]-o[0],q[1]-o[1])>=58 for o in keep):keep.append(q)
   if len(keep)>=cap:break
  for q in keep:
   f=math.degrees(math.atan2(y-q[1],x-q[0]));add(kind,src,q[0],q[1],q[2],f+180 if outward else f,'surface',area,q[3])
  if not keep:stats[kind+'_none']=stats.get(kind+'_none',0)+1
 D=json.loads((SEAT_OUT/'props.json').read_text('utf8'));A=json.loads((SEAT_OUT/'actors.json').read_text('utf8'))['actors'];props=D['props'];by={a['label']:a for a in A}
 # live street benches and shelters: the plan positions in props.json are only their first fit onto the curbs
 live=[]
 for a in SUB.get_all_level_actors():
  tags=[str(t) for t in a.tags];aid=next((t[6:] for t in tags if t.startswith('Asset-')),'')
  if 'StreetScenery-v1' not in tags or aid not in('bench-oak','bench-stone','bus-shelter'):continue
  c=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
  for i in range(c.get_instance_count() if c else 0):
   t=c.get_instance_transform(i,True);live.append((aid,t.translation.x,t.translation.y,t.translation.z,t.rotation.rotator().yaw))
 for aid,x,y,z,yaw in live:
  if aid=='bus-shelter':ring('bus_shelter','公車亭',x,y,z,220,None,False,35,60,3)
  else:wide(dict(p=[x,y,z],face=yaw),'bench',src='街道長椅')
 near=lambda t:any(abs(t['p'][0]-q[1])<200 and abs(t['p'][1]-q[2])<200 for q in live)
 kw=dict(picnic_table=(170,6),cafe_set=(170,4),gazebo=(420,8),pergola=(350,6))
 for t in props:
  k=t['k']
  if k in('chair','salon_chair'):single(t,k)
  elif k=='bench':
   if t['p'][0] or t['p'][1]:
    if not near(t):wide(t,k)
  elif k=='sofa':wide(t,k)
  elif k=='lounger':wide(t,k,nmin=1)
  elif k=='beach_lounger':
   G[0]+=1;x,y,b=t['p'];z,fl=seat_at(x,y,b,20,70);add(k,'躺椅',x,y,(z if z is not None else (fl if fl is not None else b)+35),t.get('face') or 0,'surface' if z is not None else 'nominal',t.get('a'),fl if fl is not None else b)
  elif k in('bed','bunk_bed','double_bed','medical_bed'):bed(t,k)
  elif k in kw:ring(k,t.get('n') or k,t['p'][0],t['p'][1],t['p'][2],kw[k][0],t.get('a'),cap=kw[k][1])
  elif k=='fountain':ring(k,t.get('n') or k,t['p'][0],t['p'][1],t['p'][2],500,t.get('a'),True,step=25,cap=8)
 # stadium tiers: the steps of the sideline stands, a row of seats along each
 tr=next((a for a in A if a.get('mesh','').startswith('SM_Track_SidelineSeats')),None)
 if tr:
  c0,e0=tr['c'],tr['e'];found=0;G[0]+=1
  for ix in range(int((c0[0]-e0[0])//300),int((c0[0]+e0[0])//300)+1):
   for iy in range(int((c0[1]-e0[1])//300),int((c0[1]+e0[1])//300)+1):
    x,y=ix*300.,iy*300.;h=ray(V(x,y,c0[2]+e0[2]+200),V(x,y,c0[2]-e0[2]-200))
    if not h or not h[9] or h[9].get_actor_label()!=tr['label'] or h[4].z<c0[2]-e0[2]+60:continue
    found+=1
    if found<=40:G[0]+=1;add('stand','看台',x,y,h[4].z,0,'surface',None,h[4].z-45)
 # the seat parts of the LoverSpot recipes: exact boxes, the facing from the group's backrest or table
 seen=[];pat=re.compile(r'^(LoverSpot_.*?)_(Stool\d*|Seat[-+]?\d*|Chair[-+]\d*|Bench[-+]\d*|ChairSeat|StoolSeat_\d+|Sofa|SofaBase)$')
 groups={}
 for a in A:
  if a['label'].startswith('LoverSpot_'):groups.setdefault(a['label'].rsplit('_',1)[0],[]).append(a)
 for a in sorted(A,key=lambda q:q['label']):
  m=pat.match(a['label'])
  if not m or re.search('gym_|treadmill',a['label']):continue
  part=m.group(2);x,y=a['c'][0],a['c'][1];z=a['c'][2]+a['e'][2]
  if any(abs(x-o[0])<25 and abs(y-o[1])<25 and abs(z-o[2])<40 for o in seen):continue
  G[0]+=1;seen.append((x,y,z));g=groups.get(m.group(1),[]);sign=re.search(r'[-+]\d*$',part);mate=None
  if sign:mate=next((q for q in g if q['label'].endswith('Back'+sign.group(0))),None)
  back=mate or next((q for q in g if re.search('(Back|SofaBack)$',q['label'])),None)
  f=a.get('yaw') or 0
  if back:f=math.degrees(math.atan2(y-back['c'][1],x-back['c'][0]))
  else:
   tgt=next((q for q in g if re.search('(Table|Desk|Counter|Belt|Top)$',q['label'])),None)
   if tgt:f=math.degrees(math.atan2(tgt['c'][1]-y,tgt['c'][0]-x))
  W=2*max(a['e'][0],a['e'][1]);name=m.group(1)[10:];n=max(1,min(5,int(W/58))) if re.search('Sofa|Bench|Seat$',part) else 1;tx,ty=pol(f+90,1)
  for i in range(n):
   o=(i-(n-1)/2)*W/n;add('lover_seat',name,x+tx*o,y+ty*o,z,f,'surface',None)
 # Tripo benches of the last round have no collision: the two places along the long side, at the usual height
 for a in sorted(A,key=lambda q:q['label']):
  if not re.search(r'^LoverSpot_.*bench_slat_a\d*_Tripo$|hill_Bench_Tripo$',a['label']):continue
  G[0]+=1;x,y,b=a['c'][0],a['c'][1],a['c'][2]-a['e'][2];f=a.get('yaw') or 0;tx,ty=pol(f+90,1)
  if (abs(tx)>abs(ty))!=(a['e'][0]>a['e'][1]):f+=90;tx,ty=pol(f+90,1)
  for o in (-45,45):add('lover_seat',a['label'][10:],x+tx*o,y+ty*o,b+NOM['bench'],f,'nominal',None,b)
 assert sha(MAPFILE)==LOAD_SHA
 (SEAT_OUT/'seats-fit.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,stats=stats,rows=rows),ensure_ascii=False),'utf8')
]====]
