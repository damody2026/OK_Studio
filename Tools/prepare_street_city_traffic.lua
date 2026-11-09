-- Audit the complete authored road graph, including endpoint/T intersections.
local code=[====[
import json,math,hashlib
from pathlib import Path
from collections import Counter
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'traffic-v1';O.mkdir(exist_ok=True)
def read(p):return json.loads(p.read_text(encoding='utf8'))
roads=read(B/'world-ground-v1/ground-plan.json')['roads'];asphalt=[r for r in roads if r['kind']=='asphalt'];segments=[]
for r in asphalt:
 pts=[[(1100-p[1])*100,p[0]*100] for p in r['points_map_m']]
 for a,b in zip(pts,pts[1:]):
  if math.dist(a,b)>1:segments.append(dict(a=a,b=b,width=r['width_m']*100,road=r['id']))
nodes=[]
for i,s in enumerate(segments):
 ax,ay=s['a'];dx,dy=s['b'][0]-ax,s['b'][1]-ay
 for t in segments[i+1:]:
  if s['road']==t['road']:continue
  cx,cy=t['a'];ux,uy=t['b'][0]-cx,t['b'][1]-cy;den=dx*uy-dy*ux
  if abs(den)<1e-6:continue
  v=((cx-ax)*uy-(cy-ay)*ux)/den;w=((cx-ax)*dy-(cy-ay)*dx)/den
  if not(-.0001<=v<=1.0001 and -.0001<=w<=1.0001):continue
  p=[ax+v*dx,ay+v*dy]
  if not any(math.dist(n,p)<100 for n in nodes):nodes.append(p)
junctions=[]
for p in nodes:
 arms=[]
 for s in segments:
  a,b=s['a'],s['b'];dx,dy=b[0]-a[0],b[1]-a[1];ll=dx*dx+dy*dy;v=((p[0]-a[0])*dx+(p[1]-a[1])*dy)/ll;near=[a[0]+max(0,min(1,v))*dx,a[1]+max(0,min(1,v))*dy]
  if math.dist(p,near)>50:continue
  for end in [a,b]:
   dist=math.dist(end,p)
   if dist<100:continue
   d=[(end[0]-p[0])/dist,(end[1]-p[1])/dist]
   if any(d[0]*q['direction'][0]+d[1]*q['direction'][1]>.97 for q in arms):continue
   arms.append(dict(road=s['road'],direction=d,width_cm=s['width'],length_cm=dist))
 if len(arms)<3:continue
 radius=max(q['width_cm']/2 for q in arms)
 junctions.append(dict(id='J%02d'%(len(junctions)+1),center_cm=p,arms=arms,radius_cm=radius,kind='four_way' if len(arms)==4 else 'T_junction',signalized=max(q['width_cm'] for q in arms)>=1400))
old=read(B/'flat-campus-v1/preservation.json')['after'];legacy=[r for r in old if any(x in r['actor'] for x in ['Street_crosswalk_','Street_traffic_light_','Street_lane_dash_'])]
gates=read(B/'flat-campus-v1/install.json')['enclosure']['gates']
plan=dict(status='road_graph_audited_requires_native_inventory',map_sha256=hashlib.sha256(Path('C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap').read_bytes()).hexdigest(),road_count=len(roads),asphalt_routes=len(asphalt),asphalt_segments=len(segments),junctions=junctions,legacy_marking_components=legacy,gates=gates,policy={'road_markings':'40cm white bars, 50cm gaps, 3m crossing depth; stop lines behind crossings','pedestrians':'crossings connect both sides, tactile warning pads, unobstructed 2m route','traffic':'right-hand carriageways; signal heads face approaching traffic; no simultaneous crossing greens','depth':'sample saved geometry before placement; separated paint top, no collision on markings','scope':'fictional resort university town, visual design references rather than public-road certification'},sources=[{'title':'交通部道路交通標誌標線號誌設置參考指引','url':'https://roadsafety.tw/files/downloads/附件1_道路交通標誌標線號誌設置參考指引_一般道路情境.pdf?v=20250308133607'},{'title':'臺北市交通管制工程處：行人穿越道與停止線','url':'https://bote.gov.taipei/News_Content.aspx?n=20A2BA930381C524&s=40AEEF3E1953582F'}])
(O/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf8')
print('Road audit:',len(roads),'routes,',len(asphalt),'asphalt routes,',len(junctions),'junctions',Counter(q['kind'] for q in junctions),'legacy traffic groups',len(legacy))
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
