-- Shop-street mass production (Docs/STREET_CITY_SHOP_STREET_SPEC_20261025.md). Every regular shop (S01-S96 minus the
-- special S18/S19) gets a refit GLB in the building frame of its source floor GLB: glass storefront sized to the shop width,
-- awning, blade sign (localized), upper-floor attachments, street-front display and a ground floor laid out for its shop
-- type. Types either keep the original fixtures and add to them ("keep") or have the sales floor cut and rebuilt ("rebuild").
-- Specs: output/.../shop-refits-v1/shop-specs.json is generated from the catalogue (type from the shop name, palette
-- variant by occurrence); entries in shop-spec-overrides.json win. Install: Tools/street_city_shop_samples_payload.lua.
-- Usage: lua Tools/build_street_city_shop_refits.lua [--all|S02 S03 ...]   (default: every regular shop not yet approved)
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json')
local root='C:/portable/OpenKoikatsu';local prod=root..'/output/street-social-city-production';local out=prod..'/shop-refits-v1'
os.execute('mkdir "'..out:gsub('/','\\')..'" 2>nul')
local APPROVED={S01=true,S26=true,S09=true,S17=true}   -- approved samples stay as installed (shop-samples-v1)
local SPECIAL={S18=true,S19=true}
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local r=f:read('*a');f:close();return r end
local cat=j.decode(read(prod..'/localization-v1/catalogue.json'));cat=cat.entries or cat
local RULES={{'pet','寵物'},{'pet','毛孩'},{'pet','尾巴'},{'pet','毛球'},{'pet','爪印'},{'coffee','咖啡'},{'tea','茶'},{'tea','飲'},{'bakery','烘焙'},{'bakery','麵包'},{'bakery','甜點'},
 {'restaurant','餐'},{'restaurant','食堂'},{'restaurant','家常菜'},{'fruit','果'},{'convenience','便利'},{'convenience','生活站'},{'book','書'},{'florist','花'},{'laundry','洗衣'},{'clothing','服飾'},{'clothing','衣'},
 {'barber','髮'},{'barber','美容'},{'music','唱片'},{'music','樂器'},{'music','音樂'},{'music','拾音'},{'music','回聲'},{'game','桌遊'},{'game','遊戲'},{'game','骰子'},
 {'camera','相機'},{'camera','攝影'},{'camera','相館'},{'camera','沖印'},{'camera','相機舖'},{'bike','單車'},{'bike','自行車'},{'drug','藥妝'},{'laundry','洗'},{'lottery','彩券'},{'lottery','選號'},{'lottery','好運'},
 {'special','民宿'},{'special','溫泉'}}
local specs,seen={},{}
local over=j.decode(read(out..'/shop-spec-overrides.json') or '{}')
for n=1,96 do local id=string.format('S%02d',n);local e=cat['building.'..id];local name=e.translations['zh-Hant'];local ty
 for _,r in ipairs(RULES)do if name:find(r[2],1,true)then ty=r[1];break end end
 assert(ty,'no type for '..id..' '..name);seen[ty]=(seen[ty] or 0)+1
 local s={id=id,name=name,type=ty,variant=seen[ty]-1,names=e.translations}
 for k,v in pairs(over[id] or {})do s[k]=v end
 specs[#specs+1]=s end
local f=assert(io.open(out..'/shop-specs.json','wb'));f:write(j.encode({status='generated',shops=specs}));f:close()
local ids={}
if arg[1]=='--all' then for _,s in ipairs(specs)do if not SPECIAL[s.id] then ids[#ids+1]=s.id end end
elseif #arg>0 then for i=1,#arg do ids[#ids+1]=arg[i]end
else for _,s in ipairs(specs)do if not APPROVED[s.id] and not SPECIAL[s.id] then ids[#ids+1]=s.id end end end
-- 1. textures
local tex=[====[
import json,math,random
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageFilter
O=Path(OUT);T=O/'textures';T.mkdir(parents=True,exist_ok=True);F='C:/Windows/Fonts/'
SPECS={s['id']:s for s in json.loads((O/'shop-specs.json').read_text('utf8'))['shops']}
FONT={'kai':{'zh-Hant':F+'kaiu.ttf','zh-Hans':F+'simkai.ttf','en':F+'georgiab.ttf'},'sans':{'zh-Hant':F+'msjhbd.ttc','zh-Hans':F+'msyhbd.ttc','en':F+'segoeuib.ttf'}}
PAL=json.loads(PALETTES)
def C(c):return tuple(int(v*255) if isinstance(v,float) and v<=1.0 else int(v) for v in c)
def icon(d,kind,cx,cy,r,col):
 w=max(3,int(r*.12))
 if kind=='cup':d.rounded_rectangle((cx-r*.6,cy-r*.3,cx+r*.5,cy+r*.7),radius=r*.2,outline=col,width=w);d.arc((cx+r*.3,cy-r*.05,cx+r*.85,cy+r*.45),-90,90,fill=col,width=w)
 elif kind=='bag':d.rounded_rectangle((cx-r*.6,cy-r*.35,cx+r*.6,cy+r*.75),radius=r*.15,fill=col);d.arc((cx-r*.35,cy-r*.85,cx+r*.35,cy-r*.05),180,360,fill=col,width=w)
 elif kind=='leaf':d.ellipse((cx-r*.3,cy-r*.8,cx+r*.3,cy+r*.6),fill=col);d.line((cx,cy-r*.6,cx,cy+r*.9),fill=col,width=w)
 elif kind=='bubble':
  for (ox,oy,rr) in [(-.4,.2,.45),(.3,-.25,.35),(.45,.45,.22)]:d.ellipse((cx+ox*r-rr*r,cy+oy*r-rr*r,cx+ox*r+rr*r,cy+oy*r+rr*r),outline=col,width=w)
 elif kind=='apple':d.ellipse((cx-r*.6,cy-r*.45,cx+r*.6,cy+r*.7),fill=col);d.ellipse((cx,cy-r*.9,cx+r*.4,cy-r*.45),fill=col)
 elif kind=='book':d.rectangle((cx-r*.7,cy-r*.5,cx-r*.05,cy+r*.6),outline=col,width=w);d.rectangle((cx+r*.05,cy-r*.5,cx+r*.7,cy+r*.6),outline=col,width=w)
 elif kind=='paw':
  d.ellipse((cx-r*.4,cy,cx+r*.4,cy+r*.7),fill=col)
  for ox,oy in [(-.55,-.2),(-.2,-.55),(.2,-.55),(.55,-.2)]:d.ellipse((cx+ox*r-r*.17,cy+oy*r-r*.17,cx+ox*r+r*.17,cy+oy*r+r*.17),fill=col)
 elif kind=='hanger':d.line((cx-r*.8,cy+r*.5,cx,cy-r*.1,cx+r*.8,cy+r*.5,cx-r*.8,cy+r*.5),fill=col,width=w);d.arc((cx-r*.2,cy-r*.6,cx+r*.2,cy-r*.1),180,90,fill=col,width=w)
 elif kind=='scissors':d.ellipse((cx-r*.7,cy+r*.2,cx-r*.2,cy+r*.7),outline=col,width=w);d.ellipse((cx+r*.2,cy+r*.2,cx+r*.7,cy+r*.7),outline=col,width=w);d.line((cx-r*.35,cy+r*.25,cx+r*.5,cy-r*.8),fill=col,width=w);d.line((cx+r*.35,cy+r*.25,cx-r*.5,cy-r*.8),fill=col,width=w)
 elif kind=='note':d.ellipse((cx-r*.6,cy+r*.2,cx-r*.05,cy+r*.65),fill=col);d.line((cx-r*.1,cy+r*.4,cx-r*.1,cy-r*.8),fill=col,width=w);d.line((cx-r*.1,cy-r*.8,cx+r*.5,cy-r*.5),fill=col,width=w)
 elif kind=='dice':
  d.rounded_rectangle((cx-r*.6,cy-r*.6,cx+r*.6,cy+r*.6),radius=r*.15,outline=col,width=w)
  for ox,oy in [(-.3,-.3),(0,0),(.3,.3)]:d.ellipse((cx+ox*r-r*.1,cy+oy*r-r*.1,cx+ox*r+r*.1,cy+oy*r+r*.1),fill=col)
 elif kind=='camera':d.rounded_rectangle((cx-r*.75,cy-r*.4,cx+r*.75,cy+r*.55),radius=r*.12,outline=col,width=w);d.ellipse((cx-r*.3,cy-r*.25,cx+r*.3,cy+r*.35),outline=col,width=w);d.rectangle((cx-r*.5,cy-r*.6,cx-r*.15,cy-r*.4),fill=col)
 elif kind=='bike':d.ellipse((cx-r*.9,cy,cx-r*.2,cy+r*.7),outline=col,width=w);d.ellipse((cx+r*.2,cy,cx+r*.9,cy+r*.7),outline=col,width=w);d.line((cx-r*.55,cy+r*.35,cx-r*.1,cy-r*.3,cx+r*.55,cy+r*.35),fill=col,width=w)
 elif kind=='cross':d.rectangle((cx-r*.18,cy-r*.65,cx+r*.18,cy+r*.65),fill=col);d.rectangle((cx-r*.65,cy-r*.18,cx+r*.65,cy+r*.18),fill=col)
 elif kind=='star':
  pts=[(cx+r*.75*math.cos(math.pi/2+k*math.pi/5)*(1 if k%2==0 else .45),cy-r*.75*math.sin(math.pi/2+k*math.pi/5)*(1 if k%2==0 else .45)) for k in range(10)];d.polygon(pts,fill=col)
 elif kind=='bowl':d.chord((cx-r*.8,cy-r*.5,cx+r*.8,cy+r*.8),0,180,fill=col);d.line((cx+r*.2,cy-r*.8,cx+r*.6,cy-r*.1),fill=col,width=w);d.line((cx+r*.45,cy-r*.85,cx+r*.75,cy-r*.15),fill=col,width=w)
 else:d.ellipse((cx-r*.5,cy-r*.5,cx+r*.5,cy+r*.5),outline=col,width=w)
def vertical(s,loc,text,st):
 w,h=512,2048;bg,fg=C(st['sign_bg']),C(st['sign_fg']);im=Image.new('RGB',(w,h),bg);d=ImageDraw.Draw(im)
 m=26;d.rectangle((m,m,w-m,h-m),outline=fg,width=9);icon(d,st['icon'],w//2,int(h*.09),w*.22,fg)
 font=FONT[st.get('font','sans')][loc]
 if loc=='en':
  tmp=Image.new('RGBA',(h,w),(0,0,0,0));dd=ImageDraw.Draw(tmp);size=220
  while size>20:
   f=ImageFont.truetype(font,size);b=dd.textbbox((0,0),text,font=f)
   if b[2]-b[0]<=h*.74 and b[3]-b[1]<=w*.55:break
   size-=6
  dd.text(((h-(b[2]-b[0]))/2-b[0]+h*.06,(w-(b[3]-b[1]))/2-b[1]),text,font=f,fill=fg);tmp=tmp.rotate(90,expand=True);im.paste(tmp,(0,0),tmp)
 else:
  chars=list(text);n=len(chars);cell=min(w*.62,(h*.78)/n);f=ImageFont.truetype(font,int(cell*.92));y0=h*.19+(h*.78-cell*n)/2
  for i,ch in enumerate(chars):b=d.textbbox((0,0),ch,font=f);d.text(((w-(b[2]-b[0]))/2-b[0],y0+i*cell+(cell-(b[3]-b[1]))/2-b[1]),ch,font=f,fill=fg)
 return im
def horizontal_wood(text,loc):
 w,h=2048,512;im=Image.new('RGB',(w,h),(46,30,18));d=ImageDraw.Draw(im)
 for y in range(0,h,6):d.line((0,y,w,y),fill=(52+(y*7)%10,34,20))
 d.rectangle((18,18,w-18,h-18),outline=(196,156,82),width=10);font=FONT['kai'][loc];size=300
 while size>20:
  f=ImageFont.truetype(font,size);b=d.textbbox((0,0),text,font=f)
  if b[2]-b[0]<=w*.86 and b[3]-b[1]<=h*.66:break
  size-=6
 d.text(((w-(b[2]-b[0]))/2-b[0],(h-(b[3]-b[1]))/2-b[1]),text,font=f,fill=(240,214,160));return im
for sid in IDS:
 s=SPECS[sid]
 if s['type']=='special':
  for loc in ('zh-Hant','zh-Hans','en'):horizontal_wood(s['names'][loc],loc).save(T/f'{sid}-H-{loc}.png')
  continue
 st=PAL[s['type']][s['variant']%len(PAL[s['type']])]
 for loc in ('zh-Hant','zh-Hans','en'):vertical(s,loc,s['names'][loc],st).save(T/f'{sid}-V-{loc}.png')
r=random.Random(11)
def goods(name,pal,bg=(235,235,232),tall=(90,165),wide=(34,70)):
 im=Image.new('RGB',(1024,1024),bg);d=ImageDraw.Draw(im)
 for row in range(5):
  y0=row*204+18;d.rectangle((0,y0+170,1023,y0+186),fill=(200,200,198));x=4
  while x<1010:
   wdt=r.randint(*wide);hgt=r.randint(*tall);c=r.choice(pal);d.rectangle((x,y0+170-hgt,x+wdt-4,y0+170),fill=c);d.rectangle((x+6,y0+170-hgt+16,x+wdt-10,y0+170-hgt+38),fill=tuple(min(255,v+70) for v in c));x+=wdt
 im.save(T/(name+'.png'))
goods('goods_drug',[(250,250,250),(60,140,220),(40,170,120),(230,90,140),(120,200,230),(250,210,80)],(244,246,248))
goods('goods_pet',[(170,110,60),(90,150,60),(240,140,40),(60,110,170),(220,60,60),(240,220,160)])
goods('goods_game',[(220,40,40),(40,90,190),(250,190,30),(30,140,80),(120,50,150),(30,30,30),(240,110,30)],(60,48,40),(150,170),(28,52))
goods('goods_records',[(200,60,50),(30,30,30),(230,200,60),(60,90,160),(240,240,235),(120,40,110),(40,140,120)],(52,44,40),(160,170),(18,26))
goods('goods_tea',[(240,200,120),(220,120,60),(120,170,80),(250,240,220),(200,80,90)],(250,246,236),(60,120),(30,50))
goods('goods_lottery',[(220,30,40),(250,200,30),(240,240,240),(30,120,200)],(140,20,24),(40,90),(40,60))
# photo frames: little landscapes
im=Image.new('RGB',(1024,512),(30,30,30));d=ImageDraw.Draw(im)
for k in range(4):
 x0=k*256+12;sky=r.choice([(120,170,230),(240,170,110),(90,110,170),(200,220,240)]);d.rectangle((x0,12,x0+232,500),fill=sky)
 d.polygon([(x0,500),(x0,300+r.randint(-40,40)),(x0+90,220+r.randint(-40,40)),(x0+170,300),(x0+232,260),(x0+232,500)],fill=r.choice([(60,90,60),(90,70,60),(50,70,100)]));d.ellipse((x0+150,60,x0+200,110),fill=(250,240,200))
im.save(T/'photo_prints.png')
# backlit menu / number boards
im=Image.new('RGB',(1024,512),(250,246,236));d=ImageDraw.Draw(im)
for k in range(8):x=40+(k%4)*245;y=40+(k//4)*230;d.rounded_rectangle((x,y,x+200,y+200),radius=30,fill=r.choice([(240,190,110),(200,120,70),(140,190,110),(240,230,210),(220,110,120)]));d.rectangle((x+60,y+40,x+140,y+170),fill=(255,255,255))
im.save(T/'menu_lightbox.png')
im=Image.new('RGB',(1024,512),(20,20,24));d=ImageDraw.Draw(im);fz=ImageFont.truetype(F+'segoeuib.ttf',72)
for row in range(4):
 for k in range(6):d.ellipse((60+k*160,40+row*118,150+k*160,130+row*118),fill=(220,30,40) if (row+k)%3 else (250,200,30));d.text((78+k*160,46+row*118),str(r.randint(1,49)),font=fz,fill=(255,255,255))
im.save(T/'lottery_board.png')
for n,a,b,wid in [('pole_stripes',(200,30,40),(245,245,245),64)]:
 im=Image.new('RGB',(256,512),b);d=ImageDraw.Draw(im)
 for k in range(-512,512,wid*2):d.polygon([(0,k),(256,k+128),(256,k+128+wid),(0,k+wid)],fill=a)
 im.save(T/(n+'.png'))
for n,c1,c2,sz in [('tile_white_subway',(238,236,232),(214,212,206),(128,64)),('tile_mint',(200,230,220),(170,205,195),(96,96)),('wood_dark_panel',(70,46,30),(56,36,24),(1024,96)),('paint_pastel_pink',(240,214,214),(232,204,204),(1024,1024)),('paint_pastel_blue',(210,226,240),(200,216,232),(1024,1024))]:
 im=Image.new('RGB',(1024,1024),c2);d=ImageDraw.Draw(im)
 for y in range(0,1024,sz[1]):
  off=sz[0]//2 if (y//sz[1])%2 else 0
  for x in range(-sz[0],1024,sz[0]):d.rectangle((x+off+3,y+3,x+off+sz[0]-3,y+sz[1]-3),fill=c1)
 im.save(T/(n+'.png'))
for name,(a,b) in json.loads(AWNINGS).items():
 im=Image.new('RGB',(512,512),C(a));d=ImageDraw.Draw(im)
 if a!=b:
  for k in range(0,512,128):d.rectangle((k+64,0,k+127,511),fill=C(b))
 im.save(T/(name+'.png'))
src=Path(SAMPLE_TEX)
for n in ('goods_shelf','cooler_front','book_spines','chalk_menu','brick_warm','tile_laundry','wood_slat_light','band_conv'):
 im=Image.open(src/(n+'.png'));im.save(T/(n+'.png'))
print('textures ok',len(IDS))
]====]
-- palettes per type: storefront frame / awning A,B / fascia / sign colours / icon; variant = occurrence index
local P={
 coffee={{frame={.05,.17,.11},aw={{.12,.33,.23},{.92,.89,.78}},fascia={.05,.17,.11},sign_bg={22,52,38},sign_fg={222,184,104},icon='cup',font='kai'},{frame={.25,.13,.07},aw={{.42,.22,.12},{.93,.88,.76}},fascia={.25,.13,.07},sign_bg={58,34,20},sign_fg={236,206,150},icon='cup',font='kai'},{frame={.08,.12,.22},aw={{.12,.2,.36},{.92,.9,.84}},fascia={.08,.12,.22},sign_bg={20,32,58},sign_fg={226,196,120},icon='cup',font='kai'},{frame={.36,.06,.08},aw={{.48,.1,.12},{.94,.9,.82}},fascia={.36,.06,.08},sign_bg={86,18,22},sign_fg={240,214,160},icon='cup',font='kai'},{frame={.15,.15,.15},aw={{.2,.2,.2},{.2,.2,.2}},fascia={.15,.15,.15},sign_bg={30,30,30},sign_fg={240,226,196},icon='cup',font='sans'},{frame={.62,.5,.36},aw={{.55,.4,.25},{.95,.93,.88}},fascia={.62,.5,.36},sign_bg={240,232,214},sign_fg={90,58,30},icon='cup',font='kai'}},
 tea={{frame={.1,.55,.52},aw={{.1,.55,.52},{1,1,1}},fascia={.96,.96,.94},sign_bg={20,140,132},sign_fg={255,255,255},icon='cup'},{frame={.95,.75,.2},aw={{.95,.75,.2},{1,1,1}},fascia={.97,.96,.92},sign_bg={246,190,50},sign_fg={60,40,20},icon='cup'},{frame={.85,.45,.55},aw={{.85,.45,.55},{1,1,1}},fascia={.98,.94,.95},sign_bg={220,120,140},sign_fg={255,255,255},icon='cup'},{frame={.25,.45,.25},aw={{.3,.5,.3},{.92,.95,.88}},fascia={.94,.96,.9},sign_bg={60,110,60},sign_fg={250,250,240},icon='leaf'},{frame={.55,.35,.75},aw={{.55,.35,.75},{1,1,1}},fascia={.97,.95,.99},sign_bg={140,90,190},sign_fg={255,255,255},icon='cup'},{frame={.9,.5,.2},aw={{.9,.5,.2},{.98,.95,.9}},fascia={.98,.95,.9},sign_bg={230,130,50},sign_fg={255,255,255},icon='cup'}},
 bakery={{frame={.92,.86,.74},aw={{.75,.45,.25},{.97,.94,.86}},fascia={.62,.4,.22},sign_bg={120,72,40},sign_fg={250,236,200},icon='leaf',font='kai'},{frame={.95,.9,.86},aw={{.9,.6,.65},{1,1,1}},fascia={.95,.9,.86},sign_bg={232,160,170},sign_fg={255,255,255},icon='leaf'},{frame={.2,.3,.45},aw={{.25,.38,.55},{.95,.93,.9}},fascia={.2,.3,.45},sign_bg={40,62,96},sign_fg={250,232,196},icon='leaf',font='kai'},{frame={.85,.75,.55},aw={{.8,.7,.5},{.8,.7,.5}},fascia={.85,.75,.55},sign_bg={210,180,120},sign_fg={70,44,20},icon='leaf',font='kai'},{frame={.6,.25,.2},aw={{.6,.25,.2},{.96,.92,.86}},fascia={.6,.25,.2},sign_bg={140,60,46},sign_fg={250,236,210},icon='leaf',font='kai'},{frame={.95,.95,.95},aw={{.55,.75,.6},{1,1,1}},fascia={.95,.95,.95},sign_bg={110,170,130},sign_fg={255,255,255},icon='leaf'}},
 restaurant={{frame={.3,.18,.1},aw={{.6,.1,.1},{.6,.1,.1}},fascia={.3,.18,.1},sign_bg={60,36,20},sign_fg={248,226,180},icon='bowl',font='kai'},{frame={.12,.12,.14},aw={{.1,.25,.45},{.1,.25,.45}},fascia={.12,.12,.14},sign_bg={24,40,70},sign_fg={250,240,220},icon='bowl',font='kai'},{frame={.55,.38,.22},aw={{.85,.55,.2},{.85,.55,.2}},fascia={.55,.38,.22},sign_bg={210,140,60},sign_fg={60,30,10},icon='bowl',font='kai'},{frame={.2,.3,.22},aw={{.2,.4,.28},{.92,.9,.82}},fascia={.2,.3,.22},sign_bg={36,70,50},sign_fg={248,236,200},icon='bowl',font='kai'},{frame={.5,.1,.08},aw={{.5,.1,.08},{.95,.9,.85}},fascia={.5,.1,.08},sign_bg={120,24,20},sign_fg={250,220,150},icon='bowl',font='kai'},{frame={.35,.3,.25},aw={{.3,.3,.32},{.3,.3,.32}},fascia={.35,.3,.25},sign_bg={50,46,44},sign_fg={240,220,180},icon='bowl',font='kai'}},
 fruit={{frame={.2,.5,.25},aw={{.2,.55,.25},{1,1,1}},fascia={.96,.96,.92},sign_bg={40,130,60},sign_fg={255,255,255},icon='apple'},{frame={.9,.45,.1},aw={{.92,.48,.12},{1,.98,.92}},fascia={.98,.95,.88},sign_bg={236,120,30},sign_fg={255,255,255},icon='apple'},{frame={.75,.15,.15},aw={{.75,.15,.15},{1,1,1}},fascia={.97,.95,.93},sign_bg={190,40,40},sign_fg={255,255,255},icon='apple'},{frame={.95,.8,.2},aw={{.95,.8,.2},{.3,.6,.25}},fascia={.97,.96,.9},sign_bg={60,140,60},sign_fg={255,240,120},icon='apple'},{frame={.3,.25,.2},aw={{.4,.6,.3},{.95,.92,.82}},fascia={.3,.25,.2},sign_bg={70,56,40},sign_fg={250,236,190},icon='apple',font='kai'},{frame={.5,.7,.3},aw={{.5,.7,.3},{1,1,1}},fascia={.95,.97,.9},sign_bg={110,170,60},sign_fg={255,255,255},icon='apple'}},
 convenience={{frame={.93,.94,.94},aw={{.93,.94,.94},{.93,.94,.94}},fascia={1,1,1},band='band_conv',sign_bg={250,250,248},sign_fg={18,128,72},icon='bag'},{frame={.94,.94,.95},fascia={1,1,1},band='band_conv_blue',sign_bg={245,248,252},sign_fg={30,90,180},icon='bag'},{frame={.94,.94,.94},fascia={1,1,1},band='band_conv_red',sign_bg={250,246,244},sign_fg={200,40,40},icon='bag'},{frame={.93,.94,.94},fascia={1,1,1},band='band_conv_orange',sign_bg={252,248,240},sign_fg={230,110,20},icon='bag'},{frame={.93,.94,.94},fascia={1,1,1},band='band_conv',sign_bg={250,250,248},sign_fg={18,128,72},icon='bag'},{frame={.94,.94,.95},fascia={1,1,1},band='band_conv_blue',sign_bg={245,248,252},sign_fg={30,90,180},icon='bag'}},
 book={{frame={.22,.15,.1},aw={{.25,.2,.15},{.25,.2,.15}},fascia={.22,.15,.1},sign_bg={40,30,22},sign_fg={232,210,160},icon='book',font='kai'},{frame={.15,.25,.35},aw={{.2,.32,.45},{.92,.9,.86}},fascia={.15,.25,.35},sign_bg={30,50,70},sign_fg={236,224,196},icon='book',font='kai'},{frame={.55,.42,.28},aw={{.45,.3,.2},{.45,.3,.2}},fascia={.55,.42,.28},sign_bg={232,222,200},sign_fg={70,50,30},icon='book',font='kai'},{frame={.35,.12,.12},aw={{.4,.14,.14},{.94,.9,.84}},fascia={.35,.12,.12},sign_bg={80,26,26},sign_fg={240,220,180},icon='book',font='kai'},{frame={.2,.3,.2},aw={{.25,.38,.25},{.25,.38,.25}},fascia={.2,.3,.2},sign_bg={40,60,40},sign_fg={236,226,190},icon='book',font='kai'},{frame={.85,.82,.76},aw={{.6,.55,.45},{.95,.94,.9}},fascia={.85,.82,.76},sign_bg={250,248,240},sign_fg={50,50,50},icon='book',font='kai'}},
 pet={{frame={.95,.6,.25},aw={{.95,.6,.25},{1,1,1}},fascia={.98,.96,.9},sign_bg={240,150,60},sign_fg={255,255,255},icon='paw'},{frame={.35,.6,.75},aw={{.35,.6,.75},{1,1,1}},fascia={.96,.97,.99},sign_bg={80,150,190},sign_fg={255,255,255},icon='paw'},{frame={.5,.7,.4},aw={{.5,.7,.4},{1,1,1}},fascia={.96,.98,.94},sign_bg={110,170,90},sign_fg={255,255,255},icon='paw'},{frame={.8,.5,.6},aw={{.85,.55,.65},{1,1,1}},fascia={.99,.95,.96},sign_bg={210,120,150},sign_fg={255,255,255},icon='paw'},{frame={.45,.32,.22},aw={{.55,.4,.28},{.96,.92,.86}},fascia={.45,.32,.22},sign_bg={110,76,50},sign_fg={250,236,210},icon='paw'}},
 florist={{frame={.55,.4,.25},aw={{.48,.58,.44},{.48,.58,.44}},fascia={.9,.86,.76},sign_bg={240,232,214},sign_fg={46,84,52},icon='leaf',font='kai'},{frame={.95,.95,.94},aw={{.85,.55,.62},{1,1,1}},fascia={.95,.95,.94},sign_bg={230,150,170},sign_fg={255,255,255},icon='leaf'},{frame={.2,.3,.22},aw={{.25,.38,.28},{.25,.38,.28}},fascia={.2,.3,.22},sign_bg={36,60,44},sign_fg={240,226,196},icon='leaf',font='kai'},{frame={.6,.5,.7},aw={{.62,.52,.72},{1,1,1}},fascia={.97,.96,.99},sign_bg={150,120,180},sign_fg={255,255,255},icon='leaf'},{frame={.85,.7,.45},aw={{.9,.78,.5},{.9,.78,.5}},fascia={.95,.92,.84},sign_bg={220,190,120},sign_fg={60,50,30},icon='leaf',font='kai'},{frame={.55,.4,.25},aw={{.48,.58,.44},{.48,.58,.44}},fascia={.9,.86,.76},sign_bg={240,232,214},sign_fg={46,84,52},icon='leaf',font='kai'}},
 clothing={{frame={.1,.1,.1},aw={{.1,.1,.1},{.1,.1,.1}},fascia={.1,.1,.1},sign_bg={20,20,20},sign_fg={245,245,245},icon='hanger'},{frame={.92,.9,.86},aw={{.7,.62,.5},{.7,.62,.5}},fascia={.92,.9,.86},sign_bg={240,236,228},sign_fg={60,50,40},icon='hanger'},{frame={.2,.25,.4},aw={{.2,.25,.4},{.92,.92,.95}},fascia={.2,.25,.4},sign_bg={36,46,80},sign_fg={250,250,250},icon='hanger'},{frame={.6,.2,.25},aw={{.6,.2,.25},{.6,.2,.25}},fascia={.6,.2,.25},sign_bg={150,46,56},sign_fg={255,240,230},icon='hanger'},{frame={.45,.5,.42},aw={{.5,.55,.46},{.94,.94,.9}},fascia={.45,.5,.42},sign_bg={100,110,90},sign_fg={250,248,240},icon='hanger'},{frame={.95,.95,.95},aw={{.15,.15,.15},{.95,.95,.95}},fascia={.95,.95,.95},sign_bg={250,250,250},sign_fg={20,20,20},icon='hanger'}},
 barber={{frame={.12,.15,.2},fascia={.12,.15,.2},sign_bg={26,34,48},sign_fg={240,240,240},icon='scissors'},{frame={.92,.92,.9},fascia={.92,.92,.9},sign_bg={245,245,242},sign_fg={30,40,60},icon='scissors'},{frame={.5,.12,.12},fascia={.5,.12,.12},sign_bg={130,30,30},sign_fg={250,240,230},icon='scissors'},{frame={.25,.35,.3},fascia={.25,.35,.3},sign_bg={50,76,64},sign_fg={248,240,220},icon='scissors'},{frame={.6,.5,.4},fascia={.6,.5,.4},sign_bg={150,124,96},sign_fg={255,250,240},icon='scissors'},{frame={.12,.15,.2},fascia={.12,.15,.2},sign_bg={26,34,48},sign_fg={240,240,240},icon='scissors'}},
 music={{frame={.08,.08,.1},aw={{.6,.1,.1},{.6,.1,.1}},fascia={.08,.08,.1},sign_bg={18,18,22},sign_fg={240,60,60},icon='note'},{frame={.25,.18,.12},aw={{.3,.22,.15},{.3,.22,.15}},fascia={.25,.18,.12},sign_bg={50,36,24},sign_fg={240,200,120},icon='note'},{frame={.15,.2,.35},aw={{.95,.75,.2},{.15,.2,.35}},fascia={.15,.2,.35},sign_bg={30,40,80},sign_fg={250,200,60},icon='note'},{frame={.08,.08,.1},aw={{.08,.08,.1},{.08,.08,.1}},fascia={.08,.08,.1},sign_bg={20,20,24},sign_fg={120,220,240},icon='note'},{frame={.4,.1,.35},aw={{.4,.1,.35},{.4,.1,.35}},fascia={.4,.1,.35},sign_bg={100,26,90},sign_fg={255,230,250},icon='note'},{frame={.25,.18,.12},aw={{.3,.22,.15},{.3,.22,.15}},fascia={.25,.18,.12},sign_bg={50,36,24},sign_fg={240,200,120},icon='note'}},
 game={{frame={.15,.3,.6},aw={{.95,.75,.15},{.15,.3,.6}},fascia={.15,.3,.6},sign_bg={30,70,150},sign_fg={255,220,60},icon='dice'},{frame={.55,.12,.15},aw={{.55,.12,.15},{1,1,1}},fascia={.55,.12,.15},sign_bg={140,30,40},sign_fg={255,255,255},icon='dice'},{frame={.2,.45,.3},aw={{.2,.45,.3},{.95,.9,.6}},fascia={.2,.45,.3},sign_bg={40,110,70},sign_fg={255,240,140},icon='dice'},{frame={.3,.2,.45},aw={{.3,.2,.45},{.95,.8,.3}},fascia={.3,.2,.45},sign_bg={76,50,120},sign_fg={255,220,90},icon='dice'}},
 camera={{frame={.1,.1,.1},aw={{.12,.12,.12},{.12,.12,.12}},fascia={.1,.1,.1},sign_bg={20,20,20},sign_fg={250,180,40},icon='camera'},{frame={.75,.72,.68},aw={{.3,.3,.3},{.3,.3,.3}},fascia={.75,.72,.68},sign_bg={60,60,60},sign_fg={250,250,250},icon='camera'},{frame={.3,.2,.12},aw={{.35,.24,.15},{.92,.88,.8}},fascia={.3,.2,.12},sign_bg={70,46,28},sign_fg={240,220,170},icon='camera',font='kai'},{frame={.15,.25,.3},aw={{.18,.3,.36},{.18,.3,.36}},fascia={.15,.25,.3},sign_bg={30,56,70},sign_fg={240,240,230},icon='camera'}},
 bike={{frame={.85,.25,.1},aw={{.85,.25,.1},{.15,.15,.15}},fascia={.15,.15,.15},sign_bg={30,30,30},sign_fg={240,110,40},icon='bike'},{frame={.15,.4,.7},aw={{.15,.4,.7},{1,1,1}},fascia={.95,.95,.95},sign_bg={40,100,180},sign_fg={255,255,255},icon='bike'},{frame={.3,.5,.2},aw={{.3,.5,.2},{.95,.95,.9}},fascia={.3,.5,.2},sign_bg={70,120,50},sign_fg={255,255,240},icon='bike'},{frame={.2,.2,.22},aw={{.95,.8,.1},{.2,.2,.22}},fascia={.2,.2,.22},sign_bg={36,36,40},sign_fg={250,210,40},icon='bike'}},
 drug={{frame={.95,.96,.97},fascia={1,1,1},band='band_drug_green',sign_bg={250,252,250},sign_fg={30,150,90},icon='cross'},{frame={.95,.96,.97},fascia={1,1,1},band='band_drug_blue',sign_bg={248,250,254},sign_fg={30,110,200},icon='cross'},{frame={.95,.96,.97},fascia={1,1,1},band='band_drug_pink',sign_bg={254,248,250},sign_fg={220,70,130},icon='cross'},{frame={.95,.96,.97},fascia={1,1,1},band='band_drug_green',sign_bg={250,252,250},sign_fg={30,150,90},icon='cross'}},
 laundry={{frame={.1,.36,.68},aw={{.13,.4,.7},{.94,.96,.99}},fascia={.95,.96,.97},sign_bg={28,96,176},sign_fg={255,255,255},icon='bubble'},{frame={.15,.6,.6},aw={{.15,.6,.6},{1,1,1}},fascia={.95,.97,.97},sign_bg={30,150,150},sign_fg={255,255,255},icon='bubble'},{frame={.95,.95,.96},aw={{.4,.7,.95},{1,1,1}},fascia={.95,.95,.96},sign_bg={90,170,230},sign_fg={255,255,255},icon='bubble'},{frame={.6,.75,.3},aw={{.6,.75,.3},{1,1,1}},fascia={.96,.98,.94},sign_bg={130,180,60},sign_fg={255,255,255},icon='bubble'}},
 lottery={{frame={.7,.08,.1},aw={{.75,.1,.1},{.95,.78,.2}},fascia={.7,.08,.1},sign_bg={170,20,24},sign_fg={255,214,60},icon='star'},{frame={.7,.08,.1},aw={{.95,.78,.2},{.75,.1,.1}},fascia={.95,.78,.2},sign_bg={250,200,40},sign_fg={170,20,24},icon='star'},{frame={.12,.12,.4},aw={{.15,.15,.5},{.95,.78,.2}},fascia={.12,.12,.4},sign_bg={30,30,110},sign_fg={255,214,60},icon='star'}},
}
local aw={}
for ty,list in pairs(P)do for i,v in ipairs(list)do if v.aw then v.awning=ty..'_aw'..(i-1);aw[v.awning]={v.aw[1],v.aw[2]}end end end
aw.band_conv_blue={{1,1,1},{1,1,1}};aw.band_conv_red={{1,1,1},{1,1,1}};aw.band_conv_orange={{1,1,1},{1,1,1}};aw.band_drug_green={{1,1,1},{1,1,1}};aw.band_drug_blue={{1,1,1},{1,1,1}};aw.band_drug_pink={{1,1,1},{1,1,1}}
local p=assert(io.popen('python -I -','w'))
assert(p:write('OUT='..string.format('%q',out)..'\nIDS='..j.encode(ids)..'\nPALETTES='..string.format('%q',j.encode(P))..'\nAWNINGS='..string.format('%q',j.encode(aw))..'\nSAMPLE_TEX='..string.format('%q',prod..'/shop-samples-v1/textures')..'\n'..tex))
assert(p:close())
-- band textures for convenience / drugstore variants (colour stripes on white)
local bands=[====[
from PIL import Image,ImageDraw
from pathlib import Path
T=Path(OUT)/'textures'
for n,a,b in [('band_conv_blue',(30,90,180),(250,200,40)),('band_conv_red',(200,40,40),(250,250,250)),('band_conv_orange',(230,110,20),(30,90,60)),('band_drug_green',(30,150,90),(250,250,250)),('band_drug_blue',(30,110,200),(120,200,240)),('band_drug_pink',(220,70,130),(250,200,220))]:
 im=Image.new('RGB',(512,512),(255,255,255));d=ImageDraw.Draw(im);d.rectangle((0,200,511,260),fill=a);d.rectangle((0,262,511,300),fill=b);im.save(T/(n+'.png'))
]====]
p=assert(io.popen('python -I -','w'));assert(p:write('OUT='..string.format('%q',out)..'\n'..bands));assert(p:close())
-- 2. Blender
local code=dofile('Tools/street_city_shop_refits_blender.lua')
local path=out..'/build-payload.json';local fb=assert(io.open(path,'wb'));fb:write(j.encode({out=out,code=code,ids=ids,palettes=P}));fb:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/build.log" 2>&1"'))
print('Shop refits authored ('..#ids..'); see '..out..'/build.log')
