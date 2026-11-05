local code=[====[
import json,struct
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'flat-campus-v1';S=B/'day-night-v1/surface-final'
def read(p):return json.loads(Path(p).read_text(encoding='utf8'))
scene=read(S/'scene.json');plan=read(O/'grade-plan.json');installed=read(O/'install.json');assert installed.get('exterior_ground_grade_cm')==1198;points=[]
for b in read(B/'world-ground-v1/campus-foundations.json')['buildings']:
 if b['id'] not in ('E1','EE','MA','T4','T2','IB','T1','RB','AD','LI','SC','IN','SP','D1','D2','D3','D4'):continue
 cx,cy,_=b['world_position_m']
 for e in b['entrances']:
  ex,ey,_=e['position_m'];dx,dy={'W':(-1,0),'E':(1,0),'S':(0,-1),'N':(0,1)}[e['facade_side']]
  for d in (5.,7.):points.append(dict(building=b['id'],entry=e['id'],distance_m=d,x=(cy+ey+dy*d)*100,y=(cx+ex+dx*d)*100,hits=[]))
for m in plan['meshes']:
 r=next(r for r in scene['instances'] if r['key']==m['key']);asset=scene['meshes'][r['mesh']];l=next(l for l in m['lods'] if l['lod']==0);xyz=np.frombuffer(Path(l['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3)[:,1,:];w=np.c_[xyz,np.ones(len(xyz))]@np.array(r['matrix']).reshape(4,4);source=next(l for l in asset['lods'] if l['lod']==0);raw=(S/source['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);indices=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);tri=w[indices,:3];a,b,c=tri[:,0],tri[:,1],tri[:,2];den=(b[:,1]-c[:,1])*(a[:,0]-c[:,0])+(c[:,0]-b[:,0])*(a[:,1]-c[:,1]);valid=abs(den)>1e-6;den=np.where(valid,den,1)
 for p in points:
  if not(r['min'][0]-.01<=p['x']<=r['max'][0]+.01 and r['min'][1]-.01<=p['y']<=r['max'][1]+.01):continue
  u=((b[:,1]-c[:,1])*(p['x']-c[:,0])+(c[:,0]-b[:,0])*(p['y']-c[:,1]))/den;v=((c[:,1]-a[:,1])*(p['x']-c[:,0])+(a[:,0]-c[:,0])*(p['y']-c[:,1]))/den;z=u*a[:,2]+v*b[:,2]+(1-u-v)*c[:,2];hit=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(z>=1150)&(z<=1220)
  if hit.any():p['hits'].append(float(z[hit].max()))
current={(r['actor'],r['component']):r for r in read(O/'preservation.json')['after']}
# Existing first-floor plates can cover the terrain foundation recess, including
# later-expanded wings that extend beyond the earlier entrance programme.
for r in scene['instances']:
 if not(r['actor'].startswith('Campus_') and r['actor'].endswith('_F01')):continue
 asset=scene['meshes'][r['mesh']];live=current[(r['actor'],r['component'])];assert live['mesh']==asset['asset'];l=next(l for l in asset['lods'] if l['lod']==0);raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);mat=np.array(r['matrix']).reshape(4,4);mat[3,:3]=live['transform']['translation'];w=np.c_[xyz,np.ones(nv)]@mat;indices=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);tri=w[indices,:3];a,b,c=tri[:,0],tri[:,1],tri[:,2];den=(b[:,1]-c[:,1])*(a[:,0]-c[:,0])+(c[:,0]-b[:,0])*(a[:,1]-c[:,1]);valid=abs(den)>1e-6;den=np.where(valid,den,1)
 for p in points:
  if not(r['min'][0]-.01<=p['x']<=r['max'][0]+.01 and r['min'][1]-.01<=p['y']<=r['max'][1]+.01):continue
  u=((b[:,1]-c[:,1])*(p['x']-c[:,0])+(c[:,0]-b[:,0])*(p['y']-c[:,1]))/den;v=((c[:,1]-a[:,1])*(p['x']-c[:,0])+(a[:,0]-c[:,0])*(p['y']-c[:,1]))/den;z=u*a[:,2]+v*b[:,2]+(1-u-v)*c[:,2];hit=valid&(u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(z>=1150)&(z<=1220)
  if hit.any():p['hits'].append(float(z[hit].max()))
for p in points:
 assert p['hits'],p;p['height_cm']=max(p.pop('hits'));assert 1190<=p['height_cm']<=1210,p
result=dict(status='passed',map_sha256=installed['map_sha256'],samples=len(points),min_height_cm=min(p['height_cm'] for p in points),max_height_cm=max(p['height_cm'] for p in points),points=points,scope='Independent vertical triangle intersections on actual grade-plan LOD0 positions and unchanged campus first-floor plates, 5m and 7m beyond each entrance programme anchor; not a Game movement test.')
(O/'exterior-geometry-check.json').write_text(json.dumps(result,indent=2),encoding='utf8');print('Exterior terrain support:',len(points),'samples,',result['min_height_cm'],result['max_height_cm'],'cm')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
