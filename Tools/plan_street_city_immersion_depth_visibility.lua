-- Exact current scan,or explicit geometry-preserving player-start equivalence.
-- Select probes; do not automatically approve candidates.
local code=[====[
import json,collections,hashlib
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');scopes=json.loads((O/'depth-scopes.json').read_text('utf8'));start=json.loads((O/'walker-start-install.json').read_text('utf8'));current=json.loads((O/'audit.json').read_text('utf8'));assert current['status']=='passed' and (scopes['map_sha256']==current['map_sha256'] or (scopes['map_sha256']==start['before_map_sha256'] and current['map_sha256']==start['map_sha256']));groups={}
for scope in scopes['scopes']:
 with (Path(scope['folder'])/'depth-report.conflicts.jsonl').open() as stream:
  for line in stream:
   r=json.loads(line)
   if r['pass_lod']!=0 or r['separation_cm']>.2 or abs(r['normal'][2])<.98:continue
   key=(scope['name'],r['a_actor'],r['a_material_slot'],r['b_actor'],r['b_material_slot']);g=groups.setdefault(key,dict(count=0,cells={}))
   g['count']+=1;p=r['center_cm'];cell=tuple(round(q/100) for q in p)
   if cell not in g['cells'] or r['overlap_cm2']>g['cells'][cell]['overlap_cm2']:g['cells'][cell]=r
rows=[]
for key,g in sorted(groups.items()):
 candidates=sorted(g['cells'].values(),key=lambda r:(-r['overlap_cm2'],r['center_cm']))
 for r in candidates[:8]:rows.append(dict(id='depth-%04d'%len(rows),scope=key[0],group=list(key[1:]),group_lod0_candidates=g['count'],center_cm=r['center_cm'],overlap_cm2=r['overlap_cm2'],front_normals=[r['a_front_normal'],r['b_front_normal']],two_sided=[r['a_two_sided'],r['b_two_sided']]))
assert rows;plan=dict(status='prepared_requires_native_visibility_queries',map_sha256=current['map_sha256'],geometry_scan_map_sha256=scopes['map_sha256'],geometry_preservation_receipt='walker-start-install.json',rows=rows,groups=len(groups),scope='Deterministic up-to8 spatial samples per horizontal sub2mm candidate group atLOD0. Probe actual opaque visible blockers above each candidate. Positive coverage is local evidence,not proof for unsampled triangles or temporal rendering.');(O/'depth-visibility-plan.json').write_text(json.dumps(plan,indent=2),encoding='utf8');print('Prepared',len(rows),'native candidate probes across',len(groups),'groups')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
