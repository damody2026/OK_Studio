return [====[
def motel_routes():
 installed=read('motel-install');assert installed['map_sha256']==LOAD_SHA;site=read('site-boundary-review');bases={r['building']:r['base'] for r in site['sites']};plan=read('motel-plan');world=unreal.EditorLevelLibrary.get_editor_world();issues=[];routes=[];samples=0;sweeps=0;gamefloors=[];gamesweeps=[];stairwalk=[]
 def pt(bid,v):
  b=bases[bid];return unreal.Vector(b[0]+v[1]*100,b[1]+v[0]*100,b[2]+v[2]*100+6)
 def check(name,bid,points,radius,half,height):
  nonlocal samples,sweeps
  row=dict(id=name,building=bid,segments=0,issues=[])
  for a,b in zip(points,points[1:]):
   length=math.dist(a,b);n=max(1,math.ceil(length/2.0));prev=None
   for k in range(n+1):
    p=[a[i]+(b[i]-a[i])*k/n for i in range(3)];v=pt(bid,p);hit=unreal.SystemLibrary.line_trace_single(world,v+unreal.Vector(0,0,20),v-unreal.Vector(0,0,30),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();samples+=1
    if not hit[0] or abs(hit[4].z-v.z)>20:row['issues'].append(dict(kind='unsupported',point=num(v),hit=num(hit[4]) if hit[0] else None,actor=hit[9].get_actor_label() if hit[0] and hit[9] else None))
    gamefloors.append(dict(route=name,start=num(v+unreal.Vector(0,0,20)),end=num(v-unreal.Vector(0,0,30)),min_z=v.z-20,max_z=v.z+20))
    eye=v+unreal.Vector(0,0,height)
    if prev is not None:
     result=json.loads(unreal.CityDepthAuditLibrary.sweep_clearance(world,prev,eye,radius,half));sweeps+=1;row['segments']+=1
     if radius==35.:gamesweeps.append(dict(route=name,start=num(prev),end=num(eye)))
     if result['blocked']:row['issues'].append(dict(kind='blocked',start=num(prev),end=num(eye),result=result))
    prev=eye
  if row['issues']:issues.append(dict(route=name,issues=row['issues']))
  routes.append(row)
 levels=[0,5,9.6,14,18.3]
 roadwalk=[]
 if installed.get('road_connection'):
  points=[[66,80,-.01],[66,75,0],[66,46,0],[66,34,0]];check('H1-street-to-ramp-connection','H1',points,110.,100.,125.);check('H1-street-to-ramp-pedestrian','H1',points,35.,88.,108.);roadwalk.append(dict(id='H1-street-to-ramp-pedestrian',kind='motel_street_connection',points=[num(pt('H1',p)) for p in points]))
 for i,(lo,hi) in enumerate(zip(levels,levels[1:])):
  mid=(lo+hi)/2;points=[[66,0,lo],[66,34,lo],[54,34,lo],[-54,34,mid],[-58,34,mid],[-58,45,mid],[-54,45,mid],[54,45,hi],[58,45,hi],[66,45,hi],[66,0,hi],[0,0,hi]];check('H1-vehicle-ramp-'+str(i+1),'H1',points,110.,100.,125.)
 # Check every private garage entrance from the gallery and its side pedestrian door.
 for q in plan['rooms']:
  if not q['has_in_room_garage']:continue
  cx,cy,z=q['local_center_m'];sign=1 if q['yaw']==0 else -1;gx=-q['size_m'][0]*.25;x=cx+sign*gx
  check(q['id']+'-garage','H1',[[x,0,z],[x,cy-sign*7.0,z]],110.,100.,125.)
  p0=[cx+sign*(gx+2.1),cy-sign*6.15,z];p1=[cx+sign*(gx+4.2),cy-sign*6.15,z];check(q['id']+'-garage-private-door','H1',[p0,p1],35.,88.,104.)
 for x in [-10,0,10]:
  check('S18-assigned-garage-'+str(x),'S18',[[x,-28,0],[x,-11.5,0]],110.,100.,125.)
  points=[[x,-28,0],[x,-11.5,0]];check('S18-forecourt-walk-'+str(x),'S18',points,35.,88.,108.);roadwalk.append(dict(id='S18-forecourt-walk-'+str(x),kind='motel_forecourt',points=[num(pt('S18',p)) for p in points]))
 poolwalk=[];v2f=ROOT/'output/street-social-city-production/motel-v1/sample-rooms/rooms-v2-build.json'
 V2={r['id'] for r in json.loads(v2f.read_text('utf8'))['rooms']} if v2f.exists() else set()
 for q in plan['rooms']:
  if not q['is_pool_suite']:continue
  cx,cy,z=q['local_center_m'];ang=math.radians(q['yaw']);right=-q['size_m'][0]*.27+4.1
  # rooms-v2 pool suites have ten 13.6 cm access steps; the frozen template 203 keeps the original seven 18 cm steps
  steps=[[right+.24+k*.22,4.2,(10-k)*.136] for k in range(9,-1,-1)] if q['id'] in V2 else [[right+.28+k*.30,4.2,(7-k)*.18] for k in range(6,-1,-1)]
  local=[[right+2.6,4.2,0]]+steps+[[right,4.2,1.36]]+[[right-.125-(k+.5)*.35,4.2,1.36-k*.16] for k in range(6)]+[[right-2.55,4.2,.4]]
  local=local+list(reversed(local[:-1]));points=[[cx+v[0]*math.cos(ang)-v[1]*math.sin(ang),cy+v[0]*math.sin(ang)+v[1]*math.cos(ang),z+v[2]] for v in local];check(q['id']+'-pool-entry-and-exit','H1',points,35.,88.,108.);poolwalk.append(dict(id=q['id']+'-pool-entry-and-exit',kind='private_pool_egress',points=[num(pt('H1',p)) for p in points]))
  local=[[q['size_m'][0]/2-1.25,2.1,0],[q['size_m'][0]/2-1.50,7.1,0],[q['size_m'][0]/2-1.50,8.55,.03],[q['size_m'][0]/2-1.50,7.1,0]];points=[[cx+v[0]*math.cos(ang)-v[1]*math.sin(ang),cy+v[0]*math.sin(ang)+v[1]*math.cos(ang),z+v[2]] for v in local];check(q['id']+'-pool-suite-WC-access','H1',points,35.,88.,108.);poolwalk.append(dict(id=q['id']+'-pool-suite-WC-access',kind='private_pool_bathroom',points=[num(pt('H1',p)) for p in points]))
 # Stairs use the authored rise, actual tread elevations and both arrival landings.
 for bid,ls,x,y in [('H1',levels,68,-19),('S18',[0,4.4,8.8],11.2,-4)]:
  for floor,(lo,hi) in enumerate(zip(ls,ls[1:])):
   n=math.ceil((hi-lo)/.17);half=math.ceil(n/2);r=(hi-lo)/n;points=[[x-1.2,y-.25,lo]]+[[x-1.2,y+k*.30,lo+(k+1)*r] for k in range(half)]+[[x-1.2,y+half*.30+.5,lo+half*r],[x+1.2,y+half*.30+.5,lo+half*r]]+[[x+1.2,y+(n-half-1-k)*.30,lo+(half+k+1)*r] for k in range(n-half)]+[[x+1.2,y-.25,hi]]
   check(bid+'-stairs-'+str(floor+1),bid,points,35.,88.,108.)
   stairwalk.append(dict(id=bid+'-motel-stairs-'+str(floor+1),kind='motel_stair',points=[num(pt(bid,p)) for p in points]))
 assert sha(MAPFILE)==LOAD_SHA;write('route-review',dict(status='passed' if not issues else 'requires_repair',map_sha256=LOAD_SHA,ground_samples=samples,capsule_sweeps=sweeps,routes=routes,issues=issues,game_floors=gamefloors,game_sweeps=gamesweeps,stair_walk=stairwalk,pool_walk=poolwalk,road_walk=roadwalk,scope='Native car-envelope ramps,52 private and3 assigned garages,all private pedestrian doors,six stair flights,four pool entry/exit and bathroom approaches,street connection. Actual CharacterMovement remains a separate required replay.'))

def motel_physics_plan():
 install=read('motel-install');audit=read('audit');route=read('route-review');assert install['map_sha256']==audit['map_sha256']==route['map_sha256']==LOAD_SHA;assert audit['status']==route['status']=='passed'
 oldpath=ROOT/'output/street-social-city-production/immersion-v1/game-physics-plan.json';p=json.loads(oldpath.read_text('utf8'));oldsha=sha(oldpath);counts={k:len(p[k]) for k in ['rays','floors','sweeps','fixture_positive_rays']}
 def keep(r):
  if r.get('building') in ['H1','S18']:return False
  return not re.search(r'(^|[^A-Za-z0-9])(H1|S18)([^A-Za-z0-9]|$)',r.get('id','')+' '+r.get('route',''))
 for k in counts:p[k]=[r for r in p[k] if keep(r)]
 p['floors']+=route['game_floors'];p['sweeps']+=route['game_sweeps'];walk=[];byid={r['id']:r for r in read('motel-plan')['rooms']}
 for r in install['rooms']:
  q=byid[r['id']];base=r['position'];a=math.radians(q['yaw']);w=q['size_m'][0]
  def world(v):return [base[0]+(v[0]*math.sin(a)+v[1]*math.cos(a))*100,base[1]+(v[0]*math.cos(a)-v[1]*math.sin(a))*100,base[2]]
  local=[[w*.29,-11.2],[w*.29,-9.2],[w*.29,-5],[w/2-1.25,-5],[w/2-1.25,2.1],[(w*.14 if q['is_pool_suite'] else -w*.22)+2.8,2.1]]
  points=[world(v) for v in local];walk.append(dict(id=r['id']+'-actual-player-entry',kind='motel_suite',points=points))
  for eye in [r['eye'],r['bath_eye'],r['entry']]:p['floors'].append(dict(route=r['id'],start=eye,end=[eye[0],eye[1],eye[2]-200],min_z=base[2]-5,max_z=base[2]+12))
 p.update(status='planned_for_actual_game_replay',map_sha256=LOAD_SHA,walk_routes=route['stair_walk']+route['pool_walk']+route.get('road_walk',[])+walk,previous_accepted_plan_sha256=oldsha,previous_counts=counts,motel_rooms=61,scope='Replays unchanged nonhotel physics plus motel floors/doors/stairs,pool entry/exit,bathroom and street access. Actual CharacterMovement covers61 suite approaches,six stair flights,four pools and their WCs,street connection;larger car-envelope checks stay separate. No old-map replay is presented as new evidence.')
 if install.get('branch_expansion'):
  group=next(g for g in p['stem_groups'] if any(t['instance']==268 and abs(t['center'][0]-50840)<1 for t in g['targets']));target=next(t for t in group['targets'] if t['instance']==268);target['center'][0]+=1500
  links=[r for r in p['stem_render_links'] if r['proxy_instance']==268 and abs(r['expected_root_cm'][0]-50840)<1];assert links
  for r in links:r['expected_root_cm'][0]+=1500
  p['bounded_branch_landscape_migration']=dict(receipt_sha256=sha(OUT/'branch-expansion.json'),proxy_instance=268,delta_cm=[1500,0,0],render_links=len(links),scope='Relocated tree and matching trunk proxy; original instance counts and all other collision tolerances retained.')
 # the tree moved out of the inn by the lover spots install, and its trunk proxy
 group=next(g for g in p['stem_groups'] if any(t['instance']==1431 and abs(t['center'][0]-70776.66)<1 for t in g['targets']));target=next(t for t in group['targets'] if t['instance']==1431);target['center'][0]+=600;target['center'][1]-=1200
 links=[r for r in p['stem_render_links'] if r['proxy_instance']==1431 and abs(r['expected_root_cm'][0]-70776.66)<1];assert links
 for r in links:r['expected_root_cm'][0]+=600;r['expected_root_cm'][1]-=1200
 write('game-physics-plan',p)

def motel_migrate_mirror_expectations():
 p=read('game-physics-plan');assert p['map_sha256']==LOAD_SHA;world=unreal.EditorLevelLibrary.get_editor_world();banks={r['actor']+'_'+suffix:r for r in read('restroom-mirrors-install')['mirrors'] for suffix in ['Glass','Backing']};changed=[];unresolved=[]
 for r in p['rays']:
  if r.get('kind')!='school_glazing' or not r.get('expected_hit') or 'expected_point' not in r:continue
  start=unreal.Vector(*r['start']);end=unreal.Vector(*r['end']);h=unreal.SystemLibrary.line_trace_single(world,start,end,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True).to_tuple();old=unreal.Vector(*r['expected_point'])
  if h[0] and (h[4]-old).length()<=1:continue
  label=h[9].get_actor_label() if h[0] and h[9] else '';b=banks.get(label)
  valid=False
  if b:
   face=unreal.Vector(*b['face']);n=unreal.Vector(*b['normal']);t=unreal.Vector(-n.y,n.x,0);offset=old-face
   border=label.endswith('_Backing');valid=b['backing_actor']==r['building'] and (h[4]-old).length()<=3.30 and abs(unreal.MathLibrary.dot_vector_vector(offset,n)+2.5)<.1 and abs(unreal.MathLibrary.dot_vector_vector(offset,t))<=b['width_cm']/2+(2.1 if border else .1) and abs(offset.z)<=(49.6 if border else 47.6) and 'RestroomMirror' in [str(v) for v in h[9].tags]
  if not valid:unresolved.append(dict(id=r['id'],actor=label,old_point=r['expected_point'],actual=num(h[4]) if h[0] else None));continue
  changed.append(dict(id=r['id'],building=r['building'],mirror_actor=label,verified_backing_actor=b['backing_actor'],before=r['expected_point'],after=num(h[4]),distance_cm=(h[4]-old).length()));r['expected_point']=num(h[4]);r['motel_mirror_surface_migration']=True
 assert not unresolved,('Unbounded geometry changes cannot be accepted as mirror migration',unresolved[:5]);assert changed,'No bounded mirror migrations found';assert sha(MAPFILE)==LOAD_SHA;p['mirror_surface_migrations']=len(changed);write('game-physics-plan',p);write('mirror-collision-migration',dict(status='passed_source_bounds_requires_cooked_replay',map_sha256=LOAD_SHA,changed=len(changed),rows=changed,unresolved=unresolved,retained_position_tolerance_cm=1.,scope='Only old positive school-window rays now intercepted by the tagged mirror glass with matching verified backing owner,within the bank rectangle and3.30cm of the original face. Hit=true and player-simple queries retained;global1cm cooked tolerance unchanged. No map or asset bytes changed.'))
]====]
