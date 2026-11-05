-- Streaming candidate classification; reports are evidence, never automatic approval.
local code=[====[
import json,collections
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');scopes=json.loads((O/'depth-scopes.json').read_text('utf8'));result=[]
for scope in scopes['scopes']:
 groups={};counts=collections.Counter();near=[]
 with (Path(scope['folder'])/'depth-report.conflicts.jsonl').open() as stream:
  for line in stream:
   r=json.loads(line);sep=abs(r['separation_cm']);counts['total']+=1;counts['exact']+=bool(r['exact_triangle']);counts['within_0_2cm']+=sep<=.2;counts['horizontal_within_0_2cm']+=sep<=.2 and abs(r['normal'][2])>.98
   key=(r['a_actor'],r['a_material_slot'],r['b_actor'],r['b_material_slot'],r['pass_lod'],round(abs(r['normal'][2]),2))
   g=groups.setdefault(key,dict(count=0,near_count=0,exact_count=0,min_separation_cm=1e9,max_separation_cm=0,overlap_cm2=0,example=r));g['count']+=1;g['near_count']+=sep<=.2;g['exact_count']+=bool(r['exact_triangle']);g['min_separation_cm']=min(g['min_separation_cm'],sep);g['max_separation_cm']=max(g['max_separation_cm'],sep);g['overlap_cm2']+=r['overlap_cm2']
 ordered=[dict(a_actor=k[0],a_slot=k[1],b_actor=k[2],b_slot=k[3],lod=k[4],abs_normal_z=k[5],**v) for k,v in groups.items()];ordered.sort(key=lambda g:(g['near_count'],g['overlap_cm2']),reverse=True)
 result.append(dict(scope=scope['name'],counts=dict(counts),groups=ordered));print(scope['name'],dict(counts))
 for g in ordered[:12]:print(g['a_actor'],g['a_slot'],g['b_actor'],g['b_slot'],'LOD',g['lod'],'z',g['abs_normal_z'],'n',g['count'],'near',g['near_count'],'sep',round(g['min_separation_cm'],4),round(g['max_separation_cm'],4),'xyz',g['example']['center_cm'])
(O/'depth-candidate-summary.json').write_text(json.dumps(dict(status='requires_manual_classification',map_sha256=scopes['map_sha256'],scopes=result),indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
