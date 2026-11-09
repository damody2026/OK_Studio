-- Physical sign finishes and height fields are typeset from catalogue text.
local code=[====[
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageFilter
import json,hashlib,numpy as np
out=Path('output/street-social-city-production/resort-architecture-v1')
catalogue=json.loads(Path('output/street-social-city-production/localization-v1/catalogue.json').read_text('utf8'))['entries']
buildings=json.loads((out/'geometry-manifest.json').read_text('utf8'))['buildings']
styles={
 'walnut_brass':dict(base=[50,32,23],letter=[213,176,105],frame=[116,83,43],roughness=.51,metal=.76,grain='wood',subtitle='COFFEE  &  BOOKS',emission=0),
 'cream_bronze':dict(base=[228,214,185],letter=[93,47,33],frame=[155,110,65],roughness=.33,metal=.42,grain='enamel',subtitle='BAKERY  &  PATISSERIE',emission=0),
 'sage_ceramic':dict(base=[70,99,82],letter=[239,226,195],frame=[179,154,108],roughness=.43,metal=.15,grain='enamel',subtitle='FLOWERS  &  LIFESTYLE',emission=0),
 'burgundy_enamel':dict(base=[86,29,32],letter=[233,207,155],frame=[139,104,60],roughness=.28,metal=.6,grain='enamel',subtitle='KITCHEN  &  DINING',emission=0),
 'navy_channel':dict(base=[25,44,62],letter=[229,224,204],frame=[130,143,143],roughness=.32,metal=.65,grain='metal',subtitle='UNIVERSITY  SHOPPING  STREET',emission=.12),
 'charcoal_brass':dict(base=[38,40,39],letter=[207,170,103],frame=[113,101,75],roughness=.38,metal=.82,grain='metal',subtitle='STUDIO  &  BOUTIQUE',emission=0),
 'ivory_lightbox':dict(base=[219,221,207],letter=[30,84,73],frame=[103,128,117],roughness=.36,metal=.24,grain='enamel',subtitle='UNIVERSITY  CITY',emission=.08)}
rows=[];designs=[]
for b in buildings:
 bid=b['id'];q=b['sign_board'];title=catalogue['building.'+bid]['translations']['zh-Hant'];seed=int(hashlib.sha256(bid.encode()).hexdigest()[:8],16);rng=np.random.default_rng(seed)
 style='ivory_lightbox'
 if bid.startswith('S') and bid[1:].isdigit():
  style='walnut_brass' if any(k in title for k in ['咖啡','書','茶']) else 'cream_bronze' if any(k in title for k in ['烘','甜','麵包','蛋糕']) else 'sage_ceramic' if any(k in title for k in ['花','園','植']) else 'burgundy_enamel' if any(k in title for k in ['餐','食','麵','飯','酒','料理']) else 'charcoal_brass' if any(k in title for k in ['髮','美','飾','服','藝']) else ['navy_channel','sage_ceramic','charcoal_brass'][seed%3]
 if any(k in title for k in ['民宿','溫泉','會館']):style='walnut_brass'
 s=dict(styles[style])
 for words,subtitle in [(['咖啡'],'COFFEE  &  DESSERTS'),(['書'],'BOOKS  &  COFFEE'),(['手搖','茶飲','飲店'],'TEA  &  REFRESHMENTS'),(['藥'],'HEALTH  &  BEAUTY'),(['水果','鮮果'],'FRESH  FRUIT'),(['寵物','毛孩'],'PET  SUPPLIES'),(['洗衣'],'LAUNDRY'),(['髮','美容'],'HAIR  &  BEAUTY'),(['相機','底片','相館'],'CAMERA  &  PHOTO'),(['單車','自行車'],'BICYCLE  SHOP'),(['唱片','樂器','音樂'],'RECORDS  &  MUSIC'),(['遊戲','桌遊'],'GAMES  &  HOBBIES'),(['民宿'],'GUEST  HOUSE'),(['溫泉','會館'],'HOT  SPRING  RETREAT'),(['彩券'],'LOTTERY')]:
  if any(k in title for k in words):s['subtitle']=subtitle
 if not (bid.startswith('S') and bid[1:].isdigit()):s['subtitle']='UNIVERSITY  CITY'
 vertical=q['placement']=='ground_to_upper_vertical';wm=q['width_m']*.94;hm=q['height_m']*.84
 w,h=(512,2048) if vertical else (2048,max(256,round(2048*hm/wm)))
 # Typeset on a physically proportional canvas before packing the thin atlas.
 # Keeping >=256 vertical texels must never stretch the glyphs in world space.
 if not vertical:w=round(h*wm/hm)
 canvas_w=w
 designs.append(dict(id=bid,style=style,relief_cm=2.8,face_offset_m=.19,physical_size_m=[wm,hm],letter_roughness=.24,panel_roughness=s['roughness'],letter_metallic=s['metal'],emission=s['emission'],hardware='four recessed screw heads, raised perimeter rim, original wall standoffs'))
 for locale in ['zh-Hant','zh-Hans','en']:
  w=canvas_w
  name=catalogue['building.'+bid]['translations'][locale];glyph=Image.new('L',(w,h));d=ImageDraw.Draw(glyph)
  fontpath='C:/Windows/Fonts/msjhbd.ttc'
  if style=='walnut_brass' and locale!='en':fontpath='C:/Windows/Fonts/mingliu.ttc'
  if vertical:
   chars=list(name.replace(' ',''));size=min(360,int(1800/len(chars)*.9));f=ImageFont.truetype(fontpath,size)
   for i,ch in enumerate(chars):
    box=d.textbbox((0,0),ch,font=f);d.text((w/2-(box[0]+box[2])/2,124+(i+.5)*1800/len(chars)-(box[1]+box[3])/2),ch,font=f,fill=255)
  else:
   size=int(h*.92)
   while True:
    f=ImageFont.truetype(fontpath,size);box=d.textbbox((0,0),name,font=f)
    if box[2]-box[0]<w*.89 and box[3]-box[1]<h*.67:break
    size-=1
   tracking=min(size*.95,max(0,(w*.82-d.textlength(name,font=f))/max(1,len(name)-1)))
   x=(w-d.textlength(name,font=f)-tracking*(len(name)-1))/2;y=h*.42-(box[1]+box[3])/2
   for ch in name:d.text((x,y),ch,font=f,fill=255);x+=d.textlength(ch,font=f)+tracking
   small=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',max(12,round(h*.095)));sub=s['subtitle'];box=d.textbbox((0,0),sub,font=small)
   d.text(((w-box[2])/2,h*.79),sub,font=small,fill=210)
  rim=Image.new('L',(w,h));rd=ImageDraw.Draw(rim);margin=max(6,round(min(w,h)*.045));thick=max(2,round(min(w,h)*.012))
  rd.rounded_rectangle((margin,margin,w-margin-1,h-margin-1),radius=margin*.65,outline=150,width=thick)
  for xx in [margin*1.6,w-margin*1.6]:
   for yy in [margin*1.6,h-margin*1.6]:
    r=max(2,min(w,h)*.014);rd.ellipse((xx-r,yy-r,xx+r,yy+r),fill=180);rd.line((xx-r*.6,yy,xx+r*.6,yy),fill=90,width=1)
  if not vertical and w!=2048:
   glyph=glyph.resize((2048,h),Image.Resampling.LANCZOS);rim=rim.resize((2048,h),Image.Resampling.LANCZOS);w=2048
  gm=np.asarray(glyph,dtype=np.float32)/255;rm=np.asarray(rim,dtype=np.float32)/255
  height=np.maximum(.10+.90*gm,rm*.8+.10)
  # Bevels measured by the actual board dimensions, not arbitrary normal strength.
  smooth=Image.fromarray(np.uint8(height*255)).filter(ImageFilter.GaussianBlur(.75));hf=np.asarray(smooth,dtype=np.float32)/255
  noise=rng.normal(0,.75,(h,w));yy,xx=np.mgrid[:h,:w]
  grain=noise
  if s['grain']=='wood':grain+=2.7*np.sin(yy*.42+2*np.sin(xx*.007))+1.2*np.sin(yy*1.8+xx*.013)
  elif s['grain']=='metal':grain+=.65*np.sin(xx*2.0)
  rgb=np.asarray(s['base'],np.float32)[None,None,:]+grain[:,:,None]
  rgb=rgb*(1-gm[:,:,None])+np.asarray(s['letter'])[None,None,:]*gm[:,:,None]
  rim_mask=np.clip(rm*1.7,0,1)[:,:,None];rgb=rgb*(1-rim_mask)+np.asarray(s['frame'])[None,None,:]*rim_mask
  color=Image.fromarray(np.uint8(np.clip(rgb,0,255)),'RGB').convert('RGBA');color.putalpha(smooth)
  dhdy,dhdx=np.gradient(hf*2.8,hm*100/h,wm*100/w)
  normals=np.stack([-dhdx,-dhdy,np.ones_like(hf)],axis=2);normals/=np.linalg.norm(normals,axis=2,keepdims=True)
  nrgb=np.uint8(np.clip((normals*.5+.5)*255,0,255));rough=s['roughness']*(1-gm)+.24*gm
  detail=Image.fromarray(nrgb,'RGB').convert('RGBA');detail.putalpha(Image.fromarray(np.uint8(rough*255)))
  folder=out/'relief-signs-v3'/locale;folder.mkdir(parents=True,exist_ok=True)
  paths={}
  for kind,img in [('color_height',color),('normal_roughness',detail),('height',smooth)]:
   dest=folder/(bid+'_'+kind+'.png');img.save(dest);paths[kind]=str(dest)
  assert hf[gm>.95].mean()>hf[(gm<.01)&(rm<.01)].mean()+.65
  rows.append(dict(building=bid,locale=locale,text=name,style=style,size=[w,h],physical_size_m=[wm,hm],layout_canvas_size=[canvas_w,h],font_px=size,logo=False,layout='vertical' if vertical else 'horizontal',path=paths['color_height'],maps=paths,height_min=float(hf.min()),height_max=float(hf.max())))
assert len(rows)==366
(out/'relief-signs-review.json').write_text(json.dumps(dict(status='passed',buildings=122,translations=366,texture_files=1098,rows=rows,designs=designs,method='Physical 2.8cm height field:beveled glyphs raised above recessed panel;packed color/height and tangent normal/roughness, explicit grayscale height source'),ensure_ascii=False,indent=2),'utf8')
print('Prepared122 realistic sign designs /366 height fields')
]====]
local process=assert(io.popen('python -','w'));assert(process:write(code));assert(process:close())
