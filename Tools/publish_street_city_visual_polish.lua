package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json')
local root='C:/portable/OpenKoikatsu/output/street-social-city-production/day-night-v1/'
local function read(p)local f=assert(io.open(root..p,'rb'));local t=f:read('*a');f:close();return json.decode(t)end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local install=read('visual_polish.json');local render=read('render-polish.json');local current=read('current-map.json');local audit=read('visual-polish-audit.json')
assert(install.status=='passed' and audit.status=='passed' and audit.map_sha256==current.map_sha256 and render.status=='passed' and render.set=='polish' and render.map_sha256==current.map_sha256)
local html={[=[<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>大學城｜暗底亮字與自然花樹</title><style>
*{box-sizing:border-box}body{margin:0;background:#0b1420;color:#e5e9ec;font:16px/1.65 system-ui,sans-serif}main{max-width:1500px;margin:auto;padding:32px}h1{font-size:28px;margin:0}p{max-width:950px;color:#b8c6d1}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(440px,1fr));gap:22px}figure{margin:0;background:#142232;border:1px solid #2d4254;border-radius:12px;overflow:hidden}img{width:100%;display:block}figcaption{padding:12px 18px}.meta{color:#94aabc;font-size:13px}a{color:#bcdcca}button{background:#28463f;color:#fff;border:1px solid #4b7f6c;padding:9px 18px;border-radius:6px;cursor:pointer;margin:0 8px 20px 0}.hide{display:none}@media(max-width:600px){main{padding:16px}.grid{grid-template-columns:1fr}}
</style><main><h1>大學城｜暗底亮字與自然花樹</h1>]=]}
html[#html+1]='<p>122棟建築招牌統一深色底板與暖白亮字，沿用三語文字和2.8cm浮雕。花樹改用開放葉叢與獨立花瓣，保留種植位置及碰撞。夜空獨立調暗，環境補光維持。</p>'
html[#html+1]='<p class="meta">以下為同一份主地圖的原生Unreal拍攝。此頁記錄招牌、花樹與夜空外觀；全城深度與獨立打包驗收仍另行記錄。</p>'
local game
for _,mode in ipairs({'package','editor'})do
 local path='runtime-'..mode..'-launch.json';local exists=io.open(root..path,'rb')
 if exists then exists:close();local candidate=read(path);if candidate.status=='passed' and candidate.map_sha256==current.map_sha256 then game=candidate;break end end
end
if game then
 local screenshot=assert(game.native_receipt:gsub('\\','/'):match('day%-night%-v1/(.*)')):gsub('%.json$','.png')
 html[#html+1]='<figure data-hour="21"><a href="'..esc(screenshot)..'"><img src="'..esc(screenshot)..'" alt="實際遊戲21點街景"></a><figcaption>實際遊戲 · 21:00<div class="meta">深藍夜空、暖光招牌與新花樹</div></figcaption></figure><p>遊戲程序已通過完整一天、暫停及保存重載檢查。移動路線抽查另存於同次遊戲驗收收據。</p>'
end
html[#html+1]='<button onclick="filter(0)">全部</button><button onclick="filter(21)">夜間</button><button onclick="filter(12)">日間</button><div class="grid">'
for _,r in ipairs(render.images) do
 local relative=assert(r.files.ldr.path:gsub('\\','/'):match('day%-night%-v1/(.*)'));local f=assert(io.open(root..relative,'rb'));f:close()
 html[#html+1]='<figure data-hour="'..r.hour..'"><a href="'..esc(relative)..'"><img loading="lazy" src="'..esc(relative)..'" alt="'..esc(r.name)..'"></a><figcaption>'..esc(r.name)..'<div class="meta">'..r.hour..':00 · 原生HDR/LDR成對拍攝</div></figcaption></figure>'
end
html[#html+1]='</div><p class="meta">主地圖 SHA256：'..esc(current.map_sha256)..'<br>新花樹元件：'..install.tree_components..'；實例：'..install.tree_instances..'。<br><a href="visual_polish.json">套用與保留檢查收據</a> · <a href="render-polish.json">拍攝收據</a></p></main><script>function filter(h){document.querySelectorAll("figure").forEach(e=>e.classList.toggle("hide",h&&Number(e.dataset.hour)!==h))}</script></html>'
local f=assert(io.open(root..'delivery-visual-polish.html','wb'));f:write(table.concat(html,'\n'));f:close();print(root..'delivery-visual-polish.html')
