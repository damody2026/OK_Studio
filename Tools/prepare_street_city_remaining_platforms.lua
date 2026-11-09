-- Bounded original-vertex edits; all unrelated mesh sections remain unchanged.
local code=[====[
import json,struct,hashlib,math
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'immersion-v1';S=B/'traffic-v1/surface-current'
def read(p):return json.loads(p.read_text('utf-8-sig'))
probe=read(O/'outdoor-support-review.json');scene=read(S/'scene.json');plans=[];folder=O/'waterfront';folder.mkdir(exist_ok=True)
for pid in ['0101','0108']:
 p=probe['roots'][pid];g=read(O/('water-platform-'+pid+'-geometry.json'));r=next(q for q in scene['instances'] if q['actor']=='World_PK_'+pid);m=scene['meshes'][r['mesh']];assert m['asset']==p['source_mesh'] and len(m['lods'])==1
 raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();matrix=np.array(r['matrix']).reshape(4,4);world=np.c_[xyz,np.ones(nv)]@matrix;new=world.copy();parts={q['id']:q for q in g['paving_parts']};slab=0 if pid=='0101' else 1;ramp=21 if pid=='0101' else 0;oldtop=parts[slab]['max_cm'][2];delta=1206-oldtop;new[:,2]+=delta
 pierids=range(1,21) if pid=='0101' else range(2,22)
 for q in p['piers']:
  if q['part'] not in pierids:continue
  vi=np.array(parts[q['part']]['vertex_indices']);top=world[vi,2].max();feet=vi[world[vi,2]<top-.5];new[feet,2]=q['foundation_base_cm'];new[vi[world[vi,2]>=top-.5],2]=1202
 vi=np.array(parts[ramp]['vertex_indices']);xy=np.round(world[vi,:2],3);_,inverse=np.unique(xy,axis=0,return_inverse=True);tops=np.full(inverse.max()+1,-np.inf);np.maximum.at(tops,inverse,world[vi,2]);is_top=world[vi,2]>=tops[inverse]-.5
 if pid=='0101':
  # path-014 asphalt center X52750, width 1600 => edge53550. Keep 10cm clearance.
  oldx=world[vi,0];new[vi,0]=53560+(oldx-53300)/300*120;z=1198.5+(new[vi,0]-53560)/120*7.5;new[vi,2]=z-np.where(is_top,0,16)
  si=np.array(parts[slab]['vertex_indices']);front=si[np.isclose(world[si,0],53600,atol=.02)];assert len(front)>0;new[front,0]=53680
 else:new[vi,2]=np.where(is_top,1206,1190)
 # Existing repair includes an isolated horizontal 6cm surface cap; bury it inside slab.
 overlay=np.isclose(new[:,2],1212,atol=.02);new[overlay,2]=1202
 future=matrix.copy();future[3,2]+=delta;local=(new@np.linalg.inv(future))[:,:3].astype('<f4');path=folder/('PK'+pid+'-level-vertices.bin');path.write_bytes(np.stack([xyz,local],axis=1).tobytes());asset='/Game/UniversityCity/ImmersionV1/WaterDeck/SM_PK'+pid+'_LevelAccess_v2'
 actor=dict(p['actor_before']);actor['location']=[actor['location'][0],actor['location'][1],actor['location'][2]+delta]
 mesh=dict(key=r['key'],before=p['source_mesh'],after=asset,lods=[dict(lod=0,vertices=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())]);(O/('platform-'+pid+'-mesh-plan.json')).write_text(json.dumps(dict(map_sha256=probe['map_sha256'],meshes=[mesh]),indent=2),'utf8')
 plans.append(dict(id=pid,actor=r['actor'],actor_before=p['actor_before'],actor_after=actor,source_mesh=p['source_mesh'],asset=asset,old_top_cm=oldtop,new_top_cm=1206,piers=20,buried_cap_vertices=int(overlay.sum()),policy='Preserve all furniture/rail geometry and materials; finite slab, terrain-grounded piers, flatten legacy ramp; PK0101 ramp stays outside X53550 asphalt edge.'))
stone=[];metal=[]
def box(group,c,s):assert min(s)>0;group.append(dict(center=c,size=s))
# One finite slab meets the flattened original ramp at X26800 without an overlay.
box(stone,[26650,83750,1198],[300,1300,16])
def rail(a,b):
 dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);n=math.ceil(length/160)
 for i in range(n+1):
  t=i/n;x,y=a[0]+t*dx,a[1]+t*dy;box(metal,[x,y,1207],[14,14,2]);box(metal,[x,y,1260.5],[6,6,109])
 for z,thick in [(1241,2),(1271,2),(1301,2),(1315,6)]:box(metal,[(a[0]+b[0])/2,(a[1]+b[1])/2,z],[abs(dx)-6 if abs(dx)>1 else thick,abs(dy)-6 if abs(dy)>1 else thick,thick])
for a,b in [([26515,83100],[26515,84385]),([26515,84385],[26785,84385]),([26785,83100],[26785,84115]),([26785,84115],[27085,84115]),([26785,84385],[27085,84385])]:rail(a,b)
seen=set();metal=[q for q in metal if not ((tuple(q['center']),tuple(q['size'])) in seen or seen.add((tuple(q['center']),tuple(q['size']))))]
plan=dict(status='prepared_requires_native_preflight',map_sha256=probe['map_sha256'],platforms=plans,groups=dict(Stone=stone,Metal=metal),bridge_pier_xy_cm=[[x,y] for x in [26560,26740] for y in [83180,83650,84280]]+[[26980,84250]],walks={'0101':[[53580,70000],[53800,70000],[54400,70000],[54400,70600],[55000,70600]],'0108':[[26650,83000],[26650,83200],[26650,84250],[26950,84250],[27400,84250],[28000,84250],[28400,84250]]},policy='Player-height level access. New PK0108 L-boardwalk connects the west opening to the northern land bank; grounded piers and 112cm rails. No water or building rebases.')
(O/'remaining-platform-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared two bounded level-platform meshes;',len(metal),'rail solids; native pier support and walk checks required.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
