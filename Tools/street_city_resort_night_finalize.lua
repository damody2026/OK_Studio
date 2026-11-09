local code=[====[
from pathlib import Path
import json,hashlib,html,numpy as np,zipfile,io
from PIL import Image
root=Path.cwd();out=root/'output/street-social-city-production/resort-architecture-v1'
def read(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n','utf8')
install=read(out/'moonlight-install.json');audit=read(out/'moonlight-audit.json');arch=read(out/'audit.json');render=read(out/'render.json');digest=sha(root/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')
assert install['status']==audit['status']==arch['status']==render['status']=='passed'
assert install['map_sha256']==audit['map_sha256']==arch['map_sha256']==render['map_sha256']==digest
assert read(out/'audit-exit.json')['exit_code']==0 and audit['run_id']==read(out/'audit-payload.json')['run_id'],'Independent reopen audit required'
assert render['run_id']==read(out/'install-payload.json')['run_id'],'Fresh native capture required'
capture_exit=read(out/'install-exit.json')['exit_code']
assert capture_exit in [0,-1073741819],capture_exit
if capture_exit:
 log=(out/'install-editor.log').read_text('utf8',errors='replace');assert 'LogExit: Exiting.' in log and 'Log file closed' in log
native=dict(status='passed' if capture_exit==0 else 'capture_complete_shutdown_error',run_id=render['run_id'],native_exit_code=capture_exit,images=len(render['images']),map_sha256=digest,independent_reopen_exit_code=0,limitation='Offscreen editor exits with access violation after complete capture and normal shutdown log;cause unresolved.' if capture_exit else None)
write(out/'moonlight-native-run.json',native)
images={r['name']:r for r in render['images']};quality=[]
for r in render['images']:assert sha(Path(r['path']))==r['sha256']
moon=read(out/'moon-disc-review.json');assert moon['diameter_multiplier']==6 and audit['moon_diameter_multiplier']==6
def moon_bbox(im):
 a=np.asarray(im.convert('RGB'))[180:390,900:1160];ys,xs=np.where(a.min(axis=2)>80);assert len(xs)>20;return dict(width=int(xs.max()-xs.min()+1),height=int(ys.max()-ys.min()+1),pixels=int(len(xs)))
with zipfile.ZipFile(out/'backups/before-moon-disc-v2.zip') as z:
 old=moon_bbox(Image.open(io.BytesIO(z.read(next(n for n in z.namelist() if n.endswith('S03-skyline.png'))))))
new=moon_bbox(Image.open(images['S03-skyline']['path']));assert new['width']>=old['width']*4 and new['width']>40,(old,new)
write(out/'moon-disc-visual-review.json',dict(status='passed',same_camera_before=old,after=new,diameter_pixel_ratio=new['width']/old['width'],native_map_sha256=digest,description='Larger ivory lunar disc with procedural maria,crater bowls/rims and soft additive halo.'))
for bid in ['S01','S03','S09','H1','E1','R1','TR']:
 r=images[bid+'-moonlight'];im=np.asarray(Image.open(r['path']).convert('RGB'),dtype=float);lum=im.mean(axis=2);q=dict(view=r['name'],mean_luminance=float(lum.mean()),visible_pixels_percent=float((lum>15).mean()*100),clipped_pixels_percent=float((lum>250).mean()*100));assert q['visible_pixels_percent']>35,q;quality.append(q)
pairs=[]
for bid in ['S01','S03','S09']:
 a,b=images[bid+'-night'],images[bid+'-night-off'];assert all(a['camera'][k]==b['camera'][k] for k in ['eye','target','fov']);x=np.asarray(Image.open(a['path']).convert('RGB'),dtype=float);y=np.asarray(Image.open(b['path']).convert('RGB'),dtype=float);delta=(x-y).mean(axis=2)[350:650,160:1440];assert (delta>10).sum()>300; pairs.append(dict(id=bid,pixels_increased_over_10=int((delta>10).sum())))
write(out/'moonlight-visual-review.json',dict(status='passed',scenes=quality,self_emission_pairs=pairs,excluded_views=[dict(view='LI-moonlight',reason='Camera is inside adjacent building;not accepted as an exterior view.')],note='Numerical visibility checks supplement human inspection;blocked library exterior view excluded from gallery.'))
titles={'S03-skyline':'商店街 · 月下屋頂與夜空','H1-skyline':'旅館 · 夜空與庭園燈','S01-moonlight':'商店街 · 暖色庭園燈','S03-moonlight':'餐飲街 · 入口光池','S09-moonlight':'店面 · 暖光與冷月光','H1-moonlight':'旅館 · 夜間迎賓','E1-moonlight':'校園 · 月下步道','R1-moonlight':'住宅 · 夜間歸途','TR-moonlight':'交通入口 · 清楚的街道輪廓'}
gallery=''.join(f'<figure><a href="renders/{view}.png?rev=moon-v2"><img src="renders/{view}.png?rev=moon-v2" loading="lazy" alt="{title}"></a><figcaption>{title}</figcaption></figure>' for view,title in titles.items())
page='''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>月光渡假大學城</title><style>body{margin:0;background:#0c1723;color:#eee7d4;font:17px/1.7 system-ui}main{max-width:1440px;margin:auto;padding:40px 24px}h1{font-size:clamp(32px,5vw,60px);margin-bottom:10px}p{max-width:1000px;color:#c7d6e6}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:24px}figure{margin:0;background:#162638;border-radius:12px;overflow:hidden}img{display:block;width:100%}figcaption{padding:16px;color:#ffe2ab}a{color:#f0ca88}footer{margin-top:32px;color:#a9b9c8}@media(max-width:600px){.gallery{grid-template-columns:1fr}}</style><main><h1>月光照著街道，暖燈陪你散步</h1><p>122 座青銅庭園路燈搭配 122 座低位步道燈，以 2700–2800K 暖光照亮入口與步道。燈罩、乳白燈芯、細柱與石材基座形成渡假村的街道語彙；偏冷月光補出屋頂、樹木和建築輪廓，讓夜晚仍有可讀的層次。</p><p>以下皆為 Unreal 主地圖原生拍攝。新燈具與夜間照明已保存；122 面自發光大字招牌及 427 個原有樓層保留。月光採美術調整亮度，兼顧夜色情緒與行走辨識。</p><section class="gallery">'''+gallery+'''</section><footer><a href="moonlight-audit.json">燈具重開驗收</a> · <a href="moonlight-visual-review.json">夜景可見度檢查</a> · <a href="render.json">原生拍攝記錄</a> · <a href="delivery-night-signs.html">招牌細節</a></footer></main></html>'''
for name in ['delivery-moonlight.html','delivery.html']:(out/name).write_text(page,'utf8')
page=page.replace('<section class="gallery">','<p>月亮已放大為前版直徑的 6 倍，加入象牙白月色、深淺月海、環形坑紋理與柔和光暈，與原有冷色月光及暖色路燈搭配。</p><section class="gallery">')
for name in ['delivery-moonlight.html','delivery.html']:(out/name).write_text(page,'utf8')
if capture_exit:
 page=page.replace('<footer>','<footer><p>驗收說明：圖片已完整產出，主地圖獨立重開檢查通過。離屏拍攝程序在結束時仍有引擎退出錯誤（-1073741819），原因尚未排除；此項另列為交付限制。</p>')
 for name in ['delivery-moonlight.html','delivery.html']:(out/name).write_text(page,'utf8')
accepted=read(out/'acceptance.json');accepted.update(status='passed',map_sha256=digest,native_checks=arch['checks']+audit['checks'],native_issues=[],native_render_images=len(render['images']),night_environment=dict(lanterns=122,bollards=122,moon_lux=install['moon_lux'],sky_intensity=install['sky_intensity'],temperature_kelvin=[2700,2800],persistent=True));accepted.setdefault('receipts',{}).update({n:sha(out/n) for n in ['moonlight-install.json','moonlight-audit.json','moonlight-visual-review.json','audit.json','render.json']});write(out/'acceptance.json',accepted)
for name in list(accepted.get('source_sha256',{}))+['Tools/street_city_resort_night.lua','Tools/street_city_resort_night_payload.lua','Tools/street_city_resort_night_finalize.lua']:
 accepted.setdefault('source_sha256',{})[name]=sha(root/name)
for name in ['install.json','moonlight-native-run.json','install-payload.json','audit-payload.json','install-exit.json','audit-exit.json']:accepted['receipts'][name]=sha(out/name)
accepted['receipts'].pop('render-exit.json',None) # Captures ran in install process;use its actual native exit receipt.
accepted.update(status='passed_with_renderer_shutdown_error' if capture_exit else 'passed',native_exit_codes=dict(capture_install=capture_exit,independent_reopen_audit=0),renderer_shutdown_limitation=native['limitation']);write(out/'acceptance.json',accepted)
accepted['visually_selected_gallery_images']=list(titles);write(out/'acceptance.json',accepted)
accepted['night_environment']['moon_diameter_multiplier']=6
for name in ['moon-disc-review.json','moon-disc-visual-review.json']:accepted['receipts'][name]=sha(out/name)
write(out/'acceptance.json',accepted)
state=read(root/'.ai-collab/state.json');state['resort_architecture_v1'].update(status='accepted_with_renderer_shutdown_limitation' if capture_exit else 'accepted',map_sha256=digest,native_checks=accepted['native_checks'],native_issues=0,delivery=str(out/'delivery-moonlight.html'),night_environment=accepted['night_environment'],renderer_shutdown_limitation=native['limitation']);write(root/'.ai-collab/state.json',state)
print('Moonlight accepted: '+digest)
]====]
local p=assert(io.popen('python -','w'));assert(p:write(code));assert(p:close())
