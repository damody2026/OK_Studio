-- Identify real broad ceiling undersides, not furniture or facade surfaces.
local code=[====[
import json,struct,re,hashlib
from pathlib import Path
import numpy as np
B=Path('C:/portable/OpenKoikatsu/output/street-social-city-production');O=B/'immersion-v1';S=B/'traffic-v1/surface-current'
def read(p):return json.loads(p.read_text('utf-8-sig'))
specs={b['building']:b for b in read(O/'interior-probe-plan.json')['buildings']};scene=read(S/'scene.json');live={(r['actor'],r['component']):r for r in read(O/'preservation-after.json')['components']};rows=[];actors=set();coverage={}
for r in scene['instances']:
 match=re.fullmatch(r'Campus_([A-Z0-9]+)_F(\d\d)',r['actor'])
 if not match or r['instance']!=-1:continue
 bid,no=match[1],int(match[2]);b=specs[bid]
 if no==1:continue # underground foundation underside is outside this repair
 f=next(f for f in b['floors'] if f['floor']==no);current=live[(r['actor'],r['component'])];m=scene['meshes'][r['mesh']];assert m['asset']==current['mesh'];matrix=np.array(r['matrix']).reshape(4,4);base=matrix[3,2];planes=[float(base+f['z_m']*100-30)]
 if no==b['floors'][-1]['floor']:planes.append(float(base+(f['z_m']+f['height_m'])*100-30))
 raw=(S/m['lods'][0]['file']).read_bytes();_,nv,nt=struct.unpack_from('<III',raw);v=np.frombuffer(raw,dtype='<f4',count=nv*3,offset=12).reshape(-1,3);v=(np.c_[v,np.ones(nv)]@matrix)[:,:3];tri=np.frombuffer(raw,dtype='<u4',count=nt*3,offset=12+nv*12).reshape(-1,3);slots=np.frombuffer(raw,dtype='<u4',count=nt,offset=12+nv*12+nt*16);p=v[tri];cross=np.cross(p[:,1]-p[:,0],p[:,2]-p[:,0]);area=np.linalg.norm(cross,axis=1)/2;normal=cross/np.maximum(area[:,None]*2,1e-8);z=p[:,:,2].mean(axis=1);mask=(np.ptp(p[:,:,2],axis=1)<.02)&(normal[:,2]>.9)&np.any(np.abs(z[:,None]-np.array(planes))<.5,axis=1)
 for slot in np.unique(slots[mask]):
  ar=float(area[mask&(slots==slot)].sum()/10000)
  if ar<1:continue
  before=current['materials'][slot];rows.append(dict(actor=r['actor'],component=r['component'],mesh=current['mesh'],slot=int(slot),before=before,planes_cm=planes,downward_area_m2=ar));actors.add(r['actor']);coverage[r['actor']]=coverage.get(r['actor'],0)+ar
assert len(actors)>=70,(len(actors),len(rows))
result=dict(status='prepared_requires_native_shader_and_visual_validation',map_sha256=read(O/'install.json')['map_sha256'],source_export='traffic-v1/surface-current',actors=len(actors),slots=len(rows),area_m2=sum(q['downward_area_m2'] for q in rows),rows=rows,scope='Broad downward horizontal faces at actual floor-slab underside and roof-ceiling heights. The shader mask is downward normal and two exact world-height planes; furniture, windows and vertical facades retain original shading.')
(O/'ceiling-plan.json').write_text(json.dumps(result,indent=2),'utf8');print('Ceiling plan:',result['actors'],'floor actors,',result['slots'],'slots,',round(result['area_m2']),'m2')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
