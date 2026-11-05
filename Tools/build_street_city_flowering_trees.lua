-- Reuse branch authoring, replacing opaque flower balls with leaves and petals.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local source=read('Tools/build_street_city_tree_upgrade.lua')
local code=assert(source:match('local build=%[====%[(.-)%]====%]'))
code=code:gsub('if not flower and not done:', 'if not done:')
local first=assert(code:find('  elif not done:',1,true))
local last=assert(code:find('  fx=width',first,true))
local petals=[====[
  if flower and not done:
   # Discrete five-petal blossoms among open leaf sprays. No solid canopy balls.
   for j,centre in enumerate(anchors):
    for k in range([7,4,2][lod]):
     p=centre+Vector((rng.uniform(-.72,.72),rng.uniform(-.72,.72),rng.uniform(-.35,.60)))
     n=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(.25,1))).normalized()
     axis=n.cross(Vector((0,1,0))).normalized();other=n.cross(axis).normalized()
     radius=rng.uniform(*({'golden-flower':(.018,.028),'white-flower':(.025,.036)}.get(aid,(.015,.022))))*[1,1.15,1.3][lod]
     for petal in range(5):
      angle=petal*math.tau/5+rng.uniform(-.1,.1);d=axis*math.cos(angle)+other*math.sin(angle);w=n.cross(d);centre=p+d*radius*.6+n*radius*.05;middle=vertex(centre);ring=[]
      for segment in range(6):
       theta=segment*math.tau/6;u=(.60+.66*math.cos(theta))*radius;v=math.sin(theta)*radius*.39;ring.append(vertex(p+d*u+w*v+n*(u*u/max(radius,1e-5)*.20)))
      for segment in range(6):face([middle,ring[segment],ring[(segment+1)%6]],[(.5,.5),(0,0),(1,1)],2)
]====]
code=code:sub(1,first-1)..petals..code:sub(last)
code=code:gsub("'TreeFlowers' if flower else 'TreeLeaves'", "'TreeLeaves'")
code=code:gsub('  if flower:\n', '  if False:\n')
code=code:gsub('  mesh.materials.append%(bark%);mesh.materials.append%(leaves%)', [[  mesh.materials.append(bark);mesh.materials.append(leaves)
  blossom=bpy.data.materials.new('TreeBlossoms');blossom.use_nodes=True;blossom.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(*canopy_color,1);blossom.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.78;blossom.use_backface_culling=False;mesh.materials.append(blossom)]])
local root='C:/portable/OpenKoikatsu'
local out=root..'/output/street-social-city-production/day-night-v1/flowering-trees-v5'
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'))
local task={root=root,out=out,first=1,last=3,specs={{'flower-a',937,5.5,5,6,true},{'golden-flower',1951,5.5,5,6,true,'golden'},{'white-flower',1973,5.2,4.8,6,true,'white'}},code=code}
local path=out..'/build-payload.json';local f=assert(io.open(path,'wb'));f:write(json.encode(task));f:close()
local expression="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'))
print('Flowering trees authored; native import and visual verification remain required.')
