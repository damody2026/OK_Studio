-- Generate every procedural texture referenced by motel-v1/room-specs/*.json ({"gen":{...}} descriptors) into
-- sample-rooms/textures/gen_<md5>.png. Colours are 0-1 floats. Kinds: plaster, damask, stripes, marble, wood,
-- mosaic, check, tufted, lattice, brick, geo, floral, panels, galaxy, mural, sky, filigree.
local code=[====[
import json,hashlib,math
import numpy as np
from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');D=O/'sample-rooms/textures';D.mkdir(parents=True,exist_ok=True)
N=1024
# albedo cap .85 (round 12: white tile floors and porcelain clipped to flat white under auto exposure); '|cap85' in the
# texture name hash keeps the capped textures apart from the old cached ones
def C(c):
 m=max(c) if c else 0;k=.85/m if m>.85 else 1.
 return tuple(int(max(0,min(1,v*k))*255) for v in c)
def tn(n,o=5,seed=0):
 r=np.random.default_rng(seed);out=np.zeros((n,n))
 for k in range(o):
  f=2**(k+2);g=r.random((f,f));g=np.kron(g,np.ones((n//f,n//f)));out+=np.asarray(Image.fromarray((g*255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(n/f/2)))/255/(2**k)
 return (out-out.min())/(out.max()-out.min()+1e-9)
def lerp(a,b,t):t=t[...,None];return np.array(a,float)*(1-t)+np.array(b,float)*t
def gen(g,seed):
 k=g['kind']
 if k=='plaster':return lerp(C(g['c1']),C(g.get('c2',g['c1'])),tn(N,5,seed)*.6+.2)
 if k=='marble':
  n=tn(N,7,seed);m=tn(N,7,seed+5);y,x=np.mgrid[0:N,0:N]/N;s=g.get('scale',6)
  t=np.sin((x*s*.5+y*s*.35+(np.abs(n-.5)*2+np.abs(m-.5)*1.2)*3.2)*math.pi);v=np.exp(-np.abs(t)*9)*(0.35+0.65*tn(N,3,seed+7))
  fine=np.exp(-np.abs(np.sin((x*s*1.7-y*s+m*6)*math.pi))*22)*.45;c=lerp(C(g['dark']),C(g['base']),np.clip(tn(N,5,seed+1)*1.2-.1,0,1));return lerp(c,C(g['vein']),np.clip(v+fine,0,1)*.85)
 if k=='wood':
  a=np.zeros((N,N,3));gr=tn(N,5,seed);rows=g.get('rows',7)
  for r in range(rows):
   y0=int(r*N/rows);y1=int((r+1)*N/rows);off=int((r*.37%1)*N);col=lerp(C(g['c1']),C(g['c2']),np.full((y1-y0,N),(r*.618%1)*.7)+gr[y0:y1]*.3);a[y0:y1]=np.roll(col,off,axis=1);a[y0:y0+2]*=.55
  return a
 if k=='mosaic':
  cols=[C(c) for c in g['colors']];t=g.get('tiles',40);s=N/t;r=np.random.default_rng(seed);idx=r.integers(0,len(cols),(t,t));a=np.zeros((N,N,3))
  bands=g.get('bands')
  for ty in range(t):
   for tx in range(t):
    cc=cols[(ty//bands)%len(cols)] if bands else cols[idx[ty,tx]];a[int(ty*s):int((ty+1)*s),int(tx*s):int((tx+1)*s)]=np.array(cc)*(0.9+0.2*r.random())
  for i in range(t):a[int(i*s):int(i*s)+2]=C(g.get('grout',(.75,.74,.7)));a[:,int(i*s):int(i*s)+2]=C(g.get('grout',(.75,.74,.7)))
  return a
 im=Image.new('RGB',(N,N),C(g.get('bg',(.2,.2,.2))));d=ImageDraw.Draw(im);fg=C(g.get('fg',(.7,.6,.3)))
 if k=='damask':
  for cy in range(0,N+1,256):
   for cx in range(0,N+1,256):
    for ox,oy in [(0,0),(128,128)]:
     x,y=cx+ox,cy+oy;d.ellipse((x-34,y-60,x+34,y+60),outline=fg,width=5);d.ellipse((x-14,y-26,x+14,y+26),fill=fg)
     for sgn in [-1,1]:d.arc((x+sgn*30-40,y-40,x+sgn*30+40,y+40),200 if sgn<0 else -20,340 if sgn<0 else 160,fill=fg,width=4)
     d.line((x,y-60,x,y-92),fill=fg,width=4);d.line((x,y+60,x,y+92),fill=fg,width=4)
 elif k=='stripes':
  wdt=int(g.get('width',64));c2=C(g.get('c2',(.1,.1,.1)))
  for i in range(0,N,2*wdt):
   if g.get('vertical',True):d.rectangle((i,0,i+wdt-1,N),fill=c2)
   else:d.rectangle((0,i,N,i+wdt-1),fill=c2)
 elif k=='check':
  n=g.get('n',8);s=N//n
  for i in range(n):
   for j2 in range(n):
    if (i+j2)%2:d.rectangle((i*s,j2*s,(i+1)*s-1,(j2+1)*s-1),fill=fg)
 elif k=='tufted':
  for gy in range(-128,N+128,128):
   for gx in range(-64,N+128,128):
    x=gx+(64 if (gy//128)%2 else 0);y=gy;d.polygon([(x,y-62),(x+56,y-30),(x+56,y+30),(x,y+62),(x-56,y+30),(x-56,y-30)],fill=fg,outline=C(g.get('line',(.05,.03,.03))));d.ellipse((x-6,y-6,x+6,y+6),fill=C(g.get('line',(.05,.03,.03))))
  im=im.filter(ImageFilter.GaussianBlur(3))
 elif k=='lattice':
  for i in range(-4,9):d.line((i*128,0,i*128+N,N),fill=fg,width=5);d.line((i*128,N,i*128+N,0),fill=fg,width=5)
 elif k=='brick':
  for r in range(0,N,64):
   off=64 if (r//64)%2 else 0
   for c0 in range(-128,N,128):d.rectangle((c0+off+3,r+3,c0+off+125,r+61),fill=tuple(int(v*(0.85+0.3*((c0*7+r*3)%11)/11)) for v in fg))
 elif k=='geo':
  for gy in range(0,N,128):
   for gx in range(0,N,128):
    if ((gx//128)+(gy//128))%2:d.line((gx+16,gy+16,gx+112,gy+16,gx+112,gy+112,gx+40,gy+112,gx+40,gy+48,gx+80,gy+48,gx+80,gy+80),fill=fg,width=9)
    else:d.line((gx+112,gy+16,gx+16,gy+16,gx+16,gy+112,gx+88,gy+112,gx+88,gy+48,gx+48,gy+48,gx+48,gy+80),fill=fg,width=9)
 elif k=='floral':
  r=np.random.default_rng(seed)
  for i in range(40):
   x,y=r.integers(0,N,2);s=int(r.integers(30,70))
   for p in range(6):a=p*math.pi/3;d.ellipse((x+s*.6*math.cos(a)-s*.35,y+s*.6*math.sin(a)-s*.35,x+s*.6*math.cos(a)+s*.35,y+s*.6*math.sin(a)+s*.35),fill=fg)
   d.ellipse((x-s*.25,y-s*.25,x+s*.25,y+s*.25),fill=C(g.get('fg2',(.9,.8,.3))))
 elif k=='panels':
  s=N//g.get('n',2)
  for i in range(0,N,s):
   for j2 in range(0,N,s):d.rectangle((i+20,j2+20,i+s-20,j2+s-20),outline=fg,width=8)
 elif k=='galaxy':
  a=np.zeros((N,N,3));y,x=np.mgrid[0:N,0:N]/N;n=tn(N,6,seed);sw=np.sin((np.arctan2(y-.5,x-.5)*2+np.hypot(x-.5,y-.5)*14+n*3))*.5+.5
  a=lerp(C(g.get('bg',(.05,.02,.15))),C(g.get('fg',(.6,.2,.9))),np.clip(sw*n*1.4,0,1));r=np.random.default_rng(seed)
  for _ in range(400):yy,xx=r.integers(0,N,2);a[yy:yy+2,xx:xx+2]=255
  return a
 elif k=='sky':
  # painted sky ceiling: blue gradient with soft white cumulus (tileable enough for one ceiling field)
  y,x=np.mgrid[0:N,0:N]/N;a=lerp(C(g.get('top',(.25,.5,.9))),C(g.get('bottom',(.65,.82,.98))),np.clip(np.hypot(x-.5,y-.5)*1.4,0,1))
  cl=np.clip((tn(N,6,seed)*.7+tn(N,4,seed+3)*.5-g.get('cover',.62))*3.2,0,1);return lerp(a,C(g.get('cloud',(1.,1.,1.))),cl**.8)
 elif k=='filigree':
  # pierced ornamental screen: repeating quatrefoil rosettes and S-scrolls in the fg colour on a dark ground
  t=int(g.get('cell',256))
  for cy in range(0,N+t,t):
   for cx in range(0,N+t,t):
    for a in range(4):
     ang=a*math.pi/2;ox,oy=cx+t*.22*math.cos(ang),cy+t*.22*math.sin(ang);d.ellipse((ox-t*.2,oy-t*.2,ox+t*.2,oy+t*.2),outline=fg,width=max(4,t//28))
    d.ellipse((cx-t*.08,cy-t*.08,cx+t*.08,cy+t*.08),fill=fg)
    for sgn in (-1,1):
     d.arc((cx+t*.5-t*.18,cy+sgn*t*.25-t*.18,cx+t*.5+t*.18,cy+sgn*t*.25+t*.18),0,360,fill=fg,width=max(3,t//40))
    d.rectangle((cx-t//2,cy-t//2,cx+t//2,cy+t//2),outline=fg,width=max(3,t//50))
 elif k=='mural':
  W,H=2048,512;yy=np.linspace(0,1,H)[:,None];sky=lerp(C(g.get('top',(.3,.5,.9))),C(g.get('bottom',(.95,.7,.4))),np.repeat(yy,W,axis=1));im=Image.fromarray(sky.astype(np.uint8));d=ImageDraw.Draw(im)
  d.polygon([(0,H)]+[(x,H*.62+40*math.sin(x/300)+25*math.sin(x/97)) for x in range(0,W+1,32)]+[(W,H)],fill=C(g.get('ground',(.3,.2,.15))));return np.asarray(im).astype(float)
 return np.asarray(im).astype(float)*(0.9+0.1*tn(N,3,seed)[...,None])
specs=[json.loads(p.read_text('utf8')) for p in sorted((O/'room-specs').glob('*.json'))]
found={}
def walk(v):
 if isinstance(v,dict):
  if 'gen' in v:found['gen_'+hashlib.md5((json.dumps(v['gen'],sort_keys=True)+'|cap85').encode()).hexdigest()[:10]]=v['gen']
  for x in v.values():walk(x)
 elif isinstance(v,list):
  for x in v:walk(x)
walk(specs);made=0
for name,g in found.items():
 p=D/(name+'.png')
 if p.exists():continue
 a=gen(g,int(name[4:12],16)%1000);Image.fromarray(np.clip(a,0,255).astype(np.uint8)).save(p);made+=1
print('textures referenced',len(found),'generated',made)
]====]
local p=assert(io.popen('python -I -','w'));assert(p:write(code));assert(p:close())
