-- Read-only native job: the karaoke shop S48 (唱片小室) as it stands, to plan where its booths go. Nothing is saved.
--   lua Tools/street_city_motel_job.lua world_ktv_survey Tools/street_city_ktv_survey_payload.lua
-- Output: places-v1/ktv-survey.json
--   booths: every LoverSpot_KTV_* actor (label, location, yaw, scale, bounds)
--   actors: every other actor whose bounds reach into the shop box below 2.6 m (furniture, shell, refit)
--   grid / grid_free: 20 cm cells over the shop at z 1200: '.' a 40x40x190 cm box 3 cm above the floor is clear,
--     '#' it hits something, ' ' no floor within 15 cm; grid_free is the same with the booths ignored (the room left
--     if they were moved)
return [====[
def motel_world_ktv_survey():
 import json
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 X0,Y0,X1,Y1,Z=43100.,47980.,44900.,48980.,1200.;STEP=20.
 out=ROOT/'output/street-social-city-production/places-v1/ktv-survey.json'
 acts=list(SUB.get_all_level_actors())
 def info(a):
  o,e=a.get_actor_bounds(False);l=a.get_actor_location();s=a.get_actor_scale3d()
  return dict(label=a.get_actor_label(),name=a.get_name(),cls=a.get_class().get_name(),loc=[round(l.x,1),round(l.y,1),round(l.z,1)],yaw=round(a.get_actor_rotation().yaw,2),
   scale=[round(s.x,3),round(s.y,3),round(s.z,3)],c=[round(o.x),round(o.y),round(o.z)],e=[round(e.x),round(e.y),round(e.z)])
 booths=[a for a in acts if a.get_actor_label().startswith('LoverSpot_KTV_')]
 others=[]
 for a in acts:
  if a in booths:continue
  o,e=a.get_actor_bounds(False)
  if e.x>20000 or e.y>20000:continue
  if o.x+e.x<X0 or o.x-e.x>X1 or o.y+e.y<Y0 or o.y-e.y>Y1 or o.z-e.z>Z+260 or o.z+e.z<Z:continue
  others.append(info(a))
 def floor(x,y):
  r=unreal.SystemLibrary.line_trace_single(world,V(x,y,Z+60),V(x,y,Z-40),Q,True,[],NONE,True);h=r.to_tuple() if r else [False]
  return h[4].z if h[0] else None
 def clear(x,y,ignore):
  m=V(x,y,Z+3+95);r=unreal.SystemLibrary.box_trace_single(world,m,m+V(0,0,1),V(20,20,95),unreal.Rotator(0,0,0),Q,True,ignore,NONE,True);h=r.to_tuple() if r else [False]
  return not h[0]
 g,gf=[],[]
 y=Y0+STEP/2
 while y<Y1:
  row,rowf=[],[];x=X0+STEP/2
  while x<X1:
   f=floor(x,y)
   if f is None or abs(f-Z)>15:row.append(' ');rowf.append(' ')
   else:row.append('.' if clear(x,y,[]) else '#');rowf.append('.' if clear(x,y,booths) else '#')
   x+=STEP
  g.append(''.join(row));gf.append(''.join(rowf));y+=STEP
 r=dict(status='passed',box=[X0,Y0,X1,Y1],z=Z,step=STEP,booths=[info(a) for a in booths],actors=others,grid=g,grid_free=gf)
 out.write_text(json.dumps(r,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',booths=len(booths),actors=len(others))
]====]
