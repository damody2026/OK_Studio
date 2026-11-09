-- One balcony for a building facade: concrete slab 3 m wide and 1.3 m deep, steel rail with balusters, a glass door on the
-- wall behind it, about 300 triangles. +X points away from the wall; Tools/street_city_lover_spots_payload.lua places one
-- per home. Writes output/street-social-city-production/hill-v1/balcony.glb
-- Usage: Tools\lua\lua.exe Tools\build_street_city_balcony.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
local code = [====[
import bpy,pathlib
D=pathlib.Path(TASK['out'])
bpy.ops.wm.read_factory_settings(use_empty=True)
COL=dict(concrete=(.72,.71,.68,.8,0),steel=(.13,.14,.16,.45,1),glass=(.32,.45,.55,.12,0),frame=(.4,.38,.34,.5,0))
names=list(COL);mats=[]
for n in names:
 r,g,b,rough,metal=COL[n];m=bpy.data.materials.new('balcony_'+n);m.use_nodes=True;q=m.node_tree.nodes['Principled BSDF'];q.inputs['Base Color'].default_value=(r,g,b,1);q.inputs['Roughness'].default_value=rough;q.inputs['Metallic'].default_value=metal;mats.append(m)
vs=[];fs=[];fm=[]
def box(x0,x1,y0,y1,z0,z1,m):
 i=len(vs);vs.extend([(x,y,z) for z in (z0,z1) for y in (y0,y1) for x in (x0,x1)])
 for f in ((0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)):fs.append(tuple(i+k for k in f));fm.append(m)
box(0,1.3,-1.5,1.5,-.14,0,0)
box(1.26,1.3,-1.5,1.5,1.05,1.1,1);box(0,1.3,-1.5,-1.46,1.05,1.1,1);box(0,1.3,1.46,1.5,1.05,1.1,1)
for k in range(16):
 y=-1.46+k*2.92/15;box(1.27,1.29,y-.01,y+.01,0,1.05,1)
for k in range(1,7):
 x=k*1.3/7;box(x-.01,x+.01,-1.49,-1.47,0,1.05,1);box(x-.01,x+.01,1.47,1.49,0,1.05,1)
box(.01,.04,-.7,.7,0,2.2,3);box(.04,.05,-.64,-.02,.06,2.14,2);box(.04,.05,.02,.64,.06,2.14,2)
me=bpy.data.meshes.new('balcony');me.from_pydata(vs,[],fs);me.update()
for m in mats:me.materials.append(m)
for p,m in zip(me.polygons,fm):p.material_index=m
me.uv_layers.new(name='UVMap')
o=bpy.data.objects.new('balcony',me);bpy.context.scene.collection.objects.link(o)
bpy.ops.export_scene.gltf(filepath=str(D/'balcony.glb'),export_format='GLB',use_selection=False,export_apply=True)
print('BALCONY',len(fs),flush=True)
]====]
local path = out .. '/balcony-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/balcony-blender.log" 2>&1"'))
print('wrote', out .. '/balcony.glb')
