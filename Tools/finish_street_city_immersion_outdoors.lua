-- Verify native screenshot provenance before extending the staged receipt.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash');local ok=require('ok');local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/immersion-v1'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(json.encode(d));f:close()end
local r=read(out..'/extra-outdoors/captures-running.json');local base=read(out..'/captures.json');assert(base.status=='captured_requires_visual_review' and base.exit_code==0 and base.map_sha256==r.map_sha256 and base.native_log==r.source_folder..'/native-game.log' and #base.images==107)
assert(hash.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==base.map_sha256)
local f=assert(io.open(base.native_log,'rb'));local text=f:read('*a');f:close();local last_date;local saved={}
for line in text:gmatch('[^\r\n]+')do local date=line:match('LocalDateTime = (%d%d%d%d%.%d%d%.%d%d%-%d%d%.%d%d%.%d%d)');if date then last_date=date end;local path=line:match('High resolution screenshot saved as (.+%.png)');if path then saved[path:gsub('\\','/')]=last_date end end
for _,v in ipairs(r.views)do assert(saved[v.path]==v.date,'Missing native exact-clock screenshot '..v.id);local f=assert(io.open(v.path,'rb'));assert(f:seek('end')>5000);f:close();v.sha256=hash.sha256_file(v.path)end
assert(#r.views==12);write(out..'/captures-checkpoint-107-before-extra-outdoors.json',base)
write(out..'/extra-outdoors/captures.json',{status='captured_requires_visual_review',package_id=base.package_id,engine=base.engine,executable=base.executable,map_sha256=base.map_sha256,exit_code=base.exit_code,native_log=base.native_log,images=r.views,scope='Same actual staged Game process: six previously omitted outdoor roots, day/night; five elevated diagnostic overviews and one player-height waterfront approach.'})
for _,v in ipairs(r.views)do base.images[#base.images+1]=v end;assert(#base.images==119);base.scope=base.scope..' Twelve further native day/night views cover the six previously omitted outdoor roots; five use explicitly elevated diagnostic cameras.';write(out..'/captures.json',base);print('Verified 119 actual staged Game images, including all twenty outdoor roots')
