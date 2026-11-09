return [====[
def motel_ramp_probe():
 # What stands under / in front of a walk point: multi line traces (Pawn + Visibility) and a pawn capsule sweep along a segment.
 # ramp-probe.json {"points":[[x,y]...],"segment":[[x,y,z],[x,y,z]]}
 q=json.loads((OUT/'ramp-probe.json').read_text('utf8'));world=unreal.EditorLevelLibrary.get_editor_world();out=dict(points=[],sweep=None)
 for (x,y) in q['points']:
  row=dict(xy=[x,y],hits=[])
  for ch,name in ((unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,'visibility'),(unreal.TraceTypeQuery.TRACE_TYPE_QUERY2,'camera')):
   hs=unreal.SystemLibrary.line_trace_multi(world,unreal.Vector(x,y,2000),unreal.Vector(x,y,1500),ch,True,[],unreal.DrawDebugTrace.NONE,True)
   for h in hs or []:t=h.to_tuple();row['hits'].append(dict(ch=name,z=round(t[4].z,1),actor=t[9].get_actor_label() if t[9] else None,comp=t[10].get_name() if t[10] else None))
  ob=unreal.SystemLibrary.sphere_overlap_actors(world,unreal.Vector(x,y,1830),40.,[unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY1,unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY2],None,[])
  row['overlap_actors']=[a.get_actor_label() for a in (ob or [])];out['points'].append(row)
 a,b=q['segment'];r=unreal.SystemLibrary.capsule_trace_multi(world,unreal.Vector(*a),unreal.Vector(*b),34.,88.,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
 out['sweep']=[dict(z=round(h.to_tuple()[4].z,1),impact=num(h.to_tuple()[4]),normal=num(h.to_tuple()[7]),actor=h.to_tuple()[9].get_actor_label() if h.to_tuple()[9] else None) for h in (r or [])]
 (OUT/'ramp-probe-result.json').write_text(json.dumps(out,ensure_ascii=False,indent=1),'utf8')

def motel_pool_ramps():
 # Invisible pawn ramps over the private-pool steps. Walking down 18 cm risers on 30 cm treads, a long frame (hitch) can carry
 # the capsule ~0.4-0.6 m past a tread edge before CharacterMovement starts falling: the route audit then sees the pawn
 # unsupported (2 of 3 full walks stalled on the 203/207 exit steps, segment 24). A ramp on the step nosings keeps the capsule
 # grounded on the way down; profile InvisibleWall blocks pawns only, so Visibility ground rays and pixels still see the treads.
 # Runs come from the planned pool entry/exit routes (motel-v1/game-physics-plan.json): consecutive points 20..60 cm apart with
 # an 8..25 cm drop; each descending pair's edge is (midpoint, upper z); a line is fitted through the edges.
 plan=json.loads((OUT/'game-physics-plan.json').read_text('utf8'));cube=EAL.load_asset('/Engine/BasicShapes/Cube.Cube');assert cube
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for label,a in list(actors.items()):
  if label.startswith('MotelV1_PoolRamp_'):SUB.destroy_actor(a)
 runs={}
 for r in plan['walk_routes']:
  if 'pool-entry' not in r['id']:continue
  P=r['points'];cur=[]
  def flush():
   if len(cur)>=3:
    top,bot=max(cur,key=lambda p:p[2]),min(cur,key=lambda p:p[2]);key=(round(top[0]),round(top[1]),round(bot[0]),round(bot[1]))
    if not any(abs(k[0]-key[0])<5 and abs(k[1]-key[1])<5 and abs(k[2]-key[2])<5 and abs(k[3]-key[3])<5 for k in runs):runs[key]=(r['id'],list(cur))
  for a,b in zip(P,P[1:]):
   h=math.hypot(b[0]-a[0],b[1]-a[1]);dz=abs(b[2]-a[2])
   if 20<=h<=60 and 8<=dz<=25 and (not cur or (cur[-1] is a and (b[2]-a[2])*(cur[-1][2]-cur[0][2])>=0)):
    if not cur:cur=[a]
    cur.append(b)
   else:
    flush();cur=[a,b] if 20<=h<=60 and 8<=dz<=25 else []
  flush()
 backup=OUT/('UniversityCity-before-pool-ramps-'+LOAD_SHA[:16]+'.umap')
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 rows=[]
 for n,(key,(rid,pts)) in enumerate(sorted(runs.items())):
  hi,lo=max(pts,key=lambda p:p[2]),min(pts,key=lambda p:p[2]);ux,uy=lo[0]-hi[0],lo[1]-hi[1];L=math.hypot(ux,uy);ux,uy=ux/L,uy/L
  srt=sorted(pts,key=lambda p:(p[0]-hi[0])*ux+(p[1]-hi[1])*uy);edges=[]
  # A tread's downhill edge is half a tread depth past its route point (median spacing). Midpoints are wrong where the
  # first/last step meets the floor at a longer spacing (52/50 cm vs 30/35 cm) and tilted the first fit, leaving nosings
  # up to ~2 cm proud of the ramp: the pawn stalled on them climbing the 203 inner steps.
  sp=sorted(math.hypot(b[0]-a[0],b[1]-a[1]) for a,b in zip(srt,srt[1:]));half=sp[len(sp)//2]/2;edges=[]
  for a,b in zip(srt,srt[1:]):
   if a[2]>b[2]+4:s=(a[0]-hi[0])*ux+(a[1]-hi[1])*uy+half;edges.append((s,a[2]))
  m=len(edges);sx=sum(e[0] for e in edges);sz=sum(e[1] for e in edges);sxx=sum(e[0]**2 for e in edges);sxz=sum(e[0]*e[1] for e in edges)
  k=(m*sxz-sx*sz)/(m*sxx-sx*sx);c=(sz-k*sx)/m  # z = c + k*s, k < 0 downhill
  c+=max(0.,max(e[1]-(c+k*e[0]) for e in edges))+.5  # no nosing may stand proud of the ramp surface
  # The top end used to stop at the first tread (4.5 cm under the deck, ~8 cm short of the deck edge): the capsule could
  # perch on that exposed deck corner above the ramp and stall (201/203/207 exits, segment 24). Extend the ramp up its own
  # line to 0.5 cm above the deck, measured on the deck 40 cm behind the top route point, so the corner is buried.
  w=unreal.EditorLevelLibrary.get_editor_world();zs=[]
  for back in (10,20,30,40,50,60):
   dx,dy=hi[0]-ux*back,hi[1]-uy*back
   for h in unreal.SystemLibrary.line_trace_multi(w,unreal.Vector(dx,dy,hi[2]+60),unreal.Vector(dx,dy,hi[2]-60),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True) or []:
    t=h.to_tuple()
    if t[0] and 0<=t[4].z-hi[2]<25:zs.append(t[4].z)
  deck=max(zs) if zs else hi[2]
  zt,zb=max(hi[2],deck+.5),lo[2]-3;s0=(zt-c)/k;s1=(zb-c)/k
  p0=(hi[0]+ux*s0,hi[1]+uy*s0,zt);p1=(hi[0]+ux*s1,hi[1]+uy*s1,zb);run=s1-s0;drop=zt-zb;ln=math.hypot(run,drop);th=6.
  ang=math.atan2(drop,run);nx,nz=math.sin(ang),math.cos(ang)  # ramp normal in (along,up)
  cx,cy,cz=(p0[0]+p1[0])/2-ux*nx*th/2,(p0[1]+p1[1])/2-uy*nx*th/2,(p0[2]+p1[2])/2-nz*th/2
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(cx,cy,cz),unreal.Rotator(0,-math.degrees(ang),math.degrees(math.atan2(uy,ux))))
  a.set_actor_label('MotelV1_PoolRamp_%s_%d'%(rid.split('-pool')[0],n));a.tags=[unreal.Name('MotelV1'),unreal.Name('MotelPoolRamp')];a.set_folder_path('UniversityCity/MotelV1/PoolRamps')
  smc=a.static_mesh_component;smc.set_static_mesh(cube);a.set_actor_scale3d(unreal.Vector(ln/100,1.9,th/100));smc.set_collision_profile_name('InvisibleWall');a.set_actor_hidden_in_game(True);smc.set_editor_property('cast_shadow',False)
  # pawn-profile capsule sweep 3 cm above the ramp surface, bottom to top: anything blocking here pokes through the ramp
  # capsule centre 3 cm clear of the slope: (half height - radius) + (radius + 3) / cos(slope); the ramp itself is ignored
  lift=54.+37./math.cos(ang);sa=unreal.Vector(p1[0]-ux*10,p1[1]-uy*10,p1[2]+lift+math.tan(ang)*10);sb=unreal.Vector(p0[0]+ux*10,p0[1]+uy*10,p0[2]+lift-math.tan(ang)*10)
  hit=unreal.SystemLibrary.capsule_trace_single_by_profile(unreal.EditorLevelLibrary.get_editor_world(),sa,sb,34.,88.,'Pawn',True,[a],unreal.DrawDebugTrace.NONE,True)
  ht=hit.to_tuple() if hit is not None else (False,)+(None,)*11
  rows.append(dict(actor=a.get_actor_label(),route=rid,top=list(p0),bottom=list(p1),deck_z=deck,slope_deg=math.degrees(ang),length_cm=ln,edges=m,
   clear_sweep=not ht[0],sweep_hit=dict(actor=ht[9].get_actor_label() if ht[9] else None,z=ht[4].z,dist=(ht[4]-sa).length()) if ht[0] else None))
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (OUT/'pool-ramps.json').write_text(json.dumps(dict(status='saved_requires_actual_walk',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),ramps=rows),ensure_ascii=False,indent=2),'utf8')
]====]
