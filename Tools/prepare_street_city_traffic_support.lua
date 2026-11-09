local code=[====[
import json,struct,numpy as np,math
from pathlib import Path
from collections import defaultdict
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/traffic-v1');S=O/'surface-current'
def read(p):return json.loads(p.read_text(encoding='utf8'))
s=read(S/'scene.json');plan=read(O/'road-final-plan.json');new={m['key']:m for m in plan['meshes']};grid=defaultdict(list)
for r in s['instances']:
 if r['key'] not in new:continue
 a=s['meshes'][r['mesh']];l=a['lods'][0];raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);idx=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);xyz=np.frombuffer(Path(new[r['key']]['lods'][0]['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3)[:,1];w=np.c_[xyz,np.ones(nv)]@np.array(r['matrix']).reshape(4,4);t=w[idx,:3];a,b,c=t[:,0],t[:,1],t[:,2];den=(b[:,1]-c[:,1])*(a[:,0]-c[:,0])+(c[:,0]-b[:,0])*(a[:,1]-c[:,1]);valid=(np.abs(den)>.01)&(t[:,:,2].min(1)>1100)&(t[:,:,2].max(1)<1230);t=t[valid]
 for tri in t:
  lo=np.floor(tri[:,:2].min(0)/1000).astype(int);hi=np.floor(tri[:,:2].max(0)/1000).astype(int)
  for x in range(lo[0],hi[0]+1):
   for y in range(lo[1],hi[1]+1):grid[(x,y)].append(tri)
grid={k:np.array(v) for k,v in grid.items()};layout=read(O/'layout.json');points={}
for g in layout['groups'].values():
 for r in g['instances']:points[(round(r['center'][0]),round(r['center'][1]))]=r['center'][:2]
for r in layout['signs']:points[(round(r['center'][0]),round(r['center'][1]))]=r['center'][:2]
if (O/'lane-detail-plan.json').exists():
 for r in read(O/'lane-detail-plan.json')['parts']:points[(round(r['center'][0]),round(r['center'][1]))]=r['center'][:2]
support={};missing=[]
for key,p in points.items():
 t=grid.get((math.floor(p[0]/1000),math.floor(p[1]/1000)))
 if t is None:missing.append(p);continue
 a,b,c=t[:,0],t[:,1],t[:,2];den=(b[:,1]-c[:,1])*(a[:,0]-c[:,0])+(c[:,0]-b[:,0])*(a[:,1]-c[:,1]);u=((b[:,1]-c[:,1])*(p[0]-c[:,0])+(c[:,0]-b[:,0])*(p[1]-c[:,1]))/den;v=((c[:,1]-a[:,1])*(p[0]-c[:,0])+(a[:,0]-c[:,0])*(p[1]-c[:,1]))/den;hit=(u>=-1e-5)&(v>=-1e-5)&(u+v<=1.00001)
 if not hit.any():missing.append(p);continue
 z=u*a[:,2]+v*b[:,2]+(1-u-v)*c[:,2];support['%d,%d'%key]=float(z[hit].max())
(O/'geometry-support.json').write_text(json.dumps(dict(status='sampled',source_map_sha256=plan['map_sha256'],heights=support,missing=missing,scope='Independent triangle intersections of updated terrain; fallback only when native traces cannot hit reversed source faces.'),indent=2),encoding='utf8');print('Terrain support:',len(support),'points;',len(missing),'outside terrain triangles')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
