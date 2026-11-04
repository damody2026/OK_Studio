-- Mandatory instant-meshes-rs pass (E:/Paper/instant-meshes-rs) for the prepared motel Tripo ornaments before Unreal import.
-- Usage: lua remesh_street_city_motel_tripo_decor.lua [k/n] [id]  -- k/n shards the work; run once without args to merge remeshed.json.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
-- OK_TRIPO_SET=<folder name under street-social-city-production> remeshes another prepared set (e.g. motel-furniture-tripo-v2).
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/'..(os.getenv('OK_TRIPO_SET') or 'motel-decor-tripo-v1')
local blender='C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return j.decode(s)end
local function write(p,v)local f=assert(io.open(p,'wb'));f:write(j.encode(v));f:close()end
local shard=arg[1];local only=arg[2];local sk,sn=0,1
if shard then sk,sn=shard:match('^(%d+)/(%d+)$');assert(sk,'Shard must be k/n');sk,sn=tonumber(sk),tonumber(sn)end
local prepared={}
for _,p in ipairs({o..'/prepared.json'})do local r=read(p);if r then for _,a in ipairs(r.assets)do prepared[a.id]=a end end end
for i=0,9 do local r=read(o..'/prepared-shard'..i..'.json');if r then for _,a in ipairs(r.assets)do prepared[a.id]=a end end end
-- Each rung: instant-meshes-rs remesh, then the script's own geometric validation (closed, manifold, distance tolerance, triangle cap).
local rungs={
 {tag='solid',args='--triangle-cap 14000 --tolerance 0.01 --quad-mode --project-source --dense-pass 3 --repair-solid 0.0015 --smooth-shading',
  scope='instant-meshes-rs quad remesh, 1.5mm voxel topology repair, budget LOD, projected to the prepared Tripo surface; UVs transferred from nearest source triangle'},
 -- (An earlier 'solid-fine' rung, 1mm voxel / 20000 / 15mm, produced some accepted receipts; it is superseded by the graft rungs.)
 {tag='graft',args='--triangle-cap 24000 --tolerance 0.006 --quad-mode --project-source --dense-pass 3 --repair-solid 0.0015 --smooth-shading --graft-thin-features',
  scope='instant-meshes-rs quad remesh, 1.5mm voxel topology repair, budget LOD; source triangles of sub-voxel features (cords, twigs, wires) the remesh still missed are spliced back with one overlapping ring; UVs from nearest source triangle'},
 {tag='graft-fine',args='--triangle-cap 30000 --tolerance 0.008 --quad-mode --project-source --dense-pass 3 --repair-solid 0.001 --smooth-shading --graft-thin-features',
  scope='As graft with 1mm voxel repair and a higher budget'},
 {tag='graft-wide',args='--triangle-cap 30000 --tolerance 0.006 --quad-mode --project-source --dense-pass 3 --repair-solid 0.0015 --smooth-shading --graft-thin-features',
  scope='As graft with a 30000 triangle budget for ornaments with many sub-voxel features'},
 -- Furniture-scale models (sofas 2+ m, motel-furniture-tripo-v2) pass the geometry checks at graft-fine but need ~31-38k
 -- triangles; the ornament budgets above reject them on triangle count alone.
 {tag='graft-xl',args='--triangle-cap 40000 --tolerance 0.008 --quad-mode --project-source --dense-pass 3 --repair-solid 0.001 --smooth-shading --graft-thin-features',
  scope='As graft-fine with a 40000 triangle budget for furniture-scale models'},
 {tag='graft-xl-wide',args='--triangle-cap 40000 --tolerance 0.010 --quad-mode --project-source --dense-pass 3 --repair-solid 0.0015 --smooth-shading --graft-thin-features',
  scope='As graft-xl with 1.5mm voxel repair and a 10mm distance bound'},
 -- recover keeps the prepared connectivity; furniture is prepared at <=35k triangles, so its budget has to cover that.
 {tag='recover-xl',args='--triangle-cap 40000 --tolerance 0.004 --quad-mode --project-source --dense-pass 3 --recover-source-topology --smooth-shading',
  scope='As recover with a 40000 triangle budget (furniture prepared at <=35k triangles)'},
 {tag='recover',args='--triangle-cap 30000 --tolerance 0.004 --quad-mode --project-source --dense-pass 3 --recover-source-topology --smooth-shading',
  scope='Fallback used by earlier destination imports: prepared Tripo connectivity with mandatory instant-meshes-rs field sampling, 4mm bound'}}
-- OK_REMESH_RUNGS=tag,tag,...: try only these rungs in this order (furniture sets start at graft-xl).
if os.getenv('OK_REMESH_RUNGS') then local by={};for _,r in ipairs(rungs)do by[r.tag]=r end;local pick={}
 for t in os.getenv('OK_REMESH_RUNGS'):gmatch('[^,]+')do pick[#pick+1]=assert(by[t],'Unknown rung '..t)end;rungs=pick end
local rows={}
local ids={};for id in pairs(prepared)do ids[#ids+1]=id end;table.sort(ids,function(a,b)return prepared[a].index<prepared[b].index end)
if shard or only then
 for _,id in ipairs(ids)do local a=prepared[id]
  if (not only or only==id) and a.index%sn==sk then
   local folder=o..'/remesh/'..id;assert(os.execute('if not exist "'..folder:gsub('/','\\')..'" mkdir "'..folder:gsub('/','\\')..'"'))
   local done=read(folder..'/receipt.json')
   if done and done.status=='passed' and done.prepared_sha256==a.sha256 and done.rung~='recover' then rows[#rows+1]=done else
    local receipt
    for _,r in ipairs(rungs)do
     local out=folder..'/'..r.tag
     local cmd='""'..blender..'" --background --factory-startup --threads 4 --python Tools/run_street_city_blender_task.py -- --script Tools/remesh_street_city_asset.py --status-file "'..out..'-status.json" -- --source "'..a.path..'" --output "'..out..'" --threads 4 '..r.args..' > "'..out..'.log" 2>&1"'
     -- Reuse a finished rung for the same prepared mesh and budget instead of solving it again.
     local report=read(out..'/remesh-report.json')
     -- a report whose tool run crashed is not a result: always solve it again (the tool/wrapper may have been fixed)
     for _,rec in ipairs(report and report.records or {})do if rec.status=='tool_failed' then report=nil;break end end
     if not(report and report.source_sha256==a.sha256 and report.triangle_cap==tonumber(r.args:match('%-%-triangle%-cap (%d+)')))then report=os.execute(cmd) and read(out..'/remesh-report.json')end
     if report and report.status=='passed' then
      receipt={status='passed',id=id,room_id=a.room_id,slot=a.slot,index=a.index,tripo_model_id=a.tripo_model_id,prepared=a.path,prepared_sha256=a.sha256,
       path=out..'/remeshed-candidate.glb',sha256=h.sha256_file(out..'/remeshed-candidate.glb'),triangles=report.triangles,prepared_triangles=a.triangles,
       rung=r.tag,tool=report.tool,tool_sha256=report.tool_sha256,tolerance_m=report.tolerance_m,records=report.records,scope=r.scope}
      break
     end
    end
    receipt=receipt or {status='failed',id=id,index=a.index,prepared=a.path,prepared_sha256=a.sha256}
    write(folder..'/receipt.json',receipt);rows[#rows+1]=receipt;print(id..' '..receipt.status..' '..(receipt.rung or '')..' '..(receipt.triangles or ''))
   end
  end
 end
end
-- Merge all per-asset receipts.
if not shard and not only then
 local all={};local passed=0
 for _,id in ipairs(ids)do local r=read(o..'/remesh/'..id..'/receipt.json');if r then all[#all+1]=r;if r.status=='passed' then passed=passed+1 end end end
 write(o..'/remeshed.json',{status=passed==#ids and 'remeshed_requires_native_import' or 'partial',required=#ids,completed=passed,assets=all,
  tool='E:/Paper/instant-meshes-rs/target/release/instant-meshes.exe via Tools/remesh_street_city_asset.py'})
 print('Remeshed '..passed..'/'..#ids)
end
