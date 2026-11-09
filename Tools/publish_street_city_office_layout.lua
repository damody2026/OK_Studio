package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local root='C:/portable/OpenKoikatsu/output/street-social-city-production/day-night-v1/'
local function read(n)local f=assert(io.open(root..n..'.json','rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function esc(s)return tostring(s):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;')end
local current=read('current-map');local render=read('render-office');local audit=read('office-layout-preservation');local layout=read('office-layout')
assert(render.status=='passed'and render.count==5 and render.map_sha256==current.map_sha256 and audit.status=='passed'and audit.map_sha256==current.map_sha256 and layout.status=='passed')
local images={};for _,r in ipairs(render.images)do images[r.name]=r end
local html={[=[<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>野餐草地｜辦公樓退縮修正</title><style>*{box-sizing:border-box}body{margin:0;background:#101b25;color:#edf2ee;font:16px/1.7 system-ui,sans-serif}main{max-width:1450px;margin:auto;padding:30px}h1{font-size:29px;margin:0}p{color:#bdcbd0;max-width:1050px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:22px}figure{margin:0 0 22px;background:#1a2b36;border:1px solid #3b5258;border-radius:10px;overflow:hidden}img{width:100%;display:block}figcaption{padding:12px 18px}a{color:#c6e3ca}details{font-size:13px;color:#9db1b9;margin:25px 0}@media(max-width:600px){main{padding:16px}.grid{grid-template-columns:1fr}}</style><main><h1>野餐草地｜辦公樓退縮修正</h1><p>PK-0110 保留原位。O03 整組退讓 5m，六層、24 間房的幾何與原碰撞保留；招牌、入口裝飾和燈具同步調整。補上約 1:13 緩坡及 2.425m 寬側步道，兩個站位與景點燈已回到實際草地。</p><p>下列是保存後主地圖的原生 Unreal 實拍。80 個景點鏡位已通過支撐、相機空間與視線檢查；全城接縫及打包驗收另外記錄。</p>]=]}
local order={{'office-setback-overview-12','鳥瞰：草地原位保留，辦公樓退到景點外'},{'picnic-cleared-12','12:00｜戶外草地與座位'},{'picnic-cleared-21','21:00｜草地上的景點燈'},{'picnic-cleared-2','02:00｜深夜環境可讀性'},{'picnic-access-ramp-12','公共緩坡與側步道｜2m 掃掠通過'}}
for _,q in ipairs(order)do
 local r=assert(images[q[1]]);local relative=assert(r.files.ldr.path:gsub('\\','/'):match('day%-night%-v1/(.*)'));local f=assert(io.open(root..relative,'rb'));assert(f:seek('end')>1000);f:close()
 html[#html+1]='<figure><a href="'..esc(relative)..'"><img src="'..esc(relative)..'" alt="'..esc(q[2])..'"></a><figcaption>'..esc(q[2])..'</figcaption></figure>'
end
html[#html+1]='<details><summary>原生檢查與來源</summary><p>O02 保留位置；它旁邊誤落樓板的舊站位已校正。O03 六層不縮放、不刪房間；共37個Actor與12個裝飾實例調整，原始模型資產不改。</p><p>主地圖 SHA256：'..esc(current.map_sha256)..'</p><a href="office-layout-review.json">主代理覆核</a> · <a href="office-layout-preservation.json">保存後保留檢查</a> · <a href="render-office.json">拍攝收據</a></details></main></html>'
local f=assert(io.open(root..'delivery-office-setback.html','wb'));f:write(table.concat(html,'\n'));f:close();print(root..'delivery-office-setback.html')
