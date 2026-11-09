-- Classroom wall dressing (bulletin boards, wall clocks, wall charts) for teaching floors, one merged mesh per floor.
-- Slots come from the built geometry (shop-survey-v1/classroom-wall-plan.json, street_city_shop_survey_payload.lua
-- classroom_wall_plan); thinned here so a room does not collect several clocks: clock 7 m, board 5 m, chart 3 m apart.
-- Chart art: Grok images (grok-media/flat-front-on-classroom-wall-chart-texture-*), scaled to power-of-two textures.
-- Output: output/street-social-city-production/classroom-decor-v1/<floor actor>.glb + build.json
-- Usage: lua Tools/build_street_city_classroom_decor.lua
local code=[====[
import bpy,json,math,random,hashlib
from pathlib import Path
from mathutils import Vector
R=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=R/'classroom-decor-v1';O.mkdir(exist_ok=True)
G=Path('C:/portable/OpenKoikatsu/grok-media')
ART=[(G/'flat-front-on-classroom-wall-chart-texture-a-col-1.jpg',(1024,512),(1.2,.8)),(G/'flat-front-on-classroom-wall-chart-texture-illus-1.jpg',(1024,512),(1.2,.8)),(G/'flat-front-on-classroom-wall-chart-texture-botan-1.jpg',(512,1024),(.6,.9))]
plan=json.loads((R/'shop-survey-v1/classroom-wall-plan.json').read_text('utf8'));out=[]
GAP={'clock':700.,'board':500.,'chart':300.}
for fl in plan['floors']:
 kept=[]
 for it in fl['items']:
  if all(not(k['kind']==it['kind'] and math.hypot(k['at'][0]-it['at'][0],k['at'][1]-it['at'][1])<GAP[it['kind']]) for k in kept):kept.append(it)
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS={};OBJ=[]
 def mat(k,c,rough=.7,metal=0.,img=None):
  if k in MATS:return MATS[k]
  m=bpy.data.materials.new(k);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF'];b.inputs['Base Color'].default_value=(*c,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
  if img:
   path,size,_=img;im=bpy.data.images.load(str(path));im.scale(*size);im.filepath_raw=str(O/(path.stem+'-%dx%d.png'%size));im.file_format='PNG';im.save()
   t=m.node_tree.nodes.new('ShaderNodeTexImage');t.image=im;m.node_tree.links.new(t.outputs['Color'],b.inputs['Base Color'])
  MATS[k]=m;return m
 AX,AY,AZ=fl['anchor'][0],fl['anchor'][1],fl['floor_z']
 def L(x,y,z):return Vector(((x-AX)/100,-(y-AY)/100,(z-AZ)/100))
 def frame_of(it):
  n=Vector((it['normal'][0],-it['normal'][1],0)).normalized();right=(-n).cross(Vector((0,0,1))).normalized();return n,right
 def quad(c,n,right,w,h,m):
  up=Vector((0,0,1));vs=[c-right*w/2-up*h/2,c+right*w/2-up*h/2,c+right*w/2+up*h/2,c-right*w/2+up*h/2]
  me=bpy.data.meshes.new('q');me.from_pydata([tuple(v) for v in vs],[],[(0,1,2,3)]);uv=me.uv_layers.new()
  for li,(u,v) in enumerate(((0,0),(1,0),(1,1),(0,1))):uv.data[li].uv=(u,v)
  ob=bpy.data.objects.new('q',me);bpy.context.collection.objects.link(ob);me.materials.append(m);OBJ.append(ob);return ob
 def slab(c,n,right,depth,w,h,m,off=0.):
  bpy.ops.mesh.primitive_cube_add(size=1,location=tuple(c+n*(depth/2+off)));o=bpy.context.object;o.dimensions=(depth,w,h);o.rotation_euler.z=math.atan2(n.y,n.x);bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);o.data.materials.append(m);OBJ.append(o);return o
 random.seed(hash(fl['actor'])%997);counts={'board':0,'clock':0,'chart':0}
 for it in kept:
  c=L(*it['at']);n,right=frame_of(it);k=it['kind']
  if k=='board':
   slab(c,n,right,.02,1.24,.94,mat('board_frame',(.75,.76,.78),.35,.8));slab(c,n,right,.012,1.18,.88,mat('cork',(.62,.45,.28),.9),.02)
   for i in range(random.randint(4,7)):
    col=random.choice(((.97,.97,.95),(.98,.93,.6),(.96,.78,.82),(.75,.88,.97)))
    p=c+right*random.uniform(-.42,.42)+Vector((0,0,random.uniform(-.28,.28)))
    q=quad(p+n*.034,n,right,random.uniform(.18,.3),random.uniform(.22,.32),mat('paper%.2f'%col[1],col,.9));q.rotation_euler.z=0
    slab(p+Vector((0,0,.11)),n,right,.012,.025,.025,mat('pin',(.85,.1,.1),.4),.034)
  elif k=='clock':
   bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.18,depth=.045,location=tuple(c+n*.0225));o=bpy.context.object;o.rotation_euler=(0,math.pi/2,math.atan2(n.y,n.x));o.data.materials.append(mat('clock_rim',(.08,.08,.09),.4));OBJ.append(o)
   bpy.ops.mesh.primitive_cylinder_add(vertices=32,radius=.165,depth=.006,location=tuple(c+n*.047));o=bpy.context.object;o.rotation_euler=(0,math.pi/2,math.atan2(n.y,n.x));o.data.materials.append(mat('clock_face',(.97,.97,.95),.6));OBJ.append(o)
   hm=mat('clock_hand',(.05,.05,.05),.5)
   for i in range(12):a=i*math.pi/6;p=c+right*(.14*math.sin(a))+Vector((0,0,.14*math.cos(a)));slab(p,n,right,.004,.012,.025 if i%3 else .04,hm,.05)
   ha,ma=random.uniform(0,6.28),random.uniform(0,6.28)
   import mathutils
   for (ang,ln,wd,off) in ((ha,.085,.016,.055),(ma,.125,.01,.062)):
    # build the hand pointing up from the dial centre, then turn it about the wall normal through the centre
    o=slab(c+Vector((0,0,ln/2)),n,right,.006,wd,ln,hm,off)
    # slab() keeps the object location (mesh data is local), so turn the object's world matrix, not its mesh data
    o.matrix_world=mathutils.Matrix.Translation(c)@mathutils.Matrix.Rotation(-ang,4,n)@mathutils.Matrix.Translation(-c)@o.matrix_world
   slab(c,n,right,.006,.02,.02,mat('clock_pin',(.75,.1,.1),.4),.068)
  else:
   # the plan's art index is constant for charts (kind and art both derive from n+di): pick the art from the position
   ai=(int(it['at'][0])*7+int(it['at'][1])*13)%3;art=ART[ai];w,h=art[2];it['art']=ai
   slab(c,n,right,.015,w+.04,h+.04,mat('chart_frame',(.2,.15,.1),.5));quad(c+n*.017,n,right,w,h,mat('art%d'%ai,(1,1,1),.8,img=art))
  counts[k]+=1
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=OBJ[0];bpy.ops.object.join();o=bpy.context.object;o.name=fl['actor']+'_ClassDecor'
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 p=O/(fl['actor']+'.glb');bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',export_apply=True,export_yup=True,export_image_format='AUTO');o.data.calc_loop_triangles()
 out.append(dict(actor=fl['actor'],path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),anchor_cm=[AX,AY,AZ],counts=counts,triangles=len(o.data.loop_triangles),items=[dict(kind=i['kind'],at=i['at'],normal=i['normal'],art=i.get('art')) for i in kept]))
(O/'build.json').write_text(json.dumps(dict(plan_map_sha256=plan['map_sha256'],floors=out),ensure_ascii=False,indent=1),'utf8')
t={'board':0,'clock':0,'chart':0}
for f in out:
 for k in t:t[k]+=f['counts'][k]
print('CLASSROOM DECOR',len(out),'floors',json.dumps(t))
]====]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production'
os.execute('mkdir "'..out:gsub('/','\\')..'\\classroom-decor-v1" 2>nul')
local path=out..'/classroom-decor-v1/build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({code=code}));f:close()
local expr="import json;exec(json.load(open('"..path.."',encoding='utf8'))['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/classroom-decor-build.log" 2>&1"'))
for line in io.lines(out..'/classroom-decor-build.log')do if line:find('CLASSROOM DECOR') or line:find('Error') then print(line) end end
