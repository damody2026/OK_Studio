-- Read-only material/geometry inventory for confirmed ground overlap candidates.
local code=[====[
import json,struct,collections
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');e=json.loads((O/'depth-export.json').read_text());S=Path(e['folder']);scene=json.loads((S/'scene.json').read_text());snap=json.loads((O/'preservation-after.json').read_text());lookup={r['actor']+'::'+r['component']:r for r in snap['components']};rows=[]
for r in scene['instances']:
 if r['actor'] not in ['G02','G06','G10','G11','G15','Campus_SP_F02','Campus_SP_F03','Campus_SP_Water','Campus_SP_F01']:continue
 m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);world=np.c_[xyz,np.ones(nv)]@np.array(r['matrix']).reshape(4,4);tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);q=dict(actor=r['actor'],key=r['key'],mesh=m['asset'],slots=[]);state=lookup[r['key']]
 print(r['actor'],m['asset'])
 for slot in sorted(set(slots)):
  vi=np.unique(tri[slots==slot]);p=world[vi,:3];zs=collections.Counter(np.round(p[:,2],3));mat=state['materials'][int(slot)] if int(slot)<len(state['materials']) else 'missing';item=dict(slot=int(slot),material=mat,vertices=len(vi),triangles=int((slots==slot).sum()),bounds_min=p.min(0).tolist(),bounds_max=p.max(0).tolist(),z_levels=zs.most_common(8));q['slots'].append(item);print(int(slot),mat.split('/')[-1],item['triangles'],'bounds',np.round(p.min(0),2).tolist(),np.round(p.max(0),2).tolist(),'z',zs.most_common(4))
 rows.append(q)
(O/'ground-depth-inspection.json').write_text(json.dumps(dict(map_sha256=e['map_sha256'],rows=rows),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
