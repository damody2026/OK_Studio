-- Exact transformed AABBs from native mesh bounds, including individual HISM
-- transforms. Actor bounds can contain an origin sentinel and are unsuitable.
local code=[====[
import json,math,re
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');data=json.loads((O/'inventory.json').read_text('utf8'));meshes={r['mesh']:r for r in data['meshes']};actors={r['label']:r for r in data['actors']};rows=[]
def bounds(m,t):
 x,y,z,w=t['rotation'];R=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]];s=t['scale'];p=m['bounds_origin'];e=m['bounds_extent'];center=[t['translation'][i]+sum(R[i][j]*p[j]*s[j] for j in range(3)) for i in range(3)];extent=[sum(abs(R[i][j]*s[j])*e[j] for j in range(3)) for i in range(3)];return center,extent
for c in data['components']:
 if not c['visible'] or c['hidden'] or actors[c['actor']]['hidden']:continue
 if c['actor'].startswith(('Campus_','City_','RomanceArch_','RomanceName_')):continue
 for index,t in enumerate(c.get('instances',[c['transform']])):
  center,extent=bounds(meshes[c['mesh']],t);lo=[center[i]-extent[i] for i in range(3)];hi=[center[i]+extent[i] for i in range(3)]
  if math.dist(center[:2],[80000,57250])>8000 or max(extent[:2])>2500 or not(lo[2]<1850 and hi[2]>1450):continue
  if re.search(r'/TreeUpgrade|/FloweringTrees|tree_trunk|/camphor|/cherry',c['mesh'],re.I):continue
  rows.append(dict(actor=c['actor'],component=c['component'],instance=index if 'instances' in c else -1,mesh=c['mesh'],min_cm=lo,max_cm=hi,materials=c['materials']))
(O/'pk0102-elevated-props.json').write_text(json.dumps(dict(status='diagnostic_only',map_sha256=data['map_sha256'],rows=rows),indent=2),'utf8')
print('PK0102 elevated prop components:',len(rows))
for r in rows:print(r['actor'],r['instance'],[round(v,1) for v in r['min_cm']],[round(v,1) for v in r['max_cm']],r['mesh'])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
