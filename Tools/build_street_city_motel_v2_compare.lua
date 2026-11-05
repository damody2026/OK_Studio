-- Official photos beside the packaged-game captures of the 57 mass-produced (rooms-v2) motel rooms.
-- Per room: top row = first 3 official photos, bottom row = game living-to-bed / entry-overview / bath.
-- Two rooms per page: motel-v1/reference-compare-v2/compare-NN.jpg (needs motel-v1/v2-captures.json).
-- Usage: lua Tools/build_street_city_motel_v2_compare.lua [room id ...]
local ids=table.concat(arg,' ')
local code=[====[
import json,sys
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');R=O/'reference-photos'
cap=json.loads((O/'v2-captures.json').read_text('utf8'));b=json.loads((O/'sample-rooms/rooms-v2-build.json').read_text('utf8'))
plan={r['id']:r for r in json.loads((O/'motel-plan.json').read_text('utf-8-sig'))['rooms']};lookup={r['id']:r['path'] for r in cap['images']}
only=set(sys.argv[1:]);rooms=[r['id'] for r in b['rooms'] if not only or r['id'] in only]
font=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',22);small=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',16);tw,th=640,360;dest=O/'reference-compare-v2';dest.mkdir(exist_ok=True)
def ref(rid,n):
 p=R/'rooms'/f'{rid}-{n}.jpg'  # full-size set (fetch_street_city_motel_room_photos.lua); older 3-photo set as fallback
 return p if p.exists() else R/f'{rid}-{n}.jpg'
VIEWS=['v-living-to-bed','v-entry-overview','v-bath']
def tile(p):
 t=Image.new('RGB',(tw,th),(10,10,12))
 try:im=Image.open(p).convert('RGB')
 except Exception:return t  # missing or broken download (one official photo failed earlier)
 im.thumbnail((tw,th));t.paste(im,((tw-im.width)//2,(th-im.height)//2))
 return t
block=40+2*(th+24);out=[]
for n in range(0,len(rooms),2):
 c=Image.new('RGB',(3*tw,2*block),(20,22,28));d=ImageDraw.Draw(c)
 for k,rid in enumerate(rooms[n:n+2]):
  q=plan[rid];y0=k*block;d.text((12,y0+8),f"{rid}　{q['building']} {q['room_number']} {q['source_name']}　上：官網　下：打包版遊戲",font=font,fill='white')
  for i in range(3):
   c.paste(tile(ref(rid,i+1)),(i*tw,y0+40+20));c.paste(tile(lookup.get(rid+'-'+VIEWS[i])),(i*tw,y0+40+th+24+20))
   d.text((i*tw+6,y0+40+th+24),VIEWS[i],font=small,fill=(200,210,225))
 p=dest/f'compare-{n//2+1:02d}.jpg';c.save(p,quality=88);out.append(str(p))
(dest/'manifest.json').write_text(json.dumps(dict(map_sha256=cap.get('map_sha256'),rooms=rooms,sheets=out),ensure_ascii=False,indent=2),'utf8');print(len(out),'sheets ->',dest)
]====]
local p=assert(io.popen('python -I - '..ids,'w'));assert(p:write(code));assert(p:close())
