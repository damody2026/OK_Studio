-- A walkable grass mound for the `hill` place (c-conquest 8.2: 小山觀景點). The city has no natural high ground inside the
-- walk area, so this is one low-poly mesh: flat top, slopes under 20 degrees, origin at the centre of its base.
-- Writes output/street-social-city-production/hill-v1/hill.glb; Tools/street_city_lover_spots_payload.lua places it.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_hill.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
os.execute('mkdir "' .. out:gsub('/', '\\') .. '" 2>nul')
local code = [====[
import bpy,math,random,pathlib
D=pathlib.Path(TASK['out']);R=float(TASK['radius']);H=float(TASK['height']);TOP=float(TASK['top']);N=int(TASK['rings']);S=int(TASK['spokes'])
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)
def height(r,a):
 # a smooth shoulder from the flat top to the lawn, a little uneven so the outline is not a perfect cone
 if r<=TOP:return H
 t=min(1,(r-TOP)/(R-TOP));s=1-(t*t*(3-2*t))
 return H*s*(1+.06*math.sin(a*3+1)*math.sin(t*math.pi))
vs=[(0,0,H)];fs=[]
for i in range(1,N+1):
 r=R*i/N
 for k in range(S):
  a=2*math.pi*k/S;rr=r*(1+.05*math.sin(a*2+.7)*(i/N));vs.append((rr*math.cos(a),rr*math.sin(a),height(r,a)))
for k in range(S):fs.append((0,1+k,1+(k+1)%S))
for i in range(N-1):
 a0=1+i*S;a1=1+(i+1)*S
 for k in range(S):fs.append((a0+k,a1+k,a1+(k+1)%S,a0+(k+1)%S))
m=bpy.data.meshes.new('hill');m.from_pydata(vs,[],fs);m.update()
for p in m.polygons:p.use_smooth=True
uv=m.uv_layers.new(name='UVMap')
for l in m.loops:
 x,y,z=m.vertices[l.vertex_index].co;uv.data[l.index].uv=(x/8,y/8)
o=bpy.data.objects.new('hill',m);bpy.context.scene.collection.objects.link(o)
mat=bpy.data.materials.new('hill_grass');m.materials.append(mat)
bpy.ops.export_scene.gltf(filepath=str(D/'hill.glb'),export_format='GLB',use_selection=False,export_apply=True)
print('HILL',len(vs),len(fs),flush=True)
]====]
local path = out .. '/hill-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code, radius = 36, height = 6, top = 6, rings = 24, spokes = 64 })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/hill-build.log" 2>&1"'))
print('wrote', out .. '/hill.glb')
