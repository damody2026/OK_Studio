-- World edge skirt (Docs/STREET_CITY_WORLD_GAP_INVENTORY_20261029.md §3, items 1-2): the city ground ends in a cut edge
-- with bare sky below the horizon (G085, G150, A13). This authors one low-poly ground skirt around the city ground union
-- from world-edge-v1/probe.json (native world_edge_probe):
--   - inner rim on the union border at the probed ground height - 5 cm, plus a 30 m lip tucked 0.5 m under the ground;
--   - flat for the first 150 m, then rolling grass hills (25-80 m by 900 m) and a far ridge (up to ~270 m) out to 4 km
--     so the horizon is land, not sky;
--   - only on the requested sides (default north,east,south: the west side is the existing ocean plane).
-- Coordinates are UE world / 100 (metres, same axis names); the installer reads the imported bounds to pick the axis
-- mapping, so no importer convention is assumed here. One material slot S_WorldEdgeGrass (M_GrassWorldTriplanar_v2 at
-- install: the city ground's meadow instance, planar UVs in metres / 4); ground that already lies past the border
-- (Outdoor_annex_ground) is left open and met at its level.
-- Usage: lua Tools/build_street_city_world_edge.lua [--sides north,east,south] [--reach 4000]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/world-edge-v1'
local sides,reach='north,east,south',4000
for i=1,#arg do if arg[i]=='--sides' then sides=arg[i+1] elseif arg[i]=='--reach' then reach=tonumber(arg[i+1]) end end
local code=[====[
import bpy,bmesh,math,json,hashlib,re
from pathlib import Path
bpy.ops.wm.read_factory_settings(use_empty=True)
O=Path(TASK['out']);P=json.loads((O/'probe.json').read_text('utf-8-sig'));SIDES=set(TASK['sides'].split(','));REACH=float(TASK['reach'])
x0,y0,x1,y1=[v/100 for v in P['city_ground_union']]
S={}
for s in P['edge_samples']:
 if s['hit']:S.setdefault(s['side'],[]).append(((s['x']/100,s['y']/100),s['hit']['z']/100))
allz=sorted(z for v in S.values() for _,z in v);zmed=allz[len(allz)//2]
# ground that already exists past the city border (Outdoor_annex_ground with the stadium, y 1100-1380 m): the skirt
# leaves a hole there and meets it at its walk level (the first skirt lay 10 cm over it, a darker floating lawn at
# G086 / G085 / G150, 11-02). Flat ground actors reaching past the union, top under 12.5 m, not activity planes.
HOLES=[]
for g in P['ground']:
 l=g['label']
 if re.match(r'^G\d\d',l) or l.startswith(('Activity_','Destination_')):continue
 a,b=[v/100 for v in g['min']],[v/100 for v in g['max']]
 if (b[0]>x1+5 or b[1]>y1+5 or a[0]<x0-5 or a[1]<y0-5) and b[2]<12.5 and b[0]-a[0]<1000 and b[1]-a[1]<1000:HOLES.append((a[0],a[1],b[0],b[1],a[2]))
def zside(side,t):
 # probed ground height on one border at parameter t (x for north/south, y for east/west), linear between samples
 pts=sorted((p[0] if side in('north','south') else p[1],z) for p,z in S.get(side,[]))
 if not pts:return zmed
 if t<=pts[0][0]:return pts[0][1]
 for (a,za),(b,zb) in zip(pts,pts[1:]):
  if t<=b:return za+(zb-za)*(t-a)/max(b-a,1e-6)
 return pts[-1][1]
def zedge(x,y):
 # height of the nearest border point
 cx,cy=min(max(x,x0),x1),min(max(y,y0),y1);d={'north':abs(cy-y0),'south':abs(cy-y1),'west':abs(cx-x0),'east':abs(cx-x1)}
 if x0<x<x1 and y0<y<y1:side=min(d,key=d.get)
 else:side='north' if y<=y0 else 'south' if y>=y1 else 'west' if x<=x0 else 'east'
 return zside(side,cx if side in('north','south') else cy)
def outside(x,y):
 dx=max(x0-x,0,x-x1);dy=max(y0-y,0,y-y1);d=math.hypot(dx,dy)
 for a0,b0,a1,b1,_ in HOLES:d=min(d,math.hypot(max(a0-x,0,x-a1),max(b0-y,0,y-b1)))
 return d
def hole_at(x,y,m=0):
 for h in HOLES:
  if h[0]-m<=x<=h[2]+m and h[1]-m<=y<=h[3]+m:return h
 return None
def fbm(x,y):
 v=0;a=1;f=1/900
 for k in range(4):v+=a*(math.sin(x*f+1.7*k)*math.cos(y*f*1.3-.9*k)+.5*math.sin((x+y)*f*.7+k));a*=.5;f*=2.1
 return .5+.5*max(-1,min(1,v/1.6))
def smooth(a,b,t):t=min(max((t-a)/(b-a),0),1);return t*t*(3-2*t)
OUT=[0,10,25,50,100,150,200,300,400,550,700,900,1150,1450,1800,2200,2700,3300,4000]
OUT=[o*REACH/4000 for o in OUT]
def axis(lo,hi,ext_lo,ext_hi):
 c={lo+30,hi-30};k=lo+100
 while k<hi-30:c.add(k);k+=100
 c|={lo-o for o in OUT} if ext_lo else {lo}
 c|={hi+o for o in OUT} if ext_hi else {hi}
 return sorted(c)
xs=axis(x0,x1,'west' in SIDES,'east' in SIDES);ys=axis(y0,y1,'north' in SIDES,'south' in SIDES)
# hole edges are grid lines (plus a 50 m ring of lines around each hole so the rim reaches the hole's level smoothly)
for a0,b0,a1,b1,_ in HOLES:
 xs=sorted(set(xs)|{a0,a1}|{a0-o for o in OUT if 0<o<=150}|{a1+o for o in OUT if 0<o<=150});ys=sorted(set(ys)|{b0,b1}|{b0-o for o in OUT if 0<o<=150}|{b1+o for o in OUT if 0<o<=150})
def zat(x,y):
 d=outside(x,y);ze=zedge(x,y);h=hole_at(x,y,1e-6)
 if h is not None:return h[4]-.05
 # nearer to a hole than to the city border: the rim follows that ground's level instead of the city's
 du=math.hypot(max(x0-x,0,x-x1),max(y0-y,0,y-y1))
 for a0,b0,a1,b1,hz in HOLES:
  if math.hypot(max(a0-x,0,x-a1),max(b0-y,0,y-b1))<du:ze=hz
 if d<=0:return ze-.5
 # near rolling hills rise from 150 m to about 900 m out (25-80 m), a taller far ridge (+70-190 m) from 1.2 km; the
 # earlier single 35-80 m ramp to 2.5 km stayed under 2 degrees from street level and read as flat land (G084, 11-01)
 return ze-.05+smooth(150,900,d)*(25+55*fbm(x,y))+smooth(1200,3000,d)*(70+120*fbm(x*.6+3100,y*.6-1700))
bm=bmesh.new();V={}
def v(i,k):
 if (i,k) not in V:x,y=xs[i],ys[k];V[(i,k)]=bm.verts.new((x,y,zat(x,y)))
 return V[(i,k)]
inner=(x0+30,y0+30,x1-30,y1-30);cells=0
for i in range(len(xs)-1):
 for k in range(len(ys)-1):
  a,b,c,d=xs[i],xs[i+1],ys[k],ys[k+1]
  if a>=inner[0] and b<=inner[2] and c>=inner[1] and d<=inner[3]:continue
  if hole_at((a+b)/2,(c+d)/2) is not None:continue
  # sides that are not extended keep no strip past their border (west: the ocean plane)
  if ('west' not in SIDES and b<=x0) or ('east' not in SIDES and a>=x1) or ('north' not in SIDES and d<=y0) or ('south' not in SIDES and c>=y1):continue
  bm.faces.new((v(i,k),v(i+1,k),v(i+1,k+1),v(i,k+1)));cells+=1
bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
for f in bm.faces:
 if f.normal.z<0:f.normal_flip()
me=bpy.data.meshes.new('WorldEdgeSkirt');bm.to_mesh(me);bm.free()
for p in me.polygons:p.use_smooth=True
# planar UVs in metres / 4, the same scale as the city ground sheets, so the skirt can draw the city's meadow instance
# instead of its own triplanar grass (the border between the two read as a seam, G150)
uv=me.uv_layers.new(name='UVMap')
for l in me.loops:v=me.vertices[l.vertex_index].co;uv.data[l.index].uv=(v.x/4,v.y/4)
o=bpy.data.objects.new('WorldEdgeSkirt',me);bpy.context.collection.objects.link(o)
m=bpy.data.materials.new('S_WorldEdgeGrass');m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.2,.35,.12,1);me.materials.append(m)
me.calc_loop_triangles();dest=O/'skirt';dest.mkdir(parents=True,exist_ok=True);glb=dest/'skirt.glb'
bpy.ops.object.select_all(action='SELECT');bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)
xyz=[v.co for v in me.vertices]
# placement probes: real vertices 500-2500 m out on every built side (asymmetric about both axes), traced at install to
# verify the imported axis convention instead of trusting the bounding box (a y-mirrored skirt passed the bounds check
# and covered the city, round 12)
probes=[]
for side in sorted(SIDES):
 c=[v for v in xyz if 500<outside(v.x,v.y)<2500 and ((side=='north' and v.y<y0) or (side=='south' and v.y>y1) or (side=='east' and v.x>x1) or (side=='west' and v.x<x0))]
 c.sort(key=lambda v:(round(v.x),round(v.y)))
 for v in c[::max(1,len(c)//3)][:3]:probes.append([round(v.x,3),round(v.y,3),round(v.z,3)])
meta=dict(holes_m=[list(h) for h in HOLES],status='authored_requires_native_install',path=str(glb),sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),probe_map_sha256=P['map_sha256'],sides=sorted(SIDES),reach_m=REACH,
 union_m=[x0,y0,x1,y1],triangles=len(me.loop_triangles),cells=cells,bounds_m=[[min(c[k] for c in xyz) for k in range(3)],[max(c[k] for c in xyz) for k in range(3)]],probes_m=probes,edge_z_median_m=zmed)
(dest/'build.json').write_text(json.dumps(meta,indent=1),'utf8');print('SKIRT',meta['triangles'],'tris',meta['bounds_m'],flush=True)
]====]
local path=out..'/skirt-payload.json';os.execute('mkdir "'..out:gsub('/','\\')..'" 2>nul')
local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,sides=sides,reach=reach}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/skirt-build.log" 2>&1"'))
print('World edge skirt authored; see world-edge-v1/skirt-build.log')
