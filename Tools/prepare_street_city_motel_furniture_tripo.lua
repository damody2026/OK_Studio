-- Prepares the collected motel-furniture Tripo exports (motel-furniture-tripo-v2/downloads, Tools/collect_street_city_motel_furniture_tripo.lua)
-- for the mandatory instant-meshes-rs pass: join meshes, origin at floor centre, uniform scale so the model fits the
-- plan.json size_m box ([width, depth, height] m; largest horizontal extent -> max(width, depth)), textures <= 2K,
-- pre-decimated to <= 35k triangles (or the item's own tris cap). Receipt: prepared.json (fields compatible with remesh_street_city_motel_tripo_decor.lua).
-- Usage: lua Tools/prepare_street_city_motel_furniture_tripo.lua [k/n]  -- shards run in parallel; run once without args to merge.
package.path='Tools/lua/?.lua;'..package.path
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/'..(os.getenv('OK_TRIPO_SET') or 'motel-furniture-tripo-v2')
local code=[====[
import bpy,bmesh,json,hashlib,os
from pathlib import Path
from mathutils import Vector
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production')/__import__('os').environ.get('OK_TRIPO_SET','motel-furniture-tripo-v2');plan=json.loads((O/'plan.json').read_text('utf8'));dest=O/'prepared';dest.mkdir(exist_ok=True)
shard=os.environ.get('OK_DECOR_SHARD');sk,sn=(int(v) for v in shard.split('/')) if shard else (0,1);receipt_path=O/('prepared-shard%d.json'%sk if shard else 'prepared.json');done={}
for p in [O/'prepared.json']+sorted(O.glob('prepared-shard*.json')):
 if p.exists():done.update({r['id']:r for r in json.loads(p.read_text('utf8'))['assets']})
N=len(plan['items'])
for r in plan['items']:
 index=r['index'];rid='%s-%03d-%s'%(plan.get('id_prefix','mf'),index,r['key'])
 # sets collected straight from the browser (life-tripo-v1) keep glb/<index>_<key>.glb; the motel sets use downloads/
 src=O/'glb'/('%d_%s.glb'%(index,r['key'])) if (O/'glb').is_dir() else O/'downloads'/('motel-furniture-v2-%03d.glb'%index)
 if not src.exists() or index%sn!=sk:continue
 source_sha=hashlib.sha256(src.read_bytes()).hexdigest()
 if rid in done:
  old=done[rid]
  if old['source_sha256']==source_sha and Path(old['path']).exists() and hashlib.sha256(Path(old['path']).read_bytes()).hexdigest()==old['sha256']:continue
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(src));objs=[a for a in bpy.context.scene.objects if a.type=='MESH'];assert objs,(index,src)
 for a in list(bpy.context.scene.objects):
  if a.type!='MESH':bpy.data.objects.remove(a,do_unlink=True)
 bpy.ops.object.select_all(action='DESELECT')
 for a in objs:a.select_set(True)
 bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();a=bpy.context.object;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 vs=[a.matrix_world@v.co for v in a.data.vertices];lo=Vector([min(v[k] for v in vs) for k in range(3)]);hi=Vector([max(v[k] for v in vs) for k in range(3)]);dims=hi-lo;assert min(dims)>1e-5,(index,list(dims))
 w,d,h=r['size_m'];scale=min(max(w,d)/max(dims.x,dims.y),h/dims.z);center=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for v in a.data.vertices:v.co=(a.matrix_world@v.co-center)*scale
 a.matrix_world.identity();before=sum(len(p.vertices)-2 for p in a.data.polygons)
 # plan items may carry their own triangle cap (world-tripo-v1: 300-8000 by how many instances get placed)
 cap=int(r.get('tris',35000))
 if before>cap:
  bm=bmesh.new();bm.from_mesh(a.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001);bm.to_mesh(a.data);bm.free();a.data.update()
  last=None
  for attempt in range(8):
   count=sum(len(p.vertices)-2 for p in a.data.polygons)
   if count<=cap:break
   # collapse stalls on UV seams of split Tripo shells: weld near vertices (0.2 % of the size), then collapse again
   if last is not None and count>last*.97:
    bm=bmesh.new();bm.from_mesh(a.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=max(a.dimensions)*.002);bm.to_mesh(a.data);bm.free();a.data.update()
   last=count
   m=a.modifiers.new('Furniture budget','DECIMATE');m.ratio=min(1.,cap*.94/count);m.use_collapse_triangulate=True;bpy.context.view_layer.objects.active=a;bpy.ops.object.modifier_apply(modifier=m.name)
 after=sum(len(p.vertices)-2 for p in a.data.polygons);over_cap=after>cap  # thin wire pieces (carts, racks) stop decimating; the instant-meshes-rs pass lowers them further
 if over_cap:print('Over cap',index,before,'to',after,'cap',cap,flush=True)
 for p in a.data.polygons:p.use_smooth=True
 assert a.data.materials and any(m and m.use_nodes and any(n.type=='TEX_IMAGE' and n.image for n in m.node_tree.nodes) for m in a.data.materials),(index,'Missing Tripo texture')
 for m in a.data.materials:
  if not m or not m.use_nodes:continue
  for n in m.node_tree.nodes:
   if n.type=='TEX_IMAGE' and n.image and max(n.image.size)>2048:
    im=n.image;f=2048/max(im.size);im.scale(max(1,round(im.size[0]*f)),max(1,round(im.size[1]*f)))
 target=dest/(rid+'.glb');bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
 done[rid]=dict(id=rid,key=r['key'],rooms=r.get('rooms',r.get('place')),index=index,source=str(src),source_sha256=source_sha,path=str(target),sha256=hashlib.sha256(target.read_bytes()).hexdigest(),source_triangles=before,triangles=after,over_cap=over_cap,size_m=list(a.dimensions),plan_size_m=r['size_m'],scope='Actual Tripo Batch Export mesh, origin at floor centre, uniformly scaled to fit the plan size box; simplified to <=35k triangles before the instant-meshes-rs pass. No generated geometry substituted.')
 receipt_path.write_text(json.dumps(dict(status='partial',assets=list(done.values()),required=N,completed=len(done)),ensure_ascii=False,indent=2),'utf8');print('Prepared',index,rid,before,'to',after,flush=True)
assert done,'No collected motel-furniture-v2-###.glb files'
if not shard:receipt_path.write_text(json.dumps(dict(status='prepared_requires_remesh' if len(done)==N else 'partial',assets=sorted(done.values(),key=lambda a:a['index']),required=N,completed=len(done)),ensure_ascii=False,indent=2),'utf8');print('Merged',len(done),'prepared receipts',flush=True)
]====]
local shard=arg[1];assert(not shard or shard:match('^%d+/%d+$'),'Shard must be k/n')
local f=assert(io.open(o..'/prepare-code.txt','wb'));f:write(code);f:close()
local expr="exec(compile(open(r'"..o.."/prepare-code.txt',encoding='utf-8').read(),'<tripo-furniture-preparation>','exec'))"
local env=shard and ('set "OK_DECOR_SHARD='..shard..'" && ') or 'set "OK_DECOR_SHARD=" && '
local log=o..'/prepare'..(shard and ('-'..shard:gsub('/','of')) or '')..'.log'
assert(os.execute('"'..env..'"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 4 --python-expr "'..expr..'" > "'..log..'" 2>&1"'))
