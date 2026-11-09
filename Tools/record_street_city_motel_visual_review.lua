-- Run only after actually inspecting the specified current native contact sheets.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local o='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local function read(p)local f=assert(io.open(p,'rb'));local r=j.decode(f:read('*a'));f:close();return r end
local sheets=read(o..'/contact-sheets.json');local p=read(o..'/package.json');assert(sheets.map_sha256==p.map_sha256 and sheets.package_id==p.id);local path=o..'/visual-review.json';local f=io.open(path,'rb');local r=f and j.decode(f:read('*a'))or{status='in_progress',map_sha256=p.map_sha256,package_id=p.id,reviewed_sheets={}};if f then f:close()end;assert(r.map_sha256==p.map_sha256 and r.package_id==p.id)
local lookup={};for _,s in ipairs(sheets.sheets)do lookup[s.id]=s end
for id in assert(arg[1],'Pass comma-separated sheet IDs actually inspected'):gmatch('[^,]+')do local s=assert(lookup[id],id);assert(h.sha256_file(s.path)==s.sha256);r.reviewed_sheets[id]={sha256=s.sha256,image_ids=s.image_ids,notes=arg[2]or'Inspected native pixels for visible intersections,missing geometry,texture fallback,sign/mirror appearance and lighting.'}end
local complete=true;local images={};local count=0
for _,s in ipairs(sheets.sheets)do local a=r.reviewed_sheets[s.id];if not a or a.sha256~=s.sha256 then complete=false else count=count+1;for _,id in ipairs(s.image_ids)do images[id]=true end end end
local n=0;for _ in pairs(images)do n=n+1 end;r.reviewed_sheet_count=count;r.reviewed_image_count=n;r.all_current_sheets_reviewed=complete;r.status=complete and 'passed_current_sheets' or 'in_progress';r.reviewer='Agent visual inspection of the actual specified native screenshot sheets';local f=assert(io.open(path,'wb'));f:write(j.encode(r));f:close();print('Recorded '..count..' inspected sheets covering '..n..' native images;all current sheets='..tostring(complete))
