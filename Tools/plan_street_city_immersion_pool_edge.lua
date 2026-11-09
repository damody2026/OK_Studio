-- One-centimetre water-sheet clearance from coplanar basin walls; no water elevation or UV change.
local code=[====[
import json,struct,hashlib
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');exp=json.loads((O/'depth-export.json').read_text());S=Path(exp['folder']);scene=json.loads((S/'scene.json').read_text());snap=json.loads((O/'preservation-after.json').read_text());r=next(q for q in scene['instances'] if q['actor']=='Campus_SP_Water');state=next(q for q in snap['components'] if q['actor']=='Campus_SP_Water');m=scene['meshes'][r['mesh']];assert m['asset']==state['mesh'] and state['collision']=='NoCollision';matrix=np.array(r['matrix']).reshape(4,4);assert np.allclose(matrix[3,:3],state['transform']['translation'],atol=.002);folder=O/'pool-edge';folder.mkdir(exist_ok=True);lods=[];changes=[]
for l in m['lods']:
 raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);v=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();w=(np.c_[v,np.ones(nv)]@matrix)[:,:3];new_world=w.copy();covered=np.zeros(nv,dtype=bool);pools=[];print('Pool source LOD',l['lod'],'vertices/triangles',nv,nt,'bounds',w.min(0).tolist(),w.max(0).tolist(),'Y levels',np.unique(w[:,1]).tolist())
 ys=np.unique(np.round(w[:,1],2));assert len(ys)==6;yranges=list(zip(ys[::2],ys[1::2]));assert len(yranges)==3 and all(abs(high-low-2500)<.02 for low,high in yranges)
 for low,high in yranges:
  mask=(w[:,1]>=low-.02)&(w[:,1]<=high+.02);assert mask.sum()>=8;lo=w[mask].min(0);hi=w[mask].max(0);assert abs(lo[0]-77620)<.02 and abs(hi[0]-82620)<.02 and 1184.9<=lo[2]<=1185.1 and 1185.7<=hi[2]<=1185.9,(lo,hi)
  for axis in [0,1]:new_world[mask,axis]=lo[axis]+1+(w[mask,axis]-lo[axis])*(hi[axis]-lo[axis]-2)/(hi[axis]-lo[axis])
  covered|=mask;pools.append(dict(original_bounds_cm=[lo.tolist(),hi.tolist()],inset_xy_cm=1,vertices=int(mask.sum())))
 assert covered.all() and np.array_equal(new_world[:,2],w[:,2]);new=(np.c_[new_world,np.ones(nv)]@np.linalg.inv(matrix))[:,:3].astype('<f4');new[:,2]=v[:,2];p=folder/('lod'+str(l['lod'])+'-vertices.bin');p.write_bytes(np.stack([v,new],axis=1).tobytes());lods.append(dict(lod=l['lod'],vertices=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()));changes.append(dict(lod=l['lod'],triangles=nt,vertices=nv,pools=pools,water_z_bit_identical=True))
plan=dict(status='prepared_requires_native_install',map_sha256=snap['map_sha256'],source_export_map_sha256=exp['map_sha256'],source_metadata_sha256=exp['metadata_sha256'],source_component=state,meshes=[dict(key=r['key'],before=m['asset'],after='/Game/UniversityCity/ImmersionV1/PoolEdge/SM_Campus_SP_Water_Recessed_v1',lods=lods,changes=changes)],policy='Inset each of the three existing0.8cm-thick water sheets1cm in XY so their vertical side faces no longer occupy the same plane as basin walls. Water elevations,UV/material bindings,basin dimensions and NoCollision unchanged; no pool/room movement.')
(O/'pool-edge-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared',changes,'from unchanged pool component in earlier export',exp['map_sha256'],'for current source',snap['map_sha256'])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
