package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local o='C:/portable/OpenKoikatsu/output/street-social-city-production/motel-decor-tripo-v1'
local f=assert(io.open(o..'/submissions.json','rb'));local p=j.decode(f:read('*a'));f:close();local rows={}
for i,r in ipairs(p.assets)do
 local name='motel-decor-'..string.format('%03d',i)..'.glb';local src='C:/Users/Damody/Downloads/'..name;local input=io.open(src,'rb')
 if input then
  local head=assert(input:read(20));local n=input:seek('end');assert(head:sub(1,4)=='glTF' and string.unpack('<I4',head,5)==2 and string.unpack('<I4',head,9)==n,'Invalid/incomplete GLB '..name);local chunk=string.unpack('<I4',head,13);assert(head:sub(17,20)=='JSON');input:seek('set',20);local content=j.decode(input:read(chunk));assert(content.meshes and #content.meshes>0 and content.materials and #content.materials>0 and content.images and #content.images>0,'Missing mesh/material/texture '..name)
  local source_sha=h.sha256_file(src);local dst=o..'/downloads/'..name;local existing=io.open(dst,'rb')
  if existing then existing:close();assert(h.sha256_file(dst)==source_sha,'Refuse to overwrite a different collected model') else local output=assert(io.open(dst,'wb'));input:seek('set',0);while true do local bytes=input:read(1024*1024);if not bytes then break end;assert(output:write(bytes))end;output:close();assert(h.sha256_file(dst)==source_sha)end
  input:close();rows[#rows+1]={index=i,id=r.id,room_id=r.room_id,tripo_model_id=r.tripo_model_id,path=dst,bytes=n,sha256=source_sha,materials=#content.materials,images=#content.images,status='downloaded_binary_verified_requires_preparation_and_native_review'}
 end
end
f=assert(io.open(o..'/downloads.json','wb'));f:write(j.encode({status=#rows==122 and 'all_downloaded' or 'partial',required=122,downloaded=#rows,assets=rows}));f:close();print('Verified and collected '..#rows..'/122 actual exported GLB files')
