return [====[
MAPFILE=ROOT/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
LOAD_SHA=sha(MAPFILE)

def motel_inventory():
 rows=[];actors=[]
 for a in SUB.get_all_level_actors():
  label=a.get_actor_label();origin,extent=a.get_actor_bounds(False)
  actors.append(dict(label=label,origin=num(origin),extent=num(extent),hidden=a.get_editor_property('hidden'),class_name=a.get_class().get_name()))
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   if not c.static_mesh:continue
   mats=[m.get_path_name() if m else '' for m in c.get_materials()]
   if re.search('H1|S18|hotel|motel|restroom|washroom|bathroom|toilet|basin|sink',label+' '+c.static_mesh.get_path_name()+' '+' '.join(mats),re.I):
    origin,extent=c.get_local_bounds();rows.append(dict(actor=label,component=c.get_name(),mesh=c.static_mesh.get_path_name(),materials=mats,location=num(c.get_world_location()),rotation=[c.get_world_rotation().pitch,c.get_world_rotation().yaw,c.get_world_rotation().roll],scale=num(c.get_world_scale()),bounds_min=num(origin),bounds_max=num(extent),instances=c.get_instance_count() if isinstance(c,unreal.InstancedStaticMeshComponent) else None))
 assert sha(MAPFILE)==LOAD_SHA
 write('native-inventory',dict(status='read_only',map_sha256=LOAD_SHA,actors=actors,candidate_components=rows))

def motel_serve():
 global MOTEL_STATE,MOTEL_HANDLE
 jobs=OUT/'jobs';jobs.mkdir(exist_ok=True);MOTEL_STATE=dict(busy=False,last_poll=0)
 write('serve-ready',dict(status='passed',map_sha256=LOAD_SHA,jobs=str(jobs),scope='Only motel-v1 task-local queue; no other chat coordination.'))
 def poll(dt):
  global LOAD_SHA
  if MOTEL_STATE['busy'] or time.monotonic()-MOTEL_STATE['last_poll']<1:return
  MOTEL_STATE['last_poll']=time.monotonic()
  for path in sorted(jobs.glob('*.request.json')):
   result=path.with_name(path.name.replace('.request.json','.result.json'))
   if result.exists():continue
   q=json.loads(path.read_text('utf8'));MOTEL_STATE['busy']=True;PAYLOAD['run_id']=q['id']
   try:
    if q['function']=='quit':
     result.write_text(json.dumps(dict(status='passed',id=q['id'])),'utf8');write('serve-ready',dict(status='stopped',map_sha256=sha(MAPFILE)));unreal.unregister_slate_post_tick_callback(MOTEL_HANDLE);unreal.SystemLibrary.quit_editor();return
    LOAD_SHA=sha(MAPFILE);assert LOAD_SHA==q['expected_map_sha256'],'Map changed before job'
    assert hashlib.sha256(q['code'].encode()).hexdigest()==q['code_sha256'];assert re.fullmatch(r'motel_[a-z_]+',q['function'])
    exec(compile(q['code'],'motel-v1 native job','exec'),globals());globals()[q['function']]();r=dict(status='passed',id=q['id'],map_sha256=sha(MAPFILE))
   except BaseException:r=dict(status='failed',id=q['id'],error=traceback.format_exc());unreal.log_error(r['error'])
   result.write_text(json.dumps(r,ensure_ascii=False,indent=2),'utf8');MOTEL_STATE['busy']=False;break
 MOTEL_HANDLE=unreal.register_slate_post_tick_callback(poll)

def work():
 try:
  motel_inventory()
  if MODE=='serve':motel_serve();return
  write(MODE,dict(status='passed',map_sha256=LOAD_SHA))
 except BaseException:write(MODE+'-error',dict(status='failed',error=traceback.format_exc()));unreal.log_error(traceback.format_exc())
 unreal.SystemLibrary.quit_editor()

assert unreal.EditorLevelLibrary.load_level(MAP)
unreal.EditorPythonScripting.set_keep_python_script_alive(True)
frames=0
def tick(dt):
 global frames
 frames+=1
 if frames<90:return
 unreal.unregister_slate_post_tick_callback(handle);work()
handle=unreal.register_slate_post_tick_callback(tick)
]====]
