-- Native job: move lover-spots props on the source map by a fixed offset (Tools/street_city_moved_props.lua, written by
-- the session script to places-v1/props-move.json as { moves = [{ prefix, main, from = [x,y], delta = [x,y,z] }] }).
--   lua Tools/street_city_motel_job.lua world_props_move Tools/street_city_props_move_payload.lua
-- A group moves when its main actor (prefix .. main) stands within 5 cm of `from`; one already at from + delta is left
-- (a second run moves nothing and saves nothing); anywhere else is an error. Every other LoverSpot_* actor is compared
-- before and after: moved, lost and new must be empty.
-- places-v1/props-move-apply.txt holding 1 moves and saves (the map backed up to world-edge-v1 first); otherwise it only
-- lists. Output: places-v1/props-move-result.json
return [====[
def motel_world_props_move():
 import json,shutil
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'props-move-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 cfg=json.loads((base/'props-move.json').read_text('utf8'));out=base/'props-move-result.json'
 V=unreal.Vector
 def lab(a):return a.get_actor_label()
 def at(a):l=a.get_actor_location();return [round(l.x,2),round(l.y,2),round(l.z,2),round(a.get_actor_rotation().yaw,2)]
 acts=list(SUB.get_all_level_actors())
 r=dict(status='passed',apply=APPLY,moves=[]);todo=[];mine=set()
 for m in cfg['moves']:
  group=[a for a in acts if lab(a).startswith(m['prefix'])];mine.update(lab(a) for a in group)
  main=[a for a in group if lab(a)==m['prefix']+m['main']]
  row=dict(prefix=m['prefix'],actors=len(group))
  if len(main)!=1:row.update(state='no main actor');r['moves'].append(row);r['status']='failed';continue
  l=main[0].get_actor_location();fx,fy=m['from'];dx,dy,dz=m['delta']
  if abs(l.x-fx)<5 and abs(l.y-fy)<5:row.update(state='to move',main=at(main[0]));todo.append((group,V(dx,dy,dz)))
  elif abs(l.x-fx-dx)<5 and abs(l.y-fy-dy)<5:row.update(state='already moved',main=at(main[0]))
  else:row.update(state='not where expected',main=at(main[0]));r['status']='failed'
  row['before']={lab(a):at(a) for a in group};r['moves'].append(row)
 if APPLY and todo and r['status']=='passed':
  before={lab(a):at(a) for a in acts if lab(a).startswith('LoverSpot_') and lab(a) not in mine}
  b_=base.parent/'world-edge-v1'/('UniversityCity-before-props-move-'+LOAD_SHA[:16]+'.umap')
  if not b_.exists():shutil.copy2(MAPFILE,b_)
  for group,d in todo:
   for a in group:a.set_actor_location(a.get_actor_location()+d,False,False)
  acts2=list(SUB.get_all_level_actors())
  after={lab(a):at(a) for a in acts2 if lab(a).startswith('LoverSpot_') and lab(a) not in mine}
  moved=[k for k in before if after.get(k)!=before[k]];lost=[k for k in before if k not in after];new=[k for k in after if k not in before]
  assert not moved and not lost and not new,'other LoverSpot actors changed'
  for row in r['moves']:row['after']={lab(a):at(a) for a in acts2 if lab(a).startswith(row['prefix'])}
  env=[a for a in acts2 if lab(a)=='CityEnvironmentController']
  if env:env[0].prepare_for_save()
  assert unreal.EditorLevelLibrary.save_current_level();new_sha=sha(MAPFILE)
  installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new_sha);write('motel-install',installed)
  r.update(others=len(before),moved=moved,lost=lost,new=new,map_sha256=new_sha,parent_map_sha256=LOAD_SHA,backup=str(b_))
 out.write_text(json.dumps(r,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',apply=APPLY,moves=len(r['moves']),failed=r['status']!='passed')
]====]
