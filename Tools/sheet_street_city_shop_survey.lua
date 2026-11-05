-- Tile shop-survey captures into review sheets: one sheet per 4 shops (front day / front night / inside) plus an overview sheet.
-- Usage: lua Tools/sheet_street_city_shop_survey.lua <captures folder> [samples|floors]  (samples: one 3x3 sheet per shop;
--   floors: city interior inventory, <floor actor>-v1..v4 per row, five floors per sheet)
local folder=assert(arg[1]);local samples=arg[2]=='samples';local floors=arg[2]=='floors'
local code=[====[
import glob,os,re
from PIL import Image,ImageDraw,ImageFont
D=FOLDER;font=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',20)
fs=sorted(glob.glob(D+'/*.png'));shops=sorted({os.path.basename(p)[:3] for p in fs if re.match(r'S\d\d-',os.path.basename(p))})
def tile(name,rows):
 W,H=480,270;sh=Image.new('RGB',(W*max(len(r) for r in rows),H*len(rows)),(16,16,20));d=ImageDraw.Draw(sh)
 for r,row in enumerate(rows):
  for c,p in enumerate(row):
   if p and os.path.exists(p):sh.paste(Image.open(p).convert('RGB').resize((W,H)),(c*W,r*H));d.text((c*W+6,r*H+4),os.path.basename(p)[:-4],font=font,fill=(255,220,120))
 sh.save(D+'/'+name,quality=85)
if FLOORS:
 # -v1..v4 (corner views) or -r1..r6 (in-room views from motel_city_room_views)
 fl=sorted({re.sub(r'-[vr]\d$','',os.path.basename(p)[:-4]) for p in fs if re.search(r'_F\d\d-[vr]\d\.png$',p)})
 row=lambda a:sorted(p for p in fs if re.match(re.escape(a)+r'-[vr]\d\.png$',os.path.basename(p)))
 for i in range(0,len(fl),5):tile('floors-%02d.jpg'%(i//5+1),[row(a) for a in fl[i:i+5]])
 print('floors',len(fl),'sheets',(len(fl)+4)//5);raise SystemExit
if SAMPLES:
 for s in shops:tile(s+'-samples.jpg',[[D+'/%s-%s.png'%(s,k) for k in row] for row in (('front-12','front-21','wide-12'),('wide-21','inside-12','inside-21'),('inside-back-21',))])
else:
 for i in range(0,len(shops),4):
  tile('sheet-%02d.jpg'%(i//4+1),[[D+'/%s-%s.png'%(s,k) for k in ('front-12','front-21','inside-21')] for s in shops[i:i+4]])
ov=[p for p in fs if 'overview' in p]
if ov:tile('sheet-overview.jpg',[ov[i:i+3] for i in range(0,len(ov),3)])
print('shops',len(shops),'sheets',(len(shops)+3)//4)
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write('FOLDER='..string.format('%q',folder)..'\nSAMPLES='..(samples and 'True' or 'False')..'\nFLOORS='..(floors and 'True' or 'False')..'\n'..code));assert(p:close())
