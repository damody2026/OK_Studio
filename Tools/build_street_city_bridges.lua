local code=[====[
import json,math
from pathlib import Path
from collections import defaultdict
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/traffic-v1')
def read(p):return json.loads(p.read_text(encoding='utf8'))
support=read(O/'geometry-support.json');roads=read(O.parent/'world-ground-v1/ground-plan.json')['roads'];missing=defaultdict(list);route={r['id']:r for r in roads}
for p in support['missing']:
 best=(1e12,None)
 for rid in ['path-026','path-027','path-028']:
  r=route[rid];a,b=[[(1100-q[1])*100,q[0]*100] for q in r['points_map_m']];dx,dy=b[0]-a[0],b[1]-a[1];ll=dx*dx+dy*dy;t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/ll));dist=math.dist(p,[a[0]+t*dx,a[1]+t*dy])
  if dist<best[0]:best=(dist,rid)
 if best[0]<20:missing[best[1]].append(p)
groups={};bridges=[]
def add(mat,p,size,yaw=0):groups.setdefault(mat,[]).append(dict(center=p,size=size,yaw=yaw))
for rid,points in missing.items():
 r=route[rid];a,b=[[(1100-q[1])*100,q[0]*100] for q in r['points_map_m']];length=math.dist(a,b);d=[(b[i]-a[i])/length for i in range(2)];n=[-d[1],d[0]];along=[sum((p[i]-a[i])*d[i] for i in range(2)) for p in points];lo,hi=min(along)-400,max(along)+400;span=hi-lo;width=r['width_m']*100;center=[a[i]+d[i]*(lo+hi)/2 for i in range(2)];yaw=math.degrees(math.atan2(d[1],d[0]));bridges.append(dict(id='Bridge_'+rid,road=rid,center_cm=center,direction=d,span_cm=span,carriageway_cm=width,deck_top_cm=1204,sidewalk_top_cm=1205.5,walkway_width_cm=250))
 def pos(t=0,s=0,z=1204):return [center[0]+d[0]*t+n[0]*s,center[1]+d[1]*t+n[1]*s,z]
 add('Deck',pos(z=1179),[span,width+520,50],yaw)
 for side in [-1,1]:
  add('Walk',pos(s=side*(width/2+125),z=1195.5),[span,250,20],yaw)
  add('Metal',pos(s=side*(width/2+230),z=1309.5),[span,8,8],yaw)
  add('Metal',pos(s=side*(width/2+230),z=1250.5),[span,5,5],yaw)
  count=math.ceil(span/180)
  for i in range(count+1):add('Metal',pos(t=-span/2+i*span/count,s=side*(width/2+230),z=1255.5),[8,8,100],yaw)
 for i in range(1,max(2,math.ceil(span/1500))):
  t=-span/2+i*span/max(2,math.ceil(span/1500));add('Concrete',pos(t=t,z=1139),[110,width+200,30],yaw)
  for side in [-1,1]:add('Concrete',pos(t=t,s=side*width/3,z=1069),[120,120,140],yaw)
 for side in [-1,1]:add('Concrete',pos(t=side*(span/2-150),z=1129),[280,width+520,150],yaw)
materials={'Deck':'/Game/UniversityCity/GroundPBRV2/Materials/MI_Detail_932bc009ac742438e2bf.MI_Detail_932bc009ac742438e2bf','Walk':'/Game/UniversityCity/WhitePathsV1/Materials/MI_StoneSlabs_TwoSided.MI_StoneSlabs_TwoSided','Concrete':'/Game/UniversityCity/TrafficV1/Repair2/Materials/M_Concrete.M_Concrete','Metal':'/Game/UniversityCity/TrafficV1/Repair2/Materials/M_Metal.M_Metal'}
(O/'bridge-plan.json').write_text(json.dumps(dict(status='prepared_requires_native_render',bridges=bridges,groups=groups,materials=materials,source_map_sha256=read(O/'surface-current-receipt.json')['map_sha256'],evidence='184 centre-line sample positions lacked any terrain triangle; three authored east-west roads cross the river with no deck.'),indent=2),encoding='utf8');print('Prepared',len(bridges),'bridges:',[(q['road'],round(q['span_cm']/100,1)) for q in bridges])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
