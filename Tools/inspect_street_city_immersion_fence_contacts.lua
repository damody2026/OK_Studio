-- Describe exact fence contacts; classification remains explicit and scoped.
local code=[====[
import json,collections
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');scopes=json.loads((O/'depth-scopes.json').read_text('utf8'));s=next(r for r in scopes['scopes'] if r['name']=='outdoor-ground');groups={}
for line in (Path(s['folder'])/'depth-report.conflicts.jsonl').open():
 r=json.loads(line)
 if not r['exact_triangle'] or not r['a_actor'].startswith('FlatCampus_Fence_') or not r['b_actor'].startswith('FlatCampus_Fence_'):continue
 dot=sum(a*b for a,b in zip(r['a_front_normal'],r['b_front_normal']));key=(r['a_actor'],r['b_actor'],round(r['normal'][2],3),round(dot,3),r['pass_lod']);g=groups.setdefault(key,dict(count=0,z_min=1e9,z_max=-1e9,example=r));g['count']+=1;g['z_min']=min(g['z_min'],r['center_cm'][2]);g['z_max']=max(g['z_max'],r['center_cm'][2])
rows=[dict(a=k[0],b=k[1],normal_z=k[2],front_normal_dot=k[3],lod=k[4],**v) for k,v in groups.items()]
(O/'fence-contact-context.json').write_text(json.dumps(dict(status='requires_closed_contact_review',map_sha256=scopes['map_sha256'],rows=rows),indent=2),'utf8')
for r in rows:print(r['a'],r['b'],'z',r['normal_z'],'front dot',r['front_normal_dot'],'LOD',r['lod'],'count',r['count'],'heights',r['z_min'],r['z_max'])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
