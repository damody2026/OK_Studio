-- Beach props (Docs/STREET_CITY_WORLD_GAP_INVENTORY_20261029.md section 3, Z1: the beach has only palms, no umbrellas,
-- loungers or lifeguard tower). Blender-authored low-poly models (no Tripo: the queued Tripo set waits for the user's
-- Batch Export) and a placement rule along the beach strip:
--   - every `spacing` m of coast: one umbrella with two loungers facing the sea, on the strip's flat top 3 m inland of
--     the smoothed coast curve (same curve as build_street_city_coast_strip.lua), skipping rows within 15 m of a gap
--     (river mouth) and alternating canopy colour sets;
--   - one lifeguard tower every `tower` m, 4 m inland, facing the sea.
-- Output world-edge-v1/beach-props/{umbrella,lounger,tower}.glb + placements.json (UE world cm, yaw deg).
-- Usage: lua Tools/build_street_city_beach_props.lua [--spacing 24] [--tower 260]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/world-edge-v1'
local spacing,tower=24,260
for i=1,#arg do if arg[i]=='--spacing' then spacing=tonumber(arg[i+1]) elseif arg[i]=='--tower' then tower=tonumber(arg[i+1]) end end
local code=[====[
import bpy,bmesh,json,hashlib,math
from pathlib import Path
from mathutils import Vector,Matrix
O=Path(TASK['out']);D=O/'beach-props';D.mkdir(parents=True,exist_ok=True)
def reset():bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name,rgb,rough=.6,metal=0.):
 m=bpy.data.materials.get(name) or bpy.data.materials.new(name);m.use_nodes=True;b=m.node_tree.nodes['Principled BSDF']
 b.inputs['Base Color'].default_value=(*rgb,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal;return m
def obj(name,bm,mats):
 me=bpy.data.meshes.new(name);bm.to_mesh(me);bm.free()
 for m in mats:me.materials.append(m)
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);return o
def cyl(bm,p0,p1,r,seg=8,mi=0):
 p0,p1=Vector(p0),Vector(p1);ax=(p1-p0);L=ax.length;rot=ax.to_track_quat('Z','Y').to_matrix().to_4x4()
 res=bmesh.ops.create_cone(bm,cap_ends=True,segments=seg,radius1=r,radius2=r,depth=L,matrix=Matrix.Translation((p0+p1)/2)@rot)
 for f in {f for v in res['verts'] for f in v.link_faces}:f.material_index=mi
def box(bm,c,s,mi=0,rot=None):
 m=Matrix.Translation(c)@(rot or Matrix.Identity(4))@Matrix.Diagonal((*s,1))
 res=bmesh.ops.create_cube(bm,size=1,matrix=m)
 for f in {f for v in res['verts'] for f in v.link_faces}:f.material_index=mi
def export(name):
 for o in bpy.context.scene.objects:o.select_set(True)
 glb=D/(name+'.glb');bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)
 tris=sum(len(p.vertices)-2 for o in bpy.context.scene.objects for p in o.data.polygons)
 return dict(path=str(glb),sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),triangles=tris)
built={}
# umbrella: 8-panel canopy (two alternating fabric colours), 2.3 m tall, 2.4 m wide, slight droop, valance
for setname,(ca,cb) in {'umbrella_a':((.92,.30,.22),(.96,.93,.86)),'umbrella_b':((.16,.45,.72),(.96,.93,.86))}.items():
 reset();bm=bmesh.new();R=1.2;H=2.25;N=8
 cyl(bm,(0,0,0),(0,0,H+.12),.025,8,2)
 apex=bm.verts.new((0,0,H+.08));rim=[bm.verts.new((R*math.cos(2*math.pi*k/N),R*math.sin(2*math.pi*k/N),H-.38)) for k in range(N)]
 mid=[bm.verts.new((.62*R*math.cos(2*math.pi*(k+.5)/N),.62*R*math.sin(2*math.pi*(k+.5)/N),H-.12)) for k in range(N)]
 for k in range(N):
  f=bm.faces.new((apex,rim[k],mid[k]));f.material_index=k%2;g=bm.faces.new((apex,mid[k],rim[(k+1)%N]));g.material_index=k%2
  h=bm.faces.new((rim[k],rim[(k+1)%N],mid[k]));h.material_index=k%2
  lo=[bm.verts.new((v.co.x*1.0,v.co.y*1.0,v.co.z-.14)) for v in (rim[k],rim[(k+1)%N])];v=bm.faces.new((rim[k],lo[0],lo[1],rim[(k+1)%N]));v.material_index=k%2
 box(bm,(0,0,.04),(.42,.42,.08),3)
 bmesh.ops.recalc_face_normals(bm,faces=bm.faces);o=obj(setname,bm,[mat('Fabric_'+setname,ca,.85),mat('Fabric_white',cb,.85),mat('Pole_metal',(.78,.78,.76),.35,.8),mat('Base_concrete',(.55,.53,.5),.9)])
 for f in o.data.polygons:f.use_smooth=False
 built[setname]=export(setname)
# lounger: aluminium frame, slatted bed, raised backrest (towards +x), 1.95 x .68 m
reset();bm=bmesh.new()
for y in (-.31,.31):
 cyl(bm,(-.95,y,.30),(.45,y,.30),.018,6,0);cyl(bm,(.45,y,.30),(.92,y,.78),.018,6,0)
 for x in (-.85,.35):cyl(bm,(x,y,0),(x,y,.30),.018,6,0)
for i in range(11):box(bm,(-.9+i*.125,0,.33),(.10,.62,.025),1)
back=Matrix.Rotation(math.radians(-45),4,'Y')
for i in range(5):box(bm,(.50+i*.09,0,.37+i*.09),(.10,.62,.025),1,back)
box(bm,(-.25,0,.37),(1.25,.58,.05),2)
bmesh.ops.recalc_face_normals(bm,faces=bm.faces);obj('lounger',bm,[mat('Frame_alu',(.82,.83,.84),.3,.9),mat('Slat_teak',(.55,.36,.2),.7),mat('Cushion_canvas',(.94,.92,.85),.9)])
built['lounger']=export('lounger')
# lifeguard tower: 4 splayed legs, 2.2 m platform with railing, hut with roof, ladder towards -x (sea side is +x local)
reset();bm=bmesh.new();P=2.2
for sx in (-1,1):
 for sy in (-1,1):cyl(bm,(sx*.95,sy*.95,0),(sx*.7,sy*.7,P),.07,6,0)
for sx in (-1,1):cyl(bm,(sx*.85,-.85,1.0),(sx*.85,.85,1.0),.04,6,0);cyl(bm,(-.85,sx*.85,1.0),(.85,sx*.85,1.0),.04,6,0)
box(bm,(0,0,P+.05),(2.0,2.0,.1),1)
box(bm,(-.2,0,P+.95),(1.3,1.5,1.7),2)
for k in range(5):box(bm,(-.2-.66+k*.33,0,P+.95),(.04,1.52,1.72),3)
roof=bmesh.ops.create_cone(bm,cap_ends=True,segments=4,radius1=1.35,radius2=.05,depth=.7,matrix=Matrix.Translation((-.2,0,P+2.15))@Matrix.Rotation(math.radians(45),4,'Z'))
for f in {f for v in roof['verts'] for f in v.link_faces}:f.material_index=3
for y in (-.95,.95):cyl(bm,(.95,y,P+.1),(.95,y,P+1.1),.03,6,0)
cyl(bm,(.95,-.95,P+1.1),(.95,.95,P+1.1),.03,6,0);cyl(bm,(.95,-.95,P+.6),(.95,.95,P+.6),.025,6,0)
for y in (-.3,.3):cyl(bm,(-1.9,y,0),(-1.0,y,P),.035,6,0)
for k in range(8):t=(k+1)/9;cyl(bm,(-1.9+.9*t,-.3,P*t),(-1.9+.9*t,.3,P*t),.025,6,0)
bmesh.ops.recalc_face_normals(bm,faces=bm.faces);obj('tower',bm,[mat('Tower_wood_white',(.93,.92,.88),.75),mat('Tower_deck',(.6,.45,.3),.8),mat('Tower_hut_red',(.82,.18,.14),.7),mat('Tower_trim',(.95,.95,.95),.6)])
built['tower']=export('tower')
# placements along the same smoothed coast curve as the strip
P_=json.loads((O/'coast-edge-probe.json').read_text('utf-8-sig'));segs=[[]]
for r in P_['rows']:
 x=r['edge']['land_x'] if r['edge'] and r['edge']['land_x'] is not None else None
 if x is None:
  if segs[-1]:segs.append([])
 else:segs[-1].append((r['y']/100,x/100))
segs=[s for s in segs if len(s)>=40]
place=[];k=0
for seg in segs:
 ys=[y for y,_ in seg];edge=dict(seg);cur=[min(edge[v] for v in ys if abs(v-y)<=12) for y in ys]
 for _ in range(3):cur=[min(cur[i],sum(cur[max(0,i-4):i+5])/len(cur[max(0,i-4):i+5])) for i in range(len(cur))]
 cur=[max(c,edge[y]-4) for y,c in zip(ys,cur)];C=dict(zip(ys,cur))
 lo,hi=ys[0]+15,ys[-1]-15
 def at(y,inl):
  i=min(range(len(ys)),key=lambda q:abs(ys[q]-y));a=cur[max(0,i-3)];b=cur[min(len(cur)-1,i+3)];dy=ys[min(len(cur)-1,i+3)]-ys[max(0,i-3)]
  yaw=math.degrees(math.atan2(-(b-a),dy))  # local +x of the props faces the sea (-x) after the 180 turn below
  return C[ys[i]]+inl,ys[i],yaw+180
 y=lo
 while y<=hi:
  x,yy,yaw=at(y,3.0);s='umbrella_a' if k%2==0 else 'umbrella_b';k+=1
  place.append(dict(kind=s,cm=[x*100,yy*100,1201],yaw=yaw))
  for dy in (-1.0,1.0):place.append(dict(kind='lounger',cm=[(x+.4)*100,(yy+dy)*100,1201],yaw=yaw+180))
  y+=float(TASK['spacing'])
 y=lo+float(TASK['tower'])/2
 while y<=hi:x,yy,yaw=at(y,4.0);place.append(dict(kind='tower',cm=[x*100,yy*100,1201],yaw=yaw));y+=float(TASK['tower'])
(D/'placements.json').write_text(json.dumps(dict(status='authored_requires_native_install',probe_map_sha256=P_['map_sha256'],models=built,placements=place),indent=1),'utf8')
print('BEACH',{n:b['triangles'] for n,b in built.items()},len(place),'placements',flush=True)
]====]
local path=out..'/beach-props-payload.json'
local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,spacing=spacing,tower=tower}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/beach-props-build.log" 2>&1"'))
print('Beach props authored; see world-edge-v1/beach-props-build.log')
