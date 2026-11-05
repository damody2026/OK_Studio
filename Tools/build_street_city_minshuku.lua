-- The minshuku building: minshuku_annex.glb, a one-storey Japanese inn, 34 x 12 m: entrance hall, four tatami guest rooms with
-- their own bath and toilet, a veranda along the front (-y), tiled hip roof. Local origin: centre of the floor. The front eave
-- reaches 20 cm further than the back one: the install reads from the bounding box which way the import turned y.
-- hill-v1/minshuku-walls.json lists the wall boxes (metres, local) for the collision actors of
-- Tools/street_city_lover_spots_payload.lua; rooms lists each room's box.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_minshuku.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
local code = [====[
import bpy,json,pathlib
D=pathlib.Path(TASK['out'])
bpy.ops.wm.read_factory_settings(use_empty=True)
COL=dict(wall=(.86,.82,.72,.8,0),timber=(.24,.15,.09,.6,0),roof=(.16,.17,.2,.55,0),tatami=(.62,.62,.38,.9,0),tatami2=(.56,.57,.34,.9,0),edge=(.12,.16,.1,.8,0),deck=(.42,.28,.16,.6,0),tile=(.72,.74,.74,.35,0),shoji=(.93,.91,.84,.7,0),steel=(.05,.055,.06,.4,1))
names=list(COL)
def build(name,fill):
 vs=[];fs=[];fm=[]
 def box(x0,x1,y0,y1,z0,z1,m):
  i=len(vs);vs.extend([(x,y,z) for z in (z0,z1) for y in (y0,y1) for x in (x0,x1)])
  for f in ((0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)):fs.append(tuple(i+k for k in f));fm.append(names.index(m))
 def poly(pts,m):
  i=len(vs);vs.extend(pts);fs.append(tuple(range(i,i+len(pts))));fm.append(names.index(m))
 fill(box,poly)
 me=bpy.data.meshes.new(name);me.from_pydata(vs,[],fs);me.update()
 used=sorted(set(fm))
 for k in used:
  r,g,b,rough,metal=COL[names[k]];m=bpy.data.materials.new('mk_'+names[k]);m.use_nodes=True;q=m.node_tree.nodes['Principled BSDF'];q.inputs['Base Color'].default_value=(r,g,b,1);q.inputs['Roughness'].default_value=rough;q.inputs['Metallic'].default_value=metal;me.materials.append(m)
 for p,k in zip(me.polygons,fm):p.material_index=used.index(k)
 me.uv_layers.new(name='UVMap')
 o=bpy.data.objects.new(name,me);bpy.context.scene.collection.objects.link(o)
 for x in bpy.context.scene.objects:x.select_set(x==o)
 bpy.ops.export_scene.gltf(filepath=str(D/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True)
 bpy.data.objects.remove(o);print('MESH',name,len(fs),flush=True)
H=2.7;T=.15;walls=[];rooms=[]
def wall(x0,x1,y0,y1):walls.append([x0,x1,y0,y1])
X0,X1,YF,YB,YS=-17,17,-4.5,6,2.5
# outer walls; the front wall has a door gap per room
wall(X0,X1,YB-T,YB);wall(X0,X0+T,YF,YB);wall(X1-T,X1,YF,YB)
for i in range(4):
 cx=-11+8*i
 wall(cx-4,cx-.8,YF,YF+T);wall(cx+.8,cx+4,YF,YF+T)
 wall(cx-4,cx-4+T,YF,YB)
 # bath and toilet behind the room: a door gap each in the partition, a wall between them
 wall(cx-4,cx-1.95,YS,YS+T);wall(cx-1.05,cx+2.05,YS,YS+T);wall(cx+2.95,cx+4,YS,YS+T);wall(cx+1,cx+1+T,YS,YB)
 rooms.append(dict(name='guest%d'%(i+1),cx=cx))
wall(-15,-15+T,YF,YB)
def inn(box,poly):
 box(-17.2,17.2,-6.2,6.2,-.6,.03,'deck')
 for w in walls:box(w[0],w[1],w[2],w[3],.03,H,'wall')
 # lintels over the door gaps: visual only, the collision walls stop at the jambs
 for i in range(4):
  cx=-11+8*i
  box(cx-.8,cx+.8,YF,YF+T,2.05,H,'wall');box(cx-1.95,cx-1.05,YS,YS+T,2.05,H,'wall');box(cx+2.05,cx+2.95,YS,YS+T,2.05,H,'wall')
 # timber frame, posts on the veranda
 for x in range(-17,18,4):
  box(x-.09,x+.09,YF-.03,YF+.18,.03,H,'timber');box(x-.08,x+.08,-5.92,-5.76,.03,H,'timber')
 box(-17,17,YF-.03,YF+.18,H-.14,H,'timber');box(-17,17,-5.92,-5.76,H-.14,H,'timber')
 # veranda planks
 for k in range(16):box(-17,17,-6+k*.094,-6+k*.094+.09,.03,.05,'deck')
 # shoji beside each door
 for i in range(4):
  cx=-11+8*i
  for a,b in ((cx-3.9,cx-.85),(cx+.85,cx+3.9)):
   box(a,b,YF-.04,YF-.01,.3,2.4,'shoji')
   for k in range(int((b-a)/.5)+1):box(a+k*.5-.012,a+k*.5+.012,YF-.05,YF-.03,.3,2.4,'timber')
   for k in range(6):box(a,b,YF-.05,YF-.03,.3+k*.42-.012,.3+k*.42+.012,'timber')
  # tatami: 1.8 x 0.9 mats with dark edges
  for ix in range(4):
   for iy in range(7):
    x0=cx-3.85+ix*1.93;y0=YF+.15+iy*1.0
    box(x0,x0+1.9,y0,y0+.98,.03,.06,'tatami' if (ix+iy)%2 else 'tatami2');box(x0,x0+1.9,y0-.02,y0,.03,.062,'edge')
  box(cx-3.85,cx+.98,YS+.15,YB-.15,.03,.05,'tile');box(cx+1.15,cx+3.85,YS+.15,YB-.15,.03,.05,'tile')
 # hip roof over walls and veranda, a ridge along x
 e=7.4;f=7.6;r=3.0;t=H
 poly([(-18,-f,t),(18,-f,t),(14.5,0,t+r),(-14.5,0,t+r)],'roof');poly([(18,e,t),(-18,e,t),(-14.5,0,t+r),(14.5,0,t+r)],'roof')
 poly([(-18,e,t),(-18,-f,t),(-14.5,0,t+r)],'roof');poly([(18,-f,t),(18,e,t),(14.5,0,t+r)],'roof')
 poly([(-18,-f,t),(-18,e,t),(18,e,t),(18,-f,t)],'timber')
 box(-14.6,14.6,-.14,.14,t+r-.06,t+r+.12,'timber')
build('minshuku_annex',inn)
(D/'minshuku-walls.json').write_text(json.dumps(dict(walls=walls,rooms=rooms,height=H)),'utf8')
]====]
local path = out .. '/minshuku-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/minshuku-blender.log" 2>&1"'))
print('wrote', out .. '/minshuku_annex.glb')
