-- Native job: open a cross alley through the shop street row at S44 (2026-11-08).
--   lua Tools/street_city_motel_job.lua world_alley Tools/street_city_alley_payload.lua
-- The shop row between the roads x 42700 and x 45700 had no way through for about 290 m, so onsen, realty and lottery were
-- a long walk round from the other side. S44 (y 43140-44340) gave the shortest detours for one shop gone, and no game place
-- uses it, so nothing has to move. Everything of S44 goes: its floors, the refit, its lights, the romance arch and name, the
-- city art pieces and the lover spot furniture of its flat; instances of the shared HISMs inside the lot are removed one by one.
-- The street lanterns of S44 stand on the sidewalk and stay. The lot is paved level with the sidewalk in its material.
-- The source map is backed up next to the output, then saved. Output: places-v1/alley-s44.json
return [====[
def motel_world_alley():
 import re,hashlib,shutil
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 SUB_=unreal.get_editor_subsystem(unreal.EditorActorSubsystem);EAL=unreal.EditorAssetLibrary
 MAP=ROOT/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 out=ROOT/'output/street-social-city-production/places-v1/alley-s44.json'
 r=dict(status='running',world=world.get_path_name())
 assert '/UniversityCity/Maps/UniversityCity.' in r['world'],r['world']
 X0,X1,Y0,Y1=43000.,45000.,43140.,44340.
 inside=lambda p,pad=0:X0-pad<=p.x<=X1+pad and Y0-pad<=p.y<=Y1+pad
 def ground(x,y):
  v=unreal.SystemLibrary.line_trace_single(world,V(x,y,1400),V(x,y,900),Q,True,[],NONE,True);h=v.to_tuple() if v else [False]
  return (h[4].z,h[9]) if h and h[0] else (None,None)
 # the sidewalk either side, read before anything goes
 side=[ground(x,y) for x in (42900,45100) for y in (43400,43740,44080)]
 r['sidewalk']=[[round(z,1) if z is not None else None,a.get_actor_label() if a else None] for z,a in side]
 zs=[z for z,a in side if z is not None];assert zs,'no sidewalk'
 top=max(zs);r['sidewalk_spread']=round(max(zs)-min(zs),1)
 pave=next((a for z,a in side if a and z is not None and abs(z-top)<3),None);mat=None
 if pave and pave.get_component_by_class(unreal.StaticMeshComponent):
  c=pave.get_component_by_class(unreal.StaticMeshComponent);ms=[c.get_material(i) for i in range(c.get_num_materials())]
  r['pave_materials']=[m.get_name() if m else None for m in ms]
  mat=next((m for m in ms if m and re.search('(?i)pave|side|walk|tile|stone|brick',m.get_name())),None) or (ms[0] if ms else None)
 r['pave']=pave.get_actor_label() if pave else None;r['material']=mat.get_path_name() if mat else None
 b=out.parent/('UniversityCity-before-alley-s44-'+sha(MAP)[:16]+'.umap')
 if not b.exists():shutil.copy2(MAP,b)
 r['backup']=str(b);r['parent_map_sha256']=sha(MAP)
 own=re.compile(r'^(S44_F\d+|ShopV1_S44_.*|RomanceArch_S44|RomanceName_S44|CityArtLight_S44|CityArt_.*_S44)$')
 gone=[];cut=[];kept=[]
 for a in list(SUB_.get_all_level_actors()):
  lab=a.get_actor_label();o,e=a.get_actor_bounds(False);folder=str(a.get_folder_path())
  big=e.x>3000 or e.y>3000
  if lab.startswith('ResortLantern_S44'):kept.append(lab);continue
  mine=own.match(lab) or folder.endswith('/S44') or ('s44-' in lab.lower() and lab.startswith('LoverSpot_')) or (lab.startswith('LoverSpot_') and inside(o) and not big)
  if mine and not big:
   gone.append(dict(label=lab,c=[round(o.x),round(o.y),round(o.z)]));SUB_.destroy_actor(a);continue
  if big or 'S44' in lab:
   for c in a.get_components_by_class(unreal.InstancedStaticMeshComponent):
    n=0
    for i in range(c.get_instance_count()-1,-1,-1):
     t=c.get_instance_transform(i,True);t=t[-1] if isinstance(t,tuple) else t
     if inside(t.translation,-20):c.remove_instance(i);n+=1
    if n:cut.append([lab,c.get_name(),n])
  elif 'S44' in lab:kept.append(lab)
 r['destroyed']=gone;r['instances_removed']=cut;r['kept']=kept
 # the paving: a flat block from road kerb to road kerb, 2 cm over the sidewalk mesh at each end, a few mm proud of it
 cube=EAL.load_asset('/Engine/BasicShapes/Cube.Cube');T=30.
 sx,sy=(X1-X0+20)/100.,(Y1-Y0+40)/100.
 for a in list(SUB_.get_all_level_actors()):
  if a.get_actor_label()=='Alley_S44_Paving':SUB_.destroy_actor(a)
 p=SUB_.spawn_actor_from_object(cube,V((X0+X1)/2,(Y0+Y1)/2,top+0.3-T/2),unreal.Rotator(0,0,0))
 p.set_actor_label('Alley_S44_Paving');p.set_actor_scale3d(V(sx,sy,T/100.));p.set_folder_path('Shops/Alley')
 c=p.static_mesh_component
 if mat:c.set_material(0,mat)
 c.set_editor_property('mobility',unreal.ComponentMobility.STATIC)
 r['paving']=dict(top=round(top+0.3,1),x=[X0-10,X1+10],y=[Y0-20,Y1+20])
 after=[ground(x,y) for x in (43200,44000,44800) for y in (43300,43740,44200)]
 r['after']=[[round(z,1) if z is not None else None,a.get_actor_label() if a else None] for z,a in after]
 assert all(a and a.get_actor_label()=='Alley_S44_Paving' for z,a in after),r['after']
 assert unreal.EditorLevelLibrary.save_current_level()
 r['map_sha256']=sha(MAP);r['status']='passed'
 out.write_text(json.dumps(r,indent=1),'utf8')
 return dict(status='passed',destroyed=len(gone),instances=sum(x[2] for x in cut),top=r['paving']['top'],material=r['material'])
]====]
