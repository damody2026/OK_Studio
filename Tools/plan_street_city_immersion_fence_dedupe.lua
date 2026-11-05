-- Find duplicated complete rendered fence solids,not merely adjacent end faces.
local code=[====[
import json,hashlib,struct,collections
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');ex=json.loads((O/'depth-export.json').read_text('utf8'));S=Path(ex['folder']);raw=(S/'scene.json').read_bytes();assert hashlib.sha256(raw).hexdigest()==ex['metadata_sha256'];scene=json.loads(raw);snapshot=json.loads((O/'preservation-after.json').read_text('utf8'));assert snapshot['map_sha256']==ex['map_sha256'];lookup={(r['actor'],r['component']):r for r in snapshot['components']};cache={};groups={}
for r in scene['instances']:
 if r['actor'] not in ['FlatCampus_Fence_Stone','FlatCampus_Fence_Cap']:continue
 m=scene['meshes'][r['mesh']]
 if r['mesh'] not in cache:
  b=(S/m['lods'][0]['file']).read_bytes();version,nv,nt=struct.unpack_from('<III',b);assert version==0x43445932,(version,nv,nt,m['asset']);cache[r['mesh']]=np.frombuffer(b,dtype='<f4',count=nv*3,offset=12).reshape(-1,3)
 v=cache[r['mesh']];w=(np.c_[v,np.ones(len(v))]@np.array(r['matrix']).reshape(4,4))[:,:3];points=np.unique(np.round(w,3),axis=0);assert len(points)>=8;signature=hashlib.sha256(points.astype('<f8').tobytes()).hexdigest();key=(r['actor'],r['component'],m['asset'],tuple(r['materials']),signature);groups.setdefault(key,[]).append(r['instance'])
rows=[]
for key,indices in groups.items():
 if len(indices)<2:continue
 indices.sort();state=lookup[(key[0],key[1])];assert state['mesh']==key[2] and state['materials']==list(key[3]);rows.append(dict(actor=key[0],component=key[1],mesh=key[2],render_vertex_signature=key[4],kept_instance=indices[0],removed_instances=indices[1:],source_transforms={str(i):state['instances'][i] for i in indices}))
removed=sum(len(r['removed_instances']) for r in rows);assert removed==16 and len(rows)==16,(removed,len(rows));plan=dict(status='prepared_requires_native_install',map_sha256=ex['map_sha256'],source_metadata_sha256=ex['metadata_sha256'],groups=rows,duplicate_solids=removed,scope='16 complete opaque fence mesh instances duplicate every rendered vertex with matching source mesh/materials;source meshes may contain multiple primitive pieces. Keep one per group;retained transforms/materials must remain identical. Adjacent nonduplicated fence faces are not removed. Fresh exact-triangle scan is required afterward.');(O/'fence-dedupe-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared removal of',removed,'duplicate complete fence solids across',len(rows),'groups')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
