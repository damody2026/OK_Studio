local code=[====[
import json,struct,numpy as np
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/traffic-v1');S=O/'surface-current'
def read(p):return json.loads(p.read_text(encoding='utf8'))
s=read(S/'scene.json');receipt=read(O/'surface-current-receipt.json');meshes=[]
for r in s['instances']:
 if not(len(r['actor'])==3 and r['actor'].startswith('G') and r['actor'][1:].isdigit()):continue
 a=s['meshes'][r['mesh']];mat=np.array(r['matrix']).reshape(4,4);inv=np.linalg.inv(mat);lods=[]
 for l in a['lods']:
  raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();idx=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);w=np.c_[xyz,np.ones(nv)]@mat;t=w[idx,:3];mask=np.isin(slots,[4,5,6])&(t[:,:,2].min(1)>1000)&(t[:,:,2].max(1)<1300);v=np.unique(idx[mask]);w[v,2]=1205;new=(w@inv)[:,:3].astype('<f4');file=O/('road-final-'+r['actor']+'-'+str(l['lod'])+'.bin');file.write_bytes(np.stack([xyz,new],axis=1).tobytes());lods.append(dict(lod=l['lod'],vertices=str(file),road_vertices=len(v),road_triangles=int(mask.sum()),resolved_road_slots=[4,5,6]))
 meshes.append(dict(key=r['key'],before=a['asset'],after='/Game/UniversityCity/TrafficV1/RoadFinal2/Meshes/SM_Road_'+r['actor'],lods=lods))
assert len(meshes)==16
(O/'road-final-plan.json').write_text(json.dumps(dict(map_sha256=receipt['map_sha256'],meshes=meshes,road_top_cm=1205,source='Fresh native export with corrected material slot resolution'),indent=2),encoding='utf8');print('Fresh native geometry final road plan:',len(meshes),'chunks')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
