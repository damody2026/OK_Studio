-- Reauthor the remaining opaque-ball conifer family as open branch/leaf geometry.
package.path='Tools/lua/?.lua;'..package.path
local json=require('ok.json')
local root='C:/portable/OpenKoikatsu';local out=root..'/output/street-social-city-production/immersion-v1/evergreens'
local f=assert(io.open('Tools/build_street_city_tree_upgrade.lua','rb'));local s=f:read('*a');f:close()
local code=assert(s:match('local build=%[====%[(.-)%]====%]'))
local start=assert(code:find("(OUT/'textures').mkdir",1,true));local stop=assert(code:find('for idx,spec in enumerate(specs,1):',start,true))
code=code:sub(1,start-1)..[[import shutil
(OUT/'textures').mkdir(exist_ok=True)
for filename in ['bark-color.png','bark-normal.png','bark-roughness.png']:
 shutil.copy2(ROOT/'output/street-social-city-production/tree-upgrade-v2/textures'/filename,OUT/'textures'/filename)
]]..code:sub(stop)
-- Existing masked leaf atlas and bark PBR are reused without bitmap edits.
local specs={{'evergreen-a',2881,4.8,4.5,8,false,'conifer'},{'evergreen-b',2903,4.6,4.9,8,false,'conifer'},{'evergreen-c',2957,5.1,4.6,8,false,'conifer'}}
assert(os.execute('if not exist "'..out..'" mkdir "'..out..'"'))
local payload=out..'/build-payload.json';f=assert(io.open(payload,'wb'));f:write(json.encode({root=root,out=out,first=1,last=3,specs=specs,code=code}));f:close()
local expression="import json;TASK=json.load(open('"..payload.."',encoding='utf8'));exec(TASK['code'])"
assert(os.execute('""C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --factory-startup --threads 8 --python-expr "'..expression..'" > "'..out..'/build.log" 2>&1"'))
print('Three open-canopy evergreen variants authored; native import and Game review still required.')
