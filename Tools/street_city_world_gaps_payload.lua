-- World gaps after the 11-02 recapture (Docs/STREET_CITY_PENDING_MAP_INSTALLS_20261102.md). Native jobs, each queued
-- with: lua Tools/street_city_motel_job.lua <job> Tools/street_city_world_gaps_payload.lua
--   world_gaps_probe          read-only data for the items below (see next block)
--   world_road_raster_probe   read-only 2 m walk-surface raster -> road-raster.json (Tools/find_street_city_road_ends.lua)
--   world_road_ends_install   turning circles / road strips at the street ends in road-ends.json
--   world_landmark_collision  Landmark_* props block the player with their convex hulls
--   world_groves_install      tree groves on the big empty lawns
-- Every install backs the map up to world-edge-v1/UniversityCity-before-<tag>-<sha>.umap and writes a receipt there.
--   world_gaps_probe (read-only, nothing saved):
--     sand_edge  west coast x -30..250 m, y over the union every 2 m, 1 m cells: first ground surface under the
--                dressing (WorldEdge_/Beach_/Park_/Landmark_ and actors under 15 m extent are passed through, water too):
--                hit label (index into mats; the material lookup returns no section name) and top z;
--     roads      every actor whose label / mesh / material names a road, street, asphalt, curb, kerb, crosswalk,
--                sidewalk or path: label, class, bounds, yaw, mesh and material leaves;
--     landmarks  every Landmark_* actor: bounds, collision enabled / profile, body setup trace flag and simple shapes;
--     trees      static mesh assets whose path names a tree, with instance counts (actors and instanced components)
--                and one sample transform each, so new groves reuse the city's own trees;
--     lots       every actor under 60 m extent whose bounds centre lies in x 550-1100 m, y 400-1100 m, for the A13 / A17
--                empty-lot layout.
--   Output: output/street-social-city-production/world-edge-v1/gaps-probe.json
return [====[
EDGE_OUT=ROOT/'output/street-social-city-production/world-edge-v1'
def motel_world_gaps_probe():
 world=unreal.EditorLevelLibrary.get_editor_world();P=json.loads((EDGE_OUT/'probe.json').read_text('utf8'));x0,y0,x1,y1=P['city_ground_union']
 acts=SUB.get_all_level_actors();info={}
 for a in acts:
  try:info[a.get_actor_label()]=a.get_actor_bounds(False)
  except Exception:pass
 def leaf(p):return p.split('/')[-1].split('.')[-1] if p else ''
 def wetlabel(l):return bool(re.match(r'^G\d\d_Water$',l)) or l.startswith('Activity_ACTSPACE') or 'ocean' in l.lower()
 mats=[];mi={}
 def midx(m):
  if m not in mi:mi[m]=len(mats);mats.append(m)
  return mi[m]
 def top(x,y):
  ign=[]
  for _ in range(12):
   r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,5000),unreal.Vector(x,y,-5000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ign,unreal.DrawDebugTrace.NONE,True)
   t=r.to_tuple() if r is not None else (False,)
   if not t[0] or t[9] is None:return -1,-1
   a=t[9];l=a.get_actor_label();b=info.get(l)
   if wetlabel(l) or l.startswith(('WorldEdge_','Beach_','Park_','Landmark_')) or (b is not None and max(b[1].x,b[1].y)<1500):ign.append(a);continue
   m=''
   try:
    mm=t[10].get_material(t[11]) if t[10] is not None else None;m=leaf(mm.get_path_name()) if mm else ''
   except Exception:pass
   return midx(l+'|'+m),int(round(t[4].z))
  return -1,-1
 xs=list(range(int(x0)-3000,int(x0)+25000,100));sand=[];y=int(y0)+100
 while y<y1:
  cs=[top(x,y) for x in xs];sand.append(dict(y=y,m=' '.join(str(c[0]) for c in cs),z=' '.join(str(c[1]) for c in cs)));y+=200
 def comps(a):
  out=[]
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   sm=c.static_mesh;ms=[]
   for k in range(c.get_num_materials()):
    m=c.get_material(k);ms.append(leaf(m.get_path_name()) if m else '')
   out.append(dict(comp=c.get_name(),mesh=sm.get_path_name() if sm else '',mats=ms,instances=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else 0,collision=str(c.get_collision_enabled()),profile=str(c.get_collision_profile_name())))
  return out
 roads=[];lands=[];lots=[];trees={}
 RX=re.compile(r'road|street|asphalt|curb|kerb|crosswalk|sidewalk|path|lane',re.I)
 for a in acts:
  l=a.get_actor_label();b=info.get(l)
  if b is None:continue
  o,e=b
  if e.x>2e6:continue
  bb=[round(v) for v in (o.x-e.x,o.y-e.y,o.z-e.z,o.x+e.x,o.y+e.y,o.z+e.z)];cs=None
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   sm=c.static_mesh
   if sm is None:continue
   p=sm.get_path_name()
   if 'tree' in p.lower():
    t=trees.setdefault(p,dict(actors=0,instances=0,sample=None))
    if isinstance(c,unreal.InstancedStaticMeshComponent):
     t['instances']+=c.get_instance_count()
     if t['sample'] is None and c.get_instance_count():
      tr=c.get_instance_transform(0,True);t['sample']=dict(actor=l,comp=c.get_name(),loc=[tr.translation.x,tr.translation.y,tr.translation.z],scale=[tr.scale3d.x,tr.scale3d.y,tr.scale3d.z],collision=str(c.get_collision_enabled()))
    else:
     t['actors']+=1
     if t['sample'] is None:t['sample']=dict(actor=l,comp=c.get_name(),loc=[o.x,o.y,o.z],scale=[a.get_actor_scale3d().x,a.get_actor_scale3d().y,a.get_actor_scale3d().z],collision=str(c.get_collision_enabled()))
  if l.startswith('Landmark_'):
   cs=comps(a);bs=[]
   for c in a.get_components_by_class(unreal.StaticMeshComponent):
    s=c.static_mesh.get_editor_property('body_setup') if c.static_mesh else None
    if s:
     g=s.get_editor_property('agg_geom');n={}
     for k in ('box_elems','convex_elems','sphere_elems','sphyl_elems'):
      try:n[k]=len(g.get_editor_property(k))
      except Exception:n[k]=None
     bs.append(dict(trace=str(s.get_editor_property('collision_trace_flag')),**n))
   lands.append(dict(label=l,cls=a.get_class().get_name(),bounds=bb,components=cs,body_setups=bs))
  if RX.search(l) or any(RX.search(leaf(c.static_mesh.get_path_name()) if c.static_mesh else '') for c in a.get_components_by_class(unreal.StaticMeshComponent)):
   roads.append(dict(label=l,cls=a.get_class().get_name(),bounds=bb,yaw=round(a.get_actor_rotation().yaw,2),components=cs or comps(a)))
  if max(e.x,e.y)<6000 and 55000<=o.x<=x1 and 40000<=o.y<=y1:
   lots.append(dict(label=l,bounds=bb))
 assert sha(MAPFILE)==LOAD_SHA
 (EDGE_OUT/'gaps-probe.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,union=[x0,y0,x1,y1],sand_edge=dict(x_cm=xs,mats=mats,rows=sand),roads=roads,landmarks=lands,trees=trees,lots=lots),ensure_ascii=False),'utf8')

def _gaps_backup(tag):
 b=EDGE_OUT/('UniversityCity-before-'+tag+'-'+LOAD_SHA[:16]+'.umap')
 if not b.exists():shutil.copy2(MAPFILE,b)
 return b
def _gaps_save(tag,data):
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 data.update(map_sha256=new,parent_map_sha256=LOAD_SHA)
 (EDGE_OUT/(tag+'-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(data,ensure_ascii=False,indent=1),'utf8')

def motel_world_landmark_collision():
 # world_landmark_collision (rule): every Landmark_* prop (fountains, newsstands, cafe sets, clock tower, stage, gazebos,
 # playgrounds, lighthouse) was placed NoCollision, so the player walked through them (gaps-probe 11-02: all 32). Each
 # mesh already carries one simple convex hull; the components block pawns with it (simple collision only, so the hull,
 # not the render triangles, is what the capsule meets) and characters may not step up on them. A landmark the motel
 # route review (motel-v1/route-review.json, routes job) found blocking a planned route stands on that route (the stage
 # on the S18 garage-10 forecourt, 11-02): it stays NoCollision and is listed as misplaced instead of cutting the route.
 _gaps_backup('landmark-collision');rows=[];skip=set()
 rr=OUT/'route-review.json'
 if rr.exists():
  for r in json.loads(rr.read_text('utf-8-sig')).get('issues',[]):
   for i in r['issues']:
    l=(i.get('result') or {}).get('actor','')
    if l.startswith('Landmark_'):skip.add(l)
 for a in SUB.get_all_level_actors():
  if not a.get_actor_label().startswith('Landmark_'):continue
  if a.get_actor_label() in skip:
   for c in a.get_components_by_class(unreal.StaticMeshComponent):c.set_collision_profile_name('NoCollision');c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
   continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   sm=c.static_mesh
   if sm is None:continue
   bs=sm.get_editor_property('body_setup');n=len(bs.get_editor_property('agg_geom').get_editor_property('convex_elems')) if bs else 0
   assert n>0,('no simple collision on',a.get_actor_label(),sm.get_path_name())
   c.set_collision_profile_name('BlockAll');c.set_collision_enabled(unreal.CollisionEnabled.QUERY_AND_PHYSICS)
   c.set_editor_property('can_character_step_up_on',unreal.CanBeCharacterBase.ECB_NO)
   rows.append(dict(label=a.get_actor_label(),mesh=sm.get_path_name().split('/')[-1],convex=n))
 assert rows,'no Landmark_ actors'
 _gaps_save('landmark-collision',dict(status='saved_requires_walk',components=rows,misplaced_on_routes=sorted(skip)))

def motel_world_road_raster_probe():
 # world_road_raster_probe (read-only): 2 m raster of what the player stands on over the city union, for the road end
 # search (Tools/find_street_city_road_ends.lua). Per cell one char: '.' nothing / water bed (< 1150), 'g' grass-level
 # city ground G?? (< 1201), 'r' road (city ground G?? raised to 1203-1210, or Street_paving* / Traffic_Bridge*),
 # 'o' anything else (buildings, props, other ground). Small dressing (< 1.5 m extent: lamps, bins) is passed through.
 world=unreal.EditorLevelLibrary.get_editor_world();P=json.loads((EDGE_OUT/'probe.json').read_text('utf8'));x0,y0,x1,y1=P['city_ground_union']
 info={}
 for a in SUB.get_all_level_actors():
  try:info[a.get_actor_label()]=a.get_actor_bounds(False)
  except Exception:pass
 def cell(x,y):
  ign=[]
  for _ in range(6):
   r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,5000),unreal.Vector(x,y,-5000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ign,unreal.DrawDebugTrace.NONE,True)
   t=r.to_tuple() if r is not None else (False,)
   if not t[0] or t[9] is None:return '.'
   l=t[9].get_actor_label();z=t[4].z;b=info.get(l)
   if b is not None and max(b[1].x,b[1].y)<150:ign.append(t[9]);continue
   if re.match(r'^G\d\d$',l):return '.' if z<1150 else 'g' if z<1201 else 'r' if z<=1210 else 'o'
   if l.startswith(('Street_paving','Traffic_Bridge')):return 'r'
   return 'o'
  return 'o'
 S=200;rows=[];y=y0+S/2
 while y<y1:rows.append(''.join(cell(x0+S/2+k*S,y) for k in range(int((x1-x0)//S))));y+=S
 assert sha(MAPFILE)==LOAD_SHA
 (EDGE_OUT/'road-raster.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,origin=[x0+S/2,y0+S/2],step_cm=S,rows=rows)),'utf8')
def motel_world_road_ends_install():
 # world_road_ends_install (rule): every street end from world-edge-v1/road-ends.json (Tools/find_street_city_road_ends.lua
 # over the road raster, which must be of this map) is closed:
 #   circle     a turning circle, radius max(12 m, 0.75 x width), centre pushed past the end by radius - width/2 so
 #              both road edges run into it (A04 diagonal road);
 #   connector  a road strip of the street's width over the gap to the street ahead (south road);
 #   link       a road strip joining two facing street ends (river bridge stubs to the ring road / south road), with a
 #              round pad of the road width at both ends so the angled joints have no corners missing.
 # Pieces are flat 4 cm slabs (engine basic cube / cylinder, their own simple collision, walkable), top 0.5 cm over the
 # 1205 road ground, with the city ground's own asphalt instance (world-space ground material), no shadow.
 E=json.loads((EDGE_OUT/'road-ends.json').read_text('utf8'));assert E['map_sha256']==LOAD_SHA,'road raster is of another map: rerun world_road_raster_probe'
 _gaps_backup('road-ends');acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for l,a in list(acts.items()):
  if l.startswith('WorldGap_Road'):SUB.destroy_actor(a)
 asph=EAL.load_asset('/Game/UniversityCity/GroundPBRV2/Materials/MI_Detail_932bc009ac742438e2bf');cyl=EAL.load_asset('/Engine/BasicShapes/Cylinder');cube=EAL.load_asset('/Engine/BasicShapes/Cube')
 assert asph and cyl and cube;H=4.;n=[0];rows=[]
 def slab(mesh,x,y,z,yaw,sx,sy,what):
  d=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x,y,z+.5-H/2),unreal.Rotator(0,0,yaw))
  d.set_actor_label('WorldGap_Road%s_%02d'%(what,n[0]));n[0]+=1;d.set_folder_path('UniversityCity/WorldGapsV1/Roads');d.tags=[unreal.Name('WorldGapsV1')]
  c=d.static_mesh_component;c.set_static_mesh(mesh);c.set_material(0,asph);c.set_editor_property('cast_shadow',False);c.set_editor_property('mobility',unreal.ComponentMobility.STATIC)
  d.set_actor_scale3d(unreal.Vector(sx/100.,sy/100.,H/100.))
 def strip(x0,y0,x1,y1,z,w):
  L=math.hypot(x1-x0,y1-y0)+200;slab(cube,(x0+x1)/2,(y0+y1)/2,z,math.degrees(math.atan2(y1-y0,x1-x0)),L,w,'Strip')
 for e in E['ends']:
  z=e['z'];w=e['width']
  if e['kind']=='circle':
   R=max(1200.,w*.75);off=R-w/2.;cx=e['x']+e['dir'][0]*off;cy=e['y']+e['dir'][1]*off
   slab(cyl,cx,cy,z,0,2*R,2*R,'Circle');rows.append(dict(e,center=[round(cx),round(cy)],radius=R))
  elif e['kind']=='connector':
   x1=e['x']+e['dir'][0]*e['length'];y1=e['y']+e['dir'][1]*e['length'];strip(e['x'],e['y'],x1,y1,z,w);rows.append(dict(e,to=[round(x1),round(y1)]))
  else:
   x1,y1=e['to'];strip(e['x'],e['y'],x1,y1,z,w)
   for px,py in ((e['x'],e['y']),(x1,y1)):slab(cyl,px,py,z,0,w,w,'Pad')
   rows.append(e)
 _gaps_save('road-ends-install',dict(status='saved_requires_capture_review',pieces=n[0],ends=rows))

def motel_world_groves_install():
 # world_groves_install (rule, whole city ground): big empty lawns (A13 ~250x200 m, A17 north) read as unfinished.
 # 5 m raster over the city union: a cell is open lawn when the downward trace's first blocking surface is city ground
 # G?? at street level (1150-1260) and no actor origin / instanced mesh instance lies in it. Open cells farther than
 # 25 m from anything else (chamfer distance) are grove seeds; seeds are taken greedily by distance, each claims a
 # 30-55 m blob (no two groves closer than 70 m), and each blob is filled with 6-16 of the city's own tree meshes
 # (camphor a/b/c, flower white/golden) on a jittered 9 m lattice inside the blob, kept >= 12 m from any occupied cell
 # (roads, paths, props stay clear). Like the street trees, each tree is a NoCollision render mesh plus a hidden
 # tree_trunk_collision mesh at the city's trunk scale. Deterministic (seeded).
 import random;rnd=random.Random(1102)
 world=unreal.EditorLevelLibrary.get_editor_world();P=json.loads((EDGE_OUT/'probe.json').read_text('utf8'));x0,y0,x1,y1=P['city_ground_union']
 acts=SUB.get_all_level_actors();S=500;NX=int((x1-x0)//S);NY=int((y1-y0)//S);occ=[[False]*NX for _ in range(NY)]
 def mark(x,y,r=0):
  i0=int((y-y0-r)//S);i1=int((y-y0+r)//S);k0=int((x-x0-r)//S);k1=int((x-x0+r)//S)
  for i in range(max(0,i0),min(NY,i1+1)):
   for k in range(max(0,k0),min(NX,k1+1)):occ[i][k]=True
 for a in acts:
  l=a.get_actor_label()
  if re.match(r'^G\d\d$',l) or l.startswith('WorldEdge_'):continue
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  if e.x>2e6:continue
  if max(e.x,e.y)<3000:mark(o.x,o.y,max(e.x,e.y))
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   for j in range(c.get_instance_count()):t=c.get_instance_transform(j,True);mark(t.translation.x,t.translation.y,200)
 for i in range(NY):
  for k in range(NX):
   if occ[i][k]:continue
   x=x0+(k+.5)*S;y=y0+(i+.5)*S
   r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,5000),unreal.Vector(x,y,-5000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
   t=r.to_tuple() if r is not None else (False,)
   if not(t[0] and t[9] is not None and re.match(r'^G\d\d$',t[9].get_actor_label()) and 1150<=t[4].z<=1260):occ[i][k]=True
 # chamfer distance (cells) to the nearest occupied cell
 INF=10**6;D=[[0 if occ[i][k] else INF for k in range(NX)] for i in range(NY)]
 for i in range(NY):
  for k in range(NX):
   if i:D[i][k]=min(D[i][k],D[i-1][k]+1)
   if k:D[i][k]=min(D[i][k],D[i][k-1]+1)
 for i in range(NY-1,-1,-1):
  for k in range(NX-1,-1,-1):
   if i<NY-1:D[i][k]=min(D[i][k],D[i+1][k]+1)
   if k<NX-1:D[i][k]=min(D[i][k],D[i][k+1]+1)
 seeds=sorted(((D[i][k],i,k) for i in range(NY) for k in range(NX) if D[i][k]*S>=2500),reverse=True);groves=[]
 for d,i,k in seeds:
  x=x0+(k+.5)*S;y=y0+(i+.5)*S
  if any(math.hypot(x-g[0],y-g[1])<7000 for g in groves):continue
  groves.append((x,y,min(d*S-1200,rnd.uniform(3000,5500))))
 lib={}
 for p in ('/Game/UniversityCity/TreeUpgradeV1/Assets/camphor_a/S_7127f39ef9fa4b9a/camphor_a_LOD0','/Game/UniversityCity/TreeUpgradeV1/Assets/camphor_b/S_238ca58656377b97/camphor_b_LOD0','/Game/UniversityCity/TreeUpgradeV1/Assets/camphor_c/S_83d9314c4b030a7d/camphor_c_LOD0','/Game/UniversityCity/EnvironmentV1/VisualPolishV5/FloweringTrees/Assets/white_flower/S_01d287da81d4adce/white_flower_LOD0','/Game/UniversityCity/EnvironmentV1/VisualPolishV5/FloweringTrees/Assets/golden_flower/S_a4d7175be82d25cc/golden_flower_LOD0','/Game/UniversityCity/StreetScenery/Assets/tree_trunk_collision/Source_af4f0c57688cf62c/tree_trunk_collision_LOD0'):
  m=EAL.load_asset(p);assert m,p;lib[p.split('/')[-1]]=m
 trunk=lib.pop('tree_trunk_collision_LOD0');kinds=list(lib)
 # a city street tree's trunk-collision instance scale, reused for every grove tree
 ts=None
 for a in acts:
  for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
   if c.static_mesh==trunk and c.get_instance_count():ts=c.get_instance_transform(0,True).scale3d;break
  if ts:break
 assert ts,'no trunk collision instance to copy'
 _gaps_backup('groves');old={a.get_actor_label():a for a in acts}
 for l,a in list(old.items()):
  if l.startswith(('WorldGap_Grove_','WorldGap_GroveTrunk_')):SUB.destroy_actor(a)
 rows=[]
 for gi,(gx,gy,R) in enumerate(groves):
  pts=[];sp=900
  for ix in range(-int(R//sp),int(R//sp)+1):
   for iy in range(-int(R//sp),int(R//sp)+1):
    x=gx+ix*sp+rnd.uniform(-300,300);y=gy+iy*sp+rnd.uniform(-300,300)
    if math.hypot(x-gx,y-gy)>R*(.8+.2*math.sin(math.atan2(y-gy,x-gx)*3+gi)):continue
    k=int((x-x0)//S);i=int((y-y0)//S)
    if not(0<=i<NY and 0<=k<NX) or D[i][k]*S<1200:continue
    r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,5000),unreal.Vector(x,y,-5000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
    t=r.to_tuple() if r is not None else (False,)
    if t[0] and t[9] is not None and re.match(r'^G\d\d$',t[9].get_actor_label()):pts.append((x,y,t[4].z))
  if len(pts)<6:continue
  rnd.shuffle(pts);pts=pts[:16]
  for ti,(x,y,z) in enumerate(pts):
   kind=rnd.choice(kinds);s=rnd.uniform(.85,1.2)
   t=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x,y,z),unreal.Rotator(0,0,rnd.uniform(0,360)))
   t.set_actor_label('WorldGap_Grove_%02d_%02d'%(gi,ti));t.set_folder_path('UniversityCity/WorldGapsV1/Groves');t.tags=[unreal.Name('WorldGapsV1')]
   c=t.static_mesh_component;c.set_static_mesh(lib[kind]);c.set_editor_property('mobility',unreal.ComponentMobility.STATIC);c.set_collision_enabled(unreal.CollisionEnabled.NO_COLLISION)
   t.set_actor_scale3d(unreal.Vector(s,s,s))
   k=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(x,y,z),unreal.Rotator(0,0,0))
   k.set_actor_label('WorldGap_GroveTrunk_%02d_%02d'%(gi,ti));k.set_folder_path('UniversityCity/WorldGapsV1/Groves');k.tags=[unreal.Name('WorldGapsV1')]
   c=k.static_mesh_component;c.set_static_mesh(trunk);c.set_editor_property('mobility',unreal.ComponentMobility.STATIC);c.set_collision_profile_name('BlockAll')
   c.set_editor_property('hidden_in_game',True);c.set_editor_property('cast_shadow',False);k.set_actor_scale3d(ts)
  rows.append(dict(grove=gi,center=[round(gx),round(gy)],radius=round(R),trees=len(pts)))
 _gaps_save('groves-install',dict(status='saved_requires_capture_review',groves=rows,open_cells=sum(1 for i in range(NY) for k in range(NX) if not occ[i][k]),cell_cm=S))
]====]
