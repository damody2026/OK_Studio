-- Read-only native probe for the last scene round (c-conquest 8.2: pool, observation, rooftop, boat, flower_field, hill):
--   lua Tools/street_city_motel_job.lua world_last_probe Tools/street_city_round5_probe_payload.lua
--   boxes  actors standing in the pool halls, the sky cafe and on the T1 roof, with label, mesh and bounds
--   water  every actor whose label or mesh names water, with its bounds
--   roofs  a 2 m grid of downward traces over each roof box: height, actor and material
--   thin   long thin actors reaching over the sea
-- Output: output/street-social-city-production/places-v1/round5-probe.json
return [====[
def motel_world_last_probe():
 out=ROOT/'output/street-social-city-production/places-v1';world=unreal.EditorLevelLibrary.get_editor_world();acts=SUB.get_all_level_actors()
 boxes=dict(pool1=((77120,21860,1100),(83120,25660,3020)),pool2=((77120,25940,1100),(83120,29740,3020)),pool3=((77120,30020,1100),(83120,33820,3020)),
  sky=((42311,62190,4900),(45580,65240,5400)),t1top=((61500,49468,2900),(66500,56532,4200)),m1top=((42000,60000,5300),(50000,72000,6000)))
 res={k:[] for k in boxes};water=[];thin=[]
 for a in acts:
  try:o,e=a.get_actor_bounds(False)
  except Exception:continue
  lab=a.get_actor_label();mesh=''
  c=a.get_component_by_class(unreal.StaticMeshComponent)
  if c and c.static_mesh:mesh=c.static_mesh.get_name()
  rec=dict(label=lab,mesh=mesh,cls=a.get_class().get_name(),lo=[o.x-e.x,o.y-e.y,o.z-e.z],hi=[o.x+e.x,o.y+e.y,o.z+e.z],yaw=a.get_actor_rotation().yaw)
  if re.search('water|ocean|sea|lake|pond|river|canal|pool',(lab+' '+mesh).lower()) and len(water)<400:water.append(rec)
  # long thin things reaching over the sea (pale lines showed in the water near the shore)
  if o.x-e.x<13000 and max(e.x,e.y)>1500 and min(e.x,e.y)<500:thin.append(rec)
  if max(e.x,e.y)>30000:continue
  for k,(lo,hi) in boxes.items():
   if o.x>=lo[0] and o.x<=hi[0] and o.y>=lo[1] and o.y<=hi[1] and o.z>=lo[2] and o.z<=hi[2] and len(res[k])<300:res[k].append(rec)
 roofs={}
 for k in ('t1top','m1top'):
  lo,hi=boxes[k];rows=[]
  x=lo[0]
  while x<=hi[0]:
   y=lo[1]
   while y<=hi[1]:
    raw=unreal.SystemLibrary.line_trace_single(world,unreal.Vector(x,y,9000),unreal.Vector(x,y,1000),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
    h=raw.to_tuple() if raw else [False]
    if h[0]:rows.append([round(x),round(y),round(h[4].z),h[9].get_actor_label() if h[9] else '?'])
    y+=200
   x+=200
  roofs[k]=rows
 (out/'round5-probe.json').write_text(json.dumps(dict(boxes=res,water=water,roofs=roofs,thin=thin),ensure_ascii=False,indent=0),'utf8')
 return dict(status='passed',water=len(water),pool=len(res['pool1']))
]====]
