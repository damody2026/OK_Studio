package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash');local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/flat-campus-v1'
local function raw(p)local f=assert(io.open(p,'rb'));local t=f:read('*a');f:close();return t end
local function read(p)return json.decode(raw(p))end
local function write(p,v)local f=assert(io.open(p,'wb'));f:write(type(v)=='string' and v or json.encode(v));f:close()end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local install=read(out..'/install.json');local audit=read(out..'/audit.json');local captures=read(out..'/captures.json');local review=read(out..'/visual-review.json');local package=read(root..'/output/street-social-city-production/day-night-v1/package.json')
local exterior=read(out..'/exterior-geometry-check.json');assert(exterior.status=='passed' and exterior.samples==68 and exterior.map_sha256==install.map_sha256)
local site_grade=read(out..'/flat_site_grade.json');assert(site_grade.status=='passed' and site_grade.paving_cm==1202 and site_grade.map_sha256==install.map_sha256)
local boundary=read(out..'/boundary-footprint-review.json');assert(boundary.status=='passed' and boundary.map_sha256==install.map_sha256)
local annex=read(out..'/annex-grade.json');local depth=read(out..'/annex-depth-proof.json');assert(annex.status=='passed' and annex.map_sha256==install.map_sha256 and annex.never_distance_cull and depth.status=='passed' and depth.top_cm==1198 and depth.bottom_cm==1188)
assert(install.enclosure.school_name=='影輝大學' and review.school_name=='影輝大學')
assert(audit.status=='passed' and audit.material_bindings_preserved and audit.components_preserved==6584 and #audit.threshold_probes==102 and #audit.gate_capsule_sweeps==5)
assert(review.status=='passed' and package.engine=='E:/PhysX/UE5.8' and package.exit_code==0 and package.id==captures.package_id and package.id==review.package_id)
for _,r in ipairs({audit,captures,review,package})do assert(r.map_sha256==install.map_sha256)end
assert(hash.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==install.map_sha256)
local images={};for _,r in ipairs(captures.images)do assert(hash.sha256_file(r.path)==r.sha256);images[r.id]=r end;assert(#captures.images==35)
for _,r in ipairs(audit.gate_capsule_sweeps)do assert(not r.blocked)end
local function fig(id,label)local r=assert(images[id]);local path=r.path:sub(#out+2);return '<figure><a href="'..esc(path)..'"><img loading="lazy" src="'..esc(path)..'" alt="'..esc(label)..'"></a><figcaption>'..esc(label)..'</figcaption></figure>'end
local html={'<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>影輝大學・整平校園與五座校門</title><style>body{margin:0;background:#102422;color:#e7efea;font:17px/1.7 Microsoft JhengHei,sans-serif}main{max-width:1500px;margin:auto;padding:36px}h1{font-size:46px;color:#e7dcb6}h2{margin-top:48px}a{color:#a4d7c5}figure{margin:0;background:#1d3430;border-radius:10px;overflow:hidden}img{width:100%;display:block}figcaption{padding:12px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:20px}code{overflow-wrap:anywhere}.note{padding:20px;background:#23463e;border-radius:8px}</style><main><p>University City · E:/PhysX/UE5.8</p><h1>影輝大學<br>平整校園與五座校門</h1><p>將原本 12m 商店區、20m 校園及山丘地形整理成以 12m 為主的平坦陸地。建築連同外觀、樓層、室內物件一同移位；植栽、燈具與戶外景點同步調整，水域保留較低水位。</p><div class="note">五座校門以「影輝大學」大字標示，採深底暖光字與雙面門楣。圍欄開口銜接既有步道，原生膠囊穿越五座校門均未遇阻擋。</div><h2>校園全貌</h2>'}
html[#html+1]=fig('campus-overview','新封裝實際 Game · 校園圍界與五處出入口')
html[#html+1]='<h2>校門與夜間校名</h2><div class="grid">'
for _,q in ipairs({{'SouthMain','南門'},{'SouthWalk','學生活動門'},{'WestSport','西門'},{'NorthDorm','北門'},{'EastGarden','東門'}})do html[#html+1]=fig('gate-'..q[1]..'-12',q[2]..' · 12:00')end
html[#html+1]=fig('gate-SouthMain-21','南門 · 21:00')..'</div><h2>入口與戶外地面</h2><div class="grid">'
for _,q in ipairs({{'campus-AD-threshold','行政中心入口'},{'campus-reading-ground','校園閱讀區地面'},{'campus-city-connection','校園與市區銜接'},{'PK-0102-day','噴泉花園與石板地面'}})do html[#html+1]=fig(q[1],q[2])end
html[#html+1]='</div><h2>二十處戶外景點</h2><div class="grid">'
for i=101,120 do local id='PK-'..string.format('%04d',i)..'-day';html[#html+1]=fig(id,id)end
html[#html+1]='</div><h2>全圖整平檢查</h2><div class="grid">'
for _,x in ipairs({27500,82500})do for _,y in ipairs({27500,82500})do html[#html+1]=fig('flat-city-'..x..'-'..y,'全圖分區俯視 '..x..', '..y)end end
html[#html+1]=fig('annex-ground-connection','校外體育場與市區地面銜接')
html[#html+1]='</div><h2>使用者回報的原畫面</h2><div class="grid"><figure><img src="reference-campus-overhead.jpg"><figcaption>原回報：校園地面高低不連續</figcaption></figure><figure><img src="reference-entrance.jpg"><figcaption>原回報：入口平台浮空</figcaption></figure></div><h2>驗收範圍</h2><p>247 個地面相關網格更新所有 LOD，碰撞以新幾何重建。原有 6,584 個元件的材質與碰撞設定保留；17 棟校園建築共 102 處入口支撐採樣落在 1200–1204.722cm，五座校門均有地面支撐並可讓膠囊通過。建築外側殘留低窪另行補平，PK-0112 不同高度的步道及家具一併校正，68 處地面三角形交點檢查落在 1198–1204.166cm。校門新鋪面與既有步道保留 1.5cm 深度間距。</p><p>本頁 35 張照片來自新封裝 D3D12 Game，日夜時間由原生時鐘確認。未重跑完整 24 小時時鐘、UI 或效能專項；局部實拍與幾何檢查也不代表全城所有 z-fighting 候選都已排除。</p><p><a href="audit.json">原生地面與通行檢查</a> · <a href="visual-review.json">實拍檢視紀錄</a> · <a href="acceptance.json">封裝交付收據</a></p><p>新封裝：<code>'..esc(captures.executable)..'</code></p></main></html>'
write(out..'/delivery-flat-campus.html',table.concat(html,'\n'));write(out..'/acceptance.json',{status='passed_flat_campus_rendered_scope',map_sha256=install.map_sha256,package_id=package.id,engine=package.engine,executable=captures.executable,meshes=247,existing_components_preserved=6584,campus_gates=5,threshold_samples=102,gate_clearance_sweeps=5,actual_game_images=35,scope='Flat city geometry, campus boundary and five named gates; sampled native support/clearance and actual D3D12 visual review',limitations='No fresh full 24h/UI/performance run and no global zero-depth-conflict claim'})
local previous=root..'/output/street-social-city-production/pk0102-floor-v1/delivery-PK0102-floor.html';local old=raw(previous)
if not old:find('flat-campus-latest',1,true)then old=old:gsub('<main>','<main><p id="flat-campus-latest" style="padding:18px;background:#345c48"><a href="../flat-campus-v1/delivery-flat-campus.html">查看最新：影輝大學整平校園與五座校門實拍</a></p>',1);write(previous,old)end
print('Published '..out..'/delivery-flat-campus.html')
