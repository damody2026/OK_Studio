-- A chapel you can walk into, and the small home fixtures the Tripo sets do not have.
-- chapel.glb: 16 x 11 m hall, origin at the middle of the west doorway on the ground, +X runs up the aisle to the altar, gable
-- roof, bell tower over the door, six rows of pews each side, altar on a step. Side windows are holes; the install hangs
-- stained glass in them. chapel-walls.json lists the wall pieces for the install's collision boxes (metres, chapel frame).
-- washer.glb, mailbox_bank.glb: origin bottom centre, front on -Y like the other fixtures.
-- Writes output/street-social-city-production/hill-v1/; Tools/street_city_lover_spots_payload.lua places them.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_chapel.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
local code = [====[
import bpy,json,pathlib
D=pathlib.Path(TASK['out'])
COL=dict(wall=(.92,.9,.84,.8),trim=(.62,.5,.36,.6),roof=(.2,.24,.32,.8),floor=(.55,.42,.3,.5),pew=(.32,.19,.1,.5),cloth=(.72,.1,.14,.8),altar=(.95,.94,.9,.5),gold=(.8,.62,.2,.35),white=(.9,.91,.92,.4),dark=(.05,.06,.07,.5),steel=(.6,.62,.65,.4))
def build(name,fill):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 V=[];F=[];M=[];names=list(COL)
 def box(a,b,c,d,e,f,m):
  i=len(V);V.extend([(a,c,e),(b,c,e),(b,d,e),(a,d,e),(a,c,f),(b,c,f),(b,d,f),(a,d,f)])
  for q in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)):F.append(tuple(i+k for k in q));M.append(names.index(m))
 def poly(p,m):
  i=len(V);V.extend(p);F.append(tuple(range(i,i+len(p))));M.append(names.index(m))
 fill(box,poly)
 # the import mirrors Y: a front built on Blender -Y lands on Unreal +Y; the placements of these two expect -Y
 if name in ('washer','mailbox_bank'):V=[(x,-y,z) for x,y,z in V];F=[tuple(reversed(f)) for f in F]
 me=bpy.data.meshes.new(name);me.from_pydata(V,[],F);me.update()
 for n in names:
  m=bpy.data.materials.new('fx_'+n);m.use_nodes=True;q=m.node_tree.nodes['Principled BSDF'];c=COL[n];q.inputs['Base Color'].default_value=(c[0],c[1],c[2],1);q.inputs['Roughness'].default_value=c[3];me.materials.append(m)
 for p,k in zip(me.polygons,M):p.material_index=k
 me.uv_layers.new(name='UVMap')
 o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o)
 bpy.ops.export_scene.gltf(filepath=str(D/(name+'.glb')),export_format='GLB',use_selection=False,export_apply=True)
 print('MESH',name,len(F),flush=True)
L,W,H,T=16.,5.5,5.,.25
WALLS=[]
def chapel(box,poly):
 def wall(a,b,c,d,e=0,f=H):
  box(a,b,c,d,e,f,'wall');WALLS.append([a,b,c,d])
 box(0,L,-W,W,0,.05,'floor')
 # side walls with five window holes each, 1.4 m wide from 1.6 to 4 m
 for s,c,d in ((-1,-W,-W+T),(1,W-T,W)):
  x=0.
  for k in range(5):
   wx=1.6+k*2.9;wall(x,wx,c,d);box(wx,wx+1.4,c,d,0,1.6,'wall');box(wx,wx+1.4,c,d,4.,H,'wall');WALLS.append([wx,wx+1.4,c,d]);x=wx+1.4
  wall(x,L,c,d)
 wall(L-T,L,-W,W)
 wall(0,T,-W,-1.,);wall(0,T,1.,W);box(0,T,-1.,1.,3.,H,'wall')
 # gable ends and the roof
 r=3.6
 for x in (0,L-T):
  poly([(x,-W,H),(x,W,H),(x,0,H+r)],'wall');poly([(x+T,W,H),(x+T,-W,H),(x+T,0,H+r)],'wall')
 e=.5
 poly([(-.3,-W-e,H-.3),(L+.3,-W-e,H-.3),(L+.3,0,H+r+.1),(-.3,0,H+r+.1)],'roof');poly([(L+.3,W+e,H-.3),(-.3,W+e,H-.3),(-.3,0,H+r+.1),(L+.3,0,H+r+.1)],'roof')
 poly([(L+.3,-W-e,H-.32),(-.3,-W-e,H-.32),(-.3,0,H+r+.08),(L+.3,0,H+r+.08)],'trim');poly([(-.3,W+e,H-.32),(L+.3,W+e,H-.32),(L+.3,0,H+r+.08),(-.3,0,H+r+.08)],'trim')
 box(T,L-T,-W+T,W-T,H-.02,H,'trim')
 # the door frame, open doors folded back, the tower
 box(-.05,T+.05,-1.15,-1.,0,3.1,'trim');box(-.05,T+.05,1.,1.15,0,3.1,'trim');box(-.05,T+.05,-1.15,1.15,3.,3.15,'trim')
 box(.3,1.2,-1.08,-1.,.05,3,'pew');box(.3,1.2,1.,1.08,.05,3,'pew')
 box(-1.2,1.2,-1.2,1.2,H+r-.6,H+r+2.6,'wall');box(-1.25,1.25,-1.25,1.25,H+r+2.6,H+r+2.8,'trim')
 for a,b in ((-1.3,1.3),):
  poly([(a,-1.3,H+r+2.8),(b,-1.3,H+r+2.8),(0,0,H+r+5.)],'roof');poly([(b,-1.3,H+r+2.8),(b,1.3,H+r+2.8),(0,0,H+r+5.)],'roof');poly([(b,1.3,H+r+2.8),(a,1.3,H+r+2.8),(0,0,H+r+5.)],'roof');poly([(a,1.3,H+r+2.8),(a,-1.3,H+r+2.8),(0,0,H+r+5.)],'roof')
 z=H+r+5.;box(-.04,.04,-.04,.04,z-.1,z+1.,'gold');box(-.04,.04,-.3,.3,z+.55,z+.63,'gold')
 # red carpet up the aisle, pews, altar step, altar, cross, candles
 box(T,13.2,-.75,.75,.05,.06,'cloth')
 for k in range(6):
  x=3.+k*1.55
  for s in (-1,1):
   a,b=(-4.6,-1.) if s<0 else (1.,4.6)
   box(x,x+.42,a,b,.42,.47,"pew");box(x-.04,x+.04,a,b,.47,.95,"pew");box(x,x+.46,a,a+.06,.05,.95,'pew');box(x,x+.46,b-.06,b,.05,.95,'pew')
 box(13.2,L-T,-W+T,W-T,.05,.25,'floor');box(14.,15.,-1.1,1.1,.25,1.2,'altar');box(13.95,15.05,-1.15,1.15,1.2,1.26,'cloth')
 box(15.5,15.6,-.06,.06,1.5,4.2,'gold');box(15.5,15.6,-.7,.7,3.2,3.32,'gold')
 for y in (-.8,.8):box(14.45,14.5,y-.02,y+.02,1.26,1.6,'white');box(13.1,13.2,y*2.-.03,y*2.+.03,.05,1.3,'gold')
def washer(box,poly):
 box(-.3,.3,-.3,.3,0,.85,'white');box(-.2,.2,-.31,-.3,.2,.6,'dark');box(-.14,.14,-.32,-.31,.26,.54,'steel');box(-.26,.26,-.31,-.3,.68,.8,'steel')
def mailbox(box,poly):
 box(-.75,.75,-.15,.15,0,1.45,'steel')
 for r in range(4):
  for c in range(6):
   x=-.65+c*.22;z=.35+r*.27;box(x,x+.2,-.16,-.15,z,z+.24,'white');box(x+.04,x+.16,-.17,-.16,z+.17,z+.2,'dark')
HW=[]
def hall(box,poly):
 # the university auditorium: 26 x 18 m, 7 m high, door in the west end, stage at the east end, two blocks of seat rows
 L2,W2,H2,t=26.,9.,7.,.3
 def wl(a,b,c,d):
  box(a,b,c,d,0,H2,'wall');HW.append([a,b,c,d])
 box(0,L2,-W2,W2,0,.05,'floor')
 wl(0,L2,-W2,-W2+t);wl(0,L2,W2-t,W2);wl(L2-t,L2,-W2,W2);wl(0,t,-W2,-1.2);wl(0,t,1.2,W2);box(0,t,-1.2,1.2,3.2,H2,'wall')
 box(-.05,t+.05,-1.35,-1.2,0,3.3,'trim');box(-.05,t+.05,1.2,1.35,0,3.3,'trim');box(-.05,t+.05,-1.35,1.35,3.2,3.35,'trim')
 box(-.4,L2+.4,-W2-.4,W2+.4,H2,H2+.25,'roof');box(t,L2-t,-W2+t,W2-t,H2-.03,H2,'trim');box(-.5,.05,-3.,3.,3.6,6.,'trim')
 # stage, curtains, lectern, steps up the middle
 box(19.5,L2-t,-W2+t,W2-t,.05,1.05,'floor');box(19.45,19.5,-W2+t,W2-t,.05,1.05,'pew')
 box(25.2,25.5,-W2+t,W2-t,1.05,H2,'cloth');box(23.,25.2,-W2+t,-6.,1.05,H2,'cloth');box(23.,25.2,6.,W2-t,1.05,H2,'cloth');box(20.8,21.3,-.4,.4,1.05,2.2,'pew')
 box(18.3,19.45,-1.,1.,.05,.3,'floor');box(18.7,19.45,-1.,1.,.3,.55,'floor');box(19.1,19.45,-1.,1.,.55,.8,'floor')
 for k in range(10):
  x=4.+k*1.2
  for a,b in ((-8.,-1.2),(1.2,8.)):
   box(x,x+.48,a,b,.42,.48,'cloth');box(x-.05,x+.03,a,b,.48,.95,'cloth');box(x,x+.48,a,a+.06,.05,.68,'pew');box(x,x+.48,b-.06,b,.05,.68,'pew')
build('chapel',chapel);build('washer',washer);build('mailbox_bank',mailbox);build('auditorium',hall)
(D/'chapel-walls.json').write_text(json.dumps(WALLS),'utf8');(D/'auditorium-walls.json').write_text(json.dumps(HW),'utf8')
]====]
local path = out .. '/chapel-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/chapel-blender.log" 2>&1"'))
print('wrote', out .. '/chapel.glb')
