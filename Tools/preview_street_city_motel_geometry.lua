package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local code=[====[
import bpy,json,math
from pathlib import Path
from mathutils import Vector
O=Path(TASK['out']);rooms=json.loads((O/'suite-build.json').read_text('utf8'))['rooms'];plan=json.loads((O/'motel-plan.json').read_text('utf8'))['rooms'];pick=[rooms[0],next(r for r,q in zip(rooms,plan) if q['is_pool_suite'])];(O/'geometry-preview').mkdir(exist_ok=True)
for i,r in enumerate(pick):
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=r['path']);scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=1000;scene.render.resolution_y=700;scene.render.resolution_percentage=100;scene.world=bpy.data.worlds.new('Dim ambient');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.14,.16,.20,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
 for p in r['lights_local']:
  light=bpy.data.lights.new('Room practical','AREA');light.energy=450;light.shape='DISK';light.size=3;obj=bpy.data.objects.new('Room practical',light);bpy.context.collection.objects.link(obj);obj.location=p
 for kind,eye,target in [('bed',r['eye_local'],r['target_local']),('bath',r['bath_eye_local'],r['bathroom_mirror_local']['face'])]:
  c=bpy.data.cameras.new('Geometry check');ob=bpy.data.objects.new('Geometry camera',c);bpy.context.collection.objects.link(ob);ob.location=eye;ob.rotation_euler=(Vector(target)-Vector(eye)).to_track_quat('-Z','Y').to_euler();c.lens=20;scene.camera=ob;scene.render.filepath=str(O/'geometry-preview'/(str(i)+'-'+kind+'.png'));bpy.ops.render.render(write_still=True)
]====]
local p=out..'/geometry-preview-payload.json';local f=assert(io.open(p,'wb'));f:write(j.encode({out=out,code=code}));f:close();local expr="import json;TASK=json.load(open('"..p.."',encoding='utf8'));exec(TASK['code'])";assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..out..'/geometry-preview.log" 2>&1"'))
