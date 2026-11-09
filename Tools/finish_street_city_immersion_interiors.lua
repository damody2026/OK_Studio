package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json');local hash=require('ok.hash');local ok=require('ok');local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/immersion-v1'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return json.decode(s)end
local r=read(out..'/interiors/captures-running.json');local source=read(out..'/preview/captures.json');assert(source.status=='captured_requires_visual_review' and source.exit_code==0 and source.map_sha256==r.map_sha256 and source.native_log==r.source_folder..'/native-game.log','Source Game must finish successfully first')
assert(hash.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')==r.map_sha256)
local f=assert(io.open(source.native_log,'rb'));local text=f:read('*a');f:close();local last_date;local saved={}
for line in text:gmatch('[^\r\n]+')do local date=line:match('LocalDateTime = (%d%d%d%d%.%d%d%.%d%d%-%d%d%.%d%d%.%d%d)');if date then last_date=date end;local path=line:match('High resolution screenshot saved as (.+%.png)');if path then saved[path:gsub('\\','/')]=last_date end end
for _,v in ipairs(r.views)do assert(saved[v.path]==v.date,'Missing exact reflected date for '..v.id);local f=assert(io.open(v.path,'rb'));assert(f:seek('end')>5000);f:close();v.sha256=hash.sha256_file(v.path)end
assert(#r.views==68);local receipt={status='captured_requires_visual_review',source_runtime='Uncooked UnrealEditor -game; final staged inspection remains separate',exit_code=source.exit_code,map_sha256=r.map_sha256,native_log=source.native_log,images=r.views,camera_plan_sha256=r.camera_plan_sha256}
local f=assert(io.open(out..'/interiors/captures.json','wb'));f:write(json.encode(receipt));f:close();print('Verified 68 native interior images at exact reflected day/night times')
