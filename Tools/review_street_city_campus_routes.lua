local code=[====[
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');p=json.loads((O/'campus-route-plan.json').read_text('utf8'))
scale=.018;im=Image.new('RGB',(840,1100),'#708765');d=ImageDraw.Draw(im)
def xy(q):return (40+(q[0]-54800)*scale,1060-(q[1]-19500)*scale)
for r in p['obstacles']:
 x0,y0,x1,y1=r['rect_cm'];a=xy([x0,y1]);b=xy([x1,y0]);d.rectangle([a,b],fill='#d9d7c6',outline='#535f5e',width=2);d.text((a[0]+3,a[1]+3),r['label'].replace('Campus_','').replace('_F01',''),fill='#203630')
for r in p['routes']:
 pts=[xy(q) for q in r['points_cm']]
 if len(pts)>1:d.line(pts,fill='#f0dfb3',width=5)
for r in p['routes']:
 x,y=xy(r['points_cm'][0]);d.ellipse([x-3,y-3,x+3,y+3],fill='#a64848' if r['id'].startswith('gate') else '#214d6a')
d.text((20,15),'CAMPUS ROUTE PLAN - NOT A GAME RENDER',fill='white');d.text((20,35),'5 gates + 34 entrances | native support / capsule checks required',fill='white')
im.save(O/'campus-route-plan.png')
print('Route topology review diagram written')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
