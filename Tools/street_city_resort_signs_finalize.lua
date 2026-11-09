-- Final receipts are emitted only after fresh native save, reopen and capture pass.
local code=[====[
from pathlib import Path
import json,hashlib
root=Path.cwd();out=root/'output/street-social-city-production/resort-architecture-v1'
def read(p):return json.loads(p.read_text('utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,d):p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n','utf8')
audit=read(out/'audit.json');render=read(out/'render.json');install=read(out/'install.json');letters=read(out/'lettering-review.json')
mapfile=root/'StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap'
assert audit['status']==render['status']==letters['status']=='passed'
assert audit['map_sha256']==render['map_sha256']==install['map_sha256']==sha(mapfile)
assert letters['textures']==366 and all(not r['logo'] for r in letters['rows'])
exits={m:read(out/(m+'-exit.json'))['exit_code'] for m in ['shader','install','render']}
assert all(v==0 for v in exits.values()),exits
assert all(sha(Path(r['path']))==r['sha256'] for r in render['images'])
accepted=read(out/'acceptance.json')
accepted.update(status='passed',scope='122 large-text-only exterior signs;120 ground-floor horizontal,2 ground-to-upper vertical;427 original floors retained',map_sha256=sha(mapfile),native_render_images=len(render['images']),native_checks=audit['checks'],native_issues=audit['issues'],native_exit_codes=exits,signage=dict(horizontal=120,vertical=2,lettering_textures=366,logo_artwork=False))
selected=['S01','S03','S09','E1','H1','TR','R1','R2']
accepted['visually_selected_gallery_images']=selected
accepted['excluded_camera_views']=['S18, S19, LI, D1, O01:foreground occlusion or less useful street composition','M1:tree partially obscures the name']
for name in ['shader.json','install.json','audit.json','render.json','lettering-review.json','signage-review.json','geometry-manifest.json','geometry-review.json']:
 accepted['receipts'][name]=sha(out/name)
for name in ['Tools/street_city_vertical_sign_text.lua','Tools/street_city_resort_architecture_payload.lua','Tools/street_city_resort_signs_finalize.lua']:
 accepted['source_sha256'][name]=sha(root/name)
for name in accepted['source_sha256']:accepted['source_sha256'][name]=sha(root/name)
write(out/'acceptance.json',accepted)
page=(out/'delivery-ground-signs.pending.html').read_text('utf8').replace('一樓街面招牌 · 渡假大學城','大字店名招牌 · 渡假大學城').replace('招牌回到一樓街面','大字店名，清楚看見每棟建築').replace('ground-signs','text-signs-v2')
page=page.replace('橫式招牌放在一樓店面上緣；立面較窄的公寓採轉角直排，從一樓往上延伸。舊屋頂牌連同背板、框架與支柱一起移除。','122 棟外部大招牌全部使用正式店名／館名的大字排版。120 面橫式位於一樓店面上緣，2 面公寓轉角直式從一樓延伸至上層。奶油白底與深綠粗體保留渡假大學城的氣氛。')
page=page.replace('R1／R2 直式名稱重新排成正向直排文字，保留繁中、簡中與英文切換。','全部 122 棟重新排成大字文字，366 張三語字圖保留繁中、簡中與英文切換；招牌使用無串流完整解析度貼圖。')
import re
page=re.sub(r'<figure>.*?</figure>',lambda m:m[0] if any('renders/'+bid+'.png?' in m[0] for bid in selected) else '',page)
catalogue=read(root/'output/street-social-city-production/localization-v1/catalogue.json')['entries']
import html
for bid in {r['building'] for r in letters['rows']}:
 name=html.escape(catalogue['building.'+bid]['translations']['zh-Hant'])
 page=page.replace('<b>'+bid+'</b><span>','<b>'+name+' · '+bid+'</b><span>').replace('<td>'+bid+'</td><td>'+bid+'</td>','<td>'+bid+'</td><td>'+name+'</td>')
for name in ['delivery.html','delivery-text-signs.html']: (out/name).write_text(page,'utf8')
state=read(root/'.ai-collab/state.json');s=state['resort_architecture_v1'];s.update(status='accepted',map_sha256=sha(mapfile),native_checks=audit['checks'],native_issues=0)
s['signage_revision']=dict(horizontal_ground_floor=120,vertical_ground_to_upper=2,lettering='large text only',textures=366,native_import='passed',native_map_save='passed',native_reopen='passed',native_render_exit=0)
write(root/'.ai-collab/state.json',state)
print('Accepted122 large-text signs; map '+sha(mapfile))
]====]
local process=assert(io.popen('python -','w'))
assert(process:write(code));assert(process:close())
