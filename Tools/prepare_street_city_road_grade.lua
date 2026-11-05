-- Keep authored ground road faces above lawn after removing original terrain relief.
local code=[====[
import json,struct,numpy as np
from pathlib import Path
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');F=B/'flat-campus-v1';O=B/'traffic-v1';S=B/'day-night-v1/surface-final'
def read(p):return json.loads(p.read_text(encoding='utf8'))
scene=read(S/'scene.json');current={(r['actor'],r['component']):r for r in read(F/'preservation.json')['after']};initial={r['key']:r for r in read(F/'plan.json')['meshes']};graded={r['key']:r for r in read(F/'grade-plan.json')['meshes']};meshes=[]
for r in scene['instances']:
 if not (r['actor'].startswith('G') and r['actor'][1:].isdigit() and len(r['actor'])==3):continue
 a=scene['meshes'][r['mesh']];live=current[(r['actor'],r['component'])];prior=graded.get(r['key'],initial.get(r['key']));assert prior;mat=np.array(r['matrix']).reshape(4,4);mat[3,:3]=live['transform']['translation'];inv=np.linalg.inv(mat);lods=[];changes=0
 for l in a['lods']:
  previous=next(q for q in prior['lods'] if q['lod']==l['lod']);xyz=np.frombuffer(Path(previous['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3)[:,1,:].copy();raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);assert len(xyz)==nv;idx=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);w=np.c_[xyz,np.ones(nv)]@mat;tri=w[idx,:3];mask=np.isin(slots,[4,5,6])&(tri[:,:,2].max(1)>1100)&(tri[:,:,2].min(1)>1000)&(tri[:,:,2].max(1)<1300);v=np.unique(idx[mask]);assert len(v)>0;changes+=int((np.abs(w[v,2]-1200.75)>.01).sum());w[v,2]=1200.75;new=(w@inv)[:,:3].astype('<f4');dest=O/('road-grade-'+r['actor']+'-'+str(l['lod'])+'.bin');dest.write_bytes(np.stack([xyz,new],axis=1).tobytes());lods.append(dict(lod=l['lod'],vertices=str(dest),road_vertices=len(v),road_triangles=int(mask.sum())))
 meshes.append(dict(key=r['key'],before=live['mesh'],after='/Game/UniversityCity/TrafficV1/Repair2/Meshes/SM_RoadLevel_'+r['actor'],lods=lods,changed_vertices=changes))
(O/'road-grade-plan.json').write_text(json.dumps(dict(map_sha256=read(F/'install.json')['map_sha256'],meshes=meshes,road_top_cm=1200.75,grass_top_cm=1198),indent=2),encoding='utf8');print('Road grade plan',len(meshes),'terrain chunks;',sum(r['changed_vertices'] for r in meshes),'road vertices; top1200.75 lawn1198cm')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
