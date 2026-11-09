-- Blender payload for Tools/build_street_city_shop_refits.lua: shared storefront kit + one layout function per shop type.
-- Building frame of the source floor GLB: front facade at y=-H, side walls at x=+-W, door centre dx, core front at core_y.
return [====[
import bpy,json,math,hashlib,random
from mathutils import Vector,Matrix
from pathlib import Path
O=Path(TASK['out']);T=O/'textures';SRC=Path('C:/portable/OpenKoikatsu/output/street-social-city-production')
SPECS={s['id']:s for s in json.loads((O/'shop-specs.json').read_text('utf8'))['shops']};PAL=TASK['palettes']
MATS={};NEW=[];OCC=[]
def mat(key,color=(.8,.8,.8),rough=.5,metal=0.,emit=0.,tex=None,alpha=1.,emit_tex=False,tile=1.):
 if key in MATS:return MATS[key]
 m=bpy.data.materials.new(key);m.use_nodes=True;nt=m.node_tree;p=nt.nodes['Principled BSDF']
 p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if tex:
  im=bpy.data.images.load(str(T/(tex+'.png')),check_existing=True);n=nt.nodes.new('ShaderNodeTexImage');n.image=im;nt.links.new(n.outputs['Color'],p.inputs['Base Color'])
  if emit_tex:nt.links.new(n.outputs['Color'],p.inputs['Emission Color'])
 if emit:
  if not (tex and emit_tex):p.inputs['Emission Color'].default_value=(*color,1)
  p.inputs['Emission Strength'].default_value=emit
 if alpha<1:p.inputs['Alpha'].default_value=alpha
 MATS[key]=m;return m
def C3(c):return tuple(c)
def reg(o,m):
 if m:o.data.materials.append(m)
 NEW.append(o);return o
def box(name,c,s,m,rz=0.):
 bpy.ops.mesh.primitive_cube_add(size=1,location=c);o=bpy.context.object;o.name=name;o.scale=s;o.rotation_euler.z=rz;bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);return reg(o,m)
def bb(name,x0,x1,y0,y1,z0,z1,m):return box(name,((x0+x1)/2,(y0+y1)/2,(z0+z1)/2),(max(abs(x1-x0),.002),max(abs(y1-y0),.002),max(abs(z1-z0),.002)),m)
def cyl(name,c,r,h,m,n=16,r2=None,rx=0.,ry=0.):
 bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=c);o=bpy.context.object;o.name=name
 if rx or ry:o.rotation_euler=(rx,ry,0);bpy.ops.object.transform_apply(location=False,rotation=True,scale=False)
 return reg(o,m)
def sph(name,c,r,m,sc=(1,1,1),seg=10):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=max(4,seg//2+1),radius=r,location=c);o=bpy.context.object;o.name=name;o.scale=sc;bpy.ops.object.transform_apply(scale=True);return reg(o,m)
def quad(name,corners,m,uv=((0,0),(1,0),(1,1),(0,1))):
 me=bpy.data.meshes.new(name);me.from_pydata([Vector(c) for c in corners],[],[(0,1,2,3)]);me.uv_layers.new(name='UVMap')
 for i,l in enumerate(me.loops):me.uv_layers[0].data[i].uv=uv[i]
 o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);return reg(o,m)
def face_front(name,x0,x1,z0,z1,y,m,uv=None):return quad(name,[(x0,y,z0),(x1,y,z0),(x1,y,z1),(x0,y,z1)],m,uv or ((0,0),(1,0),(1,1),(0,1)))
def face_back(name,x0,x1,z0,z1,y,m):return quad(name,[(x1,y,z0),(x0,y,z0),(x0,y,z1),(x1,y,z1)],m)
def face_x(name,x,y0,y1,z0,z1,m,sign,u=1.):
 return quad(name,[(x,y0,z0),(x,y1,z0),(x,y1,z1),(x,y0,z1)] if sign>0 else [(x,y1,z0),(x,y0,z0),(x,y0,z1),(x,y1,z1)],m,((0,0),(u,0),(u,1),(0,1)))
def bounds(o):
 v=[o.matrix_world@Vector(c) for c in o.bound_box];return [min(p[i] for p in v) for i in range(3)],[max(p[i] for p in v) for i in range(3)]
def dup(src,name,loc,rz=0.,s=1.,maxtri=None):
 o=src.copy();o.data=src.data.copy();bpy.context.collection.objects.link(o);o.name=name
 mn,mx=bounds(src);c=Vector(((mn[0]+mx[0])/2,(mn[1]+mx[1])/2,mn[2]))
 o.data.transform(src.matrix_world);o.matrix_world=Matrix.Identity(4);o.data.transform(Matrix.Translation(-c));o.data.transform(Matrix.Rotation(rz,4,'Z'));o.data.transform(Matrix.Scale(s,4));o.location=loc;bpy.context.view_layer.update()
 if maxtri and len(o.data.polygons)>maxtri:
  d=o.modifiers.new('dec','DECIMATE');d.ratio=maxtri/len(o.data.polygons);bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=d.name)
 NEW.append(o);return o
# --- occupancy: a candidate group is only added when its footprint is free (kept fixtures, clear zones, earlier groups)
def free(x0,x1,y0,y1,z0=0.,z1=2.):
 for (a0,a1,b0,b1,c0,c1) in OCC:
  if x0<a1 and x1>a0 and y0<b1 and y1>b0 and z0<c1 and z1>c0:return False
 return True
def claim(x0,x1,y0,y1,z0=0.,z1=2.5):OCC.append((x0,x1,y0,y1,z0,z1))
def place(x0,x1,y0,y1,fn,z1=2.4):
 if not free(x0,x1,y0,y1,0.,z1):return False
 fn();claim(x0,x1,y0,y1,0.,z1);return True
def place_runs(x0,x1,y0,y1,fn,step=1.6,z1=2.4):
 # split a wall run into chunks and add every chunk whose footprint is free (kept fixtures stay)
 n=max(1,int((y1-y0)/step));got=0
 for k in range(n):
  a=y0+k*(y1-y0)/n;b=a+(y1-y0)/n
  if free(x0,x1,a,b,0.,z1):fn(a,b);claim(x0,x1,a,b,0.,z1);got+=1
 return got
STEEL=lambda:mat('ShopV1_steel',(.7,.7,.72),rough=.25,metal=1.)
BLACK=lambda:mat('ShopV1_black_metal',(.04,.04,.04),rough=.4,metal=.8)
LEAF=lambda:mat('ShopV1_leaf',(.16,.4,.16),rough=.6)
def pal_mat(key,c,**k):return mat(key+'_'+'_'.join('%.2f'%v for v in c),C3(c),**k)
# ---------------- storefront kit ----------------
def storefront(G,st,glass_top=2.6,kick_h=.45):
 W,H,dx=G['W'],G['H'],G['dx'];y0=-H;P0=W-.7;frame=pal_mat('ShopV1_frame',st['frame'],rough=.35);glass=mat('ShopV1_glass',(.55,.66,.7),rough=.02,alpha=.12)
 fascia=mat('ShopV1_band_'+st['band'],(1,1,1),rough=.4,tex=st['band'],emit=.6,emit_tex=True) if st.get('band') else pal_mat('ShopV1_fascia',st['fascia'],rough=.4)
 zt=glass_top;W2=W-.2
 for s in (-1,1):bb('Storefront pilaster',s*P0,s*W2,y0-.04,y0+.2,0,3.62,frame)
 bb('Storefront fascia',-P0,P0,y0-.04,y0+.2,zt+.08,3.62,fascia);bb('Storefront transom',-P0,P0,y0-.02,y0+.18,zt,zt+.08,frame)
 bb('Storefront fascia interior',-P0,P0,y0+.2,y0+.24,zt+.08,3.5,mat('ShopV1_interior_white',(.92,.91,.88),rough=.7))
 for a,b in [(-P0,dx-1.24),(dx+1.24,P0)]:
  if b-a<.2:continue
  bb('Storefront kick',a,b,y0-.02,y0+.18,0,kick_h,frame);bb('Storefront glass',a,b,y0+.08,y0+.1,kick_h,zt,glass)
  n=max(1,int(math.ceil((b-a)/1.6)))
  for k in range(n+1):x=a+(b-a)*k/n;bb('Storefront mullion',x-.035,x+.035,y0-.03,y0+.17,kick_h,zt,frame)
 for s in (-1,1):bb('Door jamb',dx+s*1.24-.04,dx+s*1.24+.04,y0-.03,y0+.2,0,zt,frame)
 bb('Door threshold',dx-1.2,dx+1.2,y0-.05,y0+.22,0,.012,STEEL())
 for s in (-1,1):
  x=dx+s*1.18
  bb('Door leaf stile',x-.025,x+.025,y0+.22,y0+.28,0,2.38,frame);bb('Door leaf stile',x-.025,x+.025,y0+1.32,y0+1.38,0,2.38,frame)
  bb('Door leaf rail',x-.025,x+.025,y0+.22,y0+1.38,0,.1,frame);bb('Door leaf rail',x-.025,x+.025,y0+.22,y0+1.38,2.3,2.38,frame)
  bb('Door leaf glass',x-.008,x+.008,y0+.28,y0+1.32,.1,2.3,glass);bb('Door pull',x-s*.05,x-s*.03,y0+1.15,y0+1.19,.8,1.5,STEEL())
 claim(dx-1.25,dx+1.25,y0-2.4,y0+1.45,.02,2.0)   # entry lane outside and the open leaves
def awning(G,st,x0,x1,depth=1.1,drop=.3,valance=.2,zt=2.66):
 if not st.get('awning'):return
 H=G['H'];y0=-H-.05;m=mat('ShopV1_aw_'+st['awning'],(1,1,1),rough=.85,tex=st['awning']);u=(x1-x0)/1.2
 quad('Awning',[(x0,y0,zt),(x1,y0,zt),(x1,y0-depth,zt-drop),(x0,y0-depth,zt-drop)],m,((0,0),(u,0),(u,1),(0,1)))
 quad('Awning under',[(x0,y0-depth,zt-drop-.002),(x1,y0-depth,zt-drop-.002),(x1,y0,zt-.002),(x0,y0,zt-.002)],m,((0,1),(u,1),(u,0),(0,0)))
 face_front('Awning valance',x0,x1,zt-drop-valance,zt-drop,y0-depth-.003,m,((0,0),(u,0),(u,1),(0,1)));face_back('Awning valance back',x0,x1,zt-drop-valance,zt-drop,y0-depth+.003,m)
 for x in (x0+.05,x1-.05):bb('Awning arm',x-.015,x+.015,y0-depth,y0,zt-drop-.02,zt-drop+.01,BLACK())
def blade(G,st,glow):
 W,H,dx=G['W'],G['H'],G['dx'];x=(W-.95) if dx<0 else -(W-.95);y0=-H;frame=pal_mat('ShopV1_blade_frame',st['frame'],rough=.35)
 z0,z1=4.15,6.95;yA,yB=y0-.22,y0-1.02
 bb('Blade sign frame',x-.07,x+.07,yB-.04,yA+.04,z0-.04,z1+.04,frame)
 m=mat('ShopSign_'+G['id']+'_V',(1,1,1),rough=.5,tex=G['id']+'-V-zh-Hant',emit=glow,emit_tex=True)
 quad('Blade face +X',[(x+.072,yA,z0),(x+.072,yB,z0),(x+.072,yB,z1),(x+.072,yA,z1)],m);quad('Blade face -X',[(x-.072,yB,z0),(x-.072,yA,z0),(x-.072,yA,z1),(x-.072,yB,z1)],m)
 for z in (z0+.3,z1-.3):bb('Blade bracket',x-.03,x+.03,y0-.24,y0+.01,z-.03,z+.03,BLACK())
 G['signs'].append(dict(slot='ShopSign_'+G['id']+'_V',glow=glow))
def ac_units(G,xs,floors=(3.8,7.3)):
 H=G['H'];body=mat('ShopV1_ac',(.86,.87,.85),rough=.5);grill=mat('ShopV1_ac_grill',(.18,.19,.2),rough=.6)
 for fz in floors:
  for x in xs:
   bb('AC unit',x-.42,x+.42,-H-.36,-H-.06,fz+.18,fz+.74,body);cyl('AC fan grill',(x+.1,-H-.365,fz+.46),.2,.01,grill,rx=math.pi/2)
   for s in (-1,1):bb('AC bracket',x+s*.35-.02,x+s*.35+.02,-H-.4,-H,fz+.14,fz+.18,BLACK())
def flower_box(G,x0,x1,z,cols):
 H=G['H'];bb('Window flower box',x0,x1,-H-.36,-H-.04,z,z+.22,mat('ShopV1_planter_wood',(.45,.3,.18),rough=.7));n=int((x1-x0)/.18)
 for k in range(n):sph('Box flower',(x0+.1+k*(x1-x0-.2)/max(1,n-1),-H-.2,z+.3),.11,cols[k%len(cols)])
def plant(name,x,y,h=1.1,pot=None):
 pot=pot or mat('ShopV1_pot',(.3,.24,.2),rough=.6);cyl(name+' pot',(x,y,.22),.24,.44,pot,r2=.2)
 for k in range(9):a=k*2.39;sph(name+' leaf',(x+.18*math.cos(a)*(k%3+1)/3,y+.18*math.sin(a)*(k%3+1)/3,.5+h*.35+.1*(k%4)),.2,LEAF(),(1.3,.5,.55))
def pendant(x,y,shade,h=3.5,drop=1.0):
 cyl('Pendant cord',(x,y,h-drop/2),.006,drop,BLACK(),n=6);cyl('Pendant shade',(x,y,h-drop-.08),.2,.18,shade,r2=.05)
def FLW():return [mat('ShopV1_flower_'+n,c,rough=.7) for n,c in [('red',(.78,.08,.12)),('pink',(.95,.55,.65)),('white',(.95,.94,.9)),('yellow',(.98,.8,.15)),('purple',(.5,.25,.7)),('orange',(.97,.45,.12))]]
# ---------------- fixtures ----------------
def wall_run(G,side,y0,y1,depth,h,face_tex,carcass,name,emit=.12):
 W=G['W'];xf=(-W+.2) if side<0 else (W-.2);xi=xf+side*-depth
 a,b=sorted((xf,xi));bb(name,a,b,y0,y1,0,h,carcass)
 face_x(name+' front',xi-side*.001*-1 if False else (xi+(.001 if side<0 else -.001)),y0+.05,y1-.05,.08,h-.05,mat('ShopV1_tex_'+face_tex,(1,1,1),rough=.6,tex=face_tex,emit=emit,emit_tex=True),1 if side<0 else -1,u=max(1.,(y1-y0)/2))
def gondola(G,cx,y0,y1,tex,h=1.55,cap=None):
 g=mat('ShopV1_gondola',(.9,.9,.9),rough=.4,metal=.3);bb('Gondola',cx-.4,cx+.4,y0,y1,0,h,g)
 for s in (-1,1):face_x('Gondola goods',cx+s*.401,y0+.05,y1-.05,.08,h-.05,mat('ShopV1_tex_'+tex,(1,1,1),rough=.6,tex=tex,emit=.12,emit_tex=True),s,u=max(1.,(y1-y0)/2))
 if cap:bb('Gondola end cap',cx-.4,cx+.4,y0-.15,y0,0,h+.05,cap)
def counter(x0,x1,y0,y1,body,top,register=True):
 bb('Counter',x0,x1,y0,y1,0,.95,body);bb('Counter top',x0-.03,x1+.03,y0-.03,y1+.03,.95,.99,top)
 if register:d=mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4);cx=(x0+x1)/2;cy=(y0+y1)/2;bb('Register',cx-.18,cx+.18,cy-.15,cy+.15,.99,1.25,d);bb('Register screen',cx-.15,cx+.15,cy-.16,cy-.14,1.12,1.32,mat('ShopV1_screen',(.2,.6,.9),emit=2.))
def display_case(x0,x1,y0,y1,fill):
 g=mat('ShopV1_case_glass',(.8,.9,.95),rough=.04,alpha=.25);base=mat('ShopV1_case_base',(.92,.9,.86),rough=.4)
 bb('Display case base',x0,x1,y0,y1,0,.7,base);bb('Display case glass front',x0,x1,y0-.01,y0,.7,1.25,g);bb('Display case top',x0,x1,y0,y1,1.25,1.27,g)
 for s in (x0,x1):bb('Display case side',s-.005,s+.005,y0,y1,.7,1.25,g)
 bb('Display case light',x0+.05,x1-.05,y1-.1,y1-.05,1.2,1.22,mat('ShopV1_case_light',(1.,.95,.85),emit=3.));fill(x0,x1,y0,y1,.72)
def buns(x0,x1,y0,y1,z):
 cols=[mat('ShopV1_bread_'+n,c,rough=.7) for n,c in [('gold',(.78,.52,.24)),('brown',(.55,.32,.15)),('pale',(.92,.8,.6)),('pink',(.95,.7,.75))]];k=0
 x=x0+.12
 while x<x1-.1:
  y=y0+.12
  while y<y1-.1:sph('Pastry',(x,y,z+.05),.07,cols[k%4],(1.2,1.,.6),8);k+=1;y+=.2
  x+=.2
def crate_tier(G,x0,x1,y0,y1,z0,levels,fruit_mats,step=.42):
 wood=mat('ShopV1_crate_wood',(.65,.48,.3),rough=.75)
 for l in range(levels):
  yy0=y0+l*step*.0;zz=z0+l*.32;dy=(y1-y0)/levels;ya=y0+l*dy;yb=ya+dy
  bb('Crate stand',x0,x1,ya,yb,0,zz+.02,wood)
  n=max(1,int((x1-x0)/.5))
  for k in range(n):
   cx=x0+.25+k*(x1-x0-.5)/max(1,n-1);bb('Crate',cx-.22,cx+.22,ya+.04,yb-.04,zz+.02,zz+.2,wood);fm=fruit_mats[(k+l)%len(fruit_mats)]
   for q in range(6):sph('Fruit',(cx-.13+.13*(q%3),(ya+yb)/2-.06+.12*(q//3),zz+.24),.07,fm,(1,1,1),8)
def bookcase(G,side,y0,y1,h=2.3):
 wall_run(G,side,y0,y1,.4,h,'book_spines',mat('ShopV1_walnut',(.22,.13,.07),rough=.45),'Bookcase',emit=.05)
def rack(cx,cy,length,axis,garment_cols):
 st=STEEL();L=length/2
 if axis=='x':
  bb('Rack rail',cx-L,cx+L,cy-.015,cy+.015,1.5,1.53,st)
  for s in (-1,1):bb('Rack post',cx+s*L-.015,cx+s*L+.015,cy-.015,cy+.015,0,1.53,st);bb('Rack foot',cx+s*L-.02,cx+s*L+.02,cy-.25,cy+.25,0,.03,st)
  n=int(length/.09)
  for k in range(n):x=cx-L+.05+k*(length-.1)/max(1,n-1);bb('Garment',x-.02,x+.02,cy-.22,cy+.22,.75,1.45,garment_cols[k%len(garment_cols)])
 else:
  bb('Rack rail',cx-.015,cx+.015,cy-L,cy+L,1.5,1.53,st)
  for s in (-1,1):bb('Rack post',cx-.015,cx+.015,cy+s*L-.015,cy+s*L+.015,0,1.53,st);bb('Rack foot',cx-.25,cx+.25,cy+s*L-.02,cy+s*L+.02,0,.03,st)
  n=int(length/.09)
  for k in range(n):y=cy-L+.05+k*(length-.1)/max(1,n-1);bb('Garment',cx-.22,cx+.22,y-.02,y+.02,.75,1.45,garment_cols[k%len(garment_cols)])
def menu_wall(G,side,y0,y1,z0,z1,tex,emit=.4):
 W=G['W'];x=(-W+.21) if side<0 else (W-.21);face_x('Menu board',x,y0,y1,z0,z1,mat('ShopV1_tex_'+tex,(1,1,1),rough=.5,tex=tex,emit=emit,emit_tex=True),1 if side<0 else -1)
def bench(x0,x1,y,col):
 for k in range(max(1,int((x1-x0)/.6))):x=x0+.3+k*.6;bb('Bench seat',x-.25,x+.25,y-.22,y+.22,.44,.5,col);bb('Bench leg',x-.03,x+.03,y-.03,y+.03,0,.44,STEEL())
def aboard(x,y,tex='chalk_menu'):
 for s in (-1,1):quad('A-board',[(x-.3,y,0),(x+.3,y,0),(x+.3,y-s*.18,1.0),(x-.3,y-s*.18,1.0)],mat('ShopV1_tex_'+tex,(1,1,1),rough=.9,tex=tex))
def table_set(x,y,top,seat,chairs=2):
 cyl('Table top',(x,y,.74),.36,.03,top);cyl('Table stem',(x,y,.37),.03,.72,BLACK(),n=8);cyl('Table foot',(x,y,.015),.22,.03,BLACK())
 for k in range(chairs):a=k*2*math.pi/chairs;cx,cy=x+.62*math.cos(a),y+.62*math.sin(a);bb('Chair seat',cx-.2,cx+.2,cy-.2,cy+.2,.44,.48,seat);[bb('Chair leg',cx+i-.012,cx+i+.012,cy+k2-.012,cy+k2+.012,0,.44,BLACK()) for i in (-.16,.16) for k2 in (-.16,.16)]
def lantern(x,y,z,col):
 cyl('Lantern',(x,y,z),.18,.4,mat('ShopV1_lantern_'+'_'.join('%.1f'%v for v in col),col,rough=.6,emit=2.5),n=12);cyl('Lantern cap',(x,y,z+.22),.12,.05,BLACK(),n=12);cyl('Lantern cap',(x,y,z-.22),.12,.05,BLACK(),n=12)
# ---------------- shop types ----------------
def zones(G):
 W,H,dx,cy=G['W'],G['H'],G['dx'],G['core_y'];return dict(L=-W+.2,R=W-.2,F=-H+.3,B=cy-1.75,dl0=dx-1.3,dl1=dx+1.3)
def lights(G,col,n_lm=2200):
 W,H,cy=G['W'],G['H'],G['core_y'];ys=[-H+(cy+H)*f for f in (.3,.7)];L=[]
 for y in ys:
  for x in ((-W*.45,W*.35) if W>5.5 else (0.,)):L.append(((x,y,3.15),col,n_lm,700))
 L.append(((G['dx']+2.0,-H-.4,3.3),col,800,420));return L
def T_coffee(G,st):
 Z=zones(G);shade=mat('ShopV1_pendant_glow',(1.,.78,.5),emit=4.)
 menu_wall(G,-1,Z['F']+1.4,Z['F']+3.2,1.75,2.7,'chalk_menu',.15)
 for x in (Z['dl1']+1.2,Z['R']-1.5):
  for y in (Z['F']+2.2,Z['F']+4.6):
   if free(x-.2,x+.2,y-.2,y+.2,2.2,3.5):pendant(x,y,shade)
 place(Z['R']-.4,Z['R'],Z['F']+.8,Z['B']-.3,lambda:bookcase(G,1,Z['F']+.8,Z['B']-.3))
 plant('Window plant',Z['R']-.35,Z['F']+.45,1.2)
 seat=mat('ShopV1_rattan',(.62,.45,.26),rough=.8);top=mat('ShopV1_marble_white',(.9,.89,.86),rough=.2)
 for x in (Z['dl1']+1.1,Z['dl1']+3.0):
  if x<G['W']-.8:table_set(x,-G['H']-1.6,top,seat)
 aboard(Z['dl1']+.45,-G['H']-.8)
 return 'brick_warm'
def T_tea(G,st):
 Z=zones(G)
 menu_wall(G,-1,Z['F']+1.0,Z['B']-.2,1.9,2.75,'menu_lightbox',1.2);menu_wall(G,1,Z['F']+1.0,Z['B']-.2,1.9,2.75,'menu_lightbox',1.2)
 place(Z['dl1']+.2,Z['R']-.2,Z['F'],Z['F']+.5,lambda:bench(Z['dl1']+.3,Z['R']-.3,Z['F']+.25,pal_mat('ShopV1_seat',st['frame'],rough=.5)))
 plant('Corner plant',Z['R']-.35,Z['B']-.4,1.0)
 aboard(Z['dl1']+.45,-G['H']-.8,'menu_lightbox')
 return 'tile_mint'
def T_bakery(G,st):
 Z=zones(G);wood=mat('ShopV1_oak_shelf',(.6,.45,.28),rough=.55)
 place(Z['dl1']+.3,Z['R']-.3,Z['F']+1.6,Z['F']+2.4,lambda:display_case(Z['dl1']+.3,Z['R']-.3,Z['F']+1.6,Z['F']+2.4,buns))
 def shelves():
  wall_run(G,1,Z['F']+2.9,Z['B']-.2,.5,2.0,'goods_tea',wood,'Bread shelf',.08)
  for k in range(4):
   y=Z['F']+3.2+k*.7
   if y<Z['B']-.4:
    for z in (.62,1.12,1.62):buns(Z['R']-.48,Z['R']-.08,y-.2,y+.2,z)
 place(Z['R']-.55,Z['R'],Z['F']+2.9,Z['B']-.2,shelves)
 place(Z['L'],Z['L']+.9,Z['F']+1.6,Z['F']+3.4,lambda:counter(Z['L'],Z['L']+.7,Z['F']+1.6,Z['F']+3.4,pal_mat('ShopV1_counter',st['frame'],rough=.4),mat('ShopV1_marble_white',(.9,.89,.86),rough=.2)))
 menu_wall(G,-1,Z['F']+1.6,Z['F']+3.4,1.8,2.6,'chalk_menu',.15)
 table_set(Z['dl1']+1.0,-G['H']-1.5,mat('ShopV1_marble_white',(.9,.89,.86),rough=.2),pal_mat('ShopV1_seat',st['frame'],rough=.5))
 aboard(Z['dl1']+.45,-G['H']-.8)
 return 'tile_white_subway'
def T_restaurant(G,st):
 Z=zones(G);shade=mat('ShopV1_pendant_paper',(1.,.86,.62),emit=3.)
 for x in (Z['dl1']+1.0,Z['dl1']+3.0,Z['R']-1.0):
  for y in (Z['F']+2.0,Z['F']+4.5,Z['F']+7.0):
   if y<Z['B'] and x<Z['R'] and free(x-.2,x+.2,y-.2,y+.2,2.4,3.5):pendant(x,y,shade,drop=.9)
 menu_wall(G,-1,Z['F']+1.0,Z['F']+4.0,1.9,2.5,'goods_tea',.3)
 noren=pal_mat('ShopV1_noren',st['aw'][0] if st.get('aw') else st['frame'],rough=.9)
 for k in range(4):x=G['dx']-1.15+k*.58;bb('Noren panel',x,x+.55,-G['H']-.06,-G['H']-.05,2.05,2.62,noren)
 for x in (G['dx']-1.45,G['dx']+1.45):lantern(x,-G['H']-.35,2.2,(.85,.15,.1))
 plant('Entrance plant',G['dx']+1.75,-G['H']-.5,.9)
 return 'wood_slat_light'
def T_fruit(G,st):
 Z=zones(G);fm=[mat('ShopV1_fruit_'+n,c,rough=.5) for n,c in [('apple',(.75,.08,.08)),('orange',(.96,.5,.08)),('lemon',(.96,.86,.2)),('green',(.45,.7,.2)),('grape',(.35,.12,.4)),('peach',(.98,.7,.55))]]
 place(Z['L'],Z['L']+1.3,Z['F']+.6,Z['B']-.2,lambda:crate_tier(G,Z['L'],Z['L']+1.2,Z['F']+.6,Z['B']-.2,0.,3,fm))
 place(Z['R']-1.3,Z['R'],Z['F']+1.4,Z['B']-.2,lambda:crate_tier(G,Z['R']-1.2,Z['R'],Z['F']+1.4,Z['B']-.2,0.,3,fm[::-1]))
 mid=(Z['dl1']+Z['R']-1.3)/2
 place(mid-.6,mid+.6,Z['F']+2.0,Z['F']+4.0,lambda:crate_tier(G,mid-.6,mid+.6,Z['F']+2.0,Z['F']+4.0,.3,2,fm[2:]+fm[:2]))
 place(Z['dl1']+.2,Z['dl1']+1.6,Z['B']-.9,Z['B']-.2,lambda:counter(Z['dl1']+.2,Z['dl1']+1.6,Z['B']-.8,Z['B']-.2,pal_mat('ShopV1_counter',st['frame'],rough=.4),mat('ShopV1_counter_top',(.9,.88,.84),rough=.4)))
 for x0,x1 in [(-G['W']+.5,G['dx']-1.4),(G['dx']+1.4,G['W']-.5)]:
  if x1-x0>.8:crate_tier(G,x0,x1,-G['H']-1.0,-G['H']-.1,0.,2,fm)
 return 'wood_slat_light'
def T_convenience(G,st):
 Z=zones(G);gond=mat('ShopV1_gondola',(.9,.9,.9),rough=.4,metal=.3);white=mat('ShopV1_alu_white',(.93,.94,.94),rough=.3,metal=.2);dark=mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4)
 band=pal_mat('ShopV1_accent',[c/255 for c in st['sign_fg']],rough=.4,emit=.4)
 place(Z['L'],Z['L']+.7,Z['F']+3.0,Z['B'],lambda:(wall_run(G,-1,Z['F']+3.0,Z['B'],.65,2.25,'cooler_front',gond,'Cooler',1.6),bb('Cooler header',Z['L'],Z['L']+.7,Z['F']+3.0,Z['B'],2.25,2.5,band)))
 xs=[Z['dl1']+.6+k*2.1 for k in range(4)]
 for k,cx in enumerate(xs):
  if cx+.4<Z['R']-1.4:place(cx-.45,cx+.45,Z['F']+3.0,Z['B']-.2,lambda cx=cx:gondola(G,cx,Z['F']+3.15,Z['B']-.2,'goods_shelf',cap=band))
 place(Z['R']-1.4,Z['R'],Z['F']+.5,Z['F']+5.2,lambda:(counter(Z['R']-1.35,Z['R']-.75,Z['F']+.6,Z['F']+5.0,white,dark),wall_run(G,1,Z['F']+.6,Z['F']+5.0,.35,2.3,'goods_shelf',gond,'Back shelf',.12)))
 place(Z['dl1']+.1,Z['R']-1.5,Z['F'],Z['F']+.35,lambda:(bb('Magazine rack',Z['dl1']+.1,Z['R']-1.5,Z['F'],Z['F']+.3,0,1.05,gond),face_back('Magazine fronts',Z['dl1']+.15,Z['R']-1.55,.15,1.0,Z['F']-.001,mat('ShopV1_tex_goods_shelf',(1,1,1),rough=.6,tex='goods_shelf',emit=.12,emit_tex=True))))
 for k,c in enumerate([(.1,.45,.8),(.95,.75,.1),(.15,.6,.25)]):x=G['dx']+1.6+k*.5;bb('Recycle bin',x,x+.4,-G['H']-.75,-G['H']-.3,0,.95,mat('ShopV1_bin'+str(k),c,rough=.5))
 return 'wood_slat_light'
def T_drug(G,st):
 Z=zones(G);gond=mat('ShopV1_gondola',(.95,.95,.96),rough=.35,metal=.2);acc=pal_mat('ShopV1_accent',[c/255 for c in st['sign_fg']],rough=.4,emit=.4)
 place(Z['L'],Z['L']+.5,Z['F']+.5,Z['B'],lambda:wall_run(G,-1,Z['F']+.5,Z['B'],.45,2.2,'goods_drug',gond,'Wall shelf',.18))
 place(Z['R']-.5,Z['R'],Z['F']+.5,Z['B']-1.4,lambda:wall_run(G,1,Z['F']+.5,Z['B']-1.4,.45,2.2,'goods_drug',gond,'Wall shelf',.18))
 for k in range(3):
  cx=Z['dl1']+.7+k*1.9
  if cx+.4<Z['R']-.8:place(cx-.45,cx+.45,Z['F']+1.5,Z['B']-.3,lambda cx=cx:gondola(G,cx,Z['F']+1.65,Z['B']-.3,'goods_drug',1.4,acc))
 place(Z['R']-2.2,Z['R'],Z['B']-1.2,Z['B'],lambda:(counter(Z['R']-2.1,Z['R']-.3,Z['B']-1.0,Z['B']-.45,gond,mat('ShopV1_counter_top',(.9,.88,.84),rough=.4)),face_back('Pharmacy sign',Z['R']-1.6,Z['R']-.8,2.2,2.7,Z['B']+.18,mat('ShopV1_cross',(.1,.7,.4),emit=3.))))
 return 'paint_pastel_blue'
def T_book(G,st):
 Z=zones(G)
 place(Z['L'],Z['L']+.45,Z['F']+.6,Z['B'],lambda:bookcase(G,-1,Z['F']+.6,Z['B']))
 place(Z['R']-.45,Z['R'],Z['F']+.6,Z['B'],lambda:bookcase(G,1,Z['F']+.6,Z['B']))
 wood=mat('ShopV1_oak_shelf',(.6,.45,.28),rough=.55);sp=mat('ShopV1_tex_book_spines',(1,1,1),rough=.8,tex='book_spines')
 for k in range(2):
  x0=Z['dl1']+.4+k*2.3;x1=x0+1.6
  if x1<Z['R']-.7:
   def tbl(x0=x0,x1=x1):
    bb('Book table',x0,x1,Z['F']+2.2,Z['F']+3.4,.7,.76,wood);[bb('Book table leg',x-.03,x+.03,y-.03,y+.03,0,.7,wood) for x in (x0+.06,x1-.06) for y in (Z['F']+2.26,Z['F']+3.34)]
    for q in range(6):x=x0+.2+(q%3)*(x1-x0-.4)/2;y=Z['F']+2.5+(q//3)*.6;h=.1+.05*(q%3);bb('Book stack',x-.13,x+.13,y-.18,y+.18,.76,.76+h,sp)
   place(x0,x1,Z['F']+2.2,Z['F']+3.4,tbl)
 place(Z['dl1']+.2,Z['dl1']+1.8,Z['B']-.9,Z['B']-.2,lambda:counter(Z['dl1']+.2,Z['dl1']+1.8,Z['B']-.8,Z['B']-.2,wood,mat('ShopV1_counter_top',(.9,.88,.84),rough=.4)))
 cart=lambda x:(bb('Book cart',x-.5,x+.5,-G['H']-.75,-G['H']-.25,.3,.7,wood),bb('Book cart books',x-.45,x+.45,-G['H']-.7,-G['H']-.3,.7,.92,sp),[cyl('Cart wheel',(x+s*.4,-G['H']-.5,.15),.15,.04,BLACK(),ry=math.pi/2) for s in (-1,1)])
 cart(G['dx']+2.0)
 return 'wood_slat_light'
def T_pet(G,st):
 Z=zones(G);gond=mat('ShopV1_gondola',(.92,.92,.9),rough=.4,metal=.2);acc=pal_mat('ShopV1_accent',[c/255 for c in st['sign_bg']],rough=.4)
 place(Z['L'],Z['L']+.5,Z['F']+.5,Z['B'],lambda:wall_run(G,-1,Z['F']+.5,Z['B'],.45,2.0,'goods_pet',gond,'Pet shelf',.15))
 def tanks():
  W=G['W'];y0,y1=Z['F']+1.0,Z['F']+1.0+min(3.6,Z['B']-Z['F']-1.5)
  bb('Aquarium stand',Z['R']-.55,Z['R'],y0,y1,0,.8,mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4))
  for k in range(int((y1-y0)/1.2)):ya=y0+k*1.2;bb('Aquarium',Z['R']-.52,Z['R']-.05,ya+.05,ya+1.15,.8,1.4,mat('ShopV1_aquarium',(.3,.6,.9),rough=.05,emit=1.5,alpha=.5))
 place(Z['R']-.6,Z['R'],Z['F']+1.0,Z['F']+4.6,tanks)
 cx=(Z['dl1']+Z['R']-.6)/2
 def tower():
  cyl('Cat tower post',(cx,Z['F']+3.6,.9),.08,1.8,mat('ShopV1_sisal',(.75,.62,.42),rough=.9))
  for z,r in ((.4,.45),(1.0,.35),(1.6,.3)):cyl('Cat tower deck',(cx,Z['F']+3.6,z),r,.06,acc,n=20)
 place(cx-.5,cx+.5,Z['F']+3.1,Z['F']+4.1,tower)
 place(Z['dl1']+.2,Z['dl1']+1.8,Z['B']-.9,Z['B']-.2,lambda:counter(Z['dl1']+.2,Z['dl1']+1.8,Z['B']-.8,Z['B']-.2,acc,mat('ShopV1_counter_top',(.9,.88,.84),rough=.4)))
 for k in range(3):x=G['dx']+1.6+k*.55;cyl('Pet bowl',(x,-G['H']-.5,.06),.18,.12,acc,r2=.14)
 return 'paint_pastel_pink'
def T_florist(G,st):
 Z=zones(G);flw=FLW();wood=mat('ShopV1_oak_shelf',(.6,.45,.28),rough=.55);zinc=mat('ShopV1_zinc',(.62,.64,.66),rough=.35,metal=.8)
 def tiers():
  for t,(x0,x1,h) in enumerate([(Z['L'],Z['L']+.45,.9),(Z['L']+.45,Z['L']+.9,.55),(Z['L']+.9,Z['L']+1.35,.2)]):
   bb('Tier stand',x0,x1,Z['F']+.8,Z['B']-.2,0,h,wood)
   for k in range(int((Z['B']-Z['F']-1.0)/.95)):
    y=Z['F']+1.1+k*.95;xc=(x0+x1)/2;cyl('Flower bucket',(xc,y,h+.16),.16,.32,zinc,r2=.13)
    for q in range(5):sph('Bucket bloom',(xc+.08*math.cos(q*1.26),y+.08*math.sin(q*1.26),h+.5),.075,flw[(k+q+t)%6],seg=8)
 place(Z['L'],Z['L']+1.4,Z['F']+.8,Z['B']-.2,tiers)
 cx=(Z['dl1']+Z['R'])/2
 def table():
  bb('Display table',cx-1.0,cx+1.0,Z['F']+2.2,Z['F']+3.6,.72,.78,wood);[bb('Table leg',x-.03,x+.03,y-.03,y+.03,0,.72,wood) for x in (cx-.94,cx+.94) for y in (Z['F']+2.26,Z['F']+3.54)]
  for k in range(5):x=cx-.8+k*.4;cyl('Vase',(x,Z['F']+2.9,.9),.08,.24,mat('ShopV1_vase',(.85,.9,.92),rough=.1,alpha=.5));sph('Vase bloom',(x,Z['F']+2.9,1.1),.11,flw[k%6],seg=8)
 place(cx-1.05,cx+1.05,Z['F']+2.2,Z['F']+3.6,table)
 place(Z['R']-1.5,Z['R'],Z['B']-.9,Z['B']-.2,lambda:counter(Z['R']-1.4,Z['R']-.2,Z['B']-.8,Z['B']-.2,wood,mat('ShopV1_cream',(.9,.86,.76),rough=.6)))
 for x0,x1 in [(-G['W']+.5,G['dx']-1.45),(G['dx']+1.45,min(G['W']-.5,G['dx']+3.2))]:
  if x1-x0>.6:
   bb('Street tier',x0,x1,-G['H']-.9,-G['H']-.5,0,.32,wood);bb('Street tier',x0,x1,-G['H']-.5,-G['H']-.1,0,.62,wood)
   for yy,z in ((-G['H']-.7,.32),(-G['H']-.3,.62)):
    n=max(1,int((x1-x0)/.42))
    for k in range(n):x=x0+.2+k*(x1-x0-.4)/max(1,n-1);cyl('Flower bucket',(x,yy,z+.16),.16,.32,zinc,r2=.13);[sph('Bucket bloom',(x+.08*math.cos(q*1.26),yy+.08*math.sin(q*1.26),z+.5),.075,flw[(k+q)%6],seg=8) for q in range(5)]
 return 'wood_slat_light'
def T_clothing(G,st):
 Z=zones(G);cols=[mat('ShopV1_cloth_'+str(i),c,rough=.85) for i,c in enumerate([(.1,.12,.2),(.85,.82,.76),(.55,.1,.12),(.3,.4,.3),(.9,.9,.9),(.6,.5,.35),(.2,.3,.55)])]
 place_runs(Z['L'],Z['L']+.6,Z['F']+.8,Z['B'],lambda a,b:rack(Z['L']+.3,(a+b)/2,b-a-.2,'y',cols))
 place_runs(Z['R']-.6,Z['R'],Z['F']+.8,Z['B'],lambda a,b:rack(Z['R']-.3,(a+b)/2,b-a-.2,'y',cols[::-1]))
 for k in range(3):
  cx2=Z['dl1']+.9+k*1.5
  if cx2+.7<Z['R']-.7:place(cx2-.7,cx2+.7,Z['F']+4.0,Z['F']+4.6,lambda cx2=cx2:rack(cx2,Z['F']+4.3,1.3,'x',cols))
 cx=(Z['dl1']+Z['R'])/2
 place(cx-.8,cx+.8,Z['F']+2.4,Z['F']+3.2,lambda:(bb('Folding table',cx-.75,cx+.75,Z['F']+2.45,Z['F']+3.15,.7,.76,mat('ShopV1_oak_shelf',(.6,.45,.28),rough=.55)),[bb('Folded shirt',cx-.6+q*.3-.12,cx-.6+q*.3+.12,Z['F']+2.6,Z['F']+3.0,.76,.86+.03*(q%3),cols[q%7]) for q in range(5)]))
 return 'wood_slat_light'
def T_barber(G,st):
 Z=zones(G);H=G['H'];x=G['dx']+1.55
 cyl('Barber pole',(x,-H-.25,1.9),.11,1.1,mat('ShopV1_pole',(1,1,1),rough=.3,tex='pole_stripes',emit=.8,emit_tex=True),n=20);cyl('Pole cap',(x,-H-.25,2.5),.13,.1,STEEL(),n=20);cyl('Pole cap',(x,-H-.25,1.3),.13,.1,STEEL(),n=20)
 bb('Pole bracket',x-.02,x+.02,-H-.25,-H,1.9,1.94,STEEL())
 sofa=pal_mat('ShopV1_sofa',st['frame'],rough=.6)
 place(Z['dl1']+.2,Z['dl1']+2.0,Z['F'],Z['F']+.6,lambda:(bb('Waiting sofa',Z['dl1']+.2,Z['dl1']+2.0,Z['F'],Z['F']+.55,0,.45,sofa),bb('Waiting sofa back',Z['dl1']+.2,Z['dl1']+2.0,Z['F'],Z['F']+.15,.45,.85,sofa)))
 place(Z['L'],Z['L']+.4,Z['F']+.8,Z['F']+2.6,lambda:wall_run(G,-1,Z['F']+.8,Z['F']+2.6,.35,1.8,'goods_drug',mat('ShopV1_walnut',(.22,.13,.07),rough=.45),'Product shelf',.15))
 plant('Corner plant',Z['R']-.35,Z['F']+.4,1.1)
 return 'tile_white_subway'
def T_music(G,st):
 Z=zones(G);wood=mat('ShopV1_walnut',(.22,.13,.07),rough=.45);rec=mat('ShopV1_tex_goods_records',(1,1,1),rough=.6,tex='goods_records',emit=.08,emit_tex=True)
 for k in range(2):
  cx=Z['dl1']+.8+k*2.0
  if cx+.6<Z['R']-.6:place(cx-.6,cx+.6,Z['F']+2.6,Z['F']+3.6,lambda cx=cx:(bb('Record bin',cx-.55,cx+.55,Z['F']+2.65,Z['F']+3.55,0,.85,wood),quad('Records top',[(cx-.5,Z['F']+2.7,.86),(cx+.5,Z['F']+2.7,.86),(cx+.5,Z['F']+3.5,1.05),(cx-.5,Z['F']+3.5,1.05)],rec)))
 gm=[mat('ShopV1_guitar_'+str(i),c,rough=.35) for i,c in enumerate([(.6,.25,.08),(.1,.1,.12),(.85,.75,.55),(.6,.05,.08)])]
 def guitars():
  W=G['W'];x=-W+.24;n=int((Z['B']-Z['F']-1.2)/.55)
  for k in range(n):y=Z['F']+1.0+k*.55;sph('Guitar body',(x+.06,y,1.35),.17,gm[k%4],(.35,1.,1.25),12);bb('Guitar neck',x+.04,x+.08,y-.03,y+.03,1.55,2.15,wood)
 place(Z['L'],Z['L']+.25,Z['F']+.8,Z['B'],guitars)
 place(Z['R']-1.6,Z['R'],Z['B']-.9,Z['B']-.2,lambda:counter(Z['R']-1.5,Z['R']-.2,Z['B']-.8,Z['B']-.2,wood,mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4)))
 menu_wall(G,1,Z['F']+.8,Z['F']+3.4,1.4,2.6,'goods_records',.25)
 return 'wood_dark_panel'
def T_game(G,st):
 Z=zones(G);gond=mat('ShopV1_walnut',(.22,.13,.07),rough=.45)
 place(Z['L'],Z['L']+.45,Z['F']+.6,Z['B'],lambda:wall_run(G,-1,Z['F']+.6,Z['B'],.4,2.2,'goods_game',gond,'Game shelf',.15))
 place(Z['R']-.45,Z['R'],Z['F']+.6,Z['B']-1.2,lambda:wall_run(G,1,Z['F']+.6,Z['B']-1.2,.4,2.2,'goods_game',gond,'Game shelf',.15))
 place(Z['R']-1.8,Z['R'],Z['B']-.9,Z['B']-.1,lambda:counter(Z['R']-1.7,Z['R']-.5,Z['B']-.8,Z['B']-.2,pal_mat('ShopV1_counter',st['frame'],rough=.4),mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4)))
 return 'wood_slat_light'
def T_camera(G,st):
 Z=zones(G);W=G['W'];photo=mat('ShopV1_tex_photo_prints',(1,1,1),rough=.6,tex='photo_prints',emit=.1,emit_tex=True)
 for side in (-1,1):
  x=(-W+.21) if side<0 else (W-.21);n=int((Z['B']-Z['F']-1.0)/1.6)
  for k in range(n):y0=Z['F']+.8+k*1.6;face_x('Photo prints',x,y0,y0+1.4,1.4,2.1,photo,1 if side<0 else -1)
 place(Z['R']-1.8,Z['R'],Z['B']-.9,Z['B']-.1,lambda:counter(Z['R']-1.7,Z['R']-.5,Z['B']-.8,Z['B']-.2,pal_mat('ShopV1_counter',st['frame'],rough=.4),mat('ShopV1_counter_top',(.9,.88,.84),rough=.4)))
 return 'paint_pastel_blue'
def T_bike(G,st):
 Z=zones(G);H=G['H'];tm=G.get('bike_tmpl')
 if tm:
  for k in range(3):
   x=G['dx']+1.7+k*.75
   if x<G['W']-.4:dup(tm,'Street bike',(x,-H-1.0,0),math.pi/2,1.,4000)
 tire=mat('ShopV1_tire',(.05,.05,.05),rough=.8)
 def tires():
  W=G['W'];x=-W+.25
  for k in range(int((Z['B']-Z['F']-1.0)/.7)):y=Z['F']+.9+k*.7;cyl('Wall tire',(x+.06,y,1.8),.33,.05,tire,n=24,ry=math.pi/2)
 place(Z['L'],Z['L']+.2,Z['F']+.7,Z['B'],tires)
 place(Z['R']-1.8,Z['R'],Z['B']-.9,Z['B']-.1,lambda:(bb('Work bench',Z['R']-1.7,Z['R']-.2,Z['B']-.75,Z['B']-.2,0,.9,mat('ShopV1_walnut',(.22,.13,.07),rough=.45)),bb('Tool board',Z['R']-1.7,Z['R']-.2,Z['B']-.15,Z['B']-.12,1.0,1.9,mat('ShopV1_pegboard',(.6,.5,.38),rough=.7))))
 return 'tile_white_subway'
def T_laundry(G,st):
 Z=zones(G);Wt=G.get('washer_tmpl');D=G.get('dryer_tmpl');steel=STEEL()
 for k in range(int((Z['B']-Z['F']-.8)/1.0)):
  y=Z['F']+.8+k*1.0
  if Wt:place(Z['L'],Z['L']+.9,y-.45,y+.45,lambda y=y:dup(Wt,'Washer',(Z['L']+.4,y,0),math.pi/2,1.,4000))
 for k in range(int((Z['B']-Z['F']-1.2)/1.05)):
  y=Z['F']+1.2+k*1.05
  if Wt:place(Z['R']-.9,Z['R'],y-.45,y+.45,lambda y=y:(dup(Wt,'Washer',(Z['R']-.4,y,0),-math.pi/2,1.,4000),dup(D,'Dryer',(Z['R']-.4,y,1.02),-math.pi/2,1.,4000) if D else None))
 cx=(Z['dl1']+Z['R']-.9)/2
 place(cx-.8,cx+.8,Z['F']+2.4,Z['F']+4.4,lambda:(bb('Folding table',cx-.8,cx+.8,Z['F']+2.4,Z['F']+4.4,.86,.9,steel),[bb('Folding table leg',x-.025,x+.025,y-.025,y+.025,0,.86,steel) for x in (cx-.75,cx+.75) for y in (Z['F']+2.45,Z['F']+4.35)]))
 place(Z['dl1']+.1,Z['R']-1.0,Z['F'],Z['F']+.7,lambda:bench(Z['dl1']+.1,Z['R']-1.0,Z['F']+.45,pal_mat('ShopV1_seat',st['frame'],rough=.5)))
 return 'tile_laundry'
def T_lottery(G,st):
 Z=zones(G);red=pal_mat('ShopV1_counter',st['frame'],rough=.4)
 menu_wall(G,1,Z['F']+.8,Z['B']-.3,1.5,2.6,'lottery_board',1.5)
 place(Z['L'],Z['L']+.8,Z['F']+1.0,Z['B']-.2,lambda:(counter(Z['L']+.1,Z['L']+.7,Z['F']+1.0,Z['B']-.2,red,mat('ShopV1_counter_top',(.9,.88,.84),rough=.4)),bb('Lottery terminal',Z['L']+.2,Z['L']+.5,Z['F']+2.0,Z['F']+2.4,.99,1.35,mat('ShopV1_counter_dark',(.12,.12,.13),rough=.4))))
 cx=(Z['dl1']+Z['R'])/2
 place(cx-.5,cx+.5,Z['F']+2.4,Z['F']+3.2,lambda:bb('Writing desk',cx-.5,cx+.5,Z['F']+2.45,Z['F']+3.15,0,1.05,mat('ShopV1_oak_shelf',(.6,.45,.28),rough=.55)))
 aboard(G['dx']+1.6,-G['H']-.8,'lottery_board')
 return 'paint_pastel_pink'
TYPES=dict(coffee=('keep',T_coffee,(1.,.78,.55)),tea=('keep',T_tea,(1.,.9,.78)),bakery=('rebuild',T_bakery,(1.,.85,.65)),restaurant=('keep',T_restaurant,(1.,.8,.58)),fruit=('rebuild',T_fruit,(1.,.92,.8)),
 convenience=('rebuild',T_convenience,(.95,.97,1.)),drug=('rebuild',T_drug,(.95,.97,1.)),book=('rebuild',T_book,(1.,.85,.65)),pet=('rebuild',T_pet,(1.,.94,.85)),florist=('rebuild',T_florist,(1.,.88,.72)),
 clothing=('keep',T_clothing,(1.,.94,.85)),barber=('keep',T_barber,(.98,.97,.95)),music=('keep',T_music,(1.,.85,.65)),game=('keep',T_game,(1.,.92,.8)),camera=('keep',T_camera,(.98,.97,.95)),
 bike=('keep',T_bike,(.98,.97,.95)),laundry=('rebuild',T_laundry,(.94,.97,1.)),lottery=('rebuild',T_lottery,(1.,.92,.8)))
FEATURE_TEX={}
def special_frontage(sid):
 # S18 inn / S19 onsen: big buildings whose lane-facing door is entry A on the local -X wall. Build in a frame whose
 # front is -Y (door at x=0) and rotate -90 deg about Z into the building frame; interiors and doors are kept.
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS.clear();NEW.clear();OCC.clear()
 src=SRC/(sid+'-modular-components-v1')/'assembly-building'/(sid+'-F01-complete-2k.glb');bpy.ops.import_scene.gltf(filepath=str(src));old=[o for o in bpy.context.scene.objects];meshes=[o for o in old if o.type=='MESH']
 # The two inns' front doors face each other across a ~20 cm gap (source layout), so they cannot be seen. What the lane end sees is the stretch of the entry-A (-X) face nearest the lane:
 # building y -20..-9 on S18, 9..18 on S19 (UE local y is the negated Blender y). Frame: front -Y, rotated -90 deg about Z.
 fr=[o for o in meshes if '-entry-A-frame' in o.name];north=False;dxb=0.
 Wb=max(abs(bounds(o)[0][0]) for o in meshes);H=abs(min(bounds(o)[0][0] for o in fr));s=SPECS[sid];st={'sign_bg':(40,28,18),'sign_fg':(240,214,160),'frame':(.25,.15,.08)}
 wood=mat('ShopV1_hinoki',(.55,.36,.2),rough=.6);dark=mat('ShopV1_sumi',(.12,.08,.06),rough=.5);roof=mat('ShopV1_kawara',(.18,.2,.24),rough=.5,metal=.2);plaster=mat('ShopV1_shikkui',(.93,.91,.86),rough=.8)
 y0=-H;G=dict(id=sid,signs=[])
 # koshi (vertical lattice) panels either side of the door, standing 4 cm off the wall
 for a,b in [(-4.6,-.35),(.35,4.6)]:
  bb('Koshi rail',a,b,y0-.12,y0-.04,.0,.12,dark);bb('Koshi rail',a,b,y0-.12,y0-.04,2.45,2.55,dark)
  n=int((b-a)/.09)
  for k in range(n):x=a+.045+k*(b-a-.09)/max(1,n-1);bb('Koshi slat',x-.018,x+.018,y0-.11,y0-.05,.12,2.45,wood)
  for x in (a,b):bb('Koshi post',x-.07,x+.07,y0-.16,y0-.02,0,2.7,dark)
 # eave over the entrance zone
 quad('Eave',[(-4.9,y0,3.05),(4.9,y0,3.05),(4.9,y0-1.3,2.72),(-4.9,y0-1.3,2.72)],roof,((0,0),(5,0),(5,1),(0,1)));quad('Eave under',[(-4.9,y0-1.3,2.715),(4.9,y0-1.3,2.715),(4.9,y0,3.045),(-4.9,y0,3.045)],wood)
 bb('Eave fascia',-4.9,4.9,y0-1.34,y0-1.26,2.6,2.76,dark)
 for x in (-4.6,4.6):bb('Eave post',x-.08,x+.08,y0-1.3,y0-1.14,0,2.72,dark)
 # noren over entry A
 nc=(.12,.18,.36) if sid=='S18' else (.55,.12,.1)
 nm=mat('ShopV1_noren_'+sid,nc,rough=.9)
 # no door on this stretch: lanterns only, no noren
 for x in (-2.4,0.,2.4):lantern(x,y0-.7,2.05,(1.,.6,.3))
 # name board over the eave (localized via the V sign material on a horizontal board)
 bb('Name board frame',-2.6,2.6,y0-.1,y0-.02,3.2,4.1,dark)
 m=mat('ShopSign_'+sid+'_V',(1,1,1),rough=.5,tex=sid+'-H-zh-Hant',emit=3.0,emit_tex=True)
 face_front('Name board face',-2.45,2.45,3.28,4.02,y0-.101,m);G['signs'].append(dict(slot='ShopSign_'+sid+'_V',glow=3.0))
 # stone path lanterns and planters by the door
 stone=mat('ShopV1_stone',(.55,.55,.52),rough=.85)
 for x in (-4.2,4.2):
  bb('Stone lantern base',x-.2,x+.2,y0-2.1,y0-1.7,0,.5,stone);bb('Stone lantern light',x-.17,x+.17,y0-2.07,y0-1.73,.5,.82,mat('ShopV1_stone_glow',(1.,.75,.45),emit=2.5));bb('Stone lantern cap',x-.28,x+.28,y0-2.18,y0-1.62,.82,.92,stone)
  plant('Bamboo planter',x+(1.3 if x<0 else -1.3),y0-.5,1.6)
 if sid=='S19':
  for x in (-4.0,4.0):bb('Onsen mark plaque',x-.45,x+.45,y0-.18,y0-.16,3.2,4.1,mat('ShopV1_onsen_mark',(.8,.12,.1),emit=1.5))
 for o in old:bpy.data.objects.remove(o,do_unlink=True)
 cx=14.5 if sid=='S18' else -13.5
 R=Matrix.Rotation(-math.pi/2,4,'Z')@Matrix.Translation((cx,0,0))
 for o in NEW:o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4);o.data.transform(R)
 dest=O/sid;dest.mkdir(parents=True,exist_ok=True);bpy.ops.object.select_all(action='DESELECT')
 for o in NEW:o.select_set(True)
 bpy.context.view_layer.objects.active=NEW[0];bpy.ops.object.join();ob=bpy.context.object;ob.name='ShopV1_'+sid+'_Refit'
 p=dest/(sid+'-refit.glb');bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',use_selection=True,export_apply=True,export_yup=True);ob.data.calc_loop_triangles()
 def rot(v):x,y,z=v;x+=cx;return (y,-x,z)
 L=[(rot((0,y0-1.0,2.6)),(1.,.75,.5),1400,700),(rot((0,y0+3.0,3.0)),(1.,.8,.6),1600,800)]
 r=dict(id=sid,type='special',mode='keep',special=True,source=str(src),path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),W=Wb,H=H,door_x=dxb,core_y=0,triangles=len(ob.data.loop_triangles),cut=[],no_cut=True,
  signs=G['signs'],feature=None,lights=[dict(local=list(a),color=list(b),lumens=c,radius=d) for a,b,c,d in L],blockers=[],names=s['names'],
  sign_textures={'V':{loc:str(T/f'{sid}-H-{loc}.png') for loc in ('zh-Hant','zh-Hans','en')}},textures_dir=str(T))
 (dest/'build.json').write_text(json.dumps(r,ensure_ascii=False,indent=1),'utf8');print('SHOP',sid,'special tris',r['triangles'],'blockers []',flush=True);return r
results=[]
for sid in TASK['ids']:
 if SPECS[sid]['type']=='special':results.append(special_frontage(sid));continue
 s=SPECS[sid];mode,fn,lc=TYPES[s['type']];plist=PAL[s['type']];st=plist[s['variant']%len(plist)]
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS.clear();NEW.clear();OCC.clear()
 src=SRC/(sid+'-modular-components-v1')/'assembly-building'/(sid+'-F01-complete-2k.glb');bpy.ops.import_scene.gltf(filepath=str(src));old=[o for o in bpy.context.scene.objects]
 meshes=[o for o in old if o.type=='MESH'];G=dict(id=sid,signs=[])
 ext=[o for o in meshes if '/F01-exterior-' in o.name];core=[o for o in meshes if '/F01-core-' in o.name];fr=[o for o in meshes if '-entry-front-' in o.name and '-frame' in o.name]
 G['W']=round(max(max(abs(bounds(o)[0][0]),abs(bounds(o)[1][0])) for o in ext),3);G['H']=round(max(max(abs(bounds(o)[0][1]),abs(bounds(o)[1][1])) for o in ext),3)
 G['dx']=round((min(bounds(o)[0][0] for o in fr)+max(bounds(o)[1][0] for o in fr))/2,3);assert all(bounds(o)[0][1]<-G['H']+.3 for o in fr)
 G['core_y']=round(min(bounds(o)[0][1] for o in core),3);W,H,dx=G['W'],G['H'],G['dx']
 feat=sorted({m.name for o in meshes for m in o.data.materials if m and ' wall feature ' in m.name})
 heavy=sorted([o for o in meshes if len(o.data.polygons)>2000 and 'equipment' in o.name],key=lambda o:-len(o.data.polygons))
 if s['type']=='bike' and heavy:G['bike_tmpl']=heavy[0]
 if s['type']=='laundry':
  ws=[o for o in heavy if '-upper' not in o.name];ds=[o for o in heavy if '-upper' in o.name]
  if ws:G['washer_tmpl']=ws[0]
  if ds:G['dryer_tmpl']=ds[0]
 cuts=[dict(name='front wall, windows, entry, sign and band',box=[-W+.19,W-.19,-H-.03,-H+.215,-.01,3.7]),dict(name='old entry leaves',box=[dx-1.36,dx+1.36,-H-.03,-H+1.5,-.01,2.45])]
 sales=[-W+.25,W-.25,-H+.15,G['core_y']-.05,.004,2.6]
 if mode=='rebuild':cuts.append(dict(name='sales floor fixtures',box=sales))
 else:
  # kept fixtures block the new layout
  for o in meshes:
   mn,mx=bounds(o)
   if mn[0]>=sales[0] and mx[0]<=sales[1] and mn[1]>=sales[2] and mx[1]<=sales[3] and mn[2]>=-.01 and mx[2]<=2.6 and not (mn[1]<-H+1.5 and dx-1.36<=mn[0] and mx[0]<=dx+1.36):claim(mn[0]-.15,mx[0]+.15,mn[1]-.15,mx[1]+.15,mn[2],mx[2])
 claim(dx-1.3,dx+1.3,-H,G['core_y'],.02,2.0);claim(-W,W,G['core_y']-1.6,G['core_y'],.02,2.0)
 storefront(G,st,kick_h=.25 if s['type'] in ('convenience','drug','laundry') else .45)
 aw_ranges={'coffee':(dx+1.35,W-.75),'bakery':(dx+1.35,W-.75),'fruit':(-W+.75,W-.75),'florist':(-W+.75,W-.75),'pet':(dx+1.35,W-.75),'book':(dx+1.35,W-.75),'tea':(-W+.75,W-.75),'music':(dx+1.35,W-.75),'game':(dx+1.35,W-.75),'camera':(dx+1.35,W-.75),'bike':(-W+.75,W-.75),'laundry':(dx+1.35,W-.75),'lottery':(-W+.75,W-.75),'clothing':(dx+1.35,W-.75)}
 if s['type'] in aw_ranges and st.get('awning'):a0,a1=aw_ranges[s['type']];awning(G,st,a0,a1,depth=1.0 if s['type'] not in ('laundry',) else .9,drop=.3 if s['type']!='laundry' else .12,valance=.2 if s['type']!='laundry' else .12)
 blade(G,st,4.0 if s['type'] not in ('convenience','drug','laundry','lottery') else 6.0)
 if s['type']=='florist':
  cols=FLW()
  for z in (4.62,8.12):flower_box(G,-W*.66,-W*.34,z,cols);flower_box(G,W*.34,W*.66,z,cols)
 else:ac_units(G,[W*.5] if s['variant']%2 else [-W*.5,W*.5],floors=(3.8,) if s['variant']%3==0 else (3.8,7.3))
 ftex=fn(G,st)
 for o in old:bpy.data.objects.remove(o,do_unlink=True)
 block=[]
 for o in NEW:
  mn,mx=bounds(o)
  if any(k in o.name for k in ('Door','Storefront','Awning','Sign','Blade','Noren','Lantern','Pendant','AC ','Window flower','Box flower','Barber pole','Pole')):continue
  for (n,x0,x1,y0,y1) in [('door lane',dx-1.2,dx+1.2,-H-2.4,G['core_y']),('core aisle',-W,W,G['core_y']-1.5,G['core_y'])]:
   if mn[0]<x1 and mx[0]>x0 and mn[1]<y1 and mx[1]>y0 and mn[2]<2.0 and mx[2]>.03:block.append((n,o.name))
 dest=O/sid;dest.mkdir(parents=True,exist_ok=True);bpy.ops.object.select_all(action='DESELECT')
 for o in NEW:o.select_set(True)
 bpy.context.view_layer.objects.active=NEW[0];bpy.ops.object.join();ob=bpy.context.object;ob.name='ShopV1_'+sid+'_Refit'
 p=dest/(sid+'-refit.glb');bpy.ops.export_scene.gltf(filepath=str(p),export_format='GLB',use_selection=True,export_apply=True,export_yup=True)
 ob.data.calc_loop_triangles()
 r=dict(id=sid,type=s['type'],mode=mode,variant=s['variant'],source=str(src),path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),W=W,H=H,door_x=dx,core_y=G['core_y'],triangles=len(ob.data.loop_triangles),cut=cuts,
  signs=G['signs'],feature=dict(slot=feat[0].replace(' ','_'),tex=ftex) if feat and ftex else None,lights=[dict(local=list(a),color=list(b),lumens=c,radius=d) for a,b,c,d in lights(G,lc)],blockers=block,names=s['names'],
  sign_textures={'V':{loc:str(T/f'{sid}-V-{loc}.png') for loc in ('zh-Hant','zh-Hans','en')}},textures_dir=str(T))
 (dest/'build.json').write_text(json.dumps(r,ensure_ascii=False,indent=1),'utf8');results.append(r);print('SHOP',sid,s['type'],mode,'W',W,'H',H,'tris',r['triangles'],'blockers',block,flush=True)
prev={}
if (O/'refits-build.json').exists():prev={r['id']:r for r in json.loads((O/'refits-build.json').read_text('utf8'))['shops']}
prev.update({r['id']:r for r in results})
(O/'refits-build.json').write_text(json.dumps(dict(status='authored_requires_native_install',shops=list(prev.values())),ensure_ascii=False,indent=1),'utf8')
]====]
