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
--   counters   S06 checkout (conveni counter), S20 counter + draw screen (lottery counter / buy / screen)
--   livehouse  stage, speakers, bar and standing room in the music shop S96 (new place livehouse)
--   karaoke    up to three closed booths with sofa and screen in the record shop S48 (new place karaoke)
--   lots       eight flat empty roadside lots for the company game, from world-edge-v1/lot-candidates.json
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
 # 7-11 (c-conquest 11-03 game-needs list C1/C2/C7/C8/C9): shop counters, a live house, karaoke booths, company lots
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 def shopbox(b):
  sh=acts.get(b+'_F01')
  if not sh:return None
  o,e=sh.get_actor_bounds(False);return o,e,([o.x-e.x+80,o.y-e.y+80],[o.x+e.x-80,o.y+e.y-80])
 def shopdoor(b):
  ds=[p['door'] for p in P['places'] if p.get('building')==b and p.get('door') and abs(p['door'][2]-1200)<60]
  return V(ds[0]) if ds else None
 def counter(tag,b,w,M,scr=False):
  # counter w x 60 x 100 at the front of a w x 150 spot with a wall behind; the clerk stands between counter and wall
  sb=shopbox(b);d=shopdoor(b)
  if not sb:return None
  o,e,reg=sb;z=1200.
  got=_ls_search(world,unreal.Vector(o.x,o.y,z),z,w,150,120,[0,90,180,270],rmax=1200,avoid=[d] if d else [],wall=True,region=reg)
  if not got:return None
  c,yaw=got;f=_ls_off(c,yaw,45)
  _ls_box(tag+'_Counter',f,yaw,(60,w,100),M['counter']);_ls_box(tag+'_CounterTop',_ls_off(f,yaw,0,0,100),yaw,(66,w+6,4),M['wood'])
  _ls_box(tag+'_Register',_ls_off(f,yaw,-5,w/2-35,104),yaw,(35,40,25),M['dark'])
  return c,yaw,f
 # 7. convenience store S06: a checkout counter on the ground floor (job conveni_clerk: counter)
 got=counter('LoverSpot_ConveniCheckout','S06',200,M)
 if got:
  c,yaw,f=got;items.append(dict(place='conveni',anchor='counter',pos=num(_ls_off(c,yaw,-35)),yaw=yaw-90,actor='LoverSpot_ConveniCheckout_Counter'))
  views.append(dict(id='LS-conveni-checkout',eye=num(_ls_off(f,yaw,380,90,170)),target=num(_ls_off(f,yaw,0,0,90)),fov=75,hour=15))
 else:skipped.append(dict(place='conveni',reason='no 2 x 1.5 m counter spot against a wall in S06_F01'))
 # 8. lottery shop S20: counter (clerk / buyer) and a draw screen on a wall (lottery counter / buy / screen)
 got=counter('LoverSpot_Lottery','S20',160,M)
 if got:
  c,yaw,f=got;items.append(dict(place='lottery',anchor='counter',pos=num(_ls_off(c,yaw,-35)),yaw=yaw-90,actor='LoverSpot_Lottery_Counter'))
  items.append(dict(place='lottery',anchor='buy',pos=num(_ls_off(f,yaw,75)),yaw=yaw+180-90,actor='LoverSpot_Lottery_Counter'))
  views.append(dict(id='LS-lottery-counter',eye=num(_ls_off(f,yaw,380,-90,170)),target=num(_ls_off(f,yaw,0,0,90)),fov=75,hour=15))
  sb=shopbox('S20');o,e,reg=sb
  sg=_ls_search(world,_ls_off(f,yaw,200),1200.,200,40,240,[0,90,180,270],rmax=900,avoid=[f,shopdoor('S20') or f],wall=True,region=reg,step=20)
  if sg:
   s,sy=sg;_ls_box('LoverSpot_Lottery_Screen',_ls_off(s,sy,-12,0,140),sy,(6,170,95),M['dark']);_ls_box('LoverSpot_Lottery_ScreenGlow',_ls_off(s,sy,-8.5,0,145),sy,(.6,160,85),M['screen'],False)
   items.append(dict(place='lottery',anchor='screen',pos=num(_ls_off(s,sy,230)),yaw=sy+180-90,actor='LoverSpot_Lottery_Screen'))
  else:skipped.append(dict(place='lottery',reason='no free wall for the draw screen in S20_F01'))
 else:skipped.append(dict(place='lottery',reason='no 1.6 x 1.5 m counter spot against a wall in S20_F01'))
 # 9. live house in the music shop S96 回聲音樂店: a 4 x 2.5 m stage against a wall, speakers, a bar, standing room
 sb=shopbox('S96');d=shopdoor('S96')
 if sb and d:
  o,e,reg=sb;z=1200.
  got=_ls_search(world,unreal.Vector(o.x,o.y,z),z,420,560,250,[0,90,180,270],rmax=1200,avoid=[d],wall=True,region=reg,step=25)
  if got:
   c,yaw=got;st=_ls_off(c,yaw,-150);tag='LoverSpot_LiveHouse'
   _ls_box(tag+'_Stage',st,yaw,(250,400,40),M['dark'])
   for s in (-170,170):_ls_box(tag+'_Speaker%+d'%s,_ls_off(st,yaw,60,s,40),yaw,(45,50,110),M['dark'])
   _ls_cyl(tag+'_MicStand',_ls_off(st,yaw,50,0,40),2,150,M['steel'])
   items.append(dict(place='livehouse',anchor='door',pos=num(d),yaw=0,actor='S96_F01',building='S96',name='Live House（S96 回聲音樂店）',rooms=[dict(min=num(o-e),max=num(o+e))]))
   items.append(dict(place='livehouse',anchor='stage',pos=num(_ls_off(st,yaw,40,0,40)),yaw=yaw-90,actor=tag+'_Stage'))
   for k,(fw,sd) in enumerate([(230,-90),(230,90),(320,-150),(320,150)]):
    items.append(dict(place='livehouse',anchor='watch' if k==0 else 'watch%d'%(k+1),pos=num(_ls_off(st,yaw,fw,sd)),yaw=yaw+180-90,actor=tag+'_Stage'))
   views.append(dict(id='LS-livehouse',eye=num(_ls_off(st,yaw,520,0,180)),target=num(_ls_off(st,yaw,0,0,100)),fov=80,hour=20))
   bar=_ls_search(world,_ls_off(c,yaw,250),z,200,150,120,[0,90,180,270],rmax=1000,avoid=[d,c],wall=True,region=reg)
   if bar:
    bc,by=bar;bf=_ls_off(bc,by,45)
    _ls_box(tag+'_Bar',bf,by,(60,200,105),M['wood']);_ls_box(tag+'_BarTop',_ls_off(bf,by,0,0,105),by,(66,206,4),M['counter'])
    items.append(dict(place='livehouse',anchor='counter',pos=num(_ls_off(bc,by,-35)),yaw=by-90,actor=tag+'_Bar'))
    items.append(dict(place='livehouse',anchor='bar',pos=num(_ls_off(bf,by,70)),yaw=by+180-90,actor=tag+'_Bar'))
   else:skipped.append(dict(place='livehouse',reason='no bar spot in S96_F01'))
  else:skipped.append(dict(place='livehouse',reason='no 4.2 x 5.6 m stage + audience spot in S96_F01'))
 else:skipped.append(dict(place='livehouse',reason='S96_F01 or its door not found'))
 # 10. karaoke booths in S48 唱片小室: up to three closed 3.2 x 2.6 m rooms (walls 2.5 m, a door gap), sofa + screen
 sb=shopbox('S48');d=shopdoor('S48')
 if sb and d:
  o,e,reg=sb;z=1200.;tag='LoverSpot_KTV';booths=[]
  items.append(dict(place='karaoke',anchor='door',pos=num(d),yaw=0,actor='S48_F01',building='S48',name='KTV（S48 唱片小室）',rooms=[dict(min=num(o-e),max=num(o+e))]))
  for k in range(3):
   got=_ls_search(world,unreal.Vector(o.x,o.y,z),z,320,260,250,[0,90,180,270],rmax=1200,avoid=[d]+booths,wall=False,region=reg,step=25)
   if not got:break
   c,yaw=got;booths.append(c);t=tag+'_%d'%(k+1)
   # walls: back (behind the sofa), two sides, front with a 90 cm door gap on the right
   _ls_box(t+'_WallBack',_ls_off(c,yaw,-125),yaw,(10,320,250),M['sofa'])
   for s in (-155,155):_ls_box(t+'_WallSide%+d'%s,_ls_off(c,yaw,0,s),yaw,(260,10,250),M['sofa'])
   _ls_box(t+'_WallFront',_ls_off(c,yaw,125,-45),yaw,(10,230,250),M['sofa'])
   _ls_box(t+'_SofaBase',_ls_off(c,yaw,-75),yaw,(80,220,42),M['cushion']);_ls_box(t+'_SofaBack',_ls_off(c,yaw,-108),yaw,(16,220,80),M['cushion'])
   _ls_box(t+'_Table',_ls_off(c,yaw,10),yaw,(50,100,40),M['wood'])
   _ls_box(t+'_Screen',_ls_off(c,yaw,116,-60,110),yaw,(4,130,75),M['dark']);_ls_box(t+'_ScreenGlow',_ls_off(c,yaw,113.5,-60,113),yaw,(.6,122,67),M['screen'],False)
   n='' if k==0 else str(k+1)
   items.append(dict(place='karaoke',anchor='seat'+n,pos=num(_ls_off(c,yaw,-70,-40)),yaw=yaw-90,actor=t+'_SofaBase'))
   items.append(dict(place='karaoke',anchor='screen'+n,pos=num(_ls_off(c,yaw,-70,40)),yaw=yaw-90,actor=t+'_Screen'))
   views.append(dict(id='LS-ktv-%d'%(k+1),eye=num(_ls_off(c,yaw,60,100,200)),target=num(_ls_off(c,yaw,-90,0,60)),fov=90,hour=20))
  if not booths:skipped.append(dict(place='karaoke',reason='no free 3.2 x 2.6 m booth spot in S48_F01'))
 else:skipped.append(dict(place='karaoke',reason='S48_F01 or its door not found'))
 # 11. company lots: the first eight raster candidates (Tools/find_street_city_lots.lua) that are flat (40 cm) and empty
 lots=[];lc=ROOT/'output/street-social-city-production/world-edge-v1/lot-candidates.json'
 for cand in (json.loads(lc.read_text('utf8'))['candidates'] if lc.exists() else []):
  if len(lots)>=8:break
  x,y=cand['center'];g=_ls_hit(world,unreal.Vector(x,y,8000),unreal.Vector(x,y,-2000))
  if g is None:continue
  yaw=cand['yaw'];sx,sy=cand['size'];dep,wid=(sx,sy) if yaw in (0,180) else (sy,sx)
  c=unreal.Vector(x,y,g[4].z)
  if not _ls_fits(world,c,yaw,wid-100,dep-100,300,c.z,40):continue
  lots.append(dict(id='lot_%d'%(len(lots)+1),center=num(c),size_cm=[wid,dep],yaw=yaw,road_side='front (+yaw)'))
  views.append(dict(id='LS-'+lots[-1]['id'],eye=num(_ls_off(c,yaw,dep/2+900,0,700)),target=num(c),fov=75,hour=15))
 if len(lots)<8:skipped.append(dict(place='lots',reason='only %d flat empty roadside lots among the candidates'%len(lots)))
 # 12-14 (c-conquest 11-03 C12-C14): gynaecology clinic, cosmetic clinic, hair salon
 silver=EAL.load_asset('/Game/UniversityCity/ImmersionV1/Mirrors/M_SilverMirror')
 def mirror(tag,p,yaw,w,h):
  # wall mirror, bottom centre p on the wall face, looking along yaw; reflection tagged like the bed mirrors so the
  # walker's nearest-two policy switches it
  n=unreal.Vector(math.cos(math.radians(yaw)),math.sin(math.radians(yaw)),0);t=unreal.Vector(-n.y,n.x,0);mid=unreal.Vector(p.x,p.y,p.z+h/2)
  _ls_box(tag+'_Frame',_ls_off(p,yaw,.75),yaw,(1.5,w+8,h+8),M['dark'])
  g=_ls_box(tag+'_Glass',_ls_off(p,yaw,2.25,0,4),yaw,(1.5,w,h),silver or M['steel']);g.static_mesh_component.set_editor_property('cast_shadow',False)
  a=SUB.spawn_actor_from_class(unreal.PlanarReflection,mid+n*3.1,unreal.MathLibrary.make_rotation_from_axes(t,unreal.MathLibrary.cross_vector_vector(n,t),n));a.set_actor_label(tag+'_Reflection')
  a.tags=[unreal.Name('LoverSpot'),unreal.Name('ImmersionLargeMirror')];a.set_folder_path('UniversityCity/LoverSpotsV1');a.set_actor_scale3d(unreal.Vector(w/4000,h/4000,1));c=a.get_components_by_class(unreal.PlanarReflectionComponent)[0]
  for key,value in dict(screen_percentage=75,normal_distortion_strength=0.,prefilter_roughness=0.,distance_from_plane_fadeout_start=5.,distance_from_plane_fadeout_end=15.,show_preview_plane=False,max_view_distance_override=2200.).items():c.set_editor_property(key,value)
  c.set_visibility(False)
  for m in a.get_components_by_class(unreal.StaticMeshComponent):m.set_visibility(False);m.set_hidden_in_game(True);m.set_collision_profile_name('NoCollision')
 def wd(c,yaw):
  # distance from c back to the wall behind it (measured 120 cm up), so wall items sit on the wall
  a=math.radians(yaw);p=unreal.Vector(c.x,c.y,c.z+120);h=_ls_hit(world,p,p-unreal.Vector(math.cos(a),math.sin(a),0)*300)
  return (h[4]-p).length() if h else None
 def bench(tag,c,yaw,place,first,n=2):
  # waiting bench 200 x 50 x 45 with a back; n seat anchors along it, people face yaw
  _ls_box(tag+'_Seat',c,yaw,(50,200,45),M['sofa']);_ls_box(tag+'_Back',_ls_off(c,yaw,-22,0,45),yaw,(8,200,45),M['sofa'])
  for k in range(n):items.append(dict(place=place,anchor=first if k==0 else first+str(k+1),pos=num(_ls_off(c,yaw,10,-50+100*k/(max(n-1,1)))),yaw=yaw-90,actor=tag+'_Seat'))
 def spot(c0,w,d,h,reg,avoid,wall=True,step=25):
  return _ls_search(world,c0,1200.,w,d,h,[0,90,180,270],rmax=1500,avoid=avoid,wall=wall,region=reg,step=step)
 def booth(t,c,yaw,w,d,M):
  # 2.5 m partition walls round a w x d room open on the front-right (door gap 90 cm)
  _ls_box(t+'_WallBack',_ls_off(c,yaw,-d/2),yaw,(10,w,250),M['counter'])
  for s in (-w/2,w/2):_ls_box(t+'_WallSide%+d'%s,_ls_off(c,yaw,0,s),yaw,(d,10,250),M['counter'])
  _ls_box(t+'_WallFront',_ls_off(c,yaw,d/2,-45),yaw,(10,w-90,250),M['counter'])
 white=_ls_mat('M_LS_ClinicWhite',(.92,.94,.95),.5);mint=_ls_mat('M_LS_ClinicMint',(.55,.8,.75),.6)
 # 12. gynaecology clinic in the CV community clinic wing (CV-0101..0104 already hold medical beds and chairs; the
 #     builder takes doctor / bed_op / rest from them): a reception counter and a waiting bench in CV-0101
 pr=json.loads((ROOT/'output/street-social-city-production/places-v1/props.json').read_text('utf8'));ar={a['id']:a for a in pr['areas']}
 r=ar.get('cv-0101')
 if r:
  reg=([r['min'][0]+40,r['min'][1]+40],[r['max'][0]-40,r['max'][1]-40]);d=V(r['door']);c0=unreal.Vector((r['min'][0]+r['max'][0])/2,(r['min'][1]+r['max'][1])/2,1200.)
  got=spot(c0,180,150,120,reg,[d])
  if got:
   c,yaw=got;f=_ls_off(c,yaw,45);_ls_box('LoverSpot_Gyn_Counter',f,yaw,(60,180,100),white);_ls_box('LoverSpot_Gyn_CounterTop',_ls_off(f,yaw,0,0,100),yaw,(66,186,4),mint)
   items.append(dict(place='clinic_gyn',anchor='counter',pos=num(_ls_off(c,yaw,-35)),yaw=yaw-90,actor='LoverSpot_Gyn_Counter'))
   b=spot(c0,210,80,100,reg,[d,c])
   if b:bench('LoverSpot_Gyn_Bench',b[0],b[1],'clinic_gyn','seat',3)
   else:skipped.append(dict(place='clinic_gyn',reason='no waiting bench spot in CV-0101'))
   views.append(dict(id='LS-clinic-gyn',eye=num(_ls_off(f,yaw,420,120,170)),target=num(_ls_off(f,yaw,0,0,90)),fov=80,hour=11))
  else:skipped.append(dict(place='clinic_gyn',reason='no reception counter spot in CV-0101'))
 else:skipped.append(dict(place='clinic_gyn',reason='cv-0101 not in props.json areas'))
 # 13. cosmetic clinic in the drugstore S82 南苑藥妝 (ground floor is nearly empty): counter, consult table with a face
 #     sample screen, an operating booth with a bed and lamp, a recovery bed, a waiting bench and a large mirror
 sb=shopbox('S82');d=shopdoor('S82')
 if sb and d:
  o,e,reg=sb;c0=unreal.Vector(o.x,o.y,1200.);used=[d];t='LoverSpot_Beauty'
  items.append(dict(place='clinic_beauty',anchor='door',pos=num(d),yaw=0,actor='S82_F01',building='S82',name='醫美診所（S82 改建）',rooms=[dict(min=num(o-e),max=num(o+e))]))
  got=counter(t,'S82',160,dict(M,counter=white,wood=mint))
  if got:c,yaw,f=got;used.append(c);items.append(dict(place='clinic_beauty',anchor='counter',pos=num(_ls_off(c,yaw,-35)),yaw=yaw-90,actor=t+'_Counter'))
  else:skipped.append(dict(place='clinic_beauty',reason='no counter spot'))
  g=spot(c0,330,310,250,reg,used,wall=False)
  if g:
   c,yaw=g;used.append(c);booth(t+'_Op',c,yaw,330,310,dict(M,counter=white))
   _ls_box(t+'_OpBed',_ls_off(c,yaw,-40),yaw+90,(200,80,75),mint);_ls_box(t+'_OpBedPad',_ls_off(c,yaw,-40,0,75),yaw+90,(195,75,8),white)
   _ls_cyl(t+'_OpLampPost',_ls_off(c,yaw,-40,110),3,200,M['steel']);_ls_box(t+'_OpLamp',_ls_off(c,yaw,-40,60,195),yaw,(50,50,8),M['lamp'],False)
   items.append(dict(place='clinic_beauty',anchor='bed_op',pos=num(_ls_off(c,yaw,-40)),yaw=yaw,actor=t+'_OpBed'))
   views.append(dict(id='LS-beauty-op',eye=num(_ls_off(c,yaw,120,60,200)),target=num(_ls_off(c,yaw,-60,0,70)),fov=90,hour=11))
  else:skipped.append(dict(place='clinic_beauty',reason='no 3.3 x 3.1 m operating booth spot'))
  g=spot(c0,240,200,120,reg,used,wall=False)
  if g:
   c,yaw=g;used.append(c);_ls_box(t+'_ConsultTable',c,yaw,(80,120,75),white);_ls_box(t+'_ConsultScreen',_ls_off(c,yaw,0,40,75),yaw,(4,45,30),M['screen'])
   for s,an in ((-70,'consult'),(70,'consult2')):
    _ls_box(t+'_ConsultChair%+d'%s,_ls_off(c,yaw,s),yaw,(45,45,45),mint)
    items.append(dict(place='clinic_beauty',anchor=an,pos=num(_ls_off(c,yaw,s)),yaw=(yaw if s<0 else yaw+180)-90,actor=t+'_ConsultTable'))
  else:skipped.append(dict(place='clinic_beauty',reason='no consult table spot'))
  g=spot(c0,220,110,90,reg,used)
  if g:c,yaw=g;used.append(c);_ls_box(t+'_RestBed',_ls_off(c,yaw,0),yaw+90,(200,90,50),white);items.append(dict(place='clinic_beauty',anchor='rest',pos=num(c),yaw=yaw,actor=t+'_RestBed'))
  else:skipped.append(dict(place='clinic_beauty',reason='no recovery bed spot'))
  g=spot(c0,210,80,100,reg,used)
  if g:used.append(g[0]);bench(t+'_Bench',g[0],g[1],'clinic_beauty','seat',2);items.append(dict(place='clinic_beauty',anchor='wait',pos=num(_ls_off(g[0],g[1],80)),yaw=g[1]-90,actor=t+'_Bench_Seat'))
  else:skipped.append(dict(place='clinic_beauty',reason='no waiting bench spot'))
  g=spot(c0,140,90,230,reg,used,step=20)
  if g:
   c,yaw=g;used.append(c);mirror(t+'_Mirror',_ls_off(c,yaw,-((wd(c,yaw) or 45)-1),0,20),yaw,110,180)
   items.append(dict(place='clinic_beauty',anchor='mirror',pos=num(_ls_off(c,yaw,60)),yaw=yaw+180-90,actor=t+'_Mirror_Glass'))
   views.append(dict(id='LS-beauty-mirror',eye=num(_ls_off(c,yaw,320,80,165)),target=num(_ls_off(c,yaw,-45,0,110)),fov=75,hour=11))
  else:skipped.append(dict(place='clinic_beauty',reason='no free wall for the large mirror'))
  views.append(dict(id='LS-beauty',eye=num(_ls_off(d,0,0,0,170)),target=num(unreal.Vector(o.x,o.y,1290.)),fov=90,hour=11))
 else:skipped.append(dict(place='clinic_beauty',reason='S82_F01 or its door not found'))
 # 14. hair salon in S31 造型髮廊 (no salon furniture is baked in): counter, three chairs facing wall mirrors, a wash
 #     basin with a reclining chair, a waiting bench and a hair-colour swatch wall
 sb=shopbox('S31');d=shopdoor('S31')
 if sb and d:
  o,e,reg=sb;c0=unreal.Vector(o.x,o.y,1200.);used=[d];t='LoverSpot_Salon'
  items.append(dict(place='salon',anchor='door',pos=num(d),yaw=0,actor='S31_F01',building='S31',name='S31 造型髮廊',rooms=[dict(min=num(o-e),max=num(o+e))]))
  got=counter(t,'S31',140,M)
  if got:c,yaw,f=got;used.append(c);items.append(dict(place='salon',anchor='counter',pos=num(_ls_off(c,yaw,-35)),yaw=yaw-90,actor=t+'_Counter'))
  else:skipped.append(dict(place='salon',reason='no counter spot'))
  n=0
  for k in range(3):
   g=spot(c0,100,160,230,reg,used,step=20)
   if not g:break
   c,yaw=g;used.append(c);n+=1;s=t+'_Station%d'%n
   w0=(wd(c,yaw) or 80)-1;mirror(s+'_Mirror',_ls_off(c,yaw,-w0,0,70),yaw,80,120);_ls_box(s+'_Shelf',_ls_off(c,yaw,-w0+14,0,70),yaw,(25,90,4),M['wood'])
   ch=_ls_off(c,yaw,20);_ls_cyl(s+'_ChairPost',ch,8,45,M['steel']);_ls_box(s+'_ChairSeat',_ls_off(ch,yaw,0,0,45),yaw,(50,50,10),M['dark']);_ls_box(s+'_ChairBack',_ls_off(ch,yaw,22,0,55),yaw,(8,50,60),M['dark'])
   items.append(dict(place='salon',anchor='chair' if n==1 else 'chair%d'%n,pos=num(ch),yaw=yaw+180-90,actor=s+'_ChairSeat'))
  if n:views.append(dict(id='LS-salon',eye=num(_ls_off(c,yaw,380,120,170)),target=num(_ls_off(c,yaw,-40,0,110)),fov=80,hour=15))
  else:skipped.append(dict(place='salon',reason='no styling station spot'))
  g=spot(c0,90,200,120,reg,used)
  if g:
   c,yaw=g;used.append(c);_ls_box(t+'_WashBasin',_ls_off(c,yaw,-65,0,0),yaw,(60,70,90),white);_ls_box(t+'_WashChair',_ls_off(c,yaw,30),yaw,(120,60,50),M['dark'])
   items.append(dict(place='salon',anchor='wash',pos=num(_ls_off(c,yaw,30)),yaw=yaw+180-90,actor=t+'_WashBasin'))
  else:skipped.append(dict(place='salon',reason='no wash basin spot'))
  g=spot(c0,210,80,100,reg,used)
  if g:used.append(g[0]);bench(t+'_Bench',g[0],g[1],'salon','seat',2)
  else:skipped.append(dict(place='salon',reason='no waiting bench spot'))
  g=spot(c0,180,60,220,reg,used,step=20)
  if g:
   c,yaw=g;used.append(c);w0=(wd(c,yaw) or 30)-2;_ls_box(t+'_SwatchBoard',_ls_off(c,yaw,-w0,0,90),yaw,(4,160,110),white)
   cols=[(.08,.06,.05),(.35,.2,.1),(.75,.55,.3),(.92,.85,.6),(.7,.15,.15),(.85,.45,.6),(.3,.35,.75),(.55,.7,.75)]
   for k,col in enumerate(cols):_ls_box(t+'_Swatch%d'%k,_ls_off(c,yaw,-w0+2.5,-70+20*k,110),yaw,(2,12,70),_ls_mat('M_LS_Swatch%d'%k,col,.6),False)
   items.append(dict(place='salon',anchor='swatch',pos=num(_ls_off(c,yaw,80)),yaw=yaw+180-90,actor=t+'_SwatchBoard'))
  else:skipped.append(dict(place='salon',reason='no free wall for the swatch board'))
 else:skipped.append(dict(place='salon',reason='S31_F01 or its door not found'))
 # new-game spawn outside the boys' dorm: only a check view, nothing placed
 sp=next((a for a in (gp.get('boys_dorm') or {}).get('anchors',[]) if a['name']=='spawn'),None)
 if sp:views.append(dict(id='LS-spawn',eye=num(_ls_off(V(sp['pos']),sp['yaw']+90,-500,0,250)),target=num(_ls_off(V(sp['pos']),sp['yaw']+90,300,0,120)),fov=80,hour=9))
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (LS_OUT/'lover-spots-views.json').write_text(json.dumps(views,indent=1),'utf8')
 (LS_OUT/('lover-spots-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),items=items,lots=lots,skipped=skipped),ensure_ascii=False,indent=1),'utf8')
]====]
