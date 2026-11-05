-- Metric geometry, elevation planning and typesetting; no raster scene editing.
local code=[====[
import json,struct,hashlib,re,math
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path('C:/portable/OpenKoikatsu');BASE=ROOT/'output/street-social-city-production';OUT=BASE/'flat-campus-v1';SRC=BASE/'day-night-v1/surface-final'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(n,d):(OUT/(n+'.json')).write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf8')
inventory=read(OUT/'inventory.json');scene=read(SRC/'scene.json');components=inventory['components'];actors={a['label']:a for a in inventory['actors']};live={(r['actor'],r['component']):r for r in components}
archive=np.load(BASE/'world-ground-v1/world-field.npz');field=archive['height_map'];water=archive['water_map']
def height(x,y):
 # Unreal axes: X north, Y east; source height raster is row south, column east.
 x,y=np.clip(np.asarray(y)/100,0,1100),np.clip(1100-np.asarray(x)/100,0,1100);i=x.astype(int);j=y.astype(int);u=x-i;v=y-j
 return 100*((1-u)*(1-v)*field[j,i]+u*(1-v)*field[j,np.minimum(i+1,1100)]+(1-u)*v*field[np.minimum(j+1,1100),i]+u*v*field[np.minimum(j+1,1100),np.minimum(i+1,1100)])
buildings={}
for label,a in actors.items():
 if label.startswith('RomanceArch_'):
  bid=label.split('_')[1];buildings[bid]=a['xform']['location'][2]
def label_base(label):
 for pat in [r'^(?:Campus|City|Mall|RomanceArch|RomanceName)_([A-Z0-9]+)(?:_|$)',r'^CampusSign_([A-Z0-9]+)-',r'^ResortLantern_([A-Z0-9]+)_']:
  m=re.match(pat,label)
  if m and m[1] in buildings:return buildings[m[1]]
 if label.startswith('Activity_ACTSPACE-08-'):return 2000.
 if label.startswith('Activity_ACTSPACE-01-'):return 1200.
 if label.startswith(('Activity_ACTSPACE-02-','Activity_ACTSPACE-07-')):return 2000.
 if label in ('Outdoor_stadium','Outdoor_annex_ground'):return 1200.
 return None
meshes=[];surface_keys=set();folder=OUT/'vertices';folder.mkdir(exist_ok=True)
for r in scene['instances']:
 label=r['actor'];key=(label,r['component']);current=live.get(key)
 if not current or r['instance']!=-1:continue
 isground=bool(re.fullmatch(r'G\d\d',label));iswater=bool(re.fullmatch(r'G\d\d_Water',label));isroad=label.startswith(('DepthStableStreet_','DepthStableTactile_'));islink=label in ('Outdoor_campus_links','Outdoor_connection','Outdoor_annex_ground','Outdoor_campus_track_access')
 if not (isground or iswater or isroad or islink):continue
 asset=scene['meshes'][r['mesh']];assert current['mesh']==asset['asset'];mat=np.array(r['matrix']).reshape(4,4);inv=np.linalg.inv(mat);lods=[];stats=[]
 for l in asset['lods']:
  raw=(SRC/l['file']).read_bytes();magic,nv,nt=struct.unpack_from('<III',raw);assert magic==0x43445932
  xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();world=np.c_[xyz,np.ones(nv)]@mat;oldz=world[:,2].copy();base=height(world[:,0],world[:,1])
  if iswater:newz=np.full(nv,1100.)
  elif isroad:
   # Each repaired street source is a level 12m or 20m slab. Keep its finite thickness and tactile offset.
   datum=round(float(np.median(oldz))/100)*100;newz=oldz-datum+1200
  elif label=='Outdoor_annex_ground':newz=np.where(oldz>100,oldz,oldz)+0
  elif islink:
   if label=='Outdoor_connection':
    # The old sloping deck has paired top/bottom vertices at each XY.
    xy=np.round(world[:,:2],2);_,inverse=np.unique(xy,axis=0,return_inverse=True);tops=np.full(inverse.max()+1,-np.inf);np.maximum.at(tops,inverse,oldz);newz=1200+oldz-tops[inverse]
   else:newz=oldz-800
  else:
   residual=oldz-base
   # Preserve foundation excavations; remove authored hills and micro-relief from walking land.
   newz=1200+np.clip(residual,-250,-2)
   indices=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16)
   paving_slots=[i for i,m in enumerate(r['materials']) if 'asphalt' in m.lower() or 'Tripo-ground-urban' in m]
   pavement=np.unique(indices[np.isin(slots,paving_slots)])
   newz[pavement]=1200+np.clip(residual[pavement],-35,5)
   newz=np.where(oldz < -2900,-3000,newz)
   # The sea, river and pond keep a recessed bed below their common water level.
   wi=np.clip(np.rint(world[:,1]/100).astype(int),0,1100);wj=np.clip(np.rint(1100-world[:,0]/100).astype(int),0,1100)
   newz=np.where((water[wj,wi]>0)&(oldz>-2900),np.minimum(newz,1000),newz)
  world[:,2]=newz;new=(world@inv)[:,:3].astype('<f4');pairs=np.stack([xyz,new],axis=1);dest=folder/(str(asset['id'])+'-'+str(l['lod'])+'.bin');dest.write_bytes(pairs.tobytes());lods.append(dict(lod=l['lod'],vertices=str(dest),sha256=hashlib.sha256(dest.read_bytes()).hexdigest()));stats.append(dict(lod=l['lod'],vertices=nv,triangles=nt,before_z=[float(oldz.min()),float(oldz.max())],after_z=[float(newz.min()),float(newz.max())]))
 name='SM_Flat_'+hashlib.sha256((label+asset['asset']).encode()).hexdigest()[:18];meshes.append(dict(key=label+'::'+r['component'],before=asset['asset'],after='/Game/UniversityCity/FlatCampusV1/Meshes/'+name,lods=lods,statistics=stats,category='water' if iswater else 'terrain' if isground else 'path'));surface_keys.add(key)
changes=[]
for label,a in actors.items():
 own=[r for r in components if r['actor']==label]
 if not own and a['class_name'] not in ('PointLight','SpotLight','RectLight','TextRenderActor'):continue
 if all((label,r['component']) in surface_keys for r in own) and own:continue
 if label.startswith(('ResortMoon','CityEnvironment','Sun','Sky','DirectionalLight','Volumetric','Exponential')):continue
 base=label_base(label)
 regular=[r for r in own if 'instances' not in r and (label,r['component']) not in surface_keys]
 instanced=[r for r in own if 'instances' in r]
 if regular or not own:
  pos=a['xform']['location'];origin=a['origin'];x,y=pos[:2]
  if max(abs(x),abs(y))<1 and own:x,y=origin[:2]
  b=base if base is not None else float(height(x,y));delta=1200-b
  # Keep complete scenery as rigid assemblies. Building heights/floors remain unchanged.
  if abs(delta)>.005:changes.append(dict(kind='actor',actor=label,before=a['xform'],delta_z_cm=round(delta,6),reference_base_cm=round(b,6)))
 if instanced:
  for r in instanced:
   if (label,r['component']) in surface_keys:continue
   rows=[]
   for i,t in enumerate(r['instances']):
    x,y,z=t['translation'];b=base if base is not None else float(height(x,y));delta=1200-b
    if abs(delta)>.005:rows.append(dict(index=i,delta_z_cm=round(delta,6)))
   if rows:changes.append(dict(kind='instances',actor=label,component=r['component'],count=len(r['instances']),changes=rows))
gates=[dict(id='SouthMain',name='南門',center=[54800,57500],yaw=180,width=1200),dict(id='SouthWalk',name='學生活動門',center=[54800,40000],yaw=180,width=800),dict(id='WestSport',name='西門',center=[71500,19500],yaw=-90,width=1000),dict(id='NorthDorm',name='北門',center=[97000,59500],yaw=0,width=1000),dict(id='EastGarden',name='東門',center=[80000,77000],yaw=90,width=800)]
for q in gates:
 im=Image.new('RGB',(2048,320),(14,31,29));d=ImageDraw.Draw(im);font=ImageFont.truetype('C:/Windows/Fonts/msjhbd.ttc',205);text='影輝大學';bb=d.textbbox((0,0),text,font=font);d.text(((2048-bb[2]-bb[0])/2,(285-bb[3]-bb[1])/2),text,font=font,fill=(244,226,179));small=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',38);text=q['name']+'  |  YINGHUI UNIVERSITY';bb=d.textbbox((0,0),text,font=small);d.text(((2048-bb[2]-bb[0])/2,270),text,font=small,fill=(201,195,164));dest=OUT/('gate-'+q['id']+'.png');im.save(dest);q['texture']=str(dest)
save('plan',dict(status='prepared_requires_native_validation',map_sha256=inventory['map_sha256'],datum_cm=1200,water_cm=1100,meshes=meshes,changes=changes,campus_bounds_cm=[54800,19500,97000,77000],school_name='影輝大學',gates=gates,scope='Level walking land and roads; rigid building rebases; preserve floors and interiors. Water stays recessed.'))
print('Prepared',len(meshes),'surface meshes,',len(changes),'actor/component rebase groups and',len(gates),'named gates.')
]====]
local process=assert(io.popen('python -','w'));assert(process:write(code));assert(process:close())
