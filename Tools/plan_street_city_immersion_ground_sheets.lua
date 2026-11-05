-- Reuse the existing proven polygon partitioner; never move terrain elevations.
assert(not arg[1] or arg[1]=='deferred' or arg[1]=='connection','Use deferred or connection only for explicit scoped pairs')
local code=[====[
import json,re,hashlib,shutil
from pathlib import Path
DEFERRED_MODE=False
CONNECTION_MODE=False
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');d=json.loads((O/'depth-scopes.json').read_text());scope=next(s for s in d['scopes'] if s['name']=='outdoor-ground');S=Path(scope['folder']);scene=json.loads((S/'scene.json').read_text());selected=[];archive=None
if (O/'ground-sheet-install.json').exists():
 previous=json.loads((O/'ground-sheet-install.json').read_text());audit=json.loads((O/'audit.json').read_text());assert audit['status']=='passed' and audit['map_sha256']==d['map_sha256'];archive=O/'ground-sheet-history'/d['map_sha256'][:16]
 if not archive.exists():
  archive.mkdir(parents=True);files=[]
  for name in ['source','selection','empty-ledger','plan','preflight','native','collision','install']:
   p=O/('ground-sheet-'+name+'.json');shutil.copy2(p,archive/p.name);files.append(dict(file=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest()))
  (archive/'manifest.json').write_text(json.dumps(dict(map_sha256=d['map_sha256'],files=files)),'utf8')
 assert (archive/'ground-sheet-install.json').read_bytes()==(O/'ground-sheet-install.json').read_bytes()
for n in sorted(set(r['actor'] for r in scene['instances'])):
 ground=bool(re.fullmatch(r'G\d\d',n));street=n.startswith(('DepthStableStreet_','DepthStableTactile_'))
 selected.append(dict(label=n,repair_eligible=(n=='Outdoor_connection') if CONNECTION_MODE else ground or street,cover_only=False if CONNECTION_MODE else street,ground_top_replace=False if CONNECTION_MODE else ground,front_only_tolerance_cm=.002 if CONNECTION_MODE else (.2 if ground else .002)))
(O/'ground-sheet-selection.json').write_text(json.dumps(dict(actors=selected,enable_mixed_same_facing=True,prefer_same_facing_pass=True)),'utf8');(O/'ground-sheet-empty-ledger.json').write_text('{"components":[]}','utf8');n=0
with (S/'depth-report.conflicts.jsonl').open() as src,(O/'ground-sheet-conflicts.jsonl').open('w') as dest:
 for line in src:
  r=json.loads(line);a,b=r['a_actor'],r['b_actor'];ag=bool(re.fullmatch(r'G\d\d',a));bg=bool(re.fullmatch(r'G\d\d',b))
  if (ag and bg) or (ag and b.startswith(('DepthStableStreet_','DepthStableTactile_'))) or (bg and a.startswith(('DepthStableStreet_','DepthStableTactile_'))):dest.write(line);n+=1
conflicts=S/'depth-report.conflicts.jsonl';derivation=None
if CONNECTION_MODE:
 conflicts=O/'ground-sheet-connection.conflicts.jsonl';kept=0
 with (S/'depth-report.conflicts.jsonl').open() as src,conflicts.open('w') as dest:
  for line in src:
   r=json.loads(line)
   if r['a_actor']==r['b_actor']=='Outdoor_connection' and abs(r['normal'][2])>.999 and abs(r['separation_cm'])<=.2:dest.write(line);kept+=1
 assert kept>0;derivation=dict(status='explicit_outdoor_connection_subset',parent_scan=str(S/'depth-report.json'),parent_candidates_sha256=hashlib.sha256((S/'depth-report.conflicts.jsonl').read_bytes()).hexdigest(),metadata_sha256=scope['metadata_sha256'],truncated=False,candidate_conflicts=kept,target_actor='Outdoor_connection',scope='Only internal horizontal two-sided surface overlaps of this one exterior connector;original world heights,UVs and exact original collision retained.');(O/'ground-sheet-connection.json').write_text(json.dumps(derivation,indent=2),'utf8')
if DEFERRED_MODE:
 pairs={'G06':{1,3},'G07':{1,3},'G10':{1,2},'G11':{1,2},'G14':{1,2},'G15':{1,2}};conflicts=O/'ground-sheet-scoped.conflicts.jsonl';kept=0
 with (S/'depth-report.conflicts.jsonl').open() as src,conflicts.open('w') as dest:
  for line in src:
   r=json.loads(line);a=r['a_actor']
   if a==r['b_actor'] and a in pairs and {r['a_material_slot'],r['b_material_slot']}==pairs[a] and abs(r['center_cm'][2]-1198)<.02 and abs(r['normal'][2])>.999:dest.write(line);kept+=1
 derivation=dict(status='explicit_candidate_subset_for_bounded_repair_not_a_new_global_scan',parent_scan=str(S/'depth-report.json'),parent_scan_sha256=hashlib.sha256((S/'depth-report.json').read_bytes()).hexdigest(),parent_candidates_sha256=hashlib.sha256((S/'depth-report.conflicts.jsonl').read_bytes()).hexdigest(),metadata_sha256=scope['metadata_sha256'],candidate_conflicts=kept,truncated=False,filter=dict(actors_material_slot_pairs={k:sorted(v) for k,v in pairs.items()},z_cm=1198,z_tolerance_cm=.02,abs_normal_z_min=.999),limitations='All original scan rows retained separately. This complete subset only resolves explicitly identified exposed grass/campus pairs deferred by the conservative multi-operation planner. No global-zero claim; Native cover/area/shader/collision validation remains mandatory.')
 (O/'ground-sheet-scoped.json').write_text(json.dumps(derivation,indent=2),'utf8')
(O/'ground-sheet-source.json').write_text(json.dumps(dict(map_sha256=d['map_sha256'],folder=str(S),scene_sha256=scope['metadata_sha256'],conflicts=n,planner_conflicts=str(conflicts),bounded_derivation=derivation,target_mode='connection' if CONNECTION_MODE else 'terrain',prior_pass_archive=str(archive) if archive else None)),'utf8');print('Prepared conservative ground sheet input:',n,'candidates; flat heights, UVs, original source meshes retained.')
]====]
if arg[1]=='deferred'then code=code:gsub('DEFERRED_MODE=False','DEFERRED_MODE=True',1)end
if arg[1]=='connection'then code=code:gsub('CONNECTION_MODE=False','CONNECTION_MODE=True',1)end
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local o='C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1';local f=assert(io.open(o..'/ground-sheet-source.json'));local s=j.decode(f:read('*a'));f:close()
local r=ok.proc.run({'Tools/resort-props/target/release/city-world-sheets.exe',s.folder,o..'/ground-sheet-selection.json',o..'/ground-sheet-empty-ledger.json',s.planner_conflicts,o..'/ground-sheet-plan.json'},{hide=true,stdout_file=o..'/ground-sheet-planner.log',stderr_file=o..'/ground-sheet-planner.stderr',timeout=1800});assert(r.code==0,'Ground sheet planner failed; inspect its bounded logs.');print('Ground sheet candidate plan generated; native shader/area/collision checks and manual review still required.')
