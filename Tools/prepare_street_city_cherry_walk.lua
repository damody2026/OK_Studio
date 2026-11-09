-- Correct the site's transverse paving without moving either office building.
local code=[====[
import json,struct,hashlib
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'immersion-v1';S=B/'traffic-v1/surface-current';probe=json.loads((O/'cherry-context.json').read_text('utf8'));scene=json.loads((S/'scene.json').read_text('utf8'));r=next(q for q in scene['instances'] if q['actor']=='World_PK_0109');m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();matrix=np.array(r['matrix']).reshape(4,4);world=np.c_[xyz,np.ones(nv)]@matrix;tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);paving=np.unique(tri[np.isin(slots,[1,4])]);rest=np.unique(tri[~np.isin(slots,[1,4])]);assert not np.intersect1d(paving,rest).size;new=world.copy();new[rest,2]-=5.8;new[paving,2]-=50
# Keep the old curved/capped topology buried, rather than flatten overlapping
# layers into a new coplanar surface. A single finite slab carries the new path.
local=(new@np.linalg.inv(matrix))[:,:3].astype('<f4');folder=O/'cherry-walk';folder.mkdir(exist_ok=True);path=folder/'PK0109-aligned-vertices.bin';path.write_bytes(np.stack([xyz,local],axis=1).tobytes());mesh=dict(key=r['key'],before=m['asset'],after='/Game/UniversityCity/ImmersionV1/CherryWalk/SM_PK0109_AlignedPromenade_v2',lods=[dict(lod=0,vertices=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())]);(O/'cherry-mesh-plan.json').write_text(json.dumps(dict(map_sha256=probe['map_sha256'],meshes=[mesh]),indent=2),'utf8');moves=[]
for index,x,y in [(0,44050,80100),(1,44850,82900)]:
 members=[q for q in probe['fixtures'] if q['actor'].startswith('Environment_PK_0109_'+str(index)+'_')];foot=next(q for q in members if q['actor'].endswith('_Foot'));p=foot['center_cm'];base=p[2]-foot['extent_cm'][2];delta=np.array([x-p[0],y-p[1],1198.2-base]);assert len(members)==6
 for q in members:moves.append(dict(actor=q['actor'],before=q['transform'],target_cm=(np.array(q['transform']['location'])+delta).tolist()))
import math
boxes=[dict(center=[44500,81500,1196],size=[400,4000,16],roll_deg=0)]
for a,b,za,zb in [(79300,79500,1198.5,1204),(83500,83700,1204,1198.5)]:
 angle=math.atan2(zb-za,b-a);boxes.append(dict(center=[44500,(a+b)/2+math.sin(angle)*8,(za+zb)/2-math.cos(angle)*8],size=[400,(b-a)/math.cos(angle),16],roll_deg=math.degrees(angle)))
plan=dict(status='prepared_requires_native_preflight',map_sha256=probe['map_sha256'],actor=r['actor'],source_mesh=m['asset'],paving_vertex_count=len(paving),furniture_vertex_count=len(rest),fixture_moves=moves,path_bounds_cm=[44300,44700,79500,83500],path_boxes=boxes,walk_points_cm=[[44500,79325],[44500,79550],[44500,80500],[44500,81500],[44500,82500],[44500,83450],[44500,83675]],policy='PK0109 is the authored cherry-blossom promenade. Bury the obsolete transverse curved paving50cm, replace its render/collision surface with one finite40x4m longitudinal stone slab and two2m gentle access ramps in the clear office gap. Preserve existing benches/lamps and lower their feet5.8cm to land; keep both office buildings/interiors/floors unchanged. Blossom planting follows.');(O/'cherry-walk-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared PK0109 longitudinal promenade:',len(paving),'retired paving vertices;',len(rest),'furniture vertices;',len(moves),'fixture actors.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
