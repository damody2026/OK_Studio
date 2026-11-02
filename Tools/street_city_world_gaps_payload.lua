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
 # on the S18 garage-10 forecourt, 11-02): while its bounds still hold the blocked point it stays NoCollision and is listed
 # as misplaced instead of cutting the route (world_landmark_relocate moves such props off the route).
 _gaps_backup('landmark-collision');rows=[];skip=set()
 for a in SUB.get_all_level_actors():
  if not a.get_actor_label().startswith('Landmark_'):continue
  if _landmark_blocks_route(a):skip.add(a.get_actor_label())
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

def _route_block_points():
 rr=OUT/'route-review.json';pts={}
 if rr.exists():
  for r in json.loads(rr.read_text('utf-8-sig')).get('issues',[]):
   for i in r['issues']:
    q=i.get('result') or {}
    if q.get('actor','').startswith('Landmark_') and q.get('point'):pts.setdefault(q['actor'],[]).append(q['point'])
 return pts
def _landmark_blocks_route(a):
 o,e=a.get_actor_bounds(False)
 return any(o.x-e.x-50<=p[0]<=o.x+e.x+50 and o.y-e.y-50<=p[1]<=o.y+e.y+50 for p in _route_block_points().get(a.get_actor_label(),[]))
def motel_world_landmark_relocate():
 # world_landmark_relocate (rule): a Landmark_* prop that stands on a planned motel route (route review blocked point
 # inside its bounds: the stage on the S18 garage-10 forecourt) or floats (its base more than 30 cm over the first
 # surface under its centre) or stands on a roof (base over 13 m on something that is not city ground: playground_a_98
 # on the Campus_D3_F06 roof at z 34 m, where no player gets) is moved to the nearest free lawn spot within
 # 80 m (5 m rings): every point of its footprint grown by 3 m (centre, corners, edge middles) must land on grass-level
 # city ground G?? (1150-1201, spread < 10 cm), and no other actor under 60 m extent (trees, groves, props) may overlap
 # that grown footprint. The prop keeps its yaw, sits on that ground and then gets its blocking collision.
 world=unreal.EditorLevelLibrary.get_editor_world();acts=SUB.get_all_level_actors();rows=[]
 def down(x,y,ign):
  r=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,8000),unreal.Vector(x,y,-5000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ign,unreal.DrawDebugTrace.NONE,True)
  t=r.to_tuple() if r is not None else (False,)
  return (t[9].get_actor_label(),t[4].z) if t[0] and t[9] is not None else (None,None)
 boxes=[]
 for b in acts:
  l=b.get_actor_label()
  if re.match(r'^G\d\d$',l) or l.startswith('WorldEdge_'):continue
  try:o,e=b.get_actor_bounds(False)
  except Exception:continue
  if max(e.x,e.y)<6000:boxes.append((l,o.x-e.x,o.y-e.y,o.x+e.x,o.y+e.y))
 movers=[]
 for a in acts:
  l=a.get_actor_label()
  if not l.startswith('Landmark_'):continue
  o,e=a.get_actor_bounds(False);base=o.z-e.z;g=down(o.x,o.y,[a])
  why='route' if _landmark_blocks_route(a) else 'floating' if g[1] is not None and base-g[1]>30 else 'roof' if g[0] is not None and not re.match(r'^G\d\d$',g[0]) and base>1300 else None
  if why:movers.append((a,why,o,e,base,g))
 if not movers:raise RuntimeError('no landmark to relocate')
 _gaps_backup('landmark-relocate')
 for a,why,o,e,base,g in movers:
  l=a.get_actor_label();loc=a.get_actor_location();hx,hy=e.x+300,e.y+300;found=None
  for R in range(500,8001,500):
   for s in range(max(8,int(2*math.pi*R/500))):
    t=2*math.pi*s/max(8,int(2*math.pi*R/500));cx=o.x+R*math.cos(t);cy=o.y+R*math.sin(t)
    if any(b[0]!=l and b[1]<cx+hx and b[3]>cx-hx and b[2]<cy+hy and b[4]>cy-hy for b in boxes):continue
    zs=[]
    for dx in (-hx,0,hx):
     for dy in (-hy,0,hy):
      q=down(cx+dx,cy+dy,[a])
      if q[0] is None or not re.match(r'^G\d\d$',q[0]) or not(1150<=q[1]<1201):zs=None;break
      zs.append(q[1])
     if zs is None:break
    if zs and max(zs)-min(zs)<10:found=(cx,cy,max(zs));break
   if found:break
  assert found,('no free lawn spot within 80 m for',l)
  cx,cy,gz=found;a.set_actor_location(unreal.Vector(loc.x+cx-o.x,loc.y+cy-o.y,loc.z+gz-base),False,False)
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   c.set_collision_profile_name('BlockAll');c.set_collision_enabled(unreal.CollisionEnabled.QUERY_AND_PHYSICS);c.set_editor_property('can_character_step_up_on',unreal.CanBeCharacterBase.ECB_NO)
  boxes=[b for b in boxes if b[0]!=l]+[(l,cx-e.x,cy-e.y,cx+e.x,cy+e.y)]
  rows.append(dict(label=l,reason=why,from_=[round(o.x),round(o.y),round(base)],under_before=g,to=[round(cx),round(cy),round(gz)],moved_cm=round(math.hypot(cx-o.x,cy-o.y))))
 _gaps_save('landmark-relocate',dict(status='saved_requires_routes_and_walk',moved=rows))

def motel_world_annex_ground_unify():
 # world_annex_ground_unify: Outdoor_annex_ground (the lawn south of the city union, y 1100-1380 m) draws the same meadow
 # textures as the city ground G01-G16 through two instances of its own with other tints, so its border reads as a
 # colour seam (G086, G104, G148). Every slot of it that draws the meadow texture gets the city ground's meadow instance
 # (the one on G01-G16). Its walk surface stays 10 cm lower (1188 vs 1198): raising it would bury what stands on it.
 MEL=unreal.MaterialEditingLibrary;city=None
 for a in SUB.get_all_level_actors():
  if a.get_actor_label()=='G12':
   for k in range(a.static_mesh_component.get_num_materials()):
    m=a.static_mesh_component.get_material(k)
    if m and 'meadow' in str([MEL.get_material_instance_texture_parameter_value(m,n).get_name() for n in MEL.get_texture_parameter_names(m) if MEL.get_material_instance_texture_parameter_value(m,n)]):city=m;break
 assert city,'city meadow instance not found on G12'
 _gaps_backup('annex-ground');rows=[]
 for a in SUB.get_all_level_actors():
  if a.get_actor_label()!='Outdoor_annex_ground':continue
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   for k in range(c.get_num_materials()):
    m=c.get_material(k);tex=[MEL.get_material_instance_texture_parameter_value(m,n).get_name() for n in MEL.get_texture_parameter_names(m) if MEL.get_material_instance_texture_parameter_value(m,n)] if m else []
    if any('meadow' in t for t in tex):rows.append(dict(slot=k,before=m.get_path_name(),after=city.get_path_name()));c.set_material(k,city)
 assert rows,'no meadow slot on Outdoor_annex_ground'
 _gaps_save('annex-ground-unify',dict(status='saved_requires_capture_review',slots=rows))

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
def motel_world_ground_sections_probe():
 # world_ground_sections_probe (read-only): which material section of the city ground sheets G01-G16 draws each top
 # cell. Traces cannot tell (the face index does not map back to the section), so this reads the meshes: every polygon
 # of LOD0 whose normal points up (z > 0.7), with its polygon group's material (component slot), rasterised at 1 m by
 # polygon centre-in-triangle over x -30..300 m (the west coast) on the whole union y. Per cell one char: 's' beach
 # sand, 'g' meadow grass, 'a' asphalt, 'v' river gravel, 'x' another material, '.' no up-facing ground polygon.
 # Output world-edge-v1/ground-sections.json (rows along y, 1 m).
 P=json.loads((EDGE_OUT/'probe.json').read_text('utf8'));x0,y0,x1,y1=P['city_ground_union'];X0,X1=int(x0)-3000,int(x0)+30000
 NX=(X1-X0)//100;NY=int((y1-y0)//100);grid=[bytearray(b'.'*NX) for _ in range(NY)];code={}
 def ch(m):
  p=m.get_path_name() if m else ''
  return b's' if 'c6f565f3d91f57f03b7a' in p else b'g' if 'b6a245f3a69b53317770' in p else b'a' if '932bc009ac742438e2bf' in p else b'v' if '9ea1c3103a2d3f4c9850' in p else b'x'
 stats={}
 for a in SUB.get_all_level_actors():
  l=a.get_actor_label()
  if not re.match(r'^G\d\d$',l):continue
  c=a.static_mesh_component;sm=c.static_mesh;md=sm.get_static_mesh_description(0);T=c.get_world_transform()
  slots=[str(s.get_editor_property('material_slot_name')) for s in sm.get_editor_property('static_materials')]
  gm={}
  for gi in range(md.get_polygon_group_count()):
   g=unreal.PolygonGroupID(gi)
   try:name=str(md.get_polygon_group_material_slot_name(g))
   except Exception:name=''
   k=slots.index(name) if name in slots else gi
   gm[gi]=ch(c.get_material(k)) if k<c.get_num_materials() else b'x'
  for pi in range(md.get_polygon_count()):
   p=unreal.PolygonID(pi);vs=[T.transform_location(md.get_vertex_position(v)) for v in md.get_polygon_vertices(p)]
   if len(vs)<3:continue
   ax,ay,az=vs[1].x-vs[0].x,vs[1].y-vs[0].y,vs[1].z-vs[0].z;bx,by,bz=vs[2].x-vs[0].x,vs[2].y-vs[0].y,vs[2].z-vs[0].z
   nx_,ny_,nz_=ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx;n=math.sqrt(nx_*nx_+ny_*ny_+nz_*nz_) or 1
   if abs(nz_/n)<.7:continue
   xs=[v.x for v in vs];ys=[v.y for v in vs]
   if max(xs)<X0 or min(xs)>X1:continue
   m=gm.get(md.get_polygon_polygon_group(p).id_value if hasattr(md.get_polygon_polygon_group(p),'id_value') else 0,b'x')
   stats[m.decode()]=stats.get(m.decode(),0)+1
   # fill the cells whose centres fall in the polygon's triangles (fan from vertex 0)
   for t in range(1,len(vs)-1):
    A,B,C=vs[0],vs[t],vs[t+1]
    k0=max(0,int((min(A.x,B.x,C.x)-X0)//100));k1=min(NX-1,int((max(A.x,B.x,C.x)-X0)//100));i0=max(0,int((min(A.y,B.y,C.y)-y0)//100));i1=min(NY-1,int((max(A.y,B.y,C.y)-y0)//100))
    d=(B.y-C.y)*(A.x-C.x)+(C.x-B.x)*(A.y-C.y)
    if abs(d)<1e-6:continue
    for i in range(i0,i1+1):
     py=y0+(i+.5)*100
     for k in range(k0,k1+1):
      px=X0+(k+.5)*100;w1=((B.y-C.y)*(px-C.x)+(C.x-B.x)*(py-C.y))/d;w2=((C.y-A.y)*(px-C.x)+(A.x-C.x)*(py-C.y))/d
      if w1>=-1e-6 and w2>=-1e-6 and w1+w2<=1+1e-6:grid[i][k:k+1]=m
 assert sha(MAPFILE)==LOAD_SHA
 (EDGE_OUT/'ground-sections.json').write_text(json.dumps(dict(status='read_only_probe',map_sha256=LOAD_SHA,x0_cm=X0,y0_cm=y0,step_cm=100,polygons=stats,rows=[r.decode() for r in grid])),'utf8')
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
 # chamfer distance (cells) to the nearest occupied cell; the city border counts as occupied (the first run, 11-02,
 # treated the outside as open, so most groves sat on the border and the middle of A13 stayed empty)
 INF=10**6;D=[[0 if occ[i][k] else min(INF,i+1,k+1,NY-i,NX-k) for k in range(NX)] for i in range(NY)]
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
