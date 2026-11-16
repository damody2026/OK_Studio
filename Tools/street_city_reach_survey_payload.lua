-- Read-only native job: the game's own walk-grid cell test (AOKStreetSocialScene::NavCellFree) over tiles of the city, for
-- Tools/street_city_reach_check.lua (places and anchors reachable from their doors). Nothing is saved.
--   lua Tools/street_city_motel_job.lua world_reach_survey Tools/street_city_reach_survey_payload.lua
-- Input: places-v1/reach-tiles.json { cells = cells per tile side, tiles = [{ key, ix0, iy0, z }] } (ix0/iy0: the tile's first
--   40 cm lattice cell, cell centre = i * 40), and places-v1/reach-batch.json { from, to } (1-based tile range, inclusive).
-- Per cell, as the game tests it (OKStreetGroundZ, then a capsule over the ground):
--   ground: a line WorldStatic/WorldDynamic, simple collision, from z+70 down to z-120; none -> no ground
--   body: a capsule of radius 40, then 30 (the game's narrow replan), half height 60, centred 105 cm over the ground,
--     overlapping WorldStatic/WorldDynamic actors by simple collision
-- Output: places-v1/reach-grid/<from>-<to>.json { legend = [labels], tiles = { key = rows } }, one row per y (iy0..),
--   space-separated codes per x: 'n' no ground, 'b<k>' blocked at 30 by legend[k] (0-based), otherwise the ground's
--   height minus z in cm, with a trailing ',' when the cell is free at 30 only (blocked at 40).
-- (2026-11-16 c-street-city: the city-wide reachability check the coordinator asked for after crib3, civic, bike_shop)
return [====[
def motel_world_reach_survey():
 import json
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;NONE=unreal.DrawDebugTrace.NONE
 OT=[unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY1,unreal.ObjectTypeQuery.OBJECT_TYPE_QUERY2]
 base=ROOT/'output/street-social-city-production/places-v1'
 cfg=json.loads((base/'reach-tiles.json').read_text('utf8'));bat=json.loads((base/'reach-batch.json').read_text('utf8'))
 N=int(cfg['cells']);tiles=cfg['tiles'][int(bat['from'])-1:int(bat['to'])]
 legend=[];lidx={};out={}
 def ground(x,y,z):
  r=unreal.SystemLibrary.line_trace_single_for_objects(world,V(x,y,z+70),V(x,y,z-120),OT,False,[],NONE,True)
  h=r.to_tuple() if r else [False]
  return h[4].z if h[0] else None
 def body(x,y,g,rad):
  res=unreal.SystemLibrary.capsule_overlap_actors(world,V(x,y,g+105),rad,60,OT,None,[])
  acts_=res[1] if isinstance(res,tuple) else res
  return acts_[0].get_actor_label() if acts_ else None
 for t in tiles:
  z=float(t['z']);rows=[]
  for j in range(N):
   y=(t['iy0']+j)*40.;row=[]
   for i in range(N):
    x=(t['ix0']+i)*40.;g=ground(x,y,z)
    if g is None:row.append('n');continue
    d=str(int(round(g-z)))
    if body(x,y,g,40) is None:row.append(d);continue
    w=body(x,y,g,30)
    if w is None:row.append(d+',');continue
    if w not in lidx:lidx[w]=len(legend);legend.append(w)
    row.append('b%d'%lidx[w])
   rows.append(' '.join(row))
  out[t['key']]=rows
 d_=base/'reach-grid';d_.mkdir(exist_ok=True)
 (d_/('%d-%d.json'%(int(bat['from']),int(bat['to'])))).write_text(json.dumps(dict(legend=legend,tiles=out)),'utf8')
 return dict(status='passed',tiles=len(out))
]====]
