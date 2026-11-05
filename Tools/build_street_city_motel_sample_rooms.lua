-- Fidelity sample rooms (209 尊爵, 303 慾望城市, 203 泳池房1, 512 香奈兒): per-room layouts authored from the official
-- photos, textured finishes, Tripo furniture (remeshed) and per-room lights / camera views. Shell openings, garage,
-- bathroom partitions, vanity mirror recess and minibar stay where the native mirrors, routes and ornaments expect them.
-- Usage: lua build_street_city_motel_sample_rooms.lua [room-id]
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local code=[====[
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector
O=Path(TASK['out']);S=O/'sample-rooms';T=S/'textures';plan={r['id']:r for r in json.loads((O/'motel-plan.json').read_text('utf-8-sig'))['rooms']}
furn_rx={r['key']:r for r in json.loads((S/'furniture/receipts.json').read_text('utf8')) if r['status']=='passed'}
MATS={}
def mat(key,color=(.5,.5,.5),tex=None,tile=1.0,fit=False,rough=.5,metal=0.,emit=0.,alpha=1.):
 if key in MATS:return MATS[key]
 m=bpy.data.materials.new('S_'+key);m.use_nodes=True;nt=m.node_tree;p=nt.nodes.get('Principled BSDF')
 p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
 if tex:
  im=bpy.data.images.load(str(T/(tex+'.png')),check_existing=True);n=nt.nodes.new('ShaderNodeTexImage');n.image=im;nt.links.new(n.outputs['Color'],p.inputs['Base Color'])
 if emit:
  p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emit
  if tex:nt.links.new(n.outputs['Color'],p.inputs['Emission Color'])  # textured glow (galaxy walls, screens)
 if alpha<1:
  p.inputs['Alpha'].default_value=alpha;m.blend_method='BLEND' if hasattr(m,'blend_method') else None
 m['tile']=tile;m['fit']=fit;MATS[key]=m;return m
OBJS=[]
def reg(o,m=None,keepuv=False):
 if m is not None:o.data.materials.append(m)
 o['keepuv']=keepuv;OBJS.append(o);return o
def box(name,p,size,m,bevel=0,rz=0):
 bpy.ops.mesh.primitive_cube_add(size=1,location=p);o=bpy.context.object;o.name=name;o.dimensions=size;o.rotation_euler.z=rz;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if bevel:
  b=o.modifiers.new('bev','BEVEL');b.width=min(bevel,min(size)*.4);b.segments=3;b.harden_normals=True;bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=b.name)
  for f in o.data.polygons:f.use_smooth=True
 return reg(o,m)
def cyl(name,p,r,h,m,r2=None,n=32,sx=1,sy=1):
 bpy.ops.mesh.primitive_cone_add(vertices=n,radius1=r,radius2=r if r2 is None else r2,depth=h,location=p);o=bpy.context.object;o.name=name;o.scale=(sx,sy,1);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for f in o.data.polygons:f.use_smooth=len(f.vertices)==4
 return reg(o,m)
def ell(name,p,size,m,seg=20):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=seg,ring_count=max(6,seg//2),radius=1,location=p);o=bpy.context.object;o.name=name;o.scale=Vector(size)/2;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for f in o.data.polygons:f.use_smooth=True
 return reg(o,m)
def tube(name,pts,r,m,cyclic=False):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.bevel_depth=r;cu.bevel_resolution=2;s=cu.splines.new('POLY');s.points.add(len(pts)-1)
 for q,co in zip(s.points,pts):q.co=(*co,1)
 s.use_cyclic_u=cyclic;o=bpy.data.objects.new(name,cu);bpy.context.collection.objects.link(o);cu.materials.append(m)
 bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False);return reg(o)
def ring(name,c,rx,ry,r,m,plane='xz'):
 x,y,z=c;pts=[]
 for k in range(64):
  a=k*math.tau/64;u,v=rx*math.cos(a),ry*math.sin(a);pts.append((x+u,y,z+v) if plane=='xz' else ((x,y+u,z+v) if plane=='yz' else (x+u,y+v,z)))
 return tube(name,pts,r,m,True)
def plane(name,c,size,m,facing):
 # facing: '+z','-y','+y','+x','-x' ; size=(u,v)
 bpy.ops.mesh.primitive_plane_add(size=1,location=c);o=bpy.context.object;o.name=name;o.scale=(size[0],size[1],1);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 if facing=='-y':o.rotation_euler.x=math.pi/2
 elif facing=='+y':o.rotation_euler.x=-math.pi/2
 elif facing=='+x':o.rotation_euler.x=math.pi/2;o.rotation_euler.z=math.pi/2
 elif facing=='-x':o.rotation_euler.x=math.pi/2;o.rotation_euler.z=-math.pi/2
 bpy.ops.object.transform_apply(location=False,rotation=True,scale=False);return reg(o,m)
def frame(name,c,w,h,m,t=.06,axis='x'):
 x,y,z=c
 if axis=='x':
  for xx in [-w/2,w/2]:box(name,(x+xx,y,z),(t,t,h+t),m,.01)
  for zz in [-h/2,h/2]:box(name,(x,y,z+zz),(w,t,t),m,.01)
 else:
  for yy in [-w/2,w/2]:box(name,(x,y+yy,z),(t,t,h+t),m,.01)
  for zz in [-h/2,h/2]:box(name,(x,y,z+zz),(t,w,t),m,.01)
def furn(key,x,y,rot=0,z=0):
 rx=furn_rx[key];before=set(bpy.context.scene.objects);bpy.ops.import_scene.gltf(filepath=rx['path']);new=[o for o in bpy.context.scene.objects if o not in before]
 meshes=[o for o in new if o.type=='MESH']
 for o in new:
  if o.type!='MESH':bpy.data.objects.remove(o,do_unlink=True)
 bpy.ops.object.select_all(action='DESELECT')
 for o in meshes:o.select_set(True)
 bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();o=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 o.name='Furniture_'+key;o.rotation_euler.z=math.radians(rot);o.location=(x,y,z);bpy.ops.object.transform_apply(location=True,rotation=True,scale=False);o.select_set(False);return reg(o,None,True)
def column(x,y,h,ivory,gold):
 cyl('Column plinth',(x,y,.09),.30,.18,ivory,n=4);cyl('Column base torus',(x,y,.24),.24,.12,gold,r2=.21);cyl('Column shaft',(x,y,h/2),.19,h-.9,ivory,r2=.17,n=24)
 for k in range(16):a=k*math.tau/16;cyl('Column flute',(x+.185*math.cos(a),y+.185*math.sin(a),h/2),.014,h-1.1,gold,r2=.012,n=6)
 cyl('Corinthian bell',(x,y,h-.30),.20,.40,gold,r2=.30,n=24)
 for k in range(8):a=k*math.tau/8;o=ell('Acanthus leaf',(x+.25*math.cos(a),y+.25*math.sin(a),h-.25),(.10,.10,.30),gold,10)
 box('Column abacus',(x,y,h-.05),(.68,.68,.10),ivory,.02)
def drape(name,x0,x1,y,z0,z1,m,axis='x',folds=9,depth=.07):
 n=64;rows=10;verts=[];faces=[];L=x1-x0
 for r in range(rows+1):
  zz=z0+(z1-z0)*r/rows
  for i in range(n+1):
   u=x0+L*i/n;off=depth*math.sin(i/n*folds*math.tau)*(0.6+0.4*r/rows)
   verts.append((u,y+off,zz) if axis=='x' else (y+off,u,zz))
 for r in range(rows):
  for i in range(n):k=r*(n+1)+i;faces.append((k,k+1,k+n+2,k+n+1))
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o)
 for f in me.polygons:f.use_smooth=True
 bpy.context.view_layer.objects.active=o;s=o.modifiers.new('sol','SOLIDIFY');s.thickness=.02;bpy.ops.object.modifier_apply(modifier=s.name);return reg(o,m)
def hollow_tub(name,c,size,shell,inner,water,rect=True,rim=.12,depth=.55):
 x,y,z=c;rx,ry=size[0]/2,size[1]/2;n=4 if rect else 64;verts=[];faces=[]
 def ringpts(ax,ay,zz):
  if rect:return [(x+ax,y-ay,zz),(x+ax,y+ay,zz),(x-ax,y+ay,zz),(x-ax,y-ay,zz)]
  return [(x+ax*math.cos(k*math.tau/n),y+ay*math.sin(k*math.tau/n),zz) for k in range(n)]
 for ax,ay,zz in [(rx-rim,ry-rim,z+depth),(rx-rim-.05,ry-rim-.05,z+.10)]:verts+=ringpts(ax,ay,zz)
 for k in range(n):a=k;b=(k+1)%n;faces.append((a,b,b+n,a+n))
 faces.append(tuple(range(2*n-1,n-1,-1)));me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);reg(o,inner)
 for f in me.polygons:f.use_smooth=not rect
 # surround with a hole: four boxes for rect, ring of segments for round
 if rect:
  box(name+' surround',(x,y-ry+rim/2,z+depth/2),(size[0],rim,depth),shell);box(name+' surround',(x,y+ry-rim/2,z+depth/2),(size[0],rim,depth),shell)
  box(name+' surround',(x-rx+rim/2,y,z+depth/2),(rim,size[1]-2*rim,depth),shell);box(name+' surround',(x+rx-rim/2,y,z+depth/2),(rim,size[1]-2*rim,depth),shell)
 else:
  for k in range(32):
   a=(k+.5)*math.tau/32;box(name+' rim',(x+(rx-rim/2)*math.cos(a),y+(ry-rim/2)*math.sin(a),z+depth/2),(rim,2*math.pi*rx/32+.02,depth),shell,rz=a)
 w=[(x+(rx-rim-.06)*math.cos(k*math.tau/48),y+(ry-rim-.06)*math.sin(k*math.tau/48),z+depth-.12) for k in range(48)] if not rect else [(x+rx-rim-.06,y-ry+rim+.06,z+depth-.12),(x+rx-rim-.06,y+ry-rim-.06,z+depth-.12),(x-rx+rim+.06,y+ry-rim-.06,z+depth-.12),(x-rx+rim+.06,y-ry+rim+.06,z+depth-.12)]
 me=bpy.data.meshes.new('Water');me.from_pydata(w,[],[tuple(range(len(w)))]);o=bpy.data.objects.new('Bath water',me);bpy.context.collection.objects.link(o);reg(o,water)
 # Massage-tub fittings: chrome jets on the inner walls, underwater light, headrest, grab rails and a deck-mounted spout.
 chrome=mat('chrome',(.75,.76,.78),rough=.08,metal=1.);jz=z+depth-.30;ax,ay=rx-rim-.03,ry-rim-.03
 if rect:
  for s in [-1,1]:
   for k in range(4):xx=x-ax*.75+k*ax*.5;ell('Massage jet',(xx,y+s*ay,jz),(.075,.025,.075),chrome,10);ell('Jet nozzle',(xx,y+s*(ay-.012),jz),(.03,.02,.03),mat('jet_dark',(.05,.05,.05),rough=.3),8)
   ell('Massage jet',(x+s*ax,y,jz),(.025,.075,.075),chrome,10)
  box('Tub headrest',(x-ax+.12,y,z+depth-.05),(.16,ay*1.1,.14),mat('headrest',(.88,.88,.86),rough=.4),.06)
  for s in [-1,1]:tube('Tub grab rail',[(x-.25,y+s*(ry-rim/2),z+depth+.01),(x-.25,y+s*(ry-rim/2),z+depth+.09),(x+.25,y+s*(ry-rim/2),z+depth+.09),(x+.25,y+s*(ry-rim/2),z+depth+.01)],.014,chrome)
  tube('Tub spout',[(x+rx-rim/2,y,z+depth),(x+rx-rim/2,y,z+depth+.18),(x+rx-rim-.08,y,z+depth+.18)],.022,chrome)
  for k in range(3):cyl('Tub control knob',(x+rx-rim/2,y-.2+k*.2,z+depth+.02),.025,.04,chrome,n=12)
 else:
  for k in range(10):a=k*math.tau/10;ell('Massage jet',(x+ax*math.cos(a),y+ay*math.sin(a),jz),(.075,.075,.075),chrome,10)
  for k in range(2):a=math.pi*(.25+k*.5);tube('Tub grab rail',[(x+(rx-rim/2)*math.cos(a-.15),y+(ry-rim/2)*math.sin(a-.15),z+depth+.01),(x+(rx-rim/2)*math.cos(a-.15),y+(ry-rim/2)*math.sin(a-.15),z+depth+.09),(x+(rx-rim/2)*math.cos(a+.15),y+(ry-rim/2)*math.sin(a+.15),z+depth+.09),(x+(rx-rim/2)*math.cos(a+.15),y+(ry-rim/2)*math.sin(a+.15),z+depth+.01)],.014,chrome)
  tube('Tub spout',[(x+rx-rim/2,y,z+depth),(x+rx-rim/2,y,z+depth+.18),(x+rx-rim-.08,y,z+depth+.18)],.022,chrome)
 cyl('Underwater light',(x,y,z+.11),.09,.01,mat('tub_light',(.55,.8,1.),emit=6.),n=24);cyl('Tub drain',(x+(ax*.6 if rect else 0),y,z+.105),.04,.01,chrome,n=16)
def basin(p,porcelain,metal,rect=False):
 x,y,z=p
 if rect:box('Vessel basin',(x,y,z+.07),(.58,.40,.14),porcelain,.03);box('Basin bowl',(x,y,z+.12),(.48,.30,.06),mat('basin_shadow',(.70,.72,.72),rough=.2),.02)
 else:cyl('Basin',(x,y,z+.07),.30,.14,porcelain,r2=.33,sx=1.1,sy=.8)
 tube('Basin mixer',[(x,y+.26,z),(x,y+.26,z+.26),(x,y+.08,z+.26)],.018,metal)
def lamp_pleated(x,y,z,shade,base):
 cyl('Lamp base',(x,y,z+.06),.13,.12,base,r2=.10);cyl('Lamp stem',(x,y,z+.30),.03,.40,base);cyl('Pleated shade',(x,y,z+.62),.24,.34,shade,r2=.13,n=24)
def lamp_drum(x,y,z,shade,base,h=.9):
 cyl('Lamp foot',(x,y,z+.03),.15,.06,base);cyl('Lamp column',(x,y,z+h*.35),.04,h*.65,base);cyl('Drum shade',(x,y,z+h*.82),.20,.32,shade,n=32)
def downlight(x,y,h,m):cyl('Downlight',(x,y,h-.005),.07,.01,m,n=16)
def tray_ceiling(w,d,h,field,soffit,cove,trim,band=1.0,drop=.35,x0=None,x1=None,y0=None,y1=None):
 x0=-w/2+.2 if x0 is None else x0;x1=w/2-.2 if x1 is None else x1;y0=-d/2+.2 if y0 is None else y0;y1=d/2-.2 if y1 is None else y1
 box('Ceiling field',((x0+x1)/2,(y0+y1)/2,h+.05),(x1-x0,y1-y0,.10),field)
 for (cx,cy,sx,sy) in [((x0+x1)/2,y0+band/2,x1-x0,band),((x0+x1)/2,y1-band/2,x1-x0,band),(x0+band/2,(y0+y1)/2,band,y1-y0-2*band),(x1-band/2,(y0+y1)/2,band,y1-y0-2*band)]:box('Tray soffit',(cx,cy,h-drop/2),(sx,sy,drop),soffit)
 for (cx,cy,sx,sy) in [((x0+x1)/2,y0+band+.03,x1-x0-2*band,.04),((x0+x1)/2,y1-band-.03,x1-x0-2*band,.04),(x0+band+.03,(y0+y1)/2,.04,y1-y0-2*band),(x1-band-.03,(y0+y1)/2,.04,y1-y0-2*band)]:box('Cove light strip',(cx,cy,h-drop+.03),(sx,sy,.03),cove)
 for (cx,cy,sx,sy) in [((x0+x1)/2,y0+band,x1-x0-2*band+.1,.06),((x0+x1)/2,y1-band,x1-x0-2*band+.1,.06),(x0+band,(y0+y1)/2,.06,y1-y0-2*band),(x1-band,(y0+y1)/2,.06,y1-y0-2*band)]:box('Tray crown moulding',(cx,cy,h-drop-.02),(sx,sy,.06),trim)
def shell(q,M,pool=False):
 w,d,h=q['size_m'];gx=-w*.25;doorx=w*.29;M.setdefault('garagewall',M['wall'])
 box('Floor finish',(0,0,-.12),(w,d,.24),M['floor'])
 for x in [-w/2+.10,w/2-.10]:box('Side wall',(x,0,h/2),(.20,d,h),M['wall'])
 box('Rear wall',(0,d/2-.10,h/2),(w-.4,.20,h),M['wall'])
 openings=[(gx-1.9,gx+1.9,2.65)] if q['has_in_room_garage'] else []
 openings.append((doorx-.70,doorx+.70,2.45));openings.sort();last=-w/2+.20
 for lo,hi,hh in openings:
  if lo>last:box('Front wall pier',((lo+last)/2,-d/2+.10,h/2),(lo-last,.20,h),M['front'])
  box('Front opening lintel',((lo+hi)/2,-d/2+.10,(h+hh)/2),(hi-lo,.20,h-hh),M['front']);last=hi
 if last<w/2-.20:box('Front end pier',((last+w/2-.20)/2,-d/2+.10,h/2),(w/2-.20-last,.20,h),M['front'])
 for lo,hi,hh in openings:frame('Opening reveal',((lo+hi)/2,-d/2+.02,hh/2),hi-lo,hh,M['gold'],.08)
 if q['has_in_room_garage']:
  box('Garage door housing',(gx,-d/2+.30,2.95),(4.10,.48,.52),M['steel'],.04);box('Garage rear wall',(gx,-3.35,1.45),(6.15,.18,2.90),M['garagewall'])
  box('Garage jamb',(gx+3.15,-8.60,1.45),(.18,3.60,2.90),M['garagewall']);box('Garage jamb',(gx+3.15,-4.38,1.45),(.18,2.24,2.90),M['garagewall']);box('Garage door lintel',(gx+3.15,-6.15,2.675),(.18,1.30,.45),M['wood'])
  box('Garage stone floor',(gx,-6.85,.015),(6.15,7.10,.030),M['garagefloor'])
  for xx in [gx-2.55,gx+2.55]:box('Bay sideline',(xx,-7.0,.032),(.07,5.4,.01),mat('paint_white',(.85,.85,.82),rough=.6))
  box('Wheel stop',(gx,-3.80,.09),(2.5,.20,.18),mat('rubber',(.02,.02,.02),rough=.8),.035)
 # wardrobe + minibar near entrance (ornament B stays on the minibar top at z .90)
 for k in range(3):box('Wardrobe door',(w/2-.43,-7.3+k*.88,1.2),(.62,.85,2.4),M['cabinet'],.02);box('Wardrobe pull',(w/2-.76,-7.3+k*.88,1.25),(.03,.02,.32),M['gold'],.008)
 box('Minibar',(doorx-2.0,-8.8,.45),(1.3,.65,.90),M['cabinet'],.03);cyl('Ice bucket',(doorx-2.0,-8.8,1.03),.12,.22,M['steel'])
 # bathroom enclosure, identical openings
 bathx=w*.28;box('Bathroom side wall',(w*.055,8.5,1.6),(.15,3.8,3.2),M['bathwall'])
 box('Bathroom jamb',(bathx-2.2,6.80,1.6),(2.0,.16,3.2),M['bathfront']);box('Bathroom jamb',(bathx+2.5,6.80,1.6),(1.8,.16,3.2),M['bathfront']);box('Bathroom lintel',(bathx+.15,6.80,2.95),(2.7,.16,.5),M['bathfront'])
 box('Bathroom upper wall',(bathx+.15,6.80,3.55),(6.5,.16,.7),M['bathfront'])
 # bathroom-side lining of the front wall so the room side can carry the room finish
 if not M.get('glassfront'):box('Bath front lining',(bathx-2.2,6.89,1.6),(2.0,.02,3.2),M['bathwall'])
 if not M.get('glassfront'):box('Bath front lining',(bathx+2.5,6.89,1.6),(1.8,.02,3.2),M['bathwall']);box('Bath front lining',(bathx+.15,6.89,3.2),(2.7,.02,1.4),M['bathwall'])
 box('Bath floor',(w*.055+(w/2-.2-w*.055)/2,8.6,.012),(w/2-.2-w*.055,3.6,.024),M['bathfloor'])
 box('Rear wet strip floor',((-w/2+.2+w*.055)/2,8.6,.012),(w*.055+w/2-.2,3.6,.024),M['bathfloor'])
 for (cx,sx) in [((w*.055+w/2-.2)/2,w/2-.2-w*.055)]:
  box('Bath wall lining',(cx,10.18,1.9),(sx,.04,3.8),M['bathwall']);box('Bath side lining',(w/2-.22,8.6,1.9),(.04,3.5,3.8),M['bathwall'])
 vx=bathx-2.40;vy=9.78;box('Vanity cabinet',(vx,vy,.56),(1.8,.65,.58),M['vanity'],.03);box('Vanity counter',(vx,vy,.88),(1.9,.72,.08),M['counter'],.02)
 basin((vx,vy,.92),M['porcelain'],M['chrome'],rect=M.get('rectbasin',False))
 box('Vanity mirror backing',(vx,10.17,1.65),(1.75,.06,1.17),M['vanity']);frame('Vanity mirror frame',(vx,10.12,1.65),1.7,1.12,M['mirrorframe'],.08)
 sx=w/2-3.65 if pool else -w/2+1.30
 box('Shower rear panel',(sx,10.0,1.3),(1.55,.10,2.6),M['bathwall']);box('Shower side',(sx-.78,9.1,1.3),(.10,1.9,2.6),M['bathwall'])
 box('Shower glass door',(sx+.05,8.15,1.1),(1.45,.025,2.2),M['glass']);frame('Shower glass frame',(sx+.05,8.15,1.1),1.45,2.2,M['chrome'],.03)
 cyl('Rain shower stem',(sx,9.85,1.35),.025,2.2,M['chrome']);cyl('Rain shower head',(sx,9.48,2.45),.20,.04,M['chrome'])
 tx=sx+2.15;ty=9.4;box('WC cistern',(tx,9.85,.65),(.45,.24,.55),M['porcelain'],.06);ell('WC bowl',(tx,ty,.39),(.50,.68,.48),M['porcelain']);box('WC pedestal',(tx,ty,.18),(.30,.35,.36),M['porcelain'],.06)
 for xx in [tx-.80,tx+.80]:box('WC partition',(xx,9.10,1.40),(.10,2.20,2.80),M['bathwall'])
 for xx in [tx-.65,tx+.65]:box('WC jamb',(xx,8.0,1.40),(.30,.10,2.80),M['vanity'])
 box('WC lintel',(tx,8.0,2.55),(1.50,.10,.50),M['vanity']);box('WC door',(tx+.81,7.52,1.12),(.05,.95,2.24),M['vanity'],.01)
 return dict(vx=vx,bathx=bathx,doorx=doorx,gx=gx,sx=sx,tx=tx)
def common(q):
 return dict(gold=mat('gold',(.62,.42,.14),rough=.25,metal=1.),steel=mat('steel',(.3,.31,.33),rough=.25,metal=1.),chrome=mat('chrome',(.75,.76,.78),rough=.08,metal=1.),
  porcelain=mat('porcelain',(.92,.93,.93),rough=.12),glass=mat('glass',(.75,.85,.9),rough=.02,alpha=.22),water=mat('Water',(.03,.2,.25),rough=.05),
  garagefloor=mat('garage_stone',(.4,.39,.37),tex='marble_cream',tile=2.,rough=.5),
  linen=mat('linen',(.92,.91,.88),rough=.85),blackglass=mat('black_glass',(.01,.01,.012),rough=.05,metal=.3))
ROOMS={}
def room(f):ROOMS[f.__name__.split('_')[1]]=f;return f
# ------------------------------------------------------------------ 209 尊爵
@room
def r_imore93474c507aaf(q):
 C=common(q);w,d,h=q['size_m']
 M=dict(C,floor=mat('wood_dark',tex='wood_dark',tile=2.2,rough=.35),wall=mat('damask',tex='damask_brown_gold',tile=1.2,rough=.7),front=mat('dark_panel',(.16,.08,.05),tex='wood_dark',tile=1.6,rough=.4),
  wood=mat('wood_dark_trim',(.2,.1,.06),tex='wood_dark',tile=1.0,rough=.35),cabinet=mat('cabinet_cherry',(.25,.12,.07),tex='wood_walnut',tile=1.2,rough=.35),
  bathwall=mat('marble_redbrown',tex='marble_redbrown',tile=1.8,rough=.15),bathfront=mat('marble_redbrown',tex='marble_redbrown',tile=1.8,rough=.15),bathfloor=mat('marble_black',tex='marble_black',tile=1.5,rough=.12),
  vanity=mat('vanity_dark',(.06,.035,.03),tex='wood_dark',tile=1.0,rough=.3),counter=mat('marble_black',tex='marble_black',tile=1.5,rough=.12),mirrorframe=C['gold'])
 M['bathfront']=M['wall'];o=shell(q,M);ivory=mat('ivory',(.86,.80,.68),rough=.45);cream=mat('cream_plaster',(.86,.80,.70),rough=.8);cove=mat('cove_warm',(1.,.72,.42),emit=6.)
 tray_ceiling(w,d,h,cream,cream,cove,M['gold'],band=1.1)
 # wainscot: dark panels with gold rail on side and rear walls
 for x,ax in [(-w/2+.215,'y'),(w/2-.215,'y')]:
  box('Wainscot',(x,0,.47),(.03,d-.5,.94),M['wood']);box('Chair rail',(x,0,.95),(.05,d-.5,.05),M['gold'])
  for k in range(13):frame('Wainscot panel moulding',(x+(.02 if x<0 else -.02),-9.0+k*1.5,.47),1.2,.6,M['gold'],.025,'y')
 # TV wall facing the bed axis (photo 1)
 box('TV cabinetry wall',(1.6,-3.24,1.45),(4.4,.10,2.9),M['cabinet'],.02);box('TV low cabinet',(1.6,-3.0,.32),(3.6,.48,.64),M['cabinet'],.02)
 box('Television',(1.6,-3.16,1.55),(1.95,.06,1.12),C['blackglass'],.01);box('Television screen',(1.6,-3.125,1.55),(1.86,.01,1.04),mat('screen',(.05,.12,.25),emit=1.2))
 for xx in [-.3,3.5]:box('Tall speaker',(xx,-2.95,.75),(.32,.36,1.5),mat('speaker',(.03,.025,.02),rough=.4),.02);box('Speaker grille',(xx,-2.77,.95),(.24,.01,.9),mat('grille',(.01,.01,.01),rough=.9))
 for xx in [.35,2.85]:box('Shelf niche glow',(xx,-3.18,2.1),(.6,.02,.5),mat('niche',(1.,.75,.45),emit=2.))
 # rug, oval marble table, facing gilded sofas (photo 2)
 plane('Gold-bordered rug',(1.6,-.45,.006),(3.4,4.6),mat('rug',tex='rug_cream_gold',fit=True,rough=.95),'+z')
 marble=mat('marble_redbrown_table',tex='marble_redbrown',tile=1.2,rough=.08)
 cyl('Oval table top',(1.6,-.45,.47),.5,.08,marble,n=48,sx=1,sy=1.75);cyl('Oval table drum',(1.6,-.45,.22),.40,.42,M['vanity'],n=48,sx=1,sy=1.7);cyl('Table gold band',(1.6,-.45,.40),.415,.03,M['gold'],n=48,sx=1,sy=1.7)
 furn('red_baroque_sofa',-.25,-.45,90);furn('red_baroque_sofa',3.45,-.45,-90)
 for x in [.05,3.15]:column(x,3.05,h-.36,ivory,M['gold'])
 furn('canopy_bed',1.6,5.15,0)
 for x in [.0,3.2]:box('Lamp pedestal',(x,6.0,.33),(.5,.45,.66),M['cabinet'],.02);lamp_pleated(x,6.0,.66,mat('lamp_red',(.9,.25,.18),emit=1.5),M['gold'])
 box('Partition behind bed',(-1.08,6.72,h/2),(3.84,.16,h),M['wall'])
 # left lounge: second sofa, armchair, massage chairs behind sheer curtains (photo 3)
 furn('red_baroque_sofa',-4.6,-1.6,180);furn('red_baroque_armchair',-6.6,.2,90)
 cyl('Round side table',(-4.6,.05,.48),.38,.05,marble,n=32);cyl('Side table pedestal',(-4.6,.05,.23),.08,.46,M['gold'])
 furn('massage_chair',-6.35,4.6,180);furn('massage_chair',-5.15,4.6,180)
 drape('Sheer curtain',-7.3,-4.4,5.75,.05,3.5,mat('sheer',(.95,.88,.75),rough=.9,alpha=.55),'x',12,.06)
 drape('Heavy drape',-3.0,3.2,-7.45,.05,3.5,mat('drape_cream',(.82,.70,.52),rough=.9),'y',8,.09)
 for (x,y) in [(1.6,-.45),(1.6,4.6),(-4.6,-.6)]:furn('brass_chandelier',x,y,0,h-.82)
 # bathroom: square jacuzzi in marble, glass shower, ficus vines (photos 4-6)
 white=mat('acrylic',(.95,.95,.93),rough=.1)
 box('Jacuzzi marble plinth',(o['bathx']+.6,8.55,.20),(2.7,2.4,.40),M['bathwall'])
 hollow_tub('Square jacuzzi',(o['bathx']+.6,8.55,.40),(2.3,2.0),white,white,C['water'],True,.15,.55)
 leaf=mat('ficus_leaf',(.18,.42,.12),rough=.6);bark=mat('ficus_bark',(.25,.18,.10),rough=.8)
 for k in range(5):
  x0=o['bathx']-.5+k*.55;pts=[(x0+.15*math.sin(t*2+k),10.1,3.4-t*1.2) for t in [i/8 for i in range(9)]];tube('Ficus vine',pts,.018,bark)
  for i in range(14):t=i/13;ell('Ficus leaf',(x0+.15*math.sin(t*2+k)+.12*math.cos(i*2.1),10.05,3.4-t*1.2),(.12,.03,.07),leaf,8)
 for xx in [o['vx']-1.0,o['vx']+1.0]:cyl('Bath sconce',(xx,10.08,1.85),.06,.22,mat('sconce_warm',(1.,.8,.55),emit=3.),n=16)
 lights=[((1.6,-.45,3.0),(1.,.76,.52),3500,800),((1.6,4.6,3.0),(1.,.74,.5),2800,700),((-4.6,-.6,3.0),(1.,.76,.52),2600,700),((-5.8,4.2,2.6),(1.,.7,.45),1200,450),((4.4,8.5,3.0),(1.,.82,.62),2500,600),((4.4,-7.2,2.8),(1.,.8,.6),1500,500),((.0,6.0,1.3),(1.,.45,.3),400,280),((3.2,6.0,1.3),(1.,.45,.3),400,280)]
 views=[dict(id='photo2-sofas-to-bed',eye=[1.6,-2.75,1.5],target=[1.6,5.0,1.1],fov=84,ref='imore-93474c507aaf-2'),dict(id='photo1-toward-tv',eye=[-.2,2.25,1.85],target=[2.2,-3.2,.9],fov=86,ref='imore-93474c507aaf-1'),
  dict(id='photo3-massage-chairs',eye=[-3.2,2.0,1.5],target=[-5.8,4.6,.9],fov=72,ref='imore-93474c507aaf-3'),dict(id='photo6-jacuzzi',eye=[3.0,7.3,2.3],target=[5.0,8.9,.5],fov=82,ref='imore-93474c507aaf-6')]
 return dict(lights=lights,views=views,decorA=[1.6,-.45,.51],decorB=[o['doorx']-2.0,-8.8,.90])
# ------------------------------------------------------------------ 303 慾望城市
@room
def r_imore72417f713153(q):
 C=common(q);w,d,h=q['size_m']
 M=dict(C,floor=mat('terrazzo',tex='terrazzo_star_bw',tile=4.0,rough=.12),wall=mat('key_wallpaper',tex='wallpaper_key_purple',tile=1.0,rough=.6),front=mat('wood_vertical',(.2,.12,.08),tex='wood_walnut',tile=1.4,rough=.4),
  wood=mat('wood_walnut_trim',tex='wood_walnut',tile=1.0,rough=.4),cabinet=mat('lacquer_white',(.85,.84,.82),rough=.15),
  bathwall=mat('marble_black_wall',tex='marble_black',tile=1.6,rough=.18),bathfront=mat('starry_glass',(.01,.015,.06),rough=.05,metal=.2),bathfloor=mat('marble_black',tex='marble_black',tile=1.5,rough=.12),
  vanity=mat('vanity_black',(.02,.02,.025),rough=.2),counter=mat('marble_black',tex='marble_black',tile=1.5,rough=.12),mirrorframe=mat('led_frame',(.9,.95,1.),emit=4.))
 o=shell(q,M);mag=mat('magenta_led',(1.,.12,.85),emit=9.);mirrorc=mat('mirror_ceiling',(.6,.55,.62),rough=.04,metal=1.);black=mat('black_gloss',(.015,.012,.018),rough=.1)
 tray_ceiling(w,d,h,mirrorc,mat('ceiling_white',(.9,.88,.9),rough=.7),mag,mat('silver',(.7,.7,.72),rough=.2,metal=1.),band=1.3,drop=.4)
 for x in [-w/2+.22,w/2-.22]:
  for k in range(11):box('Vertical LED strip',(x,-8.0+k*1.6,1.65),(.04,.05,2.7),mag)
 # bed alcove: red tufted velvet headwall, black mirror lattice wings, sconces (photo 1)
 box('Alcove back wall',(-3.34,6.55,h/2),(5.4,.16,h),black)
 box('Tufted velvet headwall',(-3.34,6.42,1.65),(3.4,.12,2.9),mat('velvet_red',tex='velvet_tufted_red',tile=1.0,rough=.85),.03)
 for x in [-5.75,-.93]:box('Mirror lattice wing',(x,5.2,1.8),(.12,2.6,3.6),mat('mirror_lattice',tex='mirror_lattice_black',tile=1.0,rough=.08,metal=.4))
 for x in [-4.9,-1.8]:cyl('Wall sconce',(x,6.32,1.95),.07,.24,mat('sconce_bulb',(1.,.85,.6),emit=5.),n=16)
 box('Bed base',(-3.34,4.7,.22),(2.3,2.4,.44),black,.06);box('Mattress',(-3.34,4.7,.55),(2.2,2.3,.26),C['linen'],.08);box('Duvet',(-3.34,4.55,.70),(2.26,2.0,.10),mat('duvet_white',(.95,.93,.97),rough=.85),.05)
 for x in [-3.9,-2.78]:o2=box('Silver pillow',(x,5.6,.92),(.9,.32,.5),mat('satin_silver',(.65,.62,.66),rough=.4),.1);o2.rotation_euler.x=.2;box('White pillow',(x,5.35,.82),(.85,.28,.38),C['linen'],.09)
 for x in [-5.0,-1.68]:box('Glass nightstand',(x,5.6,.3),(.55,.45,.6),black,.02)
 mirrorc2=mirrorc;box('Bed ceiling mirror',(-3.34,4.6,h-.06),(3.6,3.2,.02),mirrorc2);ring('Bed cove ring',(-3.34,4.6,h-.08),1.95,1.75,.02,mag,'xy')
 # living: purple sofa, four red shell chairs, black glass table on lit gold lattice (photos 2-4)
 box('Coffee table glass top',(2.7,-.6,.44),(1.5,.95,.04),black,.01)
 for xx in [-1,1]:
  for yy in [-1,1]:tube('Gold lattice',[(2.7+xx*.68,-.6+yy*.42,.05),(2.7-xx*.68,-.6-yy*.42,.40)],.012,C['gold'])
 box('Table inner glow',(2.7,-.6,.22),(1.2,.7,.30),mat('table_glow',(.95,.62,.18),emit=1.4),.01)
 furn('purple_silver_sofa',2.7,-2.3,180)
 for (x,y,r) in [(.95,-1.25,90),(.95,.2,90),(4.45,-1.25,-90),(4.45,.2,-90)]:furn('red_shell_armchair',x,y,r)
 box('TV cabinet',(2.7,3.35,.35),(2.2,.5,.7),M['cabinet'],.02);box('Television',(2.7,3.40,1.35),(1.65,.06,.95),black,.01);box('Screen',(2.7,3.365,1.35),(1.58,.01,.9),mat('screen_dark',(.02,.03,.06),emit=.5))
 furn('massage_chair',5.0,4.9,180)
 for (x,y) in [(2.7,-.6),(-3.34,3.7)]:furn('crystal_chandelier',x,y,0,h-.40-.86)
 # starry glass bathroom front (photo 4): dark glass with fibre-optic points
 star=mat('star_point',(.55,.7,1.),emit=12.)
 for k in range(160):
  x=1.25+(k*.6180339%1)*1.9 if k%2 else 5.8+(k*.4142135%1)*1.55;z=.3+(k*.7548776%1)*2.9;ell('Fibre star',(x,6.71,z),(.03,.01,.03),star,6)
 box('Red lacquer mirror cabinet',(.5,-10.15,1.4),(1.6,.12,2.6),mat('red_lacquer',(.6,.03,.05),rough=.15),.02);box('Cabinet mirror',(.5,-10.08,1.4),(1.3,.02,2.3),mat('mirror_pane',(.7,.7,.72),rough=.03,metal=1.))
 white=mat('acrylic',(.95,.95,.93),rough=.1)
 box('Tub black surround',(o['bathx']+.6,8.55,.25),(2.6,2.2,.5),M['bathwall'])
 hollow_tub('Jacuzzi',(o['bathx']+.6,8.55,.50),(2.2,1.6),white,white,C['water'],True,.12,.45)
 lights=[((2.7,-.6,3.0),(1.,.55,.95),3000,800),((-3.34,4.6,3.0),(1.,.82,.88),2800,650),((-6.6,-2,3.2),(1.,.25,.9),900,500),((6.6,-2,3.2),(1.,.25,.9),900,500),((6.6,4,3.2),(1.,.25,.9),900,500),((4.4,8.5,3.0),(.75,.8,1.),2200,600),((4.4,-7.2,2.8),(1.,.75,.9),1500,500),((-4.9,6.1,2.0),(1.,.8,.6),350,250),((-1.8,6.1,2.0),(1.,.8,.6),350,250)]
 views=[dict(id='photo1-velvet-bed',eye=[-3.34,.7,1.45],target=[-3.34,6.3,1.5],fov=82,ref='imore-72417f713153-1'),dict(id='photo2-living',eye=[5.4,-3.1,1.75],target=[.6,1.6,.9],fov=88,ref='imore-72417f713153-2'),
  dict(id='photo4-shell-chairs',eye=[-.3,-2.9,1.6],target=[4.6,1.0,1.0],fov=86,ref='imore-72417f713153-4'),dict(id='photo5-bath',eye=[3.0,7.3,2.3],target=[5.0,8.9,.5],fov=82,ref='imore-72417f713153-5')]
 return dict(lights=lights,views=views,decorA=[2.7,-.6,.46],decorB=[o['doorx']-2.0,-8.8,.90])
# ------------------------------------------------------------------ 512 香奈兒 (WeGo)
@room
def r_wegolinsen785baab83ea4(q):
 C=common(q);w,d,h=q['size_m']
 M=dict(C,floor=mat('walnut_floor',tex='wood_walnut',tile=2.2,rough=.3),wall=mat('peach_plaster',(.88,.70,.58),rough=.8),front=mat('peach_plaster',(.88,.70,.58),rough=.8),
  wood=mat('black_lacquer',(.02,.018,.016),rough=.12),cabinet=mat('black_lacquer',(.02,.018,.016),rough=.12),
  bathwall=mat('white_tile',tex='tile_white_large',tile=1.2,rough=.15),bathfront=mat('clear_glass_wall',(.7,.78,.8),rough=.03,alpha=.3),bathfloor=mat('marble_black',tex='marble_black',tile=1.5,rough=.12),
  vanity=mat('black_lacquer',(.02,.018,.016),rough=.12),counter=mat('marble_black',tex='marble_black',tile=1.5,rough=.12),mirrorframe=C['gold'],rectbasin=True,glassfront=True)
 o=shell(q,M);white=mat('ceiling_white',(.93,.92,.9),rough=.7);cove=mat('cove_warm',(1.,.72,.42),emit=6.);black=M['cabinet'];oak=mat('honey_oak',(.72,.48,.22),rough=.45)
 tray_ceiling(w,d,h,white,white,cove,C['gold'],band=1.0,drop=.3)
 for x in [-w/2+.22,w/2-.22]:box('Gold wall band',(x,0,3.42),(.03,d-.5,.06),C['gold'])
 for (x,y) in [(-3.34,3.0),(-3.34,6.0),(1.6,-1),(1.6,2.5),(4.4,-6),(-5.8,1),(-.8,1)]:downlight(x,y,h-.3,mat('downlight',(1.,.92,.8),emit=8.))
 # bed with low black headboard ledge and gold strip (photo 1)
 box('Headboard ledge',(-3.34,6.35,.55),(5.2,.35,1.1),black,.02);box('Ledge gold strip',(-3.34,6.17,1.1),(5.2,.02,.04),C['gold'])
 box('Partition behind bed',(-2.6,6.6,h/2),(6.9,.16,h),M['wall'])
 box('Bed base',(-3.34,4.7,.2),(2.0,2.3,.40),mat('bed_skirt',(.85,.83,.8),rough=.9),.05);box('Mattress',(-3.34,4.7,.5),(2.0,2.2,.26),C['linen'],.08);box('Duvet',(-3.34,4.5,.66),(2.06,1.9,.12),C['linen'],.06)
 box('Bed runner',(-3.34,3.9,.73),(2.08,.45,.03),mat('runner_brown',(.25,.12,.06),rough=.7),.01)
 for x in [-3.9,-2.78]:o2=box('Pillow',(x,5.55,.9),(.9,.32,.5),C['linen'],.1);o2.rotation_euler.x=.2
 box('Accent cushion',(-3.34,5.2,.85),(.55,.18,.42),mat('orange_cushion',(.75,.33,.08),rough=.7),.06)
 for x in [-5.15,-1.53]:box('Bedside cabinet',(x,5.9,.3),(.6,.5,.6),black,.02);lamp_drum(x,5.9,.6,mat('lamp_shade_black',(.04,.035,.03),rough=.6),C['gold'],.6);ell('Gold ball base',(x,5.9,.68),(.18,.18,.16),C['gold'])
 # booth at the bed foot: honey oak table between two tan leather tub chairs (photo 1)
 box('Booth table top',(-3.34,2.05,.74),(.65,1.15,.04),oak,.01);box('Booth table side',(-3.34,1.5,.37),(.62,.03,.74),oak);box('Booth table side',(-3.34,2.6,.37),(.62,.03,.74),oak);box('Booth shelf',(-3.34,2.05,.25),(.6,1.1,.02),oak)
 furn('tan_tub_chair',-4.35,2.05,90);furn('tan_tub_chair',-2.33,2.05,-90)
 # black cabinetry with painted lily glass panels beside the bed
 box('Black counter',(-.05,6.22,.45),(1.6,.55,.9),black,.02);box('Counter gold edge',(-.05,5.95,.9),(1.6,.02,.03),C['gold'])
 for x in [-.45,.35]:plane('Lily glass panel',(x,6.5,2.0),(.62,1.75),mat('lily_panel',tex='panel_lily',fit=True,rough=.55),'-y');box('Panel black frame',(x,6.535,2.0),(.7,.02,1.85),black)
 box('TV console',(-3.34,-3.0,.3),(2.4,.45,.6),black,.02);box('Television',(-3.34,-3.08,1.35),(1.2,.05,.7),C['blackglass']);box('Screen',(-3.34,-3.05,1.35),(1.15,.01,.65),mat('screen_dark',(.02,.03,.06),emit=.5))
 # bathroom: white tile, black band, gold mirror, bronze sconces, rectangular tub in black surround (photos 2-3)
 box('Black frieze',((w*.055+w/2-.2)/2,10.15,3.15),(w/2-.2-w*.055,.03,.35),mat('marble_black',tex='marble_black',tile=1.5,rough=.12))
 plane('Checker border',((w*.055+w/2-.2)/2,10.13,2.95),(w/2-.2-w*.055,.08),mat('checker',tex='mosaic_black_white_check',tile=.3,rough=.2),'-y')
 hollow_tub('Rectangular tub',(o['bathx']+.7,9.55,.0),(2.2,1.2),mat('marble_black',tex='marble_black',tile=1.5,rough=.12),C['porcelain'],C['water'],True,.16,.56)
 for xx in [o['vx']-1.05,o['vx']+1.05]:tube('Sconce arm',[(xx,10.15,1.7),(xx,10.0,1.85)],.015,mat('bronze',(.3,.18,.08),rough=.3,metal=1.));cyl('Frosted sconce shade',(xx,9.98,1.95),.09,.18,mat('frosted',(1.,.9,.75),emit=3.),r2=.05,n=16)
 lights=[((-3.34,4.0,3.0),(1.,.8,.6),3200,800),((1.6,0,3.0),(1.,.82,.65),2800,800),((-3.34,-1.0,3.0),(1.,.82,.65),2000,600),((4.4,8.5,3.0),(1.,.92,.82),3000,650),((4.4,-7.2,2.8),(1.,.85,.7),1500,500),((-5.15,5.9,1.3),(1.,.75,.5),450,280),((-1.53,5.9,1.3),(1.,.75,.5),450,280)]
 views=[dict(id='photo1-booth-and-bed',eye=[-.5,-1.6,1.5],target=[-4.0,4.9,1.0],fov=82,ref='wego-linsen-785baab83ea4-1'),dict(id='photo2-tub-vanity',eye=[2.3,7.2,1.65],target=[5.6,9.6,.9],fov=86,ref='wego-linsen-785baab83ea4-b2'),
  dict(id='photo3-vanity',eye=[5.8,7.3,1.6],target=[1.9,10.0,1.2],fov=86,ref='wego-linsen-785baab83ea4-b3')]
 return dict(lights=lights,views=views,decorA=[-3.34,2.05,.76],decorB=[o['doorx']-2.0,-8.8,.90])
# ------------------------------------------------------------------ 203 泳池房1
@room
def r_imorecda5d5e2dcb9(q):
 C=common(q);w,d,h=q['size_m']
 M=dict(C,floor=mat('wood_dark',tex='wood_dark',tile=2.2,rough=.35),wall=mat('linen_wallpaper',tex='wallpaper_cream_linen',tile=1.0,rough=.8),front=mat('linen_wallpaper',tex='wallpaper_cream_linen',tile=1.0,rough=.8),
  wood=mat('wood_dark_trim',(.2,.1,.06),tex='wood_dark',tile=1.0,rough=.35),cabinet=mat('cabinet_dark',(.06,.04,.03),tex='wood_dark',tile=1.0,rough=.3),
  bathwall=mat('marble_cream_wall',tex='marble_cream',tile=1.6,rough=.15),bathfront=mat('marble_cream_wall',tex='marble_cream',tile=1.6,rough=.15),bathfloor=mat('marble_cream_floor',tex='marble_cream',tile=1.2,rough=.12),
  vanity=mat('vanity_dark',(.06,.035,.03),tex='wood_dark',tile=1.0,rough=.3),counter=mat('marble_redbrown',tex='marble_redbrown',tile=1.2,rough=.12),mirrorframe=mat('silver',(.7,.7,.72),rough=.2,metal=1.))
 o=shell(q,M,True);cream=mat('cream_plaster',(.86,.80,.70),rough=.8);cove=mat('cove_warm',(1.,.72,.42),emit=5.)
 # bedroom/living ceiling with dark wood beams; pool hall plain with skylight grid
 tray_ceiling(w,d,h,cream,M['cabinet'],cove,C['gold'],band=.7,drop=.3,x0=-.9,x1=w/2-.2)
 box('Pool hall ceiling',(-8.1,0,h+.05),(14.2,d-.4,.10),mat('hall_ceiling',tex='ceiling_grid_dark',tile=2.4,rough=.8))
 navy=mat('navy_mosaic',tex='mosaic_navy',tile=1.0,rough=.15)
 plane('Hall front mosaic',(-8.05,-10.18,1.95),(14.0,3.9),navy,'+y');plane('Hall left mosaic lower',(-14.98,4.6,.68),(11.2,1.36),navy,'+x');plane('Hall left mosaic front',(-14.98,-5.25,1.95),(9.9,3.9),navy,'+x')
 sky=mat('skylight',(.85,.92,1.),emit=3.5);grid=mat('skylight_frame',(.02,.02,.02),rough=.5)
 box('Skylight glow',(-8.6,8.2,h-.02),(12.4,3.6,.02),sky)
 for k in range(13):box('Skylight mullion',(-14.8+k*1.03,8.2,h-.06),(.06,3.7,.06),grid)
 for k in range(4):box('Skylight transom',(-8.6,6.4+k*1.2,h-.06),(12.4,.06,.06),grid)
 # glass partition between pool hall and bedroom, opening on the pool walkway (y 3.3..5.1)
 dk=mat('dark_glass',(.05,.05,.06),rough=.03,alpha=.45);mull=mat('black_metal',(.02,.02,.02),rough=.35,metal=.6)
 for (y0,y1) in [(-3.2,3.3),(5.1,10.2)]:
  box('Glass partition',(-1.0,(y0+y1)/2,1.95),(.03,y1-y0,3.9),dk)
  for k in range(int((y1-y0)/1.2)+1):box('Partition mullion',(-1.0,y0+k*1.2,1.95),(.07,.07,3.9),mull)
 box('Partition lintel',(-1.0,4.2,3.25),(.16,1.8,1.3),mull)
 # pool: blue mosaic walls, wave-pattern floor, granite coping, raised deck so the water reads flush (photos 1-3, 5)
 px,py,pw,pd=-w*.27,4.2,8.2,8.3;blue=mat('pool_mosaic',tex='mosaic_pool_blue',tile=1.0,rough=.15);granite=mat('granite',tex='granite_brown',tile=1.5,rough=.25)
 box('Pool base',(px,py,.20),(pw,pd,.40),blue);plane('Pool floor design',(px,py,.402),(pw-.5,pd-.5),mat('pool_floor',tex='pool_floor_design',fit=True,rough=.15),'+z')
 for xx in [-pw/2,pw/2]:box('Pool side wall',(px+xx,py,.78),(.25,pd,1.16),blue)
 for yy in [-pd/2,pd/2]:box('Pool end wall',(px,py+yy,.78),(pw,.25,1.16),blue)
 for xx in [-pw/2,pw/2]:box('Pool coping',(px+xx,py,1.38),(.45,pd+.45,.05),granite,.01)
 for yy in [-pd/2,pd/2]:box('Pool coping',(px,py+yy,1.38),(pw+.45,.45,.05),granite,.01)
 box('Water',(px,py,1.12),(pw-.30,pd-.30,.018),C['water'])
 box('Rear deck',(-9.5,9.34,.68),(10.9,1.72,1.36),granite);box('Left deck',(-13.69,4.2,.68),(2.53,8.3,1.36),granite)
 band=mat('wave_band',tex='mosaic_black_white_check',tile=.6,rough=.2)
 plane('Deck riser band',(-13.69+1.27,1.4,.68),(2.53,1.2),band,'-y')
 for k in range(7):box('Pool access step',(px+pw/2+.28+k*.30,py,(7-k)*.18/2),(.30,2.0,(7-k)*.18),granite)
 # striped mosaic wall, mural band with wavy edge, sconces
 stripe=mat('stripe_mosaic',tex='mosaic_red_white',tile=1.0,rough=.2)
 plane('Striped mosaic wall',(-8.5,10.17,2.26),(12.9,1.8),stripe,'-y');plane('Striped mosaic wall',(-14.98,4.6,2.26),(11.2,1.8),stripe,'+x')
 plane('Desert mural',(-8.5,10.16,3.52),(12.9,.75),mat('mural',tex='mural_desert',fit=True,rough=.6),'-y')
 tube('Mural wave edge',[(-14.95+i*12.9/80,10.12,3.16+.05*math.sin(i*.6)) for i in range(81)],.03,mat('wave_white',(.95,.95,.92),rough=.4))
 for k in range(6):x=-14.2+k*2.1;box('Sconce bracket',(x,10.1,2.75),(.06,.12,.06),mull);cyl('Sconce glass',(x,10.0,2.85),.07,.26,mat('sconce_white',(1.,.95,.85),emit=4.),n=16)
 # black glass shower cubicles + teak bench by the garage side (photo 6)
 for (x0,x1,y) in [(-14.9,-11.3,-.15)]:
  box('Shower cubicle glass',((x0+x1)/2,y,1.2),(x1-x0,.03,2.4),dk);box('Shower cubicle glass',(x1,(y-3.0)/2+0.0,1.2),(.03,2.9,2.4),dk);frame('Cubicle frame',((x0+x1)/2,y,1.2),x1-x0,2.4,mull,.04)
 box('Cubicle divider',(-13.1,-1.6,1.2),(.03,2.9,2.4),mull)
 teak=mat('teak',(.55,.4,.25),tex='wood_walnut',tile=1.0,rough=.5)
 for k in range(6):box('Bench slat',(-10.6,-1.2+k*.09-.25,.45),(1.2,.07,.03),teak)
 for xx in [-11.1,-10.1]:box('Bench leg',(xx,-1.2,.22),(.05,.45,.44),teak)
 cyl('Planter',(-1.7,8.0,.3),.35,.6,mat('planter',(.15,.1,.08),rough=.6),r2=.28);
 for k in range(9):ell('Flower bunch',(-1.7+.2*math.cos(k*.7),8.0+.2*math.sin(k*.7),.75+.08*(k%3)),(.18,.18,.18),mat('flower',(.85,.3,.35) if k%2 else (.95,.85,.4),rough=.7),10)
 # bedroom: round pleated headboard in a bronze ring, drum lamps (photos 7-8)
 bx,by=w*.14,4.7;bronze=mat('bronze',(.3,.18,.08),rough=.3,metal=1.)
 box('Partition behind bed',(3.49,6.62,h/2),(3.64,.16,h),M['wall'])
 cyl('Pleated round headboard',(bx,6.38,1.6),1.25,.14,mat('pleat',tex='pleat_radial_cream',fit=True,rough=.7),n=64).rotation_euler.x=math.pi/2
 ring('Headboard bronze ring',(bx,6.30,1.6),1.33,1.33,.05,bronze,'xz')
 for s in [-1,1]:tube('Headboard sword finial',[(bx+s*1.40,6.28,2.6),(bx+s*1.28,6.28,1.6)],.015,C['gold'])
 box('Bed base',(bx,by,.22),(2.2,2.3,.44),mat('bed_dark',(.12,.07,.08),rough=.8),.06);box('Mattress',(bx,by,.55),(2.1,2.2,.26),C['linen'],.08)
 box('Bedspread',(bx,by-.25,.72),(2.2,1.75,.1),mat('bedspread',(.22,.14,.16),rough=.8),.05)
 for x in [bx-.55,bx+.55]:o2=box('Purple pillow',(x,5.55,.95),(.9,.32,.5),mat('pillow_plum',(.25,.12,.22),rough=.7),.1);o2.rotation_euler.x=.25;box('White pillow',(x,5.3,.85),(.85,.28,.38),C['linen'],.09)
 shade=mat('drum_shade',(.95,.85,.6),emit=2.)
 for x in [bx-1.8,bx+1.8]:cyl('Woven nightstand',(x,5.5,.32),.32,.64,mat('wicker',(.25,.2,.15),rough=.8));lamp_drum(x,5.5,.64,shade,mat('chrome',(.75,.76,.78),rough=.08,metal=1.),.95)
 # living: purple chesterfield, gold mosaic drum table, TV on mosaic pedestal, massage chair, iron chandeliers (photos 9-10)
 lx,ly=w*.27,-.2;gm=mat('gold_mosaic',(.6,.45,.2),tex='mosaic_gold',tile=.4,rough=.3,metal=.7)
 furn('purple_chesterfield',lx,ly,0);furn('purple_chesterfield',lx-2.55,ly-1.5,90)
 for (x,y) in [(lx-2.6,ly+.25),(lx+1.6,ly+.15)]:lamp_drum(x,y,0,mat('floor_lamp_shade',(.95,.85,.62),emit=2.),mat('bronze',(.3,.18,.08),rough=.3,metal=1.),1.6)
 cyl('Drum table',(lx,ly-1.5,.25),.52,.5,gm,n=40);cyl('Drum table top',(lx,ly-1.5,.515),.55,.03,mat('marble_redbrown',tex='marble_redbrown',tile=1.2,rough=.12),n=40)
 cyl('TV pedestal',(lx,-3.0,.3),.45,.6,gm,n=40);box('Television',(lx,-3.0,1.15),(1.35,.06,.78),C['blackglass']);box('Screen',(lx,-2.965,1.15),(1.3,.01,.72),mat('screen',(.05,.12,.25),emit=1.2))
 furn('massage_chair',lx+2.5,-.7,155)
 for (x,y) in [(lx,ly-1.2),(bx,3.9)]:furn('iron_red_chandelier',x,y,0,h-.30-.9)
 frame_m=C['gold'];art=mat('botanical_art',(.85,.82,.72),rough=.7)
 for yy in [-1.2,.0]:box('Botanical print',(w/2-.23,yy,1.9),(.02,.5,.65),art);frame('Print frame',(w/2-.24,yy,1.9),.55,.7,frame_m,.03,'y')
 # bathroom: round jacuzzi in cream marble, checker border (photos 11-12)
 hollow_tub('Round jacuzzi',(o['bathx']+.65,8.4,.0),(2.0,2.0),M['bathwall'],C['porcelain'],C['water'],False,.18,.62)
 plane('Checker border',((w*.055+w/2-.2)/2,10.14,2.6),(w/2-.2-w*.055,.12),mat('checker',tex='mosaic_black_white_check',tile=.3,rough=.2),'-y')
 lights=[((-8.2,4.2,3.5),(.88,.93,1.),3200,1200),((-12.8,-1.5,3.0),(1.,.95,.85),1500,500),((-3.0,8.0,3.0),(1.,.92,.8),1500,600),((bx,4.0,3.0),(1.,.78,.55),2600,700),((lx,-1.0,3.0),(1.,.76,.52),3000,800),((o['bathx'],8.5,3.0),(1.,.86,.7),2600,650),((o['doorx'],-7.2,2.8),(1.,.82,.62),1500,500)]
 views=[dict(id='photo1-pool-hall',eye=[-2.8,-1.0,2.7],target=[-11.5,9.5,1.4],fov=92,ref='imore-cda5d5e2dcb9-1'),dict(id='photo3-striped-wall',eye=[-13.8,.6,3.0],target=[-6.0,9.6,1.0],fov=90,ref='imore-cda5d5e2dcb9-3'),
  dict(id='photo8-round-headboard',eye=[5.6,2.2,1.5],target=[bx,6.2,1.5],fov=75,ref='imore-cda5d5e2dcb9-8'),dict(id='photo9-living',eye=[11.5,1.2,2.0],target=[7.6,-2.8,1.0],fov=86,ref='imore-cda5d5e2dcb9-9')]
 return dict(lights=lights,views=views,decorA=[lx,ly-1.5,.53],decorB=[o['doorx']-2.0,-8.8,.90])
# ------------------------------------------------------------------ build
def uvs(o):
 if o.get('keepuv') or o.type!='MESH' or not o.data.materials:return
 m=o.data.materials[0];tile=float(m.get('tile',1.0));fit=bool(m.get('fit',False))
 bm=bmesh.new();bm.from_mesh(o.data);uv=bm.loops.layers.uv.verify();mw=o.matrix_world
 if fit:
  cs=[mw@v.co for v in bm.verts];lo=[min(c[k] for c in cs) for k in range(3)];hi=[max(c[k] for c in cs) for k in range(3)];ext=[hi[k]-lo[k] for k in range(3)];thin=ext.index(min(ext));ax=[k for k in range(3) if k!=thin]
 for f in bm.faces:
  n=mw.to_3x3()@f.normal;a=max(range(3),key=lambda k:abs(n[k]))
  for l in f.loops:
   c=mw@l.vert.co
   if fit:u=(c[ax[0]]-lo[ax[0]])/max(ext[ax[0]],1e-6);v=(c[ax[1]]-lo[ax[1]])/max(ext[ax[1]],1e-6)
   else:
    if a==2:u,v=c.x,c.y
    elif a==1:u,v=(c.x if n[1]<0 else -c.x),c.z
    else:u,v=(-c.y if n[0]<0 else c.y),c.z
    u/=tile;v/=tile
   l[uv].uv=(u,v)
 bm.to_mesh(o.data);bm.free()
def route_check(q,info):
 w=q['size_m'][0];pool=q['is_pool_suite'];doorx=w*.29
 segs=[((doorx,-11.2),(doorx,-5.0)),((doorx,-5.0),(w/2-1.25,-5.0)),((w/2-1.25,-5.0),(w/2-1.25,2.1)),((w/2-1.25,2.1),(-.54 if not pool else 7.06,2.1))]
 if pool:segs.append(((w/2-1.25,2.1),(13.7,7.1)))
 else:segs.append(((-.54,2.1),(-.54,1.2)))  # the audited standing point (motel-install eye) must stay clear
 bad=[]
 for o in OBJS:
  if o.type!='MESH' or 'Opening reveal' in o.name or 'Front' in o.name or 'Floor' in o.name or 'floor' in o.name or 'rug' in o.name.lower() or 'Ceiling' in o.name or 'Pool' in o.name or 'Water' in o.name:continue
  cs=[o.matrix_world@Vector(b) for b in o.bound_box];lo=[min(c[k] for c in cs) for k in range(3)];hi=[max(c[k] for c in cs) for k in range(3)]
  if hi[2]<.06 or lo[2]>1.8:continue
  for (a,b) in segs:
   x0,x1=sorted([a[0],b[0]]);y0,y1=sorted([a[1],b[1]]);r=.38
   if lo[0]<x1+r and hi[0]>x0-r and lo[1]<y1+r and hi[1]>y0-r:bad.append(o.name);break
 return sorted(set(bad))
results=[]
for rid,q in plan.items():
 key=rid.replace('-','')
 if key not in ROOMS or (TASK.get('only') and TASK['only']!=rid):continue
 bpy.ops.wm.read_factory_settings(use_empty=True);MATS.clear();OBJS.clear()
 info=ROOMS[key](q);blockers=route_check(q,info)
 for o in OBJS:uvs(o)
 furniture=[o.name for o in OBJS if o.get('keepuv')]
 dest=S/'models'/rid;dest.mkdir(parents=True,exist_ok=True)
 wet=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.data.materials and o.data.materials[0] and o.data.materials[0].name=='S_Water']
 bpy.ops.object.select_all(action='DESELECT')
 for o in wet:o.select_set(True)
 bpy.context.view_layer.objects.active=wet[0];bpy.ops.object.join();ob=bpy.context.object;ob.name='NoCollisionWater';bpy.ops.export_scene.gltf(filepath=str(dest/'water.glb'),export_format='GLB',use_selection=True,export_apply=True,export_yup=True);bpy.data.objects.remove(ob,do_unlink=True)
 bpy.ops.object.select_all(action='SELECT');meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];bpy.context.view_layer.objects.active=meshes[0];bpy.ops.object.join();obj=bpy.context.object;obj.name='Suite_'+rid.replace('-','_')
 bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');obj.data.calc_loop_triangles()
 out=dest/'suite.glb';bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',export_apply=True,export_yup=True,export_image_format='AUTO')
 bpy.ops.wm.save_as_mainfile(filepath=str(dest/'suite.blend'))
 meta=dict(id=rid,path=str(out),water_path=str(dest/'water.glb'),sha256=hashlib.sha256(out.read_bytes()).hexdigest(),triangles=len(obj.data.loop_triangles),materials=len(obj.data.materials),
  lights=[dict(local=list(p),color=list(c),lumens=l,radius=r) for (p,c,l,r) in info['lights']],views=info['views'],decorA_local=info['decorA'],decorB_local=info['decorB'],route_blockers=blockers,
  furniture=furniture)
 (dest/'build.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),'utf8');results.append(meta);print('SAMPLE',rid,meta['triangles'],'blockers',blockers,flush=True)
prev=json.loads((S/'sample-build.json').read_text('utf8'))['rooms'] if (S/'sample-build.json').exists() else []
keep={r['id']:r for r in prev};keep.update({r['id']:r for r in results})
(S/'sample-build.json').write_text(json.dumps(dict(status='authored_requires_native_import',rooms=list(keep.values())),ensure_ascii=False,indent=2),'utf8')
]====]
local path=out..'/sample-rooms/build-payload.json';local f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code,only=arg[1]}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..out..'/sample-rooms/build.log" 2>&1"'))
print('Sample rooms authored')
