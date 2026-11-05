-- Scoped independent triangle scans; runtime visibility excludes retired helpers.
local code=[====[
import json,hashlib,re
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');export=json.loads((O/'depth-export.json').read_text('utf8'));source=Path(export['folder']);assert source.parent==O;raw=(source/'scene.json').read_bytes();assert hashlib.sha256(raw).hexdigest()==export['metadata_sha256'];scene=json.loads(raw);snapshot=json.loads((O/'preservation-after.json').read_text('utf8'));assert snapshot['map_sha256']==export['map_sha256'];lookup={r['actor']+'::'+r['component']:r for r in snapshot['components']};meshes=json.loads(json.dumps(scene['meshes']))
for m in meshes:
 for lod in m['lods']:
  p=source/lod['file'];assert p.parent==source and p.is_file();lod['file']='../'+source.name+'/'+p.name
scopes={'outdoor-ground':[],'campus-buildings':[],'environment-fixtures':[]};skipped=0
for r in scene['instances']:
 state=lookup.get(r['key'])
 if not state or not state['visible'] or state['hidden'] or state['actor_hidden']:skipped+=1;continue
 n=r['actor'];asset=scene['meshes'][r['mesh']]['asset'];vegetation=any(k in asset for k in ['/TreeUpgrade','/ImmersionV1/Palms/','/ImmersionV1/Cherries/','/ImmersionV1/CherriesV2/','/ImmersionV1/Evergreens/','/ImmersionV1/LandscapeLOD/'])
 if (n.startswith(('World_PK_','DepthStableStreet_','DepthStableTactile_','FlatCampus_','Outdoor_','OfficeSetback_')) or re.fullmatch(r'G\d\d',n) or (n.startswith('Immersion_') and not vegetation)):scopes['outdoor-ground'].append(r)
 if (n.startswith('Campus_') or n.startswith('CityArt_canopy_') or n=='Immersion_CanopyMounts'):scopes['campus-buildings'].append(r)
 if n.startswith('Environment_'):scopes['environment-fixtures'].append(r)
result=[]
for name,instances in scopes.items():
 assert instances;folder=O/('depth-'+name+'-'+export['map_sha256'][:12]);folder.mkdir(exist_ok=True);data={k:v for k,v in scene.items() if k not in ['instances','meshes']};data['instances']=instances;data['meshes']=meshes;p=folder/'scene.json';p.write_text(json.dumps(data,separators=(',',':')),'utf8');result.append(dict(name=name,folder=str(folder),metadata_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),instances=len(instances),unique_meshes=len(set(r['mesh'] for r in instances)),report=str(folder/'depth-report.json')))
receipt=dict(status='prepared_requires_scan',map_sha256=export['map_sha256'],source_metadata_sha256=export['metadata_sha256'],source_folder=str(source),runtime_hidden_instances_excluded=skipped,scopes=result,limitations='Three explicit geometry scopes, not all props or a global zero-z-fighting certificate. Opaque/masked static triangle depth checks complement player-height screenshots and moving views; deliberate internal solid contacts require review.');(O/'depth-scopes.json').write_text(json.dumps(receipt,indent=2),'utf8');print('Prepared depth scopes:',[(r['name'],r['instances'],r['unique_meshes']) for r in result])
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
