-- A 3 x 3 m patch of flowers for the flower_field place: stems, leaves and five-petal blossoms in five colours, about
-- 1500 triangles. The Tripo meadow patches came out as crumpled sheets at this size, so this one is built from parts.
-- Writes output/street-social-city-production/hill-v1/flower_patch.glb; Tools/street_city_lover_spots_payload.lua tiles it.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_flower_patch.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
local code = [====[
import bpy,math,random,pathlib
D=pathlib.Path(TASK['out']);N=int(TASK['flowers']);random.seed(11)
bpy.ops.wm.read_factory_settings(use_empty=True)
COL=dict(leaf=(.16,.42,.12),pink=(.95,.35,.55),yellow=(.98,.8,.15),white=(.95,.94,.88),purple=(.55,.3,.85),red=(.9,.15,.15))
names=list(COL);mats=[]
for n in names:
 m=bpy.data.materials.new('flower_'+n);m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*COL[n],1);m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.8;mats.append(m)
vs=[];fs=[];fm=[]
def tri(a,b,c,m):
 i=len(vs);vs.extend([a,b,c]);fs.append((i,i+1,i+2));fm.append(m)
for k in range(N):
 x,y=random.uniform(-1.45,1.45),random.uniform(-1.45,1.45);h=random.uniform(.28,.6);c=random.randint(1,5);a=random.uniform(0,6.28);r=random.uniform(.045,.08)
 w=.012;tx,ty=math.cos(a)*w,math.sin(a)*w
 tri((x-tx,y-ty,0),(x+tx,y+ty,0),(x,y,h),0)
 for s in (-1,1):
  q=a+s*1.2;lx,ly=x+math.cos(q)*.12,y+math.sin(q)*.12;tri((x-tx,y-ty,.02),(x+tx,y+ty,.02),(lx,ly,h*.55),0)
 for p in range(5):
  b=a+p*1.257;b2=b+1.257;tri((x,y,h),(x+math.cos(b)*r,y+math.sin(b)*r,h+.012),(x+math.cos(b2)*r,y+math.sin(b2)*r,h+.012),c)
me=bpy.data.meshes.new('flower_patch');me.from_pydata(vs,[],fs);me.update()
for m in mats:me.materials.append(m)
for p,m in zip(me.polygons,fm):p.material_index=m
uv=me.uv_layers.new(name='UVMap')
o=bpy.data.objects.new('flower_patch',me);bpy.context.scene.collection.objects.link(o)
bpy.ops.export_scene.gltf(filepath=str(D/'flower_patch.glb'),export_format='GLB',use_selection=False,export_apply=True)
print('PATCH',len(fs),flush=True)
]====]
local path = out .. '/flower-patch-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code, flowers = 180 })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/flower-patch-build.log" 2>&1"'))
print('wrote', out .. '/flower_patch.glb')
