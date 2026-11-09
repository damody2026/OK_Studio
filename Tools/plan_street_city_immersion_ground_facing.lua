-- Existing within-mesh facing partitioner handles opposite-sided terrain sheets.
package.path='Tools/lua/?.lua;'..package.path
local ok=require('ok');local j=require('ok.json');local h=require('ok.hash')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1'
local function read(p)local f=assert(io.open(p,'rb'));local d=j.decode(f:read('*a'));f:close();return d end
local function write(p,d)local f=assert(io.open(p,'wb'));f:write(j.encode(d));f:close()end
local source=read(out..'/depth-export.json');source.folder=source.folder:gsub('\\','/');local map=h.sha256_file(root..'/StreetSocialCity/Content/UniversityCity/Maps/UniversityCity.umap');assert(source.map_sha256==map and source.folder:find(out,1,true)==1)
assert(h.sha256_file(source.folder..'/scene.json')==source.metadata_sha256)
write(out..'/ground-facing-selection.json',{actors={{label='G06',building_floor=true,actual_usage='terrain_not_building'},{label='G07',building_floor=true,actual_usage='terrain_not_building'}},scope='The legacy CLI building_floor key is only an eligibility switch here. Exactly two GNN terrain meshes are selected; no real building floor is modified.'})
local path=out..'/ground-facing-plan.json';local r=ok.proc.run({'Tools/resort-props/target/release/city-asymmetric-sheets.exe',source.folder,out..'/ground-facing-selection.json',path},{hide=true,stdout_file=out..'/ground-facing-planner.log',stderr_file=out..'/ground-facing-planner.stderr',timeout=1800});assert(r.code==0,'Within-mesh terrain facing planner failed')
local plan=read(path);assert(plan.status=='prepared_requires_native_validation' and plan.scene_sha256==source.metadata_sha256 and #plan.blocked==0 and plan.modified_source_triangles>0)
for _,m in ipairs(plan.meshes)do assert(#m.component_keys==1 and (m.component_keys[1]=='G06::StaticMeshComponent0' or m.component_keys[1]=='G07::StaticMeshComponent0'))end
write(out..'/ground-facing-source.json',{status='prepared_requires_native_area_shader_collision_validation',map_sha256=map,folder=source.folder,metadata_sha256=source.metadata_sha256,plan_sha256=h.sha256_file(path),scope='Covered portions of opposite-winding two-sided sheets become front-only. UVs, positions and source materials are interpolated without moving terrain; untouched uncovered pieces remain two-sided. Original collision must be preserved.'});print('Within-mesh terrain plan: '..plan.modified_source_triangles..' triangles across '..#plan.meshes..' meshes')
