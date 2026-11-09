-- Geometric pinnate fronds; no leaf-cluster bitmap is stretched across the blades.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1/palms'
local f=assert(io.open('Tools/build_street_city_tree_upgrade.lua','rb'));local s=f:read('*a');f:close();local code=assert(s:match('local build=%[====%[(.-)%]====%]'))
local start=assert(code:find("(OUT/'textures').mkdir",1,true));local stop=assert(code:find('for idx,spec in enumerate(specs,1):',start,true));code=code:sub(1,start-1)..[[import shutil
(OUT/'textures').mkdir(exist_ok=True)
for filename in ['bark-color.png','bark-normal.png','bark-roughness.png']:shutil.copy2(ROOT/'output/street-social-city-production/tree-upgrade-v2/textures'/filename,OUT/'textures'/filename)
]]..code:sub(stop)
start=assert(code:find("  elif profile=='palm':",1,true));stop=assert(code:find("  elif profile=='weeping':",start,true))
local palm=[=[  elif profile=='palm':
   branch([(0,0,0),(.06,.02,1.7),(.17,.04,3.5),(.26,.09,5.5),(.24,.1,6.8)],[.21,.20,.17,.14,.11])
   fronds=[18,12,8][lod];leaves=[24,16,12][lod];segments=[8,6,5][lod]
   for j in range(fronds):
    angle=j*2*math.pi/fronds+rng.uniform(-.09,.09);rad=Vector((math.cos(angle),math.sin(angle),0));lat=Vector((-math.sin(angle),math.cos(angle),0));origin=Vector((.24,.1,6.75+rng.uniform(-.18,.22)));length=rng.uniform(2.65,3.2);drop=1.1+(j%3)*.42
    def rachis(u):return origin+rad*(u*length)+Vector((0,0,.8*math.sin(u*math.pi*.9)-drop*u*u))
    points=[rachis(k/segments) for k in range(segments+1)];branch(points,[.032*(1-k/segments)+.005 for k in range(segments+1)])
    for k in range(leaves):
     u=.10+.86*(k+.5)/leaves;p=rachis(u);leaflength=(.20+.82*math.sin(u*math.pi)**.72)*rng.uniform(.91,1.07);halfwidth=(.027+.021*math.sin(u*math.pi))*[1,1.2,1.5][lod]
     for side in [-1,1]:
      shade=rng.uniform(.73,1.07);color=(shade,shade*rng.uniform(.93,1.04),shade*.90,1);tip=p+lat*(side*leaflength)+rad*(.20+.22*u)+Vector((0,0,-.16-.30*u));mid=p.lerp(tip,.55)+Vector((0,0,.035));across=rad*halfwidth
      if lod<2:
       ids=[vertex(p-across*.45,color),vertex(p+across*.45,color),vertex(mid+across,color),vertex(tip,color),vertex(mid-across,color)];face(ids,[(0,0),(1,0),(1,.55),(.5,1),(0,.55)],1)
      else:
       ids=[vertex(p-across,color),vertex(p+across,color),vertex(tip,color)];face(ids,[(0,0),(1,0),(.5,1)],1)
   # Short upright spears prevent an empty crown centre.
   for j in range(3 if lod<2 else 1):
    a=j*2.1;direction=Vector((math.cos(a)*.38,math.sin(a)*.38,1.1));p=Vector((.24,.1,6.75));lat=Vector((-math.sin(a),math.cos(a),0))*.09;ids=[vertex(p-lat),vertex(p+lat),vertex(p+direction)];face(ids,[(0,0),(1,0),(.5,1)],1)
   done=True
]=]
code=code:sub(1,start-1)..palm..code:sub(stop)
code=code:gsub("bs.inputs%['Base Color'%]%.default_value=%(%*canopy_color,1%);leaves.use_backface_culling=False", "bs.inputs['Base Color'].default_value=(*canopy_color,1);leaves.node_tree.links.new(vcnode.outputs['Color'],bs.inputs['Base Color']);leaves.use_backface_culling=False")
local specs={{'palm-a',7193,6.6,6.2,8,true,'palm'},{'palm-b',7219,6.3,6.6,8,true,'palm'},{'palm-c',7253,6.5,6.4,8,true,'palm'}}
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'));local payload=out..'/build-payload.json';f=assert(io.open(payload,'wb'));f:write(j.encode({root=root,out=out,first=1,last=3,specs=specs,code=code}));f:close()
local expression="import json;TASK=json.load(open('"..payload.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'));print('Three three-LOD pinnate palm variants built; native import and Game review required.')
