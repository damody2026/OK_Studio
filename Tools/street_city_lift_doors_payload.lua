-- Native job: open the closed lift doors of the campus and dorm floors above the ground floor.
--   lua Tools/street_city_motel_job.lua world_lift_doors Tools/street_city_lift_doors_payload.lua
-- Floors already opened have nothing left in the box and are skipped, so a rerun takes only new ones (SC, SP, LI, CV came 11-08).
-- The floors were modelled with the lift door shut above 1F; the game draws its own doors at the shaft, so the landing was walled in
-- 28 cm in front. On 1F the same place is an open passage 120 cm wide. The door goes from both meshes of a floor: what is drawn, and
-- ComplexCollisionMesh, the older mesh its collision comes from. The assets are edited where they are, so the map and its streaming
-- copy keep pointing at them. Only triangles wholly inside the door's box go.
-- output/street-social-city-production/places-v1/lift-doors-apply.txt holds 1 to change the meshes; without it nothing is saved.
-- Output: places-v1/lift-doors.json
return [====[
def motel_world_lift_doors():
 import math,traceback
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'lift-doors-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 r=dict(status='passed',apply=APPLY,floors=[])
 out=base/'lift-doors.json'
 AU=unreal.GeometryScript_AssetUtils;SEL=unreal.GeometryScript_MeshSelection;ED=unreal.GeometryScript_MeshEdits;QF=unreal.GeometryScript_MeshQueries
 pub=lambda c:[m for m in dir(c) if not m.startswith('_') and m not in dir(unreal.Object)]
 names=dict(au=pub(AU),sel=pub(SEL),ed=[m for m in pub(ED) if 'delete' in m or 'remove' in m],qf=[m for m in pub(QF) if 'num' in m or 'count' in m]);r['api']=names;out.write_text(json.dumps(r,indent=1),'utf8')
 for n,c,f in (('sel_box',SEL,'select_mesh_elements_in_box'),('copy_from',AU,'copy_mesh_from_static_mesh'),('copy_to',AU,'copy_mesh_to_static_mesh'),('sel_info',SEL,'get_mesh_selection_info'),('delete',ED,'delete_selected_triangles_from_mesh')):
  names[n]=(getattr(c,f).__doc__ or '')[:700] if hasattr(c,f) else None
 out.write_text(json.dumps(r,indent=1),'utf8')
 def under(x,y,z):
  v=unreal.SystemLibrary.line_trace_single(world,V(x,y,z+60),V(x,y,z-60),Q,True,[],NONE,True);h=v.to_tuple() if v else [False]
  return h[9] if h and h[0] else None
 def load(m):
  d=unreal.DynamicMesh();o=unreal.GeometryScriptCopyMeshFromAssetOptions();l=unreal.GeometryScriptMeshReadLOD()
  o.set_editor_property('apply_build_settings',False);o.set_editor_property('request_tangents',True)
  res=AU.copy_mesh_from_static_mesh(m,d,o,l);d=res[0] if isinstance(res,tuple) else res
  return d
 def pick(d,lo,hi):
  box=unreal.Box(min=V(min(lo.x,hi.x),min(lo.y,hi.y),min(lo.z,hi.z)),max=V(max(lo.x,hi.x),max(lo.y,hi.y),max(lo.z,hi.z)))
  res=SEL.select_mesh_elements_in_box(d,box,unreal.GeometryScriptMeshSelectionType.TRIANGLES,False,3)
  return res[-1] if isinstance(res,tuple) else res
 def count(s):
  return SEL.get_mesh_selection_info(s)[-1] if isinstance(SEL.get_mesh_selection_info(s),tuple) else SEL.get_mesh_selection_info(s)
 def save(d,m):
  o=unreal.GeometryScriptCopyMeshToAssetOptions();l=unreal.GeometryScriptMeshWriteLOD()
  o.set_editor_property('enable_recompute_normals',False);o.set_editor_property('enable_recompute_tangents',False);o.set_editor_property('replace_materials',False);o.set_editor_property('emit_transaction',False);o.set_editor_property('defer_mesh_post_edit_change',False)
  AU.copy_mesh_to_static_mesh(d,m,o,l)
  assert unreal.EditorAssetLibrary.save_loaded_asset(m,False),m.get_path_name()
 places=json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_places.json').read_text('utf8'))['places']
 done=set()
 for p in places:
  if p['id'] in('school','lecture','hotel','department'):continue
  for a in p['anchors']:
   if not a['name'].startswith('lift') or a['name'].startswith('lift1:'):continue
   x,y,z=a['pos'];act=under(x,y,z);row=dict(place=p['id'],name=a['name'],pos=a['pos'],actor=act.get_actor_label() if act else None)
   r['floors'].append(row)
   if not act or row['actor'] in done:continue
   done.add(row['actor'])
   try:
    t=act.get_actor_transform();m=act.static_mesh_component.static_mesh;src=m.get_editor_property('complex_collision_mesh')
    row['mesh']=m.get_path_name();row['collision']=src.get_path_name() if src else None
    # the two leaves stand 28-32 cm out from the landing, 1-61 cm either side of the middle, 240 high; the frame round them stays
    lo=t.inverse_transform_location(V(x+27,y-62,z-1));hi=t.inverse_transform_location(V(x+33,y+62,z+241))
    for key,mesh in (('drawn',m),('solid',src)):
     if not mesh:continue
     d=load(mesh);s=pick(d,lo,hi);row[key]=str(SEL.get_mesh_selection_info(s));row[key+'_all']=QF.get_num_triangle_i_ds(d)
     if APPLY and SEL.get_mesh_selection_info(s)[1]>0:
      ED.delete_selected_triangles_from_mesh(d,s);save(d,mesh)
    if APPLY and src:
     m.set_editor_property('complex_collision_mesh',src);assert unreal.EditorAssetLibrary.save_loaded_asset(m,False)
   except Exception as e:
    row['error']=traceback.format_exc()[-500:]
    if not APPLY:out.write_text(json.dumps(r,indent=1),'utf8');return dict(status='failed',at=row['actor'],error=str(e)[:300])
 out.write_text(json.dumps(r,indent=1),'utf8');return dict(status='passed',apply=APPLY,floors=len(r['floors']),edited=len(done))
]====]
