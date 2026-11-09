-- Contact sheets are QA aids; original Game screenshots remain unmodified.
local code=[====[
import json,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
out=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1/baseline')
complete=(out/'captures.json').exists()
receipt=json.loads((out/('captures.json' if complete else 'captures-running.json')).read_text('utf8'))
rows=receipt.get('images',receipt.get('views'));rows=[r for r in rows if Path(r['path']).exists()]
if complete:assert len(rows)==68
for r in rows:
 p=Path(r['path']);assert Image.open(p).size==(1920,1080)
 if complete:assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256']
folder=Path(rows[0]['path']).parent
for first in range(0,len(rows),8):
 group=rows[first:first+8];canvas=Image.new('RGB',(1280,380*((len(group)+1)//2)));draw=ImageDraw.Draw(canvas)
 for i,r in enumerate(group):
  x,y=i%2*640,i//2*380;im=Image.open(r['path']);im.thumbnail((640,360));canvas.paste(im,(x,y));draw.text((x+5,y+362),r['id'],fill='white')
 canvas.save(folder/('review-immersion-%02d.jpg'%(first//8+1)))
print('Prepared contact sheets for',len(rows),'native Game images; complete receipt:',complete)
]====]
if arg[1]=='current' then code=code:gsub('immersion%-v1/baseline','immersion-v1'):gsub('len%(rows%)==68','len(rows)==receipt.get("expected_images",219)')end
if arg[1]=='render-repair' then code=code:gsub('immersion%-v1/baseline','immersion-v1'):gsub('captures.json','render-repair-captures.json'):gsub('captures%-running.json','render-repair-running.json'):gsub('len%(rows%)==68','len(rows)==receipt.get("expected_images",0)')end
if arg[1]=='current-live' then
 code=code:gsub('immersion%-v1/baseline','immersion-v1'):gsub("complete=%(out/'captures.json'%).exists%(%)",'complete=False'):gsub('import json,hashlib','import json,hashlib,time'):gsub("if Path%(r%['path'%]%).exists%(%)","if Path(r['path']).exists() and time.time()-Path(r['path']).stat().st_mtime>2")
end
if arg[1]=='preview' then code=code:gsub('immersion%-v1/baseline','immersion-v1/preview'):gsub('len%(rows%)==68','len(rows)==72')end
if arg[1]=='interiors' then code=code:gsub('immersion%-v1/baseline','immersion-v1/interiors')end
if arg[1]=='focus' then code=code:gsub('immersion%-v1/baseline','immersion-v1/focus'):gsub('len%(rows%)==68','len(rows)==20')end
if arg[1]=='detail' then code=code:gsub('immersion%-v1/baseline','immersion-v1/detail'):gsub('len%(rows%)==68','len(rows)==22')end
if arg[1]=='players' then code=code:gsub('immersion%-v1/baseline','immersion-v1/outdoor-players'):gsub('len%(rows%)==68','len(rows)==40')end
if arg[1]=='repair' then code=code:gsub('immersion%-v1/baseline','immersion-v1/repair'):gsub('len%(rows%)==68','len(rows)==44')end
if arg[1]=='players-v2' then code=code:gsub('immersion%-v1/baseline','immersion-v1/outdoor-players-v2'):gsub('len%(rows%)==68','len(rows)==40')end
if arg[1]=='groundcheck' then code=code:gsub('immersion%-v1/baseline','immersion-v1/groundcheck'):gsub('len%(rows%)==68','len(rows)==40')end
if arg[1]=='layout' then code=code:gsub('immersion%-v1/baseline','immersion-v1/layout'):gsub('len%(rows%)==68','len(rows)==46')end
if arg[1]=='all_current' then code=code:gsub('immersion%-v1/baseline','immersion-v1/all_current'):gsub('len%(rows%)==68','len(rows)==354')end
if arg[1]=='mirrors' then code=code:gsub('immersion%-v1/baseline','immersion-v1/mirrors'):gsub('len%(rows%)==68','len(rows)==52')end
if arg[1]=='polish' then code=code:gsub('immersion%-v1/baseline','immersion-v1/polish'):gsub('len%(rows%)==68','len(rows)==176')end
if arg[1]=='floors' then code=code:gsub('immersion%-v1/baseline','immersion-v1/floors'):gsub('len%(rows%)==68','len(rows)==178')end
if arg[1]=='layout-live' then
 code=code:gsub('immersion%-v1/baseline','immersion-v1/layout'):gsub("complete=%(out/'captures.json'%).exists%(%)",'complete=False'):gsub('import json,hashlib','import json,hashlib,time'):gsub("if Path%(r%['path'%]%).exists%(%)","if Path(r['path']).exists() and time.time()-Path(r['path']).stat().st_mtime>2")
end
local pipe=assert(io.popen('python -','w'));assert(pipe:write(code));assert(pipe:close())
