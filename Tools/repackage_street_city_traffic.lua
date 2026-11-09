package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash');local ok=require('ok');local taskroot=ok.root:gsub('\\','/'):gsub('%s+$','');local taskout=taskroot..'/output/street-social-city-production/traffic-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=json.decode(f:read('*a'));f:close();return d end
local usage=read(taskout..'/material-usage.json');local source_materials={}
for _,r in ipairs(usage.materials)do assert(r.instanced_usage and hash.sha256_file(r.source_file)==r.sha256);source_materials[#source_materials+1]={file=r.source_file,sha256=r.sha256}end
local f=assert(io.open('Tools/repackage_street_city_flat_campus.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('flat%-campus%-v1','traffic-v1')
source=source:gsub('local start=assert',"source=source:gsub('GroundPBRV1','TrafficV1'):gsub('#assets>100','#assets>80')\nlocal start=assert",1)
source=source:gsub('level city geometry and five named campus gates','realistic road markings, traffic signals and corrected road grade')
assert(load(source,'traffic-repackage'))()
for _,r in ipairs(source_materials)do assert(hash.sha256_file(r.file)==r.sha256,'Source material changed during cook: '..r.file)end
local package=read(taskroot..'/output/street-social-city-production/day-night-v1/package.json');assert(package.map_sha256==usage.map_sha256)
local out=assert(io.open(taskout..'/package-material-validation.json','wb'));out:write(json.encode({status='passed',package_id=package.id,map_sha256=package.map_sha256,materials=source_materials}));out:close()
