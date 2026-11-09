-- Extend only the current 107-view staged Game with the six omitted roots.
local f=assert(io.open('Tools/attach_street_city_immersion_interiors.lua','rb'));local s=f:read('*a');f:close()
s=s:gsub("/preview/captures%-running.json","/captures-running.json"):gsub('/interior%-cameras.json','/extra-outdoor-cameras.json'):gsub('expected_images==72','expected_images==107'):gsub('view%-72.txt','view-107.txt')
s=s:gsub('/interiors/','/extra-outdoors/'):gsub('/interiors/runtime%-views','/extra-outdoors/runtime-views'):gsub('before%-interiors','before-extra-outdoors')
local first=assert(s:find('for _,c in ipairs(cameras.rows)',1,true));local last=assert(s:find('for i,v in ipairs(views)',first,true))
s=s:sub(1,first-1)..[[for _,c in ipairs(cameras.rows)do for _,h in ipairs({12,21})do views[#views+1]={id=c.id..'-overview-'..h,site=c.id,eye=c.eye,target=c.target,fov=c.fov,hour=h,camera_kind=c.camera_kind}end end;assert(#views==12)
]]..s:sub(last)
s=s:gsub('expected_images=68','expected_images=12'):gsub('Attached 68 day/night room views to native source Game:','Attached 12 day/night outdoor overview views to the staged Game:')
assert(load(s,'attach-staged-outdoor-inspection'))()
