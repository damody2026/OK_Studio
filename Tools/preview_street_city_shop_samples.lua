-- Blender EEVEE preview of the shop samples: source F01-F03 floors with the planned cut boxes removed plus the refit GLB.
-- Iteration aid only; the acceptance pictures are the UE captures. Writes shop-samples-v1/previews/<id>-sheet.jpg.
-- Usage: lua Tools/preview_street_city_shop_samples.lua [S01 ...]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/shop-samples-v1'
-- '--refits' previews the mass-production refits (shop-refits-v1) instead of the samples
local first=1;if arg[1]=='--refits' then out='C:/portable/OpenKoikatsu/output/street-social-city-production/shop-refits-v1';first=2 end
local ids={};for i=first,#arg do ids[#ids+1]=arg[i]end;if #ids==0 then ids={'S01','S26','S09','S17'}end
local code=[====[
import bpy,json,math
from mathutils import Vector
from pathlib import Path
O=Path(TASK['out']);SRC=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');(O/'previews').mkdir(exist_ok=True)
def bounds(o):
 v=[o.matrix_world@Vector(c) for c in o.bound_box];return [min(p[i] for p in v) for i in range(3)],[max(p[i] for p in v) for i in range(3)]
for sid in TASK['ids']:
 b=json.loads((O/sid/'build.json').read_text('utf8'));bpy.ops.wm.read_factory_settings(use_empty=True);sc=bpy.context.scene
 for fl in ('F01','F02','F03'):
  before=set(sc.objects);bpy.ops.import_scene.gltf(filepath=str(SRC/(sid+'-modular-components-v1')/'assembly-building'/(sid+'-'+fl+'-complete-2k.glb')))
  if fl=='F01':
   for o in [o for o in sc.objects if o not in before and o.type=='MESH']:
    mn,mx=bounds(o)
    for c in b['cut']:
     x0,x1,y0,y1,z0,z1=c['box']
     if mn[0]>=x0 and mx[0]<=x1 and mn[1]>=y0 and mx[1]<=y1 and mn[2]>=z0 and mx[2]<=z1:bpy.data.objects.remove(o,do_unlink=True);break
 bpy.ops.import_scene.gltf(filepath=b['path'])
 g=bpy.data.meshes.new('ground');H=b['H'];g.from_pydata([(-20,-H-14,-.02),(20,-H-14,-.02),(20,H+2,-.02),(-20,H+2,-.02)],[],[(0,1,2,3)]);go=bpy.data.objects.new('ground',g);sc.collection.objects.link(go)
 gm=bpy.data.materials.new('g');gm.use_nodes=True;gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.55,.55,.53,1);g.materials.append(gm)
 sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=960;sc.render.resolution_y=540
 for hour,(sky,sun) in {'day':(1.0,3.0),'night':(.03,0.)}.items():
  w=bpy.data.worlds.new('w');w.use_nodes=True;w.node_tree.nodes['Background'].inputs['Strength'].default_value=sky;w.node_tree.nodes['Background'].inputs['Color'].default_value=(.6,.7,.9,1) if hour=='day' else (.05,.07,.15,1);sc.world=w
  for o in [o for o in sc.objects if o.type=='LIGHT']:bpy.data.objects.remove(o,do_unlink=True)
  if sun:d=bpy.data.lights.new('sun','SUN');d.energy=sun;o=bpy.data.objects.new('sun',d);sc.collection.objects.link(o);o.rotation_euler=(math.radians(50),0,math.radians(20))
  for i,l in enumerate(b['lights']):d=bpy.data.lights.new('L%d'%i,'POINT');d.energy=l['lumens']*.1;d.color=l['color'];o=bpy.data.objects.new('L%d'%i,d);sc.collection.objects.link(o);o.location=l['local']
  try:sc.view_settings.view_transform='AgX'
  except Exception:pass
  dx=b['door_x'];views=[('front',(dx+1.5,-H-10,1.8),(dx+1.5,-H,3.0),70),('front-wide',(6,-H-16,4.5),(0,-H,4.5),60)]
  if hour=='night':views+=[('inside',(dx,-H+.8,1.6),(dx*.2,-H+8,1.0),88),('inside-back',(1.5,b['core_y']-1.0,1.7),(-1,-H+1.5,.9),88)]
  for vid,eye,tgt,fov in views:
   cam=bpy.data.cameras.new(vid);cam.angle=math.radians(fov);cam.clip_start=.05;o=bpy.data.objects.new(vid,cam);sc.collection.objects.link(o);o.location=eye
   o.rotation_euler=(Vector(tgt)-Vector(eye)).to_track_quat('-Z','Y').to_euler();sc.camera=o;sc.render.filepath=str(O/'previews'/f'{sid}-{vid}-{hour}.png');bpy.ops.render.render(write_still=True)
]====]
for _,sid in ipairs(ids)do
 local path=out..'/preview-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,ids={sid}}));f:close()
 local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
 assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/preview.log" 2>&1"'))
 local py=assert(io.popen('python -I -','w'))
 py:write("from PIL import Image,ImageDraw\nimport glob,os\nO='"..out.."/previews';sid='"..sid.."'\nfs=[O+'/'+sid+'-'+n+'.png' for n in ['front-day','front-night','front-wide-day','front-wide-night','inside-night','inside-back-night']]\nfs=[p for p in fs if os.path.exists(p)]\nsh=Image.new('RGB',(1440,270*((len(fs)+2)//3)),(16,16,20));d=ImageDraw.Draw(sh)\nfor i,p in enumerate(fs):\n sh.paste(Image.open(p).convert('RGB').resize((480,270)),((i%3)*480,(i//3)*270));d.text(((i%3)*480+6,(i//3)*270+4),os.path.basename(p)[:-4],fill=(255,220,120))\nsh.save(O+'/'+sid+'-sheet.jpg',quality=85)\n")
 assert(py:close());print('preview',sid)
end
