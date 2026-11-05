-- Fit-out for empty office floors (City_O01..O03, shop-survey-v1/office-fit-scan.json from street_city_dorm_decor_payload.lua
-- office_fit_scan): rooms are the 40 cm cells at least 0.8 m from any wall/standing object (door openings < 1.6 m wide cut
-- them apart); door cells touch two rooms and keep 1.4 m clear. Per room by area: open office (back-to-back desk pods
-- with chairs, monitors), meeting room (table + chairs), private office (desk, chair, bookcase), plus corner plants;
-- F01's largest room is a lobby (reception counter, sofas, coffee table). Nothing is placed in a cell the scan saw occupied.
-- One mesh per floor, origin at the floor actor XY and scanned slab level (same contract as build_street_city_office_decor.lua).
-- Output: output/street-social-city-production/office-fit-v1/<floor actor>.glb + build.json (+ layout per floor)
-- Usage: lua Tools/build_street_city_office_fit.lua
local code=[====[
import bpy,json,math,random,hashlib
from pathlib import Path
from collections import deque
R=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=R/'office-fit-v1';O.mkdir(exist_ok=True)
scan=json.loads((R/'shop-survey-v1/office-fit-scan.json').read_text('utf8'));out=[];VIEWS=[]
_fp=R/'home-fit-v1/fixture-scan-resi.json';_fx=json.loads(_fp.read_text('utf8')) if _fp.exists() else None
FIX={f['actor']:f for f in _fx['floors']} if _fx else {};FIXM=_fx['mats'] if _fx else []
# OK_FIT_SPORTS=1: also fit the Campus_SP sports-centre floors from their 40 cm fixture scan (same free/ex/ey contract)
import os
SPM=[]
if os.environ.get('OK_FIT_SPORTS')=='1':_sp=json.loads((R/'home-fit-v1/fixture-scan-sp.json').read_text('utf8'));scan['floors']+=_sp['floors'];SPM=[n.lower() for n in _sp['mats']]
N4=((1,0),(-1,0),(0,1),(0,-1))
# OK_FIT_ONLY=<actor prefix>: rebuild only those floors; the other floors keep their entries from the existing build.json
import os
only=os.environ.get('OK_FIT_ONLY')
if only and (O/'build.json').exists():
 out=[f for f in json.loads((O/'build.json').read_text('utf8'))['floors'] if not f['actor'].startswith(only) and Path(f['path']).exists()]
for fl in scan['floors']:
 if only and not fl['actor'].startswith(only):continue
 nx,ny,S=fl['nx'],fl['ny'],fl['step']/100;x0,y0=fl['origin']
 free=lambda i,k:0<=i<nx and 0<=k<ny and fl['free'][k][i]=='1'
 def step(i,k,di,dk):
  j,l=i+di,k+dk
  if not(free(i,k) and free(j,l)):return False
  if di:return fl['ex'][k][min(i,j)]=='0'
  return fl['ey'][min(k,l)][i]=='0'
 # distance (cells) to the nearest hard cell: not free, or with a blocked edge
 INF=10**9;d=[[INF]*nx for _ in range(ny)];q=deque()
 for k in range(ny):
  for i in range(nx):
   if not free(i,k) or not all(step(i,k,a,b) for a,b in N4 if 0<=i+a<nx and 0<=k+b<ny):d[k][i]=0;q.append((i,k))
 while q:
  i,k=q.popleft()
  for a,b in N4:
   j,l=i+a,k+b
   if 0<=j<nx and 0<=l<ny and d[l][j]>d[k][i]+1:d[l][j]=d[k][i]+1;q.append((j,l))
 room=[[-1]*nx for _ in range(ny)];rooms=[]
 for k in range(ny):
  for i in range(nx):
   if d[k][i]>=2 and room[k][i]<0:
    rid=len(rooms);cells=[];q=deque([(i,k)]);room[k][i]=rid
    while q:
     a,b=q.popleft();cells.append((a,b))
     for u,v in N4:
      j,l=a+u,b+v
      if 0<=j<nx and 0<=l<ny and room[l][j]<0 and d[l][j]>=2 and step(a,b,u,v):room[l][j]=rid;q.append((j,l))
    rooms.append(cells)
 # doors: free low-clearance cells reaching two rooms within 3 passable steps
 doors=[]
 for k in range(ny):
  for i in range(nx):
   if not free(i,k) or d[k][i]>=2:continue
   seen={(i,k)};q=deque([(i,k,0)]);hit=set()
   while q:
    a,b,s=q.popleft()
    if room[b][a]>=0:hit.add(room[b][a]);continue
    if s>=3:continue
    for u,v in N4:
     if (a+u,b+v) not in seen and step(a,b,u,v):seen.add((a+u,b+v));q.append((a+u,b+v,s+1))
   if len(hit)>=2:doors.append((i,k))
 # Residential floors are 3.5 m apartment rooms: after the 0.8 m door cut, grow each room one cell (0.4 m) toward its walls
 # so beds/sofas can stand against them, and keep only 0.9 m clear at doors (offices: 1.4 m).
 resi=fl['actor'].startswith('City_R');doorset=set(doors)
 if resi:
  grow=[]
  for k in range(ny):
   for i in range(nx):
    if room[k][i]>=0:continue
    if not free(i,k) or (i,k) in doorset or d[k][i]<1:continue
    for u,v in N4:
     j,l=i+u,k+v
     if 0<=j<nx and 0<=l<ny and room[l][j]>=0 and d[l][j]>=2 and step(i,k,u,v):grow.append((i,k,room[l][j]));break
  for i,k,r in grow:room[k][i]=r;rooms[r].append((i,k))
 keep=set();kr=(2,5) if resi else (4,12)
 for i,k in doors:
  for a in range(-kr[0],kr[0]+1):
   for b in range(-kr[0],kr[0]+1):
    if a*a+b*b<=kr[1]:keep.add((i+a,k+b))
 ok=lambda i,k,r:0<=i<nx and 0<=k<ny and room[k][i]==r and (i,k) not in keep
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS={};OBJ=[]
 def mat(n,c,rough=.7,metal=0.,emit=0.):
  if n in MATS:return MATS[n]
  m=bpy.data.materials.new(n);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*c,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
  if emit:b.inputs['Emission Color'].default_value=(*c,1);b.inputs['Emission Strength'].default_value=emit
  MATS[n]=m;return m
 def box(p,s,m,rz=0):
  bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.dimensions=s;o.rotation_euler.z=rz;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);o.data.materials.append(m);OBJ.append(o);return o
 def cyl(p,r,h,m,n=12,r2=None):
  bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=p);o=bpy.context.object;o.data.materials.append(m);OBJ.append(o);return o
 AX,AY,AZ=fl['anchor'][0],fl['anchor'][1],fl['floor_z']
 def W(i,k):return (x0+fl['step']*(i+.5),y0+fl['step']*(k+.5))
 def L(x,y,z=0.):return ((x-AX)/100,-(y-AY)/100,z)
 def frame(cx,cy,rz):
  c,s=math.cos(rz),math.sin(rz)
  return lambda u,v,w:(cx+u*c-v*s,cy+u*s+v*c,w)
 wood=mat('desk_top',(.78,.7,.58),.6);steel=mat('steel',(.55,.56,.58),.4,.8);black=mat('black',(.05,.05,.06),.5);screen=mat('screen',(.25,.45,.8),.3,0.,.6)
 fabric=[mat('chair_blue',(.12,.2,.38),.9),mat('chair_grey',(.3,.3,.32),.9),mat('chair_teal',(.08,.3,.3),.9)]
 def desk(at,rz,w=1.4,dep=.7):
  box(at(0,0,.735),(w,dep,.03),wood,rz);box(at(-w/2+.03,0,.36),(.04,dep-.04,.72),steel,rz);box(at(w/2-.03,0,.36),(.04,dep-.04,.72),steel,rz);box(at(0,dep/2-.08,.45),(w-.1,.02,.45),steel,rz)
 def monitor(at,rz):
  box(at(0,.12,.76),(.22,.16,.02),black,rz);box(at(0,.14,.92),(.04,.03,.3),black,rz);box(at(0,.12,1.08),(.56,.03,.33),black,rz);box(at(0,.105,1.08),(.52,.005,.29),screen,rz);box(at(0,-.12,.755),(.42,.14,.015),black,rz)
 def chair(at,rz,m):
  cyl(at(0,0,.03),.3,.04,black,5);cyl(at(0,0,.25),.025,.42,steel);box(at(0,0,.47),(.48,.46,.07),m,rz);box(at(0,.22,.78),(.46,.06,.55),m,rz)
 def plant(px,py,big=True):
  h=.44 if big else .3;cyl((px,py,h/2),.2 if big else .15,h,mat('planter',(.86,.85,.8),.6),16,.16 if big else .12)
  for n in range(12):a=n*.52;o=box((px+.12*math.cos(a),py+.12*math.sin(a),h+.18+.08*(n%3)),(.42,.07,.012),mat('leaf',(.2,.42,.18),.7),a);o.rotation_euler.y=.5
 def bookcase(at,rz):
  box(at(0,0,.95),(.9,.35,1.9),wood,rz)
  for n in range(4):
   for b in range(6):box(at(-.36+b*.14,-.02,.25+n*.45),(.1,.26,.3),mat('file%d'%(b%3),((.15,.3,.6),(.6,.15,.15),(.85,.82,.7))[b%3],.6),rz)
 def footprint(r,cx,cy,hu,hv,rz,pad):
  # every cell centre inside the rotated rectangle (+pad) must belong to room r and be outside door keep-outs
  c,s=math.cos(rz),math.sin(rz);ext=int((max(hu,hv)+pad)/S)+2;ci,ck=int((cx-x0/100)/S),int((cy-y0/100)/S)
  for a in range(ci-ext,ci+ext+1):
   for b in range(ck-ext,ck+ext+1):
    px,py=x0/100+S*(a+.5)-cx,y0/100+S*(b+.5)-cy;u,v=px*c+py*s,-px*s+py*c
    if abs(u)<=hu+pad and abs(v)<=hv+pad and not ok(a,b,r):return False
  return True
 random.seed(fl['actor']);counts=dict(pods=0,desks=0,meeting=0,private=0,plants=0,lobby=0,kitchen=0,bath=0,study=0);layout=[]
 # built-in fridges of this floor from the 20 cm fixture scan (home-fit-v1/fixture-scan-resi.json, Tools/street_city_home_fit_payload.lua):
 # cells whose hit material is a steel finish standing 1.65 m or more. Unscanned floors reuse the same building's F02 (or R1's
 # same floor) relative to the floor anchor -- the apartment floors are copies of each other.
 fridges=[]
 if resi and FIX:
  src=FIX.get(fl['actor']) or FIX.get(fl['actor'][:7]+'_F02' if not fl['actor'].endswith('_F01') else 'City_R1_F01') or FIX.get('City_R1_'+fl['actor'][-3:]) or FIX.get('City_R1_F02')
  steel_ids={k for k,n in enumerate(FIXM) if 'steel' in n.lower()}
  for kk in range(0,src['ny'],2):
   for ii in range(0,src['nx'],2):
    if src['m'][kk][ii] in steel_ids and src['h'][kk][ii]>=165:
     fridges.append(((src['origin'][0]+src['step']*(ii+.5)-src['anchor'][0]+AX)/100,(src['origin'][1]+src['step']*(kk+.5)-src['anchor'][1]+AY)/100))
 G=.4 if resi else .8
 def sports_room(r,kind,wxm,wym,wx,wy):
  # Campus_SP: the halls already hold courts, nets, lockers and benches (fixture scan); this adds what the survey
  # photos lacked -- team banners and a scoreboard high on the hall walls, benches and a ball cart on free floor along
  # them; a gym corner (dumbbell rack, mirror, mats) in mid-size rooms; water dispenser, towel shelf, clock in small rooms.
  # Floor pieces only go on free scanned cells (footprint); wall pieces hang above 2.2 m.
  cx,cy=wxm+wx/2,wym+wy/2;n=0;gymdone=False
  sides=[((1,0),(wxm+wx,cy)),((-1,0),(wxm,cy)),((0,1),(cx,wym+wy)),((0,-1),(cx,wym))]
  team=[(.75,.1,.12),(.1,.25,.65),(.95,.7,.1),(.1,.5,.25)]
  for si,((hx,hy),(ex,ey)) in enumerate(sides):
   rzh=math.atan2(-hx,hy);ux,uy=math.cos(rzh),math.sin(rzh);sl=wy if hx else wx
   wall=frame(ex+hx*(G-.06),ey+hy*(G-.06),rzh)  # just in front of the wall finish
   if kind=='hall':
    nb=int((sl-2)//4)
    for k in range(nb):
     u=-sl/2+2+4*(k+.5);c=team[(k+si)%4]
     box(wall(u,-.02,3.0),(1.0,.03,1.6),mat('banner%d'%((k+si)%4),c,.9),rzh);box(wall(u,-.05,3.82),(1.15,.04,.04),steel,rzh)
     box(wall(u,-.035,3.0),(.5,.01,.5),mat('banner_crest',(.97,.95,.9),.8),rzh)
    if si==0:
     box(wall(0,-.1,4.2),(3.2,.2,1.4),black,rzh)
     for dgt in range(4):box(wall(-1.05+dgt*.7,-.21,4.25),(.45,.01,.75),mat('score_led',((1.,.2,.1),(1.,.2,.1),(.2,1.,.3),(.2,1.,.3))[dgt],.4,0.,4.),rzh)
    for k in range(int((sl-2)//6)):
     u=-sl/2+1+6*(k+.5);bc=(ex-hx*.25+ux*u,ey-hy*.25+uy*u)
     if footprint(r,*bc,1.0,.22,rzh,.05):
      at=frame(*bc,rzh);box(at(0,0,.44),(2.0,.36,.05),mat('bench_wood',(.72,.52,.3),.5),rzh)
      for s in(-1,1):box(at(s*.85,0,.22),(.05,.3,.44),steel,rzh)
      n+=1
    if si==1:
     bc=(ex-hx*.6+ux*(sl/2-1.2),ey-hy*.6+uy*(sl/2-1.2))
     if footprint(r,*bc,.45,.35,rzh,.05):
      at=frame(*bc,rzh);box(at(0,0,.5),(.9,.6,.04),steel,rzh)
      for s in(-1,1):box(at(s*.43,0,.45),(.03,.6,.9),steel,rzh);box(at(0,s*.29,.45),(.9,.03,.9),steel,rzh)
      for b in range(8):cyl(at(-.25+(b%4)*.17,-.1+(b//4)*.2,.68+.03*(b%2)),.11,.22,mat('ball%d'%(b%3),((.95,.55,.1),(.95,.95,.92),(.15,.3,.75))[b%3],.6),12)
      n+=1
   elif kind=='gym':
    # dumbbell rack + weight bench along the first wall (any side, shifted along it) with room in front; mirror behind
    for du in ((0,2,-2,4,-4) if not gymdone else ()):
     bc=(ex-hx*.35+ux*du,ey-hy*.35+uy*du)
     if not footprint(r,*bc,1.0,.3,rzh,.05) or not footprint(r,ex-hx*1.4+ux*du,ey-hy*1.4+uy*du,.7,.35,rzh,.05):continue
     at=frame(*bc,rzh);box(at(0,0,.5),(1.9,.4,.04),steel,rzh);box(at(0,0,.2),(1.9,.4,.04),steel,rzh)
     for s in(-1,1):box(at(s*.93,0,.45),(.05,.4,.9),steel,rzh)
     for b in range(8):
      for lvl,z in ((0,.58),(1,.28)):cyl(at(-.8+b*.23,0,z),.06+.01*(b%3),.24,black,12)
     wb=frame(ex-hx*1.4+ux*du,ey-hy*1.4+uy*du,rzh);box(wb(0,0,.45),(1.2,.3,.08),mat('bench_pad',(.1,.1,.12),.6),rzh)
     for s in(-1,1):box(wb(s*.45,0,.22),(.06,.3,.44),steel,rzh)
     box(wall(du,-.01,1.6),(min(4.,sl-1),.02,1.8),mat('gym_mirror',(.8,.82,.85),.04,1.),rzh)
     n+=2;gymdone=True;break
    if si!=0:continue
    for k in range(3):
     mc=(ex-hx*(2.0+k*.9),ey-hy*(2.0+k*.9))
     if footprint(r,*mc,.95,.35,rzh,.05):box((mc[0],mc[1],.008),(1.8,.6,.016),mat('yoga%d'%k,((.55,.2,.6),(.2,.55,.6),(.9,.45,.3))[k],.95),rzh);n+=1
   elif kind=='locker' and si==0:
    bc=(ex-hx*.3+ux*(-sl/2+.6),ey-hy*.3+uy*(-sl/2+.6))
    if footprint(r,*bc,.2,.2,rzh,.05):
     at=frame(*bc,rzh);box(at(0,0,.5),(.32,.32,1.0),mat('dispenser',(.92,.92,.95),.3),rzh);cyl(at(0,0,1.18),.14,.36,mat('water_jug',(.55,.75,.95),.1,.1),16);n+=1
    box(wall(0,-.15,1.7),(1.0,.3,.03),wood,rzh)
    for k in range(5):box(wall(-.4+k*.2,-.15,1.78),(.18,.26,.12),mat('towel%d'%(k%3),((.95,.93,.88),(.55,.7,.85),(.9,.75,.7))[k%3],.95),rzh)
    cyl(wall(0,-.02,2.45),.16,.04,mat('clock_face',(.97,.97,.95),.5),24).rotation_euler=(math.pi/2,0,rzh)
  return n
 def home_room(r,kind,wxm,wym,wx,wy):
  # kitchen counter run / bathroom set / study desk against a wall of a small apartment room; returns pieces placed
  cx,cy=wxm+wx/2,wym+wy/2
  sides=[((1,0),(wxm+wx,cy)),((-1,0),(wxm,cy)),((0,1),(cx,wym+wy)),((0,-1),(cx,wym))]
  rdoor=[(a,b) for (a,b) in doors if i0-3<=a<=i1+3 and k0-3<=b<=k1+3] or doors
  def dd(pt):return min((W(a,b)[0]/100-pt[0])**2+(W(a,b)[1]/100-pt[1])**2 for (a,b) in rdoor)
  if kind=='kitchen':
   fx,fy=min(fridges,key=lambda p:(p[0]-cx)**2+(p[1]-cy)**2)
   sides.sort(key=lambda s:(s[1][0]-fx)**2+(s[1][1]-fy)**2)
  else:sides.sort(key=lambda s:-dd(s[1]))
  def run(L0,dep,skip=()):
   for (hx,hy),(ex,ey) in sides:
    if (hx,hy) in skip:continue
    rzh=math.atan2(-hx,hy);ux,uy=math.cos(rzh),math.sin(rzh);sl=wy if hx else wx
    for L in (L0,L0-.4,L0-.8,L0-1.2):
     if L<.8 or L>sl-.1:continue
     for du in (0,.3,-.3,.6,-.6):
      if footprint(r,ex+hx*(G-.25-dep/2)+ux*du,ey+hy*(G-.25-dep/2)+uy*du,L/2,dep/2,rzh,0):
       return frame(ex+hx*(G-.25)+ux*du,ey+hy*(G-.25)+uy*du,rzh),L,rzh,(hx,hy),sl
   return None
  E=lambda h:(wx if h[0] else wy)
  n=0
  if kind=='kitchen':
   got=run(min(2.6,max(wx,wy)-.2),.62)
   if not got:return 0
   at,L,rzh,h,sl=got;cab=mat('kitchen_cab',(.93,.92,.88),.5);top=mat('worktop',(.12,.12,.13),.25)
   box(at(0,-.3,.44),(L,.58,.88),cab,rzh);box(at(0,-.31,.9),(L+.02,.62,.04),top,rzh);box(at(0,-.6,.06),(L,.04,.12),black,rzh)
   for k in range(int(L/.6)):box(at(-L/2+.3+k*.6,-.595,.55),(.12,.01,.02),steel,rzh)
   box(at(0,-.012,1.2),(L,.02,.56),mat('splash_tile',(.82,.86,.85),.15),rzh)
   box(at(0,-.18,1.85),(L,.34,.62),cab,rzh)
   su=-L/2+.45;box(at(su,-.3,.915),(.5,.4,.012),steel,rzh);box(at(su,-.3,.917),(.44,.34,.01),mat('sink_dark',(.2,.21,.22),.2,.8),rzh)
   cyl(at(su,-.07,1.04),.015,.24,steel,8);box(at(su,-.13,1.15),(.03,.14,.03),steel,rzh)
   hu=L/2-.45 if L>=1.6 else None
   if hu is not None:
    box(at(hu,-.3,.925),(.56,.5,.01),mat('hob_glass',(.04,.04,.05),.08,.3),rzh)
    for (a2,b2) in ((-.13,-.12),(.13,-.12),(-.13,.12),(.13,.12)):cyl(at(hu+a2,-.3+b2,.932),.08,.004,mat('hob_ring',(.35,.08,.05),.4,0.,.4),16)
    box(at(hu,-.27,1.6),(.6,.48,.12),steel,rzh);box(at(hu,-.12,1.95),(.24,.2,.6),steel,rzh)
   box(at(su+.55,-.35,.935),(.36,.24,.02),mat('cutboard',(.75,.58,.38),.6),rzh)
   cyl(at(-su-.1 if L>=1.2 else su+.3,-.25,1.0),.08,.18,mat('kettle',(.85,.15,.12),.3,.2),16)
   cyl(at(0,-.32,.96),.13,.08,mat('fruit_bowl',(.95,.95,.93),.3),20,.08);cyl(at(-.04,-.32,1.0),.04,.06,mat('orange',(.95,.5,.1),.6),10);cyl(at(.05,-.3,1.0),.04,.06,mat('apple',(.75,.1,.1),.5),10)
   n+=1;counts['kitchen']+=1
   # two-seat table in front of the counter when it fits
   if footprint(r,*at(0,-1.5,0)[:2],.65,.45,rzh,.05):
    tt=frame(*at(0,-1.5,0)[:2],rzh);box(tt(0,0,.73),(.75,.75,.04),wood,rzh);cyl(tt(0,0,.36),.04,.7,steel,8);cyl(tt(0,0,.02),.25,.04,steel,16)
    for s in (-1,1):box(tt(s*.6,0,.45),(.4,.4,.05),wood,rzh+math.pi/2);box(tt(s*.78,0,.7),(.04,.4,.5),wood,rzh)
    n+=1
   if nv['kit']<2:nv['kit']+=1;view('kitchen%d'%nv['kit'],at(L/2-.2,-(E(h)+G-.6),1.6),at(0,-.3,.95))
  elif kind=='bath':
   got=run(min(2.0,max(wx,wy)-.2),.7)
   if not got:return 0
   at,L,rzh,h,sl=got;wht=mat('porcelain_w',(.95,.95,.94),.12);vu=-L/2+.45
   box(at(vu,-.25,.4),(.8,.48,.8),mat('vanity_wood',(.42,.3,.2),.5),rzh);box(at(vu,-.26,.82),(.82,.5,.04),mat('vanity_top',(.88,.87,.84),.2),rzh)
   cyl(at(vu,-.28,.88),.19,.1,wht,20,.16);cyl(at(vu,-.07,.95),.012,.16,steel,8)
   box(at(vu,-.012,1.55),(.7,.02,.8),mat('mirror_home',(.8,.82,.85),.04,1.),rzh);box(at(vu,-.025,1.98),(.5,.06,.05),mat('mirror_light',(1.,.96,.88),.4,0.,3.),rzh)
   if L>=1.4:
    tu=L/2-.3;box(at(tu,-.12,.55),(.38,.18,.4),wht,rzh);box(at(tu,-.45,.2),(.36,.5,.4),wht,rzh);box(at(tu,-.47,.42),(.4,.52,.04),wht,rzh)
   box(at(0 if L<1.4 else (vu+tu)/2,-.04,1.15),(.5,.03,.02),steel,rzh);box(at(0 if L<1.4 else (vu+tu)/2,-.06,1.0),(.42,.03,.32),mat('towel%d'%(r%3),((.95,.93,.88),(.55,.7,.85),(.9,.75,.7))[r%3],.95),rzh)
   box(at(vu,-.85,.005),(.6,.4,.01),mat('bathmat',(.6,.75,.82),.95),rzh)
   n+=1;counts['bath']+=1
   # shower on the opposite wall when the room is big enough
   if area>=3.6:
    opp=(-h[0],-h[1]);got2=None
    for (hx,hy),(ex,ey) in sides:
     if (hx,hy)!=opp:continue
     rz2=math.atan2(-hx,hy)
     if footprint(r,ex+hx*(G-.25-.45),ey+hy*(G-.25-.45),.45,.45,rz2,0):got2=frame(ex+hx*(G-.25),ey+hy*(G-.25),rz2)
    if got2:
     box(got2(0,-.45,.04),(.9,.9,.08),wht,rz2);box(got2(0,-.9,1.0),(.9,.012,1.9),mat('shower_glass',(.7,.8,.85),.05,.3),rz2);box(got2(.44,-.45,1.0),(.012,.9,1.9),mat('shower_glass',(.7,.8,.85),.05,.3),rz2)
     cyl(got2(0,-.15,1.95),.1,.02,steel,16);cyl(got2(0,-.03,1.4),.012,1.1,steel,8)
   if nv['bath']<2:nv['bath']+=1;view('bath%d'%nv['bath'],at(0,-(E(h)+G-.5),1.6),at(vu,-.3,.9))
  else:
   got=run(1.3,.65)
   if not got:return 0
   at,L,rzh,h,sl=got;desk(frame(*at(0,-.33,0)[:2],rzh+math.pi),rzh+math.pi,min(1.3,L),.6)
   box(at(-.2,-.35,.76),(.34,.24,.02),black,rzh);box(at(-.2,-.24,.88),(.34,.02,.22),screen,rzh)
   cyl(at(.4,-.15,.78),.07,.04,steel);cyl(at(.4,-.15,.95),.012,.34,steel,8);cyl(at(.4,-.22,1.1),.09,.12,mat('lampshade_w',(1.,.93,.8),.6,0.,1.5),16,.06)
   chair(frame(*at(0,-.95,0)[:2],rzh+math.pi),rzh+math.pi,cm)
   bc=run(.9,.36,skip=(h,))
   if bc:bookcase(frame(*bc[0](0,-.18,0)[:2],bc[2]),bc[2])
   n+=1;counts['study']+=1
  return n
 # residential floors: packaged-capture views aimed at the placed pieces (world cm), collected in fit-views.json
 nv=dict(bed=0,liv=0,kit=0,bath=0)
 def view(tag,eye,tgt):VIEWS.append(dict(id='%s-%s'%(fl['actor'],tag),eye=[eye[0]*100,eye[1]*100,AZ+eye[2]*100],target=[tgt[0]*100,tgt[1]*100,AZ+tgt[2]*100],fov=84,hour=21))
 order=sorted(range(len(rooms)),key=lambda r:-len(rooms[r]))
 for rank,r in enumerate(order):
  cells=rooms[r];area=len(cells)*S*S
  if area<(2.5 if resi else 5):continue
  i0=min(c[0] for c in cells);i1=max(c[0] for c in cells);k0=min(c[1] for c in cells);k1=max(c[1] for c in cells)
  wx,wy=(i1-i0+1)*S,(k1-k0+1)*S
  # corridor; apartment kitchens and bathrooms are narrower (>= 1.4 m) but not hallway-shaped (aspect <= 2.6)
  if resi and area<9:
   if min(wx,wy)<1.4 or max(wx,wy)/min(wx,wy)>2.6:continue
  elif min(wx,wy)<2.4:continue
  rz=0 if wx>=wy else math.pi/2;cm=fabric[r%3]
  wxm,wym=x0/100+S*i0,y0/100+S*k0
  kind='open' if area>=45 else 'meeting' if area>=18 else 'private'
  if fl['actor'].endswith('_F01') and rank==0:kind='lobby'
  if fl['actor'].startswith('City_R'):
   if area>200:continue  # the open ground around the apartment blocks (one region of ~1000 m2) is not a living room
   if area>=22:kind='living'
   elif area>=9:kind='bedroom'
   else:
    # small apartment rooms: a built-in fridge (scanned) within 0.8 m -> kitchen; under 6 m2 -> bathroom; else a study
    bx0,bx1,by0,by1=wxm-.8,wxm+wx+.8,wym-.8,wym+wy+.8
    kind='kitchen' if any(bx0<=fx<=bx1 and by0<=fy<=by1 for (fx,fy) in fridges) else 'bath' if area<6 else 'study'
  if fl['actor'].startswith('Campus_SP'):
   if i0==0 or k0==0 or i1==nx-1 or k1==ny-1:continue  # open ground outside the building reaches the scan border
   # what already stands in the room (fixture scan materials): lockers (closed steel >= 1.5 m) -> changing room kit;
   # courts / nets -> treated as a hall (wall pieces and edge benches only); otherwise a gym corner
   mm={(fl['m'][b][a],fl['h'][b][a]) for (a,b) in cells}
   lock=any(m>=0 and 'steel_closed' in SPM[m] and hh>=150 for (m,hh) in mm);court=any(m>=0 and ('court' in SPM[m] or 'net_closed' in SPM[m]) for (m,hh) in mm)
   kind='hall' if area>=150 or court else 'locker' if lock or area<20 else 'gym'
  placed=0
  if kind in ('kitchen','bath','study'):
   placed=home_room(r,kind,wxm,wym,wx,wy)
  if kind in ('hall','gym','locker'):
   placed=sports_room(r,kind,wxm,wym,wx,wy)
  if kind in('living','bedroom'):
   # the wall farthest from this room's doors takes the bed head / the TV; h points from the room to that wall
   rd=[(a,b) for (a,b) in doors if any(abs(a-c0)<=3 and abs(b-c1)<=3 for (c0,c1) in ((i0,k0),(i1,k1),(i0,k1),(i1,k0))) or (i0-3<=a<=i1+3 and k0-3<=b<=k1+3)] or doors
   cx,cy=wxm+wx/2,wym+wy/2;G=.4 if resi else .8  # room-cell edge to wall
   sides=[((1,0),(wxm+wx,cy)),((-1,0),(wxm,cy)),((0,1),(cx,wym+wy)),((0,-1),(cx,wym))]
   def far(pt):
    return min((W(a,b)[0]/100-pt[0])**2+(W(a,b)[1]/100-pt[1])**2 for (a,b) in rd) if rd else 0
   for (hx,hy),edge in sorted(sides,key=lambda s:-far(s[1])):
    rzh=math.atan2(-hx,hy);ex,ey=edge  # frame: local +v points at the wall
    if kind=='bedroom':
     if not footprint(r,ex-hx*.65,ey-hy*.65,1.25 if resi else 1.4,.65,rzh,.05):continue
     at=frame(ex+hx*(G-.25),ey+hy*(G-.25),rzh)  # bed head 5 cm off the wall (room cells end ~0.8 m before it)
     linen=mat('linen%d'%(r%3),((.92,.9,.86),(.75,.8,.9),(.9,.82,.78))[r%3],.9)
     box(at(0,-1.05,.2),(1.6,2.1,.3),mat('bedframe',(.35,.25,.18),.6),rzh);box(at(0,-1.05,.45),(1.55,2.0,.22),linen,rzh)
     box(at(0,-1.55,.58),(1.58,1.0,.06),mat('duvet%d'%(r%3),((.3,.35,.55),(.55,.4,.35),(.3,.45,.4))[r%3],.9),rzh)
     for s in(-1,1):
      box(at(s*.4,-.25,.62),(.6,.35,.14),mat('pillow',(.97,.96,.94),.9),rzh)
      box(at(s*1.1,-.25,.27),(.45,.4,.54),wood,rzh);cyl(at(s*1.1,-.25,.6),.07,.1,steel);cyl(at(s*1.1,-.25,.78),.14,.22,mat('lampshade_w',(1.,.93,.8),.6,0.,1.5),16,.1)
     box(at(0,0,1.0),(1.7,.08,.9),mat('headboard',(.4,.3,.25),.7),rzh)
     counts['private']+=1;placed+=1
     if resi and nv['bed']<4:nv['bed']+=1;view('bed%d'%nv['bed'],at(.6,-((wx if hx else wy)+G-.7),1.6),at(0,-1.0,.6))
     # wardrobe on the opposite wall, centred
     # opposite room edge is E away; the wall is ~0.8 m past it, so a 0.6 m deep wardrobe centred 0.5 m past the edge backs onto it
     E=wx if hx else wy
     if footprint(r,ex-hx*(E-.2),ey-hy*(E-.2),.85,.2,rzh,0):box((ex-hx*(E+G-.3),ey-hy*(E+G-.3),1.0),(1.6,.6,2.0),wood,rzh+math.pi)
     break
    else:  # living: TV unit on that wall, sofa facing it 3 m out, coffee table between, rug, floor lamp
     if not footprint(r,ex-hx*1.55,ey-hy*1.55,1.25,.95,rzh,.05):continue
     at=frame(ex+hx*(G-.25),ey+hy*(G-.25),rzh)
     box(at(0,-.2,.25),(1.8,.45,.5),mat('tv_unit',(.15,.12,.1),.4),rzh);box(at(0,-.2,1.05),(1.4,.05,.8),black,rzh);box(at(0,-.23,1.05),(1.34,.01,.74),screen,rzh)
     box(at(0,-2.0,.006),(2.4,1.7,.012),mat('rug%d'%(r%2),((.55,.45,.35),(.35,.4,.5))[r%2],.95),rzh)
     box(at(0,-1.65,.22),(1.1,.6,.04),wood,rzh);box(at(0,-1.65,.1),(1.0,.5,.2),mat('tv_unit',(.15,.12,.1),.4),rzh)
     sofa=mat('sofa_fab%d'%(r%3),((.45,.42,.4),(.3,.35,.45),(.5,.4,.3))[r%3],.9)
     box(at(0,-2.6,.22),(2.1,.85,.44),sofa,rzh);box(at(0,-2.95,.62),(2.1,.2,.5),sofa,rzh)
     for s in(-1,1):box(at(s*.98,-2.6,.4),(.16,.85,.36),sofa,rzh)
     cyl(at(1.35,-2.8,.02),.16,.04,steel);cyl(at(1.35,-2.8,.8),.015,1.55,steel,8);cyl(at(1.35,-2.8,1.6),.22,.32,mat('lampshade_w',(1.,.93,.8),.6,0.,1.5),20,.16)
     counts['lobby']+=1;placed+=1
     if resi and nv['liv']<3:nv['liv']+=1;view('living%d'%nv['liv'],at(1.1,-.55,1.6),at(0,-2.6,.5))
     break
  elif kind=='dining':
   cx,cy=wxm+wx/2,wym+wy/2
   if footprint(r,cx,cy,.7,.8,rz,0):
    at=frame(cx,cy,rz);box(at(0,0,.74),(1.2,.8,.04),wood,rz)
    for (u,v) in((-.45,-.3),(.45,-.3),(-.45,.3),(.45,.3)):box(at(u,v,.37),(.05,.05,.72),steel,rz)
    for s in(-1,1):box(at(0,s*.6,.45),(.42,.4,.05),wood,rz);box(at(0,s*.78,.7),(.42,.04,.5),wood,rz)
    counts['meeting']+=1;placed+=1
  if kind=='lobby':
   cx,cy=wxm+wx/2,wym+wy/2
   for dx,dy in ((0,0),(1,0),(-1,0),(0,1),(0,-1),(2,0),(-2,0)):
    if footprint(r,cx+dx,cy+dy,1.3,.5,rz,.6):
     at=frame(cx+dx,cy+dy,rz);box(at(0,0,.525),(2.4,.7,1.05),wood,rz);box(at(0,-.2,1.07),(2.5,.35,.04),mat('counter_top',(.9,.9,.88),.3),rz);monitor(frame(*at(.6,.2,0)[:2],rz+math.pi),rz+math.pi);chair(frame(*at(.6,.75,0)[:2],rz),rz,cm);placed+=1;counts['lobby']+=1;break
   for sx in (-3.2,3.2):
    if footprint(r,cx+sx*math.cos(rz),cy+sx*math.sin(rz),1.1,1.6,rz,.3):
     at=frame(cx+sx*math.cos(rz),cy+sx*math.sin(rz),rz);sofa=mat('sofa',(.35,.2,.15),.8)
     for side in (-1,1):box(at(0,side*1.15,.22),(1.9,.8,.44),sofa,rz);box(at(0,side*1.5,.55),(1.9,.16,.5),sofa,rz)
     box(at(0,0,.22),(1.1,.6,.04),mat('glass',(.6,.7,.75),.1),rz);box(at(0,0,.11),(.9,.4,.22),steel,rz);counts['lobby']+=1
  elif kind=='open':
   # pods: two 1.4x0.7 desks back to back, chairs 0.55 out each side; strides 2.3 along, 3.8 across, 0.5 m aisles
   su,sv=2.3,3.8;nu,nv=int((max(wx,wy)-1.0)//su),int((min(wx,wy)-1.0)//sv)
   ou=(max(wx,wy)-nu*su)/2;ov=(min(wx,wy)-nv*sv)/2
   for a in range(nu):
    for b in range(nv):
     u,v=ou+su*(a+.5),ov+sv*(b+.5);cx,cy=(wxm+u,wym+v) if rz==0 else (wxm+v,wym+u)
     if not footprint(r,cx,cy,.75,1.35,rz,.35):continue
     at=frame(cx,cy,rz)
     for side in (-1,1):
      t=frame(*at(0,side*.35,0)[:2],rz if side<0 else rz+math.pi);desk(t,rz if side<0 else rz+math.pi);monitor(t,rz if side<0 else rz+math.pi);chair(frame(*at(0,side*1.0,0)[:2],rz if side<0 else rz+math.pi),rz if side<0 else rz+math.pi,cm)
     counts['pods']+=1;placed+=1
  elif kind=='meeting':
   cx,cy=wxm+wx/2,wym+wy/2;tl=min(max(wx,wy)-2.4,4.2)
   if tl>=1.6 and footprint(r,cx,cy,tl/2+.6,.6+.6,rz,.2):
    at=frame(cx,cy,rz);box(at(0,0,.74),(tl,1.2,.04),wood,rz);box(at(0,0,.37),(tl*.7,.5,.7),steel,rz);n=max(2,int(tl/.75))
    for side in (-1,1):
     for m in range(n):chair(frame(*at(-tl/2+tl*(m+.5)/n,side*.95,0)[:2],rz if side<0 else rz+math.pi),rz if side<0 else rz+math.pi,cm)
    box(at(tl/2+.05 if False else 0,0,.765),(.3,.2,.01),mat('paper',(.95,.95,.93),.9),rz);counts['meeting']+=1;placed+=1
  if kind in('private',) or (kind=='meeting' and not placed):
   cx,cy=wxm+wx/2,wym+wy/2
   for dx,dy in ((0,0),(.4,0),(-.4,0),(0,.4),(0,-.4)):
    if footprint(r,cx+dx,cy+dy,.75,.9,rz,.25):
     at=frame(cx+dx,cy+dy,rz);desk(frame(*at(0,-.2,0)[:2],rz),rz,1.5,.75);monitor(frame(*at(0,-.2,0)[:2],rz),rz);chair(frame(*at(0,-.85,0)[:2],rz),rz,cm)
     bc=frame(*at(0,.65,0)[:2],rz)
     if footprint(r,*bc(0,0,0)[:2],.5,.25,rz,0):bookcase(bc,rz+math.pi)
     counts['private']+=1;placed+=1;break
  # corner plants: room cells with d==2 whose two orthogonal neighbours are both nearer the wall
  pl=0
  for (a,b) in cells:
   if pl>=(3 if kind=='open' else 1) or d[b][a]!=2 or (a,b) in keep:continue
   if sum(1 for u,v in N4 if 0<=a+u<nx and 0<=b+v<ny and d[b+v][a+u]<2)>=2:
    px,py=W(a,b);plant(px/100,py/100);pl+=1;counts['plants']+=1
  layout.append(dict(room=r,kind=kind,area_m2=round(area,1),size_m=[round(wx,1),round(wy,1)],placed=placed,plants=pl))
 if not OBJ:print('OFFICE FIT empty',fl['actor']);continue
 # Placements were made in Unreal world metres (left-handed X/Y). Bake, then map every vertex to the anchor-relative
 # Blender frame used by the other floor dressings (x-AX, -(y-AY)); the Y mirror reverses winding, so flip normals back.
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=OBJ[0];bpy.ops.object.join();o=bpy.context.object;o.name=fl['actor']+'_Fit'
 bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 for v in o.data.vertices:v.co=((v.co.x*100-AX)/100,-(v.co.y*100-AY)/100,v.co.z)
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.flip_normals();bpy.ops.object.mode_set(mode='OBJECT')
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 p=O/(fl['actor']+'.glb');bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',export_apply=True,export_yup=True);o.data.calc_loop_triangles()
 out.append(dict(actor=fl['actor'],path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),anchor_cm=[AX,AY,AZ],rooms=len(rooms),doors=len(doors),counts=counts,layout=layout,triangles=len(o.data.loop_triangles)))
 print('OFFICE FIT',fl['actor'],len(rooms),'rooms',len(doors),'door cells',counts,flush=True)
(O/'build.json').write_text(json.dumps(dict(scan_map_sha256=scan['map_sha256'],floors=out),ensure_ascii=False,indent=1),'utf8')
(O/'fit-views.json').write_text(json.dumps(VIEWS,ensure_ascii=False,indent=1),'utf8')
print('OFFICE FIT DONE',len(out),'floors')
]====]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production'
os.execute('mkdir "'..out:gsub('/','\\')..'\\office-fit-v1" 2>nul')
local path=out..'/office-fit-v1/build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({code=code}));f:close()
local expr="import json;exec(json.load(open('"..path.."',encoding='utf8'))['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/office-fit-build.log" 2>&1"'))
for line in io.lines(out..'/office-fit-build.log')do if line:find('OFFICE FIT') or line:find('Error') or line:find('Traceback') then print(line) end end
