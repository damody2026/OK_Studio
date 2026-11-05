-- Extend the44-view source repair pass with all20 outdoor player-height pairs.
local f=assert(io.open('Tools/attach_street_city_immersion_players.lua','rb'));local adapter=f:read('*a');f:close()
local g=assert(io.open('Tools/attach_street_city_immersion_interiors.lua','rb'));local source=g:read('*a');g:close()
source=source:gsub('/preview/captures%-running.json','/repair/captures-running.json'):gsub('/interior%-cameras.json','/outdoor-player-cameras.json'):gsub('expected_images==72','expected_images==44'):gsub('view%-72.txt','view-44.txt')
source=source:gsub('/interiors/','/outdoor-players-v2/'):gsub('before%-interiors','before-outdoor-players-v2'):gsub('#views==68','#views==40'):gsub('expected_images=68','expected_images=40'):gsub('Attached 68 day/night room views to native source Game:','Attached 40 current player-height outdoor views to repair Game:')
assert(load(source,'attach-repair-player-views'))()
