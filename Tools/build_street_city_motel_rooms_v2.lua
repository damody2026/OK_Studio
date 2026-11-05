-- Data-driven motel rooms (mass production, Docs/STREET_CITY_MOTEL_ROOM_SPEC_20261025.md): each room is described in
-- output/.../motel-v1/room-specs/*.json and assembled from a procedural component library plus any existing
-- remeshed Tripo furniture. Reuses the approved sample builder's shell, materials, tubs, UV and route check, so
-- openings, garage, bathroom partitions, mirror recess, minibar and the verified walk routes stay unchanged.
-- Usage: lua build_street_city_motel_rooms_v2.lua [room-id ...]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local f=assert(io.open('Tools/build_street_city_motel_sample_rooms.lua','rb'));local src=f:read('*a');f:close()
local body=assert(src:match('local code=%[====%[(.-)%]====%]'))
local helpers=assert(body:match('^(.-)\nROOMS={}'))
local tail=assert(body:match('(\ndef uvs%(o%):.-)\nresults=%[%]'))
local code=helpers..'\n'..tail..'\n'..[====[
_mat0=mat
def mat(key,color=(.5,.5,.5),tex=None,tile=1.0,fit=False,rough=.5,metal=0.,emit=0.,alpha=1.):
 # a grey metal=1 mirror has nothing to reflect in a closed room and renders as a flat blue-grey slab (414, 506 round 7):
 # keep mirrors partly diffuse with a warm silver base so they read as glass under the room's own light
 if metal>=.95 and rough<=.06 and not tex and alpha>=1. and max(color)-min(color)<.08:color,metal,rough=(.78,.74,.7),.65,.12
 # albedo above .85 (bright white paint is ~.8) clipped to flat white under the game's auto exposure: 506 floor, every
 # porcelain tub and sink in the v-bath shots (round 11). Lit (non-emissive) surfaces are scaled down to .85
 if not emit and max(color)>.85:k=.85/max(color);color=tuple(c*k for c in color)
 return _mat0(key,color,tex,tile,fit,rough,metal,emit,alpha)
SPECS={}
for _p in sorted((O/'room-specs').glob('*.json')):SPECS.update({r['id']:r for r in json.loads(_p.read_text('utf8'))['rooms']})
GEN=S/'textures'
def M(d,key=None):
 # material descriptor: preset texture name, or {color,tex,gen,tile,rough,metal,emit,alpha}
 if d is None:return None
 # the red-brown marble read bright orange in game; photos are deep Emperador brown (darkened copy, samples keep theirs)
 if isinstance(d,str):t=TEX_ALIAS.get(d,d);return mat(t,tex=t,tile=TILES.get(d,1.2),rough=ROUGH.get(d,.5))
 tex=TEX_ALIAS.get(d.get('tex'),d.get('tex'))
 if 'gen' in d:tex='gen_'+hashlib.md5((json.dumps(d['gen'],sort_keys=True)+'|cap85').encode()).hexdigest()[:10]
 name=key or ('m_'+hashlib.md5(json.dumps(d,sort_keys=True).encode()).hexdigest()[:10])
 return mat(name,tuple(d.get('color',(.8,.8,.8))),tex=tex,tile=d.get('tile',1.2),fit=d.get('fit',False),rough=d.get('rough',.5),metal=d.get('metal',0.),emit=d.get('emit',0.),alpha=d.get('alpha',1.))
TILES={'wood_dark':2.2,'wood_walnut':2.2,'terrazzo_star_bw':4.0,'marble_black':1.5,'marble_cream':1.6,'marble_redbrown':1.6,'damask_brown_gold':1.2,'tile_white_large':1.2,'mosaic_red_white':1.0,'mosaic_pool_blue':1.0,'mosaic_navy':1.0,'mosaic_gold':.4,'mosaic_black_white_check':.6,'wallpaper_key_purple':1.0,'wallpaper_cream_linen':1.0,'ceiling_grid_dark':2.4,'granite_brown':1.5,'velvet_tufted_red':1.0,'mirror_lattice_black':1.0}
TEX_ALIAS={'marble_redbrown':'marble_redbrown_deep'}
ROUGH={'marble_black':.12,'marble_cream':.15,'marble_redbrown':.12,'terrazzo_star_bw':.12,'wood_dark':.35,'wood_walnut':.32,'tile_white_large':.15}
def col(c,emit=0.,rough=.6,metal=0.):return mat('c_'+'_'.join('%.2f'%v for v in c)+('_e%.1f'%emit if emit else '')+('_m' if metal else '')+('_r%.2f'%rough),tuple(c),rough=rough,metal=metal,emit=emit)
def cushion_tufts(x0,x1,y,z0,z1,m,nx,nz,axis='x'):
 for i in range(nx):
  for k in range(nz):
   u=x0+(x1-x0)*(i+.5)/nx;v=z0+(z1-z0)*(k+.5)/nz;ell('Tuft button',(u,y,v) if axis=='x' else (y,u,v),(.035,.025,.035),m,8)
# ---------- fabric (v2 only; the samples keep the shared flat drape())
def drape2(name,x0,x1,y,z0,z1,m,axis='x',folds=10,depth=.14,tie=None,tie_w=.28,anchor=0.,flare=.12):
 # Deep-fold curtain: fold depth grows toward the hem, the hem flares out and sways; with tie=(z) the panel is gathered
 # to tie_w of its width at that height toward 'anchor' (0 = centre, -1 = x0 side, 1 = x1 side), like a tied-back drape.
 n=72;rows=18;verts=[];faces=[];L=x1-x0
 for r in range(rows+1):
  t=r/rows;zz=z0+(z1-z0)*t;g=1.
  if tie is not None:
   tt=(tie-z0)/(z1-z0);g=tie_w+(1-tie_w)*min(1.,abs(t-tt)/max(.25,(1-tt) if t>tt else tt))**1.5
  a=(anchor+1)/2*L;dep=depth*(1.3-.7*t)
  for i in range(n+1):
   u=i/n;base=x0+a+(u*L-a)*g;off=dep*math.sin(u*folds*math.tau)*(1.1 if tie is None else 1.6-g*.6)
   if t<.12:base+=(u-.5)*L*flare*(.12-t)/.12*g;off+=flare*.5*(.12-t)/.12*math.sin(u*folds*math.tau*.5+1)
   verts.append((base,y+off,zz) if axis=='x' else (y+off,base,zz))
 for r in range(rows):
  for i in range(n):k=r*(n+1)+i;faces.append((k,k+1,k+n+2,k+n+1))
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
 for f in me.polygons:f.use_smooth=True
 bpy.context.view_layer.objects.active=o;s=o.modifiers.new('sol','SOLIDIFY');s.thickness=.015;bpy.ops.object.modifier_apply(modifier=s.name);return reg(o,m)
def swag(name,p0,p1,z,m,n=3,drop=.38,fringe=None):
 # scalloped valance along a rail p0->p1 (xy) hanging from z: n swags, each a gathered panel whose hem sags in an arc
 (ax,ay),(bx,by)=p0,p1;verts=[];faces=[];N=24*n;rows=6
 for r in range(rows+1):
  t=r/rows
  for i in range(N+1):
   u=i/N;s=(u*n)%1.;hem=drop*(.45+.55*math.sin(math.pi*s));zz=z-hem*t;pull=.05*math.sin(math.pi*s)*t
   x,y=ax+(bx-ax)*u,ay+(by-ay)*u;nx,ny=-(by-ay),(bx-ax);ln=math.hypot(nx,ny) or 1
   verts.append((x-nx/ln*pull,y-ny/ln*pull,zz+.02*math.sin(u*N*math.pi/3)*t))
 for r in range(rows):
  for i in range(N):k=r*(N+1)+i;faces.append((k,k+1,k+N+2,k+N+1))
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
 for f in me.polygons:f.use_smooth=True
 bpy.context.view_layer.objects.active=o;s=o.modifiers.new('sol','SOLIDIFY');s.thickness=.015;bpy.ops.object.modifier_apply(modifier=s.name);reg(o,m)
 if fringe:
  for k in range(n+1):
   u=k/n;x,y=ax+(bx-ax)*u,ay+(by-ay)*u;cyl('Swag tassel',(x,y,z-drop*.45-.12),.025,.22,fringe,r2=.05,n=8)
 return o
# ---------- seating (front faces -y before rotation; rot in degrees about the piece centre)
def group_rot(objs,cx,cy,rot):
 if not rot:return
 a=math.radians(rot);ca,sa=math.cos(a),math.sin(a)
 for o in objs:
  for v in o.data.vertices:
   x,y=v.co.x-cx,v.co.y-cy;v.co.x=cx+x*ca-y*sa;v.co.y=cy+x*sa+y*ca
  o.data.update()
def piece(fn,*a,rot=0,cx=0,cy=0,**k):
 n0=len(OBJS);fn(*a,**k);objs=[o for o in OBJS[n0:] if o.type=='MESH'];bpy.context.view_layer.update()
 for o in objs:
  o.data.transform(o.matrix_world);o.matrix_world.identity()
 group_rot(objs,cx,cy,rot)
def sofa_shape(kind,x,y,L,m,frame,legs):
 d=.95;h=.42
 if kind=='chesterfield':
  box('Chesterfield base',(x,y,.24),(L,d,.32),m,.06);box('Chesterfield seat',(x,y-.06,.47),(L-.5,d-.25,.16),m,.06)
  box('Chesterfield back',(x,y+.36,.62),(L,.24,.56),m,.08);cushion_tufts(x-L/2+.25,x+L/2-.25,y+.235,.45,.85,frame,int(L/.22),3)
  for s in [-1,1]:cyl('Rolled arm',(x+s*(L/2-.14),y,.66),.15,d,m,n=20).rotation_euler.x=math.pi/2;box('Arm side',(x+s*(L/2-.14),y,.42),(.28,d,.44),m,.06)
 elif kind=='modern':
  box('Sofa base',(x,y,.22),(L,d,.30),m,.04);box('Sofa seat',(x,y-.06,.42),(L-.4,d-.2,.14),m,.05);box('Sofa back',(x,y+.36,.62),(L-.4,.22,.5),m,.06)
  for s in [-1,1]:box('Square arm',(x+s*(L/2-.1),y,.40),(.2,d,.5),m,.04)
  for xx in [-1,1]:box('Plinth foot',(x+xx*(L/2-.25),y,.04),(.08,d-.2,.08),legs)
 elif kind=='curved':
  R=L/2;n=12;cw=2*R*math.sin(math.radians(60/n))*1.12  # seats on an arc around (x,y-R), concave side toward -y
  for k in range(n):
   a=math.radians(-60+(k+.5)*120/n);sa,ca=math.sin(a),math.cos(a)
   b=box('Curved banquette segment',(x+R*sa,y-R+R*ca,.24),(cw,d,.34),m,.03);b.rotation_euler.z=-a
   rb=R+d/2-.1;b2=box('Curved banquette back',(x+rb*sa,y-R+rb*ca,.66),(cw*(rb/R),.2,.62),m,.03);b2.rotation_euler.z=-a
 else: # baroque
  box('Baroque base',(x,y,.26),(L,d,.30),m,.10);box('Baroque seat',(x,y-.08,.48),(L-.35,d-.25,.16),m,.07)
  box('Baroque back',(x,y+.36,.80),(L-.2,.18,.70),m,.08);cushion_tufts(x-L/2+.3,x+L/2-.3,y+.26,.6,1.05,frame,int(L/.3),2)
  pts=[(x-L/2+.05+i*(L-.1)/40,y+.46,1.12+.18*math.sin(math.pi*i/40)**1.5) for i in range(41)];tube('Carved crest',pts,.022,frame)
  for s in [-1,1]:
   box('Scroll arm',(x+s*(L/2-.1),y,.55),(.2,d,.3),m,.06);tube('Arm scroll',[(x+s*(L/2-.1),y-d/2+.05,.7),(x+s*(L/2-.1),y-d/2,.55),(x+s*(L/2-.1),y-d/2+.12,.42)],.04,frame)
   for yy in [-.33,.33]:tube('Cabriole leg',[(x+s*(L/2-.15),y+yy,.12),(x+s*(L/2-.1),y+yy-.04,.05),(x+s*(L/2-.14),y+yy,.0)],.035,frame)
  tube('Apron rail',[(x-L/2+.1,y-d/2,.14),(x,y-d/2-.02,.11),(x+L/2-.1,y-d/2,.14)],.03,frame)
def chair_shape(kind,x,y,m,frame,legs):
 if kind=='tub':
  box('Tub chair seat',(x,y,.3),(.8,.75,.32),m,.12)
  for k in range(15):a=math.radians(-100+k*200/14);box('Tub back segment',(x+.38*math.sin(a),y+.05+.33*math.cos(a),.6),(.2,.14,.42),m,.03).rotation_euler.z=-a
  for xx in [-.3,.3]:
   for yy in [-.28,.28]:cyl('Chair leg',(x+xx,y+yy,.07),.02,.14,legs,r2=.015)
 elif kind=='shell':
  box('Shell chair seat',(x,y-.05,.32),(.8,.7,.22),m,.1);o=ell('Shell fan back',(x,y+.25,.78),(.95,.25,.85),m,16)
  for k in range(7):a=math.radians(-60+k*20);tube('Shell channel',[(x,y+.12,.42),(x+.45*math.sin(a),y+.22,.42+.5*math.cos(a))],.015,m)
  tube('Shell frame',[(x+.48*math.cos(math.pi*i/20),y+.3,.45+.62*math.sin(math.pi*i/20)) for i in range(21)],.025,frame)
 elif kind=='wing':
  box('Wing chair seat',(x,y,.35),(.85,.8,.3),m,.06);box('Wing chair back',(x,y+.34,.85),(.85,.16,.8),m,.06)
  for s in [-1,1]:box('Wing',(x+s*.38,y+.15,.9),(.12,.45,.6),m,.05);box('Wing arm',(x+s*.38,y,.55),(.12,.75,.25),m,.04)
  for xx in [-.33,.33]:
   for yy in [-.3,.3]:cyl('Chair leg',(x+xx,y+yy,.1),.025,.2,legs)
 elif kind=='ottoman':
  cyl('Tufted ottoman',(x,y,.22),.42,.44,m,n=32);cushion_tufts(x-.25,x+.25,y,.44,.45,frame,3,1)
 else: # baroque armchair
  sofa_shape('baroque',x,y,1.0,m,frame,legs)
def seat(s,kind_default='modern'):
 m=M(s.get('mat',{'color':(.4,.1,.1),'rough':.8}));frame=mat('gold') if s.get('frame','gold')=='gold' else M(s['frame']);legs=M(s.get('legs',{'color':(.05,.03,.02),'rough':.4}))
 x,y=s['at'];rot=s.get('rot',0);kind=s.get('kind',kind_default)
 if s.get('key') and s['key'] in furn_rx:furn(s['key'],x,y,rot);return
 if kind=='heart_booth':k_heart_booth(dict(at=[x,y],rot=rot,mat=s.get('mat','velvet_tufted_red')),None);return
 if kind in ('baroque','chesterfield','modern','curved'):piece(sofa_shape,kind,x,y,s.get('len',2.4),m,frame,legs,rot=rot,cx=x,cy=y)
 else:piece(chair_shape,kind,x,y,m,frame,legs,rot=rot,cx=x,cy=y)
# ---------- tables, rugs
def table(t):
 x,y=t['at'];m=M(t.get('mat','marble_redbrown'));base=M(t.get('base',{'color':(.05,.03,.02),'rough':.35}));k=t.get('kind','oval_marble');sx,sy=t.get('size',(1.0,1.75))
 if t.get('key') and t['key'] in furn_rx:furn(t['key'],x,y,t.get('rot',0));return furn_rx[t['key']].get('h',.45)
 if k=='oval_marble':
  cyl('Oval table top',(x,y,.47),.5,.08,m,n=48,sx=sx,sy=sy);cyl('Oval table drum',(x,y,.22),.40,.42,base,n=48,sx=sx,sy=sy*.97);cyl('Table band',(x,y,.40),.415,.03,mat('gold'),n=48,sx=sx,sy=sy*.97);return .51
 if k=='round_drum':
  cyl('Drum table',(x,y,.25),.5*sx,.5,base,n=40);cyl('Drum top',(x,y,.515),.53*sx,.03,m,n=40);return .53
 if k=='glass_rect':
  box('Glass top',(x,y,.44),(sx,sy*.6,.04),m,.01);box('Table body',(x,y,.22),(sx-.2,sy*.6-.2,.38),base,.02)
  if t.get('glow'):box('Table glow',(x,y,.22),(sx-.24,sy*.6-.24,.30),col(t['glow'],emit=1.4),.01)
  return .46
 if k=='round_glass':
  cyl('Round glass top',(x,y,.45),.5*sx,.03,m,n=40);cyl('Pedestal',(x,y,.22),.1,.44,base);cyl('Pedestal foot',(x,y,.02),.3,.04,base);return .47
 if k=='wood_rect':
  box('Wood table top',(x,y,.44),(sx,sy*.6,.06),m,.01)
  for xx in [-1,1]:
   for yy in [-1,1]:box('Table leg',(x+xx*(sx/2-.08),y+yy*(sy*.3-.08),.2),(.06,.06,.4),base)
  return .47
 if k=='booth':
  box('Booth top',(x,y,.74),(sx,sy*.65,.04),m,.01);box('Booth side',(x,y-sy*.3,.37),(sx,.03,.74),m);box('Booth side',(x,y+sy*.3,.37),(sx,.03,.74),m);return .76
 return .5
def rug(r):
 x,y=r['at'];w,d=r.get('size',(3.0,4.0));plane('Rug',(x,y,.006),(w,d),M(r.get('mat','rug_cream_gold'),),'+z')
# ---------- bed
def bed(b,q):
 x,y=b.get('at',(-3.34,4.7));shape=b.get('shape','rect');base=M(b.get('base',{'color':(.15,.08,.06),'rough':.6}));linen=M(b.get('linen',{'color':(.93,.92,.9),'rough':.85}))
 throw=M(b.get('throw')) if b.get('throw') else None;pil=M(b.get('pillows',{'color':(.93,.92,.9),'rough':.8}));hb=b.get('headboard',{})
 if b.get('key') and b['key'] in furn_rx:furn(b['key'],x,y,0)
 elif shape=='round':
  cyl('Round bed plinth',(x,y,.21),1.45,.42,base,n=64);cyl('Round mattress',(x,y,.51),1.39,.25,linen,n=64)
  if b.get('underlight'):ring('Bed underlight',(x,y,.08),1.43,1.43,.02,col(b['underlight'],emit=6.),'xy')
  for xx in [-.55,.55]:o=box('Pillow',(x+xx,y+.85,.82),(.85,.3,.45),pil,.1);o.rotation_euler.x=.2
 else:
  box('Bed base',(x,y,.22),(2.3,2.4,.44),base,.08);box('Mattress',(x,y,.55),(2.2,2.3,.26),linen,.08);box('Duvet',(x,y-.18,.70),(2.26,1.95,.11),linen,.05)
  if throw:box('Bed runner',(x,y-.5,.77),(2.3,.5,.03),throw,.01)
  if b.get('underlight'):box('Bed underglow',(x,y,.03),(2.4,2.5,.02),col(b['underlight'],emit=5.))
  for xx in [-.56,.56]:o=box('Back pillow',(x+xx,y+.95,.92),(.9,.32,.5),pil,.1);o.rotation_euler.x=.2;box('Front pillow',(x+xx,y+.7,.83),(.85,.28,.38),linen,.09)
 t=hb.get('type','panel');hm=M(hb.get('mat',{'color':(.3,.12,.1),'rough':.8}));hy=y+1.3;w=hb.get('w',2.6);hh=hb.get('h',1.4)
 if t=='panel':box('Headboard',(x,hy,.4+hh/2),(w,.16,hh),hm,.06)
 elif t=='tufted':box('Tufted headboard',(x,hy,.4+hh/2),(w,.18,hh),hm,.08);cushion_tufts(x-w/2+.15,x+w/2-.15,hy-.1,.55,.4+hh-.1,M(hb.get('button',{'color':(.1,.08,.06)})),int(w/.25),int(hh/.25))
 elif t=='round_pleat':cyl('Round headboard',(x,hy+.05,1.5),hh/2+.3,.14,hm,n=64).rotation_euler.x=math.pi/2;ring('Headboard ring',(x,hy-.03,1.5),hh/2+.38,hh/2+.38,.05,M(hb.get('trim','gold')) if hb.get('trim','gold')!='gold' else mat('gold'),'xz')
 elif t=='wing':box('Wing headboard',(x,hy,.4+hh/2),(w,.2,hh),hm,.1);[box('Headboard wing',(x+s*(w/2+.1),hy-.15,.4+hh/2),(.22,.45,hh),hm,.08) for s in [-1,1]]
 elif t=='crown':box('Crown headboard',(x,hy,.4+hh/2),(w,.16,hh),hm,.06);tube('Crown crest',[(x-w/2+i*w/30,hy-.02,.4+hh+.25*math.sin(math.pi*i/30)) for i in range(31)],.05,mat('gold'))
 elif t=='slats':
  for k in range(int(w/.18)):box('Headboard slat',(x-w/2+.09+k*.18,hy,.4+hh/2),(.12,.08,hh),hm,.01)
 elif t=='heart':
  # tufted heart: two lobes + a 45-degree square point, upholstered panel behind
  r=hh*.32;zc=.4+hh*.62;tm=M(hb.get('button',{'color':(.1,.02,.03)}))
  box('Heart headboard back',(x,hy+.06,.4+hh*.55),(w,.1,hh*1.1),M(hb.get('back',{'color':(.02,.01,.01),'rough':.3})),.04)
  for s in [-1,1]:cyl('Heart headboard lobe',(x+s*r*.8,hy-.04,zc),r,.16,hm,n=40).rotation_euler.x=math.pi/2
  o=box('Heart headboard point',(x,hy-.04,zc-r*.55),(r*1.6,.16,r*1.6),hm,.04);o.rotation_euler.y=math.radians(45)
  cushion_tufts(x-r*1.2,x+r*1.2,hy-.13,zc-r*.8,zc+r*.6,tm,6,4)
 if b.get('canopy'):
  pm=M(b['canopy'].get('posts','gold')) if b['canopy'].get('posts','gold')!='gold' else mat('gold');dm=M(b['canopy'].get('drape',{'color':(.9,.85,.75),'rough':.9,'alpha':.6}))
  for xx in [-1.2,1.2]:
   for yy in [-1.25,1.25]:cyl('Canopy post',(x+xx,y+yy,1.3),.04,2.6,pm)
  for xx in [-1.2,1.2]:box('Canopy rail',(x+xx,y,2.6),(.06,2.6,.06),pm)
  for yy in [-1.25,1.25]:box('Canopy rail',(x,y+yy,2.6),(2.5,.06,.06),pm)
  cp=b['canopy']
  if cp.get('style','tied')=='flat':
   for xx in [-1.2,1.2]:drape('Canopy drape',y-1.25,y+1.25,x+xx,.6,2.6,dm,'y',6,.05)
  else:
   # photos: a scalloped valance with tassels on all four rails, floor-length drapes tied back to each post, optional
   # sheer inner panels along the sides (alpha) -- instead of flat side sheets
   vm=M(cp.get('valance',cp.get('drape',{'color':(.9,.85,.75),'rough':.9})));fm=M(cp.get('fringe','gold')) if cp.get('fringe','gold')!='gold' else mat('gold')
   for yy in [-1.25,1.25]:swag('Canopy valance',(x-1.2,y+yy),(x+1.2,y+yy),2.62,vm,3,.36,fm)
   for xx in [-1.2,1.2]:swag('Canopy valance',(x+xx,y-1.25),(x+xx,y+1.25),2.62,vm,3,.36,fm)
   tm=M(cp.get('tie','gold')) if cp.get('tie','gold')!='gold' else mat('gold')
   for xx in [-1.2,1.2]:
    for yy in [-1.25,1.25]:
     sg=1 if yy<0 else -1;y0,y1=sorted([y+yy,y+yy+sg*.95])
     drape2('Canopy drape',y0,y1,x+xx+(.04 if xx>0 else -.04),.03,2.55,dm,'y',7,.1,tie=1.05,tie_w=.22,anchor=-1 if sg>0 else 1)
     cyl('Canopy tieback',(x+xx+(.04 if xx>0 else -.04),y+yy+sg*.1,1.05),.07,.08,tm,n=16)
   # sheer panels need translucency the imported material does not keep (they rendered as opaque white boards
   # cutting into the mattress, 2026-10-28): only on explicit request
   if cp.get('sheer',False):
    sh=M(cp.get('sheer_mat',{'color':(.97,.96,.94),'rough':.9,'alpha':.35}))
    for xx in [-1.12,1.12]:drape2('Canopy sheer',y-.35,y+.35,x+xx,.03,2.5,sh,'y',8,.06,flare=.05)
 lt=b.get('lamps','pleated');shade=M(b.get('shade',{'color':(1.,.85,.6),'emit':1.6}));lb=M(b.get('stand',{'color':(.08,.05,.03),'rough':.35}))
 for s in [-1,1]:
  xx=x+s*1.75;box('Nightstand',(xx,y+.95,.3),(.6,.5,.6),lb,.02)
  if lt=='drum':lamp_drum(xx,y+.95,.6,shade,mat('gold'),.6)
  elif lt=='none':pass
  else:lamp_pleated(xx,y+.95,.6,shade,mat('gold'))
 return x,y
# ---------- walls, ceiling
def lining(side,mm,q,x0=None,x1=None,z0=0.,z1=None,o=0.):
 w,d,h=q['size_m'];z1=h if z1 is None else z1;zc=(z0+z1)/2;zh=z1-z0
 if side=='left':a0,a1=(-3.2 if x0 is None else x0),(6.5 if x1 is None else x1);plane('Wall lining',(-w/2+.215+o,(a0+a1)/2,zc),(a1-a0,zh),mm,'+x')
 elif side=='right':a0,a1=(-4.6 if x0 is None else x0),(6.5 if x1 is None else x1);plane('Wall lining',(w/2-.215-o,(a0+a1)/2,zc),(a1-a0,zh),mm,'-x')
 elif side=='front':a0,a1=(-w/2+.3 if x0 is None else x0),(w*.29-.9 if x1 is None else x1);plane('Wall lining',((a0+a1)/2,-d/2+.215+o,zc),(a1-a0,zh),mm,'+y')
 elif side=='rear':
  a0,a1=(-w/2+.25 if x0 is None else x0),(w/2-.25 if x1 is None else x1);bathx=w*.28;g0,g1=bathx-1.2,bathx+1.6
  for (u0,u1) in [(a0,min(a1,g0)),(max(a0,g1),a1)]:
   if u1>u0+.05:plane('Wall lining',((u0+u1)/2,6.52-o,zc),(u1-u0,zh),mm,'-y')
  if z1>2.72 and a1>g0 and a0<g1:plane('Wall lining',((max(a0,g0)+min(a1,g1))/2,6.52-o,(max(z0,2.72)+z1)/2),(min(a1,g1)-max(a0,g0),z1-max(z0,2.72)),mm,'-y')
COVE=[]
def cove_wash(x0,x1,y0,y1,band,h,colr,step=4.5):
 # An emissive strip lights nothing in UE: wash the ceiling field with its colour from point lights just inside the tray opening.
 ax0,ax1,ay0,ay1=x0+band+.3,x1-band-.3,y0+band+.3,y1-band-.3
 for (a,b,fix,horiz) in [(ax0,ax1,ay0,True),(ax0,ax1,ay1,True),(ay0,ay1,ax0,False),(ay0,ay1,ax1,False)]:
  n=max(1,round((b-a)/step))
  for i in range(n+1 if horiz else n-1):
   t=a+(b-a)*((i if horiz else i+1)/n);COVE.append((((t,fix) if horiz else (fix,t))+(h-.18,),colr,2500,380))
def ceiling(c,q):
 w,d,h=q['size_m'];k=c.get('type','tray');field=M(c.get('field',{'color':(.7,.67,.63),'rough':.8}));soffit=M(c.get('soffit',{'color':(.9,.88,.85),'rough':.8}))
 cove=col(c.get('cove',(1.,.72,.42)),emit=max(c.get("cove_emit",6.),6.)*3);trim=M(c.get('trim','gold')) if c.get('trim','gold')!='gold' else mat('gold')
 x0=c.get('x0',None)
 if k=='flat':box('Ceiling field',(0,0,h+.05),(w-.4,d-.4,.1),field);return
 if k=='beams':
  box('Ceiling field',(0,0,h+.05),(w-.4,d-.4,.1),field)
  for i in range(int(d/1.6)):box('Ceiling beam',(0,-d/2+.8+i*1.6,h-.08),(w-.4,.18,.16),soffit)
  return
 tray_ceiling(w,d,h,field,soffit,cove,trim,band=c.get('band',1.0),drop=c.get('drop',.35),x0=x0)
 cc=tuple(c.get('cove',(1.,.72,.42)))
 cove_wash(-w/2+.2 if x0 is None else x0,w/2-.2,-d/2+.2,d/2-.2,c.get('band',1.0),h,cc)
 if k=='mirror':box('Mirror ceiling',(0,1.5,h-.02),(w-2*c.get('band',1.0)-.6,d-2*c.get('band',1.0)-6,.02),mat('mirror_ceiling',(.6,.55,.62),rough=.04,metal=1.))
 if k=='dome':
  for (cx,cy) in c.get('domes',[(0,1.5)]):
   for a in range(4):COVE.append(((cx+1.2*math.cos(a*math.pi/2),cy+1.2*math.sin(a*math.pi/2),h-.25),cc,2000,300))
   ring('Dome cove',(cx,cy,h-.05),1.6,1.6,.03,cove,'xy');cyl('Dome recess',(cx,cy,h-.02),1.55,.02,M(c.get('dome_field',{'color':(.95,.85,.6),'emit':1.5})),n=48)
 for ov in c.get('ovals',[]):
  # gold-mosaic oval recess with a lit rim (315, 402): ellipse disc just under the field, gold ring, cove wash around it
  (cx,cy),(rx,ry)=ov['at'],ov.get('r',(2.2,1.5));om=M(ov.get('mat','mosaic_gold'))
  cyl('Oval recess',(cx,cy,h-.015),1.,.02,om,n=64,sx=rx,sy=ry);ring('Oval recess rim',(cx,cy,h-.04),rx+.04,ry+.04,.035,mat('gold'),'xy')
  ring('Oval cove',(cx,cy,h-.07),rx+.12,ry+.12,.02,col(tuple(ov.get('cove',c.get('cove',(1.,.72,.42)))),emit=12.),'xy')
  for a in range(6):COVE.append(((cx+rx*.8*math.cos(a*math.tau/6),cy+ry*.8*math.sin(a*math.tau/6),h-.3),tuple(ov.get('cove',c.get('cove',(1.,.72,.42)))),900,320))
 if k=='stars':
  sm=col(c.get('star',(.8,.85,1.)),emit=10.)
  for i in range(110):ell('Ceiling star',(-w/2+1+(i*.618%1)*(w-2),-4+(i*.414%1)*10,h-.03),(.025,.025,.012),sm,6)
# ---------- lighting fixtures
def chandelier(c,q):
 h=q['size_m'][2];x,y=c['at'];k=c.get('kind','arms');m=M(c.get('mat','gold')) if c.get('mat','gold')!='gold' else mat('gold');glow=col(c.get('glow',(1.,.85,.6)),emit=c.get('emit',4.))
 if c.get('key') and c['key'] in furn_rx:furn(c['key'],x,y,0,h-.3-furn_rx[c['key']].get('h',.85));return
 cyl('Chandelier rod',(x,y,h-.15),.015,.3,m)
 if k=='tiers':
  for t in range(3):
   r=.45-t*.1;z=h-.45-t*.22
   for i in range(28):a=i*math.tau/28;cyl('Crystal strand',(x+r*math.cos(a),y+r*math.sin(a),z),.008,.22,mat('crystal',(.9,.92,1.),rough=.02,emit=.6),n=6)
  cyl('Crystal core glow',(x,y,h-.65),.12,.5,glow,n=16)
 elif k=='drum':cyl('Drum pendant',(x,y,h-.65),.4,.35,glow,n=32);cyl('Drum rim',(x,y,h-.47),.41,.02,m,n=32)
 elif k=='disco':cyl('Disco rod',(x,y,h-.3),.012,.6,m);ball=ell('Mirror disco ball',(x,y,h-.85),(.5,.5,.5),mat('mirror_ball',(.8,.8,.82),rough=.05,metal=1.),16)
 elif k=='ring':ring('LED ring pendant',(x,y,h-.6),.6,.6,.03,glow,'xy');ring('LED ring pendant',(x,y,h-.75),.42,.42,.03,glow,'xy')
 elif k=='halo':
  # 513: a big flush ceiling ring of light (photo: blue LED circle in the ceiling), not a hanging double hoop
  r=c.get('r',1.4);ring('LED ceiling halo',(x,y,h-.05),r,r,.035,glow,'xy');ring('LED ceiling halo',(x,y,h-.05),r-.18,r-.18,.02,glow,'xy')
 elif k=='lantern':
  # Chinese lanterns in a row along x: red glowing body, gold caps and tassel
  n=c.get('n',3);body=col(c.get('glow',(1.,.18,.08)),emit=c.get('emit',3.))
  for i in range(n):
   lx=x+(i-(n-1)/2)*.75;cyl('Lantern cord',(lx,y,h-.25),.008,.5,m,n=6);ell('Lantern body',(lx,y,h-.85),(.5,.5,.6),body,20)
   for dz in [-.3,.3]:cyl('Lantern cap',(lx,y,h-.85+dz),.12,.05,m,n=16)
   cyl('Lantern tassel',(lx,y,h-1.3),.03,.3,col((.9,.1,.05)),n=8)
 else:
  n=c.get('n',8)
  for i in range(n):a=i*math.tau/n;tube('Chandelier arm',[(x,y,h-.45),(x+.35*math.cos(a),y+.35*math.sin(a),h-.6),(x+.55*math.cos(a),y+.55*math.sin(a),h-.55)],.015,m);cyl('Chandelier shade',(x+.55*math.cos(a),y+.55*math.sin(a),h-.48),.07,.13,glow,r2=.05,n=12)
  ell('Chandelier bowl',(x,y,h-.55),(.25,.25,.18),m,12)
# ---------- headboard feature walls (trellis, padded_wall, filigree_screen)
def wall_frame(side,q,off):
 # map wall coordinates (u along the wall, z up, 'off' metres out from the finish) to room xyz; rear = the wall behind the bed
 w=q['size_m'][0]
 if side=='left':return (lambda u,z,o=0:(-w/2+.22+off+o,u,z)),'y'
 if side=='right':return (lambda u,z,o=0:(w/2-.22-off-o,u,z)),'y'
 return (lambda u,z,o=0:(u,6.50-off-o,z)),'x'
def wbox(name,P,ax,u,z,o,su,sz,sd,m,bevel=0,tilt=0):
 # box on a wall: su along the wall, sz tall, sd deep; tilt rotates it about the wall normal (diamond pattern)
 b=box(name,P(u,z,o),(su,sd,sz) if ax=='x' else (sd,su,sz),m,bevel)
 if tilt:
  if ax=='x':b.rotation_euler.y=tilt
  else:b.rotation_euler.x=tilt
 return b
def wall_feature(e,q):
 t=e['type'];side=e.get('side','rear');w,d,h=q['size_m']
 if t=='filigree_screen' and e.get('at') and len(e['at'])==2 and side=='free':
  # freestanding pierced screen panel(s) on feet: at=[x,y], rot (deg); texture on both faces, gold frame
  x,y=e['at'];n=e.get('panels',3);pw,ph=e.get('panel',(.6,2.0));fm=mat('gold') if e.get('frame','gold')=='gold' else M(e['frame']);sm=M(e.get('mat',{'gen':{'kind':'filigree','bg':(.03,.02,.01),'fg':(.85,.65,.25)},'metal':.6,'rough':.3}))
  def build():
   for i in range(n):
    px=x+(i-(n-1)/2)*(pw+.04);box('Filigree screen panel',(px,y,.1+ph/2),(pw,.03,ph),sm);frame('Filigree screen frame',(px,y,.1+ph/2),pw,ph,fm,.04,'x')
    for s in (-1,1):box('Screen foot',(px+s*pw*.35,y,.05),(.06,.35,.06),fm)
  piece(build,rot=e.get('rot',0),cx=x,cy=y);return
 u0,u1=e.get('range',(-5.2,-1.5));z0,z1=e.get('z',(.4,2.9));P,ax=wall_frame(side,q,0.);uc,zc=(u0+u1)/2,(z0+z1)/2
 if t=='trellis':
  # metal diamond lattice (212, 201 Hawaii) over a dark padded or mirror backing, framed
  bk=e.get('back',{'color':(.03,.025,.03),'rough':.5});bm=None if bk=='none' else (mat('mirror_wall',(.72,.72,.75),rough=.03,metal=1.) if bk=='mirror' else M(bk))
  bar=mat('gold') if e.get('bar','gold')=='gold' else M(e['bar']);p=e.get('pitch',.42)
  if e.get('back')!='none':wbox('Trellis lining backing',P,ax,uc,zc,.02,u1-u0,z1-z0,.04,bm)
  L=u1-u0;H=z1-z0;off=e.get('off',.07)
  # 45-degree bars u = c + sg*(z - z0), clipped to the panel
  for sg in (1,-1):
   c=u0-H if sg>0 else u0
   while c<=(u1 if sg>0 else u1+H):
    za,zb=(max(z0,z0+u0-c),min(z1,z0+u1-c)) if sg>0 else (max(z0,z0+c-u1),min(z1,z0+c-u0))
    if zb-za>.02:tube('Trellis lining bar',[P(c+sg*(za-z0),za,off),P(c+sg*(zb-z0),zb,off)],.014,bar)
    c+=p
  for (uu,zz,su,sz) in ((uc,z0,L+.08,.06),(uc,z1,L+.08,.06),(u0,zc,.06,H),(u1,zc,.06,H)):wbox('Trellis lining frame',P,ax,uu,zz,off,su,sz,.06,bar)
 elif t=='padded_wall':
  # upholstered panels: 'rect' grid or 'diamond' (45 deg) blocks, two colours alternating, optional buttons
  s=e.get('size',.45);ms=[M(c) for c in e.get('mats',[{'color':(.25,.14,.09),'rough':.8}])];btn=M(e['button']) if e.get('button') else None
  diamond=e.get('pattern','rect')=='diamond';step=s*(1.414 if diamond else 1.)
  nu,nz=int((u1-u0)/step),int((z1-z0)/(step if not diamond else step/2))
  for i in range(nu+(1 if diamond else 0)):
   for k in range(nz+(1 if diamond else 0)):
    if diamond:uu=u0+step*(i+(.5 if k%2 else 0));zz=z0+step/2*k
    else:uu=u0+step*(i+.5);zz=z0+step*(k+.5)
    if not (u0-.01<=uu<=u1+.01 and z0-.01<=zz<=z1+.01):continue
    sz=s*(.94 if not diamond else .96)
    wbox('Padded lining panel',P,ax,uu,zz,.05,sz,sz,.09,ms[(i+k)%len(ms)],.035,math.pi/4 if diamond else 0)
    if btn and diamond:ell('Padded lining button',P(uu,zz+step/2,.1),(.03,.03,.03),btn,8)
  if e.get('frame'):
   fm=mat('gold') if e['frame']=='gold' else M(e['frame'])
   for (uu,zz,su,sz) in ((uc,z0-.04,u1-u0+.1,.05),(uc,z1+.04,u1-u0+.1,.05),(u0-.05,zc,.05,z1-z0+.1),(u1+.05,zc,.05,z1-z0+.1)):wbox('Padded lining frame',P,ax,uu,zz,.06,su,sz,.05,fm)
 elif t=='filigree_screen':
  # wall-mounted pierced gold screen (213, 101) with an optional glowing backing behind the openings
  sm=M(e.get('mat',{'gen':{'kind':'filigree','bg':(.03,.02,.01),'fg':(.85,.65,.25)},'metal':.6,'rough':.3}));fm=mat('gold') if e.get('frame','gold')=='gold' else M(e['frame'])
  if e.get('glow'):wbox('Screen lining backlight',P,ax,uc,zc,.01,u1-u0-.1,z1-z0-.1,.01,col(e['glow'],emit=e.get('emit',3.)))
  wbox('Filigree lining screen',P,ax,uc,zc,.05,u1-u0,z1-z0,.02,sm)
  for (uu,zz,su,sz) in ((uc,z0,u1-u0+.1,.08),(uc,z1,u1-u0+.1,.08),(u0,zc,.08,z1-z0),(u1,zc,.08,z1-z0)):wbox('Screen lining frame',P,ax,uu,zz,.07,su,sz,.06,fm)
  if e.get('glow'):COVE.append((P(uc,zc,.6),tuple(e['glow']),500,350))
# ---------- extras
def extra(e,q):
 w,d,h=q['size_m'];t=e['type']
 if t in KITS:KITS[t](e,q);return
 if t=='columns':
  iv=M(e.get('mat',{'color':(.86,.80,.68),'rough':.45}))
  for (x,y) in e['at']:column(x,y,h-.36,iv,mat('gold'))
 elif t=='drape':
  # deep folds and a swaying hem; 'tie' (height) gathers it toward 'anchor'; 'valance' adds a scalloped swag above
  dm=M(e.get('mat',{'color':(.85,.75,.6),'rough':.9}));ax=e.get('axis','x');z1=e.get('z1',3.5)
  if e.get('tie') and e.get('split',True):
   mid=(e['x0']+e['x1'])/2
   drape2('Drape',e['x0'],mid-.02,e['y'],.03,z1,dm,ax,max(4,e.get('folds',10)//2),.12,tie=e['tie'],anchor=-1)
   drape2('Drape',mid+.02,e['x1'],e['y'],.03,z1,dm,ax,max(4,e.get('folds',10)//2),.12,tie=e['tie'],anchor=1)
  else:drape2('Drape',e['x0'],e['x1'],e['y'],.03,z1,dm,ax,e.get('folds',10),.12,tie=e.get('tie'),anchor=e.get('anchor',0))
  if e.get('valance'):
   p0,p1=((e['x0'],e['y']),(e['x1'],e['y'])) if ax=='x' else ((e['y'],e['x0']),(e['y'],e['x1']))
   swag('Drape valance',p0,p1,z1+.02,M(e['valance']) if isinstance(e['valance'],(dict,str)) else dm,max(2,round(abs(e['x1']-e['x0'])/1.2)),.4,mat('gold'))
 elif t=='led_strips':
  m=col(e.get('color',(1.,.2,.85)),emit=e.get('emit',9.));side=e['side'];a0,a1=e.get('range',(-3,6))
  for i in range(e.get('n',8)):
   u=a0+(a1-a0)*(i+.5)/e.get('n',8)
   if side=='left':box('LED strip',(-w/2+.23,u,1.65),(.03,.05,2.6),m)
   elif side=='right':box('LED strip',(w/2-.23,u,1.65),(.03,.05,2.6),m)
   else:box('LED strip',(u,6.50,1.65),(.05,.03,2.6),m)
 elif t=='led_line':
  m=col(e.get('color',(1.,.2,.85)),emit=e.get('emit',8.));(x0,y0,z0),(x1,y1,z1)=e['a'],e['b'];tube('LED line',[(x0,y0,z0),(x1,y1,z1)],.015,m)
 elif t=='stars':
  m=col(e.get('color',(.6,.75,1.)),emit=12.);side=e['side'];a0,a1=e.get('range',(-3,6))
  for i in range(e.get('n',120)):
   u=a0+(i*.618%1)*(a1-a0);z=.4+(i*.755%1)*2.9
   p=(-w/2+.23,u,z) if side=='left' else ((w/2-.23,u,z) if side=='right' else (u,6.50,z))
   ell('Wall star',p,(.03,.03,.03),m,6)
 elif t=='mirror_wall':lining(e['side'],mat('mirror_wall',(.72,.72,.75),rough=.03,metal=1.),q,e.get('x0'),e.get('x1'),e.get('z0',.1),e.get('z1',2.8))
 elif t=='panel':lining(e['side'],M(e['mat']),q,e.get('x0'),e.get('x1'),e.get('z0',0.),e.get('z1'),.018)
 elif t=='wainscot':
  for side in e.get('sides',['left','right']):lining(side,M(e['mat']),q,None,None,0.,e.get('h',.95),.01)
  rail=mat('gold') if e.get('rail','gold')=='gold' else M(e['rail'])
  for side in e.get('sides',['left','right']):
   if side=='left':box('Chair rail',(-w/2+.23,1.6,e.get('h',.95)),(.04,9.8,.05),rail)
   elif side=='right':box('Chair rail',(w/2-.23,1.0,e.get('h',.95)),(.04,11.0,.05),rail)
 elif t=='brick_arch':
  x,y=e['at'];m=M(e.get('mat',{'color':(.5,.22,.14),'rough':.85}));r=e.get('r',2.0);sp=e.get('spring',1.3)
  for k in range(25):a=k*math.pi/24;o=box('Brick arch voussoir',(x+r*math.cos(a),y,sp+r*.75*math.sin(a)),(.25,.22,.19),m,.015);o.rotation_euler.y=-a
  for s in [-1,1]:box('Arch pier',(x+s*r,y,sp/2),(.3,.25,sp),m,.02)
 elif t=='vine_arcade':
  # red lacquered arcade over an entry passage (311 photo 2): n round arches along y every 'pitch' m starting at 'at',
  # piers just outside 'clear_w', ribs springing at 'spring' and rising 'rise'; vine stems, leaves and blossoms ride the
  # ribs, three garlands run the length, and every other arch trails a vine down the OUTER face of one pier. Nothing
  # below 'spring' enters the clear width, so the entry route stays open (route_check ignores parts above 1.8 m).
  x,y0=e['at'];n=e.get('n',6);pt=e.get('pitch',.6);cw=e.get('clear_w',1.5);sp=e.get('spring',2.35);rise=e.get('rise',.7)
  m=M(e.get('mat',{'color':(.5,.05,.04),'rough':.28,'metal':.05}));hw=cw/2+.06
  stem=mat('vine_stem',(.2,.24,.1),rough=.7);lv=[mat('vine_leaf_a',(.16,.4,.12),rough=.6),mat('vine_leaf_b',(.1,.3,.08),rough=.6)]
  import random;fl=[mat('vine_flower_a',(.95,.55,.72),rough=.6),mat('vine_flower_b',(.97,.95,.9),rough=.6)];rng=random.Random(311)
  def arc(a,dr=0.,dz=0.):return x+(hw+dr)*math.cos(a),sp+(rise+dz)*math.sin(a)
  def leaf(p,k):
   o=ell('Vine leaf',p,(.14,.08,.03),lv[k%2],8);o.rotation_euler=(rng.uniform(-.6,.6),rng.uniform(-.6,.6),rng.uniform(0,math.pi))
  for i in range(n):
   yy=y0+i*pt
   for s in (-1,1):box('Arcade pier',(x+s*hw,yy,sp/2),(.12,.22,sp),m,.02)
   tube('Arcade rib',[(arc(k*math.pi/24)[0],yy,arc(k*math.pi/24)[1]) for k in range(25)],.06,m)
   tube('Vine stem',[(arc(a,.08,.08)[0],yy+.03*math.sin(a*9+i),arc(a,.08,.08)[1]) for a in [math.radians(15+k*5) for k in range(31)]],.012,stem)
   # 'leaves' per rib / 'flowers' per rib / 'trail' every arch: 311 round 9 read sparse against the photo's thick ivy
   nl=e.get('leaves',10);nf=e.get('flowers',2)
   for k in range(nl):a=math.radians(20+k*140/max(1,nl-1));px,pz=arc(a,.1+.03*((k+i)%2),.1);leaf((px,yy+(.08 if k%2 else -.08),pz),k+i)
   for k in range(nf):a=math.radians(40+k*100/max(1,nf-1)+(i%2)*15);px,pz=arc(a,.14,.14);ell('Vine flower',(px,yy,pz),(.07,.07,.07),fl[(k+i)%2],10)
   if i%2==0 or e.get('trail'):
    s=-1 if i%4==0 else 1;px=x+s*(hw+.1)
    tube('Vine stem',[(px+.02*math.sin(z*7),yy,z) for z in [sp+.1-k*(sp-.9)/12 for k in range(13)]],.012,stem)
    for k in range(5):leaf((px+s*.04,yy+(.07 if k%2 else -.07),sp-.05-k*.3),k)
  y1=y0+(n-1)*pt
  for gx,gz in ((0.,sp+rise+.1),(-hw*.72,sp+rise*.72+.08),(hw*.72,sp+rise*.72+.08)):
   tube('Vine stem',[(x+gx,y0-.15+k*(y1-y0+.3)/20,gz-.05*math.sin(math.pi*((k%4)/4))) for k in range(21)],.014,stem)
   k=0;yy=y0-.05
   while yy<y1+.15:
    leaf((x+gx+(.06 if k%2 else -.06),yy,gz+.03),k)
    if k%4==2:ell('Vine flower',(x+gx,yy+.08,gz+.08),(.07,.07,.07),fl[(k//4)%2],10)
    k+=1;yy+=e.get('garland_step',.3)
 elif t=='screen':
  x,y=e['at'];ww,hh=e.get('size',(2.4,1.4));side=e.get('side','rear');m=M(e.get('mat',{'color':(.2,.4,.9),'emit':2.}))
  if side=='left':plane('Feature screen',(-w/2+.22,y,e.get('z',1.6)),(ww,hh),m,'+x')
  elif side=='right':plane('Feature screen',(w/2-.22,y,e.get('z',1.6)),(ww,hh),m,'-x')
  else:plane('Feature screen',(x,6.51,e.get('z',1.6)),(ww,hh),m,'-y')
 elif t=='tv':
  x,y=e['at'];rot=e.get('rot',180);wall=M(e.get('wall',{'color':(.12,.07,.05),'tex':'wood_dark','tile':1.4,'rough':.4}))
  def tvset():
   if e.get('wall'):box('TV feature wall',(x,y+.12,1.45),(e.get('ww',3.6),.08,2.9),wall,.02)
   box('TV cabinet',(x,y-.1,.32),(e.get('cw',2.6),.45,.6),M(e.get('cab',{'color':(.05,.035,.03),'rough':.3})),.02)
   box('Television',(x,y+.05,1.45),(1.6,.06,.92),mat('black_glass',(.01,.01,.012),rough=.05,metal=.3),.01);box('Screen',(x,y+.015,1.45),(1.53,.01,.86),col(e.get('screen',(.05,.12,.25)),emit=1.0))
  piece(tvset,rot=rot,cx=x,cy=y)
 elif t=='massage_chair':
  x,y=e['at'];furn('massage_chair',x,y,e.get('rot',180))
 elif t=='heart_seat':
  x,y=e['at'];m=M(e.get('mat',{'color':(.75,.05,.12),'rough':.75}))
  for s in [-1,1]:ell('Heart lobe',(x+s*.45,y+.2,.9),(1.1,.5,1.0),m,16)
  o=box('Heart point',(x,y+.2,.5),(.8,.5,.8),m,.2);o.rotation_euler.y=math.radians(45);box('Heart seat cushion',(x,y-.35,.3),(1.6,.8,.4),m,.12)
 elif t=='birdcage':
  x,y=e['at'];m=M(e.get('mat','gold')) if e.get('mat','gold')!='gold' else mat('gold')
  for i in range(16):a=i*math.tau/16;tube('Birdcage bar',[(x+.7*math.cos(a),y+.7*math.sin(a),.05),(x+.75*math.cos(a),y+.75*math.sin(a),1.2),(x+.2*math.cos(a),y+.2*math.sin(a),2.1)],.018,m)
  ring('Birdcage base ring',(x,y,.05),.72,.72,.03,m,'xy');cyl('Birdcage cushion',(x,y,.25),.65,.35,M(e.get('cushion',{'color':(.9,.85,.75),'rough':.85})),n=32)
 elif t=='swing':
  x,y=e['at'];m=M(e.get('mat',{'color':(.9,.9,.9),'rough':.5}))
  for s in [-1,1]:tube('Swing rope',[(x+s*.35,y,h),(x+s*.35,y,.6)],.012,m)
  box('Swing seat',(x,y,.58),(.8,.4,.05),m,.02)
 elif t=='pole':
  x,y=e['at'];cyl('Dance pole',(x,y,h/2),.025,h,mat('chrome',(.75,.76,.78),rough=.08,metal=1.));cyl('Pole stage',(x,y,.08),.6,.16,M(e.get('mat',{'color':(.05,.05,.06),'rough':.2})),n=32)
  if e.get('glow'):ring('Stage glow',(x,y,.165),.58,.58,.02,col(e['glow'],emit=8.),'xy')
 elif t=='bar':
  x,y=e['at'];L=e.get('len',2.4);m=M(e.get('mat',{'color':(.08,.05,.04),'rough':.3}));top=M(e.get('top','marble_black'))
  box('Bar counter',(x,y,.52),(L,.55,1.04),m,.02);box('Bar top',(x,y,1.07),(L+.1,.65,.05),top,.01)
  for i in range(int(L/.8)):cyl('Bar stool',(x-L/2+.4+i*.8,y-.6,.38),.18,.06,M(e.get('stool',{'color':(.5,.05,.08),'rough':.6})));cyl('Stool stem',(x-L/2+.4+i*.8,y-.6,.18),.03,.36,mat('chrome',(.75,.76,.78),rough=.08,metal=1.))
 elif t=='fiber_curtain':
  # 'pitch'/'r'/'emit': 416 uses a dim champagne bead curtain (a sheer alpha drape still rendered as a solid pillar)
  x,y=e['at'];ww=e.get('w',2.0);pt=e.get('pitch',.05);m=col(e.get('color',(.6,.8,1.)),emit=e.get('emit',6.))
  for i in range(int(ww/pt)):cyl('Fiber strand',(x-ww/2+i*pt,y+.02*math.sin(i),h/2),e.get('r',.004),h-.1,m,n=4)
 elif t=='water_column':
  x,y=e['at'];cyl('Water column',(x,y,h/2),e.get('r',.5),h-.2,mat('water_col',tuple(e.get('color',(.4,.6,1.))),rough=.05,emit=2.,alpha=.5),n=32);cyl('Column base',(x,y,.1),e.get('r',.5)+.08,.2,mat('black_glass',(.01,.01,.012),rough=.05,metal=.3),n=32)
 elif t=='frames':
  side=e.get('side','left');n=e.get('n',3);a0,a1=e.get('range',(-2.5,1.5));z=e.get('z',1.8);fm=mat('gold') if e.get('frame','gold')=='gold' else M(e['frame']);art=M(e.get('art',{'color':(.8,.75,.6),'rough':.7}))
  for i in range(n):
   u=a0+(a1-a0)*(i+.5)/n;ww,hh=e.get('size',(.6,.8))
   if side=='left':plane('Framed art',(-w/2+.235,u,z),(ww,hh),art,'+x');frame('Art frame',(-w/2+.24,u,z),ww+.06,hh+.06,fm,.04,'y')
   elif side=='right':plane('Framed art',(w/2-.235,u,z),(ww,hh),art,'-x');frame('Art frame',(w/2-.24,u,z),ww+.06,hh+.06,fm,.04,'y')
   else:plane('Framed art',(u,6.50,z),(ww,hh),art,'-y');frame('Art frame',(u,6.49,z),ww+.06,hh+.06,fm,.04,'x')
 elif t=='plant':
  # 'scale': 510's planters must read as the photo's big leafy pots, not a bare tub with a tuft
  x,y=e['at'];k=e.get('scale',1.);cyl('Planter',(x,y,.3*k),.3*k,.6*k,M(e.get('pot',{'color':(.15,.1,.08),'rough':.5})),r2=.25*k)
  leaf=mat('plant_leaf',(.15,.38,.12),rough=.6)
  for i in range(int(14*k*k)):a=i*2.4;ell('Leaf',(x+.25*k*math.cos(a)*(i%3+1)/3,y+.25*k*math.sin(a)*(i%3+1)/3,(.8+.1*(i%5))*k),(.35*k,.08*k,.14*k),leaf,8).rotation_euler.z=a
 elif t=='bookshelf':
  side=e.get('side','left');a0,a1=e.get('range',(-2.5,1.5));m=M(e.get('mat',{'color':(.12,.06,.03),'tex':'wood_dark','tile':1.2,'rough':.4}));glow=col(e.get('glow',(1.,.75,.4)),emit=2.5)
  L=a1-a0;cx=(a0+a1)/2;xx=-w/2+.4 if side=='left' else w/2-.4
  box('Bookshelf case',(xx,cx,1.3),(.4,L,2.6),m,.02)
  for k in range(5):box('Shelf glow',(xx+(.19 if side=='left' else -.19),cx,.4+k*.5),(.02,L-.1,.3),glow)
 elif t=='desk':
  x,y=e['at'];m=M(e.get('mat',{'color':(.9,.88,.84),'rough':.4}));box('Vanity desk',(x,y,.38),(1.2,.5,.76),m,.02);ring('Vanity mirror ring',(x,y+.24,1.35),.35,.45,.03,mat('gold'),'xz');box('Desk stool',(x,y-.55,.24),(.45,.4,.48),M(e.get('stool',{'color':(.8,.7,.75),'rough':.8})),.08)
 elif t=='platform':
  x,y=e['at'];cyl('Round platform',(x,y,.08),e.get('r',2.0),.16,M(e.get('mat','marble_black')),n=48)
  if e.get('glow'):ring('Platform glow',(x,y,.17),e.get('r',2.0)-.03,e.get('r',2.0)-.03,.02,col(e['glow'],emit=8.),'xy')
 elif t=='neon':
  # 'emit': gold at 10 tone-maps to white (513 round 10)
  side=e.get('side','rear');x,y=e.get('at',(0,0));z=e.get('z',2.2);m=col(e.get('color',(1.,.2,.5)),emit=e.get('emit',10.));s=e.get('size',.6)
  pts=[(s*16*math.sin(a)**3/16,s*(13*math.cos(a)-5*math.cos(2*a)-2*math.cos(3*a)-math.cos(4*a))/16) for a in [i*math.tau/48 for i in range(48)]] if e.get('shape','heart')=='heart' else [(s*math.cos(i*math.tau/48),s*math.sin(i*math.tau/48)) for i in range(48)]
  if side=='left':tube('Neon',[(-w/2+.25,y+u,z+v) for u,v in pts],.02,m,True)
  elif side=='right':tube('Neon',[(w/2-.25,y-u,z+v) for u,v in pts],.02,m,True)
  else:tube('Neon',[(x+u,6.48,z+v) for u,v in pts],.02,m,True)
 elif t=='ceiling_fan':
  x,y=e['at'];m=M(e.get('mat',{'color':(.25,.15,.08),'rough':.5}));cyl('Fan rod',(x,y,h-.2),.02,.4,m)
  for i in range(5):a=i*math.tau/5;o=box('Fan blade',(x+.45*math.cos(a),y+.45*math.sin(a),h-.42),(.7,.14,.015),m);o.rotation_euler.z=a
 elif t=='furniture':
  if e['key'] not in furn_rx:print('SKIP furniture not registered',e['key']);return
  rx=furn_rx[e['key']]
  if not e.get('at') and rx.get('category')=='wall':
   # wall piece (mirror): flat against the left wall, facing +x, on the first stretch of wall nothing stands in front of
   if q['is_pool_suite']:print('SKIP furniture wall pool',e['key']);return
   xw=-w/2+.23+rx['size_m'][1]/2;fps=footprints();yw=None
   for y in [-4.5,-2.5,-6.0,-.5,1.5]:
    if all(not (u0<xw+.6 and v0<y+rx['size_m'][0]/2+.1 and v1>y-rx['size_m'][0]/2-.1) for (u0,u1,v0,v1) in fps):yw=y;break
   if yw is None:print('SKIP furniture no wall',e['key']);return
   furn(e['key'],xw,yw,-90,e.get('z',1.6-rx['h']/2));return
  if not e.get('at'):
   # auto: first clear spot from the signature-piece candidates (left wall band, then the front of the room)
   fw,fd=rx['size_m'][0]+.1,rx['size_m'][1]+.1
   p=auto_at(q,e,fw,fd,left_cands(q)+[(x,y,0) for x in (-2.,0.,2.,4.) for y in (-6.5,-7.5)]+[(-w/2+.9+fd/2,y,90) for y in (2.,3.5)])
   if not p:print('SKIP furniture no room',e['key']);return
   x,y,r=p;furn(e['key'],x,y,r,e.get('z',0));return
  x,y=e['at'];furn(e['key'],x,y,e.get('rot',0),e.get('z',0))
 elif t=='chair':seat(e)
 elif t=='diamonds':
  # four squares turned 45 degrees in a diamond cluster (the red/blue/black wall art of the H1 rooms)
  side=e.get('side','left');u=e.get('at',0.);z=e.get('z',2.0);s=e.get('size',.55);cols=e.get('colors',[[.75,.08,.08],[.08,.12,.5],[.75,.08,.08],[.04,.04,.06]]);off=s*.74
  for i,(du,dz) in enumerate([(0,off),(off,0),(0,-off),(-off,0)]):
   plane('Diamond art',(0,0,0),(s,s),col(cols[i%len(cols)],rough=.3),'+z');o=OBJS[-1];o.rotation_euler=(0,0,math.pi/4);bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
   if side=='left':o.rotation_euler=(math.pi/2,0,math.pi/2);o.location=(-w/2+.235,u+du,z+dz)
   elif side=='right':o.rotation_euler=(math.pi/2,0,-math.pi/2);o.location=(w/2-.235,u-du,z+dz)
   else:o.rotation_euler=(math.pi/2,0,0);o.location=(u+du,6.49,z+dz)
 elif t=='floor_patch':
  x,y=e['at'];ww,dd=e.get('size',(2.,2.));plane('Floor patch',(x,y,.004),(ww,dd),M(e['mat']),'+z')
 elif t=='box':
  box(e.get('name','Feature'),tuple(e['at']),tuple(e['size']),M(e['mat']),e.get('bevel',0))
 elif t=='portal':
  # 406: smooth slab portal with rounded inner top corners (box piers + lintel read as a square door frame). Built as
  # three prisms (two piers carrying the corner curves + a lintel) so the route check's bounding boxes keep the opening.
  (x0,x1),(xi0,xi1)=e['x'],e['opening'];y=e['y'];D=e.get('depth',.9);H=e.get('h',3.8);hi=e['opening_h'];R=e.get('r',.9);Ro=e.get('r_out',0.);m=M(e['mat'])
  def arc(cx,cz,r,a0,a1,n=12):return [(cx+r*math.cos(a0+(a1-a0)*k/n),cz+r*math.sin(a0+(a1-a0)*k/n)) for k in range(n+1)] if r>0 else [(cx,cz)]
  def prism(name,P):
   bm=bmesh.new();f=[bm.verts.new((u,y-D/2,v)) for u,v in P];b=[bm.verts.new((u,y+D/2,v)) for u,v in P];bm.faces.new(f);bm.faces.new(b[::-1])
   for i in range(len(P)):j=(i+1)%len(P);bm.faces.new((f[i],f[j],b[j],b[i]))
   bmesh.ops.recalc_face_normals(bm,faces=bm.faces);me=bpy.data.meshes.new(name);bm.to_mesh(me);bm.free()
   for p in me.polygons:p.use_smooth=len(p.vertices)==4
   o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);return reg(o,m)
  # straight piers and separate corner pieces: a pier carrying its curve had a bounding box reaching into the opening
  # from the floor up and failed the route check (406 round 12); the corner pieces start at hi-R, above the capsule
  prism('Arch portal pier',[(x0,0.)]+arc(x0+Ro,H-Ro,Ro,math.pi,math.pi/2)+[(xi0,H),(xi0,0.)])
  prism('Arch portal pier',[(xi1,0.),(xi1,H)]+arc(x1-Ro,H-Ro,Ro,math.pi/2,0.)+[(x1,0.)])
  prism('Arch portal corner',[(xi0,H),(xi0+R,H)]+arc(xi0+R,hi-R,R,math.pi/2,math.pi))
  prism('Arch portal corner',arc(xi1-R,hi-R,R,0.,math.pi/2)+[(xi1-R,H),(xi1,H)])
  box('Arch portal lintel',((xi0+xi1)/2,y,(hi+H)/2),(xi1-xi0-2*R,D,H-hi),m)
 elif t in ('trellis','padded_wall','filigree_screen'):wall_feature(e,q)
 elif t=='pipe_arches':
  # 213: tall red lacquered tube arches standing at both sides of the bed (the "Kama Sutra" frame), hook-curled tops
  x,y=e.get('at',(-3.34,4.7));W=e.get('w',3.0);H=e.get('h',3.1);m=M(e.get('mat',{'color':(.8,.06,.05),'rough':.25,'metal':.2}))
  for s in (-1,1):
   for k,(dy,hh) in enumerate(((-.9,H),(-.3,H*.86))):
    xx=x+s*(W/2-.1*k);pts=[(xx,y+dy-.6+1.2*(i/24),.02+hh*math.sin(i/24*math.pi)) for i in range(25)]
    tube('Pipe arch',pts,.045,m)
    ring('Pipe arch curl',(xx,y+dy+.62,.55),.18,.18,.04,m,'yz')
 elif t=='crystal_spiral':
  # 201 Hawaii: hanging spiral of glowing crystal drops (instead of straight fibre strands)
  x,y=e['at'];r=e.get('r',.6);H=e.get('drop',2.2);n=e.get('n',90);m=mat('crystal',(.9,.92,1.),rough=.02,emit=e.get('emit',1.2))
  for i in range(n):
   a=i*.35;t_=i/n;px,py,pz=x+r*(1-.5*t_)*math.cos(a),y+r*(1-.5*t_)*math.sin(a),h-.2-H*t_
   cyl('Crystal spiral string',(px,py,(h+pz)/2),.003,h-pz,mat('chrome',(.75,.76,.78),rough=.08,metal=1.),n=4);ell('Crystal spiral drop',(px,py,pz),(.07,.07,.11),m,8)
  COVE.append(((x,y,h-1.0),(.85,.9,1.),600,300))
 elif t=='sunburst_mirror':
  # 307: round mirror in a gold sunflower / sunburst frame on a wall (side, at = u along the wall, z)
  P,ax=wall_frame(e.get('side','rear'),q,0.);u=e.get('at',-3.34);z=e.get('z',2.1);r=e.get('r',.45)
  mir=mat('mirror_wall',(.72,.72,.75),rough=.03,metal=1.);g=mat('gold')
  c=cyl('Sunburst mirror',P(u,z,.05),r,.02,mir,n=48)
  if ax=='x':c.rotation_euler.x=math.pi/2
  else:c.rotation_euler.y=math.pi/2
  for i in range(24):
   a=i*math.tau/24;L=.28 if i%2 else .42;p0=(u+(r+.02)*math.cos(a),z+(r+.02)*math.sin(a));p1=(u+(r+L)*math.cos(a),z+(r+L)*math.sin(a))
   tube('Sunburst ray',[P(p0[0],p0[1],.05),P(p1[0],p1[1],.05)],.018 if i%2 else .026,g)
  ring('Sunburst rim',P(u,z,.06),r+.03,r+.03,.03,g,'xz' if ax=='x' else 'yz')
 elif t=='bubble_pendant':
  # 307: cluster of glowing glass bubbles on cords at different heights
  x,y=e['at'];n=e.get('n',9);gm=col(e.get('glow',(1.,.85,.6)),emit=e.get('emit',4.))
  for i in range(n):
   a=i*2.4;rr=.35*math.sqrt((i+.5)/n);px,py=x+rr*math.cos(a),y+rr*math.sin(a);pz=h-.7-.6*((i*.618)%1);s_=.12+.06*((i*.37)%1)
   cyl('Bubble cord',(px,py,(h+pz)/2),.004,h-pz,mat('black_metal',(.02,.02,.02),rough=.35,metal=.6),n=4);ell('Bubble pendant',(px,py,pz),(s_*2,s_*2,s_*2),gm,16)
  COVE.append(((x,y,h-1.2),tuple(e.get('glow',(1.,.85,.6))),900,450))
 elif t=='drip_frieze':
  # 312: white "icing" dripping from the top of a wall (side, range), pastel band behind it
  P,ax=wall_frame(e.get('side','left'),q,0.);u0,u1=e.get('range',(-4.,4.));z=e.get('z',h-.5);m=M(e.get('mat',{'color':(.97,.96,.94),'rough':.3}))
  wbox('Drip frieze lining band',P,ax,(u0+u1)/2,z,.02,u1-u0,.22,.04,m)
  i=0;u=u0+.1
  while u<u1-.1:
   L=.12+.28*((i*.618)%1);ell('Drip lining icing',P(u,z-.11-L/2,.04),(.1,.06,L) if ax=='x' else (.06,.1,L),m,10);u+=.18+.1*((i*.37)%1);i+=1
 elif t=='lollipop':
  # 312: giant green swirl lollipops on sticks (at = list of [x,y])
  r=e.get('r',.32);zc=1.13+r
  for (x,y) in e['at']:
   cyl('Lollipop stick',(x,y,zc/2),.03,zc,mat('stick_white',(.97,.97,.95),rough=.4),n=8);c=cyl('Lollipop disc',(x,y,zc),r,.08,M(e.get('mat',{'color':(.35,.85,.35),'rough':.3})),n=40);c.rotation_euler.x=math.pi/2
   tube('Lollipop swirl',[(x+r*.88*(k/60)*math.cos(k*.42),y-.05,zc+r*.88*(k/60)*math.sin(k*.42)) for k in range(61)],.018*r/.32,mat('swirl_white',(.98,.98,.96),rough=.3))
 elif t=='gazebo':
  # 205: thatched-roof pavilion (four posts, pyramid of straw) over a lounge spot
  x,y=e['at'];s_=e.get('size',2.6);hh=e.get('h',2.5);z0=e.get('z',0.);nl=e.get('layers',6);wood=M(e.get('mat',{'color':(.42,.28,.15),'rough':.7}));straw=M(e.get('roof',{'color':(.72,.58,.32),'rough':.95}))
  for sx in (-1,1):
   for sy in (-1,1):cyl('Gazebo post',(x+sx*s_/2,y+sy*s_/2,z0+hh/2),.07,hh,wood,n=10)
  for k in range(nl):
   rr=s_*.75*(1-k/nl);cyl('Gazebo thatch',(x,y,z0+hh+.06+k*.13),rr,.16,straw,r2=rr*.85,n=4).rotation_euler.z=math.pi/4
 elif t=='hanging_chair':
  # 205: rattan egg / basket chair hung from the ceiling
  x,y=e['at'];z0=e.get('z',0.);m=M(e.get('mat',{'color':(.62,.45,.25),'rough':.85}))
  cyl('Hanging chair rope',(x,y,(h+z0+1.6)/2),.015,h-z0-1.6,mat('rope',(.8,.68,.45),rough=.9),n=6)
  ell('Hanging chair shell',(x,y,z0+1.05),(1.0,.95,1.2),m,20);ell('Hanging chair cushion',(x,y-.12,z0+.72),(.75,.6,.18),M(e.get('cushion',{'color':(.95,.93,.88),'rough':.9})),16)
 elif t=='film_strip':
  # 214: black film-strip band with sprocket holes along a wall top, posters below (side, range)
  P,ax=wall_frame(e.get('side','left'),q,0.);u0,u1=e.get('range',(-4.,4.));z=e.get('z',h-.6)
  wbox('Film strip lining',P,ax,(u0+u1)/2,z,.02,u1-u0,.36,.03,mat('film_black',(.02,.02,.02),rough=.3))
  u=u0+.1
  while u<u1-.05:
   for dz in (-.13,.13):wbox('Film strip lining hole',P,ax,u,z+dz,.035,.06,.05,.01,mat('film_hole',(.95,.92,.8),rough=.4,emit=1.5))
   u+=.16
  for i,pc in enumerate(e.get('posters',[[.8,.2,.15],[.15,.3,.6],[.9,.7,.2]])):
   uu=u0+(u1-u0)*(i+.5)/len(e.get('posters',[0,0,0]));wbox('Poster lining',P,ax,uu,z-1.0,.02,.7,1.0,.02,col(pc,emit=.6))
   for (du,dz,su,sz) in ((0,-.52,.78,.05),(0,.52,.78,.05),(-.37,0,.05,1.04),(.37,0,.05,1.04)):wbox('Poster lining frame',P,ax,uu+du,z-1.0+dz,.04,su,sz,.03,mat('gold'))
 elif t=='ceiling_neon':
  # closed wavy neon line under the ceiling (312): rectangle x0..x1 / y0..y1 with a sine offset of 'amp', 'waves' per metre
  x0,x1,y0,y1=e.get('rect',(-w/2+1.4,w/2-1.4,-d/2+1.4,6.0));amp=e.get('amp',.25);k=e.get('waves',.6);z=h-e.get('drop',.42);pts=[]
  P=2*((x1-x0)+(y1-y0));n=max(80,int(P*12))
  for i in range(n):
   s=i/n*P
   if s<x1-x0:px,py,nx,ny=x0+s,y0,0,1
   elif s<(x1-x0)+(y1-y0):px,py,nx,ny=x1,y0+s-(x1-x0),-1,0
   elif s<2*(x1-x0)+(y1-y0):px,py,nx,ny=x1-(s-(x1-x0)-(y1-y0)),y1,0,-1
   else:px,py,nx,ny=x0,y1-(s-2*(x1-x0)-(y1-y0)),1,0
   o=amp*math.sin(s*k*math.tau);pts.append((px+nx*o,py+ny*o,z))
  tube('Ceiling neon',pts,.022,col(e.get('color',(.2,.55,1.)),emit=e.get('emit',12.)),True)
  COVE.append(((0,(y0+y1)/2,z-.2),tuple(e.get('color',(.2,.55,1.))),900,500))
# ---------- occupancy: auto-placed signature pieces and the densifier only go where nothing stands and off the walk corridor
SKIP=('Floor','floor','Rug','rug','Ceiling','ceiling','Wall','wall','lining','Front','Rear','Side wall','Partition','Pool','Water','Cove','Tray','Downlight','Chandelier','Crystal','LED','Mirror','Skylight','Mural','mosaic','Sconce','Opening','Lantern','Dome','star','Drape')
def footprints():
 out=[]
 for o in OBJS:
  if o.type!='MESH' or any(k in o.name for k in SKIP):continue
  cs=[o.matrix_world@Vector(b) for b in o.bound_box];lo=[min(c[k] for c in cs) for k in range(3)];hi=[max(c[k] for c in cs) for k in range(3)]
  if hi[2]<.06 or lo[2]>1.8:continue
  out.append((lo[0],hi[0],lo[1],hi[1]))
 return out
def corridor(q):
 w=q['size_m'][0];pool=q['is_pool_suite'];doorx=w*.29
 segs=[((doorx,-11.2),(doorx,-5.0)),((doorx,-5.0),(w/2-1.25,-5.0)),((w/2-1.25,-5.0),(w/2-1.25,2.1)),((w/2-1.25,2.1),(-.54 if not pool else 7.06,2.1))]
 return segs+([((w/2-1.25,2.1),(13.7,7.1))] if pool else [((-.54,2.1),(-.54,1.2))])
def free(q,x0,x1,y0,y1,pad=.12):
 w,d,h=q['size_m'];pool=q['is_pool_suite'];lx=-.6 if pool else -w/2+.25
 if x0<lx or x1>w/2-.25 or y0<-d/2+.25 or y1>6.45:return False
 if q['has_in_room_garage'] and x1>-w*.25-2.2 and x0<-w*.25+2.2 and y0<-d/2+6.5:return False  # car bay
 for (a,b) in corridor(q):
  cx0,cx1=sorted([a[0],b[0]]);cy0,cy1=sorted([a[1],b[1]]);r=.5
  if x0<cx1+r and x1>cx0-r and y0<cy1+r and y1>cy0-r:return False
 for (u0,u1,v0,v1) in footprints():
  if x0<u1+pad and x1>u0-pad and y0<v1+pad and y1>v0-pad:return False
 return True
def auto_at(q,e,fw,fd,cands):
 # e['at'] wins; otherwise the first free candidate (x,y,rot) whose footprint (fw x fd, rotated) is clear
 if e.get('at'):return tuple(e['at'])+(e.get('rot',0),)
 for (x,y,r) in cands:
  a,b=(fw,fd) if r%180==0 else (fd,fw)
  if free(q,x-a/2,x+a/2,y-b/2,y+b/2):return (x,y,r)
 return None
def left_cands(q):
 w=q['size_m'][0];pool=q['is_pool_suite']
 if pool:return [(1.2+i*1.6,-6.5,0) for i in range(5)]+[(.4,-1-i*1.5,90) for i in range(4)]
 return [(-w/2+.9,y,90) for y in (-1.,-2.5,.5,-4.,-5.5)]+[(-4.5,y,0) for y in (-1.5,-3.5,-5.5)]
def k_heart_booth(e,q):
 p=auto_at(q,e,3.2,1.3,[] if e.get("at") else left_cands(q))
 if not p:print('SKIP heart_booth no room');return
 x,y,r=p;m=M(e.get('mat','velvet_tufted_red'));dark=col((.03,0,.01));btn=M({'color':(.12,.02,.03)})
 def build():
  box('Booth back',(x,y+.5,1.35),(3.2,.3,2.7),m,.08);box('Booth seat',(x,y,.24),(3.2,1.0,.48),m,.08);box('Booth seat cushion',(x,y-.05,.55),(3.0,.85,.16),m,.06)
  for s in [-1,1]:box('Booth wing',(x+s*1.5,y+.05,.95),(.22,1.0,1.9),m,.08)
  rr=.38;zc=1.75
  for s in [-1,1]:cyl('Booth heart cutout',(x+s*rr*.8,y+.34,zc),rr,.03,dark,n=32).rotation_euler.x=math.pi/2
  o=box('Booth heart cutout point',(x,y+.34,zc-rr*.55),(rr*1.55,.03,rr*1.55),dark);o.rotation_euler.y=math.radians(45)
  cushion_tufts(x-1.45,x+1.45,y+.34,.7,2.6,btn,12,8)
  for i in range(3):box('Booth pillow',(x-.9+i*.9,y+.22,.85),(.55,.2,.45),M(e.get('pillow',{'color':(.45,.05,.08),'rough':.7})),.08)
 piece(build,rot=r,cx=x,cy=y)
def k_swing_bed(e,q):
 h=q['size_m'][2];p=auto_at(q,e,2.3,1.7,[(-4.5,-2.0,0),(-4.5,-4.2,0),(-4.5,.2,0)]+left_cands(q))
 if not p:print('SKIP swing_bed no room');return
 x,y,r=p;m=M(e.get('mat',{'color':(.95,.93,.9),'rough':.8}));rope=M(e.get('rope',{'color':(.8,.65,.3),'rough':.7}))
 def build():
  box('Swing bed deck',(x,y,.5),(2.1,1.5,.14),M(e.get('deck',{'color':(.85,.7,.35),'metal':.6,'rough':.35})),.03);box('Swing bed cushion',(x,y,.65),(2.0,1.4,.18),m,.08)
  for i in range(2):box('Swing bed pillow',(x-.45+i*.9,y+.5,.85),(.75,.25,.35),m,.08)
  for sx in [-1,1]:
   for sy in [-1,1]:
    cyl('Swing bed rope',(x+sx*.98,y+sy*.68,(h+.55)/2),.02,h-.55,rope,n=8)
    if e.get('vines'):
     for k in range(9):ell('Swing vine leaf',(x+sx*.98+.05*math.sin(k*1.7),y+sy*.68,.8+k*.3),(.12,.05,.08),M(e.get('leaf',{'color':(.2,.45,.15)})),8)
 piece(build,rot=r,cx=x,cy=y)
def k_folding_screen(e,q):
 n=e.get('panels',4);p=auto_at(q,e,.55*n,.45,left_cands(q)+[(-w2,y,0) for w2 in (2.,3.) for y in (-6.,-7.)])
 if not p:print('SKIP folding_screen no room');return
 x,y,r=p;m=M(e.get('mat',{'color':(.7,.08,.06),'rough':.5}));fr=M(e.get('frame',{'color':(.05,.03,.02),'rough':.35}))
 def build():
  for i in range(n):
   px=x+(i-(n-1)/2)*.52;py=y+(.1 if i%2 else -.1);rz=.35 if i%2 else -.35
   box('Screen panel',(px,py,1.0),(.5,.04,1.8),m,rz=rz);box('Screen frame',(px,py,1.92),(.54,.06,.05),fr,rz=rz);box('Screen frame',(px,py,.08),(.54,.06,.05),fr,rz=rz)
 piece(build,rot=r,cx=x,cy=y)
def k_arch_mirror(e,q):
 # arched mirror on the left wall (side 'left'), optional bulb frame (Hollywood style)
 w,d,h=q['size_m'];aw,ah=e.get('w',1.4),e.get('h',2.2);xw=-w/2+.24
 if q['is_pool_suite']:print('SKIP arch_mirror pool');return
 fps=footprints();y0=None
 for y in ([e['at'][1]] if e.get('at') else [-4.5,-2.5,-6.0,-.5]):
  if all(not (u0<xw+.6 and v0<y+aw/2+.1 and v1>y-aw/2-.1) for (u0,u1,v0,v1) in fps):y0=y;break
 if y0 is None:print('SKIP arch_mirror no wall');return
 mir=mat('mirror_wall',(.72,.72,.75),rough=.03,metal=1.);fr=mat('gold') if e.get('frame','gold')=='gold' else M(e['frame'])
 plane('Arch mirror',(xw,y0,.4+(ah-aw/2)/2),(aw,ah-aw/2),mir,'+x')
 cyl('Arch mirror top',(xw,y0,.4+ah-aw/2),aw/2,.01,mir,n=40).rotation_euler.y=math.pi/2
 pts=[(xw+.01,y0-aw/2,.4)]+[(xw+.01,y0-aw/2*math.cos(k*math.pi/24),.4+ah-aw/2+aw/2*math.sin(k*math.pi/24)) for k in range(25)]+[(xw+.01,y0+aw/2,.4)]
 tube('Arch mirror frame',pts,.04,fr)
 if e.get('bulbs'):
  for (px,py,pz) in pts[::2]:ell('Mirror bulb',(px+.04,py,pz),(.07,.07,.07),col((1.,.92,.75),emit=6.),8)
KITS={'heart_booth':k_heart_booth,'swing_bed':k_swing_bed,'folding_screen':k_folding_screen,'arch_mirror':k_arch_mirror}
def floor_lamp(x,y,shade):
 cyl('Floor lamp base',(x,y,.02),.18,.04,mat('gold'),n=24);cyl('Floor lamp pole',(x,y,.8),.015,1.55,mat('gold'),n=8);cyl('Floor lamp shade',(x,y,1.6),.24,.34,shade,r2=.17,n=24)
def furnish(s,q,bx,by,lc,pool,Ms):
 # Rooms are 15 x 21 m and read empty next to the photos: add the pieces a real suite has wherever there is room.
 f=s.get('furnish',{})
 if f is False:return []
 lit=[];shade=M(s['bed'].get('shade',{'color':(1.,.85,.6),'emit':1.6}));lampc=tuple(s.get('light',{}).get('lamp',(1.,.72,.45)))
 seats=s.get('living',{}).get('seats',[]);sm=M(seats[0].get('mat',{'color':(.4,.1,.1)})) if seats else Ms['cabinet']
 # a living set around the coffee table when the spec has fewer than two seats (the photos always show a sofa group)
 if len(seats)<2:
  kind=next((se.get('kind') for se in seats if se.get('kind') in ('baroque','chesterfield','modern','curved')),'modern')
  base=dict(mat=seats[0].get('mat') if seats else {'color':(.55,.45,.35),'rough':.8},frame=seats[0].get('frame','gold') if seats else 'gold')
  for (x,y,r,k,L) in [(lc[0],lc[1]+1.45,0,kind,2.4),(lc[0]-1.65,lc[1],90,'tub',0),(lc[0]+1.65,lc[1],-90,'tub',0)]:
   fw,fd=(L+.2 if L else .95),.95
   a,b=(fw,fd) if r%180==0 else (fd,fw)
   if free(q,x-a/2,x+a/2,y-b/2,y+b/2):se=dict(base,at=[x,y],rot=r,kind=k);seat(se);seats=seats+[se] if k==kind else seats
 # bench at the foot of the bed
 if not s['bed'].get('shape')=='round' and free(q,bx-.95,bx+.95,by-1.95,by-1.45):
  box('Bed end bench',(bx,by-1.7,.24),(1.8,.48,.42),sm,.06);box('Bench legs',(bx,by-1.7,.04),(1.7,.4,.08),Ms['cabinet'])
 # floor lamp + side table at the ends of each sofa
 for se in seats:
  if se.get('kind','modern') not in ('baroque','chesterfield','modern','curved'):continue
  x,y=se['at'];L=se.get('len',2.4);a=math.radians(se.get('rot',0));ex,ey=math.cos(a),math.sin(a)
  for k,sgn in enumerate([-1,1]):
   px,py=x+sgn*ex*(L/2+.45),y+sgn*ey*(L/2+.45)
   if not free(q,px-.3,px+.3,py-.3,py+.3):continue
   if k==0:floor_lamp(px,py,shade);lit.append(((px,py,1.55),lampc,350,300))
   else:
    cyl('Side table',(px,py,.28),.28,.56,Ms['cabinet'],n=32);cyl('Side table top',(px,py,.575),.3,.03,M('marble_black'),n=32)
    # Tripo table lamps: side_lamp on the first sofa-end side table, side_lamp2 on the next
    lk=None
    if f:
     for slot in ('side_lamp','side_lamp2'):
      if f.get(slot) and f[slot] in furn_rx and not f.get('_done_'+slot):lk=f[slot];f['_done_'+slot]=True;break
    if lk:furn(lk,px,py,0,.59);lit.append(((px,py,.59+furn_rx[lk].get('h',.6)*.7),lampc,250,250))
    else:ell('Side table vase',(px,py,.75),(.16,.16,.3),mat('gold'),12)
 # console + vase + framed picture against the left wall (not in pool suites: the left half is the pool hall)
 if not pool:
  w=q['size_m'][0];xw=-w/2+.5
  for y in (-1.5,.5,-3.5,-5.5):
   if free(q,xw-.23,xw+.23,y-.85,y+.85):
    box('Console',(xw,y,.42),(.45,1.6,.84),Ms['cabinet'],.02);box('Console top',(xw,y,.86),(.5,1.66,.04),M('marble_black'))
    ell('Console vase',(xw,y-.45,1.1),(.22,.22,.45),mat('gold'),12);ell('Console flowers',(xw,y-.45,1.45),(.4,.4,.35),M({'color':(.75,.15,.25),'rough':.8}),12)
    plane('Console picture',(-w/2+.225,y,1.75),(1.2,.8),M(s.get('furnish_art',{'color':(.35,.22,.15),'rough':.6})),'+x');frame('Console picture frame',(-w/2+.235,y,1.75),1.2,.8,mat('gold'),.05,'y')
    break
 # potted plants in free corners
 w,d=q['size_m'][0],q['size_m'][1]
 for (x,y) in [(-w/2+.7,-d/2+.7),(-w/2+.7,6.0),(w/2-.7,6.0),(-.2 if pool else -w/2+.7,-3.0)]:
  if free(q,x-.35,x+.35,y-.35,y+.35):
   cyl('Plant pot',(x,y,.3),.3,.6,Ms['cabinet'],r2=.24,n=24)
   for k in range(9):ell('Plant leaf',(x+.25*math.cos(k*2.4),y+.25*math.sin(k*2.4),.9+.08*(k%3)),(.45,.16,.06),M({'color':(.12,.35,.1),'rough':.6}),8)
 return lit
# round 12: at .72 the water was lit lilac-white by the bright bath lights (translucency uses the coarse volume lighting);
# a darker, more opaque tint keeps it reading as water in white bathrooms
TUB_WATER={'color':[.01,.07,.09],'opacity':.85}
def bath(bt,o,C,q):
 w=q['size_m'][0];bathx=o['bathx'];k=bt.get('tub','rect');shell=M(bt.get('surround',bt.get('wall','marble_cream')))
 # tub water is its own slot (S_TubWater -> MI_PoolWater_TubWater at install): the shared M_SpaWater (opacity .38) let
 # the white basin show through and every v-bath read as an empty white bowl; bath.water {color, opacity} overrides
 TW=mat('TubWater',tuple((bt.get('water') or {}).get('color',TUB_WATER['color'])),rough=.05)
 if k=='round':hollow_tub('Round jacuzzi',(bathx+.65,8.4,.0),(2.0,2.0),shell,C['porcelain'],TW,False,.18,.62)
 elif k=='platform':
  # raised stone deck with a sunken round jacuzzi and a front step (the common "stone tub stage" in the photos)
  box('Tub stone deck',(bathx+.6,8.55,.25),(3.3,2.9,.5),shell,.03);box('Tub deck step',(bathx+.6,6.98,.1),(2.2,.36,.2),shell,.02)
  hollow_tub('Deck jacuzzi',(bathx+.6,8.55,.5),(2.1,2.1),shell,C['porcelain'],TW,False,.16,.5)
  # emit 8 lit the basin and the water lilac-white from the rim (406, round 12)
  if bt.get('glow'):ring('Tub LED ring',(bathx+.6,8.55,.98),.92,.92,.02,col(bt['glow'],emit=bt.get('glow_emit',2.5)),'xy')
 elif k=='oval':
  # freestanding oval soaking tub with a floor-standing filler
  x,y=bathx+.6,8.6;hollow_tub('Oval tub',(x,y,.0),(1.85,1.0),C['porcelain'],C['porcelain'],TW,False,.08,.62)
  cyl('Tub filler',(x+1.1,y,.5),.025,1.0,mat('chrome',(.85,.85,.88),rough=.1,metal=1.),n=12);box('Tub filler spout',(x+1.0,y,1.0),(.25,.04,.04),mat('chrome',(.85,.85,.88),rough=.1,metal=1.))
  plane('Tub floor mat',(x,y,.004),(2.4,1.5),M(bt.get('surround','marble_black')),'+z')
 elif k=='sunken':
  # 510: tub set into a low wide deck on a floor-level dark stone frame (photo: rim near floor level among planters), on
  # the rect plinth footprint the routes were verified with but only 0.26 m high
  x,y=bathx+.6,8.55;dz=.26;acr=mat('acrylic',(.95,.95,.93),rough=.1)
  plane('Tub floor frame',(x,y,.004),(3.3,3.0),M(bt.get('frame',{'color':(.06,.05,.04),'rough':.2})),'+z')
  hollow_tub('Sunken jacuzzi',(x,y,0.),(2.7,2.4),shell,acr,TW,True,.4,dz)
 elif k=='clawfoot':
  # hollow slipper tub on claw feet (the solid ellipsoid read as a white blob from the v-bath camera): open oval basin,
  # rolled rim, raised back end, chrome deck filler
  x,y=bathx+.6,8.7;hollow_tub('Clawfoot tub',(x,y,.14),(1.75,.85),C['porcelain'],C['porcelain'],TW,False,.06,.52)
  ring('Clawfoot rolled rim',(x,y,.67),.875,.425,.03,C['porcelain'],'xy');ell('Clawfoot tub belly',(x,y,.3),(1.7,.8,.36),C['porcelain'],24)
  box('Clawfoot slipper back',(x-.78,y,.75),(.16,.6,.2),C['porcelain'],.06)
  tube('Clawfoot filler',[(x+.95,y,.0),(x+.95,y,.95),(x+.8,y,.95)],.02,mat('chrome',(.85,.85,.88),rough=.1,metal=1.))
  for xx in [-.65,.65]:
   for yy in [-.28,.28]:ell('Claw foot',(x+xx,y+yy,.06),(.1,.1,.12),mat('gold'),8)
 else:
  # rect: wide stone deck (the plinth footprint the routes were verified with) with a smaller inset tub pushed to the
  # back wall, so the front ledge reads as a stone counter (photos 302/304/305/314/316/401/402); a low step in front.
  x,y=bathx+.6,8.55;X0,X1,Y0,Y1=x-1.35,x+1.35,y-1.2,y+1.2;tw,td=1.87,1.27;tx,ty=x,Y1-.31-td/2;dz=.58
  acr=mat('acrylic',(.95,.95,.93),rough=.1);edge=M(bt.get('ledge_trim',{'color':(.08,.06,.05),'rough':.3}))
  box('Tub deck step',(x,Y0+.16,.1),(2.7,.32,.2),shell,.01)
  box('Tub deck front ledge',(x,(Y0+.32+ty-td/2)/2,dz/2),(2.7,ty-td/2-Y0-.32,dz),shell,.01)
  box('Tub deck back ledge',(x,(ty+td/2+Y1)/2,dz/2),(2.7,Y1-ty-td/2,dz),shell,.01)
  for s in [-1,1]:box('Tub deck side ledge',(x+s*(tw/2+(1.35-tw/2)/2),ty,dz/2),(1.35-tw/2,td,dz),shell,.01)
  box('Tub deck nosing',(x,Y0+.32,dz-.02),(2.72,.05,.04),edge,.01)
  hollow_tub('Jacuzzi',(tx,ty,0.),(tw,td),acr,acr,TW,True,.06,dz)
  # ledge dressing: rolled towels, pillar candles, toiletries and a small orchid on the front counter
  towel=M(bt.get('towel',{'color':(.96,.95,.92),'rough':.95}));ly=(Y0+.32+ty-td/2)/2
  for k in range(3):cyl('Rolled towel',(x-1.05+k*.17,ly,dz+.07),.07,.32,towel,n=16).rotation_euler.x=math.pi/2
  for k,hh in enumerate((.18,.12,.24)):cyl('Pillar candle',(x+.55+k*.13,ly-.05,dz+hh/2),.04,hh,mat('candle_wax',(.97,.93,.85),rough=.6));cyl('Candle flame',(x+.55+k*.13,ly-.05,dz+hh+.02),.008,.03,col((1.,.7,.3),emit=12.),n=6)
  for k,c in enumerate(((.85,.8,.7),(.25,.2,.18))):cyl('Toiletry bottle',(x+1.05,ly-.12+k*.12,dz+.09),.035,.18,mat('bottle%d'%k,c,rough=.3),n=12)
  cyl('Orchid pot',(x-.2,ly,dz+.06),.07,.12,mat('orchid_pot',(.95,.95,.95),rough=.2),n=16)
  for k in range(5):ell('Orchid bloom',(x-.2+.06*math.cos(k*1.3),ly+.03*math.sin(k*1.3),dz+.32+.03*k),(.06,.03,.05),mat('orchid',(.95,.75,.9),rough=.6),8)
  COVE.append(((tx,ty,dz+.5),tuple(bt.get('glow',(1.,.8,.55))),300,200))
 if bt.get('vines'):
  leaf=mat('ficus_leaf',(.18,.42,.12),rough=.6);bark=mat('ficus_bark',(.25,.18,.10),rough=.8)
  for kk in range(5):
   x0=bathx-.5+kk*.55;tube('Ficus vine',[(x0+.15*math.sin(t*2+kk),10.1,3.4-t*1.2) for t in [i/8 for i in range(9)]],.018,bark)
   for i in range(12):tt=i/11;ell('Ficus leaf',(x0+.15*math.sin(tt*2+kk)+.12*math.cos(i*2.1),10.05,3.4-tt*1.2),(.12,.03,.07),leaf,8)
 if bt.get('tv'):box('Bath TV',(bathx+.6,10.12,1.6),(.7,.04,.42),mat('black_glass',(.01,.01,.012),rough=.05,metal=.3));box('Bath TV frame',(bathx+.6,10.14,1.6),(.78,.02,.5),mat('gold'))
 if bt.get('sconces',True):
  for xx in [o['vx']-1.0,o['vx']+1.0]:cyl('Bath sconce',(xx,10.08,1.85),.06,.22,col(bt.get('sconce',(1.,.82,.58)),emit=3.),n=16)
 if bt.get('band'):plane('Bath border',((w*.055+w/2-.2)/2,10.14,2.6),(w/2-.2-w*.055,.12),M(bt['band']),'-y')
def build_room(q,s):
 C=common(q);w,d,h=q['size_m'];pool=q['is_pool_suite'];COVE.clear()
 Ms=dict(C,floor=M(s['floor']),wall=M(s['wall']),front=M(s.get('front',s['wall'])),wood=M(s.get('trim',{'color':(.15,.08,.05),'tex':'wood_dark','tile':1.0,'rough':.35})),
  cabinet=M(s.get('cabinet',{'color':(.08,.05,.04),'tex':'wood_dark','tile':1.0,'rough':.35})),bathwall=M(s['bath'].get('wall','marble_cream')),bathfront=M(s['bath'].get('front',s['bath'].get('wall','marble_cream'))),
  bathfloor=M(s['bath'].get('floor','marble_black')),vanity=M(s['bath'].get('vanity',{'color':(.05,.035,.03),'tex':'wood_dark','tile':1.0,'rough':.3})),counter=M(s['bath'].get('counter','marble_black')),
  mirrorframe=mat('gold') if s['bath'].get('mirrorframe','gold')=='gold' else M(s['bath']['mirrorframe']),rectbasin=s['bath'].get('rectbasin',False),glassfront=s['bath'].get('glassfront',False))
 o=shell(q,Ms,pool)
 if not s['bath'].get('glassfront'):pass
 c=dict(s.get('ceiling',{}))
 if pool:c['x0']=-.9
 ceiling(c,q)
 if not pool:box('Partition behind bed',(-(w/2-.2)+(w/2-.2+w*.055)/2,6.66,h/2),(w/2-.2+w*.055,.16,h),Ms['wall'])
 else:box('Partition behind bed',(3.49,6.62,h/2),(3.64,.16,h),Ms['wall']);pool_hall(s.get('pool',{}),q,C)
 for wl in s.get('walls',[]):
  g=wl['mat'].get('gen',{}) if isinstance(wl['mat'],dict) else {}
  if g.get('kind')=='lattice' and not wl.get('flat') and not (pool and wl['side']=='rear'):
   # printed gold lattice -> plain ground + real metal trellis bars in front (212, 213, 201 Hawaii, 101 ...)
   lining(wl['side'],M({'color':g.get('bg',(.05,.04,.04)),'rough':wl['mat'].get('rough',.3)}),q,wl.get('x0'),wl.get('x1'),wl.get('z0',0.),wl.get('z1'))
   dflt={'left':(-3.2,6.5),'right':(-4.6,6.5),'rear':(-w/2+.25,w/2-.25),'front':(-w/2+.3,w*.29-.9)}[wl['side']]
   a0,a1=(wl.get('x0') if wl.get('x0') is not None else dflt[0]),(wl.get('x1') if wl.get('x1') is not None else dflt[1])
   spans=[(a0,a1)]
   if wl['side']=='rear':bx_=w*.28;spans=[(u0,u1) for (u0,u1) in [(a0,min(a1,bx_-1.25)),(max(a0,bx_+1.65),a1)] if u1-u0>.6]
   z0,z1=wl.get('z0',0.),(wl.get('z1') if wl.get('z1') is not None else h)
   if wl['side']!='front':
    for (u0,u1) in spans:wall_feature(dict(type='trellis',side=wl['side'],range=(u0+.05,u1-.05),z=(max(z0,.1),min(z1,h-.4)),back='none',pitch=.5,bar={'color':g.get('fg',(.85,.65,.25)),'rough':.3,'metal':.85}),q)
   continue
  lining(wl['side'],M(wl['mat']),q,wl.get('x0'),wl.get('x1'),wl.get('z0',0.),wl.get('z1'))
  # a printed 'tufted' lining reads flat in game: raise real diamond upholstery over it (its colours), split around the
  # bath opening on the rear wall; pool suites keep the print. 'flat': true in the spec keeps the old look.
  g=wl['mat'].get('gen',{}) if isinstance(wl['mat'],dict) else {}
  if g.get('kind')=='tufted' and not wl.get('flat') and wl['side'] in ('left','right','rear') and not (pool and wl['side']=='rear'):
   dflt={'left':(-3.2,6.5),'right':(-4.6,6.5),'rear':(-w/2+.25,w/2-.25)}[wl['side']]
   a0,a1=(wl.get('x0') if wl.get('x0') is not None else dflt[0]),(wl.get('x1') if wl.get('x1') is not None else dflt[1])
   spans=[(a0,a1)]
   if wl['side']=='rear':bx_=w*.28;spans=[(u0,u1) for (u0,u1) in [(a0,min(a1,bx_-1.25)),(max(a0,bx_+1.65),a1)] if u1-u0>.6]
   fg=g.get('fg',(.5,.2,.3));z0,z1=wl.get('z0',0.),(wl.get('z1') if wl.get('z1') is not None else h)
   for (u0,u1) in spans:wall_feature(dict(type='padded_wall',side=wl['side'],range=(u0+.05,u1-.05),z=(max(z0,.35)+.05,min(z1,h-.45)-.05),pattern='diamond',size=.4,
    mats=[{'color':fg,'rough':.55},{'color':[c*.86 for c in fg],'rough':.55}],button={'color':g.get('line',(.05,.03,.03)),'rough':.4,'metal':.3}),q)
 bx,by=bed(s['bed'],q)
 lv=s.get('living',{});tops=[]
 if lv.get('rug'):rug(lv['rug'])
 for se in lv.get('seats',[]):seat(se)
 if lv.get('table'):tops.append((lv['table']['at'],table(lv['table'])))
 for t in lv.get('tables',[]):tops.append((t['at'],table(t)))
 for ch in s.get('chandeliers',[]):chandelier(ch,q)
 for e in s.get('extras',[]):extra(e,q)
 bath(s['bath'],o,C,q)
 lc=lv.get('table',{}).get('at',(2.4,-.5));L=s.get('light',{});warm=tuple(L.get('warm',(1.,.78,.55)))
 COVE.extend(furnish(s,q,bx,by,lc,pool,Ms))
 if s['bath'].get('glow'):COVE.append(((o['bathx']+.6,8.55,.9),tuple(s['bath']['glow']),700,260))
 # Main lights are downward spots (recessed downlights): an omni light under the ceiling paints the tray field white and drowns the cove colour.
 SPOT=(35.,75.)
 lights=[((lc[0],lc[1],h-.45),warm,L.get('living',1600),900,SPOT),((bx,by-.4,h-.45),warm,L.get('bed',1500),800,SPOT),((-4.5 if not pool else 11.,-.8,h-.45),warm,L.get('lounge',1000),700,SPOT),((o['bathx'],8.5,h-.45),tuple(L.get('bath_color',(1.,.85,.65))),L.get('bath',1500),700,SPOT),((o['doorx'],-7.2,h-.45),warm,900,600,SPOT)]+COVE
 for s2 in [-1,1]:lights.append(((bx+s2*1.75,by+.95,1.3),tuple(L.get('lamp',(1.,.72,.45))),400,280))
 for a in L.get('accents',[]):lights.append((tuple(a['at']),tuple(a['color']),a.get('lm',900),a.get('r',500)))
 if pool:lights.append(((-8.2,4.2,3.5),(.88,.93,1.),3200,1200))
 # a downlight inside a crystal chandelier throws spoke shadows across the floor (402, 407 round 7): move it beside the fixture
 chx=[tuple(c['at']) for c in s.get('chandeliers',[])]
 def beside(p):
  for cx,cy in chx:
   if math.hypot(p[0]-cx,p[1]-cy)<.9:return (cx+1.1 if cx+1.1<w/2-.5 else cx-1.1,p[1],p[2])
  return p
 lights=[(beside(t[0]),)+tuple(t[1:]) if len(t)>4 else t for t in lights]
 views=[dict(id='v-living-to-bed',eye=[lc[0],-2.9,1.6],target=[bx,by,1.0],fov=84),dict(id='v-bed-front',eye=[bx,by-3.8,1.5],target=[bx,by+1.6,1.2],fov=80),
  dict(id='v-entry-overview',eye=[w/2-1.0,-2.9,2.0],target=[-w/2+1.5 if not pool else 2.0,5.0,.9],fov=88),dict(id='v-bath',eye=[o['bathx']-.1,7.3,2.2],target=[o['bathx']+.6,8.9,.5],fov=82)]
 if pool:views+=[dict(id='v-pool-hall',eye=[-2.8,-1.0,2.7],target=[-11.5,9.5,1.4],fov=92),dict(id='v-pool-wall',eye=[-13.8,.6,3.0],target=[-6.0,9.6,1.0],fov=90)]
 else:views.append(dict(id='v-left-lounge',eye=[1.0,1.3,1.6],target=[-6.0,-2.0,.8],fov=84))
 # a spec view with a default view's id replaces it (406/416 v-left-lounge sat behind a pier / drape in round 9)
 for v in s.get('views',[]):views=[x for x in views if x['id']!=v['id']]+[v]
 # a camera inside a piece of furniture shoots a white frame (313/314/301 v-left-lounge): nudge such eyes to the nearest
 # clear point (0.3 m from every mesh box, walls/ceiling/floor finishes excluded), keeping the target.
 boxes=[]
 for ob in OBJS:
  if ob.type!='MESH' or any(k in ob.name for k in ('Ceiling','ceiling','Floor','floor','Rug','rug','lining','Wall','Cove','Tray','Downlight','Partition','Front','Rear','Side wall','Opening','Pool hall','Mural','mosaic','Skylight')):continue
  cs=[ob.matrix_world@Vector(b) for b in ob.bound_box];boxes.append(([min(c[k] for c in cs) for k in range(3)],[max(c[k] for c in cs) for k in range(3)]))
 # and nothing at all (walls and partitions included) on the first 1.2 m of the line of sight: a lamp shade or a white
 # partition right in front of the lens filled most v-left-lounge frames (2026-10-28 captures)
 near=[]
 for ob in OBJS:
  # floor / ceiling finishes only: 'Floor lamp shade' etc. must stay (a substring test on 'Floor' dropped them)
  nm=ob.name.split('.')[0];low=nm.lower()
  if ob.type!='MESH' or (('floor' in low or 'ceiling' in low or 'rug' in low) and not any(k in low for k in ('lamp','console','picture'))) or any(k in nm for k in ('Cove','Tray','Downlight','Skylight','Water','water')):continue
  cs=[ob.matrix_world@Vector(b) for b in ob.bound_box];near.append((nm,[min(c[k] for c in cs) for k in range(3)],[max(c[k] for c in cs) for k in range(3)]))
 def sight(e,t):
  # sample the near field of the frustum (+-30 deg across, +-15 deg up/down, 0.2..1.5 m), not only the centre ray: a lamp
  # moved 0.4 m off the centre line still filled a third of the frame (round-3 captures)
  f=Vector((t[0]-e[0],t[1]-e[1],t[2]-e[2])).normalized();rt=f.cross(Vector((0,0,1)));rt=rt.normalized() if rt.length>1e-6 else Vector((1,0,0));up=rt.cross(f)
  for ah in (0,-15,15,-30,30):
   for av in (0,-15,15):
    dv=(f+rt*math.tan(math.radians(ah))+up*math.tan(math.radians(av))).normalized()
    for s in (.2,.4,.6,.8,1.0,1.25,1.5):
     p=(e[0]+dv.x*s,e[1]+dv.y*s,e[2]+dv.z*s)
     for nm,lo,hi in near:
      # low furniture (top under eye height - 0.5 m) only frames the bottom edge; tall things block the shot
      if hi[2]>e[2]-.5 and all(lo[k]-.05<p[k]<hi[k]+.05 for k in range(3)):return nm
  # mid field (1.5 m .. 60 % of the way to the target, at most 6 m): a piece of furniture taller than the eye in the middle
  # of the frame still hides the subject (215's 3.2 x 2.7 m heart booth, 4.1 m out, filled v-living-to-bed in the round-4
  # and round-6 captures; a 3 m cap missed it). Room walls and partitions are the backdrop here, not blockers.
  far=min(6.,.6*Vector((t[0]-e[0],t[1]-e[1],t[2]-e[2])).length)
  for ah in (0,-12,12):
   dv=(f+rt*math.tan(math.radians(ah))).normalized();s=1.5
   while s<=far:
    p=(e[0]+dv.x*s,e[1]+dv.y*s,e[2]+dv.z*s)
    for nm,lo,hi in near:
     if hi[2]>e[2]+.3 and not any(k in nm for k in ('Wall','wall','Partition','lining','Front','Rear','Opening','Pool hall','Mural','Column','column')) and all(lo[k]-.05<p[k]<hi[k]+.05 for k in range(3)):return nm
    s+=.25
  return None
 def blocked(p,m=.3,t=None):return any(all(lo[k]-m<p[k]<hi[k]+m for k in range(3)) for lo,hi in boxes) or (t is not None and sight(p,t))
 for v in views:
  if not blocked(v['eye'],t=v['target']):continue
  print('VIEW blocked',v['id'],sight(v['eye'],v['target']),flush=True)
  ex,ey,ez=v['eye'];best=None
  # out to 4 m: in 215 every point within 2 m of v-living-to-bed sat behind the heart booth or on the drape line
  for r in (.4,.8,1.2,1.6,2.0,2.5,3.0,3.5,4.0):
   for a in range(16):
    p=[ex+r*math.cos(a*math.tau/16),ey+r*math.sin(a*math.tau/16),ez]
    if abs(p[0])<w/2-.5 and -d/2+.5<p[1]<6.3 and not blocked(p,t=v['target']):best=p;break
   if best:break
  if best:print('VIEW moved',v['id'],[round(c,2) for c in v['eye']],'->',[round(c,2) for c in best],flush=True);v['eye']=best
 dA=list(tops[0][0])+[tops[0][1]] if tops else [lc[0],lc[1],.5]
 return dict(lights=lights,views=views,decorA=dA,decorB=[o['doorx']-2.0,-8.8,.90])
def pool_hall(P,q,C):
 w,d,h=q['size_m'];box('Pool hall ceiling',(-8.1,0,h+.05),(14.2,d-.4,.10),M(P.get('ceiling','ceiling_grid_dark')))
 sky=mat('skylight',(.85,.92,1.),emit=3.5);grid=mat('skylight_frame',(.02,.02,.02),rough=.5)
 box('Skylight glow',(-8.6,8.2,h-.02),(12.4,3.6,.02),sky)
 for k in range(13):box('Skylight mullion',(-14.8+k*1.03,8.2,h-.06),(.06,3.7,.06),grid)
 for k in range(4):box('Skylight transom',(-8.6,6.4+k*1.2,h-.06),(12.4,.06,.06),grid)
 dk=mat('dark_glass',(.05,.05,.06),rough=.03,alpha=.45);mull=mat('black_metal',(.02,.02,.02),rough=.35,metal=.6)
 for (y0,y1) in [(-3.2,3.3),(5.1,10.2)]:
  box('Glass partition',(-1.0,(y0+y1)/2,1.95),(.03,y1-y0,3.9),dk)
  for k in range(int((y1-y0)/1.2)+1):box('Partition mullion',(-1.0,y0+k*1.2,1.95),(.07,.07,3.9),mull)
 box('Partition lintel',(-1.0,4.2,3.25),(.16,1.8,1.3),mull)
 px,py,pw,pd=-w*.27,4.2,8.2,8.3;blue=M(P.get('pool_wall','mosaic_pool_blue'));granite=M(P.get('coping','granite_brown'))
 box('Pool base',(px,py,.20),(pw,pd,.40),blue);plane('Pool floor design',(px,py,.402),(pw-.5,pd-.5),M(P.get('pool_floor',{'tex':'pool_floor_design','fit':True,'rough':.15})),'+z')
 for xx in [-pw/2,pw/2]:box('Pool side wall',(px+xx,py,.78),(.25,pd,1.16),blue)
 for yy in [-pd/2,pd/2]:box('Pool end wall',(px,py+yy,.78),(pw,.25,1.16),blue)
 for xx in [-pw/2,pw/2]:box('Pool coping',(px+xx,py,1.38),(.45,pd+.45,.05),granite,.01)
 for yy in [-pd/2,pd/2]:box('Pool coping',(px,py+yy,1.38),(pw+.45,.45,.05),granite,.01)
 # pool.water {color, opacity}: its own glTF slot S_PoolWater, bound in Unreal to a per-room MI of M_MotelPoolWater
 pwm=P.get('water');box('Water',(px,py,1.12),(pw-.30,pd-.30,.018),mat('PoolWater',tuple(pwm.get('color',(.03,.2,.25))),rough=.05) if pwm else C['water'])
 box('Rear deck',(-9.5,9.34,.68),(10.9,1.72,1.36),granite);box('Left deck',(-13.69,4.2,.68),(2.53,8.3,1.36),granite)
 # ten 13.6 cm risers: the capsule audit flags a centre-ray drop over 120 cm, and 18 cm risers (104.7+18) tripped it on the way down
 for k in range(10):box('Pool access step',(px+pw/2+.24+k*.22,py,(10-k)*.136/2),(.22,2.0,(10-k)*.136),granite)
 stripe=M(P.get('stripe','mosaic_red_white'));navy=M(P.get('lower','mosaic_navy'))
 plane('Feature mosaic wall',(-8.5,10.17,2.26),(12.9,1.8),stripe,'-y');plane('Feature mosaic wall',(-14.98,4.6,2.26),(11.2,1.8),stripe,'+x')
 plane('Hall front mosaic',(-8.05,-10.18,1.95),(14.0,3.9),navy,'+y');plane('Hall left mosaic lower',(-14.98,4.6,.68),(11.2,1.36),navy,'+x');plane('Hall left mosaic front',(-14.98,-5.25,1.95),(9.9,3.9),navy,'+x')
 plane('Mural band',(-8.5,10.16,3.52),(12.9,.75),M(P.get('mural',{'tex':'mural_desert','fit':True,'rough':.6})),'-y')
 tube('Mural wave edge',[(-14.95+i*12.9/80,10.12,3.16+.05*math.sin(i*.6)) for i in range(81)],.03,mat('wave_white',(.95,.95,.92),rough=.4))
 for k in range(6):x=-14.2+k*2.1;box('Sconce bracket',(x,10.1,2.75),(.06,.12,.06),mull);cyl('Sconce glass',(x,10.0,2.85),.07,.26,mat('sconce_white',(1.,.95,.85),emit=4.),n=16)
 box('Shower cubicle glass',(-13.1,-.15,1.2),(3.6,.03,2.4),dk);box('Shower cubicle glass',(-11.3,-1.5,1.2),(.03,2.9,2.4),dk);box('Cubicle divider',(-13.1,-1.6,1.2),(.03,2.9,2.4),mull)
 for e in P.get('extras',[]):extra(e,q)
results=[];failed=[]
only=set(TASK.get('only') or [])
for rid,s in SPECS.items():
 if only and rid not in only:continue
 q=plan[rid];bpy.ops.wm.read_factory_settings(use_empty=True);MATS.clear();OBJS.clear()
 info=build_room(q,s);blockers=route_check(q,info)
 for o in OBJS:uvs(o)
 furniture=[o.name for o in OBJS if o.get('keepuv')]
 dest=S/'models-v2'/rid;dest.mkdir(parents=True,exist_ok=True)
 wet=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.data.materials and o.data.materials[0] and o.data.materials[0].name in ('S_Water','S_PoolWater','S_TubWater')]
 bpy.ops.object.select_all(action='DESELECT')
 for o in wet:o.select_set(True)
 bpy.context.view_layer.objects.active=wet[0];bpy.ops.object.join();ob=bpy.context.object;ob.name='NoCollisionWater';bpy.ops.export_scene.gltf(filepath=str(dest/'water.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True);bpy.data.objects.remove(ob,do_unlink=True)
 bpy.ops.object.select_all(action='SELECT');meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();obj=bpy.context.object;obj.name='Suite_'+rid.replace('-','_')
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');obj.data.calc_loop_triangles()
 out=dest/'suite.glb';bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_apply=True,export_yup=True,export_image_format='AUTO');bpy.ops.wm.save_as_mainfile(filepath=str(dest/'suite.blend'))
 meta=dict(id=rid,path=str(out),water_path=str(dest/'water.glb'),sha256=hashlib.sha256(out.read_bytes()).hexdigest(),triangles=len(obj.data.loop_triangles),materials=len(obj.data.materials),
  lights=[dict(local=list(t[0]),color=list(t[1]),lumens=t[2],radius=t[3],**({'spot':list(t[4])} if len(t)>4 else {})) for t in info['lights']],views=info['views'],decorA_local=info['decorA'],decorB_local=info['decorB'],route_blockers=blockers,furniture=furniture,pool_water=(s.get('pool') or {}).get('water'),tub_water=dict(TUB_WATER,**((s.get('bath') or {}).get('water') or {})))
 (dest/'build.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),'utf8');results.append(meta)
 if blockers:failed.append(rid)
 print('ROOM',rid,meta['triangles'],'blockers',blockers,flush=True)
prev=json.loads((S/'rooms-v2-build.json').read_text('utf8'))['rooms'] if (S/'rooms-v2-build.json').exists() else []
keep={r['id']:r for r in prev};keep.update({r['id']:r for r in results})
(S/'rooms-v2-build.json').write_text(json.dumps(dict(status='authored_requires_native_import',rooms=list(keep.values())),ensure_ascii=False,indent=2),'utf8')
print('FAILED_ROUTE',failed)
]====]
local ids={};for i=1,#arg do ids[#ids+1]=arg[i]end
local path=out..'/sample-rooms/build-v2-payload.json';f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,only=ids}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..out..'/sample-rooms/build-v2.log" 2>&1"'))
print('Rooms v2 authored; see build-v2.log')
