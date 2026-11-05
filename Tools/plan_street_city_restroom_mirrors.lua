-- Inventory every authored WC washbasin, including public and private annexes.
local code=[====[
import sys,json,math,hashlib
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu');sys.path.insert(0,str(R/'Tools'))
from street_city_building_context import load_manifest
from street_city_parts import transform
m=load_manifest();rooms={r['room_id']:r for r in m['layouts'] if r.get('room_id')};buildings={r['building']:r for r in m['layouts'] if r.get('kind')=='building'};rows=[]
for i in m['instances']:
 if i['asset_id'] not in ['COMMON-WC-basin','COMMON-CITY-basin']:continue
 owner=i['owner'];b=owner.split('-')[0]
 if b in ['H1','S18','M1']:continue
 room=rooms.get(owner);p=transform(i['position_m'],room['position_m'],room['rotation_z_deg']) if room else i['position_m'];yaw=i['rotation_z_deg']+(room['rotation_z_deg'] if room else 0)
 rows.append(dict(id=i['id'],owner=owner,building=b,label=i['label'],position_m=p,yaw=yaw,asset=i['asset_id']))
for floor in range(1,11):
 for sign in [-1,1]:
  for k,dx in enumerate([-8,-5,-2]):
   rows.append(dict(id=f'M1:current-wc-F{floor:02d}-{sign}-{k}',owner='M1',building='M1',label='Current mall WC washbasin',position_m=[47*sign+dx,41.0,(floor-1)*4.2],yaw=180,asset='COMMON-CITY-basin',source='Tools/street_city_mall.py current ten-floor contract, replaces stale assembly-manifest basin layout'))
O=R/'output/street-social-city-production/motel-v1';(O/'restroom-sinks-plan.json').write_text(json.dumps(dict(status='authored_positions_require_native_wall_validation',source_manifest_sha256=hashlib.sha256((R/'Docs/StreetSocialCity/production/assembly-manifest.json').read_bytes()).hexdigest(),sinks=rows,replaced_hotel_buildings=['H1','S18'],policy='All public WC and private annex washbasins, excluding kitchen/lab sinks. New motel bathrooms are covered by their own room contracts.'),ensure_ascii=False,indent=2),'utf8');print(len(rows),'existing non-hotel WC washbasins prepared for native wall validation')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
