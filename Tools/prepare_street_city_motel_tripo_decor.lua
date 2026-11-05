-- Prepares only files actually downloaded from Tripo's visible Export UI.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local o='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-decor-tripo-v1'
local code=[====[
import bpy,bmesh,json,math,hashlib,time,os
from pathlib import Path
from mathutils import Vector
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-decor-tripo-v1');manifest=json.loads((O/'submissions.json').read_text('utf8'));dest=O/'prepared';dest.mkdir(exist_ok=True)
# OK_DECOR_SHARD=k/n: process index%n==k into its own receipt; without it, merge every shard receipt into prepared.json.
shard=os.environ.get('OK_DECOR_SHARD');sk,sn=(int(v) for v in shard.split('/')) if shard else (0,1);receipt_path=O/('prepared-shard%d.json'%sk if shard else 'prepared.json');done={}
for p in [O/'prepared.json']+sorted(O.glob('prepared-shard*.json')):
 if p.exists():done.update({r['id']:r for r in json.loads(p.read_text('utf8'))['assets']})
for index,r in enumerate(manifest['assets'],1):
 src=O/'downloads'/('motel-decor-'+str(index).zfill(3)+'.glb')
 if not src.exists() or index%sn!=sk:continue
 source_sha=hashlib.sha256(src.read_bytes()).hexdigest()
 if r['id'] in done:
  old=done[r['id']]
  if old['source_sha256']==source_sha and Path(old['path']).exists() and hashlib.sha256(Path(old['path']).read_bytes()).hexdigest()==old['sha256']:continue
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src));objs=[a for a in bpy.context.scene.objects if a.type=='MESH'];assert objs,(index,src)
 for a in list(bpy.context.scene.objects):
  if a.type!='MESH':bpy.data.objects.remove(a,do_unlink=True)
 bpy.ops.object.select_all(action='DESELECT')
 for a in objs:a.select_set(True)
 bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();a=bpy.context.object;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 vertices=[a.matrix_world@v.co for v in a.data.vertices];lo=Vector([min(v[k] for v in vertices) for k in range(3)]);hi=Vector([max(v[k] for v in vertices) for k in range(3)]);dims=hi-lo;assert min(dims)>1e-5,(index,list(dims));center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z));scale=min(.62/dims.z,.43/max(dims.x,dims.y)) if r['slot']=='A' else min(.50/dims.z,.40/max(dims.x,dims.y))
 for v in a.data.vertices:v.co=(a.matrix_world@v.co-center)*scale
 a.matrix_world.identity();before=sum(len(p.vertices)-2 for p in a.data.polygons)
 if before>30000:
  bm=bmesh.new();bm.from_mesh(a.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001);bm.to_mesh(a.data);bm.free();a.data.update()
  for attempt in range(3):
   count=sum(len(p.vertices)-2 for p in a.data.polygons)
   if count<=35000:break
   m=a.modifiers.new('Game decoration budget','DECIMATE');m.ratio=min(1.,26500/count);m.use_collapse_triangulate=True;bpy.context.view_layer.objects.active=a;bpy.ops.object.modifier_apply(modifier=m.name)
 after=sum(len(p.vertices)-2 for p in a.data.polygons);assert after<=35000,(index,before,after)
 for p in a.data.polygons:p.use_smooth=True
 assert a.data.materials and any(m and m.use_nodes and any(n.type=='TEX_IMAGE' and n.image for n in m.node_tree.nodes) for m in a.data.materials),(index,'Missing Tripo texture')
 for m in a.data.materials:
  if not m or not m.use_nodes:continue
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE' and n.image:
    im=n.image
    if max(im.size)>2048:
     factor=2048/max(im.size);im.scale(max(1,round(im.size[0]*factor)),max(1,round(im.size[1]*factor)))
 target=dest/(r['id']+'.glb');bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
 row=dict(id=r['id'],room_id=r['room_id'],index=index,tripo_model_id=r['tripo_model_id'],source=str(src),source_sha256=source_sha,path=str(target),sha256=hashlib.sha256(target.read_bytes()).hexdigest(),source_triangles=before,triangles=after,size_m=list(a.dimensions),slot=r['slot'],scope='Actual exported Tripo mesh, rebased to tabletop origin and scaled to a bounded ornament size; textured geometry simplified to <=35k triangles. No generated geometry substituted.');done[r['id']]=row
 receipt=dict(status='prepared_requires_native_placement' if len(done)==122 else 'partial_requires_remaining_downloads',assets=list(done.values()),required=122,completed=len(done));receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8');print('Prepared',index,r['id'],before,'to',after,flush=True)
assert done,'No actual UI-exported motel-decor-###.glb files are available in downloads; do not fabricate completion.'
if not shard:receipt=dict(status='prepared_requires_native_placement' if len(done)==122 else 'partial_requires_remaining_downloads',assets=sorted(done.values(),key=lambda a:a['index']),required=122,completed=len(done));receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8');print('Merged',len(done),'prepared receipts',flush=True)
]====]
-- Optional arg "k/n" runs one shard (parallel Blender processes); run once without it afterwards to merge receipts.
local shard=arg[1];assert(not shard or shard:match('^%d+/%d+$'),'Shard must be k/n')
local f=assert(io.open(o..'/prepare-code.txt','wb'));f:write(code);f:close()
local expr="exec(compile(open(r'"..o.."/prepare-code.txt',encoding='utf-8').read(),'<tripo-decor-preparation>','exec'))"
local env=shard and ('set "OK_DECOR_SHARD='..shard..'" && ') or 'set "OK_DECOR_SHARD=" && '
local log=o..'/prepare'..(shard and ('-'..shard:gsub('/','of')) or '')..'.log'
assert(os.execute('"'..env..'"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 4 --python-expr "'..expr..'" > "'..log..'" 2>&1"'))
