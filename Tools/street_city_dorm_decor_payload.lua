return [====[
DORM_OUT=ROOT/'output/street-social-city-production/dorm-decor-v1'

def motel_dorm_decor_install():
 # One merged dorm-floor dressing mesh (Tools/build_street_city_dorm_decor.lua), placed on every D1..D4 F02..F06 floor:
 # actor = anchor + (floor actor offset from Campus_D1_F02) at that floor's scanned level. No collision: dressing only.
 global PREFIX,KEEP,save
 b=json.loads((DORM_OUT/'build.json').read_text('utf8'));assert sha(b['path'])==b['sha256']
 PREFIX='/Game/UniversityCity/DormDecorV1';KEEP=[];save=save_asset
 src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one']
 mesh=imp(Path(b['path']),'dorm-floor-decor',0,True)
 bs=mesh.get_editor_property('body_setup')
 if bs:bs.set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_SIMPLE_AS_COMPLEX)
 assert EAL.save_loaded_asset(mesh,False)
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 backup=DORM_OUT/('UniversityCity-before-dorm-decor-'+LOAD_SHA[:16]+'.umap')
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 for label,a in list(actors.items()):
  if label.startswith('DormDecorV1_'):SUB.destroy_actor(a)
 base=actors['Campus_D1_F02'].get_actor_location();ax,ay,az=b['anchor_cm'];rows=[]
 for f in b['floors']:
  fa=actors[f['actor']];d=fa.get_actor_location()-base
  a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(ax+d.x,ay+d.y,f['floor_z']),unreal.Rotator(0,0,0))
  a.set_actor_label('DormDecorV1_'+f['actor']);a.tags=[unreal.Name('DormDecorV1')];a.set_folder_path('UniversityCity/DormDecorV1')
  c=a.static_mesh_component;c.set_static_mesh(mesh);c.set_collision_profile_name('NoCollision');c.set_editor_property('cast_shadow',True)
  rows.append(dict(actor=a.get_actor_label(),location=num(a.get_actor_location()),beds=f['beds'],desks=f['desks']))
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)  # the motel audit keys on the current map
 (DORM_OUT/'install.json').write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),mesh=mesh.get_path_name(),triangles=mesh.get_num_triangles(0),actors=rows),ensure_ascii=False,indent=2),'utf8')

def motel_office_decor_install():
 floor_decor_install('office-decor-v1','OfficeDecorV1','-decor')

def motel_classroom_decor_install():
 floor_decor_install('classroom-decor-v1','ClassroomDecorV1','-class-decor')

def motel_office_fit_install():
 floor_decor_install('office-fit-v1','OfficeFitV1','-fit')

def motel_office_fit_scan():
 # Empty office floors (shop-survey-v1/office-fit-want.json): 40 cm grid on the floor actor bounds at this floor's own slab.
 # free: a ray down from 1.8 m lands on the slab (nothing standing there below 1.8 m). ex/ey: a ray at 1.0 m from this cell
 # centre to its +x / +y neighbour hits something (wall, door frame, glazing). Builder: Tools/build_street_city_office_fit.lua.
 world=unreal.EditorLevelLibrary.get_editor_world();want=json.loads((ROOT/'output/street-social-city-production/shop-survey-v1/office-fit-want.json').read_text('utf8'))
 def hit(p0,p1):
  r=unreal.SystemLibrary.line_trace_single(world,p0,p1,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
  t=r.to_tuple() if r is not None else (False,)+(None,)*11
  return t[4] if t[0] else None
 rows=[]
 for a in SUB.get_all_level_actors():
  if a.get_actor_label() not in want:continue
  o,e=a.get_actor_bounds(False);hs={}
  for i in range(-20,21):
   for k in range(-8,9):
    p=hit(unreal.Vector(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z+250),unreal.Vector(o.x+i*e.x/22,o.y+k*e.y/10,o.z-e.z-50))
    if p is not None:hs[round(p.z/5)*5]=hs.get(round(p.z/5)*5,0)+1
  fz=max(hs,key=hs.get);step=40.;nx,ny=int(2*e.x/step),int(2*e.y/step);x0,y0=o.x-e.x,o.y-e.y
  free=[];ex=[];ey=[]
  for k in range(ny):
   fr='';rx='';ry=''
   for i in range(nx):
    x,y=x0+step*(i+.5),y0+step*(k+.5);p=hit(unreal.Vector(x,y,fz+180),unreal.Vector(x,y,fz-20))
    fr+='1' if p is not None and abs(p.z-fz)<6 else '0'
    rx+='1' if i+1<nx and hit(unreal.Vector(x,y,fz+100),unreal.Vector(x+step,y,fz+100)) is not None else '0'
    ry+='1' if k+1<ny and hit(unreal.Vector(x,y,fz+100),unreal.Vector(x,y+step,fz+100)) is not None else '0'
   free.append(fr);ex.append(rx);ey.append(ry)
  rows.append(dict(actor=a.get_actor_label(),anchor=num(a.get_actor_location()),floor_z=fz,origin=[x0,y0],step=step,nx=nx,ny=ny,free=free,ex=ex,ey=ey))
  print('office fit scan',a.get_actor_label(),nx,ny,flush=True)
 assert sha(MAPFILE)==LOAD_SHA
 (ROOT/'output/street-social-city-production/shop-survey-v1/office-fit-scan.json').write_text(json.dumps(dict(map_sha256=LOAD_SHA,floors=sorted(rows,key=lambda r:r['actor'])),ensure_ascii=False),'utf8')

def floor_decor_install(dirname,tag,suffix):
 # Per-floor dressing meshes (Tools/build_street_city_office_decor.lua, build_street_city_classroom_decor.lua): each actor
 # <tag>_<floor actor> at its floor anchor, no collision; re-installs replace this tag's actors only.
 global PREFIX,KEEP,save
 O=ROOT/'output/street-social-city-production'/dirname;b=json.loads((O/'build.json').read_text('utf8'))
 PREFIX='/Game/UniversityCity/'+tag;KEEP=[];save=save_asset
 src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+src,ns);imp=ns['import_one']
 actors={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 backup=O/('UniversityCity-before-'+dirname+'-'+LOAD_SHA[:16]+'.umap')
 if not backup.exists():shutil.copy2(MAPFILE,backup)
 for label,a in list(actors.items()):
  if label.startswith(tag+'_'):SUB.destroy_actor(a)
 rows=[]
 for f in b['floors']:
  assert sha(f['path'])==f['sha256'];mesh=imp(Path(f['path']),f['actor'].lower().replace('_','-')+suffix,0,True);assert EAL.save_loaded_asset(mesh,False)
  ax,ay,az=f['anchor_cm'];a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,unreal.Vector(ax,ay,az),unreal.Rotator(0,0,0))
  a.set_actor_label(tag+'_'+f['actor']);a.tags=[unreal.Name(tag)];a.set_folder_path('UniversityCity/'+tag)
  c=a.static_mesh_component;c.set_static_mesh(mesh);c.set_collision_profile_name('NoCollision')
  rows.append(dict(actor=a.get_actor_label(),mesh=mesh.get_path_name(),**{k:f[k] for k in ('desks','plants','counts','triangles') if k in f}))
  KEEP.clear();unreal.SystemLibrary.collect_garbage()
 actors['CityEnvironmentController'].prepare_for_save();assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (O/'install.json').write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(backup),actors=rows),ensure_ascii=False,indent=2),'utf8')
]====]
