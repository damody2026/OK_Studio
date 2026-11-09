-- Author actual metric room meshes from the reviewed per-source room contracts.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local code=[====[
import bpy,math,json,hashlib,random,time
from pathlib import Path
from mathutils import Vector
O=Path(TASK['out']);plan=json.loads((O/'motel-plan.json').read_text('utf8'));(O/'models').mkdir(exist_ok=True);results=[]
def material(name,color,rough=.5,metal=0,emit=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*color,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if emit:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emit
 return m
def box(name,p,size,mat,bevel=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
 if bevel:
  b=o.modifiers.new('Crafted edge radius','BEVEL');b.width=min(bevel,min(size)*.4);b.segments=4;b.harden_normals=True;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=b.name)
  for face in o.data.polygons:face.use_smooth=True
  b=o.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');b.keep_sharp=True;b.weight=50;bpy.ops.object.modifier_apply(modifier=b.name)
 return o
def ellipsoid(name,p,size,mat):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,radius=1,location=p);o=bpy.context.object;o.name=name;o.scale=Vector(size)/2;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mat)
 for f in o.data.polygons:f.use_smooth=True
 return o
def cylinder(name,p,r,h,mat,r2=None,n=32):
 bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=p);o=bpy.context.object;o.name=name;o.data.materials.append(mat)
 for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
 return o
def tube(name,points,r,mat,cyclic=False):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=r;cu.bevel_resolution=2;s=cu.splines.new('POLY');s.points.add(len(points)-1)
 for p,co in zip(s.points,points):p.co=(*co,1)
 s.use_cyclic_u=cyclic;o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);cu.materials.append(mat);return o
def ring(name,p,rx,ry,r,mat,vertical=False):
 x,y,z=p;points=[(x+rx*math.cos(k*math.tau/64),y if vertical else y+ry*math.sin(k*math.tau/64),z+ry*math.sin(k*math.tau/64) if vertical else z) for k in range(64)];return tube(name,points,r,mat,True)
def frame(name,c,w,h,mat):
 x,y,z=c
 for xx in [-w/2,w/2]:box(name+' stile',(x+xx,y,z),(.055,.08,h),mat,.015)
 for zz in [-h/2,h/2]:box(name+' rail',(x,y,z+zz),(w,.08,.055),mat,.015)
def lamp(p,mat,metal):
 x,y,z=p;cylinder('Lamp base',(x,y,z+.035),.15,.07,metal);cylinder('Turned lamp stem',(x,y,z+.29),.045,.48,metal,r2=.027);cylinder('Pleated opal shade',(x,y,z+.60),.24,.30,mat,r2=.16)
 for k in range(24):
  a=k*math.tau/24;tube('Shade pleat',[(x+.24*math.cos(a),y+.24*math.sin(a),z+.45),(x+.16*math.cos(a),y+.16*math.sin(a),z+.75)],.004,metal)
def sofa(p,color,wood,classic=False):
 x,y,z=p;box('Sofa upholstered base',(x,y,z+.29),(2.7,1,.39),color,.14);box('Sofa back',(x,y+.37,z+.83),(2.75,.22,.85),color,.10)
 for xx in [-1.32,1.32]:box('Rolled sofa arm',(x+xx,y,z+.64),(.24,1.05,.43),color,.10)
 for xx in [-.87,0,.87]:box('Separate seat cushion',(x+xx,y-.10,z+.55),(.82,.78,.18),color,.07);o=box('Loose back cushion',(x+xx,y+.17,z+.94),(.67,.20,.55),color,.08);o.rotation_euler.x=-.13
 for xx in [-1.05,1.05]:
  for yy in [-.30,.30]:cylinder('Sofa foot',(x+xx,y+yy,z+.10),.06,.2,wood,r2=.04)
 if classic:
  pts=[(x-1.43+i*2.86/48,y+.50,z+1.15+.24*math.sin(math.pi*i/48)**2) for i in range(49)];tube('Carved crest rail',pts,.035,wood)
  for k in range(8):ellipsoid('Tuft button',(x-1.15+k*.33,y+.245,z+.98),(.035,.025,.035),wood)
def oval_tub(p,size,porcelain,stone,water,metal):
 x,y,z=p;rx,ry=size[0]/2,size[1]/2;n=64;verts=[];faces=[]
 # Closed outer shell, inner basin and recessed floor; never a solid filled bathtub.
 for sx,sy,zz in [(rx,ry,0),(rx,ry,.67),(rx-.12,ry-.12,.70),(rx-.20,ry-.20,.17)]:
  for k in range(n):a=k*math.tau/n;verts.append((x+sx*math.cos(a),y+sy*math.sin(a),z+zz))
 for band in range(3):
  for k in range(n):a=band*n+k;b=band*n+(k+1)%n;faces.append((a,b,b+n,a+n))
 faces.append(tuple(range(3*n,4*n)));mesh=bpy.data.meshes.new('Hollow massage tub');mesh.from_pydata(verts,[],faces);mesh.update();o=bpy.data.objects.new('Hollow massage tub',mesh);bpy.context.collection.objects.link(o);mesh.materials.append(porcelain)
 for f in mesh.polygons:f.use_smooth=True
 cylinder('Tub base',(x,y,z+.04),1,.08,stone).scale=(rx*.90,ry*.90,1)
 for k in range(10):
  a=k*math.tau/10;ellipsoid('Massage jet',(x+(rx-.16)*math.cos(a),y+(ry-.16)*math.sin(a),z+.40),(.065,.065,.065),metal)
 ring('Polished rolled tub rim',(x,y,z+.70),rx-.04,ry-.04,.033,porcelain)
 tube('Tub mixer',[(x+rx-.1,y,z+.70),(x+rx-.1,y,z+.94),(x+rx-.35,y,z+.94)],.025,metal)
 # Separate water asset gets NoCollision in native scene.
 v=[(x+(rx-.23)*math.cos(k*math.tau/64),y+(ry-.23)*math.sin(k*math.tau/64),z+.49) for k in range(64)];m=bpy.data.meshes.new('Water polygon');m.from_pydata(v,[],[tuple(range(64))]);m.materials.append(water);ob=bpy.data.objects.new('Bath water surface',m);bpy.context.collection.objects.link(ob);ob['NoCollision']=True

def basin(p,porcelain,metal):
 x,y,z=p;n=48;verts=[];faces=[]
 for rx,ry,zz in [(.34,.24,0),(.34,.24,.13),(.29,.19,.13),(.24,.14,.025)]:
  for k in range(n):a=k*math.tau/n;verts.append((x+rx*math.cos(a),y+ry*math.sin(a),z+zz))
 for band in range(3):
  for k in range(n):a=band*n+k;b=band*n+(k+1)%n;faces.append((a,b,b+n,a+n))
 faces.append(tuple(range(3*n,4*n)));m=bpy.data.meshes.new('Shallow washbasin');m.from_pydata(verts,[],faces);m.materials.append(porcelain);o=bpy.data.objects.new('Shallow washbasin',m);bpy.context.collection.objects.link(o)
 tube('Basin mixer',[(x,y+.28,z),(x,y+.28,z+.24),(x,y+.07,z+.24)],.018,metal);cylinder('Basin drain',(x,y,z+.028),.025,.005,metal)
def motif(style,bx,by,accent,gold,light,ivory,wood):
 # Visible geometric identity, independently authored; no photo pasted as a wall.
 if style in ['royal','baroque','palace','provencal','canopy','ivory','angel','music']:
  for xx in [-2.3,2.3]:
   cylinder('Fluted pilaster',(bx+xx,by,1.6),.17,3.15,ivory)
   for k in range(12):a=k*math.tau/12;cylinder('Pilaster flute',(bx+xx+.17*math.cos(a),by+.17*math.sin(a),1.6),.013,2.9,gold,n=8)
   for z in [.12,2.97,3.12]:box('Column capital',(bx+xx,by,z),(.49,.38,.12),gold,.025)
  for sign in [-1,1]:
   for k in range(3):
    pts=[(bx+sign*(.5+k*.5+.3*math.cos(a)),by-.06,2.1+.3*math.sin(a)) for a in [j*math.tau/32 for j in range(33)]];tube('Gilded scroll',pts,.025,gold)
 if style in ['canopy','angel']:
  for xx in [-1.25,1.25]:
   for yy in [-1.3,1.3]:cylinder('Four-poster canopy',(bx+xx,by-1.9+yy,1.5),.04,3.0,gold)
  for xx in [-1.25,1.25]:box('Draped canopy side',(bx+xx,by-1.9,2.9),(.06,2.65,.30),accent,.025)
  box('Canopy head valance',(bx,by-.6,2.9),(2.55,.10,.30),accent,.025)
 if style in ['candy','ribbon','marine','barbie']:
  for sign in [-1,1]:
   points=[]
   for k in range(80):
    a=k*math.tau*1.65/79;r=.08+.85*k/79;points.append((bx+sign*(2.05+r*math.cos(a)),by-.1,1.6+r*math.sin(a)))
   tube('Sculpted spiral outline',points,.065,light if style=='candy' else gold)
  for k in range(3):
   points=[(bx-2.1+i*4.2/64,by-.12,2.9+.15*math.sin(i/64*math.tau+k)) for i in range(65)];tube('Layered wave crown',points,.045,light)
 if style in ['lattice','oriental','zebra','stripe','mirror','crystal']:
  for k in range(15):
   xx=bx-2.6+k*.37;box('Headwall vertical rhythm',(xx,by-.04,1.8),(.09,.075,2.7),gold if k%2 else accent,.015)
  if style in ['lattice','oriental']:
   for k in range(8):
    x=bx-2.1+k*.6;tube('Geometric diamond',[(x,by-.13,1.1),(x+.30,by-.13,1.7),(x,by-.13,2.3),(x-.30,by-.13,1.7)],.025,gold,True)
 if style in ['flower','butterfly','garden','forest','bamboo','tropical']:
  for k in range(7):
   xx=bx-2.7+k*.9;pts=[(xx,by-.12,.4),(xx+.13,by-.12,1.25),(xx-.20,by-.12,2.1),(xx+.15,by-.12,2.9)];tube('Branch/bamboo relief',pts,.025,wood)
   for z in [1.,1.5,2.,2.5]:
    for sign in [-1,1]:o=ellipsoid('Leaf relief',(xx+sign*.17,by-.16,z),(.50,.055,.13),accent);o.rotation_euler.y=sign*.5
  if style in ['flower','butterfly']:
   for k in range(12):
    a=k*math.tau/12;o=ellipsoid('Petal mirror surround',(bx+math.cos(a)*.8,by-.20,2.3+math.sin(a)*.8),(.18,.08,.55),gold);o.rotation_euler.y=-a
 if style in ['galaxy','moon','disco','poker']:
  ring('Circular portal',(bx,by-.15,2.0),1.4,1.4,.055,light,True)
  for k in range(35):
   x=bx-2.8+(k*1.618%1)*5.6;z=.8+(k*.754%1)*2.3;ellipsoid('Pinpoint stars',(x,by-.20,z),(.025,.035,.025),light)
 if style=='poker':
  for k in range(4):
   x=bx-2.3+k*1.5;box('Playing card relief',(x,by-.17,2.8),(.8,.04,1.05),ivory,.05);ring('Card suit outline',(x,by-.21,2.8),.18,.25,.025,accent,True)
 if style=='brick':
  for k in range(25):
   a=k*math.pi/24;ob=box('Brick arch voussoir',(bx+2.6*math.cos(a),by-.1,1.5+1.55*math.sin(a)),(.25,.20,.19),accent,.015);ob.rotation_euler.y=-a
 if style in ['hammam','travertine','mediterranean','route66']:
  for xx in [-2.5,2.5]:
   box('Bath/room arch pier',(bx+xx,by,1.5),(.35,.40,3),wood,.04)
  ring('Warm oval medallion',(bx,by-.1,2.15),1.65,.8,.035,gold,True)

for index,q in enumerate(plan['rooms']):
 dest=O/'models'/q['id'];dest.mkdir(exist_ok=True)
 if TASK.get('only_pool') and not q['is_pool_suite']:results.append(json.loads((dest/'build.json').read_text('utf8')));continue
 bpy.ops.wm.read_factory_settings(use_empty=True);rng=random.Random(q['id']);w,d,h=q['size_m'];style=q['style'];col=q['accent'];pool=q['is_pool_suite'];classic=style in ['royal','baroque','palace','provencal','canopy','ivory','angel','music'];phase=index%3
 mats={
  'Wall':material('Motel_Wall',(.61,.53,.44),.70),'Floor':material('Motel_Floor',(.25,.17,.105),.45),'Stone':material('Motel_Stone',(.28,.26,.24),.28),
  'Wood':material('Motel_Wood',(.12,.065,.035),.42),'Accent':material('Motel_Accent',col,.64),'Ivory':material('Motel_Ivory',(.78,.74,.65),.48),
  'Linen':material('Motel_Linen',(.88,.86,.82),.84),'Gold':material('Motel_Gold',(.53,.32,.10),.24,.85),'Steel':material('Motel_Steel',(.28,.30,.32),.20,.9),
  'Porcelain':material('Motel_Porcelain',(.86,.88,.88),.16),'Dark':material('Motel_Dark',(.012,.014,.018),.22),'Light':material('Motel_Light',(.95,.70,.35),.35,emit=2.0),
  'Neon':material('Motel_Neon',(.22,.20,.80) if style not in ['candy','marine','moon'] else (.025,.38,.72),.3,emit=2.),'Water':material('Motel_Water',(.025,.19,.23),.10,.15)}
 mats['PoolTile']=material('Motel_PoolTile',(.035,.22,.38),.22)
 W,F,S,wood,A,I,L,G,M,P,D,light,neon,water=[mats[k] for k in ['Wall','Floor','Stone','Wood','Accent','Ivory','Linen','Gold','Steel','Porcelain','Dark','Light','Neon','Water']]
 # Structural floor and walls have exact openings and meet at their edges.
 box('Supported structural floor',(0,0,-.12),(w,d,.24),F);box('Closed ceiling',(0,0,h+.10),(w,d,.20),W)
 for x in [-w/2+.10,w/2-.10]:box('Side wall',(x,0,h/2),(.20,d,h),W)
 box('Privacy rear wall',(0,d/2-.10,h/2),(w-.4,.20,h),W)
 # Front facade: independent 3.8m vehicle opening and1.3m pedestrian entrance.
 gx=-w*.25;doorx=w*.29;openings=[(gx-1.9,gx+1.9,2.65)] if q['has_in_room_garage'] else []
 openings.append((doorx-.70,doorx+.70,2.45));openings.sort();last=-w/2+.20
 for lo,hi,hh in openings:
  if lo>last:box('Front wall pier',((lo+last)/2,-d/2+.10,h/2),(lo-last,.20,h),S)
  box('Front opening lintel',((lo+hi)/2,-d/2+.10,(h+hh)/2),(hi-lo,.20,h-hh),W);last=hi
 if last<w/2-.20:box('Front end pier',((last+w/2-.20)/2,-d/2+.10,h/2),(w/2-.20-last,.20,h),S)
 for lo,hi,hh in openings:frame('Opening reveal',((lo+hi)/2,-d/2+.02,hh/2),hi-lo,hh,G)
 # Enclosed garage bay, separated from bedroom by a real wall and private door.
 if q['has_in_room_garage']:
  box('Rolled up garage door housing',(gx,-d/2+.30,2.95),(4.10,.48,.52),M,.04)
  box('Garage rear wall',(gx,-3.35,1.45),(6.15,.18,2.90),W)
  box('Garage entry front jamb',(gx+3.15,-8.60,1.45),(.18,3.60,2.90),W);box('Garage entry rear jamb',(gx+3.15,-4.38,1.45),(.18,2.24,2.90),W);box('Garage pedestrian door lintel',(gx+3.15,-6.15,2.675),(.18,1.30,.45),wood)
  for xx in [gx-2.55,gx+2.55]:box('Bay painted sideline',(xx,-7.0,.012),(.07,5.4,.024),I)
  box('Garage stone finish',(gx,-6.85,.015),(6.15,7.10,.030),S)
  box('Wheel stop',(gx,-3.80,.09),(2.5,.20,.18),D,.035)
 else:
  sofa((gx,-7.0,0),A,wood,classic);cylinder('Lounge table',(gx,-8.5,.43),.65,.12,S);cylinder('Table pedestal',(gx,-8.5,.22),.15,.42,G)
 # Bedroom and lounge are separate usable zones; keep1.4m clear side circulation.
 bx=w*.14 if pool else -w*.22;by=4.7;roundbed=style in ['candy','poker','barbie','disco']
 box('Headwall upholstered field',(bx,by+1.55,1.65),(5.8,.16,3.2),A,.04)
 if roundbed:
  cylinder('Circular bed plinth',(bx,by,.21),1.45,.42,wood,n=64);cylinder('Round mattress',(bx,by,.51),1.39,.25,L,n=64);ring('Bed underlight',(bx,by,.15),1.43,1.43,.018,neon)
 else:
  box('Bed upholstered base',(bx,by,.22),(2.55,2.70,.44),A,.14);box('Deep mattress',(bx,by,.51),(2.45,2.60,.26),L,.10);box('Duvet',(bx,by-.18,.68),(2.49,2.20,.15),L,.065)
  verts=[];faces=[];cols=80;rows=8
  for row in range(rows+1):
   t=row/rows
   for col in range(cols+1):
    u=col/cols;verts.append((bx-1.245+u*2.49,by-1.28-.022*math.sin(u*math.tau*7)*t,.755-t*.50))
  for row in range(rows):
   for col in range(cols):
    k=row*(cols+1)+col;faces.append((k,k+cols+1,k+cols+2,k+1))
  mesh=bpy.data.meshes.new('Continuous folded duvet cloth');mesh.from_pydata(verts,[],faces);mesh.materials.append(L);cloth=bpy.data.objects.new('Continuous duvet foot drape',mesh);bpy.context.collection.objects.link(cloth)
  for face in mesh.polygons:face.use_smooth=True
  bpy.context.view_layer.objects.active=cloth;sol=cloth.modifiers.new('Woven cloth thickness','SOLIDIFY');sol.thickness=.012;bpy.ops.object.modifier_apply(modifier=sol.name)
 box('Headboard',(bx,by+1.28,1.15),(2.85,.23,1.45),A,.14)
 for x in [bx-.62,bx+.62]:
  o=box('Back pillow',(x,by+.85,.96),(1.08,.46,.55),L,.11);o.rotation_euler.x=.17;box('Front pillow',(x,by+.55,.87),(1.0,.40,.40),L,.09)
 for sign in [-1,1]:
  xx=bx+sign*1.85;box('Bedside cabinet',(xx,by+.6,.34),(.75,.65,.68),wood,.025);box('Drawer pull',(xx,by+.25,.42),(.22,.025,.025),G,.008);lamp((xx,by+.6,.68),light,G)
 motif(style,bx,by+1.40,A,G,neon,I,wood)
 if style in ['galaxy','moon']:
  for k in range(90):
   x=bx-2.6+(k*.61803398875%1)*5.2;y=by-2+(k*.41421356237%1)*4;ellipsoid('Fiber optic ceiling star',(x,y,h-.045),(.018,.018,.018),light)
 if style=='disco':
  cylinder('Disco sphere suspension',(bx,by,h-.3),.012,.6,M);ball=ellipsoid('Faceted mirror disco sphere',(bx,by,h-.80),(.64,.64,.64),M)
  for f in ball.data.polygons:f.use_smooth=False
 box('Bedroom woven rug',(bx,by-2.5,.014),(3.6,1.65,.028),A,.012)
 lx=w*.27;ly=-.20;sofa((lx,ly,0),A,G if classic else wood,classic);cylinder('Rounded coffee table',(lx,ly-1.5,.47),.65,.12,S);cylinder('Coffee table pedestal',(lx,ly-1.5,.23),.18,.46,G)
 box('Media cabinet',(lx,-3.05,.35),(3.2,.60,.70),wood,.03);box('Large television',(lx,-3.05,1.4),(2.05,.09,1.16),D,.025);box('Television screen',(lx,-3.11,1.4),(1.94,.015,1.05),M,.01)
 # Dressing storage and a minibar close to the entrance, not blocking the door.
 for k in range(3):box('Wardrobe door',(w/2-.43,-7.3+k*.88,1.2),(.62,.85,2.4),wood,.025);box('Wardrobe handle',(w/2-.76,-7.3+k*.88,1.25),(.035,.025,.32),G,.009)
 box('Minibar',(doorx-2.0,-8.8,.45),(1.3,.65,.90),wood,.04);cylinder('Ice bucket',(doorx-2.0,-8.8,1.03),.12,.22,M)
 for k in range(2):cylinder('Water glass',(doorx-2.35+k*.23,-8.8,.99),.055,.16,P)
 # Closed wet area, clear central opening, no wall across the bed.
 bathx=w*.28;bathy=8.2;box('Bathroom side wall',(w*.055,8.5,1.6),(.15,3.8,3.2),S)
 box('Bathroom left jamb',(bathx-2.2,6.80,1.6),(2.0,.16,3.2),S);box('Bathroom right jamb',(bathx+2.5,6.80,1.6),(1.8,.16,3.2),S);box('Bathroom lintel',(bathx+.15,6.80,2.95),(2.7,.16,.5),S)
 # Bath floor is a separate finish inset above its structural support.
 oval_tub((bathx+.65,8.30,.05),(2.65,1.75),P,S,water,M)
 vx=bathx-2.40;vy=9.78;box('Floating vanity cabinet',(vx,vy,.56),(1.8,.65,.58),wood,.04);box('Vanity counter',(vx,vy,.88),(1.9,.72,.10),S,.025)
 basin((vx,vy,.94),P,M)
 # Native mirror glass will sit inside this actual framed recess.
 box('Vanity mirror solid backing',(vx,10.17,1.65),(1.75,.06,1.17),wood)
 frame('Vanity mirror frame',(vx,10.12,1.65),1.7,1.12,G)
 for xx in [vx-.96,vx+.96]:box('Vanity vertical light',(xx,10.11,1.65),(.035,.035,1.0),light,.01)
 # Real opposing bathroom details make reflected depth legible as well as useful.
 tube('Bath towel rail',[(vx-.65,7.07,1.60),(vx+.65,7.07,1.60)],.022,G)
 for xx in [vx-.60,vx+.60]:tube('Towel rail wall bracket',[(xx,6.88,1.60),(xx,7.07,1.60)],.018,G)
 for xx in [vx-.31,vx+.31]:box('Folded hand towel',(xx,7.02,1.28),(.48,.045,.60),L,.015)
 box('Bathroom framed artwork',(vx,6.92,2.30),(1.0,.06,.62),I,.01);frame('Bathroom art frame',(vx,6.95,2.30),1.04,.66,G)
 for sign in [-1,1]:ring('Abstract bath art',(vx+sign*.18,6.98,2.30),.16,.21,.018,A,True)
 # Shower/WC cubicles have real door apertures and sanitary fixtures.
 sx=w/2-3.65 if pool else -w/2+1.30;sy=8.85
 box('Shower rear panel',(sx,10.0,1.3),(1.55,.10,2.6),S);box('Shower side',(sx-.78,9.1,1.3),(.10,1.9,2.6),S);cylinder('Rain shower stem',(sx,9.85,1.35),.025,2.2,M);cylinder('Rain shower head',(sx,9.48,2.45),.20,.04,M)
 box('Linear shower drain',(sx,8.4,.018),(.75,.06,.036),M)
 tx=sx+2.15;ty=9.4;box('WC cistern',(tx,9.85,.65),(.45,.24,.55),P,.06);ellipsoid('WC bowl',(tx,ty,.39),(.50,.68,.48),P);ring('WC seat',(tx,ty-.05,.61),.24,.31,.025,P);box('WC pedestal',(tx,ty,.18),(.30,.35,.36),P,.06)
 # Separate WC: side walls, lintel and two jambs leave a 1.0m opening.
 for xx in [tx-.80,tx+.80]:box('WC privacy partition',(xx,9.10,1.40),(.10,2.20,2.80),W)
 for xx in [tx-.65,tx+.65]:box('WC door jamb',(xx,8.0,1.40),(.30,.10,2.80),wood)
 box('WC door lintel',(tx,8.0,2.55),(1.50,.10,.50),wood)
 door=box('WC open privacy door',(tx+.81,7.52,1.12),(.05,.95,2.24),wood,.01)
 box('WC handle',(tx+.77,7.16,1.1),(.05,.12,.04),M)
 # Rear wet-room strip connects shower and WC around either side of headwall.
 box('Rear bathroom stone',(0,8.45,.015),(w-.42,3.65,.03),S)
 if pool:
  px=-w*.27;py=4.2;pw=8.2;pd=8.3
  # Raised private spa pool avoids cutting the original world terrain.
  tile=mats['PoolTile'];box('Pool mosaic base',(px,py,.20),(pw,pd,.40),tile)
  for xx in [-pw/2,pw/2]:box('Pool mosaic side',(px+xx,py,.78),(.25,pd,1.16),tile,.04)
  for yy in [-pd/2,pd/2]:box('Pool mosaic end',(px,py+yy,.78),(pw,.25,1.16),tile,.04)
  # Contrasting architectural bands distinguish the official pool-suite references.
  for k in range(7):box('Pool feature wall band',(px,9.95,.45+k*.45),(pw,.12,.25),A if k%2==0 else I,.02)
  box('Pool water',(px,py,1.12),(pw-.30,pd-.30,.018),water)
  for k in range(7):box('Pool access step',(px+pw/2+.28+k*.30,py,(7-k)*.18/2),(.30,2.0,(7-k)*.18),S)
  for k in range(6):cylinder('Pool wall lamp',(px-pw/2+.20,py-pd/2+1+k*1.15,1.02),.045,.03,neon,n=16)
 # Ceiling coves and proper ventilation grilles.
 for xx in [-w/2+.45,w/2-.45]:box('Perimeter cove',(xx,1.8,h-.17),(.20,d-5,.18),I);box('Cove luminous edge',(xx,1.8,h-.24),(.035,d-5,.025),neon)
 ring('Suspended oval cove',(bx,by,h-.24),2.5,1.9,.035,neon)
 for k in range(12):box('Supply air louver',(w/2-.20,4+k*.07,h-.45),(.04,.025,.23),D)
 for k in range(8):
  a=k*math.tau/8;tube('Chandelier arm',[(bx,by,h-.35),(bx+.65*math.cos(a),by+.65*math.sin(a),h-.60)],.018,G);ellipsoid('Opal chandelier globe',(bx+.65*math.cos(a),by+.65*math.sin(a),h-.60),(.16,.16,.20),light)
 # Join the authored objects into one predictable mesh with semantic material slots.
 for o in list(bpy.context.scene.objects):
  bpy.context.view_layer.objects.active=o;o.select_set(True)
  if o.type=='CURVE':bpy.ops.object.convert(target='MESH')
  o.select_set(False)
 wet=[o for o in bpy.context.scene.objects if o.type=='MESH' and any(m and m.name=='Motel_Water' for m in o.data.materials)]
 bpy.ops.object.select_all(action='DESELECT')
 for o in wet:o.select_set(True)
 if wet:
  bpy.context.view_layer.objects.active=wet[0];bpy.ops.object.join();ob=bpy.context.object;bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');ob.name='NoCollisionWater';bpy.ops.export_scene.gltf(filepath=str(dest/'water.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True);bpy.data.objects.remove(ob,do_unlink=True)
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.ops.object.join();obj=bpy.context.object;obj.name='Suite_'+q['id'].replace('-','_');bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=1.1519,island_margin=.005);bpy.ops.object.mode_set(mode='OBJECT');obj.data.calc_loop_triangles()
 output=dest/'suite.glb';bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',export_apply=True,export_yup=True)
 bounds=[list(v) for v in obj.bound_box];tri=len(obj.data.loop_triangles);meta=dict(id=q['id'],path=str(output),water_path=str(dest/'water.glb'),sha256=hashlib.sha256(output.read_bytes()).hexdigest(),triangles=tri,materials=[m.name for m in obj.data.materials],size_m=q['size_m'],reference_url=q['reference_url'],room_number=q['room_number'],bathroom_mirror_local=dict(face=[vx,10.075,1.65],normal=[0,-1,0],width_m=1.68,height_m=1.10),lights_local=[[bx,by,3.45],[lx,ly,3.35],[bathx,8.2,3.20],[doorx,-7.2,2.9]],eye_local=[bx+2.8,by-3.5,1.65],target_local=[bx,by,1.15],bath_eye_local=[vx,7.8,1.65],status='mesh_authored_requires_native_import_and_visual_review')
 (dest/'build.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),'utf8');results.append(meta)
 print('AUTHORED',index+1,q['id'],tri,flush=True)
(O/'suite-build.json').write_text(json.dumps(dict(status='authored_requires_native_import',rooms=results,total_rooms=len(results),total_triangles=sum(q['triangles'] for q in results),scope='Actual metric geometry with open entrances, furniture, bathroom fixtures and source-specific sculpted motifs. Native PBR binding, collision and reflected pixels still require validation.'),ensure_ascii=False,indent=2),'utf8')
]====]
assert(not arg[1] or arg[1]=='pools');local path=out..'/suite-build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,only_pool=arg[1]=='pools'}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..out..'/suite-build.log" 2>&1"'))
print('Source-specific suite geometry authored; native integration and actual-game acceptance remain required.')
