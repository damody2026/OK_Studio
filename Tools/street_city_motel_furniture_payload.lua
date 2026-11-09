return [====[
FURN_SETS=[('motel-furniture-tripo-v2','/Game/UniversityCity/MotelFurnitureTripoV2'),('motel-furniture-tripo-v3','/Game/UniversityCity/MotelFurnitureTripoV3')]

def motel_furniture_import():
 # Editor-only import of the motel furniture Tripo sets, using the registered models of each set
 # (register_street_city_motel_furniture_tripo.lua: oriented; instant-meshes-rs result only where it cut triangles,
 # otherwise the prepared mesh). Assets only: the map is not touched. Re-running replaces the same asset paths.
 global PREFIX,KEEP,save
 for setname,prefix in FURN_SETS:
  out=ROOT/'output/street-social-city-production'/setname;reg=out/'oriented/oriented.json'
  if not reg.exists():continue
  rows=json.loads(reg.read_text('utf8'));required=len(json.loads((out/'plan.json').read_text('utf8'))['items'])
  PREFIX=prefix;KEEP=[];save=save_asset;done=[]
  # build import_one after the globals it reads (PREFIX/KEEP/save) are set: exec copies globals()
  source=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0];ns=dict(globals());exec('def import_one('+source,ns);imp=ns['import_one']
  for r in rows:
   assert sha(r['path'])==r['sha256'];rid=Path(r['path']).stem;mesh=imp(Path(r['path']),rid,0,True);slots=[]
   for i,s in enumerate(mesh.get_editor_property('static_materials')):
    m=mesh.get_material(i);assert m;slots.append(m.get_path_name())
   b=mesh.get_bounding_box();ext=[round((b.max.x-b.min.x)/100,3),round((b.max.y-b.min.y)/100,3),round((b.max.z-b.min.z)/100,3)]
   assert slots and EAL.save_loaded_asset(mesh,False)
   done.append(dict(id=rid,index=r['index'],asset=mesh.get_path_name(),triangles=mesh.get_num_triangles(0),extent_m=ext,source_sha256=r['sha256'],mesh_source=r.get('source_choice'),materials=slots))
   KEEP.clear();unreal.SystemLibrary.collect_garbage()
  assert sha(MAPFILE)==LOAD_SHA
  (out/'imports.json').write_text(json.dumps(dict(status='imported_editor_only' if len(done)==required else 'partial_import_only',map_sha256=LOAD_SHA,assets=done,completed=len(done),required=required),ensure_ascii=False,indent=2),'utf8')
]====]
