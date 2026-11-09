-- Collect the 50 motel-furniture Tripo exports (motel-furniture-tripo-v2) from Downloads, whatever their file names.
-- Batch Export files: "<project name, + for spaces> 3d model[ (n)].glb", no model id inside -> matched by model-ids.json
-- names; names used by several items are resolved by the recorded duplicate_sha256 (chosen by basecolor texture).
-- Single Export files: material tripo_material_<operator_id> -> operator_ids. Batch files win when both exist.
-- Verifies glTF2 header/length, mesh/material/image presence, copies to downloads/motel-furniture-v2-NNN.glb (SHA checked).
-- Usage: lua Tools/collect_street_city_motel_furniture_tripo.lua
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json');local h=require('ok.hash');local lfs=require('lfs')
local o='C:/portable/OpenKoikatsu/output/street-social-city-production/'..(os.getenv('OK_TRIPO_SET') or 'motel-furniture-tripo-v2');local src='C:/Users/Damody/Downloads'
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local ids=j.decode(read(o..'/model-ids.json'))
local byop,byname={},{};for i,v in ipairs(ids.operator_ids)do byop[v]=i end
for i,n in ipairs(ids.names)do byname[n]=byname[n] or {};table.insert(byname[n],i)end
lfs.mkdir(o..'/downloads')
local pick={}  -- index -> {path,kind,sha,...}
-- OK_TRIPO_SINCE=<unix time>: only files downloaded after it (another set's batch exports may share project names)
local since=tonumber(os.getenv('OK_TRIPO_SINCE') or '0')
for name in lfs.dir(src)do if name:lower():match('%.glb$') and not name:match('^sample%-furniture') and (lfs.attributes(src..'/'..name,'modification') or 0)>=since then
 local path=src..'/'..name;local f=assert(io.open(path,'rb'));local head=f:read(20)
 if head and #head==20 and head:sub(1,4)=='glTF' then
  local n=f:seek('end');local chunk=string.unpack('<I4',head,13);f:seek('set',20);local js=f:read(chunk);f:close()
  if string.unpack('<I4',head,5)==2 and string.unpack('<I4',head,9)==n then
   local i,kind
   -- names list holds either the full project name (v3+) or the name without its " 3d model" suffix (v2)
   local full=name:gsub(' %(%d+%)%.glb$',''):gsub('%.glb$',''):gsub('%+',' ')
   local base=name:find('+',1,true) and (byname[full] and full or full:match('^(.-) 3d model$'))
   if base then
    local cand=byname[base]
    if cand and #cand==1 then i=cand[1] elseif cand then local sha=h.sha256_file(path);i=ids.duplicate_sha256[sha];assert(i,'Unresolved same-name batch export '..name..' '..sha) end
    kind='batch'
   end
   if not i then local op=js:match('tripo_material_(%x+%-%x+%-%x+%-%x+%-%x+)');i=op and byop[op];kind='single' end
   if i and (not pick[i] or (pick[i].kind=='single' and kind=='batch')) then
    local c=j.decode(js);assert(c.meshes and #c.meshes>0 and c.materials and #c.materials>0 and c.images and #c.images>0,'Missing mesh/material/texture '..name)
    pick[i]={path=path,kind=kind,bytes=n,materials=#c.materials,images=#c.images,meshopt=js:find('EXT_meshopt_compression',1,true)~=nil}
   end
  end
 else f:close() end
end end
-- Re-exporting one Tripo model gives different bytes every time; the same model keeps its basecolor image and vertex count.
local function model_key(path)
 local s=read(path);local jl=string.unpack('<I4',s,13);local js=j.decode(s:sub(21,20+jl));local bin=21+jl+8
 local ti=js.materials[1].pbrMetallicRoughness.baseColorTexture.index;local bv=js.bufferViews[js.images[js.textures[ti+1].source+1].bufferView+1]
 return h.sha256(s:sub(bin+(bv.byteOffset or 0),bin+(bv.byteOffset or 0)+bv.byteLength-1))..':'..js.accessors[js.meshes[1].primitives[1].attributes.POSITION+1].count
end
local rows,missing={},{}
for i=1,#ids.operator_ids do local p=pick[i]
 if not p then missing[#missing+1]=i else
  local dst=o..string.format('/downloads/motel-furniture-v2-%03d.glb',i);local sha=h.sha256_file(p.path)
  local e=io.open(dst,'rb')
  if e then e:close();local old=h.sha256_file(dst)
   -- keep the collected copy of a re-export (prepared/remeshed results depend on it); refuse a different model
   if old~=sha then assert(model_key(dst)==model_key(p.path),'Refuse to overwrite a different collected model '..dst);sha=old end
  else local w=assert(io.open(dst,'wb'));w:write(read(p.path));w:close();assert(h.sha256_file(dst)==sha)end
  rows[#rows+1]={index=i,name=ids.names[i],tripo_model_id=ids.ids[i],export=p.kind,source=p.path,path=dst,bytes=p.bytes,sha256=sha,materials=p.materials,images=p.images,meshopt=p.meshopt}
 end
end
local w=assert(io.open(o..'/downloads.json','wb'));w:write(j.encode({status=#missing==0 and 'all_downloaded' or 'partial',required=#ids.operator_ids,downloaded=#rows,missing=missing,assets=rows}));w:close()
print('Collected '..#rows..'/'..#ids.operator_ids..(#missing>0 and (' missing '..table.concat(missing,',')) or ''))
