local code=[====[
import json,struct
from pathlib import Path
from collections import defaultdict
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');S=B/'traffic-v1/surface-current';O=B/'immersion-v1';scene=json.loads((S/'scene.json').read_text('utf8'));r=next(q for q in scene['instances'] if q['actor']=='Outdoor_campus_track');m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);local=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);v=(np.c_[local,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);p=v[tri];cross=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);area=np.linalg.norm(cross,axis=1)/2;rows=[]
for slot in np.unique(slots):
 hit=slots==slot;xyz=p[hit].reshape(-1,3);horizontal=hit&(np.ptp(p[:,:,2],axis=1)<.02)&(area>1);levels=defaultdict(float)
 for z,a in zip(p[horizontal,:,2].mean(axis=1),area[horizontal]):levels[round(float(z),4)]+=float(a)
 row=dict(slot=int(slot),material=r['materials'][slot],vertices=len(np.unique(tri[hit])),triangles=int(hit.sum()),min_cm=xyz.min(axis=0).tolist(),max_cm=xyz.max(axis=0).tolist(),levels_cm=sorted(levels.items(),key=lambda t:-t[1])[:20]);rows.append(row);print(slot,row['material'].split('/')[-1],row['vertices'],row['triangles'],np.round(row['min_cm'],3),np.round(row['max_cm'],3),row['levels_cm'][:7])
(O/'track-geometry-review.json').write_text(json.dumps(dict(status='diagnostic_requires_review',actor=r['actor'],mesh=m['asset'],rows=rows),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
