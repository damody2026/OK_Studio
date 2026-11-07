-- Small pieces the Tripo sets do not have: the shrine's fixtures, the treatment room's bed and towel cabinet, the tandem bike.
-- Origin bottom centre, front on -Y like the other fixtures; long things lie along X.
-- Writes output/street-social-city-production/hill-v1/; Tools/street_city_lover_spots_payload.lua places them.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_fixtures.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
local code = [====[
import bpy,json,math,pathlib
D=pathlib.Path(TASK['out'])
COL=dict(wood=(.5,.32,.17,.6),dark=(.2,.12,.07,.6),pale=(.8,.66,.45,.7),stone=(.56,.56,.53,.9),water=(.2,.45,.55,.1),roof=(.13,.13,.15,.7),red=(.72,.1,.08,.5),white=(.93,.92,.88,.7),gold=(.8,.62,.2,.35),pad=(.72,.55,.42,.6),towel=(.95,.94,.9,.9),towel2=(.62,.78,.74,.9),steel=(.6,.62,.65,.35),tire=(.04,.04,.05,.8),pink=(.85,.45,.55,.6),blue=(.2,.35,.7,.6),green=(.2,.5,.3,.6))
def build(name,fill):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 V=[];F=[];M=[];names=list(COL)
 def box(a,b,c,d,e,f,m):
  i=len(V);V.extend([(a,c,e),(b,c,e),(b,d,e),(a,d,e),(a,c,f),(b,c,f),(b,d,f),(a,d,f)])
  for q in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)):F.append(tuple(i+k for k in q));M.append(names.index(m))
 def poly(p,m):
  i=len(V);V.extend(p);F.append(tuple(range(i,i+len(p))));M.append(names.index(m))
 def bar(p,q,r,m,n=6):
  # a round bar from p to q
  p=list(p);q=list(q);d=[q[k]-p[k] for k in range(3)];l=math.sqrt(sum(x*x for x in d)) or 1;d=[x/l for x in d]
  u=[0,0,1] if abs(d[2])<.9 else [1,0,0];a=[d[1]*u[2]-d[2]*u[1],d[2]*u[0]-d[0]*u[2],d[0]*u[1]-d[1]*u[0]];al=math.sqrt(sum(x*x for x in a));a=[x/al for x in a]
  b=[d[1]*a[2]-d[2]*a[1],d[2]*a[0]-d[0]*a[2],d[0]*a[1]-d[1]*a[0]];i=len(V)
  for e in (p,q):
   for k in range(n):
    t=2*math.pi*k/n;V.append(tuple(e[w]+r*(a[w]*math.cos(t)+b[w]*math.sin(t)) for w in range(3)))
  for k in range(n):F.append((i+k,i+(k+1)%n,i+n+(k+1)%n,i+n+k));M.append(names.index(m))
  F.append(tuple(i+k for k in range(n-1,-1,-1)));M.append(names.index(m));F.append(tuple(i+n+k for k in range(n)));M.append(names.index(m))
 def wheel(x,y,z,r,m):
  n=20
  for k in range(n):
   t,u=2*math.pi*k/n,2*math.pi*(k+1)/n;bar((x+r*math.cos(t),y,z+r*math.sin(t)),(x+r*math.cos(u),y,z+r*math.sin(u)),.018,m,5)
  for k in range(0,n,4):
   t=2*math.pi*k/n;bar((x,y,z),(x+r*math.cos(t),y,z+r*math.sin(t)),.004,'steel',3)
 fill(box,poly,bar,wheel)
 # the import mirrors Y: a front built on Blender -Y lands on Unreal +Y, and every placement here expects -Y
 V=[(x,-y,z) for x,y,z in V];F=[tuple(reversed(f)) for f in F]
 me=bpy.data.meshes.new(name);me.from_pydata(V,[],F);me.update()
 for n in names:
  m=bpy.data.materials.new('fx_'+n);m.use_nodes=True;q=m.node_tree.nodes['Principled BSDF'];c=COL[n];q.inputs['Base Color'].default_value=(c[0],c[1],c[2],1);q.inputs['Roughness'].default_value=c[3];me.materials.append(m)
 for p,k in zip(me.polygons,M):p.material_index=k
 me.uv_layers.new(name='UVMap')
 o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o)
 bpy.ops.export_scene.gltf(filepath=str(D/(name+'.glb')),export_format='GLB',use_selection=False,export_apply=True)
 print('MESH',name,len(F),flush=True)
def roof(poly,a,b,c,d,z,h,m):
 # a gable along X, both sides of each slope
 y=(c+d)/2
 poly([(a,c,z),(b,c,z),(b,y,z+h),(a,y,z+h)],m);poly([(b,d,z),(a,d,z),(a,y,z+h),(b,y,z+h)],m);poly([(b,c,z-.02),(a,c,z-.02),(a,y,z+h-.02),(b,y,z+h-.02)],'dark');poly([(a,d,z-.02),(b,d,z-.02),(b,y,z+h-.02),(a,y,z+h-.02)],'dark')
def saisen(box,poly,bar,wheel):
 box(-.5,.5,-.3,.3,0,.08,'dark');box(-.46,.46,-.26,.26,.08,.55,'wood');box(-.5,.5,-.3,-.26,.5,.64,'dark');box(-.5,.5,.26,.3,.5,.64,'dark');box(-.5,-.46,-.3,.3,.5,.64,'dark');box(.46,.5,-.3,.3,.5,.64,'dark')
 for k in range(9):
  x=-.4+k*.1;box(x,x+.05,-.26,.26,.56,.6,'pale')
 box(-.12,.12,-.27,-.26,.26,.4,'gold')
def temizuya(box,poly,bar,wheel):
 for x in (-1.05,1.05):
  for y in (-.65,.65):box(x-.07,x+.07,y-.07,y+.07,0,2.3,'wood')
 box(-1.2,1.2,-.72,-.6,2.2,2.32,'dark');box(-1.2,1.2,.6,.72,2.2,2.32,'dark');roof(poly,-1.45,1.45,-1.,1.,2.3,.55,'roof')
 box(-.85,.85,-.35,.35,0,.2,'stone');box(-.8,.8,-.3,.3,.2,.68,'stone');box(-.7,.7,-.2,.2,.66,.67,'water');box(-.8,.8,-.3,-.2,.68,.74,'stone');box(-.8,.8,.2,.3,.68,.74,'stone');box(-.8,-.7,-.3,.3,.68,.74,'stone');box(.7,.8,-.3,.3,.68,.74,'stone')
 for x in (-.45,0,.45):bar((x,-.32,.76),(x,.05,.76),.012,'pale');bar((x,.05,.72),(x,.05,.78),.05,'pale',8)
 box(-.14,.14,.05,.28,.68,.82,'stone');bar((0,.16,.82),(0,-.05,.86),.03,'dark')
def omikuji(box,poly,bar,wheel):
 box(-.55,.55,-.25,.25,0,.95,'wood');box(-.6,.6,-.3,.3,.95,1.,'dark')
 bar((-.25,0,1.),(-.25,0,1.42),.1,'red',6);bar((-.25,0,1.42),(-.25,0,1.5),.018,'pale',4)
 for k in range(5):box(.05+k*.09,.11+k*.09,-.1,.1,1.,1.14,'white')
 for x in (-1.2,1.2):box(x-.04,x+.04,-.04,.04,0,1.75,'wood')
 for z in (1.05,1.3,1.55):
  bar((-1.2,0,z),(1.2,0,z),.008,'steel',4)
  for k in range(16):
   x=-1.1+k*.147+(z*.3%0.05);box(x-.016,x+.016,-.008,.008,z-.11,z,'white')
def ema(box,poly,bar,wheel):
 for x in (-1.2,1.2):box(x-.05,x+.05,-.05,.05,0,2.,'wood')
 roof(poly,-1.4,1.4,-.32,.32,2.,.22,'roof')
 for r in range(4):
  z=.65+r*.33;box(-1.2,1.2,-.012,.012,z+.21,z+.24,'dark')
  for c in range(13):
   x=-1.08+c*.18;s=-1 if (r+c)%2 else 1
   box(x-.075,x+.075,min(s*.02,s*.03),max(s*.02,s*.03),z,z+.17,'pale');poly([(x-.075,s*.03,z+.17),(x+.075,s*.03,z+.17),(x,s*.03,z+.21)],'pale')
   box(x-.05,x+.05,min(s*.031,s*.032),max(s*.031,s*.032),z+.04,z+.13,'white' if (r*5+c)%3 else 'red')
def charm(box,poly,bar,wheel):
 W,Dp,H=1.6,.9,2.3
 box(-W,W,-Dp,Dp,0,.05,'dark');box(-W,W,Dp-.08,Dp,0,H,'wood');box(-W,-W+.08,-Dp,Dp,0,H,'wood');box(W-.08,W,-Dp,Dp,0,H,'wood')
 box(-W,W,-Dp,-Dp+.08,0,.9,'wood');box(-W-.04,W+.04,-Dp-.18,-Dp+.12,.9,.96,'pale');box(-W,W,-Dp,-Dp+.08,H-.35,H,'wood')
 for x in (-W,-.04,W-.08):box(x,x+.08,-Dp,-Dp+.08,.9,H-.35,'dark')
 box(-W,W,-Dp,Dp,H,H+.04,'dark');roof(poly,-W-.35,W+.35,-Dp-.55,Dp+.3,H,.6,'roof')
 box(-W+.08,W-.08,Dp-.36,Dp-.08,.9,.94,'pale');box(-W+.08,W-.08,Dp-.36,Dp-.08,1.35,1.39,'pale')
 cs=['red','white','pink','blue','green','gold']
 for k in range(18):
  x=-1.35+k*.158;box(x-.05,x+.05,-Dp-.1,-Dp-.03,.96,1.1,cs[k%6])
 for z in (.94,1.39):
  for k in range(14):
   x=-1.35+k*.21;box(x-.06,x+.06,Dp-.3,Dp-.2,z,z+.2,cs[(k+int(z*3))%6])
def spabed(box,poly,bar,wheel):
 for x in (-.85,.85):
  for y in (-.3,.3):box(x-.04,x+.04,y-.04,y+.04,0,.55,'pale')
 box(-.95,.95,-.36,.36,.5,.56,'pale');box(-1.,.78,-.4,.4,.56,.68,'pad')
 # the head end has a face hole
 box(.78,1.,-.4,-.12,.56,.68,'pad');box(.78,1.,.12,.4,.56,.68,'pad');box(.9,1.,-.12,.12,.56,.68,'pad')
 box(-.98,.3,-.38,.38,.68,.7,'towel');box(-.7,-.3,-.2,.2,.7,.77,'towel2')
def towelcab(box,poly,bar,wheel):
 box(-.6,-.57,-.22,.22,0,1.8,'white');box(.57,.6,-.22,.22,0,1.8,'white');box(-.6,.6,.2,.22,0,1.8,'white');box(-.6,.6,-.22,.22,1.78,1.8,'white')
 for r in range(4):
  z=.05+r*.44;box(-.57,.57,-.22,.2,z,z+.03,'white')
  for c in range(4):
   for q in range(2):
    x=-.42+c*.28;m='towel2' if (r+c)%3==0 else 'towel';bar((x,-.2,z+.1+q*.14),(x,.15,z+.1+q*.14),.065,m,8)
def tandem(box,poly,bar,wheel):
 r=.33;z=r;F=-1.05;B=1.05
 wheel(F,0,z,r,'tire');wheel(B,0,z,r,'tire')
 bar((F,0,z),(F+.18,0,.95),.016,'red');bar((F+.18,0,.95),(F+.22,0,1.08),.016,'steel');bar((F+.22,-.24,1.08),(F+.22,.24,1.08),.012,'tire')
 s1,s2,c1,c2=-.25,.55,-.2,.6
 bar((F+.16,0,.82),(s1,0,.92),.022,'red');bar((F+.1,0,.62),(c1,0,.3),.022,'red');bar((c1,0,.3),(s1,0,.92),.022,'red');bar((c1,0,.3),(c2,0,.3),.022,'red');bar((s1,0,.92),(s2,0,.92),.022,'red');bar((c2,0,.3),(s2,0,.92),.022,'red');bar((c2,0,.3),(B,0,z),.016,'red');bar((s2,0,.92),(B,0,z),.016,'red')
 for s,c in ((s1,c1),(s2,c2)):
  bar((s,0,.92),(s+.02,0,1.02),.012,'steel');box(s-.12,s+.14,-.08,.08,1.02,1.08,'tire');bar((c,-.1,.3),(c,.1,.3),.012,'steel');box(c-.05,c+.05,-.16,-.1,.2,.23,'tire');box(c-.05,c+.05,.1,.16,.37,.4,'tire')
 bar((s1+.25,0,.92),(s1+.22,0,1.05),.014,'steel');bar((s1+.22,-.2,1.05),(s1+.22,.2,1.05),.012,'tire')
 box(B-.32,B+.1,-.1,.1,.72,.74,'steel')
def pen(box,poly,bar,wheel):
 # 8 x 6 m wooden pen, bare ground, a hay rack and a water trough; the fence is closed, people feed over the top rail
 W,Dp=4.,3.
 box(-W,W,-Dp,Dp,0,.03,'pale')
 for x,y0,y1 in ((-W,-Dp,Dp),(W,-Dp,Dp)):
  for k in range(7):
   y=y0+k*(y1-y0)/6;box(x-.05,x+.05,y-.05,y+.05,0,1.15,'wood')
  for z in (.45,.8,1.1):box(x-.03,x+.03,y0,y1,z,z+.08,'pale')
 for y in (-Dp,Dp):
  for k in range(9):
   x=-W+k*2*W/8;box(x-.05,x+.05,y-.05,y+.05,0,1.15,'wood')
  for z in (.45,.8,1.1):box(-W,W,y-.03,y+.03,z,z+.08,'pale')
 box(1.6,3.,1.9,2.5,.03,.5,'wood');box(1.65,2.95,1.95,2.45,.5,.72,'green');box(-3.2,-1.8,2.1,2.6,.03,.3,'stone');box(-3.1,-1.9,2.2,2.5,.3,.31,'water')
def ticket(box,poly,bar,wheel):
 W,Dp,H=1.1,.9,2.4
 box(-W,W,-Dp,-Dp+.08,0,.9,'red');box(-W,W,Dp-.08,Dp,0,H,'red');box(-W,-W+.08,-Dp,Dp,0,H,'red');box(W-.08,W,-Dp,Dp,0,H,'red');box(-W-.05,W+.05,-Dp-.2,-Dp+.1,.9,.96,'white');box(-W,W,-Dp,-Dp+.08,H-.4,H,'white');box(-W,W,-Dp,Dp,H,H+.05,'white');roof(poly,-W-.3,W+.3,-Dp-.5,Dp+.3,H,.55,'green')
def crafttable(box,poly,bar,wheel):
 for x in (-.9,.9):
  for y in (-.4,.4):box(x-.05,x+.05,y-.05,y+.05,0,.72,'wood')
 box(-1.,1.,-.5,.5,.72,.78,'pale');bar((-.5,0,.78),(-.5,0,.84),.2,'steel',12);bar((-.5,0,.84),(-.5,0,1.),.11,'wood',10);bar((.2,.2,.78),(.2,.2,.9),.08,'pad',8);bar((.5,-.15,.78),(.5,-.15,.86),.1,'pad',8);bar((.75,.25,.78),(.75,.25,.96),.06,'white',8)
 for k in range(4):bar((.05+k*.08,-.32,.79),(.3+k*.08,-.4,.79),.008,'dark',4)
def crate(box,poly,bar,wheel):
 box(-.4,.4,-.3,.3,0,.04,'pale')
 for x,a,b in ((-.4,-.3,.3),(.38,-.3,.3)):box(x,x+.02,a,b,0,.3,'pale')
 for y in (-.3,.28):box(-.4,.4,y,y+.02,0,.3,'pale')
 for i in range(5):
  for k in range(4):bar((-.3+i*.15,-.21+k*.14,.26),(-.3+i*.15,-.21+k*.14,.34),.065,'red',8)
def diningset(box,poly,bar,wheel):
 # a four-seat table: 140 x 80 cm top, chairs tucked along the long sides
 for x in (-.62,.62):
  for y in (-.33,.33):box(x-.03,x+.03,y-.03,y+.03,0,.7,'wood')
 box(-.7,.7,-.4,.4,.7,.74,'pale')
 for x in (-.36,.36):
  for s in (-1,1):
   y=s*.62
   for a in (-.17,.17):
    for b in (-.17,.17):box(x+a-.02,x+a+.02,y+b-.02,y+b+.02,0,.44,'wood')
   box(x-.2,x+.2,y-.2,y+.2,.44,.48,'pale');box(x-.2,x+.2,y+s*.17-.02,y+s*.17+.02,.48,.86,'wood')
def notice(box,poly,bar,wheel):
 for x in (-.85,.85):box(x-.05,x+.05,-.05,.05,0,2.,'wood')
 box(-.85,.85,-.03,.03,.85,1.85,'pale');box(-.95,.95,-.2,.2,1.95,2.02,'green')
 for x,z,w,h,m in ((-.6,1.3,.35,.42,'white'),(-.15,1.4,.3,.3,'red'),(.3,1.25,.42,.32,'white'),(.65,1.5,.2,.26,'green'),(-.3,1.,.5,.2,'white')):box(x-w/2,x+w/2,-.045,-.03,z-h/2,z+h/2,m)
def shower(box,poly,bar,wheel):
 box(-.4,.4,-.4,.4,0,.05,'stone');bar((0,0,.05),(0,0,2.2),.035,'steel',10);bar((0,0,2.2),(0,-.35,2.25),.025,'steel',8);bar((0,-.35,2.25),(0,-.35,2.18),.09,'steel',12);bar((.04,0,1.05),(.12,0,1.05),.02,'red',8)
def fruitstand(box,poly,bar,wheel):
 box(-.75,.75,-.45,.45,0,.5,'pale');box(-.75,.75,0,.45,.5,.8,'pale')
 for z,y0,m in ((.5,-.36,'red'),(.8,.08,'green')):
  for i in range(9):
   for k in range(3):bar((-.64+i*.16,y0+k*.14,z),(-.64+i*.16,y0+k*.14,z+.08),.07,m,8)
def kiosk(box,poly,bar,wheel):
 W,Dp,H=1.2,.5,2.2
 box(-W,W,-Dp,-Dp+.08,0,1.,'white');box(-W,W,Dp-.08,Dp,0,H,'white');box(-W,-W+.08,-Dp,Dp,0,H,'white');box(W-.08,W,-Dp,Dp,0,H,'white');box(-W-.05,W+.05,-Dp-.12,-Dp+.1,1.,1.05,'wood')
 box(-W,W,-Dp,Dp,H,H+.06,'red');box(-W,W,-Dp-.02,-Dp+.02,H-.32,H,'red');box(-.8,.8,Dp-.1,Dp-.08,1.3,1.9,'pale');roof(poly,-W-.2,W+.2,-Dp-.6,Dp+.1,H+.06,.25,'red')
for n,f in (('dining_set',diningset),('notice_board',notice),('beach_shower',shower),('fruit_display',fruitstand),('snack_kiosk',kiosk),('zoo_pen',pen),('ticket_booth',ticket),('craft_table',crafttable),('fruit_crate',crate),('saisen_box',saisen),('temizuya',temizuya),('omikuji_stand',omikuji),('ema_rack',ema),('charm_booth',charm),('spa_bed',spabed),('towel_cabinet',towelcab),('tandem_bike',tandem)):build(n,f)
]====]
local path = out .. '/fixtures-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/fixtures-blender.log" 2>&1"'))
print('wrote', out)
