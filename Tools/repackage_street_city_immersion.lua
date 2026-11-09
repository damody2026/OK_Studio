-- Fresh isolated staging with E engine; keep the accepted earlier package intact.
local f=assert(io.open('Tools/repackage_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
source=source:gsub('ground%-pbr%-v1','immersion-v1'):gsub('GroundPBRV1','ImmersionV1'):gsub('#assets>100','#assets>=9')
local first=assert(source:find("local audit=read(ground..'/audit.json')",1,true));local last=assert(source:find('local host=prev.host;',first,true))
source=source:sub(1,first-1)..[[local audit=read(ground..'/audit.json');local install=read(ground..'/install.json')
local captured_parent=false;local cf=io.open(ground..'/captures.json','rb')
if cf then local c=json.decode(cf:read('*a'));cf:close();captured_parent=c.package_id==prev.id and c.map_sha256==prev.map_sha256 and c.exit_code==0 end
local pf=io.open(ground..'/physics-launch-latest.json','rb');local physics_parent=false
if pf then local p=json.decode(pf:read('*a'));pf:close();physics_parent=p.status=='passed' and p.package_id==prev.id and p.map_sha256==prev.map_sha256 and p.immutable_stage_unchanged end
assert(audit.status=='passed' and audit.map_sha256==install.map_sha256 and (prev.map_sha256==install.before_map_sha256 or prev.map_sha256==install.map_sha256 or prev.map_sha256==install.parent_map_sha256 or captured_parent or physics_parent))
]]..source:sub(last)
source=source:gsub("before==read%(out%.%.'/current%-map.json'%).map_sha256","before==audit.map_sha256")
source=source:gsub('config_before==prev.source_config_sha256',"(config_before==prev.source_config_sha256 or config_before==read(ground..'/mirror-renderer-config.json').files[1].sha256)")
source=source:gsub("local target='E:/StreetSocialCityProduction/environment%-packages/'%.%.id","local target=ground..'/packages/'..id")
source=source:gsub("%[IO%.DriveInfo%]::new%('E'%)","[IO.DriveInfo]::new('C')")
-- A second copy of the same pak is unnecessary for every unattended checkpoint.
-- Keep all previous Stage/Archive folders; future packages get an independent Stage.
source=source:gsub(",'%-archive'",'')
local archive=",'-archivedirectory='..target..'/Archive'"
local archive_start=assert(source:find(archive,1,true));source=source:sub(1,archive_start-1)..source:sub(archive_start+#archive)
source=source:gsub('100GB','45GB')
source=source:gsub("local id=os.date",function()return [[local known={};for _,a in ipairs(assets)do known[a.file]=true end
local sports=read(ground..'/sports-finish-install.json');assert(sports.map_sha256==before and hash.sha256_file(sports.source_file)==sports.sha256)
local sportsfile='StreetSocialCity/Content/UniversityCity/RomancePBR/Materials/MI_SP_wall.uasset';assert(not known[sportsfile]);assets[#assets+1]={file=sportsfile,sha256=sports.sha256};known[sportsfile]=true
for _,r in ipairs(read(ground..'/preservation-after.json').components)do
 if r.actor:match('^G%d%d$') and r.mesh:find('/EnvironmentV1/DepthRepairs/',1,true)then
  local package=r.mesh:match('^(.-)%.');assert(package and package:sub(1,6)=='/Game/' and not package:find('..',1,true));local file='StreetSocialCity/Content/'..package:sub(7)..'.uasset'
  if not known[file]then assets[#assets+1]={file=file,sha256=hash.sha256_file(root..'/'..file)};known[file]=true end
 end
end
local id=os.date]]end,1)
source=source:gsub('Fresh cook after generated grass refinement, existing successful isolated E code host, new Stage/Archive; all ground asset hashes unchanged during cook','Immersion repair cook using isolated E engine host, new C Stage/Archive; map, configuration, prebuilt executable and all ImmersionV1 asset hashes remain unchanged throughout cook')
source=source:gsub('new C Stage/Archive','new independent C Stage; earlier archives retained')
if arg[1]=='full' or arg[1]=='stage-full' then
 source=source:gsub("local prev=read%(out%.%.'/package.json'%);", "local prev=read(out..'/package.json');if prev.exit_code~=0 then prev=read(ground..'/checkpoint-20261024-135124/package.json')end;",1)
 source=source:gsub(",'%-iterativecooking'",'')
 source=source:gsub('45GB','20GB')
 if arg[1]=='stage-full' then
  source=source:gsub("'%-cook'", "'-skipcook','-CookOutputDir=D:/StreetSocialCityProduction/immersion-full-stage-20261024-145412/Windows'",1)
 else
  source=source:gsub("'%-cook'", function()return "'-cook','-CookOutputDir=D:/StreetSocialCityProduction/immersion-full-cook-'..os.date('%Y%m%d-%H%M%S')..'/Windows'" end,1)
 end
 assert(not source:find("'-iterativecooking'",1,true),'Full cook must not retain incremental shader outputs')
end
assert(load(source,'immersion-repackage'))()
