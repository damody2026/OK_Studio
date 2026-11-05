-- Office dressing for scanned floors (shop-survey-v1/office-scan.json, Tools/street_city_shop_survey_payload.lua office_scan):
-- desk items at both desk ends (the desk centre keeps its monitor), a floor plant at every other desk with a clear spot.
-- Teaching-building floors only dress small desk groups (<= 6 desks within 2.6 m chains); classroom rows are skipped.
-- One mesh per floor, origin at the floor actor's XY and scanned floor level.
-- Output: output/street-social-city-production/office-decor-v1/<floor actor>.glb + build.json
-- Usage: lua Tools/build_street_city_office_decor.lua
local code=[====[
import bpy,json,math,random,hashlib
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=R/'office-decor-v1';O.mkdir(exist_ok=True)
scan=json.loads((R/'shop-survey-v1/office-scan.json').read_text('utf8'));out=[]
for fl in scan['floors']:
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS={};OBJ=[]
 def mat(k,c,rough=.8,metal=0.,emit=0.):
  if k in MATS:return MATS[k]
  m=bpy.data.materials.new(k);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*c,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
  if emit:b.inputs['Emission Color'].default_value=(*c,1);b.inputs['Emission Strength'].default_value=emit
  MATS[k]=m;return m
 def box(p,s,m,rz=0):
  bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.dimensions=s;o.rotation_euler.z=rz;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);o.data.materials.append(m);OBJ.append(o);return o
 def cyl(p,r,h,m,n=12,r2=None):
  bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=p);o=bpy.context.object;o.data.materials.append(m);OBJ.append(o);return o
 AX,AY,AZ=fl['anchor'][0],fl['anchor'][1],fl['floor_z']
 def L(x,y,z):return ((x-AX)/100,-(y-AY)/100,z/100)
 random.seed(fl['actor']);plants=0;desks=fl['desks']  # str seed: stable across runs (hash() is randomised per process)
 if not fl['actor'].startswith(('Campus_AD_','Campus_LI_','City_CV_','City_TR_')):
  # teaching buildings: classrooms and labs hold rows of identical desks; only small groups (staff offices) are dressed.
  # Desks chain into a group when their centres are within 2.6 m; groups of more than 6 desks are left as they are.
  # classroom buildings (E1 EE MA T1 T2 T4 RB): rows of long student tables, so a wider chain (3.2 m) and groups of <= 4;
  # lab / office buildings (SC IB IN ...): <= 6 within 2.6 m
  cls=fl['actor'][7:9] in ('E1','EE','MA','T1','T2','T4','RB');CH,GMAX=(320,4) if cls else (260,6)
  par=list(range(len(desks)))
  def root(i):
   while par[i]!=i:par[i]=par[par[i]];i=par[i]
   return i
  for a in range(len(desks)):
   for b in range(a):
    if (desks[a]['x']-desks[b]['x'])**2+(desks[a]['y']-desks[b]['y'])**2<=CH**2:par[root(a)]=root(b)
  # plain loops: Blender's --python-expr exec gives comprehensions no view of these loop-local names
  size={};keep_d=[]
  for i in range(len(desks)):size[root(i)]=size.get(root(i),0)+1
  for i in range(len(desks)):
   if size[root(i)]<=GMAX:keep_d.append(desks[i])
  desks=keep_d
  print('OFFICE DECOR',fl['actor'],'staff desks',len(desks),'of',len(fl['desks']),flush=True)
 if not desks:continue
 for n,d in enumerate(desks):
  long_y=d['sy']>=d['sx'];rz=math.pi/2 if long_y else 0;Lm=max(d['sx'],d['sy'])/100;x,y,z=L(d['x'],d['y'],d['h'])
  def at(u,v,w):return (x+u*math.cos(rz)-v*math.sin(rz),y+u*math.sin(rz)+v*math.cos(rz),z+w)
  for end in (-1,1):
   u=end*(Lm/2-.17);v=random.randrange(3)
   if fl['actor'].startswith('Campus_LI_'):
    # library reading desks: open book, a stack of books, or a green-shade banker's lamp (shade glows)
    if v==0:
     cov=((.5,.12,.1),(.1,.25,.45),(.15,.35,.2))[n%3];box(at(u,-.02,.012),(.3,.22,.024),mat('cover%d'%(n%3),cov,.6),rz)
     for s in (-1,1):o=box(at(u+s*.072,-.02,.032),(.14,.2,.016),mat('page',(.96,.94,.88),.9),rz);o.rotation_euler.y=-s*.08
    elif v==1:
     for i in range(random.randrange(3,6)):box(at(u,.02,.02+i*.034),(.2+.02*(i%2),.26-.015*i,.032),mat('libbook%d'%(i%4),((.55,.15,.12),(.12,.28,.5),(.2,.4,.22),(.7,.6,.35))[i%4],.6),rz+random.uniform(-.25,.25))
    else:
     cyl(at(u,.06,.01),.07,.02,mat('brass',(.75,.6,.3),.35,.8));cyl(at(u,.06,.17),.01,.32,mat('brass',(.75,.6,.3),.35,.8))
     o=cyl(at(u,0,.33),.06,.22,mat('lampshade',(.1,.45,.2),.3,0.,2.),12);o.rotation_euler.x=math.pi/2;o.rotation_euler.z=rz
    continue
   if v==0:
    box(at(u,0,.03),(.26,.34,.06),mat('tray',(.12,.12,.13),.5),rz)
    for i in range(3):box(at(u,0,.065+i*.012),(.22,.3,.01),mat('paper',(.95,.95,.93),.9),rz+.05*i)
   elif v==1:
    for i,c in enumerate(((.15,.3,.6),(.6,.15,.15),(.15,.45,.25),(.85,.7,.2))):box(at(u+(i-1.5)*.055,.1,.15),(.05,.24,.3),mat('binder%d'%i,c,.6),rz)
   else:
    cyl(at(u,.08,.05),.035,.1,mat('pencup',(.2,.2,.22),.5));box(at(u,-.08,.025),(.18,.2,.05),mat('phone',(.08,.08,.09),.4),rz);cyl(at(u+.1,.08,.05),.04,.1,mat('mug',(.9,.88,.84),.5))
  if d.get('plant') and n%2==0:
   px,py,_=L(d['plant'][0],d['plant'][1],0);cyl((px,py,.22),.2,.44,mat('planter',(.85,.84,.8),.6),16,.16)
   for i in range(12):a=i*.52;o=box((px+.12*math.cos(a),py+.12*math.sin(a),.62+.08*(i%3)),(.42,.07,.012),mat('leaf',(.2,.42,.18),.7),a);o.rotation_euler.y=.5;plants+=0
   plants+=1
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=OBJ[0];bpy.ops.object.join();o=bpy.context.object;o.name=fl['actor']+'_Decor'
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 p=O/(fl['actor']+'.glb');bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',export_apply=True,export_yup=True);o.data.calc_loop_triangles()
 out.append(dict(actor=fl['actor'],path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),anchor_cm=[AX,AY,AZ],desks=len(desks),plants=plants,triangles=len(o.data.loop_triangles)))
(O/'build.json').write_text(json.dumps(dict(scan_map_sha256=scan['map_sha256'],floors=out),ensure_ascii=False,indent=1),'utf8')
print('OFFICE DECOR',len(out),'floors',sum(f['desks'] for f in out),'desks',sum(f['plants'] for f in out),'plants')
]====]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production'
os.execute('mkdir "'..out:gsub('/','\\')..'\\office-decor-v1" 2>nul')
local path=out..'/office-decor-v1/build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({code=code}));f:close()
local expr="import json;exec(json.load(open('"..path.."',encoding='utf8'))['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/office-decor-build.log" 2>&1"'))
for line in io.lines(out..'/office-decor-build.log')do if line:find('OFFICE DECOR') or line:find('Error') then print(line) end end
