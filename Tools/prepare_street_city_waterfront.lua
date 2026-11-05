-- Preserve the pavilion/benches/materials while adapting its old hilly-site
-- foundations and access to the level campus. All geometry remains finite.
local code=[====[
import json,struct,hashlib,math
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'immersion-v1';S=B/'traffic-v1/surface-current'
def read(p):return json.loads(p.read_text('utf8'))
probe=read(O/'water-deck-probes.json');assert probe['status']=='passed';g=read(O/'water-deck-geometry.json');scene=read(S/'scene.json');r=next(r for r in scene['instances'] if r['actor']=='World_PK_0105');asset=scene['meshes'][r['mesh']];assert asset['asset']==probe['mesh'];assert len(asset['lods'])==1
l=asset['lods'][0];raw=(S/l['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);xyz=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3).copy();matrix=np.array(r['matrix']).reshape(4,4);world=np.c_[xyz,np.ones(nv)]@matrix;new=world.copy();new[:,2]+=probe['delta_z_cm'];parts={p['id']:p for p in g['paving_parts']}
for p in probe['pier_ground']:
 vi=np.array(parts[p['part']]['vertex_indices']);top=world[vi,2].max();feet=vi[world[vi,2]<top-.5];new[feet,2]=p['foundation_base_cm'];new[vi[world[vi,2]>=top-.5],2]=1202
vi=np.array(parts[21]['vertex_indices']);xy=np.round(world[vi,:2],3);_,inverse=np.unique(xy,axis=0,return_inverse=True);tops=np.full(inverse.max()+1,-np.inf);np.maximum.at(tops,inverse,world[vi,2]);new[vi,2]=np.where(world[vi,2]>=tops[inverse]-.5,1206,1190)
# Redundant under-deck sheet strips are kept inside the finite slab, so they
# cannot fight its visible top or bottom after lowering.
for part in [22,23,24]:new[np.array(parts[part]['vertex_indices']),2]=1202
future=matrix.copy();future[3,2]+=probe['delta_z_cm'];local=(new@np.linalg.inv(future))[:,:3].astype('<f4');folder=O/'waterfront';folder.mkdir(exist_ok=True);path=folder/'PK0105-LOD0-vertices.bin';path.write_bytes(np.stack([xyz,local],axis=1).tobytes())
meshplan=dict(map_sha256=probe['map_sha256'],meshes=[dict(key=r['key'],before=probe['mesh'],after='/Game/UniversityCity/ImmersionV1/WaterDeck/SM_PK0105_LevelWaterfront',lods=[dict(lod=0,vertices=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest())])])
(O/'water-deck-mesh-plan.json').write_text(json.dumps(meshplan,indent=2),'utf8')
groups={'Stone':[],'Metal':[]}
def box(kind,c,s):assert min(s)>0;groups[kind].append(dict(center=c,size=s))
box('Stone',[(83100+84050)/2,75750,1198],[950,300,16])
for p in probe['bridge_pier_ground']:
 x,y=p['xy'];base=p['foundation_base_cm'];assert base<1191;box('Stone',[x,y,(base+1191)/2],[30,30,1191-base])
def rail(a,b):
 dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy);assert min(abs(dx),abs(dy))<.01;count=max(1,math.ceil(length/160))
 for i in range(count+1):
  t=i/count;x,y=a[0]+t*dx,a[1]+t*dy;box('Metal',[x,y,1207],[14,14,2]);box('Metal',[x,y,1260.5],[6,6,109])
 for z,thick in [(1241,2),(1271,2),(1301,2),(1315,6)]:box('Metal',[(a[0]+b[0])/2,(a[1]+b[1])/2,z],[abs(dx)-6 if abs(dx)>1 else thick,abs(dy)-6 if abs(dy)>1 else thick,thick])
for a,b in [([84375,74575],[86125,74575]),([86125,74575],[86125,76925]),([86125,76925],[84375,76925]),([84375,74575],[84375,75585]),([84375,75915],[84375,76925]),([83100,75615],[84375,75615]),([83100,75885],[84375,75885]),([84375,75585],[84375,75615]),([84375,75885],[84375,75915])]:rail(a,b)
# Adjacent segments share end posts. Keep one solid at each exact transform.
for key in groups:
 seen=set();groups[key]=[r for r in groups[key] if not ((tuple(r['center']),tuple(r['size'])) in seen or seen.add((tuple(r['center']),tuple(r['size']))))]
plan=dict(status='prepared_requires_native_install',map_sha256=probe['map_sha256'],actor='World_PK_0105',actor_before=probe['actor_transform'],actor_after_z_cm=1206,groups=groups,shore_join_cm=[83100,75750],walk_grid_target_cm=[83050,75750],access_bridge_bounds_cm=[83100,75600,84050,75900],deck_top_cm=1206,bridge_length_cm=950,rail_height_cm=112,source_mesh=probe['mesh'],policy='Level shore access, terrain-grounded 20 pavilion piers and 6 gangway piers; finite 16cm paving; geometric rails with a clear 3m access opening. Preserve all pavilion furniture/roof and material slots.')
(O/'water-deck-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared grounded PK0105:',nv,'vertices, 20 foundation piers, 9.5m gangway and',len(groups['Metal']),'railing solids')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
