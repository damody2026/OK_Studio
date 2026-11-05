-- One contract per referenced room page, with explicit site and design evidence.
local code=[====[
import json,math,hashlib,time
from pathlib import Path
R=Path('C:/portable/OpenKoikatsu');O=R/'output/street-social-city-production/motel-v1';catalog=json.loads((O/'reference-catalog.json').read_text('utf8'));rows=catalog['rooms']
IM={
 '205':('royal',(.36,.035,.065),'Tufted burgundy velvet, cream fluted columns, gilded oval furniture, canopy and chandelier'),
 '207':('galaxy',(.19,.045,.32),'Purple star-lit recessed ceiling, dark perimeter, warm metal and oval ceiling medallion'),
 '221':('palace',(.35,.22,.055),'Gold cylindrical crystal pendants and warm column rhythm'),
 '223':('lattice',(.035,.11,.27),'Blue velvet and tall black/gold scrolling and lattice headwall'),
 '225':('royal',(.21,.10,.055),'Dark timber, tall fluted headwall, classical fringed lamps and mirror partitions'),
 '227':('canopy',(.34,.018,.07),'Red button-tufted high back, draped canopy and theatrical sconces'),
 '229':('galaxy',(.34,.07,.08),'Warm pleated lamps, red accent upholstery and star-like ceiling lights'),
 '215':('butterfly',(.16,.13,.32),'Light butterfly motif on dark glass, pale bedding and blue-violet accent'),
 '231':('ribbon',(.48,.26,.08),'Looping multicolour ceiling bands and sculpted warm chandelier'),
 '233':('disco',(.42,.18,.045),'Circular ceiling recess, disco sphere and restrained coloured perimeter strips'),
 '237':('mirror',(.42,.02,.05),'Red quilted headwall, black faceted mirror panels and magenta ceiling cove'),
 '239':('royal',(.43,.25,.08),'Carved gilded curved sofa, reflective patterned headwall and warm neutral stone'),
 '241':('lattice',(.025,.14,.34),'Royal blue curved velvet seating, gold diamond lattice and light wood'),
 '243':('provencal',(.23,.12,.28),'Violet damask headwall, cream trim, gold-edged classical seating'),
 '245':('royal',(.48,.22,.23),'Blush velvet settee, curved gilded frame and dark stone table'),
 '247':('bamboo',(.13,.21,.08),'Bamboo stalks/leaves, warm natural timber and bathing enclosure'),
 '249':('marine',(.025,.14,.31),'Blue petal-backed chairs, silver outlines, teal textured wall and cool coves'),
 '251':('flower',(.42,.12,.28),'Petal-shaped golden mirror surround, floral geometry and pink-violet cove'),
 '253':('zebra',(.08,.075,.09),'Black/white upholstery rhythm, mirror partitions and freestanding media cabinet'),
 '258':('canopy',(.23,.09,.24),'Purple buttoned classical seating and warmly lit pleated shades'),
 '260':('stripe',(.28,.18,.29),'Purple/cream striped upholstery, pale patterned wall and stitched lampshade'),
 '262':('ivory',(.52,.43,.32),'Cream classical chandelier and quiet warm ivory surfaces'),
 '1340':('pool',(.20,.035,.06),'Private blue mosaic pool, curved entry steps and red/white wet-area banding'),
 '1344':('pool',(.13,.24,.12),'Private mosaic pool, warm wall lanterns and planting accents'),
 '1342':('pool',(.025,.15,.27),'Blue mosaic basin with rounded nested entry steps'),
 '1338':('pool',(.18,.08,.23),'Private pool suite with dark classical lighting and violet accents')}
def wego(r):
 n=r['name'];nogarage='無車庫' in n
 rules=[('Candy','candy',(.025,.15,.34),'Rounded white bed, sculptural candy swirls, melting edges and blue outlined ceiling'),('撲克','poker',(.42,.035,.035),'Playing-card suit reliefs, red/black round platform, bulb-trimmed curved panels'),('土耳其','hammam',(.43,.28,.07),'Gold curved textile headwall, vertical light channels and round spa tub'),('月球','moon',(.035,.11,.24),'Dark blue mosaic bath, circular porthole mirrors and cool luminous water column'),('蝴蝶','butterfly',(.30,.16,.075),'Relaxed neutral lounge, dark media wall and butterfly accents'),('愛麗斯','ivory',(.55,.40,.22),'Ivory wing-shaped headboard and suspended oval violet cove'),('舞孃','disco',(.30,.015,.045),'Red shimmering headwall, dark stage-like lounge and curved chaise'),('天使','angel',(.57,.49,.40),'Ivory classical bed, pastel ceiling panels and hanging bench'),('巴里','tropical',(.22,.11,.045),'Timber wall and ceiling, linen, shaded dressing table and warm bathing area'),('夏威夷','brick',(.43,.26,.095),'Broad brick arch opening, warm timber, cream seating and round bath'),('香奈','stripe',(.34,.20,.075),'Warm cream surfaces, amber leather seating and dark framed cabinets'),('凡賽','royal',(.43,.31,.12),'Golden bed accents, classical chandelier and dark-gold bath screen'),('加州','travertine',(.46,.34,.24),'Warm veined stone bathroom, broad round massage bath and timber vanity'),('上海','oriental',(.36,.025,.055),'Red patterned headwall, large circular fan-like headboard and dark timber'),('水晶','crystal',(.28,.28,.34),'Pale upholstered sofa, silver/faceted table and blue-violet translucent accents'),('地中海','mediterranean',(.48,.27,.12),'Ochre/cream striped headwall, timber floor and classical cornice'),('芭比','barbie',(.47,.22,.32),'Round bed, pink coves, black wavy mirror partitions and framed light motifs'),('巴洛','baroque',(.25,.19,.27),'Freestanding white clawfoot tub, small wet-area tiles and purple coves'),('伊莉','canopy' if nogarage else 'royal',(.30,.035,.055) if nogarage else (.48,.39,.25),'Four-poster red canopy and pale curved settee' if nogarage else 'Cream stone bath, classical chandelier and carved oval mirror'),('黑色','canopy' if nogarage else 'lattice',(.055,.045,.07),'Black draped bed canopy and pale stripes' if nogarage else 'Black bath podium, geometric pierced screen and warm brass'),('東方','oriental',(.38,.07,.045),'Dark timber, red upholstered panels, circular details and warm cove'),('花園','garden',(.24,.31,.13),'Cream carved furniture, green rug and generous broad-leaf planting'),('森林','forest',(.13,.16,.10),'Backlit branch relief headwall, brown lounge and leaf-green rug'),('鉑金','crystal',(.28,.27,.32),'Large faceted mirror composition, silver seating and violet underlight'),('元素','ribbon',(.33,.25,.20),'Pale vertical stripe wall, sculpted coloured ceiling elements and egg-like chairs'),('瑪姬','provencal',(.45,.28,.37),'Pastel pink wall pilasters, curved classical seating and round upholstered table'),('威尼斯','music',(.28,.09,.10),'Deep red panels, gold-framed light motifs and dark timber'),('66','route66',(.23,.11,.055),'Brown leather seating, timber headwall, bar shelves and warm bottle lighting'),('大道','mirror',(.42,.34,.16),'Vertical mirror strips, oval gilded ceiling cove and violet floor wash')]
 for key,style,color,note in rules:
  if key in n:return style,color,note
 raise AssertionError('Unclassified source room '+n)
branch_ids={'247','239','241'};designed=[]
for r in rows:
 style,color,note=IM[r['source_id']] if r['source']=='imore' else wego(r);pool=style=='pool';branch=r['source']=='imore' and r['source_id'] in branch_ids
 q=dict(id=r['id'],source=r['source'],source_id=r['source_id'],reference_url=r['url'],reference_image=r['images'][0]['url'],source_name=r['name'],building='S18' if branch else 'H1',style=style,accent=list(color),design_observations=note,source_photo_review='Primary photo visually viewed through official public image URL',is_pool_suite=pool,span=2 if pool else 1,has_in_room_garage=r['source']!='wego-linsen' or '無車庫' not in r['name'],required_features=['real enclosed bathroom','vanity mirror','shower','WC','double massage bath','king bed','lounge seating','dressing storage','minibar','television','ventilation','night lighting'],model_status='not_built')
 if branch:q['has_in_room_garage']=False;q['assigned_ground_garage']=True
 designed.append(q)
levels={1:0,2:5.,3:9.6,4:14.,5:18.3};slot=0
for q in sorted([r for r in designed if r['building']=='H1'],key=lambda r:(not r['is_pool_suite'],r['source'],r['source_id'])):
 if slot%8+q['span']>8:slot+=8-slot%8
 floor=2+slot//16;row=(slot%16)//8;col=slot%8;assert floor<=5
 q.update(floor=floor,local_center_m=[-60.8+(col+q['span']/2)*15.2,14.4 if row==0 else -14.4,levels[floor]],yaw=0 if row==0 else 180,size_m=[15.2*q['span'],20.8,3.9],floor_height_m=4.6 if floor==2 else 4.4 if floor==3 else 4.3,room_number=str(floor*100+(slot%16)+1));slot+=q['span']
for n,q in enumerate(r for r in designed if r['building']=='S18'):
 q.update(floor=n+1,local_center_m=[0,6.,n*4.4],yaw=0,size_m=[15.2,20.8,3.9],floor_height_m=4.4,room_number=str((n+1)*100+1))
assert len(designed)==len({r['id'] for r in designed})==61 and slot<=64
plan=dict(status='dimensioned_design_requires_native_boundary_checks_and_models',created_at=time.strftime('%Y-%m-%dT%H:%M:%S')+'+08:00',reference_catalog_sha256=hashlib.sha256((O/'reference-catalog.json').read_bytes()).hexdigest(),rooms=designed,buildings=[dict(id='H1',name='影輝之夜 情趣汽車旅館',original_floors=5,floors=5,original_footprint_m=[126,54],main_footprint_m=[126,54],ramp_extension_bounds_local_m=[-62,29,62,50],expanded_total_footprint_m=[126,77],room_count=sum(r['building']=='H1' for r in designed),ground_floor='Reception, service rooms, approach lane, lounge and accessible WC',vehicular_access='Two-flight switchback ramp to each upper guest level;8m central drive lane;private bay or assigned ground parking per source variant'),dict(id='S18',name='花境 情趣汽車旅館',original_floors=3,floors=3,main_footprint_m=[32,40],room_count=3,vehicular_access='Three individually assigned ground-level bays and separate pedestrian stairs')],rules=['User explicitly authorizes enlargement wherever needed.','Preserve school floors/functions, streets and old accepted package.','Reference-informed game adaptation; dimensions inferred for this scene, not claimed measured copies.','One model contract per source page; duplicate names retain distinct identities.','No models, render passes or packaging passes claimed by this planning receipt.'])
(O/'motel-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),'utf8');print('Planned',len(designed),'source-specific suites:',sum(r['building']=='H1' for r in designed),'H1 +3 S18;H1',slot,'of64 guest-level bays,including4 double-width pool suites.')
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
