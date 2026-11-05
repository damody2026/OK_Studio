-- Publish recorded native captures; no map, asset or acceptance-state mutation.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json')
local root='C:/portable/OpenKoikatsu/output/street-social-city-production/day-night-v1/'
local function read(name,optional)
 local f=io.open(root..name..'.json','rb');if not f then assert(optional,name..' missing');return nil end
 local s=f:read('*a');f:close();return json.decode(s)
end
local function write(name,s)local f=assert(io.open(root..name,'wb'));f:write(s);f:close()end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local current=read('current-map');local render=read('render-full');local audit=read('audit')
assert(render.map_sha256==current.map_sha256 and audit.map_sha256==current.map_sha256 and audit.status=='passed','Fresh map/capture/audit required')
assert(render.status=='passed' or render.status=='captured_with_missing_cameras')
local images={};local ids={};local representatives={};local site_ids={};local cameras=read('cameras');assert(cameras.map_sha256==current.map_sha256)
for _,r in ipairs(cameras.rows)do site_ids[r.id]=true end
local names={['hotel-garden']='飯店花園',['campus-lake']='湖畔木平台',['shop-dining']='商店街',['bay-camp']='露營入口',['sports-entry']='運動場入口',['public-park']='校門廣場'}
local labels=assert(io.open('openspec/changes/resort-day-night-cycle/outdoor-lighting-plan.md','rb'));local labeltext=labels:read('*a');labels:close()
for id,name in labeltext:gmatch('|%s*([%w%-]+)%s*|%s*([^|\r\n]+)%s*|')do if site_ids[id]then names[id]=name:gsub('%s+$',''):gsub('／.*','')end end
for _,r in ipairs(render.images)do
 local file=r.files.ldr;assert(file and file.sha256)
 local relative=assert(file.path:gsub('\\','/'):match('day%-night%-v1/(.*)'));assert(not relative:find('..',1,true))
 local f=assert(io.open(root..relative,'rb'));assert(f:seek('end')>1000);f:close()
 local kind=site_ids[r.id] and 'site' or r.id=='moon-skyline' and 'moon' or 'representative'
 images[#images+1]={id=r.id,name=r.name,hour=r.hour,path=relative,kind=kind}
 if kind=='representative' and not ids[r.id]then representatives[#representatives+1]=r.id;ids[r.id]=true end
end
local pending={};local f=assert(io.open('openspec/changes/resort-day-night-cycle/tasks.md','rb'));local tasks=f:read('*a');f:close()
for id in tasks:gmatch('%- %[ %] (%d+%.%d+)')do pending[#pending+1]=id end
local runtime={}
for _,mode in ipairs({'editor','pie','package'})do
 local r=read('runtime-'..mode..'-launch',true)
 runtime[mode]=r and {status=r.status,current_map=r.map_sha256==current.map_sha256,map_sha256=r.map_sha256,native_receipt=r.native_receipt,exit_code=r.exit_code,engine=r.engine,renderer=r.renderer,visual_scope=r.visual_scope} or {status='not_run',current_map=false}
end
local lighting=read('lighting-calibration',true);local depth=read('depth-review-current',true);local routes=read('routes',true);local visual=read('visual-review-current',true)
local acceptance={status='incomplete',map_sha256=current.map_sha256,captures={status=render.status,count=#images,representative_views=#representatives,missing_cameras=render.missing_cameras or {}},runtime=runtime,lighting=lighting and {status=lighting.status} or {status='not_measured'},depth=depth and {status=depth.status,map_sha256=depth.map_sha256} or {status='not_accepted'},routes=routes and {status=routes.status,map_sha256=routes.map_sha256} or {status='not_run'},remaining_spec_tasks=pending,note='A completed capture job does not mean whole-city visual/depth/runtime acceptance. Unchecked requirements and missing camera viewpoints remain explicit.'}
if lighting then
 acceptance.lighting.map_sha256=lighting.source_map_sha256
 acceptance.lighting.current_map=lighting.source_map_sha256==current.map_sha256
end
if visual then acceptance.visual={status=visual.status,current_map=visual.map_sha256==current.map_sha256,review=visual.all_sites,browser_ui=visual.browser_ui} end
write('acceptance-current.json',json.encode(acceptance))
local html={[=[<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>大學城｜日夜與戶外景點</title><style>
*{box-sizing:border-box}body{margin:0;background:#0b1522;color:#e9edf0;font:16px/1.7 system-ui,sans-serif}main{max-width:1540px;margin:auto;padding:30px}h1{font-size:30px;margin:0}h2{margin-top:34px}p{color:#b6c6d2;max-width:1000px}a{color:#c0e2d5}select,input,button{font:inherit;background:#203444;color:#fff;border:1px solid #56707c;border-radius:6px;padding:8px}nav{display:flex;gap:14px;flex-wrap:wrap;align-items:center;margin:22px 0}figure{margin:0;background:#142638;border:1px solid #30465a;border-radius:10px;overflow:hidden}img{display:block;width:100%;aspect-ratio:16/9;object-fit:contain;background:#101a25}figcaption{padding:10px 15px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:18px}.note{border-left:3px solid #cca96a;padding:8px 18px;background:#172735}.meta{font-size:13px;color:#91a8bb}details{margin:30px 0}#hero{max-width:1200px}@media(max-width:600px){main{padding:16px}.grid{grid-template-columns:1fr}}
</style><main><h1>大學城｜日夜與戶外景點</h1><p>深色招牌與暖白亮字、開放葉叢花樹、柔和路燈和深藍夜空。以下都是同一版地圖的原生 Unreal 實拍，可切換時刻查看。</p><p class="note">整體驗收仍有待完成項目；未通過的鏡位與檢查保留在頁面下方。</p><h2>全天光照</h2><nav><label>鏡位 <select id="view"></select></label><label>時間 <input id="hour" type="range" min="0" max="23" value="21"> <output id="clock">21:00</output></label></nav><figure id="hero"><a id="heroLink"><img id="heroImage" alt="原生全天光照"></a><figcaption id="heroCaption"></figcaption></figure><h2>戶外景點</h2><nav><label>時段 <select id="siteHour"><option value="17.5">17:30 藍調</option><option value="21" selected>21:00 夜景</option><option value="2">02:00 深夜</option></select></label></nav><div id="sites" class="grid"></div><h2>待處理鏡位</h2><div id="missing"></div>]=]}
html[#html+1]='<details><summary>驗收記錄</summary><p>原生畫面 '..#images..' 組；代表鏡位 '..#representatives..' 組。完整日夜、PIE、打包及深度驗收依各自收據判定。</p><p class="meta">主圖 SHA256：'..esc(current.map_sha256)..'</p><a href="acceptance-current.json">目前驗收與未完成清單</a> · <a href="render-full.json">拍攝收據</a> · <a href="delivery-visual-polish.html">招牌與花樹近照</a></details>'
if visual and visual.map_sha256==current.map_sha256 and type(visual.all_sites)=='table' then
 html[#html+1]='<p class="note">畫面細修清單：D017／D030／E034 的前景取景過近；PK-0114／PK-0115 目前只呈現運動場邊緣；D010／D024 背景松樹仍保留原本的叢簇造型。這些畫面已保留供比對，尚未列為最終視覺通過。</p>'
end
local payload=json.encode({images=images,representatives=representatives,names=names,missing=render.missing_cameras or {}}):gsub('<','\\u003c')
html[#html+1]='<script>const data='..payload..[=[;
const $=s=>document.querySelector(s),name=id=>data.names[id]||id;for(const id of data.representatives){const o=document.createElement('option');o.value=id;o.textContent=name(id);$('#view').append(o)}
function clock(h){return String(Math.floor(h)).padStart(2,'0')+':'+(h%1?'30':'00')}
function hero(){const r=data.images.find(r=>r.kind==='representative'&&r.id===$('#view').value&&r.hour===Number($('#hour').value));$('#clock').textContent=clock(Number($('#hour').value));if(!r)return;$('#heroImage').src=r.path;$('#heroLink').href=r.path;$('#heroCaption').textContent=name(r.id)+' · '+clock(r.hour)}
function sites(){const host=$('#sites');host.replaceChildren();for(const r of data.images.filter(r=>r.kind==='site'&&r.hour===Number($('#siteHour').value))){const f=document.createElement('figure'),a=document.createElement('a'),im=document.createElement('img'),c=document.createElement('figcaption');a.href=r.path;im.src=r.path;im.alt=name(r.id)+' '+clock(r.hour);im.loading='lazy';a.append(im);c.textContent=name(r.id)+' · '+clock(r.hour);c.title=r.id;f.append(a,c);host.append(f)}}
for(const r of data.missing){const p=document.createElement('p');p.textContent=name(r.id)+'（'+r.id+'）：鏡位未通過戶外支撐／遮擋檢查，等待位置處理。';$('#missing').append(p)}if(!data.missing.length)$('#missing').textContent='沒有缺少的拍攝鏡位；畫面內容仍依驗收記錄。';$('#view').onchange=hero;$('#hour').oninput=hero;$('#siteHour').onchange=sites;hero();sites();</script></main></html>]=]
write('delivery-day-night.html',table.concat(html,'\n'));print(root..'delivery-day-night.html')
