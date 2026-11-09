-- Quick Blender EEVEE preview of each sample room's official-photo views (iteration aid; not a game capture).
-- Usage: lua preview_street_city_motel_sample_rooms.lua <room-id> [room-id ...]  (also tiles <id>-v2sheet.jpg per room)
assert(arg[1]);local S='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1/sample-rooms'
local code=[====[
import bpy,json,math
from mathutils import Vector
import os
S=TASK['S'];rid=TASK['rid'];MD=S+('/models-v2/' if os.path.exists(S+'/models-v2/'+rid) else '/models/')+rid;b=json.load(open(MD+'/build.json',encoding='utf8'))
bpy.ops.wm.open_mainfile(filepath=MD+'/suite.blend');sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE';sc.render.resolution_x=960;sc.render.resolution_y=540
w=bpy.data.worlds.new('w');w.use_nodes=True;w.node_tree.nodes['Background'].inputs['Strength'].default_value=.3;sc.world=w
try:sc.view_settings.view_transform='AgX'
except Exception:pass
for i,l in enumerate(b['lights']):
 d=bpy.data.lights.new('L%d'%i,'POINT');d.energy=l['lumens']*.12;d.color=l['color'];d.shadow_soft_size=.15;o=bpy.data.objects.new('L%d'%i,d);sc.collection.objects.link(o);o.location=l['local']
for v in b['views']:
 cam=bpy.data.cameras.new(v['id']);cam.angle=math.radians(v['fov']);cam.clip_start=.05;o=bpy.data.objects.new(v['id'],cam);sc.collection.objects.link(o);o.location=v['eye']
 o.rotation_euler=(Vector(v['target'])-Vector(v['eye'])).to_track_quat('-Z','Y').to_euler();sc.camera=o
 sc.render.filepath=S+'/previews/'+rid+'-'+v['id']+'.png';bpy.ops.render.render(write_still=True)
]====]
package.path='Tools/lua/?.lua;'..package.path;local j=require('ok.json')
for _,rid in ipairs(arg) do
 local p=S..'/preview-payload.json';local f=assert(io.open(p,'wb'));f:write(j.encode({S=S,rid=rid,code=code}));f:close()
 local expr="import json;TASK=json.load(open('"..p.."',encoding='utf8'));exec(TASK['code'])"
 assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python-expr "'..expr..'" > "'..S..'/preview.log" 2>&1"'))
 local py=assert(io.popen('python -I -','w'))
 py:write("from PIL import Image,ImageDraw\nimport glob,os\nS='"..S.."';rid='"..rid.."'\nfs=sorted(glob.glob(S+'/previews/'+rid+'-v-*.png'))\nsh=Image.new('RGB',(1440,270*((len(fs)+2)//3)),(16,16,20));d=ImageDraw.Draw(sh)\nfor i,p in enumerate(fs):\n im=Image.open(p).convert('RGB').resize((480,270));sh.paste(im,((i%3)*480,(i//3)*270));d.text(((i%3)*480+6,(i//3)*270+4),os.path.basename(p)[len(rid)+1:-4],fill=(255,220,120))\nsh.save(S+'/previews/'+rid+'-v2sheet.jpg',quality=85)\n")
 assert(py:close());print('preview',rid)
end