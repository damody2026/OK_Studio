package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local json=require('ok.json');local hash=require('ok.hash');local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/pk0102-floor-v1';local prev=root..'/output/street-social-city-production/white-paths-v1'
local function raw(p)local f=assert(io.open(p,'rb'));local t=f:read('*a');f:close();return t end
local function read(p)return json.decode(raw(p))end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(type(d)=='string' and d or json.encode(d));f:close()end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local install=read(out..'/install.json');local audit=read(out..'/audit.json');local captures=read(out..'/captures.json');local review=read(out..'/visual-review.json');local reused=read(out..'/reused-runtime.json');local package=read(root..'/output/street-social-city-production/day-night-v1/package.json')
local bindings=read(out..'/runtime-material-bindings.json');assert(bindings.status=='passed' and bindings.slots==17 and bindings.package_id==package.id and bindings.map_sha256==install.map_sha256)
assert(audit.status=='passed' and audit.changed_slots==17 and audit.all_other_bindings_preserved and review.status=='passed' and reused.status=='passed' and package.exit_code==0 and package.engine=='E:/PhysX/UE5.8')
for _,v in ipairs({audit,captures,review,reused,package})do assert(v.map_sha256==install.map_sha256)end
assert(captures.package_id==package.id and review.package_id==package.id and #captures.images==3 and captures.exit_code==0)
assert(hash.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==install.map_sha256 and hash.sha256_file(captures.executable)==reused.executable_sha256)
local pics={};for _,r in ipairs(captures.images)do assert(hash.sha256_file(r.path)==r.sha256);pics[r.id]=r end
local previous=read(prev..'/captures.json');local before;for _,r in ipairs(previous.images)do if r.id=='PK-0102-day'then before=r end end;assert(before)
local function fig(path,label)return '<figure><a href="'..esc(path)..'"><img src="'..esc(path)..'" alt="'..esc(label)..'"></a><figcaption>'..esc(label)..'</figcaption></figure>'end
local function rel(p)assert(p:sub(1,#out+1)==out..'/');return p:sub(#out+2)end
local style=assert(raw(prev..'/delivery-white-paths.html'):match('<style>(.-)</style>'))
local html={'<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PK-0102 實際平台地板修正</title><style>'..style..'</style><main><p>University City / E 槽引擎</p><h1>PK-0102<br>修正實際顯示的平台地板</h1><p>漏修原因是活動平台覆蓋了原場景：World_PK_0102 已隱藏，實際入鏡的是 Activity_ACTSPACE-02-7 的 platform_LOD0。該地板元件保留了 17 個同名 M_Surface_7 綁定；僅改離線三角形顯示的第 16 號槽，第一次實景仍維持原色。因此本版統一替換此地板元件的全部同名綁定，保留其他元件的材質、噴泉、家具、平台高度與碰撞。</p><p>約 18 × 24 公尺的平台採世界座標石板鋪設，板塊約 80 × 40 公分。沿用既有 Grok Build 1K PBR 材質，底色、法線與粗糙度共用取樣比例。</p><h2>同鏡位：12:00</h2><div class="pair">'}
html[#html+1]=fig('../white-paths-v1/'..before.path:match('/white%-paths%-v1/(.+)$'),'修正前：實際活動平台仍是單色')
html[#html+1]=fig(rel(assert(pics['PK-0102-day']).path),'修正後：實際活動平台的石板地面')
html[#html+1]='</div><h2>夜景與近景</h2><div class="pair">'..fig(rel(assert(pics['PK-0102-night']).path),'21:00 同鏡位')..fig(rel(assert(pics['PK-0102-floor-close']).path),'12:00 地面近景')..'</div>'
html[#html+1]='<h2>驗證</h2><p>重新開圖確認實際可見的平台與全部 17 個同名綁定，全部 6,584 個元件的幾何、碰撞與其他元件材質保持一致。新封裝以實際 D3D12 Game 拍攝本頁三張照片；沿用同 SHA 遊戲執行檔既有的時鐘、UI 與效能測試，不把先前測試標成此次重新執行。受測圖片不代表全城深度衝突均已排除。</p><p><a href="audit.json">實際槽位核對</a> · <a href="visual-review.json">實拍檢視</a> · <a href="acceptance.json">交付收據</a></p><p>封裝程式：<code>'..esc(captures.executable)..'</code></p></main></html>'
write(out..'/delivery-PK0102-floor.html',table.concat(html,'\n'));write(out..'/acceptance.json',{status='passed_visible_PK0102_floor_scope',package_id=package.id,map_sha256=install.map_sha256,engine=package.engine,executable=captures.executable,changed_slots=17,changed_floor_components=1,target=install.target_change,target_slots=audit.target_slots,components_preserved=6584,all_other_bindings_preserved=true,actual_game_images=3,visual_review=out..'/visual-review.json',functional_tests='Reused from identical executable; fresh rendered captures verify the platform material revision',global_depth_status='Existing candidates remain pending'})
local page=prev..'/delivery-white-paths.html';local old=raw(page);if not old:find('PK0102-floor-latest',1,true)then old=old:gsub('<main>','<main><div id="PK0102-floor-latest" style="padding:18px;background:#345c48"><a href="../pk0102-floor-v1/delivery-PK0102-floor.html">查看最新：PK-0102 實際平台地板修正與同鏡位對照</a></div>',1);write(page,old)end
print('Published: '..out..'/delivery-PK0102-floor.html')
