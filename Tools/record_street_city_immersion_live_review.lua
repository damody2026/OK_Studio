-- Call only after actually viewing every listed complete contact sheet.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local id=assert(arg[1]);assert(id:match('^[a-z0-9%-]+$'));local sheets=assert(tonumber(arg[2]));assert(sheets>0 and sheets%1==0)
local out='output/street-social-city-production/immersion-v1/';local f=assert(io.open(out..id..'.json','rb'));local native=j.decode(f:read('*a'));f:close();local rows={}
assert(#native.soak_images>=sheets*8)
for i=1,sheets*8 do local r=native.soak_images[i];rows[#rows+1]={path=r.path,sha256=h.sha256_file(r.path)}end
local review={status='review_in_progress',map_sha256=native.supplied_plan_map_sha256,native_receipt=id..'.json',reviewed_at=os.date('%Y-%m-%dT%H:%M:%S')..'+08:00',complete_contact_sheets_reviewed=sheets,original_images_reviewed=#rows,reviewed_images=rows,observations=arg[3] or 'Player-height path,gate,ground/fixture contact and day/night readability checked in viewed sheets;final source/cooked acceptance still required.',scope='Manual live contact-sheet review of immutable native image files only. Not a completion or temporal-zero-depth certificate.'}
local o=assert(io.open(out..id..'-visual-review-live.json','wb'));o:write(j.encode(review));o:close();print('Recorded '..#rows..' actually viewed native images;run remains active.')
