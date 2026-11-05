local code=[====[
import json,struct
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'flat-campus-v1';S=B/'day-night-v1/surface-final'
def read(p):return json.loads(Path(p).read_text(encoding='utf8'))
s=read(S/'scene.json');r=next(r for r in s['instances'] if r['actor']=='World_PK_0112');asset=s['meshes'][r['mesh']];installed=read(O/'install.json');live=next(q for q in read(O/'preservation.json')['after'] if q['actor']==r['actor']);assert live['mesh'].endswith('SM_PK0112_LevelPaving.SM_PK0112_LevelPaving');prior=read(O/'PK0112-grade-plan.json');mat=np.array(r['matrix']).reshape(4,4);mat[3,:3]=live['transform']['translation'];inv=np.linalg.inv(mat);lods=[]
for l in asset['lods']:
 raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();indices=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);w=np.c_[xyz,np.ones(nv)]@mat;tri=w[indices,:3];normal=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);area=np.linalg.norm(normal,axis=1)/2;stone=np.isin(slots,[1,5]);floor=stone&(tri[:,:,2].max(axis=1)<1230)&(tri[:,:,2].min(axis=1)>1150)&(np.abs(normal[:,2])/(2*area+1e-8)>.97)&(area>1);f=tri[floor];assert len(f)>0
 # The support field comes from the existing paving, including the lower winding paths.
 centers=f.mean(axis=1);dist=((w[:,:2,None]-centers[:,:2].T[None,:,:])**2).sum(axis=1);ref=centers[np.argmin(dist,axis=1),2];supported=np.zeros(nv,bool)
 for t in f:
  a,b,c=t;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);u=((b[1]-c[1])*(w[:,0]-c[0])+(c[0]-b[0])*(w[:,1]-c[1]))/den;v=((c[1]-a[1])*(w[:,0]-c[0])+(a[0]-c[0])*(w[:,1]-c[1]))/den;hit=(u>=-1e-5)&(v>=-1e-5)&(u+v<=1.00001);z=u*a[2]+v*b[2]+(1-u-v)*c[2];use=hit&(~supported|(z>ref));ref[use]=z[use];supported|=hit
 old=w[:,2].copy();w[:,2]+=1202-ref
 # Highest geometric face determines the exposed surface, regardless of winding.
 fi=np.flatnonzero(floor);fc=tri[floor].mean(axis=1);highest=np.full(len(fc),-np.inf)
 for t in f:
  a,b,c=t;den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);u=((b[1]-c[1])*(fc[:,0]-c[0])+(c[0]-b[0])*(fc[:,1]-c[1]))/den;v=((c[1]-a[1])*(fc[:,0]-c[0])+(a[0]-c[0])*(fc[:,1]-c[1]))/den;hit=(u>=-1e-5)&(v>=-1e-5)&(u+v<=1.00001);z=u*a[2]+v*b[2]+(1-u-v)*c[2];highest[hit]=np.maximum(highest[hit],z[hit])
 topfi=fi[np.abs(fc[:,2]-highest)<.1];topverts=np.unique(indices[topfi]);w[topverts,2]=1202
 # Retain buried finite bottoms, rather than making a second face coplanar with grass.
 up=np.zeros(nv,bool);up[topverts]=True;stoneverts=np.zeros(nv,bool);stoneverts[np.unique(indices[stone&(tri[:,:,2].max(axis=1)<1230)])]=True;bottom=stoneverts&~up&(old<ref-.1);w[bottom,2]=np.minimum(w[bottom,2],1188)
 assert np.max(np.abs(w[topverts,2]-1202))<.05
 new=(w@inv)[:,:3].astype('<f4');dest=O/'vertices'/('PK0112-gradeV2-'+str(l['lod'])+'.bin');current=np.frombuffer(Path(next(x for x in prior['meshes'][0]['lods'] if x['lod']==l['lod'])['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3)[:,1,:];dest.write_bytes(np.stack([current,new],axis=1).tobytes());lods.append(dict(lod=l['lod'],vertices=str(dest),floor_triangles=int(floor.sum()),floor_area_m2=float(area[floor].sum()/10000)))
(O/'PK0112-grade-plan-beforeV2.json').write_text(json.dumps(prior,indent=2),encoding='utf8');(O/'PK0112-grade-plan.json').write_text(json.dumps(dict(map_sha256=installed['map_sha256'],meshes=[dict(key=r['key'],before=live['mesh'],after='/Game/UniversityCity/FlatCampusV1/Meshes/SM_PK0112_LevelPavingV2',lods=lods)]),indent=2),encoding='utf8');print('Prepared PK-0112 paving support-field flattening; floor and its furniture conform to 1202cm.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
