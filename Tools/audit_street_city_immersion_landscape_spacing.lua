-- Read-only layout flags; AABBs are candidates, never automatic relocation authority.
local code=[====[
import json,re,math,collections
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');snapshot=json.loads((O/'preservation-after.json').read_text());exp=json.loads((O/'depth-export.json').read_text());scene=json.loads((Path(exp['folder'])/'scene.json').read_text());alignment=json.loads((O/'stem-render-alignment.json').read_text());assert snapshot['map_sha256']==exp['map_sha256']==alignment['map_sha256'];visible={(r['actor'],r['component']) for r in snapshot['components'] if r['visible'] and not r['hidden'] and not r['actor_hidden']};buildings=[]
for r in scene['instances']:
 if (r['actor'],r['component']) in visible and re.fullmatch(r'(Campus_[A-Z0-9]+|City_O\d+|[A-Z]\d+)_F01',r['actor']):buildings.append(dict(actor=r['actor'],min_cm=r['min'],max_cm=r['max']))
trees=[m['tree'] for m in alignment['matches']];inside=[];close_cherries=[]
for t in trees:
 p=t['root_cm']
 for b in buildings:
  lo,hi=b['min_cm'],b['max_cm']
  if lo[0]+20<p[0]<hi[0]-20 and lo[1]+20<p[1]<hi[1]-20 and lo[2]-100<p[2]<lo[2]+300:inside.append(dict(tree=t,building=b['actor'],bounds_cm=[lo,hi],requires='Native upward/ground rays and semantic courtyard check; bounding volume alone is not an obstruction proof.'))
 if t['actor'].startswith('Immersion_Cherry_Tree_'):
  for other in trees:
   if other['actor']==t['actor']:continue
   d=math.dist(p[:2],other['root_cm'][:2])
   if d<350:close_cherries.append(dict(cherry=t,neighbor=other,distance_cm=d))
lamps=[]
for r in snapshot['components']:
 if not r['visible'] or r['hidden'] or r['actor_hidden']:continue
 if r['actor'].startswith('Environment_') and r['actor'].endswith('_Foot'):lamps.append(dict(id=r['actor'][:-4],kind='environment',root_cm=r['transform']['translation']))
 if r['actor'].startswith('Street_lamp_'):
  for i,t in enumerate(r.get('instances',[])):lamps.append(dict(id=r['actor']+'/'+str(i),kind='existing_street',root_cm=t['translation']))
for i,q in enumerate(json.loads((O/'path-lamps.json').read_text())['fixtures']):lamps.append(dict(id='Immersion_PathLamp/'+str(i),kind='immersion_path',root_cm=q['position_cm']))
for i,q in enumerate(json.loads((O/'lantern-install.json').read_text())['fixtures']):lamps.append(dict(id='Immersion_Lantern/'+str(i),kind='immersion_lantern',root_cm=q['head_cm']))
near=[]
for i,a in enumerate(lamps):
 for b in lamps[i+1:]:
  if 'environment' not in [a['kind'],b['kind']]:continue
  d=math.dist(a['root_cm'][:2],b['root_cm'][:2])
  if d<250:near.append(dict(a=a,b=b,distance_cm=d))
report=dict(status='read_only_candidates_require_native_and_visual_review',map_sha256=snapshot['map_sha256'],ground_floor_building_volumes=len(buildings),tree_roots_inside_building_bounds=inside,cherry_neighbors_within350cm=close_cherries,known_lamp_locations=len(lamps),environment_lamp_pairs_within250cm=near,scope='First-floor AABB tree-root candidates and XY fixture spacing only. Does not detect all merged original lamp geometry, prove indoor penetration, or authorize bulk deletion. Retain actual courtyard semantics and validate any proposed movement with native/render tests.')
(O/'landscape-spacing.json').write_text(json.dumps(report,indent=2),'utf8');print('Building footprints',len(buildings),'tree-root candidates',len(inside),'close cherry neighbors',len(close_cherries),'lamp pairs',len(near))
for r in inside[:20]:print('tree/building',r['tree']['actor'],r['tree']['instance'],r['building'],r['tree']['root_cm'])
for r in close_cherries:print('cherry neighbor',r['cherry']['actor'],r['neighbor']['actor'],r['neighbor']['instance'],round(r['distance_cm'],1))
for r in near[:30]:print('lamp spacing',r['a']['id'],r['b']['id'],round(r['distance_cm'],1))
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
