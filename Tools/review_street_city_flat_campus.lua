local code=[====[
import json,hashlib
from pathlib import Path
from PIL import Image,ImageDraw
out=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/flat-campus-v1');capture=json.loads((out/'captures.json').read_text(encoding='utf8'));rows=capture['images'];assert len(rows)==35
for r in rows:
 p=Path(r['path']);assert Image.open(p).size==(1920,1080);assert hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256']
groups=[('outdoor-a',rows[:12],3),('outdoor-b',rows[12:20],3),('gates',rows[20:26],2),('campus',rows[26:30],2),('world',rows[30:],2)]
byid={r['id']:r for r in rows};folder=Path(rows[0]['path']).parent
for name,group,cols in groups:
 width=640;height=380;sheet=Image.new('RGB',(cols*width,((len(group)+cols-1)//cols)*height));draw=ImageDraw.Draw(sheet)
 for i,r in enumerate(group):
  x=i%cols*width;y=i//cols*height;pic=Image.open(r['path']);pic.thumbnail((640,360));sheet.paste(pic,(x,y));draw.text((x+5,y+362),r['id'],fill='white')
 sheet.save(folder/('review-'+name+'.jpg'))
print('Verified 35 PNG dimensions/hashes; five review sheets prepared in '+str(folder))
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
