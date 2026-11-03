-- Places the StreetSocial game still lacks in UniversityCity (c-conquest 11-03, Docs/STREET_CITY_PLACES_INVENTORY_20261103.md):
--   lua Tools/street_city_motel_job.lua world_lover_spots_install Tools/street_city_lover_spots_payload.lua
--   vending    a drinks vending machine near each place whose activities use the `vending` anchor (park, aquarium,
--              dorms, cafeteria, library, school, playground, hotel, lodge, department)
--   eat-in     a window counter with three stools in the convenience store S06 (conveni seat / table)
--   lounges    sofa + TV on a low cabinet + game console in the D1 and D2 visitor lounges (dorm game dates)
--   shrine     a small shrine: torii, stone path, hokora, offering box and two stone lanterns (shrine torii / pray)
--   aquarium   the pet-shop clone S28 becomes a small aquarium: a 3.6 m tank wall with koi, a bench in front
--              (aquarium tank / bench; its vending machine goes outside S28, not at the park pond)
--   lodge      a shared sofa corner in the gallery outside the four motel pool suites (lodge lounge2 / seat)
-- Every item is placed by search, not by hand: candidate spots spiral out from a hint at 25 cm steps; a spot needs a
-- floor within 8 cm under its centre and four corners and no blocking geometry in the item's box (box sweep from 3 cm
-- above the floor). Indoor items prefer a wall behind them. Items keep 1.6 m off doors and entrances.
-- Re-running removes the previous LoverSpot_* actors first. Writes world-edge-v1/lover-spots-install-<time>.json
-- with {place, anchor, pos, yaw, actor} rows that Tools/build_street_city_places.lua turns into game anchors, and
-- world-edge-v1/lover-spots-views.json for the shop-survey capture.
return [====[
LS_OUT=ROOT/'output/street-social-city-production/world-edge-v1'
LS_DIR='/Game/UniversityCity/LoverSpotsV1'
def _ls_mat(name,col,rough=.5,metal=0.,emit=0.):
 path=LS_DIR+'/Materials/'+name
 m=EAL.load_asset(path) if EAL.does_asset_exist(path) else ATS.create_asset(name,LS_DIR+'/Materials',unreal.Material,unreal.MaterialFactoryNew())
 if EAL.get_metadata_tag(m,'LoverSpotsVersion')=='1':return m
 MEL.delete_all_material_expressions(m);n=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);n.set_editor_property('constant',unreal.LinearColor(*col,1));MEL.connect_material_property(n,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for prop,v in [(unreal.MaterialProperty.MP_ROUGHNESS,rough),(unreal.MaterialProperty.MP_METALLIC,metal)]:
  c=MEL.create_material_expression(m,unreal.MaterialExpressionConstant);c.set_editor_property('r',v);MEL.connect_material_property(c,'',prop)
 if emit:
  e=MEL.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);e.set_editor_property('constant',unreal.LinearColor(*[v*emit for v in col],1));MEL.connect_material_property(e,'',unreal.MaterialProperty.MP_EMISSIVE_COLOR)
 MEL.recompile_material(m);EAL.set_metadata_tag(m,'LoverSpotsVersion','1');assert EAL.save_loaded_asset(m,False);return m
def _ls_hit(world,a,b,ignore=[]):
 raw=unreal.SystemLibrary.line_trace_single(world,a,b,unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,ignore,unreal.DrawDebugTrace.NONE,True);h=raw.to_tuple() if raw else [False]
 return h if h[0] else None
def _ls_floor(world,x,y,z):
 h=_ls_hit(world,unreal.Vector(x,y,z+120),unreal.Vector(x,y,z-150));return h[4].z if h else None
def _ls_fits(world,c,yaw,w,d,h,z,tol=8):
 # floor under centre and corners, then an empty box from 3 cm above the floor
 a=math.radians(yaw);fx,fy=math.cos(a),math.sin(a);rx,ry=-fy,fx
 for u,v in [(0,0),(w/2,d/2),(-w/2,d/2),(w/2,-d/2),(-w/2,-d/2)]:
  q=_ls_floor(world,c.x+rx*u+fx*v,c.y+ry*u+fy*v,z)
  if q is None or abs(q-z)>tol:return False
 mid=unreal.Vector(c.x,c.y,z+3+h/2)
 hit=unreal.SystemLibrary.box_trace_single(world,mid,mid+unreal.Vector(0,0,1),unreal.Vector(d/2,w/2,h/2),unreal.Rotator(roll=0,pitch=0,yaw=yaw),unreal.TraceTypeQuery.TRACE_TYPE_QUERY1,True,[],unreal.DrawDebugTrace.NONE,True)
 t=hit.to_tuple() if hit else [False]
 return not t[0]
def _ls_wall_behind(world,c,yaw,d,z):
 a=math.radians(yaw);back=unreal.Vector(-math.cos(a),-math.sin(a),0);p=unreal.Vector(c.x,c.y,z+100)
 return _ls_hit(world,p,p+back*(d/2+40)) is not None
def _ls_search(world,hint,z,w,d,h,yaws,rmin=0,rmax=1200,avoid=[],wall=False,region=None,step=25,tol=8,follow=False):
 # follow: outdoors the ground slopes, so each candidate is tested at its own floor height instead of the hint's
 # spiral of 25 cm rings; first spot (optionally with a wall behind) wins, else the nearest free spot
 best=None
 for r in range(int(rmin),int(rmax)+1,step):
  n=max(1,int(2*math.pi*max(r,1)/step))
  for k in range(n):
   t=2*math.pi*k/n;c=unreal.Vector(hint.x+r*math.cos(t),hint.y+r*math.sin(t),z)
   if region and not(region[0][0]<=c.x<=region[1][0] and region[0][1]<=c.y<=region[1][1]):continue
   if any((c-unreal.Vector(p.x,p.y,z)).length()<160+max(w,d)/2 for p in avoid):continue
   cz=z
   if follow:
    g=_ls_hit(world,unreal.Vector(c.x,c.y,z+600),unreal.Vector(c.x,c.y,z-600))
    if g is None:continue
    cz=g[4].z
    c=unreal.Vector(c.x,c.y,cz)
   for yaw in yaws:
    if not _ls_fits(world,c,yaw,w,d,h,cz,tol):continue
    if wall and not _ls_wall_behind(world,c,yaw,d,cz):
     best=best or (c,yaw);continue
    return c,yaw
  if best and not wall:return best
 return best
def _ls_spawn(label,mesh,p,yaw,scale,mat=None,collide=True):
 a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,p,unreal.Rotator(roll=0,pitch=0,yaw=yaw));a.set_actor_label(label);a.set_folder_path('UniversityCity/LoverSpotsV1');a.tags=[unreal.Name('LoverSpot')]
 c=a.static_mesh_component;c.set_static_mesh(mesh)
 if mat:
  for i in range(c.get_num_materials()):c.set_material(i,mat)
 c.set_collision_profile_name('BlockAll' if collide else 'NoCollision');a.set_actor_scale3d(unreal.Vector(*scale));return a
def _ls_box(label,p,yaw,size,mat,collide=True):
 # engine cube is 100 cm, centred: size = (along yaw, across, height) in cm, p = bottom centre
 return _ls_spawn(label,EAL.load_asset('/Engine/BasicShapes/Cube'),unreal.Vector(p.x,p.y,p.z+size[2]/2),yaw,[size[0]/100,size[1]/100,size[2]/100],mat,collide)
def _ls_cyl(label,p,r,hgt,mat,collide=True):
 return _ls_spawn(label,EAL.load_asset('/Engine/BasicShapes/Cylinder'),unreal.Vector(p.x,p.y,p.z+hgt/2),0,[r/50,r/50,hgt/100],mat,collide)
def _ls_off(p,yaw,fwd,side=0,up=0):
 a=math.radians(yaw);return unreal.Vector(p.x+math.cos(a)*fwd-math.sin(a)*side,p.y+math.sin(a)*fwd+math.cos(a)*side,p.z+up)
def _ls_vending(i,c,yaw,M):
 # body 100 wide x 80 deep x 190 high, front (+yaw) panel lit, coin slot strip; yaw = facing direction
 lab='LoverSpot_Vending_%02d'%i
 _ls_box(lab+'_Body',c,yaw,(80,100,190),M['vend_body'])
 _ls_box(lab+'_Panel',_ls_off(c,yaw,40.5,0,95),yaw,(1.5,84,80),M['vend_panel'],False)
 _ls_box(lab+'_Buttons',_ls_off(c,yaw,40.5,0,70),yaw,(1.5,84,8),M['vend_button'],False)
 _ls_box(lab+'_Slot',_ls_off(c,yaw,40.5,0,15),yaw,(3,60,22),M['dark'],False)
 return lab
def motel_world_lover_spots_install():
 world=unreal.EditorLevelLibrary.get_editor_world();acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 b=LS_OUT/('UniversityCity-before-lover-spots-'+LOAD_SHA[:16]+'.umap')
 if not b.exists():shutil.copy2(MAPFILE,b)
 for a in list(acts.values()):
  if a.get_actor_label().startswith('LoverSpot_'):SUB.destroy_actor(a)
 M=dict(vend_body=_ls_mat('M_LS_VendBody',(.82,.12,.1),.35),vend_panel=_ls_mat('M_LS_VendPanel',(.85,.92,1.),.2,0.,3.),vend_button=_ls_mat('M_LS_VendButton',(.9,.75,.2),.3,0.,1.),dark=_ls_mat('M_LS_Dark',(.03,.03,.035),.4),
  wood=_ls_mat('M_LS_Wood',(.36,.22,.12),.55),counter=_ls_mat('M_LS_Counter',(.86,.84,.8),.4),steel=_ls_mat('M_LS_Steel',(.6,.6,.62),.3,1.),cushion=_ls_mat('M_LS_Cushion',(.75,.18,.2),.8),
  sofa=_ls_mat('M_LS_Sofa',(.32,.38,.55),.85),screen=_ls_mat('M_LS_Screen',(.2,.35,.6),.1,0.,1.5),vermilion=_ls_mat('M_LS_Vermilion',(.78,.12,.05),.45),roofblack=_ls_mat('M_LS_RoofBlack',(.05,.05,.05),.5),
  stone=_ls_mat('M_LS_Stone',(.55,.54,.5),.85),lamp=_ls_mat('M_LS_LanternLight',(1.,.8,.5),.5,0.,2.))
 P=json.loads((ROOT/'output/street-social-city-production/places-v1/places.json').read_text('utf8'));gp={g['id']:g for g in P['game_places']}
 items=[];views=[];skipped=[];V=lambda l:unreal.Vector(*l)
 # 1. vending machines: outside each place's door (or beside its main anchor outdoors), facing out, off the doorway
 vend_for=['park','aquarium','girls_dorm','boys_dorm','cafeteria','library','school','playground','hotel','lodge','department']
 # the aquarium is the converted pet shop S28 (c-conquest: an indoor aquarium, not the park koi pond)
 pl={p['id']:p for p in P['places']};aqua_door=pl.get('s28-f02',{}).get('door')
 for i,pid in enumerate(vend_for):
  g=gp.get(pid);door=aqua_door if pid=='aquarium' else (g or {}).get('door')
  if not door:skipped.append(dict(place=pid,reason='no door'));continue
  d=V(door);z=_ls_floor(world,d.x,d.y,d.z)
  if z is None:
   # door sits over water or a drop (the lodge door is at a pool suite): start from the place's first anchor instead
   an=sorted((g or {}).get('anchors') or [],key=lambda a:a['name'].startswith('bed'))  # lounge / seat before a suite bed
   for a in an:
    d=V(a['pos']);z=_ls_floor(world,d.x,d.y,d.z)
    if z is not None:break
  if z is None:skipped.append(dict(place=pid,reason='no floor at door or anchors'));continue
  got=_ls_search(world,d,z,100,80,190,[0,90,180,270],rmin=200,rmax=1000,avoid=[d],wall=True)
  # outdoors (park, playground) the lawn slopes: follow the ground, look further, allow 15 cm across the footprint
  if not got:got=_ls_search(world,d,z,100,80,190,[0,90,180,270],rmin=200,rmax=2500,avoid=[d],wall=True,step=50,tol=15,follow=True)
  if not got:skipped.append(dict(place=pid,reason='no free spot within 25 m'));continue
  c,yaw=got;lab=_ls_vending(i,c,yaw,M);front=_ls_off(c,yaw,110)
  items.append(dict(place=pid,anchor='vending',pos=num(front),yaw=yaw-90,actor=lab))
  views.append(dict(id='LS-vend-'+pid,eye=num(_ls_off(c,yaw,420,120,160)),target=num(_ls_off(c,yaw,0,0,100)),fov=70,hour=15))
 # 2. convenience store eat-in counter (S06): 240 x 50 counter at 105 cm, three stools 45 cm in front
 g=gp.get('conveni')
 if g:
  lo,hi=g['rooms'][0]['min'],g['rooms'][0]['max'];d=V(g['door']);z=lo[2]
  ctr=V([(lo[0]+hi[0])/2,(lo[1]+hi[1])/2,z])
  # full 3-stool counter inside, then a 2-stool one inside, then the 3-stool one on the pavement outside the shop front
  span=240;got=_ls_search(world,ctr,z,240,110,110,[0,90,180,270],rmax=900,avoid=[d],wall=True,region=([lo[0]+50,lo[1]+50],[hi[0]-50,hi[1]-50]))
  if not got:span=160;got=_ls_search(world,ctr,z,160,100,110,[0,90,180,270],rmax=900,avoid=[d],wall=True,step=15,region=([lo[0]+40,lo[1]+40],[hi[0]-40,hi[1]-40]))
  if not got:span=240;got=_ls_search(world,d,z,240,110,110,[0,90,180,270],rmin=150,rmax=800,avoid=[d],wall=True,follow=True,tol=10)
  if got:
   c,yaw=got;back=_ls_off(c,yaw,-30)
   _ls_box('LoverSpot_EatIn_Counter',_ls_off(back,yaw,0,0,100),yaw,(50,span,5),M['counter'])
   for k,s in enumerate((-80,0,80) if span>200 else (-40,40)):
    _ls_box('LoverSpot_EatIn_Leg_%d'%k,back,yaw,(6,6,100),M['steel'])
    st=_ls_off(c,yaw,25,s);_ls_cyl('LoverSpot_EatIn_StoolPost_%d'%k,st,4,68,M['steel']);_ls_cyl('LoverSpot_EatIn_StoolSeat_%d'%k,_ls_off(st,yaw,0,0,68),18,7,M['cushion'])
   items.append(dict(place='conveni',anchor='seat',pos=num(_ls_off(c,yaw,25,-40)),yaw=yaw+180-90,actor='LoverSpot_EatIn_StoolSeat_0'))
   items.append(dict(place='conveni',anchor='table',pos=num(_ls_off(c,yaw,25,0)),yaw=yaw+180-90,actor='LoverSpot_EatIn_Counter'))
   views.append(dict(id='LS-conveni-eatin',eye=num(_ls_off(c,yaw,320,60,160)),target=num(_ls_off(c,yaw,-20,0,90)),fov=75,hour=15))
  else:skipped.append(dict(place='conveni',reason='no free 2.4 x 1.1 or 1.6 x 1.0 m spot in S06-0101 nor outside its door'))
 # 3. dorm visitor lounges: sofa (210 x 95) facing a TV cabinet 260 cm away, TV and a console on the cabinet
 for pid in ('girls_dorm','boys_dorm'):
  g=gp.get(pid);la=next((a for a in (g or {}).get('anchors',[]) if a['name']=='lounge'),None)
  if not la:skipped.append(dict(place=pid,reason='no lounge room'));continue
  ctr=V(la['pos']);z=_ls_floor(world,ctr.x,ctr.y,ctr.z) or ctr.z;tag='LoverSpot_Lounge_'+pid
  got=None
  for c0 in [ctr]:
   for r in range(0,601,25):
    n=max(1,int(2*math.pi*max(r,1)/25))
    for k in range(n):
     t=2*math.pi*k/n;c=unreal.Vector(c0.x+r*math.cos(t),c0.y+r*math.sin(t),z)
     for yaw in (0,90,180,270):
      # sofa at c facing yaw; cabinet 260 cm ahead; the gap between must be free too
      if _ls_fits(world,c,yaw,210,95,90,z) and _ls_fits(world,_ls_off(c,yaw,260),yaw,160,45,60,z) and _ls_fits(world,_ls_off(c,yaw,130),yaw,160,150,60,z):
       got=(c,yaw);break
     if got:break
    if got:break
  if not got:skipped.append(dict(place=pid,reason='no free 2.1 x 4 m lounge spot'));continue
  c,yaw=got
  _ls_box(tag+'_SofaBase',_ls_off(c,yaw,0),yaw,(95,210,42),M['sofa'])
  _ls_box(tag+'_SofaBack',_ls_off(c,yaw,-37),yaw,(22,210,85),M['sofa'])
  for s in (-95,95):_ls_box(tag+'_SofaArm%+d'%s,_ls_off(c,yaw,0,s),yaw,(95,20,62),M['sofa'])
  cab=_ls_off(c,yaw,260)
  _ls_box(tag+'_Cabinet',cab,yaw,(45,160,50),M['wood'])
  _ls_box(tag+'_TVStand',_ls_off(cab,yaw,0,0,50),yaw,(20,30,6),M['dark'])
  _ls_box(tag+'_TV',_ls_off(cab,yaw,0,0,56),yaw,(6,130,75),M['dark'])
  _ls_box(tag+'_TVScreen',_ls_off(cab,yaw,-3.2,0,60),yaw,(.6,122,67),M['screen'],False)
  _ls_box(tag+'_Console',_ls_off(cab,yaw,-8,45,50),yaw,(20,30,6),M['dark'])
  _ls_box(tag+'_Pad',_ls_off(c,yaw,10,30,42),yaw,(10,15,4),M['dark'],False)
  items.append(dict(place=pid,anchor='lounge',pos=num(_ls_off(c,yaw,10,-45)),yaw=yaw-90,actor=tag+'_SofaBase'))
  # c-conquest 11-03: a separate anchor for "play video games together" on the same sofa, facing the TV
  items.append(dict(place=pid,anchor='game',pos=num(_ls_off(c,yaw,10,-45)),yaw=yaw-90,actor=tag+'_TV'))
  views.append(dict(id='LS-'+pid+'-lounge',eye=num(_ls_off(c,yaw,-60,-260,170)),target=num(_ls_off(c,yaw,150,0,60)),fov=80,hour=20))
 # 4. shrine: 5 x 9 m flat lawn near the park, torii at the path start, hokora at the end
 g=gp.get('park');hint=V(g['door']) if g else None
 if hint:
  z=_ls_floor(world,hint.x,hint.y,hint.z) or hint.z
  got=_ls_search(world,hint,z,500,900,420,[0,90,180,270],rmin=1500,rmax=6000,step=100,follow=True,tol=20)
  if not got:got=_ls_search(world,hint,z,400,800,420,[0,90,180,270],rmin=6000,rmax=15000,step=150,follow=True,tol=25)
  if got:
   c,yaw=got;st=_ls_off(c,yaw,-400)  # path runs along +yaw from the torii (st) to the hokora
   for s in (-170,170):_ls_cyl('LoverSpot_Shrine_ToriiPost%+d'%s,_ls_off(st,yaw,0,s),17,350,M['vermilion'])
   _ls_box('LoverSpot_Shrine_ToriiNuki',_ls_off(st,yaw,0,0,270),yaw,(18,420,20),M['vermilion'])
   _ls_box('LoverSpot_Shrine_ToriiKasagi',_ls_off(st,yaw,0,0,340),yaw,(30,500,24),M['vermilion'])
   _ls_box('LoverSpot_Shrine_ToriiCap',_ls_off(st,yaw,0,0,364),yaw,(34,520,10),M['roofblack'])
   for k in range(6):_ls_box('LoverSpot_Shrine_Path%d'%k,_ls_off(st,yaw,100+k*110,0,0),yaw,(90,120,4),M['stone'],False)
   ho=_ls_off(c,yaw,330)
   _ls_box('LoverSpot_Shrine_HokoraBase',ho,yaw,(120,140,40),M['stone'])
   _ls_box('LoverSpot_Shrine_Hokora',_ls_off(ho,yaw,0,0,40),yaw,(90,110,110),M['wood'])
   _ls_box('LoverSpot_Shrine_HokoraRoof',_ls_off(ho,yaw,0,0,150),yaw,(150,170,14),M['roofblack'])
   _ls_box('LoverSpot_Shrine_OfferingBox',_ls_off(ho,yaw,-110,0,0),yaw,(40,70,55),M['wood'])
   for s in (-150,150):
    lp=_ls_off(ho,yaw,-150,s);_ls_cyl('LoverSpot_Shrine_LanternPost%+d'%s,lp,14,110,M['stone']);_ls_box('LoverSpot_Shrine_LanternLight%+d'%s,_ls_off(lp,yaw,0,0,110),yaw,(34,34,30),M['lamp'],False);_ls_box('LoverSpot_Shrine_LanternCap%+d'%s,_ls_off(lp,yaw,0,0,140),yaw,(50,50,10),M['stone'])
   items.append(dict(place='shrine',anchor='torii',pos=num(_ls_off(st,yaw,-150)),yaw=yaw-90,actor='LoverSpot_Shrine_ToriiKasagi'))
   items.append(dict(place='shrine',anchor='pray',pos=num(_ls_off(ho,yaw,-170)),yaw=yaw-90,actor='LoverSpot_Shrine_OfferingBox'))
   views.append(dict(id='LS-shrine',eye=num(_ls_off(st,yaw,-700,150,170)),target=num(_ls_off(c,yaw,0,0,150)),fov=75,hour=15))
  else:skipped.append(dict(place='shrine',reason='no 5 x 9 m lawn (20 cm slope) 15-60 m nor 4 x 8 m 60-150 m from the park'))
 # 5. aquarium in S28 (毛孩選物, a pet-shop clone): a 3.6 m tank wall with koi against a wall, a bench 2.2 m in front
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()};sh=acts.get('S28_F01')
 if sh and aqua_door:
  o,e=sh.get_actor_bounds(False);z=1200.;lo=[o.x-e.x+100,o.y-e.y+100];hi=[o.x+e.x-100,o.y+e.y-100]
  got=_ls_search(world,unreal.Vector(o.x,o.y,z),z,380,330,170,[0,90,180,270],rmax=900,avoid=[V(aqua_door)],wall=True,region=(lo,hi))
  if got:
   c,yaw=got;tk=_ls_off(c,yaw,-130)   # tank at the back (wall side), bench toward the front
   water=_ls_mat('M_LS_AquaWater',(.1,.45,.6),.05,0.,.8);glass=_ls_mat('M_LS_AquaFrame',(.08,.08,.09),.3,.6)
   _ls_box('LoverSpot_Aqua_Base',tk,yaw,(65,380,50),M['wood'])
   # opaque constant materials only: a lit blue back panel with the fish in front of it, gravel floor, dark frame
   _ls_box('LoverSpot_Aqua_Water',_ls_off(tk,yaw,-25,0,50),yaw,(8,360,115),water,True)
   _ls_box('LoverSpot_Aqua_Gravel',_ls_off(tk,yaw,0,0,50),yaw,(55,360,6),M['stone'],False)
   for s in (-185,185):_ls_box('LoverSpot_Aqua_Side%+d'%s,_ls_off(tk,yaw,0,s,50),yaw,(65,10,115),glass)
   _ls_box('LoverSpot_Aqua_Top',_ls_off(tk,yaw,0,0,165),yaw,(65,380,8),glass)
   koi=next((a.static_mesh_component.static_mesh for a in acts.values() if a.get_actor_label().startswith('Activity_ACTSPACE-06') and isinstance(a,unreal.StaticMeshActor) and a.static_mesh_component.static_mesh and 'koi' in a.static_mesh_component.static_mesh.get_name()),None)
   if koi:
    for k,(s,u) in enumerate([(-120,35),(-60,80),(0,55),(60,95),(120,40),(30,70)]):
     _ls_spawn('LoverSpot_Aqua_Fish_%d'%k,koi,_ls_off(tk,yaw,0,s,50+u),yaw+(90 if k%2 else -90),[.6,.6,.6],None,False)
   bench=_ls_off(c,yaw,90)
   _ls_box('LoverSpot_Aqua_Bench',bench,yaw+180,(45,180,45),M['wood'])
   items.append(dict(place='aquarium',anchor='tank',pos=num(_ls_off(tk,yaw,90)),yaw=yaw+180-90,actor='LoverSpot_Aqua_Water'))
   items.append(dict(place='aquarium',anchor='bench',pos=num(bench),yaw=yaw+180-90,actor='LoverSpot_Aqua_Bench'))
   items.append(dict(place='aquarium',anchor='door',pos=aqua_door,yaw=0,actor='S28_F01',building='S28',rooms=[dict(min=num(o-e),max=num(o+e))]))
   views.append(dict(id='LS-aquarium',eye=num(_ls_off(c,yaw,260,80,160)),target=num(_ls_off(tk,yaw,0,0,100)),fov=75,hour=15))
  else:skipped.append(dict(place='aquarium',reason='no free 3.8 x 3.3 m spot in S28'))
 # 6. lodge lounge: a shared sitting corner in the gallery outside the four pool suites (lounge2 = sofa, seat = chair)
 suites=[p for p in P['places'] if p['kind']=='motel_pool_suite']
 if suites:
  ds=[V(p['door']) for p in suites];hint=unreal.Vector(sum(d.x for d in ds)/len(ds)-250,sum(d.y for d in ds)/len(ds),0)
  z=_ls_floor(world,hint.x,hint.y,ds[0].z) or ds[0].z-165
  boxes=[(p['room']['center'],p['room']['size']) for p in suites]
  def outside(c):return all(abs(c.x-b[0][0])>b[1][1]/2+60 or abs(c.y-b[0][1])>b[1][0]/2+60 for b in boxes) and all(abs(c.x-b[0][0])>b[1][0]/2+60 or abs(c.y-b[0][1])>b[1][1]/2+60 for b in boxes)
  got=None
  for r in range(0,1601,25):
   n=max(1,int(2*math.pi*max(r,1)/25))
   for k in range(n):
    t=2*math.pi*k/n;c=unreal.Vector(hint.x+r*math.cos(t),hint.y+r*math.sin(t),z)
    if not outside(c) or any((c-unreal.Vector(d.x,d.y,z)).length()<220 for d in ds):continue
    for yaw in (0,90,180,270):
     if _ls_fits(world,c,yaw,210,95,90,z) and _ls_fits(world,_ls_off(c,yaw,110),yaw,90,60,50,z) and _ls_wall_behind(world,c,yaw,95,z):got=(c,yaw);break
    if got:break
   if got:break
  if got:
   c,yaw=got;tag='LoverSpot_LodgeLounge'
   _ls_box(tag+'_SofaBase',c,yaw,(95,210,42),M['cushion'])
   _ls_box(tag+'_SofaBack',_ls_off(c,yaw,-37),yaw,(22,210,85),M['cushion'])
   for s in (-95,95):_ls_box(tag+'_SofaArm%+d'%s,_ls_off(c,yaw,0,s),yaw,(95,20,62),M['cushion'])
   _ls_box(tag+'_Table',_ls_off(c,yaw,110),yaw,(60,90,42),M['wood'])
   items.append(dict(place='lodge',anchor='lounge2',pos=num(_ls_off(c,yaw,10,-45)),yaw=yaw-90,actor=tag+'_SofaBase'))
   items.append(dict(place='lodge',anchor='seat',pos=num(_ls_off(c,yaw,10,45)),yaw=yaw-90,actor=tag+'_SofaBase'))
   views.append(dict(id='LS-lodge-lounge',eye=num(_ls_off(c,yaw,380,100,160)),target=num(_ls_off(c,yaw,0,0,60)),fov=75,hour=15))
  else:skipped.append(dict(place='lodge',reason='no free sofa corner within 16 m of the pool suite doors'))
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (LS_OUT/'lover-spots-views.json').write_text(json.dumps(views,indent=1),'utf8')
 (LS_OUT/('lover-spots-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),items=items,skipped=skipped),ensure_ascii=False,indent=1),'utf8')
]====]
