package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local out='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local f=assert(io.open('Tools/build_street_city_motel_suites.lua','rb'));local s=f:read('*a');f:close()
local helper=assert(s:match('local code=%[====%[(.-)%]====%]')):match('^(.-)\nfor index,q in enumerate')
local code=helper..[====[
# Architecture uses explicit section meshes; avoiding per-object operators keeps
# repair iterations bounded without changing metric dimensions or PBR scale.
def box(name,p,size,mat,bevel=0):
 x,y,z=[v/2 for v in size];v=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)];f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)];m=bpy.data.meshes.new(name);m.from_pydata(v,[],f);m.materials.append(mat);o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);o.location=p;return o
def cylinder(name,p,r,h,mat,r2=None,n=24):
 r2=r if r2 is None else r2;v=[(rr*math.cos(k*math.tau/n),rr*math.sin(k*math.tau/n),z) for rr,z in [(r,-h/2),(r2,h/2)] for k in range(n)];f=[tuple(reversed(range(n))),tuple(range(n,n*2))]+[(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)];m=bpy.data.meshes.new(name);m.from_pydata(v,[],f);m.materials.append(mat);o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o);o.location=p
 for face in m.polygons:face.use_smooth=len(face.vertices)==4
 return o
def slope(name,x0,x1,y,width,z0,z1,mat):
 v=[(x0,y-width/2,z0),(x1,y-width/2,z1),(x1,y+width/2,z1),(x0,y+width/2,z0)];v += [(x,y,z-.22) for x,y,z in v];faces=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
 if x1<x0:faces=[f[::-1] for f in faces]
 m=bpy.data.meshes.new(name);m.from_pydata(v,[],faces);m.materials.append(mat);o=bpy.data.objects.new(name,m);bpy.context.collection.objects.link(o)

def steps(x,y,z0,z1,metal,stone):
 rise=z1-z0;n=math.ceil(rise/.17);half=math.ceil(n/2);r=rise/n;t=.30
 # Two flights separated laterally, a broad intermediate landing.
 for k in range(half):box('Stair ascending tread',(x-1.2,y+k*t,z0+(k+.5)*r),(2.,t,r),stone)
 mid=z0+half*r;box('Stair mid landing',(x,y+half*t+.65,mid-.11),(4.5,1.6,.22),stone)
 for k in range(n-half):box('Stair return tread',(x+1.2,y+(n-half-1-k)*t,mid+(k+.5)*r),(2.,t,r),stone)
 # Continuous inclined stringers support the treads and preserve head clearance
 # under every stacked flight; a solid block would close the lower stairwell.
 for centerx,count,base,ascending in [(x-1.2,half,z0,True),(x+1.2,n-half,mid,False)]:
  run=count*t;rr=count*r;angle=math.atan2(rr,run)*(1 if ascending else -1)
  for dx in [-.76,.76]:
   ob=box('Continuous stair stringer',(centerx+dx,y+(count-1)*t/2,base+rr/2-.18),(.14,math.hypot(run,rr),.24),metal);ob.rotation_euler.x=angle
 for sign in [-1,1]:
  xx=x+sign*2.24;tube('Stair continuous handrail',[(xx,y,z0+1),(xx,y+half*t,mid+1)],.035,metal)
 for k in range(half+1):cylinder('Stair baluster',(x-2.24,y+k*t,z0+k*r+.50),.022,1.,metal,n=12)

results=[]
for bid in ['H1','S18']:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 stone=material('Motel_Stone',(.32,.29,.24),.65);wall=material('Motel_Wall',(.59,.53,.44),.7);wood=material('Motel_Wood',(.14,.075,.035),.45);metal=material('Motel_Gold',(.34,.22,.09),.3,.8);dark=material('Motel_Dark',(.025,.035,.045),.4);light=material('Motel_Light',(1,.72,.4),.5,emit=2);ivory=material('Motel_Ivory',(.72,.68,.58),.65)
 levels=[0,5,9.6,14,18.3] if bid=='H1' else [0,4.4,8.8]
 w,d=(126,54) if bid=='H1' else (32,40)
 # Ground slab is supported directly at the existing level, not a floating podium.
 if bid=='H1':box('Ground foundation',(0,0,-.12),(w,d,.24),stone)
 else:
  for xx in [-11.8,11.8]:box('Ground side foundation',(xx,0,-.12),(8.4,40,.24),stone)
  box('Ground front foundation',(0,-12.2,-.12),(15.2,15.6,.24),stone);box('Ground rear foundation',(0,18.2,-.12),(15.2,3.6,.24),stone)
 if bid=='H1':
  # Upper central driveways stop exactly at the suite thresholds at y=+-4.
  for z in levels[1:]:
   box('Central vehicle gallery',(0,0,z-.12),(126,8,.24),stone)
   box('East circulation link',(66.5,0,z-.12),(7,8,.24),stone)
   for y in [-2.7,2.7]:box('Walkable gallery edge',(0,y,z+.006),(123,.10,.012),ivory)
  # Ground reception with an actual doorway, lounge, counter and service wall.
  box('Reception back wall',(-20,20,2.2),(65,.24,4.4),wall)
  for xx in [-52.4,12.4]:box('Reception side wall',(xx,8,2.2),(.24,24,4.4),wall)
  for xx,ww in [(-42,20),(-4,31)]:box('Reception front pier',(xx,-4,2.2),(ww,.24,4.4),wall)
  box('Reception entry lintel',(-27,-4,3.7),(8,.24,1.4),wood)
  box('Reception desk',(-23,15,.60),(9,1.5,1.2),wood,.08);box('Reception desk stone',(-23,15,1.23),(9.2,1.7,.12),stone,.04)
  # Accessible ground-floor public WC, with a1.3m entrance and turning space.
  porcelain=material('Motel_Porcelain',(.86,.88,.88),.16)
  for xx in [1.8,8.2]:box('Reception accessible WC side',(xx,16.5,1.7),(.16,6.8,3.4),wall)
  for xx,ww in [(3.0,2.4),(7.0,2.4)]:box('Reception WC entrance jamb',(xx,13.1,1.7),(ww,.16,3.4),wall)
  box('Reception WC entry lintel',(5,13.1,2.95),(1.3,.16,.9),wall)
  ellipsoid('Accessible WC bowl',(3,18.7,.40),(.52,.72,.50),porcelain);box('Accessible WC cistern',(3,19.3,.65),(.5,.25,.6),porcelain,.05)
  tube('Accessible side grab bar',[(2.1,18.3,.85),(2.1,19.2,.85)],.025,metal)
  box('Reception accessible vanity',(6.3,19.15,.87),(1.8,.75,.12),stone,.02);basin((6.3,19.15,.94),porcelain,metal);box('Reception WC mirror backing',(6.3,19.80,1.65),(1.85,.10,1.2),wood);frame('Reception WC mirror frame',(6.3,19.73,1.65),1.8,1.15,metal)
  for x in [-43,-36,-7,0]:sofa((x,10,0),ivory,wood,True);cylinder('Reception coffee table',(x,7.8,.45),.75,.12,stone)
  # Broad east feeder connects the switchback ramps with each central driveway.
  for z in levels:
   box('Ramp east landing',(58,39.5,z-.11),(8,17,.22),stone)
   if z:
    box('Vehicle east feeder',(66,25,z-.11),(8,42,.22),stone)
   else:
    box('Ground feeder alongside foundation',(66.5,15.5,-.11),(7,23,.22),stone);box('Ground feeder beyond foundation',(66,36.5,-.11),(8,19,.22),stone)
   for y in [4,18,32,45]:box('East feeder light strip',(69.8,y,z+.85),(.04,1.4,.12),light)
  for lo,hi in zip(levels,levels[1:]):
   mid=(lo+hi)/2;slope('Ramp outward flight',54,-54,34,6,lo,mid,stone);slope('Ramp return flight',-54,54,45,6,mid,hi,stone);box('Ramp west turning landing',(-58,39.5,mid-.11),(8,17,.22),stone)
   for yy,zs,ze in [(30.9,lo,mid),(37.1,lo,mid),(41.9,mid,hi),(48.1,mid,hi)]:
    x0,x1=(54,-54) if yy<40 else (-54,54);tube('Vehicle guard rail',[(x0,yy,zs+1),(x1,yy,ze+1)],.045,metal)
    for k in range(28):t=k/27;cylinder('Vehicle guard post',(x0+(x1-x0)*t,yy,zs+(ze-zs)*t+.5),.035,1,metal,n=12)
  # Ground vehicle approach from south/east, preserving the existing road.
  box('Ground vehicle approach',(66.5,-12,-.11),(7,24,.22),stone)
  # Separate pedestrian emergency stairs and protected floor landings.
  for lo,hi in zip(levels,levels[1:]):steps(68,-19,lo,hi,metal,stone)
  for z in levels:
   box('Stair arrival landing',(67.55,-20,z-.11),(6.9,2.2,.22),stone);box('Stair gallery connection',(63 if z else 63.55,-11.45,z-.11),(2.2 if z else 1.1,15.1,.22),stone)
  # Slender elevation fins, deep cornices, roof pergolas and a sheltered entry.
  for x in [-61.5+i*15.2 for i in range(9)]:
   for y in [-25.3,25.3]:box('Facade vertical bronze fin',(x,y,11.3),(.20,.55,22.6),metal)
  for z in [5,9.6,14,18.3,22.5]:
   for y in [-25.5,25.5]:box('Facade deep cornice',(0,y,z),(125,.70,.22),ivory)
  box('Supported central roof bridge',(0,0,22.3),(126,8,.20),stone)
  for x in [-47,-16,16,47]:
   for xx in [-4,4]:
    for yy in [-3,3]:box('Roof pavilion column',(x+xx,yy,23.4),(.18,.18,2),metal)
   for k in range(15):box('Roof pergola slat',(x-4.2+k*.6,0,24.5),(.18,7,.16),wood)
  box('Reception weather canopy',(-27,-25.5,4.5),(20,3,.3),wood)
  for xx in [-60.8+i*15.2 for i in range(9)]:
   for yy in [-23.9,23.9]:box('Ground reinforced structural pier',(xx,yy,2.17),(.65,.65,4.34),stone)
  for yy in [-23.9,23.9]:box('Ground perimeter structural beam',(0,yy,4.55),(126,.75,.42),stone)
 else:
  # Three ground parking bays; the guest suites are accessed on foot.
  for x in [-10,0,10]:
   for xx in [-3.1,3.1]:box('Assigned garage jamb',(x+xx,-14,1.5),(.18,8,3),wall)
   box('Assigned garage canopy',(x,-14,3.1),(6.4,8,.20),wood)
   for xx in [-2.5,2.5]:box('Parking painted edge',(x+xx,-14,.006),(.07,6,.012),ivory)
   box('Parking wheel stop',(x,-10.5,.08),(2.4,.20,.16),dark,.02)
  for z in levels[1:]:box('Pedestrian front gallery',(0,-5.65,z-.12),(30,2.5,.24),stone);box('Stair arrival threshold',(11.2,-4.3,z-.12),(4.6,.6,.24),stone)
  for lo,hi in zip(levels,levels[1:]):steps(11.2,-4,lo,hi,metal,stone)
  for x in [-13,13]:
   for y in [-6,18]:box('Garden lodge facade pier',(x,y,6.6),(.32,.32,13.2),wood)
  # Pitched roof, not a generic flat slab.
  for sign in [-1,1]:
   ob=box('Pitched pavilion roof',(sign*4.0,6,13.4),(9.2,23,.20),dark);ob.rotation_euler.y=sign*.18
  box('Ridge cap',(0,6,14.18),(.28,24,.22),metal)
 # Deep framed privacy glazing on each individual suite's exterior rear wall.
 for q in [r for r in plan['rooms'] if r['building']==bid]:
  cx,cy,cz=q['local_center_m'];a=math.radians(q['yaw']);normal=-1 if q['yaw']==180 else 1
  for dx in [-q['size_m'][0]*.24,q['size_m'][0]*.24]:
   x=cx+dx*math.cos(a);y=cy+10.54*math.cos(a);z=cz+2.05;box('Frosted privacy window',(x,y,z),(2.6,.08,1.3),dark,.025)
   for xx in [-1.38,1.38]:box('Deep window side reveal',(x+xx,y-normal*.06,z),(.14,.28,1.6),wood,.015)
   for zz in [-.76,.76]:box('Deep window horizontal reveal',(x,y-normal*.06,z+zz),(2.9,.28,.14),wood,.015)
 # Join and export metric zero-pivot architecture.
 for o in list(bpy.context.scene.objects):
  bpy.context.view_layer.objects.active=o;o.select_set(True)
  if o.type=='CURVE':bpy.ops.object.convert(target='MESH')
  o.select_set(False)
 bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.ops.object.join();ob=bpy.context.object;bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');ob.name=bid+'_MotelArchitecture';bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
 uv=ob.data.uv_layers.new(name='MetricPlanar')
 for face in ob.data.polygons:
  axis=max(range(3),key=lambda i:abs(face.normal[i]));axes=[i for i in range(3) if i!=axis]
  for li in face.loop_indices:
   p=ob.data.vertices[ob.data.loops[li].vertex_index].co;uv.data[li].uv=(p[axes[0]]/2,p[axes[1]]/2)
 ob.data.calc_loop_triangles();path=O/'models'/(bid+'-architecture.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',export_yup=True,export_apply=True)
 results.append(dict(building=bid,path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),triangles=len(ob.data.loop_triangles)))
(O/'architecture-build.json').write_text(json.dumps(dict(status='authored_requires_native_integration_and_clearance_review',assets=results),indent=2),'utf8')
]====]
local path=out..'/architecture-build-payload.json';f=assert(io.open(path,'wb'));f:write(j.encode({out=out,code=code}));f:close()
local expr="import json;TASK=json.load(open('"..path.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expr..'" > "'..out..'/architecture-build.log" 2>&1"'))
