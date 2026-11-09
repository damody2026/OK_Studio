local code=[====[
import json,struct
from pathlib import Path
from collections import defaultdict
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');S=B/'traffic-v1/surface-current';scene=json.loads((S/'scene.json').read_text('utf8'));r=next(r for r in scene['instances'] if r['actor']=='World_PK_0105');m=scene['meshes'][r['mesh']];lod=m['lods'][0];raw=(S/lod['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);v=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);v=(np.c_[v,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);points=v[tri];cross=np.cross(points[:,1]-points[:,0],points[:,2]-points[:,0]);area=np.linalg.norm(cross,axis=1)/2;normal=cross/np.maximum(area[:,None]*2,1e-8);rows=[]
for slot in np.unique(slots):
 hit=slots==slot;xy=points[hit].reshape(-1,3);flat=hit&(np.ptp(points[:,:,2],axis=1)<.1)&(normal[:,2]>.9)&(area>10);levels=defaultdict(float)
 for z,a in zip(points[flat,:,2].mean(axis=1),area[flat]):levels[round(float(z),1)]+=float(a)
 row=dict(slot=int(slot),material=r['materials'][slot],min_cm=xy.min(axis=0).tolist(),max_cm=xy.max(axis=0).tolist(),horizontal_top_areas_cm2=sorted(levels.items(),key=lambda q:-q[1])[:10]);rows.append(row);print(slot,row['material'].split('/')[-1],row['min_cm'],row['max_cm'],row['horizontal_top_areas_cm2'])
parent={}
def find(a):
 parent.setdefault(a,a)
 while parent[a]!=a:parent[a]=parent[parent[a]];a=parent[a]
 return a
keys=[tuple(np.rint(p*2).astype(int)) for p in v]
for t,s in zip(tri,slots):
 if s not in [1,5]:continue
 a,b,c=[keys[i] for i in t];ra=find(a)
 for k in [b,c]:parent[find(k)]=ra
groups={}
for index,(t,s) in enumerate(zip(tri,slots)):
 if s not in [1,5]:continue
 groups.setdefault(find(keys[t[0]]),[]).append(index)
parts=[]
for faceids in groups.values():
 vi=np.unique(tri[faceids]);xyz=v[vi];lo=xyz.min(axis=0);hi=xyz.max(axis=0);row=dict(id=len(parts),triangles=len(faceids),min_cm=lo.tolist(),max_cm=hi.tolist(),vertex_indices=vi.tolist(),slots=sorted(set(int(slots[i]) for i in faceids)));parts.append(row);print('PAVING PART',row['id'],len(faceids),lo.round(1).tolist(),hi.round(1).tolist())
(B/'immersion-v1/water-deck-geometry.json').write_text(json.dumps(dict(status='diagnostic_only',source_export='traffic-v1/surface-current',actor=r['actor'],mesh=m['asset'],rows=rows,paving_parts=parts),indent=2),'utf8')
]====]
if arg[1]then
 assert(arg[1]:match('^World_PK_%d%d%d%d$'),'Expected one outdoor actor label')
 code=code:gsub('World_PK_0105',arg[1]):gsub('water%-deck%-geometry.json','water-platform-'..arg[1]:sub(-4)..'-geometry.json')
end
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
