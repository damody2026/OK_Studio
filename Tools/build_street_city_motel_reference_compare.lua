-- Side-by-side sheets: official room photos (top) against our packaged-game captures (bottom), two rooms per sheet.
local code=[====[
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1')
plan=json.loads((O/'motel-plan.json').read_text('utf8'));cap={r['id']:r for r in json.loads((O/'captures.json').read_text('utf8'))['images']}
ref=json.loads((O/'reference-photos/manifest.json').read_text('utf8'))['photos']
dest=O/'reference-compare';dest.mkdir(exist_ok=True);font=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',22);small=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',16)
tw,th,hd=560,315,40
def tile(path):
 try:
  with Image.open(path) as im:
   im=im.convert('RGB');im.thumbnail((tw,th));t=Image.new('RGB',(tw,th),(12,12,14));t.paste(im,((tw-im.width)//2,(th-im.height)//2));return t
 except Exception:return Image.new('RGB',(tw,th),(60,0,0))
rooms=plan['rooms'];sheets=[]
for n in range(0,len(rooms),2):
 group=rooms[n:n+2];canvas=Image.new('RGB',(3*tw,len(group)*(2*th+hd)),(22,24,30));d=ImageDraw.Draw(canvas)
 for g,q in enumerate(group):
  y=g*(2*th+hd);d.text((10,y+6),f"{q['building']} {q['room_number']} {q['source_name']}  ({q['id']})",font=font,fill='white')
  refs=[r for r in ref if r['id']==q['id'] and r['ok']][:3]
  for i,r in enumerate(refs):canvas.paste(tile(r['path']),(i*tw,y+hd))
  for i,k in enumerate(['bed-12','bed-21','bath-21']):canvas.paste(tile(cap[q['id']+'-'+k]['path']),(i*tw,y+hd+th))
  d.text((6,y+hd+4),'官網',font=small,fill=(255,220,120));d.text((6,y+hd+th+4),'目前遊戲',font=small,fill=(120,220,255))
 p=dest/f'compare-{n//2+1:02d}.jpg';canvas.save(p,quality=90);sheets.append(dict(id=p.stem,rooms=[q['id'] for q in group],path=str(p)))
(dest/'manifest.json').write_text(json.dumps(dict(sheets=sheets),ensure_ascii=False,indent=2),'utf8');print('Built',len(sheets),'comparison sheets')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
