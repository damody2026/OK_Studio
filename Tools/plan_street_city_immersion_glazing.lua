-- Read-only glass-surface collision probes; no replacement materials or geometry.
local code=[====[
import json,struct,re,hashlib
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');ex=json.loads((O/'depth-export.json').read_text('utf8'));S=Path(ex['folder']);raw=(S/'scene.json').read_bytes();assert hashlib.sha256(raw).hexdigest()==ex['metadata_sha256'];scene=json.loads(raw);audit=json.loads((O/'audit.json').read_text('utf8'));start=json.loads((O/'walker-start-install.json').read_text('utf8'));assert audit['status']=='passed' and (ex['map_sha256']==audit['map_sha256'] or (ex['map_sha256']==start['before_map_sha256'] and audit['map_sha256']==start['map_sha256']));rows=[];floors=set();glass_floors=set()
for r in scene['instances']:
 if not re.fullmatch(r'Campus_[A-Z0-9]+_F\d\d',r['actor']):continue
 floors.add(r['actor']);glass=[i for i,p in enumerate(r['materials']) if 'campus_glass' in str(p).lower()]
 if not glass:continue
 m=scene['meshes'][r['mesh']];b=(S/m['lods'][0]['file']).read_bytes();version,nv,nt=struct.unpack_from('<III',b);assert version==0x43445932;v=np.frombuffer(b,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);tri=np.frombuffer(b,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(b,dtype='<u4',count=nt,offset=12+nv*12+nt*16);sel=np.flatnonzero(np.isin(slots,glass));w=(np.c_[v,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];p=w[tri[sel]];normal=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);area=np.linalg.norm(normal,axis=1);normal/=np.maximum(area[:,None],1.e-12);chosen=(area>2000)&(np.abs(normal[:,2])<.02)
 for index,n,points in zip(sel[chosen],normal[chosen],p[chosen]):
  center=points.mean(0)
  for sign in [-1,1]:rows.append(dict(id='glazing-%05d'%len(rows),actor=r['actor'],component=r['component'],mesh=m['asset'],triangle=int(index),material_slot=int(slots[index]),target_cm=center.tolist(),start_cm=(center+n*sign*50).tolist(),end_cm=(center-n*sign*50).tolist()))
 if chosen.any():glass_floors.add(r['actor'])
assert len(floors)==89 and len(glass_floors)==89 and rows
plan=dict(status='prepared_requires_native_blocking_queries',map_sha256=audit['map_sha256'],geometry_export_map_sha256=ex['map_sha256'],source_metadata_sha256=ex['metadata_sha256'],floors=len(floors),glass_floors=len(glass_floors),rows=rows,scope='Both-direction queries cross the50cm window neighborhood around every LOD0 Campus_glass triangle over0.1m2 on89 floors. Require the same school-floor component to provide a blocking glass/frame/wall surface inside that finite segment. Record its actual impact;do not claim every isolated pane backface is independently collidable. Complex and simple shape impacts must agree within1cm,and cooked ECC_Pawn replay must hit that same observed point.');(O/'glazing-plan.json').write_text(json.dumps(plan,indent=2),encoding='utf8');print('Prepared',len(rows),'two-direction window-barrier probes across',len(glass_floors),'floors')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
