-- Shop-street sample shops (Docs/STREET_CITY_SHOP_STREET_FIX_PLAN_20261025.md): for each sample a "refit" GLB in the
-- building frame of its source floor GLB (front facade at y=-H, door from the source entry frame): new glass storefront,
-- fascia + localized sign boards (horizontal and blade), awning, street-front display, ground-floor fixtures for the shop
-- type and upper-floor attachments. The existing UE floor mesh keeps its depth repairs; a native job cuts the old front
-- wall / props out of it (cut boxes in build.json) and the refit is placed as its own actor on the same transform.
-- Usage: lua Tools/build_street_city_shop_samples.lua [S01 S26 ...]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/shop-samples-v1'
local ids={};for i=1,#arg do ids[#ids+1]=arg[i]end;if #ids==0 then ids={'S01','S26','S09','S17'}end
-- 1. textures (system Python + PIL): sign boards in three languages and procedural surfaces
local tex=[====[
import json,math,random
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageFilter
O=Path(OUT);T=O/'textures';T.mkdir(parents=True,exist_ok=True)
cat=json.loads(Path('C:/portable/OpenKoikatsu/output/street-social-city-production/localization-v1/catalogue.json').read_text('utf8'))
cat=cat.get('entries',cat)
F='C:/Windows/Fonts/'
FONTS={'kai':{'zh-Hant':F+'kaiu.ttf','zh-Hans':F+'simkai.ttf','en':F+'georgiab.ttf'},'sans':{'zh-Hant':F+'msjhbd.ttc','zh-Hans':F+'msyhbd.ttc','en':F+'segoeuib.ttf'},'round':{'zh-Hant':F+'msjhbd.ttc','zh-Hans':F+'msyhbd.ttc','en':F+'segoeuib.ttf'}}
STYLE={
 'S01':dict(font='kai',bg=(22,52,38),bg2=(14,36,26),fg=(222,184,104),edge=(196,156,82),icon='cup'),
 'S26':dict(font='sans',bg=(250,250,248),bg2=(236,238,236),fg=(18,128,72),edge=(18,128,72),icon='bag',stripes=[(18,128,72),(238,120,32)]),
 'S09':dict(font='kai',bg=(240,232,214),bg2=(226,216,194),fg=(46,84,52),edge=(120,140,96),icon='leaf'),
 'S17':dict(font='round',bg=(28,96,176),bg2=(18,70,140),fg=(255,255,255),edge=(220,236,255),icon='bubble'),
}
def C(c):return tuple(int(v) for v in c)
def board(w,h,s):
 im=Image.new('RGB',(w,h),C(s['bg']));d=ImageDraw.Draw(im)
 for y in range(h):d.line((0,y,w,y),fill=tuple(int(a+(b-a)*y/h) for a,b in zip(s['bg'],s['bg2'])))
 if 'stripes' in s:
  for i,c in enumerate(s['stripes']):d.rectangle((0,h-int(h*.16)+i*int(h*.08),w,h-int(h*.16)+(i+1)*int(h*.08)),fill=c)
 m=int(min(w,h)*.05);d.rectangle((m,m,w-m,h-m),outline=s['edge'],width=max(4,m//3));return im,d
def icon(d,kind,cx,cy,r,col):
 if kind=='cup':d.rounded_rectangle((cx-r*.6,cy-r*.3,cx+r*.5,cy+r*.7),radius=r*.2,outline=col,width=max(3,int(r*.12)));d.arc((cx+r*.3,cy-r*.05,cx+r*.85,cy+r*.45),-90,90,fill=col,width=max(3,int(r*.12)));[d.arc((cx-r*.35+k*r*.3,cy-r*.95,cx-r*.05+k*r*.3,cy-r*.35),180,360,fill=col,width=max(2,int(r*.08))) for k in range(3)]
 elif kind=='bag':d.rounded_rectangle((cx-r*.6,cy-r*.35,cx+r*.6,cy+r*.75),radius=r*.15,fill=col);d.arc((cx-r*.35,cy-r*.85,cx+r*.35,cy-r*.05),180,360,fill=col,width=max(3,int(r*.14)))
 elif kind=='leaf':
  for a in (-35,0,35):
   t=math.radians(a-90);x2,y2=cx+r*math.cos(t),cy+r*math.sin(t)+r*.4;d.ellipse((min(cx,x2)-r*.22,min(cy+r*.4,y2)-r*.1,max(cx,x2)+r*.22,max(cy+r*.4,y2)+r*.1),fill=col)
 elif kind=='bubble':
  for (ox,oy,rr) in [(-.4,.2,.45),(.3,-.25,.35),(.45,.45,.22),(-.1,-.6,.18)]:d.ellipse((cx+ox*r-rr*r,cy+oy*r-rr*r,cx+ox*r+rr*r,cy+oy*r+rr*r),outline=col,width=max(3,int(r*.1)))
def fit(d,text,path,maxw,maxh,start):
 size=start
 while size>10:
  f=ImageFont.truetype(path,size);b=d.textbbox((0,0),text,font=f)
  if b[2]-b[0]<=maxw and b[3]-b[1]<=maxh:return f,b
  size-=4
 return f,b
def horizontal(sid,loc,text,s):
 w,h=2048,512;im,d=board(w,h,s);ic=s['icon'];r=h*.28
 icon(d,ic,int(w*.1),int(h*.48),r,s['fg']);icon(d,ic,int(w*.9),int(h*.48),r,s['fg'])
 f,b=fit(d,text,FONTS[s['font']][loc],int(w*.68),int(h*(.5 if 'stripes' in s else .6)),300)
 tx=(w-(b[2]-b[0]))/2-b[0];ty=(h*(.42 if 'stripes' in s else .5))-(b[3]-b[1])/2-b[1]
 d.text((tx+5,ty+6),text,font=f,fill=tuple(max(0,c-90) for c in s['bg']));d.text((tx,ty),text,font=f,fill=s['fg']);return im
def vertical(sid,loc,text,s):
 w,h=512,2048;im,d=board(w,h,s);icon(d,s['icon'],w//2,int(h*.09),w*.22,s['fg'])
 if loc=='en':
  tmp=Image.new('RGBA',(h,w),(0,0,0,0));dd=ImageDraw.Draw(tmp);f,b=fit(dd,text,FONTS[s['font']][loc],int(h*.74),int(w*.55),220)
  dd.text(((h-(b[2]-b[0]))/2-b[0]+h*.06,(w-(b[3]-b[1]))/2-b[1]),text,font=f,fill=s['fg']);tmp=tmp.rotate(90,expand=True);im.paste(tmp,(0,0),tmp)
 else:
  chars=list(text);n=len(chars);cell=min(w*.62,(h*.78)/n);f=ImageFont.truetype(FONTS[s['font']][loc],int(cell*.92));y0=h*.19+(h*.78-cell*n)/2
  for i,ch in enumerate(chars):
   b=d.textbbox((0,0),ch,font=f);d.text(((w-(b[2]-b[0]))/2-b[0],y0+i*cell+(cell-(b[3]-b[1]))/2-b[1]),ch,font=f,fill=s['fg'])
 return im
names={}
for sid in IDS:
 tr=cat['building.'+sid]['translations'];names[sid]=tr;s=STYLE[sid]
 for loc in ('zh-Hant','zh-Hans','en'):
  horizontal(sid,loc,tr[loc],s).save(T/f'{sid}-H-{loc}.png');vertical(sid,loc,tr[loc],s).save(T/f'{sid}-V-{loc}.png')
r=random.Random(7)
def save(n,im):im.save(T/(n+'.png'))
# stripes for awnings
for n,a,b in [('awning_green_cream',(30,84,58),(236,226,200)),('awning_sage',(122,148,112),(122,148,112)),('band_conv',(255,255,255),(255,255,255)),('awning_blue',(32,100,178),(240,246,252))]:
 im=Image.new('RGB',(512,512),a);d=ImageDraw.Draw(im)
 if a!=b:
  for k in range(0,512,128):d.rectangle((k+64,0,k+127,511),fill=b)
 if n=='band_conv':d.rectangle((0,200,511,260),fill=(18,128,72));d.rectangle((0,262,511,300),fill=(238,120,32))
 save(n,im)
# packaged goods on shelves (convenience / drugstore gondolas)
im=Image.new('RGB',(1024,1024),(235,235,232));d=ImageDraw.Draw(im)
pal=[(220,40,40),(250,200,40),(40,120,220),(40,170,90),(240,120,30),(150,60,170),(250,250,250),(30,30,30),(230,90,140),(90,200,210)]
for row in range(5):
 y0=row*204+18;d.rectangle((0,y0+170,1023,y0+186),fill=(200,200,198))
 x=4
 while x<1010:
  wdt=r.randint(34,70);hgt=r.randint(90,165);c=r.choice(pal);d.rectangle((x,y0+170-hgt,x+wdt-4,y0+170),fill=c);d.rectangle((x+6,y0+170-hgt+16,x+wdt-10,y0+170-hgt+38),fill=tuple(min(255,v+70) for v in c));x+=wdt
save('goods_shelf',im)
# drinks cooler fronts
im=Image.new('RGB',(512,1024),(196,224,236));d=ImageDraw.Draw(im)
for row in range(6):
 y0=row*170+14;d.rectangle((0,y0+150,511,y0+158),fill=(150,160,170))
 for k in range(9):c=r.choice(pal);x=8+k*56;d.rounded_rectangle((x,y0+30,x+40,y0+150),radius=10,fill=c);d.rectangle((x+12,y0+14,x+28,y0+32),fill=(220,220,220))
d.rectangle((0,0,511,1023),outline=(170,180,190),width=10);save('cooler_front',im)
# book spines
im=Image.new('RGB',(1024,1024),(110,74,46));d=ImageDraw.Draw(im)
bp=[(130,30,30),(30,60,110),(40,90,60),(190,150,70),(80,40,90),(200,190,170),(150,90,40),(60,60,60)]
for row in range(4):
 y0=row*256+20;x=6
 while x<1010:
  wdt=r.randint(16,34);hgt=r.randint(170,226);c=r.choice(bp);d.rectangle((x,y0+226-hgt,x+wdt-2,y0+226),fill=c);d.line((x+3,y0+226-hgt+20,x+wdt-5,y0+226-hgt+20),fill=(220,200,140),width=3);x+=wdt
 d.rectangle((0,y0+226,1023,y0+240),fill=(88,58,36))
save('book_spines',im)
# chalk menu
im=Image.new('RGB',(1024,512),(34,40,36));d=ImageDraw.Draw(im);fz=ImageFont.truetype(F+'kaiu.ttf',54);fe=ImageFont.truetype(F+'georgia.ttf',36)
for i,(a,b) in enumerate([('美式咖啡','90'),('拿鐵','120'),('卡布奇諾','120'),('手沖單品','150'),('今日蛋糕','110')]):
 d.text((60,40+i*88),a,font=fz,fill=(240,236,224));d.text((860,52+i*88),b,font=fe,fill=(240,210,120));d.line((360,78+i*88,830,78+i*88),fill=(120,120,110),width=2)
d.rectangle((8,8,1015,503),outline=(160,120,70),width=14);save('chalk_menu',im)
# warm brick feature wall and laundry tiles
im=Image.new('RGB',(1024,1024),(150,150,146));d=ImageDraw.Draw(im)
for rr in range(0,1024,64):
 off=64 if (rr//64)%2 else 0
 for cc in range(-128,1024,128):base=r.choice([(150,76,54),(166,88,62),(138,70,50),(170,100,72)]);d.rectangle((cc+off+4,rr+4,cc+off+124,rr+60),fill=base)
save('brick_warm',im.filter(ImageFilter.GaussianBlur(1)))
im=Image.new('RGB',(1024,1024),(220,226,232));d=ImageDraw.Draw(im)
for rr in range(0,1024,128):
 for cc in range(0,1024,128):d.rectangle((cc+3,rr+3,cc+125,rr+125),fill=(232,238,244) if (rr//128+cc//128)%2 else (214,226,240))
save('tile_laundry',im)
im=Image.new('RGB',(1024,1024),(235,230,220));d=ImageDraw.Draw(im)
for k in range(0,1024,32):d.line((k,0,k,1023),fill=(220,212,200),width=6)
save('wood_slat_light',im)
(O/'names.json').write_text(json.dumps(names,ensure_ascii=False,indent=1),'utf8');print('textures ok',len(IDS))
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write('OUT='..string.format('%q',out)..'\nIDS='..j.encode(ids)..'\n'..tex));assert(p:close())
-- 2. Blender refit
local code=[====[
import bpy,json,math,hashlib
from mathutils import Vector
from pathlib import Path
O=Path(TASK['out']);T=O/'textures';SRC=Path('C:/portable/OpenKoikatsu/output/street-social-city-production')
NAMES=json.loads((O/'names.json').read_text('utf8'))
MATS={};NEW=[]
def mat(key,color=(.8,.8,.8),rough=.5,metal=0.,emit=0.,tex=None,alpha=1.,emit_tex=False,tile=1.):
 if key in MATS:return MATS[key]
 m=bpy.data.materials.new(key);m.use_nodes=True;nt=m.node_tree;p=nt.nodes['Principled BSDF']
 p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if tex:
  im=bpy.data.images.load(str(T/(tex+'.png')),check_existing=True);n=nt.nodes.new('ShaderNodeTexImage');n.image=im;nt.links.new(n.outputs['Color'],p.inputs['Base Color'])
  if tile!=1.:
   mp=nt.nodes.new('ShaderNodeMapping');tc=nt.nodes.new('ShaderNodeTexCoord');mp.inputs['Scale'].default_value=(tile,tile,1);nt.links.new(tc.outputs['UV'],mp.inputs['Vector']);nt.links.new(mp.outputs['Vector'],n.inputs['Vector'])
  if emit_tex:nt.links.new(n.outputs['Color'],p.inputs['Emission Color'])
 if emit:
  if not (tex and emit_tex):p.inputs['Emission Color'].default_value=(*color,1)
  p.inputs['Emission Strength'].default_value=emit
 if alpha<1:p.inputs['Alpha'].default_value=alpha;m.blend_method='BLEND' if hasattr(m,'blend_method') else None
 MATS[key]=m;return m
def reg(o,m):
 if m:o.data.materials.append(m)
 NEW.append(o);return o
def box(name,c,s,m,rz=0.):
 bpy.ops.mesh.primitive_cube_add(size=1,location=c);o=bpy.context.object;o.name=name;o.scale=s;o.rotation_euler.z=rz;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);return reg(o,m)
def bb(name,x0,x1,y0,y1,z0,z1,m):return box(name,((x0+x1)/2,(y0+y1)/2,(z0+z1)/2),(abs(x1-x0),abs(y1-y0),abs(z1-z0)),m)
def cyl(name,c,r,h,m,n=24,r2=None):
 bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=c);o=bpy.context.object;o.name=name;return reg(o,m)
def sph(name,c,r,m,sc=(1,1,1)):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=r,location=c);o=bpy.context.object;o.name=name;o.scale=sc;bpy.ops.object.transform_apply(scale=True);return reg(o,m)
def quad(name,corners,m,uv=((0,0),(1,0),(1,1),(0,1))):
 me=bpy.data.meshes.new(name);me.from_pydata([Vector(c) for c in corners],[],[(0,1,2,3)]);me.uv_layers.new(name='UVMap')
 for i,l in enumerate(me.loops):me.uv_layers[0].data[i].uv=uv[i]
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);return reg(o,m)
def face_front(name,x0,x1,z0,z1,y,m):return quad(name,[(x0,y,z0),(x1,y,z0),(x1,y,z1),(x0,y,z1)],m)        # faces -Y (street)
def face_x(name,x,y0,y1,z0,z1,m,sign):  # faces +X if sign>0
 return quad(name,[(x,y0,z0),(x,y1,z0),(x,y1,z1),(x,y0,z1)] if sign>0 else [(x,y1,z0),(x,y0,z0),(x,y0,z1),(x,y1,z1)],m)
def bounds(o):
 v=[o.matrix_world@Vector(c) for c in o.bound_box];return [min(p[i] for p in v) for i in range(3)],[max(p[i] for p in v) for i in range(3)]
def dup(src,name,loc,rz=0.,s=1.):
 o=src.copy();o.data=src.data.copy();bpy.context.collection.objects.link(o);o.name=name
 mn,mx=bounds(src);c=Vector(((mn[0]+mx[0])/2,(mn[1]+mx[1])/2,mn[2]))
 o.matrix_world=src.matrix_world.copy();bpy.context.view_layer.update()
 # move so that the footprint centre/base sits at the origin, rotate, scale, then place
 for v in o.data.vertices:pass
 o.data.transform(o.matrix_world);o.matrix_world.identity();o.data.transform(__import__('mathutils').Matrix.Translation(-c))
 o.data.transform(__import__('mathutils').Matrix.Rotation(rz,4,'Z'));o.data.transform(__import__('mathutils').Matrix.Scale(s,4));o.location=loc;bpy.context.view_layer.update()
 if len(o.data.polygons)>4000 and 'flower' in name.lower():  # bouquet copies: keep the silhouette, drop the count
  d=o.modifiers.new('dec','DECIMATE');d.ratio=1200/len(o.data.polygons);bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=d.name)
 NEW.append(o);return o
# ---------------- common storefront -----------------
def storefront(sp,G):
 H,dx=G['H'],G['dx'];y0=-H;frame=sp['frame'];glass=mat('ShopV1_glass',(.55,.66,.7),rough=.02,alpha=.12);kick=sp.get('kick',frame)
 zt=sp.get('glass_top',2.6)
 for s in (-1,1):bb('Storefront pilaster',s*5.3,s*5.8,y0-.04,y0+.2,0,3.62,frame)
 bb('Storefront fascia',-5.3,5.3,y0-.04,y0+.2,zt+.08,3.62,sp.get('fascia',frame));bb('Storefront transom',-5.3,5.3,y0-.02,y0+.18,zt,zt+.08,frame)
 bb('Storefront fascia interior',-5.3,5.3,y0+.2,y0+.24,zt+.08,3.5,mat('ShopV1_interior_white',(.92,.91,.88),rough=.7))
 spans=[(-5.3,dx-1.24),(dx+1.24,5.3)]
 for a,b in spans:
  if b-a<.2:continue
  kz=sp.get('kick_h',.45);bb('Storefront kick',a,b,y0-.02,y0+.18,0,kz,kick)
  bb('Storefront glass',a,b,y0+.08,y0+.1,kz,zt,glass)
  n=max(1,int(math.ceil((b-a)/1.6)))
  for k in range(n+1):x=a+(b-a)*k/n;bb('Storefront mullion',x-.035,x+.035,y0-.03,y0+.17,kz,zt,frame)
 for s in (-1,1):bb('Door jamb',dx+s*1.24-.04,dx+s*1.24+.04,y0-.03,y0+.2,0,zt,frame)
 bb('Door threshold',dx-1.2,dx+1.2,y0-.05,y0+.22,0,.012,mat('ShopV1_steel',(.7,.7,.72),rough=.25,metal=1.))
 for s in (-1,1):  # glass leaves standing open inward along the jambs
  x=dx+s*1.18;bb('Door leaf frame',x-.03,x+.03,y0+.22,y0+1.38,0,2.38,frame) if False else None
  bb('Door leaf stile',x-.025,x+.025,y0+.22,y0+.28,0,2.38,frame);bb('Door leaf stile',x-.025,x+.025,y0+1.32,y0+1.38,0,2.38,frame)
  bb('Door leaf rail',x-.025,x+.025,y0+.22,y0+1.38,0,.1,frame);bb('Door leaf rail',x-.025,x+.025,y0+.22,y0+1.38,2.3,2.38,frame)
  bb('Door leaf glass',x-.008,x+.008,y0+.28,y0+1.32,.1,2.3,glass);bb('Door pull',x-s*.05,x-s*.03,y0+1.15,y0+1.19,.8,1.5,mat('ShopV1_steel',(.7,.7,.72),rough=.25,metal=1.))
 # horizontal sign: the approved RomanceName_<id> 3D name plaque (dark ground, lit letters) is the shop's name sign;
 # a board is only authored when a spec explicitly asks for one
 if not sp.get('own_name_board'):return
 w=sp.get('sign_w',4.0);sx=sp.get('sign_x',0.);z0,z1=zt+.18,3.48
 bb('Sign board',sx-w/2-.06,sx+w/2+.06,y0-.12,y0-.04,z0-.06,z1+.06,sp.get('sign_frame',frame))
 face_front('Sign face',sx-w/2,sx+w/2,z0,z1,y0-.121,mat('ShopSign_'+G['id']+'_H',(1,1,1),rough=.5,tex=G['id']+'-H-zh-Hant',emit=sp.get('sign_glow',1.5),emit_tex=True))
 G['sign']=dict(slot='ShopSign_'+G['id']+'_H',glow=sp.get('sign_glow',1.5))
def awning(sp,G,x0,x1,m,depth=1.15,drop=.32,valance=.22):
 H=G['H'];zt=sp.get('glass_top',2.6)+.06;y0=-H-.05
 quad('Awning',[(x0,y0,zt),(x1,y0,zt),(x1,y0-depth,zt-drop),(x0,y0-depth,zt-drop)],m,uv=((0,0),((x1-x0)/1.2,0),((x1-x0)/1.2,1),(0,1)))
 quad('Awning under',[(x0,y0-depth,zt-drop-.002),(x1,y0-depth,zt-drop-.002),(x1,y0,zt-.002),(x0,y0,zt-.002)],m,uv=((0,1),((x1-x0)/1.2,1),((x1-x0)/1.2,0),(0,0)))
 face_front('Awning valance',x0,x1,zt-drop-valance,zt-drop,y0-depth-.003,m)
 quad('Awning valance back',[(x1,y0-depth+.003,zt-drop-valance),(x0,y0-depth+.003,zt-drop-valance),(x0,y0-depth+.003,zt-drop),(x1,y0-depth+.003,zt-drop)],m)
 for x in (x0+.05,x1-.05):
  b=bb('Awning arm',x-.015,x+.015,y0-depth,y0,zt-drop-.02,zt-drop+.01,mat('ShopV1_black_metal',(.04,.04,.04),rough=.4,metal=.8));
def blade(sp,G):
 H,dx=G['H'],G['dx'];x=5.05 if dx<0 else -5.05;y0=-H;frame=sp.get('sign_frame',sp['frame'])
 z0,z1=4.15,6.95;yA,yB=y0-.22,y0-1.02
 bb('Blade sign frame',x-.07,x+.07,yB-.04,yA+.04,z0-.04,z1+.04,frame)
 m=mat('ShopSign_'+G['id']+'_V',(1,1,1),rough=.5,tex=G['id']+'-V-zh-Hant',emit=sp.get('sign_glow',1.5),emit_tex=True)
 quad('Blade face +X',[(x+.072,yA,z0),(x+.072,yB,z0),(x+.072,yB,z1),(x+.072,yA,z1)],m)
 quad('Blade face -X',[(x-.072,yB,z0),(x-.072,yA,z0),(x-.072,yA,z1),(x-.072,yB,z1)],m)
 for z in (z0+.3,z1-.3):bb('Blade bracket',x-.03,x+.03,y0-.24,y0+.01,z-.03,z+.03,mat('ShopV1_black_metal',(.04,.04,.04),rough=.4,metal=.8))
 G['blade']=dict(slot='ShopSign_'+G['id']+'_V',glow=sp.get('sign_glow',1.5))
def ac_units(G,xs,floors=(3.8,7.3)):
 H=G['H'];body=mat('ShopV1_ac',(.86,.87,.85),rough=.5);grill=mat('ShopV1_ac_grill',(.18,.19,.2),rough=.6)
 for fz in floors:
  for x in xs:
   bb('AC unit',x-.42,x+.42,-H-.36,-H-.06,fz+.18,fz+.74,body);cyl('AC fan grill',(x+.1,-H-.365,fz+.46),.2,.01,grill).rotation_euler.x=math.pi/2
   for s in (-1,1):bb('AC bracket',x+s*.35-.02,x+s*.35+.02,-H-.4,-H,fz+.14,fz+.18,mat('ShopV1_black_metal',(.04,.04,.04),rough=.4,metal=.8))
def flower_box(G,x0,x1,z,flowers):
 H=G['H'];bb('Window flower box',x0,x1,-H-.36,-H-.04,z,z+.22,mat('ShopV1_planter_wood',(.45,.3,.18),rough=.7))
 n=int((x1-x0)/.18)
 for k in range(n):sph('Box flower',(x0+.1+k*(x1-x0-.2)/max(1,n-1),-H-.2,z+.3),.11,flowers[k%len(flowers)])
def plant(name,x,y,h=1.1,pot=None):
 pot=pot or mat('ShopV1_pot',(.3,.24,.2),rough=.6);cyl(name+' pot',(x,y,.22),.24,.44,pot,r2=.2);leaf=mat('ShopV1_leaf',(.16,.4,.16),rough=.6)
 for k in range(9):a=k*2.39;sph(name+' leaf',(x+.18*math.cos(a)*(k%3+1)/3,y+.18*math.sin(a)*(k%3+1)/3,.5+h*.35+.1*(k%4)),.2,leaf,(1.3,.5,.55)).rotation_euler.z=a
def pendant(x,y,shade,h=3.5,drop=1.0):
 cyl('Pendant cord',(x,y,h-drop/2),.006,drop,mat('ShopV1_black_metal',(.04,.04,.04),rough=.4,metal=.8),n=6);cyl('Pendant shade',(x,y,h-drop-.08),.2,.18,shade,r2=.05)
# --------------- per-shop interiors -----------------
def shop_S01(G):  # coffee + books: keep the counters/espresso/tables; add book wall, pendants, menu, plants, terrace
 H,dx=G['H'],G['dx'];sp=dict(frame=mat('ShopV1_S01_green',(.05,.17,.11),rough=.35),sign_frame=mat('ShopV1_brass',(.75,.56,.24),rough=.3,metal=1.),sign_w=4.2,sign_x=1.4,sign_glow=4.0,fascia=mat('ShopV1_S01_green',(.05,.17,.11),rough=.35))
 storefront(sp,G);awning(sp,G,dx+1.35,5.25,mat('ShopV1_S01_awning',(1,1,1),rough=.85,tex='awning_green_cream'))
 blade(sp,G);ac_units(G,[3.0],floors=(3.8,))
 brass=mat('ShopV1_brass',(.75,.56,.24),rough=.3,metal=1.);wood=mat('ShopV1_walnut',(.22,.13,.07),rough=.45)
 # book wall on the right side wall (x=+5.8 inner face 5.6)
 bb('Bookcase carcass',5.25,5.6,-H+1.0,-2.7,0,2.7,wood);face_x('Bookcase spines',5.249,-H+1.05,-2.75,.1,2.6,mat('ShopV1_books',(1,1,1),rough=.8,tex='book_spines'),-1)
 bb('Bookcase ladder rail',5.12,5.15,-H+1.0,-2.7,2.45,2.48,brass)
 bb('Menu board',-5.79,-5.74,-7.6,-5.6,1.75,2.75,mat('ShopV1_menu_frame',(.3,.2,.1),rough=.5));face_x('Menu chalk',-5.735,-7.5,-5.7,1.82,2.68,mat('ShopV1_chalk_menu',(1,1,1),rough=.9,tex='chalk_menu',emit=.15,emit_tex=True),1)
 shade=mat('ShopV1_pendant_glow',(1.,.78,.5),emit=4.)
 for x in (.9,2.9):
  for y in (-6.8,-4.2):pendant(x,y,shade)
 plant('Window plant',4.7,-H+.75,1.3);plant('Window plant',-5.15,-H+.75,1.0)
 # street terrace (outside, clear of the door path)
 tbl=mat('ShopV1_bistro',(.08,.08,.08),rough=.4,metal=.6);seat=mat('ShopV1_rattan',(.62,.45,.26),rough=.8)
 for x in (2.4,4.4):
  cyl('Bistro table top',(x,-H-1.6,.74),.33,.03,mat('ShopV1_marble_white',(.9,.89,.86),rough=.2));cyl('Bistro table stem',(x,-H-1.6,.37),.03,.72,tbl,n=8);cyl('Bistro table foot',(x,-H-1.6,.015),.2,.03,tbl)
  for s in (-1,1):
   bb('Bistro chair seat',x+s*.55-.2,x+s*.55+.2,-H-1.8,-H-1.4,.44,.48,seat);bb('Bistro chair back',x+s*.75-.02,x+s*.75+.02,-H-1.8,-H-1.4,.48,.88,seat)
   for a in (-.15,.15):
    for b2 in (-.15,.15):bb('Bistro chair leg',x+s*.55+a-.012,x+s*.55+a+.012,-H-1.6+b2-.012,-H-1.6+b2+.012,0,.44,tbl)
 # A-frame chalkboard beside the door
 ax=dx+1.7
 for s in (-1,1):quad('A-board',[(ax-.3,-H-.9+s*.0,0),(ax+.3,-H-.9,0),(ax+.3,-H-.9-s*.18,1.0),(ax-.3,-H-.9-s*.18,1.0)],mat('ShopV1_chalk_menu',(1,1,1),rough=.9,tex='chalk_menu'))
 G['cut']=[G['front_cut'],dict(name='old entry leaves',box=[dx-1.36,dx+1.36,-H-.03,-H+1.5,-.01,2.45])]
 G['lights']=[((1.9,-5.5,3.1),(1.,.78,.55),2200,700),((-4.6,-6.5,3.1),(1.,.8,.6),1400,500),((3.5,-2.6,3.0),(1.,.8,.6),1200,500),((1.4,-H-.4,3.3),(1.,.85,.6),900,420)]
 G['feature']=dict(slot='S01_wall_feature_coffee',tex='brick_warm')
def shop_S26(G):  # convenience store
 H,dx=G['H'],G['dx'];white=mat('ShopV1_alu_white',(.93,.94,.94),rough=.3,metal=.2)
 sp=dict(frame=white,sign_w=4.6,sign_x=1.6,sign_glow=6.0,kick_h=.25,fascia=mat('ShopV1_band_conv',(1,1,1),rough=.4,tex='band_conv',emit=.6,emit_tex=True))
 storefront(sp,G);blade(sp,G);ac_units(G,[-3.0,3.0])
 cooler=mat('ShopV1_cooler',(1,1,1),rough=.15,tex='cooler_front',emit=1.6,emit_tex=True);goods=mat('ShopV1_goods',(1,1,1),rough=.6,tex='goods_shelf',emit=.12,emit_tex=True)
 gond=mat('ShopV1_gondola',(.9,.9,.9),rough=.4,metal=.3);dark=mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4)
 # cooler wall along the left side wall
 bb('Cooler cabinet',-5.6,-4.95,-6.6,2.9,0,2.25,gond);face_x('Cooler doors',-4.949,-6.5,2.8,.12,2.1,cooler,1)
 bb('Cooler header',-5.6,-4.9,-6.6,2.9,2.25,2.5,mat('ShopV1_green',(.07,.5,.28),rough=.4,emit=.4))
 # gondola islands
 for cx in (-.15,1.95):
  bb('Gondola',cx-.4,cx+.4,-6.6,1.1,0,1.55,gond)
  for s in (-1,1):face_x('Gondola goods',cx+s*.401,-6.5,1.0,.08,1.5,goods,s)
  bb('Gondola end cap',cx-.4,cx+.4,-6.75,-6.6,0,1.6,mat('ShopV1_orange',(.93,.47,.13),rough=.4))
 # service counter along the right wall with register, warmer and coffee machine
 bb('Service counter',3.85,4.45,-8.8,-3.6,0,1.0,white);bb('Counter top',3.8,4.5,-8.85,-3.55,1.0,1.04,dark)
 bb('Register',3.95,4.3,-7.7,-7.3,1.04,1.32,dark);bb('Register screen',3.97,3.99,-7.65,-7.35,1.2,1.42,mat('ShopV1_screen',(.2,.6,.9),emit=2.))
 bb('Hot food warmer',3.9,4.4,-6.3,-5.5,1.04,1.5,mat('ShopV1_warmer_glass',(1.,.7,.35),rough=.1,emit=1.2,alpha=.6))
 bb('Coffee machine',3.95,4.4,-4.6,-4.1,1.04,1.7,mat('ShopV1_coffee_machine',(.1,.1,.1),rough=.3,metal=.4))
 bb('Back shelf',5.25,5.6,-8.8,-3.6,.9,2.3,gond);face_x('Back shelf goods',5.249,-8.7,-3.7,.95,2.25,goods,-1)
 bb('Magazine rack',-.2,3.2,-H+.3,-H+.6,0,1.05,gond);face_front('Magazine fronts',-.15,3.15,.15,1.0,-H+.299,goods)
 # outside: recycle bins and an ice-cream freezer clear of the door
 for k,c in enumerate([(.1,.45,.8),(.95,.75,.1),(.15,.6,.25)]):bb('Recycle bin',.6+k*.5,1.0+k*.5,-H-.75,-H-.3,0,.95,mat('ShopV1_bin'+str(k),c,rough=.5))
 G['cut']=[G['front_cut'],dict(name='old entry leaves',box=[dx-1.36,dx+1.36,-H-.03,-H+1.5,-.01,2.45]),dict(name='sales floor fixtures',box=[-5.75,5.75,-H+.15,G['core_y']-.05,.004,2.6])]
 G['lights']=[((-.15,-5.0,3.2),(.95,.97,1.),2600,800),((1.95,-1.5,3.2),(.95,.97,1.),2600,800),((-4.0,-2.0,3.2),(.95,.97,1.),1800,600),((4.4,-6.2,3.2),(.95,.97,1.),1600,600),((1.6,-H-.4,3.3),(1.,1.,1.),900,420)]
 G['feature']=dict(slot='S26_wall_feature_convenience',tex='wood_slat_light')
def flowers_mats():
 return [mat('ShopV1_flower_'+n,c,rough=.7) for n,c in [('red',(.78,.08,.12)),('pink',(.95,.55,.65)),('white',(.95,.94,.9)),('yellow',(.98,.8,.15)),('purple',(.5,.25,.7)),('orange',(.97,.45,.12))]]
def bucket_row(x0,x1,y,z,flw,tmpl=None,s=.6):
 zinc=mat('ShopV1_zinc',(.62,.64,.66),rough=.35,metal=.8);n=max(1,int((x1-x0)/.42))
 for k in range(n):
  x=x0+.2+k*(x1-x0-.4)/max(1,n-1);cyl('Flower bucket',(x,y,z+.16),.16,.32,zinc,r2=.13)
  if tmpl:dup(tmpl,'Bucket flowers',(x,y,z+.28),k*1.3,s)
  else:
   for q in range(5):sph('Bucket bloom',(x+.08*math.cos(q*1.26),y+.08*math.sin(q*1.26),z+.5+.04*(q%2)),.075,flw[(k+q)%len(flw)])
def shop_S09(G):  # florist
 H,dx=G['H'],G['dx'];oak=mat('ShopV1_oak',(.55,.4,.25),rough=.5);sp=dict(frame=oak,sign_frame=mat('ShopV1_sage_dark',(.24,.32,.22),rough=.4),sign_w=3.6,sign_x=1.6,sign_glow=4.0,fascia=mat('ShopV1_cream',(.9,.86,.76),rough=.6))
 storefront(sp,G);awning(sp,G,-5.25,5.25,mat('ShopV1_S09_awning',(1,1,1),rough=.85,tex='awning_sage'),depth=1.0)
 blade(sp,G);flw=flowers_mats();tm=None  # the decimated Tripo bouquet reads grey at bucket scale; use coloured blooms
 flower_box(G,-3.95,-2.05,4.62,flw);flower_box(G,2.05,3.95,4.62,flw);flower_box(G,-3.95,-2.05,8.12,flw);flower_box(G,2.05,3.95,8.12,flw)
 wood=mat('ShopV1_oak_shelf',(.6,.45,.28),rough=.55)
 # tiered bucket stands inside along the left wall and outside on both sides of the door
 for t,(x0,x1,h) in enumerate([(-5.6,-5.15,.9),(-5.15,-4.7,.55),(-4.7,-4.25,.2)]):bb('Tier stand',x0,x1,-8.2,-1.4,0,h,wood)
 for t,(xc,h) in enumerate([(-5.38,.9),(-4.93,.55),(-4.48,.2)]):
  for k in range(7):y=-7.95+k*.95;zinc=mat('ShopV1_zinc',(.62,.64,.66),rough=.35,metal=.8);cyl('Flower bucket',(xc,y,h+.16),.16,.32,zinc,r2=.13);(dup(tm,'Bucket flowers',(xc,y,h+.26),k*.9,.55) if tm else [sph('Bucket bloom',(xc+.08*math.cos(q*1.26),y+.08*math.sin(q*1.26),h+.5),.075,flw[(k+q+t)%6]) for q in range(5)])
 for x0,x1 in [(-5.4,dx-1.45),(dx+1.45,dx+3.0)]:
  bb('Street tier',x0,x1,-H-.9,-H-.5,0,.32,wood);bb('Street tier',x0,x1,-H-.5,-H-.1,0,.62,wood);bucket_row(x0,x1,-H-.7,.32,flw,tm,.5);bucket_row(x0,x1,-H-.3,.62,flw,tm,.5)
 # central display table with vases, flower cooler on the right wall, work counter at the back
 bb('Display table',.3,2.3,-6.4,-4.6,.72,.78,wood);[bb('Table leg',x-.03,x+.03,y-.03,y+.03,0,.72,wood) for x in (.36,2.24) for y in (-6.34,-4.66)]
 for k in range(5):x=.55+k*.42;cyl('Vase',(x,-5.5+.25*(k%2),.9),.08,.24,mat('ShopV1_vase',(.85,.9,.92),rough=.1,alpha=.5));(dup(tm,'Vase flowers',(x,-5.5+.25*(k%2),.98),k,.45) if tm else sph('Vase bloom',(x,-5.5,1.1),.1,flw[k%6]))
 bb('Flower cooler',4.95,5.6,-7.6,-3.6,0,2.2,mat('ShopV1_cooler_frame',(.85,.87,.86),rough=.3,metal=.4));face_x('Flower cooler glass',4.949,-7.5,-3.7,.1,2.1,mat('ShopV1_cooler_glass',(.8,.9,.95),rough=.05,alpha=.3,emit=.4),-1)
 for t,z in enumerate((.25,1.0,1.65)):bb('Cooler shelf',5.0,5.55,-7.5,-3.7,z,z+.03,mat('ShopV1_glass_shelf',(.85,.9,.9),rough=.1))
 for t,z in enumerate((.28,1.03)):bucket_row(-7.4+0,-3.8,5.27,z,flw,tm,.45) if False else [ (cyl('Cooler bucket',(5.27,y,z+.14),.13,.28,mat('ShopV1_zinc',(.62,.64,.66),rough=.35,metal=.8),r2=.11), dup(tm,'Cooler flowers',(5.27,y,z+.22),y,.42) if tm else None) for y in (-7.2,-6.5,-5.8,-5.1,-4.4)]
 bb('Work counter',2.6,5.3,-1.7,-1.1,0,.95,wood);bb('Counter top',2.55,5.35,-1.75,-1.05,.95,.99,mat('ShopV1_cream',(.9,.86,.76),rough=.6))
 cyl('Wrapping roll',(3.2,-1.4,1.06),.06,.9,mat('ShopV1_kraft',(.72,.55,.36),rough=.8)).rotation_euler.y=math.pi/2;bb('Register',4.6,4.95,-1.6,-1.25,.99,1.2,mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4))
 for x,y in [(.8,-2.6),(2.6,-7.5),(1.6,-3.0)]:
  cyl('Hanging pot cord',(x,y,3.2),.005,.6,mat('ShopV1_black_metal',(.04,.04,.04),rough=.4,metal=.8),n=6);cyl('Hanging pot',(x,y,2.82),.16,.18,mat('ShopV1_pot_white',(.92,.9,.86),rough=.4),r2=.1)
  for q in range(6):sph('Hanging leaf',(x+.12*math.cos(q),y+.12*math.sin(q),2.78-.08*(q%3)),.1,mat('ShopV1_leaf',(.16,.4,.16),rough=.6),(1.2,.5,.6))
 plant('Window plant',4.6,-H+.75,1.2,mat('ShopV1_pot_white',(.92,.9,.86),rough=.4))
 G['cut']=[G['front_cut'],dict(name='old entry leaves',box=[dx-1.36,dx+1.36,-H-.03,-H+1.5,-.01,2.45]),dict(name='sales floor fixtures',box=[-5.75,5.75,-H+.15,G['core_y']-.05,.004,2.6])]
 G['lights']=[((1.3,-5.5,3.15),(1.,.88,.72),2200,700),((-4.6,-4.5,3.15),(1.,.88,.72),1600,600),((4.0,-2.0,3.1),(1.,.88,.72),1400,500),((1.6,-H-.4,3.3),(1.,.9,.7),800,420)]
 G['feature']=dict(slot='S09_wall_feature_floral',tex='wood_slat_light')
def shop_S17(G):  # laundromat
 H,dx=G['H'],G['dx'];blue=mat('ShopV1_laundry_blue',(.1,.36,.68),rough=.35,metal=.2)
 sp=dict(frame=blue,sign_w=4.0,sign_x=1.6,sign_glow=6.0,kick_h=.3,fascia=mat('ShopV1_white_panel',(.95,.96,.97),rough=.4))
 storefront(sp,G);awning(sp,G,dx+1.35,5.25,mat('ShopV1_S17_awning',(1,1,1),rough=.7,tex='awning_blue'),depth=.9,drop=.12,valance=.12)
 blade(sp,G);ac_units(G,[-3.0,3.0])
 W=G.get('washer_tmpl');D=G.get('dryer_tmpl');steel=mat('ShopV1_steel',(.7,.7,.72),rough=.25,metal=1.)
 for k in range(6):
  y=-8.0+k*1.0
  if W:dup(W,'Washer',(-5.2,y,0),G.get('washer_rz',0.)+math.pi/2)
  else:bb('Washer',-5.6,-4.8,y-.42,y+.42,0,1.0,mat('ShopV1_washer',(.92,.93,.94),rough=.3))
 for k in range(4):
  y=-7.6+k*1.05
  if W:dup(W,'Washer',(5.2,y,0),G.get('washer_rz',0.)-math.pi/2)
  if D:dup(D,'Dryer',(5.2,y,1.02),G.get('dryer_rz',0.)-math.pi/2)
 bb('Folding table',.1,1.7,-6.2,-4.2,.86,.9,steel);[bb('Folding table leg',x-.025,x+.025,y-.025,y+.025,0,.86,steel) for x in (.15,1.65) for y in (-6.15,-4.25)]
 for k in range(5):x=.4+k*.6;bb('Bench seat',x-.24,x+.24,-H+.55,-H+1.0,.44,.5,mat('ShopV1_seat_blue',(.15,.45,.8),rough=.5));bb('Bench leg',x-.03,x+.03,-H+.75,-H+.81,0,.44,steel)
 bb('Detergent vending',-5.55,-4.95,-1.6,-.7,0,1.8,mat('ShopV1_vending',(.85,.1,.2),rough=.35));face_x('Vending window',-4.949,-1.5,-.8,.9,1.7,mat('ShopV1_goods',(1,1,1),rough=.6,tex='goods_shelf',emit=.6,emit_tex=True),1)
 bb('Change machine',-5.55,-5.05,-.5,.1,0,1.6,mat('ShopV1_change',(.75,.76,.78),rough=.3,metal=.6))
 cyl('Wall clock',(-0.2,-H+.25,2.3),.2,.03,mat('ShopV1_white_panel',(.95,.96,.97),rough=.4)).rotation_euler.x=math.pi/2
 G['cut']=[G['front_cut'],dict(name='old entry leaves',box=[dx-1.36,dx+1.36,-H-.03,-H+1.5,-.01,2.45]),dict(name='sales floor fixtures',box=[-5.75,5.75,-H+.15,G['core_y']-.05,.004,2.6])]
 G['lights']=[((-3.6,-5.5,3.2),(.94,.97,1.),2200,700),((3.6,-5.5,3.2),(.94,.97,1.),2200,700),((0.8,-1.8,3.2),(.94,.97,1.),1600,600),((1.6,-H-.4,3.3),(1.,1.,1.),900,420)]
 G['feature']=dict(slot='S17_wall_feature_laundry',tex='tile_laundry')
SHOPS=dict(S01=shop_S01,S26=shop_S26,S09=shop_S09,S17=shop_S17)
results=[]
for sid in TASK['ids']:
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS.clear();NEW.clear()
 src=SRC/(sid+'-modular-components-v1')/'assembly-building'/(sid+'-F01-complete-2k.glb');bpy.ops.import_scene.gltf(filepath=str(src));old=[o for o in bpy.context.scene.objects]
 G=dict(id=sid);ext=[o for o in old if o.type=='MESH' and '/F01-exterior-' in o.name]
 G['H']=max(max(abs(bounds(o)[0][1]),abs(bounds(o)[1][1])) for o in ext)
 fr=[o for o in old if o.type=='MESH' and '-entry-front-' in o.name and '-frame' in o.name];fmn=[min(bounds(o)[0][0] for o in fr)];fmx=[max(bounds(o)[1][0] for o in fr)]
 G['dx']=round((fmn[0]+fmx[0])/2,3);assert all(bounds(o)[0][1]<-G['H']+.3 for o in fr),'entry not on the -Y front'
 core=[o for o in old if o.type=='MESH' and '/F01-core-' in o.name];G['core_y']=min(bounds(o)[0][1] for o in core)
 G['front_cut']=dict(name='front wall, windows, entry, sign and band',box=[-5.81,5.81,-G['H']-.03,-G['H']+.215,-.01,3.7])
 for o in old:
  if o.type=='MESH' and 'flowers' in o.name and 'flower_tmpl' not in G:G['flower_tmpl']=o
  if o.type=='MESH' and '-upper' in o.name and 'dryer_tmpl' not in G:G['dryer_tmpl']=o
 if sid=='S17':
  ws=[o for o in old if o.type=='MESH' and 'equipment' in o.name and len(o.data.polygons)>3000 and '-upper' not in o.name]
  if ws:G['washer_tmpl']=ws[0]
 SHOPS[sid](G)
 for o in old:bpy.data.objects.remove(o,do_unlink=True)
 # route/door clearance: nothing new inside the door lane (inside and out) or the aisle in front of the core below 2.0m
 dx,H=G['dx'],G['H'];keep=[('door lane',dx-1.2,dx+1.2,-H-2.4,G['core_y'],0.03,2.0),('core aisle',-.6,4.8,G['core_y']-1.6,G['core_y'],0.03,2.0)]
 block=[]
 for o in NEW:
  mn,mx=bounds(o)
  if 'Door' in o.name or 'Storefront' in o.name or o.name.startswith('Awning') or 'Sign' in o.name:continue
  for (n,x0,x1,y0,y1,z0,z1) in keep:
   if mn[0]<x1 and mx[0]>x0 and mn[1]<y1 and mx[1]>y0 and mn[2]<z1 and mx[2]>z0:block.append((n,o.name))
 # anything that is not part of the storefront and still sits in the door lane or core aisle is dropped (clear walking path)
 drop={n for _,n in block}
 for o in [o for o in NEW if o.name in drop]:NEW.remove(o);bpy.data.objects.remove(o,do_unlink=True)
 dest=O/sid;dest.mkdir(parents=True,exist_ok=True)
 bpy.ops.object.select_all(action='DESELECT')
 for o in NEW:o.select_set(True)
 bpy.context.view_layer.objects.active=NEW[0];bpy.ops.object.join();ob=bpy.context.object;ob.name='ShopV1_'+sid+'_Refit'
 p=dest/(sid+'-refit.glb');bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',use_selection=True,export_apply=True,export_yup=True);bpy.ops.wm.save_as_mainfile(filepath=str(dest/(sid+'-refit.blend')))
 ob.data.calc_loop_triangles()
 r=dict(id=sid,source=str(src),path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),H=G['H'],door_x=G['dx'],core_y=G['core_y'],triangles=len(ob.data.loop_triangles),cut=G['cut'],
  signs=([G['sign']] if 'sign' in G else [])+([G['blade']] if 'blade' in G else []),feature=G.get('feature'),lights=[dict(local=list(a),color=list(b),lumens=c,radius=d) for a,b,c,d in G['lights']],blockers=block,
  names=NAMES[sid],sign_textures={k:{loc:str(T/f'{sid}-{k}-{loc}.png') for loc in ('zh-Hant','zh-Hans','en')} for k in ('H','V')})
 (dest/'build.json').write_text(json.dumps(r,ensure_ascii=False,indent=1),'utf8');results.append(r);print('SHOP',sid,'tris',r['triangles'],'H',G['H'],'door',G['dx'],'core',G['core_y'],'blockers',block,flush=True)
(O/'samples-build.json').write_text(json.dumps(dict(status='authored_requires_native_install',shops=results),ensure_ascii=False,indent=1),'utf8')
]====]
local path=out..'/build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,ids=ids}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --python-expr "'..expr..'" > "'..out..'/build.log" 2>&1"'))
print('Shop samples authored; see '..out..'/build.log')
