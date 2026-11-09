-- QA contact sheets only; preserve original native screenshots and their hashes.
local id=assert(arg[1],'Pass immutable physics run ID');assert(id:match('^[a-z0-9%-]+$'))
local code=[====[
import json,hashlib,time
from pathlib import Path
from PIL import Image,ImageDraw
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');run='__RUN__';live=__LIVE__
if live:
 report=json.loads((O/(run+'.json')).read_text('utf8'));rows=[]
 for r in report['soak_images']:
  p=Path(r['path'])
  if p.is_file() and time.time()-p.stat().st_mtime>3:rows.append(dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
 rows=rows[:len(rows)//8*8];manifest=dict(map_sha256=report['supplied_plan_map_sha256'])
else:manifest=json.loads((O/(run+'-images.json')).read_text('utf8'));rows=manifest['images']
assert rows
folder=O/(run+'-review');folder.mkdir(exist_ok=True)
for r in rows:
 p=Path(r['path']);assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'];assert Image.open(p).size==(1920,1080)
for first in range(0,len(rows),8):
 group=rows[first:first+8];canvas=Image.new('RGB',(1280,380*((len(group)+1)//2)));draw=ImageDraw.Draw(canvas)
 for i,r in enumerate(group):
  x,y=i%2*640,i//2*380;im=Image.open(r['path']);im.thumbnail((640,360));canvas.paste(im,(x,y));draw.text((x+5,y+362),Path(r['path']).name,fill='white')
 canvas.save(folder/('review-%02d.jpg'%(first//8+1)))
(folder/'prepared.json').write_text(json.dumps(dict(status='prepared_requires_visual_review',source_manifest=run+'-images.json',original_images=len(rows),contact_sheets=(len(rows)+7)//8,map_sha256=manifest['map_sha256'])),encoding='utf8');print(folder,len(rows),'native images')
]====]
code=code:gsub('__RUN__',id):gsub('__LIVE__',arg[2]=='live' and 'True' or 'False');local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
