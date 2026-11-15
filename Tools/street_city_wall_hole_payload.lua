-- Native job: a door hole through a wall whose mesh is open (single-sided faces), where the boolean of
-- Tools/street_city_shop_passage_payload.lua goes wrong: the karaoke S48's west partition (11-16) came out as a closed
-- box with walls on the cut's own sides. Here the mesh is sliced along the box's four sides, its bottom and its top
-- (plane slices, nothing filled) and the triangles left wholly inside the box are deleted: the wall gets a clean
-- opening, nothing is added. (Without the bottom slice nothing was deleted: the wall runs on below the floor.)
--   lua Tools/street_city_motel_job.lua world_wall_hole Tools/street_city_wall_hole_payload.lua
-- Input: places-v1/wall-hole.json { cuts = [{ name, box = [x0,y0,z0,x1,y1,z1], actors = [labels] }], grid = { box, z, step } }
-- places-v1/wall-hole-apply.txt holding 1 saves the meshes (drawn and its complex collision source); otherwise it only
-- counts what it would delete. Output: places-v1/wall-hole-result.json (per mesh: triangles before, after the slices,
-- deleted; the grid after, '.' a 40x40 cm box 3 cm over the floor is clear, '#' not).
return [====[
def motel_world_wall_hole():
 import json,traceback
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'wall-hole-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 cfg=json.loads((base/'wall-hole.json').read_text('utf8'));out=base/'wall-hole-result.json'
 AU=unreal.GeometryScript_AssetUtils;BO=unreal.GeometryScript_MeshBooleans;QF=unreal.GeometryScript_MeshQueries
 def pick(*names):
  for n in names:
   if hasattr(unreal,n):return getattr(unreal,n)
  return None
 # Geometry Script functions found by name in whichever GeometryScript* class has them (the Python class names differ
 # from the C++ ones and between versions: GeometryScript_MeshBasicEditFunctions and _ListUtilities were not there)
 # function libraries only: the struct GeometryScriptIndexList has methods of the same names (11-16)
 GS=[getattr(unreal,n) for n in dir(unreal) if n.startswith('GeometryScript')]
 GS=[c for c in GS if isinstance(c,type) and issubclass(c,unreal.Object)]
 def of(res,T):
  if isinstance(res,T):return res
  if isinstance(res,tuple):
   for x in res:
    if isinstance(x,T):return x
  return None
 def fn(name):
  for c in GS:
   if hasattr(c,name):return getattr(c,name)
  raise AttributeError('no GeometryScript class has '+name)
 r=dict(status='passed',apply=APPLY,cuts=[])
 need=['get_all_triangle_i_ds','convert_index_list_to_array','delete_triangle_from_mesh','get_triangle_positions','apply_mesh_plane_slice']
 miss=[n for n in need if not any(hasattr(c,n) for c in GS)]
 if miss:
  r.update(status='failed',why='missing '+','.join(miss),names=sorted(n for n in dir(unreal) if n.startswith('GeometryScript')))
  out.write_text(json.dumps(r,indent=1),'utf8');return dict(status='passed',apply=APPLY,failed=True)
 def load(m):
  d=unreal.DynamicMesh();o=unreal.GeometryScriptCopyMeshFromAssetOptions();l=unreal.GeometryScriptMeshReadLOD()
  o.set_editor_property('apply_build_settings',False);o.set_editor_property('request_tangents',True)
  res=AU.copy_mesh_from_static_mesh(m,d,o,l);return res[0] if isinstance(res,tuple) else res
 def save(d,m):
  o=unreal.GeometryScriptCopyMeshToAssetOptions();l=unreal.GeometryScriptMeshWriteLOD()
  o.set_editor_property('enable_recompute_normals',False);o.set_editor_property('enable_recompute_tangents',False);o.set_editor_property('replace_materials',False);o.set_editor_property('emit_transaction',False);o.set_editor_property('defer_mesh_post_edit_change',False)
  AU.copy_mesh_to_static_mesh(d,m,o,l);assert unreal.EditorAssetLibrary.save_loaded_asset(m,False),m.get_path_name()
 def frame(p,n):
  # a plane through p with normal n (local space): the transform's Z axis is the plane normal
  rot=unreal.MathLibrary.make_rot_from_z(n);return unreal.Transform(p,rot,V(1,1,1))
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 for cut in cfg['cuts']:
  x0,y0,z0,x1,y1,z1=cut['box'];row=dict(name=cut['name'],box=cut['box'],meshes=[])
  for lab in cut['actors']:
   a=acts.get(lab)
   if not a:row['meshes'].append(dict(actor=lab,missing=True));continue
   for c in a.get_components_by_class(unreal.StaticMeshComponent):
    m=c.static_mesh
    if not m:continue
    xf=c.get_world_transform();src=m.get_editor_property('complex_collision_mesh')
    lo=xf.inverse_transform_location(V(x0,y0,z0));hi=xf.inverse_transform_location(V(x1,y1,z1))
    bmin=V(min(lo.x,hi.x),min(lo.y,hi.y),min(lo.z,hi.z));bmax=V(max(lo.x,hi.x),max(lo.y,hi.y),max(lo.z,hi.z))
    for key,mesh in (('solid',src),('drawn',m)):
     if not mesh:continue
     try:
      d=load(mesh);n0=QF.get_num_triangle_i_ds(d)
      so=unreal.GeometryScriptMeshPlaneSliceOptions();so.set_editor_property('fill_holes',False)
      for p,n in ((V(bmin.x,0,0),V(1,0,0)),(V(bmax.x,0,0),V(1,0,0)),(V(0,bmin.y,0),V(0,1,0)),(V(0,bmax.y,0),V(0,1,0)),(V(0,0,bmin.z),V(0,0,1)),(V(0,0,bmax.z),V(0,0,1))):
       BO.apply_mesh_plane_slice(d,frame(p,n),so)
      n1=QF.get_num_triangle_i_ds(d)
      # the triangles wholly inside the box, one by one (select_mesh_elements_in_box chose none on 11-16: its Box from
      # Python is not marked valid)
      ids=of(fn('get_all_triangle_i_ds')(d),unreal.GeometryScriptIndexList)
      res=fn('convert_index_list_to_array')(ids)
      arr=res if isinstance(res,(list,unreal.Array)) else next((x for x in res if isinstance(x,(list,unreal.Array))),[])
      arr=[int(x) for x in arr]
      e=.5;inside=[]
      for t in arr:
       res=QF.get_triangle_positions(d,t);vs=[x for x in (res if isinstance(res,tuple) else (res,)) if isinstance(x,unreal.Vector)]
       if len(vs)==3 and all(bmin.x-e<=v.x<=bmax.x+e and bmin.y-e<=v.y<=bmax.y+e and bmin.z-e<=v.z<=bmax.z+e for v in vs):inside.append(t)
      # one by one (deleting by an index list from Python removed nothing, 11-16)
      one=fn('delete_triangle_from_mesh')
      for t in inside:one(d,t)
      # counted from the IDs in use: get_num_triangle_i_ds is the highest ID, deleting leaves gaps and it stays the same
      def count():
       res=fn('convert_index_list_to_array')(of(fn('get_all_triangle_i_ds')(d),unreal.GeometryScriptIndexList))
       a=res if isinstance(res,(list,unreal.Array)) else next((x for x in res if isinstance(x,(list,unreal.Array))),[])
       return len(a)
      n1=len(arr);n2=count()
      ent=dict(actor=lab,key=key,mesh=mesh.get_path_name(),before=n0,sliced=n1,after=n2,deleted=n1-n2,inside=len(inside))
      if APPLY and n2!=n0:save(d,mesh);ent['saved']=True
      row['meshes'].append(ent)
     except Exception:row['meshes'].append(dict(actor=lab,key=key,error=traceback.format_exc()[-700:]))
    if APPLY and src:
     m.set_editor_property('complex_collision_mesh',None);m.set_editor_property('complex_collision_mesh',src);unreal.EditorAssetLibrary.save_loaded_asset(m,False)
     if hasattr(c,'recreate_physics_state'):c.recreate_physics_state()
  r['cuts'].append(row)
 g=cfg.get('grid')
 if g:
  X0,Y0,X1,Y1=g['box'];Z=float(g['z']);ST=float(g.get('step',10));rows=[];y=Y0+ST/2
  while y<Y1:
   s='';x=X0+ST/2
   while x<X1:
    mm=V(x,y,Z+3+93.5);h=unreal.SystemLibrary.box_trace_single(world,mm,mm+V(0,0,1),V(20,20,93.5),unreal.Rotator(0,0,0),Q,True,[],NONE,True)
    s+='#' if (h and h.to_tuple()[0]) else '.';x+=ST
   rows.append(s);y+=ST
  r['grid']=dict(box=g['box'],z=Z,step=ST,rows=rows)
 out.write_text(json.dumps(r,indent=1),'utf8')
 return dict(status='passed',apply=APPLY,cuts=len(r['cuts']))
]====]
