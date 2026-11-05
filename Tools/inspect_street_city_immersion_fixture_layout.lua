-- Read-only connected geometry context for observed field furniture and roof fixtures.
local code=[====[
import json,struct,collections
from pathlib import Path
import numpy as np
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');exp=json.loads((O/'depth-export.json').read_text());S=Path(exp['folder']);scene=json.loads((S/'scene.json').read_text());rows=[]
for r in scene['instances']:
 if r['actor'] not in ['Outdoor_campus_track','World_PK_0111']:continue
 m=scene['meshes'][r['mesh']];raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);v=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);w=(np.c_[v,np.ones(nv)]@np.array(r['matrix']).reshape(4,4))[:,:3];tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16)
 # Material seams keep a furniture foot that touches the paving from merging into the entire ground sheet.
 corners=tri.reshape(-1);keys=np.c_[np.round(w[corners],2),np.repeat(slots,3)];_,weld=np.unique(keys,axis=0,return_inverse=True);weld=weld.reshape(-1,3);parent=np.arange(int(weld.max())+1)
 def find(x):
  while parent[x]!=x:parent[x]=parent[parent[x]];x=int(parent[x])
  return x
 for a,b,c in weld:
  a=find(int(a));b=find(int(b));c=find(int(c));parent[b]=a;parent[c]=a
 groups=collections.defaultdict(list)
 for i,t in enumerate(tri):groups[find(int(weld[i,0]))].append(i)
 components=[]
 for indices in groups.values():
  ix=np.array(indices);vi=np.unique(tri[ix]);p=w[vi];lo=p.min(0);hi=p.max(0);components.append(dict(triangles=len(ix),vertices=len(vi),bounds_cm=[lo.tolist(),hi.tolist()],slots=[dict(slot=int(k),material=r['materials'][int(k)],triangles=int((slots[ix]==k).sum())) for k in sorted(set(slots[ix]))],triangle_indices=indices))
 row=dict(actor=r['actor'],mesh=m['asset'],components=components);rows.append(row);print(r['actor'],'components',len(components),'vertices',nv,'triangles',nt)
 for q in components:
  lo,hi=np.array(q['bounds_cm']);size=hi-lo
  if np.max(size)<1500 and (r['actor']=='World_PK_0111' or any('wood' in s['material'].lower() for s in q['slots'])):print(q['triangles'],np.round(lo,2).tolist(),np.round(hi,2).tolist(),[(s['slot'],s['material'].split('/')[-1]) for s in q['slots']])
result=dict(status='read_only_connected_geometry_context',map_sha256=exp['map_sha256'],source_metadata_sha256=exp['metadata_sha256'],rows=rows,scope='Geometry components welded by0.01cm position only for diagnosis. No asset, actor or collision mutation; candidate groups require semantic and native support review.')
(O/'fixture-layout-geometry.json').write_text(json.dumps(result,indent=2),'utf8')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
