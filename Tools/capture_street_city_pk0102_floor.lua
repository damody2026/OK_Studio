package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash')
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local env='output/street-social-city-production/day-night-v1';local out='output/street-social-city-production/pk0102-floor-v1'
local package=read(env..'/package.json');local runtime=read(env..'/runtime-package-launch.json');local install=read(out..'/install.json')
local sha=hash.sha256_file(runtime.executable);assert(runtime.status=='passed' and sha==hash.sha256_file(package.target..'/Stage/Windows/StreetSocialCity/Binaries/Win64/StreetSocialCity.exe'))
local f=assert(io.open(out..'/reused-runtime.json','wb'));f:write(json.encode({status='passed',map_sha256=install.map_sha256,source_receipt=runtime.native_receipt,source_map_sha256=runtime.map_sha256,executable_sha256=sha,scope='Identical executable functional tests reused; one-platform material-only map revision receives fresh D3D12 captures.'}));f:close()
f=assert(io.open('Tools/capture_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v1','pk0102-floor-v1')
local needle='runtime.map_sha256==installed.map_sha256 and ';local n;source,n=source:gsub(needle:gsub('(%W)','%%%1'),'');assert(n==1)
local start=assert(source:find("local cameras=read(envout..'/cameras.json')",1,true));local stop=assert(source:find("local id=os.date",start,true))
source=source:sub(1,start-1)..[[local cameras=read(envout..'/cameras.json');assert(cameras.map_sha256==installed.before_map_sha256)
local previous=read(root..'/output/street-social-city-production/white-paths-v1/captures.json');local original
for _,v in ipairs(previous.images)do if v.id=='PK-0102-day'then original=v end end
assert(original)
local views={}
for _,hour in ipairs({12,21})do views[#views+1]={id=hour==12 and 'PK-0102-day' or 'PK-0102-night',site='PK-0102',eye=original.eye,target=original.target,fov=original.fov,hour=hour}end
views[#views+1]={id='PK-0102-floor-close',site='PK-0102',eye={79600,56500,2180},target={80000,57000,2012},fov=75,hour=12}
]]..source:sub(stop)
local scope='Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.'
source,n=source:gsub(scope:gsub('(%W)','%%%1'),'Actual staged D3D12 Game: three targeted PK-0102 day, night and close floor views; native reflected clock checked. No Editor/Python.');assert(n==1)
needle="write(macro..'/begin.txt',defer(30,'exec '..macro..'/view-1.txt')..'\\n')"
local replacement="write(macro..'/begin.txt',defer(20,'getall StaticMeshComponent OverrideMaterials')..'\\n'..defer(30,'exec '..macro..'/view-1.txt')..'\\n')"
source,n=source:gsub(needle:gsub('(%W)','%%%1'),function()return replacement end);assert(n==1)
assert(load(source,'pk0102-rendered-captures'))()
local captured=read(out..'/captures.json');f=assert(io.open(captured.native_log,'rb'));local log=f:read('*a');f:close()
local marker='PersistentLevel.StaticMeshActor_473.StaticMeshComponent0.OverrideMaterials =';local at=assert(log:find(marker,1,true),'Visible platform runtime binding header missing')
local tail=log:sub(at);local lines={};for line in tail:gmatch('[^\r\n]+')do lines[#lines+1]=line;if #lines==18 then break end end
assert(#lines==18)
for i=0,16 do assert(lines[i+2]:find(i..': ',1,true) and lines[i+2]:find(install.target_change.after,1,true),'Runtime platform alias differs: '..i)end
f=assert(io.open(out..'/runtime-material-bindings.json','wb'));f:write(json.encode({status='passed',package_id=package.id,map_sha256=install.map_sha256,actor='StaticMeshActor_473',editor_label=install.target_change.actor,material=install.target_change.after,slots=17,native_log=captured.native_log}));f:close()
