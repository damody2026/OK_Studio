-- Native job: a walk-through passage across the shop row S26-S43 (x 43000-45000, y 20860-43080).
--   lua Tools/street_city_motel_job.lua world_shop_passage Tools/street_city_shop_passage_payload.lua
-- The row stands 222 m long with 60 cm between buildings; the only way across was the S44 alley at its north end, so the park
-- (west) to the bookstore S07 (47110,28660) walked 272 m for 129 m straight (c-conquest, 11-12). S32 stands in line with the
-- bookstore but its rooms are used (s32-f01 shop, s32-0301 home), so it is not taken down: its ground floor becomes a shop you
-- can walk through, a back door cut in the west wall facing the one already open on the east side.
-- Input: places-v1/shop-passage.json { actors = [labels], cuts = [{ name, box = [x0,y0,z0,x1,y1,z1] }] } (world cm)
-- places-v1/shop-passage-apply.txt holds 1 to cut the boxes out of the meshes (drawn and its complex collision source) and
-- save them; otherwise it only maps the floor: wall sections at 60 cm and a 20 cm collision grid of the box around them.
-- Output: places-v1/shop-passage-result.json
return [====[
def motel_world_shop_passage():
 import traceback
 world=unreal.EditorLevelLibrary.get_editor_world();V=unreal.Vector;Q=unreal.TraceTypeQuery.TRACE_TYPE_QUERY1;NONE=unreal.DrawDebugTrace.NONE
 base=ROOT/'output/street-social-city-production/places-v1';flag=base/'shop-passage-apply.txt'
 APPLY=flag.exists() and flag.read_text('utf8').strip()=='1'
 cfg=json.loads((base/'shop-passage.json').read_text('utf8'))
 out=base/'shop-passage-result.json';r=dict(status='passed',apply=APPLY,actors=[],cuts=[])
 AU=unreal.GeometryScript_AssetUtils;BO=unreal.GeometryScript_MeshBooleans;PR=unreal.GeometryScript_Primitives;QF=unreal.GeometryScript_MeshQueries
 want=set(cfg['actors']);acts=[a for a in SUB.get_all_level_actors() if a.get_actor_label() in want]
 zcut=cfg.get('slice_z',1260.)
 def tris(mesh,xf):
  segs=[]
  for s in range(mesh.get_num_sections(0)):
   v,t=unreal.ProceduralMeshLibrary.get_section_from_static_mesh(mesh,0,s)[:2]
   w=[xf.transform_location(p) for p in v]
   for i in range(0,len(t),3):
    P=[w[t[i]],w[t[i+1]],w[t[i+2]]];pts=[]
    for a,b in ((0,1),(1,2),(2,0)):
     za,zb=P[a].z-zcut,P[b].z-zcut
     if (za<0)!=(zb<0):
      k=za/(za-zb);pts.append([round(P[a].x+(P[b].x-P[a].x)*k),round(P[a].y+(P[b].y-P[a].y)*k)])
    if len(pts)==2:segs.append(pts)
  return segs
 for a in acts:
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh
   if not m:continue
   src=m.get_editor_property('complex_collision_mesh')
   row=dict(actor=a.get_actor_label(),component=c.get_name(),mesh=m.get_path_name(),collision=src.get_path_name() if src else None,
            profile=str(c.get_collision_profile_name()),enabled=str(c.get_collision_enabled()))
   try:row['walls']=tris(m,c.get_world_transform())
   except Exception:row['error']=traceback.format_exc()[-400:]
   r['actors'].append(row)
 out.write_text(json.dumps(r,indent=1),'utf8')
 g=cfg.get('grid')
 if g:
  x0,y0,x1,y1=g['box'];z=g.get('z',1290.);st=g.get('step',20.);rows=[]
  def hit(p,q):
   h=unreal.SystemLibrary.line_trace_single(world,p,q,Q,True,[],NONE,True)
   return bool(h and h.to_tuple()[0])
  y=y0
  while y<=y1:
   s='';x=x0
   while x<=x1:
    bx=hit(V(x,y,z),V(x+st,y,z));by=hit(V(x,y,z),V(x,y+st,z))
    s+='#' if bx and by else ('|' if bx else ('-' if by else '.'));x+=st
   rows.append(s);y+=st
  r['grid']=dict(box=g['box'],z=z,step=st,rows=rows)
 # rebuild: re-point the drawn mesh at its collision source so the cooked collision follows an edited source
 for a in [a for a in SUB.get_all_level_actors() if a.get_actor_label() in set(cfg.get('rebuild',[]))]:
  for c in a.get_components_by_class(unreal.StaticMeshComponent):
   m=c.static_mesh;src=m.get_editor_property('complex_collision_mesh') if m else None
   if src:
    m.set_editor_property('complex_collision_mesh',None);m.set_editor_property('complex_collision_mesh',src)
    if APPLY:unreal.EditorAssetLibrary.save_loaded_asset(m,False)
    c.recreate_physics_state() if hasattr(c,'recreate_physics_state') else None
 # what a trace meets: [x0,y0,z,x1,y1] -> actor, component, point
 r['traces']=[]
 for t in cfg.get('traces',[]):
  h=unreal.SystemLibrary.line_trace_single(world,V(t[0],t[1],t[2]),V(t[3],t[4],t[2]),Q,True,[],NONE,True)
  h=h.to_tuple() if h else (False,)
  r['traces'].append(dict(at=t,hit=bool(h[0]),actor=h[9].get_actor_label() if h[0] and h[9] else None,component=h[10].get_name() if h[0] and h[10] else None,point=[round(h[4].x),round(h[4].y),round(h[4].z)] if h[0] else None))
 if APPLY:
  def load(m):
   d=unreal.DynamicMesh();o=unreal.GeometryScriptCopyMeshFromAssetOptions();l=unreal.GeometryScriptMeshReadLOD()
   o.set_editor_property('apply_build_settings',False);o.set_editor_property('request_tangents',True)
   res=AU.copy_mesh_from_static_mesh(m,d,o,l);return res[0] if isinstance(res,tuple) else res
  def save(d,m):
   o=unreal.GeometryScriptCopyMeshToAssetOptions();l=unreal.GeometryScriptMeshWriteLOD()
   o.set_editor_property('enable_recompute_normals',False);o.set_editor_property('enable_recompute_tangents',False);o.set_editor_property('replace_materials',False);o.set_editor_property('emit_transaction',False);o.set_editor_property('defer_mesh_post_edit_change',False)
   AU.copy_mesh_to_static_mesh(d,m,o,l);assert unreal.EditorAssetLibrary.save_loaded_asset(m,False),m.get_path_name()
  for cut in cfg['cuts']:
   x0,y0,z0,x1,y1,z1=cut['box'];row=dict(name=cut['name'],box=cut['box'],meshes=[])
   for a in acts:
    if a.get_actor_label() not in cut.get('actors',cfg['actors']):continue
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
       tool=unreal.DynamicMesh();po=unreal.GeometryScriptPrimitiveOptions()
       ctr=V((bmin.x+bmax.x)/2,(bmin.y+bmax.y)/2,bmin.z)
       PR.append_box(tool,po,unreal.Transform(ctr,unreal.Rotator(0,0,0),V(1,1,1)),bmax.x-bmin.x,bmax.y-bmin.y,bmax.z-bmin.z,0,0,0,unreal.GeometryScriptPrimitiveOriginMode.BASE)
       bo=unreal.GeometryScriptMeshBooleanOptions();bo.set_editor_property('fill_holes',False)
       BO.apply_mesh_boolean(d,unreal.Transform(),tool,unreal.Transform(),unreal.GeometryScriptBooleanOperation.SUBTRACT,bo)
       n1=QF.get_num_triangle_i_ds(d);ent=dict(actor=a.get_actor_label(),key=key,mesh=mesh.get_path_name(),before=n0,after=n1)
       if n1!=n0:save(d,mesh);ent['saved']=True
       row['meshes'].append(ent)
      except Exception:row['meshes'].append(dict(actor=a.get_actor_label(),key=key,error=traceback.format_exc()[-500:]))
     if src:m.set_editor_property('complex_collision_mesh',None);m.set_editor_property('complex_collision_mesh',src);unreal.EditorAssetLibrary.save_loaded_asset(m,False)
   r['cuts'].append(row)
 out.write_text(json.dumps(r,indent=1),'utf8')
 return dict(status='passed',apply=APPLY,actors=len(r['actors']),cuts=len(r['cuts']))
]====]
