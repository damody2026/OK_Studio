-- Clean low-poly shrubs, hedges and flower beds for the lawns. Decimating the Tripo foliage from 260,000 triangles to about
-- 1500 left loose shards in the air, so here each source mesh is wrapped in a closed voxel shell, reduced, and its colours are
-- baked onto the shell. Metal is switched off first: a metallic source bakes black.
-- Writes output/street-social-city-production/world-tripo-v1/foliage/<key>.glb and <key>.jpg;
-- Tools/street_city_lover_spots_payload.lua swaps them onto the WorldTripo_<key>_* instances.
-- Usage: Tools\lua\lua.exe Tools\build_street_city_foliage.lua
package.path = 'Tools/lua/?.lua;' .. package.path
local j = require('ok.json')
local root = 'C:/portable/OpenKoikatsu/output/street-social-city-production/world-tripo-v1'
local out = root .. '/foliage'
os.execute('if not exist "' .. out:gsub('/', '\\') .. '" mkdir "' .. out:gsub('/', '\\') .. '"')
local code = [====[
import bpy,json,pathlib,numpy as np
from mathutils import Vector
R=pathlib.Path(TASK['root']);D=R/'foliage';plan={q['key']:q for q in json.loads((R/'plan.json').read_text('utf-8-sig'))['items']}
for key,srck in TASK['keys']:
 r=plan[key];s=plan[srck];cap=max(int(r.get('tris',1500)),1000)
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.import_scene.gltf(filepath=str(R/'glb'/('%d_%s.glb'%(s['index'],s['key']))))
 objs=[a for a in bpy.context.scene.objects if a.type=='MESH']
 for a in list(bpy.context.scene.objects):
  if a.type!='MESH':bpy.data.objects.remove(a,do_unlink=True)
 for a in objs:a.select_set(True)
 bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();hi=bpy.context.object;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 vs=np.array([hi.matrix_world@v.co for v in hi.data.vertices]);lo,up=vs.min(0),vs.max(0);dm=up-lo
 # the same size and origin as the prepared Tripo mesh: bottom centre, inside the planned box
 w,d,h=r['size_m'];sc=min(max(w,d)/max(dm[0],dm[1]),h/dm[2]);c=Vector(((lo[0]+up[0])/2,(lo[1]+up[1])/2,lo[2]))
 for v in hi.data.vertices:v.co=(hi.matrix_world@v.co-c)*sc
 hi.matrix_world.identity();hi.data.update();size=max(dm)*sc
 avg=(.2,.3,.1)
 for m in hi.data.materials:
  q=m.node_tree.nodes.get('Principled BSDF')
  if not q:continue
  i=q.inputs['Metallic']
  for l in list(i.links):m.node_tree.links.remove(l)
  i.default_value=0
  t=[n for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and n.outputs['Color'].links]
  if t:
   px=np.array(t[0].image.pixels[:]).reshape(-1,4);k=px[:,3]>.5;avg=tuple(px[k][:,:3].mean(0)) if k.any() else avg
 bpy.ops.object.duplicate();lw=bpy.context.object;lw.name=key
 # leafy crowns take a coarser shell, so the leaves fuse into one body; what still floats alone is dropped
 m=lw.modifiers.new('v','REMESH');m.mode='VOXEL';m.voxel_size=size/(24 if key in TASK['coarse'] else 56);m.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier='v')
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='LOOSE');bpy.ops.object.mode_set(mode='OBJECT')
 parts=sorted(bpy.context.selected_objects,key=lambda o:-len(o.data.vertices));total=sum(len(o.data.vertices) for o in parts)
 for o in parts[1:]:
  if len(o.data.vertices)<total*.04:bpy.data.objects.remove(o,do_unlink=True)
 lw=bpy.data.objects[next(iter(sorted([o.name for o in bpy.context.scene.objects if o!=hi and o.type=='MESH'],key=lambda n:-len(bpy.data.objects[n].data.vertices))))]
 bpy.ops.object.select_all(action='DESELECT')
 for o in bpy.context.scene.objects:
  if o!=hi and o.type=='MESH':o.select_set(True)
 bpy.context.view_layer.objects.active=lw;bpy.ops.object.join();lw=bpy.context.object;lw.name=key
 n=sum(len(p.vertices)-2 for p in lw.data.polygons)
 m=lw.modifiers.new('d','DECIMATE');m.ratio=min(1,cap/n);m.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier='d')
 bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.01);bpy.ops.object.mode_set(mode='OBJECT')
 im=bpy.data.images.new(key,1024,1024);im.generated_color=(*avg,1)
 mt=bpy.data.materials.new('foliage_'+key);mt.use_nodes=True;nt=mt.node_tree;t=nt.nodes.new('ShaderNodeTexImage');t.image=im;q=nt.nodes['Principled BSDF'];nt.links.new(t.outputs['Color'],q.inputs['Base Color']);q.inputs['Roughness'].default_value=.9
 nt.nodes.active=t;lw.data.materials.clear();lw.data.materials.append(mt)
 sn=bpy.context.scene;sn.render.engine='CYCLES';sn.cycles.device='CPU';sn.cycles.samples=1;sn.render.bake.use_selected_to_active=True;sn.render.bake.cage_extrusion=size*.03;sn.render.bake.max_ray_distance=size*.25;sn.render.bake.margin=8;sn.render.bake.use_pass_direct=False;sn.render.bake.use_pass_indirect=False;sn.render.bake.use_pass_color=True
 bpy.ops.object.select_all(action='DESELECT');hi.select_set(True);lw.select_set(True);bpy.context.view_layer.objects.active=lw
 bpy.ops.object.bake(type='DIFFUSE')
 im.filepath_raw=str(D/(key+'.jpg'));im.file_format='JPEG';sn.render.image_settings.quality=90;im.save()
 bpy.ops.object.select_all(action='DESELECT');lw.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(D/(key+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_image_format='JPEG')
 print('FOLIAGE',key,n,'to',sum(len(p.vertices)-2 for p in lw.data.polygons),[round(x,2) for x in lw.dimensions],flush=True)
]====]
-- boxwood_round_b came back as brown balls, so it takes the colours and shape of boxwood_round_a
local keys = { { 'boxwood_round_a', 'boxwood_round_a' }, { 'boxwood_round_b', 'boxwood_round_a' }, { 'azalea_pink_a', 'azalea_pink_a' }, { 'azalea_pink_b', 'azalea_pink_b' },
  { 'hydrangea_blue', 'hydrangea_blue' }, { 'shrub_group_a', 'shrub_group_a' }, { 'shrub_group_b', 'shrub_group_b' }, { 'hedge_low', 'hedge_low' }, { 'hedge_tall', 'hedge_tall' },
  { 'hedge_corner', 'hedge_corner' }, { 'flower_bed_round', 'flower_bed_round' }, { 'flower_border', 'flower_border' }, { 'meadow_patch_a', 'meadow_patch_a' }, { 'meadow_patch_b', 'meadow_patch_b' } }
local path = out .. '/payload.json'
local f = assert(io.open(path, 'wb')); f:write(j.encode({ root = root, code = code, keys = keys, coarse = { 'azalea_pink_a', 'azalea_pink_b', 'boxwood_round_a', 'boxwood_round_b', 'shrub_group_a' } })); f:close()
local expr = "import json;TASK=json.load(open('" .. path .. "',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "' .. expr .. '" > "' .. out .. '/build.log" 2>&1"'))
print('wrote', out)
