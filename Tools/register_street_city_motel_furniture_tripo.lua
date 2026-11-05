-- Register the remeshed motel furniture (motel-furniture-tripo-v2/remeshed.json) in the room builder's furniture registry
-- (motel-v1/sample-rooms/furniture/receipts.json, contract: bottom-centre origin, front facing -Y).
-- Tripo Batch Export turns models 90 degrees against the single-export pieces, so each model is re-oriented:
--   long horizontal axis -> X when the plan box is wider than deep; front -> -Y by the back-rest rule (seating: the top
--   15 % of vertices sit at the back) or, for other pieces, the detailed side (more vertices) is the front.
-- Writes oriented/<id>.glb plus a front render oriented/<id>.png and a contact sheet oriented/sheet.png for review;
-- overrides.json {key: extra_rotation_deg} corrects a model the rule got wrong (applied after the rule).
-- Usage: lua Tools/register_street_city_motel_furniture_tripo.lua
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/'..(os.getenv('OK_TRIPO_SET') or 'motel-furniture-tripo-v2')
local reg='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1/sample-rooms/furniture/receipts.json'
local blender='C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return j.decode(s)end
local function write(p,v)local f=assert(io.open(p,'wb'));f:write(j.encode(v));f:close()end
local code=[====[
import bpy,json,math,hashlib,sys
from pathlib import Path
from mathutils import Vector
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production')/__import__('os').environ.get('OK_TRIPO_SET','motel-furniture-tripo-v2');D=O/'oriented';D.mkdir(exist_ok=True)
plan={r['index']:r for r in json.loads((O/'plan.json').read_text('utf8'))['items']}
# Source mesh per model: the instant-meshes-rs result only when it has fewer triangles than the prepared (Blender-decimated)
# mesh; otherwise the prepared mesh (user 2026-10-27: a remesh that does not reduce triangles is not used).
remd={r['id']:r for r in (json.loads((O/'remeshed.json').read_text('utf8'))['assets'] if (O/'remeshed.json').exists() else []) if r['status']=='passed'}
# Per model, the smaller of remesh and prepared (user 2026-10-27). The 90 % rule only decides whether a set keeps being
# remeshed at all (furniture sets: no more remesh runs); finished remeshes that did cut triangles are still used.
prep=json.loads((O/'prepared.json').read_text('utf8'))['assets']
pairs=[(remd[a['id']]['triangles'],a['triangles']) for a in prep if a['id'] in remd]
print('REMESH POLICY',O.name,'%d/%d remeshes not smaller'%(sum(1 for r,p in pairs if r>=p),len(pairs)),flush=True)
rem=[]
for a in prep:
 x=remd.get(a['id'])
 if x and x['triangles']<a['triangles']:rem.append(dict(x,source_choice='remesh'))
 else:rem.append(dict(id=a['id'],index=a['index'],path=a['path'],triangles=a['triangles'],rung='prepared',source_choice='prepared'+('' if not x else ' (remesh %d >= %d)'%(x['triangles'],a['triangles']))))
ov=json.loads((O/'overrides.json').read_text('utf8')) if (O/'overrides.json').exists() else {}
def category(k):
 if any(w in k for w in ('chandelier','ceiling_fan')):return 'ceiling'
 if 'mirror' in k and 'cabinet' not in k and 'coffee' not in k:return 'wall'
 if any(w in k for w in ('sofa','loveseat','chesterfield','chaise')):return 'sofa'
 if 'chair' in k or 'stools' in k:return 'chair'
 if any(w in k for w in ('coffee_table','low_table')):return 'table'
 if 'lamp' in k:return 'lamp'
 return 'floor'
rows=[]
for r in rem:
 p=plan[r['index']];key=p['key'];cat=category(key)
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=r['path'])
 ms=[a for a in bpy.context.scene.objects if a.type=='MESH']
 for a in list(bpy.context.scene.objects):
  if a.type!='MESH':bpy.data.objects.remove(a,do_unlink=True)
 bpy.ops.object.select_all(action='DESELECT')
 for a in ms:a.select_set(True)
 bpy.context.view_layer.objects.active=ms[0];bpy.ops.object.join();ob=bpy.context.object;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
 def dims():
  vs=[v.co for v in ob.data.vertices];lo=Vector([min(v[k] for v in vs) for k in range(3)]);hi=Vector([max(v[k] for v in vs) for k in range(3)]);return lo,hi
 def rot(deg):
  a=math.radians(deg);c,s=math.cos(a),math.sin(a)
  for v in ob.data.vertices:x,y=v.co.x,v.co.y;v.co.x=x*c-y*s;v.co.y=x*s+y*c
 lo,hi=dims();turn=0
 w,d,_=p['size_m']
 if w>d*1.15 and (hi.y-lo.y)>(hi.x-lo.x)*1.15:rot(90);turn+=90
 if cat=='wall' and (hi.x-lo.x)<(hi.y-lo.y)*.6:rot(90);turn+=90   # thin mirror: make its face span X
 lo,hi=dims();cy=(lo.y+hi.y)/2
 ex=ov.get(key,{});ex={'rz':ex} if not isinstance(ex,dict) else ex
 cat=ex.get('category',cat)  # e.g. a "chandelier" that Tripo built as a standing candelabra on a pedestal
 if ex.get('rx'):
  # model lies on its side (e.g. a ceiling fan exported with vertical blades): stand it up first
  a=math.radians(ex['rx']);c,s=math.cos(a),math.sin(a)
  for v in ob.data.vertices:y,z=v.co.y,v.co.z;v.co.y=y*c-z*s;v.co.z=y*s+z*c
  lo,hi=dims();cy=(lo.y+hi.y)/2
 if ex.get('ry'):
  a=math.radians(ex['ry']);c,s=math.cos(a),math.sin(a)
  for v in ob.data.vertices:x,z=v.co.x,v.co.z;v.co.x=x*c+z*s;v.co.z=-x*s+z*c
  lo,hi=dims();cy=(lo.y+hi.y)/2
 if cat in('sofa','chair'):
  # back rest = top 15 % of vertices; turn so it points +Y (front -Y). Uses both axes: square chairs have no long axis.
  zs=sorted(v.co.z for v in ob.data.vertices);zc=zs[int(len(zs)*.85)];top=[v.co for v in ob.data.vertices if v.co.z>=zc]
  cx=(lo.x+hi.x)/2;bx=sum(p.x for p in top)/len(top)-cx;by=sum(p.y for p in top)/len(top)-cy;rule='back-rest top vertices at (%+.3f, %+.3f) m'%(bx,by)
  # X only for chairs, or a sofa still lying long-side along Y (a chaise's raised end lies along its long X axis)
  if (cat=='chair' or (hi.x-lo.x)<(hi.y-lo.y)) and abs(bx)>abs(by)*1.2 and abs(bx)>.03:t=-90 if bx<0 else 90
  else:t=180 if by<0 else 0
  if t:rot(t);turn+=t
 elif cat in('floor','wall') and w>d*1.15:
  ys=[v.co.y-cy for v in ob.data.vertices];front=sum(1 for y in ys if y<0)-sum(1 for y in ys if y>0);rule='vertex balance %+d (front = more detail)'%front
  if front<0:rot(180);turn+=180
 else:rule='symmetric piece, no front rule'
 extra=ex.get('rz',0)
 if extra:rot(extra);turn+=extra
 lo,hi=dims();c=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 # scale: a model prepared lying down was fitted to the plan box with the wrong axis as height
 for v in ob.data.vertices:v.co=(v.co-c)*ex.get('scale',1.)
 ob.data.update();lo,hi=dims();size=list(hi-lo)
 out=D/(r['id']+'.glb');bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=False,export_yup=True)
 # front render (camera on -Y looking +Y), workbench with texture colours
 sc=bpy.context.scene;sc.render.engine='BLENDER_WORKBENCH';sc.display.shading.color_type='TEXTURE';sc.display.shading.light='STUDIO'
 sc.render.resolution_x=sc.render.resolution_y=320;sc.render.film_transparent=False
 cam=bpy.data.objects.new('cam',bpy.data.cameras.new('cam'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=max(size)*1.15
 cam.location=(0,-10,size[2]/2);cam.rotation_euler=(math.pi/2,0,0)
 sc.render.filepath=str(D/(r['id']+'.png'));bpy.ops.render.render(write_still=True)
 rows.append(dict(key=key,status='passed',category=cat,path=str(out),sha256=hashlib.sha256(out.read_bytes()).hexdigest(),h=size[2],size_m=size,turn_deg=turn%360,rule=rule,override_deg=extra,
  triangles=r['triangles'],rung=r['rung'],source_choice=r['source_choice'],mesh_source=r['path'],tripo_set=O.name,index=r['index'],rooms=p['rooms']))
 print('ORIENT',key,cat,turn%360,rule,flush=True)
(D/'oriented.json').write_text(json.dumps(rows,ensure_ascii=False,indent=1),'utf8')
# contact sheet: 8 per row, label = index
imgs=[(x['index'],bpy.data.images.load(str(D/(next(a['id'] for a in rem if a['index']==x['index'])+'.png')))) for x in rows]
cols=8;W=320;rws=(len(imgs)+cols-1)//cols;sheet=bpy.data.images.new('sheet',cols*W,rws*W);px=[0.]*(cols*W*rws*W*4)
for n,(idx,im) in enumerate(imgs):
 src=list(im.pixels);cx,cy=(n%cols)*W,(rws-1-n//cols)*W
 for yy in range(W):
  row=src[yy*W*4:(yy+1)*W*4];base=((cy+yy)*cols*W+cx)*4;px[base:base+W*4]=row
sheet.pixels[:]=px;sheet.filepath_raw=str(D/'sheet.png');sheet.file_format='PNG';sheet.save()
print('ORIENT DONE',len(rows))
]====]
os.execute('if not exist "'..(o..'/oriented'):gsub('/','\\')..'" mkdir "'..(o..'/oriented'):gsub('/','\\')..'"')
local cp=o..'/oriented/register-code.py';local f=assert(io.open(cp,'wb'));f:write(code);f:close()
assert(os.execute('""'..blender..'" --background --factory-startup --python "'..cp..'" > "'..o..'/oriented/register.log" 2>&1"'))
local rows=read(o..'/oriented/oriented.json');assert(rows and #rows>0,'orientation produced nothing; see oriented/register.log')
-- merge into the shared registry: replace this set's keys, keep everything else
local all=read(reg) or {};local keep={};local mine={};for _,r in ipairs(rows)do mine[r.key]=true end
for _,r in ipairs(all)do if not mine[r.key] then keep[#keep+1]=r end end
for _,r in ipairs(rows)do keep[#keep+1]=r end
local bak=reg:gsub('%.json$','.before-furniture-v2.json');local b=io.open(bak,'rb');if b then b:close() else write(bak,all) end
write(reg,keep);print('Registered '..#rows..' furniture-v2 models into '..reg..' ('..#keep..' total)')
