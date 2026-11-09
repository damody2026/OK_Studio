-- Hidden blockers must correspond to visible trunks, not merely pass positive rays.
local code=[====[
import json,collections,math
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');snapshot=json.loads((O/'preservation-after.json').read_text());audit=json.loads((O/'audit.json').read_text());assert audit['status']=='passed' and snapshot['map_sha256']==audit['map_sha256'];trees=[];proxies=[];counts=collections.Counter()
families=['/TreeUpgradeV1/Assets/','/TreeUpgradeV2/Assets/','/ImmersionV1/LandscapeLOD/','/ImmersionV1/Evergreens/','/ImmersionV1/Palms/Assets/','/ImmersionV1/Cherries/Assets/','/ImmersionV1/CherriesV2/Assets/','/FloweringTrees/']
for r in snapshot['components']:
 if r['actor'] in ['LandscapeV3_TrunkCollision','Immersion_Cherry_TrunkColliders']:
  for i,t in enumerate(r['instances']):
   root=list(t['translation']);convention='Legacy base-origin trunk mesh'
   if r['actor']=='Immersion_Cherry_TrunkColliders':
    assert r['mesh']=='/Engine/BasicShapes/Cylinder.Cylinder' and np.linalg.norm(np.array(t['rotation'][:2]))<1.e-6;root[2]-=50*t['scale'][2];convention='Vertical Engine Cylinder centre-origin: subtract local50cm half-height after scale; yaw does not change base height'
   proxies.append(dict(actor=r['actor'],instance=i,root_cm=root,source_translation_cm=t['translation'],root_convention=convention))
 if not r['visible'] or r['hidden'] or r['actor_hidden']:continue
 family=next((p for p in families if p in r['mesh']),None)
 if not family:continue
 for i,t in enumerate(r.get('instances',[r['transform']])):trees.append(dict(actor=r['actor'],component=r['component'],instance=i if 'instances' in r else -1,mesh=r['mesh'],root_cm=t['translation']));counts[family]+=1
assert trees and len(proxies)==1640
tp=np.array([t['root_cm'][:2] for t in trees]);pp=np.array([p['root_cm'][:2] for p in proxies]);dist=np.linalg.norm(tp[:,None,:]-pp[None,:,:],axis=2);tree_missing=[];proxy_missing=[];matches=[]
for i,t in enumerate(trees):
 j=int(np.argmin(dist[i]));d=float(dist[i,j]);row=dict(tree=t,proxy=proxies[j],xy_distance_cm=d,root_z_delta_cm=proxies[j]['root_cm'][2]-t['root_cm'][2]);matches.append(row)
 if d>1 or abs(row['root_z_delta_cm'])>5:tree_missing.append(row)
for j,p in enumerate(proxies):
 i=int(np.argmin(dist[:,j]));d=float(dist[i,j]);delta=p['root_cm'][2]-trees[i]['root_cm'][2]
 if d>1 or abs(delta)>5:proxy_missing.append(dict(proxy=p,nearest_tree=trees[i],xy_distance_cm=d,root_z_delta_cm=delta))
result=dict(status='matched_visible_roots' if not tree_missing and not proxy_missing else 'requires_visibility_and_vertical_geometry_review',map_sha256=snapshot['map_sha256'],visible_tree_instances=len(trees),hidden_proxy_instances=len(proxies),families=dict(counts),unmatched_visible_roots=tree_missing,unmatched_proxies=proxy_missing,matches=matches,scope='Exact root-transform alignment across upgraded and flowering tree families. Root Z tolerance5cm catches floor misplacement; positive cooked physics is a separate receipt. Unknown model families or intentional mesh-root offsets require review, never automatic collider removal.')
(O/'stem-render-alignment.json').write_text(json.dumps(result,indent=2),'utf8');print(result['status'],'trees',len(trees),'proxies',len(proxies),'unmatched trees/proxies',len(tree_missing),len(proxy_missing));print(dict(counts))
for r in proxy_missing[:5]:print('unmatched proxy',r['proxy'],'nearest',r['nearest_tree']['actor'],'XY',r['xy_distance_cm'],'Z',r['root_z_delta_cm'])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
