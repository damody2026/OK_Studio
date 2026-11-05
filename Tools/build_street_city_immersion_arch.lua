-- Physical replacement for the R018 garden gate: connected posts, arches,
-- rafters, diagonal braces and anchored feet, with three geometric LODs.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/arch'
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'))
local code=[====[
import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector
O=Path(TASK['out']);rows=[]
for lod,segments in enumerate([28,18,10]):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 wood=bpy.data.materials.new('WalnutFrame');wood.diffuse_color=(.12,.065,.032,1)
 metal=bpy.data.materials.new('BronzeAnchors');metal.diffuse_color=(.04,.055,.045,1)
 def box(name,center,size,material=wood):
  bpy.ops.mesh.primitive_cube_add(size=1,location=center);ob=bpy.context.object;ob.name=name;ob.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);ob.data.materials.append(material)
  if lod<2:
   bevel=ob.modifiers.new('Rounded engineered timber edges','BEVEL');bevel.width=.004;bevel.segments=2 if lod==0 else 1;bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=bevel.name)
  return ob
 def bar(name,a,b,width):
  a,b=Vector(a),Vector(b);ob=box(name,(a+b)/2,(width,width,(b-a).length));ob.rotation_mode='QUATERNION';ob.rotation_quaternion=(b-a).to_track_quat('Z','Y');return ob
 for x in [-1.32,1.32]:
  for y in [-.22,.22]:
   box('Anchored foot',(x,y,.025),(.21,.21,.05),metal);box('Timber post',(x,y,1.52),(.12,.12,3.0))
   bar('Diagonal corner brace',(x,y,2.55),(x-math.copysign(.4,x),y,3.23),.09)
   if lod==0:
    for dx in [-.067,.067]:
     for dy in [-.067,.067]:box('Anchor bolt',(x+dx,y+dy,.057),(.018,.018,.014),metal)
 for y in [-.22,.22]:
  vertices=[];faces=[]
  for i in range(segments+1):
   x=-1.38+2.76*i/segments;z=3.+.5*(1-(x/1.38)**2);slope=-x/(1.38**2);n=Vector((-slope,0,1)).normalized()
   for sy,sz in [(-1,-1),(1,-1),(1,1),(-1,1)]:vertices.append(tuple(Vector((x,y+sy*.06,z))+n*(sz*.06)))
  for i in range(segments):
   for j in range(4):faces.append([i*4+j,i*4+(j+1)%4,(i+1)*4+(j+1)%4,(i+1)*4+j])
  faces.extend([[3,2,1,0],[segments*4+j for j in range(4)]]);mesh=bpy.data.meshes.new('Continuous curved frame');mesh.from_pydata(vertices,[],faces);mesh.materials.append(wood);ob=bpy.data.objects.new('Continuous curved frame',mesh);bpy.context.collection.objects.link(ob)
 for i in range(11):
  x=-1.38+2.76*i/10;z=3.+.5*(1-(x/1.38)**2);box('Supported shade rafter',(x,0,z+.11),(.09,.78,.12))
 for ob in bpy.context.scene.objects:
  if ob.type!='MESH':continue
  bpy.context.view_layer.objects.active=ob;ob.select_set(True)
  if not ob.data.uv_layers:
   bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project();bpy.ops.object.mode_set(mode='OBJECT')
  ob.select_set(False)
 path=O/('LOD'+str(lod)+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB')
 triangles=0
 for ob in bpy.context.scene.objects:
  if ob.type=='MESH':ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
 assert triangles<9000;rows.append(dict(lod=lod,path=str(path),triangles=triangles,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(O/'build.json').write_text(json.dumps(dict(status='authored_requires_native_import',clear_frame_height_m=3.,top_m=3.67,lods=rows),indent=2),'utf8')
print('Connected timber garden gate built:',[r['triangles'] for r in rows])
]====]
local payload=out..'/build-payload.json';local f=assert(io.open(payload,'wb'));f:write(json.encode({out=out,code=code}));f:close()
local expression="import json;TASK=json.load(open('"..payload.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'))
print('Garden gate authored; native import and rendered review required.')
