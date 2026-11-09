-- Whole-world Tripo pass (Docs/STREET_CITY_WORLD_GAP_INVENTORY_20261029.md section 6):
--   lua Tools/street_city_motel_job.lua world_tripo_install Tools/street_city_world_tripo_payload.lua
--   street     every box-built street piece gets a Tripo look in the same spot. The old instances stay as invisible collision, so
--              walks and seats do not change; the Tripo instances have no collision.
--   landscape  shrubs, flowers, rocks and grasses scattered on the lawns of their zones, hedges along lawn edges. No collision,
--              and they keep 1.2 m off every walked route.
-- Instanced meshes need a material with the instanced usage flag, which the engine's glTF base material does not have (a
-- cooked build would fall back to the default material), so each model gets instances of M_WorldTripoPBR here.
-- Re-running removes the WorldTripo-v1 actors first. Writes world-tripo-v1/install-<time>.json.
return [====[
WT_OUT=ROOT/'output/street-social-city-production/world-tripo-v1'
WT_DIR='/Game/UniversityCity/WorldTripoV1'
WT_SWAP={'bench-oak':['bench_slat_a','bench_slat_b'],'bench-stone':['bench_backless'],'planter-long':['planter_rect','planter_rect','planter_rect','planter_wood'],'planter-square':['planter_round'],
 'lamp-lantern':['lamp_lantern_post'],'lamp-modern':['lamp_double_arm'],'recycling':['recycle_station_a','recycle_station_b'],'cycle-rack':['bicycle_rack'],'utility-box':['utility_cabinet','telecom_box'],
 'bus-shelter':['bus_shelter'],'bicycle':['bicycle_city_a','bicycle_city_b'],'scooter':['scooter_small']}
WT_ZONE=dict(Z1=(0,150,0,1050),Z2=(150,300,0,1080),Z3=(280,480,150,600),Z5=(450,950,0,900),Z6=(300,1000,840,940),Z9=(950,1100,0,1050),Z10=(300,1100,1000,1100))
WT_GRASS='MI_Detail_b6a245f3a69b53317770'
def _wt_base():
 path=WT_DIR+'/M_WorldTripoPBR'
 if EAL.does_asset_exist(path):return EAL.load_asset(path)
 m=ATS.create_asset('M_WorldTripoPBR',WT_DIR,unreal.Material,unreal.MaterialFactoryNew())
 def tex(name,kind,default):
  n=MEL.create_material_expression(m,unreal.MaterialExpressionTextureSampleParameter2D);n.set_editor_property('parameter_name',name);n.set_editor_property('sampler_type',kind);n.set_editor_property('texture',EAL.load_asset(default));return n
 c=tex('BaseColorTexture',unreal.MaterialSamplerType.SAMPLERTYPE_COLOR,'/Engine/EngineMaterials/DefaultDiffuse')
 f=MEL.create_material_expression(m,unreal.MaterialExpressionVectorParameter);f.set_editor_property('parameter_name','BaseColorFactor');f.set_editor_property('default_value',unreal.LinearColor(1,1,1,1))
 mul=MEL.create_material_expression(m,unreal.MaterialExpressionMultiply);MEL.connect_material_expressions(c,'RGB',mul,'A');MEL.connect_material_expressions(f,'',mul,'B');MEL.connect_material_property(mul,'',unreal.MaterialProperty.MP_BASE_COLOR)
 n=tex('NormalTexture',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL,'/Engine/EngineMaterials/DefaultNormal');MEL.connect_material_property(n,'RGB',unreal.MaterialProperty.MP_NORMAL)
 r=tex('MetallicRoughnessTexture',unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR,'/Engine/EngineMaterials/T_Default_Material_Grid_M')
 MEL.connect_material_property(r,'G',unreal.MaterialProperty.MP_ROUGHNESS);MEL.connect_material_property(r,'B',unreal.MaterialProperty.MP_METALLIC)
 m.set_editor_property('used_with_instanced_static_meshes',True);MEL.recompile_material(m);assert EAL.save_loaded_asset(m,False);return m
def _wt_rebind(mesh,base,key):
 # the imported glTF instances' textures, moved onto instances of the instancing-safe base
 for i,slot in enumerate(mesh.get_editor_property('static_materials')):
  src=slot.get_editor_property('material_interface');name='MI_'+key+'_'+str(i);path=WT_DIR+'/Instances/'+name
  if src and src.get_path_name().startswith(path):continue
  mi=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset(name,WT_DIR+'/Instances',unreal.MaterialInstanceConstant,unreal.MaterialInstanceConstantFactoryNew())
  MEL.set_material_instance_parent(mi,base)
  if isinstance(src,unreal.MaterialInstanceConstant):
   for q in src.get_editor_property('texture_parameter_values'):
    n=str(q.get_editor_property('parameter_info').get_editor_property('name'));t=q.get_editor_property('parameter_value')
    if n in('BaseColorTexture','NormalTexture','MetallicRoughnessTexture') and t:MEL.set_material_instance_texture_parameter_value(mi,n,t)
   for q in src.get_editor_property('vector_parameter_values'):
    if str(q.get_editor_property('parameter_info').get_editor_property('name'))=='BaseColorFactor':MEL.set_material_instance_vector_parameter_value(mi,'BaseColorFactor',q.get_editor_property('parameter_value'))
  MEL.update_material_instance(mi);assert EAL.save_loaded_asset(mi,False);mesh.set_material(i,mi)
def _wt_lean(mesh):
 # which way the upper half of a mesh sits off its middle: the backrest side of a bench, the wall of a shelter
 try:vs=list(unreal.ProceduralMeshLibrary.get_section_from_static_mesh(mesh,0,0)[0])
 except Exception:return None
 bb=mesh.get_bounding_box();lo,hi=bb.min,bb.max;up=[v for v in vs if v.z>(lo.z+hi.z)/2]
 return (sum(v.x for v in up)/len(up)-(lo.x+hi.x)/2,sum(v.y for v in up)/len(up)-(lo.y+hi.y)/2) if up else None
def motel_world_tripo_install():
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;N=unreal.DrawDebugTrace.NONE
 b=WT_OUT/('UniversityCity-before-world-tripo-'+LOAD_SHA[:16]+'.umap')
 if not b.exists():shutil.copy2(MAPFILE,b)
 for a in list(SUB.get_all_level_actors()):
  if 'WorldTripo-v1' in [str(t) for t in a.tags]:SUB.destroy_actor(a)
 plan={q['key']:q for q in json.loads((WT_OUT/'plan.json').read_text('utf-8-sig'))['items']}
 pr={q['id']:q for q in json.loads((WT_OUT/'prepared.json').read_text('utf-8-sig'))['assets']}
 paths={}
 for r in json.loads((WT_OUT/'remeshed.json').read_text('utf-8-sig'))['assets']:
  p=pr[r['id']];paths[p['key']]=r['path'] if r.get('triangles',1e9)<p.get('triangles',0) else p['path']
 base=_wt_base();meshes={}
 src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0]
 ns=dict(globals());ns.update(PREFIX=WT_DIR,KEEP=[],save=lambda a:EAL.save_loaded_asset(a,False));exec('def import_one('+src,ns)
 api=unreal.get_editor_subsystem(unreal.StaticMeshEditorSubsystem)
 def mesh(key):
  if key in meshes:return meshes[key]
  m=ns['import_one'](type(ROOT)(paths[key]),'wt-'+key,0,True);_wt_rebind(m,base,key.replace('-','_'))
  if api.get_lod_count(m)<3:
   o=unreal.EditorScriptingMeshReductionOptions();o.set_editor_property('auto_compute_lod_screen_size',False);st=[]
   for pc,sc in [(1.,1.),(.35,.2),(.12,.06)]:
    r=unreal.EditorScriptingMeshReductionSettings();r.set_editor_property('percent_triangles',pc);r.set_editor_property('screen_size',sc);st.append(r)
   o.set_editor_property('reduction_settings',st);api.set_lods(m,o)
  assert EAL.save_loaded_asset(m,False);meshes[key]=m;return m
 bp=EAL.load_asset('/Game/UniversityCity/StreetScenery/BP_StreetCluster');cells={}
 def put(key,t):cells.setdefault((key,int(t.translation.x//30000),int(t.translation.y//30000)),[]).append(t)
 def flush():
  n=0
  for (key,cx,cy),ts in sorted(cells.items()):
   m=mesh(key);ox,oy=(cx+.5)*30000,(cy+.5)*30000;oz=min(t.translation.z for t in ts);a=SUB.spawn_actor_from_class(bp.generated_class(),V(ox,oy,oz));assert a
   a.set_actor_label('WorldTripo_%s_%d_%d'%(key,cx,cy));a.tags=[unreal.Name('WorldTripo-v1')];a.set_folder_path('UniversityCity/WorldTripo/'+key)
   c=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent);a.root_component and a.root_component.set_mobility(unreal.ComponentMobility.STATIC);c.set_mobility(unreal.ComponentMobility.STATIC);c.set_static_mesh(m);c.clear_instances()
   c.set_collision_profile_name('NoCollision');bb=m.get_bounding_box();tall=bb.max.z-bb.min.z;c.set_cull_distances(*((30000,40000) if tall>300 else (12000,16000)));c.set_cast_shadow(tall>60)
   c.add_instances([unreal.Transform(location=V(t.translation.x-ox,t.translation.y-oy,t.translation.z-oz),rotation=t.rotation.rotator(),scale=t.scale3d) for t in ts],False,False,False);n+=len(ts)
  return n
 # street: same spot, same facing, the old look switched off
 swapped={}
 acts=[a for a in SUB.get_all_level_actors() if 'StreetScenery-v1' in [str(t) for t in a.tags]]
 for a in acts:
  aid=next((str(t)[6:] for t in a.tags if str(t).startswith('Asset-')),'');keys=WT_SWAP.get(aid)
  c=a.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
  if not keys or not c or not c.static_mesh:continue
  ob=c.static_mesh.get_bounding_box();ol,oh=ob.min,ob.max;oex,oey,oez=oh.x-ol.x,oh.y-ol.y,oh.z-ol.z;oc=((ol.x+oh.x)/2,(ol.y+oh.y)/2);olean=_wt_lean(c.static_mesh)
  for i in range(c.get_instance_count()):
   t=c.get_instance_transform(i,True);p=t.translation;key=keys[(int(abs(p.x)//100)+int(abs(p.y)//100))%len(keys)];m=mesh(key);nb=m.get_bounding_box();nl,nh=nb.min,nb.max;nex,ney,nez=nh.x-nl.x,nh.y-nl.y,nh.z-nl.z
   yaw=t.rotation.rotator().yaw;s0=t.scale3d.x
   rot=90 if (oex>=oey)!=(nex>=ney) else 0
   # same long side, then the same side leaning back
   nlean=_wt_lean(m)
   if nlean and olean:
    r=math.radians(rot);lx,ly=nlean[0]*math.cos(r)-nlean[1]*math.sin(r),nlean[0]*math.sin(r)+nlean[1]*math.cos(r)
    short=0 if oex<oey else 1
    if abs((lx,ly)[short])>.03*min(nex,ney) and abs(olean[short])>.03*min(oex,oey) and (lx,ly)[short]*olean[short]<0:rot+=180
   fw,ac=(ney,nex) if rot%180 else (nex,ney);s=max(.7,min(1.3,min(max(oex,oey)/max(fw,ac,1),oez/max(nez,1) if aid.startswith('lamp') or aid=='bus-shelter' else 1.)))*s0
   if aid.startswith('lamp'):s=oez/max(nez,1)*s0
   ya=math.radians(yaw);ra=math.radians(yaw+rot);ncx,ncy=(nl.x+nh.x)/2*s,(nl.y+nh.y)/2*s;ocx,ocy=oc[0]*s0,oc[1]*s0
   wx=p.x+ocx*math.cos(ya)-ocy*math.sin(ya)-(ncx*math.cos(ra)-ncy*math.sin(ra));wy=p.y+ocx*math.sin(ya)+ocy*math.cos(ya)-(ncx*math.sin(ra)+ncy*math.cos(ra))
   put(key,unreal.Transform(location=V(wx,wy,p.z+ol.z*s0-nl.z*s),rotation=unreal.Rotator(roll=0,pitch=0,yaw=yaw+rot),scale=V(s,s,s)));swapped[key]=swapped.get(key,0)+1
  c.set_visibility(False,True);c.set_hidden_in_game(True);c.set_cast_shadow(False)
 # landscape: lawns found by the ground's own material, routes kept clear
 routes=set()
 import glob
 pp=sorted(glob.glob(str(ROOT/'output/street-social-city-production/motel-v1/physics-*-plan.json')))
 if pp:
  for r in json.loads(open(pp[-1],encoding='utf8').read()).get('walk_routes',[]):
   for q in r['points']:routes.add((int(q[0]//240),int(q[1]//240)))
 def hit(x,y):
  r=unreal.SystemLibrary.line_trace_single(world,V(x,y,30000),V(x,y,-5000),Q,True,[],N,True);h=r.to_tuple() if r else [False]
  if not h[0]:return None
  mat=''
  try:
   q=h[10].get_material_from_collision_face_index(h[15]);q=q[0] if isinstance(q,tuple) else q;mat=q.get_name() if q else ''
  except Exception:pass
  return h[4],mat,h[7]
 import random
 rnd=random.Random(20261104);lawn={}
 def is_lawn(x,y):
  k=(round(x),round(y))
  if k not in lawn:
   g=hit(x,y);lawn[k]=(g[0],g[2]) if g and WT_GRASS in g[1] else None
  return lawn[k]
 placed={};skipped={}
 for key,q in plan.items():
  if q.get('group')!='landscape' or key not in paths or key in('lily_pads','reeds_a','reeds_b','dune_grass','coastal_rocks'):continue
  zs=[z for z in q['zone'].split() if z in WT_ZONE]
  if not zs:continue
  want=int(q['instances']*.7);hedge=key.startswith('hedge') or key=='flower_border';tries=0;got=0;m=mesh(key);bb=m.get_bounding_box();lz=bb.min.z
  while got<want and tries<want*30:
   tries+=1;z=WT_ZONE[rnd.choice(zs)];x=rnd.uniform(z[0],z[1])*100;y=rnd.uniform(z[2],z[3])*100
   if (int(x//240),int(y//240)) in routes:continue
   g=is_lawn(x,y)
   if not g or g[1].z<.9:continue
   yaw=rnd.uniform(0,360)
   if hedge:
    # a lawn edge: grass here, something else 2.5 m away on one axis; the hedge runs along it
    e=[(0,250),(0,-250),(250,0),(-250,0)];rnd.shuffle(e);d=next((d for d in e if not is_lawn(x+d[0],y+d[1])),None)
    if not d:continue
    yaw=0 if d[0]==0 else 90
   s=rnd.uniform(.85,1.15);put(key,unreal.Transform(location=V(x,y,g[0].z-lz*s-2),rotation=unreal.Rotator(roll=0,pitch=0,yaw=yaw),scale=V(s,s,s)));got+=1
  placed[key]=got
  if got<want:skipped[key]=want-got
 total=flush()
 acts=SUB.get_all_level_actors();cec=next((a for a in acts if a.get_actor_label()=='CityEnvironmentController'),None);cec and cec.prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (WT_OUT/('install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),instances=total,swapped=swapped,scattered=placed,short=skipped),ensure_ascii=False,indent=1),'utf8')
]====]
