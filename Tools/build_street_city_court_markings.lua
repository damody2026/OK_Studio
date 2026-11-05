-- Geometric white paint strips with exact planar overlap subtraction.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/court'
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'))
local code=[====[
import bpy,bmesh,math,json,hashlib
from pathlib import Path
O=Path(TASK['out']);polys=[];labels=[]
def area(p):return sum(p[i][0]*p[(i+1)%len(p)][1]-p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p)))/2
def add(p,label):
 if area(p)<0:p=p[::-1]
 assert area(p)>1e-7;polys.append(p);labels.append(label)
def rect(x1,y1,x2,y2,label):add([(x1,y1),(x2,y1),(x2,y2),(x1,y2)],label)
def arc(cx,cy,r,a,b,mirror,label):
 n=max(8,math.ceil(abs(b-a)*r/8))
 for i in range(n):
  u=a+(b-a)*i/n;v=a+(b-a)*(i+1)/n;add([(cx+r*math.cos(u),cy+mirror*r*math.sin(u)),(cx+r*math.cos(v),cy+mirror*r*math.sin(v)),(cx+(r-5)*math.cos(v),cy+mirror*(r-5)*math.sin(v)),(cx+(r-5)*math.cos(u),cy+mirror*(r-5)*math.sin(u))],label)
arc(0,0,180,0,2*math.pi,1,'centre-circle')
angle=math.acos(657.5/672.5);join=math.sqrt(672.5**2-657.5**2)
for mirror in [1,-1]:
 def box(x1,y1,x2,y2,label):rect(x1,min(mirror*y1,mirror*y2),x2,max(mirror*y1,mirror*y2),label)
 box(-245,-1400,-240,-820,'restricted-area');box(240,-1400,245,-820,'restricted-area');box(-245,-825,245,-820,'free-throw-line')
 arc(0,-822.5*mirror,180,0,math.pi,mirror,'free-throw-semicircle')
 arc(0,-1242.5*mirror,675,angle,math.pi-angle,mirror,'three-point-arc')
 box(-660,-1400,-655,-1242.5+join,'three-point-corner');box(655,-1400,660,-1242.5+join,'three-point-corner')
 arc(0,-1242.5*mirror,130,0,math.pi,mirror,'no-charge-semicircle');box(-130,-1280,-125,-1242.5,'no-charge-leg');box(125,-1280,130,-1242.5,'no-charge-leg')
 for y in [-1225,-1140,-1055]:box(-255,y-2.5,-245,y+2.5,'rebound-place');box(245,y-2.5,255,y+2.5,'rebound-place')
def half(poly,a,b,inside):
 if not poly:return []
 def d(p):return ((b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0]))*(1 if inside else -1)
 out=[];prev=poly[-1];d0=d(prev)
 for cur in poly:
  d1=d(cur);i0=d0>=0;i1=d1>=0
  if i0!=i1:
   t=d0/(d0-d1);out.append((prev[0]+(cur[0]-prev[0])*t,prev[1]+(cur[1]-prev[1])*t))
  if i1:out.append(cur)
  prev,d0=cur,d1
 clean=[]
 for p in out:
  if not clean or math.dist(p,clean[-1])>1e-8:clean.append(p)
 return clean
def subtract(poly,clip):
 out=[];remaining=poly
 for a,b in zip(clip,clip[1:]+clip[:1]):
  outside=half(remaining,a,b,False)
  if len(outside)>=3 and abs(area(outside))>1e-7:out.append(outside)
  remaining=half(remaining,a,b,True)
  if len(remaining)<3:return out
 return out
def bounds(p):return [min(q[0] for q in p),min(q[1] for q in p),max(q[0] for q in p),max(q[1] for q in p)]
bb=[bounds(p) for p in polys];pieces=[]
for i,p in enumerate(polys):
 fragments=[p]
 for j in range(i):
  if bb[i][0]>=bb[j][2] or bb[j][0]>=bb[i][2] or bb[i][1]>=bb[j][3] or bb[j][1]>=bb[i][3]:continue
  fragments=[q for f in fragments for q in subtract(f,polys[j])]
  if not fragments:break
 pieces.extend(fragments)
bpy.ops.wm.read_factory_settings(use_empty=True);vertices=[];faces=[]
for poly in pieces:
 first=len(vertices);vertices.extend((x/100,y/100,0) for x,y in poly)
 for i in range(1,len(poly)-1):faces.append((first,first+i,first+i+1))
mesh=bpy.data.meshes.new('CourtPaint');mesh.from_pydata(vertices,[],faces);mesh.update();bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-8);bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-8);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free();mesh.update();mat=bpy.data.materials.new('CourtWhite');mat.diffuse_color=(.85,.85,.83,1);mesh.materials.append(mat);ob=bpy.data.objects.new('BasketballMarkings',mesh);bpy.context.collection.objects.link(ob);path=O/'court-markings.glb';bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB');mesh.calc_loop_triangles();receipt=dict(status='authored_requires_native_import',source='https://assets.fiba.basketball/image/upload/documents-corporate-fiba-official-rules-2026-v1-1.pdf',reference='FIBA Official Basketball Rules2026 v1.1 Article2; scene court28x15m retained. No competition certification implied.',features=sorted(set(labels)),line_width_cm=5,source_strip_polygons=len(polys),nonoverlapping_convex_fragments=len(pieces),triangles=len(mesh.loop_triangles),path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),policy='Add missing markings only. Original outer boundary/centre line and both existing backboards/rims remain. Planar subtraction removes intersections within the new paint mesh; new paint is offset from blue rubber and older paint.');(O/'build.json').write_text(json.dumps(receipt,indent=2),'utf8');print('COURT PAINT',receipt['triangles'],'triangles;',len(pieces),'nonoverlapping pieces')
]====]
local payload=out..'/build-payload.json';local f=assert(io.open(payload,'wb'));f:write(j.encode({out=out,code=code}));f:close();local expression="import json;TASK=json.load(open('"..payload.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'));print('Basketball court marking geometry built; native import, depth scan and Game review required.')
