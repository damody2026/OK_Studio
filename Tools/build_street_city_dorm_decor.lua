-- Dorm room dressing for D1..D4 (bedding on every bunk level, desk items), one merged mesh per dorm floor layout.
-- Positions come from the built geometry (shop-survey-v1/dorm-scan.json, Tools/street_city_shop_survey_payload.lua dorm_scan):
-- the mesh origin is the D1_F02 anchor (actor XY, scanned floor level); every D-building floor gets one actor offset from it.
-- Output: output/street-social-city-production/dorm-decor-v1/dorm-floor-decor.glb + build.json
-- Usage: lua Tools/build_street_city_dorm_decor.lua
local code=[====[
import bpy,json,math,random,hashlib
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=R/'dorm-decor-v1';O.mkdir(exist_ok=True)
scan=json.loads((R/'shop-survey-v1/dorm-scan.json').read_text('utf8'));src=next(f for f in scan['floors'] if f['actor']=='Campus_D1_F02')
AX,AY,AZ=93200.0,37000.0,scan['source_floor_z']
bpy.ops.wm.read_factory_settings(use_empty=True);MATS={}
def mat(k,c,rough=.8,metal=0.,emit=0.):
 if k in MATS:return MATS[k]
 m=bpy.data.materials.new(k);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*c,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
 if emit:b.inputs['Emission Color'].default_value=(*c,1);b.inputs['Emission Strength'].default_value=emit
 MATS[k]=m;return m
OBJ=[]
def box(p,s,m,bev=0,rz=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.dimensions=s;o.rotation_euler.z=rz;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 if bev:
  b=o.modifiers.new('b','BEVEL');b.width=min(bev,min(s)*.45);b.segments=3;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=b.name)
  for f in o.data.polygons:f.use_smooth=True
 o.data.materials.append(m);OBJ.append(o);return o
def cyl(p,r,h,m,n=16,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=p);o=bpy.context.object;o.data.materials.append(m);OBJ.append(o);return o
# UE (cm, Y) -> Blender metres (glTF import negates Y)
def L(x,y,z):return ((x-AX)/100,-(y-AY)/100,z/100)
PAL=[((.93,.92,.88),(.35,.45,.62),(.95,.95,.93)),((.92,.9,.86),(.72,.35,.38),(.96,.94,.9)),((.9,.92,.9),(.42,.58,.45),(.95,.96,.94)),((.94,.9,.86),(.85,.66,.32),(.97,.95,.9))]
random.seed(7);beds=0;desks=0
for b in src['beds']:
 long_y=b['sy']>=b['sx'];Lm=max(b['sx'],b['sy'])/100;Wm=min(b['sx'],b['sy'])/100
 for lvl,h in (('up',b['h']),('low',b.get('low_h'))):
  if h is None or h<20:continue
  sheet,duvet,pil=PAL[random.randrange(4)];k=str(PAL.index((sheet,duvet,pil)))
  x,y,z=L(b['x'],b['y'],h);rz=math.pi/2 if long_y else 0  # mesh built along X, rotated onto the bed's long axis
  def at(u,v,w):return (x+u*math.cos(rz)-v*math.sin(rz),y+u*math.sin(rz)+v*math.cos(rz),z+w)
  box(at(0,0,.02),(Lm-.04,Wm-.04,.04),mat('sheet'+k,sheet,.9),.01,rz)
  box(at(-.2,0,.075),(Lm*.62,Wm,.08),mat('duvet'+k,duvet,.85),.03,rz)
  box(at(Lm*.11,0,.12),(.32,Wm*.98,.05),mat('duvet'+k,duvet,.85),.02,rz)   # folded edge
  box(at(Lm/2-.25,0,.1),(.34,Wm*.68,.13),mat('pillow'+k,pil,.9),.05,rz)
  beds+=1
for d in src['desks']:
 long_y=d['sy']>=d['sx'];rz=math.pi/2 if long_y else 0;Lm=max(d['sx'],d['sy'])/100;x,y,z=L(d['x'],d['y'],d['h'])
 def at(u,v,w):return (x+u*math.cos(rz)-v*math.sin(rz),y+u*math.sin(rz)+v*math.cos(rz),z+w)
 v=random.randrange(3)
 if v==0:
  for i,c in enumerate(((.55,.18,.15),(.2,.32,.5),(.85,.8,.65))):box(at(-Lm*.3,.05,.015+i*.03),(.24,.17,.028),mat('book%d'%i,c,.7),0,rz+.15*i)
  cyl(at(Lm*.32,.1,.01),.06,.02,mat('lamp_base',(.15,.15,.16),.4,.6));cyl(at(Lm*.32,.1,.2),.008,.38,mat('lamp_base',(.15,.15,.16),.4,.6),6);cyl(at(Lm*.32,.02,.38),.07,.1,mat('lamp_shade',(1.,.92,.75),.6,0,2.),16,.05)
 elif v==1:
  box(at(0,0,.008),(.33,.23,.016),mat('laptop',(.62,.63,.66),.3,.7),.004,rz);o=box(at(0,.11,.11),(.33,.012,.22),mat('laptop',(.62,.63,.66),.3,.7),.004,rz)
  box(at(0,.103,.11),(.3,.004,.19),mat('screen',(.25,.4,.6),.2,0,1.2),0,rz);cyl(at(Lm*.3,-.05,.05),.04,.1,mat('mug',(.9,.88,.84),.5),12)
 else:
  cyl(at(Lm*.32,.05,.06),.07,.12,mat('pot',(.62,.36,.22),.8),12,.055)
  for i in range(6):a=i*1.05;o=box(at(Lm*.32+.06*math.cos(a),.05+.06*math.sin(a),.17),(.12,.04,.012),mat('leaf',(.22,.48,.2),.7),0,a)
  for i in range(2):box(at(-Lm*.25,0,.015+i*.03),(.22,.16,.028),mat('book%d'%(i+1),((.2,.32,.5),(.85,.8,.65))[i],.7),0,rz)
 desks+=1
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=OBJ[0];bpy.ops.object.join();o=bpy.context.object;o.name='DormFloorDecor'
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
out=O/'dorm-floor-decor.glb';bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_apply=True,export_yup=True)
o.data.calc_loop_triangles()
(O/'build.json').write_text(json.dumps(dict(path=str(out),sha256=hashlib.sha256(out.read_bytes()).hexdigest(),anchor_cm=[AX,AY,AZ],source=src['actor'],scan_map_sha256=scan['map_sha256'],beds=beds,desks=desks,triangles=len(o.data.loop_triangles),
 floors=[dict(actor=f['actor'],floor_z=f['floor_z'],beds=len(f['beds']),desks=len(f['desks'])) for f in scan['floors']]),ensure_ascii=False,indent=1),'utf8')
print('DORM DECOR',beds,'bed levels',desks,'desks',len(o.data.loop_triangles),'tris')
]====]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production'
os.execute('mkdir "'..out:gsub('/','\\')..'\\dorm-decor-v1" 2>nul')
local path=out..'/dorm-decor-v1/build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({code=code}));f:close()
local expr="import json;exec(json.load(open('"..path.."',encoding='utf8'))['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/dorm-decor-build.log" 2>&1"'))
for line in io.lines('C:/portable/OpenKoikatsu/output/street-social-city-production/dorm-decor-build.log')do if line:find('DORM DECOR') or line:find('Error') then print(line) end end
