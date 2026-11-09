local code=[====[
import json,math,bisect
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/traffic-v1')
def read(p):return json.loads(p.read_text(encoding='utf8'))
plan=read(O/'plan.json');layout=read(O/'layout.json');roads=read(O.parent/'world-ground-v1/ground-plan.json')['roads'];parts=[];counts={'edges':0,'lane_dashes':0,'arrows':0}
def clear(p):return not any(math.dist(p,j['center_cm'])<j['radius_cm']+1200 for j in plan['junctions']) and not any(math.dist(p,c['center_cm'])<700 for c in layout['crossings'])
def add(p,length,width,yaw,kind):parts.append(dict(center=[*p,1205.4],size=[length,width,.2],yaw=yaw,kind=kind));counts[kind]+=1
for road in roads:
 if road['kind']!='asphalt':continue
 pts=[[(1100-p[1])*100,p[0]*100] for p in road['points_map_m']];cum=[0.]
 for a,b in zip(pts,pts[1:]):cum.append(cum[-1]+math.dist(a,b))
 def sample(t):
  i=min(len(pts)-2,bisect.bisect_right(cum,t)-1);a,b=pts[i],pts[i+1];ll=cum[i+1]-cum[i];d=[(b[k]-a[k])/ll for k in range(2)];return [a[k]+d[k]*(t-cum[i]) for k in range(2)],d
 width=road['width_m']*100
 count=max(1,math.ceil(cum[-1]/200));step=cum[-1]/count
 for i in range(count):
  p,d=sample((i+.5)*step)
  if not clear(p):continue
  n=[-d[1],d[0]];yaw=math.degrees(math.atan2(d[1],d[0]))
  for side in [-1,1]:add([p[k]+n[k]*side*(width/2-50) for k in range(2)],step,10,yaw,'edges')
 if width>=1400:
  for i in range(int(cum[-1]//800)):
   p,d=sample(i*800+400)
   if not clear(p):continue
   n=[-d[1],d[0]];yaw=math.degrees(math.atan2(d[1],d[0]))
   for side in [-1,1]:add([p[k]+n[k]*side*width/4 for k in range(2)],300,10,yaw,'lane_dashes')
for j in plan['junctions']:
 for a in j['arms']:
  d=a['direction']
  if not any(sum(d[k]*b['direction'][k] for k in range(2))<-.9 for b in j['arms']):continue
  dist=j['radius_cm']+1900
  if a['road']!='path-025' and a['length_cm']<dist+500:continue
  p=[j['center_cm'][k]+d[k]*dist for k in range(2)]
  if any(other['id']!=j['id'] and math.dist(p,other['center_cm'])<other['radius_cm']+1000 for other in plan['junctions']):continue
  n=[-d[1],d[0]];w=a['width_cm'];offsets=[w/8,3*w/8] if w>=1400 else [w/4];yaw=math.degrees(math.atan2(-d[1],-d[0]))
  for offset in offsets:
   q=[p[k]+n[k]*offset for k in range(2)];add(q,160,14,yaw,'arrows')
   for side in [-1,1]:
    c=[q[k]-d[k]*90+n[k]*side*27 for k in range(2)];add(c,90,16,yaw+side*40,'arrows')
arrow=edge=0
for r in parts:
 if r['kind']=='arrows':r['size'][2]=[.2,.4,.6][arrow%3];arrow+=1
 elif r['kind']=='edges':r['size'][2]=.2+.2*((edge//2)%2);edge+=1
(O/'lane-detail-plan.json').write_text(json.dumps(dict(status='prepared_requires_native_height_sampling',parts=parts,counts=counts,join_depth='0.1cm stagger at adjoining/overlapping paint strokes'),indent=2),encoding='utf8');print('Lane detail:',len(parts),'parts',counts)
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
