-- Supplement physics with visible render-triangle footprints, including NoCollision props.
local code=[====[
import json,struct,collections
from pathlib import Path
import numpy as np
def overlaps(p,x,y,radius):
 q=np.array([x,y]);edges=np.roll(p,-1,axis=0)-p;rel=q-p;cross=edges[:,0]*rel[:,1]-edges[:,1]*rel[:,0];a=p[1]-p[0];b=p[2]-p[0];area=abs(a[0]*b[1]-a[1]*b[0])
 if area>1.e-6 and ((cross>=-1.e-6).all() or (cross<=1.e-6).all()):return True
 projection=np.clip((rel*edges).sum(1)/np.maximum((edges*edges).sum(1),1.e-12),0,1);return bool((np.linalg.norm(p+projection[:,None]*edges-q,axis=1)<=radius).any())
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');exp=json.loads((O/'depth-export.json').read_text());S=Path(exp['folder']);scene=json.loads((S/'scene.json').read_text());snapshot=json.loads((O/'preservation-after.json').read_text());plan=json.loads((O/'fixture-placement-plan.json').read_text());assert exp['map_sha256']==snapshot['map_sha256']==plan['map_sha256'];visible={(r['actor'],r['component']) for r in snapshot['components'] if r['visible'] and not r['hidden'] and not r['actor_hidden']};cache={};rows=[]
targets=[dict(id=g['prefix'],xy=g['target']['xy_cm'],z=g['target']['ground_cm'],ignore=g['prefix']) for g in plan['groups']]+[dict(id='track-bench-'+str(y),xy=[66300,y],z=1198.,ignore='') for y in [28000,32000]]
for q in targets:
 x,y=q['xy'];z=q['z'];blocks=collections.Counter()
 for r in scene['instances']:
  if (r['actor'],r['component']) not in visible or q['ignore'] and r['actor'].startswith(q['ignore']):continue
  lo=np.array(r['min']);hi=np.array(r['max'])
  if hi[0]<x-45 or lo[0]>x+45 or hi[1]<y-45 or lo[1]>y+45 or hi[2]<z+10 or lo[2]>z+190:continue
  if r['mesh'] not in cache:
   m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);v=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);t=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);cache[r['mesh']]=(v,t)
  v,t=cache[r['mesh']];w=(np.c_[v,np.ones(len(v))]@np.array(r['matrix']).reshape(4,4))[:,:3];p=w[t];a=p.min(1);b=p.max(1);mask=(b[:,0]>=x-45)&(a[:,0]<=x+45)&(b[:,1]>=y-45)&(a[:,1]<=y+45)&(b[:,2]>=z+10)&(a[:,2]<=z+190)
  for triangle in p[mask]:
   if overlaps(triangle[:,:2],x,y,45):blocks[r['actor']]+=1
 row=dict(id=q['id'],xy_cm=q['xy'],ground_cm=z,render_footprint_intersections=dict(blocks),passed=not blocks);rows.append(row);print(q['id'],dict(blocks))
(O/'fixture-render-clearance.json').write_text(json.dumps(dict(status='passed' if all(r['passed'] for r in rows) else 'requires_layout_review',map_sha256=exp['map_sha256'],rows=rows,scope='Conservative visible LOD0 triangle XY footprints within45cm of proposed fixture/bench centers, limited to10..190cm above ground; includes NoCollision props. Supplementary placement screen, not a replacement for native player sweeps.'),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
