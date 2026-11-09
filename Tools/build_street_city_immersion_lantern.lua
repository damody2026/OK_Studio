-- Recognizable nautical lantern head, anchored metal pole and cantilever arm.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/nautical-lantern'
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'))
local code=[====[
import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector
O=Path(TASK['out']);rows=[]
for lod,n in enumerate([24,14,8]):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 metal=bpy.data.materials.new('BronzeStructure');metal.diffuse_color=(.035,.05,.045,1)
 opal=bpy.data.materials.new('OpalLantern');opal.diffuse_color=(.82,.75,.5,1)
 def box(name,p,size,mat=metal):
  bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat);return o
 def cone(name,p,r1,r2,h,mat=metal):
  bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r1,radius2=r2,depth=h,location=p);o=bpy.context.object;o.name=name;o.data.materials.append(mat)
  for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
  return o
 def bar(name,a,b,r):
  a,b=Vector(a),Vector(b);o=cone(name,(a+b)/2,r,r,(b-a).length);o.rotation_mode='QUATERNION';o.rotation_quaternion=(b-a).to_track_quat('Z','Y');return o
 cone('Bolted base',(0,0,.025),.19,.19,.05);cone('Cast foot',(0,0,.16),.12,.08,.23);cone('Tapered post',(0,0,1.62),.055,.037,2.72)
 for z in [.29,.36,2.88,3.02]:cone('Collar',(0,0,z),.072,.072,.035)
 cone('Pole crown',(0,0,3.12),.08,.025,.14);cone('Finial',(0,0,3.255),.042,.004,.09)
 bar('Horizontal lantern arm',(0,0,3.08),(.46,0,3.08),.027);bar('Triangular brace',(0,0,2.78),(.38,0,3.08),.019);bar('Suspension',(.46,0,3.08),(.46,0,2.94),.018)
 cone('Weather hood',(.46,0,2.895),.21,.06,.10);cone('Hood rim',(.46,0,2.838),.215,.215,.018)
 box('Warm diffuse glass',(.46,0,2.67),(.228,.228,.29),opal)
 for x in [-.133,.133]:
  for y in [-.133,.133]:box('Lantern corner',(.46+x,y,2.67),(.022,.022,.34))
 box('Lower lantern tray',(.46,0,2.49),(.30,.30,.036));cone('Lantern underside',(.46,0,2.452),.12,.15,.04)
 if lod<2:
  for x in [-.11,.11]:
   for y in [-.11,.11]:cone('Base fastener',(x,y,.06),.014,.014,.02)
 for o in bpy.context.scene.objects:
  if o.type!='MESH':continue
  bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project();bpy.ops.object.mode_set(mode='OBJECT');o.select_set(False)
 path=O/('LOD'+str(lod)+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB');triangles=0
 for o in bpy.context.scene.objects:
  if o.type=='MESH':o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
 rows.append(dict(lod=lod,path=str(path),triangles=triangles,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(O/'build.json').write_text(json.dumps(dict(status='authored_requires_native_import',height_m=3.3,head_center_m=[.46,0,2.67],lods=rows),indent=2),'utf8')
print('Metal nautical lantern:',[r['triangles'] for r in rows])
]====]
local payload=out..'/build-payload.json';local f=assert(io.open(payload,'wb'));f:write(json.encode({out=out,code=code}));f:close()
local expression="import json;TASK=json.load(open('"..payload.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'))
print('Nautical lantern authored; import and actual runtime review remain required.')
