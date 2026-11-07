-- Read-only native job: the shape of the space round the lift landings. Nothing is saved.
--   lua Tools/street_city_motel_job.lua world_lift_probe Tools/street_city_lift_probe_payload.lua
-- From each landing: how far a ray goes in 16 directions at chest height, and a body-sized sweep 3 m out along the same directions.
-- Output: places-v1/lift-probe.json
return [====[
def motel_world_lift_probe():
 import math
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE;LIB=unreal.CityDepthAuditLibrary
 def ray(a,b):
  r=unreal.SystemLibrary.line_trace_single(world,a,b,Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  if not(h and h[0]):return None
  p=h[4];return dict(at=[round(p.x,1),round(p.y,1),round(p.z,1)],actor=h[9].get_actor_label() if h[9] else None)
 places=json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_places.json').read_text('utf8'))['places']
 rows=[]
 for p in places:
  if p['id'] in('school','lecture'):continue
  for a in p['anchors']:
   if not a['name'].startswith('lift'):continue
   x,y,z=a['pos'];row=dict(place=p['id'],name=a['name'],pos=a['pos'],rays=[],sweeps=[])
   for k in range(16):
    t=math.radians(k*22.5);ox,oy=math.cos(t),math.sin(t)
    h=ray(V(x,y,z+120),V(x+ox*800,y+oy*800,z+120))
    row['rays'].append([k*22.5,round(math.hypot(h['at'][0]-x,h['at'][1]-y)) if h else None,(h['actor'] if h else None)])
    s=json.loads(LIB.sweep_clearance(world,V(x,y,z+98),V(x+ox*300,y+oy*300,z+98),28.,88.))
    if k==0 and not rows:row['sweep_format']=s
    row['sweeps'].append([k*22.5,bool(s.get('blocked')),s.get('distance_cm',s.get('distance')),str(s.get('actor',s.get('hit_actor','')))[:40]])
   rows.append(row)
 r=dict(status='passed',rows=rows)
 (ROOT/'output/street-social-city-production/places-v1/lift-probe.json').write_text(json.dumps(r,indent=1),'utf8');return dict(status='passed',rows=len(rows))
]====]
