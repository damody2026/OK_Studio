package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local ok=require('ok')
local root=ok.root:gsub('\\','/'):gsub('%s+$','');local out=root..'/output/street-social-city-production/motel-v1'
local function read(p)local f=assert(io.open(p,'rb'));local r=f:read('*a');f:close();return r end
local ready=j.decode(read(out..'/serve-ready.json'));assert(ready.status=='passed')
local launch=j.decode(read(out..'/serve-payload.json'));assert(ready.run_id==launch.run_id,'Wait for this exact native worker launch; stale ready receipts cannot authorize jobs')
local mode=assert(arg[1]);assert(mode:match('^[a-z_]+$'));local code=mode=='quit' and '' or dofile(assert(arg[2],'Pass Lua embedded native definitions'))
local id=os.date('%Y%m%d-%H%M%S')..'-'..mode;local request=out..'/jobs/'..id..'.request.json';local result=out..'/jobs/'..id..'.result.json'
local q={id=id,['function']=mode=='quit' and 'quit' or 'motel_'..mode,code=code,code_sha256=h.sha256(code),expected_map_sha256=h.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap')}
local f=assert(io.open(request,'wb'));f:write(j.encode(q));f:close();print('Queued '..id)
-- OK_JOB_MINUTES: longer wait for big installs (first import of many Tripo meshes); default 30
local minutes=tonumber(os.getenv('OK_JOB_MINUTES') or '30')
local cmd="$limit=(Get-Date).AddMinutes("..minutes..");while(!(Test-Path -LiteralPath '"..result.."')){if((Get-Date) -gt $limit){throw 'Native job timed out'};Start-Sleep -Seconds 1}"
assert(ok.proc.run({'powershell.exe','-NoProfile','-Command',cmd},{hide=true,timeout=minutes*60+20}).code==0)
local r=j.decode(read(result));assert(r.status=='passed',r.error or 'Native job failed');print('Completed '..result)
