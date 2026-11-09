-- Read-only semantic and mesh context for measured capsule obstructions.
local code=[====[
import sys,json,struct,collections
from pathlib import Path
import numpy as np
R=Path('C:/portable/OpenKoikatsu');O=R/'output/street-social-city-production/immersion-v1';sys.path.insert(0,str(R/'Tools'));from street_city_campus_contract import context
probe=json.loads((O/'door-capsule-probe.json').read_text());source=json.loads((O/'depth-export.json').read_text());assert source['map_sha256']==probe['map_sha256'];S=Path(source['folder']);scene=json.loads((S/'scene.json').read_text());activity=json.loads((R/'output/street-social-city-production/activity-scenes-v1/plan.json').read_text());ids={r['id']:r for r in activity['instances']};out=[]
for r in probe['issues']:
 actor=r['sweep']['actor']
 if actor.startswith('Activity_'):print(actor,ids.get(actor.removeprefix('Activity_')))
c=context('SP')
for q in c['instances']:
 if 'support-A3' in q['id'] or 'support-A3' in q['asset_id']:
  a=c['assets'][q['asset_id']];print('SP semantic',q['id'],q['asset_id'],a['name'],a['role'],q['position_m'],q['rotation_z_deg'],a.get('size_m'))
for r in scene['instances']:
 if r['actor'] not in ['Campus_SP_F01','Campus_SP_F02','Campus_SP_F03','Campus_SP_F04','Campus_SP_F05']:continue
 floor=int(r['actor'][-2:]);m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);world=(np.c_[xyz,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);issue=next(q for q in probe['issues'] if q['building']=='SP' and q['floor']==floor);z=issue['supports'][1]['expected_floor_cm'];low=np.array([75149.98,21329.98,z-.02]);high=np.array([75370.02,21550.02,z+240.02]);inside=np.all((world>=low)&(world<=high),axis=1);mask=np.all(inside[tri],axis=1);row=dict(actor=r['actor'],mesh=m['asset'],expected_fixture_bounds_cm=[low.tolist(),high.tolist()],slots=[])
 for slot in sorted(set(slots[mask])):
  indices=tri[mask&(slots==slot)];vi=np.unique(indices);p=world[vi];info=dict(slot=int(slot),material=r['materials'][int(slot)],triangles=len(indices),vertices=len(vi),bounds_cm=[p.min(0).tolist(),p.max(0).tolist()]);row['slots'].append(info);print(r['actor'],int(slot),info['material'].split('/')[-1],len(indices),'bounds',np.round(p.min(0),3).tolist(),np.round(p.max(0),3).tolist())
 out.append(row)
(O/'door-obstruction-geometry.json').write_text(json.dumps(dict(status='read_only_requires_layout_review',map_sha256=probe['map_sha256'],rows=out),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
