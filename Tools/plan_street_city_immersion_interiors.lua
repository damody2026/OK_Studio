-- Read existing architectural contracts without changing the accepted models.
local code=[====[
import sys,json,hashlib
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu');sys.path.insert(0,str(R/'Tools'))
from street_city_campus_contract import IDS,context
O=R/'output/street-social-city-production/immersion-v1';rows=[]
for bid in IDS:
 c=context(bid);b=c['building'];assembly=json.loads((c['out']/'assembly-report.json').read_text('utf8'))
 row=dict(building=bid,floors=b['floors'],doors=assembly['doors'],entrances=b['entrances'],corridors=[],rooms=[])
 for rid,r in c['rooms'].items():
  frame=c['door_frames'].get(rid+'-door')
  if frame:row['rooms'].append(dict(id=rid,name=r['display_name'],type=r['room_type'],floor=r['floor'],position_m=r['position_m'],yaw=r['rotation_z_deg'],door=frame))
 for inst in c['instances']:
  a=c['assets'][inst['asset_id']]
  if a['role']=='circulation' and any(t in a['name'].lower() for t in ['corridor','aisle','走廊','通道']):row['corridors'].append(dict(id=inst['id'],position_m=inst['position_m'],yaw=inst['rotation_z_deg'],size_m=a['size_m']))
 rows.append(row)
(O/'interior-probe-plan.json').write_text(json.dumps(dict(status='prepared',buildings=rows),ensure_ascii=False,indent=2),'utf8')
print('Prepared',len(rows),'buildings,',sum(len(r['floors']) for r in rows),'floors and',sum(len(r['doors']) for r in rows),'doors for current native inspection')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
