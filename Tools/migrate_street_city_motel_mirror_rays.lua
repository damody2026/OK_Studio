-- Derive the intentional new mirror collision face from audited cube geometry.
-- The actual cooked replay must independently agree within the original1cm limit.
local code=[====[
import json,math,hashlib
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1');load=lambda n:json.loads((O/(n+'.json')).read_text('utf8'));audit=load('audit');install=load('motel-install');package=load('package');wc=load('restroom-mirrors-install');sha=lambda f:hashlib.sha256(Path(f).read_bytes()).hexdigest();mapfile='C:/portable/OpenKoikatsu/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';ms=sha(mapfile);original=O/('game-physics-plan-before-mirror-migration-'+ms[:16]+'.json')
if original.exists():p=json.loads(original.read_text('utf8'))
else:
 legacy=O/'game-physics-plan-before-mirror-migration.json';prior=json.loads(legacy.read_text('utf8')) if legacy.exists() else None;p=prior if prior and prior['map_sha256']==ms else load('game-physics-plan')
original_text=json.dumps(p,ensure_ascii=False);assert p['map_sha256']==audit['map_sha256']==install['map_sha256']==package['map_sha256']==ms and audit['status']=='passed' and audit['new_reflection_components']==1033
group={}
for b in wc['mirrors']:group.setdefault(b['backing_actor'],[]).append(b)
dot=lambda a,b:sum(x*y for x,y in zip(a,b));sub=lambda a,b:[x-y for x,y in zip(a,b)]
def hit_box(start,end,center,half):
 delta=sub(end,start);lo=0.;hi=1.
 for i in range(3):
  if abs(delta[i])<1e-9:
   if abs(start[i]-center[i])>half[i]+1e-5:return None
  else:
   a=(center[i]-half[i]-start[i])/delta[i];b=(center[i]+half[i]-start[i])/delta[i];lo=max(lo,min(a,b));hi=min(hi,max(a,b))
   if hi<lo:return None
 return lo,[start[i]+delta[i]*lo for i in range(3)]
changes=[]
for r in p['rays']:
 if r.get('kind')!='school_glazing' or not r.get('expected_hit') or 'expected_point' not in r:continue
 old=r['expected_point'];direction=sub(r['end'],r['start']);length2=dot(direction,direction);old_t=dot(sub(old,r['start']),direction)/length2;hits=[]
 for b in group.get(r['building'],[]):
  n=b['normal'];t=[-n[1],n[0],0];offset=sub(old,b['face'])
  if abs(dot(offset,n)+2.5)>.1 or dot(direction,n)>=0 or abs(dot(offset,t))>b['width_cm']/2+2.1 or abs(offset[2])>49.6:continue
  # Old1.5cm window probes can start inside the newly added backing. Move only
  # these approaching probes to2cm outside the glass, avoiding inside-shape
  # raycast semantics while still testing the exact intended new front face.
  advance=max(0.,2.75-dot(sub(r['start'],b['face']),n));start=[r['start'][i]+n[i]*advance for i in range(3)];dd=sub(r['end'],start);old_t_new=dot(sub(old,start),dd)/dot(dd,dd)
  for suffix,depth,extra,hz in [('Glass',0,0,47.5),('Backing',-1.5,2,49.5)]:
   center=[b['face'][i]+n[i]*depth for i in range(3)];half=[abs(n[i])*.75+abs(t[i])*(b['width_cm']/2+extra)+(hz if i==2 else 0) for i in range(3)];hit=hit_box(start,r['end'],center,half)
   if hit and hit[0]>1e-6 and hit[0]<old_t_new-1e-6 and 1.<math.dist(hit[1],old)<=3.30:hits.append((hit[0],hit[1],b['actor']+'_'+suffix,b['backing_actor'],start))
 if hits:
  _,point,actor,backing,start=min(hits,key=lambda h:h[0]);changes.append(dict(id=r['id'],building=r['building'],mirror_actor=actor,verified_backing_actor=backing,before_start=r['start'],after_start=start,before=old,after=point,distance_cm=math.dist(point,old)));r['start']=start;r['expected_point']=point;r['motel_mirror_surface_migration']=True
assert changes and sha(mapfile)==ms
p['mirror_surface_migrations']=len(changes);p['mirror_migration_method']='Analytic ray/cube intersections from audited installed mirror bank transforms;pending independent cooked replay'
if not original.exists():original.write_text(original_text,'utf8')
(O/'game-physics-plan.json').write_text(json.dumps(p,ensure_ascii=False),'utf8')
receipt=dict(status='derived_from_audited_geometry_requires_cooked_replay',map_sha256=ms,changed=len(changes),rows=changes,retained_position_tolerance_cm=1.,audit_sha256=sha(O/'audit.json'),scope='Only positive school-glazing queries approaching a verified mirror-covered original backing face are updated. New contact is the analytic intersection with the installed Engine Cube glass/backing dimensions;max change3.30cm. Expected hit=true and simple Pawn checks remain unchanged. Actual Game must independently match the derived coordinates within1cm. No map or asset mutation.')
(O/'mirror-collision-migration.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),'utf8');print('Derived',len(changes),'mirror-front expectation updates;independent cooked replay required.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
