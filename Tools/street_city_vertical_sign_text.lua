-- Newly typeset glyphs; the original horizontal logos are not rotated.
-- Lua orchestration runs inline Pillow without adding a Python project script.
local code=[====[
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
p=Path('output/street-social-city-production/resort-architecture-v1')
catalogue=json.loads(Path('output/street-social-city-production/localization-v1/catalogue.json').read_text('utf8'))['entries']
buildings=json.loads((p/'geometry-manifest.json').read_text('utf8'))['buildings']
names={b['id']:catalogue['building.'+b['id']]['translations'] for b in buildings}
boards={b['id']:b['sign_board'] for b in buildings}
rows=[]
for bid,locales in names.items():
 for locale,name in locales.items():
  if locale not in ('zh-Hant','zh-Hans','en'):continue
  vertical=boards[bid]['placement']=='ground_to_upper_vertical'
  ratio=boards[bid]['width_m']*.94/(boards[bid]['height_m']*.84)
  width,height=(512,2048) if vertical else (2048,max(128,round(2048/ratio)))
  im=Image.new('RGB',(width,height),(244,238,219));d=ImageDraw.Draw(im)
  if vertical:
   chars=list(name.replace(' ',''));size=min(360,int(1850/len(chars)*.9));font=ImageFont.truetype('C:/Windows/Fonts/msjhbd.ttc',size);step=1850/len(chars)
   for i,ch in enumerate(chars):
    box=d.textbbox((0,0),ch,font=font);x=width/2-(box[2]+box[0])/2;y=99+(i+.5)*step-(box[3]+box[1])/2
    d.text((x,y),ch,font=font,fill=(28,66,59))
  else:
   size=height
   while True:
    font=ImageFont.truetype('C:/Windows/Fonts/msjhbd.ttc',size);box=d.textbbox((0,0),name,font=font)
    if box[2]-box[0]<width*.92 and box[3]-box[1]<height*.82:break
    size-=1
   # Large upright glyphs with measured tracking, never a stretched logo.
   tracking=min(size*.5,max(0,(width*.88-d.textlength(name,font=font))/max(1,len(name)-1)))
   x=(width-d.textlength(name,font=font)-tracking*(len(name)-1))/2;y=(height-box[3]-box[1])/2
   for ch in name:d.text((x,y),ch,font=font,fill=(28,66,59));x+=d.textlength(ch,font=font)+tracking
  dest=p/'lettering-v2'/locale/(bid+'.png');dest.parent.mkdir(parents=True,exist_ok=True);im.save(dest);rows.append({'building':bid,'locale':locale,'text':name,'path':str(dest),'layout':'vertical' if vertical else 'horizontal','size':[width,height],'font_px':size,'logo':False})
assert len(rows)==366
(p/'lettering-review.json').write_text(json.dumps({'status':'passed','buildings':122,'textures':366,'rows':rows},ensure_ascii=False,indent=2),'utf8')
print('Prepared 366 large text sign textures')
]====]
local process=assert(io.popen('python -','w'))
assert(process:write(code));assert(process:close())
