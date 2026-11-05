-- Extend this source preview to inspect every outdoor site from player height.
local f=assert(io.open('Tools/attach_street_city_immersion_interiors.lua','rb'));local s=f:read('*a');f:close()
s=s:gsub('/preview/captures%-running.json','/detail/captures-running.json'):gsub('/interior%-cameras.json','/outdoor-player-cameras.json'):gsub('expected_images==72','expected_images==22'):gsub('view%-72.txt','view-22.txt')
s=s:gsub('/interiors/','/outdoor-players/'):gsub('before%-interiors','before-outdoor-players'):gsub('#views==68','#views==40'):gsub('expected_images=68','expected_images=40'):gsub('Attached 68 day/night room views to native source Game:','Attached 40 player-height outdoor views to native source Game:')
assert(load(s,'attach-all-outdoor-player-views'))()
