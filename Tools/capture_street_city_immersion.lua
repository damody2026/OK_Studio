-- Fresh player-height campus inspection in the existing accepted staged Game.
local f=assert(io.open('Tools/capture_street_city_ground_pbr.lua','rb'));local source=f:read('*a');f:close()
local first=assert(source:find('local repair=arg[1]',1,true));local last=assert(source:find('local id=os.date',first,true))
source=source:sub(1,first-1)..[[local repair=false
local traffic=root..'/output/street-social-city-production/traffic-v1'
local baseline=read(traffic..'/captures.json');local package=read(envout..'/package.json')
local map=root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap';local mapsha=hash.sha256_file(map)
assert(package.map_sha256==mapsha and package.id==baseline.package_id and baseline.map_sha256==mapsha,'Baseline capture must use the unchanged accepted package/map')
local installed={map_sha256=mapsha};local cameras={map_sha256=mapsha};local views={}
local thresholds=read(traffic..'/campus-audit.json').thresholds;local entries={};local order={}
for _,r in ipairs(thresholds)do if not entries[r.entry]then entries[r.entry]={};order[#order+1]=r.entry end;local g=entries[r.entry];g[#g+1]=r end
for _,entry in ipairs(order)do
 local samples=entries[entry];local a,b=samples[1].ground,samples[#samples].ground;local dx,dy=b[1]-a[1],b[2]-a[2];local length=math.sqrt(dx*dx+dy*dy);assert(length>100)
 views[#views+1]={id='entry-'..entry,eye={b[1]+dx/length*650,b[2]+dy/length*650,b[3]+165},target={a[1],a[2],a[3]+180},fov=80,hour=12}
end
for _,r in ipairs(baseline.images)do
 if r.eye[3]<2000 and (r.id:match('^PK%-') or r.id:match('^gate%-') or r.id:match('^Bridge_') or r.id:match('^J%d+%-street') or r.id:match('^riverbank'))then
  views[#views+1]={id=r.id,site=r.site,eye=r.eye,target=r.target,fov=r.fov,hour=r.hour}
 end
end
assert(#views>=60)
]]..source:sub(last)
source=source:gsub('ground%-pbr%-v1','immersion-v1/baseline')
source=source:gsub("assert%(text:find%('BugItGo to:'", "assert(not text:find('missing usage flag InstancedStaticMeshes',1,true),'Instanced material fallback');assert(text:find('BugItGo to:'",1)
source=source:gsub('Actual staged D3D12 Game, all twenty outdoor sites, four city ground overviews, three soil views and targeted night comparisons; native reflected clock checked. No Editor/Python.','Actual staged D3D12 Game baseline immersion survey: all 34 campus entrances from player height and existing outdoor, gate, bridge and traffic pedestrian views.')
assert(os.execute('if not exist "output/street-social-city-production/immersion-v1/baseline" mkdir "output/street-social-city-production/immersion-v1/baseline"'))
assert(load(source,'immersion-player-height-capture'))()
