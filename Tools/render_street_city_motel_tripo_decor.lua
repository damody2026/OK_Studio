local o='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-decor-tripo-v1'
local code=[====[
import bpy,json,math
from pathlib import Path
from mathutils import Vector
import os
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-decor-tripo-v1');STAGE=os.environ.get('OK_DECOR_PREVIEW','prepared');ONLY=os.environ.get('OK_DECOR_PREVIEW_ONLY','')
prepared=json.loads((O/(STAGE+'.json')).read_text('utf8'));dest=O/('previews' if STAGE=='prepared' else 'previews-'+STAGE);dest.mkdir(exist_ok=True);rows=[]
for r in prepared['assets']:
 if r.get('status','passed')!='passed' and STAGE!='prepared':continue
 if ONLY and r['id'] not in ONLY.split(','):continue
 path=dest/(r['id']+'.png');bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=r['path']);meshes=[a for a in bpy.context.scene.objects if a.type=='MESH'];assert meshes
 points=[a.matrix_world@Vector(v) for a in meshes for v in a.bound_box];lo=Vector([min(v[k] for v in points) for k in range(3)]);hi=Vector([max(v[k] for v in points) for k in range(3)]);target=(lo+hi)/2;size=max(hi-lo);scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=24;scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100;scene.world=bpy.data.worlds.new('Neutral preview environment');scene.world.use_nodes=True;scene.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.17,.20,.25,1);scene.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.4
 for name,pos,power,area in [('Key',(-1,-1.5,2),180,2),('Fill',(1,-.5,1),100,1.5),('Rim',(0,1.5,1.7),200,1.2)]:
  light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=area;obj=bpy.data.objects.new(name,light);scene.collection.objects.link(obj);obj.location=pos;obj.rotation_euler=(target-obj.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,lo.z-.001));floor=bpy.context.object;mat=bpy.data.materials.new('Preview floor');mat.diffuse_color=(.045,.055,.07,1);floor.data.materials.append(mat)
 camera=bpy.data.cameras.new('AssetPreviewCamera');obj=bpy.data.objects.new('AssetPreviewCamera',camera);scene.collection.objects.link(obj);obj.location=target+Vector((size*.15,-size*2.6,size*.8));obj.rotation_euler=(target-obj.location).to_track_quat('-Z','Y').to_euler();camera.type='ORTHO';camera.ortho_scale=size*1.4;scene.camera=obj;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(path);bpy.ops.render.render(write_still=True);rows.append(dict(id=r['id'],path=str(path),tripo_model_id=r['tripo_model_id'],scope='Studio preview of the actual '+STAGE+' downloaded mesh; not an Unreal runtime screenshot.'));(dest/'preview-manifest.json').write_text(json.dumps(dict(status='rendered_requires_visual_review',images=rows),ensure_ascii=False,indent=2),'utf8')
]====]
-- Usage: lua render_street_city_motel_tripo_decor.lua [prepared|remeshed] [id,id,...]
local stage=arg[1] or 'prepared';assert(stage:match('^[a-z]+$'));local only=arg[2] or '';assert(only:match('^[%w,%-]*$'))
local f=assert(io.open(o..'/render-code.txt','wb'));f:write(code);f:close();local expr="exec(compile(open(r'"..o.."/render-code.txt',encoding='utf-8').read(),'<tripo-decor-preview>','exec'))"
assert(os.execute('"set "OK_DECOR_PREVIEW='..stage..'" && set "OK_DECOR_PREVIEW_ONLY='..only..'" && "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..o..'/render-'..stage..'.log" 2>&1"'))
