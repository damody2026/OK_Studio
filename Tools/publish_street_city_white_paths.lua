package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash');local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/white-paths-v1';local prev=root..'/output/street-social-city-production/ground-pbr-v2'
local function read(p)local f=assert(io.open(p,'rb'));local t=f:read('*a');f:close();return json.decode(t)end
local function raw(p)local f=assert(io.open(p,'rb'));local t=f:read('*a');f:close();return t end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(type(d)=='string' and d or json.encode(d));f:close()end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local install=read(out..'/install.json');local audit=read(out..'/audit.json');local package=read(root..'/output/street-social-city-production/day-night-v1/package.json');local reused=read(out..'/reused-runtime.json');local captures=read(out..'/captures.json');local review=read(out..'/visual-review.json');local previous=read(prev..'/captures.json')
assert(audit.status=='passed' and audit.path_slots==31 and audit.unchanged_previous_ground_slots==137 and review.status=='passed' and reused.status=='passed')
for _,v in ipairs({audit,package,reused,captures,review})do assert(v.map_sha256==install.map_sha256)end
assert(package.engine=='E:/PhysX/UE5.8' and package.exit_code==0 and captures.package_id==package.id and review.package_id==package.id and captures.exit_code==0)
assert(hash.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==install.map_sha256 and hash.sha256_file(captures.executable)==reused.executable_sha256)
local pics,oldpics={},{};for _,r in ipairs(captures.images)do assert(hash.sha256_file(r.path)==r.sha256);pics[r.id]=r end;for _,r in ipairs(previous.images)do oldpics[r.id]=r end
local function fig(path,label)return '<figure><a href="'..esc(path)..'"><img loading="lazy" src="'..esc(path)..'" alt="'..esc(label)..'"></a><figcaption>'..esc(label)..'</figcaption></figure>'end
local function rel(p)assert(p:sub(1,#out+1)==out..'/');return p:sub(#out+2)end
local style=assert(raw(prev..'/delivery-ground-revision.html'):match('<style>(.-)</style>'))
local html={'<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>白色步道與平台 · 石板鋪面修正</title><style>'..style..'</style><main><p>University City / E 槽引擎</p><h1>白色步道與平台<br>改成看得見板縫的石材</h1><p>全圖盤點並修正 31 個同類步道、平台及野餐區銜接坡道材質槽位。以既有 Grok Build 生成的 1K PBR 石板紋理替換常數白色，約 80 × 40 公分的板塊帶有清楚接縫，表面法線與粗糙度採一致座標。</p><p>保留上一版的灰色商店街鋪石、室內地板，以及已放大的草地、土壤與柏油；幾何、實例、碰撞及可見性均未改動。</p>'}
for _,id in ipairs({'PK-0110-day','picnic-night','PK-0104-day','PK-0117-day'})do
 local old=assert(oldpics[id]);html[#html+1]='<h2>'..id..'</h2><div class="pair">'..fig('../ground-pbr-v2/'..old.path:match('/ground%-pbr%-v2/(.+)$'),'修正前：白色步道／平台')..fig(rel(assert(pics[id]).path),'修正後：大板石材鋪面')..'</div>'
end
html[#html+1]='<h2>全圖日夜實拍</h2><p>以下為本次新封裝的實際 D3D12 Game 截圖，點圖查看原尺寸。</p><div class="gallery">'
for _,r in ipairs(captures.images)do html[#html+1]=fig(rel(r.path),r.id..' · '..r.hour..':00')end
html[#html+1]='</div><h2>驗證與封裝</h2><p>重新開圖逐項核對 31 個新鋪面槽位與全體 6,584 個元件；前版 137 個地表材質綁定維持一致。本次沿用已驗證的同一遊戲執行檔與引擎，僅重新 cook 材質與地圖，並在新封裝重新實拍。完整日夜時鐘、UI 與效能測試沿用前版同一執行檔的成功收據，沒有把它標成本圖重跑的結果。受測圖片的檢視不代表全城深度衝突均已排除。</p><p><a href="path-plan.json">全圖同類白色鋪面盤點</a> · <a href="audit.json">重新開圖核對</a> · <a href="visual-review.json">實拍檢視</a> · <a href="reused-runtime.json">同執行檔測試沿用依據</a> · <a href="acceptance.json">交付收據</a></p><p>封裝程式：<code>'..esc(captures.executable)..'</code></p></main></html>'
write(out..'/delivery-white-paths.html',table.concat(html,'\n'))
write(out..'/acceptance.json',{status='passed_white_path_material_scope',package_id=package.id,map_sha256=install.map_sha256,engine=package.engine,executable=captures.executable,white_path_slots=31,unchanged_previous_ground_slots=137,components_preserved=6584,actual_game_images=#captures.images,visual_review=out..'/visual-review.json',full_clock_tests='Reused from byte-identical executable; fresh rendered image validation covers this material-only map revision',global_depth_status='Existing candidates remain pending'})
local oldpage=prev..'/delivery-ground-revision.html';local old=raw(oldpage);if not old:find('white-paths-latest',1,true)then old=old:gsub('<main>','<main><div id="white-paths-latest" style="padding:18px;background:#345c48"><a href="../white-paths-v1/delivery-white-paths.html">查看最新：白色步道與平台的石板鋪面修正</a></div>',1);write(oldpage,old)end
print('Published: '..out..'/delivery-white-paths.html')
