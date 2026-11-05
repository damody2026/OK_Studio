-- Open branches, individual notched five-petal blossoms and small leaves.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1/cherries'
local dense=arg[1]=='v2';if dense then out=out..'-v2' end
local f=assert(io.open('Tools/build_street_city_tree_upgrade.lua','rb'));local s=f:read('*a');f:close();local code=assert(s:match('local build=%[====%[(.-)%]====%]'))
local start=assert(code:find("(OUT/'textures').mkdir",1,true));local stop=assert(code:find('for idx,spec in enumerate(specs,1):',start,true));code=code:sub(1,start-1)..[[import shutil
(OUT/'textures').mkdir(exist_ok=True)
for filename in ['bark-color.png','bark-normal.png','bark-roughness.png']:shutil.copy2(ROOT/'output/street-social-city-production/tree-upgrade-v2/textures'/filename,OUT/'textures'/filename)
]]..code:sub(stop)
start=assert(code:find('  elif not done:',1,true));stop=assert(code:find('  fx=width',start,true))
local flowers=[=[  elif not done:
   for centre in anchors:
    for k in range([90,32,9][lod]):
     p=centre+Vector((rng.uniform(-.76,.76),rng.uniform(-.76,.76),rng.uniform(-.55,.55)));normal=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-.45,1))).normalized();rot=normal.to_track_quat('Z','Y').to_matrix();radius=rng.uniform(.033,.047)*[1,1.18,1.5][lod];shade=rng.uniform(.84,1.06);color=(shade,shade,shade,1);phase=rng.random()*math.pi*2
     for petal in range(5):
      angle=phase+petal*math.pi*2/5;co,si=math.cos(angle),math.sin(angle);shape=[(0,0),(-.43,.48),(-.27,1),(0,.83),(.27,1),(.43,.48)] if lod==0 else [(0,0),(-.38,.56),(0,1),(.38,.56)] if lod==1 else [(0,0),(-.42,.72),(.42,.72)];ids=[];uv=[]
      for x,y in shape:
       q=Vector(((x*co-y*si)*radius,(x*si+y*co)*radius,(y*.14-y*y*.09)*radius));ids.append(vertex(p+rot@q,color));uv.append((x+.5,y))
      face(ids,uv,1)
    for k in range([20,9,3][lod]):
     p=centre+Vector((rng.uniform(-.65,.65),rng.uniform(-.65,.65),rng.uniform(-.5,.35)));normal=Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(.1,1))).normalized();rot=normal.to_track_quat('Z','Y').to_matrix();length=rng.uniform(.10,.17);shape=[(0,0),(-.32,.4),(-.25,.72),(0,1),(.25,.72),(.32,.4)];ids=[vertex(p+rot@Vector((x*length,y*length,.015*math.sin(y*math.pi)))) for x,y in shape];face(ids,[(x+.5,y) for x,y in shape],2)
]=]
code=code:sub(1,start-1)..flowers..code:sub(stop)
code=code:gsub("mesh.materials.append%(bark%);mesh.materials.append%(leaves%)", "mesh.materials.append(bark);mesh.materials.append(leaves);green=bpy.data.materials.new('TreeGreen');green.diffuse_color=(.05,.22,.03,1);mesh.materials.append(green)")
code=code:gsub("bs.inputs%['Base Color'%]%.default_value=%(%*canopy_color,1%);leaves.use_backface_culling=False", "bs.inputs['Base Color'].default_value=(*canopy_color,1);leaves.node_tree.links.new(vcnode.outputs['Color'],bs.inputs['Base Color']);leaves.use_backface_culling=False")
code=code:gsub('cap=%[10000,6000,2500%]','cap=[48000,18000,5000]')
if dense then
 code=code:gsub('%[90,32,9%]','[180,90,30]'):gsub('rng.uniform%(%s*%.033,%.047%)%*%[1,1%.18,1%.5%]','rng.uniform(.047,.063)*[1,1.4,2.35]')
 code=code:gsub('cap=%[48000,18000,5000%]','cap=[110000,60000,20000]')
 assert(code:find('range([180,90,30][lod])',1,true) and code:find('rng.uniform(.047,.063)*[1,1.4,2.35]',1,true),'Dense LOD adapter failed')
end
local specs={{'cherry-a',8107,3.2,4.6,6.8,true,'broad'},{'cherry-b',8147,3.3,4.5,6.7,true,'broad'},{'cherry-c',8191,3.1,4.7,6.9,true,'broad'}}
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'));local payload=out..'/build-payload.json';f=assert(io.open(payload,'wb'));f:write(j.encode({root=root,out=out,first=1,last=3,specs=specs,code=code}));f:close();local expression="import json;TASK=json.load(open('"..payload.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'));print('Three geometric blossom-tree variants built; no opaque canopy balls; native import and Game review required.')
