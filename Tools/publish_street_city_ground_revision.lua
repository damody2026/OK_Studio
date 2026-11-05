package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/ground-pbr-v2';local env=root..'/output/street-social-city-production/day-night-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(type(d)=='string' and d or json.encode(d));f:close()end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local install=read(out..'/install.json');local audit=read(out..'/audit.json');local package=read(env..'/package.json');local runtime=read(env..'/runtime-package-launch.json');local native=read(runtime.native_receipt);local captures=read(out..'/captures.json');local review=read(out..'/visual-review.json');local previous=read(root..'/output/street-social-city-production/ground-pbr-v1/captures.json')
assert(audit.status=='passed' and audit.all_1331_previous_changes_accounted and review.status=='passed' and runtime.status=='passed' and native.status=='passed' and native.world_type=='Game' and not native.python_module_loaded)
for _,v in ipairs({audit,package,runtime,captures,review})do assert(v.map_sha256==install.map_sha256)end
assert(package.engine=='E:/PhysX/UE5.8' and package.exit_code==0 and captures.package_id==package.id and review.package_id==package.id and runtime.executable==captures.executable)
assert(hash.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==install.map_sha256)
local pics,oldpics={},{};for _,r in ipairs(captures.images)do assert(hash.sha256_file(r.path)==r.sha256);pics[r.id]=r end;for _,r in ipairs(previous.images)do oldpics[r.id]=r end
local function rel(path)assert(path:sub(1,#out+1)==out..'/');return path:sub(#out+2)end
local function fig(path,label)return '<figure><a href="'..esc(path)..'"><img loading="lazy" src="'..esc(path)..'" alt="'..esc(label)..'"></a><figcaption>'..esc(label)..'</figcaption></figure>'end
local html={[=[<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>保留原地板 · 放大地表紋理</title><style>body{margin:0;background:#152322;color:#eee8d9;font:16px/1.7 system-ui,sans-serif}main{max-width:1300px;margin:auto;padding:32px 24px}h1{font-size:clamp(28px,4vw,48px)}a{color:#f1d49c}.pair,.gallery,.stats{display:grid;gap:16px}.pair{grid-template-columns:repeat(2,minmax(0,1fr))}.gallery{grid-template-columns:repeat(auto-fit,minmax(340px,1fr))}.stats{grid-template-columns:repeat(auto-fit,minmax(220px,1fr))}figure,.stats div{margin:0;background:#263733;border-radius:12px;padding:14px}img{display:block;width:100%;height:auto}figcaption{padding-top:8px}.stats b{display:block;color:#edc788;font-size:30px}h2{margin-top:42px}code{word-break:break-all;font-size:13px}@media(max-width:700px){.pair{grid-template-columns:1fr}}</style><main><p>University City / E 槽引擎 / 地表修正版</p><h1>原有地板還原<br>土粒與草葉放大到看得見</h1><p>上一版把原本合適的鋪面與地板換掉，而且地表紋理鋪得太密，正常距離仍像色塊。本版還原原有鋪石、地板、木平台、石階及導盲鋪面，將保留的 Grok 地表材質改為較大的紋理比例。</p>]=]}
html[#html+1]=string.format('<div class="stats"><div><b>%d</b>槽位恢復原有材質</div><div><b>%d</b>地表槽位放大紋理</div><div><b>5 倍</b>土壤、草坪、自然草地</div><div><b>4 倍</b>柏油、砂石、跑道與球場</div></div>',install.restored_slot_count,install.selected_slot_count)
html[#html+1]='<p>沿用上一版 Grok Build 生成的 1K 底色、派生法線與 ORM，三者使用相同放大比例。天然地面仍保留隨機取樣，連續地形共用種子與世界座標；另調整局部明暗層次，避免取樣混合後細節變淡。</p>'
for _,q in ipairs({{'pink-tree-soil-night','花樹土壤與原有鋪石'},{'picnic-night','野餐草坪夜景'},{'asphalt-road-12','柏油道路日景'},{'street-paving-21','商店街原有鋪面'}})do
 local id,label=q[1],q[2];html[#html+1]='<h2>'..label..'</h2><div class="pair">'
 local old=assert(oldpics[id]);local oldrel='../ground-pbr-v1/'..old.path:match('/ground%-pbr%-v1/(.+)$')
 html[#html+1]=fig(oldrel,'上一版：'..label);html[#html+1]=fig(rel(assert(pics[id]).path),'本版：'..label);html[#html+1]='</div>'
end
html[#html+1]='<h2>全圖實拍</h2><p>二十個戶外景點、城市俯瞰、花樹土壤、日夜道路及原有室內地板。點圖看原尺寸。</p><div class="gallery">'
for _,r in ipairs(captures.images)do html[#html+1]=fig(rel(r.path),r.id..' · '..r.hour..':00'..(r.camera_kind=='elevated ground inspection' and ' · 地表俯瞰' or ''))end
html[#html+1]='</div><h2>驗證與封裝</h2><p>全部 6,584 個網格元件的幾何、實例、變換、碰撞、可見性及陰影設定保持一致；前版 1,331 個改動槽位均已逐一對帳。新版使用 E:/PhysX/UE5.8 打包，並在實際 D3D12 Game 驗證日夜時鐘、UI、保存與讀取。受測畫面與移動截圖的檢視範圍記錄在收據中；既有全城深度衝突候選仍待逐項排除。</p>'
html[#html+1]='<p><a href="install.json">還原與比例清單</a> · <a href="audit.json">重新開圖核對</a> · <a href="visual-review.json">實拍檢視</a> · <a href="acceptance.json">交付收據</a></p><p>封裝程式：<code>'..esc(runtime.executable)..'</code></p></main></html>'
write(out..'/delivery-ground-revision.html',table.concat(html,'\n'))
write(out..'/acceptance.json',{status='passed_material_revision_global_depth_pending',map_sha256=install.map_sha256,package_id=package.id,engine=package.engine,executable=runtime.executable,restored_material_slots=install.restored_slot_count,enlarged_material_slots=install.selected_slot_count,factors=install.factors,components_preserved=6584,actual_game_images=#captures.images,visual_review=out..'/visual-review.json'})
local oldpage=root..'/output/street-social-city-production/ground-pbr-v1/delivery-ground-pbr.html';local f=assert(io.open(oldpage,'rb'));local old=f:read('*a');f:close()
if not old:find('ground-revision-latest',1,true)then old=old:gsub('<main>','<main><div id="ground-revision-latest" style="padding:18px;background:#345c48"><a href="../ground-pbr-v2/delivery-ground-revision.html">查看修正版：還原原有地板、放大地表紋理</a></div>',1);write(oldpage,old)end
print('Published: '..out..'/delivery-ground-revision.html')
