-- Syntax-only check before queueing native editor work; no map or asset mutation.
package.path='Tools/lua/?.lua;'..package.path
local j=require('ok.json')
local code=assert(dofile('Tools/street_city_immersion_payload.lua'):match('^(.-)\ndef work%(%)'))..'\n'..dofile('Tools/street_city_immersion_structures_payload.lua')
if arg[1]then local f=assert(io.open(arg[1],'rb'));local s=f:read('*a');f:close();code=assert(s:match('local code=%[====%[(.-)%]====%]'),'Expected embedded code block');assert(loadfile(arg[1]))end
local p=assert(io.popen('python -','w'));assert(p:write('import ast\nast.parse('..j.encode(code)..')\nprint("Native payload syntax passed")\n'));assert(p:close())
