local code=[====[
import json,struct,numpy as np
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');ex=json.loads((O/'depth-export.json').read_text());S=O/('depth-outdoor-ground-'+ex['map_sha256'][:12]);sc=json.loads((S/'scene.json').read_text());pairs=[]
for line in (O/('depth-outdoor-ground-'+ex['map_sha256'][:12])/'depth-report.conflicts.jsonl').open():
 q=json.loads(line)
 if q['pass_lod']!=0 or q['a_actor']!='Immersion_Water_Metal' or q['b_actor']!='Immersion_CampusPaths':continue
 key=(q['a_instance'],q['b_instance'])
 if key in [(r['a_index'],r['b_index']) for r in pairs]:continue
 bounds=[]
 for i in key:
  r=sc['instances'][i];m=sc['meshes'][r['mesh']];b=(S/m['lods'][0]['file']).read_bytes();nv=struct.unpack_from('<I',b,4)[0];v=np.frombuffer(b,dtype='<f4',offset=12,count=nv*3).reshape(-1,3);w=(np.c_[v,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];bounds.append(dict(actor=r['actor'],min=w.min(0).tolist(),max=w.max(0).tolist()))
 print(key,bounds);pairs.append(dict(a_index=key[0],b_index=key[1],bounds=bounds,candidate=q))
(O/'water-path-contact-geometry.json').write_text(json.dumps(dict(status='requires_geometric_classification',map_sha256=ex['map_sha256'],pairs=pairs),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
