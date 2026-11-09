-- One batting lane, 20 x 4.5 x 3.6 m, origin at the bottom centre, batter's end on +X and open: posts, net, turf strip,
-- home plate and a pitching machine at the far end, about 4000 triangles. No collision; the park's walkers stay as they are.
-- Writes output/street-social-city-production/hill-v1/batting_cage.glb; Tools/street_city_lover_spots_payload.lua places it.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_batting_cage.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local out = 'C:/portable/OpenKoikatsu/output/street-social-city-production/hill-v1'
local code = [====[
import bpy,math,pathlib
D=pathlib.Path(TASK['out'])
bpy.ops.wm.read_factory_settings(use_empty=True)
COL=dict(net=(.1,.13,.12,.35),post=(.45,.47,.5,.5),turf=(.1,.3,.14,.95),white=(.92,.92,.88,.7),dirt=(.42,.3,.2,.95),body=(.1,.25,.6,.5),dark=(.04,.04,.05,.6))
names=list(COL);V=[];Fc=[];FM=[]
def box(a,b,c,d,e,f,m):
 i=len(V);V.extend([(a,c,e),(b,c,e),(b,d,e),(a,d,e),(a,c,f),(b,c,f),(b,d,f),(a,d,f)])
 for q in ((0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)):Fc.append(tuple(i+k for k in q));FM.append(names.index(m))
L,W,H=10.,2.25,3.6;t=.012
box(-L,L,-W,W,0,.02,'turf');box(5.6,8.4,-1.2,1.2,.02,.03,'dirt')
i=len(V);V.extend([(7.1,-.22,.035),(7.1,.22,.035),(6.88,.22,.035),(6.66,0,.035),(6.88,-.22,.035)]);Fc.append((i,i+1,i+2,i+3,i+4));FM.append(names.index('white'))
for y in (-1.,.55):
 box(6.3,7.5,y,y+.04,.03,.04,'white');box(6.3,7.5,y+.45,y+.49,.03,.04,'white');box(6.3,6.34,y,y+.49,.03,.04,'white');box(7.46,7.5,y,y+.49,.03,.04,'white')
x=-L
while x<=L+.01:
 for s in (-W,W):box(x-.05,x+.05,s-.05,s+.05,0,H+.05,'post')
 box(x-.04,x+.04,-W,W,H,H+.08,'post');x+=4.
for s in (-W,W):box(-L,L,s-.04,s+.04,H,H+.08,'post')
z=.3
while z<H:
 for s in (-W,W):box(-L,L,s-t,s+t,z-t,z+t,'net')
 box(-L-t,-L+t,-W,W,z-t,z+t,'net');z+=.3
x=-L
while x<L:
 for s in (-W,W):box(x-t,x+t,s-t,s+t,0,H,'net')
 box(x-t,x+t,-W,W,H-t,H+t,'net');x+=.3
y=-W
while y<=W:
 box(-L-t,-L+t,y-t,y+t,0,H,'net');box(-L,L,y-t,y+t,H-t,H+t,'net');y+=.3
# the machine: body on three legs, two wheels, a feed chute, a padded screen in front of it
for a,b in ((-.3,-.3),(-.3,.3),(.3,0)):box(-8.+a-.03,-8.+a+.03,b-.03,b+.03,0,.9,'dark')
box(-8.45,-7.55,-.3,.3,.9,1.3,'body');box(-8.35,-7.65,-.05,.05,1.3,1.75,'dark')
for k in range(12):
 a=k*math.tau/12;b=(k+1)*math.tau/12
 for s in (-.2,.16):box(-7.5+math.cos(a)*.22-.03,-7.5+math.cos(a)*.22+.03,s,s+.04,1.15+math.sin(a)*.22-.03,1.15+math.sin(a)*.22+.03,'dark')
box(-7.1,-7.,-1.2,1.2,0,1.5,'body');box(-7.1,-7.,-.25,.25,.9,1.4,'dark')
me=bpy.data.meshes.new('batting_cage');me.from_pydata(V,[],Fc);me.update()
for n in names:
 m=bpy.data.materials.new('cage_'+n);m.use_nodes=True;q=m.node_tree.nodes['Principled BSDF'];c=COL[n];q.inputs['Base Color'].default_value=(c[0],c[1],c[2],1);q.inputs['Roughness'].default_value=c[3];me.materials.append(m)
for p,k in zip(me.polygons,FM):p.material_index=k
me.uv_layers.new(name='UVMap')
o=bpy.data.objects.new('batting_cage',me);bpy.context.scene.collection.objects.link(o)
bpy.ops.export_scene.gltf(filepath=str(D/'batting_cage.glb'),export_format='GLB',use_selection=False,export_apply=True)
print('CAGE',sum(len(p.vertices)-2 for p in me.polygons),flush=True)
]====]
local path = out .. '/batting-cage-payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ out = out, code = code })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/batting-cage-blender.log" 2>&1"'))
print('wrote', out .. '/batting_cage.glb')
