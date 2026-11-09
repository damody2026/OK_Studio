return [====[
HOME_OUT=ROOT/'output/street-social-city-production/home-fit-v1'

def motel_home_floor_actors():
 # Read-only list of every static mesh actor whose bounds centre lies inside the wanted floors' bounds (label, mesh,
 # location, bounds, materials) -> home-fit-v1/floor-actors.json; tells what the built-in fixtures are.
 HOME_OUT.mkdir(parents=True,exist_ok=True);want=json.loads((HOME_OUT/'scan-want.json').read_text('utf8'))
 acts=SUB.get_all_level_actors();fl={a.get_actor_label():a for a in acts if a.get_actor_label() in want['floors']};rows=[]
 boxes={k:a.get_actor_bounds(False) for k,a in fl.items()}
 for a in acts:
  if a.get_actor_label() in fl:continue
  comps=a.get_components_by_class(unreal.StaticMeshComponent)
  if not comps:continue
  o,e=a.get_actor_bounds(False)
  for k,(fo,fe) in boxes.items():
   if abs(o.x-fo.x)<=fe.x and abs(o.y-fo.y)<=fe.y and fo.z-fe.z-20<=o.z<=fo.z+fe.z:
    c=comps[0];sm=c.static_mesh
    rows.append(dict(floor=k,actor=a.get_actor_label(),cls=a.get_class().get_name(),mesh=sm.get_name() if sm else None,loc=num(a.get_actor_location()),ext=num(e),
     mats=[m.get_name() for m in c.get_materials() if m][:6],collision=str(c.get_collision_profile_name())));break
 assert sha(MAPFILE)==LOAD_SHA
 (HOME_OUT/'floor-actors.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,rows=rows),ensure_ascii=False,indent=1),'utf8')

def motel_home_fixture_scan():
 # Fixture map for apartment / hall floors (home-fit-v1/scan-want.json {tag, floors:[...], step_cm, steps:{floor:cm}}
 # -> fixture-scan-<tag>.json): per cell a ray from 2.5 m
 # above the slab straight down; h = height (cm) of what it lands on above the slab (0 = bare floor, -1 = no hit / hole),
 # m = index into mats (material of the hit face, via the complex-collision face index) so built-in kitchens, baths,
 # wardrobes etc. of the merged floor mesh can be told apart. Read-only; the map must not change.
 HOME_OUT.mkdir(parents=True,exist_ok=True)
 world=unreal.EditorLevelLibrary.get_editor_world();want=json.loads((HOME_OUT/'scan-want.json').read_text('utf8'))
 def hit(p0,p1):
  r=unreal.SystemLibrary.line_trace_single(world,p0,p1,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  return r.to_tuple() if r is not None else None
 mats=[];mid={}
 def matof(t):
  try:
   comp=t[10];face=t[15]
   m=comp.get_material_from_collision_face_index(face)
   m=m[0] if isinstance(m,tuple) else m
   n=m.get_name() if m else (comp.get_owner().get_actor_label() if comp else '?')
  except Exception as e:n='err:'+type(e).__name__
  if n not in mid:mid[n]=len(mats);mats.append(n)
  return mid[n]
 rows=[]
 for a in SUB.get_all_level_actors():
  lab=a.get_actor_label()
  if lab not in want['floors']:continue
  o,e=a.get_actor_bounds(False);hs={}
  for i in range(-20,21):
   for k in range(-8,9):
    t=hit(unreal.Vector(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z+250),unreal.Vector(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z-50))
    if t and t[0]:z=t[4].z;hs[round(z/5)*5]=hs.get(round(z/5)*5,0)+1
  fz=max(hs,key=hs.get);step=float(want.get('steps',{}).get(lab,want.get('step_cm',20)));nx,ny=int(2*e.x/step),int(2*e.y/step);x0,y0=o.x-e.x,o.y-e.y
  # free/ex/ey: same contract as office_fit_scan (slab reached from 1.8 m; a 1.0 m high ray to the +x / +y neighbour is blocked)
  H=[];M=[];free=[];ex=[];ey=[]
  for k in range(ny):
   hr=[];mr=[];fr='';rx='';ry=''
   for i in range(nx):
    x,y=x0+step*(i+.5),y0+step*(k+.5);t=hit(unreal.Vector(x,y,fz+250),unreal.Vector(x,y,fz-30))
    if t and t[0]:hr.append(int(round(t[4].z-fz)));mr.append(matof(t))
    else:hr.append(-1);mr.append(-1)
    if hr[-1]==0:fr+='1'
    else:
     t=hit(unreal.Vector(x,y,fz+180),unreal.Vector(x,y,fz-20));fr+='1' if t and t[0] and abs(t[4].z-fz)<6 else '0'
    t=hit(unreal.Vector(x,y,fz+100),unreal.Vector(x+step,y,fz+100)) if i+1<nx else None;rx+='1' if t and t[0] else '0'
    t=hit(unreal.Vector(x,y,fz+100),unreal.Vector(x,y+step,fz+100)) if k+1<ny else None;ry+='1' if t and t[0] else '0'
   H.append(hr);M.append(mr);free.append(fr);ex.append(rx);ey.append(ry)
  rows.append(dict(actor=lab,anchor=num(a.get_actor_location()),floor_z=fz,origin=[x0,y0],step=step,nx=nx,ny=ny,h=H,m=M,free=free,ex=ex,ey=ey))
  print('home fixture scan',lab,nx,ny,len(mats),flush=True)
 assert sha(MAPFILE)==LOAD_SHA
 (HOME_OUT/('fixture-scan-%s.json'%want.get('tag','all'))).write_text(json.dumps(dict(map_sha256=LOAD_SHA,mats=mats,floors=sorted(rows,key=lambda r:r['actor'])),ensure_ascii=False),'utf8')
]====]
