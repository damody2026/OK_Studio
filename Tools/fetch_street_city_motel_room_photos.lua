-- Fetch every official photo of every room (WeGo thumbnails upgraded to catalog_room_b) and tile one review sheet per room.
-- Local reference only; used to author motel-room-specs.json.
local code=[====[
import json,subprocess,os
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');D=O/'reference-photos/rooms';D.mkdir(parents=True,exist_ok=True)
c=json.loads((O/'reference-catalog.json').read_text('utf-8-sig'));plan={r['id']:r for r in json.loads((O/'motel-plan.json').read_text('utf-8-sig'))['rooms']}
font=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',22);man={}
for r in c['rooms']:
 urls=[]
 for im in r['images']:
  u=im['url'].replace('/catalog_room_s/','/catalog_room_b/')
  if u not in urls:urls.append(u)
 got=[]
 for i,u in enumerate(urls,1):
  p=D/f"{r['id']}-{i}.jpg"
  if not p.exists() or p.stat().st_size<3000:subprocess.run(['curl.exe','-s','-L','--max-time','60','-o',str(p),u])
  if p.exists() and p.stat().st_size>3000:
   try:Image.open(p).verify();got.append(str(p))
   except Exception:pass
 man[r['id']]=got;q=plan[r['id']]
 ims=[]
 for g in got:
  im=Image.open(g).convert('RGB')
  if im.width<300:continue
  im.thumbnail((640,420));t=Image.new('RGB',(640,420));t.paste(im,((640-im.width)//2,(420-im.height)//2));ims.append(t)
 rows=max(1,(len(ims)+2)//3);sh=Image.new('RGB',(1920,40+rows*420),(18,18,22));d=ImageDraw.Draw(sh)
 d.text((10,8),f"{q['building']} {q['room_number']} {q['source_name']}  {'泳池房 ' if q['is_pool_suite'] else ''}{'車庫' if q['has_in_room_garage'] else '無車庫'}  ({r['id']})",font=font,fill='white')
 for i,t in enumerate(ims):
  sh.paste(t,((i%3)*640,40+(i//3)*420));d.text(((i%3)*640+6,44+(i//3)*420),str(i+1),font=font,fill=(255,220,120))
 sh.save(D/f"{r['id']}-sheet.jpg",quality=85)
(D/'manifest.json').write_text(json.dumps(man,ensure_ascii=False,indent=1),'utf8');print('rooms',len(man),'photos',sum(len(v) for v in man.values()))
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write(code));assert(p:close())
