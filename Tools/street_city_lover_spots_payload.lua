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
def _ls_note(text):
 # progress file, written and closed at once: the editor log can lag behind a long Python call
 with open(str(ROOT/'output/street-social-city-production/world-edge-v1/lover-progress.txt'),'a',encoding='utf8') as f:f.write(time.strftime('%H:%M:%S ')+text+'\n')
def _ls_search(world,hint,z,w,d,h,yaws,rmin=0,rmax=1200,avoid=[],wall=False,region=None,step=25,tol=8,follow=False):
 # follow: outdoors the ground slopes, so each candidate is tested at its own floor height instead of the hint's
 # spiral of 25 cm rings; first spot (optionally with a wall behind) wins, else the nearest free spot
 best=None;end=time.time()+60
 for r in range(int(rmin),int(rmax)+1,step):
  if time.time()>end:_ls_note('search gave up at r=%d of %d, %dx%d near %d,%d'%(r,rmax,w,d,hint.x,hint.y));return best
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
_LS_REC=[None]  # a list while a round-2 recipe runs: the actors it spawns (section 16 swaps them for a Tripo model)
def _ls_spawn(label,mesh,p,yaw,scale,mat=None,collide=True):
 a=SUB.spawn_actor_from_class(unreal.StaticMeshActor,p,unreal.Rotator(roll=0,pitch=0,yaw=yaw))
 if _LS_REC[0] is not None:_LS_REC[0].append(a)
 a.set_actor_label(label);a.set_folder_path('UniversityCity/LoverSpotsV1');a.tags=[unreal.Name('LoverSpot')]
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
 import faulthandler;_ls_note('install started');FH=open(str(LS_OUT/'lover-stack.txt'),'a',encoding='utf8');faulthandler.dump_traceback_later(120,repeat=True,file=FH)
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
  if ds:return V(ds[0])
  # shops with only upstairs places: the refit frame (metres, front at -H, door at door_x) of the shop's F01 actor
  f=shopframe.get(b);sh=acts.get(b+'_F01')
  if not f or not sh:return None
  o=sh.get_actor_location();yaw=math.radians(sh.get_actor_rotation().yaw);lx,ly=f['door_x']*100,(f['H']-.5)*100
  return unreal.Vector(o.x+lx*math.cos(yaw)-ly*math.sin(yaw),o.y+lx*math.sin(yaw)+ly*math.cos(yaw),1200.)
 shopframe={}
 for p in ('shop-refits-v1/refits-build.json','shop-samples-v1/samples-build.json'):
  for s in json.loads((ROOT/'output/street-social-city-production'/p).read_text('utf8'))['shops']:shopframe.setdefault(s['id'],s)
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
 # 15. round 2 (c-conquest 8.2): dress the empty or converted rooms. A recipe draws one piece of furniture in a w x d
 #     footprint (front = +yaw, the standing room in front is part of the footprint) and returns its anchors; spots are
 #     searched inside the room with the same floor / box tests, plus a reserve so later pieces keep off earlier ones.
 R2={}
 def R2mat(name,col,r=.6,emit=0.):
  if name not in R2:R2[name]=_ls_mat('M_LS_R2_'+name,col,r,0.,emit)
  return R2[name]
 cnt={}
 def nm(place,base):
  k=(place,base);cnt[k]=cnt.get(k,0)+1;return base if cnt[k]==1 else '%s%d'%(base,cnt[k])
 def A2(place,base,p,yaw,actor):items.append(dict(place=place,anchor=nm(place,base),pos=num(p),yaw=yaw,actor=actor))
 def face(c,yaw,fw,side=0):return _ls_off(c,yaw,fw,side),yaw+180-90   # standing at fw, looking back at the piece
 def r_rack(t,c,yaw,pl):
  b=_ls_off(c,yaw,-45)
  for s in (-60,60):_ls_cyl(t+'_Post%+d'%s,_ls_off(b,yaw,0,s),2.5,160,M['steel'])
  _ls_box(t+'_Rail',_ls_off(b,yaw,0,0,155),yaw,(4,125,4),M['steel'],False)
  for k in range(6):_ls_box(t+'_Cloth%d'%k,_ls_off(b,yaw,0,-50+20*k,60),yaw,(38,6,90),R2mat('Cloth%d'%(k%6),[(.85,.3,.35),(.25,.45,.8),(.95,.9,.85),(.2,.2,.25),(.4,.7,.5),(.95,.75,.35)][k%6]),False)
  p,y=face(c,yaw,30);A2(pl,'rack',p,y,t+'_Rail')
 def r_fitting(t,c,yaw,pl):
  b=_ls_off(c,yaw,-40);wall=R2mat('Booth',(.88,.86,.82))
  _ls_box(t+'_Back',_ls_off(b,yaw,-60),yaw,(8,125,220),wall)
  for s in (-62,62):_ls_box(t+'_Side%+d'%s,_ls_off(b,yaw,0,s),yaw,(120,6,220),wall)
  _ls_box(t+'_Curtain',_ls_off(b,yaw,58,0,15),yaw,(3,118,195),R2mat('Curtain',(.55,.2,.3)),False)
  _ls_box(t+'_Glass',_ls_off(b,yaw,-55,0,40),yaw,(1.5,60,150),silver or M['steel'],False)
  A2(pl,'fitting',b,yaw+180-90,t+'_Curtain')
 def r_changing(base):
  def fn(t,c,yaw,pl):
   b=_ls_off(c,yaw,-40);wall=R2mat('Booth',(.88,.86,.82))
   _ls_box(t+'_Back',_ls_off(b,yaw,-60),yaw,(8,125,220),wall)
   for s in (-62,62):_ls_box(t+'_Side%+d'%s,_ls_off(b,yaw,0,s),yaw,(120,6,220),wall)
   _ls_box(t+'_Curtain',_ls_off(b,yaw,58,0,15),yaw,(3,118,195),R2mat('CurtainChange',(.3,.4,.55)),False)
   A2(pl,base,b,yaw+180-90,t+'_Curtain')
  return fn
 def r_curtain(t,c,yaw,pl):
  _ls_box(t+'_Rail',_ls_off(c,yaw,0,0,205),yaw,(4,220,4),M['steel'],False);_ls_box(t+'_Cloth',_ls_off(c,yaw,0,0,20),yaw,(3,215,185),R2mat('CurtainWhite',(.92,.93,.9)),False)
  A2(pl,'curtain',_ls_off(c,yaw,40),yaw-90,t+'_Cloth')
 def r_telescope(t,c,yaw,pl):
  _ls_cyl(t+'_Post',c,5,120,M['steel']);_ls_box(t+'_Tube',_ls_off(c,yaw,0,0,120),yaw,(60,12,12),M['dark'],False)
  p,y=face(c,yaw,50);A2(pl,'telescope',p,y,t+'_Post')
 def r_bleacher(t,c,yaw,pl):
  for k in range(3):_ls_box(t+('_Seat' if k==0 else '_Step%d'%k),_ls_off(c,yaw,50-50*k),yaw,(50,480,45*(k+1)),M['wood'])
  A2(pl,'bleacher',_ls_off(c,yaw,50),yaw-90,t+'_Step0')
 def r_mirror(t,c,yaw,pl):
  w0=(wd(c,yaw) or 60)-1;mirror(t+'_M',_ls_off(c,yaw,-w0,0,20),yaw,90,180);p,y=face(c,yaw,40);A2(pl,'mirror',p,y,t+'_M_Glass')
 def r_counter(t,c,yaw,pl,base='counter'):
  f=_ls_off(c,yaw,45);_ls_box(t+'_Counter',f,yaw,(60,c_w,100),M['counter']);_ls_box(t+'_Top',_ls_off(f,yaw,0,0,100),yaw,(66,c_w+6,4),M['wood'])
  A2(pl,base,_ls_off(c,yaw,-35),yaw-90,t+'_Counter')
 c_w=160
 def r_checkout(t,c,yaw,pl):r_counter(t,c,yaw,pl,'checkout')
 def r_bar(t,c,yaw,pl):r_counter(t,c,yaw,pl,'bar')
 def r_case(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);_ls_box(t+'_Case',b,yaw,(60,150,90),M['wood']);_ls_box(t+'_Glass',_ls_off(b,yaw,0,0,90),yaw,(56,146,20),R2mat('CaseGlass',(.8,.9,.95),.05,.3),False)
  p,y=face(c,yaw,50);A2(pl,'case',p,y,t+'_Case')
 def r_display(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);_ls_box(t+'_Table',b,yaw,(60,150,85),M['counter'])
  for k in range(4):_ls_box(t+'_Phone%d'%k,_ls_off(b,yaw,0,-55+37*k,85),yaw,(14,7,1.5),M['screen'],False)
  p,y=face(c,yaw,50);A2(pl,'display',p,y,t+'_Table')
 def r_table2(t,c,yaw,pl,base='table',seat='seat',grill=False):
  _ls_box(t+'_Table',c,yaw,(80,80,74),M['wood'])
  if grill:_ls_cyl(t+'_Grill',_ls_off(c,yaw,0,0,74),20,4,M['dark'],False)
  for s in (-65,65):_ls_box(t+'_Chair%+d'%s,_ls_off(c,yaw,s),yaw,(42,42,45),M['sofa'])
  A2(pl,base,_ls_off(c,yaw,-65),yaw-90,t+'_Table')
  if seat:A2(pl,seat,_ls_off(c,yaw,65),yaw+180-90,t+'_Table')
 def r_grill(t,c,yaw,pl):r_table2(t,c,yaw,pl,'grill_table',None,True)
 def r_try(t,c,yaw,pl):r_table2(t,c,yaw,pl,'try',None)
 def r_counter_seats(t,c,yaw,pl,base='counter_seat'):
  b=_ls_off(c,yaw,-50);_ls_box(t+'_Bar',b,yaw,(50,300,100),M['wood']);_ls_box(t+'_Top',_ls_off(b,yaw,0,0,100),yaw,(56,306,4),M['counter'])
  for k in range(4):
   s=_ls_off(c,yaw,10,-112+75*k);_ls_cyl(t+'_Stool%d'%k,s,4,65,M['steel']);_ls_cyl(t+'_Seat%d'%k,_ls_off(s,yaw,0,0,65),17,6,M['cushion'])
   A2(pl,base,s,yaw+180-90,t+'_Bar')
 def r_conveyor(t,c,yaw,pl):
  b=_ls_off(c,yaw,-50);_ls_box(t+'_Counter',b,yaw,(60,460,95),M['wood']);_ls_box(t+'_Belt',_ls_off(b,yaw,-10,0,95),yaw,(22,450,4),R2mat('Belt',(.75,.75,.78),.3),False)
  for k in range(5):_ls_box(t+'_Plate%d'%k,_ls_off(b,yaw,-10,-180+90*k,99),yaw,(14,14,3),R2mat('Plate',(.95,.55,.4)),False)
  for k in range(5):
   s=_ls_off(c,yaw,15,-180+90*k);_ls_cyl(t+'_Stool%d'%k,s,4,62,M['steel']);_ls_cyl(t+'_Seat%d'%k,_ls_off(s,yaw,0,0,62),17,6,M['cushion'])
   A2(pl,'conveyor_seat',s,yaw+180-90,t+'_Counter')
 def r_booth(t,c,yaw,pl,base='booth'):
  _ls_box(t+'_Table',c,yaw,(70,110,74),M['wood'])
  for s in (-70,70):
   _ls_box(t+'_Bench%+d'%s,_ls_off(c,yaw,s),yaw,(45,120,45),M['sofa']);_ls_box(t+'_Back%+d'%s,_ls_off(c,yaw,s*1.35),yaw,(12,120,95),M['sofa'])
  A2(pl,base,_ls_off(c,yaw,-70),yaw-90,t+'_Table')
 def r_claw(t,c,yaw,pl):
  b=_ls_off(c,yaw,-40);_ls_box(t+'_Body',b,yaw,(85,85,100),R2mat('Claw',(.95,.45,.6)));_ls_box(t+'_Glass',_ls_off(b,yaw,0,0,100),yaw,(80,80,80),R2mat('ClawGlass',(.85,.95,1.),.05,.4),False)
  _ls_box(t+'_Top',_ls_off(b,yaw,0,0,180),yaw,(85,85,15),R2mat('Claw',(.95,.45,.6)))
  p,y=face(c,yaw,45);A2(pl,'claw',p,y,t+'_Body')
 def r_cabinet(t,c,yaw,pl,base):
  b=_ls_off(c,yaw,-45);_ls_box(t+'_Body',b,yaw,(70,80,180),M['dark']);_ls_box(t+'_Screen',_ls_off(b,yaw,35.5,0,110),yaw,(1,66,50),M['screen'],False)
  if base=='racing':_ls_box(t+'_Seat',_ls_off(b,yaw,90),yaw,(60,55,50),M['cushion'])
  p,y=face(c,yaw,50 if base=='rhythm' else 90);A2(pl,base,p,y,t+'_Body')
 def r_rhythm(t,c,yaw,pl):r_cabinet(t,c,yaw,pl,'rhythm')
 def r_racing(t,c,yaw,pl):r_cabinet(t,c,yaw,pl,'racing')
 def r_photobooth(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);wall=R2mat('Photo',(.95,.8,.9))
  _ls_box(t+'_Back',_ls_off(b,yaw,-75),yaw,(8,180,220),wall)
  for s in (-90,90):_ls_box(t+'_Side%+d'%s,_ls_off(b,yaw,0,s),yaw,(150,6,220),wall)
  _ls_box(t+'_Roof',_ls_off(b,yaw,0,0,220),yaw,(150,186,6),wall);_ls_box(t+'_Curtain',_ls_off(b,yaw,74,0,30),yaw,(3,176,180),R2mat('Curtain',(.55,.2,.3)),False)
  _ls_box(t+'_Screen',_ls_off(b,yaw,-70,0,120),yaw,(2,60,40),M['screen'],False)
  A2(pl,'photobooth',b,yaw+180-90,t+'_Curtain')
 def r_dental(t,c,yaw,pl):
  ch=_ls_off(c,yaw,-20);_ls_box(t+'_Base',ch,yaw+90,(170,65,55),R2mat('Dental',(.55,.8,.85)));_ls_box(t+'_Head',_ls_off(ch,yaw,0,-80,55),yaw,(40,30,25),R2mat('Dental',(.55,.8,.85)))
  _ls_cyl(t+'_LampPost',_ls_off(ch,yaw,-55,-60),3,190,M['steel']);_ls_box(t+'_Lamp',_ls_off(ch,yaw,-25,-45,185),yaw,(30,30,8),M['lamp'],False)
  A2(pl,'dental_chair',_ls_off(ch,yaw,0,0,55),yaw,t+'_Base')
 def r_nail(t,c,yaw,pl):
  _ls_box(t+'_Table',c,yaw,(50,100,72),M['counter']);_ls_box(t+'_Lamp',_ls_off(c,yaw,0,40,72),yaw,(10,10,35),M['lamp'],False)
  for s in (-55,55):_ls_box(t+'_Chair%+d'%s,_ls_off(c,yaw,s),yaw,(42,42,45),M['cushion'])
  A2(pl,'nail_table',_ls_off(c,yaw,-55),yaw-90,t+'_Table');A2(pl,'seat',_ls_off(c,yaw,55),yaw+180-90,t+'_Table')
 def r_cats(t,c,yaw,pl):
  _ls_box(t+'_Mat',c,yaw,(160,160,2),R2mat('CatMat',(.7,.85,.6)),False)
  for k,(fw,sd,h) in enumerate([(-40,-40,150),(30,40,100)]):
   p=_ls_off(c,yaw,fw,sd);_ls_cyl(t+'_Post%d'%k,p,8,h,R2mat('Sisal',(.75,.62,.45)));_ls_box(t+'_Shelf%d'%k,_ls_off(p,yaw,0,0,h),yaw,(45,45,5),R2mat('CatMat',(.7,.85,.6)))
  for k,(fw,sd) in enumerate([(10,-10),(-30,50)]):_ls_box(t+'_Cat%d'%k,_ls_off(c,yaw,fw,sd,2),yaw+30*k,(32,16,18),R2mat('Cat%d'%k,[(.95,.6,.3),(.2,.2,.22)][k]),False)
  A2(pl,'cats',_ls_off(c,yaw,85),yaw+180-90,t+'_Mat')
 def r_mbooth(t,c,yaw,pl):
  b=_ls_off(c,yaw,-20);wall=R2mat('MBooth',(.4,.45,.55))
  _ls_box(t+'_Back',_ls_off(b,yaw,-80),yaw,(8,200,160),wall)
  for s in (-100,100):_ls_box(t+'_Side%+d'%s,_ls_off(b,yaw,0,s),yaw,(160,6,160),wall)
  _ls_box(t+'_Sofa',_ls_off(b,yaw,-40),yaw,(70,180,40),M['sofa']);_ls_box(t+'_Desk',_ls_off(b,yaw,40),yaw,(40,120,70),M['wood']);_ls_box(t+'_PC',_ls_off(b,yaw,45,0,70),yaw,(4,45,30),M['screen'],False)
  A2(pl,'booth',_ls_off(b,yaw,-40),yaw-90,t+'_Sofa')
 def r_shelf(t,c,yaw,pl):
  b=_ls_off(c,yaw,-40);_ls_box(t+'_Shelf',b,yaw,(40,200,200),M['wood'])
  for k in range(4):_ls_box(t+'_Books%d'%k,_ls_off(b,yaw,4,0,25+45*k),yaw,(34,190,30),R2mat('Books%d'%k,[(.8,.3,.3),(.3,.5,.8),(.9,.8,.4),(.4,.7,.5)][k]),False)
  p,y=face(c,yaw,40);A2(pl,'shelf',p,y,t+'_Shelf')
 def r_aisle(t,c,yaw,pl):
  _ls_box(t+'_Shelf',c,yaw,(60,300,170),M['counter'])
  for k in range(3):
   for s in (-31,31):_ls_box(t+'_Goods%d%+d'%(k,s),_ls_off(c,yaw,s,0,30+50*k),yaw,(2,290,30),R2mat('Goods%d'%k,[(.9,.5,.3),(.4,.7,.4),(.8,.8,.3)][k]),False)
  p,y=face(c,yaw,80);A2(pl,'aisle',p,y,t+'_Shelf')
 def r_fresh(t,c,yaw,pl):
  b=_ls_off(c,yaw,-35);_ls_box(t+'_Case',b,yaw,(80,200,90),M['counter']);_ls_box(t+'_Top',_ls_off(b,yaw,0,0,90),yaw,(76,196,4),R2mat('Fresh',(.6,.9,.6),.4,.5),False)
  p,y=face(c,yaw,45);A2(pl,'fresh',p,y,t+'_Case')
 def r_cart(t,c,yaw,pl):
  _ls_box(t+'_Basket',_ls_off(c,yaw,0,0,45),yaw,(80,50,45),M['steel']);_ls_box(t+'_Base',c,yaw,(70,45,8),M['dark'])
  p,y=face(c,yaw,-70);A2(pl,'cart',p,y,t+'_Basket')
 def r_ticket(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);_ls_box(t+'_Machine',b,yaw,(50,60,170),R2mat('Ticket',(.85,.85,.8)));_ls_box(t+'_Screen',_ls_off(b,yaw,25.5,0,120),yaw,(1,45,30),M['screen'],False)
  p,y=face(c,yaw,40);A2(pl,'ticket',p,y,t+'_Machine')
 def r_bench(t,c,yaw,pl):
  _ls_box(t+'_Seat',c,yaw,(45,180,45),M['wood']);A2(pl,'bench',_ls_off(c,yaw,5),yaw-90,t+'_Seat')
 def r_lane(t,c,yaw,pl):
  L=lane_len;_ls_box(t+'_Lane',c,yaw,(L,105,4),R2mat('Lane',(.85,.7,.45),.3))
  for s in (-62,62):_ls_box(t+'_Gutter%+d'%s,_ls_off(c,yaw,0,s),yaw,(L,20,2),M['dark'])
  for k in range(10):_ls_cyl(t+'_Pin%d'%k,_ls_off(c,yaw,-L/2+40+12*(k%4),-20+13*(k%3),4),4,38,R2mat('Pin',(.97,.97,.95)),False)
  A2(pl,'lane',_ls_off(c,yaw,L/2-30),yaw+180-90,t+'_Lane')
 lane_len=900
 def r_billiards(t,c,yaw,pl):
  _ls_box(t+'_Table',c,yaw,(250,140,70),M['wood']);_ls_box(t+'_Cloth',_ls_off(c,yaw,0,0,70),yaw,(230,120,6),R2mat('Felt',(.1,.45,.25),.9))
  A2(pl,'billiards',_ls_off(c,yaw,0,-105),yaw,t+'_Table')
 def r_bed(t,c,yaw,pl,base='bed'):
  _ls_box(t+'_Bed',c,yaw+90,(200,90,55),M['counter']);_ls_box(t+'_Pillow',_ls_off(c,yaw,0,-80,55),yaw,(30,60,10),R2mat('Linen',(.95,.95,.98)),False)
  _ls_box(t+'_Curtain',_ls_off(c,yaw,60),yaw,(2,220,190),R2mat('Curtain2',(.75,.85,.9)),False)
  A2(pl,base,_ls_off(c,yaw,0,0,55),yaw,t+'_Bed')
 def r_desk(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);_ls_box(t+'_Desk',b,yaw,(60,120,74),M['wood']);_ls_box(t+'_Chair',_ls_off(b,yaw,60),yaw,(42,42,45),M['sofa'])
  A2(pl,'desk',_ls_off(b,yaw,60),yaw+180-90,t+'_Desk')
 def r_recliner(t,c,yaw,pl):
  for s in (-38,38):_ls_box(t+'_Seat%+d'%s,_ls_off(c,yaw,0,s),yaw,(110,70,40),M['sofa']);_ls_box(t+'_Back%+d'%s,_ls_off(c,yaw,-50,s,40),yaw,(20,70,25),M['sofa'])
  A2(pl,'seat',_ls_off(c,yaw,0,-38,40),yaw-90,t+'_Seat-38')
 def r_kitchen(t,c,yaw,pl):
  b=_ls_off(c,yaw,-45);_ls_box(t+'_Counter',b,yaw,(60,240,90),M['counter']);_ls_box(t+'_Top',_ls_off(b,yaw,0,0,90),yaw,(62,242,4),M['stone'])
  _ls_box(t+'_Stove',_ls_off(b,yaw,0,60,94),yaw,(50,60,2),M['dark'],False);_ls_box(t+'_Sink',_ls_off(b,yaw,0,-60,92),yaw,(45,55,3),M['steel'],False)
  A2(pl,'kitchen',_ls_off(c,yaw,20,-60),yaw+180-90,t+'_Counter');A2(pl,'stove',_ls_off(c,yaw,20,60),yaw+180-90,t+'_Stove')
 def r_atm(t,c,yaw,pl):
  b=_ls_off(c,yaw,-40);_ls_box(t+'_ATM',b,yaw,(60,70,150),M['steel']);_ls_box(t+'_Screen',_ls_off(b,yaw,30.5,0,115),yaw,(1,40,28),M['screen'],False)
  p,y=face(c,yaw,40);A2(pl,'atm',p,y,t+'_ATM')
 def r_backdrop(t,c,yaw,pl):
  w0=(wd(c,yaw) or 80)-2;_ls_box(t+'_Backdrop',_ls_off(c,yaw,-w0),yaw,(3,280,250),R2mat('Backdrop',(.9,.9,.92)));_ls_box(t+'_Stool',_ls_off(c,yaw,-w0+80),yaw,(40,40,50),M['wood'])
  A2(pl,'backdrop',_ls_off(c,yaw,-w0+80),yaw+180-90,t+'_Backdrop')
  tp=_ls_off(c,yaw,-w0+380);_ls_cyl(t+'_Tripod',tp,2,140,M['steel']);_ls_box(t+'_Camera',_ls_off(tp,yaw,0,0,140),yaw,(20,15,12),M['dark'])
  A2(pl,'camera',_ls_off(tp,yaw,30),yaw+180-90,t+'_Camera')
 def r_net(t,c,yaw,pl):
  for s in (-450,450):_ls_cyl(t+'_Post%+d'%s,_ls_off(c,yaw,0,s),5,245,M['steel'])
  _ls_box(t+'_Net',_ls_off(c,yaw,0,0,145),yaw,(2,900,100),R2mat('Net',(.95,.95,.95)),False);A2(pl,'net',_ls_off(c,yaw,150),yaw+180-90,t+'_Net')
 def r_pingpong(t,c,yaw,pl):
  _ls_box(t+'_Table',c,yaw,(274,152,76),R2mat('TT',(.1,.3,.55),.5));_ls_box(t+'_Net',_ls_off(c,yaw,0,0,76),yaw,(2,170,15),R2mat('Net',(.95,.95,.95)),False)
  A2(pl,'pingpong',_ls_off(c,yaw,-190),yaw-90,t+'_Table')
 def r_treadmill(t,c,yaw,pl,base='treadmill'):
  _ls_box(t+'_Deck',c,yaw,(170,75,20),M['dark']);_ls_box(t+'_Console',_ls_off(c,yaw,80,0,20),yaw,(10,70,120),M['dark'])
  A2(pl,base,_ls_off(c,yaw,-10,0,20),yaw-90,t+'_Deck')
 def r_bike(t,c,yaw,pl):
  _ls_box(t+'_Frame',c,yaw,(110,40,60),M['dark']);_ls_box(t+'_Seat',_ls_off(c,yaw,-30,0,60),yaw,(25,20,40),M['dark']);A2(pl,'bike',_ls_off(c,yaw,-30,0,0),yaw-90,t+'_Frame')
 def r_named_counter(base):
  return lambda t,c,yaw,pl:r_counter(t,c,yaw,pl,base)
 def r_doctor(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);_ls_box(t+'_Desk',b,yaw,(60,120,74),M['wood']);_ls_box(t+'_Chair',_ls_off(b,yaw,60),yaw,(42,42,45),M['sofa'])
  _ls_box(t+'_PatientChair',_ls_off(b,yaw,40,90),yaw,(40,40,45),M['cushion'])
  A2(pl,'doctor',_ls_off(b,yaw,60),yaw+180-90,t+'_Desk')
 def r_seatbench(t,c,yaw,pl):
  _ls_box(t+'_Seat',c,yaw,(45,180,45),M['sofa']);_ls_box(t+'_Back',_ls_off(c,yaw,-20,0,45),yaw,(6,180,40),M['sofa'])
  A2(pl,'seat',_ls_off(c,yaw,5,-45),yaw-90,t+'_Seat');A2(pl,'seat',_ls_off(c,yaw,5,45),yaw-90,t+'_Seat')
 def r_shoerack(t,c,yaw,pl):
  b=_ls_off(c,yaw,-40);_ls_box(t+'_Shelf',b,yaw,(40,200,200),M['wood'])
  for k in range(4):_ls_box(t+'_Shoes%d'%k,_ls_off(b,yaw,8,0,25+45*k),yaw,(30,185,14),R2mat('Shoes%d'%k,[(.75,.72,.7),(.2,.2,.25),(.7,.25,.25),(.35,.25,.18)][k]),False)
  p,y=face(c,yaw,40);A2(pl,'shoe_rack',p,y,t+'_Shelf')
 def r_tryshoes(t,c,yaw,pl):
  _ls_box(t+'_Seat',c,yaw,(45,120,42),M['sofa']);_ls_box(t+'_FloorMirror',_ls_off(c,yaw,70,0,0),yaw,(4,40,35),silver or M['steel'],False)
  A2(pl,'try_shoes',_ls_off(c,yaw,35),yaw-90,t+'_Seat')
 def r_vaultbox(t,c,yaw,pl):
  for k,(w_,d_) in enumerate([(120,70),(114,66),(108,62),(102,58)]):_ls_box(t+'_Tier%d'%k,_ls_off(c,yaw,0,0,25*k),yaw,(d_,w_,25),R2mat('VaultWood',(.62,.45,.28)))
  _ls_box(t+'_Top',_ls_off(c,yaw,0,0,100),yaw,(58,102,8),R2mat('VaultTop',(.85,.82,.72)))
  p,y=face(c,yaw,60);A2(pl,'vault_box',p,y,t+'_Top')
 def r_gymmat(t,c,yaw,pl):
  for k in range(3):_ls_box(t+'_Mat%d'%k,_ls_off(c,yaw,0,0,10*k),yaw,(120,200,10),R2mat('GymMat',(.2,.35,.65)))
  A2(pl,'gym_mat',_ls_off(c,yaw,0,0,0),yaw-90,t+'_Mat0')
 def r_crib(t,c,yaw,pl):
  _ls_box(t+'_Base',_ls_off(c,yaw,0,0,40),yaw,(60,120,8),M['wood'])
  for s in (-28,28):_ls_box(t+'_Rail%+d'%s,_ls_off(c,yaw,s,0,48),yaw,(3,120,40),M['wood'],False)
  for s in (-58,58):_ls_box(t+'_End%+d'%s,_ls_off(c,yaw,0,s,0),yaw,(60,4,90),M['wood'])
  p,y=face(c,yaw,60);A2(pl,'crib',p,y,t+'_Base')
 def r_ultra(t,c,yaw,pl):
  _ls_box(t+'_Cart',c,yaw,(60,50,110),M['counter']);_ls_box(t+'_Screen',_ls_off(c,yaw,0,0,115),yaw,(4,45,35),M['screen'],False)
  p,y=face(c,yaw,60);A2(pl,'ultrasound_cart',p,y,t+'_Cart')
 def r_exhibit(t,c,yaw,pl):
  _ls_box(t+'_Plinth',c,yaw,(60,60,100),R2mat('Plinth',(.92,.92,.9)));_ls_box(t+'_Piece',_ls_off(c,yaw,0,0,100),yaw+25,(30,30,45),R2mat('Bronze',(.55,.4,.25),.35))
  p,y=face(c,yaw,90);A2(pl,'exhibit',p,y,t+'_Plinth')
 def r_easel(t,c,yaw,pl):
  _ls_box(t+'_Leg',c,yaw,(6,60,160),M['wood']);_ls_box(t+'_Canvas',_ls_off(c,yaw,4,0,80),yaw,(2,60,70),R2mat('Canvas',(.97,.96,.93)),False);_ls_box(t+'_Stool',_ls_off(c,yaw,70),yaw,(35,35,45),M['wood'])
  A2(pl,'easel',_ls_off(c,yaw,70),yaw+180-90,t+'_Canvas')
 def r_weights(t,c,yaw,pl):
  b=_ls_off(c,yaw,-40);_ls_box(t+'_Rack',b,yaw,(50,180,110),M['steel'])
  for k in range(5):_ls_cyl(t+'_Plate%d'%k,_ls_off(b,yaw,0,-70+35*k,110),12,8,M['dark'],False)
  _ls_box(t+'_Bench',_ls_off(c,yaw,40),yaw,(120,35,45),M['cushion']);A2(pl,'weights',_ls_off(c,yaw,40,0,45),yaw-90,t+'_Rack')
 def r_locker(t,c,yaw,pl):
  b=_ls_off(c,yaw,-35);_ls_box(t+'_Locker',b,yaw,(45,180,190),R2mat('Locker',(.45,.55,.65),.4))
  p,y=face(c,yaw,45);A2(pl,'locker',p,y,t+'_Locker')
 def r_shower(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);wall=R2mat('Tile',(.85,.9,.92),.3)
  _ls_box(t+'_Back',_ls_off(b,yaw,-50),yaw,(6,105,220),wall)
  for s in (-52,52):_ls_box(t+'_Side%+d'%s,_ls_off(b,yaw,0,s),yaw,(100,6,220),wall)
  _ls_cyl(t+'_Head',_ls_off(b,yaw,-40,0,195),8,4,M['steel'],False);A2(pl,'shower',b,yaw-90,t+'_Back')
 def r_tank(t,c,yaw,pl):
  b=_ls_off(c,yaw,-60);water=_ls_mat('M_LS_AquaWater',(.1,.45,.6),.05,0.,.8)
  _ls_box(t+'_Base',b,yaw,(60,420,50),M['wood']);_ls_box(t+'_Water',_ls_off(b,yaw,-20,0,50),yaw,(8,400,180),water)
  for s in (-205,205):_ls_box(t+'_Side%+d'%s,_ls_off(b,yaw,0,s,50),yaw,(60,10,180),M['dark'])
  _ls_box(t+'_Top',_ls_off(b,yaw,0,0,230),yaw,(60,420,10),M['dark'])
  koi=next((a.static_mesh_component.static_mesh for a in acts.values() if a.get_actor_label().startswith('Activity_ACTSPACE-06') and isinstance(a,unreal.StaticMeshActor) and a.static_mesh_component.static_mesh and 'koi' in a.static_mesh_component.static_mesh.get_name().lower()),None)
  if koi:
   for k,(s,u) in enumerate([(-150,40),(-60,110),(20,70),(110,140),(170,60),(60,30)]):_ls_spawn(t+'_Fish%d'%k,koi,_ls_off(b,yaw,0,s,50+u),yaw+(90 if k%2 else -90),[.7,.7,.7],None,False)
  p,y=face(c,yaw,80);A2(pl,'tank',p,y,t+'_Water')
 def r_jelly(t,c,yaw,pl):
  _ls_cyl(t+'_Base',c,45,40,M['dark']);_ls_cyl(t+'_Column',_ls_off(c,yaw,0,0,40),40,200,_ls_mat('M_LS_JellyWater',(.25,.3,.7),.05,0.,1.2),True);_ls_cyl(t+'_Cap',_ls_off(c,yaw,0,0,240),45,15,M['dark'])
  p,y=face(c,yaw,90);A2(pl,'jelly',p,y,t+'_Column')
 def r_vend(t,c,yaw,pl):
  b=_ls_off(c,yaw,-30);_ls_vending(60+cnt.get(('_vend',''),0),b,yaw,M);cnt[('_vend','')]=cnt.get(('_vend',''),0)+1
  p,y=face(c,yaw,80);A2(pl,'vending',p,y,'LoverSpot_Vending')
 def r_mat(t,c,yaw,pl):
  _ls_box(t+'_Mat',c,yaw,(180,60,1.5),R2mat('Yoga',(.55,.4,.75)),False);A2(pl,'mat',c,yaw-90,t+'_Mat')
 # 16. Tripo furniture (life-tripo-v1, prepared + instant-meshes-rs; remeshed.json): a dressed piece whose recipe has a
 #     model shows the model, scaled into the recipe's w x d x h box on the same spot. The recipe's boxes stay as the
 #     collision (invisible), so anchors keep their actor names and the walk replay sees the same blockers.
 LT=ROOT/'output/street-social-city-production/life-tripo-v1';ltr={};ltm={};tripo_used=[]
 if (LT/'remeshed.json').exists():
  pre={a['id']:a for a in json.loads((LT/'prepared.json').read_text('utf8'))['assets']}
  for r in json.loads((LT/'remeshed.json').read_text('utf8'))['assets']:
   p=pre.get(r['id'])
   if r.get('status')!='passed' or not p:continue
   # keep the prepared mesh when the remesh did not cut triangles (prepared pieces are already at their budget)
   ltr[p['key']]=r['path'] if r['triangles']<p['triangles'] else p['path']
 TRIPO={'rack':'clothing_rack','case':'jewelry_case','try':'eyeglass_display','ticket':'ticket_machine','conveyor':'sushi_conveyor',
  'grill':'yakiniku_table','cats':'cat_tree','mbooth':'manga_booth','claw':'claw_machine','photobooth':'photo_booth','rhythm':'rhythm_game',
  'racing':'racing_game','billiards':'billiards_table','dental':'dental_chair','bed':'hospital_bed_curtain','doctor':'consult_desk_screen',
  'nail':'nail_table','aisle':'supermarket_shelf','fresh':'produce_case','cart':'shopping_cart','atm':'atm','concession':'popcorn_counter',
  'recliner':'planetarium_recliner','exhibit':'museum_vitrine','easel':'easel_canvas','tank':'aquarium_tank_wall','jelly':'jellyfish_column',
  'bike':'spin_bike','mat':'yoga_mat_roll','shower':'gym_shower_stall','backdrop':'studio_backdrop','kitchen':'kitchen_unit',
  'shoerack':'shoe_display_rack','tryshoes':'shoe_try_bench','vaultbox':'vaulting_box','gymmat':'gym_mat_stack','crib':'baby_crib','ultra':'ultrasound_cart'}
 PLACE_TRIPO={('rack','swimwear'):'swimsuit_rack',('rack','yukata'):'yukata_rack',('rack','lingerie'):'lingerie_mannequin',('display','phone_shop'):'phone_display',
  ('counter_seats','ramen'):'ramen_counter',('counter_seats','izakaya'):'izakaya_lantern_bar',('counter','crepe'):'crepe_stand',
  ('counter','fastfood'):'fastfood_counter',('shelf','manga_cafe'):'manga_shelf'}
 # world-tripo-v1 pieces share the same path table
 wp={q['id']:q for q in json.loads((ROOT/'output/street-social-city-production/world-tripo-v1/prepared.json').read_text('utf-8-sig'))['assets']}
 for r in json.loads((ROOT/'output/street-social-city-production/world-tripo-v1/remeshed.json').read_text('utf-8-sig'))['assets']:
  p=wp[r['id']];ltr.setdefault(p['key'],r['path'] if r.get('triangles',1e9)<p.get('triangles',0) else p['path'])
 def tripo_mesh(key):
  if key in ltm:return ltm[key]
  ltm[key]=None;path=ltr.get(key)
  if path:
   src=(ROOT/'Tools/street_city_activity_native_payload.lua').read_text('utf8').split('def import_one(',1)[1].split('def simple_water(',1)[0]
   ns=dict(globals());ns.update(PREFIX='/Game/UniversityCity/LifeTripoV1',KEEP=[],save=lambda a:EAL.save_loaded_asset(a,False))
   exec('def import_one('+src,ns);ltm[key]=ns['import_one'](type(ROOT)(path),'lt-'+key,0,True)
  return ltm[key]
 def tripo_swap(t,c,yaw,w,dd,h,key,spawned):
  mesh=tripo_mesh(key)
  if not mesh or not spawned:return
  bb=mesh.get_bounding_box();lo,hi=bb.min,bb.max;ex,ey,ez=hi.x-lo.x,hi.y-lo.y,hi.z-lo.z
  # the model's long horizontal side goes along the recipe's long side (across = w, along the facing = dd)
  rot=90 if (w>=dd)==(ex>ey) else 0;fw,ac=(ey,ex) if rot else (ex,ey)
  s=min(dd/max(fw,1),w/max(ac,1),h/max(ez,1));a=math.radians(yaw+rot);cx,cy=(lo.x+hi.x)/2,(lo.y+hi.y)/2
  p=unreal.Vector(c.x-(cx*math.cos(a)-cy*math.sin(a))*s,c.y-(cx*math.sin(a)+cy*math.cos(a))*s,c.z-lo.z*s)
  _ls_spawn(t+'_Tripo',mesh,p,yaw+rot,[s,s,s],None,False)
  for b in spawned:b.static_mesh_component.set_visibility(False);b.static_mesh_component.set_cast_shadow(False)
  tripo_used.append(dict(actor=t,key=key,scale=s))
 REC={'rack':(r_rack,130,140,180,True),'fitting':(r_fitting,135,210,225,True),'mirror':(r_mirror,100,120,210,True),'counter':(r_counter,170,150,120,True),
  'checkout':(r_checkout,170,150,120,True),'bar':(r_bar,170,150,120,True),'case':(r_case,160,150,115,False),'display':(r_display,160,150,95,False),
  'table':(r_table2,90,250,80,False),'grill':(r_grill,90,250,80,False),'try':(r_try,90,250,80,False),'counter_seats':(r_counter_seats,310,200,110,True),
  'conveyor':(r_conveyor,470,200,110,True),'booth':(r_booth,130,320,100,False),'claw':(r_claw,95,180,200,False),'rhythm':(r_rhythm,90,190,185,False),
  'racing':(r_racing,90,250,185,False),'photobooth':(r_photobooth,195,230,230,False),'dental':(r_dental,170,260,200,False),'nail':(r_nail,110,200,110,False),
  'cats':(r_cats,170,260,160,False),'mbooth':(r_mbooth,210,240,170,False),'shelf':(r_shelf,210,140,210,True),'aisle':(r_aisle,310,260,175,False),
  'fresh':(r_fresh,210,160,100,True),'cart':(r_cart,90,200,95,False),'ticket':(r_ticket,70,140,175,True),'bench':(r_bench,190,110,50,False),
  'lane':(r_lane,145,960,40,False),'billiards':(r_billiards,330,290,80,False),'bed':(r_bed,230,130,200,False),'desk':(r_desk,130,200,80,True),
  'recliner':(r_recliner,160,200,70,False),'kitchen':(r_kitchen,250,170,100,True),'atm':(r_atm,80,150,155,True),'backdrop':(r_backdrop,290,520,255,True),
  'concession':(r_named_counter('concession'),170,150,120,True),'shop':(r_named_counter('shop'),170,150,120,True),'doctor':(r_doctor,180,200,80,False),
  'seatbench':(r_seatbench,190,110,90,False),'exhibit':(r_exhibit,90,200,150,False),'easel':(r_easel,80,160,165,False),'weights':(r_weights,190,180,115,True),
  'locker':(r_locker,190,130,195,True),'shower':(r_shower,115,170,225,True),'tank':(r_tank,430,260,240,True),'jelly':(r_jelly,100,200,260,False),'vend':(r_vend,110,190,195,True),
  'shoerack':(r_shoerack,210,140,210,True),'tryshoes':(r_tryshoes,130,170,60,False),'vaultbox':(r_vaultbox,130,170,110,True),'gymmat':(r_gymmat,210,130,35,True),'crib':(r_crib,130,120,95,True),'ultra':(r_ultra,70,100,150,True),
  'changing_w':(r_changing('changing_women'),135,210,225,True),'changing_m':(r_changing('changing_men'),135,210,225,True),'changing':(r_changing('changing'),135,210,225,True),
  'curtain':(r_curtain,230,90,225,False),'telescope':(r_telescope,80,120,150,False),'bleacher':(r_bleacher,490,190,140,True),
  'net':(r_net,920,320,250,False),'pingpong':(r_pingpong,190,500,80,False),'treadmill':(r_treadmill,90,220,140,False),'bike':(r_bike,60,170,100,False),'mat':(r_mat,80,200,20,False)}
 def roomreg(rid):
  a=ar.get(rid)
  if not a:return None
  return ([a['min'][0]+30,a['min'][1]+30],[a['max'][0]-30,a['max'][1]-30]),V(a['door']),a['min'][2]
 def shopreg(b):
  sb=shopbox(b);d=shopdoor(b)
  return (sb[2],d,1200.) if sb and d else None
 # every open door the physics replay walks through (side and support doors too, not only the room's main door):
 # the newest physics plan's player-capsule sweeps; pieces keep 1.5 m off both ends of each
 import glob
 pp=sorted(glob.glob(str(ROOT/'output/street-social-city-production/motel-v1/physics-*-plan.json')))
 opendoors=[]
 if pp:
  for s in json.loads(open(pp[-1],encoding='utf8').read()).get('sweeps',[]):
   if s.get('kind')=='open_door_player_capsule':opendoors+=[V(s['start']),V(s['end'])]
 def dress(place,where,plan,newplace=None,reach=1600):
  _ls_note('dress %s %s'%(place,[k for k,n in plan]))
  if not where:skipped.append(dict(place=place,reason='room not found'));return
  reg,d,z=where;c0=unreal.Vector((reg[0][0]+reg[1][0])/2,(reg[0][1]+reg[1][1])/2,z);res=[(d,150)]
  res+=[(p,150) for p in opendoors if reg[0][0]-200<=p.x<=reg[1][0]+200 and reg[0][1]-200<=p.y<=reg[1][1]+200 and abs(p.z-z)<300]
  if newplace:items.append(dict(place=place,anchor='door',pos=num(d),yaw=0,actor=newplace[0],building=newplace[1],name=newplace[2],rooms=[dict(min=[reg[0][0]-80,reg[0][1]-80,z-30],max=[reg[1][0]+80,reg[1][1]+80,z+400])]))
  for key,n in plan:
   fn,w,dd,h,wall=REC[key]
   for k in range(n):
    best=None
    st=25 if reach<=1600 else 75;dl=time.time()+45
    for r in range(0,reach+1,st):
     if time.time()>dl:break
     m=max(1,int(2*math.pi*max(r,1)/st))
     for q in range(m):
      a=2*math.pi*q/m;c=unreal.Vector(c0.x+r*math.cos(a),c0.y+r*math.sin(a),z)
      if not(reg[0][0]<=c.x<=reg[1][0] and reg[0][1]<=c.y<=reg[1][1]):continue
      if any((c-unreal.Vector(p.x,p.y,z)).length()<rr+max(w,dd)*.45 for p,rr in res):continue
      for yaw in (0,90,180,270):
       if not _ls_fits(world,c,yaw,w,dd,h,z,10):continue
       if wall and not _ls_wall_behind(world,c,yaw,dd,z):continue
       best=(c,yaw);break
      if best:break
     if best:break
    if not best:skipped.append(dict(place=place,reason='no spot for %s #%d'%(key,k+1)));break
    c,yaw=best;res.append((c,max(w,dd)*.45));t='LoverSpot_R2_%s_%s%d'%(place,key,cnt.get((place,'_'+key),0)+1);cnt[(place,'_'+key)]=cnt.get((place,'_'+key),0)+1
    key2=PLACE_TRIPO.get((key,place),TRIPO.get(key));_LS_REC[0]=[] if key2 else None
    try:fn(t,c,yaw,place)
    finally:spawned=_LS_REC[0];_LS_REC[0]=None
    if key2:tripo_swap(t,c,yaw,w,dd,h,key2,spawned)
  views.append(dict(id='R2-%s-%d'%(place,len(views)),eye=num(unreal.Vector(d.x,d.y,z+180)),target=num(unreal.Vector(c0.x,c0.y,z+90)),fov=90,hour=15))
 S=lambda b,name:(('%s_F01'%b),b,name)
 for rid in ('m1-0201','m1-0202','m1-0203','m1-0204','m1-0205','m1-0301','m1-0302','m1-0303','m1-0304'):dress('clothing',roomreg(rid),[('rack',2),('fitting',1),('mirror',1),('counter',1),('seatbench',1)])
 for b in ('S10','S30','S46','S94'):dress('clothing_'+b.lower(),shopreg(b),[('fitting',1),('mirror',1),('rack',2),('counter',1),('seatbench',1)],S(b,b+' 服飾店'))
 dress('lingerie',roomreg('m1-0206'),[('rack',2),('fitting',2),('mirror',1),('counter',1),('seatbench',1)])
 dress('swimwear',shopreg('S58'),[('rack',3),('fitting',2),('mirror',1),('counter',1),('seatbench',1)],S('S58','泳裝店（S58 改建）'))
 dress('yukata',shopreg('S76'),[('rack',3),('fitting',2),('mirror',1),('counter',1),('seatbench',1)],S('S76','浴衣租借（S76 改建）'))
 # the department store's own floors (c-conquest 10.4): zones join `department` as women_*, men_*, shoes_*, accessory_*
 dress('dept_women',roomreg('m1-0207'),[('rack',3),('fitting',2),('mirror',1),('counter',1),('seatbench',1)])
 dress('dept_men',roomreg('m1-0305'),[('rack',3),('fitting',2),('mirror',1),('counter',1),('seatbench',1)])
 dress('dept_accessory',roomreg('m1-0208'),[('rack',2),('fitting',1),('mirror',1),('counter',1),('seatbench',1)])
 for rid in ('m1-0401','m1-0402','m1-0403'):dress('dept_shoes',roomreg(rid),[('shoerack',3),('tryshoes',2),('mirror',1),('counter',1)])
 dress('gym_storage',roomreg('sp-0406'),[('vaultbox',2),('gymmat',2)],S('SP','體育倉庫'))
 dress('fixtures',roomreg('cv-0101'),[('crib',1),('ultra',1)])
 dress('optician',roomreg('m1-0407'),[('counter',1),('mirror',1),('try',2)])
 dress('jewelry',roomreg('m1-0105'),[('case',3),('counter',1),('mirror',1)])
 dress('phone_shop',roomreg('m1-0701'),[('display',3),('counter',1)])
 dress('ramen',roomreg('m1-0901'),[('ticket',1),('counter_seats',1),('table',2)])
 dress('arcade',roomreg('m1-0807'),[('claw',4),('photobooth',1)]);dress('arcade',roomreg('m1-0806'),[('rhythm',1),('racing',2),('counter',1)])
 dress('dentist',roomreg('cv-0102'),[('dental',2),('counter',1)])
 dress('nail',shopreg('S59'),[('nail',3),('counter',1),('bench',1)],S('S59','美甲店（S59 改建）'))
 dress('supermarket',shopreg('S72'),[('aisle',3),('fresh',1),('checkout',2),('cart',1)],S('S72','超市（S72 改建）'))
 dress('sushi',shopreg('S70'),[('conveyor',1),('booth',2),('counter',1)],S('S70','迴轉壽司（S70 改建）'))
 dress('yakiniku',shopreg('S88'),[('grill',4),('counter',1)],S('S88','燒肉店（S88 改建）'))
 dress('izakaya',shopreg('S52'),[('counter_seats',1),('booth',2),('bar',1)],S('S52','居酒屋（S52 改建）'))
 dress('crepe',shopreg('S69'),[('counter',1),('bench',2)],S('S69','可麗餅店（S69 改建）'))
 dress('fastfood',shopreg('S41'),[('counter',1),('table',4)],S('S41','速食店（S41 改建）'))
 dress('cat_cafe',shopreg('S67'),[('cats',2),('table',2),('counter',1)],S('S67','貓咪咖啡（S67 改建）'))
 dress('manga_cafe',shopreg('S73'),[('mbooth',3),('shelf',2),('counter',1)],S('S73','漫畫網咖（S73 改建）'))
 dress('bowling',shopreg('S79'),[('lane',2),('billiards',2),('bench',1),('counter',1)],S('S79','保齡球與撞球（S79 改建）'))
 dress('photo_studio',shopreg('S34'),[('backdrop',1),('fitting',1)])
 ir=roomreg('t1-0105')
 dress('infirmary',ir,[('bed',2),('desk',1)],('T1_F01','T1','保健室（T1-0105 改）'))
 dress('planetarium',roomreg('cv-0401'),[('recliner',4)],('CV_F04','CV','天文館（CV-0401 小劇場改）'))
 dress('bank',roomreg('cv-0202'),[('atm',1)])
 dress('girls_dorm',roomreg('d1-0102'),[('kitchen',1)]);dress('boys_dorm',roomreg('d2-0102'),[('kitchen',1)])
 dress('gym_hall',roomreg('sp-0106'),[('net',1)]);dress('gym_hall',roomreg('sp-0108'),[('pingpong',3)])
 dress('gym',roomreg('sp-0404'),[('treadmill',2),('bike',2),('locker',1),('shower',1)]);dress('gym',roomreg('sp-0501'),[('mat',3)]);dress('gym',roomreg('sp-0403'),[('weights',1)])
 # c-conquest 8.2.2: furnished rooms that still lack the game's anchors
 dress('clinic_general',roomreg('cv-0103'),[('counter',1),('doctor',1)])
 dress('post',roomreg('cv-0201'),[('seatbench',1)])
 dress('cinema',roomreg('cv-0402'),[('ticket',1),('concession',1)])
 dress('museum',roomreg('cv-0403'),[('exhibit',3),('bench',1)]);dress('museum',roomreg('cv-0404'),[('exhibit',2),('bench',1),('shop',1)])
 dress('club_room',roomreg('sc-0202'),[('table',2),('shelf',1)])
 dress('art_room',roomreg('sc-0401'),[('easel',3)])
 # aquarium moves to the CV ocean halls (c-conquest 11-03): a wall tank with koi, a bench and a vending machine in
 # CV-0301, two jellyfish columns in CV-0302; these items replace the S28 ones (same place:anchor keys, written later)
 a1,a2=ar.get('cv-0301'),ar.get('cv-0302')
 if a1 and a2:
  dress('aquarium',roomreg('cv-0301'),[('tank',1),('bench',1),('vend',1)])
  items.append(dict(place='aquarium',anchor='door',pos=a1['door'],yaw=0,actor='CV-0301',building='CV',name='海洋水族館（CV 3F 大水槽展廳、水母展廳）',rooms=[dict(min=a1['min'],max=[a1['max'][0],a1['max'][1],a1['min'][2]+420]),dict(min=a2['min'],max=[a2['max'][0],a2['max'][1],a2['min'][2]+420])]))
  dress('aquarium',roomreg('cv-0302'),[('jelly',2),('bench',1)])
 else:skipped.append(dict(place='aquarium',reason='cv-0301 / cv-0302 not in props areas'))
 # water checks for round 2: the SP pools and the S19 onsen bath (views only)
 for rid in ('sp-0101','s19-0101'):
  a=ar.get(rid)
  if a:views.append(dict(id='R2-water-'+rid,eye=num(unreal.Vector(a['door'][0],a['door'][1],a['min'][2]+250)),target=num(unreal.Vector((a['min'][0]+a['max'][0])/2,(a['min'][1]+a['max'][1])/2,a['min'][2])),fov=90,hour=15))
 # 17. rounds 3-4 outdoors (life-tripo-v1 models at their prepared size): beach play near each lifeguard tower, the summer
 #     festival on the park plaza, a Christmas tree at the campus gate, batting cages by the sports field, a skate rental
 #     and fishing spots at the park pond, barbecue / tents and the amusement park past the playground field. Each piece
 #     stands on a free, level enough lawn / sand spot (the ground is followed), has an invisible box blocker at its
 #     footprint and an anchor in front; places that the game does not have yet get a door item with a box round them.
 gpa=lambda pid,name:next((V(a['pos']) for a in (gp.get(pid) or {}).get('anchors',[]) if a['name']==name),None)
 out_used=[]
 def place_mesh(t,key,c,yaw):
  # a Tripo piece standing on c with no collision: nothing changes for the walkers
  mesh=tripo_mesh(key)
  if not mesh:skipped.append(dict(place=t,reason='no Tripo model for '+key));return
  bb=mesh.get_bounding_box();lo,hi=bb.min,bb.max;a=math.radians(yaw);cx,cy=(lo.x+hi.x)/2,(lo.y+hi.y)/2
  _ls_spawn(t+'_Tripo',mesh,unreal.Vector(c.x-(cx*math.cos(a)-cy*math.sin(a)),c.y-(cx*math.sin(a)+cy*math.cos(a)),c.z-lo.z),yaw,[1,1,1],None,False)
 ENTRY={a['building']:a['door'] for a in json.loads((ROOT/'output/street-social-city-production/places-v1/props.json').read_text('utf8'))['areas'] if a.get('kind')=='building'}
 LAWN='MI_Detail_b6a245f3a69b53317770';ROADS=('','Tripo-ground-campus')
 def ground_mat(x,y,z):
  h=_ls_hit(world,unreal.Vector(x,y,z+300),unreal.Vector(x,y,z-300))
  if not h or len(h)<16 or not h[10]:return None
  try:
   q=h[10].get_material_from_collision_face_index(h[15]);q=q[0] if isinstance(q,tuple) else q;return q.get_name() if q else ''
  except Exception:return None
 RS=[]
 for r_ in json.loads((ROOT/'output/street-social-city-production/world-ground-v1/ground-plan.json').read_text('utf8'))['roads']:
  if r_['kind']!='asphalt':continue
  q_=[((1100-p[1])*100,p[0]*100) for p in r_['points_map_m']];RS+=[(a_,b_,r_['width_m']*50) for a_,b_ in zip(q_,q_[1:])]
 road_pad=[150]
 def on_road(x,y,pad=None):
  pad=road_pad[0] if pad is None else pad
  for a_,b_,hw in RS:
   dx,dy=b_[0]-a_[0],b_[1]-a_[1];l2=dx*dx+dy*dy or 1;t_=max(0,min(1,((x-a_[0])*dx+(y-a_[1])*dy)/l2))
   if math.hypot(x-a_[0]-t_*dx,y-a_[1]-t_*dy)<hw+pad:return True
  return False
 def ground_ok(c,yaw,ex,ey,lawn):
  # never on a road; lawn pieces (the amusement park) only on grass, tested at the piece's centre and corners
  for u,v in [(0,0),(ex/2,ey/2),(-ex/2,ey/2),(ex/2,-ey/2),(-ex/2,-ey/2)]:
   p=_ls_off(c,yaw,u,v);m=ground_mat(p.x,p.y,c.z)
   if on_road(p.x,p.y) or m is None or m in ROADS or (lawn and m!=LAWN):return False
  return True
 # names of the game's lists (c-conquest 8.2) next to the models' own: anchor names stay, these point at the same spot
 DOCN=dict(batting_machine='cage',popcorn_cart='stall',float_rental_rack='rental',skate_rental='rental',christmas_tree='tree',bbq_grill='grill',camping_tent='tent',fishing_spot='fishing',ferris_wheel='ferris',coaster_station='coaster',
  haunted_house='haunted',beach_volleyball_net='volleyball',beach_house_stall='counter',bench_slat_a='bench',stepping_stones='path',flower_bed_round='photo')
 def outdoor(place,hint,plan,rmin=200,rmax=2500,newname=None,margin=60,step=50,lawn=False,block=True,pitch=None):
  _ls_note('outdoor %s %s'%(place,[k for k,n in plan]))
  if not hint:skipped.append(dict(place=place,reason='no hint anchor'));return
  placed=[];av=[]
  for key,n in plan:
   mesh=tripo_mesh(key)
   if not mesh:skipped.append(dict(place=place,reason='no Tripo model for '+key));continue
   bb=mesh.get_bounding_box();lo,hi=bb.min,bb.max;ex,ey,ez=hi.x-lo.x,hi.y-lo.y,hi.z-lo.z
   for k in range(n):
    # the followed ground can be a roof or a deck (the amusement teacups first landed 4 m up): keep only ground within
    # 1.5 m of the hint, ruling the rest out and searching again
    bad=[]
    t0_=time.time()
    for _ in range(120):
     if time.time()-t0_>90:got=None;break
     got=_ls_search(world,hint,hint.z,ey+margin,ex+margin,min(ez,400),[0,90,180,270],rmin=rmin,rmax=rmax,avoid=av+bad,follow=True,tol=20,step=step,region=pitch)
     # pitch: the sports ground's own box; it shares a material with the roads, but no road runs inside it
     if not got or (abs(got[0].z-hint.z)<=150 and (pitch or ground_ok(got[0],got[1],ex,ey,lawn))):break
     bad.append(got[0]);got=None
    if not got:skipped.append(dict(place=place,reason='no free %dx%d cm spot for %s #%d'%(ex,ey,key,k+1)));break
    c,yaw=got;a=math.radians(yaw);cx,cy=(lo.x+hi.x)/2,(lo.y+hi.y)/2
    t='LoverSpot_R3_%s_%s%d'%(place,key,k+1)
    if block:_ls_box(t+'_Block',c,yaw,(ex,ey,min(ez,300)),M['counter']).static_mesh_component.set_visibility(False)
    p=unreal.Vector(c.x-(cx*math.cos(a)-cy*math.sin(a)),c.y-(cx*math.sin(a)+cy*math.cos(a)),c.z-lo.z)
    _ls_spawn(t+'_Tripo',mesh,p,yaw,[1,1,1],None,False)
    av.append(c);placed.append((c,max(ex,ey)/2));q,y=face(c,yaw,ex/2+70);A2(place,key,q,y,t+'_Tripo')
    if key in DOCN:A2(place,DOCN[key],q,y,t+'_Tripo')
    out_used.append(dict(actor=t,key=key,place=place))
  if newname and placed:
   xs=[c.x-r for c,r in placed]+[c.x+r for c,r in placed];ys=[c.y-r for c,r in placed]+[c.y+r for c,r in placed];z=min(c.z for c,r in placed)
   items.append(dict(place=place,anchor='door',pos=num(placed[0][0]),yaw=0,actor='LoverSpot_R3_'+place,building=None,name=newname,
    rooms=[dict(min=[min(xs)-200,min(ys)-200,z-100],max=[max(xs)+200,max(ys)+200,z+3600])]))
  # look down on what was placed from high up (a low eye near the hint can sit inside a building)
  if placed:
   mx,my=sum(c.x for c,r in placed)/len(placed),sum(c.y for c,r in placed)/len(placed);span=max(1500,max(max(abs(c.x-mx),abs(c.y-my))+r for c,r in placed))
   views.append(dict(id='R3-%s-%d'%(place,len(views)),eye=num(unreal.Vector(mx-span,my-span,hint.z+span*1.3)),target=num(unreal.Vector(mx,my,hint.z+100)),fov=80,hour=15))
 for i,nm_ in enumerate(['lifeguard','lifeguard2','lifeguard3','lifeguard4','lifeguard5','lifeguard6']):
  h_=gpa('beach',nm_)
  if not h_:continue
  outdoor('beach',h_,[('changing_hut',1),('sandcastle',1),('watermelon_split',1)]+([('beach_volleyball_net',1),('float_rental_rack',1),('banana_boat',2)] if i==0 else []),rmin=500,rmax=3500,margin=250,step=100)
  if i==0:outdoor('beach_house',h_,[('beach_house_stall',1)],rmin=800,rmax=4000,newname='海之家')
  if i==1:outdoor('jetski',h_,[('jetski',2)],rmin=600,rmax=4000,newname='水上摩托車出租')
 road_pad[0]=450  # the stalls stand well clear of the road edge
 outdoor('festival',gpa('park','plaza'),[('goldfish_stall',1),('shooting_stall',1),('takoyaki_stall',1),('cotton_candy_stall',1),('yoyo_pool',1),('lantern_string',4)],rmin=300,rmax=3000,newname='夏日祭典（公園廣場）')
 outdoor('xmas_tree',gpa('campus_gate','gate'),[('christmas_tree',1)],rmin=800,rmax=3000,newname='聖誕樹廣場（校門）')
 # the `field` anchor is the base of the track mesh, which runs 3 m under the ground: the pitch is at street height
 tf=gpa('campus_sports','field');tf=tf and unreal.Vector(tf.x,tf.y,1205);TB=tf and ((tf.x-5500,tf.y-9700),(tf.x+5500,tf.y+9700))
 outdoor('batting',V([70000,53000,1205]),[('batting_machine',2)],rmin=0,rmax=1800,newname='打擊練習場')
 # the pond anchor is the lake bed: the deck over the lake is at street height, nothing stands in the water
 pd=gpa('park','pond');pd=pd and unreal.Vector(pd.x,pd.y,1205)
 outdoor('skating',gpa('park','plaza'),[('skate_rental',1)],rmin=2500,rmax=6000,step=100,newname='溜冰場（公園廣場）')
 outdoor('fishing',pd,[('fishing_spot',3)],rmin=600,rmax=2000,newname='釣魚台（湖上平台）')
 outdoor('bbq',gpa('playground','field'),[('bbq_grill',3),('camping_tent',3)],rmin=1500,rmax=5000,newname='烤肉露營區')
 outdoor('amusement',gpa('playground','field'),[('ferris_wheel',1),('carousel',1),('teacup_ride',1),('haunted_house',1),('coaster_station',1),('coaster_track',3),('ticket_gate',1),('popcorn_cart',2)],rmin=1500,rmax=20000,lawn=True,newname='遊樂園',margin=300,step=250)
 # a post box outside each home and the post office; no collision, so nothing changes for the walkers
 for pid in ('girls_dorm','boys_dorm','post','hotel'):
  q=gp.get(pid)
  if not q or not q.get('door'):continue
  h=V(q['door']);got=_ls_search(world,h,h.z,60,60,140,[0,90,180,270],rmin=250,rmax=1000,follow=True,tol=12)
  if not got:skipped.append(dict(place=pid,reason='no spot for mailbox'));continue
  c,yaw=got;t='LoverSpot_Mailbox_'+pid;place_mesh(t,'post_box',c,yaw)
  items.append(dict(place='fixtures',anchor='mailbox_'+pid,pos=num(_ls_off(c,yaw,60)),yaw=yaw-90,actor=t+'_Tripo'))
 # a shoe locker just inside each school entrance, against a wall where one is free
 for b_,e_ in sorted(ENTRY.items()):
  if not re.match('T1|T2|T4|E1|EE|MA|RB|IB|AD|LI|SC|IN',b_):continue
  got=_ls_search(world,V(e_),e_[2],210,60,190,[0,90,180,270],rmin=250,rmax=1200,wall=True,tol=10)
  if not got:skipped.append(dict(place=b_,reason='no spot for shoe lockers'));continue
  c,yaw=got;t='LoverSpot_ShoeLockers_'+b_;place_mesh(t,'shoe_lockers',c,yaw)
 # sports grounds, fitness corners, beach and plaza pieces from world-tripo-v1; no collision so the walks stay as they are
 F=dict(block=False)
 # the sports ground has its own goals: stands behind the goal lines, benches on the sidelines, lights in the track's corners
 if tf:
  for k,(key,x,y,yw) in enumerate((('bleacher_b',60812,22300,0),('bleacher_b',60812,37700,180),('scoreboard',60812,38600,180),('dugout',64600,29000,180),('dugout',64600,31000,180),('umpire_chair',64600,27000,180),('umpire_chair',57000,33000,0),
    ('floodlight',55500,20500,45),('floodlight',66100,20500,135),('floodlight',55500,39500,-45),('floodlight',66100,39500,-135))):
   place_mesh('LoverSpot_R3_facility_%s%d'%(key,k),key,V([x,y,1205]),yw)
  views.append(dict(id='R5-sports',eye=num(V([52000,30000,4200])),target=num(V([60800,30000,1205])),fov=80,hour=15))
 outdoor('facility',gpa('playground','field'),[('fitness_station_a',2),('fitness_station_b',2)],rmin=800,rmax=6000,lawn=True,**F)
 outdoor('facility',gpa('park','plaza'),[('food_cart_a',1),('food_cart_b',1)],rmin=500,rmax=3000,**F)
 for nm_ in ('lifeguard2','lifeguard4','lifeguard6'):
  h_=gpa('beach',nm_)
  if h_:outdoor('facility',h_,[('beach_umbrella_a',2),('beach_umbrella_b',2),('beach_hut',1),('beach_walkway',3)],rmin=800,rmax=6000,margin=500,step=100,**F)
 # 18. the last pieces of c-conquest 8.2 / 10.4: seats, tables and rooms beside the places above
 _ls_note('R5: start, %d items'%len(items))
 rav=[]
 def ia(place,name):return next((V(i['pos']) for i in items if i['place']==place and i['anchor']==name),None)
 def outdoor_rec(place,hint,plan,rmin=200,rmax=2500,lawn=False):
  # recipe furniture outdoors: same ground tests as outdoor(), the piece stands on the followed ground
  if not hint:skipped.append(dict(place=place,reason='no hint anchor'));return
  for key,n in plan:
   fn,w,dd,h,wall=REC[key]
   for k in range(n):
    bad=[]
    t0_=time.time()
    for _ in range(60):
     if time.time()-t0_>90:got=None;break
     got=_ls_search(world,hint,hint.z,w+60,dd+60,min(h,250),[0,90,180,270],rmin=rmin,rmax=rmax,avoid=rav+bad,follow=True,tol=20,step=50)
     if not got or (abs(got[0].z-hint.z)<=150 and ground_ok(got[0],got[1],dd,w,lawn)):break
     bad.append(got[0]);got=None
    if not got:skipped.append(dict(place=place,reason='no outdoor spot for %s #%d'%(key,k+1)));break
    c,yaw=got;rav.append(c);fn('LoverSpot_R5_%s_%s%d'%(place,key,k+1),c,yaw,place)
 outdoor('amusement',ia('amusement','carousel'),[('bench_slat_a',4)],rmin=300,rmax=3000,lawn=True,**F)
 outdoor('batting',ia('batting','batting_machine'),[('bench_slat_a',2)],rmin=300,rmax=2000,**F)
 outdoor('fishing',pd,[('bench_slat_a',1)],rmin=600,rmax=2000,**F)
 outdoor('skating',ia('skating','skate_rental'),[('bench_slat_a',2)],rmin=200,rmax=2500,**F)
 outdoor('xmas_tree',ia('xmas_tree','christmas_tree'),[('bench_slat_a',2)],rmin=300,rmax=2000,**F)
 outdoor_rec('bbq',ia('bbq','bbq_grill'),[('table',3)],rmin=300,rmax=2500)
 outdoor_rec('beach_house',ia('beach_house','beach_house_stall'),[('table',3),('shower',1)],rmin=300,rmax=1500)
 outdoor_rec('beach',gpa('beach','lifeguard'),[('locker',2)],rmin=400,rmax=3000)
 # the skating rink: a thin ice sheet with low boards near the rental, walkers cross it freely
 h_=ia('skating','skate_rental');got=h_ and _ls_search(world,h_,h_.z,1660,1060,60,[0,90],rmin=800,rmax=5000,follow=True,tol=25,step=100)
 if got:
  c,yaw=got;ice=R2mat('Ice',(.82,.9,.96),.08);_ls_box('LoverSpot_R5_rink',c,yaw,(1000,1600,4),ice,False)
  for s in (-1,1):_ls_box('LoverSpot_R5_rink_BoardA%+d'%s,_ls_off(c,yaw,s*500),yaw,(8,1600,70),M['wood'],False);_ls_box('LoverSpot_R5_rink_BoardB%+d'%s,_ls_off(c,yaw,0,s*800),yaw,(1000,8,70),M['wood'],False)
  A2('skating','rink',c,yaw,'LoverSpot_R5_rink')
 else:skipped.append(dict(place='skating',reason='no spot for the rink'))
 # sports halls: courts are the rooms themselves, stands and changing booths along the walls
 for rid in ('sp-0104','sp-0106','sp-0108'):
  a=ar.get(rid)
  if a:A2('gym_hall','court',V([(a['min'][0]+a['max'][0])/2,(a['min'][1]+a['max'][1])/2,a['min'][2]]),0,rid.upper())
 dress('gym_hall',roomreg('sp-0104'),[('bleacher',2),('changing_w',1),('changing_m',1)],reach=4000)
 dress('gym_hall',roomreg('sp-0106'),[('bleacher',1)],reach=4000)
 dress('infirmary',ir,[('curtain',2)])
 dress('photo_studio',shopreg('S34'),[('seatbench',1),('changing',1)])
 a=ar.get('cv-0401')
 if a:A2('planetarium','dome',V([(a['min'][0]+a['max'][0])/2,(a['min'][1]+a['max'][1])/2,a['min'][2]]),0,'CV-0401')
 # school changing rooms: two curtained booths in a ground floor room of each teaching building (doc 10.4); the lobbies
 # stay clear, a booth there stood on a walking route. The last rooms first: they are the ones furthest from the entrance
 for b_ in sorted(ENTRY):
  if not re.match('T1|T2|T4|E1|EE|MA|RB|IB|AD|LI|SC|IN',b_):continue
  rooms=sorted((r for r in ar if re.match(b_.lower()+'-01',r)),reverse=True);n0=len(skipped);done_=False
  for rid in rooms:
   before=len(items);dress('fixtures_changing_%s_x'%b_,roomreg(rid),[('changing',2)])
   if len(items)-before>=1:done_=True;break
  del skipped[n0:]
  if not done_:skipped.append(dict(place=b_,reason='no ground floor room takes a changing booth'))
 _ls_note('R5: rooms done, %d items'%len(items))
 # the hill (Tools/build_street_city_hill.lua) and the flower field beside it, on the open west lawns
 def lawn_spot(hints,w,d,h):
  # the 20 m ground probe: centres whose whole footprint reads lawn, nearest the hints first, at most 40 real box tests
  pts=json.loads((ROOT/'output/street-social-city-production/world-tripo-v1/probe.json').read_text('utf8'))['points']
  lawn={(p[0],p[1]) for p in pts if p[3].endswith(LAWN) and abs(p[2]-1205)<=20};rr=int(w/2//2000+1)*2000
  ok_=[c for c in lawn if all((c[0]+i,c[1]+j) in lawn for i in range(-rr,rr+1,2000) for j in range(-rr,rr+1,2000))]
  ok_.sort(key=lambda c:min(math.hypot(c[0]-x,c[1]-y) for x,y in hints))
  for c in ok_[:160]:
   g=_ls_hit(world,V([c[0],c[1],1800]),V([c[0],c[1],600]))
   if g and _ls_fits(world,g[4],0,w*.68,d*.68,h,g[4].z,30):return g[4]
  return None
 def lawn_mat(c):
  h=_ls_hit(world,V([c.x,c.y,c.z+300]),V([c.x,c.y,c.z-300]));q=h[10].get_material_from_collision_face_index(h[15]);return q[0] if isinstance(q,tuple) else q
 # the chapel stands on the nearest open lawn to the park; its spot comes from the ground probe like the hill's
 c=lawn_spot([(30000,46000),(30000,30000),(46000,46000)],1100,1100,300)
 if c:
  place_mesh('LoverSpot_R3_church_wedding_chapel1','wedding_chapel',c,0);A2('church','wedding_chapel',_ls_off(c,0,-620),0,'LoverSpot_R3_church_wedding_chapel1_Tripo')
  items.append(dict(place='church',anchor='door',pos=num(_ls_off(c,0,-620)),yaw=0,actor='LoverSpot_R3_church',building=None,name='教堂',rooms=[dict(min=[c.x-800,c.y-800,c.z-100],max=[c.x+800,c.y+800,c.z+1500])]))
  views.append(dict(id='R5-church',eye=num(V([c.x-1800,c.y-1800,c.z+1400])),target=num(c),fov=70,hour=15))
 else:skipped.append(dict(place='church',reason='no lawn for the chapel'))
 ltr['hill']=str(ROOT/'output/street-social-city-production/hill-v1/hill.glb');hm=tripo_mesh('hill')
 c=hm and lawn_spot([(72000,112000),(70000,112000),(72000,114000)],7400,7400,200)
 if c:
  bs=hm.get_editor_property('body_setup');bs.set_editor_property('collision_trace_flag',unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE);EAL.save_loaded_asset(hm,False)
  _ls_spawn('LoverSpot_R5_hill',hm,V([c.x,c.y,c.z-5]),0,[1,1,1],lawn_mat(c),True)
  top=hm.get_bounding_box().max.z+c.z-5;t_=V([c.x,c.y,top])
  items.append(dict(place='hill',anchor='door',pos=num(_ls_off(c,0,-3300)),yaw=0,actor='LoverSpot_R5_hill',building=None,name='小山觀景點',rooms=[dict(min=[c.x-3700,c.y-3700,c.z-100],max=[c.x+3700,c.y+3700,top+400])]))
  place_mesh('LoverSpot_R5_hill_Bench',"bench_slat_a",_ls_off(t_,0,-200),0);A2('hill','bench',_ls_off(t_,0,-150),-90,'LoverSpot_R5_hill_Bench_Tripo')
  A2('hill','view',_ls_off(t_,0,200),-90,'LoverSpot_R5_hill');A2('hill','view',_ls_off(t_,0,0,300),0,'LoverSpot_R5_hill')
  views.append(dict(id='R5-hill',eye=num(unreal.Vector(c.x-6000,c.y-6000,top+2500)),target=num(t_),fov=70,hour=15))
  fp=V([c.x+200,c.y+6400,c.z])
  items.append(dict(place='flower_field',anchor='door',pos=num(_ls_off(fp,0,-2500)),yaw=0,actor='LoverSpot_R5_flower',building=None,name='花海（西側草坪）',rooms=[dict(min=[fp.x-2300,fp.y-1700,c.z-100],max=[fp.x+2300,fp.y+1700,c.z+400])]))
  # the lane through the middle: stepping stones, the photo spot at its centre, benches at the end facing the flowers
  for k,o in enumerate((-1500,-750,750,1500)):
   t_=_ls_off(fp,0,o);place_mesh('LoverSpot_R5_flower_path%d'%k,'stepping_stones',t_,0);A2('flower_field','path',t_,0,'LoverSpot_R5_flower_path%d_Tripo'%k)
  place_mesh('LoverSpot_R5_flower_bed','flower_bed_round',fp,0);A2('flower_field','photo',_ls_off(fp,0,-260),0,'LoverSpot_R5_flower_bed_Tripo')
  for k,o in enumerate((-300,300)):
   t_=_ls_off(fp,0,-2200,o);place_mesh('LoverSpot_R5_flower_bench_slat_a%d'%k,'bench_slat_a',t_,0);A2('flower_field','bench',_ls_off(t_,0,60),-90,'LoverSpot_R5_flower_bench_slat_a%d_Tripo'%k)
  views.append(dict(id='R5-flower',eye=num(_ls_off(fp,0,-3200,0,700)),target=num(fp),fov=75,hour=15))
  # the field itself: 3 m flower patches (Tools/build_street_city_flower_patch.lua) over a 42 x 30 m block, a lane left through the middle
  ltr['flower_patch']=str(ROOT/'output/street-social-city-production/hill-v1/flower_patch.glb');fx0,fy0=c.x+200,c.y+6400;fn=0
  for i in range(-7,8):
   for k in range(-5,6):
    if abs(k)==0:continue
    x,y=fx0+i*280+(k%2)*90,fy0+k*280;g=_ls_hit(world,V([x,y,c.z+300]),V([x,y,c.z-300]))
    if g and abs(g[4].z-c.z)<=60 and not on_road(x,y) and ground_mat(x,y,c.z)==LAWN:fn+=1;place_mesh('LoverSpot_R5_flower%d'%fn,'flower_patch',g[4],(i*53+k*97)%360)
  _ls_note('flower patches %d'%fn)
 else:skipped.append(dict(place='hill',reason='no lawn for the hill'))
 _ls_note('R5: hill and flowers done, %d items'%len(items))
 # the 50 m pool (one water sheet over the three SP halls, deck at 1200): water points, deck edge, ladders, wet rooms
 PW=(77621,22511,82619,33169);pz=1200
 dress('pool',roomreg('sp-0101'),[('changing_w',1),('changing_m',1),('shower',2),('locker',1),('seatbench',2)],reach=3800)
 for x in (78600,80120,81640):
  for y in (24200,27840,31480):A2('pool','swim',V([x,y,1185]),0,'Campus_SP_Water')
 for x,yw in ((PW[2]+50,90),(PW[0]-50,-90)):
  for y in range(23500,33000,2400):
   q=_ls_floor(world,x,y,pz)
   if q is not None and abs(q-pz)<=10:A2('pool','poolside',V([x,y,pz]),yw,'Campus_SP_Water')
 for k,(x,s) in enumerate(((PW[0],1),(PW[2],-1))):
  y=28000+1200*s;t='LoverSpot_R5_PoolLadder%d'%k
  for o in (-22,22):_ls_cyl(t+'_Rail%+d'%o,V([x+8*s,y+o,1090]),2.5,200,M['steel'],False)
  for z_ in (1110,1140,1170):_ls_box(t+'_Rung%d'%z_,V([x+8*s,y,z_]),0,(4,44,3),M['steel'],False)
  A2('pool','ladder',V([x-40*s,y,pz]),90 if s<0 else -90,t+'_Rail-22')
 # the sky cafe's west windows: places to stand looking out, telescopes and benches between them
 dress('observation',roomreg('m1-1006'),[('telescope',2),('seatbench',2)])
 for y in (62700,63400,64100,64800):A2('observation','view',V([42420,y,4980]),90,'M1-1006')
 # flat roofs: a steel fire stair up one wall reaches each from the ground (no stairwell comes through the slabs), rails on
 # all edges with a gap at the stair head, benches. u runs along the wall, v away from it; spots come off the walk routes
 steel=M['steel'];rm=tripo_mesh('waterfront_rail');roof_rooms=[]
 def roof_stair(b,box,side,us,rz):
  bx0,by0,bx1,by1=box;cx,cy=(bx0+bx1)/2,(by0+by1)/2;tag='LoverSpot_R5_%sStair'%b
  def wall(dx,dy):
   h=_ls_hit(world,V([cx+dx*((bx1-bx0)/2+400),cy+dy*((by1-by0)/2+400),rz-150]),V([cx,cy,rz-150]));return h[4]
  X1,X0,Y1,Y0=wall(1,0).x,wall(-1,0).x,wall(0,1).y,wall(0,-1).y
  def P(u,v,z=0):return V([X1+v,u,z]) if side=='n' else V([X0-v,u,z]) if side=='s' else V([u,Y1+v,z]) if side=='e' else V([u,Y0-v,z])
  yw=0 if side in 'ns' else 90;p0=P(us[0],80);gz=_ls_floor(world,p0.x,p0.y,1205) or 1200
  u0=next((u for u in us if _ls_fits(world,P(u+180,150,gz),yw,640,300,300,gz,12)),None)
  if u0 is None:skipped.append(dict(place='rooftop',reason='no clear ground on the %s %s wall, stair placed at the first spot'%(b,side)));u0=us[0]
  va,vb,steps,fl=80,220,12,10;rise=(rz-gz)/(steps*fl);u1=u0+steps*30;z=gz;n=0
  for f in range(fl):
   up=f%2==0;v=va if up else vb
   for s_ in range(steps):
    z+=rise;u=u0+15+30*s_ if up else u1-15-30*s_;n+=1;_ls_box(tag+'_%03d'%n,P(u,v,z-8),yw,(130,30,8),steel)
    if s_%3==0:_ls_cyl(tag+'_Post%03d'%n,P(u,v+(66 if not up else -66),z),2,100,steel,False)
   _ls_box(tag+'_Landing%d'%f,P(u1+70 if up else u0-70,140,z-8),yw,(300,140,8),steel)
  for k,uc in enumerate((u0-140,u1+140)):_ls_cyl(tag+'_Col%d'%k,P(uc,210,gz),6,rz-gz,steel)
  rx0,rx1,ry0,ry1=X0+40,X1-40,Y0+40,Y1-40;blk='LoverSpot_R5_%sRailBlock'%b
  if rm:
   bb=rm.get_bounding_box();ex,ey=bb.max.x-bb.min.x,bb.max.y-bb.min.y;L=max(ex,ey);ry=90 if ey>ex else 0
   def rail_run(ax,ay,bx,by):
    d=math.hypot(bx-ax,by-ay);yr=math.degrees(math.atan2(by-ay,bx-ax));m=int(d/L)
    for i in range(m):
     t_=(i+.5)*L/d;place_mesh('LoverSpot_R5_%sRail_%d_%d_%d'%(b,ax,ay,i),'waterfront_rail',V([ax+(bx-ax)*t_,ay+(by-ay)*t_,rz]),yr+ry)
    w=_ls_box(blk+'_%d_%d'%(ax,ay),V([(ax+bx)/2,(ay+by)/2,rz]),yr,(d,8,110),M['counter']);w.static_mesh_component.set_visibility(False)
   ga,gb=u0-160,u0+20;runs=dict(n=(rx1,ry0,rx1,ry1),s=(rx0,ry0,rx0,ry1),e=(rx0,ry1,rx1,ry1),w=(rx0,ry0,rx1,ry0))
   for k,(ax,ay,bx,by) in runs.items():
    if k!=side:rail_run(ax,ay,bx,by)
    elif side in 'ns':rail_run(ax,ay,bx,ga);rail_run(ax,gb,bx,by)
    else:rail_run(ax,ay,ga,by);rail_run(gb,ay,bx,by)
  roof_rooms.append(dict(min=[X0,Y0+130,rz-20],max=[X1,Y1-130,rz+400]));head=P(u0-70,-100,rz)
  A2('rooftop','stair_bottom',P(u0-60,80,gz),0,tag+'_001')
  for q,yw2 in ((V([rx1-60,cy,rz]),-90),(V([rx0+60,cy,rz]),90),(V([cx,ry0+60,rz]),180),(V([cx,ry1-60,rz]),0)):A2('rooftop','fence',q,yw2,blk)
  for k,o in enumerate((-.3,0,.3)):
   q=V([cx-(bx1-bx0)*.25,cy+(by1-by0)*o,rz]);place_mesh('LoverSpot_R5_%s_bench_slat_a%d'%(b,k),'bench_slat_a',q,0);A2('rooftop','bench',V([q.x+60,q.y,rz]),-90,'LoverSpot_R5_%s_bench_slat_a%d_Tripo'%(b,k))
  return head,gz
 t1_head,_g=roof_stair('T1',(61500,49468,66500,56531),'n',list(range(50400,55600,200)),3200)
 for b,box,side,u,rz in (('T2',(74500,67468,79500,74531),'s',69268,3200),('T4',(61500,41468,66500,48531),'w',65100,3200),('LI',(55500,58268,60500,66731),'n',63668,3200),('D1',(90700,31968,95700,42031),'w',94300,3420),('D2',(90700,55968,95700,66031),'e',91300,3420)):
  roof_stair(b,box,side,[u,u+200,u-200,u+400,u-400],rz)
 items.append(dict(place='rooftop',anchor='door',pos=num(t1_head),yaw=0,actor='LoverSpot_R5_T1Stair',building='T1',name='屋頂',rooms=roof_rooms))
 views.append(dict(id='R5-rooftop',eye=num(V([68500,50500,4100])),target=num(V([64500,53000,3200])),fov=80,hour=15))
 views.append(dict(id='R6-roof-D2',eye=num(V([91300,68000,4300])),target=num(V([93000,62000,3420])),fov=80,hour=15))
 _ls_note('R5: pool, observation, rooftop done, %d items'%len(items))
 # boats on the park lake: open water cells of the lake box (traces land on the lake bed, the deck reads street height),
 # the pier reaches from the deck edge nearest the open water
 def water_cells(x0,y0_,x1,y1_,step=200):
  cell={}
  for x in range(x0,x1,step):
   for y in range(y0_,y1_,step):
    h=_ls_hit(world,V([x,y,1900]),V([x,y,800]));cell[(x,y)]=h[4].z if h else None
  return cell,[k for k,v in cell.items() if v is not None and v<=1110 and all((cell.get((k[0]+i*step,k[1]+j*step)) or 9999)<=1110 for i in (-2,-1,0,1,2) for j in (-1,0,1))]
 cell,free=water_cells(83250,74500,88500,78250);land=[k for k,v in cell.items() if v is None or v>1110]
 used=[]
 def on_water(key,n,place,base):
  got=0
  for k in sorted(free,key=lambda q:-min([math.hypot(q[0]-d_[0],q[1]-d_[1]) for d_ in land] or [0])):
   if got>=n:break
   if any(math.hypot(k[0]-u[0],k[1]-u[1])<450 for u in used):continue
   used.append(k);got+=1;t='LoverSpot_R5_%s%d'%(key,got);place_mesh(t,key,V([k[0],k[1],1092]),(k[0]+k[1])%360);A2(place,base,V([k[0],k[1],1100]),0,t+'_Tripo')
  if got<n:skipped.append(dict(place=place,reason='open water for %d of %d %s'%(got,n,key)))
 on_water('swan_boat',4,'boat','swan_boat');on_water('rowing_boat',2,'boat','rowing_boat')
 if free:
  deck=[k for k,v in cell.items() if v is not None and v>=1180];w0=min(free,key=lambda q:min([math.hypot(q[0]-d_[0],q[1]-d_[1]) for d_ in deck] or [9e9]));d0=min(deck,key=lambda q:math.hypot(q[0]-w0[0],q[1]-w0[1])) if deck else None
  if d0:
   yw=math.degrees(math.atan2(w0[1]-d0[1],w0[0]-d0[0]));place_mesh('LoverSpot_R5_boat_pier','lake_pier',V([(w0[0]+d0[0])/2,(w0[1]+d0[1])/2,1080]),yw)
   items.append(dict(place='boat',anchor='door',pos=[d0[0],d0[1],cell[d0]],yaw=0,actor='LoverSpot_R5_boat_pier',building=None,name='天鵝船碼頭（公園湖）',rooms=[dict(min=[83250,74500,1000],max=[88500,78250,1800])]))
   A2('boat','dock',V([d0[0],d0[1],cell[d0]]),yw-90,'LoverSpot_R5_boat_pier_Tripo')
   views.append(dict(id='R5-boat',eye=num(V([d0[0]-1500,d0[1]-1500,2200])),target=num(V([w0[0],w0[1],1100])),fov=80,hour=15))
 else:skipped.append(dict(place='boat',reason='no open water in the lake box'))
 # the sea: from each lifeguard tower straight toward the water, the shore is where the ground drops to the sea sheet
 def shore(h_):
  x=h_.x
  while x>0:
   h=_ls_hit(world,V([x,h_.y,1900]),V([x,h_.y,800]))
   if h and h[4].z<=1105:return x
   x-=100
  return None
 for i,nm_ in enumerate(['lifeguard','lifeguard2','lifeguard3','lifeguard4','lifeguard5','lifeguard6']):
  h_=gpa('beach',nm_);sx=h_ and shore(h_)
  if not sx:skipped.append(dict(place='beach',reason='no shore from '+nm_));continue
  for d_,o in ((700,-300),(1200,300)):A2('beach','swim',V([sx-d_,h_.y+o,1100]),90,'G_Water')
  if i==1:
   place_mesh('LoverSpot_R5_jetski_pier','lake_pier',V([sx-300,h_.y+600,1085]),0)
   A2('jetski','dock',V([sx+80,h_.y+600,1200]),90,'LoverSpot_R5_jetski_pier_Tripo')
   views.append(dict(id='R5-jetski-dock',eye=num(V([sx+1500,h_.y-800,1900])),target=num(V([sx-300,h_.y+600,1100])),fov=70,hour=15))
 # the landscape scatter of world-tripo-v1 read lawn collision under some roads: take those instances out
 cut=0;LK=re.compile('WorldTripo_(boxwood|azalea|hydrangea|shrub|ornamental|boulder|meadow|flower|planter_wood|stepping)')
 for a_ in SUB.get_all_level_actors():
  if not LK.match(a_.get_actor_label()):continue
  c_=a_.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
  if not c_:continue
  for i in range(c_.get_instance_count()-1,-1,-1):
   t_=c_.get_instance_transform(i,True).translation
   # the Tripo meadow patches read as crumpled sheets from the ground: none stay
   if 'meadow' in a_.get_actor_label() or on_road(t_.x,t_.y,60):c_.remove_instance(i);cut+=1
 _ls_note('road scatter removed %d'%cut)
 # new-game spawn outside the boys' dorm: only a check view, nothing placed
 sp=next((a for a in (gp.get('boys_dorm') or {}).get('anchors',[]) if a['name']=='spawn'),None)
 if sp:views.append(dict(id='LS-spawn',eye=num(_ls_off(V(sp['pos']),sp['yaw']+90,-500,0,250)),target=num(_ls_off(V(sp['pos']),sp['yaw']+90,300,0,120)),fov=80,hour=9))
 # round 3 (c-conquest 8.2.3): real tubs and cribs in the homes, more of the few-of-a-kind places
 _ls_note('R6: start, %d items'%len(items))
 pl6=json.loads((ROOT/'output/street-social-city-production/places-v1/places.json').read_text('utf8'))['places']
 def fit_home(p,key,base,start,rings):
  # a Tripo piece against the room's free floor, searched outward from `start`; the anchor stands on the piece
  mesh=tripo_mesh(key)
  if not mesh:return False
  bb=mesh.get_bounding_box();ex,ey,ez=bb.max.x-bb.min.x,bb.max.y-bb.min.y,bb.max.z-bb.min.z;rm=p['room'];lo,hi,z=rm['min'],rm['max'],rm['min'][2];door=p.get('door') or [(rm['min'][0]+rm['max'][0])/2,(rm['min'][1]+rm['max'][1])/2];dl=time.time()+20
  for r in rings:
   for q in range(12 if r else 1):
    if time.time()>dl:return False
    a=q*math.pi/6;c=V([start[0]+r*math.cos(a),start[1]+r*math.sin(a),z])
    if math.hypot(c.x-door[0],c.y-door[1])<130+max(ex,ey)/2:continue
    for yaw in (0,90):
     hx,hy=(ex/2,ey/2) if yaw==0 else (ey/2,ex/2)
     if c.x-hx<lo[0]+8 or c.x+hx>hi[0]-8 or c.y-hy<lo[1]+8 or c.y+hy>hi[1]-8:continue
     if _ls_fits(world,c,yaw,ey,ex,min(ez,110),z,8):
      t='LoverSpot_R6_%s_%s'%(key,p['id']);place_mesh(t,key,c,yaw);A2(p['id'],base,c,yaw,t+'_Tripo');return True
  return False
 tubs=cribs=0
 for p in pl6:
  b=str(p.get('building') or '');an=p.get('anchors') or []
  if p.get('kind') not in ('room_apartment','room_dorm') or 'min' not in (p.get('room') or {}) or not re.match('^(R1|R2|D[1-4]|S[0-9]+)$',b):continue
  sh=next((a for a in an if a['name'].startswith('shower')),None)
  if sh and not any(a.get('asset')=='bathtub' for a in an):
   if fit_home(p,'bathtub','bath',sh['pos'],range(110,620,35)):tubs+=1
   else:skipped.append(dict(place=p['id'],reason='no floor for a tub'))
  if b in ('R1','R2'):
   rc=[(p['room']['min'][0]+p['room']['max'][0])/2,(p['room']['min'][1]+p['room']['max'][1])/2]
   if fit_home(p,'baby_crib','crib',rc,range(0,620,45)):cribs+=1
   else:skipped.append(dict(place=p['id'],reason='no floor for a crib'))
 _ls_note('R6: %d tubs, %d cribs'%(tubs,cribs))
 dress('fixtures',roomreg('cv-0101'),[('crib',2),('ultra',2)])
 dress('infirmary',ir,[('bed',2)])
 dress('fixtures',roomreg('cv-0103'),[('ultra',1)])
 dress('gym_storage',roomreg('sp-0406'),[('vaultbox',4)])
 tr_=next(p for p in pl6 if p['id']=='tr');q_=tr_['room']
 dress('station',(([q_['min'][0]+30,q_['min'][1]+30],[q_['max'][0]-30,q_['max'][1]-30]),V(tr_['door']),q_['min'][2]),[('ticket',3)],('TR_F01','TR','交通站'),reach=2600)
 cc=ia('church','wedding_chapel')
 if cc:
  for k,(fw,sd) in enumerate(((-150,0),(-300,-120),(-300,120),(-450,0))):A2('church','wedding_aisle',_ls_off(cc,0,fw,sd),0,'LoverSpot_R3_church_wedding_chapel1_Tripo')
 # real balconies: a slab on the nearest outside wall of each home (Tools/build_street_city_balcony.lua); the facades are one
 # solid mesh, so the door on the wall is the model's and characters are placed onto the slab
 ltr['balcony']=str(ROOT/'output/street-social-city-production/hill-v1/balcony.glb');used=[]
 # the stair runs of the walk plan: a wall beside one is the stairwell's inner wall, not the facade
 stairs_=set()
 for r_ in json.loads(sorted((ROOT/'output/street-social-city-production/motel-v1').glob('physics-*-plan.json'))[-1].read_text('utf8'))['rays']:
  if r_.get('kind')=='stair_headroom':stairs_.add((round(r_['start'][0]/200),round(r_['start'][1]/200)))
 # outer footprints: R and H have stair towers and light wells inside them, their walls are not the facade
 FOOT=dict(r1=(42272,8555,48728,16445),r2=(30272,8555,36728,16445),h1=(26772,63955,32435,77045),d1=(90700,31968,95700,42031),d2=(90700,55968,95700,66031),d3=(90700,43968,95700,54031),d4=(90700,19968,95700,30031))
 def balcony(rid,lo,hi):
  z=lo[2];cx,cy=(lo[0]+hi[0])/2,(lo[1]+hi[1])/2;hx,hy=(hi[0]-lo[0])/2,(hi[1]-lo[1])/2
  if z<1400:return False
  for far in (300,600,1200,2100,3200):
   for dx,dy,half in ((1,0,hx),(-1,0,hx),(0,1,hy),(0,-1,hy)):
    sx,sy=cx+dx*(half+far),cy+dy*(half+far)
    g=_ls_hit(world,V([sx,sy,z+150]),V([sx,sy,z-3000]))
    if not g or g[4].z>z-150:continue
    h=_ls_hit(world,V([sx,sy,z+120]),V([cx,cy,z+120]))
    if not h:continue
    p=h[4];ok=True
    for o in (-150,150):
     q=_ls_hit(world,V([sx-dy*o,sy+dx*o,z+120]),V([cx-dy*o,cy+dx*o,z+120]))
     if not q or abs((q[4].x-p.x)*dx+(q[4].y-p.y)*dy)>40:ok=False
    # the slab's own spot: open down to the ground and no storey slab over it (a stairwell or a recess is not the facade)
    bx_,by_=p.x+dx*66,p.y+dy*66;g=_ls_hit(world,V([bx_,by_,z+150]),V([bx_,by_,z-3000]))
    if not g or g[4].z>z-150 or _ls_hit(world,V([bx_,by_,z+150]),V([bx_,by_,z+420])):ok=False
    if any((round(bx_/200)+i,round(by_/200)+j) in stairs_ for i in (-2,-1,0,1,2) for j in (-2,-1,0,1,2)):ok=False
    fb=FOOT.get(rid[:2])
    if fb and fb[0]+100<bx_<fb[2]-100 and fb[1]+100<by_<fb[3]-100:ok=False
    if not ok or any(abs(u[2]-z)<50 and math.hypot(u[0]-p.x,u[1]-p.y)<320 for u in used):continue
    c=V([p.x+dx*66,p.y+dy*66,z-14]);yaw=math.degrees(math.atan2(dy,dx));t='LoverSpot_R6_balcony_'+rid
    place_mesh(t,'balcony',c,yaw);w=_ls_box(t+'_Floor',c,yaw,(130,300,14),M['counter']);w.static_mesh_component.set_visibility(False)
    A2(rid,'balcony',V([c.x,c.y,z]),yaw-90,t+'_Tripo');used.append((p.x,p.y,z));return True
  return False
 ca=json.loads((ROOT/'Content/IndependentResources/StreetSocialData/city_anchors.json').read_text('utf8'))['anchors']
 homes=sorted({r['room'] for r in ca if r.get('room') and ('balcony' in r['kinds'] or 'view_window' in r['kinds'])})+sorted(k for k in ar if re.match('^d[1-4]-0[2-6]01$',k))
 nb=0
 for rid in homes:
  a=ar.get(rid)
  if a and 'min' in a and balcony(rid,a['min'],a['max']):nb+=1
 _ls_note('R6: %d balconies of %d homes'%(nb,len(homes)));skipped.append(dict(place='balcony',reason='%d of %d homes'%(nb,len(homes))))
 # world gaps of section 8.1: dune grass along the back of the beach, rocks at the waterline, reeds and lily pads on the
 # lake and canal, the interior Tripo pieces in homes, schools and offices, and lit lamp heads at night
 ng=nr=0
 for i,y in enumerate(range(3000,81000,850)):
  edge=sh_=None
  for x in range(10500,17000,100):
   h=_ls_hit(world,V([x,y,1500]),V([x,y,900]))
   if not h:continue
   if h[4].z>=1100 and sh_ is None:sh_=x
   if h[9] and h[9].get_actor_label()=='WorldEdge_CoastStrip' and h[4].z>1190:edge=(x,h[4].z)
  if edge:
   c=V([edge[0]-80-(i*37)%160,y+(i*61)%300,edge[1]])
   if _ls_fits(world,c,0,160,160,60,c.z,16):t='LoverSpot_R6_dune%d'%i;place_mesh(t,'dune_grass',c,(i*71)%360);ng+=1
  if sh_ and i%7==3:
   t='LoverSpot_R6_rocks%d'%i;place_mesh(t,'coastal_rocks',V([sh_+40,y,1094]),(i*53)%360);nr+=1
 _ls_note('R6: dune %d rocks %d'%(ng,nr));nd=nl=0
 def reed(k,x,y):
  place_mesh('LoverSpot_R6_reed%d'%k,'reeds_a' if k%2 else 'reeds_b',V([x,y,1096]),(k*67)%360)
 for i,x in enumerate(range(16000,108000,1400)):
  wet=[]
  for y in range(82000,98000,100):
   h=_ls_hit(world,V([x,y,1500]),V([x,y,800]))
   if h and h[4].z<1095:wet.append(y)
  if len(wet)<10:continue
  reed(2*i,x,wet[0]+90);reed(2*i+1,x+500,wet[-1]-90);nd+=2
  if i%3==0:place_mesh('LoverSpot_R6_lily%d'%i,'lily_pads',V([x+250,wet[0]+380,1100.5]),(i*29)%360);nl+=1
 edge_=[k for k in free if any((k[0]+i*200,k[1]+j*200) in land or (k[0]+i*200,k[1]+j*200) not in cell for i in (-3,3) for j in (-2,2))]
 for i,k in enumerate(edge_[:16]):reed(500+i,k[0],k[1]);nd+=1
 for i,k in enumerate([k for k in free[::9] if k not in edge_][:8]):place_mesh('LoverSpot_R6_lilylake%d'%i,'lily_pads',V([k[0],k[1],1100.5]),(i*47)%360);nl+=1
 _ls_note('R6: reeds %d lily %d'%(nd,nl));nf=0
 for p in pl6:
  rm_=p.get('room') or {}
  if 'min' not in rm_:continue
  b=str(p.get('building') or '');cx_=[(rm_['min'][0]+rm_['max'][0])/2,(rm_['min'][1]+rm_['max'][1])/2];an={a['name']:a for a in p.get('anchors') or []}
  plan=[]
  if b in ('R1','R2'):plan=[('fridge','fridge',(an.get('kitchen') or {}).get('pos') or cx_),('bookcase_full','bookcase',cx_),('potted_monstera','plant',cx_)]
  elif p.get('kind')=='room_dorm':plan=[('wardrobe','wardrobe',cx_),('dorm_desk','desk',cx_)]
  for key,base,st in plan:
   if fit_home(p,key,base,st,range(0,620,50)):nf+=1
 for rid,key,n in (('t1-0201','lectern',1),('t1-0202','lectern',1),('t2-0201','lectern',1),('t4-0201','lectern',1),('t1-0201','student_desk',4),('t2-0201','student_desk',4),('ad-0201','workstation',4),('ad-0201','office_chair',4),('ad-0202','workstation',4),('ad-0202','monitor_set',2),('ad-0101','sofa_three',2),('ad-0101','potted_monstera',3)):
  a=ar.get(rid)
  if not a or 'min' not in a:skipped.append(dict(place=rid,reason='no room for '+key));continue
  q=dict(id=rid,room=dict(min=a['min'],max=a['max']),door=a.get('door'))
  for k in range(n):
   q['id']='%s_%d'%(rid,k)
   if fit_home(q,key,key,[(a['min'][0]+a['max'][0])/2+k*90,(a['min'][1]+a['max'][1])/2],range(0,1000,60)):nf+=1
 _ls_note('R6: interior pieces %d'%nf);k=0
 # shop counters: the anchor stood on the counter top before the build moved it to the floor (anchor-ground.json keeps that height)
 gf=ROOT/'output/street-social-city-production/places-v1/anchor-ground.json';top={}
 if gf.is_file():
  for s_,to in json.loads(gf.read_text('utf8')).items():
   q=[float(v) for v in s_.split(',')];top[(round(to[0]),round(to[1]))]=q[2]
 for p in pl6:
  for a in p.get('anchors') or []:
   if not a.get('pos'):continue
   z_=top.get((round(a['pos'][0]),round(a['pos'][1])),a['pos'][2])
   if a['name'].startswith('counter') and str(p.get('building') or '').startswith('S') and z_-(p.get('room') or {}).get('min',[0,0,1200])[2]>70:
    k+=1;place_mesh('LoverSpot_R6_register%d'%k,'cash_register',V([a['pos'][0],a['pos'][1],z_]),a.get('yaw',0))
 # lit heads on the Tripo street lamps: opal spheres follow the day-night LampGlowWeight
 opal=EAL.load_asset('/Game/UniversityCity/EnvironmentV1/Materials/M_EnvironmentOpal_01');sph=EAL.load_asset('/Engine/BasicShapes/Sphere');nlamp=0
 for a_ in SUB.get_all_level_actors():
  lb=a_.get_actor_label()
  if not lb.startswith('WorldTripo_lamp_'):continue
  c_=a_.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
  if not c_:continue
  bb=c_.static_mesh.get_bounding_box();ex,ey=bb.max.x-bb.min.x,bb.max.y-bb.min.y;dbl='double' in lb
  for i in range(c_.get_instance_count()):
   tr=c_.get_instance_transform(i,True);p_=tr.translation;s_=tr.scale3d;ya=tr.rotation.rotator().yaw;top=p_.z+bb.max.z*s_.z
   offs=[(bb.min.x*s_.x*.88,0),(bb.max.x*s_.x*.88,0)] if dbl and ex>=ey else [(0,bb.min.y*s_.y*.88),(0,bb.max.y*s_.y*.88)] if dbl else [(0,0)]
   for j,(ox,oy) in enumerate(offs):
    q=_ls_off(V([p_.x,p_.y,top-(14 if dbl else 34)]),ya,ox,oy);nlamp+=1;_ls_spawn('LoverSpot_R6_LampGlow%d'%nlamp,sph,q,0,[.26,.26,.2] if dbl else [.34,.34,.34],opal,False)
 # one warm spot per lamp for the pool of light on the road, on the same night schedule as the path lamps
 nlight=0
 for a_ in SUB.get_all_level_actors():
  lb=a_.get_actor_label()
  if not lb.startswith('WorldTripo_lamp_'):continue
  c_=a_.get_component_by_class(unreal.HierarchicalInstancedStaticMeshComponent)
  if not c_:continue
  bb=c_.static_mesh.get_bounding_box()
  for i in range(c_.get_instance_count()):
   tr=c_.get_instance_transform(i,True);p_=tr.translation;top=p_.z+bb.max.z*tr.scale3d.z;nlight+=1
   l_=SUB.spawn_actor_from_class(unreal.SpotLight,V([p_.x,p_.y,top-30]),unreal.Rotator(pitch=-90));l_.set_actor_label('LoverSpot_R6_LampLight%d'%nlight);l_.tags=[unreal.Name('LoverSpot'),unreal.Name('EnvGroup=Path'),unreal.Name('EnvLumens=1500')];l_.set_folder_path('UniversityCity/LoverSpotsV1');c=l_.light_component;c.set_mobility(unreal.ComponentMobility.MOVABLE);c.set_editor_property('intensity_units',unreal.LightUnits.LUMENS);c.set_intensity(1500);c.set_temperature(3200);c.set_editor_property('use_temperature',True);c.set_editor_property('attenuation_radius',1500);c.set_editor_property('inner_cone_angle',50);c.set_editor_property('outer_cone_angle',75);c.set_editor_property('source_radius',12);c.set_cast_shadows(False)
 # newsstands, cafe sets and lanterns the street dressing left standing on the road: to the nearest pavement
 nm_=0
 for a_ in SUB.get_all_level_actors():
  lb=a_.get_actor_label()
  if not (lb.startswith('Landmark_newsstand') or lb.startswith('Landmark_cafe_set') or lb.startswith('ResortLantern_CV_')):continue
  o_=a_.get_actor_bounds(False)[0];l0=a_.get_actor_location()
  if not on_road(o_.x,o_.y,60):continue
  best=None
  for r in range(200,1401,100):
   for q in range(16):
    x,y=o_.x+r*math.cos(q*math.pi/8),o_.y+r*math.sin(q*math.pi/8)
    if not on_road(x,y,260):
     g=_ls_floor(world,x,y,1205)
     if g is not None and abs(g-1205)<=20:best=(x-o_.x,y-o_.y,g);break
   if best:break
  if best:a_.set_actor_location(V([l0.x+best[0],l0.y+best[1],l0.z]),False,False);nm_+=1
 skipped.append(dict(place='road_clear',reason='moved %d pieces off the road, %d lamp lights'%(nm_,nlight)))
 _ls_note('R6: lamp heads %d'%nlamp);skipped.append(dict(place='world_gap',reason='dune %d rocks %d reeds %d lily %d interior %d registers %d lamp heads %d'%(ng,nr,nd,nl,nf,k,nlamp)))
 acts={a.get_actor_label():a for a in SUB.get_all_level_actors()}
 acts.get('CityEnvironmentController') and acts['CityEnvironmentController'].prepare_for_save()
 faulthandler.cancel_dump_traceback_later();_ls_note('saving map')
 assert unreal.EditorLevelLibrary.save_current_level();new=sha(MAPFILE)
 installed=read('motel-install');installed.update(parent_map_sha256=LOAD_SHA,map_sha256=new);write('motel-install',installed)
 (LS_OUT/'lover-spots-views.json').write_text(json.dumps(views,indent=1),'utf8')
 (LS_OUT/('lover-spots-install-'+time.strftime('%Y%m%d-%H%M%S')+'.json')).write_text(json.dumps(dict(status='saved_requires_capture_review',map_sha256=new,parent_map_sha256=LOAD_SHA,backup=str(b),items=items,lots=lots,skipped=skipped,tripo=tripo_used,outdoor=out_used),ensure_ascii=False,indent=1),'utf8')
]====]
