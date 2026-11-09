-- Procedural base-colour textures for the four fidelity sample rooms (no photo is pasted; patterns are authored here).
local code=[====[
import numpy as np,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
D=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1/sample-rooms/textures');D.mkdir(parents=True,exist_ok=True)
N=1024;rng=np.random.default_rng(7)
def save(name,a):Image.fromarray(np.clip(a,0,255).astype(np.uint8)).save(D/(name+'.png'));print('TEX',name)
def tile_noise(n,octaves=5,seed=0):
 r=np.random.default_rng(seed);out=np.zeros((n,n))
 for o in range(octaves):
  f=2**(o+2);g=r.random((f,f));g=np.kron(g,np.ones((n//f,n//f)))
  img=Image.fromarray((g*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(n/f/2));out+=np.asarray(img)/255/(2**o)
 return (out-out.min())/(out.max()-out.min())
def lerp(c1,c2,t):t=t[...,None];return np.array(c1)*(1-t)+np.array(c2)*t
def marble(name,base,dark,vein,seed,scale=6):
 n=tile_noise(N,7,seed);m=tile_noise(N,7,seed+5);y,x=np.mgrid[0:N,0:N]/N
 turb=np.abs(n-.5)*2+np.abs(m-.5)*1.2
 t=np.sin((x*scale*.5+y*scale*.35+turb*3.2)*math.pi);v=np.exp(-np.abs(t)*9)*(0.35+0.65*tile_noise(N,3,seed+7))
 fine=np.exp(-np.abs(np.sin((x*scale*1.7-y*scale+m*6)*math.pi))*22)*.45
 c=lerp(dark,base,np.clip(tile_noise(N,5,seed+1)*1.2-.1,0,1));c=lerp(c,vein,np.clip(v+fine,0,1)*.85);save(name,c)
marble('marble_redbrown',(120,48,40),(48,18,16),(225,200,185),11)
marble('marble_black',(28,28,30),(8,8,9),(205,205,210),12,8)
marble('marble_cream',(222,210,192),(185,170,150),(150,130,115),13,4)
# Granite: brown speckle (pool coping).
g=tile_noise(N,3,21);sp=rng.random((N,N));c=lerp((92,46,30),(150,82,52),g);c[sp>.93]=(30,22,20);c[sp<.05]=(190,150,120);sp2=np.asarray(Image.fromarray((rng.random((N//4,N//4))*255).astype(np.uint8)).resize((N,N),Image.NEAREST))/255;c[sp2>.86]=(36,24,22);c[sp2<.10]=(205,165,130);save('granite_brown',c)
# Dark cherry planks 14cm x 120cm at 2m period -> 7 rows x ~1.7 planks.
def planks(name,c1,c2,rows=7):
 a=np.zeros((N,N,3));grain=tile_noise(N,5,31)
 for r in range(rows):
  y0=int(r*N/rows);y1=int((r+1)*N/rows);off=int((r*0.37%1)*N);tone=(r*0.618)%1
  col=lerp(c1,c2,np.full((y1-y0,N),tone*.7)+grain[y0:y1]*.3);col=np.roll(col,off,axis=1);a[y0:y1]=col
  a[y0:y0+2]*=.55
  for k in range(2):xx=(off+int(k*N/1.66))%N;a[y0:y1,xx:xx+2]*=.6
 save(name,a)
planks('wood_dark',(58,26,16),(96,48,28));planks('wood_walnut',(70,40,24),(118,74,44))
# Damask wallpaper: dark brown with gold symmetric medallions on 0.6m repeat.
im=Image.new('RGB',(N,N),(52,30,22));d=ImageDraw.Draw(im)
for cy in range(0,N+1,256):
 for cx in range(0,N+1,256):
  for ox,oy in [(0,0),(128,128)]:
   x,y=cx+ox,cy+oy;gold=(150,110,52)
   d.ellipse((x-34,y-60,x+34,y+60),outline=gold,width=5);d.ellipse((x-14,y-26,x+14,y+26),fill=gold)
   for s in [-1,1]:d.arc((x+s*30-40,y-40,x+s*30+40,y+40),200 if s<0 else -20,340 if s<0 else 160,fill=gold,width=4);d.line((x,y-60,x,y-92),fill=gold,width=4);d.line((x,y+60,x,y+92),fill=gold,width=4)
a=np.asarray(im).astype(float)*(0.85+0.15*tile_noise(N,3,41)[...,None]);save('damask_brown_gold',a)
# Charcoal-purple geometric wallpaper (303): interlocking key pattern.
im=Image.new('RGB',(N,N),(34,30,38));d=ImageDraw.Draw(im);c=(70,62,78)
for gy in range(0,N,128):
 for gx in range(0,N,128):
  k=((gx//128)+(gy//128))%2
  if k:d.line((gx+16,gy+16,gx+112,gy+16,gx+112,gy+112,gx+40,gy+112,gx+40,gy+48,gx+80,gy+48,gx+80,gy+80),fill=c,width=9)
  else:d.line((gx+112,gy+16,gx+16,gy+16,gx+16,gy+112,gx+88,gy+112,gx+88,gy+48,gx+48,gy+48,gx+48,gy+80),fill=c,width=9)
save('wallpaper_key_purple',np.asarray(im).astype(float)*(0.9+0.1*tile_noise(N,3,42)[...,None]))
# Black-white-grey star terrazzo floor (303): 4m repeat of big triangles.
im=Image.new('RGB',(N,N));d=ImageDraw.Draw(im);sp=tile_noise(N,2,51)
cols=[(232,230,226),(14,14,16),(150,148,150),(232,230,226)]
for gy in range(0,N,512):
 for gx in range(0,N,512):
  cx,cy=gx+256,gy+256;pts=[(gx,gy),(gx+512,gy),(gx+512,gy+512),(gx,gy+512)]
  for i in range(4):
   p1=pts[i];p2=pts[(i+1)%4];d.polygon([p1,p2,(cx,cy)],fill=cols[(i+(gx//512)+(gy//512))%4])
  for i in range(8):a=i*math.pi/4;d.polygon([(cx,cy),(cx+250*math.cos(a),cy+250*math.sin(a)),(cx+120*math.cos(a+.39),cy+120*math.sin(a+.39))],fill=cols[(i+1)%3])
a=np.asarray(im).astype(float);speck=rng.random((N,N))
light=a.mean(axis=2)>180;a[light&(speck>.85)]*=.72;a[(~light)&(speck>.9)]+=40;save('terrazzo_star_bw',a)
# Pool mosaic wall: 2.5cm tiles, alternating 20cm red / white bands (1m repeat -> 40 tiles).
def mosaic(name,bandfn,tiles=40):
 a=np.zeros((N,N,3));s=N/tiles;jit=rng.random((tiles,tiles))
 for ty in range(tiles):
  for tx in range(tiles):
   col=np.array(bandfn(tx,ty))*(0.88+0.24*jit[ty,tx]);y0=int(ty*s);x0=int(tx*s);a[y0:int((ty+1)*s),x0:int((tx+1)*s)]=col
   a[y0:y0+2,x0:int((tx+1)*s)]=(200,196,186);a[y0:int((ty+1)*s),x0:x0+2]=(200,196,186)
 save(name,a)
mosaic('mosaic_red_white',lambda x,y:(150,32,36) if (y//8)%2==0 else (226,214,198))
pj=np.random.default_rng(91).integers(0,3,(64,64))
mosaic('mosaic_pool_blue',lambda x,y:[(40,110,190),(70,150,215),(28,70,160)][pj[y%64,x%64]])
gj=np.random.default_rng(93).integers(0,4,(64,64))
mosaic('mosaic_gold',lambda x,y:[(190,140,50),(150,105,35),(215,170,80),(120,85,30)][gj[y%64,x%64]],tiles=32)
mosaic('mosaic_black_white_check',lambda x,y:(20,20,22) if (x//4+y//4)%2 else (232,232,228),tiles=32)
# Pool floor design (non-tiling, whole pool): concentric blue rectangles with a yellow and navy wave band.
W,H=2048,1024;im=Image.new('RGB',(W,H),(30,80,170));d=ImageDraw.Draw(im)
for i,c in enumerate([(120,190,235),(90,165,225),(60,135,210),(40,105,195),(28,78,175),(22,58,150)]):m=i*60;d.rectangle((m+150,m,W-m-40,H-m),fill=c)
for k,(col,wid) in enumerate([((235,175,40),46),((25,40,130),40),((235,175,40),38)]):
 pts=[(x,H*.18+k*58+110*math.sin(x/W*math.pi*1.4)) for x in range(0,W+1,16)];d.line(pts,fill=col,width=wid)
a=np.asarray(im).astype(float);s=32
for y in range(0,H,s):a[y:y+2]=a[y:y+2]*.7+60
for x in range(0,W,s):a[:,x:x+2]=a[:,x:x+2]*.7+60
Image.fromarray(np.clip(a,0,255).astype(np.uint8)).save(D/'pool_floor_design.png');print('TEX pool_floor_design')
# Desert sunset mural band for the pool hall top wall (non-tiling 8:1).
W,H=4096,512;y=np.linspace(0,1,H)[:,None];sky=lerp((250,170,90),(70,40,110),np.repeat(y,W,axis=1)[::-1]);sky=sky[::-1]
im=Image.fromarray(sky.astype(np.uint8));d=ImageDraw.Draw(im)
d.polygon([(0,H)]+[(x,H*.62+40*math.sin(x/300)+25*math.sin(x/97)) for x in range(0,W+1,32)]+[(W,H)],fill=(120,60,40))
for cx in [2400,2560,2700,2830]:
 b=H*.55;d.ellipse((cx-60,b-50,cx+60,b+10),fill=(25,15,20));d.rectangle((cx+40,b-90,cx+60,b-20),fill=(25,15,20));d.ellipse((cx+40,b-110,cx+85,b-80),fill=(25,15,20))
 for lx in [-45,-20,25,45]:d.rectangle((cx+lx,b,cx+lx+8,b+80),fill=(25,15,20))
d.ellipse((900,60,1150,310),fill=(255,220,150));im.save(D/'mural_desert.png');print('TEX mural_desert')
# Red tufted velvet (303 headwall): elongated hexagon tufts with button highlights.
im=Image.new('RGB',(N,N),(110,10,20));d=ImageDraw.Draw(im)
for gy in range(-128,N+128,128):
 for gx in range(-64,N+128,128):
  x=gx+(64 if (gy//128)%2 else 0);y=gy
  d.polygon([(x,y-62),(x+56,y-30),(x+56,y+30),(x,y+62),(x-56,y+30),(x-56,y-30)],fill=(150,18,30),outline=(70,4,12));d.ellipse((x-6,y-6,x+6,y+6),fill=(60,4,10))
a=np.asarray(im.filter(ImageFilter.GaussianBlur(3))).astype(float)*(0.85+0.2*tile_noise(N,4,61)[...,None]);save('velvet_tufted_red',a)
# Black mirror panel with diamond lattice (303 side walls).
im=Image.new('RGB',(N,N),(18,14,20));d=ImageDraw.Draw(im)
for k in range(-4,9):d.line((k*128,0,k*128+N,N),fill=(170,150,120),width=5);d.line((k*128,N,k*128+N,0),fill=(170,150,120),width=5)
for gy in range(0,N,128):
 for gx in range(0,N,128):d.rectangle((gx+60,gy-4+64,gx+68,gy+4+64),fill=(230,210,170))
save('mirror_lattice_black',np.asarray(im))
# Cream rug with gold border and medallion (209), non-tiling.
im=Image.new('RGB',(N,N),(214,190,140));d=ImageDraw.Draw(im)
d.rectangle((30,30,N-30,N-30),outline=(150,110,50),width=40);d.rectangle((110,110,N-110,N-110),outline=(120,80,40),width=8)
for k in range(0,N,64):d.ellipse((k,6,k+40,46),outline=(120,80,40),width=4);d.ellipse((k,N-46,k+40,N-6),outline=(120,80,40),width=4)
d.ellipse((N/2-220,N/2-160,N/2+220,N/2+160),outline=(150,110,50),width=12);save('rug_cream_gold',np.asarray(im).astype(float)*(0.9+0.1*tile_noise(N,3,71)[...,None]))
# Floral painted glass panels (512): tall lily on cream, non-tiling 1:3.
W,H=512,1536;im=Image.new('RGB',(W,H),(232,214,170));d=ImageDraw.Draw(im)
d.line([(256,H),(240,1100),(270,700),(250,300)],fill=(110,120,60),width=14)
for (fx,fy) in [(250,300),(300,640),(200,900)]:
 for k in range(6):a=k*math.pi/3;d.polygon([(fx,fy),(fx+120*math.cos(a)-25*math.sin(a),fy+120*math.sin(a)+25*math.cos(a)),(fx+150*math.cos(a),fy+150*math.sin(a)),(fx+120*math.cos(a)+25*math.sin(a),fy+120*math.sin(a)-25*math.cos(a))],fill=(215,110,45))
 d.ellipse((fx-18,fy-18,fx+18,fy+18),fill=(120,40,20))
for (lx,ly,s) in [(240,1180,1),(275,820,-1),(245,520,1)]:d.polygon([(lx,ly),(lx+s*170,ly-60),(lx+s*60,ly+20)],fill=(120,135,70))
d.rectangle((0,0,W-1,H-1),outline=(40,30,25),width=24);im.resize((512,2048),Image.LANCZOS).save(D/'panel_lily.png');print('TEX panel_lily')  # power-of-two: UE left the NPOT 512x1536 version washed out
# Large white ceramic wall tile with grout (512 bath), 60x30cm at 1.2m repeat.
a=np.full((N,N,3),236.);a*=(0.97+0.03*tile_noise(N,3,81)[...,None])
for k in range(0,N,N//2):a[:,k:k+3]=190
for k in range(0,N,N//4):a[k:k+3]=190
save('tile_white_large',a)
# Dark acoustic ceiling grid (203 pool hall): 60cm tiles, charcoal with black T-bar.
a=np.full((N,N,3),42.)*(0.85+0.15*tile_noise(N,4,101)[...,None])
for k in range(0,N,N//4):a[:,k:k+6]=12;a[k:k+6]=12
save('ceiling_grid_dark',a)
# Cream linen-texture wallpaper (203 bedroom/living).
n=tile_noise(N,6,111);ln=(np.sin(np.arange(N)/N*math.pi*2*180)[None,:]*.5+.5)*.08
a=lerp((176,160,138),(212,198,176),n*.7+.3)*(1-ln[...,None]);save('wallpaper_cream_linen',a)
# Dark navy glass mosaic (203 hall walls).
nj=np.random.default_rng(121).integers(0,3,(64,64))
mosaic('mosaic_navy',lambda x,y:[(14,22,60),(24,36,90),(8,12,30)][nj[y%64,x%64]],tiles=40)
# Pleated cream upholstery (203 round headboard): radial pleats, UV is polar-friendly when mapped planar.
y,x=np.mgrid[0:N,0:N];cx=cy=N/2;ang=np.arctan2(y-cy,x-cx);r=np.hypot(x-cx,y-cy)/(N/2)
v=0.75+0.25*np.cos(ang*48)*np.clip(r,0,1);c=lerp((160,148,128),(236,226,206),np.clip(v,0,1));c[r<.07]=(180,165,140);save('pleat_radial_cream',c)
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write(code));assert(p:close())
