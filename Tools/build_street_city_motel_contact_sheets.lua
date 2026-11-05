-- Small review sheets derived from our own native screenshots; originals kept.
local code=[====[
import json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');c=json.loads((O/'captures.json').read_text('utf8'));p=json.loads((O/'motel-plan.json').read_text('utf8'));assert not c['preview'];lookup={r['id']:r for r in c['images']};dest=O/('review-'+c['package_id']);dest.mkdir(exist_ok=True);font=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',19);small=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',16);rows=[]
def sheet(name,images):
 cols=3;tw,th=640,360;header=48;canvas=Image.new('RGB',(cols*tw,math.ceil(len(images)/cols)*(th+header)),(22,26,32));d=ImageDraw.Draw(canvas)
 for i,(label,r) in enumerate(images):
  x=(i%cols)*tw;y=(i//cols)*(th+header)
  with Image.open(r['path'])as im:assert im.size==(1920,1080);canvas.paste(im.convert('RGB').resize((tw,th),Image.Resampling.LANCZOS),(x,y+header))
  d.text((x+9,y+4),label[:42],font=font,fill='white');d.text((x+9,y+27),r['id'][:64],font=small,fill=(181,195,211))
 path=dest/(name+'.jpg');canvas.save(path,quality=94);rows.append(dict(id=name,path=str(path),image_ids=[r['id'] for label,r in images]))
rooms=p['rooms']
for n in range(0,len(rooms),3):
 group=rooms[n:n+3];images=[]
 for suffix in ['-bed-12','-bed-21','-bath-21']:
  for r in group:images.append((r['building']+' '+r['room_number']+' '+r['source_name'],lookup[r['id']+suffix]))
 sheet('rooms-'+str(n//3+1).zfill(2),images)
if any('-decor' in r['id'] for r in c['images']):
 for n in range(0,len(rooms),3):
  group=rooms[n:n+3];images=[]
  for suffix in ['-decorA-12','-decorB-12']:
   for r in group:images.append((r['building']+' '+r['room_number']+' 飾品'+suffix[6],lookup[r['id']+suffix]))
  sheet('decor-'+str(n//3+1).zfill(2),images)
rest=[r for r in c['images'] if '-bed-' not in r['id'] and '-bath-' not in r['id'] and '-decor' not in r['id']]
for n in range(0,len(rest),6):sheet('details-'+str(n//6+1).zfill(2),[(r['id'],r)for r in rest[n:n+6]])
phy=O/'physics-latest.json'
if phy.exists():
 run=json.loads(phy.read_text('utf8'))
 if run.get('status')=='passed' and run.get('soak_seconds',0)>60 and run['map_sha256']==c['map_sha256'] and run['package_id']==c['package_id']:
  live=json.loads(Path(run['native_receipt']).read_text('utf8'))['soak_images'];images=[dict(id='walk-'+str(i).zfill(4),path=r['path'])for i,r in enumerate(live)]
  for n in range(0,len(images),6):sheet('walking-'+str(n//6+1).zfill(2),[(r['id'],r)for r in images[n:n+6]])
import hashlib
for r in rows:r['sha256']=hashlib.sha256(Path(r['path']).read_bytes()).hexdigest()
(O/'contact-sheets.json').write_text(json.dumps(dict(status='generated_requires_visual_review',package_id=c['package_id'],map_sha256=c['map_sha256'],sheets=rows),ensure_ascii=False,indent=2),'utf8');print('Generated',len(rows),'native screenshot contact sheets')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
