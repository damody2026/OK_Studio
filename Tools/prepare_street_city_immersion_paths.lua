-- Plan short direct entrance links against the authored campus route graph.
local code=[====[
import json,math
from pathlib import Path
base=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');out=base/'immersion-v1'
def read(p):return json.loads(p.read_text('utf-8-sig'))
roads=read(base/'world-ground-v1/ground-plan.json')['roads'];segments=[]
for road in roads:
 if road['kind']!='campus':continue
 points=[[(1100-p[1])*100,p[0]*100] for p in road['points_map_m']]
 for a,b in zip(points,points[1:]):segments.append(dict(a=a,b=b,width=road['width_m']*100,road=road['id']))
entries={}
for row in read(base/'traffic-v1/campus-audit.json')['thresholds']:entries.setdefault(row['entry'],[]).append(row['ground'])
links=[];unresolved=[]
for entry,samples in entries.items():
 start=samples[0][:2];last=samples[-1][:2];dx,dy=last[0]-start[0],last[1]-start[1];length=math.hypot(dx,dy);direction=[dx/length,dy/length];candidates=[]
 for road in segments:
  a,b=road['a'],road['b'];ux,uy=b[0]-a[0],b[1]-a[1];den=direction[0]*uy-direction[1]*ux
  if abs(den)<1e-5:continue
  t=((a[0]-start[0])*uy-(a[1]-start[1])*ux)/den;v=((a[0]-start[0])*direction[1]-(a[1]-start[1])*direction[0])/den
  if t>100 and 0<=v<=1:candidates.append((t,road))
 if not candidates:unresolved.append(dict(entry=entry,reason='No forward campus route intersection'));continue
 t,road=min(candidates,key=lambda r:r[0]);end=[start[i]+direction[i]*max(length,t-road['width']/2+20) for i in range(2)]
 if t>6500:unresolved.append(dict(entry=entry,reason='Long link requires manual route review',length_cm=t,road=road['road']));continue
 links.append(dict(entry=entry,start_cm=start,end_cm=end,width_cm=240,length_cm=math.dist(start,end),road=road['road'],direction=direction,status='requires_native_support_and_clearance'))
(out/'entrance-path-plan.json').write_text(json.dumps(dict(status='requires_native_review',baseline_map_sha256=read(out/'inventory.json')['map_sha256'],links=links,unresolved=unresolved),indent=2),'utf8')
print('Entrance links planned:',len(links),'manual review:',len(unresolved))
for r in links:print(r['entry'],round(r['length_cm']/100,1),'m to',r['road'])
for r in unresolved:print('REVIEW',r)
]====]
local pipe=assert(io.popen('python -','w'));assert(pipe:write(code));assert(pipe:close())
