-- Level the second lake deck inside the campus fence and join the two decks.
local code=[====[
import json,struct,hashlib,math
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'immersion-v1';S=B/'traffic-v1/surface-current'
def read(p):return json.loads(p.read_text('utf-8-sig'))
p=read(O/'water2-probes.json');g=read(O/'water-platform-0106-geometry.json');scene=read(S/'scene.json');r=next(q for q in scene['instances'] if q['actor']=='World_PK_0106');m=scene['meshes'][r['mesh']];assert m['asset']==p['source_mesh'] and len(m['lods'])==1
l=m['lods'][0];raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();matrix=np.array(r['matrix']).reshape(4,4);world=np.c_[xyz,np.ones(nv)]@matrix;new=world.copy();new[:,:3]+=np.array(p['delta_cm']);parts={q['id']:q for q in g['paving_parts']}
for q in p['pier_ground']:
 vi=np.array(parts[q['part']]['vertex_indices']);top=world[vi,2].max();feet=vi[world[vi,2]<top-.5];new[feet,2]=q['foundation_base_cm'];new[vi[world[vi,2]>=top-.5],2]=1202
vi=np.array(parts[21]['vertex_indices']);xy=np.round(world[vi,:2],3);_,inverse=np.unique(xy,axis=0,return_inverse=True);tops=np.full(inverse.max()+1,-np.inf);np.maximum.at(tops,inverse,world[vi,2]);new[vi,2]=np.where(world[vi,2]>=tops[inverse]-.5,1206,1190)
for part in g['paving_parts'][22:]:new[np.array(part['vertex_indices']),2]=1202
# The rebuilt render/collision data exposes a legacy 6cm overlay not belonging
# to the principal slab. Bury that exact horizontal level inside the finite
# slab instead of accepting a step or leaving two visible coplanar surfaces.
overlay=np.isclose(new[:,2],1212.,atol=.02);assert int(overlay.sum())==432;new[overlay,2]=1202
future=matrix.copy();future[3,:3]+=np.array(p['delta_cm']);local=(new@np.linalg.inv(future))[:,:3].astype('<f4');folder=O/'waterfront';folder.mkdir(exist_ok=True);path=folder/'PK0106-LOD0-vertices.bin';path.write_bytes(np.stack([xyz,local],axis=1).tobytes())
meshplan=dict(map_sha256=p['map_sha256'],meshes=[dict(key=r['key'],before=p['source_mesh'],after='/Game/UniversityCity/ImmersionV1/WaterDeck/SM_PK0106_LevelWaterfront_v3',lods=[dict(lod=0,vertices=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())])]);(O/'water2-mesh-plan.json').write_text(json.dumps(meshplan,indent=2),'utf8')
old=read(O/'water-deck-plan.json')['groups']['Metal'];metal=[q for q in old if abs(q['center'][0]-86125)>.01]
def box(c,s):assert min(s)>0;metal.append(dict(center=c,size=s))
def rail(a,b):
 dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);assert min(abs(dx),abs(dy))<.01;count=max(1,math.ceil(length/160))
 for i in range(count+1):
  t=i/count;x,y=a[0]+t*dx,a[1]+t*dy;box([x,y,1207],[14,14,2]);box([x,y,1260.5],[6,6,109])
 for z,thick in [(1241,2),(1271,2),(1301,2),(1315,6)]:box([(a[0]+b[0])/2,(a[1]+b[1])/2,z],[abs(dx)-6 if abs(dx)>1 else thick,abs(dy)-6 if abs(dy)>1 else thick,thick])
for a,b in [([86125,74575],[86125,75335]),([86125,75665],[86125,76925]),([86125,75335],[86125,75365]),([86125,75635],[86125,75665]),([86125,75365],[86625,75365]),([86125,75635],[86625,75635])]:rail(a,b)
seen=set();metal=[q for q in metal if not ((tuple(q['center']),tuple(q['size'])) in seen or seen.add((tuple(q['center']),tuple(q['size']))))]
stone=[dict(center=[86225,75500,1198],size=[150,300,16])]
for q in read(O/'campus-route-plan.json')['boxes']:
 c,s=q['center'],q['size'];lo=[c[i]-s[i]/2 for i in range(2)];hi=[c[i]+s[i]/2 for i in range(2)]
 assert not (hi[0]>86300 and lo[0]<88400 and hi[1]>74300 and lo[1]<76700),('Existing path would overlap level deck',q)
actor=dict(p['actor_before']);actor['location']=[actor['location'][i]+p['delta_cm'][i] for i in range(3)]
plan=dict(status='prepared_requires_native_install',map_sha256=p['map_sha256'],actor='World_PK_0106',actor_before=p['actor_before'],actor_after=actor,source_mesh=p['source_mesh'],fixture_moves=p['fixture_moves'],pier_ground=p['pier_ground'],stone=stone,metal=metal,old_metal_count=len(old),deck_bounds_cm=[86600,74300,88400,76700],bridge_bounds_cm=[86150,75350,86300,75650],walk_points_cm=[[84600,75750],[84600,75000],[85900,75000],[85900,75500],[87000,75500],[88000,75500],[88000,76300],[87000,76300],[87000,75500]],policy='Level at 1206cm, move entire deck 5m inside campus perimeter; terrain-ground 20 piers; flatten old ramp; finite 1.5m slab joins PK0105 through a 3m rail opening; keep existing PK0106 railings/furniture/materials; bury isolated sealing slivers inside slab.')
(O/'water2-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared PK0106:',nv,'vertices, 20 grounded piers, 12 fixture moves and',len(metal),'shared rail solids')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
