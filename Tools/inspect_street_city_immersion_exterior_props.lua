-- Offline geometry identification only; no native map or asset mutation.
local code=[====[
import json,struct
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');ex=json.loads((O/'depth-export.json').read_text('utf8'));S=Path(ex['folder']);scene=json.loads((S/'scene.json').read_text('utf8'));cache={};rows=[];limits=[__BOUNDS__]
for r in scene['instances']:
 if not r['actor'].startswith(('Activity_','Outdoor_','Resort_','World_PK_')):continue
 key=r['mesh']
 if key not in cache:
  m=scene['meshes'][key];b=(S/m['lods'][0]['file']).read_bytes();version,nv,nt=struct.unpack_from('<III',b);assert version==0x43445932;v=np.frombuffer(b,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);lo,hi=v.min(0),v.max(0);cache[key]=(np.array([[x,y,z,1] for x in [lo[0],hi[0]] for y in [lo[1],hi[1]] for z in [lo[2],hi[2]]]),nt)
 c,nt=cache[key];w=(c@np.array(r['matrix']).reshape(4,4))[:,:3];lo,hi=w.min(0),w.max(0)
 if hi[0]<limits[0] or lo[0]>limits[1] or hi[1]<limits[2] or lo[1]>limits[3] or lo[2]>1600 or hi[2]<1180:continue
 rows.append(dict(actor=r['actor'],component=r.get('component',r.get('key')),mesh=key,min_cm=lo.tolist(),max_cm=hi.tolist(),triangles=nt,materials=[str(p).split('/')[-1] for p in r['materials']]))
(O/('exterior-prop-context-'+str(int(limits[0]))+'-'+str(int(limits[2]))+'.json')).write_text(json.dumps(dict(status='read_only_geometry_context_requires_native_identification',geometry_map_sha256=ex['map_sha256'],bounds_cm=limits+[1180,1600],rows=rows),indent=2),'utf8')
print('Context rows:',len(rows))
for r in rows:print(r['actor'],r['component'],[round(x,1) for x in r['min_cm']],[round(x,1) for x in r['max_cm']],r['materials'][:5])
]====]
local bounds={};for i,v in ipairs({77000,83500,40000,43000})do bounds[i]=tostring(arg[i] and assert(tonumber(arg[i])) or v)end
code=code:gsub('__BOUNDS__',table.concat(bounds,','));local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
