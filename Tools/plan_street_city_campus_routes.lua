-- Plan connected exterior paths; native physics review is mandatory before install.
local code=[====[
import json,math,heapq,re
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'immersion-v1'
def read(p):return json.loads(p.read_text('utf-8-sig'))
inv=read(O/'inventory.json');actors={r['label']:r for r in inv['actors']};specs={r['id']:r for r in read(B/'resort-architecture-v1/building-input.json')['buildings']}
xmin,ymin,xmax,ymax=54800,19500,97000,77000;step=100
xs=np.arange(xmin+150,xmax-100,step);ys=np.arange(ymin+150,ymax-100,step);X,Y=np.meshgrid(xs,ys,indexing='ij');free=np.ones(X.shape,dtype=bool);paved=np.zeros(X.shape,dtype=bool);obstacles=[]
for bid,spec in specs.items():
 label='Campus_'+bid+'_F01'
 if label not in actors:continue
 a=actors[label];cx,cy=a['origin'][:2];ex,ey=a['extent'][:2]
 # Floor bounds include projecting entrance pads. Keep a narrow walking margin
 # at their outer edge; exact collision clearance is checked in the editor.
 rect=[cx-ex-100,cy-ey-100,cx+ex+100,cy+ey+100];free&=~((X>=rect[0])&(X<=rect[2])&(Y>=rect[1])&(Y<=rect[3]));obstacles.append(dict(kind='building',label=label,rect_cm=rect))
for label in ['Outdoor_campus_track']:
 a=actors[label];cx,cy=a['origin'][:2];ex,ey=a['extent'][:2];rect=[cx-ex-100,cy-ey-100,cx+ex+100,cy+ey+100];free&=~((X>=rect[0])&(X<=rect[2])&(Y>=rect[1])&(Y<=rect[3]));obstacles.append(dict(kind='sports',label=label,rect_cm=rect))
# The perimeter has a recessed segment around PK0101; a rectangular boundary
# alone would route pedestrians outside the fence and through that attraction.
free&=~((X<55600)&(Y>68450)&(Y<71550))
water_access=None
if (O/'water-deck-install.json').exists():
 water_access=read(O/'water-deck-plan.json');bx0,by0,bx1,by1=water_access['access_bridge_bounds_cm'];free&=~((X>=bx0)&(X<=bx1+300)&(Y>=by0-150)&(Y<=by1+150))
obstacles.append(dict(kind='perimeter_recess',label='PK0101 fence recess',rect_cm=[54800,68450,55600,71550]))
for label,a in actors.items():
 if a['hidden'] or not label.startswith(('World_PK_','Activity_','Resort_R','Destination_')):continue
 cx,cy,cz=a['origin'];ex,ey,ez=a['extent']
 if not(xmin<cx<xmax and ymin<cy<ymax and 1<ex<3000 and 1<ey<3000 and cz+ez>1260):continue
 rect=[cx-ex-150,cy-ey-150,cx+ex+150,cy+ey+150];free&=~((X>=rect[0])&(X<=rect[2])&(Y>=rect[1])&(Y<=rect[3]));obstacles.append(dict(kind='attraction_or_fixture',label=label,rect_cm=rect))
history_path=O/'route-block-history.json';history=read(history_path) if history_path.exists() else []
native_path=O/'route-native-review.json'
if native_path.exists():
 review=read(native_path)
 for r in review['blocked']:
  if r['result'].get('point'):history.append(dict(actor=r['result'].get('actor'),point_cm=r['result']['point'][:2]))
 for r in review['unsupported']:history.append(dict(actor=r.get('actor'),point_cm=r['point_cm']))
seen=set();history=[r for r in history if not ((r['actor'],tuple(r['point_cm'])) in seen or seen.add((r['actor'],tuple(r['point_cm']))))]
history_path.write_text(json.dumps(history,indent=2),'utf8')
for r in history:
 x,y=r['point_cm'];free&=(X-x)**2+(Y-y)**2>180**2
trees=[]
for c in inv['components']:
 if not c['visible'] or c['hidden'] or not re.search(r'/TreeUpgradeV[12]/|/FloweringTrees/',c['mesh']):continue
 for t in c.get('instances',[c['transform']]):
  x,y,z=t['translation'];
  if xmin<x<xmax and ymin<y<ymax:
   lo=max(0,int((x-xs[0]-180)/step));hi=min(len(xs),int((x-xs[0]+180)/step)+2);lj=max(0,int((y-ys[0]-180)/step));hj=min(len(ys),int((y-ys[0]+180)/step)+2)
   free[lo:hi,lj:hj]&=(X[lo:hi,lj:hj]-x)**2+(Y[lo:hi,lj:hj]-y)**2>160**2;trees.append([x,y])
roads=read(B/'world-ground-v1/ground-plan.json')['roads']
for r in roads:
 if r['kind']!='campus':continue
 pts=[[(1100-p[1])*100,p[0]*100] for p in r['points_map_m']]
 for a,b in zip(pts,pts[1:]):
  dx,dy=b[0]-a[0],b[1]-a[1];ll=dx*dx+dy*dy
  if ll<1:continue
  u=np.clip(((X-a[0])*dx+(Y-a[1])*dy)/ll,0,1);paved|=(X-a[0]-u*dx)**2+(Y-a[1]-u*dy)**2<(r['width_m']*50)**2
def nearest(point):
 i=round((point[0]-xs[0])/step);j=round((point[1]-ys[0])/step);options=[]
 for di in range(-5,6):
  for dj in range(-5,6):
   a,b=i+di,j+dj
   if 0<=a<len(xs) and 0<=b<len(ys) and free[a,b]:options.append(((xs[a]-point[0])**2+(ys[b]-point[1])**2,(a,b)))
 if not options:return None
 return min(options)[1]
network=set();routes=[];issues=[]
def connect(name,point):
 start=nearest(point)
 if start is None:issues.append(dict(id=name,point_cm=point,reason='No free exterior route start within five metres'));return
 if not network:network.add(start);routes.append(dict(id=name,points_cm=[point,[float(xs[start[0]]),float(ys[start[1]])]],cells=[start]));return
 goal=min(network,key=lambda q:abs(q[0]-start[0])+abs(q[1]-start[1]));queue=[(.6*(abs(goal[0]-start[0])+abs(goal[1]-start[1])),0,start)];cost={start:0};previous={};end=None
 while queue:
  _,g,node=heapq.heappop(queue)
  if g>cost.get(node,math.inf)+1e-8:continue
  if node in network:end=node;break
  for di,dj in [(1,0),(-1,0),(0,1),(0,-1)]:
   n=node[0]+di,node[1]+dj
   if not(0<=n[0]<len(xs) and 0<=n[1]<len(ys)) or not free[n]:continue
   ng=g+(.6 if paved[n] else 1.)
   if ng<cost.get(n,math.inf):cost[n]=ng;previous[n]=node;h=.6*(abs(goal[0]-n[0])+abs(goal[1]-n[1]));heapq.heappush(queue,(ng+h,ng,n))
 if end is None:issues.append(dict(id=name,point_cm=point,reason='Exterior route is disconnected by protected building/sports/tree footprint'));return
 cells=[end]
 while cells[-1]!=start:cells.append(previous[cells[-1]])
 cells.reverse();network.update(cells);points=[point]+[[float(xs[i]),float(ys[j])] for i,j in cells]
 routes.append(dict(id=name,points_cm=points,cells=cells,length_cm=sum(math.dist(a,b) for a,b in zip(points,points[1:])),status='requires_native_support_and_capsule_clearance'))
for name,p in [('gate-SouthMain',[55250,57500]),('gate-SouthWalk',[55250,40000]),('gate-WestSport',[71500,19950]),('gate-NorthDorm',[96550,59500]),('gate-EastGarden',[80000,76550])]:connect(name,p)
entries={}
for row in read(B/'traffic-v1/campus-audit.json')['thresholds']:entries.setdefault(row['entry'],[]).append(row['ground'])
for name,points in entries.items():
 connect(name,points[-1][:2])
 if routes and routes[-1]['id']==name:
  a,b=points[0][:2],points[-1][:2];dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
  lead=[a[0]+dx/length*100,a[1]+dy/length*100]
  routes[-1]['points_cm'].insert(0,lead);routes[-1]['entrance_lead_cm']=[lead,routes[-1]['points_cm'][2]]
if water_access:connect('PK-0105-shore-access',water_access['walk_grid_target_cm'])
mask=np.zeros(free.shape,dtype=bool)
for i,j in network:
 for di in [-1,0,1]:
  for dj in [-1,0,1]:
   a,b=i+di,j+dj
   if 0<=a<len(xs) and 0<=b<len(ys) and free[a,b]:mask[a,b]=True
for route in routes:
 if 'entrance_lead_cm' not in route:continue
 a,b=route['entrance_lead_cm'];distance=math.dist(a,b)
 for t in np.linspace(0,1,max(2,int(distance/40)+1)):
  p=[a[k]*(1-t)+b[k]*t for k in range(2)];i=round((p[0]-xs[0])/step);j=round((p[1]-ys[0])/step)
  for di in [-1,0,1]:
   for dj in [-1,0,1]:
    ni,nj=i+di,j+dj
    if 0<=ni<len(xs) and 0<=nj<len(ys):mask[ni,nj]=True
boxes=[]
for i in range(len(xs)):
 j=0
 while j<len(ys):
  if not mask[i,j]:j+=1;continue
  first=j
  while j+1<len(ys) and mask[i,j+1]:j+=1
  boxes.append(dict(center=[float(xs[i]),float((ys[first]+ys[j])/2),1201.5],size=[100,float((j-first+1)*100),9]));j+=1
def serial(route):return {k:v for k,v in route.items() if k!='cells'}
result=dict(status='planned_requires_native_review',baseline_map_sha256=inv['map_sha256'],routes=[serial(r) for r in routes],issues=issues,boxes=boxes,obstacles=obstacles,tree_obstacles=len(trees),walkway_top_cm=1206,walkway_bottom_cm=1197,policy='Connected pedestrian network inside the five existing gates; preserve buildings and water. Non-overlapping contiguous row strips avoid coplanar top overlaps. Existing PBR world-space paving will be reused.')
(O/'campus-route-plan.json').write_text(json.dumps(result,indent=2),'utf8')
print('Routes:',len(routes),'unresolved:',len(issues),'nonoverlapping paving strips:',len(boxes),'tree obstacles:',len(trees))
for q in issues:print(q)
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
