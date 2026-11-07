-- Read-only native job: what UniversityCity really uses, for moving the map into OpenKoikatsu. Nothing is saved to the map.
--   lua Tools/street_city_motel_job.lua world_migrate_closure Tools/street_city_migrate_payload.lua
-- Output: output/street-social-city-production/migrate-v1/closure.json
--   packages   every /Game package the map reaches through hard and soft references
--   outside    what it reaches outside /Game and /Engine (plugin content, /Script modules)
--   classes    actor and component classes in the level, with counts
-- Tools/migrate_street_city_content.lua copies the files.
return [====[
def motel_world_migrate_closure():
 ar=unreal.AssetRegistryHelpers.get_asset_registry();opt=unreal.AssetRegistryDependencyOptions(include_soft_package_references=True,include_hard_package_references=True,include_searchable_names=False,include_soft_management_references=False,include_hard_management_references=False)
 root='/Game/UniversityCity/Maps/UniversityCity';seen={root};todo=[root];outside=set()
 while todo:
  p=todo.pop()
  for d in ar.get_dependencies(unreal.Name(p),opt) or []:
   d=str(d)
   if d.startswith('/Game/'):
    if d not in seen:seen.add(d);todo.append(d)
   elif not d.startswith('/Engine/'):outside.add(d)
 actors={};comps={}
 for a in unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors():
  k=a.get_class().get_path_name();actors[k]=actors.get(k,0)+1
  for c in a.get_components_by_class(unreal.ActorComponent):
   k=c.get_class().get_path_name();comps[k]=comps.get(k,0)+1
 o=ROOT/'output/street-social-city-production/migrate-v1';o.mkdir(parents=True,exist_ok=True)
 (o/'closure.json').write_text(json.dumps(dict(map=root,packages=sorted(seen),outside=sorted(outside),actor_classes=actors,component_classes=comps),indent=0),'utf8')
 return dict(status='passed',packages=len(seen),outside=len(outside))
]====]
