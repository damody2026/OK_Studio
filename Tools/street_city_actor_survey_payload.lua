-- Native job: list the source map's actors whose label matches, with what the eye and the game need to know about each.
--   lua Tools/street_city_motel_job.lua world_actor_survey Tools/street_city_actor_survey_payload.lua
-- Read only. Input: places-v1/actor-survey.json { patterns = [label substrings], box = [x0,y0,x1,y1] (optional) }.
-- Output: places-v1/actor-survey-result.json: per actor its label, class, location, rotation, scale, bounds (origin and
-- extent), hidden in game, and per static mesh component its mesh, visibility, hidden in game, collision and materials.
-- 11-15: the amusement park showed white boxes (the LoverSpot *_Block blockers, made invisible when installed) and no
-- haunted house; this tells which actors are there and how each is set.
return [====[
def motel_world_actor_survey():
 base=ROOT/'output/street-social-city-production/places-v1'
 cfg=json.loads((base/'actor-survey.json').read_text('utf8'))
 pats=cfg.get('patterns',[]);box=cfg.get('box')
 rows=[]
 for a in SUB.get_all_level_actors():
  lab=a.get_actor_label()
  if pats and not any(p in lab for p in pats):continue
  l=a.get_actor_location()
  if box and not (box[0]<=l.x<=box[2] and box[1]<=l.y<=box[3]):continue
  o,e=a.get_actor_bounds(False);r_=a.get_actor_rotation();s=a.get_actor_scale3d()
  row=dict(label=lab,cls=a.get_class().get_name(),loc=[round(l.x),round(l.y),round(l.z)],yaw=round(r_.yaw,1),scale=[round(s.x,3),round(s.y,3),round(s.z,3)],
   origin=[round(o.x),round(o.y),round(o.z)],extent=[round(e.x),round(e.y),round(e.z)],hidden_in_game=bool(a.get_editor_property('hidden')),comps=[])
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh
   row['comps'].append(dict(name=c.get_name(),mesh=m.get_path_name() if m else None,visible=bool(c.is_visible()),hidden_in_game=bool(c.get_editor_property('hidden_in_game')),
    collision=str(c.get_collision_enabled()),mats=[(c.get_material(i).get_path_name() if c.get_material(i) else None) for i in range(c.get_num_materials())]))
  rows.append(row)
 (base/'actor-survey-result.json').write_text(json.dumps(dict(status='passed',count=len(rows),actors=rows),indent=1),'utf8')
 return dict(status='passed',count=len(rows))
]====]
