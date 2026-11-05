local code=[====[
import json,math
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'traffic-v1';plan=json.loads((O/'plan.json').read_text(encoding='utf8'));groups={};crossings=[];signals=[];signs=[];omitted=[]
materials={'Metal':dict(color=[.065,.075,.07],metal=.8,rough=.43),'Black':dict(color=[.012,.016,.018],rough=.55),'White':dict(color=[.78,.77,.70],rough=.85),'Yellow':dict(color=[.9,.54,.045],rough=.8),'Tactile':dict(color=[.7,.45,.055],rough=.8),'Concrete':dict(color=[.36,.37,.34],rough=.9)}
for axis in [0,1]:
 for color,rgb in [('red',[1,.025,.008]),('amber',[1,.46,.015]),('green',[.015,1,.12])]:materials['Lamp%d_%s'%(axis,color)]=dict(color=rgb,rough=.3,signal_axis=axis,signal_color=color)
for color,rgb in [('red',[1,.025,.008]),('green',[.015,1,.12])]:materials['Ped_'+color]=dict(color=rgb,rough=.3,signal_axis=2,signal_color=color)
def add(mat,center,size,yaw=0,mesh='Cube',pitch=0,collision=False):
 key=mat+'_'+mesh;g=groups.setdefault(key,dict(material=mat,mesh=mesh,collision=collision,instances=[]));g['instances'].append(dict(center=center,size=size,yaw=yaw,pitch=pitch));return key
def vec(p,d,t):return [p[0]+d[0]*t,p[1]+d[1]*t]
def cube(m,p,size,yaw=0):add(m,p,size,yaw)
def cylinder(m,p,size,yaw=0,pitch=0,collision=False):add(m,p,size,yaw,'Cylinder',pitch,collision)
def stripe(p,d,offset,side,width,depth,mat='White'):
 r=[-d[1],d[0]];q=vec(vec(p,d,offset),r,side);cube(mat,[*q,1201.05],[depth,width,.2],math.degrees(math.atan2(d[1],d[0])))
def pedestrian(p,face):
 yaw=math.degrees(math.atan2(face[1],face[0]));r=[-face[1],face[0]]
 cylinder('Metal',[*p,1332],[8,8,264],collision=True);cube('Black',[*p,1468],[25,36,68],yaw)
 # Two recognisable human silhouettes, each in its own recessed display.
 for col,z in [('red',1484),('green',1454)]:
  front=vec(p,face,13.5);cube('Black',[*vec(p,face,13),z],[1,30,28],yaw)
  cylinder('Ped_'+col,[*front,z+7],[6,6,2],yaw,pitch=90)
  cube('Ped_'+col,[*front,z-1],[2,4,10],yaw)
  for side in [-1,1]:
   q=vec(front,r,side*(4 if col=='green' else 2));cube('Ped_'+col,[*q,z-10],[2,2,10],yaw)
   q=vec(front,r,side*5);cube('Ped_'+col,[*q,z],[2,5,2],yaw)
 cube('Yellow',[*vec(p,face,6),1310],[3,10,15],yaw);cylinder('Black',[*vec(p,face,8),1310],[5,5,2],yaw,pitch=90)
def vehicle(p,d,width,offset,source):
 r=[-d[1],d[0]];pole=vec(vec(p,d,offset),r,width/2+95);yaw=math.degrees(math.atan2(d[1],d[0]));axis=0 if abs(d[0])>abs(d[1]) else 1
 cylinder('Concrete',[*pole,1208],[52,52,16],collision=True);cylinder('Metal',[*pole,1498],[16,16,580],collision=True)
 reach=min(340,width/3);middle=vec(pole,r,-reach/2);cube('Metal',[*middle,1778],[18,reach,18],yaw);head=vec(pole,r,-reach)
 cube('Black',[*head,1705],[35,46,116],yaw)
 for col,z in [('red',1742),('amber',1705),('green',1668)]:
  cylinder('Black',[*vec(head,d,19),z],[34,34,7],yaw,pitch=90)
  cylinder('Lamp%d_%s'%(axis,col),[*vec(head,d,23.3),z],[27,27,2],yaw,pitch=90)
  cube('Black',[*vec(head,d,31),z+18],[28,39,3],yaw)
  for side in [-1,1]:cube('Black',[*vec(vec(head,d,29),r,side*18),z+5],[22,3,25],yaw)
 signals.append(dict(source=source,pole_cm=pole,face=d,axis=axis))
def crossing(p,d,width,offset,source,signal=True):
 r=[-d[1],d[0]];available=width-80;count=max(3,int((available+50)//90));span=count*40+(count-1)*50
 for i in range(count):stripe(p,d,offset,-span/2+20+i*90,40,300)
 stripe(p,d,offset+350,width/4,width/2-55,40)
 center=vec(p,d,offset);crossings.append(dict(id='C%02d'%(len(crossings)+1),source=source,center_cm=center,direction=d,width_cm=width,stripes=count,paint_top_cm=1201.15))
 for side in [-1,1]:
  pad=vec(center,r,side*(width/2+110));cube('Tactile',[*pad,1201.4],[240,160,1],math.degrees(math.atan2(d[1],d[0])))
  for row in [-1,0,1]:
   for col in range(-5,6):
    q=vec(vec(pad,d,col*18),r,row*36);cylinder('Tactile',[*q,1202.2],[4,4,.6])
  pedestrian(vec(vec(center,r,side*(width/2+220)),d,-170),[-r[0]*side,-r[1]*side])
 if signal:vehicle(p,d,width,offset+350,source)
 # The opposite approach receives its own head in a midblock crossing.
 return center
for j in plan['junctions']:
 for a in j['arms']:
  d=a['direction'];p=j['center_cm'];internal=False
  for other in plan['junctions']:
   if other['id']==j['id']:continue
   v=[other['center_cm'][k]-p[k] for k in range(2)];along=sum(v[k]*d[k] for k in range(2));side=abs(v[0]*d[1]-v[1]*d[0])
   if side<120 and 0<along<j['radius_cm']+other['radius_cm']+1800:internal=True
  # An endpoint stub is not a viable separate approach. Curved routes use short tessellation segments.
  short=a['length_cm']<j['radius_cm']+700 and a['road']!='path-025'
  if internal or short:omitted.append(dict(junction=j['id'],road=a['road'],reason='compound junction internal connector' if internal else 'short terminal stub'));continue
  crossing(p,d,a['width_cm'],j['radius_cm']+260,j['id'],True)
  q=vec(vec(p,d,j['radius_cm']+1400),[-d[1],d[0]],a['width_cm']/2+120);signs.append(dict(kind='speed30',center=[*q,1490],face=d,source=j['id']))
# Crossings at all five school gates, projected to the nearest real asphalt route.
roads=json.loads((B/'world-ground-v1/ground-plan.json').read_text(encoding='utf8'))['roads'];segments=[]
for road in roads:
 if road['kind']!='asphalt':continue
 pts=[[(1100-p[1])*100,p[0]*100] for p in road['points_map_m']]
 for a,b in zip(pts,pts[1:]):segments.append((a,b,road['width_m']*100,road['id']))
for g in plan['gates']:
 p=g['center'];best=None
 for a,b,width,rid in segments:
  dx,dy=b[0]-a[0],b[1]-a[1];ll=dx*dx+dy*dy;t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/ll));q=[a[0]+t*dx,a[1]+t*dy];dist=math.dist(q,p)
  if best is None or dist<best[0]:best=(dist,q,[dx/math.sqrt(ll),dy/math.sqrt(ll)],width,rid)
 dist,q,d,width,rid=best;assert dist<3500,(g['id'],dist)
 if any(math.dist(q,c['center_cm'])<1800 for c in crossings):continue
 crossing(q,d,width,0,'Gate_'+g['id'],True);vehicle(q,[-d[0],-d[1]],width,350,'Gate_'+g['id'])
 for side in [-1,1]:
  pos=vec(q,[-d[1],d[0]],side*(width/2+150));signs.append(dict(kind='pedestrian',center=[*pos,1490],face=[d[0]*side,d[1]*side],source='Gate_'+g['id']))
# Centre lines follow all polylines, with a clear box around every junction/crossing.
for a,b,width,rid in segments:
 length=math.dist(a,b);d=[(b[k]-a[k])/length for k in range(2)];steps=max(1,math.ceil(length/200));step=length/steps
 for i in range(steps):
  p=vec(a,d,(i+.5)*step)
  if any(math.dist(p,j['center_cm'])<j['radius_cm']+1200 for j in plan['junctions']) or any(math.dist(p,c['center_cm'])<700 for c in crossings):continue
  for side in [-1,1]:stripe(p,d,0,side*11,10,step+1,'Yellow')
# Standard sign graphics are metric code-drawn assets, not generated photographs.
font='C:/Windows/Fonts/msjhbd.ttc';im=Image.new('RGBA',(512,512),(0,0,0,0));dr=ImageDraw.Draw(im);dr.ellipse((8,8,504,504),fill='#d52f26');dr.ellipse((45,45,467,467),fill='#eeeee7');dr.text((256,254),'30',font=ImageFont.truetype(font,280),anchor='mm',fill='#16191a');im.save(O/'speed30.png')
im=Image.new('RGB',(512,512),'#1762a3');dr=ImageDraw.Draw(im);dr.polygon([(256,45),(455,440),(57,440)],fill='#eeeeea');dr.ellipse((235,145,281,191),fill='#17212a');dr.line([(256,193),(234,278),(195,350)],fill='#17212a',width=22);dr.line([(234,278),(306,342)],fill='#17212a',width=22);dr.line([(248,220),(193,247)],fill='#17212a',width=18);dr.line([(248,220),(304,252)],fill='#17212a',width=18)
for x in range(102,420,65):dr.rectangle((x,374,x+40,393),fill='#17212a')
im.save(O/'pedestrian.png')
layout=dict(status='prepared_requires_native_placement',map_sha256=plan['map_sha256'],materials=materials,groups=groups,crossings=crossings,signals=signals,signs=signs,omitted_approaches=omitted,cycle_seconds=80,cycle=[dict(start=0,end=26,x='green',y='red',ped='red'),dict(start=26,end=30,x='amber',y='red',ped='red'),dict(start=30,end=32,x='red',y='red',ped='red'),dict(start=32,end=58,x='red',y='green',ped='red'),dict(start=58,end=62,x='red',y='amber',ped='red'),dict(start=62,end=64,x='red',y='red',ped='red'),dict(start=64,end=76,x='red',y='red',ped='green'),dict(start=76,end=80,x='red',y='red',ped='red')])
(O/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf8');print('Prepared',len(crossings),'crossings,',len(signals),'vehicle heads,',len(signs),'signs;',sum(len(g['instances']) for g in groups.values()),'instanced parts;',len(omitted),'internal/stub approaches omitted')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
