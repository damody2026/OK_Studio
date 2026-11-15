-- Read-only native job: shop interiors as they stand, to find where a door has to be cut. Nothing is saved.
--   lua Tools/street_city_motel_job.lua world_room_survey Tools/street_city_room_survey_payload.lua
-- Input: places-v1/room-survey.json { areas = [{ name, box = [x0,y0,x1,y1], z = floor z, step = cm }] }
-- Output: places-v1/room-survey.json's sibling room-survey-result.json, per area:
--   actors: every actor whose bounds reach into the box below 2.6 m over the floor, with its static meshes and how many
--     level actors use each mesh (a cut changes the mesh asset: shared = every actor using it gets the hole)
--   thin: a 10x10x187 cm box 3 cm over the floor per cell; '.' clear, ' ' no floor within 15 cm, otherwise the letter of
--     the actor it hits (legend: letter -> label)
--   fat: the same with a 40x40 cm box (the game's route capsule); '.' clear, '#' blocked
-- (2026-11-15, c-street-city: clinic_beauty seat room and izakaya NE room)
return [====[
def motel_world_room_survey():
 import json
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 base=ROOT/'output/street-social-city-production/places-v1'
 cfg=json.loads((base/'room-survey.json').read_text('utf8'));out=base/'room-survey-result.json'
 acts=list(SUB.get_all_level_actors())
 users={}
 for a in acts:
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh
   if m:users.setdefault(m.get_path_name(),set()).add(a.get_actor_label())
 LET='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@$%&*+=?'
 areas=[]
 for ar in cfg['areas']:
  X0,Y0,X1,Y1=ar['box'];Z=float(ar['z']);STEP=float(ar.get('step',10))
  inside=[]
  for a in acts:
   o,e=a.get_actor_bounds(False)
   if e.x>20000 or e.y>20000:continue
   if o.x+e.x<X0 or o.x-e.x>X1 or o.y+e.y<Y0 or o.y-e.y>Y1 or o.z-e.z>Z+260 or o.z+e.z<Z:continue
   ms=[]
   for c in a.get_components_by_class(unreal.StaticMeshComponent):
    m=c.static_mesh
    if m:
     src=m.get_editor_property('complex_collision_mesh')
     ms.append(dict(component=c.get_name(),mesh=m.get_path_name(),users=len(users.get(m.get_path_name(),())),collision=src.get_path_name() if src else None))
   inside.append(dict(label=a.get_actor_label(),name=a.get_name(),cls=a.get_class().get_name(),c=[round(o.x),round(o.y),round(o.z)],e=[round(e.x),round(e.y),round(e.z)],meshes=ms))
  leg={};thin=[];fat=[]
  def floor(x,y):
   r=unreal.SystemLibrary.line_trace_single(world,V(x,y,Z+60),V(x,y,Z-40),Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
   return h[4].z if h[0] else None
  def box(x,y,f,half):
   m=V(x,y,f+3+93.5);r=unreal.SystemLibrary.box_trace_single(world,m,m+V(0,0,1),V(half,half,93.5),unreal.Rotator(0,0,0),Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
   return (h[9].get_actor_label() if h[9] else '?') if h[0] else None
  y=Y0+STEP/2
  while y<Y1:
   rt,rf=[],[];x=X0+STEP/2
   while x<X1:
    f=floor(x,y)
    if f is None or abs(f-Z)>15:rt.append(' ');rf.append(' ')
    else:
     w=box(x,y,f,5)
     if w is None:rt.append('.')
     else:
      if w not in leg:leg[w]=LET[len(leg)] if len(leg)<len(LET) else '#'
      rt.append(leg[w])
     rf.append('.' if box(x,y,f,20) is None else '#')
    x+=STEP
   thin.append(''.join(rt));fat.append(''.join(rf));y+=STEP
  areas.append(dict(name=ar['name'],box=ar['box'],z=Z,step=STEP,actors=inside,legend={v:k for k,v in leg.items()},thin=thin,fat=fat))
 out.write_text(json.dumps(dict(status='passed',areas=areas),indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',areas=len(areas))
]====]
