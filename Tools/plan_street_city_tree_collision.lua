-- LOD0 stem geometry, never aggregate bounds containing billboard impostors.
local code=[====[
import json,struct,hashlib,math
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');e=json.loads((O/'depth-export.json').read_text('utf8'));folder=Path(e['folder']);rawscene=(folder/'scene.json').read_bytes();assert hashlib.sha256(rawscene).hexdigest()==e['metadata_sha256'];scene=json.loads(rawscene);snap=json.loads((O/'preservation-after.json').read_text('utf8'));assert snap['map_sha256']==e['map_sha256'];lookup={r['actor']+'::'+r['component']:r for r in snap['components']};cache={};rows=[];existing=[]
for r in scene['instances']:
 m=scene['meshes'][r['mesh']];asset=m['asset']
 state=lookup[r['key']]
 if not state['visible'] or state['hidden'] or state['actor_hidden']:continue
 if not any(s in asset for s in ['/TreeUpgradeV1/Assets/','/TreeUpgradeV2/Assets/','/ImmersionV1/LandscapeLOD/','/ImmersionV1/Evergreens/','/ImmersionV1/Palms/Assets/','/ImmersionV1/Cherries/Assets/']):continue
 if r['collision']!='NoCollision':existing.append(dict(key=r['key'],instance=r['instance'],collision=r['collision']));continue
 if asset not in cache:
  lod=next(x for x in m['lods'] if x['lod']==0);data=(folder/lod['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',data);v=np.frombuffer(data,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);band=v[(v[:,2]>=-5)&(v[:,2]<=160)];assert len(band)>=5;lo=band[:,:2].min(axis=0);hi=band[:,:2].max(axis=0);center=(lo+hi)/2;radius=float(np.linalg.norm(band[:,:2]-center,axis=1).max())+1.;assert 4<radius<45,(asset,radius);cache[asset]=dict(center_xy_cm=center.tolist(),radius_cm=radius,source=lod['file'],source_sha256=hashlib.sha256(data).hexdigest(),selected_vertices=len(band))
 p=cache[asset];s=lookup[r['key']];t=s['instances'][r['instance']] if r['instance']>=0 else s['transform'];matrix=np.array(r['matrix']).reshape(4,4);pos=np.array([*p['center_xy_cm'],100,1])@matrix;scale=t['scale'];rows.append(dict(actor=r['actor'],component=s['component'],instance=r['instance'],source_transform=t,source_mesh=asset,center_cm=pos[:3].tolist(),rotation=t['rotation'],size_cm=[p['radius_cm']*2*abs(scale[0]),p['radius_cm']*2*abs(scale[1]),200*abs(scale[2])],stem_radius_local_cm=p['radius_cm'],campus=bool(54800<matrix[3,0]<97000 and 19500<matrix[3,1]<77000)))
assert len(rows)>=900
plan=dict(status='prepared_requires_native_physics_validation',map_sha256=e['map_sha256'],source_metadata_sha256=e['metadata_sha256'],source_folder=str(folder),mesh_geometry=cache,rows=rows,existing_collidable=existing,total=len(rows),campus=sum(r['campus'] for r in rows),policy='Visible tree render components remain unchanged and NoCollision. Add hidden two-metre stem-only cylinder blockers matched to LOD0 lower-trunk radii and exact world transforms, including six new cherries. No leaves/canopies become solid; no invisible broad tree AABBs. Native route/interior checks and Game traversal remain mandatory.');(O/'tree-collision-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Tree stem proxies planned:',len(rows),'campus:',plan['campus'],'unique LOD0 stem models:',len(cache),'already collidable:',len(existing))
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
