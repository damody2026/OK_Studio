local f=assert(io.open('Tools/finish_street_city_immersion_players.lua','rb'));local s=f:read('*a');f:close()
s=s:gsub('outdoor%-players/','outdoor-players-v2/'):gsub('detail/captures.json','repair/captures.json'):gsub('#base.images==22','#base.images==44'):gsub('detail22','repair44')
assert(load(s,'finish-repair-player-views'))()
