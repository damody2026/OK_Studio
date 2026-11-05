local code=[====[
import json,hashlib
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'flat-campus-v1';S=B/'day-night-v1/surface-final'
def read(p):return json.loads(Path(p).read_text(encoding='utf8'))
scene=read(S/'scene.json');plan=read(O/'plan.json');installed=read(O/'install.json');current={m['key']:m for m in installed['meshes']};archive=np.load(B/'world-ground-v1/world-field.npz');water=archive['water_map'];rows=[];footprints=[]
for r in scene['instances']:
 if r['instance']==-1 and r['actor'].endswith('_F01') and (r['actor'].startswith(('Campus_','City_','Mall_','S'))):footprints.append((r['min'][:2],r['max'][:2]))
for m in plan['meshes']:
 if m['category']!='terrain':continue
 r=next(r for r in scene['instances'] if r['key']==m['key']);mat=np.array(r['matrix']).reshape(4,4);inv=np.linalg.inv(mat);lods=[];changed=0
 for l in m['lods']:
  pairs=np.frombuffer(Path(l['vertices']).read_bytes(),dtype='<f4').reshape(-1,2,3);xyz=pairs[:,1,:].copy();w=np.c_[xyz,np.ones(len(xyz))]@mat
  inside=np.zeros(len(xyz),dtype=bool)
  for lo,hi in footprints:inside|=(w[:,0]>=lo[0]-.01)&(w[:,0]<=hi[0]+.01)&(w[:,1]>=lo[1]-.01)&(w[:,1]<=hi[1]+.01)
  east=np.clip(np.rint(w[:,1]/100).astype(int),0,1100);south=np.clip(np.rint(1100-w[:,0]/100).astype(int),0,1100);land=(water[south,east]==0)&(w[:,2]>-2900)&~inside
  # Only fill residual earth depressions outside structures. Existing pavement tops and finite slab thickness stay intact.
  fill=land&(w[:,2]<1198);changed+=int(fill.sum());w[fill,2]=1198
  new=(w@inv)[:,:3].astype('<f4');path=O/'vertices'/('grade-'+r['actor']+'-'+str(l['lod'])+'.bin');path.write_bytes(np.stack([xyz,new],axis=1).tobytes());lods.append(dict(lod=l['lod'],vertices=str(path)))
 name='SM_LevelGrade_'+r['actor']+'_'+hashlib.sha256(installed['map_sha256'].encode()).hexdigest()[:10];rows.append(dict(key=m['key'],before=current[m['key']]['after'],after='/Game/UniversityCity/FlatCampusV1/Meshes/'+name,lods=lods,filled_vertices=changed))
assert len(rows)==16;(O/'grade-plan.json').write_text(json.dumps(dict(map_sha256=installed['map_sha256'],meshes=rows,footprints=len(footprints),filled_vertices=sum(r['filled_vertices'] for r in rows)),indent=2),encoding='utf8');print('Prepared residual depression fill:',sum(r['filled_vertices'] for r in rows),'vertices,',len(footprints),'preserved building footprints.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
