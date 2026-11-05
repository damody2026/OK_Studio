package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1';local f=assert(io.open('Tools/build_street_city_motel_suites.lua','rb'));local source=f:read('*a');f:close();local helper=assert(source:match('local code=%[====%[(.-)%]====%]')):match('^(.-)\nfor index,q in enumerate')
local code=helper..[====[
font=bpy.data.fonts.load('C:/Windows/Fonts/msjhbd.ttc')
def lettering(body,p,width,height,mat,yaw=0):
 cu=bpy.data.curves.new('Raised illuminated lettering','FONT');cu.body=body;cu.font=font;cu.align_x='CENTER';cu.align_y='CENTER';cu.size=1;cu.extrude=.018;cu.bevel_depth=.003;cu.bevel_resolution=2;ob=bpy.data.objects.new(body,cu);bpy.context.collection.objects.link(ob);cu.materials.append(mat);ob.rotation_euler=(math.pi/2,0,yaw);ob.location=p;bpy.context.view_layer.update();scale=min(width/max(ob.dimensions.x,.01),height/max(ob.dimensions.z,.01));ob.scale=(scale,scale,scale);bpy.context.view_layer.objects.active=ob;ob.select_set(True);bpy.ops.object.convert(target='MESH');ob.select_set(False)
results=[]
for bid in ['H1','S18']:
 bpy.ops.wm.read_factory_settings(use_empty=True);font=bpy.data.fonts.load('C:/Windows/Fonts/msjhbd.ttc');dark=material('Motel_Dark',(.014,.018,.023),.4);gold=material('Motel_Gold',(.42,.28,.10),.25,.85);white=material('Motel_Light',(1,.82,.55),.35,emit=2)
 brand='影輝之夜 情趣汽車旅館' if bid=='H1' else '花境 情趣汽車旅館';x,y,z=(-27,-27.10,3.60) if bid=='H1' else (0,-18.18,3.95);bw=19 if bid=='H1' else 20
 box('Dark ground-entry brand fascia',(x,y,z),(bw,.18,1.25),dark,.04);lettering(brand,(x,y-.105,z),bw-1,1.0,white)
 if bid=='H1':
  for xx in [-bw/2,bw/2]:box('Brand sign support',(x+xx,y+.15,z/2),(.12,.18,z),gold)
 else:
  for xx in [-9,9]:box('Roof mounted plaque pedestal',(xx,-17.9,3.625),(.15,.25,.85),gold);box('Plaque mounting bracket',(xx,-18.04,3.55),(.18,.60,.12),gold)
 for q in [r for r in plan['rooms'] if r['building']==bid]:
  cx,cy,cz=q['local_center_m'];a=math.radians(q['yaw']);w=q['size_m'][0]
  def pos(x,y,z):return (cx+x*math.cos(a)-y*math.sin(a),cy+x*math.sin(a)+y*math.cos(a),cz+z)
  p=pos(w*.29,-10.49,2.94);ob=box('Individual dark room plaque',p,(2.65,.14,.72),dark,.025);ob.rotation_euler.z=a
  lettering(q['room_number'],pos(w*.29,-10.57,3.09),1.1,.27,white,a);lettering(q['source_name'],pos(w*.29,-10.57,2.77),2.35,.21,white,a)
 for o in list(bpy.context.scene.objects):o.select_set(True)
 bpy.context.view_layer.objects.active=next(iter(bpy.context.scene.objects));bpy.ops.object.join();ob=bpy.context.object;bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);ob.data.calc_loop_triangles();path=O/'models'/(bid+'-signs.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_apply=True,export_yup=True);results.append(dict(id=bid+'-signs',building=bid,path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),triangles=len(ob.data.loop_triangles),brand=brand))
bpy.ops.wm.read_factory_settings(use_empty=True);font=bpy.data.fonts.load('C:/Windows/Fonts/msjhbd.ttc');dark=material('Motel_Dark',(.014,.018,.023),.4);gold=material('Motel_Gold',(.42,.28,.10),.25,.85);white=material('Motel_Light',(1,.82,.55),.35,emit=2)
box('Roadside entrance pylon',(0,0,2.25),(2.4,.20,3.2),dark,.04);box('Pylon supported foot',(0,0,.20),(2.5,.90,.40),gold,.03);box('Pylon structural pedestal',(0,0,.65),(.25,.25,1.3),gold,.02)
for body,z,width,height in [('影輝之夜',3.15,2.12,.48),('汽車入口',2.25,2.12,.48),('→',1.35,1.4,.6)]:lettering(body,(0,-.125,z),width,height,white)
frame('Pylon framed border',(0,-.105,2.25),2.4,3.2,gold)
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=next(iter(bpy.context.scene.objects));bpy.ops.object.join();ob=bpy.context.object;bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);ob.data.calc_loop_triangles();path=O/'models'/'H1-road-sign.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_apply=True,export_yup=True);results.append(dict(id='H1-road-sign',building='H1',path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),triangles=len(ob.data.loop_triangles),brand='影輝之夜 汽車入口 →'))
(O/'sign-build.json').write_text(json.dumps(dict(status='authored_actual_raised_text_requires_native_review',assets=results),ensure_ascii=False,indent=2),'utf8')
]====]
local path=out..'/sign-build-payload.json';f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code}));f:close();local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])";assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..out..'/sign-build.log" 2>&1"'))
