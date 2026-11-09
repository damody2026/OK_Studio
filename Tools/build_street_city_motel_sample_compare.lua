-- Official photo (left) beside the actual game capture of the same composition (right), one sheet per sample room.
local code=[====[
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');S=O/'sample-rooms';R=O/'reference-photos/samples'
cap=json.loads((O/'sample-captures.json').read_text('utf8'));sb=json.loads((S/'sample-build.json').read_text('utf8'))
plan={r['id']:r for r in json.loads((O/'motel-plan.json').read_text('utf-8-sig'))['rooms']};lookup={r['id']:r for r in cap['images']}
font=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',24);small=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',18);tw,th=960,540;dest=S/'compare';dest.mkdir(exist_ok=True);out=[]
def tile(p):
 im=Image.open(p).convert('RGB');im.thumbnail((tw,th));t=Image.new('RGB',(tw,th),(10,10,12));t.paste(im,((tw-im.width)//2,(th-im.height)//2));return t
for b in sb['rooms']:
 q=plan[b['id']];views=b['views'];c=Image.new('RGB',(2*tw,60+len(views)*(th+34)),(20,22,28));d=ImageDraw.Draw(c)
 d.text((14,14),f"{q['building']} {q['room_number']} {q['source_name']}　左：官網　右：遊戲實機（同構圖）",font=font,fill='white')
 for i,v in enumerate(views):
  y=60+i*(th+34);c.paste(tile(R/(v['ref']+'.jpg')),(0,y+30));c.paste(tile(lookup[b['id']+'-'+v['id']]['path']),(tw,y+30));d.text((14,y+4),v['id'],font=small,fill=(200,210,225))
 p=dest/(b['id']+'.jpg');c.save(p,quality=90);out.append(str(p))
(dest/'manifest.json').write_text(json.dumps(dict(map_sha256=cap['map_sha256'],sheets=out),ensure_ascii=False,indent=2),'utf8');print('\n'.join(out))
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write(code));assert(p:close())
