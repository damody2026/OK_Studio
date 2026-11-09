-- Repair measured coplanar painted markings, keeping the approved surface shaders.
local code=[====[
import json,struct,hashlib
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');S=B/'traffic-v1/surface-current';O=B/'immersion-v1';scene=json.loads((S/'scene.json').read_text('utf8'));r=next(q for q in scene['instances'] if q['actor']=='Outdoor_campus_track');m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();matrix=np.array(r['matrix']).reshape(4,4);world=np.c_[xyz,np.ones(nv)]@matrix;tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);new=world.copy();rows=[]
for slot,levels,delta in [(10,[1226.023624],2.),(2,[1227.223624,1227.323624,1227.723624],2.)]:
 vi=np.unique(tri[slots==slot]);mask=np.zeros(nv,dtype=bool)
 for z in levels:mask[vi[np.isclose(world[vi,2],z,atol=.015)]]=True
 assert int(mask.sum())>100;new[mask,2]+=delta;rows.append(dict(slot=slot,vertices=int(mask.sum()),old_levels_cm=levels,delta_cm=delta))
local=(new@np.linalg.inv(matrix))[:,:3].astype('<f4');folder=O/'track';folder.mkdir(exist_ok=True);path=folder/'track-depth-vertices.bin';path.write_bytes(np.stack([xyz,local],axis=1).tobytes());sha=hashlib.sha256(Path('C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap').read_bytes()).hexdigest();plan=dict(status='prepared_requires_native_validation',map_sha256=sha,actor=r['actor'],changes=rows,proven_defect='Track white slot10 paint and rubber slots8/9 occupy exactly Z1226.023624cm; field white edges are 0.1cm above turf. Raise only identified low white marking vertices by 2cm.',meshes=[dict(key=r['key'],before=m['asset'],after='/Game/UniversityCity/ImmersionV1/Track/SM_Track_DepthSeparated_v1',lods=[dict(lod=0,vertices=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())])]);(O/'track-depth-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Track depth plan:',rows)
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
