local code=[====[
import json,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/traffic-v1');c=json.loads((O/'captures.json').read_text(encoding='utf8'));rows=c['images'];assert len(rows)==65;folder=Path(rows[0]['path']).parent
for r in rows:
 p=Path(r['path']);assert Image.open(p).size==(1920,1080);assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256']
groups=[('outdoor-a',rows[:12],3),('outdoor-b',rows[12:20],3),('gates',rows[20:26],2),('campus',rows[26:30],2),('world',rows[30:35],2),('junctions-a',rows[35:43],2),('junctions-b',rows[43:51],2),('traffic-street',rows[51:57],2),('bridges',rows[57:],2)]
for name,rs,cols in groups:
 im=Image.new('RGB',(640*cols,380*((len(rs)+cols-1)//cols)));d=ImageDraw.Draw(im)
 for i,r in enumerate(rs):
  x,y=i%cols*640,i//cols*380;p=Image.open(r['path']);p.thumbnail((640,360));im.paste(p,(x,y));d.text((x+5,y+362),r['id'],fill='white')
 im.save(folder/('review-'+name+'.jpg'))
print('65 actual Game PNG dimensions and hashes checked; 9 review sheets prepared:',folder)
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
