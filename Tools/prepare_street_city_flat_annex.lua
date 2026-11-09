local code=[====[
import json,hashlib,struct
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'flat-campus-v1';S=B/'day-night-v1/surface-final'
def read(p):return json.loads(Path(p).read_text(encoding='utf8'))
p=read(O/'plan.json');i=read(O/'install.json');s=read(S/'scene.json');m=next(m for m in p['meshes'] if m['key']=='Outdoor_annex_ground::StaticMeshComponent0');current=next(q for q in i['meshes'] if q['key']==m['key']);r=next(r for r in s['instances'] if r['key']==m['key']);mat=np.array(r['matrix']).reshape(4,4);inv=np.linalg.inv(mat);lods=[]
asset=s['meshes'][r['mesh']]
for l in m['lods']:
 xyz=np.frombuffer(Path(l['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3)[:,1,:].copy();w=np.c_[xyz,np.ones(len(xyz))]@mat;source=next(q for q in asset['lods'] if q['lod']==l['lod']);raw=(S/source['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);indices=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);tri=w[indices,:3];normal=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0]);up=np.zeros(nv,bool);down=np.zeros(nv,bool);up[np.unique(indices[normal[:,2]>1e-5])]=True;down[np.unique(indices[normal[:,2]<-1e-5])]=True
 _,inverse=np.unique(np.round(w[:,:2],3),axis=0,return_inverse=True);tops=np.full(inverse.max()+1,-np.inf);np.maximum.at(tops,inverse,w[:,2]);z=np.where(w[:,2]>=tops[inverse]-1e-4,1198.,1188.);z[down]=1188.;z[up]=1198.;w[:,2]=z
 new=(w@inv)[:,:3].astype('<f4');dest=O/'vertices'/('annex-level-'+str(l['lod'])+'.bin');dest.write_bytes(np.stack([xyz,new],axis=1).tobytes());lods.append(dict(lod=l['lod'],vertices=str(dest),top_cm=1198,bottom_cm=1188))
(O/'annex-plan.json').write_text(json.dumps(dict(map_sha256=i['map_sha256'],meshes=[dict(key=m['key'],before=current['after'],after='/Game/UniversityCity/FlatCampusV1/Meshes/SM_Annex_Level1198',lods=lods)]),indent=2),encoding='utf8');print('Prepared flat annex terrain at 1198cm.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
