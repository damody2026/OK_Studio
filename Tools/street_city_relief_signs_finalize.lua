local code=[====[
from pathlib import Path
import json,hashlib,html,re,numpy as np
from PIL import Image
root=Path.cwd();out=root/'output/street-social-city-production/resort-architecture-v1'
def read(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n','utf8')
audit=read(out/'audit.json');render=read(out/'render.json');install=read(out/'install.json');relief=read(out/'relief-signs-review.json');shader=read(out/'shader.json')
mapfile=root/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
assert audit['status']==render['status']==relief['status']=='passed'
assert audit['map_sha256']==render['map_sha256']==install['map_sha256']==sha(mapfile)
assert len(shader['buildings'])==len(relief['designs'])==122
assert all(abs((r['layout_canvas_size'][0]/r['layout_canvas_size'][1])/(r['physical_size_m'][0]/r['physical_size_m'][1])-1)<.03 for r in relief['rows'])
assert all('/SignsReliefV3/MI_Night_' in r['sign_material'] for r in shader['buildings'])
shader_by={r['id']:r for r in shader['buildings']}
for r in install['buildings']:
 fresh=shader_by[r['id']]
 assert r['geometry_mesh']==fresh['mesh'] and r['sign_mesh']==fresh['sign_mesh'] and r['sign_material']==fresh['sign_material'],r['id']+' map references stale sign assets'
exits={m:read(out/(m+'-exit.json'))['exit_code'] for m in ['shader','install','render']};assert all(v==0 for v in exits.values()),exits
assert all(sha(Path(r['path']))==r['sha256'] for r in render['images'])
log=(out/'shader-editor.log').read_text('utf8',errors='replace')
assert not any(s in log for s in ['Failed to compile Material','error X3000','error X3013','error X3018','error X4502']), 'Shader compiler errors'
accepted=read(out/'acceptance.json')
night=read(out/'night-signs-review.json');assert night['status']=='passed' and sum(night['counts'].values())==122
images={r['name']:r for r in render['images']};comparisons=[]
for bid in ['S01','S03','S09']:
 on=images[bid+'-night'];off=images[bid+'-night-off']
 assert all(on['camera'][k]==off['camera'][k] for k in ['eye','target','fov'])
 a=np.asarray(Image.open(on['path']).convert('RGB'),dtype=np.float32);b=np.asarray(Image.open(off['path']).convert('RGB'),dtype=np.float32)
 delta=(a-b).mean(axis=2);roi=delta[350:650,160:1440]
 assert np.max(roi)>20 and np.count_nonzero(roi>10)>300,(bid,'No visible self-emission difference')
 comparisons.append(dict(building=bid,on=on['sha256'],off=off['sha256'],mean_sign_roi_increase=float(roi.mean()),pixels_increased_over_10=int(np.count_nonzero(roi>10)),fixed_exposure=True))
write(out/'night-visual-review.json',dict(status='passed',pairs=comparisons,method='Same native camera and fixed exposure;only target sign emissive strength changes from1 to0. Directional and sky lighting restored after captures;city map is not saved during night capture.'))
selected=['S03-night','S09-night','S01-night','S01-relief-night','TR-night','R1-night','H1-night','S03','S09','S01','S03-relief']
accepted.update(status='passed',scope='122 realistic storefront/facility signs with32-step height-map parallax and normal/roughness;120 ground-floor horizontal,2 vertical;427 original floors retained',map_sha256=sha(mapfile),native_render_images=len(render['images']),native_checks=audit['checks'],native_issues=audit['issues'],native_exit_codes=exits,visually_selected_gallery_images=selected,signage=dict(horizontal=120,vertical=2,translations=366,finish_families=len({d['style'] for d in relief['designs']}),relief_cm=2.8,method='32-step POM +5 binary refinements +PixelDepthOffset via material attributes +physical tangent normals',silhouette='height-field effect within rectangular sign case;not separate extruded letter meshes'))
accepted['signage']['night_lighting']=night['counts'];accepted['signage']['night_on_off_pairs']=3
assert read(out/'relief-validation.json')['status']=='passed'
for name in ['shader.json','install.json','audit.json','render.json','night-signs-review.json','night-visual-review.json','relief-signs-review.json','relief-validation.json','geometry-manifest.json','geometry-review.json']:
 accepted['receipts'][name]=sha(out/name)
for name in ['Tools/street_city_relief_signs.lua','Tools/street_city_relief_signs_payload.lua','Tools/street_city_relief_signs_finalize.lua','Tools/street_city_relief_signs_verify.lua']:
 accepted['source_sha256'][name]=sha(root/name)
for name in accepted['source_sha256']:accepted['source_sha256'][name]=sha(root/name)
write(out/'acceptance.json',accepted)
catalogue=read(root/'output/street-social-city-production/localization-v1/catalogue.json')['entries']
styles={'walnut_brass':'深木底 × 黃銅字','cream_bronze':'奶油烤漆 × 銅色字','sage_ceramic':'鼠尾草綠 × 陶白字','burgundy_enamel':'酒紅琺瑯 × 香檳字','navy_channel':'藏藍金屬 × 立體槽字','charcoal_brass':'炭灰金屬 × 黃銅字','ivory_lightbox':'象牙底 × 深綠字'}
by={d['id']:d for d in relief['designs']}
night_by={r['id']:r for r in night['rows']};method_names=dict(lit_letters='亮字',lit_background='亮背景',backlit_halo='暖色背光暈')
gallery=''
for view in selected:
 bid=view.split('-')[0];name=html.escape(catalogue['building.'+bid]['translations']['zh-Hant']);label='斜角近照 · 字凸底凹' if '-relief' in view else styles[by[bid]['style']]
 if '-night' in view:label='夜景 · '+method_names[night_by[bid]['method']]
 gallery+=f'<figure><a href="renders/{view}.png?revision=night-v1"><img loading="lazy" src="renders/{view}.png?revision=night-v1" alt="{name}招牌實景"></a><figcaption><b>{name}</b><span>{label}</span></figcaption></figure>'
page=(out/'delivery-text-signs.html').read_text('utf8')
page=re.sub(r'<title>.*?</title>','<title>夜間自發光招牌 · 渡假大學城</title>',page)
page=re.sub(r'<h1>.*?</h1>','<h1>入夜後，店名也清楚可見</h1>',page)
page=re.sub(r'<header>(.*?)<p>.*?</p></header>',lambda m:'<header>'+m[1]+'<p>31 面亮背景、44 面亮字、47 面暖色背光暈。依店家材質選擇發光方式，同時保留凸字倒角、內縮底板與固定件；一樓橫牌及向上延伸的直牌維持原位。</p></header>',page,flags=re.S)
page=re.sub(r'<section class="gallery">.*?</section>','<section class="gallery">'+gallery+'</section>',page,flags=re.S)
comparison_html='<details><summary>相同夜間曝光：關燈／開燈對照</summary><div class="gallery">'
for bid in ['S01','S03','S09']:
 for suffix,label in [('-night-off','關閉自發光'),('-night','啟用自發光')]:
  comparison_html+=f'<figure><img loading="lazy" src="renders/{bid+suffix}.png?revision=night-v1"><figcaption>{html.escape(catalogue["building."+bid]["translations"]["zh-Hant"])} · {label}</figcaption></figure>'
page=page.replace('</section>','</section>'+comparison_html+'</div></details>',1)
page=page.replace('以下從行人高度拍攝，供檢查招牌位置與可讀性。','包含行人高度與斜角近照，檢查大字可讀性、倒角光照與高度圖視差。')
page=re.sub(r'<footer>.*?</footer>','<footer>122 棟、366 組三語字面。2.8cm 高度場使用視差遮蔽、像素深度偏移與法線；此效果在牌面內呈現凹凸，不是獨立字體網格。<a href="relief-signs-review.json">高度／材質記錄</a> · <a href="audit.json">重開圖驗收</a> · <a href="render.json">原生實景記錄</a></footer>',page,flags=re.S)
for name in ['delivery.html','delivery-night-signs.html']:(out/name).write_text(page,'utf8')
state=read(root/'.ai-collab/state.json');s=state['resort_architecture_v1'];s.update(status='accepted',map_sha256=sha(mapfile),native_checks=audit['checks'],native_issues=0,delivery=str(out/'delivery-night-signs.html'))
s['signage_revision']=dict(horizontal_ground_floor=120,vertical_ground_to_upper=2,lettering='realistic finishes with height-driven raised text and recessed backing',finish_families=accepted['signage']['finish_families'],relief_cm=2.8,native_import='passed',native_map_save='passed',native_reopen='passed',native_render_exit=0)
s['signage_revision']['self_emission']=night['counts']
write(root/'.ai-collab/state.json',state)
print('Accepted122 relief signs; map '+sha(mapfile))
]====]
local process=assert(io.popen('python -','w'));assert(process:write(code));assert(process:close())
