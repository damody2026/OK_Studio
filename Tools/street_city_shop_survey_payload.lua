-- Read-only native probes for the shop-street work (nothing is saved).
--   shop_probe: every S??_F?? shop-floor actor's transform and world bounds.
--   shop_slots: material slots of the sample shops' floor meshes (slot name, mesh material, component material).
-- Queued with: lua Tools/street_city_motel_job.lua shop_probe|shop_slots Tools/street_city_shop_survey_payload.lua
return [====[
SURVEY_OUT=ROOT/'output/street-social-city-production/shop-survey-v1'
def motel_shop_probe():
 rows=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label()
  if not re.match(r'^S\d\d_F\d\d$',label):continue
  o,e=a.get_actor_bounds(False);t=a.get_actor_transform();r=a.get_actor_rotation()
  rows.append(dict(actor=label,building=label[:3],floor=int(label[5:]),location=num(t.translation),yaw=float(r.yaw),scale=num(t.scale3d),bounds_origin=num(o),bounds_extent=num(e)))
 rows.sort(key=lambda r:r['actor'])
 assert sha(MAPFILE)==LOAD_SHA
 SURVEY_OUT.mkdir(parents=True,exist_ok=True)
 (SURVEY_OUT/'shop-probe.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,actors=rows),ensure_ascii=False,indent=2),'utf8')

def motel_city_probe():
 # every building floor actor (<building>_F<nn>) in the city, for the whole-city interior inventory captures
 rows=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label();m=re.match(r'^([A-Z][A-Z0-9]{0,4})_F(\d\d)$',label)
  if not m:continue
  o,e=a.get_actor_bounds(False);t=a.get_actor_transform();r=a.get_actor_rotation()
  rows.append(dict(actor=label,building=m.group(1),floor=int(m.group(2)),location=num(t.translation),yaw=float(r.yaw),bounds_origin=num(o),bounds_extent=num(e),hidden=bool(a.is_hidden_ed())))
 rows.sort(key=lambda r:r['actor']);assert sha(MAPFILE)==LOAD_SHA
 # naming survey of everything else: label prefix (up to the first '_') -> count, plus labels that carry a floor token
 pre={};floorish=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label();k=label.split('_')[0];pre[k]=pre.get(k,0)+1
  if re.search(r'(^|_)F\d\d($|_)',label) and not re.match(r'^S\d\d_F\d\d$',label) and len(floorish)<3000:
   o,e=a.get_actor_bounds(False);floorish.append(dict(actor=label,cls=a.get_class().get_name(),folder=str(a.get_folder_path()),bounds_origin=num(o),bounds_extent=num(e)))
 SURVEY_OUT.mkdir(parents=True,exist_ok=True)
 (SURVEY_OUT/'city-probe.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,actors=rows,prefixes=dict(sorted(pre.items(),key=lambda kv:-kv[1])),floorish=floorish),ensure_ascii=False,indent=2),'utf8')

def motel_city_room_views():
 # Camera points inside actual rooms of every non-shop floor, found from the built geometry (not the old layout manifest):
 # 2.5 m grid at eye height; a point counts as in-room when 8 horizontal rays all hit a wall within 1.2..14 m.
 # Greedy pick by openness with 6 m separation, up to 6 per floor; look along the longest ray.
 probe=json.loads((SURVEY_OUT/'city-probe.json').read_text('utf8'));world=unreal.EditorLevelLibrary.get_editor_world()
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  return r.to_tuple() if r is not None else (False,)+(None,)*11
 out=[];dirs=[(math.cos(k*math.pi/4),math.sin(k*math.pi/4)) for k in range(8)]
 for f in probe['floorish']:
  if f['cls']!='StaticMeshActor':continue
  o,e=f['bounds_origin'],f['bounds_extent'];zb=o[2]-e[2];cands=[]
  nx,ny=max(1,int((2*e[0]-200)//250)),max(1,int((2*e[1]-200)//250))
  for i in range(nx+1):
   for k in range(ny+1):
    x=o[0]-e[0]+100+i*(2*e[0]-200)/max(1,nx);y=o[1]-e[1]+100+k*(2*e[1]-200)/max(1,ny)
    h=ray(unreal.Vector(x,y,zb+200),unreal.Vector(x,y,zb-60))
    if not h[0] or h[4].z>zb+40:continue
    z=h[4].z+160;ds=[]
    # a point inside a thick wall or column sees through back faces: drop anything the pawn's width overlaps
    s=unreal.SystemLibrary.sphere_trace_single(world,unreal.Vector(x,y,z),unreal.Vector(x,y,z-1),30.,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
    if s is not None and s.to_tuple()[0]:continue
    for (dx,dy) in dirs:
     t=ray(unreal.Vector(x,y,z),unreal.Vector(x+dx*1400,y+dy*1400,z));ds.append(((t[4]-unreal.Vector(x,y,z)).length() if t[0] else 1e9))
    if min(ds)<120 or max(ds)>1400:continue
    cands.append((sum(ds)/8,x,y,z,ds))
  cands.sort(reverse=True);pick=[]
  for c in cands:
   if all((c[1]-p[1])**2+(c[2]-p[2])**2>600**2 for p in pick):pick.append(c)
   if len(pick)>=6:break
  for n,(op,x,y,z,ds) in enumerate(pick):
   k=max(range(8),key=lambda i:ds[i]);dx,dy=dirs[k];L=min(ds[k],1200)
   out.append(dict(id=f['actor']+'-r%d'%(n+1),eye=[x-dx*80,y-dy*80,z],target=[x+dx*L,y+dy*L,z-70],fov=88,hour=21,openness_cm=op))
 assert sha(MAPFILE)==LOAD_SHA
 (SURVEY_OUT/'city-room-views.json').write_text(json.dumps(out,ensure_ascii=False,indent=1),'utf8')

def motel_city_view_check():
 # For every in-room view: what the visibility ray (eye -> target) hits first, line vs pawn capsule.
 # A view that shows a wall at close range while the ray runs on means a rendered wall without collision.
 views=json.loads((SURVEY_OUT/'city-room-views.json').read_text('utf8'));world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 for v in views:
  a=unreal.Vector(*v['eye']);b=unreal.Vector(*v['target'])
  r=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  t=r.to_tuple() if r is not None else (False,)+(None,)*11
  vis=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY2,True,[],unreal.DrawDebugTrace.NONE,True)
  u=vis.to_tuple() if vis is not None else (False,)+(None,)*11
  rows.append(dict(id=v['id'],length=(b-a).length(),hit=bool(t[0]),dist=(t[4]-a).length() if t[0] else None,actor=t[9].get_actor_label() if t[0] and t[9] else None,comp=t[10].get_name() if t[0] and t[10] else None,
   cam_hit=bool(u[0]),cam_dist=(u[4]-a).length() if u[0] else None,cam_actor=u[9].get_actor_label() if u[0] and u[9] else None))
 (SURVEY_OUT/'city-view-check.json').write_text(json.dumps(rows,ensure_ascii=False,indent=1),'utf8')

def motel_city_wall_sweep():
 # For views whose ray hits a wall within 1 m of the eye: sweep the pawn capsule (r 34, half height 88) across that wall
 # in both directions. 'room_to_wall' starting inside the room the point was picked in; a miss there = walk-through wall.
 chk={r['id']:r for r in json.loads((SURVEY_OUT/'city-view-check.json').read_text('utf8'))};world=unreal.EditorLevelLibrary.get_editor_world();rows=[]
 def cap(a,b):
  r=unreal.SystemLibrary.capsule_trace_single(world,a,b,34.,88.,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  t=r.to_tuple() if r is not None else (False,)+(None,)*11
  return dict(hit=bool(t[0]),dist=(t[4]-a).length() if t[0] else None,actor=t[9].get_actor_label() if t[0] and t[9] else None)
 for v in json.loads((SURVEY_OUT/'city-room-views.json').read_text('utf8')):
  c=chk.get(v['id'])
  if not c or not c['hit'] or c['dist']>=100:continue
  e=unreal.Vector(*v['eye']);t=unreal.Vector(*v['target']);d=t-e;d.z=0;d=d.normal();z=e.z-160+95
  p=unreal.Vector(e.x+d.x*80,e.y+d.y*80,z);q=unreal.Vector(e.x-d.x*150,e.y-d.y*150,z)
  rows.append(dict(id=v['id'],wall_from_eye_cm=c['dist'],room_to_wall=cap(p,q),wall_to_room=cap(q,p)))
 n=sum(1 for r in rows if not r['room_to_wall']['hit'] or not r['wall_to_room']['hit'])
 (SURVEY_OUT/'city-wall-sweep.json').write_text(json.dumps(dict(checked=len(rows),passable=n,rows=rows),ensure_ascii=False,indent=1),'utf8')

def motel_city_frame_test():
 # Which building-local -> world mapping puts contract furniture on the built mesh? frame-test.json:
 # [{actor, local_m:[x,y,z]}]; each candidate traces down from 3 m above and reports the hit height above the local z.
 tests=json.loads((SURVEY_OUT/'frame-test.json').read_text('utf8'));world=unreal.EditorLevelLibrary.get_editor_world()
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};rows=[]
 for t in tests:
  a=actors[t['actor']];tr=a.get_actor_transform();x,y,z=t['local_m'];o,e=a.get_actor_bounds(False);res={}
  cands={'actor_xy':tr.transform_location(unreal.Vector(x*100,y*100,0)),'actor_xflipy':tr.transform_location(unreal.Vector(x*100,-y*100,0))}
  for k in range(4):
   ang=math.radians(90*k);c,s=math.cos(ang),math.sin(ang)
   cands['bounds_rot%d'%(90*k)]=unreal.Vector(o.x+(x*c-y*s)*100,o.y+(x*s+y*c)*100,0)
  base=tr.translation.z
  for k,p in cands.items():
   r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(p.x,p.y,base+z*100+300),unreal.Vector(p.x,p.y,base+z*100-200),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
   q=r.to_tuple() if r is not None else (False,)+(None,)*11
   res[k]=round(q[4].z-(base+z*100),1) if q[0] else None
  rows.append(dict(actor=t['actor'],local_m=t['local_m'],actor_location=num(tr.translation),actor_yaw=float(a.get_actor_rotation().yaw),bounds_origin=num(o),hits_cm=res))
 (SURVEY_OUT/'frame-test-result.json').write_text(json.dumps(rows,ensure_ascii=False,indent=1),'utf8')

def motel_city_floor_meshes():
 # floor actor -> static mesh path + transform (to find floors that share one layout)
 rows=[]
 for a in SUB.get_all_level_actors():
  l=a.get_actor_label()
  if re.match(r'^(Campus|City|Mall)_[A-Z0-9]+_F\d\d$',l):
   c=a.static_mesh_component;m=c.static_mesh;tr=a.get_actor_transform()
   rows.append(dict(actor=l,mesh=m.get_path_name() if m else None,tris=m.get_num_triangles(0) if m else 0,location=num(tr.translation),yaw=float(a.get_actor_rotation().yaw),scale=num(tr.scale3d)))
 (SURVEY_OUT/'city-floor-meshes.json').write_text(json.dumps(sorted(rows,key=lambda r:r['actor']),ensure_ascii=False,indent=1),'utf8')

def motel_dorm_scan():
 # Dorm furniture from the built geometry (the old layout manifest no longer matches the meshes):
 # 20 cm height field over Campus_D1_F02; mattress tops (1.35..1.8 m upper bunk, lower bunk under it), desk tops (.68..82 m).
 # The same layout repeats on D1..D4 F02..F06 (identical triangle counts, buildings offset in Y): every item is re-verified
 # on each floor by a single trace before it is kept.
 world=unreal.EditorLevelLibrary.get_editor_world();actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 def down(x,y,z0,z1):
  r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z0),unreal.Vector(x,y,z1),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  t=r.to_tuple() if r is not None else (False,)+(None,)*11
  return t[4].z if t[0] else None
 def floor_level(a):
  # start just above this floor's own slab: the actor bounds reach up into the next floor's slab, and a ray from the
  # bounds top lands on the floor above (first install put every dorm floor's dressing one storey too high)
  o,e=a.get_actor_bounds(False);hs={}
  for i in range(-20,21):
   for k in range(-8,9):
    z=down(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z+250,o.z-e.z-50)
    if z is not None:hs[round(z/5)*5]=hs.get(round(z/5)*5,0)+1
  return max(hs,key=hs.get)
 a=actors['Campus_D1_F02'];o,e=a.get_actor_bounds(False);fz=floor_level(a);step=20.
 nx,ny=int(2*e.x/step),int(2*e.y/step);grid={}
 for i in range(nx):
  for k in range(ny):
   x=o.x-e.x+step*(i+.5);y=o.y-e.y+step*(k+.5);z=down(x,y,fz+230,fz-20)
   if z is not None:grid[(i,k)]=z-fz
 def comps(lo,hi):
  seen=set();out=[]
  for c,h in grid.items():
   if c in seen or not lo<=h<=hi:continue
   st=[c];seen.add(c);cells=[]
   while st:
    p=st.pop();cells.append(p)
    for d in ((1,0),(-1,0),(0,1),(0,-1)):
     q=(p[0]+d[0],p[1]+d[1])
     if q not in seen and q in grid and lo<=grid[q]<=hi:seen.add(q);st.append(q)
   i0=min(p[0] for p in cells);i1=max(p[0] for p in cells);k0=min(p[1] for p in cells);k1=max(p[1] for p in cells)
   w,dd=(i1-i0+1)*step,(k1-k0+1)*step;out.append(dict(x=o.x-e.x+step*(i0+i1+1)/2,y=o.y-e.y+step*(k0+k1+1)/2,sx=w,sy=dd,h=sum(grid[p] for p in cells)/len(cells),n=len(cells)))
  return out
 beds=[c for c in comps(135,180) if 70<=min(c['sx'],c['sy'])<=130 and 170<=max(c['sx'],c['sy'])<=240 and c['n']>=25]
 desks=[c for c in comps(68,82) if 40<=min(c['sx'],c['sy'])<=90 and 80<=max(c['sx'],c['sy'])<=180 and c['n']>=12]
 for b in beds:
  z=down(b['x'],b['y'],fz+b['h']-25,fz-20);b['low_h']=(z-fz) if z is not None else None
 # replicate: D1..D4 x F02..F06 (D-building Y offset from actor location; floor offset from each floor's own level)
 base=a.get_actor_location();rows=[]
 for bid in ('D1','D2','D3','D4'):
  for fl in range(2,7):
   b=actors.get('Campus_%s_F%02d'%(bid,fl))
   if not b:continue
   dl=b.get_actor_location()-base;fz2=floor_level(b);dz=fz2-fz;keep_b=[];keep_d=[]
   for it in beds:
    z=down(it['x']+dl.x,it['y']+dl.y,fz2+230,fz2-20)
    if z is not None and abs(z-fz2-it['h'])<12:keep_b.append(dict(it,x=it['x']+dl.x,y=it['y']+dl.y))
   for it in desks:
    z=down(it['x']+dl.x,it['y']+dl.y,fz2+230,fz2-20)
    if z is not None and abs(z-fz2-it['h'])<8:keep_d.append(dict(it,x=it['x']+dl.x,y=it['y']+dl.y))
   rows.append(dict(actor=b.get_actor_label(),floor_z=fz2,beds=keep_b,desks=keep_d))
 assert sha(MAPFILE)==LOAD_SHA
 (SURVEY_OUT/'dorm-scan.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,source='Campus_D1_F02',source_floor_z=fz,beds_found=len(beds),desks_found=len(desks),floors=rows),ensure_ascii=False,indent=1),'utf8')

def motel_office_scan():
 # Office desks per floor from the built geometry (floors differ, so every floor is scanned): 20 cm height field from this
 # floor's own slab; desk tops .66..86 m, 35..110 x 70..240 cm (widened 10-27 for wall-side computer desks); a floor plant spot is a 3x3-cell clear patch 45 cm beyond a desk end.
 world=unreal.EditorLevelLibrary.get_editor_world();want=json.loads((SURVEY_OUT/'office-want.json').read_text('utf8'))
 def down(x,y,z0,z1):
  r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,z0),unreal.Vector(x,y,z1),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  t=r.to_tuple() if r is not None else (False,)+(None,)*11
  return t[4].z if t[0] else None
 rows=[]
 for a in SUB.get_all_level_actors():
  if a.get_actor_label() not in want:continue
  o,e=a.get_actor_bounds(False);hs={}
  for i in range(-20,21):
   for k in range(-8,9):
    z=down(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z+250,o.z-e.z-50)
    if z is not None:hs[round(z/5)*5]=hs.get(round(z/5)*5,0)+1
  fz=max(hs,key=hs.get);step=20.;grid={};nx,ny=int(2*e.x/step),int(2*e.y/step)
  for i in range(nx):
   for k in range(ny):
    z=down(o.x-e.x+step*(i+.5),o.y-e.y+step*(k+.5),fz+230,fz-20)
    if z is not None:grid[(i,k)]=z-fz
  seen=set();desks=[]
  for c,h in grid.items():
   if c in seen or not 66<=h<=86:continue
   st=[c];seen.add(c);cells=[]
   while st:
    p=st.pop();cells.append(p)
    for d in ((1,0),(-1,0),(0,1),(0,-1)):
     q=(p[0]+d[0],p[1]+d[1])
     if q not in seen and q in grid and 66<=grid[q]<=86:seen.add(q);st.append(q)
   i0=min(p[0] for p in cells);i1=max(p[0] for p in cells);k0=min(p[1] for p in cells);k1=max(p[1] for p in cells)
   sx,sy=(i1-i0+1)*step,(k1-k0+1)*step
   if 35<=min(sx,sy)<=110 and 70<=max(sx,sy)<=240 and len(cells)>=10:
    d=dict(x=o.x-e.x+step*(i0+i1+1)/2,y=o.y-e.y+step*(k0+k1+1)/2,sx=sx,sy=sy,h=sum(grid[p] for p in cells)/len(cells))
    # plant spot: past either end along the long axis, all 3x3 cells at floor level
    ci,ck=(i0+i1)//2,(k0+k1)//2;spot=None
    for sgn in (1,-1):
     if sx>=sy:pi,pk=(i1+3 if sgn>0 else i0-3),ck
     else:pi,pk=ci,(k1+3 if sgn>0 else k0-3)
     if all(abs(grid.get((pi+u,pk+v),999))<4 for u in (-1,0,1) for v in (-1,0,1)):spot=[o.x-e.x+step*(pi+.5),o.y-e.y+step*(pk+.5)];break
    d['plant']=spot;desks.append(d)
  rows.append(dict(actor=a.get_actor_label(),anchor=num(a.get_actor_location()),floor_z=fz,desks=desks))
 assert sha(MAPFILE)==LOAD_SHA
 (SURVEY_OUT/'office-scan.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,floors=sorted(rows,key=lambda r:r['actor'])),ensure_ascii=False,indent=1),'utf8')

def motel_classroom_wall_plan():
 # Wall dressing slots for teaching floors (classroom-want.json: building ids), from the built geometry:
 # in-room points (like city_room_views, up to 24 per floor, 5 m apart); from each point a ray along +-X/+-Y finds a wall
 # 1.5..8 m away facing back; five rays (centre + item corners) must hit the same floor mesh within 1.5 cm, so doors,
 # windows and boards (which stand off the wall) are skipped. Items rotate board / clock / chart; one per 2.5 m of wall.
 want=json.loads((SURVEY_OUT/'classroom-want.json').read_text('utf8'));world=unreal.EditorLevelLibrary.get_editor_world()
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  return r.to_tuple() if r is not None else (False,)+(None,)*11
 SIZE={'board':(120.,90.,155.),'clock':(36.,36.,235.),'chart':(120.,80.,160.)}
 rows=[];dirs8=[(math.cos(k*math.pi/4),math.sin(k*math.pi/4)) for k in range(8)];dirs4=[(1,0),(0,1),(-1,0),(0,-1)]
 for a in SUB.get_all_level_actors():
  m=re.match(r'^Campus_([A-Z0-9]+)_F\d\d$',a.get_actor_label())
  if not m or m.group(1) not in want:continue
  label=a.get_actor_label();o,e=a.get_actor_bounds(False);hs={}
  for i in range(-20,21):
   for k in range(-8,9):
    h=ray(unreal.Vector(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z+250),unreal.Vector(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z-50))
    if h[0]:hs[round(h[4].z/5)*5]=hs.get(round(h[4].z/5)*5,0)+1
  fz=max(hs,key=hs.get);cands=[]
  nx,ny=max(1,int((2*e.x-200)//200)),max(1,int((2*e.y-200)//200))
  for i in range(nx+1):
   for k in range(ny+1):
    x=o.x-e.x+100+i*(2*e.x-200)/nx;y=o.y-e.y+100+k*(2*e.y-200)/ny;z=fz+160
    s=unreal.SystemLibrary.sphere_trace_single(world,unreal.Vector(x,y,z),unreal.Vector(x,y,z-1),30.,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
    if s is not None and s.to_tuple()[0]:continue
    g=ray(unreal.Vector(x,y,fz+120),unreal.Vector(x,y,fz-30))
    if not g[0] or abs(g[4].z-fz)>15:continue
    ds=[]
    for (dx,dy) in dirs8:
     t=ray(unreal.Vector(x,y,z),unreal.Vector(x+dx*1400,y+dy*1400,z));ds.append((t[4]-unreal.Vector(x,y,z)).length() if t[0] else 1e9)
    if min(ds)<120 or max(ds)>1400:continue
    cands.append((sum(ds)/8,x,y))
  cands.sort(reverse=True);pts=[]
  for c in cands:
   if all((c[1]-p[1])**2+(c[2]-p[2])**2>500**2 for p in pts):pts.append(c)
   if len(pts)>=24:break
  items=[]
  for n,(op,x,y) in enumerate(pts):
   for di,(dx,dy) in enumerate(dirs4):
    kind=('board','clock','chart')[(n+di)%3];w,hgt,zc=SIZE[kind]
    t=ray(unreal.Vector(x,y,fz+zc),unreal.Vector(x+dx*800,y+dy*800,fz+zc))
    if not t[0] or t[9] is not a:continue
    d0=(t[4]-unreal.Vector(x,y,fz+zc)).length();nrm=t[7]
    if d0<150 or nrm.x*dx+nrm.y*dy>-0.95:continue
    px,py=-dy,dx;ok=True
    for (u,v) in ((-w/2,-hgt/2),(w/2,-hgt/2),(-w/2,hgt/2),(w/2,hgt/2)):
     s0=unreal.Vector(x+px*u,y+py*u,fz+zc+v);q=ray(s0,unreal.Vector(s0.x+dx*800,s0.y+dy*800,s0.z))
     if not q[0] or q[9] is not a or abs((q[4]-s0).length()-d0)>1.5:ok=False;break
    if not ok:continue
    cx,cy=t[4].x+nrm.x*1.2,t[4].y+nrm.y*1.2
    if any(abs(it['normal'][0]*nrm.x+it['normal'][1]*nrm.y-1)<.05 and math.hypot(it['at'][0]-cx,it['at'][1]-cy)<250 for it in items):continue
    items.append(dict(kind=kind,at=[cx,cy,fz+zc],normal=[nrm.x,nrm.y],w=w,h=hgt,art=(n*7+di)%3))
  rows.append(dict(actor=label,anchor=num(a.get_actor_location()),floor_z=fz,points=len(pts),items=items))
 assert sha(MAPFILE)==LOAD_SHA
 (SURVEY_OUT/'classroom-wall-plan.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,floors=sorted(rows,key=lambda r:r['actor'])),ensure_ascii=False,indent=1),'utf8')

def motel_shop_slots():
 wf=SURVEY_OUT/'slots-want.json';want=set(json.loads(wf.read_text('utf8'))) if wf.exists() else {'S01','S26','S09','S17'};rows=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label()
  if not re.match(r'^S\d\d_F\d\d$',label) or label[:3] not in want:continue
  c=a.static_mesh_component;mesh=c.static_mesh;slots=[]
  for i,s in enumerate(mesh.get_editor_property('static_materials')):
   mm=mesh.get_material(i);cm=c.get_material(i)
   slots.append(dict(index=i,slot=str(s.get_editor_property('material_slot_name')),mesh_material=mm.get_path_name() if mm else None,component_material=cm.get_path_name() if cm else None))
  bs=mesh.get_editor_property('body_setup')
  rows.append(dict(actor=label,mesh=mesh.get_path_name(),triangles=mesh.get_num_triangles(0),collision=str(bs.get_editor_property('collision_trace_flag')) if bs else None,mesh_bounds=[num(mesh.get_bounding_box().min),num(mesh.get_bounding_box().max)],slots=slots,tags=[str(t) for t in a.tags],folder=str(a.get_folder_path())))
 assert sha(MAPFILE)==LOAD_SHA
 (SURVEY_OUT/'sample-slots.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,actors=rows),ensure_ascii=False,indent=2),'utf8')
def motel_shop_front():
 # actors (other than the shop floors) whose bounds reach into the 3 m band in front of each sample's facade
 probe={r['actor']:r for r in json.loads((SURVEY_OUT/'shop-probe.json').read_text('utf8'))['actors']};rows=[]
 for sid in ('S01','S26','S09','S17'):
  f=probe[sid+'_F01'];x0,y0,_=f['bounds_origin'];ex,ey,_=f['bounds_extent']
  for a in SUB.get_all_level_actors():
   lab=a.get_actor_label()
   if lab.startswith(sid+'_F') or lab.startswith('ShopV1_'):continue
   o,e=a.get_actor_bounds(False)
   if e.x>3000 or e.y>3000:continue
   if abs(o.x-x0)<ex+350 and abs(o.y-y0)<ey+150 and not (abs(o.x-x0)<ex-30 and abs(o.y-y0)<ey-30):
    comps=[c.get_name()+':'+(c.static_mesh.get_name() if isinstance(c,unreal.StaticMeshComponent) and c.static_mesh else c.get_class().get_name()) for c in a.get_components_by_class(unreal.SceneComponent)][:6]
    rows.append(dict(shop=sid,actor=lab,cls=a.get_class().get_name(),origin=num(o),extent=num(e),folder=str(a.get_folder_path()),components=comps))
 (SURVEY_OUT/'shop-front-actors.json').write_text(json.dumps(dict(status='read_only_probe',rows=rows),ensure_ascii=False,indent=2),'utf8')
def motel_shop_actor_bounds():
 want=set(json.loads((SURVEY_OUT/'bounds-want.json').read_text('utf8')));rows=[]
 for a in SUB.get_all_level_actors():
  lab=a.get_actor_label()
  if lab in want:
   o,e=a.get_actor_bounds(False);t=a.get_actor_transform()
   row=dict(actor=lab,origin=num(o),extent=num(e),location=num(t.translation),yaw=float(a.get_actor_rotation().yaw))
   if isinstance(a,unreal.StaticMeshActor) and a.static_mesh_component.static_mesh:
    bb=a.static_mesh_component.static_mesh.get_bounding_box();row['mesh_min']=num(bb.min);row['mesh_max']=num(bb.max)
   rows.append(row)
 (SURVEY_OUT/'actor-bounds.json').write_text(json.dumps(dict(rows=rows),ensure_ascii=False,indent=1),'utf8')
def motel_shop_walk_sweep():
 # Pedestrian clearance through every refitted shop door: capsule sweeps (r 34 cm, half height 88 cm) from 2.5 m outside the
 # door, through it, 3 m in, then to the aisle in front of the core, plus floor rays at every point. Building-frame points come
 # from shop-refits-v1/refits-build.json (Blender frame; UE local y is the negated Blender y).
 builds={}
 for p in (ROOT/'output/street-social-city-production/shop-refits-v1/refits-build.json',ROOT/'output/street-social-city-production/shop-samples-v1/samples-build.json'):
  for b in json.loads(p.read_text('utf8'))['shops']:builds[b['id']]=b
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()};world=unreal.EditorLevelLibrary.get_editor_world();rows=[];fails=[]
 for sid,b in sorted(builds.items()):
  if b.get('special'):continue
  t=actors[sid+'_F01'].get_actor_transform();H,dx,cy=b['H'],b['door_x'],b['core_y']
  def W(x,y,z):return t.transform_location(unreal.Vector(x*100,-y*100,z*100))
  path=[(dx,-H-2.5),(dx,-H+.5),(dx,-H+3.0),(dx,cy-1.0)]
  seg=[];ok=True
  for (a,c) in zip(path,path[1:]):
   s=W(a[0],a[1],.96);e=W(c[0],c[1],.96)
   hr=unreal.SystemLibrary.capsule_trace_single(world,s,e,34.,88.,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);hit=hr.to_tuple() if hr is not None else (False,)+(None,)*11
   blocked=bool(hit[0]);lab=hit[9].get_actor_label() if blocked and hit[9] else None;comp=hit[10].get_name() if blocked and hit[10] else None
   seg.append(dict(a=a,b=c,blocked=blocked,actor=lab,component=comp,impact=num(hit[4]) if blocked else None));ok=ok and not blocked
  floors=[]
  for (x,y) in path:
   p=W(x,y,.5);fr=unreal.SystemLibrary.line_trace_single(world,p,p-unreal.Vector(0,0,120),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True);f=fr.to_tuple() if fr is not None else (False,)+(None,)*11
   dz=float(f[4].z-(p.z-50)) if f[0] else None;floors.append(dz);ok=ok and f[0] and abs(dz)<25
  rows.append(dict(id=sid,ok=ok,segments=seg,floor_dz_cm=floors))
  if not ok:fails.append(sid)
 (SURVEY_OUT/'shop-walk-sweep.json').write_text(json.dumps(dict(status='passed' if not fails else 'failed',map_sha256=LOAD_SHA,shops=len(rows),failed=fails,rows=rows),ensure_ascii=False,indent=1),'utf8')
]====]
