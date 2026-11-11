-- Native job: give the interiors of every building their own interior finish back (EE, LI, T4 2026-11-11; all others 11-12).
--   lua Tools/street_city_motel_job.lua world_interior_walls Tools/street_city_interior_walls_payload.lua
-- The romance PBR round (10-22, Tools/street_city_romance_pbr.lua) classified slots by name, so the interior paint and the
-- porcelain floor of the campus floors (world-wall-grok role `interior`) were taken as `wall` and got the building's facade
-- family. For most buildings that is a pale plaster or limestone, but EE (lagoon_mineral_plaster_v2), LI and T4
-- (lagoon_ceramic_v1) are blue-green mottled: walls, floor and ceiling of every room looked like a pond (ee-0205 report).
-- 11-12: the same in every other building, where the facade family was pale or, in the corner bookshop (S07), green like
-- grass (e-120fps): every interior paint, washable wall tile and porcelain floor slot the romance round touched.
-- Those interior slots and the porcelain floor go back to the material they had before the romance round (the receipt's `original`, the
-- world-wall-grok interior material or the porcelain floor). SP keeps its facade family: the sports finish reworked MI_SP_wall.
-- Facades, stairs and trims are not touched. The source map is backed up next to the output, then saved.
-- Output: places-v1/interior-walls.json (every slot: actor, slot, from, to).
return [====[
def motel_world_interior_walls():
 import hashlib,shutil
 SUB_=unreal.get_editor_subsystem(unreal.EditorActorSubsystem);EAL=unreal.EditorAssetLibrary
 MAP=ROOT/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 prod=ROOT/'output/street-social-city-production';out=prod/'places-v1/interior-walls.json'
 SKIP={'SP'}
 wall=json.loads((prod/'world-wall-grok-v1/native-install.json').read_text('utf8'))
 wl=next(v for v in wall.values() if isinstance(v,list) and v and isinstance(v[0],dict) and 'actor' in v[0])
 role={(s['actor'],s['slot']):s['role'] for s in wl}
 rom=json.loads((prod/'romance-pbr-v1/install.json').read_text('utf8'))['slots']
 # the porcelain floor never went through world-wall-grok, so it has no role there; take it by its original name
 todo=[s for s in rom if s['building'] not in SKIP and s['role']=='wall' and (role.get((s['actor'],s['slot']))=='interior' or 'porcelain' in s['original'] or 'washable' in s['original'])]
 r=dict(planned=len(todo),slots=[])
 b=out.parent/('UniversityCity-before-interior-walls-'+sha(MAP)[:16]+'.umap')
 if not b.exists():shutil.copy2(MAP,b)
 r['backup']=str(b);r['parent_map_sha256']=sha(MAP)
 actors={a.get_actor_label():a for a in SUB_.get_all_level_actors()}
 for s in todo:
  a=actors.get(s['actor']);row=dict(actor=s['actor'],slot=s['slot'],romance=s['material'],to=s['original'])
  if not a:row['skip']='no actor';r['slots'].append(row);continue
  c=next((c for c in a.get_components_by_class(unreal.StaticMeshComponent) if c.get_name()==s['component']),None)
  if not c:row['skip']='no component';r['slots'].append(row);continue
  cur=c.get_material(s['slot']);row['from']=cur.get_path_name() if cur else None
  if row['from']!=s['material']:row['skip']='slot changed since the romance round';r['slots'].append(row);continue
  m=EAL.load_asset(s['original'].split('.')[0])
  if not m:row['skip']='original material missing';r['slots'].append(row);continue
  a.modify();c.modify();c.set_material(s['slot'],m);assert c.get_material(s['slot'])==m
  row['done']=True;r['slots'].append(row)
 r['changed']=sum(1 for x in r['slots'] if x.get('done'))
 if r['changed']:assert unreal.EditorLevelLibrary.save_current_level()
 r['map_sha256']=sha(MAP);r['status']='passed'
 out.write_text(json.dumps(r,indent=1,ensure_ascii=False),'utf8')
 return dict(status='passed',planned=r['planned'],changed=r['changed'])
]====]
