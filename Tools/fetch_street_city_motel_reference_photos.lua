-- Fetch the first official room photos listed in reference-catalog.json for side-by-side model review (local only).
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash')
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-v1'
local per=tonumber(arg[1]) or 3
local f=assert(io.open(o..'/reference-catalog.json','rb'));local c=j.decode(f:read('*a'));f:close()
local dir=o..'/reference-photos';os.execute('if not exist "'..dir:gsub('/','\\')..'" mkdir "'..dir:gsub('/','\\')..'"')
local rows={}
for _,r in ipairs(c.rooms)do
 for i,img in ipairs(r.images)do
  if i>per then break end
  local ext=img.url:match('%.(%a+)$') or 'jpg';local path=dir..'/'..r.id..'-'..i..'.'..ext:lower()
  local g=io.open(path,'rb');if g then g:close() else os.execute('curl.exe -s -L --max-time 60 -o "'..path..'" "'..img.url..'"')end
  g=io.open(path,'rb');local ok=g and g:seek('end')>2000;if g then g:close()end
  rows[#rows+1]={id=r.id,index=i,url=img.url,path=path,ok=ok,sha256=ok and h.sha256_file(path) or nil}
 end
end
local n=0;for _,r in ipairs(rows)do if r.ok then n=n+1 end end
f=assert(io.open(dir..'/manifest.json','wb'));f:write(j.encode({photos=rows,fetched=n}));f:close();print('Fetched '..n..'/'..#rows..' reference photos')
