-- Read-only native job: outdoor anchors that need the ground measured (doc section 10.1), nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_anchor_fit Tools/street_city_anchor_fit_payload.lua
-- Every candidate snaps to the walkable ground nearby (top surface, a 35 cm sphere fits above it) or is dropped.
--   stroll      ordered route points: riverbank, bridge, coast, shop street, campus lamps, park
--   riverbank, bridge, coast, rooftops, behind the school buildings: the views, confessions and quiet corners
-- Output: places-v1/anchor-fit.json with rows Tools/street_city_new_anchors.lua turns into anchors.
return [====[
AF_OUT=ROOT/'output/street-social-city-production/places-v1'
def motel_world_anchor_fit():
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],N,True);h=r.to_tuple() if r else [False]
  return h if h[0] else None
 def clear(x,y,z):
  s=unreal.SystemLibrary.sphere_trace_single(world,V(x,y,z+100),V(x,y,z+101),35.,Q,True,[],N,True)
  return not(s is not None and s.to_tuple()[0])
 def ground(x,y,z,up=250,down=400):
  h=ray(V(x,y,z+up),V(x,y,z-down))
  return h[4].z if h and h[7].z>.7 else None
 def snap(x,y,z,reach=400,up=250):
  for r in range(0,reach+1,50):
   n=1 if r==0 else max(6,int(r/12))
   for k in range(n):
    a=2*math.pi*k/n;px,py=x+r*math.cos(a),y+r*math.sin(a);g=ground(px,py,z,up)
    if g is not None and clear(px,py,g):return [round(px,1),round(py,1),round(g,1)]
  return None
 rows=[];drop={}
 def put(name,x,y,z,yaw,kinds,tags=None,privacy=0,place='public',pair=True,reach=400,up=250,**o):
  p=snap(x,y,z,reach,up)
  if not p:drop[name]=drop.get(name,0)+1;return None
  rows.append(dict(name=name,pos=p,yaw=round(yaw,1),kinds=kinds,tags=tags,privacy=privacy,place=place,pair=pair,**o));return p
 A=json.loads((AF_OUT/'actors.json').read_text('utf8'))['actors'];by={a['label']:a for a in A}
 P=json.loads((AF_OUT/'places.json').read_text('utf8'));gp={g['id']:g for g in P['game_places']}
 D=json.loads((AF_OUT/'props.json').read_text('utf8'));area={a['id']:a for a in D['areas']}
 def along(a,step):
  # points down the long axis of a box actor
  c,e=a['c'],a['e'];ax=0 if e[0]>e[1] else 1;n=max(2,int(2*e[ax]/step))
  return [([c[0]-e[0]+2*e[0]*i/(n-1),c[1]] if ax==0 else [c[0],c[1]-e[1]+2*e[1]*i/(n-1)])+[c[2]+e[2]] for i in range(n)],ax
 def yaw_along(ax):return -90 if ax==0 else 0
 RIVER=['stroll','fireworks','picnic','seat_ground','stand_pair','lean','view_night']
 if 'Traffic_Riverbank_Deck' in by:
  pts,ax=along(by['Traffic_Riverbank_Deck'],800)
  for i,p in enumerate(pts):
   put('stroll_river',p[0],p[1],p[2],yaw_along(ax),RIVER if i%3==0 else ['stroll'],['route:river','water','night_view'],up=600,reach=600)
 if 'Traffic_Bridge_Walk' in by:
  pts,ax=along(by['Traffic_Bridge_Walk'],1000)
  for i,p in enumerate(pts):
   put('stroll_bridge',p[0],p[1],p[2],yaw_along(ax),['stroll','kiss','view_night','stand_pair','lean','confess'] if i%2 else ['stroll'],['route:bridge','water','night_view'],up=600,reach=500)
 # coast: the lifeguards run down the beach; route points between them and the view spots at each
 lg=[a for a in gp.get('beach',{}).get('anchors',[]) if a['name'].startswith('lifeguard')]
 lg.sort(key=lambda a:a['pos'][1])
 for i,a in enumerate(lg):
  x,y,z=a['pos']
  put('beach_view',x-300,y,z,-90,['view_sunset','stargaze','fireworks','confess','seat_ground','lie_pair','picnic','lap_pillow','selfie','gift','kiss'],['sunset','night_view','water'],place='beach',reach=800)
  if i+1<len(lg):
   q=lg[i+1]['pos']
   for t in (0,.25,.5,.75):put('stroll_coast',x+(q[0]-x)*t,y+(q[1]-y)*t,z,0,['stroll'],['route:coast','water'],reach=800)
 # shop street: shop entrances in order, a step out from the door
 ent=sorted([a for a in D['areas'] if a.get('kind')=='building' and re.match(r'building_s\d+$',a['id'])],key=lambda a:(round(a['door'][0]/3000),a['door'][1]))
 for i,a in enumerate(ent):
  if i%3==0:put('stroll_shops',a['door'][0],a['door'][1],a['door'][2],0,['stroll'],['route:shops'],reach=500)
 # campus: the lantern lamps line the paths; a nearest-neighbour chain gives the walk
 lamps=[]
 for a in SUB.get_all_level_actors():
  tags=[str(t) for t in a.tags]
  if 'StreetScenery-v1' in tags and 'Asset-lamp-lantern' in tags:
   c=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
   for i in range(c.get_instance_count() if c else 0):
    t=c.get_instance_transform(i,True).translation;lamps.append((t.x,t.y,t.z))
 best=[]
 for s in lamps[::40]:
  left=set(range(len(lamps)));cur=s;chain=[]
  while True:
   nb=min(left,key=lambda i:math.hypot(lamps[i][0]-cur[0],lamps[i][1]-cur[1]),default=None)
   if nb is None or math.hypot(lamps[nb][0]-cur[0],lamps[nb][1]-cur[1])>8000:break
   left.discard(nb);cur=lamps[nb];chain.append(cur)
  if len(chain)>len(best):best=chain
 for p in best[:40]:put('stroll_campus',p[0]+120,p[1]+120,p[2],0,['stroll'],['route:campus','shade'],reach=300)
 # park: its anchors in a loop around their centre
 pk=gp.get('park',{}).get('anchors',[])
 if pk:
  mx,my=sum(a['pos'][0] for a in pk)/len(pk),sum(a['pos'][1] for a in pk)/len(pk)
  for a in sorted(pk,key=lambda a:math.atan2(a['pos'][1]-my,a['pos'][0]-mx)):put('stroll_park',a['pos'][0],a['pos'][1],a['pos'][2],0,['stroll'],['route:park'],reach=300)
 fest=gp.get('festival',{}).get('door')
 if fest:put('fireworks',fest[0],fest[1],fest[2],0,['fireworks','meet'],['festival','night_view'],place='festival',reach=500)
 # behind each school building: the side away from its entrance, a wall to lean on and few people
 for b in ('T1','T2','T4','E1','EE','MA','RB','IB','LI','SC','IN','SP','D1','D2'):
  a=area.get('building_'+b.lower())
  if not a or 'min' not in a:continue
  cx,cy=(a['min'][0]+a['max'][0])/2,(a['min'][1]+a['max'][1])/2;dx,dy=cx-a['door'][0],cy-a['door'][1];n=math.hypot(dx,dy) or 1;dx,dy=dx/n,dy/n
  hx,hy=(a['max'][0]-a['min'][0])/2,(a['max'][1]-a['min'][1])/2;d=(hx if abs(dx)>abs(dy) else hy)+200
  yaw=math.degrees(math.atan2(dy,dx))+90
  put('behind',cx+dx*d,cy+dy*d,a['min'][2],yaw,['confess','kiss','wall_pin','h_wall','lean'],['shade'],1,reach=600,building=b)
 # flat roofs: a free spot near the middle of each teaching building and dorm, then the edge
 for b in ('T1','T2','T4','E1','D1','D2','LI'):
  a=area.get('building_'+b.lower())
  if not a or 'min' not in a:continue
  cx,cy=(a['min'][0]+a['max'][0])/2,(a['min'][1]+a['max'][1])/2;top=a['max'][2]+800
  h=ray(V(cx,cy,top),V(cx,cy,a['min'][2]));z=h[4].z if h else None
  if z is None or z<a['min'][2]+300:continue
  put('rooftop',cx,cy,z,0,['rooftop_lunch','seat_ground','feed','stargaze','fireworks','picnic','lie_pair','lap_pillow','h_floor'],['night_view'],1,place='rooftop',reach=800,up=120,building=b)
  put('rooftop_edge',a['max'][0]-150,cy,z,-90,['confess','view_sunset','view_night','lean','h_fence','kiss'],['sunset','night_view'],1,place='rooftop',reach=800,up=120,building=b)
 assert sha(MAPFILE)==LOAD_SHA
 (AF_OUT/'anchor-fit.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,dropped=drop,rows=rows),ensure_ascii=False),'utf8')
]====]
