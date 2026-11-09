-- Keep upgraded physical lanterns, reversibly retire adjacent duplicate standard poles.
local code=[====[
import json
from pathlib import Path
O=Path('C:/portable/OpenKoikatsu/output/street-social-city-production/immersion-v1');spacing=json.loads((O/'landscape-spacing.json').read_text());native=json.loads((O/'lamp-spacing-native-context.json').read_text());snapshot=json.loads((O/'preservation-after.json').read_text());assert spacing['map_sha256']==native['map_sha256']==snapshot['map_sha256'];lights={r['actor']:r for r in native['lights']};selected={}
for pair in spacing['environment_lamp_pairs_within250cm']:
 a,b=pair['a'],pair['b']
 if a['kind']=='immersion_lantern':a,b=b,a
 if a['kind']!='environment' or b['kind']!='immersion_lantern' or pair['distance_cm']>=180:continue
 prefix=a['id'];index=int(b['id'].rsplit('/',1)[1]);candidate=dict(kind='nautical_replacement',prefix=prefix,upgraded_light='Immersion_NauticalLight_%03d'%index,lantern_index=index,distance_cm=pair['distance_cm'],old_light=lights[prefix+'Light'],upgraded_before=lights['Immersion_NauticalLight_%03d'%index],source_components=[r for r in snapshot['components'] if r['actor'].startswith(prefix)])
 assert len(candidate['source_components'])==5 and not prefix.startswith('Environment_PK_');assert 'EnvGroup=Path' in candidate['old_light']['tags'] and 'EnvGroup=Path' in candidate['upgraded_before']['tags']
 if prefix not in selected or candidate['distance_cm']<selected[prefix]['distance_cm']:selected[prefix]=candidate
assert 15<=len(selected)<=40
for pair in spacing['environment_lamp_pairs_within250cm']:
 a,b=pair['a'],pair['b']
 if a['kind']!='environment' or b['kind']!='environment' or pair['distance_cm']>=120 or a['id'] in selected or b['id'] in selected:continue
 if a['id'].startswith('Environment_PK_') or b['id'].startswith('Environment_PK_'):continue
 prefix=b['id'];selected[prefix]=dict(kind='same_style_duplicate',prefix=prefix,upgraded_light=a['id']+'Light',distance_cm=pair['distance_cm'],old_light=lights[prefix+'Light'],upgraded_before=lights[a['id']+'Light'],source_components=[r for r in snapshot['components'] if r['actor'].startswith(prefix)])
plan=dict(status='prepared_requires_native_install',map_sha256=spacing['map_sha256'],groups=list(selected.values()),target_lumens=200,target_radius_cm=900,target_source_radius_cm=25,policy='Where a standard pole stands within1.8m of an upgraded nautical lantern, keep the nautical physical fixture, reversibly retire the five old mesh actors and old light(hidden,NoCollision,affects_world=false,EnvLumens=0), and use one200lm/2800K/9m soft Path-scheduled light at the surviving lantern head. Four same-style duplicate pairs below1.2m retain one unchanged original pole/light. Keep all original actors/assets for recovery; street poles and core PK site pairs excluded.')
(O/'lamp-consolidation-plan.json').write_text(json.dumps(plan,indent=2),'utf8');print('Prepared',len(selected),'reversible duplicate-pole retirements;',sum(r['kind']=='nautical_replacement' for r in selected.values()),'nautical survivors and',sum(r['kind']=='same_style_duplicate' for r in selected.values()),'unchanged original survivors')
for r in selected.values():print(r['prefix'],r['upgraded_light'],round(r['distance_cm'],1))
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
