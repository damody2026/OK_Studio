-- Read rendered geometry to locate large outdoor walking sheets for native probes.
local code=[====[
import json,struct,collections
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');ex=json.loads((O/'depth-export.json').read_text('utf8'));S=Path(ex['folder']);scene=json.loads((S/'scene.json').read_text('utf8'));rows=[]
for r in scene['instances']:
 if not r['actor'].startswith('Outdoor_'):continue
 m=scene['meshes'][r['mesh']];b=(S/m['lods'][0]['file']).read_bytes();version,nv,nt=struct.unpack_from('<III',b);assert version==0x43445932;v=np.frombuffer(b,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);tri=np.frombuffer(b,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);w=(np.c_[v,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];p=w[tri];n=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);area=np.linalg.norm(n,axis=1)/2;sel=np.flatnonzero((area>10000)&(n[:,2]>.9*np.linalg.norm(n,axis=1)));levels=collections.defaultdict(float)
 for i in sel:levels[round(float(p[i,:,2].mean()),1)]+=float(area[i])/10000
 chosen=sorted(sel,key=lambda i:area[i],reverse=True)[:8];row=dict(actor=r['actor'],component=r['component'],mesh=r['mesh'],largest_horizontal_levels=[dict(z_cm=z,area_m2=a) for z,a in sorted(levels.items(),key=lambda q:q[1],reverse=True)[:8]],samples=[dict(point_cm=p[i].mean(0).tolist(),area_m2=float(area[i])/10000) for i in chosen]);rows.append(row);print(row['actor'],row['largest_horizontal_levels'][:4])
(O/'outdoor-level-context.json').write_text(json.dumps(dict(status='geometry_candidates_require_native_support_probe',geometry_map_sha256=ex['map_sha256'],rows=rows),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
