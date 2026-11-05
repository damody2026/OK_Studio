local code=[====[
import sys,json
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu');sys.path.insert(0,str(R/'Tools'))
from street_city_campus_contract import context
rows=[]
for bid in ['SC','SP']:
 c=context(bid)
 for rid,r in c['rooms'].items():
  if not any(w in r['display_name'] for w in ['舞蹈','健身','更衣','復健','重量訓練','有氧器材','拳擊訓練','功能性訓練','體適能','瑜伽','皮拉提斯','武術','飛輪']):continue
  related=[dict(instance=i,asset=c['assets'][i['asset_id']]) for i in c['instances'] if i['owner']==rid or i['asset_id']==rid+'-shell']
  rows.append(dict(room=r,related=related))
O=R/'output/street-social-city-production/immersion-v1';(O/'mirror-room-plan.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),'utf8')
for r in rows:print(r['room']['room_id'],r['room']['display_name'],[(i['asset']['role'],i['asset']['size_m']) for i in r['related'] if 'shell' in i['instance']['asset_id']])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
