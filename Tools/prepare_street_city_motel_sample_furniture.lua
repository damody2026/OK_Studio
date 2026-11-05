-- Sample-room Tripo furniture: collect Downloads/sample-furniture-<key>.glb, scale to real size (bottom-centre origin,
-- front facing -Y), then the mandatory instant-meshes-rs pass (same graft ladder as the motel ornaments).
-- Usage: lua prepare_street_city_motel_sample_furniture.lua [key]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1/sample-rooms'
local blender='C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return j.decode(s)end
local function write(p,v)local f=assert(io.open(p,'wb'));f:write(j.encode(v));f:close()end
local spec=read(o..'/tripo-furniture.json');local only=arg[1]
os.execute('if not exist "'..(o..'/furniture'):gsub('/','\\')..'" mkdir "'..(o..'/furniture'):gsub('/','\\')..'"')
local norm=[====[
import bpy,bmesh,json,sys
from mathutils import Vector
a=json.loads(sys.argv[sys.argv.index('--')+1])
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=a['src'])
objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
for o in list(bpy.context.scene.objects):
 if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in objs:o.select_set(True)
bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();ob=bpy.context.object;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
vs=[ob.matrix_world@v.co for v in ob.data.vertices];lo=Vector([min(v[k] for v in vs) for k in range(3)]);hi=Vector([max(v[k] for v in vs) for k in range(3)]);dim=hi-lo
t=a['size'];s=min(t[0]/dim.x,t[1]/dim.y,t[2]/dim.z);c=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
for v in ob.data.vertices:v.co=(ob.matrix_world@v.co-c)*s
ob.matrix_world.identity();n=sum(len(p.vertices)-2 for p in ob.data.polygons)
if n>60000:
 m=ob.modifiers.new('budget','DECIMATE');m.ratio=50000/n;bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=m.name)
for m in ob.data.materials:
 if m and m.use_nodes:
  for nd in m.node_tree.nodes:
   if nd.type=='TEX_IMAGE' and nd.image and max(nd.image.size)>2048:f=2048/max(nd.image.size);nd.image.scale(int(nd.image.size[0]*f),int(nd.image.size[1]*f))
   if nd.type=='TEX_IMAGE' and nd.image and a.get('hue') and nd.image.colorspace_settings.name=='sRGB' and any(l.to_socket.name=='Base Color' for l in nd.outputs['Color'].links):
    # optional hue rotation of the base colour (e.g. Tripo returned blue velvet for a purple sofa)
    import numpy as np,colorsys;im=nd.image;px=np.array(im.pixels[:]).reshape(-1,4);rgb=px[:,:3];mx=rgb.max(1);mn=rgb.min(1);sat=(mx-mn)>.08
    hsv=np.array([colorsys.rgb_to_hsv(*c) for c in rgb[sat]]);hsv[:,0]=(hsv[:,0]+a['hue'])%1;rgb[sat]=np.array([colorsys.hsv_to_rgb(*c) for c in hsv]);px[:,:3]=rgb;im.pixels[:]=px.ravel();im.pack()
bpy.ops.export_scene.gltf(filepath=a['dst'],export_format='GLB',use_selection=False,export_yup=True)
print('NORM',json.dumps(dict(size=list(ob.dimensions),tris=sum(len(p.vertices)-2 for p in ob.data.polygons))))
]====]
local np=o..'/furniture/normalize-code.py';local f=assert(io.open(np,'wb'));f:write(norm);f:close()
local rungs={'--triangle-cap 24000 --tolerance 0.006 --quad-mode --project-source --dense-pass 3 --repair-solid 0.0015 --smooth-shading --graft-thin-features',
 '--triangle-cap 30000 --tolerance 0.008 --quad-mode --project-source --dense-pass 3 --repair-solid 0.001 --smooth-shading --graft-thin-features',
 '--triangle-cap 42000 --tolerance 0.008 --quad-mode --project-source --dense-pass 3 --repair-solid 0.0015 --smooth-shading --graft-thin-features',
 '--triangle-cap 36000 --tolerance 0.004 --quad-mode --project-source --dense-pass 3 --recover-source-topology --smooth-shading',
 '--triangle-cap 60000 --tolerance 0.004 --quad-mode --project-source --dense-pass 3 --recover-source-topology --smooth-shading'}
local rows=read(o..'/furniture/receipts.json') or {};local byk={};for _,r in ipairs(rows)do byk[r.key]=r end
for _,it in ipairs(spec.items)do
 if not only or only==it.key then
  local src='C:/Users/Damody/Downloads/sample-furniture-'..it.key..'.glb';local g=io.open(src,'rb')
  if g then g:close()
   local sha=h.sha256_file(src);local done=byk[it.key]
   if not(done and done.status=='passed' and done.source_sha256==sha)then
    local dir=o..'/furniture/'..it.key;os.execute('if not exist "'..dir:gsub('/','\\')..'" mkdir "'..dir:gsub('/','\\')..'"')
    local arg=j.encode({src=src,dst=dir..'/normalized.glb',size=it.size_m,hue=it.hue}):gsub('"','\\"')
    assert(os.execute('""'..blender..'" --background --factory-startup --python "'..np..'" -- "'..arg..'" > "'..dir..'/normalize.log" 2>&1"'))
    local rec={key=it.key,status='failed',source=src,source_sha256=sha,tripo_model_id=it.tripo_model_id}
    for i,r in ipairs(rungs)do
     local out=dir..'/rung'..i
     local prev=read(out..'/remesh-report.json')
     if not(prev and prev.triangle_cap==tonumber(r:match('%-%-triangle%-cap (%d+)')) and prev.source_sha256==h.sha256_file(dir..'/normalized.glb'))then
     os.execute('""'..blender..'" --background --factory-startup --threads 4 --python Tools/run_street_city_blender_task.py -- --script Tools/remesh_street_city_asset.py --status-file "'..out..'-status.json" -- --source "'..dir..'/normalized.glb" --output "'..out..'" --threads 4 '..r..' > "'..out..'.log" 2>&1"')
     end
     local rep=read(out..'/remesh-report.json')
     if rep and rep.status=='passed' then rec.status='passed';rec.rung=i;rec.path=out..'/remeshed-candidate.glb';rec.sha256=h.sha256_file(rec.path);rec.triangles=rep.triangles;rec.tool=rep.tool;break end
    end
    write(dir..'/receipt.json',rec);byk[it.key]=rec;print(it.key..' '..rec.status..' '..(rec.rung or '')..' '..(rec.triangles or ''))
   end
  else print(it.key..' not downloaded') end
 end
end
-- merge every per-item receipt (parallel runs each write their own)
rows={};for _,it in ipairs(spec.items)do local r=read(o..'/furniture/'..it.key..'/receipt.json') or byk[it.key];if r then rows[#rows+1]=r end end;write(o..'/furniture/receipts.json',rows)
