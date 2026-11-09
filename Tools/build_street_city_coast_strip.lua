-- Beach edge strip (Docs/STREET_CITY_HANDOFF_20261028.md section 10.12+): the west sea shore ends in square steps (A01-A04)
-- because the ground-sheet top polygons over the 2.5 m 1000/1200 height grid make the land edge stairs. Rule, whole
-- coast: from world-edge-v1/coast-edge-probe.json (measured land-top edge every 1 m of y) take the running maximum
-- over +-W m (so the curve is never inside a protruding step), smooth it, and author one sand strip that
--   - lies 1 cm above the 1200 land top from `inland` m inside the curve out to the curve (covers the steps),
--   - then slopes from 1201 to 1060 over `slope` m past the curve into the water (z 1100), so the waterline is the
--     smooth curve + about slope*(101/141) m instead of a stair.
-- Coordinates are UE world / 100 (metres); one material slot S_CoastSand (installed with the beach sand MI).
-- Usage: lua Tools/build_street_city_coast_strip.lua [--window 12] [--inland 6] [--slope 6]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/world-edge-v1'
local window,inland,slope=12,6,6
for i=1,#arg do if arg[i]=='--window' then window=tonumber(arg[i+1]) elseif arg[i]=='--inland' then inland=tonumber(arg[i+1]) elseif arg[i]=='--slope' then slope=tonumber(arg[i+1]) end end
local code=[====[
import bpy,bmesh,json,hashlib,math
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
O=Path(TASK['out']);P=json.loads((O/'coast-edge-probe.json').read_text('utf-8-sig'));W=float(TASK['window']);IN=float(TASK['inland']);SL=float(TASK['slope']);MAXS=4.0
rows=[(r['y']/100,(r['edge']['land_x'] if r['edge'] and r['edge']['land_x'] is not None else None)) for r in P['rows']]
# rows with no land on the probe line (the river mouth: water from 200 m inland) split the coast into segments, so the
# strip never bridges a river
segs=[[]]
for y,x in rows:
 if x is None:
  if segs[-1]:segs.append([])
 else:segs[-1].append((y,x/100))
segs=[s for s in segs if len(s)>=3]
bm=bmesh.new();prof=[(IN,12.01),(0.0,12.01),(-SL*.35,11.62),(-SL*.7,11.12),(-SL,10.60)];allcols=[];shift=0
for seg in segs:
 ys=[y for y,_ in seg];edge=dict(seg)
 # outermost land (smallest x: the sea is at x < edge) within +-W m of the same segment, then a 3-pass box smooth that
 # only ever moves seaward, so the curve is never inside a protruding step
 cur=[min(edge[v] for v in ys if abs(v-y)<=W) for y in ys]
 for _ in range(3):
  cur=[min(cur[i],sum(cur[max(0,i-4):i+5])/len(cur[max(0,i-4):i+5])) for i in range(len(cur))]
 # never more than MAXS m seaward of the row's own land edge (a headland next to the river mouth pulled the window
 # minimum 44 m out over the water on the first build), then re-smooth lightly
 cur=[max(c,edge[y]-MAXS) for y,c in zip(ys,cur)]
 cur=[sum(cur[max(0,i-2):i+3])/len(cur[max(0,i-2):i+3]) for i in range(len(cur))]
 cur=[max(c,edge[y]-MAXS) for y,c in zip(ys,cur)]
 shift=max(shift,max(edge[y]-c for y,c in zip(ys,cur)))
 # profile across the strip (offset along +x = inland, z in metres); the flat top always reaches 1 m past the row's
 # real edge so no stair corner is left uncovered
 cols=[[bm.verts.new((cx+(max(IN,edge[y]-cx+1.0) if dx==IN else dx),y,z)) for dx,z in prof] for y,cx in zip(ys,cur)]
 for a,b in zip(cols,cols[1:]):
  for k in range(len(prof)-1):bm.faces.new((a[k],a[k+1],b[k+1],b[k]))
 allcols+=cols
assert allcols,'no coast segment'
bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
for f in bm.faces:
 if f.normal.z<0:f.normal_flip()
me=bpy.data.meshes.new('CoastStrip');bm.to_mesh(me);bm.free()
for p in me.polygons:p.use_smooth=True
o=bpy.data.objects.new('CoastStrip',me);bpy.context.collection.objects.link(o)
m=bpy.data.materials.new('S_CoastSand');m.use_nodes=True;me.materials.append(m)
# planar UVs in metres / 4 so the tiled sand texture keeps its scale
uv=me.uv_layers.new(name='UVMap')
for l in me.loops:v=me.vertices[l.vertex_index].co;uv.data[l.index].uv=(v.x/4,v.y/4)
me.calc_loop_triangles();dest=O/'coast-strip';dest.mkdir(parents=True,exist_ok=True);glb=dest/'coast-strip.glb'
bpy.ops.object.select_all(action='SELECT');bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)
xyz=[v.co for v in me.vertices]
# placement probes: real vertices at both ends and the middle (asymmetric in y), checked against the imported mesh
probes=[[round(c.x,3),round(c.y,3),round(c.z,3)] for c in (xyz[0],xyz[len(xyz)//2],xyz[-1],xyz[len(prof)*7+2])]
meta=dict(status='authored_requires_native_install',path=str(glb),sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),probe_map_sha256=P['map_sha256'],window_m=W,inland_m=IN,slope_m=SL,
 triangles=len(me.loop_triangles),rows=len(allcols),segments=len(segs),max_shift_m=round(shift,2),bounds_m=[[min(c[k] for c in xyz) for k in range(3)],[max(c[k] for c in xyz) for k in range(3)]],probes_m=probes)
(dest/'build.json').write_text(json.dumps(meta,indent=1),'utf8');print('COAST',meta['triangles'],'tris shift',meta['max_shift_m'],flush=True)
]====]
local path=out..'/coast-strip-payload.json'
local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,window=window,inland=inland,slope=slope}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/coast-strip-build.log" 2>&1"'))
print('Coast strip authored; see world-edge-v1/coast-strip-build.log')
