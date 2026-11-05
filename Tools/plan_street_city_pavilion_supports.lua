-- Inspect actual source triangles for gaps between pavilion posts and sloped roofs.
local code=[====[
import json,struct,hashlib
from pathlib import Path
from collections import defaultdict
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');S=B/'traffic-v1/surface-current';O=B/'immersion-v1';scene=json.loads((S/'scene.json').read_text('utf8'));current=json.loads((O/'preservation-after.json').read_text('utf8'));lookup={(r['actor'],r['component']):r for r in current['components']};rows=[];skipped=[]
for r in scene['instances']:
 if not r['actor'].startswith('World_PK_'):continue
 wood=[i for i,p in enumerate(r['materials']) if 'Outdoor_wood.' in p];roof=[i for i,p in enumerate(r['materials']) if 'Outdoor_roof.' in p]
 if not wood or not roof:continue
 m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);local=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);v=(np.c_[local,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);parent={}
 def find(a):
  parent.setdefault(a,a)
  while parent[a]!=a:parent[a]=parent[parent[a]];a=parent[a]
  return a
 keys=[tuple(np.rint(p*2).astype(int)) for p in v]
 for t,s in zip(tri,slots):
  if s not in wood:continue
  a,b,c=[keys[i] for i in t];ra=find(a)
  for k in [b,c]:parent[find(k)]=ra
 groups=defaultdict(list)
 for t,s in zip(tri,slots):
  if s in wood:groups[find(keys[t[0]])].extend(t)
 pillars=[]
 for vi in groups.values():
  xyz=v[np.unique(vi)];lo=xyz.min(axis=0);hi=xyz.max(axis=0);size=hi-lo
  if 200<size[2]<500 and max(size[:2])<45:pillars.append(dict(min_cm=lo.tolist(),max_cm=hi.tolist(),center_cm=((lo+hi)/2).tolist()))
 if not pillars:continue
 rt=v[tri[np.isin(slots,roof)]]
 def height(x,y):
  hits=[]
  for a,b,c in rt:
   mat=np.array([[b[0]-a[0],c[0]-a[0]],[b[1]-a[1],c[1]-a[1]]]);det=np.linalg.det(mat)
   if abs(det)<.001:continue
   u,w=np.linalg.solve(mat,np.array([x-a[0],y-a[1]]))
   if u>=-.00001 and w>=-.00001 and u+w<=1.00001:hits.append(float(a[2]+u*(b[2]-a[2])+w*(c[2]-a[2])))
  return min(hits) if hits else None
 for p in pillars:
  x,y=p['center_cm'][:2];p['roof_underside_cm']=height(x,y);p['gap_cm']=p['roof_underside_cm']-p['max_cm'][2] if p['roof_underside_cm'] else None
 unrelated_posts=[p for p in pillars if p['roof_underside_cm'] is None];pillars=[p for p in pillars if p['roof_underside_cm'] is not None]
 now=lookup[(r['actor'],r['component'])];oldmatrix=np.array(r['matrix']).reshape(4,4);delta=np.array(now['transform']['translation'])-oldmatrix[3,:3];assert np.max(np.abs(delta[:2]))<.02;row=dict(actor=r['actor'],component=r['component'],source_mesh=m['asset'],current_mesh=now['mesh'],delta_cm=delta.tolist(),material=r['materials'][wood[0]],pillars=pillars,unrelated_posts_retained=unrelated_posts)
 if len(pillars)==4 and all(p['gap_cm'] is not None and 2<p['gap_cm']<80 for p in pillars):
  xs=sorted(set(round(p['center_cm'][0],3) for p in pillars));ys=sorted(set(round(p['center_cm'][1],3) for p in pillars));assert len(xs)==len(ys)==2;corners=[height(p['center_cm'][0]+dx,p['center_cm'][1]+dy) for p in pillars for dx in [-10,10] for dy in [-10,10]];assert all(z is not None for z in corners);header_top=min(corners)+5;header_bottom=header_top-24;boxes=[]
  for p in pillars:
   bottom=p['max_cm'][2]-.8;top=header_top-1;assert top>bottom;boxes.append(dict(center=[p['center_cm'][0],p['center_cm'][1],(bottom+top)/2],size=[p['max_cm'][0]-p['min_cm'][0],p['max_cm'][1]-p['min_cm'][1],top-bottom],kind='post-extension'))
  for y in ys:boxes.append(dict(center=[sum(xs)/2,y,(header_top+header_bottom)/2],size=[xs[1]-xs[0]+20,20,24],kind='header'))
  for x in xs:boxes.append(dict(center=[x,sum(ys)/2,(header_top+header_bottom)/2],size=[20,ys[1]-ys[0]-20,24],kind='header'))
  for b in boxes:b['center']=(np.array(b['center'])+delta).tolist()
  row.update(boxes=boxes,header_top_source_cm=header_top,status='prepared_requires_native_install');rows.append(row)
 else:row['status']='other_geometry_requires_review';skipped.append(row)
plan=dict(status='prepared_requires_native_install',map_sha256=current['map_sha256'],rows=rows,other_geometry=skipped,policy='Confirmed sloped-roof gaps only. Add four post extensions and nonoverlapping perimeter timber headers per four-post pavilion; retain original roof/posts/benches/material appearance, ensure >3m headroom and no coplanar beam corners.');(O/'pavilion-support-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Pavilions with measured post-to-roof gaps:',len(rows),'other candidates:',len(skipped))
for r in rows:print(r['actor'],[round(p['gap_cm'],2) for p in r['pillars']])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
