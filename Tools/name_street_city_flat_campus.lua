local code=[====[
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
out=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/flat-campus-v1');p=out/'plan.json';plan=json.loads(p.read_text(encoding='utf8'));plan['school_name']='影輝大學'
for q in plan['gates']:
 im=Image.new('RGB',(2048,320),(14,31,29));d=ImageDraw.Draw(im);font=ImageFont.truetype('C:/Windows/Fonts/msjhbd.ttc',235);text='影輝大學';tracking=170;width=d.textlength(text,font=font)+tracking*(len(text)-1);x=(2048-width)/2;bb=d.textbbox((0,0),text,font=font);y=(285-bb[3]-bb[1])/2
 for ch in text:d.text((x,y),ch,font=font,fill=(244,226,179));x+=d.textlength(ch,font=font)+tracking
 small=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',38);sub=q['name']+'  |  YINGHUI UNIVERSITY';bb=d.textbbox((0,0),sub,font=small);d.text(((2048-bb[2]-bb[0])/2,270),sub,font=small,fill=(201,195,164));im.save(q['texture'])
plan['boundary_note']='South fence follows an inward notch around PK-0101: (54800,68600) -> (55450,68600) -> (55450,71400) -> (54800,71400).'
p.write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8');print('Typeset five Yinghui University gate signs.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
